# chiffrement.tf — chiffrement côté client de l'état et des plans (M05-E27, ticket SEC-659).
#
# Fichier IDENTIQUE dans chaque configuration racine (socle/, envs/…, envs/openstack-projets/) ;
# généré par terragrunt/live/root.hcl pour les unités Terragrunt.
#
# Le fournisseur de clé n'est PAS ici : il vient de la variable d'environnement TF_ENCRYPTION,
# fusionnée par OpenTofu avec ce bloc (outils/charger-acces.sh sur adm01, outils/ci-preparer.sh
# en CI). Ainsi la phrase n'est ni dans le code, ni dans un plan enregistré (une variable
# OpenTofu, elle, est recopiée en clair dans chaque plan : voir M05-E27, étape 2).
#   TF_ENCRYPTION='key_provider "pbkdf2" "etat" { passphrase = "<PHRASE>" }'
#
# Les NOMS « etat » sont écrits dans les métadonnées de chaque état chiffré : les changer
# demande une migration (fallback) ou encrypted_metadata_alias.
terraform {
  encryption {
    method "aes_gcm" "etat" {
      keys = key_provider.pbkdf2.etat
    }

    # enforced : OpenTofu refuse d'écrire un état ou un plan en clair, même si quelqu'un
    # ajoute un jour une méthode « unencrypted » en principal.
    state {
      method   = method.aes_gcm.etat
      enforced = true
    }

    plan {
      method   = method.aes_gcm.etat
      enforced = true
    }

    # Lecture des états distants (terraform_remote_state) : ils sont chiffrés avec la même phrase.
    remote_state_data_sources {
      default {
        method = method.aes_gcm.etat
      }
    }
  }
}
