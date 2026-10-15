# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E10.sh — M13-E10 : Quotas, rétention et immuabilité des étiquettes
# À lancer depuis adm01. Lecture seule : API de Harbor (wb-checks), GitLab.

# shellcheck source=_m13-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m13-operationnel.sh"

title "M13-E10 — Quotas, rétention et immuabilité des étiquettes"
require_cmd jq

declare -A _m13_quotas=([medisphere]=40 [plateforme]=15 [bibliotheque]=15 [charts]=5 [dockerhub]=40 [ghcr]=20 [quay]=10 [k8s]=15)
for _m13_p in medisphere plateforme bibliotheque charts dockerhub ghcr quay k8s; do
  _m13_q="${_m13_quotas[$_m13_p]}"
  check_cmd "projet $_m13_p : quota de $_m13_q Gio" \
    jq -e --argjson g "$_m13_q" '.quota.hard.storage == ($g * 1073741824)' <<<"$(_m13d_api "projects/$_m13_p/summary" || true)"
done

# --- Rétention de medisphere --------------------------------------------------------------------------
_m13_rid="$(_m13d_projet medisphere | jq -r '.metadata.retention_id // empty' 2>/dev/null || true)"
_m13_ret="$(_m13d_api "retentions/${_m13_rid:-0}")"; [[ -n "$_m13_ret" ]] || _m13_ret='{}'
check_cmd "medisphere : règle de rétention planifiée" \
  jq -e '(.trigger.kind // "") == "Schedule" and ((.trigger.settings.cron // "") != "")' <<<"$_m13_ret"
check_cmd "medisphere : rétention « toujours » sur les étiquettes v*" \
  jq -e '[.rules[]? | select(.disabled != true and .template == "always" and ([.tag_selectors[]? | select(.decoration == "matches" and .pattern == "v*")] | length >= 1))] | length >= 1' <<<"$_m13_ret"
check_cmd "medisphere : rétention des 10 derniers artefacts poussés" \
  jq -e '[.rules[]? | select(.disabled != true and .template == "latestPushedK" and ((.params.latestPushedK // 0) == 10))] | length >= 1' <<<"$_m13_ret"

# --- Immuabilité ------------------------------------------------------------------------------------------
for _m13_p in medisphere bibliotheque; do
  check_cmd "$_m13_p : étiquettes v* immuables" \
    jq -e '[.[]? | select(.disabled != true and ([.tag_selectors[]? | select(.decoration == "matches" and .pattern == "v*")] | length >= 1))] | length >= 1' \
    <<<"$(_m13d_api "projects/$_m13_p/immutabletagrules" || true)"
done

# --- Ramasse-miettes ---------------------------------------------------------------------------------------
_m13_gc="$(_m13d_api "system/gc/schedule")"; [[ -n "$_m13_gc" ]] || _m13_gc='{}'
check_cmd "ramasse-miettes : planification hebdomadaire" \
  jq -e '(.schedule.type // "") as $t | $t == "Weekly" or ($t == "Custom" and ((.schedule.cron // "") | split(" ") | length == 6 and .[5] != "*"))' <<<"$_m13_gc"
check_cmd "ramasse-miettes : supprime les artefacts sans étiquette" \
  jq -e '(.parameters.delete_untagged // false) == true or (((.job_parameters // "{}") | fromjson | .delete_untagged) // false) == true' <<<"$_m13_gc"
_m13_gc_ok() { _m13d_api "system/gc?page_size=20" | jq -e '[.[]? | select(.job_status == "Success")] | length >= 1' >/dev/null 2>&1; }
check_cmd "ramasse-miettes : au moins une exécution réussie" _m13_gc_ok

check_cmd "plateforme/infra (main) : registre/politiques.tf" _m13d_fichier_main "$_M13D_INFRA" registre/politiques.tf
check_cmd "docs/registre/stockage.md sur main" _m13o_doc docs/registre/stockage.md
