#!/usr/bin/env bash
# sonde-continue.sh — mesure ce que voient les clients pendant un changement DNS (M06-E08).
#
#   sonde-continue.sh [-s SERVEUR] [-d DUREE_S] [-i INTERVALLE_S] [NOM]
#     -s  résolveur interrogé (défaut 10.10.20.10)
#     -d  durée de la mesure en secondes (défaut 120)
#     -i  intervalle entre deux questions (défaut 0.2)
#     NOM nom à résoudre (défaut dns01.par1.medisphere.internal)
#
# Deux points de vue à chaque tour :
#   brut    : dig, UNE tentative, 1 s d'attente — mesure la fenêtre où le port 53 ne répond pas ;
#   client  : dig avec les réglages d'un client glibc ordinaire (5 s, 2 tentatives) — ce que
#             vit une application. Le critère « sans coupure » porte sur cette colonne.
# Chaque échec est horodaté ; le bilan donne le nombre de questions, d'échecs et la plus
# longue durée observée. Code retour : 0 si aucun échec « client », 1 sinon.
set -euo pipefail

serveur="10.10.20.10"
duree=120
intervalle=0.2
while getopts "s:d:i:" opt; do
  case "$opt" in
    s) serveur="$OPTARG" ;;
    d) duree="$OPTARG" ;;
    i) intervalle="$OPTARG" ;;
    *) echo "Usage : $0 [-s SERVEUR] [-d DUREE_S] [-i INTERVALLE_S] [NOM]" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
nom="${1:-dns01.par1.medisphere.internal}"
command -v dig >/dev/null || { echo "sonde-continue : dig introuvable" >&2; exit 2; }

ms() { date +%s%3N; }

fin=$(( $(date +%s) + duree ))
n=0; ko_brut=0; ko_client=0; pire=0
echo "Sonde : $nom auprès de $serveur pendant ${duree} s (Ctrl+C pour arrêter plus tôt)"
trap 'fin=0' INT
while (( $(date +%s) < fin )); do
  n=$((n + 1))
  if ! dig +short +tries=1 +time=1 "@$serveur" "$nom" A 2>/dev/null | grep -qE '^[0-9.]+$'; then
    ko_brut=$((ko_brut + 1))
    echo "$(date +%T.%3N)  brut   : pas de réponse en 1 s"
  fi
  t0=$(ms)
  if ! dig +short +tries=2 +time=5 "@$serveur" "$nom" A 2>/dev/null | grep -qE '^[0-9.]+$'; then
    ko_client=$((ko_client + 1))
    echo "$(date +%T.%3N)  CLIENT : échec de résolution"
  fi
  t=$(( $(ms) - t0 ))
  (( t > pire )) && pire=$t
  sleep "$intervalle"
done

echo
echo "Bilan : $n tours ; échecs bruts (1 essai, 1 s) : $ko_brut ; échecs client (2 essais, 5 s) : $ko_client ;"
echo "        résolution la plus lente vue par un client : ${pire} ms"
((ko_client == 0))
