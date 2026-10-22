# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E34.sh — M21-E34 « Un diagnostic en temps limité » (CHRONO)
# À lancer depuis adm01, à la fin (T1). Lecture seule : journal de diagnostic sur main de
# plateforme/medisphere (GitLab), pods de wb-pannes (compte wb-checks), métriques de la recette
# (Thanos Query). La variante injectée est lue dans l'état local de l'injection
# (~/.local/state/workbook/M21-E34/variante), gardé après l'annulation.

# shellcheck source=_m21-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-production.sh"

title "M21-E34 — Un diagnostic en temps limité"
require_cmd kubectl jq curl

_m21_e34_etat="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M21-E34"
_m21_e34_var="$(cat "$_m21_e34_etat/variante" 2>/dev/null || true)"
if [[ ! "$_m21_e34_var" =~ ^[12]$ ]]; then
  check_cmd "scénario injecté (aucune trace : lance d'abord « lab/bin/break 21 34 » au début du chrono)" false
  # Script sourcé par lab/bin/check : « return » termine ce script, le bilan s'affiche quand même.
  return 0
fi

title "Journal de diagnostic"
_m21_e34_j="$(_m21p_doc_chemin "$_M21P_DOC" docs/kubernetes/journal '(m21-e34|inc-4834)[^/]*\.md$')"
if [[ -z "$_m21_e34_j" ]]; then
  check_cmd "journal docs/kubernetes/journal/*M21-E34*.md (ou *INC-4834*) sur main de $_M21P_DOC" false
else
  _m21_e34_txt="$(_m21p_fichier "$_M21P_DOC" "$_m21_e34_j" || true)"
  check_cmd "journal présent : $_m21_e34_j" test -n "$_m21_e34_txt"
  _m21_e34_heures="$(grep -Eo '\b([01]?[0-9]|2[0-3])[:h][0-5][0-9]\b' <<<"$_m21_e34_txt" | sort -u | grep -c . || true)"
  check_output "chronologie horodatée (au moins 4 heures notées)" '^([4-9]|[1-9][0-9]+)$' echo "$_m21_e34_heures"
  _m21_e34_promql="$(grep -Ec '(rate|irate|increase|histogram_quantile|sum by|topk|max_over_time)\(?' <<<"$_m21_e34_txt" || true)"
  check_output "preuves par les métriques (au moins 4 requêtes PromQL citées)" '^([4-9]|[1-9][0-9]+)$' echo "$_m21_e34_promql"
  check_cmd "le symptôme est quantifié (latence, taux d'erreurs ou débit chiffrés)" \
    grep -Eqi '[0-9]+([.,][0-9]+)? ?(ms|s|%|req/s|requêtes)' <<<"$_m21_e34_txt"
  # La cause racine, selon la variante (mots attendus, insensibles à la casse).
  case "$_m21_e34_var" in
    1) check_cmd "cause identifiée : un client en boucle sur /api/v1/creneaux qui contourne le cache" \
         bash -c 'grep -Eqi "creneaux" <<<"$1" && grep -Eqi "cache|valkey|miss" <<<"$1" && grep -Eqi "wb-pannes|export-creneaux|client|partenaire" <<<"$1"' _ "$_m21_e34_txt" ;;
    2) check_cmd "cause identifiée : une transaction longue qui verrouille rendez_vous (PostgreSQL)" \
         bash -c 'grep -Eqi "verrou|lock" <<<"$1" && grep -Eqi "transaction|export-rapports|backends_waiting|max_tx" <<<"$1"' _ "$_m21_e34_txt" ;;
  esac
  check_cmd "une action et une prévention sont proposées" \
    bash -c 'grep -Eqi "action|correctif|r[ée]paration" <<<"$1" && grep -Eqi "pr[ée]vention|pr[ée]venir|alerte|limite|quota|statement_timeout|lock_timeout" <<<"$1"' _ "$_m21_e34_txt"
fi

title "Retour à la normale"
_m21_e34_pods="$(kube -n wb-pannes get pods -l app.kubernetes.io/name=export-creneaux \
  -o jsonpath='{range .items[*]}{.status.phase}{"\n"}{end}' 2>/dev/null | grep -c Running || true)"
case "$_m21_e34_var" in
  1) check_output "plus de client « export » en marche dans wb-pannes" '^0$' echo "$_m21_e34_pods" ;;
  2) check_output "plus de session « export-rapports » dans PostgreSQL (recette)" '^0$' \
       _m21p_valeur 'sum(cnpg_backends_total{namespace="mediagenda-recette", application_name="export-rapports"}) or vector(0)' ;;
esac
_m21_e34_p95="$(_m21p_valeur 'histogram_quantile(0.95, sum by (le) (rate(mediagenda_http_request_duration_seconds_bucket{namespace="mediagenda-recette", route!~"/sante|/pret|/metrics"}[5m])))')"
if [[ -z "$_m21_e34_p95" || "$_m21_e34_p95" == NaN ]]; then
  skip "latence p95 de la recette" "pas de trafic sur 5 min : rien à mesurer"
else
  check_cmd "latence p95 de la recette revenue sous 500 ms ($_m21_e34_p95 s)" _m21p_compare "$_m21_e34_p95" '<' 0.5
fi
