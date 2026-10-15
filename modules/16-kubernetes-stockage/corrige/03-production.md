# Module 16 — Corrigé du palier 3 : Production

> ⚠️ Corrigé — à lire après avoir cherché.

**Points non testés en conditions réelles** (signale tes retours, ils corrigent le workbook) :
- Velero 1.18 : sélecteur de restauration par **absence** de label (`labelSelector.matchExpressions` `DoesNotExist`) combiné au remappage ; remappage des sujets des RoleBindings ; comportement exact des modificateurs de ressources sur un champ tableau (`/spec/hostnames` remplacé par une valeur JSON échappée, comme dans l'exemple officiel) ;
- CloudNativePG 1.30 : nom du pod de récupération (`<cluster>-1-full-recovery-*`) ; présence de `cnpg_pg_stat_archiver_*` dans la configuration de supervision par défaut de ta version ; effet d'une nouvelle version du plugin Barman Cloud sur le *sidecar* des instances (redémarrage ou non). (Lus dans le code au tag v1.30.1 : label `cnpg.io/cluster` posé sur tous les objets générés, Secret `-app` compris ; clé `uri` qui contient l'espace, clé `host` qui ne le contient pas ; `switchoverDelay` à 3600 s par défaut ; `kubectl cnpg pgbench` vise la base `app` sauf `--db-name`.)
- ceph-csi 3.18 : collision du nom de ConfigMap de KMS entre les charts `ceph-csi-rbd` et `ceph-csi-cephfs` installés dans le même espace (lue dans les gabarits des charts 3.18.1, non essayée) ; création d'un volume chiffré par clone d'un instantané **en clair** (comportement non documenté : le corrigé recommande de ne pas s'y fier) ; (lus dans le code au tag v3.18.1 : métadonnées d'image `rbd.csi.ceph.com/encrypted` et `rbd.csi.ceph.com/dek`, KEK cherchée dans les Secrets de la requête sans `secretName`, même DEK ré-enveloppée pour un clone, agrandissement refusé avec `integrityMode`) ;
- Cilium 1.20 : identité `kube-apiserver` (entité) pour le trafic du proxy de l'API vers un pod ; selon la configuration, il peut porter `remote-node` ou `host` ;
- kubelet : certificat de service signé par la CA du cluster (`serverTLSBootstrap`, M14-E26) et portant le nom court du nœud ;
- `ansible-vault encrypt` lisant l'entrée standard (`-`) ; `valkey-cli` et la variable `REDISCLI_AUTH` ;
- durées indicatives (restauration, import, montée en place, migration) : elles dépendent du volume de données de ta recette.

**Rappel** : aucune nouvelle VM dans ce palier. Fichiers de solution : `corrige/fichiers/M16-E24/` à `M16-E30/`, `M16-E32/` à `M16-E34/`. L'injection de E34 : `corrige/pannes/break-E34.sh`.

**Faits posés par ce palier** (repris par le palier 4 et le mini-projet) : espace `wb-restauration` (vide entre deux essais) ; classe `ceph-rbd-chiffre` (KMS `secrets-metadata`, Secret `ceph-csi/csi-rbd-secret-chiffre`) ; Valkey de la recette sur `ceph-rbd-chiffre` ; sonde `ms-verif-k8s-stockage` et compte `wb-system/ms-supervision-stockage` ; image `plateforme/outils-stockage:1.0.0` ; runbooks RB-161 (restaurer un espace), RB-162 mis à jour (E34), RB-163 (migrer un volume), RB-164 (mettre à jour le stockage) ; ADR-0160 ; `docs/kubernetes/stockage/politique-sauvegarde.md`.

---

### M16-E24 — Restaurer un espace de noms complet ailleurs

**Solution**

Fichiers : espace [`wb-restauration`](fichiers/M16-E24/k8s/espaces/wb-restauration.yaml), [modificateurs](fichiers/M16-E24/k8s/composants/velero/restaurations/modificateurs-restauration.yaml), [`Restore`](fichiers/M16-E24/k8s/composants/velero/restaurations/e24-recette-vers-restauration.yaml), [`Cluster` de récupération](fichiers/M16-E24/k8s/composants/cnpg/wb-restauration/mediagenda-db-recuperation.yaml), [`outils/empreinte-mediagenda.sh`](fichiers/M16-E24/k8s/outils/empreinte-mediagenda.sh), [RB-161](fichiers/M16-E24/medisphere/docs/kubernetes/stockage/runbooks/RB-161-restaurer-un-espace-de-noms.md), [modèle de compte rendu](fichiers/M16-E24/medisphere/docs/kubernetes/stockage/tests/restauration-espace-de-noms.md).

*1. Lecture* (réponses attendues) :
- **Ordre** : Velero restaure d'abord les ressources « socles » (CRD, espaces de noms, classes, PV, PVC, Secrets, ConfigMaps, comptes de service…), puis les charges ; l'ordre par défaut est dans *Restore Reference* et se change par `--restore-resource-priorities`.
- **PV et PVC remappés** : le PVC est recréé dans l'espace cible ; pour une liaison dynamique, Velero retire `volumeName` et les annotations de liaison, et le volume est **reprovisionné** puis rempli par le *data mover* (`DataDownload`) ; un PV restauré tel quel (instantané natif) dont le PVC change d'espace voit son `claimRef.namespace` remappé, et il est **renommé** (`velero-clone-<uuid>`) s'il existe déjà dans le cluster.
- **Objet existant** : ignoré par défaut (`existingResourcePolicy: none`), sauf les comptes de service (fusion) ; `update` tente un correctif, sans toucher aux données des PVC.
- **Modificateurs** : correctifs JSON Patch, *merge patch* ou *strategic merge* appliqués avant la création, filtrés par groupe-ressource, nom, espace **d'origine**, labels ; ils ne savent ni supprimer un objet de la restauration (c'est le rôle des filtres), ni lire un autre objet.
- **Filtrer** : ressources incluses/exclues, espaces, `labelSelector` (avec expressions) ou `orLabelSelectors`.
- **CloudNativePG** : un `Cluster` avec `bootstrap.recovery` et un `externalClusters` de type plugin (`barmanObjectName`, `serverName`) redémarre depuis la dernière sauvegarde de base et rejoue les WAL ; les bases et les rôles viennent de la sauvegarde, mais `bootstrap.recovery.database` et `owner` (défaut : `app`) désignent la base applicative pour laquelle l'opérateur génère le Secret `-app` (et crée base et rôle s'ils manquent) : ici `mediagenda`, sinon le Secret vise une base `app` vide ; les Secrets ne sont **pas** dans la sauvegarde (le `-app` est régénéré, et le mot de passe du propriétaire de la copie aligné sur lui) ; un cluster qui archiverait dans une archive non vide reste en `Setting up primary` avec `Expected empty archive`.
- **Pourquoi pas les PVC et les pods de la base par Velero** : l'opérateur gère l'identité des instances (PVC nommés, rôles primaire/réplica, timelines, état dans `status`) ; des volumes restaurés sans cet état (Velero retire le `status`) donnent un cluster incohérent ; et l'instantané d'un volume de base pris pendant l'activité n'est cohérent qu'en cas de panne, sans garantie sur l'archive des WAL. La base se restaure par son outil, à l'instant voulu.

*2. Inventaire* (classement attendu, à adapter à ton espace) :

