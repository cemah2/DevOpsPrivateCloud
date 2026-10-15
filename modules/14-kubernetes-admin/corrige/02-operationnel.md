# Module 14 — Palier 2 : Opérationnel — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Les fichiers.** Les solutions complètes sont dans [`fichiers/`](fichiers/), un dossier par exercice, sous la forme d'un **extrait des projets** : `fichiers/M14-EXX/k8s/…` = chemins de `plateforme/k8s`, `…/mediagenda-api/…` = `mediagenda/api`, `…/ansible/…` = `plateforme/ansible`, `…/infra/…` = `plateforme/infra`, `…/medisphere/…` = la documentation ; `…/essais/` et `…/julien/` se posent dans `~/m14/eXX/`. On **superpose** les dossiers dans l'ordre des exercices réalisés (E10, E11, E12, E13, E19, E14, E15, E16, E17, E18, E20) ; un fichier d'un exercice plus récent remplace le précédent. [`M14-E23/k8s/`](fichiers/M14-E23/k8s/) donne les fichiers de fin de palier qui ne sont pas déjà ailleurs (Taskfile, CI, README, outils de vérification). Les `*.extrait` sont des morceaux à intégrer dans un fichier existant (l'emplacement est dit en tête).

**Ce qui a été vérifié, ce qui ne l'a pas été.**
- *Admission, RBAC, quotas, ordonnancement* : tous les manifestes de `plateforme/k8s` et de `mediagenda/api` de ce palier ont été appliqués sur un **vrai** plan de contrôle Kubernetes **1.35.9** (kube-apiserver avec `NodeRestriction,LimitRanger,ResourceQuota,ServiceAccount,PodSecurity,Priority`, kube-controller-manager et kube-scheduler officiels, etcd 3.6.5), avec six objets Node factices aux noms, capacités et taints du lab (sans kubelet : les pods sont placés mais ne démarrent pas). Ont été constatés : agrégation des rôles (règles remplies par le contrôleur), matrice `matrice-droits.sh` sans écart, CSR signé et kubeconfig de Julien fonctionnel (`auth whoami`, `can-i`), refus du sujet piégé, quotas et LimitRanges (valeurs injectées, refus « maximum cpu », `exceeded quota` dans les événements), étiquettes et taints par `etiqueter-noeuds.sh`, placement de PostgreSQL sur `k8s-w03`, répartition 2+1 de l'API **et** le 3e réplica `Pending` sans `nodeTaintsPolicy: Honor`, DaemonSet sur six nœuds, Pod Security `restricted` (refus et avertissements), politique CEL `medisphere-images` (quatre refus, un accepté), et la revue de Lucas en `--dry-run=server` (refus et avertissements cités en E21).
- *Conteneurs* : Valkey 8.1 primaire + réplique avec la commande du StatefulSet, en utilisateur 999 et racine en lecture seule (réplication `master_link_status:up`) ; PostgreSQL 18 en utilisateur 999 sans capacité sur des volumes vides ; le pod `diag-memoire` tué à 64 Mio et non à 192 Mio (Docker 29, cgroup v2).
- *Validation statique* : `kubeconform` 0.8 (schémas 1.35.0, `-strict`) sur tous les manifestes, `yamllint --strict` avec la configuration de `plateforme/k8s` (E04), `helm template` du chart metrics-server 3.14.0 avec les valeurs fournies, `shellcheck -x` et `bash -n` sur les scripts.
- **Non rejoués sur un cluster réel** (signalés « ⚠️ À vérifier sur ton lab ») : tirage par les miroirs containerd et ce qu'en montre Harbor, renouvellement réel du jeton projeté par le kubelet, raison `OOMKilled` affichée pour `diag-memoire` (le processus tué n'est pas le PID 1), lecture de `/proc/1/environ` depuis un conteneur éphémère, `kubectl debug node/…` et ses profils, comportement fin de `drain` et de `kubeadm reset`, installation de metrics-server sur des kubelets kubeadm.

**Où lancer les commandes.** `admin@adm01:~$` avec ton kubeconfig personnel (contexte `k8s-par1`) ; `admin@adm01:~/src/k8s$` dans la copie de `plateforme/k8s` ; `admin@adm01:~/src/mediagenda-api$` dans celle de `mediagenda/api` ; `admin@k8s-w01:~$` en SSH sur un nœud (`sudo crictl …`). Rappel : `task appliquer` part de `main` à jour et sans modification locale.

---

### M14-E10 — Espaces de noms, quotas et LimitRanges

**Solution**

Fichiers : [`espaces/mediagenda-dev/`](fichiers/M14-E10/k8s/espaces/mediagenda-dev/) et [`espaces/mediagenda-recette/`](fichiers/M14-E10/k8s/espaces/mediagenda-recette/) (`00-namespace.yaml`, `10-quota.yaml`, `20-limites.yaml`), [`Taskfile.yml.extrait`](fichiers/M14-E10/k8s/Taskfile.yml.extrait), essais [`sans-ressources.yaml`](fichiers/M14-E10/essais/sans-ressources.yaml), [`trop-gros.yaml`](fichiers/M14-E10/essais/trop-gros.yaml), [`remplir-quota.yaml`](fichiers/M14-E10/essais/remplir-quota.yaml).

1. **Lecture.** Un ResourceQuota compte des **ressources de calcul** (`requests.cpu`, `requests.memory`, `limits.cpu`, `limits.memory`, `requests.ephemeral-storage`…), du **stockage** (`requests.storage`, par StorageClass) et des **nombres d'objets** (`pods`, `services`, `services.nodeports`, `count/<ressource>.<groupe>`). Dès qu'il suit une ressource de calcul, **tout** pod de l'espace doit la déclarer, sinon l'admission `ResourceQuota` le refuse (`must specify limits.cpu…`) ; c'est le LimitRange qui comble ce manque en injectant des valeurs par défaut, **à la création** du pod seulement : il ne modifie jamais un pod existant (les pods sont immuables sur ces champs), et un LimitRange ajouté après coup ne s'applique qu'aux pods créés ensuite.
2. **Capacité.** Allouable d'un travailleur ≈ 4 CPU et 7,3 à 7,6 Gio (8 Go moins les réservations du kubelet et du système : lis la tienne). Sans `k8s-w03` (bases), il reste deux travailleurs, soit ≈ 8 CPU et 15 Gio. Les deux budgets demandent au plus 2 + 3 = 5 CPU et 4 + 6 = 10 Gio de **requêtes** : ça tient, avec la marge pour Cilium, CoreDNS et metrics-server. Les **limites** (6 + 8 = 14 CPU, 20 Gio) dépassent la capacité : c'est normal et voulu, l'ordonnanceur ne place que sur les requêtes ; les limites autorisent des pointes, qui ne peuvent pas avoir lieu partout à la fois (surengagement assumé, à surveiller au M21).
3. **Fichiers et Taskfile.** `task valider` échoue au premier passage : `--dry-run=server` évalue chaque objet **sans rien écrire**, donc l'espace `mediagenda-dev` « créé » par le premier document n'existe pas pour les suivants (`namespaces "mediagenda-dev" not found`). Les fichiers sont justes ; c'est l'ordre des opérations qui ne l'est pas. Correction ([`Taskfile.yml.extrait`](fichiers/M14-E10/k8s/Taskfile.yml.extrait)) : une tâche `espaces` applique d'abord, pour de bon, les seuls objets `Namespace` (fichiers `espaces/*.yaml` et `espaces/*/00-namespace.yaml`), et `appliquer` l'appelle **avant** `valider`. Créer un espace vide avant d'avoir validé le reste est sans risque (il est dans la MR fusionnée de toute façon). Version complète du Taskfile en E23.
   ```
   admin@adm01:~/src/k8s$ task valider          # avant correction : NotFound sur 10-quota.yaml…
   admin@adm01:~/src/k8s$ git switch -c e10-espaces-mediagenda && git add espaces Taskfile.yml && git commit -m "feat(espaces): mediagenda-dev et mediagenda-recette (PLAT-1510)"
   admin@adm01:~/src/k8s$ git push -u origin e10-espaces-mediagenda      # MR, relecture, fusion
   admin@adm01:~/src/k8s$ git switch main && git pull && task appliquer && task diff
   ```
4. **Observation.**
   ```
   admin@adm01:~$ kubectl describe quota quota-equipe -n mediagenda-dev
   Resource                Used  Hard
   --------                ----  ----
   configmaps              1     30          # kube-root-ca.crt, publiée dans chaque espace
   count/cronjobs.batch    0     5
   limits.cpu              0     6
   pods                    0     20
   requests.cpu            0     2
   services.nodeports      0     0
   …
   ```
   La ConfigMap `kube-root-ca.crt` compte déjà : un quota d'objets à 0 sur les ConfigMaps rendrait l'espace inutilisable (piège classique).
5. **Essais.**
   - Pod sans `resources` : `kubectl get pod essai-sans-ressources -n mediagenda-dev -o jsonpath='{.spec.containers[0].resources}'` → `{"limits":{"cpu":"500m","memory":"512Mi"},"requests":{"cpu":"100m","memory":"128Mi"}}`, et l'annotation `kubernetes.io/limit-ranger: LimitRanger plugin set: cpu, memory request…` ; QoS `Burstable` (requêtes < limites).
   - Pod à 3 CPU : `Error from server (Forbidden): … pods "essai-trop-gros" is forbidden: maximum cpu usage per Container is 2, but limit is 3`. C'est l'admission **LimitRanger** (à la création), pas l'ordonnanceur.
   - Deployment de 10 × 300m : `kubectl get deploy essai-quota` affiche `6/10` (sur un espace vide ; moins s'il contient déjà des pods). Le Deployment ne dit rien d'utile ; le ReplicaSet porte la condition `ReplicaFailure` et des événements `FailedCreate` : `Error creating: pods "essai-quota-…" is forbidden: exceeded quota: quota-equipe, requested: requests.cpu=300m, used: requests.cpu=1800m, limited: requests.cpu=2`. Les 4 pods manquants ne sont **pas** `Pending` : ils n'existent pas.
     ```
     admin@adm01:~$ kubectl get events -n mediagenda-dev --field-selector reason=FailedCreate
     admin@adm01:~$ kubectl describe rs -n mediagenda-dev -l app.kubernetes.io/name=essai-quota | tail -5
     ```
6. `kubectl delete -f ~/m14/e10/` ; `describe quota` revient à `pods 0`, `requests.cpu 0` (le contrôleur de quotas recalcule en quelques secondes).

Les fichiers d'essai portent déjà un contexte de sécurité conforme au profil `restricted` : inutile ici, ils resteront valables quand E18 l'imposera.

**Explications**

Le quota est vérifié par l'**admission**, au moment de créer (ou de modifier) l'objet : il borne ce que l'espace *déclare*, pas ce qu'il *consomme*. La consommation réelle est l'affaire du kubelet (limites appliquées par les cgroups) et de l'ordonnanceur (requêtes réservées sur un nœud). Le contrôleur de quotas du kube-controller-manager tient l'état `used` à jour. Le LimitRange est un *mutateur* (valeurs par défaut) et un *validateur* (min, max, rapport limite/requête) appliqué par conteneur, par pod ou par PVC.

**Alternatives**
- *Quotas par portée* (`scopeSelector` : `PriorityClass`, `BestEffort`, `Terminating`) : utiles en E14 pour limiter les pods « critiques » d'une équipe.
- *Un quota par type de ressource* (calcul, objets) : plus lisible quand il y en a beaucoup ; ici, un seul suffit.
- *Pas de limite de CPU* (le choix d'E08 pour l'API) : on pourrait ne suivre que `requests.cpu` et `limits.memory` dans le quota. Alors un pod sans limite de CPU est accepté ; le LimitRange en donnerait quand même une par défaut (`default.cpu`), ce qu'il faudrait retirer. Choix MédiSphère : on garde des limites de CPU par défaut dans les espaces d'équipes (budget lisible), l'équipe peut en écrire de plus larges dans les bornes.

**Pièges classiques**
- Croire qu'un quota dépassé met les pods en `Pending` : ils ne sont jamais créés.
- `configmaps: "0"` ou `secrets: "0"` : `kube-root-ca.crt` et les Secrets de tirage ne passent plus.
- `services.nodeports: "0"` ne bloque pas un `LoadBalancer`… qui alloue aussi un NodePort par défaut : il est refusé lui aussi (et `services.loadbalancers: "0"` le dit explicitement).
- Oublier le LimitRange avec un quota sur `limits.*` : tous les pods sans ressources sont refusés, y compris ceux des Jobs et des outils (`kubectl run`, `kubectl debug` copie).

**En production chez MédiSphère**
Un budget par espace revu chaque trimestre avec l'équipe ; alertes sur `kube_resourcequota` (M21) à 80 % ; quota de stockage par StorageClass (M16) ; un gabarit d'espace (`outils/nouvelle-equipe.sh`, E33) plutôt que des copies à la main.

---

### M14-E11 — RBAC : des rôles pour les équipes

**Solution**

Fichiers : [`rbac/10-roles-medisphere.yaml`](fichiers/M14-E11/k8s/rbac/10-roles-medisphere.yaml), [`rbac/20-liaisons-cluster.yaml`](fichiers/M14-E11/k8s/rbac/20-liaisons-cluster.yaml), [`rbac/30-mediagenda.yaml`](fichiers/M14-E11/k8s/rbac/30-mediagenda.yaml), [`matrice-droits.sh`](fichiers/M14-E11/essais/matrice-droits.sh).

1. **Lecture.**
   - Un ClusterRole n'est qu'une **liste de règles** sans espace ; c'est la liaison qui donne la portée. Un RoleBinding vers un ClusterRole applique ces règles **dans l'espace du RoleBinding seulement** : on écrit le rôle une fois, on le lie dans chaque espace d'équipe.
   - L'agrégation sépare *ce qu'on donne* (de petits rôles thématiques) de *à qui* (les liaisons, qui visent un rôle public stable). Ajouter un droit à toutes les équipes, c'est ajouter un petit rôle étiqueté, sans toucher à aucune liaison ; c'est ainsi que les CRD des modules suivants donneront leurs droits de lecture (étiquettes `aggregate-to-view`…).
   - Droits qui en donnent d'autres : lire les **Secrets** (jetons, mots de passe) ; `pods/exec` et `pods/attach` (entrer dans un pod, lire ses variables et ses volumes, y compris des Secrets) ; **créer des pods** dans un espace (monter n'importe quel Secret de l'espace, utiliser n'importe quel compte de service de l'espace) ; `serviceaccounts/token` (fabriquer un jeton) ; les verbes `escalate` et `bind` sur les rôles (contourner la protection contre l'escalade) ; `impersonate` ; écrire des `rolebindings` ; `nodes/proxy` (API du kubelet, donc `exec` partout) ; écrire des webhooks ou des politiques d'admission ; `certificatesigningrequests/approval` avec un signataire client.
