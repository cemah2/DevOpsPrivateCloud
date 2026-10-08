# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les expressions entre apostrophes sont évaluées par bash -c ou sur l'hôte distant
#
# check-E03.sh — M07-E03 : Monter la maquette réseau par le code
# À lancer depuis adm01. Lecture seule : SDN, ACL et configuration des VMs lus en root sur pve01
# (pvesh get, pveum acl list, qm config), questions DNS, API NetBox et GitLab en lecture, état des
# VMs en SSH, copie de travail ~/src/infra.

# shellcheck source=_m07-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-decouverte.sh"

title "M07-E03 — Monter la maquette réseau par le code"
require_cmd jq curl dig

_m07d_e03_pve="${WB_PVE_HOST:-pve01}"

# --- 1. Les VNets de fabric et les droits du jeton -------------------------------------------
_m07d_e03_vnets="$(remote "$_m07d_e03_pve" "pvesh get /cluster/sdn/vnets --output-format json" 2>/dev/null || true)"
_m07d_e03_vnets_ok() {
  local i
  for i in 1 2 3 4 5 6 7 8; do
    jq -e --arg v "vfab$i" --argjson t "$((900 + i))" \
      'map(select(.vnet == $v and .zone == "lab" and (.tag | tonumber) == $t)) | length == 1' <<<"$1" >/dev/null || return 1
  done
}
check_cmd "SDN : vfab1 à vfab8 dans la zone lab, VLAN 901 à 908" _m07d_e03_vnets_ok "$_m07d_e03_vnets"
check_cmd "SDN : aucun changement en attente sur les VNets de fabric (configuration appliquée)" \
  bash -c 'remote_out="$1"; ! jq -e "map(select((.vnet | startswith(\"vfab\")) and .state != null)) | length > 0" <<<"$remote_out" >/dev/null' \
  _ "$(remote "$_m07d_e03_pve" "pvesh get /cluster/sdn/vnets --pending 1 --output-format json" 2>/dev/null || echo '[]')"

_m07d_e03_acl="$(remote "$_m07d_e03_pve" "pveum acl list --output-format json" 2>/dev/null || true)"
_m07d_e03_acl_ok() {
  local i type ugid
  for i in 1 2 3 4 5 6 7 8; do
    for type in "token:wb-tofu@pve!tofu" "user:wb-tofu@pve"; do
      ugid="${type#*:}"
      jq -e --arg p "/sdn/zones/lab/vfab$i" --arg t "${type%%:*}" --arg u "$ugid" \
        'map(select(.path == $p and .type == $t and .ugid == $u and .roleid == "PVESDNUser")) | length == 1' \
        <<<"$1" >/dev/null || return 1
    done
  done
}
check_cmd "ACL : PVESDNUser sur chaque vfabN pour le jeton wb-tofu@pve!tofu ET son utilisateur" \
  _m07d_e03_acl_ok "$_m07d_e03_acl"
check_cmd "ACL : le jeton wb-tofu n'a aucun rôle d'administration du SDN (SDN.Allocate)" \
  bash -c '! jq -e "map(select((.ugid | startswith(\"wb-tofu@pve\")) and (.roleid == \"PVESDNAdmin\" or .roleid == \"Administrator\"))) | length > 0" <<<"$1" >/dev/null' \
  _ "$_m07d_e03_acl"
check_cmd "plateforme/infra (main) : outils/m07-vnets.sh" _m07d_projet_fichier plateforme/infra outils/m07-vnets.sh

