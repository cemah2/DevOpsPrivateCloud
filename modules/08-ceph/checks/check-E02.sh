# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E02.sh — M08-E02 : Préparer les nœuds Ceph
# À lancer depuis adm01. Lecture seule : qm config sur pve01, DNS, état des nœuds en SSH
# (sudo -n), NetBox (jeton des checks), API GitLab en GET.

# shellcheck source=_m08-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-decouverte.sh"

title "M08-E02 — Préparer les nœuds Ceph"

# _m08d_e02_netbox NOM IP/MASQUE — la VM existe dans NetBox, active, avec cette IP primaire.
_m08d_e02_netbox() {
  netbox_api "virtualization/virtual-machines/?name=$1" 2>/dev/null \
    | jq -e --arg ip "$2" '.count == 1 and .results[0].status.value == "active" and .results[0].primary_ip4.address == $ip' >/dev/null
}
require_cmd jq dig curl

for _m08d_e02_n in 1 2 3; do
  _m08d_e02_nom="ceph0${_m08d_e02_n}"
  _m08d_e02_vmid="208${_m08d_e02_n}"
  _m08d_e02_pub="10.10.30.5${_m08d_e02_n}"
  _m08d_e02_clu="10.10.31.5${_m08d_e02_n}"
  _m08d_e02_conf="$(_m08d_qm "$_m08d_e02_vmid")"

  # --- 1. La VM (Proxmox) ----------------------------------------------------------------------
  check_cmd "VM $_m08d_e02_vmid nommée $_m08d_e02_nom" _m08d_qm_a "$_m08d_e02_conf" "^name: ${_m08d_e02_nom}$"
  check_cmd "$_m08d_e02_nom : étiquettes env-m08 et role-ceph" _m08d_etiquettes "$_m08d_e02_conf" env-m08 role-ceph
  check_cmd "$_m08d_e02_nom : membre du pool lab" _m08d_dans_pool "$_m08d_e02_vmid"
  check_cmd "$_m08d_e02_nom : créée par OpenTofu avec le module vm-noeud" _m08d_qm_a "$_m08d_e02_conf" 'vm-noeud'
  check_cmd "$_m08d_e02_nom : 2 vCPU, 6144 Mo, CPU x86-64-v3 ou host" \
    bash -c 'grep -q "^cores: 2$" <<<"$1" && grep -q "^memory: 6144$" <<<"$1" && grep -Eq "^cpu: (x86-64-v3|host)" <<<"$1"' _ "$_m08d_e02_conf"
  check_cmd "$_m08d_e02_nom : net0 sur vstopub et net1 sur vstoclu, MTU 9000 sur les deux" \
    bash -c 'grep -Eq "^net0: .*bridge=vstopub.*mtu=9000" <<<"$1" && grep -Eq "^net1: .*bridge=vstoclu.*mtu=9000" <<<"$1"' _ "$_m08d_e02_conf"
  check_cmd "$_m08d_e02_nom : contrôleur virtio-scsi-single, disque système sur $_M08D_NVME" \
    bash -c 'grep -q "^scsihw: virtio-scsi-single$" <<<"$1" && grep -Eq "^scsi0: $2:" <<<"$1"' _ "$_m08d_e02_conf" "$_M08D_NVME"
  check_cmd "$_m08d_e02_nom : scsi1 sur $_M08D_SSD, 64 Gio, présenté SSD, hors sauvegarde" \
    _m08d_disque "$_m08d_e02_conf" scsi1 "$_M08D_SSD" 64G 1
  check_cmd "$_m08d_e02_nom : scsi2 sur $_M08D_SSD, 64 Gio, présenté SSD, hors sauvegarde" \
    _m08d_disque "$_m08d_e02_conf" scsi2 "$_M08D_SSD" 64G 1
  check_cmd "$_m08d_e02_nom : scsi3 sur $_M08D_BULK, 64 Gio, rotatif (sans ssd=1), hors sauvegarde" \
    _m08d_disque "$_m08d_e02_conf" scsi3 "$_M08D_BULK" 64G 0

  # --- 2. Nom et NetBox --------------------------------------------------------------------------
  check_dns "DNS : $_m08d_e02_nom.par1.medisphere.internal → $_m08d_e02_pub" \
    "$_m08d_e02_nom.par1.medisphere.internal" A "^${_m08d_e02_pub//./\\.}$" "$_M08D_DNS"
  check_dns "DNS : $_m08d_e02_pub → $_m08d_e02_nom (PTR)" "$(awk -F. '{print $4"."$3"."$2"."$1}' <<<"$_m08d_e02_pub").in-addr.arpa" PTR \
    "^${_m08d_e02_nom}\.par1\.medisphere\.internal\.$" "$_M08D_DNS"
  check_cmd "NetBox : $_m08d_e02_nom active, IP primaire $_m08d_e02_pub/24" \
    _m08d_e02_netbox "$_m08d_e02_nom" "$_m08d_e02_pub/24"

  # --- 3. Le système ---------------------------------------------------------------------------
  check_ssh_output "$_m08d_e02_nom : Rocky Linux 10" "$_m08d_e02_nom" '^rocky 10' \
    '. /etc/os-release; echo "$ID ${VERSION_ID%%.*}"'
  check_ssh_output "$_m08d_e02_nom : cephadm et ceph-common en $_M08D_VERSION" "$_m08d_e02_nom" '^2$' \
    "{ cephadm version; ceph --version; } 2>/dev/null | grep -c 'version ${_M08D_VERSION//./\\.} '"
  check_ssh "$_m08d_e02_nom : dépôt Ceph épinglé sur rpm-$_M08D_VERSION, paquets vérifiés (gpgcheck)" "$_m08d_e02_nom" \
    "grep -hE '^baseurl' /etc/yum.repos.d/*.repo | grep -q 'download.ceph.com/rpm-${_M08D_VERSION}/' && ! grep -hE '^baseurl' /etc/yum.repos.d/*.repo | grep -Eq 'download.ceph.com/rpm-(tentacle|20\.2\.[^3])' && ! grep -A6 'download.ceph.com' /etc/yum.repos.d/*.repo | grep -Eq '^gpgcheck *= *(0|false)'"
  check_ssh "$_m08d_e02_nom : podman et lvm2 installés" "$_m08d_e02_nom" 'command -v podman && command -v lvcreate'
  check_ssh "$_m08d_e02_nom : temps synchronisé (chrony)" "$_m08d_e02_nom" 'chronyc -n tracking | grep -q "Leap status *: Normal"'
  check_ssh "$_m08d_e02_nom : firewalld actif, SELinux en enforcing" "$_m08d_e02_nom" \
    'systemctl is-active --quiet firewalld && [ "$(getenforce)" = Enforcing ]'
  check_ssh "$_m08d_e02_nom : connexion SSH de root toujours refusée" "$_m08d_e02_nom" \
    'sudo -n sshd -T | grep -qx "permitrootlogin no"'
  check_ssh "$_m08d_e02_nom : compte cephadm avec sudo sans mot de passe" "$_m08d_e02_nom" \
    'getent passwd cephadm >/dev/null && sudo -n -l -U cephadm | grep -Eq "NOPASSWD: *ALL"'
  check_ssh "$_m08d_e02_nom : .ssh de cephadm lisible par sshd (contexte ssh_home_t)" "$_m08d_e02_nom" \
    'sudo -n stat -c %C /var/lib/cephadm/.ssh | grep -q ":ssh_home_t:"'
  check_ssh "$_m08d_e02_nom : racine MédiSphère de confiance, CA provisoire absente" "$_m08d_e02_nom" \
    'test -s /etc/pki/ca-trust/source/anchors/medisphere-root-ca.crt && ! ls /etc/pki/ca-trust/source/anchors/ | grep -q provisoire && trust list | grep -q "MédiSphère Root CA"'
  check_ssh_output "$_m08d_e02_nom : ens18 et ens19 en MTU 9000" "$_m08d_e02_nom" '^9000 9000$' \
    'echo "$(cat /sys/class/net/ens18/mtu) $(cat /sys/class/net/ens19/mtu)"'
  check_ssh "$_m08d_e02_nom : adresses $_m08d_e02_pub/24 (ens18) et $_m08d_e02_clu/24 (ens19)" "$_m08d_e02_nom" \
    "ip -4 -o addr show ens18 | grep -q ' ${_m08d_e02_pub}/24 ' && ip -4 -o addr show ens19 | grep -q ' ${_m08d_e02_clu}/24 '"
  check_ssh "$_m08d_e02_nom : nom d'hôte court « $_m08d_e02_nom » (identité pour cephadm)" "$_m08d_e02_nom" \
    "[ \"\$(hostname -s)\" = $_m08d_e02_nom ]"
