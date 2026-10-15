# shellcheck shell=bash
# _m13-commun.sh — fonctions partagées par les scripts de panne du module 13 (M13-E19 à M13-E22).
#
# Sourcé par break-EXX.sh APRÈS lab/lib/pannes-lib.sh (wb_exec, wb_avert, WB_EX, WB_VAR…).
# Rappel : lab/bin/break tourne avec « set -euo pipefail » ; les fonctions d'annulation sont appelées
# hors de tout « if » : aucune commande ne doit y échouer sans « || true ».
#
# Principes (CONVENTIONS §8, PLAN §4.10 « Pannes du bloc C ») :
#   - E19 à E21 agissent sur les TÉMOINS (projets wb-sonde et wb-sonde-public, robots wb-sonde-*), sur
#     l'endpoint du cache dockerhub (URL seulement, valeur sauvegardée) et sur runner02 ; jamais sur les
#     images, robots ou politiques de medisphere ;
#   - E22 agit sur reg01 (Harbor de production) après avoir vérifié qu'une sauvegarde de moins de 26 h a
#     réussi (M13-E15) ; aucune donnée n'est effacée (fichier de remplissage, droits, configuration
#     générée mise de côté, jamais supprimée) ;
#   - jamais pbs01, pve01 ni une VM hors du pool lab ; l'annulation ne rétablit que ce qui porte encore
#     la marque de la panne.
#
# Identité Harbor des pannes : utilisateur local administrateur « wb-pannes » de reg01, fichier
# WB_HARBOR_PANNES_FILE (défaut ~/.config/workbook/harbor-pannes.env : HARBOR_USER=, HARBOR_PASSWORD=),
# créé par l'apprenant au début du palier 4 (en-tête de enonce/04-expert.md), supprimé en M13-E25.
#
# Témoins (créés par m13_temoins à la première injection de E19, E20 ou E21, jamais supprimés ici) :
#   Harbor : projets wb-sonde (privé : temoin:1.0, publication:courant, signee:1.0 signée) et
#            wb-sonde-public (public : temoin:1.0) ; robots système robot$wb-sonde-tirage (pull wb-sonde,
#            dockerhub, ghcr) et robot$wb-sonde-ci (pull + push wb-sonde) ;
#   runner02 : /etc/workbook/sonde-registre/ (root 700 : tirage/, ci/, anonyme/ = configurations Docker ;
#            cosign.pub = clé publique de TEST ; sonde.conf ; temoins.txt = digest signé de signee:1.0),
#            /var/lib/workbook/temoins-m13/ (clé privée de test et son mot de passe),
#            /usr/local/sbin/wb-sonde-registre (la sonde).
# État local (adm01) : ~/.local/state/workbook/M13-EXX/ (valeurs d'origine non secrètes).

_M13_REGISTRE_URL="${WB_HARBOR_URL:-https://registry.par1.medisphere.internal}"
_M13_REGISTRE="${_M13_REGISTRE_URL#https://}"
_M13_PANNES_FICHIER="${WB_HARBOR_PANNES_FILE:-$HOME/.config/workbook/harbor-pannes.env}"
_M13_RUNNER="${WB_M13_RUNNER:-runner02}"
_M13_REG01="${WB_M13_REG01:-reg01}"
_M13_RACINE=/usr/local/share/ca-certificates/medisphere-root-ca.crt
# Images Cosign tirées par le cache ghcr de Harbor (versions de PLAN §6 ; 2.5.0 = celle de Debian 13).
_M13_COSIGN_IMAGE="$_M13_REGISTRE/ghcr/sigstore/cosign/cosign:v3.1.3"
# shellcheck disable=SC2034  # utilisée par break-E21.sh
_M13_COSIGN_IMAGE_ANCIENNE="$_M13_REGISTRE/ghcr/sigstore/cosign/cosign:v2.5.0"
_M13_IMAGE_CACHE="dockerhub/library/busybox:1.37"

