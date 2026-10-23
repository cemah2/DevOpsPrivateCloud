# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E23.sh — M27-E23 « Astreinte : des rendez-vous sans notification » : MédiAgenda publie de nouveau,
# MédiNotif consomme, la file de recette est saine, le rebut ne garde plus les messages de l'incident, deux
# alertes nouvelles (échecs de publication, rebut), post-mortem INC-5423 ; panne close. Lecture seule.

# shellcheck source=_m27-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m27-expert.sh"

title "M27-E23 — Les notifications repartent"
require_cmd kubectl jq curl

_m27_e23_publie() {
  rabbitmq_api "exchanges/$_m27p_vhost_recette/notifications" 2>/dev/null |
    jq -e '(.message_stats.publish_in_details.rate // 0) > 0' >/dev/null 2>&1
}
check_cmd "l'échange notifications ($_m27p_vhost_recette) reçoit des publications (témoin de trafic)" _m27_e23_publie
_m27_e23_permission() {
  kube get permissions.rabbitmq.com -A -o json 2>/dev/null | jq -e --arg v "$_m27p_vhost_recette" '
    [.items[] | select(.spec.vhost == $v and ((.spec.user // .spec.userReference.name // "") | test("^mediagenda-recette$")))]
    | length > 0 and all(.[]; (.spec.permissions.write // "") as $w | "notifications" | test($w))' >/dev/null 2>&1
}
check_cmd "Permission déclarée de mediagenda-recette : écriture permise sur l'échange notifications" _m27_e23_permission
check_cmd "notifications ($_m27p_vhost_recette) : consommée, moins de 20 messages prêts" _m27x_file_saine "$_m27p_vhost_recette"
check_cmd "notifications ($_m27p_vhost_recette) : ni durée de vie courte ni longueur maximale qui enverraient des demandes au rebut" \
  _m27p_file "$_m27p_vhost_recette" notifications '((.effective_policy_definition["message-ttl"] // .arguments["x-message-ttl"] // 86400000) | tonumber) >= 3600000
    and ((.effective_policy_definition["max-length"] // .arguments["x-max-length"] // 1000000) | tonumber) >= 10000'
check_cmd "notifications ($_m27p_vhost_recette) : rebut « au moins une fois » (dead-letter-strategy at-least-once, overflow reject-publish)" \
  _m27p_file "$_m27p_vhost_recette" notifications '(.arguments["x-dead-letter-strategy"] // .effective_policy_definition["dead-letter-strategy"] // "") == "at-least-once"
    and (.arguments["x-overflow"] // .effective_policy_definition["overflow"] // "") == "reject-publish"'
check_cmd "MédiNotif (recette) disponible" _m27x_medinotif_sain medinotif-recette
_m27_e23_rebut() {
  local avant f="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M27-E23/rebut-avant"
  avant=5
  if [[ -r "$f" ]]; then avant="$(<"$f")"; fi
  [[ "$avant" =~ ^[0-9]+$ ]] || avant=5
  _m27p_file "$_m27p_vhost_recette" notifications.rebut "(.messages // 0) <= $avant"
}
check_cmd "notifications.rebut ($_m27p_vhost_recette) : messages de l'incident rejoués (pas plus qu'avant l'incident)" _m27_e23_rebut
check_cmd "une alerte surveille les échecs de publication de MédiAgenda" _m27p_alerte_famille 'mediagenda_notifications_total'
check_cmd "une alerte surveille la file de rebut" _m27p_alerte_famille 'notifications[.]rebut'
check_cmd "post-mortem INC-5423 publié (chronologie, impact chiffré, causes, actions)" \
  _m27p_doc "$_m27x_postmortems" INC-5423 'chronologie' 'impact' 'cause' 'action' '[0-9]+ (rendez-vous|notifications)'
check_cmd "journal d'incident INC-5423" _m27x_journal_inc 5423 '.'
check_cmd "RB-277 complété (rejeu du rebut)" _m27p_doc "$_m27p_runbooks" RB-277 'rebut' 'shovel|rejou'
check_cmd "panne M27-E23 close (lab/bin/break 27 23 --annuler après réparation)" _m27p_aucune_panne_active E23
