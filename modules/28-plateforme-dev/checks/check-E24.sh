# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E24.sh — M28-E24 « Sous le capot » : APIService des métriques externes servi par KEDA et
# disponible ; verbosité de KEDA revenue à la normale ; sous-le-capot.md. Lecture seule.

# shellcheck source=_m28-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m28-expert.sh"

title "M28-E24 — Sous le capot"
require_cmd kubectl jq curl

_m28_e24_verbosite() {
  kube -n keda get deploy keda-operator -o json 2>/dev/null | jq -e '
    [.spec.template.spec.containers[].args[]? | select(test("^--zap-log-level=(debug|[0-9]+)$"))] | length == 0' >/dev/null 2>&1
}
if _m28p_api_repond; then
  check_cmd "APIService v1beta1.external.metrics.k8s.io servi par KEDA (espace keda) et Available" _m28p_kq \
    '.spec.service.namespace == "keda" and any(.status.conditions[]?; .type == "Available" and .status == "True")' \
    apiservices v1beta1.external.metrics.k8s.io
  check_cmd "opérateur KEDA sans verbosité de débogage" _m28_e24_verbosite
else
  skip "APIService et KEDA" "l'API ne répond pas au compte des checks"
fi
check_cmd "sous-le-capot.md (main) : calcul de l'HPA, tolérance, stabilisation" _m28p_doc sous-le-capot 'ceil|⌈' 'tol[ée]rance' 'stabilisation'
check_cmd "sous-le-capot.md : chemin de la métrique externe et webhooks de Capsule" _m28p_doc sous-le-capot 'external\.metrics' 'APIService' 'failurePolicy|Fail'
