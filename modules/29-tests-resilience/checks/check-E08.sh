# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E08.sh — M29-E08 : Terratest : tester le module vm-debian
# À lancer depuis adm01. Lecture seule : fichiers de plateforme/tofu-modules (main), jobs de sa CI,
# consultation de pve01 (pvesh get, pveum … permissions), NetBox (lecture), go local (version).

# shellcheck source=_m29-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m29-operationnel.sh"

title "M29-E08 — Terratest : tester le module vm-debian"
require_cmd jq curl

check_cmd "Go 1.26 sur adm01" _m29d_version_outil go 'go1\.26\.'

# --- 1. Le test ---------------------------------------------------------------------------------------
_m29o_e08_mod="$(_m29d_contenu "$_M29O_P_MODULES" vm-debian/test/go.mod)"
check_cmd "vm-debian/test/go.mod : Go 1.26 et Terratest 1.0" bash -c '
  grep -Eq "^go 1\.26" <<<"$1" && grep -Eq "github.com/gruntwork-io/terratest v1\.0\." <<<"$1"' _ "$_m29o_e08_mod"
check_cmd "vm-debian/test/go.sum versionné (dépendances vérifiées)" _m29d_existe "$_M29O_P_MODULES" vm-debian/test/go.sum
_m29o_e08_go="$(for f in $(_m29d_arbre "$_M29O_P_MODULES" vm-debian/test | grep -E '\.go$' || true); do _m29d_contenu "$_M29O_P_MODULES" "$f"; done)"
check_cmd "test : binaire tofu imposé (TerraformBinary), pas « terraform » trouvé par hasard" bash -c 'grep -Eq "TerraformBinary: *\"tofu\"" <<<"$1"' _ "$_m29o_e08_go"
check_cmd "test : destruction garantie (defer ou t.Cleanup autour de terraform.Destroy)" bash -c '
  grep -Eq "(defer|t\.Cleanup\(func\(\) *\{?) *terraform\.Destroy" <<<"$1"' _ "$_m29o_e08_go"
check_cmd "test : VM nommée tt-<suffixe>, VMID 2290-2299" bash -c '
  grep -q "\"tt-\"" <<<"$1" && grep -q "2290" <<<"$1" && grep -q "2299" <<<"$1"' _ "$_m29o_e08_go"
check_cmd "test : vérifie SSH (cloud-init), étiquettes et agent QEMU" bash -c '
  grep -q "cloud-init status" <<<"$1" && grep -q "terratest" <<<"$1" && grep -q "agent" <<<"$1"' _ "$_m29o_e08_go"
check_cmd "test : étiquette de construction « integration » (go test ./… ne crée aucune VM)" bash -c 'grep -q "^//go:build integration" <<<"$1"' _ "$_m29o_e08_go"

# --- 2. La CI -----------------------------------------------------------------------------------------
_m29o_e08_ci="$(_m29d_contenu "$_M29O_P_MODULES" .gitlab-ci.yml)"
check_cmd "CI : job Terratest MANUEL, un seul à la fois (resource_group)" bash -c '
  grep -q "when: manual" <<<"$1" && grep -q "resource_group" <<<"$1" && grep -q -- "-tags integration" <<<"$1"' _ "$_m29o_e08_ci"
check_cmd "un job Terratest a RÉUSSI ces 30 derniers jours" _m29d_job_reussi "$_M29O_P_MODULES" 'terratest' 30

# --- 3. Identité Proxmox dédiée et propreté ------------------------------------------------------------
_m29o_e08_pools="$(_m29o_pve 'pvesh get /pools --output-format json')"
if [[ -z "$_m29o_e08_pools" ]]; then
  skip "pool et identité de Terratest sur pve01" "pve01 injoignable en SSH depuis adm01"
else
  check_cmd "pve01 : sous-pool lab/terratest" _m29d_json "$_m29o_e08_pools" 'any(.[]; .poolid == "lab/terratest")'
  _m29o_e08_lab="$(_m29o_pve "pveum user token permissions wb-terratest@pve terratest --path /pool/lab --output-format json")"
  _m29o_e08_tt="$(_m29o_pve "pveum user token permissions wb-terratest@pve terratest --path /pool/lab/terratest --output-format json")"
  check_cmd "jeton wb-terratest@pve!terratest : VM.Allocate sur /pool/lab/terratest" _m29d_json "$_m29o_e08_tt" \
    '[.. | objects | to_entries[] | select(.key == "VM.Allocate")] | length >= 1'
  check_cmd "jeton wb-terratest@pve!terratest : AUCUN droit d'écriture sur /pool/lab (le reste du lab)" \
    bash -c '[[ -n "$1" ]] && ! jq -e "[.. | objects | to_entries[] | select(.key | test(\"^VM\\\\.(Allocate|Config|PowerMgmt)\"))] | length > 0" <<<"$1" >/dev/null 2>&1' \
    _ "$_m29o_e08_lab"
  _m29o_e08_vms="$(_m29o_pve 'pvesh get /cluster/resources --type vm --output-format json')"
  _m29o_e08_orph="$(jq -r '[.[] | select((.vmid >= 2290 and .vmid <= 2299) or ((.tags // "") | test("terratest")))
      | "\(.vmid) \(.name)"] | join(", ")' <<<"${_m29o_e08_vms:-[]}" 2>/dev/null || true)"
  _m29o_e08_encours="$(gitlab_api "projects/$(_m29d_uri "$_M29O_P_MODULES")/jobs?scope%5B%5D=running&per_page=20" 2>/dev/null \
    | jq -r 'any(.[]; .name | test("terratest"))' 2>/dev/null || echo false)"
  if [[ "$_m29o_e08_encours" == "true" ]]; then
    skip "VMs de test restées dans Proxmox" "un job Terratest est EN COURS"
  else
    check_cmd "aucune VM de test restée dans Proxmox (2290-2299, étiquette terratest) : ${_m29o_e08_orph:-aucune}" \
      bash -c '[[ -z "$1" ]]' _ "$_m29o_e08_orph"
  fi
fi
_m29o_e08_nb="$(netbox_api 'virtualization/virtual-machines/?tag=terratest&limit=50' 2>/dev/null || true)"
check_cmd "NetBox : étiquette terratest définie, et aucune VM de test restée (adresses rendues)" _m29d_json "$_m29o_e08_nb" '.count == 0'
check_cmd "plateforme/medisphere : RB-293 (VMs de test orphelines)" bash -c '[[ -n "$1" ]]' _ \
  "$(_m29d_arbre "$_M29D_P_DOC" docs/qualite/runbooks | grep -E '/RB-293-[^/]+\.md$' || true)"
