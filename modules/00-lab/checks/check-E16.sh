# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E16.sh — M00-E16 : VPN d'administration WireGuard
# À lancer depuis adm01. Le poste client n'est pas joignable par les scripts :
# on vérifie l'état côté gw01 (interface, pair, session établie, filtrage). Lecture seule.

title "M00-E16 — VPN d'administration WireGuard"

h_gw="gw01"

check_ssh "gw01 : interface wg1 présente avec 10.255.1.1/24" "$h_gw" \
  'ip -4 -br addr show dev wg1 | grep -q "10\.255\.1\.1/24"'
check_ssh_output "gw01 : wg1 écoute sur UDP 51821" "$h_gw" '^51821$' \
  'sudo -n wg show wg1 listen-port'
check_ssh "gw01 : un pair déclaré pour 10.255.1.2/32" "$h_gw" \
  'sudo -n wg show wg1 allowed-ips | grep -q "10\.255\.1\.2/32"'
check_ssh "gw01 : au moins un pair a déjà établi une session (handshake)" "$h_gw" \
  'sudo -n wg show wg1 latest-handshakes | awk "\$2 > 0 {f=1} END {exit !f}"'
check_ssh "gw01 : wg-quick@wg1 activé au démarrage" "$h_gw" \
  'systemctl is-enabled --quiet wg-quick@wg1'
check_ssh_output "gw01 : /etc/wireguard/wg1.conf lisible par root seul" "$h_gw" '^600$' \
  'sudo -n stat -c %a /etc/wireguard/wg1.conf'
check_ssh "gw01 : UDP 51821 autorisé en entrée" "$h_gw" \
  'sudo -n nft list chain inet filter input | grep -Eq "udp dport (51821|\{[^}]*51821[^}]*\})"'
check_ssh "gw01 : des règles de transfert concernent wg1" "$h_gw" \
  'sudo -n nft list chain inet filter forward | grep -q "\"wg1\""'
check_ssh "gw01 : le trafic venant de wg1 n'est pas masqué (pas de NAT sur wg1)" "$h_gw" \
  '! sudo -n nft list table ip nat | grep -Eq "(iifname|ip saddr) .*(wg1|10\.255\.1\.)"'
check_ssh "gw01 : une règle de transfert ouvre le port 8006 (pve01) au VPN" "$h_gw" \
  'sudo -n nft list chain inet filter forward | grep "\"wg1\"" | grep -q "8006"'
check_ssh_output "pve01 : le VPN d'administration (10.255.1.0/24) est routé vers gw01" "$WB_PVE_HOST" \
  '^10\.255\.1\.0/24 via ([0-9]+\.){3}[0-9]+ dev vmbr0' 'ip -4 route show 10.255.1.0/24'
