# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E10.sh — M05-E10 : Construire s3-01, un stockage S3 pour le socle
# Lecture seule : Proxmox (root sur pve01), état socle (tofu show), s3-01 (SSH admin + sudo -n),
# passerelle S3 (curl, AWS CLI avec l'identité tofu-etat), projets ansible et medisphere.

# shellcheck source=_m05-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-operationnel.sh"

title "M05-E10 — Construire s3-01 : un stockage S3 pour le socle"
require_cmd jq curl dig aws tofu git

# --- La VM, créée par OpenTofu ---------------------------------------------------------------
_m05o_c="$(_m05o_qm 1006)"
check_output "VM 1006 : nom s3-01" '^name: s3-01$' printf '%s\n' "$_m05o_c"
check_cmd "VM 1006 : étiquettes socle et role-s3" \
  bash -c 'grep -E "^tags:" <<<"$1" | grep -q "role-s3" && grep -E "^tags:" <<<"$1" | grep -Eq "(^tags: |;)socle(;|$)"' _ "$_m05o_c"
check_ssh "VM 1006 : dans le pool lab" "$WB_PVE_HOST" \
  'pvesh get /pools/lab --output-format json | grep -Eq "\"vmid\" *: *1006([^0-9]|$)"'
check_output "VM 1006 : 2 vCPU" '^cores: 2$' printf '%s\n' "$_m05o_c"
check_output "VM 1006 : 2 Go de mémoire" '^memory: 2048$' printf '%s\n' "$_m05o_c"
check_output "VM 1006 : disque système de 20 Go sur ${WB_STORAGE_NVME:-local-nvme}" \
  "^scsi0: ${WB_STORAGE_NVME:-local-nvme}:[^,]+,.*size=20G" printf '%s\n' "$_m05o_c"
check_output "VM 1006 : disque de données de 100 Go sur ${WB_STORAGE_BULK:-hdd-bulk}" \
  "^scsi1: ${WB_STORAGE_BULK:-hdd-bulk}:[^,]+,.*size=100G" printf '%s\n' "$_m05o_c"
check_cmd "VM 1006 : clone complet (aucun disque adossé à un template)" \
  bash -c '[ -n "$1" ] && ! grep -Eq "^scsi[0-9]+:.*base-9[0-9]{3}-disk" <<<"$1"' _ "$_m05o_c"
check_output "VM 1006 : carte sur le VNet vinfra" '^net0: virtio=[^,]+,bridge=vinfra' printf '%s\n' "$_m05o_c"
check_output "VM 1006 : adresse 10.10.20.14/24, passerelle 10.10.20.1 (cloud-init)" \
  '^ipconfig0: (ip=10\.10\.20\.14/24,gw=10\.10\.20\.1|gw=10\.10\.20\.1,ip=10\.10\.20\.14/24)$' printf '%s\n' "$_m05o_c"
check_output "VM 1006 : démarre avec l'hôte" '^onboot: 1$' printf '%s\n' "$_m05o_c"
check_output "VM 1006 : rang de démarrage 4 (comme git01)" '^startup: order=4([,]|$)' printf '%s\n' "$_m05o_c"
check_output "VM 1006 : protégée contre la suppression" '^protection: 1$' printf '%s\n' "$_m05o_c"
check_ssh "VM 1006 : démarrée, agent QEMU actif" "$WB_PVE_HOST" 'qm status 1006 | grep -q running && qm guest cmd 1006 ping'

# --- L'état socle --------------------------------------------------------------------------
check_cmd "état socle : la VM 1006 y est (créée par OpenTofu)" _m05o_a_vmid "$_m05o_socle" 1006
check_cmd "code socle : aucun clone lié (full = false) pour s3-01" \
  bash -c '! grep -Eqs "full[[:space:]]*=[[:space:]]*false" "$1"/*.tf' _ "$_m05o_socle"

# --- Nom et accès ------------------------------------------------------------------------------
check_dns "DNS : s3-01.par1.medisphere.internal → 10.10.20.14" s3-01.par1.medisphere.internal A '^10\.10\.20\.14$' 10.10.20.10
check_dns "DNS : PTR de 10.10.20.14 → s3-01" 14.20.10.10.in-addr.arpa PTR '^s3-01\.par1\.medisphere\.internal\.$' 10.10.20.10
check_cmd "alias SSH s3-01 sur adm01 (admin + sudo -n)" remote s3-01 'sudo -n true'

# --- SeaweedFS sur s3-01 ------------------------------------------------------------------------
check_ssh "s3-01 : service seaweedfs actif et activé" s3-01 \
  'systemctl is-active --quiet seaweedfs && systemctl is-enabled --quiet seaweedfs'
check_ssh_output "s3-01 : SeaweedFS 4.4x" 'version .* 4\.4[0-9]' s3-01 'weed version 2>/dev/null | head -n 1'
check_ssh "s3-01 : les données vivent sur le disque de 100 Go (point de montage dédié)" s3-01 \
  'd="$(systemctl show -p ExecStart seaweedfs | grep -oE -- "-dir=[^ ;]+" | head -n 1 | cut -d= -f2)"; [ -n "$d" ] && [ "$(findmnt -n -T "$d" -o TARGET)" != / ] && [ "$(df -BG --output=size "$d" | tail -n 1 | tr -dc 0-9)" -ge 90 ]'
