# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq/yq et scripts distants entre apostrophes
# _m24-commun.sh — fonctions partagées par les scripts de panne du module 24 (M24-E35 à M24-E43).
#
# Sourcé par break-EXX.sh APRÈS lab/lib/pannes-lib.sh (wb_exec, wb_kubectl, wb_avert, WB_EX…).
# Rappel : lab/bin/break tourne avec « set -euo pipefail » ; les fonctions d'annulation sont appelées
# hors de tout « if » : aucune commande ne doit y échouer sans « || true ».
#
# Principes (CONVENTIONS §8, PLAN §4.12 « Pannes du bloc F ») :
#   - une panne d'identité ne modifie qu'un CLIENT, un FLUX, un COMPOSANT ou un RÉGLAGE du royaume
#     « medisphere », jamais « master » : le chemin de l'API d'administration est construit ici avec
#     le royaume en dur (m24_kc refuse tout chemin absolu ou remontant). Le jeton est celui du client
#     d'OpenTofu « svc-tofu-keycloak » (royaume master, administrateur du SEUL royaume medisphere,
#     fichier WB_M24_KC_ADMIN_FILE, défaut ~/.config/workbook/keycloak-tofu.env, M24-E08) : il sert à
#     obtenir un jeton, rien n'est écrit dans master. Chaque objet est EXPORTÉ en JSON avant
#     modification (~/.local/state/workbook/M24-EXX/, 600) et n'est restauré que s'il porte encore
#     la valeur injectée : une réparation de l'apprenant n'est jamais défaite ;
#   - jamais le compte de l'apprenant (<MOI>, <MOI>-admin) ni les comptes de bris de glace (admin de
#     l'annuaire, kc-secours, root GitLab, root@pam, admin.conf, admin local des VMs, admin Argo CD) :
#     aucune panne ne change leur mot de passe, ne les verrouille, ne leur retire un droit ;
#   - fichiers des VMs : sauvegardés par « sauver » (pannes-lib) avant modification, journal
#     /var/lib/workbook/pannes.log sur l'hôte ; un fichier lu par un processus en cours (fichier
#     d'authentification de kube-apiserver) est réécrit EN PLACE (même inode : un montage de fichier
#     isolé dans le pod statique verrait sinon l'ancien contenu) ;
#   - annuaire (ipa01, Rocky 10) : par le cadre Python de FreeIPA exécuté sur le serveur en root
#     (liaison LDAPI par autobind, équivalent du Directory Manager), jamais par le compte admin ni son
#     mot de passe ; seuls le compte système svc-keycloak, les règles HBAC/sudo nommées dans la fiche
#     et la personne fictive de l'exercice M24-E37 (WB_M24_ARRIVEE, créée puis supprimée) sont touchés ;
#   - Kubernetes : kubectl d'administration exécuté SUR un nœud de contrôle (/etc/kubernetes/admin.conf
#     lu en root), pour ne pas dépendre de l'authentification OIDC qu'une panne peut casser ; ou
#     WB_K8S_ADMIN_KUBECONFIG s'il est défini. Aucun objet de kube-system n'est touché ;
#   - horloges : jamais pve01 ni les passerelles ; chrony arrêté puis relancé avec « makestep ».

_M24_DIR="$(dirname "${BASH_SOURCE[0]}")"
_M24_SSO="${WB_KEYCLOAK_URL:-https://sso.par1.medisphere.internal}"
_M24_EMETTEUR="$_M24_SSO/realms/medisphere"
_M24_RACINE="${WB_RACINE_PKI:-/usr/local/share/ca-certificates/medisphere-root-ca.crt}"
_M24_IDP="${WB_M24_IDP:-idp01}"
_M24_IPA="${WB_M24_IPA:-ipa01}"
_M24_MON01="${WB_M24_MON01:-mon01}"
_M24_VM_SSSD="${WB_M24_VM_SSSD:-nbx01}"
_M24_AUTHN="${WB_M24_AUTHN_FICHIER:-/etc/kubernetes/authentification/config.yaml}"
_M24_ARRIVEE="${WB_M24_ARRIVEE:-emma.durand}"
_M24_GRAFANA="${WB_GRAFANA_URL:-https://grafana.apps.par1.medisphere.internal}"
_M24_BASE="dc=par1,dc=medisphere,dc=internal"
read -r -a _M24_CP <<<"${WB_M24_CP:-k8s-cp01 k8s-cp02 k8s-cp03}"
read -r -a _M24_LB <<<"${WB_M24_LB:-lb01 lb02}"
_M24_KC_JETON=""
_M24_KC_JETON_T=0

