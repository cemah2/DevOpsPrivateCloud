# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S13.sh — F1-S13 « Première livraison en production ».
# Lecture seule : /sante et /api/v1/creneaux de la production (GET, réponses non conservées),
# étiquettes et MR de GitLab, pods, Rollout, AnalysisRuns et Application de production (wb-checks),
# artefact et signature dans Harbor (robot des checks), gestionnaires de champs des objets.
#
# Variables : WB_F1_PROJET_API (mediagenda/api), WB_F1_PROJET_DEPLOIEMENT (mediagenda/deploiement),
# WB_F1_PROD_URL, WB_F1_HARBOR_DEPOT (medisphere/mediagenda-api).

# shellcheck source=_f1-cluster.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f1-cluster.sh"

title "F1-S13 — Première livraison en production"
require_cmd kubectl jq curl

_f1_s13_api="${WB_F1_PROJET_API:-mediagenda/api}"
_f1_s13_dep="${WB_F1_PROJET_DEPLOIEMENT:-mediagenda/deploiement}"
_f1_s13_harbor="${WB_F1_HARBOR_DEPOT:-medisphere/mediagenda-api}"
_f1_s13_ns=mediagenda-prod
_f1_s13_sel='app.kubernetes.io/name=mediagenda,app.kubernetes.io/component=api'

if ! _f1c_api_repond; then
  check_cmd "l'API de k8s-par1 répond au compte des checks" false
  return 0  # fichier sourcé par lab/bin/check : summary affiche le bilan
fi
_f1_s13_ne="$(_f1c_naissance_iso)"

# --- Version servie ------------------------------------------------------------------------------
_f1_s13_tag="$(_f1c_derniere_etiquette "$_f1_s13_api")"
_f1_s13_v="$(jq -r '.name // empty' <<<"${_f1_s13_tag:-null}" 2>/dev/null || true)"
_f1_s13_tag_e="$(_f1c_epoch "$(jq -r '.commit.created_at // .commit.committed_date // empty' <<<"${_f1_s13_tag:-null}" 2>/dev/null || true)")"
check_cmd "$_f1_s13_api : dernière étiquette ${_f1_s13_v:-?} publiée après la naissance du cluster" \
  bash -c '[[ "$1" =~ ^[0-9]+$ && "$2" =~ ^[0-9]+$ ]] && (( $1 > $2 ))' _ "${_f1_s13_tag_e:-x}" "$(_f1c_naissance || true)"
_f1_s13_sante="$(curl -sf --max-time 10 "$_f1c_prod_url/sante" 2>/dev/null || true)"
check_cmd "production : /sante renvoie la version ${_f1_s13_v:-?} ($(jq -r '.version // "?"' <<<"${_f1_s13_sante:-null}" 2>/dev/null || echo '?'))" \
  jq -e --arg v "${_f1_s13_v#v}" '(.version // "" | ltrimstr("v")) == $v and $v != ""' <<<"${_f1_s13_sante:-null}"
_f1_s13_cr="$(curl -sf --max-time 10 "$_f1c_prod_url/api/v1/creneaux?date=$(date -d '+7 days' +%F)" 2>/dev/null || true)"
check_cmd "production : /api/v1/creneaux renvoie le champ « nombre » (DEV-3113), égal à la taille de « libres »" \
  jq -e '(.nombre | type) == "number" and .nombre == (.libres | length)' <<<"${_f1_s13_cr:-null}"

# --- Image : condensé et signature -------------------------------------------------------------------
_f1_s13_pods="$(_f1c_kj -n "$_f1_s13_ns" pods -l "$_f1_s13_sel")"
[[ -n "$_f1_s13_pods" ]] || _f1_s13_pods='{"items":[]}'
check_cmd "pods de l'API en production : image désignée par condensé (@sha256:)" jq -e '
  (.items | length > 0) and all(.items[]; all(.spec.containers[] | select(.name == "api" or (.image | test("mediagenda-api"))); .image | test("@sha256:[0-9a-f]{64}$")))' \
  <<<"$_f1_s13_pods"
_f1_s13_digest="$(jq -r '[.items[].spec.containers[].image | select(test("mediagenda-api")) | capture("@(?<d>sha256:[0-9a-f]{64})").d] | unique | .[0] // empty' <<<"$_f1_s13_pods" 2>/dev/null || true)"
_f1_s13_art="$(harbor_api "projects/${_f1_s13_harbor%%/*}/repositories/$(_f1c_enc "${_f1_s13_harbor#*/}" | sed 's/%2F/%252F/g')/artifacts/${_f1_s13_digest:-absent}?with_accessory=true" 2>/dev/null || true)"
check_cmd "Harbor : l'image servie en production porte une signature attachée" \
  jq -e 'any(.accessories[]?; (.type // "") | test("signature"))' <<<"${_f1_s13_art:-null}"

# --- Rollout, analyse, Argo CD ---------------------------------------------------------------------------
check_cmd "Rollout mediagenda (production) : Healthy, toutes les répliques à jour" _f1c_kq \
  '.status.phase == "Healthy" and (.status.updatedReplicas // 0) == (.status.replicas // -1)' \
  -n "$_f1_s13_ns" rollouts.argoproj.io mediagenda
check_cmd "une analyse du canary a réussi en production après la naissance du cluster" _f1c_kq \
  "any(.items[]; .status.phase == \"Successful\" and .metadata.creationTimestamp > \"${_f1_s13_ne:-9999}\")" \
  -n "$_f1_s13_ns" analysisruns.argoproj.io
check_cmd "Application mediagenda-prod : Synced et Healthy" _f1c_app_saine mediagenda-prod

# _f1_s13_gestionnaires TYPE NOM — aucun champ géré par un kubectl (apply, edit, patch, scale…).
_f1_s13_gestionnaires() {
  local j
  j="$(kube -n "$_f1_s13_ns" get "$1" "$2" -o json --show-managed-fields 2>/dev/null || true)"
  [[ -n "$j" ]] && jq -e '.metadata.name != null and ([.metadata.managedFields[]?.manager] | all(startswith("kubectl") | not))' >/dev/null 2>&1 <<<"$j"
}
check_cmd "Rollout de production : aucun champ géré par un kubectl" _f1_s13_gestionnaires rollouts.argoproj.io mediagenda
check_cmd "Deployment de production : aucun champ géré par un kubectl" _f1_s13_gestionnaires deployment mediagenda

# --- Promotion par MR --------------------------------------------------------------------------------------
# _f1_s13_mr_prod — une MR fusionnée sur main après la naissance du cluster modifie overlays/prod/.
_f1_s13_mr_prod() {
  local p iid mrs
  p="$(_f1c_enc "$_f1_s13_dep")"
  mrs="$(gitlab_api "projects/$p/merge_requests?state=merged&target_branch=main&updated_after=${_f1_s13_ne:-9999}&per_page=50" 2>/dev/null || true)"
  while IFS= read -r iid; do
    [[ -n "$iid" ]] || continue
    gitlab_api "projects/$p/merge_requests/$iid/diffs?per_page=100" 2>/dev/null |
      jq -e 'any(.[]?; (.new_path // "") | startswith("overlays/prod/"))' >/dev/null 2>&1 && return 0
  done < <(jq -r --arg n "${_f1_s13_ne:-9999}" '.[]? | select((.merged_at // "") > $n) | .iid' <<<"${mrs:-[]}" 2>/dev/null || true)
  return 1
}
check_cmd "$_f1_s13_dep : une MR fusionnée après la naissance du cluster modifie overlays/prod/" _f1_s13_mr_prod
