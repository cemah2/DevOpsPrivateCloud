# Aucun secret ici (même schéma que envs/m27, socle) :
#   proxmox  : PROXMOX_VE_ENDPOINT, PROXMOX_VE_API_TOKEN (pve-tofu.env)
#   netbox   : TF_VAR_netbox_api_token (netbox-tofu.env), variable éphémère
#   powerdns : TF_VAR_pdns_api_key (powerdns-api.env), variable éphémère
# Chiffrement de l'état : chiffrement.tf, copie conforme de celui des autres racines (M05-E27).
provider "proxmox" {
  insecure = false
}

provider "netbox" {
  server_url           = var.netbox_url
  api_token            = var.netbox_api_token
  allow_insecure_https = false
}

provider "powerdns" {
  server_url = var.pdns_url
  api_key    = var.pdns_api_key
}
