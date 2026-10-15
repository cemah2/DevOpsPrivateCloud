# socle/reg01.tf — plateforme/infra, état « socle » (M13-E02, ticket PLAT-1402). RB-130.
#
# reg01 : registre Harbor 2.15 de MédiSphère. VMID 1013, 10.10.20.18 (PLAN §4.5), hôte PERMANENT.
# Même chemin que dns02 (M06-E24) et lb01/lb02 (M07-E12) : vm-debian enregistre l'intention dans
# NetBox (VM, interface, adresse imposée, IP primaire) puis crée la VM ; enregistrement-dns publie
# A et PTR. Nouveauté : un disque de données (vm-debian v2.<MINEURE>, variable disques_donnees).
#
# Le nom de SERVICE est registry.par1.medisphere.internal, un CNAME vers reg01 : les clients
# (CI, Docker, Podman, containerd au M14) n'utilisent que lui. Déplacer le service = changer le
# CNAME et réémettre le certificat, sans toucher un seul client.
#
# Si 10.10.20.18 existe déjà dans NetBox (statut « reserved », modélisation de M06-E05), supprime-la
# ou importe-la avant l'apply (RB-060, étape 2).
# Pré-requis NetBox : étiquette « role-registre » (script de modélisation de M06-E05).

module "reg01" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-debian?ref=<VERSION-TOFU-MODULES>"

  nom         = "reg01"
  vmid        = 1013
  noeud       = var.noeud
  vnet        = "vinfra"
  coeurs      = 2
  memoire_mo  = 6144 # Harbor : 4 Go minimum (doc), Trivy et PostgreSQL en plus
  disque_go   = 32   # système + images Docker de Harbor (~2 Go) + journaux
  stockage    = "local-nvme"
  etiquettes  = ["socle", "role-registre"]
  description = "Registre Harbor 2.15 (registry.par1.medisphere.internal), M13-E02. RB-130."

  # Données de Harbor (blobs, base, rapports Trivy) : disque dédié sur le HDD, monté sur /data par
  # le rôle Ansible harbor. Exclu de la sauvegarde PBS de la VM : la sauvegarde de Harbor est
  # APPLICATIVE (pg_dump de harbor-db + /data + harbor.yml vers PBS, M13-E15), cohérente et
  # restaurable sur une autre machine ; 200 Gio de blobs dans chaque sauvegarde de VM ne le sont pas.
  disques_donnees = [
    { taille_go = 200, datastore = "hdd-bulk", sauvegarde = false, serie = "reg01-donnees" },
  ]

  # Ordre de démarrage 4 (après gw01, les DNS, ca01 ; avec git01), posé en root après création :
  #   root@pve01:~# qm set 1013 --startup order=4

  reseau_prefixe = "10.10.20.0/24"
  ipv4_imposee   = "10.10.20.18"
  resolveurs     = ["10.10.20.10", "10.10.20.16"]
  cle_ssh_admin  = var.cle_ssh_admin
}

module "dns_reg01" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=<VERSION-TOFU-MODULES>"

  nom  = module.reg01.fqdn
  ipv4 = module.reg01.ipv4
  ttl  = 3600
}

# Nom de service : CNAME (pas de PTR : l'adresse a déjà son nom, reg01).
# TTL court : c'est le nom qu'on déplacerait en cas de reconstruction ailleurs.
resource "powerdns_record" "registry" {
  zone     = "par1.medisphere.internal."
  name     = "registry.par1.medisphere.internal."
  type     = "CNAME"
  ttl      = 300
  records  = ["${module.reg01.fqdn}."]
  comments = ["gere-par=opentofu (plateforme/infra)"]
}

output "reg01" {
  description = "Identité de reg01 (VMID, adresse, nom d'hôte, nom de service)."
  value = {
    vmid    = module.reg01.vmid
    ipv4    = module.reg01.ipv4
    fqdn    = module.reg01.fqdn
    service = trimsuffix(powerdns_record.registry.name, ".")
  }
}
