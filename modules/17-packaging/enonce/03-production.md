# Module 17 — Palier 3 : Production

Le chart `mediagenda` existe. Il est testé, publié dans Harbor et signé. Les overlays de `mediagenda/deploiement` livrent la recette depuis ce chart, et Helmfile décrit la plateforme. Tout cela marche quand c'est toi qui le fais, à la main, depuis `adm01`. Claire Morel veut maintenant un paquet **industriel**. Il est publié par un pipeline et jamais depuis un poste. On voit ce qui va changer avant de le changer. Il ne contient aucun secret. Les composants de plateforme se mettent à jour par une MR relue, avec un plan de retour arrière. La décision « Helm, Kustomize ou les deux » est écrite et défendable. Julien Petit, de son côté, veut savoir en combien de temps une nouvelle version de MédiAgenda arrive en recette quand tout est en place.

> ⚠️ **Rappel** : `k8s-par1` porte la recette de MédiAgenda (`mediagenda-recette`) et tous les composants de plateforme des modules 14 à 16. Avant toute action qui modifie une release de plateforme (`helmfile apply`, `helm upgrade`, `helm rollback`), lance `helmfile diff` et lis-le en entier, garde le numéro de la révision courante (`helm history`) et note la commande de retour arrière. **Un composant à la fois.**

**Chemin imposé** (introduction du module) :
- le chart vit dans `mediagenda/chart` (clone `~/src/mediagenda-chart`) ;
- les déploiements par environnement vivent dans `mediagenda/deploiement` (`~/src/mediagenda-deploiement`) ;
- la plateforme vit dans `plateforme/k8s` (`~/src/k8s`, `helmfile.yaml`).

Chaque changement passe par une MR et un pipeline vert. La documentation va dans `docs/kubernetes/packaging/` de `plateforme/medisphere` (`adr/`, `runbooks/`). Aucun secret dans un dépôt, une valeur Helm ou un journal de CI.

**État de départ attendu** (fin du palier 2) :
- chart `mediagenda` en 0.5.x (ou plus), publié et signé dans `oci://registry.par1.medisphere.internal/charts` (M17-E08) ;
- `mediagenda-dev` porte la release Helm `mediagenda`, qui sert de banc d'essai au chart ;
- `mediagenda-recette` est livrée par l'overlay `recette` (M17-E09) ;
- `plateforme/k8s` a un `helmfile.yaml` dont le `diff` est vide (M17-E10).

**Ordre conseillé** : E13 → E14 → E15 → E16 → E17 → E18. Le pipeline (E13) précède la livraison chronométrée (E18), qui suppose une chaîne entièrement automatisée. **Durée totale indicative** : 9 à 12 h.

Les vérifications se lancent **depuis `adm01`** (`lab/bin/check 17 XX`). Le compte `wb-checks` ne lit pas les Secrets, or Helm range ses releases dans des Secrets. Les contrôles qui lisent l'état d'une release (`helm status`, `helm history`, `helm get values`, `helmfile diff`) utilisent donc **ton** kubeconfig (`WB_K8S_ADMIN_KUBECONFIG`, `~/.kube/config` par défaut), en lecture seule. C'est l'exception documentée du module.

---

### M17-E13 — Le pipeline du chart  `LIBRE` `★★★`

> **Ticket PLAT-1813** — *De : Karim Benali* — *Copie : Julien Petit*
> La version 0.5 du chart a été poussée dans Harbor depuis ton poste, avec ta clé de signature chargée en mémoire. Ça a marché, mais je ne veux plus voir ça. À partir de maintenant, un chart publié sort d'un pipeline.
> Il faut qu'il soit testé avant même qu'on le relise. Son numéro de version doit dire si la nouveauté est un correctif ou une rupture. Il doit être signé par la clé de MédiSphère, celle qu'aucun humain ne manipule. Et il doit être impossible de republier une version déjà sortie.

