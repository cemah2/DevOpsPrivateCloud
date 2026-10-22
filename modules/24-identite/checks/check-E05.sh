# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E05.sh — M24-E05 : Premiers pas dans Keycloak : royaumes, clients, utilisateurs
# À lancer depuis adm01. Lecture seule : API d'administration du royaume medisphere avec le compte
# de service wb-checks (~/.config/workbook/keycloak-checks.env), découverte OIDC publique.
# Rejouable après E06 (utilisateur d'essai supprimé) et après E08 (essai-oidc supprimé par le code).

# shellcheck source=_m24-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-decouverte.sh"

title "M24-E05 — Premiers pas dans Keycloak : royaumes, clients, utilisateurs"
require_cmd jq curl

# _m24d_e05_a_les_roles LISTE — la liste (séparée par des espaces) contient les trois rôles de lecture.
_m24d_e05_a_les_roles() {
  local r
  for r in view-realm view-users view-clients; do
    grep -qw -- "$r" <<<"$1" || return 1
  done
}

# _m24d_e05_sans_ecriture LISTE — aucun rôle qui permet d'écrire ou de prendre une identité.
_m24d_e05_sans_ecriture() {
  [[ -n "$1" ]] && ! grep -Eqw -- '(manage-[a-z-]+|impersonation|realm-admin|create-client)' <<<"$1"
}

# _m24d_e05_essai_seul LIGNES — au moins un utilisateur local, et aucun ne porte le nom d'un personnage.
_m24d_e05_essai_seul() {
  local u p n=0
  while IFS= read -r u; do
    [[ -n "$u" ]] || continue
    for p in "${_M24D_PERSONNAGES[@]}" "$_M24D_MOI"; do
      [[ -n "$p" && "$u" == "$p" ]] && return 1
    done
    n=$((n + 1))
  done <<<"$1"
  ((n >= 1))
}

# --- 1. Le compte de service des vérifications ------------------------------------------------------
check_output "keycloak-checks.env en 600 (secret local, jamais dans un dépôt)" '^600$' \
  stat -c %a "${WB_KEYCLOAK_CHECKS_FILE:-$HOME/.config/workbook/keycloak-checks.env}"
_m24d_e05_royaume="$(_m24d_kc "")"
if [[ -z "$_m24d_e05_royaume" ]]; then
  _ko "API d'administration du royaume medisphere illisible avec le client wb-checks (jeton refusé, royaume absent ou /admin filtré)"
  return 0
fi
_ok "Client wb-checks : jeton obtenu (client_credentials) et royaume medisphere lisible"
check_cmd "Royaume medisphere : actif, nom affiché « MédiSphère », inscription libre fermée" _m24d_json "$_m24d_e05_royaume" \
  '.enabled == true and .displayName == "MédiSphère" and .registrationAllowed == false'
check_cmd "Royaume medisphere : TLS exigé pour toutes les requêtes externes (sslRequired external ou all)" \
  _m24d_json "$_m24d_e05_royaume" '.sslRequired == "external" or .sslRequired == "all"'

_m24d_e05_wb="$(_m24d_kc_client wb-checks)"
check_cmd "wb-checks : client confidentiel à compte de service seul (ni navigateur, ni mot de passe, ni implicite)" \
  _m24d_json "$_m24d_e05_wb" \
  '.publicClient == false and .serviceAccountsEnabled == true and .standardFlowEnabled == false
   and .directAccessGrantsEnabled == false and .implicitFlowEnabled == false'
# Rôles effectifs du compte de service sur realm-management : exactement les trois rôles de lecture.
_m24d_e05_roles() {
  local id_wb id_sa id_rm
  id_wb="$(jq -r '.id // empty' <<<"$_m24d_e05_wb" 2>/dev/null || true)"
  [[ -n "$id_wb" ]] || return 0
  id_sa="$(_m24d_kc "clients/$id_wb/service-account-user" | jq -r '.id // empty' 2>/dev/null || true)"
  id_rm="$(_m24d_kc_client realm-management | jq -r '.id // empty' 2>/dev/null || true)"
  [[ -n "$id_sa" && -n "$id_rm" ]] || return 0
  _m24d_kc "users/$id_sa/role-mappings/clients/$id_rm/composite" | jq -r '.[].name' 2>/dev/null | sort | paste -sd' ' || true
}
_m24d_e05_r="$(_m24d_e05_roles)"
check_cmd "wb-checks : rôles view-realm, view-users, view-clients de realm-management" _m24d_e05_a_les_roles "$_m24d_e05_r"
check_cmd "wb-checks : aucun rôle d'écriture (manage-*, impersonation, realm-admin, create-client)" \
  _m24d_e05_sans_ecriture "$_m24d_e05_r"

# --- 2. Le client d'essai -------------------------------------------------------------------------------
_m24d_e05_essai="$(_m24d_kc_client essai-oidc)"
if [[ -z "$_m24d_e05_essai" ]] && _m24d_identite_tofu; then
  skip "Client essai-oidc" "supprimé par le code en E08 (tofu/royaume.tf présent sur main)"
else
  check_cmd "essai-oidc : client confidentiel, flux standard (code d'autorisation) seulement" _m24d_json "$_m24d_e05_essai" \
    '.publicClient == false and .standardFlowEnabled == true and .implicitFlowEnabled == false
     and .directAccessGrantsEnabled == false and (.serviceAccountsEnabled | not)'
  check_cmd "essai-oidc : une seule URI de redirection, exacte (http://localhost:8765/rappel), aucun joker" \
    _m24d_json "$_m24d_e05_essai" '.redirectUris == ["http://localhost:8765/rappel"]'
  check_cmd "essai-oidc : PKCE S256 exigé" _m24d_json "$_m24d_e05_essai" \
    '.attributes["pkce.code.challenge.method"] == "S256"'
fi

# --- 3. L'utilisateur local d'essai ----------------------------------------------------------------------
_m24d_e05_locaux="$(_m24d_kc "users?briefRepresentation=true&max=200" \
  | jq -r '.[] | select(.federationLink == null and (.username | startswith("service-account-") | not)) | .username' 2>/dev/null || true)"
if [[ -n "$(_m24d_kc "components?type=org.keycloak.storage.UserStorageProvider" | jq -r '.[0].id // empty' 2>/dev/null || true)" ]]; then
  skip "Utilisateur local d'essai" "fédération créée (E06) : il doit avoir été supprimé, contrôlé par le check d'E06"
else
  check_cmd "Un utilisateur local d'essai existe (aucun personnage : ils viendront de l'annuaire)" \
    _m24d_e05_essai_seul "$_m24d_e05_locaux"
fi

# --- 4. Ce que publie le royaume ----------------------------------------------------------------------------
check_cmd "Découverte OIDC : émetteur $_M24D_EMETTEUR (nom public, pas idp01)" _m24d_json \
  "$(_m24d_public /realms/medisphere/.well-known/openid-configuration)" \
  '.issuer == "https://sso.par1.medisphere.internal/realms/medisphere"
   and .jwks_uri == "https://sso.par1.medisphere.internal/realms/medisphere/protocol/openid-connect/certs"'
