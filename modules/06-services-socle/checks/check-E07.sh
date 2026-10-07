# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E07.sh — M06-E07 : PowerDNS Recursor et zones relayées
# À lancer depuis adm01. Lecture seule : questions DNS au Recursor de dns01 (port d'essai 5301,
# ou 53 si la bascule de M06-E08 est faite), état de dns01 en SSH.

# shellcheck source=_m06-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-decouverte.sh"

title "M06-E07 — PowerDNS Recursor et zones relayées"
require_cmd dig

# Port du Recursor : 5301 pendant l'essai, 53 après la bascule (M06-E08). On suit celui qui répond.
_m06d_e07_port=5301
if remote dns01 'ss -Hlnup "sport = :53" | grep -q pdns_recursor' >/dev/null 2>&1; then
  _m06d_e07_port=53
fi
_m06d_e07_rec="10.10.20.10:$_m06d_e07_port"

# --- 1. Installation et configuration --------------------------------------------------------
check_ssh "dns01 : service pdns-recursor actif et lancé au démarrage" dns01 \
  'systemctl is-active --quiet pdns-recursor && systemctl is-enabled --quiet pdns-recursor'
check_ssh_output "dns01 : PowerDNS Recursor 5.4 du dépôt officiel" dns01 '^5\.4\.[0-9]+-[0-9]+pdns' \
  'dpkg-query -W -f="\${Version}" pdns-recursor'
check_ssh "dns01 : configuration au format YAML (/etc/powerdns/recursor.yml)" dns01 \
  'sudo -n test -s /etc/powerdns/recursor.yml && sudo -n pdns_recursor --config-dir=/etc/powerdns --config=check >/dev/null 2>&1'
check_ssh_output "dns01 : le Recursor écoute sur 127.0.0.1 et 10.10.20.10 (port $_m06d_e07_port), pas ailleurs" dns01 '^2$' \
  "ss -Hlnup | grep pdns_recursor | awk '{print \$4}' | sort -u | grep -Ec '^(127\.0\.0\.1|10\.10\.20\.10):$_m06d_e07_port\$'"
check_ssh "dns01 : aucune écoute du Recursor sur toutes les adresses" dns01 \
  '! ss -Hlnup | grep pdns_recursor | grep -Eq "(0\.0\.0\.0|\*|\[::\]):"'

# --- 2. Zones internes relayées vers l'autoritaire ------------------------------------------------
check_output "Nom interne résolu par le Recursor ($_m06d_e07_rec)" '^10\.10\.20\.12$' \
  _m06d_dig "$_m06d_e07_rec" git01.par1.medisphere.internal A
check_output "Inverse interne résolu par le Recursor" '^git01\.par1\.medisphere\.internal\.$' \
  _m06d_dig "$_m06d_e07_rec" -x 10.10.20.12
check_output "Nom de PAR2 résolu" '^10\.20\.10\.10$' _m06d_dig "$_m06d_e07_rec" pbs01.par2.medisphere.internal A
check_output "Nom interne inexistant : NXDOMAIN (et non SERVFAIL : la zone interne n'est pas « bogus »)" 'status: NXDOMAIN' \
  _m06d_dig_complet "$_m06d_e07_rec" nexistepas.par1.medisphere.internal A
check_output "Sous medisphere.internal, une faute de frappe reste interne : NXDOMAIN" 'status: NXDOMAIN' \
  _m06d_dig_complet "$_m06d_e07_rec" nexistepas.medisphere.internal A
check_output "Réponse interne non validée par DNSSEC (pas de drapeau ad, ancre négative)" 'flags: qr rd ra;' \
  _m06d_dig_complet "$_m06d_e07_rec" +dnssec git01.par1.medisphere.internal A

# --- 3. Internet et DNSSEC ----------------------------------------------------------------------------
check_output "Nom Internet résolu" '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' _m06d_dig "$_m06d_e07_rec" deb.debian.org A
check_output "Nom Internet signé : réponse validée (drapeau ad)" 'flags:[^;]* ad[ ;]' \
  _m06d_dig_complet "$_m06d_e07_rec" +dnssec www.isc.org A
# Mode « validate » : même un client qui ne demande rien (ni AD, ni DO) reçoit SERVFAIL pour une
# réponse « bogus ». En mode « process », il recevrait la réponse falsifiée.
check_output "Signature invalide : SERVFAIL même pour un client qui ne demande pas de validation" 'status: SERVFAIL' \
  _m06d_dig_complet "$_m06d_e07_rec" +noadflag dnssec-failed.org A

# --- 4. Le code ------------------------------------------------------------------------------------------
check_cmd "plateforme/ansible (main) : rôle powerdns_recursor" _m06d_fichier_main roles/powerdns_recursor/tasks/main.yml
check_cmd "plateforme/ansible (main) : scénario Molecule powerdns_recursor" _m06d_fichier_main molecule/powerdns_recursor/molecule.yml
