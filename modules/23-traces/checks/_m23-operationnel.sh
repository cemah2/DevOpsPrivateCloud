# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq, LogQL et TraceQL entre apostrophes
# shellcheck source-path=SCRIPTDIR
# _m23-operationnel.sh — fonctions du palier 2 du module 23 (check-E06 à check-E12). Charge aussi les
# fonctions du palier 1 (_m23d_). Sourcé, jamais lancé seul. Lecture seule. Préfixe _m23o_.

# shellcheck source=_m23-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m23-decouverte.sh"

# _m23o_env_deploy ESPACE DEPLOIEMENT CONTENEUR VARIABLE — valeur d'une variable d'environnement
# (value littérale) du conteneur dans le gabarit du Deployment ; vide si absente.
_m23o_env_deploy() {
  kube get -n "$1" deployment "$2" -o json 2>/dev/null |
    jq -r --arg c "$3" --arg v "$4" \
      '.spec.template.spec.containers[]? | select(.name == $c) | .env[]? | select(.name == $v) | .value // empty' \
      2>/dev/null | head -n 1 || true
}

# _m23o_loki_flux LOCATAIRE 'LogQL' [DEPUIS=1h] — au moins une ligne renvoyée par Loki.
_m23o_loki_flux() {
  loki_requete "$2" "$1" "${3:-1h}" 2>/dev/null |
    jq -e '[.data.result[]?.values[]?] | length > 0' >/dev/null 2>&1
}

# _m23o_exemplars 'sélecteur PromQL' [SECONDES=3600] — l'API des exemplars (Thanos Query ou Prometheus)
# renvoie au moins un exemplar portant trace_id. Code 2 si l'API ne répond pas (pour un « skip »).
_m23o_exemplars() {
  local fin r
  fin="$(date +%s)"
  r="$(curl -sf --max-time "${WB_TIMEOUT:-5}" -G -H "Accept: application/json" \
    --data-urlencode "query=$1" --data-urlencode "start=$((fin - ${2:-3600}))" --data-urlencode "end=$fin" \
    "${WB_PROM_URL:-http://prometheus.apps.par1.medisphere.internal:9090}/api/v1/query_exemplars" 2>/dev/null)" || return 2
  jq -e '.status == "success"' >/dev/null 2>&1 <<<"$r" || return 2
  jq -e '[.data[]?.exemplars[]?.labels.trace_id // empty] | length > 0' >/dev/null 2>&1 <<<"$r"
}
