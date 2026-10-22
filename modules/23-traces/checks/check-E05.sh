# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E05.sh — M23-E05 : Explorer les traces dans Grafana : TraceQL
# Lecture seule : fichier requetes/E05.traceql de plateforme/observabilite (GitLab, GET) ; chaque requête
# (une par ligne, hors commentaires « # ») est rejouée dans Tempo sur les 24 dernières heures.

# shellcheck source=_m23-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m23-decouverte.sh"

title "M23-E05 — Explorer les traces dans Grafana : TraceQL"
require_cmd jq kubectl curl

_M23D_E05="$(_m23d_fichier plateforme/observabilite requetes/E05.traceql 2>/dev/null || true)"
_m23d_e05_requetes() { grep -Ev '^[[:space:]]*(#|$)' <<<"$_M23D_E05" || true; }
_m23d_e05_nb="$(_m23d_e05_requetes | grep -c . || true)"

check_cmd "plateforme/observabilite (main) : requetes/E05.traceql présent" test -n "$_M23D_E05"
check_cmd "au moins 10 requêtes (une par ligne, hors commentaires) : ${_m23d_e05_nb:-0} trouvée(s)" \
  test "${_m23d_e05_nb:-0}" -ge 10
check_cmd "opérateurs structurels utilisés (>>, > ou ~)" grep -Eq '\}[[:space:]]*(>>|>|~|<<|<)[[:space:]]*\{' <<<"$(_m23d_e05_requetes)"
check_cmd "agrégat ou sélection utilisés (| count(), | avg(…), | select(…))" grep -Eq '\|[[:space:]]*(count|avg|min|max|sum|select)\(' <<<"$(_m23d_e05_requetes)"
check_cmd "intrinsèques utilisés (duration, kind, status, name, trace:…)" grep -Eq '(duration|kind|status|name|trace:[a-zA-Z]+)[[:space:]]*(=|!=|>|<|=~)' <<<"$(_m23d_e05_requetes)"

_m23d_e05_i=0
while IFS= read -r _m23d_e05_q; do
  [[ -n "$_m23d_e05_q" ]] || continue
  _m23d_e05_i=$((_m23d_e05_i + 1))
  _m23d_e05_n="$(_m23d_traceql_nb "$_m23d_e05_q" 86400)"
  check_cmd "requête $_m23d_e05_i acceptée par Tempo et non vide sur 24 h (${_m23d_e05_n} trace(s)) : ${_m23d_e05_q:0:70}" \
    test "$_m23d_e05_n" -gt 0
done < <(_m23d_e05_requetes)
