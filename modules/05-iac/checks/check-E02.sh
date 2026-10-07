# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres ($1…)
#
# check-E02.sh — M05-E02 : Installer OpenTofu et créer le projet plateforme/infra
# À lancer depuis adm01. Lecture seule : paquets et sources APT d'adm01, API GitLab (jeton
# des checks), copie de travail ~/src/infra (git check-ignore, sans rien modifier).

# shellcheck source=_m05-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-decouverte.sh"

title "M05-E02 — Installer OpenTofu et créer le projet plateforme/infra"
require_cmd git jq curl gpg tofu

# --- OpenTofu sur adm01 ---------------------------------------------------------------------
check_output "tofu version : série 1.13" '^1\.13\.[0-9]+$' \
  bash -c 'tofu version -json 2>/dev/null | jq -r .terraform_version'
check_output "paquet Debian « tofu » installé en 1.13.x" '^1\.13\.[0-9]+' \
  dpkg-query -W -f='${Version}' tofu
_m05_politique="$(apt-cache policy tofu 2>/dev/null)" || _m05_politique=""
check_output "le paquet installé vient de packages.opentofu.org" 'packages\.opentofu\.org/opentofu/tofu' \
  awk '/\*\*\*/ { trouve = 1; next } trouve && /^[[:space:]]+[0-9]+ / { print; exit }' <<<"$_m05_politique"
# Version installée (ligne « *** ») avec une priorité > 500 : seule une préférence APT la donne.
check_output "série épinglée par une préférence APT (priorité de la version installée > 500)" '^ok$' \
  awk '$1 == "***" { print ($3 > 500 ? "ok" : "non"); exit }' <<<"$_m05_politique"
check_cmd "préférence APT qui limite tofu à la série 1.13 (/etc/apt/preferences.d/)" \
  bash -c 'grep -rEqs "^Pin:[[:space:]]*version[[:space:]]+1\.13" /etc/apt/preferences.d/ \
    && grep -rEqs "^Package:.*\btofu\b" /etc/apt/preferences.d/'
check_cmd "dépôt OpenTofu déclaré avec des clés limitées à ce dépôt (signed-by / Signed-By)" \
  bash -c 'grep -rhEis "packages\.opentofu\.org/opentofu/tofu" /etc/apt/sources.list.d/ | grep -qi "signed-by" \
    || grep -rlEis "packages\.opentofu\.org/opentofu/tofu" /etc/apt/sources.list.d/*.sources 2>/dev/null \
       | xargs -r grep -qi "^Signed-By:"'
# Une clé d'OpenTofu dans le trousseau global signerait n'importe quel paquet.
check_cmd "aucune clé d'OpenTofu dans le trousseau APT global (trusted.gpg, trusted.gpg.d)" \
  bash -c '! { for f in /etc/apt/trusted.gpg /etc/apt/trusted.gpg.d/*; do [ -e "$f" ] || continue;
      gpg --show-keys --with-colons "$f" 2>/dev/null; done \
    | grep -Eq "^fpr:+(E3E6E43D84CB852EADB0051D0C0AF313E5FD9F80|F4AF70F66EAC4337EEECC97407D3DFCD4C61499F):"; }'
check_cmd "cache des providers configuré dans ~/.tofurc, et son dossier existe" \
  bash -c 'd="$(sed -nE "s/^[[:space:]]*plugin_cache_dir[[:space:]]*=[[:space:]]*\"([^\"]+)\".*/\1/p" ~/.tofurc 2>/dev/null | head -n1)";
    d="${d//\$HOME/$HOME}"; [ -n "$d" ] && [ -d "$d" ]'

# --- Projet GitLab : configuration standard, sans publication de versions --------------------
_m05_projet="$(gitlab_api "$_M05_PROJET" 2>/dev/null)" || _m05_projet=""
check_cmd "GitLab : le projet plateforme/infra existe et est lisible avec le jeton des checks" \
  test -n "$_m05_projet"
check_output "projet privé" '^private$' _m05_val "$_m05_projet" '.visibility'
check_output "branche par défaut : main" '^main$' _m05_val "$_m05_projet" '.default_branch'
check_output "méthode de fusion de la plateforme (historique semi-linéaire ou fast-forward)" \
  '^(rebase_merge|ff)$' _m05_val "$_m05_projet" '.merge_method'
check_output "fusion refusée tant que le pipeline n'a pas réussi" '^true$' \
  _m05_val "$_m05_projet" '.only_allow_merge_if_pipeline_succeeds'
check_output "fusion refusée tant que des discussions restent ouvertes" '^true$' \
  _m05_val "$_m05_projet" '.only_allow_merge_if_all_discussions_are_resolved'
_m05_pb="$(gitlab_api "$_M05_PROJET/protected_branches/main" 2>/dev/null)" || _m05_pb=""
check_output "main protégée : personne ne peut y pousser directement" '^\[0\]$' \
  _m05_val "$_m05_pb" '[.push_access_levels[].access_level] | sort | tostring'
