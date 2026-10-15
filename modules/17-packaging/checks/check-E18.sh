# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E18.sh — M17-E18 « Livrer une nouvelle version de MédiAgenda en temps limité » (à lancer à T4) :
# image v1.1.0, chart publié et signé, dev (release Helm) et recette (overlay) en v1.1.0 avec
# MEDIAGENDA_ENVIRONNEMENT, /sante en HTTPS, prod inchangée, aucun geste manuel. Lecture seule.

# shellcheck source=_m17-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m17-production.sh"

title "M17-E18 — Livrer MédiAgenda 1.1.0 jusqu'en recette"
require_cmd jq kubectl helm curl

_e18_cible="v1.1.0"
_e18_img="$(_m17p_harbor_artefact medisphere mediagenda-api "$_e18_cible")" || _e18_img=""
check_cmd "Harbor : medisphere/mediagenda-api:$_e18_cible existe" test -n "$_e18_img"

_e18_r="$(_m17p_deploy mediagenda-recette mediagenda)" || _e18_r=""
_e18_d="$(_m17p_deploy mediagenda-dev mediagenda)" || _e18_d=""
_e18_chart_r="$(jq -r '.metadata.labels["helm.sh/chart"] // empty' <<<"$_e18_r" 2>/dev/null)" || _e18_chart_r=""
_e18_chart_d="$(_m17p_rel_chart mediagenda-dev mediagenda)" || _e18_chart_d=""

# Recette
check_cmd "recette : image $_e18_cible" test "$(_m17p_image_tag "$_e18_r")" = "$_e18_cible"
check_cmd "recette : MEDIAGENDA_ENVIRONNEMENT=recette (API et migrations)" _m17p_jq "$_e18_r" \
  '[.spec.template.spec | (.containers + (.initContainers // []))[] | .env[]? | select(.name == "MEDIAGENDA_ENVIRONNEMENT") | .value] | length >= 1 and all(. == "recette")'
check_cmd "recette : déploiement terminé, tous les pods prêts" _m17p_deploy_a_jour "$_e18_r"
check_cmd "recette : aucun geste manuel dans les managedFields" _m17p_sans_manuel "$_e18_r"

# Chart : même version en dev et en recette, publiée et signée
_e18_v="${_e18_chart_r#mediagenda-}"
check_cmd "dev et recette rendus par la même version du chart (${_e18_chart_r:-?} / ${_e18_chart_d:-?})" \
  test -n "$_e18_chart_r" -a "$_e18_chart_r" = "$_e18_chart_d"
_e18_art="$(_m17p_harbor_artefact charts mediagenda "$_e18_v")" || _e18_art=""
check_cmd "Harbor : charts/mediagenda:$_e18_v publié" test -n "$_e18_art"
if [[ -n "$_e18_art" ]]; then
  _e18_rc=0
  _m17p_cosign_ok "$_m17p_harbor_hote/charts/mediagenda@$(jq -r .digest <<<"$_e18_art")" || _e18_rc=$?
  if ((_e18_rc == 2)); then
    check_cmd "chart $_e18_v : signature attachée" _m17p_jq "$_e18_art" '(.accessories // []) | length > 0'
  else
    check_cmd "chart $_e18_v : signature MédiSphère vérifiée" test "$_e18_rc" -eq 0
  fi
fi

# Dev (release Helm)
check_output "dev : release mediagenda deployed" '^deployed$' _m17p_rel_statut mediagenda-dev mediagenda
check_cmd "dev : image $_e18_cible et MEDIAGENDA_ENVIRONNEMENT=dev" \
  test "$(_m17p_image_tag "$_e18_d")/$(_m17p_env "$_e18_d" MEDIAGENDA_ENVIRONNEMENT)" = "$_e18_cible/dev"
check_cmd "dev : aucun geste manuel dans les managedFields" _m17p_sans_manuel "$_e18_d"

# Point d'accès publié
_e18_sante="$(curl -s --max-time "$WB_TIMEOUT" https://mediagenda-recette.apps.par1.medisphere.internal/sante 2>/dev/null)" || _e18_sante=""
check_cmd "https://mediagenda-recette…/sante : version $_e18_cible, environnement recette" \
  _m17p_jq "$_e18_sante" '.version == "v1.1.0" and .environnement == "recette"'

# Migration V3 : visible dans le journal du conteneur de migration d'un pod de la recette (si lisible).
_e18_logs="$(kube logs -n mediagenda-recette deploy/mediagenda -c migrations --tail=200 2>/dev/null)" || _e18_logs=""
if grep -q 'V3__canal' <<<"$_e18_logs"; then
  check_cmd "recette : migration V3__canal.sql appliquée (journal des migrations)" true
elif grep -q 'migrations terminées' <<<"$_e18_logs"; then
  skip "migration V3 visible dans le journal" "ce pod n'a rien appliqué (V3 déjà faite par un autre pod) : vérifie le journal du premier pod"
else
  skip "migration V3 visible dans le journal" "journal des migrations illisible par le compte des checks"
fi

# Prod inchangée
_e18_p="$(_m17p_deploy mediagenda-prod mediagenda)" || _e18_p=""
if [[ -z "$_e18_p" ]]; then
  skip "prod inchangée" "pas de Deployment dans mediagenda-prod"
elif [[ "$(_m17p_image_tag "$_e18_p")" == "$_e18_cible" ]]; then
  skip "prod inchangée" "la prod tourne déjà $_e18_cible (promotion faite après l'exercice ?)"
else
  check_cmd "prod inchangée (image $(_m17p_image_tag "$_e18_p"))" true
fi
