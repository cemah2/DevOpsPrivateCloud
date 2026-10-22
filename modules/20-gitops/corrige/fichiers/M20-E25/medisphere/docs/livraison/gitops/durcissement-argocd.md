# Durcissement d'Argo CD

| | |
|---|---|
| Ticket | SEC-2125 |
| Exercice | M20-E25 |
| Code | `plateforme/k8s` : `composants/argocd/values-durcissement.yaml`, `composants/argocd/values.yaml` (exclusions), `composants/reseau/politiques/argocd.yaml`, `releases/argocd/policy.csv` (E24) |
| Dernière revue | <DATE> |

## Modèle de menace (résumé)

Argo CD a, par son contrôleur, le droit d'écrire **partout** dans `k8s-par1` (ClusterRole du chart) et lit tous les dépôts de livraison. Qui prend un de ses pods, ou un compte qui peut synchroniser la production, a la production. Les mesures ci-dessous réduisent : (1) ce que ses pods peuvent joindre ; (2) ce que ses comptes peuvent faire et pendant combien de temps ; (3) ce qui tourne réellement ; (4) ce qui échappe à la trace.

## Mesures

| # | Mesure | Où | Pourquoi | Vérification |
|---|---|---|---|---|
| 1 | Refus par défaut entrée et sortie de l'espace `argocd`, une CiliumNetworkPolicy par composant | `composants/reseau/politiques/argocd.yaml` | un pod compromis ne joint que sa ligne de la matrice des flux ; le *repo-server* (qui exécute `helm` et `kustomize` sur du contenu de dépôts) ne sort que vers `git01` et Harbor | `hubble observe -n argocd --verdict DROPPED` ; `kubectl -n argocd exec deploy/argocd-repo-server -- git ls-remote https://github.com/argoproj/argo-cd` → délai dépassé, refus visible dans Hubble ; `git ls-remote https://git01.par1.medisphere.internal/formation/gitops-labo.git` → demande d'identifiants (le flux passe) |
| 2 | NetworkPolicy du chart désactivées | `global.networkPolicy.create: false` | elles n'ont que l'entrée, et laissent tout entrer sur `argocd-server` ; deux sources de politiques se combinent par union (la plus large gagne) | `kubectl -n argocd get networkpolicy` → `refus-par-defaut` seulement |
| 3 | Terminal web fermé, accès anonyme fermé, **écrits** | `exec.enabled: false`, `users.anonymous.enabled: false` | défauts déjà sûrs, rendus explicites : un changement de défaut en amont ne les ouvre pas en silence | `kubectl -n argocd get cm argocd-cm -o yaml` |
| 4 | Sessions de 8 h | `users.session.duration: 8h` | un jeton de session volé (poste, navigateur) expire dans la journée | `argocd account get-user-info` puis lecture de `exp` du jeton |
| 5 | `override` pour synchroniser une autre révision | `application.sync.requireOverridePrivilegeForRevisionSync: true` | sans lui, `argocd app sync --revision <branche>` contourne la revue de `main` pour qui a `sync` | `argocd app sync mediagenda-recette --revision essai` en `julien-petit` → refus |
| 6 | Capacités des comptes : humains `login`, `ci-lecture` `apiKey` | `accounts.*` d'`argocd-cm` | un humain ne fabrique pas de jeton longue durée à son nom ; le compte de service ne se connecte pas à l'interface | `argocd account list` ; jetons existants : `argocd account get --account <nom>`, à supprimer par `argocd account delete-token` (la capacité retirée empêche d'en créer, la liste des jetons dans `argocd-secret` décide de leur validité : à vérifier sur ton lab) |
| 7 | Applications et ApplicationSets dans `argocd` seulement | absence de `application.namespaces` et `applicationsetcontroller.namespaces` ; pas de `sourceNamespaces` dans les AppProjects | sinon, quiconque peut créer un objet `Application` dans un espace autorisé obtient les droits du contrôleur dans les limites du projet : la frontière passe au RBAC Kubernetes de ces espaces | `kubectl -n argocd get cm argocd-cmd-params-cm -o yaml`, `kubectl get appproj -A -o jsonpath='{..sourceNamespaces}'` |
| 8 | Exclusions de ressources complétées (Velero) | `resourceExclusionsAdditional` de `values.yaml` | moins d'objets surveillés : moins de mémoire, moins de bruit ; on n'exclut que ce que personne ne décrit dans Git (pas les `Backup` de CNPG, enfants utiles des `ScheduledBackup`) | page *Clusters* (nombre de ressources), avant/après |
| 9 | Images par empreinte | `global.image.tag`, `redis.image.tag` = `étiquette@sha256:…` | ce qui tourne ne change pas si l'étiquette est réécrite en amont ou dans le cache | `kubectl -n argocd get pods -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' \| sort -u` |
| 10 | RBAC au moindre privilège, `policy.default` vide, testé en CI | E24 | — | `lab/bin/check 20 24` |

## Trace : qui a fait quoi

| Source | Contenu | Conservation | Limite |
|---|---|---|---|
| Historique Git (`plateforme/gitops`, dépôts `deploiement`) + MR | quoi, qui l'a écrit, qui l'a fusionné | illimitée | ne dit pas **quand** le cluster a changé |
| `status.history` et `status.operationState` des Applications | révision synchronisée, date, `initiatedBy.username` ou `automated` | 10 entrées par défaut (`revisionHistoryLimit` de l'Application) | perdu à la suppression de l'Application |
| `Event` Kubernetes émis par Argo CD sur les Applications (`kubectl -n argocd get events --field-selector involvedObject.kind=Application`) | « initiated sync », « Sync operation … succeeded », changements d'état, avec l'utilisateur | **1 h** (durée de vie des événements de l'API, `--event-ttl`) | trop court seul ; collecté par Alloy vers Loki au M22 |
| Journaux d'`argocd-server` (JSON) | appels d'API, connexions, échecs d'authentification | durée de vie du pod | idem, M22 |
| Audit de l'API Kubernetes (M14-E27) | écritures du compte de service du contrôleur dans le cluster | rotation des fichiers d'audit des nœuds de contrôle | identité = le contrôleur, pas l'humain : il faut recouper avec les sources précédentes |

## Ce qui reste ouvert

| Point | Risque | Traité par |
|---|---|---|
| Gateway → `argocd-server` en HTTP dans le cluster | lecture du trafic par qui contrôle un nœud | `BackendTLSPolicy` (support Cilium 1.20 à vérifier) ou TLS de bout en bout ; à revoir au M26 |
| Redis sans TLS | lecture du cache (manifestes rendus, sans Secrets) depuis un pod autorisé | politique réseau (seuls serveur, *repo-server*, contrôleur) ; `redis.tls` en option |
| Contrôleur avec droits d'écriture sur tout le cluster | un contrôleur compromis écrit partout | *Sync impersonation* (alpha en 3.5 : un compte de service par projet) ; à évaluer au M26 |
| Comptes locaux et mots de passe | pas de MFA, pas de groupe | SSO Keycloak au M24 |
| Trace courte (événements, journaux) | preuve d'audit HDS insuffisante | Loki au M22 |
