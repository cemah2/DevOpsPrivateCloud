# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
#
# check-E26.sh — M06-E26 « DNSSEC sur la zone interne »
# Lancé depuis adm01. Lecture seule : requêtes DNS, rec_control et pdnsutil en lecture (sudo -n).

# shellcheck source=_m06-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-production.sh"

title "M06-E26 — DNSSEC sur la zone interne"
require_cmd dig ssh

_m06_z=par1.medisphere.internal

title "Zone signée (serveurs faisant autorité)"
for _m06_a in 10.10.20.10 10.10.20.16; do
  check_output "$_m06_a:5300 publie les DNSKEY de $_m06_z" '(^| )25[67] 3 [0-9]+ ' \
    dig +short +norecurse +time=3 "@$_m06_a" -p 5300 "$_m06_z" DNSKEY
  check_output "$_m06_a:5300 signe les réponses (RRSIG sur git01)" 'RRSIG[[:space:]]+A[[:space:]]' \
    dig +dnssec +norecurse +time=3 "@$_m06_a" -p 5300 "git01.$_m06_z" A
done
check_ssh "dns02 : la zone y est marquée pré-signée (transfert d'une zone signée)" dns02 \
  "sudo -n -u pdns pdnsutil metadata get $_m06_z PRESIGNED 2>/dev/null | grep -Eq '= *1'"
check_ssh "dns01 : réglage SOA-EDIT des zones signées choisi (métadonnée ou réglage global)" dns01 \
  "sudo -n sh -c 'grep -hEqs \"^default-soa-edit-signed=[A-Z]\" /etc/powerdns/pdns.conf /etc/powerdns/pdns.d/*.conf' || sudo -n -u pdns pdnsutil metadata get $_m06_z SOA-EDIT 2>/dev/null | grep -Eq '= *[A-Z]'"

title "Validation par les récurseurs"
for _m06_r in 10.10.20.10 10.10.20.16; do
  check_cmd "$_m06_r : réponse validée (ad) pour git01.$_m06_z" _m06p_ad "$_m06_r" "git01.$_m06_z"
  check_cmd "$_m06_r : résolution Internet validée (ad) pour isc.org" _m06p_ad "$_m06_r" isc.org SOA
  check_dns "$_m06_r : zone non signée par2 toujours résolue" pbs01.par2.medisphere.internal A '^10\.20\.10\.10$' "$_m06_r"
  check_dns "$_m06_r : zone inverse toujours résolue" 10.20.10.10.in-addr.arpa PTR 'dns01\.par1\.medisphere\.internal\.$' "$_m06_r"
done
for _m06_h in dns01 dns02; do
  check_ssh_output "$_m06_h : ancre de confiance pour $_m06_z chargée" "$_m06_h" "$_m06_z" \
    'sudo -n rec_control get-tas'
  check_ssh "$_m06_h : aucune ancre négative ne porte sur $_m06_z" "$_m06_h" \
    'o=$(sudo -n rec_control get-ntas) && ! grep -Eiq "^[[:space:]]*par1\.medisphere\.internal\.?([[:space:]]|$)" <<<"$o"'
done
