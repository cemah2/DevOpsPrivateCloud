# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
#
# check-E27.sh — M06-E27 « La PKI en production : durées de vie, renouvellement, révocation »
# Lancé depuis adm01. Lecture seule : ca.json lu sur ca01 (sudo -n), CRL publique, certificats
# présentés par les services, unités systemd des hôtes, dépôt de documentation.

# shellcheck source=_m06-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-production.sh"

title "M06-E27 — La PKI en production : durées de vie, renouvellement, révocation"
require_cmd jq ssh curl openssl

_m06_cajson="$(remote ca01 'sudo -n cat /etc/step-ca/config/ca.json' 2>/dev/null || true)"
# _m06_ca FILTRE — filtre booléen sur ca.json (lu une fois).
_m06_ca() { jq -e "$1" >/dev/null 2>&1 <<<"${_m06_cajson:-null}"; }
_m06_prov='.authority.provisioners[] | select(.name == $n) | .claims'

title "Durées (ca.json)"
check_cmd "ca01 : ca.json lisible" _m06_ca '.authority.provisioners | length > 0'
check_cmd "provisioner acme : 30 jours par défaut et au maximum" \
  jq -e --arg n acme "[$_m06_prov] | length == 1 and (.[0].defaultTLSCertDuration | test(\"^720h\")) and (.[0].maxTLSCertDuration | test(\"^720h\"))" <<<"${_m06_cajson:-null}"
check_cmd "provisioner admin : 24 h par défaut, 7 jours au maximum" \
  jq -e --arg n admin "[$_m06_prov] | length == 1 and (.[0].defaultTLSCertDuration | test(\"^24h\")) and (.[0].maxTLSCertDuration | test(\"^168h\"))" <<<"${_m06_cajson:-null}"
check_cmd "certificats SSH d'utilisateur : 16 h au maximum" \
  _m06_ca '[.authority.claims.maxUserSSHCertDuration // empty, (.authority.provisioners[].claims.maxUserSSHCertDuration // empty)] | length > 0 and all(test("^(16h|([0-9]|1[0-5])h)"))'
check_cmd "certificats SSH d'hôte : 30 jours au maximum" \
  _m06_ca '[.authority.claims.maxHostSSHCertDuration // empty, (.authority.provisioners[].claims.maxHostSSHCertDuration // empty)] | length > 0 and all(test("^720h"))'
check_cmd "renouvellement après expiration interdit" \
  _m06_ca '(.authority.provisioners | length > 0) and (.authority.claims.allowRenewalAfterExpiry // false) == false'

title "Révocation active (CRL)"
check_cmd "CRL activée et écouteur HTTP déclaré" _m06_ca '.crl.enabled == true and (.insecureAddress // "") != ""'
_m06_crl="$(curl -sf --max-time "$WB_TIMEOUT" http://ca01.par1.medisphere.internal/1.0/crl 2>/dev/null \
  | openssl crl -inform DER -noout -text 2>/dev/null || true)"
check_output "CRL servie en HTTP et émise par l'intermédiaire MédiSphère" 'Issuer:.*Interm' printf '%s\n' "$_m06_crl"
check_output "la CRL contient au moins un certificat révoqué" 'Serial Number:' printf '%s\n' "$_m06_crl"

title "Renouvellement et expiration"
for _m06_h in nbx01 git01 dns01; do
  check_ssh "$_m06_h : seuil de renouvellement à 15 jours (--expires-in 360h dans cert-renewer@)" "$_m06_h" \
    'grep -rqs -- "--expires-in 360h" /etc/systemd/system/cert-renewer@.service /etc/systemd/system/cert-renewer@*.service.d/'
  check_ssh "$_m06_h : au moins une minuterie cert-renewer active" "$_m06_h" \
    'systemctl list-timers --no-legend "cert-renewer@*" | grep -q .'
done
for _m06_p in git01.par1.medisphere.internal:443 nbx01.par1.medisphere.internal:443 ca01.par1.medisphere.internal:443; do
  check_cmd "${_m06_p} : certificat valide, plus de 10 jours avant expiration" _m06p_cert_valide "${_m06_p%:*}" "${_m06_p##*:}" 10
done

title "Clé racine et documentation"
check_ssh "ca01 : aucune clé racine présente" ca01 \
  '! sudo -n find /etc/step-ca /root /home -xdev -iname "*root*key*" 2>/dev/null | grep -q .'
check_cmd "plateforme/medisphere : RB-063 dans docs/socle/runbooks/" _m06p_runbook RB-063
# _m06_rb063 — contenu de RB-063 sur main (nom exact du fichier lu dans l'arborescence).
_m06_rb063() {
  local f
  f="$(gitlab_api "projects/plateforme%2Fmedisphere/repository/tree?ref=main&path=docs%2Fsocle%2Frunbooks&per_page=100" \
    | jq -r '.[] | select(.name | startswith("RB-063")) | .path' | head -n 1)" || return 1
  [[ -n "$f" ]] && gitlab_api "projects/plateforme%2Fmedisphere/repository/files/${f//\//%2F}/raw?ref=main"
}
check_output "RB-063 : date de fin de vie de l'intermédiaire renseignée" '[Ii]ntermédiaire.*20[0-9]{2}-[0-9]{2}-[0-9]{2}' _m06_rb063
