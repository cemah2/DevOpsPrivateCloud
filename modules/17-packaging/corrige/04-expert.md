# Module 17 — Corrigé du palier 4 : Expert

> ⚠️ Corrigé — à lire après avoir cherché.

Les corrigés des pannes suivent la trame habituelle : **symptômes → hypothèses → commandes de diagnostic dans l'ordre → cause racine (par variante) → correctif → prévention**. Avec Helm et Kustomize, « j'ai désinstallé et réinstallé » est la pire des réparations. Elle efface la preuve (Secrets de release, `managedFields`), interrompt le service, et peut emporter des données : PVC d'un sous-chart, objets à `resource-policy` absente.

Les scripts d'injection sont dans `corrige/pannes/`. `_m17-commun.sh` contient les fonctions partagées :
- Helm avec le kubeconfig d'administration ;
- lecture, décodage et écriture des Secrets de release ;
- branche locale « de Lucas » dans une copie de travail, puis annulation.

Les objets modifiés sont sauvegardés sur `adm01` dans `~/.local/state/workbook/k8s/M17-EXX/`, l'état de la panne dans `~/.local/state/workbook/M17-EXX/`.

**Testé** pendant la rédaction, sur un banc kube-apiserver 1.36 + etcd sans nœuds (Helm 4.3.0, Kustomize 5.8.1 de kubectl 1.36.5, yq 4.54.1) :
- injection, constat et annulation des variantes 1 à 3 de E19, 1 à 3 de E20, 1 et 2 de E21, 1 et 2 de E22 ;
- les réparations décrites ici, et les messages d'erreur cités (sorties réelles) ;
- le script `helm-release.sh` de E23, avec les deux pilotes.

**Points non testés en conditions réelles** :
- E22 variante 3 : le banc n'avait pas de `kube-controller-manager`. Sont à vérifier sur `k8s-par1` :
  - le nom du gestionnaire de champs du contrôleur HPA (`kube-controller-manager`, sous-ressource `scale`) ;
  - la montée à `minReplicas` sans métriques disponibles.
- E21 : application de l'overlay `prod` complet sur `k8s-par1` (CRD réelles de CNPG, Cilium, Gateway API).
- E23 : nom exact de la variable de connexion du pilote `sql` (`HELM_DRIVER_SQL_CONNECTION_STRING` dans la documentation de Helm 3 ; à confirmer pour Helm 4).

---

## Méthode commune aux pannes de packaging

