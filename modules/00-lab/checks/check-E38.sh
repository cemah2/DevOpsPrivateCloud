# shellcheck shell=bash
# check-E38.sh — M00-E38 « Panne : plus d'accès Internet depuis INFRA » : retour à l'état sain.
title "M00-E38 — Panne : plus d'accès Internet depuis INFRA"

check_ssh_output "gw01 : routage IPv4 actif" gw01 '^1$' "sysctl -n net.ipv4.ip_forward"
check_ssh "gw01 : routage IPv4 actif au prochain redémarrage" gw01 \
  "grep -Ehs '^[[:space:]]*net\.ipv4\.ip_forward[[:space:]]*=' /etc/sysctl.conf /etc/sysctl.d/*.conf | tail -n 1 | grep -Eq '=[[:space:]]*1[[:space:]]*\$'"
check_ssh_output "gw01 : traduction d'adresses sortante vers le WAN" gw01 \
  '(oifname|oif) "?ens18"?.*masquerade' "sudo -n nft list chain ip nat postrouting"
check_ssh "dns01 : Internet joignable en ICMP" dns01 "ping -c 2 -W 3 9.9.9.9"
check_ssh "dns01 : Internet joignable en TCP/443" dns01 "timeout 5 bash -c 'exec 3<>/dev/tcp/1.1.1.1/443'"
check_ssh "dns01 : dépôt Debian joignable par son nom (HTTP)" dns01 "timeout 10 bash -c 'exec 3<>/dev/tcp/deb.debian.org/80'"
check_cmd "adm01 : Internet joignable en TCP/443" timeout 5 bash -c 'exec 3<>/dev/tcp/1.1.1.1/443'
