#!/usr/bin/env bash
# outils/verifier-jeton.sh — vérifie un JWT du royaume medisphere SANS bibliothèque (M24-E44, PLAT-2544).
#
# Usage : outils/verifier-jeton.sh [--emetteur URL] [--audience AUD] [--racine FICHIER] < jeton
#   Le jeton est lu sur l'ENTRÉE STANDARD (jamais en argument : visible par ps et dans l'historique).
#   --emetteur  émetteur ATTENDU (défaut : https://sso.par1.medisphere.internal/realms/medisphere) ; le
#               JWKS est pris dans SA découverte, jamais à une adresse tirée du jeton (jku, x5u, iss).
#   --audience  si donnée, « aud » (chaîne ou liste) doit la contenir.
#   --racine    racine de confiance pour joindre l'émetteur (défaut : racine MédiSphère du rôle ca_lab).
#
# Contrôles, dans l'ordre : forme (trois parties base64url) ; algorithme IMPOSÉ : RS256 (« alg » de
# l'en-tête comparé, jamais utilisé pour choisir) ; clé choisie par « kid » dans le JWKS de l'émetteur
# attendu (clé RSA de signature) ; signature PKCS#1 v1.5 / SHA-256 vérifiée par openssl sur l'entrée
# signée « en-tête.charge » telle quelle ; puis iss, exp, nbf (tolérance 30 s) et aud.
# Sortie : en-tête et revendications utiles, JAMAIS le jeton ni la signature. Code 0 si tout est valide.
# Dépendances : bash, curl, jq, openssl, base64, fold.
set -euo pipefail

EMETTEUR="https://sso.par1.medisphere.internal/realms/medisphere"
AUDIENCE=""
RACINE="/usr/local/share/ca-certificates/medisphere-root-ca.crt"
TOLERANCE=30

erreur() { printf 'REFUSÉ : %s\n' "$*" >&2; exit 1; }

while (($#)); do
  case "$1" in
    --emetteur) EMETTEUR="${2:?--emetteur attend une URL}"; shift 2 ;;
    --audience) AUDIENCE="${2:?--audience attend une valeur}"; shift 2 ;;
    --racine) RACINE="${2:?--racine attend un fichier}"; shift 2 ;;
    -h | --help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "Option inconnue : $1 (le jeton se lit sur l'entrée standard)" >&2; exit 2 ;;
  esac
done
[[ -t 0 ]] && erreur "aucun jeton sur l'entrée standard (exemple : jq -r .access_token jetons.json | $0)"
for outil in curl jq openssl base64 fold; do
  command -v "$outil" >/dev/null || erreur "outil manquant : $outil"
done

TRAVAIL="$(mktemp -d)"
chmod 700 "$TRAVAIL"
trap 'rm -rf "$TRAVAIL"' EXIT

