# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant ou par bash -c
#
# check-E46.sh — M07-E46 « Mini-projet : socle MédiSphère v2 »
# Contrôle global du socle v2 (depuis adm01) : bordure redondante, répartiteurs, routage, MTU,
# supervision, absence de maquette, acquis du module 06 revérifiés À TRAVERS la nouvelle bordure
# (résolveurs, PKI, NetBox, GitLab), documentation et hygiène. Lecture seule : pve01 et pbs01 en
# root (qm/pvesh/ip/wg en lecture), passerelles et répartiteurs en admin + sudo -n, dig, curl,
# openssl, API GitLab et NetBox en GET. Les détails restent dans les checks des exercices.

# shellcheck source=_m07-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-production.sh"

title "M07-E46 — Socle MédiSphère v2 : contrôle global"
require_cmd jq dig curl openssl ssh git
_m07p_charger
_m07p_charger_adresses gw01 gw02 lb01 lb02
_m07_doc="$_M07P_DEPOT/docs/socle"

# --- 1. VMs ----------------------------------------------------------------------------------------
title "1/9 VMs du socle v2"
for _m07_v in "1000 role-routeur" "1009 role-routeur" "1010 role-lb" "1011 role-lb"; do
  read -r _m07_id _m07_role <<<"$_m07_v"
  check_cmd "VM $_m07_id : démarrée, pool lab, étiquettes socle et $_m07_role" \
    _m07p_vm_jq "$_m07_id" "(.status == \"running\") and (.pool == \"lab\") and (((.tags // \"\") | split(\";\")) as \$t | (\$t | index(\"socle\")) and (\$t | index(\"$_m07_role\")))"
done
check_ssh "VMs du socle v1 (1001-1008) toujours démarrées" "$WB_PVE_HOST" \
  'for i in 1001 1002 1003 1004 1005 1006 1007 1008; do qm status "$i" | grep -q running || exit 1; done'
check_ssh "VMs 1000, 1009, 1010, 1011 : démarrage automatique et agent QEMU" "$WB_PVE_HOST" \
  'for i in 1000 1009 1010 1011; do qm config "$i" | grep -q "^onboot: 1" && qm guest cmd "$i" ping || exit 1; done'
check_cmd "maquette détruite : aucune VM 2070-2079" _m07p_aucune_vm_entre 2070 2079
check_cmd "maquette reconstructible : code de l'état m07-maquette conservé dans plateforme/infra" bash -c \
  'grep -rlsE "20(7[0-9])" "$1"/envs/m07-maquette "$1"/m07-maquette 2>/dev/null | grep -q .' _ "$_M07P_INFRA"

# --- 2. Bordure ------------------------------------------------------------------------------------
title "2/9 Bordure redondante"
for _m07_v in "${_M07P_VLANS[@]}"; do
  check_cmd "VLAN $_m07_v : gw01 .2, gw02 .3, VIP .1 portée par gw01 (état nominal)" bash -c \
    '[ "$1" = "gw01" ] && [ "$2" = 1 ] && [ "$3" = 1 ]' _ "$(_m07p_porteurs "10.10.$_m07_v.1" gw01 gw02 | tr '\n' ' ' | sed 's/ $//')" \
    "$(_m07p_porte gw01 "10.10.$_m07_v.2" && echo 1)" "$(_m07p_porte gw02 "10.10.$_m07_v.3" && echo 1)"
done
if [[ -n "${WB_GW_WAN_VIP:-}" ]]; then
  check_cmd "VIP WAN portée par gw01, avec les VIP des VLAN" _m07p_vips_bordure_ensemble
  check_ssh_output "pve01 : le lab est routé par la VIP WAN" "$WB_PVE_HOST" "via ${WB_GW_WAN_VIP//./\\.}( |$)" 'ip -4 route show 10.10.0.0/16'
  check_ssh_output "pbs01 : extrémité wg0 = VIP WAN" "$WB_PBS_HOST" "${WB_GW_WAN_VIP//./\\.}:51820" 'wg show wg0 endpoints'
  check_ssh_output "gw01 : le lab sort traduit vers la VIP WAN" gw01 "snat (ip )?to ${WB_GW_WAN_VIP//./\\.}" 'sudo -n nft list table ip nat'
