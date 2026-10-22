# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes (variables jq, pas du shell)
#
# check-E07.sh — M24-E07 : OIDC à la main : code d'autorisation, PKCE, jetons et découverte
# À lancer depuis adm01. Lecture seule : découverte et JWKS publics, client essai-oidc (wb-checks),
# compte rendu dans plateforme/medisphere (GitLab). Le flux lui-même, avec ses jetons, n'est
# jamais rejoué ici : un check ne s'authentifie pas à ta place.

# shellcheck source=_m24-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-decouverte.sh"

title "M24-E07 — OIDC à la main : code d'autorisation, PKCE, jetons et découverte"
require_cmd jq curl

# _m24d_e07_toutes TEXTE REGEX… — le texte contient chacune des regex étendues.
_m24d_e07_toutes() {
  local texte="$1" r
  shift
  [[ -n "$texte" ]] || return 1
  for r in "$@"; do
    grep -Eq -- "$r" <<<"$texte" || return 1
  done
}

# _m24d_e07_sans_jeton TEXTE — aucun JWT complet (en-tête.charge.signature) recopié.
_m24d_e07_sans_jeton() {
  ! grep -Eq 'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{40,}\.[A-Za-z0-9_-]{20,}' <<<"$1"
}

# --- 1. Ce que publie le royaume --------------------------------------------------------------------
_m24d_e07_decouverte="$(_m24d_public /realms/medisphere/.well-known/openid-configuration)"
check_cmd "Découverte : points de terminaison sous l'émetteur public (autorisation, jeton, userinfo, introspection, déconnexion)" \
  _m24d_json "$_m24d_e07_decouverte" \
  '. as $d | ["authorization_endpoint","token_endpoint","userinfo_endpoint","introspection_endpoint","end_session_endpoint"]
   | all(. as $k | $d[$k] | type == "string" and startswith($d.issuer + "/protocol/openid-connect/"))'
check_cmd "Découverte : PKCE S256 annoncé" _m24d_json "$_m24d_e07_decouverte" \
  '.code_challenge_methods_supported | index("S256") != null'
check_cmd "JWKS : au moins une clé de signature RS256 publiée (kid, n, e)" _m24d_json \
  "$(_m24d_public /realms/medisphere/protocol/openid-connect/certs)" \
  '[.keys[] | select(.use == "sig" and .alg == "RS256" and .kty == "RSA" and (.kid | length > 0) and (.n | length > 0))] | length >= 1'
check_cmd "JWKS : aucune clé privée publiée (ni d, ni p, ni q)" _m24d_json \
  "$(_m24d_public /realms/medisphere/protocol/openid-connect/certs)" \
  '[.keys[] | select(has("d") or has("p") or has("q"))] | length == 0'

# --- 2. Le client d'essai après l'exercice ------------------------------------------------------------
_m24d_e07_essai="$(_m24d_kc_client essai-oidc)"
if [[ -z "$_m24d_e07_essai" ]] && _m24d_identite_tofu; then
  skip "Client essai-oidc (audience, PKCE)" "supprimé par le code en E08"
else
  check_cmd "essai-oidc : mappeur d'audience qui ajoute essai-oidc à « aud » du jeton d'accès (introspection)" \
    _m24d_json "$_m24d_e07_essai" \
    '[.protocolMappers[]? | select(.protocolMapper == "oidc-audience-mapper"
       and .config["included.client.audience"] == "essai-oidc" and .config["access.token.claim"] == "true")] | length == 1'
  check_cmd "essai-oidc : PKCE S256 toujours exigé et Direct Access Grants toujours désactivés" _m24d_json "$_m24d_e07_essai" \
    '.attributes["pkce.code.challenge.method"] == "S256" and .directAccessGrantsEnabled == false'
fi

# --- 3. Le compte rendu --------------------------------------------------------------------------------
_m24d_e07_cr="$(_m24d_contenu_main plateforme/medisphere docs/securite/identite/oidc-a-la-main.md)"
if [[ -z "$_m24d_e07_cr" ]]; then
  _ko "plateforme/medisphere : docs/securite/identite/oidc-a-la-main.md absent de main"
else
  _ok "plateforme/medisphere : docs/securite/identite/oidc-a-la-main.md présent sur main"
  check_cmd "Compte rendu : défi PKCE (code_verifier, code_challenge, S256)" \
    _m24d_e07_toutes "$_m24d_e07_cr" 'code_verifier' 'code_challenge' 'S256'
  check_cmd "Compte rendu : revendications lues dans les jetons (iss, aud, azp, exp, nonce)" \
    _m24d_e07_toutes "$_m24d_e07_cr" '\biss\b' '\baud\b' '\bazp\b' '\bexp\b' '\bnonce\b'
  check_cmd "Compte rendu : introspection, rafraîchissement et déconnexion essayés" \
    _m24d_e07_toutes "$_m24d_e07_cr" '[Ii]ntrospect' '[Rr]afra[îi]ch|refresh_token' '[Dd]éconnexion|logout'
  check_cmd "Compte rendu : ce qui se passe sans PKCE, ou avec un mauvais verifier" \
    _m24d_contient "$_m24d_e07_cr" '(code_challenge_method|PKCE verification failed|Missing parameter)'
  check_cmd "Compte rendu : aucun jeton complet recopié (pas de JWT eyJ…eyJ… de plus de 100 caractères)" \
    _m24d_e07_sans_jeton "$_m24d_e07_cr"
fi
