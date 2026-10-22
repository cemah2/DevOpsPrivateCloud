# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E21.sh — M24-E21 : authentification forte, OTP obligatoire, WebAuthn en option.
# Vérifie, en lecture seule (API d'administration du royaume medisphere par wb-checks) :
#   - le flux de navigateur du royaume est navigateur-medisphere ;
#   - l'OTP y est REQUIRED dans un sous-flux CONDITIONAL gardé par la condition « user role » sur le
#     rôle second-facteur-obligatoire (non inversée) ;
#   - ce rôle est porté par les groupes plateforme-admins et securite, et par eux seuls (aucune personne) ;
#   - ton compte a un OTP ; l'enrôlement n'est pas imposé à tous par défaut ;
#   - aucun client n'a les Direct Access Grants (ils contourneraient le second facteur) ;
#   - tofu/flux.tf sur main de plateforme/identite.

# shellcheck source=_m24-operationnel-c.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-operationnel-c.sh"

title "M24-E21 — Authentification forte : OTP obligatoire, WebAuthn en option"
require_cmd jq curl

_m24c_e21_role=second-facteur-obligatoire

# --- 1. Le flux ---------------------------------------------------------------------------------------
check_cmd "Royaume medisphere : flux de navigateur navigateur-medisphere" _m24c_json "$(_m24c_kc "")" \
  '.browserFlow == "navigateur-medisphere"'

_m24c_e21_exec="$(_m24c_kc "authentication/flows/navigateur-medisphere/executions")"
# Identifiants des configurations de la condition « user role » qui visent le rôle sans l'inverser.
_m24c_e21_config_ok() {
  local id cfg
  for id in $(jq -r '.[] | select(.providerId == "conditional-user-role") | .authenticationConfig // empty' <<<"$_m24c_e21_exec" 2>/dev/null); do
    cfg="$(_m24c_kc "authentication/config/$id")"
    if _m24c_json "$cfg" '.config.condUserRole == $r and ((.config.negate // "false") == "false")' --arg r "$_m24c_e21_role"; then
      printf '%s\n' "$id"
    fi
  done
}
_m24c_e21_cfg_id="$(_m24c_e21_config_ok | head -n 1)"
check_cmd "Condition « user role » sur $_m24c_e21_role (non inversée) dans navigateur-medisphere" \
  test -n "$_m24c_e21_cfg_id"
# L'OTP doit suivre CETTE condition, au même niveau, dans un sous-flux CONDITIONAL.
check_cmd "OTP REQUIRED dans le sous-flux CONDITIONAL gardé par cette condition" _m24c_json "$_m24c_e21_exec" '
  . as $e
  | ([range(0; $e | length)] | map(select($e[.].authenticationConfig == $c)) | first) as $i
  | if $i == null then false else
      ([range(0; $i)] | map(select($e[.].level == $e[$i].level - 1)) | last) as $p
      | ($p != null and $e[$p].requirement == "CONDITIONAL" and $e[$p].authenticationFlow == true)
        and ([range($i + 1; $e | length)]
             | reduce .[] as $j ({fin: false, ok: false};
                 if .fin then .
                 elif $e[$j].level < $e[$i].level then .fin = true
                 elif $e[$j].level == $e[$i].level and $e[$j].providerId == "auth-otp-form"
                      and $e[$j].requirement == "REQUIRED" then .ok = true
                 else . end)
             | .ok)
    end' --arg c "$_m24c_e21_cfg_id"

# --- 2. Qui porte le rôle -------------------------------------------------------------------------------
check_cmd "Rôle $_m24c_e21_role porté exactement par les groupes plateforme-admins et securite" _m24c_json \
  "$(_m24c_kc "roles/$_m24c_e21_role/groups?briefRepresentation=true")" \
  '[.[].name] | sort == ["plateforme-admins", "securite"]'
check_cmd "Rôle $_m24c_e21_role attribué à AUCUNE personne directement (seulement par les groupes)" _m24c_json \
  "$(_m24c_kc "roles/$_m24c_e21_role/users?briefRepresentation=true")" 'length == 0'

# --- 3. Les personnes ---------------------------------------------------------------------------------
if [[ -z "$_M24C_MOI" ]]; then
  skip "OTP de ton compte" "WB_MOI non défini dans lab/lab.env"
else
  _m24c_e21_moi="$(_m24c_kc_utilisateur "$_M24C_MOI")"
  check_cmd "Ton compte ($_M24C_MOI) a un OTP enregistré dans le royaume medisphere" _m24c_json \
    "$(_m24c_kc "users/$_m24c_e21_moi/credentials")" '[.[].type] | index("otp") != null'
fi
check_cmd "L'enrôlement OTP est activé mais pas imposé à tous par défaut" _m24c_json \
  "$(_m24c_kc "authentication/required-actions")" \
  '[.[] | select(.alias == "CONFIGURE_TOTP")][0] | .enabled == true and .defaultAction == false'

# --- 4. Pas de contournement ------------------------------------------------------------------------------
# admin-cli (client intégré de chaque royaume) est traité au durcissement (M24-E27) : son flux « direct
# grant » par défaut exige déjà l'OTP de qui en a un.
check_cmd "Aucun client MédiSphère n'accepte les Direct Access Grants (mot de passe sans formulaire ni OTP)" \
  _m24c_json "$(_m24c_kc "clients?max=500")" \
  'length > 0 and ([.[] | select(.directAccessGrantsEnabled == true and .clientId != "admin-cli")] | length == 0)'

# --- 5. Le code ---------------------------------------------------------------------------------------
check_cmd "tofu/flux.tf sur main de plateforme/identite (flux lié au royaume)" \
  _m24c_sur_main plateforme/identite tofu/flux.tf 'keycloak_authentication_bindings'
