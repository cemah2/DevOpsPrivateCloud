# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E20.sh — M00-E20 : Réinstaller hp01 en Proxmox Backup Server
# À lancer depuis adm01. Lecture seule.
#
# Accès à pbs01 :
#   - par le tunnel (alias SSH $WB_PBS_HOST → 10.20.10.10) dès que M00-E21 est fait ;
#   - sinon par son adresse LAN, si WB_PBS_LAN est renseignée dans lab/lab.env
#     (connexion root@<IP-HP01-LAN>, à initialiser une fois à la main pour la clé d'hôte) ;
#   - sinon, les contrôles sont ignorés.

title "M00-E20 — Réinstaller hp01 en Proxmox Backup Server"

h_pbs=""
pbs_ip=""
if remote "$WB_PBS_HOST" true >/dev/null 2>&1; then
  h_pbs="$WB_PBS_HOST"; pbs_ip="10.20.10.10"
elif [[ -n "${WB_PBS_LAN:-}" ]]; then
  h_pbs="root@${WB_PBS_LAN}"; pbs_ip="$WB_PBS_LAN"
fi

if [[ -z "$h_pbs" ]]; then
  skip "contrôles de pbs01" "ni l'alias $WB_PBS_HOST ni WB_PBS_LAN (lab/lab.env) ne mènent à pbs01"
  check_cmd "pbs01 joignable depuis adm01 (tunnel ou adresse LAN WB_PBS_LAN)" false
else
  check_port "interface web PBS (TCP 8007) sur $pbs_ip" "$pbs_ip" 8007
  check_ssh "SSH root sur pbs01 ($h_pbs) sans interaction" "$h_pbs" 'true'
  check_ssh_output "nom d'hôte court : pbs01" "$h_pbs" '^pbs01$' 'hostname -s'
  check_ssh_output "FQDN : pbs01.par2.medisphere.internal" "$h_pbs" '^pbs01\.par2\.medisphere\.internal$' 'hostname -f'
  check_ssh_output "Proxmox Backup Server en version 4.x" "$h_pbs" 'proxmox-backup-server[^0-9]*4\.' \
    'proxmox-backup-manager versions'
  check_ssh "dépôt pbs-no-subscription configuré" "$h_pbs" \
    'grep -Rqs "pbs-no-subscription" /etc/apt/sources.list /etc/apt/sources.list.d/'
  check_ssh "dépôt pbs-enterprise désactivé (pas d'erreur 401 à chaque apt update)" "$h_pbs" \
    '! grep -Eqs "^[[:space:]]*deb .*pbs-enterprise" /etc/apt/sources.list /etc/apt/sources.list.d/*.list && ! cat /etc/apt/sources.list.d/*.sources 2>/dev/null | awk -v RS= "/pbs-enterprise/ && !/Enabled:[[:space:]]*(no|false)/ {f=1} END {exit !f}"'
  check_ssh "vmbr1 porte 10.20.10.10/24" "$h_pbs" \
    'ip -4 -br addr show dev vmbr1 | grep -q "10\.20\.10\.10/24"'
  check_ssh "aucune mise à jour Proxmox en attente" "$h_pbs" \
    '! apt list --upgradable 2>/dev/null | grep -Eq "^(proxmox-|pbs-|libproxmox)"'
fi
