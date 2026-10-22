# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions PromQL et filtres jq entre apostrophes
#
# check-E20.sh — M21-E20 : Superviser Kubernetes (plan de contrôle, etcd, kubelet, Cilium)
# À lancer depuis adm01. Lecture seule : Prometheus du cluster, ConfigMap kube-system/kubeadm-config
# et nœuds (« kube »), GitLab.

# shellcheck source=_m21-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-operationnel.sh"

title "M21-E20 — Superviser Kubernetes : plan de contrôle, etcd, kubelet, Cilium"
require_cmd jq kubectl curl

for _m21o_e20_j in kube-controller-manager:3 kube-scheduler:3 kube-etcd:3 coredns:2; do
  check_cmd "job ${_m21o_e20_j%%:*} : au moins ${_m21o_e20_j##*:} cibles, toutes joignables" \
    _m21o_job_up "${_m21o_e20_j%%:*}" "${_m21o_e20_j##*:}"
done
_m21o_e20_noeuds="$(_m21o_valeur 'count(kube_node_info)')"
check_cmd "agent Cilium : une cible joignable par nœud (${_m21o_e20_noeuds:-?} nœuds)" \
  _m21o_job_up cilium-agent "${_m21o_e20_noeuds:-6}"
check_cmd "opérateur Cilium : cible joignable" _m21o_job_up cilium-operator 1
check_cmd "Hubble : cibles joignables" _m21o_job_up hubble-metrics 1
check_cmd "etcd : trois membres, chacun avec un leader (etcd_server_has_leader == 1)" \
  _m21o_au_moins 'count(etcd_server_has_leader == 1)' 3

check_output "cluster/kubeadm-config.yaml (main) : listen-metrics-urls d'etcd" 'listen-metrics-urls' \
  _m21o_contenu "$_M21O_P_K8S" cluster/kubeadm-config.yaml
_m21o_e20_cm() { _m21o_k get configmap kubeadm-config -n kube-system -o json | jq -r '.data.ClusterConfiguration // empty' 2>/dev/null || true; }
check_output "ConfigMap kube-system/kubeadm-config téléversé (listen-metrics-urls présent)" 'listen-metrics-urls' _m21o_e20_cm
check_output "ConfigMap kube-system/kubeadm-config : bind-address de kube-scheduler et kube-controller-manager" \
  'bind-address' _m21o_e20_cm
check_cmd "tous les nœuds sont Ready et toujours en 1.36" _m21o_json "$(_m21o_k get nodes -o json)" '
  (.items | length) >= 3 and all(.items[]; (.status.nodeInfo.kubeletVersion | startswith("v1.36."))
    and any(.status.conditions[]; .type == "Ready" and .status == "True"))'
