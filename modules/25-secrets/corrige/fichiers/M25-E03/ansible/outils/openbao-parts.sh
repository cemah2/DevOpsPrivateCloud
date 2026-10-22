#!/usr/bin/env bash
# openbao-parts.sh — parts de la clé racine d'OpenBao et jeton racine initial (M25-E03, PLAT-2603).
# Projet plateforme/ansible. Aucune valeur sensible n'est jamais écrite en clair sur disque, passée
# en argument d'une commande, ni affichée : elles ne circulent que dans des tubes.
#
#   chiffrer DESTINATAIRES       lit sur l'entrée standard la sortie JSON de
#                                « bao operator init -format=json » ; écrit sur la sortie standard un
#                                document JSON (donc YAML) où chaque part est chiffrée par age pour
#                                SON dépositaire, et le jeton racine pour l'officiant (JETON_POUR).
#                                À enchaîner sur « ansible-vault encrypt » (identité critique).
#   desceller NUMERO IDENTITE    déchiffre la part NUMERO avec l'identité age du dépositaire (fichier,
#                                éventuellement protégé par phrase de passe : age la demande) et la
#                                présente à sys/unseal de BAO_ADDR ; n'affiche que la progression.
#   jeton-racine IDENTITE        déchiffre le jeton racine et le donne à « bao login » (rangé dans
#                                ~/.vault-token, jamais affiché). Paliers 1 seulement : révoqué en E08.
#   resume                       ce que contient le fichier (dépositaires, dates), sans rien déchiffrer.
#
# DESTINATAIRES : fichier de clés PUBLIQUES (pki/openbao-depositaires.txt), une ligne par part,
# dans l'ordre des parts :   <identifiant> <clé publique age1…>     (# = commentaire)
# Variables : BAO_ADDR (serveur), JETON_POUR (identifiant de l'officiant, défaut : WB_MOI),
#             PARTS_FICHIER (défaut : secrets/openbao-init.yml), PARTS_CLE (défaut : openbao_init).
set -euo pipefail
umask 077

fichier="${PARTS_FICHIER:-secrets/openbao-init.yml}"
cle="${PARTS_CLE:-openbao_init}"

erreur() { echo "openbao-parts : $*" >&2; exit 1; }
besoin() { local c; for c in "$@"; do command -v "$c" >/dev/null || erreur "outil manquant : $c"; done; }

# Contenu déchiffré du fichier Ansible Vault (sur la sortie standard, jamais sur disque).
lire_coffre() {
  [[ -r "$fichier" ]] || erreur "$fichier illisible (lance depuis la racine de plateforme/ansible)"
  uv run ansible-vault view "$fichier" 2>/dev/null || erreur "impossible de déchiffrer $fichier (identité critique)"
}

