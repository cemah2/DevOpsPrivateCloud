# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres ($1…)
#
# check-E02.sh — M04-E02 : Créer le projet plateforme/ansible et un environnement reproductible
# À lancer depuis adm01. Lecture seule : API GitLab (jeton des checks), copie de travail
# ~/src/ansible, environnement .venv (jamais resynchronisé : « uv lock --check » ne réécrit
# pas uv.lock), lecture de la configuration effective par « ansible-config ».

# shellcheck source=_m04-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-decouverte.sh"

title "M04-E02 — Créer le projet plateforme/ansible et un environnement reproductible"
require_cmd git jq curl uv python3

# _m04_val JSON FILTRE — valeur brute d'un champ (vide si absent ou JSON invalide)
_m04_val() { jq -r "$2" <<<"$1" 2>/dev/null || true; }

# --- Projet GitLab : configuration standard de la plateforme ------------------------
_m04_projet="$(gitlab_api "$_M04_PROJET" 2>/dev/null)" || _m04_projet=""
check_cmd "GitLab : le projet plateforme/ansible existe et est lisible avec le jeton des checks" \
  test -n "$_m04_projet"
check_output "projet privé" '^private$' _m04_val "$_m04_projet" '.visibility'
check_output "branche par défaut : main" '^main$' _m04_val "$_m04_projet" '.default_branch'
check_output "méthode de fusion de la plateforme (historique semi-linéaire ou fast-forward)" \
  '^(rebase_merge|ff)$' _m04_val "$_m04_projet" '.merge_method'
check_output "fusion refusée tant que le pipeline n'a pas réussi" '^true$' \
  _m04_val "$_m04_projet" '.only_allow_merge_if_pipeline_succeeds'
check_output "fusion refusée tant que des discussions restent ouvertes" '^true$' \
  _m04_val "$_m04_projet" '.only_allow_merge_if_all_discussions_are_resolved'

_m04_pb="$(gitlab_api "$_M04_PROJET/protected_branches/main" 2>/dev/null)" || _m04_pb=""
check_output "main protégée : personne ne peut y pousser directement" '^\[0\]$' \
  _m04_val "$_m04_pb" '[.push_access_levels[].access_level] | sort | tostring'
check_output "main protégée : seuls les Maintainers fusionnent" '^\[40\]$' \
  _m04_val "$_m04_pb" '[.merge_access_levels[].access_level] | sort | tostring'
check_output "main protégée : poussée forcée interdite" '^false$' _m04_val "$_m04_pb" '.allow_force_push'
_m04_pt="$(gitlab_api "$_M04_PROJET/protected_tags" 2>/dev/null)" || _m04_pt=""
check_output "étiquettes v* protégées" '^true$' _m04_val "$_m04_pt" 'any(.[]; .name == "v*")'

if _m04_jetons="$(gitlab_api "$_M04_PROJET/access_tokens" 2>/dev/null)"; then
  check_output "jeton de projet bot-release actif (Maintainer, portées api et write_repository)" '^true$' \
    _m04_val "$_m04_jetons" 'any(.[]; .name == "bot-release" and .active and .revoked == false
      and .access_level == 40 and (.scopes | index("api")) and (.scopes | index("write_repository")))'
else
  skip "jeton de projet bot-release" "liste des jetons de projet illisible avec le jeton des checks"
fi
if _m04_vars="$(gitlab_api "$_M04_PROJET/variables" 2>/dev/null)"; then
  # Seuls les attributs sont lus : la valeur n'est ni affichée ni conservée.
  check_output "variable CI GITLAB_TOKEN protégée et masquée" '^true$' \
    _m04_val "$_m04_vars" 'any(.[]; .key == "GITLAB_TOKEN" and .protected and .masked)'
else
  skip "variable CI GITLAB_TOKEN" "variables du projet illisibles avec le jeton des checks"
fi
_m04_vars=""

