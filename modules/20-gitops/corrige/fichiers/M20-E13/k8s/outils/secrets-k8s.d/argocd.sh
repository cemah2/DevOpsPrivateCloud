#!/usr/bin/env bash
# shellcheck disable=SC2154  # CONTENU, MODE, info, erreur, k, empreinte : fournis par secrets-k8s.sh
# =============================================================================
# plateforme/k8s — outils/secrets-k8s.d/argocd.sh : composant « argocd » de secrets-k8s.sh
# (M20-E06, PLAT-2106 ; dépôt Helm OCI de Harbor en M20-E13).
# Sourcé par secrets-k8s.sh (voir secrets-k8s.sh.extrait-E06) quand le composant demandé est
# « argocd » : les Secrets d'Argo CD portent des ÉTIQUETTES que la table secrets-k8s.conf ne sait
# pas poser (argocd.argoproj.io/secret-type=…), d'où une fonction.
#
# Source : secrets/argocd.yml (Ansible Vault « critique »), clé argocd_depots :
#   argocd_depots:
#     plateforme: {utilisateur: "<nom d'utilisateur du jeton>", jeton: "gldt-…"}
#     mediagenda: {…}
#     medidoc:    {…}
#     formation:  {…}
#   argocd_harbor_charts: {utilisateur: "robot$charts+lecture", jeton: "…"}     (M20-E13)
# Un Secret « repo-creds-<groupe> » par groupe GitLab : modèle d'identifiants (repo-creds) pour toute
# URL qui commence par https://git01.par1.medisphere.internal/<groupe>/ (le plus long préfixe gagne).
# Les modules suivants ajoutent leurs fonctions ici (M20-E13 dépôt OCI, M20-E26 cluster, M20-E27
# webhook…) et les appellent depuis secrets_argocd_appliquer / secrets_argocd_verifier.
# Ne jamais lancer avec « bash -x » : la trace afficherait les jetons.
# =============================================================================

ARGOCD_GITLAB_URL="${ARGOCD_GITLAB_URL:-https://git01.par1.medisphere.internal}"
ARGOCD_GROUPES=(plateforme mediagenda medidoc formation)

# secret_repo_creds_gitlab GROUPE — crée ou met à jour argocd/repo-creds-GROUPE (server-side apply).
secret_repo_creds_gitlab() {
  local groupe="$1" utilisateur jeton
  utilisateur="$(yq -r ".argocd_depots.${groupe}.utilisateur // \"\"" <<<"$CONTENU")"
  jeton="$(yq -r ".argocd_depots.${groupe}.jeton // \"\"" <<<"$CONTENU")"
  if [[ -z "$utilisateur" || -z "$jeton" || "$jeton" == null ]]; then
    erreur "argocd_depots.${groupe} incomplet dans secrets/argocd.yml (utilisateur, jeton)"
    return 1
  fi
  # Le jeton passe par une substitution de processus (--from-file) : ni « ps », ni historique, ni
  # annotation last-applied-configuration (server-side apply).
  k create secret generic "repo-creds-${groupe}" --namespace argocd \
    --from-literal=type=git \
    --from-literal=url="${ARGOCD_GITLAB_URL}/${groupe}/" \
    --from-literal=username="$utilisateur" \
    --from-file=password=<(printf '%s' "$jeton") \
    --dry-run=client -o yaml \
    | k label --local -f - -o yaml \
        argocd.argoproj.io/secret-type=repo-creds \
        medisphere.internal/composant=argocd medisphere.internal/source=ansible-vault \
    | k apply --server-side --field-manager=secrets-k8s -f - >/dev/null
  info "[OK] argocd/repo-creds-${groupe} à jour (${ARGOCD_GITLAB_URL}/${groupe}/, ${utilisateur})"
}

