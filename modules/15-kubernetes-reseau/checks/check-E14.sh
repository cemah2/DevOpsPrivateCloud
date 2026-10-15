# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E14.sh — M15-E14 : Défis DNS-01 par RFC 2136 : la zone apps
# À lancer depuis adm01. Lecture seule (dig, pdnsutil metadata get / nft list sur dns01, kube get,
# openssl, GitLab). L'essai de refus d'une mise à jour depuis adm01 fait partie de l'exercice, pas
# du check (un check n'écrit jamais, même pour être refusé).

# shellcheck source=_m15-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-operationnel.sh"

title "M15-E14 — Défis DNS-01 par RFC 2136 : la zone apps"
require_cmd kubectl jq dig openssl

_m15o_z="$_M15O_APPS"

# --- Zone sur les deux serveurs ---------------------------------------------------------------------
_m15o_soa1="$(_m15o_dig 10.10.20.10 5300 "$_m15o_z" SOA +norecurse)"
_m15o_soa2="$(_m15o_dig 10.10.20.16 5300 "$_m15o_z" SOA +norecurse)"
check_output "dns01 (primaire) sert la zone $_m15o_z" '^dns01\.par1\.medisphere\.internal\. ' echo "$_m15o_soa1"
check_cmd "dns02 (secondaire) sert la zone avec le même numéro de série" \
  bash -c '[[ -n "$1" && "$(awk "{print \$3}" <<<"$1")" == "$(awk "{print \$3}" <<<"$2")" ]]' _ "$_m15o_soa1" "$_m15o_soa2"
check_output "NS de la zone : dns01 et dns02" '^dns01\.par1\.medisphere\.internal\. dns02\.par1\.medisphere\.internal\.$' \
  bash -c 'dig +short +norecurse -p 5300 @10.10.20.10 "$1" NS | sort | paste -sd" " -' _ "$_m15o_z"
check_output "zone signée : DNSKEY servi par dns02" '^257 3 13 ' _m15o_dig 10.10.20.16 5300 "$_m15o_z" DNSKEY +norecurse
check_output "délégation : DS de la zone publié dans par1" '^[0-9]+ 13 2 [0-9A-Fa-f]+' _m15o_dig 10.10.20.10 5300 "$_m15o_z" DS +norecurse
check_output "validation DNSSEC par les récurseurs (bit ad)" 'flags:[^;]* ad[ ;]' \
  dig +dnssec +time="$WB_TIMEOUT" @10.10.20.10 "$_m15o_z" SOA

# --- Autorisations (lecture des métadonnées sur dns01) -------------------------------------------------
_m15o_meta="$(remote dns01 "sudo -n -u pdns pdnsutil metadata get $_m15o_z TSIG-ALLOW-DNSUPDATE ALLOW-DNSUPDATE-FROM NOTIFY-DNSUPDATE TSIG-ALLOW-AXFR" 2>/dev/null || true)"
check_cmd "mises à jour réservées aux clés certmanager-k8s et externaldns-k8s" bash -c \
  'l="$(grep "^TSIG-ALLOW-DNSUPDATE" <<<"$1")"; [[ "$l" == *certmanager-k8s* && "$l" == *externaldns-k8s* && $(tr -cd , <<<"$l" | wc -c) -eq 1 ]]' _ "$_m15o_meta"
check_output "mises à jour acceptées depuis 10.10.40.0/24 seulement" '^ALLOW-DNSUPDATE-FROM = 10\.10\.40\.0/24$' echo "$_m15o_meta"
check_output "NOTIFY après chaque mise à jour" '^NOTIFY-DNSUPDATE = 1$' echo "$_m15o_meta"
check_output "externaldns-k8s autorisée à transférer la zone (AXFR)" '^TSIG-ALLOW-AXFR = .*externaldns-k8s' echo "$_m15o_meta"
_m15o_par1="$(remote dns01 "sudo -n -u pdns pdnsutil metadata get par1.medisphere.internal TSIG-ALLOW-DNSUPDATE" 2>/dev/null || true)"
check_cmd "les clés du cluster n'ont aucun droit sur par1" bash -c '! grep -qE "certmanager-k8s|externaldns-k8s" <<<"$1"' _ "$_m15o_par1"
check_ssh_output "dns01 : pare-feu local ouvert sur 5300 depuis 10.10.40.0/24" dns01 \
  '10\.10\.40\.0/24.*dport 5300|dport 5300.*10\.10\.40\.0/24' "sudo -n nft list ruleset"
