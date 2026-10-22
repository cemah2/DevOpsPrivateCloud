# politiques/ci-medidoc-medidoc.hcl — plateforme/secrets (M25-E10, SEC-2610)
# Même modèle que ci-mediagenda-api pour medidoc/medidoc.
path "kv/data/plateforme/harbor/robot-ci" {
  capabilities = ["read"]
}

path "kv/data/medidoc/ci/release" {
  capabilities = ["read"]
}
