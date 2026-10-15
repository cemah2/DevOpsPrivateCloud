#!/usr/bin/env bash
# outils/secrets-en-clair.sh — plateforme/k8s (M14-E28) : compte, dans etcd, les Secrets par préfixe de
# stockage (k8s:enc:<fournisseur>:v1:<clé> ou « clair »), sans jamais afficher une valeur.
# Lecture seule, sur un nœud de contrôle (etcdctl du rôle etcd_instantane). Code 1 s'il reste du clair.
# Usage : outils/secrets-en-clair.sh [NŒUD]   (défaut k8s-cp01)
set -Eeuo pipefail
noeud="${1:-k8s-cp01}"
# shellcheck disable=SC2016  # évalué sur le nœud
ssh "$noeud" 'sudo -n bash -s' <<'DISTANT'
set -Eeuo pipefail
export ETCDCTL_ENDPOINTS=https://127.0.0.1:2379 ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt
export ETCDCTL_CERT=/etc/kubernetes/pki/etcd/healthcheck-client.crt ETCDCTL_KEY=/etc/kubernetes/pki/etcd/healthcheck-client.key
bilan="$(etcdctl get /registry/secrets/ --prefix --keys-only | while read -r cle; do
  [ -n "$cle" ] || continue
  debut="$(etcdctl get "$cle" --print-value-only | head -c 48 | tr -c '[:print:]' '.')" || true
  case "$debut" in
    k8s:enc:*) echo "$debut" | cut -d: -f3,5 ;;
    *) echo clair ;;
  esac
done | sort | uniq -c)"
echo "$bilan"
if grep -q ' clair$' <<<"$bilan"; then exit 1; fi
exit 0
DISTANT
