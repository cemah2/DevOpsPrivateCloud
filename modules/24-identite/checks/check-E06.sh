# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes (variables jq, pas du shell)
#
# check-E06.sh — M24-E06 : Fédérer l'annuaire FreeIPA dans Keycloak
# À lancer depuis adm01. Lecture seule : API d'administration du royaume medisphere (wb-checks),
# annuaire en LDAPS (wb-checks de l'annuaire) pour comparer les deux côtés.

# shellcheck source=_m24-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-decouverte.sh"

title "M24-E06 — Fédérer l'annuaire FreeIPA dans Keycloak"
require_cmd jq curl ldapsearch

_m24d_e06_users_dn="cn=users,cn=accounts,$_M24D_BASE"

# _m24d_e06_cfg JSON CLÉ — première valeur de config[CLÉ] d'un composant Keycloak.
_m24d_e06_cfg() {
  jq -r --arg k "$2" '.config[$k][0] // empty' <<<"$1" 2>/dev/null || true
}

# _m24d_e06_egal A B — deux nombres égaux et non nuls.
_m24d_e06_egal() {
  [[ "$1" =~ ^[1-9][0-9]*$ && "$1" == "$2" ]] && echo egal
}

# _m24d_e06_aucun REGEX TEXTE — le texte est NON VIDE et aucune de ses lignes ne correspond.
_m24d_e06_aucun() { [[ -n "$2" ]] && ! grep -Eq -- "$1" <<<"$2"; }

# --- 1. Le fournisseur LDAP ---------------------------------------------------------------------------
_m24d_e06_ldap="$(_m24d_kc "components?type=org.keycloak.storage.UserStorageProvider" \
  | jq -c '[.[] | select(.providerId == "ldap")] | if length == 1 then .[0] else empty end' 2>/dev/null || true)"
if [[ -z "$_m24d_e06_ldap" ]]; then
  _ko "Royaume medisphere : aucune (ou plus d'une) fédération LDAP lisible par wb-checks"
  return 0
fi
_ok "Royaume medisphere : une fédération LDAP ($(jq -r .name <<<"$_m24d_e06_ldap"))"
check_output "Fédération : LDAPS vers ipa01 (ldaps://ipa01.par1.medisphere.internal, jamais ldap:// en clair)" \
  '^ldaps://ipa01\.par1\.medisphere\.internal(:636)?/?$' _m24d_e06_cfg "$_m24d_e06_ldap" connectionUrl
check_output "Fédération : liaison par le compte système svc-keycloak" \
  "^uid=svc-keycloak,cn=sysaccounts,cn=etc,$_M24D_BASE\$" _m24d_e06_cfg "$_m24d_e06_ldap" bindDn
check_output "Fédération : mode READ_ONLY (Keycloak n'écrit jamais dans l'annuaire)" '^READ_ONLY$' \
  _m24d_e06_cfg "$_m24d_e06_ldap" editMode
check_output "Fédération : utilisateurs cherchés sous cn=users,cn=accounts" "^${_m24d_e06_users_dn}\$" \
  _m24d_e06_cfg "$_m24d_e06_ldap" usersDn
check_cmd "Fédération : identifiant = uid, identifiant stable = ipaUniqueID" _m24d_json "$_m24d_e06_ldap" \
  '.config.usernameLDAPAttribute[0] == "uid" and .config.uuidLDAPAttribute[0] == "ipaUniqueID"'
check_output "Fédération : le compte admin de FreeIPA (bris de glace de l'annuaire) n'est pas importé" \
  'uid=admin' _m24d_e06_cfg "$_m24d_e06_ldap" customUserSearchFilter
check_output "Fédération : synchronisation des changements toutes les 15 minutes (900 s)" '^900$' \
  _m24d_e06_cfg "$_m24d_e06_ldap" changedSyncPeriod
check_output "Fédération : le magasin de confiance du système (racine MédiSphère) sert pour LDAPS" \
  '^(always|ldapsOnly)$' _m24d_e06_cfg "$_m24d_e06_ldap" useTruststoreSpi

# --- 2. Le mappeur de groupes -------------------------------------------------------------------------
_m24d_e06_lid="$(jq -r .id <<<"$_m24d_e06_ldap")"
_m24d_e06_gm="$(_m24d_kc "components?parent=$(_m24d_uri "$_m24d_e06_lid")&type=org.keycloak.storage.ldap.mappers.LDAPStorageMapper" \
  | jq -c '[.[] | select(.providerId == "group-ldap-mapper")] | .[0] // empty' 2>/dev/null || true)"