2. **Inventaire de départ.**
   ```
   admin@adm01:~$ kubectl get clusterrolebindings -o json | jq -r '.items[] | select(.roleRef.name=="cluster-admin")
       | "\(.metadata.name)\t\([.subjects[]? | .kind + ":" + .name] | join(","))"'
   cluster-admin                         Group:system:masters
   kubeadm:cluster-admins                Group:kubeadm:cluster-admins
   medisphere:plateforme-admins          Group:medisphere:plateforme-admins
   admin@adm01:~$ kubectl get clusterrolebindings -o json | jq -r '.items[] | select(any(.subjects[]?; .name=="system:authenticated" or .name=="system:unauthenticated"))
       | "\(.metadata.name) → \(.roleRef.name)"'
   system:basic-user → system:basic-user
   system:discovery → system:discovery
   system:public-info-viewer → system:public-info-viewer
   ```
   `system:masters` : groupe codé en dur, qui court-circuite l'autorisation (porté par `super-admin.conf`, au coffre) ; `kubeadm:cluster-admins` : groupe de `admin.conf` (depuis 1.29, pour pouvoir retirer ce droit) ; `medisphere:plateforme-admins` : E06. Les trois liaisons de `system:authenticated`/`unauthenticated` ne donnent que la découverte de l'API, `/version`, `/healthz` et `SelfSubjectAccessReview`/`SelfSubjectRulesReview` : c'est le minimum pour qu'un client fonctionne. Si une autre liaison vise ces groupes, c'est une faille.
3. **Le rôle `view`.** `kubectl get clusterrole view -o yaml` montre `aggregationRule` avec `rbac.authorization.k8s.io/aggregate-to-view: "true"` : il est lui-même agrégé (de `system:aggregate-to-view` et des rôles des CRD). Il ne contient ni les **Secrets** (lire un Secret, c'est souvent obtenir des droits), ni les objets RBAC, ni `pods/exec` ; `edit` ajoute l'écriture et les Secrets, `admin` ajoute les Roles et RoleBindings de l'espace.
4. **Rôles et liaisons.** `task appliquer` (dossier `rbac/`). Contrôle de l'agrégation :
   ```
   admin@adm01:~$ kubectl get clusterrole medisphere-developpeur -o json | jq '[.rules[] | .resources[]] | length'
   35
   admin@adm01:~$ kubectl get clusterrole medisphere-developpeur -o json | jq '[.rules[] | select(.resources | index("secrets"))] | length'
   0
   ```
   La liaison de `medisphere:plateforme-admins` reste dans `rbac/plateforme-admins.yaml` (E06) : ne la recrée pas sous un autre nom (deux liaisons identiques ne se voient pas, et on n'en retire qu'une).
5. **Matrice.** [`matrice-droits.sh`](fichiers/M14-E11/essais/matrice-droits.sh) : 19 cas, sortie `OK`/`ÉCART`, code 1 au moindre écart. Extrait de la sortie :
   ```
   OK     julien.petit   medisphere:mediagenda-devs   mediagenda-dev       create   deployments.apps       yes
   OK     julien.petit   medisphere:mediagenda-devs   mediagenda-recette   get      secrets                no
   OK     nadia.roussel  medisphere:lecture           mediagenda-dev       get      secrets                no
   OK     inconnu        system:authenticated         mediagenda-dev       list     pods                   no
   Matrice conforme.
   ```
   `--as` demande le droit `impersonate` sur les utilisateurs **et** sur les groupes (pour `--as-group`) : `cluster-admin` l'a. L'API ajoute `system:authenticated` à l'identité usurpée.
6. **Le piège de `exec`.** Après E19 :
   ```
   admin@adm01:~$ kubectl auth can-i get secrets -n mediagenda-recette --as=julien.petit --as-group=medisphere:mediagenda-devs
   no
   admin@adm01:~$ kubectl exec -n mediagenda-dev deploy/mediagenda-api --as=julien.petit --as-group=medisphere:mediagenda-devs \
       -- printenv MEDIAGENDA_DB_MDP
   9f3c…        # le mot de passe, lu sans aucun droit sur les Secrets
   ```
   En dev, l'équipe gère déjà ses Secrets (`medisphere-secrets-edition`) : `exec` ne lui donne rien de plus. En recette, `exec` contournerait le refus de lire les Secrets ; c'est pourquoi le rôle de recette n'a pas `pods/exec` (et, au-delà, une recette qui ressemble à la production ne s'administre pas « en entrant dans les pods »).
7. **Agrégation à l'usage.** On ajoute `storage.k8s.io/storageclasses` (get, list, watch) à `medisphere-lecture-cluster` ; quelques secondes après `task appliquer`, `kubectl get clusterrole medisphere-lecture -o yaml` contient la règle. On la garde : utile au support dès le M16, et sans secret.

**Explications**

L'API autorise une requête si **une** règle d'**un** rôle lié à l'identité (utilisateur, ou un de ses groupes) l'autorise : RBAC est purement additif, il n'existe pas de « refus ». D'où l'importance de petites briques et de liaisons par groupe. La protection contre l'escalade empêche de créer ou de lier un rôle qui donne plus que ce qu'on a soi-même (sauf verbes `escalate`/`bind`). Le contrôleur d'agrégation (kube-controller-manager) réécrit en permanence `rules` des rôles agrégés : une modification à la main y est écrasée.

**Alternatives**
- *Rôles intégrés* `view`/`edit` liés par espace : rapides, mais `edit` donne les Secrets et `view` ne donne pas les métriques ; on ne maîtrise pas leur évolution d'une version à l'autre.
- *Roles (namespacés) écrits par espace* : plus de fichiers, des dérives entre espaces.
- *Kyverno* (M26) pour générer les RoleBindings à la création d'un espace étiqueté.
- `kubectl auth reconcile` : applique des objets RBAC en ajoutant les règles manquantes sans retirer celles en trop (option `--remove-extra-permissions`) ; `apply` remplace. Pour un dépôt qui fait foi, `apply` est le bon outil.

**Pièges classiques**
- Oublier le groupe d'API (`deployments` est dans `apps`) ou la sous-ressource (`pods/log`, `deployments/scale`).
- Donner `pods/exec` en `create` seulement : avec le transport WebSocket de `kubectl exec` (par défaut dans les versions récentes), l'API vérifie aussi `get` sur `pods/exec`.
- Lier par `ClusterRoleBinding` un rôle d'équipe : il s'applique alors à **tous** les espaces.
- Croire que retirer quelqu'un d'un « groupe » se fait dans Kubernetes : le groupe vient du certificat (E12).
- `system:authenticated` dans une liaison « pour aller vite ».

**En production chez MédiSphère**
Matrice de droits exécutée en CI à chaque MR de `rbac/` (contre un cluster de test) et chaque nuit contre `k8s-par1` ; groupes venant de l'annuaire (OIDC, M24) ; revue trimestrielle des liaisons par Sophie (export `kubectl get rolebindings,clusterrolebindings -A`) ; audit des `exec` (E27).

---

### M14-E12 — Identités humaines : certificats clients et CSR

**Solution**

Fichiers : [`julien/generer-demande.sh`](fichiers/M14-E12/julien/generer-demande.sh) (côté Julien), [`outils/kubeconfig-csr.sh`](fichiers/M14-E12/k8s/outils/kubeconfig-csr.sh), [`docs/kubernetes/acces-humains.md`](fichiers/M14-E12/medisphere/docs/kubernetes/acces-humains.md).

1. **Lecture.** Le signataire `kubernetes.io/kube-apiserver-client` est implémenté par le kube-controller-manager avec la **CA du cluster** : `--cluster-signing-cert-file=/etc/kubernetes/pki/ca.crt` et `--cluster-signing-key-file=/etc/kubernetes/pki/ca.key` dans `/etc/kubernetes/manifests/kube-controller-manager.yaml` (sur les trois nœuds de contrôle). La durée accordée est le minimum entre `spec.expirationSeconds` et `--cluster-signing-duration` (un an par défaut). Le kube-apiserver fait confiance à cette CA (`--client-ca-file`) : le `CN` devient le nom d'utilisateur, chaque `O` un groupe. Un CSR `O=system:masters` approuvé sans lecture produit un certificat **super-administrateur irrévocable**, qui court-circuite RBAC et l'audit des refus : c'est exactement ce que l'outil doit refuser, et c'est pourquoi le droit d'**approuver** (`certificatesigningrequests/approval` + `approve` sur le signataire) est un droit d'administrateur.
2. **Côté Julien.**
   ```
   admin@adm01:~$ install -d -m 700 ~/m14/e12/julien && cp generer-demande.sh ~/m14/e12/julien/ && ~/m14/e12/julien/generer-demande.sh
   subject=CN = julien.petit, O = medisphere:mediagenda-devs
   ```
