# shellcheck shell=bash
# shellcheck disable=SC2016  # commandes distantes et filtres jq entre apostrophes (développés à distance)
# shellcheck source-path=SCRIPTDIR
# check-S03.sh — F5-S03 « L'hyperviseur et le réseau de PAR2 » : PBS intact, Proxmox VE à côté, stockage
# et pool de PAR2, réseau (vmbr2, NAT inet par2, wg1), premières VMs, DNS secondaire et noms globaux,
# état OpenTofu de PAR2 sur s3-02, temps. Lecture seule (SSH root vers hp01 en consultation, SSH admin
# vers les VMs, dig, API S3 de s3-02 avec l'identité wb-checks, GitLab).

# shellcheck source=_f5-par2.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f5-par2.sh"

title "F5-S03 — L'hyperviseur et le réseau de PAR2"
require_cmd ssh jq dig curl

# --- Documents ---------------------------------------------------------------------------------------
check_cmd "RB-353 publié : go/no-go, sauvegarde de /etc/proxmox-backup, retour arrière, CHG-3503" \
  _f5p_doc runbooks/RB-353-hyperviseur-par2.md 'go.?/.?no.?go|no-go' '/etc/proxmox-backup' 'retour arri' 'CHG-3503'

# --- PBS intact et sauvegarde de sa configuration --------------------------------------------------------
_f5_s03_archive_hp01() {
  _f5p_hp01 'f=$(ls -1t /root/f5/pbs-config-*.tar.gz 2>/dev/null | head -n 1); [ -n "$f" ] && tar -tzf "$f" | grep -q "proxmox-backup/datastore.cfg"'
}
check_cmd "hp01 : archive /root/f5/pbs-config-<date>.tar.gz lisible, avec datastore.cfg" _f5_s03_archive_hp01
if [[ "$(hostname -s)" == "adm01" ]]; then
  _f5_s03_archive_adm01() { compgen -G "$HOME/f5/pbs-config-*.tar.gz" >/dev/null; }
  check_cmd "adm01 : copie de l'archive de configuration de PBS dans ~/f5/ (hors de hp01)" _f5_s03_archive_adm01
else
  skip "copie de l'archive de configuration de PBS sur adm01" "check lancé ailleurs que sur adm01"
fi
check_cmd "hp01 : PBS sert toujours le datastore ds-lab (proxmox-backup-proxy actif)" \
  _f5p_hp01 'systemctl is-active --quiet proxmox-backup-proxy && proxmox-backup-manager datastore list --output-format json | jq -e "any(.[]; .name == \"ds-lab\")" >/dev/null'
check_output "hp01 : Proxmox VE 9.2 installé (pveversion)" 'pve-manager/9\.2' _f5p_hp01 'pveversion'
_f5_s03_sauvegarde_apres() {
  # Un instantané de ds-lab plus récent que l'installation de pve-manager : les sauvegardes continuent.
  _f5p_hp01 'p=$(proxmox-backup-manager datastore show ds-lab --output-format json | jq -r .path); \
    ref=/var/lib/dpkg/info/pve-manager.list; [ -e "$ref" ] && [ -d "$p" ] && \
    [ -n "$(find "$p" -path "$p/.chunks" -prune -o -name index.json.blob -newer "$ref" -print -quit 2>/dev/null)" ]'
}
check_cmd "hp01 : au moins une sauvegarde arrivée dans ds-lab APRÈS l'installation de Proxmox VE" _f5_s03_sauvegarde_apres

# --- Stockage et pool --------------------------------------------------------------------------------
check_cmd "hp01 : stockage par2-vms actif" \
  _f5p_hp01 'pvesm status --storage par2-vms 2>/dev/null | awk "NR > 1 && \$3 == \"active\" { ok = 1 } END { exit !ok }"'
_f5_s03_limite() {
  # Limite technique : par2-vms sur un autre système de fichiers que ds-lab, ou sur un jeu ZFS avec quota.
  _f5p_hp01 'set -e; s=$(pvesh get /storage/par2-vms --output-format json | jq -r ".path // empty"); \
    d=$(proxmox-backup-manager datastore show ds-lab --output-format json | jq -r .path); [ -n "$s" ]; \
    fs=$(findmnt -n -o SOURCE -T "$s"); fd=$(findmnt -n -o SOURCE -T "$d"); \
    if [ "$fs" != "$fd" ]; then \
      t=$(findmnt -n -o FSTYPE -T "$s"); \
      if [ "$t" = zfs ]; then q=$(zfs get -H -o value quota,refquota "$fs" | grep -vc "^none$" || true); [ "$q" -ge 1 ]; else exit 0; fi; \
    else exit 1; fi'
}
check_cmd "hp01 : par2-vms a une limite de taille (système de fichiers distinct de ds-lab, ou jeu ZFS avec quota)" _f5_s03_limite
check_cmd "hp01 : pool Proxmox par2 présent" _f5p_hp01 'pvesh get /pools/par2 --output-format json >/dev/null 2>&1 || pvesh get /pools --poolid par2 --output-format json | jq -e "length > 0" >/dev/null'

# --- Réseau ------------------------------------------------------------------------------------------
check_output "hp01 : vmbr2 porte 10.20.20.1/24" 'inet 10\.20\.20\.1/24' _f5p_hp01 'ip -4 -o addr show dev vmbr2'
check_output "hp01 : routage IPv4 actif" '^1$' _f5p_hp01 'cat /proc/sys/net/ipv4/ip_forward'
check_cmd "hp01 : table nftables inet par2 avec traduction de la sortie de PAR2 INFRA" \
  _f5p_hp01 'nft list table inet par2 2>/dev/null | grep -Eq "masquerade|snat"'
