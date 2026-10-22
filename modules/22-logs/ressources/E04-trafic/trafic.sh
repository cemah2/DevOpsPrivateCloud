#!/usr/bin/env bash
# trafic.sh — M22-E04 et M22-E06 : produit quelques minutes de trafic réaliste sur MédiAgenda, pour
# que les requêtes LogQL aient des journaux d'accès à lire (succès, 404, 422 ; jamais de 5xx voulus).
# Lecture seule côté données : uniquement des GET (créneaux, rendez-vous inexistants, liste).
#
# Usage : trafic.sh [URL] [MINUTES]
#   URL     : défaut https://mediagenda-recette.apps.par1.medisphere.internal (WB_M22_MEDIAGENDA_URL)
#             pour mediagenda-dev (E06) : http://127.0.0.1:18000 après
#             kubectl --context k8s-par1 -n mediagenda-dev port-forward svc/mediagenda 18000:80
#   MINUTES : défaut 10
# La racine MédiSphère du magasin système de adm01 suffit à vérifier le certificat (jamais -k).
set -euo pipefail

url="${1:-${WB_M22_MEDIAGENDA_URL:-https://mediagenda-recette.apps.par1.medisphere.internal}}"
minutes="${2:-10}"
fin=$(( $(date +%s) + minutes * 60 ))
demain="$(date -d tomorrow +%F)"
n=0

echo "Trafic vers $url pendant $minutes min (Ctrl-C pour arrêter)…"
while (( $(date +%s) < fin )); do
  for chemin in \
    "/api/v1/creneaux?date=${demain}" \
    "/api/v1/rendez-vous?limite=5" \
    "/api/v1/rendez-vous/999999" \
    "/api/v1/creneaux" \
    "/api/v1/inexistant"; do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
      -H "X-Request-ID: trafic-m22-$(date +%s%N)" "${url}${chemin}" || true)"
    n=$((n + 1))
    (( n % 50 == 0 )) && echo "  $n requêtes (dernier code : $code)"
  done
  sleep 1
done
echo "Terminé : $n requêtes."