done

# --- 4. Trames jumbo de bout en bout (sans fragmentation) ------------------------------------------
for _m08d_e02_cible in 10.10.30.52 10.10.30.53 10.10.31.52 10.10.31.53; do
  check_ssh "ceph01 → $_m08d_e02_cible : 9000 octets sans fragmentation" ceph01 \
    "ping -c 2 -W 2 -M do -s 8972 $_m08d_e02_cible >/dev/null"
done
check_ssh "ceph01 : le réseau cluster n'a pas de passerelle (VLAN 31 non routé)" ceph01 \
  '! ip -4 route show dev ens19 | grep -q "^default"'

# --- 5. Le code ----------------------------------------------------------------------------------
check_cmd "plateforme/tofu-modules (main) : module vm-noeud" _m08d_fichier_main plateforme/tofu-modules vm-noeud/main.tf
check_cmd "plateforme/infra (main) : environnement envs/ceph" _m08d_fichier_main plateforme/infra envs/ceph/ceph.tf
check_cmd "plateforme/ansible (main) : rôle ceph_noeud" _m08d_fichier_main plateforme/ansible roles/ceph_noeud/tasks/main.yml
check_cmd "plateforme/ansible (main) : scénario Molecule ceph_noeud" _m08d_fichier_main plateforme/ansible molecule/ceph_noeud/molecule.yml
check_cmd "plateforme/ansible (main) : source d'inventaire de l'environnement Ceph" \
  _m08d_fichier_main plateforme/ansible inventories/lab/netbox-ceph.yml
check_output "plateforme/ansible (main) : collection medisphere.socle en 1.2 ou plus (ca_lab pour Rocky)" \
  '^version: 1\.([2-9]|[1-9][0-9])\.' \
  _m08d_contenu_main plateforme/ansible collections/ansible_collections/medisphere/socle/galaxy.yml
