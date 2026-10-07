# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions évaluées par le bash -c
#
# check-E13.sh — M05-E13 : Écrire un module vm-debian réutilisable
# Lecture seule : copie de travail ~/src/tofu-modules. « tofu validate » et « tofu test »
# tournent sur une copie jetable du module : ta copie de travail n'est pas touchée.

# shellcheck source=_m05-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-operationnel.sh"

title "M05-E13 — Écrire un module vm-debian réutilisable"
require_cmd tofu git grep

_m05o_m="$_m05o_modules/vm-debian"
for _m05o_f in versions.tf variables.tf main.tf outputs.tf README.md; do
  check_cmd "vm-debian/$_m05o_f présent" test -s "$_m05o_m/$_m05o_f"
done
check_cmd "le module déclare ses providers (required_providers bpg/proxmox)" \
  bash -c 'grep -Eqs "source[[:space:]]*=[[:space:]]*\"bpg/proxmox\"" "$1"/*.tf' _ "$_m05o_m"
check_cmd "le module ne configure aucun provider (pas de bloc provider)" \
  bash -c '! grep -Eqs "^[[:space:]]*provider[[:space:]]+\"proxmox\"" "$1"/*.tf' _ "$_m05o_m"
check_cmd "VM par la ressource proxmox_virtual_environment_vm (jamais proxmox_vm)" \
  bash -c 'grep -Eqs "resource[[:space:]]+\"proxmox_virtual_environment_vm\"" "$1"/*.tf && ! grep -Eqs "resource[[:space:]]+\"proxmox_vm\"" "$1"/*.tf' _ "$_m05o_m"
check_cmd "image trouvée par étiquettes (gold, current) et non par VMID figé" \
  bash -c 'grep -qs "\"current\"" "$1"/*.tf && grep -qs "\"gold\"" "$1"/*.tf' _ "$_m05o_m"
check_cmd "clone complet (full = true)" \
  bash -c 'grep -Eqs "full[[:space:]]*=[[:space:]]*true" "$1"/*.tf' _ "$_m05o_m"
check_cmd "nouvelle image « current » sans recréation des VMs (ignore_changes sur clone)" \
  bash -c 'grep -Eqs "ignore_changes[[:space:]]*=[[:space:]]*\[[^]]*clone" "$1"/*.tf' _ "$_m05o_m"
check_cmd "toutes les variables ont une description" \
  bash -c 'v=$(grep -Ec "^variable " "$1/variables.tf"); d=$(grep -Ec "^[[:space:]]+description[[:space:]]*=" "$1/variables.tf"); [ "$v" -gt 0 ] && [ "$d" -ge "$v" ]' _ "$_m05o_m"
check_cmd "au moins trois validations de variables" \
  bash -c '[ "$(grep -Ec "^[[:space:]]+validation[[:space:]]*\{" "$1/variables.tf")" -ge 3 ]' _ "$_m05o_m"
for _m05o_o in vm_id nom ipv4; do
  check_cmd "sortie $_m05o_o" bash -c 'grep -Eqs "^output[[:space:]]+\"$2\"" "$1"/*.tf' _ "$_m05o_m" "$_m05o_o"
done
check_cmd "README généré par terraform-docs (marqueurs BEGIN_TF_DOCS/END_TF_DOCS)" \
  bash -c 'grep -q "BEGIN_TF_DOCS" "$1/README.md" && grep -q "END_TF_DOCS" "$1/README.md"' _ "$_m05o_m"
if command -v terraform-docs >/dev/null 2>&1; then
  check_cmd "README à jour par rapport au code (terraform-docs --output-check)" \
    bash -c 'cd "$1" && terraform-docs --output-check vm-debian' _ "$_m05o_modules"
else
  skip "README à jour (terraform-docs --output-check)" "terraform-docs pas encore installé (M05-E20)"
fi
check_cmd "format canonique (tofu fmt -check)" bash -c 'cd "$1" && tofu fmt -check -recursive' _ "$_m05o_m"

# Copie jetable du module : « tofu init » écrirait sinon un .terraform.lock.hcl dans ta copie.
_m05o_valider() {
  local d="$1" t rc=0
  t="$(mktemp -d)"
  cp -r "$d/." "$t/" && rm -rf "$t/.terraform" "$t/.terraform.lock.hcl"
  (cd "$t" && tofu init -backend=false -input=false -no-color >/dev/null 2>&1 \
     && tofu "${@:2}" -no-color >/dev/null 2>&1) || rc=1
  rm -rf "$t"
  return "$rc"
}
check_cmd "le module est valide (tofu validate)" _m05o_valider "$_m05o_m" validate
if [[ -d "$_m05o_m/tests" ]]; then
  check_cmd "tests du module (tofu test, provider simulé)" _m05o_valider "$_m05o_m" test
else
  skip "tests du module (tofu test)" "pas de dossier tests/ : facultatif, voir « Pour aller plus loin »"
fi
check_cmd "Git : module commité, copie de travail propre" \
  bash -c 'git -C "$1" rev-parse -q --verify HEAD >/dev/null && [ -z "$(git -C "$1" status --porcelain -- vm-debian)" ]' _ "$_m05o_modules"
