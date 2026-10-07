# env.hcl — environnement de test de MédiDoc (M05-E24).
locals {
  environnement = "dev-doc"

  vms = {
    "doc-api" = { vm_id = 2059, coeurs = 1, memoire_mo = 1024 }
  }
}
