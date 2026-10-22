#!/usr/bin/env bash
# shellcheck disable=SC2154  # CONTENU, info, erreur, k, empreinte : fournis par secrets-k8s.sh
# =============================================================================
# plateforme/k8s — outils/secrets-k8s.d/medidoc-commun.sh (M20-E33, DEV-2133)
# Fonctions communes aux composants medidoc-dev et medidoc-recette (modules medidoc-<env>.sh,
# sourcés par secrets-k8s.sh comme argocd.sh en M20-E06 et mediagenda-*.sh en M20-E12). Remplace
# outils/secret-medidoc-s3.sh (M16-E46), qui lisait un fichier de ~/.config/workbook : la source
# devient le Vault. Source : secrets/medidoc-<env>.yml (Ansible Vault « critique ») :
#   harbor_pull_utilisateur: "robot$k8s-pull"      harbor_pull_jeton: "<jeton>"
#   medidoc_s3_cle_acces: "<clé>"                    medidoc_s3_cle_secrete: "<secret>"
# Crée, dans l'espace du même nom que le composant :
#   harbor-pull   kubernetes.io/dockerconfigjson (robot$k8s-pull)
#   medidoc-s3    AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY du compte RGW de l'environnement
# Aucun de ces Secrets n'est dans medidoc/deploiement : Argo CD ne les voit pas et ne les supprime pas.
# Ne jamais lancer avec « bash -x » : la trace afficherait les valeurs.
# =============================================================================

_REGISTRE_MEDISPHERE="registry.par1.medisphere.internal"

# _medidoc_valeur CLÉ — valeur d'une clé du Vault déchiffré (vide si absente).
_medidoc_valeur() { yq -r ".$1 // \"\"" <<<"$CONTENU"; }

# _medidoc_dockerconfig — JSON .dockerconfigjson construit depuis le Vault (sur la sortie standard).
_medidoc_dockerconfig() {
  local utilisateur jeton
  utilisateur="$(_medidoc_valeur harbor_pull_utilisateur)"
  jeton="$(_medidoc_valeur harbor_pull_jeton)"
  [[ -n "$utilisateur" && -n "$jeton" && "$jeton" != null ]] || return 1
  jq -cn --arg r "$_REGISTRE_MEDISPHERE" --arg a "$(printf '%s:%s' "$utilisateur" "$jeton" | base64 -w0)" \
    '{auths: {($r): {auth: $a}}}'
}

# secrets_medidoc_appliquer ESPACE — crée ou met à jour ESPACE/harbor-pull et ESPACE/medidoc-s3.
secrets_medidoc_appliquer() {
  local espace="$1" config cle secret
  cle="$(_medidoc_valeur medidoc_s3_cle_acces)"
  secret="$(_medidoc_valeur medidoc_s3_cle_secrete)"
  if ! config="$(_medidoc_dockerconfig)" || [[ -z "$cle" || -z "$secret" ]]; then
    erreur "clé absente de secrets/$espace.yml (harbor_pull_utilisateur, harbor_pull_jeton, medidoc_s3_cle_acces, medidoc_s3_cle_secrete)"
    return 1
  fi
  # Les valeurs passent par des substitutions de processus (--from-file) : ni « ps », ni disque.
  k create secret generic harbor-pull --namespace "$espace" \
    --type=kubernetes.io/dockerconfigjson \
    --from-file=.dockerconfigjson=<(printf '%s' "$config") \
    --dry-run=client -o yaml \
    | k label --local -f - -o yaml \
        medisphere.internal/composant="$espace" medisphere.internal/source=ansible-vault \
    | k apply --server-side --field-manager=secrets-k8s -f - >/dev/null
  k create secret generic medidoc-s3 --namespace "$espace" \
    --from-file=AWS_ACCESS_KEY_ID=<(printf '%s' "$cle") \
    --from-file=AWS_SECRET_ACCESS_KEY=<(printf '%s' "$secret") \
    --dry-run=client -o yaml \
    | k label --local -f - -o yaml \
        medisphere.internal/composant="$espace" medisphere.internal/source=ansible-vault \
    | k apply --server-side --field-manager=secrets-k8s -f - >/dev/null
  info "[OK] $espace/harbor-pull et $espace/medidoc-s3 à jour"
}

# _medidoc_comparer ESPACE SECRET CLÉ_K8S VALEUR — lecture seule : la clé du Secret égale la valeur.
_medidoc_comparer() {
  local espace="$1" nom="$2" cle="$3" valeur="$4" json
  json="$(k get secret "$nom" --namespace "$espace" -o json 2>/dev/null)" || json=""
  if [[ -z "$json" ]]; then
    info "[KO] $espace/$nom absent"
    return 1
  fi
  if [[ "$(jq -r --arg c "$cle" '.data[$c] // ""' <<<"$json" | base64 -d 2>/dev/null | empreinte)" \
    != "$(printf '%s' "$valeur" | empreinte)" ]]; then
    info "[KO] $espace/$nom : $cle diffère du Vault"
    return 1
  fi
  info "[OK] $espace/$nom : $cle identique au Vault"
}

# secrets_medidoc_verifier ESPACE — lecture seule, par empreintes.
secrets_medidoc_verifier() {
  local espace="$1" config ecarts=0
  config="$(_medidoc_dockerconfig)" || config=""
  _medidoc_comparer "$espace" harbor-pull .dockerconfigjson "$config" || ecarts=$((ecarts + 1))
  _medidoc_comparer "$espace" medidoc-s3 AWS_ACCESS_KEY_ID "$(_medidoc_valeur medidoc_s3_cle_acces)" || ecarts=$((ecarts + 1))
  _medidoc_comparer "$espace" medidoc-s3 AWS_SECRET_ACCESS_KEY "$(_medidoc_valeur medidoc_s3_cle_secrete)" || ecarts=$((ecarts + 1))
  ((ecarts == 0))
}
