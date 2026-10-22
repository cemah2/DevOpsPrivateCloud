# Module 19 — Intégration continue : palier 4 — Expert

La chaîne de CI de MédiSphère tourne : deux runners dans `k8s-par1` (dont un protégé), un démon BuildKit partagé, un cache S3, des composants CI/CD versionnés, des images signées et promues par MR, un agent GitLab qui déploie en dev. Tout le monde en dépend désormais, et Nadia Roussel pose la question qu'elle pose à chaque nouvelle brique : « Quand un pipeline reste bloqué à 7 h du matin le jour d'une mise en production, qui sait chercher, et où ? » Karim Benali a préparé huit pannes, toutes tirées d'incidents réels de chaînes GitLab CI sur Kubernetes : des jobs qui attendent, des jobs qui meurent avant leur script, une construction d'image qui échoue, un cache qui ne sert plus, un déploiement refusé, un secret qui fuit dans un journal, des pipelines qui ne se déclenchent plus, des jobs tués en plein vol. Une astreinte en combine trois. Puis tu suis un `git push` jusqu'au pod de job, preuves à l'appui, et tu passes les questions qu'on pose en entretien.

La méthode reste celle des modules précédents : observer avant d'agir, formuler une hypothèse, la tester par la mesure la moins invasive, corriger à la racine, prévenir la récidive. Avec trois règles propres à la CI :
- **GitLab raconte ce qu'il fait, mais à plusieurs endroits.** Le journal du job (y compris ses premières lignes : runner, exécuteur, image, préparation), la page du pipeline (configuration fusionnée, *Full configuration*, erreurs de création), l'état du runner (dernier contact, étiquettes, pause, note de maintenance), les journaux du gestionnaire (`kubectl logs` dans `gitlab-runner`), les événements Kubernetes de `ci-jobs`. Un job « sans erreur » dans GitLab peut avoir un pod en échec dans Kubernetes, et l'inverse.
- **Situe l'étage.** Création du pipeline (règles, `workflow`, configuration, droits) → file d'attente (runner, étiquettes, protection, pause) → gestionnaire du runner (configuration, certificats, jetons) → API Kubernetes (admission, quotas, compte de service) → ordonnanceur et kubelet (ressources, priorité, éviction) → pod de job (helper, image, script) → services joints par le job (Harbor, `s3-01`, `buildkitd`, KAS, `git01`). Chaque étage a sa preuve ; ne corrige pas un étage tant que celui du dessus n'est pas prouvé sain.
- **Le code fait foi.** La configuration du runner est dans les values Helmfile de `plateforme/k8s`, ses secrets dans Vault (`secrets/<composant>.yml`, posés par `outils/secrets-k8s.sh`), l'agent dans `.gitlab/agents/k8s-par1/config.yaml`, les composants dans `plateforme/ci-templates`. Une réparation à chaud est permise pour rétablir le service ; elle est ensuite reportée par une MR, sinon le prochain `helmfile apply` ou le prochain `secrets-k8s.sh` remet la panne ou défait ta réparation.

> **Rappels** : tout se lance depuis `adm01`. Ton kubeconfig personnel sert au quotidien ; ton jeton d'administration GitLab (`~/.config/workbook/gitlab-admin.token`, M01-E05, avec *Admin Mode*) sert aux actions d'administration ; le jeton des checks est en lecture seule. Les journaux de GitLab sont sur `git01` (`/var/log/gitlab/`), ceux du gestionnaire du runner dans ses pods (`kubectl -n gitlab-runner logs`).

## Règles du jeu des pannes (M19-E35 à M19-E43)

