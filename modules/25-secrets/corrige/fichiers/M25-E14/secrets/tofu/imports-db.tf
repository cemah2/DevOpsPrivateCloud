# tofu/imports-db.tf — plateforme/secrets (M25-E14) : connexions créées à la main (étape 3) puis
# reprises en code. Supprimer ces blocs une fois l'import appliqué (ou les garder : sans effet).
import {
  to = vault_database_secret_backend_connection.mediagenda["recette"]
  id = "db-mediagenda/config/mediagenda-recette"
}
import {
  to = vault_database_secret_backend_connection.mediagenda["prod"]
  id = "db-mediagenda/config/mediagenda-prod"
}
