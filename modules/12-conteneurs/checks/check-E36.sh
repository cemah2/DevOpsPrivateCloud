# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E36.sh — M12-E36 « Panne : "permission denied" sur le volume » : la base de recette de ctr01
# écrit dans son volume (propriétaire 999, mode 700), le témoin recette-cache de ctr02 et de ctr03
# (s'il existe) écrit ses données sans privilège supplémentaire, sans refus SELinux récent.
# Lecture seule.

# shellcheck source=_m12-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-expert.sh"

title "M12-E36 — Les conteneurs écrivent dans leurs volumes"
require_cmd jq curl ssh

if _m12x_recette_repond; then
  check_cmd "ctr01 : base de recette démarrée et saine" _m12x_sain db
  check_cmd "ctr01 : données de la base à l'UID 999, mode 700 (ni root, ni droits élargis)" \
    _m12x_jq '.pgdata == "999 700"'
  check_cmd "ctr01 : base sans redémarrage pendant 20 s" _m12x_stable db 20
else
  skip "base de recette" "Docker ne répond pas sur $_m12x_ctr01, ou la pile « recette » n'existe pas"
fi
check_http "ctr01 : /pret de l'API répond 200" "$_m12x_url_api/pret" 200

_m12_e36_cache() {
  local h="$1"
  check_cmd "$h : service recette-cache actif (compte app)" _m12x_cache_jq "$h" '.actif == "active"'
  check_cmd "$h : Valkey répond (PONG)" _m12x_cache_jq "$h" '.pong == "PONG"'
  check_cmd "$h : ~app/recette/cache n'appartient pas à app (UID du conteneur, pas root du conteneur)" \
    _m12x_cache_jq "$h" '.proprietaire >= 0 and .proprietaire != .uid_app'
}
if _m12x_joignable "$_m12x_ctr02"; then
  _m12_e36_cache "$_m12x_ctr02"
else
  skip "témoin de $_m12x_ctr02" "$_m12x_ctr02 ne répond pas en SSH"
fi
if _m12x_joignable "$_m12x_ctr03"; then
  _m12_e36_cache "$_m12x_ctr03"
  check_cmd "$_m12x_ctr03 : répertoire de données étiqueté container_file_t" \
    _m12x_cache_jq "$_m12x_ctr03" '.contexte | test("container_file_t")'
  check_cmd "$_m12x_ctr03 : aucun refus AVC récent pour Valkey" _m12x_cache_jq "$_m12x_ctr03" '.avc == 0'
else
  skip "témoin de $_m12x_ctr03" "$_m12x_ctr03 ne répond pas en SSH"
fi
check_cmd "panne M12-E36 close (lab/bin/break 12 36 --annuler après réparation)" _m12x_aucune_panne_active E36
