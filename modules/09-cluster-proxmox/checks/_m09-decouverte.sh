# shellcheck shell=bash
# shellcheck disable=SC2016  # commandes entre apostrophes : évaluées par bash -c ou sur l'hôte distant
# _m09-decouverte.sh — fonctions partagées par les checks M09-E02 à M09-E08 (lecture seule).
# Sourcé par les check-EXX.sh concernés (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m09d_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès utilisés (tous en lecture) :
#   - pve01 en root (WB_PVE_HOST) : configuration des VMs 2091-2093, stockages, ACL ;
#   - les nœuds en root par leurs alias SSH hv01, hv02, hv03 (~/.ssh/config de adm01, M09-E03) :
#     pvecm, corosync-cfgtool, corosync-cmapctl, pvesh get, zpool, ip ;
#   - pbs01 en root (WB_PBS_HOST) : état de corosync-qnetd et de son pare-feu (E05, E08) ;
#   - les copies de travail (WB_SRC), l'API GitLab (jeton des checks), NetBox (jeton des checks).

_M09D_INFRA="${WB_SRC:-$HOME/src}/infra"
_M09D_ANSIBLE="${WB_SRC:-$HOME/src}/ansible"
_M09D_DNS="10.10.20.10"
_M09D_PVE="${WB_PVE_HOST:-pve01}"
_M09D_PBS="${WB_PBS_HOST:-pbs01}"

# _m09d_qm VMID — configuration Proxmox de la VM sur pve01 (vide si absente).
_m09d_qm() {
  remote "$_M09D_PVE" "qm config $1" 2>/dev/null || true
}

# _m09d_qm_a CONFIG CLE REGEX — la ligne « CLE: valeur » de la configuration correspond à la regex.
_m09d_qm_a() {
  grep -Eq -- "^$2: $3" <<<"$1"
}

# _m09d_etiquettes CONFIG ETIQ… — la VM porte toutes les étiquettes données.
_m09d_etiquettes() {
  local conf="$1" e tags
  shift
  tags="$(sed -n 's/^tags: //p' <<<"$conf")"
  for e in "$@"; do
    grep -Eq "(^|;)$e(;|$)" <<<"$tags" || return 1
  done
}

# _m09d_dans_pool VMID — la VM est membre du pool lab.
_m09d_dans_pool() {
  remote "$_M09D_PVE" "pvesh get /pools/lab --output-format json" 2>/dev/null \
    | jq -e --argjson id "$1" '(.members // .[0].members // []) | map(select(.vmid == $id)) | length == 1' >/dev/null
}

# _m09d_mac N K — adresse MAC attendue de la carte K du nœud N (02:4d:53:09:NN:0K, majuscules
# comme les écrit Proxmox).
_m09d_mac() {
  printf '02:4D:53:09:%02X:%02X' "$1" "$2"
}

# _m09d_declaree_iac VMID — le VMID figure dans les données de l'état « hv » (copie de travail).
_m09d_declaree_iac() {
  jq -e --argjson id "$1" '[.noeuds[] | select(.vmid == $id)] | length == 1' \
    "$_M09D_INFRA/envs/hv/noeuds.auto.tfvars.json" >/dev/null 2>&1
}

# _m09d_fichier_main PROJET CHEMIN — le fichier existe sur la branche main du projet GitLab
# (PROJET : « plateforme/ansible », « plateforme/infra »…).
_m09d_fichier_main() {
  local p c
  p="$(jq -rn --arg v "$1" '$v | @uri')"
  c="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "projects/$p/repository/files/$c?ref=main" >/dev/null 2>&1
}

# _m09d_hv NŒUD COMMANDE — exécute une commande en root sur un nœud (alias SSH) ; sortie vide
# si le nœud ne répond pas.
_m09d_hv() {
  remote "$1" "$2" 2>/dev/null || true
}

# _m09d_premier_noeud — premier nœud joignable parmi hv01..hv03 (vide si aucun).
_m09d_premier_noeud() {
  local n
  for n in hv01 hv02 hv03; do
    remote "$n" true >/dev/null 2>&1 && { echo "$n"; return 0; }
  done
  return 0
}

# _m09d_anneaux NŒUD_INTERROGÉ NOM IP_LIEN0 IP_LIEN1 — dans la configuration Corosync en
# service (corosync-cmapctl), le nœud NOM a ring0_addr = IP_LIEN0 et ring1_addr = IP_LIEN1.
_m09d_anneaux() {
  local cmap idx
  cmap="$(_m09d_hv "$1" 'corosync-cmapctl nodelist.node')"
  idx="$(sed -nE "s/^nodelist\.node\.([0-9]+)\.name \(str\) = $2\$/\1/p" <<<"$cmap" | head -n 1)"
  [[ -n "$idx" ]] || return 1
  grep -qx "nodelist.node.$idx.ring0_addr (str) = $3" <<<"$cmap" \
    && grep -qx "nodelist.node.$idx.ring1_addr (str) = $4" <<<"$cmap"
}

