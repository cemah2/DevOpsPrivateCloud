# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes exécutées DANS les VMs (expansion côté invité, voulue)
# check-S10.sh — F4-S10 « Migrer les VMs d'InfoGér vers Proxmox VE ». Lecture seule : configuration des
# VMs lue sur pve01, commandes de lecture dans les VMs par l'agent QEMU, DNS, NetBox, HTTP, GitLab ;
# « tofu plan » sans verrou ni enregistrement si l'environnement est cloné sur adm01.

# shellcheck source=_f4-migrations.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f4-migrations.sh"

title "F4-S10 — Migrer les VMs d'InfoGér vers Proxmox VE"
require_cmd jq curl ssh dig

for _f4_s10_nom in legacy-rdv01 ftp-part01 stats01; do
  _f4_s10_id="$(_f4g_vmid "$_f4_s10_nom")"
  _f4_s10_ip="$(_f4g_ip "$_f4_s10_nom")"
  check_cmd "VM $_f4_s10_id nommée $_f4_s10_nom, dans le pool lab" _f4g_vm_filtre "$_f4_s10_id" ".name == \"$_f4_s10_nom\" and .pool == \"lab\""
  check_cmd "$_f4_s10_nom : VirtIO SCSI, carte virtio sur vinfra, agent activé, ni SATA/IDE ni vmxnet3/e1000" _f4g_conforme "$_f4_s10_id"
  if _f4g_agent "$_f4_s10_id"; then
    check_cmd "$_f4_s10_nom : l'agent QEMU répond" true
    check_output "$_f4_s10_nom : l'invité porte $_f4_s10_ip" "^${_f4_s10_ip//./\\.}$" _f4g_ips "$_f4_s10_id"
    check_cmd "$_f4_s10_nom : open-vm-tools ni installé ni actif" _f4g_invite "$_f4_s10_id" \
      '! dpkg-query -W -f="\${Status}" open-vm-tools 2>/dev/null | grep -q "ok installed" && ! systemctl is-active --quiet open-vm-tools'
    check_cmd "$_f4_s10_nom : le compte infoger ne peut plus se connecter (absent, ou verrouillé sans clé)" _f4g_invite "$_f4_s10_id" \
      '! id infoger >/dev/null 2>&1 || { passwd -S infoger | grep -Eq "^infoger (L|LK) " && ! test -s /home/infoger/.ssh/authorized_keys; }'
    check_cmd "$_f4_s10_nom : plus aucune adresse 192.168.50.x dans les configurations réseau et applicatives" _f4g_invite "$_f4_s10_id" \
      '! grep -rIsq "192\.168\.50\." /etc/network /etc/hosts /etc/resolv.conf /etc/vsftpd.conf /etc/stats /etc/mysql /etc/apache2/sites-enabled'
  else
    check_cmd "$_f4_s10_nom : l'agent QEMU répond" false
    skip "$_f4_s10_nom : contrôles internes (adresse, outils VMware, compte infoger, re-adressage)" "agent injoignable"
  fi
  check_dns "$_f4_s10_nom.par1.medisphere.internal résout en $_f4_s10_ip" "$_f4_s10_nom.par1.medisphere.internal" A "^${_f4_s10_ip//./\\.}$" 10.10.20.10
  check_dns "$_f4_s10_ip résout en $_f4_s10_nom (inverse)" "$(awk -F. '{print $4"."$3"."$2"."$1".in-addr.arpa"}' <<<"$_f4_s10_ip")" PTR \
    "^$_f4_s10_nom\.par1\.medisphere\.internal\.$" 10.10.20.10
  check_output "NetBox : $_f4_s10_nom a pour adresse primaire $_f4_s10_ip" "^${_f4_s10_ip//./\\.}$" _f4g_netbox_ip "$_f4_s10_nom"
  check_output "une sauvegarde de $_f4_s10_nom ($_f4_s10_id) existe sur pbs-par2" "pbs-par2:backup/vm/$_f4_s10_id/" \
    _f4g_pve "pvesm list pbs-par2 --vmid $_f4_s10_id"
