# dns.tf — noms des adresses fixes du VLAN 99 (A + PTR), M07-E03.
# Les VMs en DHCP sont nommées par Kea (mise à jour dynamique, M06-E17) : rien à faire ici.
# Module du dépôt tofu-modules, étiquette de version (jamais une branche, M05-E14).

module "dns" {
  source   = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=v2.1.0"
  for_each = local.adresses_fixes

  nom  = "${each.key}.par1.medisphere.internal"
  ipv4 = each.value
}

# La VIP de démonstration de M07-E08 (VRID 199) : un nom pour un service, pas pour une VM.
module "dns_web_demo" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=v2.1.0"

  nom  = "web-demo.par1.medisphere.internal"
  ipv4 = "10.10.99.240"
}
