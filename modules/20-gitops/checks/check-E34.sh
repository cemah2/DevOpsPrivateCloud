# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E34.sh — M20-E34 « Une mise en production en temps limité » (CHG-2134), à lancer à T1.
# Lecture seule : ~/m20/e34/T0 et ~/m20/e34/journal.md d'adm01 ; Application mediagenda-prod,
# Deployments mediagenda de recette et de production, Rollout, ReplicaSets, AnalysisRuns, HTTPRoute
# (wb-checks) ; MR et fichiers de mediagenda/deploiement, documentation (GitLab) ; Mailpit.
# Chaque tâche vaut ses points si TOUS ses contrôles passent ; l'exercice est validé à 70 points.

# shellcheck source=_m20-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-production.sh"

title "M20-E34 — Une mise en production en temps limité"
require_cmd kubectl jq curl
check_cmd "l'API du cluster répond (readyz)" _m20p_joignable

_M20_E34_DIR="${WB_M20_E34_DIR:-$HOME/m20/e34}"
_m20_e34_t0_txt="$(head -1 "$_M20_E34_DIR/T0" 2>/dev/null || true)"
_m20_e34_t0="$(_m20p_epoch "$_m20_e34_t0_txt" || true)"
check_output "T0 lisible dans $_M20_E34_DIR/T0 (${_m20_e34_t0_txt:-absent})" '^[0-9]+$' echo "${_m20_e34_t0:-}"
_m20_e34_t0="${_m20_e34_t0:-9999999999}"
_m20_e34_score=0
_m20_e34_max=0

# _m20_e34_tache NUM POIDS TITRE CONTRÔLE… — chaque CONTRÔLE est une fonction ; la tâche rapporte POIDS
# si toutes réussissent. Affichage propre à l'exercice (ne compte pas dans le bilan OK/KO).
_m20_e34_tache() {
  local num="$1" poids="$2" titre="$3" f echec=""
  shift 3
  _m20_e34_max=$((_m20_e34_max + poids))
  for f in "$@"; do
    if ! "$f" >/dev/null 2>&1; then echec="${echec:+$echec, }${f#_m20_e34_}"; fi
  done
  if [[ -z "$echec" ]]; then
    _m20_e34_score=$((_m20_e34_score + poids))
    printf '  [%2d/%2d] tâche %d — %s\n' "$poids" "$poids" "$num" "$titre"
  else
    printf '  [ 0/%2d] tâche %d — %s (en défaut : %s)\n' "$poids" "$num" "$titre" "$echec"
  fi
}

# _m20_e34_apres DATE — la date est postérieure ou égale à T0.
_m20_e34_apres() { local e; e="$(_m20p_epoch "$1")" || return 1; (( e >= _m20_e34_t0 )); }

# Lectures (une fois).
_M20_E34_DEP=mediagenda/deploiement
_m20_e34_app="$(_m20p_app mediagenda-prod)"
_m20_e34_dep_prod="$(_m20p_json -n mediagenda-prod get deployment mediagenda)"
_m20_e34_dep_rec="$(_m20p_json -n mediagenda-recette get deployment mediagenda)"
_m20_e34_ro="$(_m20p_json -n mediagenda-prod get rollouts.argoproj.io mediagenda)"
_m20_e34_rs="$(_m20p_json -n mediagenda-prod get replicasets)"
_m20_e34_ar="$(_m20p_json -n mediagenda-prod get analysisruns.argoproj.io)"
_m20_e34_route="$(_m20p_json -n mediagenda-prod get httproutes.gateway.networking.k8s.io mediagenda)"
_m20_e34_t0_iso="$(date -u -d "@$_m20_e34_t0" +%FT%TZ 2>/dev/null || echo 2099-01-01T00:00:00Z)"
_m20_e34_mrs="$(gitlab_api "projects/$(_m20p_uri "$_M20_E34_DEP")/merge_requests?state=merged&target_branch=main&updated_after=$_m20_e34_t0_iso&per_page=20" \
  2>/dev/null || echo '[]')"
