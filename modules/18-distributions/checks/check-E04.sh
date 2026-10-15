# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
#
# check-E04.sh — M18-E04 : RKE2, un cluster durci (à lancer AVANT de retirer le groupe rke2)
# À lancer depuis adm01. Lecture seule : qm config, SSH vers rke2-01..03 (rpm -q, getenforce,
# systemctl, getent, grep), kubectl get avec rke2.kubeconfig, GitLab en GET.

# shellcheck source=_m18-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m18-decouverte.sh"

title "M18-E04 — RKE2 : un cluster durci"
require_cmd jq kubectl

_m18d_e04_i=2
for _m18d_e04_n in "${_M18D_RKE2[@]}"; do
  _m18d_vm "$_m18d_e04_n" "218$_m18d_e04_i" "$_m18d_e04_n" 2 4096 "bc:24:11:99:18:8$_m18d_e04_i" env-m18 role-rke2
  _m18d_e04_i=$((_m18d_e04_i + 1))
  check_output "$_m18d_e04_n : Rocky Linux 10" '^10' remote "$_m18d_e04_n" '. /etc/os-release && [ "$ID" = rocky ] && echo "$VERSION_ID"'
  check_output "$_m18d_e04_n : rke2-server 1.36.5~rke2r1 et rke2-selinux installés" '^rke2-server-1\.36\.5~rke2r1.*rke2-selinux-' \
    remote "$_m18d_e04_n" 'rpm -q rke2-server rke2-selinux | paste -sd " "'
  check_output "$_m18d_e04_n : SELinux Enforcing" '^Enforcing$' remote "$_m18d_e04_n" 'getenforce'
  check_ssh "$_m18d_e04_n : firewalld inactif" "$_m18d_e04_n" '! systemctl is-active --quiet firewalld'
  check_ssh "$_m18d_e04_n : utilisateur et groupe etcd locaux" "$_m18d_e04_n" 'grep -q "^etcd:" /etc/passwd && grep -q "^etcd:" /etc/group'
  check_ssh "$_m18d_e04_n : paramètres noyau CIS dans /etc/sysctl.d/60-rke2-cis.conf, et chargés" "$_m18d_e04_n" \
    'test -f /etc/sysctl.d/60-rke2-cis.conf && [ "$(sysctl -n kernel.panic_on_oops)" = 1 ] && [ "$(sysctl -n vm.overcommit_memory)" = 1 ]'
  check_ssh "$_m18d_e04_n : profile: cis dans /etc/rancher/rke2/config.yaml" "$_m18d_e04_n" \
    'sudo -n grep -Eq "^profile: \"?cis\"?$" /etc/rancher/rke2/config.yaml'
  check_output "$_m18d_e04_n : etcd tourne sous l'utilisateur etcd" '^etcd$' remote "$_m18d_e04_n" 'ps -o user= -C etcd | sort -u'
done

# --- Le cluster ---------------------------------------------------------------------------------
check_cmd "rke2.kubeconfig en 600" _m18d_600 "$_M18D_DIR/rke2.kubeconfig"
check_output "rke2.kubeconfig : serveur https://rke2-01.par1.medisphere.internal:6443" '^https://rke2-01\.par1\.medisphere\.internal:6443$' \
  _m18d_serveur rke2
_m18d_e04_noeuds="$(_m18d_kj rke2 get nodes -o json)"
check_cmd "Trois nœuds Ready en v1.36.5+rke2r1" _m18d_noeuds_prets "$_m18d_e04_noeuds" 3 v1.36.5+rke2r1
check_cmd "Les trois nœuds sont control-plane et etcd" _m18d_json "$_m18d_e04_noeuds" \
  'all(.items[]; .metadata.labels["node-role.kubernetes.io/control-plane"] == "true" and .metadata.labels["node-role.kubernetes.io/etcd"] == "true")'
check_ssh "Pod Security : restricted par défaut dans la configuration d'admission de RKE2" "${_M18D_RKE2[0]}" \
  'sudo -n grep -Eq "enforce: \"?restricted\"?" /etc/rancher/rke2/rke2-pss.yaml'
check_cmd "NetworkPolicies posées par le profil dans kube-system, kube-public et default" _m18d_json \
  "$(_m18d_kj rke2 get networkpolicies -A -o json)" \
  '([.items[].metadata.namespace] | unique) as $e | ($e | index("kube-system")) and ($e | index("kube-public")) and ($e | index("default"))'
check_cmd "Pod essai-cis/conforme en cours d'exécution" _m18d_json \
  "$(_m18d_kj rke2 -n essai-cis get pod conforme -o json)" '.status.phase == "Running"'

# --- Le code et la documentation ---------------------------------------------------------------
_m18d_fichiers_main plateforme/ansible roles/rke2/tasks/main.yml inventories/lab/group_vars/role_rke2/rke2.yml
_m18d_fichiers_main plateforme/distributions rke2/README.md rke2/essai-cis/pod-conforme.yaml
_m18d_fichiers_main plateforme/medisphere docs/kubernetes/distributions/rke2.md
