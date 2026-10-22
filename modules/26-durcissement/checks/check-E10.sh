# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes distantes et filtres jq entre apostrophes
#
# check-E10.sh — M26-E10 : le rôle Ansible « durcissement » sur les VMs d'essai.
# À lancer depuis adm01. Lecture seule : GitLab (fichiers sur main), SSH de consultation vers les
# VMs d'essai (ou, après E14, vers un hôte durci de chaque famille), fichiers de travail ~/m26/e10.

# shellcheck source=_m26-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-operationnel.sh"

title "M26-E10 — Le rôle Ansible durcissement sur les VMs d'essai"
require_cmd jq curl ssh

for _m26o_e10_f in roles/durcissement/tasks/main.yml roles/durcissement/defaults/main.yml \
  roles/durcissement/meta/argument_specs.yml roles/durcissement/tasks/noyau.yml roles/durcissement/tasks/conformite.yml \
  playbooks/durcissement.yml playbooks/conformite-mesure.yml inventories/lab/durcissement.yml; do
  check_cmd "plateforme/ansible : $_m26o_e10_f sur main" _m26o_fichier "$_M26O_P_ANSIBLE" "$_m26o_e10_f"
done
_m26o_e10_exc=inventories/lab/group_vars/all/durcissement.yml
check_cmd "exceptions du parc : signées par sophie.laurent, avec une date de revue" \
  _m26o_contient "$_M26O_P_ANSIBLE" "$_m26o_e10_exc" '^[[:space:]]*valideur:[[:space:]]*sophie\.laurent'
check_cmd "exceptions du parc : les trois règles de routage sont déclarées (un seul réglage du noyau)" bash -c '
  c="$1"; for r in sysctl_net_ipv4_ip_forward sysctl_net_ipv4_conf_all_forwarding sysctl_net_ipv4_conf_default_forwarding; do
    grep -Eq "regle:[[:space:]]*$r\$" <<<"$c" || exit 1; done' _ "$(_m26o_contenu "$_M26O_P_ANSIBLE" "$_m26o_e10_exc")"

for _m26o_e10_h in "$(_m26o_essai deb)" "$(_m26o_essai rocky)"; do
  check_ssh_output "$_m26o_e10_h : kernel.kptr_restrict vaut 2 (fichier sysctl du rôle chargé)" "$_m26o_e10_h" \
    '^2$' 'sysctl -n kernel.kptr_restrict'
  check_ssh "$_m26o_e10_h : /etc/sysctl.d/60-durcissement.conf posé par le rôle" "$_m26o_e10_h" \
    'grep -q "rôle durcissement" /etc/sysctl.d/60-durcissement.conf'
  check_ssh_output "$_m26o_e10_h : /tmp monté sans exécution (noexec)" "$_m26o_e10_h" \
    '(^|,)noexec(,|$)' 'findmnt -no OPTIONS /tmp'
  check_ssh "$_m26o_e10_h : profils adaptés CIS et ANSSI et registre des exceptions présents" "$_m26o_e10_h" \
    'sudo -n test -s /etc/medisphere/conformite/tailoring-cis.xml && sudo -n test -s /etc/medisphere/conformite/tailoring-anssi.xml && sudo -n test -s /etc/medisphere/conformite/exceptions.json'
  check_ssh "$_m26o_e10_h : le profil adapté CIS désélectionne au moins une règle en exception" "$_m26o_e10_h" \
    'sudo -n grep -q "selected=\"false\"" /etc/medisphere/conformite/tailoring-cis.xml'
done

check_cmd "travail ~/m26/e10/scores.md : scores chiffrés de durci-deb" _m26o_travail e10/scores.md 'durci-deb.*[0-9]{2}'
check_cmd "travail ~/m26/e10/scores.md : scores chiffrés de durci-rocky" _m26o_travail e10/scores.md 'durci-rocky.*[0-9]{2}'
check_cmd "travail ~/m26/e10/conception.md : décision sur Molecule et essai d'exception refusée" bash -c \
  'f="$1"; [[ -s "$f" ]] && grep -qi molecule "$f" && grep -Eqi "valideur|revue" "$f"' _ "$_M26O_TRAVAIL/e10/conception.md"
