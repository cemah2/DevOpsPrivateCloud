# tests/vm-debian.tftest.hcl — tests unitaires du module, SANS Proxmox (M05-E13).
#
# « tofu test » avec un provider simulé (mock_provider, OpenTofu >= 1.8) : rien n'est créé,
# on vérifie la logique du module (étiquettes, validations, choix de l'image, sorties).
# Lancement, depuis vm-debian/ : tofu init && tofu test
# La CI de tofu-modules (M05-E14) le lance à chaque MR.

mock_provider "proxmox" {
  # La source de données renvoie un seul template « courant », VMID 9012.
  mock_data "proxmox_virtual_environment_vms" {
    defaults = {
      vms = [{
        name      = "deb13-gold-20261005-1"
        node_name = "pve01"
        status    = "stopped"
        tags      = ["current", "debian13", "gold"]
        template  = true
        vm_id     = 9012
      }]
    }
  }
}

variables {
  nom      = "m05-test"
  vm_id    = 2051
  noeud    = "pve01"
  reseau   = { vnet = "vsandbox" }
  cles_ssh = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestTestTestTestTestTestTestTestTest00 admin@adm01"]
}

run "etiquettes_triees_et_role" {
  command = plan

  variables {
    socle      = true
    role       = "s3"
    etiquettes = ["sauvegarde", "socle"]
  }

  assert {
    condition     = jsonencode(output.etiquettes) == jsonencode(["role-s3", "sauvegarde", "socle"])
    error_message = "Étiquettes attendues triées et sans doublon : ${jsonencode(output.etiquettes)}"
  }
}

run "image_courante_par_defaut" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.vm.clone[0].vm_id == 9012 && proxmox_virtual_environment_vm.vm.clone[0].full
    error_message = "Le module doit cloner (clone complet) le template courant renvoyé par la source de données."
  }
}

run "image_imposee" {
  command = plan

  variables {
    image = { vm_id = 9010 }
  }

  assert {
    condition     = proxmox_virtual_environment_vm.vm.clone[0].vm_id == 9010
    error_message = "Un VMID d'image imposé doit l'emporter sur le template courant."
  }
}

run "ip_statique" {
  command = plan

  variables {
    reseau = { vnet = "vinfra", ipv4 = "10.10.20.14/24", passerelle = "10.10.20.1" }
  }

  assert {
    condition     = output.ipv4 == "10.10.20.14"
    error_message = "La sortie ipv4 doit donner l'adresse statique sans masque."
  }
}

run "statique_sans_passerelle_refusee" {
  command = plan

  variables {
    reseau = { vnet = "vinfra", ipv4 = "10.10.20.14/24" }
  }

  expect_failures = [var.reseau]
}

run "vmid_hors_plage_refuse" {
  command = plan

  variables {
    vm_id = 9005
  }

  expect_failures = [var.vm_id]
}

run "disques_donnees_numerotes" {
  command = plan

  variables {
    disques_donnees = [{ taille_go = 100 }, { taille_go = 10, datastore = "ssd-lab" }]
  }

  assert {
    condition     = length(proxmox_virtual_environment_vm.vm.disk) == 3 && proxmox_virtual_environment_vm.vm.disk[2].interface == "scsi2"
    error_message = "Les disques de données doivent suivre le disque système : scsi1, scsi2…"
  }
}

run "sans_acces_refuse" {
  command = plan

  variables {
    cles_ssh = []
  }

  expect_failures = [proxmox_virtual_environment_vm.vm]
}
