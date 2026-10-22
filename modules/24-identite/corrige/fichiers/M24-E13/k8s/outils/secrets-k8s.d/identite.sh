#!/usr/bin/env bash
# shellcheck disable=SC2154  # CONTENU, info, erreur, k, empreinte : fournis par secrets-k8s.sh
# =============================================================================
# plateforme/k8s — outils/secrets-k8s.d/identite.sh : module du composant « identite » de
# secrets-k8s.sh (M24-E13, SEC-2513). Sourcé par secrets-k8s.sh APRÈS le traitement des lignes de la
# table (grafana-oidc, M24-E12 ; oauth2-proxy-oidc, M24-E18) : il ne crée que les Secrets qui exigent
# une ÉTIQUETTE que la table ne sait pas poser.
#
# Source : secrets/identite.yml de plateforme/ansible (Vault « critique », lu par secrets-k8s.sh,
# M24-E12), clé keycloak_secrets_clients.<client>, écrite par plateforme/identite/outils/
# ranger-secret-client.sh.
#
# argocd/argocd-oidc, clé clientSecret : référencé par oidc.config (« $argocd-oidc:clientSecret »).
# Argo CD ne résout une référence $<secret>:<clé> que vers un Secret de l'espace argocd portant
# l'étiquette app.kubernetes.io/part-of=argocd (même règle que argocd-webhook-gitlab, M20-E27).
# Ne jamais lancer avec « bash -x » : la trace afficherait le secret.
# =============================================================================

# _identite_secret_client CLÉ — valeur de keycloak_secrets_clients.CLÉ (sortie standard ; jamais à l'écran).
_identite_secret_client() {
  local v
  v="$(yq -r ".keycloak_secrets_clients.$1 // \"\"" <<<"$CONTENU")"
  [[ ${#v} -ge 32 && "$v" != null ]] || return 1
  printf '%s' "$v"
}

secret_argocd_oidc() {
  if ! _identite_secret_client argocd >/dev/null; then
    erreur "keycloak_secrets_clients.argocd absent ou trop court dans secrets/identite.yml (ranger-secret-client.sh argocd)"
    return 1
  fi
  k create secret generic argocd-oidc --namespace argocd \
    --from-file=clientSecret=<(_identite_secret_client argocd) \
    --dry-run=client -o yaml \
    | k label --local -f - -o yaml \
        app.kubernetes.io/part-of=argocd \
        medisphere.internal/composant=identite medisphere.internal/source=ansible-vault \
    | k apply --server-side --field-manager=secrets-k8s -f - >/dev/null
  info "[OK] argocd/argocd-oidc à jour (clientSecret, étiquette part-of=argocd)"
}

verifier_argocd_oidc() {
  local json
  json="$(k get secret argocd-oidc --namespace argocd -o json 2>/dev/null)" || json=""
  if [[ -z "$json" ]]; then
    info "[KO] argocd/argocd-oidc absent"
    return 1
  fi
  if [[ "$(yq -r '.metadata.labels["app.kubernetes.io/part-of"] // ""' <<<"$json")" != argocd ]]; then
    info "[KO] argocd/argocd-oidc : étiquette app.kubernetes.io/part-of=argocd absente (Argo CD ignorera la référence)"
    return 1
  fi
  if [[ "$(yq -r '.data.clientSecret // ""' <<<"$json" | base64 -d 2>/dev/null | empreinte)" \
    != "$(_identite_secret_client argocd | empreinte)" ]]; then
    info "[KO] argocd/argocd-oidc : clientSecret différent du Vault"
    return 1
  fi
  info "[OK] argocd/argocd-oidc identique au Vault"
}

secrets_identite_appliquer() {
  secret_argocd_oidc || return 1
}

secrets_identite_verifier() {
  local ecarts=0
  verifier_argocd_oidc || ecarts=$((ecarts + 1))
  ((ecarts == 0))
}
