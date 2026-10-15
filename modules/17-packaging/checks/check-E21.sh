# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E21.sh — M17-E21 « Panne : la production déploie la mauvaise image » : la prod correspond au
# rendu de origin/main, pods prêts, aucun réglage de débogage, contrôle de cohérence dans la CI.
# Lecture seule (kubectl diff --server-side est une simulation).

# shellcheck source=_m17-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m17-production.sh"

title "M17-E21 — La prod tourne ce qui est approuvé"
require_cmd git kubectl jq

if [[ -d "$_m17p_deploiement/.git" ]]; then
  check_cmd "kubectl diff --server-side -k overlays/prod (origin/main) : vide" _m17p_diff_overlay prod
else
  check_cmd "copie de travail $_m17p_deploiement présente" false
fi
_e21_d="$(_m17p_deploy mediagenda-prod mediagenda)" || _e21_d=""
check_cmd "prod : déploiement terminé, tous les pods prêts" _m17p_deploy_a_jour "$_e21_d"
check_cmd "prod : aucun réglage de débogage (DEBUG, format texte)" _m17p_jq "$_e21_d" \
  '[.spec.template.spec.containers[] | .env[]? | select((.name == "MEDIAGENDA_LOG_LEVEL" and .value == "DEBUG") or (.name == "MEDIAGENDA_LOG_FORMAT" and .value == "texte"))] | length == 0'
check_cmd "mediagenda/deploiement : dernier pipeline de main réussi" _m17p_gl_pipeline_ok mediagenda/deploiement main
check_cmd "mediagenda/deploiement : job de cohérence des images et des components réussi" \
  _m17p_gl_jobs_ok mediagenda/deploiement main 'image|coh[eé]rence|livraison|component'
check_cmd "panne M17-E21 close (lab/bin/break 17 21 --annuler après réparation)" _m17p_panne_close E21