- Les pannes s'injectent **depuis `adm01`**, à la racine de ta copie du workbook :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ lab/bin/break 19 35
  ```
  Le script tire une variante au hasard et n'affiche que le **symptôme**, comme un ticket. Chaque panne a 3 ou 4 variantes : refais l'exercice jusqu'à les avoir toutes rencontrées (`--variante N` force une variante, sans dire laquelle est laquelle). Si une variante n'a pas d'effet sur ton lab (ta configuration diffère de celle du corrigé), le script en essaie une autre.
- **Une injection est lente** : le script lance de vrais pipelines pour constater que la panne est effective (de 2 à 10 minutes ; jusqu'à 30 minutes pour l'astreinte). C'est le prix de la règle « jamais de ticket pour une panne inexistante ».
- **Avant d'injecter**, lance le contrôle de l'exercice (`lab/bin/check 19 35`) : il doit être vert. Le script refuse d'ailleurs de casser une chaîne qui ne va pas bien (runner `k8s-par1` hors ligne ou en pause, API de `k8s-par1` muette, canari en échec).
- **Prérequis sur `adm01`** : `curl`, `jq`, `yq` (mikefarah), `perl`, `kubectl` ; ton jeton d'administration GitLab (`WB_GITLAB_ADMIN_TOKEN_FILE`, défaut `~/.config/workbook/gitlab-admin.token`) ; tes identifiants Harbor (`~/.config/workbook/harbor-moi.env`, M13, ou `WB_M19_HARBOR_ADMIN_FILE`) ; le compte GitLab `lucas.martin` actif.
- **Témoin.** À la première injection, le script crée le projet **`formation/ci-pannes`**, le « canari » de la CI, qu'il ne supprime jamais :
  - un composant CI/CD **`canari`** dans `templates/canari/template.yml`, publié par étiquettes `X.Y.Z` (`1.0.0` au départ) et consommé par le `.gitlab-ci.yml` du projet lui-même ;
  - un job `canari` sur l'étiquette `k8s` qui affiche `CANARI cache restauré : oui|non`, liste ses variables `CANARI_*`, vérifie l'accès HTTPS au dépôt avec le jeton `CANARI_JETON`, occupe 120 Mio de mémoire et 100 Mio de disque pendant 45 s, puis écrit son cache ;
  - une variable **`CANARI_JETON`** (masquée, protégée) qui contient un jeton d'accès de projet `canari-lecture` (`read_repository`) ;
  - un pipeline planifié **`canari-quotidien`** (05:17, Europe/Paris), propriété de Lucas Martin, membre *Maintainer* du projet.

  Le canari ne gêne ni le mini-projet ni le module 20 ; tu peux supprimer le projet après la recette (M19-E46). Certaines variantes créent aussi l'espace **`wb-pannes-ci`** (charge de démonstration).
- **Périmètre.** Les pannes n'agissent que sur : le runner `k8s-par1` (API GitLab, ConfigMap et Secret de son chart dans `gitlab-runner`), l'espace `ci-jobs`, le démon `buildkitd` et ses certificats, le robot Harbor du cache de construction, l'identité S3 `ci-cache` de `s3-01`, l'agent `k8s-par1` (Deployment et Secret dans `gitlab-agent`, RoleBinding dans `mediagenda-dev`, configuration dans `plateforme/k8s`), le job `deployer-dev` de `mediagenda/deploiement` (relancé à l'identique) et le témoin. Toute modification d'un dépôt est un **commit identifiable** (auteur Lucas Martin, marqueur `M19-EXX` dans le message ; par MR fusionnée sur `plateforme/k8s`), défait par un commit inverse, jamais par réécriture d'historique. **Aucune donnée n'est supprimée** : ni volume, ni compartiment, ni base, ni projet, ni image.
- **Ne lis pas** les scripts de `corrige/pannes/`, ni `~/.local/state/workbook/` sur `adm01`, ni `/var/lib/workbook/` sur `s3-01` : ils contiennent la cause.
- Une seule panne active à la fois par exercice. Si tu abandonnes : `lab/bin/break 19 35 --annuler` remet l'état sain (filet de sécurité, pas un correctif : compte l'exercice comme non réussi). **Quand tu as réparé**, lance aussi `--annuler` pour **clore** la panne (sinon elle reste marquée active et bloque l'astreinte et le mini-projet) : l'annulation ne rétablit que ce qui est encore dans l'état cassé et ne revient jamais sur ta réparation.
- **Tiens un journal de diagnostic** pour chaque panne dans `docs/kubernetes/journal/` de `~/medisphere` (publié par MR) : heure, hypothèse, commande, résultat observé, conclusion. Les runbooks du palier vont dans `docs/livraison/ci/`, à côté de RB-190 (M19-E22) : **RB-194** « Un pipeline ne se déclenche pas », **RB-195** « Un job échoue avant son script ou est tué », **RB-196** « Construction d'image et cache de CI », **RB-197** « Déploiement par l'agent GitLab », **RB-198** « Un secret apparaît dans un journal de CI ».
- Le **temps cible** est indicatif. Le dépasser n'est pas un échec ; corriger sans comprendre en est un.

> ⚠️ **Effets de bord** : certaines variantes arrêtent **toute** la CI sur Kubernetes (runner en pause, gestionnaire qui ne démarre plus, démon BuildKit inutilisable) ; une variante de M19-E41 **bloque le compte GitLab de Lucas** (`--annuler` le réactive toujours, les pannes suivantes en ont besoin) ; une variante de M19-E42 crée dans `wb-pannes-ci` un pod de priorité haute qui réserve la mémoire libre d'un travailleur. N'injecte pas pendant qu'un pipeline important tourne, et ne lance pas de composant temporaire lourd (SonarQube, Jenkins) pendant le palier.

---

### M19-E35 — Panne : les jobs restent en attente  `BF` `★★`

> **Ticket INC-4635** — *De : Julien Petit*
> *(Le détail du ticket s'affiche à l'injection : selon le cas, tous les jobs `k8s` restent en attente, ou seulement ceux d'une branche.)* Ça bloque nos MR. Ne redémarre rien « pour voir » : trouve la cause.

**Objectifs pédagogiques**
- Distinguer un job **en attente** (aucun runner ne le prend) d'un job **pris mais bloqué** (le runner l'a pris, le pod ne démarre pas) et d'un job qui **échoue à la préparation**.
- Lire ce que GitLab dit d'un job bloqué (message *stuck*, étiquettes demandées, runners éligibles) et ce que dit l'API des runners (statut, `contacted_at`, `paused`, étiquettes, `access_level`, note de maintenance).
- Appliquer et compléter RB-190 (M19-E22).

**Prérequis** : M19-E04, M19-E22 (RB-190), M19-E24 (runner protégé) ; `lab/bin/check 19 35` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : un job est attribué par GitLab à un runner qui le demande (*long polling* de `POST /api/v4/jobs/request`) et qui satisfait **toutes** ses conditions : étiquettes du job incluses dans celles du runner, runner non suspendu, référence protégée si le runner est en `ref_protected`, projet autorisé à utiliser le runner. Une fois pris, le job passe en `running` même si le pod n'existe pas encore : la suite se joue dans Kubernetes (quotas, admission, ordonnancement), et le runner attend le pod au plus `poll_timeout` secondes.

**Injection** : `lab/bin/break 19 35` (4 variantes).

**Travail demandé**
1. Constate sans rien toucher : statut du job (`pending` ou `running`), message affiché par GitLab sur la page du job, étiquettes demandées, référence (protégée ou non). Relis le journal du job s'il a commencé.
2. Interroge les runners par l'API (`GET /runners/all`, puis `GET /runners/:id`) : statut, dernier contact, étiquettes, `paused`, `access_level`, `maintenance_note`. Compare avec ce que le job demande.
3. Si le job a été pris : événements de `ci-jobs` (`kubectl -n ci-jobs get events --sort-by=.lastTimestamp`), objets de l'espace (quotas, LimitRange), journaux du gestionnaire.
4. Trouve la cause racine, retrouve qui l'a introduite et quand, corrige-la à l'endroit qui fait foi (l'API du runner est une source : dis où ce réglage devrait être tracé).
5. Vérifie : un pipeline du canari (`formation/ci-pannes`) passe, aucun job n'attend plus.
6. Complète RB-190 : une entrée par cause (étiquettes, pause, quota, runner protégé), avec le symptôme exact, la commande qui la prouve et le correctif.

**Critères de réussite**
- [ ] Le runner `k8s-par1` est en ligne, actif, avec les étiquettes `k8s` et `kubernetes` et sans jobs non étiquetés ; le runner protégé ne prend que les références protégées.
- [ ] Le quota de `ci-jobs` laisse au moins 2 Gio de mémoire et 4 pods ; aucun job du canari n'attend depuis plus de 10 minutes ; le dernier pipeline de `main` du canari est vert.
- [ ] RB-190 traite les quatre causes ; ton journal contient le message exact de GitLab ou de Kubernetes qui a orienté le diagnostic.

**Vérification** : `lab/bin/check 19 35`

<details><summary>Indice 1</summary>

Un job `pending` n'a pas de pod : inutile de chercher dans Kubernetes. La page du job affiche « This job is stuck… » avec les étiquettes en cause. Avec `GITLAB=https://git01.par1.medisphere.internal`, `curl -s -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(<~/.config/workbook/gitlab-admin.token)") "$GITLAB/api/v4/runners/all?per_page=100" | jq '.[] | {id, description, status, paused}'` liste les runners.
</details>

<details><summary>Indice 2</summary>

Un job `running` dont le journal s'arrête à « Waiting for pod… » ou qui échoue à `prepare environment` : regarde les événements de `ci-jobs` et `kubectl -n ci-jobs describe resourcequota`. Un refus de quota n'apparaît **jamais** comme un pod `Pending` : l'API refuse de créer l'objet. Pour un runner protégé, relis la documentation *Protected runners* : qu'est-ce qu'une « référence protégée », et que voit un job d'une branche quelconque ?
</details>

**Pour aller plus loin** : mesure le délai entre la remise en service du runner et le démarrage du job en attente ; relie-le au *long polling* (`check_interval`, `request_concurrency`) et à la durée de maintien des requêtes par Workhorse (M19-E44).

---

### M19-E36 — Panne : le job échoue avant le script  `BF` `★★`

> **Ticket INC-4636** — *De : Julien Petit (ou Nadia Roussel)*
> *(Le détail s'affiche à l'injection : selon le cas, le job du canari échoue en quelques secondes avant la première ligne de son script, ou le runner ne prend plus rien depuis un redémarrage.)* Remets la CI en route sans contourner les garde-fous.

**Objectifs pédagogiques**
- Situer un échec dans les étapes d'un job de l'exécuteur Kubernetes : récupération de la configuration par le gestionnaire, création du pod (API, admission, compte de service), tirage des images (job, helper, services), démarrage, puis seulement `get_sources` et le script.
- Lire un `ERROR: Job failed (system failure)` jusqu'au message Kubernetes qu'il résume, et les journaux du gestionnaire quand il n'y a même pas de job.
- Corriger dans les values Helmfile et dans Vault, pas seulement dans le cluster.

