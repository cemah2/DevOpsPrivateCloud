---
chg: CHG-3407
titre: "ceph-par1 : mise à jour sous charge (corrective Tentacle, ou système des hôtes en roulement)"
categorie: normal
statut: termine
decision: go
variante: systeme              # ceph-orch (nouvelle corrective publiée) | systeme (aucune corrective : Rocky 10 en roulement)
demandeur: Sophie Laurent
executant: équipe Plateforme
approbateurs: Claire Morel, Sophie Laurent
fenetre-debut: 2026-11-17T20:00:00+01:00
fenetre-fin: 2026-11-17T23:00:00+01:00
mesure-source: cluster
mesure-groupes: ""
mesure-debut: 2026-11-17T20:00:00+01:00
mesure-fin: 2026-11-17T22:15:00+01:00
mesure-objectif-s: 30
mesure-interruption-s: 0
---

# CHG-3407 — Ceph sous charge

> Fiche de **référence** (lab imaginé). Le jour J, regarde d'abord s'il existe une corrective Tentacle
> plus récente que 20.2.4 (notes de version, avis de sécurité) : si oui, variante **ceph-orch**
> (RB-082 du M08, sous la sonde) ; sinon variante **systeme** (ci-dessous). Dans les deux cas, le cluster
> ne s'arrête jamais et chaque hôte ou démon ne part que si le cluster dit que c'est sans danger.

## 1. Résumé

Aucune corrective Tentacle après 20.2.4 à la date de la fenêtre : on fait ce que l'audit HDS demande (« systèmes maintenus ») — mise à jour du système Rocky Linux 10 des trois hôtes de `ceph-par1`, un à la fois, sous la charge réelle du cluster (RBD des PVC de `k8s-par1`, RGW de Loki et Thanos) et sous la sonde.

## 2. Risque

| Risque | Probabilité | Gravité | Réduction | Signal |
|---|---|---|---|---|
| Écritures RBD bloquées pendant l'arrêt d'un hôte | faible | forte (bases, RabbitMQ) | réplication 3, `min_size` 2 : un hôte arrêté laisse 2 copies ; `maintenance enter` refuse si ce n'est pas sûr | sonde, `ceph health`, latence des PVC |
| Un hôte ne redémarre pas (noyau) | faible | moyenne (cluster dégradé, 2 copies) | console série (`qm terminal`), noyau précédent dans GRUB, sauvegarde PBS `par1/ceph` | `maintenance exit` impossible |
| Paquets Ceph mis à jour hors contrôle | moyenne sans précaution | moyenne | `cephadm`, `ceph-common` exclus (épinglés par `ceph_noeud`) | `cephadm version` |
| RGW : un démon sur deux pendant l'arrêt | certaine | faible (haproxy de l'ingress bascule) | 2 RGW derrière la VIP 10.10.30.200 | sonde `continuite-rgw`, erreurs d'écriture de Loki |

## 3. Impact attendu

Aucune coupure ; latence d'écriture en hausse pendant la reprise des PG (*recovery*) après chaque retour d'hôte. Cinder : profil openstack arrêté (le cluster k8s tourne) : non mesuré ici, il le sera pendant CHG-3408.

## 4. Fenêtre

Mardi 17/11/2026, 20 h-23 h ; environ 25 min par hôte (mise à jour, redémarrage, retour à `HEALTH_OK`).

## 5. Préparation

- [x] Notes de version Ceph : aucune corrective après 20.2.4 ; avis de sécurité lus.
- [x] Notes de mise à jour de Rocky Linux 10 (noyau, systemd, podman) : rien qui touche cephadm.
- [x] Sauvegarde PBS `par1/ceph` de la nuit vérifiée ; spécifications cephadm à jour dans `plateforme/ceph`.
- [x] `HEALTH_OK`, deux mgr, trois mon en quorum, `ceph orch host ls` sans hôte en maintenance.
- [x] Sonde lancée (RB-340) + groupe `continuite-rgw` ajouté sur `mon01` ; objectif 30 s.
- [x] Playbook `ceph-roulement-systeme.yml` essayé en `--check` (lecture) et sur `ceph03` d'abord.

## 6. Étapes

| # | Étape | Commande | Contrôle de passage | Heure réelle |
|---|---|---|---|---|
| 1 | Go/no-go | ligne de base 30 min, `ceph -s` | 0 s, `HEALTH_OK` | 20 h 00 |
| 2 | `ceph03` | `uv run ansible-playbook playbooks/ceph-roulement-systeme.yml --limit ceph03` | `HEALTH_OK`, sonde à 0 | 20 h 05 → 20 h 31 |
| 3 | `ceph02` | `--limit ceph02` | idem | 20 h 36 → 21 h 02 |
| 4 | `ceph01` (mgr actif : bascule) | `--limit ceph01` | idem | 21 h 07 → 21 h 40 |
| 5 | Après | `ceph orch ps`, `ceph versions`, drapeaux | aucun drapeau, aucune maintenance | 21 h 45 |

## 7. Critères d'abandon

> 30 s d'erreur cumulées ; un PG `inactive` ou `incomplete` ; `HEALTH_OK` non revenu 20 min après le retour d'un hôte : on ne touche pas à l'hôte suivant ; diagnostic (RB-343 §5).

## 8. Retour arrière

Pas de « retour » d'une mise à jour de paquets système en roulement : on démarre sur le noyau précédent (GRUB) si le nouveau pose problème, `dnf history undo` sur un paquet précis en dernier recours. Filet : PBS `par1/ceph` (restauration du disque système d'un hôte, testée au M08-E25). Variante ceph-orch : pause, analyse, reprise (`ceph orch upgrade pause|resume`) ; pas de retour à 20.2.4 une fois les moniteurs passés (RB-082).

## 9. Communication

J-2 : Julien, Inès, Nadia, Hugo (équipe Data : extraction nocturne décalée après 23 h).

## 10. Mesure de l'interruption

| Moment | Fenêtre | Secondes d'erreur cumulées | Requêtes en erreur (k6) | p95 MédiAgenda prod | Remarques |
|---|---|---|---|---|---|
| avant | 19 h 30 → 20 h 00 | 0 | 0 | 40 ms | |
| pendant | 20 h 00 → 22 h 15 | 0 | 0 | 71 ms | pointes de latence au retour de chaque hôte (*recovery* de 2 à 4 min) |
| après | 22 h 15 → 22 h 45 | 0 | 0 | 41 ms | |

Contrôles en plus de la sonde : aucune erreur d'écriture de Loki ni de Thanos (sidecar) dans leurs journaux ; `rbd perf image iostat` sans blocage ; 0 message perdu (files quorum RabbitMQ à 3 membres).

## 11. Journal

20 h 05 `ceph03` en maintenance (OSD 3, 7, 11 `noout`), 412 paquets, redémarrage 2 min 10 s ; `HEALTH_OK` à 20 h 31. 21 h 07 bascule du mgr de `ceph01` vers `ceph02`.

## 12. Clôture et revue

Réussi, 0 s ≤ 30 s. Action : PLAT-3407-1 « minuterie de mise à jour mensuelle des hôtes Ceph en changement standard (RB-343) ».
