# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E15.sh — M22-E15 « OpenSearch : la recherche plein texte en comparaison » : à lancer APRÈS le
# retrait. Comparatif publié avec des mesures, espace opensearch-essai et Applications d'essai absents,
# aucun volume orphelin. Lecture seule.

# shellcheck source=_m22-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m22-production.sh"

title "M22-E15 — OpenSearch en comparaison (après retrait)"
require_cmd kubectl jq

check_cmd "comparatif-opensearch.md publié (main) : Loki et OpenSearch, mesures, recommandation" \
  _m22p_doc docs/observabilite/journaux comparatif-opensearch 'OpenSearch' 'Loki' '[0-9]+([.,][0-9]+)? ?(ms|s|Mi?o|Gi?o|MB|GB|MiB|GiB)' 'recommand'

_m22_e15_compte() {
  local c
  c="$(gitlab_api "projects/plateforme%2Fmedisphere/repository/files/$(jq -rn --arg s "$1" '$s|@uri')/raw?ref=main" 2>/dev/null)" || return 1
  (($(grep -Eoc '[0-9]+([.,][0-9]+)? ?(ms|s|Mi?o|Gi?o|MB|GB|MiB|GiB)\b' <<<"$c") >= 6))
}
_m22_e15_mesures() {
  local f
  f="$(_m22p_arbre plateforme/medisphere docs/observabilite/journaux | grep -E '/comparatif-opensearch[^/]*$' | head -n 1)"
  [[ -n "$f" ]] && _m22_e15_compte "$f"
}
check_cmd "le comparatif contient au moins six valeurs mesurées (temps, tailles)" _m22_e15_mesures

if ! kube get namespaces >/dev/null 2>&1; then
  skip "retrait de l'essai" "le compte des checks ne joint pas l'API Kubernetes"
else
  _m22_e15_ns_absent() { ! kube get namespace opensearch-essai >/dev/null 2>&1; }
  check_cmd "espace opensearch-essai retiré" _m22_e15_ns_absent
  _m22_e15_apps_absentes() {
    local l
    l="$(kube -n argocd get applications.argoproj.io -o json 2>/dev/null)" || return 1
    jq -e '[.items[].metadata.name | select(. == "opensearch-essai" or . == "fluent-bit-opensearch")] | length == 0' >/dev/null 2>&1 <<<"$l"
  }
  check_cmd "Applications Argo CD opensearch-essai et fluent-bit-opensearch retirées" _m22_e15_apps_absentes
  _m22_e15_pv() {
    local l
    l="$(kube get pv -o json 2>/dev/null)" || return 1
    jq -e '[.items[] | select((.spec.claimRef.namespace // "") == "opensearch-essai")] | length == 0' >/dev/null 2>&1 <<<"$l"
  }
  check_cmd "aucun volume persistant ne référence encore opensearch-essai" _m22_e15_pv
  _m22_e15_pas_de_fluentbit() {
    local l
    l="$(kube get daemonsets -A -o json 2>/dev/null)" || return 1
    jq -e '[.items[] | select(.metadata.name | test("fluent-bit"))] | length == 0' >/dev/null 2>&1 <<<"$l"
  }
  check_cmd "plus aucun DaemonSet Fluent Bit dans le cluster" _m22_e15_pas_de_fluentbit
fi
