# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E18.sh — M19-E18 : Déployer en dev avec l'agent GitLab pour Kubernetes
# À lancer depuis adm01. Lecture seule : API GitLab (agents, jetons, déploiements), « kube » (pods,
# liaisons RBAC ; droits du compte de l'agent par SubjectAccessReview : rien n'est écrit).

# shellcheck source=_m19-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-operationnel.sh"

title "M19-E18 — Déployer en dev avec l'agent GitLab pour Kubernetes"
require_cmd jq curl kubectl

_m19o_e18_agent="$(_m19o_api "$_M19O_P_K8S/cluster_agents" | jq -c '[.[] | select(.name == "k8s-par1")][0] // empty' 2>/dev/null || true)"
check_cmd "plateforme/k8s : agent k8s-par1 enregistré" test -n "$_m19o_e18_agent"
_m19o_e18_aid="$(jq -r '.id // 0' <<<"${_m19o_e18_agent:-null}" 2>/dev/null || echo 0)"
# last_used_at n'est rendu que pour un jeton lu individuellement : un jeton actif utilisé depuis < 1 h.
_m19o_e18_recent=0
for _m19o_e18_t in $(_m19o_api "$_M19O_P_K8S/cluster_agents/$_m19o_e18_aid/tokens" | jq -r '.[] | select(.status == "active") | .id' 2>/dev/null || true); do
  if _m19o_json "$(_m19o_api "$_M19O_P_K8S/cluster_agents/$_m19o_e18_aid/tokens/$_m19o_e18_t")" \
      '.last_used_at != null and (now - (.last_used_at | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601)) < 3600'; then
    _m19o_e18_recent=1; break
  fi
done
check_cmd "l'agent est connecté (jeton actif utilisé depuis moins d'une heure)" test "$_m19o_e18_recent" = 1

_m19o_e18_pods="$(_m19o_k get pods -n gitlab-agent -o json)"
check_cmd "espace gitlab-agent : au moins un pod agentk prêt" _m19o_json "$_m19o_e18_pods" \
  'any(.items[]; .metadata.labels["app.kubernetes.io/name"] == "gitlab-agent" and any(.status.conditions[]?; .type == "Ready" and .status == "True"))'
check_cmd "agentk : image par Harbor, en 19.4 ou plus" _m19o_json "$_m19o_e18_pods" \
  'any(.items[].spec.containers[]; .image | test("^registry\\.par1\\.medisphere\\.internal/.*/agentk:v19\\."))'

_m19o_e18_crb="$(_m19o_k get clusterrolebindings -o json)"
if [[ -n "$_m19o_e18_crb" ]]; then
  check_cmd "aucun ClusterRoleBinding ne vise un compte de service de l'espace gitlab-agent" _m19o_json "$_m19o_e18_crb" \
    '[.items[] | select(any(.subjects[]?; .kind == "ServiceAccount" and .namespace == "gitlab-agent"))] | length == 0'
else
  skip "ClusterRoleBindings de l'espace gitlab-agent" "lecture refusée à wb-checks (contrôle par SubjectAccessReview ci-dessous)"
fi
_M19O_E18_SA="system:serviceaccount:gitlab-agent:gitlab-agent"
_m19o_e18_attendu() { # RÉPONSE VERBE RESSOURCE ESPACE GROUPE
  [[ "$(_m19o_peut "$_M19O_E18_SA" "$2" "$3" "$4" "$5")" == "$1" ]]
}
check_cmd "compte de l'agent : peut modifier un Deployment de mediagenda-dev" _m19o_e18_attendu yes patch deployments mediagenda-dev apps
check_cmd "compte de l'agent : peut créer un ConfigMap dans wb-essais" _m19o_e18_attendu yes create configmaps wb-essais ""
check_cmd "compte de l'agent : peut appliquer le Cluster CNPG de mediagenda-dev" _m19o_e18_attendu yes patch clusters mediagenda-dev postgresql.cnpg.io
check_cmd "compte de l'agent : RIEN dans mediagenda-recette" _m19o_e18_attendu no create configmaps mediagenda-recette ""
check_cmd "compte de l'agent : RIEN dans kube-system (Secrets)" _m19o_e18_attendu no get secrets kube-system ""
check_cmd "compte de l'agent : ni les nœuds" _m19o_e18_attendu no list nodes "" ""
check_cmd "compte de l'agent : ni les rôles (pas d'escalade)" _m19o_e18_attendu no create rolebindings mediagenda-dev rbac.authorization.k8s.io

_m19o_e18_dep="$(_m19o_api "$_M19O_P_DEP/deployments?environment=dev&order_by=id&sort=desc&per_page=1" | jq -c '.[0] // empty' 2>/dev/null || true)"
check_cmd "mediagenda/deploiement : le dernier déploiement de l'environnement dev a réussi" _m19o_json "$_m19o_e18_dep" '.status == "success"'
check_cmd "… par le job deployer-dev" _m19o_json "$_m19o_e18_dep" '.deployable.name == "deployer-dev"'
check_output "plateforme/k8s (main) : .gitlab/agents/k8s-par1/config.yaml autorise le groupe mediagenda" 'id: *mediagenda' \
  _m19o_contenu "$_M19O_P_K8S" .gitlab/agents/k8s-par1/config.yaml
