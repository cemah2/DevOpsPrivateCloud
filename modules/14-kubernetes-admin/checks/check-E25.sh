# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E25.sh — M14-E25 « Monter le cluster de version : 1.35 → 1.36 »
# À lancer depuis adm01. Lecture seule : nœuds, pods du plan de contrôle et des modules (API, compte
# wb-checks), ConfigMap kubeadm-config, sources APT, épingles, versions et configuration de containerd
# sur chaque nœud (SSH, sudo -n pour « containerd config dump »), dépôts GitLab.

# shellcheck source=_m14-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-production.sh"

title "M14-E25 — Montée de version 1.35 → 1.36"
require_cmd kubectl jq ssh
check_cmd "l'API du cluster répond (readyz)" _m14p_joignable

# Mineure cible : texte simple (jq : startswith/contains) et motif grep (point échappé).
_M14_E25_MIN=1.36
_M14_E25_MINEURE='1\.36'
_m14_e25_noeuds="$(_m14p_json get nodes)"

title "Nœuds"
check_cmd "six nœuds au moins" _m14p_jq "$_m14_e25_noeuds" '(.items | length) >= 6'
check_cmd "tous les nœuds sont Ready" _m14p_jq "$_m14_e25_noeuds" \
  'all(.items[]; any(.status.conditions[]; .type == "Ready" and .status == "True"))'
check_cmd "aucun nœud n'est cordonné (SchedulingDisabled)" _m14p_jq "$_m14_e25_noeuds" \
  'all(.items[]; (.spec.unschedulable // false) | not)'
check_cmd "tous les kubelets sont en v1.36.x" _m14p_jq "$_m14_e25_noeuds" \
  "all(.items[]; .status.nodeInfo.kubeletVersion | startswith(\"v$_M14_E25_MIN.\"))"

title "Plan de contrôle et modules"
check_output "kubeadm-config : kubernetesVersion v1.36.x" "kubernetesVersion: v$_M14_E25_MINEURE\." _m14p_cc
for _m14_e25_n in "${_M14P_CP[@]}"; do
  for _m14_e25_c in kube-apiserver kube-controller-manager kube-scheduler; do
    check_cmd "$_m14_e25_c-$_m14_e25_n : image v1.36.x, pod prêt" bash -c \
      'jq -e --arg m ":v$2." "(.spec.containers[0].image | contains(\$m)) and .status.phase == \"Running\"" >/dev/null <<<"$1"' \
      _ "$(_m14p_pod_statique "$_m14_e25_c" "$_m14_e25_n")" "$_M14_E25_MIN"
  done
done
_m14_e25_etcd="$(_m14p_version_etcd_cluster || true)"
check_output "etcd en 3.6.8 ou plus récent (image de kubeadm 1.36)" '^ok$' \
  bash -c '[[ -n "$1" ]] && [[ "$(printf "%s\n3.6.8\n" "$1" | sort -V | head -1)" == 3.6.8 ]] && echo ok' _ "$_m14_e25_etcd"
check_output "CoreDNS en v1.14.x" 'coredns:v1\.14\.' \
  kube -n kube-system get deployment coredns -o 'jsonpath={.spec.template.spec.containers[0].image}'
check_output "kube-proxy en v1.36.x" "kube-proxy:v$_M14_E25_MINEURE\." \
  kube -n kube-system get daemonset kube-proxy -o 'jsonpath={.spec.template.spec.containers[0].image}'
check_cmd "Cilium : tous les agents prêts sur tous les nœuds" bash -c \
  'jq -e "(.status.desiredNumberScheduled // 0) >= 6 and .status.numberReady == .status.desiredNumberScheduled and .status.updatedNumberScheduled == .status.desiredNumberScheduled" >/dev/null <<<"$1"' \
  _ "$(_m14p_json -n kube-system get daemonset cilium)"

title "Paquets et runtime sur chaque nœud"
# Image pause attendue : celle que liste kubeadm de la version installée (lue sur le 1er nœud de contrôle).
_m14_e25_pause="$(remote "${_M14P_CP[0]}" 'kubeadm config images list --kubernetes-version "$(kubeadm version -o short)" 2>/dev/null' \
  | grep -E '/pause:' | head -1 || true)"
check_output "image pause attendue par kubeadm lue sur ${_M14P_CP[0]}" '/pause:[0-9.]+$' echo "$_m14_e25_pause"
for _m14_e25_n in "${_M14P_TOUS[@]}"; do
  check_ssh_output "$_m14_e25_n : dépôt pkgs.k8s.io de la 1.36, aucune autre mineure" "$_m14_e25_n" '^ok$' \
    "s=\$(grep -rhs 'pkgs.k8s.io' /etc/apt/sources.list /etc/apt/sources.list.d/); \
     echo \"\$s\" | grep -q '/v1.36/' && ! echo \"\$s\" | grep -Eq '/v1\.(3[0-5]|2[0-9])/' && echo ok"
  check_ssh_output "$_m14_e25_n : kubeadm, kubelet et kubectl épinglés" "$_m14_e25_n" '^3$' \
    "apt-mark showhold | grep -cxE 'kubeadm|kubelet|kubectl'"
  check_ssh_output "$_m14_e25_n : kubeadm en v1.36.x" "$_m14_e25_n" "^v$_M14_E25_MINEURE\." 'kubeadm version -o short'
  if [[ -n "$_m14_e25_pause" ]]; then
    check_ssh_output "$_m14_e25_n : containerd utilise l'image pause de kubeadm (${_m14_e25_pause##*/})" "$_m14_e25_n" \
      "^ok$" "sudo -n containerd config dump 2>/dev/null | grep -F '$_m14_e25_pause' >/dev/null && echo ok"
  fi
done
for _m14_e25_n in "${_M14P_CP[@]}"; do
  check_ssh_output "$_m14_e25_n : etcdutl en ${_m14_e25_etcd:-?} (version de l'etcd du cluster)" "$_m14_e25_n" '^ok$' \
    "/usr/local/bin/etcdutl version | grep -qx 'etcdutl version: ${_m14_e25_etcd:-inconnue}' && echo ok"
done

title "Code et documentation"
check_cmd "plateforme/k8s : cluster/kubeadm-config.yaml déclare la 1.36 sur main" \
  _m14p_fichier_contient plateforme/k8s cluster/kubeadm-config.yaml "kubernetesVersion: v$_M14_E25_MINEURE\."
check_cmd "plateforme/ansible : playbook de montée de version sur main" \
  _m14p_fichier_contient plateforme/ansible playbooks/k8s-montee-version.yml 'kubeadm upgrade (apply|node)' 'drain'
check_cmd "RB-142 sur main (drain, upgrade apply, upgrade node, retour arrière)" \
  _m14p_doc_prefixe docs/kubernetes/runbooks RB-142 'drain' 'upgrade apply' 'upgrade node' 'retour arri'
check_cmd "compte rendu de la montée sur main" \
  _m14p_fichier_contient plateforme/medisphere docs/kubernetes/tests/montee-1.36.md '1\.36'
