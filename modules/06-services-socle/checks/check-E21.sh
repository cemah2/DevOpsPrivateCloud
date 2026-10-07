# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E21.sh — M06-E21 : Une heure de référence fiable et authentifiée
# À lancer depuis adm01. Lecture seule (chronyc, ss, openssl, nft en lecture).

# shellcheck source=_m06-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-operationnel.sh"

title "M06-E21 — Une heure de référence fiable et authentifiée"
require_cmd openssl

# --- gw01 : sources NTS -----------------------------------------------------------------------------
check_ssh "gw01 : chrony.conf ne déclare que des sources NTS (aucune « pool », aucun « server » sans nts)" gw01 \
  '! grep -Ev "^[[:space:]]*(#|$)" /etc/chrony/chrony.conf /etc/chrony/conf.d/*.conf /etc/chrony/sources.d/*.sources 2>/dev/null \
     | grep -E "^[^:]*:[[:space:]]*(pool|server|peer)[[:space:]]" | grep -qvE "[[:space:]]nts([[:space:]]|$)"'
check_ssh_output "gw01 : au moins deux sources authentifiées par NTS" gw01 '^[2-9]$|^[1-9][0-9]+$' \
  'chronyc -n authdata | grep -cE "[[:space:]]NTS[[:space:]]"'
check_ssh "gw01 : horloge synchronisée (Leap status Normal)" gw01 \
  'chronyc tracking | grep -q "Leap status *: Normal"'
check_ssh "gw01 : chronyd écoute NTS-KE (TCP 4460)" gw01 \
  'sudo -n ss -Hltnp "sport = :4460" | grep -q chronyd'
check_ssh "gw01 : configuration de chrony gérée par Ansible" gw01 \
  'grep -qi "ansible" /etc/chrony/chrony.conf && [ ! -e /etc/chrony/conf.d/10-serveur-lab.conf ]'

# --- Certificat NTS de gw01, vu par un client du VLAN INFRA ---------------------------------------------------
# NTS-KE exige le protocole applicatif (ALPN) « ntske/1 ».
_m06o_x509="$(_m06o_cert_tls 10.10.20.1 4460 -alpn ntske/1)"
check_output "certificat NTS de gw01 émis par « MédiSphère Intermediate CA »" 'issuer=.*Interm' echo "$_m06o_x509"
check_output "certificat NTS : contient l'adresse de passerelle 10.10.20.1" 'IP Address:10\.10\.20\.1(,|$)' echo "$_m06o_x509"
check_output "certificat NTS : contient l'adresse de passerelle 10.10.10.1" 'IP Address:10\.10\.10\.1(,|$)' echo "$_m06o_x509"
check_ssh "gw01 : renouvellement du certificat NTS planifié (cert-renewer@)" gw01 \
  'systemctl list-units --type=timer --state=active --no-legend "cert-renewer@*" | grep -q cert-renewer@'

# --- Clients ----------------------------------------------------------------------------------------------------
check_cmd "adm01 : sa passerelle (10.10.10.1) authentifiée par NTS" \
  bash -c 'chronyc -n authdata | grep -E "^10\.10\.10\.1[[:space:]]" | grep -q " NTS "'
check_ssh "dns01 : sa passerelle (10.10.20.1) authentifiée par NTS" dns01 \
  'chronyc -n authdata | grep -E "^10\.10\.20\.1[[:space:]]" | grep -q " NTS "'
check_ssh "dns01 : horloge synchronisée sur 10.10.20.1" dns01 \
  'chronyc -n tracking | grep -q "Reference ID.*(10\.10\.20\.1)"'

# --- Pare-feu --------------------------------------------------------------------------------------------------
check_ssh "gw01 : NTS-KE (TCP 4460) accepté en entrée depuis le lab" gw01 \
  'sudo -n nft list chain inet filter input | grep -E "tcp dport 4460" | grep -q accept'
check_ssh "gw01 : port 80 en entrée réservé à ca01 (défi ACME)" gw01 \
  'r="$(sudo -n nft list chain inet filter input | grep -E "tcp dport 80 ")"; [ -n "$r" ] && ! grep -vq "10\.10\.20\.11" <<<"$r"'
