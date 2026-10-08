# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E08.sh — M11-E08 : Piloter l'alimentation par API
# À lancer depuis adm01. Lecture seule : droits Proxmox lus en root sur pve01, une lecture de
# /cluster/resources avec le jeton wb-maas@pve!maas, contenu de main. Aucune action d'alimentation.

# shellcheck source=_m11-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m11-operationnel.sh"

title "M11-E08 — Piloter l'alimentation par API"
require_cmd jq curl

# --- Le jeton et ce qu'il voit --------------------------------------------------------------------------
check_cmd "pve-maas.env présent, en mode 600" _m11o_mode600 "$_M11O_PVE_MAAS_ENV"
check_output "pve-maas.env : jeton wb-maas@pve!maas" '^wb-maas@pve!maas$' _m11o_lire "$_M11O_PVE_MAAS_ENV" PVE_TOKEN_ID
_m11o_vus="$(_m11o_pve_maas '/cluster/resources?type=vm' | jq -r '[.data[].name] | sort | join(" ")' 2>/dev/null || true)"
check_output "le jeton voit exactement bm01, bm02, bm03, bm04 (${_m11o_vus:-rien})" '^bm01 bm02 bm03 bm04$' echo "$_m11o_vus"

# --- Rôle, ACL, séparation des privilèges (lus en root sur pve01) ----------------------------------------------
_m11o_roles="$(remote "$_M11O_PVE" 'pveum role list --output-format json' 2>/dev/null || true)"
check_output "rôle WBMaas : exactement VM.Audit et VM.PowerMgmt" '^VM\.Audit,VM\.PowerMgmt$' \
  jq -r '.[] | select(.roleid == "WBMaas") | .privs | split(",") | map(gsub(" "; "")) | sort | join(",")' <<<"$_m11o_roles"
_m11o_acl="$(remote "$_M11O_PVE" 'pveum acl list --output-format json' 2>/dev/null || true)"
check_output "ACL WBMaas : seulement /vms/2112 à /vms/2115" '^/vms/2112 /vms/2113 /vms/2114 /vms/2115$' \
  jq -r '[.[] | select(.roleid == "WBMaas") | .path] | unique | sort | join(" ")' <<<"$_m11o_acl"
check_cmd "ACL WBMaas : posées pour l'utilisateur ET pour le jeton, sur chacune des quatre VMs" \
  jq -e '[.[] | select(.roleid == "WBMaas")] as $a
         | ["2112","2113","2114","2115"] | all(. as $v |
             ($a | map(select(.path == "/vms/" + $v and .ugid == "wb-maas@pve")) | length == 1)
             and ($a | map(select(.path == "/vms/" + $v and .ugid == "wb-maas@pve!maas")) | length == 1))' <<<"$_m11o_acl"
check_cmd "aucun autre rôle n'est donné à wb-maas (ni à son jeton)" \
  jq -e '[.[] | select((.ugid | startswith("wb-maas@pve")) and .roleid != "WBMaas")] | length == 0' <<<"$_m11o_acl"
_m11o_privsep() {
  remote "$_M11O_PVE" 'pveum user token list wb-maas@pve --output-format json' 2>/dev/null \
    | jq -r '.[] | select(.tokenid == "maas") | .privsep'
}
check_output "jeton maas : séparation des privilèges active" '^1$' _m11o_privsep

# --- L'outil ----------------------------------------------------------------------------------------------------
_m11o_alim="$(_m11o_contenu_main "$_M11O_PROJET_PROV" outils/alim.sh)"
check_output "plateforme/provisioning : outils/alim.sh sur main" 'hp01' echo "$_m11o_alim"
check_cmd "outils/alim.sh : jamais de vérification TLS désactivée (-k, --insecure)" \
  bash -c '[ -n "$1" ] && ! grep -Eq -- "(^|[[:space:]])(-k|--insecure)([[:space:]]|$)" <<<"$1"' _ "$_m11o_alim"
if command -v shellcheck >/dev/null 2>&1; then
  check_cmd "outils/alim.sh : ShellCheck sans avertissement" \
    bash -c 'f="$(mktemp)"; printf "%s\n" "$1" >"$f"; shellcheck -S warning "$f"; r=$?; rm -f "$f"; exit $r' _ "$_m11o_alim"
else
  skip "ShellCheck de alim.sh" "shellcheck absent de adm01"
fi
check_output "plateforme/provisioning : dernier pipeline de main réussi" '^success$' _m11o_pipeline_main "$_M11O_PROJET_PROV"

# --- wb-redfish n'a pas gardé de droit d'alimentation ------------------------------------------------------------
_m11o_fiche=""
for _m11o_m in $(_m11o_redfish /redfish/v1/AccountService/Accounts/ 2>/dev/null | jq -r '.Members[]?["@odata.id"]' 2>/dev/null || true); do
  _m11o_c="$(_m11o_redfish "$_m11o_m" || true)"
  if [[ "$(jq -r '.UserName // empty' <<<"$_m11o_c" 2>/dev/null)" == wb-redfish ]]; then _m11o_fiche="$_m11o_c"; fi
done
if [[ -n "$_m11o_fiche" ]]; then
  check_cmd "wb-redfish : pas de privilège « Virtual Power and Reset »" \
    jq -e '(.Oem.Hp.Privileges.VirtualPowerAndResetPriv // false) | not' <<<"$_m11o_fiche"
else
  skip "privilèges de wb-redfish" "fiche du compte non lisible avec ce compte"
fi
check_cmd "registre des secrets : jeton wb-maas inscrit" grep -q 'wb-maas' "$_M11O_REGISTRE"