# ---------------------------------------------------------------------------
# État local et journal (adm01)
# ---------------------------------------------------------------------------

# m24_etat EXX — affiche (et crée, en 700) le dossier d'état local de la panne.
m24_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M24-$1"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}

m24_journal() {
  local ex="$1" d
  shift
  d="$(m24_etat "$ex")"
  printf '%s %s [M24-%s variante %s] %s\n' "$(date -Is)" "$(hostname -s)" "$ex" "${WB_VAR:-?}" "$*" >>"$d/journal"
}

# m24_lire EXX CLÉ / m24_ecrire EXX CLÉ VALEUR / m24_oublier EXX CLÉ — petites valeurs d'état (600).
m24_lire() {
  local f
  f="$(m24_etat "$1")/$2"
  if [[ -f "$f" ]]; then cat "$f"; fi
}
m24_ecrire() {
  local d
  d="$(m24_etat "$1")"
  (umask 077 && printf '%s\n' "$3" >"$d/$2")
}
m24_oublier() {
  local d
  d="$(m24_etat "$1")"
  rm -f -- "${d:?}/$2"
}

# m24_attendre SECONDES commande… — relance la commande toutes les 10 s jusqu'à succès ou délai.
m24_attendre() {
  local max="$1" t=0
  shift
  while ((t < max)); do
    if "$@"; then return 0; fi
    sleep 10
    t=$((t + 10))
  done
  "$@"
}

# m24_essayer EXX NB DÉPART — essaie les variantes à partir de DÉPART ; une variante qui renvoie 10
# est « sans effet sur ce lab » (objet absent, nom différent de la fiche) : on passe à la suivante.
# La fonction _m24EXX_une N fait l'injection (et la défait elle-même si elle renvoie 10).
m24_essayer() {
  local ex="$1" nb="$2" depart="$3" i n rc
  for ((i = 0; i < nb; i++)); do
    n=$(((depart - 1 + i) % nb + 1))
    rc=0
    WB_VAR="$n"
    "_m24${ex}_une" "$n" || rc=$?
    if ((rc == 0)); then
      WB_VAR="$n"
      return 0
    fi
    ((rc == 10)) || return 1
    m24_journal "$ex" "variante $n sans effet sur ce lab, suivante"
  done
  wb_avert "aucune variante de M24-$ex n'a d'effet sur ce lab (configuration différente de la fiche du module)"
  return 1
}

m24_maintenant() { date +%s; }
_m24_enc() { jq -rn --arg v "$1" '$v|@uri'; }

# ---------------------------------------------------------------------------
# Keycloak : API d'administration du royaume medisphere (et lui seul)
# ---------------------------------------------------------------------------

# _m24_kc_jeton — jeton du client svc-tofu-keycloak (le jeton de master dure 60 s par défaut :
# renouvelé au bout de 40 s). Le secret ne passe jamais sur une ligne de commande.
_m24_kc_jeton() {
  local f="${WB_M24_KC_ADMIN_FILE:-$HOME/.config/workbook/keycloak-tofu.env}" KEYCLOAK_CLIENT_ID="" KEYCLOAK_CLIENT_SECRET="" r
  if [[ -n "$_M24_KC_JETON" ]] && (($(m24_maintenant) - _M24_KC_JETON_T < 40)); then return 0; fi
  [[ -r "$f" ]] || return 1
  # shellcheck disable=SC1090
  source "$f"
  r="$(curl -sf --max-time 20 --cacert "$_M24_RACINE" \
    -K <(printf 'user = "%s:%s"\n' "$KEYCLOAK_CLIENT_ID" "$KEYCLOAK_CLIENT_SECRET") \
    -d grant_type=client_credentials "$_M24_SSO/realms/master/protocol/openid-connect/token" 2>/dev/null |
    jq -r '.access_token // empty' 2>/dev/null)" || r=""
  [[ -n "$r" ]] || return 1
  _M24_KC_JETON="$r"
  _M24_KC_JETON_T="$(m24_maintenant)"
}

