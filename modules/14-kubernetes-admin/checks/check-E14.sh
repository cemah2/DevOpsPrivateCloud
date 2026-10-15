# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E14.sh — M14-E14 : Ordonnancement : affinités, taints et répartition
# À lancer depuis adm01. Lecture seule : nœuds, pods, PriorityClasses (« kube »), API GitLab.

# shellcheck source=_m14-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-operationnel.sh"

title "M14-E14 — Ordonnancement : affinités, taints et répartition"
require_cmd jq kubectl curl

_m14o_e14_n="$(_m14o_k get nodes -o json)"
for _m14o_e14_x in "${!_M14O_ZONE[@]}"; do
  check_cmd "$_m14o_e14_x : zone ${_M14O_ZONE[$_m14o_e14_x]}" _m14o_json "$_m14o_e14_n" \
    'any(.items[]; .metadata.name == $n and .metadata.labels["topology.kubernetes.io/zone"] == $z)' \
    --arg n "$_m14o_e14_x" --arg z "${_M14O_ZONE[$_m14o_e14_x]}"
done
check_cmd "k8s-w03 : étiquette medisphere.internal/dedie=bdd et taint dedie=bdd:NoSchedule" _m14o_json "$_m14o_e14_n" \
  'any(.items[]; .metadata.name == "k8s-w03" and .metadata.labels["medisphere.internal/dedie"] == "bdd"
     and any(.spec.taints[]?; .key == "dedie" and .value == "bdd" and .effect == "NoSchedule"))'
check_cmd "seul k8s-w03 porte la taint dedie=bdd" _m14o_json "$_m14o_e14_n" \
  '[.items[] | select(any(.spec.taints[]?; .key == "dedie")) | .metadata.name] == ["k8s-w03"]'

_m14o_e14_pc="$(_m14o_k get priorityclasses -o json)"
check_cmd "PriorityClasses : critique 100000 > standard 10000 > essai 100 (Never), aucune par défaut" _m14o_json "$_m14o_e14_pc" '
  (reduce .items[] as $i ({}; .[$i.metadata.name] = $i)) as $p
  | $p["medisphere-critique"].value == 100000 and $p["medisphere-standard"].value == 10000
    and $p["medisphere-essai"].value == 100 and $p["medisphere-essai"].preemptionPolicy == "Never"
    and ([$p["medisphere-critique","medisphere-standard","medisphere-essai"].globalDefault] | all(. != true))'

_m14o_e14_pods="$(_m14o_k get pods -n mediagenda-dev -o json)"
check_cmd "PostgreSQL de mediagenda-dev tourne sur k8s-w03 en medisphere-critique" _m14o_json "$_m14o_e14_pods" \
  '[.items[] | select(.metadata.labels["app.kubernetes.io/name"] == "postgresql" and .status.phase == "Running")]
   | length >= 1 and all(.spec.nodeName == "k8s-w03" and .spec.priorityClassName == "medisphere-critique")'
check_cmd "aucun pod applicatif sur k8s-w03 hors bases de données et DaemonSets" _m14o_json "$(_m14o_k get pods -A -o json)" '
  [.items[] | select(.spec.nodeName == "k8s-w03" and (.status.phase == "Running" or .status.phase == "Pending"))
   | select((.metadata.ownerReferences // []) | all(.kind != "DaemonSet"))
   | select(.metadata.namespace != "kube-system")
   | select(any(.spec.tolerations[]?; .key == "dedie") | not)] | length == 0'
_m14o_e14_api='[.items[] | select(.metadata.labels["app.kubernetes.io/name"] == "mediagenda-api")]'
check_cmd "API : 3 réplicas prêts, en medisphere-standard" _m14o_json "$_m14o_e14_pods" "$_m14o_e14_api"'
  | map(select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))) | length >= 3
    and all(.spec.priorityClassName == "medisphere-standard")'
check_cmd "API : contrainte de répartition stricte par zone (maxSkew 1, DoNotSchedule)" _m14o_json "$_m14o_e14_pods" "$_m14o_e14_api"'
  | length >= 1 and all(any(.spec.topologySpreadConstraints[]?; .topologyKey == "topology.kubernetes.io/zone"
      and .maxSkew == 1 and .whenUnsatisfiable == "DoNotSchedule"))'
_m14o_e14_zones() {
  jq -n --argjson p "$_m14o_e14_pods" --argjson n "$_m14o_e14_n" '
    ($n.items | map({(.metadata.name): .metadata.labels["topology.kubernetes.io/zone"]}) | add) as $z
    | [$p.items[] | select(.metadata.labels["app.kubernetes.io/name"] == "mediagenda-api" and .spec.nodeName != null)
       | $z[.spec.nodeName]] | unique | length >= 2' -e >/dev/null 2>&1
}
check_cmd "API répartie sur au moins deux zones" _m14o_e14_zones
check_cmd "aucun pod Pending dans mediagenda-dev" _m14o_json "$_m14o_e14_pods" '[.items[] | select(.status.phase == "Pending")] | length == 0'
check_cmd "plateforme/k8s : cluster/noeuds.yaml sur main" _m14o_fichier_main "$_M14O_P_K8S" cluster/noeuds.yaml
check_cmd "plateforme/k8s : ordonnancement/priorites.yaml sur main" _m14o_fichier_main "$_M14O_P_K8S" ordonnancement/priorites.yaml
check_cmd "plateforme/k8s : outils/etiqueter-noeuds.sh sur main" _m14o_fichier_main "$_M14O_P_K8S" outils/etiqueter-noeuds.sh