1. **Reproduire et lire le message en entier.** Helm dit presque toujours l'étage : `UPGRADE FAILED: another operation…` (état), `YAML parse error on <fichier>` (gabarit), `values don't meet the specifications of the schema` (valeurs), `conflict occurred while applying object` (serveur, SSA), `execution error at (<fichier>:<ligne>)` (`required`/`fail`).
2. **Situer l'étage.**
   - Rendu : `helm template --debug`, `kubectl kustomize`.
   - Application : `--dry-run=server`, `kubectl diff --server-side`.
   - État : `helm history`, Secrets `sh.helm.release.v1.*`, `managedFields`, `rollout history`.
3. **Chercher ce qui a bougé** :
   - Git : `git log --all`, `git reflog`, branches locales ;
   - cluster : `managedFields[].time`, ReplicaSets et leur date ;
   - Helm : `info.description` et dates des révisions.
4. **Corriger à la racine**, dans le dépôt, puis remettre le cluster d'accord par le chemin normal. Les diffs doivent être vides.
5. **Prévenir** : quel job de pipeline, quelle règle de schéma, quel RBAC aurait arrêté la panne avant l'utilisateur ?

---

### M17-E19 — Panne : la release est bloquée

**Démarche de diagnostic**

*Symptômes* : `another operation (install/upgrade/rollback) is in progress` (variantes 1 et 3), ou `release: already exists` avec un historique auquel il manque la dernière révision (variante 2).

*Hypothèses* : opération réellement en cours (job de CI, collègue) ; révision restée `pending-*` après interruption ; Secret de révision illisible ; droits.

**Étape 1 — Constater.**

```
admin@adm01:~$ helm status mediagenda -n mediagenda-dev | grep -E 'STATUS|REVISION|DESCRIPTION'
admin@adm01:~$ helm history mediagenda -n mediagenda-dev
admin@adm01:~$ helm list -A --pending
admin@adm01:~$ kubectl get secret -n mediagenda-dev -l owner=helm,name=mediagenda -L status,version
```

Avant de conclure à un blocage, on vérifie qu'aucune opération ne tourne vraiment : jobs de CI en cours sur `plateforme/k8s`, collègues. Débloquer une release qu'un autre processus est en train d'écrire produirait deux écritures concurrentes.

**Variante 1 (dev) et variante 3 (metrics-server) — révision `pending-upgrade`.** Sortie réelle :

```
REVISION  UPDATED                   STATUS           CHART              DESCRIPTION
1         …                         superseded       mediagenda-0.6.0   Install complete
2         …                         deployed         mediagenda-0.6.0   Upgrade complete
3         Wed … 21:53:25            pending-upgrade  mediagenda-0.6.0   Preparing upgrade
```

`info.description = "Preparing upgrade"` et la date de la veille au soir, décodées du Secret v3, racontent un upgrade qui a écrit sa révision puis n'est jamais allé au bout. Helm refuse toute nouvelle opération tant que la dernière révision est `pending-*`. Il n'y a pas de verrou : c'est l'état de la dernière révision qui sert de verrou. On vérifie que les objets sont sur la révision 2 (image, `rollout history`) : ici, rien n'a été appliqué. Correctif, après sauvegarde du Secret v3 :

```
admin@adm01:~$ helm rollback mediagenda 2 -n mediagenda-dev --wait
Rollback was a success! Happy Helming!
admin@adm01:~$ helm upgrade mediagenda oci://registry.par1.medisphere.internal/charts/mediagenda --version <X.Y.Z> -n mediagenda-dev -f valeurs-dev.yaml
```

Après le retour, la révision 4 (`deployed`) recouvre la révision 3, qui peut rester `pending-upgrade` dans l'historique : constaté avec Helm 4.3. Elle ne bloque plus, parce que seule la **dernière** révision compte. Variante 3 : même lecture dans `kube-system`, puis `helmfile -e par1 -l composant=metrics-server apply`. Le job de nuit avait été annulé pendant l'attente (`--wait`). Comme les valeurs ne changeaient pas, aucun objet n'était touché.

**Variante 2 — Secret de révision illisible.**

```
admin@adm01:~$ helm upgrade mediagenda … -n mediagenda-dev
Error: UPGRADE FAILED: release: already exists
admin@adm01:~$ helm history mediagenda -n mediagenda-dev      # la révision 2 manque
1   …   superseded   …
admin@adm01:~$ kubectl get secret -n mediagenda-dev -l owner=helm,name=mediagenda -L status,version
sh.helm.release.v1.mediagenda.v1   …   superseded   1
sh.helm.release.v1.mediagenda.v2   …   deployed     2
admin@adm01:~$ kubectl get secret sh.helm.release.v1.mediagenda.v2 -n mediagenda-dev -o jsonpath='{.data.release}' | base64 -d | base64 -d | gzip -dc | head -c 100
gzip: stdin: unexpected end of file
```

Helm ignore en silence une révision qu'il ne sait pas décoder. Il prend v1 pour la dernière et veut écrire v2, qui existe déjà. Les objets, eux, sont bien ceux de la révision 2 (la version tourne). Correctif : sauvegarder le Secret v2, vérifier que v1 se décode, supprimer **v2 seul**, puis `helm upgrade`. Helm réécrit v2 depuis l'état réel, en SSA.

```
admin@adm01:~$ kubectl get secret sh.helm.release.v1.mediagenda.v2 -n mediagenda-dev -o yaml > ~/sauvegardes/mediagenda-v2.yaml && chmod 600 ~/sauvegardes/mediagenda-v2.yaml
admin@adm01:~$ kubectl delete secret sh.helm.release.v1.mediagenda.v2 -n mediagenda-dev
admin@adm01:~$ helm upgrade mediagenda … -n mediagenda-dev      # REVISION: 2, deployed
```

Origine réaliste : un Secret modifié à la main (« nettoyage »), une écriture interrompue, une sauvegarde etcd ou Velero restaurée partiellement.

**Prévention** : RB-170 ([exemple](fichiers/M17-E19/medisphere/docs/kubernetes/packaging/runbooks/RB-170-release-bloquee.md)). En CI :
- le `timeout` du job doit être supérieur à `--timeout` ;
- un `resource_group` par release ;
- `rollbackOnFailure` ;
- on n'annule jamais un job d'application en cours.

Une alerte « release en `pending-*` depuis plus de 15 min » viendra au M21 (métriques de Helm par un exporteur, ou script `helm list -A --pending`).

---

### M17-E20 — Panne : le rendu du chart échoue

**Démarche de diagnostic**

```
admin@adm01:~/src/mediagenda-chart$ git branch --show-current ; git log --oneline -3 ; git show --stat HEAD
admin@adm01:~/src/mediagenda-chart$ helm lint --strict charts/mediagenda --set medisphere.environnement=recette
admin@adm01:~/src/mediagenda-chart$ helm template mediagenda charts/mediagenda -n mediagenda-recette --set medisphere.environnement=recette > /dev/null
```

**Variante 1 — type refusé par le schéma** (`lucas/ttl-lisible`) :

```
Error: values don't meet the specifications of the schema(s) in the following chart(s):
mediagenda:
- at '/config/cacheTtl': got string, want integer
```

Étage : **valeurs**. `git show` : `cacheTtl: "60s"` dans `values.yaml`. L'application lit `MEDIAGENDA_CACHE_TTL` comme un entier (`config.py` : `doit être un entier`). Le schéma a donc raison, et le message montre qu'il fait son travail. Correctif : nouveau commit `fix: cacheTtl reste un nombre de secondes`. Si Julien veut une durée lisible, c'est un changement de l'application d'abord, puis du schéma (MR distinctes). Le pipeline arrête cette erreur dès `helm-lint`.

**Variante 2 — indentation** (`lucas/alignement`) :

```
Error: YAML parse error on mediagenda/templates/deployment.yaml: error converting YAML to JSON:
yaml: line 64: block sequence entries are not allowed in this context
```

Étage : **gabarit**. La ligne citée est celle du **rendu**, pas du gabarit. `helm template --debug --show-only templates/deployment.yaml` affiche le document fautif : `env:            - name: MEDIAGENDA_DB_URL` sur une seule ligne. `git show` : `| nindent 12` est devenu `| indent 12`, et `indent` n'ajoute pas le saut de ligne. Correctif : revenir à `nindent 12`. Test qui le voit : n'importe quel test helm-unittest sur `deployment.yaml` échoue au rendu. La règle à retenir : on écrit toujours `{{- include … | nindent N }}` derrière la clé parente.

**Variante 3 — `required` et chemin de valeur** (`lucas/nommage-url`) :

```
Error: execution error at (mediagenda/templates/migrations-job.yaml:41:12):
externalValkey.url est obligatoire quand valkey.enabled est faux
```

Pourtant `externalValkey.url` est bien dans `values.yaml`. `git show` : le gabarit `mediagenda.valkeyUrl` lit désormais `.Values.externalValkey.uri`. Le message de `required` décrit ce que l'auteur **croyait** lire. Correctif : revenir à `.url`, ou renommer partout (valeur, schéma, tests), ce qui serait une rupture : `feat!:`.

Piège constaté pendant la rédaction : **`helm lint --strict` passe** sur cette variante. En mode lint, Helm ne rend pas `required` bloquant. Seul le rendu (`helm template`, job `helm-lint` du pipeline qui rend chaque environnement) l'arrête. Ajoute un test helm-unittest qui vérifie la valeur de `MEDIAGENDA_VALKEY_URL` rendue (`redis://valkey:6379/0`).

