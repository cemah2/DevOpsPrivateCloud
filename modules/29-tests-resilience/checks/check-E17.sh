# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E17.sh — M29-E17 « ADR : outillage de tests et de chaos » : présence et contenu minimal de
# l'ADR-0290 (les cinq décisions et l'exception chaos-experiences). Le fond s'auto-évalue avec le corrigé.

# shellcheck source=_m29-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m29-production.sh"

title "M29-E17 — ADR-0290"
require_cmd jq curl

check_cmd "ADR-0290 publié (main) : statut, contexte, décision, conséquences" \
  _m29p_doc docs/qualite/adr '^ADR-0290' '^#+ .*Contexte' '^#+ .*D[ée]cision' '^#+ .*Cons[ée]quences' 'statut'
check_cmd "ADR-0290 : chaos (Chaos Mesh retenu, LitmusChaos écarté)" _m29p_doc docs/qualite/adr '^ADR-0290' 'Chaos Mesh' 'Litmus'
check_cmd "ADR-0290 : charge (k6, k6-operator)" _m29p_doc docs/qualite/adr '^ADR-0290' 'k6-operator'
check_cmd "ADR-0290 : tests d'infrastructure (Testinfra, Goss, Terratest)" _m29p_doc docs/qualite/adr '^ADR-0290' 'Testinfra' 'Goss' 'Terratest'
check_cmd "ADR-0290 : validation statique (kubeconform, conftest, Kyverno)" _m29p_doc docs/qualite/adr '^ADR-0290' 'kubeconform' 'conftest' 'Kyverno'
check_cmd "ADR-0290 : exception chaos-experiences hors GitOps encadrée" _m29p_doc docs/qualite/adr '^ADR-0290' 'chaos-experiences' 'Argo CD' 'exception'
