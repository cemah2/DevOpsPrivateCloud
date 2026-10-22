#!/usr/bin/env bash
# openbao-parts-p3.sh — gestes du palier 3 avec les parts d'OpenBao (M25-E25, E28). Projet plateforme/ansible.
# Complète outils/openbao-parts.sh (M25-E03) avec la même règle : aucune part, aucun jeton n'est
# écrit en clair sur disque, passé en argument ou affiché ; ils ne circulent que dans des tubes.
#
#   migrer NUMERO IDENTITE         déchiffre la part NUMERO avec l'identité age de son dépositaire et la
#                                  présente à sys/unseal de BAO_ADDR AVEC « migrate » (migration du
#                                  seal Shamir → transit, M25-E25). BAO_ADDR = l'adresse du NŒUD, pas
#                                  la VIP. N'affiche que la progression.
#   racine-debut                   lance une génération de jeton racine (sys/generate-root-token/attempt,
#                                  authentifié : jeton de la session, politique plateforme-admin) ;
#                                  écrit le nonce sur la sortie standard et l'OTP dans le fichier
#                                  RACINE_OTP (défaut : $XDG_RUNTIME_DIR/openbao-otp, 600).
#   racine-part NUMERO IDENTITE NONCE
#                                  donne la part de récupération NUMERO (clé de récupération depuis
#                                  M25-E25) pour la génération NONCE ; affiche la progression. Chaque
#                                  dépositaire lance cette commande avec SA clé age.
#   racine-fin ENCODÉ              décode le jeton localement (OTP lu dans RACINE_OTP, puis effacé ;
#                                  l'encodé seul ne vaut rien sans l'OTP) et le donne à
#                                  « bao login » (rangé dans ~/.vault-token, jamais affiché). À
#                                  RÉVOQUER dans la minute : bao token revoke -self.
#   racine-annuler                 annule une génération en cours.
#
# Variables : BAO_ADDR, BAO_CACERT, PARTS_FICHIER (défaut secrets/openbao-init.yml ; pour kms01 :
# secrets/kms01-init.yml), PARTS_CLE (défaut openbao_init ; kms01 : kms01_init), RACINE_OTP.
# Le jeton de la session (racine-*) est lu par « bao print token » (~/.vault-token après bao login).
set -euo pipefail
umask 077

fichier="${PARTS_FICHIER:-secrets/openbao-init.yml}"
cle="${PARTS_CLE:-openbao_init}"
otp_fichier="${RACINE_OTP:-${XDG_RUNTIME_DIR:-/tmp}/openbao-otp}"

erreur() { echo "openbao-parts-p3 : $*" >&2; exit 1; }
besoin() { local c; for c in "$@"; do command -v "$c" >/dev/null || erreur "outil manquant : $c"; done; }

lire_coffre() {
  [[ -r "$fichier" ]] || erreur "$fichier illisible (lance depuis la racine de plateforme/ansible)"
  uv run ansible-vault view "$fichier" 2>/dev/null || erreur "impossible de déchiffrer $fichier (identité critique)"
}

# part NUMERO IDENTITE — la part déchiffrée, sur la sortie standard (pour un tube seulement).
part() {
  local numero="$1" identite="$2"
  [[ "$numero" =~ ^[1-9]$ ]] || erreur "numéro de part attendu (1 à 9)"
  [[ -r "$identite" ]] || erreur "identité age illisible : $identite"
  lire_coffre | jq -r --arg cle "$cle" --argjson n "$numero" \
    '.[$cle].depositaires[] | select(.numero == $n) | .part' | age -d -i "$identite" \
    || erreur "part $numero : impossible de la déchiffrer avec $identite"
}

# api MÉTHODE CHEMIN — requête avec le jeton de la session passé par un fichier de configuration curl
# (jamais sur la ligne de commande) ; corps lu sur l'entrée standard.
api() {
  local methode="$1" chemin="$2" ca=()
  [[ -n "${BAO_CACERT:-}" ]] && ca=(--cacert "$BAO_CACERT")
  curl -sS --fail-with-body "${ca[@]}" -X "$methode" \
    -K <(printf 'header = "X-Vault-Token: %s"\n' "$(bao print token)") \
    --data @- "$BAO_ADDR/v1/$chemin"
}

