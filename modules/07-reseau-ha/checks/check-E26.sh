# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
#
# check-E26.sh — M07-E26 « Bordure redondante côté WAN et VPN »
# Lecture seule : gw01/gw02 (admin + sudo -n ; la clé PUBLIQUE est recalculée sur l'hôte, la clé
# privée ne sort jamais), pve01 et pbs01 (root, lecture des routes et de l'état WireGuard), API GitLab.
# Valeurs de lab/lab.env : WB_GW_WAN_VIP (obligatoire ici), WB_GW01_WAN, WB_GW02_WAN.

# shellcheck source=_m07-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-production.sh"

title "M07-E26 — Bordure redondante côté WAN et VPN"
require_cmd jq ssh
_m07p_charger
_m07p_charger_adresses gw01 gw02
_m07_vip="${WB_GW_WAN_VIP:-}"
_m07_m="$(_m07p_maitre)"
_m07_s="$(_m07p_secours)"

if [[ -z "$_m07_vip" ]]; then
  skip "contrôles de la VIP WAN" "WB_GW_WAN_VIP non renseignée dans lab/lab.env"
else
  title "VIP WAN ($_m07_vip)"
  check_cmd "VIP WAN portée par une seule passerelle" _m07p_vip_unique "$_m07_vip" gw01 gw02
  check_cmd "VIP WAN et VIP des VLAN sur la même passerelle" _m07p_vips_bordure_ensemble
  for _m07_h in gw01 gw02; do
    check_ssh "$_m07_h : instance VRID 250 sur ens18, dans le groupe BORDURE" "$_m07_h" '
      c=$(sudo -n cat /etc/keepalived/keepalived.conf) || exit 1
      awk "/^vrrp_instance/ {i=0} /interface ens18\$/ {i=1} i && /virtual_router_id 250\$/ {ok=1} END {exit !ok}" <<<"$c" &&
      [ "$(awk "/^vrrp_sync_group BORDURE/ {g=1} g && /^}/ {g=0} g && /^[[:space:]]+[A-Z]+[0-9]*[[:space:]]*\$/ {n++} END {print n+0}" <<<"$c")" -ge 10 ]'
  done
fi

title "Tunnels : sur le maître seulement, mêmes clés"
if [[ -z "$_m07_m" ]]; then
  check_cmd "une passerelle maître identifiable (porte 10.10.10.1)" false
else
  for _m07_i in wg0 wg1 wg2; do
    check_ssh "$_m07_m (maître) : interface $_m07_i présente" "$_m07_m" "ip link show dev $_m07_i >/dev/null"
    check_ssh "$_m07_s (secours) : interface $_m07_i absente" "$_m07_s" "! ip link show dev $_m07_i >/dev/null 2>&1"
  done
fi
# _m07_cles_pub HÔTE — clés publiques de wg0, wg1, wg2 recalculées sur l'hôte depuis sa configuration.
_m07_cles_pub() {
  remote "$1" 'for i in wg0 wg1 wg2; do sudo -n awk "/^PrivateKey/ {print \$3}" /etc/wireguard/$i.conf | wg pubkey || exit 1; done' 2>/dev/null
}
_m07_cles_identiques() {
  local a b
  a="$(_m07_cles_pub gw01)" || return 1
  b="$(_m07_cles_pub gw02)" || return 1
  [[ "$(wc -l <<<"$a")" == 3 && "$a" == "$b" ]]
}
check_cmd "wg0, wg1, wg2 : même identité (clé publique) sur gw01 et gw02" _m07_cles_identiques
for _m07_h in gw01 gw02; do
  check_ssh "$_m07_h : wg-quick@wg0/1/2 non démarrés au boot (pilotés par la transition)" "$_m07_h" \
    'for i in wg0 wg1 wg2; do [ "$(systemctl is-enabled wg-quick@$i 2>/dev/null)" != enabled ] || exit 1; done'
  check_ssh "$_m07_h : fichiers WireGuard réservés à root (600)" "$_m07_h" \
    'for i in wg0 wg1 wg2; do [ "$(sudo -n stat -c %a /etc/wireguard/$i.conf)" = 600 ] || exit 1; done'
  check_ssh "$_m07_h : le script de transition pilote les trois tunnels" "$_m07_h" \
    'grep -Eq "^BORDURE_TUNNELS=\"?wg0 wg1 wg2\"?" /etc/bordure/transition.conf'
