# Module 17 — Palier 2 : Opérationnel

Le chart `mediagenda` existe, il refuse les valeurs fausses, il tourne en dev ; la recette est décrite par Kustomize. Mais le chart ne sait pas encore déployer ce dont MédiAgenda dépend, personne ne l'a testé autrement qu'à la main, il n'est publié nulle part, la production n'existe pas, la plateforme est toujours un tas de `helm install` oubliés, et les migrations de schéma se lancent encore « quand on y pense ». Ce palier traite ces tickets du quotidien : dépendances et sous-charts, tests, publication signée, Kustomize avancé et création de la production, Helmfile, une revue du chart de Lucas, et les hooks de migration.

> **Rappels du module** (introduction) : un seul gestionnaire par objet (dev = Helm, recette et prod = Kustomize, plateforme = Helmfile) ; tout passe par une MR ; aucun secret dans un chart ni dans un dépôt ; la production ne déploie que ce qui est signé. Les commandes se lancent depuis `adm01`. Vérifications : `lab/bin/check 17 <XX>`.

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| Chart | `mediagenda` 0.3.0 (E06), 0.4.0 (E07), 0.5.0 (E12) ; bibliothèque `medisphere-commun` 0.1.0 (`charts/medisphere-commun/`, `type: library`) |
| Sous-chart Valkey | chart officiel `valkey` 0.12.0 (dépôt `https://valkey.io/valkey-helm/`), recopié dans Harbor `charts/valkey` en E08 ; activé par `valkey.enabled` ; Service `mediagenda-valkey` |
| Base CNPG du chart | rendue si `postgresql.cnpg.enabled` : `Cluster` `mediagenda-db` (`<release>-db`), Secret `mediagenda-db-app`, annotation `helm.sh/resource-policy: keep` |
| Espace jetable | `wb-ct` (chart-testing, E07), créé puis supprimé |
| Harbor | projet `charts` (privé, OCI, immuabilité de toutes les étiquettes, signature Cosign exigée) ; robot `robot$charts+ci` (push/pull sur `charts`) ; variables CI `HARBOR_CHARTS_USER` (protégée, non développée : le `$` empêche le masquage, comme `HARBOR_ROBOT_USER` au M13) et `HARBOR_CHARTS_TOKEN` (protégée, masquée), dans le groupe `mediagenda` |
| Production | espace `mediagenda-prod` (créé en E09 par `overlays/prod`), nom publié `mediagenda.apps.par1.medisphere.internal` |
| Plateforme | `plateforme/k8s` : `helmfile.yaml`, `releases/*.yaml.gotmpl`, `environnements/par1.yaml`, `composants/<release>/values.yaml` |
| Revue | `ressources/E11-chart-medidoc/` (chart de MédiDoc de Lucas) ; ta version corrigée dans `~/m17/e11/medidoc/` |
| Documentation | `plateforme/medisphere`, `docs/kubernetes/packaging/` |

Durée indicative du palier : 14 à 18 heures. Ordre conseillé :

```
E06 ─ E07 ─ E08 ─ E12 ─ E09        (E09 consomme le chart 0.5.0 signé)
E10 (dès le palier 1 terminé)
E11 (quand tu veux, idéalement après E07)
```

---

### M17-E06 — Dépendances et sous-charts  `LAB` `★★★`

> **Ticket DEV-1806** — *De : Julien Petit*
> En dev, la base et le cache sont encore les bricolages de ton premier ticket. Je voudrais que le chart sache déployer **tout** MédiAgenda d'un coup quand on le lui demande (pour dev et pour les tests), mais qu'il sache aussi se brancher sur une base existante (la recette). Et ne réécris pas Valkey toi-même : il existe un chart officiel. Karim veut en plus qu'on mette en commun ce qui servira aux charts des autres équipes.

**Objectifs pédagogiques**
- Déclarer des dépendances (`dependencies` de `Chart.yaml`) : version, dépôt, `condition`, `import-values` ; `helm dependency update` contre `build`, rôle de `Chart.lock`.
- Passer des valeurs à un sous-chart, lire ses valeurs et ses noms d'objets.
- Écrire un chart de bibliothèque (`type: library`) et l'utiliser.
- Rendre une ressource d'un opérateur (`Cluster` CloudNativePG) sous condition, protéger les données à la désinstallation.
- Reprendre un objet existant dans une release (`--take-ownership`) et retirer proprement les objets provisoires.

