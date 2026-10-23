# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E35.sh — M26-E35 « Plus aucun déploiement ne passe en recette » : l'admission de mediagenda-recette
# est revenue à l'état sain (aucune garde trop large, aucun refus réseau total), rapports sans erreur,
# pipeline vert, panne close. Lecture seule.
# shellcheck source=_m26-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-expert.sh"

title "M26-E35 — Les déploiements passent de nouveau en recette"
require_cmd jq kubectl

_e35_pas_de_garde() { _m26x_vp_sans_condition exiger-change && _m26x_vp_sans_condition garde-recette; }
_e35_pas_de_fail_recette() {
  _m26x_kq '[.items[]? | select((.spec.failurePolicy // "Ignore") == "Fail")
            | select((.spec.matchConstraints.namespaceSelector.matchLabels["kubernetes.io/metadata.name"] // "") == "mediagenda-recette")] | length == 0' \
    validatingpolicies.policies.kyverno.io
}
_e35_pas_de_refus_total() {
  ! kube -n mediagenda-recette get ciliumnetworkpolicies,networkpolicies -o json 2>/dev/null |
    jq -e '[.items[]? | select((.metadata.labels["medisphere.internal/panne"] // "") == "M26-E35" or (.metadata.name | test("refus-total")))] | length > 0' >/dev/null 2>&1
}
_e35_recette_restricted() { [[ "$(_m26x_psa_enforce mediagenda-recette)" == restricted ]]; }
_e35_rapports_sans_erreur() {
  _m26x_kq '[.items[]? | .results[]? | select(.result == "error")] | length == 0' policyreports.wgpolicyk8s.io -n mediagenda-recette
}

check_cmd "les politiques de validation n'ont plus de condition ajoutée par la panne" _e35_pas_de_garde
check_cmd "aucune politique propre à la recette ne bloque quand elle ne peut pas décider" _e35_pas_de_fail_recette
check_cmd "le réseau de mediagenda-recette n'a pas de politique ajoutée par la panne" _e35_pas_de_refus_total
check_cmd "l'espace mediagenda-recette est bien en PSA restricted" _e35_recette_restricted
check_cmd "les rapports de politiques de recette sont sans erreur d'évaluation" _e35_rapports_sans_erreur
check_cmd "pipeline de main de plateforme/politiques vert" _m26x_pipeline_main_vert plateforme/politiques
check_cmd "RB du palier : section sur une admission qui refuse tout" \
  _m26x_doc_contient "$_m26x_rb/RB-26*.md" '(refuse tout|plus aucun d[ée]ploiement|admission)'
check_cmd "panne M26-E35 close (lab/bin/break 26 35 --annuler après réparation)" _m26x_aucune_panne_active E35
