# versions.tf — dépôt mediagenda/recette-infra (équipe MédiAgenda), M10-E31 (DEV-1157).
# État : compartiment DÉDIÉ à l'équipe sur s3-01 (identité S3 « tofu-mediagenda » limitée à ce
# compartiment) ; les identifiants de la plateforme ne sont jamais donnés à l'équipe.
terraform {
  required_version = "~> 1.13.0"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.4"
    }
  }

  backend "s3" {
    bucket = "tofu-state-mediagenda"
    key    = "recette/terraform.tfstate"

    region                      = "us-east-1"
    endpoints                   = { s3 = "https://s3-01.par1.medisphere.internal:8333" }
    use_path_style              = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true

    use_lockfile = true
  }

  # Chiffrement de l'état et des plans (comme M05-E27) ; fournisseur de clé dans TF_ENCRYPTION
  # (variable protégée et masquée du projet GitLab de l'équipe, phrase PROPRE à l'équipe).
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
  }
}