3. **Outil.** [`kubeconfig-csr.sh`](fichiers/M14-E12/k8s/outils/kubeconfig-csr.sh) : sujet comparé champ par champ (`-nameopt multiline` : un `O` en trop est vu), signature du CSR vérifiée, clé RSA de moins de 3072 bits refusée, objet `CertificateSigningRequest` à nom unique (`julien.petit-<date>`), `kubectl certificate approve`, attente du certificat, kubeconfig construit avec la CA de **ton** kubeconfig et un `client-key` **relatif** (écrit avec `yq` : `kubectl config set users.julien.petit…` ne sait pas traiter un nom qui contient un point).
   ```
   admin@adm01:~/src/k8s$ outils/kubeconfig-csr.sh ~/m14/e12/julien/julien.petit.csr julien.petit medisphere:mediagenda-devs
   certificatesigningrequest.certificates.k8s.io/julien.petit-20261012-091512 created
   certificatesigningrequest.certificates.k8s.io/julien.petit-20261012-091512 approved
   Kubeconfig écrit : /home/admin/m14/e12/julien/julien.petit.kubeconfig (certificat valable jusqu'au Oct 19 09:10:12 2026 GMT).
   ```
4. **L'objet CSR.**
   ```
   admin@adm01:~$ kubectl get csr julien.petit-20261012-091512 -o json | jq '{demandeur: .spec.username, duree: .spec.expirationSeconds, conditions: .status.conditions}'
   { "demandeur": "<MOI>", "duree": 604800,
     "conditions": [ { "type": "Approved", "reason": "KubectlApprove", "message": "This CSR was approved by kubectl certificate approve." } ] }
   admin@adm01:~$ kubectl get csr julien.petit-20261012-091512 -o jsonpath='{.status.certificate}' | base64 -d \
       | openssl x509 -noout -subject -issuer -dates
   subject=CN = julien.petit, O = medisphere:mediagenda-devs
   issuer=CN = kubernetes
   notBefore=Oct 12 09:10:12 2026 GMT
   notAfter=Oct 19 09:10:12 2026 GMT
   ```
   `spec.username` est le **demandeur** (toi), pas le sujet. Le certificat est antidaté de quelques minutes (tolérance d'horloge). Le nettoyeur de CSR du kube-controller-manager supprime un CSR approuvé et émis **une heure** après (un CSR en attente après 24 h) : l'objet n'est pas un registre des accès. La trace durable, c'est le ticket et, à partir d'E27, l'audit de l'API.
5. **Essais avec le kubeconfig de Julien.**
   ```
   admin@adm01:~$ export KUBECONFIG=~/m14/e12/julien/julien.petit.kubeconfig
   admin@adm01:~$ kubectl auth whoami
   Username   julien.petit
   Groups     [medisphere:mediagenda-devs system:authenticated]
   admin@adm01:~$ kubectl auth can-i create deployments -n mediagenda-dev        # yes
   admin@adm01:~$ kubectl create deployment essai --image=… -n mediagenda-recette # Forbidden
   admin@adm01:~$ kubectl get nodes                                               # Forbidden … cannot list resource "nodes"
   admin@adm01:~$ unset KUBECONFIG
   ```
6. **Révocation.** Il n'y en a pas : le kube-apiserver ne consulte ni CRL ni OCSP pour les certificats clients, et supprimer l'objet CSR ne change rien au certificat. Preuve : supprime le CSR, `kubectl auth whoami` avec le kubeconfig de Julien fonctionne toujours. Si Julien perd son portable : 1) supprimer le RoleBinding de **groupe** dans les espaces de l'équipe et redonner l'accès aux autres membres par des liaisons nominatives (`kind: User`) ; 2) attendre l'expiration (7 jours au plus) ; 3) émettre un nouveau certificat à Julien (nouvelle clé) ; 4) remettre la liaison de groupe. Pour un certificat d'administrateur compromis : rotation de la CA. Voir [`acces-humains.md`](fichiers/M14-E12/medisphere/docs/kubernetes/acces-humains.md).
7. **Demande piégée.**
   ```
   admin@adm01:~/src/k8s$ outils/kubeconfig-csr.sh /tmp/piege.csr julien.petit medisphere:mediagenda-devs
   sujet refusé :
     commonName=julien.petit
     organizationName=medisphere:mediagenda-devs
     organizationName=system:masters
   attendu : CN=julien.petit, O=medisphere:mediagenda-devs (et rien d'autre)
   ```

**Explications**

L'authentification X.509 de Kubernetes est volontairement simple : toute chaîne de certificats vers la CA de `--client-ca-file` est acceptée tant qu'elle n'est pas expirée. L'API `CertificateSigningRequest` ne fait qu'éviter de manipuler la clé de la CA à la main : elle trace la demande et l'approbation (dans l'objet, pendant une heure, et dans l'audit), et applique la durée demandée. C'est le même mécanisme que pour les kubelets (signataire `kubernetes.io/kube-apiserver-client-kubelet`, approuvé automatiquement), vu en E26.

**Alternatives**
- *OIDC* (Keycloak, M24) : jetons courts, groupes de l'annuaire, désactivation immédiate ; c'est la cible.
- *Signer avec la CA à la main* (`openssl x509 -req -CA /etc/kubernetes/pki/ca.crt`) : la clé de la CA sort de son répertoire, rien n'est tracé. À proscrire.
- *Jeton de compte de service pour un humain* : identité partagée, mauvaise traçabilité.
- *Une CA cliente séparée* (`--client-ca-file` avec un paquet de deux CA, la seconde dédiée aux humains) : permettrait de « révoquer » tous les humains d'un coup en la retirant ; possible, plus complexe à gérer avec kubeadm.
- *Une ValidatingAdmissionPolicy* qui refuse les requêtes d'un utilisateur précis (`request.userInfo.username`) : coupe ses **écritures** immédiatement, mais pas ses lectures (l'admission ne voit pas les `get`/`list`). Utile en urgence, pas suffisant.

**Pièges classiques**
- Envoyer la clé privée « pour gagner du temps ».
- Un `O` de trop, ou un `CN` avec une majuscule (`Julien.Petit` ≠ `julien.petit` pour RBAC).
- Oublier `expirationSeconds` : le certificat dure un an (`--cluster-signing-duration`).
- Construire le kubeconfig avec `admin.conf` comme modèle et y laisser la clé de l'administrateur.
- Croire que supprimer le CSR révoque le certificat.

**En production chez MédiSphère**
Délivrance déclenchée par le ticket validé, outil exécuté par la CI (job manuel protégé) plutôt que depuis un poste, rappel de renouvellement automatique, inventaire des certificats émis (numéros de série, dates) dans le registre des accès ; migration vers OIDC au M24, après quoi plus aucun certificat humain n'est émis (sauf bris de glace).

---

### M14-E13 — Comptes de service et jetons liés

**Solution**

Fichiers : [`espaces/mediagenda-dev/30-comptes-service.yaml`](fichiers/M14-E13/k8s/espaces/mediagenda-dev/30-comptes-service.yaml) (et recette), [`jeton-projete.yaml`](fichiers/M14-E13/essais/jeton-projete.yaml).

1. **Le pod par défaut.**
   ```
   admin@adm01:~$ kubectl run essai-sa -n wb-essais --image=registry.par1.medisphere.internal/dockerhub/library/busybox:1.37 -- sleep 3600
   admin@adm01:~$ kubectl get pod essai-sa -n wb-essais -o json | jq '.spec.serviceAccountName, (.spec.volumes[] | select(.name|startswith("kube-api-access")))'
   "default"
   { "name": "kube-api-access-7xq2m", "projected": { "defaultMode": 420, "sources": [
       { "serviceAccountToken": { "expirationSeconds": 3607, "path": "token" } },
       { "configMap": { "name": "kube-root-ca.crt", "items": [ { "key": "ca.crt", "path": "ca.crt" } ] } },
       { "downwardAPI": { "items": [ { "path": "namespace", "fieldRef": { "fieldPath": "metadata.namespace" } } ] } } ] } }
   admin@adm01:~$ kubectl exec -n wb-essais essai-sa -- cat /var/run/secrets/kubernetes.io/serviceaccount/token \
       | jq -R 'split(".") | .[1] | @base64d | fromjson'
   { "aud": ["https://kubernetes.default.svc.cluster.local"], "exp": 1791792000, "iat": 1760256000,
     "iss": "https://kubernetes.default.svc.cluster.local",
     "kubernetes.io": { "namespace": "wb-essais", "node": { "name": "k8s-w01", "uid": "…" },
       "pod": { "name": "essai-sa", "uid": "…" }, "serviceaccount": { "name": "default", "uid": "…" },
       "warnafter": 1760259607 },
     "nbf": 1760256000, "sub": "system:serviceaccount:wb-essais:default" }
   ```
   Le kubelet demande 3607 s, mais `exp` est à **un an** : avec `--service-account-extend-token-expiration=true` (défaut), l'API prolonge les jetons des volumes `kube-api-access` pour ne pas casser les clients qui lisent le fichier une fois pour toutes ; `warnafter` (iat + 3607 s) marque le moment à partir duquel l'usage du jeton est compté comme « jeton périmé utilisé » (métrique `serviceaccount_stale_tokens_total`). Le kubelet, lui, renouvelle le fichier vers 80 % de la durée demandée. Le jeton est **lié** au pod et au nœud : il devient invalide dès que le pod est supprimé, même avant `exp`. `jq` sait décoder le base64url avec `@base64d` (le remplissage manquant ne le gêne pas).
2. **Appel de l'API depuis le pod.**
   ```
   admin@adm01:~$ kubectl exec -n wb-essais essai-sa -- sh -c 'wget -qO- --header "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
       https://kubernetes.default.svc/api/v1/namespaces/wb-essais/pods 2>&1 | head -3'
   wget: server returned error: HTTP/1.1 403 Forbidden
   ```
   403 et non 401 : l'API a **authentifié** `system:serviceaccount:wb-essais:default`, puis refusé faute de droit. Le jeton est donc une identité valable, que n'importe quel processus du pod (une dépendance compromise…) peut présenter ; d'où l'intérêt de ne pas le monter. (busybox `wget` vérifie mal les certificats : avec `curl`, on passerait `--cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt`.)
3. **Comptes de service des équipes.** [`30-comptes-service.yaml`](fichiers/M14-E13/k8s/espaces/mediagenda-dev/30-comptes-service.yaml) ; `task appliquer`. Un `kubectl apply` du compte `default` n'en crée pas un second : il fusionne le champ (avertissement sur l'annotation `last-applied-configuration` absente : normal, le compte a été créé par le contrôleur ; la tâche du Taskfile fait du *server-side apply*, qui n'en a pas besoin). Un pod de test dans `mediagenda-dev` n'a plus de volume `kube-api-access-*` ni de fichier sous `/var/run/secrets/kubernetes.io/`. `mediagenda-api` n'apparaît dans aucune liaison :
   ```
   admin@adm01:~$ kubectl get rolebindings,clusterrolebindings -A -o json | jq '[.items[] | select(any(.subjects[]?; .kind=="ServiceAccount" and .name=="mediagenda-api"))] | length'
   0
   ```
4. **Jetons à la demande.**
   ```
   admin@adm01:~$ kubectl create token mediagenda-api -n mediagenda-dev --duration=10m | jq -R 'split(".")|.[1]|@base64d|fromjson|{aud,exp,iat,sub}'
   admin@adm01:~$ kubectl run porteur -n mediagenda-dev --image=…/busybox:1.37 --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":65534,"seccompProfile":{"type":"RuntimeDefault"}}}}' -- sleep 600
   admin@adm01:~$ J=$(kubectl create token mediagenda-api -n mediagenda-dev --duration=10m --bound-object-kind Pod --bound-object-name porteur)
   admin@adm01:~$ kubectl --token="$J" --kubeconfig=/dev/null --server=https://k8s-api.par1.medisphere.internal:8443 \
       --certificate-authority=<(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d) auth whoami
   Username  system:serviceaccount:mediagenda-dev:mediagenda-api
   admin@adm01:~$ kubectl delete pod porteur -n mediagenda-dev
   admin@adm01:~$ kubectl --token="$J" … auth whoami
   error: You must be logged in to the server (Unauthorized)
   admin@adm01:~$ unset J
   ```
   `--duration=1000h` : l'API plafonne à `--service-account-max-token-expiration` si l'option est fixée ; sans elle (cas kubeadm par défaut, à vérifier dans le manifeste), le jeton est émis pour la durée demandée — un jeton de 41 jours, ce qui montre pourquoi on fixe ce plafond (pour aller plus loin). ⚠️ À vérifier sur ton lab : la valeur effective dans `exp`.
