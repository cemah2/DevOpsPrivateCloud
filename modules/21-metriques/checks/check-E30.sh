# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E30.sh — M21-E30 « Capacité et performance de Prometheus »
# À lancer depuis adm01. Lecture seule : CR Prometheus et Deployment thanos-query (compte wb-checks),
# règles chargées et requêtes de mesure (Thanos Query), fichiers sur main dans GitLab.

# shellcheck source=_m21-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-production.sh"

title "M21-E30 — Capacité et performance de Prometheus"
require_cmd kubectl jq curl

_m21_e30_p="$(_m21p_prometheus)"
check_cmd "rétention bornée en taille (retentionSize) sous la taille du volume" _m21p_jq "$_m21_e30_p" '
  # retentionSize suit les unités de Prometheus (KB, MB, GB… en puissances de 1024) ; la taille du
  # volume suit les quantités Kubernetes (G = 10^9, Gi = 2^30).
  def octets: capture("^(?<n>[0-9.]+)(?<u>[KMGTP]?i?B?)$") as $c
    | ($c.n | tonumber) * ({"": 1, "B": 1, "KB": 1024, "MB": 1048576, "GB": 1073741824, "TB": 1099511627776,
                            "K": 1e3, "M": 1e6, "G": 1e9, "T": 1e12,
                            "Ki": 1024, "Mi": 1048576, "Gi": 1073741824, "Ti": 1099511627776}[$c.u] // 0);
  (.spec.retentionSize // "") != ""
  and ((.spec.retentionSize | octets) < (.spec.storage.volumeClaimTemplate.spec.resources.requests.storage | octets))'
check_cmd "limite d'échantillons imposée à toutes les cibles (enforcedSampleLimit > 0)" \
  _m21p_jq "$_m21_e30_p" '(.spec.enforcedSampleLimit // 0) > 0'
check_cmd "limites d'étiquettes imposées (enforcedLabelLimit > 0)" \
  _m21p_jq "$_m21_e30_p" '(.spec.enforcedLabelLimit // 0) > 0'
check_cmd "requêtes bornées (query.maxSamples et query.timeout)" \
  _m21p_jq "$_m21_e30_p" '(.spec.query.maxSamples // 0) > 0 and (.spec.query.timeout // "") != ""'
check_cmd "mémoire demandée ET limitée pour Prometheus" \
  _m21p_jq "$_m21_e30_p" '(.spec.resources.requests.memory // "") != "" and (.spec.resources.limits.memory // "") != ""'
_m21_e30_q="$(_m21p_json -n "$_M21P_NS" get deployment thanos-query)"
check_cmd "Thanos Query borne aussi ses lectures (--store.limits.request-samples)" _m21p_jq "$_m21_e30_q" \
  'any(.spec.template.spec.containers[].args[]?; test("^--store\\.limits\\.request-samples=[1-9]"))'

title "Mesures et garde-fous en service"
check_output "aucune cible refusée pour dépassement de la limite d'échantillons depuis 1 h" '^0$' \
  _m21p_valeur 'sum(increase(prometheus_target_scrapes_exceeded_sample_limit_total{job="kps-prometheus"}[1h])) or vector(0)'
_m21_e30_r="$(_m21p_regles alert)"
for _m21_e30_a in PrometheusSeriesProchesDuBudget PrometheusLimiteEchantillonsAtteinte PrometheusMemoireProcheLimite; do
  check_cmd "alerte de capacité $_m21_e30_a chargée" _m21p_alerte_chargee "$_m21_e30_a" "$_m21_e30_r"
done
# Requêtes de mesure : chaque bloc de requetes/E30.promql s'évalue sans erreur.
_m21_e30_f="$(_m21p_fichier "$_M21P_OBS" requetes/E30.promql || true)"
if [[ -n "$_m21_e30_f" ]]; then
  _m21_e30_nb=0
  _m21_e30_ko=0
  while IFS= read -r -d '' _m21_e30_bloc; do
    _m21_e30_expr="$(grep -v '^[[:space:]]*#' <<<"$_m21_e30_bloc" | sed '/^[[:space:]]*$/d' || true)"
    [[ -n "$_m21_e30_expr" ]] || continue
    _m21_e30_nb=$((_m21_e30_nb + 1))
    # Délai élargi : certaines mesures (topk sur toutes les séries, fenêtres de 7 jours) dépassent
    # les 5 s par défaut de WB_TIMEOUT sans être fausses.
    if ! WB_TIMEOUT=60 prom_requete "$_m21_e30_expr" 2>/dev/null | jq -e '.status == "success"' >/dev/null 2>&1; then
      _m21_e30_ko=$((_m21_e30_ko + 1))
    fi
  done < <(awk 'BEGIN { RS = ""; ORS = "\0" } { print }' <<<"$_m21_e30_f")
  check_output "requetes/E30.promql : au moins 6 requêtes de mesure" '^([6-9]|[1-9][0-9])$' echo "$_m21_e30_nb"
  check_output "requetes/E30.promql : toutes s'évaluent sans erreur" '^0$' echo "$_m21_e30_ko"
else
  check_cmd "requêtes de mesure dans $_M21P_OBS (requetes/E30.promql)" false
fi
_m21_e30_d="$(_m21p_doc_chemin "$_M21P_DOC" docs/observabilite/metriques 'dimensionnement[^/]*\.md$')"
if [[ -n "$_m21_e30_d" ]]; then
  check_cmd "dimensionnement écrit : séries, mémoire, disque, rétention" \
    _m21p_fichier_contient "$_M21P_DOC" "$_m21_e30_d" 's[ée]ries' 'm[ée]moire' '(disque|volume)' 'r[ée]tention'
else
  check_cmd "dimensionnement écrit (docs/observabilite/metriques/dimensionnement.md)" false
fi
