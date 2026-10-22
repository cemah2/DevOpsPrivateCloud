# socle/vault01.tf — plateforme/infra, état « socle » (M25-E03, ticket PLAT-2603).
#
# vault01 : premier nœud du coffre OpenBao (stockage Raft intégré). VMID 1021, 10.10.20.21
# (PLAN §4.5), VLAN 20 INFRA, hôte PERMANENT du socle (socle v5). vault02 et vault03 (1022-1023)
# arrivent au M25-E24 sur le même modèle, kms01 (1024) au M25-E25.
# Même chemin que idp01 (M24-E04) : vm-debian enregistre l'intention dans NetBox puis crée la VM ;
# enregistrement-dns publie A et PTR.
#
# Le nom du SERVICE, openbao.par1.medisphere.internal, est celui que tous les clients utilisent
# (CLI, OpenTofu, ESO, CI). Tant que le coffre n'a qu'un nœud, il pointe directement sur vault01 ;
# au M25-E24 il passe sur la VIP keepalived 10.10.20.200 : un seul enregistrement à changer, aucun
# client à reconfigurer. Pas de PTR pour ce nom (10.10.20.21 a déjà le sien : vault01).
#
# Pré-requis NetBox : étiquette « role-coffre » (script de modélisation de M06-E05). 10.10.20.21-23
# sont réservées dans NetBox depuis M06-E05 : supprime ou importe la réservation avant l'apply (RB-060).

module "vault01" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-debian?ref=<VERSION-TOFU-MODULES>"

  nom         = "vault01"
  vmid        = 1021
  noeud       = var.noeud
  vnet        = "vinfra"
  coeurs      = 2
  memoire_mo  = 1024 # OpenBao : quelques centaines de Mo pour le lab ; le stockage Raft est en mémoire mappée
  disque_go   = 20
  stockage    = "local-nvme"
  etiquettes  = ["socle", "role-coffre"]
  description = "Coffre OpenBao, nœud 1 (Raft), M25-E03."

  # Ordre de démarrage 4 (après gw01, les DNS, ca01, ipa01 ; avant git01, idp01 et le cluster),
  # posé en root après création :
  #   root@pve01:~# qm set 1021 --startup order=4
  # Rappel : au démarrage, le coffre est SCELLÉ (Shamir) tant que trois dépositaires n'ont pas
  # donné leur part ; l'auto-descellement arrive au M25-E25.

  reseau_prefixe = "10.10.20.0/24"
  ipv4_imposee   = "10.10.20.21"
  resolveurs     = ["10.10.20.10", "10.10.20.16"]
  cle_ssh_admin  = var.cle_ssh_admin
}

module "dns_vault01" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=<VERSION-TOFU-MODULES>"

  nom  = module.vault01.fqdn
  ipv4 = module.vault01.ipv4
  ttl  = 3600
}

# Nom du service. TTL court : il changera de cible au M25-E24 (VIP), et les clients doivent suivre vite.
resource "powerdns_record" "openbao" {
  zone     = "par1.medisphere.internal."
  name     = "openbao.par1.medisphere.internal."
  type     = "A"
  ttl      = 300
  records  = [module.vault01.ipv4]
  comments = ["gere-par=opentofu (plateforme/infra), nom du coffre ; VIP 10.10.20.200 au M25-E24"]
}

output "vault01" {
  description = "Identité de vault01 (VMID, adresse, nom d'hôte) et nom du service."
  value = {
    vmid    = module.vault01.vmid
    ipv4    = module.vault01.ipv4
    fqdn    = module.vault01.fqdn
    service = "openbao.par1.medisphere.internal"
  }
}
