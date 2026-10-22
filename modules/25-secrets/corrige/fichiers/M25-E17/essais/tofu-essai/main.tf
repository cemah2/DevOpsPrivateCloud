# ~/m25/e17/tofu-essai/main.tf — essai du fournisseur de clé « openbao » d'OpenTofu (M25-E17, étape 7).
# Promesse du M05-E27 : « au module 25, le fournisseur de clé openbao remplacera la phrase par une
# clé de transit ». Ici sur un état LOCAL jetable, avec la clé d'essai essai-e17 ; la migration des
# états réels est une décision écrite dans docs/securite/secrets/transit.md (tous ne doivent pas
# dépendre du coffre : socle, qui recrée vault01-03, garde sa phrase).
#
# Le fournisseur demande à OpenBao une CLÉ DE DONNÉES (transit/datakey/plaintext/<clé>) : il reçoit
# la clé en clair (pour chiffrer l'état localement, AES-GCM) ET sa version chiffrée par la clé de
# transit, rangée dans les métadonnées de l'état. Pour relire : transit/decrypt/<clé>.
# Identité : BAO_ADDR et BAO_TOKEN (ou ~/.vault-token après « bao login »).
# Étapes : 1) sans le bloc « encryption », tofu apply (état en clair) ; 2) avec ce bloc (fallback
# « unencrypted »), tofu apply : l'état est réécrit chiffré ; 3) retirer le fallback.
terraform {
  required_version = "~> 1.13.0"

  encryption {
    key_provider "openbao" "essai" {
      key_name = "essai-e17"
      # address et token : pris dans BAO_ADDR et BAO_TOKEN, jamais écrits ici.
    }

    method "aes_gcm" "essai" {
      keys = key_provider.openbao.essai
    }

    # Lecture de l'ancien état en clair le temps d'UNE réécriture ; à retirer ensuite (étape 3).
    method "unencrypted" "migration" {}

    state {
      method = method.aes_gcm.essai
      fallback {
        method = method.unencrypted.migration
      }
    }
  }
}

resource "terraform_data" "essai" {
  input = "état d'essai du M25-E17"
}
