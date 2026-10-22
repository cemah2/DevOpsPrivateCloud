# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E18.sh — M21-E18 : Analyses Prometheus pour Argo Rollouts
# À lancer depuis adm01. Lecture seule : objets d'Argo Rollouts (« kube », wb-checks-livraison).

# shellcheck source=_m21-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-operationnel.sh"

title "M21-E18 — Analyses Prometheus pour Argo Rollouts"
require_cmd jq kubectl

_m21o_e18_cat="$(_m21o_k get clusteranalysistemplates.argoproj.io taux-erreur-mediagenda -o json)"
check_cmd "ClusterAnalysisTemplate taux-erreur-mediagenda : fournisseur Prometheus à l'adresse interne du cluster" \
  _m21o_json "$_m21o_e18_cat" '[.spec.metrics[].provider.prometheus.address // empty] as $a
    | ($a | length) >= 1 and ($a | all(test("^https?://[a-z0-9.-]+\\.supervision\\.svc(\\.cluster\\.local)?:9090")))'
check_cmd "le modèle mesure la révision canary (argument hash-canary utilisé par les requêtes)" _m21o_json "$_m21o_e18_cat" '
  any(.spec.args[]; .name == "hash-canary")
  and ([.spec.metrics[].provider.prometheus.query // ""] | all(test("args\\.hash-canary")))'

for _m21o_e18_ns in mediagenda-recette mediagenda-prod; do
  check_cmd "Rollout mediagenda ($_m21o_e18_ns) : analyse taux-erreur-mediagenda (clusterScope)" _m21o_json \
    "$(_m21o_k get rollouts.argoproj.io mediagenda -n "$_m21o_e18_ns" -o json)" '
    [.spec.strategy.canary.analysis.templates[]?, (.spec.strategy.canary.steps[]?.analysis.templates[]?)]
    | any(.templateName == "taux-erreur-mediagenda" and .clusterScope == true)'
done

_m21o_e18_ar="$(_m21o_k get analysisruns.argoproj.io -n mediagenda-recette -o json)"
# AnalysisRun issu du modèle : une de ses métriques interroge Prometheus sur le hachage de révision.
_M21O_E18_DU_MODELE='[.items[] | select(any(.spec.metrics[]?; (.provider.prometheus.query // "") | test("rollouts_pod_template_hash")))]'
check_cmd "recette : au moins un AnalysisRun Prometheus réussi (Successful)" _m21o_json "$_m21o_e18_ar" \
  "$_M21O_E18_DU_MODELE"' | any(.status.phase == "Successful")'
check_cmd "recette : au moins un AnalysisRun Prometheus en échec (canary échoué volontairement)" _m21o_json "$_m21o_e18_ar" \
  "$_M21O_E18_DU_MODELE"' | any(.status.phase == "Failed")'
check_cmd "recette : la Rollout mediagenda est saine (Healthy) à la fin" _m21o_json \
  "$(_m21o_k get rollouts.argoproj.io mediagenda -n mediagenda-recette -o json)" '.status.phase == "Healthy"'
