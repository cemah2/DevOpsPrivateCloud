# Module 14 — Palier 2 : Opérationnel

Le palier 1 a monté `k8s-par1` : trois nœuds de contrôle derrière la VIP d'API, trois travailleurs, Cilium, ton kubeconfig personnel, le compte de service des vérifications, et un premier MédiAgenda dans `wb-essais`. Tout le monde y est administrateur, ou personne. Ce palier en fait un cluster **partagé** : des espaces de noms par équipe avec un budget (quotas, LimitRanges), des **identités** (certificats d'humains signés par l'API, comptes de service, jetons liés) et des **rôles** (RBAC par agrégation), des règles d'**admission** (Pod Security, ValidatingAdmissionPolicy), des images qui viennent **toutes** de Harbor. Tu y déploies MédiAgenda pour de bon, avec un placement maîtrisé (zones, taints, priorités), les bons contrôleurs (StatefulSet, Job, CronJob, DaemonSet), des mises à jour sans coupure et des budgets de perturbation ; tu ajoutes puis retires un nœud ; tu installes metrics-server et tu apprends à diagnostiquer un pod. Tu termines en relisant les manifestes de Lucas, en écrivant le runbook « nœud NotReady » et en prouvant que le cluster se reconstruit depuis le code.

> **Rappels du module** (introduction) : toute VM passe par OpenTofu (état `k8s` de `plateforme/infra`, module `vm-noeud`), toute préparation de nœud par les rôles Ansible `containerd`, `k8s_noeud`, `k8s_plan_controle`, `k8s_travailleur` ; tout objet de **plateforme** (espaces, quotas, RBAC, admission, composants) vit dans `plateforme/k8s` (clone `~/src/k8s` sur `adm01`), passe par une MR relue puis par `task appliquer` ; les manifestes de **l'application** vivent chez l'équipe, dans `mediagenda/api` (dossier `k8s/`, clone `~/src/mediagenda-api`). Aucun Secret n'est versionné. `kubectl` se lance depuis `adm01` avec ton kubeconfig personnel (`admin@adm01:~$`), jamais avec `admin.conf`. Les vérifications (`lab/bin/check 14 XX`) lisent le cluster avec le compte `wb-checks` (lecture seule, sans les Secrets).

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| Cluster | `k8s-par1` 1.35.x, API `https://k8s-api.par1.medisphere.internal:8443` ; `k8s-cp01-03` (10.10.40.51-53), `k8s-w01-03` (10.10.40.61-63) ; `k8s-w04` (2147, 10.10.40.64) le temps d'E17 |
| Espaces de noms | `mediagenda-dev`, `mediagenda-recette` (E10, étiquettes `medisphere.internal/equipe: mediagenda` et `medisphere.internal/environnement: dev\|recette`) ; `wb-essais` (essais, palier 1) ; `wb-system` (checks, E06) ; `wb-diagnostic` (pods de diagnostic de nœud, E20) |
| Budgets (E10) | ResourceQuota `quota-equipe`, LimitRange `limites-defaut` dans chaque espace MédiAgenda ; fichiers `espaces/<espace>/00-namespace.yaml`, `10-quota.yaml`, `20-limites.yaml`, `30-comptes-service.yaml` |
| Groupes RBAC (champ `O` des certificats) | `medisphere:plateforme-admins` (cluster-admin, E06), `medisphere:mediagenda-devs`, `medisphere:lecture` ; rôles agrégés `medisphere-lecture` et `medisphere-developpeur` (E11, `rbac/`) |
| Identités | `julien.petit` (groupe `medisphere:mediagenda-devs`, certificat de 7 jours, E12) ; comptes de service `mediagenda-api` (sans droit, sans jeton monté) et `default` (sans jeton monté) dans les espaces MédiAgenda (E13) |
| Images | uniquement `registry.par1.medisphere.internal/…` : `medisphere/mediagenda-api:v1.0.0` (M13), caches `dockerhub/library/postgres:18-trixie`, `dockerhub/valkey/valkey:8.1`, `dockerhub/library/busybox:1.37`, `k8s/pause:3.10.1` ; miroirs containerd vers les caches (E19) ; Secret de tirage `harbor-pull` (robot `robot$k8s-pull`, identifiants dans `~/.config/workbook/harbor-k8s-pull.env`, 600) porté par les comptes de service (E19) |
| MédiAgenda (dev) | mêmes noms qu'en E07-E08 : `mediagenda-api` (Deployment, 3 réplicas, conteneur sur 8000, Service sur 80), `postgresql` (PostgreSQL 18 **jetable**, `emptyDir`, sur `k8s-w03`), `valkey` (StatefulSet de 3 en E15), ConfigMap `mediagenda-api-config`, Job `mediagenda-migration-v1-0-0`, CronJob `mediagenda-sauvegarde` ; Secret `mediagenda-db` (clé `mot-de-passe`) créé par `outils/secret-mediagenda.sh` |
| Placement (E14) | `topology.kubernetes.io/zone` : `par1-baie-a` (cp01, w01), `par1-baie-b` (cp02, w02), `par1-baie-c` (cp03, w03) ; `k8s-w03` : étiquette `medisphere.internal/dedie=bdd` et taint `dedie=bdd:NoSchedule` ; PriorityClasses `medisphere-critique`, `medisphere-standard`, `medisphere-essai` ; fichiers `cluster/noeuds.yaml` (tâche `etiquettes`), `ordonnancement/priorites.yaml` |
| Admission (E18) | PSA `restricted` (appliqué) sur `mediagenda-*`, `baseline` sur `wb-essais` ; ValidatingAdmissionPolicy `medisphere-images` (`admission/`) |
| Documentation | `plateforme/medisphere` : `docs/kubernetes/` (runbooks `docs/kubernetes/runbooks/RB-14N-*.md`, fiches `docs/kubernetes/changements/CHG-15xx-*.md`) ; brouillons et essais dans `~/m14/eXX/` sur `adm01` |

> 💡 **Où vivent les fichiers.** `plateforme/k8s` décrit ce que l'équipe Plateforme possède (espaces, budgets, droits, règles, composants du cluster). `mediagenda/api` (dossier `k8s/dev/`, puis `k8s/recette/` en E21) décrit l'application ; l'équipe de Julien en est responsable, tu y contribues par MR. Les deux dossiers `dev/` et `recette/` se ressemblent beaucoup : c'est le problème que Kustomize résoudra au module 17.

> ⚠️ **PostgreSQL et Valkey sont jetables dans tout ce module** (volumes `emptyDir`) : un pod recréé repart d'une base vide. Le stockage persistant arrive au module 16. Ne mets aucune donnée à laquelle tu tiens dans `mediagenda-*`.