5. **Jeton projeté.** `kubectl apply -f ~/m14/e13/jeton-projete.yaml` ; `kubectl exec -n wb-essais jeton-projete -- cat /var/run/secrets/medisphere/jeton | jq -R …` montre `"aud": ["medisphere-essai"]` et `exp - iat = 600` (pas de prolongation : ce n'est pas le volume `kube-api-access`). `kubectl logs -f jeton-projete -n wb-essais` : l'empreinte change au bout de 8 minutes environ (80 % de 600 s). L'audience dit **à qui** le jeton est destiné : un service qui vérifie l'audience (Vault au M25, par exemple, avec l'audience `vault`) refuse un jeton fait pour un autre, et inversement ce jeton est refusé par le kube-apiserver lui-même (audience différente de `--api-audiences`). Un jeton volé ne sert qu'à un seul destinataire. ⚠️ À vérifier sur ton lab : l'instant exact du renouvellement.
6. **Jetons hérités.**
   ```
   admin@adm01:~$ kubectl get secrets -A --field-selector type=kubernetes.io/service-account-token
   NAMESPACE   NAME             TYPE                                  DATA   AGE
   wb-system   wb-checks-jeton  kubernetes.io/service-account-token   3      9d
   ```
   Depuis 1.24, l'API ne crée plus ces Secrets automatiquement ; depuis 1.30, le nettoyeur des jetons hérités (`LegacyServiceAccountTokenCleanUp`) marque d'abord inutilisé (`kubernetes.io/legacy-token-invalid-since`) puis supprime les Secrets **créés automatiquement** et non utilisés depuis un an (`kubernetes.io/legacy-token-last-used` dit la dernière utilisation). Un Secret créé à la main, comme celui de `wb-checks`, n'est pas concerné : il reste valable tant qu'il existe, d'où l'exception documentée (droits limités, fichier 600, suppression = révocation).
7. **Règle d'équipe** (journal) : 1) aucun jeton monté par défaut (`automountServiceAccountToken: false` sur `default` et sur chaque compte) ; 2) un pod qui parle à l'API utilise un compte dédié, lié au rôle minimal, et monte le jeton explicitement ; 3) un jeton destiné à autre chose que l'API (Vault, un service interne) est projeté avec une **audience** dédiée et une durée courte ; 4) un jeton pour l'extérieur du cluster se demande par `kubectl create token --duration` court ; 5) un jeton permanent (Secret) n'est admis que par exception inscrite au registre des secrets, avec ses compensations.

**Explications**

Depuis 1.22, tous les jetons montés sont des jetons **liés** (TokenRequest) : audience, expiration, lien à un objet (pod, Secret, nœud) que l'API vérifie à chaque requête. L'admission `ServiceAccount` ajoute le compte `default` aux pods qui n'en nomment pas, le volume projeté `kube-api-access-*` (sauf `automountServiceAccountToken: false`), et recopie les `imagePullSecrets` du compte (E19). Le kubelet obtient le jeton par l'API TokenRequest au nom du pod, l'écrit et le renouvelle.

