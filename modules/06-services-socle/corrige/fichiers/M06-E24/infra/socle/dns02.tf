# socle/dns02.tf — plateforme/infra, état « socle » (M06-E24, ticket PLAT-750). RB-060, étape 2.
#
# dns02 : DNS secondaire (PowerDNS Authoritative secondaire + Recursor) et Kea de secours.
# VMID 1008, 10.10.20.16 (PLAN §4.5). Le module vm-debian v2 (M06-E13) enregistre l'intention
# dans NetBox AVANT de créer la VM (VM, interface, adresse IMPOSÉE, adresse primaire), puis le
# module enregistrement-dns (M06-E14) crée A et PTR à partir de l'adresse que NetBox porte.
# La configuration de l'invité est le travail d'Ansible (playbooks/dns01.yml, groupe role_dns).
#
# Si 10.10.20.16 existait déjà dans NetBox (statut « reserved », modélisation de M06-E05),
# supprime-la ou importe-la avant l'apply (RB-060, étape 2) : sinon doublon et échec.

module "dns02" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-debian?ref=v2.1.0"

  nom         = "dns02"
  vmid        = 1008
  noeud       = var.noeud
  vnet        = "vinfra"
  coeurs      = 1
  memoire_mo  = 2048
  disque_go   = 10
  stockage    = "local-nvme"
  etiquettes  = ["socle", "role-dns"]
  description = "DNS secondaire et DHCP de secours (M06-E24, M06-E25)."

  # Même ordre que dns01 : après gw01 (1), avant adm01 (3) et la forge (4, 5).
  ordre_demarrage = 2

  # Adresse FIXÉE par le PLAN : enregistrée telle quelle dans NetBox, pas allouée dans la plage.
  reseau_prefixe = "10.10.20.0/24"
  ipv4_imposee   = "10.10.20.16"

  # dns02 s'interroge d'abord lui-même (son récurseur relaie les zones internes vers les deux
  # serveurs faisant autorité), puis dns01.
  resolveurs    = ["10.10.20.16", "10.10.20.10"]
  cle_ssh_admin = var.cle_ssh_admin
}

module "dns_dns02" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=v2.1.0"

  nom  = module.dns02.fqdn
  ipv4 = module.dns02.ipv4
  ttl  = 3600 # hôte permanent : TTL long
}

output "dns02" {
  description = "Identité de dns02 (VMID, adresse, nom)."
  value = {
    vmid = module.dns02.vmid
    ipv4 = module.dns02.ipv4
    fqdn = module.dns02.fqdn
  }
}