**Pourquoi Lucas ne l'a pas vu** : il n'a lancé que `helm lint` (v3), ou rien (v1, v2), et la branche n'a jamais été poussée, donc aucun pipeline. Prévention : `pre-commit` du projet (M01) avec un hook local `helm template` et `helm unittest`, et la règle « une branche se pousse le jour même ».

---

### M17-E21 — Panne : la production déploie la mauvaise image

**Démarche de diagnostic**

*Étape 1 — Les faits.*

```
admin@adm01:~$ kubectl get deploy mediagenda -n mediagenda-prod -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
admin@adm01:~$ kubectl rollout history deploy/mediagenda -n mediagenda-prod
admin@adm01:~$ kubectl get rs -n mediagenda-prod -l app.kubernetes.io/name=mediagenda --sort-by=.metadata.creationTimestamp
admin@adm01:~$ kubectl get deploy mediagenda -n mediagenda-prod --show-managed-fields -o json | jq '.metadata.managedFields[] | {manager, operation, time}'
{"manager":"kubectl","operation":"Apply","time":"<HIER 17:4x>"}
```

Le gestionnaire est `kubectl`, celui de la livraison normale. Ce n'est donc pas un `kubectl edit` : quelqu'un a appliqué un **rendu** d'overlay, hier vers 17 h 40.

*Étape 2 — `main` est-elle en cause ?*

```
admin@adm01:~/src/mediagenda-deploiement$ git fetch && git status
admin@adm01:~$ mkdir /tmp/prod-main && git -C ~/src/mediagenda-deploiement archive origin/main | tar -x -C /tmp/prod-main
admin@adm01:~$ kubectl diff --server-side -k /tmp/prod-main/overlays/prod
-        image: …/mediagenda-api:v1.1.0
+        image: …/mediagenda-api:v1.0.0
```

`main` prévoit la version approuvée. Ce qui tourne vient d'ailleurs.

*Étape 3 — D'où ?*

