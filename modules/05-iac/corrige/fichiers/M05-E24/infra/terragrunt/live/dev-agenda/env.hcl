# env.hcl — environnement de test de MédiAgenda (ticket DEV de Julien Petit, M05-E24).
# Tout ce qui distingue cet environnement d'un autre tient ici. Copier ce dossier, changer
# ces valeurs : c'est tout ce que coûte un nouvel environnement.
locals {
  environnement = "dev-agenda"

  # VMID réservés au palier 3 du module (2057-2059), DHCP sur vsandbox.
  vms = {
    "agenda-api" = { vm_id = 2057, coeurs = 1, memoire_mo = 1024 }
    "agenda-bdd" = { vm_id = 2058, coeurs = 1, memoire_mo = 1536 }
  }
}
