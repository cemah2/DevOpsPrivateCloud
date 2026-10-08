# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E17.sh — M08-E17 : Exporter un bloc en iSCSI
# À lancer depuis adm01. Lecture seule : rbdmap, configuration sauvegardée de LIO (lue par jq sur
# cephcli01, sans jamais afficher le secret CHAP), port 3260, absence de la VM 2086.

# shellcheck source=_m08-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-operationnel.sh"

title "M08-E17 — Exporter un bloc en iSCSI"
require_cmd jq

_m08o_iqn=iqn.2026-10.internal.medisphere.par1:cephcli01.legacy
_m08o_init=iqn.2026-10.internal.medisphere.par1:m08-initiateur
# Résumé de saveconfig.json, SANS le mot de passe CHAP (seulement sa présence) : le fichier est lu
# par sudo sur cephcli01 et filtré aussitôt par jq sur adm01, jamais stocké ni affiché.
_m08o_lio="$(_m08o_client 'sudo -n cat /etc/rtslib-fb-target/saveconfig.json' | jq -c --arg t "$_m08o_iqn" '
  { so: [.storage_objects[] | {name, plugin, dev}],
    t: [.targets[] | select(.wwn == $t) | .tpgs[] | {attributes, portals,
        luns: [.luns[] | {index, storage_object}],
        acls: [.node_acls[] | {node_wwn, chap_userid, chap: ((.chap_password // "") | length > 0)}]}] }' 2>/dev/null || true)"

check_ssh "cephcli01 : rbdmap déclare rbd-test/iscsi-scan avec client.iscsi-cephcli01" "$_M08O_CLIENT" \
  'grep -Ev "^[[:space:]]*#" /etc/ceph/rbdmap | grep -E "^rbd-test/iscsi-scan[[:space:]]" | grep -q "id=iscsi-cephcli01"'
check_ssh "cephcli01 : rbdmap.service activé" "$_M08O_CLIENT" 'systemctl is-enabled --quiet rbdmap.service'
check_ssh "cephcli01 : /dev/rbd/rbd-test/iscsi-scan présent" "$_M08O_CLIENT" 'test -b /dev/rbd/rbd-test/iscsi-scan'
check_cmd "client.iscsi-cephcli01 : profil rbd sur rbd-test, limité à 10.10.30.20" \
  jq -e '.[0].caps.osd | test("profile rbd pool=rbd-test") and test("network 10\\.10\\.30\\.20/32")' \
  <<<"$(_m08o_ceph auth get client.iscsi-cephcli01 --format json)"

check_cmd "LIO : backstore block sur /dev/rbd/rbd-test/iscsi-scan (pas /dev/rbdN)" \
  jq -e '[.so[] | select(.plugin == "block" and .dev == "/dev/rbd/rbd-test/iscsi-scan")] | length == 1' <<<"$_m08o_lio"
check_cmd "LIO : cible $_m08o_iqn, LUN 0 sur ce backstore" \
  jq -e '[.t[].luns[] | select(.index == 0 and (.storage_object | endswith("/iscsi-scan")))] | length == 1' <<<"$_m08o_lio"
check_cmd "LIO : portail 10.10.30.20:3260 seulement" \
  jq -e '[.t[].portals[] | "\(.ip_address):\(.port)"] == ["10.10.30.20:3260"]' <<<"$_m08o_lio"
check_cmd "LIO : ACL pour l'initiateur, avec CHAP (identifiant scan-legacy)" \
  jq -e --arg i "$_m08o_init" '[.t[].acls[] | select(.node_wwn == $i and .chap_userid == "scan-legacy" and .chap)] | length == 1' <<<"$_m08o_lio"
check_cmd "LIO : authentification exigée, pas d'ACL générées (mode démo)" \
  jq -e '.t[0].attributes.authentication == 1 and .t[0].attributes.generate_node_acls == 0' <<<"$_m08o_lio"
check_ssh "cephcli01 : saveconfig.json lisible par root seulement" "$_M08O_CLIENT" \
  '[ "$(sudo -n stat -c %a /etc/rtslib-fb-target/saveconfig.json)" = 600 ]'
check_ssh "cephcli01 : restauration de LIO activée au démarrage" "$_M08O_CLIENT" \
  'systemctl list-unit-files --state=enabled --no-legend | grep -qiE "rtslib|^target\.service"'
check_port "10.10.30.20 répond sur TCP 3260" 10.10.30.20 3260
check_ssh "pve01 : la VM jetable 2086 (m08-initiateur) est détruite" "${WB_PVE_HOST:-pve01}" '! qm status 2086 >/dev/null 2>&1'
