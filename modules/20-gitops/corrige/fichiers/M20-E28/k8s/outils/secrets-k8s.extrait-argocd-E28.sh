#!/usr/bin/env bash
# shellcheck disable=SC2154  # CONTENU (Vault déchiffré en mémoire) est fourni par secrets-k8s.sh
# =============================================================================
# plateforme/k8s — outils/secrets-k8s.sh, composant « argocd » : AJOUT de M20-E28 (PLAT-2128).
# Secret « argocd-sauvegardes-s3 » : identité S3 du CronJob argocd-export (conteneur « envoi »).
# =============================================================================

secret_argocd_sauvegardes_s3() {
  local cle secret
  cle="$(yq -r '.argocd_sauvegardes_s3_cle_acces // ""' <<<"$CONTENU")"
  secret="$(yq -r '.argocd_sauvegardes_s3_cle_secrete // ""' <<<"$CONTENU")"
  if [[ -z "$cle" || -z "$secret" ]]; then
    echo "secret_argocd_sauvegardes_s3 : clés argocd_sauvegardes_s3_* absentes de secrets/argocd.yml" >&2
    return 1
  fi
  kubectl create secret generic argocd-sauvegardes-s3 --namespace argocd \
    --from-file=AWS_ACCESS_KEY_ID=<(printf '%s' "$cle") \
    --from-file=AWS_SECRET_ACCESS_KEY=<(printf '%s' "$secret") \
    --dry-run=client -o yaml \
    | kubectl label --local -f - -o yaml \
        app.kubernetes.io/part-of=argocd-sauvegarde \
        medisphere.internal/composant=argocd medisphere.internal/source=ansible-vault \
    | kubectl apply --server-side --field-manager=secrets-k8s -f - >/dev/null
  echo "[OK] argocd/argocd-sauvegardes-s3 à jour"
}