**Prérequis** : M19-E04, M19-E05 (anatomie d'un pod de job), M19-E24 ; M14-E28 (admission, VAP `medisphere-images`) ; `lab/bin/check 19 36` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : le chart `gitlab/gitlab-runner` rend `runners.config` dans une ConfigMap (clé `config.template.toml`) que le gestionnaire fusionne à son démarrage ; il monte le Secret désigné par `certsSecretName` dans `/home/gitlab-runner/.gitlab-runner/certs/` ; l'enregistrement par jeton `glrt-` est revérifié à chaque démarrage. Les pods de job sont créés avec le compte de service `ci-job` et passent par toute la chaîne d'admission de `ci-jobs`.

**Injection** : `lab/bin/break 19 36` (4 variantes).

**Travail demandé**
1. Lis le journal du job en entier, en partant du haut : quelle est la dernière étape atteinte ? Classe l'échec : configuration, admission, image, démarrage.
2. Remonte au message source : événements de `ci-jobs`, `kubectl -n gitlab-runner logs` du gestionnaire (avec `--previous` s'il redémarre), état des pods du gestionnaire.
3. Compare ce qui tourne avec le code : `helmfile -e par1 -l composant=gitlab-runner diff`, gabarit TOML de la ConfigMap, objets de `ci-jobs` et leur description dans `plateforme/k8s`, `.gitlab-ci.yml` du canari et son historique.
4. Corrige à la racine (values, Vault puis `secrets-k8s.sh`, manifestes de l'espace, ou dépôt du canari) et rejoue le canari.
5. Commence RB-195 « Un job échoue avant son script ou est tué » : une section `## Avant le script` avec, pour chaque étape, le message typique, la commande qui le confirme et le correctif.

**Critères de réussite**
- [ ] Le gestionnaire du runner est entièrement disponible ; l'image *helper* vient d'un projet Harbor qui existe ; le compte de service `ci-job` existe, sans montage automatique de jeton ; aucun pod de `ci-jobs` en `ImagePullBackOff`.
- [ ] Le canari n'utilise aucune image hors de Harbor et son dernier pipeline de `main` est vert.
- [ ] RB-195 contient sa section `Avant le script` ; ta correction est dans le code (MR) et ton journal cite le message source.

**Vérification** : `lab/bin/check 19 36`

<details><summary>Indice 1</summary>

`kubectl -n ci-jobs get events --sort-by=.lastTimestamp | tail -n 20` montre les refus d'admission, les tirages d'image ratés et les comptes de service introuvables. Si aucun job ne démarre du tout, regarde d'abord les pods du gestionnaire : `kubectl -n gitlab-runner get pods` puis `logs --previous`.
</details>

<details><summary>Indice 2</summary>

`kubectl -n gitlab-runner get configmap <cm> -o jsonpath='{.data.config\.template\.toml}'` montre le gabarit réellement monté ; compare-le au rendu de tes values (`helmfile … template`). Un Secret se compare sans afficher son contenu : `kubectl get secret … -o json | jq '.data | map_values(length)'`.
</details>

**Pour aller plus loin** : avec `FF_RETRIEVE_POD_WARNING_EVENTS` (à vérifier dans la liste des *feature flags* de ta version), le runner recopie les événements d'avertissement du pod dans le journal du job. Active-le dans un essai et compare ce que voit un développeur avant et après.

---

### M19-E37 — Panne : la construction d'image échoue  `BF` `★★★`

> **Ticket INC-4637** — *De : Julien Petit*
> Plus aucune image ne se construit par le démon BuildKit partagé : le job de construction de `mediagenda/api` échoue, chez MédiDoc pareil. Les tests passent, c'est seulement l'image. Lucas a « durci » et « rangé » des choses autour de `buildkitd` cette semaine. Il nous faut une release ce soir.

**Objectifs pédagogiques**
- Suivre une construction distante de bout en bout : client `buildctl` dans le pod de job → TLS mutuel → `buildkitd` (espace `buildkit`) → registre (image de base, cache `type=registry`, poussée) → stockage local du démon.
- Prouver chaque maillon avec un outil : `buildctl debug workers`, `openssl s_client`, `hubble observe` (ou les politiques Cilium), API Harbor, `df` dans le pod du démon.
- Respecter les contraintes de l'ADR-0120 : jamais de conteneur privilégié, jamais de TLS désactivé, jamais de contournement de Harbor.

**Prérequis** : M19-E08 (BuildKit rootless, TLS mutuel, CiliumNetworkPolicy, cache), M15 (Hubble, CiliumNetworkPolicy), M13 (robots Harbor) ; `lab/bin/check 19 37` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : la panne touche le démon partagé ou ce qui l'entoure, jamais le code de MédiAgenda. Relance toi-même le pipeline de `main` de `mediagenda/api` pour lire l'erreur. Le cache de construction est poussé par le client (identifiants du job) vers `plateforme/cache-buildkit`.

**Injection** : `lab/bin/break 19 37` (4 variantes).

**Travail demandé**
1. Lis l'erreur de `buildctl` dans le journal du job et classe-la : connexion (TLS, réseau), registre (401, 403, 404), démon (stockage, solveur).
2. Reproduis hors pipeline, depuis un pod jetable de `ci-jobs` qui respecte le profil `restricted` et monte le Secret client : `buildctl … debug workers`, puis une construction minimale. Ne crée rien de privilégié.
3. Prouve le maillon en cause : certificats (émetteur, chaîne, dates : `kubectl get certificate`, `cmctl status certificate`, `openssl`), flux (`hubble observe --to-namespace buildkit`, politiques de l'espace), robot Harbor (état, droits, date d'expiration), stockage du démon.
4. Corrige à la racine, dans le code (`plateforme/k8s`, état OpenTofu `registre`, Vault) ; si tu libères de la place dans le démon, dis ce que tu as supprimé et pourquoi cela ne perd aucune donnée.
5. Rejoue le pipeline de `main` de `mediagenda/api` jusqu'au vert.
6. Commence RB-196 « Construction d'image et cache de CI » : une section `## buildkitd` (un tableau message → maillon → preuve → correctif).

**Critères de réussite**
- [ ] `buildkitd` est disponible ; ses certificats sont émis par `buildkit-ca` et prêts ; aucune politique de `buildkit` ne refuse le trafic des jobs ; le robot du cache de construction est actif.
- [ ] Le dernier pipeline de `main` de `mediagenda/api` est vert, construction comprise, sans conteneur privilégié.
- [ ] RB-196 contient sa section `buildkitd` ; ton journal montre la preuve du maillon en cause.

**Vérification** : `lab/bin/check 19 37`

<details><summary>Indice 1</summary>

`tls: bad certificate`, `unknown authority`, `context deadline exceeded`, `401 Unauthorized`, `no space left on device` désignent chacun un maillon différent. `kubectl get certificates -A -o wide` et `kubectl get issuers,clusterissuers -A` montrent qui émet quoi.
</details>

<details><summary>Indice 2</summary>

Les refus explicites de Cilium (`ingressDeny`, `egressDeny`) l'emportent sur toute autorisation : `kubectl -n buildkit get ciliumnetworkpolicies -o yaml` et `hubble observe --namespace buildkit --verdict DROPPED`. Côté Harbor : `GET /api/v2.0/robots?q=…` avec ton compte, champ `disable`.
</details>

<details><summary>Indice 3</summary>

Dans le pod du démon : `kubectl -n buildkit exec <pod> -- df -h <dossier de données>` puis `du` pour trouver ce qui occupe. `buildctl du` et `buildctl prune` (avec `--keep-storage`) gèrent le cache du démon ; un fichier qui n'est pas du cache n'a rien à faire là.
</details>

**Pour aller plus loin** : ajoute à ton chart local `buildkitd` une sonde de disponibilité qui échoue quand le volume dépasse 90 %, et une règle de ramasse-miettes (`[worker.oci] gc`, `gckeepstorage`) dans `buildkitd.toml` : vérifie les clés exactes dans la documentation de BuildKit 0.34.

---

### M19-E38 — Panne : le cache ne sert plus  `BF` `★★`

> **Ticket INC-4638** — *De : Julien Petit*
> Nos pipelines ont pris plusieurs minutes d'un coup : les dépendances sont retéléchargées à chaque fois. Les jobs sont verts, mais le cache ne sert plus. Le canari de la plateforme le montre aussi : « CANARI cache restauré : non », pipeline après pipeline. Lucas a travaillé sur « l'optimisation des caches ».

**Objectifs pédagogiques**
- Suivre le cycle d'un cache distribué : calcul de la clé, URL présignée générée par le gestionnaire, téléchargement et extraction par le *helper*, archivage des chemins, téléversement vers `s3-01`.
- Lire les avertissements de cache d'un journal de job (ils ne font jamais échouer le job) et les relier à leur étage : clé, chemins, compartiment, identité S3.
- Retrouver une régression dans une version de composant (comparer deux étiquettes, lire la configuration fusionnée).

**Prérequis** : M19-E07 (cache S3 `ci-cache`), M19-E10 (composants), M05 (SeaweedFS, identités) ; `lab/bin/check 19 38` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Injection** : `lab/bin/break 19 38` (4 variantes).

**Travail demandé**
1. Compare les journaux de deux jobs successifs du canari : lignes `Restoring cache`, `Checking cache for …`, `Creating cache …`, `Uploading cache.zip`, avertissements. Note la clé calculée à chaque fois.
2. Vérifie la configuration réellement utilisée : configuration fusionnée du pipeline (*Full configuration* ou API `ci/lint`), version du composant consommée et différence avec la précédente (`git diff 1.0.0..<version> -- templates/`), gabarit TOML du runner (`[runners.cache]`).
3. Vérifie le stockage : le compartiment existe-t-il, l'identité `ci-cache` peut-elle y lire et écrire (`aws s3 ls`, `aws s3 cp` d'un petit fichier puis suppression, avec `s3-ci-cache.env`) ? Les objets de cache sont-ils créés ?
4. Corrige à la racine (values, identités de `s3-01` par le rôle Ansible, ou nouvelle version du composant) ; si tu corriges le composant, publie une version (jamais de réécriture d'une étiquette existante).
5. Complète RB-196 avec une section `## Cache` : symptôme, ligne de journal, étage, correctif.

**Critères de réussite**
- [ ] Le gabarit du runner désigne le compartiment `ci-cache`, que l'identité `ci-cache` peut lister.
- [ ] Le composant canari consommé calcule sa clé à partir d'un fichier de verrou et ne cache que des chemins du projet ; le dernier canari affiche `CANARI cache restauré : oui`.
- [ ] RB-196 contient sa section `Cache` ; ton journal cite la ligne de journal qui a orienté le diagnostic.

**Vérification** : `lab/bin/check 19 38`

<details><summary>Indice 1</summary>

Un cache qui n'est jamais retrouvé a trois explications : la clé change à chaque fois, rien n'a été archivé (chemins), ou l'archive n'a pas pu être lue ou écrite (stockage). Le journal du job dit lesquelles ; cherche les lignes `WARNING` autour de `cache`.
</details>

<details><summary>Indice 2</summary>

`cache:paths` n'accepte que des chemins **dans** le répertoire du projet (documentation *Caching in GitLab CI/CD*). Les URL de cache sont présignées par le gestionnaire avec l'identité configurée : une erreur `403` ou `404` vient de `s3-01`, pas du job. Sur `s3-01`, l'identité se lit dans le fichier d'identités de la passerelle (M05-E10).
</details>

**Pour aller plus loin** : mesure le gain réel du cache sur le pipeline de MR de `mediagenda/api` (M19-E23) et calcule à partir de quelle taille d'archive il devient plus lent de télécharger le cache que de réinstaller les dépendances depuis le miroir.

---

### M19-E39 — Panne : le déploiement en dev est refusé  `BF` `★★★`

> **Ticket INC-4639** — *De : Julien Petit*
> Notre MR de promotion vient d'être fusionnée dans `mediagenda/deploiement`, mais le job `deployer-dev` échoue : rien n'est arrivé dans `mediagenda-dev`. Ça marchait jeudi. Lucas a « fait de la sécurité » sur l'agent cette semaine. On ne revient pas aux `kubectl` depuis `adm01` : répare la chaîne, puis relance le job.

**Objectifs pédagogiques**
- Décomposer le *CI/CD workflow* de l'agent : contexte kubeconfig injecté dans le job, autorisation `ci_access` du projet, connexion de `agentk` à KAS (jeton, adresse, TLS), identité Kubernetes utilisée (compte de service de l'agent) et ses droits.
- Lire les journaux de `agentk` et de KAS (`/var/log/gitlab/gitlab-kas/` sur `git01`), et l'état de l'agent dans GitLab.
- Garder le modèle de droits du M19-E18 : aucun droit au-delà de `mediagenda-dev` et `wb-essais`, pas d'usurpation d'identité (Premium).

**Prérequis** : M19-E18, M19-E17 ; `lab/bin/check 19 39` vert avant l'injection (un job `deployer-dev` réussi sur `main`).
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : le script de panne relance le dernier job `deployer-dev` réussi : il réapplique le même overlay et ne change rien à `mediagenda-dev` quand tout va bien. Le jeton de l'agent est rangé dans Vault (`secrets/gitlab-agent.yml`) et posé par `outils/secrets-k8s.sh`.

**Injection** : `lab/bin/break 19 39` (4 variantes).

**Travail demandé**
1. Lis l'erreur du job : contexte absent, connexion refusée, `Forbidden` de l'API Kubernetes ? Chaque cas désigne un étage différent.
2. Vérifie l'agent côté GitLab (page *Operate > Kubernetes clusters* de `plateforme/k8s`, `GET /projects/:id/cluster_agents` et ses jetons) et côté cluster (pods de `gitlab-agent`, `kubectl logs`, arguments du Deployment).
3. Vérifie l'autorisation : `config.yaml` de l'agent sur `main` de `plateforme/k8s` et son historique, droits du compte de service (`kubectl auth can-i --as=system:serviceaccount:gitlab-agent:<sa> -n mediagenda-dev …`).
4. Corrige à la racine par le code (MR sur `plateforme/k8s`, Vault puis `secrets-k8s.sh`, values Helmfile) ; un jeton d'agent ne se « répare » pas : il se remplace.
5. Relance `deployer-dev` et constate le déploiement dans `mediagenda-dev`.
6. Rédige RB-197 « Déploiement par l'agent GitLab » : arbre de décision par étage, avec la preuve et le correctif de chacun.

**Critères de réussite**
- [ ] L'agent est disponible et pointe vers `git01.par1.medisphere.internal` ; le compte de service de l'agent a ses droits dans `mediagenda-dev` (et pas ailleurs que dans `mediagenda-dev` et `wb-essais`) ; `ci_access` autorise le groupe `mediagenda`.
- [ ] Le dernier job `deployer-dev` de `main` a réussi.
- [ ] RB-197 existe ; tout correctif est tracé dans le code (MR ou Vault), ton journal cite l'erreur d'origine.

**Vérification** : `lab/bin/check 19 39`

<details><summary>Indice 1</summary>

Dans le job, `kubectl config get-contexts` liste les contextes que GitLab a injectés : un contexte manquant ne vient pas de Kubernetes. `kubectl -n gitlab-agent logs deploy/<agent> | tail` dit si l'agent est connecté et pourquoi il ne l'est pas.
</details>

<details><summary>Indice 2</summary>

`git log -p -- .gitlab/agents/k8s-par1/config.yaml` dans `plateforme/k8s` ; `kubectl -n mediagenda-dev get rolebindings -o wide` ; `kubectl -n gitlab-agent get deploy -o jsonpath='{..args}'`. Pour les jetons : `GET /projects/:id/cluster_agents/:agent_id/tokens` montre les jetons actifs et leur dernier usage (`last_used_at`).
</details>

**Pour aller plus loin** : prépare la rotation planifiée du jeton de l'agent (deux jetons actifs au plus par agent) sans coupure : ordre des opérations, contrôle, retrait de l'ancien. Écris-la dans RB-197.

---

### M19-E40 — Panne : un secret apparaît dans un journal de job  `BF` `★★★`

> **Ticket SEC-2040** — *De : Sophie Laurent (RSSI)* — priorité haute
> Un développeur me signale qu'en lisant le journal du dernier job du canari (`formation/ci-pannes`), il a vu passer ce qui ressemble au jeton `CANARI_JETON`, ou à une valeur dérivée. La variable est censée être masquée. Je veux : la fuite arrêtée, le secret considéré comme compromis et remplacé, les journaux exposés effacés, et une explication écrite de ce qui a contourné le masquage.

**Objectifs pédagogiques**
- Comprendre ce que garantit le masquage de GitLab (remplacement de la valeur exacte dans le journal) et ce qu'il ne garantit pas (valeurs transformées, trace de débogage, variable démasquée, fichiers d'artefacts).
- Traiter une fuite comme un incident de sécurité : confinement, rotation, effacement des journaux (et des artefacts), recherche d'autres expositions, prévention.
- Distinguer les mécanismes : variable masquée, masquée et cachée, protégée, `CI_DEBUG_TRACE`, trace `set -x` d'un shell.

**Prérequis** : M19-E25 (secrets en CI, variables masquées et cachées) ; `lab/bin/check 19 40` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Injection** : `lab/bin/break 19 40` (3 variantes).

**Travail demandé**
1. **Confiner d'abord** : trouve tous les jobs qui ont exposé la valeur (le canari tourne peut-être aussi la nuit). Note leurs identifiants dans ton journal, **sans recopier la valeur**.
2. Trouve ce qui a contourné le masquage : attributs de la variable, variables de débogage du projet (et de son groupe, et de l'instance), version du composant consommée et son contenu.
3. **Remplace le secret** : rotation du jeton d'accès de projet `canari-lecture` (l'ancien doit être révoqué) et mise à jour de `CANARI_JETON`, avec les bons attributs.
4. **Efface les journaux exposés** (et leurs artefacts) ; vérifie qu'ils ne sont plus lisibles.
5. Corrige la cause dans le code ou le réglage concerné ; rejoue le canari et vérifie que le journal montre `CANARI_JETON=[MASKED]`.
6. Rédige RB-198 « Un secret apparaît dans un journal de CI » (déroulé, rôles, commandes, preuves à garder sans le secret) et réponds à Sophie en dix lignes dans le ticket (cause, exposition, actions, prévention).

**Critères de réussite**
- [ ] `CANARI_JETON` est masquée et protégée ; aucune variable `CI_DEBUG_*` dans le projet ; le composant consommé ne trace plus les commandes.
- [ ] Le jeton exposé est révoqué (rotation faite) ; les journaux des jobs exposés sont effacés ; le dernier canari est vert et masque le jeton.
- [ ] RB-198 existe, ne contient aucun secret, et décrit la rotation et l'effacement.

**Vérification** : `lab/bin/check 19 40`

<details><summary>Indice 1</summary>

Le masquage remplace une chaîne **exacte**. Cherche dans le journal autre chose que la valeur elle-même : une ligne qui commence par `+`, un en-tête `Authorization`, une chaîne base64. La documentation *CI/CD variables* (sections *Mask a CI/CD variable* et *Enable debug logging*) dit ce que le masquage ne couvre pas.
</details>

<details><summary>Indice 2</summary>

API : `GET /projects/:id/variables/:key` (attributs ; la valeur n'est pas à afficher), `POST /projects/:id/access_tokens/:token_id/rotate`, `POST /projects/:id/jobs/:job_id/erase`. L'effacement d'un job retire son journal **et** ses artefacts.
</details>

**Pour aller plus loin** : écris un job de contrôle (dans le composant `securite`) qui échoue si un journal de job contient un motif de jeton GitLab (`glpat-`, `glrt-`, `glcbt-`…) ou une chaîne base64 d'une variable sensible ; discute ses limites avec Sophie.

---

### M19-E41 — Panne : les pipelines ne se déclenchent plus  `BF` `★★`

> **Ticket INC-4641** — *De : Julien Petit (ou Nadia Roussel)*
> *(Le détail s'affiche à l'injection : selon le cas, les commits poussés sur `main` du canari ne déclenchent plus rien, ou le pipeline planifié de la nuit n'a pas tourné.)* Pas d'erreur, pas de pipeline en échec : rien. Retrouve pourquoi, sans casser ce qui est voulu.

**Objectifs pédagogiques**
- Connaître toutes les raisons pour lesquelles GitLab ne crée **pas** de pipeline, sans erreur visible : `workflow:rules`, `rules` qui ne retiennent aucun job, chemin de configuration, fonction CI/CD désactivée, `[skip ci]`, options de poussée, pipelines planifiés dont le propriétaire ne peut plus agir.
- Tester une configuration sans pousser : *Pipeline editor*, API `ci/lint` (avec `dry_run` et la référence), configuration fusionnée.
- Comprendre au nom de qui tourne un pipeline planifié, et ce qui arrive quand cette personne part.

**Prérequis** : M19-E06 (`workflow:rules`), M19-E10 (composants), M01 (pipelines planifiés) ; `lab/bin/check 19 41` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Injection** : `lab/bin/break 19 41` (4 variantes).

**Travail demandé**
1. Prouve l'absence : liste des pipelines du projet par commit (`GET /projects/:id/pipelines?sha=…`) et par source (`source=schedule`) ; compare avec l'historique des commits.
2. Vérifie les réglages du projet qui conditionnent la création (fonctions, chemin de configuration) et l'historique des changements (*audit events* du projet si disponibles, sinon l'API du projet et la mémoire de l'équipe).
3. Fais évaluer la configuration à GitLab sans pousser (`POST /projects/:id/ci/lint` avec `dry_run=true` et `ref=main`) et lis ce qu'elle produit ; compare deux versions du composant consommé.
4. Pour un pipeline planifié : propriétaire, état de son compte, ce que montre la page *Schedules* ; corrige proprement (qui doit être propriétaire d'un pipeline planifié d'équipe ?).
5. Corrige, puis prouve qu'un commit sur `main` crée de nouveau un pipeline (et que les MR ne créent pas de doublon).
6. Rédige RB-194 « Un pipeline ne se déclenche pas » : une ligne par cause, la preuve et le correctif, et une règle d'équipe sur les propriétaires des pipelines planifiés.

**Critères de réussite**
- [ ] CI/CD activée sur le canari, chemin de configuration par défaut ; le dernier commit de `main` a son pipeline ; le composant consommé garde les pipelines de branche.
- [ ] Le pipeline planifié `canari-quotidien` est actif et son propriétaire est un compte actif.
- [ ] RB-194 existe et traite `workflow`, chemin, CI/CD désactivée et pipelines planifiés.

**Vérification** : `lab/bin/check 19 41`

<details><summary>Indice 1</summary>

Un pipeline qui n'existe pas n'a pas de journal : la preuve est dans la configuration. `GET /projects/:id` (`builds_access_level`, `ci_config_path`) et `POST /projects/:id/ci/lint` répondent en quelques secondes. Le message « Pipeline filtered out by workflow rules » n'apparaît que dans certains cas (création manuelle ou par l'API) : essaie de créer un pipeline à la main.
</details>

<details><summary>Indice 2</summary>

Page *Build > Pipeline schedules* : colonne *Owner*. Un pipeline planifié tourne avec les droits de son propriétaire (documentation *Scheduled pipelines*, section *Take ownership*). Un compte bloqué ne déclenche plus rien.
</details>

**Pour aller plus loin** : écris un contrôle (dans le pipeline planifié de M19-E32) qui signale tout pipeline planifié dont le propriétaire est bloqué ou n'est plus membre du projet.

---

### M19-E42 — Panne : le job est tué en cours de route  `BF` `★★★`

> **Ticket INC-4642** — *De : Julien Petit*
> Le job du canari (`formation/ci-pannes`) meurt en plein milieu : il démarre, affiche ses premières lignes, puis le journal s'arrête net et le job passe en échec, sans erreur de notre script. Chez nous, les tests d'intégration ont le même comportement depuis hier. Lucas a fait « de l'optimisation de ressources » sur le cluster. Trouve qui tue le job.

**Objectifs pédagogiques**
- Reconnaître les façons dont un pod de job meurt sans que son script le décide : noyau (OOM, `exitCode` 137), délai actif (`activeDeadlineSeconds`, `DeadlineExceeded`), kubelet (éviction pour stockage éphémère), ordonnanceur (préemption par priorité), et ce que montre chacune.
- Attraper la preuve à temps : les pods de job sont supprimés à la fin du job (événements de l'espace, `kubectl get pods -w`, journal d'audit M14-E27, `KUBERNETES_*` de surcharge pour garder des traces).
- Relier chaque cause à son réglage : gabarit du runner (limites et maximums de surcharge), politiques d'admission, `PriorityClass`.

**Prérequis** : M19-E05, M19-E27 (capacité, PriorityClass `medisphere-ci`) ; M14-E38 (façons de mourir d'un conteneur), M14-E28 (admission) ; `lab/bin/check 19 42` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Injection** : `lab/bin/break 19 42` (4 variantes).

**Travail demandé**
1. Lance un pipeline du canari en surveillant `ci-jobs` (`kubectl -n ci-jobs get pods -w` et `kubectl -n ci-jobs get events -w` dans deux terminaux) ; relève l'état final du pod (`phase`, `reason`, `containerStatuses[].state.terminated`) avant qu'il disparaisse.
2. Classe la mort (noyau, délai, kubelet, ordonnanceur) et trouve l'objet ou le réglage qui l'a causée : `spec.containers[].resources` réellement appliqués, `spec.activeDeadlineSeconds` (et qui l'a posé : runner ou admission ?), politiques de mutation, pods de haute priorité sur le même nœud.
3. Corrige à la racine, dans le code ; si la cause est une charge d'une autre équipe, dis ce que tu demandes à son auteur et ce qui doit l'empêcher la prochaine fois.
4. Rejoue le canari jusqu'à `CANARI terminé`.
5. Complète RB-195 avec une section `## Job tué` : un tableau « ce que je vois → qui a tué → réglage → commande de preuve ».

**Critères de réussite**
- [ ] Les limites des jobs dans le gabarit du runner sont raisonnables (au moins 256 Mio de mémoire et 1 Gio de stockage éphémère s'ils sont fixés) ; aucune politique de mutation n'impose `activeDeadlineSeconds` ; aucune charge de démonstration prioritaire ne reste.
- [ ] Les pods de job portent la PriorityClass `medisphere-ci` ; le dernier canari va au bout.
- [ ] RB-195 contient sa section `Job tué` (OOMKilled, délai, éviction, préemption) ; ton journal contient la preuve capturée avant la disparition du pod.

**Vérification** : `lab/bin/check 19 42`

<details><summary>Indice 1</summary>

`kubectl -n ci-jobs get events --sort-by=.lastTimestamp` garde les raisons après la disparition du pod : `OOMKilling`, `Evicted`, `Preempted`, `DeadlineExceeded`. Avec Kubernetes 1.36, les politiques de mutation déclaratives existent : `kubectl get mutatingadmissionpolicies,mutatingadmissionpolicybindings`.
</details>

<details><summary>Indice 2</summary>

Pour une préemption : `kubectl get pods -A --field-selector spec.nodeName=<nœud> -o custom-columns=…,PRIO:.spec.priority,CLASSE:.spec.priorityClassName` et `kubectl get priorityclass`. Pour les limites appliquées : la ConfigMap du runner (`memory_limit`, `ephemeral_storage_limit` et leurs `*_overwrite_max_allowed`).
</details>

**Pour aller plus loin** : compare le comportement avec et sans `FF_USE_POD_ACTIVE_DEADLINE_SECONDS` (documentation *Pod lifecycle* de l'exécuteur Kubernetes) et avec l'option `pod_disruption_budget` (Runner 18.10+) : laquelle protège d'un `kubectl drain`, laquelle d'une préemption, laquelle d'aucune des deux ?

---

### M19-E43 — Astreinte : la chaîne de livraison en détresse  `BF` `★★★★`

> **Ticket INC-4643** — *De : Nadia Roussel (responsable astreinte)* — priorité P1
> Tu es d'astreinte. Mardi, 7 h 40 : la mise en production de MédiAgenda est prévue à 14 h et plusieurs remontées arrivent sur la chaîne de livraison (le détail s'affiche à l'injection). Julien doit pouvoir construire, analyser, signer et promouvoir sa version avant midi. Tiens-moi informée toutes les 30 minutes, puis rédige le post-mortem avec le modèle de l'équipe.

**Objectifs pédagogiques**
- Gérer un incident à causes multiples sur une chaîne de livraison : trier, prioriser par dépendances (création des pipelines, puis prise des jobs, puis préparation, puis services joints, puis déploiement), éviter qu'une panne en masque une autre.
- Communiquer sur l'impact métier (qui ne peut plus livrer quoi) et décider d'un contournement acceptable, ou de l'absence de contournement.
- Rédiger un post-mortem sans recherche de coupable.

**Prérequis** : M19-E35 à M19-E42 (au moins une variante de chacun).
**Durée indicative** : 2 h de rétablissement + 45 min de post-mortem.

**Contexte technique** : le script tire **trois** pannes distinctes parmi celles de M19-E35 à M19-E42 (au plus une parmi E36, E38, E40, E41 et E42), avec une variante au hasard pour chacune, et les injecte ensemble. Les symptômes peuvent se recouvrir (un runner arrêté masque un cache cassé ; un job tué ressemble à un job qui échoue avant son script). `--variante N` (1 à 16) force le trio, pas les variantes. `--annuler` retire les trois. Modèle de post-mortem : [`modules/00-lab/ressources/M00-E46/modele-post-mortem.md`](../../00-lab/ressources/M00-E46/modele-post-mortem.md).

**Injection** : `lab/bin/break 19 43`

**Travail demandé**
1. **Triage (10 min max)** : liste les symptômes, leur impact (qui ne peut plus livrer quoi), une hypothèse de regroupement. Vérifie d'abord tes instruments : ton jeton d'administration, `kubectl`, l'accès aux journaux de `git01`, le canari. Envoie la première communication.
2. **Diagnostic** : traite les pannes dans un ordre que tu justifies par les dépendances. Tiens ton journal horodaté ; garde les sorties qui prouvent chaque cause (jamais un secret).
3. **Rétablissement** : corrige chaque cause racine dans le code ; après chaque correction, rejoue le canari et les contrôles du palier.
4. **Clôture** : communication de fin d'incident, `--annuler` pour clore, puis post-mortem dans `docs/kubernetes/post-mortems/AAAA-MM-JJ-INC-4643.md`, publié par MR.

**Critères de réussite**
- [ ] Toutes les vérifications de M19-E35 à M19-E42 sont vertes (le contrôle les rejoue toutes) et aucune panne n'est encore marquée active.
- [ ] Le post-mortem existe, contient une chronologie horodatée, les trois causes racines, des extraits de preuves (journaux de jobs, `kubectl`, API GitLab), l'analyse de la détection (qu'est-ce qui aurait dû alerter avant Julien ?), des actions correctives avec responsable et échéance, et aucun secret.
- [ ] Le journal contient au moins quatre communications d'incident espacées d'environ 30 minutes.

**Vérification** : `lab/bin/check 19 43`

<details><summary>Indice 1</summary>

Ordre des dépendances : un pipeline doit d'abord **exister** (E41), puis être **pris** (E35, gestionnaire du runner), puis **démarrer** (E36), puis **aller au bout** (E42) ; ensuite seulement les services qu'il joint (E37, E38, E40) et la suite de la chaîne (E39). Une panne plus haut fausse les tests de tout ce qui est en dessous.
</details>

<details><summary>Indice 2</summary>

Les contrôles `lab/bin/check 19 35` à `19 42` sont des sondes ciblées : lance-les pendant le triage pour cartographier ce qui est rouge. Un contrôle rouge n'est pas forcément une panne injectée : ce peut être la conséquence d'une autre (pas de canari vert tant qu'aucun job ne démarre).
</details>

**Pour aller plus loin** : liste les trois métriques qu'exposent le gestionnaire du runner (port de métriques du chart) et GitLab qui auraient détecté chacune de tes pannes avant Julien ; garde la liste pour le module 21.

---

### M19-E44 — Sous le capot : du `git push` au pod de job  `LAB` `★★★★`

> **Ticket PLAT-2044** — *De : Karim Benali*
> Pendant les pannes, tout le monde a parlé du runner qui « demande des jobs », de GitLab qui « crée le pipeline », du pod qui « apparaît ». Je veux que tu saches **montrer** le chemin complet : du `git push` jusqu'au téléversement des artefacts, en prouvant chaque étape dans un journal différent (GitLab, Sidekiq, Workhorse, gestionnaire du runner, audit de l'API Kubernetes, pod). Compte rendu pour les prochains arrivants.

**Objectifs pédagogiques**
- Suivre la réception d'un push (gitlab-shell ou Workhorse, Gitaly, *hook* `post-receive`) et la création asynchrone du pipeline par Sidekiq.
- Comprendre l'attribution des jobs : file, *long polling* de `POST /api/v4/jobs/request` maintenu par Workhorse, réponse `201` avec la charge utile du job ou `204` sans job, jeton de job.
- Suivre l'exécuteur Kubernetes : requêtes du compte de service du gestionnaire vers l'API (création du pod, attachement, suppression), conteneurs `build` et `helper`, journal envoyé par morceaux, artefacts téléversés par le *helper* à travers Workhorse.

**Prérequis** : M19-E05, M19-E09, M19-E35 à M19-E42 ; M14-E27 (journal d'audit de l'API), M14-E44 (sous le capot de Kubernetes).
**Durée indicative** : 3 h.

**Contexte technique**
- Travaille avec le projet `formation/ci-labo` : ajoute sur une branche `capot` un job `capot` (étiquette `k8s`) qui affiche l'heure, dort 120 s (le temps d'observer le pod) et produit un artefact `capot.txt`.
- Journaux de `git01` (lecture avec `sudo`) : `/var/log/gitlab/gitlab-rails/production_json.log` et `api_json.log` (requêtes Rails et API, une ligne JSON par requête, `correlation_id`), `/var/log/gitlab/sidekiq/current` (travaux asynchrones, JSON), `/var/log/gitlab/gitlab-workhorse/current`, `/var/log/gitlab/gitlab-shell/gitlab-shell.log` (poussées SSH). `jq` lit tout cela ; `sudo gitlab-ctl tail <service>` suit en direct.
- Gestionnaire du runner : `kubectl -n gitlab-runner logs -f deploy/<gestionnaire>` ; le niveau de journal se règle par `logLevel` dans les values (passe-le en `debug` le temps de l'exercice, par Helmfile, puis remets-le).
- Journal d'audit de l'API Kubernetes (M14-E27) sur les nœuds de contrôle.
- Squelette du compte rendu : [`ressources/E44-sous-le-capot/sous-le-capot.squelette.md`](../ressources/E44-sous-le-capot/sous-le-capot.squelette.md).

> ⚠️ **Attention** : les journaux de GitLab et du runner en `debug` contiennent des identifiants de jobs et, selon les versions, des fragments d'URL signées : ne les copie jamais en entier dans le compte rendu. Le jeton de job (`CI_JOB_TOKEN`) et le jeton `glrt-` ne doivent apparaître nulle part. Remets `logLevel` à sa valeur d'origine à la fin (vérifie par `helmfile diff`).

**Travail demandé**
1. **Le push.** Note l'heure, pousse la branche `capot` en SSH. Sur `git01`, retrouve la poussée dans `gitlab-shell.log`, les appels internes (`/api/v4/internal/allowed`, `/api/v4/internal/post_receive`) dans `api_json.log`, puis le travail Sidekiq déclenché par la réception (`PostReceive`) et ce qu'il enchaîne.
2. **Le pipeline.** Retrouve dans Sidekiq la création et le traitement du pipeline (classes `CreatePipelineWorker`, `Ci::InitialPipelineProcessWorker`, `PipelineProcessWorker` ou leurs équivalents dans ta version : cherche par `correlation_id` et par l'identifiant du pipeline). Relève la durée entre la poussée et le passage du job à `pending`.
3. **La file et le runner.** Dans `api_json.log` et le journal de Workhorse, retrouve les requêtes `POST /api/v4/jobs/request` du runner : combien de temps chacune est maintenue, ce qu'elle renvoie quand il n'y a pas de job, et la requête qui reçoit le tien (`201`). Dans le journal du gestionnaire, retrouve la prise du job et la création du pod.
4. **Le pod.** Pendant les 120 s : `kubectl -n ci-jobs get pod <pod> -o yaml` (conteneurs, init, volumes, compte de service, `activeDeadlineSeconds`, priorité) ; dans le journal d'audit, toutes les requêtes du compte de service du gestionnaire pour ce pod (création, `attach` ou `exec`, lectures, suppression), avec leur heure.
5. **Le journal et les artefacts.** Dans `api_json.log`, retrouve l'envoi du journal par morceaux (`PATCH /api/v4/jobs/:id/trace`), la mise à jour d'état (`PUT /api/v4/jobs/:id`) et le téléversement de `capot.txt` (`…/artifacts/authorize` puis `…/artifacts`, à travers Workhorse). Où est rangé l'artefact sur `git01` (ou dans le stockage objet) ?
6. **Compte rendu.** Rédige `docs/livraison/ci/sous-le-capot.md` avec exactement ces sections : `## Réception du push`, `## Création du pipeline`, `## File d'attente et runner (long polling)`, `## Le pod de job (Kubernetes)`, `## Artefacts et fin du job`, `## Réponses aux questions`. Pour chaque étape : l'heure relevée, la ligne de journal (raccourcie, sans secret) et une phrase d'explication ; cite l'identifiant de ton job. Publie-le par MR, remets `logLevel` et supprime la branche `capot`.

**Questions d'analyse** (à traiter dans le compte rendu)
1. Pourquoi le pipeline est-il créé de façon asynchrone par Sidekiq et pas pendant le `git push` ? Que voit le développeur si Sidekiq est saturé ?
2. Pourquoi le runner fait-il du *long polling* plutôt que d'interroger GitLab toutes les secondes ? Qui maintient la requête ouverte, combien de temps, et qu'est-ce qui la libère quand un job arrive ?
3. Que contient la réponse `201` de `jobs/request` (sans recopier de valeur) ? Quelle est la durée de vie du jeton de job et que peut-il faire ?
4. Pourquoi le gestionnaire a-t-il besoin de droits `create` sur `pods` et `pods/attach` (ou `pods/exec`) dans `ci-jobs`, et pourquoi le pod de job, lui, n'en a aucun ?
5. Le journal du job arrive par morceaux pendant l'exécution : où GitLab les range-t-il avant de les consolider, et que se passe-t-il si le gestionnaire meurt en plein job ?
6. Pourquoi les artefacts passent-ils par Workhorse plutôt que par Rails ? Quelle limite de taille s'applique et où se règle-t-elle ?
7. Dans tout ce chemin, quels éléments ne sont pas redondants dans le lab, et que se passe-t-il pour les jobs en cours si chacun tombe ?

**Critères de réussite**
- [ ] Le compte rendu existe, est commité, contient les six sections, cite `production_json.log` ou `api_json.log`, Sidekiq, `jobs/request`, l'audit Kubernetes, le *helper* et les artefacts, et l'identifiant de ton job.
- [ ] Les 7 questions sont traitées ; aucun jeton, aucune clé, aucune URL signée dans le compte rendu.
- [ ] `logLevel` du runner est revenu à sa valeur du code (`helmfile diff` vide) ; la branche `capot` est supprimée.

**Vérification** : `lab/bin/check 19 44`

<details><summary>Indice 1</summary>

Chaque requête Rails porte un `correlation_id` qu'on retrouve dans Sidekiq pour les travaux qu'elle a mis en file : `sudo jq -c 'select(.correlation_id == "<id>")' /var/log/gitlab/sidekiq/current`. Pour l'API : `sudo jq -c 'select(.route == "/api/:version/jobs/request") | {time, status, duration_s}' /var/log/gitlab/gitlab-rails/api_json.log | tail`.
</details>

<details><summary>Indice 2</summary>

Le *long polling* est porté par Workhorse (réglage `gitlab_workhorse['api_ci_long_polling_duration']` dans `gitlab.rb`, à vérifier dans la documentation d'omnibus de ta version) : une réponse sans job arrive au bout de ce délai, une réponse avec job dès qu'il est attribué. Dans le journal d'audit : `jq 'select(.user.username | startswith("system:serviceaccount:gitlab-runner:")) | select(.objectRef.namespace == "ci-jobs")'`.
</details>

<details><summary>Indice 3</summary>

Pour attraper le pod, `kubectl -n ci-jobs get pods -w` dans un terminal dès la poussée. Les conteneurs d'un pod de job et leur rôle sont décrits dans ton livrable de M19-E05 (`anatomie-job.md`) : complète-le s'il te manque une pièce.
</details>

**Pour aller plus loin** : refais le parcours avec `runner02` (exécuteur `docker`) et mets les deux chemins côte à côte : quelles étapes sont identiques, lesquelles changent, et lesquelles n'existent que dans Kubernetes ?

---

### M19-E45 — Questions expert : intégration continue  `Q` `★★★`

> **Ticket PLAT-2045** — *De : Karim Benali*
> Dernière étape avant la recette de la chaîne de CI : ces questions, je les pose en entretien pour un poste d'ingénieur plateforme. Réponds par écrit, en argumentant. Pas de recherche pendant la première passe ; vérifie ensuite dans la documentation et corrige-toi en couleur.

**Objectifs pédagogiques**
- Consolider la compréhension des mécanismes internes de GitLab CI, des runners Kubernetes et de la chaîne d'approvisionnement manipulés dans ce module.
- S'entraîner à argumenter une réponse technique comme en entretien ou en revue d'architecture.

**Prérequis** : paliers 1 à 3 du module, M19-E44.
**Durée indicative** : 2 h 30.

**Questions**

1. Décris le chemin d'un `git push` sur une branche jusqu'au premier octet du journal du job : composants, ordre, ce qui est synchrone et ce qui ne l'est pas.
2. QCM — Un job porte `tags: [k8s, protege]`. Le runner A a les étiquettes `k8s, kubernetes` ; le runner B a `protege` et `access_level: ref_protected`. Le job est sur une branche non protégée. Que se passe-t-il ?
   a) A le prend : une étiquette commune suffit ; b) B le prend : l'étiquette la plus précise gagne ; c) personne ne le prend : il faut un runner qui porte **toutes** les étiquettes, et B ne prend de toute façon que les références protégées ; d) GitLab le répartit entre A et B.
3. `rules:changes` dans un pipeline de branche poussé pour la première fois, dans un pipeline planifié, dans un pipeline de MR : sur quoi la comparaison porte-t-elle dans chaque cas, et quel piège en découle ?
4. Pourquoi les composants CI/CD (`spec:inputs`, `$[[ inputs.x ]]`) sont-ils plus sûrs que des `include:` de fichiers avec des variables ? Quand les entrées sont-elles interpolées, et qu'est-ce que cela empêche ?
5. QCM — Un composant est consommé avec `@~latest`. Lucas publie une version cassée. Que se passe-t-il ?
   a) rien : `~latest` désigne la dernière version vérifiée par le catalogue ; b) tous les pipelines suivants des projets consommateurs utilisent la version cassée ; c) seuls les nouveaux projets la reçoivent ; d) GitLab refuse de publier une version qui casse des consommateurs.
6. Masquage d'une variable : ce qu'il garantit, ce qu'il ne garantit pas (trois contournements involontaires), et ce qu'ajoute « masquée et cachée ».
7. `CI_JOB_TOKEN` : que permet-il, pendant combien de temps, et à quoi sert la liste d'autorisation entrante ? Pourquoi est-il préférable à un jeton de projet pour cloner un autre dépôt du même groupe ?
8. Jeton d'identité (`id_tokens`) : en quoi un JWT signé par GitLab avec `aud` et des revendications (`project_path`, `ref_protected`) change-t-il la gestion des secrets en CI ? Qu'est-ce qui doit être vérifié côté consommateur (M25) ?
9. QCM — Un job du runner Kubernetes est tué au bout de 60 minutes alors que son `timeout` vaut 2 h. Quelle est la cause la plus probable ?
   a) le `maximum_timeout` du runner vaut 1 h ; b) `poll_timeout` ; c) `activeDeadlineSeconds` posé par le runner ; d) le cache a expiré.
