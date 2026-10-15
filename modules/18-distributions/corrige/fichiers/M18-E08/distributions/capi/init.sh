#!/usr/bin/env bash
# capi/init.sh — installe les fournisseurs de Cluster API dans un cluster de gestion (M18-E08, E12).
#
#   capi/init.sh <kubeconfig> proxmox     cœur + kubeadm + CAPMOX + IPAM in-cluster (cas nominal)
#   capi/init.sh <kubeconfig> docker      cœur + kubeadm + CAPD (repli de la vérification préalable)
#
# AUCUN identifiant Proxmox ici : CAPMOX démarre sans client global (PROXMOX_URL vide) et chaque
# cluster apporte les siens (ProxmoxCluster.spec.credentialsRef, M18-E10). C'est aussi ce qui
# permet le pivot (E12) sans recopier de secret à la main.
# Versions : capi/versions.env (toutes explicites : clusterctl prendrait sinon la dernière).
set -euo pipefail

ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=versions.env
source "$ICI/versions.env"

kubeconfig="${1:?usage : $0 <kubeconfig> proxmox|docker}"
infra="${2:?usage : $0 <kubeconfig> proxmox|docker}"
[[ -r "$kubeconfig" ]] || { echo "kubeconfig illisible : $kubeconfig" >&2; exit 1; }

args=(
  --kubeconfig "$kubeconfig"
  --core "cluster-api:${CAPI_VERSION}"
  --bootstrap "kubeadm:${CAPI_VERSION}"
  --control-plane "kubeadm:${CAPI_VERSION}"
  --wait-providers
)
case "$infra" in
  proxmox)
    args+=(--infrastructure "proxmox:${CAPMOX_VERSION}" --ipam "in-cluster:${IPAM_INCLUSTER_VERSION}")
    # Pas d'identifiants globaux : les variables du gabarit du fournisseur restent vides.
    unset PROXMOX_URL PROXMOX_TOKEN PROXMOX_SECRET
    ;;
  docker)
    # CAPD a besoin de ClusterClass pour ses gabarits (documentation de démarrage de CAPI).
    export CLUSTER_TOPOLOGY=true
    args+=(--infrastructure "docker:${CAPD_VERSION}")
    ;;
  *)
    echo "fournisseur inconnu : $infra (proxmox ou docker)" >&2; exit 1 ;;
esac

clusterctl init "${args[@]}"
kubectl --kubeconfig "$kubeconfig" get providers.clusterctl.cluster.x-k8s.io -A
