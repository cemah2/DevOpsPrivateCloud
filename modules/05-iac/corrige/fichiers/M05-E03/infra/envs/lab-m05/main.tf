# main.tf — premier plan : lire la version de Proxmox VE, sans rien créer (M05-E03).
#
# La source de données « proxmox_version » appelle GET /api2/json/version : elle prouve
# que l'adresse, le TLS et le jeton fonctionnent. N'importe quel utilisateur authentifié
# peut lire cet appel : elle ne prouve RIEN sur les privilèges du jeton.
data "proxmox_version" "pve01" {}

output "version_pve" {
  description = "Version de Proxmox VE lue par l'API (preuve que la connexion fonctionne)."
  value       = data.proxmox_version.pve01.version
}
