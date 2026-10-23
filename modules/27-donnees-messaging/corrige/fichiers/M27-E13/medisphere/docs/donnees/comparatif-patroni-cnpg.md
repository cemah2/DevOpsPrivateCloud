# Patroni sur VMs ou CloudNativePG : comparaison (M27-E13, PLAT-2813)

| | |
|---|---|
| Date de l'essai | <AAAA-MM-JJ> |
| Patroni | 4.1.5 (PyPI, `/opt/patroni`), etcd du paquet Debian 13 (API v3), PostgreSQL 18.x (PGDG), 3 VMs `pg-patroni01..03` (2271-2273, 1 vCPU, 1 Go), HAProxy 5000 sur `pg-patroni01` |
| CloudNativePG | 1.30.x, `mediagenda-db` de recette (3 instances, `ceph-rbd`), mesures de M16-E25 refaites le même jour |
| Code de l'essai | `plateforme/infra` `envs/m27/`, `plateforme/donnees` `patroni-essai/` (VMs détruites le <AAAA-MM-JJ>) |

> Les valeurs ci-dessous sont celles du lab de référence : **remplace-les par tes mesures**.

## Ce qu'on a fait tourner

```
postgres@pg-patroni01:~$ /opt/patroni/bin/patronictl -c /etc/patroni/patroni.yml list
+ Cluster: pg-essai (7562301938446712345) ---------+----+-------------+-----+------------+-----+
| Member       | Host        | Role         | State     | TL | Receive LSN | Lag | Replay LSN | Lag |
+--------------+-------------+--------------+-----------+----+-------------+-----+------------+-----+
| pg-patroni01 | 10.10.99.71 | Leader       | running   |  1 |             |     |            |     |
| pg-patroni02 | 10.10.99.72 | Sync Standby | streaming |  1 |   0/4000168 |   0 |  0/4000168 |   0 |
| pg-patroni03 | 10.10.99.73 | Replica      | streaming |  1 |   0/4000168 |   0 |  0/4000168 |   0 |
+--------------+-------------+--------------+-----------+----+-------------+-----+------------+-----+
```

Dans etcd (`etcdctl get --prefix /service/pg-essai/ --keys-only`) : `config` (configuration commune, écrite par `bootstrap.dcs` puis par `patronictl edit-config`), `initialize` (identifiant du système), `leader` (clé à bail, renouvelée à chaque boucle par le primaire), `members/<nom>` (état publié par chaque nœud), `status` (dernier LSN connu, créneaux), `sync` (réplica synchrone désigné), `history` (changements de *timeline*).

## Mesures

Témoin : boucle d'`INSERT` toutes les 200 ms (horodatée côté client), par HAProxy (Patroni) et par le Service `mediagenda-db-rw` (CNPG).

| Opération | Patroni (HAProxy) | CloudNativePG (`-rw`) |
|---|---|---|
| Bascule planifiée (`patronictl switchover` / `kubectl cnpg promote`) | 6,8 s d'écritures en échec (arrêt propre, promotion, `GET /primary` vu par HAProxy en 2 × `inter 2s`) | 4,1 s (arrêt rapide, promotion, Service `-rw` repointé par l'opérateur) |
| Bascule sur panne (primaire tué) | 31 s (expiration de la clé `leader`, `ttl: 30`, + course au verrou + promotion + détection HAProxy) | 12 s (sonde de disponibilité, bail du primaire de 15 s, promotion) |
| Écritures validées perdues | 0 (`synchronous_mode: true`) | 0 (`dataDurability: required`) |
| Retour de l'ancien primaire | `pg_rewind` automatique (`use_pg_rewind`) puis réplica | `pg_rewind` par le gestionnaire d'instance, ou reclonage |
| `pause` puis arrêt de PostgreSQL sur le primaire | Patroni ne fait **rien** (mode maintenance) : écritures en échec jusqu'au `resume` | pas d'équivalent exact : `cnpg.io/reconciliationLoop: disabled` arrête l'opérateur, `kubectl cnpg maintenance set` déclare une fenêtre de maintenance des nœuds (`nodeMaintenanceWindow`) |

`patronictl failover --candidate pg-patroni03` sur une grappe saine : accepté (avec `--force`), Patroni avertit et promeut ; c'est une bascule sans contrôle de retard, d'où le conseil de la documentation (`switchover` sur une grappe saine, `failover` seulement sans *leader* ou sans réplica synchrone).

## Comparaison

| Critère | Patroni sur VMs | CloudNativePG |
|---|---|---|
| Consensus et élection | DCS externe (etcd, Consul, ZooKeeper) ; clé `leader` à bail ; seul le réplica synchrone peut se promouvoir en `synchronous_mode` | API Kubernetes ; bail `Lease` du primaire (1.30) ; l'opérateur choisit le réplica le plus avancé ; `failoverQuorum` en option |
| Clôture de l'ancien primaire | Patroni rétrograde son PostgreSQL s'il perd le DCS ; chien de garde (`watchdog`) en option contre un Patroni figé | arrêt de l'ancien primaire avant promotion ; contrôle d'isolement (sonde de vivacité) ; le pod perd ses Services |
| Point d'accès | **à construire** : HAProxy + `GET /primary`, ou vip-manager (VIP selon la clé `leader`), ou client multi-hôtes | Services `-rw`, `-ro`, `-r`, *pooler* intégré |
| Sauvegarde et PITR | à construire (pgBackRest, Barman) | plugin Barman Cloud, `ScheduledBackup`, restauration déclarative |
| Mises à jour | mineure : nœud par nœud, à la main ou par Ansible ; majeure : `pg_upgrade` orchestré à la main | mineure : `imageName` (redémarrage progressif + bascule) ; majeure : `pg_upgrade` en place déclaratif ou import |
| Déclaratif | configuration Patroni + Ansible ; rôles et bases à la main ou par Ansible (`bootstrap.users` supprimé en 4.0) | `Cluster`, `managed.roles`, `Database`, `Pooler` dans Git |
| Supervision | API REST `/metrics` de Patroni + `postgres_exporter` à installer | exportateur intégré (9187), PodMonitor |
| Sécurité | TLS d'etcd, de l'API REST et de PostgreSQL à poser soi-même | TLS de PostgreSQL et des réplications par défaut (CA de l'opérateur ou cert-manager) |
| Ressources et exploitation | 3 VMs (OS, correctifs, sauvegardes PBS, durcissement M26) + etcd à exploiter | 3 pods ; l'opérateur est une dépendance de plus (montées de version de l'opérateur) |
| Hors Kubernetes | oui : c'est son domaine | non |

Ce qu'il faudrait construire autour de Patroni pour atteindre le niveau de service actuel de `mediagenda-db` : deux HAProxy + keepalived (ou vip-manager), pgBackRest vers `s3-01` avec PITR et tests de restauration, TLS partout (step-ca), `postgres_exporter` et règles d'alerte, rôle Ansible de mise à jour mineure, procédure de montée majeure, intégration à OpenBao (identifiants dynamiques : déjà possible), et l'exploitation de trois VMs de plus (correctifs, durcissement, sauvegardes).

## Conclusion

CloudNativePG reste notre choix pour les bases des applications du cluster : à niveau de service égal, il évite de construire et d'exploiter le point d'accès, la sauvegarde et le TLS, et nos mesures ne montrent aucun désavantage (bascules plus courtes, même RPO nul). Patroni reste la bonne réponse pour une base **hors** Kubernetes (par exemple si Legacy-RDV migrait vers PostgreSQL sur VM) : le code de l'essai est gardé à cette fin. Décision consignée dans l'ADR-0270.
