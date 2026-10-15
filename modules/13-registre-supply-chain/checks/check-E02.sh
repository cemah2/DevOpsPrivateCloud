# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes distantes entre apostrophes
#
# check-E02.sh — M13-E02 : Installer Harbor sur reg01
# À lancer depuis adm01. Lecture seule : qm config sur pve01, DNS, NetBox, TLS, état de reg01 en SSH
# (sudo -n pour lire), API publique de Harbor (/health), nftables des passerelles en lecture, GitLab.

# shellcheck source=_m13-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m13-decouverte.sh"

title "M13-E02 — Installer Harbor sur reg01"
require_cmd jq dig curl openssl

_m13_conf="$(_m13d_qm 1013)"
_m13_nvme="${WB_STORAGE_NVME:-local-nvme}"
_m13_bulk="${WB_STORAGE_BULK:-hdd-bulk}"

# --- 1. La VM -------------------------------------------------------------------------------------
check_output "VM 1013 nommée reg01" '^name: reg01$' echo "$_m13_conf"
check_cmd "reg01 : étiquettes socle et role-registre" \
  bash -c 't="$(sed -n "s/^tags: //p" <<<"$1")"; [[ ";$t;" == *";socle;"* && ";$t;" == *";role-registre;"* ]]' _ "$_m13_conf"
check_cmd "reg01 : 2 vCPU et 6144 Mo" \
  bash -c 'grep -q "^cores: 2$" <<<"$1" && grep -q "^memory: 6144$" <<<"$1"' _ "$_m13_conf"
check_output "reg01 : carte sur le VNet vinfra" '^net0: .*bridge=vinfra' echo "$_m13_conf"
check_cmd "reg01 : disque système scsi0 de 32 Gio sur $_m13_nvme" \
  bash -c 'grep -Eq "^scsi0: $2:[^,]+,.*size=32G" <<<"$1"' _ "$_m13_conf" "$_m13_nvme"
check_cmd "reg01 : disque de données scsi1 de 200 Gio sur $_m13_bulk, série reg01-donnees, hors sauvegarde" \
  bash -c 'l="$(grep -E "^scsi1: " <<<"$1")"; [[ "$l" == "scsi1: $2:"* && "$l" == *size=200G* && "$l" == *backup=0* && "$l" == *serial=reg01-donnees* ]]' \
  _ "$_m13_conf" "$_m13_bulk"
check_output "reg01 : créée par OpenTofu (note de la VM)" 'Harbor|OpenTofu|M13-E02' echo "$_m13_conf"

# --- 2. Noms et NetBox -----------------------------------------------------------------------------
check_dns "DNS : reg01.par1.medisphere.internal → 10.10.20.18" reg01.par1.medisphere.internal A '^10\.10\.20\.18$' "$_M13D_DNS"
check_dns "DNS : 10.10.20.18 → reg01 (PTR)" 18.20.10.10.in-addr.arpa PTR '^reg01\.par1\.medisphere\.internal\.$' "$_M13D_DNS"
check_dns "DNS : registry.par1.medisphere.internal est un CNAME vers reg01" "$_M13D_NOM" CNAME '^reg01\.par1\.medisphere\.internal\.$' "$_M13D_DNS"
_m13_nb() {
  netbox_api "virtualization/virtual-machines/?name=reg01" 2>/dev/null \
    | jq -e '.count == 1 and .results[0].status.value == "active" and .results[0].primary_ip4.address == "10.10.20.18/24"' >/dev/null
}
check_cmd "NetBox : reg01 active, IP primaire 10.10.20.18/24" _m13_nb

# --- 3. L'hôte --------------------------------------------------------------------------------------
check_ssh_output "reg01 : Debian 13" "$_M13D_REG" '^debian 13' '. /etc/os-release; echo "$ID $VERSION_ID"'
check_ssh "reg01 : /data est un XFS monté depuis le disque reg01-donnees" "$_M13D_REG" \
  'findmnt -no FSTYPE /data | grep -qx xfs && s="$(findmnt -no SOURCE /data)" && readlink -f /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_reg01-donnees | grep -qx "$(readlink -f "$s")"'
check_ssh "reg01 : /data fait environ 200 Gio" "$_M13D_REG" \
  'g=$(( $(findmnt -bno SIZE /data) / 1073741824 )); [ "$g" -ge 190 ] && [ "$g" -le 201 ]'
check_ssh "reg01 : docker.service attend le montage de /data" "$_M13D_REG" \
  'systemctl show -p RequiresMountsFor docker.service | grep -q "/data"'
check_ssh_output "reg01 : Docker Engine 29.x" "$_M13D_REG" '^29\.' 'sudo -n docker version --format "{{.Server.Version}}"'
check_ssh_output "reg01 : Docker Compose v5" "$_M13D_REG" '^v?5\.' 'docker compose version --short'
check_ssh "reg01 : harbor.service actif et activé au démarrage" "$_M13D_REG" \
  'systemctl is-active --quiet harbor.service && systemctl is-enabled --quiet harbor.service'
