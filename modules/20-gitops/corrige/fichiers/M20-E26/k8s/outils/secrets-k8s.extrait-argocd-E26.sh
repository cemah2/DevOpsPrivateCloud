#!/usr/bin/env bash
# shellcheck disable=SC2154  # CONTENU (Vault déchiffré en mémoire) est fourni par secrets-k8s.sh
# =============================================================================
# plateforme/k8s — outils/secrets-k8s.sh, composant « argocd » : AJOUT de M20-E26 (PLAT-2126),
# complété en M20-E27 (champ shard). Fonction à appeler depuis le traitement du composant argocd, à
# côté de celles d'E06 (jetons de déploiement) et d'E13 (dépôt OCI).
# Secret de CLUSTER « cluster-lyo-k3s01 » : Argo CD reconnaît un cluster à l'étiquette
# argocd.argoproj.io/secret-type=cluster ; le générateur « clusters » des ApplicationSets le choisit
# par ses autres étiquettes (site=lyo1).
# Champs (documentation « Declarative Setup », section Clusters) :
#   name, server         nom affiché et URL de l'API (le nom doit être dans tls-san de k3s)
#   namespaces           espaces gérés : Argo CD ne surveille QUE ceux-là (le compte n'a qu'un Role)
#   clusterResources     "false" : aucun objet de cluster (Namespace, CRD, ClusterRole…)
#   shard                partition du contrôleur (M20-E27) : 1, pour ne pas tout mettre sur la 0
#   config               JSON : jeton (bearerToken) et autorité (caData = PEM encodé en base64)
# Ne jamais lancer avec « bash -x » : la trace afficherait le jeton.
# =============================================================================

secret_cluster_lyo_k3s01() {
  local jeton ca config
  jeton="$(yq -r '.lyo_k3s01_jeton // ""' <<<"$CONTENU")"
  ca="$(yq -r '.lyo_k3s01_ca // ""' <<<"$CONTENU")"
  if [[ -z "$jeton" || "$ca" != *"BEGIN CERTIFICATE"* ]]; then
    echo "secret_cluster_lyo_k3s01 : lyo_k3s01_jeton ou lyo_k3s01_ca absent de secrets/argocd.yml" >&2
    return 1
  fi
  # TLS VÉRIFIÉ (insecure: false) contre l'autorité de k3s : jamais « insecure: true ».
  config="$(jq -cn --arg j "$jeton" --arg ca "$(printf '%s' "$ca" | base64 -w0)" \
    '{bearerToken: $j, tlsClientConfig: {insecure: false, caData: $ca}}')"
  kubectl create secret generic cluster-lyo-k3s01 --namespace argocd \
    --from-literal=name=lyo-k3s01 \
    --from-literal=server=https://lyo-k3s01.par1.medisphere.internal:6443 \
    --from-literal=namespaces=agence \
    --from-literal=clusterResources=false \
    --from-literal=shard=1 \
    --from-file=config=<(printf '%s' "$config") \
    --dry-run=client -o yaml \
    | kubectl label --local -f - -o yaml \
        argocd.argoproj.io/secret-type=cluster \
        site=lyo1 medisphere.internal/environnement=agence \
        medisphere.internal/composant=argocd medisphere.internal/source=ansible-vault \
    | kubectl apply --server-side --field-manager=secrets-k8s -f - >/dev/null
  echo "[OK] argocd/cluster-lyo-k3s01 à jour (https://lyo-k3s01.par1.medisphere.internal:6443, espace agence)"
}
