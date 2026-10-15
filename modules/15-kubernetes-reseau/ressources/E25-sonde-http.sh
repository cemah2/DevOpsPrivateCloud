#!/usr/bin/env bash
# ressources/E25-sonde-http.sh — sonde HTTPS de M15-E25 (et de tout le palier 3).
# Fournie : instrument de mesure, pas une solution.
#
# Usage : E25-sonde-http.sh [-i INTERVALLE_S] [-t DELAI_S] [-o FICHIER.csv] URL
#   -i  intervalle entre deux requêtes (défaut 0.2 s)
#   -t  délai maximal d'une requête (défaut 1 s)
#   -o  journal CSV (défaut ~/m15/sonde-AAAAMMJJ-HHMMSS.csv) : horodatage_ms;code;duree_s
# Arrêt : Ctrl-C ; la sonde affiche alors le bilan (requêtes, échecs, plus longue interruption).
# Une requête « échoue » si le code HTTP n'est pas 2xx/3xx (000 = pas de réponse ou TLS refusé).
# Vérifie le certificat contre la racine MédiSphère (jamais -k).
set -uo pipefail

intervalle=0.2
delai=1
sortie=""
racine=/usr/local/share/ca-certificates/medisphere-root-ca.crt

while getopts ':i:t:o:h' opt; do
  case "$opt" in
    i) intervalle="$OPTARG" ;;
    t) delai="$OPTARG" ;;
    o) sortie="$OPTARG" ;;
    h) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "option inconnue (-h pour l'aide)" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
[[ $# -eq 1 ]] || { echo "Usage : $0 [-i S] [-t S] [-o FICHIER] URL" >&2; exit 2; }
url="$1"
[[ -r "$racine" ]] || { echo "racine MédiSphère illisible : $racine" >&2; exit 1; }
if [[ -z "$sortie" ]]; then
  mkdir -p "$HOME/m15"
  sortie="$HOME/m15/sonde-$(date +%Y%m%d-%H%M%S).csv"
fi

total=0
echecs=0
debut_panne=0
plus_longue=0
pannes=0

bilan() {
  local fin
  fin=$(date +%s%3N)
  if ((debut_panne > 0)); then
    # interruption encore en cours à l'arrêt
    ((fin - debut_panne > plus_longue)) && plus_longue=$((fin - debut_panne))
  fi
  echo
  echo "URL                : $url"
  echo "Requêtes           : $total"
  echo "Échecs             : $echecs"
  echo "Interruptions      : $pannes"
  printf 'Plus longue        : %d.%03d s\n' $((plus_longue / 1000)) $((plus_longue % 1000))
  echo "Journal            : $sortie"
  exit 0
}
trap bilan INT TERM

echo "horodatage_ms;code;duree_s" >"$sortie"
echo "Sonde vers $url toutes les $intervalle s (Ctrl-C pour le bilan) — journal : $sortie"
while :; do
  t=$(date +%s%3N)
  r=$(curl -s -o /dev/null --cacert "$racine" --max-time "$delai" -w '%{http_code};%{time_total}' "$url" 2>/dev/null)
  [[ -n "$r" ]] || r="000;$delai"
  code=${r%%;*}
  echo "$t;$r" >>"$sortie"
  total=$((total + 1))
  if [[ "$code" =~ ^[23] ]]; then
    if ((debut_panne > 0)); then
      d=$((t - debut_panne))
      ((d > plus_longue)) && plus_longue=$d
      printf '%s  REPRISE après %d.%03d s\n' "$(date +%T)" $((d / 1000)) $((d % 1000))
      debut_panne=0
    fi
  else
    echecs=$((echecs + 1))
    if ((debut_panne == 0)); then
      debut_panne=$t
      pannes=$((pannes + 1))
      printf '%s  ÉCHEC (code %s)\n' "$(date +%T)" "$code"
    fi
  fi
  sleep "$intervalle"
done
