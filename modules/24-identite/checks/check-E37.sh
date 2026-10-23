# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq, requêtes LogQL et SQL entre apostrophes
#
# check-E37.sh — M24-E37 « Panne : les nouveaux arrivants n'existent pas » : la fédération ipa01 a le
# filtre des personnes et le filtre des groupes du code (plateforme/identite, main) ; aucune erreur LDAP
# de Keycloak depuis 10 min ; chaque personne de l'annuaire (cn=users, hors admin) créée depuis plus de
# 20 min existe dans Keycloak (lien de fédération), avec les mêmes groupes parmi les sept ; alerte
# FederationLdapEnEchec chargée ; RB-241 et RB-246 complétés ; journal ; panne close.
# Lecture seule : keycloak_api (wb-checks), ipa_ldap (wb-checks de l'annuaire), SELECT sur la base de
# Keycloak (idp01), Loki, GitLab.

# shellcheck source=_m24-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-expert.sh"

title "M24-E37 — Panne : les nouveaux arrivants n'existent pas"
require_cmd jq curl ldapsearch ssh

# --- 1. La fédération est celle du code ------------------------------------------------------------------
_m24x_e37_ldap="$(_m24x_ldap_federation)"
_m24x_e37_filtre_code="$(_m24x_tofu_valeur federation-ldap.tf custom_user_search_filter)"
_m24x_e37_groupes_code="$(_m24x_tofu_valeur federation-ldap.tf groups_ldap_filter)"
if [[ -z "$_m24x_e37_ldap" ]]; then
  _ko "Keycloak : fédération « ipa01 » introuvable (ou composants illisibles avec wb-checks)"
elif [[ -z "$_m24x_e37_filtre_code" || -z "$_m24x_e37_groupes_code" ]]; then
  _ko "plateforme/identite : tofu/federation-ldap.tf illisible sur main (filtres de référence introuvables)"
else
  check_cmd "Fédération ipa01 : filtre des personnes identique au code ($_m24x_e37_filtre_code)" \
    _m24d_json "$_m24x_e37_ldap" '(.config.customUserSearchFilter[0] // "") == $f' --arg f "$_m24x_e37_filtre_code"
  _m24x_e37_mappeur="$(_m24d_kc "components?parent=$(_m24d_uri "$(jq -r .id <<<"$_m24x_e37_ldap")")&type=org.keycloak.storage.ldap.mappers.LDAPStorageMapper" \
    | jq -c '[.[] | select(.providerId == "group-ldap-mapper")][0] // empty' 2>/dev/null || true)"
  check_cmd "Mappeur de groupes de la fédération : filtre identique au code (les sept groupes)" \
    _m24d_json "$_m24x_e37_mappeur" '(.config["groups.ldap.filter"][0] // "") == $f' --arg f "$_m24x_e37_groupes_code"
fi
check_output "Loki (audit) : aucune erreur LDAP dans le journal de Keycloak depuis 10 minutes" '^0$' \
  _m24p_loki_lignes '{service="keycloak"} |~ "(?i)ldap" | json | level=~"ERROR|WARN"' audit 10m

# --- 2. Annuaire et Keycloak d'accord, personne par personne ------------------------------------------------
# Personnes de l'annuaire : uid et createTimestamp des entrées de cn=users,cn=accounts (hors admin).
_m24x_e37_personnes="$(_m24d_ldap '(&(objectClass=inetOrgPerson)(!(uid=admin)))' uid createTimestamp \
  | awk -v base="cn=users,cn=accounts,$_M24D_BASE" '
      /^dn: / { garde = (index(tolower($0), tolower(base)) > 0); uid = ""; ts = "" }
      garde && tolower($1) == "uid:" { uid = $2 }
      garde && tolower($1) == "createtimestamp:" { ts = $2 }
      /^$/ { if (garde && uid != "") print uid, ts; garde = 0 }
      END { if (garde && uid != "") print uid, ts }')"
