# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions évaluées par le bash -c ou l'hôte distant
#
# check-E19.sh — M05-E19 : cloud-init généré et snippets gérés par le code
# Lecture seule : pve01 (root : stockage, compte, sudoers, ACL, snippets, agent QEMU de 2054),
# code et état de lab-m05.

# shellcheck source=_m05-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-operationnel.sh"

title "M05-E19 — cloud-init généré et snippets gérés par le code"
require_cmd jq tofu

# --- pve01 : ce dont le provider a besoin, et rien de plus ---------------------------------------
check_ssh_output "pve01 : stockage tofu-snippets actif" '^tofu-snippets[[:space:]]+dir[[:space:]]+active' \
  "$WB_PVE_HOST" 'pvesm status --storage tofu-snippets'
check_ssh_output "pve01 : tofu-snippets ne reçoit que des snippets" '"content" *: *"snippets"' "$WB_PVE_HOST" \
  'pvesh get /storage/tofu-snippets --output-format json'
check_ssh "pve01 : compte Linux wb-tofu, sans mot de passe utilisable" "$WB_PVE_HOST" \
  'id wb-tofu >/dev/null && passwd -S wb-tofu | grep -Eq "^wb-tofu (L|NP) "'
check_ssh "pve01 : clé de wb-tofu limitée à adm01 (from=)" "$WB_PVE_HOST" \
  'grep -q "from=\"10\.10\.10\.10\"" ~wb-tofu/.ssh/authorized_keys'
check_ssh "pve01 : sudoers de wb-tofu valide et limité (tee vers les snippets, pvesm apiinfo)" "$WB_PVE_HOST" \
  'f=/etc/sudoers.d/wb-tofu; visudo -cf "$f" >/dev/null && grep -q "/usr/bin/tee /mnt/hdd-bulk/tofu-snippets/snippets/" "$f" && ! grep -Eq "NOPASSWD:[[:space:]]*ALL|/usr/sbin/qm|pvesm[[:space:]]*$|/usr/bin/tee /var/lib/vz/\*" "$f"'
check_ssh "pve01 : jeton wb-tofu!tofu avec Datastore.Allocate sur tofu-snippets" "$WB_PVE_HOST" \
  'pveum user token permissions wb-tofu@pve tofu --path /storage/tofu-snippets --output-format json | grep -q "Datastore.Allocate\""'
check_ssh "pve01 : jeton wb-tofu!tofu SANS Datastore.Allocate sur ${WB_STORAGE_BULK:-hdd-bulk}" "$WB_PVE_HOST" \
  "! pveum user token permissions wb-tofu@pve tofu --path /storage/${WB_STORAGE_BULK:-hdd-bulk} --output-format json | grep -q 'Datastore.Allocate\"'"

# --- Le code ---------------------------------------------------------------------------------
check_cmd "lab-m05 : provider avec bloc ssh (utilisateur wb-tofu, agent SSH)" \
  bash -c 'grep -Ezqs "ssh[[:space:]]*\{[^}]*username[[:space:]]*=[[:space:]]*\"wb-tofu\"" "$1"/*.tf && grep -Eqs "agent[[:space:]]*=[[:space:]]*true" "$1"/providers.tf' _ "$_m05o_lab"
check_cmd "aucune clé privée ni mot de passe SSH dans le code" \
  bash -c '! grep -Eqs "(private_key|password)[[:space:]]*=" "$1"/*.tf' _ "$_m05o_lab"
check_cmd "lab-m05 : snippet généré par templatefile ou yamlencode" \
  bash -c 'grep -Eqs "templatefile\(|yamlencode\(" "$1"/*.tf' _ "$_m05o_lab"
check_cmd "état lab-m05 : le snippet est une ressource gérée (proxmox_virtual_environment_file)" \
  _m05o_a_adresse "$_m05o_lab" '^proxmox_virtual_environment_file\.'
check_cmd "socle : aucun snippet (l'état socle reste applicable sans SSH vers pve01)" \
  bash -c '! grep -qs "proxmox_virtual_environment_file" "$1"/*.tf' _ "$_m05o_socle"

# --- La VM et son cloud-init ---------------------------------------------------------------------
_m05o_c="$(_m05o_qm 2054)"
check_output "VM 2054 : user-data = snippet de tofu-snippets (cicustom)" '^cicustom: .*user=tofu-snippets:snippets/' \
  printf '%s\n' "$_m05o_c"
_m05o_snip="$(sed -nE 's/^cicustom: .*user=tofu-snippets:snippets\/([^,]+).*/\1/p' <<<"$_m05o_c")"
check_ssh "snippet présent sur pve01 et commençant par #cloud-config" "$WB_PVE_HOST" \
  "head -n 1 '/mnt/hdd-bulk/tofu-snippets/snippets/${_m05o_snip:-absent}' | grep -q '^#cloud-config'"
check_output "dans la VM : fichier écrit par le snippet (/etc/medisphere/generation)" 'generation=' \
  _m05o_invite 2054 cat /etc/medisphere/generation
check_ssh "dans la VM : cloud-init terminé sans erreur" "$WB_PVE_HOST" \
  'qm guest exec 2054 --timeout 20 -- cloud-init status | grep -q "status: done"'
check_cmd "lab-m05 : plan sans aucun changement" _m05o_plan_vide "$_m05o_lab"