```
admin@adm01:~/src/mediagenda-deploiement$ git branch -a ; git reflog -8
… checkout: moving from lucas/essai-version-prod to main
… commit: chore(prod): essai de la nouvelle version avant le comité
admin@adm01:~/src/mediagenda-deploiement$ git diff main lucas/essai-version-prod
```

**Variante 1 — `images:` égaré.** Lucas a ajouté à `overlays/prod/kustomization.yaml` :

```yaml
images:
  - name: registry.par1.medisphere.internal/medisphere/mediagenda-api
    newTag: v1.1.0
```

Il croyait le component `livraison` « toujours en dernier ». C'est vrai **parmi les components**. Mais l'ordre de construction de Kustomize est le suivant :
1. accumuler les `resources` ;
2. appliquer les `components` dans l'ordre de la liste (`livraison`, ses `replacements`) ;
3. appliquer les **transformateurs propres à l'overlay** : `images`, `replicas`, `patches`, `labels`…

Le `images:` de l'overlay passe donc **après** `livraison` et l'emporte. Comportement vérifié pendant la rédaction avec Kustomize 5.8.2 et 5.8.1. Seul un overlay *parent*, qui inclurait celui-ci en ressource, passerait encore après.

**Variante 2 — component `debogage` inclus à tort.** `components: [dependances, haute-disponibilite, debogage, livraison]` (commit `chore(prod): journaux détaillés pour le diagnostic…`). L'image est la bonne, mais :
- `MEDIAGENDA_LOG_LEVEL=DEBUG` et `MEDIAGENDA_LOG_FORMAT=texte` (le correctif stratégique du component) ;
- `MEDIAGENDA_CACHE_TTL=5`, d'où la lenteur des créneaux.

`kubectl diff` le montre. Un diagnostic en prod se fait par une MR temporaire, approuvée et datée, jamais depuis un poste.

*Correctif* : appliquer `main`, par le chemin normal.

```
admin@adm01:~/src/mediagenda-deploiement$ git switch main && git pull
admin@adm01:~/src/mediagenda-deploiement$ outils/rendre-base.sh --verifier       # base = chart signé attendu
admin@adm01:~/src/mediagenda-deploiement$ kubectl diff --server-side -k overlays/prod
admin@adm01:~/src/mediagenda-deploiement$ kubectl apply --server-side -k overlays/prod
admin@adm01:~$ kubectl rollout status deploy/mediagenda -n mediagenda-prod
```

On garde la branche de Lucas (preuve) jusqu'au post-mortem. On ne la pousse pas.

*Prévention* :
- garde-fou de CI [`outils/verifier-livraison.sh`](fichiers/M17-E21/deploiement/outils/verifier-livraison.sh) ([job](fichiers/M17-E21/deploiement/.gitlab-ci.extrait.yml)) : pour chaque overlay, l'image rendue (API **et** migrations) et `MEDIAGENDA_VERSION` égalent `livraison.yaml` ; en prod, ni `images:`, ni `debogage`, ni réglage de débogage ;
- aujourd'hui, rien n'empêche encore quelqu'un qui a les droits d'appliquer depuis son poste. Le RBAC doit réserver `apply` sur `mediagenda-prod` à un compte de déploiement ;
- au M20, Argo CD appliquera `main` seul, affichera toute dérive et pourra la réparer.

---

### M17-E22 — Panne : conflit de propriété des champs

**Démarche de diagnostic**

```
admin@adm01:~$ helm get values mediagenda -n mediagenda-dev -o yaml > /tmp/valeurs-dev.yaml
admin@adm01:~$ helm upgrade mediagenda oci://…/charts/mediagenda --version <la même> -n mediagenda-dev -f /tmp/valeurs-dev.yaml
```

Messages réels (Helm 4.3) :

```
v1 : Error: UPGRADE FAILED: conflict occurred while applying object mediagenda-dev/mediagenda apps/v1, Kind=Deployment:
     Apply failed with 2 conflicts: conflicts with "kubectl-edit" using apps/v1:
     - .spec.template.spec.containers[name="api"].env[name="MEDIAGENDA_LOG_LEVEL"].value
     - .spec.template.spec.containers[name="api"].resources.limits.memory
v2 : … Kind=ConfigMap: Apply failed with 1 conflict: conflict with "kubectl-client-side-apply" using v1: .data.MEDIAGENDA_CACHE_TTL
v3 : … Kind=Deployment: Apply failed with 1 conflict: conflict with "kube-controller-manager" with subresource "scale" using apps/v1: .spec.replicas
```

