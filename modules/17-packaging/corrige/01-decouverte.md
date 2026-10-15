# Module 17 — Palier 1 : Découverte — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Les fichiers.** Les solutions complètes sont dans [`fichiers/`](fichiers/), un dossier par exercice, sous la forme d'**extraits des projets** : `fichiers/M17-EXX/chart/…` = chemins du projet `mediagenda/chart`, `…/deploiement/…` = `mediagenda/deploiement`, `…/k8s/…` = `plateforme/k8s`. Deux états du chart sont fournis :
- [`M17-E03/chart/`](fichiers/M17-E03/chart/) : le chart 0.1.0 du premier ticket, complet ;
- [`M17-E12/chart/`](fichiers/M17-E12/chart/) : le projet `mediagenda/chart` **complet à la fin du palier 2** (chart 0.5.0, bibliothèque, tests, `ct.yaml`). Les corrigés de E05, E06, E07 et E12 citent les fichiers de cet état final : chaque exercice y a ajouté sa part, signalée dans les commentaires des fichiers. C'est aussi le chart sur lequel s'appuient les paliers 3 et 4.

**Ce qui a été vérifié, et comment.** Helm **4.3.0** (binaire officiel, somme contrôlée), Kustomize **5.8.2** et kubectl **1.36.5** (Kustomize 5.8.1 embarqué), helm-unittest **1.2.1** (installé avec `--verify=false`), helm-diff 3.15.15, Helmfile **1.8.1**, chart-testing **3.15.0** (image `quay.io/helmpack/chart-testing:v3.15.0`), kubeconform 0.8 avec les schémas Kubernetes 1.36 et le catalogue de CRD (CNPG `Cluster`, `HTTPRoute`, `CiliumNetworkPolicy`) :
- les deux charts passent `helm lint --strict` ; leurs rendus (dev, recette, prod) passent kubeconform sans erreur ; les règles du schéma et des `fail` ont été déclenchées une à une (messages cités ci-dessous, copiés de Helm 4.3) ;
- les 35 tests helm-unittest de l'état final passent ; `ct lint` passe (avec le Helm 3.16 de l'image **et** avec Helm 4.3 monté dans l'image) et refuse une modification sans montée de version ;
- tous les overlays Kustomize ont été construits et leurs sorties validées par kubeconform ;
- les sorties d'aide citées (`helm install|upgrade|uninstall|pull --help`) sont celles de Helm 4.3.0.

