# providers.tf — connexion à l'API de pve01 (M05-E03).
#
# Aucun secret ici. Le provider lit dans l'environnement (fichier
# ~/.config/workbook/pve-tofu.env sur adm01, variables CI protégées et masquées ensuite) :
#   PROXMOX_VE_ENDPOINT   https://<IP-PVE01>:8006/   (sans /api2/json)
#   PROXMOX_VE_API_TOKEN  wb-tofu@pve!tofu=<SECRET>
#
# TLS vérifié : le provider (Go) utilise le magasin de certificats du système, qui
# contient l'autorité de pve01 depuis M03-E02 (/usr/local/share/ca-certificates/).
# Pas de bloc ssh : aucune ressource du palier 1 n'en a besoin (seuls les snippets,
# M05-E19, passent par SSH).
provider "proxmox" {
  insecure = false # valeur par défaut, écrite pour qu'un relecteur n'ait pas à le deviner
}
