# app.tf — serveurs d'application de test (M05-E07), réécrits avec le module vm-debian
# (M05-E17). Remplace la ressource proxmox_virtual_environment_vm.app de main.tf.
# Les valeurs reproduisent EXACTEMENT les VMs existantes (disques raw sur local-nvme,
# présentés en SSD, arrêt net à la destruction, pas de démarrage avec l'hôte) : sinon le
# plan proposerait de les modifier, voire de les recréer.
module "app" {
  source   = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-debian?ref=v1.1.0"
  for_each = var.vms_app

  nom           = "m05-${each.key}"
  vm_id         = each.value.vmid
  noeud         = var.noeud
  pool          = var.pool
  environnement = var.environnement

  coeurs            = each.value.coeurs
  memoire_mo        = each.value.memoire_mo
  datastore_systeme = var.stockage_vm
  disque_systeme_go = 10
  disques_donnees = [
    for taille in each.value.disques_donnees : {
      taille_go = taille
      datastore = var.stockage_vm
      format    = "raw"
      ssd       = true
    }
  ]

  reseau   = { vnet = var.vnet }
  dns      = { serveurs = local.resolveurs, domaine = local.domaine }
  cles_ssh = var.cles_ssh_admin

  demarrage_auto = false
  arret_force    = true
}
