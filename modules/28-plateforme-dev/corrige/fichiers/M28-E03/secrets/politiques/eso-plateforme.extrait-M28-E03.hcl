# plateforme/secrets — politiques/eso-plateforme.hcl : EXTRAIT (M28-E03).
# Le ClusterSecretStore « openbao » (rôle eso-plateforme) importe dans « messagerie » les identifiants
# des utilisateurs RabbitMQ. Si TON M27 a déjà ouvert kv/medinotif/+/amqp de la même façon, ajoute
# seulement le chemin de KEDA. Lecture seule, chemin exact.
path "kv/data/medinotif/recette/keda" {
  capabilities = ["read"]
}