**Alternatives**
- *Désactiver le montage par pod seulement* : fragile (un nouveau manifeste l'oublie) ; on le fait sur le compte **et** dans les manifestes.
- *Une politique d'admission* (Kyverno, M26) qui refuse un pod montant un jeton sans annotation de justification.
- *Identités de charge de travail fédérées* (jetons projetés vérifiés par un tiers via la découverte OIDC de l'émetteur du cluster) : la voie du M25 avec Vault.

**Pièges classiques**
- Mettre `automountServiceAccountToken: false` sur le compte et l'écraser à `true` dans un gabarit copié d'Internet.
- Décoder la signature et la publier : seule la charge utile (2e partie) se lit ; on n'écrit jamais un jeton entier dans un journal.
- Créer un Secret `service-account-token` « parce que l'outil le demande » : la plupart des outils savent utiliser un jeton projeté ou `kubectl create token`.
- `expirationSeconds` < 600 : refusé par l'API.

**En production chez MédiSphère**
Plafond `--service-account-max-token-expiration` fixé dans la configuration kubeadm (E23/E25), audit des requêtes faites avec des jetons périmés (E27, métrique `serviceaccount_stale_tokens_total` au M21), inventaire des Secrets de jetons en CI, identités applicatives auprès de Vault par jetons projetés (M25).

---

### M14-E14 — Ordonnancement : affinités, taints et répartition

**Solution**

Fichiers : [`cluster/noeuds.yaml`](fichiers/M14-E14/k8s/cluster/noeuds.yaml), [`outils/etiqueter-noeuds.sh`](fichiers/M14-E14/k8s/outils/etiqueter-noeuds.sh), [`ordonnancement/priorites.yaml`](fichiers/M14-E14/k8s/ordonnancement/priorites.yaml), [`Taskfile.yml.extrait`](fichiers/M14-E14/k8s/Taskfile.yml.extrait) ; côté équipe [`20-postgresql.yaml`](fichiers/M14-E14/mediagenda-api/k8s/dev/20-postgresql.yaml), [`40-api.yaml`](fichiers/M14-E14/mediagenda-api/k8s/dev/40-api.yaml) ; essais [`taint-sans-tolerance.yaml`](fichiers/M14-E14/essais/taint-sans-tolerance.yaml), [`preemption.yaml`](fichiers/M14-E14/essais/preemption.yaml), [`preemption-critique.yaml`](fichiers/M14-E14/essais/preemption-critique.yaml).

1. **NodeRestriction.** Le kubelet peut poser à son enregistrement (`--node-labels`) les étiquettes hors des préfixes `kubernetes.io`/`k8s.io`, et, dans ces préfixes, seulement une liste autorisée : `kubernetes.io/hostname`, `kubernetes.io/arch`, `kubernetes.io/os`, `node.kubernetes.io/instance-type`, `topology.kubernetes.io/region`, **`topology.kubernetes.io/zone`**, et les préfixes `kubelet.kubernetes.io/` et `node.kubernetes.io/`. `medisphere.internal/dedie` est donc permise aussi. Mais `--node-labels` ne vaut **qu'à l'enregistrement** du nœud : pour des nœuds existants, et pour corriger une dérive, il faut l'API. Un nœud ne peut en revanche pas se donner `node-role.kubernetes.io/*` (c'est voulu : un nœud compromis ne doit pas pouvoir attirer des charges sensibles). D'où le choix : un fichier source de vérité, un script idempotent rejoué après chaque jonction.
2. **Étiquettes et taints.**
   ```
   admin@adm01:~/src/k8s$ outils/etiqueter-noeuds.sh --dry-run
   node/k8s-cp01 labeled (server dry run)
   …
   admin@adm01:~/src/k8s$ task etiquettes
   admin@adm01:~$ kubectl get nodes -L topology.kubernetes.io/zone,medisphere.internal/dedie
   NAME       STATUS   ROLES           AGE   VERSION   ZONE          DEDIE
   k8s-cp01   Ready    control-plane   12d   v1.35.9   par1-baie-a
   k8s-cp02   Ready    control-plane   12d   v1.35.9   par1-baie-b
   k8s-cp03   Ready    control-plane   12d   v1.35.9   par1-baie-c
   k8s-w01    Ready    <none>          12d   v1.35.9   par1-baie-a
   k8s-w02    Ready    <none>          12d   v1.35.9   par1-baie-b
   k8s-w03    Ready    <none>          12d   v1.35.9   par1-baie-c   bdd
   admin@adm01:~$ kubectl describe node k8s-w03 | grep -A1 Taints
   Taints:             dedie=bdd:NoSchedule
   ```
   Le script ne retire jamais rien (une étiquette retirée du fichier se retire à la main, dans la MR) : retirer automatiquement « tout ce qui n'est pas dans le fichier » effacerait les étiquettes de kubeadm, de Cilium et du kubelet. La tâche `etiquettes` (le nom `noeuds` est déjà pris par la convergence Ansible) et le dossier `ordonnancement` dans `DOSSIERS` sont dans [`Taskfile.yml.extrait`](fichiers/M14-E14/k8s/Taskfile.yml.extrait).
3. **Les pods déjà sur `k8s-w03`.** `NoSchedule` n'agit qu'à l'ordonnancement : les pods en place restent (`NoExecute` les évincerait, sauf tolérance). Pour libérer le nœud des charges d'équipe sans toucher aux DaemonSets : supprimer les pods concernés un par un (ils sont recréés ailleurs par leur contrôleur, la taint les empêchant de revenir), ou `kubectl drain k8s-w03 --ignore-daemonsets --delete-emptydir-data` suivi de `kubectl uncordon k8s-w03` (plus brutal : il évince aussi les bases jetables). On liste d'abord : `kubectl get pods -A -o wide --field-selector spec.nodeName=k8s-w03`.
4. **Essais.** Sans tolérance : `0/6 nodes are available: 1 node(s) had untolerated taint {dedie: bdd}, 3 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: }, 2 node(s) didn't match Pod's node affinity/selector` (texte exact selon la version). Avec la tolérance seule, le pod peut aller n'importe où, y compris sur `k8s-w01` : une tolérance **autorise**, elle n'**attire** pas.
5. **PostgreSQL.** Tolérance `dedie=bdd:NoSchedule` + `nodeAffinity` requise sur `medisphere.internal/dedie In [bdd]` + `priorityClassName: medisphere-critique` ([`20-postgresql.yaml`](fichiers/M14-E14/mediagenda-api/k8s/dev/20-postgresql.yaml)). Après `kubectl apply`, `kubectl get pod -n mediagenda-dev -l app.kubernetes.io/name=postgresql -o wide` → `k8s-w03`. La base repart vide : relance la migration (E19 : `kubectl rollout restart deploy/mediagenda-api`, son `initContainer` migre ; après E15, le Job).
6. **API et répartition.** Avec la contrainte « naïve » (`maxSkew: 1`, `topologyKey: topology.kubernetes.io/zone`, `whenUnsatisfiable: DoNotSchedule`), deux réplicas se placent (baies a et b) et le troisième reste `Pending` :
   ```
   0/6 nodes are available: 2 node(s) didn't match pod topology spread constraints,
   4 node(s) had untolerated taint(s). preemption: 0/6 nodes are available: …
   ```
   Explication : pour compter les zones, l'ordonnanceur prend par défaut tous les nœuds qui satisfont l'affinité du pod (`nodeAffinityPolicy: Honor`) **sans regarder les taints** (`nodeTaintsPolicy: Ignore`). La zone `par1-baie-c` (seulement `k8s-cp03` et `k8s-w03`, tous deux « taintés ») compte donc, avec 0 pod pour toujours ; un 3e pod en baie a ou b créerait un écart de 2 avec elle. Correction : `nodeTaintsPolicy: Honor` (seules les zones où le pod **peut** aller comptent). Résultat 2 + 1 sur deux zones. Ajouts : `matchLabelKeys: [pod-template-hash]` (la répartition se calcule par révision : pendant une mise à jour, les anciens pods ne faussent pas le calcul), et une anti-affinité **préférée** par nœud (`preferredDuringScheduling…`, poids 100) : avec deux travailleurs dans deux zones, une exigence stricte par nœud limiterait l'API à 2 réplicas.
   ```
   admin@adm01:~$ kubectl get pods -n mediagenda-dev -l app.kubernetes.io/name=mediagenda-api -o wide
   mediagenda-api-…-8v6ns   1/1   Running   k8s-w01
   mediagenda-api-…-d9rzc   1/1   Running   k8s-w01
   mediagenda-api-…-z67jb   1/1   Running   k8s-w02
   ```
7. **Préemption.** `kubectl apply -f preemption.yaml`, puis `kubectl scale deploy remplissage -n wb-essais --replicas=8` jusqu'à des `Pending` ; `kubectl apply -f preemption-critique.yaml` : l'ordonnanceur choisit un nœud où l'éviction de pods **moins prioritaires** suffit, pose `status.nominatedNodeName` sur le pod critique, évince (événements `Preempted` : `Preempted by pod … on node k8s-w0X`), puis place le pod critique. Les pods `remplissage` évincés sont recréés par leur ReplicaSet… et restent `Pending` : `preemptionPolicy: Never` les empêche de préempter à leur tour. Nettoyage : `kubectl delete -f preemption-critique.yaml -f preemption.yaml`.
8. **Perte de `k8s-w01`.** Après 5 minutes (tolérance `unreachable` par défaut), ses deux réplicas sont évincés ; les nouveaux ne peuvent aller que sur `k8s-w02` (baie b)… mais la contrainte stricte exige un écart ≤ 1 entre baies a et b, et la baie a n'a plus de nœud éligible : avec `nodeTaintsPolicy: Honor` et un nœud `unreachable` (taint `NoExecute` + `NoSchedule`), la baie a sort du calcul, il ne reste qu'une zone, les trois réplicas vont sur `k8s-w02`. Sans `Honor`, ils resteraient `Pending`. C'est le bon comportement : on veut l'API disponible, quitte à la regrouper, pendant la panne. ⚠️ À vérifier sur ton lab (E35 permet de le constater).

**Explications**

L'ordonnanceur procède en deux temps : **filtrage** (nœuds possibles : ressources, taints/tolérances, affinités requises, contraintes de répartition `DoNotSchedule`) puis **notation** (préférences, `ScheduleAnyway`, équilibre). La préemption n'intervient que si aucun nœud ne passe le filtre : elle cherche le nœud où évincer le moins de pods de priorité inférieure (en respectant les PDB « au mieux »). Les taints protègent un nœud ; les affinités choisissent un nœud ; la répartition topologique garantit un écart maximal entre domaines.

**Alternatives**
- `nodeSelector` au lieu de `nodeAffinity` pour la base : équivalent ici, moins expressif.
- Anti-affinité **requise** par zone pour l'API : interdit plus d'un pod par zone, donc au plus 2 réplicas aujourd'hui. Trop rigide.
- `whenUnsatisfiable: ScheduleAnyway` : jamais de `Pending`, mais la répartition n'est plus garantie.
- Réserver `k8s-w03` par `NoExecute` : chasserait aussi les pods non tolérants déjà présents, mais tout pod sans tolérance (y compris un DaemonSet d'un composant oublié) en serait évincé.

**Pièges classiques**
- Taint sans affinité (la base peut aller ailleurs) ou affinité sans tolérance (la base reste `Pending`).
- `nodeTaintsPolicy` par défaut à `Ignore` avec des nœuds de contrôle étiquetés dans les zones (voir étape 6).
- Croire que les PriorityClasses se limitent par espace : n'importe qui peut écrire `priorityClassName: medisphere-critique` (d'où le quota par portée, *pour aller plus loin*).
- Une PriorityClass `globalDefault: true` créée après coup : elle ne s'applique qu'aux nouveaux pods.

**En production chez MédiSphère**
Étiquettes posées à l'enregistrement (`kubeletExtraArgs` `node-labels` dans la configuration de jonction du rôle `k8s_travailleur`) **et** par le script (dérive), quota `scopeSelector` sur `medisphere-critique` dans chaque espace d'équipe, bases sur des nœuds dédiés avec stockage local rapide au M16-M27, alerte sur les pods `Pending` depuis plus de 5 minutes (M21).

---

### M14-E15 — StatefulSets, DaemonSets, Jobs et CronJobs

**Solution**

Fichiers : [`10-config.yaml`](fichiers/M14-E15/mediagenda-api/k8s/dev/10-config.yaml), [`30-valkey.yaml`](fichiers/M14-E15/mediagenda-api/k8s/dev/30-valkey.yaml), [`40-api.yaml`](fichiers/M14-E15/mediagenda-api/k8s/dev/40-api.yaml) (sans `initContainer`), [`50-migration.yaml`](fichiers/M14-E15/mediagenda-api/k8s/dev/50-migration.yaml), [`60-sauvegarde.yaml`](fichiers/M14-E15/mediagenda-api/k8s/dev/60-sauvegarde.yaml), [`sonde-noeud.yaml`](fichiers/M14-E15/essais/sonde-noeud.yaml).

1. **Tableau.**

   | Contrôleur | Garantit | Unité de mise à jour | Chez MédiSphère |
   |---|---|---|---|
   | Deployment | N pods interchangeables | ReplicaSet (révision), progressive | API MédiAgenda, MédiDoc |
   | StatefulSet | N pods à identité stable (nom, ordinal, DNS, volume), ordre | pod par pod, du plus grand ordinal au plus petit, `partition` | Valkey, bases, files (M27) |
   | DaemonSet | un pod par nœud (sélectionné) | nœud par nœud (`maxUnavailable`) | Cilium, sondes, collecteurs de journaux (M22) |
   | Job | une tâche menée à terme (N succès) | aucune (immuable) | migration de schéma |
   | CronJob | un Job selon un calendrier | le gabarit, pour les Jobs suivants | export, purge, rapports |
2. **Valkey.**
   ```
   admin@adm01:~$ kubectl delete svc,deploy valkey -n mediagenda-dev   # clusterIP: None est immuable ; l'ancien Deployment part aussi
   admin@adm01:~/src/mediagenda-api$ kubectl apply -f k8s/dev/30-valkey.yaml
   admin@adm01:~$ kubectl get pods -n mediagenda-dev -l app.kubernetes.io/name=valkey -w     # valkey-0, puis -1 quand -0 est prêt, puis -2
   admin@adm01:~$ kubectl exec -n mediagenda-dev valkey-1 -- valkey-cli info replication | grep -E 'role|master_host|master_link_status'
   role:slave
   master_host:valkey-0.valkey.mediagenda-dev.svc.cluster.local
   master_link_status:up
   admin@adm01:~$ kubectl exec -n mediagenda-dev valkey-0 -- valkey-cli info replication | grep connected_slaves
   connected_slaves:2
   admin@adm01:~$ kubectl run dns -n wb-essais --rm -it --restart=Never --image=…/busybox:1.37 -- nslookup valkey-1.valkey.mediagenda-dev.svc.cluster.local
   ```
   ⚠️ L'ancien Deployment `valkey` doit disparaître avec l'ancien Service : ses pods portent les mêmes étiquettes, le Service *headless* les inclurait. `kubectl delete pod valkey-1` : le pod recréé s'appelle **encore** `valkey-1`, a le même nom DNS et redevient réplique (son `emptyDir` est neuf : resynchronisation complète depuis le primaire). Le Service est *headless* (`clusterIP: None`) : son nom DNS rend les adresses des pods, et chaque pod a un nom `<pod>.<service>` ; `publishNotReadyAddresses: true` est nécessaire parce que `-1` doit résoudre `-0` avant d'être prêt… et que `-0` doit être résolu par l'API même pendant une resynchronisation.
3. **ConfigMap.** `MEDIAGENDA_VALKEY_URL` vise maintenant `valkey-0.valkey` (le primaire ; les répliques sont en lecture seule et l'API écrit dans le cache). Les variables d'environnement sont lues au démarrage : après `kubectl apply -f 10-config.yaml`, les pods de l'API gardent l'ancienne valeur (`kubectl exec … -- printenv MEDIAGENDA_VALKEY_URL`) ; `kubectl rollout restart deploy/mediagenda-api -n mediagenda-dev` les recrée. (Le M17 fera dépendre le gabarit d'une empreinte de la ConfigMap pour que le redémarrage soit automatique.)
4. **Migration.**
   ```
   admin@adm01:~/src/mediagenda-api$ kubectl apply -f k8s/dev/50-migration.yaml
   admin@adm01:~$ kubectl wait --for=condition=Complete job/mediagenda-migration-v1-0-0 -n mediagenda-dev --timeout=5m
   admin@adm01:~$ kubectl logs -n mediagenda-dev job/mediagenda-migration-v1-0-0
   {"niveau": "INFO", "message": "migration appliquée : V1 init", …}
   admin@adm01:~/src/mediagenda-api$ kubectl apply -f k8s/dev/40-api.yaml                    # sans initContainer
   ```
   Réappliquer après avoir modifié la commande : `The Job "mediagenda-migration-v1-0-0" is invalid: spec.template: … field is immutable`. Le gabarit d'un Job est immuable : une nouvelle version = un **nouveau** Job (`…-v1-1-0`), d'où la version dans le nom. Procédure de montée de version : 1) Job de migration de la nouvelle version, attendre `Complete` ; 2) mettre à jour l'API (E16) ; la migration doit être **compatible** avec l'ancienne version de l'API, qui tourne encore pendant la mise à jour progressive (migrations « expand/contract »). La migration n'a plus besoin de tourner à chaque démarrage, et le compte de l'application pourrait perdre les droits DDL (deux comptes PostgreSQL : M27).
5. **Échec.** Copie avec une URL fausse : `restartPolicy: Never` → un **nouveau pod** par essai (4 pods au total pour `backoffLimit: 3`), avec un délai croissant (10 s, 20 s, 40 s…, plafonné à 6 min) ; condition finale `Failed` raison `BackoffLimitExceeded` (ou `DeadlineExceeded` si `activeDeadlineSeconds` est atteint d'abord). Les pods en échec restent, avec leurs journaux, jusqu'au TTL ou à la suppression du Job. Avec `restartPolicy: OnFailure`, c'est le **même** pod qui redémarre son conteneur (journaux précédents écrasés au-delà d'un).
6. **CronJob.**
   ```
   admin@adm01:~/src/mediagenda-api$ kubectl apply -f k8s/dev/60-sauvegarde.yaml
   admin@adm01:~$ kubectl create job --from=cronjob/mediagenda-sauvegarde sauvegarde-manuelle-1 -n mediagenda-dev
   admin@adm01:~$ kubectl logs -n mediagenda-dev job/sauvegarde-manuelle-1
   export terminé : 5821 octets, sha256 3b0c…
   ```
   Le Job manuel porte une référence de propriétaire vers le CronJob (il apparaît dans son historique) et l'annotation `cronjob.kubernetes.io/instantiate: manual`. Sans `timeZone`, le calendrier est interprété dans le fuseau du **kube-controller-manager** : celui du conteneur, UTC en pratique sur kubeadm — 2 h 15 UTC = 3 h 15 ou 4 h 15 à Paris selon la saison. Les fuseaux viennent de la base tz embarquée dans le binaire. `concurrencyPolicy: Forbid` : si l'export précédent tourne encore, l'exécution suivante est **sautée** (pas mise en file) ; avec `Replace`, l'ancienne serait tuée. `startingDeadlineSeconds: 900` : si le contrôleur était arrêté à 2 h 15 et revient à 2 h 40, l'exécution est abandonnée (et, sans ce champ, un contrôleur qui a raté plus de 100 exécutions refuse de démarrer le CronJob).
7. **DaemonSet.** Sans tolérance : 2 pods (`k8s-w01`, `k8s-w02`) : la taint `dedie=bdd` exclut `k8s-w03`, celle de `control-plane` les trois nœuds de contrôle. Avec `tolerations: [{operator: Exists}]` : 6 pods. Le contrôleur DaemonSet ajoute de lui-même les tolérances `not-ready`, `unreachable`, `disk-pressure`, `memory-pressure`, `pid-pressure`, `unschedulable` (un DaemonSet reste sur un nœud malade ou en maintenance), pas celles des taints posées par les humains.
   ```
   admin@adm01:~$ kubectl get pods -n wb-essais -l app.kubernetes.io/name=sonde-noeud -o wide
   admin@adm01:~$ kubectl run c -n wb-essais --rm -it --restart=Never --image=…/busybox:1.37 -- wget -qO- http://<IP-DU-POD>:8080/
   noeud=k8s-cp02
   ip=10.10.40.52
   ```

**Explications**

Le StatefulSet attribue à chaque pod une identité qui survit à sa recréation (nom, ordinal, nom DNS stable via le Service *headless*, et, au M16, son propre volume par `volumeClaimTemplates`). L'ordre (`OrderedReady`) garantit que `-0` est prêt avant `-1` : c'est ce qui permet un primaire désigné par son ordinal. Le Job suit des **complétions** ; le CronJob crée des Jobs. Le DaemonSet suit les nœuds, pas un nombre de réplicas.

**Alternatives**
- Valkey en Deployment + Service unique (E07) : suffisant pour un cache jetable ; la réplication n'a d'intérêt que pour l'apprentissage ou la lecture répartie.
- Un opérateur ou Sentinel pour la bascule automatique (M27).
- Migration en `initContainer` avec verrou consultatif (E07) : simple, mais à chaque démarrage, avec les droits DDL ; ou en *hook* de déploiement (Helm `pre-upgrade`, M17 ; Argo CD `PreSync`, M20) : la forme industrielle du Job versionné.
- `podManagementPolicy: Parallel` : démarrage plus rapide, mais `-1` démarrerait avant que `-0` existe (il réessaierait la réplication).

**Pièges classiques**
- Changer un Service ClusterIP en *headless* par `apply` : refusé (champ immuable).
- Oublier de supprimer l'ancien Deployment : ses pods se mélangent au StatefulSet derrière le Service.
- `command` au lieu de `args` : on perd `tini` et le script d'entrée de l'image.
- CronJob sans `timeZone` à une heure « locale ».
- `ttlSecondsAfterFinished` court sur un Job de migration : la trace disparaît avant qu'on la lise.
- Un DaemonSet de diagnostic qui tolère tout **et** demande beaucoup de ressources : il passe avant les applications sur chaque nœud.

**En production chez MédiSphère**
Valkey par un opérateur ou en Sentinel (M27), migrations par *hook* de déploiement (M17-M20) avec retour arrière documenté, CronJobs surveillés (dernière réussite, M21 : `kube_cronjob_status_last_successful_time`), sauvegardes réelles par CloudNativePG et Velero (M16).

---

### M14-E16 — Mises à jour progressives, retour arrière et PDB

**Solution**

Fichiers : [`40-api.yaml`](fichiers/M14-E16/mediagenda-api/k8s/dev/40-api.yaml), [`45-pdb.yaml`](fichiers/M14-E16/mediagenda-api/k8s/dev/45-pdb.yaml), [`sonde-disponibilite.yaml`](fichiers/M14-E16/essais/sonde-disponibilite.yaml), [`eviction.json`](fichiers/M14-E16/essais/eviction.json).

1. **Calcul.** 3 réplicas, `maxSurge: 25 %` arrondi **au-dessus** (1), `maxUnavailable: 25 %` arrondi **au-dessous** (0) : au plus 4 pods, au moins 3 disponibles. Les valeurs par défaut ne coupent donc pas le service *si* les sondes disent vrai. La coupure d'hier vient d'ailleurs : le plus probablement une sonde de disponibilité absente ou trop optimiste (le Deployment de dev d'avant E08, par exemple) : le nouveau pod est déclaré prêt avant de l'être, l'ancien est arrêté, les requêtes partent vers un processus qui démarre. Second suspect : l'arrêt des anciens pods (requêtes en cours coupées si `terminationGracePeriodSeconds` < délai d'arrêt de l'application, ou si le pod est retiré des points de terminaison **après** avoir cessé de répondre).
2. **Mise à jour avec les valeurs par défaut.**
   ```
   admin@adm01:~$ kubectl apply -f ~/m14/e16/sonde-disponibilite.yaml
   admin@adm01:~$ kubectl set env deploy/mediagenda-api -n mediagenda-dev -c api MEDIAGENDA_LOG_LEVEL=DEBUG
   admin@adm01:~$ kubectl annotate deploy/mediagenda-api -n mediagenda-dev kubernetes.io/change-cause="E16 : journal DEBUG (valeurs par défaut)"
   admin@adm01:~$ kubectl rollout status deploy/mediagenda-api -n mediagenda-dev
   admin@adm01:~$ kubectl logs sonde-disponibilite -n wb-essais --since=5m | grep -c ECHEC
   ```
   Avec les sondes d'E08, 0 à quelques `ECHEC` selon le moment où un ancien pod reçoit SIGTERM alors que des connexions lui arrivent encore (le retrait des points de terminaison n'est pas instantané). Note la valeur.
3. **Stratégie réglée** ([`40-api.yaml`](fichiers/M14-E16/mediagenda-api/k8s/dev/40-api.yaml) : `maxSurge: 1`, `maxUnavailable: 0`, `minReadySeconds: 10`, `progressDeadlineSeconds: 120`, `revisionHistoryLimit: 5`), puis retour à `INFO` (en retirant la variable de l'`env` dans le fichier, MR, `kubectl apply`). `minReadySeconds` impose 10 s de disponibilité continue avant de compter un pod : un pod qui tombe juste après sa première sonde réussie ne fait pas avancer la mise à jour. Résultat attendu : 0 `ECHEC`. S'il en reste, c'est l'arrêt : MédiAgenda finit ses requêtes sur SIGTERM, mais il peut en recevoir de nouvelles pendant la propagation du retrait des points de terminaison ; un `preStop` (`sleep 5` dans le conteneur, ou `lifecycle.preStop.sleep`, GA en 1.34 à vérifier) couvre ce délai.
4. **Image inexistante.**
   ```
   admin@adm01:~$ kubectl set image deploy/mediagenda-api -n mediagenda-dev api=registry.par1.medisphere.internal/medisphere/mediagenda-api:v9.9.9
   admin@adm01:~$ kubectl rollout status deploy/mediagenda-api -n mediagenda-dev
   Waiting for deployment "mediagenda-api" rollout to finish: 1 out of 3 new replicas have been updated...
   error: deployment "mediagenda-api" exceeded its progress deadline
   admin@adm01:~$ kubectl get deploy mediagenda-api -n mediagenda-dev -o jsonpath='{.status.conditions[?(@.type=="Progressing")]}'
   {"reason":"ProgressDeadlineExceeded","status":"False", …}
   admin@adm01:~$ kubectl rollout undo deploy/mediagenda-api -n mediagenda-dev
   ```
   Un seul nouveau pod (`maxSurge: 1`) en `ImagePullBackOff`, les trois anciens intacts : aucun `ECHEC`. Le Deployment **ne revient pas** en arrière seul : il signale. `rollout undo` remet le gabarit de la révision précédente (nouvelle révision, numéro suivant) ; ensuite, le fichier versionné doit dire la même chose (sinon le prochain `apply` remet `v9.9.9`).
5. **Mauvaise configuration.** `kubectl set env … MEDIAGENDA_VALKEY_URL=redis://valkey-absent:6379/0` : le nouveau pod démarre (`/sante` répond, il n'est pas redémarré), mais `/pret` renvoie 503 (Valkey injoignable) : `Running` et **non prêt**, il ne reçoit pas de trafic ; les anciens restent ; `ProgressDeadlineExceeded` au bout de 2 minutes ; aucun `ECHEC`.
   ```
   admin@adm01:~$ kubectl rollout history deploy/mediagenda-api -n mediagenda-dev
   REVISION  CHANGE-CAUSE
   2         E16 : journal DEBUG (valeurs par défaut)
   4         E16 : retour à INFO, stratégie réglée
   5         E16 : image v9.9.9 (essai)
   6         E16 : Valkey inexistant (essai)
   admin@adm01:~$ kubectl rollout undo deploy/mediagenda-api -n mediagenda-dev --to-revision=4
   ```
   (Numéros indicatifs : une révision reprise par `undo` change de numéro.)
6. **PDB** ([`45-pdb.yaml`](fichiers/M14-E16/mediagenda-api/k8s/dev/45-pdb.yaml)) : `kubectl get pdb -n mediagenda-dev` → `MAX UNAVAILABLE 1`, `ALLOWED DISRUPTIONS 1`. Éviction par l'API ([`eviction.json`](fichiers/M14-E16/essais/eviction.json), à adapter au nom du pod) :
   ```
   admin@adm01:~$ kubectl create --raw /api/v1/namespaces/mediagenda-dev/pods/<POD-1>/eviction -f eviction.json   # acceptée
   admin@adm01:~$ kubectl create --raw /api/v1/namespaces/mediagenda-dev/pods/<POD-2>/eviction -f eviction.json   # tout de suite après
   Error from server (TooManyRequests): Cannot evict pod as it would violate the pod's disruption budget.
   ```
   Le second passe dès que le remplaçant du premier est prêt. Le PDB **n'empêche pas** `kubectl delete pod` (pas d'éviction), la perte d'un nœud (involontaire), ni une mise à jour du Deployment (réglée par la stratégie). `unhealthyPodEvictionPolicy: AlwaysAllow` : un pod non prêt peut être évincé même si le budget est épuisé (sinon un pod malade bloque le drain de son nœud pour toujours).
7. **Pas de retour arrière automatique** : le Deployment ne sait pas ce qu'est une « bonne » version (des pods prêts ne prouvent pas que l'application rend le bon service) ; il garantit seulement qu'une mauvaise version bloquée ne remplace pas la bonne. Le retour arrière automatique demande un critère métier (taux d'erreur, latence) et un outil qui le mesure : déploiement progressif (Argo Rollouts, Flagger) avec les métriques du M21, et GitOps (M20) pour que le retour arrière soit un `git revert`.

