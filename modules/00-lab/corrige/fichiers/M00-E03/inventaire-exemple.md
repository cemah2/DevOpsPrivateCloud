# Inventaire local du lab — pve01

> Rédigé le : 2026-10-05 — Par : (exemple fictif, pour comparaison)
> Document local, ignoré par git : il décrit mon réseau domestique.
> Mise à jour : relancer les commandes indiquées en commentaire (`<!-- … -->`).

## 1. Proxmox VE
<!-- pveversion ; pveversion -v | head ; cat /etc/os-release ; uname -r ; pvecm status ; pvesubscription get -->
- Version (sortie de `pveversion`) : `pve-manager/9.2.13/0a1b2c3d4e5f6a7b (running kernel: 6.17.2-1-pve)`
- Version de Debian et du noyau : Debian 13.1 « trixie », noyau 6.17.2-1-pve
- Nom du nœud (`<NOEUD>`) : `pve01`
- Cluster : nœud autonome (`pvecm status` : « Error: Corosync config '/etc/pve/corosync.conf' does not exist »)
- Abonnement : aucun (`status: notfound`)
- Dépôts APT configurés : `debian.sources` (trixie, trixie-updates, trixie-security) actif ;
  `pve-enterprise.sources` actif → **401 à chaque apt update** ; `ceph.sources` (enterprise) actif → 401.
  Aucun dépôt no-subscription. → à corriger en E06.
- Pare-feu Proxmox : désactivé au niveau datacenter (`pve-firewall status` : disabled/running)

## 2. Matériel (CPU, RAM)
<!-- lscpu ; grep -c vmx /proc/cpuinfo ; free -g ; cat /sys/module/kvm_intel/parameters/nested -->
- CPU : Intel Xeon E-2378G, 8 cœurs / 16 threads, VT-x (vmx) et VT-d présents
- RAM : 125 Gio utilisables ; 22 Gio utilisés (dont 16 Gio par les VMs perso), 101 Gio disponibles
- Virtualisation imbriquée : `nested` = `Y` (valeur par défaut du noyau), non persistée

## 3. Disques et stockages
<!-- lsblk -o NAME,SIZE,TYPE,ROTA,TRAN,MODEL,SERIAL,FSTYPE,MOUNTPOINTS ; ls -l /dev/disk/by-id/ ;
     pvs ; vgs ; lvs ; zpool status ; findmnt ; wipefs -n /dev/sdX ; cat /etc/pve/storage.cfg -->
| Disque (/dev/disk/by-id/…) | Taille | Type | Utilisation actuelle | Conclusion |
|---|---|---|---|---|
| `nvme-SAMSUNG_MZVL22T0HBLB-00B00_S6XXNF0R123456` | 2 To | NVMe | GPT : ESP 1 Gio + PV LVM 1,8 To (VG `pve` : `root` 96 Gio, `swap` 8 Gio, thin pool `data` 1,7 To) ; `VFree` 16 Gio | **à préserver** (système + VMs perso) |
| `ata-Samsung_SSD_870_EVO_2TB_S6PNNS0T654321` | 2 To | SSD SATA | aucune partition, `wipefs -n` vide, absent de `pvs`/`zpool`/`findmnt`/`storage.cfg` | **vierge, réaffectable** |
| `ata-ST2000DM008-2UB102_ZK20ABCD` | 2 To | HDD SATA | aucune partition, `wipefs -n` vide | **vierge, réaffectable** (cible des photos E04) |

| Stockage Proxmox | Type | Support physique | Contenus autorisés | Utilisé / total |
|---|---|---|---|---|
| `local` | dir `/var/lib/vz` | LV `pve/root` (NVMe) | iso, vztmpl, backup | 12 / 94 Gio |
| `local-lvm` | lvmthin `pve/data` | NVMe | images, rootdir | 180 Gio / 1,7 To |

- Santé : NVMe 3 % d'usure (`smartctl -a`, *Percentage Used*), SSD 0 réallocation, HDD 0 secteur en attente.

## 4. Réseau
<!-- ip -br link ; ip -br addr ; ip route ; cat /etc/network/interfaces ; bridge link ; cat /etc/resolv.conf -->
- Interfaces physiques : `enp1s0` (1 Gb/s, UP) ; `enp2s0` (1 Gb/s, DOWN, non câblée)
- Bridges : `vmbr0` (port `enp1s0`), non VLAN-aware
- pve01 : 192.168.1.20/24, passerelle 192.168.1.1, DNS 192.168.1.1
- LAN maison : 192.168.1.0/24, box 192.168.1.1, plage DHCP de la box 192.168.1.100-199
- Particularités : la box distribue de l'IPv6 (SLAAC) ; aucun VLAN sur le LAN

## 5. VMs et conteneurs existants
<!-- qm list ; pct list ; pvesh get /cluster/resources --type vm ; cat /etc/pve/jobs.cfg -->
| VMID | Nom | Type | État | Démarrage auto | RAM | Disques (stockage) | Remarque |
|---|---|---|---|---|---|---|---|
| 100 | homeassistant | VM | running | oui | 4 Gio | 32 Gio (local-lvm) | critique : domotique |
| 101 | jellyfin | VM | running | oui | 8 Gio | 64 Gio (local-lvm) | |
| 102 | nextcloud | CT | running | oui | 4 Gio | 80 Gio (local-lvm) | données familiales |
| 9000 | modele-ubuntu | VM (template) | — | — | 2 Gio | 3,5 Gio (local-lvm) | **conflit** avec le template 9000 du workbook |

- VMID en conflit : **9000**. Décision : renuméroter mon template perso en 8000 (clone complet puis suppression de l'original), validé avant E11.
- Sauvegardes des VMs perso : aucune planifiée (`jobs.cfg` vide) → vzdump vers disque USB avant E06/E07.

## 6. Ressources libres et contraintes
- RAM utilisable pour le lab : ~100 Gio (125 - 16 VMs perso - ~8 pour l'hôte et le cache)
- Espace libre : thin pool `local-lvm` 1,5 To ; SSD et HDD vierges (2 To chacun)
- Contraintes : homeassistant ne doit pas être arrêtée en journée ; redémarrage de pve01 possible le soir après 22 h.

## 7. Valeurs du lab
| Valeur | Ma valeur |
|---|---|
| `<NOEUD>` | `pve01` |
| `<LAN-MAISON>` | 192.168.1.0/24 |
| `<IP-BOX>` | 192.168.1.1 |
| `<IP-PVE01>` | 192.168.1.20 |
| `<IP-HP01-LAN>` | 192.168.1.30 |
| `<IP-GW01-WAN>` | à définir en E10 (hors plage DHCP de la box) |
| `<DNS-PUBLIC>` | à définir en E12 |
| `<DNS-AMONT>` | à définir en E13 |
| Stockage `local-nvme` | à définir en E07 |
| Stockage `ssd-lab` | à définir en E07 |
| Stockage `hdd-bulk` | à définir en E07 |
