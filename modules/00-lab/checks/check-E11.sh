# shellcheck shell=bash
# M00-E11 — Fabriquer le template cloud-init tpl-debian13.
# Lecture seule. Les contrôles s'exécutent sur pve01 (WB_PVE_HOST).

title "M00-E11 — Fabriquer le template cloud-init tpl-debian13"

NVME="${WB_STORAGE_NVME:-local-nvme}"
BULK="${WB_STORAGE_BULK:-hdd-bulk}"
SNIPPET="$BULK:snippets/vendor-debian13.yaml"

_m00_vm() {
  printf "pvesh get /cluster/resources --type vm --output-format json | perl -MJSON::PP -0777 -ne 'exit(!grep { \$_->{vmid} == %d && (\$_->{%s} // q{}) eq q{%s} } @{decode_json(\$_)})'" "$1" "$2" "$3"
}

check_ssh "la VM 9000 s'appelle tpl-debian13" "$WB_PVE_HOST" "$(_m00_vm 9000 name tpl-debian13)"
check_ssh "9000 est dans le pool lab" "$WB_PVE_HOST" "$(_m00_vm 9000 pool lab)"
check_ssh_output "9000 est un template" "$WB_PVE_HOST" '^template: 1' "qm config 9000"
check_ssh_output "contrôleur virtio-scsi-single" "$WB_PVE_HOST" '^scsihw: virtio-scsi-single$' "qm config 9000"
check_ssh_output "disque scsi0 (image de base) sur $NVME" "$WB_PVE_HOST" "^scsi0: ${NVME}:.*base-9000-disk" "qm config 9000"
check_ssh_output "amorçage sur scsi0" "$WB_PVE_HOST" '^boot: order=scsi0$' "qm config 9000"
check_ssh_output "lecteur cloud-init en ide2" "$WB_PVE_HOST" '^ide2: .*cloudinit' "qm config 9000"
# Après M00-E28, le template peut pointer sur le VNet vsandbox au lieu de vmbr1.
check_ssh_output "net0 sur vmbr1 (ou sur le VNet vsandbox après E28)" "$WB_PVE_HOST" '^net0: .*bridge=(vmbr1|vsandbox)(,|$)' "qm config 9000"
check_ssh_output "console série (serial0: socket)" "$WB_PVE_HOST" '^serial0: socket$' "qm config 9000"
check_ssh_output "affichage redirigé sur la console série (vga: serial0)" "$WB_PVE_HOST" '^vga: serial0$' "qm config 9000"
check_ssh_output "agent QEMU activé" "$WB_PVE_HOST" '^agent: (1|enabled=1)' "qm config 9000"
check_ssh_output "utilisateur cloud-init admin" "$WB_PVE_HOST" '^ciuser: admin$' "qm config 9000"
check_ssh_output "clé SSH cloud-init renseignée" "$WB_PVE_HOST" '^sshkeys: ssh-' "qm config 9000"
check_ssh_output "résolveur 10.10.20.10" "$WB_PVE_HOST" '^nameserver: 10\.10\.20\.10$' "qm config 9000"
check_ssh_output "domaine de recherche par1.medisphere.internal" "$WB_PVE_HOST" \
  '^searchdomain: par1\.medisphere\.internal$' "qm config 9000"
check_ssh_output "vendor-data personnalisé ($SNIPPET)" "$WB_PVE_HOST" \
  "^cicustom: .*vendor=${SNIPPET//./\\.}" "qm config 9000"
check_ssh "le snippet vendor-debian13.yaml existe" "$WB_PVE_HOST" \
  "test -s \"\$(pvesm path $SNIPPET)\""
check_ssh "le snippet commence par #cloud-config" "$WB_PVE_HOST" \
  "head -n1 \"\$(pvesm path $SNIPPET)\" | grep -q '^#cloud-config'"
check_ssh "le snippet installe qemu-guest-agent" "$WB_PVE_HOST" \
  "grep -q 'qemu-guest-agent' \"\$(pvesm path $SNIPPET)\""
