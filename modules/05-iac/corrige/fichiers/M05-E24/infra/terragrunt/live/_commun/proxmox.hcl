# _commun/proxmox.hcl — bloc provider Proxmox, inclus par les unités qui gèrent des VMs (M05-E24).
#
# Inclus en plus de root.hcl : include "proxmox" { path = ".../_commun/proxmox.hcl" }.
# Le dossier _commun ne contient pas de terragrunt.hcl : ce n'est pas une unité, « run --all »
# l'ignore.
#
# Pas de secret : endpoint et jeton viennent de PROXMOX_VE_ENDPOINT / PROXMOX_VE_API_TOKEN.
# Pas de bloc ssh : ces unités ne déposent aucun snippet (seule opération du provider qui
# exige SSH vers le nœud, voir M05-E19).
generate "provider_proxmox" {
  path      = "provider-proxmox.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOT
    # Généré par Terragrunt (live/_commun/proxmox.hcl) — ne pas modifier.
    provider "proxmox" {
      insecure = false
    }
  EOT
}
