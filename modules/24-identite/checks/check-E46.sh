# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
# shellcheck source-path=SCRIPTDIR
#
# check-E46.sh — M24-E46 « Mini-projet : l'identité de MédiSphère v1 »
# Contrôle global de la livraison identite-v1 (depuis adm01). Lecture seule : Keycloak (wb-checks),
# annuaire (wb-checks), Grafana (Viewer), Harbor (robot de lecture), kubectl (wb-checks), SSH en
# consultation, pvesh/pveum en lecture sur pve01, GitLab en lecture. Rejoue les contrôles clés des
# paliers précédents (E06, E11, E13, E16, E19, E20, E21, E28, E30), puis vérifie l'état de livraison.
# Compte 3 à 6 minutes.

# shellcheck source=_m24-expert-b.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-expert-b.sh"

title "M24-E46 — Mini-projet : l'identité de MédiSphère v1 (contrôle global)"
require_cmd jq curl ldapsearch kubectl

# --- 1. Contrôles clés des paliers 1 à 3 ---------------------------------------------------------------
_m24y_e46_dir="$(dirname "${BASH_SOURCE[0]}")"
for _m24y_e46_x in E06 E11 E13 E16 E19 E20 E21 E28 E30; do
  if [[ -f "$_m24y_e46_dir/check-$_m24y_e46_x.sh" ]]; then
    # shellcheck disable=SC1090  # contrôles des autres paliers, chargés dynamiquement
    source "$_m24y_e46_dir/check-$_m24y_e46_x.sh"
  else
    skip "contrôle M24-$_m24y_e46_x" "script check-$_m24y_e46_x.sh absent"
  fi
done

# --- 2. Tous les services en SSO ----------------------------------------------------------------------------
title "M24-E46 — 2/6 Tous les services en SSO, clients propres"
_m24y_e46_clients="$(_m24p_clients_metier)"
if [[ -z "$_m24y_e46_clients" || "$_m24y_e46_clients" == "[]" ]]; then
  _ko "clients du royaume medisphere illisibles par wb-checks (lab/bin/check 24 05)"
else
  for _m24y_e46_c in gitlab grafana argocd argocd-cli harbor proxmox pbs netbox kubernetes oauth2-proxy step-ca wb-checks revue-acces; do
    check_cmd "client $_m24y_e46_c présent et actif" \
      _m24c_json "$_m24y_e46_clients" 'any(.[]; .clientId == $c and .enabled == true)' --arg c "$_m24y_e46_c"
  done
  check_cmd "aucun client métier avec une URI de retour à joker" \
    _m24c_json "$_m24y_e46_clients" '[.[] | .redirectUris[]? | select(test("\\*"))] | length == 0'
  check_cmd "aucun client métier avec le flux implicite ou les Direct Access Grants" \
    _m24c_json "$_m24y_e46_clients" '[.[] | select(.implicitFlowEnabled == true or .directAccessGrantsEnabled == true)] | length == 0'
  check_cmd "aucun client d'essai restant (essai-oidc, essai-capot, clients « test »/« essai »)" \
    _m24c_json "$_m24y_e46_clients" '[.[] | select(.clientId | test("essai|test"; "i"))] | length == 0'
fi
_m24y_e46_flux() { _m24p_royaume | jq -r '.browserFlow // empty' 2>/dev/null || true; }
check_output "flux de navigateur du royaume : navigateur-medisphere (OTP conditionnel)" '^navigateur-medisphere$' _m24y_e46_flux

# --- 3. Comptes locaux réduits au bris de glace ---------------------------------------------------------------
title "M24-E46 — 3/6 Comptes locaux réduits au bris de glace"
_m24y_e46_grafana() { grafana_api frontend/settings 2>/dev/null | jq -r '.disableLoginForm // false' 2>/dev/null || true; }
_m24y_e46_harbor() { harbor_api systeminfo 2>/dev/null | jq -r '.auth_mode // empty' 2>/dev/null || true; }
check_output "Grafana : formulaire de connexion local désactivé (SSO seulement)" '^true$' _m24y_e46_grafana
check_output "Harbor : mode d'authentification OIDC" '^oidc_auth$' _m24y_e46_harbor
_m24y_e46_argocm="$(_m24c_k -n argocd get configmap argocd-cm -o json)"
check_cmd "Argo CD : admin désactivé, seul compte local ci-lecture (jeton)" _m24c_json "$_m24y_e46_argocm" \
  '(.data["admin.enabled"] // "true") == "false"
   and ([.data | keys[] | select(startswith("accounts.") and (endswith(".enabled") | not))] - ["accounts.ci-lecture"] | length == 0)'
