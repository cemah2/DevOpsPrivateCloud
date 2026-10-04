#!/bin/bash
# check_disk.sh - InfoGer - v2.0
# Alerte si une partition depasse le seuil (en %). Sortie : liste des partitions en alerte.
# Usage : check_disk.sh [seuil]

SEUIL=${1:-90}
alertes=0

function verifier {
  local ligne=$1
  local usage=$(echo $ligne | awk '{print $5}' | tr -d '%')
  local point=$(echo $ligne | awk '{print $6}')
  if [ $usage -ge $SEUIL ]; then
    echo "ALERTE $point : $usage%"
    alertes=$((alertes+1))
  fi
}

df -P | tail -n +2 | while read ligne; do
  verifier "$ligne"
done

if [ $alertes == 0 ]; then
  echo "OK : aucune partition au-dessus de $SEUIL%"
fi

grep -q "^/dev/" /proc/mounts
if [ $? -ne 0 ]; then
  echo "pas de systeme de fichiers local ?"
fi
exit $alertes
