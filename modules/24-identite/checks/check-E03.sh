# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E03.sh — M24-E03 : Personnes, groupes et politiques de mot de passe en code
# À lancer depuis adm01. Lecture seule : annuaire en LDAPS avec le compte système wb-checks
# (~/.config/workbook/ipa-checks.env), fichiers et pipelines de plateforme/identite (GitLab).

# shellcheck source=_m24-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-decouverte.sh"

title "M24-E03 — Personnes, groupes et politiques de mot de passe en code"
require_cmd jq curl ldapsearch

_m24d_e03_users="cn=users,cn=accounts,$_M24D_BASE"
_m24d_e03_groupes="cn=groups,cn=accounts,$_M24D_BASE"
# _m24d_e03_aucun REGEX TEXTE — le texte est NON VIDE et aucune de ses lignes ne correspond
# (un texte vide = donnée illisible : jamais un succès).
_m24d_e03_aucun() { [[ -n "$2" ]] && ! grep -Eq -- "$1" <<<"$2"; }

# _m24d_e03_membres GROUPE — identifiants des membres directs (un par ligne, triés).
_m24d_e03_membres() {
  _m24d_ldap "(&(objectClass=ipausergroup)(cn=$1))" member \
    | sed -n "s/^member: uid=\\([^,]*\\),$_m24d_e03_users\$/\\1/p" | sort
}

# _m24d_e03_membres_tous GROUPE — membres sur une seule ligne, séparés par des espaces (vide si illisible).
_m24d_e03_membres_tous() {
  _m24d_e03_membres "$1" | paste -sd' '
}

# --- 1. Le compte des vérifications et le projet -----------------------------------------------
check_output "Compte système wb-checks : liaison LDAPS acceptée (ipa-checks.env, uid=wb-checks,cn=sysaccounts,cn=etc)" \
  '^uid: admin$' _m24d_ldap '(uid=admin)' uid
check_output "ipa-checks.env en 600 (secret local, jamais dans un dépôt)" '^600$' \
  stat -c %a "${WB_IPA_CHECKS_FILE:-$HOME/.config/workbook/ipa-checks.env}"
for _m24d_e03_f in annuaire/personnes.yml annuaire/groupes.yml annuaire/politiques.yml annuaire/comptes-systeme.yml annuaire/annuaire.yml .gitlab-ci.yml; do
  check_cmd "plateforme/identite : $_m24d_e03_f présent sur main" \
    _m24d_contient "$(_m24d_contenu_main plateforme/identite "$_m24d_e03_f")" '[a-z]'
done
_m24d_e03_ci="$(_m24d_contenu_main plateforme/identite .gitlab-ci.yml)"
check_cmd ".gitlab-ci.yml : application de l'annuaire par un job MANUEL de main" \
  _m24d_contient "$_m24d_e03_ci" 'when: manual'
check_output "Dernier pipeline de main de plateforme/identite réussi" '^success$' _m24d_pipeline_main plateforme/identite
_m24d_e03_vault="$(_m24d_contenu_main plateforme/identite annuaire/vault-critique.yml)"
if [[ -n "$_m24d_e03_vault" ]]; then
  check_cmd "annuaire/vault-critique.yml chiffré par Ansible Vault (identité critique)" \
    _m24d_contient "$(head -n 1 <<<"$_m24d_e03_vault")" '^[$]ANSIBLE_VAULT;1\.2;AES256;critique$'
else
  skip "annuaire/vault-critique.yml chiffré" "fichier absent de main (secrets rangés ailleurs ?)"
fi

# --- 2. Les personnes ---------------------------------------------------------------------------------
_m24d_e03_personnes=("${_M24D_PERSONNAGES[@]}")
if [[ -n "$_M24D_MOI" ]]; then
  _m24d_e03_personnes+=("$_M24D_MOI")
else
  skip "Ton compte dans l'annuaire" "WB_MOI non renseigné dans lab/lab.env"
fi
for _m24d_e03_u in "${_m24d_e03_personnes[@]}"; do
  check_output "Personne $_m24d_e03_u : compte actif avec une adresse @medisphere.internal" \
    "^mail: ${_m24d_e03_u//./\\.}@medisphere\\.internal\$" \
    _m24d_ldap "(&(uid=$_m24d_e03_u)(objectClass=person)(!(nsAccountLock=TRUE)))" mail
done

