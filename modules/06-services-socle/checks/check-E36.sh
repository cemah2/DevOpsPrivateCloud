# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
# check-E36.sh — M06-E36 « Panne : les VMs sandbox n'obtiennent plus d'adresse » : chaîne DHCP du
# VLAN 99 saine (relais de gw01, filtrage, Kea sur dns01 et dns02). Lecture seule.

# shellcheck source=_m06-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-expert.sh"

title "M06-E36 — DHCP du VLAN sandbox"
require_cmd ssh

check_ssh "gw01 : relais DHCP (dnsmasq) actif" gw01 'systemctl is-active -q dnsmasq'
check_ssh "gw01 : relais du VLAN 99 (adresse locale 10.10.99.1) vers dns01" gw01 \
  "grep -Ehs '^[[:space:]]*dhcp-relay=10\\.10\\.99\\.1,10\\.10\\.20\\.10([,#[:space:]]|\$)' /etc/dnsmasq.conf /etc/dnsmasq.d/*.conf | grep -q ."
check_ssh "gw01 : aucune règle ne jette les réponses des serveurs DHCP" gw01 \
  "! sudo -n nft list chain inet filter input | grep -E 'udp sport 67' | grep -Eq '(drop|reject)'"
check_ssh "gw01 : jeu de règles en mémoire identique au fichier (aucune règle posée à chaud)" gw01 \
  "! sudo -n nft list chain inet filter input | grep -q 'durcissement INC-3342'"
for _m06_e36_h in dns01 dns02; do
  if [[ "$_m06_e36_h" == dns02 ]] && ! _m06x_existe dns02; then
    skip "dns02 : Kea" "dns02 absent (M06-E24)"
    continue
  fi
  check_ssh "$_m06_e36_h : kea-dhcp4 actif et activé" "$_m06_e36_h" \
    "$_m06x_kea4"'; [ -n "$k" ] && systemctl is-active -q "$k" && systemctl is-enabled -q "$k"'
  check_ssh "$_m06_e36_h : configuration de kea-dhcp4 valide (kea-dhcp4 -t)" "$_m06_e36_h" \
    'sudo -n kea-dhcp4 -t /etc/kea/kea-dhcp4.conf'
  check_ssh "$_m06_e36_h : sous-réseau 10.10.99.0/24 (id 99), plage .100-.199" "$_m06_e36_h" \
    'c=$(sudo -n cat /etc/kea/kea-dhcp4.conf); echo "$c" | grep -q "10\.10\.99\.0/24" && echo "$c" | grep -Eq "\"id\"[[:space:]]*:[[:space:]]*99([^0-9]|\$)" && echo "$c" | grep -Eq "10\.10\.99\.100[[:space:]]*-[[:space:]]*10\.10\.99\.199"'
  check_ssh "$_m06_e36_h : baux dans /var/lib/kea, interfaces existantes" "$_m06_e36_h" '
    c=$(sudo -n cat /etc/kea/kea-dhcp4.conf)
    ! echo "$c" | grep -Eq "\"name\"[[:space:]]*:[[:space:]]*\"/(tmp|var/tmp)/" || exit 1
    for i in $(echo "$c" | tr "\n" " " | grep -oE "\"interfaces\"[[:space:]]*:[[:space:]]*\[[^]]*\]" | grep -oE "\"[^\"]+\"" | tr -d "\"" | grep -v "^interfaces$"); do
      [ "$i" = "*" ] || ip link show "${i%%/*}" >/dev/null 2>&1 || exit 1
    done'
  check_ssh "$_m06_e36_h : kea-dhcp4 écoute sur UDP/67" "$_m06_e36_h" \
    "sudo -n ss -lunp 'sport = :67' | grep -q kea-dhcp4"
done
if remote "$WB_PVE_HOST" "qm status 2069" >/dev/null 2>&1; then
  check_ssh "VM sonde 2069 : adresse obtenue sur le VLAN 99" "$WB_PVE_HOST" \
    "qm guest cmd 2069 network-get-interfaces | grep -Eq '\"ip-address\" *: *\"10\\.10\\.99\\.'"
else
  skip "VM sonde 2069" "absente (détruite par --annuler)"
fi
check_cmd "panne M06-E36 close (lab/bin/break 06 36 --annuler après réparation)" _m06x_aucune_panne_active E36
