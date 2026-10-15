#!/usr/bin/env bash
# plateforme/k8s — outils/temoin-api.sh (M16-E25, réutilisé en E29 et E33)
# Témoin côté application : crée un rendez-vous de test par seconde par l'API publiée et
# journalise chaque échec. À l'arrêt (Ctrl-C), affiche le bilan : tentatives, échecs, première et
# dernière erreur, plus longue coupure. Les rendez-vous de test portent le praticien wb-temoin, sur
# des créneaux de 2030 ; « --nettoyer » les supprime ensuite par l'API.
# Usage : outils/temoin-api.sh [--api URL] [--journal FICHIER] | --nettoyer [--api URL]
set -euo pipefail

api="https://mediagenda-recette.apps.par1.medisphere.internal"
journal="$HOME/temoin-api-$(date +%Y%m%d-%H%M%S).log"
nettoyer=0
while (($#)); do
  case "$1" in
    --api) api="$2"; shift 2 ;;
    --journal) journal="$2"; shift 2 ;;
    --nettoyer) nettoyer=1; shift ;;
    *) echo "usage : $0 [--api URL] [--journal FICHIER] | --nettoyer [--api URL]" >&2; exit 2 ;;
  esac
done

if ((nettoyer)); then
  # L'API ne liste que les 1000 premiers rendez-vous par date : on relit la liste à chaque passe
  # et on s'arrête quand une passe ne supprime plus rien (créneaux de 2030 : en fin de liste).
  n=0
  while :; do
    avant=$n
    ids="$(curl -sf --max-time 10 "$api/api/v1/rendez-vous?limite=1000" \
      | jq -r '.[] | select(.praticien == "wb-temoin") | .id')" || { echo "API injoignable" >&2; exit 1; }
    [[ -n "$ids" ]] || break
    for id in $ids; do
      if curl -sf -o /dev/null -X DELETE --max-time 10 "$api/api/v1/rendez-vous/$id"; then n=$((n + 1)); fi
    done
    ((n > avant)) || { echo "suppression impossible (ou rendez-vous hors des 1000 premiers)" >&2; break; }
  done
  echo "$n rendez-vous de test supprimés."
  exit 0
fi

essais=0 echecs=0 premiere="" derniere="" debut_coupure=0 plus_longue=0
bilan() {
  echo
  echo "Bilan : $essais tentatives, $echecs échecs${premiere:+, première erreur $premiere, dernière $derniere}, plus longue coupure ${plus_longue} s."
  echo "Journal : $journal"
}
trap 'bilan; exit 0' INT TERM

base=$((RANDOM * 10))
echo "Témoin sur $api — journal $journal (Ctrl-C pour arrêter)"
while sleep 1; do
  essais=$((essais + 1))
  debut="$(TZ=Europe/Paris date -d "2030-01-01 +$((base + essais)) hours" +%Y-%m-%dT%H:00:00%:z)"
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 -H 'Content-Type: application/json' \
    -d "{\"patient\":\"Témoin\",\"praticien\":\"wb-temoin\",\"debut\":\"$debut\"}" \
    "$api/api/v1/rendez-vous")" || code=000
  maintenant="$(date +%s)"
  if [[ "$code" == 201 ]]; then
    if ((debut_coupure > 0)); then
      d=$((maintenant - debut_coupure)); ((d > plus_longue)) && plus_longue=$d
      echo "$(date +%T) reprise après ${d} s" | tee -a "$journal"
      debut_coupure=0
    fi
  else
    echecs=$((echecs + 1))
    h="$(date +%T)"; premiere="${premiere:-$h}"; derniere="$h"
    ((debut_coupure > 0)) || debut_coupure=$maintenant
    echo "$h échec HTTP $code" | tee -a "$journal"
  fi
done
