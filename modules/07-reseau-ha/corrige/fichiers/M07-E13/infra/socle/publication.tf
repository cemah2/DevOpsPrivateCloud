# socle/publication.tf — plateforme/infra, état « socle » (M07-E13, ticket PLAT-823).
#
# Noms PUBLIÉS : ils désignent un service, pas une machine, et pointent vers la VIP des
# répartiteurs. Enregistrements A sans PTR (le PTR de 10.10.70.200 est lb.par1.medisphere.internal,
# repartiteurs.tf : une adresse n'a qu'un nom inverse). Un CNAME vers lb.par1… conviendrait aussi ;
# le A garde la résolution en une étape et le même module que le reste du socle.

locals {
  noms_publies = ["gitlab", "netbox"]
}

module "dns_publication" {
  source   = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=v2.1.0"
  for_each = toset(local.noms_publies)

  nom  = "${each.key}.par1.medisphere.internal"
  ipv4 = local.vip_lb # repartiteurs.tf
  ttl  = 300
  ptr  = false
}

output "noms_publies" {
  description = "Services publiés par les répartiteurs."
  value       = [for m in module.dns_publication : m.fqdn]
}
