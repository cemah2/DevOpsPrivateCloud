# Aucun secret ici (même schéma que envs/lab-m06, M06-E13) :
#   proxmox : PROXMOX_VE_ENDPOINT, PROXMOX_VE_API_TOKEN (pve-tofu.env)
#   netbox  : jeton dans TF_VAR_netbox_api_token (netbox-tofu.env), variable éphémère
# TLS vérifié avec le magasin du système (racine MédiSphère, M06-E03).
# Pas de PowerDNS : les VMs de ce module prennent leur adresse et leur nom auprès de Kea (DDNS).

provider "proxmox" {
  insecure = false
}

provider "netbox" {
  server_url           = var.netbox_url
  api_token            = var.netbox_api_token
  allow_insecure_https = false
}