chiffrer() {
  local destinataires="$1" init noms=() cles=() nom pub n i k pour jeton_pour=""
  besoin age jq
  [[ -r "$destinataires" ]] || erreur "$destinataires illisible"
  while read -r nom pub _; do
    [[ -z "$nom" || "$nom" == \#* ]] && continue
    [[ "$pub" =~ ^age1[0-9a-z]{58}$ ]] || erreur "clé publique age invalide pour $nom"
    noms+=("$nom"); cles+=("$pub")
  done < "$destinataires"
  pour="${JETON_POUR:-${WB_MOI:-}}"
  [[ -n "$pour" ]] || erreur "JETON_POUR (ou WB_MOI) : à qui chiffrer le jeton racine ?"
  for i in "${!noms[@]}"; do [[ "${noms[$i]}" == "$pour" ]] && jeton_pour="${cles[$i]}"; done
  [[ -n "$jeton_pour" ]] || erreur "$pour n'est pas dans $destinataires"
  [[ "$(printf '%s\n' "${cles[@]}" | sort -u | wc -l)" -eq "${#cles[@]}" ]] || erreur "deux dépositaires ont la même clé"

  init="$(cat)"
  jq -e '.unseal_keys_b64 and .root_token and .unseal_threshold' >/dev/null <<<"$init" \
    || erreur "l'entrée n'est pas la sortie JSON de « bao operator init -format=json »"
  n="$(jq -r '.unseal_keys_b64 | length' <<<"$init")"
  [[ "$n" -eq "${#noms[@]}" ]] || erreur "$n parts pour ${#noms[@]} dépositaires : rien n'est écrit"

  local parts="[]" chiffre
  for ((k = 0; k < n; k++)); do
    chiffre="$(jq -r ".unseal_keys_b64[$k]" <<<"$init" | tr -d '\n' | age -a -r "${cles[$k]}")"
    parts="$(jq -c --argjson num "$((k + 1))" --arg nom "${noms[$k]}" --arg pub "${cles[$k]}" --arg c "$chiffre" \
      '. + [{numero: $num, depositaire: $nom, destinataire: $pub, part: $c}]' <<<"$parts")"
  done
  chiffre="$(jq -r '.root_token' <<<"$init" | tr -d '\n' | age -a -r "$jeton_pour")"
  jq -n --arg cle "$cle" --argjson parts "$parts" --arg j "$chiffre" --arg pour "$pour" \
    --argjson seuil "$(jq '.unseal_threshold' <<<"$init")" --arg serveur "${BAO_ADDR:-?}" \
    --arg date "$(date -u +%FT%TZ)" '
    {($cle): {
       date: $date, serveur: $serveur, parts: ($parts | length), seuil: $seuil,
       depositaires: $parts,
       jeton_racine: {pour: $pour, chiffre: $j,
                      note: "jeton racine initial, à révoquer en M25-E08 (bao token revoke -self)"}
    }}'
}

desceller() {
  local numero="$1" identite="$2"
  besoin age jq curl
  [[ "$numero" =~ ^[1-9]$ ]] || erreur "numéro de part attendu (1 à 9)"
  [[ -r "$identite" ]] || erreur "identité age illisible : $identite"
  : "${BAO_ADDR:?BAO_ADDR non défini}"
  local part ca=()
  [[ -n "${BAO_CACERT:-}" ]] && ca=(--cacert "$BAO_CACERT")
  # La part déchiffrée ne vit que dans cette variable (mémoire du script), puis dans un tube.
  part="$(lire_coffre | jq -r --arg cle "$cle" --argjson n "$numero" \
      '.[$cle].depositaires[] | select(.numero == $n) | .part' | age -d -i "$identite")" \
    || erreur "part $numero : impossible de la déchiffrer avec $identite (est-ce la bonne personne ?)"
  [[ -n "$part" ]] || erreur "part $numero absente de $fichier"
  printf '%s' "$part" | jq -Rc '{key: .}' \
    | curl -sS --fail-with-body "${ca[@]}" --data @- "$BAO_ADDR/v1/sys/unseal" \
    | jq -r '"part acceptée : \(.progress)/\(.t) ; scellé=\(.sealed)"'
}

jeton_racine() {
  local identite="$1"
  besoin age jq bao
  [[ -r "$identite" ]] || erreur "identité age illisible : $identite"
  lire_coffre | jq -r --arg cle "$cle" '.[$cle].jeton_racine.chiffre' \
    | age -d -i "$identite" | bao login -no-print -
  echo "jeton racine chargé dans ~/.vault-token : n'en fais que ce qu'E04 à E08 demandent, puis révoque-le (E08)."
}

resume() {
  besoin jq
  lire_coffre | jq -r --arg cle "$cle" '.[$cle] |
    "initialisé le \(.date) sur \(.serveur) : \(.parts) parts, seuil \(.seuil)",
    (.depositaires[] | "  part \(.numero) → \(.depositaire) (\(.destinataire[0:16])…)"),
    "  jeton racine → \(.jeton_racine.pour)"'
}

case "${1:-}" in
  chiffrer) [[ $# -eq 2 ]] || erreur "usage : chiffrer DESTINATAIRES < init.json"; chiffrer "$2" ;;
  desceller) [[ $# -eq 3 ]] || erreur "usage : desceller NUMERO IDENTITE"; desceller "$2" "$3" ;;
  jeton-racine) [[ $# -eq 2 ]] || erreur "usage : jeton-racine IDENTITE"; jeton_racine "$2" ;;
  resume) resume ;;
  *) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
