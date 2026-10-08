# Module 09 — Cluster de virtualisation

| | |
|---|---|
| **Bloc** | B — Infrastructure cloud privé |
| **Niveau** | Cœur |
| **Profil de lab** | infra : socle + cluster Proxmox imbriqué `hv01-03` (2091-2093, 12 Go chacun) ; `ceph01-03` démarrées seulement pour l'exercice de stockage externe |
| **Prérequis** | Module 08 (Ceph) ; module 07 (VLAN, MTU, VRRP) ; module 00 (Proxmox VE, PBS) |
| **Durée indicative** | 40 à 50 heures |

## Contexte MédiSphère

`pve01` est un hyperviseur unique : sa panne arrête tout PAR1. Pour la production, MédiSphère veut un **cluster** de virtualisation : migration à chaud pour la maintenance, redémarrage automatique des VMs sur un autre nœud en cas de panne, stockage partagé, sauvegardes hors site. Le parc d'InfoGér tournait déjà sur un Proxmox ancien, sans quorum correct ni procédure. Claire Morel veut une plateforme qu'on maintient sans interruption de service ; Nadia Roussel veut des runbooks pour la perte d'un nœud ; Sophie Laurent exige pare-feu, double authentification et traçabilité. Dans le lab, le cluster est **imbriqué** : trois nœuds Proxmox VE virtuels sur `pve01`.

## Objectifs

