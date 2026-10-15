# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E02.sh — M14-E02 : Préparer les nœuds
# À lancer depuis adm01. Lecture seule : qm config sur pve01, DNS, NetBox (jeton des checks),
# état des nœuds en SSH (sudo -n pour containerd et crictl), API GitLab en GET.

# shellcheck source=_m14-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-decouverte.sh"

title "M14-E02 — Préparer les nœuds"
require_cmd jq dig curl

# _m14d_e02_netbox NOM IP/MASQUE — la VM existe dans NetBox, active, avec cette IP primaire.
_m14d_e02_netbox() {
  netbox_api "virtualization/virtual-machines/?name=$1" 2>/dev/null \
    | jq -e --arg ip "$2" '.count == 1 and .results[0].status.value == "active" and .results[0].primary_ip4.address == $ip' >/dev/null
}

for _m14d_e02_nom in "${_M14D_CP[@]}" "${_M14D_W[@]}"; do
  read -r _m14d_e02_vmid _m14d_e02_ip _m14d_e02_role <<<"${_M14D_PLAN[$_m14d_e02_nom]:-0 0 x}"
  _m14d_e02_suffixe="${_m14d_e02_ip##*.}"
  _m14d_e02_conf="$(_m14d_qm "$_m14d_e02_vmid")"
  if [[ "$_m14d_e02_role" == cp ]]; then
    _m14d_e02_etiq=role-k8s-cp; _m14d_e02_cpu=2; _m14d_e02_mem=4096; _m14d_e02_disque=40G
  else
    _m14d_e02_etiq=role-k8s-worker; _m14d_e02_cpu=4; _m14d_e02_mem=8192; _m14d_e02_disque=60G
  fi

  # --- 1. La VM (Proxmox) ----------------------------------------------------------------------
  check_cmd "VM $_m14d_e02_vmid nommée $_m14d_e02_nom" grep -qx "name: $_m14d_e02_nom" <<<"$_m14d_e02_conf"
  check_cmd "$_m14d_e02_nom : étiquettes env-k8s et $_m14d_e02_etiq" \
    _m14d_etiquettes "$_m14d_e02_conf" env-k8s "$_m14d_e02_etiq"
  check_cmd "$_m14d_e02_nom : membre du pool lab" _m14d_dans_pool "$_m14d_e02_vmid"
  check_cmd "$_m14d_e02_nom : créée par OpenTofu avec le module vm-noeud" grep -q 'vm-noeud' <<<"$_m14d_e02_conf"
  check_cmd "$_m14d_e02_nom : $_m14d_e02_cpu vCPU, $_m14d_e02_mem Mo, sans démarrage automatique" \
    bash -c 'grep -qx "cores: $2" <<<"$1" && grep -qx "memory: $3" <<<"$1" && ! grep -qx "onboot: 1" <<<"$1"' \
    _ "$_m14d_e02_conf" "$_m14d_e02_cpu" "$_m14d_e02_mem"
  check_cmd "$_m14d_e02_nom : une carte sur vk8s, MAC BC:24:11:40:00:$_m14d_e02_suffixe" \
    bash -c 'grep -Eiq "^net0: virtio=BC:24:11:40:00:$2,bridge=vk8s" <<<"$1" && ! grep -q "^net1:" <<<"$1"' \
    _ "$_m14d_e02_conf" "$_m14d_e02_suffixe"
  check_cmd "$_m14d_e02_nom : disque système de $_m14d_e02_disque sur $_M14D_NVME" \
    bash -c 'grep -Eq "^scsi0: $2:.*size=$3(,|$)" <<<"$1"' _ "$_m14d_e02_conf" "$_M14D_NVME" "$_m14d_e02_disque"

  # --- 2. Nom et NetBox --------------------------------------------------------------------------
  check_dns "DNS : $_m14d_e02_nom.par1.medisphere.internal → $_m14d_e02_ip" \
    "$_m14d_e02_nom.par1.medisphere.internal" A "^${_m14d_e02_ip//./\\.}$" "$_M14D_DNS"
  check_dns "DNS : $_m14d_e02_ip → $_m14d_e02_nom (PTR)" "$_m14d_e02_suffixe.40.10.10.in-addr.arpa" PTR \
    "^${_m14d_e02_nom}\.par1\.medisphere\.internal\.$" "$_M14D_DNS"
  check_cmd "NetBox : $_m14d_e02_nom active, IP primaire $_m14d_e02_ip/24" \
    _m14d_e02_netbox "$_m14d_e02_nom" "$_m14d_e02_ip/24"

  # --- 3. Le système -----------------------------------------------------------------------------
  check_ssh_output "$_m14d_e02_nom : Debian 13, nom d'hôte « $_m14d_e02_nom »" "$_m14d_e02_nom" \
    "^debian 13 ${_m14d_e02_nom}$" '. /etc/os-release; echo "$ID $VERSION_ID $(hostname -s)"'
  check_ssh_output "$_m14d_e02_nom : containerd.io 2.3.x du dépôt Docker installé" "$_m14d_e02_nom" \
    '^containerd\.io 2\.3\.[0-9]+-[^ ]+ ii $' \
    "dpkg-query -W -f='\${Package} \${Version} \${db:Status-Abbrev}\n' containerd.io 2>/dev/null"
  check_ssh_output "$_m14d_e02_nom : kubelet, kubeadm, kubectl en $_M14D_VERSION-1.1 et retenus (hold)" "$_m14d_e02_nom" \
    '^3$' "dpkg-query -W -f='\${Package} \${Version} \${db:Status-Abbrev}\n' kubelet kubeadm kubectl 2>/dev/null | grep -c ' ${_M14D_VERSION//./\\.}-1\.1 hi '"
  check_ssh "$_m14d_e02_nom : dépôt pkgs.k8s.io de la mineure $_M14D_MINEURE, signé" "$_m14d_e02_nom" \
    "grep -q '^URIs: https://pkgs.k8s.io/core:/stable:/v${_M14D_MINEURE}/deb/' /etc/apt/sources.list.d/kubernetes.sources && grep -q '^Signed-By: /etc/apt/keyrings/' /etc/apt/sources.list.d/kubernetes.sources"
  check_ssh "$_m14d_e02_nom : containerd.io épinglé sur la branche 2.3 (préférence APT)" "$_m14d_e02_nom" \
    'apt-cache policy containerd.io | grep -Eq "^ +(\*\*\* )?2\.3\.[0-9]+[^ ]* 1001$"'
  check_ssh "$_m14d_e02_nom : pas de swap actif ni déclaré" "$_m14d_e02_nom" \
    '[ -z "$(swapon --show --noheadings)" ] && ! grep -Eq "^[^#]\S*\s+\S+\s+swap\s" /etc/fstab'
  check_ssh "$_m14d_e02_nom : modules overlay et br_netfilter chargés et déclarés au démarrage" "$_m14d_e02_nom" \
    'lsmod | grep -q "^overlay " && lsmod | grep -q "^br_netfilter " && grep -qx overlay /etc/modules-load.d/*.conf && grep -qx br_netfilter /etc/modules-load.d/*.conf'
  check_ssh_output "$_m14d_e02_nom : routage IPv4 et passage du trafic ponté par netfilter" "$_m14d_e02_nom" \
    '^1 1$' 'echo "$(sysctl -n net.ipv4.ip_forward) $(sysctl -n net.bridge.bridge-nf-call-iptables)"'
  check_ssh "$_m14d_e02_nom : containerd actif, greffon CRI chargé, cgroups systemd" "$_m14d_e02_nom" \
    'systemctl is-active --quiet containerd && sudo -n containerd config dump | grep -q "SystemdCgroup = true" && ! sudo -n containerd config dump | grep -Eq "^disabled_plugins = \[.*cri"'
  check_ssh "$_m14d_e02_nom : image pause de containerd = celle de kubeadm $_M14D_VERSION ($_M14D_PAUSE)" "$_m14d_e02_nom" \
    "sudo -n containerd config dump | grep -q \"sandbox = '$_M14D_PAUSE'\" && kubeadm config images list --kubernetes-version v$_M14D_VERSION 2>/dev/null | grep -qx '$_M14D_PAUSE'"
  check_ssh "$_m14d_e02_nom : le runtime répond au CRI (crictl info : RuntimeReady)" "$_m14d_e02_nom" \
    'sudo -n crictl info 2>/dev/null | jq -e ".status.conditions[] | select(.type == \"RuntimeReady\") | .status == true" >/dev/null'
  check_ssh "$_m14d_e02_nom : kubelet activé au démarrage" "$_m14d_e02_nom" 'systemctl is-enabled --quiet kubelet'
  check_ssh "$_m14d_e02_nom : cgroup v2 (hiérarchie unifiée)" "$_m14d_e02_nom" 'test -f /sys/fs/cgroup/cgroup.controllers'
  check_ssh "$_m14d_e02_nom : racine MédiSphère de confiance" "$_m14d_e02_nom" \
    'test -s /usr/local/share/ca-certificates/medisphere-root-ca.crt && test -L /etc/ssl/certs/medisphere-root-ca.pem'
  check_ssh "$_m14d_e02_nom : connexion SSH de root toujours refusée" "$_m14d_e02_nom" \
    'sudo -n sshd -T | grep -qx "permitrootlogin no"'
