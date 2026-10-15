# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions yq et commandes bash -c entre apostrophes
#
# check-E11.sh — M18-E11 : revue des manifestes Cluster API du stagiaire
# À lancer depuis adm01. Lecture seule : GitLab en GET (capi/revue-lucas/ de plateforme/distributions),
# analyse des manifestes corrigés par yq (mikefarah) et jq.

# shellcheck source=_m18-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m18-operationnel.sh"

title "M18-E11 — Revue : les manifestes Cluster API du stagiaire"
require_cmd jq yq

_m18d_e11_p=plateforme/distributions
_m18d_e11_revue="$(_m18d_contenu_main "$_m18d_e11_p" capi/revue-lucas/REVUE.md)"
check_cmd "REVUE.md : au moins douze défauts listés (« - »)" bash -c '[[ $(grep -c "^- " <<<"$1") -ge 12 ]]' _ "$_m18d_e11_revue"
check_cmd "REVUE.md : gravités indiquées (bloquant, majeur, mineur)" bash -c \
  'grep -qi "bloquant" <<<"$1" && grep -qi "majeur" <<<"$1" && grep -qi "mineur" <<<"$1"' _ "$_m18d_e11_revue"

_m18d_e11_arbre="$(_m18d_arbre_main "$_m18d_e11_p" | grep '^capi/revue-lucas/' || true)"
check_cmd "Manifestes corrigés présents, sans identifiants.yaml" bash -c \
  'grep -qx "capi/revue-lucas/cluster.yaml" <<<"$1" && grep -qx "capi/revue-lucas/plan-controle.yaml" <<<"$1" \
   && grep -qx "capi/revue-lucas/travailleurs.yaml" <<<"$1" && ! grep -q "identifiants.yaml" <<<"$1"' _ "$_m18d_e11_arbre"

# Tous les YAML corrigés, convertis en un tableau JSON d'objets.
_m18d_e11_objets="$(grep '\.ya\?ml$' <<<"$_m18d_e11_arbre" | while read -r f; do _m18d_contenu_main "$_m18d_e11_p" "$f"; echo '---'; done \
  | yq -o=json -I=0 'select(. != null)' 2>/dev/null | jq -s . 2>/dev/null || true)"
_m18d_e11_j() { _m18d_json "$_m18d_e11_objets" "$@"; }

check_cmd "Aucun Secret dans les manifestes" _m18d_e11_j '(length > 0) and ([.[] | select(.kind == "Secret")] | length == 0)'
check_cmd "Identifiants par credentialsRef (Secret créé hors dépôt)" _m18d_e11_j \
  'any(.[]; .kind == "ProxmoxCluster" and (.spec.credentialsRef.name // "" | length > 0))'
check_cmd "VIP hors des plages de nœuds (150-169 de capi-essai, et la sienne), distincte de 10.10.40.210" _m18d_e11_j '
  [.[] | select(.kind == "ProxmoxCluster")][0] as $pc
  | ($pc.spec.controlPlaneEndpoint.host | split(".") | map(tonumber)) as $v
  | ($pc.spec.ipv4Config.addresses | map(split("-") | map(split(".") | map(tonumber)))) as $plages
  | $pc.spec.controlPlaneEndpoint.host != "10.10.40.210"
    and ($v[0:3] == [10, 10, 40]) and ($v[3] < 150 or $v[3] > 169)
    and all($plages[]; (.[0][3] > $v[3] or .[1][3] < $v[3]) and (.[0][3] > 169 or .[1][3] < 150))'
check_cmd "Résolveurs du lab seulement (10.10.20.10, 10.10.20.16)" _m18d_e11_j \
  '[.[] | select(.kind == "ProxmoxCluster")][0].spec.dnsServers | (length > 0) and all(.[]; . == "10.10.20.10" or . == "10.10.20.16")'
check_cmd "Réseau des pods hors de 192.168.0.0/16" _m18d_e11_j \
  '[.[] | select(.kind == "Cluster")][0].spec.clusterNetwork.pods.cidrBlocks | (length > 0) and all(.[]; startswith("192.168.") | not)'
check_cmd "Plan de contrôle : nombre impair de nœuds, Kubernetes v1.36.4 (template 9060), même version que les travailleurs" _m18d_e11_j '
  ([.[] | select(.kind == "KubeadmControlPlane")][0]) as $kcp | ([.[] | select(.kind == "MachineDeployment")][0]) as $md
  | ($kcp.spec.replicas % 2 == 1) and $kcp.spec.version == "v1.36.4" and $md.spec.template.spec.version == "v1.36.4"'
check_cmd "ProxmoxMachineTemplates : vk8s, pool lab, VMID 5180-5189, pas de qcow2, sélection de template valide" _m18d_e11_j '
  [.[] | select(.kind == "ProxmoxMachineTemplate") | .spec.template.spec] as $t | ($t | length >= 2) and all($t[];
    (.network.networkDevices[0].bridge == "vk8s") and .pool == "lab" and ((.format // "raw") != "qcow2")
    and .vmIDRange.start >= 5180 and .vmIDRange.end <= 5189
    and (.templateID == 9060 or ((.templateSelector.matchPolicy // "exact") | IN("exact", "uniqueSubset", "bestSubset"))))'
check_cmd "Nœuds de contrôle : au moins 2 vCPU et 2 Gio" _m18d_e11_j '
  ([.[] | select(.kind == "KubeadmControlPlane")][0].spec.machineTemplate.spec.infrastructureRef.name) as $n
  | [.[] | select(.kind == "ProxmoxMachineTemplate" and .metadata.name == $n) | .spec.template.spec][0]
  | ((.numSockets // 1) * (.numCores // 0)) >= 2 and (.memoryMiB // 0) >= 2048'
check_cmd "Aucun compte root déclaré par cloud-init" _m18d_e11_j \
  '(length > 0) and ([.. | objects | select(has("users")) | .users[]? | .name] | (index("root") | not))'
check_cmd "kube-vip : version fixée et correctif super-admin.conf" bash -c \
  'grep -Eq "ghcr.io/kube-vip/kube-vip:v[0-9]" <<<"$1" && ! grep -q "kube-vip:latest" <<<"$1" && grep -q "super-admin.conf" <<<"$1"' \
  _ "$(_m18d_contenu_main "$_m18d_e11_p" capi/revue-lucas/plan-controle.yaml)"
check_cmd "ClusterResourceSet : son sélecteur correspond aux étiquettes du Cluster" _m18d_e11_j '
  ([.[] | select(.kind == "Cluster")][0].metadata.labels // {}) as $l
  | [.[] | select(.kind == "ClusterResourceSet")] | (length >= 1) and all(.[]; .spec.clusterSelector.matchLabels | to_entries | all(.[]; $l[.key] == .value))'
