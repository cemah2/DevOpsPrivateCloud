# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E21.sh — M21-E21 : Revue, les règles d'alerte du stagiaire
# À lancer depuis adm01. Lecture seule : GitLab (branche revue-lucas, pipeline), fichier local de revue.

# shellcheck source=_m21-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-operationnel.sh"

title "M21-E21 — Revue : les règles d'alerte du stagiaire"
require_cmd jq curl yq

_m21o_e21_b=revue-lucas
_m21o_e21_defauts() {
  local n
  n="$(grep -Ec '^ *([0-9]+[.)] |[-*] |\| *[0-9]+ *\|)' "$_M21O_TRAVAIL/e21/revue.md" 2>/dev/null || true)"
  (( ${n:-0} >= 10 ))
}
check_cmd "revue ~/m21/e21/revue.md : relève au moins dix défauts (une ligne numérotée, une puce ou une ligne de tableau par défaut)" \
  _m21o_e21_defauts
check_cmd "branche $_m21o_e21_b dans plateforme/observabilite" _m21o_branche "$_M21O_P_OBS" "$_m21o_e21_b"

_m21o_e21_regles="$(_m21o_contenu "$_M21O_P_OBS" regles/alertes-lucas.yaml "$_m21o_e21_b" | yq -o=json '.' 2>/dev/null || true)"
check_cmd "regles/alertes-lucas.yaml (branche) : chaque alerte a for, gravite, equipe, runbook_url, sans irate" \
  _m21o_json "$_m21o_e21_regles" '[.spec.groups[].rules[] | select(.alert)] as $a
    | ($a | length) >= 1 and ($a | all(
        ((.for // "") != "") and (.labels.gravite // "" | test("^(critique|avertissement|info)$"))
        and ((.labels.equipe // "") != "") and (.annotations.runbook_url // "" | test("RB-21[0-9]"))
        and ((.expr | test("irate\\(")) | not)))'

# Les runbook_url pointent vers des fichiers qui existent sur main de plateforme/medisphere.
_m21o_e21_runbooks() {
  local u chemin n=0
  while IFS= read -r u; do
    [[ -n "$u" ]] || continue
    chemin="${u#*/-/blob/main/}"
    [[ "$chemin" != "$u" ]] || return 1
    _m21o_fichier "$_M21O_P_DOC" "$chemin" || return 1
    n=$((n + 1))
  done < <(jq -r '[.spec.groups[].rules[] | .annotations.runbook_url // empty] | unique[]' <<<"$_m21o_e21_regles" 2>/dev/null || true)
  (( n >= 1 ))
}
check_cmd "les runbook_url de la branche pointent vers des runbooks existants (plateforme/medisphere, main)" \
  _m21o_e21_runbooks
check_output "tests promtool des alertes corrigées sur la branche" 'lucas' \
  _m21o_arbre "$_M21O_P_OBS" tests "$_m21o_e21_b"
check_cmd "dernier pipeline de la branche $_m21o_e21_b réussi" _m21o_pipeline_ok "$_M21O_P_OBS" "$_m21o_e21_b"
check_cmd "le job tests-regles de ce pipeline a réussi" _m21o_job_ok "$_M21O_P_OBS" tests-regles "$_m21o_e21_b"
