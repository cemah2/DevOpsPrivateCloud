# M06-E14 — nouveaux fichiers de envs/lab-m06 (à côté de ceux de M06-E13) :
# le nom DNS est créé avec la VM, à partir de l'adresse que NetBox lui a donnée.
# v2.1.0 : étiquette du dépôt tofu-modules qui ajoute ce module (feat, semantic-release).

module "dns_ipam01" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=v2.1.0"

  nom  = module.ipam01.fqdn
  ipv4 = module.ipam01.ipv4
}

output "dns_ipam01" {
  value = module.dns_ipam01.fqdn
}
