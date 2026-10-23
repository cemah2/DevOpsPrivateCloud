# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E17.sh — M28-E17 « ADR : la plateforme développeurs » : présence de l'ADR-0280 et de ses rubriques
# (le fond s'auto-évalue avec le corrigé). Lecture seule.

# shellcheck source=_m28-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m28-production.sh"

title "M28-E17 — ADR-0280"
require_cmd jq curl

check_cmd "ADR-0280 publié (main) : portail Backstage" _m28p_doc ADR-0280 'Backstage'
check_cmd "ADR-0280 : Capsule et vCluster comparés" _m28p_doc ADR-0280 'Capsule' 'vCluster'
check_cmd "ADR-0280 : HPA, KEDA, VPA en recommandation" _m28p_doc ADR-0280 'HPA' 'KEDA' 'VPA'
check_cmd "ADR-0280 : Crossplane et Tilt/Skaffold écartés" _m28p_doc ADR-0280 'Crossplane' 'Tilt|Skaffold'
check_cmd "ADR-0280 : risques et révision" _m28p_doc ADR-0280 'risque' 'r[ée]vision'