# Groupes des sept, depuis les entrées de groupes (attribut member) : « uid groupe » par ligne.
_m24x_e37_membres="$(_m24d_ldap '(&(objectClass=groupOfNames)(|(cn=plateforme-admins)(cn=plateforme)(cn=mediagenda)(cn=medidoc)(cn=securite)(cn=support)(cn=direction)))' cn member \
  | awk '/^dn: / { g = "" } tolower($1) == "cn:" { g = $2 } tolower($1) == "member:" && $2 ~ /^uid=/ { m = $2; sub(/^uid=/, "", m); sub(/,.*/, "", m); if (g != "") print m, g }')"
# Personnes fédérées de Keycloak (base, lecture seule) : « identifiant uid » par ligne.
_m24x_e37_kc="$(_m24p_sql "SELECT u.id || ' ' || u.username FROM user_entity u JOIN realm r ON r.id = u.realm_id WHERE r.name = 'medisphere' AND u.federation_link IS NOT NULL")"
_m24x_e37_seuil="$(date -u -d '-20 min' +%Y%m%d%H%M%SZ)"

# _m24x_e37_coherent — chaque personne ancienne de 20 min est dans Keycloak avec les mêmes groupes.
_m24x_e37_coherent() {
  local uid ts id attendus vus n=0 ko=0
  while read -r uid ts; do
    [[ -n "$uid" ]] || continue
    [[ -z "$ts" || "$ts" > "$_m24x_e37_seuil" ]] && continue
    n=$((n + 1))
    id="$(awk -v u="$uid" '$2 == u { print $1; exit }' <<<"$_m24x_e37_kc")"
    if [[ -z "$id" ]]; then
      echo "    absente de Keycloak : $uid" >&2
      ko=1
      continue
    fi
    attendus="$(awk -v u="$uid" '$1 == u { print $2 }' <<<"$_m24x_e37_membres" | sort -u | paste -sd, -)"
    vus="$(_m24d_kc "users/$id/groups?briefRepresentation=true" | jq -r '.[].name' 2>/dev/null \
      | grep -E "$_M24X_GROUPES_RE" | sort -u | paste -sd, - || true)"
    if [[ "$attendus" != "$vus" ]]; then
      echo "    groupes différents pour $uid : annuaire [$attendus], Keycloak [$vus]" >&2
      ko=1
    fi
  done <<<"$_m24x_e37_personnes"
  ((n >= 7 && ko == 0))
}
if [[ -z "$_m24x_e37_personnes" || -z "$_m24x_e37_kc" ]]; then
  _ko "Annuaire (wb-checks) ou base de Keycloak (idp01) illisible : comparaison des personnes impossible"
else
  _m24x_e37_rc=0
  _m24x_e37_detail="$(_m24x_e37_coherent 2>&1)" || _m24x_e37_rc=$?
  check_cmd "Toutes les personnes de l'annuaire (au moins sept, créées il y a plus de 20 min) sont dans Keycloak, avec les mêmes groupes" \
    test "$_m24x_e37_rc" -eq 0
  if [[ -n "$_m24x_e37_detail" ]]; then printf '%s\n' "$_m24x_e37_detail"; fi
fi

# --- 3. Prévention, documentation, clôture -------------------------------------------------------------
check_cmd "Ruler de Loki (audit) : FederationLdapEnEchec chargée" _m24d_contient "$(_m24p_ruler audit)" '^FederationLdapEnEchec$'
_m24x_e37_rb241="$(_m24p_arbre plateforme/medisphere "$_M24P_DOC/runbooks" | grep -E '/RB-241[^/]*\.md$' | head -n 1 || true)"
check_cmd "RB-241 : étape de vérification dans Keycloak (synchronisation, groupes évalués dans un jeton)" \
  _m24p_tous "$([[ -n "$_m24x_e37_rb241" ]] && _m24p_doc "$_m24x_e37_rb241")" 'Evaluate|[ée]valu' 'Sync|synchronis'
check_cmd "RB-246 sur main : section « une personne de l'annuaire n'existe pas dans Keycloak »" \
  _m24x_section "$(_m24x_rb246)" 'annuaire|n.existe pas|arriv'
check_cmd "Journal de diagnostic M24-E37 sur main (docs/socle/journal/)" _m24x_journal E37
check_cmd "Panne M24-E37 close (lab/bin/break 24 37 --annuler après réparation)" _m24x_panne_close E37
