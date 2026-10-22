# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E10.sh — M20-E10 « ApplicationSets : un générateur pour trois environnements ». Lecture seule :
# ApplicationSet et Applications (wb-checks), argocd-cmd-params-cm, ReplicaSet de mediagenda-dev,
# arbre de plateforme/gitops (GitLab).

# shellcheck source=_m20-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-operationnel.sh"

title "M20-E10 — ApplicationSets : un générateur pour trois environnements"
require_cmd jq kubectl curl

_e10_as="$(_m20o_obj argocd applicationsets.argoproj.io mediagenda)"
check_cmd "ApplicationSet argocd/mediagenda présent" test -n "$_e10_as"
check_cmd "ApplicationSet : politique create-update (ne supprime jamais d'Application)" \
  _m20o_jq "$_e10_as" '.spec.syncPolicy.applicationsSync == "create-update"'
check_cmd "ApplicationSet : preserveResourcesOnDeletion (aucun finaliseur de suppression en cascade)" \
  _m20o_jq "$_e10_as" '.spec.syncPolicy.preserveResourcesOnDeletion == true'
_e10_params="$(_m20o_obj argocd configmap argocd-cmd-params-cm)"
check_cmd "argocd-cmd-params-cm : la politique propre à chaque ApplicationSet est prise en compte" \
  _m20o_jq "$_e10_params" '.data["applicationsetcontroller.enable.policy.override"] == "true"'
check_cmd "ApplicationSet : pas d'erreur de rendu (condition ErrorOccurred absente ou fausse)" \
  _m20o_jq "$_e10_as" '[.status.conditions[]? | select(.type == "ErrorOccurred" and .status == "True")] | length == 0'

for _e10_env in dev recette prod; do
  _e10_app="$(_m20o_app "mediagenda-$_e10_env")"
  if [[ -z "$_e10_app" ]]; then
    check_cmd "Application mediagenda-$_e10_env présente" false
    continue
  fi
  check_cmd "mediagenda-$_e10_env : générée par l'ApplicationSet mediagenda (propriétaire)" \
    _m20o_jq "$_e10_app" '[.metadata.ownerReferences[]? | select(.kind == "ApplicationSet" and .name == "mediagenda")] | length == 1'
  check_cmd "mediagenda-$_e10_env : projet mediagenda, overlays/$_e10_env, espace mediagenda-$_e10_env" \
    _m20o_jq "$_e10_app" '.spec.project == "mediagenda" and .spec.source.path == ("overlays/" + $e)
      and .spec.destination.namespace == ("mediagenda-" + $e)' --arg e "$_e10_env"
  check_cmd "mediagenda-$_e10_env : pas de finaliseur resources-finalizer (supprimer l'Application ne supprime pas les charges)" \
    _m20o_jq "$_e10_app" '[.metadata.finalizers[]? | select(startswith("resources-finalizer.argocd.argoproj.io"))] | length == 0'
  if [[ "$_e10_env" == prod ]]; then
    check_cmd "mediagenda-prod : AUCUNE synchronisation automatique" \
      _m20o_jq "$_e10_app" '(.spec.syncPolicy.automated // null) == null'
    check_cmd "mediagenda-prod : saine (Healthy)" _m20o_jq "$_e10_app" '.status.health.status == "Healthy"'
  else
    check_cmd "mediagenda-$_e10_env : synchronisation automatique avec prune et selfHeal" \
      _m20o_jq "$_e10_app" '.spec.syncPolicy.automated.prune == true and .spec.syncPolicy.automated.selfHeal == true'
    check_cmd "mediagenda-$_e10_env : Synced et Healthy" _m20o_sync_sante "$_e10_app"
  fi
done

# Reprise sans coupure : le ReplicaSet qui sert en dev est antérieur à l'ApplicationSet, OU les pods
# ont été recréés par une vraie livraison postérieure (on ne peut pas trancher : on regarde seulement
# qu'aucun pod n'a moins de temps que l'ApplicationSet SANS changement de gabarit).
_e10_cree_as="$(jq -r '.metadata.creationTimestamp // ""' <<<"$_e10_as" 2>/dev/null)" || _e10_cree_as=""
_e10_dep="$(_m20o_obj mediagenda-dev deployment mediagenda)"
_e10_rs_avant() {
  [[ -n "$_e10_cree_as" && -n "$_e10_dep" ]] || return 1
  local gen rs
  gen="$(jq -r '.metadata.annotations["deployment.kubernetes.io/revision"] // ""' <<<"$_e10_dep")"
  rs="$(_m20o_k get replicasets -n mediagenda-dev -o json | jq -r --arg g "$gen" \
    '[.items[] | select(.metadata.annotations["deployment.kubernetes.io/revision"] == $g)][0].metadata.creationTimestamp // ""')"
  [[ -n "$rs" ]] && [[ "$rs" < "$_e10_cree_as" ]]
}
if _e10_rs_avant; then
  check_cmd "mediagenda-dev : ReplicaSet en service antérieur à l'ApplicationSet (reprise sans recréer les pods)" true
else
  skip "mediagenda-dev : ReplicaSet antérieur à l'ApplicationSet" \
    "ReplicaSet plus récent : normal si une version a été livrée depuis ; sinon, l'adoption a recréé les pods (voir le corrigé)"
fi

# L'Application écrite à la main en E08 a quitté le dépôt (une seule source : l'ApplicationSet).
_e10_doublon() {
  local f arbre
  arbre="$(_m20o_gl_arbre plateforme/gitops)"
  [[ -n "$arbre" ]] || return 1   # dépôt illisible : on ne conclut pas
  while read -r f; do
    _m20o_gl_fichier plateforme/gitops "$f" | yq -o json -I0 '.' 2>/dev/null \
      | jq -e 'select(.kind == "Application" and .metadata.name == "mediagenda-dev")' >/dev/null 2>&1 && return 1
  done < <(grep -E '\.ya?ml$' <<<"$arbre")
  return 0
}
check_cmd "plateforme/gitops : plus d'Application mediagenda-dev écrite à la main" _e10_doublon
