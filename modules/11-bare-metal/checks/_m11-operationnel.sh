# shellcheck shell=bash
# _m11-operationnel.sh — fonctions partagées par les checks M11-E06 à M11-E10 (lecture seule).
# Sourcé par les check-EXX.sh concernés (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m11o_ : pas de collision avec les fonctions des autres paliers.
# Rappels : les checks tournent sous « set -euo pipefail » (lab/bin/check) ; les secrets (jetons,
# mots de passe, clé MAAS) sont lus dans leurs fichiers SANS les exécuter et passés à curl par un
# fichier du dossier temporaire (700) ou par l'entrée standard : jamais dans ps ni dans la sortie.

_M11O_CFG="$HOME/.config/workbook"
_M11O_PVE="${WB_PVE_HOST:-pve01}"
_M11O_NB="${WB_NETBOX_URL:-https://nbx01.par1.medisphere.internal}"
_M11O_PROJET_PROV="projects/plateforme%2Fprovisioning"
_M11O_PROJET_ANSIBLE="projects/plateforme%2Fansible"
_M11O_PXE_URL="http://pxe01.par1.medisphere.internal"
# HTTPS à partir de M11-E13 (le port 80 ne fait plus que rediriger) : HTTPS d'abord.
_M11O_PXE_URLS="https://pxe01.par1.medisphere.internal $_M11O_PXE_URL"

# _m11o_http CHEMIN — contenu servi par pxe01 (HTTPS d'abord), vide sinon.
_m11o_http() {
  local u
  for u in $_M11O_PXE_URLS; do
    if curl -sf --max-time "$WB_TIMEOUT" --proto-redir '-all' "$u/$1" 2>/dev/null; then return 0; fi
  done
  return 0
}
_M11O_ILO_ENV="${WB_ILO_ENV_FILE:-$_M11O_CFG/ilo-hp01.env}"
_M11O_ILO_PEM="$_M11O_CFG/ilo-hp01.pem"
_M11O_PVE_MAAS_ENV="$_M11O_CFG/pve-maas.env"
_M11O_MAAS_URL="${WB_MAAS_URL:-http://10.10.60.11:5240/MAAS}"
_M11O_MAAS_CLE="${WB_MAAS_KEY_FILE:-$_M11O_CFG/maas-api.key}"
_M11O_REGISTRE="${WB_DEPOT:-$HOME/medisphere}/docs/socle/registre-secrets.md"

_M11O_TMP="$(mktemp -d)"
chmod 700 "$_M11O_TMP"
trap 'rm -rf "$_M11O_TMP"' EXIT

# Serveurs nus : nom VMID MAC
_M11O_BM="bm01 2112 02:4d:53:60:00:01
bm02 2113 02:4d:53:60:00:02
bm03 2114 02:4d:53:60:00:03
bm04 2115 02:4d:53:60:00:04"

# _m11o_mode600 FICHIER — existe, non vide, mode 600.
_m11o_mode600() {
  [[ -s "$1" && "$(stat -c %a "$1" 2>/dev/null)" == 600 ]]
}

# _m11o_lire FICHIER CLÉ — valeur de CLÉ=… (guillemets facultatifs), sans exécuter le fichier.
_m11o_lire() {
  sed -nE "s/^[[:space:]]*(export[[:space:]]+)?$2=\"?([^\"]*)\"?[[:space:]]*(#.*)?\$/\\2/p" "$1" 2>/dev/null | tail -n 1 || true
}

# _m11o_nb FICHIER_JETON CHEMIN — GET NetBox avec un jeton v2 (fichier d'une ligne nbt_…).
_m11o_nb() {
  [[ -r "$1" ]] || return 1
  printf 'Authorization: Bearer %s\n' "$(tr -d '\n' <"$1")" >"$_M11O_TMP/nb"
  curl -sf --max-time "$WB_TIMEOUT" -H @"$_M11O_TMP/nb" -H 'Accept: application/json' "$_M11O_NB/api/$2"
}

# _m11o_nb_checks CHEMIN — GET NetBox avec le jeton en lecture des checks.
_m11o_nb_checks() {
  _m11o_nb "${WB_NETBOX_TOKEN_FILE:-$_M11O_CFG/netbox-checks.token}" "$1"
}

# _m11o_nb_ansible CHEMIN — GET NetBox avec le jeton de lecture de svc-automatisation (netbox-ansible.env).
_m11o_nb_ansible() {
  local j
  j="$(_m11o_lire "$_M11O_CFG/netbox-ansible.env" NETBOX_TOKEN)"
  [[ -n "$j" ]] || return 1
  printf '%s\n' "$j" >"$_M11O_TMP/jeton-ansible"
  _m11o_nb "$_M11O_TMP/jeton-ansible" "$1"
}

