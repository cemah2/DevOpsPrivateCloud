# Aucun secret ici (même principe qu'envs/lab-m06, M06-E13 et E14).
#   proxmox  : PROXMOX_VE_ENDPOINT, PROXMOX_VE_API_TOKEN (pve-tofu.env, chargé par outils/charger-acces.sh)
#   netbox   : jeton dans TF_VAR_netbox_api_token (netbox-tofu.env)
#   powerdns : clé dans TF_VAR_pdns_api_key (powerdns-api.env)
# TLS vérifié avec le magasin du système (racine MédiSphère, ancre de pve01).
# Pas de bloc ssh : la maquette n'utilise aucun snippet, l'API suffit.

provider "proxmox" {
  insecure = false
}

provider "netbox" {
  server_url           = var.netbox_url
  api_token            = var.netbox_api_token
  allow_insecure_https = false
}

# Le serveur web de PowerDNS ne parle que HTTP (écart connu, suivi depuis M06-E14).
provider "powerdns" {
  server_url = var.pdns_url
  api_key    = var.pdns_api_key
}
