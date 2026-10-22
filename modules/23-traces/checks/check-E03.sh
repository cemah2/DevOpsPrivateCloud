# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et TraceQL entre apostrophes
#
# check-E03.sh — M23-E03 : Tempo sur le RGW
# Lecture seule : Application et objets de Tempo (kube), configuration rendue (ConfigMap tempo), API de Tempo
# (/ready, recherche) par la source Grafana ou le mandataire de l'API, liste du compartiment RGW avec
# l'identité de ~/.config/workbook/s3-tempo.env, dépôts GitLab en GET.

# shellcheck source=_m23-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m23-decouverte.sh"

title "M23-E03 — Tempo sur le RGW"
require_cmd jq kubectl curl yq

_m23d_e03_conf() { kube -n "$_m23d_ns" get configmap tempo -o jsonpath='{.data.tempo\.yaml}' 2>/dev/null | yq -o json '.' 2>/dev/null; }
_M23D_E03_CONF="$(_m23d_e03_conf || true)"
_m23d_e03_conf_q() { [[ -n "$_M23D_E03_CONF" ]] && jq -e "$1" >/dev/null 2>&1 <<<"$_M23D_E03_CONF"; }

# --- 1. Déploiement --------------------------------------------------------------------------------
check_cmd "Application Argo CD tempo : Synced et Healthy" _m23d_app_saine tempo
check_cmd "StatefulSet tempo prêt (image 3.1.x de Harbor, volume ceph-rbd)" _m23d_kq \
  '(.status.readyReplicas // 0) >= 1 and (.spec.template.spec.containers[] | select(.name == "tempo") | .image | test("^registry\\.par1\\.medisphere\\.internal/.+/tempo:3\\.1\\.")) and ([.spec.volumeClaimTemplates[]?.spec.storageClassName] | index("ceph-rbd") != null)' \
  -n "$_m23d_ns" statefulset tempo
check_output "Tempo répond « ready » (/ready)" '^ready' _m23d_tempo_get /ready
check_cmd "identifiants du RGW lus dans le Secret tempo-objstore (hors Git)" _m23d_kq \
  '[.spec.template.spec.containers[] | select(.name == "tempo") | .envFrom[]?.secretRef.name] | index("tempo-objstore") != null' \
  -n "$_m23d_ns" statefulset tempo

# --- 2. Configuration rendue ------------------------------------------------------------------------
check_cmd "stockage S3 : compartiment tempo-k8s-par1 sur rgw.par1.medisphere.internal, style chemin" _m23d_e03_conf_q \
  '.storage.trace.backend == "s3" and .storage.trace.s3.bucket == "tempo-k8s-par1" and (.storage.trace.s3.endpoint | test("rgw\\.par1\\.medisphere\\.internal")) and .storage.trace.s3.forcepathstyle == true'
check_cmd "TLS vérifié vers le RGW (racine MédiSphère, pas de tls_insecure_skip_verify)" _m23d_e03_conf_q \
  '(.storage.trace.s3.tls_ca_path // "") != "" and (.storage.trace.s3.tls_insecure_skip_verify // false) == false and (.storage.trace.s3.insecure // false) == false'
check_cmd "aucune clé d'accès en clair dans la configuration (référence \${…})" _m23d_e03_conf_q \
  '(.storage.trace.s3.access_key // "" | test("^\\$\\{")) and (.storage.trace.s3.secret_key // "" | test("^\\$\\{"))'
check_cmd "rétention explicite d'au moins 14 jours (block_retention ≥ 336h)" _m23d_e03_conf_q \
  '[.backend_worker.compaction.block_retention // "0h" | capture("^(?<h>[0-9]+)h$").h | tonumber] | .[0] >= 336'

# --- 3. Chaîne complète -------------------------------------------------------------------------------
check_cmd "otel-passerelle exporte vers Tempo (otlp_grpc vers tempo.traces…:4317), plus de debug" _m23d_cr otel-passerelle \
  '([.spec.config.exporters | to_entries[] | select((.key | startswith("otlp_grpc")) and (.value.endpoint | test("tempo\\.traces(\\.svc(\\.cluster\\.local)?)?:4317$")))] | length >= 1) and ([.spec.config.service.pipelines.traces.exporters[] | select(startswith("debug"))] | length == 0)'
check_cmd "CiliumNetworkPolicy traces-tempo présente" _m23d_kq '.metadata.name == "traces-tempo"' \
  -n "$_m23d_ns" ciliumnetworkpolicies.cilium.io traces-tempo
check_cmd "Tempo trouve des traces de la dernière heure (recherche TraceQL « {} »)" _m23d_traces 3600 '{}'

# --- 4. Le compartiment ----------------------------------------------------------------------------------
_m23d_e03_blocs() {
  _m23d_s3 "$_m23d_s3_tempo" s3api list-objects-v2 --bucket tempo-k8s-par1 --prefix single-tenant/ --max-items 200 2>/dev/null |
    jq -e '[.Contents[]?.Key | select(endswith("/data.parquet"))] | length > 0' >/dev/null 2>&1
}
if ! command -v aws >/dev/null 2>&1; then
  skip "blocs de traces dans tempo-k8s-par1" "commande aws absente d'adm01 (M16)"
elif [[ ! -r "$_m23d_s3_tempo" ]]; then
  skip "blocs de traces dans tempo-k8s-par1" "$_m23d_s3_tempo illisible (créé en M23-E03)"
else
  check_cmd "blocs Parquet écrits dans le compartiment tempo-k8s-par1 (single-tenant/…/data.parquet)" _m23d_e03_blocs
fi

# --- 5. Grafana -----------------------------------------------------------------------------------------
check_output "source Grafana uid « tempo » déclarée par code (ConfigMap du sidecar)" 'uid: *"?tempo"?' _m23d_sources_grafana
check_output "source Grafana Tempo saine (test de connexion)" '"status": *"OK"' \
  grafana_api "datasources/uid/$_m23d_tempo_uid/health"
check_output "plateforme/charts-miroir (main) : chart tempo recopié" '(^|[^a-z-])tempo' \
  _m23d_fichier plateforme/charts-miroir charts.yaml
