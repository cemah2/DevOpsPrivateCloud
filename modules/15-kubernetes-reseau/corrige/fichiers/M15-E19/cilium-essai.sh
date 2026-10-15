#!/usr/bin/env bash
# ~/m15/e19/cilium-essai.sh — Cilium sur m15-essai (depuis adm01, KUBECONFIG=~/.kube/m15-essai.conf).
# ⚠️ Le pool d'adresses de pods par défaut de Cilium (cluster-pool) est 10.0.0.0/8 : il RECOUVRE le
# lab (10.10.0.0/16). On le fixe explicitement à un réseau qui n'existe nulle part ailleurs.
# kube-proxy conservé (défaut kubeadm), aucun pool LB IPAM : MetalLB attribue les adresses.
set -euo pipefail
cilium install --version 1.20.2 \
  --set ipam.mode=cluster-pool \
  --set ipam.operator.clusterPoolIPv4PodCIDRList=10.244.0.0/16
cilium status --wait
