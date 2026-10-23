# envs/par2 — VMs du site de repli PAR2 sur l'hyperviseur de hp01 (F5-S03, CHG-3503 ; ADR-0350).
#
# Règle d'or : cette configuration ne dépend d'AUCUN service de PAR1 pour un plan ou un apply.
#   - état : compartiment tofu-par2 de s3-02 (PAR2), pas tofu-state de s3-01 ;
#   - module : local (modules/vm-par2), pas plateforme/tofu-modules téléchargé depuis git01 ;
#   - pas de NetBox ni de PowerDNS (à PAR1) : les noms de PAR2 sont publiés par l'état « socle »
#     (socle/dns-par2.tf), transférés à dns03 par AXFR ;
#   - fournisseur : registre public (Internet par hp01) ou miroir de fournisseurs sur adm02
#     (tofu providers mirror, RB-353 §6).
#
# AMORÇAGE (RB-353 §5) : s3-02 porte l'état qui le décrit. Premier apply avec le fichier
# amorcage/backend-local.tf.exemple copié en backend_override.tf (état LOCAL, jamais commité), ciblé sur
# adm02, dns03, s3-02 ; configuration de s3-02 (Ansible) ; puis suppression de backend_override.tf et
# « tofu init -migrate-state » vers le backend ci-dessous.

terraform {
  required_version = ">= 1.13.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.116.0"
    }
  }

  backend "s3" {
    bucket                      = "tofu-par2"
    key                         = "envs/par2/terraform.tfstate"
    region                      = "us-east-1"
    endpoints                   = { s3 = "https://s3-02.par2.medisphere.internal:8333" }
    use_path_style              = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    use_lockfile                = true
  }
}

# Accès : PROXMOX_VE_ENDPOINT=https://10.20.10.10:8006/ et PROXMOX_VE_API_TOKEN=wb-tofu@pve!par2=…
# (~/.config/workbook/pve-par2.env sur adm01 et adm02, depuis Ansible Vault « critique »).
# Certificat de l'API : celui de hp01 (autorité propre de PVE) ; son certificat racine est ajouté au
# magasin système de adm01/adm02 (comme pve01 au M03) : pas d'« insecure ».
provider "proxmox" {}
