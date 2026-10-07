# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées par bash -c
#
# check-E25.sh — M04-E25 « Mises à jour progressives : serial et tolérance aux échecs »
# Le playbook est sur main avec lots, tolérance nulle et contrôle depuis le contrôleur ; le
# journal des déploiements est tenu une fois par exécution ; si la flotte existe encore (elle
# est détruite à la fin de l'E26), ses trois nœuds sont en service sur la même version.

# shellcheck source=_m04-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-production.sh"

title "M04-E25 — Mises à jour progressives"
require_cmd jq ssh curl
_m04_charger

title "Playbook (branche main)"
check_cmd "playbooks/maj-progressive.yml présent sur main" _m04_fichier_main playbooks/maj-progressive.yml
check_cmd "exécution par lots (serial)" _m04_fichier_main_contient playbooks/maj-progressive.yml '^[[:space:]]*serial:'
check_cmd "tolérance d'échec explicite (max_fail_percentage ou any_errors_fatal)" \
  _m04_fichier_main_contient playbooks/maj-progressive.yml '^[[:space:]]*(max_fail_percentage|any_errors_fatal):'
check_cmd "contrôle de santé HTTP délégué au contrôleur" \
  _m04_fichier_main_contient playbooks/maj-progressive.yml 'delegate_to:[[:space:]]*localhost'
check_cmd "contrôle de santé par ansible.builtin.uri" \
  _m04_fichier_main_contient playbooks/maj-progressive.yml 'ansible\.builtin\.uri'

title "Journal des déploiements (~/m04/e25/deploiements.log)"
_m04_journal="$HOME/m04/e25/deploiements.log"
check_cmd "le journal existe et compte au moins deux déploiements" \
  bash -c '[ "$(grep -c "version=" "$1" 2>/dev/null)" -ge 2 ]' _ "$_m04_journal"
# Une ligne par exécution : deux lignes consécutives ne portent pas le même horodatage.
check_cmd "une ligne par exécution, pas une par nœud (horodatages distincts)" \
  bash -c 'test -s "$1" && [ -z "$(awk "{print \$1}" "$1" | uniq -d)" ]' _ "$_m04_journal"

title "Flotte de démonstration"
if _m04_existe 2042 || _m04_existe 2043 || _m04_existe 2044; then
  for _m04_v in 2042 2043 2044; do
    check_cmd "VM $_m04_v : étiquettes env-m04 et flotte" \
      _m04_vm_filtre "$_m04_v" '(.tags // "" | split(";")) as $t | ($t | index("env-m04")) and ($t | index("flotte"))'
  done
  _m04_versions=""
  for _m04_ip in 10.10.99.42 10.10.99.43 10.10.99.44; do
    check_output "$_m04_ip : /sante répond « ok <version> »" '^ok [^ ]+$' \
      curl -sf --max-time "$WB_TIMEOUT" "http://$_m04_ip/sante"
    _m04_versions+="$(curl -sf --max-time "$WB_TIMEOUT" "http://$_m04_ip/sante" 2>/dev/null || echo "?")"$'\n'
  done
  check_cmd "les trois nœuds servent la même version" \
    bash -c '[ "$(printf "%s" "$1" | sed "/^$/d" | sort -u | wc -l)" -eq 1 ] && ! grep -q "?" <<<"$1"' _ "$_m04_versions"
else
  skip "flotte en service sur une même version" "flotte détruite (fin de l'E26)"
fi
