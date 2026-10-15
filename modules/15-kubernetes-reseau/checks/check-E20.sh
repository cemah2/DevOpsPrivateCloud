# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E20.sh — M15-E20 : Publier une application hors du lab par lb01/lb02
# À lancer depuis adm01. Lecture seule (requêtes HTTPS vers la VIP des répartiteurs, lecture de
# haproxy.cfg et nft list en SSH, GitLab, journal).

# shellcheck source=_m15-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-operationnel.sh"

title "M15-E20 — Publier une application hors du lab par lb01/lb02"
require_cmd curl openssl

_m15o_vip=10.10.70.200

# --- Comportement par la VIP des répartiteurs ---------------------------------------------------------
check_output "$_M15O_NOM_MA répond 200 en HTTPS par la VIP des répartiteurs" '^200$' \
  _m15o_code "https://$_M15O_NOM_MA/sante" "$(_m15o_resolve "$_M15O_NOM_MA" 443 "$_m15o_vip")"
_m15o_c="$(_m15o_cert "$_m15o_vip" 443 "$_M15O_NOM_MA")"
check_cmd "le certificat vu par la VIP est le joker du cluster (TLS de bout en bout)" _m15o_cert_pki_joker "$_m15o_c"
check_output "un nom *.apps non publié est refusé par les répartiteurs" '^000$' \
  _m15o_code "https://essai.$_M15O_APPS/" "$(_m15o_resolve "essai.$_M15O_APPS" 443 "$_m15o_vip")"
check_output "GitLab répond toujours par les répartiteurs" '^200$' _m15o_code "https://gitlab.par1.medisphere.internal/-/readiness"
for _m15o_lb in lb01 lb02; do
  check_http "$_m15o_lb : sonde /sante de la terminaison locale" "https://$_m15o_lb.par1.medisphere.internal/sante" 200
  check_ssh_output "$_m15o_lb : aiguillage par SNI vers 10.10.41.10:443 dans haproxy.cfg" "$_m15o_lb" \
    'server [^ ]+ 10\.10\.41\.10:443' "sudo -n cat /etc/haproxy/haproxy.cfg"
  check_ssh_output "$_m15o_lb : terminaison locale derrière le PROXY protocol (adresse client conservée)" "$_m15o_lb" \
    'accept-proxy' "sudo -n cat /etc/haproxy/haproxy.cfg"
done

# --- Flux ---------------------------------------------------------------------------------------------
for _m15o_g in gw01 gw02; do
  check_ssh_output "$_m15o_g : transit lb01/lb02 → 10.10.41.10 TCP 443" "$_m15o_g" \
    '10\.10\.70\.1[01].*10\.10\.41\.10.*dport 443' "sudo -n nft list chain inet filter forward"
  check_ssh "$_m15o_g : 10.10.41.0/24 n'est pas ouvert en entier depuis la DMZ" "$_m15o_g" \
    "! sudo -n nft list chain inet filter forward | grep -E '10\\.10\\.70\\.' | grep -q '10\\.10\\.41\\.0/24'"
done

# --- Code et journal -----------------------------------------------------------------------------------
_m15o_h="$(_m15o_contenu_main "$_M15O_ANSIBLE" inventories/lab/group_vars/role_lb/haproxy.yml)"
check_cmd "haproxy.yml sur main de plateforme/ansible : liste des noms publiés et aiguillage SNI" \
  bash -c 'grep -q "mediagenda-recette.apps.par1.medisphere.internal" <<<"$1" && grep -q "req.ssl_sni" <<<"$1"' _ "$_m15o_h"
check_cmd "journal ~/m15/e20/journal.md : mesure de bascule et adresse client (au moins 10 lignes)" \
  _m15o_journal "$_M15O_TRAVAIL/e20/journal.md" 10
