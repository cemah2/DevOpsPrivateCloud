# terraform.tfvars — valeurs de l'environnement lab-m05 (M05-E06, E07, E08).
# VERSIONNÉ : rien de secret ici (les accès à l'API viennent de l'environnement, PROXMOX_VE_*).

noeud = "pve01" # <NOEUD> : hostname réel de pve01
# L'image à cloner n'est plus ici : elle est cherchée dans Proxmox (data.tf, M05-E08).

# Clé(s) PUBLIQUE(S) du compte admin : contenu de ~/.ssh/id_ed25519.pub sur adm01.
cles_ssh_admin = [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA_REMPLACE_PAR_LA_CLE_PUBLIQUE_D_ADM01 admin@adm01",
]

vm_essai = {
  vmid       = 2050
  nom        = "m05-essai"
  memoire_mo = 2048
}

# DEV-607 : trois serveurs d'application de test pour l'équipe de Julien.
vms_app = {
  app01 = { vmid = 2051 }
  app02 = { vmid = 2052, disques_donnees = [2] }
  app03 = { vmid = 2053, disques_donnees = [2, 3] }
}
