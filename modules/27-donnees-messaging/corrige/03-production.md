# Module 27 — Palier 3 : Production — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Points non testés en conditions réelles** (signale tes retours, ils corrigent le workbook) :
- Vérifié hors du lab : `ansible-playbook --syntax-check` et rendu des gabarits Jinja de `patroni-essai/` ; configuration Patroni rendue passée à `patroni --validate-config` de **Patroni 4.1.5** (aucune clé refusée ; seuls les contrôles propres à la machine — adresses, ports, `bin_dir` — échouent hors des VMs) ; `tofu fmt` de `envs/m27/` ; `promtool check rules` et `promtool test rules` (Prometheus 3.5) sur `alertes-donnees.yaml` ; `python -m py_compile` du script d'export ; champs des manifestes comparés aux CRD de CloudNativePG 1.30.1, du plugin Barman Cloud 0.15.1, du Cluster Operator 2.23.1 et du Messaging Topology Operator 1.20.4 ; options de `pgbench`, `rabbitmq-perf-test` 2.25.0 (source de `PerfTest.java`), `patronictl` 4.1.5, `rabbitmq-queues` relues dans la documentation de la version.
- **À vérifier sur ton lab** : l'installation sur Debian 13 (paquets `etcd-server`, dépôt PGDG `trixie-pgdg`), les durées de bascule, le comportement réel de la CiliumNetworkPolicy L7 sur `/metrics/detailed?…`, la lecture de l'archive par le réplica de secours avec une identité SeaweedFS en lecture seule, la compatibilité du Cluster Operator 2.23 avec RabbitMQ 4.4, la version de PgBouncer de l'image du *pooler*.
- Les mesures citées dans les documents d'exemple sont celles d'un lab de référence : remplace-les par les tiennes.

**Fichiers** : [`fichiers/M27-E13/`](fichiers/M27-E13/) à [`fichiers/M27-E17/`](fichiers/M27-E17/), un dossier par exercice, sous la forme d'un extrait des projets : `infra/…` = `plateforme/infra`, `donnees/…` = `plateforme/donnees`, `k8s/…` = `plateforme/k8s`, `secrets/…` = `plateforme/secrets`, `observabilite/…` = `plateforme/observabilite`, `ansible/…` = `plateforme/ansible`, `deploiement-mediagenda/…` = `mediagenda/deploiement`, `medisphere/…` = la documentation. Les `*.extrait.*` sont à fusionner dans le fichier existant (l'emplacement est dit en tête).

---

### M27-E13 — Patroni sur VMs : l'autre façon de faire

**Solution**

