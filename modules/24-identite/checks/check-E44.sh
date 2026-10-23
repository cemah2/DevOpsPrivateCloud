# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E44.sh — M24-E44 « Sous le capot : signatures, JWKS, sessions et rotation des clés »
# Vérifie, en lecture seule depuis adm01 :
#   - le compte rendu sur main de plateforme/medisphere (sections, notions relevées, aucun jeton) ;
#   - l'outil outils/verifier-jeton.sh sur main de plateforme/identite ;
#   - le ménage : client d'essai essai-capot supprimé (Keycloak et code), récepteur de déconnexion
#     arrêté sur idp01 (port 18081), dossier de travail ~/m24/e44 sans jeton résiduel.

# shellcheck source=_m24-expert-b.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-expert-b.sh"

title "M24-E44 — Sous le capot : signatures, JWKS, sessions et rotation des clés"
require_cmd jq curl

_m24y_e44_cr="$(_m24p_doc "$_M24P_DOC/analyses/oidc-sous-le-capot.md")"
check_cmd "compte rendu sur main ($_M24P_DOC/analyses/oidc-sous-le-capot.md)" test -n "$_m24y_e44_cr"
check_cmd "compte rendu : sections signature, JWKS, sessions, déconnexion, rotation, réponses" _m24p_tous "$_m24y_e44_cr" \
  '^#+ .*signature' '^#+ .*jwks' '^#+ .*sessions?' '^#+ .*d[ée]connexion' '^#+ .*rotation' '^#+ .*r[ée]ponses'
check_cmd "compte rendu : RS256, kid, x5c, et la vérification par openssl" _m24p_tous "$_m24y_e44_cr" \
  'RS256' '\bkid\b' 'x5c' 'openssl (dgst|pkeyutl)'
check_cmd "compte rendu : cookies de Keycloak relevés (AUTH_SESSION_ID, KEYCLOAK_IDENTITY, KEYCLOAK_SESSION)" _m24p_tous "$_m24y_e44_cr" \
  'AUTH_SESSION_ID' 'KEYCLOAK_IDENTITY' 'KEYCLOAK_SESSION'
check_cmd "compte rendu : jeton de déconnexion par canal arrière (logout_token, événement backchannel-logout, sid)" \
  _m24p_tous "$_m24y_e44_cr" 'logout_token' 'backchannel-logout' '\bsid\b'
check_cmd "compte rendu : cache des clés côté services (kube-apiserver : métrique jwks_fetch)" _m24p_tous "$_m24y_e44_cr" \
  'jwks_fetch'
check_cmd "compte rendu : aucun jeton complet ni clé privée" _m24y_sans_jeton "$_m24y_e44_cr"

check_output "plateforme/identite : outils/verifier-jeton.sh sur main (vérification RS256 par openssl, clé par kid)" \
  'openssl' _m24d_contenu_main plateforme/identite outils/verifier-jeton.sh

# --- Ménage ------------------------------------------------------------------------------------------------
_m24y_e44_lisible="$(_m24c_kc_client grafana)"
if [[ -z "$_m24y_e44_lisible" ]]; then
  skip "client d'essai essai-capot supprimé" "clients du royaume illisibles par wb-checks"
else
  check_cmd "Keycloak : client d'essai essai-capot supprimé" test -z "$(_m24c_kc_client essai-capot)"
fi
_m24y_e44_sans_essai_tofu() {
  _m24d_identite_tofu && [[ -z "$(_m24d_contenu_main plateforme/identite tofu/clients-essai-capot.tf)" ]]
}
check_cmd "plateforme/identite : code lisible et plus aucun fichier tofu/clients-essai-capot.tf sur main" _m24y_e44_sans_essai_tofu
check_cmd "idp01 : plus de récepteur de déconnexion à l'écoute (port 18081)" _m24y_ssh_ok "$_M24D_IDP" \
  '! ss -Hltn "sport = :18081" | grep -q . && echo oui'
check_cmd "adm01 : aucun fichier de jetons laissé dans ~/m24/e44" \
  bash -c '! grep -rlqE "eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{16,}" "$HOME/m24/e44" 2>/dev/null'
