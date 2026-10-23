# Module 29 — Palier 1 : Découverte

Première semaine du chantier « tests et résilience ». Karim veut savoir d'où tu pars, puis il te confie le bas de la pyramide : des manifestes validés avec les schémas **réels** des CRD du cluster, des règles écrites et testées sur les plans OpenTofu, des tests qui interrogent l'état réel des VMs du socle. Julien, lui, attend son premier chiffre : combien de réservations par seconde la recette de MédiAgenda encaisse-t-elle avant de sortir de son SLO ? À la fin du palier, `kubeconform`, `opa`, `conftest`, Testinfra et `k6` tournent depuis `adm01`, chacun avec au moins un cas où il passe **au rouge** pour une bonne raison.

Prérequis : l'état d'entrée de [`00-introduction.md`](00-introduction.md) (`plateforme-dev-v1`, bilan de capacité fait). Lis ses **règles du module** avant de commencer, en particulier : jamais la production, données factices seulement.

---

### M29-E01 — Test de positionnement : tests et résilience  `Q` `★★`

> **Ticket PLAT-3001** — *De : Karim Benali*
> Avant de te laisser écrire les tests de toute la plateforme, le questionnaire habituel. Il couvre la validation statique, les tests d'infrastructure, la charge et le chaos. Réponds par écrit, sans moteur de recherche ni IA, puis corrige-toi avec la grille : les notions où tu perds des points sont celles à lire de près dans le module.

**Objectifs pédagogiques**
- Évaluer tes acquis sur les tests d'infrastructure, la mesure de performance et l'ingénierie du chaos.
- Repérer les notions à retravailler avant les exercices qui les mobilisent.

