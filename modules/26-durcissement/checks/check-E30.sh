# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes distantes entre apostrophes
#
# check-E30.sh — M26-E30 « Correctifs de sécurité : le parc, le cluster et les images en service »
# À lancer depuis adm01. Lecture seule : configuration des mises à jour automatiques et minuteries sur
# un échantillon de VMs (SSH : apt-config dump, grep, systemctl is-*), métriques et règles (Thanos
# Query), fichiers sur main de plateforme/k8s et plateforme/ansible.

# shellcheck source=_m26-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-production.sh"

title "M26-E30 — Correctifs de sécurité : le parc, le cluster et les images en service"
require_cmd jq curl ssh

title "Mises à jour automatiques (échantillon de VMs)"
for _m26_e30_vm in "${_M26P_VMS[@]}"; do
  case "$(_m26p_famille "$_m26_e30_vm")" in
    Debian)
      check_ssh_output "$_m26_e30_vm : unattended-upgrades limité à l'origine de sécurité" "$_m26_e30_vm" \
        'label=Debian-Security' 'apt-config dump | grep -F Unattended-Upgrade::Origins-Pattern'
      # La liste noire n'existe pas dans la configuration du paquet : elle prouve que le rôle est passé.
      check_ssh "$_m26_e30_vm : liste noire des montées contrôlées (kubelet, keepalived…)" "$_m26_e30_vm" \
        'apt-config dump | grep -F "Unattended-Upgrade::Package-Blacklist::" | grep -q keepalived'
      check_ssh "$_m26_e30_vm : aucun redémarrage automatique" "$_m26_e30_vm" \
        'apt-config dump | grep -q "^Unattended-Upgrade::Automatic-Reboot \"false\""'
      check_ssh "$_m26_e30_vm : mises à niveau quotidiennes actives (APT::Periodic::Unattended-Upgrade)" "$_m26_e30_vm" \
        'apt-config dump | grep -q "^APT::Periodic::Unattended-Upgrade \"1\""'
      check_ssh "$_m26_e30_vm : needrestart en mode liste" "$_m26_e30_vm" \
        'grep -rqsE "nrconf\{restart\} *= *.l." /etc/needrestart/conf.d/'
      ;;
    RedHat)
      check_ssh "$_m26_e30_vm : dnf-automatic en mode sécurité, sans redémarrage" "$_m26_e30_vm" \
        'grep -Eq "^upgrade_type *= *security" /etc/dnf/automatic.conf && grep -Eq "^reboot *= *never" /etc/dnf/automatic.conf'
      check_ssh "$_m26_e30_vm : dnf-automatic.timer actif" "$_m26_e30_vm" 'systemctl is-active --quiet dnf-automatic.timer'
      ;;
    *) check_cmd "$_m26_e30_vm : distribution lue par SSH" false ;;
  esac
  check_ssh "$_m26_e30_vm : correctifs-etat.timer activé et actif" "$_m26_e30_vm" \
    'systemctl is-enabled --quiet correctifs-etat.timer && systemctl is-active --quiet correctifs-etat.timer'
done

title "Métriques et alertes"
check_output "toutes les VMs du socle publient medisphere_redemarrage_requis" '^0$' \
  _m26p_nb '(up{job="vms"} == 1) unless on (instance) medisphere_redemarrage_requis'
_m26_e30_nb="$(_m26p_valeur 'count(medisphere_redemarrage_requis)')"
check_cmd "des hôtes publient l'état des correctifs (${_m26_e30_nb:-0})" _m26p_compare "${_m26_e30_nb:-0}" '>' 0
for _m26_e30_a in RedemarrageEnAttente CorrectifsSecuriteEnAttente CorrectifsVerificationAbsente; do
  check_cmd "alerte $_m26_e30_a chargée par Prometheus" _m26p_alerte_chargee "$_m26_e30_a"
done

title "Outils sur main"
check_cmd "$_M26P_K8S : outils/cve-en-service.sh (digests en service, analyses de Harbor)" \
  _m26p_fichier_contient "$_M26P_K8S" outils/cve-en-service.sh 'imageID' 'scan_overview'
check_cmd "$_M26P_ANSIBLE : playbooks/redemarrages-vague.yml (un hôte à la fois, drain, noout)" \
  _m26p_fichier_contient "$_M26P_ANSIBLE" playbooks/redemarrages-vague.yml 'serial' 'drain' 'noout'
