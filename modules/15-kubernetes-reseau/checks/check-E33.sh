# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées par bash -c
#
# check-E33.sh — M15-E33 « Durcir l'entrée : TLS, en-têtes et authentification mutuelle »
# Lecture seule : négociations TLS et requêtes HTTPS depuis adm01 (openssl, curl ; requêtes GET/HEAD
# sur /sante), objets Gateway API (wb-checks), DNS, droits des fichiers locaux, fiche sur main.
# Remarque : si l'openssl d'adm01 refuse lui-même TLS 1.0/1.1, le contrôle « refuse TLS 1.1 » est
# forcé côté client par « -cipher DEFAULT@SECLEVEL=0 » ; lis le corrigé si tu doutes du résultat.

# shellcheck source=_m15-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-production.sh"

title "M15-E33 — Durcir l'entrée"
require_cmd kubectl jq curl openssl dig
check_cmd "l'API de k8s-par1 répond (compte wb-checks)" _m15p_api_ok

_m15_e33_app="mediagenda-recette.$_M15P_APPS"
_m15_e33_part="mediagenda-partenaires.$_M15P_APPS"

title "TLS de gw-par1"
_m15_e33_tls() {
  # _m15_e33_tls OPTIONS… — la négociation aboutit (« New, <version de la suite>, Cipher is <suite> » ;
  # un échec affiche « New, (NONE), Cipher is (NONE) »). La version forcée vient de l'option -tls1_x.
  openssl s_client -connect "$_M15P_GW_IP:443" -servername "$_m15_e33_app" "$@" </dev/null 2>/dev/null \
    | grep -Eq '^New, .*Cipher is [^(]'
}
check_cmd "TLS 1.3 accepté" _m15_e33_tls -tls1_3
check_cmd "TLS 1.2 accepté" _m15_e33_tls -tls1_2
check_cmd "TLS 1.1 refusé" bash -c '! openssl s_client -connect "$1:443" -servername "$2" -tls1_1 -cipher "DEFAULT@SECLEVEL=0" </dev/null 2>/dev/null | grep -Eq "^New, .*Cipher is [^(]"' _ "$_M15P_GW_IP" "$_m15_e33_app"

title "En-têtes de MédiAgenda"
_M15_E33_H="$(_m15p_entetes "https://$_m15_e33_app/sante")"
_m15_e33_hsts() {
  local a
  a="$(grep -i '^strict-transport-security:' <<<"$_M15_E33_H" | grep -Eio 'max-age=[0-9]+' | cut -d= -f2 | head -n 1)"
  [[ "$a" =~ ^[0-9]+$ ]] && ((a >= 31536000))
}
check_cmd "Strict-Transport-Security avec max-age d'au moins un an" _m15_e33_hsts
check_cmd "X-Content-Type-Options: nosniff" grep -Eiq '^x-content-type-options: *nosniff' <<<"$_M15_E33_H"
check_cmd "Referrer-Policy: no-referrer" grep -Eiq '^referrer-policy: *no-referrer' <<<"$_M15_E33_H"
check_cmd "X-Frame-Options: DENY" grep -Eiq '^x-frame-options: *deny' <<<"$_M15_E33_H"

title "Gateway des partenaires"
_M15_E33_GW="$(_m15p_get -n passerelles gateway gw-partenaires)"
check_cmd "gw-partenaires a l'adresse 10.10.41.11" \
  _m15p_jq "$_M15_E33_GW" 'any(.status.addresses[]?; .value == "10.10.41.11")'
check_cmd "gw-partenaires : écouteur TLS en passthrough sur 443" \
  _m15p_jq "$_M15_E33_GW" 'any(.spec.listeners[]; .protocol == "TLS" and .port == 443 and .tls.mode == "Passthrough")'
check_cmd "gw-partenaires est programmée" _m15p_condition "$_M15_E33_GW" Programmed
_m15_e33_route() {
  local j
  j="$(_m15p_get tlsroutes -A)"
  _m15p_jq "$j" 'any(.items[]; any(.spec.parentRefs[]; .name == "gw-partenaires")
     and any(.spec.hostnames[]?; . == $h)
     and any(.status.parents[]?.conditions[]?; .type == "Accepted" and .status == "True"))' --arg h "$_m15_e33_part"
}
check_cmd "une TLSRoute pour $_m15_e33_part est acceptée par gw-partenaires" _m15_e33_route
check_cmd "$_m15_e33_part résout vers 10.10.41.11" _m15p_resout "$_m15_e33_part" 10.10.41.11

title "Authentification mutuelle"
_m15_e33_dir="$HOME/.config/workbook"
check_cmd "sans certificat client : refusé (pas de réponse 2xx)" \
  bash -c '! [[ "$1" =~ ^2 ]]' _ "$(_m15p_code_https "https://$_m15_e33_part/sante")"
check_cmd "avec le certificat de test centre-test-01 : l'API répond (2xx)" \
  _m15p_https_code "https://$_m15_e33_part/sante" '^2[0-9][0-9]$' \
  --cert "$_m15_e33_dir/partenaire-centre-test-01.crt" --key "$_m15_e33_dir/partenaire-centre-test-01.key"
check_cmd "clé de l'autorité des partenaires en 600" _m15p_mode_600 "$_m15_e33_dir/ca-partenaires.key"
check_cmd "clé du certificat de test en 600" _m15p_mode_600 "$_m15_e33_dir/partenaire-centre-test-01.key"

title "Documentation"
check_cmd "docs/kubernetes/reseau/durcissement-entree.md sur main (support de Cilium 1.20 argumenté)" \
  _m15p_doc_main docs/kubernetes/reseau/durcissement-entree.md 'BackendTLSPolicy' 'passthrough' 'certificat client|client certificate' 'HSTS|Strict-Transport-Security'
