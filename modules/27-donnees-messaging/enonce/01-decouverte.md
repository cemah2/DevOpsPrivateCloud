# Module 27 — Palier 1 : Découverte

Avant de brancher quoi que ce soit, on reprend ce qui existe et on pose les fondations. Ce palier approfondit **CloudNativePG** sur `mediagenda-db` (rôles et base déclaratifs, réserve de connexions, bascules et mises à jour), installe **RabbitMQ** par ses opérateurs, décrit sa **topologie** dans Git et déploie enfin **MédiNotif** en recette, puis confie les migrations de MédiAgenda à **Flyway**. Le palier s'ouvre sur un questionnaire.

Prérequis : module 26 terminé (`lab/bin/check 26 46` vert) ; module 16 (CloudNativePG, plugin Barman Cloud, `mediagenda-db`) ; module 20 (Argo CD, hook de migration) ; module 25 (OpenBao, ESO, identifiants dynamiques PostgreSQL, ClusterIssuer `openbao-services`). Lis [`00-introduction.md`](00-introduction.md), en particulier le chemin imposé, les faits techniques, les règles et le bilan de mémoire.

---

### M27-E01 — Test de positionnement : données et messagerie  `Q` `★★`

> **Ticket PLAT-2801** — *De : Karim Benali*
> Le rituel, trois quarts d'heure, par écrit, sans moteur de recherche ni IA. Ce module touche aux deux choses qu'on ne peut pas perdre : les données et les messages. Je veux savoir comment tu raisonnes sur la durabilité, la cohérence et la compatibilité avant que tu touches à `mediagenda-db`. Réponds même là où tu hésites, et justifie.

**Objectifs pédagogiques**
- Évaluer ta compréhension de la réplication, des réserves de connexions, des migrations de schéma et des garanties de livraison avant de les pratiquer.
- Repérer les thèmes à retravailler et les exercices du module qui les mobilisent.

