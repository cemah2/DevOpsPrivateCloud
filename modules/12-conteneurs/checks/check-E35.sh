# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E35.sh — M12-E35 « Panne : le conteneur s'arrête aussitôt » : la pile de recette de ctr01
# est revenue à un état sain et stable (API et MédiDoc démarrés, sans redémarrage), les points
# d'accès répondent depuis adm01, la panne est close. Lecture seule.

# shellcheck source=_m12-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-expert.sh"

title "M12-E35 — Les conteneurs de la recette démarrent et restent démarrés"
require_cmd jq curl ssh

if _m12x_recette_repond; then
  check_cmd "API : conteneur démarré et sain" _m12x_sain api
  check_cmd "MédiDoc : conteneur démarré" _m12x_sain doc
  check_cmd "migrations : dernière exécution terminée avec le code 0" \
    _m12x_jq '.services.migrations.statut == "exited" and .services.migrations.code == 0'
  check_cmd "API : aucun redémarrage pendant 30 s" _m12x_stable api 30
  check_cmd "MédiDoc : aucun redémarrage pendant 10 s" _m12x_stable doc 10
else
  skip "état des conteneurs" "Docker ne répond pas sur $_m12x_ctr01, ou la pile « recette » n'existe pas"
fi
check_http "API : /sante répond 200 depuis adm01" "$_m12x_url_api/sante" 200
check_http "API : /pret répond 200 (PostgreSQL et Valkey joignables)" "$_m12x_url_api/pret" 200
check_http "MédiDoc : /healthz répond 200 depuis adm01" "$_m12x_url_doc/healthz" 200
check_cmd "panne M12-E35 close (lab/bin/break 12 35 --annuler après réparation)" _m12x_aucune_panne_active E35
