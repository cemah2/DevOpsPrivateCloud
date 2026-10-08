# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant ou par bash -c
# check-E15.sh — M11-E15 « De la source de vérité au serveur en service » : pour chaque équipement
# serveur-bm « active » : nom résolu vers son IP NetBox, SSH avec clé d'hôte reconnue (certificat),
# racine de la PKI, présent dans l'inventaire Ansible, journal NetBox ; au moins un BIOS/Debian et un
# UEFI/Rocky ; outil et documentation sur main. Lecture seule.

# shellcheck source=_m11-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m11-production.sh"

title "M11-E15 — Serveurs mis en service depuis NetBox"
require_cmd curl jq ssh dig

mapfile -t _m11_e15_actifs < <(_m11p_bm_actifs)
check_cmd "NetBox : au moins deux équipements serveur-bm à l'état active" test "${#_m11_e15_actifs[@]}" -ge 2

# Inventaire Ansible : celui par défaut du projet, plus les fichiers d'inventaire NetBox
# supplémentaires (inventories/lab/*netbox*.yml : netbox-bm.yml dans le corrigé).
_m11_e15_sources=()
for _m11_e15_f in "$_m11p_src"/ansible/inventories/lab/*netbox*.yml; do
  if [[ -f "$_m11_e15_f" ]]; then _m11_e15_sources+=(-i "inventories/lab/${_m11_e15_f##*/}"); fi
done
_m11_e15_inv="$(_m11p_ansible ansible-inventory "${_m11_e15_sources[@]}" --list 2>/dev/null)" || true
_m11_e15_bios_debian=0
_m11_e15_uefi_rocky=0
for _m11_e15_l in "${_m11_e15_actifs[@]}"; do
  read -r _m11_e15_nom _m11_e15_ip <<<"$_m11_e15_l"
  _m11_e15_fqdn="$_m11_e15_nom.$_m11p_zone"
  check_cmd "$_m11_e15_nom : IP primaire dans NetBox" test -n "$_m11_e15_ip"
  check_dns "$_m11_e15_nom : $_m11_e15_fqdn résolu vers $_m11_e15_ip" "$_m11_e15_fqdn" A "^${_m11_e15_ip//./\\.}\$" 10.10.20.10
  # Connexion neuve, clé d'hôte vérifiée sans question (certificat d'hôte et @cert-authority).
  check_cmd "$_m11_e15_nom : SSH depuis adm01, clé d'hôte reconnue (StrictHostKeyChecking=yes)" \
    ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o ControlPath=none -o ConnectTimeout=8 "admin@$_m11_e15_fqdn" true
  check_cmd "$_m11_e15_nom : racine MédiSphère installée" \
    ssh -o BatchMode=yes -o ControlPath=none -o ConnectTimeout=8 "admin@$_m11_e15_fqdn" \
    'test -s /usr/local/share/ca-certificates/medisphere-root-ca.crt || test -s /etc/pki/ca-trust/source/anchors/medisphere-root-ca.crt'
  check_cmd "$_m11_e15_nom : présent dans l'inventaire Ansible" \
    bash -c 'jq -e --arg h "$1" "._meta.hostvars | has(\$h)" <<<"$2" >/dev/null' _ "$_m11_e15_nom" "$_m11_e15_inv"
  _m11_e15_id="$(_m11p_equipement "$_m11_e15_nom" | jq -r '.id')" || true
  _m11_e15_nj="$(netbox_api "extras/journal-entries/?assigned_object_type=dcim.device&assigned_object_id=$_m11_e15_id&limit=1" 2>/dev/null | jq -r '.count // 0')" || true
  check_cmd "$_m11_e15_nom : journal NetBox des transitions (au moins 3 entrées)" test "${_m11_e15_nj:-0}" -ge 3
  # Famille du système et micrologiciel de la VM
  _m11_e15_os="$(ssh -o BatchMode=yes -o ControlPath=none -o ConnectTimeout=8 "admin@$_m11_e15_fqdn" 'sed -n "s/^ID=//p" /etc/os-release' 2>/dev/null | tr -d '"')" || true
  _m11_e15_vmid="${_m11p_vmid[$_m11_e15_nom]:-}"
  _m11_e15_bios="seabios"
  if [[ -n "$_m11_e15_vmid" ]] && remote "$WB_PVE_HOST" "qm config $_m11_e15_vmid | grep -q '^bios: ovmf'" >/dev/null 2>&1; then
    _m11_e15_bios="ovmf"
  fi
  if [[ "$_m11_e15_os" == debian && "$_m11_e15_bios" == seabios ]]; then _m11_e15_bios_debian=1; fi
  if [[ "$_m11_e15_os" == rocky && "$_m11_e15_bios" == ovmf ]]; then _m11_e15_uefi_rocky=1; fi
done
check_cmd "au moins un serveur BIOS (SeaBIOS) en Debian mis en service" test "$_m11_e15_bios_debian" -eq 1
check_cmd "au moins un serveur UEFI (OVMF) en Rocky mis en service" test "$_m11_e15_uefi_rocky" -eq 1

check_cmd "docs/provisioning/orchestration.md sur main de plateforme/medisphere" \
  _m11p_gitlab_fichier plateforme/medisphere docs/provisioning/orchestration.md
check_output "RB-110 sur main (docs/provisioning/runbooks/)" '^RB-110' _m11p_gitlab_ls plateforme/medisphere docs/provisioning/runbooks
check_output "pipeline de plateforme/provisioning : un job manuel (when: manual)" 'when:[[:space:]]*manual' \
  _m11p_gitlab_brut plateforme/provisioning .gitlab-ci.yml
skip "relance sans effet et redémarrage sans réinstallation" "auto-évaluation : démontre-les (sortie et code de retour, console) dans ton compte rendu"
