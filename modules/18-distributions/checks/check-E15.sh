# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes distantes et filtres entre apostrophes
#
# check-E15.sh — M18-E15 « Durcissement comparé »
# Lecture seule : profil et état CIS des serveurs RKE2 (SSH, sudo -n : grep, ps, sysctl -n), état du
# chiffrement des Secrets de k3s01 (« k3s secrets-encrypt status »), état de capi-essai vu du cluster de
# gestion, documentation et rapports sur main.

# shellcheck source=_m18-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m18-production.sh"

title "M18-E15 — Durcissement comparé"
require_cmd kubectl jq ssh

title "RKE2 (profil cis)"
# Tous les paramètres du fichier sysctl du profil ont la valeur demandée (lecture du fichier sur le nœud).
_e15_sysctl() {
  _m18p_sudo "$1" 'bash -c '\''f=/usr/share/rke2/rke2-cis-sysctl.conf; [ -r "$f" ] || f=/usr/local/share/rke2/rke2-cis-sysctl.conf
    n=0; while IFS="=" read -r k v; do k="${k// /}"; v="${v// /}"; case "$k" in ""|\#*) continue;; esac
    [ "$(sysctl -n "$k")" = "$v" ] || exit 1; n=$((n+1)); done < "$f"; [ "$n" -ge 3 ]'\'''
}
for _e15_n in "${_M18P_RKE2[@]}"; do
  check_ssh_output "$_e15_n : profil cis dans la configuration" "$_e15_n" '^ok$' \
    'sudo -n grep -Eq "^profile: *\"?cis(-[0-9.]+)?\"? *$" /etc/rancher/rke2/config.yaml && echo ok'
  check_ssh_output "$_e15_n : etcd tourne sous l'utilisateur etcd" "$_e15_n" '^etcd$' 'ps -o user= -C etcd | sort -u'
  check_cmd "$_e15_n : paramètres noyau du profil appliqués" _e15_sysctl "$_e15_n"
done

title "k3s01 (cluster de gestion)"
check_ssh_output "k3s01 : chiffrement des Secrets activé" k3s01 'Encryption Status: Enabled' 'sudo -n k3s secrets-encrypt status'
check_ssh_output "k3s01 : rotation terminée (reencrypt_finished)" k3s01 'Current Rotation Stage: reencrypt_finished' \
  'sudo -n k3s secrets-encrypt status'
check_ssh_output "k3s01 : option secrets-encryption dans la configuration (posée par le rôle)" k3s01 '^ok$' \
  'sudo -n grep -rEqs "^secrets-encryption: *true" /etc/rancher/k3s/config.yaml /etc/rancher/k3s/config.yaml.d/ && echo ok'
check_cmd "capi-essai toujours disponible vu du cluster de gestion" _m18p_cluster_disponible

title "Documentation"
check_cmd "durcissement.md : tableau kubeadm / k3s / RKE2 / Talos, avec kube-bench et Pod Security" \
  _m18p_fichier_contient plateforme/medisphere docs/kubernetes/distributions/durcissement.md \
  'kubeadm' 'k3s' 'rke2' 'talos' 'kube-bench' 'pod security|PSA' 'chiffrement' 'module 26|M26'
_e15_rap="$(_m18p_arbre plateforme/medisphere docs/kubernetes/distributions/durcissement | grep -c '\.json$')" || _e15_rap=0
check_output "au moins trois rapports kube-bench publiés sous durcissement/ (lu : $_e15_rap)" '^ok$' \
  bash -c '(( $1 >= 3 )) && echo ok' _ "$_e15_rap"