**Explications**

Le contrôleur de Deployment crée un nouveau ReplicaSet par gabarit de pod (empreinte `pod-template-hash`) et fait varier les deux ReplicaSets dans les bornes `maxSurge`/`maxUnavailable`, en ne comptant comme disponibles que les pods prêts depuis `minReadySeconds`. Les anciens ReplicaSets (à 0 réplica) sont l'historique (`revisionHistoryLimit`). Le PDB est consulté par l'**API d'éviction** seulement : `drain`, l'autoscaler de cluster, `kubectl create … /eviction`.

**Alternatives**
- `strategy: Recreate` : coupure assumée, utile quand deux versions ne peuvent pas coexister (schéma incompatible).
- PDB en `minAvailable: 2` : équivalent ici ; `maxUnavailable` s'adapte mieux au changement du nombre de réplicas.
- Bleu/vert ou canari par deux Deployments et le Service (M15 avec la Gateway API, poids de routage).

**Pièges classiques**
- `maxUnavailable: 0` **et** `maxSurge: 0` : refusé par l'API.
- PDB `minAvailable: 1` sur un Deployment à 1 réplica : le drain ne finit jamais (E21, E17).
- Sélecteur de PDB qui ne correspond à aucun pod : `ALLOWED DISRUPTIONS 0`… ou rien de protégé, selon la forme.
- `kubectl rollout undo` sans mettre le dépôt à jour : la prochaine application ramène la mauvaise version.
- `port-forward` pour mesurer la disponibilité : il s'attache à un pod, qui disparaît.

**En production chez MédiSphère**
Métriques de disponibilité côté client (M21) plutôt qu'une sonde maison, `preStop` systématique, PDB obligatoire pour tout Deployment de plus d'un réplica (Kyverno, M26), retour arrière par GitOps (M20).

---

### M14-E17 — Drainer, ajouter et retirer un nœud

**Solution**

Fichiers : fiche [`CHG-1517-ajout-retrait-noeud.md`](fichiers/M14-E17/medisphere/docs/kubernetes/changements/CHG-1517-ajout-retrait-noeud.md) (le déroulé complet, commandes comprises), [`terraform.tfvars.extrait`](fichiers/M14-E17/infra/envs/k8s/terraform.tfvars.extrait) ; `cluster/noeuds.yaml` reçoit puis perd l'entrée `k8s-w04` (modèle en commentaire dans le fichier d'E14).

