# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E29.sh — M25-E29 « Monter de version la grappe sans coupure » : les trois nœuds et kms01
# SERVENT la 2.7.1 (version lue sur l'API, pas le paquet), descellés ; grappe saine ; versions
# épinglées sur main de plateforme/ansible ; RB-253 sur main avec un retour arrière par instantané.
# À lancer depuis adm01. Lecture seule : sys/health sans jeton, AppRole wb-checks (autopilot), GitLab.

# shellcheck source=_m25-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-production.sh"

title "M25-E29 — Monter de version la grappe sans coupure"
require_cmd curl jq
_m25p_connexion

_M25_E29_VERSION="${WB_M25_VERSION_CIBLE:-2.7.1}"
for _m25_e29_n in "${_M25P_NOEUDS[@]}" "$_M25P_KMS"; do
  check_cmd "$_m25_e29_n : sert OpenBao $_M25_E29_VERSION, descellé" \
    _m25p_jq "$(_m25p_sante "$_m25_e29_n")" '.version == $v and .sealed == false' --arg v "$_M25_E29_VERSION"
done
check_cmd "grappe saine après la montée (autopilot, tolérance ≥ 1)" \
  _m25p_jq "$(_m25p_bao sys/storage/raft/autopilot/state)" '.data.healthy == true and .data.failure_tolerance >= 1'
for _m25_e29_g in role_coffre role_kms; do
  check_output "$_m25_e29_g : version $_M25_E29_VERSION épinglée sur main de $_M25P_ANSIBLE" \
    "openbao_version: \"?${_M25_E29_VERSION//./\\.}\"?" \
    _m25p_fichier "$_M25P_ANSIBLE" "inventories/lab/group_vars/$_m25_e29_g/openbao.yml"
done
check_cmd "RB-253 sur main : ordre du roulement, kms01, retour arrière par instantané" \
  _m25p_doc "$_M25P_DOC" "$_M25P_RB" 'RB-253[^/]*\.md$' 25 'step-down|passage de t[ée]moin' 'kms01' 'instantan' 'retour arri'
