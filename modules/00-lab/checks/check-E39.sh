# shellcheck shell=bash
# check-E39.sh — M00-E39 « Panne : adm01 ne joint plus dns01 » : retour à l'état sain.
title "M00-E39 — Panne : adm01 ne joint plus dns01"

check_ping "adm01 → dns01 (ICMP)" 10.10.20.10
check_ssh "adm01 → dns01 (SSH)" dns01 "true"
check_port "adm01 → dns01 (DNS TCP/53)" 10.10.20.10 53
check_ssh_output "pve01 : la carte réseau de dns01 est sur le réseau INFRA" "$WB_PVE_HOST" \
  '(bridge=vinfra|tag=20)([,[:space:]]|$)' "qm config 1002 | grep '^net0:'"
check_ssh_output "dns01 : adresse 10.10.20.10/24" dns01 'inet 10\.10\.20\.10/24 ' "ip -o -4 addr show"
check_ssh_output "dns01 : route par défaut via 10.10.20.1" dns01 '^default via 10\.10\.20\.1 ' "ip route show default"
check_ssh "dns01 : sortie vers les autres VLANs (ping de la passerelle MGMT)" dns01 "ping -c 2 -W 3 10.10.10.1"
