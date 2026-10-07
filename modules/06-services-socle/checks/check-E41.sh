# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
# check-E41.sh — M06-E41 « Panne : SERVFAIL sur la zone signée » : la zone interne est signée,
# validée par les récurseurs (drapeau ad), et l'ancre de confiance correspond à une clé active.
# Lecture seule.

# shellcheck source=_m06-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-expert.sh"

title "M06-E41 — Zone signée et validée"
require_cmd dig ssh

check_cmd "dns01 : SOA de $_m06x_zone validé (drapeau ad)" _m06x_valide 10.10.20.10 "$_m06x_zone" SOA
check_cmd "dns01 : git01.$_m06x_zone validé (drapeau ad)" _m06x_valide 10.10.20.10 "git01.$_m06x_zone" A
check_ssh "dns01 : la zone n'est pas en mode PRESIGNED" dns01 \
  "! sudo -n pdnsutil metadata get $_m06x_zone PRESIGNED 2>/dev/null | grep -q '= 1'"
check_ssh "dns01 : au moins une clé active, pdnsutil zone check sans erreur" dns01 \
  "sudo -n pdnsutil zone show $_m06x_zone | grep -Eq '^ID = [0-9]+ .*[[:space:]]Active' && sudo -n pdnsutil zone check $_m06x_zone >/dev/null"
check_ssh "dns01 : l'ancre de confiance du récurseur correspond au DS d'une clé active" dns01 '
  ta=$(sudo -n rec_control get-tas 2>/dev/null)
  sudo -n pdnsutil zone export-ds '"$_m06x_zone"' 2>/dev/null | awk "{ for (i = 1; i <= NF; i++) if (\$i == \"DS\" && \$(i + 3) == 2) print tolower(\$(i + 4)) }" | while read -r d; do
    echo "$ta" | tr "A-F" "a-f" | grep -qF "$d" && exit 10
  done; [ $? -eq 10 ]'
if _m06x_existe dns02; then
  check_cmd "dns02 : SOA de $_m06x_zone validé (drapeau ad)" _m06x_valide 10.10.20.16 "$_m06x_zone" SOA
else
  skip "dns02 : validation" "dns02 absent (M06-E24)"
fi
check_cmd "panne M06-E41 close (lab/bin/break 06 41 --annuler après réparation)" _m06x_aucune_panne_active E41
