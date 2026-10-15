# Module 17 — Palier 1 : Découverte

Les composants de la plateforme ont été installés par Helm sans que tu aies eu à comprendre Helm : une commande, des valeurs, un nom de release. Ce palier ouvre la boîte. Tu manipules Helm 4 sur un chart public jusqu'à savoir ce qu'il a enregistré et comment revenir en arrière, tu écris le premier chart de MédiAgenda et tu l'installes en dev, tu découvres l'autre manière de décliner des manifestes (Kustomize) en reprenant la recette, puis tu rends le chart robuste : des valeurs validées par un schéma, des gabarits factorisés, des erreurs claires quand il manque quelque chose.

> **Rappels du module** (introduction) : `mediagenda-dev` est le banc d'essai du chart (release Helm `mediagenda`) ; la recette passe sous Kustomize en E04 ; un seul gestionnaire par objet. Les commandes se lancent depuis `adm01` avec ton identité personnelle (`~/.kube/config`). Tout fichier de projet passe par une MR relue (Karim relit les charts, Julien relit ce qui touche MédiAgenda). Les vérifications se lancent depuis `adm01` : `lab/bin/check 17 <XX>`.

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| Chart public d'essai | `podinfo` (Stefan Prodan), OCI `ghcr.io/stefanprodan/charts/podinfo`, versions 6.14.0 et 6.15.0, par le cache Harbor `ghcr` : `oci://registry.par1.medisphere.internal/ghcr/stefanprodan/charts/podinfo` |
| Espace d'essai | `wb-essais` (Pod Security `baseline`), release `podinfo` |
| Chart MédiAgenda | projet GitLab `mediagenda/chart` (groupe `mediagenda`, branche `main` protégée), clone `~/src/mediagenda-chart`, chart dans `charts/mediagenda/` ; version 0.1.0 (E03) puis 0.2.0 (E05) |
| Release de dev | `mediagenda` dans `mediagenda-dev`, nom publié `mediagenda-dev.apps.par1.medisphere.internal` |
| Dépendances provisoires de dev | `ressources/E03-dependances-dev.yaml` : CNPG `mediagenda-db` (1 instance, `ceph-rbd` 2 Gio), Valkey `valkey` sans persistance, politiques réseau `dev-*-provisoire` (remplacées en E06) |
| Dépôt de déploiement | projet GitLab `mediagenda/deploiement`, clone `~/src/mediagenda-deploiement` (E04) |
| Brouillons | `~/m17/eXX/` sur `adm01` |

Durée indicative du palier : 8 à 11 heures.

---

### M17-E01 — Questions : manifestes, gabarits et overlays  `Q` `★★`

> **Ticket PLAT-1801** — *De : Karim Benali*
> Avant qu'on écrive notre premier chart, je veux qu'on parle le même langage. Réponds par écrit, sans chercher à faire long : je veux voir que tu sais **pourquoi** on choisit un outil, pas seulement comment on tape la commande.

**Objectifs pédagogiques**
- Situer Helm, Kustomize et Helmfile les uns par rapport aux autres et par rapport à `kubectl apply`.
- Comprendre ce qu'est une release, une révision, un rendu, un overlay.
- Repérer les changements de Helm 4 qui modifient le comportement d'une commande connue.

**Prérequis** : modules 14 à 16 (tu as déjà lancé des `helm install`).
**Durée indicative** : 45 min.

Réponds dans `~/m17/e01/reponses.md`.

1. MédiAgenda est aujourd'hui déployé par trois copies de manifestes YAML. Cite trois problèmes concrets que cela pose en exploitation et, pour chacun, dis si Helm, Kustomize ou les deux le résolvent.
2. Qu'est-ce qu'une **release** Helm ? Qu'est-ce qu'une **révision** ? Où Helm range-t-il l'historique par défaut, et quelle conséquence cela a-t-il pour un compte qui n'a pas le droit de lire les Secrets d'un espace ?
3. `helm template` et `helm install --dry-run=server` produisent tous deux du YAML sans rien créer. Donne deux différences de comportement, et dis laquelle des deux tu utilises dans un pipeline qui n'a pas accès au cluster.
4. QCM argumenté. En Helm 4, tu lances `helm upgrade --install cert-manager jetstack/cert-manager …` sur une release **créée par Helm 3**. Les objets sont-ils appliqués :
   a) en *client-side apply*, comme avant ;
   b) en *server-side apply*, parce que c'est le défaut de Helm 4 ;
   c) selon `--server-side=auto`, c'est-à-dire comme à la révision précédente ;
   d) ça dépend de la version de kubectl installée.