Puis `managedFields` (opération, sous-ressource, `time`) des objets nommés, et `kubectl get hpa -n mediagenda-dev` :
- v1 : `kubectl-edit`, `Update`, à l'heure où Lucas « regardait ». La valeur DEBUG et la limite à 1 Gi sont dans `fieldsV1`.
- v2 : `kubectl-client-side-apply` **et** l'annotation `last-applied-configuration` sur la ConfigMap : un `kubectl apply -f` côté client d'une copie modifiée.
- v3 : un objet nouveau, l'HPA `mediagenda` (min 2) ; `spec.replicas` appartient à `kube-controller-manager` (sous-ressource `scale`).

*Décision et correctif.*

- **v1 et v2, modification non voulue.** On retire l'entrée du gestionnaire manuel (et l'annotation `last-applied-configuration` en v2). Le `helm upgrade` habituel passe alors **sans** forçage et repose les valeurs du chart. Vérification : changer réellement `config.logLevel` ou `config.cacheTtl` dans les valeurs du dev, puis `helm upgrade` : ça passe.
  ```
  admin@adm01:~$ i=$(kubectl get deploy mediagenda -n mediagenda-dev --show-managed-fields -o json | jq '.metadata.managedFields | map(.manager) | index("kubectl-edit")')
  admin@adm01:~$ kubectl patch deploy mediagenda -n mediagenda-dev --type json -p "[{\"op\":\"remove\",\"path\":\"/metadata/managedFields/$i\"}]"
  ```
  `helm upgrade --force-conflicts` une seule fois donne le même résultat. Il est acceptable **après** l'analyse, pas à la place.
- **Piège, testé pendant la rédaction** : remettre `INFO` à la main avec `kubectl edit` fait passer l'upgrade suivant, parce que `kubectl-edit` et `helm` **copossèdent** le champ (même valeur). Le jour où le chart change `logLevel`, l'upgrade échoue à nouveau. Seuls le retrait de l'entrée ou `--force-conflicts` rendent l'objet propre.
- **v3, HPA.** Deux décisions possibles :
  1. *L'HPA n'est pas voulu en dev* (cas du ticket) : on supprime l'HPA, on retire l'entrée `kube-controller-manager`/`scale`, puis `helm upgrade` repose `replicas: 1`.
  2. *L'HPA est voulu* : il entre **dans le chart**. Une valeur `autoscaling.enabled` rend l'HPA, et `spec.replicas` disparaît du Deployment ([extrait](fichiers/M17-E22/chart/charts/mediagenda/templates/deployment.extrait.yaml)). Attention : si `helm` est le seul propriétaire de `replicas`, l'appliquer sans le champ le **retire**, et le Deployment retombe à 1 réplica par défaut. On crée donc l'HPA **avant**, dans la même révision ou une révision précédente. Le contrôleur devient copropriétaire, et quand `helm` abandonne le champ, la valeur reste celle de l'HPA. C'est la démarche de la documentation Kubernetes (*Horizontal Pod Autoscaling*, migration).

*Prévention* : RB-171 ([exemple](fichiers/M17-E22/medisphere/docs/kubernetes/packaging/runbooks/RB-171-conflit-champs.md)). En RBAC, `medisphere:mediagenda-devs` n'a que la lecture sur `mediagenda-dev` (Lucas n'aurait pas pu « regarder » avec `edit`).

---

### M17-E23 — Sous le capot : où Helm range-t-il ses releases ?

**Solution**

*1.* `type: helm.sh/release.v1`, un Secret par révision `sh.helm.release.v1.<release>.v<N>`. Étiquettes `name`, `owner=helm`, `status`, `version`, et `modifiedAt` (horodatage Unix, ajouté par les versions récentes). `helm list` et `helm history` cherchent par **sélecteur d'étiquettes** (`owner=helm,name=…`). C'est pourquoi `helm list -l` ne marche qu'avec les pilotes `secret` et `configmap` (aide de `helm list`).

*2. Décodage.*

```
admin@adm01:~$ kubectl get secret sh.helm.release.v1.capot.v3 -n wb-essais -o jsonpath='{.data.release}' \
    | base64 -d | base64 -d | gzip -dc | jq 'keys'
["apply_method","chart","config","hooks","info","manifest","name","namespace","version"]
```

Deux base64 : celui de l'API (tout `data` d'un Secret) et celui de Helm, qui encode le flux gzip. Avec le pilote `configmap`, un seul (le texte n'est pas réencodé par l'API). Les clés :

