# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
#
# check-E24.sh — M06-E24 « DNS secondaire dns02 : transferts de zone et TSIG »
# Lancé depuis adm01. Lecture seule : pve01 (root), dns01/dns02/runner01/gw01 (admin + sudo -n),
# API NetBox (jeton des checks), API GitLab (jeton des checks), requêtes DNS.

# shellcheck source=_m06-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-production.sh"

title "M06-E24 — DNS secondaire dns02 : transferts de zone et TSIG"
require_cmd dig jq ssh curl
_m06p_charger

title "La VM dns02 (1008)"
check_cmd "VM 1008 « dns02 » démarrée" _m06p_vm_jq 1008 '.name == "dns02" and .status == "running"'
check_cmd "VM 1008 dans le pool lab" _m06p_vm_jq 1008 '.pool == "lab"'
check_cmd "VM 1008 étiquetée socle et role-dns" _m06p_vm_etiquettes 1008 socle role-dns
check_ssh "VM 1008 : démarrage automatique avec l'hôte" "$WB_PVE_HOST" "qm config 1008 | grep -q '^onboot: 1'"
check_cmd "VM 1008 : clone complet (aucun disque lié à un template)" _m06p_clone_complet 1008

title "Source de vérité (NetBox) et nommage"
_m06_nb="$(netbox_api "virtualization/virtual-machines/?name=dns02" 2>/dev/null || true)"
check_cmd "NetBox : une VM dns02, vmid 1008" \
  jq -e '.count == 1 and ((.results[0].custom_fields.vmid // 0) | tostring) == "1008"' <<<"${_m06_nb:-null}"
check_cmd "NetBox : adresse primaire 10.10.20.16/24" \
  jq -e '.results[0].primary_ip4.address == "10.10.20.16/24"' <<<"${_m06_nb:-null}"
check_dns "DNS : dns02.par1.medisphere.internal → 10.10.20.16" dns02.par1.medisphere.internal A '^10\.10\.20\.16$' 10.10.20.10
check_dns "DNS : PTR de 10.10.20.16 → dns02" 16.20.10.10.in-addr.arpa PTR '^dns02\.par1\.medisphere\.internal\.$' 10.10.20.10

title "Réplication des zones"
for _m06_z in "${_M06P_ZONES[@]}"; do
  check_cmd "$_m06_z : même numéro de série sur dns01 et dns02 (port 5300)" _m06p_series_egales "$_m06_z"
  check_output "$_m06_z : les NS citent dns02" '^dns02\.par1\.medisphere\.internal\.$' \
    dig +short +norecurse +time=3 @10.10.20.10 -p 5300 "$_m06_z" NS
done
check_ssh "dns01 : les quatre zones sont de type primaire" dns01 \
  'l=$(sudo -n -u pdns pdnsutil zone list-all primary 2>/dev/null | sed "s/\.$//"); for z in par1.medisphere.internal par2.medisphere.internal 10.10.in-addr.arpa 20.10.in-addr.arpa; do grep -qx "$z" <<<"$l" || exit 1; done'
check_ssh "dns02 : les quatre zones sont de type secondaire" dns02 \
  'l=$(sudo -n -u pdns pdnsutil zone list-all secondary 2>/dev/null | sed "s/\.$//"); for z in par1.medisphere.internal par2.medisphere.internal 10.10.in-addr.arpa 20.10.in-addr.arpa; do grep -qx "$z" <<<"$l" || exit 1; done'

title "TSIG et contrôle des transferts"
check_ssh "dns01 : la clé axfr-par1 autorise le transfert des quatre zones" dns01 \
  'for z in par1.medisphere.internal par2.medisphere.internal 10.10.in-addr.arpa 20.10.in-addr.arpa; do sudo -n -u pdns pdnsutil metadata get "$z" TSIG-ALLOW-AXFR 2>/dev/null | grep -q "axfr-par1" || exit 1; done'
check_ssh "dns02 : les quatre zones sont transférées avec la clé axfr-par1" dns02 \
  'for z in par1.medisphere.internal par2.medisphere.internal 10.10.in-addr.arpa 20.10.in-addr.arpa; do sudo -n -u pdns pdnsutil metadata get "$z" AXFR-MASTER-TSIG 2>/dev/null | grep -q "axfr-par1" || exit 1; done'
# Le serveur doit RÉPONDRE (un SOA) pour que le refus de l'AXFR signifie quelque chose.
check_cmd "dns01 : le serveur faisant autorité répond à adm01 (5300)" _m06p_serie 10.10.20.10 par1.medisphere.internal
check_cmd "dns01 : AXFR sans clé depuis adm01 refusé" bash -c \
  'o=$(dig +time=3 +tries=1 @10.10.20.10 -p 5300 par1.medisphere.internal AXFR 2>&1); [[ -n "$(dig +short +time=3 @10.10.20.10 -p 5300 par1.medisphere.internal SOA)" ]] && ! grep -Eq "[[:space:]]IN[[:space:]]+A[[:space:]]" <<<"$o"'

title "Récurseur de dns02 et clients"
check_dns "dns02 : résout un nom interne" git01.par1.medisphere.internal A '^10\.10\.20\.12$' 10.10.20.16
check_dns "dns02 : résout un nom Internet" deb.debian.org A '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' 10.10.20.16
check_cmd "adm01 : connaît le résolveur 10.10.20.16" bash -c \
  '{ resolvectl dns 2>/dev/null; cat /etc/resolv.conf; } | grep -q "10\.10\.20\.16"'
check_ssh "runner01 : connaît le résolveur 10.10.20.16" runner01 \
  '{ resolvectl dns 2>/dev/null; cat /etc/resolv.conf; } | grep -q "10\.10\.20\.16"'
check_ssh_output "gw01 : les VLANs routés peuvent interroger dns02 (règle de transit vers le port 53)" gw01 \
  'daddr \{[^}]*10\.10\.20\.16[^}]*\}.*dport 53|daddr 10\.10\.20\.16 .*dport 53' \
  "sudo -n nft list chain inet filter forward"

title "Code"
check_cmd "plateforme/ansible : scénario Molecule powerdns_replication sur main" \
  _m06p_fichier_existe plateforme/ansible molecule/powerdns_replication/molecule.yml
check_cmd "plateforme/ansible : un job Molecule powerdns_replication a réussi sur main" \
  _m06p_job_reussi plateforme/ansible powerdns_replication
