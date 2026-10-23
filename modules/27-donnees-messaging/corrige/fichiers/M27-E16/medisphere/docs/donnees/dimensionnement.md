# Dimensionnement des données et de la messagerie (M27-E16, PLAT-2816)

| | |
|---|---|
| Date | <AAAA-MM-JJ> |
| Banc PostgreSQL | `wb-essais/bench-essai` (1 instance, 1 CPU / 1 Gi, `ceph-rbd`, PostgreSQL 18.6) et `bench-essai-pooler-rw` (PgBouncer 1.26.1 épinglé comme en M27-E02, mode `transaction`, `default_pool_size` 10, `max_db_connections` 40) ; `pgbench` échelle 20 (2 M de lignes) depuis un pod du même espace |
| Banc RabbitMQ | `wb-essais/rabbitmq-essai` (3 nœuds, 4.3.7, 1 CPU / 768 Mi, `ceph-rbd`) ; `rabbitmq-perf-test` 2.25.0 ; file quorum, messages persistants de 1 Kio |
| Manifestes | `plateforme/donnees/outils/banc/` (banc retiré le <AAAA-MM-JJ>) |

> Chiffres du lab de référence (Ceph partagé, travailleurs de 4 vCPU) : remplace-les par les tiens. Ce qui compte, ce sont les **rapports** et leur explication.

## PostgreSQL : direct ou par le *pooler*

| Mesure (60 s, TPC-B par défaut) | TPS | Latence moyenne | p95 | Connexions côté PostgreSQL |
|---|---|---|---|---|
| direct, `-c 20` | 612 | 32,6 ms | 61 ms | 20 (+ système) |
| *pooler*, `-c 20` | 585 | 34,1 ms | 66 ms | 10 |
| direct, `-c 80` | 655 | 122 ms | 240 ms | 80 (à 18 de `max_connections`) |
| *pooler*, `-c 80` | 634 | 125 ms | 238 ms | **10** (70 clients attendent dans PgBouncer : `cl_waiting`) |
| direct, `-c 20 -C` | 88 | 227 ms | 410 ms | jusqu'à 20, créées et détruites à chaque transaction |
| *pooler*, `-c 20 -C` | 466 | 43 ms | 87 ms | 10, stables |

