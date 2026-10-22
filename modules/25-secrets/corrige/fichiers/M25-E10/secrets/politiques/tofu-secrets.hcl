# politiques/tofu-secrets.hcl — plateforme/secrets (M25-E10, SEC-2610)
# Pipeline de plateforme/secrets (rôle JWT ci-plateforme-secrets : main et conf/* PROTÉGÉES).
# C'est une politique d'ADMINISTRATION de la configuration du coffre : elle écrit les politiques et
# les méthodes, donc elle peut s'élargir elle-même. Ce qui la borne : la protection des branches,
# l'approbation des MR (plateforme-admins), le job apply manuel, et l'audit (E21).
# Ce qu'elle NE donne PAS : la lecture des valeurs KV (sauf les accès de l'état OpenTofu), la
# génération d'identifiants (creds), l'émission de certificats (issue/sign), le chiffrement
# (encrypt/decrypt), sys/raw, la génération d'un jeton racine.

# Accès à l'état OpenTofu (identité S3 tofu-etat, phrase de chiffrement), lus par le job.
path "kv/data/plateforme/tofu/etat-secrets" {
  capabilities = ["read"]
}

# Politiques ACL et politiques de mot de passe.
path "sys/policies/acl" {
  capabilities = ["list"]
}

path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "sys/policies/password/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Méthodes d'authentification : activer/désactiver/régler exige « sudo » sur sys/auth/*.
path "sys/auth" {
  capabilities = ["read"]
}

path "sys/auth/*" {
  capabilities = ["create", "read", "update", "delete", "sudo"]
}

path "auth/+/config" {
  capabilities = ["create", "read", "update"]
}

path "auth/+/role/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "auth/+/role" {
  capabilities = ["list"]
}

# Groupes et alias d'identité (groupes externes OIDC du palier 1).
path "identity/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Montages de moteurs et leur réglage.
path "sys/mounts" {
  capabilities = ["read"]
}

path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete"]
}

# Configuration des moteurs du palier 2 (connexions, rôles, émetteurs) — jamais creds/, issue/, sign/.
path "db-mediagenda/config/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "db-mediagenda/roles/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "pki-services/roles/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "pki-services/config/*" {
  capabilities = ["create", "read", "update"]
}

path "pki-services/issuer/*" {
  capabilities = ["read", "update"]
}

path "kv/config" {
  capabilities = ["read", "update"]
}
