# registre/chiffrement.tf — copie CONFORME de socle/chiffrement.tf (M05-E27).
# Indispensable ici : l'état contient les secrets des robots et les mots de passe initiaux des
# utilisateurs (random_password). La phrase vient de TF_ENCRYPTION (outils/charger-acces.sh,
# outils/ci-preparer.sh), jamais du code.
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
