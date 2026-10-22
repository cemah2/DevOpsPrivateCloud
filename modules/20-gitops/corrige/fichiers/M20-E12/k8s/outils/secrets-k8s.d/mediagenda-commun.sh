#!/usr/bin/env bash
# shellcheck disable=SC2154  # CONTENU, info, erreur, k, empreinte : fournis par secrets-k8s.sh
# =============================================================================
# plateforme/k8s — outils/secrets-k8s.d/mediagenda-commun.sh (M20-E12, PLAT-2112)
# Fonctions communes aux composants mediagenda-dev, mediagenda-recette, mediagenda-prod (modules
# mediagenda-<env>.sh, sourcés par secrets-k8s.sh comme argocd.sh en E06). Source :
# secrets/mediagenda-<env>.yml (Ansible Vault « critique ») :
#   harbor_pull_utilisateur: "robot$k8s-pull"
#   harbor_pull_jeton: "<jeton>"
# Crée, dans l'espace du même nom, le Secret harbor-pull (kubernetes.io/dockerconfigjson) que citent
# les pods de MédiAgenda. Les autres Secrets de MédiAgenda ne passent PAS par ici : mediagenda-db-app
# est créé par CloudNativePG, cnpg-s3 par l'outil du M16. Aucun n'est dans mediagenda/deploiement :
# Argo CD ne les voit pas (pas d'annotation de suivi) et ne les supprime donc jamais.
# Ne jamais lancer avec « bash -x » : la trace afficherait le jeton.
# =============================================================================

_REGISTRE_MEDISPHERE="registry.par1.medisphere.internal"

# _mediagenda_dockerconfig — JSON .dockerconfigjson construit depuis le Vault (sur la sortie standard).
_mediagenda_dockerconfig() {
  local utilisateur jeton
  utilisateur="$(yq -r '.harbor_pull_utilisateur // ""' <<<"$CONTENU")"
  jeton="$(yq -r '.harbor_pull_jeton // ""' <<<"$CONTENU")"
  [[ -n "$utilisateur" && -n "$jeton" && "$jeton" != null ]] || return 1
  jq -cn --arg r "$_REGISTRE_MEDISPHERE" --arg a "$(printf '%s:%s' "$utilisateur" "$jeton" | base64 -w0)" \
    '{auths: {($r): {auth: $a}}}'
}

# secrets_mediagenda_appliquer ESPACE — crée ou met à jour ESPACE/harbor-pull (server-side apply).
secrets_mediagenda_appliquer() {
  local espace="$1" config
  if ! config="$(_mediagenda_dockerconfig)"; then
    erreur "harbor_pull_utilisateur ou harbor_pull_jeton absent de secrets/$espace.yml"
    return 1
  fi
  # Le contenu passe par une substitution de processus (--from-file) : ni « ps », ni disque.
  k create secret generic harbor-pull --namespace "$espace" \
    --type=kubernetes.io/dockerconfigjson \
    --from-file=.dockerconfigjson=<(printf '%s' "$config") \
    --dry-run=client -o yaml \
    | k label --local -f - -o yaml \
        medisphere.internal/composant="$espace" medisphere.internal/source=ansible-vault \
    | k apply --server-side --field-manager=secrets-k8s -f - >/dev/null
  info "[OK] $espace/harbor-pull à jour"
}

# secrets_mediagenda_verifier ESPACE — lecture seule : Secret présent, du bon type, identique au Vault.
secrets_mediagenda_verifier() {
  local espace="$1" json config e_vault e_secret
  json="$(k get secret harbor-pull --namespace "$espace" -o json 2>/dev/null)" || json=""
  if [[ -z "$json" ]]; then
    info "[KO] $espace/harbor-pull absent"
    return 1
  fi
  if [[ "$(jq -r '.type' <<<"$json")" != kubernetes.io/dockerconfigjson ]]; then
    info "[KO] $espace/harbor-pull n'est pas de type kubernetes.io/dockerconfigjson"
    return 1
  fi
  # Même forme que le Secret appliqué (printf '%s', sans fin de ligne) : sinon les empreintes diffèrent.
  config="$(_mediagenda_dockerconfig)" || config=""
  e_vault="$(printf '%s' "$config" | empreinte)"
  e_secret="$(jq -r '.data[".dockerconfigjson"] // ""' <<<"$json" | base64 -d 2>/dev/null | empreinte)"
  if [[ -z "$config" || "$e_vault" != "$e_secret" ]]; then
    info "[KO] $espace/harbor-pull diffère du Vault (rotation du robot non reportée ?)"
    return 1
  fi
  info "[OK] $espace/harbor-pull identique au Vault"
}