# --- 2. Les VMs : configuration Proxmox ---------------------------------------------------------
_m07d_e03_vm_ok() {
  local conf="$1" nom="$2" cartes="$3" i=1 v
  grep -q "^name: $nom$" <<<"$conf" || return 1
  _m07d_carte "$conf" 0 vsandbox || return 1
  for v in ${cartes//,/ }; do
    _m07d_carte "$conf" "$i" "$v" || return 1
    i=$((i + 1))
  done
  # Pas de carte en trop.
  ! grep -q "^net$i: " <<<"$conf"
}
_m07d_e03_meta_ok() {
  _m07d_etiquettes "$1" env-m07 "$2" && _m07d_dans_pool "$3" && ! grep -q "^onboot: 1$" <<<"$1"
}
# nom:VMID:étiquette de fonction:VNets des cartes net1… (séparés par des virgules)
for _m07d_e03_v in "net01:2070:m07-labo:" "spine01:2071:m07-spine:vfab1,vfab2" "spine02:2072:m07-spine:vfab3,vfab4" \
  "leaf01:2073:m07-leaf:vfab1,vfab3,vfab5,vfab7" "leaf02:2074:m07-leaf:vfab2,vfab4,vfab6,vfab7" \
  "srv01:2075:m07-web:vfab5" "srv02:2076:m07-web:vfab6" "lyo-gw01:2077:m07-lyo:vfab8" "lyo-pc01:2078:m07-lyo:vfab8"; do
  IFS=: read -r _m07d_e03_nom _m07d_e03_id _m07d_e03_fn _m07d_e03_cartes <<<"$_m07d_e03_v"
  _m07d_e03_conf="$(_m07d_qm "$_m07d_e03_id")"
  check_cmd "VM $_m07d_e03_id $_m07d_e03_nom : nom, eth0 sur vsandbox, cartes de fabric (${_m07d_e03_cartes:-aucune}) dans l'ordre" \
    _m07d_e03_vm_ok "$_m07d_e03_conf" "$_m07d_e03_nom" "$_m07d_e03_cartes"
  check_cmd "VM $_m07d_e03_id : étiquettes env-m07 et $_m07d_e03_fn, pool lab, pas de démarrage automatique" \
    _m07d_e03_meta_ok "$_m07d_e03_conf" "$_m07d_e03_fn" "$_m07d_e03_id"
done

check_cmd "Copie de travail ~/src/infra : envs/m07-maquette déclare les VMID 2070 à 2078" \
  bash -c 'for i in 2070 2071 2072 2073 2074 2075 2076 2077 2078; do grep -rEq "(vm_?id)[[:space:]]*=[[:space:]]*$i([^0-9]|$)" "$1" --include="*.tf" || exit 1; done' \
  _ "$_M07D_INFRA/envs/m07-maquette"
check_cmd "plateforme/infra (main) : envs/m07-maquette publié" _m07d_projet_dossier plateforme/infra envs/m07-maquette

# --- 3. Noms et réservations --------------------------------------------------------------------
for _m07d_e03_v in leaf01:10.10.99.251 srv01:10.10.99.252 srv02:10.10.99.253 lyo-gw01:10.10.99.250 web-demo:10.10.99.240; do
  _m07d_e03_n="${_m07d_e03_v%%:*}.par1.medisphere.internal"
  _m07d_e03_ip="${_m07d_e03_v##*:}"
  check_dns "DNS : $_m07d_e03_n → $_m07d_e03_ip" "$_m07d_e03_n" A "^${_m07d_e03_ip//./\\.}$" "$_M07D_DNS"
  check_dns "DNS : $_m07d_e03_ip → $_m07d_e03_n" "$(awk -F. '{print $4"."$3"."$2"."$1".in-addr.arpa"}' <<<"$_m07d_e03_ip")" PTR \
    "^${_m07d_e03_n//./\\.}\.$" "$_M07D_DNS"
done
for _m07d_e03_n in net01 spine01 spine02 leaf02 lyo-pc01; do
  check_dns "DNS dynamique : $_m07d_e03_n.par1.medisphere.internal → une adresse du VLAN 99" \
    "$_m07d_e03_n.par1.medisphere.internal" A '^10\.10\.99\.' "$_M07D_DNS"
done
_m07d_e03_nb() {
  netbox_api "ipam/ip-addresses/?address=$1" 2>/dev/null \
    | jq -e --arg r "$2" '.count == 1 and .results[0].status.value == "reserved"
        and ($r == "" or (.results[0].role.value // "") == $r)' >/dev/null
}
for _m07d_e03_ip in 10.10.99.250 10.10.99.251 10.10.99.252 10.10.99.253; do
  check_cmd "NetBox : $_m07d_e03_ip réservée (statut Reserved)" _m07d_e03_nb "$_m07d_e03_ip" ""
done
check_cmd "NetBox : VIP 10.10.99.240 réservée avec le rôle VRRP" _m07d_e03_nb 10.10.99.240 vrrp

# --- 4. Accès et configuration ------------------------------------------------------------------
for _m07d_e03_n in $_M07D_VMS; do
  check_ssh "SSH : adm01 joint $_m07d_e03_n par son nom ; iperf3, traceroute, ethtool installés" "$_m07d_e03_n" \
    'command -v iperf3 && command -v traceroute && command -v ethtool'
done

# --- 5. La fabric au niveau 3 : chaque lien /31 (et le LAN de LYO1) fonctionne ----------------
for _m07d_e03_l in spine01:10.10.250.1 spine01:10.10.250.3 spine02:10.10.250.5 spine02:10.10.250.7 \
  leaf01:10.10.250.9 leaf01:10.10.250.13 leaf02:10.10.250.11 lyo-gw01:10.30.10.10; do
  check_cmd "Lien : ${_m07d_e03_l%%:*} joint ${_m07d_e03_l##*:}" _m07d_ping "${_m07d_e03_l%%:*}" "${_m07d_e03_l##*:}"
done
