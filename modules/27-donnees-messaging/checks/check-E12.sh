# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E12.sh — M27-E12 : runbook RB-270 (maintenance et bascule de PostgreSQL)
# À lancer depuis adm01. Lecture seule : documentation sur main de plateforme/medisphere. Contrôle de
# PRÉSENCE et de structure : la qualité d'un runbook se juge en le déroulant (étape 3 de l'énoncé).

# shellcheck source=_m27-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m27-operationnel.sh"

title "M27-E12 — Runbook : maintenance et bascule de PostgreSQL"
require_cmd jq curl

_m27o_e12_rb="${_M27D_DOC}/runbooks/RB-270-postgresql-maintenance-bascule.md"
_m27o_e12_c="$(_m27d_contenu_main "$_M27D_P_DOC" "$_m27o_e12_rb")"
if [[ -z "$_m27o_e12_c" ]]; then
  _ko "plateforme/medisphere (main) : $_m27o_e12_rb absent"
else
  _ok "plateforme/medisphere (main) : $_m27o_e12_rb"
  check_cmd "RB-270 : état du Cluster (kubectl cnpg status)" bash -c 'grep -q "kubectl cnpg status" <<<"$1"' _ "$_m27o_e12_c"
  check_cmd "RB-270 : bascule volontaire (kubectl cnpg promote)" bash -c 'grep -q "kubectl cnpg promote" <<<"$1"' _ "$_m27o_e12_c"
  check_cmd "RB-270 : procédures planifiées (drain d'un nœud)" bash -c 'grep -Eq "kubectl drain" <<<"$1"' _ "$_m27o_e12_c"
  check_cmd "RB-270 : bascule subie (failover)" bash -c 'grep -Eqi "subie|failover" <<<"$1"' _ "$_m27o_e12_c"
  check_cmd "RB-270 : interdits" bash -c 'grep -Eqi "interdit|ne jamais|jamais" <<<"$1"' _ "$_m27o_e12_c"
  check_cmd "RB-270 : escalade" bash -c 'grep -Eqi "escalade" <<<"$1"' _ "$_m27o_e12_c"
  check_cmd "RB-270 : des durées mesurées (secondes) et plus de valeur à compléter (<N>)" bash -c '
    grep -Eq "[0-9]+([,.][0-9]+)? ?s([^a-zA-Z]|$)" <<<"$1" && ! grep -q "<N>" <<<"$1"' _ "$_m27o_e12_c"
  check_cmd "RB-270 : historique daté (test à froid)" bash -c '
    grep -Eqi "historique" <<<"$1" && grep -Eq "20[0-9]{2}-[0-9]{2}-[0-9]{2}" <<<"$1"' _ "$_m27o_e12_c"
fi
if [[ -n "$(_m27d_contenu_main "$_M27D_P_DOC" "${_M27D_DOC}/runbooks/RB-271-rabbitmq-redemarrage-roulement.md")" ]]; then
  _ok "facultatif : RB-271 (redémarrage de RabbitMQ par roulement) présent"
else
  skip "RB-271 (RabbitMQ)" "facultatif, absent"
fi
check_cmd "postgresql.md renvoie vers RB-270" _m27d_doc_contient "${_M27D_DOC}/postgresql.md" 'RB-270'
