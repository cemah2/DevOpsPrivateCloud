# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E16.sh — M20-E16 « Canary piloté par la Gateway API ». Lecture seule : Rollout, Services,
# HTTPRoute, Deployment et Application de recette et de prod (wb-checks).

# shellcheck source=_m20-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-operationnel.sh"

title "M20-E16 — Canary piloté par la Gateway API"
require_cmd jq kubectl curl

if ! _m20o_lisible rollouts.argoproj.io mediagenda-recette; then
  check_cmd "wb-checks lit les Rollouts (M20-E15)" false
else
  _e16_ns=mediagenda-recette
  _e16_ro="$(_m20o_obj "$_e16_ns" rollouts.argoproj.io mediagenda)"
  check_cmd "recette : Rollout mediagenda présent" test -n "$_e16_ro"
  check_cmd "Rollout : référence le Deployment mediagenda (workloadRef), réduction progressive" \
    _m20o_jq "$_e16_ro" '.spec.workloadRef.kind == "Deployment" and .spec.workloadRef.name == "mediagenda"
      and .spec.workloadRef.scaleDown == "progressively"'
  check_cmd "Rollout : routage par le greffon Gateway API sur l'HTTPRoute mediagenda" \
    _m20o_jq "$_e16_ro" '.spec.strategy.canary.trafficRouting.plugins["argoproj-labs/gatewayAPI"].httpRoute == "mediagenda"'
  check_cmd "Rollout : Services stable « mediagenda » et canary « mediagenda-canary »" \
    _m20o_jq "$_e16_ro" '.spec.strategy.canary.stableService == "mediagenda" and .spec.strategy.canary.canaryService == "mediagenda-canary"'
  check_cmd "Rollout : marches setWeight 10, 25, 50 dans cet ordre, avec des pauses" \
    _m20o_jq "$_e16_ro" '[.spec.strategy.canary.steps[] | .setWeight // empty] as $w
      | ($w | index(10)) != null and ($w | index(25)) != null and ($w | index(50)) != null
      and ($w | index(10)) < ($w | index(25)) and ($w | index(25)) < ($w | index(50))
      and ([.spec.strategy.canary.steps[] | select(has("pause"))] | length >= 3)'
  check_cmd "Rollout : au moins une révision livrée en canary (révision ≥ 2)" \
    _m20o_jq "$_e16_ro" '(.metadata.annotations["rollout.argoproj.io/revision"] // "0" | tonumber) >= 2'
  check_cmd "Rollout : Healthy, dernière révision promue (stable = courante)" \
    _m20o_jq "$_e16_ro" '.status.phase == "Healthy" and .status.stableRS == .status.currentPodHash'
  _e16_dep="$(_m20o_obj "$_e16_ns" deployment mediagenda)"
  check_cmd "Deployment mediagenda réduit à 0 réplica par le Rollout" _m20o_jq "$_e16_dep" '.spec.replicas == 0'
  _e16_svc="$(_m20o_obj "$_e16_ns" service mediagenda-canary)"
  check_cmd "Service mediagenda-canary : restreint à une révision (rollouts-pod-template-hash)" \
    _m20o_jq "$_e16_svc" '.spec.selector["rollouts-pod-template-hash"] != null'
  _e16_rt="$(_m20o_obj "$_e16_ns" httproutes.gateway.networking.k8s.io mediagenda)"
  check_cmd "HTTPRoute mediagenda : deux backendRefs (mediagenda, mediagenda-canary)" \
    _m20o_jq "$_e16_rt" '[.spec.rules[0].backendRefs[].name] | sort == ["mediagenda", "mediagenda-canary"]'
  check_cmd "HTTPRoute mediagenda : au repos, 100 % sur la révision stable" \
    _m20o_jq "$_e16_rt" '[.spec.rules[0].backendRefs[] | select(.name == "mediagenda-canary") | (.weight // 1)] == [0]'
  check_cmd "HTTPRoute mediagenda : acceptée par gw-par1, références résolues" \
    _m20o_jq "$_e16_rt" '([.status.parents[]?.conditions[]? | select(.type == "Accepted" and .status == "True")] | length > 0)
      and ([.status.parents[]?.conditions[]? | select(.type == "ResolvedRefs" and .status == "False")] | length == 0)'
  _e16_app="$(_m20o_app mediagenda-recette)"
  check_cmd "mediagenda-recette : Synced et Healthy (les poids réglés par le greffon n'ont pas créé d'écart)" \
    _m20o_sync_sante "$_e16_app"

  _e16_rop="$(_m20o_obj mediagenda-prod rollouts.argoproj.io mediagenda)"
  if [[ -n "$_e16_rop" ]]; then
    check_cmd "prod : Rollout mediagenda à 3 réplicas, dernière marche en promotion manuelle (pause sans durée)" \
      _m20o_jq "$_e16_rop" '.spec.replicas == 3 and (.spec.strategy.canary.steps | last | has("pause") and (.pause.duration == null))'
    check_cmd "prod : Rollout Healthy" _m20o_jq "$_e16_rop" '.status.phase == "Healthy"'
  else
    check_cmd "prod : Rollout mediagenda présent (MR et synchronisation manuelle de mediagenda-prod)" false
  fi
fi