_f5_s03_pas_lan() {
  # La table inet par2 ne doit pas laisser PAR2 INFRA joindre le LAN maison : une règle doit le mentionner.
  local lan="${WB_LAN_MAISON:-}"
  [[ -n "$lan" ]] || return 0
  _f5p_hp01 "nft list table inet par2 2>/dev/null | grep -Fq '${lan%%/*}'"
}
if [[ -n "${WB_LAN_MAISON:-}" ]]; then
  check_cmd "hp01 : la table inet par2 traite explicitement le LAN maison ($WB_LAN_MAISON)" _f5_s03_pas_lan
else
  skip "filtrage du LAN maison dans inet par2" "WB_LAN_MAISON non renseignée"
fi
check_output "hp01 : wg1 écoute en UDP 51823" '^51823$' _f5p_hp01 'wg show wg1 listen-port'
check_output "hp01 : wg1 porte 10.255.3.1/24" 'inet 10\.255\.3\.1/24' _f5p_hp01 'ip -4 -o addr show dev wg1'

# --- VMs ---------------------------------------------------------------------------------------------
for _f5_s03_v in 1050:adm02 1051:dns03 1052:s3-02; do
  _f5_s03_id="${_f5_s03_v%%:*}"
  _f5_s03_nom="${_f5_s03_v#*:}"
  check_output "VM $_f5_s03_id ($_f5_s03_nom) en marche sur hp01" '^running$' _f5p_vm_etat "$_f5_s03_id"
  check_output "VM $_f5_s03_id dans le pool par2" '^par2$' _f5p_vm_pool "$_f5_s03_id"
  check_output "VM $_f5_s03_id étiquetée site-par2" '(^|;)site-par2(;|$)' _f5p_vm "$_f5_s03_id" tags
  check_cmd "SSH vers $_f5_s03_nom.par2.medisphere.internal (admin)" _f5p_ssh "$_f5_s03_nom.par2.medisphere.internal" true
done

# --- DNS (par les récurseurs, port 53 : les autoritaires en 5300 ne sont pas ouverts à MGMT) ---------
for _f5_s03_z in medisphere.internal par1.medisphere.internal par2.medisphere.internal; do
  _f5_s03_p="$(_f5p_soa "$_f5_s03_z" "$_f5p_dns01" || true)"
  _f5_s03_s="$(_f5p_soa "$_f5_s03_z" "$_f5p_dns03" || true)"
  check_cmd "dns03 sert $_f5_s03_z au même numéro de série que dns01 (${_f5_s03_s:-rien} / ${_f5_s03_p:-rien})" \
    test -n "$_f5_s03_p" -a "$_f5_s03_p" = "$_f5_s03_s"
done
check_output "dns03 (récurseur) résout adm02.par2.medisphere.internal" '10\.20\.20\.10' \
  dig +short +time="$WB_TIMEOUT" "@$_f5p_dns03" adm02.par2.medisphere.internal A
for _f5_s03_n in mediagenda medidoc rdv; do
  # Par le récurseur : le TTL servi décroît depuis 60 (cache), il ne dépasse jamais 60.
  check_output "$_f5_s03_n.medisphere.internal : CNAME de TTL ≤ 60 s vers PAR1 (récurseur de dns01)" \
    "^$_f5_s03_n\.medisphere\.internal\.[[:space:]]+([1-5]?[0-9]|60)[[:space:]]+IN[[:space:]]+CNAME[[:space:]]+.*par1\.medisphere\.internal\.$" \
    _f5p_dig "$_f5_s03_n.medisphere.internal" CNAME "$_f5p_dns01"
done
check_output "mediagenda.medisphere.internal servi aussi par dns03 (CNAME)" 'CNAME' \
  _f5p_dig mediagenda.medisphere.internal CNAME "$_f5p_dns03"

# --- État OpenTofu de PAR2 --------------------------------------------------------------------------
if command -v aws >/dev/null 2>&1 && [[ -r "$_f5p_s3_env" ]]; then
  check_cmd "s3-02 : état s3://tofu-par2/envs/par2/terraform.tfstate présent" \
    _f5p_s3 head-object --bucket tofu-par2 --key envs/par2/terraform.tfstate
  check_output "s3-02 : versionnage actif sur tofu-par2" '"Status": *"Enabled"' \
    _f5p_s3 get-bucket-versioning --bucket tofu-par2
else
  skip "état OpenTofu de PAR2 sur s3-02" "aws absent ou $_f5p_s3_env illisible"
fi
skip "« tofu plan » de envs/par2 vide depuis adm02" "auto-évalué (un plan pose un verrou d'état : pas de lecture seule)"

# --- Temps -------------------------------------------------------------------------------------------
check_cmd "hp01 : chrony autorise PAR2 INFRA (directive allow)" \
  _f5p_hp01 'grep -RhsE "^[[:space:]]*allow[[:space:]]+10\.20\.(20\.0/24|0\.0/16)" /etc/chrony/'
_f5_s03_source_hors_par1() {
  # Au moins une source de temps de hp01 n'est ni à PAR1 (10.10/16) ni le tunnel (10.255/16).
  _f5p_hp01 'chronyc -n sources 2>/dev/null' | awk 'NR > 2 { print $2 }' | grep -Evq '^(10\.10\.|10\.255\.)'
}
check_cmd "hp01 : une source de temps qui ne passe pas par PAR1" _f5_s03_source_hors_par1
check_cmd "dns03 se synchronise sur 10.20.20.1" \
  _f5p_ssh dns03.par2.medisphere.internal 'chronyc -n sources 2>/dev/null | grep -q "10\.20\.20\.1"'
