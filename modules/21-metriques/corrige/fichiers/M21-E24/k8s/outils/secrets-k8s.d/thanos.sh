#!/usr/bin/env bash
# shellcheck disable=SC2154  # CONTENU, info, erreur, k, empreinte : fournis par secrets-k8s.sh
# =============================================================================
# plateforme/k8s — outils/secrets-k8s.d/thanos.sh (M21-E24, PLAT-2224) : composant « thanos » de
# secrets-k8s.sh (outils/secrets-k8s.sh appliquer|verifier thanos), sur le modèle des modules du
# M20 (argocd.sh, medidoc-commun.sh) : le Secret n'est pas une simple liste de clés (la table
# secrets-k8s.conf ne sait pas le décrire) mais un document objstore.yml construit à partir du Vault.
#
# Source : secrets/thanos.yml (Ansible Vault « critique », modèle secrets/thanos.yml.exemple) :
#   thanos_s3_access_key, thanos_s3_secret_key (utilisateur RGW « thanos », M21-E24 étape 2).
# Secret produit : supervision/thanos-objstore, clé objstore.yml (format objstore de Thanos), lu par
# les sidecars (prometheusSpec.thanos.objectStorageConfig), le Store Gateway et le Compactor.
# Le secret ne passe ni par un fichier en clair, ni par la ligne de commande (ps), ni par l'écran.
# Ne jamais lancer avec « bash -x » : la trace afficherait les valeurs.
# =============================================================================

_THANOS_ESPACE=supervision
_THANOS_SECRET=thanos-objstore

# _thanos_objstore — document objstore.yml construit en mémoire depuis le Vault (sortie standard).
# insecure: false + ca_file : TLS vérifié contre la racine MédiSphère (ConfigMap racine-medisphere,
# montée par chaque composant dans /etc/thanos/ca). bucket_lookup_type: path : le RGW du lab n'a pas
# de joker DNS (*.rgw.par1…) pour le style « virtual-host » (même choix que pour aws cli, M08).
_thanos_objstore() {
  local ak sk
  ak="$(yq -r '.thanos_s3_access_key // ""' <<<"$CONTENU")"
  sk="$(yq -r '.thanos_s3_secret_key // ""' <<<"$CONTENU")"
  [[ -n "$ak" && "$ak" != null && -n "$sk" && "$sk" != null ]] || return 1
  AK="$ak" SK="$sk" yq -n '
    .type = "S3" |
    .config.bucket = "thanos-k8s-par1" |
    .config.endpoint = "rgw.par1.medisphere.internal" |
    .config.region = "us-east-1" |
    .config.insecure = false |
    .config.bucket_lookup_type = "path" |
    .config.access_key = strenv(AK) |
    .config.secret_key = strenv(SK) |
    .config.http_config.tls_config.ca_file = "/etc/thanos/ca/ca.crt"
  '
}

# secrets_thanos_appliquer — crée ou met à jour supervision/thanos-objstore (server-side apply).
secrets_thanos_appliquer() {
  local doc
  if ! doc="$(_thanos_objstore)"; then
    erreur "secrets/thanos.yml : clés thanos_s3_access_key / thanos_s3_secret_key absentes"
    return 1
  fi
  # Le document passe par une substitution de processus (--from-file) : ni « ps », ni disque.
  k create secret generic "$_THANOS_SECRET" --namespace "$_THANOS_ESPACE" \
    --from-file=objstore.yml=<(printf '%s\n' "$doc") \
    --dry-run=client -o yaml \
    | k label --local -f - -o yaml \
        app.kubernetes.io/part-of=thanos medisphere.internal/composant=thanos medisphere.internal/source=ansible-vault \
    | k apply --server-side --field-manager=secrets-k8s -f - >/dev/null
  info "[OK] $_THANOS_ESPACE/$_THANOS_SECRET à jour (clé objstore.yml)"
}

# secrets_thanos_verifier — lecture seule : objstore.yml du Secret identique à celui du Vault (empreintes).
secrets_thanos_verifier() {
  local doc json
  doc="$(_thanos_objstore)" || { erreur "secrets/thanos.yml incomplet"; return 1; }
  json="$(k get secret "$_THANOS_SECRET" --namespace "$_THANOS_ESPACE" -o json 2>/dev/null)" || json=""
  if [[ -z "$json" ]]; then
    info "[KO] $_THANOS_ESPACE/$_THANOS_SECRET absent"
    return 1
  fi
  if [[ "$(jq -r '.data["objstore.yml"] // ""' <<<"$json" | base64 -d 2>/dev/null | empreinte)" \
    != "$(printf '%s\n' "$doc" | empreinte)" ]]; then
    info "[KO] $_THANOS_ESPACE/$_THANOS_SECRET : objstore.yml diffère du Vault"
    return 1
  fi
  info "[OK] $_THANOS_ESPACE/$_THANOS_SECRET : objstore.yml identique au Vault"
}
