# politiques/wb-checks.hcl — VERSION FINALE (M25-E46, étiquette secrets-v1) : la politique du M25-E07/E08
# et tous les extraits ajoutés exercice par exercice (E10, E17, E24, E28, E41, E44), fusionnés sans
# doublon. MÉTADONNÉES ET CONFIGURATION SEULEMENT : jamais kv/data/*, */creds/*, */issue/*, */sign/*,
# transit/decrypt|export|backup, sys/storage/raft/snapshot, auth/approle/role/+/secret-id ni role-id.

# --- M25-E07/E08 : montages, méthodes, politiques, existence des secrets, accessors -----------------
path "sys/mounts" {
  capabilities = ["read"]
}

path "sys/auth" {
  capabilities = ["read"]
}

path "sys/policies/acl" {
  capabilities = ["list"]
}

path "sys/policies/acl/*" {
  capabilities = ["read"]
}

path "kv/config" {
  capabilities = ["read"]
}

path "kv/metadata/*" {
  capabilities = ["read", "list"]
}

# Rôles des méthodes (réglages, CIDR, durées) ; la lecture d'une configuration OIDC ne renvoie pas
# le secret du client. Jamais auth/approle/role/+/secret-id ni role-id.
path "auth/+/config" {
  capabilities = ["read"]
}

path "auth/+/role/" {
  capabilities = ["list"]
}

path "auth/+/role/+" {
  capabilities = ["read"]
}

path "identity/group/name/" {
  capabilities = ["list"]
}

path "identity/group/name/+" {
  capabilities = ["read"]
}

# Qui s'est déjà connecté par quelle méthode (alias d'entité : identifiant et méthode, rien d'autre).
path "identity/entity-alias/id/" {
  capabilities = ["list"]
}

# Contrôler qu'aucun jeton racine ne traîne (M25-E08) : liste des accessors et lecture de leurs
# métadonnées (politiques, date). Un accessor ne permet pas d'utiliser le jeton.
path "auth/token/accessors" {
  capabilities = ["list", "sudo"]
}

path "auth/token/lookup-accessor" {
  capabilities = ["update"]
}

# --- M25-E10 : moteur database, rôles PKI, baux des identifiants dynamiques (list exige sudo) --------
path "db-mediagenda/config/*" {
  capabilities = ["read", "list"]
}

path "db-mediagenda/roles/*" {
  capabilities = ["read", "list"]
}

path "pki-services/roles/*" {
  capabilities = ["read", "list"]
}

# Lister des baux exige « sudo » (API sys/leases/lookup ; essayé : « list » seul est refusé). Limité
# au préfixe des identifiants dynamiques : on voit des identifiants de baux, jamais les comptes.
path "sys/leases/lookup/db-mediagenda/*" {
  capabilities = ["list", "sudo"]
}

# --- M25-E17 : métadonnées des clés de transit (aucun matériel de clé) -------------------------------
path "transit/keys" {
  capabilities = ["list"]
}

path "transit/keys/+" {
  capabilities = ["read"]
}

# --- M25-E24 : pairs Raft et autopilot ---------------------------------------------------------------
path "sys/storage/raft/configuration" {
  capabilities = ["read"]
}

path "sys/storage/raft/autopilot/state" {
  capabilities = ["read"]
}

path "sys/storage/raft/autopilot/configuration" {
  capabilities = ["read"]
}

# --- M25-E28 : quotas de débit -----------------------------------------------------------------------
path "sys/quotas/rate-limit" {
  capabilities = ["list"]
}

path "sys/quotas/rate-limit/*" {
  capabilities = ["read"]
}

# --- M25-E41 : configuration de l'émetteur et de la CRL de la PKI de services ------------------------
path "pki-services/config/issuers" {
  capabilities = ["read"]
}

path "pki-services/issuer/+" {
  capabilities = ["read"]
}

path "pki-services/config/crl" {
  capabilities = ["read"]
}

# --- M25-E44 : état du trousseau (terme, date, compteur ; aucune clé) --------------------------------
path "sys/key-status" {
  capabilities = ["read"]
}
