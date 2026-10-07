# env.hcl — préproduction de MédiAgenda (DEV-679, M05-E34).
# Répétition générale de la mise en production : deux frontaux, une base. Environnement jetable,
# détruit par « terragrunt run --all destroy » après la répétition.
locals {
  environnement = "preprod-agenda"

  vms = {
    "pp-api1" = { vm_id = 2057, coeurs = 1, memoire_mo = 1024, etiquettes = ["app-api"] }
    "pp-api2" = { vm_id = 2058, coeurs = 1, memoire_mo = 1024, etiquettes = ["app-api"] }
    "pp-bdd"  = {
      vm_id      = 2059
      coeurs     = 2
      memoire_mo = 2048
      etiquettes = ["app-bdd"]
      # Données de la base : stockage rapide, raw (LVM-thin ou ZFS n'acceptent pas qcow2).
      disques_donnees = [{ taille_go = 10, datastore = "local-nvme", format = "raw" }]
    }
  }
}
