# vm-debian v2 — fournisseurs requis (M06-E13 ; inchangés en v2.2, M10-E02).
# v2.0.0 est une version MAJEURE : le module exige désormais un fournisseur « netbox »
# configuré par l'appelant (l'adresse IP vient de l'IPAM de NetBox, plus d'une variable).
# Les consommateurs de v1.x ne sont pas cassés tant qu'ils restent sur leur étiquette v1.

terraform {
  required_version = ">= 1.13.0"

  required_providers {
    # Contrainte large, comme en v1 (M05-E13) : un module trop strict empêcherait ses
    # consommateurs de monter de version (M05-E31 : racines en ~> 0.116.0).
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.115.0, < 1.0.0"
    }
    netbox = {
      source = "e-breuninger/netbox"
      # 5.8 : jetons v2 (préfixe nbt_) reconnus d'eux-mêmes ; NetBox 4.3 à 4.6.5 validé
      # par l'éditeur (avertissement non bloquant au-delà, voir README).
      version = "~> 5.8.0"
    }
  }
}
