# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S08.sh — F7-S08 « Fédérer l'identité du client » : royaume ghsv-idp publié et décrit dans un
# état séparé, fournisseur et mappeurs dans medisphere, groupe des agents hors annuaire, refus des
# utilisateurs fédérés par le flux du royaume, mandataire des agents, route publique fermée aux
# anonymes, documentation. Lecture seule.

# shellcheck source=_f7-livraison.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f7-livraison.sh"

title "F7-S08 — Fédérer l'identité du client"
require_cmd curl jq

_f7_s08_sso="${WB_KEYCLOAK_URL:-https://sso.par1.medisphere.internal}"

# --- L'IdP simulé du client --------------------------------------------------------------------------
_f7_s08_decouverte() {
  curl -sf --max-time "$((WB_TIMEOUT * 2))" "$_f7_s08_sso/realms/ghsv-idp/.well-known/openid-configuration" 2>/dev/null |
    jq -e --arg e "$_f7_s08_sso/realms/ghsv-idp" '.issuer == $e' >/dev/null 2>&1
}
check_cmd "royaume ghsv-idp publié (découverte OIDC, émetteur $_f7_s08_sso/realms/ghsv-idp)" _f7_s08_decouverte

# Le royaume ghsv-idp est décrit en code dans un dossier OpenTofu dont l'état n'est pas celui de medisphere.
_f7_s08_etat_separe() {
  local f dossier c cle_ghsv="" cle_med=""
  while IFS= read -r f; do
    [[ "$f" == *.tf ]] || continue
    c="$(_f7c_fichier "$_f7l_identite" "$f" 2>/dev/null)" || continue
    if grep -Eq 'realm[[:space:]]*=[[:space:]]*"ghsv-idp"' <<<"$c" && grep -q 'resource "keycloak_realm"' <<<"$c"; then
      dossier="${f%/*}"
      cle_ghsv="$(_f7_s08_cle_etat "$dossier")"
    elif grep -Eq 'realm[[:space:]]*=[[:space:]]*"medisphere"' <<<"$c" && grep -q 'resource "keycloak_realm"' <<<"$c"; then
      cle_med="$(_f7_s08_cle_etat "${f%/*}")"
    fi
  done < <(_f7c_arbre "$_f7l_identite")
  [[ -n "$cle_ghsv" && -n "$cle_med" && "$cle_ghsv" != "$cle_med" ]]
}
# _f7_s08_cle_etat DOSSIER — clé « key » du backend s3 déclaré dans un .tf du dossier.
_f7_s08_cle_etat() {
  local f
  while IFS= read -r f; do
    [[ "$f" == "$1"/*.tf && "${f#"$1"/}" != */* ]] || continue
    _f7c_fichier "$_f7l_identite" "$f" 2>/dev/null | sed -n 's/^[[:space:]]*key[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1
  done < <(_f7c_arbre "$_f7l_identite" "$1") | grep . | head -n 1
}
check_cmd "$_f7l_identite (main) : royaume ghsv-idp en code, état OpenTofu distinct de celui de medisphere" _f7_s08_etat_separe

