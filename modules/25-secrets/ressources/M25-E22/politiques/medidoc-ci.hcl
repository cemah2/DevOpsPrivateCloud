# politiques/medidoc-ci.hcl — CI de medidoc/medidoc (MR !214, Lucas Martin).

# Temporaire, le temps de trouver ce dont la CI a besoin
path "*" {
  capabilities = ["read", "list"]
}

path "kv/data/medidoc/prod/*" {
  capabilities = ["read", "sudo"]
}
