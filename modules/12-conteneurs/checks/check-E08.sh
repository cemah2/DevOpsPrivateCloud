# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E08.sh — M12-E08 : Docker Compose : MédiAgenda, PostgreSQL et Valkey
# À lancer depuis adm01. Lecture seule : docker ps / inspect / exec de lecture sur ctr01 (SSH),
# requête HTTP vers l'API, API GitLab en GET.

# shellcheck source=_m12-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-decouverte.sh"

title "M12-E08 — Docker Compose : MédiAgenda, PostgreSQL et Valkey"
require_cmd jq curl

# _m12d_e08_id SERVICE — identifiant du conteneur du service dans le projet Compose « mediagenda ».
_m12d_e08_id() {
  _m12d_docker "ps -aq --filter label=com.docker.compose.project=mediagenda --filter label=com.docker.compose.service=$1" | sed -n 1p
}

# _m12d_e08_insp ID FORMAT — docker inspect --format sur un conteneur du projet (vide si ID vide).
_m12d_e08_insp() {
  [[ -n "$1" ]] || return 0
  _m12d_inspect "$1" "$2"
}

# _m12d_e08_pid1 ID — ligne de commande du PID 1 du conteneur (vide si ID vide).
_m12d_e08_pid1() {
  [[ -n "$1" ]] || return 0
  _m12d_docker "exec $1 cat /proc/1/cmdline" | tr '\0' ' '
}

_m12d_e08_db="$(_m12d_e08_id db)"
_m12d_e08_valkey="$(_m12d_e08_id valkey)"
_m12d_e08_mig="$(_m12d_e08_id migrations)"
_m12d_e08_api="$(_m12d_e08_id api)"

# --- 1. La pile tourne -------------------------------------------------------------------------------
for _m12d_e08_def in "db:$_m12d_e08_db" "valkey:$_m12d_e08_valkey" "api:$_m12d_e08_api"; do
  _m12d_e08_s="${_m12d_e08_def%%:*}"
  _m12d_e08_c="${_m12d_e08_def#*:}"
  check_output "Projet mediagenda : service $_m12d_e08_s en marche et sain (sonde de santé)" '^running healthy$' \
    _m12d_e08_insp "$_m12d_e08_c" '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}'
done
check_output "Projet mediagenda : service migrations terminé avec le code 0 (sans redémarrage)" '^exited 0 (no)?$' \
  _m12d_e08_insp "$_m12d_e08_mig" '{{.State.Status}} {{.State.ExitCode}} {{.HostConfig.RestartPolicy.Name}}'
check_http "Depuis adm01 : /pret de l'API (port 8000) répond 200 (base et cache joignables)" "http://$(_m12d_fqdn ctr01):8000/pret" 200
check_output "Service db : PostgreSQL 18" '"PG_MAJOR=18"' _m12d_e08_insp "$_m12d_e08_db" '{{json .Config.Env}}'

# --- 2. Isolement et données --------------------------------------------------------------------------
for _m12d_e08_def in "db:$_m12d_e08_db" "valkey:$_m12d_e08_valkey"; do
  _m12d_e08_s="${_m12d_e08_def%%:*}"
  _m12d_e08_c="${_m12d_e08_def#*:}"
  _m12d_e08_j="$(_m12d_e08_insp "$_m12d_e08_c" '{{json .}}')"
  check_cmd "Service $_m12d_e08_s : aucun port publié sur l'hôte" _m12d_json "$_m12d_e08_j" \
    '[.NetworkSettings.Ports // {} | to_entries[] | .value // [] | .[]] | length == 0'
  # Réseaux du service : tous internes.
  _m12d_e08_ok=1
  for _m12d_e08_n in $(jq -r '.NetworkSettings.Networks // {} | keys[]' <<<"${_m12d_e08_j:-[]}" 2>/dev/null || true); do
    [[ "$(_m12d_docker "network inspect --format '{{.Internal}}' $_m12d_e08_n")" == true ]] || _m12d_e08_ok=0
  done
  [[ -n "$_m12d_e08_j" ]] || _m12d_e08_ok=0
  check_cmd "Service $_m12d_e08_s : seulement sur des réseaux internes" test "$_m12d_e08_ok" = 1
done
_m12d_e08_jdb="$(_m12d_e08_insp "$_m12d_e08_db" '{{json .Mounts}}')"
check_cmd "Service db : volume nommé monté sur /var/lib/postgresql (disposition de PostgreSQL 18)" _m12d_json "${_m12d_e08_jdb:-}" \
  '[.[] | select(.Type == "volume" and .Destination == "/var/lib/postgresql")] | length == 1'

# --- 3. Le secret ---------------------------------------------------------------------------------------
_m12d_e08_envs="$(for _m12d_e08_c in $_m12d_e08_db $_m12d_e08_valkey $_m12d_e08_mig $_m12d_e08_api; do _m12d_e08_insp "$_m12d_e08_c" '{{json .Config.Env}}'; done)"
check_cmd "Aucun mot de passe dans l'environnement des conteneurs (POSTGRES_PASSWORD, PGPASSWORD, URL avec mot de passe)" \
  bash -c '[[ -n "$1" ]] && ! grep -Eq "\"(POSTGRES_PASSWORD|PGPASSWORD)=|postgres(ql)?://[^:/@\"]+:[^@\"]+@" <<<"$1"' _ "$_m12d_e08_envs"
check_output "Service db : mot de passe lu dans un fichier de secret (POSTGRES_PASSWORD_FILE sous /run/secrets)" \
  '"POSTGRES_PASSWORD_FILE=/run/secrets/' bash -c 'echo "$1"' _ "$_m12d_e08_envs"
check_output "API : le PID 1 est mediagenda (pas un shell)" '^([^ ]*python[^ ]* )?[^ ]*/?mediagenda( |$)' \
  _m12d_e08_pid1 "$_m12d_e08_api"
check_ssh "ctr01 : le fichier de secret n'est pas lisible par les autres comptes de l'hôte" ctr01 \
  'f=$HOME/src/mediagenda-api/secrets/db_mdp; test -s "$f" && { [ $(( 0$(stat -c %a "$f") & 4 )) -eq 0 ] || [ $(( 0$(stat -c %a "$(dirname "$f")") & 1 )) -eq 0 ]; }'

# --- 4. Le dépôt ------------------------------------------------------------------------------------------
_m12d_e08_compose="$(_m12d_contenu_main mediagenda/api compose.yaml)"
check_cmd "mediagenda/api (main) : compose.yaml présent, sans attribut « version: »" \
  bash -c '[[ -n "$1" ]] && ! grep -Eq "^version:" <<<"$1"' _ "$_m12d_e08_compose"
check_cmd "compose.yaml : dépendances conditionnées (service_healthy, service_completed_successfully)" \
  bash -c 'grep -q "service_healthy" <<<"$1" && grep -q "service_completed_successfully" <<<"$1"' _ "$_m12d_e08_compose"
check_cmd "mediagenda/api (main) : aucun fichier sous secrets/ n'est versionné" \
  bash -c '[[ -n "$1" ]] && ! grep -Eq "^secrets/" <<<"$1"' _ "$(_m12d_arbre_main mediagenda/api)"
check_output "mediagenda/api (main) : .gitignore exclut secrets/" '^/?secrets/?$' \
  _m12d_contenu_main mediagenda/api .gitignore
