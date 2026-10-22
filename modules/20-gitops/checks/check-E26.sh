# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E26.sh — M20-E26 « Multi-cluster : le cluster de l'agence LYO1 » (PLAT-2126)
# À lancer depuis adm01. Lecture seule : configuration de la VM 2201 sur pve01 (qm config), nœud,
# droits et Deployment de lyo-k3s01 (SSH, sudo -n k3s kubectl get), clusters vus par l'API d'Argo CD
# (jeton ci-lecture), Applications (wb-checks), GitLab (code et documentation sur main).

# shellcheck source=_m20-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-production.sh"

title "M20-E26 — Multi-cluster : le cluster de l'agence LYO1"
require_cmd kubectl jq curl ssh
check_cmd "l'API du cluster k8s-par1 répond (readyz)" _m20p_joignable

title "VM 2201 lyo-k3s01"
check_ssh_output "pve01 : VM 2201 nommée lyo-k3s01, étiquette env-m20" "$WB_PVE_HOST" '^ok$' \
  "qm config 2201 | grep -q '^name: lyo-k3s01\$' && qm config 2201 | grep -Eq '^tags:.*env-m20' && echo ok"
check_ssh_output "pve01 : carte sur vsandbox (VLAN 99)" "$WB_PVE_HOST" '^ok$' \
  "qm config 2201 | grep -Eq '^net[0-9]+:.*(bridge=vsandbox|tag=99)' && echo ok"
_m20_e26_code() {
  local f
  while IFS= read -r f; do
    [[ "$f" == *.tf ]] || continue
    _m20p_fichier_contient plateforme/infra "$f" 'vmid *= *2201' '10\.10\.99\.61' && return 0
  done < <(_m20p_arbre plateforme/infra envs/m20)
  return 1
}
check_cmd "plateforme/infra : lyo-k3s01 (VMID 2201, 10.10.99.61) décrite dans envs/m20 sur main" _m20_e26_code

title "k3s sur lyo-k3s01"
_m20_e26_noeud="$(_m20p_lyo get node lyo-k3s01)"
check_cmd "nœud lyo-k3s01 Ready" _m20p_jq "$_m20_e26_noeud" \
  'any(.status.conditions[]; .type == "Ready" and .status == "True")'
check_cmd "k3s en v1.36.5+k3s1" _m20p_jq "$_m20_e26_noeud" '.status.nodeInfo.kubeletVersion == "v1.36.5+k3s1"'
_m20_e26_crb="$(_m20p_lyo get clusterrolebindings)"
_m20_e26_rb="$(_m20p_lyo get rolebindings -A)"
_M20_E26_SUJET='any(.subjects[]?; .kind == "ServiceAccount" and .name == "argocd-gestion")'
check_cmd "argocd-gestion n'est lié à aucun ClusterRole (aucun ClusterRoleBinding)" _m20p_jq "$_m20_e26_crb" \
  "[.items[] | select($_M20_E26_SUJET)] | length == 0"
check_cmd "argocd-gestion n'a de RoleBinding que dans l'espace agence (et en a un)" _m20p_jq "$_m20_e26_rb" \
  "[.items[] | select($_M20_E26_SUJET) | .metadata.namespace] | length > 0 and all(.[]; . == \"agence\")"
check_cmd "le RoleBinding d'argocd-gestion ne vise ni cluster-admin, ni admin" _m20p_jq "$_m20_e26_rb" \
  "all(.items[] | select($_M20_E26_SUJET); .roleRef.name != \"cluster-admin\" and .roleRef.name != \"admin\")"

title "Le cluster dans Argo CD"
_m20_e26_clusters="$(_m20p_argocd_api clusters 2>/dev/null || echo null)"
_m20_e26_c="$(jq -c --arg s "$_M20P_LYO_SERVEUR" '[.items[]? | select(.server == $s)][0] // null' <<<"$_m20_e26_clusters" 2>/dev/null || echo null)"
check_cmd "cluster $_M20P_LYO_SERVEUR enregistré" _m20p_jq "$_m20_e26_c" '.server != null'
check_cmd "étiquette site=lyo1 sur le Secret de cluster" _m20p_jq "$_m20_e26_c" '.labels.site == "lyo1"'
check_cmd "limité à l'espace agence (namespaces = [agence]), sans objets de cluster" _m20p_jq "$_m20_e26_c" \
  '(.namespaces // []) == ["agence"] and ((.clusterResources // false) == false)'
check_cmd "état de connexion Successful" _m20p_jq "$_m20_e26_c" \
  '((.info.connectionState.status // .connectionState.status) // "") == "Successful"'

title "ApplicationSet labo-agences"
_m20_e26_apps="$(_m20p_json -n argocd get applications.argoproj.io)"
_m20_e26_app="$(jq -c --arg s "$_M20P_LYO_SERVEUR" '[.items[]? | select(.spec.destination.server == $s and .spec.destination.namespace == "agence")][0] // null' \
  <<<"$_m20_e26_apps" 2>/dev/null || echo null)"
check_cmd "une Application déploie dans agence de lyo-k3s01, générée par l'ApplicationSet labo-agences" _m20p_jq "$_m20_e26_app" \
  'any(.metadata.ownerReferences[]?; .kind == "ApplicationSet" and .name == "labo-agences")'
check_cmd "cette Application est dans le projet labo" _m20p_jq "$_m20_e26_app" '.spec.project == "labo"'
check_cmd "cette Application est Synced/Healthy" _m20p_app_saine "$_m20_e26_app"
check_cmd "le Deployment labo de agence est prêt sur lyo-k3s01" _m20p_jq "$(_m20p_lyo -n agence get deployment labo)" \
  '(.status.readyReplicas // 0) >= 1 and (.status.readyReplicas // 0) == (.spec.replicas // 1)'

title "Flux et documentation"
check_cmd "matrice des flux de la bordure : K8S_TRAV → 10.10.99.61:6443" \
  _m20p_doc docs/socle/matrice-flux.md '10\.10\.99\.61' '6443'
check_cmd "docs/livraison/gitops/multi-cluster.md sur main (namespaces, clusterResources)" \
  _m20p_doc docs/livraison/gitops/multi-cluster.md 'namespaces' 'clusterResources'
