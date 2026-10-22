# politiques/medidoc-dev.hcl — groupe « medidoc » (MR !214 corrigée, M25-E22). Modèle : mediagenda-dev.
# L'équipe gère les secrets de SON environnement de dev, et rien d'autre.
path "kv/data/medidoc/dev/*" {
  capabilities = ["create", "read", "update", "delete"]
}

# Métadonnées : lister et lire les versions de SES secrets. Pas de « delete » sur metadata : il
# DÉTRUIT toutes les versions d'un secret, sans retour (kv metadata delete).
path "kv/metadata/medidoc/dev/*" {
  capabilities = ["read", "list"]
}

path "kv/metadata/medidoc/dev/" {
  capabilities = ["list"]
}

path "kv/metadata/medidoc/" {
  capabilities = ["list"]
}

# Supprimer (réversible) et restaurer une version.
path "kv/delete/medidoc/dev/*" {
  capabilities = ["update"]
}

path "kv/undelete/medidoc/dev/*" {
  capabilities = ["update"]
}

# Explicite et sans risque : même si une autre politique du jeton l'accordait un jour.
path "kv/data/medidoc/prod/*" {
  capabilities = ["deny"]
}

# Révoquer ses identifiants PostgreSQL de DEV : par bail (sys/leases/revoke, l'identifiant du bail
# est rendu avec les identifiants), jamais par préfixe (sudo, et le préfixe couvrait la prod).
path "sys/leases/revoke" {
  capabilities = ["update"]
}

path "sys/capabilities-self" {
  capabilities = ["update"]
}
