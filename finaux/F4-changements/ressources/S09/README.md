# F4-S09 — L'export VMware d'InfoGér (simulé)

InfoGér arrête son contrat. Ses trois dernières VMs tournent sur son VMware (vSphere 8, matériel virtuel `vmx-19`) ; le lab n'a pas d'ESXi, alors ce dossier **fabrique**, sur `pve01`, l'export qu'InfoGér t'aurait livré : un dossier par VM avec un descripteur **OVF**, un disque **VMDK *streamOptimized*** et un manifeste **`.mf`** (SHA-256), plus une fiche d'inventaire incomplète.

Ce n'est pas la VM du M09-E23 : les systèmes sont des **Debian 12** installées « à la main » par InfoGér (noyau standard, outils VMware, adresse fixe sur `ens192`, cloud-init désactivé), et `legacy-rdv01` contient **des données** : environ 2 600 rendez-vous et une centaine de pièces jointes, tous fictifs.

## Fichiers

| Fichier | Rôle |
|---|---|
| `fabriquer-export-vmware.sh` | Fabrique l'export (à lancer en root sur `pve01`). Idempotent, ne touche à aucune VM. |
| `modele-vmware.ovf` | Descripteur OVF 1.0 « façon vCenter » (`vmx-19`, `VmxNet3`, contrôleur `VirtualSCSI` = pvscsi ou `lsilogic`, micrologiciel EFI ou BIOS, MAC VMware). |
| `inventaire-infoger.csv` | La fiche d'inventaire **telle qu'InfoGér l'a envoyée** : incomplète et en partie fausse. |
| `personnalisation/` | Ce qui est appliqué dans chaque image : réseau, comptes, services, Legacy-RDV et ses données, vsftpd, statistiques. **Ne le lis pas avant d'avoir fait ta propre découverte (F4-S09)** : c'est l'équivalent du « savoir d'InfoGér » qui ne t'a pas été transmis. |

## Méthode de fabrication

1. Téléchargement de `debian-12-genericcloud-amd64.qcow2` depuis `https://cloud.debian.org/images/cloud/bookworm/latest/` et vérification par la somme SHA-512 du fichier `SHA512SUMS` (HTTPS). L'image est gardée en cache (vérifiée à chaque passage).
2. Pour chaque VM : disque qcow2 de 8 Gio où la partition racine est agrandie (`virt-resize --expand /dev/sda1`).
3. Personnalisation **hors ligne** par `virt-customize` (libguestfs démarre une petite machine d'appoint qui monte le disque ; aucune VM Proxmox n'est créée) : installation des paquets (noyau standard `linux-image-amd64` à la place du noyau *cloud*, `open-vm-tools`, `ifupdown`, Apache + PHP 8.2 + MariaDB 10.11, vsftpd…), fichiers de configuration d'InfoGér, compte `infoger` (mot de passe aléatoire **non conservé**, clé SSH dont la partie privée est **détruite**), `root` sans mot de passe. Pour `legacy-rdv01`, un MariaDB **temporaire** est démarré dans la machine d'appoint (sans réseau) pour charger le schéma de `apps/legacy-rdv/schema.sql` et les données générées par `generer-donnees.pl` (déterministe : mêmes données à chaque fabrication).
4. `virt-sparsify --in-place`, puis `qemu-img convert -O vmdk -o subformat=streamOptimized,adapter_type=lsilogic`.
5. Descripteur OVF rempli depuis `modele-vmware.ovf`, manifeste `SHA256(fichier)= somme`.

## Fabriquer l'export

Sur `pve01` (il a accès à Internet, et c'est là que tu importeras) :

```
root@pve01:~# apt-get install -y libguestfs-tools
root@pve01:~# /root/DevOpsPrivateCloud/finaux/F4-changements/ressources/S09/fabriquer-export-vmware.sh
```

> ⚠️ **Attention** : `libguestfs-tools` s'installe sur l'hôte Proxmox lui-même (paquets Debian officiels, aucun service démarré). Si tu préfères ne rien installer sur `pve01`, garde-le en tête dans ta fiche de changement et retire le paquet après F4 (`apt-get purge libguestfs-tools && apt-get autoremove`).

- Le dossier produit est `<chemin du stockage hdd-bulk>/import/infoger-export/` (option `--stockage` pour un autre stockage de type répertoire). Rien d'autre n'est écrit ; aucune VM n'est créée ni modifiée ; le contenu `import` du stockage n'est **pas** activé par le script.
- Durée : 15 à 30 minutes. Espace : 25 Gio libres pendant la fabrication, environ 3 Gio ensuite.
- Relancer le script ne refait que ce qui manque ou ne correspond plus au manifeste ; `--forcer` refait tout ; `--vm stats01` ne refait qu'une VM.
- À la fin, le script affiche les sommes SHA-256 des fichiers livrés : c'est le « courriel d'InfoGér ». Garde-les, tu les compareras avant tout import (F4-S10).
- Le sous-dossier caché `.workbook/` (700) sert au workbook : date de référence des données, image en cache, rendez-vous témoins relus par `lab/bin/check F4 13`, mot de passe du compte MariaDB `stats`. Ce n'est pas une livraison d'InfoGér : ne t'en sers pas pour ta découverte.

Si le téléchargement échoue sur une somme incorrecte, relance plus tard : `latest` change quand Debian publie une nouvelle image et les deux fichiers peuvent être brièvement désynchronisés.

## Ce qu'InfoGér te dit (et ne te dit pas)

> **Objet** : Export des VMs MEDISPHERE — fin de contrat
> Ci-joint l'export OVF des trois VMs (vCenter 8.0, format OVF). Les VMs ont été arrêtées proprement avant l'export. Fiche d'inventaire jointe. Les mots de passe sont dans notre coffre, nous vous les communiquerons sous dix jours ouvrés après signature du PV de réversibilité.
> Le support InfoGér

La fiche d'inventaire n'est pas la vérité : à toi de découvrir ce que contiennent réellement les disques (sans démarrer les VMs si tu le peux), et ce qui dépend de quoi.
