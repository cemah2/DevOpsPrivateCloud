# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E41.sh — M21-E41 « Panne : une règle ne se charge pas » : chaque PrometheusRule du cluster est
# chargée (ses groupes sont vus par la vue globale), les applications de MédiAgenda sont synchronisées,
# le pipeline de mediagenda/deploiement lit les règles (promtool), panne close. Lecture seule.

# shellcheck source=_m21-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-expert.sh"

title "M21-E41 — Toutes les règles sont chargées"
require_cmd jq kubectl curl

_m21_e41_regles="$(_m21x_regles_json)" || _m21_e41_regles=""
_m21_e41_objets="$(kube get prometheusrules.monitoring.coreos.com -A -o json 2>/dev/null)" || _m21_e41_objets=""
if [[ -z "$_m21_e41_regles" || -z "$_m21_e41_objets" ]]; then
  skip "règles" "vue globale ou API Kubernetes muette (lab/bin/check 21 24, 21 15)"
else
  while IFS=$'\t' read -r _m21_e41_ns _m21_e41_nom _m21_e41_groupes; do
    [[ -n "$_m21_e41_nom" ]] || continue
    check_cmd "PrometheusRule $_m21_e41_ns/$_m21_e41_nom chargée par Prometheus" \
      jq -e --arg g "$_m21_e41_groupes" '[.data.groups[]?.name] as $vus | ($g | split(",")) | all(. as $x | $vus | index($x) != null)' \
      <<<"$_m21_e41_regles"
  done < <(jq -r '.items[] | [.metadata.namespace, .metadata.name, ([.spec.groups[]?.name] | join(","))] | @tsv' <<<"$_m21_e41_objets")
fi
for _m21_e41_app in mediagenda-dev mediagenda-recette; do
  if kube -n argocd get applications.argoproj.io "$_m21_e41_app" >/dev/null 2>&1; then
    check_cmd "Application $_m21_e41_app Synced, Healthy, dernière synchronisation réussie" _m21x_app_ok "$_m21_e41_app"
  fi
done
_m21_e41_ci() { _m21x_git_brut mediagenda/deploiement .gitlab-ci.yml 2>/dev/null | grep -q promtool; }
check_cmd "pipeline de mediagenda/deploiement : validation des règles par promtool présente" _m21_e41_ci
check_cmd "RB-217 : section « règle non chargée »" _m21x_doc_contient "$_m21x_rb/RB-217-*.md" '^#+ .*r[eè]gle'
check_cmd "panne M21-E41 close (lab/bin/break 21 41 --annuler après réparation)" _m21x_aucune_panne_active E41
