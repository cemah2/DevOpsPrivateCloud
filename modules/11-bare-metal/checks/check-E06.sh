# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E06.sh — M11-E06 : Des installations décrites par NetBox
# À lancer depuis adm01. Lecture seule (NetBox en lecture, configuration chargée par Kea, fichiers
# servis par pxe01, API GitLab en lecture, agent QEMU).

# shellcheck source=_m11-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m11-operationnel.sh"

title "M11-E06 — Des installations décrites par NetBox"
require_cmd jq curl dig

_m11o_dns_name() { _m11o_nb_checks "ipam/ip-addresses/$1/" | jq -r .dns_name; }
_m11o_compte_ansible() { _m11o_nb_ansible "dcim/devices/?role=serveur-bm&brief=true" | jq -r .count; }
_m11o_nom_hote() { remote "$_M11O_PVE" "qm guest cmd $1 get-host-name" | jq -r '.["host-name"]'; }
_m11o_rendu_ignore() { _m11o_contenu_main "$_M11O_PROJET_PROV" .gitignore | grep -Eq '^/?rendu/?$'; }

_m11o_devs="$(_m11o_nb_checks 'dcim/devices/?role=serveur-bm&site=par1&limit=50' || true)"
check_output "NetBox : bm01 à bm04, rôle serveur-bm, site par1" '^bm01 bm02 bm03 bm04$' \
  jq -r '[.results[].name] | sort | join(" ")' <<<"$_m11o_devs"
_m11o_kea1="$(_m11o_kea dns01)"; _m11o_kea2="$(_m11o_kea dns02)"

