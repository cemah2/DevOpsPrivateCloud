# socle/idp01.tf — plateforme/infra, état « socle » (M24-E04, ticket PLAT-2504).
#
# idp01 : fournisseur d'identité Keycloak (royaume medisphere), base PostgreSQL 17 locale.
# VMID 1030, 10.10.20.30 (PLAN §4.5), VLAN 20 INFRA, hôte PERMANENT du socle (socle v5).
# Même chemin que mon01 (M19-E03) : vm-debian enregistre l'intention dans NetBox (VM, interface,
# adresse imposée, IP primaire) puis crée la VM ; enregistrement-dns publie A et PTR.
# Le nom PUBLIC du service (sso.par1.medisphere.internal) pointe vers la VIP des répartiteurs :
# il est dans publication.tf (M07-E13), pas ici.
#
# Pré-requis NetBox : étiquette « role-idp » (script de modélisation de M06-E05). Si 10.10.20.30
# existe déjà dans NetBox (réservée en M06-E05), supprime-la ou importe-la avant l'apply (RB-060).

module "idp01" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-debian?ref=<VERSION-TOFU-MODULES>"

  nom         = "idp01"
  vmid        = 1030
  noeud       = var.noeud
  vnet        = "vinfra"
  coeurs      = 2
  memoire_mo  = 3072 # Keycloak (tas Java de 1 Gio au plus, + métaspace et natif) + PostgreSQL 17
  disque_go   = 32
  stockage    = "local-nvme"
  etiquettes  = ["socle", "role-idp"]
  description = "Fournisseur d'identité Keycloak (sso.par1.medisphere.internal), M24-E04."

  # Ordre de démarrage 6 (après ipa01, git01, reg01, mon01), posé en root après création :
  #   root@pve01:~# qm set 1030 --startup order=6

  reseau_prefixe = "10.10.20.0/24"
  ipv4_imposee   = "10.10.20.30"
  resolveurs     = ["10.10.20.10", "10.10.20.16"]
  cle_ssh_admin  = var.cle_ssh_admin
}

module "dns_idp01" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=<VERSION-TOFU-MODULES>"

  nom  = module.idp01.fqdn
  ipv4 = module.idp01.ipv4
  ttl  = 3600
}

output "idp01" {
  description = "Identité de idp01 (VMID, adresse, nom d'hôte)."
  value = {
    vmid = module.idp01.vmid
    ipv4 = module.idp01.ipv4
    fqdn = module.idp01.fqdn
  }
}