5. Kustomize n'a pas de gabarits. Donne un besoin de MédiAgenda qu'il couvre **mieux** que Helm, et un qu'il ne sait pas couvrir sans aide.
6. Que fait le suffixe d'empreinte (`mediagenda-parametres-7c9f…`) d'un `configMapGenerator`, et quel problème des ConfigMap « classiques » résout-il ? Quel est son inconvénient ?
7. Pourquoi l'étiquette `app.kubernetes.io/version` ne doit-elle **jamais** figurer dans le sélecteur d'un Deployment, alors qu'on la met sur le pod ?
8. Helmfile, Argo CD (M20) et un script `for` de `helm upgrade` font en apparence la même chose. Qu'apporte Helmfile au script ? Que lui manque-t-il par rapport à Argo CD ?
9. Un chart publié `mediagenda-0.5.0` est réécrit dans le registre avec un contenu différent mais la même étiquette. Comment un consommateur peut-il s'en apercevoir, et comment s'en protéger ?
10. Vrai ou faux, en justifiant : « Avec Helm 4, `--atomic` n'existe plus. »

**Critères de réussite** (auto-évaluation avec le corrigé)
- [ ] Chaque réponse est argumentée en deux à six lignes, avec un exemple MédiSphère quand c'est possible.
- [ ] Les questions 4 et 10 sont justifiées par la documentation ou par `helm upgrade --help`, pas par un souvenir de Helm 3.

<details><summary>Indice 1</summary>

Pour les questions 4 et 10, `helm upgrade --help` répond directement : lis la description des options `--server-side` et `--rollback-on-failure`, et essaie l'ancienne option sur une commande sans effet.
</details>

<details><summary>Indice 2</summary>

Pour la question 9 : à quoi correspond un digest OCI, et qu'est-ce que Harbor sait faire d'une étiquette (règles du projet `medisphere` au M13) ?
</details>

---

### M17-E02 — Helm 4 : installer, inspecter, monter, revenir  `LAB` `★★`

> **Ticket PLAT-1802** — *De : Nadia Roussel*
> À l'astreinte, quand un composant installé par Helm se comporte mal, on ne sait pas répondre à trois questions : qu'est-ce qui a été installé exactement, avec quelles valeurs, et comment revenir à la version d'hier. Entraîne-toi sur un chart qui ne fait de mal à personne, et rédige-moi une fiche de commandes.

**Objectifs pédagogiques**
- Installer un chart depuis un registre OCI (par le cache Harbor), avec un fichier de valeurs.
- Lire ce que Helm a enregistré : valeurs fournies et calculées, manifeste, notes, historique.
- Monter de version, observer les pièges de `--reuse-values`, revenir en arrière, désinstaller en gardant l'historique.
- Constater le *server-side apply* de Helm 4 dans les `managedFields`.

**Prérequis** : M14-E06 (kubectl), M13 (cache Harbor `ghcr`).
**Durée indicative** : 1 h 30.

