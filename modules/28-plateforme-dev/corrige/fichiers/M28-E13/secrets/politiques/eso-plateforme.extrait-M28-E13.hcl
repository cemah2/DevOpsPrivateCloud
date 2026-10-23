# plateforme/secrets — politiques/eso-plateforme.hcl : EXTRAIT (M28-E13, PLAT-2913).
# Même ajout qu'en M28-E03 pour la production : le ClusterSecretStore « openbao » (rôle eso-plateforme)
# importe dans « messagerie » le mot de passe du compte RabbitMQ keda-prod (ExternalSecret
# rabbitmq-utilisateur-keda-prod de topologie/medinotif-prod/keda.yaml). Lecture seule, chemin exact.
# Côté medinotif-prod, rien à ajouter : le rôle eso-medinotif-prod lit déjà kv/medinotif/prod/* (M27-E08).
path "kv/data/medinotif/prod/keda" {
  capabilities = ["read"]
}

# Compte d'essai campagne-recette (topologie/medinotif-recette/campagne.yaml) : même import dans
# « messagerie ». À retirer avec le compte (quand les essais de charge passeront par k6, M29).
path "kv/data/medinotif/recette/campagne" {
  capabilities = ["read"]
}
