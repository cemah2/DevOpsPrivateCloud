# Aucun secret ici.
#   proxmox : PROXMOX_VE_ENDPOINT, PROXMOX_VE_API_TOKEN (pve-tofu.env, M05-E03)
#   netbox  : URL ci-dessous (non secrète) ; jeton dans TF_VAR_netbox_api_token
#             (netbox-tofu.env sur adm01, variable protégée et masquée en CI).
# Pourquoi une variable et pas NETBOX_API_TOKEN ? Le fournisseur déclare server_url et
# api_token « obligatoires » : sans valeur dans le code, « tofu validate » échoue dès que la
# variable d'environnement manque, c'est-à-dire dans le job validate d'une MR, où les variables
# PROTÉGÉES ne sont pas exposées. Une variable « ephemeral » se valide sans valeur, et sa
# valeur n'est jamais écrite dans le plan ni dans l'état (OpenTofu ≥ 1.11).
# TLS : vérifié avec le magasin du système (racine MédiSphère, M06-E03 ; ancre de pve01, M02-E08).

provider "proxmox" {
  insecure = false
}

provider "netbox" {
  server_url = var.netbox_url
  # Jeton v2 (nbt_…) : le fournisseur envoie « Authorization: Bearer … » de lui-même.
  api_token            = var.netbox_api_token
  allow_insecure_https = false
}
