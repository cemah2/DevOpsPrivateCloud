# CHG-855 — Passerelles virtuelles VRRP sur les VLAN du lab

| | |
|---|---|
| Ticket | PLAT-851 |
| Demandeur | Claire Morel |
| Exécutant | `<MOI>` ; relecture : Karim Benali ; information : Nadia Roussel, Sophie Laurent |
| Créneau | `<DATE>`, 9 h 00 – 13 h 00 (aucune sauvegarde PBS planifiée ; pipelines suspendus de 9 h 30 à 12 h 30) |
| Risque | Élevé : toutes les VLAN routées du lab. Coupure attendue ≈ 4 s par VLAN, une VLAN à la fois |
| Statut | Préparé → relu → **exécuté** → clos |

## Objectif

La passerelle de chaque VLAN routé devient une adresse virtuelle VRRP (`.1`), portée par `gw01` (`.2`, priorité 150) ou `gw02` (`.3`, priorité 100). Aucun client ne change de configuration.

## Plan

| VLAN | Nom | VRID | VIP | `gw01` | `gw02` | Ordre |
|---|---|---|---|---|---|---|
| 99 | SANDBOX | 99 | 10.10.99.1 | 10.10.99.2 | 10.10.99.3 | 1 |
| 70 | DMZ | 70 | 10.10.70.1 | 10.10.70.2 | 10.10.70.3 | 2 |
| 60 | PROV | 60 | 10.10.60.1 | 10.10.60.2 | 10.10.60.3 | 3 |
| 52 | OS-EXT | 52 | 10.10.52.1 | 10.10.52.2 | 10.10.52.3 | 4 |
| 50 | OS-API | 50 | 10.10.50.1 | 10.10.50.2 | 10.10.50.3 | 5 |
| 40 | K8S | 40 | 10.10.40.1 | 10.10.40.2 | 10.10.40.3 | 6 |
| 30 | STOR-PUB | 30 | 10.10.30.1 | 10.10.30.2 | 10.10.30.3 | 7 |
| 20 | INFRA | 20 | 10.10.20.1 | 10.10.20.2 | 10.10.20.3 | 8 |
| 10 | MGMT | 10 | 10.10.10.1 | 10.10.10.2 | 10.10.10.3 | 9 |

Ordre : d'abord la sandbox (aucun service), puis les VLAN vides ou presque (DMZ : `lb01`/`lb02` survivent à 4 s ; PROV, OS-*, K8S, STOR-PUB n'hébergent rien de permanent à ce stade), puis INFRA (DNS, forge, PKI : un pipeline interrompu se relance), et MGMT en dernier (`adm01`, depuis la session WAN).

Paramètres : VRRP v3, unicast (`unicast_src_ip` propre, pair = l'autre passerelle), `advert_int 1`, état initial `BACKUP` sur les deux, **`nopreempt`** ; groupe de synchronisation `BORDURE` (suit ens18 et ens19) **constitué à la fin**, une fois les neuf instances en place des deux côtés. Pendant la migration, le groupe est désactivé (`bordure_groupe_actif: false`) : au rechargement, keepalived ne laisse un groupe `MASTER` que si **tous** ses membres l'étaient, et une instance nouvelle ajoutée à un groupe maître ferait retomber toutes les VIP déjà migrées (essai fait avec keepalived 2.2 : ≈ 3 s sans aucune VIP).

**Choix de préemption.** Avec préemption, une panne de `gw01` coûte **deux** bascules (départ, puis retour dès que `gw01` revient, peut-être en plein redémarrage de ses services ou en boucle si elle est instable) ; avec `nopreempt`, une seule, et le retour sur `gw01` se fait par RB-071, de jour, quand on l'a décidé. Prix : après un incident, `gw02` (identique) reste active jusqu'au retour planifié, et la supervision (M07-E29) le signale. `preempt_delay` (retour retardé) a été écarté : il garde la seconde bascule, seulement plus tard.

## Prérequis (cochés le jour J)

- [ ] Instantanés : `ms-snapshot --prefix avant-m07 1000 1009`.
- [ ] Accès de secours : console noVNC de 1000 et 1009 ouvertes ; SSH `admin@<IP-GW01-WAN>` et `admin@<IP-GW02-WAN>` ouverts depuis `pve01`.
- [ ] `sysctl net.ipv4.conf.all.promote_secondaries` = 1 sur `gw01`.
- [ ] Préparation (étape 3 de l'exercice) appliquée et vérifiée : `.2` présente partout sur `gw01`, DNS et NetBox à jour, BGP de `leaf01` sur `.2`/`.3`, relais et NTP sur adresses propres, VRRP autorisé dans la matrice des deux passerelles.
- [ ] keepalived installé et actif sur les deux passerelles, sans instance (`keepalived_vlans_vrrp: []`), groupe désactivé (`bordure_groupe_actif: false`).
- [ ] Mesures prêtes : `sudo ping -D -i 0.1 <cible>` depuis une VM du VLAN migré vers 10.10.20.10, et depuis `adm01` vers cette VM.

## Étapes (une par VLAN, dans l'ordre du plan)

| # | Action | Vérification | Retour arrière |
|---|---|---|---|
| 1 | MR : V retiré de `routeur_reseau_vip_statique` (gw01), ajouté à `keepalived_vlans_vrrp` (gw01, gw02) | pipeline vert (lint, `--check`) | fermer la MR |
| 2 | Job manuel `migration-vrrp` (`-e vlan=V`) | VIP sur `gw01`, instance V `BACKUP` sur `gw02`, perte mesurée ≤ 5 s | automatique dans le playbook (`.1` reposée) ; sinon : `ip address replace 10.10.V.1/24 dev ens19.V` sur `gw01`, puis MR inverse et `routeurs.yml --limit gw01,gw02` |
| 3 | Tests : `ping`, `dig`, SSH, `apt update` sur une VM du VLAN ; ARP de la VM | même MAC qu'avant pour `.1` ; VIP des VLAN déjà migrés inchangées | idem étape 2 |

**Après le VLAN 10** : MR `bordure_groupe_actif: true`, puis `playbooks/groupe-bordure.yml` (passerelle de secours d'abord) : il refuse de continuer si une passerelle porte une partie seulement des VIP, recharge, vérifie que rien n'a bougé et initialise `/run/bordure/etat`. Retour arrière : `bordure_groupe_actif: false` et `routeurs.yml` (la disparition du groupe ne change l'état d'aucune instance).

**Critères d'arrêt** : perte > 10 s sur un VLAN ; VIP présente sur les deux passerelles ; perte de la session WAN de secours ; tout comportement non expliqué. On s'arrête, on revient sur le VLAN en cours, on garde les VLAN déjà migrés (ils sont indépendants), on analyse.

## Compte rendu

| VLAN | Heure | Perte mesurée (VM → INFRA) | Perte (`adm01` → VM) | Remarque |
|---|---|---|---|---|
| 99 | 09 h 41 | 3,6 s | 3,7 s | MAC inchangée ; une alerte `ms-verif-services` (ping DHCP) sans suite |
| 70 | 09 h 58 | 3,5 s | — | |
| … | | | | |
| 10 | 11 h 52 | 3,6 s (depuis `adm01` vers 10.10.20.10) | — | migré depuis la session WAN |

Écarts : `<À REMPLIR>`. Bascule complète (étape 8) : `<pertes mesurées>` ; `adm01` → `pve01` ne revient pas tant que `pve01` route par `<IP-GW01-WAN>` (traité par CHG-856, M07-E26). Instantanés supprimés le `<DATE>`.