10. Pourquoi un démon BuildKit **partagé** et *rootless* plutôt que Docker-in-Docker privilégié, Kaniko, ou BuildKit sans démon dans chaque job ? Quels risques le démon partagé introduit-il (isolation entre projets, cache empoisonné) et comment les réduis-tu ?
11. Cache contre artefacts : différences de garanties, de portée, de stockage ; pourquoi ne faut-il jamais compter sur le cache pour transmettre un résultat d'un job à l'autre ?
12. Le runner Kubernetes et la préemption : pourquoi une PriorityClass basse pour les jobs, quel effet sur la file en cas de saturation, et pourquoi un PodDisruptionBudget par job ne protège-t-il pas d'une préemption ?
13. Un pipeline planifié appartient à un compte bloqué. Que se passe-t-il, et quelle règle d'équipe proposes-tu (compte de service, *take ownership*, audit) ?
14. Environnements protégés et approbations de déploiement sont Premium. Comment MédiSphère obtient-elle une garantie comparable en Free (branches protégées, runner protégé, variables protégées, `resource_group`, MR obligatoire sur `mediagenda/deploiement`) et que reste-t-il de moins bien ?
15. Monter GitLab de 19.4 à 19.5 : ordre GitLab / runners / agent, règle de compatibilité des versions, migrations d'arrière-plan, retour arrière. Pourquoi la sauvegarde PBS seule ne suffit-elle pas ?
16. Tu dois prouver à un auditeur HDS qu'une image en production a été construite par la CI à partir d'un commit relu. Quelles preuves présentes-tu (signature, provenance, SBOM, MR, journaux), et lesquelles sont falsifiables par un administrateur de la plateforme ?

