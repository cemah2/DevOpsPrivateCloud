# Module 16 — Palier 3 : Production

Les volumes arrivent à la demande, PostgreSQL tourne sous CloudNativePG avec ses WAL archivés sur `s3-01`, Velero sauvegarde les espaces de noms : le stockage de `k8s-par1` **fonctionne**. Il n'est pas encore **exploitable**. Personne n'a restauré un espace de noms entier ailleurs que là où il vivait ; personne n'a provoqué de bascule de la base sous charge ; les volumes RBD sont en clair sur `ceph-par1` ; aucune sonde ne dit qu'un PVC reste Pending ou que l'archivage des WAL s'est arrêté ; on ignore ce que vaut un volume en IOPS et en latence ; et la première mise à jour de ceph-csi ou de l'opérateur se fera « en croisant les doigts ». Ce palier fait passer les données de Kubernetes en production : restaurer, basculer, chiffrer, surveiller, mesurer, migrer, mettre à jour, et l'écrire.

> ⚠️ **Rappel** : `mediagenda-recette` est l'environnement de recette de l'équipe de Julien. Toute manipulation de `mediagenda-db` (bascule, redémarrage, mise à jour) se prévient sur le canal de l'équipe, se fait hors des créneaux de démonstration, et commence par une **sauvegarde de base vérifiée** (`kubectl get backups.postgresql.cnpg.io -n mediagenda-recette` : la plus récente est `completed`) et par la condition `ContinuousArchiving` à `True`. Le pool `k8s-rbd` de `ceph-par1` a un **quota** (M08 : 20 Gio au départ, peut-être relevé en M16-E20) : avant chaque exercice qui crée des volumes (E24, E25, E28, E29), vérifie la marge (`ceph osd pool get-quota k8s-rbd` et `ceph df` sur `ceph01`) et supprime ce que tu crées dès que la mesure est faite. Les commandes qui suppriment un PVC, un PV ou un `Cluster` se relisent deux fois : avec `reclaimPolicy: Delete`, l'image RBD disparaît avec eux.

**Chemin imposé** (introduction du module) : tout objet durable du cluster est décrit dans `plateforme/k8s` (MR relue, pipeline, application par `task appliquer`) ; les composants installés par Helm le sont avec des fichiers de valeurs versionnés dans `plateforme/k8s/composants/<nom>/` et des versions épinglées ; les secrets (clés cephx, phrase de chiffrement, identifiants S3) viennent d'Ansible Vault (`critique`) par les scripts de `plateforme/k8s/outils/`, jamais du dépôt, et sont inscrits au **registre des secrets** ; la documentation va dans `docs/kubernetes/stockage/` de `plateforme/medisphere` (`adr/`, `runbooks/`, `tests/`). Une commande `kubectl` à la main sert à **constater** ou à **déclencher** une opération ponctuelle (bascule, restauration), jamais à créer un état durable.

**Espaces de noms de ce palier** : `mediagenda-recette` (MédiAgenda, `mediagenda-db`, Valkey), `wb-essais` (essais, mesures, clusters PostgreSQL jetables), `wb-restauration` (créé en E24), `velero`, `cnpg-system`, `ceph-csi`, `kube-system` (contrôleur de snapshots). Aucune nouvelle VM.

**Ordre conseillé** : E27 → E24 → E25 → E26 → E28 → E29 → E33 → E30 → E32 → E31 → E34. La sonde (E27) veille pendant tout le reste ; la classe chiffrée (E26) est la cible de la migration (E29) et l'un des objets mesurés (E28) ; l'outillage de E28 sert en E29 ; E33 réutilise les témoins de E25 ; E34 se passe en dernier, en conditions d'examen. **Durée totale indicative** : 32 à 38 h.

Les vérifications se lancent **depuis `adm01`** (`lab/bin/check 16 XX`).

---

### M16-E24 — Restaurer un espace de noms complet ailleurs  `LAB` `★★★`

> **Ticket PLAT-1724** — *De : Nadia Roussel*
> Velero tourne depuis E16 et les sauvegardes sont vertes. Très bien. Mais « vert » ne veut pas dire « restaurable » : je veux qu'on prouve qu'on sait remonter **tout** l'environnement de recette de MédiAgenda — l'API, Valkey, la base, les secrets, les politiques réseau — dans un autre espace de noms, sans toucher à l'original, et qu'on sache dire combien de temps ça prend.
> Et je veux que la procédure tienne dans un runbook qu'un collègue d'astreinte pourra suivre à 3 h du matin.

**Objectifs pédagogiques**
- Comprendre ce que fait une restauration Velero, objet par objet : ordre, renommage des PV, liaison des PVC, remappage d'espace de noms, politique sur les objets existants, modificateurs de ressources.
- Distinguer ce qu'un outil de sauvegarde **générique** sait restaurer et ce qui doit l'être par l'outil **propre** à la donnée (PostgreSQL par CloudNativePG).
- Repérer tout ce qui, dans un espace de noms, désigne son propre nom (et casse ou fuit après un remappage).
- Mesurer un RTO réel et contrôler les données restaurées, pas seulement les objets.

**Prérequis** : M16-E16 et E17 (Velero, BSL `s3-01`, node-agent Kopia, déplacement des données de snapshots CSI), M16-E18 et E19 (`mediagenda-db`, `ObjectStore` `cnpg-s3`, sauvegarde continue, PITR), M16-E08 (Valkey en StatefulSet), M15-E17 (politiques réseau de MédiAgenda), M14-E18 (PSA).
**Durée indicative** : 4 h.

**Contexte technique**
- Source : l'espace `mediagenda-recette` tel que les paliers 1 et 2 l'ont laissé : Deployment de l'API, StatefulSet Valkey et son PVC (`ceph-rbd`), `Cluster` `mediagenda-db` (3 instances, archivage des WAL et sauvegardes de base par le plugin Barman Cloud vers l'`ObjectStore` `cnpg-s3`), `ScheduledBackup`, Secrets, ConfigMaps, NetworkPolicies et CiliumNetworkPolicies, HTTPRoute `mediagenda` publiée en `mediagenda-recette.apps.par1.medisphere.internal`, ResourceQuota.
- Cible : l'espace **`wb-restauration`**, déclaré dans `plateforme/k8s/espaces/` comme les autres (PSA `restricted` en `enforce`, quota de stockage), **sans** le label d'exposition `medisphere.fr/exposition: oui` : une copie de données de santé n'est pas publiée.
- Velero 1.18 (espace `velero`, CLI `velero` sur `adm01`), BSL `s3-01` (compartiment `velero-k8s-par1`). La sauvegarde de référence de l'exercice est une sauvegarde **à la demande** de `mediagenda-recette` avec déplacement des données de snapshots CSI (`--snapshot-move-data`, E17).
- La restauration est décrite par un **manifeste `Restore`** versionné (`plateforme/k8s/composants/velero/restaurations/`), pas par une ligne de commande tapée à 3 h du matin ; ses modificateurs de ressources sont dans une ConfigMap de l'espace `velero`, versionnée au même endroit.
- Contraintes posées par Nadia et Sophie :
  1. l'original n'est **jamais** modifié (ni objets, ni données, ni archives S3 de `mediagenda-db`) ;
  2. la copie n'est **ni publiée** (aucun nom DNS, aucune route acceptée par `gw-par1`), **ni active** : aucune tâche planifiée restaurée ne s'exécute, aucune sauvegarde ni archivage de WAL ne part de la copie ;
  3. la copie ne parle **qu'à elle-même** : l'API restaurée utilise la base restaurée et le Valkey restauré, jamais ceux de la recette ;
  4. la base est restaurée par CloudNativePG (récupération depuis `cnpg-s3`) dans un `Cluster` à **une** instance, pour ménager le quota de `k8s-rbd`.
- Documents : runbook **RB-161** (`docs/kubernetes/stockage/runbooks/RB-161-restaurer-un-espace-de-noms.md`) et compte rendu d'essai `docs/kubernetes/stockage/tests/restauration-espace-de-noms.md` (étapes chronométrées, RTO mesuré, contrôles de données, écarts).

> ⚠️ **Attention** : (1) une restauration Velero **sans** remappage recrée les objets dans `mediagenda-recette` : relis le manifeste `Restore` (champ `namespaceMapping`) avant de l'appliquer, et applique-le d'abord avec un sélecteur qui ne retient rien si tu n'es pas sûr ; (2) un `Cluster` CloudNativePG restauré qui archiverait ses WAL avec le même `serverName` que la recette écrirait dans **ses** archives : la copie ne doit avoir **aucun** plugin d'archivage ; (3) une HTTPRoute restaurée telle quelle porte le nom d'hôte de la recette ; (4) `wb-restauration` contient une copie de données de santé : supprime-le dès la vérification faite (étape 8).

