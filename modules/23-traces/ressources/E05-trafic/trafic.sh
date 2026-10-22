#!/usr/bin/env bash
# trafic.sh — M23-E05 : génère un trafic VARIÉ sur l'API MédiAgenda (dev), pour avoir de quoi interroger
# dans Tempo : créations, conflits (409), introuvables (404), créneaux servis par la base puis par le
# cache, annulations, pièces jointes si MédiDoc est branché (M23-E06).
# Usage (depuis adm01, dans un second terminal : kubectl -n mediagenda-dev port-forward svc/mediagenda 18000:80) :
#   ./trafic.sh [URL=http://127.0.0.1:18000] [TOURS=20]
# Données FACTICES uniquement (patients « Essai-… ») : jamais de vraie donnée de santé, même en dev.
set -euo pipefail

url="${1:-http://127.0.0.1:18000}"
tours="${2:-20}"
jour_base=$(( (RANDOM % 20) + 1 ))

requete() { curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "$@" || echo "000"; }

for ((i = 1; i <= tours; i++)); do
  jour="2027-03-$(printf '%02d' $(( (jour_base + i % 5) % 28 + 1 )))"
  heure=$(printf '%02d' $(( 8 + i % 4 )))
  corps="{\"patient\":\"Essai-$i\",\"praticien\":\"dr-essai-$(( i % 3 ))\",\"debut\":\"${jour}T${heure}:00:00+01:00\",\"motif\":\"Essai M23-E05\"}"
  c1=$(requete -X POST "$url/api/v1/rendez-vous" -H 'Content-Type: application/json' -d "$corps")
  c2=$(requete -X POST "$url/api/v1/rendez-vous" -H 'Content-Type: application/json' -d "$corps")   # 409 attendu
  c3=$(requete "$url/api/v1/creneaux?date=$jour&praticien=dr-essai-$(( i % 3 ))")                    # cache : miss
  c4=$(requete "$url/api/v1/creneaux?date=$jour&praticien=dr-essai-$(( i % 3 ))")                    # cache : hit
  c5=$(requete "$url/api/v1/rendez-vous/999999$i")                                                 # 404 attendu
  c6=$(requete "$url/api/v1/rendez-vous?limite=20")
  printf 'tour %2d : création %s, doublon %s, créneaux %s/%s, introuvable %s, liste %s\n' "$i" "$c1" "$c2" "$c3" "$c4" "$c5" "$c6"
  sleep 0.5
done
echo "Terminé. Les traces sont interrogeables dans Tempo après quelques dizaines de secondes."
