# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E06.sh — M19-E06 : pipelines : stages, needs, rules et workflow
# À lancer depuis adm01. Lecture seule : API GitLab en GET (.gitlab-ci.yml de main, pipelines, jobs).

# shellcheck source=_m19-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-decouverte.sh"

title "M19-E06 — Pipelines : stages, needs, rules et workflow"
require_cmd jq curl yq

# --- 1. Le fichier de main -------------------------------------------------------------------------
_m19d_e06_yml="$(_m19d_contenu_main "$_M19D_LABO" .gitlab-ci.yml)"
# Ancres et clés de fusion développées (explode) avant la conversion en JSON.
_m19d_e06_cfg="$(yq -o=json 'explode(.)' <<<"$_m19d_e06_yml" 2>/dev/null || true)"
check_cmd "$_M19D_LABO (main) : .gitlab-ci.yml lisible" _m19d_json "$_m19d_e06_cfg" 'type == "object"'
check_cmd "workflow:rules présentes" _m19d_json "$_m19d_e06_cfg" '(.workflow.rules // []) | length > 0'
check_cmd "workflow : pas de pipeline de branche quand une MR est ouverte (CI_OPEN_MERGE_REQUESTS)" \
  _m19d_json "$_m19d_e06_cfg" 'any(.workflow.rules[]?; ((.if // "") | test("CI_OPEN_MERGE_REQUESTS")) and .when == "never")'
check_cmd "workflow:auto_cancel:on_new_commit déclaré" _m19d_json "$_m19d_e06_cfg" '.workflow.auto_cancel.on_new_commit != null'
check_cmd "au moins un job avec needs (graphe)" _m19d_json "$_m19d_e06_cfg" \
  '[to_entries[] | select((.value | type) == "object") | select(.value.needs != null)] | length > 0'
check_cmd "des rules avec changes" _m19d_json "$_m19d_e06_cfg" '[.. | objects | select(has("changes"))] | length > 0'
check_cmd "des conditions sur CI_PIPELINE_SOURCE" _m19d_json "$_m19d_e06_cfg" \
  '[.. | objects | select(has("if")) | .if | select(type == "string" and test("CI_PIPELINE_SOURCE"))] | length > 0'
check_cmd "jobs interruptibles par défaut (default:interruptible ou par job)" _m19d_json "$_m19d_e06_cfg" \
  '(.default.interruptible == true) or ([.. | objects | select(.interruptible == true)] | length > 0)'

# --- 2. Le dernier pipeline de main : réussi, et graphe effectif ------------------------------------
_m19d_e06_main="$(_m19d_pipelines "$_M19D_LABO" 'ref=main&per_page=1')"
check_cmd "dernier pipeline de main réussi" _m19d_json "$_m19d_e06_main" '.[0].status == "success"'
_m19d_e06_pid="$(jq -r '.[0].id // empty' <<<"${_m19d_e06_main:-[]}" 2>/dev/null || true)"
if [[ -n "$_m19d_e06_pid" && -n "$_m19d_e06_cfg" ]]; then
  _m19d_e06_stages="$(jq -c '.stages // ["build", "test", "deploy"]' <<<"$_m19d_e06_cfg")"
  check_cmd "graphe effectif : un job a démarré avant la fin d'un job d'un stage précédent" _m19d_json \
    "$(_m19d_jobs "$_M19D_LABO" "$_m19d_e06_pid")" '
    def rang($s): ($st | index($s)) // -1;
    [.[] | select(.started_at != null and .finished_at != null)] as $j
    | any($j[] as $a | $j[] as $b
          | (rang($a.stage) > rang($b.stage)) and ($a.started_at < $b.finished_at); .)' \
    --argjson st "$_m19d_e06_stages"
else
  skip "graphe effectif du dernier pipeline de main" "pas de pipeline de main ou fichier illisible"
fi

# --- 3. Pas de doublon branche + MR pour un même commit --------------------------------------------
_m19d_e06_recents="$(_m19d_pipelines "$_M19D_LABO" 'per_page=30')"
check_cmd "pipelines récents lisibles" _m19d_json "$_m19d_e06_recents" 'length > 0'
check_cmd "aucun commit n'a à la fois un pipeline de branche (hors main) et un pipeline de MR (30 derniers)" \
  _m19d_json "$_m19d_e06_recents" '
  group_by(.sha)
  | all(.[]; (any(.[]; .source == "push" and .ref != "main" and (.ref | startswith("refs/") | not))
              and any(.[]; .source == "merge_request_event")) | not)'
check_cmd "au moins un pipeline de MR parmi les 30 derniers (le cas normal du développement)" \
  _m19d_json "$_m19d_e06_recents" 'any(.[]; .source == "merge_request_event")'