# --- Le courtier dans medisphere ---------------------------------------------------------------------
_f7_s08_idp_json="$(_f7l_idp)" || _f7_s08_idp_json=""
if [[ -n "$_f7_s08_idp_json" ]]; then
  _f7_s08_idp_ok() {
    jq -e '.enabled == true
      and ((.hideOnLogin // false) == true or (.config.hideOnLoginPage // "false") == "true")
      and (.config.validateSignature // "false") == "true"
      and (.storeToken // false) == false' >/dev/null 2>&1 <<<"$_f7_s08_idp_json"
  }
  check_cmd "fournisseur $_f7l_idp : actif, caché sur la page de connexion, signatures vérifiées, jetons non conservés" _f7_s08_idp_ok
  # « Caché » n'interdit pas l'adresse directe du courtier (/broker/<alias>/login) avec la session d'un
  # client interne ; le retour du courtier ne rejoue pas le flux du navigateur : seul un flux « après
  # courtier » peut refuser à ce moment-là.
  _f7_s08_apres_courtier() {
    local f
    f="$(jq -r '.postBrokerLoginFlowAlias // .config.postBrokerLoginFlowAlias // empty' <<<"$_f7_s08_idp_json" 2>/dev/null)"
    [[ -n "$f" ]] && keycloak_api "authentication/flows/$(_f7c_enc "$f")/executions" 2>/dev/null |
      jq -e 'any(.[]; (.providerId // "") == "deny-access-authenticator")' >/dev/null 2>&1
  }
  check_cmd "fournisseur $_f7l_idp : un flux après courtier refuse (accès direct au courtier depuis un client interne)" _f7_s08_apres_courtier
  _f7_s08_mappeur_groupe() {
    _f7l_idp_mappeurs | jq -e --arg g "$_f7l_groupe_agents" 'any(.[]; (.config.group // "") | test("(^|/)" + $g + "$"))' >/dev/null 2>&1
  }
  check_cmd "un mappeur du fournisseur place les agents dans le groupe $_f7l_groupe_agents" _f7_s08_mappeur_groupe
else
  _ko "fournisseur $_f7l_idp illisible dans le royaume medisphere (absent, ou wb-checks sans le rôle view-identity-providers)"
fi

# Les membres du groupe des agents sont des comptes fédérés par le courtier, jamais des comptes de l'annuaire.
_f7_s08_membres() {
  local g id m
  g="$(_f7l_groupe_kc "$_f7l_groupe_agents")"
  id="$(jq -r '.id // empty' <<<"$g" 2>/dev/null)"
  [[ -n "$id" ]] || return 1
  m="$(keycloak_api "groups/$id/members?max=500" 2>/dev/null)" || return 1
  jq -e 'all(.[]; (.federationLink // null) == null)' >/dev/null 2>&1 <<<"$m"
}
check_cmd "groupe $_f7l_groupe_agents : présent, aucun membre venu de l'annuaire (fédération LDAP)" _f7_s08_membres

# Un flux de premier niveau de medisphere (le flux du navigateur, en pratique) refuse sur condition de
# rôle : « Condition - user role » + « Deny access » (refus des utilisateurs fédérés d'un client).
_f7_s08_refus() {
  local flux
  while IFS= read -r flux; do
    [[ -n "$flux" ]] || continue
    keycloak_api "authentication/flows/$(_f7c_enc "$flux")/executions" 2>/dev/null |
      jq -e 'any(.[]; (.providerId // "") == "deny-access-authenticator")
        and any(.[]; (.providerId // "") == "conditional-user-role")' >/dev/null 2>&1 && return 0
  done < <(keycloak_api "authentication/flows" 2>/dev/null | jq -r '.[] | select(.topLevel == true and (.builtIn // false) == false) | .alias' 2>/dev/null)
  return 1
}
check_cmd "medisphere : un flux d'authentification refuse sur condition de rôle (utilisateurs venus d'un client)" _f7_s08_refus

# --- Publication -------------------------------------------------------------------------------------
_f7_s08_redirection() {
  local h
  h="$(curl -s -o /dev/null -D - --max-time "$((WB_TIMEOUT * 2))" "$_f7l_url_agents/" 2>/dev/null)" || return 1
  grep -Eq '^HTTP/[0-9.]+ 30[27]' <<<"$h" && grep -Eqi '^location:.*/realms/' <<<"$h"
}
check_cmd "$_f7l_url_agents/ sans session : redirection vers l'authentification" _f7_s08_redirection
check_cmd "route publique : liste des rendez-vous refusée sans authentification (401, 403 ou 404)" \
  _f7l_code_dans "$_f7l_url_prod/api/v1/rendez-vous" '^(401|403|404)$'
check_cmd "route publique : annulation refusée sans authentification (401, 403, 404 ou 405)" \
  _f7l_code_dans "$_f7l_url_prod/api/v1/rendez-vous/1" '^(401|403|404|405)$' -X DELETE

# --- Documentation ----------------------------------------------------------------------------------
check_cmd "identite-federee.md : échanges, ce que nous recevons et refusons, constat de cloisonnement" \
  _f7l_doc . '^identite-federee\.md$' 'groups?' 'refus' 'gitlab' 'grafana' 'argo'
check_cmd "RB-372 (identité fédérée : raccordement, diagnostic, rotation, départ)" \
  _f7l_doc runbooks '^RB-372' 'rotation' 'secret' 'd(é|e)part'
