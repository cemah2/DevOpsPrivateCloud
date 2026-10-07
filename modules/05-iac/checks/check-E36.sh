# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E36.sh — M05-E36 « Panne : "Error acquiring the state lock" » : aucun verrou ne subsiste
# sur les états socle et envs/lab-m05, aucun processus OpenTofu ne traîne sur adm01, le runbook
# du verrou bloqué existe. Lecture seule (interrogation S3 en HEAD, aucun verrou pris).

# shellcheck source=_m05-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-expert.sh"

title "M05-E36 — Verrous d'état libérés proprement"
require_cmd aws jq

# Un processus tofu lancé depuis plus d'une heure sur adm01 est suspect (session oubliée).
_m05_e36_pas_de_tofu_ancien() {
  ! ps -eo etimes=,args= 2>/dev/null | awk '$2 ~ /(^|\/)tofu$/ && $1 > 3600 { f = 1 } END { exit !f }'
}
_m05_e36_runbook() {
  local f
  f="$(find "$_m05x_depot/docs/socle/runbooks" -maxdepth 1 -name 'RB-050*.md' 2>/dev/null | head -n 1)"
  [[ -n "$f" ]] && grep -q 'force-unlock' "$f"
}

check_cmd "état socle : aucun objet de verrou (socle/terraform.tfstate.tflock)" _m05x_verrou_absent "$_m05x_cle_socle"
check_cmd "état envs/lab-m05 : aucun objet de verrou" _m05x_verrou_absent "$_m05x_cle_envs"
check_cmd "adm01 : aucun processus OpenTofu lancé depuis plus d'une heure" _m05_e36_pas_de_tofu_ancien
check_cmd "socle : l'état se lit normalement (tofu state list)" _m05x_tofu "$_m05x_socle" state list
check_cmd "documentation : runbook RB-050 (verrou bloqué) présent et traitant de force-unlock" _m05_e36_runbook
check_cmd "panne M05-E36 close (lab/bin/break 05 36 --annuler après réparation)" _m05x_aucune_panne_active E36
