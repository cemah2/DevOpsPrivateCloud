# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres ($1…)
#
# check-E04.sh — M05-E04 : Première VM déclarée
# À lancer depuis adm01. Lecture seule : configuration de la VM 2050 lue en root sur pve01
# (qm config, qm cloudinit dump, agent QEMU), port SSH testé depuis adm01, code et état de
# envs/lab-m05, « tofu fmt -check » et « tofu plan » sans verrou ni enregistrement (1 à 2 min).

# shellcheck source=_m05-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-decouverte.sh"

title "M05-E04 — Première VM déclarée"
require_cmd git jq curl tofu

# --- La VM 2050 dans Proxmox --------------------------------------------------------------------
_m05_cfg="$(_m05_qm_config 2050)"
check_cmd "Proxmox : la VM 2050 existe" test -n "$_m05_cfg"
check_output "nom : m05-essai" '^m05-essai$' _m05_cle "$_m05_cfg" name
check_cmd "ce n'est pas un template" bash -c '! grep -q "^template: 1" <<<"$1"' _ "$_m05_cfg"
_m05_res="$(_m05_ressource 2050)"
check_output "dans le pool lab" '^lab$' _m05_val "$_m05_res" '.pool // empty'
check_output "démarrée" '^running$' _m05_val "$_m05_res" '.status // empty'
check_cmd "étiquette env-m05, et aucune étiquette héritée ou réservée (gold, current, socle…)" \
  _m05_etiquettes_saines 2050
check_cmd "ne démarre pas avec pve01 (on_boot = false)" bash -c '! grep -q "^onboot: 1" <<<"$1"' _ "$_m05_cfg"
check_output "agent QEMU activé" '^(1|enabled=1)' _m05_cle "$_m05_cfg" agent
check_output "contrôleur virtio-scsi-single (comme l'image dorée)" '^virtio-scsi-single$' _m05_cle "$_m05_cfg" scsihw
_m05_scsi0="$(_m05_cle "$_m05_cfg" scsi0)"
check_output "disque scsi0 sur $_M05_STOCKAGE" "^$_M05_STOCKAGE:" printf '%s\n' "$_m05_scsi0"
# Un clone lié référence le volume du template : « base-90xx-disk-N/vm-2050-disk-M ».
check_cmd "clone complet : le disque ne dépend pas du volume du template" \
  bash -c '[[ -n "$1" && "$1" != *base-* ]]' _ "$_m05_scsi0"
check_output "disque scsi0 de 10 Go au moins" '^ok$' \
  bash -c 's="$(grep -oE "size=[0-9]+G" <<<"$1" | grep -oE "[0-9]+")"; [ "${s:-0}" -ge 10 ] && echo ok' _ "$_m05_scsi0"
check_output "carte réseau sur le VNet vsandbox" 'bridge=vsandbox([,]|$)' _m05_cle "$_m05_cfg" net0
check_output "cloud-init : compte admin" '^admin$' _m05_cle "$_m05_cfg" ciuser
check_output "cloud-init : adresse par DHCP" '^ip=dhcp' _m05_cle "$_m05_cfg" ipconfig0
check_output "cloud-init : résolveur 10.10.20.10" '^10\.10\.20\.10$' _m05_cle "$_m05_cfg" nameserver
check_output "cloud-init : domaine par1.medisphere.internal" '^par1\.medisphere\.internal$' _m05_cle "$_m05_cfg" searchdomain
# Le corps de la clé publique (2e champ) ne contient que [A-Za-z0-9+/=] : sûr dans une commande.
_m05_cle_pub="$(awk '{print $2}' "$HOME/.ssh/id_ed25519.pub" 2>/dev/null || true)"
check_cmd "cloud-init : la clé publique d'adm01 est autorisée pour admin" \
  bash -c '[[ "$2" =~ ^[A-Za-z0-9+/=]+$ ]] && grep -qF -- "$2" <<<"$1"' _ \
  "$(_m05_pve "qm cloudinit dump 2050 user 2>/dev/null")" "$_m05_cle_pub"

# --- La VM vivante ------------------------------------------------------------------------------------
_m05_ip="$(_m05_ipv4_agent 2050)"
check_output "l'agent QEMU répond et rapporte une adresse DHCP du VLAN 99 (10.10.99.100-199)" \
  '^10\.10\.99\.1[0-9]{2}$' printf '%s\n' "$_m05_ip"
check_output "nom d'hôte dans la VM : m05-essai" '^m05-essai' _m05_guest_sortie 2050 hostname
if [[ -n "$_m05_ip" ]]; then
  check_port "SSH joignable depuis adm01 ($_m05_ip:22)" "$_m05_ip" 22
else
  skip "SSH joignable depuis adm01" "adresse inconnue : l'agent n'a rien rapporté"
fi

# --- Le code ------------------------------------------------------------------------------------------
check_cmd "envs/lab-m05 : ressource de type proxmox_virtual_environment_vm" \
  _m05_tf_contient '^[[:space:]]*resource[[:space:]]+"proxmox_virtual_environment_vm"'
check_cmd "aucune ressource expérimentale proxmox_vm" \
  bash -c '! grep -Eqs "^[[:space:]]*resource[[:space:]]+\"proxmox_vm\"" "$1"/*.tf' _ "$_M05_ENV"
check_cmd "code formaté (tofu fmt -check)" _m05_tofu fmt -check -no-color
check_output "main : envs/lab-m05 déclare la VM d'essai" \
  'resource[[:space:]]+"proxmox_virtual_environment_vm"[[:space:]]+"essai"' _m05_tf_main

# --- État et plan ---------------------------------------------------------------------------------------
_m05_controles_etat_et_plan "l'état connaît une VM proxmox_virtual_environment_vm de VMID 2050" \
  '[.resources[]? | select(.mode == "managed" and .type == "proxmox_virtual_environment_vm")
    | .instances[].attributes.vm_id] | index(2050) != null'