**Prérequis** : aucun (à faire à froid).
**Durée indicative** : 1 h 15 (+ 30 min d'auto-correction).

**Travail demandé**

Réponds aux 12 questions. Pour les QCM, justifie ton choix en une ou deux phrases.

1. Range les tests suivants dans la pyramide (statique, unitaire, intégration réelle, bout en bout/charge, résilience) et dis, pour chacun, s'il doit tourner à chaque MR, chaque nuit ou à la demande : (a) `kubeconform` sur les manifestes rendus de `plateforme/gitops` ; (b) un test Terratest qui crée une VM ; (c) `opa test` sur les règles des plans ; (d) Testinfra sur les 15 VMs du socle ; (e) un test k6 de 20 minutes à 50 requêtes/s ; (f) `conftest` sur le plan d'une MR de `plateforme/infra` ; (g) une expérience qui tue un pod de l'API en recette. Quel critère, en plus du coût, te fait remonter ou descendre un test ?

2. *(QCM)* La CI lance `kubeconform -strict -summary -ignore-missing-schemas rendu/` sur 40 manifestes dont une `Application` Argo CD qui contient `spec.syncPolicy.automatd: {}` (faute de frappe). Aucun schéma de CRD n'est fourni. Que se passe-t-il ?
   - A. kubeconform signale une erreur sur l'`Application` et sort avec le code 1.
   - B. L'`Application` est comptée « skipped », le code de sortie est 0.
   - C. kubeconform émet un avertissement et sort avec le code 1 à cause de `-strict`.
   - D. kubeconform valide l'`Application` avec un schéma générique d'objet Kubernetes et trouve la faute.

3. En M16, les schémas des CRD ont été produits par `jq '.spec.versions[].schema.openAPIV3Schema'` sur les CRD du cluster. Un `kubeconform -strict` avec ces schémas laisse passer un champ inconnu dans un objet `Cluster` de CloudNativePG, alors qu'il refuse un champ inconnu dans un `Deployment`. Explique pourquoi, et ce qu'il faut changer aux schémas pour que `-strict` serve à quelque chose sur les ressources personnalisées.

4. Qu'est-ce qui a changé dans le langage Rego avec OPA 1.0 ? Que se passe-t-il quand OPA 1.21 charge un fichier écrit `deny[msg] { … }` ? Donne deux façons de migrer un dépôt existant, et laquelle tu choisis pour une équipe qui a 40 fichiers.

5. Le job de plan de `plateforme/infra` produit `plan.json` (`tofu show -json plan.tfplan`) pour que conftest l'analyse. Un collègue propose de le publier comme artefact du job « pour pouvoir le relire ». Qu'y a-t-il dans ce fichier qui pose problème ? Où doit tourner conftest, et que fait-on du fichier ensuite ?

6. Compare Testinfra, Goss et Molecule : que teste chacun, contre quelles machines, écrit dans quel langage, lancé comment ? Dans quel cas Testinfra sur le **parc réel** apporte-t-il quelque chose que les tests Molecule du M04 n'apportent pas ? Quel risque prend-on en le lançant sur le parc réel, et comment le limite-t-on ?

7. Un test Terratest crée une VM avec `terraform.InitAndApply` puis vérifie qu'on s'y connecte en SSH. Le job CI est coupé au bout de 30 minutes par son délai (`timeout`) pendant la vérification SSH. Qu'advient-il de la VM ? Qu'aurait-il fallu prévoir, dans le test et dans le job, pour qu'elle soit détruite quoi qu'il arrive ? Que se passe-t-il si `go test` est lancé sans `-timeout` ?

8. *(QCM)* Un test k6 utilise l'exécuteur `constant-vus` avec 50 VUs sans pause. Le serveur répond en 100 ms au début, puis en 2 s après une dégradation. Quel débit k6 envoie-t-il après la dégradation ?
   - A. Toujours 500 requêtes/s : le nombre de VUs est constant.
   - B. Environ 25 requêtes/s.
   - C. Environ 250 requêtes/s.
   - D. k6 crée des VUs supplémentaires pour maintenir le débit.

   Complète : quel exécuteur aurait représenté une campagne de vaccination, et quelle métrique de k6 dit qu'il n'a pas tenu le débit demandé ?

9. Sur 10 000 requêtes, MédiAgenda en a servi 9 300 en moins de 100 ms, 300 entre 100 et 250 ms, 300 entre 250 ms et 1 s, et 100 en plus de 1 s. (a) La moyenne peut-elle être sous 250 ms ? (b) Le SLO « 95 % des requêtes en moins de 250 ms » est-il tenu ? (c) Le p99 est-il sous 1 s ? (d) Trois pods rapportent chacun leur p95 (120, 140 et 900 ms) : pourquoi la moyenne de ces trois p95 ne dit-elle rien du p95 du service, et comment le calculer correctement avec Prometheus ?

10. *(QCM)* Un script k6 contient des `check()` mais aucun `thresholds`. Pendant le test, 30 % des checks échouent. Que renvoie `k6 run` ?
    - A. Le code 99 (seuils franchis).
    - B. Le code 0 : les checks ne font pas échouer un test.
    - C. Le code 1 dès que plus de 5 % des checks échouent.
    - D. Le code 107 (erreur de script).

11. Formule une expérience de chaos complète pour la question « MédiAgenda survit-il à la perte d'un pod de son API pendant les heures d'ouverture ? » : état stable (avec la requête qui le mesure), hypothèse falsifiable, injection, rayon d'action, conditions d'arrêt, ce que tu conclus si l'hypothèse tombe. Cite quatre garde-fous qui ne dépendent pas de la bonne volonté de la personne qui lance l'expérience.

12. Chaos Mesh installe un `chaos-controller-manager` (Deployment) et un `chaos-daemon` (DaemonSet). Lequel injecte réellement une latence réseau dans le pod visé, et comment y parvient-il ? Pourquoi a-t-il besoin d'être privilégié, et qu'est-ce que cela impose côté Pod Security Admission et côté Falco ? Que se passe-t-il si une expérience vise un espace **non** annoté alors que le filtre d'espaces est actif ?

**Critères de réussite**
- [ ] Les 12 réponses sont rédigées et justifiées.
- [ ] Auto-correction faite avec le corrigé ; les notions faibles sont notées dans ton journal avec les exercices du module qui les traitent.

**Vérification** : auto-évaluation avec le corrigé (pas de check automatique).

<details><summary>Indice 1</summary>

Pour les questions de performance (8, 9), fais le calcul : un VU fait une requête à la fois ; un percentile se lit sur la distribution, pas sur des moyennes.
</details>

<details><summary>Indice 2</summary>

Pour les questions 2 et 3, demande-toi ce que kubeconform fait quand il **ne trouve pas** de schéma, et ce qu'un schéma JSON accepte quand il ne dit rien des propriétés supplémentaires.
</details>

**Pour aller plus loin** (facultatif) : lis *Principles of Chaos Engineering* (<https://principlesofchaos.org/>) et la page « Open and closed models » de la documentation de k6.

---

### M29-E02 — kubeconform : valider les manifestes avec leurs CRD  `LAB` `★★`

> **Ticket PLAT-3002** — *De : Karim Benali*
> La semaine dernière, une `Application` Argo CD avec `automatd` à la place d'`automated` est passée en revue, en CI, et en production : la synchronisation automatique ne s'est jamais faite, on l'a vu trois jours après. La CI de `plateforme/gitops` ne valide que les objets standard ; tout ce qui vient d'une CRD est ignoré. Je veux que **tout** ce que nous appliquons soit validé contre le schéma que le cluster sert vraiment, y compris ce qui sort des charts, et qu'un champ inconnu soit une erreur. Les schémas doivent être produits une fois, publiés, et consommés par toutes les CI.

**Objectifs pédagogiques**
- Valider des manifestes avec kubeconform 0.8 : schémas des objets standard, schémas des CRD, mode strict, versions de Kubernetes.
- Comprendre pourquoi un schéma brut de CRD ne détecte pas un champ inconnu, et le corriger avec le convertisseur officiel de kubeconform.
- Publier un artefact partagé (paquet générique GitLab) versionné et vérifiable.
- Valider ce qu'Argo CD appliquera vraiment : le rendu des charts avec nos valeurs.

**Prérequis** : M16-E23 (première génération de schémas), M20 (Applications, charts recopiés dans Harbor), M19 (paquets GitLab).
**Durée indicative** : 2 h.

**Contexte technique**
- kubeconform cherche un schéma pour chaque objet dans les emplacements donnés par `-schema-location`, dans l'ordre ; `default` désigne les schémas des objets standard (projet `kubernetes-json-schema`, téléchargés et mis en cache). Pour les CRD, le gabarit attendu par ce workbook est `<dossier>/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json` (groupe d'API, *kind* en minuscules, version).
- Le convertisseur officiel est `scripts/openapi2jsonschema.py` du dépôt `yannh/kubeconform`, à l'étiquette **v0.8.0**. Il se recopie dans `plateforme/k8s/outils/` et s'utilise **vérifié par empreinte** (calcule-la toi-même sur le fichier de l'étiquette et note-la dans le script).
- Le paquet générique s'appelle **`schemas-crd`**, dans le projet **`plateforme/k8s`**, version **`AAAA.MM.JJ`** (suffixe `-N` si plusieurs le même jour). Fichiers : `schemas-crd.tar.gz` et `schemas-crd.tar.gz.sha256`. L'archive contient, **à sa racine**, un dossier par groupe d'API avec ses schémas, un `api-versions.txt` (sortie de `kubectl api-versions` : les charts s'en servent via `.Capabilities.APIVersions`) et un `LISEZMOI` (provenance : cluster, date, version du convertisseur).
- La version de Kubernetes du cluster est **1.36.5** (`-kubernetes-version` de kubeconform, `--kube-version` de `helm template`).
- Les charts des Applications de `plateforme/gitops/plateforme/` viennent du miroir Harbor (`registry.par1.medisphere.internal/charts`, robot de lecture `robot$charts+lecture` du M17) et leurs valeurs de `plateforme/gitops/valeurs/<composant>/` (références `$values`).

**Travail demandé**
1. Installe kubeconform 0.8.x sur `adm01` depuis les publications GitHub du projet, **après vérification** de l'archive avec le fichier de sommes publié.
2. Rends les manifestes de `plateforme/k8s` (`kustomize build` de chaque dossier) et passe-les à `kubeconform -strict -summary` avec les seuls schémas `default`. Note ce qui arrive aux objets des CRD. Recommence avec `-ignore-missing-schemas` et note le code de sortie. Écris en deux phrases pourquoi cette option sera interdite dans nos CI.
3. Écris `plateforme/k8s/outils/schemas-crd.sh` (il remplace celui du M16), avec trois sous-commandes :
   - `generer [DOSSIER]` : lit **toutes** les CRD servies par `k8s-par1` (lecture seule), les convertit avec le convertisseur officiel vérifié, range les schémas selon le gabarit ci-dessus, écrit `api-versions.txt` et `LISEZMOI` ;
   - `publier VERSION [DOSSIER]` : fabrique une archive reproductible, son empreinte, et les dépose dans le paquet générique `schemas-crd` (API des paquets génériques, jeton d'écriture de `~/.config/workbook/`) ; refuse une version mal formée ;
   - `verifier [DOSSIER]` : rejoue les manifestes du dépôt contre les schémas.
4. Prouve l'intérêt du convertisseur : prends un objet personnalisé réel (un `Cluster` CNPG de recette, par exemple), ajoute-lui un champ mal orthographié, et valide-le avec `-strict` d'abord contre le schéma brut (`openAPIV3Schema` extrait au `jq`, comme au M16), puis contre le schéma converti. Garde les deux sorties pour ta documentation.
5. Publie une première version du paquet et vérifie, depuis un autre dossier, que tu sais la télécharger et en contrôler l'empreinte.
6. Dans `plateforme/gitops`, écris `outils/rendre-charts.sh` : pour chaque Application de `plateforme/` dont une source est un chart du miroir Harbor, rends le chart (`helm template`) avec la version et les fichiers de valeurs que l'Application déclare, la version de Kubernetes du cluster et les API de `api-versions.txt`. Une Application dont un fichier de valeurs ne peut pas être trouvé est **signalée** et fait échouer le script à la fin, jamais ignorée en silence. Valide le rendu avec kubeconform et le paquet.
7. Retire `-ignore-missing-schemas` de toute CI qui valide des manifestes : `plateforme/k8s`, `plateforme/gitops`, `mediagenda/deploiement`, `medinotif/deploiement`. Si l'une d'elles échoue ensuite faute de schéma, c'est exactement ce qu'il fallait voir : télécharge le paquet dans le job (E10 généralisera).
8. Documente dans `plateforme/medisphere`, `docs/qualite/schemas-crd.md` : d'où viennent les schémas, comment les régénérer et **quand** (toute installation ou montée de version d'un composant qui apporte des CRD), comment les consommer, pourquoi pas `-ignore-missing-schemas`.

**Critères de réussite**
- [ ] `kubeconform -v` sur `adm01` répond 0.8.x.
- [ ] Le paquet générique `schemas-crd` de `plateforme/k8s` existe, en version `AAAA.MM.JJ`, avec une empreinte qui correspond à l'archive.
- [ ] L'archive contient `api-versions.txt` et un schéma pour **chaque** CRD servie par le cluster ; les schémas sont stricts (`additionalProperties: false`).
- [ ] Une `Application` avec un champ inconnu est refusée par `kubeconform -strict` avec les schémas du paquet.
- [ ] `outils/schemas-crd.sh` (k8s) et `outils/rendre-charts.sh` (gitops) sont sur `main` ; aucune des quatre CI citées n'utilise `-ignore-missing-schemas`.
- [ ] `docs/qualite/schemas-crd.md` existe sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 29 02`

> Le contrôle « un schéma pour chaque CRD servie » restera vrai seulement si tu régénères le paquet après chaque nouvelle CRD : il repassera au rouge après E09 (Chaos Mesh) jusqu'à la publication d'une nouvelle version. C'est voulu.

<details><summary>Indice 1</summary>

Le convertisseur lit des fichiers de CRD (YAML ou JSON) et écrit un fichier par version de chaque CRD dans le **dossier courant**, nommé selon la variable d'environnement `FILENAME_FORMAT`. Lis son en-tête avant de l'appeler en boucle.
</details>

<details><summary>Indice 2</summary>

Pour qu'une archive soit reproductible (même contenu, même empreinte), fixe l'ordre des fichiers, leur date et leur propriétaire au moment de `tar`, et compresse sans horodatage. Le téléversement d'un paquet générique se fait par `PUT` sur `/api/v4/projects/<id>/packages/generic/<paquet>/<version>/<fichier>`.
</details>

<details><summary>Indice 3</summary>

Dans une `Application` multi-sources, la source qui porte `ref: values` désigne le dépôt des valeurs, et `$values/...` dans `helm.valueFiles` de la source du chart pointe dedans. Commence par lister les Applications avec `yq` et regarde la forme de `spec.sources`.
</details>

**Pour aller plus loin** (facultatif) : planifie un pipeline hebdomadaire de `plateforme/k8s` qui compare les CRD du cluster à la dernière version du paquet et ouvre une MR quand elles diffèrent.

---

### M29-E03 — conftest et Rego v1 : des règles sur les plans OpenTofu  `LAB` `★★`

> **Ticket PLAT-3003** — *De : Karim Benali* — *Copie : Sophie Laurent*
> Mardi, une MR de `plateforme/infra` a changé l'image de `dns02`. Le plan disait `-/+ destroy and then create replacement` en ligne 212 sur 240. Deux relecteurs l'ont approuvée ; c'est le job d'apply, en voyant la durée, qui nous a mis la puce à l'oreille. Je veux que la CI **lise le plan à notre place** : VMID dans la plage de l'état, pool, étiquettes, et surtout aucune destruction d'une VM du socle sans une décision explicite sur la MR. Les règles en Rego v1, avec leurs tests : une règle sans test, je ne la relis pas.

**Objectifs pédagogiques**
- Lire le format JSON d'un plan OpenTofu (`resource_changes`, `change.actions`, `before`, `after`).
- Écrire des règles Rego v1 (OPA 1.21 : `if`, `contains`, `in`, `every`) et les tester avec `opa test`.
- Lancer conftest 0.71 sur un plan avec des données externes (plages, contexte de la MR).
- Concevoir une règle qui échoue **fermée** : une donnée absente est un refus, pas un silence.

**Prérequis** : M05 (OpenTofu, états de `plateforme/infra`), M26 (projet `plateforme/politiques`), PLAN §4.6 (plages de VMID) et §4.8 (étiquettes).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Les règles des plans vivent dans **`plateforme/politiques/rego/tofu/`**, toutes dans le paquet **`tofu`** ; les données dans **`rego/donnees/`** ; des plans d'exemple (anonymisés, réduits) dans `rego/exemples/`.
- Commande que le job de plan lancera (E10), depuis la racine de `plateforme/politiques` :
  `conftest test --namespace tofu -p rego/tofu --data rego/donnees --data contexte.json plan.json`
- `contexte.json` est écrit par le job : `{"contexte": {"etat": "<dossier de la configuration>", "etiquettes_mr": ["…"]}}`. `etat` vaut `socle`, `envs/k8s`, `envs/m20`, `envs/m29`… (le dossier dans `plateforme/infra`) ; `etiquettes_mr` est la liste des étiquettes de la MR (variable `CI_MERGE_REQUEST_LABELS`).
- `rego/donnees/plages-vmid.yaml` a pour clé de premier niveau `plages_vmid` : un état → une liste de plages `[min, max]`. Pour un état `envs/mNN` sans entrée, la plage est celle du module : de 2000 + 10 × NN à 2000 + 10 × NN + 9.
- Les VMs sont des ressources `proxmox_virtual_environment_vm` (fournisseur `bpg/proxmox`) ; les champs utiles de `change.after` sont `vm_id`, `pool_id`, `tags`. Le pool du lab est **`lab`**.
- Étiquettes (PLAN §4.8) : une VM de l'état `socle` porte `socle` et au moins un `role-<rôle>` ; une VM de `envs/mNN` porte `env-mNN` ; une VM d'un autre environnement porte au moins un `env-…` ; aucune VM hors du socle ne porte `socle`.
- L'étiquette de MR qui autorise la destruction ou le remplacement d'une VM du socle est **`destruction-autorisee`** (posée par Karim ou toi après relecture).

> ⚠️ Un plan JSON contient les valeurs **en clair**, y compris celles marquées sensibles (jetons, mots de passe cloud-init). Ne le versionne jamais et ne le publie jamais ; les exemples de `rego/exemples/` sont construits à la main ou expurgés.

**Travail demandé**
1. Installe OPA 1.21.x et conftest 0.71.x sur `adm01`, binaires vérifiés par empreinte.
2. Produis le plan JSON d'une petite modification de `plateforme/infra` (par exemple une étiquette ajoutée à une VM d'environnement) dans un dossier temporaire et explore-le avec `jq` : où sont les actions, que contiennent `before` et `after`, à quoi ressemble un remplacement ? Supprime le fichier ensuite.
3. Écris les règles (`deny`) dans `rego/tofu/` : contexte présent ; état connu ; VMID numérique et dans la plage de l'état ; pool `lab` (un pool **absent** est un écart) ; étiquettes selon l'état ; destruction ou remplacement d'une VM du socle refusé sans l'étiquette de MR. Ajoute un avertissement (`warn`) quand une destruction du socle est autorisée, pour qu'elle reste visible dans le journal du job. Chaque message nomme la ressource (`address`) et la valeur fautive.
4. Écris `rego/donnees/plages-vmid.yaml` pour **tous** les états de ton dépôt `plateforme/infra` (regarde ses dossiers).
5. Écris les tests (`*_test.rego`, paquet distinct) : pour **chaque** règle, au moins un cas accepté et un cas refusé, y compris un remplacement dans les deux ordres d'actions possibles. `opa test` doit tout passer.
6. Ajoute à `rego/exemples/` trois plans réduits (un conforme, un avec plusieurs défauts, un remplacement d'une VM du socle) et lance la commande conftest du contexte technique sur chacun, avec les bons contextes.
7. Vérifie que ton code passe `opa check --strict` et `opa fmt` (sans différence), puis fusionne sur `main` de `plateforme/politiques`.

**Critères de réussite**
- [ ] `opa version` et `conftest --version` sur `adm01` répondent 1.21.x et 0.71.x.
- [ ] `rego/tofu/` contient les règles (paquet `tofu`, Rego v1) et au moins 8 tests ; `opa test rego/tofu rego/donnees` passe.
- [ ] Avec la commande du contexte technique : un plan conforme (VMID 2291, pool `lab`, `env-m29`, état `envs/m29`) est **accepté** ; un VMID 5001, un pool absent, une étiquette `env-m28` dans `envs/m29` sont **refusés**.
- [ ] Le remplacement d'une VM du socle avec `create_before_destroy` est refusé sans l'étiquette `destruction-autorisee`, accepté avec.
- [ ] Un plan analysé sans `contexte.json` est refusé.

**Vérification** : `lab/bin/check 29 03`

<details><summary>Indice 1</summary>

Un remplacement n'a pas toujours la même forme : l'ordre des actions dépend du cycle de vie de la ressource. Ne teste pas une position dans la liste ; teste l'appartenance.
</details>

<details><summary>Indice 2</summary>

`input.x.y != "lab"` est **indéfini** (donc la règle ne se déclenche pas) quand `y` n'existe pas. Cherche dans la documentation la fonction qui lit un champ avec une valeur par défaut.
</details>

<details><summary>Indice 3</summary>

Dans un test, `with input as …` et `with data.contexte as …` remplacent l'entrée et les données pour une seule expression. Un test qui vérifie seulement qu'un plan correct **passe** reste vert si la règle ne se déclenche jamais.
</details>

**Pour aller plus loin** (facultatif) : ajoute une règle qui exige une approbation (étiquette de MR) pour toute modification de `pve_*` ou du réseau SDN, et lis la section *Policy Performance* de la documentation d'OPA.

---

### M29-E04 — Testinfra : tester les rôles Ansible sur les VMs  `LAB` `★★`

> **Ticket PLAT-3004** — *De : Sophie Laurent* — *Copie : Karim Benali*
> En M26 un rôle a désactivé `auditd` sur trois VMs et rien ne l'a vu pendant dix jours : Molecule teste les rôles sur des instances jetables, OpenSCAP passe une fois par semaine. Je veux un test qui interroge le **parc réel** et me dise, chaque nuit, si le durcissement, les exportateurs de supervision et l'heure sont toujours ce que les rôles promettent. Les exceptions du registre ne doivent pas être redites dans les tests : le registre fait foi.

**Objectifs pédagogiques**
- Écrire des tests pytest-testinfra 10.2 qui contrôlent l'état réel (services, sockets, paramètres du noyau, commandes), pas seulement des fichiers.
- Utiliser l'inventaire Ansible existant comme source des hôtes (connecteur `ansible://`).
- Organiser les tests : fixtures partagées, marqueurs, exceptions lues dans le registre, rapport JUnit.
- Lancer les tests depuis la CI sur `runner01`, sans privilège supplémentaire.

**Prérequis** : M04 (rôles, inventaire, `uv`), M21 (`node_exporter` 1.12 en TLS, Alloy), M26 (rôle `durcissement`, registre `exceptions.json`), M04-E30/M25-E11 (clé SSH de la CI).
**Durée indicative** : 2 h.

**Contexte technique**
- Les tests vivent dans **`plateforme/ansible/tests/infra/`** : `conftest.py` (fixtures partagées), `test_durcissement.py`, `test_node_exporter.py`, `test_alloy.py`, `test_chrony.py` (client de temps du rôle `base`) ; un **marqueur pytest** par fichier, du même nom (`durcissement`, `node_exporter`, `alloy`, `chrony`), déclaré, avec `--strict-markers`.
- Dépendances dans le groupe `tests` du `pyproject.toml` de `plateforme/ansible` (`pytest-testinfra` 10.2.x, `pytest-xdist` pour le parallélisme), verrouillées dans `uv.lock`.
- Le connecteur `ansible://<groupe>` lit l'inventaire du dépôt (NetBox, `ansible.cfg`) et ses variables de connexion (`ansible_host`, `ansible_user`, `ansible_become`). Il ne lit **pas** `ANSIBLE_PRIVATE_KEY_FILE` : la clé se passe par une option de pytest.
- Le registre des exceptions du M26 est sur chaque hôte durci : `/etc/medisphere/conformite/exceptions.json` (lisible par root).
- Rapport JUnit : `rapports/junit/testinfra.xml`, publié par le job.

**Travail demandé**
1. Ajoute les dépendances au groupe `tests` et verrouille-les. Vérifie que `pytest --collect-only` trouve tes tests sans contacter aucun hôte.
2. Écris `conftest.py` : fixtures pour les variables Ansible de l'hôte, ses groupes, sa famille de système, et le registre des exceptions (une règle en exception fait **sauter** le test correspondant, avec la raison).
3. Écris au moins **4 tests par fichier** de rôle. Chaque fichier contrôle au moins un état réel (service actif, socket à l'écoute, valeur de `sysctl`, sortie d'une commande) en plus des fichiers. Exemples de ce qu'il faut couvrir : paramètres du noyau et modules interdits, `sshd -T`, `auditd` actif, `/tmp` monté avec ses options, minuterie AIDE ; `node_exporter` à la bonne version, à l'écoute en TLS, qui **refuse** le HTTP clair ; Alloy actif à la bonne version ; chrony synchronisé sur les sources prévues avec NTS.
4. Lance la suite depuis `adm01` sur tout le socle, puis sur un seul hôte et un seul marqueur. Corrige ce qui doit l'être (tes tests, ou le parc : un test rouge est peut-être une vraie dérive ; dans ce cas, ouvre un ticket plutôt que d'assouplir le test).
5. Ajoute un job à la CI de `plateforme/ansible` qui lance Testinfra sur `runner01` (modèle `.socle` existant, clé de la CI), **chaque nuit** (pipeline planifié) et à la demande sur `main`, avec le rapport JUnit. Le job sera repris en E10 par le composant `validation`.
6. Crée le pipeline planifié et fais réussir au moins une exécution.