**Objectifs pédagogiques**
- Concevoir le pipeline complet d'un chart Helm : contrôles de MR, version sémantique, paquet, publication OCI, signature par digest.
- Réutiliser les gabarits de CI de la plateforme (M01) et les adapter là où leurs hypothèses ne tiennent plus (pipeline d'étiquette).
- Faire cohabiter des outils qui n'embarquent pas la même version de Helm.

**Prérequis** : M17-E07 (tests, `ct.yaml`), M17-E08 (publication et signature à la main), M01-E24/E25 (gabarits `qualite.yml` et `release.yml`, semantic-release), M12-E20/E21 (`runner02`, exécuteur `docker`), M13-E03 (robots Harbor), M13-E07 (Cosign 3, clé MédiSphère).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Runner : `runner02`, exécuteur `docker`, étiquette `docker`, sans mode privilégié. Les images d'outils sont tirées par les caches de Harbor (`registry.par1.medisphere.internal/dockerhub/…`, `/quay/…`, `/ghcr/…`).
- Images disponibles, aux versions de PLAN §6 :
  - Helm 4.3 : `alpine/helm:4.3.0` sur Docker Hub ;
  - chart-testing 3.15 : `quay.io/helmpack/chart-testing:v3.15.0` ;
  - Cosign 3.1 : l'image outillée `plateforme/outils-supply-chain` de ton M13-E09 (Cosign, racine MédiSphère, clé publique et configuration de signature sans journal), déjà utilisée par la chaîne de livraison des images.
  Ouvre ces images avant de t'en servir. Toutes ne contiennent pas la version de Helm que tu crois.
- Harbor : projet `charts` (OCI). Robot `robot$charts+ci`, à créer s'il n'existe pas encore (droits : pousser et tirer sur `charts`, rien d'autre). Il n'y a ni ChartMuseum ni index `index.yaml` : seulement de l'OCI.
- Le gabarit `templates/qualite.yml` de `plateforme/ci-templates` ne crée **aucun** pipeline sur une étiquette (M01-E24). Le gabarit `release.yml` pose les étiquettes `vX.Y.Z` avec semantic-release sur `runner01`.
- La clé privée Cosign (variable de type fichier `COSIGN_PRIVATE_KEY`) et son mot de passe (`COSIGN_PASSWORD`) sont des variables de CI protégées du groupe (M13-E09). La clé publique est `docs/registre/cosign.pub` de `plateforme/medisphere`, la configuration de signature `docs/registre/signing-config.json` (M13-E07).
- Le lab est souverain : aucune signature ne part vers le journal de transparence public (ADR-0130).

**Contraintes**
- Une MR vers `main` exécute au moins :
  - `helm lint --strict` avec les jeux de valeurs réalistes ;
  - un rendu complet pour chaque environnement ;
  - `ct lint` ;
  - les tests helm-unittest, avec un rapport JUnit affiché dans la MR.
  Un seul échec bloque la fusion.
- Le numéro de version suit SemVer et se déduit des messages de commit (Conventional Commits). Personne ne l'écrit à la main dans une MR.
- Seul un pipeline d'étiquette de version protégée publie. Il construit le paquet, le pousse dans `charts`, le signe **par digest** avec la clé MédiSphère, puis vérifie la signature avec la clé **publique**.
- Une version déjà publiée ne peut pas être republiée. Le pipeline le refuse avant Harbor, avec un message clair.
- Aucun identifiant en clair, ni dans le dépôt ni dans les journaux de jobs. Les variables qui donnent le droit de pousser ou de signer ne sont visibles que des références protégées.
- Les outils sont épinglés à leur version (images, greffons Helm) : le pipeline ne change pas tout seul.
- Le chart déjà publié (0.5.x) reste la base de l'historique : la première version publiée par le pipeline lui succède (0.5.y ou 0.6.0), elle ne repart pas de 1.0.0.

**Critères de réussite**
- [ ] Le projet `mediagenda/chart` a un `.gitlab-ci.yml` et un `.releaserc.json`. Le dernier pipeline de `main` est vert et contient des jobs de lint, de test helm-unittest et de release.
- [ ] Une étiquette `vX.Y.Z` posée par semantic-release a déclenché un pipeline vert, avec des jobs de paquet, de poussée et de signature.
- [ ] `oci://registry.par1.medisphere.internal/charts/mediagenda` contient la version `X.Y.Z`, avec une signature Cosign attachée. `cosign verify` la valide avec `cosign.pub`, sans journal de transparence.
- [ ] Relancer le pipeline de l'étiquette échoue proprement au job de paquet (version déjà publiée), sans rien pousser.
- [ ] Une MR de test qui casse le chart (au choix : une valeur hors schéma, un test unitaire faux) a un pipeline rouge et n'est pas fusionnable. Garde son lien pour la revue.

**Vérification** : `lab/bin/check 17 13`

<details><summary>Indice 1</summary>

Le gabarit de qualité dit « pas de pipeline sur les étiquettes ». Tu publies pourtant à partir d'une étiquette. Lis comment GitLab combine un mot-clé de premier niveau défini à la fois dans un `include` et dans le fichier du projet. Ensuite, demande-toi quels jobs du gabarit doivent ou non tourner sur une étiquette.
</details>

<details><summary>Indice 2</summary>

`helm version` dans l'image de chart-testing te réservera une surprise. Garde Helm 4 pour tout ce qui produit le paquet. Pour `ct lint`, regarde ses options autour des dépendances : le job d'avant peut lui fournir un dossier `charts/` déjà construit. Pour la version, `helm package` sait recevoir le numéro de l'extérieur. Il reste à savoir quel fichier de configuration de chart-testing doit alors changer.
</details>

<details><summary>Indice 3</summary>

`helm push` affiche le digest de ce qu'il vient de pousser. Un job suivant peut le recevoir par un artefact `dotenv`. Une variable de CI de type fichier contient un **chemin**, pas le contenu. En version 3, Cosign utilise par défaut la configuration de signature publique de Sigstore : relis comment le M13-E07 l'en empêche, et ce que la chaîne des images (M13-E09) embarque déjà. La clé publique n'est pas secrète.
</details>

**Pour aller plus loin** (facultatif) : déplace les jobs du chart dans un gabarit `templates/helm-chart.yml` de `plateforme/ci-templates`, réutilisable par les futurs charts (MédiDoc). Ajoute un job `ct install` dans un espace jetable sur `k8s-par1` (il faudra un kubeconfig de CI : c'est le sujet du M19).

---

### M17-E14 — Différences et dérive : `helm diff`, `kubectl diff`, *server-side apply*  `LAB` `★★`

> **Ticket PLAT-1814** — *De : Karim Benali*
> En revue, je ne veux plus lire « ça devrait juste changer la limite mémoire ». Je veux voir le diff de ce qui va **réellement** changer dans le cluster, pour la release Helm de dev comme pour la recette qui passe par Kustomize.
> Et explique-moi un truc : vendredi, Lucas a fait un `kubectl edit` sur le dev pour « tester un truc ». Est-ce que le prochain `helm upgrade` l'écrase, l'ignore ou échoue ?

**Objectifs pédagogiques**
- Prévisualiser un changement Helm (`helm diff`) et un changement Kustomize (`kubectl diff --server-side`) avant de l'appliquer.
- Lire les `managedFields` d'un objet et comprendre qui possède quel champ avec le *server-side apply* (SSA), le mode par défaut des nouvelles releases de Helm 4.
- Créer une dérive volontaire, la détecter et la corriger de trois façons. Savoir laquelle choisir.

**Prérequis** : M17-E02 (Helm 4), M17-E09 (overlay `recette`), M17-E10 (Helmfile, greffon `helm-diff`), M14-E06 (`kubectl diff`, `--dry-run=server`).
**Durée indicative** : 1 h 30.

**Contexte technique**
- Release `mediagenda` dans `mediagenda-dev`, installée par Helm 4. Overlay `recette` de `mediagenda/deploiement` : sa base est le rendu du chart signé (`outils/rendre-base.sh`, M17-E09), appliqué par `kubectl apply --server-side -k overlays/recette`.
- Le greffon `helm-diff` est installé sur `adm01` depuis M17-E10. Sinon : `helm plugin install https://github.com/databus23/helm-diff --verify=false`. Avec Helm 4, un greffon non signé installé depuis Git exige `--verify=false`.
- ⚠️ Tout se passe dans `mediagenda-dev` et en lecture sur la recette. **N'applique rien sur `mediagenda-recette` dans cet exercice.**

**Travail demandé**
1. Prépare une modification du chart sans l'appliquer : la limite mémoire de l'API passe à 448 Mi. Affiche ce que ferait `helm upgrade` sur le dev avec `helm diff upgrade`. Compare avec `helm template` suivi d'un `diff` sur `helm get manifest`. Qu'est-ce que `helm diff` voit et que ce second calcul ne voit pas ?
2. Lis les options de `helm diff upgrade` : `--server-side`, `--three-way-merge`, `--context`, `--show-secrets`, `--normalize-manifests` (consulte `helm diff upgrade --help` sur ta version). Choisis celles qui produisent un diff fidèle pour une release Helm 4 en SSA, et note pourquoi.
3. Affiche les `managedFields` du Deployment `mediagenda` du dev (`kubectl get … --show-managed-fields -o yaml`). Combien de gestionnaires (*managers*) ? Lesquels, quelle opération (`Apply` ou `Update`), sur quels champs ? Fais de même en recette et compare les gestionnaires.
4. Crée une dérive : sur le dev, `kubectl edit` du Deployment, `MEDIAGENDA_LOG_LEVEL` passe à `DEBUG`. Relis les `managedFields`. Puis relance `helm diff upgrade` **sans** changer de valeurs : la dérive apparaît-elle ? Et avec `--three-way-merge` ?
5. Tente le `helm upgrade` de l'étape 1. Note le message exact, le statut de la release (`helm status`) et la nouvelle révision (`helm history`). Corrige la dérive de trois façons, l'une après l'autre (en recréant la dérive entre deux) :
   - en rendant le champ à Helm (`--force-conflicts`) ;
   - en défaisant la modification manuelle ;
   - en retirant au gestionnaire manuel la propriété du champ.
   Pour chacune, relis les `managedFields`.
6. Côté Kustomize, prévisualise l'application de l'overlay `recette` avec `kubectl diff --server-side -k`, exactement comme en M17-E09. Quel est le nom du gestionnaire de champs utilisé quand on n'en donne pas ? Le diff doit être vide. Recommence avec `--field-manager=essai` : qu'est-ce qui change, et pourquoi faut-il **toujours** appliquer un même dépôt sous le même nom ?
7. Écris dans `docs/kubernetes/packaging/derive.md` une demi-page : comment voir une dérive (Helm, Kustomize), qui gagne en SSA, et la conduite à tenir (on corrige le code, jamais le cluster). Ajoute le diff Helm et le diff Kustomize à la description des MR du chart et du déploiement (gabarit de MR).

**Critères de réussite**
- [ ] La release `mediagenda` du dev est `deployed`, sa dernière révision contient la limite 448 Mi, et elle a été installée et montée en SSA (`apply_method` de la release).
- [ ] Sur le Deployment du dev, aucun champ de la spécification n'appartient à un gestionnaire `kubectl-edit`, `kubectl-client-side-apply` ou `kubectl-patch`. La valeur de `MEDIAGENDA_LOG_LEVEL` est celle du chart.
- [ ] `kubectl diff --server-side` de l'overlay `recette` est vide.
- [ ] `docs/kubernetes/packaging/derive.md` est publié et le gabarit de MR des deux projets demande les diffs.

**Vérification** : `lab/bin/check 17 14`

<details><summary>Indice 1</summary>

`helm diff upgrade` compare par défaut le **manifeste stocké dans la release** au nouveau rendu, pas l'état du cluster. Cherche l'option qui fait entrer l'état réel dans la comparaison. Pour Kustomize, il n'y a pas de « release » : `kubectl diff` interroge toujours le serveur.
</details>

<details><summary>Indice 2</summary>

En SSA, une modification par `kubectl edit` est une opération `Update` qui **prend la propriété** des champs modifiés. Helm, au prochain `Apply` d'une autre valeur sur ces champs, se heurte à un *conflict*. `--force-conflicts` existe dans Helm 4 comme dans `kubectl apply --server-side`. Pour retirer une propriété sans toucher à la valeur, relis la documentation *Server-Side Apply* : un gestionnaire peut aussi abandonner un champ.
</details>

<details><summary>Indice 3</summary>

Le nom de gestionnaire (`--field-manager`) est une **identité**. Deux applications du même manifeste sous deux noms différents font deux propriétaires. Si l'un retire ensuite un champ de son manifeste, le champ reste, parce que l'autre le possède encore.
</details>

**Pour aller plus loin** (facultatif) : lis [Server-Side Apply](https://kubernetes.io/docs/reference/using-api/server-side-apply/) jusqu'à la section sur le transfert de propriété entre `kubectl apply` côté client et côté serveur. Essaie `kubectl apply --server-side` sur un objet créé en côté client et observe `kubectl.kubernetes.io/last-applied-configuration`.

---

### M17-E15 — Des paquets sans secrets  `LAB` `★★`

> **Ticket SEC-1815** — *De : Sophie Laurent*
> Audit interne : je veux la preuve qu'aucun mot de passe, aucune clé, aucun jeton ne se trouve dans un chart, un overlay, un fichier de valeurs, **ni dans une release Helm**. Lucas m'a dit qu'« avec Helm, les valeurs sont chiffrées dans le cluster ». Je voudrais que tu me montres ce qu'il en est vraiment.
> Et je veux savoir, pour chaque Secret que consomment MédiAgenda et la plateforme, qui le crée, d'où il vient et comment on le change.

**Objectifs pédagogiques**
- Savoir où finissent les valeurs d'une release (Secret `sh.helm.release.v1.*`) et qui peut les lire.
- Auditer les releases, les charts et les overlays à la recherche de secrets, et corriger ce qui doit l'être.
- Appliquer le motif « Secret créé hors du paquet » (`existingSecret`, `secretKeyRef`) et refuser par la CI tout chart qui rendrait un Secret.
- Situer les solutions de fond (SOPS, External Secrets Operator, Vault), traitées au M25.

**Prérequis** : M17-E05 (`required`, `lookup`), M17-E13 (pipeline du chart), M14-E11 (RBAC), M16-E18 (Secret `mediagenda-db-app` de CloudNativePG), M01 (Gitleaks).
**Durée indicative** : 1 h 30.

**Contexte technique** : MédiAgenda reçoit `MEDIAGENDA_DB_URL` du Secret `<cluster>-app` que crée CloudNativePG (clé `uri`). Le Secret de tirage `harbor-pull` est posé par le script du M14. Les clés TSIG (M15) et les identifiants S3 (M16) viennent de Vault Ansible par des scripts. L'espace `wb-essais` sert aux démonstrations.

**Travail demandé**
1. **Démonstration.** Dans `wb-essais`, installe le chart `mediagenda` en release `fuite`, et passe une valeur inventée `--set config.extraEnv.MEDIAGENDA_JETON=jeton-de-demo-1234`. Retrouve cette valeur de trois façons :
   - `helm get values` ;
   - le Secret de la release, décodé par toi ;
   - le manifeste de la ConfigMap.
   Qui, dans le RBAC de `k8s-par1`, peut lire ce Secret ? Que vaut l'affirmation de Lucas ? Supprime ensuite la release **et** vérifie qu'il ne reste aucun Secret `sh.helm.release.v1.fuite.*`.
2. **Audit des releases.** Pour toutes les releases du cluster (`helm list -A`), extrais les valeurs fournies (`helm get values -o json`) et cherche les clés et valeurs qui ressemblent à un secret. Écris un petit script `outils/audit-valeurs-helm.sh` dans `plateforme/k8s` : il sort en erreur s'il trouve quelque chose, sans jamais afficher la valeur trouvée. Corrige chaque trouvaille en faisant porter le secret par un Secret existant que référence le chart du composant (consulte ses valeurs : `existingSecret`, `secretName`…), créé hors de Helmfile par le même chemin que les autres secrets (Vault Ansible → script).
3. **Audit des dépôts.** Lance Gitleaks sur l'historique complet de `mediagenda/chart`, `mediagenda/deploiement` et `plateforme/k8s`. Vérifie que le rendu de chaque overlay (`kubectl kustomize overlays/<env>`) ne produit **aucun** objet `kind: Secret`. S'il y en a un (un `secretGenerator` par exemple), sors-le du dépôt.
4. **Garde-fou dans la CI du chart.** Ajoute au pipeline de `mediagenda/chart` un job qui rend le chart avec chaque jeu de valeurs et échoue si un objet `Secret` apparaît dans le rendu. Ajoute aussi un test helm-unittest qui vérifie que l'URL de base de données de l'API vient d'une référence de Secret et jamais d'une valeur littérale.
5. **Registre des secrets de la plateforme.** Rédige `docs/kubernetes/packaging/secrets.md`. Pour chaque Secret consommé par MédiAgenda et par les composants du `helmfile.yaml`, une ligne : espace de noms, nom, créé par (opérateur, script, humain), source de vérité (Vault Ansible `lab`/`critique`, opérateur), consommateurs, procédure de rotation. Des **emplacements**, jamais de valeurs. Termine par une section « Ce qui change au M25 » : SOPS, External Secrets Operator, Vault.
6. Réponds à Sophie en quelques lignes : ce que Helm protège, ce qu'il ne protège pas, et ce que tu as mis en place.

**Critères de réussite**
- [ ] Plus aucune release `fuite` ni Secret `sh.helm.release.v1.fuite.*` dans `wb-essais`.
- [ ] `outils/audit-valeurs-helm.sh` est sur `main` de `plateforme/k8s`, et aucune release du cluster n'a de valeur qui ressemble à un secret (mot de passe, jeton, clé TSIG, contenu d'identifiants).
- [ ] Dans les Deployments de MédiAgenda (dev, recette), `MEDIAGENDA_DB_URL` vient d'une `secretKeyRef`. Aucune variable ne contient d'URL PostgreSQL littérale.
- [ ] Le pipeline de `main` de `mediagenda/chart` contient le job « sans Secret » et il est vert. `docs/kubernetes/packaging/secrets.md` est publié.

**Vérification** : `lab/bin/check 17 15`

<details><summary>Indice 1</summary>

Les valeurs d'une release sont stockées dans le champ `release` du Secret, encodé deux fois en base64 et compressé par gzip. C'est un **encodage**, pas un chiffrement. Le chiffrement au repos d'etcd (M14-E28) protège le disque, pas l'API : quiconque a `get secrets` dans l'espace lit tout.
</details>

<details><summary>Indice 2</summary>

Pour l'audit, `helm list -A -o json` donne les couples nom/espace, et `helm get values <nom> -n <espace> -o json` les valeurs fournies (pas les défauts du chart). `jq` sait parcourir toutes les clés d'un document (`paths`, `getpath`, `leaf_paths`). Un audit qui affiche le secret trouvé est lui-même une fuite (journal de CI, historique du terminal).
</details>

<details><summary>Indice 3</summary>

Pour le garde-fou, `helm template` puis un filtre `yq` sur `.kind` suffit. Pense aussi au rendu des sous-charts : le chart Valkey sait-il créer un Secret selon ses valeurs ?
</details>

**Pour aller plus loin** (facultatif) : la fonction `lookup` permet de conserver un mot de passe généré au premier `install`. Rends le chart deux fois avec `helm template` (ou avec `outils/rendre-base.sh` de `mediagenda/deploiement`) : que devient ce mot de passe à chaque rendu ? C'est l'une des raisons pour lesquelles MédiSphère interdit aux charts de générer des secrets.

---

### M17-E16 — Monter un composant de plateforme par Helmfile  `LAB` `★★★`

> **Ticket CHG-1816** — *De : Claire Morel* — *Copie : Nadia Roussel*
> Changement planifié : cert-manager passe à la dernière version de correctif de sa mineure. C'est le premier changement de plateforme qui passe par Helmfile. Je veux que ce soit le modèle des suivants : diff relu en MR, ordre des dépendances explicite, fenêtre annoncée à Nadia, retour arrière **répété** avant le jour J, preuve que rien n'a bougé ailleurs.
> Si cert-manager est déjà à jour, prends le composant qui a du retard. Le but est la procédure.

**Objectifs pédagogiques**
- Préparer une montée de version de chart : notes de version, valeurs modifiées, CRD, compatibilité.
- Décrire l'ordre des releases avec `needs` et en comprendre l'effet sur `apply` et `destroy`.
- Appliquer par Helmfile avec retour automatique sur échec (`--rollback-on-failure` de Helm 4), puis répéter un vrai retour arrière et en mesurer les effets de bord.

**Prérequis** : M17-E10 (`helmfile.yaml` et `releases/*.yaml.gotmpl` de `plateforme/k8s`, environnement `par1`, adoption des releases), M17-E14 (`helm diff`), M15-E13/E14 (cert-manager, ClusterIssuer `step-ca-acme`, certificat `apps-joker`), M14-E30 (ADR-0141, politique de versions).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Les versions publiées d'un chart se listent avec `helm search repo --versions` (dépôt HTTP) ou `helm show chart oci://…` (OCI).
- cert-manager publie ses notes de version par version. Il ne prend **pas** en charge le retour à une version antérieure (consulte la page *Upgrading* de sa documentation). Ses CRD sont installées par le chart (`crds.enabled`, conservées par `crds.keep`, M15).
- metrics-server (M14-E20) est sans état : c'est le composant sur lequel on **répète** un retour arrière sans risque.
- Helmfile 1.8 avec Helm 4. Les clés `helmDefaults` et les options de release qui touchent au retour arrière sont dans la documentation de Helmfile (*configuration*) : `atomic`, `rollbackOnFailure`, `wait`, `timeout`, `historyMax`… Toutes ne veulent pas dire la même chose avec Helm 4.
- ⚠️ cert-manager porte les certificats de la Gateway `gw-par1` et des défis ACME. Annonce la fenêtre à Nadia (ticket), vérifie avant de commencer que le certificat joker n'arrive pas à échéance dans les 48 h, et garde une session sur les journaux du contrôleur.

**Travail demandé**
1. **Inventaire.** Pour chaque release du `helmfile.yaml`, note la version installée et la dernière version publiée de la même mineure (tableau dans la MR). Choisis la cible : cert-manager, sinon le composant le plus en retard. Lis les notes de version entre les deux : changements de valeurs, de CRD, de comportement. Compare `helm show values` des deux versions.
2. **Ordre.** Le `ClusterIssuer` `step-ca-acme` (M15) est appliqué à part, après cert-manager, par une commande que l'on peut oublier ou lancer dans le mauvais ordre. Fais-en une release d'un petit chart local `emetteurs` (dossier `charts/emetteurs/` de `plateforme/k8s`), déclarée dans le même fichier de releases que cert-manager. L'objet existant doit être **repris sans être recréé** (cherche l'option de Helmfile et de Helm 4 qui le permet, et retire-la une fois la reprise faite). Exprime la dépendance par `needs`. Vérifie avec `helmfile -e par1 list` et `helmfile -e par1 build` que l'ordre est celui que tu crois. Que fait `needs` à un `helmfile -e par1 -l composant=cert-manager apply` ? Et à `destroy` ?
3. **Retour sur échec.** Configure Helmfile pour que l'application de la cible attende la disponibilité des objets et revienne seule à la révision précédente en cas d'échec. Avec Helm 4, vérifie dans la sortie de `helmfile --debug apply` quel drapeau Helm est réellement passé. Garde aussi l'historique utile (pas plus de 10 révisions).
4. **Répétition sur metrics-server.**
   - Monte metrics-server d'une version par Helmfile : MR, diff, application.
   - Reviens en arrière de deux façons : `helm rollback` direct, puis retour de l'épinglage dans `helmfile.yaml` suivi d'un `helmfile apply`.
   - Après le `helm rollback`, que dit `helmfile diff` ? Laquelle des deux méthodes laisse le dépôt et le cluster d'accord ?
   - Chronomètre les deux retours.
5. **Le changement.** MR sur `plateforme/k8s` avec : le diff complet (`helmfile diff`, secrets masqués), les notes de version résumées, le plan de retour arrière propre au composant (pour cert-manager, ce n'est **pas** un `helm rollback`), et la fenêtre annoncée. Après revue, applique **la seule cible** (`-l`). Vérifie ensuite :
   - pods prêts, webhook joignable ;
   - un `Certificate` d'essai dans `wb-essais` émis par `step-ca-acme`, puis supprimé ;
   - `apps-joker` toujours `Ready` ;
   - `helmfile diff` vide sur **toute** la plateforme.
6. Mets à jour le runbook de montée de version de plateforme dans `docs/kubernetes/packaging/runbooks/` (ou crée `RB-172-montee-composant.md`) à partir de ce que tu as vécu.

**Critères de réussite**
- [ ] La release cible est `deployed` à la version épinglée sur `main` de `plateforme/k8s` (`releases/*.yaml.gotmpl`). `helmfile -e par1 diff` est vide sur toute la plateforme.
- [ ] Le `ClusterIssuer` `step-ca-acme` appartient à la release `emetteurs` (même objet, pas recréé : `Ready`), qui déclare `needs` vers cert-manager. Le retour sur échec est une option de Helmfile, pas une option tapée à la main.
- [ ] cert-manager est prêt : déploiements disponibles, `apps-joker` `Ready`. Aucun `Certificate` d'essai ne reste dans `wb-essais`.
- [ ] La MR contient le tableau d'inventaire, le diff, le plan de retour arrière et les deux chronométrages de la répétition. RB-172 (ou le runbook existant) est à jour.

**Vérification** : `lab/bin/check 17 16`

<details><summary>Indice 1</summary>

Helm 4 a renommé l'option de retour sur échec, et l'ancienne reste acceptée avec un avertissement. Helmfile 1.8 connaît les deux noms dans `helmDefaults`. Relis la documentation de configuration pour savoir lequel il traduit en quoi, et lequel est refusé s'il est combiné à l'autre.
</details>

<details><summary>Indice 2</summary>

Un `helm rollback` crée une nouvelle révision dont le contenu est celui d'une ancienne. Le dépôt, lui, n'a pas bougé. Lance `helmfile diff` juste après : ce qui apparaît, c'est ce que le prochain `apply`, celui de n'importe qui, remettra en place.
</details>

<details><summary>Indice 3</summary>

Pour cert-manager, « revenir en arrière » après une montée de correctif se prépare par une sauvegarde de ses ressources. Consulte la page *Backup and restore* de sa documentation : `Issuer`, `ClusterIssuer`, `Certificate`, et les Secrets qu'ils produisent. La parade habituelle est de corriger vers l'avant (*roll forward*).
</details>

**Pour aller plus loin** (facultatif) : ajoute à `plateforme/k8s` un job de pipeline planifié qui lance `helmfile diff --detailed-exitcode` chaque nuit et ouvre un ticket s'il n'est pas vide (détection de dérive). Il faudra un accès au cluster depuis la CI : prépare-le en lisant ce que prévoit le M19.

---

### M17-E17 — ADR : Helm, Kustomize ou les deux  `RED` `★★`

> **Ticket PLAT-1817** — *De : Claire Morel* — *Copie : Karim Benali, Julien Petit*
> On a maintenant les trois : un chart, des overlays Kustomize qui partent du rendu de ce chart, et Helmfile pour la plateforme. Julien voudrait « tout en Helm, c'est plus simple ». Karim voudrait « tout en Kustomize, au moins on voit ce qu'on applique ». Et dans deux modules, Argo CD va consommer tout ça.
> Écris l'ADR-0170. Je veux une règle que l'équipe MédiDoc pourra appliquer seule le mois prochain.

**Objectifs pédagogiques**
- Comparer Helm, Kustomize et leur combinaison sur des critères d'exploitation réels (pas sur des goûts).
- Décider ce que chaque outil fait chez MédiSphère : applications, plateforme, configuration par environnement, consommation par GitOps.
- Écrire une décision avec ses conséquences négatives et ce qu'elle impose aux modules suivants.

**Prérequis** : M17-E02 à M17-E16 (au minimum E04, E09, E10, E12, E14, E15).
**Durée indicative** : 2 h.

**Travail demandé**
Rédige `docs/kubernetes/packaging/adr/ADR-0170-helm-kustomize.md` (gabarit MADR de M00-E33, deux pages au plus), par MR sur `plateforme/medisphere`. L'ADR doit au minimum :
1. Poser le **contexte** : ce qui existe (chart `mediagenda` publié et signé, `mediagenda/deploiement`, `helmfile.yaml` de la plateforme), ce qui arrive (Argo CD au M20, MédiDoc et MédiNotif, multi-équipes au F2), les contraintes (HDS : traçabilité de ce qui tourne ; souveraineté : tout depuis Harbor ; Helm 4 et le SSA).
2. Lister des **critères** pondérés. Au minimum :
   - lisibilité de ce qui est appliqué ;
   - paramétrage par environnement ;
   - cycle de vie : hooks, ordre, retour arrière, désinstallation ;
   - état stocké dans le cluster et ce qu'il coûte (E15, E23) ;
   - dérive et SSA (E14) ;
   - tests et publication (E07, E13) ;
   - consommation par Argo CD (qui sait rendre un chart et appliquer Kustomize, mais n'exécute pas les hooks comme Helm) ;
   - charts tiers de la plateforme ;
   - compétences de l'équipe.
3. Comparer au moins quatre **options** : tout Helm (releases par environnement), tout Kustomize (manifestes rendus et versionnés), Helm pour empaqueter et Kustomize pour livrer (le montage actuel), Helmfile partout. Chaque évaluation s'appuie sur un fait constaté dans un exercice.
4. **Trancher** par type de logiciel (application maison, composant de plateforme tiers, objets de configuration de la plateforme). Dire où vit la configuration d'environnement, et ce que deviennent les **hooks** du chart quand Kustomize le gonfle.
5. Lister les **conséquences** négatives et les actions, chacune rattachée à un module ou datée. Exemples :
   - migrations par conteneur d'initialisation plutôt que par hook ;
   - double maintenance des valeurs ;
   - le dev, banc d'essai Helm, à faire rentrer dans la règle au mini-projet ;
   - gabarit de CI des charts ;
   - Argo CD au M20 ;
   - secrets au M25.

**Critères de réussite**
- [ ] L'ADR suit le gabarit, tient en deux pages, et contient un tableau critères × options pondéré.
- [ ] Au moins quatre options réellement évaluées. Chaque évaluation cite un exercice ou une documentation.
- [ ] La décision est formulée comme une règle applicable par une autre équipe (« une application maison… ; un composant tiers… »), avec le sort des hooks et de la configuration d'environnement.
- [ ] Les conséquences négatives sont écrites, avec des actions rattachées à un module.

Auto-évaluation : grille fournie dans le corrigé.

<details><summary>Indice 1</summary>

Demande-toi ce que chaque outil **sait** et ce qu'il **retient**. Helm retient (une release, un historique, des hooks exécutés dans l'ordre) ; Kustomize ne retient rien et produit seulement du YAML. Ce qui retient l'état est utile pour revenir en arrière, et gênant pour GitOps, qui veut que le dépôt soit la seule vérité.
</details>

<details><summary>Indice 2</summary>

Pour Argo CD, lis dès maintenant la page *Helm* de sa documentation : comment il traite un chart (il le rend, il ne l'installe pas), et ce qu'il fait des annotations `helm.sh/hook`. Ta décision ne doit pas être défaite deux modules plus tard.
</details>

**Pour aller plus loin** (facultatif) : compare avec Timoni (CUE) ou les charts « v3 » expérimentaux de Helm 4 (`HELM_EXPERIMENTAL_CHART_V3`) : qu'est-ce qui changerait dans ta décision, et à quelle condition la reverrais-tu ?

---

### M17-E18 — Livrer une nouvelle version de MédiAgenda en temps limité  `CHRONO` `★★★`

> **Ticket DEV-1818** — *De : Julien Petit* — *Copie : Claire Morel*
> MédiAgenda 1.1.0 est prête : on enregistre maintenant par quel canal le rendez-vous a été pris, et l'API exige de savoir dans quel environnement elle tourne. Il y a une migration de schéma.
> Claire veut savoir combien de temps il faut entre « le code est fusionné » et « la recette tourne la nouvelle version », quand on fait tout proprement. Chrono en main.

**Règles de l'exercice**
- Conditions d'examen. Tu n'as ni corrigé ni autres notes que **tes** runbooks, ton code et la documentation officielle.
- Durée cible : **60 minutes** entre l'ouverture du dossier (T0) et la recette vérifiée (T4).
- Tout passe par le code, les MR et les pipelines :
  - `mediagenda/api` pour l'image ;
  - `mediagenda/chart` pour le chart ;
  - `mediagenda/deploiement` pour la recette ;
  - la release Helm du dev.
  Aucun `kubectl edit`, `kubectl set` ni `helm upgrade --set` ne doit rester en place à T4. Un geste manuel se note dans la feuille de temps, avec sa raison : c'est un défaut de ta chaîne.
- Ordre imposé : dev, puis recette. La **production ne bouge pas**.

**Prérequis** : M17-E13 (pipeline du chart), M17-E09 (overlays), M17-E12 (migrations), M13-E09 (pipeline de livraison de l'image), M16-E18 (base de recette).
**Durée** : 60 minutes chronométrées + 20 minutes de retour d'expérience.

**Dossier** : [`ressources/E18-dossier-chrono.md`](../ressources/E18-dossier-chrono.md) (le besoin, les exigences, la feuille de temps) et [`ressources/E18-mediagenda-1.1.0.patch`](../ressources/E18-mediagenda-1.1.0.patch) (le code de Julien). Lis-les à T0, pas avant.

**Critères de réussite**
- [ ] Toutes les exigences du dossier sont satisfaites à T4 (vérification ci-dessous).
- [ ] La feuille de temps est remplie (T0 à T4), avec les gestes manuels éventuels et leur raison. Le temps total est inférieur à 60 minutes. Sinon, améliore ta chaîne et refais l'exercice avec une version 1.1.1 fictive (un `fix:`).
- [ ] Le retour d'expérience (une demi-page) est rédigé, et ton runbook de livraison mis à jour par MR.

**Vérification** : `lab/bin/check 17 18` (à lancer à T4).

**Pour aller plus loin** (facultatif) : mesure séparément le temps des pipelines et ton temps à toi. Lequel des deux réduirais-tu en premier, et avec quel outil des modules 19 et 20 ?