check_ssh_output "gw01 : transit 10.10.40.0/24 → dns01 port 5300" gw01 \
  '10\.10\.40\.0/24.*10\.10\.20\.10.*5300' "sudo -n nft list chain inet filter forward"

# --- cert-manager et joker ------------------------------------------------------------------------------
_m15o_ci="$(_m15o_kjson clusterissuer step-ca-acme)"
check_cmd "step-ca-acme : solveur DNS-01 rfc2136 vers 10.10.20.10:5300, clé certmanager-k8s, réservé à la zone apps" \
  _m15o_jq "$_m15o_ci" 'any(.spec.acme.solvers[]?; (.selector.dnsZones // [] | index("apps.par1.medisphere.internal")) and .dns01.rfc2136.nameserver == "10.10.20.10:5300" and .dns01.rfc2136.tsigKeyName == "certmanager-k8s" and .dns01.rfc2136.tsigSecretSecretRef.name != null)'
_m15o_cj="$(_m15o_kjson certificate apps-joker -n passerelles)"
check_output "passerelles/apps-joker : Ready" '^True$' _m15o_condition "$_m15o_cj" Ready
check_cmd "apps-joker : *.apps.par1.medisphere.internal, émis par step-ca-acme" _m15o_jq "$_m15o_cj" \
  '(.spec.dnsNames | index("*.apps.par1.medisphere.internal")) and .spec.secretName == "apps-joker" and .spec.issuerRef.name == "step-ca-acme"'
_m15o_c="$(_m15o_cert "$_M15O_GW" 443 "$_M15O_NOM_MA")"
_m15o_j="$(_m15o_duree_jours "$_m15o_c")"
check_cmd "gw-par1 présente le joker de la PKI MédiSphère" _m15o_cert_pki_joker "$_m15o_c"
check_cmd "le joker présenté vient d'ACME (plus de 8 jours et 30 au plus : ${_m15o_j} j ; le manuel faisait 7 j)" \
  bash -c '(( $1 > 8 && $1 <= 30 ))' _ "$_m15o_j"

# --- Secrets et code -----------------------------------------------------------------------------------
_m15o_v="$(_m15o_contenu_main "$_M15O_ANSIBLE" inventories/lab/group_vars/role_dns/vault-lab.yml)"
check_output "secrets TSIG dans un fichier chiffré par Ansible Vault (identité lab)" '^\$ANSIBLE_VAULT;1\.2;AES256;lab' head -n1 <<<"$_m15o_v"
check_cmd "zone apps déclarée et signée dans l'inventaire (main de plateforme/ansible)" bash -c \
  'grep -q "apps.par1.medisphere.internal" <<<"$1" && grep -q "apps.par1.medisphere.internal" <<<"$2"' _ \
  "$(_m15o_contenu_main "$_M15O_ANSIBLE" inventories/lab/group_vars/role_dns/powerdns_auth.yml)" \
  "$(_m15o_contenu_main "$_M15O_ANSIBLE" inventories/lab/group_vars/role_dns/dnssec.yml)"
check_cmd "dnsupdate-k8s.yml sur main, sans secret TSIG en clair (référence au Vault)" bash -c \
  '[[ -n "$1" ]] && ! grep -qE "secret: *\"?[A-Za-z0-9+/]{43}=" <<<"$1"' _ \
  "$(_m15o_contenu_main "$_M15O_ANSIBLE" inventories/lab/group_vars/role_dns/dnsupdate-k8s.yml)"
check_cmd "journal ~/m15/e14/journal.md rédigé (au moins 15 lignes)" _m15o_journal "$_M15O_TRAVAIL/e14/journal.md" 15
