# politiques/sops-plateforme.hcl — chiffrer et déchiffrer les fichiers SOPS des dépôts de
# formation et d'essai par la clé de transit sops-plateforme (M25-E18, PLAT-2618).
# Attachée aux groupes externes plateforme-admins et plateforme (variable groupes_keycloak).
# Rien d'autre : ni lire ni régler la clé, ni la tourner.
path "transit/encrypt/sops-plateforme" {
  capabilities = ["update"]
}

path "transit/decrypt/sops-plateforme" {
  capabilities = ["update"]
}
