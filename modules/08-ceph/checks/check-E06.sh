# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E06.sh — M08-E06 : RBD : images, snapshots et clones
# À lancer depuis adm01. Lecture seule : qm config sur pve01, DNS, commandes « ceph » et « rbd »
# d'observation sur le nœud _admin, état de cephcli01 en SSH, API GitLab en GET.

# shellcheck source=_m08-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-decouverte.sh"

title "M08-E06 — RBD : images, snapshots et clones"
require_cmd jq dig curl

_m08d_e06_cli="$_M08D_CLIENT"

# _m08d_e06_caps — droits cephx de client.rbd-test : profil rbd au moniteur, profil rbd limité au
# pool rbd-test sur les OSD, rien d'autre. Les ajouts des exercices suivants restent acceptés :
# restriction réseau (E13), profil rbd du mgr (E13), pool de données EC rbd-ec-donnees (E15).
_m08d_e06_caps() {
  _m08d_ceph "auth get client.rbd-test -f json" | jq -e '
    .[0].caps as $c
    | ($c | keys - ["mgr", "mon", "osd"] | length == 0)
      and ($c.mon | test("^profile rbd( network [0-9./]+)?$"))
      and ($c.osd | split(", *"; null) | all(test("^profile rbd pool=(rbd-test|rbd-ec-donnees)( network [0-9./]+)?$")))
      and ($c.osd | test("pool=rbd-test"))
      and (($c.mgr // "profile rbd") | split(", *"; null) | all(test("^profile rbd( pool=[a-z0-9-]+)?$")))' >/dev/null 2>&1
}

# --- 1. La VM cliente -------------------------------------------------------------------------------
_m08d_e06_conf="$(_m08d_qm 2085)"
check_cmd "VM 2085 nommée cephcli01" \
  bash -c 'grep -q "^name: cephcli01$" <<<"$1"' _ "$_m08d_e06_conf"
check_cmd "cephcli01 : étiquettes env-m08 et role-ceph-client" _m08d_etiquettes "$_m08d_e06_conf" env-m08 role-ceph-client
check_cmd "cephcli01 : une seule carte, sur vstopub, MTU 9000" \
  bash -c 'grep -Eq "^net0: .*bridge=vstopub.*mtu=9000" <<<"$1" && ! grep -q "^net1:" <<<"$1"' _ "$_m08d_e06_conf"
check_dns "DNS : cephcli01.par1.medisphere.internal → 10.10.30.20" cephcli01.par1.medisphere.internal A '^10\.10\.30\.20$' "$_M08D_DNS"
check_ssh_output "cephcli01 : Debian 13" "$_m08d_e06_cli" '^debian 13$' '. /etc/os-release; echo "$ID $VERSION_ID"'

# --- 2. Le client cephx ------------------------------------------------------------------------------
check_cmd "client.rbd-test : droits limités au profil rbd sur le pool rbd-test (mon, osd)" _m08d_e06_caps
check_ssh "cephcli01 : trousseau client.rbd-test en 600, root" "$_m08d_e06_cli" \
  '[ "$(sudo -n stat -c %a:%U /etc/ceph/ceph.client.rbd-test.keyring)" = 600:root ]'
check_ssh "cephcli01 : AUCUN trousseau client.admin" "$_m08d_e06_cli" \
  '! sudo -n ls /etc/ceph/ | grep -q "client.admin"'
check_ssh "cephcli01 : ceph.conf minimal pointant vers le cluster (même fsid)" "$_m08d_e06_cli" \
  "grep -Eq '^\s*fsid\s*=\s*$(_m08d_ceph fsid | tr -d '[:space:]')\s*$' /etc/ceph/ceph.conf && grep -q '10.10.30.51:3300' /etc/ceph/ceph.conf"
check_ssh "cephcli01 : le client lit le cluster avec ses seuls droits (rbd ls rbd-test)" "$_m08d_e06_cli" \
  'sudo -n rbd --id rbd-test ls rbd-test | grep -qx disque01'

# --- 3. Images, instantanés, clones -------------------------------------------------------------------
check_cmd "Image rbd-test/disque01 de 10 Gio" _m08d_json "$(_m08d_rbd "info rbd-test/disque01 --format json")" \
  '.size == 10737418240'
check_cmd "Instantané disque01@avant-maj présent et protégé" _m08d_json "$(_m08d_rbd "snap ls rbd-test/disque01 --format json")" \
  '[.[] | select(.name == "avant-maj" and (.protected | tostring) == "true")] | length == 1'
check_cmd "Clone rbd-test/disque01-clone présent et aplati (plus de parent)" \
  _m08d_json "$(_m08d_rbd "info rbd-test/disque01-clone --format json")" '(.name == "disque01-clone") and (has("parent") | not)'

# --- 4. Le montage sur le client, persistant -------------------------------------------------------------
check_ssh "cephcli01 : /mnt/disque01 monté en XFS depuis un périphérique rbd" "$_m08d_e06_cli" \
  'findmnt -n -o SOURCE,FSTYPE /mnt/disque01 | grep -Eq "^/dev/rbd[0-9]+ +xfs$"'
check_ssh "cephcli01 : le périphérique monté est bien rbd-test/disque01" "$_m08d_e06_cli" \
  'd=$(findmnt -n -o SOURCE /mnt/disque01) && [ "$(readlink -f /dev/rbd/rbd-test/disque01)" = "$d" ]'
check_ssh "cephcli01 : rbdmap activé et déclare rbd-test/disque01" "$_m08d_e06_cli" \
  'systemctl is-enabled --quiet rbdmap && grep -Eq "^rbd-test/disque01\s+.*id=rbd-test" /etc/ceph/rbdmap'
check_ssh "cephcli01 : fstab monte /mnt/disque01 en noauto (monté par rbdmap après le mappage)" "$_m08d_e06_cli" \
  'findmnt --fstab -n -o OPTIONS /mnt/disque01 | grep -q noauto'

# --- 5. Le code ------------------------------------------------------------------------------------------
check_cmd "plateforme/ansible (main) : rôle ceph_client" _m08d_fichier_main plateforme/ansible roles/ceph_client/tasks/main.yml
check_cmd "plateforme/infra (main) : cephcli01 dans envs/ceph" _m08d_fichier_main plateforme/infra envs/ceph/cephcli01.tf
check_cmd "Clé cephx du client chiffrée sous l'identité « lab »" \
  bash -c 'head -n 1 "$1/ansible/inventories/lab/group_vars/role_ceph_client/vault-lab.yml" 2>/dev/null | grep -q "^\$ANSIBLE_VAULT;1\.2;AES256;lab"' _ "$_M08D_SRC"
