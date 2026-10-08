# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant ou par bash -c
#
# check-E34.sh — M07-E34 « Publier un nouveau service en temps limité » (agenda-demo)
# À lancer à T5, AVANT le retrait. Lecture seule : DNS, HTTPS (GET/HEAD) depuis adm01 et depuis
# pve01 (LAN maison, par la VIP WAN ; la racine PUBLIQUE de la PKI est passée à curl par l'entrée
# standard, rien n'est écrit sur pve01), lb01/lb02 (admin + sudo -n), copies de travail.

# shellcheck source=_m07-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-production.sh"

title "M07-E34 — Publier un nouveau service en temps limité (agenda-demo)"
require_cmd dig curl openssl ssh
_m07_n="agenda-demo.$_M07P_ZONE"
_m07_url="https://$_m07_n/"

title "Nom et service (exigences 1, 2, 5)"
check_dns "$_m07_n mène à la VIP des répartiteurs (10.10.70.200)" "$_m07_n" A '^10\.10\.70\.200$' 10.10.20.10
check_dns "$_m07_n : même réponse sur dns02" "$_m07_n" A '^10\.10\.70\.200$' 10.10.20.16
check_output "page servie en HTTPS (chaîne vérifiée) par srv01 ou srv02" 'srv0[12]' \
  curl -s --max-time 10 --cacert "$_M07P_RACINE" "$_m07_url"
check_output "en-tête X-MediSphere-Service: agenda-demo" '^agenda-demo$' _m07p_entete "$_m07_url" X-MediSphere-Service
check_output "HSTS présent" 'max-age=[0-9]+' _m07p_entete "$_m07_url" Strict-Transport-Security
check_output "HTTP redirigé vers HTTPS" '^30[18]$' \
  bash -c 'curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://$1/" || true' _ "$_m07_n"

title "Redondance et certificats (exigences 3, 4)"
for _m07_h in lb01 lb02; do
  check_cmd "$_m07_h : srv01 UP dans be_agenda_demo" _m07p_serveur_up "$_m07_h" be_agenda_demo srv01
  check_cmd "$_m07_h : srv02 UP dans be_agenda_demo" _m07p_serveur_up "$_m07_h" be_agenda_demo srv02
  check_ssh "$_m07_h : contrôle de santé HTTP applicatif sur be_agenda_demo" "$_m07_h" \
    'sudo -n awk "/^backend be_agenda_demo/ {b=1; next} /^(backend|frontend|listen) / {b=0} b && /http-check send/ {ok=1} END {exit !ok}" /etc/haproxy/haproxy.cfg'
  # Le certificat se lit sur l'écouteur de la VIP… que seul l'actif porte : on le lit dans le fichier.
  check_ssh "$_m07_h : certificat ACME agenda-demo présent (≤ 31 jours, émis par l'intermédiaire)" "$_m07_h" '
    f=$(sudo -n find /etc/haproxy/certs -maxdepth 1 -type f 2>/dev/null | while read -r c; do sudo -n openssl x509 -in "$c" -noout -ext subjectAltName 2>/dev/null | grep -q "agenda-demo.par1.medisphere.internal" && echo "$c"; done | head -n 1)
    [ -n "$f" ] || exit 1
    p=$(sudo -n openssl x509 -in "$f") && openssl x509 -noout -issuer <<<"$p" | grep -q "Intermediate CA" &&
    d=$(( $(date -d "$(openssl x509 -noout -enddate <<<"$p" | cut -d= -f2)" +%s) - $(date -d "$(openssl x509 -noout -startdate <<<"$p" | cut -d= -f2)" +%s) )) &&
    [ "$d" -le 2678400 ] && openssl x509 -noout -checkend 864000 <<<"$p" >/dev/null'
done
check_cmd "certificat servi par la VIP valide pour le nom (plus de 10 jours)" _m07p_cert_ok "$_m07_n" 10.10.70.200

title "Accès (exigence 6)"
if [[ -n "${WB_GW_WAN_VIP:-}" ]]; then
  # _m07_depuis_lan — code HTTP vu depuis pve01 (LAN maison) par la redirection de la VIP WAN.
  _m07_depuis_lan() {
    remote "$WB_PVE_HOST" "curl -s -o /dev/null -w '%{http_code}' --max-time 10 --cacert /dev/stdin --resolve $_m07_n:443:$WB_GW_WAN_VIP https://$_m07_n/" \
      <"$_M07P_RACINE" 2>/dev/null || true
  }
  check_output "depuis le LAN maison (VIP WAN) : 403" '^403$' _m07_depuis_lan
else
  skip "refus depuis le LAN maison" "WB_GW_WAN_VIP non renseignée dans lab/lab.env"
fi

title "Flux et supervision (exigences 7, 8)"
check_cmd "matrice : un flux référencé M07-E34 (répartiteurs → srv01, srv02)" bash -c \
  'grep -q "M07-E34" "$1/inventories/lab/group_vars/role_routeur/pare_feu.yml"' _ "$_M07P_ANSIBLE"
check_output "supervision : agenda-demo dans la configuration de ms-verif-reseau" 'agenda-demo\.par1\.medisphere\.internal' \
  cat /usr/local/etc/ms-verif-reseau.conf
