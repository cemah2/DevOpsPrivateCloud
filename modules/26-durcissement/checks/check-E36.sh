# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E36.sh — M26-E36 « Un pod privilégié est passé » : le trou d'admission est refermé, rapports sans
# violation admise, pipeline vert, panne close. Lecture seule.
# shellcheck source=_m26-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-expert.sh"

title "M26-E36 — Le trou d'admission est refermé"
require_cmd jq kubectl

_e36_pas_exception_large() {
  ! kube get policyexceptions.policies.kyverno.io -A -o json 2>/dev/null |
    jq -e '[.items[]? | select((.spec.policyRefs[]?.name) == "registres-autorises")
      | select((.spec.matchConditions // []) | any(.expression | test("^\\s*object\\.metadata\\.namespace\\s*==\\s*.wb-pannes.\\s*$")))] | length > 0' >/dev/null 2>&1
}
_e36_pas_ns_privileged() {
  local ns
  for ns in mediagenda-dev mediagenda-recette mediagenda-prod medidoc-dev medidoc-recette; do
    [[ "$(_m26x_psa_enforce "$ns")" == privileged ]] && return 1
  done
  return 0
}
_e36_registres_couvre() {
  _m26x_kq '[.items[]? | select(.metadata.name | test("registre"))
            | select((.spec.matchConstraints.namespaceSelector.matchExpressions // []) | any(.operator == "NotIn" and (.values | index("wb-pannes"))))] | length == 0' \
    validatingpolicies.policies.kyverno.io
}
_e36_pas_violation_admise() {
  ! kube get policyreports.wgpolicyk8s.io -A -o json 2>/dev/null |
    jq -e '[.items[]? | select(.metadata.namespace | test("^(mediagenda|medidoc)-"))
      | .results[]? | select(.result == "fail" and (.properties.blocked // "true") == "false")] | length > 0' >/dev/null 2>&1
}

check_cmd "aucune exception Kyverno ne couvre un espace entier" _e36_pas_exception_large
check_cmd "aucun espace applicatif n'est étiqueté pod-security enforce: privileged" _e36_pas_ns_privileged
check_cmd "registres-autorises couvre bien wb-pannes" _e36_registres_couvre
check_cmd "les politiques s'appliquent à toutes les identités" _m26x_vp_sans_exemption_groupe
check_cmd "aucune violation « admise » dans les rapports des espaces applicatifs" _e36_pas_violation_admise
check_cmd "pipeline de main de plateforme/politiques vert" _m26x_pipeline_main_vert plateforme/politiques
check_cmd "panne M26-E36 close" _m26x_aucune_panne_active E36
