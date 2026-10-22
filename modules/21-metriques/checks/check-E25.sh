# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E25.sh — M21-E25 « Thanos : vue globale, compaction, sous-échantillonnage, rétention »
# À lancer depuis adm01. Lecture seule : StatefulSet et pods du Compactor (compte wb-checks), métriques
# du Compactor et règles chargées (Thanos Query), points d'accès (/api/v1/stores), runbook dans GitLab.

# shellcheck source=_m21-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-production.sh"

title "M21-E25 — Thanos : compaction, sous-échantillonnage, rétention"
require_cmd kubectl jq curl

_m21_e25_sts="$(_m21p_json -n "$_M21P_NS" get statefulset thanos-compactor)"
check_cmd "StatefulSet thanos-compactor : exactement 1 réplica demandé, prêt" \
  _m21p_jq "$_m21_e25_sts" '.spec.replicas == 1 and (.status.readyReplicas // 0) == 1'
_m21_e25_tous="$(kube get pods -A -l app.kubernetes.io/name=thanos-compactor -o json 2>/dev/null \
  | jq '[.items[] | select(.status.phase == "Running")] | length' 2>/dev/null || echo -1)"
check_output "un seul Compactor en marche dans tout le cluster" '^1$' echo "$_m21_e25_tous"
_m21_e25_args="$(jq -r '[.spec.template.spec.containers[] | select(.name == "thanos-compactor") | .args[]] | join(" ")' \
  <<<"$_m21_e25_sts" 2>/dev/null || true)"
check_output "rétention brute 30 j" '--retention\.resolution-raw=30d( |$)' echo "$_m21_e25_args"
check_output "rétention 5 min 180 j" '--retention\.resolution-5m=180d( |$)' echo "$_m21_e25_args"
check_output "rétention 1 h 2 ans" '--retention\.resolution-1h=(2y|730d)( |$)' echo "$_m21_e25_args"
check_output "dédoublonnage hors ligne sur prometheus_replica" '--deduplication\.replica-label=prometheus_replica( |$)' \
  echo "$_m21_e25_args"
check_output "le Compactor tourne en continu (--wait)" '(^| )(-w|--wait)( |$)' echo "$_m21_e25_args"
if grep -q -- '--downsampling.disable' <<<"$_m21_e25_args"; then
  check_cmd "sous-échantillonnage actif (--downsampling.disable présent)" false
fi

title "État du Compactor (métriques)"
check_output "le Compactor est collecté (up{job=\"thanos-compactor\"} = 1)" '^1$' \
  _m21p_valeur 'sum(up{job="thanos-compactor"})'
check_output "le Compactor n'est pas arrêté sur erreur (thanos_compact_halted = 0)" '^0$' \
  _m21p_valeur 'max(thanos_compact_halted{job="thanos-compactor"})'
check_output "au moins un passage de compaction réussi" '^[1-9]' \
  _m21p_valeur 'sum(thanos_compact_iterations_total{job="thanos-compactor"})'

# Sous-échantillonnage : un bloc 5 min n'apparaît que pour des blocs bruts de plus de 40 h.
_m21_e25_ds="$(_m21p_valeur 'sum(thanos_compact_downsample_total{job="thanos-compactor"})')"
if _m21p_compare "$_m21_e25_ds" '>' 0; then
  check_cmd "blocs sous-échantillonnés produits ($_m21_e25_ds)" true
else
  _m21_e25_min="$(prom_api stores 2>/dev/null | jq -r '[.data.store[]?.minTime] | min // empty' 2>/dev/null || true)"
  if [[ "$_m21_e25_min" =~ ^[0-9]+$ ]] && (( $(date +%s) - _m21_e25_min / 1000 > 48 * 3600 )); then
    check_cmd "blocs sous-échantillonnés produits (aucun alors que le compartiment a plus de 48 h de données)" false
  else
    skip "blocs sous-échantillonnés" "le compartiment a moins de 48 h de données : relance ce check plus tard"
  fi
fi

title "Alertes et documentation"
_m21_e25_r="$(_m21p_regles alert)"
for _m21_e25_a in ThanosCompacteursMultiples ThanosCompacteurArrete ThanosSidecarEnvoisArretes ThanosQueryStoreManquant; do
  check_cmd "alerte $_m21_e25_a chargée" _m21p_alerte_chargee "$_m21_e25_a" "$_m21_e25_r"
done
check_cmd "règles testées : un fichier tests/*thanos*.test.yaml dans $_M21P_OBS" \
  _m21p_doc_present "$_M21P_OBS" tests 'thanos.*\.test\.ya?ml$' 10
check_cmd "runbook RB-214 dans $_M21P_DOC (docs/observabilite/metriques/runbooks/)" \
  _m21p_doc_present "$_M21P_DOC" docs/observabilite/metriques/runbooks 'RB-214[^/]*\.md$' 20