**Contexte technique**
- Chart : `podinfo` 6.14.0 puis 6.15.0, depuis `oci://registry.par1.medisphere.internal/ghcr/stefanprodan/charts/podinfo` (le cache Harbor relaie `ghcr.io` ; si ton cache refuse les artefacts Helm, utilise `oci://ghcr.io/stefanprodan/charts/podinfo` et note-le dans le journal : `adm01` sort vers Internet).
- Release `podinfo` dans `wb-essais`. Fichier de valeurs : `~/m17/e02/valeurs.yaml` (deux réplicas, un message d'accueil `ui.message`, des requêtes de ressources).
- `podinfo` déclare des tests Helm (`helm test`) : certains utilisent des images publiques, tirées par le cache.

**Travail demandé**
1. Sans rien installer, examine le chart : `helm show chart`, `helm show values` (repère `replicaCount`, `ui.message`, `resources`), `helm show readme`. Note la ligne `Digest:` qu'affiche Helm : à quoi correspond-elle ?
2. Rédige `valeurs.yaml`, puis rends le chart **localement** (`helm template podinfo <CHART> --version 6.14.0 -f valeurs.yaml -n wb-essais`). Compte les objets, repère ceux qui portent l'annotation `helm.sh/hook`.
3. Installe la version 6.14.0 avec ces valeurs dans `wb-essais`, en attendant que les objets soient prêts. Puis :
   - `helm list -n wb-essais`, `helm status podinfo -n wb-essais` ;
   - `helm get values podinfo` et `helm get values podinfo --all` : quelle différence ?
   - `helm get manifest`, `helm get notes`, `helm get hooks` ;
   - `helm test podinfo -n wb-essais --logs`.
4. Regarde comment le Deployment a été écrit : `kubectl -n wb-essais get deploy podinfo -o yaml --show-managed-fields`. Quel gestionnaire (`manager`), quelle opération (`operation`) ? Copie l'extrait dans `~/m17/e02/managed-fields.txt`.
5. Monte en 6.15.0 **sans repasser le fichier de valeurs** et sans autre option. Que deviennent tes valeurs ? Recommence avec `--reuse-values`, puis avec `--reset-then-reuse-values`. Lis l'aide de ces options et explique dans le journal pourquoi `--reuse-values` est dangereux quand le chart ajoute de nouvelles valeurs par défaut.
6. `helm history podinfo -n wb-essais`. Reviens à la première révision (`helm rollback`). Que montre maintenant l'historique (numéro de révision, description) ? Quelle version du chart tourne ?
7. Simule un échec : monte en 6.15.0 avec une valeur qui empêche les pods de démarrer (par exemple une image inexistante par `--set image.tag=…`), avec un délai court et **`--rollback-on-failure`**. Observe l'historique. Essaie la même commande avec `--atomic` et note le message.
8. Désinstalle avec `--keep-history`. Que montrent `helm list -n wb-essais`, `helm list -n wb-essais --uninstalled` et `helm history` ? Enregistre la sortie finale de `helm history podinfo -n wb-essais` dans `~/m17/e02/historique.txt`. Puis supprime définitivement l'historique et vérifie qu'il ne reste rien de la release dans `wb-essais`.
9. Rédige la fiche demandée : `docs/kubernetes/packaging/fiche-helm.md` dans `plateforme/medisphere` (MR) : une ligne par question d'astreinte, la commande, ce qu'elle montre.

**Critères de réussite**
- [ ] `~/m17/e02/historique.txt` montre au moins quatre révisions, dont un retour arrière (« Rollback to 1 ») et l'état final `uninstalled`.
- [ ] `~/m17/e02/managed-fields.txt` montre le gestionnaire `helm` et l'opération `Apply`.
- [ ] Il ne reste dans `wb-essais` aucun objet de la release `podinfo`.
- [ ] La fiche `docs/kubernetes/packaging/fiche-helm.md` est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 17 02`

<details><summary>Indice 1</summary>

`helm show …`, `helm template`, `helm install` et `helm upgrade` acceptent tous une référence `oci://…` et l'option `--version`. Pour attendre que tout soit prêt, lis la description de `--wait` dans `helm install --help` : en Helm 4, elle prend une stratégie.
</details>

<details><summary>Indice 2</summary>

Une montée sans `-f` ni `--set` repart des valeurs **par défaut du nouveau chart**. `--reuse-values` repart des valeurs **de la révision précédente**, y compris des défauts de l'ancien chart qu'elle fige. Compare `helm get values --all` après chacune des trois montées.
</details>

<details><summary>Indice 3</summary>

Un retour arrière ne réécrit pas l'histoire : il crée une **nouvelle** révision. Pour supprimer une release gardée avec `--keep-history`, relis l'aide de `helm uninstall`.
</details>

**Pour aller plus loin** (facultatif) : installe la même release avec `--server-side=false`, puis modifie un champ à la main avec `kubectl edit` et relance `helm upgrade` avec les deux méthodes. Lequel des deux te signale le conflit ? (Le palier 3 y revient en détail.)

---

### M17-E03 — Écrire le chart `mediagenda`  `LAB` `★★`

> **Ticket DEV-1803** — *De : Julien Petit*
> Je veux un vrai paquet pour MédiAgenda, que je puisse installer en dev avec une commande et des valeurs, et qui crée exactement les mêmes objets à chaque fois. Commence simple : l'API, sa configuration, son exposition. On ajoutera la base et le cache au paquet plus tard. Et garde les noms d'aujourd'hui (`mediagenda`), mes scripts et les tableaux de bord de Nadia s'en servent.

**Objectifs pédagogiques**
- Créer un chart `apiVersion: v2` : `Chart.yaml`, `values.yaml`, gabarits, `NOTES.txt`, `.helmignore`.
- Utiliser les objets intégrés (`.Release`, `.Chart`, `.Values`, `.Template`), les fonctions `include`, `toYaml`, `nindent`, `quote`, `default`, et les gabarits nommés.
- Comprendre pourquoi les étiquettes de sélection sont figées et pourquoi une annotation d'empreinte redéploie les pods.
- Installer le chart en dev et vérifier ce qui a été rendu.

**Prérequis** : M17-E02 ; M14-E07/E08 (objets de MédiAgenda), M15 (Gateway, politiques réseau), M16-E18 (CNPG).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Projet GitLab `mediagenda/chart` à créer (groupe `mediagenda`, branche `main` protégée, fusion par MR, Conventional Commits comme au M01), chart dans `charts/mediagenda/`.
- Dépendances provisoires de dev : `ressources/E03-dependances-dev.yaml` (CNPG `mediagenda-db`, Valkey `valkey`, politiques réseau). L'espace `mediagenda-dev` existe (M14-E10, quotas) ; il est en refus réseau par défaut (M15) et en Pod Security `restricted`.
- Ce que l'API attend (voir `apps/mediagenda/README.md`) : port 8000, `/sante` (vivacité), `/pret` (disponibilité : PostgreSQL et Valkey), variables `MEDIAGENDA_DB_URL` (Secret `mediagenda-db-app`, clé `uri`, créé par CNPG), `MEDIAGENDA_VALKEY_URL` (`redis://valkey:6379/0`), `MEDIAGENDA_LOG_LEVEL`, `MEDIAGENDA_LOG_FORMAT`, `MEDIAGENDA_VERSION`, `MEDIAGENDA_FUSEAU`, `MEDIAGENDA_CACHE_TTL`, `MEDIAGENDA_DELAI_ARRET` (20 s, à respecter à l'arrêt).
- Objets attendus du chart 0.1.0 : ServiceAccount, ConfigMap, Deployment, Service, HTTPRoute (vers `gw-par1`, espace `passerelles`, écouteur `https`), NetworkPolicy (sorties DNS, PostgreSQL, Valkey) et CiliumNetworkPolicy (entrée depuis la Gateway, identité `ingress`). Tous nommés `mediagenda` pour la release `mediagenda`.
- Le Secret de tirage `harbor-pull` existe dans l'espace (M14-E19).