1. **Fiche** rédigée avant d'agir : voir le fichier (objectif, prérequis cochés, étapes A-B-C, contrôles, retour arrière, résultat).
2. **Maintenance de `k8s-w02`.**
   ```
   admin@adm01:~$ kubectl drain k8s-w02
   node/k8s-w02 cordoned
   error: unable to drain node "k8s-w02" due to error: [cannot delete DaemonSet-managed Pods (use --ignore-daemonsets to ignore):
     kube-system/cilium-…, wb-essais/sonde-noeud-…, cannot delete Pods with local storage (use --delete-emptydir-data to override):
     mediagenda-dev/valkey-1, …]
   admin@adm01:~$ kubectl drain k8s-w02 --ignore-daemonsets --delete-emptydir-data --timeout=10m
   evicting pod mediagenda-dev/mediagenda-api-…
   error when evicting pods/"mediagenda-api-…" -n "mediagenda-dev" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
   …
   node/k8s-w02 drained
   admin@adm01:~$ kubectl uncordon k8s-w02
   ```
   Le premier `drain` a quand même **cordonné** le nœud (`SchedulingDisabled`) avant d'échouer : ne pas l'oublier dans cet état. Le PDB fait attendre l'éviction d'un second réplica de l'API tant que le remplaçant du premier n'est pas prêt. 0 `ECHEC` attendu ; Valkey `-1` (ou `-2`) est recréé ailleurs et se resynchronise. Après `uncordon`, rien ne revient sur `k8s-w02` : l'ordonnanceur place, il ne réorganise pas.
3. **Ajout.** MR `plateforme/infra` (`avec_k8s_w04 = true`), NetBox, puis `task noeuds -- --limit k8s-w04`. ⚠️ À vérifier sur ton lab : si le rôle `k8s_travailleur` lit des faits de `k8s-cp01` (jeton de jonction obtenu par délégation), limite à `k8s-w04,k8s-cp01` ; le playbook est idempotent pour `k8s-cp01`. `task etiquettes` après l'ajout de `k8s-w04` à `cluster/noeuds.yaml`. Un jeton de jonction kubeadm a une durée de vie (24 h par défaut, plus court si le rôle le demande) : `kubeadm token list` ne doit pas montrer de jeton sans expiration (`<forever>`).
4. **Charges.** Drain de `k8s-w01` : ses réplicas de l'API vont sur `k8s-w04` (seul autre nœud de la baie A : la contrainte par zone les y pousse), Valkey et la sonde aussi.
5. **Retrait.** Voir la fiche, partie C. `kubeadm reset` le dit lui-même : *The reset process does not clean CNI configuration… does not reset or clean up iptables rules or IPVS tables… does not clean your kubeconfig files*. L'ordre compte : `kubectl delete node` **avant** la destruction de la VM, sinon le nœud reste `NotReady` dans l'API (et ses pods de DaemonSet `Terminating`) jusqu'à suppression manuelle.
6. **Fermeture** : mesures dans la fiche ; reprise dans RB-140 (E22) des options de drain, du nettoyage et de `task etiquettes`.

**Explications**

