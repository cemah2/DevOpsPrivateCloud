# Démarrage réseau des serveurs nus — séquences observées (M11-E03)

Relevé du JJ/MM/AAAA, `bm03` (OVMF) puis `bm01` (SeaBIOS), VLAN 60, Kea (`dns01` primaire).
Sources : journal de Kea (`journalctl -u isc-kea-dhcp4-server` sur `dns01`), journal de tftpd-hpa
(`journalctl -t in.tftpd` sur `pxe01`), journal d'accès de nginx (`/var/log/nginx/pxe-acces.log`).

## `bm03` — UEFI (OVMF) : la séquence complète

| # | Qui | Quoi | Preuve |
|---|---|---|---|
| 1 | micrologiciel UEFI (pile PXE d'EDK2) | DHCPDISCOVER, option 93 = 0x0007, option 60 `PXEClient:Arch:00007:…`, pas d'option 77 | Kea : `DHCP4_PACKET_RECEIVED` … classes `ALL, pxe-uefi-x64, KNOWN/UNKNOWN` |
| 2 | Kea | OFFER/ACK : 10.10.60.1xx, `siaddr` 10.10.60.10, `file` = `ipxe.efi` | Kea : `DHCP4_LEASE_ALLOC` |
| 3 | micrologiciel | TFTP RRQ `ipxe.efi` (négociation `tsize`, `blksize`) | tftpd : `RRQ from 10.10.60.1xx filename ipxe.efi` |
| 4 | iPXE (le nôtre, paquet Debian) | DHCPDISCOVER, option 77 = `iPXE` | Kea : classe `ipxe` |
| 5 | Kea | ACK : `file` = `http://pxe01.par1.medisphere.internal/boot.ipxe` | |
| 6 | iPXE | GET `/boot.ipxe`, GET `/ipxe/mac-02-4d-53-60-00-03.ipxe` (404), GET `/ipxe/menu.ipxe` | nginx : trois lignes, la deuxième en 404 |

## `bm01` — BIOS (SeaBIOS) : pas de TFTP

| # | Qui | Quoi |
|---|---|---|
| 1 | ROM réseau de la carte virtio de QEMU = **iPXE** (version de QEMU, affichée par le menu) | DHCPDISCOVER avec option 93 = 0x0000 **et** option 77 = `iPXE` |
| 2 | Kea | classe `ipxe` (les classes `pxe-*` excluent iPXE) : `file` = URL de `boot.ipxe` |
| 3 | iPXE de la ROM | GET `/boot.ipxe`, puis le menu ; aucun accès TFTP |

**Pourquoi.** QEMU embarque iPXE comme ROM d'option des cartes réseau virtuelles (`pxe-virtio.rom`) : en BIOS,
le « micrologiciel PXE » **est** iPXE. En UEFI, OVMF utilise sa propre pile PXE (EDK2) au-dessus du pilote de
la carte : on voit la séquence complète. Sur un vrai serveur (carte Intel ou Broadcom), le BIOS ferait la
séquence complète avec `undionly.kpxe`.

**Conséquence** : le chemin TFTP en BIOS n'est pas exercé par le lab (toutes les ROM réseau de QEMU sont des
iPXE). Il reste écrit et testé (Kea : classe `pxe-bios` ; TFTP : `undionly.kpxe` servi) pour les vrais
serveurs. Autre conséquence : en BIOS, c'est l'iPXE **de QEMU** qui exécute nos scripts, pas celui du paquet
Debian ; ses options de compilation (HTTPS notamment) ne sont pas les nôtres, ce qui comptera en M11-E13.
