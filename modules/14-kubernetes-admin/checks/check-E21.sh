# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E21.sh — M14-E21 : Revue : les manifestes du stagiaire
# À lancer depuis adm01. Lecture seule : déploiement corrigé en mediagenda-recette (« kube »), dépôt
# mediagenda/api (aucun Secret sous k8s/recette/). La revue elle-même s'auto-évalue avec le corrigé.

# shellcheck source=_m14-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-operationnel.sh"

title "M14-E21 — Revue : les manifestes du stagiaire"
require_cmd jq kubectl curl

_m14o_e21_ns=mediagenda-recette
_m14o_e21_d="$(_m14o_k get deployment mediagenda-api -n "$_m14o_e21_ns" -o json)"
_m14o_e21_spec="$(jq -c '.spec.template.spec' <<<"${_m14o_e21_d:-{\}}" 2>/dev/null || true)"
check_cmd "API en recette : au moins 2 réplicas prêts" _m14o_json "$_m14o_e21_d" '.spec.replicas >= 2 and (.status.readyReplicas // 0) >= 2'
check_cmd "sélecteur du Deployment sans étiquette de version" _m14o_json "$_m14o_e21_d" \
  '.spec.selector.matchLabels | keys | all(test("version") | not)'
check_cmd "compte de service mediagenda-api" _m14o_json "$_m14o_e21_spec" '.serviceAccountName == "mediagenda-api"'
check_cmd "ni nodeName, ni hostPort, ni hostNetwork" _m14o_json "$_m14o_e21_spec" \
  '(.nodeName == null) and (.hostNetwork != true) and ([.containers[].ports[]? | select((.hostPort // 0) != 0)] | length == 0)'
check_cmd "sondes : vivacité /sante, disponibilité /pret" _m14o_json "$_m14o_e21_spec" \
  'any(.containers[]; .livenessProbe.httpGet.path == "/sante" and .readinessProbe.httpGet.path == "/pret")'
check_cmd "ressources déclarées (requêtes CPU et mémoire, limite mémoire)" _m14o_json "$_m14o_e21_spec" \
  'all(.containers[]; .resources.requests.cpu != null and .resources.requests.memory != null and .resources.limits.memory != null)'
check_cmd "commande de l'image conservée (pas de « sh -c » qui avale SIGTERM)" _m14o_json "$_m14o_e21_spec" \
  'all(.containers[]; ((.command // []) | index("sh") == null))'
check_cmd "délai d'arrêt ≥ 25 s (MédiAgenda finit ses requêtes en 20 s)" _m14o_json "$_m14o_e21_spec" '(.terminationGracePeriodSeconds // 30) >= 25'
check_cmd "image v* de Harbor (pas latest)" _m14o_json "$_m14o_e21_spec" \
  'all(.containers[]; .image | test("^registry\\.par1\\.medisphere\\.internal/medisphere/mediagenda-api:v[0-9]"))'
check_cmd "aucune ConfigMap de recette ne contient de mot de passe ou d'URL avec identifiants" \
  _m14o_json "$(_m14o_k get configmaps -n "$_m14o_e21_ns" -o json)" \
  '[.items[].data // {} | to_entries[] | select((.key | test("MDP|PASSWORD|SECRET"; "i")) or (.value | test("://[^/@]+:[^/@$]+@")))] | length == 0'
check_cmd "le Service de l'API a des points de terminaison prêts" \
  _m14o_json "$(_m14o_k get endpointslices -n "$_m14o_e21_ns" -l kubernetes.io/service-name=mediagenda-api -o json)" \
  '[.items[].endpoints[]? | select(.conditions.ready == true)] | length >= 2'
check_cmd "aucun Service NodePort ou LoadBalancer en recette" \
  _m14o_json "$(_m14o_k get services -n "$_m14o_e21_ns" -o json)" '[.items[] | select(.spec.type == "NodePort" or .spec.type == "LoadBalancer")] | length == 0'
check_cmd "PostgreSQL de recette : un seul réplica, sans hostPath" \
  _m14o_json "$(_m14o_k get deployments,statefulsets -n "$_m14o_e21_ns" -o json)" \
  '[.items[] | select(.metadata.name == "postgresql")] | length == 1 and all(.spec.replicas == 1
    and ([.spec.template.spec.volumes[]? | select(has("hostPath"))] | length == 0))'
check_cmd "PDB de l'API : le drain reste possible (au moins une perturbation autorisée)" \
  _m14o_json "$(_m14o_k get pdb -n "$_m14o_e21_ns" -o json)" \
  '[.items[] | select(.spec.selector.matchLabels["app.kubernetes.io/name"] == "mediagenda-api")] | length == 1 and all(.status.disruptionsAllowed >= 1)'

_m14o_e21_fichiers="$(_m14o_arbre "$_M14O_P_APP" k8s/recette)"
check_cmd "mediagenda/api : k8s/recette/ sur main" bash -c '[[ -n "$1" ]]' _ "$_m14o_e21_fichiers"
_m14o_e21_secret() {
  local f
  for f in $_m14o_e21_fichiers; do
    _m14o_contenu_main "$_M14O_P_APP" "$f" | grep -Eq '^kind: *Secret[[:space:]]*$' && return 1
  done
  return 0
}
check_cmd "aucun Secret versionné sous k8s/recette/" _m14o_e21_secret
