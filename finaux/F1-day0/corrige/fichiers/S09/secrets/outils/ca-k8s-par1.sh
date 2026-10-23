#!/usr/bin/env bash
# plateforme/secrets — outils/ca-k8s-par1.sh (F1-S09, SEC-3109 ; prévention de F1-S12, INC-5712)
# Autorité de certification du cluster k8s-par1, dont OpenBao a besoin pour vérifier le certificat de
# l'API quand il appelle TokenReview (méthode « kubernetes » montée en k8s-par1/, tofu/auth-k8s-par1.tf).
#
#   outils/ca-k8s-par1.sh ecrire     racine/k8s-par1-ca.crt ← ConfigMap publique kube-root-ca.crt du
#                                    cluster (lue avec ton kubeconfig), après contrôle TLS ; à committer
#                                    par MR (le pipeline applique) : jamais d'écriture directe dans OpenBao
#   outils/ca-k8s-par1.sh verifier   sans aucun identifiant Kubernetes :
#                                      1. le fichier du dépôt vérifie le certificat présenté par l'API
#                                         (https://k8s-api.par1.medisphere.internal:8443) ;
#                                      2. si une session OpenBao est disponible (BAO_TOKEN ou jeton de la
#                                         CI), l'autorité de auth/k8s-par1/config est celle du fichier.
#                                    Code 1 au moindre écart : c'est le job planifié qui aurait vu INC-5712.
# Prérequis : openssl ; ecrire : kubectl ; verifier (2) : bao.

set -euo pipefail

ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FICHIER="$ICI/racine/k8s-par1-ca.crt"
API_HOTE="${API_HOTE:-k8s-api.par1.medisphere.internal}"
API_PORT="${API_PORT:-8443}"
CTX="${KUBECTL_CONTEXTE:-k8s-par1}"

empreinte() { openssl x509 -noout -fingerprint -sha256 | sed 's/^.*=//'; }

# api_verifiee FICHIER_CA — la poignée de main TLS avec l'API réussit avec cette seule autorité.
api_verifiee() {
  openssl s_client -connect "$API_HOTE:$API_PORT" -servername "$API_HOTE" -CAfile "$1" \
    -verify_return_error </dev/null 2>/dev/null | grep -q 'Verify return code: 0 (ok)'
}

ecrire() {
  local tmp
  tmp="$(mktemp)"
  kubectl --context "$CTX" -n default get configmap kube-root-ca.crt -o jsonpath='{.data.ca\.crt}' >"$tmp"
  openssl x509 -noout -in "$tmp" || { rm -f "$tmp"; echo "ConfigMap kube-root-ca.crt illisible" >&2; exit 1; }
  if ! api_verifiee "$tmp"; then
    rm -f "$tmp"
    echo "Cette autorité ne vérifie PAS le certificat de $API_HOTE:$API_PORT : contexte « $CTX » sur le bon cluster ?" >&2
    exit 1
  fi
  mv "$tmp" "$FICHIER"
  chmod 644 "$FICHIER"
  echo "racine/k8s-par1-ca.crt : $(empreinte <"$FICHIER")"
  openssl x509 -noout -subject -dates <"$FICHIER"
  echo "À committer par MR (le pipeline applique tofu/auth-k8s-par1.tf)."
}

verifier() {
  local ko=0 b
  if api_verifiee "$FICHIER"; then
    echo "OK  racine/k8s-par1-ca.crt vérifie l'API de $API_HOTE"
  else
    echo "KO  racine/k8s-par1-ca.crt NE vérifie PAS l'API de $API_HOTE (cluster reconstruit ? autorité renouvelée ?)"
    ko=1
  fi
  if command -v bao >/dev/null 2>&1 && bao token lookup >/dev/null 2>&1; then
    b="$(bao read -field=kubernetes_ca_cert auth/k8s-par1/config | empreinte)"
    if [[ "$b" == "$(empreinte <"$FICHIER")" ]]; then
      echo "OK  OpenBao (auth/k8s-par1/config) utilise l'autorité du dépôt"
    else
      echo "KO  OpenBao (auth/k8s-par1/config) utilise une AUTRE autorité que le dépôt ($b)"
      ko=1
    fi
  else
    echo "--  OpenBao non vérifié (pas de session)"
  fi
  return "$ko"
}

case "${1:-}" in
  ecrire) ecrire ;;
  verifier) verifier ;;
  *) echo "Usage : $0 ecrire | verifier" >&2; exit 2 ;;
esac
