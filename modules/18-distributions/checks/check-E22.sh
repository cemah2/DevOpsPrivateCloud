# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes distantes entre apostrophes
#
# check-E22.sh — M18-E22 « Panne : RKE2 ne démarre plus »
# Lecture seule : nœuds et pods etcd (kubeconfig rke2), service, profil, compte etcd, paramètres noyau,
# SELinux et configuration des trois serveurs (SSH, sudo -n pour lire), documentation sur main.

# shellcheck source=_m18-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m18-production.sh"

title "M18-E22 — RKE2 démarre sur les trois serveurs"
require_cmd kubectl jq ssh

check_cmd "l'API RKE2 répond (readyz)" _m18p_joignable "$_M18P_KC_RKE2"
check_cmd "trois nœuds Ready" _m18p_noeuds_prets "$_M18P_KC_RKE2" 3
_e22_etcd="$(_m18p_json "$_M18P_KC_RKE2" -n kube-system get pods -l component=etcd)"
check_cmd "trois membres etcd prêts (pods etcd-<nœud>)" _m18p_jq "$_e22_etcd" \
  '[.items[]? | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length == 3'

_e22_sysctl() {
  _m18p_sudo "$1" 'bash -c '\''f=/usr/share/rke2/rke2-cis-sysctl.conf; [ -r "$f" ] || f=/usr/local/share/rke2/rke2-cis-sysctl.conf
    n=0; while IFS="=" read -r k v; do k="${k// /}"; v="${v// /}"; case "$k" in ""|\#*) continue;; esac
    [ "$(sysctl -n "$k")" = "$v" ] || exit 1; n=$((n+1)); done < "$f"; [ "$n" -ge 3 ]'\'''
}
for _e22_n in "${_M18P_RKE2[@]}"; do
  title "$_e22_n"
  check_ssh "$_e22_n : rke2-server actif" "$_e22_n" 'systemctl is-active -q rke2-server'
  check_ssh_output "$_e22_n : profil cis dans la configuration" "$_e22_n" '^ok$' \
    'sudo -n grep -Eq "^profile: *\"?cis(-[0-9.]+)?\"? *$" /etc/rancher/rke2/config.yaml && echo ok'
  check_ssh_output "$_e22_n : protect-kernel-defaults non désactivé" "$_e22_n" '^ok$' \
    'sudo -n grep -rqsE "^protect-kernel-defaults: *(false|\"false\")" /etc/rancher/rke2/config.yaml /etc/rancher/rke2/config.yaml.d/ || echo ok'
  check_ssh_output "$_e22_n : compte et groupe etcd présents, etcd tourne sous etcd" "$_e22_n" '^etcd$' \
    'getent passwd etcd >/dev/null && getent group etcd >/dev/null && ps -o user= -C etcd | sort -u'
  check_cmd "$_e22_n : paramètres noyau du profil appliqués" _e22_sysctl "$_e22_n"
  check_ssh_output "$_e22_n : SELinux en mode enforcing" "$_e22_n" '^Enforcing$' 'getenforce'
  check_ssh_output "$_e22_n : config.yaml sans tabulation" "$_e22_n" '^ok$' \
    'sudo -n grep -qP "\t" /etc/rancher/rke2/config.yaml || echo ok'
done

title "Documentation"
check_cmd "RB-185 publié (messages typiques, vérifications de l'hôte du profil CIS, interdits)" \
  _m18p_doc_prefixe docs/kubernetes/distributions/runbooks RB-185 'journalctl' 'etcd' 'sysctl|noyau' 'cis'
check_cmd "journal de diagnostic INC-4522 publié dans docs/socle/journal/" \
  _m18p_un_fichier_contient plateforme/medisphere docs/socle/journal 'INC-4522'
