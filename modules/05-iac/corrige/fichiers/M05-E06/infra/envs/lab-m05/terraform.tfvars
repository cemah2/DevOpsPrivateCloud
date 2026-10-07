# terraform.tfvars — valeurs de l'environnement lab-m05 (M05-E06).
# VERSIONNÉ : rien de secret ici (les accès à l'API viennent de l'environnement, PROXMOX_VE_*).

noeud      = "pve01" # <NOEUD> : hostname réel de pve01
image_vmid = 9012    # <VMID-CURRENT> : image dorée Debian 13 étiquetée « current » (qm list)

# Clé(s) PUBLIQUE(S) du compte admin : contenu de ~/.ssh/id_ed25519.pub sur adm01.
cles_ssh_admin = [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA_REMPLACE_PAR_LA_CLE_PUBLIQUE_D_ADM01 admin@adm01",
]

vm_essai = {
  vmid       = 2050
  nom        = "m05-essai"
  memoire_mo = 2048
}
