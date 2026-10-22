# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E36.sh — M19-E36 « Panne : le job échoue avant le script » : gestionnaire prêt, image helper
# prise dans un projet Harbor existant, compte de service ci-job présent et sans jeton, canari par
# Harbor et vert, RB-195, panne close. Lecture seule.

# shellcheck source=_m19-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-expert.sh"

title "M19-E36 — Les jobs passent la préparation"
require_cmd jq kubectl curl

if _m19x_api_repond; then
  check_cmd "gestionnaire du runner $_m19x_runner : Deployment entièrement disponible" _m19x_runner_deploy_pret
  _m19_e36_helper="$(_m19x_toml_valeur helper_image)"
  if [[ -n "$_m19_e36_helper" ]]; then
    check_cmd "image helper tirée par Harbor (registry.par1.medisphere.internal)" \
      bash -c '[[ "$1" == registry.par1.medisphere.internal/* ]]' _ "$_m19_e36_helper"
    _m19_e36_projet="$(cut -d/ -f2 <<<"$_m19_e36_helper")"
    _m19_e36_projet_existe() { harbor_api "projects?name=$1" 2>/dev/null | jq -e --arg p "$1" 'any(.[]; .name == $p)' >/dev/null 2>&1; }
    check_cmd "image helper : le projet Harbor « $_m19_e36_projet » existe" _m19_e36_projet_existe "$_m19_e36_projet"
  else
    skip "image helper" "pas de helper_image dans le gabarit : image par défaut du runner (par le miroir des nœuds)"
  fi
  check_cmd "compte de service ci-job présent dans ci-jobs, sans montage automatique de jeton" \
    _m19x_kq '.automountServiceAccountToken == false' -n ci-jobs serviceaccount ci-job
  check_cmd "aucun pod de ci-jobs en ErrImagePull ou ImagePullBackOff" \
    _m19x_kq '[.items[].status | (.containerStatuses // []) + (.initContainerStatuses // []) | .[].state.waiting.reason // empty
              | select(test("ErrImagePull|ImagePullBackOff"))] | length == 0' -n ci-jobs pods
else
  skip "objets Kubernetes du runner" "l'API de k8s-par1 ne répond pas au compte des checks"
fi
if _m19x_temoin_existe; then
  _m19_e36_image_harbor() { ! _m19x_brut "$_m19x_temoin" .gitlab-ci.yml main | grep -Eq 'image: *(docker\.io|quay\.io|ghcr\.io)/'; }
  check_cmd "témoin : le canari n'utilise pas d'image hors de Harbor" _m19_e36_image_harbor
  check_cmd "témoin : dernier pipeline de main réussi" _m19x_canari_vert
else
  skip "témoin $_m19x_temoin" "absent : il est créé à la première injection (lab/bin/break 19 36)"
fi
check_cmd "RB-195 : section sur les échecs avant le script (helper, compte de service, admission, certificats)" \
  _m19x_doc_contient 'RB-195*.md' 'helper'
check_cmd "panne M19-E36 close (lab/bin/break 19 36 --annuler après réparation)" _m19x_aucune_panne_active E36