**Travail demandé**
1. Applique les dépendances provisoires et attends que la base soit prête :
   ```
   admin@adm01:~$ kubectl apply --server-side -f ~/DevOpsPrivateCloud/modules/17-packaging/ressources/E03-dependances-dev.yaml
   admin@adm01:~$ kubectl -n mediagenda-dev get cluster.postgresql.cnpg.io mediagenda-db -w
   ```
   Vérifie que le Secret `mediagenda-db-app` existe et qu'il a une clé `uri` (sans en afficher la valeur).
2. Crée le projet, clone-le dans `~/src/mediagenda-chart` et lance `helm create charts/mediagenda`. Lis ce que le squelette produit, puis **vide-le** : garde la structure, réécris chaque fichier pour MédiAgenda. Un chart qu'on ne comprend pas ligne par ligne n'entre pas en production.
3. Écris `Chart.yaml` (version 0.1.0, `appVersion` = la version de l'API sans le `v`, `kubeVersion`, mainteneur) et `values.yaml` (image, réplicas, configuration, Secret de la base, URL de Valkey, nom publié, ressources). Aucune valeur secrète.
4. Écris `templates/_helpers.tpl` : nom complet (qui ne répète pas `mediagenda` quand la release s'appelle déjà ainsi, et tient en 63 caractères), étiquettes communes (recommandations `app.kubernetes.io/*`, plus `medisphere.fr/environnement`), étiquettes **de sélection** séparées. Puis les gabarits des objets. Contraintes :
   - l'étiquette d'image vaut `v<appVersion>` sauf si une valeur l'impose ;
   - les pods respectent Pod Security `restricted` (non root, pas d'élévation, capacités retirées, `seccompProfile`), système de fichiers racine en lecture seule avec un `emptyDir` sur `/tmp` ;
   - sondes de démarrage et de vivacité sur `/sante`, de disponibilité sur `/pret` ;
   - le délai de grâce de l'arrêt couvre `MEDIAGENDA_DELAI_ARRET` ;
   - une modification de la ConfigMap redéploie les pods.
5. Écris `NOTES.txt` (adresse publiée, commande de suivi) et `.helmignore`.
6. Contrôle avant d'installer : `helm lint --strict`, `helm template mediagenda charts/mediagenda -n mediagenda-dev`, puis `helm install … --dry-run=server`. Explique dans `~/m17/e03/journal.md` ce que le passage par le serveur a vérifié de plus.
7. Installe la release `mediagenda` dans `mediagenda-dev`, en attendant que tout soit prêt. Vérifie : pods prêts, route acceptée par la Gateway (`kubectl get httproute mediagenda -o yaml`, conditions de `status.parents`), `curl -fsS https://mediagenda-dev.apps.par1.medisphere.internal/sante` affiche la bonne version.
8. Change `config.cacheTtl` par un `helm upgrade --set` et observe le redéploiement. Puis change une valeur qui n'a **pas** d'effet sur un objet (une clé inconnue, par exemple `cacheTTL`) : que se passe-t-il ? Note la leçon : tu y remédieras en E05.
9. MR « feat: chart mediagenda 0.1.0 » relue par Julien, fusionnée.

**Critères de réussite**
- [ ] `helm lint --strict` passe sur `charts/mediagenda` (sur `main` de `mediagenda/chart`).
- [ ] Dans `mediagenda-dev`, le Deployment `mediagenda` appartient à la release `mediagenda` (annotations `meta.helm.sh/*`), porte `helm.sh/chart: mediagenda-0.x.y`, et ses pods sont prêts.
- [ ] Les pods respectent `restricted` et ont des ressources, des sondes `/sante` et `/pret`.
- [ ] La route `mediagenda` est acceptée par `gw-par1` et `https://mediagenda-dev.apps.par1.medisphere.internal/sante` répond 200.

**Vérification** : `lab/bin/check 17 03`

<details><summary>Indice 1</summary>

Le squelette de `helm create` est une bonne référence de gabarits nommés (`<chart>.fullname`, `<chart>.labels`, `<chart>.selectorLabels`) et de l'usage de `include … | nindent N`. Lis-le avant de le vider, pas après.
</details>

<details><summary>Indice 2</summary>

Pour l'empreinte de la ConfigMap, la documentation Helm a une page « Chart Development Tips and Tricks » : cherche « Automatically Roll Deployments ». Pour le délai de grâce, la fonction `add` existe dans les gabarits.
</details>

<details><summary>Indice 3</summary>

Si la route reste refusée, relis `status.parents[].conditions` : `NotAllowedByListeners` renvoie aux `allowedRoutes` de la Gateway (M15 : étiquette d'espace), `NoMatchingListenerHostname` au nom publié, `BackendNotFound` au Service. Si le pod reste non prêt, lis `/pret` depuis le pod lui-même : il dit qui ne répond pas. Pense aux politiques réseau des **deux** côtés.
</details>

**Pour aller plus loin** (facultatif) : compare ton chart avec le résultat de `helm create` : qu'as-tu retiré, et pourquoi (Ingress, HPA, `serviceAccount.annotations`…) ?

---

### M17-E04 — Kustomize : une base et des overlays  `LAB` `★★`

> **Ticket PLAT-1804** — *De : Karim Benali*
> Avant de tout miser sur Helm, regarde l'autre manière de faire. Reprends la recette de MédiAgenda avec Kustomize : une base commune, un overlay par environnement, zéro copie. On garde ce qui marche le mieux. Et ce n'est pas un essai : la recette doit être gérée par ce dépôt à la fin du ticket.

**Objectifs pédagogiques**
- Écrire une base et des overlays : `namespace`, `labels`, `images`, `replicas`, `namePrefix`.
- Corriger une base par un *patch* stratégique et par un *patch* JSON 6902, savoir quand choisir l'un ou l'autre.
- Générer une ConfigMap à suffixe d'empreinte et constater qu'elle redéploie les pods.
- Reprendre des objets existants (créés aux modules 14 à 16) sans casser la recette.

**Prérequis** : M17-E03.
**Durée indicative** : 2 h 30.

**Contexte technique**
- Projet GitLab `mediagenda/deploiement` à créer, clone `~/src/mediagenda-deploiement`. Arborescence : `base/`, `overlays/dev/`, `overlays/recette/`, `overlays/essai/`.
- Base : les manifestes **rendus** du chart 0.1.0 (`helm template mediagenda <chart> > base/mediagenda.yaml`), sans espace de noms. Tu verras en E09 comment brancher le chart lui-même.
- Recette : objets actuels du M16 dans `mediagenda-recette` (Deployment, Service, HTTPRoute, politiques…). La base de données et Valkey **restent** hors de ce dépôt.
- `overlays/dev` est seulement **construit** : `mediagenda-dev` appartient à la release Helm (règle d'un seul gestionnaire). `overlays/essai` sert à l'étape 6 et n'est jamais appliqué.

**Travail demandé**
1. Inventorie la recette telle qu'elle est : `kubectl -n mediagenda-recette get deploy,svc,cm,httproute,netpol,ciliumnetworkpolicy -o wide --show-labels`. Pour le Deployment, note le **sélecteur** (`spec.selector`) et ses gestionnaires de champs. Note tout dans `~/m17/e04/inventaire.md`.
2. Crée le projet et `base/` : le rendu du chart, un `kustomization.yaml` qui le liste. `kustomize build base` doit rendre exactement le rendu.
3. Écris `overlays/recette/` :
   - espace `mediagenda-recette`, étiquette `medisphere.fr/environnement: recette` sur les objets et les pods mais **pas** dans les sélecteurs ;
   - image fixée par le transformateur `images`, deux réplicas par `replicas` ;
   - ressources de la recette par un **patch stratégique** (fichier `ressources.yaml`) ;
   - nom publié `mediagenda-recette.apps.par1.medisphere.internal` par un **patch JSON 6902** ;
   - une ConfigMap générée `mediagenda-parametres` (fichier `parametres.env`, par exemple `MEDIAGENDA_CACHE_TTL=120`) ajoutée **en dernier** aux `envFrom` du conteneur par un patch JSON 6902.
4. Fais de même pour `overlays/dev/` (une réplique, journaux en `DEBUG`), sans l'appliquer. Compare `kustomize build overlays/dev` et `kubectl kustomize overlays/dev` : même sortie ? Même version de Kustomize ?
5. Prépare la reprise de la recette : `kubectl diff --server-side -k overlays/recette`. Compare le sélecteur rendu avec celui de l'étape 1.
   > ⚠️ **Attention** : le sélecteur d'un Deployment est **immuable**. S'il diffère, l'application échouera (`field is immutable`) : il faudra supprimer l'ancien Deployment et le recréer, ce qui coupe la recette une à deux minutes. Préviens Julien avant, garde l'ancien manifeste (`kubectl get deploy mediagenda -o yaml > ~/m17/e04/ancien-deploy.yaml`) pour revenir en arrière, et ne touche **jamais** à la base `mediagenda-db` ni au StatefulSet `valkey`.
   Applique (`kubectl apply --server-side -k overlays/recette`), surveille le déploiement, puis supprime les objets de la recette que la nouvelle version ne gère plus (anciens noms de ConfigMap ou de politiques) après avoir vérifié qu'ils ne servent plus. Note ce que tu as supprimé.
6. Dans `overlays/essai` (espace `wb-essais`, `namePrefix: essai-`, sans route), construis et lis le résultat : quels noms ont changé ? Quelles **références** à ces noms ont été mises à jour (compte de service, ConfigMap, Service de la route…) et lesquelles ne l'ont pas été (le Secret `mediagenda-db-app`, les sélecteurs des politiques réseau) ? Explique pourquoi dans le journal.
7. Change `MEDIAGENDA_CACHE_TTL` dans `parametres.env`, reconstruis : que devient le nom de la ConfigMap ? Applique et observe le redéploiement. Que reste-t-il de l'ancienne ConfigMap dans le cluster ?
8. MR relue par Karim, fusionnée ; la recette est maintenant gérée par `mediagenda/deploiement`.

**Critères de réussite**
- [ ] `mediagenda/deploiement` contient `base/` et les overlays `dev`, `recette`, `essai` ; `kustomize build` réussit pour chacun.
- [ ] Dans `mediagenda-recette`, le Deployment `mediagenda` n'appartient pas à une release Helm, porte `medisphere.fr/environnement: recette`, a deux réplicas prêts et lit une ConfigMap `mediagenda-parametres-<empreinte>` qui existe.
- [ ] La route `mediagenda` de la recette publie `mediagenda-recette.apps.par1.medisphere.internal` et `/sante` y répond 200.
- [ ] La base `mediagenda-db` de la recette n'a pas été recréée (son âge est antérieur au module).

**Vérification** : `lab/bin/check 17 04`

<details><summary>Indice 1</summary>

La documentation de Kustomize (kubectl.docs.kubernetes.io) a une page par champ : `labels` (et ses options `includeSelectors`, `includeTemplates`), `images`, `replicas`, `patches`, `configMapGenerator`. Un patch JSON 6902 se déclare dans `patches` avec une `target` et un `patch` en liste d'opérations.
</details>

<details><summary>Indice 2</summary>

Pour ajouter un élément **à la fin** d'une liste en JSON 6902, le chemin se termine par `/-`. Un patch stratégique, lui, fusionne les listes de conteneurs par le champ `name`.
</details>

<details><summary>Indice 3</summary>

Si `kubectl apply --server-side` signale un conflit sur un champ, lis le nom du gestionnaire qui le possède : c'est la trace de la façon dont l'objet a été créé au M16. Comprends le conflit avant d'utiliser `--force-conflicts`.
</details>

**Pour aller plus loin** (facultatif) : `kubectl apply --prune` avec un *ApplySet* (fonction encore en alpha, variable `KUBECTL_APPLYSET=true`) supprime les objets retirés d'un overlay. Essaie-le sur `wb-essais` seulement.

---

### M17-E05 — Valeurs, schéma de valeurs et helpers  `LAB` `★★`

> **Ticket DEV-1805** — *De : Julien Petit*
> Hier, Lucas a passé `--set replicaCount=deux` et `--set cacheTTL=30` : le premier a cassé le rendu avec un message illisible, le second n'a rien fait du tout et personne ne s'en est aperçu. Et quelqu'un a déployé `latest` en dev. Je veux que le chart refuse ce qui est faux, avec un message qu'on comprend, **avant** de toucher au cluster.

**Objectifs pédagogiques**
- Écrire un `values.schema.json` qui type et borne les valeurs, refuse les clés inconnues et les secrets.
- Utiliser `required`, `fail`, `tpl`, `default`, `ternary`, et des gabarits nommés qui prennent des paramètres (`dict`).
- Comprendre ce que fait `lookup`, ce qu'il renvoie hors du cluster, et pourquoi on ne fonde pas un rendu dessus.
- Faire évoluer le chart sans casser la release existante.

**Prérequis** : M17-E03.
**Durée indicative** : 2 h.

**Contexte technique**
- Chart 0.2.0. Valeur d'environnement : `medisphere.environnement`, sans défaut, parmi `dev`, `recette`, `prod` ; équipe `medisphere.equipe` (`mediagenda`) ; `medisphere.donneesSante` (booléen, étiquette `medisphere.fr/donnees-sante`).
- Règles à faire respecter : registre `registry.par1.medisphere.internal` uniquement (la ValidatingAdmissionPolicy du M14-E18 refuse les autres) ; étiquette `vX.Y.Z` ou vide, jamais `latest` ; digest `sha256:…` accepté et prioritaire ; aucune clé `password` ou `url` dans `database` ; en `prod`, au moins deux réplicas ; variables supplémentaires `config.extraEnv` nommées `MEDIAGENDA_*`.
- Le nom publié devient calculé (`mediagenda-<environnement>.apps.par1.medisphere.internal`) mais reste surchargeable, et la valeur peut contenir un gabarit (`{{ .Release.Namespace }}`).
- La release de dev existe (E03) : la montée en 0.2.0 ne doit pas recréer le Deployment.

**Travail demandé**
1. Lis la page « Schema Files » de la documentation Helm. Note dans le journal (`~/m17/e05/journal.md`) quand le schéma est appliqué (`install`, `upgrade`, `lint`, `template`), à quelles valeurs (celles du chart parent, des dépendances) et comment le contourner (`--skip-schema-validation`) — et pourquoi on ne le contourne pas.
2. Réorganise `values.yaml` (bloc `medisphere`, bloc `image` avec `digest`, bloc `config` avec `extraEnv`) et documente chaque clé par un commentaire.
3. Écris `values.schema.json` : types, énumérations, motifs, bornes, `additionalProperties: false` là où une faute de frappe doit être refusée. Teste chaque règle par un `helm template` qui **doit** échouer, et note le message obtenu.
4. Factorise les gabarits : un gabarit nommé pour la référence d'image (digest prioritaire), un pour l'URL de Valkey avec `required`, un pour le nom publié avec `tpl`, un gabarit `mediagenda.verifications` qui `fail` sur les règles qui portent sur **plusieurs** valeurs (prod et réplicas).
5. `lookup` : dans `NOTES.txt`, avertis si le Secret de la base est introuvable. Rends le chart avec `helm template`, `helm install --dry-run=client` et `--dry-run=server` : quand l'avertissement apparaît-il ? Écris dans le journal pourquoi un gabarit qui **crée** un objet selon le résultat de `lookup` est une mauvaise idée (pense à Argo CD au M20, et au rendu de Kustomize en E09).
6. Monte la release de dev en 0.2.0 avec `-f` d'un fichier `~/m17/e05/dev.yaml` (environnement `dev`), après `helm upgrade --dry-run=server` et une comparaison du rendu avant/après (`helm get manifest` contre `helm template`). Vérifie que les pods ont été renouvelés **par une mise à jour progressive**, pas par une recréation du Deployment.
7. Rejoue les deux erreurs de Lucas : `--set replicaCount=deux` et `--set cacheTTL=30`. Copie les messages dans le journal.
8. MR « feat: schéma de valeurs et helpers (0.2.0) », relue par Julien.

**Critères de réussite**
- [ ] `charts/mediagenda/values.schema.json` est sur `main` ; un rendu avec `image.tag=latest`, `replicaCount=deux`, une clé inconnue, `database.password` ou `medisphere.environnement=preprod` échoue avec un message qui nomme la valeur fautive.
- [ ] La release de dev est en 0.2.0 ou plus ; ses objets portent `medisphere.fr/environnement: dev` et `medisphere.fr/donnees-sante`.
- [ ] Le Deployment de dev n'a pas été recréé (même `metadata.uid` qu'avant la montée, noté dans le journal).

**Vérification** : `lab/bin/check 17 05`

<details><summary>Indice 1</summary>

Helm 4 accepte un schéma au format JSON Schema 2020-12 (`$schema` correspondant). Pour interdire une clé, le mot-clé `not` avec un schéma vide (`{}`) refuse toute valeur. Pour les noms de variables, regarde `propertyNames`.
</details>

<details><summary>Indice 2</summary>

`include` ne prend qu'un argument : pour passer plusieurs paramètres à un gabarit nommé, construis un dictionnaire avec `dict "cle" valeur …`. `tpl` a besoin du contexte en second argument (souvent `.` ou `$`).
</details>

<details><summary>Indice 3</summary>

Note `metadata.uid` du Deployment avant la montée (`kubectl get deploy mediagenda -o jsonpath='{.metadata.uid}'`). S'il change, c'est que Helm a remplacé l'objet : cherche quel champ immuable a changé dans ton rendu (le sélecteur).
</details>

**Pour aller plus loin** (facultatif) : l'outil `helm-docs` génère la documentation des valeurs à partir des commentaires de `values.yaml` ; le plugin `helm-schema` génère un schéma. Compare ce qu'ils produisent avec ton schéma écrit à la main.
