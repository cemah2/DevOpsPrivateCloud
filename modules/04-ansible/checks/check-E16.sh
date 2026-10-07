# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E16.sh — M04-E16 : Rôle gitlab_runner : reprendre runner01 en code
# À lancer depuis adm01. Lecture seule : paquets et outils sur runner01 (vus par le compte
# gitlab-runner), état du runner dans GitLab (API, jeton des checks), playbook en --check.

# shellcheck source=_m04-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-operationnel.sh"

title "M04-E16 — Rôle gitlab_runner : reprendre runner01 en code"
require_cmd git jq curl

check_cmd "roles/gitlab_runner : tasks, defaults et meta présents" _m04o_role_complet gitlab_runner
check_cmd "roles/gitlab_runner publié sur main" _m04_fichier_main roles/gitlab_runner/tasks/main.yml
check_cmd "un playbook applique gitlab_runner au groupe role_runner" \
  bash -c 'grep -rlE "gitlab_runner" "$1/playbooks" | xargs -r grep -lE "hosts:[[:space:]]*role_runner" | grep -q .' _ "$_M04_SRC"
check_cmd "le jeton du runner est dans le Vault (vault_gitlab_runner_jeton)" \
  _m04o_vault_contient '^vault_gitlab_runner_jeton:[[:space:]]*"?glrt-'
check_cmd "aucun jeton glrt- en clair dans l'historique du projet" \
  bash -c '! git -C "$1" log --all -p 2>/dev/null | grep -Eq "glrt-[A-Za-z0-9_-]{20,}"' _ "$_M04_SRC"

# --- GitLab Runner ----------------------------------------------------------------------------------
_m04o_gl="$(gitlab_api version 2>/dev/null | jq -r '.version // empty' | cut -d. -f1,2)" || true
check_ssh_output "runner01 : GitLab Runner à la même version majeure.mineure que GitLab (${_m04o_gl:-?})" runner01 \
  "^Version:[[:space:]]+${_m04o_gl:-inconnue}\." 'gitlab-runner --version'
check_ssh "runner01 : gitlab-runner et ses images d'assistance figés (hold)" runner01 \
  'h="$(apt-mark showhold)"; grep -qx gitlab-runner <<<"$h" && grep -qx gitlab-runner-helper-images <<<"$h"'
check_ssh_output "runner01 : le dépôt GitLab Runner est déclaré une seule fois" runner01 '^1$' \
  'grep -rlE "packages\.gitlab\.com/runner/gitlab-runner" /etc/apt/sources.list.d/ | wc -l'
check_ssh "runner01 : config.toml lisible par root seulement" runner01 \
  '[ "$(sudo -n stat -c %a:%U /etc/gitlab-runner/config.toml)" = "600:root" ]'
check_ssh_output "runner01 : deux jobs simultanés au plus (concurrent = 2)" runner01 '^concurrent = 2$' \
  'sudo -n grep -E "^concurrent" /etc/gitlab-runner/config.toml'
check_ssh "runner01 : service gitlab-runner actif et activé" runner01 \
  'systemctl is-active --quiet gitlab-runner && systemctl is-enabled --quiet gitlab-runner'
check_cmd "GitLab : le runner runner01-shell est en ligne" _m04o_runner_en_ligne runner01-shell
check_ssh "runner01 : le compte des jobs n'a aucun groupe privilégié" runner01 \
  '! id -nG gitlab-runner | grep -Eqw "sudo|adm|docker|root"'

# --- Outils, tels que les voient les jobs ----------------------------------------------------------------
for _m04o_o in git uv pre-commit gitleaks shellcheck shfmt jq bats task node packer; do
  check_ssh "runner01 : « $_m04o_o » visible par gitlab-runner" runner01 \
    "sudo -n -u gitlab-runner -H bash -lc 'command -v $_m04o_o' >/dev/null"
done
check_ssh_output "runner01 : ShellCheck 0.11" runner01 '^version: 0\.11\.' 'shellcheck --version'
check_ssh_output "runner01 : Node.js 24" runner01 '^v24\.' 'node --version'
check_ssh_output "runner01 : Packer 1.16" runner01 '^Packer v1\.16\.' 'packer version'
check_ssh_output "runner01 : gitleaks 8.30" runner01 '^8\.30\.' 'gitleaks version'
check_ssh "runner01 : /opt/release-tools non modifiable par les jobs" runner01 \
  'test -d /opt/release-tools/node_modules && ! sudo -n -u gitlab-runner test -w /opt/release-tools/node_modules'
check_ssh "runner01 : semantic-release et commitlint installés dans /opt/release-tools" runner01 \
  'test -x /opt/release-tools/node_modules/.bin/semantic-release && test -x /opt/release-tools/node_modules/.bin/commitlint'

# --- Idempotence -----------------------------------------------------------------------------------------
_m04o_pb="$(grep -rlE "hosts:[[:space:]]*role_runner" "$_M04_SRC/playbooks" 2>/dev/null | head -n 1)" || true
_m04o_sortie="$(_m04_simuler "${_m04o_pb#"$_M04_SRC"/}")"
check_cmd "--check du playbook du runner : aucun changement, aucun échec" _m04_recap "$_m04o_sortie" runner01
