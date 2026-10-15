# Module 17 — Corrigé du palier 5 : Mini-projet

> ⚠️ Corrigé — à lire après avoir cherché.

**Testé** pendant la rédaction, sur le banc kube-apiserver 1.36 sans nœuds : la reprise du dev (point 2), avec la release Helm, l'overlay `dev` du corrigé M17-E09 et Helm 4.3. Le garde-fou de livraison a été rejoué : refus d'un `images:` en prod.

**Non testé en conditions réelles** :
- comportement de CloudNativePG si la spécification du `Cluster` du dev change à la reprise ;
- durée réelle du contrôle global (`helmfile diff` de toute la plateforme).

Piège vu pendant la rédaction (corrigé dans les fichiers de M17-E09) : un ResourceQuota écrit `services.loadbalancer` (au lieu de `services.loadbalancers`) est refusé par l'API, et une NetworkPolicy qui porte `egress: []` rend le `kubectl diff --server-side` jamais vide (le serveur retire la liste vide).

---

### M17-E25 — Mini-projet : packaging MédiSphère v1

**Solution**

*1. Rien de provisoire.*

```
admin@adm01:~/DevOpsPrivateCloud$ ls ~/.local/state/workbook/pannes-actives/ | grep M17      # rien
admin@adm01:~$ helm list -n wb-essais ; HELM_DRIVER=configmap helm list -n wb-essais
admin@adm01:~$ kubectl get secret,configmap -n wb-essais -l owner=helm
admin@adm01:~/src/mediagenda-chart$ git branch --list 'lucas/*'
```

Une panne réparée sans `--annuler` reste marquée active : on lance `lab/bin/break 17 XX --annuler`, qui ne revient pas sur la réparation. `capot-cm` (M17-E23) se désinstalle avec `HELM_DRIVER=configmap helm uninstall capot-cm -n wb-essais`.

*2. Reprise du dev.* Procédure (à publier en `RB-173-reprise-release-helm.md`) :

1. **Préparer.** L'overlay `dev` doit rendre la même version du chart et les mêmes valeurs que la release : même `chart.env` ; `livraison.yaml` du dev à la version de la release.
   ```
   admin@adm01:~/src/mediagenda-deploiement$ kubectl diff --server-side -k overlays/dev
   ```
   Le diff doit se limiter aux étiquettes et aux annotations : l'environnement `medisphere.fr/environnement`, et le conteneur d'initialisation qui remplace le hook (`migrations.mode: initContainer` dans `values-communes.yaml`). Le `Cluster` `mediagenda-db` de `ressources/E03-…` et celui du component `dependances` doivent être identiques. Sinon, aligne d'abord le component sur l'existant, ou accepte en connaissance de cause le changement (instances, stockage) : en dev, les données sont jetables.
