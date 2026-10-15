# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E05.sh — M16-E05 : raccorder les travailleurs au réseau de stockage
# À lancer depuis adm01. Lecture seule : qm config sur pve01, état réseau des nœuds en SSH, objets
# Kubernetes (wb-checks), API NetBox et GitLab en GET.

# shellcheck source=_m16-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-decouverte.sh"

title "M16-E05 — Raccorder les travailleurs au réseau de stockage"
require_cmd jq kubectl curl

_m16d_e05_noeuds="$(_m16d_kj get nodes)"

# --- 1. Les cartes Proxmox ------------------------------------------------------------------------------
# Travailleurs : VMID 2144-2146, suffixe 61-63 (règle de envs/k8s/noeuds.tf).
for _m16d_e05_i in 1 2 3; do
  _m16d_e05_vmid=$((2143 + _m16d_e05_i))
  _m16d_e05_suffixe=$((60 + _m16d_e05_i))
  _m16d_e05_conf="$(_m16d_qm "$_m16d_e05_vmid")"
  check_cmd "VM $_m16d_e05_vmid (k8s-w0$_m16d_e05_i) : net1 sur vstopub, MTU 9000, MAC BC:24:11:30:00:$_m16d_e05_suffixe" \
    bash -c 'grep -Eiq "^net1: virtio=$2,.*bridge=vstopub" <<<"$1" && grep -Eq "^net1: .*mtu=9000" <<<"$1"' \
    _ "$_m16d_e05_conf" "BC:24:11:30:00:$_m16d_e05_suffixe"
done
for _m16d_e05_vmid in 2141 2142 2143; do
  check_cmd "VM $_m16d_e05_vmid (contrôle) : aucune carte sur vstopub" \
    bash -c '[[ -n "$1" ]] && ! grep -Eq "^net[0-9]+: .*bridge=vstopub" <<<"$1"' _ "$(_m16d_qm "$_m16d_e05_vmid")"
done

# --- 2. Les invités -------------------------------------------------------------------------------------
_m16d_e05_i=0
for _m16d_e05_n in $_M16D_TRAVAILLEURS; do
  _m16d_e05_i=$((_m16d_e05_i + 1))
  _m16d_e05_ip="10.10.30.$((80 + _m16d_e05_i))"
  check_ssh_output "$_m16d_e05_n : eth1 porte $_m16d_e05_ip/24 en MTU 9000" "$_m16d_e05_n" \
    "^ok$" "ip -o -4 addr show dev eth1 | grep -q ' $_m16d_e05_ip/24 ' && [ \"\$(cat /sys/class/net/eth1/mtu)\" = 9000 ] && echo ok"
  check_ssh "$_m16d_e05_n : une seule route par défaut, et pas par eth1" "$_m16d_e05_n" \
    '[ "$(ip -4 route show default | wc -l)" = 1 ] && ! ip -4 route show default | grep -q eth1'
  check_ssh "$_m16d_e05_n : 9000 octets sans fragmentation vers les trois moniteurs" "$_m16d_e05_n" \
    "for m in $_M16D_MONS; do ping -M do -s 8972 -c 1 -W 2 -I eth1 \$m >/dev/null || exit 1; done"
  check_ssh "$_m16d_e05_n : protection cloud-init (réseau figé, clés d'hôte conservées) et netplan de eth1" "$_m16d_e05_n" \
    'f=/etc/cloud/cloud.cfg.d/99-medisphere-k8s.cfg; grep -Eq "^network: *\{ *config: *disabled *\}" $f \
     && grep -Eq "^ssh_deletekeys: *false" $f && sudo -n grep -q "eth1" /etc/netplan/60-stockage.yaml'
  check_ssh "$_m16d_e05_n : modules rbd et ceph chargés" "$_m16d_e05_n" \
    'grep -q "^rbd " /proc/modules && grep -q "^ceph " /proc/modules'
  check_cmd "$_m16d_e05_n : adresse interne Kubernetes restée sur le VLAN 40 (10.10.40.$((60 + _m16d_e05_i)))" \
    _m16d_json "$_m16d_e05_noeuds" '.items[] | select(.metadata.name == $n)
      | [.status.addresses[] | select(.type == "InternalIP") | .address] == [$ip]' \
    --arg n "$_m16d_e05_n" --arg ip "10.10.40.$((60 + _m16d_e05_i))"
done

# --- 3. L'étiquette et l'état des nœuds -------------------------------------------------------------------
check_cmd "étiquette $_M16D_ETIQUETTE=oui sur les travailleurs, et seulement eux" \
  bash -c 'diff <(jq -r --arg k "$2" ".items[] | select(.metadata.labels[\$k] == \"oui\") | .metadata.name" <<<"$1" | sort) \
                 <(printf "%s\n" $3 | sort) >/dev/null' _ "$_m16d_e05_noeuds" "$_M16D_ETIQUETTE" "$_M16D_TRAVAILLEURS"
check_cmd "les travailleurs sont Ready et planifiables" _m16d_json "$_m16d_e05_noeuds" '
  [.items[] | select(.metadata.name as $m | $t | index($m))
   | select((.spec.unschedulable // false) == false
            and any(.status.conditions[]; .type == "Ready" and .status == "True"))] | length == ($t | length)' \
  --argjson t "$(printf '%s\n' "$_M16D_TRAVAILLEURS" | tr ' ' '\n' | sed '/^$/d' | jq -R . | jq -s .)"

# --- 4. IPAM, code, documentation ------------------------------------------------------------------------
for _m16d_e05_ip in 10.10.30.81 10.10.30.82 10.10.30.83; do
  check_cmd "NetBox : $_m16d_e05_ip/24 enregistrée et affectée à une interface" _m16d_netbox_ip "$_m16d_e05_ip"
done
check_cmd "plateforme/ansible (main) : rôle k8s_reseau_stockage" \
  _m16d_fichier_main plateforme/ansible roles/k8s_reseau_stockage/tasks/main.yml
check_cmd "plateforme/ansible (main) : playbook k8s-reseau-stockage.yml" \
  _m16d_fichier_main plateforme/ansible playbooks/k8s-reseau-stockage.yml
check_cmd "plateforme/infra (main) : envs/k8s déclare les cartes vstopub (bc:24:11:30:00)" \
  _m16d_recherche_main plateforme/infra "bc:24:11:30:00"
check_cmd "plateforme/medisphere (main) : la matrice des flux cite 10.10.30.81-83" \
  bash -c 'grep -Eq "10\.10\.30\.8[1-3]" <<<"$1"' _ "$(_m16d_contenu_main plateforme/medisphere docs/socle/matrice-flux.md)"
