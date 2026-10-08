# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes entre apostrophes
#
# check-E07.sh — M09-E07 : Premières VMs du cluster et migration
# À lancer depuis adm01. Lecture seule : /cluster/resources, /cluster/tasks, configuration et
# agent des invités (pvesh get, root sur un nœud), configuration des VMs 2091-2093 sur pve01,
# ping et SSH (compte admin) vers l'invité app01.

# shellcheck source=_m09-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-decouverte.sh"

title "M09-E07 — Premières VMs du cluster et migration"
require_cmd jq

_m09d_e07_h="$(_m09d_premier_noeud)"
_m09d_e07_res="$(_m09d_ressources "${_m09d_e07_h:-hv01}")"

for _m09d_e07_v in 101:app01 102:app02; do
  _m09d_e07_id="${_m09d_e07_v%%:*}"
  _m09d_e07_nom="${_m09d_e07_v##*:}"
  check_cmd "Invité $_m09d_e07_id « $_m09d_e07_nom » présent dans le cluster" \
    jq -e --argjson id "$_m09d_e07_id" --arg n "$_m09d_e07_nom" \
    '[.[] | select(.vmid == $id and .name == $n and (.template // 0) == 0)] | length == 1' <<<"$_m09d_e07_res"
  _m09d_e07_conf="$(_m09d_config_invite "${_m09d_e07_h:-hv01}" "$_m09d_e07_id")"
  check_cmd "$_m09d_e07_nom : disque sur zfs-local, carte sur vmbr1 VLAN 99" \
    jq -e '(.scsi0 // "" | startswith("zfs-local:")) and (.net0 // "" | test("bridge=vmbr1") and test("tag=99"))' <<<"$_m09d_e07_conf"
  check_cmd "$_m09d_e07_nom : clone complet (disque indépendant du template)" \
    jq -e '(.scsi0 // "") | test("base-199-") | not' <<<"$_m09d_e07_conf"
done
check_cmd "app01 en marche" jq -e '[.[] | select(.vmid == 101 and .status == "running")] | length == 1' <<<"$_m09d_e07_res"

# --- app01 joignable ------------------------------------------------------------------------------
_m09d_e07_porteur="$(jq -r '.[] | select(.vmid == 101) | .node' <<<"$_m09d_e07_res" 2>/dev/null | head -n 1)"
_m09d_e07_ip="$(_m09d_hv "${_m09d_e07_h:-hv01}" "pvesh get /nodes/${_m09d_e07_porteur:-hv01}/qemu/101/agent/network-get-interfaces --output-format json" \
  | jq -r '[.result[]?."ip-addresses"[]? | select(."ip-address-type" == "ipv4") | ."ip-address" | select(startswith("10.10.99."))][0] // empty' 2>/dev/null || true)"
check_cmd "app01 : l'agent QEMU répond et rapporte une adresse DHCP du VLAN 99" test -n "$_m09d_e07_ip"
if [[ -n "$_m09d_e07_ip" ]]; then
  check_ping "app01 ($_m09d_e07_ip) répond au ping depuis adm01" "$_m09d_e07_ip"
  check_cmd "app01 : SSH admin par clé depuis adm01" \
    ssh -o BatchMode=yes -o ConnectTimeout="$WB_TIMEOUT" -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile=/dev/null "admin@$_m09d_e07_ip" true
else
  skip "app01 joignable depuis adm01" "adresse inconnue"
fi

# --- Les migrations ---------------------------------------------------------------------------------
_m09d_e07_taches="$(_m09d_hv "${_m09d_e07_h:-hv01}" 'pvesh get /cluster/tasks --output-format json')"
for _m09d_e07_id in 101 102; do
  check_cmd "Au moins une migration réussie de l'invité $_m09d_e07_id (tâche qmigrate OK)" \
    jq -e --arg id "$_m09d_e07_id" '[.[] | select(.type == "qmigrate" and .id == $id and .status == "OK")] | length >= 1' <<<"$_m09d_e07_taches"
done

# --- Expérience du pare-feu de pve01 : annulée -------------------------------------------------------
for _m09d_e07_vm in 2091 2092; do
  check_cmd "VM $_m09d_e07_vm : pare-feu de pve01 désactivé sur net4 (retour à l'état du code)" \
    bash -c 'grep -q "^net4: " <<<"$1" && ! grep -E "^net4: " <<<"$1" | grep -q "firewall=1"' _ "$(_m09d_qm "$_m09d_e07_vm")"
done