# ---------------------------------------------------------------------------
# État local et journal (adm01)
# ---------------------------------------------------------------------------
m13_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M13-$1"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}
m13_journal() {
  local ex="$1" d
  shift
  d="$(m13_etat "$ex")"
  printf '%s %s [M13-%s variante %s] %s\n' "$(date -Is)" "$(hostname -s)" "$ex" "${WB_VAR:-?}" "$*" >>"$d/journal"
}
m13_lire() {
  local f
  f="$(m13_etat "$1")/$2"
  if [[ -f "$f" ]]; then cat "$f"; fi
}
# Une seule écriture par clé et par panne : on ne capture jamais un état déjà cassé.
m13_ecrire() {
  local d
  d="$(m13_etat "$1")"
  [[ -f "$d/$2" ]] || printf '%s\n' "$3" >"$d/$2"
}

# ---------------------------------------------------------------------------
# API Harbor (identité wb-pannes)
# ---------------------------------------------------------------------------

# m13_api MÉTHODE CHEMIN [CORPS_JSON] — appel à /api/v2.0 ; corps de la réponse sur la sortie standard ;
# code 0 pour une réponse 2xx. Les identifiants passent par un fichier de configuration de curl lu sur
# un descripteur (jamais dans « ps »).
m13_api() {
  local m="$1" chemin="$2" corps="${3:-}" HARBOR_USER="" HARBOR_PASSWORD="" sortie code
  [[ -r "$_M13_PANNES_FICHIER" ]] || { wb_avert "identifiants des pannes illisibles : $_M13_PANNES_FICHIER"; return 1; }
  # shellcheck disable=SC1090
  source "$_M13_PANNES_FICHIER"
  local -a a=(-sS --max-time 30 -X "$m" -H "Accept: application/json" -w '\n%{http_code}')
  [[ -z "$corps" ]] || a+=(-H "Content-Type: application/json" --data "$corps")
  sortie="$(curl "${a[@]}" -K <(printf 'user = "%s:%s"\n' "$HARBOR_USER" "$HARBOR_PASSWORD") \
    "$_M13_REGISTRE_URL/api/v2.0/$chemin" 2>/dev/null)" || return 1
  code="${sortie##*$'\n'}"
  printf '%s' "${sortie%$'\n'*}"
  [[ "$code" =~ ^2[0-9][0-9]$ ]]
}

# m13_sante — 0 si /api/v2.0/health répond « healthy » (sans identité).
m13_sante() {
  curl -sf --max-time 10 --cacert "$_M13_RACINE" "$_M13_REGISTRE_URL/api/v2.0/health" 2>/dev/null \
    | jq -e '.status == "healthy"' >/dev/null 2>&1
}

# m13_attendre SECONDES COMMANDE… — relance COMMANDE toutes les 5 s jusqu'au succès ou à l'échéance.
m13_attendre() {
  local fin=$((SECONDS + $1))
  shift
  while ((SECONDS < fin)); do
    "$@" && return 0
    sleep 5
  done
  return 1
}

m13_projet_id() { m13_api GET "projects/$1" | jq -r '.project_id // empty'; }

# m13_robot NOM — objet JSON du robot système robot$NOM (vide s'il n'existe pas).
m13_robot() {
  m13_api GET "robots?page_size=100" | jq -c --arg n "robot\$$1" '[.[]? | select(.name == $n)][0] // empty'
}

# ---------------------------------------------------------------------------
# Témoins
# ---------------------------------------------------------------------------

# _m13_creer_projet NOM PUBLIC(true|false)
_m13_creer_projet() {
  [[ -n "$(m13_projet_id "$1")" ]] && return 0
  m13_api POST projects "{\"project_name\":\"$1\",\"metadata\":{\"public\":\"$2\"},\"storage_limit\":-1}" >/dev/null
}

# _m13_creer_robot NOM PERMISSIONS_JSON — crée (ou recrée) le robot et imprime son secret.
_m13_creer_robot() {
  local r id
  r="$(m13_robot "$1")"
  if [[ -n "$r" ]]; then
    id="$(jq -r '.id' <<<"$r")"
    m13_api DELETE "robots/$id" >/dev/null || return 1
  fi
  m13_api POST robots "{\"name\":\"$1\",\"description\":\"Témoin du palier 4 du module 13 (workbook)\",\"level\":\"system\",\"duration\":-1,\"disable\":false,\"permissions\":$2}" \
    | jq -r '.secret // empty'
}

