# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur pve01 ou par bash -c
#
# check-E46.sh — M04-E46 « Mini-projet : le socle en configuration as code »
# Contrôle global de la livraison de plateforme/ansible (à lancer depuis adm01). Lecture seule :
# API GitLab en GET (jeton des checks), ansible-inventory, ansible-lint, ansible-playbook --check
# (aucune modification des hôtes), lecture des clones, qm en lecture sur pve01.
# Durée : quelques minutes (passage --check complet de site.yml).

# shellcheck source=_m04-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-expert.sh"

title "M04-E46 — Le socle en configuration as code : contrôle global"
require_cmd git jq curl ssh

_m04_e46_proj="plateforme%2Fansible"
_m04_e46_depot="${WB_DEPOT:-$HOME/medisphere}"
_m04_e46_doc="$_m04_e46_depot/docs/socle"

# --- 1. Forge : protections, pipeline, planification, version ---------------------------
title "1/7 Forge (plateforme/ansible)"

_m04_e46_main_protegee() {
  gitlab_api "projects/$_m04_e46_proj/protected_branches/main" | jq -e '.push_access_levels | all(.access_level == 0)' >/dev/null
}
_m04_e46_pipeline_main() {
  gitlab_api "projects/$_m04_e46_proj/pipelines?ref=main&per_page=1" | jq -r '.[0] | select(.status == "success") | .id'
}
# Le dernier pipeline réussi de main propose la vérification du socle et l'application (manuelle).
_m04_e46_jobs_main() {
  local id j
  id="$(_m04_e46_pipeline_main)"
  [[ -n "$id" ]] || return 1
  j="$(gitlab_api "projects/$_m04_e46_proj/pipelines/$id/jobs?per_page=100")" || return 1
  jq -e '[.[].name] as $n | ($n | index("check-socle")) and ($n | index("appliquer"))' >/dev/null <<<"$j"
}
# Les jobs de lint et de Molecule (déclenchés par les changements des rôles) ont réussi récemment.
_m04_e46_jobs_tests() {
  local j
  j="$(gitlab_api "projects/$_m04_e46_proj/jobs?scope%5B%5D=success&per_page=100")" || return 1
  jq -e '[.[].name] as $n | ($n | any(test("lint"))) and ($n | any(test("^molecule:")))' >/dev/null <<<"$j"
}
_m04_e46_planif() {
  gitlab_api "projects/$_m04_e46_proj/pipeline_schedules?scope=active" | jq -e 'length > 0' >/dev/null
}
_m04_e46_planif_verte() {
  gitlab_api "projects/$_m04_e46_proj/pipelines?source=schedule&per_page=1" | jq -e '.[0].status == "success"' >/dev/null
}
_m04_e46_version() {
  gitlab_api "projects/$_m04_e46_proj/releases?per_page=1" | jq -e '.[0].tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$")' >/dev/null
}

check_cmd "main protégée (aucun push direct)" _m04_e46_main_protegee
check_cmd "dernier pipeline de main réussi" bash -c '[ -n "$1" ]' _ "$(_m04_e46_pipeline_main 2>/dev/null || true)"
check_cmd "dernier pipeline de main : check-socle et appliquer présents" _m04_e46_jobs_main
check_cmd "jobs ansible-lint et molecule:<scénario> réussis récemment (100 derniers jobs réussis)" _m04_e46_jobs_tests
check_cmd "contrôle de dérive planifié (planification active)" _m04_e46_planif
check_cmd "dernier pipeline planifié réussi" _m04_e46_planif_verte
check_cmd "version publiée (release vX.Y.Z)" _m04_e46_version

# --- 2. Projet et qualité -----------------------------------------------------------------
title "2/7 Projet ($_m04x_src)"

_m04_e46_propre() { [[ -z "$(git -C "$_m04x_src" status --porcelain 2>/dev/null)" ]]; }
# La copie de travail est sur le dernier commit de main de la forge (comparaison par l'API, sans fetch).
_m04_e46_a_jour() {
  local distant
  distant="$(gitlab_api "projects/$_m04_e46_proj/repository/branches/main" | jq -r '.commit.id // empty')" || return 1
  [[ -n "$distant" && "$(git -C "$_m04x_src" rev-parse HEAD)" == "$distant" ]]
}
_m04_e46_roles() {
  local r
  for r in base ssh_durci pare_feu gitlab_runner dnsmasq; do
    [[ -f "$_m04x_src/roles/$r/tasks/main.yml" ]] || return 1
  done
}
_m04_e46_molecule() {
  [[ "$(find "$_m04x_src/roles" "$_m04x_src/molecule" -name molecule.yml 2>/dev/null | wc -l)" -ge 3 ]]
}
_m04_e46_lint() { (cd "$_m04x_src" && _m04x_ansible ansible-lint >/dev/null 2>&1); }

check_cmd "copie de travail propre" _m04_e46_propre
check_cmd "copie de travail sur le dernier commit de main (forge)" _m04_e46_a_jour
check_cmd "rôles base, ssh_durci, pare_feu, gitlab_runner et dnsmasq présents" _m04_e46_roles
check_cmd "au moins 3 scénarios Molecule" _m04_e46_molecule
check_cmd "ansible-lint passe sur tout le projet" _m04_e46_lint

# --- 3. Inventaire ------------------------------------------------------------------------
title "3/7 Inventaire"

