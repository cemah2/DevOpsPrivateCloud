# shellcheck shell=bash
# Vérification M00-E31 — Temps synchronisé sur tout le lab (lancé depuis adm01).

title "M00-E31 — Temps synchronisé sur tout le lab"
require_cmd ssh

# --- gw01 : serveur -------------------------------------------------------------
check_ssh_output "gw01 est synchronisé" gw01 '^Leap status +: Normal' "chronyc -n tracking"
check_ssh_output "gw01 a une source Internet sélectionnée" gw01 '^\^\* ' "chronyc -n sources"
check_ssh_output "gw01 autorise le réseau PAR1 (test 10.10.10.10)" gw01 'allowed' \
  "sudo -n chronyc accheck 10.10.10.10"
check_ssh_output "gw01 autorise le réseau PAR2 (test 10.20.10.10)" gw01 'allowed' \
  "sudo -n chronyc accheck 10.20.10.10"
check_ssh_output "gw01 refuse une adresse hors du lab (test 203.0.113.10)" gw01 'denied' \
  "sudo -n chronyc accheck 203.0.113.10"
check_ssh_output "la chaîne input de gw01 contient une règle NTP" gw01 'udp dport (123|ntp)' \
  "sudo -n nft list chain inet filter input"
check_ssh_output "gw01 a déjà servi des clients NTP" gw01 '^10\.' "sudo -n chronyc -n clients"

# --- adm01 (local) ---------------------------------------------------------------
check_output "adm01 est synchronisé sur 10.10.10.1" '^\^\* 10\.10\.10\.1[[:space:]]' chronyc -n sources
check_output "adm01 : Leap status Normal" '^Leap status +: Normal' chronyc -n tracking
check_ssh "adm01 : systemd-timesyncd n'est pas actif" adm01 "! systemctl is-active --quiet systemd-timesyncd"

# --- dns01 -------------------------------------------------------------------------
check_ssh_output "dns01 est synchronisé sur 10.10.20.1" dns01 '^\^\* 10\.10\.20\.1[[:space:]]' "chronyc -n sources"
check_ssh "dns01 : systemd-timesyncd n'est pas actif" dns01 "! systemctl is-active --quiet systemd-timesyncd"

# --- pbs01 -------------------------------------------------------------------------
check_ssh_output "pbs01 est synchronisé sur gw01 via le tunnel" "$WB_PBS_HOST" \
  '^\^\* 10\.(10\.[0-9]+\.1|255\.0\.1)[[:space:]]' "chronyc -n sources"
check_ssh "pbs01 : systemd-timesyncd n'est pas actif" "$WB_PBS_HOST" "! systemctl is-active --quiet systemd-timesyncd"

# --- pve01 : choix libre, mais synchronisé -----------------------------------------
check_ssh_output "pve01 est synchronisé (source au choix)" "$WB_PVE_HOST" '^Leap status +: Normal' "chronyc -n tracking"
