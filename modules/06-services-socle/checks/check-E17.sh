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
# M06-E17 : HTTP sur 127.0.0.1:8004. À partir de M06-E25, la même socket passe en HTTPS sur l'adresse de
# service (10.10.20.10:8004) : le contrôle suit l'état en place, sans jamais accepter 0.0.0.0.
if remote dns01 'sudo -n ss -Hltn "sport = :8004"' 2>/dev/null | grep -q '10\.10\.20\.10:8004'; then
  _m06o_kea_url="https://10.10.20.10:8004/"
  _m06o_kea_opt="--cacert /usr/local/share/ca-certificates/medisphere-root-ca.crt"
else
  _m06o_kea_url="http://127.0.0.1:8004/"
  _m06o_kea_opt=""
fi
check_ssh_output "API de Kea ($_m06o_kea_url) : 401 sans identifiants" dns01 '^401$' \
  "curl -s -o /dev/null -w '%{http_code}' --max-time 5 $_m06o_kea_opt -X POST -H 'Content-Type: application/json' -d '{\"command\": \"version-get\"}' $_m06o_kea_url"
check_ssh_output "API de Kea : lease4-get-all répond avec les identifiants (hook lease_cmds chargé)" dns01 '"result": *(0|3)' \
  "printf 'user = \"kea-api:%s\"\\n' \"\$(sudo -n cat /etc/kea/kea-api-mdp)\" | curl -s --max-time 5 $_m06o_kea_opt -K - -X POST -H 'Content-Type: application/json' -d '{\"command\": \"lease4-get-all\"}' $_m06o_kea_url"
check_ssh "dns01 : l'API n'écoute ni sur toutes les adresses, ni en clair hors de la boucle locale" dns01 \
  's=$(sudo -n ss -Hltn "sport = :8004"); [ -n "$s" ] && ! grep -Eq "(0\.0\.0\.0|\*|\[::\]):8004" <<<"$s" && { ! grep -q "10\.10\.20\.10:8004" <<<"$s" || sudo -n grep -Eq "\"socket-type\": *\"https\"" /etc/kea/kea-dhcp4.conf; }'
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
    "sudo -n -u pdns pdnsutil metadata get $_m06o_z TSIG-ALLOW-DNSUPDATE"
  # (dns02 s'y ajoute en M06-E25 : son kea-dhcp-ddns écrit chez le primaire.)
  check_ssh_output "PowerDNS : $_m06o_z n'accepte de mises à jour que depuis la boucle locale (et dns02 après M06-E25)" dns01 \
    'ALLOW-DNSUPDATE-FROM = 127\.0\.0\.1(/32)?(, 10\.10\.20\.16(/32)?)?$' \
    "sudo -n -u pdns pdnsutil metadata get $_m06o_z ALLOW-DNSUPDATE-FROM"
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
