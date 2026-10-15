#!/usr/bin/env bash
# plateforme/k8s — outils/kubeconfig-supervision-stockage.sh (M16-E27)
# Produit ~/.config/workbook/k8s-supervision-stockage.kubeconfig (600) pour la sonde
# ms-verif-k8s-stockage : jeton LIÉ (TokenRequest) de 48 h du compte wb-system/ms-supervision-stockage,
# CA et adresse de l'API reprises du kubeconfig de l'administrateur. Lancé chaque jour par
# kubeconfig-supervision-stockage.timer (adm01) : le jeton n'est jamais à plus d'un jour de son
# expiration, et un jeton volé ne vaut que 48 h.
set -euo pipefail

sortie="${1:-$HOME/.config/workbook/k8s-supervision-stockage.kubeconfig}"
api="https://k8s-api.par1.medisphere.internal:8443"
sa=ms-supervision-stockage
ns=wb-system

jeton="$(kubectl create token "$sa" -n "$ns" --duration=48h)"
ca="$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
[[ -n "$jeton" && -n "$ca" ]] || { echo "jeton ou CA introuvable" >&2; exit 1; }

umask 077
tmp="$(mktemp "${sortie}.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
cat >"$tmp" <<FIN
apiVersion: v1
kind: Config
clusters:
- name: k8s-par1
  cluster:
    server: $api
    certificate-authority-data: $ca
users:
- name: $sa
  user:
    token: $jeton
contexts:
- name: supervision-stockage
  context: {cluster: k8s-par1, user: $sa}
current-context: supervision-stockage
FIN
mv "$tmp" "$sortie"
trap - EXIT
kubectl --kubeconfig "$sortie" auth whoami -o jsonpath='{.status.userInfo.username}{"\n"}'
