# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E11.sh — M20-E11 « Vagues et hooks de synchronisation ». Lecture seule : résultat de la dernière
# synchronisation des Applications (wb-checks), Job et Deployment de recette, fichiers de
# mediagenda/deploiement sur main (GitLab).

# shellcheck source=_m20-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-operationnel.sh"

title "M20-E11 — Vagues et hooks de synchronisation"
require_cmd jq kubectl curl yq

_e11_app="$(_m20o_app mediagenda-recette)"
check_cmd "mediagenda-recette : dernière synchronisation réussie" \
  _m20o_jq "$_e11_app" '.status.operationState.phase == "Succeeded"'
# Le résultat d'une synchronisation liste ses hooks (hookType, hookPhase) à côté des objets appliqués.
_e11_hook='[.status.operationState.syncResult.resources[]?
  | select(.kind == "Job" and .name == "mediagenda-migrate" and (.hookType // "") != "")]'
check_cmd "mediagenda-recette : le Job mediagenda-migrate a tourné comme hook lors de la dernière synchronisation" \
  _m20o_jq "$_e11_app" "$_e11_hook | length >= 1"
check_cmd "mediagenda-recette : ce hook a réussi (hookPhase Succeeded)" \
  _m20o_jq "$_e11_app" "$_e11_hook | all(.hookPhase == \"Succeeded\")"
check_cmd "mediagenda-recette : hook de phase Sync (pas PreSync : la base doit exister avant lui)" \
  _m20o_jq "$_e11_app" "$_e11_hook | all(.hookType == \"Sync\")"

_e11_job="$(_m20o_obj mediagenda-recette job mediagenda-migrate)"
if [[ -n "$_e11_job" ]]; then
  check_cmd "Job mediagenda-migrate : vague -1 et politique BeforeHookCreation" \
    _m20o_jq "$_e11_job" '.metadata.annotations["argocd.argoproj.io/sync-wave"] == "-1"
      and (.metadata.annotations["argocd.argoproj.io/hook-delete-policy"] // "" | test("BeforeHookCreation"))'
else
  skip "Job mediagenda-migrate : annotations" "Job absent (supprimé par sa politique de suppression ?) : seul le résultat de synchronisation compte"
fi

# Les migrations ont quitté les pods de l'API (plus de conteneur d'initialisation « migrations »).
_e11_dep_ou_ro() {
  local d
  d="$(_m20o_obj mediagenda-recette deployment mediagenda)"
  _m20o_jq "$d" '[.spec.template.spec.initContainers[]? | select(.name == "migrations")] | length == 0'
}
check_cmd "recette : le gabarit de pod de l'API n'a plus de conteneur d'initialisation de migration" _e11_dep_ou_ro

# Ordre déclaré dans le dépôt (lu sur main) : ConfigMaps en -3, base CNPG en -2.
_e11_rendu_dev() {
  local c
  c="$(_m20o_gl_fichier mediagenda/deploiement components/migrations/kustomization.yaml)"
  [[ -n "$c" ]] && grep -q 'sync-wave' <<<"$c" && grep -Eq '"?-3"?' <<<"$c" && grep -Eq '"?-2"?' <<<"$c"
}
check_cmd "mediagenda/deploiement (main) : component migrations avec les vagues -3 et -2" _e11_rendu_dev
_e11_values() { _m20o_gl_fichier mediagenda/deploiement base/values-communes.yaml | yq -e '.migrations.mode == "none"' >/dev/null 2>&1; }
check_cmd "mediagenda/deploiement (main) : base rendue avec migrations.mode: none" _e11_values
for _e11_o in dev recette prod; do
  _e11_dans() { _m20o_gl_fichier mediagenda/deploiement "overlays/$_e11_o/kustomization.yaml" | grep -q 'components/migrations'; }
  check_cmd "overlays/$_e11_o inclut le component migrations" _e11_dans
done

_e11_dev="$(_m20o_app mediagenda-dev)"
check_cmd "mediagenda-dev : toujours Synced et Healthy après le changement" _m20o_sync_sante "$_e11_dev"
