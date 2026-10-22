# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E40.sh — M20-E40 « Panne : le canary ne progresse plus » : contrôleur Argo Rollouts prêt avec
# le plugin Gateway API déclaré, Rollout de recette sain et piloté par le plugin, dernière analyse
# réussie, poids de la HTTPRoute ignorés par Argo CD et revenus au stable, RB-200 et journal, panne
# close. Lecture seule.

# shellcheck source=_m20-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-expert.sh"

title "M20-E40 — Le canary de recette va au bout"
require_cmd jq kubectl curl

_m20_e40_ns_ar="${WB_M20_NS_ROLLOUTS:-argo-rollouts}"
if ! _m20x_argo_lisible; then
  skip "Applications d'Argo CD" "le compte des checks ne lit pas les Applications (wb-checks-livraison, M20-E03)"
else
  check_cmd "contrôleur Argo Rollouts : au moins un pod prêt, aucun en redémarrage en boucle" \
    _m20x_kq '([.items[] | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length > 0)
      and ([.items[].status.containerStatuses[]? | select((.state.waiting.reason // "") == "CrashLoopBackOff")] | length == 0)' \
    -n "$_m20_e40_ns_ar" pods -l app.kubernetes.io/name=argo-rollouts
  check_cmd "argo-rollouts-config : plugin argoproj-labs/gatewayAPI déclaré" \
    _m20x_kq '(.data.trafficRouterPlugins // "") | test("argoproj-labs/gatewayAPI")' -n "$_m20_e40_ns_ar" configmap argo-rollouts-config
  check_cmd "$_m20x_app_recette : Synced, Healthy" _m20x_app_saine "$_m20x_app_recette"
  check_cmd "recette : Rollout mediagenda Healthy, ni en pause ni interrompu" _m20x_rollout_sain "$_m20x_ns_recette" mediagenda
  check_cmd "recette : Rollout piloté par le plugin Gateway API (trafficRouting.plugins)" \
    _m20x_kq '.spec.strategy.canary.trafficRouting.plugins["argoproj-labs/gatewayAPI"] != null' -n "$_m20x_ns_recette" rollouts.argoproj.io mediagenda
  check_cmd "recette : la dernière analyse (AnalysisRun) a réussi" \
    _m20x_kq '(.items | length > 0) and ((.items | sort_by(.metadata.creationTimestamp) | last | .status.phase) == "Successful")' \
    -n "$_m20x_ns_recette" analysisruns.argoproj.io
  check_cmd "$_m20x_app_recette : différences de la HTTPRoute ignorées (poids gérés par le plugin)" \
    _m20x_app_jq "$_m20x_app_recette" '[.spec.ignoreDifferences[]? | select(.kind == "HTTPRoute")] | length > 0'
  check_cmd "recette : HTTPRoute mediagenda revenue à 100 % sur le stable (canary à 0)" \
    _m20x_kq '[.spec.rules[].backendRefs[]? | select(.name == "mediagenda-canary") | (.weight // 1)] | all(. == 0)' \
    -n "$_m20x_ns_recette" httproutes.gateway.networking.k8s.io mediagenda
fi
check_cmd "plateforme/outils : outil canary-etat.sh présent" _m20x_fichier_present plateforme/outils canary-etat.sh
check_cmd "RB-200 : section sur le canary bloqué" _m20x_doc_contient "$_m20x_rb200" '^#+ .*(canary|Rollout)'
check_cmd "journal de diagnostic de INC-4740 commité (docs/kubernetes/journal/)" _m20x_journal 'INC-4740'
check_cmd "panne M20-E40 close (lab/bin/break 20 40 --annuler après réparation)" _m20x_aucune_panne_active E40
