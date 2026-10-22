# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes distantes et filtres entre apostrophes
#
# check-E19.sh — M24-E19 : inscrire les VMs dans FreeIPA (SSSD, HBAC, sudo).
# Vérifie, en lecture seule depuis adm01 :
#   - chaque hôte attendu est inscrit (entrée d'hôte dans l'annuaire, /etc/ipa/default.conf, SSSD
#     actif, une personne résolue) et le compte local admin n'est jamais résolu par SSSD ;
#   - la bordure (gw01, gw02) n'est pas inscrite ;
#   - les règles HBAC et sudo dans l'annuaire, allow_all désactivée ;
#   - sur mon01 : la décision HBAC pour lucas.martin (acceptée) et julien.petit (refusée), par sssctl
#     (consultation : aucune connexion n'est ouverte).

# shellcheck source=_m24-operationnel-c.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-operationnel-c.sh"

title "M24-E19 — Inscrire les VMs dans FreeIPA : SSSD, HBAC et sudo"
require_cmd jq ldapsearch

# --- 1. Les hôtes --------------------------------------------------------------------------------
_m24c_e19_hotes="$(_m24c_ldap '(objectClass=ipaHost)' fqdn | sed -n 's/^fqdn: //p')"
if [[ -z "$_m24c_e19_hotes" ]]; then
  _ko "Annuaire : aucune entrée d'hôte lisible par wb-checks (ipa-checks.env, lab/bin/check 24 03)"
fi
# Commande de consultation sur chaque hôte : inscrit, SSSD actif, personne résolue, admin local intact.
_m24c_e19_cmd='test -s /etc/ipa/default.conf && systemctl is-active --quiet sssd \
  && getent -s sss passwd lucas.martin >/dev/null && ! getent -s sss passwd admin >/dev/null \
  && getent -s files passwd admin >/dev/null && echo inscrit-sain'
for _m24c_e19_h in "${_M24C_INSCRITS[@]}"; do
  check_cmd "$_m24c_e19_h : hôte déclaré dans l'annuaire ($_m24c_e19_h.$_M24C_DOMAINE)" \
    grep -qx "$_m24c_e19_h.$_M24C_DOMAINE" <<<"$_m24c_e19_hotes"
  check_ssh_output "$_m24c_e19_h : inscrit, SSSD actif, personnes de l'annuaire résolues, admin reste local" \
    "$_m24c_e19_h" '^inscrit-sain$' "$_m24c_e19_cmd"
done
for _m24c_e19_h in "${_M24C_BORDURE[@]}"; do
  check_cmd "$_m24c_e19_h : la bordure n'est PAS inscrite dans l'annuaire" \
    bash -c '! grep -qx "$1" <<<"$2"' _ "$_m24c_e19_h.$_M24C_DOMAINE" "$_m24c_e19_hotes"
done

# --- 2. HBAC -------------------------------------------------------------------------------------------
# _m24c_e19_regle FILTRE ATTRIBUTS… — LDIF de la règle (vide si illisible).
_m24c_e19_regle() { _m24c_ldap "$@"; }
_m24c_e19_allow_all="$(_m24c_e19_regle '(&(objectClass=ipaHBACRule)(cn=allow_all))' ipaEnabledFlag)"
if [[ -z "$_m24c_e19_allow_all" ]]; then
  skip "règles HBAC de l'annuaire" "illisibles par le compte wb-checks : contrôle « ipa hbacrule-find » à la main"
