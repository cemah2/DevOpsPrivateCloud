# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E02.sh — M24-E02 : Construire l'annuaire : FreeIPA sur ipa01 et sa CA subordonnée
# À lancer depuis adm01. Lecture seule : DNS, NetBox, ports, chaîne TLS de l'annuaire, paquet
# public des CA de FreeIPA, SSH en consultation sur ipa01, GitLab (procès-verbal, CSR et certificat).

# shellcheck source=_m24-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-decouverte.sh"

title "M24-E02 — Construire l'annuaire : FreeIPA sur ipa01 et sa CA subordonnée"
require_cmd jq curl dig openssl

_m24d_e02_fqdn="ipa01.$_M24D_DOMAINE"
_m24d_e02_rx="${_m24d_e02_fqdn//./\\.}"

# _m24d_e02_signee_par_racine PEM — le certificat se vérifie contre la SEULE racine MédiSphère.
_m24d_e02_signee_par_racine() {
  openssl verify -CAfile "$_M24D_RACINE" <(printf '%s' "$1") >/dev/null 2>&1
}

# _m24d_e02_pathlen0 PEM — autorité dont la longueur de chemin vaut 0.
_m24d_e02_pathlen0() {
  openssl x509 -noout -ext basicConstraints <<<"$1" 2>/dev/null | grep -q 'CA:TRUE, pathlen:0'
}

# _m24d_e02_tls PORT PEM_CA — le service présente un certificat valide pour ipa01, vérifié avec la
# racine et la CA de FreeIPA comme seules autorités.
_m24d_e02_tls() {
  timeout "$WB_TIMEOUT" openssl s_client -connect "$_m24d_e02_fqdn:$1" -servername "$_m24d_e02_fqdn" \
    -verify_hostname "$_m24d_e02_fqdn" -verify_return_error \
    -CAfile <(cat "$_M24D_RACINE"; printf '%s' "$2") </dev/null 2>&1 | grep -q 'Verify return code: 0 (ok)'
}

# --- 1. La machine ---------------------------------------------------------------------------------
check_cmd "NetBox : VM ipa01 déclarée (créée par OpenTofu, étiquettes socle et role-annuaire)" _m24d_json \
  "$(netbox_api "virtualization/virtual-machines/?name=ipa01" 2>/dev/null || true)" \
  '.count == 1 and ([.results[0].tags[].slug] | index("socle") != null and index("role-annuaire") != null)'
check_ssh_output "ipa01 : Rocky Linux 10" "$_M24D_IPA" '^Rocky Linux release 10' "cat /etc/rocky-release"
check_ssh_output "ipa01 : nom complet ipa01.par1.medisphere.internal" "$_M24D_IPA" "^${_m24d_e02_rx}\$" "hostname -f"
check_ssh_output "ipa01 : horloge synchronisée (chrony)" "$_M24D_IPA" 'Leap status +: Normal' "chronyc tracking"

# --- 2. Le DNS publié dans PowerDNS (pas de DNS intégré) -----------------------------------------
check_dns "A ipa01.par1.medisphere.internal → 10.10.20.31" "$_m24d_e02_fqdn" A '^10\.10\.20\.31$'
check_dns "PTR 10.10.20.31 → ipa01.par1.medisphere.internal" 31.20.10.10.in-addr.arpa PTR "^${_m24d_e02_rx}\\.\$"
check_dns "A ipa-ca.par1.medisphere.internal → 10.10.20.31 (OCSP et CRL de la CA)" "ipa-ca.$_M24D_DOMAINE" A '^10\.10\.20\.31$'
check_dns "SRV _ldap._tcp → ipa01:389" "_ldap._tcp.$_M24D_DOMAINE" SRV " 389 ${_m24d_e02_rx}\\.\$"
check_dns "SRV _kerberos._udp → ipa01:88" "_kerberos._udp.$_M24D_DOMAINE" SRV " 88 ${_m24d_e02_rx}\\.\$"
check_dns "SRV _kerberos._tcp → ipa01:88" "_kerberos._tcp.$_M24D_DOMAINE" SRV " 88 ${_m24d_e02_rx}\\.\$"
check_dns "SRV _kpasswd._udp → ipa01:464" "_kpasswd._udp.$_M24D_DOMAINE" SRV " 464 ${_m24d_e02_rx}\\.\$"
check_dns "TXT _kerberos → royaume PAR1.MEDISPHERE.INTERNAL" "_kerberos.$_M24D_DOMAINE" TXT "^\"$_M24D_ROYAUME_KRB\"\$"

# --- 3. Les services -------------------------------------------------------------------------------
check_ssh "ipa01 : tous les services de FreeIPA démarrés (ipactl status)" "$_M24D_IPA" \
  "sudo -n ipactl status 2>&1 | grep -q 'The ipactl command was successful'"