check_ssh "reg01 : /opt/harbor désigne l'installateur 2.15.3" "$_M13D_REG" \
  '[ "$(readlink -f /opt/harbor)" = /opt/harbor-dist/2.15.3/harbor ]'
check_ssh_output "reg01 : harbor-core en v2.15.3" "$_M13D_REG" ':v2\.15\.3$' \
  'sudo -n docker inspect -f "{{.Config.Image}}" harbor-core'
check_ssh "reg01 : conteneurs de Harbor (dont trivy-adapter) en service et sains" "$_M13D_REG" \
  'out="$(sudo -n docker ps --format "{{.Names}} {{.Status}}")"; for c in harbor-core harbor-db registry nginx harbor-jobservice redis trivy-adapter; do grep -Eq "^$c Up.*\(healthy\)" <<<"$out" || exit 1; done'
check_ssh "reg01 : harbor.yml en 600 (root), mot de passe par défaut absent" "$_M13D_REG" \
  '[ "$(sudo -n stat -c "%a %U" /opt/harbor/harbor.yml)" = "600 root" ] && ! sudo -n grep -Eq "Harbor12345|root123" /opt/harbor/harbor.yml'
check_ssh "reg01 : hostname de harbor.yml = $_M13D_NOM" "$_M13D_REG" \
  "sudo -n grep -qx 'hostname: $_M13D_NOM' /opt/harbor/harbor.yml"
check_ssh "reg01 : cert-renewer@harbor.timer actif" "$_M13D_REG" 'systemctl is-active --quiet cert-renewer@harbor.timer'

# --- 4. HTTPS -----------------------------------------------------------------------------------------
_m13_sante() { curl -sf --max-time "$WB_TIMEOUT" "https://$_M13D_NOM/api/v2.0/health" | jq -e '.status == "healthy"' >/dev/null; }
check_cmd "https://$_M13D_NOM/api/v2.0/health « healthy » depuis adm01 (TLS vérifié)" _m13_sante
check_ssh "/api/v2.0/health « healthy » depuis runner02 (TLS vérifié)" runner02 \
  "curl -sf --max-time 5 https://$_M13D_NOM/api/v2.0/health | grep -q '\"status\": *\"healthy\"'"
_m13_x509="$(_m13d_cert_tls "$_M13D_NOM" 443)"
check_output "certificat émis par l'intermédiaire MédiSphère" 'issuer=.*Interm' echo "$_m13_x509"
check_output "certificat : nom $_M13D_NOM" "DNS:${_M13D_NOM//./\\.}" echo "$_m13_x509"
check_output "certificat : nom reg01.par1.medisphere.internal" 'DNS:reg01\.par1\.medisphere\.internal' echo "$_m13_x509"
_m13_duree="$(_m13d_duree_jours "$_m13_x509")"
check_output "certificat : 30 jours au plus (durée : $_m13_duree j)" '^([1-9]|[12][0-9]|30)$' echo "$_m13_duree"

# --- 5. Flux et code -----------------------------------------------------------------------------------
for _m13_gw in gw01 gw02; do
  check_ssh "$_m13_gw : transit VLAN 40 et 99 → 10.10.20.18 TCP 443 autorisé" "$_m13_gw" \
    'r="$(sudo -n nft list chain inet filter forward)"; grep "10.10.20.18" <<<"$r" | grep -E "dport 443" | grep accept | grep -q "ens19.40" && grep "10.10.20.18" <<<"$r" | grep -E "dport 443" | grep accept | grep -q "ens19.99"'
done
_m13_matrice() { _m13d_contenu_main "$_M13D_DOC" docs/socle/matrice-flux.md | grep -Eq 'reg01|10\.10\.20\.18'; }
check_cmd "matrice des flux (docs/socle/matrice-flux.md, main) : reg01 mentionné" _m13_matrice
check_cmd "plateforme/infra (main) : socle/reg01.tf" _m13d_fichier_main "$_M13D_INFRA" socle/reg01.tf
_m13_role() { _m13d_fichier_main "$_M13D_ANSIBLE" roles/harbor/tasks/main.yml && _m13d_fichier_main "$_M13D_ANSIBLE" playbooks/registre.yml; }
check_cmd "plateforme/ansible (main) : rôle harbor et playbooks/registre.yml" _m13_role
_m13_epingle() {
  _m13d_contenu_main "$_M13D_ANSIBLE" inventories/lab/group_vars/role_registre/harbor.yml \
    | grep -Eq 'harbor_installateur_sha256: *"?[0-9a-f]{64}'
}
check_cmd "plateforme/ansible (main) : empreinte SHA-256 de l'installateur épinglée" _m13_epingle
_m13_rb() {
  gitlab_api "$_M13D_DOC/repository/tree?path=docs/registre/runbooks&ref=main&per_page=100" 2>/dev/null \
    | jq -e '[.[].name | select(test("^RB-130"))] | length >= 1' >/dev/null
}
check_cmd "RB-130 publié dans docs/registre/runbooks/ (main)" _m13_rb
check_output "adm01 : Cosign 3.1.x" 'GitVersion: *v?3\.1\.' cosign version
