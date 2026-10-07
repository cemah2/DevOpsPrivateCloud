# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
#
# check-E34.sh — M06-E34 « Un nouveau service complet en temps limité » (stat01, VMID 2069)
# À lancer à T5, AVANT le retrait. Lecture seule : pve01, NetBox, DNS, HTTPS, clé d'hôte SSH,
# fichiers de stat01 (sudo -n) et de adm01, règles de gw01.

# shellcheck source=_m06-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-production.sh"

title "M06-E34 — Un nouveau service complet en temps limité (stat01)"
require_cmd jq dig curl ssh ssh-keyscan openssl
_m06p_charger

_m06_n=stat01.par1.medisphere.internal

title "Machine (exigence 1)"
check_cmd "VM 2069 « stat01 » démarrée, dans le pool lab" _m06p_vm_jq 2069 '.name == "stat01" and .status == "running" and .pool == "lab"'
check_cmd "VM 2069 étiquetée env-m06 et role-statut" _m06p_vm_etiquettes 2069 env-m06 role-statut
check_cmd "VM 2069 : pas d'étiquette socle (service temporaire)" _m06p_vm_jq 2069 '((.tags // "") | split(";") | index("socle")) == null'
check_cmd "VM 2069 : clone complet" _m06p_clone_complet 2069

title "Adresse et nom (exigences 2 et 3)"
_m06_nb="$(netbox_api "virtualization/virtual-machines/?name=stat01" 2>/dev/null || true)"
_m06_ip="$(jq -r '.results[0].primary_ip4.address // empty' <<<"${_m06_nb:-null}" 2>/dev/null | cut -d/ -f1 || true)"
check_cmd "NetBox : VM stat01, vmid 2069, adresse primaire" \
  jq -e '.count == 1 and ((.results[0].custom_fields.vmid // 0) | tostring) == "2069" and .results[0].primary_ip4 != null' <<<"${_m06_nb:-null}"
check_output "NetBox : adresse dans la plage statique INFRA (10.10.20.10-49)" '^10\.10\.20\.([1-4][0-9])$' printf '%s\n' "${_m06_ip:-}"
for _m06_r in 10.10.20.10 10.10.20.16; do
  check_dns "$_m06_r : $_m06_n → adresse de NetBox" "$_m06_n" A "^${_m06_ip:-aucune}\$" "$_m06_r"
  check_cmd "$_m06_r : réponse validée DNSSEC (ad)" _m06p_ad "$_m06_r" "$_m06_n"
done
check_output "PTR de l'adresse → stat01" "^${_m06_n//./\\.}\\.\$" dig +short +time=3 @10.10.20.10 -x "${_m06_ip:-0.0.0.0}"

title "Accès d'administration (exigence 4)"
check_output "clé d'hôte SSH signée (certificat présenté)" '-cert-v01@openssh\.com' \
  ssh-keyscan -c -T "$WB_TIMEOUT" "$_m06_n"

title "Service et certificat (exigences 5 et 6)"
check_output "page servie en HTTPS (chaîne MédiSphère vérifiée), témoin présent" 'temoin-stat01-m06e34' \
  curl -s --max-time "$WB_TIMEOUT" --cacert "$_M06P_RACINE" "https://$_m06_n/"
check_output "HTTP redirige vers HTTPS" '^30[18]$' \
  curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" "http://$_m06_n/"
check_cmd "certificat valide plus de 10 jours" _m06p_cert_valide "$_m06_n" 443 10
# _m06_duree_max — le certificat servi expire dans 31 jours au plus (échoue si rien n'est servi).
_m06_duree_max() {
  local pem
  pem="$(openssl s_client -connect "$_m06_n:443" -servername "$_m06_n" </dev/null 2>/dev/null | openssl x509 2>/dev/null)" || return 1
  [[ -n "$pem" ]] && ! openssl x509 -noout -checkend 2678400 <<<"$pem" >/dev/null
}
check_cmd "certificat de 30 jours au plus (provisioner ACME)" _m06_duree_max
check_ssh "stat01 : renouvellement à 15 jours (--expires-in 360h) et minuterie active" "admin@$_m06_n" \
  'grep -rqs -- "--expires-in 360h" /etc/systemd/system/cert-renewer@.service /etc/systemd/system/cert-renewer@*.service.d/ && systemctl list-timers --no-legend "cert-renewer@*" | grep -q .'

title "Filtrage, supervision (exigences 7 et 8)"
check_ssh_output "stat01 : filtrage d'entrée local en politique drop" "admin@$_m06_n" 'hook input .*policy drop' \
  'sudo -n nft list table inet filtre_local'
# _m06_gw01_sans_ip — aucune règle de gw01 ne cite l'adresse de stat01 (échoue si adresse inconnue).
_m06_gw01_sans_ip() {
  local r
  [[ -n "${_m06_ip:-}" ]] || return 1
  r="$(remote gw01 "sudo -n nft list ruleset" 2>/dev/null)" || return 1
  [[ -n "$r" ]] && ! grep -qF -- "$_m06_ip" <<<"$r"
}
check_cmd "gw01 : aucune règle propre à stat01" _m06_gw01_sans_ip
check_output "supervision : stat01 dans la configuration de ms-verif-services" "stat01\\.par1\\.medisphere\\.internal:443" \
  cat /usr/local/etc/ms-verif-services.conf
