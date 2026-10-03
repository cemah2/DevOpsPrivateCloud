# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E50.sh — M00-E50 « Mini-projet : livrer le socle MédiSphère v0 »
# Contrôle global du socle (à lancer depuis adm01) + présence du dossier de livraison.
# Lecture seule. Les contrôles détaillés de chaque brique restent dans leurs exercices.

title "M00-E50 — Socle MédiSphère v0 : contrôle global"
require_cmd dig ssh git

# --- 1. Hyperviseur et inventaire Proxmox ---------------------------------------------
title "1/9 Hyperviseur pve01"
check_ssh_output "pve01 : version de Proxmox VE" "$WB_PVE_HOST" 'pve-manager/(8|9)\.' "pveversion"
check_ssh_output "pve01 : pare-feu Proxmox actif" "$WB_PVE_HOST" 'Status: enabled/running' "pve-firewall status"
check_ssh_output "pve01 : utilisateurs du lab présents" "$WB_PVE_HOST" 'wb-automation@pve' "pveum user list"
check_ssh_output "pve01 : jeton d'automatisation présent" "$WB_PVE_HOST" '(^|[^a-z])lab([^a-z]|$)' \
  "pveum user token list wb-automation@pve"
_wb_stos="${WB_STORAGE_NVME:-local-nvme} ${WB_STORAGE_SSD:-ssd-lab} ${WB_STORAGE_BULK:-hdd-bulk}"
check_ssh "pve01 : stockages du lab actifs ($_wb_stos)" "$WB_PVE_HOST" \
  's=$(pvesm status); for n in '"$_wb_stos"'; do echo "$s" | grep -Eq "^$n[[:space:]]+[a-z]+[[:space:]]+active" || exit 1; done'
check_ssh "pve01 : zone SDN lab et VNets vmgmt, vinfra, vsandbox appliqués" "$WB_PVE_HOST" \
  'v=$(pvesh get /cluster/sdn/vnets --output-format json); for n in vmgmt vinfra vsandbox; do echo "$v" | grep -q "\"$n\"" || exit 1; ip link show "$n" >/dev/null 2>&1 || exit 1; done'

# --- 2. VMs du socle ---------------------------------------------------------------
title "2/9 VMs du socle"
for _wb_id in 1000 1001 1002; do
  check_ssh_output "VM $_wb_id : démarrée" "$WB_PVE_HOST" '^status: running' "qm status $_wb_id"
  check_ssh "VM $_wb_id : démarrage automatique avec l'hôte" "$WB_PVE_HOST" "qm config $_wb_id | grep -q '^onboot: 1'"
  check_ssh "VM $_wb_id : agent QEMU actif" "$WB_PVE_HOST" "qm guest cmd $_wb_id ping"
done
check_ssh "gw01 démarre avant les autres VMs du socle (ordre de démarrage)" "$WB_PVE_HOST" \
  'o() { qm config "$1" | sed -nE "s/^startup:.*order=([0-9]+).*/\1/p"; }; g=$(o 1000); a=$(o 1001); d=$(o 1002); [ -n "$g" ] && [ "$g" -lt "${a:-9999}" ] && [ "$g" -lt "${d:-9999}" ]'
check_ssh "template 9000 (tpl-debian13) présent" "$WB_PVE_HOST" "qm config 9000 | grep -q '^template: 1'"
check_ssh "VMs du socle et template rangés dans le pool lab" "$WB_PVE_HOST" \
  'p=$(pvesh get /pools/lab --output-format json); for i in 1000 1001 1002 9000; do echo "$p" | grep -Eq "\"vmid\" *: *$i([^0-9]|\$)" || exit 1; done'
check_ssh "aucune VM sandbox oubliée (5000-5999)" "$WB_PVE_HOST" \
  '! qm list | awk "NR>1 {print \$1}" | grep -Eq "^5[0-9]{3}$"'

# --- 3. Routage, NAT et filtrage (gw01) --------------------------------------------
title "3/9 Routeur gw01"
check_ssh_output "gw01 : routage IPv4 actif" gw01 '^1$' "sysctl -n net.ipv4.ip_forward"
check_ssh "gw01 : nftables chargé au démarrage" gw01 "systemctl is-enabled -q nftables"
check_ssh_output "gw01 : politique drop en entrée" gw01 'policy drop' "sudo -n nft list chain inet filter input"
check_ssh_output "gw01 : politique drop en transit" gw01 'policy drop' "sudo -n nft list chain inet filter forward"
check_ssh "gw01 : /etc/nftables.conf valide (rechargeable sans erreur)" gw01 \
  'sudo -n nft -c -f /etc/nftables.conf'