check_cmd "Mappeur de groupes : groupes de cn=groups,cn=accounts en lecture seule, appartenance par l'attribut member (DN)" \
  _m24d_json "$_m24d_e06_gm" \
  '.config["groups.dn"][0] == $dn and .config.mode[0] == "READ_ONLY"
   and .config["membership.ldap.attribute"][0] == "member" and .config["membership.attribute.type"][0] == "DN"' \
  --arg dn "cn=groups,cn=accounts,$_M24D_BASE"

# --- 3. Les personnes et les groupes vus par Keycloak ------------------------------------------------
_m24d_e06_lucas="$(_m24d_kc "users?username=lucas.martin&exact=true" | jq -c '.[0] // empty' 2>/dev/null || true)"
check_cmd "lucas.martin : importé de l'annuaire (lien de fédération vers ipa01), adresse reprise" _m24d_json "$_m24d_e06_lucas" \
  '.federationLink == $l and .email == "lucas.martin@medisphere.internal"' --arg l "$_m24d_e06_lid"
_m24d_e06_lucas_groupes() {
  local id
  id="$(jq -r '.id // empty' <<<"$_m24d_e06_lucas" 2>/dev/null || true)"
  [[ -n "$id" ]] && _m24d_kc "users/$id/groups" | jq -r '.[].name' 2>/dev/null
}
check_output "lucas.martin : membre du groupe plateforme dans Keycloak (lu dans l'annuaire)" '^plateforme$' _m24d_e06_lucas_groupes
check_cmd "lucas.martin : PAS membre de plateforme-admins" _m24d_e06_aucun '^plateforme-admins$' "$(_m24d_e06_lucas_groupes)"
for _m24d_e06_g in "${_M24D_GROUPES[@]}"; do
  check_cmd "Groupe $_m24d_e06_g présent dans Keycloak (premier niveau)" _m24d_json \
    "$(_m24d_kc "groups?search=$_m24d_e06_g&exact=true&briefRepresentation=true")" \
    '[.[].path] | index($p) != null' --arg p "/$_m24d_e06_g"
done
# Les groupes internes de FreeIPA (admins, ipausers, editors…) n'ont rien à faire dans Keycloak.
check_cmd "Aucun groupe interne de FreeIPA importé (admins, ipausers, editors, trust admins)" _m24d_e06_aucun \
  '^(admins|ipausers|editors|trust admins)$' \
  "$(_m24d_kc "groups?briefRepresentation=true&max=200" | jq -r '.[].name' 2>/dev/null || true)"

# --- 4. Plus de comptes locaux de personnes --------------------------------------------------------------
check_cmd "Plus aucun utilisateur LOCAL dans medisphere (l'utilisateur d'essai d'E05 est supprimé)" _m24d_json \
  "$(_m24d_kc "users?briefRepresentation=true&max=500")" \
  'length > 0 and ([.[] | select(.federationLink == null and (.username | startswith("service-account-") | not))] | length == 0)'

# --- 5. La portée « groupes » --------------------------------------------------------------------------
_m24d_e06_scope="$(_m24d_kc "client-scopes" | jq -c '[.[] | select(.name == "groupes")] | .[0] // empty' 2>/dev/null || true)"
check_cmd "Portée groupes : revendication « groups », noms courts (chemin complet désactivé), dans l'ID token, l'access token et userinfo" \
  _m24d_json "$_m24d_e06_scope" \
  '.protocol == "openid-connect"
   and ([.protocolMappers[]? | select(.protocolMapper == "oidc-group-membership-mapper")
         | select(.config["claim.name"] == "groups" and .config["full.path"] == "false"
                  and .config["id.token.claim"] == "true" and .config["access.token.claim"] == "true"
                  and .config["userinfo.token.claim"] == "true")] | length == 1)'
check_cmd "Portée groupes : portée par défaut du royaume (ajoutée à tout nouveau client)" _m24d_json \
  "$(_m24d_kc "default-default-client-scopes")" '[.[].name] | index("groupes") != null'

# --- 6. Annuaire et Keycloak d'accord ------------------------------------------------------------------
_m24d_e06_nb_ldap="$(_m24d_ldap "(&(objectClass=person)(objectClass=posixAccount)(!(uid=admin)))" uid \
  | grep -c "^dn: uid=[^,]*,$_m24d_e06_users_dn\$" || true)"
_m24d_e06_nb_kc="$(_m24d_kc "users?briefRepresentation=true&max=500" \
  | jq --arg l "$_m24d_e06_lid" '[.[] | select(.federationLink == $l)] | length' 2>/dev/null || true)"
check_output "Autant de personnes fédérées dans Keycloak ($_m24d_e06_nb_kc) que dans l'annuaire ($_m24d_e06_nb_ldap, hors admin)" \
  '^egal$' _m24d_e06_egal "$_m24d_e06_nb_ldap" "$_m24d_e06_nb_kc"
