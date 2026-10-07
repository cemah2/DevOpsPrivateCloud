# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E17.sh — M06-E17 : Kea : API de contrôle et mise à jour dynamique du DNS
# À lancer depuis adm01, sbx66 (2066) démarrée. Lecture seule : aucune mise à jour DNS n'est
# tentée (même refusée, ce serait une écriture si la protection manquait).

# shellcheck source=_m06-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-operationnel.sh"

title "M06-E17 — Kea : API de contrôle et mise à jour dynamique du DNS"
require_cmd jq dig

_m06o_pvehote="${WB_PVE_HOST:-pve01}"

# --- API de contrôle -------------------------------------------------------------------------------------
check_ssh_output "API de Kea (127.0.0.1:8004) : 401 sans identifiants" dns01 '^401$' \
  'curl -s -o /dev/null -w "%{http_code}" --max-time 5 -X POST -H "Content-Type: application/json" -d "{\"command\": \"version-get\"}" http://127.0.0.1:8004/'
check_ssh_output "API de Kea : lease4-get-all répond avec les identifiants (hook lease_cmds chargé)" dns01 '"result": *(0|3)' \
  'printf "user = \"kea-api:%s\"\n" "$(sudo -n cat /etc/kea/kea-api-mdp)" | curl -s --max-time 5 -K - -X POST -H "Content-Type: application/json" -d "{\"command\": \"lease4-get-all\"}" http://127.0.0.1:8004/'
check_ssh "dns01 : l'API n'écoute que sur la boucle locale" dns01 \
  'sudo -n ss -Hltnp "sport = :8004" | grep -q "127.0.0.1:8004" && ! sudo -n ss -Hltn "sport = :8004" | grep -Eq "(0\.0\.0\.0|\*|10\.10\.20\.10):8004"'
check_ssh "dns01 : aucun mot de passe en clair dans kea-dhcp4.conf (password-file)" dns01 \
  'sudo -n grep -q "password-file" /etc/kea/kea-dhcp4.conf && ! sudo -n grep -Eq "\"password\"[[:space:]]*:" /etc/kea/kea-dhcp4.conf'

# --- kea-dhcp-ddns ------------------------------------------------------------------------------------------
check_ssh "dns01 : isc-kea-dhcp-ddns-server actif et activé" dns01 \
  'systemctl is-active --quiet isc-kea-dhcp-ddns-server && systemctl is-enabled --quiet isc-kea-dhcp-ddns-server'
check_ssh "dns01 : secret TSIG dans un fichier en 640, pas dans kea-dhcp-ddns.conf" dns01 \
  'f="$(sudo -n sed -nE "s/.*\"secret-file\"[[:space:]]*:[[:space:]]*\"([^\"]+)\".*/\1/p" /etc/kea/kea-dhcp-ddns.conf | head -n 1)";
   [ -n "$f" ] && [ "$(sudo -n stat -c %a "$f")" = 640 ] && ! sudo -n grep -Eq "\"secret\"[[:space:]]*:" /etc/kea/kea-dhcp-ddns.conf'
check_ssh "dns01 : kea-dhcp4 transmet les baux à kea-dhcp-ddns (enable-updates)" dns01 \
  'sudo -n grep -Eq "\"enable-updates\"[[:space:]]*:[[:space:]]*true" /etc/kea/kea-dhcp4.conf'

# --- Autorisations côté PowerDNS ----------------------------------------------------------------------------
check_ssh "PowerDNS : mises à jour dynamiques activées (dnsupdate=yes)" dns01 \
  'sudo -n grep -RhsE "^[[:space:]]*dnsupdate[[:space:]]*=[[:space:]]*yes" /etc/powerdns/pdns.conf /etc/powerdns/pdns.d/ | grep -q .'
for _m06o_z in par1.medisphere.internal 10.10.in-addr.arpa; do
  check_ssh_output "PowerDNS : $_m06o_z n'accepte que la clé ddns-kea" dns01 'TSIG-ALLOW-DNSUPDATE.*ddns-kea' \
    "sudo -n pdnsutil metadata get $_m06o_z TSIG-ALLOW-DNSUPDATE"
  check_ssh_output "PowerDNS : $_m06o_z n'accepte de mises à jour que depuis la boucle locale" dns01 'ALLOW-DNSUPDATE-FROM = 127\.0\.0\.1(/32)?$' \
    "sudo -n pdnsutil metadata get $_m06o_z ALLOW-DNSUPDATE-FROM"
done

# --- Le service rendu ---------------------------------------------------------------------------------------
if remote "$_m06o_pvehote" 'qm status 2066 | grep -q running' >/dev/null 2>&1; then
  _m06o_ip="$(remote "$_m06o_pvehote" 'qm guest cmd 2066 network-get-interfaces' 2>/dev/null \
    | jq -r '[.[] | select(.name != "lo") | .["ip-addresses"][]? | select(.["ip-address-type"] == "ipv4") | .["ip-address"]][0] // empty' || true)"
  _m06o_nom="$(remote "$_m06o_pvehote" 'qm guest cmd 2066 get-host-name' 2>/dev/null | jq -r '.["host-name"] // empty' || true)"
  check_output "sbx66 : ${_m06o_nom:-?}.$_M06O_ZONE → ${_m06o_ip:-?} (A publié par Kea)" "^${_m06o_ip//./\\.}\$" \
    _m06o_dig "${_m06o_nom:-sbx66}.$_M06O_ZONE"
  check_output "sbx66 : PTR de ${_m06o_ip:-?} publié par Kea" "^${_m06o_nom:-sbx66}\.par1\.medisphere\.internal\.\$" \
    dig +short +time=3 @10.10.20.10 -x "${_m06o_ip:-0.0.0.0}"
  check_output "sbx66 : enregistrement DHCID présent (résolution de conflits de Kea)" '.' \
    _m06o_dig "${_m06o_nom:-sbx66}.$_M06O_ZONE" DHCID
else
  skip "noms publiés pour sbx66" "VM 2066 arrêtée ou absente"
fi
# Le socle n'a pas été détourné par un client (étape 7).
check_output "dns01.$_M06O_ZONE pointe toujours vers 10.10.20.10" '^10\.10\.20\.10$' _m06o_dig "dns01.$_M06O_ZONE"
