#!/usr/bin/env bash
# sonde-flotte.sh — simule un répartiteur de charge devant la flotte de démonstration (M04-E25, fourni)
#
# Interroge http://<nœud>/sante chaque seconde et affiche, par nœud, le code HTTP et la version,
# puis le nombre de nœuds en service. Signale toute seconde où moins de MIN nœuds sont en service.
#
# Usage : sonde-flotte.sh [-m MIN] [-i INTERVALLE] [NŒUD...]
#   par défaut : MIN=2, INTERVALLE=1 s, nœuds 10.10.99.42 10.10.99.43 10.10.99.44
# Arrêt : Ctrl+C (affiche alors le bilan : secondes observées, secondes sous le minimum).
set -euo pipefail

min=2
intervalle=1
while getopts ':m:i:h' opt; do
  case "$opt" in
    m) min="$OPTARG" ;;
    i) intervalle="$OPTARG" ;;
    h) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "Usage : $0 [-m MIN] [-i INTERVALLE] [NŒUD...]" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
if (($# > 0)); then
  noeuds=("$@")
else
  noeuds=(10.10.99.42 10.10.99.43 10.10.99.44)
fi

command -v curl >/dev/null || { echo "curl est requis" >&2; exit 1; }

observees=0
degradees=0
bilan() {
  echo
  echo "Bilan : ${observees} relevé(s), ${degradees} sous le minimum de ${min} nœud(s) en service."
}
trap 'bilan; exit 0' INT TERM

while true; do
  ligne="$(date +%H:%M:%S)"
  en_service=0
  for n in "${noeuds[@]}"; do
    # -w : code HTTP ; le corps (« ok 2.0 ») donne la version. Délai court : un nœud lent est hors service.
    reponse="$(curl -s --max-time 1 -w ' %{http_code}' "http://${n}/sante" 2>/dev/null || true)"
    code="${reponse##* }"
    corps="${reponse% *}"
    corps="${corps//$'\n'/}"
    if [[ "$code" == "200" ]]; then
      en_service=$((en_service + 1))
      ligne+="  ${n}=200(${corps#ok })"
    else
      ligne+="  ${n}=${code:-000}"
    fi
  done
  observees=$((observees + 1))
  if ((en_service < min)); then
    degradees=$((degradees + 1))
    ligne+="  | en service : ${en_service}/${#noeuds[@]}  <<< SOUS LE MINIMUM"
  else
    ligne+="  | en service : ${en_service}/${#noeuds[@]}"
  fi
  printf '%s\n' "$ligne"
  sleep "$intervalle"
done