# _m09d_ressources NŒUD — liste JSON des VMs du cluster (pvesh /cluster/resources).
_m09d_ressources() {
  _m09d_hv "$1" 'pvesh get /cluster/resources --type vm --output-format json'
}

# _m09d_config_invite NŒUD_INTERROGÉ VMID — configuration JSON d'un invité imbriqué, lue sur le
# nœud qui le porte (trouvé par /cluster/resources).
_m09d_config_invite() {
  local hote="$1" vmid="$2" porteur
  porteur="$(_m09d_ressources "$hote" | jq -r --argjson id "$vmid" '.[] | select(.vmid == $id) | .node' 2>/dev/null | head -n 1)"
  [[ -n "$porteur" ]] || return 0
  _m09d_hv "$hote" "pvesh get /nodes/$porteur/qemu/$vmid/config --output-format json"
}

# _m09d_controler_vm_noeud NOM NUMERO — contrôles de la VM d'un nœud (configuration sur pve01).
# Émet ses propres lignes OK/KO (check_cmd).
_m09d_controler_vm_noeud() {
  local nom="$1" num="$2" vmid conf k
  vmid=$((2090 + num))
  conf="$(_m09d_qm "$vmid")"
  check_cmd "VM $vmid nommée $nom" _m09d_qm_a "$conf" name "$nom\$"
  check_cmd "$nom : étiquettes env-m09 et hv-par1, pool lab" _m09d_etiquettes_et_pool "$conf" "$vmid"
  check_cmd "$nom : déclarée dans l'état « hv » de plateforme/infra (VMID $vmid)" _m09d_declaree_iac "$vmid"
  check_cmd "$nom : CPU « host », 4 cœurs, 12 Go sans ballon" \
    bash -c 'grep -Eq "^cpu: (cputype=)?host(,|$)" <<<"$1" && grep -q "^cores: 4$" <<<"$1" \
      && grep -q "^memory: 12288$" <<<"$1" && grep -q "^balloon: 0$" <<<"$1"' _ "$conf"
  check_cmd "$nom : disque système 32 Go sur local-nvme (série $nom-systeme)" \
    _m09d_qm_a "$conf" scsi0 "local-nvme:.*serial=$nom-systeme.*size=32G"
  check_cmd "$nom : disques OSD 2 × 48 Go et ZFS 32 Go sur ssd-lab" \
    bash -c 'grep -Eq "^scsi1: ssd-lab:.*serial=$2-osd1.*size=48G" <<<"$1" && grep -Eq "^scsi2: ssd-lab:.*serial=$2-osd2.*size=48G" <<<"$1" \
      && grep -Eq "^scsi3: ssd-lab:.*serial=$2-zfs.*size=32G" <<<"$1"' _ "$conf" "$nom"
  local ponts=(vmgmt vcoro vstopub vstoclu vmbr1)
  for k in 0 1 2 3 4; do
    check_cmd "$nom : net$k sur ${ponts[k]}, MAC $(_m09d_mac "$num" "$k")" \
      _m09d_qm_a "$conf" "net$k" "virtio=$(_m09d_mac "$num" "$k"),bridge=${ponts[k]}(,|$)"
  done
  check_cmd "$nom : MTU 9000 sur les cartes Ceph (net2, net3), pas sur MGMT ni Corosync" \
    bash -c 'grep -Eq "^net2: .*mtu=9000" <<<"$1" && grep -Eq "^net3: .*mtu=9000" <<<"$1" \
      && ! grep -Eq "^net[01]: .*mtu=" <<<"$1"' _ "$conf"
  check_cmd "$nom : net4 en trunk limité au VLAN 99, sans étiquette ni pare-feu" \
    bash -c 'l="$(grep "^net4: " <<<"$1")"; grep -Eq "trunks=99(,|$)" <<<"$l" \
      && ! grep -Eq "(tag=|firewall=1)" <<<"$l"' _ "$conf"
  check_cmd "$nom : démarre sur le disque, ISO préparée en secours (ide2)" \
    bash -c 'grep -Eq "^boot: order=scsi0;ide2" <<<"$1" && grep -Eq "^ide2: hdd-bulk:iso/pve92-auto-$2\.iso" <<<"$1"' _ "$conf" "$nom"
}

# _m09d_netbox_vm NOM IP — NetBox décrit la VM NOM avec l'IP primaire IP (jeton des checks).
_m09d_netbox_vm() {
  netbox_api "virtualization/virtual-machines/?name=$1" 2>/dev/null \
    | jq -e --arg ip "$2/" '.count == 1 and ((.results[0].primary_ip4.address // "") | startswith($ip))' >/dev/null
}

# _m09d_etiquettes_et_pool CONFIG VMID — étiquettes env-m09 + hv-par1 et pool lab.
_m09d_etiquettes_et_pool() {
  _m09d_etiquettes "$1" env-m09 hv-par1 && _m09d_dans_pool "$2"
}

