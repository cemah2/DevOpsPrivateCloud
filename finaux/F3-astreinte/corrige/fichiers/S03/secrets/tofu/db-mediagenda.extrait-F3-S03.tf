# tofu/db-mediagenda.tf — plateforme/secrets : EXTRAIT de la correction de F3-S03 (INC-5903, PLAT-3303).
# Remplace le bloc « locals { roles_mediagenda = … } » du M25-E14 ; le reste du fichier est inchangé.
#
# Les rôles dynamiques de l'API reçoivent des délais PAR RÔLE (ALTER ROLE … SET), appliqués à
# l'ouverture de chaque connexion serveur. Avec PgBouncer en mode transaction, une connexion serveur
# appartient à un seul utilisateur : les réglages suivent bien l'identifiant dynamique.
#   - lock_timeout 3 s : une requête de l'API n'attend plus un verrou plus de 3 s (erreur claire,
#     au lieu d'une file d'attente qui sature le pooler) ;
#   - statement_timeout 15 s : aucune requête de l'API ne dépasse 15 s ;
#   - idle_in_transaction_session_timeout 60 s : cohérent avec idle_transaction_timeout du pooler.
# Le migrateur n'est pas concerné : Flyway pose son propre lock_timeout (M27-E06).
# Les identifiants déjà émis gardent l'ancien réglage jusqu'à leur renouvellement (30 min, ESO).
locals {
  delais_api = [
    "ALTER ROLE \"{{name}}\" SET lock_timeout = '3s';",
    "ALTER ROLE \"{{name}}\" SET statement_timeout = '15s';",
    "ALTER ROLE \"{{name}}\" SET idle_in_transaction_session_timeout = '60s';",
  ]
  roles_mediagenda = merge([
    for env, _ in local.bases_mediagenda : {
      "mediagenda-api-${env}" = {
        env = env
        creation = concat(
          ["CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}' IN ROLE mediagenda_api;"],
          local.delais_api,
        )
      }
      "mediagenda-migrateur-${env}" = {
        env = env
        creation = [
          "CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}' IN ROLE mediagenda;",
          "ALTER ROLE \"{{name}}\" SET role = 'mediagenda';",
        ]
      }
    }
  ]...)
}