**Travail demandé**
1. **Lecture.** Dans la documentation de Velero 1.18 (*Restore Reference*, *Restore Resource Modifiers*, *CSI Snapshot Data Movement*), relève : l'ordre de restauration des ressources ; ce que Velero fait d'un PV et d'un PVC quand l'espace de noms est remappé ; ce qui se passe quand un objet existe déjà (`existingResourcePolicy`) ; ce que peut et ne peut pas faire un modificateur de ressources ; comment filtrer ce qui est restauré (ressources, labels). Dans la documentation de CloudNativePG 1.30 (*Recovery*) et du plugin Barman Cloud (*Usage*), relève : comment un `Cluster` démarre depuis un `ObjectStore`, ce que devient l'utilisateur applicatif, et la sécurité qui empêche un cluster d'écrire dans une archive non vide. Réponds dans ton journal : pourquoi ne pas laisser Velero restaurer les PVC et les pods de `mediagenda-db` ?
2. **Inventaire.** Liste tout ce que contient `mediagenda-recette` (`kubectl api-resources --namespaced -o name` et une boucle `kubectl get`), puis classe chaque objet : restauré tel quel, restauré **modifié** (comment), **exclu** (pourquoi), **reconstruit** par un autre outil. Cherche en particulier tout ce qui désigne l'espace de noms par son nom : noms DNS de Services dans des Secrets ou des ConfigMaps, sélecteurs d'espace de noms des politiques réseau, sujets des RoleBindings, noms d'hôtes des routes. Pour chacun, dis ce qui se passerait dans la copie.
3. **Préparer la cible et la restauration** (par MR sur `plateforme/k8s`) : l'espace `wb-restauration` ; la ConfigMap de modificateurs (au minimum : nom d'hôte des HTTPRoute remplacé par `mediagenda-restauration.apps.par1.medisphere.internal`, CronJobs suspendus) ; le manifeste `Restore` (sauvegarde source, remappage `mediagenda-recette` → `wb-restauration`, filtrage des objets que CloudNativePG reconstruira, référence aux modificateurs) ; le manifeste du `Cluster` de récupération (une instance, `bootstrap.recovery` depuis l'`ObjectStore` restauré, `serverName` de la recette, **pas** de `.spec.plugins`).
4. **Sauvegarde de référence.** Suspends les écritures de test sur la recette pendant l'exercice. Note l'état de référence : nombre de rendez-vous et empreinte de la table `rendez_vous` (somme de contrôle de toutes les lignes triées par `id`), nombre de clés de Valkey. Lance la sauvegarde :
   ```
   admin@adm01:~$ velero backup create e24-recette --include-namespaces mediagenda-recette --snapshot-move-data --wait
   admin@adm01:~$ velero backup describe e24-recette --details
   ```
   Lis le détail : quels volumes ont été déplacés par le *data mover*, lesquels ignorés, combien d'objets.
5. **Restaurer.** Applique le manifeste `Restore` et suis-le (`velero restore describe <NOM> --details`, `velero restore logs <NOM>`, objets `datadownloads.velero.io` de l'espace `velero`). Quand il est `Completed`, applique le `Cluster` de récupération et suis-le (`kubectl cnpg status mediagenda-db -n wb-restauration`). Chronomètre chaque étape, de la décision de restaurer jusqu'à l'API restaurée prête.
6. **Contrôler.** Vérifie, preuves à l'appui : les pods de `wb-restauration` sont prêts (la sonde `/pret` de l'API exige PostgreSQL **et** Valkey) ; l'API restaurée répond par un `kubectl port-forward` et liste les rendez-vous ; nombre de rendez-vous, empreinte de la table et nombre de clés Valkey identiques à l'état de référence ; l'API restaurée parle à la base **restaurée** (lis la chaîne de connexion qu'elle reçoit et les connexions vues côté PostgreSQL) ; la HTTPRoute de la copie n'est pas acceptée par `gw-par1` et aucun enregistrement DNS n'a été créé ; aucune sauvegarde ni aucun WAL n'est parti de la copie (le préfixe de `mediagenda-db` dans `cnpg-k8s-par1` n'a reçu que les WAL de la recette) ; la recette est intacte.
7. **Écrire.** Le compte rendu (étapes, durées, RTO mesuré, écarts et leurs causes) et le runbook RB-161 : quand l'utiliser, prérequis, décisions à prendre (où restaurer, quelle sauvegarde, à quel instant pour la base), étapes, contrôles, retour arrière, nettoyage.
8. **Nettoyer** après `lab/bin/check 16 24` : supprime la copie (`Cluster`, puis l'espace de noms) et vérifie que les images RBD de la copie ont disparu de `k8s-rbd`. Garde le manifeste et la sauvegarde `e24-recette` (elle expire selon sa durée de vie).

**Critères de réussite**
- [ ] `wb-restauration` existe, décrit dans `plateforme/k8s`, en PSA `restricted`, sans label d'exposition.
- [ ] Une restauration Velero `Completed` remappe `mediagenda-recette` vers `wb-restauration` et référence une ConfigMap de modificateurs ; aucune HTTPRoute de la copie ne porte le nom de la recette ; aucun CronJob de la copie n'est actif.
- [ ] Dans `wb-restauration`, `mediagenda-db` est sain, démarré par `bootstrap.recovery`, sans plugin d'archivage ; Valkey a son PVC lié et ses données ; tous les Deployments et StatefulSets sont disponibles.
- [ ] Les contrôles de données sont identiques à l'état de référence et consignés, avec le RTO mesuré, dans `docs/kubernetes/stockage/tests/restauration-espace-de-noms.md` ; RB-161 est sur `main` de `plateforme/medisphere`.
- [ ] La recette est intacte : `mediagenda-db` de `mediagenda-recette` sain, archivage continu actif, API disponible.

**Vérification** : `lab/bin/check 16 24` (avant le nettoyage de l'étape 8).

<details><summary>Indice 1</summary>

Un sélecteur de labels de `Restore` accepte des expressions (`matchExpressions`), y compris l'**absence** d'un label. Regarde quels labels CloudNativePG pose sur tout ce qu'il crée pour un `Cluster` (pods, PVC, Secrets, Services, PDB) : c'est la poignée qui permet de laisser de côté, d'un coup, tout ce que l'opérateur saura recréer lui-même.
</details>

<details><summary>Indice 2</summary>

Lis le contenu (décodé, sans l'afficher sur un écran partagé) du Secret que l'API utilise pour joindre la base : quel nom d'hôte y figure, et ce nom contient-il l'espace de noms ? Selon que ce Secret est restauré par Velero ou recréé par l'opérateur dans la copie, l'API restaurée ne visera pas la même base. Les politiques réseau restaurées, elles, te protègent peut-être d'une mauvaise surprise : vérifie-le plutôt que de compter dessus.
</details>

<details><summary>Indice 3</summary>

L'`ObjectStore` est un objet **de l'espace de noms** : restauré dans `wb-restauration`, il pointe toujours vers le même compartiment et le même préfixe. C'est exactement ce qu'il faut pour **lire** les archives de la recette (`externalClusters` + `serverName`), et exactement ce qu'il ne faut pas pour **écrire** (`.spec.plugins` avec `isWALArchiver`). La sécurité « archive non vide » de CloudNativePG est un filet, pas un plan.
</details>

**Pour aller plus loin** (facultatif) : restaurer dans **un autre cluster** (même BSL en lecture seule, `accessMode: ReadOnly`) ; la politique `--existing-resource-policy=update` et ses limites sur les PVC ; les crochets de restauration (`restore hooks`) ; [Restore Reference](https://velero.io/docs/v1.18/restore-reference/), [Resource Modifiers](https://velero.io/docs/v1.18/restore-resource-modifiers/), [CNPG Recovery](https://cloudnative-pg.io/documentation/1.30/recovery/).

---

### M16-E25 — PostgreSQL : bascule, maintenance et montée de version  `LAB` `★★★`

> **Ticket PLAT-1725** — *De : Julien Petit* — *Copie : Karim Benali*
> On me dit que la base « bascule toute seule ». Je veux le voir, et savoir ce que mes utilisateurs perçoivent : combien de secondes d'erreurs, est-ce qu'on perd des rendez-vous, est-ce que l'API se reconnecte seule. Et on aura des mises à jour mineures tous les trimestres et une majeure par an : je veux qu'on sache les faire.
> *Karim* : et je veux qu'on sache **isoler** une instance malade sans la détruire, pour garder de quoi enquêter.

**Objectifs pédagogiques**
- Distinguer bascule planifiée (*switchover*) et bascule sur panne (*failover*), et mesurer leur effet côté application.
- Comprendre l'élection du primaire (bail Kubernetes de CloudNativePG 1.30), le retour de l'ancien primaire (`pg_rewind`), l'isolement (*fencing*).
- Conduire une mise à jour à redémarrage (*rolling update*) en mode `supervised`, une mise à jour mineure par l'image, et comparer les deux voies de montée majeure : import logique et `pg_upgrade` en place.

**Prérequis** : M16-E18 et E19, M16-E27 conseillé (la sonde doit voir la bascule), M14-E16 (PDB).
**Durée indicative** : 4 h.

**Contexte technique**
- `mediagenda-db` (espace `mediagenda-recette`, 3 instances, PostgreSQL 18, `ceph-rbd`). Plugin `kubectl cnpg` sur `adm01`. Les manifestes du `Cluster` sont là où E18 les a mis (dépôt de code et MR) : un réglage durable se change par le code, une bascule se **déclenche** par la commande.
- Témoin côté application : une boucle sur `adm01` qui crée un rendez-vous de test chaque seconde par l'API publiée et journalise chaque échec avec l'heure (créneaux en 2030 pour ne pas gêner l'équipe ; ces rendez-vous de test sont supprimés en fin d'exercice) :
  ```
  admin@adm01:~$ API=https://mediagenda-recette.apps.par1.medisphere.internal
  admin@adm01:~$ i=0; while sleep 1; do i=$((i+1)); d=$(date -d "2030-01-01 +$i hours" +%Y-%m-%dT%H:00:00+01:00)
        c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 -H 'Content-Type: application/json' \
            -d "{\"patient\":\"Témoin E25\",\"praticien\":\"wb-temoin\",\"debut\":\"$d\"}" "$API/api/v1/rendez-vous")
        [ "$c" = 201 ] || echo "$(date +%T) échec $c"; done | tee ~/e25-temoin.log
  ```
- Cluster d'essai **`pg-essai`** dans `wb-essais` : 2 instances, 1 Gio chacune sur `ceph-rbd`, image `registry.par1.medisphere.internal/ghcr/cloudnative-pg/postgresql:17.10-minimal-trixie` au départ (cache Harbor `ghcr`, comme pour `mediagenda-db`), accès super-utilisateur activé (il servira de source à un import). Données d'essai : `kubectl cnpg pgbench pg-essai -n wb-essais -- --initialize --scale 5` (voir `--help` ; environ 75 Mio). Cluster cible de l'import : **`pg-essai-import`** (PostgreSQL 18.6, même famille d'image `minimal-trixie`, 1 instance).
- Compte rendu : `docs/kubernetes/stockage/tests/bascules-postgresql.md` (une ligne par opération : heure, durée d'indisponibilité vue par le témoin, erreurs, rendez-vous perdus, observations).

> ⚠️ **Attention** : (1) prévenir l'équipe de Julien avant chaque opération sur `mediagenda-db` ; une sauvegarde de base récente et `ContinuousArchiving` à `True` sont exigés avant de commencer ; (2) **jamais** deux opérations en même temps (bascule pendant une mise à jour, *fencing* du primaire) : attends `Cluster in healthy state` entre deux ; (3) isoler le **primaire** n'entraîne **pas** de bascule : la recette s'arrête jusqu'à la levée ; (4) la montée majeure ne se pratique que sur `pg-essai`, jamais sur `mediagenda-db` ; (5) si des politiques réseau s'appliquent dans `wb-essais` (M15-E06), les clusters d'essai ont besoin des mêmes autorisations que `mediagenda-db` (opérateur, réplication, plugin, S3 s'ils archivent).

**Travail demandé**
1. **Lecture.** Dans la documentation de CloudNativePG 1.30 (*Automated failover*, *Rolling updates*, *Fencing*, *PostgreSQL upgrades*, *Replication*, et le *Status* du plugin), relève : les étapes d'une bascule sur panne et le rôle de `.spec.failoverDelay`, `.spec.switchoverDelay` et du bail (*primary lease*) ; ce que deviennent l'ancien primaire et sa timeline ; la différence entre `primaryUpdateStrategy` `unsupervised` et `supervised`, et entre `primaryUpdateMethod` `restart` et `switchover` ; ce que fait l'opérateur quand on change la majeure dans `imageName` ; ce que coûte la réplication synchrone (`.spec.postgresql.synchronous`) en disponibilité.
2. **État initial.** Relève le primaire, la timeline, le retard des réplicas, les PDB et le bail (`kubectl cnpg status`, `kubectl get pdb,lease -n mediagenda-recette`), et les nœuds qui portent chaque instance.
3. **Bascule planifiée.** Témoin lancé, promeus un réplica (`kubectl cnpg promote`). Mesure l'indisponibilité, vérifie qu'aucun rendez-vous acquitté (201) n'est perdu, observe le déplacement du Service `-rw` et la nouvelle timeline.
4. **Bascule sur panne.** Témoin lancé, supprime brutalement le pod primaire (`--grace-period=0 --force`, avertissement compris). Mesure, puis suis le retour de l'ancien primaire comme réplica : trouve dans ses journaux la trace de `pg_rewind`, et dis pourquoi il est nécessaire ici et pas après la bascule planifiée.
5. **Isolement.** Isole un **réplica** (`kubectl cnpg fencing on`), observe l'état du pod, du Service `-ro`, de la sonde E27 et de la métrique `cnpg_collector_fencing_on`, puis lève l'isolement. Réponds : à quoi sert l'isolement d'une instance qui redémarre en boucle ?
6. **Maintenance supervisée.** Par MR, passe `mediagenda-db` en `primaryUpdateStrategy: supervised`, puis change un paramètre PostgreSQL qui exige un redémarrage (par exemple `max_connections`). Observe : les réplicas redémarrent, le primaire attend. Termine par une bascule manuelle vers le réplica le plus à jour, puis décide (et écris) si la recette reste en `supervised`.
7. **Mise à jour mineure** sur `pg-essai` : 17.10 → 17.11 par l'image. Observe l'ordre des redémarrages et la durée d'indisponibilité.
8. **Montée majeure 17 → 18**, deux voies, sur des données identiques : (a) **import** : crée `pg-essai-import` en PostgreSQL 18.6 par `bootstrap.initdb.import` (type `microservice`) depuis `pg-essai`, et compare les nombres de lignes ; (b) **en place** : change `imageName` de `pg-essai` vers `18.6-minimal-trixie`, suis le Job de montée, les réplicas recréés, puis lance `ANALYZE`. Compare indisponibilité, durée, espace consommé, retour arrière possible et effet sur l'archive des WAL.
9. **Écrire** le compte rendu, puis supprime les rendez-vous de test (`praticien = wb-temoin`) par l'API.

**Critères de réussite**
- [ ] `mediagenda-db` est sain, 3 instances prêtes, sans instance isolée ; sa timeline montre au moins deux promotions.
- [ ] Le compte rendu donne, pour la bascule planifiée et la bascule sur panne, l'indisponibilité mesurée par le témoin et le nombre de rendez-vous acquittés perdus (attendu : 0), et cite la trace de `pg_rewind`.
- [ ] `pg-essai` tourne en PostgreSQL 18 après une montée en place, `pg-essai-import` en PostgreSQL 18 par import ; tous deux sains, mêmes nombres de lignes.
- [ ] La décision `supervised`/`unsupervised` pour la recette est écrite et appliquée par le code.
- [ ] Les rendez-vous de test ont été supprimés.

**Vérification** : `lab/bin/check 16 25`

<details><summary>Indice 1</summary>

Le témoin mesure ce que voit l'utilisateur : la durée entre le premier et le dernier échec n'est pas la durée de la promotion. Pense à ce qui s'ajoute : la mise à jour des points de terminaison du Service, le pool de connexions de l'API (psycopg) qui garde des connexions vers l'ancien primaire, et la sonde `/pret` qui retire ou non le pod de l'API.
</details>

<details><summary>Indice 2</summary>

Après une bascule planifiée, l'ancien primaire s'est arrêté **proprement** avant la promotion : il n'a rien écrit que le nouveau n'ait reçu. Après une suppression brutale, c'est moins sûr : relis ce que dit la documentation de l'arrêt « immédiat » et des WAL non archivés, et regarde à quel moment de sa timeline l'ancien primaire a divergé.
</details>

<details><summary>Indice 3</summary>

Pour l'import, la source doit être joignable avec un compte qui a le droit de tout lire : l'opérateur crée un Secret de super-utilisateur quand l'accès super-utilisateur est activé. Pour la voie en place, lis attentivement la condition sur la **famille** d'image (système d'exploitation de base) : ce n'est pas un détail.
</details>

**Pour aller plus loin** (facultatif) : la montée majeure **en ligne** par réplication logique (`Publication`/`Subscription` déclaratives) ; `INSTANCES_ROLLOUT_DELAY` ; la réplication synchrone `dataDurability: preferred` contre `required` ; [Automated failover](https://cloudnative-pg.io/documentation/1.30/failover/), [PostgreSQL upgrades](https://cloudnative-pg.io/documentation/1.30/postgres_upgrades/), [Fencing](https://cloudnative-pg.io/documentation/1.30/fencing/).

---

### M16-E26 — Chiffrer les volumes  `LAB` `★★★`

> **Ticket SEC-1726** — *De : Sophie Laurent*
> Les volumes de nos bases et de nos caches sont aujourd'hui en clair dans `k8s-rbd`. N'importe qui capable de lire une image RBD — un administrateur Ceph, une clé cephx trop large, une sauvegarde de disque d'OSD mal rangée — lit des données de santé. Le chiffrement des OSD (M08-E27) ne protège que du vol du support.
> Je veux une classe de stockage chiffrée **par le client**, avec une clé par volume, et je veux savoir exactement qui détient quelle clé. Et confirme-moi que le transit vers Ceph est chiffré pour tous les volumes, RBD comme CephFS.

**Objectifs pédagogiques**
- Comprendre le chiffrement des volumes RBD par ceph-csi (LUKS sur le nœud), la séparation clé de chiffrement des données (DEK) / clé de chiffrement des clés (KEK), et les fournisseurs de clés (KMS) disponibles.
- Construire un modèle de menace : qui peut lire quoi, avec quelle clé, à chaque couche.
- Créer une classe chiffrée sans toucher aux volumes existants, et le prouver sur le nœud **et** dans Ceph.
- Vérifier le chiffrement en transit (msgr2 `secure`) des clients noyau.

**Prérequis** : M16-E06 et E07 (ceph-csi, classes, Secrets créés par script), M08-E27 (chiffrement des OSD, msgr2 `secure`), M14-E28 (chiffrement des Secrets dans etcd).
**Durée indicative** : 3 h 30.

**Contexte technique**
- ceph-csi 3.18 : paramètres de StorageClass `encrypted`, `encryptionType` (`block` par défaut, LUKS), `encryptionKMSID` ; configuration des fournisseurs de clés dans la ConfigMap de KMS du pilote RBD (valeur `encryptionKMSConfig` du chart, `kmsConfigMapName` pour son nom) ; fournisseurs : phrase unique dans le Secret de la classe, `metadata` (une DEK par volume, chiffrée par une KEK, rangée dans les métadonnées de l'image), HashiCorp Vault (module 25), et d'autres.
- Décision de Sophie pour la v1 (Vault n'arrive qu'au module 25) : **une DEK par volume**, enveloppée par une **KEK propre à la classe chiffrée**, distincte de tout autre secret ; KEK générée sur `adm01`, rangée en Ansible Vault `critique`, poussée dans le cluster par un script de `plateforme/k8s/outils/` (comme les clés cephx de E06), inscrite au registre des secrets. Bascule vers Vault au module 25.
- Nouvelle classe **`ceph-rbd-chiffre`** : mêmes paramètres que `ceph-rbd` (pool, fonctionnalités, `ext4`, agrandissement), `reclaimPolicy: Delete`, **pas** classe par défaut. Identifiant de KMS : **`secrets-metadata`**. Secret de la classe : **`csi-rbd-secret-chiffre`** (espace `ceph-csi`).
- Volume témoin : PVC `e26-temoin` (1 Gio, `ceph-rbd-chiffre`) et pod `e26-temoin` dans `wb-essais`, conservés jusqu'à E28 (qui mesure le coût du chiffrement). Volume de contrôle `e26-clair` (1 Gio, `ceph-rbd`), supprimé en fin d'exercice.
- Documentation : `docs/kubernetes/stockage/chiffrement.md` (modèle de menace, mécanismes, détenteurs des clés, limites, plan de bascule vers Vault).

> ⚠️ **Attention** : (1) ne modifie **jamais** les paramètres de chiffrement d'une classe qui a déjà des volumes (documentation de ceph-csi) : c'est une **nouvelle** classe ; (2) la mise à jour des valeurs du chart RBD redémarre les pods du pilote, un nœud à la fois : les volumes déjà montés par le client noyau restent montés, mais aucune création ni aucun montage ne se fait pendant quelques secondes — fais-le hors démonstration ; (3) **perdre la KEK, c'est perdre tous les volumes de la classe** : la copie en Vault `critique` (et sa copie hors ligne) est vérifiée **avant** de créer le premier volume ; (4) `rbd export` d'une image en cours d'utilisation est une lecture : sans risque pour le volume, mais elle charge le cluster — limite-toi au volume témoin de 1 Gio.

**Travail demandé**
1. **Lecture.** Dans la documentation de ceph-csi 3.18.1 (`docs/rbd/deploy.md`, section *Encryption for RBD volumes*, et l'exemple de configuration des KMS), relève : le cycle de vie d'un volume chiffré (création, premier montage, montages suivants, suppression), où vit la DEK selon le fournisseur, d'où vient la KEK du fournisseur `metadata`, ce qui est refusé (chiffrer une classe qui a déjà des volumes), les paramètres de chiffrement possibles (algorithme, taille de clé, intégrité) et leur effet sur l'agrandissement.
2. **Modèle de menace.** Tableau : acteurs (administrateur de `pve01`, administrateur Ceph avec `client.admin`, détenteur de `client.k8s`, administrateur Kubernetes qui lit les Secrets, compte de service du pilote sur un nœud, attaquant sur le VLAN 30, quelqu'un qui récupère une sauvegarde Velero ou une archive PBS d'un OSD) × ce qu'ils lisent **sans** et **avec** la classe chiffrée. Lis aussi les droits du compte de service du *nodeplugin* RBD (son ClusterRole) : que peut-il lire, et qu'en conclus-tu sur la séparation des secrets ?
3. **La KEK.** Génère-la (au moins 32 octets aléatoires), range-la en Vault `critique`, vérifie la relecture, inscris-la au registre des secrets. Étends le script de Secrets de E06 pour créer `csi-rbd-secret-chiffre` (identité de `client.k8s` **et** phrase `encryptionPassphrase`), sans que la valeur passe par un argument de commande ni par le disque.
4. **Le pilote et la classe.** Par MR sur `plateforme/k8s` : déclare le fournisseur `secrets-metadata` (type `metadata`) dans les valeurs du chart RBD et applique ; crée `ceph-rbd-chiffre`. Vérifie que la ConfigMap de KMS montée par les pods du pilote contient bien l'identifiant, et que `ceph-rbd` n'a pas changé.
5. **La preuve.** Crée `e26-temoin` (chiffré) et `e26-clair` (en clair), chacun monté par un pod qui écrit une chaîne témoin reconnaissable dans un fichier. Puis :
   - sur le nœud qui monte `e26-temoin` : `lsblk`, `cryptsetup status` et `cryptsetup luksDump` sur le bon périphérique (où est la phrase ? que montre l'en-tête ?) ;
   - sur `ceph01` : `rbd image-meta list` des deux images (que contiennent les métadonnées de l'image chiffrée ?), puis `rbd export <image> - | grep -c <CHAÎNE>` sur chacune ;
   - un instantané de `e26-temoin` (`ceph-rbd-snap`) et un clone restauré depuis cet instantané : le clone est-il chiffré, et avec quelle DEK ?
6. **Le transit.** Vérifie pour **chaque** classe (`ceph-rbd`, `ceph-rbd-retain`, `ceph-rbd-chiffre`, `cephfs`) que les clients noyau des nœuds se connectent en msgr2 `secure` : options de la classe, connexions des nœuds vers les moniteurs (`ss`), messages du noyau. Ce qui n'est pas protégé est écrit.
7. **Écrire** `chiffrement.md` : modèle de menace, mécanismes par couche (transit, repos côté Ceph, repos côté client, etcd), **détenteurs** de chaque clé, procédure de perte ou de compromission de la KEK, limites (rotation de la KEK, volumes existants en clair, CephFS), plan Vault (M25). Supprime `e26-clair`, l'instantané et le clone.

**Critères de réussite**
- [ ] `ceph-rbd-chiffre` existe (chiffrement activé, KMS `secrets-metadata` de type `metadata`, Secret distinct de celui de `ceph-rbd`) ; `ceph-rbd` est toujours la classe par défaut, inchangée.
- [ ] Le fournisseur `secrets-metadata` figure dans la ConfigMap de KMS du pilote RBD.
- [ ] Le volume `e26-temoin` est lié ; sur son nœud, son périphérique RBD porte un mappage `crypt` ; dans Ceph, son image porte l'état « chiffré » et une DEK enveloppée.
- [ ] La chaîne témoin se lit dans l'export de `e26-clair`, jamais dans celui de `e26-temoin` (résultats consignés) ; `e26-clair` a ensuite été supprimé.
- [ ] Toutes les classes Ceph montent en msgr2 `secure` ; `chiffrement.md` est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 16 26`

<details><summary>Indice 1</summary>

Le fournisseur `metadata` sans nom de Secret explicite prend sa KEK dans les Secrets **de la classe** (ceux du *provisioner* et du *node-stage*), sous une clé précise. D'où l'intérêt d'un Secret dédié à la classe chiffrée : la KEK ne voyage pas avec les autres classes, et une rotation de la clé cephx n'a pas à toucher à la KEK.
</details>

<details><summary>Indice 2</summary>

Sur le nœud, le volume chiffré apparaît deux fois : le périphérique `rbdN` (ce qui part vers Ceph) et, au-dessus, un périphérique du *device-mapper* (ce que le conteneur voit). Pour l'export, choisis une chaîne qu'aucun hasard ne produira, et assure-toi qu'elle a bien atteint le disque (`sync`) avant d'exporter.
</details>

<details><summary>Indice 3</summary>

Pour le transit, la configuration centrale de Ceph (M08-E27) impose `secure` aux démons, mais un client **noyau** choisit son mode à la connexion, par une option de montage ou de mappage. Cherche où les classes de E06-E07 la passent (`mapOptions`, `kernelMountOptions`) et confirme ce qui se passe réellement par les connexions établies et le journal du noyau.
</details>

**Pour aller plus loin** (facultatif) : le chiffrement de fichiers `fscrypt` (`encryptionType: file`) et ce que ceph-csi propose pour CephFS ; la rotation des clés par les *CSI-Addons* ; l'intégrité `integrityMode` (et pourquoi elle interdit l'agrandissement) ; [ceph-csi RBD](https://github.com/ceph/ceph-csi/blob/v3.18.1/docs/rbd/deploy.md), [KMS](https://github.com/ceph/ceph-csi/blob/v3.18.1/examples/kms/vault/kms-config.yaml).

---

### M16-E27 — Superviser le stockage du cluster  `LAB` `★★`

> **Ticket PLAT-1727** — *De : Nadia Roussel*
> J'ai appris par hasard qu'un PVC de `mediagenda-dev` était Pending depuis deux jours, et qu'une sauvegarde Velero avait échoué la semaine dernière. Pour Ceph j'ai `ms-verif-ceph` ; pour le stockage de Kubernetes, rien.
> Même principe : une sonde qui tourne seule, qui alerte, qui dit en une ligne ce qui ne va pas — volumes, pilotes, snapshots, sauvegardes, bases. Et sans donner à la sonde plus de droits qu'il n'en faut : je ne veux pas d'un `cluster-admin` qui tourne toutes les dix minutes.

**Objectifs pédagogiques**
- Inventorier les signaux du stockage de Kubernetes : état des objets (PVC, PV, VolumeAttachment, VolumeSnapshot), pilotes CSI, métriques du kubelet, état de Velero et de CloudNativePG.
- Lire les métriques du kubelet et de CloudNativePG sans Prometheus (qui arrive au module 21), avec des droits minimaux, et comprendre pourquoi certains droits (`nodes/proxy`) sont dangereux.
- Écrire une sonde testée, planifiée et branchée sur l'alerte, dans la lignée des `ms-verif-*`.

**Prérequis** : M08-E24 (`ms-verif-ceph`, modèle), M06-E29 (`ms-alerte@`), M14-E06 (comptes de service et kubeconfig), M14-E26 (certificats de service du kubelet), M15-E17 (politiques réseau de MédiAgenda), M16-E16 à E19.
**Durée indicative** : 4 h.

**Contexte technique**
- Sonde **`ms-verif-k8s-stockage`** dans `plateforme/outils` : script `bin/ms-verif-k8s-stockage`, configuration `etc/ms-verif-k8s-stockage.conf` (installée sous `/usr/local/etc`), tests `tests/bats/ms-verif-k8s-stockage.bats`, unités `ms-verif-k8s-stockage.service` (utilisateur `admin`, `OnFailure=ms-alerte@%n.service`) et `.timer` (toutes les **10 minutes**, `Persistent=true`). Codes retour : 0 tout va bien, 1 anomalie **ou contrôle impossible**, 2 usage.
- Identité de la sonde : compte de service **`ms-supervision-stockage`** (espace `wb-system`), ClusterRole du même nom (lecture seule, liste fermée de ressources), kubeconfig `~/.config/workbook/k8s-supervision-stockage.kubeconfig` (600) produit par un script de `plateforme/k8s/outils/` (jeton lié de durée limitée, renouvelé par une minuterie : pas le jeton longue durée de `wb-checks`, exception documentée en M14-E06).
- Métriques du kubelet : `https://<nœud>:10250/metrics` (`kubelet_volume_stats_*` par PVC monté en mode système de fichiers), interrogées **directement** sur chaque nœud depuis `adm01` (le VLAN MGMT joint le VLAN 40), avec le jeton de la sonde et la CA du cluster.
- Métriques de CloudNativePG : port **9187** (`/metrics`) de chaque instance, lues par le proxy de l'API (`kubectl get --raw /api/v1/namespaces/<ns>/pods/<pod>:9187/proxy/metrics`), ce qui exige une autorisation réseau dans les espaces en refus par défaut.
- Seuils de départ (dans la configuration, pas dans le script) : PVC Pending depuis plus de 15 min ; volume rempli à plus de 80 % (octets ou inodes) ; VolumeSnapshot non prêt depuis plus de 30 min ; dernière sauvegarde réussie de chaque planification Velero de plus de 26 h ; BSL non `Available` ; dernière sauvegarde de base de chaque `Cluster` de plus de 26 h ; archivage continu en échec ; retard de réplication de plus de 60 s.

> ⚠️ **Attention** : (1) ne donne **pas** `nodes/proxy` à la sonde, même en lecture : ce droit ouvre tout le kubelet (y compris l'exécution de commandes dans les pods par certaines voies) ; (2) l'autorisation réseau vers le port 9187 ne doit ouvrir **que** ce port, **que** depuis l'API, **que** vers les instances PostgreSQL ; (3) le test d'alerte (étape 6) crée un PVC volontairement Pending dans `wb-essais` : supprime-le ensuite.

**Travail demandé**
1. **Inventaire des signaux.** Pour chaque panne que tu connais du palier 2 (PVC Pending, pilote arrêté sur un nœud, volume plein, snapshot bloqué, sauvegarde Velero en échec, archivage des WAL bloqué, réplica en retard), dis quel objet ou quelle métrique la révèle, et en combien de temps. Écris le tableau en tête de la section « Stockage Kubernetes » de `docs/astreinte.md` (`plateforme/outils`).
2. **L'identité.** Par MR sur `plateforme/k8s` (`rbac/`) : le compte de service, son ClusterRole (lecture des seules ressources nécessaires, **sans** Secrets ni `nodes/proxy` ; lecture des métriques du kubelet par la sous-ressource prévue pour cela), les liaisons, et le droit de lire **uniquement** le proxy des pods des espaces qui portent une base. Le script qui produit le kubeconfig. Vérifie par `kubectl auth can-i --as=system:serviceaccount:wb-system:ms-supervision-stockage` ce qui est permis et ce qui est refusé (au moins cinq essais négatifs).
3. **Métriques du kubelet.** Depuis `adm01`, avec le jeton de la sonde, lis les métriques d'un travailleur et retrouve, pour le PVC de Valkey, `kubelet_volume_stats_used_bytes`, `…_capacity_bytes` et les inodes. Pourquoi un PVC en mode `Block` n'y figure-t-il pas ? Pourquoi un PVC non monté non plus ?
4. **Métriques de CloudNativePG.** Ajoute (par MR, dans le dépôt qui porte les politiques de MédiAgenda) l'autorisation réseau vers le port 9187 depuis l'API, puis lis par le proxy les métriques d'une instance : état, retard de réplication, état de l'archivage (`cnpg_pg_stat_archiver_*` ou équivalent sur ta version), fencing.
5. **La sonde.** Écris `ms-verif-k8s-stockage` (bibliothèque `ms-commun.sh`, configuration séparée, kubeconfig de la sonde, aucune valeur en dur) et ses tests `bats` (sans cluster : `kubectl` et `curl` simulés, au moins un test rouge par contrôle). Contrôles minimaux : PVC Pending trop longtemps ; PV `Failed` ou `Released` d'une classe en `Delete` ; VolumeAttachment en erreur ; pods des pilotes ceph-csi (contrôleurs et *nodeplugins* : un par travailleur) et contrôleur de snapshots prêts ; volumes au-delà du seuil ; VolumeSnapshots non prêts ; BSL de Velero et âge de la dernière sauvegarde réussie de chaque planification ; pour chaque `Cluster` : phase saine, nombre d'instances prêtes, archivage continu, âge de la dernière sauvegarde de base, retard de réplication.
6. **Planification et preuve.** Installe (`task install:systeme`), active le timer, puis prouve la chaîne d'alerte : crée dans `wb-essais` un PVC d'une classe inexistante, attends le dépassement du seuil (abaisse-le temporairement par un *drop-in* si tu ne veux pas attendre), constate l'alerte de `ms-alerte`, supprime le PVC, constate le retour au vert. Note le délai et ce qui le détermine.
7. **Astreinte.** Complète `docs/astreinte.md` : lire le message, les trois premières commandes par famille de contrôle, quand réveiller quelqu'un (archivage des WAL bloqué : oui ; snapshot de recette lent : non).

**Critères de réussite**
- [ ] Le compte `ms-supervision-stockage` existe ; son ClusterRole ne donne ni Secrets, ni `nodes/proxy`, ni aucun verbe d'écriture ; il permet de lire les métriques du kubelet.
- [ ] `ms-verif-k8s-stockage` est installé sous `/usr/local/bin`, sa configuration sous `/usr/local/etc` ; il rend 0 sur le cluster sain ; une option inconnue donne 2.
- [ ] Le timer passe toutes les 10 minutes ; une alerte a été reçue pendant le test ; le PVC de test n'existe plus.
- [ ] Les tests `bats` sont sur `main` de `plateforme/outils` et passent dans le pipeline ; `docs/astreinte.md` contient la section « Stockage Kubernetes ».

**Vérification** : `lab/bin/check 16 27`

<details><summary>Indice 1</summary>

Le kubelet autorise ses points d'accès par le *webhook* d'autorisation de l'API : chaque chemin correspond à une sous-ressource de `nodes` (`metrics`, `stats`, `log`, `proxy`…). Lis la page *Kubelet authentication/authorization* de la documentation de Kubernetes : la sous-ressource qui suffit pour `/metrics` n'est pas `proxy`.
</details>

<details><summary>Indice 2</summary>

Une requête par le proxy de l'API vers un pod part d'un nœud de contrôle (le processus `kube-apiserver`), pas d'un pod. Une NetworkPolicy standard ne sait pas désigner cette source proprement ; Cilium, si (identités réservées, *entities*).
</details>

<details><summary>Indice 3</summary>

« Dernière sauvegarde réussie de plus de 26 h » suppose de savoir quelles planifications existent : lis les objets `schedules.velero.io` puis, pour chacune, les `backups.velero.io` qui portent son label. Une planification sans aucune sauvegarde réussie est une anomalie, pas un cas à ignorer. Même raisonnement pour les `ScheduledBackup` de CloudNativePG.
</details>

**Pour aller plus loin** (facultatif) : les métriques des pilotes ceph-csi (`httpMetrics`, port des *nodeplugins*) ; les événements Kubernetes comme source d'alerte ; préparer le moissonnage par Prometheus (M21 : `PodMonitor` de CloudNativePG, règles reprenant tes seuils) ; [Kubelet authorization](https://kubernetes.io/docs/reference/access-authn-authz/kubelet-authn-authz/), [CNPG Monitoring](https://cloudnative-pg.io/documentation/1.30/monitoring/).

---

### M16-E28 — Mesurer les performances des volumes  `LAB` `★★★`

> **Ticket PLAT-1728** — *De : Karim Benali* — *Copie : Claire Morel*
> Julien demande « des volumes rapides » pour la base, Sophie veut tout chiffrer, et Claire doit signer l'ADR du stockage. Personne n'a de chiffres. Je veux une campagne de mesures **reproductible** : mêmes profils, même nœud, chaque type de volume du cluster, et une interprétation honnête — qu'est-ce qui coûte quoi, et qu'est-ce que le lab ne permet pas de conclure.

**Objectifs pédagogiques**
- Mesurer un volume avec `fio` depuis un pod, avec des profils qui représentent des charges réelles (base de données, cache, fichiers).
- Isoler les variables (nœud, taille, cache de pages, profondeur de file, `fsync`) et répéter les mesures.
- Comparer les couches : client noyau nu (M08-E28), volume Kubernetes, chiffrement LUKS, CephFS, disque local du nœud.
- Interpréter les écarts et les limites du lab sans les maquiller.

**Prérequis** : M08-E28 (mesures de `ceph-par1` depuis `cephcli01`), M16-E26 (`ceph-rbd-chiffre`, volume `e26-temoin`), M16-E15 (mesures Longhorn consignées), M13 (chaîne de construction et de signature des images de plateforme).
**Durée indicative** : 3 h.

**Contexte technique**
- Image **`registry.par1.medisphere.internal/plateforme/outils-stockage:1.0.0`** : Debian 13 (`debian:trixie-slim` par le cache), paquets `fio` et `rsync` de Debian, utilisateur non root, construite et signée par le même chemin que les autres images du projet Harbor `plateforme` (M13) ; elle sert aussi en E29.
- Pods de mesure dans `wb-essais`, **tous sur le même travailleur** (`k8s-w01`), conformes à la PSA `restricted`, par un Job paramétré (classe, profil) généré par un script de `plateforme/k8s/outils/` ; un PVC de 4 Gio par mesure, fichier de travail de 2 Gio, supprimé après la mesure.
- Profils imposés (même fichier `fio` pour toutes les cibles, `--direct=1`, `ioengine=libaio`, 60 s après 10 s de chauffe, 3 répétitions) :

  | Profil | Représente | Paramètres |
  |---|---|---|
  | `wal` | journal de PostgreSQL | écriture séquentielle 8 Kio, profondeur 1, `fdatasync` à chaque écriture |
  | `oltp` | pages de la base | 70 % lecture / 30 % écriture aléatoires 8 Kio, profondeur 16 |
  | `iops` | plafond d'opérations | écriture aléatoire 4 Kio, profondeur 32 |
  | `debit` | sauvegarde, export | lecture séquentielle 1 Mio, profondeur 8 |

- Cibles : `ceph-rbd`, `ceph-rbd-chiffre`, `cephfs`, `emptyDir` (disque local du nœud, sur `local-nvme`), et **Longhorn** : chiffres repris de M16-E15 s'il a été retiré (le dire). Point de comparaison : les chiffres de M08-E28 (`cephcli01`, client noyau, même pool ou pool de même classe).
- Résultats : `docs/kubernetes/stockage/tests/performances.md` (tableau IOPS, débit, latence moyenne et p99 par profil et par cible, avec la dispersion des 3 répétitions, la date, les versions, l'état du cluster pendant la mesure).

> ⚠️ **Attention** : (1) une mesure `iops` ou `debit` charge **tout** `ceph-par1` (et donc les volumes de la recette et d'OpenStack s'il tourne) : préviens, mesure hors démonstration, une cible à la fois ; (2) vérifie avant chaque série la marge du quota de `k8s-rbd` ; (3) un `emptyDir` remplit le disque du nœud (`/var/lib/kubelet`) : la limite `sizeLimit` et un fichier de 2 Gio suffisent, le kubelet expulse le pod au-delà ; (4) ne mesure **jamais** sur un volume qui porte des données (`e26-temoin` est un volume d'essai : c'est permis, en écrasant son fichier de travail seulement).

**Travail demandé**
1. **L'image.** Écris le Containerfile, fais-le construire, analyser, signer et pousser par la chaîne de M13. Vérifie la signature avant de l'utiliser dans le cluster.
2. **Le banc.** Écris le fichier de profils `fio` et le script qui génère le Job (classe ou `emptyDir`, profil, répétition) : PVC dédié, pod non root, `nodeSelector` sur `k8s-w01`, résultats en JSON (`--output-format=json`) récupérés par `kubectl logs`, nettoyage du PVC à la fin même en cas d'échec.
3. **Contrôle du banc.** Avant toute campagne, vérifie qu'un même profil donne des résultats stables (écart entre répétitions < 15 %) et que le cache de pages ne fausse pas les lectures (que se passe-t-il sans `--direct=1` ?).
4. **La campagne.** Mesure les quatre profils sur les cinq cibles (Longhorn compris si encore présent). Pour `ceph-rbd-chiffre`, mesure aussi l'utilisation du processeur du nœud pendant `debit` (`kubectl top node`, `mpstat` sur le nœud).
5. **Interpréter.** Dans `performances.md`, réponds au minimum : quel est le surcoût de Kubernetes par rapport au client noyau nu de M08-E28, et pourquoi ? Que coûte LUKS, et sur quelle ressource ? Pourquoi `wal` est-il de loin le profil le plus lent sur Ceph, et ce que cela implique pour PostgreSQL (temps de validation d'une transaction) ? Pourquoi `emptyDir` est-il plus rapide, et pourquoi n'est-ce pas une option pour la base ? Ce que le lab ne permet **pas** de conclure (un seul hyperviseur, des OSD sur un même disque physique, réseau virtuel).
6. **Nettoyer.** Supprime les PVC de mesure, les Jobs, et `e26-temoin` (son rôle est fini).

**Critères de réussite**
- [ ] L'image `plateforme/outils-stockage:1.0.0` est dans Harbor, signée.
- [ ] `performances.md` est sur `main` de `plateforme/medisphere` : quatre profils × au moins quatre cibles (`ceph-rbd`, `ceph-rbd-chiffre`, `cephfs`, `emptyDir`) + Longhorn (mesuré ou repris de E15), avec la dispersion des répétitions, et les cinq questions de l'étape 5 traitées.
- [ ] Le script du banc est sur `main` de `plateforme/k8s`.
- [ ] Aucun Job, pod ou PVC de mesure ne subsiste dans `wb-essais` ; `e26-temoin` est supprimé.

**Vérification** : `lab/bin/check 16 28`

<details><summary>Indice 1</summary>

La latence d'une écriture avec `fdatasync` à profondeur 1 est un aller-retour complet : nœud → OSD primaire → réplicas → acquittement, plus le temps d'écriture durable sur chaque OSD. Aucune profondeur de file ne la masque. Compare-la au temps d'aller-retour réseau sur le VLAN 30 et à la latence du profil `iops`.
</details>

<details><summary>Indice 2</summary>

Avec un fichier de 2 Gio sur un PVC de 4 Gio, la première écriture alloue des objets RADOS qui n'existaient pas (provisionnement fin) : la première passe n'est pas représentative. C'est le rôle de la chauffe, et d'une préparation du fichier (`fio` sait le pré-remplir).
</details>

**Pour aller plus loin** (facultatif) : `kubectl cnpg fio` (Job `fio` fourni par le plugin) ; `pgbench` sur `ceph-rbd` et `ceph-rbd-chiffre` pour relier `wal` à un nombre de transactions par seconde ; la classe de QoS de RBD (`VolumeAttributesClass`) ; [fio](https://fio.readthedocs.io/), [CNPG benchmarking](https://cloudnative-pg.io/documentation/1.30/benchmarking/).

---

### M16-E29 — Migrer des données d'une classe de stockage à une autre  `LAB` `★★★`

> **Ticket SEC-1729** — *De : Sophie Laurent* — *Copie : Julien Petit*
> La classe chiffrée existe (SEC-1726). Les volumes existants, eux, sont toujours en clair, et on ne chiffre pas un volume en place. Je veux que le Valkey de la recette passe sur `ceph-rbd-chiffre` cette semaine, et qu'on ait une procédure pour les suivants.
> *Julien* : d'accord, mais l'API ne doit pas tomber. Valkey peut s'absenter un peu, l'API sait vivre sans cache. Une ou deux minutes, pas plus.

**Objectifs pédagogiques**
- Savoir quand une « migration » n'en est pas une (changer la politique de récupération d'un PV se fait **en place**) et quand elle est inévitable (changer de pilote ou de chiffrement).
- Comparer les voies : instantané et clone, Velero avec changement de classe, copie de fichiers, réplication applicative.
- Mener une migration par copie avec une coupure minimale (pré-copie à chaud, copie finale à froid) et un retour arrière garanti.
- Réattacher un PV à un PVC de nom imposé, et contourner l'immuabilité des `volumeClaimTemplates` d'un StatefulSet.

**Prérequis** : M16-E03 (liaison PV/PVC, `claimRef`), M16-E08 (StatefulSet Valkey), M16-E10 (instantanés et clones), M16-E26 (`ceph-rbd-chiffre`), M16-E28 (image `outils-stockage`).
**Durée indicative** : 3 h.

**Contexte technique**
- Source : le StatefulSet `valkey` de `mediagenda-recette` (une réplique, PVC `donnees-valkey-0` créé par `volumeClaimTemplates` sur `ceph-rbd`, persistance configurée en E08). Cible : `ceph-rbd-chiffre`, même taille. Le **nom** du PVC final ne change pas (le StatefulSet le retrouve par son nom).
- Ce que dit le code de MédiAgenda (`apps/mediagenda`) : sans Valkey, les créneaux sont calculés depuis la base (mode dégradé) et la création de rendez-vous ne dépend pas du cache ; mais `/pret` répond 503 dès que Valkey **ou** PostgreSQL ne répond pas. Ce que cela produit pendant une coupure de Valkey dépend donc de la façon dont les sondes de l'API ont été écrites (M14-E08) : à toi de le constater avant de promettre quoi que ce soit à Julien. Indisponibilité maximale de Valkey : **2 minutes** ; indisponibilité de l'**API** : aucune.
- Copie par un Job (image `outils-stockage`, `rsync`), dans le même espace de noms. La procédure devient le runbook **RB-163** (`docs/kubernetes/stockage/runbooks/RB-163-migrer-un-volume.md`) ; le compte rendu de cette migration va dans `docs/kubernetes/stockage/tests/migration-valkey.md` (étapes, heures, durée de la coupure, contrôles).

> ⚠️ **Attention** : (1) avant **toute** suppression de PVC, passe le PV source en `Retain` : c'est ton retour arrière (avec `Delete`, supprimer le PVC détruit l'image RBD) ; (2) un PVC RWO déjà monté ne peut être monté par un second pod **que sur le même nœud** ; (3) `kubectl delete statefulset --cascade=orphan` laisse les pods tourner sans propriétaire : ne l'utilise qu'au moment prévu par ta procédure ; (4) garde le volume source (en `Retain`) jusqu'à la validation, puis supprime-le **et** son image RBD (un PV `Retain` supprimé laisse l'image dans Ceph).

**Travail demandé**
1. **Ce qui n'est pas une migration.** Sur un PVC d'essai de `wb-essais` (`ceph-rbd`), passe son PV en `Retain` sans déplacer de données, supprime le PVC, constate que l'image RBD reste, puis réattache le PV à un nouveau PVC. Quelles demandes de « migration » se règlent ainsi (politique de récupération), lesquelles non (classe, chiffrement, pilote, taille à la baisse) ?
2. **Les voies.** Tableau : instantané + clone vers la classe chiffrée (que dit la documentation de ceph-csi sur un volume chiffré créé depuis une source en clair ? qu'obtiendrais-tu ?), Velero avec la ConfigMap de changement de classe (durée de coupure ?), copie de fichiers à chaud puis à froid, réplica Valkey sur un nouveau volume puis bascule. Choisis, justifie, et écris le plan avec ses points de non-retour et son retour arrière.
3. **Répétition et préparation.** Sur une copie de l'API dans `wb-essais` (ou, après avoir prévenu Julien, sur la recette), coupe Valkey 2 minutes et mesure ce que voient les utilisateurs de l'API (témoin de E25). Si l'API devient indisponible, explique pourquoi, choisis comment l'éviter pendant la migration (par le code, avec retour à l'état normal après), et ouvre la demande d'évolution à l'équipe de Julien (ticket DEV) que ce constat justifie. Écris ensuite dans Valkey des clés témoins (au moins 1 000, avec une somme de contrôle connue) ; vérifie la persistance sur disque. Crée le PVC cible temporaire sur `ceph-rbd-chiffre`. Passe le PV source en `Retain`.
4. **Pré-copie à chaud.** Un Job `rsync` monte le PVC source (en lecture) et la cible, **sur le nœud** du pod Valkey, avec les bons droits (utilisateur, groupe de fichiers) et les contraintes PSA `restricted`.
5. **Bascule.** Arrête Valkey (le StatefulSet à 0), copie finale, puis rattache le volume cible sous le **nom** du PVC du StatefulSet ; recrée le StatefulSet avec `ceph-rbd-chiffre` dans ses `volumeClaimTemplates` (par le code) ; redémarre. Chronomètre la coupure de Valkey et, avec le témoin de E25, vérifie que l'API a continué de créer des rendez-vous pendant toute la coupure.
6. **Valider.** Clés témoins et somme de contrôle identiques ; le volume monté est chiffré (`lsblk` sur le nœud, métadonnées de l'image) ; la sonde E27 est verte. Puis supprime le volume source (PV et image RBD) et le PVC d'essai de l'étape 1.
7. **Écrire** RB-163 (générique : n'importe quel volume RWO d'un StatefulSet ou d'un Deployment, avec les variantes) et le compte rendu. Dis ce qui changerait pour les volumes de `mediagenda-db` (CloudNativePG : ne pas copier, laisser l'opérateur recréer les instances une à une ? à vérifier dans sa documentation).

**Critères de réussite**
- [ ] Le StatefulSet Valkey de `mediagenda-recette` déclare `ceph-rbd-chiffre` dans ses `volumeClaimTemplates` (code sur `main`) ; son PVC est lié à un volume de `ceph-rbd-chiffre`, et ce volume est chiffré.
- [ ] Aucun PVC temporaire de migration ne subsiste ; l'ancien PV a été supprimé, et son image RBD aussi.
- [ ] Le compte rendu donne la durée de la coupure de Valkey (≤ 2 min), le résultat des contrôles de clés, le journal du témoin de l'API (aucun échec pendant la coupure) et la mesure prise pour y parvenir ; les sondes de l'API sont revenues à leur état normal ; RB-163 est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 16 29`

<details><summary>Indice 1</summary>

Un PV `Retain` dont le PVC a disparu passe en `Released` et garde un `claimRef` vers l'ancien PVC (avec son `uid`) : il n'est pas disponible pour un nouveau PVC tant que cette référence n'est pas retirée ou réécrite. Un PVC qui nomme explicitement un PV (`volumeName`) et sa classe peut alors s'y lier.
</details>

<details><summary>Indice 2</summary>

Les `volumeClaimTemplates` d'un StatefulSet ne se modifient pas : il faut supprimer l'objet StatefulSet **sans** supprimer ses pods ni ses PVC, puis le recréer. Quand il revient, il cherche des PVC aux noms `<modèle>-<statefulset>-<ordinal>` : s'il les trouve, il les adopte tels quels, quelle que soit leur classe.
</details>

<details><summary>Indice 3</summary>

Pour la pré-copie, `rsync` sur un répertoire qu'un processus modifie produit une copie incohérente, mais rapide à compléter : c'est la copie finale, à froid, qui garantit la cohérence, et elle ne transfère que ce qui a changé. Mesure-la pendant la répétition à blanc : c'est elle qui fait ta coupure.
</details>

**Pour aller plus loin** (facultatif) : migrer un volume RWX CephFS vers une autre classe (plusieurs pods écrivent : comment geler ?) ; la fonction *VolumePopulator* et les sources de données inter-espaces ; [ceph-csi RBD encryption](https://github.com/ceph/ceph-csi/blob/v3.18.1/docs/rbd/deploy.md), [Velero : changer de classe](https://velero.io/docs/v1.18/restore-reference/#changing-pvpvc-storage-classes).

---

### M16-E30 — ADR : le stockage de `k8s-par1`  `RED` `★★`

> **Ticket PLAT-1730** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent*
> J'ai tranché le principe en début de module : on s'appuie sur `ceph-par1`. Maintenant que vous avez installé, mesuré et démonté Rook et Longhorn, je veux l'ADR-0160 qui le justifie — ou qui me dit que j'avais tort. Avec ce que ça nous coûte, et ce qu'on fera quand on aura un second site.

**Objectifs pédagogiques**
- Comparer des architectures de stockage pour Kubernetes sur des critères pondérés, à partir de faits vérifiés dans le module.
- Séparer le choix du **fournisseur** de stockage (où vivent les données) de celui du **pilote** (comment Kubernetes les consomme).
- Écrire une décision avec ses conséquences négatives et ses actions.

**Prérequis** : M16-E06, E07, E13 à E15 (Rook, Longhorn), E26, E28, M08-E33 (politique de stockage de Ceph), M14-E31 (ADR-0140).
**Durée indicative** : 2 h.

**Travail demandé**
Rédige `docs/kubernetes/stockage/adr/ADR-0160-stockage-k8s-par1.md` (gabarit MADR, deux pages au plus), par MR sur `plateforme/medisphere`. L'ADR doit au minimum :
1. Énoncer le **contexte** : charges (PostgreSQL de MédiAgenda, Valkey, fichiers partagés de MédiDoc, volumes des équipes), exigences (données de santé, chiffrement, sauvegarde hors cluster, PRA à PAR2 au final F5), contraintes du lab (un hyperviseur, disques partagés) et de la cible.
2. Lister des **critères** pondérés : domaine de panne (qu'est-ce qui tombe avec le cluster Kubernetes ?), performances mesurées (E28), chiffrement, instantanés et clones, sauvegarde et restauration (E17, E24), exploitation (mises à jour, supervision, compétences de l'équipe), consommation de ressources des nœuds, couplage des cycles de vie (Kubernetes et stockage), multi-consommateurs (OpenStack, VMs), réversibilité.
3. Comparer au moins quatre **options** : ceph-csi vers `ceph-par1` (externe) ; Rook en mode interne (Ceph dans le cluster) ; Rook en mode **externe** vers `ceph-par1` ; Longhorn ; et, pour mémoire, des volumes locaux (`local` / TopoLVM) laissant la réplication à l'application.
4. **Trancher**, et dire ce que deviennent les options écartées (retirées en fin de module, reprises un jour pour quel cas ?).
5. Lister les **conséquences** négatives et les actions rattachées à un module : dépendance de `k8s-par1` au VLAN 30 et à `ceph-par1`, gestion des clés cephx et de la KEK (Vault, M25), supervision (M21), réplication vers PAR2 (F5), montée de version coordonnée de Ceph et de ceph-csi (M16-E33, F4).

**Critères de réussite**
- [ ] L'ADR suit le gabarit, tient en deux pages, contient un tableau critères × options pondéré.
- [ ] Au moins quatre options ; chaque évaluation renvoie à un fait vérifié (exercice, mesure, documentation).
- [ ] La décision dit ce que deviennent Rook et Longhorn, et la distinction fournisseur/pilote est explicite.
- [ ] Les conséquences négatives sont écrites, avec des actions rattachées à un module ou datées.

Auto-évaluation : grille fournie dans le corrigé.

<details><summary>Indice 1</summary>

Demande-toi, pour chaque option, ce qui se passe le jour où le cluster Kubernetes est **perdu** (etcd irrécupérable, montée de version ratée) : où sont les données, et que faut-il pour les relire depuis un cluster neuf ? Puis le jour où c'est le stockage qui tombe : qu'est-ce qui s'arrête en plus de Kubernetes ?
</details>

<details><summary>Indice 2</summary>

Rook n'est pas qu'un Ceph dans Kubernetes : en mode externe, c'est aussi une façon de déployer et de configurer les pilotes ceph-csi (par son opérateur CSI) vers un cluster existant. Compare ce que tu as fait à la main en E06-E07 à ce que ce mode automatise, et à ce qu'il ajoute comme composant à maintenir.
</details>

**Pour aller plus loin** (facultatif) : le stockage NVMe-oF de Ceph Tentacle et son pilote (alpha dans ceph-csi 3.18) ; [ceph-csi](https://github.com/ceph/ceph-csi), [Rook external cluster](https://rook.io/docs/rook/latest/CRDs/Cluster/external-cluster/external-cluster/), [Longhorn architecture](https://longhorn.io/docs/1.13.0/concepts/).

---

### M16-E31 — Questions de production : données dans Kubernetes  `Q` `★★★`

> **Ticket PLAT-1731** — *De : Karim Benali*
> Avant de te laisser l'astreinte sur les données du cluster, je veux t'entendre sur ces questions. Argumente, chiffre quand c'est possible, et dis de quoi dépend le « ça dépend ».

**Objectifs pédagogiques**
- Raisonner sur le comportement en production des données dans Kubernetes : volumes, pilotes, sauvegardes, bases opérées.
- Relier les choix du module à des risques concrets.

**Prérequis** : paliers 1 et 2, M16-E24 à E30.
**Durée indicative** : 1 h 30.

**Questions**

1. Le travailleur qui porte le primaire de `mediagenda-db` perd son alimentation (VM arrêtée brutalement). Décris, dans l'ordre, ce qui se passe côté Kubernetes (nœud `NotReady`, pods, VolumeAttachment), côté CloudNativePG (bail, élection) et côté Ceph (verrou exclusif de l'image RBD, liste de blocage). Au bout de combien de temps la base accepte-t-elle de nouveau des écritures ? Qu'est-ce qui empêche l'ancien primaire d'écrire encore s'il revenait à moitié ?
2. QCM — Un pod qui monte un PVC RWO `ceph-rbd` est sur un nœud devenu `NotReady`. Le Deployment recrée le pod ailleurs. Le nouveau pod :
   a) démarre immédiatement, le volume étant détaché automatiquement du nœud perdu ;
   b) reste en `ContainerCreating` avec une erreur *Multi-Attach* tant que le VolumeAttachment de l'ancien nœud existe ;
   c) démarre, mais en lecture seule ;
   d) ne peut jamais démarrer tant que le nœud n'est pas revenu.
   Justifie, et dis ce que change la marque `node.kubernetes.io/out-of-service`.
3. Velero sauvegarde `mediagenda-recette` chaque nuit, volumes compris (*data mover*). Pourquoi cette sauvegarde ne remplace-t-elle pas celle de CloudNativePG pour la base ? Et l'inverse : que manque-t-il à une sauvegarde CloudNativePG seule pour reconstruire l'application ?
4. Un instantané CSI d'un volume de base de données est-il une sauvegarde ? Est-il cohérent ? Que fait CloudNativePG quand il sauvegarde par instantanés de volumes (*volume snapshot backup*) pour le rendre exploitable ?
5. QCM — Tu supprimes par erreur l'espace de noms `mediagenda-dev`. Les classes sont en `reclaimPolicy: Delete`. Qu'as-tu perdu ?
   a) rien, les PV sont conservés tant qu'un instantané existe ;
   b) les objets de l'espace, et les images RBD de ses PVC (et leurs instantanés CSI) ;
   c) seulement les objets ; les images RBD restent dans Ceph jusqu'à l'intervention d'un administrateur ;
   d) les objets et les PVC, mais les PV passent en `Released`.
   Justifie, et dis ce qui permet de restaurer, avec quel RPO.
6. Le quota du pool `k8s-rbd` est atteint. Que voient : un PVC en cours de création, un pod qui écrit dans un volume existant, PostgreSQL, Valkey ? Quel signal t'aurait prévenu avant, et à quel seuil ?
7. Pourquoi l'archivage des WAL bloqué est-il une urgence alors que la base répond normalement ? Que se passe-t-il pour l'espace disque du primaire, et pour le RPO ?
8. QCM — `mediagenda-db` est en réplication **asynchrone**. Le primaire meurt brutalement avec 200 ms de transactions validées non encore reçues par les réplicas. Après la bascule :
   a) ces transactions sont rejouées depuis l'archive S3 ;
   b) elles sont perdues ;
   c) l'ancien primaire les renvoie au nouveau à son retour ;
   d) la bascule est refusée tant qu'elles ne sont pas récupérées.
   Justifie, et dis ce que coûterait `synchronous` avec `dataDurability: required` sur un cluster de 3 instances dont une est en maintenance.
9. Le chiffrement LUKS des volumes (E26) protège-t-il contre un administrateur de Kubernetes ? contre un administrateur de Ceph ? contre une sauvegarde Velero volée ? Où est la DEK de chaque copie ?
10. Tu dois mettre à jour ceph-csi pendant qu'un volume CephFS est monté par le client **FUSE** sur un nœud. Pourquoi est-ce dangereux, et pourquoi ce n'est pas le cas du client noyau ? Que recommande la documentation ?
11. QCM — Une restauration Velero vers un **autre** espace de noms échoue partiellement : les PVC sont `Bound`, mais les pods restent en `Pending` avec « volume node affinity conflict ». La cause la plus probable :
    a) la classe n'existe pas dans le cluster ;
    b) le PV restauré porte une affinité de nœud (volume local ou topologie) incompatible avec les nœuds disponibles ;
    c) le quota de l'espace de noms est dépassé ;
    d) le node-agent est absent.
    Justifie, et dis pourquoi ce n'est pas le cas de `ceph-rbd`.
12. Pourquoi une montée majeure de PostgreSQL rend-elle inutilisables, pour une restauration à un instant donné postérieur, les sauvegardes et WAL antérieurs ? Que fais-tu juste après la montée ?
13. La sonde E27 lit `kubelet_volume_stats_used_bytes`. Un PVC de 10 Gio annonce 9,5 Gio utilisés mais `ceph df` ne montre que 3 Gio pour toute l'image. Explique (système de fichiers, provisionnement fin, `discard`). Lequel des deux chiffres déclenche le « disque plein » de l'application ?
14. Compare RPO et RTO pour la base de MédiAgenda selon trois incidents : suppression accidentelle de lignes, perte du cluster Kubernetes, perte de `ceph-par1`. Quelles sauvegardes servent dans chaque cas (CloudNativePG, Velero, etcd, PBS) ?
15. Pourquoi ne pas mettre la base de MédiAgenda sur `cephfs` (RWX) pour « faciliter les bascules » ? Et pourquoi pas sur `emptyDir` avec trois réplicas, puisque les données sont répliquées par PostgreSQL ?
16. L'auditeur HDS demande la preuve que les sauvegardes de la base sont restaurables. Que lui montres-tu (artefacts, fréquence, qui signe) ?

Les réponses argumentées sont dans le corrigé.

---

### M16-E32 — Politique de sauvegarde des données Kubernetes  `RED` `★★`

> **Ticket PLAT-1732** — *De : Claire Morel* — *Copie : Sophie Laurent, Nadia Roussel*
> On a quatre mécanismes de sauvegarde qui se recouvrent : les instantanés d'etcd (M14), Velero, CloudNativePG, et PBS sous Ceph (M08). Je veux une politique qui dise, **pour chaque donnée**, qui la sauvegarde, à quel rythme, où, combien de temps, avec quel RPO et quel RTO **mesuré** — et qui teste la restauration, quand.

**Objectifs pédagogiques**
- Construire une politique de sauvegarde par donnée, pas par outil.
- Relier chaque engagement (RPO, RTO, rétention) à un mécanisme existant et à une preuve (test de restauration).
- Couvrir le cycle de vie complet : rétention, chiffrement, effacement (RGPD), tests, alertes.

**Prérequis** : M14-E24 (etcd), M16-E16, E17, E19, E24, E25, M08-E25 (PBS), M08-E33 (politique de stockage), M16-E27 (sonde).
**Durée indicative** : 2 h 30.

**Travail demandé**
Rédige `docs/kubernetes/stockage/politique-sauvegarde.md` dans `plateforme/medisphere` (3 à 5 pages, par MR, relue par Claire, Sophie et Nadia — joue leur rôle avec la grille du corrigé). Elle doit au minimum couvrir :
1. **Objet et périmètre** : les données du cluster `k8s-par1` (état du cluster, objets des applications, volumes, bases opérées) ; ce qui n'en relève pas (`ceph-par1` lui-même, `s3-01`, les VMs).
2. **Inventaire par donnée** : état du cluster (etcd), objets de chaque espace applicatif, volumes de chaque application (Valkey, fichiers de MédiDoc), bases PostgreSQL, Secrets (et leur source de vérité réelle : Vault/Ansible Vault, pas la sauvegarde), configuration de la plateforme (dépôts Git). Pour chacune : mécanisme, fréquence, destination, rétention, chiffrement, RPO, RTO **mesuré** (ou « non mesuré » assumé), propriétaire.
3. **Dépendances de restauration** : ce qu'il faut pour restaurer chaque donnée (le cluster ? `s3-01` ? les clés ?), dans quel ordre, et ce qui se passe si `s3-01` est perdu (où sont les sauvegardes des sauvegardes ?).
4. **Tests de restauration** : lesquels (E24, E19, E34, M14-E24), à quel rythme, qui, quelle preuve conservée, quel critère d'échec.
5. **Supervision et alertes** : ce que surveille `ms-verif-k8s-stockage` (E27), seuils, qui est alerté.
6. **Rétention et effacement** : durées par donnée, cohérence avec la politique de stockage (M08-E33), effacement d'une donnée de patient sur demande (que deviennent les copies dans les sauvegardes ? délai réel).
7. **Exceptions, limites et gestion du document** : un seul site en v1, `s3-01` VM unique, ce qui n'est pas couvert ; propriétaire, version, date de revue.

**Critères de réussite**
- [ ] Les sept rubriques sont présentes ; l'inventaire couvre au moins etcd, les objets, les volumes Valkey, les bases PostgreSQL et les Secrets.
- [ ] Chaque RPO/RTO renvoie à un mécanisme existant et, pour le RTO, à un test réel (ou est marqué non mesuré, avec une action datée).
- [ ] Les dépendances de restauration et le cas « perte de `s3-01` » sont traités honnêtement.
- [ ] Le document est sur `main` de `plateforme/medisphere`, au chemin imposé.

Auto-évaluation : grille fournie dans le corrigé.

<details><summary>Indice 1</summary>

Pars des **incidents** plutôt que des outils : suppression de lignes, suppression d'un espace de noms, perte d'un PV, perte du cluster, perte de `ceph-par1`, perte de `s3-01`, rançongiciel avec des identifiants d'administration. Pour chacun : quelle copie sert, et existe-t-elle hors de portée de ce qui a été perdu ?
</details>

<details><summary>Indice 2</summary>

Un RTO « 1 h » non mesuré est un souhait. Reprends les durées réellement chronométrées (E19, E24, E34, M14-E24) et dis ce qui les ferait varier en production (volumétrie, téléchargement des WAL, personne disponible).
</details>

**Pour aller plus loin** (facultatif) : la règle 3-2-1 et ses variantes (copie immuable : verrouillage d'objets S3) ; la réplication des sauvegardes de `s3-01` vers PAR2 (F5) ; [Velero : planifications et durée de vie](https://velero.io/docs/v1.18/backup-reference/), [CNPG backup](https://cloudnative-pg.io/documentation/1.30/backup/).

---

### M16-E33 — Mettre à jour ceph-csi et CloudNativePG sans interruption  `LAB` `★★★`

> **Ticket CHG-1733** — *De : Karim Benali*
> ceph-csi, CloudNativePG et le plugin Barman Cloud publient des versions correctives tous les mois ou presque, souvent avec des correctifs de sécurité (CloudNativePG en a publié trois cette année). Ce sont « juste » des correctives, mais ce sont les pièces qui tiennent nos données : je veux la procédure, les témoins, et la preuve qu'aucune application n'a rien vu — ou la mesure exacte de ce qu'elle a vu. Et je veux qu'on l'ait faite **une fois** avant d'en avoir besoin en urgence.

**Objectifs pédagogiques**
- Lire des notes de version et une procédure de mise à jour amont, et en tirer un ordre, des prérequis et des points de retour arrière.
- Comprendre ce que redémarre chaque mise à jour : pilotes CSI (contrôleurs, *nodeplugins*), opérateur, gestionnaire d'instance de chaque pod PostgreSQL, *sidecar* du plugin.
- Mettre à jour sans interruption perceptible, en le prouvant par des témoins.

**Prérequis** : M16-E06, E07, E18, E19, E25 (témoin, bascules), M14-E25 (procédure de montée de version, RB-142), M16-E27 (sonde).
**Durée indicative** : 3 h.

**Contexte technique**
- Versions de départ : celles installées en E06, E07 et E18 (ceph-csi **3.18.1**, charts `ceph-csi-rbd` et `ceph-csi-cephfs` ; opérateur CloudNativePG **1.30.1**, chart `cloudnative-pg` 0.29.1 ; plugin Barman Cloud **0.15.1**, chart `plugin-barman-cloud` 0.8.1). Cibles : la **dernière version corrective de la même mineure** publiée le jour où tu fais l'exercice (3.18.x, 1.30.x, 0.15.x), après lecture de ses notes. Pour un composant qui n'a pas encore de corrective plus récente, fais la **répétition générale** : mêmes témoins, mêmes étapes, avec un redémarrage contrôlé qui produit les mêmes effets qu'une mise à jour (`kubectl rollout restart` des contrôleurs et des *nodeplugins* de ceph-csi, de l'opérateur et du plugin ; `kubectl cnpg restart` pour les instances), et consigne-le ; la vraie mise à jour suivra RB-164 à la sortie de la corrective.
- Versions et valeurs épinglées dans `plateforme/k8s/composants/` ; la mise à jour est une MR (une par composant), appliquée par `task appliquer`.
- Témoins, lancés avant et arrêtés après chaque mise à jour : la boucle de l'API de E25 ; un pod de `wb-essais` qui écrit chaque seconde une ligne horodatée dans un volume `ceph-rbd` **et** un pod qui fait de même dans un volume `cephfs` ; un PVC créé et supprimé chaque minute (le provisionnement doit rester possible ou reprendre vite).
- Procédure : runbook **RB-164** (`docs/kubernetes/stockage/runbooks/RB-164-mettre-a-jour-le-stockage.md`) ; compte rendu `docs/kubernetes/stockage/tests/mise-a-jour-stockage.md`.

> ⚠️ **Attention** : (1) avant de commencer : sauvegarde Velero de `mediagenda-recette`, sauvegarde de base de `mediagenda-db` `completed`, archivage continu `True`, sonde E27 verte, instantané etcd récent ; (2) la mise à jour de l'opérateur redémarre par défaut **toutes** les instances PostgreSQL du cluster et finit par une **bascule** : lis le mode de mise à jour en place du gestionnaire d'instance avant de décider ; (3) un seul composant à la fois, retour au vert de la sonde entre deux ; (4) ne passe jamais une version mineure (3.19, 1.31) par erreur : la 1.31 de CloudNativePG **supprime** l'archivage intégré `barmanObjectStore` (sans effet ici puisque tu utilises le plugin, mais vérifie qu'aucun `Cluster` du lab ne s'en sert).

**Travail demandé**
1. **Lecture.** Notes de version des correctives visées (ceph-csi, CloudNativePG — et la section *Upgrades* de la documentation : deux étapes, mise à jour en place du gestionnaire d'instance, `CLUSTERS_ROLLOUT_DELAY`/`INSTANCES_ROLLOUT_DELAY`), plugin) ; procédure de mise à jour de ceph-csi (`docs/ceph-csi-upgrade.md` au tag) : ordre CephFS puis RBD, cas du client FUSE, contrôleur de snapshots. Construis la matrice : composant, version de départ et cible, compatibilités (Kubernetes 1.36, Ceph Tentacle, cert-manager), ce qui redémarre, effet attendu, retour arrière.
2. **Prérequis et témoins.** Vérifie les prérequis de l'avertissement, lance les témoins, et note leur état « avant » (aucune erreur depuis 10 minutes).
3. **ceph-csi.** MR (CephFS, puis RBD), application, puis observe : déploiement des contrôleurs (nombre de réplicas, élection), mise à jour progressive du DaemonSet des *nodeplugins* (un nœud à la fois ?), journaux des témoins. Un volume monté continue-t-il d'être écrit pendant le redémarrage du *nodeplugin* de son nœud ? Pourquoi ? Combien de temps la création de PVC a-t-elle été impossible ?
4. **CloudNativePG.** Décide entre la mise à jour avec redémarrage progressif des instances (bascule à la fin) et la mise à jour **en place** du gestionnaire d'instance ; justifie au regard du témoin de l'API. Applique (MR), observe la mise à jour des CRD, du déploiement de l'opérateur, puis des instances ; mesure par le témoin.
5. **Plugin Barman Cloud.** Applique, observe ce que devient le *sidecar* des instances (redémarrage ?), et vérifie que l'archivage des WAL n'a pas d'interruption durable (`ContinuousArchiving`, prochaine sauvegarde de base).
6. **Contrôles et retour arrière.** Tous les pods sur les nouvelles images ; sonde verte ; sauvegarde de base à la demande réussie ; un PVC `ceph-rbd-chiffre` créé et monté. Documente le retour arrière de chaque composant (Helm : `helm rollback` est-il sûr pour des CRD ? pour l'opérateur ?) sans l'exécuter.
7. **Écrire** RB-164 et le compte rendu (chronologie, ce que chaque témoin a vu, écarts).

**Critères de réussite**
- [ ] Tous les conteneurs `cephcsi` de l'espace `ceph-csi` sont sur une même version 3.18.x (au moins 3.18.1), DaemonSets et Deployments entièrement à jour et prêts.
- [ ] L'opérateur CloudNativePG est en 1.30.x (au moins 1.30.1) et le plugin Barman Cloud en 0.15.x (au moins 0.15.1) ; tous les `Cluster` du lab sont sains, archivage continu actif.
- [ ] Le compte rendu donne, pour chaque composant, ce qu'ont vu les témoins (erreurs, durées) ; RB-164 est sur `main` de `plateforme/medisphere` ; les versions sont épinglées sur `main` de `plateforme/k8s`.
- [ ] La sonde `ms-verif-k8s-stockage` est verte ; aucun témoin ne subsiste dans `wb-essais`.

**Vérification** : `lab/bin/check 16 33`

<details><summary>Indice 1</summary>

Un volume RBD monté par le client **noyau** est un périphérique `rbdN` du noyau du nœud : le *nodeplugin* l'a créé (`rbd map`) puis l'a monté, mais il n'est pas dans le chemin des entrées/sorties. Le redémarrer n'interrompt pas les écritures, il interrompt les **nouveaux** montages et démontages sur ce nœud. Ce n'est vrai ni pour `rbd-nbd`, ni pour CephFS en FUSE.
</details>

<details><summary>Indice 2</summary>

Le gestionnaire d'instance de CloudNativePG est le PID 1 de chaque pod PostgreSQL : le remplacer « normalement », c'est recréer le pod, donc redémarrer PostgreSQL. La mise à jour en place remplace le binaire sans tuer le *postmaster*. Lis ce qu'elle laisse en contrepartie (définition du pod qui ne reflète plus la version réelle) et comment l'activer (configuration de l'opérateur).
</details>

<details><summary>Indice 3</summary>

Les CRD de CloudNativePG sont dans les gabarits du chart (option `crds.create`) : un `helm upgrade` les met à jour, un `helm rollback` les ramènerait aussi. Lis ce qui peut alors arriver aux objets écrits par la nouvelle version, et préfère, pour le retour arrière, « corriger en avant » quand c'est possible.
</details>

**Pour aller plus loin** (facultatif) : passer à `ceph-csi-operator` (utilisé par Rook) ; automatiser les mises à jour correctives par Renovate (M13) avec ces témoins comme tests ; [ceph-csi upgrade](https://github.com/ceph/ceph-csi/blob/v3.18.1/docs/ceph-csi-upgrade.md), [CNPG upgrades](https://cloudnative-pg.io/documentation/1.30/installation_upgrade/).

---

### M16-E34 — Restaurer la base de MédiAgenda en temps limité  `CHRONO` `★★★`

> **Ticket INC-4334** — *De : Nadia Roussel*
> Urgence. Le secrétariat de la clinique partenaire appelle : tous les rendez-vous d'un praticien ont disparu de l'agenda de recette, qui sert à la démonstration de demain matin. Un script de « nettoyage » lancé par erreur. L'heure de l'erreur est dans le ticket. Les autres praticiens ont continué à prendre des rendez-vous depuis : **on ne les perd pas**.
> Tu as 45 minutes.

**Règles de l'exercice**
- Conditions d'examen : pas de corrigé, pas d'autres notes que **tes** runbooks (RB-161, RB-162), ton code et la documentation officielle.
- L'incident est injecté par `lab/bin/break 16 34`, qui affiche l'heure de l'erreur : c'est T0. Durée cible : **45 minutes** entre T0 et la livraison vérifiée (T3).
- La base de production de l'exercice (`mediagenda-db` de `mediagenda-recette`) **n'est ni arrêtée, ni remplacée, ni restaurée par-dessus** : les écritures postérieures à l'erreur doivent survivre. Tout ce qui est créé pour l'enquête est supprimé avant T3.
- Aucune donnée de patient dans un document, un ticket ou un journal partagé : uniquement des identifiants de rendez-vous.

**Prérequis** : M16-E19 (PITR dans un nouveau cluster), M16-E24 (RB-161), M16-E25. Le runbook **RB-162** (restaurer PostgreSQL à un instant donné) doit exister (E19) ; s'il n'existe pas, écris-le **avant** de lancer l'exercice. L'archivage continu de `mediagenda-db` doit être actif et une sauvegarde de base `completed` doit exister : l'injection le vérifie.
**Durée** : 45 minutes chronométrées + 30 minutes de retour d'expérience.

**Dossier** : [`ressources/E34-dossier-chrono.md`](../ressources/E34-dossier-chrono.md) (le besoin, les exigences, la feuille de temps). Lis-le à T0, pas avant.

**Critères de réussite**
- [ ] Toutes les exigences du dossier sont satisfaites à T3 (vérification ci-dessous).
- [ ] La feuille de temps est remplie (T0 à T3) ; le temps total est inférieur à 45 minutes (sinon, améliore RB-162 et ton outillage, puis refais l'exercice : `lab/bin/break 16 34 --annuler` remet l'état initial).
- [ ] Le retour d'expérience (une demi-page) est rédigé et RB-162 mis à jour par MR.

**Vérification** : `lab/bin/check 16 34` (à lancer à T3).

**Pour aller plus loin** (facultatif) : refais l'exercice en visant 20 minutes avec un script de récupération sélective prêt à l'emploi (cluster temporaire, extraction, réinjection) ; demande-toi ce qu'il faudrait pour que l'équipe de Julien puisse le faire seule.
