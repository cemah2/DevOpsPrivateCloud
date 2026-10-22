#!/usr/bin/env bash
# outils/kubeconfig-oidc.sh — identité OIDC sur k8s-par1 (M24-E16, PLAT-2516).
#
# Ajoute à ~/.kube/config l'utilisateur « oidc » (plugin kubelogin : kubectl oidc-login get-token) et le
# contexte « k8s-par1-oidc » (cluster du contexte k8s-par1 existant, M14-E06). Aucun secret : le client
# « kubernetes » est PUBLIC (PKCE). Le jeton (ID token de 5 min) et le jeton de rafraîchissement sont
# gardés par kubelogin dans ~/.kube/cache/oidc-login (700) ; « kubectl oidc-login clean » les efface.
#
#   outils/kubeconfig-oidc.sh             ajoute ou met à jour (idempotent)
#   outils/kubeconfig-oidc.sh --defaut    ... et fait de k8s-par1-oidc le contexte courant (M24-E17)
#
# Navigateur : adm01 n'en a pas. kubelogin écoute sur 127.0.0.1:8000 (puis 18000) d'adm01 et affiche
# une URL ; ouvre-la sur ton poste, avec un tunnel vers adm01 pour le retour :
#   ssh -L 8000:127.0.0.1:8000 -L 18000:127.0.0.1:18000 admin@adm01.par1.medisphere.internal
set -euo pipefail

EMETTEUR="https://sso.par1.medisphere.internal/realms/medisphere"
CLIENT="kubernetes"
CLUSTER_SOURCE="${KUBE_CONTEXTE_SOURCE:-k8s-par1}"
CONTEXTE="k8s-par1-oidc"
UTILISATEUR="oidc"
RACINE="${CA:-/usr/local/share/ca-certificates/medisphere-root-ca.crt}"

die() { echo "kubeconfig-oidc : $*" >&2; exit 1; }
command -v kubectl >/dev/null || die "kubectl absent"
kubectl oidc-login --help >/dev/null 2>&1 || die "kubelogin absent : kubectl krew install oidc-login"
[[ -r "$RACINE" ]] || die "racine MédiSphère introuvable : $RACINE"

cluster="$(kubectl config view -o jsonpath="{.contexts[?(@.name==\"$CLUSTER_SOURCE\")].context.cluster}")"
[[ -n "$cluster" ]] || die "contexte $CLUSTER_SOURCE absent de ~/.kube/config (M14-E06)"

kubectl config set-credentials "$UTILISATEUR" \
  --exec-api-version=client.authentication.k8s.io/v1 \
  --exec-interactive-mode=Never \
  --exec-command=kubectl \
  --exec-arg=oidc-login \
  --exec-arg=get-token \
  --exec-arg="--oidc-issuer-url=$EMETTEUR" \
  --exec-arg="--oidc-client-id=$CLIENT" \
  --exec-arg=--oidc-pkce-method=S256 \
  --exec-arg="--certificate-authority=$RACINE" \
  --exec-arg=--skip-open-browser \
  --exec-arg=--grant-type=authcode >/dev/null
kubectl config set-context "$CONTEXTE" --cluster="$cluster" --user="$UTILISATEUR" >/dev/null
echo "kubeconfig-oidc : contexte $CONTEXTE (cluster $cluster, utilisateur $UTILISATEUR, client $CLIENT) prêt."

if [[ "${1:-}" == --defaut ]]; then
  kubectl config use-context "$CONTEXTE" >/dev/null
  echo "kubeconfig-oidc : $CONTEXTE est le contexte courant (bris de glace : admin.conf du Vault)."
fi
echo "Essai : kubectl --context $CONTEXTE auth whoami   (tunnel SSH vers localhost:8000 ouvert ?)"
