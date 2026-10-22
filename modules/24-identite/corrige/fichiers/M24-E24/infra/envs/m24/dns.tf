# dns.tf — noms des VMs à adresse fixe (A + PTR), comme envs/m20.
# idp02 a besoin de son nom : certificat ACME (défi HTTP-01 de ca01) et vérification TLS par HAProxy.
module "dns_hote" {
  source   = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=v2.1.0"
  for_each = module.hote

  nom  = trimsuffix(each.value.fqdn, ".")
  ipv4 = each.value.ipv4
}

output "dns" {
  description = "Noms publiés dans PowerDNS."
  value       = [for n in module.dns_hote : n.fqdn]
}
