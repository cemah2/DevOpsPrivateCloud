# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E11.sh — M07-E11 : Nginx en reverse proxy : TLS et comparaison
# À lancer depuis adm01. Lecture seule.

# shellcheck source=_m07-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-operationnel.sh"

title "M07-E11 — Nginx en reverse proxy : TLS et comparaison"
require_cmd openssl curl

_m07o_fqdn="hap01.$_M07O_ZONE"
for _m07o_p in 443:HAProxy 8443:Nginx; do
  _m07o_port="${_m07o_p%%:*}"
  _m07o_qui="${_m07o_p#*:}"
  _m07o_x509="$(_m07o_cert_tls "$_m07o_fqdn" "$_m07o_port")"
  check_output "$_m07o_qui ($_m07o_port) : certificat émis par « MédiSphère Intermediate CA »" 'issuer=.*Interm' echo "$_m07o_x509"
  check_output "$_m07o_qui ($_m07o_port) : le nom $_m07o_fqdn est dans le certificat" "DNS:${_m07o_fqdn//./\\.}" echo "$_m07o_x509"
  check_output "$_m07o_qui ($_m07o_port) : page d'un serveur de test, chaîne validée par la seule racine MédiSphère" \
    '^200$' _m07o_curl "https://$_m07o_fqdn:$_m07o_port/"
done
check_ssh "hap01 : c'est bien nginx qui écoute sur 8443" hap01 'sudo -n ss -Hltnp "sport = :8443" | grep -q nginx'
check_ssh "hap01 : c'est bien haproxy qui écoute sur 443" hap01 'sudo -n ss -Hltnp "sport = :443" | grep -q haproxy'
check_ssh "hap01 : renouvellement du certificat planifié (cert-renewer@hap01)" hap01 \
  'systemctl is-active --quiet cert-renewer@hap01.timer'
check_ssh "hap01 : le défi ACME est relayé par HAProxy (port 80)" hap01 \
  'sudo -n grep -Eq "path_beg /\.well-known/acme-challenge/" /etc/haproxy/haproxy.cfg'
check_ssh "hap01 : HAProxy transmet X-Forwarded-For au serveur" hap01 \
  'sudo -n grep -Eq "^[[:space:]]*option forwardfor" /etc/haproxy/haproxy.cfg'

# Pare-feu : défi ACME de ca01 vers le VLAN 99, port 80, et rien de plus large.
_m07o_fwd="$(_m07o_nft_gw01 forward)"
_m07o_regle_acme() {
  grep 'oifname "ens19\.99"' <<<"$_m07o_fwd" | grep '10\.10\.20\.11' | grep -q 'tcp dport 80 accept'
}
check_cmd "gw01 : ca01 joint le port 80 de la sandbox (défi ACME)" _m07o_regle_acme
_m07o_large() {
  # Aucune règle ouvrant le port 80 vers la sandbox à une autre source que ca01.
  [[ -n "$_m07o_fwd" ]] \
    && ! grep -E 'oifname "ens19\.99".*tcp dport (80|\{[^}]*\b80\b)' <<<"$_m07o_fwd" | grep -vq '10\.10\.20\.11'
}
check_cmd "gw01 : le port 80 de la sandbox n'est ouvert à personne d'autre" _m07o_large
