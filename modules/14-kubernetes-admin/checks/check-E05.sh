# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E05.sh — M14-E05 : Joindre les nœuds et installer Cilium
# À lancer depuis adm01. Lecture seule : kubectl « get » (kubeconfig des checks, ou repli SSH avec
# admin.conf avant M14-E06), etcdctl « member list » dans le conteneur etcd de k8s-cp01 (crictl exec,
# observation seulement), HAProxy en « show stat », outils de adm01, API GitLab en GET.

# shellcheck source=_m14-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-decouverte.sh"

title "M14-E05 — Joindre les nœuds et installer Cilium"
require_cmd jq

# --- 1. Les nœuds ---------------------------------------------------------------------------------
_m14d_e05_noeuds="$(_m14d_k get nodes -o json)"
check_cmd "Le cluster répond et compte exactement six nœuds" _m14d_json "$_m14d_e05_noeuds" '.items | length == 6'
for _m14d_e05_n in "${_M14D_CP[@]}" "${_M14D_W[@]}"; do
  read -r _ _m14d_e05_ip _m14d_e05_role <<<"${_M14D_PLAN[$_m14d_e05_n]:-0 0 x}"
  check_cmd "$_m14d_e05_n : Ready, kubelet v$_M14D_VERSION, adresse interne $_m14d_e05_ip" _m14d_json "$_m14d_e05_noeuds" \
    '.items[] | select(.metadata.name == $n)
     | ([.status.conditions[] | select(.type == "Ready")][0].status == "True")
       and .status.nodeInfo.kubeletVersion == ("v" + $v)
       and ([.status.addresses[] | select(.type == "InternalIP") | .address] == [$ip])' \
    --arg n "$_m14d_e05_n" --arg v "$_M14D_VERSION" --arg ip "$_m14d_e05_ip"
  if [[ "$_m14d_e05_role" == cp ]]; then
    check_cmd "$_m14d_e05_n : rôle control-plane et taint NoSchedule (aucune charge applicative)" _m14d_json "$_m14d_e05_noeuds" \
      '.items[] | select(.metadata.name == $n)
       | (.metadata.labels | has("node-role.kubernetes.io/control-plane"))
         and ([.spec.taints[]? | select(.key == "node-role.kubernetes.io/control-plane" and .effect == "NoSchedule")] | length == 1)' \
      --arg n "$_m14d_e05_n"
  else
    check_cmd "$_m14d_e05_n : travailleur sans taint" _m14d_json "$_m14d_e05_noeuds" \
      '.items[] | select(.metadata.name == $n) | ((.spec.taints // []) | length == 0)' --arg n "$_m14d_e05_n"
  fi
done

# --- 2. Le plan de contrôle -------------------------------------------------------------------------------
_m14d_e05_pods="$(_m14d_k -n kube-system get pods -o json)"
for _m14d_e05_c in etcd kube-apiserver kube-controller-manager kube-scheduler; do
  check_cmd "Plan de contrôle : $_m14d_e05_c prêt sur les trois nœuds de contrôle" _m14d_json "$_m14d_e05_pods" \
    '[.items[] | select(.metadata.labels.component == $c and .status.phase == "Running")
      | select(all(.status.containerStatuses[]; .ready))] | length == 3' --arg c "$_m14d_e05_c"
done
_m14d_e05_membres="$(remote "$_M14D_REF" 'id=$(sudo -n crictl ps --name "^etcd$" -q | head -1); sudo -n crictl exec "$id" etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt --key=/etc/kubernetes/pki/etcd/healthcheck-client.key member list -w json' 2>/dev/null || true)"
check_cmd "etcd : trois membres démarrés (k8s-cp01, k8s-cp02, k8s-cp03), aucun apprenant" _m14d_json "$_m14d_e05_membres" \
  '([.members[] | .name] | sort) == ["k8s-cp01", "k8s-cp02", "k8s-cp03"] and all(.members[]; (.isLearner // false) == false)'
for _m14d_e05_n in "${_M14D_CP[@]}"; do
  check_cmd "$_m14d_e05_n : HAProxy voit les trois kube-apiserver UP, contrôle /readyz en TLS" bash -c \
    'awk -F, "\$1 == \"be_k8s_api\" && \$2 ~ /^k8s-cp/ && \$18 ~ /^UP/ {n++} END {exit !(n == 3)}" <<<"$1" && grep -q "/readyz" <<<"$2"' \
    _ "$(_m14d_haproxy_stat "$_m14d_e05_n")" "$(remote "$_m14d_e05_n" 'sudo -n grep "http-check send" /etc/haproxy/haproxy.cfg' 2>/dev/null || true)"
done

