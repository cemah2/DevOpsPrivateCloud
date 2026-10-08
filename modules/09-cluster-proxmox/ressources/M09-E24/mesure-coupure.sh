#!/usr/bin/env bash
# mesure-coupure.sh — mesure, vue d'un utilisateur, les interruptions d'un service TCP (M09-E24).
#
# Usage : mesure-coupure.sh HÔTE [PORT=22] [INTERVALLE_S=1]
#   ex. : ./mesure-coupure.sh fence01.par1.medisphere.internal 22
#         ./mesure-coupure.sh 10.10.99.123
#
# Toutes les INTERVALLE_S secondes, tente une connexion TCP (délai d'une seconde) vers HÔTE:PORT.
# Affiche chaque changement d'état, horodaté, et la durée de chaque interruption. Ctrl-C affiche
# le bilan (nombre d'interruptions, durée de la plus longue, durée totale). Lecture seule : la
# connexion est ouverte puis refermée aussitôt, sans rien envoyer.
#
# Le nom est résolu à chaque tentative (un changement d'adresse se voit). Pour mesurer un RTO
# indépendant du DNS, donne l'adresse IP.
set -uo pipefail

usage() {
  echo "Usage : $0 HÔTE [PORT=22] [INTERVALLE_S=1]" >&2
  exit 2
}

[[ $# -ge 1 && $# -le 3 ]] || usage
hote="$1"
port="${2:-22}"
pas="${3:-1}"
[[ "$port" =~ ^[0-9]+$ && "$pas" =~ ^[0-9]+$ && "$pas" -ge 1 ]] || usage

nb_coupures=0
plus_longue=0
total=0
etat=""          # "ok" ou "ko"
debut_ko=0

horodatage() { date '+%F %T'; }

# shellcheck disable=SC2016  # $1 et $2 sont ceux de bash -c, volontairement non développés ici
joignable() {
  timeout 1 bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$hote" "$port" 2>/dev/null
}

bilan() {
  local maintenant
  maintenant=$(date +%s)
  if [[ "$etat" == ko ]]; then
    # Interruption en cours au moment du Ctrl-C : on la compte jusqu'à maintenant.
    local d=$((maintenant - debut_ko))
    nb_coupures=$((nb_coupures + 1))
    total=$((total + d))
    ((d > plus_longue)) && plus_longue=$d
    echo "$(horodatage)  (interruption toujours en cours : ${d} s)"
  fi
  echo
  echo "Bilan pour $hote:$port : $nb_coupures interruption(s), plus longue ${plus_longue} s, total ${total} s."
  exit 0
}
trap bilan INT TERM

echo "$(horodatage)  début de la mesure vers $hote:$port (toutes les ${pas} s ; Ctrl-C pour le bilan)"
while true; do
  t=$(date +%s)
  if joignable; then
    if [[ "$etat" == ko ]]; then
      d=$((t - debut_ko))
      nb_coupures=$((nb_coupures + 1))
      total=$((total + d))
      ((d > plus_longue)) && plus_longue=$d
      echo "$(horodatage)  RÉTABLI après ${d} s d'interruption"
    elif [[ -z "$etat" ]]; then
      echo "$(horodatage)  joignable"
    fi
    etat=ok
  else
    if [[ "$etat" != ko ]]; then
      debut_ko=$t
      echo "$(horodatage)  INTERROMPU"
    fi
    etat=ko
  fi
  sleep "$pas"
done
