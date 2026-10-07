#!/usr/bin/env bash
# restaurer-etat.sh — restaure une version précise d'un état OpenTofu du compartiment versionné
# tofu-state (s3-01), sans rien perdre (M05-E42, runbook RB-051).
#
# Usage (depuis adm01, identité S3 chargée) :
#   set -a; . ~/.config/workbook/s3-tofu.env; set +a
#   outils/restaurer-etat.sh lister  <clé>                 # versions et marqueurs, du plus récent au plus ancien
#   outils/restaurer-etat.sh restaurer <clé> <VersionId>   # recopie cette version comme version courante
#
# Ce que fait « restaurer », dans l'ordre :
#   1. refuse si un verrou <clé>.tflock existe (quelqu'un travaille sur cet état) ;
#   2. enregistre la liste complète des versions dans ~/m05/sauvegardes-etat/ (600) ;
#   3. copie l'objet courant (s'il existe) dans ce même dossier ;
#   4. recopie la version demandée comme NOUVELLE version courante (copy-object) : aucune version
#      n'est supprimée, l'historique garde la trace de l'incident et de la restauration ;
#   5. affiche la version courante avant/après.
# Il ne supprime jamais rien (pas de delete-object --version-id). Il ne déchiffre rien : la preuve
# que la version restaurée est la bonne se fait ensuite avec tofu (state list, plan).
# Codes retour : 0 succès, 1 erreur, 2 usage, 3 refus (verrou présent, version inconnue).
set -euo pipefail

compartiment="${TOFU_STATE_BUCKET:-tofu-state}"
endpoint="${S3_ENDPOINT:-https://s3-01.par1.medisphere.internal:8333}"
dossier="${HOME}/m05/sauvegardes-etat"

usage() {
  sed -n '2,12p' "$0" >&2
  exit 2
}

s3() { aws --endpoint-url "$endpoint" --output json "$@"; }

versions() {
  s3 s3api list-object-versions --bucket "$compartiment" --prefix "$1" \
    | jq --arg k "$1" '{
        versions: [(.Versions // [])[] | select(.Key == $k) | {VersionId, IsLatest, LastModified, Size, ETag, type: "version"}],
        marqueurs: [(.DeleteMarkers // [])[] | select(.Key == $k) | {VersionId, IsLatest, LastModified, type: "marqueur"}]
      }'
}

lister() {
  versions "$1" | jq -r '(.versions + .marqueurs) | sort_by(.LastModified) | reverse | .[]
    | [.LastModified, .type, (if .IsLatest then "COURANTE" else "-" end), (.Size // "-" | tostring), .VersionId] | @tsv' \
    | column -t -s $'\t'
}

courante() {
  versions "$1" | jq -r '[(.versions + .marqueurs)[] | select(.IsLatest) | "\(.type):\(.VersionId)"] | .[0] // "absente"'
}

restaurer() {
  local cle="$1" id="$2" horo v
  if s3 s3api head-object --bucket "$compartiment" --key "$cle.tflock" >/dev/null 2>&1; then
    echo "Refus : un verrou $cle.tflock existe. Règle d'abord le verrou (RB-050)." >&2
    exit 3
  fi
  v="$(versions "$cle")"
  if ! jq -e --arg id "$id" '.versions | any(.VersionId == $id)' >/dev/null <<<"$v"; then
    echo "Refus : $id n'est pas une version de données de $cle (un marqueur ne se restaure pas)." >&2
    exit 3
  fi
  umask 077
  mkdir -p "$dossier"
  horo="$(date +%Y%m%dT%H%M%S)"
  printf '%s\n' "$v" >"$dossier/$(tr '/' '_' <<<"$cle").$horo.versions.json"
  echo "Liste des versions enregistrée dans $dossier/"
  if [[ "$(courante "$cle")" == version:* ]]; then
    s3 s3api get-object --bucket "$compartiment" --key "$cle" \
      "$dossier/$(tr '/' '_' <<<"$cle").$horo.courante.bin" >/dev/null
    echo "Objet courant copié (chiffré) dans $dossier/"
  fi
  echo "Avant : $(courante "$cle")"
  s3 s3api copy-object --bucket "$compartiment" --key "$cle" \
    --copy-source "$compartiment/$cle?versionId=$id" >/dev/null
  echo "Après : $(courante "$cle") (copie de $id)"
  echo "Vérifie maintenant : tofu state list, puis tofu plan (doit être vide), dans la configuration concernée."
}

for outil in aws jq column; do
  command -v "$outil" >/dev/null || { echo "outil manquant : $outil" >&2; exit 1; }
done
(($# >= 2)) || usage
case "$1" in
  lister) lister "$2" ;;
  restaurer) (($# == 3)) || usage; restaurer "$2" "$3" ;;
  *) usage ;;
esac