# m24_kc MÉTHODE CHEMIN [options curl…] — /admin/realms/medisphere/CHEMIN (CHEMIN vide : le royaume
# lui-même) ; jamais un autre royaume.
m24_kc() {
  local m="$1" p="$2"
  shift 2
  if [[ "$p" == /* || "$p" == *..* ]]; then
    wb_avert "chemin d'API Keycloak refusé : $p"
    return 1
  fi
  _m24_kc_jeton || return 1
  curl -sS --fail --max-time 30 --cacert "$_M24_RACINE" -X "$m" \
    -K <(printf 'header = "Authorization: Bearer %s"\n' "$_M24_KC_JETON") \
    -H 'Accept: application/json' "$_M24_SSO/admin/realms/medisphere${p:+/$p}" "$@"
}

# m24_kc_json MÉTHODE CHEMIN JSON — envoi d'une représentation JSON.
m24_kc_json() { m24_kc "$1" "$2" -H 'Content-Type: application/json' --data-binary "$3"; }

# m24_kc_client CLIENT_ID — représentation du client (vide si absent).
m24_kc_client() { m24_kc GET "clients?clientId=$(_m24_enc "$1")" 2>/dev/null | jq -c '.[0] // empty' 2>/dev/null; }

# m24_kc_client_uuid CLIENT_ID — identifiant interne du client (vide si absent).
m24_kc_client_uuid() { m24_kc_client "$1" | jq -r '.id // empty' 2>/dev/null; }

# m24_kc_portee_uuid NOM — identifiant de la portée (client scope).
m24_kc_portee_uuid() {
  m24_kc GET client-scopes 2>/dev/null | jq -r --arg n "$1" '[.[] | select(.name == $n)][0].id // empty' 2>/dev/null
}

# m24_kc_ldap — composant de la fédération LDAP (celle nommée ipa01, sinon la seule).
m24_kc_ldap() {
  m24_kc GET "components?type=org.keycloak.storage.UserStorageProvider" 2>/dev/null | jq -c '
    [.[] | select(.providerId == "ldap")] as $l
    | (([$l[] | select(.name == "ipa01")][0]) // (if ($l | length) == 1 then $l[0] else empty end)) // empty' 2>/dev/null
}

# m24_kc_mappeur_groupes LDAP_ID — mappeur group-ldap-mapper de la fédération.
m24_kc_mappeur_groupes() {
  m24_kc GET "components?parent=$(_m24_enc "$1")&type=org.keycloak.storage.ldap.mappers.LDAPStorageMapper" 2>/dev/null |
    jq -c '[.[] | select(.providerId == "group-ldap-mapper")][0] // empty' 2>/dev/null
}

# m24_kc_sauver EXX CLÉ JSON — export avant modification (une seule fois par panne).
m24_kc_sauver() {
  local f
  f="$(m24_etat "$1")/kc-$2.json"
  [[ -e "$f" ]] && return 0
  (umask 077 && printf '%s\n' "$3" >"$f")
}
# m24_kc_sauve EXX CLÉ — export sauvegardé (code 1 si aucun).
m24_kc_sauve() {
  local f
  f="$(m24_etat "$1")/kc-$2.json"
  [[ -s "$f" ]] && cat "$f"
}
m24_kc_oublier() { m24_oublier "$1" "kc-$2.json"; }

# m24_kc_code_auth CLIENT_ID REDIRECT — code HTTP du point d'autorisation pour cette redirection
# (200 = formulaire de connexion ; 400 = redirection refusée). Aucune connexion n'est faite.
m24_kc_code_auth() {
  curl -s -o /dev/null -w '%{http_code}' --max-time 20 --cacert "$_M24_RACINE" -G \
    --data-urlencode "client_id=$1" --data-urlencode "redirect_uri=$2" --data-urlencode response_type=code \
    --data-urlencode scope=openid --data-urlencode "state=wb$RANDOM" \
    "$_M24_EMETTEUR/protocol/openid-connect/auth" 2>/dev/null || true
}

# m24_kc_synchro LDAP_ID [triggerChangedUsersSync|triggerFullSync] — synchronisation de la fédération
# (point de terminaison de la console d'administration ; la réponse n'est pas interprétée).
m24_kc_synchro() {
  m24_kc POST "user-storage/$(_m24_enc "$1")/sync?action=${2:-triggerChangedUsersSync}" >/dev/null 2>&1 || true
}

# m24_kc_utilisateur NOM — représentation de l'utilisateur (recherche exacte ; vide si absent).
m24_kc_utilisateur() {
  m24_kc GET "users?username=$(_m24_enc "$1")&exact=true" 2>/dev/null | jq -c '.[0] // empty' 2>/dev/null
}

# m24_decouverte_emetteur — émetteur annoncé par la découverte publique (vide si muette).
m24_decouverte_emetteur() {
  curl -sf --max-time 15 --cacert "$_M24_RACINE" "$_M24_EMETTEUR/.well-known/openid-configuration" 2>/dev/null |
    jq -r '.issuer // empty' 2>/dev/null
}

# ---------------------------------------------------------------------------
# VMs, annuaire et cluster
# ---------------------------------------------------------------------------

# m24_ssh HÔTE 'commande' — commande courte en root sur une VM (sortie standard).
m24_ssh() { remote "$1" "sudo -n bash -c $(printf '%q' "$2")" </dev/null; }

# Aides ajoutées devant les scripts distants (wb_exec) : service de temps, unité par binaire.
read -r -d '' _M24_AIDE <<'AIDE' || true
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# unite_temps — chrony (Debian) ou chronyd (Rocky).
unite_temps() {
  if systemctl cat chrony.service >/dev/null 2>&1; then echo chrony; else echo chronyd; fi
}
# unite_de BINAIRE — unité de service dont l'ExecStart lance ce binaire (nom de base).
unite_de() {
  local u x
  for u in $(systemctl list-units --type=service --all --no-legend --plain 2>/dev/null | awk '{print $1}'); do
    x="$(systemctl show -p ExecStart --value "$u" 2>/dev/null | sed -n 's/.*path=\([^ ;]*\).*/\1/p' | head -n 1)"
    [ "$(basename "${x:-/}")" = "$1" ] && { echo "$u"; return 0; }
  done
  return 1
}
# option_de UNITÉ OPTION — valeur d'une option longue (--opt=v ou --opt v) de la ligne de commande.
option_de() {
  systemctl show -p ExecStart --value "$1" 2>/dev/null | tr ' ;' '\n\n' |
    sed -n "s/^--$2=\(.*\)/\1/p; /^--$2\$/{n;p}" | head -n 1
}
# ecrire_en_place FICHIER (contenu sur l'entrée standard) — garde l'inode, le propriétaire et les droits.
ecrire_en_place() {
  local t
  t="$(mktemp)"
  cat > "$t" && cat "$t" > "$1"
  rm -f "$t"
}
# restaurer_en_place — comme restaurer_fichiers (pannes-lib), mais sans changer d'inode.
restaurer_en_place() {
  local m="$WB_DIR/$WB_EX.manifeste" src dst
  [ -f "$m" ] || return 0
  while IFS="$(printf '\t')" read -r src dst; do
    if [ "$dst" != ABSENT ] && [ -e "$dst" ] && [ -e "$src" ]; then
      cat "$dst" > "$src" && rm -f "$dst"
    fi
  done < "$m"
  rm -f "$m"
}
AIDE

# m24_wb_exec HÔTE [VAR=valeur…] <<'EOF' … EOF — wb_exec avec les aides ci-dessus.
m24_wb_exec() {
  local h="$1"
  shift
  { printf '%s\n' "$_M24_AIDE"; cat; } | wb_exec "$h" "$@"
}

# Prélude Python de l'annuaire : cadre de FreeIPA côté serveur, liaison LDAPI en root (autobind).
# Le script reçoit ses paramètres en JSON (sys.argv[1]) et écrit un JSON sur la sortie standard.
read -r -d '' _M24_IPA_PRELUDE <<'PY' || true
import json, sys
from ipalib import api, errors
api.bootstrap(context='cli', in_server=True, confdir='/etc/ipa')
api.finalize()
api.Backend.ldap2.connect()
P = json.loads(sys.argv[1]) if len(sys.argv) > 1 else {}
def sortie(o):
    print(json.dumps(o, default=str))
PY

# m24_ipa_py 'code Python' 'paramètres JSON' — exécute le code sur ipa01 (root), sortie JSON.
m24_ipa_py() {
  local code="$_M24_IPA_PRELUDE"$'\n'"$1" params="${2:-}"
  [[ -n "$params" ]] || params='{}'
  m24_wb_exec "$_M24_IPA" "PY=$code" "PARAMS=$params" <<'EOF'
journal "annuaire (cadre FreeIPA) : ${PARAMS:0:200}"
python3 -I -c "$PY" "$PARAMS"
EOF
}

# m24_cp1 — premier nœud de contrôle (ceux par qui passe le kubectl d'administration).
m24_cp1() { printf '%s\n' "${_M24_CP[0]}"; }

# m24_kubectl ARGS… — kubectl d'administration sans OIDC : WB_K8S_ADMIN_KUBECONFIG s'il est défini,
# sinon /etc/kubernetes/admin.conf lu en root sur le premier nœud de contrôle.
m24_kubectl() {
  if [[ -n "${WB_K8S_ADMIN_KUBECONFIG:-}" ]]; then
    wb_kubectl "$@"
    return
  fi
  local a args=""
  for a in "$@"; do args+=" $(printf '%q' "$a")"; done
  remote "$(m24_cp1)" "sudo -n kubectl --kubeconfig /etc/kubernetes/admin.conf --request-timeout=20s$args"
}

# m24_ecart_horloge HÔTE — écart en secondes (hôte − adm01).
m24_ecart_horloge() {
  local d
  d="$(remote "$1" 'date +%s' </dev/null 2>/dev/null)" || return 1
  [[ "$d" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$((d - $(m24_maintenant)))"
}

# m24_marquee EXX… — 0 si l'une des pannes listées est marquée active.
m24_marquee() {
  local e
  for e in "$@"; do
    wb_marqueur_existe "M24-$e" && return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# Santé avant injection
# ---------------------------------------------------------------------------

# m24_sain_keycloak — le fournisseur répond avec le bon émetteur et le client d'OpenTofu obtient un jeton.
m24_sain_keycloak() {
  if [[ -n "${_M24_ASTREINTE:-}" ]]; then return 0; fi
  if [[ "$(m24_decouverte_emetteur)" != "$_M24_EMETTEUR" ]]; then
    echo "La découverte OIDC de $_M24_EMETTEUR ne répond pas (ou annonce un autre émetteur) : rien n'est cassé (lab/bin/check 24 04)." >&2
    return 1
  fi
  if ! _m24_kc_jeton; then
    echo "Pas de jeton d'administration du royaume medisphere (client svc-tofu-keycloak, fichier ${WB_M24_KC_ADMIN_FILE:-~/.config/workbook/keycloak-tofu.env}) : rien n'est cassé (M24-E08)." >&2
    return 1
  fi
  if ! command -v yq >/dev/null || ! yq --version 2>/dev/null | grep -q mikefarah; then
    echo "yq (mikefarah, v4) est nécessaire sur adm01 : rien n'est cassé." >&2
    return 1
  fi
}

# m24_sain_hote HÔTE — la VM répond en SSH avec sudo sans mot de passe.
m24_sain_hote() {
  if ! remote "$1" 'sudo -n true' </dev/null >/dev/null 2>&1; then
    echo "$1 ne répond pas en SSH (admin + sudo) : rien n'est cassé." >&2
    return 1
  fi
}
