# Module 07 — Réseau datacenter et haute disponibilité

| | |
|---|---|
| **Bloc** | B — Infrastructure cloud privé |
| **Niveau** | Cœur |
| **Profil de lab** | Socle + maquette réseau (VMs 2070-2079, ≈ 10 Go toutes allumées) ; `gw02`, `lb01`, `lb02` permanents, créés dans ce module |
| **Prérequis** | Module 06 (socle v1 : NetBox, PowerDNS, Kea, step-ca) ; module 05 (OpenTofu) ; module 04 (rôles Ansible) |
| **Durée indicative** | 40 à 50 heures |

## Contexte MédiSphère

Le socle v1 tient, mais il repose sur **une seule passerelle** : quand `gw01` redémarre, tout le lab est coupé du monde, les sauvegardes vers PAR2 s'arrêtent et le VPN d'administration tombe. Le bloc B va ajouter des dizaines de machines (Ceph, cluster Proxmox, OpenStack) qui exigent un réseau de datacenter sérieux : réseaux de stockage en *jumbo frames*, routage dynamique, points d'entrée redondants. Claire Morel veut une bordure sans point unique de défaillance avant d'y brancher le stockage ; Karim Benali veut que l'équipe sache lire une fabric *leaf-spine* et une session BGP, parce que Kubernetes annoncera ses adresses de services en BGP au bloc C ; MédiSphère ouvre aussi une agence à Lyon qu'il faut raccorder.

## Objectifs

À la fin de ce module, tu sais :
- agréger des liens (bonding, LACP), segmenter en VLAN et utiliser Open vSwitch ;
- router en statique, en OSPF et en BGP avec FRR, y compris BGP *unnumbered* et ECMP dans une fabric *leaf-spine* ;
- rendre une passerelle et un service redondants avec VRRP (keepalived), synchroniser les connexions (conntrackd) ;
- publier des services derrière des répartiteurs HAProxy redondants, terminer TLS, comparer avec Nginx ;
- maîtriser le MTU de bout en bout (jumbo frames, PMTUD) ;
- raccorder un site distant en WireGuard avec routage dynamique ;
- diagnostiquer méthodiquement une panne réseau, du pont Linux à la table de routage.

## Carte des exercices

