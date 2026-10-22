#!/usr/bin/env bash
# csr-forgee.sh — M26-E25, étape 3 : soumettre une demande kubelet-serving FORGÉE (nom hors de
# l'expression de l'approbateur) et constater qu'elle est REFUSÉE. La demande est créée EN SE FAISANT
# PASSER pour le kubelet de k8s-w01 (kubectl --as) : c'est le scénario du modèle de menace (un kubelet
# compromis qui demande un certificat au nom d'un autre service). Exige le droit « impersonate »
# (groupe plateforme-admins) ; l'usurpation est tracée dans le journal d'audit (impersonatedUser).
# La clé et la demande vivent dans $XDG_RUNTIME_DIR (mémoire) et sont supprimées, ainsi que l'objet
# CSR, à la fin.
# Usage : ./csr-forgee.sh [NOM]      (défaut : sso — « je suis le serveur sso », exemple du README amont)
set -Eeuo pipefail
umask 077
nom="${1:-sso}"
noeud=k8s-w01
dossier="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/csr-forgee.XXXXXX")"
objet="wb-essai-forgee-$(date +%s)"
trap 'rm -rf "$dossier"; kubectl delete csr "$objet" --ignore-not-found >/dev/null 2>&1 || true' EXIT

openssl ecparam -name prime256v1 -genkey -noout -out "$dossier/cle.pem"
openssl req -new -key "$dossier/cle.pem" -out "$dossier/demande.pem" \
  -subj "/O=system:nodes/CN=system:node:$noeud" \
  -addext "subjectAltName=DNS:$nom.par1.medisphere.internal,IP:10.10.20.30"

kubectl create --as="system:node:$noeud" --as-group=system:nodes --as-group=system:authenticated -f - <<YAML
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: $objet
spec:
  signerName: kubernetes.io/kubelet-serving
  # Clé ECDSA : pas de « key encipherment » (réservé à RSA).
  usages: [digital signature, server auth]
  request: $(base64 -w0 "$dossier/demande.pem")
YAML

echo "Demande $objet soumise ; attente de la décision de l'approbateur (30 s au plus)…"
for _ in $(seq 1 15); do
  etat="$(kubectl get csr "$objet" -o jsonpath='{range .status.conditions[*]}{.type}{" "}{.reason}{" "}{.message}{"\n"}{end}')"
  [[ -n "$etat" ]] && break
  sleep 2
done
echo "${etat:-aucune décision (approbateur arrêté ?)}"
