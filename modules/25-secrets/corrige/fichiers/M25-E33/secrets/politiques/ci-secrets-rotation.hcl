# politiques/ci-secrets-rotation.hcl — job planifié de rotation de plateforme/secrets (M25-E33, SEC-2633),
# rôle JWT « ci-secrets-rotation » du montage gitlab (branche main protégée de plateforme/secrets).
# Écrire une nouvelle version des secrets de la plateforme et lire leurs métadonnées ; lire ses propres
# identifiants de rotation (Keycloak svc-rotation, jeton GitLab de rotation) ; faire tourner le mot de
# passe racine des connexions de bases ; rien d'autre (pas de suppression, pas de destruction de
# version, pas de sys/).
path "kv/data/plateforme/*" {
  capabilities = ["read", "update", "patch"]
}

path "kv/metadata/plateforme/*" {
  capabilities = ["read", "list", "patch"]
}

path "kv/metadata/plateforme" {
  capabilities = ["list"]
}

path "kv/data/plateforme/rotation/*" {
  capabilities = ["read"]
}

path "db-mediagenda/rotate-root/+" {
  capabilities = ["update"]
}