| Objet | Sort | Pourquoi |
|---|---|---|
| Deployment de l'API, Service, ConfigMap, Secret `harbor-pull` | restaurés tels quels | aucun nom d'espace dans leur contenu (vérifie tes ConfigMaps : un `MEDIAGENDA_*` qui contiendrait `…mediagenda-recette.svc` serait à corriger) |
| StatefulSet Valkey + PVC `donnees-valkey-0` | restaurés ; données par le *data mover* | |
| HTTPRoute `mediagenda` | restaurée **modifiée** (nom d'hôte) | sinon deux routes pour le même nom sur `gw-par1` (même si l'espace n'est pas autorisé par `allowedRoutes`, le nom ne doit pas être revendiqué) |
| CronJobs éventuels | restaurés **suspendus** | une purge ou un export en double |
| NetworkPolicies, CiliumNetworkPolicies | restaurées ; **à relire** | un `namespaceSelector` sur `kubernetes.io/metadata.name: mediagenda-recette` ouvrirait la copie à la recette ; les politiques du M15 n'utilisent que des `podSelector` dans l'espace, plus l'espace `passerelles` et `kube-system` |
| RoleBindings | restaurés | sujets de type ServiceAccount de l'espace : remappés par Velero (à vérifier sur ta version : `kubectl get rolebinding -n wb-restauration -o yaml`) ; groupes (`medisphere:mediagenda-devs`) : inchangés, voulu |
| ResourceQuota, LimitRange de la recette | ignorés si un objet du même nom existe déjà, sinon restaurés | le quota de `wb-restauration` est celui du code |
| `ObjectStore` `cnpg-s3` + Secret de ses identifiants | restaurés | la copie doit **lire** les archives |
| `Cluster`, `Backup`, `ScheduledBackup`, `Pooler` | **exclus** | reconstruits (cluster) ou interdits (sauvegardes depuis la copie) |
| Pods, PVC, Services, Secrets, PDB générés par l'opérateur (label `cnpg.io/cluster`) | **exclus** | l'opérateur les recrée pour la copie |
| Secret `mediagenda-db-app` | exclu (label) **et** à surveiller | son `uri` contient `mediagenda-db-rw.mediagenda-recette` : restauré tel quel, il ferait viser la base de la **recette** par l'API de la copie |
| Événements | exclus | bruit |

*3. Préparer* : MR sur `plateforme/k8s` avec les quatre fichiers ; `task appliquer` crée l'espace et la ConfigMap (le `Restore` et le `Cluster` ne sont **pas** appliqués par `task appliquer` : ce sont des opérations).

*4. Sauvegarde de référence* :

```
admin@adm01:~$ ~/src/k8s/outils/empreinte-mediagenda.sh mediagenda-recette
rendez_vous=42 empreinte=3b9c…
valkey_cles=118
admin@adm01:~$ velero backup create e24-recette --include-namespaces mediagenda-recette --snapshot-move-data --wait
admin@adm01:~$ velero backup describe e24-recette --details | sed -n '/Backup Volumes/,$p'
```

Le détail montre les volumes déplacés par le *data mover* (Valkey **et** les trois PVC de `mediagenda-db` : la sauvegarde planifiée les contient aussi ; on ne les restaure pas, mais une sauvegarde qui les exclut — label `velero.io/exclude-from-backup` ou politique de ressources — économise de la place : décision à écrire dans la politique de sauvegarde, E32).

*5. Restaurer* :

```
admin@adm01:~$ kubectl apply -f ~/src/k8s/composants/velero/restaurations/e24-recette-vers-restauration.yaml
admin@adm01:~$ velero restore describe e24-recette-vers-restauration --details
admin@adm01:~$ kubectl get datadownloads.velero.io -n velero -w
admin@adm01:~$ velero restore logs e24-recette-vers-restauration | grep -Ei 'error|warn' | head
admin@adm01:~$ kubectl apply -f ~/src/k8s/composants/cnpg/wb-restauration/mediagenda-db-recuperation.yaml
admin@adm01:~$ kubectl cnpg status mediagenda-db -n wb-restauration
admin@adm01:~$ kubectl get pods -n wb-restauration -w
```

Pendant la récupération, un pod `mediagenda-db-1-full-recovery-…` télécharge la sauvegarde de base puis rejoue les WAL ; ensuite le pod `mediagenda-db-1` démarre en primaire, l'opérateur crée les Services `-rw`/`-ro`/`-r` et le Secret `mediagenda-db-app` (hôte `mediagenda-db-rw.wb-restauration`). Les pods de l'API, restaurés plus tôt, passent prêts dès que `/pret` voit PostgreSQL **et** Valkey : c'est la fin du RTO technique.

*6. Contrôler* :

```
admin@adm01:~$ ~/src/k8s/outils/empreinte-mediagenda.sh wb-restauration
rendez_vous=42 empreinte=3b9c…            # identique
valkey_cles=118                           # identique
admin@adm01:~$ kubectl port-forward -n wb-restauration svc/mediagenda-api 18000:80 &
admin@adm01:~$ curl -s localhost:18000/pret ; curl -s 'localhost:18000/api/v1/rendez-vous?limite=3' | jq length
admin@adm01:~$ kubectl get secret mediagenda-db-app -n wb-restauration -o jsonpath='{.data.uri}' | base64 -d | sed -E 's#^[^@]*@##; s#/.*##' ; echo   # mediagenda-db-rw.wb-restauration:5432 (sans le mot de passe)
admin@adm01:~$ kubectl cnpg psql mediagenda-db -n wb-restauration -- -At -c "SELECT count(*) FROM pg_stat_activity WHERE application_name NOT LIKE 'cnpg%' AND backend_type = 'client backend'"
admin@adm01:~$ kubectl get httproute -n wb-restauration -o jsonpath='{.items[*].status.parents[*].conditions[?(@.type=="Accepted")].status}'   # False
admin@adm01:~$ dig +short mediagenda-restauration.apps.par1.medisphere.internal                                              # rien
admin@adm01:~$ kubectl get cronjob -n wb-restauration -o jsonpath='{.items[*].spec.suspend}'                                 # true…
admin@adm01:~$ set -a; . ~/.config/workbook/s3-cnpg.env; set +a
admin@adm01:~$ aws --endpoint-url https://s3-01.par1.medisphere.internal:8333 s3 ls s3://cnpg-k8s-par1/          # un seul préfixe : mediagenda-db/
```

La clé `host` du Secret ne contient que `mediagenda-db-rw` (nom court, résolu dans l'espace du pod) ; c'est `uri`, la clé que lit l'API, qui porte l'espace (`mediagenda-db-rw.<espace>:5432`) : c'est donc elle qu'on contrôle, en coupant le mot de passe avant tout affichage. Le Service `mediagenda-api` (M14) écoute en 80 et renvoie vers le port `http` (8000) des pods. Le dernier contrôle porte sur le compartiment : il ne doit y avoir que les préfixes des clusters qui archivent réellement (la copie n'a pas de `.spec.plugins`). Si ta CLI S3 n'est pas `aws`, prends celle du M05.

*7. Écrire* : compte rendu et RB-161 (fichiers). RTO typique sur le lab : 10 à 20 minutes (téléchargement des volumes par le *data mover*, téléchargement de la sauvegarde de base, rejeu des WAL depuis la dernière sauvegarde) : **mesure-le**, ne le recopie pas.

*8. Nettoyer* : suppression du `Cluster` (ses PVC partent avec), puis des objets restants de l'espace (RB-161) ; `kubectl get pv | grep wb-restauration` vide ; `rbd ls k8s-rbd` sur `ceph01` revenu au compte d'avant.

**Explications**

Velero est un outil **générique** : il sait recréer des objets Kubernetes et remplir des volumes, mais il ne sait rien de ce qu'il y a dedans. Une base de données opérée a un état (primaire, timelines, archive) que seul son opérateur sait reconstituer de façon cohérente, et un outil propre pour remonter à un instant précis. La bonne restauration combine donc les deux : Velero pour « tout sauf la base », CloudNativePG pour la base, chacun avec sa sauvegarde, et un ordre (les objets de l'espace, dont l'`ObjectStore`, puis le `Cluster` de récupération). Le remappage d'espace est mécanique ; ce qui ne l'est pas, ce sont les **références au nom de l'espace** cachées dans les données des objets (chaînes de connexion, sélecteurs, noms d'hôtes) : c'est l'étape d'inventaire qui les trouve. Enfin, une copie de restauration est un **double** de l'original : il faut l'empêcher d'agir comme lui (publier, sauvegarder, archiver, exécuter des tâches).

**Alternatives**
- Restaurer **aussi** la base par Velero (volumes du `Cluster` + objet `Cluster`) : documenté par endroits pour des sauvegardes « à froid » (cluster hiberné pendant la sauvegarde), fragile à chaud ; écarté.
- Sauvegarde CloudNativePG par **instantanés de volumes** (`method: volumeSnapshot`, E19 pour aller plus loin) : récupération plus rapide qu'un téléchargement S3 pour une grosse base, mais les instantanés vivent dans le même Ceph : complément, pas remplacement.
- Restaurer dans un **autre cluster** (`m15-essai`, futur cluster de secours) avec le BSL en lecture seule : la vraie répétition d'un PRA (F5).
- `--existing-resource-policy=update` pour restaurer « par-dessus » un espace abîmé : n'écrase pas les données des volumes ; utile pour des objets, dangereux comme réflexe.

**Pièges classiques**
- Oublier `namespaceMapping` (les objets manquants sont recréés dans la recette).
- Restaurer le Secret `-app` : l'API de la copie vise la base de la recette (bloquée ici par les politiques réseau… ou pas, selon les tiennes).
- Oublier `database`/`owner` dans `bootstrap.recovery` : l'API restaurée se connecte à une base `app` vide créée par l'opérateur.
- Mettre `.spec.plugins` dans le `Cluster` de récupération « pour être complet » : la copie archive dans le même préfixe, l'opérateur la bloque (`Expected empty archive`) — ou pire, avec un autre `serverName`, elle remplit le compartiment de la recette.
- Comparer seulement le nombre d'objets restaurés : seule une empreinte des **données** prouve la restauration.
- Laisser la copie en place « pour plus tard » : une copie de données de santé non suivie.

**En production chez MédiSphère**
Restauration trimestrielle chronométrée dans `wb-restauration` (preuve HDS), puis vers un cluster de secours à PAR2 (F5) ; sauvegardes Velero qui excluent les volumes des bases (économie, et pas de fausse impression de sauvegarde) ; script de contrôle d'empreintes fourni par chaque équipe applicative pour ses propres données.

---

### M16-E25 — PostgreSQL : bascule, maintenance et montée de version

**Solution**

Fichiers : [`pg-essai.yaml`](fichiers/M16-E25/wb-essais/pg-essai.yaml), [`pg-essai-import.yaml`](fichiers/M16-E25/wb-essais/pg-essai-import.yaml), [`outils/temoin-api.sh`](fichiers/M16-E25/k8s/outils/temoin-api.sh) (la boucle de l'énoncé, avec un bilan), [extrait du `Cluster` `mediagenda-db`](fichiers/M16-E25/mediagenda/mediagenda-db-maintenance.extrait.yaml), [modèle de compte rendu](fichiers/M16-E25/medisphere/docs/kubernetes/stockage/tests/bascules-postgresql.md).

*1. Lecture* (réponses attendues) :
- **Bascule sur panne** : la sonde de disponibilité du primaire échoue ; au-delà de `failoverDelay` (0 s par défaut), l'opérateur marque la cible `pending`, ce qui force l'arrêt du primaire (arrêt *fast* borné par `switchoverDelay`, puis *immediate* ; *immediate* d'emblée si PostgreSQL ne répond plus), attend l'arrêt des récepteurs de WAL des réplicas, puis promeut le réplica le plus avancé. Depuis la 1.30, la promotion exige le **bail** Kubernetes (`Lease` `mediagenda-db`) : libéré proprement par un ancien primaire arrêté, ou expiré (`leaseDurationSeconds`) s'il a disparu.
- **Ancien primaire** : redémarre, constate qu'il n'est plus primaire, et rejoint comme réplica ; s'il a divergé (WAL écrits mais jamais reçus), il est resynchronisé par `pg_rewind` (si son PVC est disponible) ; sinon il est recloné.
- `unsupervised` : l'opérateur termine seul la mise à jour par le primaire (`restart` ou `switchover`) ; `supervised` : il s'arrête après les réplicas et attend `kubectl cnpg promote` (ou `restart`, mais pas pour une nouvelle image).
- **Majeure dans `imageName`** : mise à jour **en place hors ligne** : arrêt de toutes les instances, Job `<primaire>-major-upgrade` qui lance `pg_upgrade --link`, suppression des PVC des réplicas, redémarrage du primaire, reclonage des réplicas ; seulement entre images de la même distribution ; en cas d'échec, revenir à l'ancienne image suffit.
- **Synchrone** : `synchronous` (`method: any`, `number: 1`) rend une validation dépendante d'un réplica ; avec `dataDurability: required`, plus de réplica disponible = plus d'écriture (durabilité d'abord) ; avec `preferred`, la base continue en asynchrone (disponibilité d'abord).

*2. État initial* :

```
admin@adm01:~$ kubectl cnpg status mediagenda-db -n mediagenda-recette
admin@adm01:~$ kubectl get pdb,lease -n mediagenda-recette
admin@adm01:~$ kubectl get pods -n mediagenda-recette -l cnpg.io/cluster=mediagenda-db -o wide
```

L'opérateur crée deux PDB : un pour les réplicas, un (`-primary`) qui protège le primaire d'une éviction (un `kubectl drain` du nœud du primaire attend une bascule).

*3. Bascule planifiée* :

```
admin@adm01:~$ ~/src/k8s/outils/temoin-api.sh &                 # ou la boucle de l'énoncé
admin@adm01:~$ kubectl cnpg promote mediagenda-db mediagenda-db-2 -n mediagenda-recette
admin@adm01:~$ kubectl cnpg status mediagenda-db -n mediagenda-recette   # primaire 2, timeline +1
admin@adm01:~$ kubectl get endpointslices -n mediagenda-recette -l kubernetes.io/service-name=mediagenda-db-rw -o wide
```

Indisponibilité typique : quelques secondes (arrêt propre de l'ancien primaire, promotion, mise à jour du Service `-rw`, renouvellement des connexions du pool psycopg de l'API) ; **0** rendez-vous acquitté perdu : l'ancien primaire s'est arrêté proprement, tout ce qu'il avait validé était reçu par le réplica promu.

*4. Bascule sur panne* :

```
admin@adm01:~$ kubectl delete pod mediagenda-db-2 -n mediagenda-recette --grace-period=0 --force
admin@adm01:~$ kubectl cnpg status mediagenda-db -n mediagenda-recette
admin@adm01:~$ kubectl logs -n mediagenda-recette mediagenda-db-2 -c postgres | grep -i rewind
```

Indisponibilité typique : une à quelques dizaines de secondes (détection, élection, et attente du bail si l'ancien n'a pas pu le libérer). `pg_rewind` apparaît quand l'ancien primaire avait écrit des WAL que le nouveau n'a pas reçus avant la promotion : sa timeline a divergé, il faut « rembobiner » ses fichiers jusqu'au point de bifurcation avant de suivre la nouvelle timeline. Après une bascule planifiée, il n'y a pas de divergence (arrêt propre, WAL envoyés), donc pas besoin. Avec la réplication synchrone d'E18 (`any 1`, `dataDurability: required`), toute transaction acquittée (201) existe sur au moins une réplique, et l'opérateur promeut la plus avancée : **0** rendez-vous perdu attendu, ici aussi. En asynchrone, des transactions validées par l'ancien primaire et non reçues seraient **perdues** (un 201 reçu, puis le rendez-vous absent) : c'est le RPO non nul de l'asynchrone. Si ton témoin en montre, vérifie `synchronous_standby_names` et `pg_stat_replication` avant d'accuser l'opérateur.

*5. Isolement* :

```
admin@adm01:~$ kubectl cnpg fencing on mediagenda-db 3 -n mediagenda-recette
admin@adm01:~$ kubectl get pods -n mediagenda-recette -l cnpg.io/cluster=mediagenda-db     # mediagenda-db-3 0/1, Running
admin@adm01:~$ kubectl get endpointslices -n mediagenda-recette -l kubernetes.io/service-name=mediagenda-db-ro
admin@adm01:~$ kubectl get --raw /api/v1/namespaces/mediagenda-recette/pods/mediagenda-db-3:9187/proxy/metrics | grep fencing_on
admin@adm01:~$ kubectl cnpg fencing off mediagenda-db 3 -n mediagenda-recette
```

Le *postmaster* est arrêté mais le pod reste (non prêt) : il sort du Service `-ro`, la sonde E27 signale « 2/3 instances prêtes ». Usage : une instance en redémarrage en boucle (corruption, extension cassée) qu'on veut **examiner** (journaux, fichiers du PVC) sans qu'elle soit recréée ou reclonée. Isoler le primaire n'entraîne aucune bascule : la base est arrêtée jusqu'à la levée.

*6. Maintenance supervisée* : deux MR (voir l'extrait) : d'abord `primaryUpdateStrategy: supervised`, puis `max_connections`. L'opérateur redémarre les réplicas un par un, puis le cluster affiche qu'une bascule manuelle est attendue (`kubectl cnpg status`, métrique `cnpg_collector_manual_switchover_required` à 1) :

```
admin@adm01:~$ kubectl cnpg promote mediagenda-db <RÉPLICA-LE-PLUS-À-JOUR> -n mediagenda-recette
```

Décision du corrigé : la **recette reste en `supervised`** (les démonstrations ont lieu en journée, une bascule se décide et s'annonce) ; la production sera en `unsupervised` avec une fenêtre de maintenance, faute de quelqu'un pour « promouvoir » à chaque correctif de l'opérateur. Avec `primaryUpdateMethod: switchover`, ne change pas l'image et un paramètre dans la même MR : le webhook refuse.

*7. Mineure sur `pg-essai`* : `imageName` → `…:17.11-minimal-trixie` ; le réplica redémarre d'abord, puis bascule (méthode `switchover`) et redémarrage de l'ancien primaire ; indisponibilité : celle d'une bascule planifiée.

*8. Majeure* :

```
admin@adm01:~$ kubectl apply -f pg-essai.yaml          # puis données d'essai
admin@adm01:~$ kubectl cnpg pgbench pg-essai -n wb-essais --db-name essai --job-name pgbench-init -- --initialize --scale 5
admin@adm01:~$ kubectl cnpg psql pg-essai -n wb-essais -- -d essai -At -c 'SELECT count(*) FROM pgbench_accounts'
admin@adm01:~$ kubectl apply -f pg-essai-import.yaml   # (a) import, source en 17.11
admin@adm01:~$ kubectl cnpg psql pg-essai-import -n wb-essais -- -d essai -At -c 'SELECT count(*) FROM pgbench_accounts'
admin@adm01:~$ kubectl patch cluster pg-essai -n wb-essais --type merge \
    -p '{"spec":{"imageName":"registry.par1.medisphere.internal/ghcr/cloudnative-pg/postgresql:18.6-minimal-trixie"}}'   # (b)
admin@adm01:~$ kubectl get jobs,pods -n wb-essais -w            # pg-essai-1-major-upgrade
admin@adm01:~$ kubectl cnpg psql pg-essai -n wb-essais -- -d essai -c 'ANALYZE'
admin@adm01:~$ kubectl cnpg psql pg-essai -n wb-essais -- -At -c 'SELECT version()'
```

(La commande `kubectl cnpg pgbench` crée un Job qui se connecte avec le Secret `pg-essai-app` à la base `app` par défaut : `--db-name essai` est indispensable ici. L'échelle 5 donne 500 000 lignes, environ 75 Mio, compatibles avec un volume de 1 Gio.) Comparaison (voir le modèle de compte rendu) : l'import laisse la source intacte (retour arrière immédiat) mais impose de geler les écritures pendant la copie ou de passer par la réplication logique pour une bascule en ligne ; la voie en place arrête **tout** le cluster, mais sa durée dépend peu du volume (`--link`) ; dans les deux cas, l'archive des WAL repart d'un nouveau système (nouvel identifiant de système) : changer le `serverName` du plugin au même moment et faire une sauvegarde de base aussitôt, car aucune restauration à un instant donné ne traverse une majeure.

*9.* `outils/temoin-api.sh --nettoyer`. Puis suppression de `pg-essai` et `pg-essai-import` après la vérification.

**Explications**

CloudNativePG ne s'appuie ni sur un DCS (etcd, Consul) comme Patroni, ni sur un StatefulSet : l'opérateur gère directement les pods et les PVC de chaque instance, et l'API Kubernetes **est** la source de vérité (statut du `Cluster`, bail). Une bascule est donc une suite d'actions de l'opérateur, observables dans le statut et les événements. Côté application, l'indisponibilité ne se résume jamais à la promotion : le Service doit pointer vers le nouveau primaire, et les connexions établies vers l'ancien doivent être fermées et rouvertes — d'où l'importance d'un pool de connexions qui détecte les erreurs, et d'une sonde `/pret` qui ne fait pas sortir **tous** les pods de l'API du Service pour quelques secondes de base indisponible (point repris en E29). `pg_rewind` existe parce qu'une bascule sur panne peut laisser l'ancien primaire « en avance » sur une branche qui n'existe plus.

**Alternatives**
- Réplication synchrone `any 1` + `dataDurability: preferred` (au lieu du `required` d'E18) : RPO nul tant qu'un réplica suit, sans bloquer les écritures quand les deux réplicas manquent ; la garantie tombe alors en silence : choix de disponibilité, à écrire dans la politique (E32). Coût commun aux deux : la latence de chaque validation (un aller-retour de plus, voir E28 `wal`).
- PgBouncer (`Pooler` de CloudNativePG) devant la base : les applications gardent leurs connexions au *pooler*, qui suit le primaire ; en mode `transaction`, une bascule devient presque invisible.
- Montée majeure en ligne par réplication logique (`Publication`/`Subscription`), puis bascule de l'application : quasi sans coupure, plus complexe (séquences, DDL non répliquée).

**Pièges classiques**
- Mesurer la bascule dans `kubectl cnpg status` (secondes) et la promettre à Julien, alors que le témoin voit davantage.
- Isoler le primaire « pour voir » : la recette s'arrête.
- Changer image et paramètres dans la même MR en `switchover` : refus du webhook.
- Montée majeure entre familles d'images différentes (`system` ↔ `minimal`/`standard`, ou bookworm ↔ trixie) : refusée.
- Oublier `ANALYZE` après `pg_upgrade` (statistiques non transférées : plans de requête mauvais).
- Garder le même `serverName` après une majeure : archive mélangée de deux systèmes.

**En production chez MédiSphère**
Bascules planifiées en fenêtre, annoncées, avec le témoin ; exercice de bascule sur panne trimestriel ; `Pooler` devant les bases de production ; réplication synchrone `required` gardée pour MédiAgenda (RPO nul, au prix des écritures suspendues si les deux réplicas manquent) ; montée majeure annuelle répétée sur un clone (`pg-essai` à partir d'une sauvegarde de production anonymisée), avec nouveau `serverName` et sauvegarde immédiate.

---

### M16-E26 — Chiffrer les volumes

**Solution**

Fichiers : [extrait de `values-rbd.yaml`](fichiers/M16-E26/k8s/composants/ceph-csi/values-rbd.chiffrement.extrait.yaml), [classe `ceph-rbd-chiffre`](fichiers/M16-E26/k8s/composants/ceph-csi/classes/ceph-rbd-chiffre.yaml), [`outils/secret-rbd-chiffre.sh`](fichiers/M16-E26/k8s/outils/secret-rbd-chiffre.sh) (voisin de `outils/ceph-csi-secrets.sh`, même fichier Vault), [volumes d'essai](fichiers/M16-E26/wb-essais/e26-volumes.yaml), [`chiffrement.md`](fichiers/M16-E26/medisphere/docs/kubernetes/stockage/chiffrement.md).

*1. Lecture* (ceph-csi 3.18.1, `docs/rbd/deploy.md`) : à la **création**, l'image est créée et, si un KMS est utilisé, une phrase (DEK) est générée et stockée ; l'état `encryptionPrepared` est écrit dans les métadonnées de l'image. Au **premier montage**, le *nodeplugin* récupère la phrase, formate le périphérique en LUKS, passe l'état à `encrypted`. Aux montages suivants, il ouvre le LUKS et monte le périphérique du *device-mapper*. À la **suppression**, la phrase est retirée du KMS (erreurs ignorées). Fournisseurs : phrase **unique** dans les Secrets de la classe (clé `encryptionPassphrase`, une même phrase pour tous les volumes) ; `metadata` (DEK par volume, chiffrée par la KEK, rangée dans la métadonnée de l'image ; KEK lue dans le Secret nommé par `secretName`/`secretNamespace` de la configuration du KMS ou, à défaut, dans les Secrets **de la requête** : ceux de la StorageClass pour créer et monter, mais ceux de la VolumeSnapshotClass pour un instantané) ; Vault (`vault`, `vaulttokens`, `vaulttenantsa`) et d'autres KMS. **Interdit** : activer le chiffrement sur une classe qui a déjà des volumes, ou sur un volume existant. Paramètres : `encryptionCipher` (`aes-xts-plain64` par défaut), `encryptionKeySize`, `encryptionSectorSize`, `integrityMode` (dm-integrity : **interdit l'agrandissement**).

*2. Modèle de menace* : voir [`chiffrement.md`](fichiers/M16-E26/medisphere/docs/kubernetes/stockage/chiffrement.md). Le point qui surprend : le ClusterRole du *nodeplugin* RBD (chart 3.18) donne `get/list/watch` sur **tous** les Secrets du cluster (pour lire les jetons Vault des espaces locataires) : le *nodeplugin* est de fait un composant de confiance de niveau administrateur, et quiconque peut exécuter du code dans son pod lit tout. Conséquence : la KEK dans un Secret ne protège **pas** contre les administrateurs de Kubernetes ; elle protège contre ceux de Ceph et contre les copies d'images. C'est l'objet de la bascule vers Vault (M25).

*3. La KEK* :

```
admin@adm01:~/src/k8s$ export KEK="$(openssl rand -base64 48)"
admin@adm01:~/src/k8s$ uv run --project ~/src/ansible ansible-vault view --vault-id critique@$HOME/src/ansible/outils/vault-pass-client.sh secrets/ceph-csi.yml \
    | yq '.ceph_csi_rbd_kek = strenv(KEK)' \
    | uv run --project ~/src/ansible ansible-vault encrypt --vault-id critique@$HOME/src/ansible/outils/vault-pass-client.sh --output secrets/ceph-csi.yml.nouveau -
admin@adm01:~/src/k8s$ unset KEK ; mv secrets/ceph-csi.yml.nouveau secrets/ceph-csi.yml
admin@adm01:~/src/k8s$ outils/secret-rbd-chiffre.sh --verifier
```

La KEK n'apparaît ni à l'écran, ni dans l'historique, ni sur le disque en clair (variable d'environnement du shell courant seulement, puis supprimée). Copie hors ligne : `ansible-vault view … | yq .ceph_csi_rbd_kek` imprimé une fois, sous enveloppe scellée au coffre, inscrit au registre des secrets (propriétaire, emplacement, date). Puis `outils/secret-rbd-chiffre.sh` crée `csi-rbd-secret-chiffre`.

*4. Pilote et classe* : MR (valeurs + classe), `task appliquer` (le chart RBD est mis à jour : ConfigMap de KMS, redémarrage progressif des pods du pilote).

```
admin@adm01:~$ kubectl get cm -n ceph-csi -o json | jq -r '.items[] | select(.data["config.json"] // "" | contains("secrets-metadata")) | .metadata.name'
admin@adm01:~$ kubectl get sc ceph-rbd -o yaml | grep -E 'encrypt|is-default'      # aucune clé encrypt, défaut true
```

Le fournisseur désigne la KEK **par son nom** (`secretName: csi-rbd-secret-chiffre`, `secretNamespace: ceph-csi`). Sans cela, un instantané de `e26-temoin` par `ceph-rbd-snap` (dont le Secret est `csi-rbd-secret`, sans KEK) échoue (`missing "encryptionPassphrase" in storageclass secret` dans le `csi-rbdplugin` du provisioner, contenu d'instantané en erreur) : ceph-csi doit relire la DEK de la source pour l'instantané, avec les Secrets de la classe d'instantané. Les sauvegardes Velero par déplacement des données d'instantanés (Valkey sur la classe chiffrée après E29, planification du mini-projet) échoueraient de même. L'autre solution — une classe d'instantanés dédiée qui nomme `csi-rbd-secret-chiffre`, imposée aux PVC chiffrés par l'annotation `velero.io/csi-volumesnapshot-class` — marche aussi, mais il faut y penser pour chaque volume.

La ConfigMap de KMS du pilote RBD garde son nom par défaut (`ceph-csi-encryption-kms-config`) : celle du chart CephFS a été renommée en E07 (`ceph-csi-encryption-kms-config-cephfs`), justement parce que les deux charts créent par défaut la même ConfigMap dans le même espace. Si l'application du chart échoue avec un conflit de propriété sur cette ConfigMap, c'est que ce renommage manque dans `values-cephfs.yaml`.

*5. La preuve* :

```
admin@adm01:~$ kubectl apply -f e26-volumes.yaml
admin@adm01:~$ kubectl get pvc -n wb-essais e26-temoin e26-clair
admin@adm01:~$ kubectl get pod -n wb-essais e26-temoin -o jsonpath='{.spec.nodeName}{"\n"}'
admin@k8s-w02:~$ lsblk -o NAME,TYPE,SIZE,MOUNTPOINT | grep -B1 -A1 crypt
admin@k8s-w02:~$ sudo cryptsetup status /dev/mapper/<NOM-DU-MAPPAGE>
admin@k8s-w02:~$ sudo cryptsetup luksDump /dev/rbd<N> | head -20          # LUKS2, aes-xts-plain64, un emplacement de clé
admin@adm01:~$ kubectl get pv $(kubectl get pvc -n wb-essais e26-temoin -o jsonpath='{.spec.volumeName}') -o jsonpath='{.spec.csi.volumeAttributes.imageName}{"\n"}'
[admin@ceph01 ~]$ sudo rbd image-meta list k8s-rbd/<IMAGE-TEMOIN>
[admin@ceph01 ~]$ sudo rbd export k8s-rbd/<IMAGE-TEMOIN> - | grep -c MEDISPHERE-E26-TEMOIN-7f3c9a     # 0
[admin@ceph01 ~]$ sudo rbd export k8s-rbd/<IMAGE-CLAIR> - | grep -c MEDISPHERE-E26-TEMOIN-7f3c9a      # > 0
```

`cryptsetup status` montre le chiffrement, la taille de clé, le périphérique sous-jacent ; `luksDump` l'en-tête LUKS2 (la phrase n'est **nulle part** sur le nœud de façon durable : elle est passée à `cryptsetup` à l'ouverture, puis seule la clé maîtresse vit dans le noyau tant que le volume est ouvert). `image-meta list` montre `rbd.csi.ceph.com/encrypted` = `encrypted` et `rbd.csi.ceph.com/dek` = la DEK **chiffrée** par la KEK. L'export de l'image chiffrée ne contient pas la chaîne ; celui de l'image en clair, si (des milliers d'occurrences : `grep -c` compte des lignes du flux binaire, peu importe).

Instantané et clone : le clone restauré depuis l'instantané de `e26-temoin` (dans `ceph-rbd-chiffre`) est chiffré ; ceph-csi relit la DEK en clair de la source et la stocke, ré-enveloppée, pour le clone : **même DEK** (les blocs sont les mêmes, copiés à l'écriture), enveloppe différente. Conséquence : compromettre la DEK d'un volume compromet ses clones.

*6. Transit* :

```
admin@adm01:~$ kubectl get sc -o custom-columns=NOM:.metadata.name,MAP:.parameters.mapOptions,MOUNT:.parameters.kernelMountOptions
admin@k8s-w02:~$ ss -tn state established '( dst 10.10.30.51 or dst 10.10.30.52 or dst 10.10.30.53 )' | awk '{print $4}' | sort | uniq -c
admin@k8s-w02:~$ sudo dmesg | grep -E 'libceph|ceph:' | tail
```

Attendu : `krbd:ms_mode=secure` pour les trois classes RBD, `ms_mode=secure` dans `kernelMountOptions` de `cephfs` (posés en E06-E07 : sans eux, les montages échoueraient contre `ms_service_mode secure`) ; connexions vers le port **3300** seulement (msgr2) ; journal du noyau sans erreur de négociation. Non protégé : les métadonnées de trafic (qui parle à qui, volumes) ; et rien n'empêche techniquement une classe future sans `ms_mode` de se connecter en msgr1 si les moniteurs annoncent encore leurs adresses v1 (M08-E27 : désactivation de msgr1 inscrite au ticket).

*7.* `chiffrement.md` (fichier), puis `kubectl delete pod,pvc e26-clair -n wb-essais` et suppression de l'instantané et du clone.

**Explications**

Le chiffrement « par le client » déplace la frontière de confiance : Ceph ne voit plus que des blocs chiffrés, donc ni un administrateur Ceph, ni une clé cephx, ni une copie d'image ne lisent les données. La clé se déplace donc vers Kubernetes, et toute la question devient : **qui** peut lire la KEK ? Avec le type `metadata`, la réponse en v1 est « quiconque lit les Secrets de `ceph-csi` », ce qui est acceptable pour un premier pas (la menace principale visée par Sophie était le stockage) et prépare le pas suivant (un KMS externe qui n'est pas dans le cluster). La DEK par volume limite l'effet d'une fuite (une DEK = un volume et ses clones) et permet de supprimer un volume de façon sûre (sans la DEK, les blocs restants sont illisibles : effacement cryptographique).

**Alternatives**
- Phrase unique dans le Secret de la classe (sans KMS) : plus simple ; une seule phrase pour tous les volumes, impossible à faire tourner sans tout migrer.
- Vault comme KMS dès maintenant : la bonne cible, mais Vault n'existe qu'au module 25 ; c'est la suite du ticket.
- Chiffrement dans l'application ou la base (pgcrypto, chiffrement de colonnes) : protège aussi contre les administrateurs de Kubernetes ; complémentaire, à la charge des équipes.
- `fscrypt` (`encryptionType: file`) : chiffrement au niveau des fichiers d'ext4 ; exige le support du noyau et laisse les métadonnées en clair.

**Pièges classiques**
- Ajouter `encrypted: "true"` à `ceph-rbd` (refusé ou incohérent : des volumes en clair et chiffrés dans la même classe).
- Mettre la KEK dans le Secret de `ceph-rbd` : rotation de la clé cephx et de la KEK liées, et la KEK suit toutes les classes.
- Laisser le fournisseur `metadata` sans `secretName` : création et montage marchent, les instantanés (et Velero) échouent sur les volumes chiffrés.
- Prouver le chiffrement par `lsblk` seulement : il montre le LUKS sur le nœud, pas ce que Ceph stocke ; la preuve, c'est l'export.
- `integrityMode` « pour faire bien » : l'agrandissement devient impossible.
- Perdre la KEK (Secret supprimé, coffre non relu) : tous les volumes perdus.

**En production chez MédiSphère**
KMS Vault (`vaulttenantsa`, une politique par espace) au module 25, DEK dans Vault et non dans Ceph ; règle d'admission (Kyverno, M26) qui impose `ceph-rbd-chiffre` aux PVC des espaces portant des données de santé ; test trimestriel de restauration d'un volume chiffré depuis Velero (la DEK suit-elle ?).

---

### M16-E27 — Superviser le stockage du cluster

**Solution**

Fichiers : projet `plateforme/outils` : [`bin/ms-verif-k8s-stockage`](fichiers/M16-E27/outils/bin/ms-verif-k8s-stockage), [`etc/ms-verif-k8s-stockage.conf`](fichiers/M16-E27/outils/etc/ms-verif-k8s-stockage.conf), [tests `bats`](fichiers/M16-E27/outils/tests/bats/ms-verif-k8s-stockage.bats) (20 tests, sans cluster), [unités systemd](fichiers/M16-E27/outils/systemd/), [extrait du Taskfile](fichiers/M16-E27/outils/Taskfile-install-extrait.yml), [section d'astreinte](fichiers/M16-E27/outils/docs/astreinte-extrait.md) ; projet `plateforme/k8s` : [RBAC](fichiers/M16-E27/k8s/rbac/ms-supervision-stockage.yaml), [`outils/kubeconfig-supervision-stockage.sh`](fichiers/M16-E27/k8s/outils/kubeconfig-supervision-stockage.sh) ; politiques de MédiAgenda : [CiliumNetworkPolicy du port 9187](fichiers/M16-E27/mediagenda/cnp-metriques-cnpg.yaml).

*1. Inventaire* : tableau en tête de la [section d'astreinte](fichiers/M16-E27/outils/docs/astreinte-extrait.md).

*2. L'identité* :

```
admin@adm01:~/src/k8s$ task appliquer                                  # rbac/ms-supervision-stockage.yaml
admin@adm01:~/src/k8s$ outils/kubeconfig-supervision-stockage.sh
system:serviceaccount:wb-system:ms-supervision-stockage
admin@adm01:~$ S=system:serviceaccount:wb-system:ms-supervision-stockage
admin@adm01:~$ for v in "get secrets -A" "get nodes/proxy" "create pvc -n wb-essais" "delete volumesnapshots -A" \
      "get pods/proxy -n wb-essais" "get pods/exec -n mediagenda-recette" "patch clusters.postgresql.cnpg.io -A"; do
      printf '%-45s %s\n' "$v" "$(kubectl auth can-i $v --as=$S)"; done          # tous « no »
admin@adm01:~$ kubectl auth can-i get nodes/metrics --as=$S                        # yes
admin@adm01:~$ kubectl auth can-i get pods/proxy -n mediagenda-recette --as=$S      # yes
```

Pourquoi pas `nodes/proxy` : c'est l'accès complet à l'API du kubelet (`/exec`, `/run`, `/logs`, ports des pods) ; le kubelet autorise `/metrics` par la sous-ressource `nodes/metrics` (et `/stats` par `nodes/stats`). Une minuterie quotidienne (`kubeconfig-supervision-stockage.timer`) renouvelle le jeton lié de 48 h (contrairement au jeton longue durée de `wb-checks`, exception documentée en M14-E06).

*3. Métriques du kubelet* :

```
admin@adm01:~$ K=~/.config/workbook/k8s-supervision-stockage.kubeconfig
admin@adm01:~$ T=$(kubectl --kubeconfig $K config view --raw --minify -o jsonpath='{.users[0].user.token}')
admin@adm01:~$ kubectl --kubeconfig $K config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > /tmp/ca-k8s.pem
admin@adm01:~$ curl -s --cacert /tmp/ca-k8s.pem -H "Authorization: Bearer $T" https://k8s-w02:10250/metrics | grep 'kubelet_volume_stats.*donnees-valkey-0'
```

(Si la vérification TLS échoue, le certificat de service du kubelet n'est pas signé par la CA du cluster : reprends M14-E26, rotation et approbation des CSR `kubelet-serving` ; ne passe pas en `-k`.) Un PVC en mode `Block` n'a pas de système de fichiers monté par le kubelet : pas de statistiques d'octets ni d'inodes (la surveillance de capacité se fait alors côté application ou côté Ceph). Un PVC non monté n'est sur aucun nœud : aucun kubelet ne le mesure ; c'est pourquoi la sonde ne s'alarme pas d'un PVC absent des métriques (elle couvre ce qui est monté) et surveille le pool `k8s-rbd` par `ms-verif-ceph`.

*4. Métriques de CloudNativePG* : politique du fichier (MR dans le dépôt des politiques de MédiAgenda), puis :

```
admin@adm01:~$ kubectl --kubeconfig $K get --raw /api/v1/namespaces/mediagenda-recette/pods/mediagenda-db-2:9187/proxy/metrics \
    | grep -E '^cnpg_(collector_up|pg_replication_lag|collector_fencing_on|pg_stat_archiver)' | head
```

Sans la politique, la requête expire (refus par défaut de M15). Si l'entité `kube-apiserver` ne suffit pas sur ta configuration, regarde le verdict dans Hubble (`hubble observe --to-pod mediagenda-recette/mediagenda-db-2 --port 9187`) pour voir l'identité réelle de la source.

*5. La sonde* : voir le script. Points de conception :
- **Une identité dédiée**, lue dans un kubeconfig dont le jeton expire : un jeton expiré produit `KO api`, pas un silence.
- **Les seuils dans la configuration**, et des seuils **temporels** (Pending depuis 15 min, non prêt depuis 30 min) : un PVC Pending pendant 10 secondes est normal (`WaitForFirstConsumer`, provisionnement en cours).
- **Les absences sont des anomalies** : aucune planification Velero, aucune sauvegarde réussie, aucun `Cluster`, un kubelet illisible.
- **Des droits et une configuration qui se répondent** : le retard de réplication n'est lu que dans les espaces où la sonde a `pods/proxy` (`MS_K8S_ESPACES_BASES`) ; les clusters d'essai de `wb-essais` (E25) restent surveillés sur leur phase et leur archivage, sans fausse alerte « métriques illisibles ».
- **Kubelet interrogé en direct**, nœud par nœud, avec le jeton et la CA du kubeconfig (fichier temporaire privé).
- **Tests** : `kubectl` et `curl` remplacés par des fonctions qui produisent du JSON et des métriques à partir de variables d'état ; un test vert, un test « rouge » par contrôle, un test de non-alerte (Pending récent), configuration vide, option inconnue.

*6. Planification et preuve* :

```
admin@adm01:~/src/outils$ task install:systeme && sudo systemctl enable --now ms-verif-k8s-stockage.timer
admin@adm01:~$ kubectl apply -n wb-essais -f - <<'FIN'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: e27-test-alerte}
spec: {accessModes: [ReadWriteOnce], storageClassName: classe-inexistante, resources: {requests: {storage: 1Gi}}}
FIN
admin@adm01:~$ sudo systemctl edit ms-verif-k8s-stockage.service     # drop-in de test : Environment=MS_CONF=/home/admin/m16/e27/conf-test (seuil 1 min)
admin@adm01:~$ journalctl -u ms-verif-k8s-stockage -n 5 ; journalctl -t ms-alerte -n 3
admin@adm01:~$ kubectl delete pvc e27-test-alerte -n wb-essais ; sudo systemctl revert ms-verif-k8s-stockage.service
```

Délai = seuil (15 min, ou 1 min en test) + jusqu'à 10 min (période du timer) + délai aléatoire (`RandomizedDelaySec`).

*7. Astreinte* : la section (fichier) ; installée par MR sur `plateforme/outils`.

**Explications**

Le stockage de Kubernetes ne tombe presque jamais « d'un coup » : il se dégrade (un PVC qui reste Pending, un *nodeplugin* qui ne revient pas sur un nœud après une mise à jour, une sauvegarde qui échoue une nuit, un archivage de WAL bloqué qui remplit doucement le disque du primaire). D'où une sonde qui regarde **l'âge** des choses autant que leur état, et qui vérifie le service rendu (sauvegardes réussies, archivage actif) plutôt que la simple présence des composants. Les droits de la sonde sont l'autre moitié de l'exercice : une sonde est un compte qui tourne en permanence, souvent oublié ; s'il lit les Secrets ou passe par `nodes/proxy`, c'est une porte d'entrée.

**Alternatives**
- kube-state-metrics + Prometheus + règles d'alerte (M21) : la cible ; la sonde reste comme contrôle de bout en bout indépendant, ou est remplacée par des règles qui reprennent exactement ses seuils.
- Alerter sur les **événements** Kubernetes (`ProvisioningFailed`, `FailedAttachVolume`, `FailedMount`) : rapide, mais bruyant et éphémère (une heure de rétention par défaut).
- Lire les métriques du kubelet par le proxy de l'API (`nodes/proxy`) : plus simple (un seul point d'accès), mais droit beaucoup trop large.

**Pièges classiques**
- `nodes/proxy` « parce que c'est ce que fait la documentation de Prometheus » (certaines configurations l'utilisent : c'est précisément ce qu'on évite).
- Jeton de compte de service sans expiration dans un fichier d'`adm01`.
- Ignorer les PVC de `wb-essais` « parce que ce sont des essais » : c'est là que la panne se voit d'abord.
- Seuils sans dimension temporelle : alertes à chaque provisionnement.
- Métriques CNPG lues sans politique réseau : la sonde dit « illisible » et on l'éteint, au lieu de corriger.

**En production chez MédiSphère**
Règles Prometheus équivalentes (M21) : `kubelet_volume_stats_*`, `kube_persistentvolumeclaim_status_phase`, métriques de Velero et de CloudNativePG (*PodMonitor*), tableaux de bord par équipe ; la sonde garde le rôle de contrôle de bout en bout, sous un compte qui ne voit rien de sensible.

---

### M16-E28 — Mesurer les performances des volumes

**Solution**

Fichiers : [Containerfile de `outils-stockage`](fichiers/M16-E28/images/outils-stockage/Containerfile), banc [`profils.fio`](fichiers/M16-E28/k8s/outils/banc-volumes/profils.fio), [`banc-volumes.sh`](fichiers/M16-E28/k8s/outils/banc-volumes/banc-volumes.sh), [`campagne.sh`](fichiers/M16-E28/k8s/outils/banc-volumes/campagne.sh), [modèle de `performances.md`](fichiers/M16-E28/medisphere/docs/kubernetes/stockage/tests/performances.md).

*1. L'image* : dépôt des images de plateforme du M13 (pipeline sur `runner02`, construction sans démon privilégié, Trivy, Syft, Cosign, poussée dans le projet Harbor `plateforme`). Avant usage :

```
admin@adm01:~$ cosign verify --key ~/src/images-conteneurs/cosign.pub --insecure-ignore-tlog \
    registry.par1.medisphere.internal/plateforme/outils-stockage:1.0.0 >/dev/null && echo signée
admin@adm01:~$ crane digest registry.par1.medisphere.internal/plateforme/outils-stockage:1.0.0   # pour épingler BANC_IMAGE
```

(Options de vérification et emplacement de la clé publique : ceux de ton M13.)

*2. Le banc* : un Job par mesure, PVC dédié de 4 Gio (ou `emptyDir` limité à 3 Gio), pod non root et en lecture seule sauf le volume, `nodeSelector` sur `k8s-w01`, profil passé par ConfigMap, résultat JSON écrit dans le volume puis affiché (les messages de `fio` ne coupent pas le JSON), nettoyage par `trap` (Job, ConfigMap, PVC). Le résumé (`jq`) donne IOPS, débit, latence moyenne et p99 par sens.

*3. Contrôle du banc* : trois répétitions de `oltp` sur `ceph-rbd` ; écart > 15 % = le banc mesure autre chose (autre charge sur Ceph, OSD en récupération, nœud chargé). Sans `--direct=1`, les lectures de `debit` sont servies par le cache de pages du nœud (8 Go de mémoire pour un fichier de 2 Gio) : chiffres « impossibles », qui mesurent la mémoire.

*4. La campagne* :

```
admin@adm01:~/src/k8s$ outils/banc-volumes/campagne.sh ceph-rbd ceph-rbd-chiffre cephfs emptydir
admin@adm01:~$ kubectl top node k8s-w01        # pendant « debit » sur ceph-rbd-chiffre (et ssh k8s-w01 mpstat 5)
```

Ordre de grandeur attendu sur le lab (indicatif, non mesuré en conditions réelles : **mesure les tiens**) : `wal` de quelques centaines d'opérations par seconde sur Ceph (latence de l'ordre de la milliseconde ou plus, aller-retour réseau et triple écriture) contre plusieurs milliers sur `emptyDir` ; `iops` limité par les OSD (tous sur un seul SSD physique) ; `debit` limité par le réseau virtuel et les OSD ; `ceph-rbd-chiffre` proche de `ceph-rbd` en latence, plus coûteux en processeur sur `debit` ; `cephfs` proche de RBD pour les gros blocs, plus lent sur `wal` (métadonnées, capacités du MDS).

*5. Interpréter* : voir le modèle, sections « Interprétation » et « Réserves » ; ce sont les réponses attendues aux cinq questions.

*6. Nettoyer* :

```
admin@adm01:~$ kubectl get job,pod,pvc -n wb-essais -l medisphere.internal/banc=oui          # rien
admin@adm01:~$ kubectl delete pod,pvc e26-temoin -n wb-essais
```

**Explications**

Une mesure de stockage n'a de sens qu'avec son **profil** : « 10 000 IOPS » ne dit rien sans taille de bloc, profondeur de file, ratio lecture/écriture, synchronisation. Le profil `wal` est le plus important pour une base : il mesure la latence d'une écriture **durable**, que rien ne parallélise ; il borne le débit de validations d'une connexion PostgreSQL (`synchronous_commit = on`). Les profils parallèles (`oltp`, `iops`) mesurent ce que le stockage encaisse quand beaucoup de requêtes arrivent en même temps. Les comparaisons relatives (Kubernetes ou pas, chiffré ou pas) sont fiables sur le lab ; les chiffres absolus, non.

**Alternatives**
- `kubectl cnpg fio` : Job `fio` fourni par le plugin CloudNativePG (profils prédéfinis) ; pratique, moins maîtrisé.
- `pgbench` sur la base : la mesure qui parle à Julien (transactions par seconde), mais elle mélange processeur, mémoire et stockage.
- `dbench`, `kubestr` : outils de banc pour Kubernetes ; à éviter s'ils ne sont pas dans Harbor et vérifiés.

**Pièges classiques**
- Mesurer sans `--direct=1` (cache de pages) ou sur un fichier plus petit que la mémoire du nœud.
- Première passe sur un volume neuf (provisionnement fin : allocation des objets RADOS pendant la mesure).
- Pods sur des nœuds différents d'une mesure à l'autre.
- Lancer la campagne pendant une récupération Ceph ou une sauvegarde Velero.
- Publier des chiffres absolus du lab comme engagement de performance.

**En production chez MédiSphère**
Banc rejoué après chaque changement de matériel, de version de Ceph ou de ceph-csi (comparaison avec la référence) ; métriques de latence des OSD et des volumes (M21) ; classe de QoS par volume (`VolumeAttributesClass`) pour isoler les bases des volumes « bruyants ».

---

### M16-E29 — Migrer des données d'une classe de stockage à une autre

**Solution**

Fichiers : [PVC cible](fichiers/M16-E29/migration/01-pvc-cible.yaml), [Job de copie](fichiers/M16-E29/migration/02-job-copie.yaml), [PVC final](fichiers/M16-E29/migration/03-pvc-final.yaml), [extrait du StatefulSet](fichiers/M16-E29/mediagenda/valkey-statefulset.extrait.yaml), [extrait de la sonde de l'API pendant la fenêtre](fichiers/M16-E29/mediagenda/api-sonde-pendant-migration.extrait.yaml), [RB-163](fichiers/M16-E29/medisphere/docs/kubernetes/stockage/runbooks/RB-163-migrer-un-volume.md), [modèle de compte rendu](fichiers/M16-E29/medisphere/docs/kubernetes/stockage/tests/migration-valkey.md).

*1. Ce qui n'est pas une migration* :

```
admin@adm01:~$ kubectl apply -n wb-essais -f - <<'FIN'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: e29-essai}
spec: {accessModes: [ReadWriteOnce], storageClassName: ceph-rbd, resources: {requests: {storage: 1Gi}}}
FIN
admin@adm01:~$ kubectl run e29-lien -n wb-essais --image=registry.par1.medisphere.internal/dockerhub/library/debian:trixie-slim --restart=Never \
    --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":10001},"containers":[{"name":"c","image":"registry.par1.medisphere.internal/dockerhub/library/debian:trixie-slim","command":["true"],"volumeMounts":[{"name":"v","mountPath":"/v"}]}],"volumes":[{"name":"v","persistentVolumeClaim":{"claimName":"e29-essai"}}]}}'
admin@adm01:~$ PV=$(kubectl get pvc e29-essai -n wb-essais -o jsonpath='{.spec.volumeName}')
admin@adm01:~$ kubectl patch pv "$PV" -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
admin@adm01:~$ kubectl delete pod e29-lien -n wb-essais ; kubectl delete pvc e29-essai -n wb-essais
admin@adm01:~$ kubectl get pv "$PV"                                     # Released
[admin@ceph01 ~]$ sudo rbd ls k8s-rbd | grep <IMAGE>                    # toujours là
admin@adm01:~$ kubectl patch pv "$PV" --type json -p '[{"op":"remove","path":"/spec/claimRef"}]'   # Available
```

Puis un PVC `e29-essai` avec `volumeName: $PV` et `storageClassName: ceph-rbd` s'y lie. (Le pod éphémère sert à déclencher la liaison si `ceph-rbd` est en `WaitForFirstConsumer`.) Se règlent ainsi : la politique de récupération (dans les deux sens) ; l'agrandissement (en place, E11). Exigent une migration : la classe elle-même (le champ `storageClassName` d'un PVC lié est immuable), le chiffrement, le pilote, une réduction de taille.

*2. Les voies* :

| Voie | Verdict | Raison |
|---|---|---|
| Instantané + clone vers `ceph-rbd-chiffre` | **écartée** | la documentation de ceph-csi interdit d'activer le chiffrement sur un volume créé sans ; le code copie la configuration de chiffrement **de la source** (en clair : rien à copier) : au mieux un refus, au pire un volume annoncé chiffré qui ne l'est pas — non documenté, non retenu |
| Velero + ConfigMap `change-storage-class` | possible | sauvegarde de l'espace, suppression, restauration : coupure de toute la durée, et de **tout** l'espace (ou d'un sous-ensemble filtré) |
| Copie `rsync` à chaud puis à froid | **retenue** | coupure = arrêt de Valkey + copie finale + redémarrage ; générique (RB-163) |
| Réplica Valkey sur un nouveau volume puis bascule | élégante | suppose une réplication Valkey (réplica + promotion, ou Sentinel) que E08 n'a pas mise en place |

Plan : Retain sur le PV source (retour arrière) → répétition → pré-copie → coupure (arrêt, copie finale, rattachement, StatefulSet recréé, redémarrage) → contrôles → suppression de l'ancien volume (point de non-retour, après validation).

*3. Répétition et préparation* : constat attendu de la répétition : la sonde de disponibilité de l'API est `/pret`, qui répond 503 dès que Valkey ne répond pas ; au bout de `failureThreshold` × `periodSeconds` (10 s avec les valeurs du M14 : `periodSeconds: 5`, `failureThreshold: 2`), **tous** les pods de l'API sortent du Service : l'API tombe alors que son code sait fonctionner sans cache (créneaux calculés depuis la base). La coupure de Valkey prévue (une à deux minutes) dépasse cette fenêtre. Mesure retenue : MR « avant » qui porte `failureThreshold` à 60 pendant la fenêtre (300 s), MR « après » qui le rétablit (chaque MR déclenche un déploiement progressif de l'API, sans coupure) ; ticket **DEV-1729** à l'équipe de Julien : la disponibilité ne devrait pas dépendre d'une dépendance facultative. Une autre réponse est d'écourter la coupure sous 10 s (pré-copie, volume petit, image déjà sur le nœud) : à mesurer, sans marge. Côté création de rendez-vous, l'API efface deux clés de cache par création, avec un délai de 2 s par appel à Valkey : tant que le Service `valkey` sans point de terminaison est **refusé** tout de suite (réponse de Cilium à un Service sans *backend*, `serviceNoBackendResponse: reject` par défaut : à vérifier sur ta version), la création reste rapide ; si les paquets étaient jetés, chaque création attendrait jusqu'à 4 s, au-delà du `--max-time 3` du témoin.

Clés témoins :

```
admin@adm01:~$ kubectl exec -n mediagenda-recette valkey-0 -- sh -c 'for i in $(seq 1 1000); do echo "SET e29:$i valeur-$i"; done | valkey-cli --pipe'
admin@adm01:~$ kubectl exec -n mediagenda-recette valkey-0 -- sh -c 'valkey-cli --scan --pattern "e29:*" | sort | xargs valkey-cli MGET | sha256sum'
admin@adm01:~$ kubectl exec -n mediagenda-recette valkey-0 -- valkey-cli BGSAVE        # ou constate l'AOF configuré en E08
admin@adm01:~$ PVS=$(kubectl get pvc donnees-valkey-0 -n mediagenda-recette -o jsonpath='{.spec.volumeName}')
admin@adm01:~$ kubectl patch pv "$PVS" -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
admin@adm01:~$ kubectl apply -f 01-pvc-cible.yaml
```

(Si Valkey exige un mot de passe (E08), `valkey-cli` le lit dans la variable d'environnement du conteneur : jamais en argument.)

*4. Pré-copie* : `UID`/`GID` lus dans le StatefulSet (`kubectl get sts valkey -n mediagenda-recette -o jsonpath='{.spec.template.spec.securityContext}'`), nœud de `valkey-0` (`kubectl get pod valkey-0 -o jsonpath='{.spec.nodeName}'`) ; `02-job-copie.yaml` avec `<PASSE>=chaud`, puis `kubectl logs job/migration-valkey-copie-chaud` (statistiques de `rsync`).

*5. Bascule* (chronométrée) :

```
admin@adm01:~$ ~/src/k8s/outils/temoin-api.sh &
admin@adm01:~$ date +%T ; kubectl scale sts valkey -n mediagenda-recette --replicas=0 ; kubectl wait --for=delete pod/valkey-0 -n mediagenda-recette --timeout=60s
admin@adm01:~$ sed 's/<PASSE>/froid/' 02-job-copie.yaml | kubectl apply -f - ; kubectl wait --for=condition=complete job/migration-valkey-copie-froid -n mediagenda-recette --timeout=120s
admin@adm01:~$ PVC=$(kubectl get pvc migration-valkey-cible -n mediagenda-recette -o jsonpath='{.spec.volumeName}')
admin@adm01:~$ kubectl patch pv "$PVC" -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
admin@adm01:~$ kubectl delete job migration-valkey-copie-chaud migration-valkey-copie-froid -n mediagenda-recette
admin@adm01:~$ kubectl delete pvc migration-valkey-cible -n mediagenda-recette
admin@adm01:~$ kubectl patch pv "$PVC" --type json -p '[{"op":"remove","path":"/spec/claimRef"}]'
admin@adm01:~$ kubectl delete pvc donnees-valkey-0 -n mediagenda-recette          # PV source en Retain : conservé
admin@adm01:~$ sed "s/<PV-CIBLE>/$PVC/; s/<TAILLE>/1Gi/" 03-pvc-final.yaml | kubectl apply -f -
admin@adm01:~$ kubectl delete sts valkey -n mediagenda-recette --cascade=orphan
admin@adm01:~/src/mediagenda-api$ # MR : storageClassName: ceph-rbd-chiffre dans k8s/recette/30-valkey.yaml, fusion, puis :
admin@adm01:~/src/mediagenda-api$ kubectl apply -f k8s/recette/30-valkey.yaml
admin@adm01:~$ kubectl rollout status sts/valkey -n mediagenda-recette ; date +%T
```

(Le PVC final est appliqué à la main dans l'urgence de la coupure : c'est un objet créé normalement par le StatefulSet, il n'a pas sa place dans le dépôt ; il est décrit dans RB-163.) Les Jobs sont supprimés **avant** le PVC temporaire : un PVC monté par un pod, même terminé, reste protégé contre la suppression (`kubernetes.io/pvc-protection`) tant que le pod existe.

*6. Valider* : somme des clés témoins identique ; `kubectl get pvc donnees-valkey-0 -n mediagenda-recette -o jsonpath='{.spec.storageClassName}'` → `ceph-rbd-chiffre` ; `lsblk` sur le nœud : `crypt` ; `rbd image-meta list` : `encrypted` ; témoin de l'API : aucun échec ; sonde verte. Puis :

```
admin@adm01:~$ kubectl get pv "$PVS"                                                    # Released (son PVC a été supprimé)
admin@adm01:~$ kubectl patch pv "$PVS" -p '{"spec":{"persistentVolumeReclaimPolicy":"Delete"}}'
admin@adm01:~$ kubectl get pv "$PVS"                                                    # disparaît : ceph-csi supprime l'image
[admin@ceph01 ~]$ sudo rbd ls k8s-rbd | grep -c <IMAGE-SOURCE>                          # 0
admin@adm01:~$ kubectl patch pv "$PVC" -p '{"spec":{"persistentVolumeReclaimPolicy":"Delete"}}'
```

Remettre en `Delete` un PV **`Released`** fait réclamer le volume par le provisionneur : c'est la façon propre de supprimer l'ancien volume (image **et** entrées de journal de ceph-csi dans le pool). Supprimer le PV puis l'image à la main (`kubectl delete pv`, puis `rbd rm` après `rbd status`) marche aussi, mais laisse les entrées de journal de ceph-csi (objets `csi.volume.*` et clé dans `csi.volumes.default` du pool, à vérifier) : sans effet sur le fonctionnement, mais du désordre. Enfin, le PVC `e29-essai` de l'étape 1.

*7.* RB-163 et compte rendu (fichiers). Pour `mediagenda-db` : ne pas copier ; l'opérateur sait recréer une instance (`kubectl cnpg destroy mediagenda-db <N>` supprime une instance et son PVC, l'opérateur en recrée une par clonage depuis le primaire, avec la classe de `.spec.storage` si elle a été changée) : réplicas d'abord, puis bascule, puis l'ancien primaire. À valider sur `pg-essai` avant (le webhook accepte-t-il le changement de `storageClass` ? : à vérifier sur ta version).

**Explications**

Kubernetes sépare le **volume** (PV) de la **demande** (PVC) : on ne change pas la classe d'un volume, on fait pointer une demande vers un autre volume. Toute la technique consiste à garder un retour arrière à chaque étape (`Retain` avant chaque suppression), à profiter de la liaison explicite (`volumeName` + suppression du `claimRef`) pour reprendre un nom imposé, et à contourner l'immuabilité du StatefulSet sans toucher à ses pods ni à ses PVC (`--cascade=orphan`). La coupure se réduit à la copie **différentielle** finale : d'où la pré-copie. Et la vraie disponibilité se mesure du côté de l'utilisateur : ici, c'est la sonde de l'API, pas Valkey, qui décidait si l'application tombait.

**Alternatives**
- Velero avec changement de classe (`change-storage-class`) : rien à écrire à la main, coupure plus longue ; utile pour migrer **beaucoup** de volumes d'un coup.
- Réplication applicative (Valkey réplica + promotion, PostgreSQL par l'opérateur) : coupure quasi nulle, propre à chaque application.
- *VolumePopulators* (sources de données personnalisées) : remplir un PVC neuf depuis une source arbitraire ; encore peu outillé.

**Pièges classiques**
- Supprimer le PVC source avec un PV en `Delete`.
- Job de copie sur un autre nœud pendant que Valkey tourne : *Multi-Attach*.
- `rsync -a` non root : erreurs de `chown` ; copie en root : fichiers illisibles par Valkey.
- Oublier de retirer le `claimRef` : le PVC final reste Pending.
- Supprimer le StatefulSet sans `--cascade=orphan`.
- Oublier les sondes de l'API : Valkey migre parfaitement, l'API tombe 90 secondes.
- Oublier l'image RBD du PV supprimé : le quota du pool se remplit de fantômes.

**En production chez MédiSphère**
Migrations planifiées par ticket CHG, fenêtre annoncée, RB-163 en binôme ; inventaire automatique des volumes de données de santé encore en clair (requête sur les PVC par classe) avec une échéance ; correction côté application de la sonde `/pret` (DEV-1729).

---

### M16-E30 — ADR : le stockage de `k8s-par1`

**Solution**

Modèle : [`ADR-0160-stockage-k8s-par1.md`](fichiers/M16-E30/medisphere/docs/kubernetes/stockage/adr/ADR-0160-stockage-k8s-par1.md). Décision : **fournisseur `ceph-par1` (externe), pilote ceph-csi** ; Rook et Longhorn retirés ; Rook externe gardé comme repli quand plusieurs clusters Kubernetes consommeront le même Ceph ; Longhorn comme option pour une agence sans Ceph. Argument décisif : le **domaine de panne** — les données ne vivent pas dans le cluster Kubernetes, qui peut être perdu et reconstruit (M14-E23) sans perdre ses volumes, et dont les montées de version ne touchent pas au stockage.

**Explications**

La distinction fournisseur/pilote évite un faux débat : « Rook ou ceph-csi » n'est pas « Ceph ou autre chose » (Rook externe **utilise** ceph-csi, déployé par son opérateur). Le vrai choix porte sur **où** vivent les données (dans le cluster ou à côté) et **qui** exploite le stockage (une équipe qui connaît déjà Ceph). Les notes doivent toutes renvoyer à un fait du module : c'est ce qui rend l'ADR défendable.

**Alternatives** (également défendables)
- Rook externe dès maintenant (O3) : moins de configuration manuelle des pilotes, mises à jour coordonnées par l'opérateur ; un composant de plus, et une abstraction de plus à dépanner (E36-E38 deviennent plus opaques).
- Volumes locaux + réplication applicative pour les bases (O5) : meilleure latence ; exige des nœuds dédiés et des applications qui répliquent toutes (ce n'est pas le cas des fichiers de MédiDoc).

**Pièges classiques**
- Comparer des produits « dans l'absolu », sans les mesures et les essais du module.
- Oublier le couplage des cycles de vie (un Ceph dans Kubernetes monte de version avec lui, et tombe avec lui).
- Taire la dépendance au VLAN 30 et à un cluster Ceph unique.
- Ne pas dire ce que deviennent Rook et Longhorn.

**En production chez MédiSphère**
Revue de l'ADR au PRA (F5 : réplication RBD vers PAR2, ou second Ceph) et à l'arrivée d'un second cluster Kubernetes (F2) ; indicateurs de capacité et de latence de `k8s-rbd` dans les revues mensuelles.

**Grille d'auto-évaluation**

| Critère | Attendu |
|---|---|
| Gabarit | MADR, statut, date, décideurs, ticket ; deux pages au plus |
| Contexte | charges, exigences (chiffrement, sauvegarde, PRA), limites du lab |
| Critères | au moins 8, pondérés, dont domaine de panne, restauration, chiffrement, couplage des cycles de vie |
| Options | au moins 4, dont Rook externe ; chaque note renvoie à un exercice ou une mesure |
| Décision | fournisseur et pilote distingués ; devenir de Rook et Longhorn écrit |
| Conséquences | négatives écrites, actions rattachées à un module (M21, M25, F4, F5) |

---

### M16-E31 — Questions de production : données dans Kubernetes

1. **Panne du nœud du primaire.** Kubernetes : le nœud passe `NotReady` après `node-monitor-grace-period` (de l'ordre de 40 à 50 s selon la version : à vérifier sur 1.36), les pods sont marqués pour éviction après la tolérance `not-ready`/`unreachable` (300 s par défaut) — mais CloudNativePG n'attend pas : la sonde du primaire ne répond plus, l'opérateur déclenche la bascule dès que l'instance est jugée en échec (`failoverDelay` 0). Il ne peut pas arrêter proprement l'ancien primaire (injoignable) : le **bail** n'est pas libéré, la promotion attend son expiration (`leaseDurationSeconds`) ; puis le réplica le plus avancé est promu sur **son** volume (pas celui de l'ancien primaire, qui reste attaché au nœud perdu : VolumeAttachment intact). Écritures de nouveau acceptées : de l'ordre de la durée du bail plus la promotion (quelques dizaines de secondes) ; les connexions de l'API doivent se refaire. Ceph : l'image RBD de l'ancien primaire garde son verrou exclusif ; si l'ancien nœud revenait « à moitié », le contrôle d'isolement de CloudNativePG (primaire qui ne joint plus l'API → redémarrage) et le bail l'empêchent de reprendre le rôle ; côté Ceph, un nouveau client qui prend le verrou de **cette** image met l'ancien en liste de blocage (`blocklist`) : ses écritures sont refusées.
2. **b)** Le VolumeAttachment de l'ancien nœud existe toujours (le contrôleur d'attachement ne détache pas un volume d'un nœud injoignable : il ne peut pas savoir s'il est encore utilisé) : le nouveau pod reste en `ContainerCreating` avec *Multi-Attach error* (RWO). a) faux : pas de détachement automatique d'un nœud perdu (sauf après 6 minutes de « force detach » quand le pod est supprimé et que le nœud reste injoignable — comportement à vérifier sur ta version) ; c) faux : pas de lecture seule automatique ; d) faux : on peut débloquer. La marque `node.kubernetes.io/out-of-service` (posée par un humain qui **sait** que le nœud est arrêté) fait supprimer de force les pods et détacher leurs volumes : la reprise devient immédiate ; la poser sur un nœud encore vivant risque deux écrivains (ce que le verrou exclusif RBD limite, sans le rendre acceptable).
3. Velero copie des **fichiers** (ou un instantané) d'un volume de base à un instant ; même cohérent en cas de panne, il ne donne ni le rejeu des WAL (pas de restauration à un instant donné), ni la garantie que l'archive des WAL est alignée ; et l'opérateur ne sait pas reprendre des volumes sans son état. CloudNativePG seul sauvegarde **la base** : il manque tout le reste de l'application (Deployments, Services, ConfigMaps, routes, Valkey, politiques), et les Secrets ne sont pas sauvegardés. Les deux se complètent (E24, E32).
4. Un instantané CSI n'est **pas** une sauvegarde : il vit dans le même cluster Ceph (perdre Ceph, c'est perdre l'instantané). Il est cohérent « en cas de panne » seulement (comme une coupure de courant). CloudNativePG, en sauvegarde par instantanés, encadre la prise de vue (`pg_backup_start`/`pg_backup_stop` en ligne, ou arrêt de l'instance en mode « à froid ») et garde l'archive des WAL : la restauration rejoue les WAL depuis l'instantané, ce qui le rend exploitable et permet la restauration à un instant donné.
5. **b)** Supprimer l'espace supprime ses PVC ; avec `reclaimPolicy: Delete`, les PV et les images RBD suivent, et les VolumeSnapshots de l'espace aussi (avec `deletionPolicy: Delete` de leur classe, les instantanés RBD disparaissent). a) faux : un instantané ne retient pas un PV ; c) faux : `Delete` supprime l'image ; d) faux : c'est le comportement de `Retain`. Restauration : Velero (objets + volumes du *data mover*) au RPO de la dernière sauvegarde (24 h), base par CloudNativePG (RPO de quelques minutes). La classe `ceph-rbd-retain` existe pour les volumes qu'on ne veut pas voir disparaître avec leur PVC.
6. Le pool passe en `POOL_FULL` : un PVC en création réussit souvent (image fine, rien n'est écrit) mais son formatage peut échouer ; un pod qui écrit voit ses écritures **bloquer** (le client RBD attend, pas d'erreur immédiate), donc des processus figés en état D ; PostgreSQL bloque ses validations (le journal ne s'écrit plus) puis ses connexions s'accumulent ; Valkey bloque ses écritures sur disque (persistance) et, selon sa configuration, refuse les écritures. Signal : occupation du pool (`ms-verif-ceph`, seuil 80 %) et quotas par classe dans les espaces (E20) : alerte à 80 %, action avant 90 %.
7. Parce que le RPO s'allonge à chaque minute (les transactions validées ne sont plus hors du cluster) **et** parce que le primaire conserve tous les WAL non archivés dans `pg_wal` : son volume se remplit, et à 100 % PostgreSQL s'arrête — panne de la base causée par sa sauvegarde. D'où la sonde (E27) et l'alerte immédiate.
8. **b)** Perdues : en asynchrone, une transaction est validée dès qu'elle est écrite sur le primaire ; ce que les réplicas n'ont pas reçu disparaît avec lui. a) faux : non archivées (l'archivage suit l'écriture, avec retard) ; c) faux : l'ancien primaire est rembobiné (`pg_rewind`), ses WAL divergents sont **jetés** ; d) faux : la bascule privilégie la disponibilité. Avec `synchronous` `any 1` et `dataDurability: required` sur 3 instances dont une en maintenance : il en reste une pour acquitter, tout va bien ; si celle-ci tombe aussi, **plus aucune écriture** n'est validée tant qu'un réplica ne revient pas — la durabilité est payée en disponibilité (avec `preferred`, la base continue en asynchrone).
9. Administrateur de Kubernetes : **non** (il lit la KEK dans le Secret de la classe et peut lancer un pod qui monte le volume). Administrateur de Ceph : **oui** (blocs chiffrés ; DEK enveloppée ; KEK hors de Ceph). Sauvegarde Velero volée : **non** par le chiffrement des volumes, car le *data mover* lit le système de fichiers **monté** (déchiffré) et copie des fichiers en clair dans le dépôt Kopia — ce qui la protège, c'est le chiffrement du dépôt Kopia et les droits sur le compartiment. DEK : dans les métadonnées de l'image originale ; pour un clone, ré-enveloppée dans les métadonnées du clone ; dans Velero, aucune (données en clair dans le dépôt, chiffré par sa propre clé).
10. Le client FUSE est un **processus** du *nodeplugin* : le redémarrer (mise à jour) tue le processus qui sert le montage ; les pods voient « Transport endpoint is not connected » jusqu'à leur redémarrage. Le client noyau est dans le noyau du nœud : le *nodeplugin* n'est pas dans le chemin des E/S. La documentation recommande de ne pas utiliser FUSE et, si on y est contraint, de passer le DaemonSet en `OnDelete` pour redémarrer les *nodeplugins* nœud par nœud en drainant d'abord.
11. **b)** Un PV restauré qui porte une affinité de nœud (volume local, `hostPath`, ou topologie de zone) ne peut être monté que sur les nœuds qui la satisfont ; si ces nœuds n'existent pas dans la cible (autre cluster, autre zone), conflit. a) faux : le PVC ne serait pas `Bound` ; c) faux : le PVC serait refusé à la création ; d) faux : le *data mover* échouerait, la restauration ne serait pas `Completed`. `ceph-rbd` : volumes réseau sans affinité de nœud (pas de `allowedTopologies` dans nos classes, E12), restaurés par reprovisionnement : montables partout.
12. `pg_upgrade` crée un **nouveau** système (nouvel identifiant de système, timeline 1) : les WAL d'avant appartiennent à un autre système et ne peuvent pas être rejoués sur le nouveau ; une sauvegarde d'avant ne restaure que l'ancienne majeure. Juste après : nouveau `serverName` (déjà changé avec l'image), sauvegarde de base immédiate, vérification que l'archivage reprend, et suppression planifiée des anciennes archives à l'échéance de leur rétention.
13. `kubelet_volume_stats_used_bytes` vient d'un `statfs` du système de fichiers monté : ce que **le système de fichiers** considère comme occupé. `ceph df` compte les objets RADOS **réellement écrits** dans l'image. Les deux divergent dans les deux sens : un fichier préalloué (`fallocate`, fréquent pour des journaux ou des fichiers de base) ou des réservations du système de fichiers occupent des blocs sans qu'aucune donnée n'ait été écrite (9,5 Gio vus, 3 Gio stockés : c'est le cas de la question) ; à l'inverse, des fichiers supprimés **sans** `discard` laissent dans Ceph des objets que le système de fichiers croit libres (Ceph > système de fichiers). Ce qui déclenche « disque plein » pour l'application : le chiffre du **système de fichiers** (9,5 Gio sur 10, la sonde E27 alerte) ; celui de Ceph compte pour le quota du pool et la capacité du cluster.
14. Suppression de lignes : CloudNativePG (PITR dans un cluster temporaire, récupération sélective, E34) : RPO ≈ 0 (on remonte juste avant l'erreur), RTO 30-60 min. Perte du cluster Kubernetes : reconstruction (M14-E23) ou restauration etcd (RB-141), les **volumes sont intacts** dans Ceph : la base repart sur ses volumes si le cluster est restauré, sinon CloudNativePG depuis `s3-01` (RPO de quelques minutes) ; RTO de quelques heures. Perte de `ceph-par1` : volumes perdus ; base depuis `s3-01` (RPO de quelques minutes), autres volumes depuis Velero (RPO 24 h), sur un stockage reconstruit : RTO d'une journée. PBS (VMs des nœuds) ne sert qu'à reconstruire des nœuds.
15. CephFS : PostgreSQL n'a pas besoin de RWX (une seule instance écrit son répertoire) ; CephFS ajoute la latence des métadonnées et des capacités du MDS sur chaque `fsync`, et les verrous de fichiers en réseau sont un risque ; un « volume partagé pour faciliter les bascules » est l'inverse de l'architecture de CloudNativePG (chaque instance a **son** volume, la réplication se fait par PostgreSQL). `emptyDir` : les données disparaissent avec le pod ; un drain de nœud, une mise à jour, une éviction pour pression mémoire suffisent à perdre une instance, et une opération sur plusieurs nœuds (mise à jour du cluster) peut toutes les perdre : il faudrait des recopies complètes en permanence, et aucune protection contre un incident commun.
16. Les comptes rendus datés des tests de restauration (E24, E19, E34 : instant restauré, empreintes, RTO, signataire), le planning et l'historique de ces tests, les journaux de la sonde (sauvegardes réussies chaque nuit, archivage continu), la politique de sauvegarde validée (E32), et une restauration **en présence** de l'auditeur sur demande. Signataires : le propriétaire de la politique (Claire), Sophie pour la sécurité ; l'équipe applicative valide les contrôles de données.

---

### M16-E32 — Politique de sauvegarde des données Kubernetes

**Solution**

Modèle : [`politique-sauvegarde.md`](fichiers/M16-E32/medisphere/docs/kubernetes/stockage/politique-sauvegarde.md). Points structurants : un inventaire **par donnée** (pas par outil), avec la source de vérité de chacune (les Secrets viennent de Vault, pas de Velero) ; deux règles de restauration (la base par CloudNativePG, jamais par Velero ; les Secrets par recréation) ; les dépendances de restauration et le cas « perte de `s3-01` » écrits honnêtement (toutes les sauvegardes du cluster au même endroit en v1) ; des tests de restauration réguliers avec un critère d'échec ; l'effacement RGPD dans les sauvegardes (délai réel = rétention).

**Explications**

Quatre mécanismes qui se recouvrent finissent par laisser des trous si on raisonne par outil : chacun croit que l'autre couvre. En partant des **données** et des **incidents**, on voit ce que chaque copie protège réellement, et surtout ce qui tombe en même temps qu'elle. Un RTO n'existe que s'il a été mesuré : la politique cite les essais du module et dit ce qui n'a pas été mesuré.

**Alternatives**
- Une politique commune à tout le parc (VMs, Ceph, Kubernetes) avec une annexe par plateforme : plus lisible pour l'auditeur, plus longue à maintenir.
- Engagements par classe de données (santé, technique, éphémère) plutôt que par donnée : utile quand les applications se multiplient (module 28).

**Pièges classiques**
- RTO recopiés de la documentation (ou souhaités) au lieu d'être mesurés.
- Croire que Velero sauvegarde « tout, base comprise ».
- Oublier que les sauvegardes du cluster sont toutes sur `s3-01`.
- Oublier l'effacement RGPD dans les copies.
- Tests de restauration sans critère d'échec ni trace.

**En production chez MédiSphère**
Copies des compartiments de `s3-01` vers PAR2 (F5), verrouillage d'objets pour une copie immuable, tableau de bord des sauvegardes (M21), tests de restauration au calendrier de l'astreinte, revue annuelle avec le DPO.

**Grille d'auto-évaluation**

| Relecteur | Critère | Attendu |
|---|---|---|
| Claire | Inventaire | etcd, objets, volumes, bases, Secrets, configuration ; une ligne par donnée avec propriétaire |
| Claire | Engagements | RPO/RTO reliés à un mécanisme et à un test réel, ou « non mesuré » + action datée |
| Nadia | Restauration | dépendances et ordre ; runbooks cités (RB-141, RB-161, RB-162) ; tests réguliers avec critère d'échec |
| Nadia | Alertes | ce que surveille la sonde, seuils, qui est réveillé |
| Sophie | Sécurité | chiffrement de chaque copie, sensibilité du compartiment Velero (il contient des Secrets), effacement RGPD et délai réel |
| Tous | Limites | perte de `s3-01`, un seul site, absence de copie immuable : écrites |

---

### M16-E33 — Mettre à jour ceph-csi et CloudNativePG sans interruption

**Solution**

Fichiers : [témoins de volumes](fichiers/M16-E33/wb-essais/temoins-volumes.yaml), [`outils/temoins-stockage.sh`](fichiers/M16-E33/k8s/outils/temoins-stockage.sh), [extrait de valeurs de l'opérateur](fichiers/M16-E33/k8s/composants/cloudnative-pg/values.extrait.yaml), [RB-164](fichiers/M16-E33/medisphere/docs/kubernetes/stockage/runbooks/RB-164-mettre-a-jour-le-stockage.md), [modèle de compte rendu](fichiers/M16-E33/medisphere/docs/kubernetes/stockage/tests/mise-a-jour-stockage.md) ; témoin de l'API : `outils/temoin-api.sh` (E25).

*1. Lecture et matrice* (exemple pour des correctives) :

| Composant | De → vers | Compatibilité | Ce qui redémarre | Effet attendu | Retour arrière |
|---|---|---|---|---|---|
| ceph-csi CephFS | 3.18.1 → 3.18.x | Kubernetes 1.34-1.36, Ceph Tentacle | contrôleurs (un par un), *nodeplugins* (un nœud à la fois, `RollingUpdate`) | écritures continues (client noyau) ; provisionnement CephFS interrompu brièvement | `helm rollback` |
| ceph-csi RBD | 3.18.1 → 3.18.x | idem | idem | écritures continues (`rbdN`) ; montages sur un nœud impossibles pendant le redémarrage de son *nodeplugin* | `helm rollback` |
| Opérateur CNPG | 1.30.1 → 1.30.x | Kubernetes 1.34-1.36 | CRD, opérateur ; instances : en place (option) ou redémarrage + bascule | 0 erreur en place ; sinon une bascule planifiée | corriger en avant |
| Plugin Barman Cloud | 0.15.1 → 0.15.x | cert-manager 1.21, CNPG 1.30 | plugin ; *sidecar* des instances si son image change | archivage repris | `helm rollback` |

La procédure de ceph-csi (`docs/ceph-csi-upgrade.md` au tag) met à jour CephFS avant RBD, et rappelle le cas FUSE ; le contrôleur de snapshots est de la responsabilité de la distribution (hors de cette mise à jour).

*2. Prérequis et témoins* :

```
admin@adm01:~$ velero backup create e33-avant --include-namespaces mediagenda-recette --snapshot-move-data --wait
admin@adm01:~$ kubectl cnpg backup mediagenda-db -n mediagenda-recette --method=plugin --plugin-name=barman-cloud.cloudnative-pg.io
admin@adm01:~$ /usr/local/bin/ms-verif-k8s-stockage --quiet && /usr/local/bin/ms-verif-ceph --quiet
admin@adm01:~$ kubectl apply -f temoins-volumes.yaml
admin@adm01:~$ ~/src/k8s/outils/temoin-api.sh & ~/src/k8s/outils/temoins-stockage.sh provisionnement &
```

*3. ceph-csi* : MR qui change la version épinglée du chart CephFS, `task appliquer` (qui lance `helm upgrade --version <X> -f composants/ceph-csi-cephfs/values.yaml`), puis la même chose pour RBD.

```
admin@adm01:~$ kubectl rollout status -n ceph-csi daemonset/ceph-csi-rbd-nodeplugin
admin@adm01:~$ kubectl get pods -n ceph-csi -o wide -w
admin@adm01:~$ ~/src/k8s/outils/temoins-stockage.sh trous
```

(Noms des objets : ceux de tes releases.) Constat attendu : aucun trou dans les écritures des témoins RBD et CephFS (client noyau : le *nodeplugin* n'est pas dans le chemin des E/S) ; un PVC du témoin de provisionnement peut mettre quelques secondes de plus à se lier pendant le remplacement des contrôleurs (élection de leader du *sidecar* `csi-provisioner`).

*4. CloudNativePG* : décision du corrigé : **mise à jour en place** du gestionnaire d'instance pour les correctives (`ENABLE_INSTANCE_MANAGER_INPLACE_UPDATES: "true"`, extrait de valeurs), appliquée **avant** la mise à jour (la configuration de l'opérateur doit être lue par la nouvelle version). Puis MR de version du chart `cloudnative-pg`, `task appliquer`. Les CRD (dans les gabarits du chart) sont mises à jour, l'opérateur redémarre, puis chaque instance remplace son binaire sans redémarrer PostgreSQL : le témoin de l'API ne voit rien. Sans cette option : redémarrage progressif, et une bascule à la fin (en `supervised` pour la recette : promotion manuelle, E25).

```
admin@adm01:~$ kubectl get deploy -n cnpg-system -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.template.spec.containers[0].image}{"\n"}{end}'
admin@adm01:~$ kubectl cnpg status mediagenda-db -n mediagenda-recette | grep -iE 'version|primary'
```

*5. Plugin* : MR, `task appliquer`. Si l'image du *sidecar* change, les instances redémarrent pour l'adopter (une à une, bascule à la fin) : c'est ce que dit le témoin. Puis : `ContinuousArchiving` `True`, nouvelle sauvegarde à la demande `completed`.

*6. Contrôles* : RB-164, section « Contrôles finaux ». Retour arrière documenté, non exécuté.

*7. Écrire* : RB-164 et le compte rendu (fichiers). En **répétition générale** (aucune corrective plus récente disponible), le compte rendu le dit, et les redémarrages contrôlés (`kubectl rollout restart` des DaemonSets et Deployments de `ceph-csi`, de l'opérateur et du plugin ; `kubectl cnpg restart mediagenda-db`) produisent les mêmes effets observables, sauf la mise à jour des CRD et le remplacement en place du binaire.

**Explications**

Une mise à jour « sans interruption » n'existe que si on sait **ce que redémarre** chaque composant et **où il se trouve dans le chemin des données**. Les pilotes CSI ne sont dans le chemin qu'au montage (client noyau) : leur redémarrage interrompt la gestion des volumes, pas leur usage. L'opérateur CloudNativePG, lui, a un morceau de lui-même dans chaque pod de base (le gestionnaire d'instance, PID 1) : le mettre à jour, c'est toucher à chaque base — d'où l'option de remplacement en place. Les témoins rendent tout cela mesurable, et transforment « ça s'est bien passé » en chiffres.

**Alternatives**
- Mises à jour correctives automatiques (Renovate, M13) dans un pipeline qui lance les témoins et les vérifications : la cible ; il faut d'abord la procédure manuelle maîtrisée.
- Laisser le redémarrage progressif des instances (sans mise à jour en place) : plus « immuable » (la définition des pods dit la vérité), au prix d'une bascule par cluster.
- `ceph-csi-operator` (utilisé par Rook) pour gérer les pilotes : mises à jour par un objet, mais une couche de plus.

**Pièges classiques**
- Mettre à jour plusieurs composants à la fois.
- Changer de mineure par erreur (`3.19`, `1.31`) en laissant une borne de version trop large.
- Oublier que la mise à jour de l'opérateur touche tous les `Cluster` en même temps.
- `helm rollback` de l'opérateur sans lire ce qu'il fait des CRD.
- Déclarer le succès sans regarder les témoins.

**En production chez MédiSphère**
Correctives appliquées dans la semaine (sécurité) par RB-164, d'abord sur un environnement d'essai, puis en recette, puis en production ; témoins permanents (sonde E27, témoins applicatifs) ; mises à jour mineures traitées comme un changement (CHG) avec répétition sur `pg-essai`.

---

### M16-E34 — Restaurer la base de MédiAgenda en temps limité

**Solution** (déroulé de référence ; à ne lire qu'après ta tentative chronométrée)

Fichiers : [`Cluster` d'enquête](fichiers/M16-E34/mediagenda-recette/mediagenda-db-enquete.yaml), [`outils/recuperer-lignes.sh`](fichiers/M16-E34/k8s/outils/recuperer-lignes.sh) (modèle pour RB-162). Injection : [`break-E34.sh`](pannes/break-E34.sh).

| Jalon | Actions | Temps de référence |
|---|---|---|
| T0 → T1 | Lire l'heure de l'erreur ; vérifier que les WAL de l'instant voulu sont archivés (`kubectl cnpg status` : dernier WAL archivé postérieur à l'heure de l'erreur — sinon attendre l'`archive_timeout` ou forcer un changement de segment sur le primaire : `SELECT pg_switch_wal()`) ; écrire le `Cluster` d'enquête : une instance, `recoveryTarget.targetTime` = l'heure affichée **avec son décalage**, pas de `.spec.plugins` ; appliquer | 10 min |
| T1 → T2 | Attendre la récupération (`kubectl cnpg status mediagenda-db-enquete`) ; contrôler dans le cluster d'enquête que les rendez-vous de `dr-garnier` sont là et qu'aucun rendez-vous postérieur à l'erreur n'y figure ; simulation puis réinjection sélective (`recuperer-lignes.sh --praticien dr-garnier`, puis `--appliquer`) ; noter le conflit signalé | 20 min |
| T2 → T3 | Contrôler par l'API (identifiants rendus, rendez-vous postérieurs présents) ; supprimer le cluster d'enquête (ses PVC partent avec) et le fichier d'extraction (`shred`, déjà fait par le script) ; compte rendu (identifiants seulement), MR de RB-162 ; `lab/bin/check 16 34` | 10 min |

Total de référence : 40 minutes avec un RB-162 préparé et le script de récupération sélective ; sans script, compter plus d'une heure, avec les erreurs typiques ci-dessous.

```
admin@adm01:~$ sed 's/<AAAA-MM-JJ HH:MM:SS+HH:MM>/<HEURE-AFFICHÉE>/' mediagenda-db-enquete.yaml | kubectl apply -f -
admin@adm01:~$ kubectl cnpg status mediagenda-db-enquete -n mediagenda-recette
admin@adm01:~$ kubectl cnpg psql mediagenda-db-enquete -n mediagenda-recette -- -d mediagenda -At \
    -c "SELECT count(*), max(cree_le) FROM rendez_vous WHERE praticien = 'dr-garnier'"
admin@adm01:~$ ~/src/k8s/outils/recuperer-lignes.sh --praticien dr-garnier             # simulation : REINSERE 7 … CONFLIT <ID> …
admin@adm01:~$ ~/src/k8s/outils/recuperer-lignes.sh --praticien dr-garnier --appliquer
admin@adm01:~$ curl -s https://mediagenda-recette.apps.par1.medisphere.internal/api/v1/rendez-vous/<ID> | jq .praticien
admin@adm01:~$ kubectl delete cluster mediagenda-db-enquete -n mediagenda-recette
```

(`mediagenda` : la base de E18 ; adapte si tu en as choisi une autre. Sans `database`/`owner` dans `bootstrap.recovery`, l'opérateur ajoute une base `app` vide : les données sont quand même dans `mediagenda`.) Le conflit : un rendez-vous supprimé à 10 h a vu son créneau repris après l'incident ; l'index unique `(praticien, debut)` interdirait de toute façon de le réinsérer ; le script le **signale** au lieu d'échouer, et son identifiant va dans le compte rendu.

**Explications**

Restaurer une base « à un instant donné » ne veut presque jamais dire remettre la production à cet instant : on perdrait tout ce qui a été écrit depuis. La bonne réponse est une **récupération sélective** : un cluster temporaire remonté juste avant l'erreur, et la réinjection des seules données manquantes, avec leurs identifiants (les patients les connaissent) et une règle explicite pour les conflits. Le temps se gagne en amont : runbook à jour, manifeste prêt à remplir, script de réinjection testé, et la vérification de l'archive avant de lancer la récupération (sans le WAL de l'instant voulu, la récupération échoue ou s'arrête trop tôt).

**Alternatives**
- PITR **en place** (supprimer `mediagenda-db` et le recréer à l'instant voulu) : interdit par le dossier ; perd toutes les écritures postérieures ; c'est la réponse à un sinistre logique global (corruption de toute la base), pas à une suppression ciblée.
- Extraire les lignes par `pg_dump --data-only --table` du cluster d'enquête : possible, mais l'import ne gère ni les conflits ni « seulement ce qui manque ».
- Journal applicatif des suppressions (table d'audit, suppression logique) : rendrait l'opération triviale ; demande d'évolution à l'équipe de Julien (DEV).

**Pièges classiques**
- Heure sans fuseau (`targetTime` interprété en UTC : une ou deux heures d'écart).
- Récupérer **après** la validation de la transaction fautive (heure arrondie à la minute supérieure).
- Cluster d'enquête avec `.spec.plugins` : il archive dans `cnpg-k8s-par1` (ou est bloqué par l'archive non vide).
- Réinsérer sans `OVERRIDING SYSTEM VALUE` : nouveaux identifiants.
- Écraser le rendez-vous pris après l'incident.
- Noms de patients dans le compte rendu ou dans le ticket.
- Oublier le fichier d'extraction sur `adm01`.

**En production chez MédiSphère**
Script de récupération sélective par application, maintenu par l'équipe et testé chaque mois (RB-162) ; suppressions logiques et journal d'audit dans l'application ; exercice chronométré semestriel pour chaque membre de l'astreinte.