**Critères de réussite**
- [ ] Les cinq fichiers sont sur `main` ; chaque fichier de test a au moins 4 tests, un marqueur, et un contrôle d'état réel.
- [ ] `conftest.py` lit `exceptions.json` ; les marqueurs sont déclarés avec `--strict-markers`.
- [ ] `pyproject.toml` déclare pytest-testinfra 10.2 ; `uv.lock` verrouille pytest-testinfra 10.2.x et pytest-xdist.
- [ ] La CI lance Testinfra sur les hôtes de l'inventaire avec la clé de la CI ; un job a réussi dans les 7 derniers jours.

**Vérification** : `lab/bin/check 29 04`

<details><summary>Indice 1</summary>

`host.ansible.get_variables()` donne les variables d'inventaire de l'hôte courant, groupes compris. `host.run(...)` renvoie un objet avec `rc`, `stdout`, `stderr` ; `host.check_output(...)` échoue si la commande échoue.
</details>

<details><summary>Indice 2</summary>

Un test qui contrôle `node_exporter` « depuis » l'hôte (`curl localhost`) ne voit pas le pare-feu ni le certificat que voit Prometheus. Pour un contrôle vu de l'extérieur, la fixture `host` n'est pas obligatoire : un test peut s'exécuter sur le contrôleur (`adm01` ou le runner) et joindre l'hôte par le réseau. Marque ces tests à part : ils dépendent des flux.
</details>

