# ~/m05/e27/main.tf — expérience « où va la phrase ? » (M05-E27, étape 2). État LOCAL jetable.
#
#   A. Phrase par variable OpenTofu : décommenter le key_provider ci-dessous, puis
#        unset TF_ENCRYPTION; export TF_VAR_phrase_essai='phrase-de-demonstration-01'
#        tofu init && tofu plan -out=a.tfplan && tofu show -json a.tfplan | jq .variables
#      → phrase_essai ET secret_essai y sont EN CLAIR (« sensitive » ne change rien).
#   B. Phrase par TF_ENCRYPTION : recommenter le key_provider, rm -rf .terraform* *.tfplan, puis
#        export TF_ENCRYPTION='key_provider "pbkdf2" "etat" { passphrase = "phrase-de-demonstration-01" }'
#        tofu init && tofu plan -out=b.tfplan && tofu show -json b.tfplan | jq .variables
#      → phrase_essai vaut null ; secret_essai est toujours en clair : un plan est un secret.
#
# Ce dossier est jetable : rm -rf ~/m05/e27 à la fin (il contient des états et des plans).

variable "phrase_essai" {
  description = "Phrase de chiffrement passée en variable (variante A seulement)."
  type        = string
  sensitive   = true
  default     = null
}

variable "secret_essai" {
  description = "Un secret ordinaire : où finit-il ?"
  type        = string
  sensitive   = true
  default     = "valeur-secrete-de-demonstration"
}

resource "terraform_data" "essai" {
  input = var.secret_essai
}

terraform {
  encryption {
    # Variante A : décommenter, et ne PAS définir TF_ENCRYPTION.
    # key_provider "pbkdf2" "etat" {
    #   passphrase = var.phrase_essai
    # }
    method "aes_gcm" "etat" {
      keys = key_provider.pbkdf2.etat
    }
    state {
      method = method.aes_gcm.etat
    }
    plan {
      method = method.aes_gcm.etat
    }
  }
}
