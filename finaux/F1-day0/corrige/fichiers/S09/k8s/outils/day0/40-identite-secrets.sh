#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# plateforme/k8s — outils/day0/40-identite-secrets.sh (F1-S09, SEC-3109)
# Raccroche le coffre et l'identité au cluster neuf. Après 30-couche-base.sh, dans ~/src/k8s, avec
# DAY0_KUBECONFIG = admin.conf du nouveau cluster et une session OpenBao (bao login -method=oidc).
#
#   1. autorité du nouveau cluster dans plateforme/secrets : préparée ici (outils/ca-k8s-par1.sh
#      ecrire), committée par MR, appliquée par le PIPELINE ; le script attend qu'OpenBao l'utilise ;
#   2. amorçage d'Argo CD : AppProject « plateforme », Applications « external-secrets » et
#      « secrets-plateforme » appliquées UNE fois (l'application racine les reprendra en S10, mêmes noms) ;
#   3. ESO prêt, ClusterSecretStore openbao prêt ; SecretStores et comptes « eso » des espaces
#      applicatifs (fichiers 80-openbao.yaml de espaces/, liaison openbao-auth-delegator) ;
#   4. adoption des Secrets d'amorçage vérifiée (outils/amorcer-secrets.sh verifier), marque retirée ;
#   5. RBAC des personnes (rbac/, liaisons oidc-*) et ton kubeconfig OIDC (nouvelle autorité).
# Restent à la main, notés comme gestes : le nouvel admin.conf dans le Vault « critique » et la mise à
# jour de l'inventaire des secrets.

# shellcheck source=../../../../S07/k8s/outils/day0/commun.sh
source "$(dirname "${BASH_SOURCE[0]}")/commun.sh"

PHASE=identite-secrets
K8S="$DAY0_SRC/k8s"
SECRETS="$DAY0_SRC/secrets"
GITOPS="$DAY0_SRC/gitops"
CTX_PERSO="${DAY0_CONTEXTE_PERSO:-k8s-par1}"
KUBECONFIG_PERSO="${DAY0_KUBECONFIG_PERSO:-$HOME/.kube/config}"

outils_requis kubectl bao jq yq openssl git
cd "$K8S"

empreinte() { openssl x509 -noout -fingerprint -sha256 | sed 's/^.*=//'; }
ca_cluster() { k -n default get configmap kube-root-ca.crt -o jsonpath='{.data.ca\.crt}'; }

preparer_mr_secrets() {
  (cd "$SECRETS" && git switch -c "day0/k8s-par1-ca-$(date +%Y%m%d)" && outils/ca-k8s-par1.sh ecrire &&
    git add racine/k8s-par1-ca.crt &&
    git commit -m "fix(k8s-par1): autorité du cluster reconstruit (SEC-3109, CHG-3107)" &&
    git push -u origin HEAD)
  echo "Ouvre la MR dans plateforme/secrets, fais-la approuver, fusionne : le pipeline applique."
}

openbao_a_jour() {
  [[ "$(bao read -field=kubernetes_ca_cert auth/k8s-par1/config | empreinte)" == "$(ca_cluster | empreinte)" ]]
}

amorcer_argocd() {
  # Les trois fichiers sont ceux de plateforme/gitops (M20-E07, M25-E12, M25-E13) : rien n'est réécrit.
  k apply --server-side -f "$GITOPS/projets/plateforme.yaml"
  k apply --server-side -f "$GITOPS/plateforme/external-secrets.yaml"
  k apply --server-side -f "$GITOPS/plateforme/secrets-plateforme.yaml"
}

app_saine() {
  [[ "$(k -n argocd get applications.argoproj.io "$1" -o jsonpath='{.status.sync.status}/{.status.health.status}')" == Synced/Healthy ]]
}
css_prete() {
  [[ "$(k get clustersecretstores.external-secrets.io openbao -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" == True ]]
}

magasins_applicatifs() {
  # Comptes « eso », SecretStores « openbao » et leurs droits, espace par espace (80-openbao.yaml), et la
  # liaison system:auth-delegator des comptes clients ; PAS le reste de espaces/ (bases CNPG : S11).
  local f
  while IFS= read -r -d '' f; do
    k apply --server-side --field-manager=plateforme-k8s -f "$f"
  done < <(find espaces -name '80-openbao.yaml' -print0)
  k apply --server-side --field-manager=plateforme-k8s -f rbac/openbao-auth-delegator.yaml
}

adoption() {
  attendre 900 "Secrets d'amorçage adoptés par leurs ExternalSecrets" outils/amorcer-secrets.sh verifier
  outils/amorcer-secrets.sh nettoyer
}

rbac_personnes() {
  k apply --server-side --field-manager=plateforme-k8s -R -f rbac/
}

kubeconfig_personnel() {
  local cluster tmp
  cluster="$(kubectl --kubeconfig "$KUBECONFIG_PERSO" config view -o json |
    jq -r --arg c "$CTX_PERSO" '.contexts[] | select(.name == $c) | .context.cluster')"
  [[ -n "$cluster" ]] || { echo "contexte $CTX_PERSO absent de $KUBECONFIG_PERSO" >&2; return 1; }
  tmp="$(mktemp)"
  ca_cluster >"$tmp"
  kubectl --kubeconfig "$KUBECONFIG_PERSO" config set-cluster "$cluster" --certificate-authority="$tmp" --embed-certs=true >/dev/null
  rm -f "$tmp"
  echo "Connexion OIDC : une fenêtre de navigateur peut s'ouvrir (kubelogin)."
  kubectl --kubeconfig "$KUBECONFIG_PERSO" --context "$CTX_PERSO" auth whoami
}

bao token lookup >/dev/null 2>&1 || { echo "Session OpenBao absente : bao login -method=oidc" >&2; exit 1; }
etape "$PHASE" "MR de plateforme/secrets (autorité du nouveau cluster)" preparer_mr_secrets
etape "$PHASE" "OpenBao fait confiance au nouveau cluster (pipeline appliqué)" attendre 3600 "auth/k8s-par1/config à jour" openbao_a_jour
geste "$PHASE" "Argo CD : AppProject plateforme + Applications external-secrets et secrets-plateforme appliqués à la main (reprises par la racine en S10)"
etape "$PHASE" "amorçage d'ESO par Argo CD" amorcer_argocd
etape "$PHASE" "Application external-secrets saine" attendre 900 "external-secrets Synced/Healthy" app_saine external-secrets
etape "$PHASE" "ClusterSecretStore openbao prêt" attendre 600 "magasin openbao prêt" css_prete
etape "$PHASE" "SecretStores des espaces applicatifs" magasins_applicatifs
etape "$PHASE" "Application secrets-plateforme saine" attendre 900 "secrets-plateforme Synced/Healthy" app_saine secrets-plateforme
etape "$PHASE" "adoption des Secrets d'amorçage" adoption
etape "$PHASE" "RBAC des personnes (oidc-*)" rbac_personnes
etape "$PHASE" "kubeconfig personnel (OIDC, nouvelle autorité)" kubeconfig_personnel
geste "$PHASE" "nouvel admin.conf rangé dans le Vault critique (bris de glace) ; ancien supprimé ; inventaire des secrets mis à jour"
jalon "$PHASE" "identité et secrets raccrochés" "lab/bin/check F1 09"
