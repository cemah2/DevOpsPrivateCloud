# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes distantes entre apostrophes
#
# check-E11.sh — M26-E11 : accès (SSH, PAM, sudo, comptes).
# À lancer depuis adm01. Lecture seule : SSH de consultation (sshd -T et lectures par « sudo -n »)
# vers les VMs d'essai (après E14 : un hôte durci de chaque famille), GitLab, ~/m26/e11.

# shellcheck source=_m26-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-operationnel.sh"

title "M26-E11 — Accès : SSH, PAM, sudo et comptes"
require_cmd jq curl ssh

_m26o_e11_deb="$(_m26o_essai deb)"
_m26o_e11_rocky="$(_m26o_essai rocky)"

for _m26o_e11_h in "$_m26o_e11_deb" "$_m26o_e11_rocky"; do
  check_ssh_output "$_m26o_e11_h : sshd n'accepte que des groupes nommés (AllowGroups, dont admin)" "$_m26o_e11_h" \
    '^allowgroups admin$' 'sudo -n sshd -T 2>/dev/null | grep "^allowgroups"'
  check_ssh_output "$_m26o_e11_h : les personnes de plateforme-admins restent autorisées en SSH" "$_m26o_e11_h" \
    '^allowgroups plateforme-admins$' 'sudo -n sshd -T 2>/dev/null | grep "^allowgroups"'
  check_ssh_output "$_m26o_e11_h : connexion root toujours refusée" "$_m26o_e11_h" \
    '^permitrootlogin no$' 'sudo -n sshd -T 2>/dev/null | grep "^permitrootlogin"'
  check_ssh "$_m26o_e11_h : aucune clé d'hôte ECDSA NIST présentée" "$_m26o_e11_h" \
    'a=$(sudo -n sshd -T 2>/dev/null | grep "^hostkeyalgorithms "); [ -n "$a" ] && ! grep -q "ecdsa-sha2-nistp" <<<"$a"'
  check_ssh "$_m26o_e11_h : sudo dans un pseudo-terminal et journal dédié (00-durcissement)" "$_m26o_e11_h" \
    'sudo -n grep -q "^Defaults use_pty" /etc/sudoers.d/00-durcissement && sudo -n grep -q "^Defaults logfile=" /etc/sudoers.d/00-durcissement'
  check_ssh "$_m26o_e11_h : faillock limité aux comptes locaux (annuaire : politique de FreeIPA)" "$_m26o_e11_h" \
    'grep -Eq "^[[:space:]]*local_users_only" /etc/security/faillock.conf && grep -Eq "^[[:space:]]*deny[[:space:]]*=" /etc/security/faillock.conf'
  check_ssh "$_m26o_e11_h : pam_faillock présent dans la pile d'authentification" "$_m26o_e11_h" \
    'grep -qs pam_faillock.so /etc/pam.d/common-auth || grep -qs pam_faillock.so /etc/pam.d/system-auth'
  check_ssh "$_m26o_e11_h : su réservé à un groupe (pam_wheel)" "$_m26o_e11_h" \
    'grep -Eq "^auth[[:space:]]+required[[:space:]]+pam_wheel\.so.*group=" /etc/pam.d/su'
done

check_ssh_output "$_m26o_e11_deb : échange de clés hybride post-quantique en tête (Debian)" "$_m26o_e11_deb" \
  '^kexalgorithms mlkem768x25519-sha256,' 'sudo -n sshd -T 2>/dev/null | grep "^kexalgorithms"'
check_ssh_output "$_m26o_e11_rocky : politique cryptographique MédiSphère pour SSH (Rocky)" "$_m26o_e11_rocky" \
  'NO-SSHCBC.*NO-WEAKMAC.*NO-SSHNIST|NO-SSHNIST' 'update-crypto-policies --show'

for _m26o_e11_p in medisphere-debian13.txt medisphere-rocky10.txt; do
  check_cmd "plateforme/medisphere : politique ssh-audit $_m26o_e11_p (listes d'échanges de clés et de chiffrements)" \
    bash -c 'grep -q "^key exchanges = " <<<"$1" && grep -q "^ciphers = " <<<"$1"' _ \
    "$(_m26o_contenu "$_M26O_P_DOC" "$_M26O_DOC_DURCI/ssh-audit/$_m26o_e11_p")"
done
check_cmd "travail ~/m26/e11/acces.md : essais d'accès consignés (faillock et HBAC compris)" bash -c \
  'f="$1"; [[ -s "$f" ]] && grep -qi faillock "$f" && grep -Eqi "hbac|refus" "$f" && grep -qi secours "$f"' _ "$_M26O_TRAVAIL/e11/acces.md"