check_ssh_output "ipa01 : pas de DNS intégré (named arrêté), pas de service NTP ouvert par firewalld" "$_M24D_IPA" '^aucun$' \
  "if systemctl is-active --quiet named || sudo -n firewall-cmd --list-services 2>/dev/null | grep -qw ntp; then echo present; else echo aucun; fi"
for _m24d_e02_p in 88 389 443 464 636; do
  check_port "ipa01 : port TCP $_m24d_e02_p joignable depuis MGMT" "$_m24d_e02_fqdn" "$_m24d_e02_p"
done

# --- 4. La CA subordonnée à la racine MédiSphère ----------------------------------------------------
# Le paquet des CA de FreeIPA est public (http://ipa01/ipa/config/ca.crt, lu aussi par
# ipa-client-install) : on y prend la CA de FreeIPA et on la vérifie contre la SEULE racine.
_m24d_e02_paquet="$(curl -sf --max-time "$WB_TIMEOUT" "http://$_m24d_e02_fqdn/ipa/config/ca.crt" 2>/dev/null || true)"
# Sujet « CN=Certificate Authority,O=<royaume> » (ordre LDAP) : openssl l'affiche dans l'ordre d'encodage.
_m24d_e02_ca="$(_m24d_pem_selon_sujet \
  "^subject=(O=$_M24D_ROYAUME_KRB,CN=Certificate Authority|CN=Certificate Authority,O=$_M24D_ROYAUME_KRB)\$" <<<"$_m24d_e02_paquet")"
if [[ -z "$_m24d_e02_ca" ]]; then
  _ko "CA de FreeIPA introuvable dans http://$_m24d_e02_fqdn/ipa/config/ca.crt (sujet CN=Certificate Authority,O=$_M24D_ROYAUME_KRB)"
else
  check_cmd "CA de FreeIPA signée par « MédiSphère Root CA » (vérifiée contre la seule racine du lab)" \
    _m24d_e02_signee_par_racine "$_m24d_e02_ca"
  check_cmd "CA de FreeIPA : autorité (CA:TRUE) de longueur de chemin 0" _m24d_e02_pathlen0 "$_m24d_e02_ca"
  check_cmd "LDAPS (636) : certificat de ipa01 vérifié jusqu'à la racine, nom d'hôte compris" \
    _m24d_e02_tls 636 "$_m24d_e02_ca"
  check_cmd "HTTPS (443) : même vérification sur l'interface et l'API de FreeIPA" _m24d_e02_tls 443 "$_m24d_e02_ca"
fi
check_ssh_output "ipa01 : le certificat de signature de Dogtag est bien celui que la racine a signé" "$_M24D_IPA" \
  '^issuer=CN=MédiSphère Root CA$' \
  "sudo -n certutil -L -d /etc/pki/pki-tomcat/alias -n 'caSigningCert cert-pki-ca' -a 2>/dev/null | openssl x509 -noout -issuer -nameopt utf8,sep_comma_plus"

# --- 5. Traces écrites -------------------------------------------------------------------------------
_m24d_e02_pv="$(_m24d_contenu_main plateforme/medisphere docs/securite/identite/ceremonie-ca.md)"
if [[ -z "$_m24d_e02_pv" ]]; then
  _ko "plateforme/medisphere : docs/securite/identite/ceremonie-ca.md absent de main (procès-verbal de la cérémonie)"
else
  _ok "plateforme/medisphere : docs/securite/identite/ceremonie-ca.md présent sur main"
  check_cmd "ceremonie-ca.md : empreinte SHA-256 du certificat signé relevée" \
    _m24d_contient "$_m24d_e02_pv" '([0-9A-Fa-f]{2}:){15}|[0-9a-f]{64}'
  check_cmd "ceremonie-ca.md : échéance et renouvellement de la CA de FreeIPA prévus" \
    _m24d_contient "$_m24d_e02_pv" '([Rr]enouvel|[Éé]chéance)'
fi
check_cmd "plateforme/ansible : CSR de la CA de FreeIPA versionnée (pki/ipa01-ipa.csr)" \
  _m24d_contient "$(_m24d_contenu_main plateforme/ansible pki/ipa01-ipa.csr)" 'BEGIN CERTIFICATE REQUEST'
_m24d_e02_crt="$(_m24d_contenu_main plateforme/ansible pki/ipa01-ipa.crt)"
check_cmd "plateforme/ansible : certificat signé versionné (pki/ipa01-ipa.crt), sans clé privée" \
  _m24d_contient "$_m24d_e02_crt" 'BEGIN CERTIFICATE'
if _m24d_contient "$_m24d_e02_crt" 'PRIVATE KEY'; then
  _ko "pki/ipa01-ipa.crt contient une CLÉ PRIVÉE : retire-la de l'historique Git et change la clé"
fi
