# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes et filtres entre apostrophes (hôte distant, jq)
# check-E39.sh — M08-E39 « Panne : le client RBD est refusé » : client.sonde a les bons droits, son
# trousseau est valide sur cephcli01, l'image n'utilise que des fonctionnalités prises en charge par
# krbd, et le volume est monté. Lecture seule.

# shellcheck source=_m08-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-expert.sh"

title "M08-E39 — Le client RBD accède à son image"
require_cmd jq ssh

if ! _m08x_temoins; then
  skip "client RBD témoin" "témoins pas encore créés : ils le sont à la première injection (lab/bin/break 08 39)"
else
  if _m08x_cluster_repond; then
    check_cmd "client.sonde : droits OSD « profile rbd » limités au pool rbd-test" \
      _m08x_jq '.sonde.osd | test("^profile rbd pool=rbd-test$")'
    check_cmd "client.sonde : droits MON « profile rbd »" _m08x_jq '.sonde.mon == "profile rbd"'
  else
    skip "droits de client.sonde" "les moniteurs ne répondent pas au nœud $_m08x_admin"
  fi
  check_ssh "$_m08x_client : client.sonde s'authentifie et lit l'image (rbd info)" "$_m08x_client" \
    'sudo -n timeout 30 rbd --id sonde info rbd-test/sonde >/dev/null 2>&1'
  check_ssh "$_m08x_client : l'image n'a pas de fonctionnalité refusée par krbd (journaling)" "$_m08x_client" \
    'f=$(sudo -n timeout 30 rbd --id sonde info rbd-test/sonde --format json 2>/dev/null) && [ -n "$f" ] && ! printf "%s" "$f" | grep -q journaling'
  check_ssh "$_m08x_client : trousseau de client.sonde en mode 600" "$_m08x_client" \
    '[ "$(sudo -n stat -c %a /etc/ceph/ceph.client.sonde.keyring)" = 600 ]'
  check_ssh "$_m08x_client : /mnt/sonde est monté depuis un périphérique /dev/rbd*" "$_m08x_client" \
    'findmnt -no SOURCE /mnt/sonde | grep -q "^/dev/rbd"'
  check_ssh "$_m08x_client : le fichier témoin de l'image est lisible" "$_m08x_client" \
    'sudo -n timeout 10 cat /mnt/sonde/temoin >/dev/null'
fi
check_cmd "panne M08-E39 close (lab/bin/break 08 39 --annuler après réparation)" _m08x_aucune_panne_active E39