# m13_temoins — crée les témoins s'ils n'existent pas (idempotent). Code ≠ 0 si impossible.
m13_temoins() {
  local s_tirage s_ci perm_t perm_c
  m13_sante || { wb_avert "Harbor ne répond pas « healthy » : impossible de préparer les témoins"; return 1; }
  if wb_exec "$_M13_RUNNER" <<'EOF' >/dev/null 2>&1; then
test -x /usr/local/sbin/wb-sonde-registre && test -s /etc/workbook/sonde-registre/temoins.txt
EOF
    [[ -n "$(m13_projet_id wb-sonde)" && -n "$(m13_robot wb-sonde-ci)" ]] && return 0
  fi
  echo "Préparation des témoins (première injection du palier 4, 1 à 3 minutes)…" >&2
  _m13_creer_projet wb-sonde false || return 1
  _m13_creer_projet wb-sonde-public true || return 1
  perm_t='[{"kind":"project","namespace":"wb-sonde","access":[{"resource":"repository","action":"pull"}]},
    {"kind":"project","namespace":"dockerhub","access":[{"resource":"repository","action":"pull"}]},
    {"kind":"project","namespace":"ghcr","access":[{"resource":"repository","action":"pull"}]}]'
  perm_c='[{"kind":"project","namespace":"wb-sonde","access":[{"resource":"repository","action":"pull"},{"resource":"repository","action":"push"}]},
    {"kind":"project","namespace":"wb-sonde-public","access":[{"resource":"repository","action":"pull"},{"resource":"repository","action":"push"}]}]'
  s_tirage="$(_m13_creer_robot wb-sonde-tirage "$(jq -c . <<<"$perm_t")")" || return 1
  s_ci="$(_m13_creer_robot wb-sonde-ci "$(jq -c . <<<"$perm_c")")" || return 1
  [[ -n "$s_tirage" && -n "$s_ci" ]] || { wb_avert "création des robots témoins impossible"; return 1; }
  wb_exec "$_M13_RUNNER" REG="$_M13_REGISTRE" RACINE="$_M13_RACINE" COSIGN_IMAGE="$_M13_COSIGN_IMAGE" \
    IMAGE_CACHE="$_M13_IMAGE_CACHE" S_TIRAGE="$s_tirage" S_CI="$s_ci" <<'EOF'
set -e
umask 077
D=/etc/workbook/sonde-registre
K=/var/lib/workbook/temoins-m13
install -d -m 0700 "$D" "$D/tirage" "$D/ci" "$D/anonyme" "$K"
auth() { printf '{"auths":{"%s":{"auth":"%s"}}}\n' "$REG" "$(printf '%s:%s' "$1" "$2" | base64 -w0)"; }
auth 'robot$wb-sonde-tirage' "$S_TIRAGE" > "$D/tirage/config.json"
auth 'robot$wb-sonde-ci' "$S_CI" > "$D/ci/config.json"
echo '{}' > "$D/anonyme/config.json"
cat > "$D/sonde.conf" <<CONF
# Configuration de la sonde des témoins du palier 4 du module 13 (créée par lab/bin/break).
REGISTRE=$REG
RACINE=$RACINE
COSIGN_IMAGE=$COSIGN_IMAGE
IMAGE_CACHE=$IMAGE_CACHE
CONF

