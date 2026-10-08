# CHG-1059 — Mise à jour mineure et de sécurité de `hv-par1` (changement standard)

| | |
|---|---|
| Type | **Standard** (pré-approuvé par le comité de changement le 2026-10-XX ; revu chaque année) |
| Propriétaire | Équipe Plateforme (Claire Morel) |
| Procédure | [RB-092](../runbooks/RB-092-mettre-a-jour-hv-par1.md), sections 1 à 4 |
| Fréquence | mises à jour de sécurité : chaque semaine (mardi 14:00-16:00) ; mineures : à la sortie, après 7 jours de recul |
| Impact attendu | aucun pour les VMs HA et les VMs migrables ; VMs non migrables (disque local non répliqué) : arrêt annoncé 48 h avant |

## Périmètre

**Inclus (pré-approuvé)** : paquets des dépôts configurés de Proxmox VE 9.x (`pve-no-subscription`) et Ceph de la version **majeure en cours** (Tentacle 20.2.x), Debian 13 (sécurité et point release) ; nouveau noyau de la **même** série ; redémarrage des nœuds un par un.

**Exclu (changement normal, fiche dédiée)** : version majeure de Proxmox VE ou de Ceph (ex. 9 → 10, Tentacle → suivante) ; changement de série de noyau ou d'option d'amorçage ; modification de configuration (réseau, Corosync, stockage, HA) ; toute mise à jour dont les notes de version signalent une action manuelle ou un « known issue » qui touche le cluster ; ajout ou retrait de dépôt.

## Conditions préalables (toutes, avec leur preuve)

| # | Condition | Preuve |
|---|---|---|
| 1 | Cluster sain | `ms-verif-cluster` code 0 dans l'heure ; `pvecm status` quorate 3/3 ; `ceph -s` `HEALTH_OK` |
| 2 | Sauvegardes à jour | dernier job vzdump OK (< 26 h) ; sauvegarde de configuration des 3 nœuds OK (`systemctl show -p Result wb-backup-socle.service` = `success`) |
| 3 | Contenu connu | `apt list --upgradable` sur un nœud, collé au compte rendu : **aucun** paquet hors périmètre (sinon : changement normal) |
| 4 | Notes de version lues | lien et date dans le compte rendu ; aucun point « action required » |
| 5 | Place disque | `/` et `/boot` des nœuds : > 2 Gio libres ; `proxmox-boot-tool status` sans erreur |
| 6 | Capacité | `ms-capacite-cluster` : `SAIN` (un nœud en maintenance doit pouvoir être absorbé) |
| 7 | Pas de sauvegarde ni réplication en cours, pas d'autre changement dans la fenêtre | `pvesr status`, calendrier des changements |

## Déroulé

RB-092 § 2 (ordre des nœuds) et § 3 (un nœud), puis § 4 (contrôle final). Chaque nœud est terminé (contrôles verts) avant le suivant.

## Critères de réussite

- `pveversion -v` identique sur les trois nœuds, versions attendues.
- `ms-verif-cluster` code 0 ; `ceph versions` homogène ; aucune ressource HA en `error`.
- Sondes de coupure (VMs témoins 120/121) : 0 s d'interruption.

## Critères d'arrêt (on s'arrête, on stabilise, on bascule en changement normal ou en incident)

| Observation | Commande |
|---|---|
| Un nœud ne revient pas dans le cluster dans les 10 min après redémarrage | `pvecm status` |
| Ceph pas revenu en `HEALTH_OK` (hors `noout` attendu) 15 min après le retour du nœud | `ceph -s`, `ceph health detail` |
| Une ressource HA en `error` ou une migration en échec | `ha-manager status`, journal de tâche |
| `apt` propose de **supprimer** un paquet `proxmox-ve`, `pve-*` ou `ceph-*` | sortie de `apt full-upgrade` (simulation `-s`) |
| Tout avertissement non décrit dans RB-092 | — |

## Retour arrière

Réel : démarrer le nœud sur le **noyau précédent** (épinglé par `proxmox-boot-tool kernel pin`) ; revenir à une version de paquet précédente reste possible pour un paquet isolé (`apt install <paquet>=<version>` si elle est encore dans le dépôt) mais **n'est pas** une procédure standard. Non réversible : une montée de version de démon Ceph après redémarrage ; un schéma de base modifié. D'où les critères d'arrêt **avant** le nœud suivant : on ne laisse jamais plus d'un nœud dans un état douteux.

## Communication

Annonce 48 h avant (canal Plateforme, équipes concernées par d'éventuelles VMs non migrables) ; message de début et de fin ; compte rendu ci-dessous.

## Compte rendu (répétition du 2026-10-XX)

| Heure | Nœud | Versions avant → après | Durée | Incidents |
|---|---|---|---|---|
| 14:05 | `hv03` | pve-manager 9.2.x → 9.2.y ; noyau 6.17.x → 6.17.y | 14 min | aucun |
| 14:21 | `hv02` | idem | 15 min | `fence01` migrée vers `hv03`, revenue à la fin |
| 14:38 | `hv01` (maître HA, VIP) | idem | 16 min | bascule du maître HA et de la VIP (2 s sans VIP) |

Sondes de coupure : 0 s. `ms-verif-cluster` : vert à 14:56.
