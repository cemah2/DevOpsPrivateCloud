#!/usr/bin/env bash
# shellcheck disable=SC2154  # CONTENU (Vault déchiffré en mémoire) est fourni par secrets-k8s.sh
# =============================================================================
# plateforme/k8s — outils/secrets-k8s.sh, composant « argocd » : AJOUT de M20-E27 (PLAT-2127).
# Secret « argocd-webhook-gitlab » : la valeur du secret partagé des webhooks GitLab. argocd-secret ne
# contient qu'une RÉFÉRENCE ($argocd-webhook-gitlab:secret, values-ha.yaml) ; Argo CD ne résout une
# référence que vers un Secret portant l'étiquette app.kubernetes.io/part-of=argocd.
# =============================================================================

secret_webhook_gitlab() {
  local secret
  secret="$(yq -r '.argocd_webhook_gitlab_secret // ""' <<<"$CONTENU")"
  if [[ ${#secret} -lt 32 ]]; then
    echo "secret_webhook_gitlab : argocd_webhook_gitlab_secret absent ou trop court (32 caractères au moins)" >&2
    return 1
  fi
  kubectl create secret generic argocd-webhook-gitlab --namespace argocd \
    --from-file=secret=<(printf '%s' "$secret") \
    --dry-run=client -o yaml \
    | kubectl label --local -f - -o yaml \
        app.kubernetes.io/part-of=argocd \
        medisphere.internal/composant=argocd medisphere.internal/source=ansible-vault \
    | kubectl apply --server-side --field-manager=secrets-k8s -f - >/dev/null
  echo "[OK] argocd/argocd-webhook-gitlab à jour"
}
