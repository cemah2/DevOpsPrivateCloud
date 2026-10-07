# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E23.sh — M04-E23 : Déléguer et orchestrer : delegate_to, run_once
# À lancer depuis adm01. Lecture seule : le playbook, les instantanés sur pve01 (qm
# listsnapshot), le journal des changements, et un passage en --check limité à dns01 (en
# --check, ni instantané ni écriture dans le journal).

# shellcheck source=_m04-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-operationnel.sh"

title "M04-E23 — Déléguer et orchestrer : delegate_to, run_once"
require_cmd git jq curl

_m04o_pb="playbooks/changement-socle.yml"
check_cmd "$_m04o_pb publié sur main" _m04_fichier_main "$_m04o_pb"
check_cmd "le playbook délègue (delegate_to) et regroupe (run_once)" \
  bash -c 'grep -q "delegate_to:" "$1" && grep -q "run_once:" "$1"' _ "$_M04_SRC/$_m04o_pb"
check_cmd "le playbook vérifie depuis dns01 et depuis adm01 (deux délégations différentes)" \
  bash -c 'grep -Eq "delegate_to:[[:space:]]*dns01" "$1" && grep -Eq "delegate_to:[[:space:]]*(localhost|adm01)" "$1"' \
  _ "$_M04_SRC/$_m04o_pb"
check_cmd "sans numéro de changement, le playbook refuse de démarrer" \
  _m04o_echoue_avec 'changement' ansible-playbook "$_m04o_pb" --check --limit dns01

check_ssh "pve01 : au moins une VM du socle a un instantané de changement (chg-…)" "${WB_PVE_HOST:-pve01}" \
  'for i in 1000 1001 1002 1004 1007; do qm listsnapshot "$i" 2>/dev/null | grep -Eq "chg-[0-9]+" && exit 0; done; exit 1'
check_cmd "journal des changements (plateforme/medisphere) : une ligne par changement appliqué" \
  bash -c 'grep -Eq "^\| [0-9]{4}-[0-9]{2}-[0-9]{2} .*\| (CHG|INC)-[0-9]+ \|" "$1"/docs/socle/journal/*.md' _ "${WB_DEPOT:-$HOME/medisphere}"

_m04o_sortie="$(_m04_simuler "$_m04o_pb" -e changement=CHG-000 --limit dns01)"
check_cmd "--check -e changement=CHG-000 --limit dns01 : enveloppe et vérifications sans échec" \
  jq -e '.stats.dns01 as $s | $s != null and $s.failures == 0 and $s.unreachable == 0' <<<"$_m04o_sortie"
