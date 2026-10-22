# politiques/eso-wb-essais.hcl — plateforme/secrets (M25-E12)
# SecretStore « openbao » de l'espace d'essais : rien hors de kv/wb-essais/.
path "kv/data/wb-essais/*" {
  capabilities = ["read"]
}
