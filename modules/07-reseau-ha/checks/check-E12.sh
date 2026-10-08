# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E12.sh — M07-E12 : Déployer les répartiteurs lb01 et lb02
# À lancer depuis adm01. Lecture seule (aucune bascule n'est provoquée).

# shellcheck source=_m07-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-operationnel.sh"

title "M07-E12 — Déployer les répartiteurs lb01 et lb02"
require_cmd jq curl openssl dig

declare -A _m07o_ip=([lb01]=10.10.70.10 [lb02]=10.10.70.11)
declare -A _m07o_vmid=([lb01]=1010 [lb02]=1011)

# --- Les VMs, leurs noms ------------------------------------------------------------------------------
for _m07o_h in lb01 lb02; do
  _m07o_conf="$(_m07o_vm_config "${_m07o_vmid[$_m07o_h]}")"
  check_output "VM ${_m07o_vmid[$_m07o_h]} : nommée $_m07o_h" "^name: $_m07o_h\$" echo "$_m07o_conf"
  check_output "VM ${_m07o_vmid[$_m07o_h]} : étiquettes socle et role-lb" '^tags:.*role-lb' echo "$_m07o_conf"
  check_output "VM ${_m07o_vmid[$_m07o_h]} : étiquette socle" '^tags:(.*;)?socle(;|$)' echo "$_m07o_conf"
  check_output "VM ${_m07o_vmid[$_m07o_h]} : carte sur vdmz" '^net0:.*bridge=vdmz' echo "$_m07o_conf"
  check_dns "$_m07o_h.$_M07O_ZONE → ${_m07o_ip[$_m07o_h]}" "$_m07o_h.$_M07O_ZONE" A "^${_m07o_ip[$_m07o_h]//./\\.}$" 10.10.20.10
  check_ssh "$_m07o_h : joignable en SSH, keepalived et haproxy actifs" "$_m07o_h" \
    'systemctl is-active --quiet keepalived && systemctl is-active --quiet haproxy'
  check_ssh "$_m07o_h : HAProxy 3.2" "$_m07o_h" 'haproxy -v | grep -q "^HAProxy version 3\.2\."'
  check_ssh "$_m07o_h : keepalived en VRRP v3, VRID 170, annonces unicast" "$_m07o_h" \
    'f=/etc/keepalived/keepalived.conf; sudo -n grep -Eq "vrrp_version 3|^[[:space:]]*version 3" $f && sudo -n grep -Eq "virtual_router_id 170$" $f && sudo -n grep -q "unicast_peer" $f'
  check_ssh "$_m07o_h : les scripts de suivi ne tournent pas en root (enable_script_security)" "$_m07o_h" \
    'sudo -n grep -q "enable_script_security" /etc/keepalived/keepalived.conf'
done

# --- La VIP ---------------------------------------------------------------------------------------------
check_dns "lb.$_M07O_ZONE → 10.10.70.200" "lb.$_M07O_ZONE" A '^10\.10\.70\.200$' 10.10.20.10
_m07o_role_vip() { netbox_api "ipam/ip-addresses/?address=10.10.70.200" | jq -r '.results[0].role.value // empty'; }
check_output "NetBox : 10.10.70.200 a le rôle « VIP »" '^vip$' _m07o_role_vip
_m07o_porteurs=0
for _m07o_h in lb01 lb02; do
  if remote "$_m07o_h" 'ip -o -4 addr show | grep -q " 10\.10\.70\.200/"' >/dev/null 2>&1; then
    _m07o_porteurs=$((_m07o_porteurs + 1))
  fi
done
check_output "un et un seul répartiteur porte la VIP (vu : $_m07o_porteurs)" '^1$' echo "$_m07o_porteurs"

# --- Le service rendu ----------------------------------------------------------------------------------
_m07o_x509="$(_m07o_cert_tls 10.10.70.200 443 "lb.$_M07O_ZONE")"
check_output "VIP : certificat émis par « MédiSphère Intermediate CA »" 'issuer=.*Interm' echo "$_m07o_x509"
check_output "VIP : le nom lb.$_M07O_ZONE est dans le certificat" "DNS:lb\\.par1\\.medisphere\\.internal" echo "$_m07o_x509"
check_output "https://lb.$_M07O_ZONE/sante répond 200 (racine MédiSphère seule)" '^200$' _m07o_curl "https://lb.$_M07O_ZONE/sante"
check_output "http://lb.$_M07O_ZONE/ redirige vers HTTPS (301)" '^301$' \
  bash -c 'curl -s -o /dev/null -w "%{http_code}" --max-time "$1" "http://lb.par1.medisphere.internal/" || true' _ "$WB_TIMEOUT"
for _m07o_h in lb01 lb02; do
  check_output "$_m07o_h répond en direct (curl --resolve vers ${_m07o_ip[$_m07o_h]})" '^200$' \
    _m07o_curl "https://lb.$_M07O_ZONE/sante" --resolve "lb.$_M07O_ZONE:443:${_m07o_ip[$_m07o_h]}"
done

# --- Pare-feu et documentation ---------------------------------------------------------------------------
_m07o_fwd="$(_m07o_nft_gw01 forward)"
_m07o_regle() { # _m07o_regle MOTIF… — une règle de forward contient tous les motifs donnés
  local l="$_m07o_fwd" m
  for m in "$@"; do l="$(grep -E -- "$m" <<<"$l" || true)"; done
  [[ -n "$l" ]]
}
check_cmd "gw01 : runner01 joint les répartiteurs en SSH" _m07o_regle 'oifname "ens19\.70"' '10\.10\.20\.15' 'tcp dport 22 accept'
check_cmd "gw01 : les répartiteurs joignent ca01 en 443 (ACME)" _m07o_regle 'iifname "ens19\.70"' '10\.10\.20\.11' 'tcp dport 443 accept'
check_cmd "gw01 : ca01 joint le port 80 des répartiteurs (défi ACME)" _m07o_regle 'oifname "ens19\.70"' 'ip saddr 10\.10\.20\.11' 'tcp dport 80 accept'
check_output "plateforme/medisphere : ADR-0071 sur main" 'ADR-0071' \
  _m07o_cherche_main "$_M07O_PROJET_DOC" '^docs/socle/adr/ADR-0071'
check_cmd "plateforme/ansible : playbook repartiteurs.yml sur main" \
  _m07o_fichier_main "$_M07O_PROJET_ANSIBLE" playbooks/repartiteurs.yml
