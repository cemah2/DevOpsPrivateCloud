# tofu/db-mediagenda.tf — plateforme/secrets (M25-E14, DEV-2614)
# Moteur « database » des bases de MédiAgenda (CloudNativePG), joint par des Services LoadBalancer
# réservés : 10.10.41.64 (recette), 10.10.41.65 (prod).
#
# Le MOT DE PASSE de connexion (rôle PostgreSQL « openbao ») n'est PAS dans ce code ni dans l'état :
#   1. la connexion est créée une fois à la main, mot de passe initial passé par l'entrée standard
#      (corrigé M25-E14, étape 3), puis aussitôt remplacé par OpenBao (rotate-root) : plus personne
#      ne le connaît ;
#   2. elle est ensuite IMPORTÉE ici (imports.tf) ; OpenTofu gère tout le reste (URL, rôles permis,
#      politique de mot de passe). Une mise à jour sans mot de passe GARDE celui d'OpenBao (vérifié :
#      verify_connection réussit après une réécriture sans mot de passe).
# Reconstruction depuis zéro : refaire l'étape 1 avant tofu apply (sinon la vérification échoue).
#
# TLS : sslmode=verify-ca et sslrootcert (fichier posé sur vault01-03 par le rôle openbao) dans
# l'URL. Le paramètre « tls_ca » du fournisseur n'est PAS utilisé : le greffon PostgreSQL
# d'OpenBao 2.6 l'enregistre sans s'en servir (vérifié dans le code du greffon, plugins/database/
# postgresql, et en essai : une CA fausse dans tls_ca ne change rien).

resource "vault_mount" "db_mediagenda" {
  path        = "db-mediagenda"
  type        = "database"
  description = "Identifiants dynamiques PostgreSQL de MédiAgenda (M25-E14)"
  # Aucun bail de ce moteur ne dépasse 24 h.
  max_lease_ttl_seconds     = 86400
  default_lease_ttl_seconds = 3600
}

resource "vault_password_policy" "postgresql_url" {
  name   = "postgresql-url"
  policy = file("${path.module}/../politiques-mdp/postgresql-url.hcl")
}

locals {
  bases_mediagenda = {
    recette = { adresse = "10.10.41.64" }
    prod    = { adresse = "10.10.41.65" }
  }
}

resource "vault_database_secret_backend_connection" "mediagenda" {
  for_each = local.bases_mediagenda

  backend       = vault_mount.db_mediagenda.path
  name          = "mediagenda-${each.key}"
  plugin_name   = "postgresql-database-plugin"
  allowed_roles = ["mediagenda-api-${each.key}", "mediagenda-migrateur-${each.key}"]
  # verify_connection : une configuration qui ne se connecte pas est refusée à l'écriture.
  verify_connection = true
  password_policy   = vault_password_policy.postgresql_url.name

  postgresql {
    connection_url          = "postgresql://{{username}}:{{password}}@${each.value.adresse}:5432/mediagenda?sslmode=verify-ca&sslrootcert=/etc/openbao/postgresql/mediagenda-${each.key}-ca.crt&connect_timeout=5"
    username                = "openbao"
    password_authentication = "scram-sha-256"
    max_open_connections    = 4
  }
}

# Instructions SQL. {{name}}, {{password}}, {{expiration}} : remplis par OpenBao.
#  - api : appartenance au rôle de groupe mediagenda_api (droits de lecture-écriture des lignes,
#    posés une fois par le SQL de préparation) ; VALID UNTIL = fin du bail.
#  - migrateur : appartenance au propriétaire « mediagenda », et paramètre de session role par
#    défaut = mediagenda : tout ce que la session crée APPARTIENT à mediagenda, pas au compte
#    temporaire (sinon DROP ROLE échouerait à la révocation, « role … cannot be dropped because some
#    objects depend on it », et le schéma changerait de propriétaire à chaque migration).
#  - révocation : DROP ROLE ; les sessions encore ouvertes de ce compte cessent de fonctionner
#    (« invalid role OID ») : un pod doit avoir changé d'identifiant AVANT la fin du bail (E15).
locals {
  roles_mediagenda = merge([
    for env, _ in local.bases_mediagenda : {
      "mediagenda-api-${env}" = {
        env      = env
        creation = ["CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}' IN ROLE mediagenda_api;"]
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

resource "vault_database_secret_backend_role" "mediagenda" {
  for_each = local.roles_mediagenda

  backend               = vault_mount.db_mediagenda.path
  name                  = each.key
  db_name               = vault_database_secret_backend_connection.mediagenda[each.value.env].name
  creation_statements   = each.value.creation
  revocation_statements = ["DROP ROLE IF EXISTS \"{{name}}\";"]
  default_ttl           = 3600
  max_ttl               = 86400
}
