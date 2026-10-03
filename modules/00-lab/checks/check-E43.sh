# shellcheck shell=bash
# check-E43.sh — M00-E43 « Panne : le site PAR2 est injoignable » : retour à l'état sain.
title "M00-E43 — Panne : le site PAR2 est injoignable"

# Les pings génèrent du trafic dans le tunnel, donc une poignée de main si la session a expiré.
check_ssh "gw01 → hp01 : extrémité du tunnel (10.255.0.2)" gw01 "ping -c 2 -W 3 10.255.0.2"
check_ping "adm01 → pbs01 (10.20.10.10)" 10.20.10.10
check_ssh "gw01 : poignée de main WireGuard récente sur wg0" gw01 \
  "t=\$(sudo -n wg show wg0 latest-handshakes | awk '{print \$2}' | sort -n | tail -n 1); [ -n \"\$t\" ] && [ \$(( \$(date +%s) - t )) -lt 180 ]"
check_ssh "pve01 → API de pbs01 (TCP/8007)" "$WB_PVE_HOST" "timeout 5 bash -c 'exec 3<>/dev/tcp/10.20.10.10/8007'"
check_ssh_output "pve01 : stockage pbs-par2 actif" "$WB_PVE_HOST" '^pbs-par2[[:space:]]+pbs[[:space:]]+active' \
  "pvesm status --storage pbs-par2"
check_ssh "adm01 → pbs01 (SSH)" "$WB_PBS_HOST" "true"
