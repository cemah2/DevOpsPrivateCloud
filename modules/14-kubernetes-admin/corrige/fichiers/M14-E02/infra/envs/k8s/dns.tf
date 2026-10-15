# dns.tf — noms des nœuds (A + PTR), M14-E02. Le nom de la VIP d'API arrive en E03 (api.tf).

module "dns_noeud" {
  source   = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=v2.1.0"
  for_each = module.noeud

  nom  = trimsuffix(each.value.fqdn, ".")
  ipv4 = each.value.ipv4
}

output "dns" {
  description = "Noms publiés dans PowerDNS."
  value       = [for n in module.dns_noeud : n.fqdn]
}