# b64url_vers_binaire — base64url (sans rembourrage) sur l'entrée standard → binaire sur la sortie.
b64url_vers_binaire() {
  local s
  s="$(tr -d '\n' | tr '_-' '/+')"
  while (( ${#s} % 4 )); do s+="="; done
  printf '%s' "$s" | base64 -d
}

JETON="$(tr -d '[:space:]')"
IFS=. read -r P1 P2 P3 RESTE <<<"$JETON"
[[ -n "${P1:-}" && -n "${P2:-}" && -n "${P3:-}" && -z "${RESTE:-}" ]] || erreur "forme invalide (trois parties attendues)"
[[ "$P1$P2$P3" =~ ^[A-Za-z0-9_-]+$ ]] || erreur "caractères hors base64url"

ENTETE="$(printf '%s' "$P1" | b64url_vers_binaire | jq -c . 2>/dev/null)" || erreur "en-tête illisible"
CHARGE="$(printf '%s' "$P2" | b64url_vers_binaire | jq -c . 2>/dev/null)" || erreur "charge illisible"

ALG="$(jq -r '.alg // ""' <<<"$ENTETE")"
KID="$(jq -r '.kid // ""' <<<"$ENTETE")"
[[ "$ALG" == RS256 ]] || erreur "algorithme « $ALG » refusé : seul RS256 est accepté (jamais none ni HMAC)"
[[ -n "$KID" ]] || erreur "pas de kid dans l'en-tête"
if jq -e 'has("jku") or has("x5u") or has("jwk")' >/dev/null <<<"$ENTETE"; then
  echo "note : l'en-tête désigne une clé externe (jku/x5u/jwk) : IGNORÉE, la clé vient du JWKS de l'émetteur attendu" >&2
fi

# JWKS de l'émetteur ATTENDU, par sa découverte.
DECOUVERTE="$(curl -sSf --max-time 15 --cacert "$RACINE" "$EMETTEUR/.well-known/openid-configuration")" || erreur "découverte de $EMETTEUR injoignable"
[[ "$(jq -r '.issuer' <<<"$DECOUVERTE")" == "$EMETTEUR" ]] || erreur "la découverte annonce un autre émetteur que $EMETTEUR"
JWKS_URI="$(jq -r '.jwks_uri // empty' <<<"$DECOUVERTE")"
[[ "$JWKS_URI" == "$EMETTEUR/"* ]] || erreur "jwks_uri hors de l'émetteur : $JWKS_URI"
X5C="$(curl -sSf --max-time 15 --cacert "$RACINE" "$JWKS_URI" |
  jq -r --arg k "$KID" '[.keys[] | select(.kid == $k and .kty == "RSA" and ((.use // "sig") == "sig"))][0].x5c[0] // empty')" ||
  erreur "JWKS illisible"
[[ -n "$X5C" ]] || erreur "aucune clé de signature RSA de kid $KID dans le JWKS (clé désactivée ou inconnue)"

{
  echo "-----BEGIN CERTIFICATE-----"
  printf '%s' "$X5C" | fold -w 64
  echo
  echo "-----END CERTIFICATE-----"
} >"$TRAVAIL/cle.crt"
openssl x509 -in "$TRAVAIL/cle.crt" -pubkey -noout >"$TRAVAIL/cle.pub" 2>/dev/null || erreur "x5c illisible"

printf '%s.%s' "$P1" "$P2" >"$TRAVAIL/entree"
printf '%s' "$P3" | b64url_vers_binaire >"$TRAVAIL/signature" || erreur "signature illisible"
openssl dgst -sha256 -verify "$TRAVAIL/cle.pub" -signature "$TRAVAIL/signature" "$TRAVAIL/entree" >/dev/null 2>&1 ||
  erreur "signature invalide pour la clé $KID"

MAINTENANT="$(date +%s)"
jq -e --arg e "$EMETTEUR" '.iss == $e' >/dev/null <<<"$CHARGE" || erreur "iss différent de $EMETTEUR"
EXP="$(jq -r '.exp // empty' <<<"$CHARGE")"
[[ "$EXP" =~ ^[0-9]+$ ]] || erreur "pas d'exp"
((MAINTENANT <= EXP + TOLERANCE)) || erreur "expiré depuis $((MAINTENANT - EXP)) s"
NBF="$(jq -r '.nbf // empty' <<<"$CHARGE")"
if [[ "$NBF" =~ ^[0-9]+$ ]] && ((MAINTENANT + TOLERANCE < NBF)); then erreur "pas encore valable (nbf)"; fi
if [[ -n "$AUDIENCE" ]]; then
  jq -e --arg a "$AUDIENCE" '(.aud | if type == "array" then . else [.] end) | index($a) != null' >/dev/null <<<"$CHARGE" ||
    erreur "audience $AUDIENCE absente de aud"
fi

echo "VALIDE : signature RS256 (kid $KID), émetteur, dates${AUDIENCE:+, audience $AUDIENCE}"
jq '{typ, azp, aud, sub, preferred_username, sid, groups, iat: (.iat | todate), exp: (.exp | todate), events}
    | with_entries(select(.value != null))' <<<"$CHARGE"
