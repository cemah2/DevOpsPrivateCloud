# terraform.tfvars — recette-m05 (versionné, rien de secret).
noeud = "<NOEUD>"

cles_ssh_admin = [
  "ssh-ed25519 <CLE-PUBLIQUE-ADM01> admin@adm01",
]

vms = {
  api = { vm_id = 2055 }
  bdd = { vm_id = 2056, donnees_go = 10 }
}