Durée indicative du palier : 24 à 30 heures. Ordre conseillé (E19 se fait **tôt** : c'est lui qui déploie MédiAgenda dans `mediagenda-dev`) :

```
E10 ─ E11 ─ E12
       └─── E13 ─ E19 ─ E14 ─ E15 ─ E16 ─ E17
                          └──── E18 (après E15)
E20 (dès E19 fait)
E21 (après E18)   E22 (après E17)   E23 (en dernier : il reprend tout)
```

---

### M14-E10 — Espaces de noms, quotas et LimitRanges  `LAB` `★★`

> **Ticket PLAT-1510** — *De : Claire Morel*
> L'équipe de Julien arrive sur le cluster. Je veux deux espaces à elle, dev et recette, avec un budget clair : si leur dev s'emballe, ça ne doit pas affamer la recette ni nos composants. Et un pod qui ne dit pas ce qu'il consomme doit quand même recevoir des valeurs raisonnables. Tout ça dans `plateforme/k8s`, pas créé à la main.

**Objectifs pédagogiques**
- Créer des espaces de noms par le code, avec des étiquettes qui serviront de sélecteurs.
- Comprendre ce que compte un ResourceQuota (requêtes, limites, nombre d'objets) et ce qu'il impose aux pods.
- Utiliser un LimitRange pour donner des valeurs par défaut et des bornes.
- Savoir où un refus de quota apparaît (et où il n'apparaît pas).

**Prérequis** : M14-E06 (kubeconfig personnel, `wb-checks`), M14-E08 (requêtes, limites, QoS).
**Durée indicative** : 1 h 30.

**Contexte technique**
- Espaces : `mediagenda-dev` et `mediagenda-recette`, étiquettes `medisphere.internal/equipe: mediagenda` et `medisphere.internal/environnement: dev` (ou `recette`), annotation `medisphere.internal/responsable: julien.petit`.
- Budget de `mediagenda-dev` : 2 CPU et 4 Gio de **requêtes**, 6 CPU et 8 Gio de **limites**, 20 pods, 10 Services, aucun NodePort ni LoadBalancer, 30 ConfigMaps, 30 Secrets, 20 Jobs, 5 CronJobs. `mediagenda-recette` : 3 CPU / 6 Gio de requêtes, 8 CPU / 12 Gio de limites, 30 pods, le reste identique. Pas de quota de stockage : il arrive au M16 avec les volumes persistants.
- LimitRange `limites-defaut` (les deux espaces) : par conteneur, requête par défaut 100m / 128 Mio, limite par défaut 500m / 512 Mio, minimum 10m / 16 Mio, maximum 2 CPU / 2 Gio ; par pod, maximum 4 CPU / 4 Gio.
- Fichiers : un dossier par espace d'équipe, `espaces/<espace>/00-namespace.yaml`, `10-quota.yaml`, `20-limites.yaml` dans `plateforme/k8s` (les espaces du workbook restent des fichiers uniques, `espaces/wb-essais.yaml`…). La tâche `appliquer` du `Taskfile.yml` (E05-E06) lance `valider` (`yamllint`, puis `--dry-run=server`), puis applique `espaces/`, `rbac/`, `admission/` en *server-side apply*, récursivement.
- Image d'essai : `registry.par1.medisphere.internal/dockerhub/library/busybox:1.37` (cache Docker Hub de Harbor, public).

**Travail demandé**
1. Lis les pages *Resource Quotas* et *Limit Ranges* de la documentation Kubernetes. Note dans `~/m14/e10/journal.md` : quelles ressources un quota peut-il compter ? Que se passe-t-il pour un pod sans `resources` dans un espace dont le quota suit `limits.cpu` ? Le LimitRange modifie-t-il les pods **déjà** créés ?
2. Calcule si le cluster peut honorer les deux budgets en même temps (capacité allouable des travailleurs : `kubectl describe node`, section *Allocatable*). Note le résultat, en tenant compte du fait que `k8s-w03` sera réservé aux bases de données en E14.
3. Écris les six fichiers dans une branche de `plateforme/k8s` et lance `task valider`. Pourquoi la validation par le serveur échoue-t-elle pour un espace qui n'existe pas encore, alors que les fichiers sont justes ? Corrige le `Taskfile.yml` pour que `appliquer` crée (ou mette à jour) les espaces de noms **avant** de valider le reste, ouvre la MR. Après fusion : `task appliquer`, puis `task diff` (aucune différence attendue).
4. Observe : `kubectl describe quota -n mediagenda-dev`, `kubectl describe limitrange -n mediagenda-dev`.
5. Essais dans `mediagenda-dev` (fichiers dans `~/m14/e10/`) :
   - un pod busybox **sans** `resources` : relis-le (`kubectl get pod -o yaml`) et retrouve les valeurs injectées ; sa classe QoS ;
   - un pod qui demande 3 CPU : lis le refus, et qui l'émet ;
   - un Deployment de 10 réplicas à 300m de requête : combien de pods existent ? Où est le message d'erreur (Deployment, ReplicaSet, pods, événements) ? Que dit `kubectl describe quota` ?
6. Supprime tes essais (`kubectl delete -f ~/m14/e10/`), vérifie que le quota retombe à zéro.

**Critères de réussite**
- [ ] `mediagenda-dev` et `mediagenda-recette` existent avec leurs étiquettes ; leurs fichiers sont sur `main` de `plateforme/k8s`.
- [ ] Chaque espace a le quota `quota-equipe` (requêtes, limites, pods, NodePorts à 0) et le LimitRange `limites-defaut` aux valeurs demandées.
- [ ] Aucun pod d'essai ne reste dans `mediagenda-dev`.
- [ ] Le journal répond aux questions des étapes 1, 2 et 5.

**Vérification** : `lab/bin/check 14 10`

<details><summary>Indice 1</summary>

Un quota ne dit pas « tant de CPU sur le cluster » : il borne la **somme** des valeurs déclarées par les pods de l'espace. Dès qu'il suit une ressource, tout pod doit la déclarer, ou se la voir attribuer par un LimitRange.
</details>

<details><summary>Indice 2</summary>

Un refus de quota est une erreur d'**admission** de l'objet Pod. Or le pod n'est pas créé par toi mais par un contrôleur : cherche l'événement chez celui qui a tenté de le créer (`kubectl describe rs …`, `kubectl get events --field-selector reason=FailedCreate`).
</details>

**Pour aller plus loin** (facultatif) : lis la section *Quota scopes* (`scopeSelector`, `PriorityClass`) : en E14, comment empêcherais-tu l'équipe de dev de lancer plus de deux pods en priorité « critique » ?

---

### M14-E11 — RBAC : des rôles pour les équipes  `LAB` `★★★`

> **Ticket SEC-1511** — *De : Sophie Laurent*
> Aujourd'hui, quiconque a un kubeconfig est administrateur. Je veux trois profils : l'équipe Plateforme (tout), les développeurs de MédiAgenda (leur dev en écriture, leur recette en lecture, rien d'autre, et surtout pas les Secrets de la recette), et un profil lecture pour le support et mes audits, qui voit tout sauf les Secrets. Des droits donnés à des groupes, jamais à des personnes, et une matrice que je peux relire et rejouer.

**Objectifs pédagogiques**
- Distinguer Role/ClusterRole et RoleBinding/ClusterRoleBinding, et savoir lier un ClusterRole dans un seul espace.
- Construire des rôles par **agrégation** (`aggregationRule`), comme les rôles intégrés `view`, `edit`, `admin`.
- Vérifier des droits par usurpation d'identité (`kubectl auth can-i --as --as-group`) et en faire une matrice rejouable.
- Repérer les droits qui en donnent d'autres (`pods/exec`, Secrets, `escalate`, `bind`, `impersonate`).

**Prérequis** : M14-E10.
**Durée indicative** : 3 h.

**Contexte technique**
- Groupes (champ `O` des certificats clients) : `medisphere:plateforme-admins` (déjà lié à `cluster-admin` en E06), `medisphere:mediagenda-devs`, `medisphere:lecture`.
- Rôles à construire, tous des **ClusterRoles** réutilisables, dans `rbac/` de `plateforme/k8s` :
  - `medisphere-lecture` et `medisphere-developpeur` : rôles **agrégés**, sans règle écrite à la main, qui collectent les petits rôles portant respectivement l'étiquette `rbac.medisphere.internal/agreger-vers-lecture: "true"` ou `rbac.medisphere.internal/agreger-vers-developpeur: "true"` ;
  - `medisphere-lecture-charges` (lecture des objets d'un espace, **sans Secrets**, agrégé dans les deux), `medisphere-lecture-cluster` (nœuds, espaces de noms, PriorityClasses, métriques : lecture seule, agrégé dans `medisphere-lecture` seulement), `medisphere-developpeur-ecriture` (écriture des charges de travail, Services, ConfigMaps, PDB, `exec`, `port-forward`, conteneurs éphémères ; agrégé dans `medisphere-developpeur`), `medisphere-secrets-edition` (Secrets, **non** agrégé).
- Liaisons : `medisphere:lecture` → `medisphere-lecture` sur tout le cluster ; `medisphere:mediagenda-devs` → `medisphere-developpeur` **et** `medisphere-secrets-edition` dans `mediagenda-dev`, → `medisphere-lecture-charges` dans `mediagenda-recette`.
- Ton identité est dans `medisphere:plateforme-admins` : `cluster-admin` comprend `impersonate`, ce qui permet `--as`.

**Travail demandé**
1. Lis *Using RBAC Authorization* (sections *Aggregated ClusterRoles*, *Default roles and role bindings*, *Privilege escalation prevention and bootstrapping*). Dans le journal (`~/m14/e11/journal.md`) : pourquoi peut-on lier un ClusterRole par un RoleBinding ? Qu'apporte l'agrégation par rapport à un gros rôle écrit à la main ? Quelles ressources ou verbes donnent indirectement d'autres droits ?
2. Inventaire de départ : liste les ClusterRoleBindings qui donnent `cluster-admin` et ceux qui visent `system:authenticated` ou `system:unauthenticated`. Explique chacun.
3. Lis les règles du rôle intégré `view` (`kubectl get clusterrole view -o yaml`) : comment est-il construit ? Que ne contient-il pas, et pourquoi ?
4. Écris les rôles et les liaisons dans `rbac/` (MR), applique. Vérifie que le contrôleur a bien rempli les règles des deux rôles agrégés.
5. Écris `~/m14/e11/matrice-droits.sh` : une vingtaine de cas `kubectl auth can-i <verbe> <ressource> -n <espace> --as=<utilisateur> --as-group=<groupe>`, chacun avec la réponse attendue, sortie lisible et code de retour non nul en cas d'écart. Couvre au moins : écriture en dev, lecture et absence d'écriture en recette, Secrets de recette, `pods/exec` en recette, quotas et RoleBindings en dev, nœuds, `kube-system`, et un utilisateur authentifié quelconque.
6. Prouve un piège : quand MédiAgenda tournera dans `mediagenda-dev` (E19), montre qu'avec le seul droit `pods/exec`, l'identité de Julien lit le contenu du Secret `mediagenda-db` sans avoir besoin du droit sur les Secrets. Note pourquoi c'est acceptable en dev et pas en recette. (Tu peux revenir à cette étape après E19.)
7. Agrégation à l'usage : ajoute la lecture des `storageclasses` à `medisphere-lecture-cluster`, applique, et constate que `medisphere-lecture` l'a reçue **sans** que tu y touches. Garde-la ou retire-la (MR), en justifiant dans le journal.

**Critères de réussite**
- [ ] Les six ClusterRoles existent ; `medisphere-developpeur` et `medisphere-lecture` ont des règles **remplies par agrégation** ; aucun n'accorde les Secrets sauf `medisphere-secrets-edition`.
- [ ] Les liaisons sont faites à des **groupes** : écriture en `mediagenda-dev`, lecture seule en `mediagenda-recette`, lecture partout pour `medisphere:lecture`.
- [ ] Aucune liaison ne donne `cluster-admin` en dehors des groupes `medisphere:plateforme-admins`, `kubeadm:cluster-admins` et `system:masters`.
- [ ] `matrice-droits.sh` passe sans écart ; les fichiers `rbac/` sont sur `main`.

**Vérification** : `lab/bin/check 14 11`

<details><summary>Indice 1</summary>

Un rôle agrégé a un champ `aggregationRule.clusterRoleSelectors` et **pas** de `rules` écrites : c'est le contrôleur d'agrégation du kube-controller-manager qui les remplit, et qui les réécrira si tu y touches (n'écris même pas `rules: []` : avec le *server-side apply* du Taskfile, ton dépôt deviendrait propriétaire du champ).
</details>

<details><summary>Indice 2</summary>

`kubectl auth can-i` renvoie `yes` ou `no` sur la sortie standard et un code de retour (0 ou 1). Pour une sous-ressource, écris-la telle quelle (`pods/exec`, `deployments/scale`) ; pour une ressource d'un groupe d'API, `deployments.apps`. Sans `-n`, la question porte sur l'espace courant de ton contexte, pas sur le cluster : pour une ressource de cluster (nœuds, espaces), la question n'a pas d'espace.
</details>

<details><summary>Indice 3</summary>

Depuis que `kubectl exec` passe par WebSocket, l'API vérifie le verbe `get` sur `pods/exec` (et plus seulement `create`). Ton rôle d'écriture doit porter les deux.
</details>

**Pour aller plus loin** (facultatif) : `kubectl auth can-i --list --as=julien.petit --as-group=medisphere:mediagenda-devs -n mediagenda-dev` ; compare avec ta matrice. Lis aussi `kubectl auth reconcile` : en quoi diffère-t-il de `kubectl apply` pour des objets RBAC ?

---

### M14-E12 — Identités humaines : certificats clients et CSR  `LAB` `★★`

> **Ticket DEV-1512** — *De : Julien Petit*
> Mon équipe veut travailler sur `mediagenda-dev` dès lundi. Pour commencer, moi : il me faut un kubeconfig. Je ne veux pas que ma clé privée passe par un ticket ou par vos postes, et je préfère un accès court qu'on renouvelle qu'un accès d'un an. Et dites-moi ce qu'on fait si je perds mon portable.
>
> *Commentaire de Sophie Laurent* : avant de valider, je veux savoir comment on **retire** un accès donné par certificat.

**Objectifs pédagogiques**
- Comprendre comment l'API authentifie un certificat client (CN = utilisateur, O = groupes) et qui le signe.
- Faire signer une demande par l'API `CertificateSigningRequest` (signataire `kubernetes.io/kube-apiserver-client`), avec une durée courte.
- Construire un kubeconfig qui ne contient pas la clé privée d'autrui.
- Mesurer les limites de ce mode d'authentification (pas de révocation) et préparer le passage à OIDC (M24).

**Prérequis** : M14-E11.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Julien travaille sur son poste ; ici, on simule son poste par le dossier `~/m14/e12/julien/` (700) sur `adm01`. Seul le fichier `.csr` en sort.
- Identité : `CN=julien.petit`, `O=medisphere:mediagenda-devs` (un seul `O`). Clé EC P-256.
- Durée : **7 jours**, comme les certificats personnels de l'équipe Plateforme (E06). L'API accepte de 10 minutes à la durée maximale fixée par le kube-controller-manager.
- Outil à écrire : `outils/kubeconfig-csr.sh` dans `plateforme/k8s` (contrôle du sujet, création du CSR, approbation, kubeconfig **sans** clé, qui désigne la clé par un chemin relatif `julien.petit.key`).
- Kubeconfig produit : `~/m14/e12/julien/julien.petit.kubeconfig` (600), cluster `k8s-par1`, contexte `julien.petit@k8s-par1`.
- Documentation : `docs/kubernetes/acces-humains.md` dans `plateforme/medisphere`.

**Travail demandé**
1. Lis *Certificates and Certificate Signing Requests* et *Authenticating → X509 client certificates*. Dans `~/m14/e12/journal.md` : qui signe les certificats émis pour `kubernetes.io/kube-apiserver-client` dans un cluster kubeadm (quels fichiers sur les nœuds de contrôle) ? Que se passe-t-il si un CSR demande `O=system:masters` et qu'un administrateur l'approuve sans lire ?
2. « Côté Julien » : génère la clé et la demande dans `~/m14/e12/julien/` (`openssl req -new …`), clé en 600.
3. Écris `outils/kubeconfig-csr.sh` : il refuse un sujet différent de l'attendu (CN, et **exactement** un O), crée l'objet CSR avec `expirationSeconds`, l'approuve, attend le certificat et écrit le kubeconfig. MR, puis lance-le sur la demande de Julien.
4. Lis l'objet CSR créé (`kubectl get csr -o yaml`) : conditions, qui a approuvé, certificat. Décode le certificat : sujet, émetteur, dates. Que devient l'objet CSR une heure plus tard ?
5. Teste avec le kubeconfig de Julien : `kubectl auth whoami`, puis trois actions : une permise en dev, une refusée en recette, la lecture des nœuds.
6. Révocation : montre (dans le journal, avec tes commandes) qu'il n'y a pas de moyen de rendre ce certificat invalide avant son terme. Propose la procédure à suivre si Julien perd son portable, et rédige `docs/kubernetes/acces-humains.md` (principe, demande, délivrance, renouvellement, retrait). MR dans `plateforme/medisphere`.
7. Essaie l'outil avec une demande piégée (`O=system:masters` en plus du bon `O`) : il doit refuser.

**Critères de réussite**
- [ ] `~/m14/e12/julien/julien.petit.kubeconfig` (600) authentifie `julien.petit` dans le groupe `medisphere:mediagenda-devs`, avec un certificat signé par la CA du cluster, valable 7 jours au plus.
- [ ] La clé de Julien est en 600 et n'est pas dans le kubeconfig produit par l'outil.
- [ ] Avec ce kubeconfig : création de Deployment permise en `mediagenda-dev`, refusée en `mediagenda-recette`.
- [ ] `outils/kubeconfig-csr.sh` est sur `main` de `plateforme/k8s` et refuse un sujet piégé ; `docs/kubernetes/acces-humains.md` est publié.

**Vérification** : `lab/bin/check 14 12`

<details><summary>Indice 1</summary>

L'objet CSR porte la demande PKCS#10 encodée en base64 dans `spec.request`, le signataire dans `spec.signerName`, l'usage `client auth` et la durée `spec.expirationSeconds`. `kubectl certificate approve` ajoute la condition `Approved` ; c'est ensuite le kube-controller-manager qui signe et remplit `status.certificate`.
</details>

<details><summary>Indice 2</summary>

`openssl req -noout -subject -nameopt multiline` affiche un champ par ligne : pratique pour compter les `organizationName`. Dans un kubeconfig, un chemin relatif (`client-key: julien.petit.key`) est résolu par rapport au fichier kubeconfig lui-même.
</details>

**Pour aller plus loin** (facultatif) : lis la page *Pod Certificates* (`PodCertificateRequest`, GA en 1.37) et la *ClusterTrustBundle* : que changeront-elles pour les identités des charges de travail ?

---

### M14-E13 — Comptes de service et jetons liés  `LAB` `★★`

> **Ticket SEC-1513** — *De : Sophie Laurent*
> L'audit de l'ancien prestataire a trouvé des jetons d'API valables à vie dans des scripts. Sur notre cluster, je veux : aucun jeton monté dans un pod qui n'en a pas besoin, aucun jeton permanent sauf exception documentée, et que tu me montres concrètement à quoi ressemble un jeton « lié » et comment il expire.

**Objectifs pédagogiques**
- Comprendre ce qu'est un compte de service, ce que l'admission `ServiceAccount` fait d'un pod, et où se trouve le jeton monté.
- Désactiver le montage automatique (`automountServiceAccountToken`) au niveau du compte et du pod.
- Obtenir et lire un jeton lié (TokenRequest : `kubectl create token`, durée, audience, lien à un pod) et un jeton projeté par le kubelet.
- Savoir pourquoi les jetons « Secret » permanents ont disparu depuis 1.24, et quand on en crée encore un.

**Prérequis** : M14-E11.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Dans `mediagenda-dev` et `mediagenda-recette` : le compte `default` ne monte plus de jeton ; un compte `mediagenda-api`, **sans aucun droit RBAC** (l'API MédiAgenda ne parle pas à Kubernetes) et sans jeton monté, sera l'identité de l'application. Fichier `espaces/<espace>/30-comptes-service.yaml`.
- Essai dans `wb-essais` : compte `jeton-essai`, pod `jeton-projete` qui monte un jeton **projeté** d'audience `medisphere-essai`, valable 600 s, dans `/var/run/secrets/medisphere/jeton` (et aucun autre jeton).
- Exception connue : le compte `wb-checks` (E06) a un jeton permanent (Secret `kubernetes.io/service-account-token`), parce que les vérifications tournent hors du cluster sans renouvellement. Elle est documentée au registre des secrets.
- Pour lire un JWT : `cut -d. -f2 | base64 -d` (complète le remplissage `=` si besoin) ou `jq -R 'split(".") | .[1] | @base64d | fromjson'`.

**Travail demandé**
1. Dans `wb-essais`, lance un pod busybox minimal sans rien préciser. Retrouve dans sa spécification ce que l'admission a ajouté (volume `kube-api-access-…` : trois sources projetées). Lis le jeton depuis le pod, décode-le : audience, émetteur, expiration, champs `kubernetes.io` (pod, compte, nœud). Explique l'écart entre la durée demandée par le kubelet et la date `exp` du jeton.
2. Utilise ce jeton depuis le pod pour appeler l'API (`wget --header "Authorization: Bearer …" https://kubernetes.default.svc/api/v1/namespaces/wb-essais/pods`, avec la CA montée) : quelle réponse, et qu'est-ce qu'elle prouve (authentification réussie, autorisation refusée) ?
3. Écris `30-comptes-service.yaml` pour les deux espaces MédiAgenda (MR, application). Recrée un pod de test dans `mediagenda-dev` et vérifie qu'il n'a plus de jeton.
4. Jetons à la demande : `kubectl create token mediagenda-api -n mediagenda-dev --duration=10m`, décode-le ; puis un jeton **lié à un pod** (`--bound-object-kind Pod --bound-object-name …`) : supprime le pod et montre que le jeton est refusé aussitôt (TokenReview, ou appel de l'API). Essaie `--duration=1000h` : que reçois-tu ?
5. Applique `~/m14/e13/jeton-projete.yaml` (compte `jeton-essai`, pod `jeton-projete`). Vérifie l'audience du jeton projeté, puis montre que le kubelet le **renouvelle** (le contenu du fichier change avant 10 minutes). À quoi sert une audience dédiée ?
6. Cherche dans le cluster les Secrets de type `kubernetes.io/service-account-token` (`kubectl get secrets -A --field-selector type=…`) : il ne doit rester que celui de `wb-checks`. Lis l'étiquette `kubernetes.io/legacy-token-last-used` s'il y en a, et note ce que fait le nettoyage des jetons hérités.
7. Ajoute au journal (`~/m14/e13/journal.md`) une règle d'équipe en cinq lignes : quand monter un jeton, avec quelle audience, quand un jeton permanent est admissible.

**Critères de réussite**
- [ ] Dans les deux espaces MédiAgenda, `default` et `mediagenda-api` ont `automountServiceAccountToken: false` ; `mediagenda-api` n'est lié à aucun rôle.
- [ ] Aucun pod des espaces MédiAgenda ne monte de jeton d'API.
- [ ] Le pod `jeton-projete` tourne dans `wb-essais` avec un seul jeton, projeté, d'audience `medisphere-essai`, valable 600 s.
- [ ] Le journal contient les jetons décodés (sans la signature) et la règle d'équipe.

**Vérification** : `lab/bin/check 14 13`

<details><summary>Indice 1</summary>

Le kubelet renouvelle un jeton projeté quand il a atteint 80 % de sa durée de vie, ou au bout de 24 h. Le jeton du volume `kube-api-access-…` est demandé pour 3607 s, mais l'API peut en **prolonger** la validité (`exp`) pour ne pas casser les vieux clients qui ne relisent jamais le fichier ; le champ `warnafter` (sous `kubernetes.io`) dit à partir de quand elle signale ces clients. Compare `exp`, `iat` et `warnafter`.
</details>

<details><summary>Indice 2</summary>

`automountServiceAccountToken` existe aux deux niveaux : sur le compte (valeur par défaut des pods qui l'utilisent) et sur le pod (qui l'emporte). Pour monter un jeton choisi, c'est un volume `projected` de source `serviceAccountToken`, avec `audience`, `expirationSeconds` (600 au minimum) et `path`.
</details>

**Pour aller plus loin** (facultatif) : lis la documentation du kube-apiserver sur `--service-account-max-token-expiration` et `--service-account-extend-token-expiration`, puis repère leurs valeurs dans le manifeste statique de `k8s-cp01`.

---

### M14-E14 — Ordonnancement : affinités, taints et répartition  `LAB` `★★★`

> **Ticket PLAT-1514** — *De : Claire Morel*
> Deux exigences de l'architecture pour MédiAgenda. Un : les bases de données sur un nœud qui leur est réservé (`k8s-w03`), et rien d'autre dessus. Deux : la perte d'une baie ne doit jamais emporter toutes les instances de l'API ; nos nœuds sont répartis sur trois baies comme les serveurs Ceph. Et quand la place manque, je veux que ce soit la base qui passe devant les essais, pas l'inverse.

**Objectifs pédagogiques**
- Donner des étiquettes et des taints aux nœuds par le code, et comprendre ce que le kubelet a le droit de poser lui-même.
- Combiner taint + tolérance + affinité de nœud pour **réserver** un nœud (l'une sans l'autre ne suffit pas).
- Répartir des réplicas sur des domaines de panne avec `topologySpreadConstraints` et l'anti-affinité, et comprendre `whenUnsatisfiable`, `nodeTaintsPolicy`, `matchLabelKeys`.
- Utiliser les PriorityClasses et observer une préemption.

**Prérequis** : M14-E19 (MédiAgenda dans `mediagenda-dev`).
**Durée indicative** : 3 h.

**Contexte technique**
- Zones (étiquette standard `topology.kubernetes.io/zone`), mêmes noms que les baies CRUSH du M08 : `par1-baie-a` (`k8s-cp01`, `k8s-w01`), `par1-baie-b` (`k8s-cp02`, `k8s-w02`), `par1-baie-c` (`k8s-cp03`, `k8s-w03`).
- `k8s-w03` : étiquette `medisphere.internal/dedie=bdd`, taint `dedie=bdd:NoSchedule`.
- Source de vérité : `cluster/noeuds.yaml` dans `plateforme/k8s` (étiquettes et taints **MédiSphère** par nœud ; jamais celles de kubeadm), appliquée par un script idempotent `outils/etiqueter-noeuds.sh` (lu avec `yq`), appelé par une nouvelle tâche `etiquettes` du Taskfile (la tâche `noeuds` existe déjà : c'est la convergence Ansible) et rejoué après chaque jonction de nœud.
- PriorityClasses (`ordonnancement/priorites.yaml`, dossier à ajouter à la liste `DOSSIERS` du Taskfile ; pas dans `cluster/`, qui contient la configuration kubeadm) : `medisphere-critique` (100000), `medisphere-standard` (10000), `medisphere-essai` (100, ne préempte jamais). Aucune n'est la classe par défaut.
- Cibles MédiAgenda (`mediagenda/api`, `k8s/dev/`) : PostgreSQL (`postgresql`) en `medisphere-critique`, sur `k8s-w03` exclusivement ; l'API en `medisphere-standard`, **3 réplicas**, écart d'au plus 1 entre zones (contrainte stricte), sur des nœuds différents si possible.

**Travail demandé**
1. Lis *Assigning Pods to Nodes*, *Taints and Tolerations*, *Pod Topology Spread Constraints* et *Pod Priority and Preemption*. Dans `~/m14/e14/journal.md` : le kubelet peut-il poser lui-même `topology.kubernetes.io/zone` à son enregistrement ? Et `medisphere.internal/dedie` ? (cherche *NodeRestriction*).
2. Écris `cluster/noeuds.yaml` et `outils/etiqueter-noeuds.sh` (option `--dry-run`), ajoute la tâche `etiquettes`, MR, applique. Vérifie : `kubectl get nodes -L topology.kubernetes.io/zone,medisphere.internal/dedie`, `kubectl describe node k8s-w03 | grep -A2 Taints`.
3. Que sont devenus les pods qui tournaient déjà sur `k8s-w03` ? Explique (effet `NoSchedule` vs `NoExecute`), puis libère `k8s-w03` des charges qui n'ont rien à y faire **sans** toucher aux DaemonSets (Cilium).
4. Essai : un pod qui exige `medisphere.internal/dedie=bdd` sans tolérer la taint ; lis le message de l'ordonnanceur. Puis un pod qui tolère sans exiger : où va-t-il ?
5. PostgreSQL : ajoute tolérance, affinité de nœud requise et classe de priorité ; applique et vérifie qu'il tourne sur `k8s-w03`. ⚠️ Le pod est recréé : la base jetable repart vide, relance la migration (comme en E19).
6. API : passe à 3 réplicas, ajoute la contrainte de répartition par zone (stricte, écart 1), l'anti-affinité « préférée » par nœud et la classe de priorité. Applique : combien de réplicas sont `Running` ? Explique ce que tu vois avec `kubectl describe pod` sur un pod `Pending`, puis corrige la contrainte (lis bien la documentation des champs de la contrainte) jusqu'à 3/3 répartis sur deux zones.
7. Préemption, dans `wb-essais` : remplis les travailleurs de pods `medisphere-essai` (1 CPU chacun) jusqu'à en avoir en `Pending`, puis crée un pod `medisphere-critique` qui demande 1 CPU. Observe (`kubectl get events -n wb-essais`) qui est évincé. Nettoie.
8. Note dans le journal ce qui se passe pour l'API si `k8s-w01` tombe (combien de réplicas, où, et la contrainte reste-t-elle satisfaisable ?).

**Critères de réussite**
- [ ] Les six nœuds portent leur zone ; `k8s-w03` porte l'étiquette et la taint `dedie=bdd:NoSchedule` ; `cluster/noeuds.yaml` et `ordonnancement/priorites.yaml` sont sur `main`.
- [ ] Les trois PriorityClasses existent avec les valeurs demandées.
- [ ] PostgreSQL de `mediagenda-dev` tourne sur `k8s-w03` en `medisphere-critique` ; aucun pod applicatif n'est sur `k8s-w03` hors bases de données et DaemonSets.
- [ ] L'API a 3 réplicas prêts, répartis sur au moins deux zones, avec une contrainte de répartition par zone stricte ; aucun pod `Pending` dans `mediagenda-dev`.

**Vérification** : `lab/bin/check 14 14`

<details><summary>Indice 1</summary>

Une taint repousse, une affinité attire. Réserver un nœud, c'est les deux : la taint empêche les autres d'y aller, l'affinité empêche la base d'aller ailleurs.
</details>

<details><summary>Indice 2</summary>

Pour calculer l'écart entre zones, l'ordonnanceur compte les zones « éligibles ». Par défaut, il tient compte de l'affinité de nœud du pod, mais **pas** des taints des nœuds : une zone dont tous les nœuds sont « taintés » est éligible… et vide pour toujours.
</details>

<details><summary>Indice 3</summary>

`kubectl label node … --overwrite` et `kubectl taint node … --overwrite` sont idempotents. `yq -r '.noeuds | keys | .[]'` liste les nœuds d'un fichier ; avec `to_entries`, tu obtiens des couples clé=valeur.
</details>

**Pour aller plus loin** (facultatif) : ajoute à `mediagenda-dev` un second ResourceQuota à `scopeSelector` sur la PriorityClass `medisphere-critique` (au plus 2 pods) : une équipe ne peut plus se déclarer « critique » à volonté.

---

### M14-E15 — StatefulSets, DaemonSets, Jobs et CronJobs  `LAB` `★★`

> **Ticket DEV-1515** — *De : Julien Petit*
> Trois choses pour notre dev. La migration du schéma tourne aujourd'hui au démarrage de chaque pod de l'API : ça ralentit les montées en charge et ça oblige le compte de l'appli à avoir les droits DDL ; je la voudrais à part, une fois par version. Je voudrais un export de la base chaque nuit à 2 h 15, heure de Paris. Et on veut essayer Valkey avec deux répliques en lecture, pour voir.
>
> *Commentaire de Karim Benali* : et profites-en pour nous faire une petite sonde sur chaque nœud, plan de contrôle compris, pour comprendre les DaemonSets.

**Objectifs pédagogiques**
- Choisir le bon contrôleur : Deployment, StatefulSet, DaemonSet, Job, CronJob.
- Construire un StatefulSet : Service *headless*, identité stable (nom, ordinal, DNS), ordre de démarrage.
- Écrire un Job robuste (`backoffLimit`, `activeDeadlineSeconds`, `ttlSecondsAfterFinished`, `restartPolicy`) et un CronJob (`timeZone`, `concurrencyPolicy`, `startingDeadlineSeconds`, historique).
- Placer un DaemonSet sur tous les nœuds, y compris ceux qui portent des taints.

**Prérequis** : M14-E14.
**Durée indicative** : 2 h 30.

**Contexte technique**
- Valkey : StatefulSet `valkey` de 3 pods ; `valkey-0` primaire, `-1` et `-2` répliques de `-0` (option `--replicaof <hôte> 6379` de `valkey-server`) ; Service *headless* `valkey` ; données en `emptyDir` (pas de volume persistant avant le M16) ; pas de bascule automatique (M27). L'API écrit sur le primaire : `MEDIAGENDA_VALKEY_URL=redis://valkey-0.valkey:6379/0` ; options de cache inchangées depuis E08 (`--save ""`, `--maxmemory`…).
- Migration : Job `mediagenda-migration-v1-0-0` (la version dans le nom), étiquette `app.kubernetes.io/name: mediagenda-migration`, commande `python -m mediagenda.migrate`, gardé 7 jours après la fin ; l'`initContainer` de l'API disparaît.
- Export : CronJob `mediagenda-sauvegarde`, 02:15 heure de Paris, jamais deux exécutions simultanées, exécution manquée de plus de 15 minutes abandonnée, `pg_dump -Fc` (image `postgres:18-trixie` du cache) vers un `emptyDir`, taille et empreinte dans le journal. ⚠️ C'est un exercice : l'export disparaît avec le pod ; la vraie sauvegarde arrive au M16.
- Sonde : DaemonSet `sonde-noeud` dans `wb-essais`, busybox `httpd` sur 8080 qui répond le nom et l'adresse de son nœud (API descendante, *downward API*), sur les **six** nœuds.

**Travail demandé**
1. Dans `~/m14/e15/journal.md`, un tableau : pour chaque contrôleur (Deployment, StatefulSet, DaemonSet, Job, CronJob), ce qu'il garantit, son unité de mise à jour, un usage chez MédiSphère.
2. Valkey en StatefulSet. ⚠️ Le Service existant n'est pas *headless* et ce champ est immuable : supprime-le avant d'appliquer le nouveau fichier (coupure courte du cache, sans conséquence). Applique, observe l'ordre de création des pods, résous `valkey-1.valkey` depuis un pod, et vérifie la réplication (`valkey-cli info replication` sur `-0` et sur `-1`). Supprime `valkey-1` : quel nom, quelle identité a le pod recréé ?
3. Mets à jour la ConfigMap de l'API vers le primaire. L'API utilise-t-elle la nouvelle valeur ? Fais ce qu'il faut pour qu'elle la prenne.
4. Migration : écris le Job, retire l'`initContainer` de l'API. Lance le Job, attends sa fin (`kubectl wait --for=condition=Complete`), lis ses journaux. Essaie de le « réappliquer » après une modification de sa commande : que dit l'API ? Décris dans le journal la procédure de montée de version (Job de la nouvelle version, puis API).
5. Provoque un échec du Job (copie de test avec une mauvaise URL de base) : combien de pods, quel délai entre eux, quel état final ? Supprime la copie.
6. CronJob : écris-le, applique, puis déclenche une exécution **à la main** sans attendre la nuit (`kubectl create job --from=cronjob/…`). Vérifie le résultat dans les journaux. Explique ce que changerait l'absence de `timeZone` (dans quel fuseau tourne le kube-controller-manager ?) et ce que fait `concurrencyPolicy: Forbid` si un export dure plus de 24 h.
7. DaemonSet : applique la sonde dans `wb-essais` sans tolérance d'abord : sur combien de nœuds tourne-t-elle ? Ajoute ce qu'il faut pour qu'elle couvre les six. Interroge chaque pod (`kubectl get pods -o wide`, puis `wget` depuis un autre pod).

**Critères de réussite**
- [ ] `valkey` est un StatefulSet de 3 pods prêts, derrière un Service *headless* ; `-1` et `-2` répliquent `-0`.
- [ ] Un Job `mediagenda-migration-*` a réussi et sera gardé au moins un jour ; l'API n'a plus d'`initContainer`.
- [ ] Le CronJob `mediagenda-sauvegarde` est planifié à 2 h 15 en `Europe/Paris`, en `Forbid`, avec `startingDeadlineSeconds` ; au moins une de ses exécutions a réussi.
- [ ] Le DaemonSet `sonde-noeud` a un pod prêt sur chacun des six nœuds.

**Vérification** : `lab/bin/check 14 15`

<details><summary>Indice 1</summary>

Le nom d'hôte d'un pod de StatefulSet est son nom (`valkey-1`) : l'ordinal est ce qui suit le dernier tiret. Un `args` remplace le `CMD` de l'image mais garde son `ENTRYPOINT` (ici `tini` puis le script d'entrée de Valkey) ; un `command` remplacerait les deux.
</details>

<details><summary>Indice 2</summary>

Les répliques doivent résoudre le nom DNS de `-0` avant d'être prêtes elles-mêmes : regarde le champ `publishNotReadyAddresses` du Service. Pour la ConfigMap : une variable d'environnement est lue au **démarrage** du conteneur.
</details>

<details><summary>Indice 3</summary>

Un DaemonSet n'échappe pas aux taints : il lui faut des tolérances, comme à n'importe quel pod. Une tolérance `operator: Exists` **sans clé** tolère toutes les taints, y compris celles que Kubernetes pose sur un nœud en difficulté.
</details>

---

### M14-E16 — Mises à jour progressives, retour arrière et PDB  `LAB` `★★`

> **Ticket DEV-1516** — *De : Julien Petit*
> Hier, une mise à jour de la dev a coupé l'API une minute : les nouveaux pods n'étaient pas prêts que les anciens étaient déjà partis. Je veux des mises à jour sans aucune erreur côté client, pouvoir revenir en arrière en une commande, et que vos opérations sur les nœuds (Nadia parle de « drain ») ne nous coupent pas non plus.

**Objectifs pédagogiques**
- Régler une stratégie `RollingUpdate` (`maxSurge`, `maxUnavailable`, `minReadySeconds`, `progressDeadlineSeconds`) et la lier aux sondes de disponibilité.
- Suivre, historiser et annuler un déploiement (`rollout status`, `history`, `undo`, `kubernetes.io/change-cause`).
- Reconnaître un déploiement bloqué et comprendre que Kubernetes ne revient pas en arrière tout seul.
- Écrire un PodDisruptionBudget et savoir contre quoi il protège (et contre quoi il ne protège pas).

**Prérequis** : M14-E15.
**Durée indicative** : 2 h.

**Contexte technique**
- Cible pour `mediagenda-api` (dev) : un pod de plus pendant la mise à jour, **jamais** un de moins ; un nouveau pod compte comme disponible après 10 s de disponibilité continue ; mise à jour déclarée en échec au bout de 2 minutes sans progrès ; 5 révisions gardées.
- PDB `mediagenda-api` : au plus une instance indisponible lors d'une éviction volontaire ; un pod **déjà** malade doit pouvoir être évincé même si le budget est épuisé.
- Mesure de disponibilité : un pod `sonde-disponibilite` dans `wb-essais` interroge le **Service** (`http://mediagenda-api.mediagenda-dev.svc.cluster.local/sante`) toutes les 0,5 s et journalise `OK` ou `ECHEC` (fichier `~/m14/e16/sonde-disponibilite.yaml`, busybox `wget -T 2`).
- Il n'existe qu'une image applicative (`v1.0.0`) : une « nouvelle version » sera ici un changement du gabarit de pod (une variable d'environnement), ce qui crée une révision exactement comme une nouvelle image. Si tu as publié une `v1.0.1` au M13, utilise-la en plus.

**Travail demandé**
1. Lis *Deployments* (sections *Rolling Update Deployment*, *Rolling Back*, *Failed Deployment*) et *Specifying a Disruption Budget*. Dans `~/m14/e16/journal.md` : avec 3 réplicas, `maxSurge: 25 %` et `maxUnavailable: 25 %` (valeurs par défaut), combien de pods au plus et au moins pendant une mise à jour ? Pourquoi la coupure d'hier ?
2. Lance la sonde de disponibilité. Fais une première mise à jour **avec la stratégie par défaut** (ajoute `MEDIAGENDA_LOG_LEVEL=DEBUG` dans l'`env` du conteneur, avec une annotation `kubernetes.io/change-cause`) ; compte les `ECHEC`.
3. Règle la stratégie, `minReadySeconds`, `progressDeadlineSeconds`, `revisionHistoryLimit` dans `40-api.yaml` (MR dans `mediagenda/api`). Refais une mise à jour (retour à `INFO`) en suivant `kubectl rollout status` : compte les `ECHEC`, et explique la différence.
4. Mise à jour cassée n° 1 : une étiquette d'image qui n'existe pas (`v9.9.9`). Que deviennent les anciens pods ? Que dit `kubectl rollout status`, puis la condition `Progressing` après 2 minutes ? Reviens en arrière avec `kubectl rollout undo`, puis remets le fichier versionné en cohérence.
5. Mise à jour cassée n° 2 : une image correcte mais `MEDIAGENDA_VALKEY_URL` vers un hôte inexistant (variable d'`env` du conteneur). Les pods démarrent-ils ? Sont-ils prêts ? Le service est-il coupé ? Reviens à une révision précise (`rollout history`, `undo --to-revision`).
6. Écris le PDB (`45-pdb.yaml`). Vérifie son état (`kubectl get pdb`). Essaie d'évincer deux pods de l'API à la suite par l'API d'éviction (`kubectl drain` le fera en E17 ; ici, `kubectl evict` n'existe pas : cherche comment créer un objet `Eviction`, ou attends E17). Note ce que le PDB n'empêche pas (`kubectl delete pod`, nœud qui tombe, mise à jour du Deployment).
7. Dans le journal : pourquoi le retour arrière automatique n'existe pas dans un Deployment, et ce qui le fournira plus tard (GitOps au M20, déploiement progressif).

**Critères de réussite**
- [ ] `mediagenda-api` : `maxUnavailable: 0`, `maxSurge` ≥ 1, `minReadySeconds` > 0, `progressDeadlineSeconds` ≤ 300, et le Deployment est entièrement à jour et disponible.
- [ ] L'historique du Deployment contient au moins trois révisions ; la révision courante correspond au fichier versionné (image `v1.0.0` ou ta `v1.0.1`).
- [ ] Le PDB `mediagenda-api` existe, sélectionne les 3 pods de l'API, autorise une perturbation, avec la politique d'éviction des pods malades demandée.
- [ ] Le journal contient les comptes d'`ECHEC` des étapes 2 et 3 et les réponses des étapes 4 et 5.

**Vérification** : `lab/bin/check 14 16`

<details><summary>Indice 1</summary>

`maxUnavailable: 0` ne sert à rien sans sonde de disponibilité honnête : c'est elle qui dit au contrôleur qu'un nouveau pod peut recevoir du trafic. Ici, `/pret` vérifie PostgreSQL **et** Valkey.
</details>

<details><summary>Indice 2</summary>

`kubectl rollout status` attend ; sa sortie s'arrête en erreur quand `progressDeadlineSeconds` est dépassé. `kubectl get deploy mediagenda-api -o jsonpath='{.status.conditions}'` montre la raison. `kubectl rollout history … --revision=N` montre le gabarit d'une révision.
</details>

<details><summary>Indice 3</summary>

Une éviction est une sous-ressource du pod (`pods/eviction`) : un `POST` d'un objet `Eviction` (`policy/v1`) que l'API refuse avec un code 429 quand le budget est épuisé. `kubectl create --raw` sait envoyer un corps JSON vers un chemin d'API.
</details>

---

### M14-E17 — Drainer, ajouter et retirer un nœud  `LAB` `★★`

> **Ticket PLAT-1517** — *De : Nadia Roussel*
> Avant de vous laisser seuls la nuit avec ce cluster, je veux que l'équipe ait fait les trois gestes à froid : sortir un travailleur pour maintenance sans casser MédiAgenda, ajouter un travailleur neuf, et en retirer un proprement, jusqu'à la VM. Faites-le avec un quatrième nœud, et que la fiche de changement soit assez précise pour que je la rejoue.

**Objectifs pédagogiques**
- Mettre un nœud en maintenance (`cordon`, `drain`) en respectant les PDB, et comprendre ce que `drain` refuse par défaut.
- Ajouter un travailleur par le code (OpenTofu, NetBox, Ansible, jeton de jonction kubeadm) et lui donner ses étiquettes.
- Retirer un nœud proprement (drain, `kubectl delete node`, `kubeadm reset`, nettoyage), puis détruire la VM par le code.
- Rédiger une fiche de changement rejouable.

**Prérequis** : M14-E16 (PDB), M14-E14 (`cluster/noeuds.yaml`), M14-E05 (rôle `k8s_travailleur`).
**Durée indicative** : 3 h.

**Contexte technique**
- `k8s-w04` : VMID **2147**, 10.10.40.64, MAC `bc:24:11:40:00:64`, mêmes ressources que `k8s-w01-03` (4 vCPU, 8 Go, 60 Go `local-nvme`), étiquettes Proxmox `env-k8s` et `role-k8s-worker`, zone `par1-baie-a`. L'état `k8s` de `plateforme/infra` le prévoit depuis E02 : variable `avec_k8s_w04` (`false` par défaut). Enregistré dans NetBox comme les autres nœuds, il rejoint les groupes d'inventaire `k8s_par1` et `k8s_travailleurs` (source `netbox-k8s.yml`).
- Mémoire : 8 Go de plus sur `pve01` pendant l'exercice. Vérifie ta marge avant.
- Jonction : le rôle `k8s_travailleur` (E05) obtient un jeton de jonction sur `k8s-cp01` (durée de vie courte) ; aucun jeton n'est écrit dans un dépôt.
- Maintenance simulée : `k8s-w02` (un réplica de l'API y tourne, et un pod de chaque DaemonSet).
- Fiche de changement : `docs/kubernetes/changements/CHG-1517-ajout-retrait-noeud.md` dans `plateforme/medisphere`.

**Travail demandé**
1. Rédige la fiche de changement **avant** d'agir : objectif, prérequis (marge mémoire, état du cluster, PDB), étapes, contrôles, retour arrière, critères de fin.
2. Maintenance de `k8s-w02` : lance la sonde de disponibilité d'E16, puis `kubectl drain k8s-w02` **sans option** : lis le refus. Ajoute les options strictement nécessaires (explique chacune dans la fiche), et observe l'ordre des évictions, le respect du PDB, les pods recréés ailleurs. Combien d'`ECHEC` ? Remets le nœud en service (`uncordon`) : les pods reviennent-ils seuls sur `k8s-w02` ?
3. Ajout de `k8s-w04` : VM par MR dans `plateforme/infra`, NetBox, DNS, puis le playbook du cluster limité au nouveau nœud. Ajoute le nœud à `cluster/noeuds.yaml`, `task etiquettes`. Vérifie : nœud `Ready`, zone, pods Cilium et `sonde-noeud` dessus, `kubeadm` n'a laissé aucun jeton valable au-delà de sa durée (`kubeadm token list` sur `k8s-cp01`).
4. Fais tourner de vraies charges sur `k8s-w04` : drain de `k8s-w01`, puis `uncordon`. Où sont les réplicas de l'API ?
5. Retrait de `k8s-w04` : drain, `kubectl delete node`, puis sur le nœud `kubeadm reset` (lis ce que la commande dit ne **pas** nettoyer et fais-le), arrêt de la VM. Retire le nœud de `cluster/noeuds.yaml`, repasse `avec_k8s_w04` à `false` (MR dans `plateforme/infra` : la VM est détruite par le pipeline) et retire-le de NetBox.
6. Ferme la fiche (résultat, écarts, durées). Tire-en les éléments pour RB-140 (E22).

**Critères de réussite**
- [ ] `k8s-w04` n'est plus un nœud du cluster, la VM 2147 n'existe plus et n'est plus active dans NetBox.
- [ ] Aucun nœud n'est resté `SchedulingDisabled` ; les six nœuds de référence sont `Ready`.
- [ ] La fiche `CHG-1517-ajout-retrait-noeud.md` est publiée, avec les options de `drain` justifiées et le nombre d'`ECHEC` mesuré.

**Vérification** : `lab/bin/check 14 17`

<details><summary>Indice 1</summary>

`drain` = `cordon` + éviction de chaque pod par l'API d'éviction (donc PDB respectés). Il refuse par défaut les pods de DaemonSet (ils reviendraient aussitôt) et les pods qui ont un volume `emptyDir` (leurs données seraient perdues) : à toi de décider si c'est acceptable, ici, pour une base jetable.
</details>

<details><summary>Indice 2</summary>

`kubeadm reset` ne nettoie ni les règles iptables/nftables, ni la configuration CNI (`/etc/cni/net.d`), ni le fichier kubeconfig de l'utilisateur : il le dit dans sa sortie. Pour la VM, c'est le retrait de sa déclaration dans l'état `k8s` qui la détruit, pas un `qm destroy`.
</details>

---

### M14-E18 — Admission : Pod Security et ValidatingAdmissionPolicy  `LAB` `★★★`

> **Ticket SEC-1518** — *De : Sophie Laurent*
> Les manifestes passent par des MR, très bien, mais rien n'empêche aujourd'hui un pod root, privilégié ou monté sur le disque du nœud, ni une image tirée de n'importe où, en `latest`. Je veux des règles **dans le cluster** : le niveau de sécurité le plus strict pour les espaces des équipes, un niveau raisonnable ailleurs, des images qui viennent toutes de notre Harbor avec une version explicite. Et la mise en service ne doit casser personne par surprise.

**Objectifs pédagogiques**
- Situer l'admission dans le traitement d'une requête (authentification, autorisation, mutation, validation, persistance).
- Appliquer les profils Pod Security Standards par étiquettes d'espace (`enforce`, `warn`, `audit`, versions), et mesurer l'effet d'un changement **avant** de l'imposer.
- Écrire une ValidatingAdmissionPolicy en CEL, avec paramètres et liaison, et la mettre en service progressivement (`Warn`/`Audit` puis `Deny`).
- Savoir ce que ces mécanismes ne couvrent pas (et ce qu'apportera Kyverno au M26).

**Prérequis** : M14-E15 (MédiAgenda complet dans `mediagenda-dev`), M14-E19 (images par Harbor).
**Durée indicative** : 3 h.

**Contexte technique**
- Pod Security : `restricted` **appliqué** sur `mediagenda-dev` et `mediagenda-recette` (version d'application figée à `v1.35`, signalement et audit en `latest`) ; `baseline` appliqué sur `wb-essais` (signalement et audit `restricted`) ; `restricted` sur `wb-system` ; `kube-system` sans étiquette (privilégié par défaut). L'espace `wb-diagnostic` (E20) est `privileged` : exception documentée.
- Politique `medisphere-images` (`admission/` de `plateforme/k8s`) : refuse, dans les espaces portant l'étiquette `medisphere.internal/equipe`, tout pod **et** tout contrôleur de pods (Deployment, StatefulSet, DaemonSet, ReplicaSet, Job, CronJob) dont une image (conteneurs, `initContainers`, conteneurs éphémères) n'est pas sous `registry.par1.medisphere.internal/`, ou n'a ni étiquette ni condensé, ou est en `latest`. La liste des registres autorisés est un **paramètre** : ConfigMap `medisphere-images` de `kube-system`, clé `registres` (préfixes séparés par des virgules).
- La journalisation d'audit de l'API n'arrive qu'en E27 : en attendant, un refus ou un avertissement se lit dans la réponse de l'API (sortie de `kubectl`) et dans les annotations d'audit plus tard.
- Fichiers d'essai dans `~/m14/e18/`.

**Travail demandé**
1. Lis *Pod Security Admission*, *Pod Security Standards* et *Validating Admission Policy*. Dans `~/m14/e18/journal.md` : à quelle étape agit chaque mécanisme ? Pourquoi `enforce` ne touche-t-il pas aux pods déjà en marche, et que se passe-t-il pour un Deployment dont le gabarit viole le profil ?
2. **Avant** d'imposer : demande au serveur ce que donnerait l'étiquette `enforce=restricted` sur chaque espace (`kubectl label --dry-run=server --overwrite ns …`). Note les avertissements, corrige les manifestes fautifs (MR dans `mediagenda/api` si besoin), recommence jusqu'à ne plus en avoir dans `mediagenda-*`.
3. Ajoute les étiquettes Pod Security aux fichiers d'espace (`espaces/…`), MR, `task appliquer`. Vérifie avec `~/m14/e18/refuses.yaml` (premier objet : un pod sans contexte de sécurité) en `--dry-run=server`.
4. Écris la ValidatingAdmissionPolicy, sa ConfigMap de paramètres et sa liaison, avec d'abord `validationActions: [Warn, Audit]`. Applique, puis lance `kubectl apply --dry-run=server` sur des objets conformes et non conformes : un pod tiré de `docker.io`, une étiquette `latest`, une image sans étiquette, un Deployment non conforme. Lis les messages.
5. Recense ce qui tourne dans les espaces des équipes et ne passerait pas la règle (un `jq` sur `kubectl get pods -A -o json`). Quand il n'y a plus rien, passe la liaison en `[Deny]` (MR).
6. Vérifie que les objets conformes passent (`~/m14/e18/accepte.yaml`), que la règle ne s'applique pas à `kube-system` ni à `wb-essais`, et que modifier la ConfigMap (ajouter un préfixe fictif) change la décision sans toucher à la politique.
7. Limites, dans le journal : un conteneur éphémère ajouté par `kubectl debug` passe-t-il par cette politique ? Que se passe-t-il si la ConfigMap de paramètres est supprimée (lis `parameterNotFoundAction`) ? Que ne peut pas vérifier une politique CEL (signature d'image, existence réelle de l'étiquette dans Harbor) ?

**Critères de réussite**
- [ ] `mediagenda-dev` et `mediagenda-recette` sont en `enforce=restricted` (version figée), avec `warn` et `audit` ; `wb-essais` en `enforce=baseline` ; `wb-system` en `restricted`.
- [ ] La politique `medisphere-images` et sa liaison existent, liaison en `Deny`, limitée aux espaces des équipes, avec la ConfigMap de paramètres ; `failurePolicy: Fail`.
- [ ] Tous les pods des espaces MédiAgenda sont conformes à `restricted` et n'utilisent que des images de `registry.par1.medisphere.internal` avec une version explicite.
- [ ] Les fichiers `espaces/` et `admission/` sont sur `main` ; le journal répond aux questions des étapes 1 et 7.

**Vérification** : `lab/bin/check 14 18`

<details><summary>Indice 1</summary>

`kubectl label --dry-run=server` fait évaluer par le contrôleur Pod Security les pods **existants** de l'espace contre le nouveau niveau : les avertissements listent les pods qui seraient refusés s'ils étaient recréés.
</details>

<details><summary>Indice 2</summary>

En CEL, une variable (`spec.variables`) évite de répéter l'accès à la spécification de pod selon le type d'objet (`object.spec`, `object.spec.template.spec`, `object.spec.jobTemplate.spec.template.spec`). `has()` teste un champ facultatif ; `filter`, `exists`, `all`, `map` parcourent une liste ; `startsWith`, `endsWith`, `contains`, `split` et `join` travaillent les chaînes.
</details>

<details><summary>Indice 3</summary>

L'image `registry.par1.medisphere.internal:443/x/y` contient un deux-points qui n'est pas une étiquette : ne cherche l'étiquette que dans le **dernier** segment après `/`. `messageExpression` permet un message qui cite l'image fautive.
</details>

**Pour aller plus loin** (facultatif) : lis *MutatingAdmissionPolicy* (GA en 1.36) : que pourrait-on muter plutôt que refuser, et pourquoi Sophie préfère-t-elle refuser ?

---

### M14-E19 — Tirer les images depuis Harbor  `LAB` `★★`

> **Ticket PLAT-1519** — *De : Karim Benali*
> Les nœuds tirent encore les images publiques directement d'Internet : Docker Hub nous limitera, et on ne sait pas ce qui entre. Fais passer tous les tirages des nœuds par les caches de Harbor, et déploie MédiAgenda dans `mediagenda-dev` avec l'image privée du projet `medisphere`, sans que l'équipe de Julien ait à manipuler d'identifiants. Montre-moi dans Harbor que ça passe bien par lui.

**Objectifs pédagogiques**
- Configurer des miroirs de registre dans containerd (`hosts.toml`, `config_path`) par le rôle Ansible, et comprendre `override_path` avec les caches Harbor.
- Créer un Secret de tirage (`kubernetes.io/dockerconfigjson`) sans exposer le secret, et le porter par un compte de service plutôt que par chaque pod.
- Choisir `imagePullPolicy` et comprendre le risque d'une image privée déjà présente sur un nœud.
- Prouver, côté Harbor, l'origine des tirages.

**Prérequis** : M14-E13, M13-E04 (caches Harbor `dockerhub`, `quay`, `ghcr`, `k8s`), M13-E03 (robot `robot$k8s-pull`), M14-E02 (rôle `containerd`).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Miroirs : variable `containerd_miroirs` du rôle `containerd` (`group_vars/k8s_par1/containerd.yml`, vide depuis E02) : `docker.io` → `https://registry.par1.medisphere.internal/v2/dockerhub`, `quay.io` → `…/v2/quay`, `ghcr.io` → `…/v2/ghcr`, `registry.k8s.io` → `…/v2/k8s`, chacun avec `override_path: true` et son serveur d'origine en repli. La CA MédiSphère est dans le magasin de certificats des nœuds (rôle `ca_lab` du playbook `k8s-noeuds.yml`) : containerd l'utilise. Les `hosts.toml` sont relus à chaque tirage (pas de redémarrage).
- Flux : VLAN 40 → `reg01` 443 est ouvert depuis M13 (vérifie-le dans `group_vars/role_routeur/pare_feu.yml`).
- Robot : `robot$k8s-pull` (système, tirage seul), identifiants dans `~/.config/workbook/harbor-k8s-pull.env` (600, `HARBOR_USER='robot$k8s-pull'` et `HARBOR_PASSWORD='…'`, **entre apostrophes** : le `$` du nom ne doit pas être interprété) ; copie dans le Vault `critique`.
- Outils à écrire dans `plateforme/k8s` : `outils/secret-tirage.sh ESPACE…` (Secret `harbor-pull`, jamais versionné) et `outils/secret-mediagenda.sh ESPACE` (Secret `mediagenda-db`, clé `mot-de-passe` aléatoire, créé s'il n'existe pas : base jetable).
- Comptes de service de `mediagenda-dev` et `mediagenda-recette` (`default`, `mediagenda-api`) : `imagePullSecrets: [harbor-pull]` (`espaces/<espace>/30-comptes-service.yaml`).
- Manifestes de l'équipe : `mediagenda/api`, dossier `k8s/dev/` (`10-config.yaml`, `20-postgresql.yaml`, `30-valkey.yaml`, `40-api.yaml`), repris de `k8s/essais/` (E07-E08) : mêmes noms d'objets, mais **chemins Harbor explicites** pour toutes les images (`registry.par1.medisphere.internal/dockerhub/library/postgres:18-trixie`…) et plus de `imagePullSecrets` dans les pods. La migration reste un `initContainer` pour l'instant (E15 la sortira).

**Travail demandé**
1. Lis *containerd → Registry Configuration* (`hosts.toml`) et *Pull an Image from a Private Registry*. Dans `~/m14/e19/journal.md` : quelle est la différence entre tirer `docker.io/library/postgres:18-trixie` à travers un miroir et tirer `registry.par1.medisphere.internal/dockerhub/library/postgres:18-trixie` ? Laquelle des deux formes la règle d'admission d'E18 exigera-t-elle, et pourquoi ?
2. Remplis `containerd_miroirs` (MR dans `plateforme/ansible`), applique le rôle sur **un** travailleur d'abord (`--limit k8s-w01`), puis sur les autres et les nœuds de contrôle. Sur `k8s-w01` : `crictl pull docker.io/library/busybox:1.37` puis `crictl pull registry.k8s.io/pause:3.10.1` ; retrouve les deux dépôts dans les projets `dockerhub` et `k8s` de Harbor (interface ou API : nombre de tirages, date), et l'adresse du nœud dans les journaux du proxy de Harbor sur `reg01`.
3. Prouve que l'image privée ne se tire pas sans identifiants : `crictl pull registry.par1.medisphere.internal/medisphere/mediagenda-api:v1.0.0` sur un nœud. Lis l'erreur.
4. Écris `outils/secret-tirage.sh` (le mot de passe ne doit apparaître ni à l'écran, ni dans un fichier en clair, ni dans la ligne de commande d'un processus) et `outils/secret-mediagenda.sh`. MR. Crée `harbor-pull` dans `mediagenda-dev` et `mediagenda-recette`, et `mediagenda-db` dans `mediagenda-dev`. Décode `harbor-pull` pour vérifier son format, sans afficher le mot de passe.
5. Ajoute `imagePullSecrets` aux comptes de service (MR, `task appliquer`). Crée un pod de test qui utilise l'image privée **sans** nommer de Secret : retrouve dans sa spécification ce que l'admission y a ajouté.
6. Déploie MédiAgenda dans `mediagenda-dev` (MR dans `mediagenda/api`, puis `kubectl apply -f k8s/dev/` depuis ta copie à jour de `main`). Vérifie `/pret` à travers le Service (`kubectl port-forward svc/mediagenda-api 8080:80 -n mediagenda-dev`), puis crée un rendez-vous et relis-le.
7. `imagePullPolicy` : quelle valeur s'applique à `v1.0.0` si tu n'en écris pas ? Si un pod d'un **autre** espace, sans Secret, demande la même image privée sur un nœud qui l'a déjà, que se passe-t-il ? Essaie-le dans `wb-essais` avec `IfNotPresent` puis `Always`, et explique pourquoi c'est un problème de sécurité (cherche la porte de fonctionnalité `KubeletEnsureSecretPulledImages` et son état dans ta version).
8. Épingle les images par condensé dans un essai (`…@sha256:…`, condensé lu dans Harbor) et note ce que cela change pour les mises à jour et pour Renovate (M13).

**Critères de réussite**
- [ ] Les six nœuds ont un `hosts.toml` vers Harbor pour `docker.io`, `quay.io`, `ghcr.io` et `registry.k8s.io`, posé par le rôle `containerd`.
- [ ] Harbor montre des dépôts tirés par le cluster dans ses caches (au moins `k8s/pause` et un dépôt de `dockerhub`).
- [ ] Dans `mediagenda-dev` et `mediagenda-recette`, `default` et `mediagenda-api` portent `harbor-pull` ; aucun Secret n'est versionné.
- [ ] MédiAgenda tourne dans `mediagenda-dev` (API prête, image `medisphere/mediagenda-api` de Harbor, compte `mediagenda-api`), toutes ses images sous `registry.par1.medisphere.internal/`.

**Vérification** : `lab/bin/check 14 19`

<details><summary>Indice 1</summary>

Avec `override_path = true`, containerd n'ajoute pas `/v2` au chemin du miroir : il demande `<miroir>/<dépôt>/manifests/<réf>`. C'est ce qu'il faut pour un cache Harbor, dont l'API pour le projet `dockerhub` est sous `https://registry.par1.medisphere.internal/v2/dockerhub/`.
</details>

<details><summary>Indice 2</summary>

Le contenu d'un Secret `dockerconfigjson` est un JSON `{"auths": {"<registre>": {"username": …, "password": …, "auth": base64(username:password)}}}`. `jq -n` sait construire ce JSON à partir de **variables d'environnement** (`env.NOM`), et `kubectl create secret generic … --type=kubernetes.io/dockerconfigjson --from-file=.dockerconfigjson=/dev/stdin` le lit sur l'entrée standard.
</details>

<details><summary>Indice 3</summary>

Si une variable d'environnement doit en contenir une autre (l'URL de la base contient le mot de passe), Kubernetes sait l'interpoler : `$(NOM)` dans `value`, à condition que `NOM` soit défini **plus haut** dans la liste `env`. C'est ce que fait déjà `k8s/essais/` (E08).
</details>

---

### M14-E20 — Diagnostiquer un pod  `LAB` `★★`

> **Ticket INC-4120** — *De : Nadia Roussel*
> Cette nuit, l'astreinte a mis quarante minutes à comprendre pourquoi un pod ne démarrait pas : elle a tout essayé dans le désordre. Je veux une méthode, toujours la même, et les outils qui vont avec, y compris quand l'image n'a pas de shell et quand le problème est sur le nœud. Et qu'on puisse enfin voir la consommation réelle des pods, sans attendre Prometheus.

**Objectifs pédagogiques**
- Suivre une démarche fixe : état et raison → événements → journaux (y compris du conteneur précédent) → intérieur du conteneur → nœud.
- Utiliser `kubectl debug` : conteneur éphémère (`--target`), copie de pod, pod de diagnostic de nœud (`node/…`, profils).
- Installer metrics-server (Helm comme simple installateur) et lire `kubectl top`.
- Distinguer les états : `Pending`, `ContainerCreating`, `CreateContainerConfigError`, `CrashLoopBackOff`, `OOMKilled`, `Running` non prêt.

**Prérequis** : M14-E19, M14-E08 (sondes, ressources).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Pods à diagnostiquer : `ressources/E20-diagnostic.yaml` (cinq pods `diag-*` et leurs objets, dans `wb-essais`, étiquette `medisphere.internal/exercice: e20`). Applique-le tel quel ; ne le lis pas pour trouver les causes.
- Images de diagnostic : `registry.par1.medisphere.internal/dockerhub/library/busybox:1.37` ; les outils du nœud (`crictl`, `journalctl`) s'utilisent depuis le pod de diagnostic de nœud par `chroot /host`.
- Pods de diagnostic de nœud : espace `wb-diagnostic` (`espaces/wb-diagnostic.yaml`, Pod Security `privileged` : il partage réseau, processus et disque de l'hôte), vidé après chaque usage.
- metrics-server : chart `metrics-server` **3.14.0** (application 0.9.0) du dépôt `https://kubernetes-sigs.github.io/metrics-server/`, espace `kube-system`, valeurs dans `composants/metrics-server/values.yaml` : 2 réplicas sur deux nœuds, PDB, ressources. Les certificats de service des kubelets sont auto-signés au M14 : metrics-server doit être autorisé à ne pas les vérifier (`--kubelet-insecure-tls`), **dette** consignée, levée en E26. Installation : `helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/` puis `helm upgrade --install metrics-server metrics-server/metrics-server --version 3.14.0 -n kube-system -f composants/metrics-server/values.yaml` (Helm sera enseigné au M17 ; ici, tu l'utilises comme un installateur).

**Travail demandé**
1. Écris dans `~/m14/e20/journal.md` ta démarche en cinq étapes (quelle commande, quelle information attendue), avant de commencer.
2. Applique `ressources/E20-diagnostic.yaml`. Pour **chacun** des cinq pods, note : état et raison (`kubectl get`, `-o jsonpath` sur `status.containerStatuses`), événements, journaux (`--previous` quand il le faut), cause, correction. Un des pods n'a pas de problème : prouve-le, et dis ce qui le rend difficile à inspecter.
3. Conteneur éphémère : sur `diag-sans-shell`, `kubectl exec` échoue ; ajoute un conteneur éphémère busybox qui partage l'espace de processus du conteneur (`--target`), et lis la commande et l'utilisateur du processus principal (`/proc/1/…`). Lire aussi ses variables d'environnement demande d'être le même utilisateur que lui, dans un espace `baseline` : trouve comment (lis `kubectl debug --help`, options `--profile` et `--custom`).
4. Copie de pod : sur `diag-crash`, fais une copie du pod dont tu remplaces la commande par un shell (`kubectl debug … --copy-to … -it -- sh`), pour explorer sans que le conteneur meure. Supprime la copie.
5. Nœud : ajoute `espaces/wb-diagnostic.yaml` (MR, `task appliquer`), puis `kubectl debug node/k8s-w01 -n wb-diagnostic --profile=sysadmin --image=… -it`. Depuis ce pod : `chroot /host`, `crictl ps`, `crictl inspect` d'un conteneur `diag-*`, `journalctl -u kubelet --since -10min`, l'OOM du noyau (`journalctl -k`). Supprime le pod de diagnostic.
6. metrics-server : écris `composants/metrics-server/values.yaml`, ajoute une tâche `metrics-server` au Taskfile, MR, installe. Vérifie l'`APIService` `v1beta1.metrics.k8s.io`, puis `kubectl top node`, `kubectl top pod -A --sort-by=memory`, `kubectl top pod -n mediagenda-dev --containers`. Compare la consommation réelle de l'API aux requêtes déclarées.
7. Répare les pods `diag-*` dans `~/m14/e20/diagnostic-corrige.yaml` (ce qui est immuable dans un pod impose de le recréer), applique : les cinq doivent être `Running` et prêts. Utilise `kubectl top` pour dimensionner celui qui en a besoin.
8. Complète ta démarche (étape 1) avec ce que tu as appris : c'est la base de RB-140 (E22) et des pannes du palier 4.

**Critères de réussite**
- [ ] metrics-server (chart 3.14.0) tourne en deux réplicas dans `kube-system` ; l'API `metrics.k8s.io` est disponible et `kubectl top node` répond pour les six nœuds.
- [ ] Les cinq pods `diag-*` de `wb-essais` sont `Running` et prêts.
- [ ] `wb-diagnostic` existe en Pod Security `privileged`, et aucun pod n'y reste.
- [ ] Le journal contient, pour chaque pod, état, preuve et cause, et la démarche finale.

**Vérification** : `lab/bin/check 14 20`

<details><summary>Indice 1</summary>

Un conteneur qui redémarre en boucle a deux histoires : celle du conteneur courant (`kubectl logs`) et celle du précédent (`kubectl logs --previous`). La raison du dernier arrêt et son code de sortie sont dans `status.containerStatuses[].lastState.terminated`. Un code 137, c'est 128 + 9 (SIGKILL).
</details>

<details><summary>Indice 2</summary>

Un pod qui n'arrive même pas à créer son conteneur n'a pas de journal : tout est dans les événements (`kubectl describe pod`, ou `kubectl get events --field-selector involvedObject.name=…`). Un pod `Running` mais non prêt sort des points de terminaison de son Service : `kubectl get endpointslices -l kubernetes.io/service-name=…`.
</details>

<details><summary>Indice 3</summary>

Les profils de `kubectl debug` (`--profile`) fixent le contexte de sécurité du conteneur de diagnostic. Pour un nœud, le système de fichiers de l'hôte est monté sous `/host` dans le pod de diagnostic. Les conteneurs éphémères respectent la règle Pod Security de l'espace : dans un espace `restricted`, il faut un profil compatible.
</details>

---

### M14-E21 — Revue : les manifestes du stagiaire  `REV` `★★`

> **Ticket PLAT-1521** — *De : Karim Benali* — *Copie : Lucas Martin, Julien Petit*
> Lucas a préparé le déploiement de MédiAgenda en recette (MR !12 sur `mediagenda/api`), « testé sur kind ». Julien en a besoin lundi pour sa campagne de recette. Fais une vraie revue : chaque défaut, sa gravité, ce qu'il casserait **chez nous** (quotas, Pod Security, politique d'images, RBAC, drain). Puis déploie la version corrigée en recette.

**Objectifs pédagogiques**
- Relire des manifestes Kubernetes en pensant au cluster réel (admission, quotas, ordonnancement, opérations), pas seulement à la syntaxe.
- Repérer les défauts de sécurité, de disponibilité et d'exploitation, et les hiérarchiser.
- Rédiger une revue utile à un débutant, puis livrer la correction.

**Prérequis** : M14-E10 à M14-E19.
**Durée indicative** : 2 h.

**Contexte technique**
- Fichiers : `ressources/E21-manifestes-lucas/` (`MR-lucas.md`, `00-secret.yaml`, `10-config.yaml`, `20-postgresql.yaml`, `30-valkey.yaml`, `40-api.yaml`, `45-pdb.yaml`). Le mot de passe qu'ils contiennent est **fictif**.
- Cible : `mediagenda-recette` (quota, LimitRange, comptes de service, `harbor-pull` en place depuis E10-E19 ; Pod Security `restricted` et politique d'images depuis E18). Le Secret `mediagenda-db` de recette se crée par `outils/secret-mediagenda.sh`.
- La version corrigée va dans `mediagenda/api`, dossier `k8s/recette/` (même structure que `k8s/dev/`, plus le Job de migration et le PDB), par une MR qui remplace celle de Lucas.

**Travail demandé**
1. Lis tout, sans rien noter. Puis réponds : combien d'instances de l'API et de la base tourneraient, sur quels nœuds ? Où est le mot de passe de la base, et qui peut le lire (pense au groupe `medisphere:lecture`) ? Que se passe-t-il au `kubectl apply` dans `mediagenda-recette` ?
2. Confirme par le serveur : `kubectl apply --dry-run=server -f ressources/E21-manifestes-lucas/` ; classe chaque refus ou avertissement par mécanisme (quota, LimitRange, Pod Security, politique d'images). Quels défauts graves **passent** l'admission ?
3. Rédige la revue en tableau : n°, fichier et ligne(s), défaut, catégorie (sécurité, disponibilité, exploitation, fonctionnel), gravité (critique, élevée, moyenne, faible), impact concret chez nous, correction. Au moins 12 défauts.
4. Classe les défauts par ordre de traitement ; justifie les trois premiers.
5. Écris la version corrigée dans `k8s/recette/` (MR), crée le Secret de recette, applique (Job de migration d'abord). Vérifie que l'API répond à travers son Service.
6. Trois lignes de conseils à Lucas sur sa façon de tester (« testé sur kind »).

**Critères de réussite**
- [ ] La revue compte au moins 12 défauts, dont tous les défauts critiques et élevés du corrigé, chacun avec un impact concret et une correction précise.
- [ ] MédiAgenda tourne dans `mediagenda-recette` : API à au moins 2 réplicas prêts, derrière un Service qui a des points de terminaison, sondes `/sante` (vivacité) et `/pret` (disponibilité), ressources déclarées, compte `mediagenda-api`, sans `nodeName`, `hostPort` ni NodePort.
- [ ] Aucun Secret n'est versionné dans `k8s/recette/` ; le PDB laisse le drain possible.

**Vérification** : `lab/bin/check 14 21`

<details><summary>Indice 1</summary>

Pour chaque sélecteur (Service, PDB, Deployment), vérifie qu'il désigne bien les pods voulus, et seulement eux. Pour chaque sonde, demande-toi ce qui se passe quand la **base** est lente ou absente.
</details>

<details><summary>Indice 2</summary>

Une ConfigMap n'est pas un Secret : qui a le droit de lire les ConfigMaps de la recette ? Un `stringData` dans un fichier versionné, c'est un mot de passe dans Git, même dans un objet Secret.
</details>

<details><summary>Indice 3</summary>

`sh -c "a; b"` : qui est le PID 1, et que devient SIGTERM ? Et si `a` échoue ? Un champ `selector` de Deployment est immuable : qu'implique une étiquette de version dedans ?
</details>

---

### M14-E22 — Runbook : un nœud est NotReady  `RED` `★★`

> **Ticket PLAT-1522** — *De : Nadia Roussel*
> Premier runbook Kubernetes de l'astreinte : « un nœud est `NotReady` ». Je veux pouvoir le suivre à 3 h du matin sans connaître Kubernetes par cœur : quoi regarder d'abord, quoi ne pas faire, quand réveiller quelqu'un, et comment savoir que c'est fini. Format de nos autres runbooks.

**Objectifs pédagogiques**
- Transformer les gestes d'E17 et d'E20 en procédure d'astreinte.
- Ordonner un diagnostic du plus probable au moins probable, du moins risqué au plus risqué.
- Prévoir les impacts (évictions automatiques, PDB, bases jetables) et les critères d'escalade.

**Prérequis** : M14-E17, M14-E20.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Format : celui des runbooks du socle (objet, déclencheur, impact, prérequis, diagnostic, actions, retour à la normale, escalade, historique). Fichier `docs/kubernetes/runbooks/RB-140-noeud-notready.md` dans `plateforme/medisphere`.
- Accès de l'astreinte : kubeconfig personnel (groupe `medisphere:plateforme-admins`), SSH `admin` vers les nœuds, console Proxmox de `pve01` ; pas de `admin.conf` (bris de glace, Vault `critique`).
- Comportement par défaut à connaître : taints `node.kubernetes.io/not-ready` et `unreachable` posées par le contrôleur de nœuds, tolérance par défaut de 300 s des pods avant éviction, pods de DaemonSet jamais évincés, pods sur `emptyDir` perdus.

**Travail demandé**
1. Rédige RB-140 : déclencheur (comment on le constate), impact attendu minute par minute (0, 40 s, 5 min…), vérifications préalables (un seul nœud ? un nœud de contrôle ? la VIP ?), arbre de diagnostic (VM allumée ? réseau ? kubelet ? containerd ? disque ? mémoire ? certificats ? horloge ?) avec, pour chaque branche, la commande et le résultat attendu.
2. Actions : redémarrer le kubelet, redémarrer containerd, drainer et isoler, redémarrer la VM, et en dernier recours retirer le nœud et le reconstruire (lien vers la procédure d'E17 et d'E23). Pour chacune : risque, prérequis, retour arrière.
3. Cas particuliers : nœud de contrôle (quorum etcd, VIP), `k8s-w03` (PostgreSQL jetable : la base repart vide ailleurs ? peut-elle seulement aller ailleurs ?), plusieurs nœuds à la fois (escalade immédiate).
4. Retour à la normale : critères observables (nœud `Ready`, plus de taint, pods replacés, PDB satisfaits, `task etiquettes` rejouée si le nœud a été reconstruit).
5. Fais relire le runbook par un collègue imaginaire : liste trois questions qu'il poserait et réponds-y dans le document.

**Critères de réussite** (auto-évaluation avec le corrigé)
- [ ] Le runbook suit le format, couvre au moins six causes avec commande et résultat attendu, et distingue nœud de travail et nœud de contrôle.
- [ ] Chaque action risquée a un avertissement et un retour arrière ; les critères d'escalade sont explicites.
- [ ] RB-140 est publié dans `plateforme/medisphere`.

<details><summary>Indice 1</summary>

Un nœud `NotReady` est un nœud dont le kubelet ne renouvelle plus son bail (`kube-node-lease`) ou déclare une condition mauvaise. Lis les conditions (`kubectl describe node`) : `Ready=Unknown` et `Ready=False` ne racontent pas la même histoire.
</details>

<details><summary>Indice 2</summary>

Les délais par défaut (40 s avant `Unknown`, 300 s avant éviction) se lisent dans la documentation du contrôleur de nœuds et dans les tolérances ajoutées automatiquement aux pods (`kubectl get pod -o yaml`, section `tolerations`).
</details>

---

### M14-E23 — Le cluster décrit par le code  `LIBRE` `★★★`

> **Ticket PLAT-1523** — *De : Claire Morel*
> Si `k8s-par1` disparaissait demain, combien de temps pour le refaire à l'identique, et avec quoi ? Je veux la réponse « avec `plateforme/infra`, `plateforme/ansible` et `plateforme/k8s`, et cette procédure », et je veux la preuve : reconstruis un travailleur de zéro, VM comprise, sans geste à la main, et montre-moi que le cluster est revenu exactement comme avant.

**Objectifs pédagogiques**
- Faire l'inventaire de tout ce qui constitue le cluster et le ramener dans le code.
- Détecter la dérive entre le dépôt et le cluster.
- Prouver la reconstructibilité par une reconstruction réelle.

**Prérequis** : tout le palier 2.
**Durée indicative** : 4 h.

**Contraintes**
- Trois dépôts seulement font foi : `plateforme/infra` (VMs, état `k8s`), `plateforme/ansible` (nœuds et cluster), `plateforme/k8s` (configuration kubeadm, composants, espaces, budgets, RBAC, admission, priorités, étiquettes et taints des nœuds, outils). Les manifestes des applications restent chez les équipes. Aucun secret dans ces dépôts.
- Le `README.md` de `plateforme/k8s` décrit l'arborescence et l'ordre de reconstruction complet (VMs → nœuds → amorçage → composants → objets → étiquettes → vérification), avec les commandes.
- Le `Taskfile.yml` offre au moins : valider (hors ligne et contre le serveur), montrer la dérive, appliquer, poser les étiquettes et taints, installer ou mettre à jour chaque composant (Cilium, metrics-server), et une tâche de vérification qui dit si le cluster est conforme.
- La CI de `plateforme/k8s` valide chaque MR sans accès au cluster (syntaxe YAML, schémas des objets pour la version de Kubernetes du cluster, scripts).
- La dérive se constate en une commande ; un objet modifié à la main dans le cluster est détecté.
- Reconstruction d'un travailleur : `k8s-w02`, détruit et recréé (VM comprise), revenu `Ready` avec ses étiquettes, sans commande tapée à la main en dehors des tâches et playbooks documentés ; la sonde de disponibilité d'E16 ne doit pas voir de coupure de l'API MédiAgenda.
- La procédure et le compte rendu de la reconstruction (durée, écarts, corrections apportées au code) sont publiés dans `docs/kubernetes/reconstruction.md` de `plateforme/medisphere`.

**Critères de réussite**
- [ ] `plateforme/k8s` contient `README.md`, `Taskfile.yml`, `.gitlab-ci.yml`, `cluster/kubeadm-config.yaml`, `cluster/noeuds.yaml`, les dossiers `composants/`, `espaces/`, `rbac/`, `admission/`, `ordonnancement/`, `outils/` ; le dernier pipeline de `main` a réussi.
- [ ] Les étiquettes et taints des six nœuds sont conformes à `cluster/noeuds.yaml` ; les paramètres principaux de la configuration kubeadm du cluster (version, point d'accès, sous-réseaux) sont ceux du dépôt.
- [ ] `k8s-w02` a été recréé pendant l'exercice (nœud plus récent que le cluster) et il est `Ready` ; aucun nœud n'est `SchedulingDisabled`.
- [ ] `docs/kubernetes/reconstruction.md` est publié avec la procédure et le compte rendu.

**Vérification** : `lab/bin/check 14 23`

<details><summary>Indice 1</summary>

Pour l'inventaire, pars du cluster et non du dépôt : liste tous les objets qui ne viennent ni de kubeadm, ni de Cilium, ni d'une application, et demande-toi d'où vient chacun. `kubectl get … --show-managed-fields` dit qui a posé quel champ.
</details>

<details><summary>Indice 2</summary>

La dérive « dans le sens dépôt → cluster » se voit avec `kubectl diff --server-side`. L'autre sens (un objet créé à la main, absent du dépôt) demande une liste : les objets portant l'étiquette de ton dépôt, ou ceux dont le gestionnaire de champs est le tien, comparés aux fichiers.
</details>