# --- Contenu de main -------------------------------------------------------------------
for _m04_f in README.md .gitignore .gitlab-ci.yml .pre-commit-config.yaml commitlint.config.mjs \
  .releaserc.json CONTRIBUTING.md .gitlab/merge_request_templates/Default.md \
  ansible.cfg pyproject.toml uv.lock .python-version collections/requirements.yml; do
  check_cmd "main contient $_m04_f" _m04_fichier_main "$_m04_f"
done
_m04_ci="$(gitlab_api "$_M04_PROJET/repository/files/.gitlab-ci.yml/raw?ref=main" 2>/dev/null)" || _m04_ci=""
check_output ".gitlab-ci.yml inclut les gabarits de plateforme/ci-templates figés en v1" \
  'ref:[[:space:]]*["'\'']?v1["'\'']?[[:space:]]*$' printf '%s\n' "$_m04_ci"
_m04_mr="$(gitlab_api "$_M04_PROJET/merge_requests?state=merged&target_branch=main&per_page=1" 2>/dev/null)" \
  || _m04_mr=""
check_output "au moins une merge request fusionnée dans main" '^[1-9]' _m04_val "$_m04_mr" 'length'
_m04_pl="$(gitlab_api "$_M04_PROJET/pipelines?ref=main&per_page=1" 2>/dev/null)" || _m04_pl=""
check_output "dernier pipeline de main réussi" '^success$' _m04_val "$_m04_pl" '.[0].status'

# --- Copie de travail -------------------------------------------------------------------
check_cmd "copie de travail ~/src/ansible (dépôt Git)" git -C "$_M04_SRC" rev-parse --is-inside-work-tree
check_output "origin pointe vers plateforme/ansible sur git01" \
  'git01\.par1\.medisphere\.internal[:/]plateforme/ansible(\.git)?$' git -C "$_M04_SRC" remote get-url origin
for _m04_h in pre-commit commit-msg; do
  _m04_hook="$(git -C "$_M04_SRC" rev-parse --path-format=absolute --git-path "hooks/$_m04_h" 2>/dev/null)" \
    || _m04_hook="/nonexistent"
  check_cmd "hook $_m04_h installé par pre-commit" grep -q 'pre-commit' "$_m04_hook"
done

# --- Environnement Python (uv) ----------------------------------------------------------------
# _m04_toml FILTRE_JQ — interroge pyproject.toml converti en JSON (tomllib de Python 3.13)
_m04_toml() {
  python3 -c 'import json, sys, tomllib; print(json.dumps(tomllib.load(open(sys.argv[1], "rb"))))' \
    "$_M04_SRC/pyproject.toml" 2>/dev/null | jq -r "$1" 2>/dev/null
}
check_output "pyproject.toml : ansible-core limité à la série 2.21" '^ansible-core ?(~= ?2\.21|>= ?2\.21[^,]*, ?< ?2\.22)' \
  _m04_toml '.project.dependencies[] | select(ascii_downcase | startswith("ansible-core"))'
check_output "pyproject.toml : proxmoxer >= 2.3 et requests" '^2$' \
  _m04_toml '[.project.dependencies[] | ascii_downcase | select(test("^(proxmoxer|requests)\\b"))] | length'
check_output "pyproject.toml : ansible-lint et molecule déclarés (outils de qualité)" '^2$' \
  _m04_toml '[(.project.dependencies // []), (."dependency-groups".dev // [])] | add
    | [.[] | ascii_downcase | select(test("^(ansible-lint|molecule)\\b"))] | length'
check_output "uv : Python du système uniquement (python-preference)" '^only-system$' \
  _m04_toml '.tool.uv."python-preference" // empty'
check_cmd "uv.lock à jour par rapport à pyproject.toml (uv lock --check)" \
  bash -c 'cd "$1" && uv lock --check >/dev/null 2>&1' _ "$_M04_SRC"
check_cmd "l'environnement .venv n'est pas versionné et est ignoré" \
  bash -c '[[ -z $(git -C "$1" ls-files .venv) ]] && git -C "$1" check-ignore -q .venv' _ "$_M04_SRC"
check_output "l'environnement .venv repose sur le Python de Debian (/usr/bin)" '^home = /usr/bin$' \
  cat "$_M04_SRC/.venv/pyvenv.cfg"
check_output "ansible-core 2.21 dans l'environnement du projet" '^ansible \[core 2\.21\.' \
  _m04_ans ansible --version
check_output "ansible-lint 26 dans l'environnement du projet" '^ansible-lint 26\.' \
  _m04_ans ansible-lint --version
check_output "molecule 26 dans l'environnement du projet" '^molecule 26\.' _m04_ans molecule --version

# --- Collections ----------------------------------------------------------------------------
# _m04_collection ESPACE NOM — version installée dans ./collections du projet
_m04_collection() {
  jq -r '.collection_info.version' \
    "$_M04_SRC/collections/ansible_collections/$1/$2/MANIFEST.json" 2>/dev/null
}
check_output "collection community.proxmox 2.x installée dans ./collections" '^2\.' \
  _m04_collection community proxmox
check_output "collection community.general 13.x installée dans ./collections" '^13\.' \
  _m04_collection community general
check_output "collection ansible.posix installée dans ./collections" '^[0-9]+\.' \
  _m04_collection ansible posix
check_cmd "les collections de Galaxy ne sont pas versionnées (ignorées par Git)" \
  git -C "$_M04_SRC" check-ignore -q collections/ansible_collections/community/general/MANIFEST.json
check_cmd "une future collection interne medisphere.* serait versionnée (non ignorée)" \
  bash -c '! git -C "$1" check-ignore -q collections/ansible_collections/medisphere/socle/galaxy.yml' _ "$_M04_SRC"

# --- Configuration effective d'Ansible ----------------------------------------------------------
_m04_cfg="$(_m04_ans ansible-config dump --only-changed -t all 2>/dev/null)" || _m04_cfg=""
check_output "ansible.cfg du projet utilisé quand on lance Ansible depuis sa racine" \
  "^CONFIG_FILE\(\) = $_M04_SRC/ansible\.cfg$" printf '%s\n' "$_m04_cfg"
check_output "collections cherchées dans le projet (collections_path)" \
  "^COLLECTIONS_PATHS\([^)]*\) = \['$_M04_SRC/collections'\]$" printf '%s\n' "$_m04_cfg"
check_output "inventaire du lab déclaré (inventories/lab/…)" \
  "^DEFAULT_HOST_LIST\([^)]*\) = \['$_M04_SRC/inventories/lab" printf '%s\n' "$_m04_cfg"
check_output "faits accessibles uniquement par ansible_facts (inject_facts_as_vars = False)" \
  '^INJECT_FACTS_AS_VARS\([^)]*\) = False$' printf '%s\n' "$_m04_cfg"
check_output "modules exécutés par le Python du système des hôtes (/usr/bin/python3)" \
  '^INTERPRETER_PYTHON\([^)]*\) = /usr/bin/python3$' printf '%s\n' "$_m04_cfg"
check_output "pipelining SSH activé" '^ANSIBLE_PIPELINING\([^)]*\) = True$' printf '%s\n' "$_m04_cfg"
check_cmd "vérification des clés d'hôte SSH conservée (host_key_checking non désactivé)" \
  bash -c '! grep -Eq "^HOST_KEY_CHECKING\([^)]*\) = False$" <<<"$1"' _ "$_m04_cfg"
check_cmd "ansible-config validate -t all : aucune clé inconnue" _m04_ans ansible-config validate -t all
_m04_ping="$(_m04_json ansible adm01 -m ansible.builtin.ping)"
check_output "Ansible s'exécute localement sur adm01 (ping de l'inventaire minimal)" '^pong$' \
  _m04_resultat "$_m04_ping" adm01 '.ping // empty'
