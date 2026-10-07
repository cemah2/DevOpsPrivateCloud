# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
#
# check-E25.sh — M06-E25 « Kea en haute disponibilité »
# Lancé depuis adm01. Lecture seule : status-get avec le compte de supervision
# (~/.config/workbook/kea-supervision.env), fichiers de dns01/dns02/gw01 (sudo -n), pve01, GitLab.

# shellcheck source=_m06-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-production.sh"

title "M06-E25 — Kea en haute disponibilité"
require_cmd jq ssh curl openssl
_m06p_charger

title "Paire Kea"
for _m06_h in dns01 dns02; do
  check_ssh "$_m06_h : service isc-kea-dhcp4-server actif et lancé au démarrage" "$_m06_h" \
    'systemctl is-active --quiet isc-kea-dhcp4-server && systemctl is-enabled --quiet isc-kea-dhcp4-server'
done
check_output "adm01 : identité de supervision Kea en 600" '^[4-7]00$' stat -c '%a' "$_M06P_KEA_ENV"
check_cmd "dns01 : rôle primary, état hot-standby, en contact avec dns02" \
  _m06p_kea_ha 10.10.20.10 '.local.role == "primary" and .local.state == "hot-standby" and .remote["in-touch"] == true'
check_cmd "dns02 : rôle standby, état hot-standby, en contact avec dns01" \
  _m06p_kea_ha 10.10.20.16 '.local.role == "standby" and .local.state == "hot-standby" and .remote["in-touch"] == true'
check_output "socket de contrôle : requête sans identifiants refusée (401)" '^401$' \
  curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" --cacert "$_M06P_RACINE" \
  -H 'Content-Type: application/json' --data '{"command": "status-get"}' https://10.10.20.10:8004/

title "TLS"
for _m06_h in dns01 dns02; do
  check_ssh "$_m06_h : pairs HA en HTTPS sur le port 8001, certificats clients exigés" "$_m06_h" \
    'f=/etc/kea/kea-dhcp4.conf; [ "$(sudo -n grep -cE "\"url\": *\"https://10\.10\.20\.(10|16):8001/\"" $f)" -eq 2 ] && sudo -n grep -Eq "\"require-client-certs\": *true" $f'
  check_ssh "$_m06_h : certificat de Kea émis par la PKI interne" "$_m06_h" \
    "sudo -n openssl verify -CAfile $_M06P_RACINE -untrusted /etc/kea/tls/kea.crt /etc/kea/tls/kea.crt"
  check_ssh "$_m06_h : renouvellement automatique du certificat de Kea actif" "$_m06_h" \
    'systemctl is-active --quiet cert-renewer@kea.timer'
done
check_ssh "dns01 : le certificat porte l'adresse IP 10.10.20.10" dns01 \
  'sudo -n openssl x509 -in /etc/kea/tls/kea.crt -noout -ext subjectAltName | grep -q "IP Address:10\.10\.20\.10"'
check_ssh "dns02 : le certificat porte l'adresse IP 10.10.20.16" dns02 \
  'sudo -n openssl x509 -in /etc/kea/tls/kea.crt -noout -ext subjectAltName | grep -q "IP Address:10\.10\.20\.16"'
check_cmd "le socket de contrôle de dns02 présente un certificat valide pour son nom" \
  _m06p_cert_valide dns02.par1.medisphere.internal 8004 1

title "Relais de gw01"
check_ssh "gw01 : relais vers 10.10.20.10 et 10.10.20.16, fichier géré par Ansible" gw01 \
  'f=/etc/dnsmasq.d/relais-dhcp.conf; grep -q "Ansible" $f && grep -Eq "^dhcp-relay=10\.10\.99\.1,10\.10\.20\.10(,|$)" $f && grep -Eq "^dhcp-relay=10\.10\.99\.1,10\.10\.20\.16(,|$)" $f'
check_ssh "gw01 : relais actif" gw01 'systemctl is-active --quiet dnsmasq'
check_ssh_output "gw01 : réponses DHCP de dns02 acceptées (chaîne input)" gw01 \
  'saddr \{[^}]*10\.10\.20\.16[^}]*\}.*dport 67|saddr 10\.10\.20\.16 .*dport 67' \
  "sudo -n nft list chain inet filter input"

title "Test et documentation"
check_cmd "pve01 : une VM 2065 a servi de client de test" _m06p_vm_a_existe 2065
check_cmd "pve01 : la VM 2065 n'existe plus" _m06p_vm_absente 2065
check_cmd "plateforme/medisphere : RB-062 dans docs/socle/runbooks/" _m06p_runbook RB-062
check_cmd "plateforme/ansible : rôle relais_dhcp sur main" _m06p_fichier_existe plateforme/ansible roles/relais_dhcp/tasks/main.yml
check_cmd "plateforme/ansible : un job Molecule kea_ha a réussi sur main" _m06p_job_reussi plateforme/ansible kea_ha
