# tofu/db-data.tf — plateforme/secrets (F2-S07, DEV-3207)
# Moteur « database » de la base de l'équipe Data (statistiques-db, espace data-traitements), joint par
# le Service LoadBalancer réservé 10.10.41.66 (plateforme/k8s, espaces/data-traitements/60-openbao.yaml).
# Même méthode que db-mediagenda (M25-E14) :
#   1. connexion créée une fois avec le mot de passe INITIAL du rôle « openbao » (Secret
#      openbao-pg-initial, produit dans le cluster), passé par l'entrée standard, puis rotate-root :
#        admin@adm01:~$ kubectl -n data-traitements get secret openbao-pg-initial -o jsonpath='{.data.password}' \
#            | base64 -d | bao write db-data/config/statistiques password=- …   (voir le corrigé, étape 6)
#        admin@adm01:~$ bao write -f db-data/rotate-root/statistiques
#   2. puis importée ici (imports-db-data.tf) ; OpenTofu gère le reste.
# CA de la base : posée sur vault01-03 par le rôle openbao (openbao_bases_postgresql : statistiques-data).
resource "vault_mount" "db_data" {
  path                      = "db-data"
  type                      = "database"
  description               = "Identifiants dynamiques PostgreSQL de l'équipe Data (F2-S07)"
  max_lease_ttl_seconds     = 86400
  default_lease_ttl_seconds = 3600
}

resource "vault_database_secret_backend_connection" "statistiques" {
  backend           = vault_mount.db_data.path
  name              = "statistiques"
  plugin_name       = "postgresql-database-plugin"
  allowed_roles     = ["data-analyste", "data-traitement"]
  verify_connection = true
  password_policy   = vault_password_policy.postgresql_url.name

  postgresql {
    connection_url          = "postgresql://{{username}}:{{password}}@10.10.41.66:5432/statistiques?sslmode=verify-ca&sslrootcert=/etc/openbao/postgresql/statistiques-data-ca.crt&connect_timeout=5"
    username                = "openbao"
    password_authentication = "scram-sha-256"
    max_open_connections    = 4
  }
}

# data-analyste : personnes du groupe « data » (Hugo, Sarah) pour l'analyse ad hoc, en lecture, 8 h au
#   plus (une journée de travail) ; connexion par « kubectl port-forward » vers statistiques-db-r (une seule instance : le Service -ro
#   n'a aucun point de terminaison tant qu'il n'y a pas de réplica).
# data-traitement : CronJobs de l'équipe (ESO, générateur VaultDynamicSecret), écriture dans stats,
#   1 h ; la session prend le rôle stats_ecriture (les objets créés lui appartiennent, pas au compte
#   temporaire : sinon DROP ROLE échouerait à la fin du bail).
resource "vault_database_secret_backend_role" "data_analyste" {
  backend               = vault_mount.db_data.path
  name                  = "data-analyste"
  db_name               = vault_database_secret_backend_connection.statistiques.name
  creation_statements   = ["CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}' CONNECTION LIMIT 3 IN ROLE stats_lecture;"]
  revocation_statements = ["DROP ROLE IF EXISTS \"{{name}}\";"]
  default_ttl           = 28800
  max_ttl               = 28800
}

resource "vault_database_secret_backend_role" "data_traitement" {
  backend = vault_mount.db_data.path
  name    = "data-traitement"
  db_name = vault_database_secret_backend_connection.statistiques.name
  creation_statements = [
    "CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}' CONNECTION LIMIT 5 IN ROLE stats_ecriture;",
    "ALTER ROLE \"{{name}}\" SET role = 'stats_ecriture';",
  ]
  revocation_statements = ["DROP ROLE IF EXISTS \"{{name}}\";"]
  default_ttl           = 3600
  max_ttl               = 7200
}
