# Module 27 — Données et messagerie

| | |
|---|---|
| **Bloc** | G — Services de plateforme |
| **Niveau** | Secondaire |
| **Profil de lab** | Socle v5 + `ceph-par1` + `k8s-par1` (≈ 111 Go) ; Kafka `kafka-essai` (≈ 4,5 Gi dans les travailleurs) de E09 à la fin de E10 ; `pg-patroni01..03` (2271-2273, 3 × 1 Go) le temps de E13 |
| **Prérequis** | Module 26 (`durcissement-v1`) ; module 16 (CloudNativePG, plugin Barman Cloud, `mediagenda-db`) ; module 20 (Argo CD, hooks de migration) ; module 25 (OpenBao, rôles dynamiques PostgreSQL, External Secrets) ; module 12 (image de MédiNotif) ; module 21 (supervision) |
| **Durée indicative** | 40 à 50 heures (palier 1 : 8-10 h ; palier 2 : 12-15 h ; palier 3 : 10-12 h ; palier 4 : 6-8 h ; mini-projet : 4-6 h) |

## Contexte MédiSphère

Les patients prennent rendez-vous, mais personne ne leur confirme rien : MédiNotif, construit au module 12, n'a jamais quitté `ctr01`. La base de MédiAgenda tourne dans CloudNativePG depuis le module 16, mais chaque connexion de l'API ouvre un processus PostgreSQL, les migrations sont un script maison, et le Valkey de recette date d'avant la montée en 9. Julien Petit veut des notifications fiables (« un SMS de rappel perdu, c'est un patient qui ne vient pas »), Nadia Roussel veut savoir quoi faire quand le primaire tombe pendant l'astreinte, et Karim Benali veut qu'on arrête de débattre de Kafka à chaque comité d'architecture : on l'essaie, on mesure, on écrit la décision.

## Objectifs

À la fin de ce module, tu sais :
- exploiter PostgreSQL dans Kubernetes avec CloudNativePG au-delà de l'installation : rôles et bases déclaratifs, *pooler* PgBouncer, bascules, mises à jour, réplica de secours, supervision ; comparer avec Patroni sur VMs ;
- versionner un schéma avec **Flyway** et livrer des migrations qui ne cassent pas la version précédente de l'application ;
- exploiter **Valkey** comme cache : montée de version, ACL, TLS, éviction ;
- déployer **RabbitMQ** par ses opérateurs, déclarer sa topologie (vhosts, utilisateurs, files quorum, rebut) et y brancher MédiNotif et MédiAgenda ;
- déployer **Kafka** avec Strimzi (KRaft), le comparer à RabbitMQ et à NATS, et décider par écrit ;
- diagnostiquer des écritures bloquées, un consommateur arrêté, une migration verrouillée, un cache inutilisable.

## Carte des exercices

| ID | Titre | Type | Diff. | Palier |
|---|---|---|---|---|
| M27-E01 | Test de positionnement : données et messagerie | Q | ★★ | 1 |
| M27-E02 | CloudNativePG en profondeur : rôles, bases et *pooler* | LAB | ★★ | 1 |
| M27-E03 | RabbitMQ par l'opérateur : la grappe `messagerie/rabbitmq` | LAB | ★★ | 1 |
| M27-E04 | Topologie déclarative et MédiNotif en recette | LAB | ★★ | 1 |
| M27-E05 | Flyway : reprendre les migrations de MédiAgenda | LAB | ★★ | 1 |
| M27-E06 | Migrations sans interruption : *expand/contract* | LAB | ★★★ | 2 |
| M27-E07 | Valkey 9 : montée de version, ACL, TLS et éviction | LAB | ★★★ | 2 |
| M27-E08 | MédiAgenda publie les notifications, MédiNotif en production | LIBRE | ★★★ | 2 |
| M27-E09 | Kafka avec Strimzi : KRaft, pools de nœuds, *topics* et utilisateurs | LAB | ★★★ | 2 |
| M27-E10 | MédiNotif sur Kafka : *offsets*, rebut, comparaison, puis retrait | LAB | ★★★ | 2 |
| M27-E11 | Revue : les manifestes de données du stagiaire | REV | ★★ | 2 |
| M27-E12 | Runbook : maintenance et bascule de PostgreSQL | RED | ★★ | 2 |
| M27-E13 | Patroni sur VMs : l'autre façon de faire | LAB | ★★★ | 3 |
| M27-E14 | Superviser les données et la messagerie | LAB | ★★★ | 3 |
| M27-E15 | Reprise et montée de version : réplica de secours, RabbitMQ 4.4 | LAB | ★★★ | 3 |
| M27-E16 | Performance et dimensionnement : pgbench, perf-test, *pooler* | LAB | ★★★ | 3 |
| M27-E17 | ADR : données et messagerie de MédiSphère | RED | ★★ | 3 |
| M27-E18 | Questions de production : données et messagerie | Q | ★★★ | 3 |
| M27-E19 | Panne : les écritures de MédiAgenda sont bloquées | BF | ★★★ | 4 |
| M27-E20 | Panne : MédiNotif ne consomme plus | BF | ★★ | 4 |
| M27-E21 | Panne : la migration bloque la mise en production | BF | ★★★ | 4 |
| M27-E22 | Panne : le cache ne sert plus | BF | ★★ | 4 |
| M27-E23 | Astreinte : des rendez-vous sans notification | BF | ★★★★ | 4 |
| M27-E24 | Sous le capot : réplication synchrone, WAL et Raft des files quorum | LAB | ★★★★ | 4 |
| M27-E25 | Mini-projet : les données et la messagerie de MédiSphère v1 | LIBRE | ★★★ | 5 |

**Répartition** : 24 exercices + mini-projet · 5 break & fix · 2 questionnaires · 1 revue · 2 rédactions.

## Hôtes et composants créés dans ce module

| Élément | Où | Rôle | Exercice |
|---|---|---|---|
| Pooler PgBouncer `mediagenda-db-pooler-rw` | `mediagenda-recette`, `mediagenda-prod` | Réserve de connexions devant `mediagenda-db` | E02 |
| Cluster Operator 2.23, Messaging Topology Operator 1.20 | espace `rabbitmq-system` (manifestes amont dans `plateforme/donnees`) | Opérateurs RabbitMQ | E03 |
| RabbitMQ 4.3 `rabbitmq` (3 nœuds) | espace `messagerie`, `https://rabbitmq.apps.par1.medisphere.internal` | Messagerie de MédiSphère | E03 |
| MédiNotif | espaces `medinotif-recette`, `medinotif-prod` (dépôt `medinotif/deploiement`, ApplicationSet `medinotif`) | Notifications | E04, E08 |
| Flyway 13 | Job de migration de MédiAgenda (hook Argo CD) | Migrations de schéma | E05 |
| Strimzi 1.3, Kafka 4.3.1 `kafka-essai` | espace `kafka-essai` | Comparaison, **retiré** à la fin de E10 | E09 |
| `pg-patroni01..03` | VMs 2271-2273, `vsandbox` 10.10.99.71-73 | Comparaison Patroni, **détruites** en fin d'exercice | E13 |
| `mediagenda-db-secours` | espace `mediagenda-secours` | Réplica de secours alimenté par le stockage objet | E15 |

Détails figés : [`PLAN.md`](../../PLAN.md) §4.13. Versions : [`annexes/versions-bloc-G.md`](../../annexes/versions-bloc-G.md). Fiche : [`annexes/decouverte/nats.md`](../../annexes/decouverte/nats.md).

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check 27 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break 27 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.
