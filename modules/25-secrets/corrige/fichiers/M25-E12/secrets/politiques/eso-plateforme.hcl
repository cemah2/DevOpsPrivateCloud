# politiques/eso-plateforme.hcl — plateforme/secrets (M25-E12 ; complétée en M25-E13)
# ClusterSecretStore « openbao » (compte external-secrets). Il sert TOUS les espaces de plateforme
# listés dans ses conditions : chaque chemin ajouté ici devient lisible par tout ExternalSecret de
# ces espaces. Donc : un bloc par composant, ajouté par MR quand le composant migre (E13), jamais
# « kv/data/plateforme/* » (qui donnerait ansible-vault, harbor/robot-ci, tofu/etat-secrets…).
# E12 : vide (le ClusterSecretStore doit être Ready ; aucune donnée n'est encore lue).
path "kv/metadata/plateforme/vide" {
  capabilities = ["deny"]
}
