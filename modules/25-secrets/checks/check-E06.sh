# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # variables jq ($ui, $p…) entre apostrophes : voulu
#
# check-E06.sh — M25-E06 : Les personnes entrent par le SSO : méthode OIDC
# À lancer depuis adm01. Lecture seule : client « openbao » du royaume medisphere (keycloak_api,
# client wb-checks du M24), code de plateforme/identite (GitLab), configuration de la méthode oidc,
# de son rôle et des groupes externes d'OpenBao, alias d'entité (qui s'est déjà connecté par OIDC),
# métadonnées du secret rangé dans kv. La configuration oidc lue ne contient pas le secret du client.

# shellcheck source=_m25-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-decouverte.sh"

title "M25-E06 — Les personnes entrent par le SSO : méthode OIDC"
require_cmd jq curl

_m25d_e06_rappel_ui="https://openbao.par1.medisphere.internal:8200/ui/vault/auth/oidc/oidc/callback"
_m25d_e06_rappel_cli="http://localhost:8250/oidc/callback"

# --- 1. Le client Keycloak, en code -----------------------------------------------------------------
check_cmd "plateforme/identite : tofu/clients-openbao.tf sur main (client créé par le code)" _m25d_contient \
  "$(_m25d_contenu_main plateforme/identite tofu/clients-openbao.tf)" 'client_id += +"openbao"'
_m25d_e06_client="$(_m25d_kc_client openbao)"
if [[ -z "$_m25d_e06_client" ]]; then
  _ko "Keycloak : client openbao introuvable dans le royaume medisphere (ou keycloak-checks.env illisible)"
else
  check_cmd "Client openbao : confidentiel, flux standard seul (ni implicite, ni Direct Access Grants)" \
    _m25d_json "$_m25d_e06_client" \
    '.publicClient == false and .standardFlowEnabled == true and .implicitFlowEnabled == false and .directAccessGrantsEnabled == false'
  check_cmd "Client openbao : exactement les deux redirections attendues, sans joker" _m25d_json "$_m25d_e06_client" \
    '(.redirectUris | sort) == ([$ui, $cli] | sort)' --arg ui "$_m25d_e06_rappel_ui" --arg cli "$_m25d_e06_rappel_cli"
  check_cmd "Client openbao : PKCE S256 exigé" _m25d_json "$_m25d_e06_client" \
    '.attributes["pkce.code.challenge.method"] == "S256"'
fi

# --- 2. La méthode oidc d'OpenBao --------------------------------------------------------------------------
_m25d_annoncer_acces
check_cmd "OpenBao : méthode de type oidc montée en oidc/" _m25d_json "$(_m25d_api sys/auth)" \
  '(.data // .)["oidc/"].type == "oidc"'
check_cmd "OpenBao : aucune méthode userpass (les personnes n'ont pas de mot de passe local)" _m25d_json \
  "$(_m25d_api sys/auth)" '[(.data // .) | to_entries[] | select(.value.type == "userpass")] | length == 0'
check_cmd "auth/oidc/config : découverte sur l'émetteur du royaume medisphere, client openbao, rôle par défaut personne" \
  _m25d_json "$(_m25d_api auth/oidc/config)" \
  '.data.oidc_discovery_url == $e and .data.oidc_client_id == "openbao" and .data.default_role == "personne"' \
  --arg e "$_M25D_EMETTEUR"
_m25d_e06_role="$(_m25d_api auth/oidc/role/personne)"
if [[ -z "$_m25d_e06_role" ]]; then
  _ko "Rôle OIDC personne introuvable (auth/oidc/role/personne)"
else
  check_cmd "Rôle personne : identifiant preferred_username, groupes par la revendication groups" _m25d_json \
    "$_m25d_e06_role" '.data.user_claim == "preferred_username" and .data.groups_claim == "groups"'
  check_cmd "Rôle personne : audience openbao exigée (bound_audiences)" _m25d_json "$_m25d_e06_role" \
    '.data.bound_audiences == ["openbao"]'
  check_cmd "Rôle personne : mêmes redirections que le client Keycloak" _m25d_json "$_m25d_e06_role" \
    '(.data.allowed_redirect_uris | sort) == ([$ui, $cli] | sort)' --arg ui "$_m25d_e06_rappel_ui" --arg cli "$_m25d_e06_rappel_cli"
  check_cmd "Rôle personne : politique default seulement (les droits viennent des groupes), 8 h au plus" \
    _m25d_json "$_m25d_e06_role" '.data.token_policies == ["default"] and .data.token_max_ttl > 0 and .data.token_max_ttl <= 28800'
fi

# --- 3. Groupes externes -----------------------------------------------------------------------------------
_m25d_e06_acc="$(_m25d_api sys/auth | jq -r '(.data // .)["oidc/"].accessor // empty' 2>/dev/null || true)"
for _m25d_e06_g in "${!_M25D_GROUPES[@]}"; do
  check_cmd "Groupe externe $_m25d_e06_g → politique ${_M25D_GROUPES[$_m25d_e06_g]}, alias sur la méthode oidc" \
    _m25d_json "$(_m25d_api "identity/group/name/$_m25d_e06_g")" \
    '.data.type == "external" and (.data.policies | index($p)) != null
     and .data.alias.name == $g and .data.alias.mount_accessor == $a' \
    --arg p "${_M25D_GROUPES[$_m25d_e06_g]}" --arg g "$_m25d_e06_g" --arg a "${_m25d_e06_acc:-?}"
done

# --- 4. Le secret du client et la première connexion ---------------------------------------------------------
check_cmd "kv/plateforme/openbao/oidc existe (secret du client rangé dans le coffre)" _m25d_json \
  "$(_m25d_api kv/metadata/plateforme/openbao/oidc)" '.data.current_version >= 1'
if [[ -n "$_M25D_MOI" ]]; then
  check_cmd "Tu t'es connecté au moins une fois par OIDC ($_M25D_MOI, alias d'entité de la méthode oidc)" _m25d_json \
    "$(_m25d_requete LIST identity/entity-alias/id)" \
    '[.data.key_info[]? | select(.mount_type == "oidc" and .name == $moi)] | length >= 1' --arg moi "$_M25D_MOI"
else
  skip "Première connexion OIDC de ton compte" "WB_MOI non renseigné dans lab/lab.env"
fi
