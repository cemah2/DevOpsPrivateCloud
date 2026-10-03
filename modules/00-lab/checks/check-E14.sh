# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E14.sh — M00-E14 : DHCP du VLAN SANDBOX par relais
# Lancé depuis pve01 (avant E15) ou depuis adm01 (après E15). Lecture seule.

title "M00-E14 — DHCP du VLAN SANDBOX par relais"

h_dns="dns01"
if ! remote dns01 true >/dev/null 2>&1; then h_dns="admin@10.10.20.10"; fi
h_gw="gw01"
if ! remote gw01 true >/dev/null 2>&1; then h_gw="admin@10.10.10.1"; fi

# --- Relais sur gw01 ---
check_ssh "gw01 : un service écoute en UDP 67 (relais DHCP)" "$h_gw" \
  'ss -Hlnu "sport = :67" | grep -q .'
check_ssh "gw01 : aucun service DNS exposé par le relais (port 53 fermé hors boucle locale)" "$h_gw" \
  '! ss -Hlnu "sport = :53" | grep -Ev "(127\.[0-9.]+|\[::1\]):53" | grep -q .'
check_ssh "gw01 : la chaîne input reste en politique drop" "$h_gw" \
  'sudo -n nft list chain inet filter input | grep -q "policy drop"'

# --- Serveur sur dns01 ---
check_ssh "dns01 : plage DHCP 10.10.99.100-10.10.99.199 déclarée" "$h_dns" \
  'grep -Ehs "^[[:space:]]*dhcp-range=" /etc/dnsmasq.conf /etc/dnsmasq.d/* | grep -q "10\.10\.99\.100,10\.10\.99\.199"'
check_ssh "dns01 : n'a aucune adresse dans le VLAN 99 (il sert le VLAN à distance)" "$h_dns" \
  '! ip -4 -br addr | grep -q "10\.10\.99\."'
check_ssh "dns01 : au moins un bail attribué dans 10.10.99.100-199" "$h_dns" \
  'sudo -n grep -Eq " 10\.10\.99\.1[0-9]{2} " /var/lib/misc/dnsmasq.leases'

# --- VM de test (facultatif : la VM peut déjà avoir été détruite) ---
if remote "$WB_PVE_HOST" 'qm status 5001 2>/dev/null | grep -q running' >/dev/null 2>&1; then
  check_ssh_output "sbx01 (5001) a une adresse 10.10.99.100-199" "$WB_PVE_HOST" '10\.10\.99\.1[0-9]{2}' \
    'qm guest cmd 5001 network-get-interfaces'
  check_ssh_output "sbx01.par1.medisphere.internal se résout (nom annoncé en DHCP)" "$h_dns" '^10\.10\.99\.1[0-9]{2}$' \
    'dig +short +time=3 @10.10.20.10 sbx01.par1.medisphere.internal A'
else
  skip "sbx01 (5001) a obtenu son adresse par DHCP" "VM 5001 absente ou arrêtée : le bail sur dns01 fait foi"
fi
