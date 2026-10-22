# Module 22 — Palier 1 : Découverte

Avant de chercher quoi que ce soit dans les journaux, il faut un endroit où les ranger et un agent pour les y mettre. Ce palier installe **Loki** sur le RGW de `ceph-par1`, multi-locataire, publié pour les VMs sur 10.10.41.62 ; il déploie **Alloy** en DaemonSet pour les pods et les nœuds, apprend **LogQL** sur les vrais journaux du lab, puis branche les **VMs du socle** par un rôle Ansible. Le palier s'ouvre sur un questionnaire.

Prérequis : modules 20 et 21 terminés (`lab/bin/check 20 46` et `lab/bin/check 21 46` verts : Argo CD, `charts-miroir`, Grafana, Alertmanager, `plateforme/observabilite`) ; module 16 (RGW de `ceph-par1` joignable par la carte VLAN 30 des travailleurs) ; module 14 (journal d'audit de l'API). Lis [`00-introduction.md`](00-introduction.md), en particulier le chemin imposé, les faits techniques et les règles du module.

---

### M22-E01 — Test de positionnement : journaux  `Q` `★★`

> **Ticket PLAT-2301** — *De : Karim Benali*
> Le rituel : trois quarts d'heure, par écrit, sans moteur de recherche ni IA. Avant qu'on écrive la moindre étiquette, je veux savoir comment tu penses un journal : à quoi il sert, ce qu'il coûte, ce qu'il a le droit de contenir. Réponds même là où tu hésites.

**Objectifs pédagogiques**
- Situer les journaux par rapport aux métriques et aux traces.
- Évaluer ta compréhension des index, de la cardinalité, du multi-locataire et des obligations RGPD/HDS avant de les pratiquer.

