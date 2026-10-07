# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
# check-E35.sh — M06-E35 « Panne : un nom interne ne se résout plus » : état sain de la résolution
# des noms internes (récurseur de dns01, autoritaire local, secondaire s'il existe). Lecture seule.

# shellcheck source=_m06-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-expert.sh"

title "M06-E35 — Les noms internes se résolvent"
require_cmd dig ssh

for _m06_e35_h in gw01 adm01 dns01 ca01 git01 nbx01 s3-01 runner01; do
  check_cmd "dns01 : $_m06_e35_h.$_m06x_zone → ${_m06x_ip[$_m06_e35_h]}" \
    _m06x_resout "$_m06_e35_h.$_m06x_zone" "${_m06x_ip[$_m06_e35_h]}"
done
check_dns "dns01 : inverse de 10.10.20.12 (git01)" 12.20.10.10.in-addr.arpa PTR "^git01\\.par1\\.medisphere\\.internal\\.$" 10.10.20.10
check_output "dns01 : réponse en TCP" '^10\.10\.20\.12$' dig +short +tcp +time=3 @10.10.20.10 "git01.$_m06x_zone" A
check_output "dns01 : récursion vers Internet (deb.debian.org)" '^NOERROR$' _m06x_statut 10.10.20.10 deb.debian.org A
check_ssh "dns01 : pdns et pdns-recursor actifs et activés" dns01 \
  'for s in pdns pdns-recursor; do systemctl is-active -q "$s" && systemctl is-enabled -q "$s" || exit 1; done'
check_ssh_output "dns01 : l'autoritaire local (127.0.0.1:5300) sert git01" dns01 '^10\.10\.20\.12$' \
  "dig +short +time=3 @127.0.0.1 -p 5300 git01.$_m06x_zone A"
check_ssh "dns01 : base de l'autoritaire lisible par le compte du service" dns01 '
  f=$(sudo -n sh -c "grep -hE \"^[[:space:]]*(gsqlite3-database|lmdb-filename)[[:space:]]*=\" /etc/powerdns/pdns.conf /etc/powerdns/pdns.d/*.conf 2>/dev/null" | tail -n 1 | cut -d= -f2- | tr -d " ")
  [ -z "$f" ] || [ "$(sudo -n stat -c %U "$f")" != root ]'
check_ssh "dns01 : le récurseur relaie la zone $_m06x_zone vers le port 5300" dns01 \
  "sudo -n grep -A6 -E 'zone:[[:space:]]*[\"'\'']?par1\\.medisphere\\.internal\\.?[\"'\'']?([[:space:]]|,|\$)' /etc/powerdns/recursor.yml | grep -q ':5300'"
if _m06x_existe dns02; then
  check_cmd "dns02 : git01.$_m06x_zone → 10.10.20.12" _m06x_resout "git01.$_m06x_zone" 10.10.20.12 10.10.20.16
  check_output "dns02 : le serveur faisant autorité (10.10.20.16:5300) sert git01" '^10\.10\.20\.12$' \
    dig +short +norecurse +time=3 @10.10.20.16 -p 5300 "git01.$_m06x_zone" A
else
  skip "dns02 : résolution de git01" "dns02 absent (M06-E24)"
fi
check_cmd "panne M06-E35 close (lab/bin/break 06 35 --annuler après réparation)" _m06x_aucune_panne_active E35
