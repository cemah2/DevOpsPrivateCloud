# enregistrement-dns (tofu-modules ≥ v2.1.0) — A + PTR d'un hôte dans PowerDNS (M06-E14).
# Module ADJACENT à vm-debian (et non intégré) : on peut nommer une VM, un service ou une
# adresse virtuelle sans créer de VM, et vm-debian ne dépend pas du fournisseur PowerDNS.

terraform {
  required_version = ">= 1.13.0"

  required_providers {
    powerdns = {
      # Le fournisseur historique pan-net/powerdns est abandonné : fork maintenu mmianl.
      source  = "mmianl/powerdns"
      version = "~> 2.5.0"
    }
  }
}