| Clé | Contenu |
|---|---|
| `info` | `status`, `first_deployed`, `last_deployed`, `description`, `notes` (NOTES.txt rendu) |
| `chart` | le chart **complet** : `metadata` (Chart.yaml), `templates` (gabarits en base64), `values` (défauts), `schema`, `files`, `lock` |
| `config` | les valeurs **fournies** (`-f`, `--set`) ; absente si aucune |
| `manifest` | le rendu appliqué (objets ordinaires) |
| `hooks` | chaque hook, son rendu, ses événements, `last_run` (`started_at`, `completed_at`, `phase`) |
| `apply_method` | `ssa` (Helm 4) ou `csa` |
| `version`, `name`, `namespace` | numéro de révision, release, espace |

*3. Taille.* `jq 'to_entries | map({cle: .key, octets: (.value | tojson | length)})'` : `chart` représente l'essentiel (gabarits, `values.yaml` et sous-charts embarqués). Un Secret, comme tout objet, est limité à **1 Mio** (limite de l'API Kubernetes, sous la limite de requête d'etcd). Avec 2 Mo de gabarits (déjà compressés), l'écriture de la release échoue. Les parades :
- alléger le chart (`.helmignore`, sous-charts inutiles) ;
- découper le chart ;
- changer de pilote (`sql`).

`--history-max` (défaut **10** pour `upgrade`, 0 = illimité) limite le nombre de Secrets gardés.

*4. Une montée vue des Secrets.*

```
sh.helm.release.v1.capot.v4   pending-upgrade   4
sh.helm.release.v1.capot.v3   superseded        3
sh.helm.release.v1.capot.v4   deployed          4
```

Ordre réel : écriture de la nouvelle révision en `pending-upgrade` ; hooks `pre-upgrade` ; application ; suppression des objets présents dans l'ancien manifeste et absents du nouveau (ici le PDB) ; attente ; hooks `post-upgrade` ; ancienne révision `superseded` ; nouvelle `deployed`. L'annotation `helm.sh/resource-policy: keep` fait garder l'objet (et le laisse orphelin de toute release).

*5. Pilote `configmap`.* `HELM_DRIVER=configmap helm install capot-cm …` : des ConfigMaps `sh.helm.release.v1.capot-cm.v*`. `helm list` **sans** la variable ne les voit pas : chaque pilote a son propre stockage, et deux personnes qui n'ont pas le même `HELM_DRIVER` croient à deux états différents. Lecture : quiconque lit les ConfigMaps de l'espace lit les valeurs, y compris `wb-checks` et souvent des équipes applicatives. À Sophie : jamais pour une release qui aurait la moindre valeur sensible. C'est-à-dire jamais chez MédiSphère, où la règle reste de n'avoir aucun secret en valeur.

