# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E13.sh — M07-E13 : Publier GitLab et NetBox derrière les répartiteurs
# À lancer depuis adm01. Lecture seule.

# shellcheck source=_m07-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-operationnel.sh"

title "M07-E13 — Publier GitLab et NetBox derrière les répartiteurs"
require_cmd jq curl openssl dig

# --- Noms et certificats publiés ---------------------------------------------------------------------------
for _m07o_n in gitlab netbox; do
  _m07o_fqdn="$_m07o_n.$_M07O_ZONE"
  check_dns "$_m07o_fqdn → 10.10.70.200" "$_m07o_fqdn" A '10\.10\.70\.200' 10.10.20.10
  _m07o_x509="$(_m07o_cert_tls 10.10.70.200 443 "$_m07o_fqdn")"
  check_output "$_m07o_fqdn : certificat de la PKI" 'issuer=.*Interm' echo "$_m07o_x509"
  check_output "$_m07o_fqdn : certificat à ce nom" "DNS:${_m07o_fqdn//./\\.}" echo "$_m07o_x509"
done
check_output "GitLab publié : page de connexion (200)" '^200$' _m07o_curl "https://gitlab.$_M07O_ZONE/users/sign_in"
check_output "NetBox publié : page de connexion (200)" '^200$' _m07o_curl "https://netbox.$_M07O_ZONE/login/"
check_output "un nom inconnu n'obtient aucun service par la VIP (TLS refusé ou 503)" '^(000|503)$' \
  _m07o_curl "https://inconnu.$_M07O_ZONE/" --resolve "inconnu.$_M07O_ZONE:443:10.10.70.200"

# --- Serveurs vus par les deux répartiteurs ------------------------------------------------------------
for _m07o_h in lb01 lb02; do
  _m07o_stat="$(_m07o_haproxy_stat "$_m07o_h")"
  check_output "$_m07o_h : git01 est UP (contrôle de santé)" '^UP' bash -c \
    'awk -F, '"'"'$2 == "git01" && $1 != "stats" {print $18}'"'"' <<<"$1" | head -n 1' _ "$_m07o_stat"
  check_output "$_m07o_h : nbx01 est UP (contrôle de santé)" '^UP' bash -c \
    'awk -F, '"'"'$2 == "nbx01" && $1 != "stats" {print $18}'"'"' <<<"$1" | head -n 1' _ "$_m07o_stat"
  check_ssh "$_m07o_h : aucune vérification TLS désactivée vers les serveurs" "$_m07o_h" \
    '! sudo -n grep -Eq "verify[[:space:]]+none" /etc/haproxy/haproxy.cfg'
  check_ssh "$_m07o_h : serveurs re-chiffrés avec « verify required » et nom attendu" "$_m07o_h" \
    'sudo -n grep -E "^[[:space:]]*server (git01|nbx01) " /etc/haproxy/haproxy.cfg | grep "verify required" | grep -c verifyhost | grep -qx 2'
done

# --- Ce qui ne doit pas être publié, ce qui doit continuer ---------------------------------------------
_m07o_port22_ferme() { ! timeout "$WB_TIMEOUT" bash -c 'exec 3<>/dev/tcp/10.10.70.200/22' 2>/dev/null; }
check_cmd "VIP : port 22 fermé (le SSH de GitLab n'est pas publié)" _m07o_port22_ferme
check_port "git01 : SSH de GitLab toujours direct (port 22)" 10.10.20.12 22
check_output "accès direct : https://git01.$_M07O_ZONE répond" '^(200|302)$' _m07o_curl "https://git01.$_M07O_ZONE/users/sign_in"
check_output "accès direct : https://nbx01.$_M07O_ZONE répond" '^200$' _m07o_curl "https://nbx01.$_M07O_ZONE/login/"

# --- Bordure : traduction du port 443 WAN vers la VIP --------------------------------------------------
_m07o_pre="$(_m07o_nft_gw01 'nat prerouting')"
_m07o_dnat() {
  grep -E 'dnat to 10\.10\.70\.200(:443)?' <<<"$_m07o_pre" | grep 'tcp dport 443' | grep -q 'ip saddr'
}
check_cmd "gw01 : le port 443 WAN est traduit vers la VIP, pour une source restreinte" _m07o_dnat
_m07o_fwd="$(_m07o_nft_gw01 forward)"
_m07o_transit_wan() {
  grep -E 'iifname "ens18"' <<<"$_m07o_fwd" | grep '10\.10\.70\.200' | grep -q 'tcp dport 443 accept'
}
check_cmd "gw01 : transit autorisé du WAN vers la VIP sur 443 seulement" _m07o_transit_wan
_m07o_lb_infra() {
  grep -E 'iifname "ens19\.70"' <<<"$_m07o_fwd" | grep '10\.10\.20\.12' | grep -q 'tcp dport 443 accept'
}
check_cmd "gw01 : les répartiteurs joignent les serveurs publiés (443)" _m07o_lb_infra