# --- 3. Le réseau des pods (Cilium) --------------------------------------------------------------------
_m14d_e05_ds="$(_m14d_k -n kube-system get daemonsets -o json)"
for _m14d_e05_d in cilium kube-proxy; do
  check_cmd "DaemonSet $_m14d_e05_d : six pods prêts" _m14d_json "$_m14d_e05_ds" \
    '.items[] | select(.metadata.name == $d) | .status.desiredNumberScheduled == 6 and .status.numberReady == 6' --arg d "$_m14d_e05_d"
done
_m14d_e05_dep="$(_m14d_k -n kube-system get deployments -o json)"
for _m14d_e05_d in cilium-operator hubble-relay coredns; do
  check_cmd "Deployment $_m14d_e05_d : tous les réplicas disponibles" _m14d_json "$_m14d_e05_dep" \
    '.items[] | select(.metadata.name == $d) | .status.replicas >= 1 and .status.availableReplicas == .status.replicas' --arg d "$_m14d_e05_d"
done
_m14d_e05_cfg="$(_m14d_k -n kube-system get configmap cilium-config -o json)"
check_cmd "Cilium : IPAM cluster-pool 10.240.0.0/16 (/24 par nœud), kube-proxy conservé" _m14d_json "$_m14d_e05_cfg" \
  '.data.ipam == "cluster-pool" and .data["cluster-pool-ipv4-cidr"] == "10.240.0.0/16"
   and .data["cluster-pool-ipv4-mask-size"] == "24" and .data["kube-proxy-replacement"] == "false"'
check_cmd "Cilium : relais Hubble activé, cluster nommé k8s-par1" _m14d_json "$_m14d_e05_cfg" \
  '.data["enable-hubble"] == "true" and .data["cluster-name"] == "k8s-par1"'
check_cmd "Cilium : les agents joignent l'API par la VIP ($_M14D_API:8443)" _m14d_json \
  "$(_m14d_k -n kube-system get daemonset cilium -o json)" \
  '[.spec.template.spec.containers[] | select(.name == "cilium-agent") | .env[]? | select(.name | startswith("KUBERNETES_SERVICE_")) | .value] | sort == ["8443", $h]' \
  --arg h "$_M14D_API"
check_cmd "Chaque nœud a reçu un /24 de 10.240.0.0/16 (CiliumNode)" _m14d_json "$(_m14d_k get ciliumnodes -o json)" \
  '(.items | length == 6) and all(.items[]; (.spec.ipam.podCIDRs // []) | length >= 1 and all(.[]; test("^10\\.240\\.[0-9]+\\.0/24$")))'
check_cmd "CoreDNS : deux pods prêts sur des adresses de 10.240.0.0/16" _m14d_json "$_m14d_e05_pods" \
  '[.items[] | select(.metadata.labels["k8s-app"] == "kube-dns" and .status.phase == "Running")
    | select(.status.podIP | test("^10\\.240\\.")) | select(all(.status.containerStatuses[]; .ready))] | length == 2'
check_cmd "Plus aucun pod du test de connectivité (espace cilium-test-* supprimé)" bash -c \
  '[[ "$1" == *namespace/kube-system* ]] && ! grep -q "cilium-test" <<<"$1"' _ "$(_m14d_k get namespaces -o name)"

# --- 4. adm01 ----------------------------------------------------------------------------------------
check_output "adm01 : kubectl 1.36 (une mineure d'écart au plus avec le cluster)" 'Client Version: v1\.36\.' kubectl version --client
check_output "adm01 : Helm 4.3" '^v4\.3\.' helm version --short
check_output "adm01 : CLI cilium 0.20" 'cilium-cli: v0\.20\.' cilium version --client
check_output "adm01 : CLI hubble 1.20" '^hubble v1\.20\.' hubble version
check_output "adm01 : etcdctl de la version d'etcd du cluster ($_M14D_ETCD)" "^etcdctl version: ${_M14D_ETCD//./\\.}\$" etcdctl version
check_cmd "adm01 : k9s installé" command -v k9s

# --- 5. Le code et la documentation -------------------------------------------------------------------
for _m14d_e05_f in roles/k8s_plan_controle/tasks/jonction.yml roles/k8s_travailleur/tasks/main.yml roles/outils_k8s/tasks/main.yml; do
  check_cmd "plateforme/ansible (main) : $_m14d_e05_f" _m14d_fichier_main plateforme/ansible "$_m14d_e05_f"
done
check_output "plateforme/k8s (main) : composants/cilium/values.yaml (cluster-pool, VIP)" 'k8sServiceHost: *k8s-api\.par1\.medisphere\.internal' \
  _m14d_contenu_main plateforme/k8s composants/cilium/values.yaml
check_output "plateforme/k8s (main) : Taskfile.yml (noeuds, cilium, appliquer)" '^ +appliquer:' \
  _m14d_contenu_main plateforme/k8s Taskfile.yml
check_cmd "plateforme/medisphere (main) : fiche du cluster docs/kubernetes/cluster.md" \
  _m14d_fichier_main plateforme/medisphere docs/kubernetes/cluster.md
