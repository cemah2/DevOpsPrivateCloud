#!/usr/bin/env bash
# capi/outils/suivi-temoin.sh — compte chaque seconde les pods « temoin » prêts dans capi-essai (M18-E13).
# Usage : capi/outils/suivi-temoin.sh [KUBECONFIG]   (Ctrl+C pour arrêter : affiche le minimum observé)
# Lecture seule. Sortie : « HH:MM:SS prêts/désirés » ; « ? » quand l'API ne répond pas (à noter aussi :
# pendant le remplacement du nœud de contrôle unique, l'API peut décrocher quelques secondes).
set -uo pipefail

kc="${1:-$HOME/.config/workbook/m18/capi-essai.kubeconfig}"
min=""

fin() {
  printf 'minimum de pods prêts observé : %s\n' "${min:-inconnu}"
  exit 0
}
trap fin INT TERM

while :; do
  ligne="$(kubectl --kubeconfig "$kc" --request-timeout=2s -n wb-essais get deployment temoin \
    -o jsonpath='{.status.readyReplicas}/{.spec.replicas}' 2>/dev/null)" || ligne="?"
  pret="${ligne%%/*}"
  [[ "$ligne" == /* ]] && pret=0 && ligne="0${ligne}"
  if [[ "$pret" =~ ^[0-9]+$ ]] && { [[ -z "$min" ]] || (( pret < min )); }; then
    min="$pret"
  fi
  printf '%s %s\n' "$(date +%T)" "$ligne"
  sleep 1
done
