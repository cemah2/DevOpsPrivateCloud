# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E10.sh — M28-E10 : Le portail montre l'état : plugins Kubernetes et TechDocs
# Lecture seule : ClusterRole et liaison, Rollouts (kube) ; API du catalogue ; compartiment
# portail-techdocs avec l'identité de LECTURE (~/.config/workbook/s3-techdocs.env) ; GitLab (GET).

# shellcheck source=_m28-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m28-operationnel.sh"

title "M28-E10 — Le portail montre l'état : plugins Kubernetes et TechDocs"
require_cmd jq kubectl curl aws

check_cmd "ClusterRole portail-lecture-k8s : lecture seule, sans Secrets, ConfigMaps ni journaux" _m28d_kq \
  '(.rules | length >= 1)
   and all(.rules[]; all(.verbs[]; . == "get" or . == "list" or . == "watch"))
   and ([.rules[].resources[]] | (index("secrets") == null and index("configmaps") == null and index("pods/log") == null and index("*") == null))
   and ([.rules[].resources[]] | index("pods") != null)' \
  clusterroles.rbac.authorization.k8s.io portail-lecture-k8s
check_cmd "ClusterRoleBinding vers le compte de service portail/portail" _m28d_kq \
  '[.items[] | select(.roleRef.name == "portail-lecture-k8s") | .subjects[]? | select(.kind == "ServiceAccount" and .name == "portail" and .namespace == "portail")] | length >= 1' \
  clusterrolebindings.rbac.authorization.k8s.io
for _m28o_e10_c in mediagenda-api medinotif-worker medidoc; do
  check_cmd "Component $_m28o_e10_c annoté backstage.io/kubernetes-id" _m28o_eq component "$_m28o_e10_c" \
    '(.metadata.annotations["backstage.io/kubernetes-id"] // "") != ""'
done
for _m28o_e10_ns in mediagenda-recette mediagenda-prod; do
  check_cmd "$_m28o_e10_ns : Rollout mediagenda étiqueté backstage.io/kubernetes-id=mediagenda-api" _m28d_kq \
    '.metadata.labels["backstage.io/kubernetes-id"] == "mediagenda-api"' -n "$_m28o_e10_ns" rollouts.argoproj.io mediagenda
done
check_cmd "Component mediagenda-api annoté backstage.io/techdocs-ref" _m28o_eq component mediagenda-api \
  '(.metadata.annotations["backstage.io/techdocs-ref"] // "") != ""'
check_cmd "site TechDocs publié : portail-techdocs/default/component/mediagenda-api/index.html" \
  _m28o_s3_objet portail-techdocs default/component/mediagenda-api/index.html
check_cmd "mediagenda/api (main) : la CI publie la documentation (techdocs-cli publish)" \
  _m28d_contient mediagenda/api .gitlab-ci.yml 'techdocs-cli.* publish|techdocs-cli publish'
