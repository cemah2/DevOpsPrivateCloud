# terraform.tfvars — valeurs NON secrètes de l'état socle (versionné).
# <NOEUD> : nom du nœud Proxmox de pve01 ; <CLE-PUBLIQUE-ADM01> : contenu de ~/.ssh/id_ed25519.pub
# sur adm01 (une clé publique se versionne ; même valeur que ms_cles_admin côté Ansible).
noeud = "<NOEUD>"

cles_ssh_admin = [
  "ssh-ed25519 <CLE-PUBLIQUE-ADM01> admin@adm01",
]