`drain` = `cordon` (le nœud n'accepte plus de pods) + éviction de chaque pod par l'API d'éviction (PDB respectés, `terminationGracePeriodSeconds` respecté). Les pods de DaemonSet tolèrent `unschedulable` : ils resteraient de toute façon. Un pod « nu », sans contrôleur, serait perdu : `drain` refuse sans `--force`. `kubeadm join` utilise un jeton d'amorçage (Secret `bootstrap-token-*` dans `kube-system`) et l'empreinte de la CA, obtient un certificat de kubelet par CSR (approuvé automatiquement), puis le kubelet s'enregistre.

**Alternatives**
- Remplacer plutôt que réparer : un travailleur malade est drainé, supprimé et reconstruit par le code (E23) ; c'est la pratique cible.
- Le *descheduler* pour rééquilibrer après `uncordon`.
- Laisser le nœud dans NetBox en statut *planifié* pour le réutiliser : possible, mais l'inventaire Ansible filtre sur le statut actif.

**Pièges classiques**
- `--force` « pour que ça passe ».
- `--disable-eviction` (supprime au lieu d'évincer : PDB ignorés).
- Un PDB impossible à satisfaire (1 réplica, `minAvailable: 1`) : le drain boucle jusqu'au `--timeout`.
- Détruire la VM avant `kubectl delete node`.
- Oublier `task etiquettes` : le nouveau nœud n'a pas de zone, la contrainte de répartition l'ignore (ou le compte comme une zone vide selon les réglages).

**En production chez MédiSphère**
Drains automatisés par un outil de maintenance (kured pour les redémarrages après mise à jour du noyau), fenêtres de maintenance déclarées, nœuds remplacés plutôt que réparés, alertes sur les nœuds `SchedulingDisabled` depuis plus d'une heure.

---

### M14-E18 — Admission : Pod Security et ValidatingAdmissionPolicy

**Solution**

Fichiers : [`espaces/mediagenda-dev/00-namespace.yaml`](fichiers/M14-E18/k8s/espaces/mediagenda-dev/00-namespace.yaml) (et recette), [`espaces/wb-essais.yaml`](fichiers/M14-E18/k8s/espaces/wb-essais.yaml), [`espaces/wb-system.yaml`](fichiers/M14-E18/k8s/espaces/wb-system.yaml), [`admission/10-images-medisphere.yaml`](fichiers/M14-E18/k8s/admission/10-images-medisphere.yaml) ; essais [`refuses.yaml`](fichiers/M14-E18/essais/refuses.yaml), [`accepte.yaml`](fichiers/M14-E18/essais/accepte.yaml).

1. **Lecture.** Une requête d'écriture passe par : authentification → autorisation (RBAC) → **admission mutante** (dont `ServiceAccount`, `LimitRanger`, `Priority`, MutatingAdmissionPolicy, webhooks mutants) → validation du schéma → **admission validante** (dont `PodSecurity`, `ResourceQuota`, ValidatingAdmissionPolicy, webhooks validants) → persistance dans etcd. Pod Security et la politique CEL sont donc des **validations** : elles refusent, elles ne corrigent pas. L'admission n'intervient qu'à l'écriture : un pod existant n'est jamais réévalué (`enforce` ne touche pas aux pods en marche) ; un Deployment dont le gabarit viole le profil est **accepté** (avec un avertissement `would violate PodSecurity`), puis ses pods sont refusés à leur création par le ReplicaSet (événements `FailedCreate`). D'où l'intérêt de la politique CEL qui, elle, vise aussi les contrôleurs.
2. **Mesure avant d'imposer.**
   ```
   admin@adm01:~$ kubectl label --dry-run=server --overwrite ns mediagenda-dev pod-security.kubernetes.io/enforce=restricted
   namespace/mediagenda-dev labeled (server dry run)        # aucun avertissement : tout est conforme
   admin@adm01:~$ kubectl label --dry-run=server --overwrite ns wb-essais pod-security.kubernetes.io/enforce=restricted
   Warning: existing pods in namespace "wb-essais" violate the new PodSecurity enforce level "restricted:latest"
   Warning: mediagenda-api-…: allowPrivilegeEscalation != false, …     # selon tes essais d'E07-E08
   ```
   Dans `mediagenda-*`, les manifestes d'E19 et suivants sont déjà conformes (contexte de sécurité complet, utilisateurs 999 et 10001, `seccompProfile: RuntimeDefault`) ; un écart typique viendrait d'un essai resté là (`kubectl run` sans contexte de sécurité) : supprime-le. `wb-essais` ne passerait pas `restricted` (essais du palier 1) : il reçoit `baseline` en `enforce`, `restricted` seulement en `warn`/`audit`.
3. **Étiquettes.** Fichiers d'espace ; `task appliquer`. `kubectl apply --dry-run=server -f refuses.yaml` (premier objet) :
   ```
   Error from server (Forbidden): … pods "refus-psa" is forbidden: violates PodSecurity "restricted:v1.35":
   allowPrivilegeEscalation != false (container "attente" must set securityContext.allowPrivilegeEscalation=false),
   unrestricted capabilities (container "attente" must set securityContext.capabilities.drop=["ALL"]),
   runAsNonRoot != true (pod or container "attente" must set securityContext.runAsNonRoot=true),
   seccompProfile (pod or container "attente" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
   ```
   Version figée (`enforce-version: v1.35`) : une montée de Kubernetes (E25) ne durcit pas la règle à l'insu de tous ; `warn-version: latest` annonce ce qui casserait au prochain alignement. Pourquoi `wb-diagnostic` est `privileged` : les pods de `kubectl debug node/` partagent réseau, processus et système de fichiers de l'hôte ; l'espace est réservé aux administrateurs et vidé après usage (exception inscrite dans la documentation d'accueil).
4. **Politique en `[Warn, Audit]`.** [`10-images-medisphere.yaml`](fichiers/M14-E18/k8s/admission/10-images-medisphere.yaml) avec `validationActions: ["Warn", "Audit"]` d'abord. Les objets non conformes sont **acceptés** avec `Warning: Validation failed for ValidatingAdmissionPolicy 'medisphere-images' with binding 'medisphere-images': image(s) hors du registre MédiSphère : docker.io/library/busybox:1.37 …`. Passée en `Deny` :
   ```
   admin@adm01:~$ kubectl apply --dry-run=server -f ~/m14/e18/refuses.yaml
   … pods "refus-registre" is forbidden: ValidatingAdmissionPolicy 'medisphere-images' with binding 'medisphere-images'
     denied request: image(s) hors du registre MédiSphère : docker.io/library/busybox:1.37 (autorisé : registry.par1.medisphere.internal/ ; …)
   … pods "refus-latest" is forbidden: … image(s) sans version explicite ou en « latest » : registry.par1.medisphere.internal/dockerhub/library/busybox:latest …
   … deployments.apps "refus-sans-etiquette" is forbidden: … sans version explicite ou en « latest » : registry.par1.medisphere.internal/dockerhub/library/busybox …
   ```
   La politique : `variables` (`specPod` selon le type d'objet, liste de toutes les `images`, `registres` tirés du paramètre, listes fautives), deux validations avec `messageExpression`. L'étiquette est cherchée dans le **dernier** segment (`registry:443/…` n'est pas une étiquette) ; un condensé `@sha256:` suffit.
5. **Recensement.**
   ```
   admin@adm01:~$ kubectl get pods -A -o json | jq -r '.items[] | select(.metadata.namespace | startswith("mediagenda-"))
       | . as $p | ([.spec.containers[], (.spec.initContainers // [])[]] | map(.image))[]
       | select((startswith("registry.par1.medisphere.internal/") | not) or endswith(":latest") or (split("/") | last | contains(":") | not))
       | "\($p.metadata.namespace)/\($p.metadata.name) \(.)"'
   ```
   Liste vide → MR qui passe la liaison en `["Deny"]`. (Le filtre ne connaît pas les condensés : relis les lignes restantes à la main.)
6. **Contrôles.** `accepte.yaml` passe ; un pod `docker.io/…` dans `wb-essais` ou `kube-system` passe (pas d'étiquette `medisphere.internal/equipe`). Ajouter `"registry.par1.medisphere.internal/,docker.io/library/"` dans la ConfigMap : le pod `refus-registre` devient acceptable, sans toucher à la politique ; on remet la valeur.
7. **Limites.**
   - Un conteneur éphémère est ajouté par la **sous-ressource** `pods/ephemeralcontainers` : la règle sur `pods` ne la vise pas (`resources: ["pods"]` ne couvre pas les sous-ressources). Il faudrait ajouter `pods/ephemeralcontainers` à `matchConstraints` (et lire alors `object.spec.ephemeralContainers`). Pod Security, lui, évalue les conteneurs éphémères. Choix ici : on les laisse passer (diagnostic avec busybox du cache), à décider avec Sophie.
   - ConfigMap de paramètres absente : `parameterNotFoundAction: Deny` → **tout** pod des espaces d'équipes est refusé (comportement sûr, mais panne d'admission : la ConfigMap est versionnée et appliquée avec la politique) ; avec `Allow`, la règle ne s'appliquerait plus du tout.
   - Une politique CEL ne voit que l'objet envoyé : elle ne sait pas si l'étiquette existe dans Harbor, ni si l'image est signée (Cosign, M13), ni ses vulnérabilités. Pour cela : Kyverno (`verifyImages`, M26) ou la politique de Harbor côté registre (M13-E14).

**Explications**

Pod Security Admission est un contrôleur intégré, configuré par étiquettes d'espace : trois profils (`privileged`, `baseline`, `restricted`), trois modes (`enforce` refuse, `warn` avertit le client, `audit` annote l'événement d'audit), chacun avec sa version. La ValidatingAdmissionPolicy (GA 1.30) exécute du CEL dans le kube-apiserver : pas de service externe à faire tourner, donc pas de panne d'admission par un webhook injoignable ; `failurePolicy: Fail` ne concerne que les erreurs d'évaluation (expression qui échoue, paramètre mal formé).

**Alternatives**
- Configuration par défaut de Pod Security dans le kube-apiserver (`AdmissionConfiguration`, `defaults` et `exemptions`) : tout espace sans étiquette reçoit `baseline`. Plus sûr pour les nouveaux espaces, mais demande de modifier le manifeste statique du kube-apiserver (configuration kubeadm, E25-E27).
- Kyverno ou Gatekeeper (M26) : règles plus riches, mutation, génération, rapports.
- Un webhook maison : non (disponibilité, maintenance).

**Pièges classiques**
- Passer en `enforce` sans `--dry-run=server` préalable.
- Oublier les `initContainers` et les conteneurs éphémères dans la règle.
- Chercher `:` dans toute l'image pour trouver l'étiquette (le port du registre).
- Une liaison sans `matchResources` : la règle s'applique à **tout** le cluster, `kube-system` compris (Cilium, CoreDNS ne passent plus).
- `enforce-version: latest` : la règle change à chaque montée de version.

**En production chez MédiSphère**
Configuration par défaut de Pod Security en `baseline` au niveau du kube-apiserver avec exemptions (`kube-system`) ; politiques d'images et de signatures par Kyverno (M26) ; journaux d'audit (E27) analysés pour les annotations `pod-security.kubernetes.io/audit-violations` et `validation.policy.admission.k8s.io/validation_failure` ; revue des exceptions chaque trimestre.

---

### M14-E19 — Tirer les images depuis Harbor

**Solution**

Fichiers : [`group_vars/k8s_par1/containerd.yml`](fichiers/M14-E19/ansible/inventories/lab/group_vars/k8s_par1/containerd.yml), [`outils/secret-tirage.sh`](fichiers/M14-E19/k8s/outils/secret-tirage.sh), [`outils/secret-mediagenda.sh`](fichiers/M14-E19/k8s/outils/secret-mediagenda.sh), [`espaces/mediagenda-dev/30-comptes-service.yaml`](fichiers/M14-E19/k8s/espaces/mediagenda-dev/30-comptes-service.yaml) (et recette) ; côté équipe [`k8s/dev/`](fichiers/M14-E19/mediagenda-api/k8s/dev/) (`10-config.yaml`, `20-postgresql.yaml`, `30-valkey.yaml`, `40-api.yaml`).

1. **Miroir ou chemin explicite.** `docker.io/library/postgres:18-trixie` à travers un miroir : le **nom** reste celui de Docker Hub (dans le manifeste, dans `crictl images`), c'est containerd qui va le chercher chez Harbor ; si le miroir échoue, il se replie sur Docker Hub. `registry.par1.medisphere.internal/dockerhub/library/postgres:18-trixie` : le nom **dit** d'où vient l'image ; pas de repli possible, pas d'ambiguïté. La règle d'admission d'E18 exige la seconde forme : vérifiable dans l'objet (elle ne voit pas la configuration des nœuds), et indépendante de la configuration de containerd. Les miroirs restent utiles pour tout ce qui n'est pas écrit par nous : images de Cilium, de kubeadm (pause, CoreDNS, etcd…), des charts installés.
2. **Miroirs.** [`containerd.yml`](fichiers/M14-E19/ansible/inventories/lab/group_vars/k8s_par1/containerd.yml) : quatre entrées, `override_path: true`, repli sur l'origine.
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/k8s-noeuds.yml --limit k8s-w01 --tags containerd --diff
   admin@k8s-w01:~$ cat /etc/containerd/certs.d/docker.io/hosts.toml
   server = "https://registry-1.docker.io"
   [host."https://registry.par1.medisphere.internal/v2/dockerhub"]
     capabilities = ["pull", "resolve"]
     override_path = true
   admin@k8s-w01:~$ sudo crictl pull docker.io/library/busybox:1.37
   admin@k8s-w01:~$ sudo crictl pull registry.k8s.io/pause:3.10.1
   admin@adm01:~$ curl -s -u "$HARBOR_USER:$HARBOR_PASSWORD" https://registry.par1.medisphere.internal/api/v2.0/projects/k8s/repositories | jq -r '.[] | "\(.name) \(.pull_count)"'
   k8s/pause 7
   ```
   (Identifiants du robot de lecture des checks, `~/.config/workbook/harbor-checks.env`.) Côté `reg01`, `sudo grep 10.10.40.61 /var/log/harbor/proxy.log | tail` montre les requêtes `GET /v2/dockerhub/library/busybox/manifests/1.37` du nœud. ⚠️ À vérifier sur ton lab : le chemin des journaux de Harbor dépend de `log.local.location` dans `harbor.yml` (M13). Les `hosts.toml` sont relus à chaque tirage : pas de redémarrage de containerd. Puis les autres nœuds (sans `--limit`).
3. **Image privée sans identifiants.** `sudo crictl pull registry.par1.medisphere.internal/medisphere/mediagenda-api:v1.0.0` → `failed to authorize: … 401 Unauthorized`. Le nœud lui-même n'a pas d'identifiants : c'est le **kubelet** qui les passe à containerd, au moment du tirage, à partir des `imagePullSecrets` du pod.
4. **Outils.** [`secret-tirage.sh`](fichiers/M14-E19/k8s/outils/secret-tirage.sh) : identifiants lus dans un fichier 600 (refus sinon), JSON construit par `jq -n` depuis l'**environnement** (`env.HARBOR_PASSWORD` : pas dans `ps`), Secret créé par `kubectl create secret generic --type=kubernetes.io/dockerconfigjson --from-file=.dockerconfigjson=/dev/stdin --dry-run=client -o yaml | kubectl apply -f -` (idempotent). [`secret-mediagenda.sh`](fichiers/M14-E19/k8s/outils/secret-mediagenda.sh) : mot de passe aléatoire passé par l'entrée standard, jamais affiché, Secret créé seulement s'il n'existe pas.
   ```
   admin@adm01:~/src/k8s$ outils/secret-tirage.sh mediagenda-dev mediagenda-recette
   admin@adm01:~/src/k8s$ outils/secret-mediagenda.sh mediagenda-dev
   admin@adm01:~$ kubectl get secret harbor-pull -n mediagenda-dev -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d \
       | jq '.auths | map_values({username, password: "***", auth: "***"})'
   { "registry.par1.medisphere.internal": { "username": "robot$k8s-pull", "password": "***", "auth": "***" } }
   ```
5. **Comptes de service.** [`30-comptes-service.yaml`](fichiers/M14-E19/k8s/espaces/mediagenda-dev/30-comptes-service.yaml) ; `task appliquer`. Un pod qui utilise l'image privée **sans** nommer de Secret reçoit de l'admission `ServiceAccount` : `spec.imagePullSecrets: [{name: harbor-pull}]` (copié du compte). Les manifestes de l'équipe n'ont donc plus d'`imagePullSecrets` : changer de robot ou de Secret ne touche que la plateforme.
6. **Déploiement.** Repris de `k8s/essais/` : mêmes noms (`postgresql`, `valkey`, `mediagenda-api`, `mediagenda-api-config`, `mediagenda-db`), images en chemins Harbor explicites, contexte de sécurité complet (le profil `restricted` arrivera en E18 : autant y être déjà), `serviceAccountName: mediagenda-api`, pas d'`imagePullSecrets`.
   ```
   admin@adm01:~/src/mediagenda-api$ kubectl apply -f k8s/dev/
   admin@adm01:~$ kubectl rollout status deploy/mediagenda-api -n mediagenda-dev
   admin@adm01:~$ kubectl port-forward -n mediagenda-dev svc/mediagenda-api 8080:80 &
   admin@adm01:~$ curl -s localhost:8080/pret
   {"statut":"pret","postgresql":"ok","valkey":"ok"}
   admin@adm01:~$ curl -s -X POST localhost:8080/api/v1/rendez-vous -H 'Content-Type: application/json' \
       -d '{"patient":"Jeanne Exemple","praticien":"dr-morel","debut":"2026-11-02T09:00:00+01:00","duree_minutes":30,"motif":"Suivi"}'
   ```
   ⚠️ Le Secret `mediagenda-db` doit exister **avant** le premier démarrage de PostgreSQL (le mot de passe n'est lu qu'à l'initialisation de la base) ; s'il change ensuite, la base (jetable) doit être recréée.
7. **`imagePullPolicy`.** Non écrite, elle vaut `IfNotPresent` pour une étiquette autre que `latest` (et `Always` pour `latest` ou sans étiquette). Un pod de `wb-essais`, **sans** Secret, qui demande `medisphere/mediagenda-api:v1.0.0` avec `IfNotPresent` sur un nœud qui a déjà l'image… **démarre** : le kubelet ne retire pas l'image et ne revérifie pas les droits. Avec `Always`, il retire (même si les couches sont en cache) et échoue en `ErrImagePull`/401. C'est une fuite : une image privée tirée pour un espace est utilisable par tout espace dont un pod atterrit sur ce nœud. Parades : l'admission `AlwaysPullImages` (coûteuse, chaque démarrage interroge Harbor), ou la fonctionnalité `KubeletEnsureSecretPulledImages` (le kubelet mémorise avec quelles identités une image a été tirée et revérifie pour un autre pod) : ⚠️ à vérifier sur ta version — son niveau (alpha/bêta) et son activation par défaut se lisent dans *Feature Gates* de la documentation 1.35 et 1.36.
8. **Condensés.** `…/mediagenda-api:v1.0.0@sha256:<CONDENSÉ>` : le kubelet tire exactement ce contenu (l'étiquette devient indicative), immuable même si l'étiquette était déplacée ; la politique d'E18 l'accepte. Prix : une mise à jour = changer le condensé ; Renovate (M13) sait proposer ces MR (`pinDigests`). Chez nous, `v*` est déjà immuable dans Harbor : le condensé apporte surtout une garantie **vérifiable dans le manifeste**, et prépare la vérification de signature (M26).

**Explications**

containerd résout une image par son nom de registre (`docker.io`, `quay.io`…) et consulte `/etc/containerd/certs.d/<registre>/hosts.toml` (`config_path` dans `config.toml`, posé en E02) : les `[host]` sont essayés dans l'ordre, `server` en dernier. Un cache Harbor (*proxy cache*) relaie la requête vers l'origine à la première demande, garde le manifeste et les couches, et sert les suivantes. Le Secret de tirage est un `config.json` Docker ; le kubelet le lit au nom du pod et le passe au CRI.

**Alternatives**
- Pas de miroir, chemins Harbor partout : impossible pour les composants qu'on n'écrit pas (Cilium, kubeadm) sans réécrire leurs images une à une.
- Identifiants de registre au niveau du **nœud** (fichier d'identifiants du kubelet, ou *credential provider*) : plus besoin de Secret par espace, mais tous les pods du nœud peuvent tirer les images privées — l'inverse de ce qu'on veut.
- Projets Harbor publics pour les images applicatives : refusé (images internes, données de santé dans les noms de projet ou les journaux de build).

**Pièges classiques**
- `override_path` absent : containerd demande `…/v2/dockerhub/v2/library/…` → 404.
- `HARBOR_USER=robot$k8s-pull` sans apostrophes : `$k8s` est interprété, l'utilisateur devient `robot-pull`.
- Mot de passe passé en argument (`--docker-password=…`) : visible dans `ps` et l'historique du shell.
- Secret de tirage créé dans un espace et référencé dans un autre : un Secret est **namespacé**.
- Croire que `imagePullSecrets` protège une image déjà présente sur le nœud (étape 7).

**En production chez MédiSphère**
Robot de tirage à durée limitée et renouvelé par Vault (M25) avec External Secrets ; `KubeletEnsureSecretPulledImages` ou `AlwaysPullImages` selon l'état de la fonctionnalité ; condensés partout et vérification de signature à l'admission (M26) ; supervision des tirages en échec (`kubelet_image_pull_*`, M21) ; coupure d'Internet pour le VLAN 40 une fois tous les composants passés par Harbor.
