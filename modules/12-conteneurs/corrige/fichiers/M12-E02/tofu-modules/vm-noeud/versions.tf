# vm-noeud — fournisseurs requis (M08-E02).
#
# Module « nœud de cluster » : une VM clonée de l'image dorée courante d'une FAMILLE
# (debian13 ou rocky10), avec PLUSIEURS cartes réseau (MTU par carte), des disques de données
# et ses adresses enregistrées dans NetBox, comme vm-debian v2 (M06-E13).
# Il vit À CÔTÉ de vm-debian (pas dedans) : vm-debian garde son interface simple pour les
# hôtes à une carte ; vm-noeud sert aux nœuds Ceph (M08) et plus tard à OpenStack (M10).
# Contraintes larges : la configuration racine épingle (~> 0.116.0, ~> 5.8.0).

terraform {
  required_version = ">= 1.13.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.115.0, < 1.0.0"
    }
    netbox = {
      source  = "e-breuninger/netbox"
      version = "~> 5.8.0"
    }
  }
}