*6. Pilote `sql`.* Les releases vont dans une base PostgreSQL (chaîne de connexion par variable d'environnement, voir *Helm Storage Backends*). Il est justifié pour des releases trop grosses pour 1 Mio, ou pour un audit centralisé de l'historique. Mais Helm dépend alors d'une base **hors du cluster**, qui doit être disponible, sauvegardée et accessible à tous ceux qui exécutent Helm. Les sauvegardes Velero ou etcd du cluster ne contiennent plus l'état des releases. Non retenu.

*7.* Outil : [`outils/helm-release.sh`](fichiers/M17-E23/k8s/outils/helm-release.sh). Il donne statut, dates, chart, méthode, objets, hooks et **noms** des clés de valeurs. Il fonctionne avec les deux pilotes et a été testé.

*8. Kustomize.* Il ne garde aucun état : `kubectl apply` ne sait pas ce qui a disparu d'un overlay. `kubectl apply --prune -l <sélecteur>` supprime les objets portant l'étiquette et absents du rendu. C'est dangereux avec un sélecteur trop large. Les *ApplySets* (`--applyset`, encore alpha, `KUBECTL_APPLYSET=true`) rangent la liste des objets dans un objet parent. Argo CD (M20) garde cette liste dans son application et propose le nettoyage (*prune*) en clair.

**Pièges classiques** : afficher `config` dans un ticket ; supprimer « les vieux Secrets » à la main au lieu de `--history-max` ; mélanger des `HELM_DRIVER` différents entre personnes ou CI.

---

### M17-E24 — Questions expert : packaging

1. **SSA et Helm 3.** Avec `--server-side=auto` (défaut d'`upgrade` et de `rollback`), Helm reprend la méthode de la révision précédente. Une release née sous Helm 3 reste en client-side (*3-way merge*). Ce défaut évite de basculer d'un coup des milliers de releases existantes, avec les conflits que ferait apparaître une prise de propriété brutale. Forcer `--server-side=true` sur une release en client-side transfère la propriété des champs à `helm` en SSA. Les champs que d'autres gestionnaires ont modifiés depuis (y compris les entrées `kubectl-client-side-apply` ou `before-first-apply`) produisent des conflits, qu'il faut lire avant de les forcer. On le fait volontairement, release par release, de préférence sur un objet sans dérive (`helm diff --three-way-merge` vide).
2. **`--rollback-on-failure` sans `--wait`.** Helm 4 active alors l'attente `watcher` (aide de `helm upgrade`), jusqu'à `--timeout` (5 min par défaut). Le défaut sans option est `hookOnly` : seuls les hooks sont attendus. Helm 3 n'attendait rien par défaut, et `--wait` y était fondé sur des règles maison. Helm 4 s'appuie sur **kstatus**, la même définition de « prêt » que kubectl et les outils GitOps, qui couvre aussi les ressources personnalisées qui exposent des conditions standard. `watcher` veut dire qu'on observe les objets par *watch* plutôt que par interrogation périodique.
3. **Hook `pre-upgrade` en échec.** La révision passe `failed`. Les objets ordinaires ne sont **pas** appliqués : l'ancienne version continue de tourner (M17-E12). Le schéma est dans l'état où la migration s'est arrêtée. Avec une migration transactionnelle par fichier, comme MédiAgenda, les fichiers précédents sont appliqués et celui en échec est annulé. Avec `hook-succeeded` seul, le Job en échec **reste** : on peut lire ses journaux. Au prochain upgrade, la création du Job échoue (`already exists`) si la politique ne contient pas `before-hook-creation`. C'est pourquoi on combine `before-hook-creation` (et `hook-succeeded` si l'on ne veut pas garder les réussites).
4. **`lookup` vide.** Sous `helm template`, `--dry-run` client et `kubectl kustomize --enable-helm`, Helm n'a pas de connexion au cluster : `lookup` renvoie un dictionnaire vide. Sans danger : un défaut qu'on ne remplace que s'il existe déjà, par exemple réutiliser une annotation existante, sans conséquence si elle manque. Piège : générer un mot de passe « sauf s'il existe déjà ». Chaque rendu sans cluster en génère un nouveau, et le Secret change à chaque livraison, avec des applications qui perdent leur accès. Même chose si les droits de Helm ne permettent pas de lire l'objet.
5. **Version dans le sélecteur.** `spec.selector` est **immuable** : la montée suivante échoue (`field is immutable`). Sortie sans interruption :
   - créer un **nouveau** Deployment (autre nom) avec le bon sélecteur, à côté de l'ancien ;
   - faire désigner les deux par le Service, par une étiquette commune (`app.kubernetes.io/name`) ;
   - attendre que le nouveau soit prêt, puis supprimer l'ancien.

   Ou bien : `kubectl delete deploy --cascade=orphan` (les pods restent et servent), puis recréer le Deployment avec le sélecteur correct, qui adopte les pods compatibles ou en crée de nouveaux. Le PDB et le Service doivent couvrir les deux générations. La règle : rien de variable dans un sélecteur (helper `selectorLabels`, M17-E05).
6. **Ordre Kustomize.** Ressources accumulées, puis components dans l'ordre de la liste (`dependances`, puis `haute-disponibilite`, puis `livraison`), puis transformateurs de l'overlay : `images`, `replicas`, `patches`, `labels`, `replacements`… Un `replicas:` de l'overlay gagne sur celui du component, parce qu'il passe après : le component a transformé les ressources accumulées, puis l'overlay retransforme le résultat. C'est la même raison qui fait gagner l'`images:` égaré de M17-E21 sur `livraison`.
7. **Suffixe d'empreinte.** Le nom change quand le contenu change. Le Deployment qui la référence change donc aussi, ce qui déclenche un déploiement progressif et rend un retour arrière (ancienne ConfigMap toujours présente) cohérent. Avec `disableNameSuffixHash`, la ConfigMap est modifiée **sur place**. Les pods ne redémarrent pas : la variable d'environnement ne change qu'au prochain redémarrage, et des pods de la même version ont des configurations différentes. Le retour arrière ne ramène plus l'ancienne configuration. Restent à nettoyer les anciennes ConfigMaps suffixées : `kubectl apply` ne les supprime pas (pas d'état, E23). Ce sont `--prune`/ApplySet, ou Argo CD (M20) avec *prune*.
8. **Provenance Helm et Cosign.**
   - La provenance Helm (`helm package --sign`) produit un fichier `.prov` : empreinte du paquet signée en PGP. `helm install --verify` la contrôle avec un trousseau PGP. Pour l'OCI, le fichier `.prov` voyage comme couche de l'artefact : peu d'outils le gèrent, et la gestion des clés PGP est lourde.
   - Cosign signe le **digest** de l'artefact OCI, stocke la signature comme référent OCI dans Harbor, et se vérifie avec la clé MédiSphère.
   - Dans la chaîne : le pipeline signe et vérifie ; `outils/rendre-base.sh` vérifie avant rendu (M17-E09) ; Argo CD sait vérifier des signatures de commits, mais pas nativement celles de charts OCI par Cosign (à étudier au M20) ; Kyverno `verifyImages` vérifie les **images** à l'admission (M26), pas le chart.

   Chacune prouve qu'un détenteur de la clé a signé ce contenu. Aucune ne prouve que le contenu est bon.
9. **`version: 0.7.0` dans `helmCharts`.** Rien ne garantit le contenu, sauf l'immuabilité des étiquettes du projet Harbor `charts` (M13) : une étiquette OCI est un pointeur. Plus fort : épingler le **digest** et vérifier la signature avant rendu. C'est le choix de `chart.env` (`CHART_VERSION` + `CHART_DIGEST`, `rendre-base.sh`), avec un rendu commité, lisible en MR. Le prix :
   - une étape de plus à chaque montée (relancer le script, relire un gros diff) ;
   - un rendu commité qui peut diverger du chart si on l'édite à la main, ce que le job `--verifier` interdit.
10. **Helmfile, `needs` et sélecteurs.**
    - `needs` ordonne : les dépendances s'appliquent avant, et sont supprimées après.
    - Avec `-l name=X`, Helmfile n'applique que X et **ignore** `needs` (`--skip-needs` vrai par défaut). `--include-needs` ajoute les dépendances directes de X, `--include-transitive-needs` toutes.
    - Les dépendants de X ne sont jamais ajoutés.

    Par défaut, un sélecteur veut dire « exactement ce périmètre ». Appliquer en douce des releases que l'opérateur n'a pas désignées serait plus dangereux qu'un ordre non respecté sur un composant déjà en place.
11. **CRD.** Helm installe le dossier `crds/` à la première installation et ne le met **jamais** à jour ni ne le supprime : une CRD supprimée emporte toutes les ressources de ce type dans tout le cluster, et une montée de CRD peut casser d'autres consommateurs. cert-manager rend ses CRD comme gabarits ordinaires (`crds.enabled`), donc mises à jour à chaque upgrade, et les protège par `crds.keep` (`helm.sh/resource-policy: keep`). Risques :
    - suppression par `helm uninstall` sans `keep` (toutes les données cert-manager perdues) ;
    - champ retiré d'une CRD encore utilisé ;
    - version de stockage changée sans migration ;
    - deux releases qui se disputent la même CRD.
12. **Secret de release de 900 Kio.** Le chart complet est embarqué dans chaque révision : gabarits, sous-charts, gros `values.yaml`, fichiers (`.Files`, tableaux de bord JSON…), plus le manifeste rendu. La limite est **1 Mio** par objet. Les trois sorties :
    - réduire le chart (`.helmignore`, sortir les gros fichiers en ConfigMaps gérées ailleurs, retirer les sous-charts inutiles) ;
    - découper en plusieurs charts ou releases ;
    - pilote `sql`.

    `--history-max` ne change rien à la taille d'**une** révision.
13. **Post-renderer en Helm 4.** Ce sont désormais des **greffons** de type post-renderer : `--post-renderer` prend le nom d'un greffon, plus un exécutable quelconque. Avantages par rapport au montage retenu : on garde la release Helm (hooks ordonnés, `rollback`, `helm history`) tout en patchant par Kustomize. Inconvénients :
    - deux outils dans une seule commande, difficiles à déboguer ;
    - un rendu final invisible en MR (sauf `helm diff` avec le greffon) ;
    - l'état reste dans des Secrets ;
    - Argo CD ne sait pas exécuter ce couple tel quel ;
    - il faut installer et épingler le greffon partout.
14. **« Ce qui tournait le 3 mars à 14 h ».**
    - Release Helm : `helm history` donne les dates des révisions. La révision active à 14 h se décode (`manifest`). Mais l'historique est tronqué à 10 révisions (`historyMax`), modifiable par quiconque a les droits, et ignore toute dérive manuelle.
    - Overlay : `git log` de `mediagenda/deploiement` donne la version de `main` à cette heure. Rien ne prouve qu'elle était **appliquée** : appliquée quand, par qui, et sans branche locale comme en M17-E21.

    Il manque un enregistrement fiable de ce qui a été appliqué : journal d'audit de l'API Kubernetes (M14-E27, à conserver et centraliser, M22), historique de synchronisation d'Argo CD (M20) relié aux commits, et images signées vérifiées à l'admission (M26). Le **digest** d'image de chaque pod (`status.containerStatuses[].imageID`) est la preuve la plus directe, à conserver par la supervision (M21/M22).
