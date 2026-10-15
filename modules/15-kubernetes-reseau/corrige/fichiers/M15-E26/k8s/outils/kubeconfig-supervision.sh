#!/usr/bin/env bash
# outils/kubeconfig-supervision.sh — construit ~/.config/workbook/k8s-supervision.kubeconfig (600)
# pour le compte de service ms-supervision (M15-E26). À lancer sur adm01 avec TON kubeconfig personnel
# (lecture du Secret de jeton : réservée aux administrateurs). Le jeton ne passe jamais en argument.
# Usage : outils/kubeconfig-supervision.sh [FICHIER_SORTIE]
set -euo pipefail
umask 077

sortie="${1:-$HOME/.config/workbook/k8s-supervision.kubeconfig}"
serveur=https://k8s-api.par1.medisphere.internal:8443
espace=supervision
secret=ms-supervision-jeton

command -v kubectl >/dev/null || { echo "kubectl absent" >&2; exit 1; }
mkdir -p "$(dirname "$sortie")"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Attendre que le contrôleur ait rempli le Secret (jeton et CA).
for _ in $(seq 1 20); do
  if kubectl -n "$espace" get secret "$secret" -o jsonpath='{.data.token}' 2>/dev/null | grep -q .; then break; fi
  sleep 1
done
kubectl -n "$espace" get secret "$secret" -o jsonpath='{.data.ca\.crt}' | base64 -d >"$tmp/ca.crt"
kubectl -n "$espace" get secret "$secret" -o jsonpath='{.data.token}' | base64 -d >"$tmp/jeton"
[[ -s "$tmp/ca.crt" && -s "$tmp/jeton" ]] || { echo "Secret $espace/$secret incomplet" >&2; exit 1; }

# Le kubeconfig est écrit d'un bloc (jeton jamais en argument d'une commande, donc jamais dans ps).
{
  echo "apiVersion: v1"
  echo "kind: Config"
  echo "clusters:"
  echo "- name: k8s-par1"
  echo "  cluster:"
  echo "    server: $serveur"
  printf '    certificate-authority-data: %s\n' "$(base64 -w0 <"$tmp/ca.crt")"
  echo "users:"
  echo "- name: ms-supervision"
  echo "  user:"
  printf '    token: %s\n' "$(<"$tmp/jeton")"
  echo "contexts:"
  echo "- name: ms-supervision@k8s-par1"
  echo "  context: {cluster: k8s-par1, user: ms-supervision, namespace: $espace}"
  echo "current-context: ms-supervision@k8s-par1"
} >"$tmp/kubeconfig"

install -m 600 "$tmp/kubeconfig" "$sortie"
echo "Écrit : $sortie"
# Preuves attendues : lecture des nœuds permise, lecture des Secrets refusée.
kubectl --kubeconfig "$sortie" auth can-i list nodes
kubectl --kubeconfig "$sortie" auth can-i get secrets -n kube-system || true
