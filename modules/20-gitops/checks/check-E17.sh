# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E17.sh — M20-E17 « Blue/green avec aperçu et promotion manuelle ». Lecture seule : Rollout,
# Services, AnalysisRuns de wb-essais, ClusterAnalysisTemplate (wb-checks).

# shellcheck source=_m20-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-operationnel.sh"

title "M20-E17 — Blue/green avec aperçu et promotion manuelle"
require_cmd jq kubectl

if ! _m20o_lisible rollouts.argoproj.io wb-essais; then
  check_cmd "wb-checks lit les Rollouts (M20-E15)" false
else
  _e17_ro="$(_m20o_obj wb-essais rollouts.argoproj.io labo)"
  check_cmd "Rollout labo : stratégie blueGreen (activeService labo, previewService labo-apercu)" \
    _m20o_jq "$_e17_ro" '.spec.strategy.blueGreen.activeService == "labo" and .spec.strategy.blueGreen.previewService == "labo-apercu"'
  check_cmd "Rollout labo : promotion manuelle (autoPromotionEnabled: false)" \
    _m20o_jq "$_e17_ro" '.spec.strategy.blueGreen.autoPromotionEnabled == false'
  check_cmd "Rollout labo : analyse avant promotion (gabarit de cluster pret-http)" \
    _m20o_jq "$_e17_ro" '[.spec.strategy.blueGreen.prePromotionAnalysis.templates[]? | select(.templateName == "pret-http" and .clusterScope == true)] | length == 1'
  _e17_cat="$(_m20o_k get clusteranalysistemplates.argoproj.io pret-http -o json)"
  check_cmd "ClusterAnalysisTemplate pret-http présent (livré avec Argo Rollouts)" \
    _m20o_jq "$_e17_cat" '.spec.metrics[0].provider.web.url | test("args\\.url")'
  _e17_apercu="$(_m20o_obj wb-essais service labo-apercu)"
  check_cmd "Service labo-apercu présent" test -n "$_e17_apercu"
  check_cmd "Rollout labo : Healthy, révision active = révision courante" \
    _m20o_jq "$_e17_ro" '.status.phase == "Healthy" and .status.blueGreen.activeSelector == .status.currentPodHash'
  # Une révision a été promue après une analyse d'aperçu réussie.
  _e17_ar="$(_m20o_k get analysisruns.argoproj.io -n wb-essais -o json)"
  check_cmd "wb-essais : au moins une analyse pret-http réussie (avant une promotion)" \
    _m20o_jq "$_e17_ar" '[.items[] | select(.metadata.ownerReferences[]?.name == "labo")
      | select([.spec.metrics[]?.name] | index("http-2xx") != null) | select(.status.phase == "Successful")] | length >= 1'
fi
