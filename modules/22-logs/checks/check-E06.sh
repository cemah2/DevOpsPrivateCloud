# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et LogQL entre apostrophes
#
# check-E06.sh — M22-E06 : Des journaux structurés : MédiAgenda en JSON
# À lancer depuis adm01. Lecture seule : code de mediagenda/api et overlay dev de
# mediagenda/deploiement (GitLab), ConfigMaps de mediagenda-dev et journaux (« kube »), requêtes
# LogQL dans le locataire mediagenda (15 min), compteur de lignes écartées par Alloy (Prometheus).
# Prérequis du contrôle : du trafic sur mediagenda-dev dans les 15 dernières minutes
# (ressources/E04-trafic/trafic.sh, voir l'énoncé).

# shellcheck source=_m22-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m22-operationnel.sh"

title "M22-E06 — Des journaux structurés : MédiAgenda en JSON"
require_cmd jq kubectl curl

_m22o_e06_sel='{namespace="mediagenda-dev", container="api"}'

# --- 1. L'application et son environnement ------------------------------------------------------------
check_output "mediagenda/api (main) : le middleware pose un request_id (X-Request-ID)" 'x-request-id|X-Request-ID' \
  _m22o_contenu_main projects/mediagenda%2Fapi src/mediagenda/app.py
check_cmd "mediagenda-dev : MédiAgenda journalise en DEBUG (les sondes sont donc écrites par l'application)" _m22o_json \
  "$(_m22o_k get configmap mediagenda -n mediagenda-dev -o json)" '.data.MEDIAGENDA_LOG_LEVEL == "DEBUG"'
check_cmd "mediagenda-recette : reste en INFO" _m22o_json \
  "$(_m22o_k get configmap mediagenda -n mediagenda-recette -o json)" '(.data.MEDIAGENDA_LOG_LEVEL // "INFO") == "INFO"'

# --- 2. Ce que Loki reçoit (15 dernières minutes) ----------------------------------------------------
check_cmd "des lignes de MédiAgenda (dev) dans les 15 dernières minutes (sinon : lance le trafic)" bash -c '[[ "$1" -ge 1 ]]' _ \
  "$(_m22o_nb "$_m22o_e06_sel" mediagenda 15m)"
check_cmd "request_id en métadonnée structurée (filtrable sans analyseur)" bash -c '[[ "$1" -ge 1 ]]' _ \
  "$(_m22o_nb "$_m22o_e06_sel"' | request_id=~".+"' mediagenda 15m)"
check_cmd "niveau en métadonnée structurée" bash -c '[[ "$1" -ge 1 ]]' _ \
  "$(_m22o_nb "$_m22o_e06_sel"' | niveau=~"INFO|DEBUG|WARNING|ERROR"' mediagenda 15m)"
_m22o_e06_idx="$(_m22o_etiquettes mediagenda 15m | paste -sd, - || true)"
check_cmd "ni request_id ni niveau parmi les étiquettes indexées (vu : ${_m22o_e06_idx:-rien})" bash -c \
  '[[ -n "$1" ]] && ! grep -Eq "(^|,)(request_id|niveau|level|route|code)(,|$)" <<<"$1"' _ "$_m22o_e06_idx"
check_cmd "aucune ligne de sonde (/sante, /pret, /metrics) dans Loki" bash -c '[[ "$1" -eq 0 ]]' _ \
  "$(_m22o_nb "$_m22o_e06_sel"' | json | route=~"/sante|/pret|/metrics"' mediagenda 15m)"
_m22o_e06_ecartees="$(_m22o_prom_valeur 'sum(increase(loki_process_dropped_lines_total{reason="sonde"}[15m]))')"
check_cmd "…parce qu'Alloy les a écartées (loki_process_dropped_lines_total{reason=\"sonde\"} : ${_m22o_e06_ecartees%%.*} en 15 min)" \
  bash -c '[[ "${1%%.*}" -ge 1 ]]' _ "$_m22o_e06_ecartees"
check_cmd "horodatage de l'entrée = champ « horodatage » de l'application (à la seconde près)" _m22o_json \
  "$(_m22o_requete "$_m22o_e06_sel"' | json | journal="mediagenda.acces"' mediagenda 15m)" \
  '[.data.result[].values[] | select(.[1] | test("horodatage"))][0] as $v
   | $v != null
   and (($v[0] | tonumber / 1e9 | floor)
        == ($v[1] | fromjson | .horodatage | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601))'

# --- 3. La configuration --------------------------------------------------------------------------------
_m22o_e06_cfg="$(_m22o_k get configmap alloy-config -n "$_M22O_NS" -o json | jq -r '.data["config.alloy"] // empty' 2>/dev/null || true)"
check_output "Alloy : traitement propre à MédiAgenda (stage.match sur ses journaux)" 'stage\.match' printf '%s' "$_m22o_e06_cfg"
check_output "Alloy : request_id rangé en métadonnée structurée" 'request_id' printf '%s' "$_m22o_e06_cfg"
_m22o_e06_loki="$(curl -sf --max-time "$WB_TIMEOUT" "$_M22O_LOKI/config" 2>/dev/null || true)"
if [[ -n "$_m22o_e06_loki" ]]; then
  check_cmd "Loki : « niveau » parmi les champs de niveau (log_level_fields)" bash -c \
    'grep -A20 "log_level_fields:" <<<"$1" | grep -Eq "^[[:space:]]*- niveau$"' _ "$_m22o_e06_loki"
else
  skip "Loki : log_level_fields" "/config injoignable depuis adm01"
fi
