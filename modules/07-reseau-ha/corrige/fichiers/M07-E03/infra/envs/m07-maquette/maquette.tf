# maquette.tf — LA description de la maquette (M07-E03) : une entrée par VM.
#
#   admin  : adresse de eth0 sur vsandbox : "dhcp", ou une adresse fixe /24 (passerelle 10.10.99.1)
#   cartes : cartes SUPPLÉMENTAIRES, dans l'ordre (net1 → eth1, net2 → eth2…) : VNet + adresse
#   fonction : étiquette(s) Proxmox de fonction, en plus de env-m07 (→ groupes Ansible m07_…)
#
# Ajouter une VM (hap01 au palier 2) = ajouter une entrée. Changer l'ordre des cartes d'une VM
# change ses noms d'interface (eth1, eth2…) : ne le fais qu'en connaissance de cause.
# Adresses : introduction du module, « Plan d'adressage » ; PLAN.md §4.9.

locals {
  passerelle_sandbox = "10.10.99.1"

  vms = {
    net01 = {
      vmid   = 2070, coeurs = 2, memoire = 2048, admin = "dhcp", fonction = ["m07-labo"]
      cartes = []
    }
    spine01 = {
      vmid = 2071, coeurs = 1, memoire = 1024, admin = "dhcp", fonction = ["m07-fabric", "m07-spine"]
      cartes = [
        { vnet = "vfab1", ipv4 = "10.10.250.0/31" }, # → leaf01
        { vnet = "vfab2", ipv4 = "10.10.250.2/31" }, # → leaf02
      ]
    }
    spine02 = {
      vmid = 2072, coeurs = 1, memoire = 1024, admin = "dhcp", fonction = ["m07-fabric", "m07-spine"]
      cartes = [
        { vnet = "vfab3", ipv4 = "10.10.250.4/31" }, # → leaf01
        { vnet = "vfab4", ipv4 = "10.10.250.6/31" }, # → leaf02
      ]
    }
    leaf01 = {
      # Adresse fixe : extrémité de la session BGP avec la bordure (M07-E16).
      vmid = 2073, coeurs = 1, memoire = 1024, admin = "10.10.99.251/24", fonction = ["m07-fabric", "m07-leaf"]
      cartes = [
        { vnet = "vfab1", ipv4 = "10.10.250.1/31" },  # → spine01
        { vnet = "vfab3", ipv4 = "10.10.250.5/31" },  # → spine02
        { vnet = "vfab5", ipv4 = "10.10.250.8/31" },  # → srv01
        { vnet = "vfab7", ipv4 = "10.10.250.12/31" }, # → leaf02
      ]
    }
    leaf02 = {
      vmid = 2074, coeurs = 1, memoire = 1024, admin = "dhcp", fonction = ["m07-fabric", "m07-leaf"]
      cartes = [
        { vnet = "vfab2", ipv4 = "10.10.250.3/31" },  # → spine01
        { vnet = "vfab4", ipv4 = "10.10.250.7/31" },  # → spine02
        { vnet = "vfab6", ipv4 = "10.10.250.10/31" }, # → srv02
        { vnet = "vfab7", ipv4 = "10.10.250.13/31" }, # → leaf01
      ]
    }
    srv01 = {
      # Adresse fixe : VRRP unicast (E08) et backend HAProxy (E10).
      vmid   = 2075, coeurs = 1, memoire = 1024, admin = "10.10.99.252/24", fonction = ["m07-web"]
      cartes = [{ vnet = "vfab5", ipv4 = "10.10.250.9/31" }]
    }
    srv02 = {
      vmid   = 2076, coeurs = 1, memoire = 1024, admin = "10.10.99.253/24", fonction = ["m07-web"]
      cartes = [{ vnet = "vfab6", ipv4 = "10.10.250.11/31" }]
    }
    lyo-gw01 = {
      # eth0 = le « WAN Internet » de l'agence de Lyon (extrémité de wg2, M07-E18).
      vmid   = 2077, coeurs = 1, memoire = 1024, admin = "10.10.99.250/24", fonction = ["m07-lyo"]
      cartes = [{ vnet = "vfab8", ipv4 = "10.30.10.1/24" }]
    }
    lyo-pc01 = {
      # eth0 : administration ; garde TOUJOURS sa route par défaut (DHCP). M07-E18 n'ajoute que
      # des routes ciblées vers PAR1, par lyo-gw01 (10.30.10.1).
      vmid   = 2078, coeurs = 1, memoire = 512, admin = "dhcp", fonction = ["m07-lyo"]
      cartes = [{ vnet = "vfab8", ipv4 = "10.30.10.10/24" }]
    }
  }

  # Adresses fixes du VLAN 99 qui ont un nom (A + PTR) et une réservation dans NetBox.
  adresses_fixes = {
    for nom, vm in local.vms : nom => split("/", vm.admin)[0] if vm.admin != "dhcp"
  }

  description = "Maquette réseau du module 07. Gérée par OpenTofu (plateforme/infra, envs/m07-maquette) : jetable, ne pas modifier à la main."
}
