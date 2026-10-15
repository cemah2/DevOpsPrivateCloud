# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E04.sh — M14-E04 : Amorcer le cluster avec kubeadm
# À lancer depuis adm01. Lecture seule : fichiers de k8s-cp01 en SSH (sudo -n stat, openssl),
# kubectl « get » (kubeconfig des checks, ou repli SSH avec admin.conf avant M14-E06), API GitLab.

# shellcheck source=_m14-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-decouverte.sh"

title "M14-E04 — Amorcer le cluster avec kubeadm"
require_cmd jq curl

_m14d_e04_cp="$_M14D_REF"

# --- 1. Le nœud amorcé -----------------------------------------------------------------------------
check_ssh "$_m14d_e04_cp : quatre manifestes statiques (etcd, kube-apiserver, kube-controller-manager, kube-scheduler)" \
  "$_m14d_e04_cp" 'for c in etcd kube-apiserver kube-controller-manager kube-scheduler; do sudo -n test -s /etc/kubernetes/manifests/$c.yaml || exit 1; done'
check_ssh "$_m14d_e04_cp : fichier kubeadm du nœud en 600 (/etc/kubernetes/kubeadm/kubeadm-config.yaml)" "$_m14d_e04_cp" \
  '[ "$(sudo -n stat -c "%a %U" /etc/kubernetes/kubeadm/kubeadm-config.yaml)" = "600 root" ]'
check_ssh "$_m14d_e04_cp : admin.conf présent, lisible par root seul" "$_m14d_e04_cp" \
  '[ "$(sudo -n stat -c "%a %U" /etc/kubernetes/admin.conf)" = "600 root" ]'
check_ssh "$_m14d_e04_cp : super-admin.conf retiré du nœud (copie chiffrée dans plateforme/k8s)" "$_m14d_e04_cp" \
  '! sudo -n test -e /etc/kubernetes/super-admin.conf'
check_ssh "$_m14d_e04_cp : certificat de kube-apiserver valable pour $_M14D_API et $_M14D_VIP" "$_m14d_e04_cp" \
  "sudo -n openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -ext subjectAltName | grep -q 'DNS:${_M14D_API}' && sudo -n openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -ext subjectAltName | grep -q 'IP Address:${_M14D_VIP}'"
check_ssh "$_m14d_e04_cp : CA du cluster valable 10 ans environ (au moins 9 ans restants)" "$_m14d_e04_cp" \
  'sudo -n openssl x509 -in /etc/kubernetes/pki/ca.crt -noout -checkend $((9*365*24*3600))'
check_ssh "$_m14d_e04_cp : kubelet configuré par kubeadm, pilote de cgroups systemd" "$_m14d_e04_cp" \
  'sudo -n grep -qx "cgroupDriver: systemd" /var/lib/kubelet/config.yaml && systemctl is-active --quiet kubelet'
check_ssh_output "L'API répond par la VIP et HAProxy : /readyz = ok (TLS vérifié par la CA du cluster)" "$_m14d_e04_cp" '^ok$' \
  "curl -sS --max-time 5 --cacert /etc/kubernetes/pki/ca.crt https://${_M14D_API}:8443/readyz"

# --- 2. La configuration enregistrée dans le cluster ---------------------------------------------------
_m14d_e04_cc="$(_m14d_k -n kube-system get configmap kubeadm-config -o jsonpath='{.data.ClusterConfiguration}')"
check_cmd "ConfigMap kubeadm-config lisible (le cluster répond)" test -n "$_m14d_e04_cc"
check_cmd "ClusterConfiguration : clusterName k8s-par1, kubernetesVersion v$_M14D_VERSION" bash -c \
  'grep -qx "clusterName: k8s-par1" <<<"$1" && grep -qx "kubernetesVersion: v$2" <<<"$1"' _ "$_m14d_e04_cc" "$_M14D_VERSION"
check_cmd "ClusterConfiguration : controlPlaneEndpoint $_M14D_API:8443" grep -qx "controlPlaneEndpoint: $_M14D_API:8443" <<<"$_m14d_e04_cc"
check_cmd "ClusterConfiguration : pods 10.240.0.0/16, services 10.96.0.0/16" bash -c \
  'grep -qx "  podSubnet: 10.240.0.0/16" <<<"$1" && grep -qx "  serviceSubnet: 10.96.0.0/16" <<<"$1"' _ "$_m14d_e04_cc"
check_output "kube-proxy en mode iptables explicite" '^mode: iptables$' \
  _m14d_k -n kube-system get configmap kube-proxy -o jsonpath='{.data.config\.conf}'
check_output "Nœud $_m14d_e04_cp enregistré en v$_M14D_VERSION" "^v${_M14D_VERSION//./\\.}$" \
  _m14d_k get node "$_m14d_e04_cp" -o jsonpath='{.status.nodeInfo.kubeletVersion}'
check_output "Liaison kubeadm:cluster-admins → cluster-admin (l'identité d'admin.conf)" '^cluster-admin kubeadm:cluster-admins$' \
  _m14d_k get clusterrolebinding kubeadm:cluster-admins -o jsonpath='{.roleRef.name} {.subjects[0].name}'

# --- 3. Le code et les secrets ---------------------------------------------------------------------
_m14d_e04_conf="$(_m14d_contenu_main plateforme/k8s cluster/kubeadm-config.yaml)"
check_cmd "plateforme/k8s (main) : cluster/kubeadm-config.yaml en v1beta4 avec controlPlaneEndpoint" bash -c \
  'grep -q "^apiVersion: kubeadm.k8s.io/v1beta4" <<<"$1" && grep -q "^controlPlaneEndpoint: k8s-api.par1.medisphere.internal:8443" <<<"$1"' \
  _ "$_m14d_e04_conf"
check_cmd "plateforme/k8s (main) : le fichier du cluster n'a ni InitConfiguration ni JoinConfiguration" bash -c \
  '[[ -n "$1" ]] && ! grep -Eq "^kind: *(Init|Join)Configuration" <<<"$1"' _ "$_m14d_e04_conf"
for _m14d_e04_s in admin super-admin; do
  check_output "plateforme/k8s (main) : secrets/$_m14d_e04_s.conf.vault chiffré (Ansible Vault, identité critique)" \
    '^\$ANSIBLE_VAULT;1\.2;AES256;critique' _m14d_contenu_main plateforme/k8s "secrets/$_m14d_e04_s.conf.vault"
done
check_cmd "plateforme/k8s (main) : aucun kubeconfig, clé ou certificat en clair dans le dépôt" bash -c \
  '[[ -n "$1" ]] && ! grep -Eq "(\.conf|\.kubeconfig|\.key|\.pem|\.crt)$" <<<"$1"' _ "$(_m14d_arbre_main plateforme/k8s)"
