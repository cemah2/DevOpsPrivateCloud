# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E10.sh — M07-E10 : Répartir un service HTTP avec HAProxy
# À lancer depuis adm01, hap01, srv01 et srv02 démarrées. Lecture seule.
# srv01/srv02 : rôle nginx_web de M07-E08 (en-tête X-Serveur, point de santé /sante).

# shellcheck source=_m07-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-operationnel.sh"

title "M07-E10 — Répartir un service HTTP avec HAProxy"
require_cmd jq curl

# --- La VM -------------------------------------------------------------------------------------------
_m07o_conf="$(_m07o_vm_config 2079)"
check_output "VM 2079 : nommée hap01" '^name: hap01$' echo "$_m07o_conf"
check_output "VM 2079 : étiquette env-m07" '^tags:.*env-m07' echo "$_m07o_conf"
check_output "VM 2079 : carte sur vsandbox" '^net0:.*bridge=vsandbox' echo "$_m07o_conf"
check_output "plateforme/infra : VMID 2079 déclaré dans envs/m07-maquette (main)" 'vmid[[:space:]]*=[[:space:]]*2079' \
  _m07o_contenu_dossier "$_M07O_PROJET_INFRA" envs/m07-maquette '\.tf$'

# --- HAProxy sur hap01 ------------------------------------------------------------------------------
check_ssh "hap01 : HAProxy 3.2 installé depuis haproxy.debian.net" hap01 \
  'haproxy -v | grep -q "^HAProxy version 3\.2\." && apt-cache policy haproxy | grep -A1 "^ \*\*\*" | grep -q haproxy.debian.net'
check_ssh "hap01 : service haproxy actif et activé" hap01 \
  'systemctl is-active --quiet haproxy && systemctl is-enabled --quiet haproxy'
check_ssh "hap01 : configuration valide (haproxy -c)" hap01 \
  'sudo -n haproxy -c -f /etc/haproxy/haproxy.cfg >/dev/null 2>&1'
check_ssh "hap01 : contrôle de santé HTTP sur /sante configuré" hap01 \
  'sudo -n grep -Eq "^[[:space:]]*option httpchk" /etc/haproxy/haproxy.cfg && sudo -n grep -Eq "^[[:space:]]*http-check send .*uri /sante" /etc/haproxy/haproxy.cfg'
check_ssh "hap01 : page de statistiques sur la seule boucle locale (8404)" hap01 \
  'sudo -n ss -Hltn "sport = :8404" | grep -q "127\.0\.0\.1:8404" && ! sudo -n ss -Hltn "sport = :8404" | grep -Eq "(0\.0\.0\.0|\*|\[::\]):8404"'

_m07o_stat="$(_m07o_haproxy_stat hap01)"
for _m07o_s in srv01 srv02; do
  check_output "hap01 : $_m07o_s est UP dans be_web" '^UP' _m07o_etat_serveur "$_m07o_stat" be_web "$_m07o_s"
done
check_output "hap01 : le dernier contrôle des serveurs est de niveau 7 (L7OK)" 'L7OK' \
  awk -F, '$1 == "be_web" && $2 ~ /^srv0[12]$/ {print $37}' <<<"$_m07o_stat"

# --- Le service rendu ---------------------------------------------------------------------------------
_m07o_noms="$(for _i in 1 2 3 4 5 6; do
  curl -s -o /dev/null -D - --max-time "$WB_TIMEOUT" "http://hap01.$_M07O_ZONE/" 2>/dev/null \
    | sed -n 's/^[Xx]-[Ss]erveur: *\([a-z0-9-]*\).*/\1/p' || true
done | sort -u | tr '\n' ' ' || true)"
check_output "six requêtes par hap01 : réponses de srv01 ET de srv02 (vu : ${_m07o_noms:-aucune})" \
  'srv01 srv02' echo "$_m07o_noms"
for _m07o_s in srv01 srv02; do
  check_ssh "$_m07o_s : /sante répond 200" "$_m07o_s" \
    '[ "$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1/sante)" = 200 ]'
done

check_cmd "plateforme/ansible : rôle haproxy sur main" \
  _m07o_fichier_main "$_M07O_PROJET_ANSIBLE" roles/haproxy/tasks/main.yml
check_cmd "plateforme/ansible : scénario Molecule haproxy sur main" \
  _m07o_fichier_main "$_M07O_PROJET_ANSIBLE" molecule/haproxy/molecule.yml
