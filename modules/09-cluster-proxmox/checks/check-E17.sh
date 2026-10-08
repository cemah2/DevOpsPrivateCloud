# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes entre apostrophes : pas d'expansion voulue
#
# check-E17.sh — M09-E17 : Droits, pools et jetons du cluster
# À lancer depuis adm01. Lecture seule : pools, groupes, ACL, rôles, droits effectifs (pveum … permissions),
# un GET /version avec le jeton (lu dans pve-tofu-hv.env, passé à curl par l'entrée standard).

# shellcheck source=_m09-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-operationnel.sh"

title "M09-E17 — Droits, pools et jetons du cluster"
require_cmd jq curl

_m09o_n="$(_m09o_noeud)"
_m09o_tmp="$(mktemp -d)"
trap 'rm -rf "$_m09o_tmp"' EXIT

# --- Pools ---------------------------------------------------------------------------------------------
_m09o_p="$(_m09o_pvesh /pools --poolid prod)"
check_cmd "pool prod : app01-03 (101-103) et rep01 (110)" _m09o_json "$_m09o_p" \
  '[.[0].members[]? | .vmid] as $m | all(101, 102, 103, 110; . as $i | $m | index($i) != null)'
check_cmd "pool recette existe" _m09o_json "$(_m09o_pvesh /pools)" 'map(select(.poolid == "recette")) | length == 1'

# --- Groupes et comptes ----------------------------------------------------------------------------------
_m09o_ga="$(_m09o_pvesh /access/groups/hv-admins)"
_m09o_go="$(_m09o_pvesh /access/groups/hv-ops)"
if [[ -n "${WB_MOI:-}" ]]; then
  check_cmd "groupe hv-admins : contient ${WB_MOI}@pve" _m09o_json "$_m09o_ga" '(.members // []) | index($u) != null' --arg u "${WB_MOI}@pve"
else
  check_cmd "groupe hv-admins : contient au moins un compte nominatif @pve (WB_MOI vide dans lab.env)" _m09o_json "$_m09o_ga" \
    '(.members // []) | map(select(endswith("@pve"))) | length > 0'
fi
check_cmd "groupe hv-ops : contient nadia.roussel@pve" _m09o_json "$_m09o_go" '(.members // []) | index("nadia.roussel@pve") != null'

_m09o_perm() { # _m09o_perm UTILISATEUR CHEMIN — droits effectifs (JSON {chemin: {privilège: 1}})
  _m09o_hv "$_m09o_n" "pveum user permissions '$1' --path '$2' --output-format json"
}
check_cmd "nadia.roussel@pve : démarrer/arrêter et console sur une VM de prod (VM.PowerMgmt, VM.Console)" _m09o_json \
  "$(_m09o_perm nadia.roussel@pve /vms/101)" '[.[] | keys[]] | index("VM.PowerMgmt") != null and index("VM.Console") != null'
check_cmd "nadia.roussel@pve : ni création ni suppression (pas de VM.Allocate) sur une VM de prod" _m09o_json \
  "$(_m09o_perm nadia.roussel@pve /vms/101)" '([.[] | keys[]] | length > 0) and ([.[] | keys[]] | index("VM.Allocate") == null)'
check_cmd "nadia.roussel@pve : pas de Sys.Modify ni Sys.Console sur un nœud" _m09o_json \
  "$(_m09o_perm nadia.roussel@pve /nodes/hv01)" '[.[] | keys[]] | index("Sys.Modify") == null and index("Sys.Console") == null'

# --- Rôle et jeton d'OpenTofu ------------------------------------------------------------------------------
_m09o_r="$(_m09o_pvesh /access/roles/WBTofuHV)"
check_cmd "rôle WBTofuHV : contient VM.PowerMgmt, VM.Clone, VM.Allocate" _m09o_json "$_m09o_r" \
  'has("VM.PowerMgmt") and has("VM.Clone") and has("VM.Allocate")'
check_cmd "rôle WBTofuHV : aucun Sys.*, Permissions.*, Datastore.Allocate, Pool.Allocate" _m09o_json "$_m09o_r" \
  '(keys | length > 0) and (keys | map(select(startswith("Sys.") or startswith("Permissions.")
     or . == "Datastore.Allocate" or . == "Pool.Allocate")) | length == 0)'
check_cmd "jeton wb-tofu-hv@pve!tofu : privilèges séparés, avec expiration future" _m09o_json \
  "$(_m09o_pvesh /access/users/wb-tofu-hv@pve/token/tofu)" \
  '((.privsep // 1) | tostring | test("^(1|true)$")) and ((.expire // 0) > now)'
_m09o_tperm() { _m09o_hv "$_m09o_n" "pveum user token permissions wb-tofu-hv@pve tofu --path '$1' --output-format json"; }
check_cmd "jeton : aucun droit sur /" _m09o_json "$(_m09o_tperm /)" '[.[] | keys[]] | length == 0'
check_cmd "jeton : aucun droit sur /pool/prod" _m09o_json "$(_m09o_tperm /pool/prod)" '[.[] | keys[]] | length == 0'
check_cmd "jeton : VM.Allocate et VM.PowerMgmt sur /pool/recette" _m09o_json "$(_m09o_tperm /pool/recette)" \
  '[.[] | keys[]] | index("VM.Allocate") != null and index("VM.PowerMgmt") != null'

# --- Fichier d'accès sur adm01 et appel réel ---------------------------------------------------------------
_m09o_env="$HOME/.config/workbook/pve-tofu-hv.env"
check_cmd "pve-tofu-hv.env existe et est en 600" bash -c '[[ -s "$1" && "$(stat -c %a "$1")" == 600 ]]' _ "$_m09o_env"
# Valeurs lues sans exécuter le fichier.
_m09o_val() { sed -nE "s/^(export[[:space:]]+)?$1=\"?([^\"]*)\"?.*/\\2/p" "$_m09o_env" 2>/dev/null | head -n 1 || true; }
_m09o_url="$(_m09o_val PROXMOX_VE_ENDPOINT)"
# L'autorité du cluster (publique) sert d'ancre : elle n'est dans le magasin système qu'à partir d'E18.
# Après M09-E26, le certificat vient de la PKI MédiSphère : le magasin système est ajouté à l'ancre.
{ cat /etc/ssl/certs/ca-certificates.crt 2>/dev/null; _m09o_hv "$_m09o_n" 'cat /etc/pve/pve-root-ca.pem'; } >"$_m09o_tmp/ca.pem"
_m09o_code="$(printf 'Authorization: PVEAPIToken=%s\n' "$(_m09o_val PROXMOX_VE_API_TOKEN)" \
  | curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" --cacert "$_m09o_tmp/ca.pem" -H @- \
      "${_m09o_url%/}/api2/json/version" 2>/dev/null || true)"
check_output "le jeton répond à l'API du cluster depuis adm01 (${_m09o_url:-PROXMOX_VE_ENDPOINT absent}, HTTP ${_m09o_code:-—})" '^200$' echo "$_m09o_code"
check_output "PROXMOX_VE_API_TOKEN désigne bien wb-tofu-hv@pve!tofu" '^wb-tofu-hv@pve!tofu=' _m09o_val PROXMOX_VE_API_TOKEN
