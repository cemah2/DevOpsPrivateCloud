# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et yq entre apostrophes
# check-E19.sh — M29-E19 « Panne : un plan dangereux passe la CI » : le plan de référence est refusé par
# les politiques de main avec les arguments de la CI de plateforme/infra ; paquets évalués ; aucun job de
# validation en allow_failure ; test de non-régression sur un plan réel dans plateforme/politiques ;
# panne close. Lecture seule (copie temporaire des politiques, conftest et opa en local).

# shellcheck source=_m29-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m29-expert.sh"

title "M29-E19 — Le plan dangereux est de nouveau refusé"
require_cmd jq curl yq conftest opa

check_cmd "plan de référence refusé par rego/tofu (main) avec les arguments du job de plan (espaces, données, contexte ${WB_M29_E19_ETAT:-socle})" _m29x_plan_refuse
check_cmd "tous les paquets des règles de rego/tofu sont dans les espaces évalués par la CI" _m29x_paquets_evalues
# Racines explicites, comme le composant validation : « opa test rego » chargerait aussi les plans
# d'exemple JSON de rego/exemples/ comme des données (conflit de fusion).
_m29_e19_opa() {
  local d
  local -a r
  d="$(_m29x_rapatrier_rego)" || return 1
  r=("$d/rego/tofu")
  [[ -d "$d/rego/donnees" ]] && r+=("$d/rego/donnees")
  opa test "${r[@]}" >/dev/null 2>&1 || return 1
  [[ ! -d "$d/rego/kubernetes" ]] || opa test "$d/rego/kubernetes" >/dev/null 2>&1
}
check_cmd "opa test vert sur rego/tofu (+ rego/donnees) et rego/kubernetes (main)" _m29_e19_opa
check_cmd "plateforme/infra : aucun job de validation ni de plan (.plan, plan:*) en allow_failure: true" _m29x_sans_allow_failure "$_m29x_infra"
_m29_e19_composant() {
  _m29p_fichier_main "$_m29x_ci" "$_m29x_composant" 2>/dev/null |
    yq -e '[select(document_index == 1) | to_entries[] | select(.value.allow_failure == true)] | length == 0' >/dev/null 2>&1
}
check_cmd "composant validation (main de ci-templates) : aucun job en allow_failure: true" _m29_e19_composant

# Test de non-régression : un plan JSON réel (resource_changes) versionné ET utilisé par la CI.
_m29_e19_non_regression() {
  local f ci
  ci="$(_m29p_fichier_main "$_m29x_politiques" .gitlab-ci.yml 2>/dev/null)" || return 1
  while IFS= read -r f; do
    [[ "$f" == *.json ]] || continue
    _m29p_fichier_main "$_m29x_politiques" "$f" 2>/dev/null | jq -e '.resource_changes | length > 0' >/dev/null 2>&1 || continue
    grep -qF "$(basename "$f")" <<<"$ci" && return 0
  done < <(_m29p_arbre "$_m29x_politiques")
  return 1
}
check_cmd "plateforme/politiques : un plan réel versionné, rejoué par la CI (non-régression)" _m29_e19_non_regression
check_cmd "panne M29-E19 close (lab/bin/break 29 19 --annuler après réparation)" _m29x_aucune_panne_active E19
