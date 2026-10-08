# dns.tf — A et PTR des nœuds dans PowerDNS (M09-E03, module de M06-E14).
# Mets à ?ref= la dernière étiquette publiée de plateforme/tofu-modules (v2.1.0 au module 06).

module "dns" {
  source   = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=v2.1.0"
  for_each = var.noeuds

  nom  = "${each.key}.${local.domaine}"
  ipv4 = each.value.mgmt
}
