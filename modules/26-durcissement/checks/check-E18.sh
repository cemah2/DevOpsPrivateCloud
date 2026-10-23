# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E18.sh — M26-E18 : exceptions et rapports de politiques
# À lancer depuis adm01. Lecture seule : contrôleurs et objets de Kyverno, rapports (compte wb-checks,
# wb-checks-securite), règles et métriques (Prometheus), tableau (Grafana), dépôt et jobs (GitLab).
# Ce qui est vérifié : exceptions activées et confinées à kyverno-exceptions ; chaque exception datée
# (future, ≤ 92 jours), conditionnée et justifiée ; plus aucun échec exiger-digest en production ;
# métriques collectées, alertes chargées, tableau provisionné ; contrôle des exceptions en CI.

# shellcheck source=_m26-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-operationnel.sh"

title "M26-E18 — Exceptions et rapports de politiques"
require_cmd jq kubectl curl

# --- Activation -----------------------------------------------------------------------------------
_m26c_e18_dep="$(_m26c_k get deployments -n kyverno -o json)"
for _m26c_e18_c in admission-controller background-controller reports-controller; do
  check_cmd "contrôleur Kyverno $_m26c_e18_c : exceptions activées, lues dans kyverno-exceptions seulement" \
    _m26c_json "$_m26c_e18_dep" --arg c "$_m26c_e18_c" '
      [.items[] | select(.metadata.labels["app.kubernetes.io/component"] == $c)
       | [.spec.template.spec.containers[].args[]?] ] as $a
      | ($a | length) >= 1 and ($a | all(index("--enablePolicyException=true") and index("--exceptionNamespace=kyverno-exceptions")))'
done
check_cmd "espace kyverno-exceptions présent" kube get namespace kyverno-exceptions

# --- Exceptions -----------------------------------------------------------------------------------
_m26c_e18_exc="$(_m26c_k get policyexceptions.policies.kyverno.io -A -o json)"
check_cmd "aucune PolicyException hors de kyverno-exceptions (Kyverno les ignorerait, sans erreur)" \
  _m26c_json "$_m26c_e18_exc" '.items | length >= 1 and all(.metadata.namespace == "kyverno-exceptions")'
check_cmd "aucune ancienne PolicyException kyverno.io (dépréciée en 1.19)" \
  _m26c_json "$(_m26c_k get policyexceptions.kyverno.io -A -o json)" '.items | length == 0'
check_cmd "chaque exception a une échéance future à 92 jours au plus" \
  _m26c_json "$_m26c_e18_exc" '[.items[] | .spec.expiresAt // "" | (try fromdateiso8601 catch 0)]
    | length >= 1 and all(. > now and . <= now + 92 * 86400)'
check_cmd "chaque exception a au moins une matchCondition (sinon elle vaut pour tout le périmètre de la politique)" \
  _m26c_json "$_m26c_e18_exc" '.items | length >= 1 and all((.spec.matchConditions // []) | length >= 1)'
check_cmd "chaque exception porte les propriétés raison, ticket, valideur" \
  _m26c_json "$_m26c_e18_exc" '.items | length >= 1
    and all(.spec.properties // {} | (.raison // "") != "" and (.ticket // "") != "" and (.valideur // "") != "")'

# --- Rapports -------------------------------------------------------------------------------------
check_cmd "rapports de mediagenda-prod : aucun échec exiger-digest (corrigé ou exempté)" \
  _m26c_json "$(_m26c_k get policyreports.wgpolicyk8s.io -n mediagenda-prod -o json)" '
    (.items | length) >= 1 and ([.items[].results[]? | select(.policy == "exiger-digest" and .result == "fail")] | length == 0)'

# --- Supervision ----------------------------------------------------------------------------------
check_cmd "Prometheus collecte les résultats des politiques Kyverno (kyverno_validating_policy_results_total)" \
  _m26c_prom_existe 'count(kyverno_validating_policy_results_total) > 0'
check_cmd "alertes PolitiqueRefusEnRafale, PolitiqueEnEchecEnProduction, PolitiqueEnErreur chargées" \
  _m26c_alertes_chargees PolitiqueRefusEnRafale PolitiqueEnEchecEnProduction PolitiqueEnErreur
check_cmd "tableau Grafana politiques-admission provisionné" \
  _m26c_json "$(grafana_api "dashboards/uid/politiques-admission" 2>/dev/null || true)" '.meta.provisioned == true'

# --- CI -------------------------------------------------------------------------------------------
_m26c_e18_fichiers_ci() {
  _m26c_fichier "$_M26C_P_POLITIQUES" outils/verifier-exceptions.sh \
    && _m26c_fichier "$_M26C_P_POLITIQUES" kyverno/exceptions/kustomization.yaml
}
check_cmd "plateforme/politiques : outils/verifier-exceptions.sh et kyverno/exceptions/kustomization.yaml sur main" \
  _m26c_e18_fichiers_ci
check_cmd "plateforme/politiques : un job kyverno:exceptions a réussi sur main" \
  _m26c_job_reussi "$_M26C_P_POLITIQUES" "kyverno:exceptions"