done
check_cmd "dépôt Ansible : aucune clé privée WireGuard en clair" bash -c '
  ! grep -rIEl "^[[:space:]]*(PrivateKey[[:space:]]*=|vault_wireguard_[a-z0-9_]*:)[[:space:]]*\"?[A-Za-z0-9+/]{42}[AEIMQUYcgkosw048]=" "$1/inventories" "$1/roles" 2>/dev/null | grep -q .' _ "$_M07P_ANSIBLE"
check_cmd "clés de la bordure en Vault (group_vars/role_routeur/vault-critique.yml chiffré)" bash -c \
  'head -n 1 "$1/inventories/lab/group_vars/role_routeur/vault-critique.yml" 2>/dev/null | grep -q "^\$ANSIBLE_VAULT;1\.2;AES256;critique"' _ "$_M07P_ANSIBLE"

if [[ -n "$_m07_vip" ]]; then
  title "Traduction et redirection"
  for _m07_h in gw01 gw02; do
    check_ssh_output "$_m07_h : le lab sort traduit vers la VIP WAN" "$_m07_h" \
      "ip saddr 10\\.10\\.0\\.0/16 .*snat (ip )?to ${_m07_vip//./\\.}" 'sudo -n nft list table ip nat'
    check_ssh "$_m07_h : plus de masquerade du lab sur le WAN" "$_m07_h" \
      '! sudo -n nft list table ip nat | grep -E "oifname \"ens18\" ip saddr 10\.10\.0\.0/16 .*masquerade"'
    check_ssh_output "$_m07_h : tunnels émis depuis la VIP (traduction des ports 51820-51821)" "$_m07_h" \
      "udp sport \\{ 51820, 51821 \\} snat (ip )?to ${_m07_vip//./\\.}" 'sudo -n nft list table ip nat'
    check_ssh_output "$_m07_h : redirection HTTPS sur la VIP WAN vers 10.10.70.200" "$_m07_h" \
      "ip daddr ${_m07_vip//./\\.} tcp dport 443 dnat (ip )?to 10\\.10\\.70\\.200" 'sudo -n nft list table ip nat'
  done

  title "Extérieur de la bordure"
  for _m07_r in 10.10.0.0/16 10.20.0.0/16 10.255.1.0/24; do
    check_ssh_output "pve01 : $_m07_r via la VIP WAN" "$WB_PVE_HOST" "via ${_m07_vip//./\\.}( |$)" "ip -4 route show $_m07_r"
  done
  check_ssh_output "pbs01 : extrémité wg0 de PAR1 = VIP WAN" "$WB_PBS_HOST" "${_m07_vip//./\\.}:51820" 'wg show wg0 endpoints'
  check_ssh "pbs01 : poignée de main wg0 de moins de 3 minutes" "$WB_PBS_HOST" \
    'now=$(date +%s); wg show wg0 latest-handshakes | awk -v n="$now" "\$2 > 0 && n - \$2 < 180 {ok=1} END {exit !ok}"'
fi

title "Lyon et documentation"
if _m07p_vm_tourne 2077 && [[ -n "$_m07_m" ]]; then
  check_cmd "BGP de Lyon (10.255.2.2) établi sur le maître" _m07p_bgp_etabli "$_m07_m" 10.255.2.2
else
  skip "BGP de Lyon" "maquette LYO1 arrêtée (VM 2077) ou maître non identifiable"
fi
check_cmd "plateforme/medisphere : fiche CHG-856 sur main" _m07p_doc_main docs/socle/changements CHG-856
# _m07_rb071 — RB-071 sur main de plateforme/medisphere, qui traite le cerveau divisé.
_m07_rb071() {
  local f
  f="$(gitlab_api "projects/plateforme%2Fmedisphere/repository/tree?ref=main&path=docs%2Fsocle%2Frunbooks&per_page=100" 2>/dev/null \
    | jq -r '.[]? | select(.name | startswith("RB-071")) | .path' | head -n 1)" || return 1
  [[ -n "$f" ]] && _m07p_fichier_main plateforme/medisphere "$f" 2>/dev/null | grep -qiE 'cerveau|split'
}
check_cmd "plateforme/medisphere : RB-071 sur main, cas du cerveau divisé traité" _m07_rb071