**Prérequis** : aucun.
**Durée indicative** : 45 min (+ 20 min d'auto-correction).

**Travail demandé**

Réponds aux 12 questions. Pour les QCM, justifie ton choix en une ou deux phrases et dis pourquoi chaque autre option est fausse.

*PostgreSQL et CloudNativePG*

1. `mediagenda-db` est configurée avec `synchronous: {method: any, number: 1, dataDurability: required}`. Explique ce que l'application attend quand elle valide une transaction. Que se passe-t-il pour les écritures si les **deux** réplicas deviennent injoignables ? Qu'aurait changé `dataDurability: preferred` ?

2. *(QCM)* Le primaire de `mediagenda-db` est sur `k8s-w02`. Tu dois redémarrer ce nœud pour une mise à jour du noyau. Quelle séquence est la plus sûre ?
   - A. `kubectl drain k8s-w02 --disable-eviction --force` pour ne pas attendre
   - B. Bascule planifiée (*switchover*) vers une réplique saine et synchrone, vérification, puis `kubectl drain`
   - C. `kubectl delete pod` du primaire pour forcer une élection, puis `drain`
   - D. Mettre `instances: 1` le temps de l'opération

3. Un collègue propose de passer `max_connections` de 100 à 1 000 « pour ne plus jamais être à court de connexions ». Pourquoi est-ce une mauvaise idée pour PostgreSQL, et que proposes-tu à la place ?

4. *(QCM)* Devant `mediagenda-db`, PgBouncer est configuré en mode **transaction**. Laquelle de ces pratiques **casse** à travers lui ?
   - A. Une requête `SELECT` simple, sans transaction explicite
   - B. Un `BEGIN … COMMIT` de trois instructions
   - C. `SELECT pg_advisory_lock(42)` dans une requête, puis le travail protégé dans les suivantes
   - D. Une connexion qui change d'utilisateur PostgreSQL à chaque requête

*Migrations de schéma*

5. MédiAgenda est déployé par *canary* (M20) : pendant dix minutes, l'ancienne et la nouvelle version servent ensemble. Le Job de migration passe **avant** la nouvelle version. Lesquelles de ces migrations sont dangereuses dans ce contexte, et pourquoi : (a) ajouter une colonne `NOT NULL` sans défaut ; (b) renommer la colonne `motif` en `raison` ; (c) ajouter une table ; (d) supprimer une colonne que la nouvelle version n'utilise plus ?

6. Pourquoi un `ALTER TABLE rendez_vous ADD COLUMN …` de quelques millisecondes peut-il geler toute l'API pendant des minutes ? Quel réglage de session limite ce risque, et que doit faire le Job de migration quand il se déclenche ?

7. Une migration `V3__…` déjà appliquée en recette contient une faute. Un développeur corrige le fichier et pousse. Que fait Flyway au déploiement suivant, et quelle est la bonne correction ?

*Cache*

8. *(QCM)* Valkey sert de cache aux créneaux de MédiAgenda, `maxmemory` atteint. Quelle politique d'éviction convient, et pourquoi pas les autres ?
   - A. `noeviction`
   - B. `allkeys-lru`
   - C. `volatile-ttl`
   - D. Pas de `maxmemory` : le pod a une limite mémoire de toute façon

*Messagerie*

9. Une file **quorum** de trois répliques : combien de nœuds peuvent tomber sans perdre de message confirmé ni empêcher la publication ? Pourquoi ne faut-il pas de grappe RabbitMQ à **deux** nœuds ? Que sont devenues les files « miroir » ?

10. MédiNotif acquitte un message **après** l'envoi du SMS. Décris le scénario qui produit un **double** envoi, et ce qu'il faudrait pour que le second envoi n'ait pas lieu. Quelle garantie l'éditeur obtient-il en activant les **confirmations de publication**, et laquelle n'obtient-il pas ?

11. Kafka ou RabbitMQ ? Pour chacun de ces besoins, choisis et justifie en deux lignes : (a) envoyer un SMS de confirmation par rendez-vous pris ; (b) conserver 30 jours tous les événements « rendez-vous créé / annulé », relus par la facturation, les statistiques et un futur moteur de recommandations ; (c) un message qui échoue doit être réessayé dix minutes plus tard sans bloquer les autres.

12. Un message de notification invalide revient sans cesse dans la file : le worker le rejette **avec** remise en file, le reçoit à nouveau, le rejette… Quels mécanismes de RabbitMQ empêchent cette boucle ? Et quel est l'équivalent (ou l'absence d'équivalent) avec Kafka ?

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 12 questions avant d'ouvrir le corrigé.
- [ ] Tu as noté chaque réponse avec la grille du corrigé (0, 1 ou 2 points) et calculé ton score sur 24.
- [ ] Tu as noté les thèmes à retravailler et les exercices du module qui les mobilisent.

<details><summary>Indice 1</summary>

Pour la réplication, distingue « le primaire a écrit » et « une réplique a confirmé l'écriture » ; pour les files quorum, raisonne en **majorité**. Pour les migrations, imagine l'ancienne version de l'API exécuter ses requêtes **après** la migration.
</details>

<details><summary>Indice 2</summary>

Pour le mode transaction de PgBouncer, demande-toi ce qu'il reste à un client **entre** deux transactions : la connexion serveur qu'il a utilisée peut être donnée à un autre client. Pour la livraison, cherche le moment exact où un worker peut mourir entre « fait » et « dit que c'est fait ».
</details>

**Pour aller plus loin** (facultatif) : refais ce test à la fin du module (M27-E25), sans relire le corrigé, et compare.

---

### M27-E02 — CloudNativePG en profondeur : rôles, bases et *pooler*  `LAB` `★★`

> **Ticket PLAT-2802** — *De : Nadia Roussel* — *Copie : Julien Petit, Karim Benali*
> Jeudi, le primaire de recette a redémarré et l'API a renvoyé des 500 pendant deux minutes : 34 connexions ouvertes, `max_connections` atteint au retour, et personne ne savait si la bascule était finie. Je veux trois choses avant qu'on mette les notifications en production : (1) l'API ne parle plus directement à PostgreSQL mais à une **réserve de connexions** ; (2) les rôles et la base sont **déclarés** dans Git, plus créés à la main ; (3) quelqu'un dans l'équipe a fait au moins une fois, calmement, une bascule planifiée, un drainage de nœud et une mise à jour d'image, en recette, avec les commandes notées. Lucas a besoin d'un accès en lecture à la base de recette pour sa semaine d'analyse des requêtes lentes : il doit **expirer seul**.

**Objectifs pédagogiques**
- Déclarer des rôles (`spec.managed.roles`) et une base (CRD `Database`) et comprendre ce que l'opérateur réconcilie, et ce qu'il ne fait pas.
- Mettre un *pooler* PgBouncer devant une base, en mode transaction, et y faire passer l'application.
- Activer `pg_stat_statements` et lire les requêtes les plus coûteuses.
- Conduire les trois opérations de maintenance courantes : *switchover*, drainage d'un nœud, mise à jour de l'image.
- Préparer la lecture des nouveaux objets du bloc G par les vérifications du workbook.

**Prérequis** : M16 (CloudNativePG, `mediagenda-db`) ; M25-E14 (rôles gérés `openbao` et `mediagenda_api`, identifiants dynamiques) ; M21 (Prometheus, sélecteur `medisphere.internal/supervision: "oui"`).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Base de recette | Cluster `mediagenda-db`, espace `mediagenda-recette`, fichier `espaces/mediagenda-recette/50-mediagenda-db.yaml` de `plateforme/k8s` (`task appliquer`) |
| Base de prod | rendue par `components/dependances` de `mediagenda/deploiement`, corrigée par `overlays/prod/base-openbao.yaml` (M25) ; Argo CD, synchronisation manuelle |
| Pooler | **`mediagenda-db-pooler-rw`**, `type: rw`, `poolMode: transaction`, 2 instances sur deux nœuds différents ; Service du même nom, port 5432 ; métriques sur 9127 |
| Rôle de Lucas | `lucas_lecture`, membre du rôle de groupe `mediagenda_lecture` (sans connexion, `SELECT` seulement), mot de passe dans OpenBao `kv/mediagenda/recette/lecture-lucas` (clés `username`, `password`), expiration dans **7 jours** |
| Base déclarée | CRD `Database` nommée `mediagenda-db-mediagenda`, base PostgreSQL `mediagenda`, propriétaire `mediagenda`, **jamais supprimée** avec l'objet |
| `pg_stat_statements` | activé par un paramètre `pg_stat_statements.*` du Cluster |
| Images | `registry.par1.medisphere.internal/ghcr/cloudnative-pg/postgresql:18.6-…-minimal-trixie` ; PgBouncer `registry.par1.medisphere.internal/ghcr/cloudnative-pg/pgbouncer:<VERSION>` |
| Vérifications | ClusterRole **`wb-checks-services`** (`plateforme/k8s`, `rbac/`), agrégée à `wb-checks` par l'étiquette `workbook.medisphere.internal/checks: "true"` |

**Travail demandé**

*A. Les droits des vérifications (préparation du bloc G)*

1. Relis `rbac/wb-checks-stockage.yaml` (M16) : quelles API de CloudNativePG sont déjà lisibles par `wb-checks` ? Écris `rbac/wb-checks-services.yaml` : une ClusterRole agrégée, en lecture seule, pour les objets que ce module et les deux suivants ajoutent (RabbitMQ, Strimzi ; M28 et M29 l'étendront par leurs propres fichiers). Elle ne doit donner accès à **aucun** Secret ni à rien qui en recopie la valeur. `task appliquer`, puis vérifie avec `kubectl auth can-i --as=system:serviceaccount:wb-system:wb-checks …`.

*B. Rôles et base déclaratifs (recette)*

2. Lis la page « Declarative role management » de CloudNativePG 1.30. Réponds dans `~/m27/e02/journal.md` : que fait l'opérateur d'un rôle présent dans PostgreSQL mais absent de `managed.roles` ? Que fait-il d'une appartenance absente de `inRoles` ? Comment déclare-t-on un mot de passe, et sous quelle forme est-il stocké ?
3. Ajoute au Cluster de recette le rôle de groupe `mediagenda_lecture` (sans connexion) et le rôle `lucas_lecture` (connexion, membre de `mediagenda_lecture`, limite de connexions basse, `validUntil` à J+7). Son mot de passe vient d'OpenBao par un ExternalSecret dans l'espace (format attendu par l'opérateur : lis la documentation). Les droits `SELECT` sur les tables, CloudNativePG ne sait pas les déclarer : écris-les dans un fichier SQL idempotent à côté des autres (`sql/`), comme au M25.
4. Déclare la base `mediagenda` **existante** par une CRD `Database`. Avant d'appliquer, trouve le champ qui décide de ce qui arrive à la base PostgreSQL quand on supprime l'objet, et fixe-le explicitement. Observe `status` après application : l'opérateur a-t-il recréé ou adopté la base ?
5. Active `pg_stat_statements` sur le Cluster. Combien d'instances redémarrent, et pourquoi ? Une fois actif, liste les cinq requêtes de MédiAgenda qui coûtent le plus de temps cumulé (`kubectl cnpg psql`, avec un compte qui n'est **pas** le superutilisateur si possible) et note-les.

*C. Le pooler*

6. Lis la page « Connection pooling » de CloudNativePG 1.30 (authentification par `auth_query`, paramètres modifiables, image, supervision). Note dans `journal.md` pourquoi un pooler en mode transaction n'oblige **plus** MédiAgenda à désactiver ses instructions préparées (versions de PgBouncer et de psycopg en jeu) et ce qui, en revanche, ne doit jamais passer par lui.
7. Écris le Pooler `mediagenda-db-pooler-rw` (recette) : deux instances réparties sur deux nœuds, mode transaction, quelques paramètres bornés (`max_client_conn`, `default_pool_size`), ressources déclarées, PriorityClass de l'API. Applique, puis relève la version réelle de PgBouncer (`status.image` du Pooler, et `pgbouncer --version` dans un pod). Si elle est antérieure à la dernière corrective de sa branche, épingle l'image par ton cache Harbor.
8. Réseau : les pods du pooler ont-ils besoin de nouvelles politiques ? Lis les étiquettes qu'ils portent (`kubectl get pods --show-labels`), compare avec les sélecteurs des politiques existantes de l'espace (plateforme et chart), et n'ajoute **que** ce qui manque (indice : la supervision).
9. Supervision : un `PodMonitor` qui récupère les métriques `cnpg_pgbouncer_*` (le champ `enablePodMonitor` du Pooler est déprécié : lis pourquoi), avec l'étiquette que sélectionne Prometheus (M21).
10. Bascule de MédiAgenda : l'API doit joindre `mediagenda-db-pooler-rw` ; le Job de migration, lui, continue d'aller **directement** à `mediagenda-db-rw`. Trouve où l'URL de l'API est fabriquée depuis le M25 (component `identifiants-dynamiques`) et modifie-la par une MR de `mediagenda/deploiement` — sans casser le Job. Après synchronisation, montre que les connexions de l'API arrivent par le pooler (`pg_stat_activity` côté PostgreSQL, `SHOW POOLS` ou les métriques côté PgBouncer).

*D. Maintenance en recette*

> ⚠️ **Attention** : ces trois opérations touchent la base de recette pendant que l'API tourne. Avant chacune : `kubectl cnpg status` sain (trois instances, réplication synchrone, archivage sans erreur) et une sauvegarde `Completed` récente (`kubectl cnpg backup mediagenda-db -n mediagenda-recette`, puis `kubectl get backups`). Fais tourner une sonde (`while sleep 1; do curl -s -o /dev/null -w '%{http_code}\n' …/pret; done`) et garde sa sortie. Retour arrière : une bascule se défait par une autre bascule ; un `drain` par un `uncordon` ; une image par le retour de `imageName` à la précédente.

11. **Bascule planifiée** : promeus une réplique par `kubectl cnpg promote`. Chronomètre la durée sans écriture possible vue par la sonde. Qu'ont vu les clients du pooler ?
12. **Nœud drainé** : choisis le travailleur `<NOEUD-REPLIQUE>` qui porte une réplique (pas le primaire), `kubectl drain` (avec les options nécessaires), observe ce que fait l'opérateur de l'instance qui y tournait (PVC `ceph-rbd`, anti-affinité), puis `uncordon`. Recommence avec le nœud du **primaire** : qu'est-ce que l'opérateur fait d'abord ? Note la différence.
13. **Mise à jour de l'image** : PostgreSQL 18.6 est la dernière mineure publiée ; l'image `18.6-minimal-trixie` est pourtant reconstruite régulièrement (paquets du système). Passe le Cluster de recette à la reconstruction la plus récente, **par empreinte** (`…:18.6-<AAAAMMJJhhmm>-minimal-trixie@sha256:…`), et décris dans l'ordre ce que fait l'opérateur (`primaryUpdateMethod`). Pour voir une vraie montée **mineure**, refais-la sur une grappe jetable `essai-maj` dans `wb-essais` (une instance de 18.4 vers 18.6), puis supprime-la.

*E. Prod et documentation*

14. Reporte en production, par MR de `mediagenda/deploiement` (synchronisation manuelle) : `pg_stat_statements`, la `Database`, le Pooler et son `PodMonitor`, l'URL de l'API. **Pas** de rôle pour Lucas en production. Avant la synchronisation : sauvegarde `Completed` de la prod.
15. Écris `docs/donnees/postgresql.md` (`plateforme/medisphere`) : où chaque objet est défini (recette, prod), le chemin des connexions (API → pooler → primaire ; migrations → primaire), les commandes de la section D et ce qu'elles ont donné chez toi (durées mesurées).

**Critères de réussite**
- [ ] La ClusterRole `wb-checks-services` est agrégée à `wb-checks` : le compte lit les objets `rabbitmq.com` et `kafka.strimzi.io`, et ne lit toujours pas les Secrets.
- [ ] En recette, `managed.roles` déclare `mediagenda_lecture` (sans connexion) et `lucas_lecture` (avec `validUntil`), et l'opérateur les montre réconciliés.
- [ ] Une `Database` déclare la base `mediagenda` sans pouvoir la supprimer avec l'objet ; elle est appliquée.
- [ ] `pg_stat_statements` est activé sur la recette et la prod.
- [ ] Le Pooler `mediagenda-db-pooler-rw` (mode transaction, deux instances) tourne en recette et en prod, et un `PodMonitor` étiqueté pour Prometheus le supervise.
- [ ] L'API de recette et de prod se connecte par le pooler (métriques de PgBouncer) ; le Job de migration va directement au primaire.
- [ ] `docs/donnees/postgresql.md` existe sur `main` et contient les durées mesurées.

**Vérification** : `lab/bin/check 27 02`

<details><summary>Indice 1</summary>

Le mot de passe d'un rôle géré vient d'un Secret de type `kubernetes.io/basic-auth` (clés `username` et `password`) : un modèle d'ExternalSecret sait poser le type. Pour `validUntil`, un horodatage RFC 3339. La CRD `Database` a un champ `databaseReclaimPolicy` ; et son `spec.cluster`, comme celui d'un Pooler, ne se change plus après création.
</details>

<details><summary>Indice 2</summary>

Les pods du pooler portent l'étiquette `cnpg.io/cluster: mediagenda-db` en plus de `cnpg.io/poolerName` : relis tes politiques réseau à cette lumière. L'URL de l'API est dans le **modèle** de l'ExternalSecret `mediagenda-db-api` : PgBouncer ignore qui se connecte tant que `auth_query` le trouve dans PostgreSQL — les comptes dynamiques d'OpenBao passent donc sans configuration supplémentaire.
</details>

<details><summary>Indice 3</summary>

`kubectl cnpg promote <cluster> <instance>` ; `kubectl drain <nœud> --ignore-daemonsets --delete-emptydir-data` ; le PodDisruptionBudget posé par l'opérateur sur le primaire empêche de l'évincer avant une bascule. Pour trouver l'empreinte d'une étiquette : `crane digest` ou `skopeo inspect --format '{{.Digest}}'` sur l'image du cache Harbor.
</details>

**Pour aller plus loin** (facultatif) : la CRD `DatabaseRole` (CloudNativePG 1.30) gère un rôle comme un objet à part : compare-la à `managed.roles` (qui peut la créer, qui la voit dans Argo CD, ce qui arrive si deux sources déclarent le même rôle).

---

### M27-E03 — RabbitMQ par l'opérateur : la grappe `messagerie/rabbitmq`  `LAB` `★★`

> **Ticket PLAT-2803** — *De : Karim Benali* — *Copie : Sophie Laurent*
> On installe RabbitMQ comme le reste : par Argo CD, sans rien tirer d'Internet. Le projet ne publie **pas** de chart Helm, et le chart Bitnami est hors de question : on recopie les manifestes de publication des deux opérateurs, épinglés et vérifiés, dans un nouveau projet `plateforme/donnees`. Grappe de trois nœuds dans `messagerie`, un nœud par travailleur, TLS par notre PKI de services, plugin Prometheus. L'interface de gestion se publie sur la Gateway, **connexion par Keycloak** ; Sophie veut que le compte d'administration créé par l'opérateur soit documenté comme compte de bris de glace et pas utilisé au quotidien. Et je veux qu'on vérifie que c'est bien Khepri qui tient les métadonnées.

**Objectifs pédagogiques**
- Installer des opérateurs depuis des manifestes amont recopiés et vérifiés, avec Kustomize et Argo CD.
- Décrire une grappe RabbitMQ (`RabbitmqCluster`) : réplicas, stockage, anti-affinité, ressources, TLS, configuration, Pod Security.
- Publier l'interface de gestion derrière le SSO (OAuth 2.0) en gardant l'API pour les vérifications.
- Vérifier l'état de la grappe : nœuds, Khepri, alarmes, *feature flags*.

**Prérequis** : M27-E02 (ClusterRole `wb-checks-services`) ; M25-E16 (ClusterIssuer `openbao-services`) ; M24 (Keycloak, `plateforme/identite/tofu`) ; M15 (Gateway `gw-par1`, HTTPRoute) ; M20 (Applications, projet `plateforme`).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Manifestes amont | `cluster-operator.yml` (Cluster Operator **v2.23.1**) et `messaging-topology-operator-with-certmanager.yaml` (Messaging Topology Operator **v1.20.4**), pièces jointes des pages de publication GitHub des projets `rabbitmq/cluster-operator` et `rabbitmq/messaging-topology-operator` |
| Projet | `plateforme/donnees` : `vendor/rabbitmq/` (copies épinglées + `kustomization.yaml`), `rabbitmq/` (grappe), `outils/recopier-operateurs.sh` |
| Applications | **`rabbitmq-operateurs`** (chemin `vendor/rabbitmq`, espace `rabbitmq-system`) et **`rabbitmq`** (chemin `rabbitmq`, espace `messagerie`), projet `plateforme` |
| Espaces | `rabbitmq-system` et `messagerie` dans `plateforme/k8s/espaces/` ; Pod Security `restricted` visé pour les deux (à vérifier sur les rendus) |
| Images | `registry.par1.medisphere.internal/ghcr/rabbitmq/cluster-operator:2.23.1`, `…/ghcr/rabbitmq/messaging-topology-operator:1.20.4`, `registry.par1.medisphere.internal/dockerhub/library/rabbitmq:4.3.<z>-management` (dernière corrective de 4.3 à relever) |
| Grappe | `RabbitmqCluster` **`rabbitmq`**, 3 réplicas, `ceph-rbd` 10 Gio par nœud, requêtes 1 Gio / limite 1,5 Gio, plugin `rabbitmq_auth_backend_oauth2` |
| TLS | Certificate `rabbitmq-tls` (ClusterIssuer `openbao-services`, 72 h au plus) : `rabbitmq.messagerie.svc`, `*.rabbitmq-nodes.messagerie.svc` et leurs formes `.cluster.local` |
| Gestion | HTTPRoute `rabbitmq` sur `gw-par1`, `rabbitmq.apps.par1.medisphere.internal` ; client Keycloak **`rabbitmq`** (public, PKCE) déclaré dans `plateforme/identite/tofu` ; groupes `plateforme-admins` (administration), `plateforme` et `support` (supervision) |
| Vérifications | utilisateur RabbitMQ **`wb-checks`** (étiquette `monitoring`), mot de passe dans OpenBao `kv/plateforme/rabbitmq/wb-checks`, copie locale `~/.config/workbook/rabbitmq-checks.env` (600) |

**Travail demandé**

*A. Recopier les opérateurs*

1. Crée `plateforme/donnees` et son arborescence. Écris `outils/recopier-operateurs.sh` : il télécharge les deux manifestes **à une version donnée**, vérifie leur SHA-256 contre une valeur écrite dans le script (relevée et relue en MR), et les range dans `vendor/rabbitmq/<opérateur>/`. Relève toi-même les deux empreintes.
2. Inventorie ce que contiennent ces manifestes (`yq 'select(.kind != "CustomResourceDefinition") | .kind + " " + .metadata.name'`) : quels objets de cluster, quels webhooks, quelles dépendances (cert-manager ?), quel objet est présent **dans les deux** fichiers ? Comment Kustomize réagit-il à ce doublon ?
3. Écris les `kustomization.yaml` de `vendor/rabbitmq/` : images réécrites vers le cache Harbor, objet en double neutralisé (l'espace appartient à `plateforme/k8s`). Rends le tout (`kubectl kustomize`) et vérifie le contexte de sécurité des Deployments : passeront-ils la Pod Security `restricted` ?
4. Espaces `rabbitmq-system` et `messagerie` dans `plateforme/k8s` (étiquettes Pod Security, quota, `LimitRange`), `task appliquer`. Puis l'Application `rabbitmq-operateurs` (le projet `plateforme` doit accepter les types de cluster que ces manifestes créent) ; synchronise et vérifie que les deux opérateurs sont prêts et que leurs webhooks ont un certificat.

*B. La grappe*

5. Relève la dernière corrective de RabbitMQ 4.3 sur Docker Hub (étiquette `4.3.<z>-management`) et son empreinte. Lis les notes de version de la 4.3 : qu'est-ce qui a changé pour les files classiques, pour Khepri, pour les *feature flags* ?
6. Écris `rabbitmq/` : le Certificate `rabbitmq-tls`, le `RabbitmqCluster` `rabbitmq` (image épinglée, trois réplicas, anti-affinité **obligatoire** par nœud, stockage, ressources, TLS, `additionalPlugins`, `additionalConfig` avec la configuration OAuth 2.0 du point 9, délai d'arrêt suffisant pour vider un nœud), un PodDisruptionBudget si l'opérateur n'en pose pas (vérifie), et la CiliumNetworkPolicy de l'espace : AMQPS 5671 depuis les espaces qui en auront besoin (aucun pour l'instant, prévois la règle), gestion 15672 depuis la Gateway, Prometheus 15692 depuis `supervision`, opérateurs (`rabbitmq-system`) vers 15671/15672, trafic entre nœuds de la grappe ; **rien** vers 5672.
7. Application `rabbitmq`, synchronisation. Suis l'ordre de démarrage des pods (`kubectl get pods -w`). Lis le Secret `rabbitmq-default-user` **sans** afficher le mot de passe : quelles clés contient-il ? Range ce compte comme bris de glace (où, qui y a accès, quand l'utiliser) dans `docs/donnees/rabbitmq.md`.
8. Vérifie la grappe de l'intérieur (`kubectl exec rabbitmq-server-0 -- rabbitmq-diagnostics …`) : statut de la grappe et des trois nœuds, **magasin de métadonnées** (Khepri ?), *feature flags* activés, alarmes, écouteurs (5671 en TLS ? 5672 ?), certificat présenté sur 5671 (`openssl s_client` depuis un pod de `wb-essais`, avec la racine MédiSphère).

*C. Gestion par SSO et compte des vérifications*

9. Dans `plateforme/identite/tofu`, déclare le client Keycloak `rabbitmq` (lis la documentation « OAuth 2.0 » de RabbitMQ 4.3 : client **public** ou confidentiel ? quelle audience ? quelles portées ?) et les rôles du client qui portent les droits RabbitMQ (`rabbitmq.tag:administrator`, `rabbitmq.read:*/*`, …), attribués aux groupes. Côté RabbitMQ, la configuration correspondante (`auth_backends`, `auth_oauth2.*`, `management.oauth_*`) : les utilisateurs internes (applications, `wb-checks`, bris de glace) doivent continuer de fonctionner, l'interface web ne doit proposer **que** le SSO, l'API HTTP doit accepter l'authentification basique.
10. HTTPRoute `rabbitmq` sur `gw-par1` vers le port de gestion ; ExternalDNS publie le nom. Connecte-toi à l'interface par Keycloak (OTP compris) : quel nom d'utilisateur apparaît, avec quelles étiquettes ?
11. Compte `wb-checks` : mot de passe aléatoire dans OpenBao (`kv/plateforme/rabbitmq/wb-checks`), un `User` RabbitMQ déclaratif (CRD du Topology Operator) dont le mot de passe vient de ce chemin par un ExternalSecret (ClusterSecretStore `openbao`), étiquette `monitoring`. Il ne peut lire **aucun** message. Écris `~/.config/workbook/rabbitmq-checks.env` (600) et teste `curl -u … https://rabbitmq.apps.par1.medisphere.internal/api/overview`. (La politique `eso-plateforme` d'OpenBao doit lui donner ce chemin : MR de `plateforme/secrets`.)

**Critères de réussite**
- [ ] Les deux opérateurs tournent dans `rabbitmq-system` (images du cache Harbor, versions 2.23.1 et 1.20.4), installés par l'Application `rabbitmq-operateurs`, à partir de copies vérifiées par empreinte dans `plateforme/donnees`.
- [ ] La grappe `messagerie/rabbitmq` a trois nœuds prêts, un par travailleur, en RabbitMQ 4.3.x épinglé, stockage `ceph-rbd`, TLS par `openbao-services`, sous Pod Security `restricted`.
- [ ] Khepri est le magasin de métadonnées ; aucune alarme active.
- [ ] Une CiliumNetworkPolicy protège les pods de la grappe ; 5672 n'est autorisé depuis nulle part.
- [ ] `https://rabbitmq.apps.par1.medisphere.internal` répond, l'interface propose la connexion par Keycloak, le client `rabbitmq` existe dans le royaume `medisphere`.
- [ ] `wb-checks` lit l'API HTTP (étiquette `monitoring`), son identifiant vient d'OpenBao, et `rabbitmq-checks.env` est en 600.

**Vérification** : `lab/bin/check 27 03`

<details><summary>Indice 1</summary>

Deux fichiers qui déclarent le même `Namespace` : Kustomize refuse de les assembler (« already registered id »). Un `kustomization.yaml` par opérateur, chacun avec un correctif `$patch: delete`, puis un troisième qui inclut les deux. Pour les images, le champ `images:` de Kustomize suffit. Les Deployments amont déclarent déjà `runAsNonRoot`, `seccompProfile` et `capabilities.drop` : lis-les avant d'écrire un correctif.
</details>

<details><summary>Indice 2</summary>

`spec.tls.secretName` attend un Secret avec `tls.crt` et `tls.key` (cert-manager ajoute `ca.crt`). Avec TLS, l'opérateur ajoute les écouteurs TLS sans retirer les autres, sauf `disableNonTLSListeners` : lis ce que ce champ coupe **aussi**, et pourquoi la Gateway a besoin du port de gestion en clair (dans le cluster). La configuration de RabbitMQ se donne en format `rabbitmq.conf` dans `spec.rabbitmq.additionalConfig`. Pour Khepri : cherche « metadata » dans `rabbitmq-diagnostics help`, et le *feature flag* `khepri_db` dans `rabbitmqctl list_feature_flags`.
</details>

<details><summary>Indice 3</summary>

Le client de l'interface est **public** (code d'autorisation avec PKCE, pas de secret). RabbitMQ lit les portées dans `scope` et, si tu le lui dis (`auth_oauth2.additional_scopes_key`), dans d'autres revendications, comme les rôles de client de Keycloak (`resource_access.rabbitmq.roles`). Il exige son `resource_server_id` dans l'audience (`aud`) : un mappeur d'audience de Keycloak. L'API HTTP accepte l'authentification basique par défaut même avec OAuth 2.0 activé ; c'est l'**interface** qui ne propose plus le formulaire (`management.oauth_disable_basic_auth`).
</details>

**Pour aller plus loin** (facultatif) : le chiffrement de la distribution Erlang entre nœuds (`spec.tls.interNode`). Le trafic entre pods traverse déjà le tunnel WireGuard de Cilium (M15, M26) : qu'apporterait le TLS entre nœuds en plus, et qu'est-ce qu'il coûterait ?

---

### M27-E04 — Topologie déclarative et MédiNotif en recette  `LAB` `★★`

> **Ticket DEV-2804** — *De : Julien Petit* — *Copie : Karim Benali*
> MédiNotif tourne depuis le M12 sur une VM qui n'existe plus. Je veux le voir en recette **cette semaine**, branché sur la nouvelle grappe. Mes contraintes : la file est déclarée par la plateforme (mon worker ne la crée plus, `MEDINOTIF_DECLARER_FILE=0`), mon compte ne peut que lire `notifications`, celui de MédiAgenda ne pourra qu'écrire sur l'échange, et un message pourri ne doit **ni** boucler indéfiniment **ni** disparaître : je veux le retrouver dans un rebut. Même modèle de déploiement que MédiAgenda : un dépôt de déploiement, Argo CD, image signée par empreinte.

**Objectifs pédagogiques**
- Déclarer une topologie RabbitMQ complète par le Messaging Topology Operator (vhost, échanges, files quorum, liaisons, politique, utilisateurs, permissions).
- Fournir les identifiants AMQP aux applications par OpenBao et External Secrets, sans secret dans Git.
- Déployer une nouvelle application par GitOps de bout en bout : espace, dépôt de déploiement, AppProject, ApplicationSet.
- Vérifier le chemin d'un message, y compris vers le rebut.

**Prérequis** : M27-E03 ; M20 (AppProject, ApplicationSet, dépôt de déploiement de MédiAgenda) ; M25-E13 (SecretStore `openbao` par espace) ; M26 (Pod Security, Kyverno, signatures) ; M12-E17 (image de MédiNotif) ; M19 (composants CI/CD de `medinotif/worker`).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Topologie | dossier `topologie/medinotif-recette/` de `plateforme/donnees`, Application **`rabbitmq-topologie`** (chemin `topologie`, espace `messagerie`) ; tous les objets dans l'espace `messagerie`, préfixés par l'environnement |
| Vhost | `medinotif-recette`, type de file par défaut `quorum` |
| Objets RabbitMQ | échange `notifications` (direct) ; file `notifications` (quorum) ; liaison clé `notifications` ; échange `notifications.rebut` (fanout) ; file `notifications.rebut` (quorum) ; politique `notifications-rebut` (sur `^notifications$`, files quorum : échange de rebut, limite de livraison 5, rebut « au moins une fois ») |
| Utilisateurs | `medinotif-recette` : lire `notifications` ; `mediagenda-recette` : écrire sur l'échange `notifications` ; `wb-checks` : aucun droit sur les messages, mais une permission (vide) sur le vhost pour en voir les métadonnées |
| Secrets OpenBao | `kv/medinotif/recette/amqp`, `kv/mediagenda/recette/amqp` : clés `utilisateur`, `mot_de_passe`, `url` (`amqps://<utilisateur>:<mot de passe>@rabbitmq.messagerie.svc:5671/medinotif-recette`) |
| MédiNotif | dépôt **`medinotif/deploiement`** (clone `~/src/medinotif-deploiement`, `base/` + `overlays/recette`, `overlays/prod` plus tard), AppProject **`medinotif`**, ApplicationSet **`medinotif`** (`plateforme/gitops/applications/medinotif.yaml`), espace **`medinotif-recette`** ; Deployment `medinotif` (1 réplica), ExternalSecret `medinotif-amqp`, `MEDINOTIF_DECLARER_FILE=0`, métriques 9100 (Service + ServiceMonitor), racine MédiSphère pour vérifier le certificat de RabbitMQ |
| Image | `registry.par1.medisphere.internal/medisphere/medinotif-worker:<VERSION-MEDINOTIF>@sha256:…`, signée (Kyverno l'exige en recette) |
| Outil fourni | [`ressources/E04-messages/publier.py`](../ressources/E04-messages/publier.py) : publie des demandes de notification (valides et invalides) en AMQPS |

**Travail demandé**

*A. Identifiants*

1. Génère deux mots de passe aléatoires et écris `kv/medinotif/recette/amqp` et `kv/mediagenda/recette/amqp` dans OpenBao (sans que le mot de passe passe par l'historique du shell). La politique `eso-plateforme` doit pouvoir lire ces deux chemins pour créer les utilisateurs dans `messagerie` : MR de `plateforme/secrets`, avec la justification en commentaire (c'est une exception à la règle « la plateforme ne lit pas les secrets des équipes »).

*B. La topologie*

2. Lis la documentation du Messaging Topology Operator (CRD `Vhost`, `Exchange`, `Queue`, `Binding`, `Policy`, `User`, `Permission`) : comment un objet désigne-t-il sa grappe ? Que se passe-t-il dans RabbitMQ quand on **supprime** l'objet `Queue` (champ `deletionPolicy`) ? Quels champs d'une `Queue` sont immuables, et pourquoi (que fait RabbitMQ si on redéclare une file existante avec d'autres arguments) ?
3. Écris `topologie/medinotif-recette/` et sa `kustomization.yaml`, puis `topologie/kustomization.yaml` qui l'inclut (la prod s'y ajoutera en E08). Les utilisateurs prennent leur mot de passe dans des ExternalSecret (ClusterSecretStore `openbao`) au format qu'attend la CRD `User`. Ajoute une `Permission` (vide) pour `wb-checks` sur ce vhost. Application `rabbitmq-topologie`, synchronisation.
4. Vérifie dans RabbitMQ, par l'API (`wb-checks`) et dans l'interface (SSO) : vhost, files (type, politique effective), liaisons ; puis par `rabbitmqctl` dans un pod : permissions des trois utilisateurs. Qu'arrive-t-il si tu essaies de publier sur `notifications` avec le compte de MédiNotif ?

*C. Le dépôt de déploiement et Argo CD*

5. L'image : vérifie qu'une version de `medinotif/worker` est publiée **et signée** dans Harbor (`cosign verify` avec la clé du M25, ou l'onglet du projet). Sinon, pose une étiquette `vX.Y.Z` pour déclencher son pipeline (composants `construction-image` et `securite`, M19 et M25).
6. Espace `medinotif-recette` dans `plateforme/k8s/espaces/` (Pod Security `restricted`, quota, `LimitRange`, refus par défaut, compte `eso` et SecretStore `openbao` comme au M25-E13 ; rôle `eso-medinotif-recette` dans `plateforme/secrets`). `task appliquer`.
7. Projet GitLab `medinotif/deploiement` : `base/` (Deployment `medinotif` sans privilège, compte de service sans jeton, sondes, ressources, `terminationGracePeriodSeconds` qui couvre un message, PriorityClass, Service et ServiceMonitor des métriques, NetworkPolicy/CNP : sortie DNS et AMQPS vers `messagerie`, entrée Prometheus sur 9100), `overlays/recette/` (ExternalSecret `medinotif-amqp` qui fournit `MEDINOTIF_AMQP_URL`, ConfigMap de la racine MédiSphère et la variable qui la fait lire par Python, image par empreinte). Vérifie le rendu (`kubectl kustomize`) contre la Pod Security et les politiques Kyverno (`kubectl apply --dry-run=server` dans l'espace).
8. Côté `plateforme/gitops` : AppProject `medinotif` (sur le modèle de `mediagenda` : objets interdits, ressources orphelines) et ApplicationSet `medinotif` (recette synchronisée automatiquement ; la prod viendra en E08). Identifiant de dépôt du groupe `medinotif` pour Argo CD (jeton de déploiement en lecture). Côté `messagerie` : complète la CNP de la grappe pour accepter AMQPS depuis `medinotif-recette`.
9. Synchronise. Lis les journaux du worker : à quelle file s'est-il abonné, avec quel compte ?

*D. Le chemin d'un message*

10. Avec `ressources/E04-messages/publier.py` (lis-le d'abord), publie depuis `adm01` dix messages valides et deux invalides avec le compte de MédiAgenda (lis son mot de passe dans OpenBao ; le port 5671 n'est joignable que dans le cluster : `kubectl port-forward` vers le Service, et l'outil vérifie le certificat sous son vrai nom).
11. Suis-les : journaux de MédiNotif, compteur `medinotif_messages_total` (Prometheus), files `notifications` et `notifications.rebut` (API). Les deux messages invalides sont-ils au rebut ? Avec quels en-têtes (`x-death`, raison) ? Pourquoi le worker n'a-t-il pas eu besoin de connaître le rebut ?
12. Documente dans `docs/donnees/messagerie-topologie.md` : la topologie, les comptes et leurs droits, le chemin d'un message et du rebut, comment ajouter un environnement.

**Critères de réussite**
- [ ] Le vhost `medinotif-recette`, ses deux échanges, ses deux files **quorum**, ses liaisons et la politique de rebut existent, déclarés par l'Application `rabbitmq-topologie` depuis `plateforme/donnees`.
- [ ] Les utilisateurs `medinotif-recette` et `mediagenda-recette` existent avec des droits minimaux ; leurs mots de passe viennent d'OpenBao.
- [ ] L'ApplicationSet `medinotif` produit l'Application `medinotif-recette`, synchronisée et saine ; le Deployment `medinotif` tourne avec une image par empreinte, `MEDINOTIF_DECLARER_FILE=0` et l'URL AMQP lue dans le Secret `medinotif-amqp` d'un ExternalSecret.
- [ ] MédiNotif est consommateur de la file `notifications` (une connexion AMQPS de `medinotif-recette`).
- [ ] Des messages ont été envoyés (métrique `medinotif_messages_total{resultat="envoye"}` > 0) et au moins un message invalide est dans `notifications.rebut`.
- [ ] `docs/donnees/messagerie-topologie.md` existe sur `main`.

**Vérification** : `lab/bin/check 27 04`

<details><summary>Indice 1</summary>

Chaque objet du Topology Operator a un `rabbitmqClusterReference` (nom et espace de la grappe) et, pour ceux d'un vhost, un champ `vhost`. Un `User` lit ses identifiants dans le Secret de `importCredentialsSecret` (clés `username` et `password`) ; la `Permission` désigne l'utilisateur par son nom dans RabbitMQ (`user`) ou par l'objet (`userReference`). La politique s'applique aux files dont le nom correspond au motif ; `applyTo` accepte `quorum_queues`.
</details>

<details><summary>Indice 2</summary>

`pika` vérifie le certificat **et** le nom du serveur (`amqps://`) avec le magasin de certificats par défaut de Python, que la variable `SSL_CERT_FILE` remplace : il suffit de monter la racine MédiSphère (une ConfigMap) et de pointer cette variable dessus. Un message rejeté sans remise en file (`basic_nack requeue=False`) part vers l'échange de rebut **de la file**, défini par la politique.
</details>

<details><summary>Indice 3</summary>

Le message n'a pas besoin d'être un « vrai » rejet pour aller au rebut : la limite de livraison y envoie aussi un message dont la livraison a échoué trop souvent (en RabbitMQ 4.3 : `basic.reject` ou consommateur mort avant l'accusé ; un `basic.nack` avec remise en file, lui, ne compte pas). Pour les en-têtes, l'API de gestion permet de **lire** un message sans le consommer (`POST /api/queues/<vhost>/<file>/get`, `ackmode=ack_requeue_true`) — avec ton compte personnel (SSO), pas avec `wb-checks`.
</details>

**Pour aller plus loin** (facultatif) : ajoute une file de rappel différé (TTL + rebut vers `notifications`) pour réessayer un envoi en échec dans dix minutes sans bloquer la file : qu'en dit la documentation des files quorum (TTL par message) ?

---

### M27-E05 — Flyway : reprendre les migrations de MédiAgenda  `LAB` `★★`

> **Ticket DEV-2805** — *De : Julien Petit* — *Copie : Karim Benali*
> Notre `python -m mediagenda.migrate` a bien servi, mais il ne sait ni valider, ni lister proprement, ni reprendre une base existante, et c'est un outil maison de plus à maintenir. On passe à **Flyway 13**, édition libre. Contraintes : on garde les fichiers `V1__init.sql` et `V2__index.sql` tels quels ; **aucune** migration ne doit être rejouée sur la recette ni la prod (elles sont à la version 2 depuis le M16) ; le compte reste le migrateur dynamique d'OpenBao ; l'image de migration est construite par notre CI, signée, et le Job garde sa place dans la synchronisation (vague −1). Karim veut voir la reprise répétée sur une base jetable avant qu'on touche à la recette.

**Objectifs pédagogiques**
- Comprendre le modèle de Flyway : versions, somme de contrôle, table d'historique, verrou, `baseline`.
- Reprendre une base existante sans rejouer de migration, avec un garde-fou.
- Construire une image de migration à partir de l'image officielle, épinglée, sans privilège.
- Remplacer le Job de migration dans le flux GitOps existant (vague −1, identifiants dynamiques).

**Prérequis** : M20-E11 (Job de migration en hook) ; M25-E14 (compte `mediagenda-migrateur` dynamique) ; M19 (composants CI/CD) ; M26 (signatures exigées en recette et en prod).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Flyway | **13.11.1**, édition OSS (Apache 2.0) ; image `registry.par1.medisphere.internal/dockerhub/flyway/flyway:13.11.1` épinglée par empreinte ; tourne en utilisateur quelconque (racine du conteneur en lecture seule) |
| Migrations | `migrations/V1__init.sql`, `migrations/V2__index.sql` de `mediagenda/api` (inchangés) |
| Historique existant | table `mediagenda_historique_schema` (versions `1` et `2`, empreintes SHA-256), écrite par `mediagenda.migrate` |
| Image de migration | `registry.par1.medisphere.internal/medisphere/mediagenda-migrations:vX.Y.Z` (même version que l'API), Dockerfile `Dockerfile.migrations` de `mediagenda/api`, construite par un pipeline enfant (les composants CI/CD ont des noms de jobs fixes) |
| Job | **`mediagenda-migrations`** (hook Sync, vague −1, `BeforeHookCreation`), remplace `mediagenda-migrate` ; il se connecte **directement** à `mediagenda-db-rw` (jamais au pooler) |
| Compte | rôle dynamique `mediagenda-migrateur-<env>` (M25) : membre de `mediagenda`, `SET role = 'mediagenda'` à la connexion ; Secret `mediagenda-db-migrateur` (ExternalSecret du component `identifiants-dynamiques`) |
| Répétition | grappe jetable `flyway-essai` (une instance) dans `wb-essais` |

**Travail demandé**

*A. Comprendre*

1. Lis dans la documentation de Flyway 13 : la nomenclature des fichiers, la table d'historique, `info`, `validate`, `migrate`, `baseline` (et les paramètres `baselineVersion`, `baselineDescription`, `baselineOnMigrate`), `repair`, les rappels SQL (*callbacks*), la façon de passer la configuration (fichier TOML, arguments, variables d'environnement `FLYWAY_*`) et l'emplacement par défaut des migrations dans l'image Docker. Vérifie la licence de l'édition utilisée dans l'image (`/flyway/licenses/`). Notes dans `~/m27/e05/journal.md`.
2. Sans lancer Flyway : que fera `flyway migrate` sur la base de recette telle qu'elle est (schéma non vide, pas de `flyway_schema_history`) ? Et `migrate` avec `baselineOnMigrate=true` et `baselineVersion=2` sur une base **neuve** (environnement reconstruit) ? Sur une base où `V2` n'aurait **pas** été appliquée ?

*B. Répéter sur une base jetable*

3. Dans `wb-essais`, crée une grappe CloudNativePG `flyway-essai` d'une instance, puis amène-la exactement dans l'état de la recette : l'image de l'API **actuelle** lance `python -m mediagenda.migrate` dans un pod jetable (même compte que l'application de cette base).
4. Avec l'image Flyway (pod jetable, utilisateur non root, racine en lecture seule, migrations montées depuis une ConfigMap) : `info`, puis `migrate` **sans** reprise (constate le refus), puis la reprise à la version 2, puis `info` et `validate`. Lis `flyway_schema_history`. Modifie un octet de `V2__index.sql` dans la ConfigMap et relance `validate`. Note chaque sortie.
5. Le garde-fou : écris un rappel SQL `beforeBaseline.sql` qui fait échouer la reprise si `mediagenda_historique_schema` ne contient pas les versions 1 et 2. Prouve-le sur une seconde base jetable où seule `V1` a été appliquée. Supprime ensuite `flyway-essai`.

*C. L'image et la CI*

6. `Dockerfile.migrations` dans `mediagenda/api` : `FROM` l'image Flyway du cache Harbor par empreinte, `COPY` des migrations et du rappel, utilisateur non root (UID au choix, documenté), télémétrie de Redgate désactivée, aucune commande par défaut dangereuse (`clean` est-il désactivé par défaut ?). Construis-la localement si tu peux, sinon par la CI.
7. CI de `mediagenda/api` : un pipeline enfant (`ci/migrations.yml`) qui inclut `construction-image` et `securite` pour `medisphere/mediagenda-migrations` (même étiquette `vX.Y.Z` que l'API, image signée), et un job `migrations:verifier` qui lance `flyway migrate` puis `validate` et `info` contre un service PostgreSQL 18 jetable du job. Pousse, vérifie dans Harbor l'image et sa signature.

*D. Le Job*

8. Dans `mediagenda/deploiement`, remplace le component `migrations` (Job `mediagenda-migrate`) par le Job **`mediagenda-migrations`** : image de migration, configuration Flyway par variables d'environnement (URL JDBC vers `mediagenda-db-rw` avec vérification du certificat de la base, utilisateur et mot de passe du migrateur), reprise à la version 2 **avec** le garde-fou, tentatives de connexion, délais et ressources, contexte de sécurité `restricted`. Mets à jour ce qui visait l'ancien Job (`livraison`, `identifiants-dynamiques` : le modèle de l'ExternalSecret du migrateur doit fournir ce dont Flyway a besoin) et la promotion des images (deux empreintes).
9. Recette : MR, synchronisation automatique. Lis le journal du Job : a-t-il fait une reprise ? `flyway_schema_history` contient-il une ligne `BASELINE` à la version 2, installée par qui ? Puis la prod (MR approuvée, sauvegarde `Completed` d'abord, synchronisation manuelle).
10. Une fois les **trois** environnements repris (dev compris), une MR retire `baselineOnMigrate` du Job. Pourquoi ne pas le laisser « au cas où » ? Documente le tout dans `docs/donnees/migrations.md` (règles d'écriture, commande de diagnostic, ce que fait le Job, ce qu'on ne fait jamais : `repair` sans ticket, modifier une migration publiée).

**Critères de réussite**
- [ ] L'image `medisphere/mediagenda-migrations` existe dans Harbor à la même version que l'API, construite par la CI de `mediagenda/api` à partir de Flyway 13.11, et elle est signée.
- [ ] `mediagenda/deploiement` déclare le Job `mediagenda-migrations` (hook Sync, vague −1) ; l'ancien Job `mediagenda-migrate` n'est plus rendu.
- [ ] En recette et en prod, le dernier Job `mediagenda-migrations` s'est terminé avec succès, sous Pod Security `restricted`, avec le compte migrateur dynamique.
- [ ] `flyway_schema_history` existe en recette et en prod, avec une reprise (`BASELINE`) à la version 2 et aucune réapplication de `V1` ni `V2`.
- [ ] Le Job ne passe pas par le pooler.
- [ ] `docs/donnees/migrations.md` existe sur `main`.

**Vérification** : `lab/bin/check 27 05`

<details><summary>Indice 1</summary>

Flyway lit chaque paramètre aussi dans une variable d'environnement : `FLYWAY_` suivi du nom du paramètre en majuscules, mots séparés par `_` (`baselineOnMigrate` → `FLYWAY_BASELINE_ON_MIGRATE`). Attention : une variable mal orthographiée est **ignorée sans message**. Dans l'image officielle, l'emplacement par défaut est le dossier `sql` du répertoire d'installation (`/flyway/sql`).
</details>

<details><summary>Indice 2</summary>

Flyway veut une URL **JDBC** (`jdbc:postgresql://hôte:5432/base?…`) et l'utilisateur à part, pas l'URL `postgresql://u:p@…` que fabrique le component du M25 : ajoute des clés au **modèle** de l'ExternalSecret du migrateur. CloudNativePG publie la CA de la base dans le Secret `mediagenda-db-ca` (clé `ca.crt`) ; le pilote JDBC accepte `sslmode=verify-full&sslrootcert=<fichier>`. Le certificat serveur de CNPG porte les noms des Services `-rw`, `-ro`, `-r`.
</details>

<details><summary>Indice 3</summary>

`baselineOnMigrate` ne fait rien sur un schéma **vide** (un dev reconstruit rejoue V1 et V2 normalement) ; sur un schéma non vide **sans** historique, il crée la ligne de reprise… et déclenche les rappels `beforeBaseline`. Le rappel s'exécute dans la base, avec le compte du migrateur : il peut lire `mediagenda_historique_schema`.
</details>

**Pour aller plus loin** (facultatif) : Liquibase 5 et Atlas font le même travail. Lis leurs licences actuelles (annexe des versions) et ce que l'édition libre de chacun ne fait plus : tu en auras besoin pour l'ADR-0270.