**Critères de réussite**
- [ ] Les 16 questions ont une réponse écrite et argumentée (pour les QCM : la bonne réponse **et** pourquoi les autres sont fausses).
- [ ] Après correction, tu as identifié tes trois points les plus faibles et noté un exercice ou une lecture pour chacun.

<details><summary>Indice 1</summary>

Pour 1 à 9 : *GitLab architecture overview*, *Job execution flow* de GitLab Runner, *Configure runners* (étiquettes, runners protégés), *`rules`* et *`workflow`*, *CI/CD components*, *CI/CD variables*, *CI/CD job token*, *OpenID Connect (OIDC) authentication using ID tokens*, *Configure job timeouts* ; ton compte rendu de M19-E44.
</details>

<details><summary>Indice 2</summary>

Pour 10 à 16 : *BuildKit rootless mode*, *Caching in GitLab CI/CD*, *Job artifacts*, *Kubernetes executor* (*Pod lifecycle*, *Protect job pods from eviction*), *Pod Priority and Preemption*, *Scheduled pipelines*, *Upgrading GitLab* et *GitLab Runner version compatibility*, *SLSA* ; tes journaux de M19-E35 à M19-E42 et l'ADR-0190.
</details>

**Pour aller plus loin** : choisis trois questions et transforme chacune en mini-démonstration sur le lab (5 minutes, reproductible, sans casser la CI des équipes), à présenter à Karim.