while read -r _m11o_nom _m11o_vmid _m11o_mac; do
  _m11o_d="$(jq -c --arg n "$_m11o_nom" '.results[] | select(.name == $n)' <<<"$_m11o_devs" 2>/dev/null || true)"
  if [[ -z "$_m11o_d" ]]; then
    _ko "NetBox : $_m11o_nom absent"
    continue
  fi
  _m11o_num="${_m11o_nom#bm0}"
  _m11o_ip_att="10.10.60.10$_m11o_num"
  check_output "$_m11o_nom : plate-forme debian-13 ou rocky-10" '^(debian-13|rocky-10)$' jq -r '.platform.slug // empty' <<<"$_m11o_d"
  # MAC de eno1 dans NetBox = MAC de la VM dans Proxmox.
  _m11o_if="$(_m11o_nb_checks "dcim/interfaces/?device_id=$(jq -r .id <<<"$_m11o_d")&name=eno1" || true)"
  _m11o_mac_nb="$(jq -r '.results[0] | (.primary_mac_address.mac_address // .mac_address // "") | ascii_downcase' <<<"$_m11o_if" 2>/dev/null || true)"
  _m11o_mac_pve="$(remote "$_M11O_PVE" "qm config $_m11o_vmid" 2>/dev/null | sed -nE 's/^net0: [a-z0-9]+=([0-9A-Fa-f:]{17}),.*/\1/p' | tr 'A-F' 'a-f' || true)"
  check_output "$_m11o_nom : MAC primaire de eno1 ($_m11o_mac_nb) = MAC de la VM $_m11o_vmid" "^${_m11o_mac}\$" \
    bash -c '[ "$1" = "$2" ] && echo "$1"' _ "$_m11o_mac_nb" "$_m11o_mac_pve"
  check_output "$_m11o_nom : IP primaire $_m11o_ip_att/24" "^${_m11o_ip_att//./\\.}/24\$" jq -r '.primary_ip4.address // empty' <<<"$_m11o_d"
  _m11o_ipid="$(jq -r '.primary_ip4.id // empty' <<<"$_m11o_d")"
  check_output "$_m11o_nom : dns_name $_m11o_nom.par1.medisphere.internal" "^$_m11o_nom\\.par1\\.medisphere\\.internal\$" \
    _m11o_dns_name "$_m11o_ipid"
  # Réservation Kea (deux pairs) conforme à NetBox.
  for _m11o_k in "$_m11o_kea1" "$_m11o_kea2"; do
    check_cmd "$_m11o_nom : réservation Kea $_m11o_mac → $_m11o_ip_att ($( [[ "$_m11o_k" == "$_m11o_kea1" ]] && echo dns01 || echo dns02))" \
      jq -e --arg m "$_m11o_mac" --arg i "$_m11o_ip_att" '[.arguments.Dhcp4.subnet4[] | select(.id == 60) | .reservations[]?
              | select((.["hw-address"] | ascii_downcase) == $m and .["ip-address"] == $i)] | length == 1' <<<"$_m11o_k"
  done
  # Script iPXE par MAC, cohérent avec le statut NetBox.
  _m11o_statut="$(jq -r '.status.value' <<<"$_m11o_d")"
  _m11o_script="$(_m11o_http "ipxe/mac-${_m11o_mac//:/-}.ipxe")"
  if [[ "$_m11o_statut" == planned ]]; then
    check_output "$_m11o_nom (planned) : script iPXE servi, qui installe sous le bon nom" "(hostname=$_m11o_nom|kickstart/$_m11o_nom\\.ks|preseed/$_m11o_nom\\.cfg)" echo "$_m11o_script"
  else
    check_cmd "$_m11o_nom ($_m11o_statut) : script iPXE servi, qui démarre sur le disque (aucun noyau)" \
      bash -c 'head -n 1 <<<"$1" | grep -qx "#!ipxe" && ! grep -q "^kernel" <<<"$1" && grep -q "^exit" <<<"$1"' _ "$_m11o_script"
  fi
done <<<"$_M11O_BM"

# --- Le jeton de lecture de svc-automatisation ---------------------------------------------------------------
check_output "jeton de lecture de svc-automatisation : lit les équipements serveur-bm" '^[4-9]$|^[1-9][0-9]+$' \
  _m11o_compte_ansible
_m11o_jeton_lecture_seule() {
  local j cle
  j="$(_m11o_lire "$_M11O_CFG/netbox-ansible.env" NETBOX_TOKEN)"
  cle="$(sed -nE 's/^nbt_([A-Za-z0-9]+)\..*/\1/p' <<<"$j")"
  [[ -n "$cle" ]] && _m11o_nb_checks "users/tokens/?key=$cle" \
    | jq -e '.results | length == 1 and (.[0].write_enabled == false)' >/dev/null
}
check_cmd "jeton de lecture de svc-automatisation : toujours sans droit d'écriture" _m11o_jeton_lecture_seule

# --- Les serveurs installés par la chaîne ------------------------------------------------------------------
for _m11o_nom in bm01 bm02; do
  check_output "NetBox : $_m11o_nom est passé en service (active)" '^active$' \
    jq -r --arg n "$_m11o_nom" '.results[] | select(.name == $n) | .status.value' <<<"$_m11o_devs"
  check_dns "$_m11o_nom.par1.medisphere.internal se résout" "$_m11o_nom.par1.medisphere.internal" A '^10\.10\.60\.10[0-9]$' 10.10.20.10
done
while read -r _m11o_nom _m11o_vmid _m11o_mac; do
  [[ "$_m11o_nom" == bm01 || "$_m11o_nom" == bm02 ]] || continue
  if remote "$_M11O_PVE" "qm status $_m11o_vmid" 2>/dev/null | grep -q running; then
    check_output "$_m11o_nom : nom d'hôte décidé par NetBox (agent QEMU)" "^$_m11o_nom(\\.|\$)" \
      _m11o_nom_hote "$_m11o_vmid"
  else
    skip "$_m11o_nom : nom d'hôte" "VM $_m11o_vmid arrêtée : démarre-la (elle doit démarrer sur son disque)"
  fi
done <<<"$_M11O_BM"

# --- Le projet ----------------------------------------------------------------------------------------------
check_cmd "plateforme/provisioning : outils/netbox-provision.py sur main" _m11o_fichier_main "$_M11O_PROJET_PROV" outils/netbox-provision.py
check_output "plateforme/provisioning : le pipeline lance des tests (pytest) et le rendu" 'pytest' \
  _m11o_contenu_main "$_M11O_PROJET_PROV" .gitlab-ci.yml
check_output "plateforme/provisioning : dernier pipeline de main réussi" '^success$' _m11o_pipeline_main "$_M11O_PROJET_PROV"
check_cmd "plateforme/provisioning : les fichiers rendus ne sont pas versionnés (rendu/ ignoré)" _m11o_rendu_ignore
