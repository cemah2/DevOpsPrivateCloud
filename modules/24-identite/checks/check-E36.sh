# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E36.sh — M24-E36 « Panne : kubectl refuse les jetons » : sur les trois nœuds de contrôle, le
# fichier d'authentification structurée est le même (hors commentaires), attend l'audience kubernetes,
# n'a que la règle azp sur les revendications, préfixe noms et groupes par « oidc: », garde les règles
# qui refusent « system: » ; l'émetteur est joignable depuis chaque nœud ; les liaisons RBAC visent
# toujours oidc:<groupe> ; alerte sur les refus de jetons chargée ; RB-246 ; journal ; panne close.
# Lecture seule (SSH admin : sudo -n cat du fichier, curl de la découverte ; kube : liaisons RBAC).

# shellcheck source=_m24-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-expert.sh"

title "M24-E36 — Panne : kubectl refuse les jetons"
require_cmd jq yq curl kubectl ssh

# _m24x_e36_conforme JSON — l'entrée de l'émetteur du royaume est conforme à M24-E16.
_m24x_e36_conforme() {
  _m24d_json "$1" '
    .kind == "AuthenticationConfiguration"
    and ([.jwt[] | select(.issuer.url == $e)] | length) == 1
    and ([.jwt[] | select(.issuer.url == $e)][0] as $j
      | ($j.issuer.audiences == ["kubernetes"])
      and (($j.claimValidationRules // []) | length) == 1
      and ($j.claimValidationRules[0].expression | test("azp") and test("kubernetes"))
      and $j.claimMappings.username.prefix == "oidc:"
      and $j.claimMappings.groups.prefix == "oidc:"
      and $j.claimMappings.groups.claim == "groups"
      and ([($j.userValidationRules // [])[].expression | select(test("system:"))] | length) >= 2)' \
    --arg e "$_M24D_EMETTEUR"
}

_m24x_e36_empreintes=()
for _m24x_e36_n in "${_M24X_CP[@]}"; do
  _m24x_e36_j="$(_m24x_authn_json "$_m24x_e36_n")"
  check_cmd "$_m24x_e36_n : audience kubernetes, seule règle azp, préfixes oidc:, refus de system: ($_M24X_AUTHN)" \
    _m24x_e36_conforme "$_m24x_e36_j"
  if [[ -n "$_m24x_e36_j" ]]; then
    _m24x_e36_empreintes+=("$(sha256sum <<<"$_m24x_e36_j" | cut -d' ' -f1)")
  else
    _m24x_e36_empreintes+=("illisible-$_m24x_e36_n")
  fi
  check_ssh "$_m24x_e36_n : l'émetteur est joignable en TLS vérifié (flux K8S_CP → VIP lb 443)" "$_m24x_e36_n" \
    "curl -sf --max-time 5 -o /dev/null $_M24D_EMETTEUR/.well-known/openid-configuration"
done
check_output "Les ${#_M24X_CP[@]} nœuds de contrôle ont le même fichier d'authentification, lisible (hors commentaires)" '^1$' \
  bash -c 'printf "%s\n" "$@" | sort -u | wc -l' _ "${_m24x_e36_empreintes[@]}"

# --- RBAC : aucune « réparation » qui suivrait un préfixe faux -----------------------------------------------
_m24x_e36_sujets="$(kube get clusterrolebindings,rolebindings -A -o json 2>/dev/null \
  | jq -r '.items[].subjects[]? | select(.kind == "Group") | .name' 2>/dev/null || true)"
check_cmd "RBAC : le groupe oidc:plateforme-admins est toujours lié (rbac/oidc.yaml)" \
  grep -qx 'oidc:plateforme-admins' <<<"$_m24x_e36_sujets"
check_cmd "RBAC : aucune liaison vers un groupe « oidc-… » (préfixe de la panne)" \
  _m24p_aucun '^oidc-' "$_m24x_e36_sujets"

# --- Prévention, documentation, clôture -------------------------------------------------------------------
check_cmd "Prometheus : une alerte chargée surveille l'authentification JWT ou le rechargement du fichier des serveurs d'API" \
  _m24x_prom_qui 'apiserver_authentication_(jwt_authenticator|config_controller)'
check_cmd "RB-246 sur main : section « kubectl refuse les jetons »" _m24x_section "$(_m24x_rb246)" 'kubectl'
check_cmd "Journal de diagnostic M24-E36 sur main (docs/socle/journal/)" _m24x_journal E36
check_cmd "Panne M24-E36 close (lab/bin/break 24 36 --annuler après réparation)" _m24x_panne_close E36
