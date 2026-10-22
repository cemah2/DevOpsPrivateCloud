# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes (variables jq, pas du shell)
#
# check-E02.sh — M21-E02 : Déployer kube-prometheus-stack par Argo CD
# À lancer depuis adm01. Lecture seule : « kube » (wb-checks), API de Prometheus et d'Alertmanager
# par leurs Services LoadBalancer, GET HTTPS sur Grafana, DNS.
# Rejouable après M21-E24 : le Service prometheus-externe peut alors viser Thanos Query.

# shellcheck source=_m21-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-decouverte.sh"

title "M21-E02 — Déployer kube-prometheus-stack par Argo CD"
require_cmd jq curl kubectl dig

# --- 1. Droits des vérifications ------------------------------------------------------------------
_m21d_e02_cr="$(_m21d_k get clusterrole wb-checks-observabilite -o json)"
check_cmd "ClusterRole wb-checks-observabilite : agrégée aux checks, lecture des CRD monitoring.coreos.com, sans Secrets" \
  _m21d_json "$_m21d_e02_cr" \
  '.metadata.labels["workbook.medisphere.internal/checks"] == "true"
   and ([.rules[] | select(.apiGroups | index("monitoring.coreos.com")) | .resources[]] | index("servicemonitors") != null)
   and ([.rules[].resources[]] | index("secrets") == null)
   and ([.rules[].verbs[]] | all(. == "get" or . == "list" or . == "watch"))'

# --- 2. Espaces ----------------------------------------------------------------------------------
check_cmd "Espace supervision : Pod Security « restricted » appliquée, exposition par la Gateway autorisée" \
  _m21d_json "$(_m21d_k get namespace "$_M21D_NS" -o json)" \
  '.metadata.labels["pod-security.kubernetes.io/enforce"] == "restricted"
   and .metadata.labels["medisphere.internal/exposition"] == "oui"'
check_cmd "Espace supervision-noeuds : existe, réservé à node-exporter (seul DaemonSet, aucun Deployment)" bash -c \
  'jq -e ".metadata.name == \"supervision-noeuds\"" <<<"$1" >/dev/null &&
   jq -e "[.items[]] | length == 0" <<<"$2" >/dev/null' _ \
  "$(_m21d_k get namespace "$_M21D_NS_NOEUDS" -o json)" "$(_m21d_k -n "$_M21D_NS_NOEUDS" get deployments -o json)"

# --- 3. Argo CD ----------------------------------------------------------------------------------
_m21d_e02_app="$(_m21d_application kube-prometheus-stack)"
if [[ -z "$_m21d_e02_app" ]]; then
  _ko "Application Argo CD kube-prometheus-stack illisible ou absente (kube -n argocd get applications)"
