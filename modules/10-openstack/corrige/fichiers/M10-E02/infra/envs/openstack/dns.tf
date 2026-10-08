# dns.tf — noms des nœuds (A + PTR) et des deux VIP de Kolla (A seulement) (M10-E02).
# Les VIP n'appartiennent à aucune VM : elles sont portées par keepalived (E04). Leur nom est
# un nom de SERVICE ; un PTR pointerait l'adresse vers un seul des deux noms possibles, on n'en
# pose pas (le PTR de .200/.201 n'est pas lu par Kolla ni par les clients).

module "dns_noeud" {
  source   = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=v2.1.0"
  for_each = module.noeud

  nom  = trimsuffix(each.value.fqdn, ".")
  ipv4 = each.value.ipv4
}

locals {
  vip = {
    "openstack-int.par1.medisphere.internal" = "10.10.50.200"
    "openstack.par1.medisphere.internal"     = "10.10.50.201"
  }
}

module "dns_vip" {
  source   = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=v2.1.0"
  for_each = local.vip

  nom  = each.key
  ipv4 = each.value
  ptr  = false
}

output "dns" {
  description = "Noms publiés dans PowerDNS."
  value = concat(
    [for n in module.dns_noeud : n.fqdn],
    [for v in module.dns_vip : v.fqdn],
  )
}
