# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et PromQL entre apostrophes
#
# check-E06.sh — M29-E06 : k6 en profondeur : scénarios, seuils des SLO, métriques
# À lancer depuis adm01. Lecture seule : scénario et résultats de plateforme/resilience (main), copie
# temporaire lue par « k6 inspect » ; Prometheus du cluster (effets de la charge sur la recette).

# shellcheck source=_m29-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m29-operationnel.sh"

title "M29-E06 — k6 en profondeur : scénarios, seuils des SLO, métriques"
require_cmd jq curl

_m29o_e06_s="$(_m29d_contenu "$_M29D_P_RESILIENCE" charge/parcours-recette.js)"
check_cmd "$_M29D_P_RESILIENCE : charge/parcours-recette.js sur main" bash -c '[[ -n "$1" ]]' _ "$_m29o_e06_s"
check_cmd "deux scénarios à taux d'arrivée : constant-arrival-rate ET ramping-arrival-rate" bash -c '
  grep -q "constant-arrival-rate" <<<"$1" && grep -q "ramping-arrival-rate" <<<"$1"' _ "$_m29o_e06_s"
check_cmd "seuils par parcours (sous-métriques filtrées par étiquette : {parcours:…})" bash -c 'grep -Eq "\{parcours: *[a-z]+\}" <<<"$1"' _ "$_m29o_e06_s"
check_cmd "seuil aligné sur le SLO de latence (part sous 250 ms > 95 %, ou p(95)<250)" bash -c '
  grep -Eq "rate *> *0\.95|p\(95\) *< *250" <<<"$1"' _ "$_m29o_e06_s"
check_cmd "arrêt automatique sur erreurs (abortOnFail)" bash -c 'grep -q "abortOnFail" <<<"$1"' _ "$_m29o_e06_s"
check_cmd "itérations perdues surveillées (dropped_iterations)" bash -c 'grep -q "dropped_iterations" <<<"$1"' _ "$_m29o_e06_s"
check_cmd "résumé écrit par handleSummary (JSON versionnable)" bash -c 'grep -q "export function handleSummary" <<<"$1"' _ "$_m29o_e06_s"

if command -v k6 >/dev/null 2>&1 && [[ -n "$_m29o_e06_s" ]]; then
  _m29d_copier "$_M29D_P_RESILIENCE" charge "$_M29D_TMP/r" >/dev/null
  _m29o_e06_insp="$(cd "$_M29D_TMP/r" && k6 inspect charge/parcours-recette.js 2>/dev/null || true)"
  check_cmd "k6 inspect : deux scénarios et au moins quatre seuils lus" _m29d_json "$_m29o_e06_insp" \
    '(.scenarios | length) >= 2 and (.thresholds | length) >= 4'
else
  skip "k6 inspect du scénario" "k6 absent de adm01 ou scénario absent"
fi

# --- Résultats versionnés ----------------------------------------------------------------------------
_m29o_e06_res="$(_m29d_arbre "$_M29D_P_RESILIENCE" charge/resultats | sort)"
_m29o_e06_json="$(grep -E '\.json$' <<<"$_m29o_e06_res" || true)"
_m29o_e06_n="$(grep -c . <<<"$_m29o_e06_json" || true)"
check_cmd "charge/resultats/ : au moins deux résumés JSON (comparaison cache froid / cache chaud) : ${_m29o_e06_n}" \
  bash -c '(( ${1:-0} >= 2 ))' _ "$_m29o_e06_n"
_m29o_e06_dernier="$(tail -1 <<<"$_m29o_e06_json")"
if [[ -n "$_m29o_e06_dernier" ]]; then
  _m29o_e06_c="$(_m29d_contenu "$_M29D_P_RESILIENCE" "$_m29o_e06_dernier")"
  check_cmd "$(basename "$_m29o_e06_dernier") : métriques de k6 présentes (http_reqs, http_req_duration)" _m29d_json "$_m29o_e06_c" \
    '[.. | objects | select(has("metrics")) | .metrics | has("http_reqs") and has("http_req_duration")] | any'
  check_cmd "$(basename "$_m29o_e06_dernier") : mesuré sur la RECETTE (jamais la production)" bash -c '
    grep -q "mediagenda-recette" <<<"$1" && ! grep -Eq "https://mediagenda\.apps\.par1" <<<"$1"' _ "$_m29o_e06_c"
fi
check_cmd "charge/resultats/ : analyse écrite (*analyse*.md) : corrélation client / serveur, cache, HPA" \
  bash -c 'grep -Eq "analyse[^/]*\.md$" <<<"$1"' _ "$_m29o_e06_res"

# --- Effets sur la recette (Prometheus) -----------------------------------------------------------------
# Au mini-projet (check-E25), la fenêtre de 7 jours est passée : contrôles sautés.
if [[ -n "${_M29_MINI_PROJET:-}" ]]; then
  skip "effets de la charge sur la recette (cache, HPA, 7 jours)" "mini-projet : vérifiés pendant M29-E06"
else
  _m29o_e06_hit="$(_m29d_prom_valeur 'sum(increase(mediagenda_cache_total{namespace="mediagenda-recette", resultat="hit"}[7d]))')"
  check_cmd "cache Valkey sollicité en recette ces 7 jours (succès : ${_m29o_e06_hit%%.*})" _m29d_superieur "$_m29o_e06_hit" 100
  _m29o_e06_hpa="$(_m29d_prom_valeur 'max(max_over_time(kube_horizontalpodautoscaler_status_current_replicas{namespace="mediagenda-recette"}[7d]) - min_over_time(kube_horizontalpodautoscaler_status_current_replicas{namespace="mediagenda-recette"}[7d]))')"
  check_cmd "l'HPA de MédiAgenda a ajouté au moins un réplica sous la charge (écart sur 7 jours : ${_m29o_e06_hpa%%.*})" \
    _m29d_superieur "$_m29o_e06_hpa" 0
fi
