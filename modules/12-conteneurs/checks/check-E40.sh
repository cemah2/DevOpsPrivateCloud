# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E40.sh — M12-E40 « Panne : le service Quadlet ne démarre pas » : sur ctr02, le témoin
# recette-cache du compte app est généré sans erreur par Quadlet, actif, tiré par default.target
# (il revient au démarrage), et la persistance de session (linger) de app est active. Lecture seule.

# shellcheck source=_m12-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-expert.sh"

title "M12-E40 — Le service Quadlet recette-cache démarre et survit au redémarrage"
require_cmd jq ssh

if _m12x_joignable "$_m12x_ctr02"; then
  check_cmd "compte app présent" _m12x_cache_jq "$_m12x_ctr02" '.app == true'
  check_cmd "persistance de session (linger) active pour app" _m12x_cache_jq "$_m12x_ctr02" '.linger == "yes"'
  check_cmd "Quadlet génère recette-cache sans erreur (essai à blanc)" _m12x_cache_jq "$_m12x_ctr02" '.generateur == 1'
  check_cmd "recette-cache tiré par default.target (redémarre avec le gestionnaire de app)" \
    _m12x_cache_jq "$_m12x_ctr02" '.voulu == 1'
  check_cmd "service recette-cache actif" _m12x_cache_jq "$_m12x_ctr02" '.actif == "active"'
  check_cmd "Valkey répond (PONG)" _m12x_cache_jq "$_m12x_ctr02" '.pong == "PONG"'
else
  skip "témoin recette-cache" "$_m12x_ctr02 ne répond pas en SSH (avec sudo)"
fi
check_cmd "panne M12-E40 close (lab/bin/break 12 40 --annuler après réparation)" _m12x_aucune_panne_active E40
