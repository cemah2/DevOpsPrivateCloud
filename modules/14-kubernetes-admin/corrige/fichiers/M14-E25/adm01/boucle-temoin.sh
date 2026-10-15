#!/usr/bin/env bash
# boucle-temoin.sh — charge témoin pendant une opération sur k8s-par1 (M14-E25, E29).
# Une requête par seconde vers MédiAgenda (/sante) par un port-forward relancé s'il tombe, et vers
# l'API à travers la VIP (/readyz). Une ligne par requête en échec ou lente (> 2 s), et un bilan.
# Usage : ./boucle-temoin.sh [ESPACE] [SERVICE]   (défaut : mediagenda-recette mediagenda-api)
# Arrêt : Ctrl-C (le bilan s'affiche).
set -uo pipefail
espace="${1:-mediagenda-recette}"
service="${2:-mediagenda-api}"
port=18000
journal="boucle-temoin-$(date +%Y%m%dT%H%M%S).log"
total=0; echecs_app=0; echecs_api=0; pf=""

relancer_pf() {
  [[ -n "$pf" ]] && kill "$pf" 2>/dev/null
  kubectl -n "$espace" port-forward "svc/$service" "$port:80" >/dev/null 2>&1 &
  pf=$!
  sleep 2
}
bilan() {
  [[ -n "$pf" ]] && kill "$pf" 2>/dev/null
  printf 'Bilan : %d secondes, %d échecs MédiAgenda, %d échecs API (journal : %s)\n' \
    "$total" "$echecs_app" "$echecs_api" "$journal" | tee -a "$journal"
  exit 0
}
trap bilan INT TERM

relancer_pf
while true; do
  total=$((total + 1))
  h="$(date +%T)"
  r="$(curl -s -o /dev/null -w '%{http_code} %{time_total}' --max-time 3 "http://127.0.0.1:$port/sante")"
  read -r code duree <<<"$r"
  if [[ "$code" != 200 ]]; then
    echecs_app=$((echecs_app + 1)); echo "$h app ÉCHEC code=$code" | tee -a "$journal"
    kill -0 "$pf" 2>/dev/null || relancer_pf
  elif awk -v d="$duree" 'BEGIN { exit !(d > 2) }'; then
    echo "$h app LENT ${duree}s" | tee -a "$journal"
  fi
  if ! kubectl get --raw /readyz --request-timeout=3s >/dev/null 2>&1; then
    echecs_api=$((echecs_api + 1)); echo "$h api ÉCHEC /readyz" | tee -a "$journal"
  fi
  sleep 1
done
