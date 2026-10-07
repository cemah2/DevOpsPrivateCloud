# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes entre apostrophes : évalués par jq et bash -c
#
# check-E05.sh — M06-E05 : Modéliser MédiSphère dans NetBox
# À lancer depuis adm01. Lecture seule : API REST de NetBox en GET avec le jeton v2 des checks,
# copie de travail de plateforme/outils.

# shellcheck source=_m06-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-decouverte.sh"

title "M06-E05 — Modéliser MédiSphère dans NetBox"
require_cmd jq curl

# _m06d_e05 CHEMIN FILTRE_JQ — GET sur l'API puis filtre jq qui doit valoir true.
_m06d_e05() {
  netbox_api "$1" 2>/dev/null | jq -e "$2" >/dev/null 2>&1
}

# --- 1. Organisation -------------------------------------------------------------------------
check_cmd "Région « France »" _m06d_e05 "dcim/regions/?slug=france" '.count == 1'
check_cmd "Locataire (tenant) « MédiSphère »" _m06d_e05 "tenancy/tenants/?slug=medisphere" '.count == 1'
check_cmd "Sites PAR1 et PAR2, en France" _m06d_e05 "dcim/sites/?region=france" \
  '[.results[].slug] | (index("par1") != null) and (index("par2") != null)'
check_cmd "Au moins une baie par site" _m06d_e05 "dcim/racks/?limit=100" \
  '[.results[].site.slug] | (index("par1") != null) and (index("par2") != null)'

# --- 2. Physique et virtualisation ------------------------------------------------------------
check_cmd "Équipements pve01 (PAR1) et hp01 (PAR2), rangés dans une baie" _m06d_e05 "dcim/devices/?name=pve01&name=hp01" \
  '.count == 2 and all(.results[]; .rack != null) and ([.results[] | select(.name == "pve01") | .site.slug] == ["par1"])'
check_cmd "Type de cluster « Proxmox VE » et cluster pve01 rattaché au site PAR1" _m06d_e05 "virtualization/clusters/?name=pve01" \
  '.count == 1 and (.results[0].type.slug == "proxmox-ve") and (.results[0].scope_type == "dcim.site") and (.results[0].scope.slug == "par1")'
check_cmd "L'équipement pve01 est l'hôte du cluster pve01" _m06d_e05 "dcim/devices/?name=pve01" \
  '.results[0].cluster.name == "pve01"'
check_cmd "Champ personnalisé « vmid » (entier) sur les machines virtuelles" _m06d_e05 "extras/custom-fields/?name=vmid" \
  '.count == 1 and (.results[0].type.value == "integer") and (.results[0].object_types | index("virtualization.virtualmachine") != null)'

# --- 3. Adressage (PLAN.md §4.2) -----------------------------------------------------------------
check_cmd "Groupe de VLAN PAR1 : les 13 VLAN du site" _m06d_e05 "ipam/vlans/?group=par1&limit=100" \
  '[.results[].vid] | sort == [10,20,30,31,32,40,41,50,51,52,60,70,99]'
check_cmd "Préfixe 10.10.20.0/24 rattaché au VLAN 20 (INFRA) et au site PAR1" _m06d_e05 "ipam/prefixes/?prefix=10.10.20.0/24" \
  '.count == 1 and (.results[0].vlan.vid == 20) and (.results[0].scope.slug == "par1")'
check_cmd "Un préfixe /24 par VLAN de PAR1, chacun lié à son VLAN" _m06d_e05 "ipam/prefixes/?within=10.10.0.0/16&mask_length=24&limit=100" \
  '[.results[] | select(.vlan != null)] | length >= 13'
check_cmd "Agrégats 10.10.0.0/16 (PAR1) et 10.20.0.0/16 (PAR2) en conteneurs" _m06d_e05 "ipam/prefixes/?status=container&limit=100" \
  '[.results[].prefix] | (index("10.10.0.0/16") != null) and (index("10.20.0.0/16") != null)'
check_cmd "Rôles IPAM statique, nœuds, DHCP, VIP" _m06d_e05 "ipam/roles/?limit=100" '.count >= 4'
check_cmd "Plage DHCP du VLAN 99 : 10.10.99.100 à .199, rôle DHCP" _m06d_e05 "ipam/ip-ranges/?start_address=10.10.99.100" \
  '.count == 1 and (.results[0].end_address | startswith("10.10.99.199/")) and (.results[0].role != null)'
check_cmd "Plage des adresses statiques d'INFRA : 10.10.20.10 à .49" _m06d_e05 "ipam/ip-ranges/?start_address=10.10.20.10" \
  '.count == 1 and (.results[0].end_address | startswith("10.10.20.49/"))'

# --- 4. Les VMs du socle ------------------------------------------------------------------------------
_m06d_e05_vms="$(netbox_api "virtualization/virtual-machines/?cluster=pve01&limit=200" 2>/dev/null || true)"
for _m06d_e05_v in gw01:1000:10.10.10.1 adm01:1001:10.10.10.10 dns01:1002:10.10.20.10 ca01:1003:10.10.20.11 \
  git01:1004:10.10.20.12 nbx01:1005:10.10.20.13 s3-01:1006:10.10.20.14 runner01:1007:10.10.20.15; do
  IFS=: read -r _m06d_e05_n _m06d_e05_id _m06d_e05_ip <<<"$_m06d_e05_v"
  check_cmd "VM $_m06d_e05_n : vmid $_m06d_e05_id, IP primaire $_m06d_e05_ip, étiquette socle" \
    jq -e --arg n "$_m06d_e05_n" --argjson id "$_m06d_e05_id" --arg ip "$_m06d_e05_ip" \
    '[.results[] | select(.name == $n)] | length == 1 and (.[0].custom_fields.vmid == $id)
     and ((.[0].primary_ip4.address // "") | startswith($ip + "/"))
     and ([.[0].tags[].slug] | index("socle") != null)' <<<"$_m06d_e05_vms"
done
check_cmd "Chaque VM du socle porte son étiquette role-*" \
  jq -e '[.results[] | select([.tags[].slug] | index("socle") != null)] | length >= 8
         and all(.[]; [.tags[].slug] | any(startswith("role-")))' <<<"$_m06d_e05_vms"

# --- 5. Reproductible ------------------------------------------------------------------------------------
check_cmd "plateforme/outils : le script de modélisation et ses données sont versionnés" \
  bash -c 'git -C "$1" ls-files | grep -Ei "netbox" | grep -Eq "\.(py|ya?ml)$"' _ "${WB_SRC:-$HOME/src}/outils"
