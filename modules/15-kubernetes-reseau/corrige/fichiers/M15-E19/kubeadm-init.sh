#!/usr/bin/env bash
# ~/m15/e19/kubeadm-init.sh — initialisation À LA MAIN du cluster d'essai (sur m15-essai, en root).
# Lancé par : ssh m15-essai 'sudo bash -s' < kubeadm-init.sh
set -euo pipefail
VERSION="${VERSION:-v1.36.5}"   # même patch que k8s-par1 (kubeadm version)
kubeadm init \
  --kubernetes-version "$VERSION" \
  --apiserver-advertise-address 10.10.99.51 \
  --control-plane-endpoint 10.10.99.51:6443 \
  --pod-network-cidr 10.244.0.0/16 \
  --service-cidr 10.97.0.0/16
# Mononœud : les pods applicatifs doivent pouvoir tourner sur le nœud de contrôle.
KUBECONFIG=/etc/kubernetes/admin.conf kubectl taint nodes --all node-role.kubernetes.io/control-plane-