check_ssh "dns01 : Internet joignable (TCP/443)" dns01 "timeout 5 bash -c 'exec 3<>/dev/tcp/1.1.1.1/443'"
check_cmd "adm01 : Internet joignable (TCP/443)" timeout 5 bash -c 'exec 3<>/dev/tcp/1.1.1.1/443'
check_cmd "adm01 → dns01 : paquets de 1500 octets non fragmentables" ping -M 'do' -s 1472 -c 2 -W 3 10.10.20.10

# --- 4. DNS et DHCP --------------------------------------------------------------
title "4/9 DNS et DHCP"
check_dns "DNS : adm01.par1.medisphere.internal" adm01.par1.medisphere.internal A '^10\.10\.10\.10$' 10.10.20.10
check_dns "DNS : gw01.par1.medisphere.internal" gw01.par1.medisphere.internal A '^10\.10\.10\.1$' 10.10.20.10
check_dns "DNS : inverse de 10.10.20.10" 10.20.10.10.in-addr.arpa PTR 'dns01\.par1\.medisphere\.internal\.$' 10.10.20.10
check_dns "DNS : pbs01.par2.medisphere.internal" pbs01.par2.medisphere.internal A '^10\.20\.10\.10$' 10.10.20.10
check_dns "DNS : récursion vers Internet" deb.debian.org A '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' 10.10.20.10
check_cmd "adm01 : résolveur système et domaine de recherche" getent hosts dns01
check_ssh "dns01 : plage DHCP du VLAN 99 déclarée" dns01 \
  "grep -Ehs '^[[:space:]]*dhcp-range=' /etc/dnsmasq.conf /etc/dnsmasq.d/*.conf | grep -q '10\.10\.99\.100'"
check_ssh "gw01 : relais DHCP actif" gw01 \
  "systemctl is-active -q dnsmasq || systemctl is-active -q isc-dhcp-relay"

# --- 5. Temps -----------------------------------------------------------------------
title "5/9 Temps"
check_ssh_output "gw01 : synchronisé sur Internet" gw01 '^\^\*' "sudo -n chronyc -n sources"
check_output "adm01 : synchronisé sur 10.10.10.1" '^\^\*[[:space:]]+10\.10\.10\.1[[:space:]]' sudo -n chronyc -n sources
check_ssh_output "dns01 : synchronisé sur 10.10.20.1" dns01 '^\^\*[[:space:]]+10\.10\.20\.1[[:space:]]' "sudo -n chronyc -n sources"
check_ssh_output "pbs01 : synchronisé sur gw01" "$WB_PBS_HOST" '^\^\*[[:space:]]+10\.(10\.[0-9]+\.1|255\.0\.1)[[:space:]]' "chronyc -n sources"

# --- 6. VPN et interconnexion ----------------------------------------------------------
title "6/9 VPN d'administration et tunnel PAR1-PAR2"
check_ssh_output "gw01 : VPN d'administration wg1 en écoute sur UDP/51821" gw01 '^51821$' "sudo -n wg show wg1 listen-port"
check_ssh "gw01 : wg0 et wg1 démarrent au boot" gw01 \
  "systemctl is-enabled -q wg-quick@wg0 && systemctl is-enabled -q wg-quick@wg1"
check_ssh "gw01 → hp01 : extrémité du tunnel (10.255.0.2)" gw01 "ping -c 2 -W 3 10.255.0.2"
check_ping "adm01 → pbs01 (10.20.10.10) par le tunnel" 10.20.10.10
check_ssh "gw01 : poignée de main WireGuard récente sur wg0" gw01 \
  't=$(sudo -n wg show wg0 latest-handshakes | awk "{print \$2}" | sort -n | tail -n 1); [ -n "$t" ] && [ $(( $(date +%s) - t )) -lt 180 ]'

# --- 7. Sauvegarde ------------------------------------------------------------------
title "7/9 Sauvegarde PBS"
check_ssh_output "pve01 : stockage pbs-par2 actif" "$WB_PVE_HOST" '^pbs-par2[[:space:]]+pbs[[:space:]]+active' \
  "pvesm status --storage pbs-par2"
check_ssh "pve01 : pbs-par2 chiffré côté client" "$WB_PVE_HOST" "test -s /etc/pve/priv/storage/pbs-par2.enc"
check_ssh "pve01 : tâche de sauvegarde planifiée vers pbs-par2" "$WB_PVE_HOST" \
  'pvesh get /cluster/backup --output-format json | grep -Eq "\"storage\" *: *\"pbs-par2\""'
