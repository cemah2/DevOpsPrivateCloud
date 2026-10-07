# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E06.sh — M06-E06 : PowerDNS Authoritative sur dns01
# À lancer depuis adm01. Lecture seule : questions DNS au port 5300 de dns01, état de dns01
# en SSH, API PowerDNS en GET (clé de ~/.config/workbook/powerdns-api.env), API GitLab en GET.

# shellcheck source=_m06-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-decouverte.sh"

title "M06-E06 — PowerDNS Authoritative sur dns01"
require_cmd dig curl jq

_m06d_e06_auth="10.10.20.10:5300"

# --- 1. Installation ---------------------------------------------------------------------------
check_ssh "dns01 : service pdns actif et lancé au démarrage" dns01 \
  'systemctl is-active --quiet pdns && systemctl is-enabled --quiet pdns'
check_ssh_output "dns01 : PowerDNS Authoritative 5.0 du dépôt officiel" dns01 '^5\.0\.[0-9]+-[0-9]+pdns' \
  'dpkg-query -W -f="\${Version}" pdns-server'
check_ssh_output "dns01 : backend gsqlite3, et lui seul" dns01 '^gsqlite3$' \
  'sudo -n grep -rhE "^[[:space:]]*launch\+?=" /etc/powerdns/pdns.conf /etc/powerdns/pdns.d/ | sed -E "s/.*=[[:space:]]*//" | grep -v "^$" | tr "\n" " " | sed "s/ $//"'
check_ssh "dns01 : base SQLite et fichiers WAL appartenant au compte pdns" dns01 \
  'f=$(sudo -n grep -rhE "^gsqlite3-database=" /etc/powerdns/pdns.d/ | cut -d= -f2); [ -n "$f" ] && ! sudo -n find "$(dirname "$f")" -maxdepth 1 -name "$(basename "$f")*" ! -user pdns | grep -q .'
check_ssh "dns01 : configuration (clé d'API) illisible par les autres comptes" dns01 \
  '! sudo -n find /etc/powerdns/pdns.d -type f -perm /o+r | grep -q .'

# --- 2. Écoute : jamais le port 53 -------------------------------------------------------------
check_ssh_output "dns01 : pdns écoute sur 127.0.0.1:5300 et 10.10.20.10:5300" dns01 '^2$' \
  'sudo -n ss -Hlnup "sport = :5300" | grep pdns_server | awk "{print \$4}" | sort -u | grep -Ec "^(127\.0\.0\.1|10\.10\.20\.10):5300$"'
check_ssh "dns01 : pdns n'écoute pas sur le port 53" dns01 '! sudo -n ss -Hlnup "sport = :53" | grep -q pdns_server'

# --- 3. Les zones, servies avec autorité -------------------------------------------------------
for _m06d_e06_z in medisphere.internal par1.medisphere.internal par2.medisphere.internal 10.10.in-addr.arpa 20.10.in-addr.arpa; do
  check_output "Zone $_m06d_e06_z : SOA servi avec autorité (aa) par dns01:5300" 'status: NOERROR.*flags:[^;]* aa' \
    bash -c 'dig +norecurse +time=3 -p 5300 @10.10.20.10 "$1" SOA | tr "\n" " "' _ "$_m06d_e06_z"
done
check_output "SOA de par1 : serveur primaire dns01, numéro de série AAAAMMJJnn" \
  '^dns01\.par1\.medisphere\.internal\. [^ ]+ 20[0-9]{8} ' _m06d_dig "$_m06d_e06_auth" par1.medisphere.internal SOA

# --- 4. Le contenu : mêmes réponses que le DNS en service --------------------------------------
for _m06d_e06_v in dns01:10.10.20.10 gw01:10.10.10.1 adm01:10.10.10.10 ca01:10.10.20.11 git01:10.10.20.12 \
  nbx01:10.10.20.13 s3-01:10.10.20.14 runner01:10.10.20.15; do
  _m06d_e06_n="${_m06d_e06_v%%:*}.par1.medisphere.internal"
  _m06d_e06_ip="${_m06d_e06_v##*:}"
  check_output "A $_m06d_e06_n → $_m06d_e06_ip" "^${_m06d_e06_ip//./\\.}$" _m06d_dig "$_m06d_e06_auth" "$_m06d_e06_n" A
  check_output "PTR $_m06d_e06_ip → $_m06d_e06_n" "^${_m06d_e06_n//./\\.}\.$" _m06d_dig "$_m06d_e06_auth" -x "$_m06d_e06_ip"
done
check_output "A pbs01.par2.medisphere.internal → 10.20.10.10" '^10\.20\.10\.10$' _m06d_dig "$_m06d_e06_auth" pbs01.par2.medisphere.internal A
check_output "PTR 10.10.20.1 (passerelle INFRA) → gw01" '^gw01\.par1\.medisphere\.internal\.$' _m06d_dig "$_m06d_e06_auth" -x 10.10.20.1
check_output "Nom inexistant de par1 : NXDOMAIN avec autorité" 'status: NXDOMAIN.*flags:[^;]* aa' \
  bash -c 'dig +norecurse +time=3 -p 5300 @10.10.20.10 nexistepas.par1.medisphere.internal A | tr "\n" " "'
check_output "Question hors de ses zones : refusée (un serveur faisant autorité ne fait pas de récursion)" 'status: REFUSED' \
  _m06d_dig_complet "$_m06d_e06_auth" +norecurse deb.debian.org A

# --- 5. L'API ------------------------------------------------------------------------------------------
# La copie de travail de la clé sur adm01 arrive en M06-E14 : contrôle fait seulement si elle existe.
if [[ -e "$_M06D_CFG/powerdns-api.env" ]]; then
  check_output "API : répond avec la clé de powerdns-api.env (200)" '^200$' _m06d_pdns_api zones
else
  skip "API : réponse avec la clé" "powerdns-api.env n'existe qu'à partir de M06-E14"
fi
check_http "API : refuse sans clé (401)" "http://10.10.20.10:8081/api/v1/servers/localhost/zones" 401 --noproxy '*'
# Un hôte du socle hors de webserver-allow-from (git01) ne doit pas obtenir de réponse de l'API.
check_ssh "API : fermée aux hôtes non autorisés (essai depuis git01)" git01 \
  'c=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 --noproxy "*" http://10.10.20.10:8081/api/v1/servers/localhost); [ "$c" != 401 ] && [ "$c" != 200 ]'

# --- 6. Le code ----------------------------------------------------------------------------------------
check_cmd "plateforme/ansible (main) : rôle powerdns_auth" _m06d_fichier_main roles/powerdns_auth/tasks/main.yml
check_cmd "plateforme/ansible (main) : scénario Molecule powerdns_auth" _m06d_fichier_main molecule/powerdns_auth/molecule.yml
