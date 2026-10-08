# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E13.sh — M08-E13 : Cephx : des clients aux droits minimaux
# À lancer depuis adm01. Lecture seule (auth ls, stat, rbd ls avec la clé de lecture).

# shellcheck source=_m08-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-operationnel.sh"

title "M08-E13 — Cephx : des clients aux droits minimaux"
require_cmd jq ssh

_m08o_auth="$(_m08o_ceph auth ls --format json)"
_m08o_caps() { jq -c --arg e "$1" '.auth_dump[] | select(.entity == $e) | .caps' <<<"$_m08o_auth" 2>/dev/null || true; }

check_ssh "cephcli01 : aucune clé client.admin (/etc/ceph, /root, /home)" "$_M08O_CLIENT" \
  '! sudo -n find /etc/ceph /root /home -name "ceph.client.admin.keyring" 2>/dev/null | grep -q .'
# Clés des DÉMONS créées par cephadm (RGW, NFS, crash, exporter, amorçage) exclues : elles ne sont
# sur aucun client et cephadm fixe leurs droits.
check_cmd "aucun client (hors client.admin et clés de démons) n'a « allow * » sur les moniteurs" \
  jq -e '[.auth_dump[] | select((.entity | startswith("client.")) and .entity != "client.admin"
          and (.entity | test("^client\\.(rgw|nfs|crash|ceph-exporter|bootstrap-|rbd-mirror|cephfs-mirror|nvmeof)") | not)
          and ((.caps.mon // "") | test("allow \\*")))] | length == 0' <<<"$_m08o_auth"

_m08o_rw="$(_m08o_caps client.rbd-test)"
check_cmd "client.rbd-test : profil rbd sur rbd-test, limité à 10.10.30.20/32 (mon et osd)" \
  jq -e '((.mon // "") | test("profile rbd") and test("network 10\\.10\\.30\\.20/32"))
         and ((.osd // "") | test("profile rbd pool=rbd-test") and test("network 10\\.10\\.30\\.20/32"))
         and ((.osd // "") | test("allow (\\*|rwx?)( |$)") | not)' <<<"$_m08o_rw"
_m08o_ro="$(_m08o_caps client.rbd-lecture)"
check_cmd "client.rbd-lecture : profil rbd-read-only sur rbd-test, aucun droit d'écriture" \
  jq -e '((.osd // "") | test("profile rbd-read-only pool=rbd-test"))
         and ((.osd // "") | test("profile rbd pool|allow [^ ]*w|allow \\*") | not)' <<<"$_m08o_ro"

for _m08o_k in rbd-test rbd-lecture; do
  check_cmd "cephcli01 : trousseau client.$_m08o_k en 600, propriétaire root" \
    _m08o_root600 "$_M08O_CLIENT" "/etc/ceph/ceph.client.$_m08o_k.keyring"
done
check_ssh "cephcli01 : « rbd ls rbd-test » fonctionne avec la clé de lecture" "$_M08O_CLIENT" \
  'sudo -n timeout 20 rbd --id rbd-lecture ls rbd-test >/dev/null'
check_cmd "registre des secrets : rbd-test et rbd-lecture inscrites" \
  bash -c 'grep -qi "client.rbd-test" "$1" && grep -qi "rbd-lecture" "$1"' _ "$_M08O_REGISTRE"
