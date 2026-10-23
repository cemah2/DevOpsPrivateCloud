# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E23.sh — M29-E23 « Astreinte : la journée de jeu réveille une vraie faiblesse » : plus aucune
# expérience active sur la recette, journée de jeu automatique arrêtée, API de recette rétablie (vivacité
# sur /sante, ≥ 2 pods prêts, aucun redémarrage récent, HPA minReplicas ≥ 2), overlay recette sans le
# changement fautif, post-mortem INC-5623, panne close. Lecture seule.

# shellcheck source=_m29-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m29-expert.sh"

title "M29-E23 — Astreinte : recette rétablie, post-mortem publié"
require_cmd kubectl jq curl

if ! _m29p_api_repond; then
  skip "recette de MédiAgenda" "l'API ne répond pas au compte des checks"
else
  if _m29p_lit_chaos; then
    check_cmd "aucune expérience, aucun Schedule ni Workflow actif visant la recette" \
      bash -c '[[ "$(jq "length" <<<"$1")" == 0 ]]' _ "$(_m29x_chaos_actifs)"
  else
    skip "expériences actives" "le compte des checks ne lit pas chaos-mesh.org"
  fi
  check_cmd "API de recette : au moins deux pods prêts" _m29p_kq \
    '[.items[] | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length >= 2' \
    -n "$_m29p_recette" pods -l "$_m29x_api_sel"
  check_cmd "API de recette : sonde de vivacité sur /sante (pas sur /pret)" _m29p_kq \
    '(.items | length) > 0 and all(.items[]; all(.spec.containers[] | select(.livenessProbe != null); .livenessProbe.httpGet.path == "/sante"))' \
    -n "$_m29p_recette" pods -l "$_m29x_api_sel"
  check_cmd "API de recette : aucun conteneur redémarré dans les 15 dernières minutes" _m29p_kq \
    '[.items[].status.containerStatuses[]? | .lastState.terminated.finishedAt // empty | fromdateiso8601
      | select(. > (now - 900))] | length == 0' -n "$_m29p_recette" pods -l "$_m29x_api_sel"
  check_cmd "HPA de la recette : minReplicas ≥ 2" _m29p_kq \
    '(.items | length) > 0 and all(.items[]; (.spec.minReplicas // 1) >= 2)' -n "$_m29p_recette" horizontalpodautoscalers
fi
_m29_e23_overlay() {
  local c
  c="$(_m29p_fichier_main mediagenda/deploiement overlays/recette/kustomization.yaml 2>/dev/null)" || return 1
  ! grep -q 'value: /pret' <<<"$c" && ! grep -Eq 'path: /spec/minReplicas' <<<"$c"
}
check_cmd "mediagenda/deploiement : l'overlay recette ne surcharge plus la vivacité ni minReplicas" _m29_e23_overlay
check_cmd "post-mortem INC-5623 publié (main) : causes (déclencheur, défaut latent, conception), /pret, actions" \
  _m29p_doc docs/qualite/post-mortems 'INC-5623' '/pret' 'Valkey' '^#+ .*Cause' '^#+ .*Action'
check_cmd "panne M29-E23 close (lab/bin/break 29 23 --annuler après réparation)" _m29x_aucune_panne_active E23