**Prérequis** : M17-E05 ; M16-E18 (CloudNativePG).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Chart Valkey officiel : dépôt `https://valkey.io/valkey-helm/`, chart `valkey`, version **0.12.0** (Valkey 9.1). Lis ses valeurs (`helm show values`) avant de t'en servir : registre de l'image, format de `imagePullSecrets`, étiquettes de ses pods, nom de son Service.
- Chart de bibliothèque `medisphere-commun` 0.1.0 dans `charts/medisphere-commun/` du même projet, référencé par `repository: file://../medisphere-commun`. Il fournit : étiquettes `medisphere.internal/*`, contextes de sécurité `restricted`, référence d'image.
- Base rendue par le chart : `Cluster` `postgresql.cnpg.io/v1`, une instance en dev, `ceph-rbd`, image PostgreSQL 18 par le cache Harbor `ghcr`, `bootstrap.initdb` (`mediagenda` / `mediagenda`), et ses politiques réseau (clients, réplication, opérateur dans `cnpg-system`, accès à l'API Kubernetes par CiliumNetworkPolicy `toEntities: [kube-apiserver]`).
- En dev, le `Cluster` `mediagenda-db` existe déjà (créé par `kubectl` en E03) : il doit être **repris**, pas recréé (les données de dev ne sont pas précieuses, mais c'est l'exercice). Les objets provisoires à retirer : StatefulSet et Service `valkey`, politiques `dev-base-provisoire`, `dev-base-provisoire-api-kubernetes`, `dev-valkey-provisoire`.
- Chart 0.3.0.

**Travail demandé**
1. Lis la page « Charts » de la documentation Helm, section *Chart Dependencies* : `condition` et `tags`, `alias`, `import-values` (formes « exports » et « child/parent »). Note dans `~/m17/e06/journal.md` ce que `helm dependency update` fait de plus que `build`, ce que contient `Chart.lock`, et ce qui doit être versionné dans Git.
2. Écris `charts/medisphere-commun` (`type: library`, aucun objet), puis fais-y migrer les gabarits communs de `mediagenda` sans changer le rendu : compare `helm template` avant et après (le diff doit être vide, aux commentaires près).
3. Déclare les deux dépendances dans `Chart.yaml` de `mediagenda` ; Valkey sous la condition `valkey.enabled` ; importe la valeur `service` du sous-chart sous `valkeyImporte` pour que l'URL de Valkey suive le port du sous-chart. Lance `helm dependency update`, versionne `Chart.lock`, ignore les archives `charts/*/charts/`.
4. Passe au sous-chart les valeurs nécessaires chez MédiSphère : registre MédiSphère (cache `dockerhub`), Secret de tirage, ressources. Vérifie au rendu que ses pods passeraient Pod Security `restricted`.
5. Ajoute la base CNPG conditionnelle et ses politiques réseau ; l'URL de connexion vient du Secret `<cluster>-app` que crée CNPG. Ajoute un contrôle qui refuse `database.existingSecret` **et** `postgresql.cnpg.enabled` en même temps. Garantis qu'un `helm uninstall` ne supprime pas la base.
6. Rends trois profils et lis-les : recette (base et Valkey externes), dev (tout intégré), « tout intégré à trois instances ». Valide-les (`helm template … | kubeconform …` si tu l'as installé, sinon `kubectl apply --dry-run=server -f -` dans `wb-essais`).
7. Monte la release de dev en 0.3.0 avec base et Valkey intégrés. Le premier essai échoue : lis le message (le `Cluster` existe et n'appartient pas à la release). Lis `helm upgrade --help` et reprends l'objet. Vérifie ensuite que le `Cluster` porte les annotations `meta.helm.sh/*` et que son âge n'a pas changé.
   > ⚠️ **Attention** : l'option de reprise s'applique à **tous** les objets du rendu qui existent déjà sans appartenir à la release. Lis `helm upgrade --dry-run=server` avant, et assure-toi que rien d'autre n'est concerné (en particulier rien de la recette : vérifie l'espace dans la commande).
8. Bascule l'API sur `mediagenda-valkey`, puis retire les objets provisoires de E03. Vérifie que `/pret` répond toujours 200.
9. MR « feat: dépendances valkey et base CNPG, bibliothèque medisphere-commun (0.3.0) », relue par Karim et Julien.

**Critères de réussite**
- [ ] `Chart.yaml` de `mediagenda` déclare `medisphere-commun` et `valkey` (avec `condition`) ; `Chart.lock` est versionné, les archives de dépendances ne le sont pas.
- [ ] En dev, le `Cluster` `mediagenda-db` appartient à la release `mediagenda` et n'a pas été recréé ; il porte `helm.sh/resource-policy: keep`.
- [ ] En dev, Valkey est celui du sous-chart (`mediagenda-valkey`, pods prêts) ; les objets provisoires de E03 n'existent plus.
- [ ] L'API de dev est prête et `/sante` répond 200 sur son nom publié.

**Vérification** : `lab/bin/check 17 06`

<details><summary>Indice 1</summary>

Un chart de bibliothèque ne contient que des fichiers `templates/_*.tpl` (gabarits nommés) : Helm refuse d'installer un chart `type: library`, mais ses gabarits sont accessibles au chart parent qui le déclare en dépendance. Les valeurs lues par ces gabarits sont celles du **parent** : passe-leur le contexte racine.
</details>

<details><summary>Indice 2</summary>

Le Service du sous-chart s'appelle `<release>-valkey` (lis le gabarit `fullname` de son `_helpers.tpl`). Ses pods portent `app.kubernetes.io/name: valkey` et `app.kubernetes.io/instance: <release>` : tes politiques réseau doivent les viser **tous les deux**, sinon elles s'appliqueraient aussi à d'autres Valkey de l'espace. Et son `imagePullSecrets` n'a pas la même forme que le tien.
</details>

<details><summary>Indice 3</summary>

Pour la reprise : `helm upgrade --help` décrit une option qui « ignore the check for helm annotations ». Pour la conservation de la base, cherche « resource-policy » dans la documentation Helm. Et pense à ce qui se passe au **premier** `helm install` sur un espace vide : le Secret de la base n'existe pas encore quand les pods de l'API démarrent ; qu'est-ce que Kubernetes en fait ?
</details>

**Pour aller plus loin** (facultatif) : remplace `import-values` par la forme `exports` (le sous-chart déclare ce qu'il exporte) : pourquoi le chart Valkey officiel ne le permet-il pas ? Que faudrait-il proposer à ses mainteneurs ?

---

### M17-E07 — Tester un chart  `LAB` `★★★`

> **Ticket PLAT-1807** — *De : Karim Benali*
> Ton chart grossit. À chaque MR, je relis le rendu à l'œil et je ne vois rien. Je veux trois filets : des tests unitaires du rendu (rapides, sans cluster), un test d'intégration qui installe vraiment le chart dans un espace jetable puis le supprime, et un `helm test` qui dit si l'application répond après chaque montée. Le pipeline (palier 3) n'aura plus qu'à les lancer.

**Objectifs pédagogiques**
- Écrire des tests helm-unittest : suites, `set`, `release`, `documentSelector`, assertions (`equal`, `contains`, `matchRegex`, `hasDocuments`, `failedTemplate`…), et éviter les tests qui passent pour une mauvaise raison.
- Écrire un test `helm test` (hook `test`) qui n'utilise que des images autorisées.
- Utiliser chart-testing : `ct lint` (lint, yamllint, schéma de `Chart.yaml`, montée de version obligatoire) et `ct install` dans un espace jetable.

**Prérequis** : M17-E06.
**Durée indicative** : 2 h 30.

**Contexte technique**
- helm-unittest 1.2.1 (installé en introduction) : tests dans `charts/mediagenda/tests/*_test.yaml`, lancés par `helm unittest charts/mediagenda`. Ils ne doivent pas partir dans l'archive du chart.
- `helm test` : un pod `mediagenda-test-pret` (hook `test`) qui appelle `/pret` et `/sante` par le Service et vérifie la version. Image : celle de l'application (pas de `busybox` ni de `curl` publics : la VAP du M14 les refuse).
- chart-testing 3.15 : `ct.yaml` à la racine du projet ; valeurs de test dans `charts/mediagenda/ci/*-values.yaml` (chaque fichier = un cas lint + installation). Constat vérifié : l'image `quay.io/helmpack/chart-testing:v3.15.0` embarque **Helm 3.16** ; sur `adm01`, `ct` utilise ton Helm 4.3.
- Espace jetable `wb-ct` : Pod Security `restricted` comme les espaces applicatifs, Secret `harbor-pull` recopié depuis `mediagenda-dev` (sans afficher son contenu), supprimé en fin d'exercice. Le cas d'installation de `ct` doit être **autonome** (base et Valkey intégrés, pas de route publiée).
- Chart 0.4.0.

**Travail demandé**
1. Lis le README de helm-unittest (format des suites, liste des assertions). Écris au moins cinq suites : Deployment (image par défaut, digest prioritaire, Secret de la base selon le profil, Valkey intégré ou non, sécurité, sondes, empreinte, conteneur d'initialisation absent par défaut), exposition (nom publié calculé et imposé, PDB rendu ou non), politiques réseau (base externe, base intégrée, désactivation), base CNPG (absente par défaut, présente et conservée), schéma (un cas témoin **qui rend**, puis un cas par règle, avec un motif d'erreur précis).
2. Démontre qu'un test mal écrit peut mentir : écris un test `failedTemplate: {}` qui passe avec des valeurs **valides** (indice : un gabarit inclus qui n'est pas chargé dans la suite). Corrige-le et note la règle dans le journal.
3. Ajoute le test `helm test` (`templates/tests/test-pret.yaml`) et vérifie qu'il est bien dans le rendu **et** dans l'archive (`helm package` puis `tar -tzf`) alors que `tests/` (helm-unittest) et `ci/` n'y sont pas. Attention au `.helmignore`.
4. Écris `ct.yaml` (répertoire des charts, branche cible, pas de validation des mainteneurs GitHub, montée de version vérifiée, bibliothèque exclue) et `ci/autonome-values.yaml`. Lance `ct lint --config ct.yaml --all`, puis modifie une valeur sans changer la version et relance `ct lint` sans `--all` sur une branche : que dit-il ?
5. Prépare `wb-ct` (étiquettes Pod Security, Secret de tirage recopié), puis `ct install --config ct.yaml --namespace wb-ct --charts charts/mediagenda`. Pendant l'installation, observe dans un autre terminal ce qui se crée dans `wb-ct`. Que fait `ct` à la fin ? Supprime ensuite `wb-ct`.
   > ⚠️ **Attention** : `ct install` crée une base CNPG et un volume `ceph-rbd` à chaque passage. Vérifie après coup qu'il ne reste ni PVC ni image RBD orpheline (`kubectl get pv | grep wb-ct`), et supprime le `Cluster` si `ct` ne l'a pas fait (la politique `keep` le protège aussi de `ct`).
6. Monte la release de dev en 0.4.0, puis `helm test mediagenda -n mediagenda-dev --logs`. Rends ensuite Valkey injoignable le temps d'un essai, **sans toucher aux objets de la release** (un `kubectl scale` ou `edit` changerait le propriétaire d'un champ : c'est l'objet de M17-E22) : une CiliumNetworkPolicy temporaire `essai-coupure-valkey` avec une règle `ingressDeny` sur les pods de Valkey. Relance `helm test`, lis l'échec et ses journaux, supprime la politique et relance le test jusqu'au succès. Que dit `helm status` du dernier test ?
7. MR « test: tests unitaires, helm test et chart-testing (0.4.0) », relue par Karim.

**Critères de réussite**
- [ ] `charts/mediagenda/tests/` contient au moins cinq suites ; `helm unittest charts/mediagenda` passe ; une suite contient un cas témoin qui rend sans erreur.
- [ ] `charts/mediagenda/templates/tests/` contient un test `helm test` qui utilise l'image de l'application ; `ct.yaml` et au moins un `ci/*-values.yaml` sont sur `main`.
- [ ] En dev, le dernier pod de test `mediagenda-test-pret` a réussi.
- [ ] L'espace `wb-ct` n'existe plus et aucun PV de `wb-ct` ne reste.

**Vérification** : `lab/bin/check 17 07`

<details><summary>Indice 1</summary>

Dans une suite helm-unittest, `templates:` liste les gabarits **chargés** ; un gabarit qui en `include` un autre (l'empreinte de la ConfigMap) a besoin que l'autre soit chargé aussi. `template:` dans un test choisit celui sur lequel portent les assertions.
</details>

<details><summary>Indice 2</summary>

Dans `.helmignore`, un motif `tests/` exclut **tout** répertoire de ce nom, y compris `templates/tests/`. Vérifie dans la documentation comment ancrer un motif à la racine du chart.
</details>

<details><summary>Indice 3</summary>

`ct` cherche sa configuration de lint (`lintconf.yaml`, `chart_schema.yaml`) dans le répertoire courant, `~/.ct` ou `/etc/ct`. Pour la montée de version, il compare au `remote`/`target-branch` de `ct.yaml` : il lui faut un dépôt Git avec cette branche récupérée.
</details>

**Pour aller plus loin** (facultatif) : les instantanés (*snapshots*) de helm-unittest (`matchSnapshot`) figent le rendu complet ; quand sont-ils utiles, quand deviennent-ils du bruit ?

---

### M17-E08 — Publier le chart en OCI dans Harbor et le signer  `LAB` `★★`

> **Ticket SEC-1808** — *De : Sophie Laurent*
> Un chart, c'est du code qui s'exécute avec les droits de celui qui l'installe. Je veux qu'il vienne de **notre** registre, qu'une version publiée ne puisse plus être remplacée, et qu'il soit signé avec la clé MédiSphère comme nos images. Même règle pour les charts tiers que nous embarquons : on les recopie, on les relit, on les signe.

**Objectifs pédagogiques**
- Publier un chart en OCI (`helm package`, `helm registry login`, `helm push`), le récupérer par étiquette et par digest.
- Configurer le projet Harbor `charts` : privé, immuabilité, signature exigée, robot de CI.
- Signer le chart par digest avec Cosign 3 sans journal de transparence public, et vérifier la signature.
- Comparer la provenance Helm (`.prov`, PGP, `helm verify`) et la signature Cosign, et justifier le choix de MédiSphère.
- Recopier une dépendance tierce dans Harbor et y faire pointer le chart.

**Prérequis** : M17-E07 ; M13-E03 (projets, robots), M13-E07 (Cosign), M13-E14 (politiques de projet).
**Durée indicative** : 2 h.

**Contexte technique**
- Projet Harbor `charts` : à créer s'il n'existe pas (M13 l'a peut-être déjà fait : vérifie). Privé ; règle d'immuabilité sur **toutes** les étiquettes de tous les dépôts du projet ; politique « Cosign » comme le projet `medisphere` (M13-E14).
- Publication manuelle par ton compte personnel Harbor (`<MOI>`) ; le robot `robot$charts+ci` (push et pull d'artefacts, projet `charts`, expiration 90 jours) est créé pour le pipeline du palier 3 : son jeton va directement dans les variables protégées du groupe GitLab `mediagenda` (`HARBOR_CHARTS_TOKEN`, masquée ; `HARBOR_CHARTS_USER`, non développée), nulle part ailleurs.
- Clé Cosign MédiSphère : privée en Vault `critique` (M13), publique dans `plateforme/medisphere` (`docs/registre/cosign.pub`). Signature **par digest**, sans Rekor public, avec la même méthode que tes images : la configuration de signature sans service `docs/registre/signing-config.json` et le script de chargement de la clé `outils/cosign-cle.sh` du M13-E07.
- Helm 4 : `helm registry login` n'accepte que le **nom de domaine** du registre.
- Le chart Valkey 0.12.0 est recopié en `charts/valkey` ; ensuite la dépendance du chart pointe vers `oci://registry.par1.medisphere.internal/charts`.

**Travail demandé**
1. Configure le projet `charts` (immuabilité, politique de signature) et crée le robot `robot$charts+ci` ; range ses identifiants dans les variables du groupe `mediagenda` sans qu'ils passent par un fichier ni par ton historique de commandes. Note dans `docs/kubernetes/packaging/registre-charts.md` (dans `plateforme/medisphere`) les règles du projet et l'inventaire du robot (date d'expiration), comme le registre des secrets du M06.
2. Connecte Helm au registre (`helm registry login`) avec ton compte personnel, mot de passe par l'entrée standard. Où Helm range-t-il cet identifiant ?
3. Recopie Valkey : `helm pull` depuis le dépôt d'origine (version 0.12.0), relis rapidement son contenu (images, objets, droits RBAC demandés), `helm push` vers `charts`, signe-le par digest. Modifie `Chart.yaml` de `mediagenda` pour pointer vers Harbor, `helm dependency update` : `Chart.lock` change-t-il ? Pourquoi ?
4. Empaquette `mediagenda` 0.4.0 (`helm package`, dépendances incluses), lis la liste des fichiers de l'archive, publie-la. Note le digest affiché.
5. Essaie de republier la même version avec un contenu modifié : que répond Harbor ? Et si tu supprimes l'artefact puis le republies ? Qu'en conclus-tu sur ce que protège l'immuabilité ?
6. Signe le chart **par digest** avec la clé MédiSphère, vérifie la signature avec la clé publique, et regarde comment Harbor présente l'artefact (onglet *Accessories*). Vérifie aussi qu'une signature avec une **autre** clé (une paire jetable générée pour l'occasion) est refusée à la vérification.
7. Récupère le chart comme un consommateur : `helm pull` par étiquette, puis installation par digest dans `wb-essais` en `--dry-run=server` (`helm install … oci://…/mediagenda@sha256:…`). Essaie `helm pull --verify` : que se passe-t-il, et pourquoi ?
8. Réponds dans le journal : provenance Helm (fichier `.prov`, PGP) ou Cosign ? Donne deux arguments pour Cosign chez MédiSphère et un cas où la provenance Helm resterait utile.
9. MR « build: dépendance valkey depuis Harbor », relue par Sophie.

**Critères de réussite**
- [ ] Le projet Harbor `charts` est privé, contient `mediagenda` (au moins la version 0.4.0) et `valkey` 0.12.0, chacun avec une signature attachée.
- [ ] La dépendance `valkey` de `Chart.yaml` (sur `main`) pointe vers `oci://registry.par1.medisphere.internal/charts`.
- [ ] Le robot `robot$charts+ci` existe, limité au projet `charts`, avec une expiration ; `registre-charts.md` est sur `main` de `plateforme/medisphere`.
- [ ] Une republication de `mediagenda` 0.4.0 est refusée (noté dans le journal avec le message).

**Vérification** : `lab/bin/check 17 08`

<details><summary>Indice 1</summary>

`helm push <archive> oci://<registre>/<projet>` : le nom du dépôt OCI vient du **nom du chart**, l'étiquette de sa **version**. Le digest affiché par `helm push` est celui à signer.
</details>

<details><summary>Indice 2</summary>

Cosign s'authentifie auprès du registre avec la configuration Docker (`~/.docker/config.json`) ou `cosign login`, pas avec celle de Helm. Pour signer par digest : `registry.par1.medisphere.internal/charts/mediagenda@sha256:…`, sans `oci://`.
</details>

<details><summary>Indice 3</summary>

`helm pull --verify` cherche un fichier de provenance `.prov` et un trousseau PGP (`--keyring`) : il ne connaît pas les signatures Cosign. Lis l'aide de `helm package --sign` pour savoir ce qu'il faudrait pour en produire un.
</details>

**Pour aller plus loin** (facultatif) : produis une provenance Helm (clé PGP jetable, `helm package --sign`, `helm verify`) et pousse-la avec le chart : Harbor la conserve-t-il ? `helm pull --verify` fonctionne-t-il alors en OCI ?

---

### M17-E09 — Kustomize avancé : components, remplacements, générateurs  `LAB` `★★★`

> **Ticket PLAT-1809** — *De : Claire Morel*
> Le comité a validé l'ouverture de MédiAgenda en production le mois prochain. Je veux l'espace de production, avec les mêmes garde-fous que les autres, une application en haute disponibilité et sa propre base, déployés par le même dépôt que la recette, depuis le chart **signé**. Et je ne veux pas trois copies de la version : on promeut une version, on ne la recopie pas.

**Objectifs pédagogiques**
- Organiser des variantes par **components** Kustomize (inclus ou non par overlay) et comprendre l'ordre d'application.
- Utiliser les `replacements` pour qu'une seule valeur alimente plusieurs champs, et des ressources « locales » qui ne sont pas déployées.
- Brancher un chart Helm dans Kustomize : gonfleur `helmCharts` (`--enable-helm`) ou rendu vérifié commité ; choisir et justifier.
- Créer un espace de production complet par le code (Pod Security, quotas, refus réseau par défaut, exposition).

**Prérequis** : M17-E04, M17-E08, M17-E12 (le chart 0.5.0 signé contient les migrations par conteneur d'initialisation).
**Durée indicative** : 3 h.

**Contexte technique**
- Chart consommé : `oci://registry.par1.medisphere.internal/charts/mediagenda`, version **0.5.0**, digest et signature vérifiés avant usage. Mode de migration sous Kustomize : `migrations.mode: initContainer` (Kustomize et `kubectl apply` ne connaissent pas les hooks Helm : E12).
- Organisation cible de `mediagenda/deploiement` :
  - `chart.env` (référence, version, digest) et `outils/rendre-base.sh` (vérifie, puis rend), `base/` (rendu commité + valeurs communes + ConfigMap générée `mediagenda-parametres`) ;
  - `components/` : `dependances` (base CNPG `mediagenda-db` et Valkey `valkey` **hors chart**, avec leurs politiques réseau), `haute-disponibilite` (3 réplicas, répartition par baie et par nœud, PDB à 2, base à 3 instances avec réplication synchrone), `debogage` (journaux `DEBUG`, format `texte`, cache court), `livraison` (remplacements) ;
  - `overlays/dev` (construit seulement : dev reste Helm jusqu'au mini-projet), `overlays/recette`, `overlays/prod` ;
  - `essais/helmcharts/` : la même recette, gonflée par `helmCharts`, pour comparer.
- Mode de livraison retenu par MédiSphère : le **rendu vérifié et commité** (`chart.env` + `outils/rendre-base.sh`), appliqué par `kubectl apply --server-side -k overlays/<env>`. Les exercices suivants (E14, E18, E21, E25) s'appuient sur ce montage ; l'essai `helmCharts` sert à le confronter au gonfleur et à argumenter le choix dans l'ADR-0170.
- Une ConfigMap locale `livraison` par overlay (`version`, `nom-publie`), annotée `config.kubernetes.io/local-config: "true"`, est la **seule** source de la version et du nom publié.
- Production : `mediagenda-prod`, étiquettes d'espace d'équipe du M14-E10 (`medisphere.internal/equipe`, `medisphere.internal/environnement` : la politique d'images du M14-E18 et le RBAC s'en servent) et du M15-E28 (`medisphere.internal/equipe`), Pod Security `restricted` (enforce, audit, warn), `medisphere.internal/exposition: oui` (routes admises par `gw-par1`), `ResourceQuota` et `LimitRange` comme au M14-E10, NetworkPolicy de refus par défaut `refus-par-defaut` (même nom qu'au M15) ; Secret de tirage `harbor-pull` créé hors dépôt comme au M14-E19. Nom publié `mediagenda.apps.par1.medisphere.internal`.
- La recette passe du rendu 0.1.0 (E04) au rendu 0.5.0 : le conteneur d'initialisation `migrations` apparaît. Les en-têtes de sécurité que l'overlay de recette ajoute à la route depuis E04 valent aussi pour la production : place-les là où les deux les reçoivent.

**Travail demandé**
1. Lis les pages *Components*, *replacements* et *helmCharts* de la documentation Kustomize. Note dans `~/m17/e09/journal.md` l'ordre dans lequel une kustomization traite ses `resources`, ses `components` et ses propres transformations, et ce qu'implique `--enable-helm` pour qui construit (outils, accès réseau, identifiants du registre).
2. Écris `chart.env` et `outils/rendre-base.sh` : récupère la version demandée, vérifie que son digest est celui de `chart.env`, vérifie la signature Cosign **de ce digest**, puis rend avec `base/values-communes.yaml` sans hooks ni tests. Prévois un mode `--verifier` qui échoue si le rendu commité n'est pas à jour (le pipeline du palier 3 s'en servira). Lance-le, commite le rendu.
3. Fais de la ConfigMap générée un élément de la **base** (valeurs par défaut) que chaque overlay complète par `behavior: merge`. Vérifie que la référence dans `envFrom` porte bien le nom suffixé dans chaque overlay.
4. Écris les quatre components. Pour `haute-disponibilite`, un patch stratégique pour la répartition, des patchs JSON 6902 pour le PDB et le `Cluster`. Pour `debogage`, un patch stratégique sur `env` : pourquoi une ConfigMap ne suffit-elle pas pour `MEDIAGENDA_LOG_LEVEL` ? Pour `livraison`, des remplacements qui recopient `version` dans l'image de l'API **et** du conteneur d'initialisation, dans `MEDIAGENDA_VERSION` et dans les étiquettes `app.kubernetes.io/version`, et `nom-publie` dans la route.
5. Écris les overlays. Construis-les tous et vérifie au moins : prod à 3 réplicas avec la répartition et sans `DEBUG` ; dev avec `DEBUG` et **sans** PDB (une réplique) ; version identique dans les quatre champs de chaque overlay. Change la version de la recette dans `livraison.yaml` : combien de lignes as-tu modifiées pour une promotion ?
6. Crée la production : `kubectl diff --server-side -k overlays/prod`, puis `apply`. Crée le Secret `harbor-pull` dès que l'espace existe (le premier `apply` s'arrêtera peut-être sur les pods en attente : c'est l'ordre normal, réapplique). Attends la base (3 instances), puis l'API. Vérifie l'exposition HTTPS.
7. Mets à jour la recette avec le rendu 0.5.0 (`diff` puis `apply`). Observe le conteneur d'initialisation : que dit son journal sur une base déjà à jour ?
8. Dans `essais/helmcharts/`, construis la même recette avec `kustomize build --enable-helm` et compare avec `overlays/recette`. Regarde en particulier la référence `envFrom` à la ConfigMap générée. Note le constat, puis justifie en cinq lignes dans le journal le choix du rendu commité contre le gonfleur (ou, si ton constat te fait conclure l'inverse, ce qu'il faudrait changer dans le dépôt) : tu reprendras l'argument dans l'ADR-0170.
9. MR « feat: production, components et chart 0.5.0 signé », relue par Karim, validée par Claire.

**Critères de réussite**
- [ ] `mediagenda-prod` existe avec les étiquettes d'équipe, Pod Security `restricted`, l'étiquette d'exposition, un quota, une LimitRange et la politique `refus-par-defaut`.
- [ ] En prod : 3 pods de l'API prêts sur au moins 2 nœuds, base `mediagenda-db` à 3 instances prêtes, Valkey prêt ; `https://mediagenda.apps.par1.medisphere.internal/sante` répond 200 avec la version de `livraison.yaml` et les mêmes en-têtes de sécurité que la recette.
- [ ] En prod, aucun conteneur n'a `MEDIAGENDA_LOG_LEVEL=DEBUG` ; l'étiquette d'image, `MEDIAGENDA_VERSION` et `app.kubernetes.io/version` sont identiques.
- [ ] La recette tourne le rendu 0.5.0 (conteneur d'initialisation `migrations`), toujours gérée par Kustomize.
- [ ] `mediagenda/deploiement` contient `chart.env` (digest), `outils/rendre-base.sh` et les quatre components déclarés `kind: Component`.

**Vérification** : `lab/bin/check 17 09`

<details><summary>Indice 1</summary>

Un fichier référencé par une kustomization doit se trouver **sous** son répertoire (restriction de chargement par défaut) : un overlay ne peut pas lire `../../base/valeurs.yaml` comme fichier de valeurs ni un fichier de remplacements partagé. Un component, lui, est une kustomization : il emporte ses propres fichiers.
</details>

<details><summary>Indice 2</summary>

Un remplacement peut viser une partie d'un champ : `options.delimiter` et `options.index` découpent une chaîne (une image `registre/dépôt:étiquette`). Les sélecteurs de champs acceptent `[name=api]` pour choisir un élément de liste par sa clé.
</details>

<details><summary>Indice 3</summary>

Si le PDB de dev bloque, compte : une réplique et `minAvailable: 1`. Si la base de prod reste en `Pending`, regarde le quota de l'espace et la règle d'anti-affinité « requise » : trois instances, combien de travailleurs ?
</details>

**Pour aller plus loin** (facultatif) : signe aussi le **rendu** (le fichier `base/rendu/mediagenda.yaml`, par `cosign sign-blob`), et fais vérifier cette signature par `rendre-base.sh --verifier` : que gagne-t-on par rapport à la seule vérification du chart ?

---

### M17-E10 — Helmfile : décrire la plateforme  `LAB` `★★★`

> **Ticket PLAT-1810** — *De : Karim Benali*
> Ma question de la semaine dernière tient toujours : quelle version de cert-manager tourne, avec quelles valeurs, et qui l'a décidé ? Je veux la réponse dans Git. Toutes les releases installées depuis le module 14 dans un `helmfile.yaml` de `plateforme/k8s`, et **aucune réinstallation** : à la fin, `helmfile diff` ne doit rien montrer. Si quelque chose diffère, c'est le fichier qu'on corrige, pas le cluster.

**Objectifs pédagogiques**
- Écrire un Helmfile 1.x : environnements, dépôts, valeurs par défaut (`helmDefaults`), releases, étiquettes et sélecteurs, sous-fichiers et bases, gabarits `.gotmpl`.
- Reprendre des releases existantes sans les réinstaller : versions et valeurs **fournies** alignées sur le cluster, `helmfile diff` vide.
- Comprendre ce que Helmfile délègue à Helm et à helm-diff, et ses limites.

**Prérequis** : M17-E02 ; modules 14 à 16 (les releases existent).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Releases attendues (vérifie noms, espaces et versions avec `helm list -A` : ce qui fait foi, c'est le cluster) : `cilium` (`kube-system`, installée par la CLI `cilium`, qui crée une release Helm), `cert-manager` (`cert-manager`), `external-dns` (`external-dns`), `ceph-csi-rbd` et `ceph-csi-cephfs` (`ceph-csi`), `cnpg` et `plugin-barman-cloud` (`cnpg-system`), `velero` (`velero`), `metrics-server` (`kube-system`). Ce qui a été installé par manifeste ou par Kustomize (CRD Gateway API, external-snapshotter) reste hors de Helmfile.
- Sources des charts : celles des installations d'origine (relis les commandes des modules 14 à 16) : `https://helm.cilium.io`, `oci://quay.io/jetstack/charts` (cert-manager, M15), `https://kubernetes-sigs.github.io/external-dns/`, `https://ceph.github.io/csi-charts`, `https://cloudnative-pg.github.io/charts`, `https://vmware-tanzu.github.io/helm-charts`, `https://kubernetes-sigs.github.io/metrics-server/`.
- Organisation : `helmfile.yaml` à la racine (environnement `par1` et inclusion des fichiers de `releases/`), `releases/_communs.yaml` (environnements, dépôts, `helmDefaults`, partagé par `bases:`), un fichier `releases/NN-<groupe>.yaml.gotmpl` par groupe (`reseau`, `certificats`, `stockage`, `observabilite`), `environnements/par1.yaml`, valeurs dans `composants/` (le répertoire existe depuis le M14) : garde les fichiers existants à leur place (`composants/ceph-csi/values-rbd.yaml`, `composants/cloudnative-pg/values.yaml`…) et crée `composants/<release>/values.yaml` pour ceux qui manquent. Chaque release porte les étiquettes `groupe` et `composant`.
- Helmfile 1.8.1 + helm-diff 3.15 ; Helm 4.3. Helmfile refuse un `helmfile.yaml` et un répertoire `helmfile.d/` côte à côte.
- Aucun secret dans les valeurs : les Secrets (TSIG, S3 de Velero, Ceph) existent déjà, créés par les scripts des modules 15 et 16 ; les valeurs n'en citent que les **noms**.

**Travail demandé**
1. Inventaire : pour chaque release, version du chart (`helm list -A`), valeurs **fournies** (`helm get values <R> -n <NS>`), méthode d'application de la dernière révision (*server-side* ou non : regarde les `managedFields` d'un objet de la release). Note tout dans `~/m17/e10/inventaire.md`. Pour Cilium, note les valeurs que la CLI a ajoutées d'elle-même.
2. Écris l'ossature (`helmfile.yaml`, `_communs.yaml`, `environnements/par1.yaml`) et un premier fichier de releases avec **metrics-server seul**. `helmfile -e par1 list`, puis `helmfile -e par1 diff -l composant=metrics-server`. Fais converger le fichier (version, valeurs) jusqu'à un diff vide. Ne lance aucun `apply` tant que le diff n'est pas vide.
3. Ajoute les autres releases, une par une, avec la même discipline. Rassemble les valeurs fournies dans les fichiers de `composants/` (un script de comparaison peut t'aider : `helm get values` contre le fichier du dépôt). Utilise au moins une valeur d'environnement dans un gabarit (`.Values` de `environnements/par1.yaml`, par exemple le domaine filtré par ExternalDNS).
4. Quand **tout** le diff est vide (`helmfile -e par1 diff --detailed-exitcode` renvoie 0), enregistre la sortie et le code dans `~/m17/e10/diff-final.txt`. Lance alors `helmfile -e par1 apply` : que fait-il, puisque rien ne diffère ? Vérifie avec `helm list -A` que les révisions n'ont pas bougé.
5. Teste une modification réelle et sans risque : augmente une ressource de metrics-server dans `composants/metrics-server/values.yaml`, `diff`, `apply -l composant=metrics-server`, vérifie la nouvelle révision, puis reviens en arrière **par le fichier** (pas par `helm rollback`).
6. Réponds dans le journal : que se passe-t-il si quelqu'un lance `helm upgrade cert-manager … --set …` à la main demain ? Qui s'en aperçoit, et quand ? Que changera Argo CD (M20) ?
7. MR « feat: plateforme sous Helmfile », avec la sortie de `helmfile diff` vide dans la description ; relue par Karim. Ajoute à `Taskfile.yml` de `plateforme/k8s` les tâches `helmfile:diff` et `helmfile:apply`.

**Critères de réussite**
- [ ] `plateforme/k8s` contient `helmfile.yaml`, `releases/_communs.yaml` et des fichiers `releases/*.yaml.gotmpl` qui déclarent les neuf releases, avec leurs étiquettes `groupe` et `composant`.
- [ ] Pour chaque release, la version déclarée dans Helmfile est celle qui tourne (étiquettes de chart des objets) et la release existe toujours dans son espace.
- [ ] `~/m17/e10/diff-final.txt` montre un `helmfile diff` sans écart (code de sortie 0).
- [ ] Aucune valeur de `composants/` ne contient de secret (mot de passe, clé, jeton).

**Vérification** : `lab/bin/check 17 10`

<details><summary>Indice 1</summary>

En Helmfile 1.x, un fichier n'est rendu comme gabarit que s'il se termine par `.gotmpl`, et une partie d'un fichier (séparée par `---`) ne voit que ce qui a été défini dans les parties **précédentes**. Un sous-fichier ne connaît un environnement que s'il le déclare (d'où les `bases:`), et le fichier racine doit lui aussi déclarer l'environnement choisi par `-e`.
</details>

<details><summary>Indice 2</summary>

Un diff qui montre des champs que tu n'as jamais réglés vient souvent de valeurs que l'installateur avait ajoutées (la CLI `cilium`) ou de défauts qui ont changé entre la version de chart installée et celle que tu déclares. Compare `helm get values` (fournies) avec ton fichier, pas `--all`.
</details>

<details><summary>Indice 3</summary>

`--detailed-exitcode` fait renvoyer à `helmfile diff` un code 2 quand il y a des différences : c'est ce qu'un pipeline testera. Si le diff mentionne la méthode d'application ou des champs gérés, regarde les options de Helmfile 1.8 pour Helm 4 (`--server-side`) et la méthode d'origine de la release (question 1).
</details>

**Pour aller plus loin** (facultatif) : recopie les charts de plateforme dans le projet Harbor `charts` (comme Valkey en E08) et fais pointer Helmfile vers `oci://registry.par1.medisphere.internal/charts` : la plateforme ne dépend plus d'Internet pour se réinstaller.

---

### M17-E11 — Revue : le chart du stagiaire  `REV` `★★`

> **Ticket PLAT-1811** — *De : Karim Benali* — *Copie : Lucas Martin*
> Lucas a écrit le chart de MédiDoc « sur le modèle de MédiAgenda ». Il me demande une validation pour vendredi. Fais-lui une vraie revue : chaque défaut, sa gravité, ce qu'il casserait **chez nous**, et la correction. Puis propose-lui une version corrigée qu'il pourra comparer à la sienne.

**Objectifs pédagogiques**
- Relire un chart comme il se rendra et s'exécutera : rendu, valeurs, sélecteurs, sécurité, cycle de vie (hooks, aléas), exposition.
- Classer des défauts par gravité et rédiger une revue utile.
- Produire une version corrigée qui passe les contrôles de MédiSphère.

**Prérequis** : M17-E05 à M17-E07.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Fichiers : `ressources/E11-chart-medidoc/` (`MR-lucas.md`, `Chart.yaml`, `values.yaml`, `templates/…`). Les clés S3 qu'ils contiennent sont **fictives**.
- MédiDoc (voir `apps/README.md`) : port 8080, `/healthz` (vivacité), `/readyz` (disponibilité : accès au compartiment S3), variables `MEDIDOC_S3_ENDPOINT`, `MEDIDOC_S3_BUCKET`, `MEDIDOC_S3_REGION`, `MEDIDOC_CA_FILE`, `MEDIDOC_MAX_MB`, `MEDIDOC_PORT`, `MEDIDOC_LOG_LEVEL`, `MEDIDOC_VERSION`, et `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`. Cible : espace `medidoc-dev` (M14-E33), RGW `https://rgw.par1.medisphere.internal` (M08), compartiment `medidoc-documents`, compte `medidoc-app` dont les clés sont déjà dans un Secret `medidoc-s3` créé hors chart, image `registry.par1.medisphere.internal/medisphere/medidoc`, racine MédiSphère dans une ConfigMap `medisphere-ca`.
- Ta version corrigée : `~/m17/e11/medidoc/` (un chart complet, pas un extrait). Elle ne sera pas installée par ce ticket.

**Travail demandé**
1. Lis tout sans rien noter. Puis réponds : le chart se rend-il ? Combien de pods tournent, sur quel sélecteur ? D'où viennent les clés S3 et qui peut les lire ? Que se passe-t-il au deuxième `helm upgrade` ?
2. Rédige la revue en tableau dans `~/m17/e11/revue.md` : n°, fichier et ligne(s), défaut, catégorie (sécurité, disponibilité, exploitation, conformité aux standards), gravité (critique, élevée, moyenne, faible), impact concret chez nous, correction.
3. Classe les défauts par ordre de traitement et justifie le premier. Que doit faire Lucas **avant même** de corriger son chart, à propos des clés qu'il a publiées ?
4. Écris la version corrigée dans `~/m17/e11/medidoc/` : elle doit passer `helm lint --strict` et se rendre avec les valeurs par défaut.
5. Trois lignes de conseils à Lucas sur sa façon de tester (« ça marche sur mon kind »).

**Critères de réussite**
- [ ] `revue.md` identifie au moins 12 défauts, dont tous les critiques et élevés du corrigé, chacun avec un impact et une correction précis.
- [ ] `~/m17/e11/medidoc/` passe `helm lint --strict` et se rend ; le rendu n'utilise ni `latest`, ni Ingress, ni clé S3 en clair, ni espace de noms codé en dur, ni version dans un sélecteur, et ses pods respectent `restricted`.

**Vérification** : `lab/bin/check 17 11` (contrôle la version corrigée ; la revue est auto-évaluée avec le corrigé)

<details><summary>Indice 1</summary>

Commence par `helm lint` et `helm template` sur le chart de Lucas : ce qui ne se rend pas est le plus facile à trouver. Ensuite, pour chaque objet, demande-toi ce qui changera entre deux `helm upgrade` successifs **sans changement de valeurs**.
</details>

<details><summary>Indice 2</summary>

Pour chaque sonde, demande-toi ce que fait kubelet quand elle échoue, et si la cause d'échec est dans le pod ou à l'extérieur (le stockage objet). Pour chaque annotation `helm.sh/hook`, demande-toi qui gère l'objet ensuite.
</details>

---

### M17-E12 — Hooks, ordre de déploiement et migrations de schéma  `LAB` `★★★`

> **Ticket DEV-1812** — *De : Julien Petit*
> Aujourd'hui, les migrations, c'est moi qui lance `python -m mediagenda.migrate` depuis un pod quand je pense à le faire. La semaine dernière, la nouvelle version a démarré avant la migration et a renvoyé des 500 pendant dix minutes. Je veux que le chart applique les migrations **avant** de déployer la nouvelle version, qu'un échec de migration laisse l'ancienne version en place, et je veux savoir ce qu'on fait quand ça casse.

**Objectifs pédagogiques**
- Comprendre le cycle de vie d'une release et l'ordre d'exécution : hooks par phase et par poids, objets ordinaires, ordre des types d'objets.
- Écrire un Job de migration en hook (`helm.sh/hook`, `hook-weight`, `hook-delete-policy`) et les objets dont il dépend, en tenant compte de ce qui n'existe pas encore au moment du hook.
- Choisir entre hook, conteneur d'initialisation et Job séparé selon l'outil qui déploie.
- Provoquer un échec de migration, constater ce qui reste en place, revenir à un état sain, et savoir ce qu'un `helm rollback` ne défait pas.

**Prérequis** : M17-E06, M17-E07 ; `apps/mediagenda/README.md` (section Migrations).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Commande de migration : `python -m mediagenda.migrate` (variables `MEDIAGENDA_DB_URL`, `MEDIAGENDA_MIGRATIONS_DIR`) ; elle applique les fichiers `V<n>__*.sql` absents de la table `mediagenda_historique_schema`, chacun dans une transaction, sous un verrou consultatif (deux exécutions simultanées ne se gênent pas) ; elle s'arrête en code 1 si le répertoire est introuvable ou si une migration déjà appliquée a été modifiée. Répertoire des migrations dans l'image : celui de ton Dockerfile du M12-E05 (le corrigé suppose `/app/migrations`).
- Valeur `migrations.mode` à créer : `hook` (Job de hook, défaut), `initContainer` (conteneur d'initialisation de chaque pod, pour Kustomize en E09), `none`.
- En dev, la base est rendue par le chart (E06) ; en recette, elle est externe. À la **première** installation d'une release qui rend aussi sa base, le `Cluster` n'existe pas pendant les hooks `pre-install`.
- L'espace est en refus réseau par défaut et la politique réseau de la release est un objet ordinaire ; le compte de service du chart aussi.
- Lecture de la table d'historique : `kubectl cnpg psql mediagenda-db -n mediagenda-dev -- -c 'SELECT * FROM mediagenda_historique_schema'` (plugin `kubectl cnpg` du M16).
- Chart 0.5.0, publié et signé comme en E08 à la fin de l'exercice.

**Travail demandé**
1. Lis la page « Chart Hooks » de la documentation Helm. Dessine dans `~/m17/e12/journal.md` la séquence d'un `helm upgrade` : hooks `pre-upgrade` (dans quel ordre de poids, et Helm attend-il chacun ?), objets ordinaires, `post-upgrade`. Que veut dire « prêt » pour un Job de hook ? Où passent les hooks dans un `helm template`, et dans un `kustomize build` du rendu ?
2. Écris le Job de migration en hook : `pre-install,pre-upgrade` quand la base est externe, `post-install,pre-upgrade` quand le chart la rend ; politique de suppression qui garde un Job terminé pour lire ses journaux, nettoyage par `ttlSecondsAfterFinished` ; `backoffLimit`, `activeDeadlineSeconds` ; contexte de sécurité `restricted`. Réfléchis aux dépendances du Job au moment où il s'exécute (compte de service, politique réseau) et écris ce qu'il faut, avec les bons poids.
3. Écris le mode `initContainer` (même conteneur, dans le Deployment) et le mode `none`. Ajoute les tests unitaires correspondants (poids, phases, absence de hook hors mode `hook`).
4. Monte la release de dev en 0.5.0 avec `--wait`. Pendant la montée, observe l'ordre réel : `kubectl -n mediagenda-dev get events --sort-by=.lastTimestamp -w` et `kubectl get jobs,pods -w`. Lis le journal du Job, puis la table d'historique : quelles migrations sont notées, avec quelles empreintes ?
5. Provoque un échec de migration **sans** construire d'image : une montée qui pointe le Job vers un répertoire de migrations inexistant, `backoffLimit` à 0. Observe : statut de la release (`helm history`), Job et ses journaux, Deployment (a-t-il changé ? quelle image tourne ?), disponibilité de `/sante`. Enregistre `helm history` dans `~/m17/e12/historique.txt`.
6. Reviens à un état sain par une nouvelle montée correcte, puis rejoue l'échec avec `--rollback-on-failure` : différence dans l'historique ?
7. Réponds dans le journal : une migration V3 qui **réussit** suivie d'une nouvelle version de l'API qui plante au démarrage ; tu lances `helm rollback`. Dans quel état est la base ? L'ancienne version de l'API fonctionne-t-elle sur le nouveau schéma ? Quelle discipline de migration (« expand / contract ») rend ce retour arrière sûr, et que faut-il en dire à l'équipe de Julien ?
8. Publie et signe le chart 0.5.0 (comme en E08). MR « feat: migrations de schéma par hook (0.5.0) », relue par Julien.

**Critères de réussite**
- [ ] En dev, la release est en 0.5.0 ; le Job `mediagenda-migrations` porte un hook `…,pre-upgrade` et sa dernière exécution a réussi.
- [ ] `~/m17/e12/historique.txt` montre une révision `failed` suivie d'une révision `deployed`.
- [ ] Pendant l'échec, l'API de dev a continué de servir (noté dans le journal avec l'image observée).
- [ ] `charts/mediagenda:0.5.0` est publié et signé dans Harbor.

**Vérification** : `lab/bin/check 17 12`

<details><summary>Indice 1</summary>

Les hooks d'une phase sont triés par poids (puis par type et par nom) ; Helm crée chacun et attend qu'il soit « prêt » avant le suivant — pour un Job, prêt veut dire terminé avec succès. Un hook n'est pas un objet de la release : il n'est ni mis à jour ni supprimé avec elle, sauf par sa politique de suppression.
</details>

<details><summary>Indice 2</summary>

Pendant un `pre-install`, les objets ordinaires du chart (dont son ServiceAccount et sa NetworkPolicy) n'existent pas encore. Un objet nécessaire au Job peut être lui-même un hook de la même phase, avec un poids plus faible.
</details>

<details><summary>Indice 3</summary>

Pour l'échec : la valeur `migrations.repertoire` suffit. Pour le statut de la release après un échec de hook sans retour arrière automatique, regarde `helm status` : la prochaine montée est-elle possible directement ?
</details>

**Pour aller plus loin** (facultatif) : ajoute un hook `post-upgrade` qui interroge `/sante` et vérifie la version : en quoi diffère-t-il de `helm test` ? Lequel des deux bloque la release s'il échoue ?
