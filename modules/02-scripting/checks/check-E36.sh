# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
# check-E36.sh — M02-E36 « Panne : medictl ne parle plus à Proxmox » : état sain.
# Chaîne complète : fichier d'accès, TLS vérifié, authentification, autorisation, compte,
# puis medictl lui-même. Lecture seule (API en GET, pveum en lecture sur pve01).

title "M02-E36 — medictl parle à Proxmox"
require_cmd curl jq ssh openssl

_m02_e36_env="${MEDICTL_ENV_FILE:-$HOME/.config/workbook/pve-api.env}"

# _m02_e36_get CHEMIN — GET avec le jeton de pve-api.env ; corps sur la sortie standard.
_m02_e36_get() {
  # shellcheck source=/dev/null
  (source "$_m02_e36_env" \
    && printf 'Authorization: PVEAPIToken=%s=%s\n' "$PVE_TOKEN_ID" "$PVE_TOKEN_SECRET" \
    | curl -sf --max-time "${WB_TIMEOUT:-5}" --cacert "$PVE_CACERT" -H @- "$PVE_API_URL$1")
}

_m02_e36_mode_600() { [[ "$(stat -c %a "$_m02_e36_env" 2>/dev/null)" == 600 ]]; }

# La CA de adm01 peut être l'ancre « conforme » fabriquée en M02-E08 (même sujet et même
# clé que celle de pve01, extensions différentes) : on compare sujet et clé publique,
# pas le fichier ni son empreinte.
_m02_e36_ca_de_pve01() {
  local ca ici la_bas
  # shellcheck source=/dev/null
  ca="$(source "$_m02_e36_env" && printf '%s' "$PVE_CACERT")"
  [[ -f "$ca" ]] || return 1
  ici="$(openssl x509 -in "$ca" -noout -subject -pubkey 2>/dev/null)" || return 1
  la_bas="$(remote "$WB_PVE_HOST" 'openssl x509 -in /etc/pve/pve-root-ca.pem -noout -subject -pubkey')" || return 1
  [[ -n "$ici" && "$ici" == "$la_bas" ]]
}

_m02_e36_voit_le_pool() {
  _m02_e36_get '/cluster/resources?type=vm' | jq -e '[.data[] | select(.pool == "lab")] | length > 0' >/dev/null
}

_m02_e36_medictl() {
  medictl vm list --pool lab --format json 2>/dev/null | jq -e 'length > 0' >/dev/null
}

check_cmd "fichier d'accès $_m02_e36_env présent, mode 600" _m02_e36_mode_600
check_cmd "le fichier de CA de adm01 porte le sujet et la clé de la CA de pve01" _m02_e36_ca_de_pve01
check_cmd "API Proxmox : authentification par jeton acceptée (GET /version)" _m02_e36_get /version
check_cmd "API Proxmox : le jeton voit les VMs du pool lab" _m02_e36_voit_le_pool
check_ssh "pve01 : compte wb-automation@pve actif" "$WB_PVE_HOST" \
  'pveum user list --output-format json | perl -MJSON::PP -0777 -ne '"'"'for (@{decode_json($_)}) { exit(($_->{enable} // 1) ? 0 : 1) if $_->{userid} eq "wb-automation\@pve" } exit 1'"'"
check_ssh "pve01 : jeton wb-automation@pve!lab valide encore au moins 30 jours" "$WB_PVE_HOST" \
  'pveum user token list wb-automation@pve --output-format json | perl -MJSON::PP -0777 -ne '"'"'for (@{decode_json($_)}) { if ($_->{tokenid} eq "lab") { my $e = $_->{expire} // 0; exit(($e == 0 || $e > time() + 30*86400) ? 0 : 1) } } exit 1'"'"
check_ssh_output "pve01 : droits effectifs du jeton sur /pool/lab (création de VM)" "$WB_PVE_HOST" 'VM\.Allocate' \
  'pveum user token permissions wb-automation@pve lab --path /pool/lab'
check_cmd "medictl vm list --pool lab --format json renvoie des VMs" _m02_e36_medictl
