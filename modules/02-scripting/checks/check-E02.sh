# shellcheck shell=bash
#
# check-E02.sh — M02-E02 : Créer le projet plateforme/outils
# À lancer depuis adm01. Lecture seule : API GitLab avec le jeton des checks (read_api)
# et copie de travail locale ~/src/outils.

title "M02-E02 — Créer le projet plateforme/outils"
require_cmd git jq curl

_m02_p="projects/plateforme%2Foutils"
_m02_clone="${WB_SRC:-$HOME/src}/outils"

# _m02_val JSON FILTRE — valeur brute d'un champ (vide si absent ou JSON invalide)
_m02_val() { jq -r "$2" <<<"$1" 2>/dev/null || true; }

# --- Projet --------------------------------------------------------------------
_m02_projet="$(gitlab_api "$_m02_p" 2>/dev/null)" || _m02_projet=""
check_cmd "GitLab : le projet plateforme/outils existe et est lisible avec le jeton des checks" \
  test -n "$_m02_projet"
check_output "projet privé" '^private$' _m02_val "$_m02_projet" '.visibility'
check_output "branche par défaut : main" '^main$' _m02_val "$_m02_projet" '.default_branch'
check_output "méthode de fusion conforme au choix de l'équipe (historique semi-linéaire ou fast-forward)" \
  '^(rebase_merge|ff)$' _m02_val "$_m02_projet" '.merge_method'
check_output "fusion refusée tant que le pipeline n'a pas réussi" '^true$' \
  _m02_val "$_m02_projet" '.only_allow_merge_if_pipeline_succeeds'
check_output "fusion refusée tant que des discussions restent ouvertes" '^true$' \
  _m02_val "$_m02_projet" '.only_allow_merge_if_all_discussions_are_resolved'

# --- Protections ----------------------------------------------------------------
_m02_pb="$(gitlab_api "$_m02_p/protected_branches/main" 2>/dev/null)" || _m02_pb=""
check_output "main protégée : personne ne peut y pousser directement" '^\[0\]$' \
  _m02_val "$_m02_pb" '[.push_access_levels[].access_level] | sort | tostring'
check_output "main protégée : seuls les Maintainers fusionnent" '^\[40\]$' \
  _m02_val "$_m02_pb" '[.merge_access_levels[].access_level] | sort | tostring'
check_output "main protégée : poussée forcée interdite" '^false$' \
  _m02_val "$_m02_pb" '.allow_force_push'
_m02_pt="$(gitlab_api "$_m02_p/protected_tags" 2>/dev/null)" || _m02_pt=""
check_output "étiquettes v* protégées" '^true$' _m02_val "$_m02_pt" 'any(.[]; .name == "v*")'

# --- Contenu de main --------------------------------------------------------------
_m02_arbre="$(gitlab_api "$_m02_p/repository/tree?ref=main&recursive=true&per_page=100" 2>/dev/null)" \
  || _m02_arbre=""
for _m02_f in README.md .gitignore .gitlab-ci.yml .pre-commit-config.yaml commitlint.config.mjs \
  .releaserc.json CONTRIBUTING.md .gitlab/merge_request_templates/Default.md; do
  check_output "main contient $_m02_f" '^true$' \
    _m02_val "$_m02_arbre" "any(.[]; .path == \"$_m02_f\" and .type == \"blob\")"
done
_m02_ci="$(gitlab_api "$_m02_p/repository/files/.gitlab-ci.yml/raw?ref=main" 2>/dev/null)" || _m02_ci=""
check_output ".gitlab-ci.yml inclut les gabarits du projet plateforme/ci-templates" \
  'project:[[:space:]]*["'\'']?plateforme/ci-templates' printf '%s\n' "$_m02_ci"
check_output ".gitlab-ci.yml inclut qualite.yml et release.yml" 'qualite\.yml' printf '%s\n' "$_m02_ci"
check_output ".gitlab-ci.yml inclut release.yml" 'release\.yml' printf '%s\n' "$_m02_ci"
check_output "les gabarits sont figés sur une référence (ref: v1)" \
  'ref:[[:space:]]*["'\'']?v1["'\'']?[[:space:]]*$' printf '%s\n' "$_m02_ci"

# --- Release automatique : jeton de projet et variable CI ---------------------------
if _m02_jetons="$(gitlab_api "$_m02_p/access_tokens" 2>/dev/null)"; then
  check_output "jeton de projet bot-release actif (Maintainer, portées api et write_repository)" '^true$' \
    _m02_val "$_m02_jetons" 'any(.[]; .name == "bot-release" and .active and .revoked == false
      and .access_level == 40 and (.scopes | index("api")) and (.scopes | index("write_repository")))'
else
  skip "jeton de projet bot-release" "liste des jetons de projet illisible avec le jeton des checks"
fi
if _m02_vars="$(gitlab_api "$_m02_p/variables" 2>/dev/null)"; then
  # Seuls les attributs sont extraits : la valeur n'est ni affichée ni conservée.
  check_output "variable CI GITLAB_TOKEN protégée et masquée" '^true$' \
    _m02_val "$_m02_vars" 'any(.[]; .key == "GITLAB_TOKEN" and .protected and .masked)'
else
  skip "variable CI GITLAB_TOKEN" "variables du projet illisibles avec le jeton des checks"
fi
_m02_vars=""

# --- Le workflow a été suivi ----------------------------------------------------------
_m02_mr="$(gitlab_api "$_m02_p/merge_requests?state=merged&target_branch=main&per_page=1" 2>/dev/null)" \
  || _m02_mr=""
check_output "au moins une merge request fusionnée dans main" '^[1-9]' _m02_val "$_m02_mr" 'length'
_m02_pl="$(gitlab_api "$_m02_p/pipelines?ref=main&per_page=1" 2>/dev/null)" || _m02_pl=""
check_output "dernier pipeline de main réussi" '^success$' _m02_val "$_m02_pl" '.[0].status'

# --- Copie de travail sur adm01 ---------------------------------------------------------
check_cmd "copie de travail ~/src/outils (dépôt Git)" git -C "$_m02_clone" rev-parse --is-inside-work-tree
check_output "origin pointe vers plateforme/outils sur git01" \
  'git01\.par1\.medisphere\.internal[:/]plateforme/outils(\.git)?$' git -C "$_m02_clone" remote get-url origin
# --git-path respecte core.hooksPath s'il est défini.
for _m02_h in pre-commit commit-msg; do
  _m02_hook="$(git -C "$_m02_clone" rev-parse --path-format=absolute --git-path "hooks/$_m02_h" 2>/dev/null)" \
    || _m02_hook="/nonexistent"
  check_cmd "hook $_m02_h installé par pre-commit dans la copie de travail" grep -q 'pre-commit' "$_m02_hook"
done