else
  skip "VIP WAN, route de pve01, extrémité de pbs01, traduction" "WB_GW_WAN_VIP non renseignée dans lab/lab.env"
fi
for _m07_h in gw01 gw02; do
  check_ssh "$_m07_h : keepalived et conntrackd actifs" "$_m07_h" 'systemctl is-active -q keepalived && systemctl is-active -q conntrackd'
done
check_ssh "gw01 : MASTER, tunnels wg0 wg1 wg2 montés" gw01 \
  'grep -qx MASTER /run/bordure/etat && for i in wg0 wg1 wg2; do ip link show dev $i >/dev/null || exit 1; done'
check_ssh "gw02 : BACKUP, aucun tunnel monté, cache externe de conntrackd non vide" gw02 \
  'grep -qx BACKUP /run/bordure/etat && ! ip link show dev wg0 >/dev/null 2>&1 && [ "$(sudo -n conntrackd -e | grep -c .)" -gt 0 ]'
check_ssh "gw01 : poignée de main wg0 (PAR2) de moins de 3 minutes" gw01 \
  'now=$(date +%s); sudo -n wg show wg0 latest-handshakes | awk -v n="$now" "\$2 > 0 && n - \$2 < 180 {ok=1} END {exit !ok}"'
check_cmd "gw01 et gw02 chargent le même jeu de règles" _m07p_rulesets_identiques
check_ssh "aucune règle temporaire restante (amorçage, TEST-E32, agenda-demo)" gw01 \
  '! sudo -n nft list ruleset | grep -Eqi "amorçage|amorcage|TEST-E32|M07-E34"'

