# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E19.sh — M13-E19 « Panne : impossible de tirer l'image »
#
# Variantes :
#   1. robot$wb-sonde-tirage expiré (durée ramenée sous son âge) ou, s'il a moins de deux jours,
#      désactivé → tirages privés et par le cache refusés (« unauthorized ») ;
#   2. projet wb-sonde-public repassé en privé → tirage anonyme refusé ;
#   3. racine MédiSphère retirée du magasin de certificats de runner02 (et de /etc/docker/certs.d) puis
#      démon Docker redémarré → « x509: certificate signed by unknown authority » (seulement si aucun job
#      ne tourne sur runner02) ;
#   4. identifiants invalides posés sur l'endpoint amont du cache dockerhub (« jeton Docker Hub »
#      collé par erreur) → Docker Hub refuse l'authentification : ce qui est en cache passe, une image
#      jamais tirée échoue. Seulement si l'endpoint est anonyme (M13-E04, défaut) : un secret existant
#      ne peut pas être relu par l'API, donc pas restauré — la variante est alors refusée.
# Valeurs d'origine dans ~/.local/state/workbook/M13-E19/ (adm01) et /var/lib/workbook/ (runner02).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m13-commun.sh
source "$WB_ROOT/modules/13-registre-supply-chain/corrige/pannes/_m13-commun.sh"

# Images publiques candidates pour la variante 4 (la première qui n'est pas encore en cache).
_E19_CANDIDATES=(library/python:3.14-slim-trixie library/node:24-trixie-slim library/golang:1.26-alpine
  library/alpine:3.22 library/redis:8.0-alpine library/nginx:1.29-alpine library/busybox:1.36.1)

_e19_registre_cache_id() { m13_api GET projects/dockerhub | jq -r '.registry_id // empty'; }

# _e19_en_cache DÉPÔT:ÉTIQUETTE — l'artefact existe déjà dans le projet dockerhub.
_e19_en_cache() {
  local repo="${1%%:*}" tag="${1##*:}"
  m13_api GET "projects/dockerhub/repositories/${repo//\//%252F}/artifacts/$tag" >/dev/null 2>&1
}

# _e19_manifeste_refuse DÉPÔT:ÉTIQUETTE — avec un jeton de wb-pannes, le manifeste n'est pas servi.
_e19_manifeste_refuse() {
  local repo="${1%%:*}" tag="${1##*:}" jeton code HARBOR_USER="" HARBOR_PASSWORD=""
  # shellcheck disable=SC1090
  source "$_M13_PANNES_FICHIER"
  jeton="$(curl -sf --max-time 20 -K <(printf 'user = "%s:%s"\n' "$HARBOR_USER" "$HARBOR_PASSWORD") \
    "$_M13_REGISTRE_URL/service/token?service=harbor-registry&scope=repository:dockerhub/$repo:pull" | jq -r '.token // empty')"
  [[ -n "$jeton" ]] || return 1
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 60 -H "Authorization: Bearer $jeton" \
    -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json' \
    "$_M13_REGISTRE_URL/v2/dockerhub/$repo/manifests/$tag")"
  [[ "$code" != 200 ]]
}

_e19_poser() {
  local r id age j cid u img
  case "$1" in
    1)
      r="$(m13_robot wb-sonde-tirage)"
      [[ -n "$r" ]] || return 1
      m13_ecrire E19 robot "$r"
      id="$(jq -r '.id' <<<"$r")"
      age=$((($(date +%s) - $(date -d "$(jq -r '.creation_time' <<<"$r")" +%s)) / 86400))
      if ((age >= 2)); then
        j="$(jq -c '.duration = 1 | .disable = false' <<<"$r")"
      else
        j="$(jq -c '.disable = true' <<<"$r")"
      fi
      m13_api PUT "robots/$id" "$j" >/dev/null || return 1
      ;;
    2)
      m13_ecrire E19 public "$(m13_api GET projects/wb-sonde-public | jq -r '.metadata.public')"
      m13_api PUT projects/wb-sonde-public '{"metadata":{"public":"false"}}' >/dev/null || return 1
      ;;
    3)
      m13_runner_libre || { wb_avert "un job tourne sur $_M13_RUNNER : variante 3 impossible maintenant"; return 10; }
      wb_exec "$_M13_RUNNER" REG="$_M13_REGISTRE" RACINE="$_M13_RACINE" <<'EOF' || return 1
