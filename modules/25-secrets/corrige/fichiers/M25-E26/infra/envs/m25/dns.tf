# dns.tf — noms des VMs temporaires (A + PTR) : certificat de bao-essai (step, provisioner admin),
# vérification TLS depuis adm01 et kms01 (seal transit de bao-restauration : nom vérifié).
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
