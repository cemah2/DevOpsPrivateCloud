# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes : évaluées par bash -c ou sur l'hôte distant
#
# check-E03.sh — M09-E03 : Installer Proxmox VE sans clavier
# À lancer depuis adm01. Lecture seule : qm config et stockages sur pve01, nœuds hv01 et hv02
# en root (SSH), DNS, NetBox (jeton des checks), copies de travail et main des projets GitLab.

# shellcheck source=_m09-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-decouverte.sh"

title "M09-E03 — Installer Proxmox VE sans clavier"
require_cmd jq dig

# --- 1. Le code ----------------------------------------------------------------------------------
check_cmd "plateforme/infra (main) : état « hv » (envs/hv/main.tf)" _m09d_fichier_main plateforme/infra envs/hv/main.tf
_m09d_e03_installation_main() {
  _m09d_fichier_main plateforme/infra envs/hv/installation/reponse.toml.modele \
    && _m09d_fichier_main plateforme/infra envs/hv/installation/preparer-iso.sh
}
check_cmd "plateforme/infra (main) : modèle de fichier de réponse et script de préparation des ISO" \
  _m09d_e03_installation_main
check_cmd "Fichier de réponse : clés en kebab-case, pas de mot de passe en clair" \
  bash -c 'f="$1/envs/hv/installation/reponse.toml.modele"; [ -s "$f" ] \
    && grep -Eq "^root-password-hashed" "$f" && ! grep -Eq "^(root_password|root-password)[[:space:]]*=" "$f" \
    && ! grep -Eq "^[a-z]+_[a-z_]+[[:space:]]*=" "$f"' _ "$_M09D_INFRA"
_m09d_e03_ansible_main() {
  _m09d_fichier_main plateforme/ansible roles/pve_noeud/tasks/main.yml \
    && _m09d_fichier_main plateforme/ansible playbooks/hv.yml \
    && _m09d_fichier_main plateforme/ansible inventories/lab/hv.yml
}
check_cmd "plateforme/ansible (main) : rôle pve_noeud, inventaire hv.yml et playbook hv.yml" _m09d_e03_ansible_main
check_cmd "adm01 : mot de passe root des nœuds dans ~/.config/workbook/hv-root.pass (600)" \
  bash -c '[ -s "$1" ] && [ "$(stat -c %a "$1")" = 600 ]' _ "$HOME/.config/workbook/hv-root.pass"

# --- 2. Les ISO préparées --------------------------------------------------------------------------
for _m09d_e03_n in hv01 hv02; do
  check_ssh "pve01 : ISO préparée hdd-bulk:iso/pve92-auto-$_m09d_e03_n.iso" "$_M09D_PVE" \
    "pvesm list hdd-bulk --content iso | grep -q 'hdd-bulk:iso/pve92-auto-$_m09d_e03_n\.iso'"
done

# --- 3. Les VMs et les nœuds -----------------------------------------------------------------------
_m09d_controler_vm_noeud hv01 1
_m09d_controler_vm_noeud hv02 2
_m09d_controler_noeud_configure hv01 1
_m09d_controler_noeud_configure hv02 2

# --- 4. Entre les nœuds ---------------------------------------------------------------------------
check_ssh "hv01 joint hv02 sur le réseau Corosync (10.10.32.52)" hv01 'ping -c 2 -W 2 10.10.32.52 >/dev/null'
check_ssh "hv01 joint hv02 sur le réseau Ceph cluster en trames de 9000 octets" hv01 \
  'ping -c 1 -W 2 -M do -s 8972 10.10.31.72 >/dev/null'
