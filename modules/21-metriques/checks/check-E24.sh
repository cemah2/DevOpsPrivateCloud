# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E24.sh — M21-E24 « Prometheus redondant et Thanos sur le RGW »
# À lancer depuis adm01. Lecture seule : objets de l'espace supervision (compte wb-checks),
# existence du Secret thanos-objstore (kubeconfig d'administration, nom seulement), API de Thanos
# Query (10.10.41.60), liste et meta.json des blocs du compartiment (identité thanos),
# « radosgw-admin user info » sur ceph01 (sudo -n, quota seulement : les clés ne sont pas lues).

# shellcheck source=_m21-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-production.sh"

title "M21-E24 — Prometheus redondant et Thanos sur le RGW"
require_cmd kubectl jq curl aws

_m21_e24_p="$(_m21p_prometheus)"
check_cmd "le CR Prometheus « kps » demande 2 réplicas" _m21p_jq "$_m21_e24_p" '.spec.replicas == 2'
check_cmd "le CR Prometheus déclare le sidecar Thanos avec le Secret thanos-objstore" \
  _m21p_jq "$_m21_e24_p" '.spec.thanos.objectStorageConfig.name == "thanos-objstore"'
check_cmd "le sidecar Thanos est en 0.42.x, tiré par Harbor" \
  _m21p_jq "$_m21_e24_p" '(.spec.thanos.image // "") | test("^registry\\.par1\\.medisphere\\.internal/.+:v0\\.42\\.")'
check_cmd "les deux pods prometheus-kps-0 et -1 sont prêts" _m21p_pret statefulset prometheus-kps 2
_m21_e24_noeuds="$(kube -n "$_M21P_NS" get pods -l app.kubernetes.io/name=prometheus,operator.prometheus.io/name=kps \
  -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | sort -u | grep -c . || true)"
check_output "les deux réplicas tournent sur deux nœuds différents" '^2$' echo "$_m21_e24_noeuds"
check_cmd "Secret thanos-objstore présent dans supervision (hors Git)" _m21p_secret_existe "$_M21P_NS" thanos-objstore

title "Thanos Query et Store Gateway"
check_cmd "Deployment thanos-query : 2 réplicas prêts" _m21p_pret deployment thanos-query 2
check_cmd "StatefulSet thanos-store : prêt" _m21p_pret statefulset thanos-store
_m21_e24_svc="$(_m21p_json -n "$_M21P_NS" get service prometheus-externe)"
check_cmd "10.10.41.60 (Service prometheus-externe) désigne Thanos Query" \
  _m21p_jq "$_m21_e24_svc" '.spec.selector["app.kubernetes.io/name"] == "thanos-query" and any(.status.loadBalancer.ingress[]?; .ip == "10.10.41.60")'
_m21_e24_version() { prom_api status/buildinfo 2>/dev/null | jq -r '.data.version // empty' 2>/dev/null || true; }
check_output "10.10.41.60:9090 répond comme Thanos 0.42 (status/buildinfo)" '^0\.42\.' _m21_e24_version
_m21_e24_stores="$(prom_api stores 2>/dev/null || echo null)"
check_cmd "Thanos Query voit les 2 sidecars, sans erreur" \
  _m21p_jq "$_m21_e24_stores" '([.data.sidecar[]? | select(.lastError == null)] | length) == 2'
check_cmd "Thanos Query voit le Store Gateway, sans erreur" \
  _m21p_jq "$_m21_e24_stores" '([.data.store[]? | select(.lastError == null)] | length) >= 1'
# Dédoublonnage : avec dedup (défaut), l'étiquette de réplica disparaît ; sans, deux valeurs.
check_output "lecture dédoublonnée : prometheus_replica absente des résultats" '^1$' \
  _m21p_valeur 'count(count by (prometheus_replica) (up{job="kps-prometheus"}))'
_m21_e24_nodedup="$(prom_api 'query?dedup=false&query=count(count%20by%20(prometheus_replica)%20(up%7Bjob%3D%22kps-prometheus%22%7D))' 2>/dev/null \
  | jq -r '.data.result[0].value[1] // empty' 2>/dev/null || true)"
check_output "sans dédoublonnage (dedup=false), les deux réplicas apparaissent" '^2$' echo "$_m21_e24_nodedup"
_m21_e24_ds="$(kube -n "$_M21P_NS" get configmap kps-grafana-datasource -o jsonpath='{.data.datasource\.yaml}' 2>/dev/null || true)"
check_output "la source Grafana par défaut (uid prometheus) interroge Thanos Query" 'url: *http://thanos-query' echo "$_m21_e24_ds"

title "Compartiment thanos-k8s-par1 (RGW)"
check_cmd "identité RGW thanos présente sur adm01 ($_M21P_S3_ENV, mode 600)" \
  bash -c '[[ -r "$1" && "$(stat -c %a "$1")" == 600 ]]' _ "$_M21P_S3_ENV"
mapfile -t _m21_e24_blocs < <(_m21p_blocs)
if (( ${#_m21_e24_blocs[@]} > 0 )); then
  check_cmd "le compartiment contient des blocs (${#_m21_e24_blocs[@]})" true
  _m21_e24_meta="$(_m21p_meta "${_m21_e24_blocs[-1]}")"
  check_cmd "le dernier bloc porte les étiquettes externes cluster=k8s-par1 et prometheus_replica" \
    _m21p_jq "$_m21_e24_meta" '.thanos.labels.cluster == "k8s-par1" and ((.thanos.labels.prometheus_replica // "") | test("^prometheus-kps-[01]$"))'
  _m21_e24_debut=$(( ${#_m21_e24_blocs[@]} > 12 ? ${#_m21_e24_blocs[@]} - 12 : 0 ))
  _m21_e24_repl="$(for b in "${_m21_e24_blocs[@]:_m21_e24_debut}"; do _m21p_meta "$b" | jq -r '.thanos.labels.prometheus_replica // empty' 2>/dev/null; done | sort -u | grep -c . || true)"
  check_output "les deux réplicas envoient leurs blocs (parmi les 12 derniers)" '^2$' echo "$_m21_e24_repl"
else
  check_cmd "le compartiment contient des blocs (aucun : un premier bloc part 2 à 3 h après la mise en service ; sinon identités, certificat, flux)" false
fi
_m21_e24_non_versionne() {
  local v
  v="$(_m21p_s3 s3api get-bucket-versioning --bucket "$_M21P_BUCKET" 2>/dev/null)" || return 1
  ! grep -q '"Enabled"' <<<"$v"
}
check_cmd "le compartiment n'est pas versionné (le Compactor supprime lui-même)" _m21_e24_non_versionne
_m21_e24_rgw="$(_m21p_rgw "user info --uid=thanos" | jq -c '{max_buckets, user_quota}' 2>/dev/null || true)"
if [[ -n "$_m21_e24_rgw" ]]; then
  check_cmd "utilisateur RGW thanos : un seul compartiment autorisé, quota de taille actif" \
    _m21p_jq "$_m21_e24_rgw" '.max_buckets == 1 and .user_quota.enabled == true and (.user_quota.max_size // -1) > 0'
else
  skip "utilisateur RGW thanos (max-buckets, quota)" "radosgw-admin illisible sur $_M21P_CEPH (ssh/sudo -n)"
fi
