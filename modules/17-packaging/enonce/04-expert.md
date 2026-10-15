# Module 17 — Palier 4 : Expert

Le packaging tourne : un chart publié par pipeline, des overlays qui livrent la recette et la production, une plateforme sous Helmfile. Nadia Roussel connaît la suite : « Le jour où un `helm upgrade` refuse de démarrer, ou que la prod tourne autre chose que ce qu'on a validé, qui sait lire ce que Helm a rangé dans le cluster ? » Karim Benali a préparé quatre pannes, tirées de ce que racontent les forums et les post-mortems publics :
- une release bloquée ;
- un chart qui ne se rend plus ;
- une production qui déploie la mauvaise image ;
- un conflit de propriété des champs.

Ensuite tu descends sous le capot, dans les Secrets où Helm range ses releases, puis tu passes les questions qu'on pose en entretien.

La méthode reste celle des modules précédents : observer avant d'agir, formuler une hypothèse, la tester par la mesure la moins invasive, corriger à la racine, prévenir la récidive. Le packaging y ajoute trois règles :
- **Distingue le rendu, l'application et l'état.** Une erreur peut naître au rendu (`helm template`, `kustomize build` : gabarit, valeurs, schéma), à l'application (serveur d'API : validation, admission, conflits de propriété) ou dans l'état que Helm garde (Secrets `sh.helm.release.v1.*`). Chacun a ses outils, et une commande qui « répare » le mauvais étage aggrave la panne.
- **Le dépôt est la vérité, le cluster est une copie.** Une réparation à chaud est permise pour rétablir le service. Elle n'est terminée que lorsque le dépôt (chart, overlay, `helmfile.yaml`) et le cluster sont d'accord : `helm diff`, `helmfile diff` et `kubectl diff --server-side` vides.
- **Ne détruis pas ce qui sert d'historique.** `helm uninstall`, la suppression en masse des Secrets de release et `helm upgrade --force-replace` sont **interdits** dans ce palier. Supprimer **un** Secret de release précis est permis quand tu as prouvé qu'il est en cause et que tu l'as sauvegardé. Aucune des pannes n'exige plus.

> **Rappels** : tout se lance depuis `adm01`.
> - Copies de travail : `~/src/mediagenda-chart`, `~/src/mediagenda-deploiement`, `~/src/k8s`.
> - Kubeconfig personnel : `~/.kube/config`.
> - La release `mediagenda` de `mediagenda-dev` est le banc d'essai Helm du chart. La recette et la production sont livrées par les overlays : base = rendu du chart signé (`chart.env`, `outils/rendre-base.sh`), application par `kubectl apply --server-side -k overlays/<env>` (M17-E09).

## Règles du jeu des pannes (M17-E19 à M17-E22)

