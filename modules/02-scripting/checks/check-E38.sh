# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur runner01
# check-E38.sh — M02-E38 « Panne : rouge en CI, vert en local » : état sain.
# CI de plateforme/outils verte sur main, aucune MR ouverte au pipeline en échec, aucune
# variable CI qui change le comportement de ShellCheck, verrou uv à jour, outils du pipeline
# présents sur runner01. Lecture seule (API GitLab en GET avec le jeton des checks).

title "M02-E38 — Même résultat en CI et en local"
require_cmd curl jq ssh

_m02_e38_proj="plateforme%2Foutils"
_m02_e38_outils="${WB_SRC:-$HOME/src}/outils"

_m02_e38_main_vert() {
  [[ "$(gitlab_api "projects/$_m02_e38_proj/pipelines?ref=main&per_page=1" | jq -r '.[0].status // ""')" == success ]]
}

# Aucune MR ouverte dont le dernier pipeline a échoué.
_m02_e38_mr_ok() {
  local iid st
  for iid in $(gitlab_api "projects/$_m02_e38_proj/merge_requests?state=opened&per_page=100" | jq -r '.[].iid'); do
    st="$(gitlab_api "projects/$_m02_e38_proj/merge_requests/$iid" | jq -r '.head_pipeline.status // "aucun"')"
    [[ "$st" != failed ]] || return 1
  done
}

# Pas de SHELLCHECK_OPTS dans les variables CI du groupe ni du projet.
_m02_e38_pas_de_variable() {
  local niveau
  for niveau in "groups/plateforme" "projects/$_m02_e38_proj"; do
    gitlab_api "$niveau/variables?per_page=100" | jq -e 'all(.[]; .key != "SHELLCHECK_OPTS")' >/dev/null || return 1
  done
}

_m02_e38_verrou() { (cd "$_m02_e38_outils" && uv lock --check >/dev/null 2>&1); }

check_cmd "API GitLab joignable avec le jeton des checks" gitlab_api "projects/$_m02_e38_proj"
check_cmd "dernier pipeline de main : réussi" _m02_e38_main_vert
check_cmd "aucune merge request ouverte avec un pipeline en échec" _m02_e38_mr_ok
check_cmd "aucune variable CI ne modifie le comportement de ShellCheck (groupe et projet)" _m02_e38_pas_de_variable
if command -v uv >/dev/null 2>&1; then
  check_cmd "clone local : uv.lock à jour par rapport à pyproject.toml" _m02_e38_verrou
else
  skip "clone local : uv.lock à jour" "uv absent de ce poste"
fi
# Vu par le compte qui exécute les jobs (son PATH de shell de connexion), pas par admin (M02-E24).
check_ssh "runner01 : outils du pipeline présents pour gitlab-runner (shellcheck, shfmt, bats, task, uv)" runner01 \
  'sudo -n -u gitlab-runner -H bash -lc '"'"'for c in shellcheck shfmt bats task uv; do command -v "$c" >/dev/null || exit 1; done'"'"
