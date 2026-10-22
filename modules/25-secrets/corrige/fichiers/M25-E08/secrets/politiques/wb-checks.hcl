# politiques/wb-checks.hcl — AppRole « wb-checks » des vérifications du workbook (M25-E07, en code
# en E08). MÉTADONNÉES SEULEMENT : la configuration du coffre et l'existence des secrets, jamais une
# valeur (aucun kv/data/*, aucun secret-id, aucune configuration contenant un secret).
# Les paliers suivants ajoutent ce que leurs checks lisent (rôles JWT et Kubernetes, sys/audit…).
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