check_ssh "s3-01 : la passerelle S3 écoute sur 10.10.20.14:8333" s3-01 \
  'ss -Hltn "sport = :8333" | grep -q "10\.10\.20\.14:8333"'
check_ssh "s3-01 : master, volume et filer n'écoutent pas sur le réseau" s3-01 \
  '! ss -Hltn | grep -E "(0\.0\.0\.0|\*|\[::\]|10\.10\.20\.14):(9333|8080|8888|19333|18080|18888)\b"'
check_ssh "s3-01 : télémétrie de SeaweedFS désactivée" s3-01 \
  'systemctl show -p ExecStart seaweedfs | grep -q -- "-master.telemetry=false"'
check_ssh "s3-01 : identités S3 et clé TLS illisibles par les autres comptes" s3-01 \
  'f="$(systemctl show -p ExecStart seaweedfs | grep -oE -- "-s3\.(config|key\.file)=[^ ;]+" | cut -d= -f2)"; [ "$(printf "%s\n" "$f" | grep -c .)" -eq 2 ] && for x in $f; do sudo -n stat -c %a "$x" | grep -Eq "^[0-7][0-7]0$" || exit 1; done'

# --- Passerelle S3, vue des clients ------------------------------------------------------------
check_http "HTTPS vérifié avec la CA provisoire, accès anonyme refusé (403)" \
  "https://s3-01.par1.medisphere.internal:8333/" 403
check_http "HTTP en clair refusé sur le port 8333" "http://s3-01.par1.medisphere.internal:8333/" 400
check_cmd "accès de tofu-etat dans ~/.config/workbook/s3-tofu.env (mode 600)" \
  bash -c '[ "$(stat -c %a "$1")" = 600 ] && grep -q "^AWS_SECRET_ACCESS_KEY=" "$1"' _ "$_m05o_cfg/s3-tofu.env"
_m05o_compartiments() { _m05o_aws s3api list-buckets | jq -c '[.Buckets[].Name]'; }
check_output "tofu-etat ne voit que le compartiment tofu-state" '^\["tofu-state"\]$' _m05o_compartiments
check_output "compartiment tofu-state versionné" '"Status": *"Enabled"' \
  _m05o_aws s3api get-bucket-versioning --bucket "$_m05o_bucket"
check_output "politique du compartiment : tofu-etat ne peut pas effacer l'historique" 'DeleteObjectVersion' \
  _m05o_aws s3api get-bucket-policy --bucket "$_m05o_bucket"
check_cmd "client aws : profil s3-socle avec l'adresse de s3-01" \
  bash -c 'grep -A6 "^\[profile s3-socle\]" "$HOME/.aws/config" | grep -q "s3-01.par1.medisphere.internal:8333"'

# --- Le code : rôle Ansible et documentation ------------------------------------------------------
for _m05o_f in roles/seaweedfs/tasks/main.yml roles/seaweedfs/defaults/main.yml roles/seaweedfs/meta/main.yml \
  molecule/seaweedfs/molecule.yml molecule/seaweedfs/verify.yml; do
  check_cmd "plateforme/ansible : $_m05o_f" test -s "$_m05o_ansible/$_m05o_f"
done
check_cmd "plateforme/ansible : secrets de s3-01 chiffrés par Ansible Vault" \
  bash -c 'n=0; for f in "$1"/inventories/lab/host_vars/s3-01/*vault*.yml; do [ -f "$f" ] || continue; n=$((n+1)); head -n 1 "$f" | grep -q "^\$ANSIBLE_VAULT;" || exit 1; done; [ "$n" -ge 1 ]' _ "$_m05o_ansible"
check_cmd "plateforme/ansible : aucun secret S3 en clair hors du coffre" \
  bash -c '! grep -rEs "^[[:space:]]*(cle_secrete|secretKey|aws_secret_access_key)[[:space:]]*[:=][[:space:]]*\"?[A-Za-z0-9/+]{30,}" "$1/inventories" "$1/roles/seaweedfs"' _ "$_m05o_ansible"
check_output "inventaire dynamique : s3-01 dans le groupe role_s3" 's3-01' \
  _m05o_ansible ansible-inventory --graph role_s3
check_cmd "registre des secrets : identités tofu-etat et admin-s3 inscrites" \
  bash -c 'grep -q "tofu-etat" "$1" && grep -q "admin-s3" "$1"' _ "$_m05o_depot/docs/socle/registre-secrets.md"
check_cmd "inventaire du socle : s3-01 (1006, 10.10.20.14) documentée" \
  bash -c 'grep -q "s3-01" "$1" && grep -q "10.10.20.14" "$1"' _ "$_m05o_depot/docs/socle/inventaire.md"
