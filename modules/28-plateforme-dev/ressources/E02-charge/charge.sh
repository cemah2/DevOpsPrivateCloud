#!/usr/bin/env bash
# charge.sh — génère du trafic HTTP vers MédiAgenda (dev ou recette uniquement), depuis adm01.
# M28-E02 (HPA) et M28-E03 (KEDA). Outils : bash, curl, xargs (présents sur adm01), rien à installer.
#
# Usage : charge.sh [-u URL] [-d DURÉE_S] [-c CONCURRENCE] [-m lecture|rendez-vous]
#   -u  URL de base (défaut : https://mediagenda-recette.apps.par1.medisphere.internal)
#   -d  durée en secondes (défaut : 300)
#   -c  requêtes en parallèle (défaut : 16)
#   -m  lecture      : GET des créneaux et de la liste des rendez-vous (CPU de l'API)
#       rendez-vous  : POST de rendez-vous FACTICES (« Essai-… »), chacun publie une demande de
#                      notification (M27-E08) : remplit la file notifications de la recette
# Refuse toute URL qui n'est pas celle d'un environnement dev ou recette (pas de charge en production).
# Affiche à la fin le nombre de réponses par code HTTP.
set -euo pipefail

url="https://mediagenda-recette.apps.par1.medisphere.internal"
duree=300
conc=16
mode=lecture

while getopts ':u:d:c:m:h' opt; do
  case "$opt" in
    u) url="${OPTARG%/}" ;;
    d) duree="$OPTARG" ;;
    c) conc="$OPTARG" ;;
    m) mode="$OPTARG" ;;
    h) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "option inconnue : -$OPTARG (voir -h)" >&2; exit 2 ;;
  esac
done

[[ "$duree" =~ ^[0-9]+$ && "$conc" =~ ^[0-9]+$ ]] || { echo "durée et concurrence : entiers attendus" >&2; exit 2; }
(( conc >= 1 && conc <= 64 )) || { echo "concurrence entre 1 et 64" >&2; exit 2; }
case "$mode" in lecture | rendez-vous) ;; *) echo "mode : lecture ou rendez-vous" >&2; exit 2 ;; esac
hote="${url#https://}"
hote="${hote%%/*}"
if [[ ! "$hote" =~ ^mediagenda-(dev|recette)\.apps\.par1\.medisphere\.internal$ ]]; then
  echo "refusé : $hote n'est pas un environnement dev ou recette de MédiAgenda (pas de charge en production)" >&2
  exit 2
fi

# Vérification préalable : l'API répond.
curl -sf --max-time 5 -o /dev/null "$url/sante" || { echo "$url/sante ne répond pas" >&2; exit 1; }

resultats="$(mktemp)"
trap 'rm -f "$resultats"' EXIT
fin=$(( $(date +%s) + duree ))
export url mode fin

# Une requête : affiche le code HTTP (000 si pas de réponse).
requete() {
  local n="$1" jour heure minute corps
  if [[ "$mode" == lecture ]]; then
    if (( n % 4 == 0 )); then
      curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 "$url/api/v1/rendez-vous?limite=50"
    else
      jour=$(( (n % 28) + 1 ))
      curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 \
        "$url/api/v1/creneaux?date=2030-03-$(printf '%02d' "$jour")&praticien=dr-essai-$(( n % 7 ))"
    fi
  else
    # Créneau factice, loin dans le futur, réparti pour limiter les conflits (409).
    jour=$(( (n % 28) + 1 )); heure=$(( 8 + (n / 28) % 4 )); minute=$(( (n / 112) % 2 * 30 ))
    corps=$(printf '{"patient":"Essai-%d","praticien":"dr-essai-%d","debut":"2031-%02d-%02dT%02d:%02d:00+01:00","duree_minutes":30,"motif":"Essai de charge"}' \
      "$n" "$(( (n / 224) % 50 ))" "$(( (n / 11200) % 12 + 1 ))" "$jour" "$heure" "$minute")
    curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 -H 'Content-Type: application/json' \
      -d "$corps" "$url/api/v1/rendez-vous"
  fi
}
export -f requete

echo "Charge « $mode » sur $url : $duree s, $conc en parallèle (Ctrl-C pour arrêter)…"
n=0
while (( $(date +%s) < fin )); do
  # Lots de 20 × concurrence requêtes, numérotées pour varier les paramètres.
  seq "$n" "$(( n + 20 * conc - 1 ))" | xargs -P "$conc" -I{} bash -c 'requete {}' >>"$resultats" || true
  n=$(( n + 20 * conc ))
done
echo "Réponses par code HTTP :"
sort "$resultats" | uniq -c | sort -rn