**Prérequis** : aucun.
**Durée indicative** : 45 min (+ 20 min d'auto-correction).

**Travail demandé**

Réponds aux 14 questions. Pour les QCM, justifie ton choix en une ou deux phrases.

*Journaux, métriques, traces*

1. Donne, pour chacun des trois signaux (métrique, journal, trace), une question d'incident à laquelle il répond mieux que les deux autres. Pourquoi alerte-t-on d'ordinaire sur des métriques plutôt que sur des journaux ?

2. *(QCM)* MédiAgenda renvoie 2 % d'erreurs 500 depuis 10 minutes. Quel signal te donne le plus vite **la cause** ?
   - A. Le taux d'erreurs par route dans Prometheus
   - B. Les lignes d'erreur de l'API (avec le message d'exception) pour ces 10 minutes
   - C. Le nombre de pods prêts
   - D. La latence au 95e centile

3. Une application écrit ses journaux dans un fichier `/var/log/app.log` à l'intérieur de son conteneur. Cite trois problèmes que cela pose sur Kubernetes, et ce que dit le facteur XI des « 12 facteurs ».

*Index et cardinalité*

4. Un moteur à **index inversé** (OpenSearch, Elasticsearch) et Loki stockent tous deux des journaux. Explique en quelques lignes ce que chacun indexe, ce que cela coûte à l'écriture et au stockage, et quelle requête est rapide ou lente dans chacun.

5. Loki appelle **flux** l'ensemble des lignes qui portent exactement les mêmes étiquettes. Un collègue propose d'ajouter les étiquettes `pod`, `request_id` et `code_http`. Estime l'effet de chacune sur le nombre de flux du locataire `mediagenda`, et dis lesquelles tu refuses.

6. *(QCM)* Qu'est-ce qu'une **métadonnée structurée** dans Loki 3 ?
   - A. Une étiquette indexée, mais cachée dans Grafana
   - B. Une paire clé-valeur attachée à chaque ligne, stockée avec elle, non indexée, filtrable après le sélecteur de flux
   - C. Le contenu JSON de la ligne, analysé à l'écriture
   - D. Un champ calculé par la requête (`| json`)

7. Pourquoi un journal **structuré** (une ligne JSON par événement) est-il préférable à du texte libre, et qu'est-ce qu'il ne règle pas ?

*Collecte*

8. Sur un nœud Kubernetes avec containerd, où se trouve la sortie standard d'un conteneur ? Que se passe-t-il pour ces fichiers quand le pod est supprimé ? Quel est le rôle d'un **fichier de positions** pour un agent de collecte ?

9. Un agent de collecte tourne en DaemonSet sur six nœuds et lit, en plus des fichiers, les **événements Kubernetes** par l'API. Quel problème cela pose-t-il, et comment le résoudre ?

*Multi-locataire, rétention, données personnelles*

10. *(QCM)* Loki tourne avec `auth_enabled: true`. Une requête arrive **sans** en-tête `X-Scope-OrgID`. Que se passe-t-il ?
    - A. Elle va dans le locataire `fake`
    - B. Elle est refusée
    - C. Elle lit tous les locataires
    - D. Elle va dans le locataire par défaut configuré dans Loki

11. L'en-tête `X-Scope-OrgID` suffit-il à garantir qu'une équipe ne lit pas les journaux d'une autre ? Qu'est-ce qui doit l'entourer ?

12. Pourquoi garder les journaux d'audit **plus longtemps** que les journaux applicatifs ? Pourquoi ne pas tout garder un an « au cas où » ?

13. Un développeur journalise `"rendez-vous pris pour Jeanne Martin, NIR 2 85 07 75 123 456 78"`. Cite les règles RGPD et HDS en jeu, et les deux lignes de défense que la plateforme peut mettre en place. Laquelle est la seule complète ?

14. Un utilisateur exerce son **droit à l'effacement**. Ses données sont dans PostgreSQL, dans une sauvegarde, et peut-être dans des journaux. Qu'est-ce que cela implique pour la conception de la journalisation ?

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 14 questions avant d'ouvrir le corrigé.
- [ ] Tu as noté chaque réponse avec la grille (0, 1 ou 2 points) et calculé ton score sur 28.
- [ ] Tu as noté les thèmes à retravailler et les exercices du module qui les mobilisent.

<details><summary>Indice 1</summary>

Pour les questions d'index, pense à ce qu'il faut faire **à l'écriture** de chaque ligne (découper en mots ? ne rien faire ?) et **à la lecture** (consulter un dictionnaire de mots ? lire des blocs compressés ?).
</details>

<details><summary>Indice 2</summary>

Pour la cardinalité, multiplie : nombre d'espaces × de conteneurs × de valeurs de la nouvelle étiquette. Une étiquette dont la valeur change à chaque requête crée un flux par requête.
</details>

**Pour aller plus loin** (facultatif) : refais ce test à la fin du module (M22-E25), sans relire le corrigé, et compare.

---

### M22-E02 — Loki multi-locataire sur le RGW  `LAB` `★★`

> **Ticket PLAT-2302** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent*
> On installe Loki comme on a installé la supervision : chart recopié dans Harbor, Application Argo CD, valeurs dans `plateforme/observabilite`. Données sur le RGW de `ceph-par1`, dans un compartiment à lui, avec un utilisateur à lui et un quota. **Un locataire par équipe** dès le premier jour, et une source Grafana par locataire. Les VMs devront écrire depuis l'extérieur du cluster : publie l'API sur l'adresse réservée, 10.10.41.62, mais Sophie veut savoir qui peut lire et qui peut écrire. Pas de passerelle nginx, pas de memcached : le lab n'en a ni le besoin ni la mémoire.

**Objectifs pédagogiques**
- Déployer Loki en mode monolithique sur le stockage objet, par Argo CD, sans secret dans Git.
- Comprendre ce que le chart génère (configuration, StatefulSet, Services) et ce qu'il faut ajouter soi-même.
- Mettre en place le multi-locataire de bout en bout : Loki, sources Grafana, en-tête des requêtes.
- Publier un service hors du cluster avec une adresse demandée et une politique réseau qui distingue lecture et écriture.

**Prérequis** : M21-E46 ; M20-E13 (`charts-miroir`, Application multi-sources) ; M16 (RGW, carte VLAN 30 des travailleurs) ; M15 (LB IPAM, BGP, ExternalDNS, CiliumNetworkPolicy).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Chart | `grafana-community/loki` **19.0.3** (Loki 3.7.9), dépôt `https://grafana-community.github.io/helm-charts` ; empreinte de l'archive à relever dans l'index du dépôt |
| Application | `loki`, projet `plateforme`, fichier `plateforme/loki.yaml` de `plateforme/gitops` ; sources : le chart de Harbor, `plateforme/observabilite` (`loki/values.yaml`), et le dossier `loki/` de ce même dépôt (manifestes à toi) |
| Mode | `deploymentMode: Monolithic`, 1 réplica, WAL sur un PVC `ceph-rbd` de 20 Gio, PriorityClass `medisphere-critique` |
| Stockage | RGW `https://rgw.par1.medisphere.internal` ; utilisateur RGW `loki` (quota 50 Gio) ; compartiment `loki-k8s-par1` ; Secret `loki-objstore` (clés `LOKI_S3_ACCESS_KEY_ID`, `LOKI_S3_SECRET_ACCESS_KEY`) par `secrets-k8s.sh` (composant `loki`, Vault `critique` `secrets/loki.yml`) ; `~/.config/workbook/s3-loki.env` (600 : `AWS_ACCESS_KEY_ID=…`, `AWS_SECRET_ACCESS_KEY=…`) |
| Index | TSDB, schéma `v13`, tables de 24 h, préfixe `loki_index_`, à partir du `2026-10-01` |
| Service externe | `loki-externe`, `LoadBalancer`, adresse demandée **10.10.41.62**, port **3100** seul, `externalTrafficPolicy: Local`, nom `loki.apps.par1.medisphere.internal` (ExternalDNS) |
| Politique réseau | CiliumNetworkPolicy `loki-entree` : Alloy (espace `journaux`), Grafana et Prometheus (`supervision`), MGMT (10.10.10.0/24) ; les réseaux des VMs du socle (INFRA 10.10.20.0/24, DMZ 10.10.70.0/24, et l'adresse des passerelles sur le VLAN 40) **en écriture seulement** |
| Grafana | quatre sources `Loki — <locataire>` (UID `loki-<locataire>`) déclarées par code (ConfigMap étiquetée `grafana_datasource: "1"` dans `supervision`) |

**Travail demandé**

*A. Le stockage*

1. Sur `ceph01`, crée l'utilisateur RGW `loki` (`radosgw-admin user create`) et pose-lui un quota de 50 Gio (portée utilisateur, activé). Range ses clés dans `~/.config/workbook/s3-loki.env` (600) sur `adm01`, et dans le Vault `critique` de `plateforme/k8s` (`secrets/loki.yml`).
2. Avec ces clés, crée le compartiment `loki-k8s-par1` (`aws s3api create-bucket`, point d'accès du RGW). Vérifie qu'il est vide et que la racine MédiSphère suffit à vérifier le certificat (pas d'option qui désactive TLS).
3. Ajoute le composant `loki` à `plateforme/k8s/outils/secrets-k8s.sh` : il crée le Secret `loki-objstore` dans l'espace `journaux`. (L'espace n'existe pas encore : l'ordre des étapes compte, note-le.)

*B. Le chart et ses valeurs*

4. Ajoute le chart à `plateforme/charts-miroir` (`charts.yaml`), MR, pipeline : le chart doit être signé dans Harbor `charts/`.
5. Récupère le chart en local (`helm pull` depuis Harbor) et lis `values.yaml` : quelles sont les valeurs par défaut de `deploymentMode`, `gateway.enabled`, `chunksCache.enabled`, `lokiCanary.enabled`, `loki.auth_enabled`, `sidecar.rules.enabled` et `rbac.namespaced` ? Que crée le chart avec ces défauts ? Note-le dans `~/m22/e02/journal.md`.
6. Écris `loki/values.yaml` dans `plateforme/observabilite` : mode, réplicas, persistance, stockage S3 du RGW (identifiants par variables d'environnement venues du Secret, CA du RGW), schéma, locataires, limites de base, et désactive tout ce qui n'est pas demandé. Rends le chart (`helm template … -f loki/values.yaml`) et lis la **configuration de Loki générée** (ConfigMap `loki`) : retrouve-y chacune de tes valeurs.
7. Pourquoi la configuration effective ne doit-elle **jamais** contenir la clé secrète en clair ? Comment la tienne l'évite-t-elle ?

*C. Ce que le chart ne fait pas*

8. Dans `loki/` (dossier de `plateforme/observabilite`), ajoute les manifestes : l'espace `journaux` (Pod Security : lis la règle 5 de l'introduction et la prochaine étape E03 avant de choisir le niveau appliqué), la racine MédiSphère (ConfigMap `racine-medisphere`), le Service `loki-externe`, la CiliumNetworkPolicy `loki-entree`. Une `kustomization.yaml` les assemble.
9. Écris l'Application `loki` (trois sources), MR sur `plateforme/gitops`, synchronisation. Puis crée le Secret par `secrets-k8s.sh`. Suis le démarrage : `kubectl -n journaux get pods,pvc,svc` et les journaux du conteneur `loki`.

*D. Vérifier, du dehors et du dedans*

10. Depuis `adm01` : `/ready`, `/loki/api/v1/status/buildinfo`, puis `/loki/api/v1/labels` **sans** en-tête, puis **avec** `X-Scope-OrgID: plateforme`. Explique les réponses.
11. Pousse une ligne de test à la main dans le locataire `essai` (API `POST /loki/api/v1/push`, corps JSON), relis-la avec `query_range`, puis cherche-la dans le locataire `plateforme`. Conclusion ?
12. Lis la configuration effective (`/config`) : où sont `auth_enabled`, le schéma, le compartiment ? Où est la clé secrète ?
13. Déclare les quatre sources de Grafana par code (fichier dans `plateforme/observabilite`, consommé par l'Application `observabilite`). Dans Explore, sélectionne chaque source : laquelle montre ta ligne de test ? Pourquoi aucune ?
14. Après une ou deux heures d'ingestion (E03 en fait arriver), liste le compartiment : quels préfixes apparaissent ? Pourquoi rien n'y est-il écrit pendant la première demi-heure ?
15. Écris la fiche du service `docs/observabilite/journaux/loki.md` (plateforme/medisphere) et complète la matrice des flux du cluster.

**Critères de réussite**
- [ ] L'Application `loki` (projet `plateforme`, chart 19.x tiré de Harbor) est synchronisée et saine ; le StatefulSet tourne en mode monolithique avec son WAL sur `ceph-rbd` ; ni passerelle, ni memcached, ni canari dans `journaux`.
- [ ] Les identifiants S3 viennent du Secret `loki-objstore`, créé hors Git ; `s3-loki.env` est en 600.
- [ ] `loki.apps.par1.medisphere.internal` résout en 10.10.41.62 ; depuis `adm01`, `/ready` répond, et une requête sans `X-Scope-OrgID` est refusée (401).
- [ ] La configuration effective montre `auth_enabled: true`, le schéma v13 et le compartiment `loki-k8s-par1`.
- [ ] Une CiliumNetworkPolicy protège les pods Loki ; une VM du VLAN 20 ne peut que pousser (un `GET` depuis elle échoue).
- [ ] Les quatre sources Grafana existent, déclarées par code, chacune avec son locataire.
- [ ] Après ingestion, le compartiment contient l'index (`index/…`) et des chunks.

**Vérification** : `lab/bin/check 22 02`

<details><summary>Indice 1</summary>

Le chart ne génère pas toute la configuration de Loki lui-même : il assemble `loki.config` (un gabarit) à partir des sections `loki.*` de tes valeurs. Pour le stockage S3, regarde `loki.storage` (type, noms de compartiments, bloc `s3`). Loki remplace `${VARIABLE}` par l'environnement quand il démarre avec `-config.expand-env=true` : regarde les arguments du conteneur dans le rendu.
</details>

<details><summary>Indice 2</summary>

Pour l'adresse demandée : même annotation qu'au M15 (LB IPAM de Cilium). Pour distinguer lecture et écriture au niveau du réseau, une CiliumNetworkPolicy peut porter des **règles HTTP** (méthode, chemin) sur un port : cherche `rules.http` dans la documentation de Cilium. Pense à ce que voit Loki comme adresse source avec `externalTrafficPolicy: Local`, et à l'adresse qu'utilisent `gw01`/`gw02` pour joindre 10.10.41.0/24.
</details>

<details><summary>Indice 3</summary>

« Rien dans le compartiment » au début n'est pas une panne : l'ingester garde les chunks en mémoire (et dans le WAL) jusqu'à ce qu'ils soient pleins, inactifs ou trop vieux, et l'index TSDB est envoyé par lots. Cherche `chunk_idle_period`, `max_chunk_age` dans la référence de configuration.
</details>

**Pour aller plus loin** (facultatif) : lis la page « Deployment modes » de Loki : à partir de quel volume quotidien passerais-tu au mode microservices, et pourquoi le mode « simple scalable » n'est-il plus une option ?

---

### M22-E03 — Alloy dans le cluster : pods et nœuds  `LAB` `★★`

> **Ticket PLAT-2303** — *De : Karim Benali*
> Loki est vide. Déploie Alloy en DaemonSet dans `journaux` : les journaux de **tous** les pods, et le journal systemd de **chaque** nœud, contrôle compris. Deux règles non négociables. Un : les étiquettes, c'est une **liste fermée** — `cluster`, `namespace`, `app`, `container`, `node`, `job` — et rien d'autre ; le nom du pod n'en fait pas partie. Deux : le locataire se déduit de l'espace, `mediagenda-*` chez MédiAgenda, `medidoc-*` chez MédiDoc, le reste chez nous. Et je veux que la configuration passe la CI avant d'arriver dans le cluster.

**Objectifs pédagogiques**
- Écrire une configuration Alloy : découverte Kubernetes, règles de relabel, lecture de fichiers, traitement (`loki.process`), écriture.
- Comprendre le format CRI des journaux des conteneurs et le rôle des positions de lecture.
- Appliquer une politique d'étiquettes et de locataires, et la vérifier dans Loki.
- Donner à un agent de nœud le minimum de droits et de privilèges.

**Prérequis** : M22-E02.
**Durée indicative** : 2 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Chart | `grafana/alloy` **1.14.1** (Alloy v1.21.1), dépôt `https://grafana.github.io/helm-charts`, recopié dans Harbor |
| Application | `alloy`, projet `plateforme`, espace `journaux` ; valeurs `alloy/values.yaml`, configuration `alloy/config.alloy` de `plateforme/observabilite`, transformée en ConfigMap `alloy-config` |
| Fichiers des pods | `/var/log/pods/<espace>_<pod>_<uid>/<conteneur>/<n>.log`, format CRI (`<horodatage> <stdout|stderr> <F|P> <message>`) |
| Journal systemd | `/var/log/journal` sur chaque nœud (persistant sur Debian 13) |
| Écriture | `http://loki.journaux.svc.cluster.local:3100/loki/api/v1/push` (dans le cluster) |
| Taints des nœuds | `node-role.kubernetes.io/control-plane:NoSchedule` (k8s-cp01-03), `dedie=bdd:NoSchedule` (k8s-w03, M14-E14) |
| Valeurs de `job` | `pods`, `journald` |

**Travail demandé**

1. Recopie le chart dans Harbor (`charts-miroir`). Lis ses valeurs par défaut : où va la configuration ? où sont rangées les positions de lecture (`storagePath`) et sur quel type de volume ? quels droits RBAC donne-t-il ? quelles CRD crée-t-il ? Note-le.
2. Écris `alloy/config.alloy`, en commentant chaque bloc :
   - découverte des pods **du nœud seulement** (le nom du nœud vient d'une variable d'environnement que tu poses dans les valeurs) ;
   - règles de relabel : `cluster`, `job`, `namespace`, `container`, `node`, `app` (première valeur trouvée parmi `app.kubernetes.io/name`, `app`, `k8s-app`, sinon le nom du conteneur), une étiquette temporaire de **locataire**, une étiquette temporaire `pod`, et le chemin des fichiers ;
   - lecture des fichiers, puis un `loki.process` qui analyse le format CRI, applique le locataire, range `pod` (et tout ce que le format CRI ajoute) en métadonnées structurées et retire ce qui n'est pas dans la liste ;
   - le journal systemd du nœud (`job="journald"`, étiquette `node`), avec l'unité systemd et le niveau en métadonnées structurées, sans le niveau `debug`, sans relire plus de 12 heures au premier démarrage ;
   - l'écriture vers Loki (locataire par défaut : `plateforme`).
3. Vérifie localement : `alloy fmt --test` et `alloy validate` (binaire 1.21.1 téléchargé sur `adm01`, vérifié par sa somme). Provoque une erreur (attribut mal orthographié) : que dit `validate` ? Qu'est-ce qu'il ne peut **pas** vérifier ?
4. Ajoute un job de CI `alloy-validation` au pipeline de `plateforme/observabilite`, avec l'image de la même version.
5. Écris `alloy/values.yaml` : configuration lue d'une ConfigMap générée depuis `config.alloy` (kustomize), positions de lecture sur le disque du nœud, `/var/log` en lecture seule, variable du nom du nœud, tolérances, ressources, contexte de sécurité minimal, RBAC minimal, pas de CRD, ServiceMonitor avec l'étiquette de sélection du M21. Rends le chart et relis le DaemonSet.
6. Écris l'Application `alloy` (trois sources, comme `loki`), MR, synchronisation. Vérifie : un pod par nœud, tous prêts ; l'interface d'Alloy (`kubectl port-forward` sur le port 12345) montre le graphe des composants, tous sains.
7. Dans Grafana (Explore, source `Loki — plateforme`) : les journaux de `kube-system`, de `journaux`, le journal systemd de `k8s-cp02`. Source `Loki — mediagenda` : les journaux de `mediagenda-recette`. Puis, depuis `adm01`, liste les étiquettes indexées de chaque locataire (`/loki/api/v1/labels`) : y a-t-il autre chose que la liste ?
8. Supprime un pod Alloy (`kubectl delete pod`, dans `journaux`) pendant que `mediagenda-recette` reçoit du trafic : les lignes de la minute écoulée arrivent-elles ? en double ? Explique avec les positions de lecture.
9. Fais au moins une requête à MédiDoc (il ne journalise que les vraies requêtes) et retrouve sa ligne dans `Loki — medidoc`.

**Critères de réussite**
- [ ] L'Application `alloy` (chart de Harbor) est synchronisée et saine ; le DaemonSet a un pod prêt sur chacun des six nœuds.
- [ ] Les positions de lecture sont sur le disque du nœud ; `/var/log` est monté en lecture seule ; une limite de mémoire est posée ; les droits d'Alloy ne lisent pas les Secrets ; la configuration vient de Git.
- [ ] Locataire `plateforme` : journaux des pods de `kube-system` et `journaux`, journal systemd de chaque nœud ; `mediagenda` et `medidoc` : leurs espaces ; aucun journal d'équipe dans `plateforme`.
- [ ] Aucune étiquette indexée hors de la liste fermée ; le nom du pod est filtrable en métadonnée structurée.
- [ ] Le job de CI `alloy-validation` passe sur `main`.

**Vérification** : `lab/bin/check 22 03`

<details><summary>Indice 1</summary>

`discovery.kubernetes` accepte des blocs `selectors` (rôle, sélecteur de champ). Le chart d'Alloy accepte des variables d'environnement supplémentaires (`alloy.extraEnv`) : une variable peut venir de `fieldRef: spec.nodeName`. Dans la configuration, `sys.env("…")` la lit.
</details>

<details><summary>Indice 2</summary>

Une règle de relabel avec plusieurs `source_labels` les concatène avec `separator` : une expression régulière qui saute les valeurs vides au début donne « la première valeur non vide ». `loki.source.file` ajoute d'office une étiquette ; `stage.cri` aussi. `stage.structured_metadata` peut **déplacer** une étiquette en métadonnée structurée, `stage.label_drop` en retirer.
</details>

<details><summary>Indice 3</summary>

Le locataire d'une entrée se change dans un `loki.process` (`stage.tenant`) ; il se lit d'une étiquette. Pour journald, les champs du journal arrivent en étiquettes internes `__journal_…` : relabel-les dans les `relabel_rules` du composant (sinon elles disparaissent). Le niveau a deux formes (`__journal_priority`, `__journal_priority_keyword`).
</details>

**Pour aller plus loin** (facultatif) : compare avec `loki.source.kubernetes`, qui lit les journaux par l'API (sans `hostPath`) : ce que tu gagnes, ce que tu perds (charge du kubelet et de l'API, reprise après coupure).

---

### M22-E04 — LogQL : filtres, analyseurs et métriques de journaux  `LAB` `★★`

> **Ticket PLAT-2304** — *De : Nadia Roussel* — *Copie : Julien Petit*
> Les journaux arrivent, très bien. Mais à 3 h du matin je ne vais pas lire 40 000 lignes. Il me faut les requêtes de base, rangées quelque part, et que tout le monde sache les relancer — dans Grafana, et en ligne de commande depuis `adm01` quand Grafana est en cause. Julien voudrait aussi savoir si on peut tirer des **chiffres** des journaux de MédiAgenda, des durées par route par exemple.

**Objectifs pédagogiques**
- Écrire des requêtes LogQL : sélecteurs, filtres de ligne, analyseurs `json`, `logfmt`, `pattern`, filtres d'étiquettes extraites, `line_format`.
- Tirer des métriques des journaux : `count_over_time`, `rate`, `bytes_over_time`, `unwrap` et `quantile_over_time`, agrégations `sum by`, `topk`.
- Installer et utiliser `logcli` par le code.

**Prérequis** : M22-E03 (journaux des pods et des nœuds dans Loki).
**Durée indicative** : 1 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Journaux d'accès de MédiAgenda | une ligne JSON par requête : `horodatage`, `niveau`, `journal` (`mediagenda.acces`), `message`, `methode`, `chemin`, `route`, `code`, `duree_ms`, `client` (voir `apps/mediagenda/src/mediagenda/journal.py` et `app.py`) |
| Journaux de Loki et d'Alloy | format logfmt (`level=… ts=… caller=… msg=…`) |
| Trafic | `ressources/E04-trafic/trafic.sh` (GET sur la recette : succès, 404, 422 ; 10 min par défaut) |
| logcli | 3.7.9, archive `logcli-linux-amd64.zip` de la publication de Loki, vérifiée par `SHA256SUMS` ; installé par le rôle `outils_k8s` (M14) ; variables `LOKI_ADDR`, `LOKI_ORG_ID` |
| Fichier | `requetes/E04.logql` de `plateforme/observabilite` : une requête par ligne, chacune précédée d'un commentaire `# Qn — …` ; une ligne `# locataire: <nom>` vaut pour les requêtes qui suivent |

**Travail demandé**

1. Ajoute logcli au rôle `outils_k8s` (même version que Loki). Le binaire de l'archive s'appelle `logcli-linux-amd64` : fais en sorte que la commande s'appelle `logcli`. Joue le playbook sur `adm01` ; `logcli --version`.
2. Lance `ressources/E04-trafic/trafic.sh` (10 min) dans un second terminal.
3. Écris les requêtes suivantes, essaie-les dans Explore **et** avec logcli (`logcli query`, `logcli instant-query`), puis range-les dans `requetes/E04.logql` :
   - **Q1** sélecteur : les journaux du conteneur Loki ;
   - **Q2** filtres de ligne : ses lignes `level=info`, sans les lignes d'un composant bavard de ton choix ;
   - **Q3** `logfmt`, filtre sur le niveau extrait, `line_format` qui n'affiche que l'appelant et le message ;
   - **Q4** la même ligne découpée par `pattern` au lieu de `logfmt` ;
   - **Q5** le nombre de lignes par minute et par espace, pour `kube-system` et `journaux` ;
   - **Q6** les cinq applications qui écrivent le plus d'octets sur l'heure ;
   - **Q7** le nombre de lignes de journald par nœud sur l'heure ;
   - **Q8** (`mediagenda`) les requêtes de MédiAgenda en recette dont le code est ≥ 400 ;
   - **Q9** une ligne d'accès lisible : méthode, route, code, durée ;
   - **Q10** les requêtes par seconde, par code HTTP ;
   - **Q11** le 95e centile de la durée par route, sur 5 minutes ;
   - **Q12** la part des requêtes en erreur (≥ 400) sur 10 minutes.
4. Pour Q11 : que se passe-t-il si une ligne n'a pas de champ `duree_ms` numérique ? Comment l'écarter proprement ?
5. Compare Q3 et Q4 : temps d'exécution (statistiques de la réponse de l'API, ou `--stats` de logcli) sur la même heure. Lequel est le moins coûteux, et pourquoi ?
6. Avec logcli : `logcli series` sur le locataire `plateforme` et l'option `--analyze-labels` : combien de flux, quelle étiquette a le plus de valeurs ? Note la réponse : elle servira en M22-E14.
7. Pousse `requetes/E04.logql` sur `main` (MR).

**Critères de réussite**
- [ ] `logcli` 3.7.x est installé sur `adm01` par le rôle `outils_k8s` (commande `logcli`).
- [ ] `requetes/E04.logql` est sur `main` : au moins 10 requêtes, dans au moins deux locataires, qui utilisent filtres de ligne, `json`, `logfmt`, `pattern`, `line_format`, `count_over_time`, `rate`, `unwrap` et `quantile_over_time`.
- [ ] Chaque requête du fichier s'exécute et renvoie des données sur la dernière heure (lance le trafic avant de vérifier).

**Vérification** : `lab/bin/check 22 04`

<details><summary>Indice 1</summary>

Une requête de journaux commence **toujours** par un sélecteur `{…}` avec au moins une égalité qui ne correspond pas à la chaîne vide. Les analyseurs (`| json`, `| logfmt`) transforment les champs de la ligne en étiquettes **de la requête**, filtrables ensuite (`| code >= 400` compare des nombres).
</details>

<details><summary>Indice 2</summary>

`unwrap <champ>` transforme une requête de journaux en série de nombres ; les fonctions `*_over_time` sur des valeurs « déballées » acceptent ensuite un `by (…)`. Une ligne dont le champ n'est pas un nombre produit une erreur d'analyse (étiquette `__error__`) : filtre-la.
</details>

**Pour aller plus loin** (facultatif) : écris Q11 en *requête métrique enregistrée* (règle d'enregistrement du ruler, M22-E08) et compare son coût avec l'histogramme `mediagenda_http_request_duration_seconds` du M21 : quand une métrique tirée des journaux est-elle légitime ?

---

### M22-E05 — Alloy sur les VMs du socle  `LAB` `★★`

> **Ticket PLAT-2305** — *De : Claire Morel* — *Copie : Karim Benali*
> Le cluster est couvert ; le socle, non. Quand GitLab a ralenti la semaine dernière, on a ouvert six sessions SSH pour lire six `journalctl`. Je veux le journal systemd de **toutes** les VMs du socle dans Loki, locataire `plateforme`, avec de quoi les retrouver : le nom de la VM, son rôle, le site. Même modèle que node_exporter au M21 : un rôle Ansible, un binaire vérifié, un service durci, et le flux ouvert proprement sur la bordure.

**Objectifs pédagogiques**
- Écrire un rôle Ansible d'agent : binaire amont vérifié, compte de service, unité systemd durcie, configuration validée avant d'être posée, rechargement à chaud.
- Lire le journal systemd avec les bons droits et les bonnes bornes.
- Ouvrir un flux vers un service du cluster sur la bordure, et le documenter.

**Prérequis** : M22-E02 (10.10.41.62) ; M21-E08 (rôle `node_exporter`, modèle) ; M07 (rôle `pare_feu`, matrice commune des passerelles).
**Durée indicative** : 1 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Hôtes | groupe d'inventaire `socle` (Debian 13) : `gw01`, `gw02`, `adm01`, `dns01`, `dns02`, `ca01`, `git01`, `runner01`, `runner02`, `nbx01`, `s3-01`, `reg01`, `mon01`, `lb01`, `lb02` |
| Binaire | `https://github.com/grafana/alloy/releases/download/v1.21.1/alloy-linux-amd64.zip`, somme dans `SHA256SUMS` de la même publication |
| Rôle | `alloy` dans `plateforme/ansible` ; playbook `playbooks/journaux-vms.yml` |
| Configuration | `/etc/alloy/config.alloy` ; positions sous `/var/lib/alloy` ; interface de l'agent sur `127.0.0.1:12345` seulement |
| Étiquettes | `job="journald"`, `host` (nom court), `role` (groupe d'inventaire `role_*` sans le préfixe), `site="par1"` ; unité et niveau en métadonnées structurées |
| Destination | `http://loki.apps.par1.medisphere.internal:3100/loki/api/v1/push`, locataire `plateforme` |
| Flux | VLAN 20 (INFRA) et VLAN 70 (DMZ) → 10.10.41.62 TCP 3100 (bordure) ; MGMT (`adm01`) déjà ouvert ; trafic propre de `gw01`/`gw02` (adresses du VLAN 40) ; ces trois cas couvrent les 15 VMs du groupe `socle` |

**Travail demandé**

1. Choisis entre le paquet `.deb` du dépôt `apt.grafana.com` et le binaire amont vérifié par empreinte. Écris ton choix et ses raisons dans ton journal (deux arguments pour chaque option).
2. Écris le rôle `alloy` :
   - refus de tout autre système que Debian 13, et d'une VM dont le journal n'est pas persistant ;
   - compte système `alloy`, membre des groupes qui lisent le journal (cherche lesquels dans la documentation du composant) ;
   - binaire dans un dossier versionné, vérifié par la somme publiée, lien `/usr/local/bin/alloy` ;
   - configuration générée par un gabarit et **validée avant d'être posée** ;
   - unité systemd durcie (lecture seule sauf l'état, aucune capacité), rechargement par signal, mémoire bornée ;
   - un contrôle final : l'agent répond prêt sur son interface locale.
3. Écris `playbooks/journaux-vms.yml` (groupe `socle`, quelques VMs à la fois). Essaie-le d'abord sur `mon01` seul.
4. Ouvre le flux sur la bordure (`group_vars/role_routeur/pare_feu.yml`, une passerelle à la fois) et mets à jour `docs/socle/matrice-flux.md`. Pourquoi n'y a-t-il rien à faire pour `adm01` ? Et pour `gw01`/`gw02` eux-mêmes ? (Relis la CNP `loki-entree`.)
5. Joue le playbook sur tout le socle par le pipeline protégé. Second passage : `changed=0`.
6. Dans Grafana : le journal de `git01` ; toutes les erreurs (`niveau` `error` et plus graves) du socle sur la dernière heure, par VM. Sur `dns01`, écris une ligne avec `logger -p user.err "M22-E05 essai"` et retrouve-la.
7. Arrête l'agent de `lb01` cinq minutes, écris une ligne avec `logger`, redémarre-le : la ligne arrive-t-elle ? Avec quel horodatage ?

**Critères de réussite**
- [ ] Le journal systemd de chacune des 15 VMs du socle arrive dans Loki (`job="journald"`, `host`, `role`, `site="par1"`) ; aucune étiquette hors liste ; le niveau `debug` n'est jamais envoyé.
- [ ] Sur les VMs, le service `alloy` est actif, sous le compte `alloy`, en version 1.21 ; son interface n'écoute que sur 127.0.0.1.
- [ ] Le rôle, son gabarit et le playbook sont sur `main` de `plateforme/ansible` ; le second passage donne `changed=0`.
- [ ] Le flux vers 10.10.41.62:3100 est dans la matrice des passerelles et dans `docs/socle/matrice-flux.md`.

**Vérification** : `lab/bin/check 22 05`

<details><summary>Indice 1</summary>

`get_url` accepte `checksum: sha256:<URL du fichier de sommes>` : il y cherche la ligne du fichier téléchargé. Le module `template` accepte `validate:` : la commande reçoit le fichier temporaire en `%s`. Alloy recharge sa configuration sur `SIGHUP` et expose `/-/ready`.
</details>

<details><summary>Indice 2</summary>

Avec `externalTrafficPolicy: Local`, Loki voit l'adresse source réelle. Une passerelle qui envoie elle-même vers 10.10.41.62 sort par son interface du VLAN 40 : avec quelle adresse source ? La CNP doit l'autoriser.
</details>

**Pour aller plus loin** (facultatif) : étends le rôle aux VMs de `ceph-par1` (Rocky Linux 10) : ce qui change (groupes, SELinux, chemin du journal), et le flux supplémentaire depuis le VLAN 30.
