# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E03.sh — M03-E03 « Premier build : proxmox-clone depuis tpl-debian13 »
# À lancer AVANT de supprimer le template d'essai 9090. Lecture seule.

# shellcheck source=_m03-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m03-production.sh"

title "M03-E03 — Premier build : proxmox-clone depuis tpl-debian13"
require_cmd jq packer
_m03_charger
_m03_e03_dir="$HOME/m03/e03"

title "Fichier Packer et notes (~/m03/e03)"
check_cmd "essai.pkr.hcl présent" test -s "$_m03_e03_dir/essai.pkr.hcl"
check_cmd "essai.pkr.hcl bien formaté (packer fmt -check)" packer fmt -check "$_m03_e03_dir/essai.pkr.hcl"
check_cmd "essai.pkr.hcl déclare le plugin proxmox (required_plugins)" \
  grep -Eq 'source *= *"github\.com/hashicorp/proxmox"' "$_m03_e03_dir/essai.pkr.hcl"
check_cmd "le jeton est une variable marquée sensitive" grep -Eq 'sensitive *= *true' "$_m03_e03_dir/essai.pkr.hcl"
check_cmd "aucune vérification TLS désactivée" \
  bash -c '! grep -Eq "insecure_skip_tls_verify *= *true" "$1"' _ "$_m03_e03_dir/essai.pkr.hcl"
check_cmd "notes.md rédigé (étapes du build, comparaison des clones)" test -s "$_m03_e03_dir/notes.md"

title "Template d'essai 9090"
_m03_e03_conf="$(_m03_conf 9090)" || _m03_e03_conf=""
_m03_e03_a() { grep -Eq -- "$1" <<<"$_m03_e03_conf"; }
check_cmd "9090 existe et est un template" _m03_e03_a '^template: 1'
check_cmd "9090 s'appelle tpl-essai-e03" _m03_e03_a '^name: tpl-essai-e03$'
check_cmd "9090 est dans le pool lab" \
  jq -e 'any(.[]; .vmid == 9090 and (.pool // "") == "lab")' <<<"$(_m03_vms)"
check_cmd "contrôleur virtio-scsi-single (pas la valeur par défaut du plugin)" _m03_e03_a '^scsihw: virtio-scsi-single$'
check_cmd "CPU x86-64-v2-AES (pas kvm64)" _m03_e03_a '^cpu: (cputype=)?x86-64-v2-AES'
check_cmd "mémoire 2048 Mo" _m03_e03_a '^memory: 2048$'
check_cmd "console série conservée (serial0: socket, vga: serial0)" \
  bash -c 'grep -q "^serial0: socket" <<<"$1" && grep -q "^vga: serial0" <<<"$1"' _ "$_m03_e03_conf"
check_cmd "agent QEMU activé" _m03_e03_a '^agent: (1|enabled=1)'
check_cmd "lecteur cloud-init présent sur le template" _m03_e03_a '^(ide|sata|scsi)[0-9]+: .*cloudinit'

# Le template a été converti par le jeton de Packer (journal des tâches de pve01 ; la tâche
# de clonage est rattachée au VMID source, 9000, d'où ce seul contrôle).
_m03_e03_taches="$(remote "$WB_PVE_HOST" 'pvesh get "/nodes/$(hostname)/tasks" --vmid 9090 --source all --limit 50 --output-format json' 2>/dev/null)" \
  || _m03_e03_taches="[]"
check_cmd "conversion en template faite par wb-packer@pve!packer (journal des tâches)" \
  jq -e 'any(.[]; .type == "qmtemplate" and (.user // "") == "wb-packer@pve!packer")' <<<"$_m03_e03_taches"

title "Hygiène"
check_cmd "clones de comparaison 2030 et 2031 détruits" _m03_aucune_vm 2030 2031
