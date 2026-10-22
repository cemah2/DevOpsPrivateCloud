# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E15.sh — M21-E15 : Écrire de bonnes alertes
# À lancer depuis adm01. Lecture seule : règles chargées par le Prometheus du cluster, GitLab.

# shellcheck source=_m21-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-operationnel.sh"

title "M21-E15 — Écrire de bonnes alertes"
require_cmd jq curl

_m21o_e15_r="$(_m21o_regles alert)"
for _m21o_e15_a in MediagendaTauxErreurEleve MediagendaLatenceElevee MediagendaIndisponible \
  MediagendaPodsNonPrets CibleInjoignable DisqueBientotPlein CertificatBientotExpire; do
  check_cmd "$_m21o_e15_a : chargée, gravite et equipe, resume, description, runbook_url, for ≥ 5 min" \
    _m21o_json "$_m21o_e15_r" --arg a "$_m21o_e15_a" '
      [.data.groups[].rules[] | select(.name == $a)] as $x
      | ($x | length) >= 1
      and ($x | all(
          (.labels.gravite // "" | test("^(critique|avertissement|info)$"))
          and (.labels.equipe // "" | test("^(plateforme|mediagenda|medidoc)$"))
          and ((.annotations.resume // "") != "") and ((.annotations.description // "") != "")
          and (.annotations.runbook_url // "" | test("RB-21[0-9]"))
          and ((.duration // 0) >= 300)))'
done
check_cmd "aucune de ces alertes n'utilise irate" _m21o_json "$_m21o_e15_r" '
  [.data.groups[].rules[] | select(.name | test("^(Mediagenda|CibleInjoignable|DisqueBientotPlein|CertificatBientotExpire)")) | .query]
  | length > 0 and all(test("irate\\(") | not)'
check_cmd "MediagendaIndisponible couvre la disparition des cibles (absent)" _m21o_json "$_m21o_e15_r" '
  any(.data.groups[].rules[]; .name == "MediagendaIndisponible" and (.query | test("absent\\(")))'
check_cmd "règles chargées sans erreur" _m21o_json "$_m21o_e15_r" '
  [.data.groups[].rules[] | select(.name | test("^(Mediagenda|CibleInjoignable|DisqueBientotPlein|CertificatBientotExpire)")) | select(.health == "err")] | length == 0'
check_cmd "plateforme/observabilite : dernier pipeline de main réussi" _m21o_pipeline_ok "$_M21O_P_OBS"
check_cmd "plateforme/observabilite : le job tests-regles a réussi dans ce pipeline" _m21o_job_ok "$_M21O_P_OBS" tests-regles
