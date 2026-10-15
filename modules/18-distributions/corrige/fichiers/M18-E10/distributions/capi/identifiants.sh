#!/usr/bin/env bash
# capi/identifiants.sh — crée les Secrets de capi-essai dans le cluster de gestion (M18-E10).
#
#   admin@adm01:~/src/distributions$ capi/identifiants.sh ~/.config/workbook/m18/kind-gestion.kubeconfig
#
# 1. capi-essai-proxmox : identifiants Proxmox de CAPMOX (credentialsRef du ProxmoxCluster).
#    Clés lues par CAPMOX v0.9.1 : url, token, secret, insecure, root_ca. SANS « insecure »,
#    CAPMOX NE VÉRIFIE PAS le certificat de pve01 : on écrit insecure=false et on donne l'ancre.
# 2. medisphere-root-ca : racine MédiSphère pour les nœuds (fichier du KubeadmConfig).
# Les valeurs viennent de fichiers 600 de adm01 et passent par l'entrée standard de kubectl :
# rien sur la ligne de commande, rien dans un dépôt. Les deux Secrets portent l'étiquette
# clusterctl.cluster.x-k8s.io/move pour suivre le cluster lors du pivot (E12) ; le premier la
# reçoit aussi de CAPMOX (ownerRef), le second non.
set -euo pipefail

kubeconfig="${1:?usage : $0 <kubeconfig du cluster de gestion>}"
ENV_FILE="${ENV_FILE:-$HOME/.config/workbook/pve-capi.env}"
ANCRE_PVE="${ANCRE_PVE:-$HOME/.config/workbook/pve-root-ca.pem}"
RACINE="${RACINE:-/usr/local/share/ca-certificates/medisphere-root-ca.crt}"
ESPACE=capi-essai

[[ "$(stat -c %a "$ENV_FILE")" == 600 ]] || { echo "$ENV_FILE doit être en 600" >&2; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"
: "${PROXMOX_URL:?}" "${PROXMOX_TOKEN:?}" "${PROXMOX_SECRET:?}"

k() { kubectl --kubeconfig "$kubeconfig" "$@"; }

k create namespace "$ESPACE" --dry-run=client -o yaml | k apply -f -

# Secret d'identifiants : manifeste construit par jq (JSON), lu par kubectl sur son entrée standard.
jq -n --arg url "$PROXMOX_URL" --arg token "$PROXMOX_TOKEN" --arg secret "$PROXMOX_SECRET" \
  --rawfile ca "$ANCRE_PVE" --arg ns "$ESPACE" '{
    apiVersion: "v1", kind: "Secret", type: "Opaque",
    metadata: {name: "capi-essai-proxmox", namespace: $ns, labels: {
      "platform.ionos.com/secret-type": "proxmox-credentials",
      "clusterctl.cluster.x-k8s.io/move": ""}},
    stringData: {url: $url, token: $token, secret: $secret, insecure: "false", root_ca: $ca}
  }' | k apply -f -

k create secret generic medisphere-root-ca --namespace "$ESPACE" --from-file=ca.crt="$RACINE" \
  --dry-run=client -o yaml \
  | k label --local -f - clusterctl.cluster.x-k8s.io/move="" -o yaml \
  | k apply -f -

k -n "$ESPACE" get secrets -l clusterctl.cluster.x-k8s.io/move
