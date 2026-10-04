#!/usr/bin/env bash
# check_disk.sh — liste les systèmes de fichiers au-delà d'un seuil d'occupation.
# Version corrigée (M02-E04) du script InfoGér v2.0.
# Usage : check_disk.sh [SEUIL]   (pourcentage, 90 par défaut)
# Codes retour : 0 aucun dépassement, 1 au moins un dépassement, 2 usage.
set -euo pipefail

seuil="${1:-90}"
if [[ ! "$seuil" =~ ^[0-9]+$ ]] || ((seuil > 100)); then
  echo "Usage : ${0##*/} [SEUIL en %]" >&2
  exit 2
fi

alertes=0
# --output évite de découper la sortie de df à la main (points de montage avec espaces) ;
# les pseudo-systèmes de fichiers sont exclus. La boucle lit une substitution de
# processus : elle tourne dans le shell courant, « alertes » survit à la boucle.
while read -r occupation point; do
  occupation="${occupation%\%}"
  [[ "$occupation" =~ ^[0-9]+$ ]] || continue # « - » pour certains montages
  if ((occupation >= seuil)); then
    echo "ALERTE $point : ${occupation}%"
    alertes=$((alertes + 1))
  fi
done < <(df --output=pcent,target -x tmpfs -x devtmpfs -x overlay -x squashfs | tail -n +2)

if ((alertes == 0)); then
  echo "OK : aucun système de fichiers au-dessus de ${seuil}%"
  exit 0
fi
exit 1