migrer() {
  besoin age jq curl uv
  : "${BAO_ADDR:?BAO_ADDR non défini (adresse du NŒUD)}"
  [[ "$BAO_ADDR" != *openbao.par1* ]] || erreur "BAO_ADDR désigne la VIP : donne l'adresse du nœud à migrer"
  local ca=()
  [[ -n "${BAO_CACERT:-}" ]] && ca=(--cacert "$BAO_CACERT")
  part "$1" "$2" | jq -Rc '{key: ., migrate: true}' \
    | curl -sS --fail-with-body "${ca[@]}" --data @- "$BAO_ADDR/v1/sys/unseal" \
    | jq -r '"part acceptée : \(.progress)/\(.t) ; scellé=\(.sealed) ; migration=\(.migration)"'
}

racine_debut() {
  besoin jq curl bao
  : "${BAO_ADDR:?BAO_ADDR non défini}"
  local r
  r="$(printf '{}' | api PUT sys/generate-root-token/attempt)" || erreur "lancement refusé : $r"
  install -m 0600 /dev/null "$otp_fichier"
  jq -r '.data.otp' <<<"$r" >"$otp_fichier"
  jq -r '"nonce : \(.data.nonce) ; parts requises : \(.data.required) ; OTP rangé dans '"$otp_fichier"'"' <<<"$r"
}

racine_part() {
  besoin age jq curl bao uv
  local numero="$1" identite="$2" nonce="$3"
  [[ "$nonce" =~ ^[0-9a-f-]{36}$ ]] || erreur "nonce attendu (UUID)"
  part "$numero" "$identite" | jq -Rc --arg n "$nonce" '{key: ., nonce: $n}' \
    | api PUT sys/generate-root-token/update \
    | jq -r '.data | if .complete then "terminé : jeton encodé = \(.encoded_token)" else "part acceptée : \(.progress)/\(.required)" end'
}

racine_fin() {
  besoin bao python3
  local encode="$1"
  [[ -r "$otp_fichier" ]] || erreur "OTP introuvable : $otp_fichier (racine-debut lancé sur ce poste ?)"
  # Décodage local, sans « bao operator generate-root -decode=… -otp=… » : l'encodé et l'OTP réunis
  # SONT le jeton, ils ne passent pas sur une ligne de commande (ps). Jeton = base64(encodé) XOR OTP.
  { printf '%s\n' "$encode"; cat "$otp_fichier"; } | python3 -I -c '
import base64, sys
e, o = sys.stdin.read().split()
b = base64.b64decode(e + "=" * (-len(e) % 4))
sys.stdout.write(bytes(x ^ y for x, y in zip(b, o.encode())).decode())' | bao login -no-print -
  rm -f "$otp_fichier"
  echo "jeton racine chargé dans ~/.vault-token. Fais l'action prévue, puis : bao token revoke -self"
}

racine_annuler() {
  besoin curl bao
  printf '' | api DELETE sys/generate-root-token/attempt >/dev/null && echo "génération annulée"
  rm -f "$otp_fichier"
}

case "${1:-}" in
  migrer) shift; [[ $# -eq 2 ]] || erreur "usage : migrer NUMERO IDENTITE"; migrer "$@" ;;
  racine-debut) racine_debut ;;
  racine-part) shift; [[ $# -eq 3 ]] || erreur "usage : racine-part NUMERO IDENTITE NONCE"; racine_part "$@" ;;
  racine-fin) shift; [[ $# -eq 1 ]] || erreur "usage : racine-fin ENCODÉ"; racine_fin "$@" ;;
  racine-annuler) racine_annuler ;;
  *) erreur "usage : $0 migrer|racine-debut|racine-part|racine-fin|racine-annuler …" ;;
esac
