# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E13.sh — M18-E13 « Cycle de vie par Cluster API : montée de version, réparation, mise à l'échelle »
# Lecture seule : objets Cluster API de capi-essai (cluster de gestion k3s01), nœuds du cluster de charge de
# travail, étiquettes des templates sur pve01, fichiers sur main (GitLab).

# shellcheck source=_m18-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m18-production.sh"

title "M18-E13 — Cycle de vie par Cluster API"
require_cmd kubectl jq ssh
_e13_cible=v1.36.5
_e13_ns="$_M18P_ESPACE_CAPI"
check_cmd "le cluster de gestion k3s01 répond (readyz)" _m18p_joignable "$_M18P_KC_GESTION"

title "Réparation automatique (MachineHealthCheck)"
_e13_mhc="$(_m18p_gjson get machinehealthchecks.v1beta2.cluster.x-k8s.io -n "$_e13_ns")"
# MHC de capi-essai qui visent le MachineDeployment (et pas le plan de contrôle).
_e13_mt="$(jq -c '[.items[]? | select(.spec.clusterName == "capi-essai")
  | select((.spec.selector.matchLabels // {}) | has("cluster.x-k8s.io/deployment-name"))
  | select(((.spec.selector.matchLabels // {}) | has("cluster.x-k8s.io/control-plane")) | not)] | first // null' <<<"$_e13_mhc" 2>/dev/null)" || _e13_mt=null
check_cmd "un MachineHealthCheck de capi-essai vise le MachineDeployment des travailleurs, pas le plan de contrôle" \
  _m18p_jq "$_e13_mt" '.metadata.name'
check_cmd "MHC : aucun MachineHealthCheck ne sélectionne les machines du plan de contrôle" \
  _m18p_jq "$_e13_mhc" '[.items[]? | select(.spec.clusterName == "capi-essai") | select((.spec.selector.matchLabels // {}) | has("cluster.x-k8s.io/control-plane"))] | length == 0'
check_cmd "MHC : nœud malade si Ready=Unknown ET si Ready=False, chacun depuis 10 min au plus" _m18p_jq "$_e13_mt" '
  [.spec.checks.unhealthyNodeConditions[]? | select(.type == "Ready") | select(.timeoutSeconds <= 600) | .status]
  | (index("Unknown") != null) and (index("False") != null)'
check_cmd "MHC : délai de démarrage d'une machine neuve d'au moins 10 min" _m18p_jq "$_e13_mt" \
  '(.spec.checks.nodeStartupTimeoutSeconds // 600) >= 600 and (.spec.checks.nodeStartupTimeoutSeconds // 600) != 0'
# Seuil : nombre de réparations permises avec le nombre de machines visées = exactement 1.
check_cmd "MHC : le seuil d'arrêt permet exactement une réparation à la fois sur les machines visées" _m18p_jq "$_e13_mt" '
  (.status.expectedMachines // 0) as $n
  | (.spec.remediation.triggerIf.unhealthyLessThanOrEqualTo // "100%") as $s
  | (if ($s | type) == "number" then $s
     elif ($s | test("^[0-9]+%$")) then (($s | rtrimstr("%") | tonumber) * $n / 100 | floor)
     else ($s | tonumber) end) as $permis
  | $n >= 2 and $permis == 1'
check_cmd "MHC : toutes les machines visées sont saines (currentHealthy = expectedMachines ≥ 2)" _m18p_jq "$_e13_mt" \
  '(.status.expectedMachines // 0) >= 2 and .status.currentHealthy == .status.expectedMachines'

title "Version et gabarits ($_e13_cible, template 9061)"
_e13_kcp="$(_m18p_gjson get kubeadmcontrolplanes.v1beta2.controlplane.cluster.x-k8s.io -n "$_e13_ns" -l cluster.x-k8s.io/cluster-name=capi-essai)"
check_cmd "KCP : version $_e13_cible demandée et atteinte, toutes les machines à jour" _m18p_jq "$_e13_kcp" "
  (.items | length) == 1 and (.items[0] | .spec.version == \"$_e13_cible\" and .status.version == \"$_e13_cible\"
   and .status.upToDateReplicas == .spec.replicas and .status.readyReplicas == .spec.replicas)"
_e13_md="$(_m18p_gjson get machinedeployments.v1beta2.cluster.x-k8s.io -n "$_e13_ns")"
check_cmd "MachineDeployment : version $_e13_cible, réplicas prêts et à jour (2 ou plus)" _m18p_jq "$_e13_md" "
  [.items[]? | select(.spec.clusterName == \"capi-essai\")] | length >= 1 and all(.[];
   .spec.template.spec.version == \"$_e13_cible\" and (.spec.replicas // 0) >= 2
   and .status.readyReplicas == .spec.replicas and .status.upToDateReplicas == .spec.replicas)"
_e13_m="$(_m18p_gjson get machines.v1beta2.cluster.x-k8s.io -n "$_e13_ns" -l cluster.x-k8s.io/cluster-name=capi-essai)"
check_cmd "toutes les machines de capi-essai sont Running en $_e13_cible" _m18p_jq "$_e13_m" "
  (.items | length) >= 3 and all(.items[]; .status.phase == \"Running\" and .spec.version == \"$_e13_cible\")"
_e13_pm="$(_m18p_gjson get proxmoxmachines.v1alpha2.infrastructure.cluster.x-k8s.io -n "$_e13_ns" -l cluster.x-k8s.io/cluster-name=capi-essai)"
if _m18p_jq "$_e13_pm" '[.items[]? | .spec.templateID] | length > 0 and all(. != null)'; then
  check_cmd "toutes les ProxmoxMachine de capi-essai sont clonées depuis le template 9061" _m18p_jq "$_e13_pm" \
    '(.items | length) >= 3 and all(.items[]; .spec.templateID == 9061)'
else
  skip "ProxmoxMachine clonées depuis 9061" "sélection par étiquettes (templateSelector) : vérifie l'image à la main"
fi

title "Cluster de charge de travail"
check_cmd "l'API de capi-essai répond (VIP 10.10.40.210)" _m18p_joignable "$_M18P_KC_CAPI"
_e13_n="$(_m18p_json "$_M18P_KC_CAPI" get nodes)"
check_cmd "nœuds de capi-essai Ready, kubelets en $_e13_cible" _m18p_jq "$_e13_n" "
  (.items | length) >= 3 and all(.items[]; .status.nodeInfo.kubeletVersion == \"$_e13_cible\"
   and any(.status.conditions[]; .type == \"Ready\" and .status == \"True\"))"

title "Templates sur pve01"
_e13_tpl_neuf() { _m18p_a_tag 9061 capi && _m18p_a_tag 9061 current; }
_e13_tpl_ancien() { ! _m18p_a_tag 9060 current && _m18p_a_tag 9060 capi; }
check_cmd "template 9061 : étiquettes capi et current" _e13_tpl_neuf
if _m18p_pve "qm config 9060" | grep -q '^template: 1'; then
  check_cmd "template 9060 : plus d'étiquette current" _e13_tpl_ancien
else
  skip "template 9060 sans current" "9060 n'existe plus"
fi

title "Code et documentation"
check_cmd "plateforme/distributions (main) : un MachineHealthCheck sous capi/capi-essai/" \
  _m18p_un_fichier_contient plateforme/distributions capi/capi-essai 'kind: *MachineHealthCheck' 'unhealthyNodeConditions'
check_cmd "plateforme/distributions (main) : des gabarits ProxmoxMachineTemplate sur le template 9061" \
  _m18p_un_fichier_contient plateforme/distributions capi/capi-essai 'kind: *ProxmoxMachineTemplate' 'templateID: *9061'
check_cmd "RB-182 publié (préalables, ordre, retour arrière)" \
  _m18p_doc_prefixe docs/kubernetes/distributions/runbooks RB-182 'pr(é|e)alable' 'retour arri(è|e)re' 'KubeadmControlPlane|KCP' 'MachineDeployment'
check_cmd "compte rendu tests/cycle-de-vie-capi.md publié (réparation, mise à l'échelle, montée en $_e13_cible)" \
  _m18p_fichier_contient plateforme/medisphere docs/kubernetes/distributions/tests/cycle-de-vie-capi.md 'MachineHealthCheck|MHC' "${_e13_cible//./\\.}" '9061'
