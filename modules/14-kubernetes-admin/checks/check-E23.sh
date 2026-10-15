# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E23.sh — M14-E23 : Le cluster décrit par le code
# À lancer depuis adm01. Lecture seule : dépôt plateforme/k8s (GitLab), nœuds et ConfigMap
# kube-system/kubeadm-config (« kube »), documentation.

# shellcheck source=_m14-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-operationnel.sh"

title "M14-E23 — Le cluster décrit par le code"
require_cmd jq kubectl curl yq

for _m14o_e23_f in README.md Taskfile.yml .gitlab-ci.yml cluster/kubeadm-config.yaml cluster/noeuds.yaml; do
  check_cmd "plateforme/k8s : $_m14o_e23_f sur main" _m14o_fichier_main "$_M14O_P_K8S" "$_m14o_e23_f"
done
_m14o_e23_arbre="$(_m14o_arbre "$_M14O_P_K8S" "")"
for _m14o_e23_d in composants espaces rbac admission ordonnancement outils; do
  check_output "plateforme/k8s : dossier $_m14o_e23_d/ non vide" "^$_m14o_e23_d/" echo "$_m14o_e23_arbre"
done
check_cmd "plateforme/k8s : dernier pipeline de main réussi" _m14o_pipeline_ok "$_M14O_P_K8S"
check_output "la CI valide les schémas des objets (kubeconform ou équivalent)" 'kubeconform|kubeval|--dry-run' \
  _m14o_contenu_main "$_M14O_P_K8S" .gitlab-ci.yml
_m14o_e23_task="$(_m14o_contenu_main "$_M14O_P_K8S" Taskfile.yml)"
check_output "Taskfile : une tâche de dérive ou de différence" '^  (derive|diff|drift)[a-z-]*:' echo "$_m14o_e23_task"
check_output "Taskfile : une tâche de vérification de conformité" '^  (verifier|verif|conformite)[a-z-]*:' echo "$_m14o_e23_task"

# Étiquettes et taints conformes à cluster/noeuds.yaml (main).
_m14o_e23_noeuds_yaml="$(_m14o_contenu_main "$_M14O_P_K8S" cluster/noeuds.yaml)"
_m14o_e23_n="$(_m14o_k get nodes -o json)"
_m14o_e23_conforme() {
  local attendu
  attendu="$(yq -o=json '.noeuds' <<<"$_m14o_e23_noeuds_yaml" 2>/dev/null)" || return 1
  [[ -n "$attendu" && "$attendu" != null ]] || return 1
  jq -e -n --argjson a "$attendu" --argjson n "$_m14o_e23_n" '
    ($n.items | map({(.metadata.name): .}) | add) as $k
    | ($a | keys | length) >= 6
    and ($a | to_entries | all(.key as $nom | .value as $v | $k[$nom] != null
      and (($v.etiquettes // {}) | to_entries | all(.key as $c | .value as $val | $k[$nom].metadata.labels[$c] == $val))
      and (($v.taints // []) | all(.cle as $c | .valeur as $val | .effet as $e
            | any($k[$nom].spec.taints[]?; .key == $c and .value == $val and .effect == $e)))))' >/dev/null 2>&1
}
check_cmd "étiquettes et taints des nœuds conformes à cluster/noeuds.yaml" _m14o_e23_conforme

# Paramètres principaux de kubeadm : dépôt contre ConfigMap kube-system/kubeadm-config.
_m14o_e23_depot="$(_m14o_contenu_main "$_M14O_P_K8S" cluster/kubeadm-config.yaml | yq ea -N -o=json 'select(.kind == "ClusterConfiguration")' 2>/dev/null || true)"
_m14o_e23_vivant="$(_m14o_k get configmap kubeadm-config -n kube-system -o json | jq -r '.data.ClusterConfiguration // ""' 2>/dev/null | yq -o=json 2>/dev/null || true)"
_m14o_e23_kubeadm() {
  jq -e -n --argjson d "${_m14o_e23_depot:-null}" --argjson v "${_m14o_e23_vivant:-null}" '
    $d != null and $v != null
    and ($d.kubernetesVersion == $v.kubernetesVersion) and ($d.controlPlaneEndpoint == $v.controlPlaneEndpoint)
    and ($d.networking.podSubnet == $v.networking.podSubnet) and ($d.networking.serviceSubnet == $v.networking.serviceSubnet)' >/dev/null 2>&1
}
check_cmd "kubeadm : version, point d'accès et sous-réseaux du dépôt = ceux du cluster" _m14o_e23_kubeadm

# k8s-w02 recréé pendant l'exercice : nœud nettement plus récent que le cluster (espace kube-system).
_m14o_e23_recent() {
  local ks w
  ks="$(_m14o_k get namespace kube-system -o jsonpath='{.metadata.creationTimestamp}')"
  w="$(jq -r '.items[] | select(.metadata.name == "k8s-w02") | .metadata.creationTimestamp' <<<"$_m14o_e23_n" 2>/dev/null)"
  [[ -n "$ks" && -n "$w" ]] && (( $(date -d "$w" +%s) - $(date -d "$ks" +%s) > 86400 ))
}
check_cmd "k8s-w02 a été recréé (nœud plus récent d'au moins un jour que le cluster)" _m14o_e23_recent
check_cmd "k8s-w02 est Ready" _m14o_json "$_m14o_e23_n" \
  'any(.items[]; .metadata.name == "k8s-w02" and any(.status.conditions[]; .type == "Ready" and .status == "True"))'
check_cmd "aucun nœud SchedulingDisabled" _m14o_json "$_m14o_e23_n" '[.items[] | select(.spec.unschedulable == true)] | length == 0'
check_cmd "plateforme/medisphere : docs/kubernetes/reconstruction.md sur main" \
  _m14o_fichier_main "$_M14O_P_DOC" docs/kubernetes/reconstruction.md
check_output "reconstruction.md contient un compte rendu chiffré (durées)" '[0-9]+ ?(min|s\b|h\b)' \
  _m14o_contenu_main "$_M14O_P_DOC" docs/kubernetes/reconstruction.md
