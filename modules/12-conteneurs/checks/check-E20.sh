# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # gabarits Go, filtres jq et commandes entre apostrophes
#
# check-E20.sh — M12-E20 : Un runner GitLab à exécuteur Docker
# À lancer depuis adm01. Lecture seule : qm config sur pve01, NetBox et GitLab en GET, DNS ; sur
# runner02 : docker version, systemctl is-active, lecture de config.toml (sudo), id.

# shellcheck source=_m12-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-operationnel.sh"

title "M12-E20 — Un runner GitLab à exécuteur Docker"
require_cmd jq dig

# --- 1. La VM du socle ------------------------------------------------------------------------------------
_m12o_e20_qm="$(_m12o_ssh "$WB_PVE_HOST" 'qm config 1012')"
check_cmd "Proxmox : VM 1012 runner02, étiquettes socle et role-runner" \
  bash -c 'grep -q "^name: runner02$" <<<"$1" && t="$(sed -n "s/^tags: //p" <<<"$1")" && grep -Eq "(^|;)socle(;|$)" <<<"$t" && grep -Eq "(^|;)role-runner(;|$)" <<<"$t"' _ "$_m12o_e20_qm"
check_cmd "Proxmox : runner02 démarre avec l'hyperviseur (onboot), 4 Go" \
  bash -c 'grep -q "^onboot: 1" <<<"$1" && grep -q "^memory: 4096" <<<"$1"' _ "$_m12o_e20_qm"
_m12o_e20_nb() {
  netbox_api "virtualization/virtual-machines/?name=runner02" \
    | jq -e '.count == 1 and .results[0].status.value == "active" and (.results[0].primary_ip4.address // "" | startswith("10.10.20.17/"))' >/dev/null
}
check_cmd "NetBox : runner02 actif, adresse primaire 10.10.20.17" _m12o_e20_nb
check_dns "DNS : runner02.par1.medisphere.internal → 10.10.20.17" "runner02.$_M12O_DOMAINE" A '^10\.10\.20\.17$' 10.10.20.10

# --- 2. L'hôte -------------------------------------------------------------------------------------------------
check_output "runner02 : Docker Engine 29.8" '^29\.8\.' _m12o_ssh "$_M12O_RUNNER02" "sudo -n docker version --format '{{.Server.Version}}'"
check_ssh "runner02 : service gitlab-runner actif" "$_M12O_RUNNER02" 'systemctl is-active -q gitlab-runner'
check_cmd "runner02 : le compte gitlab-runner n'est pas dans le groupe docker" \
  bash -c '[ -n "$1" ] && ! grep -qw docker <<<"$1"' _ "$(_m12o_ssh "$_M12O_RUNNER02" 'id -nG gitlab-runner')"
check_output "runner02 : config.toml en 600, propriété de root" '^600 root$' \
  _m12o_ssh "$_M12O_RUNNER02" 'sudo -n stat -c "%a %U" /etc/gitlab-runner/config.toml'
_m12o_e20_conf="$(_m12o_ssh "$_M12O_RUNNER02" 'sudo -n cat /etc/gitlab-runner/config.toml')"
check_cmd "config.toml : exécuteur docker" _m12o_correspond "$_m12o_e20_conf" '^\s*executor\s*=\s*"docker"'
check_cmd "config.toml : privileged = false, et aucun runner privilégié" \
  bash -c 'grep -Eq "^\s*privileged\s*=\s*false" <<<"$1" && ! grep -Eq "^\s*privileged\s*=\s*true" <<<"$1"' _ "$_m12o_e20_conf"
check_cmd "config.toml : image par défaut épinglée par empreinte" _m12o_correspond "$_m12o_e20_conf" '^\s*image\s*=\s*"[^"]+@sha256:[0-9a-f]{64}"'
check_cmd "config.toml : politique de tirage définie, sans « never » seule" \
  bash -c 'grep -Eq "^\s*pull_policy\s*=" <<<"$1" && ! grep -Eq "^\s*pull_policy\s*=\s*\[\s*\"never\"\s*\]" <<<"$1"' _ "$_m12o_e20_conf"
check_cmd "config.toml : mémoire des jobs bornée" _m12o_correspond "$_m12o_e20_conf" '^\s*memory\s*=\s*"[0-9]+[kmgKMG]?b?"'
check_cmd "config.toml : socket du démon jamais monté dans les jobs" _m12o_absent "$_m12o_e20_conf" 'docker\.sock'

# --- 3. GitLab et la bordure -------------------------------------------------------------------------------------
_m12o_e20_runner() {
  gitlab_api "runners/all?tag_list=docker&per_page=100" \
    | jq -e '[.[] | select(.online == true or .status == "online")] | length >= 1' >/dev/null
}
check_cmd "GitLab : un runner d'étiquette docker en ligne" _m12o_e20_runner
check_cmd "plateforme/ansible (main) : matrice des flux, runner02 → ctr01:5000" \
  bash -c 'grep -Eq "RUNNER02|10\.10\.20\.17" <<<"$1" && grep -Eq "5000" <<<"$1"' _ "$(_m12o_fichier plateforme/ansible inventories/lab/group_vars/role_routeur/pare_feu.yml)"