| ID | Titre | Type | Diff. | Palier |
|---|---|---|---|---|
| M07-E01 | Test de positionnement : réseau de datacenter | Q | ★★ | 1 |
| M07-E02 | Cartographier le réseau du lab de bout en bout | LAB | ★ | 1 |
| M07-E03 | Monter la maquette réseau par le code | LAB | ★★ | 1 |
| M07-E04 | Bonding Linux : active-backup et LACP | LAB | ★★ | 1 |
| M07-E05 | Premiers pas avec Open vSwitch | LAB | ★★ | 1 |
| M07-E06 | Routage statique puis OSPF avec FRR | LAB | ★★ | 1 |
| M07-E07 | BGP avec FRR : sessions et politiques | LAB | ★★ | 1 |
| M07-E08 | Une adresse virtuelle avec VRRP | LAB | ★★ | 1 |
| M07-E09 | Questions : L2, L3, agrégation, redondance | Q | ★★ | 1 |
| M07-E10 | Répartir un service HTTP avec HAProxy | LAB | ★★ | 2 |
| M07-E11 | Nginx en reverse proxy : TLS et comparaison | LAB | ★★ | 2 |
| M07-E12 | Déployer les répartiteurs `lb01` et `lb02` | LAB | ★★★ | 2 |
| M07-E13 | Publier GitLab et NetBox derrière les répartiteurs | LIBRE | ★★★ | 2 |
| M07-E14 | Fabric leaf-spine : BGP unnumbered et ECMP | LAB | ★★★ | 2 |
| M07-E15 | Jumbo frames sur les réseaux de stockage | LAB | ★★ | 2 |
| M07-E16 | FRR sur la bordure : préparer le BGP de la plateforme | LAB | ★★★ | 2 |
| M07-E17 | Open vSwitch : bonds LACP, VLAN et miroir de port | LAB | ★★ | 2 |
| M07-E18 | Raccorder le site de Lyon en WireGuard | LAB | ★★ | 2 |
| M07-E19 | Routage dynamique à travers le tunnel | LIBRE | ★★★ | 2 |
| M07-E20 | Méthode de diagnostic réseau | LAB | ★★ | 2 |
| M07-E21 | Revue : les répartiteurs du stagiaire | REV | ★★ | 2 |
| M07-E22 | Runbook : maintenance d'un répartiteur | RED | ★★ | 2 |
| M07-E23 | Revue : la configuration BGP du prestataire | REV | ★★★ | 2 |
| M07-E24 | Une seconde passerelle : `gw02` | LAB | ★★★ | 3 |
| M07-E25 | VRRP sur les passerelles du lab | LAB | ★★★★ | 3 |
| M07-E26 | Bordure redondante côté WAN et VPN | LIBRE | ★★★★ | 3 |
| M07-E27 | Basculer sans couper les connexions : conntrackd | LAB | ★★★ | 3 |
| M07-E28 | HAProxy en production | LAB | ★★★ | 3 |
| M07-E29 | Superviser la bordure et les répartiteurs | LAB | ★★ | 3 |
| M07-E30 | La matrice des flux v2 | LAB | ★★ | 3 |
| M07-E31 | ADR : haute disponibilité de la bordure | RED | ★★ | 3 |
| M07-E32 | Tester et mesurer les bascules | LIBRE | ★★★ | 3 |
| M07-E33 | Questions de production : réseau et HA | Q | ★★★ | 3 |
| M07-E34 | Publier un nouveau service en temps limité | CHRONO | ★★★ | 3 |
| M07-E35 | Panne : la session BGP ne monte pas | BF | ★★★ | 4 |
| M07-E36 | Panne : Lyon ne joint plus Paris | BF | ★★ | 4 |
| M07-E37 | Panne : deux maîtres VRRP | BF | ★★★ | 4 |
| M07-E38 | Panne : les gros transferts se figent | BF | ★★★ | 4 |
| M07-E39 | Panne : 503 Service Unavailable | BF | ★★ | 4 |
| M07-E40 | Panne : l'agrégat a perdu un lien | BF | ★★ | 4 |
| M07-E41 | Panne : ça part mais ça ne revient pas | BF | ★★★ | 4 |
| M07-E42 | Panne : la fabric perd la moitié de son trafic | BF | ★★★ | 4 |
| M07-E43 | Astreinte : la bordure en panne | BF | ★★★★ | 4 |
| M07-E44 | Sous le capot : le voyage d'un paquet | LAB | ★★★ | 4 |
| M07-E45 | Questions expert : réseau et haute disponibilité | Q | ★★★ | 4 |
| M07-E46 | Mini-projet : socle MédiSphère v2 | LIBRE | ★★★ | 5 |

**Répartition** : 45 exercices + mini-projet · 9 break & fix · 4 questionnaires · 2 revues · 2 rédactions · 1 chronométré.

## Hôtes créés ou transformés dans ce module

| Hôte | VMID | Adresse | Rôle | Exercice |
|---|---|---|---|---|
| `lb01`, `lb02` | 1010, 1011 | 10.10.70.10, .11 (VIP 10.10.70.200) | HAProxy + keepalived, points d'entrée publiés | E12 |
| `gw01` | 1000 | `.1` → `.2` + VIP `.1` | FRR (AS 65000), keepalived, conntrackd, `wg2` | E16, E25-E27 |
| `gw02` | 1009 | `.3` sur chaque VLAN routé | Seconde passerelle | E24-E26 |
| Maquette | 2070-2079 | `vsandbox` + VNets `vfab1-8` | `net01`, `spine01-02`, `leaf01-02`, `srv01-02`, `lyo-gw01`, `lyo-pc01`, `hap01` | E03 |

Toutes les valeurs (VRID, AS, adresses de fabric, site LYO1, MTU) sont dans [`PLAN.md`](../../PLAN.md) §4.9.

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check 07 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break 07 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.