# « Aucune personne créée à la main » : tout compte de cn=users (sauf admin) est dans personnes.yml.
_m24d_e03_code="$(_m24d_contenu_main plateforme/identite annuaire/personnes.yml)"
_m24d_e03_hors_code() {
  local u n=0
  [[ -n "$_m24d_e03_code" ]] || return 1
  while IFS= read -r u; do
    [[ -z "$u" || "$u" == admin ]] && continue
    if ! grep -Eq -- "(^|[^a-z0-9._-])${u//./\\.}([^a-z0-9._-]|\$)" <<<"$_m24d_e03_code"; then
      echo "  compte hors du code : $u" >&2
      n=$((n + 1))
    fi
  done < <(_m24d_ldap "(&(objectClass=person)(objectClass=posixAccount))" uid \
             | sed -n "s/^dn: uid=\\([^,]*\\),$_m24d_e03_users\$/\\1/p")
  ((n == 0))
}
check_cmd "Aucun compte de personne hors de annuaire/personnes.yml (hors admin, bris de glace)" _m24d_e03_hors_code

# --- 3. Les groupes -------------------------------------------------------------------------------------
for _m24d_e03_g in "${_M24D_GROUPES[@]}"; do
  check_output "Groupe $_m24d_e03_g présent" "^dn: cn=$_m24d_e03_g,$_m24d_e03_groupes\$" \
    _m24d_ldap "(&(objectClass=ipausergroup)(cn=$_m24d_e03_g))" cn
done
check_output "plateforme-admins : karim.benali membre" '^karim\.benali$' _m24d_e03_membres plateforme-admins
if [[ -n "$_M24D_MOI" ]]; then
  check_output "plateforme-admins : $_M24D_MOI membre" "^${_M24D_MOI//./\\.}\$" _m24d_e03_membres plateforme-admins
fi
check_cmd "plateforme-admins : ni lucas.martin ni personne hors de l'équipe Plateforme" _m24d_e03_aucun \
  '^(lucas\.martin|claire\.morel|sophie\.laurent|julien\.petit|nadia\.roussel)$' "$(_m24d_e03_membres plateforme-admins)"
check_output "plateforme : lucas.martin membre" '^lucas\.martin$' _m24d_e03_membres plateforme
check_output "mediagenda : julien.petit membre" '^julien\.petit$' _m24d_e03_membres mediagenda
check_output "securite : sophie.laurent membre" '^sophie\.laurent$' _m24d_e03_membres securite
check_output "support : nadia.roussel membre" '^nadia\.roussel$' _m24d_e03_membres support
check_output "direction : claire.morel membre" '^claire\.morel$' _m24d_e03_membres direction
check_output "Groupe admins de FreeIPA : admin seul (les droits d'IPA ne suivent pas plateforme-admins)" '^admin$' \
  _m24d_e03_membres_tous admins

# --- 4. La politique de mot de passe globale --------------------------------------------------------
_m24d_e03_pp="$(_m24d_ldap '(&(objectClass=krbPwdPolicy)(cn=global_policy))' krbPwdMinLength krbPwdHistoryLength krbPwdMaxFailure)"
if [[ -z "$_m24d_e03_pp" ]]; then
  skip "Politique de mot de passe globale (longueur 12, historique 6, verrouillage après 6 échecs)" \
    "illisible par wb-checks : contrôle par « ipa pwpolicy-show » dans le corrigé"
else
  check_output "Politique globale : 12 caractères au moins" '^krbPwdMinLength: (1[2-9]|[2-9][0-9])$' printf '%s\n' "$_m24d_e03_pp"
  check_output "Politique globale : historique de 6 mots de passe" '^krbPwdHistoryLength: ([6-9]|[1-9][0-9])$' printf '%s\n' "$_m24d_e03_pp"
  check_output "Politique globale : verrouillage après 6 échecs" '^krbPwdMaxFailure: 6$' printf '%s\n' "$_m24d_e03_pp"
fi

# --- 5. Les comptes système -----------------------------------------------------------------------------
# Les entrées de cn=sysaccounts ne sont pas toutes lisibles par un autre compte système : on contrôle
# ici le code ; E06 prouve la liaison de svc-keycloak (fédération qui fonctionne).
_m24d_e03_sys="$(_m24d_contenu_main plateforme/identite annuaire/comptes-systeme.yml)"
check_cmd "comptes-systeme.yml : svc-keycloak déclaré" _m24d_contient "$_m24d_e03_sys" 'svc-keycloak'
check_cmd "comptes-systeme.yml : wb-checks déclaré" _m24d_contient "$_m24d_e03_sys" 'wb-checks'
check_cmd "comptes-systeme.yml : aucun mot de passe en clair (variables du Vault seulement)" _m24d_e03_aucun \
  '^[[:space:]]*(password|mot_de_passe|userpassword):[[:space:]]*[^[:space:]{"]' "$_m24d_e03_sys"
