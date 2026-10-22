# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et PromQL entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E23.sh — M23-E23 « Astreinte : l'API est lente » : l'API de dev a retrouvé sa latence, sans
# étranglement CPU, l'observabilité est entière (rejoue les checks de M23-E19 à E22), le post-mortem est
# commité, aucune panne n'est encore active. Lecture seule.

# shellcheck source=_m23-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m23-expert.sh"

title "M23-E23 — Astreinte : l'API est lente"
require_cmd kubectl jq curl

_m23_e23_pm="docs/kubernetes/post-mortems"
check_cmd "post-mortem INC-5023 : chronologie, causes, détection, actions" \
  _m23p_doc_nom "$_m23_e23_pm" INC-5023 '^#+ .*[Cc]hronologie' '^#+ .*[Cc]auses?' '^#+ .*[Dd][ée]tection' '^#+ .*[Aa]ctions'
check_cmd "post-mortem : preuves tirées des signaux (TraceQL, PromQL ou LogQL, profil)" \
  _m23p_doc_nom "$_m23_e23_pm" INC-5023 '(\{ *resource\.|\{ *span\.|duration *>|histogram_quantile|rate\(|\| *json|flame|pyroscope)'
check_cmd "latence p95 de la prise de rendez-vous (POST, dev) sous 300 ms sur 10 min" \
  _m23p_prom_valeur_sous 'histogram_quantile(0.95, sum by (le) (rate(mediagenda_http_request_duration_seconds_bucket{namespace="mediagenda-dev", methode="POST", route="/api/v1/rendez-vous"}[10m])))' 0.3
check_cmd "latence p95 de toutes les routes de l'API (dev) sous 300 ms sur 10 min" \
  _m23p_prom_valeur_sous 'histogram_quantile(0.95, sum by (le) (rate(mediagenda_http_request_duration_seconds_bucket{namespace="mediagenda-dev", route=~"/api/.*"}[10m])))' 0.3
check_cmd "API de dev : pas d'étranglement CPU notable (moins de 20 % de périodes étranglées, 10 min)" \
  _m23p_prom_nul_ou_absent 'sum(rate(container_cpu_cfs_throttled_periods_total{namespace="mediagenda-dev", container="api"}[10m])) / sum(rate(container_cpu_cfs_periods_total{namespace="mediagenda-dev", container="api"}[10m])) > 0.2'
check_cmd "aucune span de base de données de MédiAgenda (dev) au-delà de 500 ms depuis 10 min" \
  _m23p_sans_traces 600 "{resource.service.name = \"mediagenda-api\" && $_m23p_attr_env = \"dev\" && span.db.system.name != nil && duration > 500ms} || {resource.service.name = \"mediagenda-api\" && $_m23p_attr_env = \"dev\" && span.db.system != nil && duration > 500ms}"
check_cmd "aucune panne M23 encore marquée active (lab/bin/break)" _m23x_aucune_panne_active

_m23_e23_checks="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=check-E19.sh
source "$_m23_e23_checks/check-E19.sh"
# shellcheck source=check-E20.sh
source "$_m23_e23_checks/check-E20.sh"
# shellcheck source=check-E21.sh
source "$_m23_e23_checks/check-E21.sh"
# shellcheck source=check-E22.sh
source "$_m23_e23_checks/check-E22.sh"