# _m09d_controler_noeud_configure NOM NUMERO — contrôles du système du nœud (en root, par SSH).
_m09d_controler_noeud_configure() {
  local nom="$1" num="$2" ip_mgmt ip_coro ip_pub ip_clu
  ip_mgmt="10.10.10.$((50 + num))"
  ip_coro="10.10.32.$((50 + num))"
  ip_pub="10.10.30.$((70 + num))"
  ip_clu="10.10.31.$((70 + num))"
  check_dns "DNS : $nom.par1.medisphere.internal → $ip_mgmt" "$nom.par1.medisphere.internal" A "^${ip_mgmt//./\\.}\$" "$_M09D_DNS"
  check_dns "DNS : $ip_mgmt → $nom.par1.medisphere.internal" "$((50 + num)).10.10.10.in-addr.arpa" PTR "^$nom\\.par1\\.medisphere\\.internal\\.\$" "$_M09D_DNS"
  check_ssh "$nom : SSH root par clé depuis adm01, hôte reconnu (certificat d'hôte ou clé vérifiée)" "$nom" true
  check_ssh_output "$nom : Proxmox VE 9.2" "$nom" '^pve-manager/9\.2' 'pveversion'
  check_ssh "$nom : certificat SSH d'hôte signé par la CA, principal $nom.par1.medisphere.internal" "$nom" \
    "ssh-keygen -L -f /etc/ssh/ssh_host_ed25519_key-cert.pub | grep -qx '[[:space:]]*$nom.par1.medisphere.internal'"
  check_ssh_output "$nom : authentification SSH par mot de passe refusée" "$nom" '^passwordauthentication no$' \
    'sshd -T 2>/dev/null | grep -i "^passwordauthentication"'
  check_ssh "$nom : virtualisation imbriquée disponible (/dev/kvm)" "$nom" 'test -c /dev/kvm'
  check_ssh "$nom : cartes nic0..nic4 épinglées sur leurs MAC" "$nom" \
    "for k in 0 1 2 3 4; do m=\$(cat /sys/class/net/nic\$k/address) || exit 1; [ \"\$m\" = \"\$(printf '02:4d:53:09:%02x:%02x' $num \$k)\" ] || exit 1; done"
  check_ssh "$nom : MGMT $ip_mgmt sur vmbr0, Corosync $ip_coro sur nic1" "$nom" \
    "ip -4 -br a show dev vmbr0 | grep -q ' $ip_mgmt/24' && ip -4 -br a show dev nic1 | grep -q ' $ip_coro/24'"
  check_ssh "$nom : Ceph $ip_pub (nic2) et $ip_clu (nic3) en MTU 9000" "$nom" \
    "ip -4 -br a show dev nic2 | grep -q ' $ip_pub/24' && ip -4 -br a show dev nic3 | grep -q ' $ip_clu/24' \
     && [ \$(cat /sys/class/net/nic2/mtu) = 9000 ] && [ \$(cat /sys/class/net/nic3/mtu) = 9000 ] && [ \$(cat /sys/class/net/vmbr0/mtu) = 1500 ]"
  check_ssh "$nom : trames de 9000 octets sans fragmentation jusqu'à la passerelle du VLAN 30" "$nom" \
    'ping -c 1 -W 2 -M do -s 8972 10.10.30.1 >/dev/null'
  check_ssh "$nom : vmbr1 sur nic4, VLAN-aware, sans adresse" "$nom" \
    '[ "$(cat /sys/class/net/vmbr1/bridge/vlan_filtering)" = 1 ] && [ -e /sys/class/net/vmbr1/brif/nic4 ] && [ -z "$(ip -4 -br a show dev vmbr1 | awk "{print \$3}")" ]'
  check_ssh "$nom : aucun dépôt à abonnement actif, dépôt pve-no-subscription déclaré" "$nom" \
    'for f in $(grep -rls enterprise.proxmox.com /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null); do grep -qiE "^Enabled: *(no|false)" "$f" || exit 1; done; grep -rqs pve-no-subscription /etc/apt/sources.list.d/'
  check_ssh "$nom : heure synchronisée sur la passerelle de MGMT (10.10.10.1)" "$nom" \
    'chronyc -n sources | grep -Eq "^\^\* 10\.10\.10\.1 "'
  check_ssh "$nom : ARC de ZFS plafonné à 1 Gio au plus (modprobe.d)" "$nom" \
    'v=$(grep -hoE "zfs_arc_max=[0-9]+" /etc/modprobe.d/*.conf | tail -n 1 | cut -d= -f2); [ -n "$v" ] && [ "$v" -gt 0 ] && [ "$v" -le 1073741824 ]'
  check_port "$nom : interface web (8006) joignable depuis adm01" "$ip_mgmt" 8006
  check_cmd "NetBox : VM $nom, IP primaire $ip_mgmt" _m09d_netbox_vm "$nom" "$ip_mgmt"
}
