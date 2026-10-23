#!/usr/bin/env bash
# plateforme/observabilite — outils/mesurer-interruption.sh (F4-S02, CHG-3402, RB-340)
# Relève la mesure d'une fenêtre de changement : secondes d'erreur cumulées, requêtes en erreur de la
# charge, détail par sonde. Même calcul que les checks du final F4 (_f4-montees.sh).
#
#   outils/mesurer-interruption.sh DÉBUT FIN [cluster|temoin] [GROUPES]
#   ex. outils/mesurer-interruption.sh 2026-11-10T20:00:00+01:00 2026-11-10T22:40:00+01:00
#       outils/mesurer-interruption.sh 2026-11-21T08:00:00+01:00 2026-11-21T13:10:00+01:00 temoin 'continuite-openstack.*'
#
# Variables : PROM_URL (défaut http://prometheus.apps.par1.medisphere.internal:9090, Thanos Query),
#             TEMOIN_URL (défaut http://mon01.par1.medisphere.internal:9090).
set -euo pipefail

[[ $# -ge 2 ]] || { echo "Usage : $0 DÉBUT FIN [cluster|temoin] [GROUPES]" >&2; exit 2; }
debut="$(date -d "$1" +%s)" || exit 2
fin="$(date -d "$2" +%s)" || exit 2
source="${3:-cluster}"
groupes="${4:-}"
d=$((fin - debut))
((d > 0)) || { echo "FIN doit suivre DÉBUT" >&2; exit 2; }
[[ -z "$groupes" || "$groupes" =~ ^[a-z0-9.*|-]+$ ]] || { echo "GROUPES : lettres, chiffres, - . * | seulement" >&2; exit 2; }

if [[ "$source" == temoin ]]; then
  base="${TEMOIN_URL:-http://mon01.par1.medisphere.internal:9090}"
  if [[ -n "$groupes" ]]; then serie="max(continuite:sonde_en_erreur{groupe=~\"$groupes\"})"; else serie='max(continuite:sondes_en_erreur:max)'; fi
else
  base="${PROM_URL:-http://prometheus.apps.par1.medisphere.internal:9090}"
  serie='max(continuite:en_erreur)'
fi

# requete 'PromQL' — valeurs du résultat évalué à FIN (une ligne par série : étiquettes puis valeur).
requete() {
  curl -sf --max-time 60 -H 'Accept: application/json' --data-urlencode "query=$1" --data-urlencode "time=$fin" \
    "$base/api/v1/query" | jq -r '.data.result[] | "\(.metric | del(.__name__) | to_entries | map("\(.key)=\(.value)") | join(",")) \(.value[1])"'
}

printf 'Fenêtre : %s → %s (%d s), source %s%s\n' "$1" "$2" "$d" "$source" "${groupes:+, groupes $groupes}"
couverture="$(requete "count_over_time(${serie}[${d}s:15s]) * 15 / $d" | awk '{print $NF}')"
erreur="$(requete "avg_over_time(${serie}[${d}s:15s]) * $d" | awk '{print $NF}')"
printf 'Couverture de la mesure : %.0f %%\n' "$(awk -v x="${couverture:-0}" 'BEGIN { print x * 100 }')"
printf 'Secondes d'"'"'erreur cumulées : %.0f   ← à reporter dans mesure-interruption-s\n' "${erreur:-0}"

if [[ "$source" == cluster ]]; then
  echo "Charge (k6, testid sonde-continuite-*) :"
  requete "sum by (testid) (increase(k6_http_reqs_total{testid=~\"sonde-continuite.*\"}[${d}s]))" | sed 's/^/  requêtes envoyées   /'
  requete "sum by (testid) (increase(k6_http_reqs_total{testid=~\"sonde-continuite.*\", expected_response=\"false\"}[${d}s]))" | sed 's/^/  requêtes en erreur  /'
  echo "MédiAgenda prod :"
  requete "sum(increase(mediagenda_http_requests_total{namespace=\"mediagenda-prod\", route!~\"/sante|/pret|/metrics\", code=~\"5..\"}[${d}s]))" | sed 's/^/  réponses 5xx       /'
  requete "histogram_quantile(0.95, sum by (le) (increase(mediagenda_http_request_duration_seconds_bucket{namespace=\"mediagenda-prod\", route!~\"/sante|/pret|/metrics\"}[${d}s])))" | sed 's/^/  p95 (s)            /'
fi
echo "Détail par sonde (secondes en échec) :"
if [[ "$source" == temoin ]]; then
  requete "avg_over_time(continuite:sonde_en_erreur[${d}s]) * $d" | sed 's/^/  /'
else
  requete "avg_over_time((1 - probe_success{job=\"blackbox\", groupe=~\"continuite-.+\"})[${d}s:30s]) * $d" | sed 's/^/  /'
fi
