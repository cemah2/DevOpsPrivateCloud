# shellcheck shell=bash
# check-E41.sh — M00-E41 « Panne : les petits échanges passent, les gros bloquent » : état sain.
title "M00-E41 — Panne : les petits échanges passent, les gros bloquent"

check_ssh_output "gw01 : MTU de ens19.10" gw01 ' mtu 1500 ' "ip link show ens19.10"
check_ssh_output "gw01 : MTU de ens19.20" gw01 ' mtu 1500 ' "ip link show ens19.20"
check_ssh_output "gw01 : MTU de wg0 d'au moins 1300 octets" gw01 ' mtu (1[3-9][0-9]{2}|[2-9][0-9]{3}) ' "ip link show wg0"
check_cmd "adm01 → dns01 : paquet de 1500 octets non fragmentable" ping -M 'do' -s 1472 -c 2 -W 3 10.10.20.10
check_ssh "dns01 → adm01 : paquet de 1500 octets non fragmentable" dns01 "ping -M do -s 1472 -c 2 -W 3 10.10.10.10"
check_ssh "pve01 → pbs01 : paquet de 1300 octets non fragmentable à travers le tunnel" "$WB_PVE_HOST" \
  "ping -M do -s 1272 -c 2 -W 3 10.20.10.10"
# Transferts TCP volumineux dans les deux sens (délai borné : un trou noir PMTU les fige).
check_cmd "transfert de 2 Mo dns01 → adm01 (SSH)" timeout 30 bash -c \
  'ssh -o BatchMode=yes dns01 "head -c 2000000 /dev/zero" | wc -c | grep -qx 2000000'
check_cmd "transfert de 2 Mo adm01 → dns01 (SSH)" timeout 30 bash -c \
  'head -c 2000000 /dev/zero | ssh -o BatchMode=yes dns01 "wc -c" | grep -qx 2000000'
check_ssh "dns01 : téléchargement HTTP depuis deb.debian.org" dns01 \
  "timeout 30 bash -c 'exec 3<>/dev/tcp/deb.debian.org/80; printf \"GET /debian/dists/trixie/Release HTTP/1.0\r\nHost: deb.debian.org\r\n\r\n\" >&3; cat <&3 | wc -c' | awk '{exit !(\$1 > 50000)}'"
