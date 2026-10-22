# observabilite-grafana/versions.tf — configuration racine « observabilite-grafana » de
# plateforme/infra (M21-E17, PLAT-2217).
#
# Les OBJETS d'organisation de Grafana (dossiers, équipes, permissions), séparés du déploiement de
# Grafana (Argo CD, chart) et des tableaux (fichiers JSON provisionnés par le sidecar) :
#   - ce qui CONTIENT (dossiers, UID fixes) et qui A LE DROIT (équipes, permissions) : ici ;
#   - ce qui est AFFICHÉ (tableaux) : plateforme/observabilite/tableaux/.
# Appliqué depuis adm01 (MGMT joint la Gateway gw-par1) avec le jeton du compte de service
# « tofu » de Grafana : TF_VAR_grafana_jeton="$(cat ~/.config/workbook/grafana-tofu.token)".
# Le pipeline de plateforme/infra tourne sur runner01 (VLAN 20), qui ne joint pas 10.10.41.10:443 :
# l'appliquer par la CI demanderait d'ouvrir ce flux (non fait dans ce module).
terraform {
  required_version = "~> 1.13.0"

  required_providers {
    grafana = {
      source = "grafana/grafana"
      # Version de référence : 4.50.x (dernière publiée au 22/10/2026, registres OpenTofu et Terraform).
      # « ~> 4.50 » accepte les mineures suivantes sans passer à une version majeure. tofu init écrit la version retenue dans .terraform.lock.hcl
      # (à committer) : c'est elle qui fait foi.
      version = "~> 4.50"
    }
  }

  backend "s3" {
    bucket                      = "tofu-state"
    key                         = "observabilite-grafana/terraform.tfstate"
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
