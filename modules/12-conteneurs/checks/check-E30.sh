# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes entre apostrophes
#
# check-E30.sh — M12-E30 « Mettre à jour sans interruption et revenir en arrière »
# Lecture seule : docker inspect sur ctr01, HTTP vers la recette, podman inspect et systemctl
# --user du compte app sur ctr02, journal système (journalctl), fichiers sur main (API GitLab).

# shellcheck source=_m12-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-production.sh"

title "M12-E30 — Mise à jour sans interruption"
require_cmd jq curl

title "Partie A : ctr01, deux instances derrière HAProxy"
for _m12_e30_s in api api-b; do
  _m12_e30_c="$(_m12p_ctr_service ctr01 mediagenda "$_m12_e30_s")"
  _m12_e30_j="$(_m12p_inspect ctr01 "$_m12_e30_c")"
  check_cmd "service $_m12_e30_s : en marche et sain" _m12p_jq "$_m12_e30_j" '.State.Health.Status == "healthy"'
  check_cmd "service $_m12_e30_s : aucun port publié directement" _m12p_jq "$_m12_e30_j" \
    '[(.HostConfig.PortBindings // {}) | to_entries[] | .value // [] | .[]] | length == 0'
done
_m12_e30_e="$(_m12p_ctr_service ctr01 mediagenda entree)"
check_cmd "HAProxy de la recette (service entree) en marche" test -n "$_m12_e30_e"
check_cmd "HAProxy publie le port 8000 de l'hôte" _m12p_jq "$(_m12p_inspect ctr01 "$_m12_e30_e")" \
  '[(.HostConfig.PortBindings // {}) | to_entries[] | .value // [] | .[] | .HostPort] | index("8000") != null'
check_http "/sante répond à travers le port 8000 de ctr01" "http://ctr01.$_M12P_DOMAINE:8000/sante" 200
check_ssh_output "les deux serveurs sont UP dans HAProxy (page d'état)" ctr01 '^api-a UP api-b UP$' \
  "curl -fsS --max-time 5 'http://127.0.0.1:8404/etat;csv' | awk -F, '\$1 == \"api\" && \$2 != \"BACKEND\" { printf \"%s %s \", \$2, \$18 }' | sed 's/ \$//'"

title "Partie B : ctr02, mise à jour automatique (compte app)"
_m12_e30_p="$(_m12p_podman ctr02 "ps --filter label=io.containers.autoupdate=registry --format '{{.Names}}'" | head -n 1)"
check_cmd "un conteneur du compte app porte AutoUpdate=registry" test -n "$_m12_e30_p"
_m12_e30_pj="$(_m12p_podman ctr02 "inspect ${_m12_e30_p:-absent}" | jq -c '.[0]' 2>/dev/null || echo null)"
check_cmd "il suit l'étiquette mobile recette de mediagenda/api" _m12p_jq "$_m12_e30_pj" \
  '.ImageName | test("mediagenda/api:recette$")'
check_cmd "il a une sonde de santé et il est sain" _m12p_jq "$_m12_e30_pj" \
  '((.Config.Healthcheck.Test // []) | length > 0) and (.State.Health.Status == "healthy")'
_m12_e30_u="$(jq -r '.Config.Labels.PODMAN_SYSTEMD_UNIT // empty' <<<"$_m12_e30_pj" 2>/dev/null || true)"
check_output "son unité systemd est active" '^active$' _m12p_systemctl_app ctr02 "is-active ${_m12_e30_u:-absente.service}"
check_output "le timer podman-auto-update du compte est actif" '^active$' \
  _m12p_systemctl_app ctr02 "is-active podman-auto-update.timer"
# Libellé du retour arrière à vérifier sur ta version (podman auto-update : « rolled back »).
check_ssh_output "un retour arrière automatique est journalisé (30 jours)" ctr02 'roll(ed)?[ -]?back|rollback' \
  "sudo -n journalctl -q --no-pager --since -30d _UID=$_M12P_APP_UID -o cat | grep -iE 'auto-update|autoupdate' | grep -iE 'roll' | tail -n 3"

title "Dans le code"
check_cmd "mediagenda/api : compose.ha.yaml (extends, plus de publication directe)" \
  _m12p_doc_main mediagenda/api compose.ha.yaml 'extends' '!reset'
check_cmd "mediagenda/api : configuration HAProxy avec résolution dynamique et nouvelles tentatives" \
  _m12p_doc_main mediagenda/api haproxy/haproxy.cfg '^resolvers ' 'retry-on' 
check_cmd "mediagenda/api : outils/maj-progressive.sh sur main" _m12p_arbre_contient mediagenda/api '^outils/maj-progressive\.sh$'
check_cmd "RB-122 sur main" _m12p_arbre_contient plateforme/medisphere '^docs/conteneurs/runbooks/RB-122'