else
  check_output "HBAC : allow_all désactivée (pas supprimée)" '^ipaEnabledFlag: FALSE$' \
    printf '%s\n' "$_m24c_e19_allow_all"
  _m24c_e19_plat="$(_m24c_e19_regle '(&(objectClass=ipaHBACRule)(cn=hbac-plateforme))' ipaEnabledFlag memberUser hostCategory memberService)"
  check_cmd "HBAC : hbac-plateforme active, groupes plateforme-admins et plateforme, tous les hôtes, sshd" \
    bash -c 'grep -q "^ipaEnabledFlag: TRUE" <<<"$1" && grep -q "^memberUser: cn=plateforme-admins,cn=groups" <<<"$1" \
      && grep -q "^memberUser: cn=plateforme,cn=groups" <<<"$1" && grep -q "^hostCategory: all" <<<"$1" \
      && grep -q "^memberService: cn=sshd," <<<"$1" && [[ $(grep -c "^memberUser:" <<<"$1") -eq 2 ]]' _ "$_m24c_e19_plat"
  _m24c_e19_supp="$(_m24c_e19_regle '(&(objectClass=ipaHBACRule)(cn=hbac-support))' ipaEnabledFlag memberUser memberHost hostCategory)"
  check_cmd "HBAC : hbac-support active, groupe support, mon01 et nbx01 seulement" \
    bash -c 'grep -q "^ipaEnabledFlag: TRUE" <<<"$1" && grep -q "^memberUser: cn=support,cn=groups" <<<"$1" \
      && ! grep -q "^hostCategory:" <<<"$1" && [[ $(grep -c "^memberHost:" <<<"$1") -eq 2 ]] \
      && grep -q "^memberHost: fqdn=mon01\." <<<"$1" && grep -q "^memberHost: fqdn=nbx01\." <<<"$1"' _ "$_m24c_e19_supp"
fi

# --- 3. sudo -------------------------------------------------------------------------------------------
_m24c_e19_sudo_adm="$(_m24c_ldap '(&(objectClass=ipaSudoRule)(cn=sudo-plateforme-admins))' ipaEnabledFlag memberUser cmdCategory)"
_m24c_e19_sudo_pla="$(_m24c_ldap '(&(objectClass=ipaSudoRule)(cn=sudo-plateforme))' ipaEnabledFlag memberUser cmdCategory memberAllowCmd)"
if [[ -z "$_m24c_e19_sudo_adm$_m24c_e19_sudo_pla" ]]; then
  skip "règles sudo de l'annuaire" "absentes ou illisibles par wb-checks : contrôle « ipa sudorule-find » à la main"
else
  check_cmd "sudo : sudo-plateforme-admins active, groupe plateforme-admins, toutes commandes" \
    bash -c 'grep -q "^ipaEnabledFlag: TRUE" <<<"$1" && grep -q "^memberUser: cn=plateforme-admins,cn=groups" <<<"$1" \
      && grep -q "^cmdCategory: all" <<<"$1"' _ "$_m24c_e19_sudo_adm"
  check_cmd "sudo : sudo-plateforme active, groupe plateforme, liste de commandes (PAS toutes les commandes)" \
    bash -c 'grep -q "^ipaEnabledFlag: TRUE" <<<"$1" && grep -q "^memberUser: cn=plateforme,cn=groups" <<<"$1" \
      && ! grep -q "^cmdCategory: all" <<<"$1" && grep -q "^memberAllowCmd:" <<<"$1"' _ "$_m24c_e19_sudo_pla"
fi
_m24c_e19_depot() {
  _m24c_sur_main plateforme/identite annuaire/hbac.yml 'hbac-plateforme' \
    && _m24c_sur_main plateforme/identite annuaire/sudo.yml 'sudo-plateforme'
}
check_cmd "annuaire/hbac.yml et annuaire/sudo.yml sur main de plateforme/identite" _m24c_e19_depot

# --- 4. La décision HBAC sur une machine ------------------------------------------------------------------
_m24c_e19_sssctl="$(_m24c_ssh "$_M24C_MON01" 'command -v sssctl >/dev/null && echo oui')"
if [[ "$_m24c_e19_sssctl" != oui ]]; then
  skip "décision HBAC sur mon01 (sssctl)" "sssctl absent de mon01 (paquet sssd-tools)"
else
  check_ssh_output "mon01 : lucas.martin (plateforme) peut entrer par sshd" "$_M24C_MON01" 'pam_acct_mgmt: Success' \
    'sudo -n sssctl user-checks -a acct -s sshd lucas.martin 2>&1'
  check_ssh_output "mon01 : julien.petit (mediagenda, aucune règle HBAC) est refusé" "$_M24C_MON01" \
    'pam_acct_mgmt: (Permission denied|Authentication failure)' \
    'sudo -n sssctl user-checks -a acct -s sshd julien.petit 2>&1'
fi
