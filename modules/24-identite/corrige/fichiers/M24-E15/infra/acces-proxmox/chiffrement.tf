# acces-proxmox/chiffrement.tf — COPIE à l'identique de socle/chiffrement.tf (M05-E27), M24-E15.
# Même fournisseur de clé « pbkdf2 etat », même phrase (TF_ENCRYPTION, outils/charger-acces.sh).
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