done

# --- Services rendus ----------------------------------------------------------------------------------
check_output "Legacy-RDV répond sur http://legacy-rdv01.par1.medisphere.internal/" 'Rendez-vous' \
  _f4g_get "http://legacy-rdv01.par1.medisphere.internal/"
check_output "Legacy-RDV répond sur $_f4g_rdv/ (nom des cabinets, répartiteurs)" 'Rendez-vous' _f4g_get "$_f4g_rdv/"
check_port "ftp-part01 accepte les connexions FTP (21) depuis adm01" 10.10.20.45 21
if _f4g_agent 3402; then
  check_cmd "ftp-part01 : vsftpd actif et adresse passive annoncée = 10.10.20.45 (ou non fixée)" _f4g_invite 3402 \
    'systemctl is-active --quiet vsftpd && { ! grep -q "^pasv_address=" /etc/vsftpd.conf || grep -qx "pasv_address=10.10.20.45" /etc/vsftpd.conf; }'
fi
if _f4g_agent 3403; then
  check_cmd "stats01 : un fichier de statistiques NON VIDE a été produit (lecture de la base réussie)" _f4g_invite 3403 \
    'for f in $(ls -t /srv/stats/rdv-*.csv 2>/dev/null | head -n 5); do [ "$(wc -l < "$f")" -gt 1 ] && exit 0; done; exit 1'
fi
if _f4g_agent 3401; then
  check_cmd "legacy-rdv01 : le compte MariaDB « stats » n'accepte que 10.10.20.46" _f4g_invite 3401 \
    'mariadb -N -B -e "SELECT host FROM mysql.user WHERE user = \"stats\"" | grep -qx "10.10.20.46" && ! mariadb -N -B -e "SELECT host FROM mysql.user WHERE user = \"stats\"" | grep -vqx "10.10.20.46"'
fi

# --- Code ---------------------------------------------------------------------------------------------
_f4_s10_tf() {
  local f c tout=""
  while IFS= read -r f; do
    [[ "$f" == *.tf ]] || continue
    c="$(_f4g_fichier plateforme/infra "$f" 2>/dev/null)" || continue
    tout+="$c"$'\n'
  done < <(_f4g_arbre plateforme/infra envs/f4-infoger)
  grep -Eq '^[[:space:]]*import[[:space:]]*\{' <<<"$tout" || return 1
  for v in 3401 3402 3403; do grep -q "$v" <<<"$tout" || return 1; done
}
check_cmd "plateforme/infra (main) : envs/f4-infoger importe les VMs 3401-3403 (blocs import)" _f4_s10_tf

_f4_s10_plan_vide() {
  local d="$_f4g_infra/envs/f4-infoger"
  [[ -d "$d" ]] || return 1
  (
    cd "$d" || exit 1
    set -a
    for f in "$HOME/.config/workbook/pve-tofu.env" "$HOME/.config/workbook/s3-tofu.env" \
             "$HOME/.config/workbook/netbox-tofu.env" "$HOME/.config/workbook/powerdns-api.env"; do
      # shellcheck source=/dev/null
      if [[ -r "$f" ]]; then source "$f"; fi
    done
    set +a
    # shellcheck source=/dev/null
    . "$_f4g_infra/outils/charger-acces.sh" >/dev/null 2>&1 || true
    exec timeout 600 tofu plan -lock=false -input=false -no-color -detailed-exitcode </dev/null
  ) >/dev/null 2>&1
}
if [[ -d "$_f4g_infra/envs/f4-infoger" && -r "$_f4g_infra/outils/charger-acces.sh" ]] && command -v tofu >/dev/null 2>&1; then
  check_cmd "tofu plan de envs/f4-infoger : aucun changement (clone $_f4g_infra à jour de main)" _f4_s10_plan_vide
else
  skip "tofu plan de envs/f4-infoger" "clone $_f4g_infra, outils/charger-acces.sh ou tofu absent sur ce poste"
fi