- Les pannes s'injectent **depuis `adm01`**, à la racine de ta copie du workbook :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ lab/bin/break 17 19
  ```
  Le script tire une variante au hasard et n'affiche que le **symptôme**, comme un ticket. Chaque panne a 2 ou 3 variantes : refais l'exercice jusqu'à les avoir toutes rencontrées (`--variante N` force une variante, sans dire laquelle est laquelle). Si une variante n'a pas d'effet sur ton lab, le script en essaie une autre ou s'annule.
- **Avant d'injecter**, lance le contrôle de l'exercice (`lab/bin/check 17 19`) : il doit être vert. Les scripts refusent de casser une release qui n'est pas `deployed` ou une copie de travail qui contient des modifications non commitées.
- **Ne lis pas** :
  - les scripts de `corrige/pannes/` ;
  - `~/.local/state/workbook/` sur `adm01` ;
  - les annotations ou étiquettes qui n'ont rien à faire sur un objet.

  Ils contiennent la cause.
- Une seule panne active à la fois par exercice. Si tu abandonnes, `lab/bin/break 17 19 --annuler` remet l'état sain. C'est un filet de sécurité, pas un correctif : compte l'exercice comme non réussi.
- **Quand tu as réparé**, lance aussi `--annuler` pour **clore** la panne. Sinon elle reste marquée active et bloque le mini-projet. L'annulation ne rétablit que ce qui est encore dans l'état cassé et ne revient jamais sur ta réparation.
- Les pannes n'agissent que sur :
  - la release `mediagenda` de `mediagenda-dev` et ses objets ;
  - la release `metrics-server` de `kube-system` ;
  - le Deployment de `mediagenda-prod` ;
  - tes copies de travail, sur une **branche locale** créée pour l'occasion : jamais de commit sur `main`, jamais de `git push`.

  Elles ne touchent jamais `mediagenda-recette`, cert-manager, Cilium ni le stockage. Tout objet modifié est sauvegardé avant (PLAN §4.10, « Pannes du bloc C »).
- **Tiens un journal de diagnostic** pour chaque panne, dans `docs/kubernetes/journal/` de `plateforme/medisphere` (clone `~/medisphere`, publié par MR) : heure, hypothèse, commande, résultat observé, conclusion. Un incident qui a touché un service (la production en M17-E21) a en plus son post-mortem dans `docs/kubernetes/post-mortems/`.
- Le **temps cible** est indicatif. Le dépasser n'est pas un échec ; corriger sans comprendre en est un.

> ⚠️ **Accès aux Secrets de release** : tu les lis avec ton kubeconfig personnel. Avant de modifier ou de supprimer un Secret `sh.helm.release.v1.*`, **sauvegarde-le** :
> ```
> kubectl get secret <NOM> -n <ESPACE> -o yaml > ~/sauvegardes/<NOM>.yaml
> ```
> Il contient les valeurs de la release. Ne le colle jamais dans un ticket ni dans le journal.

---

### M17-E19 — Panne : la release est bloquée  `BF` `★★`

> **Ticket INC-4419** — *De : Nadia Roussel*
> *(Le détail du ticket s'affiche à l'injection : selon le cas, Julien ne peut plus monter le dev, ou Karim ne peut plus appliquer Helmfile.)* Personne n'a touché au chart. Lucas propose de « désinstaller et réinstaller, ça ira plus vite » : c'est non.

**Objectifs pédagogiques**
- Relier un refus de Helm (`another operation (install/upgrade/rollback) is in progress`, `release: already exists`) à l'état des Secrets de release.
- Lire les statuts d'une révision (`deployed`, `superseded`, `failed`, `pending-install`, `pending-upgrade`, `pending-rollback`) et ce que Helm en déduit.
- Débloquer une release sans la désinstaller et sans perdre son historique, puis écrire le runbook RB-170.

**Prérequis** : M17-E02 (`history`, `rollback`), M17-E10 (Helmfile), M17-E14 ; `lab/bin/check 17 19` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : Helm garde une révision par Secret (`sh.helm.release.v1.<release>.v<N>`). Leurs étiquettes `name`, `owner`, `status` et `version` servent aux recherches de `helm list` et `helm history`. Avant d'appliquer quoi que ce soit, Helm écrit la nouvelle révision dans un état `pending-*`, puis la passe en `deployed` ou `failed` à la fin. Une commande interrompue (coupure réseau, `Ctrl+C`, job de CI tué) peut laisser la révision dans l'état intermédiaire.

**Injection** : `lab/bin/break 17 19` (3 variantes).

**Travail demandé**
1. Reproduis le symptôme et note le message exact. Avant toute action, regarde ce que montrent `helm status`, `helm history` et `helm list -A --pending`, puis les Secrets de la release avec leurs étiquettes (`kubectl get secret -l owner=helm,name=<release> -L status,version`). Les trois récits sont-ils d'accord ?
2. Pour chaque révision suspecte, décode le Secret (champ `release`) et lis `info.status`, `info.description` et les dates. Que s'est-il passé, et quand ?
3. Avant de corriger, vérifie l'état réel des objets de la release : la version qui tourne correspond-elle à la dernière révision `deployed` ? Rien n'est-il à moitié appliqué ?
4. Débloque la release par la méthode la moins destructive qui convient à la cause : `helm rollback` vers la bonne révision, ou suppression d'**un seul** Secret de révision prouvé en cause, après sauvegarde. Rejoue ensuite l'opération qui avait échoué (`helm upgrade` du dev, ou `helmfile apply` de la cible) et vérifie qu'elle passe.
5. Rédige `RB-170 — Release Helm bloquée` dans `docs/kubernetes/packaging/runbooks/`. Il doit dire :
   - comment reconnaître chaque cas ;
   - ce qu'on vérifie avant d'agir ;
   - la méthode par cas ;
   - ce qu'on ne fait jamais ;
   - comment éviter la récidive en CI (`timeout`, `resource_group`, retour sur échec).

**Critères de réussite**
- [ ] Les releases `mediagenda` (`mediagenda-dev`) et `metrics-server` (`kube-system`) sont `deployed`. Aucune release du cluster n'est en état `pending-*`.
- [ ] Pour ces deux releases, la plus haute révision lisible par `helm history` est aussi la plus haute présente parmi les Secrets de release : aucun Secret illisible ni orphelin.
- [ ] Les objets du dev (et l'API de métriques) fonctionnent. L'opération qui échouait passe.
- [ ] Ton journal contient le message initial, les statuts lus et la preuve de la cause. RB-170 est publié.

**Vérification** : `lab/bin/check 17 19`

<details><summary>Indice 1</summary>

`helm history` ne montre que les révisions qu'il sait **décoder**. Si les étiquettes des Secrets annoncent une révision que `helm history` ne montre pas, cette révision existe pour Kubernetes, mais pas pour Helm.
</details>

<details><summary>Indice 2</summary>

Une révision `pending-upgrade` plus récente que la dernière `deployed` suffit à faire refuser toute nouvelle opération. Lis la page *helm rollback* de ta version : un retour vers une révision `deployed` est permis depuis cet état.
</details>

<details><summary>Indice 3</summary>

Helm calcule le numéro de la révision suivante à partir de la dernière révision qu'il sait lire. Si un Secret de ce numéro existe déjà, mais qu'il est illisible, l'écriture échoue.
</details>

**Pour aller plus loin** (facultatif) : provoque toi-même un `pending-upgrade` dans `wb-essais` : un chart dont un hook `pre-upgrade` ne se termine jamais, et un `helm upgrade` interrompu par `Ctrl+C`. Observe ce que fait Helm 4 au signal, et ce qui reste dans les Secrets.

---

### M17-E20 — Panne : le rendu du chart échoue  `BF` `★★`

> **Ticket INC-4420** — *De : Julien Petit*
> Lucas a travaillé avec moi hier sur `adm01`, dans ta copie du chart. Il est en congé jusqu'à lundi et il a laissé une branche à moitié finie. Je dois la livrer aujourd'hui, mais rien ne passe : `helm template` échoue. Il m'a dit « petite modif sans risque ». Trouve ce qui ne va pas et corrige-le sur sa branche, pour que je puisse ouvrir la MR.

**Objectifs pédagogiques**
- Lire une erreur de rendu Helm jusqu'à sa cause : fichier, ligne, gabarit, valeur.
- Distinguer une erreur de valeurs (schéma JSON), de gabarit (indentation `nindent`/`indent`, `required`, chemin de valeur) et d'objet Kubernetes (validation par le serveur).
- Outiller la détection : rendu de débogage, tests unitaires, `--dry-run=server`.

**Prérequis** : M17-E05 (schéma, `required`, helpers), M17-E07 (tests), M17-E13 (pipeline) ; `lab/bin/check 17 20` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : la branche de Lucas est une branche locale de `~/src/mediagenda-chart` (`git branch` la montre), partie de `main`. Les jeux de valeurs de référence sont ceux du pipeline : `--set medisphere.environnement=recette` et `ci/*-values.yaml`.

**Injection** : `lab/bin/break 17 20` (3 variantes). La panne crée la branche, y commite, et t'y laisse. `--annuler` te ramène sur ta branche d'origine et ne supprime la branche de Lucas que si tu n'y as rien ajouté.

**Travail demandé**
1. Reproduis l'erreur avec les jeux de valeurs du pipeline : `helm lint --strict`, `helm template`, puis la simulation par le serveur (`--dry-run=server` sur la release du dev). Note à quel étage elle apparaît : valeurs, gabarit ou objet.
2. Retrouve exactement ce que Lucas a changé (`git log`, `git show`), puis relie le message d'erreur à la ligne du commit. Utilise les options de débogage de `helm template` : sur une erreur YAML, la sortie partielle montre le document fautif.
3. Corrige sur la branche de Lucas, par un nouveau commit Conventional Commits : on ne réécrit pas son commit. Garde ce qu'il voulait faire, si c'est légitime. La branche doit passer `helm lint --strict`, les rendus et `helm unittest`.
4. Ajoute le test helm-unittest ou la règle de schéma qui aurait **vu** cette erreur dans le pipeline avant la revue, si elle n'y est pas déjà.
5. Dans ton journal, explique pourquoi cette erreur n'a pas été vue sur le poste de Lucas, et à quel job du pipeline elle aurait été arrêtée.

**Critères de réussite**
- [ ] La copie de travail est sur une branche dont le chart passe `helm lint --strict` et `helm template` avec les jeux de valeurs du pipeline, et dont le rendu est accepté par le serveur d'API.
- [ ] Toute branche locale `lucas/*` passe les mêmes contrôles.
- [ ] Un test ou une règle de schéma couvre la cause. Ton journal relie le message d'erreur à la ligne fautive.

**Vérification** : `lab/bin/check 17 20`

<details><summary>Indice 1</summary>

Le message de Helm donne le fichier et souvent la ligne **du rendu**, pas du gabarit. `helm template --debug` (et, pour isoler un gabarit, `--show-only templates/<fichier>`) affiche ce qui a été produit, même partiellement.
</details>

<details><summary>Indice 2</summary>

`nindent N` ajoute un saut de ligne **puis** N espaces devant chaque ligne ; `indent N` n'ajoute pas le saut de ligne. Le chiffre doit correspondre à la colonne où la clé parente attend ses enfants, et une erreur de deux colonnes produit un YAML qui reste parfois valide, mais qui ne veut plus dire la même chose.
</details>

<details><summary>Indice 3</summary>

Un message produit par `required` ou `fail` dit ce que **l'auteur du gabarit** croyait. Si la valeur nommée par le message est bien présente dans tes valeurs, regarde quel chemin le gabarit lit vraiment.
</details>

---

### M17-E21 — Panne : la production déploie la mauvaise image  `BF` `★★`

> **Ticket INC-4421** — *De : Sophie Laurent* — *Copie : Claire Morel*
> Contrôle de conformité de ce matin : la production ne tourne pas ce qui a été validé en recette et approuvé en comité de changement. *(Le détail de l'écart s'affiche à l'injection.)* Personne n'a ouvert de MR sur `overlays/prod`. Je veux savoir ce qui tourne, depuis quand, d'où ça vient, et que la prod revienne à ce qui a été approuvé.

**Objectifs pédagogiques**
- Comparer ce qui tourne (cluster), ce que le dépôt prévoit (rendu de `main`) et ce qui a été appliqué (`managedFields`, historique des ReplicaSets).
- Comprendre l'ordre de construction de Kustomize : ressources, components, transformateurs de l'overlay, overlays imbriqués.
- Remettre la production d'accord avec `main` et rendre l'écart impossible à reproduire.

**Prérequis** : M17-E09 (overlays, components `livraison`, `debogage`, `haute-disponibilite`), M17-E14 (`kubectl diff --server-side`, `managedFields`) ; `lab/bin/check 17 21` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : la prod (`mediagenda-prod`) est livrée par l'overlay `prod` de `mediagenda/deploiement`, par `kubectl apply --server-side -k overlays/prod` (gestionnaire de champs `kubectl`). La version approuvée est celle de `overlays/prod/livraison.yaml` sur `main` (`origin/main`). Les révisions d'un Deployment se lisent avec `kubectl rollout history` ; chaque révision correspond à un ReplicaSet.

**Injection** : `lab/bin/break 17 21` (2 variantes). La panne travaille dans ta copie de `mediagenda/deploiement` (branche locale, rien n'est poussé), applique la prod, puis te remet sur ta branche d'origine.

**Travail demandé**
1. Établis les faits sans rien modifier :
   - ce qui tourne : image, variables, étiquettes, révision du Deployment ;
   - depuis quand : `rollout history`, date du ReplicaSet ;
   - sous quel gestionnaire de champs, et à quelle heure (`managedFields[].time`).
2. Rends `overlays/prod` depuis `origin/main` et compare au cluster avec `kubectl diff --server-side`. L'écart vient-il de `main` ?
3. Trouve d'où vient ce qui a été appliqué : branches locales, `git reflog`, rendu de chaque candidat. Explique **par l'ordre de construction de Kustomize** pourquoi ce rendu-là produit cet écart.
4. Remets la production sur `main` par le chemin normal (rendu de `main`, signature du chart vérifiée, `kubectl diff --server-side`, application sous le même gestionnaire de champs) et vérifie le retour.
5. Rends l'erreur impossible à fusionner : ajoute au pipeline de `mediagenda/deploiement` un contrôle qui rend chaque overlay et refuse, pour la prod, une image dont la version n'est pas celle de son `livraison.yaml`, et tout component de débogage. Écris dans ton journal ce qui empêcherait encore, aujourd'hui, quelqu'un d'appliquer la prod depuis son poste, et ce qu'apporteront le M20 (Argo CD) et le RBAC.

**Critères de réussite**
- [ ] Le Deployment de `mediagenda-prod` correspond exactement au rendu de `origin/main` (`kubectl diff --server-side` vide), image comprise, et ses pods sont tous prêts.
- [ ] La prod ne porte aucun réglage de débogage (`MEDIAGENDA_LOG_LEVEL` à `DEBUG`, format `texte`).
- [ ] Le pipeline de `main` de `mediagenda/deploiement` contient le contrôle de cohérence des images et des components, et il est vert.
- [ ] Ton journal établit ce qui tournait, depuis quand, depuis quel rendu, et pourquoi Kustomize l'a produit.

**Vérification** : `lab/bin/check 17 21`

<details><summary>Indice 1</summary>

Les `managedFields` disent **qui** a écrit en dernier et **quand**, pas d'où venait le manifeste. Pour le « d'où », il faut comparer des rendus : celui de `main`, et ceux des autres références qui existent sur le poste qui applique.
</details>

<details><summary>Indice 2</summary>

Dans un overlay, l'ordre n'est pas celui des lignes du fichier. Kustomize accumule les `resources`, puis applique les `components` (dans l'ordre de la liste), puis **ses propres** transformateurs : `images`, `replicas`, `patches`… Un overlay qui inclut un autre overlay en ressource passe, lui, après tout ce qu'a fait ce dernier.
</details>

---

### M17-E22 — Panne : conflit de propriété des champs  `BF` `★★★`

> **Ticket INC-4422** — *De : Julien Petit*
> Depuis ce matin, le `helm upgrade` du dev échoue, même quand je ne change aucune valeur. Hier tout marchait. Lucas jure qu'il n'a « rien cassé, juste regardé ». Je voudrais pouvoir monter le dev sans `--force-quelque-chose` dont je ne comprends pas l'effet.

**Objectifs pédagogiques**
- Diagnostiquer un conflit de *server-side apply* : quel champ, quel gestionnaire, quelle opération, quelle sous-ressource.
- Choisir entre reprendre le champ (`--force-conflicts`), défaire le changement, retirer la propriété, ou changer le chart, selon que la modification manuelle était voulue ou non.
- Comprendre la cohabitation d'un contrôleur (HPA) et d'un gestionnaire de manifestes sur `spec.replicas`.

**Prérequis** : M17-E14 (SSA, `managedFields`), M14-E16 (déploiements progressifs), M14-E20 (metrics-server) ; `lab/bin/check 17 22` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : la release `mediagenda` de `mediagenda-dev` est en SSA (Helm 4), sous le gestionnaire `helm`. Un HorizontalPodAutoscaler modifie le nombre de réplicas d'un Deployment par sa sous-ressource `scale`.

**Injection** : `lab/bin/break 17 22` (3 variantes).

**Travail demandé**
1. Reproduis le `helm upgrade` de Julien, avec les valeurs actuelles et la même version du chart. Note le message en entier : objet, gestionnaire, champs.
2. Lis les `managedFields` de chaque objet nommé : opération, sous-ressource, date, champs possédés (`fieldsV1`). Établis ce qui a été modifié, par quel outil et quand. Cherche s'il y a un objet nouveau dans l'espace.
3. Décide, et écris la décision dans ton journal : la modification manuelle était-elle voulue (alors elle va dans le chart) ou non (alors elle disparaît) ? Si un contrôleur gère légitimement un champ, qui doit cesser de le gérer ?
4. Corrige de façon que le `helm upgrade` de Julien passe **sans** option de forçage dans sa commande, et que le prochain changement de valeur sur ces champs passe aussi. Vérifie-le en changeant réellement une valeur concernée.
5. Rédige `RB-171 — Conflit de propriété des champs` dans `docs/kubernetes/packaging/runbooks/` : lecture des `managedFields`, arbre de décision, commandes, pièges (dont la copropriété qui survit à un retour manuel).

**Critères de réussite**
- [ ] La release `mediagenda` du dev est `deployed`, et une montée avec les valeurs courantes passe sans option de forçage.
- [ ] Aucun champ du Deployment ni de la ConfigMap de la release n'appartient à un gestionnaire `kubectl-edit`, `kubectl-client-side-apply`, `kubectl-patch` ou `kubectl` (sous-ressource `scale`).
- [ ] Si un HPA cible le Deployment, `spec.replicas` n'est plus rendu par le chart (sinon : aucun HPA ne cible ce Deployment).
- [ ] RB-171 est publié. Ton journal identifie champ, gestionnaire, opération et date pour la variante rencontrée.

**Vérification** : `lab/bin/check 17 22`

<details><summary>Indice 1</summary>

`kubectl get <objet> --show-managed-fields -o json | jq '.metadata.managedFields[] | {manager, operation, subresource, time}'` est le point de départ. `fieldsV1` se lit comme un arbre : `f:` pour un champ, `k:` pour un élément de liste repéré par sa clé (`{"name":"api"}`), `v:` pour une valeur.
</details>

<details><summary>Indice 2</summary>

`kubectl apply` sans `--server-side` n'est pas une opération `Apply` pour le serveur : c'est un `Update` du gestionnaire `kubectl-client-side-apply`, qui laisse en plus une annotation `last-applied-configuration`. Et `kubectl edit` porte le nom `kubectl-edit`.
</details>

<details><summary>Indice 3</summary>

Quand un HPA pilote un Deployment, la documentation Kubernetes (*Horizontal Pod Autoscaling*, section sur la migration vers l'autoscaling) dit de retirer `spec.replicas` des manifestes. Le chart doit donc savoir **ne pas** rendre ce champ. Cherche aussi comment retirer la propriété que `helm` garde sur ce champ sans changer le nombre de pods.
</details>

---

### M17-E23 — Sous le capot : où Helm range-t-il ses releases ?  `LAB` `★★★`

> **Ticket PLAT-1823** — *De : Karim Benali*
> Après les pannes de la semaine, je veux que toute l'équipe sache lire ce que Helm laisse dans le cluster. Fais-nous une séance : ce qu'il y a dans un Secret de release, ce que Helm en fait à chaque commande, ce qui change avec un autre pilote de stockage, et un outil pour décoder une révision sans en afficher les secrets.

**Objectifs pédagogiques**
- Décoder une révision de release et en connaître la structure : chart complet, valeurs fournies, manifeste, hooks, statut, méthode d'application.
- Comprendre le cycle d'un `helm upgrade` vu depuis les Secrets : révision `pending-upgrade`, application, `deployed`, ancienne révision `superseded`, suppression des objets retirés, `historyMax`.
- Comparer les pilotes de stockage `secret` (défaut), `configmap` et `sql`, et la taille maximale d'une release.

**Prérequis** : M17-E15 (valeurs dans les releases), M17-E19 (statuts), M14-E06 (kubectl, `-o jsonpath`), M14-E28 (chiffrement des Secrets au repos).
**Durée indicative** : 2 h.

**Contexte technique** : tout se fait dans `wb-essais`, avec le chart `mediagenda` (`--set httpRoute.enabled=false`) ou un chart de démonstration (`helm create`). Le pilote de stockage se choisit par la variable d'environnement `HELM_DRIVER`. Les détails des pilotes, dont la chaîne de connexion du pilote `sql` (PostgreSQL), sont dans la documentation de Helm 4 (*Helm Storage Backends* ; vérifie le nom exact de la variable de connexion sur ta version).

**Travail demandé**
1. Installe une release `capot` (pilote par défaut) puis monte-la deux fois en changeant une valeur. Liste ses Secrets avec leurs étiquettes. Que vaut `type` ? À quoi servent les étiquettes, et quelle commande Helm s'en sert ?
2. Décode la dernière révision. Combien de fois faut-il décoder le base64, et pourquoi ? Quel format de compression ? Liste les clés de premier niveau et décris chacune. Où sont :
   - les valeurs fournies, et les valeurs par défaut du chart ?
   - les gabarits, et le manifeste rendu ?
   - les hooks et leur dernière exécution ?
   - la méthode d'application (`apply_method`) ?
3. Mesure la taille de chaque Secret de révision, et la part de chaque clé. Quelle limite de taille s'applique à un Secret dans Kubernetes, et que se passerait-il avec un chart de 2 Mo de gabarits ? Que règle `--history-max`, et que vaut-il par défaut ?
4. Observe une montée en direct : dans un second terminal, `kubectl get secret -n wb-essais -l owner=helm,name=capot -L status,version -w`, puis `helm upgrade --wait`. Note l'ordre des écritures. Retire ensuite un objet du chart (par exemple le PDB, avec la valeur qui le désactive) et vérifie que Helm le supprime. Que faudrait-il pour qu'il le garde (`helm.sh/resource-policy`) ?
5. Recommence l'étape 1 dans `wb-essais` avec `HELM_DRIVER=configmap` et une release `capot-cm` (deux révisions au moins). Que montre `helm list` **sans** la variable ? Qui peut désormais lire les valeurs, et que dit-on à Sophie (E15) ? Laisse `capot-cm` en place jusqu'à la vérification.
6. Lis la documentation du pilote `sql`. Dans quels cas serait-il justifié, et qu'est-ce qu'il ferait dépendre de quoi ? *Facultatif* : essaie-le contre une base PostgreSQL jetable dans `wb-essais` (cluster CNPG d'une instance), puis supprime-la.
7. Écris `outils/helm-release.sh` dans `plateforme/k8s` : `helm-release.sh <espace> <release> [révision]` affiche en JSON le statut, les dates, la description, le chart (nom, version, appVersion), la méthode d'application, la liste des objets du manifeste et les noms des hooks. Les valeurs fournies sont **masquées** (clés seulement). Il fonctionne avec les pilotes `secret` et `configmap` (option ou détection). ShellCheck propre, MR, pipeline vert.
8. Compare avec Kustomize (aucun état dans le cluster) : comment `kubectl` sait-il quoi supprimer quand un objet disparaît d'un overlay ? Lis la documentation de `kubectl apply --prune` et des *ApplySets*, et note ce que M20 (Argo CD) apporte à la place.

**Critères de réussite**
- [ ] La release `capot-cm` existe dans `wb-essais` sous le pilote `configmap`, avec au moins deux révisions (ConfigMaps `sh.helm.release.v1.capot-cm.v*`, la dernière `deployed`).
- [ ] La release `capot` (pilote `secret`) est désinstallée, et il ne reste aucun Secret `sh.helm.release.v1.capot.*`.
- [ ] `outils/helm-release.sh` est sur `main` de `plateforme/k8s`, passe `bash -n` et ShellCheck, et n'affiche aucune valeur fournie.
- [ ] Tes notes répondent aux questions des étapes 2 à 6, et à la 8 (dans le journal ou `docs/kubernetes/packaging/sous-le-capot.md`).

**Vérification** : `lab/bin/check 17 23` (puis désinstalle `capot-cm` : le mini-projet vérifie que `wb-essais` est propre).

<details><summary>Indice 1</summary>

Le serveur d'API encode toujours en base64 le contenu d'un Secret (`data`), alors qu'une ConfigMap stocke du texte. Helm, lui, encode toujours sa release en base64 après l'avoir compressée. Compte les couches pour chaque pilote.
</details>

<details><summary>Indice 2</summary>

`jq 'to_entries | map({cle: .key, octets: (.value | tojson | length)})'` donne la part de chaque clé. Le chart complet (`.chart.templates[].data`, en base64) est presque toujours la plus grosse.
</details>

---

### M17-E24 — Questions expert : packaging  `Q` `★★★`

> **Ticket PLAT-1824** — *De : Claire Morel*
> Avant de te laisser encadrer les équipes MédiDoc et MédiNotif sur le packaging, je te fais passer les questions que Karim pose en entretien. Réponds par écrit, avec tes arguments : je veux le raisonnement, pas un mot-clé.

**Prérequis** : paliers 1 à 4 du module.
**Durée indicative** : 1 h 30.

1. Helm 4 installe les nouvelles releases en *server-side apply*. Une release créée par Helm 3 et montée par Helm 4 : quelle méthode est utilisée, et pourquoi ce choix par défaut (`--server-side=auto`) ? Que se passe-t-il si on force `--server-side=true` sur une release qui a toujours été en client-side ?
2. `helm upgrade --rollback-on-failure` sans `--wait` explicite : qu'attend Helm, et combien de temps ? Pourquoi Helm 4 a-t-il changé la stratégie d'attente par défaut, et que veut dire `watcher` ?
3. Un hook `pre-upgrade` (Job de migration) échoue. Dans quel état sont la release, les objets ordinaires et le schéma de la base ? Avec `helm.sh/hook-delete-policy: hook-succeeded` seul, que devient le Job en échec ? Et la révision suivante ?
4. Pourquoi `lookup` renvoie-t-il un dictionnaire vide sous `helm template`, `helm install --dry-run` (client) et `kubectl kustomize --enable-helm` (générateur `helmCharts`) ? Donne un usage où c'est sans danger et un usage où c'est un piège.
5. Le sélecteur (`spec.selector`) d'un Deployment rendu par un chart contient `app.kubernetes.io/version`. Que se passe-t-il à la prochaine montée de version de l'application ? Comment en sortir sans interruption de service ?
6. Kustomize : un overlay `prod` inclut les components `dependances`, `haute-disponibilite` et `livraison`, et porte un `images:`. Dans quel ordre s'appliquent ces transformations ? Lequel gagne entre un `replicas:` du component `haute-disponibilite` et un `replicas:` de l'overlay ? Justifie par le modèle de construction, pas par l'essai.
7. Pourquoi un `configMapGenerator` ajoute-t-il un suffixe d'empreinte au nom, et qu'est-ce qui casse si on le désactive (`disableNameSuffixHash`) ? Qu'est-ce qui reste à nettoyer dans le cluster au fil des livraisons, et qui le fait ?
8. Comparez la provenance Helm (`helm package --sign`, `.prov`, `helm install --verify`) et une signature Cosign d'un chart OCI. Qu'est-ce que chacune prouve, où est-elle stockée, qui sait la vérifier dans la chaîne MédiSphère (pipeline, Kustomize, Argo CD au M20, Kyverno au M26) ?
9. Un chart OCI est référencé par `version: 0.7.0` dans le générateur `helmCharts` de Kustomize. Qu'est-ce qui garantit que le contenu ne change pas d'un rendu à l'autre ? Pourquoi MédiSphère a-t-elle préféré `chart.env` (version **et** digest, signature vérifiée, rendu commité) ? À quel prix ?
10. Helmfile : `needs`, `helmfile apply -l name=X` et `--include-needs`. Quel est l'effet de chaque combinaison sur l'ordre et le périmètre ? Pourquoi les sélecteurs ignorent-ils `needs` par défaut ?
11. Les CRD : pourquoi Helm ne les met-il pas à jour depuis le dossier `crds/` lors d'un `upgrade`, et comment cert-manager contourne-t-il ce choix ? Quels sont les risques d'une CRD mise à jour (ou supprimée) par une release ?
12. Un Secret de release fait 900 Kio. Qu'est-ce qui le rend si gros, quelle limite approche-t-il, et quelles sont les trois façons de s'en sortir ?
13. On envisage de livrer la prod par `helm upgrade` avec un post-renderer Kustomize. Que change Helm 4 aux post-renderers ? Quels avantages et inconvénients par rapport au montage retenu (rendu du chart signé commité, puis overlays Kustomize) ?
14. Un auditeur HDS demande « la liste exacte de ce qui tournait en production le 3 mars à 14 h ». D'où la tires-tu, selon que la prod est une release Helm ou un overlay Kustomize ? Qu'est-ce qui manque aujourd'hui, et quel module le comble ?
