# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # gabarits Go et commandes entre apostrophes : évalués à distance
#
# check-E18.sh — M12-E18 : Journaux, ressources et santé des conteneurs
# À lancer depuis adm01. Lecture seule : daemon.json et docker inspect sur ctr01 ; fichier Quadlet et
# état de l'API sous le compte app de ctr02 ; API GitLab en GET.

# shellcheck source=_m12-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-operationnel.sh"

title "M12-E18 — Journaux, ressources et santé des conteneurs"
require_cmd jq

# --- 1. Journaux ---------------------------------------------------------------------------------------------
_m12o_e18_daemon="$(_m12o_ssh "$_M12O_CTR01" 'cat /etc/docker/daemon.json')"
check_cmd "ctr01 : daemon.json — json-file avec max-size et compress" _m12o_json "$_m12o_e18_daemon" \
  '."log-driver" == "json-file" and (."log-opts"."max-size" // "") != "" and (."log-opts".compress // "") == "true"'
check_output "m12-e18-local : pilote de journaux local" '^local$' _m12o_docker "inspect --format '{{.HostConfig.LogConfig.Type}}' m12-e18-local"
check_output "m12-e18-journald : pilote de journaux journald" '^journald$' _m12o_docker "inspect --format '{{.HostConfig.LogConfig.Type}}' m12-e18-journald"

# --- 2. Ressources --------------------------------------------------------------------------------------------
_m12o_e18_svc() {
  local id
  id="$(_m12o_docker "ps -q --filter label=com.docker.compose.project=mediagenda --filter label=com.docker.compose.service=$1" | head -n 1)"
  [[ -n "$id" ]] && _m12o_docker "inspect $id" | jq -c '.[0]' 2>/dev/null || true
}
for _m12o_e18_s in api db valkey; do
  _m12o_e18_j="$(_m12o_e18_svc "$_m12o_e18_s")"
  check_cmd "pile mediagenda, $_m12o_e18_s : limites de mémoire et de processus" _m12o_json "${_m12o_e18_j:-}" \
    '(.HostConfig.Memory // 0) > 0 and (.HostConfig.PidsLimit // 0) > 0'
  check_cmd "pile mediagenda, $_m12o_e18_s : délai d'arrêt explicite (au moins 15 s)" _m12o_json "${_m12o_e18_j:-}" \
    '(.Config.StopTimeout // 0) >= 15' 
done
_m12o_e18_vk="$(_m12o_e18_svc valkey)"
check_cmd "valkey : mémoire maximale et politique d'éviction (maxmemory, maxmemory-policy)" _m12o_json "${_m12o_e18_vk:-}" \
  '((.Config.Cmd // []) | join(" ")) | test("maxmemory [0-9]") and test("maxmemory-policy")'
check_cmd "mediagenda/api (main) : compose.yaml avec des limites de mémoire" \
  bash -c 'grep -Eq "mem_limit:|memory:" <<<"$1" && grep -Eq "pids_limit:|pids:" <<<"$1"' _ "$(_m12o_fichier mediagenda/api compose.yaml)"
check_output "m12-e18-oom : arrêté, tué par le noyau (OOMKilled)" '^exited true 137$' \
  _m12o_docker "inspect --format '{{.State.Status}} {{.State.OOMKilled}} {{.State.ExitCode}}' m12-e18-oom"

# --- 3. Santé --------------------------------------------------------------------------------------------------
check_output "m12-e18-malade : en marche mais malade (unhealthy)" '^running unhealthy$' \
  _m12o_docker "inspect --format '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' m12-e18-malade"
_m12o_e18_q="$(_m12o_ssh "$_M12O_CTR02" 'sudo -n cat /home/app/.config/containers/systemd/mediagenda-api.container')"
check_cmd "ctr02 : mediagenda-api.container — HealthOnFailure et PidsLimit" \
  bash -c 'grep -Eq "^HealthOnFailure=(kill|restart|stop)" <<<"$1" && grep -Eq "^PidsLimit=[0-9]+" <<<"$1"' _ "$_m12o_e18_q"
check_output "ctr02 (app) : l'API est saine" '^healthy$' \
  _m12o_app "$_M12O_CTR02" "podman inspect --format '{{.State.Health.Status}}' mediagenda-api"
