# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant ou dans la VM
#
# check-E06.sh — M03-E06 « Image de base Rocky Linux 10 avec kickstart »
# VM de contrôle 2031 démarrée. Lecture seule ; « packer validate » local (ne contacte pas
# Proxmox), avec des valeurs factices pour les accès.

# shellcheck source=_m03-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m03-production.sh"

title "M03-E06 — Image de base Rocky Linux 10 avec kickstart"
require_cmd jq packer
_m03_charger
_m03_e06_bulk="${WB_STORAGE_BULK:-hdd-bulk}"
_m03_e06_d="$_M03_SRC/rocky10-base"

title "ISO et code"
check_ssh_output "ISO Rocky Linux 10 « boot » déposée sur $_m03_e06_bulk" "$WB_PVE_HOST" \
  'Rocky-10\.[0-9]+-x86_64-boot\.iso' "pvesm list $_m03_e06_bulk --content iso"
for _m03_e06_f in rocky10-base/build.pkr.hcl rocky10-base/variables.pkr.hcl rocky10-base/http/ks.cfg; do
  check_cmd "$_m03_e06_f sur main" _m03_fichier_main "$_m03_e06_f"
done
check_cmd "kickstart : SELinux enforcing, root verrouillé, pas de LVM ni de swap" \
  bash -c 'grep -q "^selinux --enforcing" "$1" && grep -q "^rootpw --lock" "$1" && grep -Eq "^autopart .*--type=plain.*--noswap|^autopart .*--noswap.*--type=plain" "$1"' \
  _ "$_m03_e06_d/http/ks.cfg"

# Validation des variables, avec des accès factices (passés par l'environnement : une
# variable non déclarée y est ignorée sans erreur).
_m03_e06_valider() { # TYPE_CPU
  (cd "$_m03_e06_d" && env CHECKPOINT_DISABLE=1 PKR_VAR_proxmox_url=https://controle.invalid:8006/api2/json \
    PKR_VAR_proxmox_username='controle@pve!controle' PKR_VAR_proxmox_token=controle-factice \
    PKR_VAR_proxmox_node=controle PKR_VAR_build_password=controle-factice \
    packer validate -var-file=../vars/lab.pkrvars.hcl -var "cpu_type=$1" . >/dev/null 2>&1)
}
_m03_e06_refuse() { ! _m03_e06_valider "$1"; }
check_cmd "configuration valide avec cpu_type=x86-64-v3" _m03_e06_valider x86-64-v3
check_cmd "configuration refusée avec cpu_type=x86-64-v2-AES (règle de validation)" _m03_e06_refuse x86-64-v2-AES

title "Template 9002 tpl-rocky10-base"
_m03_e06_conf="$(_m03_conf 9002)" || _m03_e06_conf=""
_m03_e06_a() { grep -Eq -- "$1" <<<"$_m03_e06_conf"; }
check_cmd "9002 est un template nommé tpl-rocky10-base" \
  bash -c 'grep -q "^template: 1" <<<"$1" && grep -q "^name: tpl-rocky10-base$" <<<"$1"' _ "$_m03_e06_conf"
check_cmd "9002 dans le pool lab" jq -e 'any(.[]; .vmid == 9002 and (.pool // "") == "lab")' <<<"$(_m03_vms)"
check_cmd "étiquettes base et rocky10" \
  bash -c 'grep -Eq "^tags: .*base" <<<"$1" && grep -Eq "^tags: .*rocky10" <<<"$1"' _ "$_m03_e06_conf"
check_cmd "type de CPU compatible avec Rocky Linux 10 (x86-64-v3, v4 ou host)" \
  _m03_e06_a '^cpu: (cputype=)?(x86-64-v3|x86-64-v4|host)(,|$)'
check_cmd "contrôleur virtio-scsi-single, agent, port série" \
  bash -c 'grep -q "^scsihw: virtio-scsi-single$" <<<"$1" && grep -Eq "^agent: (1|enabled=1)" <<<"$1" && grep -q "^serial0: socket" <<<"$1"' \
  _ "$_m03_e06_conf"
check_cmd "lecteur cloud-init présent, plus aucune ISO" \
  bash -c 'grep -Eq "^(ide|sata|scsi)[0-9]+: .*cloudinit" <<<"$1" && ! grep -q ":iso/" <<<"$1"' _ "$_m03_e06_conf"

title "VM de contrôle 2031 (clone de 9002)"
check_cmd "VM 2031 démarrée" _m03_en_marche 2031
check_cmd "2031 : Rocky Linux 10" _m03_gexec_match 2031 'cat /etc/os-release' '^VERSION_ID="?10\.'
check_cmd "2031 : cloud-init a terminé" _m03_gexec_match 2031 'cloud-init status' '^status: done'
check_cmd "2031 : SELinux en mode enforcing" _m03_gexec_match 2031 'getenforce' '^Enforcing'
check_cmd "2031 : admin membre de wheel" _m03_gexec_match 2031 'id -nG admin' '(^| )wheel( |$)'
