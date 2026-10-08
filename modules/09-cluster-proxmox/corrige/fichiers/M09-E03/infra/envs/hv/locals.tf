# locals.tf — valeurs calculées (M09-E03).
locals {
  domaine = "par1.medisphere.internal"

  # Étiquettes Proxmox : env-m09 (environnement du module, PLAN §4.8) et hv-par1 (appartenance
  # au cluster imbriqué). Triées : Proxmox les trie, sinon chaque plan verrait une différence.
  etiquettes = sort(["env-m09", "hv-par1"])

  description = "Nœud du cluster Proxmox imbriqué hv-par1 (M09). Géré par OpenTofu (plateforme/infra, envs/hv) : ne pas modifier à la main."

  # Les cinq cartes, DANS CET ORDRE (net0 à net4). Le nom (nicK) est celui que l'installateur
  # épingle sur l'adresse MAC (fichier de réponse, [network.interface-name-pinning]).
  #   mtu = null : rien d'imposé, l'invité garde 1500 (VLAN 10, 32, 99 : PLAN §4.9, M07-E15) ;
  #   mtu = 9000 : trames géantes de bout en bout (VLAN 30 et 31). Jamais « 1 » (MTU du pont) :
  #   vmbr1 est à 9000 depuis M07-E15, et le nœud passerait MGMT à 9000 derrière une passerelle à 1500.
  cartes = [
    { pont = "vmgmt", mtu = null, trunks = null, usage = "MGMT, vmbr0 du nœud, Corosync lien 1" },
    { pont = "vcoro", mtu = null, trunks = null, usage = "COROSYNC, lien 0" },
    { pont = "vstopub", mtu = 9000, trunks = null, usage = "Ceph public" },
    { pont = "vstoclu", mtu = 9000, trunks = null, usage = "Ceph cluster" },
    { pont = var.pont_invites, mtu = null, trunks = join(";", [for v in var.vlans_invites : tostring(v)]), usage = "trunk des invités imbriqués" },
  ]

  # Adresses MAC fixes, administrées localement (bit 0x02) : 02:4d:53 (« MS »), 09 (module),
  # numéro du nœud, numéro de la carte. Elles doivent rester stables : l'installateur y épingle
  # les noms nic0..nic4, et le filtre réseau du fichier de réponse désigne nic0 par sa MAC.
  # installation/preparer-iso.sh calcule les mêmes valeurs.
  macs = {
    for n, v in var.noeuds : n => [for k in range(5) : format("02:4d:53:09:%02x:%02x", v.numero, k)]
  }

  # Disques : numéros de série fixes (≤ 20 octets), visibles dans le nœud sous
  # /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_<série>. Le fichier de réponse choisit le disque
  # système par sa série ; Ceph (E10) et ZFS (E06) désignent leurs disques de la même façon.
  disques = [
    { interface = "scsi0", role = "systeme", taille = 32, stockage = var.stockage_systeme },
    { interface = "scsi1", role = "osd1", taille = 48, stockage = var.stockage_donnees },
    { interface = "scsi2", role = "osd2", taille = 48, stockage = var.stockage_donnees },
    { interface = "scsi3", role = "zfs", taille = 32, stockage = var.stockage_donnees },
  ]
}
