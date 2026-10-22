# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # TraceQL entre apostrophes
#
# check-E12.sh — M23-E12 : Trouver où passe le temps
# Lecture seule : marqueur local de panne (~/.local/state/workbook), journal de diagnostic dans
# plateforme/medisphere (GitLab, GET), recherches TraceQL dans Tempo sur la recette (15 dernières minutes).

# shellcheck source=_m23-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m23-operationnel.sh"

title "M23-E12 — Trouver où passe le temps"
require_cmd jq kubectl curl

_m23o_e12_marqueur="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives/M23-E12"
check_cmd "la lenteur injectée n'est plus active (lab/bin/break 23 12 réparé, sans --annuler en cours)" test ! -e "$_m23o_e12_marqueur"
check_cmd "plateforme/medisphere : journal de diagnostic INC-5012 (traces, span, cause, prévention)" \
  _m23d_doc_nom docs/kubernetes/journal INC-5012 'trace' 'span' 'cause' 'pr[ée]vention'

_m23o_e12_activite="$(_m23d_traceql_nb '{ resource.service.name = "mediagenda-api" && resource.deployment.environment.name = "recette" && kind = server }' 900)"
if [[ "$_m23o_e12_activite" -le 0 ]]; then
  check_cmd "requêtes récentes de recette dans Tempo (15 min) : relance le trafic sur la recette" false
else
  check_cmd "recette : aucune span PostgreSQL de plus de 300 ms (15 min)" _m23d_sans_traces 900 \
    '{ resource.deployment.environment.name = "recette" && (span.db.system.name = "postgresql" || span.db.system = "postgresql") && duration > 300ms }'
  check_cmd "recette : aucune span Valkey de plus de 200 ms (15 min)" _m23d_sans_traces 900 \
    '{ resource.deployment.environment.name = "recette" && (span.db.system.name = "redis" || span.db.system = "redis") && duration > 200ms }'
  check_cmd "recette : aucune requête serveur de plus de 300 ms (15 min)" _m23d_sans_traces 900 \
    '{ resource.service.name = "mediagenda-api" && resource.deployment.environment.name = "recette" && kind = server && duration > 300ms }'
fi
