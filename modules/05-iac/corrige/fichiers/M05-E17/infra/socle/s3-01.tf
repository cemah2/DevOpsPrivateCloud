# s3-01.tf — stockage objet S3 du socle, par le module vm-debian (M05-E17).
# Remplace la ressource directe de M05-E10 ; le bloc moved de refactorisation.tf dit à
# OpenTofu que c'est le MÊME objet, à une nouvelle adresse : aucune recréation.
module "s3_01" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-debian?ref=v1.1.0"

  nom         = "s3-01"
  vm_id       = 1006
  noeud       = var.noeud
  pool        = var.pool
  description = "Stockage objet S3 du socle (SeaweedFS), état OpenTofu."
  socle       = true
  role        = "s3"

  coeurs            = 2
  memoire_mo        = 2048
  datastore_systeme = var.datastore_systeme
  disque_systeme_go = 20
  disques_donnees = [
    { taille_go = 100, datastore = var.datastore_donnees, format = "qcow2" },
  ]

  reseau = {
    vnet       = "vinfra"
    ipv4       = "10.10.20.14/24"
    passerelle = "10.10.20.1"
  }
  dns      = var.dns
  cles_ssh = var.cles_ssh_admin

  demarrage_auto  = true
  ordre_demarrage = 4
  # Le module ne peut pas porter prevent_destroy (valeur fixe d'un bloc lifecycle) :
  # Proxmox refuse la suppression tant que ce drapeau est posé.
  protection = true
}