# --- 3. Routage ------------------------------------------------------------------------------------
title "3/9 Routage dynamique (FRR)"
for _m07_h in gw01 gw02; do
  check_ssh "$_m07_h : FRR actif, AS 65000, plage d'écoute K8S prête (10.10.40.0/24)" "$_m07_h" '
    systemctl is-active -q frr || exit 1
    c=$(sudo -n vtysh -c "show running-config") || exit 1
    grep -q "^router bgp 65000" <<<"$c" && grep -Eq "bgp listen range 10\.10\.40\.0/24 peer-group K8S" <<<"$c"'
  check_ssh "$_m07_h : politique d'entrée qui n'accepte que 10.10.255.0/24 et 10.10.41.0/24" "$_m07_h" '
    c=$(sudo -n vtysh -c "show running-config") || exit 1
    grep -Eq "prefix-list .* permit 10\.10\.41\.0/24" <<<"$c" && grep -Eq "prefix-list .* permit 10\.10\.255\.0/24" <<<"$c"'
  check_ssh "$_m07_h : aucun voisin configuré en échec (Lyon et leaf01 désactivés ou retirés)" "$_m07_h" '
    sudo -n vtysh -c "show bgp summary json" | jq -e "[.. | objects | select(has(\"peers\")) | .peers[] | .state
      | select(. != \"Established\" and (test(\"Admin\") | not))] | length == 0" >/dev/null'
done

# --- 4. MTU ----------------------------------------------------------------------------------------
title "4/9 MTU : jumbo frames sur les VLAN de stockage seulement"
check_ssh_output "pve01 : vmbr1 en MTU 9000" "$WB_PVE_HOST" 'mtu 9000' 'ip link show dev vmbr1'
for _m07_h in gw01 gw02; do
  check_ssh "$_m07_h : ens19 et ens19.30 en 9000, ens19.10 et ens19.99 en 1500" "$_m07_h" '
    [ "$(cat /sys/class/net/ens19/mtu)" = 9000 ] && [ "$(cat /sys/class/net/ens19.30/mtu)" = 9000 ] &&
    [ "$(cat /sys/class/net/ens19.10/mtu)" = 1500 ] && [ "$(cat /sys/class/net/ens19.99/mtu)" = 1500 ]'
done

# --- 5. Répartiteurs ---------------------------------------------------------------------------------
title "5/9 Points d'entrée"
check_cmd "VIP 10.10.70.200 portée par un seul répartiteur" _m07p_vip_unique 10.10.70.200 lb01 lb02
check_cmd "gitlab.$_M07P_ZONE : certificat valide (PKI MédiSphère, ACME)" _m07p_cert_ok "gitlab.$_M07P_ZONE" 10.10.70.200
check_cmd "netbox.$_M07P_ZONE : certificat valide (PKI MédiSphère, ACME)" _m07p_cert_ok "netbox.$_M07P_ZONE" 10.10.70.200
check_output "GitLab par la VIP : 200 avec HSTS" 'max-age=' _m07p_entete "https://gitlab.$_M07P_ZONE/users/sign_in" Strict-Transport-Security
check_output "NetBox par la VIP : 200" '^200$' _m07p_code "https://netbox.$_M07P_ZONE/login/"
for _m07_h in lb01 lb02; do
  check_cmd "$_m07_h : git01 et nbx01 UP" bash -c '[ "$1" = 1 ] && [ "$2" = 1 ]' _ \
    "$(_m07p_serveur_up "$_m07_h" be_gitlab git01 && echo 1)" "$(_m07p_serveur_up "$_m07_h" be_netbox nbx01 && echo 1)"
  check_ssh "$_m07_h : filtrage local en politique drop" "$_m07_h" 'sudo -n nft list table inet filtre_local | grep -q "policy drop"'
done
check_output "service temporaire de M07-E34 retiré (agenda-demo ne se résout plus)" '^$' \
  dig +short +time=3 @10.10.20.10 "agenda-demo.$_M07P_ZONE" A

# --- 6. Acquis du module 06, à travers la nouvelle bordure -------------------------------------------
title "6/9 Acquis du module 06"
for _m07_r in 10.10.20.10 10.10.20.16; do
  check_dns "$_m07_r : résout git01" "git01.$_M07P_ZONE" A '^10\.10\.20\.12$' "$_m07_r"
  check_dns "$_m07_r : résout un nom Internet" deb.debian.org A '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' "$_m07_r"
done
check_dns "DNS : gw01 → 10.10.10.2" "gw01.$_M07P_ZONE" A '^10\.10\.10\.2$' 10.10.20.10
check_http "ca01 : step-ca en bonne santé" "https://ca01.$_M07P_ZONE/health" 200 --cacert "$_M07P_RACINE"
_m07_nb_ok() { netbox_api status/ | jq -e '."netbox-version" | startswith("4.6.")' >/dev/null; }
check_cmd "API NetBox 4.6.x (jeton des checks)" _m07_nb_ok
_m07_gl_ok() { gitlab_api version | jq -e '.version | startswith("19.")' >/dev/null; }
check_cmd "API GitLab (jeton des checks)" _m07_gl_ok
_m07_vms_nb() {
  local h
  for h in gw02 lb01 lb02; do
    netbox_api "virtualization/virtual-machines/?name=$h" | jq -e '.count == 1 and .results[0].status.value == "active"' >/dev/null || return 1
  done
}
check_cmd "NetBox : gw02, lb01, lb02 décrits (actifs)" _m07_vms_nb
check_cmd "NetBox : neuf groupes FHRP vrrp3 de la bordure" bash -c \
  '[ "$1" -ge 9 ]' _ "$(netbox_api 'ipam/fhrp-groups/?protocol=vrrp3&limit=100' 2>/dev/null | jq '.count // 0' 2>/dev/null || echo 0)"

# --- 7. Supervision ----------------------------------------------------------------------------------
title "7/9 Supervision"
for _m07_u in ms-verif-reseau ms-verif-services; do
  check_cmd "$_m07_u : timer actif, dernier passage réussi" bash -c \
    'systemctl is-active -q "$1.timer" && [ "$(systemctl show "$1.service" -p Result --value)" = success ]' _ "$_m07_u"
done
check_cmd "ms-verif-reseau : tout va bien maintenant" timeout 180 /usr/local/bin/ms-verif-reseau --quiet

# --- 8. Documentation ----------------------------------------------------------------------------------
title "8/9 Documentation (plateforme/medisphere)"
check_cmd "docs/socle/reseau/architecture.md : bordure, VRRP, points d'entrée, points uniques restants" bash -c \
  'f="$1/reseau/architecture.md"; for m in VRRP 10.10.70.200 pve01 65000 conntrackd; do grep -qi "$m" "$f" || exit 1; done' _ "$_m07_doc"
check_cmd "ADR-0070 présent" bash -c 'ls "$1"/adr/ADR-0070*.md >/dev/null 2>&1' _ "$_m07_doc"
check_cmd "RB-070, RB-071, RB-072 présents" bash -c \
  'for r in RB-070 RB-071 RB-072; do ls "$1"/runbooks/"$r"*.md >/dev/null 2>&1 || exit 1; done' _ "$_m07_doc"
check_cmd "matrice des flux générée (ms-matrice-flux)" bash -c 'grep -q "ms-matrice-flux" "$1/matrice-flux.md"' _ "$_m07_doc"
check_cmd "tests de bascule consignés (bascules.md, sept scénarios au moins)" bash -c \
  '[ "$(grep -Ec "^\| *[0-9]+ *\|.*[0-9]+([,.][0-9]+)? ?(s|ms) *\|" "$1/tests/bascules.md")" -ge 7 ]' _ "$_m07_doc"
check_cmd "inventaire : gw02, lb01, lb02 et leurs adresses" bash -c \
  'for m in gw02 10.10.10.3 lb01 10.10.70.10 lb02 10.10.70.11; do grep -qF "$m" "$1/inventaire.md" || exit 1; done' _ "$_m07_doc"
check_cmd "registre des secrets : WireGuard de la bordure, statistiques HAProxy, clé de supervision" bash -c \
  'f="$1/registre-secrets.md"; grep -qi "wireguard" "$f" && grep -qi "haproxy" "$f" && grep -qi "supervision-reseau" "$f"' _ "$_m07_doc"
check_cmd "aucun secret évident dans docs/socle (clé privée, clé WireGuard, jetons)" bash -c \
  '! grep -REq "(BEGIN [A-Z ]*PRIVATE KEY|PrivateKey *= *[A-Za-z0-9+/]{42}[AEIMQUYcgkosw048]=|nbt_[A-Za-z0-9]{8,}\.[A-Za-z0-9]{16,}|glpat-[A-Za-z0-9_-]{20})" "$1"' _ "$_m07_doc"

# --- 9. Livraison et hygiène -----------------------------------------------------------------------------
title "9/9 Livraison"
check_output "dépôt de documentation : aucune modification non commitée" '^$' git -C "$_M07P_DEPOT" status --porcelain
_m07_etiquette() { gitlab_api 'projects/plateforme%2Fmedisphere/repository/tags/socle-v2' | jq -e '.name == "socle-v2"' >/dev/null; }
check_cmd "plateforme/medisphere : étiquette socle-v2 publiée" _m07_etiquette
check_cmd "aucune panne M07 encore active (lab/bin/break)" _m07p_aucune_panne_active
check_cmd "fichiers de secrets de ~/.config/workbook en 600 (dont la clé de supervision)" bash -c \
  '! find "$HOME/.config/workbook" -maxdepth 1 -type f \( -name "*.env" -o -name "*.token" -o -name "*.pass" -o -name "ssh-*" ! -name "*.pub" \) ! -perm 600 | grep -q .'
