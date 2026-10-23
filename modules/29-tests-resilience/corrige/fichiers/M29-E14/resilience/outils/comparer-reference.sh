#!/usr/bin/env bash
# plateforme/resilience — outils/comparer-reference.sh (M29-E14, PLAT-3014 ; RB-295)
# Compare un essai de charge (identifié par son testid, sur une fenêtre de temps) à la référence.
# Mesures AGRÉGÉES lues dans Prometheus (Thanos Query), jamais dans les résumés des exécuteurs (chacun
# n'a vu qu'une part de la charge) :
#   - p95 / p99 côté SERVEUR : histogramme de MédiAgenda sur la fenêtre (exact, toutes requêtes) ;
#   - taux d'erreurs 5xx côté serveur ;
#   - débit atteint côté CLIENT : k6_http_reqs_total{testid} (somme des exécuteurs) ;
#   - p95 côté client : max des p95 des exécuteurs (indicateur seulement : on ne moyenne pas des centiles).
# Usage : outils/comparer-reference.sh --testid ID --debut EPOCH --fin EPOCH [--reference FICHIER]
# Sortie : tableau lisible + resultat.json ; code 0 si dans les tolérances, 1 sinon, 2 si mesure impossible.
# Variables : PROM_URL (défaut http://thanos-query.supervision.svc.cluster.local:9090).
set -euo pipefail

PROM_URL="${PROM_URL:-http://thanos-query.supervision.svc.cluster.local:9090}"
ref=charge/references/mediagenda-recette.json
testid="" debut="" fin=""
while (($#)); do
  case "$1" in
    --testid) testid="$2"; shift 2 ;;
    --debut) debut="$2"; shift 2 ;;
    --fin) fin="$2"; shift 2 ;;
    --reference) ref="$2"; shift 2 ;;
    *) echo "option inconnue : $1" >&2; exit 2 ;;
  esac
done
[[ -n "$testid" && -n "$debut" && -n "$fin" ]] || { echo "usage : $0 --testid ID --debut EPOCH --fin EPOCH" >&2; exit 2; }
duree=$((fin - debut))
((duree >= 120)) || { echo "fenêtre trop courte (${duree} s)" >&2; exit 2; }

# requete 'PromQL' — valeur scalaire évaluée à la fin de la fenêtre (vide si aucune série).
requete() {
  curl -sf --max-time 30 --data-urlencode "query=$1" --data-urlencode "time=$fin" "$PROM_URL/api/v1/query" |
    jq -r '.data.result[0].value[1] // empty'
}
F='namespace="mediagenda-recette", route!~"/sante|/pret|/metrics"'
D="${duree}s"
p95="$(requete "histogram_quantile(0.95, sum by (le) (increase(mediagenda_http_request_duration_seconds_bucket{$F}[$D])))")"
p99="$(requete "histogram_quantile(0.99, sum by (le) (increase(mediagenda_http_request_duration_seconds_bucket{$F}[$D])))")"
err="$(requete "sum(increase(mediagenda_http_requests_total{$F, code=~\"5..\"}[$D])) / sum(increase(mediagenda_http_requests_total{$F}[$D]))")"
rps="$(requete "sum(increase(k6_http_reqs_total{testid=\"$testid\"}[$D])) / $duree")"
p95c="$(requete "max(max_over_time(k6_http_req_duration_p95{testid=\"$testid\", type=\"metier\"}[$D]))")"

if [[ -z "$p95" || -z "$p99" || -z "$rps" || "$p95" == NaN || "$p99" == NaN ]]; then
  echo "Mesure impossible : pas de séries pour testid=$testid sur la fenêtre (TestRun en erreur ? écriture distante ?)" >&2
  exit 2
fi
err="${err:-0}"
[[ "$err" == NaN ]] && err=0

jq -n --slurpfile r "$ref" --arg testid "$testid" --argjson debut "$debut" --argjson fin "$fin" \
  --argjson p95 "$p95" --argjson p99 "${p99:-0}" --argjson err "$err" --argjson rps "$rps" --arg p95c "${p95c:-}" '
  $r[0] as $ref | $ref.tolerances as $t |
  {testid: $testid, debut: $debut, fin: $fin,
   mesures: {p95_s: $p95, p99_s: $p99, taux_erreurs: $err, debit_rps: $rps, p95_client_max_s: ($p95c | tonumber? // null)},
   reference: {p95_s: $ref.p95_s, p99_s: $ref.p99_s, taux_erreurs: $ref.taux_erreurs, debit_rps: $ref.debit_rps},
   ecarts: {p95: (($p95 - $ref.p95_s) / $ref.p95_s), p99: (($p99 - $ref.p99_s) / $ref.p99_s),
            erreurs: ($err - $ref.taux_erreurs), debit: (($rps - $ref.debit_rps) / $ref.debit_rps)},
   verdicts: {p95: ($p95 <= $ref.p95_s * (1 + $t.p95_relative)), p99: ($p99 <= $ref.p99_s * (1 + $t.p99_relative)),
              erreurs: ($err <= $ref.taux_erreurs + $t.taux_erreurs_absolu),
              debit: ($rps >= $ref.debit_rps * (1 + $t.debit_relatif_min))}}
  | .ok = ([.verdicts[]] | all)' >resultat.json

jq -r '"Essai \(.testid)\n" +
  "  p95 serveur   : \(.mesures.p95_s * 1000 | floor) ms (réf. \(.reference.p95_s * 1000 | floor) ms, écart \(.ecarts.p95 * 100 | floor) %) \(if .verdicts.p95 then "OK" else "RÉGRESSION" end)\n" +
  "  p99 serveur   : \(.mesures.p99_s * 1000 | floor) ms (réf. \(.reference.p99_s * 1000 | floor) ms) \(if .verdicts.p99 then "OK" else "RÉGRESSION" end)\n" +
  "  erreurs 5xx   : \(.mesures.taux_erreurs * 100) % (réf. \(.reference.taux_erreurs * 100) %) \(if .verdicts.erreurs then "OK" else "RÉGRESSION" end)\n" +
  "  débit atteint : \(.mesures.debit_rps | floor) req/s (réf. \(.reference.debit_rps | floor)) \(if .verdicts.debit then "OK" else "INSUFFISANT" end)\n" +
  "  p95 client (max des exécuteurs, indicatif) : \(.mesures.p95_client_max_s // "n/d")"' resultat.json
jq -e '.ok' resultat.json >/dev/null
