#!/usr/bin/env bash
# ~/m21/e18/trafic-empoisonne.sh — trafic de recette pendant un canary, dont une requête sur cinq
# provoque une erreur 500 dans MédiAgenda (M21-E18, étape 7). Depuis adm01 (MGMT → gw-par1 443).
# La requête empoisonnée : un caractère nul (%00) dans « praticien » ; PostgreSQL refuse les octets
# nuls dans un texte, psycopg lève une erreur non traitée, l'API répond 500. Elle touche TOUS les
# pods, stables comme canary : c'est voulu (voir le corrigé).
# Usage : trafic-empoisonne.sh [durée en secondes, défaut 600]
# Arrêt : Ctrl-C. Ne vise QUE la recette.
set -Eeuo pipefail

url="https://mediagenda-recette.apps.par1.medisphere.internal"
duree="${1:-600}"
fin=$(( $(date +%s) + duree ))
n=0
while (( $(date +%s) < fin )); do
  n=$((n + 1))
  jour="2026-11-$(printf '%02d' $(( (n % 20) + 1 )))"
  if (( n % 5 == 0 )); then
    chemin="/api/v1/creneaux?date=${jour}&praticien=%00"
  else
    chemin="/api/v1/creneaux?date=${jour}&praticien=dr-martin"
  fi
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url$chemin" || true)"
  printf '%s %s %s\n' "$(date +%T)" "$code" "$chemin"
  sleep 0.2
done
