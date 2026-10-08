# versions.tf — module openstack-env-app (M10-E31, DEV-1157). Le module ne configure PAS le
# provider : c'est la configuration racine (le dépôt de l'équipe) qui l'authentifie.
terraform {
  required_version = ">= 1.13.0"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.4"
    }
  }
}
