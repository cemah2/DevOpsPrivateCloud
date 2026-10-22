# politiques/eso-plateforme.hcl — plateforme/secrets (M25-E12, complétée en M25-E13, PLAT-2613)
# ClusterSecretStore « openbao » (compte external-secrets). Il sert TOUS les espaces listés dans ses
# conditions : chaque chemin ci-dessous est lisible par tout ExternalSecret de ces espaces. D'où un
# bloc par COMPOSANT migré, ajouté par MR, et jamais « kv/data/plateforme/* » (qui donnerait
# ansible-vault, harbor/robot-ci, tofu/etat-secrets, cosign…).
# Limite assumée (à revoir en M25-E46 ou M26) : un ExternalSecret de l'espace traces pourrait lire un
# secret d'argocd. La parade serait un SecretStore par espace de plateforme, comme pour les équipes.
path "kv/data/plateforme/argocd/*" {
  capabilities = ["read"]
}

path "kv/data/plateforme/grafana/*" {
  capabilities = ["read"]
}

path "kv/data/plateforme/thanos/*" {
  capabilities = ["read"]
}

path "kv/data/plateforme/loki/*" {
  capabilities = ["read"]
}

path "kv/data/plateforme/tempo/*" {
  capabilities = ["read"]
}

path "kv/data/plateforme/pyroscope/*" {
  capabilities = ["read"]
}

path "kv/data/plateforme/otel/*" {
  capabilities = ["read"]
}

path "kv/data/plateforme/gitlab-runner/*" {
  capabilities = ["read"]
}

path "kv/data/plateforme/gitlab-agent/*" {
  capabilities = ["read"]
}

path "kv/data/plateforme/oauth2-proxy/*" {
  capabilities = ["read"]
}
