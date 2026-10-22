# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E27.sh — M21-E27 « Budgets d'erreur et alertes multi-fenêtres ; Sloth en comparaison »
# À lancer depuis adm01. Lecture seule : CR ServiceLevelObjective et Prometheus (compte wb-checks),
# règles d'alerte chargées (Thanos Query), configuration d'Alertmanager (API v2), fichiers sur main
# dans GitLab (plateforme/observabilite, plateforme/medisphere).

# shellcheck source=_m21-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-production.sh"

title "M21-E27 — Budgets d'erreur et alertes multi-fenêtres"
require_cmd kubectl jq curl

_m21_e27_slos="$(_m21p_json -n "$_M21P_NS" get servicelevelobjectives.pyrra.dev)"
check_cmd "les trois SLO alertent (burnrates non désactivé)" _m21p_jq "$_m21_e27_slos" '
  [.items[] | select(.metadata.name | test("^(mediagenda-disponibilite|mediagenda-latence|medidoc-disponibilite)$"))]
  | length == 3 and all(.[]; (.spec.alerting.burnrates != false) and (.spec.alerting.disabled != true))'
check_cmd "mediagenda-disponibilite : consommation rapide en « critique », lente en « avertissement »" _m21p_jq "$_m21_e27_slos" '
  any(.items[]; .metadata.name == "mediagenda-disponibilite"
      and .spec.alerting.severities.fastBurn == "critique"
      and .spec.alerting.severities.longTermBurn == "avertissement")'
check_cmd "medidoc-disponibilite (recette) ne réveille personne (aucune fenêtre en « critique »)" _m21p_jq "$_m21_e27_slos" '
  any(.items[]; .metadata.name == "medidoc-disponibilite"
      and ((.spec.alerting.severities // {}) | [.fastBurn, .mediumBurn, .slowBurn, .longTermBurn] | all(. != null and . != "critique")))'
check_cmd "chaque SLO désigne son équipe (étiquette pyrra.dev/equipe)" _m21p_jq "$_m21_e27_slos" '
  [.items[] | select(.metadata.name | test("^(mediagenda|medidoc)-"))] | length >= 3
  and all(.[]; (.metadata.labels["pyrra.dev/equipe"] // "") != "")'
check_cmd "chaque SLO donne un runbook aux alertes (annotation pyrra.dev/runbook_url)" _m21p_jq "$_m21_e27_slos" '
  [.items[] | select(.metadata.name | test("^(mediagenda|medidoc)-"))]
  | all(.[]; (.metadata.annotations["pyrra.dev/runbook_url"] // "") | test("^https://git01\\."))'

title "Alertes chargées et routage"
_m21_e27_r="$(_m21p_regles alert)"
check_cmd "ErrorBudgetBurn de mediagenda-disponibilite chargée (4 paires de fenêtres)" _m21p_jq "$_m21_e27_r" '
  [.data.groups[].rules[] | select(.name == "ErrorBudgetBurn" and .labels.slo == "mediagenda-disponibilite")] | length == 4'
check_cmd "les alertes ErrorBudgetBurn portent l'équipe (equipe)" _m21p_jq "$_m21_e27_r" '
  [.data.groups[].rules[] | select(.name == "ErrorBudgetBurn")] | length > 0 and all(.[]; (.labels.equipe // "") != "")'
_m21_e27_p="$(_m21p_prometheus)"
check_cmd "Prometheus recopie severity dans gravite pour Alertmanager (additionalAlertRelabelConfigs)" \
  _m21p_jq "$_m21_e27_p" '(.spec.additionalAlertRelabelConfigs.name // "") != ""'
_m21_e27_am="$(_m21p_am_config)"
if [[ -n "$_m21_e27_am" ]] && command -v amtool >/dev/null 2>&1; then
  _m21_e27_tmp="$(mktemp)"
  printf '%s\n' "$_m21_e27_am" > "$_m21_e27_tmp"
  check_output "une ErrorBudgetBurn critique de MédiAgenda (prod) part à l'astreinte" 'astreinte' \
    amtool config routes test --config.file="$_m21_e27_tmp" alertname=ErrorBudgetBurn gravite=critique \
    severity=critique equipe=mediagenda slo=mediagenda-disponibilite namespace=mediagenda-prod
  rm -f "$_m21_e27_tmp"
else
  skip "routage d'une ErrorBudgetBurn critique" "amtool absent de adm01 ou configuration d'Alertmanager illisible"
fi

title "Comparaison et politique"
check_cmd "spécification Sloth du même objectif dans $_M21P_OBS (slo/sloth/)" \
  _m21p_doc_present "$_M21P_OBS" slo/sloth '\.ya?ml$' 10
check_cmd "règles de SLO testées (tests/*slo*.test.yaml)" \
  _m21p_doc_present "$_M21P_OBS" tests 'slo.*\.test\.ya?ml$' 10
check_cmd "comparatif Pyrra / Sloth dans $_M21P_DOC (docs/observabilite/metriques/)" \
  _m21p_doc_present "$_M21P_DOC" docs/observabilite/metriques 'comparatif[^/]*sloth[^/]*\.md$' 15
_m21_e27_pol="$(_m21p_doc_chemin "$_M21P_DOC" docs/observabilite/metriques 'politique-budget-erreur\.md$')"
if [[ -n "$_m21_e27_pol" ]]; then
  check_cmd "politique de budget d'erreur : gel des livraisons et décideurs écrits" \
    _m21p_fichier_contient "$_M21P_DOC" "$_m21_e27_pol" 'gel' 'budget' '(Julien|Claire|Karim)'
else
  check_cmd "politique de budget d'erreur (docs/observabilite/metriques/politique-budget-erreur.md)" false
fi
