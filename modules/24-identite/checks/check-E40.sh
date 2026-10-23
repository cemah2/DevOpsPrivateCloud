# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes distantes et filtres entre apostrophes
#
# check-E40.sh — M24-E40 « Panne : SSH et sudo refusés sur les VMs »
# Vérifie, en lecture seule depuis adm01, chaque brique de l'accès aux VMs :
#   - annuaire : allow_all désactivée, hbac-plateforme et hbac-support actives, sudo-plateforme active
#     sur TOUS les hôtes (aucun hôte nommé) ;
#   - VM témoin (WB_M24_VM_SSSD, défaut nbx01) : SSSD actif, sssd.conf réservé à root (0600), une
#     personne résolue, règle sudo de lucas.martin visible ;
#   - mon01 : décision HBAC pour nadia.roussel (support) acceptée (sssctl, aucune connexion ouverte) ;
#   - step-ca : le provisioner keycloak émet le principal preferred_username (liste publique) ;
#   - documentation : section « SSH ou sudo refusé » de RB-246.

# shellcheck source=_m24-expert-b.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-expert-b.sh"

title "M24-E40 — Panne : SSH et sudo refusés sur les VMs"
require_cmd jq ldapsearch curl

# --- 1. Annuaire -----------------------------------------------------------------------------------
_m24y_e40_regle() { _m24c_ldap "$@"; }
_m24y_e40_aa="$(_m24y_e40_regle '(&(objectClass=ipaHBACRule)(cn=allow_all))' ipaEnabledFlag)"
if [[ -z "$_m24y_e40_aa" ]]; then
  skip "règles de l'annuaire" "illisibles par wb-checks (ipa-checks.env) : « ipa hbacrule-find » et « ipa sudorule-find » à la main"
else
  check_output "HBAC : allow_all toujours désactivée" '^ipaEnabledFlag: FALSE$' printf '%s\n' "$_m24y_e40_aa"
  for _m24y_e40_r in hbac-plateforme hbac-support; do
    check_output "HBAC : $_m24y_e40_r active" '^ipaEnabledFlag: TRUE$' \
      _m24y_e40_regle "(&(objectClass=ipaHBACRule)(cn=$_m24y_e40_r))" ipaEnabledFlag
  done
  _m24y_e40_sudo="$(_m24y_e40_regle '(&(objectClass=ipaSudoRule)(cn=sudo-plateforme))' ipaEnabledFlag hostCategory memberHost)"
  check_cmd "sudo : sudo-plateforme active, valable sur tous les hôtes (aucun hôte nommé)" \
    bash -c 'grep -q "^ipaEnabledFlag: TRUE" <<<"$1" && grep -q "^hostCategory: all" <<<"$1" && ! grep -q "^memberHost:" <<<"$1"' \
    _ "$_m24y_e40_sudo"
fi

# --- 2. VM témoin -----------------------------------------------------------------------------------
check_cmd "$_M24Y_VM_SSSD : SSSD actif, sssd.conf à root en 0600, lucas.martin résolu" _m24y_ssh_ok "$_M24Y_VM_SSSD" \
  'systemctl is-active --quiet sssd && [ "$(sudo -n stat -c "%U %a" /etc/sssd/sssd.conf)" = "root 600" ] \
   && getent -s sss passwd lucas.martin >/dev/null && echo oui'
check_ssh_output "$_M24Y_VM_SSSD : lucas.martin peut lire les journaux par sudo (groupe systemd-journal)" "$_M24Y_VM_SSSD" \
  'journalctl' 'sudo -n -l -U lucas.martin 2>&1'

# --- 3. HBAC sur mon01 -------------------------------------------------------------------------------
_m24y_e40_sssctl="$(_m24c_ssh "$_M24C_MON01" 'command -v sssctl >/dev/null && echo oui')"
if [[ "$_m24y_e40_sssctl" != oui ]]; then
  skip "décision HBAC sur mon01" "sssctl absent de mon01 (paquet sssd-tools)"
else
  check_ssh_output "mon01 : nadia.roussel (support) peut entrer par sshd" "$_M24C_MON01" 'pam_acct_mgmt: Success' \
    'sudo -n sssctl user-checks -a acct -s sshd nadia.roussel 2>&1'
fi

# --- 4. step-ca ---------------------------------------------------------------------------------------
_m24y_e40_prov="$(_m24c_provisioners)"
if [[ -z "$_m24y_e40_prov" ]]; then
  skip "provisioner keycloak de step-ca" "liste publique des provisioners illisible ($_M24C_STEP_CA)"
else
  check_cmd "step-ca : le provisioner keycloak met preferred_username comme seul principal (pas le courriel)" \
    _m24c_json "$_m24y_e40_prov" '[.provisioners[] | select(.name == "keycloak") | .options.ssh.template // ""][0]
      | test("principals\"\\s*:\\s*\\[\\s*\\{\\{\\s*toJson\\s+\\.Token\\.preferred_username\\s*\\}\\}\\s*\\]")'
fi

# --- 5. Documentation ----------------------------------------------------------------------------------
check_output "RB-246 : section SSH ou sudo refusé sur les VMs" '^#+ .*(SSH|sudo)' _m24y_rb246
