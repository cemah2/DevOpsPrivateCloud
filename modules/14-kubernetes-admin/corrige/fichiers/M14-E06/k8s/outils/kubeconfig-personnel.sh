#!/usr/bin/env bash
# outils/kubeconfig-personnel.sh — identité personnelle sur k8s-par1 (M14-E06, SEC-1506).
#
# Émet un certificat client de 7 jours (CN=<MOI>, O=medisphere:plateforme-admins) signé par la CA
# du cluster, et le range dans ~/.kube/config (contexte « k8s-par1 »). À relancer avant
# l'expiration (le script affiche la date) ; aucun mot de passe, aucun jeton durable.
#
#   outils/kubeconfig-personnel.sh <MOI>               # émet ou renouvelle
#   outils/kubeconfig-personnel.sh <MOI> --verifier    # affiche l'identité et l'expiration seulement
#
# Méthode : « kubeadm kubeconfig user » sur un nœud de contrôle (SSH, sudo). La clé privée est
# générée là-bas et ne transite que par la sortie standard de SSH : elle n'est jamais écrite sur le
# nœud, et sur adm01 seulement dans ~/.kube/config (600) et, le temps du script, dans le dossier de
# session en mémoire ($XDG_RUNTIME_DIR). La voie par l'API (CertificateSigningRequest) est vue en
# M14-E12 ; elle exige une identité qui fonctionne déjà, celle-ci non (seulement SSH et sudo).
set -euo pipefail

usage() { echo "Usage : $0 <MOI> [--verifier]" >&2; exit 2; }
[[ $# -ge 1 && $# -le 2 ]] || usage
moi="$1"
[[ "$moi" =~ ^[a-z][a-z0-9._-]{1,62}$ ]] || { echo "Nom invalide : $moi" >&2; exit 2; }
mode="${2:-emettre}"
[[ "$mode" == emettre || "$mode" == --verifier ]] || usage

NOEUD="${K8S_NOEUD_CONTROLE:-k8s-cp01}"
GROUPE="medisphere:plateforme-admins"
DUREE="168h"   # 7 jours (PLAN §4.10)
CONTEXTE="k8s-par1"
CONFIG_KUBEADM="/etc/kubernetes/kubeadm/kubeadm-config.yaml"
KUBECONFIG_PERSO="${HOME}/.kube/config"

# Date de fin du certificat de l'utilisateur dans ~/.kube/config (vide si absent).
expiration() {
  kubectl --kubeconfig "$KUBECONFIG_PERSO" config view --raw \
    -o jsonpath="{.users[?(@.name==\"$moi\")].user.client-certificate-data}" 2>/dev/null \
    | base64 -d 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | sed 's/^notAfter=//'
}

if [[ "$mode" == --verifier ]]; then
  fin="$(expiration)"
  [[ -n "$fin" ]] || { echo "Aucun certificat pour $moi dans $KUBECONFIG_PERSO." >&2; exit 1; }
  echo "Certificat de $moi valable jusqu'au : $fin"
  kubectl --context "$CONTEXTE" auth whoami
  exit 0
fi

# Dossier de travail en mémoire, propre à l'utilisateur ; repli sur un dossier 700 de /tmp.
base="${XDG_RUNTIME_DIR:-}"
[[ -n "$base" && -d "$base" && -O "$base" ]] || base="$(mktemp -d)"
travail="$(mktemp -d "$base/kubeconfig-personnel.XXXXXX")"
chmod 700 "$travail"
trap 'rm -rf -- "$travail"' EXIT
umask 077

echo "Émission d'un certificat de $DUREE pour $moi (groupe $GROUPE) sur $NOEUD…"
# Arguments fixes et validés ci-dessus : pas d'injection dans la commande distante.
ssh -o BatchMode=yes "$NOEUD" -- sudo -n kubeadm kubeconfig user \
  --config "$CONFIG_KUBEADM" --client-name "$moi" --org "$GROUPE" --validity-period "$DUREE" \
  > "$travail/emis.kubeconfig"

# On reprend les trois éléments (CA, certificat, clé) et l'adresse du point d'accès, puis on les
# range dans ~/.kube/config sous des noms stables : un renouvellement remplace, il n'ajoute pas.
for champ in certificate-authority-data:ca.crt server:serveur; do
  cle="${champ%%:*}"; fichier="${champ##*:}"
  kubectl --kubeconfig "$travail/emis.kubeconfig" config view --raw \
    -o jsonpath="{.clusters[0].cluster.$cle}" > "$travail/$fichier"
done
base64 -d -i "$travail/ca.crt" > "$travail/ca.pem"
kubectl --kubeconfig "$travail/emis.kubeconfig" config view --raw \
  -o jsonpath='{.users[0].user.client-certificate-data}' | base64 -d > "$travail/client.crt"
kubectl --kubeconfig "$travail/emis.kubeconfig" config view --raw \
  -o jsonpath='{.users[0].user.client-key-data}' | base64 -d > "$travail/client.key"

# Garde-fous : ce qu'on range est bien ce qu'on a demandé.
sujet="$(openssl x509 -in "$travail/client.crt" -noout -subject -nameopt RFC2253)"
[[ "$sujet" == "subject=CN=$moi,O=$GROUPE" ]] || { echo "Sujet inattendu : $sujet" >&2; exit 1; }
openssl verify -CAfile "$travail/ca.pem" "$travail/client.crt" >/dev/null
serveur="$(<"$travail/serveur")"
[[ "$serveur" == "https://k8s-api.par1.medisphere.internal:8443" ]] \
  || { echo "Point d'accès inattendu dans le kubeconfig émis : $serveur" >&2; exit 1; }

mkdir -p "$(dirname "$KUBECONFIG_PERSO")"
touch "$KUBECONFIG_PERSO"
chmod 600 "$KUBECONFIG_PERSO"
export KUBECONFIG="$KUBECONFIG_PERSO"
kubectl config set-cluster "$CONTEXTE" --server="$serveur" \
  --certificate-authority="$travail/ca.pem" --embed-certs=true >/dev/null
kubectl config set-credentials "$moi" --client-certificate="$travail/client.crt" \
  --client-key="$travail/client.key" --embed-certs=true >/dev/null
kubectl config set-context "$CONTEXTE" --cluster="$CONTEXTE" --user="$moi" >/dev/null
kubectl config use-context "$CONTEXTE" >/dev/null

echo "Contexte « $CONTEXTE » prêt dans $KUBECONFIG_PERSO ; certificat valable jusqu'au : $(expiration)"
kubectl --context "$CONTEXTE" auth whoami
