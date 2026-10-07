# providers.tf — connexion à l'API de pve01 (M05-E10, identique à envs/lab-m05).
#
# Aucun secret ici : PROXMOX_VE_ENDPOINT et PROXMOX_VE_API_TOKEN viennent de
# ~/.config/workbook/pve-tofu.env (M05-E03). TLS vérifié avec le magasin système.
# Pas de bloc ssh : l'état socle ne gère aucun snippet (choix de M05-E19), il n'a donc
# besoin que de l'API, depuis adm01 comme depuis runner01 (pipeline, M05-E26).
provider "proxmox" {
  insecure = false
}
