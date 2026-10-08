# M09-E23 — La VM « venue d'InfoGér »

InfoGér a livré l'export de l'application **Legacy-RDV** (ancienne prise de rendez-vous, PHP + MariaDB) sous la forme d'une archive **OVA** issue de son VMware. Le workbook ne versionne pas d'image disque : `generer-ova.sh` reconstruit un export équivalent à partir de l'image cloud officielle de Debian 13.

## Fiche de livraison d'InfoGér (telle que reçue)

> **Objet** : Export VM RDV-LEGACY-01 — fin de contrat
> Format : OVA (OVF 1.0), matériel virtuel vmx-13, exporté depuis vCenter.
> VM : `legacy-rdv01`, 2 vCPU, 2 Go RAM, 1 disque de 10 Go (contrôleur LSI Logic), 1 carte E1000 sur le réseau « RDV-PROD » (192.168.50.20/24, passerelle 192.168.50.1).
> Système : Debian 64 bits. Outils VMware installés. Compte d'administration : à demander au support (délai : 10 jours ouvrés).
> Somme de contrôle : voir le manifeste dans l'archive.

Ce que la fiche ne dit pas (et que tu découvriras) : l'image a été préparée pour démarrer sur un hyperviseur, avec cloud-init actif ; ni l'agent QEMU, ni les pilotes que tu attends n'y sont forcément.

## Fichiers

| Fichier | Rôle |
|---|---|
| `generer-ova.sh` | Télécharge `debian-13-genericcloud-amd64.qcow2` (HTTPS, somme SHA-512 vérifiée contre `SHA512SUMS`), l'agrandit à 10 Gio, la convertit en VMDK *streamOptimized*, remplit le descripteur, écrit le manifeste SHA-256, assemble `legacy-rdv01.ova` (descripteur en premier). |
| `legacy-rdv01.ovf.modele` | Descripteur OVF 1.0 « façon VMware » (contrôleur `lsilogic`, carte `E1000`, micrologiciel BIOS, type de système Debian 64 bits). |

## Générer l'OVA

Sur `hv01` (il a `qemu-img`, l'accès à Internet par la passerelle, et c'est là que tu importeras) :

```
admin@adm01:~$ scp -r ~/DevOpsPrivateCloud/modules/09-cluster-proxmox/ressources/M09-E23 root@hv01:/root/
root@hv01:~# /root/M09-E23/generer-ova.sh /var/lib/vz/import
```

Environ 330 Mio à télécharger, 4 Gio d'espace libre pendant la génération sur le stockage `local` de `hv01`. Note la somme SHA-256 affichée à la fin : c'est elle que tu compareras avant l'import, comme tu le ferais avec la somme qu'un prestataire t'envoie par un autre canal.

Si le téléchargement échoue (somme incorrecte), relance plus tard : `latest` change à chaque nouvelle image publiée par Debian, et les deux fichiers peuvent être brièvement désynchronisés.
