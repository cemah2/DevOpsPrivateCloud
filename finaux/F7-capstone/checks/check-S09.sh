# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S09.sh — F7-S09 « Contrats d'interface et tests de contrat » : contrat du GHSV versionné
# intact dans mediagenda/api, job de contrat et pipeline vert, MR fautive refusée par ce job, instance
# de recette conforme (opérations du contrat présentes, authentification exigée), documentation.
# Lecture seule.

# shellcheck source=_f7-livraison.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f7-livraison.sh"

title "F7-S09 — Contrats d'interface et tests de contrat"
require_cmd curl jq sha256sum

_f7_s09_contrat_local="$(dirname "${BASH_SOURCE[0]}")/../ressources/S01/api-rendez-vous-v1.yaml"
_f7_s09_p="$(_f7c_enc "$_f7l_api")"

# --- Le contrat, intact, dans le dépôt du producteur --------------------------------------------------
_f7_s09_contrat() {
  local f attendu
  [[ -r "$_f7_s09_contrat_local" ]] || return 1
  attendu="$(sha256sum <"$_f7_s09_contrat_local" | cut -d' ' -f1)"
  while IFS= read -r f; do
    [[ "${f##*/}" == api-rendez-vous-v1.yaml ]] || continue
    [[ "$(gitlab_api "projects/$_f7_s09_p/repository/files/$(_f7c_enc "$f")/raw?ref=main" 2>/dev/null | sha256sum | cut -d' ' -f1)" == "$attendu" ]] && return 0
  done < <(_f7c_arbre "$_f7l_api")
  return 1
}
check_cmd "$_f7l_api (main) : contrat du GHSV présent et IDENTIQUE à ressources/S01/api-rendez-vous-v1.yaml" _f7_s09_contrat

_f7_s09_job() {
  local f
  for f in .gitlab-ci.yml $(_f7c_arbre "$_f7l_api" ci | grep -E '\.ya?ml$'); do
    _f7l_contient "$_f7l_api" "$f" 'contrat' && return 0
  done
  return 1
}
check_cmd "$_f7l_api : un job de CI de test de contrat est déclaré" _f7_s09_job
check_cmd "$_f7l_api : le dernier pipeline de main a réussi" _f7l_pipeline_ok "$_f7l_api"

# Une MR fermée sans fusion dont le pipeline a échoué sur un job « contrat ».
_f7_s09_mr_refusee() {
  local iid pid
  while IFS= read -r iid; do
    [[ -n "$iid" ]] || continue
    while IFS= read -r pid; do
      [[ -n "$pid" ]] || continue
      gitlab_api "projects/$_f7_s09_p/pipelines/$pid/jobs?scope%5B%5D=failed&per_page=50" 2>/dev/null |
        jq -e 'any(.[]; .name | test("contrat"; "i"))' >/dev/null 2>&1 && return 0
    done < <(gitlab_api "projects/$_f7_s09_p/merge_requests/$iid/pipelines?per_page=5" 2>/dev/null | jq -r '.[].id' 2>/dev/null)
  done < <(gitlab_api "projects/$_f7_s09_p/merge_requests?state=closed&per_page=30" 2>/dev/null | jq -r '.[].iid' 2>/dev/null)
  return 1
}
check_cmd "$_f7l_api : une MR de démonstration (fermée, non fusionnée) a été refusée par le job de contrat" _f7_s09_mr_refusee

# --- L'instance de recette tient le contrat ----------------------------------------------------------
_f7_s09_operations() {
  _f7l_json "$_f7l_url_recette/openapi.json" | jq -e '
    (.paths | to_entries) as $p
    | any($p[]; (.key | test("^/api/v1/rendez-vous/\\{[^}]+\\}$")) and (.value | has("patch")))
    and any($p[]; .key == "/api/v1/rendez-vous" and ((.value.get.parameters // []) | map(.name) | (index("du") != null and index("au") != null and index("praticien") != null)))' \
    >/dev/null 2>&1
}
check_cmd "recette du client : déplacement (PATCH) et filtres de la liste (praticien, du, au) servis" _f7_s09_operations
check_output "recette du client : une opération du contrat sans jeton répond 401" '^401$' \
  _f7l_code "$_f7l_url_recette/api/v1/creneaux?date=2030-01-07"

# --- Documentation ----------------------------------------------------------------------------------
check_cmd "api/ecarts-contrat-v1.md : écarts classés et décisions (déplacement, filtres, authentification)" \
  _f7l_doc api '^ecarts-contrat-v1\.md$' 'bloquant' 'd(é|e)cision' 'patch|d(é|e)placer' 'jeton|oauth' 'medidoc'
check_cmd "api/versionnage.md : compatibilité, coexistence d'au moins 12 mois, dépréciation" \
  _f7l_doc api '^versionnage\.md$' 'compatib' '12 mois' 'd(é|e)pr(é|e)ciation|sunset'
check_cmd "RB-373 (faire évoluer le contrat d'API d'un client)" _f7l_doc runbooks '^RB-373' 'contrat' 'version'
