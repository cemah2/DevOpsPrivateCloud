# socle/runner02.tf — plateforme/infra, état « socle » (M12-E20, ticket PLAT-1320).
#
# runner02 : GitLab Runner à exécuteur docker du SOCLE (hôte permanent, pas un hôte du module 12).
# VMID 1012, 10.10.20.17 (PLAN §4.5), VLAN 20 INFRA, 2 vCPU, 4 Go. Même chemin que dns02 (M06-E24),
# lb01/lb02 (M07-E12) et reg01 (M13-E02) : vm-debian enregistre l'intention dans NetBox (VM,
# interface, adresse imposée, IP primaire) puis crée la VM ; enregistrement-dns publie A et PTR.
#
# Si 10.10.20.17 existe déjà dans NetBox (statut « reserved », modélisation de M06-E05), supprime-la
# ou importe-la avant l'apply (RB-060, étape 2). Pré-requis NetBox : étiquette « role-runner »
# (existe depuis runner01).

module "runner02" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-debian?ref=<VERSION-TOFU-MODULES>"

  nom         = "runner02"
  vmid        = 1012
  noeud       = var.noeud
  vnet        = "vinfra"
  coeurs      = 2
  memoire_mo  = 4096 # deux jobs simultanés (1,5 Go chacun au plus, config.toml) + Docker
  disque_go   = 64   # images des jobs, cache de BuildKit éphémère, volumes /cache
  stockage    = "local-nvme"
  etiquettes  = ["socle", "role-runner"]
  description = "GitLab Runner, exécuteur docker, jamais privilégié (M12-E20). Constructions par BuildKit sans privilège (M12-E21)."

  # Ordre de démarrage 5 (comme runner01 : après git01), posé en root après création :
  #   root@pve01:~# qm set 1012 --startup order=5

  reseau_prefixe = "10.10.20.0/24"
  ipv4_imposee   = "10.10.20.17"
  resolveurs     = ["10.10.20.10", "10.10.20.16"]
  cle_ssh_admin  = var.cle_ssh_admin
}

module "dns_runner02" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=<VERSION-TOFU-MODULES>"

  nom  = module.runner02.fqdn
  ipv4 = module.runner02.ipv4
  ttl  = 3600
}

output "runner02" {
  description = "Identité de runner02 (VMID, adresse, nom)."
  value = {
    vmid = module.runner02.vmid
    ipv4 = module.runner02.ipv4
    fqdn = module.runner02.fqdn
  }
}
