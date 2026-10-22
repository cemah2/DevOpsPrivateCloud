# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E14.sh — M24-E14 : Harbor en OIDC
# À lancer depuis adm01. Lecture seule : client « harbor » (wb-checks), informations système de Harbor
# et projets (robot de lecture des checks, harbor-checks.env), fichiers de registre/ sur main de
# plateforme/infra (GitLab).

# shellcheck source=_m24-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-operationnel.sh"

title "M24-E14 — Harbor en OIDC"
require_cmd jq curl

# _m24o_e14_auth_ok TEXTE — réglages d'authentification voulus.
_m24o_e14_auth_ok() {
  grep -Eq 'auth_mode +=  *"oidc_auth"' <<<"$1" && grep -Eq 'oidc_verify_cert +=  *true' <<<"$1" \
    && grep -Eq 'oidc_admin_group +=  *"plateforme-admins"' <<<"$1" && grep -Eq 'oidc_groups_claim +=  *"groups"' <<<"$1" \
    && ! grep -Eq 'oidc_verify_cert +=  *false' <<<"$1"
}

# _m24o_e14_secret_ok TEXTE — secret par oidc_client_secret_wo, aucun oidc_client_secret littéral.
_m24o_e14_secret_ok() {
  grep -Eq 'oidc_client_secret_wo +=  *var\.' <<<"$1" && ! grep -Eq '^[[:space:]]*oidc_client_secret[[:space:]]*=' <<<"$1"
}

# _m24o_e14_sans_utilisateurs PROJETS — registre/ est lisible (projets.tf non vide) et n'a plus
#   d'utilisateurs.tf : un GitLab injoignable ne doit pas faire passer ce contrôle.
_m24o_e14_sans_utilisateurs() {
  [[ -n "$1" ]] && [[ -z "$(_m24d_contenu_main "$_M24O_P_INFRA" registre/utilisateurs.tf)" ]] \
    && ! grep -Eq 'resource +"harbor_user"' <<<"$1"
}

# --- 1. Le client -----------------------------------------------------------------------------------------
_m24o_controler_client harbor confidentiel S256 "https://registry.par1.medisphere.internal/c/oidc/callback"
check_cmd "plateforme/identite : tofu/clients-harbor.tf sur main" \
  _m24o_fichier_main "$_M24O_P_IDENTITE" tofu/clients-harbor.tf 'client_id *= *"harbor"'

# --- 2. Harbor ------------------------------------------------------------------------------------------------
_m24o_e14_info="$(harbor_api systeminfo 2>/dev/null || true)"
if [[ -z "$_m24o_e14_info" ]]; then
  _ko "Harbor : /api/v2.0/systeminfo illisible avec le robot des checks (Harbor arrêté ? robot expiré ?)"
else
  check_cmd "Harbor : mode d'authentification OIDC (auth_mode = oidc_auth)" \
    _m24o_json "$_m24o_e14_info" '.auth_mode == "oidc_auth"'
fi
check_cmd "Harbor : le robot des checks lit toujours le projet medisphere (les robots ne dépendent pas du mode)" \
  _m24o_json "$(harbor_api 'projects?name=medisphere' 2>/dev/null || true)" '[.[]? | .name] | index("medisphere") != null'

# --- 3. Le code de registre/ ----------------------------------------------------------------------------------
_m24o_e14_auth="$(_m24d_contenu_main "$_M24O_P_INFRA" registre/authentification.tf)"
check_cmd "registre/authentification.tf : oidc_auth, certificat de Keycloak VÉRIFIÉ, groupe administrateur plateforme-admins" \
  _m24o_e14_auth_ok "$_m24o_e14_auth"
check_cmd "registre/authentification.tf : secret en argument en écriture seule, jamais littéral" \
  _m24o_e14_secret_ok "$_m24o_e14_auth"
_m24o_e14_projets="$(_m24d_contenu_main "$_M24O_P_INFRA" registre/projets.tf)"
check_cmd "registre/projets.tf : membres = groupes OIDC (harbor_project_member_group, type oidc)" \
  _m24d_contient "$_m24o_e14_projets" 'type += +"oidc"'
check_cmd "registre/ : plus aucun membre utilisateur (harbor_project_member_user)" \
  _m24o_aucune_ligne 'resource +"harbor_project_member_user"' "$_m24o_e14_projets"
check_cmd "registre/ : plus aucun utilisateur local (utilisateurs.tf retiré, aucun harbor_user)" \
  _m24o_e14_sans_utilisateurs "$_m24o_e14_projets"
