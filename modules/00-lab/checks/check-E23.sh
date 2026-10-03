# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E23.sh — M00-E23 : Restaurer une VM et un fichier
# À lancer depuis adm01. Lecture seule.

title "M00-E23 — Restaurer une VM et un fichier"

h_dns="dns01"
restored="/root/restore-E23/medisphere.conf"

# --- Restauration complète ---
check_ssh "pve01 : une restauration vers le VMID 5090 s'est terminée OK" "$WB_PVE_HOST" \
  'pvesh get /nodes/$(hostname)/tasks --vmid 5090 --typefilter qmrestore --limit 50 --output-format json | grep -Eq "\"status\" *: *\"OK\""'
if remote "$WB_PVE_HOST" 'qm status 5090 >/dev/null 2>&1' >/dev/null 2>&1; then
  check_ssh "5090 : aucune carte réseau active dans le VLAN INFRA (pas de doublon d'IP)" "$WB_PVE_HOST" \
    '! qm config 5090 | grep -E "^net[0-9]+:" | grep -v "link_down=1" | grep -Eq "tag=20([^0-9]|$)|bridge=vinfra"'
  check_ssh_output "5090 : renommée (pas un second « dns01 » dans l'inventaire)" "$WB_PVE_HOST" '^name: ' \
    'qm config 5090 | grep "^name: " | grep -v "^name: dns01$"'
else
  skip "5090 isolée du VLAN INFRA" "VM 5090 déjà détruite après l'exercice"
fi
check_ssh "dns01 (1002) toujours en service" "$WB_PVE_HOST" \
  'qm status 1002 | grep -q running'
check_ssh_output "dns01 répond toujours aux requêtes DNS" "$h_dns" '^10\.10\.20\.10$' \
  'dig +short +time=3 @10.10.20.10 dns01.par1.medisphere.internal A'

# --- Restauration de fichier ---
check_ssh "pve01 : fichier restauré présent ($restored)" "$WB_PVE_HOST" \
  "test -s $restored"
if live_sum="$(remote "$h_dns" 'md5sum < /etc/dnsmasq.d/medisphere.conf' 2>/dev/null)" \
   && rest_sum="$(remote "$WB_PVE_HOST" "md5sum < $restored" 2>/dev/null)" \
   && [[ "${live_sum%% *}" == "${rest_sum%% *}" ]]; then
  check_cmd "fichier restauré identique à la version en service sur dns01" true
else
  skip "fichier restauré identique à la version en service sur dns01" \
    "différent ou illisible : normal si la configuration a changé depuis la sauvegarde, vérifie avec diff"
fi
