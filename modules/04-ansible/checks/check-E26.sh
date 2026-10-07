# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées par bash -c
#
# check-E26.sh — M04-E26 « Performances d'Ansible »
# ansible.cfg de main : cache de faits jsonfile avec expiration, gathering smart, callback de
# mesure ; docs/performances.md avec des mesures ; cache de faits local en 700 ; flotte détruite.

# shellcheck source=_m04-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-production.sh"

title "M04-E26 — Performances d'Ansible"
require_cmd jq ssh curl
_m04_charger

title "ansible.cfg (branche main)"
check_cmd "cache de faits jsonfile" _m04_fichier_main_contient ansible.cfg '^[[:space:]]*fact_caching[[:space:]]*=[[:space:]]*jsonfile'
check_cmd "dossier du cache de faits déclaré" _m04_fichier_main_contient ansible.cfg '^[[:space:]]*fact_caching_connection[[:space:]]*='
check_cmd "expiration du cache explicite" _m04_fichier_main_contient ansible.cfg '^[[:space:]]*fact_caching_timeout[[:space:]]*=[[:space:]]*[0-9]+'
check_cmd "collecte des faits « smart »" _m04_fichier_main_contient ansible.cfg '^[[:space:]]*gathering[[:space:]]*=[[:space:]]*smart'
check_cmd "callback de mesure activé (ansible.posix.timer, profile_tasks ou profile_roles)" \
  _m04_fichier_main_contient ansible.cfg '^[[:space:]]*callbacks_enabled[[:space:]]*=.*ansible\.posix\.(timer|profile_tasks|profile_roles)'

title "Mesures (branche main)"
check_cmd "docs/performances.md présent" _m04_fichier_main docs/performances.md
check_cmd "docs/performances.md cite forks" _m04_fichier_main_contient docs/performances.md '[Ff]orks'
check_cmd "docs/performances.md cite le pipelining" _m04_fichier_main_contient docs/performances.md '[Pp]ipelining'
check_cmd "docs/performances.md contient un tableau de durées" \
  _m04_fichier_main_contient docs/performances.md '^\|.*\|[[:space:]]*[0-9]+([.,][0-9]+)?[[:space:]]*\|'

title "Cache de faits sur adm01"
_m04_cache="$HOME/.cache/ansible/faits"
check_output "cache de faits (.cache/ansible/faits) en 700" '^700$' stat -c '%a' "$_m04_cache"
check_cmd "le cache contient au moins trois hôtes du socle" \
  bash -c 'n=0; for h in gw01 adm01 dns01 git01 runner01; do ls "$1"/*"$h"* >/dev/null 2>&1 && n=$((n+1)); done; [ "$n" -ge 3 ]' _ "$_m04_cache"

title "Hygiène"
check_cmd "flotte de démonstration détruite (VMID 2042-2044)" _m04_aucune_vm 2042 2044
