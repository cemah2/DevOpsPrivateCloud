# plateforme/secrets — politiques/eso-plateforme.hcl : EXTRAIT (M28-E06).
# Le ClusterSecretStore « openbao » lit les secrets du portail (ExternalSecret « portail »).
path "kv/data/plateforme/portail" {
  capabilities = ["read"]
}