**Non rejoué sur un cluster** (aucun cluster n'était disponible pendant la rédaction) : installation réelle des charts, ordre exact des événements des hooks, comportement de la Gateway et des politiques Cilium avec ces objets, reprise de la recette, comportement du cache Harbor pour les artefacts Helm. Ces points sont signalés « ⚠️ À vérifier sur ton lab » : tes retours les corrigeront.

---

### M17-E01 — Questions : manifestes, gabarits et overlays

1. **Trois copies.** (a) *Dérive* : une correction (limite mémoire, sonde) faite dans une copie n'arrive pas dans les autres ; Kustomize la résout (la base est unique, les overlays ne portent que les différences), Helm aussi (un gabarit, des valeurs). (b) *Valeurs en dur répétées* (nom publié à quatre endroits, version de l'image) : Helm la résout par une valeur unique réutilisée ; Kustomize par `images`, `replacements` (E09). (c) *Pas de version de l'ensemble* : impossible de dire « recette tourne la livraison 0.4.0 » ; seul Helm apporte un paquet versionné et un historique de releases ; Kustomize se contente de la version Git du dépôt de déploiement. On peut ajouter : pas de validation avant application (le schéma de Helm), pas de retour arrière en une commande (`helm rollback`).
2. **Release, révision.** Une *release* est une installation nommée d'un chart dans un espace (`mediagenda` dans `mediagenda-dev`). Chaque `install`, `upgrade` ou `rollback` crée une *révision* numérotée, qui contient le chart, les valeurs, le manifeste rendu et le statut. Par défaut Helm range chaque révision dans un **Secret** `sh.helm.release.v1.<release>.v<N>` (type `helm.sh/release.v1`) de l'espace de la release. Conséquence : sans droit de lecture des Secrets, `helm list`, `helm history` et `helm upgrade` échouent. C'est le cas du compte `wb-checks` : les vérifications du module lisent donc les annotations `meta.helm.sh/release-name` et `meta.helm.sh/release-namespace` que Helm pose sur chaque objet, et non l'historique.
3. **`template` contre `install --dry-run=server`.** `helm template` rend **sans cluster** : `.Capabilities` vient de valeurs par défaut (ou de `--kube-version`, `--api-versions`), `lookup` renvoie un dictionnaire vide, rien n'est validé par l'API, et les tests sont inclus sauf `--skip-tests`. `--dry-run=server` contacte l'API : `lookup` voit les vrais objets, les manifestes passent la validation du serveur (schémas OpenAPI, admission), les conflits avec des objets existants apparaissent. Dans un pipeline sans accès au cluster : `helm template` (ou `helm lint`), et `--dry-run=client` est un équivalent qui ne contacte pas l'API.
4. **Réponse c.** `helm upgrade --help` (4.3) : `--server-side string must be "true", "false" or "auto" … ("auto" defaults the value from the previous chart release's method) (default "auto")`. Une release créée par Helm 3 (ou par la CLI `cilium`, qui embarque le SDK Helm) reste en *client-side apply* tant qu'on ne force pas `--server-side=true`. (b) est vrai pour `helm install` seulement (`--server-side … (default true)`). (a) n'est vrai que par conséquence de (c). (d) est faux : Helm n'appelle pas kubectl, il parle directement à l'API par client-go.
5. **Kustomize.** Mieux que Helm : décliner un manifeste existant **sans** le réécrire en gabarit — par exemple ajouter à la recette une limite mémoire par un patch de six lignes, lisible en MR, sans toucher au chart. Hors de sa portée sans aide : tout ce qui demande une **logique** (rendre la base CloudNativePG seulement si on le demande, calculer un nom, valider des valeurs), un **cycle de vie** (hooks de migration avant la mise à jour, historique et retour arrière), ou une **distribution** versionnée à des tiers.
6. **Suffixe d'empreinte.** Le nom de la ConfigMap générée inclut une empreinte de son contenu ; les références (`envFrom`, volumes) sont réécrites avec ce nom. Changer le contenu change le nom, donc le gabarit de pod, donc déclenche une mise à jour progressive — alors qu'une ConfigMap modifiée en place ne redémarre aucun pod (et un `rollout undo` reviendrait au même nom… mais pas à l'ancien contenu). Inconvénient : les anciennes ConfigMap restent dans le cluster tant qu'on ne les supprime pas (`--prune`, ou un outil GitOps), et l'empreinte rend les noms imprévisibles pour qui les cherche à la main.
7. **Version et sélecteur.** `spec.selector` d'un Deployment est **immuable** après création. Avec la version dans le sélecteur, chaque montée de version voudrait changer le sélecteur : l'API refuse (`field is immutable`), et Helm ne peut s'en sortir qu'en remplaçant l'objet (coupure). Sur le pod, l'étiquette est utile (tableaux de bord, `kubectl get pods -L app.kubernetes.io/version`) et sans danger. Règle : sélecteur = `name` + `instance` (+ un composant fixe), jamais une valeur qui change.
8. **Helmfile.** Au script, il ajoute la **déclaration** (toutes les releases, versions et valeurs dans un fichier relu), le **diff** avant d'agir, l'idempotence (seules les releases qui diffèrent sont touchées), les environnements, les sélecteurs (`-l groupe=stockage`) et l'ordre (`needs`). Par rapport à Argo CD : pas de **boucle de réconciliation** (rien ne détecte ni ne corrige une dérive tant qu'un humain ne relance pas `helmfile diff`), pas d'interface ni d'historique de synchronisation, pas de contrôle d'accès propre (il agit avec les droits de qui le lance).
9. **Étiquette réécrite.** Une étiquette OCI est un pointeur mobile ; le **digest** (`sha256:…` du manifeste) désigne un contenu unique. Le consommateur s'en aperçoit s'il a noté le digest (Helm 4 l'affiche à chaque `pull`/`install` : `Digest: sha256:…`) et le compare, ou si la signature Cosign qu'il vérifie porte sur l'ancien digest. Protections : règle d'**immuabilité** des étiquettes dans le projet Harbor `charts` (comme `v*` dans `medisphere` au M13), consommation **par digest** (Helm 4 l'accepte), vérification Cosign du digest avant usage (E08, E09).
10. **Faux.** `--atomic` existe encore en Helm 4.3, mais il est **déprécié** : `helm upgrade --atomic …` affiche `Flag --atomic has been deprecated, use --rollback-on-failure instead`. Il fait la même chose (retour arrière si l'opération échoue, et `--wait` passe en stratégie `watcher`). Il disparaîtra dans une version majeure suivante : les scripts de MédiSphère utilisent `--rollback-on-failure`. Même chose pour `--force` → `--force-replace`.

---

### M17-E02 — Helm 4 : installer, inspecter, monter, revenir

**Solution**

Commandes complètes, avec la référence par le cache Harbor (`C=oci://registry.par1.medisphere.internal/ghcr/stefanprodan/charts/podinfo`) :

```
admin@adm01:~$ mkdir -p ~/m17/e02 && cd ~/m17/e02
admin@adm01:~/m17/e02$ C=oci://registry.par1.medisphere.internal/ghcr/stefanprodan/charts/podinfo
admin@adm01:~/m17/e02$ helm show chart $C --version 6.14.0
Pulled: registry.par1.medisphere.internal/ghcr/stefanprodan/charts/podinfo:6.14.0
Digest: sha256:476bed61733536f99e7331b0fe4cc9fd70bc6497a855ad38ba49b72de50c1132
apiVersion: v1
…
admin@adm01:~/m17/e02$ helm show values $C --version 6.14.0 | less
```

La ligne `Digest:` est le digest du **manifeste OCI** de l'artefact (celui que l'on signe, que l'on épingle, que Harbor affiche). Celui ci-dessus est celui de `ghcr.io` au moment de la rédaction ; le cache Harbor sert le même digest (il relaie l'artefact sans le modifier). Note que `podinfo` est un chart `apiVersion: v1` (format Helm 2) : Helm 4 le lit toujours.

[`valeurs.yaml`](fichiers/M17-E02/valeurs.yaml) :

```yaml
replicaCount: 2
ui:
  message: "Essai Helm 4 — équipe Plateforme"
resources:
  requests:
    cpu: 10m
    memory: 32Mi
  limits:
    memory: 64Mi
```

Rendu local, installation et lecture :

```
admin@adm01:~/m17/e02$ helm template podinfo $C --version 6.14.0 -f valeurs.yaml -n wb-essais | grep -E '^kind:|helm.sh/hook:'
kind: Service
kind: Deployment
kind: Pod
    "helm.sh/hook": test-success
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
…
admin@adm01:~/m17/e02$ helm install podinfo $C --version 6.14.0 -f valeurs.yaml -n wb-essais --wait --timeout 5m
admin@adm01:~/m17/e02$ helm list -n wb-essais
NAME    NAMESPACE  REVISION  UPDATED   STATUS    CHART           APP VERSION
podinfo wb-essais  1         …         deployed  podinfo-6.14.0  6.14.0
admin@adm01:~/m17/e02$ helm get values podinfo -n wb-essais          # « USER-SUPPLIED VALUES » : ton fichier
admin@adm01:~/m17/e02$ helm get values podinfo -n wb-essais --all    # « COMPUTED VALUES » : défauts du chart + tes valeurs
admin@adm01:~/m17/e02$ helm get manifest podinfo -n wb-essais | less
admin@adm01:~/m17/e02$ helm get notes podinfo -n wb-essais
admin@adm01:~/m17/e02$ helm get hooks podinfo -n wb-essais | grep -E '^kind|hook'
admin@adm01:~/m17/e02$ helm test podinfo -n wb-essais --logs
```

`--wait` seul vaut `--wait=watcher` (Helm 4 : attente fondée sur *kstatus*, qui sait lire l'état de la plupart des objets, y compris des ressources personnalisées qui exposent des conditions standard). Sans `--wait`, le défaut est `hookOnly` : Helm n'attend que les hooks.

*Server-side apply* :

```
admin@adm01:~/m17/e02$ kubectl -n wb-essais get deploy podinfo -o yaml --show-managed-fields | sed -n '/managedFields:/,/^  name:/p' > managed-fields.txt
admin@adm01:~/m17/e02$ grep -E 'manager|operation' managed-fields.txt
  - manager: helm
    operation: Apply
  - manager: kube-controller-manager
    operation: Update
```

La release a été créée par Helm 4 : opération `Apply` (server-side), gestionnaire `helm`. Le contrôleur de Deployment possède les champs de `status` (opération `Update`, sous-ressource `status`).

Montées et valeurs :

```
admin@adm01:~/m17/e02$ helm upgrade podinfo $C --version 6.15.0 -n wb-essais --wait
admin@adm01:~/m17/e02$ helm get values podinfo -n wb-essais            # null : tes valeurs ont disparu (1 réplica, plus de message)
admin@adm01:~/m17/e02$ helm upgrade podinfo $C --version 6.15.0 -n wb-essais --wait -f valeurs.yaml   # on remet
admin@adm01:~/m17/e02$ helm upgrade podinfo $C --version 6.15.0 -n wb-essais --wait --reuse-values
admin@adm01:~/m17/e02$ helm upgrade podinfo $C --version 6.15.0 -n wb-essais --wait --reset-then-reuse-values
```

- Sans `-f` ni `--set` ni option de réutilisation : Helm **repart des défauts du chart** ; les valeurs de la révision précédente ne sont pas reprises. C'est la surprise la plus fréquente à l'astreinte.
- `--reuse-values` reprend les valeurs **calculées** de la révision précédente et y fusionne la ligne de commande : si le nouveau chart ajoute une valeur par défaut (une nouvelle clé utilisée par un nouveau gabarit), elle n'est pas prise en compte (les valeurs reprises ne la contiennent pas… et sont fusionnées par-dessus les défauts), d'où des rendus avec des clés vides, voire des erreurs `nil pointer`.
- `--reset-then-reuse-values` (depuis Helm 3.14) : part des **défauts du nouveau chart**, applique les valeurs **fournies** de la révision précédente, puis la ligne de commande. C'est ce qu'on veut presque toujours. La pratique MédiSphère est encore plus simple : **toujours** repasser les fichiers de valeurs versionnés (`-f`), jamais de réutilisation implicite. C'est ce que fera Helmfile en E10.

Retour arrière et échec :

```
admin@adm01:~/m17/e02$ helm history podinfo -n wb-essais
admin@adm01:~/m17/e02$ helm rollback podinfo 1 -n wb-essais --wait
admin@adm01:~/m17/e02$ helm history podinfo -n wb-essais
REVISION  UPDATED  STATUS      CHART           APP VERSION  DESCRIPTION
1         …        superseded  podinfo-6.14.0  6.14.0       Install complete
2         …        superseded  podinfo-6.15.0  6.15.0       Upgrade complete
…
6         …        deployed    podinfo-6.14.0  6.14.0       Rollback to 1
admin@adm01:~/m17/e02$ helm upgrade podinfo $C --version 6.15.0 -n wb-essais -f valeurs.yaml \
    --set image.tag=n-existe-pas --rollback-on-failure --timeout 90s
Error: UPGRADE FAILED: release podinfo failed, and has been rolled back due to rollback-on-failure being set: …
admin@adm01:~/m17/e02$ helm history podinfo -n wb-essais | tail -n 2
7         …        failed      podinfo-6.15.0  6.15.0       Upgrade "podinfo" failed: …
8         …        deployed    podinfo-6.14.0  6.14.0       Rollback to 6
admin@adm01:~/m17/e02$ helm upgrade podinfo $C --version 6.15.0 -n wb-essais -f valeurs.yaml --set image.tag=n-existe-pas --atomic --timeout 90s
Flag --atomic has been deprecated, use --rollback-on-failure instead
…
```

Le retour arrière crée une **nouvelle** révision (« Rollback to N ») : l'historique est un journal, jamais réécrit. `--rollback-on-failure` impose l'attente (`watcher`) : sans attente, Helm ne verrait pas que les pods ne démarrent pas, et ne saurait pas qu'il a échoué.

Désinstallation :

```
admin@adm01:~/m17/e02$ helm uninstall podinfo -n wb-essais --keep-history --wait
admin@adm01:~/m17/e02$ helm list -n wb-essais                 # vide
admin@adm01:~/m17/e02$ helm list -n wb-essais --uninstalled   # podinfo … uninstalled
admin@adm01:~/m17/e02$ helm history podinfo -n wb-essais > historique.txt; tail -n 1 historique.txt
10        …        uninstalled podinfo-6.14.0  6.14.0       Uninstallation complete
admin@adm01:~/m17/e02$ helm uninstall podinfo -n wb-essais    # sur une release déjà désinstallée : purge l'historique
admin@adm01:~/m17/e02$ kubectl -n wb-essais get all,secret -l 'app.kubernetes.io/name=podinfo' ; kubectl -n wb-essais get secret -l owner=helm,name=podinfo
```

Avec `--keep-history`, les objets sont supprimés mais les Secrets de révision restent (statut `uninstalled`) : `helm history` fonctionne, `helm rollback podinfo <N>` peut **réinstaller** une ancienne révision. Un second `helm uninstall` sans l'option purge l'historique (⚠️ à vérifier sur ton lab : le message diffère selon les versions). Les pods de test de `podinfo` portent `helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded` : ils disparaissent dès qu'ils ont réussi. Un pod de test **en échec** reste, lui : supprime-le à la main s'il en reste un.

Fiche d'astreinte : [`fiche-helm.md`](fichiers/M17-E02/medisphere/docs/kubernetes/packaging/fiche-helm.md).

**Explications**

- **Ce que Helm enregistre.** Une révision contient le chart complet (gabarits compris), les valeurs fournies, le manifeste rendu, les hooks, les notes et le statut. `helm get manifest` montre **ce que Helm croit avoir appliqué**, pas forcément ce qui tourne (quelqu'un a pu modifier l'objet après) : comparer les deux est l'objet de M17-E14.
- **Valeurs fournies et calculées.** `get values` sans `--all` donne ce qu'il faut repasser pour reproduire la release ; `--all` donne ce que les gabarits ont réellement lu. L'astreinte regarde les deux.
- **OCI.** Un chart OCI n'a pas d'index : on ne fait ni `helm repo add` ni `helm search repo` ; on vise une référence et une version, comme une image. Le cache Harbor `ghcr` relaie les artefacts OCI comme les images (⚠️ à vérifier sur ton lab pour les artefacts Helm : si le cache refuse, le message d'erreur vient de Harbor, et l'accès direct à `ghcr.io` reste possible depuis `adm01`).

**Alternatives**

- `helm install --generate-name` : à éviter, le nom de la release est la clé de tout le reste.
- `helm upgrade --install` : idempotent (installe si absent), c'est la forme des scripts et de Helmfile.
- `helm diff upgrade` (plugin) pour voir l'écart avant de monter : vu en E10 et E14.

**Pièges classiques**

- Oublier `-n` : la release est créée dans l'espace courant du contexte (souvent `default`), et `helm list` ne la montre plus depuis le bon espace.
- Monter sans `-f` : les valeurs disparaissent sans message.
- Croire qu'un `rollback` revient sur l'état de la base de données : il ne revient que sur les objets Kubernetes. Une migration de schéma n'est **pas** annulée (E12).
- Un `rollback` avec `--wait` sur une révision dont l'image n'existe plus échoue lui aussi.

**En production chez MédiSphère**

Les composants ne sont jamais montés à la main : Helmfile (E10), puis Argo CD (M20). La fiche d'astreinte sert à **lire** l'état ; l'action (rollback) passe par le runbook RB-170 (palier 4), qui commence par geler l'outil qui réconcilie, sinon il annule le rollback.

---

### M17-E03 — Écrire le chart `mediagenda`

**Solution**

Chart complet : [`fichiers/M17-E03/chart/charts/mediagenda/`](fichiers/M17-E03/chart/charts/mediagenda/) — [`Chart.yaml`](fichiers/M17-E03/chart/charts/mediagenda/Chart.yaml), [`values.yaml`](fichiers/M17-E03/chart/charts/mediagenda/values.yaml), [`_helpers.tpl`](fichiers/M17-E03/chart/charts/mediagenda/templates/_helpers.tpl), [`deployment.yaml`](fichiers/M17-E03/chart/charts/mediagenda/templates/deployment.yaml), `service.yaml`, `configmap.yaml`, `serviceaccount.yaml`, `httproute.yaml`, `networkpolicy.yaml`, `NOTES.txt`, `.helmignore`.

1. **Dépendances provisoires.**
   ```
   admin@adm01:~$ kubectl apply --server-side -f ~/DevOpsPrivateCloud/modules/17-packaging/ressources/E03-dependances-dev.yaml
   admin@adm01:~$ kubectl -n mediagenda-dev wait cluster.postgresql.cnpg.io/mediagenda-db --for=condition=Ready --timeout=10m
   admin@adm01:~$ kubectl -n mediagenda-dev get secret mediagenda-db-app -o jsonpath='{.data}' | jq 'keys'
   [ "dbname", "host", "jdbc-uri", "password", "pgpass", "port", "uri", "user", "username" ]
   ```
   (liste à vérifier sur ta version de CNPG ; seule `uri` compte ici.)
2. **Projet.** Création dans GitLab (groupe `mediagenda`, projet `chart`, protection de `main`, fusion par MR ; reprends les réglages de `mediagenda/api`), puis :
   ```
   admin@adm01:~/src$ git clone git@git01.par1.medisphere.internal:mediagenda/chart.git mediagenda-chart && cd mediagenda-chart
   admin@adm01:~/src/mediagenda-chart$ mkdir charts && helm create charts/mediagenda
   ```
   `helm create` produit un Deployment générique, Service, Ingress, HPA, ServiceAccount, `tests/test-connection.yaml` (image `busybox`) et un `_helpers.tpl`. On garde la structure et les idées des helpers ; on retire l'Ingress (pas d'ingress-nginx chez nous, la Gateway API le remplace), l'HPA (pas de métriques applicatives avant le M21), le test `busybox` (image hors registre MédiSphère, refusée par la VAP du M14 ; un test propre arrive en E07).
3. **`Chart.yaml`.** `version` = version **du chart** (SemVer, change à chaque modification du chart) ; `appVersion` = version **de l'application** livrée par défaut (information, et ici source de l'étiquette d'image). `kubeVersion: ">=1.35.0-0"` (le suffixe `-0` accepte les versions de pré-publication que certains distributeurs annoncent, comme `v1.36.5-rc.0`, et ce que kubeadm rapporte parfois).
4. **Helpers et gabarits.** Points de solution :
   - nom complet : la release `mediagenda` du chart `mediagenda` donne `mediagenda` (fonction `contains`), tronqué à 63 caractères (`trunc 63 | trimSuffix "-"`), longueur maximale d'un nom DNS-1123 d'étiquette ;
   - sélection : `app.kubernetes.io/name`, `app.kubernetes.io/instance` **et** `app.kubernetes.io/component: api` posé dès la 0.1.0 dans le Deployment et le Service : le sélecteur est immuable, et d'autres pods de la release viendront (migrations en E12, tests en E07) qu'il ne faut pas confondre avec l'API ;
   - empreinte de la ConfigMap dans une annotation du **gabarit de pod** :
     ```yaml
     checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
     ```
   - `terminationGracePeriodSeconds: {{ add .Values.config.delaiArret 10 }}` : uvicorn termine ses requêtes en `MEDIAGENDA_DELAI_ARRET` secondes après SIGTERM ; au-delà du délai de grâce, kubelet envoie SIGKILL ;
   - Pod Security `restricted` : `runAsNonRoot` et `seccompProfile: RuntimeDefault` au niveau du pod, `allowPrivilegeEscalation: false` et `capabilities.drop: [ALL]` au niveau du conteneur ; `readOnlyRootFilesystem: true` + `emptyDir` sur `/tmp` (Python écrit des fichiers temporaires).
5. **NOTES.txt** : rendu par Helm à la fin de `install`/`upgrade` (et `helm get notes`).
6. **Contrôles.**
   ```
   admin@adm01:~/src/mediagenda-chart$ helm lint --strict charts/mediagenda
   ==> Linting charts/mediagenda
   [INFO] Chart.yaml: icon is recommended
   1 chart(s) linted, 0 chart(s) failed
   admin@adm01:~/src/mediagenda-chart$ helm template mediagenda charts/mediagenda -n mediagenda-dev | less
   admin@adm01:~/src/mediagenda-chart$ helm install mediagenda charts/mediagenda -n mediagenda-dev --dry-run=server
   ```
   `--dry-run=server` envoie les objets au serveur **sans les enregistrer** : validation par les schémas OpenAPI (y compris des CRD : `HTTPRoute`, `CiliumNetworkPolicy`), passage par l'**admission** (Pod Security, ValidatingAdmissionPolicy du M14-E18, quotas), et détection d'objets existants qui n'appartiennent pas à la release.
7. **Installation.**
   ```
   admin@adm01:~/src/mediagenda-chart$ helm install mediagenda charts/mediagenda -n mediagenda-dev --wait --timeout 5m
   admin@adm01:~/src/mediagenda-chart$ kubectl -n mediagenda-dev get httproute mediagenda -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
   Accepted=True Accepted
   ResolvedRefs=True ResolvedRefs
   admin@adm01:~/src/mediagenda-chart$ curl -fsS https://mediagenda-dev.apps.par1.medisphere.internal/sante
   {"statut":"ok","version":"v1.0.0"}
   ```
8. **Valeurs.** `helm upgrade mediagenda charts/mediagenda -n mediagenda-dev --reuse-values --set config.cacheTtl=30` : l'empreinte change, nouveau ReplicaSet. Avec `--set cacheTTL=30` : rien ne change, aucun message — Helm accepte toute clé inconnue tant que rien ne la lit. C'est le problème de E05.

**Explications**

- **Objets intégrés.** `.Release` (nom, espace, révision, `IsInstall`/`IsUpgrade`, `Service` = « Helm »), `.Chart` (le contenu de `Chart.yaml`), `.Values` (fusion des valeurs), `.Template` (`BasePath`, `Name`), `.Capabilities` (versions d'API du cluster), `.Files` (fichiers du chart).
- **`include` plutôt que `template`.** `template` écrit directement dans la sortie ; `include` renvoie une chaîne qu'on peut passer à `nindent`, `quote`, `sha256sum`. D'où la règle : toujours `include … | nindent N` pour un bloc YAML, et `{{-` pour avaler le retour à la ligne précédent.
- **Politiques réseau dans le chart.** L'espace est en refus par défaut (M15) : sans elles, l'API ne joint ni le DNS, ni la base, ni Valkey, et la Gateway ne la joint pas. Le trafic de la Gateway Cilium vient de l'Envoy de Cilium, avec l'identité réservée `ingress` : une NetworkPolicy standard ne sait pas l'exprimer, d'où la CiliumNetworkPolicy `fromEntities: [ingress]` (la même que celle du M15-E17).

**Alternatives**

- Partir du gabarit d'une bibliothèque publique (charts « communs » de type `bjw-s/common` ou les charts Bitnami) : beaucoup de fonctions, mais un code qu'on ne maîtrise pas ; MédiSphère écrit son petit chart de bibliothèque en E06.
- Mettre l'URL de Valkey dans un Secret plutôt qu'une ConfigMap : nécessaire dès que Valkey a un mot de passe (pas le cas au lab).

**Pièges classiques**

- Indentation : `toYaml .Values.resources | nindent 12` à la mauvaise colonne donne un YAML valide… sous la mauvaise clé. `helm template` puis lecture, toujours.
- `helm create` laisse un test `busybox` : refusé par la VAP (registre), `helm test` échoue.
- Nom publié qui ne correspond pas à l'écouteur (`*.apps.par1.medisphere.internal`) : `NoMatchingListenerHostname`.
- Oublier `sectionName: https` : la route s'accroche aussi à l'écouteur HTTP, qui ne fait que rediriger (M15), et contourne la redirection.

**En production chez MédiSphère**

Le chart vit dans son propre projet, avec ses propres versions : l'équipe de Julien le fait évoluer avec l'application, l'équipe Plateforme relit. Les valeurs propres à un environnement ne vont jamais dans `values.yaml` du chart : elles vont dans le dépôt de déploiement (E04, E09).

---

### M17-E04 — Kustomize : une base et des overlays

**Solution**

Projet complet : [`fichiers/M17-E04/deploiement/`](fichiers/M17-E04/deploiement/) — [`base/kustomization.yaml`](fichiers/M17-E04/deploiement/base/kustomization.yaml), [`base/mediagenda.yaml`](fichiers/M17-E04/deploiement/base/mediagenda.yaml) (rendu du chart 0.1.0), [`overlays/recette/`](fichiers/M17-E04/deploiement/overlays/recette/) (`kustomization.yaml`, `ressources.yaml`, `parametres.env`), [`overlays/dev/`](fichiers/M17-E04/deploiement/overlays/dev/kustomization.yaml), [`overlays/essai/`](fichiers/M17-E04/deploiement/overlays/essai/kustomization.yaml).

1. **Inventaire.**
   ```
   admin@adm01:~$ kubectl -n mediagenda-recette get deploy mediagenda -o jsonpath='{.spec.selector}{"\n"}'
   admin@adm01:~$ kubectl -n mediagenda-recette get deploy mediagenda -o yaml --show-managed-fields | grep -E 'manager:|operation:'
   ```
   Au M16, les objets ont été appliqués par `kubectl apply` (gestionnaire `kubectl-client-side-apply`, annotation `kubectl.kubernetes.io/last-applied-configuration`) ou `kubectl apply --server-side` (gestionnaire `kubectl`) : note ce que tu trouves.
2. **Base.**
   ```
   admin@adm01:~/src/mediagenda-deploiement$ helm template mediagenda ~/src/mediagenda-chart/charts/mediagenda > base/mediagenda.yaml
   admin@adm01:~/src/mediagenda-deploiement$ kustomize build base | diff - <(yq ea '.' base/mediagenda.yaml) && echo identique
   ```
   (au formatage près : Kustomize réordonne les objets et les clés.)
3. **Recette** — l'essentiel de [`overlays/recette/kustomization.yaml`](fichiers/M17-E04/deploiement/overlays/recette/kustomization.yaml) :
   ```yaml
   namespace: mediagenda-recette
   resources: [../../base]
   labels:
     - pairs: {medisphere.fr/environnement: recette}
       includeSelectors: false
       includeTemplates: true
   images:
     - name: registry.par1.medisphere.internal/medisphere/mediagenda-api
       newTag: v1.0.0
   replicas:
     - name: mediagenda
       count: 2
   configMapGenerator:
     - name: mediagenda-parametres
       envs: [parametres.env]
   patches:
     - path: ressources.yaml                       # stratégique
     - target: {kind: HTTPRoute, name: mediagenda}  # JSON 6902
       patch: |-
         - op: replace
           path: /spec/hostnames/0
           value: mediagenda-recette.apps.par1.medisphere.internal
     - target: {kind: Deployment, name: mediagenda}
       patch: |-
         - op: add
           path: /spec/template/spec/containers/0/envFrom/-
           value: {configMapRef: {name: mediagenda-parametres}}
   ```
   Résultat vérifié (`kustomize build overlays/recette`) : Deployment à deux réplicas, ressources de la recette, étiquette `recette` sur l'objet et le gabarit de pod mais pas dans `spec.selector`, `envFrom` = `[mediagenda, mediagenda-parametres-<empreinte>]`, route sur le bon nom.
4. **Dev.** `kustomize build overlays/dev` et `kubectl kustomize overlays/dev` donnent la même sortie sur ces fonctions ; `kustomize version` → v5.8.2, `kubectl version --client` → `Kustomize Version: v5.8.1`. Un écart de version mineure peut changer un comportement fin : la CI (M19) épingle **une** version.
5. **Reprise de la recette.**
   ```
   admin@adm01:~/src/mediagenda-deploiement$ kubectl get deploy mediagenda -n mediagenda-recette -o yaml > ~/m17/e04/ancien-deploy.yaml
   admin@adm01:~/src/mediagenda-deploiement$ kubectl diff --server-side -k overlays/recette
   admin@adm01:~/src/mediagenda-deploiement$ kubectl apply --server-side -k overlays/recette
   admin@adm01:~/src/mediagenda-deploiement$ kubectl -n mediagenda-recette rollout status deploy/mediagenda
   ```
   Si le sélecteur du M16 diffère (par exemple `app: mediagenda`) : l'`apply` échoue sur `spec.selector … field is immutable`. Après accord de Julien :
   ```
   admin@adm01:~/src/mediagenda-deploiement$ kubectl -n mediagenda-recette delete deploy mediagenda --wait
   admin@adm01:~/src/mediagenda-deploiement$ kubectl apply --server-side -k overlays/recette
   ```
   Retour arrière : `kubectl apply -f ~/m17/e04/ancien-deploy.yaml` (après avoir retiré `metadata.uid`, `resourceVersion` et `status`). Si l'`apply` signale un **conflit** (un champ possédé par `kubectl-client-side-apply`), c'est que le champ a été positionné autrement au M16 ; la migration de propriété *client-side* → *server-side* est gérée par kubectl pour les champs de la dernière configuration appliquée, les autres conflits se règlent par `--force-conflicts` **après** lecture (M17-E14 y revient). Enfin, nettoyage :
   ```
   admin@adm01:~$ kubectl -n mediagenda-recette get cm,netpol,ciliumnetworkpolicy,svc --show-labels
   ```
   Ne supprime que ce qui n'est plus référencé (par exemple une ancienne ConfigMap `mediagenda-config` et les politiques du M15-E17 désormais doublées par celles du chart — en vérifiant avec Hubble qu'aucun flux ne les utilise encore). Les politiques `default-deny`, celles de la base et de Valkey restent.
6. **`namePrefix`.** Dans `overlays/essai` : objets renommés `essai-mediagenda`, `essai-mediagenda-depuis-gateway` ; références mises à jour : `serviceAccountName`, `envFrom[].configMapRef` (les deux sont des références connues de Kustomize). Non modifiés : le Secret `mediagenda-db-app` (il n'est pas dans les ressources de l'overlay : Kustomize ne renomme que ce qu'il gère), les **sélecteurs** d'étiquettes (`podSelector`, `endpointSelector`, `selector` du Service) — un préfixe change des **noms**, pas des étiquettes. Observé avec Kustomize 5.8.2 : la référence `backendRefs` d'une `HTTPRoute` vers le Service **est** réécrite (Kustomize connaît désormais ce champ de la Gateway API) ; sur une version plus ancienne ou une ressource personnalisée inconnue, il faut déclarer la référence (`configurations:` et `nameReference`).
7. **Empreinte.** `MEDIAGENDA_CACHE_TTL=90` → nouveau nom `mediagenda-parametres-<autre empreinte>`, nouvelle révision du Deployment. L'ancienne ConfigMap reste dans le cluster (orpheline) : `kubectl apply` ne supprime rien. Elle permet d'ailleurs un `kubectl rollout undo` cohérent ; on fait le ménage périodiquement, ou on laisse Argo CD le faire (M20).

**Explications**

- **Stratégique ou JSON 6902 ?** Le patch stratégique (*strategic merge patch*) est un morceau de manifeste fusionné selon les règles de l'API (listes fusionnées par clé : conteneurs par `name`, ports par `containerPort`) : lisible, idéal pour « mettre ces ressources sur ce conteneur ». Le JSON 6902 est une liste d'opérations sur des chemins : précis, indispensable pour remplacer un élément de liste sans clé de fusion (`hostnames/0`), ajouter en fin de liste (`/-`) ou retirer un champ ; fragile si l'ordre de la liste change.
- **Ordre des sources d'environnement.** Dans `envFrom`, la **dernière** source l'emporte sur une clé en double ; et `env` l'emporte sur `envFrom`. D'où l'ajout en fin de liste.
- **Pourquoi `includeSelectors: false`.** Ajouter une étiquette au sélecteur d'un Deployment existant est un changement de champ immuable ; et un sélecteur de Service élargi peut capturer des pods qu'il ne devrait pas.

**Alternatives**

- `commonLabels` : déprécié au profit de `labels`, et il modifie les sélecteurs (justement ce qu'on évite).
- Reprendre la recette sans couper, même si le sélecteur diffère : déployer à côté sous un autre nom, basculer la route, supprimer l'ancien. Plus propre, plus long ; la coupure d'une recette annoncée est acceptée ici.

**Pièges classiques**

- `kubectl apply -k` d'un overlay dans le mauvais espace : le champ `namespace:` de l'overlay l'emporte sur `-n`. Lis `kubectl diff` avant.
- Patch stratégique sur une liste sans clé de fusion (par exemple `hostnames`) : la liste entière est **remplacée**.
- Oublier que `images` ne touche que les champs `image` des conteneurs connus de Kustomize : une image citée dans une variable d'environnement ou une CRD n'est pas changée.
- Supprimer le Deployment de la recette alors que l'overlay pointe vers un Secret qui n'existe pas : vérifier `kubectl get secret mediagenda-db-app` avant.

**En production chez MédiSphère**

Le dépôt `mediagenda/deploiement` devient la seule source de vérité des environnements applicatifs ; Argo CD l'appliquera (M20) et fera le ménage des objets orphelins. D'ici là, `kubectl diff` est obligatoire avant tout `apply`, et le résultat est collé dans la MR.

---

### M17-E05 — Valeurs, schéma de valeurs et helpers

**Solution**

Fichiers de l'état final (chart 0.5.0, qui contient tout le travail de E05) : [`values.yaml`](fichiers/M17-E12/chart/charts/mediagenda/values.yaml), [`values.schema.json`](fichiers/M17-E12/chart/charts/mediagenda/values.schema.json), [`_helpers.tpl`](fichiers/M17-E12/chart/charts/mediagenda/templates/_helpers.tpl), [`NOTES.txt`](fichiers/M17-E12/chart/charts/mediagenda/templates/NOTES.txt), [`configmap.yaml`](fichiers/M17-E12/chart/charts/mediagenda/templates/configmap.yaml) (`extraEnv` rendu par `tpl`). En 0.2.0, les étiquettes `medisphere.fr/*`, les contextes de sécurité et la référence d'image étaient dans `_helpers.tpl` ; E06 les déplace dans la bibliothèque `medisphere-commun` ([`_commun.tpl`](fichiers/M17-E12/chart/charts/medisphere-commun/templates/_commun.tpl)), à l'identique.

1. **Quand le schéma s'applique.** À `install`, `upgrade`, `lint` et `template` (et `--dry-run`), sur les **valeurs fusionnées** (défauts + fichiers + `--set`) ; le schéma d'un sous-chart s'applique à la partie des valeurs qui le concerne. `--skip-schema-validation` le désactive (option de `install`, `upgrade`, `template`, `lint`) : on ne s'en sert que pour diagnostiquer un schéma lui-même cassé, jamais dans un script.
2. et 3. **Schéma.** Les règles qui portent la solution :
   ```json
   "additionalProperties": false,                                  // racine : une faute de frappe est refusée
   "medisphere": { "required": ["equipe", "environnement"],
                   "properties": { "environnement": { "enum": ["dev", "recette", "prod"] } } },
   "image": { "properties": {
       "registry": { "const": "registry.par1.medisphere.internal" },
       "tag":    { "pattern": "^$|^v[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z.-]+)?$" },
       "digest": { "pattern": "^$|^sha256:[a-f0-9]{64}$" } } },
   "replicaCount": { "type": "integer", "minimum": 1, "maximum": 10 },
   "database": { "additionalProperties": false, "properties": {
       "url":      { "not": {} },
       "password": { "not": {} } } },
   "config": { "properties": { "extraEnv": { "propertyNames": { "pattern": "^MEDIAGENDA_[A-Z0-9_]+$" } } } }
   ```
   Messages obtenus avec Helm 4.3 (extraits) :
   ```
   $ helm template m charts/mediagenda --set medisphere.environnement=dev --set image.tag=latest
   - at '/image/tag': 'latest' does not match pattern '^$|^v[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z.-]+)?$'
   $ … --set replicaCount=deux
   - at '/replicaCount': got string, want integer
   $ … --set database.password=x
   - at '/database/password': 'not' failed
   $ … --set image.registry=docker.io
   - at '/image/registry': value must be 'registry.par1.medisphere.internal'
   $ helm lint --strict charts/mediagenda          # sans environnement
   [ERROR] values.yaml: - at '/medisphere/environnement': value must be one of 'dev', 'recette', 'prod'
   ```
   Le dernier est voulu : sans environnement, le chart ne se rend pas. `helm lint` se lance donc avec un fichier de valeurs (`-f ci/…`, E07). Piège rencontré : avec `additionalProperties: false` à la racine, Helm ajoute aux valeurs une clé par **dépendance** (ici `medisphere-commun` et `valkey` après E06) et `global` : elles doivent être déclarées dans le schéma, sinon `additional properties 'medisphere-commun' not allowed`.
4. **Helpers.** Image (digest prioritaire, digest malformé refusé par `fail`), URL de Valkey (`required` si Valkey externe sans URL), nom publié par `tpl` :
   ```
   {{- define "mediagenda.hostname" -}}
   {{- if .Values.httpRoute.hostname -}}
   {{- tpl .Values.httpRoute.hostname . -}}
   {{- else -}}
   {{- printf "mediagenda-%s.apps.par1.medisphere.internal" .Values.medisphere.environnement -}}
   {{- end -}}
   {{- end -}}
   ```
   et les règles croisées, appelées en tête de `deployment.yaml` :
   ```
   {{- if and (eq .Values.medisphere.environnement "prod") (lt (int .Values.replicaCount) 2) -}}
   {{- fail "prod : replicaCount doit valoir au moins 2" -}}
   {{- end -}}
   ```
   → `Error: execution error at (mediagenda/templates/deployment.yaml:1:4): prod : replicaCount doit valoir au moins 2`.
5. **`lookup`.** Dans `NOTES.txt` : avertissement si `lookup "v1" "Secret" .Release.Namespace <secret>` est vide à l'installation. Avec `helm template` et `--dry-run=client`, `lookup` renvoie toujours un dictionnaire vide : l'avertissement apparaît **à tort**. Avec `--dry-run=server` et une vraie installation, il reflète le cluster. Fonder un **rendu** sur `lookup` (créer un mot de passe seulement s'il n'existe pas, choisir une valeur selon un objet présent) produit un résultat qui dépend de qui rend et d'où : Argo CD rend sans `lookup` (comme `helm template`), Kustomize aussi (E09) ; le même chart donnerait deux sorties différentes, et chaque synchronisation tenterait de « corriger » l'écart. Le texte de `NOTES.txt` le dit en commentaire.
6. **Montée en 0.2.0.**
   ```
   admin@adm01:~/src/mediagenda-chart$ kubectl -n mediagenda-dev get deploy mediagenda -o jsonpath='{.metadata.uid}{"\n"}' | tee -a ~/m17/e05/journal.md
   admin@adm01:~/src/mediagenda-chart$ helm get manifest mediagenda -n mediagenda-dev > /tmp/avant.yaml
   admin@adm01:~/src/mediagenda-chart$ helm template mediagenda charts/mediagenda -n mediagenda-dev -f ~/m17/e05/dev.yaml > /tmp/apres.yaml
   admin@adm01:~/src/mediagenda-chart$ diff /tmp/avant.yaml /tmp/apres.yaml          # aucun changement de spec.selector
   admin@adm01:~/src/mediagenda-chart$ helm upgrade mediagenda charts/mediagenda -n mediagenda-dev -f ~/m17/e05/dev.yaml --dry-run=server
   admin@adm01:~/src/mediagenda-chart$ helm upgrade mediagenda charts/mediagenda -n mediagenda-dev -f ~/m17/e05/dev.yaml --wait
   admin@adm01:~/src/mediagenda-chart$ kubectl -n mediagenda-dev get deploy mediagenda -o jsonpath='{.metadata.uid}{"\n"}'   # identique
   admin@adm01:~/src/mediagenda-chart$ kubectl -n mediagenda-dev rollout history deploy/mediagenda
   ```
   [`dev.yaml`](fichiers/M17-E05/dev.yaml) : `medisphere.environnement: dev`, une réplique, `httpRoute.hostname` vide (calculé). Remarque : tant que le chart n'a pas de base intégrée (E06), `database.existingSecret` reste `mediagenda-db-app`.
7. Les deux erreurs de Lucas sont maintenant refusées : `- at '/replicaCount': got string, want integer` et `- at '': additional properties 'cacheTTL' not allowed` (à la racine ; sous `config`, le message dit `at '/config'`).

**Explications**

- **Schéma ou `fail` ?** Le schéma décrit chaque valeur isolément (type, motif, énumération) et s'applique avant tout rendu, avec des messages normalisés ; `fail` exprime les règles qui croisent plusieurs valeurs (prod + réplicas, base intégrée + Secret externe). Les deux s'exécutent avant tout contact avec le cluster.
- **`required` dans un gabarit nommé** : l'erreur nomme la valeur et le gabarit, et ne se déclenche que si le chemin de code qui en a besoin est rendu (l'URL de Valkey externe n'est requise que si le sous-chart est désactivé).
- **`tpl`** rend une chaîne comme un gabarit, avec le contexte donné : utile pour qu'un overlay ou un fichier de valeurs dise `{{ .Release.Namespace }}` sans que le chart connaisse l'espace à l'avance. À réserver aux valeurs prévues pour : `tpl` sur une valeur arbitraire est une injection de gabarit.

**Alternatives**

- Générer le schéma depuis `values.yaml` annoté (plugin `helm-schema`) : rapide, mais un schéma généré décrit ce qui **est**, pas ce qui est **permis** (pas de motif, pas d'interdiction).
- Valider par une politique d'admission (Kyverno au M26) plutôt que dans le chart : complémentaire (ça protège aussi contre ce qui ne passe pas par le chart), mais l'erreur arrive plus tard et plus loin de l'auteur.

**Pièges classiques**

- `"type": "integer"` et `--set replicaCount=2` : `--set` convertit en entier, mais `--set-string` non. Les fichiers YAML sont plus sûrs.
- Un schéma qui interdit une valeur… que `values.yaml` contient par défaut : `helm lint` échoue tout de suite, c'est voulu (environnement vide) ou c'est une erreur.
- `lookup` dans un gabarit d'objet « pour garder le mot de passe existant » : marche avec `helm upgrade`, casse avec tout le reste.
- Changer `selectorLabels` en refactorisant les helpers : le Deployment devient impossible à mettre à jour (champ immuable) ; d'où le contrôle de `metadata.uid`.

**En production chez MédiSphère**

Le schéma est le **contrat** du chart : toute nouvelle valeur y entre dans la même MR, et le pipeline (E13) lance le rendu de chaque fichier `ci/*-values.yaml` et des cas d'erreur des tests unitaires. Une valeur retirée du schéma est une rupture : version majeure du chart.
