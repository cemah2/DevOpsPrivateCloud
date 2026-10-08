# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant ou par bash -c
#
# check-E46.sh — M09-E46 « Mini-projet : virtualisation MédiSphère v1 »
# Contrôle global PENDANT LA RECETTE (avant le nettoyage d'après-recette, auto-évalué) : cluster
# reconstruit, Ceph, stockages, HA, réplication, sauvegardes, SDN, droits, sécurité, supervision,
# documentation et hygiène. Lecture seule : pvesh get, ceph … --format json, fichiers de /etc/pve,
# qm config / tâches de pve01, essais TCP depuis gw01, API GitLab en GET. Durée : 2 à 4 minutes.

# shellcheck source=_m09-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-production.sh"

title "M09-E46 — Virtualisation MédiSphère v1 : contrôle global"
require_cmd jq ssh openssl
_m09p_charger
_m09_e46_ref="$(_m09p_noeud 2>/dev/null || echo hv01)"

# --- 1. Reconstruction ----------------------------------------------------------------------------
title "1/9 Nœuds reconstruits depuis le code"
_m09_e46_pve="$(remote "$WB_PVE_HOST" 'pvesh get /cluster/resources --type vm --output-format json' 2>/dev/null)" || _m09_e46_pve=null
for _m09_e46_n in "${_M09P_NOEUDS[@]}"; do
  _m09_e46_id="${_M09P_VMID[$_m09_e46_n]}"
  check_cmd "VM $_m09_e46_id $_m09_e46_n : démarrée, pool lab, étiquette env-m09" \
    jq -e --argjson id "$_m09_e46_id" --arg n "$_m09_e46_n" '.[] | select(.vmid == $id)
      | .name == $n and .status == "running" and .pool == "lab" and (((.tags // "") | split(";")) | index("env-m09"))' \
    <<<"$_m09_e46_pve"
  check_cmd "VM $_m09_e46_id : recréée depuis moins de 14 jours (reconstruction de la v1)" \
    _m09p_creations_min "$_m09_e46_id" 1 1209600
  check_ssh_output "VM $_m09_e46_id : chien de garde i6300esb (reset)" "$WB_PVE_HOST" 'i6300esb.*reset|reset.*i6300esb' \
    "qm config $_m09_e46_id | grep '^watchdog:'"
done
check_cmd "ceph01-03 arrêtées (budget mémoire du profil infra)" \
  jq -e '[.[] | select(.vmid >= 2081 and .vmid <= 2083 and .status == "running")] | length == 0' <<<"$_m09_e46_pve"
check_cmd "journal de reconstruction sur main (docs/virtualisation/tests/reconstruction-hv-par1.md)" \
  _m09p_doc tests reconstruction-hv-par1

# --- 2. Cluster -----------------------------------------------------------------------------------
title "2/9 Cluster hv-par1"
check_cmd "cluster hv-par1 quorate, trois nœuds en ligne" _m09p_pvesh_jq /cluster/status \
  '(.[] | select(.type == "cluster") | .name == "hv-par1" and .quorate == 1)
   and ([.[] | select(.type == "node" and .online == 1)] | length) == 3'
check_ssh "corosync.conf : deux liens par nœud, pas de QDevice" "$_m09_e46_ref" \
  '[ "$(grep -c "ring0_addr: *10\.10\.32\." /etc/pve/corosync.conf)" = 3 ] && [ "$(grep -c "ring1_addr: *10\.10\.10\.5" /etc/pve/corosync.conf)" = 3 ] && ! grep -q "device" /etc/pve/corosync.conf'
for _m09_e46_n in "${_M09P_NOEUDS[@]}"; do
  check_ssh "$_m09_e46_n : liens Corosync connectés, i6300esb chargé, sauvegarde de configuration active" "$_m09_e46_n" \
    's=$(corosync-cfgtool -s); ! printf "%s\n" "$s" | grep -qi disconnected && lsmod | grep -q "^i6300esb " && systemctl is-active --quiet wb-backup-socle.timer'
done
check_cmd "VIP portée par un seul nœud" _m09p_vip_unique
check_ssh_output "migration secure sur 10.10.30.0/24" "$_m09_e46_ref" '^migration: (.*,)?network=10\.10\.30\.0/24' 'cat /etc/pve/datacenter.cfg'

# --- 3. Ceph et stockages -------------------------------------------------------------------------
title "3/9 Ceph et stockages"
check_cmd "Ceph en HEALTH_OK, 3 MON, 6 OSD up et in" _m09p_ceph_jq status \
  '.health.status == "HEALTH_OK" and (.quorum_names | length) == 3 and .osdmap.num_osds == 6 and .osdmap.num_up_osds == 6 and .osdmap.num_in_osds == 6'
check_cmd "Ceph Tentacle 20.2 partout, require_osd_release tentacle" _m09p_ceph_jq versions \
  '.overall | keys | length > 0 and all(test(" 20\\.2\\."))'
check_cmd "require_osd_release = tentacle" _m09p_ceph_jq "osd dump" '.require_osd_release == "tentacle"'
check_cmd "pool ceph-vm : size 3, min_size 2" _m09p_ceph_jq "osd pool ls detail" \
  'any(.[]; .pool_name == "ceph-vm" and .size == 3 and .min_size == 2)'
for _m09_e46_s in ceph-vm zfs-local pbs-par2; do
  check_ssh "stockage $_m09_e46_s actif" "$_m09_e46_ref" "pvesm status --storage $_m09_e46_s 2>/dev/null | awk 'NR > 1 {print \$3}' | grep -qx active"
done
check_ssh "stockage externe ceph-par1-rbd retiré (E12 nettoyé)" "$_m09_e46_ref" '! grep -Eq "^rbd: *ceph-par1-rbd" /etc/pve/storage.cfg'
check_ssh "sauvegardes chiffrées (clé du stockage pbs-par2 présente)" "$_m09_e46_ref" 'test -s /etc/pve/priv/storage/pbs-par2.enc'

# --- 4. HA, réplication, sauvegardes --------------------------------------------------------------
title "4/9 HA, réplication, sauvegardes"
check_cmd "ressources HA présentes, aucune en error, fence ou recovery" _m09p_pvesh_jq /cluster/ha/status/current \
  '([.[] | select(.type == "service")] | length) > 0
   and ([.[] | select(.type == "service" and ((.state // "") | test("^(error|fence|recovery)$")))] | length) == 0'
check_cmd "règles HA : au moins une affinité de nœud et une affinité de ressources" _m09p_pvesh_jq /cluster/ha/rules \
  'any(.[]; .type == "node-affinity") and any(.[]; .type == "resource-affinity")'
_m09_e46_repli() {
  local n j nb=0
  for n in "${_M09P_NOEUDS[@]}"; do
    j="$(_m09p_hv "$n" "pvesh get /nodes/$n/replication --output-format json" 2>/dev/null)" || return 1
    jq -e 'all(.[]; (.fail_count // 0) == 0)' >/dev/null <<<"$j" || return 1
    nb=$((nb + $(jq 'length' <<<"$j")))
  done
  ((nb > 0))
}
check_cmd "réplication ZFS : au moins une tâche, aucun échec" _m09_e46_repli
check_cmd "dernière sauvegarde du cluster réussie il y a moins de 26 h" _m09p_pvesh_jq /cluster/tasks \
  '([.[] | select(.type == "vzdump" and (.endtime // 0) > 0)] | sort_by(.endtime) | last) as $d
   | $d != null and $d.status == "OK" and (now - $d.endtime) < 93600'

# --- 5. SDN, droits ---------------------------------------------------------------------------------
title "5/9 SDN et droits"
check_cmd "SDN : zone VLAN invites et une zone EVPN" _m09p_pvesh_jq /cluster/sdn/zones \
  'any(.[]; .zone == "invites" and .type == "vlan") and any(.[]; .type == "evpn")'
check_cmd "SDN : VNets vinv99 et vevpn1" _m09p_pvesh_jq /cluster/sdn/vnets \
  'any(.[]; .vnet == "vinv99") and any(.[]; .vnet == "vevpn1")'
check_cmd "groupes hv-admins et hv-ops" _m09p_pvesh_jq /access/groups \
  'any(.[]; .groupid == "hv-admins") and any(.[]; .groupid == "hv-ops")'
check_cmd "pools prod et recette" _m09p_pvesh_jq /pools 'any(.[]; .poolid == "prod") and any(.[]; .poolid == "recette")'

# --- 6. Sécurité ------------------------------------------------------------------------------------
title "6/9 Sécurité"
check_ssh_output "pare-feu de cluster activé" "$_m09_e46_ref" '^enable: 1$' 'cat /etc/pve/firewall/cluster.fw'
check_cmd "gw01 → hv01:8006 refusé" _m09p_port_ferme gw01 10.10.10.51 8006
for _m09_e46_n in hv01 hv02 hv03 hv; do
  check_cmd "$_m09_e46_n.$_M09P_ZONE:8006 : certificat de la PKI MédiSphère valide" _m09p_cert_ok "$_m09_e46_n.$_M09P_ZONE" 8006 10
done
check_cmd "TOTP pour root@pam" _m09p_pvesh_jq /access/tfa 'any(.[]; .userid == "root@pam" and any(.entries[]?; .type == "totp"))'
check_cmd "SSH sans mot de passe sur les trois nœuds" _m09p_tous 'sshd -T 2>/dev/null | grep -qx "passwordauthentication no"'

# --- 7. Supervision ---------------------------------------------------------------------------------
title "7/9 Supervision"
check_cmd "minuterie ms-verif-cluster active sur adm01" systemctl is-active --quiet ms-verif-cluster.timer
check_cmd "ms-verif-cluster au vert" timeout 180 /usr/local/bin/ms-verif-cluster --quiet
check_cmd "ms-capacite-cluster : la perte d'un nœud serait absorbée" timeout 120 /usr/local/bin/ms-capacite-cluster --quiet

# --- 8. Documentation -------------------------------------------------------------------------------
title "8/9 Documentation (plateforme/medisphere, main)"
check_cmd "docs/virtualisation/hv-par1.md" _m09p_doc "" hv-par1
for _m09_e46_d in RB-090 RB-091 RB-092; do
  check_cmd "runbook $_m09_e46_d" _m09p_doc runbooks "$_m09_e46_d"
done
check_cmd "ADR-0090" _m09p_doc adr ADR-0090
check_cmd "matrice des flux du cluster" _m09p_doc "" matrice-flux-hv-par1

# --- 9. Hygiène -------------------------------------------------------------------------------------
title "9/9 Hygiène"
check_cmd "aucune panne M09 encore active (lab/bin/break)" \
  bash -c '! ls "${XDG_STATE_HOME:-$HOME/.local/state}"/workbook/pannes-actives/M09-* >/dev/null 2>&1'
_m09_e46_pipeline() {
  gitlab_api "projects/plateforme%2F$1/pipelines?ref=main&per_page=1" 2>/dev/null | jq -e '.[0].status == "success"' >/dev/null
}
check_cmd "plateforme/infra : dernier pipeline de main réussi" _m09_e46_pipeline infra
check_cmd "plateforme/ansible : dernier pipeline de main réussi" _m09_e46_pipeline ansible
check_cmd "plateforme/outils : dernier pipeline de main réussi" _m09_e46_pipeline outils
