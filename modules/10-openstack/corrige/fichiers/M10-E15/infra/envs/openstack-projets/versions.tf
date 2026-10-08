# envs/openstack-projets — socle des projets d'équipe sur OpenStack PAR1 (M10-E15, PLAT-1125).
# Quotas, réseau, sous-réseau, routeur et groupe de sécurité d'administration de chaque projet.
# Les projets eux-mêmes et les rôles restent créés par RB-100 (M10-E22).

terraform {
  required_version = ">= 1.13.0"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.4"
    }
  }

  # Même backend que les autres états (M05-E11, E12) ; une clé par configuration racine.
  backend "s3" {
    bucket                      = "tofu-state"
    key                         = "envs/openstack-projets/terraform.tfstate"
    region                      = "us-east-1"
    endpoints                   = { s3 = "https://s3-01.par1.medisphere.internal:8333" }
    use_path_style              = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    use_lockfile                = true
  }
}
