# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées dans la VM
#
# check-E13.sh — M03-E13 « Durcir une image »
# Contrôle, sur la VM de recette m03-durci (2035, clone de l'image durcie), les exigences
# observables du ticket SEC-450, puis la présence du script et de la documentation dans le
# projet. Lecture seule : tout passe par l'agent QEMU (via pve01) et l'API GitLab.

# shellcheck source=_m03-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m03-production.sh"

title "M03-E13 — Durcir une image"
require_cmd jq ssh curl shellcheck
_m03_charger
_m03_e13=2035

check_cmd "VM 2035 (m03-durci, clone de l'image durcie) démarrée" _m03_en_marche "$_m03_e13"
check_cmd "VM 2035 : cloud-init a terminé sans erreur (le durcissement ne l'a pas cassé)" \
  _m03_gexec "$_m03_e13" 'cloud-init status --wait >/dev/null'

title "SSH (configuration effective, sshd -T)"
_m03_sshd="$(_m03_gexec "$_m03_e13" 'sshd -T 2>/dev/null')" || true
_m03_sshd_vaut() { grep -Eqx -- "$1" <<<"$_m03_sshd"; }
check_cmd "connexion root refusée" _m03_sshd_vaut 'permitrootlogin no'
check_cmd "authentification par mot de passe refusée" _m03_sshd_vaut 'passwordauthentication no'
check_cmd "redirection X11 refusée" _m03_sshd_vaut 'x11forwarding no'
check_cmd "transfert d'agent refusé" _m03_sshd_vaut 'allowagentforwarding no'
check_cmd "au plus 3 tentatives d'authentification" _m03_sshd_vaut 'maxauthtries [1-3]'
check_cmd "délai d'authentification de 30 s au plus" _m03_sshd_vaut 'logingracetime ([1-9]|[12][0-9]|30)'
check_cmd "sessions inactives détectées (ClientAliveInterval > 0)" _m03_sshd_vaut 'clientaliveinterval [1-9][0-9]*'
check_cmd "bannière légale configurée" _m03_sshd_vaut 'banner /.+'
_m03_sshd_sans() { [[ -n "$_m03_sshd" ]] && ! grep -Eq -- "$1" <<<"$_m03_sshd"; }
check_cmd "aucun MAC SHA-1 proposé (ni échange de clés SHA-1)" _m03_sshd_sans '^(macs|kexalgorithms) .*sha1'

title "Noyau et réseau"
_m03_e13_sysctl() { _m03_gexec_match "$_m03_e13" "sysctl -n $1" "^$2\$"; }
check_cmd "redirections ICMP refusées (all)" _m03_e13_sysctl net.ipv4.conf.all.accept_redirects 0
check_cmd "redirections ICMP refusées sur l'interface de la route par défaut" \
  _m03_gexec_match "$_m03_e13" 'i=$(ip -4 route show default | sed -n "s/.* dev \([^ ]*\).*/\1/p" | head -n1); sysctl -n "net.ipv4.conf.$i.accept_redirects"' '^0$'
check_cmd "aucune redirection ICMP émise" _m03_e13_sysctl net.ipv4.conf.all.send_redirects 0
check_cmd "paquets martiens journalisés" _m03_e13_sysctl net.ipv4.conf.all.log_martians 1
check_cmd "adresses du noyau masquées à tous (kptr_restrict)" _m03_e13_sysctl kernel.kptr_restrict 2
check_cmd "protocole SCTP non chargeable" _m03_gexec_match "$_m03_e13" 'modprobe -n -v sctp 2>&1' '^install /(usr/)?bin/(false|true)'
check_cmd "stockage USB non chargeable" _m03_gexec_match "$_m03_e13" 'modprobe -n -v usb-storage 2>&1' '^install /(usr/)?bin/(false|true)'
check_cmd "système de fichiers ISO 9660 toujours disponible (lecteur cloud-init)" _m03_gexec "$_m03_e13" \
  'grep -qw iso9660 /proc/filesystems || modprobe -n -v isofs 2>&1 | grep -q "^insmod"'
check_cmd "/dev/shm monté noexec, nosuid, nodev" \
  _m03_gexec_match "$_m03_e13" 'findmnt -no OPTIONS /dev/shm' '^(.*,)?noexec(,|$)'

title "Traçabilité et surface d'attaque"
check_cmd "auditd actif" _m03_gexec "$_m03_e13" 'systemctl is-active -q auditd'
check_cmd "règles d'audit chargées (au moins 5)" \
  _m03_gexec "$_m03_e13" '[ "$(auditctl -l 2>/dev/null | grep -vc "^No rules")" -ge 5 ]'
check_cmd "aucun port TCP en écoute hors SSH (adresses non locales)" _m03_gexec "$_m03_e13" \
  '! ss -Htln | awk "{print \$4}" | grep -Ev "^(127\.[0-9.]+(%[a-z0-9]+)?|\[::1\]):[0-9]+$" | grep -Ev ":22$" | grep -q .'

title "Projet plateforme/images"
check_cmd "scripts/durcir.sh présent sur main" _m03_fichier_main scripts/durcir.sh
check_cmd "scripts/durcir.sh sans remarque ShellCheck (clone local)" shellcheck -x "$_M03_SRC/scripts/durcir.sh"
check_cmd "le build doré Debian applique durcir.sh (debian13-gold/build.pkr.hcl)" \
  _m03_fichier_main_contient debian13-gold/build.pkr.hcl 'durcir\.sh'
_m03_e13_doc() {
  _m03_fichier_main_contient docs/durcissement.md '(ANSSI|CIS)' \
    && _m03_fichier_main_contient docs/durcissement.md '[Ee]xception' \
    && _m03_fichier_main_contient docs/durcissement.md '([Aa]vant|[Aa]près)'
}
check_cmd "docs/durcissement.md sur main : références, exceptions, mesure avant/après" _m03_e13_doc
