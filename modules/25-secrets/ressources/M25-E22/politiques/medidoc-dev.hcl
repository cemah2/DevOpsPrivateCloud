# politiques/medidoc-dev.hcl — groupe « medidoc » (MR !214, Lucas Martin).
# L'équipe MédiDoc gère les secrets de son environnement de dev, comme mediagenda-dev.

path "kv/data/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "kv/metadata/*" {
  capabilities = ["read", "list", "delete"]
}

# Tout l'arbre de dev (kv/medidoc/dev/<composant>/<secret>)
path "kv/data/medidoc/dev/+" {
  capabilities = ["create", "read", "update", "delete"]
}

# Par sécurité : jamais la prod
path "kv/data/medidoc/prod/*" {
  capabilities = ["deny"]
}

# Pour que les devs puissent couper leurs identifiants PostgreSQL de test
path "sys/leases/revoke-prefix/db-medidoc/*" {
  capabilities = ["update", "sudo"]
}

path "sys/capabilities-self" {
  capabilities = ["update"]
}