check_output "main protégée : seuls les Maintainers fusionnent" '^\[40\]$' \
  _m05_val "$_m05_pb" '[.merge_access_levels[].access_level] | sort | tostring'
check_output "main protégée : poussée forcée interdite" '^false$' _m05_val "$_m05_pb" '.allow_force_push'

if _m05_jetons="$(gitlab_api "$_M05_PROJET/access_tokens" 2>/dev/null)"; then
  check_output "aucun jeton de publication (bot-release) actif : ce projet ne publie pas de versions" '^false$' \
    _m05_val "$_m05_jetons" 'any(.[]; .name == "bot-release" and .active and (.revoked | not))'
else
  skip "jeton de projet bot-release" "liste des jetons de projet illisible avec le jeton des checks"
fi
if _m05_vars="$(gitlab_api "$_M05_PROJET/variables" 2>/dev/null)"; then
  # Seuls les noms sont lus : aucune valeur n'est affichée ni conservée.
  check_output "aucune variable CI GITLAB_TOKEN (secret sans usage)" '^false$' \
    _m05_val "$_m05_vars" 'any(.[]; .key == "GITLAB_TOKEN")'
else
  skip "variable CI GITLAB_TOKEN" "variables du projet illisibles avec le jeton des checks"
fi
_m05_vars=""

# --- Contenu de main ---------------------------------------------------------------------------
for _m05_f in README.md .gitignore .gitlab-ci.yml .pre-commit-config.yaml commitlint.config.mjs \
  .gitleaks.toml CONTRIBUTING.md .gitlab/merge_request_templates/Default.md envs/lab-m05/README.md; do
  check_cmd "main contient $_m05_f" _m05_fichier_main "$_m05_f"
done
_m05_absent_main() { ! _m05_fichier_main "$1"; }
check_cmd "main ne contient pas .releaserc.json (pas de semantic-release ici)" _m05_absent_main .releaserc.json
_m05_ci="$(_m05_brut_main .gitlab-ci.yml)"
check_output ".gitlab-ci.yml inclut plateforme/ci-templates figé en v1" \
  'ref:[[:space:]]*["'\'']?v1["'\'']?[[:space:]]*$' printf '%s\n' "$_m05_ci"
check_output ".gitlab-ci.yml inclut le gabarit qualite.yml" 'templates/qualite\.yml' printf '%s\n' "$_m05_ci"
check_cmd ".gitlab-ci.yml n'inclut pas le gabarit release.yml" \
  bash -c '! grep -Eq "^[^#]*templates/release\.yml" <<<"$1"' _ "$_m05_ci"
_m05_mr="$(gitlab_api "$_M05_PROJET/merge_requests?state=merged&target_branch=main&per_page=1" 2>/dev/null)" \
  || _m05_mr=""
check_output "au moins une merge request fusionnée dans main" '^[1-9]' _m05_val "$_m05_mr" 'length'
# Pipelines de push sur main seulement (les pipelines planifiés de E28/E29 ne comptent pas) ;
# « manual » = réussi, avec des jobs apply manuels non lancés (E26).
_m05_pl="$(gitlab_api "$_M05_PROJET/pipelines?ref=main&source=push&per_page=1" 2>/dev/null)" || _m05_pl=""
check_output "dernier pipeline de main réussi" '^(success|manual)$' _m05_val "$_m05_pl" '.[0].status'

# --- Copie de travail et .gitignore --------------------------------------------------------------
check_cmd "copie de travail ~/src/infra (dépôt Git)" git -C "$_M05_SRC" rev-parse --is-inside-work-tree
check_output "origin pointe vers plateforme/infra sur git01" \
  'git01\.par1\.medisphere\.internal[:/]plateforme/infra(\.git)?$' git -C "$_M05_SRC" remote get-url origin
for _m05_h in pre-commit commit-msg; do
  _m05_hook="$(git -C "$_M05_SRC" rev-parse --path-format=absolute --git-path "hooks/$_m05_h" 2>/dev/null)" \
    || _m05_hook="/nonexistent"
  check_cmd "hook $_m05_h installé par pre-commit" grep -q 'pre-commit' "$_m05_hook"
done
# --no-index : on teste les RÈGLES, que le fichier existe, soit suivi ou non.
for _m05_f in envs/lab-m05/terraform.tfstate envs/lab-m05/terraform.tfstate.backup \
  envs/lab-m05/.terraform/providers envs/lab-m05/essai.tfplan envs/lab-m05/.terraform.tfstate.lock.info \
  envs/lab-m05/crash.log; do
  check_cmd ".gitignore : $_m05_f est ignoré" git -C "$_M05_SRC" check-ignore -q --no-index "$_m05_f"
done
for _m05_f in envs/lab-m05/.terraform.lock.hcl envs/lab-m05/terraform.tfvars envs/lab-m05/main.tf; do
  check_cmd ".gitignore : $_m05_f reste versionnable" \
    bash -c '! git -C "$1" check-ignore -q --no-index "$2"' _ "$_M05_SRC" "$_m05_f"
done
