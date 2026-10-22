# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E30.sh — M20-E30 « Retirer à la CI tout accès en écriture aux applications » (SEC-2130)
# À lancer depuis adm01. Lecture seule : RoleBindings, ClusterRoleBindings, managedFields des
# Deployments, StatefulSets et Services des espaces applicatifs (wb-checks) ; configuration de l'agent,
# .gitlab-ci.yml et dernier pipeline de mediagenda/deploiement (GitLab) ; documentation sur main.

# shellcheck source=_m20-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-production.sh"

title "M20-E30 — Retirer à la CI tout accès en écriture aux applications"
require_cmd kubectl jq
check_cmd "l'API du cluster répond (readyz)" _m20p_joignable

title "Agent GitLab k8s-par1"
_m20_e30_agent="$(_m20p_fichier_main plateforme/k8s .gitlab/agents/k8s-par1/config.yaml)"
check_cmd "configuration de l'agent présente sur main de plateforme/k8s" test -n "$_m20_e30_agent"
check_output "ci_access ne cite plus ni mediagenda ni medidoc" '^ok$' \
  bash -c 'grep -v "^[[:space:]]*#" <<<"$1" | grep -Eq "id:[[:space:]]*\"?(mediagenda|medidoc)" || echo ok' _ "$_m20_e30_agent"
_m20_e30_rb="$(_m20p_json get rolebindings -A)"
_m20_e30_crb="$(_m20p_json get clusterrolebindings)"
_M20_E30_AGENT='any(.subjects[]?; .kind == "ServiceAccount" and .namespace == "gitlab-agent")'
check_cmd "aucun RoleBinding d'un compte de gitlab-agent dans mediagenda-*, medidoc-*, argocd, argo-rollouts" \
  _m20p_jq "$_m20_e30_rb" "[.items[] | select(.metadata.namespace | test(\"^(mediagenda-.*|medidoc-.*|argocd|argo-rollouts)\$\"))
    | select($_M20_E30_AGENT)] | length == 0"
check_cmd "aucun ClusterRoleBinding d'écriture (cluster-admin, admin, edit) pour un compte de gitlab-agent" \
  _m20p_jq "$_m20_e30_crb" "[.items[] | select($_M20_E30_AGENT) | select(.roleRef.name | IN(\"cluster-admin\", \"admin\", \"edit\"))] | length == 0"
check_cmd "l'agent garde un RoleBinding dans wb-essais (formation/ci-labo)" \
  _m20p_jq "$_m20_e30_rb" "any(.items[]; .metadata.namespace == \"wb-essais\" and $_M20_E30_AGENT)"

title "Pipeline de mediagenda/deploiement : validation seulement"
_m20_e30_ci="$(_m20p_fichier_main mediagenda/deploiement .gitlab-ci.yml)"
check_cmd ".gitlab-ci.yml présent sur main" test -n "$_m20_e30_ci"
check_output ".gitlab-ci.yml : ni « kubectl apply » ni contexte d'agent" '^ok$' \
  bash -c 'grep -v "^[[:space:]]*#" <<<"$1" | grep -Eqi "kubectl[[:space:]]+(apply|create|replace|patch)|:k8s-par1|KUBE_CONTEXT" || echo ok' \
  _ "$_m20_e30_ci"
_m20_e30_pipe="$(_m20p_dernier_pipeline mediagenda/deploiement)"
_m20_e30_pid="$(jq -r '.id // empty' <<<"$_m20_e30_pipe" 2>/dev/null || true)"
check_cmd "dernier pipeline de main réussi" _m20p_jq "$_m20_e30_pipe" '.status == "success"'
if [[ -n "$_m20_e30_pid" ]]; then
  _m20_e30_jobs="$(_m20p_jobs mediagenda/deploiement "$_m20_e30_pid")"
  check_cmd "… avec au moins un job de validation (kustomize, kubeconform, signatures)" _m20p_jq "$_m20_e30_jobs" \
    'any(.[]; .name | test("valid|kubeconform|kustomize|verif|signature"; "i"))'
  check_cmd "… et aucun job de déploiement" _m20p_jq "$_m20_e30_jobs" \
    'all(.[]; (.name | test("deploy|d(e|é)ployer|appliquer|apply"; "i")) | not)'
else
  check_cmd "jobs du dernier pipeline de main (pipeline introuvable)" false
fi

title "Gestionnaires de champs des objets applicatifs"
_m20_e30_ns="$(_m20p_json get namespaces | jq -r '.items[].metadata.name | select(test("^(mediagenda|medidoc)-"))' 2>/dev/null || true)"
check_output "espaces applicatifs trouvés : $(tr '\n' ' ' <<<"$_m20_e30_ns")" 'mediagenda-prod' echo "$_m20_e30_ns"
_m20_e30_fautifs=""
while IFS= read -r _m20_e30_e; do
  [[ -n "$_m20_e30_e" ]] || continue
  _m20_e30_f="$(_m20p_json -n "$_m20_e30_e" get deployments,statefulsets,services | jq -r --arg ns "$_m20_e30_e" '
      .items[]? | . as $o | [.metadata.managedFields[]?.manager | select(test("^(kubectl|kubectl-.*|helm|gitlab.*|agentk)$"))] | unique
      | select(length > 0) | "\($ns)/\($o.kind)/\($o.metadata.name) (\(join(",")))"' 2>/dev/null || true)"
  [[ -n "$_m20_e30_f" ]] && _m20_e30_fautifs="$_m20_e30_fautifs $_m20_e30_f"
done <<<"$_m20_e30_ns"
check_output "aucun gestionnaire humain ou de CI (kubectl*, helm, gitlab*, agentk)${_m20_e30_fautifs:+ — trouvés :$_m20_e30_fautifs}" '^ok$' \
  bash -c '[[ -z "$1" ]] && echo ok' _ "$_m20_e30_fautifs"

title "Documentation"
check_cmd "docs/livraison/gitops/acces-ci.md sur main (chemins d'écriture, preuves, revue)" \
  _m20p_doc docs/livraison/gitops/acces-ci.md 'can-i' 'managedFields|gestionnaire' 'revue'
