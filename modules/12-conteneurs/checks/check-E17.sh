# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016,SC2088  # « ~ » développé sur l'hôte distant ou simple libellé ; gabarits Go et commandes entre apostrophes : évalués par docker ou bash -c
#
# check-E17.sh — M12-E17 : Conteneuriser MédiNotif : signaux, PID 1, arrêt propre
# À lancer depuis adm01. Lecture seule : API GitLab en GET ; docker inspect et lecture de
# /proc/1/cmdline du worker sur ctr01 ; métriques HTTP du worker ; lecture de ~/m12/e17/arret.txt.

# shellcheck source=_m12-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-operationnel.sh"

title "M12-E17 — Conteneuriser MédiNotif : signaux, PID 1, arrêt propre"
require_cmd jq curl

# --- 1. Le projet -----------------------------------------------------------------------------------------
check_output "GitLab : projet medinotif/worker, branche par défaut main" '"default_branch": *"main"' \
  bash -c 'jq "{default_branch}" <<<"$1"' _ "$(_m12o_projet medinotif/worker)"
_m12o_e17_df="$(_m12o_fichier medinotif/worker Dockerfile)"
check_cmd "Dockerfile : USER numérique non root" _m12o_correspond "$_m12o_e17_df" '^USER +[1-9][0-9]*(:[0-9]+)?\s*$'
check_cmd "Dockerfile : STOPSIGNAL explicite" _m12o_correspond "$_m12o_e17_df" '^STOPSIGNAL +'
check_cmd "Dockerfile : commande en forme exec" _m12o_correspond "$_m12o_e17_df" '^(ENTRYPOINT|CMD) +\['
check_cmd "medinotif/worker (main) : compose.yaml et .dockerignore présents" \
  test -n "$(_m12o_fichier medinotif/worker compose.yaml)" -a -n "$(_m12o_fichier medinotif/worker .dockerignore)"

# --- 2. La pile de test ------------------------------------------------------------------------------------
_m12o_e17_id="$(_m12o_docker "ps -q --filter label=com.docker.compose.project=medinotif --filter label=com.docker.compose.service=worker" | head -n 1)"
_m12o_e17_j="$( [[ -n "$_m12o_e17_id" ]] && _m12o_docker "inspect $_m12o_e17_id" | jq -c '.[0]' 2>/dev/null || true)"
check_cmd "ctr01 : worker de la pile medinotif en marche et sain" _m12o_json "${_m12o_e17_j:-}" \
  '.State.Status == "running" and .State.Health.Status == "healthy"'
check_cmd "worker : délai de grâce d'au moins 15 s" _m12o_json "${_m12o_e17_j:-}" '(.Config.StopTimeout // 10) >= 15'
check_cmd "worker : utilisateur non root" _m12o_json "${_m12o_e17_j:-}" '(.Config.User // "") | test("^(0|root)?(:.*)?$") | not'
_m12o_e17_pid1="$( [[ -n "$_m12o_e17_id" ]] && _m12o_docker "exec $_m12o_e17_id cat /proc/1/cmdline" | tr '\0' ' ' || true)"
check_cmd "worker : le PID 1 est le worker, pas un shell ($_m12o_e17_pid1)" \
  bash -c 'grep -q "medinotif" <<<"$1" && ! grep -Eq "^(/bin/)?(ba|da)?sh( |$)|docker-init|tini" <<<"$1"' _ "$_m12o_e17_pid1"
_m12o_e17_envs="$(_m12o_docker "ps -q --filter label=com.docker.compose.project=medinotif" | while read -r _i; do _m12o_docker "inspect --format '{{json .Config.Env}}' $_i"; done)"
check_cmd "pile medinotif : aucun mot de passe dans l'environnement des conteneurs" \
  _m12o_absent "$_m12o_e17_envs" 'RABBITMQ_DEFAULT_PASS=|amqps?://[^:/@"]+:[^@"]+@'
check_output "Depuis adm01 : métriques du worker sur ctr01:9100 (medinotif_messages_total)" 'medinotif_messages_total' \
  curl -s --max-time "${WB_TIMEOUT:-5}" "http://$_M12O_NOM01:9100/metrics"

# --- 3. La mesure de l'arrêt ----------------------------------------------------------------------------------
_m12o_e17_arret="$(_m12o_ssh "$_M12O_CTR01" 'cat ~/m12/e17/arret.txt')"
check_cmd "~/m12/e17/arret.txt : code de sortie 0 et « arrêt terminé »" \
  bash -c 'grep -Eq "code de sortie *: *0\b" <<<"$1" && grep -q "arrêt terminé" <<<"$1"' _ "$_m12o_e17_arret"
check_cmd "~/m12/e17/arret.txt : arrêt en moins de 10 s" \
  bash -c 'd="$(grep -Eo "durée[^0-9]*[0-9]+([.,][0-9]+)?" <<<"$1" | grep -Eo "[0-9]+([.,][0-9]+)?$" | head -n 1 | tr , .)"; [ -n "$d" ] && awk -v d="$d" "BEGIN { exit !(d < 10) }"' _ "$_m12o_e17_arret"