À la fin de ce module, tu sais :
- installer des nœuds Proxmox VE de façon automatisée et former un cluster (Corosync, liens redondants) ;
- raisonner sur le quorum, y compris avec un QDevice, et éviter le *split-brain* ;
- mettre en œuvre le stockage du cluster : Ceph hyperconvergé, Ceph externe, ZFS et réplication ;
- configurer la haute disponibilité (règles d'affinité de Proxmox VE 9, fencing) et la tester ;
- sauvegarder et restaurer avec PBS, migrer à chaud, importer des VMs ;
- maintenir le cluster : mises à jour progressives, montée de version de Ceph, sécurité, supervision ;
- diagnostiquer les pannes de cluster (quorum, pmxcfs, HA, migration, stockage).

## Carte des exercices

| ID | Titre | Type | Diff. | Palier |
|---|---|---|---|---|
| M09-E01 | Test de positionnement : virtualisation en cluster | Q | ★★ | 1 |
| M09-E02 | Préparer la virtualisation imbriquée | LAB | ★★ | 1 |
| M09-E03 | Installer Proxmox VE sans clavier | LAB | ★★ | 1 |
| M09-E04 | Former le cluster et ses liens Corosync | LAB | ★★ | 1 |
| M09-E05 | Deux nœuds et un arbitre : le QDevice | LAB | ★★★ | 1 |
| M09-E06 | Stockages et réseaux des invités | LAB | ★★ | 1 |
| M09-E07 | Premières VMs du cluster et migration | LAB | ★★ | 1 |
| M09-E08 | Un troisième nœud | LAB | ★★ | 1 |
| M09-E09 | Questions : cluster, quorum et HA | Q | ★★ | 1 |
| M09-E10 | Ceph hyperconvergé | LAB | ★★ | 2 |
| M09-E11 | Stockage partagé et migration à chaud | LAB | ★★ | 2 |
| M09-E12 | Consommer le Ceph de PAR1 | LAB | ★★★ | 2 |
| M09-E13 | Haute disponibilité : ressources et règles | LAB | ★★★ | 2 |
| M09-E14 | Réplication ZFS entre nœuds | LAB | ★★ | 2 |
| M09-E15 | Sauvegarder le cluster vers PBS | LAB | ★★ | 2 |
| M09-E16 | SDN du cluster : zones, VNets et EVPN | LAB | ★★★ | 2 |
| M09-E17 | Droits, pools et jetons du cluster | LAB | ★★ | 2 |
| M09-E18 | Piloter le cluster par le code | LIBRE | ★★★ | 2 |
| M09-E19 | Mises à jour progressives des nœuds | LAB | ★★ | 2 |
| M09-E20 | Évacuer un nœud, équilibrer la charge | LAB | ★★ | 2 |
| M09-E21 | Revue : la configuration de cluster du stagiaire | REV | ★★ | 2 |
| M09-E22 | Runbook : maintenance d'un nœud | RED | ★★ | 2 |
| M09-E23 | Importer une VM venue d'ailleurs | LAB | ★★ | 2 |
| M09-E24 | Le fencing à l'épreuve | LAB | ★★★ | 3 |
| M09-E25 | Superviser le cluster | LAB | ★★ | 3 |
| M09-E26 | Sécuriser le cluster | LAB | ★★★ | 3 |
| M09-E27 | Le réseau de migration | LAB | ★★ | 3 |
| M09-E28 | Monter Ceph de Squid à Tentacle | LAB | ★★★ | 3 |
| M09-E29 | Reconstruire un nœud, restaurer le cluster | LIBRE | ★★★ | 3 |
| M09-E30 | ADR : cluster Proxmox ou OpenStack ? | RED | ★★ | 3 |
| M09-E31 | Capacité et surallocation | LIBRE | ★★★ | 3 |
| M09-E32 | Questions de production : cluster de virtualisation | Q | ★★★ | 3 |
| M09-E33 | Fiche de changement : mise à jour du cluster | RED | ★★ | 3 |
| M09-E34 | Remplacer un nœud en temps limité | CHRONO | ★★★ | 3 |
| M09-E35 | Panne : le cluster a perdu le quorum | BF | ★★★ | 4 |
| M09-E36 | Panne : un nœud ne rejoint plus le cluster | BF | ★★★ | 4 |
| M09-E37 | Panne : une VM HA reste en erreur | BF | ★★★ | 4 |
| M09-E38 | Panne : la migration à chaud échoue | BF | ★★ | 4 |
| M09-E39 | Panne : les VMs se figent | BF | ★★★ | 4 |
| M09-E40 | Panne : la réplication est en échec | BF | ★★ | 4 |
| M09-E41 | Panne : la sauvegarde nocturne a échoué | BF | ★★ | 4 |
| M09-E42 | Panne : impossible de modifier une VM | BF | ★★★ | 4 |
| M09-E43 | Astreinte : le cluster en détresse | BF | ★★★★ | 4 |
| M09-E44 | Sous le capot : pmxcfs, votequorum et le gestionnaire HA | LAB | ★★★ | 4 |
| M09-E45 | Questions expert : cluster Proxmox | Q | ★★★ | 4 |
| M09-E46 | Mini-projet : virtualisation MédiSphère v1 | LIBRE | ★★★ | 5 |

**Répartition** : 45 exercices + mini-projet · 9 break & fix · 4 questionnaires · 1 revue · 3 rédactions · 1 chronométré.

## Hôtes créés dans ce module

| Hôte | VMID | Adresses | Rôle | Exercice |
|---|---|---|---|---|
| `hv01`, `hv02` | 2091, 2092 | MGMT 10.10.10.51-52, COROSYNC 10.10.32.51-52, Ceph 10.10.30.71-72 / 10.10.31.71-72 | Nœuds Proxmox VE 9.2 imbriqués | E03 |
| `hv03` | 2093 | MGMT 10.10.10.53, COROSYNC 10.10.32.53, Ceph 10.10.30.73 / 10.10.31.73 | Troisième nœud | E08 |
| QDevice | — | `pbs01` (10.20.10.10) | `corosync-qnetd` (phase à deux nœuds) | E05 |

Cluster `hv-par1`, invités imbriqués VMID 100-199, sauvegardes `ds-lab` namespace `par1/hv` : voir [`PLAN.md`](../../PLAN.md) §4.9. Le cluster est détruit en fin de module ; la recette le reconstruit depuis le code.

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check 09 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break 09 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.
