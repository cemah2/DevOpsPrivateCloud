# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur pve01 ou par bash -c
#
# check-E46.sh — M02-E46 « Mini-projet : outillage MédiSphère v1 »
# Contrôle global de la livraison de plateforme/outils (à lancer depuis adm01). Lecture seule :
# API GitLab en GET (jeton des checks), systemctl show, lecture des clones, pvesh en lecture.
# Les contrôles détaillés de chaque brique restent dans leurs exercices.

title "M02-E46 — Outillage MédiSphère v1 : contrôle global"
require_cmd git jq curl ssh

_m02_e46_proj="plateforme%2Foutils"
_m02_e46_outils="${WB_SRC:-$HOME/src}/outils"
_m02_e46_depot="${WB_DEPOT:-$HOME/medisphere}"
_m02_e46_version=""

# --- 1. Forge, release et paquet -----------------------------------------------------
title "1/7 Release et paquet (GitLab)"

_m02_e46_main_protegee() {
  gitlab_api "projects/$_m02_e46_proj/protected_branches/main" | jq -e '.push_access_levels | all(.access_level == 0)' >/dev/null
}

# Dernière release ≥ 1.0.0 ; mémorise sa version pour les contrôles suivants.
_m02_e46_release() {
  local tag
  tag="$(gitlab_api "projects/$_m02_e46_proj/releases?per_page=1" | jq -r '.[0].tag_name // ""')"
  [[ "$tag" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || return 1
  ((BASH_REMATCH[1] >= 1)) || return 1
  _m02_e46_version="${tag#v}"
}

_m02_e46_paquet() {
  [[ -n "$_m02_e46_version" ]] || return 1
  gitlab_api "projects/$_m02_e46_proj/packages?package_type=pypi&package_name=medictl&per_page=100" \
    | jq -e --arg v "$_m02_e46_version" 'any(.[]; .name == "medictl" and .version == $v)' >/dev/null
}

_m02_e46_pipeline_main() {
  local id
  id="$(gitlab_api "projects/$_m02_e46_proj/pipelines?ref=main&per_page=1" | jq -r '.[0] | select(.status == "success") | .id')"
  [[ -n "$id" ]] || return 1
  printf '%s\n' "$id"
}

_m02_e46_couverture() {
  local id
  id="$(_m02_e46_pipeline_main)" || return 1
  gitlab_api "projects/$_m02_e46_proj/pipelines/$id" | jq -e '(.coverage // "") | tostring | test("^[0-9]")' >/dev/null
}

_m02_e46_rapport_tests() {
  local id
  id="$(_m02_e46_pipeline_main)" || return 1
  gitlab_api "projects/$_m02_e46_proj/pipelines/$id/test_report" | jq -e '.total_count > 0 and .failed_count == 0 and (.error_count // 0) == 0' >/dev/null
}

check_cmd "plateforme/outils : main protégée (aucun push direct)" _m02_e46_main_protegee
check_cmd "plateforme/outils : dernière release en version ≥ 1.0.0 (étiquette vX.Y.Z)" _m02_e46_release
printf '         (version publiée : %s)\n' "${_m02_e46_version:-?}"
check_cmd "registre PyPI du projet : paquet medictl de cette version publié" _m02_e46_paquet
check_cmd "dernier pipeline de main réussi" _m02_e46_pipeline_main
check_cmd "dernier pipeline de main : rapport de tests JUnit présent, sans échec" _m02_e46_rapport_tests
check_cmd "dernier pipeline de main : couverture de tests mesurée" _m02_e46_couverture

# --- 2. medictl sur adm01 ----------------------------------------------------------------
title "2/7 medictl installé sur adm01"

_m02_e46_depuis_registre() {
  local r
  r="$(uv tool dir 2>/dev/null)/medictl/uv-receipt.toml"
  grep -q 'packages/pypi' "$r" 2>/dev/null
}

_m02_e46_version_medictl() {
  [[ -n "$_m02_e46_version" ]] && medictl --version 2>&1 | grep -qF -- "$_m02_e46_version"
}

if command -v uv >/dev/null 2>&1; then
  check_cmd "medictl installé par uv tool depuis le registre de paquets de GitLab" _m02_e46_depuis_registre
else
  skip "medictl installé par uv tool" "uv absent de ce poste"
fi
check_cmd "medictl --version = version de la dernière release" _m02_e46_version_medictl
check_cmd "medictl vm list --pool lab répond (API Proxmox)" \
  bash -c 'medictl vm list --pool lab --format json 2>/dev/null | jq -e "length > 0" >/dev/null'

# --- 3. Qualité du code (clone local) -----------------------------------------------------
title "3/7 Scripts, tests et tâches (clone $_m02_e46_outils)"

_m02_e46_scripts() { find "$_m02_e46_outils/bin" -maxdepth 1 -type f -name 'ms-*' 2>/dev/null | sort; }

_m02_e46_shellcheck() {
  local -a s
  mapfile -t s < <(_m02_e46_scripts)
  ((${#s[@]} > 0)) && (cd "$_m02_e46_outils" && shellcheck -x "${s[@]}" lib/*.sh)
}

# Chaque script bin/ms-* est cité par au moins un fichier de tests bats.
_m02_e46_bats_couvre() {
  local f
  while IFS= read -r f; do
    grep -lqF -- "$(basename "$f")" "$_m02_e46_outils"/tests/bats/*.bats 2>/dev/null || return 1
  done < <(_m02_e46_scripts)
}

_m02_e46_taches() {
  local t
  for t in lint test build install; do
    grep -Eq "^  $t:" "$_m02_e46_outils/Taskfile.yml" 2>/dev/null || return 1
  done
}

check_cmd "clone de plateforme/outils présent" git -C "$_m02_e46_outils" rev-parse --is-inside-work-tree
check_cmd "au moins 3 scripts bin/ms-*" bash -c '[ "$(find "$1/bin" -maxdepth 1 -type f -name "ms-*" | wc -l)" -ge 3 ]' _ "$_m02_e46_outils"
if command -v shellcheck >/dev/null 2>&1; then
  check_cmd "bin/ms-* et lib/*.sh : ShellCheck sans remarque" _m02_e46_shellcheck
else
  skip "ShellCheck des scripts" "shellcheck absent de ce poste"
fi
check_cmd "chaque bin/ms-* est couvert par des tests bats" _m02_e46_bats_couvre
check_cmd "tests pytest présents (tests/python/test_*.py)" \
  bash -c 'ls "$1"/tests/python/test_*.py >/dev/null 2>&1' _ "$_m02_e46_outils"
check_cmd "Taskfile.yml : tâches lint, test, build et install" _m02_e46_taches
check_cmd "pyproject.toml et uv.lock versionnés" \
  git -C "$_m02_e46_outils" ls-files --error-unmatch pyproject.toml uv.lock

# --- 4. Contrôle planifié des sauvegardes ---------------------------------------------------
title "4/7 Contrôle planifié des sauvegardes"
check_cmd "timer ms-verif-sauvegardes actif et activé" \
  bash -c 'systemctl is-active -q ms-verif-sauvegardes.timer && systemctl is-enabled -q ms-verif-sauvegardes.timer'
check_output "dernier passage du contrôle réussi" '^success$' \
  systemctl show ms-verif-sauvegardes.service -p Result --value
check_output "le service déclare une notification d'échec (OnFailure=)" '[a-z]' \
  systemctl show ms-verif-sauvegardes.service -p OnFailure --value

# --- 5. Documentation ------------------------------------------------------------------------
title "5/7 Documentation"
check_cmd "README.md du projet outils" test -s "$_m02_e46_outils/README.md"
check_cmd "guide d'astreinte des outils dans docs/" \
  bash -c 'ls "$1"/docs/*astreinte* >/dev/null 2>&1' _ "$_m02_e46_outils"
check_cmd "ADR-0020 dans docs/socle/adr/ de plateforme/medisphere" \
  bash -c 'ls "$1"/docs/socle/adr/ADR-0020*.md >/dev/null 2>&1' _ "$_m02_e46_depot"

# L'inventaire du socle cite chaque VM étiquetée « socle » du pool lab.
_m02_e46_inventaire() {
  local ids id f="$_m02_e46_depot/docs/socle/inventaire.md"
  [[ -s "$f" ]] || return 1
  ids="$(remote "$WB_PVE_HOST" 'pvesh get /cluster/resources --type vm --output-format json' \
    | jq -r '.[] | select(.pool == "lab" and ((.tags // "") | split(";") | index("socle"))) | .vmid')" || return 1
  [[ -n "$ids" ]] || return 1
  for id in $ids; do
    grep -Eq "(^|[^0-9])${id}([^0-9]|\$)" "$f" || return 1
  done
}
check_cmd "inventaire du socle à jour (toutes les VMs étiquetées socle y figurent)" _m02_e46_inventaire
check_cmd "dépôt de documentation : inventaire commité, sans modification en attente" \
  bash -c 'cd "$1" && git ls-files --error-unmatch docs/socle/inventaire.md >/dev/null 2>&1 && [ -z "$(git status --porcelain -- docs/socle)" ]' _ "$_m02_e46_depot"

# --- 6. Hygiène du lab ------------------------------------------------------------------------
title "6/7 Hygiène du lab"
check_cmd "aucune panne M02 encore active (lab/bin/break)" \
  bash -c '! ls "${XDG_STATE_HOME:-$HOME/.local/state}"/workbook/pannes-actives/M02-E* >/dev/null 2>&1'
check_ssh "aucune VM d'exercice du module oubliée (VMID 2020-2029)" "$WB_PVE_HOST" \
  '! qm list | awk "NR>1 {print \$1}" | grep -Eq "^202[0-9]$"'

# --- 7. Secrets -------------------------------------------------------------------------------
title "7/7 Secrets"
check_cmd "aucun secret évident dans le dépôt outils (jeton Proxmox, jeton GitLab, clé privée)" \
  bash -c 'cd "$1" && ! git grep -nIE "(PVEAPIToken=[^ ]*=[0-9a-f]{8}-|PVE_TOKEN_SECRET *= *\"?[0-9a-f]{8}-[0-9a-f]{4}|glpat-[A-Za-z0-9_-]{20}|BEGIN [A-Z ]*PRIVATE KEY)" >/dev/null' _ "$_m02_e46_outils"
check_cmd "fichiers de secrets de ~/.config/workbook en mode 600" \
  bash -c '! find "$HOME/.config/workbook" -maxdepth 1 -type f \( -name "*.env" -o -name "*.token" \) ! -perm 600 | grep -q .'