_m24y_e46_pve() {
  remote "${WB_PVE_HOST:-pve01}" 'pveum user list --output-format json' 2>/dev/null \
    | jq -e '[.[] | select(.userid == "wb-admin@pve")] | all(.enable == 0)' >/dev/null 2>&1
}
_m24y_e46_liaisons() {
  local j
  j="$(_m24c_k get clusterrolebindings,rolebindings -A -o json)"
  _m24c_json "$j" '[.items[] | .subjects[]? | select(.kind == "Group" and (.name | startswith("medisphere:")))] | length == 0'
}
check_cmd "Proxmox VE : wb-admin@pve désactivé (root@pam = bris de glace)" _m24y_e46_pve
check_cmd "Kubernetes : plus aucune liaison RBAC vers des groupes de certificats medisphere:*" _m24y_e46_liaisons

# --- 4. Rien de provisoire, départ démontré ------------------------------------------------------------------
title "M24-E46 — 4/6 Rien de provisoire, départ démontré"
check_cmd "aucune panne M24 encore marquée active" _m24y_aucune_panne
for _m24y_e46_vm in 2241 2242; do
  check_cmd "VM temporaire $_m24y_e46_vm (idp02 / idp-resto) détruite" _m24p_vm_absente "$_m24y_e46_vm"
done
_m24y_e46_depart="${WB_M24_DEPART:-thomas.leroy}"
_m24y_e46_p="$(_m24c_ldap "(&(objectClass=person)(uid=$_m24y_e46_depart))" nsAccountLock memberOf)"
check_cmd "démonstration de départ : $_m24y_e46_depart existe dans l'annuaire, désactivé (pas supprimé)" \
  bash -c 'grep -qi "^nsAccountLock: TRUE" <<<"$1"' _ "$_m24y_e46_p"
check_cmd "démonstration de départ : $_m24y_e46_depart n'est plus membre d'aucun groupe de la plateforme" \
  bash -c '[[ -n "$1" ]] && ! grep -Eq "^memberOf: cn=(plateforme-admins|plateforme|mediagenda|medidoc|securite|support|direction),cn=groups" <<<"$1"' \
  _ "$_m24y_e46_p"
_m24y_e46_kcid="$(_m24c_kc_utilisateur "$_m24y_e46_depart")"
_m24y_e46_sessions() { [[ "$(keycloak_api "users/$1/sessions" 2>/dev/null | jq -r 'length' 2>/dev/null)" == 0 ]]; }
if [[ -n "$_m24y_e46_kcid" ]]; then
  check_cmd "démonstration de départ : aucune session Keycloak ouverte pour $_m24y_e46_depart" _m24y_e46_sessions "$_m24y_e46_kcid"
fi

# --- 5. Documentation -------------------------------------------------------------------------------------------
title "M24-E46 — 5/6 Documentation"
_m24y_e46_docs="$(_m24p_arbre plateforme/medisphere "$_M24P_DOC")"
for _m24y_e46_d in 'modele-autorisation\.md$' 'ceremonie-ca\.md$' 'adr/ADR-0240[^/]*\.md$' 'adr/ADR-0241[^/]*\.md$' \
  'runbooks/RB-240[^/]*\.md$' 'runbooks/RB-241[^/]*\.md$' 'runbooks/RB-242[^/]*\.md$' 'runbooks/RB-243[^/]*\.md$' \
  'runbooks/RB-244[^/]*\.md$' 'runbooks/RB-245[^/]*\.md$' 'runbooks/RB-246[^/]*\.md$' 'revue-acces/.+\.md$'; do
  check_cmd "documentation sur main : $_M24P_DOC/ ~ $_m24y_e46_d" _m24d_contient "$_m24y_e46_docs" "/$_m24y_e46_d"
done
_m24y_e46_fiche="$(_m24p_doc "$_M24P_DOC/identite-v1.md")"
check_cmd "fiche de livraison identite-v1.md : limites, ce que consomment M25 et M26, démonstration de départ" _m24p_tous "$_m24y_e46_fiche" \
  '^#+ .*(limites|non couvert)' 'M25' 'M26' 'openbao' 'd[ée]part'
check_cmd "fiche de livraison : inventaire des comptes locaux restants (bris de glace)" _m24p_tous "$_m24y_e46_fiche" \
  'kc-secours' 'root@pam' 'admin\.conf'
check_cmd "fiche de livraison : aucun jeton ni clé recopiés" _m24y_sans_jeton "$_m24y_e46_fiche"

# --- 6. Livraison ---------------------------------------------------------------------------------------------------
title "M24-E46 — 6/6 Livraison"
_m24y_e46_pipeline() { [[ "$(_m24d_pipeline_main plateforme/identite)" == success ]]; }
_m24y_e46_etiquette() { gitlab_api "projects/plateforme%2Fmedisphere/repository/tags/identite-v1" >/dev/null 2>&1; }
check_cmd "plateforme/identite : pipeline de main vert" _m24y_e46_pipeline
check_cmd "étiquette identite-v1 posée sur plateforme/medisphere" _m24y_e46_etiquette
