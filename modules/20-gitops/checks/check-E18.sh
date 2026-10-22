# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E18.sh — M20-E18 « Analyses : tests de fumée et requêtes web ». Lecture seule : AnalysisTemplates,
# Rollout et AnalysisRuns de mediagenda-recette, politiques réseau (wb-checks).

# shellcheck source=_m20-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-operationnel.sh"

title "M20-E18 — Analyses : tests de fumée et requêtes web"
require_cmd jq kubectl

_e18_ns=mediagenda-recette
if ! _m20o_lisible analysistemplates.argoproj.io "$_e18_ns"; then
  check_cmd "wb-checks lit les AnalysisTemplates et AnalysisRuns (M20-E15)" false
else
  _e18_fumee="$(_m20o_obj "$_e18_ns" analysistemplates.argoproj.io fumee-mediagenda)"
  check_cmd "AnalysisTemplate fumee-mediagenda : un Job" _m20o_jq "$_e18_fumee" '[.spec.metrics[].provider.job] | length >= 1'
  check_cmd "fumee-mediagenda : image du Job tirée par Harbor et épinglée par digest" \
    _m20o_jq "$_e18_fumee" '[.spec.metrics[].provider.job.spec.template.spec.containers[].image]
      | all(startswith("registry.par1.medisphere.internal/") and contains("@sha256:"))'
  check_cmd "fumee-mediagenda : vise le Service canary" \
    _m20o_jq "$_e18_fumee" 'tostring | test("mediagenda-canary")'
  _e18_pret="$(_m20o_obj "$_e18_ns" analysistemplates.argoproj.io pret-mediagenda)"
  check_cmd "AnalysisTemplate pret-mediagenda : mesure web de /pret sur le Service canary" \
    _m20o_jq "$_e18_pret" '[.spec.metrics[].provider.web.url | select(test("mediagenda-canary") and test("/pret"))] | length >= 1'
  check_cmd "pret-mediagenda : condition de succès et limites d'échec explicites" \
    _m20o_jq "$_e18_pret" '[.spec.metrics[] | select(.successCondition != null and .failureLimit != null)] | length >= 1'
  _e18_ro="$(_m20o_obj "$_e18_ns" rollouts.argoproj.io mediagenda)"
  check_cmd "Rollout : analyse de fond pret-mediagenda" \
    _m20o_jq "$_e18_ro" '[.spec.strategy.canary.analysis.templates[]?.templateName] | index("pret-mediagenda") != null'
  check_cmd "Rollout : marche d'analyse fumee-mediagenda" \
    _m20o_jq "$_e18_ro" '[.spec.strategy.canary.steps[] | .analysis.templates[]?.templateName] | index("fumee-mediagenda") != null'
  _e18_runs="$(_m20o_k get analysisruns.argoproj.io -n "$_e18_ns" -o json)"
  check_cmd "recette : une analyse de fumée réussie" \
    _m20o_jq "$_e18_runs" '[.items[] | select(.spec.metrics[]?.name == "fumee") | select(.status.phase == "Successful")] | length >= 1'
  check_cmd "recette : un canary interrompu par une analyse (AnalysisRun en Failed ou Error conservée)" \
    _m20o_jq "$_e18_runs" '[.items[] | select(.status.phase == "Failed" or .status.phase == "Error")] | length >= 1'
  check_cmd "recette : Rollout revenu Healthy après l'échec provoqué (version stable servie)" \
    _m20o_jq "$_e18_ro" '.status.phase == "Healthy" and .status.stableRS == .status.currentPodHash'
  _e18_np="$(_m20o_obj "$_e18_ns" networkpolicy mediagenda-analyses-entree)"
  check_cmd "NetworkPolicy : l'API admet le Job de fumée et le contrôleur d'Argo Rollouts" \
    _m20o_jq "$_e18_np" '.spec.ingress | tostring | test("argo-rollouts") and test("analyse")'
fi
