# chiffrement.tf — PHASE 1 de la migration (M05-E27) : écrire chiffré, savoir encore lire en clair.
#
# 1. Cette version est fusionnée, puis appliquée (plan VIDE : l'apply réécrit l'état, chiffré).
# 2. On vérifie l'objet dans tofu-state (clé encrypted_data, plus de clé resources).
# 3. Une seconde MR remplace ce fichier par la version finale (socle/chiffrement.tf) : plus de
#    méthode « unencrypted », enforced = true. Sans cette seconde étape, un état en clair restauré
#    par erreur serait lu sans alerte, et réécrit… chiffré, en silence.
terraform {
  encryption {
    method "aes_gcm" "etat" {
      keys = key_provider.pbkdf2.etat
    }

    # Uniquement pour la migration : lire un état encore en clair.
    method "unencrypted" "migration" {}

    state {
      method = method.aes_gcm.etat
      fallback {
        method = method.unencrypted.migration
      }
    }

    plan {
      method = method.aes_gcm.etat
      fallback {
        method = method.unencrypted.migration
      }
    }

    remote_state_data_sources {
      default {
        method = method.aes_gcm.etat
        fallback {
          method = method.unencrypted.migration
        }
      }
    }
  }
}
