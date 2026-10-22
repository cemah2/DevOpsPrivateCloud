# politiques/plateforme-admin.hcl — groupe Keycloak « plateforme-admins » (M25-E05, en code en E08).
# Administrer la CONFIGURATION du coffre et les secrets de la plateforme, sans être root.
# Ce qui n'y est pas, volontairement : sys/raw (lecture brute du stockage), sys/rotate et
# sys/rekey (clés de la barrière : cérémonie à plusieurs, E44), les secrets des applications
# (kv/<application>/… : leurs équipes et leurs identités machines).
# Les paliers suivants ajoutent les montages qu'ils créent (db-mediagenda/, transit/, pki-services/).

# --- Montages de moteurs, méthodes d'authentification, politiques -------------------------------
path "sys/mounts" {
  capabilities = ["read"]
}

path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete"]
}

# Activer, régler ou retirer une méthode d'authentification exige « sudo ».
path "sys/auth" {
  capabilities = ["read"]
}

path "sys/auth/*" {
  capabilities = ["create", "read", "update", "delete", "sudo"]
}

path "sys/policies/acl" {
  capabilities = ["list"]
}

path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# --- Configuration des méthodes (rôles OIDC, AppRole, plus tard JWT et Kubernetes) ----------------
# Le « + » vise un seul segment : auth/oidc/role/x, auth/approle/role/x/secret-id…
path "auth/+/config" {
  capabilities = ["create", "read", "update"]
}

# Une liste (LIST) porte sur le chemin AVEC la barre finale (auth/oidc/role/) : « * » la couvre.
path "auth/+/role/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Jeton enfant créé par le fournisseur OpenTofu (durée courte, révoqué après chaque exécution).
path "auth/token/create" {
  capabilities = ["update"]
}

path "auth/token/lookup-accessor" {
  capabilities = ["update"]
}

path "auth/token/revoke-accessor" {
  capabilities = ["update"]
}

path "auth/token/accessors" {
  capabilities = ["list", "sudo"]
}

# --- Identités : groupes externes et leurs alias (correspondance Keycloak → politiques) ------------
path "identity/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# --- Secrets de la plateforme (KV v2) --------------------------------------------------------------
path "kv/config" {
  capabilities = ["read", "update"]
}

path "kv/data/plateforme/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "kv/metadata/*" {
  capabilities = ["read", "list"]
}

path "kv/metadata/plateforme/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "kv/delete/plateforme/*" {
  capabilities = ["update"]
}

path "kv/undelete/plateforme/*" {
  capabilities = ["update"]
}

path "kv/destroy/plateforme/*" {
  capabilities = ["update"]
}

# --- Exploitation ------------------------------------------------------------------------------------
path "sys/capabilities" {
  capabilities = ["update"]
}

path "sys/capabilities-accessor" {
  capabilities = ["update"]
}

path "sys/leases/lookup" {
  capabilities = ["update"]
}

path "sys/leases/revoke" {
  capabilities = ["update"]
}

# Sceller le coffre en urgence (fuite avérée, RB-250) : « sudo ».
path "sys/seal" {
  capabilities = ["update", "sudo"]
}

# Régénérer un jeton racine avec les parts (E28) : depuis OpenBao 2.6, l'opération passe par ces
# chemins AUTHENTIFIÉS ; les anciens chemins sans jeton sont désactivés par défaut depuis 2.5.3.
path "sys/generate-root-token/*" {
  capabilities = ["create", "read", "update", "delete"]
}
