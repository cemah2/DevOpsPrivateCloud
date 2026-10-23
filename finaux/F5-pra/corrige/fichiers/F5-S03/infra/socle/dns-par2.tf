# socle/dns-par2.tf — noms des hôtes de PAR2 (F5-S03, CHG-3503). État « socle » (s3-01), comme les
# autres enregistrements du socle : le primaire DNS est dns01 ; dns03 reçoit la zone par AXFR et la
# servira seul en PRA (promu primaire, RB-350). envs/par2 n'écrit pas dans le DNS (aucune dépendance à
# PAR1) : les enregistrements sont déclarés ICI, une fois, y compris ceux des VMs qui ne tournent qu'en
# PRA (kms01 restauré, 10.20.20.24 : le nom existe toujours, l'hôte non).
#
# Module enregistrement-dns de plateforme/tofu-modules (A + PTR dans 20.10.in-addr.arpa).

locals {
  hotes_par2 = {
    "adm02.par2.medisphere.internal"        = "10.20.20.10"
    "dns03.par2.medisphere.internal"        = "10.20.20.11"
    "s3-02.par2.medisphere.internal"        = "10.20.20.14"
    "reg02.par2.medisphere.internal"        = "10.20.20.18"
    "bao-par2.par2.medisphere.internal"     = "10.20.20.21"
    "kms01.par2.medisphere.internal"        = "10.20.20.24"
    "k8s-par2-n01.par2.medisphere.internal" = "10.20.20.50"
    "gw-par2.par2.medisphere.internal"      = "10.20.20.200"
    # hp01 sur PAR2 INFRA (passerelle) ; son nom de gestion (10.20.10.10) existe depuis le M00.
    "hp01-infra.par2.medisphere.internal" = "10.20.20.1"
  }
}

module "dns_par2" {
  source   = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=<VERSION-TOFU-MODULES>"
  for_each = local.hotes_par2

  nom  = each.key
  ipv4 = each.value
  zone = "par2.medisphere.internal."
  ttl  = 300
}

# Point d'accès de l'API de k8s-par2 (pas de VIP : nœud unique).
resource "powerdns_record" "k8s_api_par2" {
  zone     = "par2.medisphere.internal."
  name     = "k8s-api.par2.medisphere.internal."
  type     = "CNAME"
  ttl      = 300
  records  = ["k8s-par2-n01.par2.medisphere.internal."]
  comments = ["gere-par=opentofu (plateforme/infra)"]
}

# Noms des services de PAR2 : un joker vers la Gateway gw-par2 (pas d'ExternalDNS à PAR2 : il écrirait
# dans dns01, à PAR1 ; ADR-0350). Pas de PTR pour un joker.
resource "powerdns_record" "apps_par2" {
  zone     = "par2.medisphere.internal."
  name     = "*.apps.par2.medisphere.internal."
  type     = "A"
  ttl      = 300
  records  = ["10.20.20.200"]
  comments = ["gere-par=opentofu (plateforme/infra) — Gateway gw-par2 (F5-S06)"]
}
