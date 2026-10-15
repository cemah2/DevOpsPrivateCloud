# registre/versions.tf — configuration racine « registre » de plateforme/infra (M13-E03, PLAT-1403).
#
# Les OBJETS de Harbor (projets, utilisateurs, membres, robots, caches, politiques), séparés de la
# VM reg01 (état « socle ») : rejouer ou détruire la configuration de Harbor ne peut jamais toucher
# une VM, et un « plan » du socle ne dépend pas de la disponibilité de Harbor.
# Appliqué par le pipeline de plateforme/infra (runner01, même VLAN que reg01), avec les variables
# protégées et masquées HARBOR_URL, HARBOR_USERNAME (admin), HARBOR_PASSWORD (Vault critique).
terraform {
  required_version = "~> 1.13.0"

  required_providers {
    harbor = {
      source = "goharbor/harbor"
      # 3.12.x : 2.15 pris en charge (ca_certificate des registres, proxy_cache_local_on_not_found).
      version = "~> 3.12.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  backend "s3" {
    bucket                      = "tofu-state"
    key                         = "registre/terraform.tfstate"
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
