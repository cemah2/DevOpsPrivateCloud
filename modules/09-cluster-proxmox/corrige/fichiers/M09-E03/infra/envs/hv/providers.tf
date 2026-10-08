# providers.tf — accès aux API, sans aucun secret (M09-E03).
#
#   proxmox  : API de pve01 (l'hyperviseur PHYSIQUE qui porte les nœuds imbriqués), jeton
#              wb-tofu@pve!tofu : PROXMOX_VE_ENDPOINT, PROXMOX_VE_API_TOKEN (pve-tofu.env, M05-E03).
#              Le cluster imbriqué hv-par1 a sa PROPRE API : elle n'est pas pilotée ici (M09-E18).
#   netbox   : jeton de svc-automatisation, TF_VAR_netbox_api_token (netbox-tofu.env, M06-E13).
#   powerdns : clé d'API, TF_VAR_pdns_api_key (powerdns-api.env, M06-E14).
# TLS vérifié partout (magasin du système : ancre de pve01, racine MédiSphère).

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
