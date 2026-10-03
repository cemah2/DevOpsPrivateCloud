# shellcheck shell=bash
# Vérification M00-E28 — Migrer le réseau du lab vers Proxmox SDN (lancé depuis adm01).

title "M00-E28 — Migrer le réseau du lab vers Proxmox SDN"
require_cmd ssh dig curl

# --- Zone -------------------------------------------------------------------
check_ssh_output "la zone SDN lab est de type VLAN" "$WB_PVE_HOST" '"type" *: *"vlan"' \
  "pvesh get /cluster/sdn/zones/lab --output-format json"
check_ssh_output "la zone SDN lab s'appuie sur vmbr1" "$WB_PVE_HOST" '"bridge" *: *"vmbr1"' \
  "pvesh get /cluster/sdn/zones/lab --output-format json"

# --- VNets : existence, tag, zone, application sur l'hôte ------------------
for couple in vmgmt:10 vinfra:20 vstopub:30 vstoclu:31 vcoro:32 vk8s:40 vk8slb:41 \
              vosapi:50 vostun:51 vosext:52 vprov:60 vdmz:70 vsandbox:99; do
  vnet="${couple%%:*}"; tag="${couple##*:}"
  check_ssh_output "VNet $vnet : VLAN $tag" "$WB_PVE_HOST" "\"tag\" *: *\"?$tag\"?[,}]" \
    "pvesh get /cluster/sdn/vnets/$vnet --output-format json"
  check_ssh_output "VNet $vnet : zone lab" "$WB_PVE_HOST" '"zone" *: *"lab"' \
    "pvesh get /cluster/sdn/vnets/$vnet --output-format json"
  check_ssh "VNet $vnet : présent sur l'hôte (configuration appliquée)" "$WB_PVE_HOST" \
    "ip link show dev $vnet"
done

# --- VMs du socle ------------------------------------------------------------
check_ssh_output "dns01 (1002) est branchée sur vinfra" "$WB_PVE_HOST" '^net0: .*bridge=vinfra' \
  "qm config 1002 --current"
check_ssh_output "adm01 (1001) est branchée sur vmgmt" "$WB_PVE_HOST" '^net0: .*bridge=vmgmt' \
  "qm config 1001 --current"
check_ssh "dns01 et adm01 n'ont plus de tag VLAN sur leur interface" "$WB_PVE_HOST" \
  "! qm config 1001 --current | grep -E '^net0:.*tag=' && ! qm config 1002 --current | grep -E '^net0:.*tag='"
check_ssh_output "gw01 (1000) garde une interface trunk sur vmbr1" "$WB_PVE_HOST" \
  '^net[0-9]+: [^ ]*bridge=vmbr1(,|$)' "qm config 1000 --current"
check_ssh "l'interface trunk de gw01 n'est pas taguée" "$WB_PVE_HOST" \
  "! qm config 1000 --current | grep -E '^net[0-9]+: .*bridge=vmbr1.*tag='"

# --- Connectivité -------------------------------------------------------------
check_ping "adm01 joint dns01 (10.10.20.10)" 10.10.20.10
check_ping "adm01 joint sa passerelle (10.10.10.1)" 10.10.10.1
check_dns "résolution interne via dns01" adm01.par1.medisphere.internal A '^10\.10\.10\.10$' 10.10.20.10
check_dns "résolution d'un nom Internet via dns01" debian.org A '^[0-9.]+$' 10.10.20.10
check_cmd "adm01 accède à Internet (HTTPS)" curl -s -o /dev/null --max-time "$WB_TIMEOUT" https://deb.debian.org/

# --- Droits SDN.Use ------------------------------------------------------------
check_ssh_output "wb-admin@pve (groupe wb-admins) peut utiliser vinfra" "$WB_PVE_HOST" 'SDN\.Use' \
  "pveum user permissions wb-admin@pve --path /sdn/zones/lab/vinfra"
check_ssh_output "wb-automation@pve peut utiliser vsandbox" "$WB_PVE_HOST" 'SDN\.Use' \
  "pveum user permissions wb-automation@pve --path /sdn/zones/lab/vsandbox"
check_ssh_output "le jeton wb-automation@pve!lab peut utiliser vsandbox" "$WB_PVE_HOST" 'SDN\.Use' \
  "pveum user token permissions wb-automation@pve lab --path /sdn/zones/lab/vsandbox"