_m20_e34_main="$(gitlab_api "projects/$(_m20p_uri "$_M20_E34_DEP")/repository/branches/main" 2>/dev/null \
  | jq -r '.commit.id // empty' 2>/dev/null || true)"
_m20_e34_image() { jq -r '.spec.template.spec.containers[] | select(.name == "api" or (.image | test("mediagenda-api"))) | .image' <<<"$1" 2>/dev/null | head -1; }
_m20_e34_img_prod="$(_m20_e34_image "$_m20_e34_dep_prod" || true)"
_m20_e34_img_rec="$(_m20_e34_image "$_m20_e34_dep_rec" || true)"

# Tâche 1 — préparer
_m20_e34_t1_journal() {
  grep -q 'CHG-2134' "$_M20_E34_DIR/journal.md" && grep -Eq 'sha256:[0-9a-f]{64}' "$_M20_E34_DIR/journal.md"
}
# Tâche 2 — MR de promotion fusionnée après T0, qui touche overlays/prod et cite CHG-2134
_m20_e34_t2_mr() {
  local iid
  while IFS= read -r iid; do
    [[ -n "$iid" ]] || continue
    gitlab_api "projects/$(_m20p_uri "$_M20_E34_DEP")/merge_requests/$iid/diffs?per_page=100" 2>/dev/null \
      | jq -e 'any(.[]; (.new_path // .old_path) | startswith("overlays/prod/"))' >/dev/null 2>&1 && return 0
  done < <(jq -r --argjson t0 "$_m20_e34_t0" '.[]? | select((.merged_at // "1970-01-01T00:00:00Z" | sub("\\.[0-9]+"; "") | fromdateiso8601) >= $t0)
             | select(((.title // "") + " " + (.description // "")) | test("CHG-2134")) | .iid' <<<"$_m20_e34_mrs" 2>/dev/null)
  return 1
}
# Tâche 3 — même digest en recette et en production (main et cluster)
_m20_e34_t3_overlays() {
  local p r
  p="$(_m20p_fichier_main "$_M20_E34_DEP" overlays/prod/kustomization.yaml | grep -Eo 'sha256:[0-9a-f]{64}' | head -1)"
  r="$(_m20p_fichier_main "$_M20_E34_DEP" overlays/recette/kustomization.yaml | grep -Eo 'sha256:[0-9a-f]{64}' | head -1)"
  [[ -n "$p" && "$p" == "$r" ]]
}
_m20_e34_t3_cluster() {
  [[ "$_m20_e34_img_prod" == *@sha256:* && "${_m20_e34_img_prod##*@}" == "${_m20_e34_img_rec##*@}" ]]
}
# Tâche 4 — synchronisation manuelle réussie après T0, sur la révision de main
_m20_e34_t4_manuelle() {
  _m20p_jq "$_m20_e34_app" '(.status.operationState.operation.initiatedBy.automated // false) == false
    and ((.status.operationState.operation.initiatedBy.username // "") != "")'
}
_m20_e34_t4_apres_t0() { _m20_e34_apres "$(jq -r '.status.operationState.startedAt // empty' <<<"$_m20_e34_app")"; }
_m20_e34_t4_reussie() {
  _m20p_jq "$_m20_e34_app" '.status.operationState.phase == "Succeeded"' \
    && [[ -n "$_m20_e34_main" ]] \
    && _m20p_jq "$_m20_e34_app" '.status.sync.revision == $r' --arg r "$_m20_e34_main"
}
# Tâche 5 — canary allé au bout
_m20_e34_t5_promu() {
  _m20p_jq "$_m20_e34_ro" '.status.phase == "Healthy" and .status.stableRS != null and .status.stableRS == .status.currentPodHash'
}
_m20_e34_t5_revision_recente() {
  local h
  h="$(jq -r '.status.currentPodHash // empty' <<<"$_m20_e34_ro")"
  [[ -n "$h" ]] || return 1
  _m20_e34_apres "$(jq -r --arg h "$h" '[.items[] | select(.metadata.labels["rollouts-pod-template-hash"] == $h)][0].metadata.creationTimestamp // empty' <<<"$_m20_e34_rs")"
}
_m20_e34_t5_poids() {
  _m20p_jq "$_m20_e34_route" '[.spec.rules[0].backendRefs[]] as $b
    | any($b[]; .name == "mediagenda" and (.weight // 1) == 100)
      and all($b[]; .name != "mediagenda-canary" or (.weight // 1) == 0)'
}
_m20_e34_t5_app_saine() { _m20p_app_saine "$_m20_e34_app"; }
# Tâche 6 — analyses de la nouvelle révision réussies, aucune en échec depuis T0
_m20_e34_t6_reussies() {
  _m20p_jq "$_m20_e34_ar" '[.items[] | select((.metadata.creationTimestamp | fromdateiso8601) >= $t0)] as $a
    | any($a[]; .status.phase == "Successful" and (.spec.metrics | any(.name | test("fumee"))))
      and any($a[]; .status.phase == "Successful" and (.spec.metrics | any(.name | test("fumee")) | not))' \
    --argjson t0 "$_m20_e34_t0"
}
_m20_e34_t6_aucun_echec() {
  _m20p_jq "$_m20_e34_ar" 'all(.items[] | select((.metadata.creationTimestamp | fromdateiso8601) >= $t0);
    .status.phase != "Failed" and .status.phase != "Error")' --argjson t0 "$_m20_e34_t0"
}
# Tâche 7 — message d'Argo CD dans Mailpit après T0
_m20_e34_t7_message() {
  local sujet cree
  while IFS=$'\t' read -r sujet cree; do
    [[ "$sujet" == *mediagenda-prod* ]] || continue
    grep -Eqi 'd(e|é)ploy' <<<"$sujet" || continue
    _m20_e34_apres "$cree" && return 0
  done < <(mailpit_api "search?query=$(_m20p_uri 'mediagenda-prod')&limit=50" 2>/dev/null \
             | jq -r '.messages[]? | [.Subject, .Created] | @tsv' 2>/dev/null)
  return 1
}
# Tâche 8 — compte rendu sur main
_m20_e34_t8_compte_rendu() {
  _m20p_doc docs/livraison/gitops/tests/mise-en-production-chrono.md 'T0' 'T1' 'sha256:' 'CHG-2134'
}

title "Score par tâche"
_m20_e34_tache 1 10 "préparer (journal, CHG, digest)" _m20_e34_t1_journal
_m20_e34_tache 2 15 "MR de promotion fusionnée" _m20_e34_t2_mr
_m20_e34_tache 3 10 "même digest en recette et en production" _m20_e34_t3_overlays _m20_e34_t3_cluster
_m20_e34_tache 4 15 "synchronisation manuelle réussie" _m20_e34_t4_manuelle _m20_e34_t4_apres_t0 _m20_e34_t4_reussie
_m20_e34_tache 5 20 "canary conduit jusqu'au bout" _m20_e34_t5_promu _m20_e34_t5_revision_recente _m20_e34_t5_poids _m20_e34_t5_app_saine
_m20_e34_tache 6 15 "analyses réussies" _m20_e34_t6_reussies _m20_e34_t6_aucun_echec
_m20_e34_tache 7 5 "notification reçue" _m20_e34_t7_message
_m20_e34_tache 8 10 "compte rendu" _m20_e34_t8_compte_rendu
printf '  Score : %d / %d\n' "$_m20_e34_score" "$_m20_e34_max"
check_output "au moins 70 points sur 100 (score : $_m20_e34_score)" '^ok$' \
  bash -c '(( $1 >= 70 )) && echo ok' _ "$_m20_e34_score"
