# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # bash -c et regex : les $ sont évalués par le sous-shell, pas ici
#
# check-E19.sh — M04-E19 : Exploitation quotidienne : tags, limit, check, diff
# À lancer depuis adm01. Lecture seule : listes (hôtes, tâches, étiquettes) et site.yml en
# --check sur tout le socle (deux à quatre minutes).

# shellcheck source=_m04-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-operationnel.sh"

title "M04-E19 — Exploitation quotidienne : tags, limit, check, diff"
require_cmd git jq curl

check_cmd "playbooks/site.yml publié sur main" _m04_fichier_main playbooks/site.yml
check_cmd "site.yml importe les playbooks du socle (import_playbook)" \
  bash -c 'grep -c "import_playbook:" "$1/playbooks/site.yml" | grep -Eq "^[3-9]"' _ "$_M04_SRC"
_m04o_tags="$(_m04_ans ansible-playbook playbooks/site.yml --list-tags 2>/dev/null)" || true
for _m04o_t in base ssh pare_feu runner base_temps base_utilisateurs; do
  check_output "étiquette « $_m04o_t » disponible (--list-tags)" "(\\[|, )$_m04o_t(,|\\])" printf '%s\n' "$_m04o_tags"
done
_m04o_taches="$(_m04_ans ansible-playbook playbooks/site.yml --list-tasks --tags pare_feu 2>/dev/null)" || true
check_cmd "--tags pare_feu --list-tasks : les tâches du rôle pare_feu sont sélectionnées" \
  grep -Eq '^[[:space:]]+pare_feu : ' <<<"$_m04o_taches"
check_cmd "--tags pare_feu --list-tasks : aucune autre tâche de rôle (hors always)" \
  bash -c '! grep -E "^[[:space:]]+[a-z_]+ : " <<<"$1" | grep -v "^[[:space:]]*pare_feu : " | grep -vq "TAGS: \[always"' _ "$_m04o_taches"
check_cmd "docs/exploitation.md du projet : --check, --diff, --limit et --tags expliqués" \
  bash -c 'f="$1/docs/exploitation.md"; for m in --check --diff --limit --tags; do grep -q -- "$m" "$f" || exit 1; done' \
  _ "$_M04_SRC"

_m04o_sortie="$(_m04_simuler playbooks/site.yml)"
for _m04o_h in $_M04_SOCLE; do
  check_cmd "--check de site.yml sur $_m04o_h : socle convergé (aucun changement, aucun échec)" \
    _m04_recap "$_m04o_sortie" "$_m04o_h"
done
