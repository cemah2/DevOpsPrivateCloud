# tofu/transit.tf — moteur transit : le chiffrement comme service (M25-E17, SEC-2617).
# Les clés ne quittent jamais OpenBao : les clients envoient des données, reçoivent du chiffré
# (« vault:v<N>:… »), et inversement. Clés ajoutées par les exercices suivants : sops-plateforme
# (M25-E18), cosign-medisphere (M25-E20).
#
# Ce que ce fichier NE fait PAS : tourner une clé. La rotation est une OPÉRATION
# (transit/keys/<clé>/rotate, ou auto_rotate_period), pas une configuration : OpenTofu ne fait que
# lire latest_version. min_decryption_version n'est PAS géré ici non plus : le relever est une
# décision ponctuelle (crypto-effacement, RB-250), pas un état à reconverger à chaque apply.

resource "vault_mount" "transit" {
  path        = "transit"
  type        = "transit"
  description = "Chiffrement comme service : clés non exportables (SEC-2617)"
}

# Champs des fiches d'intervention exportées par medictl (codes d'accès des baies, numéros
# d'astreinte des prestataires). Rotation automatique annuelle ; jamais exportable, jamais de
# sauvegarde en clair, jamais supprimable par erreur (deletion_allowed = false).
resource "vault_transit_secret_backend_key" "medictl_donnees" {
  backend = vault_mount.transit.path
  name    = "medictl-donnees"
  type    = "aes256-gcm96"

  exportable             = false
  allow_plaintext_backup = false
  deletion_allowed       = false
  auto_rotate_period     = 31536000 # 365 jours, en secondes
}

# Clé JETABLE des manipulations d'E17 (rotation, rewrap, min_decryption_version, trim, essai du
# fournisseur de clé d'OpenTofu). deletion_allowed = true pour pouvoir la détruire : retire ce bloc
# à la fin de l'exercice (le plan annonce « 1 to destroy »), elle n'a rien à faire en production.
resource "vault_transit_secret_backend_key" "essai_e17" {
  backend = vault_mount.transit.path
  name    = "essai-e17"
  type    = "aes256-gcm96"

  exportable             = false
  allow_plaintext_backup = false
  deletion_allowed       = true
}
