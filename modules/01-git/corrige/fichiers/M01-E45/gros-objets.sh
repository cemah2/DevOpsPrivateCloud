#!/usr/bin/env bash
# gros-objets.sh — liste les plus gros blobs de TOUT l'historique d'un dépôt Git (M01-E45).
#
# Usage : gros-objets.sh [DÉPÔT] [N]      (défaut : dossier courant, 10 objets)
# Colonnes : taille réelle, taille sur disque (compressée ou en delta), empreinte, chemin
# (premier chemin connu de l'objet). Lecture seule.
set -euo pipefail

depot="${1:-.}"
n="${2:-10}"
git -C "$depot" rev-parse --git-dir >/dev/null

humain() { numfmt --to=iec-i --suffix=o --format='%.1f' "$1"; }

git -C "$depot" rev-list --objects --all \
  | git -C "$depot" cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(objectsize:disk) %(rest)' \
  | awk '$1 == "blob"' \
  | sort -k3,3 -n -r \
  | head -n "$n" \
  | while read -r _type sha taille disque chemin; do
      printf '%10s  %10s  %s  %s\n' "$(humain "$taille")" "$(humain "$disque")" "${sha:0:12}" "${chemin:-?}"
    done

echo
git -C "$depot" count-objects -vH | sed -n 's/^size-pack: /Paquets : /p; s/^in-pack: /Objets empaquetés : /p'