**Lecture.**
- Sans `-C`, le *pooler* coûte un aller-retour réseau de plus et un passage dans PgBouncer : 3 à 4 % de TPS et ~1 ms. C'est le prix, et il est faible.
- À 80 clients, PostgreSQL direct tient encore mais chaque connexion est un processus (≈ 5 à 10 Mio, plus `work_mem` par opération) et on frôle `max_connections` : un pic de plus, et les connexions sont **refusées**. Par le *pooler*, 10 connexions serveur suffisent pour le même débit : le goulot est le disque (Ceph), pas le nombre de connexions.
- Avec une connexion par transaction (`-C` : comportement d'un client sans réserve de connexions, d'un Job, d'un script), le direct s'effondre (×5 en TPS) : création d'un processus, échange SCRAM et TLS à chaque fois. Le *pooler* absorbe ce coût : la connexion client est légère, la connexion serveur reste ouverte.

**Ce qui casse en mode transaction** (étape 3) : tout ce qui suppose que deux transactions successives d'un client tombent sur la même connexion serveur : `SET` de session (utiliser `SET LOCAL` dans la transaction), tables temporaires au-delà d'une transaction, verrous consultatifs de **session** (`pg_advisory_lock` ; les `pg_advisory_xact_lock` vont bien), `LISTEN/NOTIFY`, curseurs `WITH HOLD`. Les requêtes préparées **par protocole** (`-M prepared`) marchent depuis PgBouncer 1.21 si `max_prepared_statements` est non nul (100 sur le banc) ; `PREPARE` en SQL, non. psycopg 3 prépare automatiquement une requête jouée 5 fois (`prepare_threshold`) : avec `max_prepared_statements: 0`, MédiAgenda verrait des erreurs `prepared statement "_pg3_0" does not exist`. Le *pooler* de M27-E02 ne pose pas ce paramètre : la valeur par défaut de PgBouncer s'applique (non nulle dans les versions récentes : lis-la dans `SHOW CONFIG;` de ta 1.26.1) ; ne jamais le mettre à 0.

Version de PgBouncer servie (`kubectl -n mediagenda-prod exec deploy/mediagenda-db-pooler-rw -c pgbouncer -- pgbouncer --version`) : 1.26.1, épinglée en M27-E02 (trois CVE corrigées en 1.26).

## RabbitMQ : confirmations et `prefetch`

| Mesure (60 s, 1 producteur sauf mention) | Publication (msg/s) | Consommation (msg/s) | Latence p50 / p95 / p99 |
|---|---|---|---|
| sans confirmation (`-c -1`), 1 consommateur `-q 1` | 9 800 | 1 650 | la file grossit : latence sans signification |
| `-c 1` (attend chaque confirmation), `-q 1` | 410 | 410 | 2,3 / 4,1 / 9,8 ms |
| `-c 100`, `-q 1` | 7 200 | 1 700 | file qui grossit |
| `-c 100`, `-q 50` | 7 100 | 6 900 | 11 / 24 / 48 ms |
| `-c 100`, 3 consommateurs `-q 50` | 7 000 | 7 000 | 9 / 19 / 41 ms |

**Lecture.**
- Une file quorum ne confirme un message qu'une fois écrit (et `fsync`) sur la **majorité** des membres : avec `-c 1`, chaque publication paie un aller-retour réseau + une écriture disque répliquée (~2,4 ms ici). C'est exactement le cas de MédiAgenda, qui publie un message par requête et attend sa confirmation : **~400 publications par seconde et par connexion**, très loin du besoin.
- Avec des confirmations en vol (`-c 100`), le débit est multiplié par ~17 : le courtier regroupe les écritures.
- Avec `prefetch` 1, le consommateur attend chaque message après son acquittement (un aller-retour par message) : ~1 700 msg/s au mieux pour perf-test, qui ne fait rien du message. MédiNotif passe ~50 ms par envoi (`MEDINOTIF_DELAI_ENVOI_MS`, demain la passerelle SMS) : c'est **son** traitement qui borne son débit (~20 msg/s par réplica), pas le `prefetch`. Monter le `prefetch` de MédiNotif n'apporterait rien et augmenterait les redélivrances à l'arrêt d'un pod : on le garde à 1 et on ajoute des réplicas.

## Besoin et marge pour janvier

| Hypothèse (Julien Petit) | Aujourd'hui | Janvier |
|---|---|---|
| Rendez-vous par jour | 3 000 | 12 000 |
| Pointe : 10 % du jour en une heure | 300/h = 0,08/s | 1 200/h = 0,33/s |
| Notifications (2 par rendez-vous) en pointe | 0,17 msg/s | 0,67 msg/s |
| Rappels de la veille (lot de 18 h, 1 par rendez-vous du lendemain, en 10 min) | 5 msg/s | 20 msg/s |

- **RabbitMQ** : 20 msg/s en pointe contre ~400 msg/s **par connexion** confirmée une à une : marge × 20 sans rien changer. La grappe n'est pas le sujet ; la **passerelle SMS** et MédiNotif le sont : à 50 ms par envoi, 20 msg/s demandent **1 réplica** au minimum, **2** pour la tolérance (déjà le cas), 3 si l'envoi réel dépasse 100 ms. KEDA (M28) ajustera.
- **PostgreSQL** : 0,33 création/s + lectures (créneaux en cache) : quelques dizaines de transactions par seconde, contre ~600 mesurées. Marge confortable.
- **Connexions** : API de production 3 réplicas × 10 (réserve psycopg) = 30 connexions **client** au *pooler*, + Job de migration (1 à 2), + OpenBao (≤ 10, `connectionLimit`), + supervision. Côté serveur, `default_pool_size` vaut **par couple base/utilisateur** : avec les identifiants dynamiques d'OpenBao (M25), chaque pod de l'API a **son** utilisateur PostgreSQL, donc sa réserve. Trois réplicas = jusqu'à 3 × 10 = 30 connexions serveur, deux fois plus pendant le recouvrement de deux identifiants, plus celles des anciens utilisateurs pendant une rotation (jusqu'à `server_idle_timeout`). Le plafond se pose par base : `max_db_connections`.

## Réglages recommandés

| Réglage | Valeur | Raison |
|---|---|---|
| `max_connections` (PostgreSQL) | 100 (inchangé) | 40 (pooler, `max_db_connections`) + 10 (OpenBao) + migration + supervision + réplication + marge de bris de glace |
| `default_pool_size` | 10 (inchangé, M27-E02) | les mesures ne montrent aucun gain au-delà (goulot disque) |
| `max_db_connections` | 40 (inchangé, M27-E02) | plafond par base, quel que soit le nombre d'utilisateurs dynamiques : 40 + OpenBao + migration + supervision < `max_connections` |
| `max_client_conn` | 200 (inchangé), 500 si l'HPA (M28) dépasse 10 réplicas | 30 aujourd'hui ; coût mémoire négligeable dans PgBouncer |
| `max_prepared_statements` | défaut de PgBouncer 1.26 (non nul, vérifié par `SHOW CONFIG`) ; jamais 0 | requêtes préparées automatiques de psycopg 3 |
| `prefetch` de MédiNotif | 1 | voir plus haut |
| Réplicas de MédiNotif (prod) | 2, puis KEDA (M28) | tolérance d'un pod ; débit borné par l'envoi |

## Limites de la mesure

Un seul banc, une seule fois, sur un Ceph **partagé** avec le reste du lab (variance d'un jour à l'autre : refaire 3 fois avant de comparer finement) ; perf-test ne fait aucun travail par message ; le TPC-B de `pgbench` n'est pas la charge de MédiAgenda (plus de lectures, transactions plus courtes) ; réseau du lab sans contention. Les ordres de grandeur sont solides ; les pourcentages, non.
</content>
</invoke>