set -e
sauver "$RACINE"
for f in /etc/docker/certs.d/"$REG"/*.crt; do [ -e "$f" ] && sauver "$f"; done
rm -f "$RACINE" /etc/docker/certs.d/"$REG"/*.crt
update-ca-certificates --fresh >/dev/null 2>&1
systemctl restart docker
journal "racine MédiSphère retirée, Docker redémarré"
EOF
      ;;
    4)
      cid="$(_e19_registre_cache_id)"
      [[ -n "$cid" ]] || return 1
      for img in "${_E19_CANDIDATES[@]}"; do
        _e19_en_cache "$img" || { m13_ecrire E19 image "$img"; break; }
      done
      [[ -n "$(m13_lire E19 image)" ]] || { wb_avert "toutes les images candidates sont déjà en cache"; return 10; }
      u="$(m13_api GET "registries/$cid" | jq -r '.credential.access_key // ""')"
      [[ -z "$u" ]] || { wb_avert "l'endpoint dockerhub a un compte configuré : variante 4 refusée (secret non restaurable)"; return 10; }
      m13_ecrire E19 endpoint "$cid"
      m13_api PUT "registries/$cid" '{"credential_type":"basic","access_key":"medisphere-ci","access_secret":"dckr_pat_wb-m13-e19-invalide"}' >/dev/null || return 1
      ;;
  esac
  m13_journal E19 "variante $1 posée"
}

_e19_defaire() {
  local r id cid
  case "$1" in
    1)
      r="$(m13_lire E19 robot)"
      [[ -n "$r" ]] || return 0
      id="$(jq -r '.id' <<<"$r")"
      # Encore cassé (désactivé ou expiré) : on remet l'objet d'origine.
      if m13_api GET "robots/$id" | jq -e '.disable == true or (.duration == 1)' >/dev/null 2>&1; then
        m13_api PUT "robots/$id" "$(jq -c 'del(.secret)' <<<"$r")" >/dev/null || wb_avert "annulation : robot wb-sonde-tirage non rétabli"
      fi
      ;;
    2)
      [[ -n "$(m13_lire E19 public)" ]] || return 0
      if m13_api GET projects/wb-sonde-public | jq -e '.metadata.public == "false"' >/dev/null 2>&1; then
        m13_api PUT projects/wb-sonde-public '{"metadata":{"public":"true"}}' >/dev/null || wb_avert "annulation : wb-sonde-public non rétabli"
      fi
      ;;
    3)
      wb_exec "$_M13_RUNNER" RACINE="$_M13_RACINE" <<'EOF' || wb_avert "annulation : racine de runner02 non rétablie"
if [ -f "$WB_DIR/$WB_EX.manifeste" ]; then
  restaurer_fichiers
  update-ca-certificates >/dev/null 2>&1
  systemctl restart docker
  journal "racine MédiSphère rétablie, Docker redémarré"
fi
EOF
      ;;
    4)
      cid="$(m13_lire E19 endpoint)"
      [[ -n "$cid" ]] || return 0
      if m13_api GET "registries/$cid" | jq -e '.credential.access_key == "medisphere-ci"' >/dev/null 2>&1; then
        m13_api PUT "registries/$cid" '{"credential_type":"basic","access_key":"","access_secret":""}' >/dev/null \
          || wb_avert "annulation : identifiants de l'endpoint dockerhub non retirés"
      fi
      ;;
  esac
}

_e19_injecter() { m13_preparer || return 1; _e19_poser "$1"; }
panne_E19_v1() { _e19_injecter 1; }
panne_E19_v2() { _e19_injecter 2; }
panne_E19_v3() { _e19_injecter 3; }
panne_E19_v4() { _e19_injecter 4; }

verifier_E19() {
  case "$WB_VAR" in
    1) m13_attendre 60 m13_sonde_echoue tirage ;;
    2) m13_attendre 60 m13_sonde_echoue public ;;
    3) m13_attendre 60 m13_sonde_echoue tirage ;;
    *) m13_attendre 120 _e19_manifeste_refuse "$(m13_lire E19 image)" ;;
  esac
}

annuler_E19() {
  case "${WB_VAR:-}" in
    1 | 2 | 3 | 4) _e19_defaire "$WB_VAR" ;;
    *) _e19_defaire 4; _e19_defaire 3; _e19_defaire 2; _e19_defaire 1 ;;
  esac
  m13_journal E19 "annulation"
  rm -rf -- "$(m13_etat E19)"
}

resume_E19() { echo "Les jobs de runner02 n'arrivent plus à tirer certaines images de Harbor."; }

symptome_E19() {
  local l
  case "$WB_VAR" in
    1) l="Depuis ce matin, les jobs qui tirent les images privées de wb-sonde (et les images publiques par le cache) échouent sur runner02 : « unauthorized ». Rien n'a changé dans nos pipelines." ;;
    2) l="Le job de documentation tire wb-sonde-public/temoin:1.0 sans identifiants, comme toujours. Depuis une heure : « unauthorized to access repository ». C'était public, non ?" ;;
    3) l="Après le redémarrage de Docker sur runner02 cette nuit, plus aucun tirage depuis Harbor ne passe sur ce runner. Depuis mon poste, ça marche." ;;
    *) l="Le nouveau job qui utilise $(m13_lire E19 image | sed 's|^library/||') par le cache dockerhub échoue. Les jobs qui utilisent les images de base habituelles passent." ;;
  esac
  wb_symptome "Ticket INC-4031 — De : Julien Petit" \
    "$l" \
    "Reproduction : « sudo wb-sonde-registre » sur runner02. Lucas propose de tout passer en public :" \
    "n'en fais rien." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 13 19"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 13 E19 4 "$@"; }
fi
