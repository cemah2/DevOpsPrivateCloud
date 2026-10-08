# Aucun secret ici (mêmes conventions que envs/lab-m06, M06-E13/E14).
#   proxmox  : PROXMOX_VE_ENDPOINT, PROXMOX_VE_API_TOKEN (pve-tofu.env, M05-E03)
#   netbox   : jeton dans TF_VAR_netbox_api_token (netbox-tofu.env ; variable protégée en CI)
#   powerdns : clé dans TF_VAR_pdns_api_key (powerdns-api.env ; variable protégée en CI)
# TLS : vérifié avec le magasin du système (racine MédiSphère, ancre de pve01).

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