2. **Faire oublier la release à Helm**, sans toucher aux objets. On sauvegarde puis on supprime ses Secrets de révision (M17-E23 : c'est tout ce que Helm sait de la release).
   ```
   admin@adm01:~$ kubectl get secret -n mediagenda-dev -l owner=helm,name=mediagenda -o yaml > ~/sauvegardes/dev-release-mediagenda.yaml && chmod 600 ~/sauvegardes/dev-release-mediagenda.yaml
   admin@adm01:~$ kubectl delete secret -n mediagenda-dev -l owner=helm,name=mediagenda
   admin@adm01:~$ helm list -n mediagenda-dev        # vide ; les objets sont toujours là
   ```
   `helm uninstall` **supprimerait** les objets. Mettre `helm.sh/resource-policy: keep` sur chacun puis désinstaller fonctionne aussi, mais demande une révision de plus et oublie facilement un objet.
3. **Prendre la propriété** par la commande de livraison, en forçant **une** fois :
   ```
   admin@adm01:~/src/mediagenda-deploiement$ kubectl apply --server-side --force-conflicts -k overlays/dev
   ```
4. **Retirer le copropriétaire `helm`.** Après l'étape 3, `helm` copossède encore les champs de même valeur (constaté : `[helm, kubectl]`). Pour chaque objet repris (Deployment, Service, ServiceAccount, ConfigMap, PDB, NetworkPolicy…) :
   ```
   i=$(kubectl get <genre>/<nom> -n mediagenda-dev --show-managed-fields -o json | jq '.metadata.managedFields | map(.manager) | index("helm")')
   kubectl patch <genre>/<nom> -n mediagenda-dev --type json -p "[{\"op\":\"remove\",\"path\":\"/metadata/managedFields/$i\"}]"
   kubectl annotate <genre>/<nom> -n mediagenda-dev meta.helm.sh/release-name- meta.helm.sh/release-namespace-
   ```
   L'ordre compte : on applique **d'abord** l'overlay (étape 3), qui fait de `kubectl` un copropriétaire de chaque champ rendu, **puis** on retire `helm`. Dans l'ordre inverse, un champ que seul `helm` possédait resterait sans propriétaire : sans effet immédiat, mais source de dérive. Ce n'est pas grave, mais ce n'est pas propre.
5. **Nettoyer** ce que l'overlay ne décrit pas : Job et NetworkPolicy de migration du hook (`mediagenda-migrations`), pod `mediagenda-test-pret` de `helm test`. On vérifie avec `kubectl get all,networkpolicy -n mediagenda-dev` et le rendu. L'étiquette `app.kubernetes.io/managed-by: Helm` reste sur les objets : elle vient du rendu du chart (`helm template`), comme en recette et en prod. Elle est commentée dans `base/kustomization.yaml`.
6. **Vérifier** : `kubectl diff --server-side -k overlays/dev` est vide, les pods sont prêts, et `https://mediagenda-dev.apps…/pret` répond 200.

*3. Prod en 1.1.0.* Étapes :
1. **Sauvegarde de la base**, à la demande, par le plugin Barman Cloud (M16-E19), puis vérification :
   ```yaml
   apiVersion: postgresql.cnpg.io/v1
   kind: Backup
   metadata: { name: avant-1-1-0, namespace: mediagenda-prod }
   spec:
     cluster: { name: mediagenda-db }
     method: plugin
     pluginConfiguration: { name: barman-cloud.cloudnative-pg.io }
   ```
   On vérifie `kubectl get backup -n mediagenda-prod avant-1-1-0` (phase `completed`).
2. **MR** `overlays/prod/livraison.yaml : version: v1.1.0`. Le garde-fou `verifier-livraison` est vert, et le diff (`kubectl diff --server-side -k overlays/prod`) est collé dans la MR. Retour arrière : MR inverse vers `v1.0.0`. Le schéma reste en V3, additive (M17-E18), et la 1.0.0 fonctionne dessus.
3. **Application après fusion**, puis vérification :
   ```
   kubectl apply --server-side -k overlays/prod
   kubectl rollout status deploy/mediagenda -n mediagenda-prod
   ```
   Le budget de perturbation garde 2 pods pendant le déploiement progressif (`maxSurge: 1`, `maxUnavailable: 0`).

*4. Pipelines.*
- `mediagenda/chart` : pipeline M17-E13 + job `sans-secret` (E15).
- `mediagenda/deploiement` : `rendre-base --verifier` (M17-E09), `verifier-livraison` (E21), et un job de diff manuel, faute d'accès au cluster depuis la CI avant le M19.
- `plateforme/k8s` : `helmfile -e par1 lint` (rendu des valeurs et des gabarits sans cluster), le script d'audit (E15) **à blanc** sur des valeurs rendues, et `shellcheck` des `outils/`.

*5. Plateforme.* Les commandes de contrôle :

```
helmfile -e par1 diff --detailed-exitcode
helm list -A --failed
helm list -A --pending
```

Les trois doivent être vides.

*6. `architecture.md`.* Le chemin d'un changement applicatif : commit sur `mediagenda/api` → image signée (M13) → MR du chart → étiquette → chart signé → MR de `chart.env` → rendu vérifié et commité → MR `livraison.yaml` par environnement → `kubectl apply --server-side -k` depuis `adm01`. Le chemin plateforme : MR sur `releases/` → `helmfile diff` en MR → `helmfile apply -l`. Ce qui n'est pas automatique :
- l'application dans le cluster (M20, Argo CD) ;
- la CI avec accès au cluster (M19) ;
- les secrets par Vault et ESO (M25) ;
- la vérification de signature à l'admission (M26).

*8. Démonstrations.*
- **Karim** :
  - une MR de chart avec `replicaCount: "2"` → `helm-lint` rouge ;
  - une MR de prod avec `images:` → `verifier-livraison` rouge (« « images: » interdit dans l'overlay »).
- **Sophie**, trois commandes :
  ```
  grep CHART_DIGEST ~/src/mediagenda-deploiement/chart.env
  cosign verify --key ~/medisphere/docs/registre/cosign.pub --insecure-ignore-tlog=true registry.par1.medisphere.internal/charts/mediagenda@<CHART_DIGEST>
  kubectl get pods -n mediagenda-prod -o jsonpath='{range .items[*]}{.status.containerStatuses[0].imageID}{"\n"}{end}' | sort -u   # digest = celui de v1.1.0 signé (cosign verify de l'image, M13)
  ```
- **Nadia** : RB-170, cas « pending-upgrade » → `helm rollback` vers la dernière révision `deployed`.

**Grille d'auto-évaluation** (sur 20)

| Critère | Points |
|---|---|
| Contrôle global vert, rien de provisoire (pannes closes, `wb-essais` propre, branches traitées) | 4 |
| Reprise du dev sans suppression d'objet, procédure écrite et réutilisable | 4 |
| Promotion de la prod : sauvegarde vérifiée, MR, garde-fou, retour arrière écrit, sans interruption | 4 |
| Pipelines comme seule voie (trois projets verts, MR de test refusées pour la bonne raison) | 3 |
| Documentation : architecture, ADR, registre des secrets, runbooks ; ce qui n'est pas automatique est dit | 3 |
| Revue : présentation claire, démonstrations réussies | 2 |

**Explications**

Le packaging v1 sépare trois objets qui avaient tendance à se confondre :
- le **paquet** : le chart, versionné et signé, sans environnement ni secret ;
- la **décision de livraison** : `chart.env` et `livraison.yaml` par environnement, relus en MR ;
- l'**état** : le cluster, qui doit être une copie fidèle du dépôt (diffs vides).

L'ADR-0170 en découle. Kustomize sans état pour les applications : ce que GitOps applique tel quel. Helm avec état pour les composants tiers, dont les hooks et les CRD l'exigent.

**Pièges classiques**
- `helm uninstall` du dev « pour repartir propre » : base et Service supprimés, nom publié perdu le temps de la reprise.
- Retirer `helm` des `managedFields` **avant** d'avoir appliqué l'overlay.
- Promouvoir la prod en reconstruisant ou en republiant : on promeut le **même** digest.
- Oublier que le contrôle global lit `origin/main` : une correction locale non poussée ne compte pas.

**En production chez MédiSphère**

Au M20, Argo CD remplace l'application depuis `adm01` : une Application par environnement sur `mediagenda/deploiement`, une autre sur `plateforme/k8s`. La promotion devient une MR et rien d'autre. Au M26, une politique Kyverno refuse en prod toute image non signée par la clé MédiSphère.