check_ssh_output "pve01 : la dernière sauvegarde s'est terminée sans erreur" "$WB_PVE_HOST" '"status" *: *"OK"' \
  'pvesh get /nodes/$(hostname)/tasks --typefilter vzdump --limit 1 --output-format json'
check_ssh "pve01 : sauvegarde de moins de 48 h pour 1000, 1001 et 1002" "$WB_PVE_HOST" \
  'j=$(pvesh get /nodes/$(hostname)/storage/pbs-par2/content --content backup --output-format json); for i in 1000 1001 1002; do echo "$j" | perl -MJSON::PP -0777 -ne "exit((grep { \$_->{vmid} == $i && \$_->{ctime} > time() - 172800 } @{decode_json(\$_)}) ? 0 : 1)" || exit 1; done'
check_ssh "pbs01 : datastore ds-lab sans mode maintenance" "$WB_PBS_HOST" \
  "! proxmox-backup-manager datastore show ds-lab --output-format json | grep -q maintenance"
check_ssh "pbs01 : vérification et purge planifiées" "$WB_PBS_HOST" \
  'proxmox-backup-manager verify-job list --output-format json | grep -q "\"ds-lab\"" && proxmox-backup-manager prune-job list --output-format json | grep -q "\"ds-lab\""'

# --- 8. Pannes et exercices ----------------------------------------------------------
title "8/9 Hygiène du lab"
check_cmd "aucune panne d'exercice encore active (lab/bin/break)" \
  bash -c '! ls "${XDG_STATE_HOME:-$HOME/.local/state}"/workbook/pannes-actives/E* >/dev/null 2>&1'
check_ssh "gw01 : aucune règle de traçage nftables oubliée" gw01 "! sudo -n nft list ruleset | grep -q nftrace"

# --- 9. Dossier de livraison ----------------------------------------------------------
title "9/9 Dossier de livraison (docs/socle/)"
_wb_depot="${WB_DEPOT:-$HOME/medisphere}"
_wb_doc="$_wb_depot/docs/socle"
check_cmd "dépôt Git du socle présent ($_wb_depot)" git -C "$_wb_depot" rev-parse --is-inside-work-tree
check_output "dépôt : aucune modification non commitée" '^$' git -C "$_wb_depot" status --porcelain
check_cmd "dépôt : étiquette socle-v0 posée" git -C "$_wb_depot" rev-parse -q --verify refs/tags/socle-v0
for _wb_f in README.md architecture.md inventaire.md matrice-flux.md capacite.md tests/restauration.md; do
  check_cmd "docs/socle/$_wb_f présent" test -s "$_wb_doc/$_wb_f"
done
check_cmd "au moins 4 runbooks (docs/socle/runbooks/)" \
  bash -c '[ "$(find "$1" -maxdepth 1 -name "*.md" ! -name README.md | wc -l)" -ge 4 ]' _ "$_wb_doc/runbooks"
check_cmd "au moins 3 ADR (docs/socle/adr/)" \
  bash -c '[ "$(find "$1" -maxdepth 1 -name "*.md" ! -name README.md | wc -l)" -ge 3 ]' _ "$_wb_doc/adr"
check_cmd "au moins un post-mortem (docs/socle/post-mortems/)" \
  bash -c '[ "$(find "$1" -maxdepth 1 -name "*.md" ! -name README.md | wc -l)" -ge 1 ]' _ "$_wb_doc/post-mortems"
check_output "matrice des flux : tunnel, VPN, DNS, NTP, DHCP et PBS couverts" '51820' cat "$_wb_doc/matrice-flux.md"
check_cmd "matrice des flux : ports 51821, 53, 123, 67 et 8007 cités" \
  bash -c 'for p in 51821 53 123 67 8007; do grep -Eq "(^|[^0-9])$p([^0-9]|\$)" "$1" || exit 1; done' _ "$_wb_doc/matrice-flux.md"
check_cmd "plan de capacité : profils infra, openstack, k8s et plateforme traités" \
  bash -c 'for p in infra openstack k8s plateforme; do grep -qi "$p" "$1" || exit 1; done' _ "$_wb_doc/capacite.md"
check_output "test de restauration : durée mesurée consignée" '([0-9]+ ?min|[0-9]+:[0-9]{2}|RTO)' cat "$_wb_doc/tests/restauration.md"
check_cmd "aucun secret évident dans le dossier (clé privée, jeton)" \
  bash -c '! grep -REqi "(PrivateKey *= *[A-Za-z0-9+/]{42,43}=|BEGIN [A-Z ]*PRIVATE KEY|(secret|password|token)[^[:space:]]*[ :=\"]+[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})" "$1"' _ "$_wb_doc"