# --- Sonde -------------------------------------------------------------------------------------
cat > /usr/local/sbin/wb-sonde-registre <<'SONDE'
#!/usr/bin/env bash
# wb-sonde-registre — sonde des témoins du palier 4 du module 13 (workbook DevOps / cloud privé).
# Joue le rôle d'un pipeline : tirages, poussée, vérification de signature, sur les projets wb-sonde*.
# Usage : wb-sonde-registre [--lecture] [--etape tirage|public|cache|publication|poussee|signature]
#   --lecture : sans tirage ni poussée (« docker manifest inspect » au lieu de « docker pull ») ;
#               l'étape publication est remplacée par « poussee » (le jeton accorde-t-il push ?)
#               et la signature n'est pas vérifiée ; c'est le mode des contrôles du workbook.
# Code retour : 0 si toutes les étapes demandées réussissent, 1 sinon.
set -uo pipefail
D=/etc/workbook/sonde-registre
# shellcheck source=/dev/null
source "$D/sonde.conf"
LECTURE=0
SEULE=""
while (($#)); do
  case "$1" in
    --lecture) LECTURE=1; shift ;;
    --etape) SEULE="${2:-}"; shift 2 ;;
    *) echo "usage : $0 [--lecture] [--etape tirage|public|cache|publication|poussee|signature]" >&2; exit 2 ;;
  esac
