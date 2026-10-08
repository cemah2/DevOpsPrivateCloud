# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
#
# check-E24.sh — M09-E24 « Le fencing à l'épreuve »
# Lecture seule : API du cluster (pvesh get), configuration des VMs 2091-2093 sur pve01 (qm config),
# réglages et modules des nœuds, code OpenTofu et Ansible de adm01, documentation sur GitLab.

# shellcheck source=_m09-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-production.sh"

title "M09-E24 — Le fencing à l'épreuve"
require_cmd jq ssh
_m09p_charger

title "Cluster"
check_cmd "cluster quorate, trois nœuds en ligne" _m09p_quorate_3
check_cmd "aucune ressource HA en error, fence ou recovery" _m09p_ha_sans_erreur

title "VMs de test 120 et 121"
_m09_e24_ha() {
  _m09p_pvesh_jq /cluster/ha/status/current '
    [.[] | select(.type == "service" and (.sid == "vm:120" or .sid == "vm:121"))] as $s
    | ($s | length) == 2 and ($s | all(.state == "started")) and ($s[0].node != $s[1].node)'
}
check_cmd "vm:120 et vm:121 : ressources HA « started », sur deux nœuds différents" _m09_e24_ha
_m09_e24_ceph() {
  local id c
  for id in 120 121; do
    c="$(_m09p_vm_config "$id" 2>/dev/null)" || return 1
    grep -Eq '^(scsi|virtio|sata)0: ceph-vm:' <<<"$c" || return 1
  done
}
check_cmd "vm:120 et vm:121 : disque système sur ceph-vm" _m09_e24_ceph
_m09_e24_regles() {
  _m09p_pvesh_jq /cluster/ha/rules '
    (any(.[]; .type == "node-affinity" and ((.resources // "") | tostring | test("vm:120"))))
    and (any(.[]; .type == "resource-affinity" and .affinity == "negative"
         and ((.resources // "") | tostring | test("vm:120")) and ((.resources // "") | tostring | test("vm:121"))))'
}
check_cmd "règles HA : affinité de nœud pour vm:120, affinité négative entre vm:120 et vm:121" _m09_e24_regles

title "Chien de garde émulé (pve01 et code OpenTofu)"
for _m09_e24_n in "${_M09P_NOEUDS[@]}"; do
  _m09_e24_id="${_M09P_VMID[$_m09_e24_n]}"
  check_ssh_output "VM $_m09_e24_id ($_m09_e24_n) : chien de garde i6300esb, action reset" "$WB_PVE_HOST" \
    '^watchdog: .*(model=)?i6300esb.*action=reset|^watchdog: .*action=reset.*i6300esb' "qm config $_m09_e24_id"
done
check_cmd "code OpenTofu de l'état hv : bloc watchdog i6300esb" \
  bash -c 'grep -rqsE "model[[:space:]]*=[[:space:]]*\"i6300esb\"" "$1"/*.tf' _ "$_M09P_SRC/infra/hv"

title "watchdog-mux sur les nœuds"
for _m09_e24_n in "${_M09P_NOEUDS[@]}"; do
  check_ssh "$_m09_e24_n : WATCHDOG_MODULE=i6300esb, module chargé, softdog absent, watchdog-mux actif" "$_m09_e24_n" \
    'grep -Eq "^WATCHDOG_MODULE=i6300esb" /etc/default/pve-ha-manager && lsmod | grep -q "^i6300esb " && ! lsmod | grep -q "^softdog " && systemctl is-active --quiet watchdog-mux'
  check_ssh "$_m09_e24_n : aucune règle nftables qui bloque Corosync" "$_m09_e24_n" \
    '! nft list ruleset 2>/dev/null | grep -Eq "dport 5405-5412 drop|dport \{? ?5405"'
done
check_cmd "rôle pve_noeud : réglage WATCHDOG_MODULE dans le code Ansible" \
  bash -c 'grep -rqs "WATCHDOG_MODULE" "$1"/roles/pve_noeud/' _ "$_M09P_SRC/ansible"

title "Compte rendu"
_m09_e24_cr() {
  local c
  c="$(_m09p_doc_contenu tests fencing-hv-par1)" || return 1
  (($(grep -c 'RTO' <<<"$c") >= 3))
}
check_cmd "docs/virtualisation/tests/fencing-hv-par1.md sur main, au moins trois mesures de RTO" _m09_e24_cr