# _m11o_kea HÔTE — configuration CHARGÉE par kea-dhcp4 (config-get, socket UNIX), JSON ou vide.
_m11o_kea() {
  remote "$1" 'printf "{ \"command\": \"config-get\" }" | sudo -n socat - UNIX-CONNECT:/run/kea/kea4-ctrl-socket' 2>/dev/null || true
}

# _m11o_contenu_main PROJET CHEMIN — contenu brut d'un fichier sur main (vide si absent).
_m11o_contenu_main() {
  local chemin
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "$1/repository/files/$chemin/raw?ref=main" 2>/dev/null || true
}

# _m11o_fichier_main PROJET CHEMIN — le fichier existe sur main.
_m11o_fichier_main() {
  local chemin
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "$1/repository/files/$chemin?ref=main" >/dev/null 2>&1
}

# _m11o_pipeline_main PROJET — statut du dernier pipeline de main (success, failed…), vide sinon.
_m11o_pipeline_main() {
  gitlab_api "$1/pipelines?ref=main&per_page=1" 2>/dev/null | jq -r '.[0].status // empty' 2>/dev/null || true
}

# _m11o_redfish CHEMIN — GET Redfish sur l'iLO de hp01 avec wb-redfish, TLS épinglé (jamais -k).
_m11o_redfish() {
  local hote nom u p
  [[ -r "$_M11O_ILO_ENV" && -r "$_M11O_ILO_PEM" ]] || return 1
  hote="$(_m11o_lire "$_M11O_ILO_ENV" ILO_HOST)"; nom="$(_m11o_lire "$_M11O_ILO_ENV" ILO_NOM_TLS)"
  u="$(_m11o_lire "$_M11O_ILO_ENV" ILO_USER)"; p="$(_m11o_lire "$_M11O_ILO_ENV" ILO_PASSWORD)"
  [[ -n "$hote" && -n "$nom" && -n "$u" && -n "$p" ]] || return 1
  p="${p//\\/\\\\}"; p="${p//\"/\\\"}"
  printf 'user = "%s:%s"\n' "$u" "$p" \
    | curl -sf --max-time 20 --proto '=https' --cacert "$_M11O_ILO_PEM" --resolve "$nom:443:$hote" \
        -H 'Accept: application/json' -K - "https://$nom$1"
}

# _m11o_pve_maas CHEMIN — GET sur l'API Proxmox avec le jeton wb-maas@pve!maas (pve-maas.env).
_m11o_pve_maas() {
  local url id sec ca
  url="$(_m11o_lire "$_M11O_PVE_MAAS_ENV" PVE_API_URL)"; id="$(_m11o_lire "$_M11O_PVE_MAAS_ENV" PVE_TOKEN_ID)"
  sec="$(_m11o_lire "$_M11O_PVE_MAAS_ENV" PVE_TOKEN_SECRET)"; ca="$(_m11o_lire "$_M11O_PVE_MAAS_ENV" PVE_CACERT)"
  ca="${ca//\$HOME/$HOME}"
  [[ -n "$url" && -n "$id" && -n "$sec" && -r "$ca" ]] || return 1
  printf 'header = "Authorization: PVEAPIToken=%s=%s"\n' "$id" "$sec" \
    | curl -sf --max-time "$WB_TIMEOUT" --proto '=https' --cacert "$ca" -K - "$url$1"
}

# _m11o_maas CHEMIN — GET sur l'API 2.0 de MAAS avec la clé de maas-api.key (OAuth 1.0 PLAINTEXT).
# Clé = « consumer:token:secret » ; l'en-tête est écrit dans le dossier temporaire du check.
_m11o_maas() {
  local cle ck tk ts
  [[ -r "$_M11O_MAAS_CLE" ]] || return 1
  cle="$(tr -d '\n' <"$_M11O_MAAS_CLE")"
  IFS=: read -r ck tk ts <<<"$cle"
  [[ -n "$ck" && -n "$tk" && -n "$ts" ]] || return 1
  printf 'Authorization: OAuth oauth_version="1.0", oauth_signature_method="PLAINTEXT", oauth_consumer_key="%s", oauth_token="%s", oauth_signature="&%s", oauth_nonce="%s", oauth_timestamp="%s"\n' \
    "$ck" "$tk" "$ts" "$RANDOM$RANDOM$RANDOM" "$(date +%s)" >"$_M11O_TMP/maas"
  curl -sf --max-time "$WB_TIMEOUT" -H @"$_M11O_TMP/maas" -H 'Accept: application/json' "$_M11O_MAAS_URL/api/2.0/$1"
}
