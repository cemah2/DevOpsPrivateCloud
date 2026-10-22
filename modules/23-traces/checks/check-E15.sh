# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E15.sh — M23-E15 « Jaeger v2 en comparaison » : comparatif rédigé, essai entièrement retiré.
# Lecture seule.

# shellcheck source=_m23-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m23-production.sh"

title "M23-E15 — Jaeger v2 en comparaison (puis retiré)"
require_cmd kubectl jq curl

check_cmd "comparatif docs/observabilite/traces/comparatif-jaeger.md : stockage, requêtes, ressources, décision" \
  _m23p_doc docs/observabilite/traces comparatif-jaeger 'stockage' 'TraceQL' 'm[ée]moire|ressources' 'd[ée]cision'
check_cmd "comparatif : mesures relevées pendant l'essai (Mi, Go ou m de CPU)" \
  _m23p_doc docs/observabilite/traces comparatif-jaeger '[0-9]+ ?(Mi|Gi|Mo|Go|m\b|millic)'
_m23_e15_absent() {
  kube get namespace default >/dev/null 2>&1 || return 1 # API joignable, sinon on ne conclut rien
  ! kube get namespace jaeger-essai >/dev/null 2>&1
}
check_cmd "espace jaeger-essai supprimé" _m23_e15_absent
check_cmd "aucune Application Argo CD ne déploie encore dans jaeger-essai" \
  _m23p_kq '[.items[] | select(.spec.destination.namespace == "jaeger-essai")] | length == 0' -n argocd applications.argoproj.io
check_cmd "passerelle : plus aucun exportateur vers Jaeger" \
  _m23p_config_collector "$_m23p_passerelle" '[.exporters | to_entries[] | select((.key | test("jaeger"; "i")) or ((.value.endpoint? // "") | test("jaeger"; "i")))] | length == 0'
check_cmd "passerelle : aucun pipeline ne référence un exportateur absent" \
  _m23p_config_collector "$_m23p_passerelle" '(.exporters | keys) as $e | all(.service.pipelines[]; all(.exporters[]; . as $x | $e | index($x) != null))'
