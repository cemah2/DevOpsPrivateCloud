# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et yq entre apostrophes
# check-S15.sh — F3-S15 « Faire taire les alertes inutiles » (PLAT-3315) : une MR fusionnée de
# plateforme/observabilite qui cite PLAT-3315 modifie des règles (regles/) ET leurs tests
# (tests/*.test.yaml), ajoute au moins une inhibition ou un regroupement d'Alertmanager ; son pipeline et
# celui de main sont verts, job tests-regles (promtool test rules) compris ; la configuration chargée
# par l'Alertmanager du cluster a autant d'inhibitions que le dépôt (le changement est appliqué) ; la
# revue des alertes de la semaine est publiée dans plateforme/medisphere.
# Lecture seule : API GitLab (MR, diffs, pipelines, jobs, fichiers), Alertmanager (status).

# shellcheck source=_f3-fin.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f3-fin.sh"

title "F3-S15 — Les alertes inutiles se taisent, la couverture reste"
require_cmd jq curl yq

_s15_mr="$(_f3f_mr_fusionnee "$_f3f_obs" PLAT-3315)"
if [[ -z "$_s15_mr" ]]; then
  _ko "$_f3f_obs : aucune MR fusionnée qui cite PLAT-3315 (titre ou description)"
else
  _s15_iid="$(jq -r '.iid' <<<"$_s15_mr")"
  _ok "$_f3f_obs : MR !$_s15_iid fusionnée (PLAT-3315)"
  _s15_d="$(_f3f_mr_diffs "$_f3f_obs" "$_s15_iid")"
  check_cmd "MR !$_s15_iid : modifie des règles d'alerte (regles/)" \
    _f3f_json "$_s15_d" 'any(.[]; (.new_path // "") | startswith("regles/"))'
  check_cmd "MR !$_s15_iid : ajoute ou modifie des tests promtool (tests/*.test.yaml)" \
    _f3f_json "$_s15_d" 'any(.[]; (.new_path // "") | test("^tests/.*\\.test\\.ya?ml$"))'
  check_cmd "MR !$_s15_iid : ajoute au moins une inhibition ou un regroupement d'Alertmanager" \
    _f3f_json "$_s15_d" 'any(.[]; (.diff // "") | split("\n") | any(.[]; test("^\\+.*(source_matchers|target_matchers|group_by|inhibit_rules)")))'
  _s15_pip="$(gitlab_api "projects/$(_f3s_enc "$_f3f_obs")/merge_requests/$_s15_iid/pipelines?per_page=1" 2>/dev/null | jq -c '.[0] // empty' 2>/dev/null || true)"
  check_cmd "MR !$_s15_iid : dernier pipeline vert" _f3f_json "$_s15_pip" '.status == "success"'
  _s15_pid="$(jq -r '.id // empty' <<<"${_s15_pip:-null}" 2>/dev/null || true)"
  check_cmd "MR !$_s15_iid : job tests-regles (promtool test rules) réussi" \
    _f3f_pipeline_job_ok "$_f3f_obs" "${_s15_pid:-0}" '^tests-regles$'
fi

_s15_main="$(_f3f_dernier_pipeline "$_f3f_obs")"
check_cmd "$_f3f_obs : dernier pipeline de main vert" _f3f_json "$_s15_main" '.status == "success"'
check_cmd "$_f3f_obs : job tests-regles réussi sur main" \
  _f3f_pipeline_job_ok "$_f3f_obs" "$(jq -r '.id // 0' <<<"${_s15_main:-null}" 2>/dev/null || echo 0)" '^tests-regles$'

# Appliqué : même nombre d'inhibitions dans le dépôt et dans la configuration chargée par l'Alertmanager.
_s15_git_inh="$(_f3f_gl_fichier "$_f3f_obs" kps/values.yaml | yq -r '.alertmanager.config.inhibit_rules | length' 2>/dev/null || true)"
_s15_am_inh="$(am_api status 2>/dev/null | jq -r '.config.original // ""' 2>/dev/null | yq -r '.inhibit_rules | length' 2>/dev/null || true)"
check_cmd "Alertmanager du cluster : configuration chargée à jour ($_s15_am_inh inhibition(s) chargée(s), ${_s15_git_inh:-?} dans le dépôt)" \
  test -n "$_s15_git_inh" -a "$_s15_git_inh" = "$_s15_am_inh"

# Revue publiée (classement actionnable / non actionnable).
_s15_revue="$(_f3f_fichiers_doc "^$_f3s_doc/.*(bruit|revue-alertes).*\\.md$" | head -n 1)"
if [[ -z "$_s15_revue" ]]; then
  _ko "revue des alertes de la semaine ($_f3s_doc/…bruit… ou …revue-alertes….md) absente de main"
else
  _f3s_doc_contient "$_s15_revue" 'actionnable' "revue des alertes : classement actionnable / non actionnable ($_s15_revue)"
  _f3s_doc_contient "$_s15_revue" 'PLAT-3315' "revue des alertes : renvoie à la MR (PLAT-3315)"
fi
