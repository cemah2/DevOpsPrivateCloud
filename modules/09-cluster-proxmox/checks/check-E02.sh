# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes : évaluées par bash -c ou sur pve01
#
# check-E02.sh — M09-E02 : Préparer la virtualisation imbriquée
# À lancer depuis adm01. Lecture seule : paramètres du noyau, mémoire, ACL, stockages et VMs
# de pve01 (root), copie de travail et branche main de plateforme/images.

# shellcheck source=_m09-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-decouverte.sh"

title "M09-E02 — Préparer la virtualisation imbriquée"
require_cmd jq

# --- 1. L'hyperviseur sait imbriquer ------------------------------------------------------------
check_ssh "pve01 : extensions de virtualisation matérielles présentes (vmx ou svm)" "$_M09D_PVE" \
  'grep -Eqm1 "\b(vmx|svm)\b" /proc/cpuinfo'
check_ssh_output "pve01 : virtualisation imbriquée active dans le module KVM" "$_M09D_PVE" '^(Y|1)$' \
  'cat /sys/module/kvm_intel/parameters/nested 2>/dev/null || cat /sys/module/kvm_amd/parameters/nested'

# --- 2. La place -------------------------------------------------------------------------------
# Mémoire disponible + mémoire des nœuds hv déjà en marche (le contrôle reste vrai après E03).
check_ssh "pve01 : au moins 40 Gio de mémoire pour le profil infra (disponible + nœuds hv en marche)" "$_M09D_PVE" \
  'dispo=$(awk "/^MemAvailable:/ {print int(\$2/1024)}" /proc/meminfo); hv=$(pvesh get /cluster/resources --type vm --output-format json | jq "[.[] | select(.vmid >= 2091 and .vmid <= 2093 and .status == \"running\") | .maxmem] | add // 0 | . / 1048576 | floor"); [ $(( (dispo + hv) / 1024 )) -ge 40 ]'
check_ssh "pve01 : ceph01-03 (2081-2083) arrêtées (elles ne servent qu'en M09-E12)" "$_M09D_PVE" \
  'for v in 2081 2082 2083; do s=$(qm status $v 2>/dev/null | awk "{print \$2}"); [ -z "$s" ] || [ "$s" = stopped ] || exit 1; done'
check_ssh "pve01 : VM d'essai 2099 détruite" "$_M09D_PVE" '! qm status 2099 >/dev/null 2>&1'

# --- 3. L'ISO officielle, vérifiée, et l'outil de préparation -----------------------------------
check_ssh "pve01 : ISO officielle de Proxmox VE 9.2 sur hdd-bulk" "$_M09D_PVE" \
  'pvesm list hdd-bulk --content iso | grep -Eq "hdd-bulk:iso/proxmox-ve_9\.2-[0-9]+\.iso"'
check_ssh "pve01 : proxmox-auto-install-assistant et xorriso installés" "$_M09D_PVE" \
  'dpkg-query -W -f="\${Status}\n" proxmox-auto-install-assistant xorriso 2>/dev/null | grep -c "install ok installed" | grep -qx 2'
check_cmd "plateforme/images (copie de travail) : deposer-iso.sh connaît la famille proxmox-ve" \
  grep -q 'proxmox-ve)' "${WB_SRC:-$HOME/src}/images/outils/deposer-iso.sh"
check_cmd "plateforme/images (copie de travail) : la signature de l'ISO Proxmox est vérifiée (VALIDSIG)" \
  bash -c 'sed -n "/proxmox-ve)/,\$p" "$1" | grep -q "VALIDSIG"' _ "${WB_SRC:-$HOME/src}/images/outils/deposer-iso.sh"
check_cmd "plateforme/images (main) : outils/deposer-iso.sh publié" _m09d_fichier_main plateforme/images outils/deposer-iso.sh

# --- 4. Le droit d'OpenTofu sur le pont des invités -----------------------------------------------
check_ssh "pve01 : wb-tofu@pve peut utiliser le pont vmbr1 (SDN.Use sur /sdn/zones/localnetwork/vmbr1)" "$_M09D_PVE" \
  'pveum acl list --output-format json | jq -e "[.[] | select(.path == \"/sdn/zones/localnetwork/vmbr1\" and (.ugid | startswith(\"wb-tofu@pve\")))] | length >= 1" >/dev/null'
check_ssh "pve01 : wb-tofu@pve a accès aux stockages ssd-lab et hdd-bulk" "$_M09D_PVE" \
  'pveum acl list --output-format json | jq -e "[.[] | select(.ugid | startswith(\"wb-tofu@pve\")) | .path] as \$p | (\$p | index(\"/\") != null or index(\"/storage\") != null) or ((\$p | index(\"/storage/ssd-lab\") != null) and (\$p | index(\"/storage/hdd-bulk\") != null))" >/dev/null'
