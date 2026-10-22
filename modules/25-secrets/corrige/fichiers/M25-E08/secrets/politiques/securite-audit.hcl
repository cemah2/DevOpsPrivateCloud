# politiques/securite-audit.hcl — groupe « securite » (Sophie Laurent) (M25-E05, en code en E08).
# Auditer sans pouvoir agir : la configuration, les dispositifs d'audit, les politiques, les
# identités, les jetons en cours (métadonnées). Aucune valeur de secret, aucune écriture.
path "sys/mounts" {
  capabilities = ["read"]
}

path "sys/auth" {
  capabilities = ["read"]
}

# Lister les dispositifs d'audit exige « sudo » (lecture seule malgré le nom).
path "sys/audit" {
  capabilities = ["read", "sudo"]
}

# Calculer le HMAC d'une valeur pour la retrouver dans le journal d'audit (M25-E21).
path "sys/audit-hash/*" {
  capabilities = ["update"]
}

path "sys/policies/acl" {
  capabilities = ["list"]
}

path "sys/policies/acl/*" {
  capabilities = ["read"]
}

path "kv/metadata/*" {
  capabilities = ["read", "list"]
}

# Mêmes motifs que plateforme-admin et plateforme-lecture (voir l'avertissement de ce fichier-là).
path "auth/+/role/*" {
  capabilities = ["read", "list"]
}

path "identity/*" {
  capabilities = ["read", "list"]
}

path "auth/token/accessors" {
  capabilities = ["list", "sudo"]
}

path "auth/token/lookup-accessor" {
  capabilities = ["update"]
}

path "sys/capabilities-self" {
  capabilities = ["update"]
}
