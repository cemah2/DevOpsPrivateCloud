#!/usr/bin/env bash
# sauvegarder-etats.sh — copie externe des états OpenTofu du compartiment tofu-state (M05-E29).
#
# Usage :
#   outils/sauvegarder-etats.sh DOSSIER
# Copie chaque objet d'état COURANT (clés *.tfstate, hors _restauration/ et _essais/, hors
# verrous .tflock) TEL QUEL, donc chiffré (M05-E27), dans DOSSIER/<clé>, et écrit :
#   DOSSIER/manifeste.json     clé, VersionId, serial, lineage, sha256, taille, date
#   DOSSIER/SHA256SUMS         pour « sha256sum -c » à la restauration
# Ne déchiffre RIEN (pas de « tofu state pull », qui produirait une copie en clair) : la phrase
# de chiffrement n'est pas nécessaire, et la copie peut vivre dans un artefact de CI.
#
# Accès S3 : identité tofu-etat (lecture suffit). Sur adm01, AWS_PROFILE=s3-socle
# (s3-tofu.env) donne l'adresse et l'ancre TLS ; en CI, S3_ENDPOINT et AWS_CA_BUNDLE.
#
# Codes retour : 0 tout est copié et chiffré · 1 au moins un état EN CLAIR, illisible ou absent
#                (la copie est faite quand même, pour ne rien perdre) · 2 erreur d'utilisation.
set -euo pipefail

COMPARTIMENT="${COMPARTIMENT:-tofu-state}"
dest="${1:?usage : $0 DOSSIER}"
[[ $# -eq 1 ]] || { echo "usage : $0 DOSSIER" >&2; exit 2; }
for c in aws jq sha256sum; do command -v "$c" >/dev/null || { echo "outil manquant : $c" >&2; exit 2; }; done

s3() {
  if [[ -n "${S3_ENDPOINT:-}" ]]; then
    aws --endpoint-url "$S3_ENDPOINT" --output json "$@"
  else
    aws --output json "$@"
  fi
}

umask 077
mkdir -p "$dest"
manifeste="[]"
anomalie=0

cles="$(s3 s3api list-objects-v2 --bucket "$COMPARTIMENT" --query 'Contents[].Key' \
  | jq -r '.[]? | select(endswith(".tfstate")) | select(startswith("_restauration/") or startswith("_essais/") | not)')"
[[ -n "$cles" ]] || { echo "aucun état trouvé dans $COMPARTIMENT : anomalie" >&2; exit 1; }

while IFS= read -r cle; do
  fichier="$dest/$cle"
  mkdir -p "$(dirname "$fichier")"
  if ! reponse="$(s3 s3api get-object --bucket "$COMPARTIMENT" --key "$cle" "$fichier")"; then
    echo "ILLISIBLE  $cle" >&2
    anomalie=1
    continue
  fi
  version="$(jq -r '.VersionId // "null"' <<<"$reponse")"
  # Un état chiffré par OpenTofu : encrypted_data présent, pas de « resources » lisible.
  if jq -e 'has("encrypted_data") and (has("resources") | not)' "$fichier" >/dev/null 2>&1; then
    etat="chiffre"
  elif jq -e 'has("resources")' "$fichier" >/dev/null 2>&1; then
    etat="EN-CLAIR"
    anomalie=1
  else
    etat="INCONNU"
    anomalie=1
  fi
  serial="$(jq -r '.serial // "?"' "$fichier" 2>/dev/null || echo "?")"
  lineage="$(jq -r '.lineage // "?"' "$fichier" 2>/dev/null || echo "?")"
  somme="$(sha256sum "$fichier" | cut -d' ' -f1)"
  printf '%-9s %-55s serial=%-5s version=%s\n' "$etat" "$cle" "$serial" "$version"
  manifeste="$(jq -c --arg k "$cle" --arg v "$version" --arg s "$serial" --arg l "$lineage" \
    --arg h "$somme" --arg e "$etat" --argjson t "$(stat -c %s "$fichier")" \
    '. + [{cle: $k, version_id: $v, serial: $s, lineage: $l, sha256: $h, taille: $t, etat: $e}]' <<<"$manifeste")"
done <<<"$cles"

jq --arg d "$(date -Iseconds)" --arg b "$COMPARTIMENT" '{date: $d, compartiment: $b, etats: .}' \
  <<<"$manifeste" > "$dest/manifeste.json"
(cd "$dest" && jq -r '.etats[] | "\(.sha256)  \(.cle)"' manifeste.json > SHA256SUMS)

echo "$(jq '.etats | length' "$dest/manifeste.json") état(s) copié(s) dans $dest"
if [[ $anomalie -ne 0 ]]; then
  echo "ANOMALIE : au moins un état est en clair, illisible ou de format inconnu (voir ci-dessus)." >&2
fi
exit "$anomalie"
