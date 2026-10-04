#!/usr/bin/env bash
# purge_logs.sh — purge les journaux applicatifs de plus de N jours.
# Version corrigée (M02-E04) du script InfoGér v1.3.
# Usage : purge_logs.sh DOSSIER [JOURS]   (JOURS : 30 par défaut)
set -euo pipefail

usage() { echo "Usage : ${0##*/} DOSSIER [JOURS]" >&2; }

(($# >= 1 && $# <= 2)) || {
  usage
  exit 2
}
dossier="$1"
jours="${2:-30}"
journal=/var/log/purge_logs.log

[[ "$jours" =~ ^[0-9]+$ ]] || {
  echo "JOURS doit être un entier : $jours" >&2
  exit 2
}
# Garde-fous : jamais de purge sur « / » ou sur un dossier inexistant.
[[ -d "$dossier" ]] || {
  echo "dossier introuvable : $dossier" >&2
  exit 1
}
dossier="$(realpath -- "$dossier")"
[[ "$dossier" != / ]] || {
  echo "refus de purger /" >&2
  exit 3
}

echo "$(date -Is) début purge de $dossier ($jours jours)" >>"$journal"

# find évite l'analyse de ls, gère tous les noms de fichiers et compte ce qu'il supprime.
# -mtime +N : modifié il y a plus de N périodes de 24 h (même sémantique que l'original).
nb=$(find "$dossier" -maxdepth 1 -type f \( -name '*.log' -o -name '*.log.gz' \) \
  -mtime "+$jours" -print -delete | wc -l)

# Les archives : seulement ce qui dépasse la même ancienneté, plus « tout » à l'aveugle.
if [[ -d "$dossier/archives" ]]; then
  find "$dossier/archives" -mindepth 1 -maxdepth 1 -mtime "+$jours" -exec rm -rf -- {} +
fi

echo "$(date -Is) fin purge : $nb fichier(s) supprimé(s)" >>"$journal"
