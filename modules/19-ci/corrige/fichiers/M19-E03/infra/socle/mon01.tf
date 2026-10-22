# socle/mon01.tf — plateforme/infra, état « socle » (M19-E03, ticket PLAT-2003).
#
# mon01 : messagerie du lab (Mailpit, M19) puis supervision « témoin » hors cluster (M21).
# VMID 1014, 10.10.20.19 (PLAN §4.5), VLAN 20 INFRA, hôte PERMANENT du socle (socle v4).
# Même chemin que reg01 (M13-E02) : vm-debian enregistre l'intention dans NetBox (VM, interface,
# adresse imposée, IP primaire) puis crée la VM ; enregistrement-dns publie A et PTR.
#
# Si 10.10.20.19 existe déjà dans NetBox (statut « reserved », modélisation de M06-E05),
# supprime-la ou importe-la avant l'apply (RB-060, étape 2).
# Pré-requis NetBox : étiquette « role-supervision » (script de modélisation de M06-E05 : à
# ajouter à son fichier de données si elle n'existe pas encore).

module "mon01" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-debian?ref=<VERSION-TOFU-MODULES>"

  nom         = "mon01"
  vmid        = 1014
  noeud       = var.noeud
  vnet        = "vinfra"
  coeurs      = 2
  memoire_mo  = 3072 # Mailpit (≈ 50 Mo) au M19 ; Prometheus et Alertmanager « témoins » au M21
  disque_go   = 32   # système, base de Mailpit (5000 messages au plus), TSDB du témoin au M21
  stockage    = "local-nvme"
  etiquettes  = ["socle", "role-supervision"]
  description = "Messagerie du lab (Mailpit, smtp.par1.medisphere.internal), M19-E03 ; supervision témoin au M21."

  # Ordre de démarrage 5 (après git01 et reg01), posé en root après création :
  #   root@pve01:~# qm set 1014 --startup order=5

  reseau_prefixe = "10.10.20.0/24"
  ipv4_imposee   = "10.10.20.19"
  resolveurs     = ["10.10.20.10", "10.10.20.16"]
  cle_ssh_admin  = var.cle_ssh_admin
}

module "dns_mon01" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=<VERSION-TOFU-MODULES>"

  nom  = module.mon01.fqdn
  ipv4 = module.mon01.ipv4
  ttl  = 3600
}

# Nom de SERVICE de la messagerie : CNAME (pas de PTR : l'adresse a déjà son nom, mon01).
# Tous les clients (GitLab, Alertmanager, Argo CD…) n'utilisent que lui ; le certificat de Mailpit
# le porte en SAN. TTL court : c'est le nom qu'on déplacerait.
resource "powerdns_record" "smtp" {
  zone     = "par1.medisphere.internal."
  name     = "smtp.par1.medisphere.internal."
  type     = "CNAME"
  ttl      = 300
  records  = ["${module.mon01.fqdn}."]
  comments = ["gere-par=opentofu (plateforme/infra)"]
}

output "mon01" {
  description = "Identité de mon01 (VMID, adresse, nom d'hôte, nom du service SMTP)."
  value = {
    vmid = module.mon01.vmid
    ipv4 = module.mon01.ipv4
    fqdn = module.mon01.fqdn
    smtp = trimsuffix(powerdns_record.smtp.name, ".")
  }
}
