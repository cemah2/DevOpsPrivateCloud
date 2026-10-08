# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes entre apostrophes : pas d'expansion voulue
#
# check-E23.sh — M09-E23 : Importer une VM venue d'ailleurs
# À lancer depuis adm01, legacy-rdv01 (150) démarrée. Lecture seule (configuration, ping de l'agent QEMU,
# liste des sauvegardes).

# shellcheck source=_m09-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-operationnel.sh"

title "M09-E23 — Importer une VM venue d'ailleurs"
require_cmd jq

_m09o_res="$(_m09o_ressources)"
_m09o_c="$(_m09o_conf 150)"
check_cmd "invité 150 legacy-rdv01 existe, dans le pool prod" _m09o_json "$_m09o_res" \
  'map(select(.vmid == 150))[0] | . != null and .name == "legacy-rdv01" and .pool == "prod"'
check_cmd "150 : disque(s) sur ceph-vm" _m09o_disques_sur "$_m09o_c" ceph-vm
check_output "150 : contrôleur virtio-scsi-single" '^scsihw: virtio-scsi-single$' echo "$_m09o_c"
check_output "150 : carte virtio sur le VNet vinv99" '^net0: virtio=[^,]+,.*bridge=vinv99' echo "$_m09o_c"
check_cmd "150 : aucune carte e1000/vmxnet3 restante" bash -c '[[ -n "$1" ]] && ! grep -Eq "^net[0-9]+: (e1000|e1000e|vmxnet3)" <<<"$1"' _ "$_m09o_c"
check_cmd "150 : aucun disque SATA/IDE hors lecteur cloud-init" bash -c \
  '[[ -n "$1" ]] && ! grep -E "^(sata|ide)[0-9]+: " <<<"$1" | grep -v "cloudinit" | grep -vq "media=cdrom"' _ "$_m09o_c"
check_output "150 : type de CPU explicite (x86-64-v2-AES ou host…), pas celui par défaut de l'import" '^cpu: ' echo "$_m09o_c"
check_output "150 : console série" '^serial0: socket' echo "$_m09o_c"
check_output "150 : agent QEMU activé dans la configuration" '^agent: (1|enabled=1)' echo "$_m09o_c"

_m09o_n="$(jq -r 'map(select(.vmid == 150))[0].node // empty' <<<"$_m09o_res" 2>/dev/null || true)"
if [[ -n "$_m09o_n" ]]; then
  check_ssh "150 : l'agent QEMU répond (depuis $_m09o_n)" "$_m09o_n" 'qm guest cmd 150 ping >/dev/null 2>&1'
  check_cmd "150 : au moins une sauvegarde sur pbs-par2" _m09o_json \
    "$(_m09o_hv "$_m09o_n" "pvesh get /nodes/$_m09o_n/storage/pbs-par2/content --vmid 150 --output-format json")" \
    'map(select(.vmid == 150)) | length > 0'
else
  skip "agent et sauvegarde de 150" "invité 150 introuvable"
fi
