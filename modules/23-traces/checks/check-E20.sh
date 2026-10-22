# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E20.sh — M23-E20 « Panne : les traces sont coupées en morceaux » : les traces MédiAgenda → MédiDoc sont
# entières, la propagation et l'échantillonnage sont cohérents, l'équilibrage par traceID est en place.
# Lecture seule.

# shellcheck source=_m23-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m23-expert.sh"

title "M23-E20 — Des traces entières de bout en bout"
require_cmd kubectl jq curl

check_cmd "traces distribuées mediagenda-api → medidoc (dev) sur les 15 dernières minutes" \
  _m23p_traces 900 "$_m23x_sel_dist"
check_cmd "aucune trace de dev enracinée dans medidoc depuis 10 min (pas de MédiDoc orphelin)" \
  _m23p_sans_traces 600 "$_m23x_sel_racine_doc"
check_cmd "mediagenda-dev : OTEL_PROPAGATORS absent ou contenant tracecontext" \
  _m23x_env_pods mediagenda-dev mediagenda '(.name != "OTEL_PROPAGATORS") or ((.value // "") | test("tracecontext"))'
check_cmd "medidoc-dev : échantillonneur absent ou « parentbased_* »" \
  _m23x_env_pods medidoc-dev medidoc '(.name != "OTEL_TRACES_SAMPLER") or ((.value // "") | test("^parentbased_"))'
check_cmd "agent : exportateur loadbalancing (clé de routage traceID) dans le pipeline de traces" \
  _m23p_config_collector "$_m23p_agent" '([.exporters | to_entries[] | select(.key | test("^loadbalancing")) | .value.routing_key // "traceID"] | index("traceID") != null)
     and all(.service.pipelines | to_entries[] | select(.key | test("^traces")); any(.value.exporters[]; test("^loadbalancing")))'
check_cmd "passerelle : au moins 2 réplicas disponibles" \
  _m23p_kq '(.status.availableReplicas // 0) >= 2' -n traces deployment otel-passerelle-collector
check_cmd "runbook RB-236 « Traces coupées » publié" \
  _m23p_doc "$_m23x_runbooks" RB-236 'traceparent' 'loadbalancing' 'parentbased'
check_cmd "panne M23-E20 close (lab/bin/break 23 20 --annuler après réparation)" _m23x_aucune_panne_active E20