*1. Les VMs.* [`envs/m27/`](fichiers/M27-E13/infra/envs/m27/) reprend `envs/m13/` : `versions.tf` (clé d'état `envs/m27/terraform.tfstate`), `chiffrement.tf`, `providers.tf`, `variables.tf` identiques, et [`pg-patroni.tf`](fichiers/M27-E13/infra/envs/m27/pg-patroni.tf) qui déclare les trois VMs par `for_each` sur une table `nom → {vmid, ipv4}`, avec leurs enregistrements DNS. Étiquettes NetBox `env-m27` et `role-pg-essai` créées d'abord (script de modélisation de M06-E05).

```
admin@adm01:~/src/infra/envs/m27$ source ~/src/infra/outils/charger-acces.sh
admin@adm01:~/src/infra/envs/m27$ tofu init && tofu plan -out plan.tfplan     # 3 VMs + 3 enregistrements A/PTR + objets NetBox
admin@adm01:~/src/infra/envs/m27$ tofu apply plan.tfplan
admin@adm01:~/src/infra/envs/m27$ tofu output -json pg_patroni | jq -r 'to_entries[] | "\(.key) \(.value.vmid) \(.value.ipv4)"'
pg-patroni01 2271 10.10.99.71
pg-patroni02 2272 10.10.99.72
pg-patroni03 2273 10.10.99.73
```

*2. Configuration.* [`patroni-essai/`](fichiers/M27-E13/donnees/patroni-essai/) dans `plateforme/donnees` : inventaire **statique** (ces VMs n'ont rien à faire dans les groupes du socle construits depuis NetBox), variables non secrètes, secrets en Vault Ansible `lab` (modèle `secrets.yml.exemple`), et [`patroni-essai.yml`](fichiers/M27-E13/donnees/patroni-essai/patroni-essai.yml) :
- **paquets** : `create_main_cluster = false` posé **avant** l'installation de `postgresql-18` (sinon le paquet crée et démarre `18/main` sur le port 5432, que Patroni veut pour lui) ; dépôt PGDG en deb822 ; `etcd-server`, `etcd-client` de Debian 13 ; Patroni **4.1.5** exactement, par `pip` dans `/opt/patroni` (extras `etcd3` et `psycopg3`) ;
- **etcd** : [`etcd.env.j2`](fichiers/M27-E13/donnees/patroni-essai/templates/etcd.env.j2) (`ETCD_INITIAL_CLUSTER` des trois membres, `initial-cluster-state new`), effacement unique des données du membre isolé démarré par le paquet, redémarrage **simultané** des trois (chaque membre attend ses pairs), contrôle `etcdctl endpoint health --cluster` ;
- **Patroni** : [`patroni.yml.j2`](fichiers/M27-E13/donnees/patroni-essai/templates/patroni.yml.j2) (`scope: pg-essai`, `etcd3`, `bootstrap.dcs` avec `ttl: 30`, `loop_wait: 10`, `synchronous_mode: true`, `use_pg_rewind`, `pg_hba`, comptes `postgres`, `replicateur`, `rewind`) contrôlé par `patroni --validate-config`, unité systemd ([`patroni.service.j2`](fichiers/M27-E13/donnees/patroni-essai/templates/patroni.service.j2), d'après celle de Patroni : `KillMode=process`, `Restart=no`), démarrage **un nœud à la fois** (`serial: 1`) : le premier prend la clé d'initialisation et lance `initdb`, les suivants clonent par `pg_basebackup` ;
- **HAProxy** sur `pg-patroni01` ([`haproxy.cfg.j2`](fichiers/M27-E13/donnees/patroni-essai/templates/haproxy.cfg.j2)) : port 5000 vers le seul serveur dont `GET /primary` (API REST, 8008) répond 200, `on-marked-down shutdown-sessions` pour couper les sessions restées sur l'ancien primaire.

Le flux provisoire depuis le cluster (pgbench facultatif) est dans [`pare_feu.extrait.yml`](fichiers/M27-E13/ansible/inventories/lab/group_vars/role_routeur/pare_feu.extrait.yml) ; etcd et l'API REST restent dans le VLAN 99.

*3. Observer.*

```
admin@adm01:~$ ssh pg-patroni01 sudo -u postgres /opt/patroni/bin/patronictl -c /etc/patroni/patroni.yml list
admin@adm01:~$ ssh pg-patroni01 sudo -u postgres /opt/patroni/bin/patronictl -c /etc/patroni/patroni.yml topology
admin@adm01:~$ ssh pg-patroni01 etcdctl --endpoints=http://127.0.0.1:2379 get --prefix /service/pg-essai/ --keys-only
/service/pg-essai/config
/service/pg-essai/initialize
/service/pg-essai/leader
/service/pg-essai/members/pg-patroni01
/service/pg-essai/members/pg-patroni02
/service/pg-essai/members/pg-patroni03
/service/pg-essai/status
/service/pg-essai/sync
admin@adm01:~$ ssh pg-patroni01 'etcdctl get /service/pg-essai/leader -w json' | jq '.kvs[0].lease'   # la clé leader porte un bail
```

*4. Bascule planifiée.* Table et témoin (depuis `pg-patroni02`, par HAProxy) :

```
postgres@pg-patroni02:~$ psql -h 10.10.99.71 -p 5000 -U postgres -c 'CREATE TABLE IF NOT EXISTS temoin (t timestamptz DEFAULT clock_timestamp())'
postgres@pg-patroni02:~$ while true; do psql -h 10.10.99.71 -p 5000 -U postgres -qtAc 'INSERT INTO temoin DEFAULT VALUES RETURNING t' 2>/dev/null || date +"%T.%3N ÉCHEC"; sleep 0.2; done | tee /tmp/temoin.log
admin@adm01:~$ ssh pg-patroni01 sudo -u postgres /opt/patroni/bin/patronictl -c /etc/patroni/patroni.yml switchover pg-essai --leader pg-patroni01 --candidate pg-patroni02 --force
```

Le plus grand trou entre deux `INSERT` réussis (`SELECT max(t - lag(t) OVER (ORDER BY t)) FROM temoin` n'est pas permis : sous-requête `SELECT max(e) FROM (SELECT t - lag(t) OVER (ORDER BY t) AS e FROM temoin) s`) donne l'indisponibilité : quelques secondes, dominées par l'arrêt propre de l'ancien primaire et par la détection de HAProxy (2 × `inter 2s`).

*5. Bascule sur panne.* Sur le primaire : `sudo systemctl kill -s SIGKILL patroni` **puis** `sudo -u postgres /usr/lib/postgresql/18/bin/pg_ctl -D /var/lib/postgresql/18/pg-essai stop -m immediate` (tuer Patroni seul laisse PostgreSQL primaire et orphelin : c'est précisément le cas que le *watchdog* de Patroni sert à couvrir). Les réplicas voient la clé `leader` expirer après `ttl` (30 s), font la course ; seul le réplica **synchrone** peut gagner (`synchronous_mode`). Au redémarrage de l'ancien primaire (`systemctl start patroni`), Patroni constate qu'il n'est plus *leader*, lance `pg_rewind` (journaux : `running pg_rewind from pg-patroni02`) et le rattache. `patronictl history` montre la nouvelle *timeline*. `patronictl failover` exige un candidat (`--candidate` ; plus d'option `--leader` depuis 4.0) et ne vérifie pas que la grappe a un *leader* : sur une grappe saine, si le candidat n'est pas le réplica synchrone, `patronictl` demande seulement « *Are you sure you want to failover to the asynchronous node …?* » (sans `--force`), puis l'agent décide d'après l'état réel (en `synchronous_mode`, un candidat non synchrone peut être refusé : lis les journaux de Patroni). `switchover`, lui, refuse d'emblée un candidat qui n'est pas le réplica synchrone (« *candidate name does not match with sync_standby* », API REST) et arrête proprement l'ancien primaire : c'est l'outil des bascules planifiées, `failover` celui des grappes **sans *leader*** (code de `patronictl` 4.1.5).

*6. Maintenance.* `patronictl pause` : la configuration commune passe en `pause: true` ; arrêter PostgreSQL sur le primaire ne déclenche **rien** (Patroni n'agit plus, il signale seulement) : les écritures échouent jusqu'au redémarrage manuel et au `resume`. C'est l'outil des interventions (montée de version manuelle, déplacement de données), et un piège si on l'oublie (une grappe en pause n'a plus de haute disponibilité : `patronictl list` affiche « Maintenance mode: on »).

*7. Comparatif* : [`comparatif-patroni-cnpg.md`](fichiers/M27-E13/medisphere/docs/donnees/comparatif-patroni-cnpg.md).

*8. Destruction.*

```
admin@adm01:~/src/infra/envs/m27$ tofu destroy
admin@adm01:~$ ssh root@pve01 'for v in 2271 2272 2273; do qm status $v; done'    # « does not exist »
admin@adm01:~$ dig +short pg-patroni01.par1.medisphere.internal                     # vide
```

et la MR qui retire le flux provisoire du pare-feu (`git revert`).

**Explications**

Patroni est un **agent** sur chaque nœud qui pilote son PostgreSQL et se coordonne par un magasin externe à consensus (DCS). Le primaire est celui qui détient la clé `leader`, à bail : tant qu'il la renouvelle (`loop_wait`), personne d'autre ne se promeut ; s'il ne peut plus joindre le DCS, il **se rétrograde** lui-même (il ne peut plus prouver qu'il est le seul). Le DCS fournit donc l'élection **et** la clôture, à condition que l'agent soit vivant : un Patroni figé laisse un PostgreSQL primaire sans contrôle, d'où le *watchdog* (`/dev/watchdog`) qui redémarre la machine. CloudNativePG fait la même chose avec l'API Kubernetes : le gestionnaire d'instance (PID 1 du pod) joue le rôle de l'agent, l'opérateur décide, le bail `Lease` du primaire et le contrôle d'isolement jouent le rôle de la clé `leader` et de l'auto-rétrogradation (M27-E24).

**Alternatives**

- **vip-manager** au lieu de HAProxy : une adresse flottante posée sur le nœud qui détient la clé `leader` ; pas de saut réseau supplémentaire, mais la bascule de l'adresse dépend aussi du bail et de l'ARP gratuit.
- **Client multi-hôtes** (`host=a,b,c target_session_attrs=read-write` de libpq, psycopg) : aucune brique de plus, mais chaque client découvre le primaire à la connexion ; une réserve de connexions garde ses anciennes connexions jusqu'à leur échec.
- **Consul** ou **ZooKeeper** comme DCS ; le DCS Raft intégré est déprécié depuis Patroni 3.0.
- L'opérateur **Zalando Postgres Operator** fait tourner Patroni dans Kubernetes (DCS = API Kubernetes) : une alternative réelle à CNPG, qu'on n'a pas essayée.

**Pièges classiques**
- Laisser le paquet Debian créer `18/main` : Patroni ne démarre pas (« port 5432 already in use ») ou deux PostgreSQL se disputent la machine.
- Changer `bootstrap.dcs` dans le fichier **après** le premier démarrage et s'étonner que rien ne bouge : la configuration commune vit dans le DCS (`patronictl edit-config`).
- `etcd` (API v2) au lieu de `etcd3` : les clés v2 et v3 ne se voient pas ; un etcd récent n'active plus l'API v2.
- Tuer Patroni sans PostgreSQL et croire avoir simulé une panne.
- Oublier la destruction : trois VMs et 3 Go de RAM pris jusqu'au M29 ; le check le rappelle.

**En production chez MédiSphère**

Patroni n'est pas retenu pour les bases du cluster (ADR-0270). S'il servait un jour pour une base sur VM : TLS sur etcd, l'API REST et PostgreSQL (step-ca), authentification de l'API REST pour les GET aussi, *watchdog* activé, deux HAProxy derrière keepalived, pgBackRest vers `s3-01`, `postgres_exporter` et métriques de Patroni dans Prometheus, rôle Ansible maintenu, et des VMs dans le socle (sauvegarde PBS, durcissement M26).

---

### M27-E14 — Superviser les données et la messagerie

**Solution**

*1. RabbitMQ.* [`servicemonitor.yaml`](fichiers/M27-E14/donnees/rabbitmq/servicemonitor.yaml) dans `plateforme/donnees/rabbitmq/` (Application `rabbitmq`, [extrait de kustomization](fichiers/M27-E14/donnees/rabbitmq/kustomization.extrait.yaml)), sur le modèle de celui que publie le Cluster Operator (`observability/prometheus/monitors/`) : un point d'accès `/metrics` (agrégé : nœuds, alarmes, mémoire, disque, totaux `rabbitmq_global_*`) et un `/metrics/detailed` avec `params` `family: [queue_coarse_metrics, queue_consumer_count]` et `vhost: [medinotif-recette, medinotif-prod]`. `/metrics/per-object` renverrait **toutes** les métriques de **tous** les objets (files, canaux, connexions) : coûteux pour le courtier à chaque collecte et pour Prometheus en séries ; `/metrics/detailed` filtré ne coûte que ce qu'on demande (la documentation du plugin annonce jusqu'à 60 fois moins cher). L'entrée de Prometheus sur 15692 est déjà dans `reseau.yaml` (M27-E03) ; ligne de la [matrice du cluster](fichiers/M27-E14/medisphere/docs/kubernetes/reseau/matrice-flux-cluster.extrait.md). Pour aller plus loin, une règle L7 (méthode `GET`, chemins `/metrics` et `/metrics/detailed` ; le `:path` vu par Envoy contient la chaîne de requête) resserrerait ce flux.

```
admin@adm01:~$ kubectl -n messagerie get svc rabbitmq -o jsonpath='{range .spec.ports[*]}{.name}={.port} {end}{"\n"}'
amqps=5671 management-tls=15671 prometheus=15692 …
# Thanos Query
count by (__name__) ({__name__=~"rabbitmq_detailed_queue_.*"})
sum by (vhost, queue) (rabbitmq_detailed_queue_messages_ready)
```

*2. Pooler.* Le PodMonitor `mediagenda-db-pooler-rw` est posé par M27-E02 dans le composant `supervision` de `mediagenda/deploiement` (`enablePodMonitor` est déprécié dans le `Pooler` comme dans le `Cluster`, documentation CNPG 1.30) : `cnpg_pgbouncer_pools_cl_waiting{namespace="mediagenda-recette"}` et `…prod` doivent répondre dans Thanos Query ; sinon, vérifier le composant et la politique réseau (port 9127). Version servie :

```
admin@adm01:~$ kubectl -n mediagenda-prod exec deploy/mediagenda-db-pooler-rw -c pgbouncer -- pgbouncer --version
```

M27-E02 a épinglé l'image 1.26.1 (`spec.pgbouncer.image`) : la commande le confirme ; sans cet épinglage, c'est l'image par défaut de l'opérateur qui fixe la version (à suivre et à inscrire au registre des écarts du M26 si elle est en retard).

*3. Valkey* : `redis_up{namespace="mediagenda-prod"}` dans Thanos Query ; si l'exportateur de M27-E07 n'est pas collecté, un PodMonitor sur son port nommé suffit (même modèle que le *pooler*).

*4. Règles* : [`alertes-donnees.yaml`](fichiers/M27-E14/observabilite/regles/alertes-donnees.yaml), tests [`alertes-donnees.test.yaml`](fichiers/M27-E14/observabilite/regles/tests/alertes-donnees.test.yaml), ajout à la CI ([extrait](fichiers/M27-E14/observabilite/regles/kustomization.extrait.yaml)) :

```
admin@adm01:~/src/observabilite$ yq '.spec' regles/alertes-donnees.yaml > /tmp/alertes-donnees.rules.yaml
admin@adm01:~/src/observabilite$ promtool check rules /tmp/alertes-donnees.rules.yaml
  SUCCESS: 14 rules found
admin@adm01:~/src/observabilite$ promtool test rules regles/tests/alertes-donnees.test.yaml
  SUCCESS
```

Points de conception :
- **Primaire absent** : `count by (namespace) (instances collectées) unless count by (namespace) (instances joignables ET hors récupération)` donne une série par espace sans primaire ; `absent()` (renommé par `label_replace`) couvre le cas où plus rien n'est collecté en prod. Une règle « `cnpg_pg_replication_in_recovery == 0` absente » ne marcherait pas : une série qui disparaît ne déclenche rien.
- **Synchrone sans réplica** : le primaire publie `cnpg_pg_replication_streaming_replicas` ; à 0 avec `dataDurability: required`, toutes les validations attendent — c'est la cause la plus probable d'« écritures bloquées » (M27-E19). `cnpg_collector_sync_replicas{value="observed"}` ne convient pas : il compte les noms de `synchronous_standby_names`, pas les réplicas connectés.
- **Files** : les métriques d'une file quorum viennent du nœud de son leader ; on somme par `vhost, queue` (un changement de leader change l'étiquette `pod`) et `deriv()` porte sur une sous-requête de la somme.
- **Alarmes** : une alarme mémoire ou disque bloque **tous** les publieurs de la grappe : critique, quel que soit le vhost.
- **Cache** : plein n'est pas une panne avec `allkeys-lru` ; plein **et** inefficace (taux de succès < 30 %), ou des erreurs vues par l'API (`mediagenda_cache_total{resultat="erreur"}`), oui.
- Recette en avertissement, production en critique (seul le critique réveille, routage du M21).

*5. Tableau* : [`donnees-messagerie.json`](fichiers/M27-E14/observabilite/tableaux/plateforme/donnees-messagerie.json) (UID `m27-donnees`, variables `datasource` et `env`), provisionné par [`kustomization.extrait.yaml`](fichiers/M27-E14/observabilite/tableaux/kustomization.extrait.yaml).

*6. Essai.* MR dans `medinotif/deploiement` qui met la recette à `replicas: 0`, synchronisation, puis observation dans Prometheus (`ALERTS{alertname="RabbitmqFileSansConsommateur"}`) et Alertmanager ; MR inverse. Isolement d'un réplica :

```
admin@adm01:~$ kubectl cnpg fencing on mediagenda-db 3 -n mediagenda-recette
admin@adm01:~$ kubectl cnpg fencing off mediagenda-db 3 -n mediagenda-recette
```

(un seul réplica : la réplication synchrone garde l'autre, les écritures continuent ; avec les deux, M27-E19.)

*7.* [`RB-274-alertes-donnees.md`](fichiers/M27-E14/medisphere/docs/donnees/runbooks/RB-274-alertes-donnees.md), et le `runbook_url` de chaque alerte pointe sur sa section.

**Explications**

Trois familles de signaux : **disponibilité** (un primaire, des consommateurs, un cache joignable), **saturation** (retard de réplication, clients en attente, file qui grossit, alarmes, mémoire), **erreurs** vues par le client (cache en erreur ; publications ratées, M27-E23). Les alertes de production réveillent sur ce qui casse le service (pas de primaire, écritures suspendues, aucun consommateur, alarme) ; le reste est un avertissement traité en heures ouvrées. Les durées (`for`) absorbent les états transitoires connus : une bascule CNPG dure moins d'une minute, un redémarrage de MédiNotif quelques secondes, un lot de rappels fait monter la file un quart d'heure.

**Alternatives**

- Les règles et tableaux communautaires (mixins `cloudnative-pg`, tableaux « RabbitMQ-Overview » de l'équipe RabbitMQ) : bons points de départ, à adapter (noms d'étiquettes, seuils, langue des runbooks).
- `prometheus.return_per_object_metrics = true` : simple, mais tout le coût de `/metrics/per-object` à chaque collecte.
- Superviser MédiNotif plutôt que la file (taux de `medinotif_messages_total`) : complémentaire, mais ne voit pas un MédiNotif absent.

**Pièges classiques**
- Collecter `/metrics/per-object` « pour être complet » : dizaines de milliers de séries par grappe chargée.
- Écrire `rabbitmq_queue_messages_ready` (préfixe agrégé) au lieu de `rabbitmq_detailed_queue_messages_ready` : la série n'existe pas sans `return_per_object_metrics`, l'alerte ne sonnera jamais.
- Oublier que `cnpg_pg_replication_lag` est publié par chaque instance : sur le primaire il vaut 0 ; c'est le `max` par pod qui compte.
- Laisser `enablePodMonitor: true` (déprécié) en plus d'un PodMonitor écrit à la main : séries en double.
- Un `for: 0s` sur une alarme de file : une alerte par lot de rappels.

**En production chez MédiSphère**

Revue trimestrielle des alertes (combien ont sonné, combien étaient utiles), sondes synthétiques de bout en bout (publier un message de test dans un vhost dédié et le voir consommé, M29), suivi de la cardinalité des séries `rabbitmq_detailed_*` quand les files se multiplieront, et tableaux par équipe (Julien voit MédiNotif sans voir les alarmes de la grappe).

---

### M27-E15 — Reprise et montée de version : réplica de secours, RabbitMQ 4.4

**Solution**

*0. La prod archive-t-elle ?*

```
admin@adm01:~$ kubectl -n mediagenda-prod get cluster mediagenda-db -o jsonpath='{.spec.plugins}{"\n"}{.status.conditions[?(@.type=="ContinuousArchiving")].status}{"\n"}'
admin@adm01:~$ kubectl -n mediagenda-prod get backups.postgresql.cnpg.io --sort-by=.status.stoppedAt | tail -3
```

Si `plugins` est vide : correctif [`prod-archivage.extrait.yaml`](fichiers/M27-E15/deploiement-mediagenda/prod-archivage.extrait.yaml) dans l'overlay de prod (`serverName: mediagenda-db-prod`, la recette occupant déjà `mediagenda-db`), `ObjectStore` et Secrets dans `mediagenda-prod`, flux vers `s3-01`, en fenêtre (les instances redémarrent une à une), puis `kubectl cnpg backup mediagenda-db -n mediagenda-prod` et un `ScheduledBackup` quotidien : sans sauvegarde de base, le réplica n'a rien pour démarrer.

*1. Le réplica de secours.* Dossier [`espaces/mediagenda-secours/`](fichiers/M27-E15/k8s/espaces/mediagenda-secours/) de `plateforme/k8s` : espace `restricted` et quota ([`00-espace.yaml`](fichiers/M27-E15/k8s/espaces/mediagenda-secours/00-espace.yaml)), réseau en refus par défaut avec seulement DNS, opérateur, instances entre elles, Prometheus, `s3-01:8333` et l'API Kubernetes ([`40-reseau.yaml`](fichiers/M27-E15/k8s/espaces/mediagenda-secours/40-reseau.yaml) ; l'API passe par une CNP `toEntities: [kube-apiserver]`, une NetworkPolicy `ipBlock` ne couvrant pas les adresses des nœuds sous Cilium), entrée dans OpenBao et Secrets ([`45-secrets.yaml`](fichiers/M27-E15/k8s/espaces/mediagenda-secours/45-secrets.yaml), et l'espace ajouté à `eso-espaces.tf` de `plateforme/secrets` : [extrait](fichiers/M27-E15/secrets/tofu/eso-espaces.tf.extrait)), [`ObjectStore`](fichiers/M27-E15/k8s/espaces/mediagenda-secours/60-cnpg-s3.yaml) **sans** `retentionPolicy` et avec une identité SeaweedFS en **lecture** (`Read` et `List` sur `cnpg-k8s-par1`), et le [`Cluster`](fichiers/M27-E15/k8s/espaces/mediagenda-secours/50-mediagenda-db-secours.yaml) :

```yaml
  bootstrap:
    recovery: {source: mediagenda-db-prod, database: mediagenda, owner: mediagenda}
  replica: {enabled: true, source: mediagenda-db-prod}
  externalClusters:
    - name: mediagenda-db-prod
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters: {barmanObjectName: cnpg-s3, serverName: mediagenda-db-prod}
```

Pas de bloc `plugins` : un réplica n'archive rien, et le jour de sa promotion il archivera sous un **nouveau** nom (RB-275).

```
admin@adm01:~/src/k8s$ kubectl apply -f espaces/mediagenda-secours/
admin@adm01:~$ kubectl cnpg status mediagenda-db-secours -n mediagenda-secours
Cluster Summary
Name:                 mediagenda-secours/mediagenda-db-secours
…
Status:               Cluster in healthy state
Instances:            2
Ready instances:      2
Replica Cluster:      true   (source: mediagenda-db-prod)
admin@adm01:~$ kubectl cnpg psql mediagenda-db-secours -n mediagenda-secours -- -c "SELECT pg_is_in_recovery(), pg_last_wal_replay_lsn(), now() - pg_last_xact_replay_timestamp() AS retard;"
```

*2. Supervision* : [`70-supervision.yaml`](fichiers/M27-E15/k8s/espaces/mediagenda-secours/70-supervision.yaml) (PodMonitor) et l'alerte `PostgresqlSecoursEnRetard` de `alertes-donnees.yaml` (> 600 s pendant 10 min : deux fois `archive_timeout`). Piège : sur ce réplica, `cnpg_pg_replication_lag` n'est pas un retard mais l'âge de la dernière transaction rejouée (la requête de CNPG ne renvoie 0 que si le récepteur de WAL a tout rejoué, et il n'y a pas de récepteur) ; il grandit toute la nuit si la prod n'écrit rien. L'alerte compare donc l'heure du dernier archivage de la prod (`cnpg_pg_stat_archiver_last_archived_time`, publié par son primaire) à celle de la dernière transaction rejouée par le secours (`time() − lag`) : plus de 10 min d'écart, c'est une archive qui arrive et n'est pas lue. Un test `promtool` couvre les deux cas (prod au repos : silence ; prod active : alerte). Même raisonnement pour la requête `now() - pg_last_xact_replay_timestamp()` ci-dessus : à lire en même temps que l'heure de la dernière écriture de la prod.

*3. Répétition de promotion* : [`secours-essai.yaml`](fichiers/M27-E15/k8s/essais/secours-essai.yaml) dans `wb-essais` (avec un `ObjectStore` `cnpg-s3-lecture` et les Secrets du même modèle). Une fois sain :

```
admin@adm01:~$ kubectl cnpg psql mediagenda-db -n mediagenda-prod -- -d mediagenda -c "SELECT now() AS t_prod, max(cree_le) AS dernier_rdv FROM rendez_vous;"
admin@adm01:~$ kubectl cnpg psql secours-essai -n wb-essais -- -c "SELECT pg_last_xact_replay_timestamp();"
admin@adm01:~$ kubectl -n wb-essais patch cluster secours-essai --type merge -p '{"spec":{"replica":{"enabled":false}}}'
admin@adm01:~$ kubectl cnpg status secours-essai -n wb-essais          # nouvelle timeline, primaire
```

RPO ≈ heure de la dernière écriture de la prod − `pg_last_xact_replay_timestamp()` au moment de la promotion : jusqu'à `archive_timeout` (5 min, posé par CNPG) en régime calme. Deuxième mesure : `SELECT pg_switch_wal();` sur la prod juste avant, attente de l'archivage (`SELECT last_archived_wal, last_archived_time FROM pg_stat_archiver;`), puis promotion : quelques dizaines de secondes. Suppression immédiate (`kubectl -n wb-essais delete cluster secours-essai`, les PVC partent avec lui) : c'est une copie de données de santé.

*4.* [`RB-275-reprise-secours.md`](fichiers/M27-E15/medisphere/docs/donnees/runbooks/RB-275-reprise-secours.md).

*5. Définitions RabbitMQ* : [`sauvegarde-definitions/`](fichiers/M27-E15/donnees/rabbitmq/sauvegarde-definitions/) dans `plateforme/donnees/rabbitmq/` : un `User` `sauvegarde-definitions` (étiquette `administrator` exigée par l'export de toute la grappe, **aucune** permission de vhost ; identifiants par ESO), un CronJob à deux conteneurs ([`cronjob.yaml`](fichiers/M27-E15/donnees/rabbitmq/sauvegarde-definitions/cronjob.yaml)) : [`export_definitions.py`](fichiers/M27-E15/donnees/rabbitmq/sauvegarde-definitions/export_definitions.py) (bibliothèque standard, retire `password_hash`) puis `aws s3 cp` vers `s3://messagerie-definitions/<AAAA>/<MM>/` (`AWS_REQUEST_CHECKSUM_CALCULATION=when_required` : aws-cli ≥ 2.23 ajoute sinon des sommes de contrôle que les S3 compatibles ne gèrent pas toujours), et ses politiques réseau. Les deux secrets (`kv/plateforme/rabbitmq/sauvegarde-definitions`, `kv/plateforme/rabbitmq/messagerie-definitions-s3`) sont lus par le ClusterSecretStore `openbao` : ajoute-les, chemin par chemin, à la politique `eso-plateforme` de `plateforme/secrets` ([extrait](fichiers/M27-E15/secrets/politiques/eso-plateforme.hcl.extrait-M27-E15)). La racine MédiSphère vient de la ConfigMap `racine-medisphere` de l'espace (M27-E03). Rétention : règle de cycle de vie du compartiment, posée côté `s3-01`.

```
admin@adm01:~$ kubectl -n messagerie create job --from=cronjob/export-definitions export-manuel-$(date +%s)
admin@adm01:~$ kubectl -n messagerie logs job/export-manuel-… -c export
{"fichier": "/travail/definitions-20261105T101500Z.json", "vhosts": 3, "files": 4, "politiques": 2, "version": "4.3.7"}
admin@adm01:~$ aws --endpoint-url https://s3-01.par1.medisphere.internal:8333 s3 ls s3://messagerie-definitions/2026/11/
admin@adm01:~$ aws … s3 cp s3://messagerie-definitions/2026/11/definitions-….json - | jq '[.users[] | has("password_hash")] | any'   # false
```

Réimport d'un vhost (sur la grappe jetable) : extraire du fichier les objets du vhost voulu, ou plus simplement exporter le vhost seul (`GET /api/definitions/medinotif-recette`) et le poster dans le vhost d'essai (`POST /api/definitions/essai`) : un export par vhost ne porte pas le nom du vhost et se réimporte dans n'importe lequel.

*6. Répétition de montée* : [`rabbitmq-essai.yaml`](fichiers/M27-E15/donnees/rabbitmq-essai/rabbitmq-essai.yaml) (ressources réduites, `autoEnableAllFeatureFlags: true`), [`messages-essai.sh`](fichiers/M27-E15/donnees/rabbitmq-essai/messages-essai.sh) pour remplir une file quorum et une classique :

```
admin@adm01:~/src/donnees$ kubectl apply -f rabbitmq-essai/rabbitmq-essai.yaml && rabbitmq-essai/messages-essai.sh preparer
admin@adm01:~$ for i in 0 1 2; do kubectl -n wb-essais exec rabbitmq-essai-server-$i -c rabbitmq -- rabbitmqctl list_feature_flags name state | grep -v enabled; done
admin@adm01:~$ kubectl -n wb-essais exec rabbitmq-essai-server-0 -c rabbitmq -- rabbitmq-queues check_if_node_is_quorum_critical
admin@adm01:~$ kubectl -n wb-essais patch rabbitmqcluster rabbitmq-essai --type merge -p '{"spec":{"image":"registry.par1.medisphere.internal/dockerhub/library/rabbitmq:4.4.0-management"}}'
admin@adm01:~$ kubectl -n wb-essais get pods -w      # server-2, puis -1, puis -0
admin@adm01:~$ kubectl -n wb-essais exec rabbitmq-essai-server-0 -c rabbitmq -- rabbitmq-queues quorum_status --vhost essai essai-quorum
admin@adm01:~/src/donnees$ rabbitmq-essai/messages-essai.sh compter
```

Le retour en 4.3 échoue : le nœud redémarré refuse de rejoindre une grappe dont des *feature flags* lui sont inconnus, et ne relirait pas le stockage v2 des files classiques. Suppression de la grappe et de ses PVC.

*7. Décision* : [`montee-rabbitmq-4.4.md`](fichiers/M27-E15/medisphere/docs/donnees/montee-rabbitmq-4.4.md) (exemple : rester en 4.3.7 jusqu'à la 4.4.1, au plus tard le 15/12/2026) ; si la décision est d'appliquer, MR [`rabbitmqcluster-4.4.extrait.yaml`](fichiers/M27-E15/donnees/rabbitmq/rabbitmqcluster-4.4.extrait.yaml) en fenêtre CHG-2815. Le check accepte les deux, avec la décision écrite.

**Explications**

Un *standalone replica cluster* CNPG est une base en récupération permanente : son instance désignée exécute la `restore_command` du plugin, qui va chercher dans l'archive chaque segment de WAL suivant ; les autres instances du réplica sont en cascade sur elle. Comme il ne voit que ce qui est **archivé**, son retard est au moins l'intervalle d'archivage : PostgreSQL n'archive un segment que lorsqu'il est plein (16 Mio) ou quand `archive_timeout` force un changement de segment (5 min posé par CNPG). D'où un RPO de quelques minutes, à comparer au RPO nul de la réplication synchrone **dans** la grappe : les deux mécanismes ne couvrent pas la même panne (perte d'une instance contre perte de toute la grappe ou de son stockage). La promotion (`replica.enabled: false`) fait sortir l'instance désignée de la récupération et ouvre une nouvelle *timeline* : l'historique diverge définitivement de celui de la source.

Côté RabbitMQ, les **définitions** sont la topologie (vhosts, échanges, files, liaisons, politiques, utilisateurs, permissions) ; les **messages** n'y sont pas. Chez MédiSphère, l'essentiel est déjà dans Git (Topology Operator) : l'export nocturne est une ceinture (ce qui a été créé à la main, l'état réel à une date) et un outil de vérification après reprise.

**Alternatives**

- **Topologie distribuée** CNPG (`replica.primary`, `replica.source`, jeton de rétrogradation) : bascule contrôlée sans reconstruire l'ancienne prod, à envisager avec un second site (PAR2).
- Réplica alimenté **en flux** (`connectionParameters`, `pg_basebackup` + réplication) : RPO de quelques secondes, mais un flux réseau direct prod → secours et une dépendance de plus ; en mode hybride, PostgreSQL bascule entre flux et archive.
- Restauration à un instant donné à la demande (M16-E19) : pas de copie qui tourne en permanence, mais un RTO bien plus long (rejouer depuis la dernière sauvegarde de base).
- `rabbitmqadmin` v2 (`definitions export`) dans le CronJob : plus court, mais un binaire de plus à épingler.

**Pièges classiques**
- Mettre `retentionPolicy` dans l'`ObjectStore` du secours avec une identité en écriture : son sidecar applique la rétention… sur l'archive de la prod.
- Donner au secours le `serverName` de la recette (`mediagenda-db`) : il rejoue la mauvaise base.
- Ajouter `plugins` avec `isWALArchiver: true` au réplica « pour plus tard » : à la promotion, il archive dans un emplacement qui contient déjà un autre historique (`Expected empty archive`) ou dans celui de la prod.
- Valeurs de `max_connections` (et des autres paramètres « de taille ») plus petites sur le réplica que sur la source : le réplica refuse de démarrer en *hot standby*.
- Oublier la copie de `wb-essais` : des données de santé de production qui traînent dans un espace d'essais.
- Croire que l'export des définitions sauvegarde les messages.
- Monter RabbitMQ sans vérifier les *feature flags* : un nœud mis à jour peut refuser de rejoindre la grappe.

**En production chez MédiSphère**

Le réplica de secours irait sur **PAR2** (`hp01`) : c'est là qu'il protège d'une perte de salle ; en attendant, il protège d'une perte de la grappe ou de ses volumes. Exercice de reprise trimestriel sur `wb-essais` (le RPO et le RTO mesurés vont au rapport de PRA du F5), alerte sur l'âge du dernier export de définitions, chiffrement côté serveur du compartiment `messagerie-definitions`, et montées de RabbitMQ toujours répétées sur une grappe jetable avant la prod.

---

### M27-E16 — Performance et dimensionnement : pgbench, perf-test, *pooler*

**Solution**

*1. Banc* : [`bench-essai.yaml`](fichiers/M27-E16/donnees/outils/banc/bench-essai.yaml) (`Cluster` + `Pooler` en mode transaction), puis l'initialisation par le plugin :

```
admin@adm01:~/src/donnees$ kubectl apply -f outils/banc/bench-essai.yaml
admin@adm01:~$ kubectl cnpg pgbench bench-essai -n wb-essais --db-name banc --job-name pgbench-init -- --initialize --scale 20
admin@adm01:~$ kubectl -n wb-essais logs -f job/pgbench-init
```

*2. Mesures.* `kubectl cnpg pgbench` vise le Service `-rw` ; `--dry-run` imprime son Job, point de départ de [`pgbench.yaml`](fichiers/M27-E16/donnees/outils/banc/pgbench.yaml) où l'hôte est un paramètre :

```
admin@adm01:~/src/donnees$ for hote in bench-essai-rw bench-essai-pooler-rw; do
>   for a in '"-c","20","-j","2","-T","60","-P","10"' '"-c","80","-j","4","-T","60","-P","10"' '"-c","20","-j","2","-T","60","-C","-P","10"'; do
>     n="$(echo "$hote$a" | md5sum | cut -c1-6)"
>     sed -e "s/@HOTE@/$hote/" -e "s/@NOM@/$n/" -e "s/@ARGS@/$a/" outils/banc/pgbench.yaml | kubectl apply -f -
>     kubectl -n wb-essais wait --for=condition=complete --timeout=180s job/pgbench-$n && kubectl -n wb-essais logs job/pgbench-$n | tail -6
>   done; done
```

Pendant chaque mesure : `SELECT count(*) FROM pg_stat_activity WHERE datname = 'banc';` (primaire) et le tableau `m27-donnees` (variable d'environnement adaptée, ou Explore sur `cnpg_pgbouncer_pools_*{namespace="wb-essais"}`).

*3.* `-M prepared` par le *pooler* : réussit si `max_prepared_statements` > 0 (PgBouncer ≥ 1.21) ; échoue sinon (`prepared statement … does not exist`). Une transaction interactive multi-requêtes passe (le mode transaction garde la connexion serveur jusqu'au `COMMIT`) ; ce qui casse, c'est ce qui dépasse la transaction (voir le document).

*4. RabbitMQ* : grappe de banc = manifeste de M27-E15 ; mesures par [`perf-test.yaml`](fichiers/M27-E16/donnees/outils/banc/perf-test.yaml) (URI construite dans le conteneur à partir du Secret de la grappe jetable) :

```
admin@adm01:~/src/donnees$ for a in "-x 1 -y 1 -q 1" "-x 1 -y 1 -c 1 -q 1" "-x 1 -y 1 -c 100 -q 1" "-x 1 -y 1 -c 100 -q 50" "-x 1 -y 3 -c 100 -q 50"; do
>   n="$(echo "$a" | tr -d ' -')"; sed -e "s/@NOM@/$n/" -e "s/@ARGS@/$a/" outils/banc/perf-test.yaml | kubectl apply -f -
>   kubectl -n wb-essais wait --for=condition=complete --timeout=180s job/perf-test-$n; kubectl -n wb-essais logs job/perf-test-$n | tail -3
> done
```

(perf-test sans `-c` ne demande pas de confirmation : c'est la première ligne du tableau.)

*5-6.* [`dimensionnement.md`](fichiers/M27-E16/medisphere/docs/donnees/dimensionnement.md), puis `kubectl -n wb-essais delete -f outils/banc/bench-essai.yaml`, suppression de la grappe de banc et de ses PVC, `kubectl -n wb-essais delete job -l app.kubernetes.io/name=pgbench` (et `perf-test`).

**Explications**

Un *pooler* en mode transaction **multiplexe** : N clients se partagent M connexions serveur, une connexion n'étant prêtée que le temps d'une transaction. Il ne rend pas PostgreSQL plus rapide ; il évite (1) le coût d'établissement d'une connexion (processus, authentification SCRAM, TLS) et (2) la saturation de `max_connections` et de la mémoire par des connexions oisives. Avec les identifiants dynamiques d'OpenBao, chaque pod a son utilisateur, donc sa réserve : le plafond se pose par base (`max_db_connections`). Côté RabbitMQ, la latence d'une confirmation sur une file quorum est celle d'une écriture répliquée sur la majorité et synchronisée sur disque : avec une confirmation à la fois, c'est elle qui borne le débit ; le `prefetch` borne de la même façon la consommation quand le consommateur attend chaque message.

**Alternatives**

- `pgbench -f` avec un script qui reproduit les requêtes de MédiAgenda (création, lecture des créneaux) : plus représentatif que TPC-B.
- k6 (M29) contre l'API elle-même : mesure de bout en bout, la seule qui compte pour le SLO.
- PgBouncer en mode `session` : aucune limite fonctionnelle, mais aucun multiplexage (une connexion serveur par client connecté).

**Pièges classiques**
- Mesurer une seule fois et comparer des pourcentages : Ceph partagé, variance forte.
- Lancer pgbench depuis `adm01` à travers un `port-forward` : on mesure le tunnel.
- Conclure que le *pooler* « ralentit » sur la mesure sans `-C`.
- Confondre débit du courtier et débit de MédiNotif : c'est l'envoi qui borne.
- Oublier le banc : une base et trois nœuds RabbitMQ qui consomment la marge des travailleurs.

**En production chez MédiSphère**

Rejouer le banc à chaque montée majeure (PostgreSQL, RabbitMQ, CNPG), versionner les résultats à côté du dimensionnement, et confronter les hypothèses à la réalité après la rentrée (débit réel de la file `notifications`, connexions réelles du *pooler*) : M28 fixera les seuils de KEDA et de l'HPA à partir de ces chiffres.

---

### M27-E17 — ADR : données et messagerie de MédiSphère

**Solution** : [`ADR-0270-donnees-et-messagerie.md`](fichiers/M27-E17/medisphere/docs/donnees/adr/ADR-0270-donnees-et-messagerie.md).

**Explications**

Un bon ADR dit **pourquoi pas** les options écartées avec des faits (mesures, licences, coûts d'exploitation), et **quand** on reviendra dessus avec des conditions observables. Kafka n'est pas « moins bien » : c'est un journal rejouable, et MédiSphère n'a aujourd'hui qu'une file de tâches avec un seul consommateur. Les licences se lisent dans le fichier `LICENSE` du dépôt à la version utilisée : la FSL (*Functional Source License*) de Liquibase 5 interdit l'usage concurrent pendant deux ans avant de devenir Apache 2.0, et n'est pas une licence libre au sens de l'OSI ; pour Atlas, seule l'édition *Community* est sous Apache 2.0. L'*outbox* est la réponse standard au problème de la double écriture (base + courtier) sans transaction distribuée.

**Alternatives** : un ADR par décision (quatre ADR courts) se défend ; un seul ADR montre les liens (l'*outbox* dépend du choix de RabbitMQ et de PostgreSQL).

**Pièges classiques**
- Citer une licence d'après un article de blog, ou celle d'une ancienne version (Liquibase était sous Apache 2.0 jusqu'à la 4.x).
- « Kafka est plus performant » sans dire pour quel besoin.
- Des conditions de révision non vérifiables (« si besoin »).

**En production chez MédiSphère** : l'ADR est relu au comité, puis chaque critère de révision devient une alerte ou une question du point trimestriel d'architecture.

---

### M27-E18 — Questions de production : données et messagerie

**1. Le pod meurt entre `COMMIT` et la publication.** Le rendez-vous existe, la demande de notification n'est jamais publiée : perte silencieuse (la requête a pu même répondre 201 si la mort survient après la réponse). Deux remèdes : l'***outbox*** (la demande est écrite dans une table **dans la même transaction** ; un relais la publie avec confirmation et la marque envoyée ; coût : une table, un relais, de l'idempotence côté consommateur) ; la **capture des changements** (Debezium lit le WAL et publie ; coût : Kafka Connect, un slot de réplication logique à superviser — un slot abandonné retient les WAL et remplit le disque). « Publier d'abord, valider ensuite » est pire : si la transaction échoue (conflit 409, base indisponible), MédiNotif envoie une confirmation pour un rendez-vous **qui n'existe pas** ; un SMS envoyé ne se reprend pas.

**2. Doublons et idempotence.** (a) MédiNotif envoie le SMS puis meurt avant `basic_ack` : le message est redélivré. (b) Le courtier perd la connexion entre l'envoi de l'accusé et sa prise en compte, ou un *failover* du leader de la file quorum survient. (c) Avec l'*outbox*, le relais publie puis meurt avant de marquer la ligne. Rendre idempotent : un **identifiant de demande** unique (UUID posé par MédiAgenda, ou `rendez_vous_id` + `modele`), une table ou une clé Valkey `envoyee:<id>` écrite **après** l'envoi réussi et consultée **avant**, avec une durée de vie supérieure à la fenêtre de redélivrance possible (7 jours couvre le rejeu d'un rebut). Pour un SMS déjà envoyé, rien à défaire : on évite le second envoi. Le cas résiduel (envoyé, mort avant d'écrire la clé) reste « au moins une fois » : accepté et documenté (le fournisseur SMS peut parfois dédoublonner).

**3. `nack` avec remise en file et limite de livraison en 4.3.** Depuis RabbitMQ 4.3, la limite de livraison d'une file quorum compte le `delivery-count`, qui n'augmente que pour les **échecs** : `basic.reject` (ou `rejected` en AMQP 1.0) et la fermeture d'un canal ou d'une connexion avec des messages non acquittés ; un `basic.nack` avec remise en file **ne compte pas** (documentation 4.3, « Repeatedly Requeued Deliveries » : des boucles infinies de `nack` sont permises). MédiNotif rejette ses échecs passagers par `basic_nack(requeue=True)` : un message qui échoue toujours tourne indéfiniment (une fois par seconde, avec la pause de MédiNotif) et ne part jamais au rebut. À changer dans MédiNotif : `basic_reject(requeue=True)` pour un échec (compté), garder `basic_nack(requeue=False)` pour un invalide, et/ou un compteur de tentatives applicatif ; côté file, `delayed-retry-*` de la 4.3 pour espacer les remises.

**4. Deux réplicas perdus en `dataDurability: required`.** MédiAgenda voit ses écritures **attendre** (chaque `COMMIT` reste en `SyncRep`) jusqu'au délai du client ou de la requête : créations de rendez-vous en échec après de longues secondes, lectures normales, *pooler* qui se remplit de clients en attente. Nadia voit `PostgresqlSynchroneSansReplica` (et `PgbouncerClientsEnAttente`). `preferred` : `synchronous_standby_names` ne contient que les réplicas sains ; sans réplica, les validations sont confirmées par le seul primaire. On gagne la disponibilité, on accepte de **perdre** les validations confirmées pendant ce temps si le primaire meurt à son tour. Pour une base de rendez-vous de santé, `required` (choix du M16) ; `preferred` se défend pour une base reconstructible (cache matérialisé, statistiques).

**5. *Split-brain*.** Deux primaires acceptent des écritures en même temps (partition réseau) : deux historiques divergents, irréconciliables sans travail manuel. Patroni : le primaire doit renouveler la clé `leader` dans le DCS ; coupé du DCS, il se **rétrograde** lui-même après `ttl` ; le *watchdog* couvre un Patroni figé. CloudNativePG : l'opérateur ne promeut un réplica qu'après avoir arrêté l'ancien primaire ou constaté qu'il ne répond plus ; depuis 1.30, la promotion exige le **bail** `Lease` du primaire (pas de promotion tant que l'ancien le détient ou qu'il n'a pas expiré) ; le **contrôle d'isolement** fait échouer la sonde de vivacité d'un primaire qui ne joint plus ni l'API ni les autres instances (le kubelet le redémarre) ; les Services ne pointent que vers le pod désigné primaire. Fenêtre résiduelle : un primaire isolé qui garde des clients **déjà connectés** continue de valider pendant l'arrêt *smart* (`smartShutdownTimeout`, 180 s par défaut) — sauf que, en réplication synchrone `required`, ces validations ne peuvent pas être confirmées sans réplica : c'est la synchrone qui ferme la fenêtre. Perte possible restante : `ANY 1` avec le primaire **et** le réplica synchrone perdus ensemble ; le troisième, en retard, est promu (`failoverQuorum` interdit justement cette promotion).

**6. Partition RabbitMQ.** Une file quorum a besoin de la majorité de ses membres : le leader isolé (minoritaire) ne peut plus rien valider et cède ; la majorité (deux nœuds) élit un nouveau leader au terme suivant ; les clients connectés au nœud isolé voient leurs publications non confirmées et leurs consommations arrêtées, et doivent se reconnecter ailleurs (le Service les y envoie). Les métadonnées sont dans **Khepri**, lui aussi un Raft : le côté minoritaire ne peut plus modifier la topologie, et rien n'est à « réconcilier » au retour. À l'époque de Mnesia (magasin par défaut jusqu'à 4.1 ; Khepri par défaut pour les nouvelles grappes depuis 4.2, et seul magasin pris en charge depuis 4.3, qui a retiré Mnesia et ses stratégies de partition), chaque côté continuait et il fallait une stratégie `cluster_partition_handling` (`pause_minority`, `autoheal`) qui jetait les changements d'un côté ; les files miroir classiques (supprimées en 4.0) pouvaient perdre des messages.

**7. Mode transaction.** Ne pas : utiliser des `SET` de session (préférer `SET LOCAL` ou les options de connexion), compter sur des tables temporaires d'une transaction à l'autre, utiliser des verrous consultatifs de session ou `LISTEN/NOTIFY`, préparer en SQL (`PREPARE`) ; les requêtes préparées par protocole exigent `max_prepared_statements`. Le Job de migration a une raison de garder une connexion **directe** (`mediagenda-db-rw`) : Flyway prend un verrou consultatif (transactionnel par défaut, mais en mode session si `postgresql.transactional.lock=false`), peut exécuter des instructions non transactionnelles (`CREATE INDEX CONCURRENTLY`) et des sessions longues ; et une migration ne doit pas consommer la réserve de l'API.

**8. Bitnami.** Depuis le 28/08/2025, Broadcom a figé le catalogue gratuit : images déplacées vers `docker.io/bitnamilegacy` sans mises à jour, charts publics non maintenus, versions maintenues réservées à l'offre payante « Bitnami Secure Images ». Rester sur une image figée, c'est accumuler les CVE sans correctif, perdre la compatibilité avec les nouvelles versions de Kubernetes, et dépendre d'un dépôt qui peut disparaître. Le workbook utilise les images officielles des projets (`rabbitmq`, `valkey/valkey`) et leurs opérateurs.

**9. Montée majeure avec CNPG.** **En place** : changer `imageName` vers une image de majeure supérieure ; l'opérateur arrête **tout** le cluster, lance un Job `pg_upgrade --link`, puis reclone les réplicas ; indisponibilité totale (minutes, peu dépendante du volume) ; retour arrière possible tant que le Job a échoué (l'opérateur détecte le retour à l'ancienne image), sinon restauration ; les statistiques ne sont pas transférées (`ANALYZE` après) ; nouveau système pour l'archive : changer le `serverName` et faire une sauvegarde aussitôt (aucune restauration à un instant donné ne traverse une majeure). **Import logique** (`bootstrap.initdb.import`) : un nouveau cluster, la source intacte (retour arrière immédiat), durée proportionnelle aux données, écritures à geler pendant la copie. **Réplication logique** (publication/abonnement, CRD `Publication`/`Subscription`) : quasi sans interruption (bascule finale), mais séquences, DDL et grands objets à gérer à part.

**10. Migration *contract* pendant un *canary*.** Pendant le *canary* à 20 %, 80 % du trafic est encore servi par la version N−1. Le Job de migration (vague −1) passe **avant** le déploiement de la version N : si `V4__` supprime une colonne que N−1 lit encore, les pods N−1 échouent sur chaque requête qui la touche — une panne de 80 % du trafic causée par la livraison. *Expand/contract* l'évite : la version N n'a besoin que des ajouts (*expand*) ; la suppression (*contract*) ne part qu'avec une version **ultérieure**, quand plus aucun pod ne lit la colonne. Les vagues d'Argo CD ordonnent la migration avant l'application ; elles ne protègent pas de l'ancienne version : c'est la règle d'écriture des migrations qui le fait.

**11. Valkey disparaît.** MédiAgenda perd le cache des créneaux : chaque lecture des créneaux recalcule depuis la base (plus de charge et de latence sur PostgreSQL), les invalidations échouent sans conséquence. Garanties : côté client, délais courts (`socket_connect_timeout` et `socket_timeout` à 2 s, déjà dans le code) et erreurs de cache attrapées (mode dégradé, déjà dans le code) ; côté serveur, `maxmemory` avec une politique d'éviction (`allkeys-lru`) pour ne jamais refuser une écriture, aucune persistance exigée (un redémarrage repart à vide) ; côté plateforme, ne pas faire dépendre la **disponibilité** de l'API du cache : aujourd'hui `/pret` renvoie 503 si Valkey ne répond pas, ce qui retire **tous** les pods du service quand le cache tombe ; il vaudrait mieux que `/pret` ne vérifie que PostgreSQL (MR proposée à Julien).

**12. Promotion avec 7 minutes de retard.** Décision de Claire (ou de son suppléant), sur la base : la prod est-elle irrécupérable à court terme (RB-270 et RB-162 épuisés) ? quel est le retard exact (`pg_last_xact_replay_timestamp`) ? peut-on encore forcer un `pg_switch_wal()` sur la prod ? Le RTO d'une restauration serait-il acceptable à la place ? Aux centres : les rendez-vous pris entre l'heure de la dernière transaction rejouée et la panne peuvent avoir disparu ; on leur donne la plage horaire exacte, on extrait des journaux de MédiAgenda (Loki) et des notifications envoyées (journaux de MédiNotif) la liste des rendez-vous confirmés dans cette plage pour les recontacter ou les ressaisir.