# verifier_repo_creds_gitlab GROUPE — lecture seule : étiquette, URL, et jeton identique au Vault.
verifier_repo_creds_gitlab() {
  local groupe="$1" json e_vault e_secret
  json="$(k get secret "repo-creds-${groupe}" --namespace argocd -o json 2>/dev/null)" || json=""
  if [[ -z "$json" ]]; then
    info "[KO] argocd/repo-creds-${groupe} absent"
    return 1
  fi
  if [[ "$(yq -r '.metadata.labels["argocd.argoproj.io/secret-type"] // ""' <<<"$json")" != repo-creds ]]; then
    info "[KO] argocd/repo-creds-${groupe} : étiquette argocd.argoproj.io/secret-type=repo-creds absente"
    return 1
  fi
  e_vault="$(yq -r ".argocd_depots.${groupe}.jeton // \"\"" <<<"$CONTENU" | tr -d '\n' | empreinte)"
  e_secret="$(yq -r '.data.password // ""' <<<"$json" | base64 -d 2>/dev/null | empreinte)"
  if [[ "$e_vault" != "$e_secret" ]]; then
    info "[KO] argocd/repo-creds-${groupe} : jeton différent de celui du Vault"
    return 1
  fi
  info "[OK] argocd/repo-creds-${groupe} identique au Vault"
}

# --- M20-E13 : dépôt Helm OCI de Harbor (projet « charts ») -------------------------------------
# Secret de DÉPÔT (étiquette argocd.argoproj.io/secret-type=repository) : type helm + enableOCI font
# de « registry.par1.medisphere.internal/charts » (sans oci://) un dépôt de charts OCI. Robot en
# LECTURE seule (M17-E13) : Argo CD n'écrit jamais dans Harbor.
ARGOCD_HARBOR_CHARTS_URL="registry.par1.medisphere.internal/charts"

secret_depot_harbor_charts() {
  local utilisateur jeton
  utilisateur="$(yq -r '.argocd_harbor_charts.utilisateur // ""' <<<"$CONTENU")"
  jeton="$(yq -r '.argocd_harbor_charts.jeton // ""' <<<"$CONTENU")"
  if [[ -z "$utilisateur" || -z "$jeton" || "$jeton" == null ]]; then
    erreur "argocd_harbor_charts incomplet dans secrets/argocd.yml (utilisateur, jeton)"
    return 1
  fi
  k create secret generic depot-harbor-charts --namespace argocd \
    --from-literal=name=harbor-charts \
    --from-literal=type=helm \
    --from-literal=url="$ARGOCD_HARBOR_CHARTS_URL" \
    --from-literal=enableOCI=true \
    --from-literal=username="$utilisateur" \
    --from-file=password=<(printf '%s' "$jeton") \
    --dry-run=client -o yaml \
    | k label --local -f - -o yaml \
        argocd.argoproj.io/secret-type=repository \
        medisphere.internal/composant=argocd medisphere.internal/source=ansible-vault \
    | k apply --server-side --field-manager=secrets-k8s -f - >/dev/null
  info "[OK] argocd/depot-harbor-charts à jour ($ARGOCD_HARBOR_CHARTS_URL, $utilisateur)"
}

verifier_depot_harbor_charts() {
  local json e_vault e_secret
  json="$(k get secret depot-harbor-charts --namespace argocd -o json 2>/dev/null)" || json=""
  if [[ -z "$json" ]]; then
    info "[KO] argocd/depot-harbor-charts absent"
    return 1
  fi
  if [[ "$(yq -r '.metadata.labels["argocd.argoproj.io/secret-type"] // ""' <<<"$json")" != repository ]]; then
    info "[KO] argocd/depot-harbor-charts : étiquette argocd.argoproj.io/secret-type=repository absente"
    return 1
  fi
  e_vault="$(yq -r '.argocd_harbor_charts.jeton // ""' <<<"$CONTENU" | tr -d '\n' | empreinte)"
  e_secret="$(yq -r '.data.password // ""' <<<"$json" | base64 -d 2>/dev/null | empreinte)"
  if [[ "$e_vault" != "$e_secret" ]]; then
    info "[KO] argocd/depot-harbor-charts : jeton différent de celui du Vault"
    return 1
  fi
  info "[OK] argocd/depot-harbor-charts identique au Vault"
}

secrets_argocd_appliquer() {
  local g
  for g in "${ARGOCD_GROUPES[@]}"; do
    secret_repo_creds_gitlab "$g" || return 1
  done
  secret_depot_harbor_charts || return 1
}

secrets_argocd_verifier() {
  local g ecarts=0
  for g in "${ARGOCD_GROUPES[@]}"; do
    verifier_repo_creds_gitlab "$g" || ecarts=$((ecarts + 1))
  done
  verifier_depot_harbor_charts || ecarts=$((ecarts + 1))
  ((ecarts == 0))
}
