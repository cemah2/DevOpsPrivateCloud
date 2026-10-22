# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E38.sh — M21-E38 « Panne : Prometheus déborde » : la cible témoin est collectée sans
# exploser (échantillons par collecte), son ServiceMonitor porte une limite, Prometheus a une limite
# globale et une alerte sur la tête, la cardinalité est documentée (RB-219), panne close. Lecture seule.

# shellcheck source=_m21-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-expert.sh"

title "M21-E38 — La cardinalité est maîtrisée"
require_cmd jq kubectl curl

if ! _m21x_vue_globale; then
  skip "collecte" "la vue globale ne répond pas (lab/bin/check 21 24)"
elif _m21x_temoins; then
  check_cmd "témoin (wb-pannes) collecté : les deux pods sont up" \
    bash -c '[[ "$1" -ge 2 ]]' _ "$(_m21x_nb 'up{namespace="wb-pannes",service="temoin-metriques"} == 1')"
  check_cmd "témoin : moins de 1 000 échantillons par collecte après relabeling" \
    _m21x_vide 'scrape_samples_post_metric_relabeling{namespace="wb-pannes",service="temoin-metriques"} >= 1000'
  check_cmd "ServiceMonitor temoin-metriques : une limite posée (sampleLimit, labelLimit ou labelValueLengthLimit)" \
    _m21x_kq '(.spec.sampleLimit // 0) > 0 or (.spec.labelLimit // 0) > 0 or (.spec.labelValueLengthLimit // 0) > 0' \
    -n wb-pannes servicemonitors.monitoring.coreos.com temoin-metriques
else
  skip "témoin de wb-pannes" "absent : il est créé à la première injection (lab/bin/break 21 38)"
fi
check_cmd "Prometheus : limite globale par cible (enforcedSampleLimit ou enforcedLabelLimit)" \
  _m21x_kq '.items[0].spec | ((.enforcedSampleLimit // 0) > 0 or (.enforcedLabelLimit // 0) > 0)' \
  -n supervision prometheuses.monitoring.coreos.com
if _m21x_vue_globale; then
  check_cmd "une alerte surveille le nombre de séries en tête (prometheus_tsdb_head_series)" \
    _m21x_regle_qui 'prometheus_tsdb_head_series[^_]'
  check_cmd "une alerte surveille le rythme de création des séries (head_series_created ou scrape_series_added)" \
    _m21x_regle_qui 'prometheus_tsdb_head_series_created_total|scrape_series_added'
fi
check_cmd "RB-219 : section sur la cardinalité" _m21x_doc_contient "$_m21x_rb/RB-219-*.md" '^#+ .*cardinalit'
check_cmd "panne M21-E38 close (lab/bin/break 21 38 --annuler après réparation)" _m21x_aucune_panne_active E38