<details><summary>Indice 3</summary>

Le paramètre de pytest à passer pour la clé SSH s'appelle `--ssh-identity-file`. Dans le job, la clé est déjà préparée par le modèle `.socle` (regarde quelle variable il exporte).
</details>

**Pour aller plus loin** (facultatif) : fais produire au job un résumé « hôte × rôle » (vert, rouge, sauté) lisible dans la MR, et compare-le au rapport hebdomadaire d'OpenSCAP du M26.

---

### M29-E05 — k6 : premier test de charge de MédiAgenda  `LAB` `★★`

> **Ticket PLAT-3005** — *De : Julien Petit* — *Copie : Nadia Roussel*
> Pour la campagne de vaccination, on attend jusqu'à 3 réservations par seconde en pointe et une vingtaine de lectures de créneaux par seconde. Je voudrais un premier chiffre : la recette tient-elle ça dans le SLO (250 ms pour 95 % des requêtes) ? Contraintes de mon équipe : la recette sert à nos tests d'intégration, donc des données factices qu'on reconnaît, rien qui reste en base après, et vous nous prévenez avant. La production, vous n'y touchez pas, même « juste 30 secondes ».

**Objectifs pédagogiques**
- Écrire un premier script k6 1.8 : requêtes, `check`, `thresholds`, étiquettes de nommage.
- Comparer un modèle fermé (VUs) et un modèle ouvert (taux d'arrivée) sur le même parcours.
- Rendre un test **sûr** par construction : cible autorisée, données factices, nettoyage.
- Lire le résumé de fin de test et le relier aux métriques de MédiAgenda dans Prometheus.

**Prérequis** : M21 (SLO de MédiAgenda, Prometheus), M28-E02 (HPA de MédiAgenda en recette), API de MédiAgenda (`apps/mediagenda/README.md`).
**Durée indicative** : 1 h 30.

**Contexte technique**
- MédiAgenda de recette : `https://mediagenda-recette.apps.par1.medisphere.internal` ; `/pret` (disponibilité) ; `GET /api/v1/creneaux?date=AAAA-MM-JJ&praticien=<id>` ; `POST /api/v1/rendez-vous` (JSON : `patient`, `praticien`, `debut` **avec fuseau**, `duree_minutes`, `motif`) → 201 et un `id`, 409 si le créneau est pris, 422 si la requête est invalide ; `DELETE /api/v1/rendez-vous/{id}` → 204 ; `GET /api/v1/rendez-vous` (liste).
- Projet **`plateforme/resilience`** (à créer dans le groupe `plateforme`, clone `~/src/resilience`) : `charge/` pour les scripts k6, `chaos/` (E09), `journees-de-jeu/`, `outils/`. Les scripts se lancent depuis la racine du clone.
- Données factices imposées : praticiens **`dr-k6-<n>`** (aucun praticien réel n'a ce préfixe), patients « Patient Charge … », motif qui mentionne le test, rendez-vous à **J+60** au moins.
- Convention de nommage des requêtes (étiquette `name`), commune à tous les scripts : `MÉTHODE /chemin`, avec `{id}` à la place d'un identifiant (`DELETE /api/v1/rendez-vous/{id}`).
- Métriques de MédiAgenda dans Prometheus : `mediagenda_http_requests_total` et `mediagenda_http_request_duration_seconds_bucket` (étiquettes `methode`, `route`, `code`, `namespace`).

**Travail demandé**
1. Installe k6 1.8.x sur `adm01` (archive des publications GitHub, empreinte vérifiée). Crée le projet `plateforme/resilience` avec un `README.md` qui dit à quoi il sert et les règles du module.
2. Écris `charge/lib/commun.js`, importé par tous les scripts de charge : l'URL cible (recette par défaut, modifiable par `-e BASE_URL=…`), le **garde-fou** qui refuse de charger le script si la cible n'est pas dans une liste d'autorisation (recette, dev, et `http://127.0.0.1:<port>` pour un essai local), et des fonctions qui fabriquent des données factices et des créneaux **uniques** par VU et par itération.
3. Écris `charge/premier-test.js` : lire les créneaux, réserver, relire, **annuler**. Nomme les requêtes pour que les URL avec identifiant ne produisent pas une série par rendez-vous. Ajoute les seuils : p95 sous 250 ms, moins de 0,5 % d'échecs, tous les checks réussis.
4. Permets deux modèles de charge dans le même script (choisis par une variable) : 5 VUs pendant 2 minutes (fermé) et 3 itérations par seconde pendant 2 minutes (ouvert).
5. Vérifie le garde-fou **avant** toute charge : `k6 inspect` du script avec la recette, puis avec l'URL de production (`https://mediagenda.apps.par1.medisphere.internal`) — le second doit échouer avant toute requête.
6. Annonce le test dans ton journal (`docs/qualite/journal/`), lance les deux modèles sur la recette, puis compare : débit obtenu, p95, nombre de VUs. Pendant le test, regarde dans Prometheus la latence vue par MédiAgenda et le nombre de réplicas.
7. Vérifie qu'aucun rendez-vous factice n'est resté en base.

**Critères de réussite**
- [ ] `k6 version` sur `adm01` répond v1.8.x ; `charge/premier-test.js` et `charge/lib/commun.js` sont sur `main` de `plateforme/resilience`.
- [ ] Le script a des seuils sur p95 (< 250 ms) et sur `http_req_failed` ; il propose les deux modèles ; il crée **et** annule ; ses requêtes sont nommées.
- [ ] `k6 inspect` réussit sur la recette et **échoue** avec l'URL de production ; l'URL de production n'apparaît dans aucun script ; aucun script ne désactive la vérification TLS ; les dates envoyées portent un fuseau.
- [ ] Les métriques de la recette montrent au moins 100 réservations dans les 7 derniers jours ; aucun rendez-vous `dr-k6-*` ne reste en base.

**Vérification** : `lab/bin/check 29 05`

<details><summary>Indice 1</summary>

Le code au premier niveau d'un script k6 (hors des fonctions) s'exécute au chargement, une fois par VU, et aussi lors d'un `k6 inspect`. Une exception levée à cet endroit arrête k6 avant la première requête.
</details>

<details><summary>Indice 2</summary>

Une liste d'**autorisation** refuse tout ce qu'elle ne connaît pas, y compris une faute de frappe ou une nouvelle URL de production ; une liste d'interdiction laisse passer ce qu'on a oublié d'y mettre.
</details>

<details><summary>Indice 3</summary>

`exec.vu.idInTest` et `exec.vu.iterationInScenario` (module `k6/execution`) donnent de quoi fabriquer un couple (praticien, heure) que personne d'autre n'utilise. Une date sans fuseau est refusée par MédiAgenda (422) : un check qui accepte « tout sauf 5xx » ne le verra pas.
</details>

**Pour aller plus loin** (facultatif) : lance le modèle ouvert à 3, 6 puis 12 itérations par seconde et note à partir de quand la p95 décroche ; c'est le point de départ d'E06.
