#!/usr/bin/env bash
# trafic-mediagenda.sh — trafic de lecture vers MédiAgenda, pour avoir des courbes (M21-E04, E05).
# Uniquement des LECTURES (GET), plus des requêtes volontairement en erreur côté client (404, 422 :
# corps invalide, rien n'est écrit en base). Jamais vers la production.
# Usage : ressources/E04-trafic/trafic-mediagenda.sh [URL] [DUREE_MIN] [REQ_PAR_S]
#   URL        défaut https://mediagenda-recette.apps.par1.medisphere.internal
#   DUREE_MIN  défaut 30 (minutes) ; REQ_PAR_S défaut 4 (requêtes par seconde, 20 au plus)
# Arrêt : Ctrl-C. Le certificat est vérifié par le magasin du système (racine MédiSphère, M06).
set -euo pipefail

url="${1:-https://mediagenda-recette.apps.par1.medisphere.internal}"
duree_min="${2:-30}"
debit="${3:-4}"

case "$url" in
  *mediagenda-prod*|*mediagenda.apps*) echo "Refus : pas de trafic d'essai vers la production ($url)." >&2; exit 2 ;;
esac
[[ "$duree_min" =~ ^[0-9]+$ && "$debit" =~ ^[0-9]+$ ]] || { echo "DUREE_MIN et REQ_PAR_S : des entiers." >&2; exit 2; }
(( debit >= 1 && debit <= 20 )) || { echo "REQ_PAR_S entre 1 et 20 (c'est une recette, pas un test de charge)." >&2; exit 2; }
curl -fsS --max-time 5 "$url/sante" >/dev/null || { echo "$url/sante ne répond pas : rien à faire." >&2; exit 1; }

fin=$(( $(date +%s) + duree_min * 60 ))
pause="$(awk -v d="$debit" 'BEGIN { printf "%.3f", 1 / d }')"
n=0
echo "Trafic vers $url : $debit req/s pendant $duree_min min (Ctrl-C pour arrêter)."
while (( $(date +%s) < fin )); do
  # Un jour ouvré au hasard dans les 14 prochains jours : le cache des créneaux est tantôt
  # froid (miss), tantôt chaud (hit).
  jour="$(date -d "+$(( RANDOM % 14 )) days" +%F)"
  case $(( RANDOM % 10 )) in
    0|1|2|3) chemin="/api/v1/creneaux?date=$jour" ;;
    4|5)     chemin="/api/v1/creneaux?date=$jour&praticien=dr-morel" ;;
    6|7)     chemin="/api/v1/rendez-vous?limite=20" ;;
    8)       chemin="/api/v1/rendez-vous/999999999" ;;   # 404 : rendez-vous inexistant
    9)       chemin="POST" ;;                             # 422 : corps invalide, rien d'écrit
  esac
  if [[ "$chemin" == "POST" ]]; then
    curl -s -o /dev/null --max-time 5 -X POST -H 'Content-Type: application/json' \
      -d '{"patient": ""}' "$url/api/v1/rendez-vous" || true
  else
    curl -s -o /dev/null --max-time 5 "$url$chemin" || true
  fi
  n=$(( n + 1 ))
  (( n % 500 == 0 )) && echo "$(date +%T) $n requêtes envoyées"
  sleep "$pause"
done
echo "Terminé : $n requêtes."
