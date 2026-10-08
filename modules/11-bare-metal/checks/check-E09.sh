# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E09.sh — M11-E09 : Installer MAAS
# À lancer depuis adm01, maas01 démarrée. Lecture seule : configuration Proxmox, état de maas01 en
# SSH, API de MAAS en lecture avec ta clé (maas-api.key).

# shellcheck source=_m11-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m11-operationnel.sh"

title "M11-E09 — Installer MAAS"
require_cmd jq curl dig

# --- Template et VM ------------------------------------------------------------------------------------------
_m11o_tpl="$(remote "$_M11O_PVE" 'qm config 9050' 2>/dev/null || true)"
check_output "9050 est un template" '^template: 1' echo "$_m11o_tpl"
check_output "9050 : nom tpl-ubuntu2404, étiquette ubuntu2404" '^name: tpl-ubuntu2404$' echo "$_m11o_tpl"
check_output "9050 : étiquette ubuntu2404" '^tags:.*ubuntu2404' echo "$_m11o_tpl"
_m11o_conf="$(remote "$_M11O_PVE" 'qm config 2116' 2>/dev/null || true)"
check_output "maas01 (2116) sur le VNet vprov" 'bridge=vprov' echo "$_m11o_conf"
check_output "maas01 : étiquettes env-m11 et role-maas" '^tags:.*env-m11.*role-maas|^tags:.*role-maas.*env-m11' echo "$_m11o_conf"
check_dns "maas01.par1.medisphere.internal → 10.10.60.11" maas01.par1.medisphere.internal A '^10\.10\.60\.11$' 10.10.20.10
check_output "NetBox : VM maas01, IP primaire 10.10.60.11/24" '^10\.10\.60\.11/24$' \
  bash -c 'jq -r ".results[0].primary_ip4.address // empty" <<<"$1"' _ "$(_m11o_nb_checks 'virtualization/virtual-machines/?name=maas01' || true)"

# --- Sur maas01 -------------------------------------------------------------------------------------------------
check_ssh "maas01 : Ubuntu 24.04" maas01 'grep -q "^VERSION_ID=\"24.04\"" /etc/os-release'
check_ssh_output "maas01 : snap maas suit le canal 3.7/stable" maas01 '^tracking: +3\.7/stable' 'snap info maas 2>/dev/null'
check_ssh "maas01 : PostgreSQL 16 actif" maas01 \
  'systemctl is-active --quiet postgresql && v=$(sudo -n -u postgres psql -tAc "SHOW server_version_num") && [ "$v" -ge 160000 ] && [ "$v" -lt 170000 ]'
check_ssh "maas01 : base maasdb accessible seulement en local (pas de 0.0.0.0/0 ni de « all » ouvert sur le réseau)" maas01 \
  'f=$(sudo -n find /etc/postgresql -name pg_hba.conf | head -n 1); [ -n "$f" ] && sudo -n grep -Eq "^host[[:space:]]+maasdb[[:space:]]+maas[[:space:]]+127\.0\.0\.1/32" "$f" && ! sudo -n grep -Eq "^host.*(0\.0\.0\.0/0|0/0|::/0)" "$f"'
check_ssh "maas01 : PostgreSQL n'écoute que sur la boucle locale" maas01 \
  's=$(ss -Hltn "sport = :5432"); [ -n "$s" ] && ! grep -Eqv "(127\.0\.0\.1|\[::1\]):5432" <<<"$s"'

# --- L'API de MAAS -------------------------------------------------------------------------------------------------
check_output "API de MAAS : version 3.7" '"version": *"3\.7' \
  curl -sf --max-time "$WB_TIMEOUT" "$_M11O_MAAS_URL/api/2.0/version/"
check_cmd "maas-api.key présent, en mode 600" _m11o_mode600 "$_M11O_MAAS_CLE"
check_output "la clé d'API authentifie un administrateur de MAAS" '^true$' \
  bash -c 'jq -r ".is_superuser" <<<"$1"' _ "$(_m11o_maas 'users/?op=whoami' || true)"
_m11o_images="$(_m11o_maas 'boot-resources/' || true)"
check_cmd "images : Ubuntu 24.04 (noble) amd64 synchronisée" \
  jq -e 'map(select(.name == "ubuntu/noble" and (.architecture | startswith("amd64")))) | length > 0' <<<"$_m11o_images"
# À ce stade (avant E10), MAAS ne sert le DHCP sur AUCUN VLAN : Kea tient le VLAN 60.
check_cmd "MAAS : DHCP désactivé sur tous ses VLAN" \
  bash -c 'jq -e "[.[].vlans[]? | select(.dhcp_on == true)] | length == 0" <<<"$1"' _ "$(_m11o_maas 'fabrics/' || true)"
