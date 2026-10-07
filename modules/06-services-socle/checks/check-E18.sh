# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E18.sh — M06-E18 : Certificats automatiques par ACME pour GitLab et NetBox
# À lancer depuis adm01. Lecture seule : connexions TLS, état des minuteries.

# shellcheck source=_m06-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-operationnel.sh"

title "M06-E18 — Certificats automatiques par ACME pour GitLab et NetBox"
require_cmd openssl curl

_m06o_racine=/usr/local/share/ca-certificates/medisphere-root-ca.crt

for _m06o_cible in git01:443 nbx01:443 s3-01:8333; do
  _m06o_h="${_m06o_cible%%:*}"
  _m06o_fqdn="$_m06o_h.$_M06O_ZONE"
  _m06o_x509="$(_m06o_cert_tls "$_m06o_fqdn" "${_m06o_cible#*:}")"
  check_output "$_m06o_h : certificat émis par « MédiSphère Intermediate CA »" 'issuer=.*Interm' echo "$_m06o_x509"
  check_output "$_m06o_h : durée de validité de 30 jours au plus" '^([0-9]|[12][0-9]|30)$' \
    _m06o_duree_jours "$_m06o_x509"
  check_output "$_m06o_h : le nom $_m06o_fqdn est dans le certificat" "DNS:${_m06o_fqdn//./\\.}" echo "$_m06o_x509"
  check_cmd "$_m06o_h : chaîne complète acceptée par curl avec la seule racine MédiSphère" \
    curl -sS -o /dev/null --max-time "$WB_TIMEOUT" --cacert "$_m06o_racine" "https://$_m06o_fqdn:${_m06o_cible#*:}/"
  check_ssh "$_m06o_h : une minuterie cert-renewer@ est active" "$_m06o_h" \
    'systemctl list-units --type=timer --state=active --no-legend "cert-renewer@*" | grep -q cert-renewer@'
  check_ssh "$_m06o_h : aucune exécution de cert-renewer@ en échec" "$_m06o_h" \
    '! systemctl list-units --failed --no-legend "cert-renewer@*" | grep -q cert-renewer@'
done

# Plus aucun service HTTPS du socle ne présente un certificat de la CA provisoire.
for _m06o_cible in git01:443 nbx01:443 s3-01:8333 ca01:443; do
  _m06o_x509="$(_m06o_cert_tls "${_m06o_cible%%:*}.$_M06O_ZONE" "${_m06o_cible#*:}")"
  check_cmd "${_m06o_cible%%:*} : pas de certificat signé par la CA provisoire" \
    bash -c '[[ -n "$1" ]] && ! grep -qi "provisoire" <<<"$1"' _ "$_m06o_x509"
done

check_cmd "plateforme/ansible : scénario Molecule du rôle certificats_acme sur main" \
  _m06o_fichier_main "$_M06O_PROJET_ANSIBLE" molecule/certificats_acme/molecule.yml