_m04_e46_dyn="$(_m04x_ansible ansible-inventory -i inventories/lab/proxmox.yml --list 2>/dev/null)" || _m04_e46_dyn='{}'
_m04_e46_socle_dyn() {
  local h
  for h in gw01 adm01 dns01 git01 runner01; do
    _m04x_hotes_groupe "$_m04_e46_dyn" socle | grep -qx "$h" || return 1
  done
}
_m04_e46_strict() {
  local d
  d="$(_m04x_ansible ansible-config dump --only-changed 2>/dev/null)" || return 1
  grep -Eq '^INVENTORY_(ANY_)?UNPARSED_IS_FAILED\(.*\) = True$' <<<"$d"
}
_m04_e46_garde_fou() { grep -Eq "groups\[['\"]socle['\"]\]" "$_m04x_src/playbooks/site.yml" 2>/dev/null; }

check_cmd "inventaire dynamique : les cinq hôtes dans socle" _m04_e46_socle_dyn
check_cmd "une source d'inventaire illisible fait échouer (unparsed_is_failed / any_unparsed_is_failed)" _m04_e46_strict
check_cmd "site.yml : garde-fou sur le contenu du groupe socle" _m04_e46_garde_fou

# --- 4. Convergence ---------------------------------------------------------------------------
title "4/7 Convergence (site.yml --check, plusieurs minutes)"

_m04_e46_recap="$(_m04x_ansible ansible-playbook playbooks/site.yml --check 2>&1 | sed -n '/^PLAY RECAP/,$p')" || _m04_e46_recap=""
_m04_e46_converge() {
  local h
  for h in gw01 adm01 dns01 git01 runner01; do
    grep -Eq "^${h}[[:space:]]+:.*changed=0[[:space:]]+unreachable=0[[:space:]]+failed=0" <<<"$_m04_e46_recap" || return 1
  done
}
check_cmd "site.yml --check : les cinq hôtes joints, changed=0, failed=0" _m04_e46_converge

# --- 5. Secrets --------------------------------------------------------------------------------
title "5/7 Secrets"

_m04_e46_vault_chiffre() {
  head -n 1 "$_m04x_src/$_m04x_vault" 2>/dev/null | grep -q '^\$ANSIBLE_VAULT;' \
    && git -C "$_m04x_src" ls-files --error-unmatch "$_m04x_vault" >/dev/null 2>&1
}
# Aucune variable vault_* en clair dans l'inventaire (les fichiers chiffrés ne montrent rien).
_m04_e46_pas_de_clair() { ! grep -rEq '^vault_[a-z0-9_]+:' "$_m04x_src/inventories" 2>/dev/null; }
_m04_e46_pas_de_secret() {
  ! git -C "$_m04x_src" grep -nIE "(PVEAPIToken=[^ ]*=[0-9a-f]{8}-|TOKEN_SECRET *[=:] *\"?[0-9a-f]{8}-[0-9a-f]{4}|glpat-[A-Za-z0-9_-]{20}|glrt-[A-Za-z0-9_-]{20}|BEGIN [A-Z ]*PRIVATE KEY)" >/dev/null
}

check_cmd "group_vars/all/vault.yml chiffré et versionné" _m04_e46_vault_chiffre
check_cmd "aucune variable vault_* en clair dans l'inventaire" _m04_e46_pas_de_clair
check_cmd "aucun secret évident dans le dépôt (jeton Proxmox ou GitLab, clé privée)" _m04_e46_pas_de_secret
check_cmd "registre des secrets : jeton wb-ansible et coffre Ansible inscrits" \
  bash -c 'grep -q "wb-ansible" "$1" && grep -qi "vault" "$1"' _ "$_m04_e46_doc/registre-secrets.md"

# --- 6. Documentation -----------------------------------------------------------------------------
title "6/7 Documentation (plateforme/medisphere)"
check_cmd "docs/socle/configuration.md présent" test -s "$_m04_e46_doc/configuration.md"
check_cmd "ADR-0040 présent" bash -c 'ls "$1"/adr/ADR-0040*.md >/dev/null 2>&1' _ "$_m04_e46_doc"
check_cmd "RB-040 présent" bash -c 'ls "$1"/runbooks/RB-040*.md >/dev/null 2>&1' _ "$_m04_e46_doc"
check_cmd "matrice des flux : accès SSH de runner01 (CI Ansible) documenté" \
  bash -c 'grep -E "runner01" "$1" | grep -Eq "(^|[^0-9])22([^0-9]|$)"' _ "$_m04_e46_doc/matrice-flux.md"
check_cmd "dépôt de documentation : rien en attente de commit dans docs/socle" \
  bash -c 'cd "$1" && [ -z "$(git status --porcelain -- docs/socle)" ]' _ "$_m04_e46_depot"

# --- 7. Hygiène -------------------------------------------------------------------------------------
title "7/7 Hygiène du lab"
check_cmd "aucune panne M04 encore active (lab/bin/break)" _m04x_aucune_panne_active
check_ssh "aucune VM d'environnement du module (2040-2049, dont sem01) restante" "$WB_PVE_HOST" \
  '! qm list | awk "NR>1 {print \$1}" | grep -Eq "^204[0-9]$"'
check_cmd "pas de copie de rôle dans playbooks/roles/" bash -c '[ ! -d "$1/playbooks/roles" ]' _ "$_m04x_src"
check_cmd "fichiers de secrets de ~/.config/workbook en mode 600" \
  bash -c '! find "$HOME/.config/workbook" -maxdepth 1 -type f ! -perm 600 | grep -q .'
