#!/usr/bin/env bash
# plateforme/k8s — outils/kubeconfig-csr.sh (M14-E12)
# Signe la demande de certificat (CSR PKCS#10) d'un HUMAIN par l'API CertificateSigningRequest
# du cluster, puis produit un kubeconfig SANS clé privée (la clé ne quitte jamais le poste
# du demandeur ; le kubeconfig la désigne par un chemin relatif à lui-même).
#
# Usage : outils/kubeconfig-csr.sh FICHIER.csr UTILISATEUR GROUPE [DURÉE_S] [SORTIE]
#   ex.   outils/kubeconfig-csr.sh ~/m14/e12/julien/julien.petit.csr julien.petit medisphere:mediagenda-devs
# DURÉE_S : durée demandée en secondes (défaut 604800 = 7 jours ; minimum accepté par l'API : 600).
# SORTIE  : kubeconfig produit (défaut : UTILISATEUR.kubeconfig à côté du CSR).
# À lancer depuis adm01 avec un kubeconfig du groupe medisphere:plateforme-admins (create + approve).
set -euo pipefail

usage() { sed -n '3,12p' "$0" >&2; exit 2; }
(($# >= 3)) || usage
csr="$1"; utilisateur="$2"; groupe="$3"; duree="${4:-604800}"
sortie="${5:-$(dirname "$csr")/$utilisateur.kubeconfig}"
api="https://k8s-api.par1.medisphere.internal:8443"
grappe="k8s-par1"

[[ -r "$csr" ]] || { echo "CSR illisible : $csr" >&2; exit 1; }
if ! [[ "$duree" =~ ^[0-9]+$ ]] || ((duree < 600 || duree > 2592000)); then
  echo "durée hors bornes (600 s à 30 jours) : $duree" >&2; exit 1
fi

# 1. Le sujet doit être EXACTEMENT CN=<utilisateur> et O=<groupe>, rien d'autre (chaque O est un groupe :
#    un O de plus, ce serait un groupe de plus — par exemple system:masters).
champs="$(openssl req -in "$csr" -noout -subject -nameopt multiline | tail -n +2 | sed 's/^ *//; s/ *= */=/')"
attendu="$(printf 'commonName=%s\norganizationName=%s' "$utilisateur" "$groupe")"
if [[ "$(sort <<<"$champs")" != "$(sort <<<"$attendu")" ]]; then
  printf 'sujet refusé :\n  %s\n' "${champs//$'\n'/$'\n  '}" >&2
  echo "attendu : CN=$utilisateur, O=$groupe (et rien d'autre)" >&2
  exit 1
fi
openssl req -in "$csr" -noout -verify >/dev/null 2>&1 || { echo "signature du CSR invalide" >&2; exit 1; }
# Clé : EC P-256/P-384 ou RSA >= 3072 bits.
texte="$(openssl req -in "$csr" -noout -text)"
if grep -q 'rsaEncryption' <<<"$texte"; then
  bits="$(sed -n 's/.*Public-Key: (\([0-9]*\) bit).*/\1/p' <<<"$texte" | head -n1)"
  ((${bits:-0} >= 3072)) || { echo "clé RSA trop courte (${bits:-?} bits)" >&2; exit 1; }
fi

# 2. Objet CertificateSigningRequest (nom unique : on ne réutilise jamais un CSR).
nom="$utilisateur-$(date +%Y%m%d-%H%M%S)"
kubectl apply -f - <<YAML
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: $nom
  labels:
    medisphere.internal/utilisateur: "$utilisateur"
spec:
  request: $(base64 -w0 "$csr")
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: $duree
  usages: ["client auth"]
YAML

# 3. Approbation (tracée dans l'API : condition Approved, qui et quand) puis attente du certificat.
kubectl certificate approve "$nom"
cert=""
for _ in $(seq 1 30); do
  cert="$(kubectl get csr "$nom" -o jsonpath='{.status.certificate}')"
  [[ -n "$cert" ]] && break
  sleep 1
done
[[ -n "$cert" ]] || { echo "le certificat n'a pas été émis (kubectl describe csr $nom)" >&2; exit 1; }

# 4. Kubeconfig : CA du cluster (prise dans TON kubeconfig), certificat émis, clé désignée par chemin.
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' \
  | base64 -d > "$tmp/ca.crt"
base64 -d <<<"$cert" > "$tmp/client.crt"
rm -f "$sortie"
kubectl config --kubeconfig="$sortie" set-cluster "$grappe" --server="$api" \
  --certificate-authority="$tmp/ca.crt" --embed-certs=true >/dev/null
kubectl config --kubeconfig="$sortie" set-credentials "$utilisateur" \
  --client-certificate="$tmp/client.crt" --embed-certs=true >/dev/null
# Chemin RELATIF : kubectl le résout par rapport au fichier kubeconfig lui-même. On l'écrit avec yq
# (« kubectl config set users.<nom>… » ne sait pas traiter un nom qui contient un point).
U="$utilisateur" K="$utilisateur.key" yq -i \
  '(.users[] | select(.name == strenv(U)) | .user."client-key") = strenv(K)' "$sortie"
kubectl config --kubeconfig="$sortie" set-context "$utilisateur@$grappe" --cluster="$grappe" \
  --user="$utilisateur" >/dev/null
kubectl config --kubeconfig="$sortie" use-context "$utilisateur@$grappe" >/dev/null
chmod 600 "$sortie"

fin="$(openssl x509 -in "$tmp/client.crt" -noout -enddate | sed 's/^notAfter=//')"
echo "Kubeconfig écrit : $sortie (certificat valable jusqu'au $fin)."
echo "À remettre au demandeur : il place sa clé « $utilisateur.key » (600) à côté du fichier."
