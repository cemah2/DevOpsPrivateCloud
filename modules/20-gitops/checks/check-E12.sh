# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E12.sh — M20-E12 « Ce qu'Argo CD ne doit pas gérer : différences ignorées et Secrets hors Git ».
# Lecture seule : Applications, HPA et ConfigMap argocd-cm (wb-checks), arbres des dépôts suivis (GitLab).

# shellcheck source=_m20-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-operationnel.sh"

title "M20-E12 — Différences ignorées et Secrets hors Git"
require_cmd jq kubectl curl yq

for _e12_env in recette prod; do
  _e12_app="$(_m20o_app "mediagenda-$_e12_env")"
  check_cmd "mediagenda-$_e12_env : poids des backendRefs de l'HTTPRoute mediagenda ignorés" \
    _m20o_jq "$_e12_app" '[.spec.ignoreDifferences[]? | select(.kind == "HTTPRoute" and .group == "gateway.networking.k8s.io"
      and (.name // "") == "mediagenda"
      and (([.jqPathExpressions[]?, .jsonPointers[]?] | map(test("weight"))) | any))] | length == 1'
  check_cmd "mediagenda-$_e12_env : réplicas du Deployment mediagenda ignorés, et seulement eux" \
    _m20o_jq "$_e12_app" '[.spec.ignoreDifferences[]? | select(.kind == "Deployment" and (.name // "") == "mediagenda")]
      | length == 1 and (.[0].jsonPointers // [] | . == ["/spec/replicas"])'
  check_cmd "mediagenda-$_e12_env : RespectIgnoreDifferences=true (la synchronisation ne remet pas ces champs)" \
    _m20o_jq "$_e12_app" '(.spec.syncPolicy.syncOptions // []) | index("RespectIgnoreDifferences=true") != null'
done
_e12_dev="$(_m20o_app mediagenda-dev)"
check_cmd "mediagenda-dev : aucune différence ignorée (rien n'y écrit à la place d'Argo CD)" \
  _m20o_jq "$_e12_dev" '(.spec.ignoreDifferences // []) | length == 0'
for _e12_env in dev recette prod; do
  _e12_app="$(_m20o_app "mediagenda-$_e12_env")"
  check_cmd "mediagenda-$_e12_env : webhooks de mutation inclus dans le diff côté serveur" \
    _m20o_jq "$_e12_app" '.metadata.annotations["argocd.argoproj.io/compare-options"] // "" | test("IncludeMutationWebhook=true") and (test("ServerSideDiff=false") | not)'
done
check_cmd "mediagenda-dev : Synced (aucun faux écart, valeurs par défaut de CNPG comprises)" \
  _m20o_jq "$_e12_dev" '.status.sync.status == "Synced"'

# labo : HPA et réplicas laissés au HPA (le HPA vise le Deployment en E12, le Rollout à partir d'E15).
_e12_hpa="$(_m20o_obj wb-essais horizontalpodautoscaler labo)"
check_cmd "wb-essais : HPA labo (2 à 4 pods)" _m20o_jq "$_e12_hpa" '.spec.minReplicas == 2 and .spec.maxReplicas == 4'
_e12_labo="$(_m20o_app labo)"
check_cmd "Application labo : spec.replicas de la charge visée par le HPA ignoré, RespectIgnoreDifferences" \
  _m20o_jq "$_e12_labo" '([.spec.ignoreDifferences[]? | select((.kind == "Deployment" or .kind == "Rollout") and (.name // "") == "labo"
      and ((.jsonPointers // []) | index("/spec/replicas") != null))] | length >= 1)
    and ((.spec.syncPolicy.syncOptions // []) | index("RespectIgnoreDifferences=true") != null)'
check_cmd "Application labo : Synced alors que le HPA a choisi le nombre de pods" _m20o_sync_sante "$_e12_labo"

# Exclusions de ressources : le chart garde sa liste par défaut et on y AJOUTE (pas de remplacement).
_e12_cm="$(_m20o_obj argocd configmap argocd-cm)"
check_cmd "argocd-cm : exclusions par défaut conservées (Endpoints, Lease…)" \
  _m20o_jq "$_e12_cm" '.data["resource.exclusions"] // "" | test("Lease") and test("EndpointSlice")'
check_cmd "argocd-cm : exclusion ajoutée pour les objets créés par Velero" \
  _m20o_jq "$_e12_cm" '.data["resource.exclusions"] // "" | test("velero\\.io")'

# Aucun Secret dans les dépôts suivis par Argo CD (lecture des arbres sur main par l'API).
_e12_secret_dans() {
  local projet="$1" f arbre
  arbre="$(_m20o_gl_arbre "$projet")"
  [[ -n "$arbre" ]] || { echo "  dépôt $projet illisible" >&2; return 0; }   # illisible : pas de conclusion favorable
  while read -r f; do
    if _m20o_gl_fichier "$projet" "$f" | grep -Eq '^[[:space:]]*kind:[[:space:]]*"?Secret"?[[:space:]]*$'; then
      echo "  Secret trouvé : $projet/$f" >&2
      return 0
    fi
  done < <(grep -E '\.(ya?ml|json)$' <<<"$arbre")
  return 1
}
_e12_aucun_secret() { ! _e12_secret_dans "$1"; }
for _e12_p in mediagenda/deploiement plateforme/gitops formation/gitops-labo; do
  check_cmd "$_e12_p : aucun objet « kind: Secret » dans les fichiers de main" _e12_aucun_secret "$_e12_p"
done
# Les Secrets de MédiAgenda existent dans le cluster, créés hors Git (wb-checks ne lit pas les Secrets :
# on constate seulement que les pods de l'API, qui citent harbor-pull et mediagenda-db-app, tournent).
for _e12_env in dev recette prod; do
  _e12_pods="$(_m20o_k get pods -n "mediagenda-$_e12_env" -l app.kubernetes.io/name=mediagenda,app.kubernetes.io/component=api -o json)"
  check_cmd "mediagenda-$_e12_env : pods de l'API prêts (Secrets hors Git présents)" \
    _m20o_jq "$_e12_pods" '(.items | length) > 0 and ([.items[] | .status.conditions[]? | select(.type == "Ready") | .status == "True"] | all)'
done
