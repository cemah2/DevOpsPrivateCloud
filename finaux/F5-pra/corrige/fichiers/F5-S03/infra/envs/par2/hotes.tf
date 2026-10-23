# hotes.tf — catalogue des VMs de PAR2 (PLAN §4.5 et §4.15, F5-S03 à S06). Pool par2, étiquette
# site-par2, pont vmbr2, passerelle 10.20.20.1 (hp01), MAC bc:24:11:20:50:<2 derniers chiffres du VMID>.
# Mémoire de PAR2 : ≈ 8 Go en veille, ≈ 10 Go en PRA (bao-par2 démarré, kms01 restauré hors OpenTofu).
#
# kms01 restauré (VMID 3501, 10.20.20.24) n'est PAS ici : c'est une restauration PBS (RB-355), jamais
# une VM créée par OpenTofu.

locals {
  catalogue = {
    adm02 = {
      vmid = 1050, ipv4 = "10.20.20.10", coeurs = 1, memoire_mo = 1024, disque_go = 32, disques_donnees = [],
      etiquettes = ["role-bastion"], demarre = true,
      description = "Poste d'administration de secours, miroirs Git, sonde ms-sonde-pra (F5-S03/S04)."
    }
    dns03 = {
      vmid = 1051, ipv4 = "10.20.20.11", coeurs = 1, memoire_mo = 512, disque_go = 16, disques_donnees = [],
      etiquettes = ["role-dns"], demarre = true,
      description = "PowerDNS secondaire de toutes les zones internes + récurseur ; promu primaire en PRA (F5-S03)."
    }
    s3-02 = {
      vmid = 1052, ipv4 = "10.20.20.14", coeurs = 1, memoire_mo = 1024, disque_go = 20,
      # Taille : volume réel des compartiments copiés de s3-01 (S02) × 1,5 ; à reprendre de ta mesure.
      disques_donnees = [{ taille_go = 300 }],
      etiquettes      = ["role-s3"], demarre = true,
      description     = "SeaweedFS de PAR2 : état tofu-par2, cible de filer.sync et de la copie MédiDoc (F5-S03/S04)."
    }
    reg02 = {
      vmid = 1053, ipv4 = "10.20.20.18", coeurs = 1, memoire_mo = 512, disque_go = 16,
      disques_donnees = [{ taille_go = 60 }],
      etiquettes      = ["role-registre"], demarre = true,
      description     = "registry:3 en lecture pour PAR2 : images et signatures copiées par cosign copy (F5-S04)."
    }
    k8s-par2-n01 = {
      vmid = 1054, ipv4 = "10.20.20.50", coeurs = 2, memoire_mo = 5120, disque_go = 60, disques_donnees = [],
      etiquettes = ["role-k8s-cp", "env-k8s-par2"], demarre = true,
      description = "Nœud unique du cluster de secours k8s-par2 (F5-S06)."
    }
    bao-par2 = {
      vmid = 1055, ipv4 = "10.20.20.21", coeurs = 1, memoire_mo = 1024, disque_go = 16, disques_donnees = [],
      etiquettes = ["role-coffre"], demarre = false,
      description = "OpenBao de secours : ARRÊTÉ hors PRA ; restauré depuis l'instantané, descellé par kms01 restauré (F5-S05)."
    }
  }

  hotes = { for nom, h in local.catalogue : nom => h if !contains(var.absentes, nom) }
}

module "vm" {
  source   = "./modules/vm-par2"
  for_each = local.hotes

  nom             = each.key
  vmid            = each.value.vmid
  noeud           = var.noeud
  stockage        = var.stockage
  pont            = var.pont
  coeurs          = each.value.coeurs
  memoire_mo      = each.value.memoire_mo
  disque_go       = each.value.disque_go
  disques_donnees = each.value.disques_donnees
  ipv4            = each.value.ipv4
  mac             = format("bc:24:11:20:50:%02d", each.value.vmid % 100)
  etiquettes      = concat(["site-par2"], each.value.etiquettes)
  description     = each.value.description
  demarre         = each.value.demarre
  cle_ssh_admin   = var.cle_ssh_admin
  # s3-02 porte l'état : Proxmox refuse sa suppression, OpenTofu aussi (prevent_destroy dans le module
  # n'accepte pas de variable : la protection Proxmox fait office de garde-fou pour toutes).
  protection = contains(["s3-02", "adm02"], each.key)
}
