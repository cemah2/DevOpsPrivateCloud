# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E20.sh — M29-E20 « Panne : une expérience de chaos ne s'arrête plus » : aucune expérience hors de
# chaos-experiences et wb-essais, aucun Schedule actif sans durée, daemons prêts avec le socket attendu,
# aucune suppression bloquée, aucun netem sur l'API de recette, p95 revenu, RB-297, panne close.
# Lecture seule (sur les nœuds : crictl et nsenter … tc qdisc show).

# shellcheck source=_m29-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m29-expert.sh"

title "M29-E20 — Plus aucune expérience ne traîne"
require_cmd kubectl jq curl ssh

if ! _m29p_api_repond; then
  skip "Chaos Mesh" "l'API ne répond pas au compte des checks"
elif ! _m29p_lit_chaos; then
  skip "Chaos Mesh" "le compte des checks ne lit pas chaos-mesh.org (ClusterRole wb-checks-services-m29, M29-E09)"
else
  _m29_e20_tous="$(_m29p_chaos_tous)" || _m29_e20_tous="[]"
  check_cmd "aucun objet de chaos hors de $_m29p_chaos_ns (VAP medisphere-chaos-espaces, M29-E09)" \
    bash -c '[[ "$(jq --arg c "$1" "[.[] | select(.metadata.namespace != \$c)] | length" <<<"$2")" == 0 ]]' \
    _ "$_m29p_chaos_ns" "$_m29_e20_tous"
  check_cmd "aucune expérience « en pause » par une annotation mal écrite (annotation *pause* sans experiment.chaos-mesh.org/pause=true)" \
    bash -c '[[ "$(jq "[.[] | (.metadata.annotations // {}) as \$a | select(any(\$a | keys[]; test(\"pause\")))
              | select((\$a[\"experiment.chaos-mesh.org/pause\"] // \"\") != \"true\")] | length" <<<"$1")" == 0 ]]' \
    _ "$_m29_e20_tous"
  check_cmd "aucun Schedule hors pause n'embarque une expérience sans durée" \
    bash -c '[[ "$(jq "[.[] | select(.kind == \"Schedule\") | select((.metadata.annotations[\"experiment.chaos-mesh.org/pause\"] // \"\") != \"true\")
              | select(.spec.type != \"Workflow\") | select([.spec | to_entries[] | select(.key | test(\"Chaos$\")) | .value.duration // \"\"] | all(. == \"\"))] | length" <<<"$1")" == 0 ]]' \
    _ "$_m29_e20_tous"
  check_cmd "aucune expérience bloquée en suppression (finaliseur)" \
    bash -c '[[ "$(jq "[.[] | select(.metadata.deletionTimestamp != null)] | length" <<<"$1")" == 0 ]]' _ "$_m29_e20_tous"
  check_cmd "chaos-daemon prêts sur tous les nœuds visés, socket /host-run/containerd.sock" _m29p_kq \
    '.status.numberReady == .status.desiredNumberScheduled and .status.desiredNumberScheduled > 0
     and ([.spec.template.spec.containers[].args[]?] | index("/host-run/containerd.sock") != null)' -n chaos-mesh daemonset chaos-daemon
  _m29_e20_netem() { _m29x_aucun_netem_api; }
  check_cmd "aucun qdisc netem sur les pods de l'API MédiAgenda (recette)" _m29_e20_netem
fi

_m29_e20_p95="$(_m29p_prom_val 'histogram_quantile(0.95, sum by (le) (rate(mediagenda_http_request_duration_seconds_bucket{namespace="mediagenda-recette", route!~"/sante|/pret|/metrics"}[10m])))')" || _m29_e20_p95=""
if [[ -z "$_m29_e20_p95" || "$_m29_e20_p95" == NaN ]]; then
  skip "p95 de la recette" "pas de trafic sur 10 min : lance quelques requêtes puis relance"
else
  check_cmd "p95 de la recette sous 250 ms (10 min) : ${_m29_e20_p95} s" awk -v v="$_m29_e20_p95" 'BEGIN { exit !(v < 0.25) }'
fi
check_cmd "RB-297 publié (main) : expérience qui ne s'arrête pas" _m29p_doc docs/qualite '^RB-297' 'Schedule' 'finali' 'netem|tc qdisc'
check_cmd "panne M29-E20 close (lab/bin/break 29 20 --annuler après réparation)" _m29x_aucune_panne_active E20
