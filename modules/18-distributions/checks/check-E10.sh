# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes bash -c entre apostrophes
#
# check-E10.sh — M18-E10 : CAPMOX, un cluster de charge de travail sur Proxmox
# À lancer depuis adm01. Lecture seule : kubectl get sur le cluster de gestion (kind-gestion, ou
# k3s01 après le pivot) et sur capi-essai, qm config sur pve01, sonde TCP de la VIP, GitLab en GET.
# Du Secret d'identifiants, seule la clé « insecure » est lue (et comparée), jamais affichée.

# shellcheck source=_m18-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m18-operationnel.sh"

title "M18-E10 — CAPMOX : un cluster de charge de travail sur Proxmox"
require_cmd jq kubectl

_m18d_e10_g="$(_m18o_gestion)"
check_cmd "Cluster de gestion : capi-essai décrit dans l'espace capi-essai (kind-gestion ou k3s01)" test -n "$_m18d_e10_g"
_m18d_e10_g="${_m18d_e10_g:-kind-gestion}"

_m18d_e10_cl="$(_m18d_kj "$_m18d_e10_g" -n capi-essai get cluster capi-essai -o json)"
check_cmd "Cluster capi-essai provisionné, étiquette cni=cilium" _m18d_json "$_m18d_e10_cl" \
  '.status.phase == "Provisioned" and .metadata.labels.cni == "cilium"'
check_cmd "Plan de contrôle : 1 réplica disponible en v1.36.4" _m18d_json \
  "$(_m18d_kj "$_m18d_e10_g" -n capi-essai get kubeadmcontrolplane capi-essai-plan-controle -o json)" \
  '.spec.replicas == 1 and .spec.version == "v1.36.4" and (.status.availableReplicas // 0) == 1'
check_cmd "Trois machines Running" _m18d_json "$(_m18d_kj "$_m18d_e10_g" -n capi-essai get machines -o json)" \
  '(.items | length == 3) and all(.items[]; .status.phase == "Running")'

_m18d_e10_capd=0
_m18d_json "$_m18d_e10_cl" '.spec.infrastructureRef.kind == "DockerCluster"' && _m18d_e10_capd=1
if (( _m18d_e10_capd )); then
  skip "Contrôles Proxmox (VMID, pool, VNet, identifiants, VIP)" "repli CAPD (vérification préalable de M18-E08 en échec)"
else
  _m18d_e10_pm="$(_m18d_kj "$_m18d_e10_g" -n capi-essai get proxmoxmachines -o json)"
  check_cmd "ProxmoxMachines : trois VMID dans 5180-5189" _m18d_json "$_m18d_e10_pm" \
    '(.items | length == 3) and all(.items[]; (.spec.virtualMachineID // 0) >= 5180 and (.spec.virtualMachineID // 0) <= 5189)'
  for _m18d_e10_id in $(jq -r '.items[].spec.virtualMachineID // empty' <<<"$_m18d_e10_pm" 2>/dev/null || true); do
    _m18d_e10_conf="$(_m18d_qm "$_m18d_e10_id")"
    check_cmd "VM $_m18d_e10_id : sur vk8s, étiquettes env-m18 et capi-essai, pool lab" bash -c \
      'grep -Eq "^net0: .*bridge=vk8s" <<<"$1"' _ "$_m18d_e10_conf"
    check_cmd "VM $_m18d_e10_id : étiquettes et pool" bash -c '[[ "$1" == 1 ]]' _ \
      "$( { _m18d_etiquettes "$_m18d_e10_conf" env-m18 capi-essai && _m18d_dans_pool "$_m18d_e10_id" && echo 1; } || echo 0)"
  done
  check_output "Identifiants : Secret capi-essai-proxmox avec insecure=false" '^false$' \
    _m18o_secret_cle "$_m18d_e10_g" capi-essai capi-essai-proxmox insecure
  check_cmd "Identifiants : ancre root_ca présente" bash -c '[[ "$1" -gt 0 ]]' _ \
    "$(_m18d_kj "$_m18d_e10_g" -n capi-essai get secret capi-essai-proxmox -o jsonpath='{.data.root_ca}' | wc -c)"
  check_cmd "Réservoir d'adresses de CAPMOX : 10.10.40.150-10.10.40.169" _m18d_json \
    "$(_m18d_kj "$_m18d_e10_g" -n capi-essai get inclusterippools -o json)" \
    'any(.items[]; .spec.addresses == ["10.10.40.150-10.10.40.169"])'
  check_port "VIP du plan de contrôle 10.10.40.210:6443" 10.10.40.210 6443
fi
check_cmd "ClusterResourceSet cilium appliqué à capi-essai" _m18d_json \
  "$(_m18d_kj "$_m18d_e10_g" -n capi-essai get clusterresourcesetbindings -o json)" \
  'any(.items[]; any(.spec.bindings[]?; .clusterResourceSetName == "cilium" and any(.resources[]?; .applied == true)))'

# --- Le cluster capi-essai ----------------------------------------------------------------------------
check_cmd "capi-essai.kubeconfig en 600" _m18d_600 "$_M18D_DIR/capi-essai.kubeconfig"
_m18d_e10_noeuds="$(_m18d_kj capi-essai get nodes -o json)"
check_cmd "capi-essai : trois nœuds Ready en v1.36.4" _m18d_noeuds_prets "$_m18d_e10_noeuds" 3 v1.36.4
if (( ! _m18d_e10_capd )); then
  check_cmd "capi-essai : adresses des nœuds dans 10.10.40.150-169" _m18d_json "$_m18d_e10_noeuds" \
    'all(.items[]; [.status.addresses[] | select(.type == "InternalIP") | .address | split(".") | map(tonumber)]
       | any(.[]; .[0:3] == [10, 10, 40] and .[3] >= 150 and .[3] <= 169))'
fi
check_cmd "capi-essai : Cilium prêt sur les trois nœuds" _m18d_json "$(_m18d_kj capi-essai -n kube-system get daemonset cilium -o json)" \
  '.status.desiredNumberScheduled == 3 and .status.numberReady == 3'

# --- Le code ------------------------------------------------------------------------------------------
_m18d_fichiers_main plateforme/distributions capi/capi-essai/10-cluster.yaml capi/capi-essai/20-plan-controle.yaml \
  capi/capi-essai/25-travailleurs.yaml capi/capi-essai/30-crs-cilium.yaml capi/identifiants.sh capi/cilium/values.yaml
check_cmd "plateforme/distributions (main) : aucun Secret dans capi/capi-essai/" bash -c \
  'grep -q "kind: Cluster" <<<"$1" && ! grep -Eq "^kind: *Secret" <<<"$1"' _ "$(for f in 00-espace 10-cluster 20-plan-controle 25-travailleurs 30-crs-cilium; do _m18d_contenu_main plateforme/distributions "capi/capi-essai/$f.yaml"; done)"
