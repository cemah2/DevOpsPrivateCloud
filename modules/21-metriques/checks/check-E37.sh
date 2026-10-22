# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E37.sh — M21-E37 « Panne : les tableaux de bord sont vides » : pour chaque tableau versionné dans
# plateforme/observabilite (tableaux/*.json) : présent dans Grafana, aucune source citée en dur qui
# n'existe pas, variables label_values() qui renvoient des valeurs, règles d'enregistrement citées qui
# produisent des données ; source par défaut de Grafana = Thanos Query ; pipeline de main vert ;
# RB-217 ; panne close. Lecture seule.

# shellcheck source=_m21-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-expert.sh"

title "M21-E37 — Les tableaux de bord affichent des données"
require_cmd jq curl

_m21_e37_proj="plateforme/observabilite"
# _m21_e37_valeurs ÉTIQUETTE SÉLECTEUR — l'étiquette a au moins une valeur sur les séries du sélecteur.
_m21_e37_valeurs() {
  curl -sf --max-time "$WB_TIMEOUT" -G --data-urlencode "match[]=$2" \
    "${WB_PROM_URL:-http://prometheus.apps.par1.medisphere.internal:9090}/api/v1/label/$1/values" |
    jq -e '.data | length > 0' >/dev/null
}
_m21_e37_uids="$(grafana_api frontend/settings 2>/dev/null | jq -r '[.datasources[].uid] | join(" ")')" || _m21_e37_uids=""
if [[ -z "$_m21_e37_uids" ]]; then
  skip "tableaux de bord" "API de Grafana muette avec le jeton des checks (lab/bin/check 21 05)"
else
  _m21_e37_n=0
  while read -r _m21_e37_f; do
    _m21_e37_json="$(_m21x_git_brut "$_m21_e37_proj" "$_m21_e37_f" 2>/dev/null)" || continue
    _m21_e37_uid="$(jq -r '.uid // empty' <<<"$_m21_e37_json" 2>/dev/null)" || _m21_e37_uid=""
    [[ -n "$_m21_e37_uid" ]] || continue
    _m21_e37_n=$((_m21_e37_n + 1))
    _m21_e37_d="$(grafana_api "dashboards/uid/$_m21_e37_uid" 2>/dev/null | jq -c '.dashboard' 2>/dev/null)" || _m21_e37_d=""
    if [[ -z "$_m21_e37_d" || "$_m21_e37_d" == null ]]; then
      _ko "$_m21_e37_f : tableau $_m21_e37_uid absent de Grafana"
      continue
    fi
    # Sources citées en dur qui n'existent pas
    _m21_e37_inconnues="$(jq -r --arg u " $_m21_e37_uids " '
      [.. | objects | select(has("uid") and has("type") and ((.type | type) == "string") and (.type | test("prometheus|loki|tempo")))
       | .uid | select(type == "string") | select(test("^\\$") | not) | select($u | contains(" " + . + " ") | not)] | unique | join(" ")' <<<"$_m21_e37_d")" || _m21_e37_inconnues=""
    check_cmd "$_m21_e37_f : aucune source de données inconnue citée en dur${_m21_e37_inconnues:+ ($_m21_e37_inconnues)}" test -z "$_m21_e37_inconnues"
    # Variables label_values(sélecteur, étiquette)
    while IFS=$'\t' read -r _m21_e37_v _m21_e37_sel _m21_e37_lab; do
      [[ -n "$_m21_e37_v" ]] || continue
      check_cmd "$_m21_e37_f : la variable \$$_m21_e37_v a des valeurs" _m21_e37_valeurs "$_m21_e37_lab" "$_m21_e37_sel"
    done < <(jq -r '.templating.list[]? | select(.type == "query")
        | ((.definition // "") + " " + (if (.query | type) == "object" then (.query.query // "") else (.query // "") end)) as $q
        | ($q | capture("label_values\\((?<s>[A-Za-z_:][A-Za-z0-9_:]*(\\{[^}]*\\})?|\\{[^}]*\\})\\s*,\\s*(?<l>[A-Za-z_][A-Za-z0-9_]*)\\)")?) as $c
        | select($c != null and ($c.s | test("\\$") | not)) | [.name, $c.s, $c.l] | @tsv' <<<"$_m21_e37_d" 2>/dev/null | sort -u)
    # Règles d'enregistrement citées
    for _m21_e37_r in $(jq -r '[.. | objects | .expr? // empty | strings | scan("[a-zA-Z_][a-zA-Z0-9_]*:[a-zA-Z_][a-zA-Z0-9_]*:[a-zA-Z0-9_]+")] | unique | .[]' <<<"$_m21_e37_d" 2>/dev/null); do
      check_cmd "$_m21_e37_f : la règle d'enregistrement $_m21_e37_r produit des données" _m21x_non_vide "count($_m21_e37_r)"
    done
  done < <(_m21x_git_arbre "$_m21_e37_proj" tableaux 2>/dev/null | grep -E '\.json$')
  check_cmd "au moins un tableau versionné dans $_m21_e37_proj/tableaux" test "$_m21_e37_n" -gt 0
fi

if kube -n supervision get configmaps -l grafana_datasource=1 -o name >/dev/null 2>&1; then
  check_cmd "source de données par défaut de Grafana : Thanos Query (vue globale)" bash -c '
    kubectl --kubeconfig "$1" -n supervision get configmaps -l grafana_datasource=1 -o json 2>/dev/null |
      jq -r ".items[].data[]" | grep -qi "thanos"' _ "${WB_K8S_KUBECONFIG:-$HOME/.config/workbook/k8s-checks.kubeconfig}"
else
  skip "source de données par défaut" "ConfigMaps grafana_datasource illisibles par le compte des checks"
fi
check_cmd "pipeline de main de $_m21_e37_proj vert" _m21x_pipeline_main_vert "$_m21_e37_proj"
check_cmd "RB-217 : section « tableau vide »" _m21x_doc_contient "$_m21x_rb/RB-217-*.md" '^#+ .*(tableau|vide|No data)'
check_cmd "panne M21-E37 close (lab/bin/break 21 37 --annuler après réparation)" _m21x_aucune_panne_active E37