done

# --- 4. Le code ----------------------------------------------------------------------------------
check_output "plateforme/infra (main) : environnement envs/k8s (module vm-noeud)" 'tofu-modules\.git//vm-noeud' \
  _m14d_contenu_main plateforme/infra envs/k8s/noeuds.tf
check_output "plateforme/infra (main) : état distant envs/k8s/terraform.tfstate" 'key *= *"envs/k8s/terraform\.tfstate"' \
  _m14d_contenu_main plateforme/infra envs/k8s/versions.tf
for _m14d_e02_f in roles/containerd/tasks/main.yml roles/containerd/templates/config.toml.j2 roles/k8s_noeud/tasks/main.yml \
  molecule/k8s_noeud/molecule.yml playbooks/k8s-noeuds.yml inventories/lab/netbox-k8s.yml \
  inventories/lab/group_vars/k8s_par1/kubernetes.yml; do
  check_cmd "plateforme/ansible (main) : $_m14d_e02_f" _m14d_fichier_main plateforme/ansible "$_m14d_e02_f"
done
check_output "plateforme/ansible (main) : version de Kubernetes fixée à $_M14D_VERSION dans l'inventaire" \
  "^k8s_version: *\"?${_M14D_VERSION//./\\.}\"?" \
  _m14d_contenu_main plateforme/ansible inventories/lab/group_vars/k8s_par1/kubernetes.yml
