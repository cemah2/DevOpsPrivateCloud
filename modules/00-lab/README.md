# Module 00 — Positionnement et montage du lab

| | |
|---|---|
| **Bloc** | A — Fondations automatisées |
| **Niveau** | Cœur |
| **Profil de lab** | Socle (construit dans ce module) |
| **Prérequis** | Aucun (module d'entrée) |
| **Durée indicative** | 35 à 50 heures |

## Contexte MédiSphère

Premier jour dans l'équipe Plateforme. Claire Morel te confie le chantier fondateur : préparer l'**hyperviseur du site PAR1** (`pve01`), construire le **réseau isolé du futur cloud privé** (VLANs, routeur/pare-feu, DNS, temps, accès d'administration), réaffecter l'ancien serveur du site **PAR2** (`hp01`) en **serveur de sauvegarde**, relier les deux sites par un **tunnel chiffré**, et livrer un **socle documenté, sauvegardé et restaurable**. Tous les modules suivants s'appuient sur ce socle.

Avant cela, Karim Benali veut évaluer ton niveau Linux et réseau : le module commence par un test de positionnement.

## Objectifs

À la fin de ce module, tu sais :
- évaluer tes acquis Linux/réseau et identifier tes lacunes ;
- administrer Proxmox VE au-delà de l'interface web : stockages, réseau, SDN, pools, permissions, API, jetons ;
- construire un routeur/pare-feu Linux (sous-interfaces VLAN, routage, nftables, NAT) ;
- fabriquer un template cloud-init et déployer des VMs reproductibles ;
- mettre en place DNS/DHCP provisoires, un serveur de temps et un VPN d'administration WireGuard ;
- installer et exploiter Proxmox Backup Server (sauvegarde, rétention, vérification, chiffrement, restauration) ;
- relier deux sites par WireGuard ;
- diagnostiquer méthodiquement des pannes réseau, DNS, MTU, stockage et sauvegarde.

## Carte des exercices

| ID | Titre | Type | Diff. | Palier |
|---|---|---|---|---|
| M00-E01 | Test de positionnement Linux | Q | ★★ | 1 |
| M00-E02 | Test de positionnement réseau | Q | ★★ | 1 |
| M00-E03 | Inventaire de l'existant sur `pve01` | RED | ★ | 1 |
| M00-E04 | Sauvegarde vérifiée des photos de `hp01` | LAB | ★ | 1 |
| M00-E05 | Comprendre l'architecture du lab | Q | ★★ | 1 |
| M00-E06 | Préparer `pve01` (dépôts, mises à jour, virtualisation imbriquée) | LAB | ★ | 1 |
| M00-E07 | Organiser les stockages sans rien casser | LAB | ★★ | 1 |
| M00-E08 | Pool, utilisateurs, groupes et rôles | LAB | ★ | 1 |
| M00-E09 | Créer le bridge du lab `vmbr1` | LAB | ★★ | 1 |
| M00-E10 | Construire le routeur/pare-feu `gw01` | LAB | ★★ | 1 |
| M00-E11 | Fabriquer le template cloud-init `tpl-debian13` | LAB | ★★ | 1 |
| M00-E12 | Déployer `adm01` et `dns01` depuis le template | LAB | ★ | 1 |
| M00-E13 | DNS provisoire avec dnsmasq | LAB | ★★ | 2 |
| M00-E14 | DHCP du VLAN SANDBOX par relais | LAB | ★★★ | 2 |
| M00-E15 | Outiller le poste d'administration `adm01` | LAB | ★★ | 2 |
| M00-E16 | VPN d'administration WireGuard | LAB | ★★ | 2 |
| M00-E17 | API Proxmox et jeton à privilèges minimaux | LAB | ★★ | 2 |
| M00-E18 | Créer une VM uniquement par l'API | LAB | ★★ | 2 |
| M00-E19 | Snapshots, clones liés et clones complets | LAB | ★ | 2 |
| M00-E20 | Réinstaller `hp01` en Proxmox Backup Server | LAB | ★★★ | 2 |
| M00-E21 | Tunnel inter-sites PAR1 ↔ PAR2 | LAB | ★★★ | 2 |
| M00-E22 | Datastore, rétention et tâches de sauvegarde | LAB | ★★ | 2 |
| M00-E23 | Restaurer une VM et un fichier | LAB | ★★ | 2 |
| M00-E24 | Questions d'exploitation : sauvegarde | Q | ★★ | 2 |
| M00-E25 | Runbooks « créer une VM » et « restaurer une VM » | RED | ★★ | 2 |
| M00-E26 | Revue de la configuration nftables d'un stagiaire | REV | ★★ | 2 |
| M00-E27 | Durcir l'accès à `pve01` | LAB | ★★ | 3 |
| M00-E28 | Migrer le réseau du lab vers Proxmox SDN | LAB | ★★★ | 3 |
| M00-E29 | Notifications Proxmox et PBS | LAB | ★★ | 3 |
| M00-E30 | Sauvegarder la configuration de l'hyperviseur | LAB | ★★ | 3 |
| M00-E31 | Temps synchronisé sur tout le lab | LAB | ★★ | 3 |
| M00-E32 | Optimiser la configuration des VMs du socle | LIBRE | ★★★ | 3 |
| M00-E33 | ADR : routeur Linux et stratégie de sauvegarde | RED | ★★ | 3 |
| M00-E34 | Mises à jour maîtrisées de `pve01` et `pbs01` | LAB | ★★ | 3 |
| M00-E35 | Questions de production : hyperviseur | Q | ★★★ | 3 |
| M00-E36 | Chiffrer les sauvegardes côté client | LAB | ★★★ | 3 |
| M00-E37 | Exercice de restauration chronométré | CHRONO | ★★★ | 3 |
| M00-E38 | Panne : plus d'accès Internet depuis INFRA | BF | ★★ | 4 |
| M00-E39 | Panne : `adm01` ne joint plus `dns01` | BF | ★★ | 4 |
| M00-E40 | Panne : la résolution DNS ne fonctionne plus | BF | ★★★ | 4 |
| M00-E41 | Panne : les petits échanges passent, les gros bloquent | BF | ★★★ | 4 |
| M00-E42 | Panne : la sauvegarde nocturne a échoué | BF | ★★ | 4 |
| M00-E43 | Panne : le site PAR2 est injoignable | BF | ★★★ | 4 |
| M00-E44 | Panne : une VM refuse de démarrer | BF | ★★★ | 4 |
| M00-E45 | Panne : horloges désynchronisées | BF | ★★ | 4 |
| M00-E46 | Astreinte : pannes multiples | BF | ★★★★ | 4 |
| M00-E47 | Suivre un paquet de bout en bout | LAB | ★★★ | 4 |
| M00-E48 | Mesurer et comprendre les performances disque | LAB | ★★★★ | 4 |
| M00-E49 | Questions expert : sous le capot | Q | ★★★ | 4 |
| M00-E50 | Mini-projet : livrer le socle MédiSphère v0 | LIBRE | ★★★ | 5 |

**Répartition** : 49 exercices + mini-projet · 9 break & fix · 6 questionnaires · 3 rédactions · 1 revue · 1 chronométré.

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check 00 <XX>` (voir l'introduction pour savoir d'où les lancer).
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.
