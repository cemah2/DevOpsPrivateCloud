# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E07.sh — M10-E07 : Nova : gabarits, clés et première instance
# À lancer depuis adm01. Lecture seule : CLI openstack (flavor show, keypair show, subnet show,
# server show, console log show) avec WB_OS_CLOUD et le cloud medisphere-plateforme (E05),
# empreinte de ~/.ssh/id_ed25519.pub, API GitLab en GET.

# shellcheck source=_m10-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-decouverte.sh"

title "M10-E07 — Nova : gabarits, clés et première instance"
require_cmd jq openstack ssh-keygen

_m10d_e07_p="medisphere-plateforme"

# --- 1. Gabarits ---------------------------------------------------------------------------------
# _m10d_e07_gabarit NOM VCPU RAM DISQUE — gabarit public avec exactement ces ressources.
_m10d_e07_gabarit() {
  _m10d_jq "$(_m10d_os flavor show "$1")" \
    ".vcpus == $2 and .ram == $3 and .disk == $4 and (.\"OS-FLV-EXT-DATA:ephemeral\" // 0) == 0
     and (.\"os-flavor-access:is_public\" // .is_public) == true"
}
check_cmd "m1.petit : 1 vCPU, 1024 Mio, 10 Go, public" _m10d_e07_gabarit m1.petit 1 1024 10
check_cmd "m1.moyen : 2 vCPU, 2048 Mio, 20 Go, public" _m10d_e07_gabarit m1.moyen 2 2048 20
check_cmd "m1.grand : 2 vCPU, 4096 Mio, 40 Go, public" _m10d_e07_gabarit m1.grand 2 4096 40
check_cmd "plateforme/openstack (main) : playbooks/catalogue.yml" \
  _m10d_fichier_main plateforme/openstack playbooks/catalogue.yml

# --- 2. Paire de clés ----------------------------------------------------------------------------
_m10d_e07_fp_local="$(ssh-keygen -E md5 -lf "$HOME/.ssh/id_ed25519.pub" 2>/dev/null | awk '{print $2}' | sed 's/^MD5://' || true)"
_m10d_e07_kp="$(_m10d_os --os-cloud "$_m10d_e07_p" keypair show cle-adm01)"
check_cmd "Paire cle-adm01 (ton compte) : même clé que ~/.ssh/id_ed25519.pub de adm01" \
  _m10d_jq "$_m10d_e07_kp" ".fingerprint == \"$_m10d_e07_fp_local\" and \"$_m10d_e07_fp_local\" != \"\""

# --- 3. Réseau du projet ----------------------------------------------------------------------
_m10d_e07_sn="$(_m10d_os --os-cloud "$_m10d_e07_p" subnet show sous-reseau-plateforme)"
check_cmd "sous-reseau-plateforme : 172.16.10.0/24, DHCP, résolveurs 10.10.20.10 et 10.10.20.16" _m10d_jq "$_m10d_e07_sn" \
  '.cidr == "172.16.10.0/24" and .enable_dhcp == true
   and ((.dns_nameservers | tostring) | test("10\\.10\\.20\\.10")) and ((.dns_nameservers | tostring) | test("10\\.10\\.20\\.16"))'
_m10d_e07_net="$(_m10d_os --os-cloud "$_m10d_e07_p" network show reseau-plateforme)"
_m10d_e07_snid="$(jq -r '.id // "absent"' <<<"${_m10d_e07_sn:-null}" 2>/dev/null || echo absent)"
check_cmd "reseau-plateforme appartient au projet plateforme et porte ce sous-réseau" _m10d_jq "$_m10d_e07_net" \
  ".project_id == \"$(_m10d_id_projet plateforme)\" and ((.subnets | tostring) | contains(\"$_m10d_e07_snid\"))"

# --- 4. L'instance -------------------------------------------------------------------------------
_m10d_e07_vm="$(_m10d_os --os-cloud "$_m10d_e07_p" server show essai01)"
check_cmd "essai01 : ACTIVE dans le projet plateforme" _m10d_jq "$_m10d_e07_vm" \
  ".status == \"ACTIVE\" and .project_id == \"$(_m10d_id_projet plateforme)\""
check_cmd "essai01 : gabarit m1.petit, image debian-13, clé cle-adm01" _m10d_jq "$_m10d_e07_vm" \
  '((.flavor | tostring) | test("m1\\.petit")) and ((.image | tostring) | test("debian-13")) and .key_name == "cle-adm01"'
check_cmd "essai01 : une adresse dans 172.16.10.0/24" _m10d_jq "$_m10d_e07_vm" \
  '(.addresses | tostring) | test("172\\.16\\.10\\.[0-9]+")'
check_output "essai01 : le journal de console montre la fin de cloud-init" 'Cloud-init v\. .* finished' \
  timeout 60 openstack --os-cloud "$_m10d_e07_p" console log show essai01