else
  check_cmd "Application kube-prometheus-stack : projet plateforme, Synced et Healthy" _m21d_json "$_m21d_e02_app" \
    '.spec.project == "plateforme" and .status.sync.status == "Synced" and .status.health.status == "Healthy"'
  check_cmd "Chart 92.x tiré du miroir Harbor (registry.par1.medisphere.internal/charts), jamais d'Internet" _m21d_json "$_m21d_e02_app" \
    '[(.spec.sources // [.spec.source])[] | select(.chart == "kube-prometheus-stack")]
     | length == 1 and (.[0].repoURL | test("^(oci://)?registry\\.par1\\.medisphere\\.internal/charts/?$"))
     and (.[0].targetRevision | test("^92\\."))'
  check_cmd "Values lues dans plateforme/observabilite (kps/values.yaml)" _m21d_json "$_m21d_e02_app" \
    '([(.spec.sources // [])[] | select(.repoURL | test("plateforme/observabilite"))] | length >= 1)
     and ([(.spec.sources // [])[] | .helm.valueFiles[]? | select(test("kps/values\\.ya?ml$"))] | length >= 1)'
  check_cmd "Synchronisation côté serveur (CRD volumineuses) et aucun espace créé par Argo CD" _m21d_json "$_m21d_e02_app" \
    '(.spec.syncPolicy.syncOptions // []) as $o
     | ($o | index("ServerSideApply=true")) != null and ($o | index("CreateNamespace=true")) == null'
fi

# --- 4. Prometheus, Alertmanager, composants -------------------------------------------------------
_m21d_e02_prom="$(_m21d_k -n "$_M21D_NS" get prometheuses.monitoring.coreos.com -o json)"
check_cmd "CR Prometheus « kps » : sélecteurs sur $_M21D_SELECTEUR=oui (ServiceMonitor, PodMonitor, règles, ScrapeConfig, Probe), tous espaces" \
  _m21d_json "$_m21d_e02_prom" \
  '.items[] | select(.metadata.name == "kps") | .spec as $s
   | all(("serviceMonitor","podMonitor","rule","scrapeConfig","probe");
         ($s[. + "Selector"].matchLabels[$l] == "oui") and ($s[. + "NamespaceSelector"] == {}))' \
  --arg l "$_M21D_SELECTEUR"
check_cmd "CR Prometheus « kps » : rétention 15d, volume persistant ceph-rbd, étiquette externe cluster=k8s-par1" \
  _m21d_json "$_m21d_e02_prom" \
  '.items[] | select(.metadata.name == "kps") | .spec.retention == "15d"
   and .spec.storage.volumeClaimTemplate.spec.storageClassName == "ceph-rbd"
   and .spec.externalLabels.cluster == "k8s-par1"'
check_cmd "Pods de Prometheus prêts (StatefulSet prometheus-kps)" _m21d_json \
  "$(_m21d_k -n "$_M21D_NS" get statefulset prometheus-kps -o json)" \
  '.status.readyReplicas >= 1 and .status.readyReplicas == .spec.replicas'
check_cmd "Alertmanager prêt (StatefulSet alertmanager-kps), volume persistant" _m21d_json \
  "$(_m21d_k -n "$_M21D_NS" get statefulset alertmanager-kps -o json)" \
  '.status.readyReplicas >= 1 and .status.readyReplicas == .spec.replicas and (.spec.volumeClaimTemplates | length >= 1)'
_m21d_e02_dep="$(_m21d_k -n "$_M21D_NS" get deployments -o json)"
for _m21d_e02_d in kps-operator kps-kube-state-metrics kps-grafana; do
  check_cmd "Deployment $_m21d_e02_d disponible" _m21d_json "$_m21d_e02_dep" \
    '.items[] | select(.metadata.name == $d) | .status.availableReplicas >= 1 and .status.availableReplicas == .spec.replicas' \
    --arg d "$_m21d_e02_d"
done
check_cmd "node-exporter : un pod prêt sur chacun des $_M21D_NOEUDS nœuds (contrôle compris)" _m21d_json \
  "$(_m21d_k -n "$_M21D_NS_NOEUDS" get daemonsets -o json)" \
  '[.items[] | select(.metadata.name | test("node-exporter"))] | length == 1
   and (.[0].status.numberReady == ($n | tonumber)) and (.[0].status.desiredNumberScheduled == ($n | tonumber))' \
  --arg n "$_M21D_NOEUDS"

# --- 5. Accès depuis MGMT -------------------------------------------------------------------------
_m21d_e02_svc="$(_m21d_k -n "$_M21D_NS" get services -o json)"
check_cmd "Service prometheus-externe : LoadBalancer 10.10.41.60:9090, externalTrafficPolicy Local" _m21d_json "$_m21d_e02_svc" \
  '.items[] | select(.metadata.name == "prometheus-externe") | .spec.type == "LoadBalancer"
   and .spec.externalTrafficPolicy == "Local" and (.status.loadBalancer.ingress[0].ip == "10.10.41.60")
   and ([.spec.ports[].port] | index(9090) != null)'
check_cmd "Service alertmanager-externe : LoadBalancer 10.10.41.61:9093, externalTrafficPolicy Local" _m21d_json "$_m21d_e02_svc" \
  '.items[] | select(.metadata.name == "alertmanager-externe") | .spec.type == "LoadBalancer"
   and .spec.externalTrafficPolicy == "Local" and (.status.loadBalancer.ingress[0].ip == "10.10.41.61")
   and ([.spec.ports[].port] | index(9093) != null)'
check_cmd "Le Service du chart kps-prometheus reste interne (ClusterIP)" _m21d_json "$_m21d_e02_svc" \
  '.items[] | select(.metadata.name == "kps-prometheus") | .spec.type == "ClusterIP"'
# Politiques : entrée depuis MGMT et mon01, JAMAIS depuis « tout le monde ».
_m21d_e02_cnp="$(_m21d_k -n "$_M21D_NS" get ciliumnetworkpolicies -o json)"
for _m21d_e02_p in 9090 9093; do
  check_cmd "Politique Cilium sur le port $_m21d_e02_p : MGMT (10.10.10.0/24) et mon01 (10.10.20.19/32), ni world ni 0.0.0.0/0" \
    _m21d_json "$_m21d_e02_cnp" \
    '[.items[].spec | select([.ingress[]? | .toPorts[]?.ports[]?.port] | index($p) != null) | .ingress[]?] as $r
     | ($r | length > 0)
     and ([$r[] | .fromCIDR[]?, .fromCIDRSet[]?.cidr] | (index("10.10.10.0/24") != null) and (index("10.10.20.19/32") != null)
          and (index("0.0.0.0/0") == null))
     and ([$r[] | .fromEntities[]?] | index("world") == null and index("all") == null)' --arg p "$_m21d_e02_p"
done
check_dns "prometheus.apps.par1.medisphere.internal → 10.10.41.60 (ExternalDNS)" prometheus.apps.par1.medisphere.internal A '^10\.10\.41\.60$'
check_dns "alertmanager.apps.par1.medisphere.internal → 10.10.41.61 (ExternalDNS)" alertmanager.apps.par1.medisphere.internal A '^10\.10\.41\.61$'
# Avant M21-E24 : buildinfo de Prometheus 3.x ; après : Thanos Query répond aussi aux requêtes.
_m21d_e02_prometheus_repond() {
  local v
  v="$(prom_api status/buildinfo 2>/dev/null | jq -r '.data.version // empty' 2>/dev/null || true)"
  [[ "$v" =~ ^3\. ]] && return 0
  [[ -n "$(_m21d_valeur 'count(prometheus_build_info)')" ]]
}
_m21d_e02_alertmanager_repond() {
  am_api status 2>/dev/null | jq -e '.versionInfo.version | test("^0\\.3[4-9]")' >/dev/null 2>&1
}
check_cmd "Prometheus répond depuis adm01 (API ; Prometheus 3.x, ou Thanos Query après E24)" _m21d_e02_prometheus_repond
check_cmd "Alertmanager répond depuis adm01 (API v2 /status, version 0.34 ou ultérieure)" _m21d_e02_alertmanager_repond

# --- 6. Cibles collectées ---------------------------------------------------------------------------
check_cmd "Cibles kubelet : les $_M21D_NOEUDS nœuds répondent (métriques et cAdvisor)" \
  _m21d_au_moins 'count(up{job="kubelet", metrics_path="/metrics"} == 1)' "$_M21D_NOEUDS"
check_cmd "Cibles node-exporter : $_M21D_NOEUDS en état up" _m21d_au_moins 'count(up{job="node-exporter"} == 1)' "$_M21D_NOEUDS"
check_cmd "Cibles apiserver : les 3 kube-apiserver répondent" _m21d_au_moins 'count(up{job="apiserver"} == 1)' 3
check_cmd "Composants de l'espace supervision collectés (opérateur, kube-state-metrics, Prometheus, Alertmanager, Grafana)" \
  _m21d_au_moins 'count(count by (job) (up{namespace="supervision"} == 1))' 5
check_cmd "Aucune cible en échec (up == 0)" _m21d_vide 'up == 0'
check_cmd "Aucune cible du plan de contrôle désactivé (controller-manager, scheduler, etcd, kube-proxy)" \
  _m21d_vide 'up{job=~"kube-controller-manager|kube-scheduler|kube-etcd|kube-proxy"}'

# --- 7. Grafana -------------------------------------------------------------------------------------
check_cmd "HTTPRoute de Grafana acceptée par gw-par1" _m21d_json \
  "$(_m21d_k -n "$_M21D_NS" get httproutes -o json)" \
  '[.items[] | select(.spec.hostnames | index("grafana.apps.par1.medisphere.internal"))
    | .status.parents[]? | select(.parentRef.name == "gw-par1") | .conditions[] | select(.type == "Accepted" and .status == "True")]
   | length >= 1'
check_http "https://grafana.apps.par1.medisphere.internal/api/health répond (certificat vérifié)" \
  https://grafana.apps.par1.medisphere.internal/api/health 200
