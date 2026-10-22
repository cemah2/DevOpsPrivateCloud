# politiques/medidoc-purge.hcl — script de purge nocturne de MédiDoc sur runner02 (MR !214 corrigée).
# Son propre secret d'accès, rien d'autre (et surtout pas la politique de la CI).
path "kv/data/medidoc/prod/purge" {
  capabilities = ["read"]
}
