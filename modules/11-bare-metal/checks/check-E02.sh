# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes et filtres jq entre apostrophes, évalués ailleurs
#
# check-E02.sh — M11-E02 : Le réseau de provisioning
# À lancer depuis adm01. Lecture seule. Le seul paquet émis vers le VLAN 60 est un DHCPDISCOVER
# (sonde nmap sur pxe01, si nmap y est installé) : un DISCOVER suivi d'une OFFER ne crée aucun bail.

# shellcheck source=_m11-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m11-decouverte.sh"

title "M11-E02 — Le réseau de provisioning"
require_cmd jq curl dig

# --- pxe01 : la VM, son nom ----------------------------------------------------------------------
_m11d_conf="$(_m11d_qm_config 2111)"
check_output "pxe01 (2111) existe, sur le VNet vprov" 'bridge=vprov' echo "$_m11d_conf"
check_output "pxe01 : étiquettes env-m11 et role-pxe" '^tags:.*env-m11' echo "$_m11d_conf"
check_output "pxe01 : étiquette role-pxe" '^tags:.*role-pxe' echo "$_m11d_conf"
check_dns "pxe01.par1.medisphere.internal → 10.10.60.10" pxe01.par1.medisphere.internal A '^10\.10\.60\.10$' 10.10.20.10
check_output "10.10.60.10 → pxe01.par1.medisphere.internal (PTR)" '^pxe01\.par1\.medisphere\.internal\.$' \
  dig +short +time=3 @10.10.20.10 -x 10.10.60.10
check_ssh "pxe01 joignable en SSH à 10.10.60.10" pxe01 'ip -4 -o addr show | grep -q "10\.10\.60\.10/24"'

# --- TFTP et HTTP ------------------------------------------------------------------------------
check_ssh "pxe01 : tftpd-hpa et nginx actifs et activés" pxe01 \
  'for s in tftpd-hpa nginx; do systemctl is-active --quiet $s && systemctl is-enabled --quiet $s || exit 1; done'
# TFTP lu DEPUIS pxe01 : le transfert revient d'un port éphémère, qu'un pare-feu sans assistant
# TFTP (la bordure) traite comme une nouvelle connexion VLAN 60 → MGMT, donc refusée.
for _m11d_f in undionly.kpxe ipxe.efi; do
  check_ssh "TFTP sert $_m11d_f" pxe01 \
    "curl -sf --max-time 10 -o /dev/null tftp://10.10.60.10/$_m11d_f"
done
check_ssh "TFTP refuse les écritures (pas d'option --create)" pxe01 \
  '! grep -Eq "^TFTP_OPTIONS=.*(-c|--create)" /etc/default/tftpd-hpa'
check_ssh "TFTP et HTTP n'écoutent pas sur toutes les adresses" pxe01 \
  's="$(ss -Hlun "sport = :69"; ss -Hltn "sport = :80")"; [ -n "$s" ] && ! grep -Eq "(0\.0\.0\.0|\*|\[::\]):(69|80)\b" <<<"$s"'
_m11d_racine="$(_m11d_http pki/medisphere-root-ca.crt | sha256sum | cut -d ' ' -f 1)"
check_output "HTTP sert la racine de la PKI (identique à celle de adm01)" "^$(_m11d_sha_racine_locale)\$" echo "$_m11d_racine"
check_output "HTTP ne liste pas les répertoires (/preseed/ : 403 ou 404)" '^(403|404)$' \
  curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" "$_M11D_PXE_URL/preseed/"

# --- Kea : configuration chargée sur les deux pairs ---------------------------------------------------
for _m11d_h in dns01 dns02; do
  _m11d_k="$(_m11d_kea "$_m11d_h")"
  check_cmd "$_m11d_h : Kea charge le sous-réseau 60 (10.10.60.0/24, plage .100-.199)" \
    jq -e '.arguments.Dhcp4.subnet4 | map(select(.id == 60 and .subnet == "10.10.60.0/24"
           and ([.pools[].pool | gsub(" "; "")] | index("10.10.60.100-10.10.60.199") != null))) | length == 1' <<<"$_m11d_k"
  check_cmd "$_m11d_h : sous-réseau 60 avec next-server 10.10.60.10 et routeur 10.10.60.1" \
    jq -e '.arguments.Dhcp4.subnet4[] | select(.id == 60)
           | .["next-server"] == "10.10.60.10"
             and ([.["option-data"][] | select(.name == "routers") | .data] | index("10.10.60.1") != null)' <<<"$_m11d_k"
  check_cmd "$_m11d_h : sous-réseau 99 toujours servi" \
    jq -e '.arguments.Dhcp4.subnet4 | map(select(.id == 99 and .subnet == "10.10.99.0/24")) | length == 1' <<<"$_m11d_k"
done

# --- Relais des deux passerelles --------------------------------------------------------------------
for _m11d_h in gw01 gw02; do
  check_ssh "$_m11d_h : le relais écoute sur ens19.60 et relaie vers dns01 et dns02" "$_m11d_h" \
    'f=$(grep -lsR "dhcp-relay=" /etc/dnsmasq.d/ /etc/dnsmasq.conf 2>/dev/null);
     [ -n "$f" ] && grep -hq "^interface=ens19\.60$" $f
     && grep -hEq "^dhcp-relay=10\.10\.60\.[0-9]+,10\.10\.20\.10" $f
     && grep -hEq "^dhcp-relay=10\.10\.60\.[0-9]+,10\.10\.20\.16" $f
     && systemctl is-active --quiet dnsmasq'
done

# --- Bout en bout : une offre pour un client du VLAN 60 ------------------------------------------------
if remote pxe01 'command -v nmap' >/dev/null 2>&1; then
  check_ssh_output "un DHCPDISCOVER émis sur le VLAN 60 reçoit une offre dans 10.10.60.100-199" pxe01 \
    'IP Offered: 10\.10\.60\.1[0-9][0-9]' \
    'sudo -n nmap --script broadcast-dhcp-discover -e "$(ip -4 -o route show default | awk "{print \$5}")" 2>/dev/null'
else
  skip "offre DHCP sur le VLAN 60" "nmap absent de pxe01 : installe-le pour l'étape 5"
fi

# --- La matrice des flux ---------------------------------------------------------------------------------
_m11d_pf="$(_m11d_contenu_main "$_M11D_PROJET_ANSIBLE" inventories/lab/host_vars/gw01/pare_feu.yml)"
check_output "matrice de la bordure (main) : clients DHCP du VLAN 60 vers le relais" \
  '(PROV|prov|ens19\.60|10\.10\.60).*ports: 67\b' echo "$_m11d_pf"
check_cmd "documentation : matrice-flux.md décrit le DHCP du VLAN 60" \
  grep -qE '(10\.10\.60|VLAN 60).*\b67\b' "${WB_DEPOT:-$HOME/medisphere}/docs/socle/matrice-flux.md"
