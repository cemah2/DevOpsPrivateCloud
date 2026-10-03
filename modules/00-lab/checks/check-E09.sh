# shellcheck shell=bash
# M00-E09 — Créer le bridge du lab vmbr1.
# Lecture seule. Les contrôles s'exécutent sur pve01 (WB_PVE_HOST).

title "M00-E09 — Créer le bridge du lab vmbr1"

check_ssh "le bridge vmbr1 existe" "$WB_PVE_HOST" "ip link show dev vmbr1"
check_ssh_output "vmbr1 est VLAN-aware (filtrage VLAN actif dans le noyau)" "$WB_PVE_HOST" \
  'vlan_filtering 1' "ip -d link show dev vmbr1"
check_ssh "vmbr1 n'a aucun port physique" "$WB_PVE_HOST" \
  "ip link show dev vmbr1 >/dev/null 2>&1 && ! ip -o link show master vmbr1 | awk -F': ' '{print \$2}' | grep -Evq '^(tap|fwpr|fwln|veth)'"
check_ssh "vmbr1 n'a pas d'adresse IP sur pve01 (hors lien local IPv6)" "$WB_PVE_HOST" \
  "ip link show dev vmbr1 >/dev/null 2>&1 && ! ip -o addr show dev vmbr1 | grep -v 'inet6 fe80:' | grep -Eq 'inet6? '"
check_ssh_output "configuration persistante : bridge-vlan-aware yes" "$WB_PVE_HOST" \
  'bridge-vlan-aware[[:space:]]+yes' "ifquery vmbr1"
check_ssh_output "configuration persistante : bridge-ports none" "$WB_PVE_HOST" \
  'bridge-ports[[:space:]]+none' "ifquery vmbr1"
check_ssh_output "configuration persistante : bridge-vids 2-4094" "$WB_PVE_HOST" \
  'bridge-vids[[:space:]]+2-4094' "ifquery vmbr1"
check_ssh_output "vmbr0 est toujours actif avec une adresse IPv4" "$WB_PVE_HOST" \
  '[[:space:]]UP[[:space:]]+([0-9]+\.){3}[0-9]+/' "ip -4 -br addr show dev vmbr0"
check_ssh "aucun retour arrière réseau programmé ne reste actif" "$WB_PVE_HOST" \
  "! systemctl is-active --quiet retour-reseau.timer"
check_ssh "wb-admins a le rôle PVESDNUser sur /sdn/zones/localnetwork/vmbr1" "$WB_PVE_HOST" \
  "pvesh get /access/acl --output-format json | perl -MJSON::PP -0777 -ne 'exit(!grep { \$_->{path} eq q{/sdn/zones/localnetwork/vmbr1} && \$_->{ugid} eq q{wb-admins} && \$_->{roleid} eq q{PVESDNUser} } @{decode_json(\$_)})'"
