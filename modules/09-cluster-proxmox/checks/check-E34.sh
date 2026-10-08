# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
#
# check-E34.sh — M09-E34 « Remplacer un nœud en temps limité » (hv02, VMID 2092)
# À lancer à T5. Lecture seule : journal des tâches de pve01, API du cluster, Ceph (JSON), état
# local de hv02 (modules, pare-feu, ZFS, keepalived, sshd), certificat servi, sonde ms-verif-cluster.

# shellcheck source=_m09-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-production.sh"

title "M09-E34 — Remplacer un nœud en temps limité (hv02)"
require_cmd jq ssh openssl
_m09p_charger
_m09_e34_h="root@hv02.$_M09P_ZONE"

title "Nouveau matériel (exigence 3)"
check_cmd "VM 2092 recréée depuis moins de 48 h (tâche de création sur pve01)" _m09p_creations_min 2092 1 172800
check_cmd "VM 2092 créée au moins deux fois depuis le début du module" _m09p_creations_min 2092 2

title "Réintégration (exigence 4)"
check_cmd "cluster quorate, trois nœuds en ligne" _m09p_quorate_3
check_ssh "hv02 : deux liens Corosync connectés" "$_m09_e34_h" \
  's=$(corosync-cfgtool -s); [ "$(printf "%s\n" "$s" | grep -c "^LINK ID")" -ge 2 ] && ! printf "%s\n" "$s" | grep -qi "disconnected"'
check_cmd "Ceph : hv02 porte un MON en quorum" _m09p_ceph_jq status '.quorum_names | index("hv02") != null'
check_cmd "Ceph : hv02 porte un MGR (actif ou en attente)" _m09p_ceph_jq "mgr dump" \
  '.active_name == "hv02" or any(.standbys[]?; .name == "hv02")'
check_ssh "Ceph : hv02 porte deux OSD" "root@hv01.$_M09P_ZONE" '[ "$(ceph osd ls-tree hv02 | wc -l)" -eq 2 ]'
check_ssh "hv02 : chien de garde i6300esb chargé, softdog absent" "$_m09_e34_h" \
  'lsmod | grep -q "^i6300esb " && ! lsmod | grep -q "^softdog "'
check_ssh "hv02 : pare-feu du nœud actif" "$_m09_e34_h" \
  '! grep -qs "^enable: 0" /etc/pve/nodes/hv02/host.fw && pve-firewall status | grep -q "enabled/running"'
check_cmd "hv02 : certificat 8006 de la PKI MédiSphère valide" _m09p_cert_ok "hv02.$_M09P_ZONE" 8006 10
check_ssh "hv02 : pool ZFS tank en ligne, keepalived actif" "$_m09_e34_h" \
  'zpool list -H -o health tank | grep -qx ONLINE && systemctl is-active --quiet keepalived'
check_ssh_output "hv02 : sshd refuse les mots de passe" "$_m09_e34_h" '^passwordauthentication no$' 'sshd -T 2>/dev/null'
_m09_e34_repli() {
  local n j t ok=0
  t="$(date +%s)"
  for n in "${_M09P_NOEUDS[@]}"; do
    j="$(_m09p_hv "$n" "pvesh get /nodes/$n/replication --output-format json" 2>/dev/null)" || return 1
    jq -e 'all(.[]; (.fail_count // 0) == 0)' >/dev/null <<<"$j" || return 1
    if jq -e --argjson t "$t" 'any(.[]; .target == "hv02" and ($t - (.last_sync // 0)) < 3600)' >/dev/null <<<"$j"; then ok=1; fi
  done
  ((ok == 1))
}
check_cmd "réplication vers hv02 rétablie (synchronisée depuis moins d'une heure, aucun échec)" _m09_e34_repli

title "Retour au nominal (exigence 5)"
check_cmd "Ceph en HEALTH_OK, 6 OSD existants, up et in" _m09p_ceph_jq status \
  '.health.status == "HEALTH_OK" and .osdmap.num_osds == 6 and .osdmap.num_up_osds == 6 and .osdmap.num_in_osds == 6'
check_ssh "aucun nœud fantôme (/etc/pve/nodes = hv01, hv02, hv03)" "root@hv01.$_M09P_ZONE" \
  '[ "$(ls /etc/pve/nodes | sort | tr "\n" " ")" = "hv01 hv02 hv03 " ]'
check_cmd "aucune ressource HA en error, fence ou recovery" _m09p_ha_sans_erreur
check_cmd "vm:120 (fence01) revenue sur hv02" _m09p_pvesh_jq /cluster/ha/status/current \
  'any(.[]; .type == "service" and .sid == "vm:120" and .state == "started" and .node == "hv02")'
check_cmd "ms-verif-cluster au vert" timeout 180 /usr/local/bin/ms-verif-cluster --quiet
