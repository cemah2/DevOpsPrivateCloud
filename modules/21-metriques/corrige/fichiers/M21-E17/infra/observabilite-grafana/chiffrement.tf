# observabilite-grafana/chiffrement.tf — copie CONFORME de socle/chiffrement.tf (M05-E27).
# L'état ne contient pas de secret (le jeton du fournisseur n'y est jamais écrit), mais la règle
# MédiSphère est la même pour tous les états : chiffrés, phrase dans TF_ENCRYPTION.
terraform {
  encryption {
    method "aes_gcm" "etat" {
      keys = key_provider.pbkdf2.etat
    }
    state {
      method   = method.aes_gcm.etat
      enforced = true
    }
    plan {
      method   = method.aes_gcm.etat
      enforced = true
    }
    remote_state_data_sources {
      default {
        method = method.aes_gcm.etat
      }
    }
  }
}
