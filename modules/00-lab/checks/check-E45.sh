# shellcheck shell=bash
# check-E45.sh — M00-E45 « Panne : horloges désynchronisées » : retour à l'état sain.
title "M00-E45 — Panne : horloges désynchronisées"

check_ssh "gw01 : chrony actif" gw01 "systemctl is-active -q chrony"
check_ssh "dns01 : chrony actif" dns01 "systemctl is-active -q chrony"
check_ssh "dns01 : chrony démarre au boot" dns01 "systemctl is-enabled -q chrony"
check_cmd "adm01 : chrony actif" systemctl is-active -q chrony
check_ssh_output "gw01 : synchronisé sur une source externe" gw01 '^\^\*' "sudo -n chronyc -n sources"
check_ssh_output "dns01 : synchronisé sur la passerelle de son VLAN" dns01 '^\^\*[[:space:]]+10\.10\.20\.1[[:space:]]' \
  "sudo -n chronyc -n sources"
check_output "adm01 : synchronisé sur la passerelle de son VLAN" '^\^\*[[:space:]]+10\.10\.10\.1[[:space:]]' \
  sudo -n chronyc -n sources
check_ssh "dns01 : écart d'horloge avec adm01 inférieur à 2 s" dns01 \
  "d=\$(( \$(date +%s) - $(date +%s) )); [ \${d#-} -le 2 ]"
check_ssh "gw01 : écart d'horloge avec adm01 inférieur à 2 s" gw01 \
  "d=\$(( \$(date +%s) - $(date +%s) )); [ \${d#-} -le 2 ]"
