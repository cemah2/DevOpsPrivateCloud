# commun.hcl — constantes non secrètes partagées par les environnements (M05-E24).
# Lu par root.hcl (read_terragrunt_config). Ce n'est pas une unité : pas de terragrunt.hcl ici.
locals {
  noeud = "<NOEUD>" # nom du nœud Proxmox de pve01 (pvesh get /nodes)
  pool  = "lab"

  dns = {
    serveurs = ["10.10.20.10"]
    domaine  = "par1.medisphere.internal"
  }

  # Clé PUBLIQUE de admin@adm01 (~/.ssh/id_ed25519.pub) : l'équipe garde l'accès aux VMs
  # de tous les environnements, en plus de la clé propre à chaque environnement.
  cles_ssh_admin = [
    "<CLE-PUBLIQUE-ADM01>",
  ]
}