done
ECHECS=0
etape() {
  local nom="$1" sortie rc
  shift
  [[ -z "$SEULE" || "$SEULE" == "$nom" ]] || return 0
  sortie="$(timeout 120 "$@" 2>&1)"; rc=$?
  if ((rc == 0)); then
    printf 'OK      %-12s\n' "$nom"
  else
    printf 'ÉCHEC   %-12s (code %d)\n' "$nom" "$rc"
    printf '%s\n' "$sortie" | tail -n 4 | sed 's/^/          | /'
    ECHECS=$((ECHECS + 1))
  fi
}
tirer() {   # tirer CONFIG IMAGE
  if ((LECTURE)); then
    docker --config "$D/$1" manifest inspect "$REGISTRE/$2" >/dev/null
  else
    docker image rm -f "$REGISTRE/$2" >/dev/null 2>&1 || true
    docker --config "$D/$1" pull -q "$REGISTRE/$2"
  fi
}
publier() {
  local t rc=0
  t="$(mktemp -d)"
  date -Ins > "$t/date.txt"
  printf 'FROM scratch\nCOPY date.txt /\n' > "$t/Dockerfile"
  docker build -q -t "$REGISTRE/wb-sonde/publication:courant" "$t" >/dev/null && \
    docker --config "$D/ci" push -q "$REGISTRE/wb-sonde/publication:courant" || rc=$?
  rm -rf "$t"
  return "$rc"
}
# droit_poussee — sans rien pousser : le jeton délivré au robot ci pour wb-sonde/publication contient « push ».
droit_poussee() {
  local auth jeton p
  auth="$(sed -nE 's/.*"auth":"([^"]+)".*/\1/p' "$D/ci/config.json")"
  jeton="$(curl -sf --max-time 20 -H "Authorization: Basic $auth" \
    "https://$REGISTRE/service/token?service=harbor-registry&scope=repository:wb-sonde/publication:pull,push" \
    | sed -nE 's/.*"token":"([^"]+)".*/\1/p')"
  [ -n "$jeton" ] || { echo "aucun jeton délivré" >&2; return 1; }
  p="$(cut -d. -f2 <<<"$jeton" | tr '_-' '/+')"
  while (( ${#p} % 4 )); do p="$p="; done
  base64 -d <<<"$p" 2>/dev/null | grep -q '"push"' || { echo "le jeton n'accorde pas « push »" >&2; return 1; }
}
verifier() {
  docker --config "$D/tirage" run --rm --network host \
    -v "$D/tirage:/cfg:ro" -v "$RACINE:/ca.crt:ro" -v "$D/cosign.pub:/cosign.pub:ro" \
    -e DOCKER_CONFIG=/cfg -e SSL_CERT_FILE=/ca.crt \
    "$COSIGN_IMAGE" verify --key /cosign.pub --insecure-ignore-tlog=true "$REGISTRE/wb-sonde/signee:1.0" >/dev/null
}
etape tirage tirer tirage wb-sonde/temoin:1.0
etape public tirer anonyme wb-sonde-public/temoin:1.0
etape cache tirer tirage "$IMAGE_CACHE"
if ((LECTURE)); then etape poussee droit_poussee; else etape publication publier; fi
((LECTURE)) || etape signature verifier
echo "Bilan : $ECHECS échec(s)."
((ECHECS == 0))
SONDE
chmod 0755 /usr/local/sbin/wb-sonde-registre

# --- Images témoins (FROM scratch : aucun tirage nécessaire) -------------------------------------
construire() {   # construire IMAGE TEXTE
  local t
  t="$(mktemp -d)"
  printf '%s\n' "$2" > "$t/temoin.txt"
  printf 'FROM scratch\nCOPY temoin.txt /\n' > "$t/Dockerfile"
  docker build -q -t "$REG/$1" "$t" >/dev/null
  rm -rf "$t"
  docker --config "$D/ci" push "$REG/$1" 2>&1 | grep -o 'sha256:[0-9a-f]\{64\}' | tail -n 1
}
construire wb-sonde/temoin:1.0 "témoin privé" >/dev/null
construire wb-sonde-public/temoin:1.0 "témoin public" >/dev/null
construire wb-sonde/publication:courant "$(date -Is)" >/dev/null
DIGEST="$(construire wb-sonde/signee:1.0 "image signée des témoins")"
[ -n "$DIGEST" ]

# --- Clé de test et signature ---------------------------------------------------------------------
[ -s "$K/cosign-sonde.pass" ] || head -c 24 /dev/urandom | base64 > "$K/cosign-sonde.pass"
cos() {
  docker --config "$D/tirage" run --rm --network host --user 0:0 \
    -v "$K:/k" -v "$D/ci:/cfg:ro" -v "$RACINE:/ca.crt:ro" -w /k \
    -e DOCKER_CONFIG=/cfg -e SSL_CERT_FILE=/ca.crt -e COSIGN_PASSWORD="$(cat "$K/cosign-sonde.pass")" \
    "$COSIGN_IMAGE" "$@"
}
# Configuration de signature SANS aucun service (ni Fulcio, ni Rekor, ni horodatage), comme
# docs/registre/signing-config.json (M13-E07) : rien ne part vers le journal public.
[ -s "$K/signing-config.json" ] || printf '{"mediaType":"application/vnd.dev.sigstore.signingconfig.v0.2+json"}\n' > "$K/signing-config.json"
[ -s "$K/cosign-sonde.key" ] || cos generate-key-pair --output-key-prefix cosign-sonde >/dev/null 2>&1
chmod 600 "$K/cosign-sonde.key"
cp "$K/cosign-sonde.pub" "$D/cosign.pub"
cos sign --yes --key /k/cosign-sonde.key --signing-config /k/signing-config.json "$REG/wb-sonde/signee@$DIGEST" >/dev/null 2>&1
printf 'signee:1.0 %s\n' "$DIGEST" > "$D/temoins.txt"
journal "témoins créés (signee:1.0 = $DIGEST)"
/usr/local/sbin/wb-sonde-registre >/dev/null
EOF
}

# m13_sonde [OPTIONS…] — lance la sonde sur runner02 ; code de la sonde.
m13_sonde() {
  local o
  o="$(printf '%q ' "$@")"
  remote "$_M13_RUNNER" "sudo -n /usr/local/sbin/wb-sonde-registre $o" >/dev/null 2>&1
}

# m13_sonde_echoue ETAPE — 0 si l'étape échoue (la panne est constatée).
m13_sonde_echoue() { ! m13_sonde --etape "$1"; }

# m13_preparer — témoins prêts et sonde entièrement verte avant d'injecter (on ne casse pas un lab
# déjà cassé).
m13_preparer() {
  m13_temoins || return 1
  if ! m13_sonde; then
    wb_avert "la sonde des témoins n'est pas verte avant l'injection (sudo wb-sonde-registre sur $_M13_RUNNER) : rien n'a été cassé"
    return 1
  fi
}

# m13_runner_libre — aucun job GitLab en cours sur runner02 (conteneurs du runner).
m13_runner_libre() {
  wb_exec "$_M13_RUNNER" <<'EOF' >/dev/null 2>&1
[ -z "$(docker ps -q --filter label=com.gitlab.gitlab-runner.type 2>/dev/null)" ]
EOF
}
