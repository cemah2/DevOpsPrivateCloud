# Module 11 — Provisioning bare-metal

| | |
|---|---|
| **Bloc** | B — Infrastructure cloud privé |
| **Niveau** | Secondaire |
| **Profil de lab** | Socle + VLAN 60 PROV : `pxe01` (2111), `bm01-04` (2112-2115), `maas01` (2116) ; iLO de `hp01` en lecture |
| **Prérequis** | Module 06 (Kea, NetBox, step-ca) ; module 07 (passerelles, relais) ; module 09 (installateur automatique de Proxmox VE) |
| **Durée indicative** | 20 à 25 heures |

## Contexte MédiSphère

Les serveurs physiques du futur datacenter arrivent par palettes : il faudra les installer par dizaines, identiques, sans clé USB ni écran. Chez InfoGér, chaque installation prenait une demi-journée et ne ressemblait à aucune autre. Karim Benali veut une **chaîne de provisioning** : le serveur est déclaré dans NetBox, il démarre sur le réseau, s'installe seul et rejoint l'inventaire ; son alimentation se pilote à distance par son contrôleur (IPMI, Redfish). Claire Morel veut aussi évaluer **MAAS** face à une solution maison avant de choisir.

Dans le lab, les « serveurs » sont des VMs vides qui démarrent en PXE, et le vrai contrôleur de gestion est l'**iLO de `hp01`**, interrogé en lecture : `hp01` porte PBS et n'est jamais réinstallé.

## Objectifs

À la fin de ce module, tu sais :
- construire un réseau de provisioning (DHCP avec classes PXE, TFTP, HTTP, iPXE) pour des machines BIOS et UEFI ;
- automatiser l'installation de Debian (preseed) et de Rocky Linux (kickstart), et d'un nœud Proxmox VE ;
- générer les configurations d'installation depuis NetBox ;
- interroger et piloter un contrôleur de gestion par IPMI et Redfish ;
- déployer MAAS et lui confier le cycle de vie de machines ;
- sécuriser et dépanner une chaîne de provisioning.

## Carte des exercices

| ID | Titre | Type | Diff. | Palier |
|---|---|---|---|---|
| M11-E01 | Test de positionnement : installer des serveurs | Q | ★★ | 1 |
| M11-E02 | Le réseau de provisioning | LAB | ★★ | 1 |
| M11-E03 | PXE et iPXE : démarrer sur le réseau | LAB | ★★ | 1 |
| M11-E04 | Installer Debian sans intervention (preseed) | LAB | ★★ | 1 |
| M11-E05 | Installer Rocky Linux sans intervention (kickstart) | LAB | ★★ | 1 |
| M11-E06 | Des installations décrites par NetBox | LAB | ★★★ | 2 |
| M11-E07 | IPMI et Redfish : découvrir l'iLO de `hp01` | LAB | ★★ | 2 |
| M11-E08 | Piloter l'alimentation par API | LAB | ★★ | 2 |
| M11-E09 | Installer MAAS | LAB | ★★ | 2 |
| M11-E10 | MAAS : inventorier et déployer des machines | LAB | ★★★ | 2 |
| M11-E11 | Revue : les fichiers d'installation du prestataire | REV | ★★ | 2 |
| M11-E12 | Runbook : provisionner un serveur | RED | ★★ | 2 |
| M11-E13 | Sécuriser la chaîne de provisioning | LAB | ★★★ | 3 |
| M11-E14 | Provisionner un nœud Proxmox VE par le réseau | LAB | ★★★ | 3 |
| M11-E15 | De la source de vérité au serveur en service | LIBRE | ★★★ | 3 |
| M11-E16 | ADR : MAAS, Tinkerbell ou chaîne maison ? | RED | ★★ | 3 |
| M11-E17 | Questions de production : provisioning | Q | ★★★ | 3 |
| M11-E18 | Inventaire matériel et firmware | LAB | ★★ | 3 |
| M11-E19 | Panne : le serveur ne démarre pas sur le réseau | BF | ★★ | 4 |
| M11-E20 | Panne : iPXE s'arrête en chemin | BF | ★★★ | 4 |
| M11-E21 | Panne : l'installation reste bloquée | BF | ★★ | 4 |
| M11-E22 | Panne : MAAS ne pilote plus les machines | BF | ★★★ | 4 |
| M11-E23 | Sous le capot : un démarrage PXE paquet par paquet | LAB | ★★★ | 4 |
| M11-E24 | Questions expert : provisioning | Q | ★★★ | 4 |
| M11-E25 | Mini-projet : l'usine de provisioning | LIBRE | ★★★ | 5 |

**Répartition** : 24 exercices + mini-projet · 4 break & fix · 3 questionnaires · 1 revue · 2 rédactions.

## Hôtes créés dans ce module

| Hôte | VMID | Adresse | Rôle | Exercice |
|---|---|---|---|---|
| `pxe01` | 2111 | 10.10.60.10 | TFTP, HTTP (nginx), iPXE, preseed, kickstart | E02 |
| `bm01-04` | 2112-2115 | DHCP 10.10.60.100-199 | Serveurs « nus » (SeaBIOS et OVMF) | E03 |
| `maas01` | 2116 | 10.10.60.11 | MAAS 3.7 (Ubuntu 24.04) | E09 |
| `tpl-ubuntu2404` | 9050 | — | Template Ubuntu 24.04 | E09 |

DHCP du VLAN 60, compte `wb-maas@pve!maas`, iLO de `hp01` : voir [`PLAN.md`](../../PLAN.md) §4.9.

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check 11 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break 11 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.
