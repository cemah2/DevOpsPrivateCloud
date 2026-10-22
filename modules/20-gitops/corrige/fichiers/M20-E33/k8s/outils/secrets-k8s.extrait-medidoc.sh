#!/usr/bin/env bash
# shellcheck disable=SC2154  # CONTENU (Vault déchiffré en mémoire) est fourni par secrets-k8s.sh
# =============================================================================
# plateforme/k8s — outils/secrets-k8s.sh : AJOUT de M20-E33 (DEV-2133), composants medidoc-dev et
# medidoc-recette, sur le modèle de secrets_mediagenda (M20-E12). Remplace outils/secret-medidoc-s3.sh
# (M16-E46), qui lisait un fichier de ~/.config/workbook : la source devient le Vault.
# Crée, dans l'espace du même nom que le composant :
#   harbor-pull   kubernetes.io/dockerconfigjson (robot$k8s-pull)
#   medidoc-s3    AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY du compte RGW de l'environnement
# Aucun de ces Secrets n'est dans medidoc/deploiement : Argo CD ne les voit pas et ne les supprime pas.
# Ne jamais lancer avec « bash -x ».
# =============================================================================

secrets_medidoc() {
  local espace="$1" utilisateur jeton auth cle secret
  case "$espace" in
    medidoc-dev | medidoc-recette) ;;
    *) echo "secrets_medidoc : composant inconnu « $espace »" >&2; return 2 ;;
  esac
  utilisateur="$(yq -r '.harbor_pull_utilisateur // ""' <<<"$CONTENU")"
  jeton="$(yq -r '.harbor_pull_jeton // ""' <<<"$CONTENU")"
  cle="$(yq -r '.medidoc_s3_cle_acces // ""' <<<"$CONTENU")"
  secret="$(yq -r '.medidoc_s3_cle_secrete // ""' <<<"$CONTENU")"
  if [[ -z "$utilisateur" || -z "$jeton" || -z "$cle" || -z "$secret" ]]; then
    echo "secrets_medidoc : clé absente de secrets/$espace.yml (harbor_pull_*, medidoc_s3_*)" >&2
    return 1
  fi
  auth="$(printf '%s:%s' "$utilisateur" "$jeton" | base64 -w0)"
  kubectl create secret generic harbor-pull --namespace "$espace" \
    --type=kubernetes.io/dockerconfigjson \
    --from-file=.dockerconfigjson=<(jq -cn --arg a "$auth" \
      '{auths: {"registry.par1.medisphere.internal": {auth: $a}}}') \
    --dry-run=client -o yaml \
    | kubectl label --local -f - -o yaml \
        medisphere.internal/composant="$espace" medisphere.internal/source=ansible-vault \
    | kubectl apply --server-side --field-manager=secrets-k8s -f - >/dev/null
  kubectl create secret generic medidoc-s3 --namespace "$espace" \
    --from-file=AWS_ACCESS_KEY_ID=<(printf '%s' "$cle") \
    --from-file=AWS_SECRET_ACCESS_KEY=<(printf '%s' "$secret") \
    --dry-run=client -o yaml \
    | kubectl label --local -f - -o yaml \
        medisphere.internal/composant="$espace" medisphere.internal/source=ansible-vault \
    | kubectl apply --server-side --field-manager=secrets-k8s -f - >/dev/null
  echo "[OK] $espace/harbor-pull et $espace/medidoc-s3 à jour"
}
