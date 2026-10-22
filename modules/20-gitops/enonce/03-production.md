# Module 20 — Palier 3 : Production

Les paliers 1 et 2 ont mis MédiSphère en GitOps : Argo CD installé par Helmfile, le dépôt `plateforme/gitops` et son application racine, des AppProjects par équipe, MédiAgenda reprise sans coupure puis déclinée en trois environnements par un ApplicationSet, des promotions par MR, des canary qui s'arrêtent seuls. Mais Argo CD est devenu **le** point par lequel tout passe : quiconque le contrôle contrôle la production. Aujourd'hui, les droits y sont grossiers (lecture pour tous ou administration), ses pods parlent à qui ils veulent, un seul contrôleur et un seul *repo-server* portent toute la réconciliation, personne ne sait le reconstruire, rien n'empêche une synchronisation de production un vendredi à 18 h, et la CI garde ses droits d'écriture du M19 « au cas où ». Sophie Laurent veut un Argo CD durci et une CI sans aucun droit sur les espaces applicatifs ; Claire Morel veut la haute disponibilité, la reconstruction prouvée et la politique de changement ; l'agence de Lyon veut être gérée du même endroit ; l'équipe MédiDoc veut entrer dans le GitOps. Ce palier fait passer Argo CD en production, puis te fait livrer une version de MédiAgenda en production, en temps limité.

> ⚠️ **Rappel** : à partir de ce palier, Argo CD synchronise `mediagenda-prod`. Une erreur de politique réseau, de RBAC ou de désinstallation peut (1) couper Argo CD de ses dépôts — rien ne casse, mais plus rien ne se déploie ; (2) bien pire, supprimer **en cascade** les charges de production si une Application portant le finaliseur `resources-finalizer.argocd.argoproj.io` est supprimée pendant que le contrôleur tourne. Avant toute intervention sur Argo CD lui-même : (a) `argocd app list` tout `Synced`/`Healthy`, ou les écarts expliqués ; (b) un instantané etcd vérifié de moins d'une heure (`outils/etcd-instantane.sh`, M14-E24) ; (c) la synchronisation de `mediagenda-prod` est manuelle (palier 2) — vérifie-le ; (d) tu sais revenir à l'état précédent du code (`git revert` de la MR, puis `helmfile apply`).

**Chemin imposé** (introduction du module) : Argo CD et sa configuration (values, politique RBAC, tests) dans `plateforme/k8s` (Helmfile, release `argocd`, `composants/argocd/`, `releases/argocd/`) ; les politiques réseau de plateforme dans `plateforme/k8s`, `composants/reseau/politiques/` (M15-E28) ; les AppProjects, ApplicationSets et Applications dans `plateforme/gitops` ; les Secrets hors Git par `plateforme/k8s/outils/secrets-k8s.sh` (Ansible Vault `critique`, `secrets/<composant>.yml`) ; les VMs dans `plateforme/infra` (OpenTofu, état `envs/m20`), leur configuration dans `plateforme/ansible` ; les flux de la bordure dans `group_vars/role_routeur/pare_feu.yml` et `docs/socle/matrice-flux.md`, les flux du cluster dans `docs/kubernetes/reseau/matrice-flux-cluster.md` ; la documentation dans `docs/livraison/gitops/` de `plateforme/medisphere`. Tout passe par une MR relue.

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| Argo CD | 3.5.5 (chart `argo/argo-cd` 10.10.5), release Helmfile `argocd` (`plateforme/k8s`, `releases/argocd.yaml.gotmpl`, valeurs dans `composants/argocd/`), espace `argocd`, `https://argocd.apps.par1.medisphere.internal` (HTTPRoute sur `gw-par1`, 10.10.41.10, TLS terminé à la Gateway, `server.insecure` derrière elle) |
| Composants d'Argo CD | `argocd-server`, `argocd-repo-server`, `argocd-application-controller` (StatefulSet), `argocd-applicationset-controller`, `argocd-notifications-controller`, `argocd-redis` ; Dex désactivé (SSO au M24) |
| Comptes locaux (M20-E03) | `<MOI-ARGO>`, `karim-benali`, `julien-petit`, `nadia-roussel`, `ci-lecture` — les noms des comptes locaux d'Argo CD ne peuvent pas contenir de point (la clé `accounts.<nom>` de `argocd-cm` est découpée sur les points) : les points des noms GitLab deviennent des tirets ; `admin` désactivé |
| Dépôts suivis | `plateforme/gitops`, `mediagenda/deploiement`, `medidoc/deploiement`, `formation/gitops-labo` sur `https://git01.par1.medisphere.internal` ; charts OCI dans `oci://registry.par1.medisphere.internal/charts` (`plateforme/charts-miroir`, M20-E13) |
| Projets Argo CD (M20-E07) | `plateforme`, `mediagenda`, `medidoc`, `labo` ; Applications `mediagenda-dev`, `mediagenda-recette`, `mediagenda-prod` (ApplicationSet `mediagenda`), `racine`, `applications`, `projets`, `plateforme`, `labo`, `argo-rollouts` ; MédiDoc dev encore hors d'Argo CD (E33) |
| Adresses | `git01` 10.10.20.12, `reg01` 10.10.20.18 (`registry.par1.medisphere.internal`), `mon01` 10.10.20.19 (`smtp.par1.medisphere.internal:25`), `s3-01` 10.10.20.14:8333, Gateway `gw-par1` 10.10.41.10 ; travailleurs `K8S_TRAV` 10.10.40.61-63 |
| VM du palier | **2201 `lyo-k3s01`** (E26) : `vsandbox`, **10.10.99.61** fixe, 2 vCPU, 2 Go, k3s v1.36.5+k3s1 (rôle `k3s` du M18), état OpenTofu `envs/m20` (créé en M20-E23), étiquette `env-m20` ; détruite au mini-projet |
| Fichiers des checks | `~/.config/workbook/argocd-checks.token` (jeton de `ci-lecture`, M20-E03), `gitlab-checks.token`, `k8s-checks.kubeconfig` (`wb-checks`, qui lit les objets d'Argo CD depuis M20-E03 et ceux d'Argo Rollouts depuis M20-E15), `mailpit-checks.env` |
| Documentation | `docs/livraison/gitops/` : `rbac.md`, `durcissement-argocd.md`, `multi-cluster.md`, `performance.md`, `politique-changements.md`, `runbooks/RB-201-reconstruire-argo-cd.md`, `adr/ADR-0200-gitops.md` |

**Ordre conseillé** : E24 → E25 → E29 → E27 → E26 → E28 → E30 → E33 → E31 → E32 → E34. Le RBAC (E24) et le durcissement (E25) précèdent tout : une politique réseau ou un rôle trop large découverts après l'ajout d'un cluster distant coûtent plus cher. La reconstruction (E28) vient après E26 et E27 exprès : elle doit restaurer aussi le cluster distant et les webhooks. E30 retire les derniers droits de la CI une fois qu'Argo CD est fiable ; E34 réutilise tout le reste. **Durée totale indicative** : 22 à 27 h.

> 💾 **Mémoire** : `lyo-k3s01` (E26) ajoute 2 Go ; la haute disponibilité (E27) ajoute environ 1,5 Go de pods dans `k8s-par1`. Ni Jenkins ni SonarQube (retirés au M19) ni `flux01` (M20-E23) ne doivent tourner en même temps que `lyo-k3s01` : détruis `flux01` (retire `flux` des groupes de `envs/m20`) avant E26 si ce n'est pas fait.

Les vérifications se lancent **depuis `adm01`** (`lab/bin/check 20 XX`).

---

### M20-E24 — RBAC d'Argo CD et projets par équipe  `LAB` `★★★`

> **Ticket SEC-2124** — *De : Sophie Laurent* — *Copie : Julien Petit, Nadia Roussel*
> Aujourd'hui, dans Argo CD, on est soit administrateur, soit lecteur de tout. Ce n'est pas acceptable : Julien doit pouvoir synchroniser ses environnements de développement et de recette, et seulement les regarder en production ; Nadia doit tout voir sans rien pouvoir lancer ; personne ne doit hériter de droits « par défaut ». Et je veux que la politique soit **testée** : une MR qui ouvrirait la production à l'équipe MédiAgenda doit être refusée par la CI, pas par ma relecture.

**Objectifs pédagogiques**
- Comprendre le modèle RBAC d'Argo CD (Casbin) : politiques `p`, affectations `g`, ressources, actions, objets `<projet>/<application>`, effet `deny` prioritaire, `policy.default`.
- Distinguer les rôles globaux (`argocd-rbac-cm`) et les rôles de projet (AppProject), et savoir lequel utiliser.
- Écrire une politique au moindre privilège et la **tester hors ligne** (`argocd admin settings rbac can`) dans un pipeline.

**Prérequis** : M20-E03 (comptes locaux, `ci-lecture` et son jeton), M20-E07 (AppProjects), M20-E10 (Applications `mediagenda-*`), M20-E16 (Rollout de recette).
**Durée indicative** : 3 h.

**Contexte technique**
- La politique vit dans le ConfigMap `argocd-rbac-cm`, produit par le chart à partir de `configs.rbac` (`policy.csv`, `policy.default`, `scopes`, `policy.matchMode`). Le chart accepte aussi des clés `policy.<nom>.csv`, concaténées après `policy.csv`.
- Rôles demandés : **`role:plateforme-admin`** (`<MOI-ARGO>`, `karim-benali`), **`role:mediagenda-equipe`** (`julien-petit` : lire tout le projet `mediagenda`, synchroniser `mediagenda-dev` et `mediagenda-recette`, piloter le canary de recette, lire `mediagenda-prod` sans la synchroniser ni lire ses journaux), **`role:lecture`** (`nadia-roussel`, `ci-lecture` : lire les objets d'Argo CD, sans journaux de pods ni terminal). `policy.default` **vide**.
- Rôles de projet : un rôle `equipe` dans les AppProjects `mediagenda` et `medidoc`, relié aux groupes `medisphere:mediagenda-devs` et `medisphere:medidoc-devs` (mêmes noms que les groupes Kubernetes du M14) : il ne sert qu'à partir du SSO (M24), mais il est écrit maintenant.
- Fichiers attendus dans `plateforme/k8s` : `releases/argocd/policy.csv` (la politique, injectée dans les valeurs par la release), `releases/argocd/rbac-tests.txt` (les tests), `outils/argocd-rbac-tests.sh` (le script qui les joue), et un job de pipeline qui lance ce script.
- `argocd` (CLI 3.5.5) est sur `adm01` (rôle `outils_k8s`, M20-E03).

> ⚠️ **Attention** : une politique fausse peut retirer à **tous** les comptes, y compris le tien, le droit de corriger la politique par l'interface. Ce n'est pas grave tant que la politique vient de Helmfile (on corrige le fichier et on réapplique), mais garde ton accès `kubectl` au cluster pendant l'exercice, et lance toujours les tests **avant** `helmfile apply`.

**Travail demandé**
1. **Lecture.** Dans la documentation d'Argo CD (*RBAC Configuration*, *Projects* : *Project Roles*, `argocd-rbac-cm.yaml`, `assets/builtin-policy.csv`), réponds dans `docs/livraison/gitops/rbac.md` : que donne exactement `role:readonly` (et pourquoi ce n'est pas ce que veut Sophie) ? Pourquoi un `deny` dans `policy.default` ne peut-il pas être contredit, et pourquoi un `policy.default` non vide est-il dangereux ? Que changent, depuis la 3.0, les actions `update` et `delete` sur une Application par rapport à `update/*` et `delete/*` ? Que permet l'action `override` et le réglage `application.sync.requireOverridePrivilegeForRevisionSync` ? Quelle est la forme de l'objet d'une politique `applications`, `logs`, `exec`, `clusters`, `projects` ?
2. **Matrice.** Écris dans `rbac.md` la matrice des droits : en lignes les comptes et rôles, en colonnes les actions (lire, synchroniser, supprimer, `override`, actions sur un Rollout, journaux, terminal, projets, clusters, dépôts) par projet et par environnement. Chaque case « oui » est justifiée par un besoin du ticket.
3. **Politique.** Écris `releases/argocd/policy.csv` à partir de la matrice : trois rôles, les affectations des comptes, aucun `*` sur les ressources qui n'en ont pas besoin. Branche-le dans la release (`policy.default` vide, `scopes` prévu pour le M24) sans recopier la politique dans un fichier de valeurs : le fichier `.csv` est la seule source.
4. **Tests.** Écris `releases/argocd/rbac-tests.txt` : une ligne par cas, avec le résultat attendu, le sujet, l'action, la ressource et l'objet ; au moins 20 cas, dont au moins la moitié de **refus** attendus (synchroniser la production, supprimer, `override`, terminal, journaux de production, un compte inconnu, une ressource hors projet). Écris `outils/argocd-rbac-tests.sh` qui joue chaque ligne avec `argocd admin settings rbac can … --policy-file`, affiche les écarts et sort en erreur au premier écart ou à la première ligne invalide. Lance-le, puis **casse** volontairement la politique de deux façons : (a) remplace l'autorisation de synchroniser `mediagenda-dev` par `mediagenda/*` ; (b) fais de même **et** retire tout ce qui protège explicitement la production. Les tests attrapent-ils les deux ? Explique la différence dans `rbac.md`.
5. **Pipeline.** Ajoute au pipeline de `plateforme/k8s` un job qui lance ce script à chaque MR qui touche `releases/argocd/` ou `outils/argocd-rbac-tests.sh`, avec l'image d'Argo CD de la version déployée tirée par le cache Harbor. Ouvre une MR avec la politique cassée (variante qui fait échouer les tests) : le pipeline doit échouer. Ferme-la.
6. **Rôles de projet.** Dans `plateforme/gitops` (`projets/`), ajoute le rôle `equipe` aux AppProjects `mediagenda` et `medidoc`. Dans `rbac.md`, explique la différence avec les rôles globaux, quand un rôle de projet est le bon choix, et ce que sont ses jetons JWT.
7. **Application.** `helmfile -e par1 -l composant=argocd diff` (lis ce qui change dans `argocd-rbac-cm`), puis `apply`. Connecte-toi avec `julien-petit` puis `nadia-roussel` (CLI, puis interface) : `argocd account can-i …`, essai de synchronisation de `mediagenda-prod` (refus attendu), essai sur `mediagenda-recette` (accepté). Vérifie que le jeton de `ci-lecture` lit toujours les Applications, les projets et les clusters.

**Critères de réussite**
- [ ] `argocd-rbac-cm` déclare un `policy.default` vide et les rôles `role:plateforme-admin`, `role:mediagenda-equipe`, `role:lecture` ; aucun compte autre que `<MOI-ARGO>` et `karim-benali` n'a `role:admin` ou `role:plateforme-admin`.
- [ ] Évaluée par `argocd admin settings rbac can` sur la politique **en vigueur** : `julien-petit` synchronise `mediagenda-recette` mais ni `mediagenda-prod` ni `medidoc-dev`, ne supprime rien, n'ouvre pas de terminal ; `nadia-roussel` ne synchronise rien ; un compte inconnu n'a aucun droit.
- [ ] Le jeton `ci-lecture` lit les Applications et les clusters, et l'API répond `no` quand il demande s'il peut synchroniser `mediagenda-prod`.
- [ ] `releases/argocd/rbac-tests.txt` (≥ 20 cas, ≥ 10 refus) et `outils/argocd-rbac-tests.sh` sont sur `main` de `plateforme/k8s`, et le dernier pipeline de `main` contient le job des tests RBAC, réussi.
- [ ] Les AppProjects `mediagenda` et `medidoc` portent un rôle `equipe` ; `docs/livraison/gitops/rbac.md` (réponses et matrice) est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 20 24`

<details><summary>Indice 1</summary>

L'objet d'une politique `applications`, `applicationsets`, `logs` et `exec` est `<projet>/<application>` ; celui de `projects` est le nom du projet ; celui de `clusters` est l'URL du serveur. Pour l'équipe, pense par cas : un `allow` large en lecture sur `mediagenda/*`, des `allow` précis pour la synchronisation, et demande-toi si un `deny` explicite sur la production apporte quelque chose (que se passe-t-il le jour où quelqu'un ajoute un `allow` plus large ?).
</details>

<details><summary>Indice 2</summary>

`argocd admin settings rbac can` sort en code 0 pour « Yes » et 1 pour « No »… mais aussi 1 pour une erreur (action ou ressource inconnue, fichier illisible). Ton script doit lire la **sortie** (`Yes`/`No`), pas seulement le code. Et cette commande veut une configuration Kubernetes même quand la politique vient d'un fichier : dans un job de CI sans cluster, il lui faut un kubeconfig, même factice.
</details>

<details><summary>Indice 3</summary>

Helmfile sait lire un fichier dans un gabarit (`readFile`, chemin relatif au dossier du fichier de releases) ; un fichier de valeurs `.yaml.gotmpl` est rendu comme un gabarit. Attention à l'indentation du contenu injecté sous `policy.csv: |`.
</details>

**Pour aller plus loin** (facultatif) : `policy.matchMode: regex` et ses pièges ; le rôle `role:authenticated` recommandé par la documentation quand `policy.default` n'est pas vide ; les jetons d'un rôle de projet (`argocd proj role create-token`) pour une automatisation limitée à un projet ; [RBAC Configuration](https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/), [Project Roles](https://argo-cd.readthedocs.io/en/stable/user-guide/projects/#project-roles).

---

### M20-E25 — Durcir Argo CD  `LAB` `★★★`

> **Ticket SEC-2125** — *De : Sophie Laurent* — *Copie : Karim Benali*
> Argo CD a les droits d'écrire partout dans le cluster et lit nos dépôts. Si quelqu'un prend la main sur un de ses pods, il a la production. Je veux : des flux réseau réduits au strict nécessaire (le *repo-server* ne parle qu'à GitLab et à Harbor), pas de terminal web, des sessions courtes, aucun compte qui puisse fabriquer des jetons sans raison, des images épinglées, et une trace de qui a fait quoi. Tout ça dans le code, avec la liste de ce que tu as volontairement laissé ouvert.

**Objectifs pédagogiques**
- Établir la matrice des flux d'Argo CD (qui parle à qui, sur quel port, pourquoi) et la traduire en politiques Cilium par composant, avec refus par défaut.
- Réduire la surface de l'interface et de l'API : terminal, sessions, capacités des comptes, `override`, applications hors de l'espace d'Argo CD.
- Épingler les images par empreinte, réduire ce que le contrôleur surveille (exclusions), et savoir où se trouve la trace des actions.

**Prérequis** : M20-E24 ; M15-E17 et E28 (refus par défaut, `base-dns`, `toFQDNs`, matrice des flux du cluster) ; M14-E27 (audit de l'API).
**Durée indicative** : 3 h 30.

**Contexte technique**
- Le chart crée par défaut des NetworkPolicy **d'entrée** seulement (`global.networkPolicy.create: true`), dont une qui accepte **tout** en entrée sur `argocd-server` ; rien en sortie. Pour une seule source de vérité, tu les remplaces par tes propres politiques dans `plateforme/k8s`, `composants/reseau/politiques/argocd.yaml`, appliquées comme les autres politiques de plateforme (M15-E28).
- Destinations hors cluster : `git01.par1.medisphere.internal:443`, `registry.par1.medisphere.internal:443` (CNAME vers `reg01`), `smtp.par1.medisphere.internal:25` (notifications, M20-E19). Le serveur est joint par la Gateway (identité Cilium `ingress`) sur son port 8080. La politique `base-dns` (M15-E28) fait passer le DNS de tous les pods par le proxy DNS de Cilium : prérequis des règles `toFQDNs`.
- Pod du chart à ne pas oublier : le Job `argocd-redis-secret-init` (crochet Helm `pre-install,pre-upgrade`) parle à l'API du cluster.
- Les réglages de `argocd-cm` et `argocd-cmd-params-cm` passent par `configs.cm` et `configs.params` des valeurs ; les exclusions supplémentaires par `configs.cm.resourceExclusionsAdditional` (le chart les **ajoute** à sa liste par défaut ; redéfinir `resource.exclusions` la remplacerait).
- Empreintes des images de la version déployée (relevées le 22/10/2026 ; vérifie-les toi-même) : `quay.io/argoproj/argocd:v3.5.5` → `sha256:13db7b10db23283b1b36f855046602e18539a8a8204c9f6f039e8896c8897518` ; `docker.io/library/redis:8.6.4-alpine` → `sha256:2cc044fc5a07c9b701f8f1255a309ae9ad7856e694ac03513bf3648c01e40763` (index multi-architecture).

> ⚠️ **Attention** : une politique réseau trop stricte coupe Argo CD de l'API du cluster ou de ses dépôts : rien n'est supprimé, mais plus rien n'est réconcilié et les Applications passent en `Unknown`. Applique les politiques **composant par composant**, en observant `hubble observe -n argocd --verdict DROPPED` dans un autre terminal ; garde la commande de retour arrière prête (`kubectl --context k8s-par1 -n argocd delete ciliumnetworkpolicy <nom>`, puis correction du fichier par MR).

**Travail demandé**
1. **Matrice des flux.** Pour chaque composant d'Argo CD (y compris Redis et le Job d'initialisation), liste ses flux entrants et sortants : source, destination, port, raison. Sers-toi de la documentation (*Architecture*, *High Availability*), des ports déclarés dans le rendu du chart (`helmfile -e par1 -l composant=argocd template`) et de Hubble (`hubble observe -n argocd` pendant une synchronisation et un rafraîchissement). Reporte-la dans `docs/kubernetes/reseau/matrice-flux-cluster.md`.
2. **Politiques réseau.** Écris `composants/reseau/politiques/argocd.yaml` : refus par défaut en entrée **et** en sortie pour tout l'espace, puis une politique Cilium par composant qui n'ouvre que la matrice. Le *repo-server* ne sort que vers `git01` et `registry` en 443 (et le DNS) ; le serveur n'est joint que par la Gateway. Désactive les NetworkPolicy du chart. Applique, puis prouve : une synchronisation et un rafraîchissement fonctionnent, `git ls-remote` lancé **dans** le conteneur du *repo-server* (`kubectl exec`) réussit vers `git01` et échoue vers un dépôt public d'Internet, et Hubble montre ce refus. N'ajoute pas de pod de test portant les étiquettes du *repo-server* : il entrerait dans son Service.
3. **Interface et API.** Dans les valeurs (`composants/argocd/values-durcissement.yaml`) : terminal web désactivé **explicitement**, accès anonyme désactivé explicitement, durée de session de 8 h, `application.sync.requireOverridePrivilegeForRevisionSync` activé, capacités des comptes réduites (humains : `login` seulement ; `ci-lecture` : `apiKey` seulement). Que deviennent les jetons déjà émis par un compte humain ? Vérifie avec `argocd account list` et `argocd account get --account …`.
4. **Applications hors de l'espace d'Argo CD.** Vérifie que les fonctions *Applications in any namespace* et *ApplicationSets in any namespace* ne sont pas activées (`application.namespaces`, `applicationsetcontroller.namespaces`, `sourceNamespaces` des AppProjects) et écris pourquoi on les laisse fermées.
5. **Exclusions.** Relis les exclusions posées en M20-E12 (objets de Velero) : manque-t-il des objets à fort renouvellement que personne ne déclare dans Git (les autres types de demandes de Velero, par exemple) ? Complète la liste **là où elle est déjà** (une liste n'est pas fusionnée entre deux fichiers de valeurs : la redéfinir dans un autre fichier remplacerait celle d'E12). Dis pourquoi tu n'exclus **pas** les `Backup` de CloudNativePG créés par les `ScheduledBackup` de MédiAgenda. Mesure le nombre de ressources surveillées avant et après (page *Clusters* de l'interface, ou `argocd admin cluster stats` avec ton kubeconfig).
6. **Images.** Épingle les images d'Argo CD et de Redis par empreinte (étiquette **et** empreinte, tirées par les caches Harbor). Vérifie dans les pods que l'image en cours est bien celle de l'empreinte.
7. **Trace.** Où sont écrits « qui a synchronisé quoi, quand » ? Compare : l'historique de Git, les `Event` Kubernetes émis par Argo CD sur les Applications (`kubectl -n argocd get events --field-selector involvedObject.kind=Application`), `status.operationState` et `status.history` des Applications, les journaux de `argocd-server`, le journal d'audit de l'API Kubernetes (M14-E27) pour le compte de service du contrôleur. Durée de conservation de chacun ? Ce qui manque jusqu'au M22 (Loki) ?
8. **Document.** `docs/livraison/gitops/durcissement-argocd.md` : chaque mesure, sa justification, sa vérification, et la liste de ce qui reste ouvert (par exemple : le trafic Gateway → serveur en clair dans le cluster, le Redis sans TLS, les droits en écriture du contrôleur sur tout le cluster) avec le module qui le traitera.

**Critères de réussite**
- [ ] L'espace `argocd` a un refus par défaut en entrée et en sortie ; chaque composant a sa CiliumNetworkPolicy ; la politique du *repo-server* n'autorise en sortie que `git01`, `registry`/`reg01` en 443, Redis et le DNS (aucun `world`, aucun CIDR large) ; le serveur n'accepte en entrée que la Gateway ; les NetworkPolicy du chart ont disparu.
- [ ] `argocd-cm` contient `exec.enabled: "false"`, `users.anonymous.enabled: "false"`, une durée de session de 12 h au plus, `application.sync.requireOverridePrivilegeForRevisionSync: "true"` ; aucun compte humain n'a la capacité `apiKey` ; `ci-lecture` n'a pas la capacité `login`.
- [ ] Ni `application.namespaces` ni `applicationsetcontroller.namespaces` ne sont définis ; les exclusions comprennent les objets de Velero.
- [ ] Tous les conteneurs de l'espace `argocd` tournent sur une image référencée par empreinte (`@sha256:`), tirée de `registry.par1.medisphere.internal`.
- [ ] Toutes les Applications sont `Synced`/`Healthy` (ou leurs écarts expliqués) après le durcissement ; `durcissement-argocd.md` et la matrice des flux du cluster sont sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 20 25`

<details><summary>Indice 1</summary>

Une politique Cilium qui contient une section `ingress` (ou `egress`) fait passer les pods qu'elle sélectionne en refus par défaut dans ce sens ; un `refus-par-defaut` en NetworkPolicy standard (`podSelector: {}`, deux `policyTypes`) le fait pour tout l'espace, comme au M15. L'API du cluster s'autorise par l'entité `kube-apiserver` ; les composants entre eux par `toEndpoints`/`fromEndpoints` et les étiquettes `app.kubernetes.io/name` du chart.
</details>

<details><summary>Indice 2</summary>

Qui parle à Redis ? Lis la NetworkPolicy du chart pour Redis (rendu Helm) : elle te donne la liste. Qui parle au *repo-server* ? Même méthode. Et n'oublie pas le crochet de pré-installation : s'il ne joint plus l'API, la **prochaine** `helmfile apply` échoue, pas celle d'aujourd'hui.
</details>

<details><summary>Indice 3</summary>

Les capacités d'un compte local sont la valeur de `accounts.<nom>` dans `argocd-cm` (`login`, `apiKey`, ou les deux). Retirer `apiKey` à un compte n'invalide pas forcément les jetons qu'il a déjà : lis comment Argo CD vérifie un jeton (liste des jetons du compte dans `argocd-secret`) et supprime ceux qui n'ont pas lieu d'être (`argocd account delete-token`).
</details>

**Pour aller plus loin** (facultatif) : TLS entre la Gateway et le serveur (`BackendTLSPolicy`, à vérifier dans la matrice de support de Cilium 1.20) ; TLS de Redis (`redis.tls`) ; *Sync impersonation* (`application.sync.impersonation.enabled`, alpha) pour que le contrôleur synchronise avec un compte de service par projet au lieu de ses propres droits ; [Security](https://argo-cd.readthedocs.io/en/stable/operator-manual/security/), [Resource Exclusion](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#resource-exclusioninclusion).

---

### M20-E26 — Multi-cluster : le cluster de l'agence LYO1  `LAB` `★★★`

> **Ticket PLAT-2126** — *De : Claire Morel* — *Copie : Sophie Laurent*
> L'agence de Lyon aura son petit cluster k3s pour ses services locaux (borne d'accueil, impression des convocations). Je ne veux pas d'un second Argo CD à Lyon : on le gère d'ici, avec les mêmes dépôts et les mêmes règles. Sophie pose une condition : Argo CD ne doit **pas** être administrateur de ce cluster. Commence par un service d'essai.

**Objectifs pédagogiques**
- Enregistrer un cluster distant dans Argo CD de façon déclarative (Secret de cluster étiqueté), avec un compte de service à droits limités et une autorité vérifiée.
- Comprendre ce que les champs `namespaces` et `clusterResources` d'un cluster changent pour le contrôleur (surveillance, droits requis).
- Déployer sur un ensemble de clusters choisi par étiquette avec le générateur `clusters` d'un ApplicationSet.

**Prérequis** : M18-E03 (rôle `k3s`, k3s mononœud de l'agence), M20-E23 (état OpenTofu `envs/m20`), M20-E07 (AppProject `labo`), M20-E25 (politiques réseau d'Argo CD).
**Durée indicative** : 4 h.

**Contexte technique**
- VM **2201 `lyo-k3s01`** : Debian 13, `vsandbox`, adresse fixe **10.10.99.61/24** (plage « nœuds de clusters »), 2 vCPU, 2 Go, 20 Go sur `local-nvme`, étiquettes `env-m20` et `role-k3s`, module `vm-noeud` et enregistrement DNS `lyo-k3s01.par1.medisphere.internal`. Elle fait partie de l'état `envs/m20` écrit en M20-E23, qui la prévoyait déjà : **une seule** déclaration par VM dans cet état.
- k3s **v1.36.5+k3s1** par le rôle `k3s` du M18 (script figé, `registries.yaml` vers les caches Harbor) : `tls-san` avec le nom et l'adresse, `traefik` et `servicelb` désactivés, kubeconfig local en 600. k3s applique tout manifeste déposé dans `/var/lib/rancher/k3s/server/manifests/` (*Auto-Deploying Manifests*).
- Ce qu'il faut créer dans `lyo-k3s01`, par le code (rôle ou playbook) : l'espace **`agence`**, le compte de service **`argocd-gestion`** (espace `agence`), un Role et un RoleBinding qui lui donnent les droits de déployer dans `agence` **seulement**, et un Secret de jeton longue durée de type `kubernetes.io/service-account-token` (exception écrite, comme `wb-checks` au M14).
- Côté Argo CD : un Secret de cluster `cluster-lyo-k3s01` dans `argocd` (étiquettes `argocd.argoproj.io/secret-type: cluster`, `site: lyo1`, `medisphere.internal/environnement: agence`), créé hors Git par `secrets-k8s.sh` (composant `argocd`) à partir du Vault (`secrets/argocd.yml`) ; le serveur est `https://lyo-k3s01.par1.medisphere.internal:6443`.
- Application d'essai : un dossier `agence/` dans `formation/gitops-labo` (un Deployment `labo` de l'image `docker.io/traefik/whoami:v1.11.0`, comme le service d'essai du M18-E03, et son Service) ; un ApplicationSet **`labo-agences`** (projet `labo`) dans `plateforme/gitops/applications/` qui génère une Application `labo-<nom du cluster>` pour chaque cluster étiqueté `site=lyo1`.
- Flux : **`K8S_TRAV` → 10.10.99.61 TCP 6443** (le contrôleur d'Argo CD sort par l'adresse de son nœud) ; VLAN 99 → `reg01` 443 existe déjà (M13).

> ⚠️ **Attention** : `lyo-k3s01` ajoute 2 Go : vérifie la mémoire libre de `pve01` et détruis `flux01` d'abord si elle tourne encore. Le nouveau flux se pose sur une passerelle à la fois (`--limit gw01`, puis `gw02`), retour arrière par `git revert` et le même playbook.

**Travail demandé**
1. **La VM.** `envs/m20` : fais créer `lyo-k3s01` par l'état d'E23 (adresse fixe, enregistrement DNS), `tofu plan` (seules cette VM et son nom apparaissent, plus la destruction de `flux01` si elle tournait encore), `apply`. Inventaire Ansible et `host_vars/lyo-k3s01/k3s.yml` ; un playbook `playbooks/m20-lyo.yml` qui applique le rôle `k3s` puis dépose les manifestes de gestion. Vérifie depuis `adm01` avec le kubeconfig local de k3s (récupéré dans `~/.config/workbook/m20/`, 600).
2. **Compte de gestion.** Écris les manifestes (`agence`, `argocd-gestion`, Role, RoleBinding, Secret de jeton). Le Role donne ce qu'il faut pour gérer les objets de l'application (Deployments, Services, ConfigMaps, ReplicaSets et pods en lecture…) dans `agence`, rien d'autre. Vérifie : `kubectl auth can-i --list --as system:serviceaccount:agence:argocd-gestion -n agence`, puis la même chose dans `kube-system` et pour les ressources de cluster.
3. **Lecture.** Dans la documentation (*Declarative Setup*, section *Clusters*), relève les champs d'un Secret de cluster et réponds dans `docs/livraison/gitops/multi-cluster.md` : que changent `namespaces` et `clusterResources` ? Pourquoi un compte limité à un espace **impose-t-il** `namespaces` ? Que contient `config` (jeton, `tlsClientConfig`, `caData`) et pourquoi ne jamais mettre `insecure: true` ? Que vaut l'état de connexion d'un cluster **sans** application, et pourquoi ?
4. **Le flux.** Règle de la bordure (`pare_feu.yml`, matrice des flux), puis la politique Cilium du contrôleur (E25) : ajoute la sortie vers `lyo-k3s01:6443`. Vérifie avec Hubble que le contrôleur joint le cluster distant et que rien d'autre ne le peut.
5. **Le Secret de cluster.** Ajoute au Vault (`secrets/argocd.yml`) le jeton et l'autorité de `lyo-k3s01`, et au module `argocd` de `secrets-k8s.sh` (`outils/secrets-k8s.d/argocd.sh`, M20-E06) la création du Secret de cluster (étiquettes, `namespaces: agence`, `clusterResources: "false"`). Lance-le. `argocd cluster list` : le cluster apparaît ; quel est son état ?
6. **Projet et ApplicationSet.** Autorise la destination `lyo-k3s01`/`agence` dans l'AppProject `labo` ; écris le dossier `agence/` de `formation/gitops-labo` et l'ApplicationSet `labo-agences` (générateur `clusters` avec un sélecteur `site: lyo1`, synchronisation automatique avec `prune` et `selfHeal`, pas de `CreateNamespace`). MR, fusion, racine synchronisée : l'Application `labo-lyo-k3s01` apparaît, se synchronise, et le cluster passe à `Successful`.
7. **Preuves.** Sur `lyo-k3s01`, le Deployment `labo` est prêt ; supprime-le à la main (`kubectl delete deployment labo -n agence` avec le kubeconfig local) : Argo CD le recrée. Essaie de faire déployer à l'ApplicationSet un objet dans `kube-system` (MR d'essai sur une branche, Application de test) : qui refuse, l'AppProject ou le cluster ? Documente les deux niveaux de défense dans `multi-cluster.md`.

**Critères de réussite**
- [ ] `lyo-k3s01` (VM 2201, 10.10.99.61, étiquette `env-m20`) est décrite dans `envs/m20` ; k3s y est `Ready` en v1.36.5+k3s1.
- [ ] Dans `lyo-k3s01`, `argocd-gestion` n'est lié à aucun ClusterRole d'écriture et n'a de droits d'écriture que dans `agence`.
- [ ] Argo CD voit le cluster `https://lyo-k3s01.par1.medisphere.internal:6443` avec l'étiquette `site=lyo1`, limité à l'espace `agence`, en état `Successful`.
- [ ] L'Application `labo-lyo-k3s01`, générée par l'ApplicationSet `labo-agences` (projet `labo`), est `Synced`/`Healthy` ; le Deployment `labo` de `agence` est prêt sur `lyo-k3s01`.
- [ ] Le flux `K8S_TRAV` → 10.10.99.61:6443 est dans la matrice des flux ; `multi-cluster.md` est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 20 26`

<details><summary>Indice 1</summary>

Un Role ne donne rien sur les objets de cluster (espaces, CRD, ClusterRoles). Si tu enregistres le cluster sans `namespaces`, le contrôleur essaie de surveiller **toutes** les ressources de **tout** le cluster, et chaque `list`/`watch` refusé fait échouer son cache : l'état passe en `Failed`. Lister les espaces gérés lui dit où regarder. Même dans `agence`, ton compte n'a pas le droit de lister tous les types (les Secrets, par exemple) : cherche dans *Declarative Setup* comment demander au contrôleur de **respecter** les droits qu'on lui donne au lieu d'échouer.
</details>

<details><summary>Indice 2</summary>

`caData` est l'autorité du serveur d'API de k3s **encodée en base64** (le contenu PEM, pas un chemin) : tu la trouves dans le Secret de jeton du compte de service (`ca.crt`) ou dans le kubeconfig de k3s. Le nom que tu mets dans `server` doit figurer dans le certificat du serveur d'API : c'est le rôle de `tls-san`.
</details>

<details><summary>Indice 3</summary>

Le générateur `clusters` sélectionne les **Secrets de cluster** par leurs étiquettes et expose dans le gabarit `name`, `server` et les étiquettes (`metadata.labels.<clé>`). Avec `goTemplate: true`, écris `{{ .name }}`, `{{ .server }}` ; garde `goTemplateOptions: ["missingkey=error"]`.
</details>

**Pour aller plus loin** (facultatif) : le champ `project` d'un Secret de cluster (cluster réservé à un projet) ; un cluster enregistré par l'agent (Argo CD *agent*, mode « principal/agent », hors périmètre) quand le cluster distant n'est pas joignable depuis le centre ; [Declarative Setup — Clusters](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#clusters), [Cluster Generator](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Cluster/).

---

### M20-E27 — Haute disponibilité et performance d'Argo CD  `LAB` `★★★`

> **Ticket PLAT-2127** — *De : Claire Morel* — *Copie : Julien Petit*
> Deux remarques de la semaine. Julien : « après une fusion, j'attends jusqu'à quatre minutes avant qu'Argo CD bouge ». Karim : « mardi, pendant le redémarrage de `k8s-w02`, l'interface d'Argo CD était inaccessible et plus rien ne se synchronisait ». Je veux un Argo CD qui survit à la perte d'un travailleur, qui réagit en secondes à un `git push`, et des chiffres avant/après.

**Objectifs pédagogiques**
- Savoir ce qui, dans Argo CD, est sans état (serveur, *repo-server*) et ce qui ne l'est pas (contrôleur et ses partitions, Redis), et le dimensionner en conséquence.
- Comprendre le partitionnement (*sharding*) du contrôleur : par **cluster**, pas par application.
- Remplacer l'interrogation périodique par des webhooks GitLab sécurisés, et régler `timeout.reconciliation` en connaissance de cause.

**Prérequis** : M20-E25 (politiques réseau), M20-E26 (deux clusters gérés), M14-E16 (PDB), M19 (GitLab 19.5, réglages réseau de l'instance).
**Durée indicative** : 3 h.

**Contexte technique**
- Valeurs de la release : `server.replicas`, `repoServer.replicas`, `controller.replicas` (le chart reporte la valeur dans `ARGOCD_CONTROLLER_REPLICAS`), `applicationSet.replicas`, `*.pdb.enabled`, `redis-ha.enabled` ; `configs.cm."timeout.reconciliation"` et `timeout.reconciliation.jitter` ; `configs.params."controller.sharding.algorithm"`.
- Le serveur d'Argo CD reçoit les webhooks sur `https://argocd.apps.par1.medisphere.internal/api/webhook` (en-tête `X-Gitlab-Token` comparé à `webhook.gitlab.secret` de `argocd-secret`). Argo CD accepte qu'une clé de `argocd-secret` désigne une clé d'un **autre** Secret (`$<nom>:<clé>`, ce Secret portant l'étiquette `app.kubernetes.io/part-of: argocd`) : la référence peut vivre dans les valeurs, le secret lui-même dans un Secret `argocd-webhook-gitlab` créé par `secrets-k8s.sh`.
- GitLab refuse par défaut les webhooks vers des adresses privées : l'administrateur peut ajouter un nom ou une adresse à la liste d'autorisation des requêtes locales (*Admin → Paramètres → Réseau → Requêtes sortantes* ; l'attribut correspondant de l'API des paramètres n'est pas modifiable par l'API en 19.x). Flux à ouvrir : **`git01` → 10.10.41.10 TCP 443** (VLAN 20 vers la plage des services).
- Webhooks attendus au minimum sur `plateforme/gitops` et `mediagenda/deploiement` (événements de *push*, vérification TLS active).

> ⚠️ **Attention** : passer le contrôleur de 1 à 2 réplicas **redistribue les clusters** entre les partitions : pendant quelques dizaines de secondes, une partie des Applications n'est plus réconciliée. Fais-le hors d'une synchronisation en cours, et note l'heure. Chaque réplica de plus coûte de la mémoire sur les travailleurs (relève `kubectl top pods -n argocd` avant et après).

**Travail demandé**
1. **Mesure de départ.** Chronomètre dix fois le délai entre la fusion d'une MR triviale dans `mediagenda/deploiement` (une annotation de l'overlay `dev`) et le début de la synchronisation de `mediagenda-dev` (`status.operationState.startedAt`) ; note min, médiane, max. Relève la mémoire et le processeur des pods d'Argo CD. Explique les valeurs observées à partir de `timeout.reconciliation` et de sa gigue.
2. **Lecture.** *High Availability* et *Dynamic Cluster Distribution* : qu'est-ce qui est partitionné entre les réplicas du contrôleur ? Combien de partitions utiles avec **deux** clusters gérés (`in-cluster` et `lyo-k3s01`) ? Que se passe-t-il si un réplica du StatefulSet est perdu sans distribution dynamique ? Pourquoi `ARGOCD_API_SERVER_REPLICAS` pour le serveur ? Pourquoi la documentation dit-elle que Redis peut être perdu « sans interruption » ?
3. **Réplicas et PDB.** Dans `composants/argocd/values-ha.yaml` : 2 réplicas pour le serveur, le *repo-server*, le contrôleur et le contrôleur d'ApplicationSets, anti-affinité qui les étale sur les travailleurs, une PDB par composant répliqué. Décide pour Redis (le chart propose `redis-ha` : trois Redis avec Sentinel et trois HAProxy, anti-affinité stricte) et **justifie** dans `performance.md`. Applique ; vérifie la répartition des clusters entre les partitions (`argocd admin cluster stats` ou `shards`, avec ton kubeconfig).
4. **Panne.** Draine un travailleur qui porte un pod d'Argo CD (`kubectl drain --ignore-daemonsets --delete-emptydir-data`) pendant qu'une boucle depuis `adm01` interroge l'API (`argocd app list` toutes les 5 s) et qu'une MR est fusionnée : l'interface répond-elle ? La synchronisation a-t-elle lieu ? Remets le nœud en service.
5. **Webhooks.** Secret partagé (aléatoire, en Vault, Secret `argocd-webhook-gitlab` par `secrets-k8s.sh`, référence `$argocd-webhook-gitlab:secret` dans les valeurs) ; liste d'autorisation de GitLab ; flux de la bordure ; puis un script idempotent `outils/argocd-webhooks-gitlab.sh` (`plateforme/k8s`) qui crée ou met à jour le webhook de chaque projet suivi par Argo CD (`push_events`, `enable_ssl_verification`, jeton secret), en lisant le jeton GitLab et le secret depuis des fichiers 600. Teste un *push* : événement `200` dans GitLab (*Paramètres → Webhooks → Événements récents*) et rafraîchissement immédiat dans Argo CD.
6. **Réconciliation.** Avec les webhooks en place, passe `timeout.reconciliation` à 300 s (gigue 60 s). Quels changements ne sont **pas** signalés par un webhook (chart OCI, image, dépôt sans webhook) et quand seront-ils vus ? Refais la mesure de l'étape 1 et consigne les deux séries dans `docs/livraison/gitops/performance.md` (avec la mémoire avant/après et la décision sur Redis).

**Critères de réussite**
- [ ] `argocd-server`, `argocd-repo-server` et `argocd-applicationset-controller` ont au moins 2 réplicas prêts, répartis sur deux travailleurs au moins ; le StatefulSet du contrôleur a 2 réplicas prêts et `ARGOCD_CONTROLLER_REPLICAS=2` ; une PDB protège chacun de ces composants.
- [ ] `timeout.reconciliation` est explicitement réglé (180 s ou plus) dans `argocd-cm`.
- [ ] `plateforme/gitops` et `mediagenda/deploiement` ont un webhook vers `https://argocd.apps.par1.medisphere.internal/api/webhook` (événements de *push*, TLS vérifié) qui a reçu au moins une réponse 2xx dans les 7 derniers jours.
- [ ] Le flux `git01` → 10.10.41.10:443 est dans la matrice des flux ; `performance.md` (deux séries de mesures, décision Redis) est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 20 27`

<details><summary>Indice 1</summary>

Le contrôleur ne répartit pas les **Applications** mais les **clusters** : avec deux clusters et deux réplicas, au mieux chaque réplica en porte un — et l'algorithme par défaut (`legacy`, empreinte de l'identifiant du cluster) peut très bien les mettre tous les deux sur la même partition. Vérifie (`argocd admin cluster stats`), et lis ce que fait le champ `shard` d'un Secret de cluster. Dans tous les cas, `in-cluster` (presque toutes les Applications) reste sur un seul réplica : le second apporte surtout la reprise après la perte d'un pod, pas la répartition de la charge — à écrire dans `performance.md`.
</details>

<details><summary>Indice 2</summary>

GitLab envoie le secret dans l'en-tête `X-Gitlab-Token`. Si l'événement reste en échec, lis sa réponse dans l'interface de GitLab : refus de GitLab lui-même (« Requests to the local network are not allowed ») avant tout envoi, délai dépassé (bordure, politique réseau du serveur), erreur TLS (racine de confiance de GitLab), ou `400` d'Argo CD (secret différent).
</details>

<details><summary>Indice 3</summary>

L'API des webhooks de projet de GitLab : `GET /projects/:id/hooks` pour trouver un webhook existant par son URL, `POST` pour créer, `PUT /projects/:id/hooks/:hook_id` pour mettre à jour. Le jeton secret n'est jamais renvoyé par l'API : un script idempotent le réécrit à chaque passage.
</details>

**Pour aller plus loin** (facultatif) : le webhook du contrôleur d'ApplicationSets (générateurs Git, port 7000, à exposer à part) ; `controller.sharding.algorithm: consistent-hashing` et la distribution dynamique (alpha) ; `reposerver.parallelism.limit` et `ARGOCD_EXEC_TIMEOUT` ; [High Availability](https://argo-cd.readthedocs.io/en/stable/operator-manual/high_availability/), [Webhook Configuration](https://argo-cd.readthedocs.io/en/stable/operator-manual/webhook/).

---

### M20-E28 — Sauvegarder et reconstruire Argo CD  `LAB` `★★★`

> **Ticket PLAT-2128** — *De : Claire Morel* — *Copie : Nadia Roussel, Sophie Laurent*
> On dit partout que « tout est dans Git ». Prouve-le : je veux qu'on désinstalle complètement Argo CD — espace, CRD, tout — et qu'on le reconstruise, sans qu'un seul pod de production ne redémarre. Et si Git ne suffit pas, je veux savoir ce qui manque et comment on le sauvegarde. Nadia veut le runbook.

**Objectifs pédagogiques**
- Distinguer ce qui se reconstruit depuis Git et le Vault, et ce qui n'existe que dans le cluster (mots de passe des comptes locaux, clé de signature des sessions et des jetons).
- Sauvegarder l'état d'Argo CD (`argocd admin export`) chiffré, hors du cluster, automatiquement.
- Désinstaller Argo CD **sans** suppression en cascade : finaliseurs, ApplicationSets en `--cascade=orphan`, ordre des opérations ; puis le reconstruire et retrouver l'état `Synced` sans recréer de pods.

**Prérequis** : M20-E26, M20-E27 ; M14-E24 (stockage objet `s3-01`, identités sans droit de suppression) ; M16 (Velero, pour comparer).
**Durée indicative** : 4 h.

**Contexte technique**
- `argocd admin export` écrit en YAML : les ConfigMaps `argocd-cm`, `argocd-rbac-cm`, `argocd-ssh-known-hosts-cm`, `argocd-tls-certs-cm`, le Secret `argocd-secret` et les Secrets étiquetés `argocd.argoproj.io/secret-type` (dépôts, identifiants, clusters), les AppProjects, Applications et ApplicationSets. **Il contient des secrets** : il se chiffre avant de quitter le cluster. `argocd admin import` le relit (avec `--dry-run`).
- L'image d'Argo CD contient `gpg` (mais ni client S3 ni `curl`) ; l'image `rclone/rclone` (cache `dockerhub`) envoie un fichier vers un stockage S3.
- Destination : `s3-01`, compartiment **`argocd-sauvegardes`** (versionné), identité **`argocd-sauvegardes`** sans droit de suppression (rôle `seaweedfs`, méthode du M14-E24 ; politique du compartiment dans `plateforme/infra`, `outils/s3/politique-argocd-sauvegardes.json`) ; sur `adm01`, `~/.config/workbook/s3-argocd-sauvegardes.env` (600). Flux `K8S_TRAV` → `s3-01` 8333 : déjà ouvert (M16).
- Les Applications portent (ou non) le finaliseur `resources-finalizer.argocd.argoproj.io` ; les Applications générées par un ApplicationSet n'en portent pas si `preserveResourcesOnDeletion: true` (M20-E10). Le chart installe les CRD avec `helm.sh/resource-policy: keep`.
- Runbook attendu : `docs/livraison/gitops/runbooks/RB-201-reconstruire-argo-cd.md`.

> ⚠️ **Attention — lis tout avant de commencer.** (1) Si une Application qui porte le finaliseur est supprimée **pendant que le contrôleur tourne**, Argo CD supprime **toutes** ses ressources : pour `mediagenda-prod`, la production, base CNPG comprise (le volume suit la politique de récupération de sa classe de stockage). (2) Si le contrôleur est arrêté, la même suppression reste bloquée (finaliseur), l'espace `argocd` reste en `Terminating`, et la reconstruction est impossible tant que tu n'as pas retiré les finaliseurs. (3) L'application racine (*App of Apps*) avec `prune` supprime les Applications enfants dont elle perd la trace. Ordre de sûreté : **arrêter** les contrôleurs, **retirer** les finaliseurs, **orpheliner** les ApplicationSets, **vérifier** (aucun finaliseur restant), puis seulement supprimer. Avant de commencer : instantané etcd vérifié, sauvegarde Velero des espaces `mediagenda-*` et `medidoc-*` (M16), export d'Argo CD chiffré et **relu** (déchiffré sur `adm01`), et le relevé des UID des pods des espaces applicatifs. Retour arrière à chaque étape écrit dans ton journal **avant** de la faire.

**Travail demandé**
1. **Inventaire.** Dans `RB-201`, dresse la liste de **tout** ce qui fait Argo CD et d'où chaque élément revient : Helmfile (release, valeurs, politique RBAC), `composants/reseau/politiques/argocd.yaml`, Vault + `secrets-k8s.sh` (identifiants des dépôts, cluster `lyo-k3s01`, secret des webhooks), `plateforme/gitops` (projets, ApplicationSets, Applications) via l'application racine, l'Application racine elle-même (créée à la main en M20-E06 : où est son manifeste ?) — et ce qui ne revient de nulle part : les mots de passe des comptes locaux, `server.secretkey` (signature des sessions **et des jetons d'API**, dont celui de `ci-lecture`). Que se passe-t-il pour `argocd-checks.token` si `server.secretkey` change ?
2. **Sauvegarde automatique.** Un CronJob **`argocd-export`** dans `argocd` (manifestes dans `plateforme/k8s`, `composants/argocd-sauvegarde/`) : un conteneur d'initialisation (image d'Argo CD) fait `argocd admin export` et chiffre le fichier avec la clé **publique** GPG de sauvegarde (ConfigMap) ; le conteneur principal (`rclone`) l'envoie vers `argocd-sauvegardes` sous un nom horodaté. Compte de service dédié, Role en lecture limité à ce que l'export lit, Secret S3 par `secrets-k8s.sh`, politique réseau (API du cluster pour l'un, `s3-01:8333` pour l'autre). Clé privée en Vault `critique`, jamais dans le cluster. Une exécution par jour ; lance-en une à la main (`kubectl create job --from=cronjob/argocd-export`), récupère l'objet sur `adm01`, déchiffre-le, relis-le.
3. **Préparation.** Relève les UID et dates de création des pods et des Deployments de `mediagenda-dev`, `mediagenda-recette`, `mediagenda-prod`, `medidoc-dev`, `medidoc-recette` (si E33 est fait) et `agence` sur `lyo-k3s01` dans `docs/livraison/gitops/tests/reconstruction-argo-cd.md`. Vérifie quelles Applications portent un finaliseur.
4. **Désinstallation contrôlée.** En suivant ton RB-201 : contrôleurs d'Applications et d'ApplicationSets à 0 réplica ; finaliseurs retirés de toutes les Applications (vérifie : plus aucun) ; ApplicationSets supprimés avec `--cascade=orphan` ; Applications puis AppProjects supprimés ; release supprimée (`helmfile -e par1 -l composant=argocd destroy`) ; CRD d'Argo CD supprimées ; espace `argocd` supprimé. À chaque étape, contrôle que les pods applicatifs n'ont pas bougé.
5. **Reconstruction.** Espace (`task espaces`), politiques réseau, `helmfile apply`, `secrets-k8s.sh appliquer argocd`, restauration de `argocd-secret` depuis l'export déchiffré (et pas le reste de l'export : pourquoi ?), Application racine. Suis le retour à `Synced`/`Healthy` de chaque Application (`argocd app list`, `argocd app diff`), sans synchroniser à la main ce qui n'est pas `Synced` avant d'avoir compris pourquoi. Chronomètre chaque étape.
6. **Après.** Compare les UID et dates relevés : aucun pod applicatif recréé ? `ci-lecture` répond-il avec son ancien jeton ? Le cluster `lyo-k3s01` est-il `Successful` ? Les webhooks fonctionnent-ils (réponse 2xx au prochain *push*) ? Complète le compte rendu (durées, RTO mesuré, écarts) et RB-201 (quand reconstruire et quand **ne pas** le faire, préalables, ordre exact, retour arrière, vérifications).

**Critères de réussite**
- [ ] Le CronJob `argocd-export` existe, sa dernière exécution a réussi il y a moins de 26 h, et `argocd-sauvegardes` contient un objet de moins de 26 h **chiffré** (en-tête OpenPGP) ; une suppression avec l'identité `argocd-sauvegardes` est refusée.
- [ ] Argo CD a été reconstruit : ses CRD sont plus récentes que celles d'Argo Rollouts, et le StatefulSet du contrôleur plus récent que les Deployments `mediagenda` des trois espaces `mediagenda-*`, que le Rollout de production et que les pods de la base `mediagenda-db` de production, qui n'ont pas été recréés.
- [ ] L'Application `racine` et toutes les Applications de `mediagenda` sont `Synced`/`Healthy` ; le jeton `ci-lecture` d'avant la reconstruction est toujours accepté.
- [ ] RB-201 et le compte rendu de reconstruction (durées, RTO) sont sur `main` de `plateforme/medisphere` ; les manifestes de `composants/argocd-sauvegarde/` sur `main` de `plateforme/k8s`.

**Vérification** : `lab/bin/check 20 28`

<details><summary>Indice 1</summary>

L'export est un flux YAML de plusieurs documents. `yq 'select(.kind == "Secret" and .metadata.name == "argocd-secret")'` en extrait le Secret principal ; avant de l'appliquer, retire de ses métadonnées ce qui ne doit pas être réappliqué (`resourceVersion`, `uid`, `creationTimestamp`) — vérifie si l'export les contient déjà ou non. Réappliquer tout l'export recréerait aussi les Applications **avant** l'application racine : à éviter, la racine doit rester la source.
</details>

<details><summary>Indice 2</summary>

Pour retirer les finaliseurs d'un coup : `kubectl get applications.argoproj.io -n argocd -o name | xargs -r -I{} kubectl patch {} -n argocd --type merge -p '{"metadata":{"finalizers":null}}'`. Puis `kubectl get applications.argoproj.io -n argocd -o json | jq '[.items[] | select(.metadata.finalizers)] | length'` doit valoir 0 **avant** toute suppression. Et si l'application racine est encore réconciliée à ce moment-là, que fait-elle des finaliseurs écrits dans Git ?
</details>

<details><summary>Indice 3</summary>

Si une Application reste `OutOfSync` après la reconstruction alors que rien n'a changé dans Git, regarde le diff : souvent un champ que le contrôleur ignorait grâce à un réglage d'`argocd-cm` (`ignoreDifferences` globaux) ou une étiquette de suivi. Si les ressources n'ont pas l'annotation `argocd.argoproj.io/tracking-id` attendue (nom d'Application changé, autre méthode de suivi), Argo CD ne les reconnaît pas comme siennes.
</details>

**Pour aller plus loin** (facultatif) : reconstruire sur un **autre** cluster (qu'est-ce qui change pour `in-cluster`, pour les identifiants des dépôts ?) ; Velero pour sauvegarder l'espace `argocd` et ses CRD, et pourquoi ce n'est pas suffisant seul ; [Disaster Recovery](https://argo-cd.readthedocs.io/en/stable/operator-manual/disaster_recovery/), [App Deletion](https://argo-cd.readthedocs.io/en/stable/user-guide/app_deletion/), [ApplicationSet — Application Deletion](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Application-Deletion/).

---

### M20-E29 — Fenêtres de synchronisation et gel des changements  `LAB` `★★`

> **Ticket CHG-2129** — *De : Claire Morel* — *Copie : Julien Petit, Nadia Roussel*
> Règle de la maison, valable pour tout ce qui touche la production : pas de mise en production du vendredi 16 h au lundi 8 h, ni pendant un gel annoncé (fin d'année, audit HDS). Mais l'astreinte doit pouvoir corriger un incident à 3 h du matin un samedi. Je veux que la règle soit appliquée par l'outil, pas par la mémoire des gens, et écrite.

**Objectifs pédagogiques**
- Configurer des fenêtres de synchronisation (`syncWindows`) d'AppProject : `allow`/`deny`, planification cron, durée, fuseau horaire, sélection par application, espace ou cluster, `manualSync`.
- Comprendre ce qu'une fenêtre bloque (synchronisations automatiques, manuelles, auto-réparation) et ce qu'elle ne bloque pas (Argo Rollouts, `kubectl`).
- Organiser un gel des changements par ticket et une dérogation d'urgence tracée.

**Prérequis** : M20-E07 (AppProjects), M20-E10 (synchronisation manuelle de la production), M20-E24 (RBAC).
**Durée indicative** : 2 h.

**Contexte technique**
- Champs d'une fenêtre (CRD 3.5) : `kind` (`allow` ou `deny`), `schedule` (cron à cinq champs), `duration`, `applications`, `namespaces`, `clusters` (motifs), `manualSync`, `timeZone`, `andOperator`, `description`, `syncOverrun`.
- Lecture : `argocd proj windows list <projet>`, `argocd app get <application>` (lignes `SyncWindow` et `Assigned Windows`), API `GET /api/v1/projects/<projet>/syncwindows`.
- Les AppProjects vivent dans `plateforme/gitops/projets/` : une fenêtre est une MR.

**Travail demandé**
1. **Lecture.** *Sync Windows* : écris dans `politique-changements.md` comment se combinent plusieurs fenêtres (`allow` et `deny`), ce que fait `manualSync`, ce que fait `syncOverrun`, et ce qu'une fenêtre ne bloque pas. Comment une durée fixe se comporte-t-elle au passage à l'heure d'été ou d'hiver ?
2. **Fenêtre hebdomadaire.** Dans les AppProjects `mediagenda` et `medidoc` : une fenêtre `deny` qui couvre du vendredi 16:00 au lundi 08:00, heure de Paris, pour les Applications de production, avec synchronisation manuelle permise (astreinte) et une description qui cite le ticket. MR, fusion, puis vérifie avec `argocd proj windows list` et `argocd app get mediagenda-prod`.
3. **Essais.** Pour tester sans attendre vendredi, ajoute **sur une branche** une fenêtre `deny` active maintenant (durée 30 min) qui vise `mediagenda-recette` (synchronisation automatique) : pousse une modification triviale dans l'overlay `recette` et observe ce qui se passe (synchronisation automatique, auto-réparation après un `kubectl scale`) ; puis une synchronisation manuelle avec et sans `manualSync`. Retire la fenêtre d'essai. Que devient la modification bloquée quand la fenêtre se ferme ?
4. **Gel.** Écris la procédure de gel : une MR qui ajoute une fenêtre `deny` sur toute la production avec la référence du ticket CHG dans `description`, sa date de fin, et la MR inverse préparée ; la dérogation d'urgence (qui peut synchroniser pendant un gel, comment c'est tracé : ticket INC, commentaire dans la MR, `argocd app sync` par un compte nominatif). Montre comment le RBAC (E24) et les fenêtres se complètent.
5. **Document.** `docs/livraison/gitops/politique-changements.md` : règle, fenêtres en place (copie de `argocd proj windows list`), procédure de gel, dérogation, et ce que la règle **ne couvre pas** (Argo Rollouts qui poursuit un canary commencé avant la fenêtre, `kubectl` d'un administrateur, la couche de base sous Helmfile).

**Critères de réussite**
- [ ] Les AppProjects `mediagenda` et `medidoc` ont une fenêtre `deny` : planification `0 16 * * 5` (ou équivalent), durée de 64 h, fuseau `Europe/Paris`, `manualSync` activé, limitée aux Applications de production (motif qui couvre `mediagenda-prod` et pas `mediagenda-dev`).
- [ ] Aucune fenêtre d'essai ne reste sur `mediagenda-recette` ou `mediagenda-dev`.
- [ ] `docs/livraison/gitops/politique-changements.md` (règle, gel, dérogation, limites) est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 20 29`

<details><summary>Indice 1</summary>

Une fenêtre `deny` démarre à chaque déclenchement de son cron et dure `duration`. Du vendredi 16:00 au lundi 08:00 : combien d'heures ? Le cron est évalué dans `timeZone` ; la durée, elle, est une durée réelle.
</details>

<details><summary>Indice 2</summary>

`manualSync: true` laisse passer une synchronisation **manuelle** pendant une fenêtre `deny` ; les synchronisations automatiques (et l'auto-réparation) restent bloquées. La question devient : **qui** a le droit de synchroniser à la main la production ? C'est le RBAC qui répond.
</details>

**Pour aller plus loin** (facultatif) : une fenêtre `allow` de mise en production (mardi et jeudi, 10:00-12:00) plutôt qu'un `deny` ; Kargo (fiche de promotion de l'ADR-0200) et ses étapes de vérification ; [Sync Windows](https://argo-cd.readthedocs.io/en/stable/user-guide/sync_windows/).

---

### M20-E30 — Retirer à la CI tout accès en écriture aux applications  `LIBRE` `★★★`

> **Ticket SEC-2130** — *De : Sophie Laurent* — *Copie : Karim Benali, Julien Petit*
> Depuis le M19, la CI peut encore écrire dans `mediagenda-dev` par l'agent GitLab. Maintenant qu'Argo CD fait tout, je veux qu'un jeton de CI volé ne puisse **rien** changer à nos applications : il pourra au mieux ouvrir une MR, qui sera relue. Et je veux la preuve qu'aucun objet applicatif n'a été modifié par autre chose qu'Argo CD et les contrôleurs de Kubernetes.

**Objectifs pédagogiques**
- Concevoir un modèle où la CI n'a plus que des droits de **proposition** (MR) et de **validation**, et en faire la preuve.
- Retirer des droits sans casser ce qui en dépend encore (`wb-essais`, `formation/ci-labo`).
- Lire et nettoyer les gestionnaires de champs (`managedFields`) laissés par l'histoire d'un objet.

**Prérequis** : M19-E17 (promotion par MR, jeton `ci-promotion`), M19-E18 (agent `k8s-par1`, `ci_access`, RBAC de l'agent), M19-E29 (porte de vérification des signatures), M20-E08 (adoption de `mediagenda-dev`), M20-E33 si fait (MédiDoc).
**Durée indicative** : 3 h.

**Contexte**
- L'agent `k8s-par1` (espace `gitlab-agent`) est configuré par `.gitlab/agents/k8s-par1/config.yaml` de `plateforme/k8s` ; son compte de service a reçu des droits par RoleBindings (M19-E18). Le job `deployer-dev` a été retiré du pipeline de `mediagenda/deploiement` en M20-E08.
- Les objets applicatifs gérés par Argo CD avec `ServerSideApply=true` sont écrits par le gestionnaire de champs `argocd-controller`. Les contrôleurs de Kubernetes et d'Argo Rollouts écrivent aussi (statut, réplicas) sous leurs propres noms.
- La synchronisation d'Argo CD ne migre automatiquement que les champs d'un gestionnaire **client-side** (`kubectl-client-side-apply`, opération `Update`) ; les champs posés par `kubectl apply --server-side` (gestionnaire `kubectl`, opération `Apply`) au M17 et au M19 restent co-détenus.

**Exigences**
1. L'agent `k8s-par1` ne donne plus d'accès CI qu'au projet `formation/ci-labo`, et son compte de service n'a de droits d'écriture que dans `wb-essais` : plus aucun RoleBinding ni ClusterRoleBinding qui lui donne quoi que ce soit dans `mediagenda-*`, `medidoc-*`, `argocd`, `argo-rollouts`.
2. Les pipelines de `mediagenda/deploiement` et `medidoc/deploiement` ne font plus que **valider** (rendu Kustomize, schémas, vérification des signatures des images de l'overlay modifié) ; aucun job ne parle à l'API du cluster ; la promotion reste une MR (jeton `ci-promotion`, sans droit sur le cluster).
3. Sur les Deployments, StatefulSets et Services des espaces `mediagenda-*` et `medidoc-*`, plus aucun gestionnaire de champs humain ou de CI (`kubectl`, `kubectl-*`, `helm`, `gitlab*`, `agentk`) : seuls Argo CD et des contrôleurs. Le nettoyage ne doit supprimer **aucun** champ en vigueur (prouve-le avant de l'appliquer).
4. Une fois fait, un essai d'écriture avec le contexte de l'agent depuis un job de `formation/ci-labo` dans `mediagenda-dev` est refusé ; le même dans `wb-essais` réussit.
5. Livrable : `docs/livraison/gitops/acces-ci.md` — qui peut écrire quoi dans le cluster, par quel chemin (Argo CD, contrôleurs, plateforme par Helmfile, bris de glace), avec les preuves (`kubectl auth can-i`, essais, extraits des `managedFields`) et la procédure de revue trimestrielle.

**Contraintes**
- Tout par MR (agent, pipelines, RBAC de la plateforme) ; aucun Secret dans un dépôt.
- `formation/ci-labo` continue de déployer dans `wb-essais`.
- Aucune interruption de MédiAgenda, aucune synchronisation forcée de la production pendant les heures ouvrées.

**Critères de réussite**
- [ ] La configuration de l'agent sur `main` de `plateforme/k8s` ne cite plus les groupes ni les projets `mediagenda` et `medidoc` ; aucun RoleBinding d'un espace `mediagenda-*`/`medidoc-*`/`argocd`/`argo-rollouts` et aucun ClusterRoleBinding d'écriture ne vise un compte de service de l'espace `gitlab-agent`.
- [ ] Le dernier pipeline de `main` de `mediagenda/deploiement` a réussi, contient un job de validation et aucun job de déploiement ; son `.gitlab-ci.yml` ne contient ni `kubectl apply` ni contexte d'agent.
- [ ] Aucun Deployment, StatefulSet ou Service de `mediagenda-*` et `medidoc-*` n'a de gestionnaire de champs `kubectl*`, `helm`, `agentk` ou `gitlab*`.
- [ ] `docs/livraison/gitops/acces-ci.md` est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 20 30`

**Pour aller plus loin** (facultatif) : une ValidatingAdmissionPolicy qui refuse toute écriture dans les espaces applicatifs par une identité autre que le compte de service du contrôleur d'Argo CD et les contrôleurs (et son exception de bris de glace) ; [Server-Side Apply — field management](https://kubernetes.io/docs/reference/using-api/server-side-apply/#field-management).

---

### M20-E31 — ADR : Argo CD, Flux et le modèle de promotion  `RED` `★★`

> **Ticket PLAT-2131** — *De : Karim Benali*
> On a maintenant pratiqué Argo CD en profondeur et Flux en comparaison (E23). Avant le mini-projet, je veux l'ADR qui fige nos choix GitOps : l'outil, le modèle de promotion, ce qui reste sous Helmfile, ce qu'on fait des Secrets jusqu'au M25. Avec les chiffres et les incidents du module, pas des listes de fonctionnalités.

**Objectifs pédagogiques**
- Argumenter un choix d'outil GitOps sur des critères d'exploitation mesurés.
- Décider d'un modèle de promotion entre environnements et de ses limites, et dire quand le revoir.

**Prérequis** : M20-E14 (promotion), M20-E23 (Flux, `comparatif-flux.md`), M20-E24 à E29.
**Durée indicative** : 2 h.

**Travail demandé**

Rédige `docs/livraison/gitops/adr/ADR-0200-gitops.md` (contexte, options, décision, conséquences, révision) :
1. **Outil** : Argo CD, Flux, et « rien » (la CI applique, comme au M19) : modèle de sécurité (où sont les droits d'écriture), multi-locataire (projets, RBAC, interface), multi-cluster, observabilité de l'état, coût d'exploitation mesuré (mémoire, incidents du palier), écosystème (Rollouts, notifications). Kargo est cité pour la promotion.
2. **Modèle de promotion** : MR qui recopie un **digest** d'overlay en overlay (`outils/promouvoir.sh`), synchronisation manuelle de la production ; alternatives (branches par environnement, étiquettes Git, Kargo, *Source Hydrator* en bêta) et pourquoi on ne les retient pas maintenant.
3. **Frontière Helmfile / Argo CD** : ce qui reste sous Helmfile (couche de base et Argo CD lui-même) et pourquoi ; ce qui passe sous Argo CD (applications, puis services de plateforme des M21-M23).
4. **Secrets** : hors Git (`secrets-k8s.sh` + Vault `critique`) jusqu'au M25, ce que ça coûte (reconstruction E28, rotation), et ce que le M25 changera (External Secrets).
5. **Révision** : à quelles conditions l'ADR serait remplacée (nombre de clusters, d'équipes, arrivée du SSO, version 3.6).

**Critères de réussite**
- [ ] Chaque option est évaluée sur les mêmes critères, dont au moins trois mesures ou incidents réels du module (E23, E27, E28 par exemple), cités.
- [ ] Le modèle de promotion, la frontière Helmfile/Argo CD et la gestion des Secrets sont décidés, avec leurs conséquences.
- [ ] Les conditions de révision de l'ADR sont écrites ; l'ADR est sur `main` de `plateforme/medisphere`.

<details><summary>Indice 1</summary>

Pour Flux, reprends ton comparatif d'E23 : pas d'interface native, CRD par source, *pull* aussi, multi-locataire par comptes de service et impersonation (que l'on n'a pas en GitLab Free côté agent, mais que Flux fait côté Kubernetes). Pour Argo CD : ce que t'ont coûté E25 (flux réseau), E27 (mémoire de la HA) et E28 (ce qui n'est pas dans Git).
</details>

<details><summary>Indice 2</summary>

La question « branches par environnement » revient toujours. Demande-toi ce que devient une correction faite en `prod` (cherry-pick ?), comment on voit l'écart entre environnements (un `diff` de deux dossiers contre un `git log` de deux branches), et qui fusionne quoi avec GitLab Free.
</details>

---

### M20-E32 — Questions de production : GitOps  `Q` `★★★`

> **Ticket PLAT-2132** — *De : Karim Benali*
> Avant de te laisser l'astreinte d'Argo CD, je veux t'entendre sur ces questions. Argumente, chiffre quand c'est possible, et dis de quoi dépend le « ça dépend ».

**Objectifs pédagogiques**
- Raisonner sur le comportement en production d'une plateforme GitOps : pannes d'Argo CD, de Git, du registre, droits, promotions, Secrets.
- Relier les choix du module à des risques concrets.

**Prérequis** : paliers 1 et 2, M20-E24 à E31.
**Durée indicative** : 1 h 30.

**Questions**

1. Argo CD est entièrement arrêté pendant deux heures (contrôleur, serveur, *repo-server*). Que deviennent les applications en production ? Qu'est-ce qui ne fonctionne plus (cite au moins quatre choses) ? Qu'est-ce qui continue sans lui ?
2. QCM — GitLab (`git01`) est indisponible depuis 30 minutes. Argo CD :
   a) supprime les ressources des Applications dont il ne peut plus lire le dépôt ;
   b) garde les ressources en place, signale une erreur de comparaison, et ne peut plus synchroniser de changement ;
   c) synchronise depuis le cache du *repo-server* jusqu'à 24 h, comme si de rien n'était ;
   d) passe toutes les Applications en `Degraded`.
   Justifie, et dis ce que change le cache du *repo-server* dans ce scénario.
3. Un développeur supprime par erreur le dossier `overlays/recette` dans une MR fusionnée. `mediagenda-recette` a `prune` et `selfHeal`, l'ApplicationSet est un générateur de dossiers Git avec la politique `create-update`. Que se passe-t-il, objet par objet ? Et si la politique était `sync` ? Comment l'éviter ?
4. Pourquoi `prune: true` est-il raisonnable en `dev` et discutable en production ? Quelles protections intermédiaires existent (options de synchronisation, annotations), et laquelle choisirais-tu pour la base CNPG de production ?
5. QCM — Un attaquant obtient le jeton de `ci-promotion` (portées `api` et `write_repository` sur `mediagenda/deploiement`). Il peut :
   a) déployer directement une image en production ;
   b) ouvrir une MR qui change le digest de production, que la CI validera si l'image est signée ;
   c) pousser directement sur `main` ;
   d) modifier la fenêtre de synchronisation de la production.
   Justifie chaque lettre, et dis ce qui l'arrête dans le cas b).
6. Les Secrets ne sont pas dans Git. Cite trois conséquences concrètes de ce choix pour la reconstruction (E28), la rotation et la revue de code, et ce que le M25 apporte.
7. `selfHeal` est activé en `recette`. Un collègue fait `kubectl scale deployment mediagenda --replicas=0` pour un test de charge. Que se passe-t-il, en combien de temps ? Et si un HPA gère les réplicas avec `ignoreDifferences` sur `/spec/replicas` ?
8. Comparer « la CI applique » (push, M19) et « Argo CD tire » (pull) sur trois axes : où sont les droits d'écriture, que se passe-t-il quand quelqu'un modifie le cluster à la main, que se passe-t-il quand le déploiement échoue à moitié.
9. QCM — Tu passes le contrôleur à 3 réplicas avec 2 clusters gérés. Le troisième réplica :
   a) prend un tiers des Applications de `in-cluster` ;
   b) n'a aucun cluster à gérer avec l'algorithme par défaut et ne sert à rien ;
   c) reprend les clusters d'un réplica tombé, immédiatement ;
   d) sert de réplica en lecture pour l'interface.
   Justifie, et dis ce que change la distribution dynamique.
10. Une Application est `Synced` mais l'application ne répond pas. Comment est-ce possible ? Donne trois causes et, pour chacune, l'indicateur qui l'aurait montré (santé, analyse de Rollout, sonde).
11. Pourquoi la couche de base (Cilium, cert-manager, ceph-csi, Argo CD) reste-t-elle sous Helmfile alors que tout le reste passe sous Argo CD ? Que se passerait-il si Argo CD gérait Cilium et qu'une synchronisation de Cilium échouait à moitié ?
12. QCM — Pendant une fenêtre `deny` sans `manualSync`, l'astreinte doit corriger d'urgence la production. Les options :
    a) `argocd app sync --force` ;
    b) MR qui retire la fenêtre (ou ajoute `manualSync`), fusion, synchronisation manuelle, puis MR inverse ;
    c) `kubectl edit` du Deployment, en sachant que `selfHeal` ne le défera pas pendant la fenêtre ;
    d) suppression de l'Application et recréation.
    Classe-les de la meilleure à la pire, justifie, et dis laquelle est **parfois** acceptable et à quelle condition.
13. Un canary de production est à 25 % quand la fenêtre `deny` du vendredi s'ouvre. Que fait Argo Rollouts ? Que fait Argo CD ? Que fais-tu ?
14. Tu dois prouver à un auditeur HDS « qui a mis en production quoi, quand, et qui l'a validé ». Où trouves-tu chaque élément, combien de temps est-il conservé, et que manque-t-il avant le M22 ?

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 14 questions, en justifiant chaque QCM (y compris pourquoi les autres options sont fausses).
- [ ] Au moins cinq réponses s'appuient sur une mesure ou un essai de ce module (E25 à E29).
- [ ] Tu as noté chaque réponse (0, 1 ou 2 points) avec le corrigé et listé les notions à revoir.

<details><summary>Indice 1</summary>

Sépare toujours trois plans : ce qui **tourne** (pods, Services, Gateway : indépendants d'Argo CD), ce qui **converge** (réconciliation, auto-réparation, synchronisation), et ce qui **se voit** (interface, notifications, état). Une panne d'Argo CD ou de Git n'atteint en général que les deux derniers.
</details>

<details><summary>Indice 2</summary>

Pour les droits, demande-toi à chaque fois : quel jeton, quelles portées, quelle protection de branche, quelle relecture, et quelle vérification automatique (signature, schémas) se trouve entre ce jeton et le cluster.
</details>

Les réponses argumentées sont dans le corrigé.

---

### M20-E33 — Accueillir MédiDoc en GitOps  `LIBRE` `★★★`

> **Ticket DEV-2133** — *De : Julien Petit* — *Copie : l'équipe MédiDoc*
> L'équipe MédiDoc a son dépôt `medidoc/deploiement` depuis le M19 et un environnement de dev appliqué à la main. Elle veut le même confort que MédiAgenda : un environnement de recette, des déploiements par MR, l'état visible dans Argo CD. Sophie rappelle que MédiDoc stocke des documents patients : pas un seul identifiant S3 dans un dépôt.

**Objectifs pédagogiques**
- Accueillir une équipe dans le modèle GitOps de bout en bout : espace préparé par la plateforme, dépôt de l'équipe, projet, ApplicationSet, Secrets hors Git, politiques réseau.
- Reprendre un environnement existant (`medidoc-dev`) sans coupure et en créer un nouveau (`medidoc-recette`).

**Prérequis** : M19-E33 (`medidoc/deploiement`, base + overlay `dev`), M16-E46 (MédiDoc sur le RGW), M15-E34 et E28 (politiques de `medidoc-dev`, cloisons), M14-E33 (accueil d'une équipe), M20-E08 et E10 (reprise sans coupure, ApplicationSet), M20-E12 (Secrets hors Git).
**Durée indicative** : 3 h 30.

**Contexte**
- Espaces : `medidoc-dev` (existant) et **`medidoc-recette`** (à créer par la plateforme, avec les mêmes garde-fous que `medidoc-dev` : étiquettes d'équipe et Pod Security, quota, LimitRange, cloison `isolement-medidoc-recette`). Les politiques réseau de l'application (refus par défaut, entrée par la Gateway, sortie DNS et RGW) sont dans `base/` de `medidoc/deploiement` depuis le M19-E33.
- Stockage : MédiDoc recette écrit dans son **propre** compartiment du RGW de `ceph-par1` avec son **propre** compte (pas celui de dev) ; le Secret `medidoc-s3` (clés `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) de chaque espace est créé par `secrets-k8s.sh` à partir du Vault.
- Nom publié de la recette : `medidoc-recette.apps.par1.medisphere.internal` (HTTPRoute sur `gw-par1`, comme `medidoc-dev`).
- L'AppProject `medidoc` (M20-E07) existe dans `plateforme/gitops` ; `medidoc-dev` est encore appliqué à la main depuis `adm01` (M19-E33) : il n'a ni Application ni ApplicationSet.

**Exigences**
1. `medidoc-recette` existe avec les garde-fous de la plateforme ; ces objets (espace, quota, LimitRange, cloison) sont décrits dans `plateforme/k8s`, pas dans le dépôt de l'équipe, et l'AppProject `medidoc` interdit à l'équipe de les créer (même règle que pour MédiAgenda en M20-E07 : les politiques réseau de l'application restent à l'équipe).
2. `medidoc/deploiement` a un overlay `recette` (image par digest, deux réplicas, compartiment et nom publié de la recette) ; aucun Secret, aucun identifiant dans le dépôt (vérifiable par une recherche dans l'arbre Git).
3. L'ApplicationSet `medidoc` génère `medidoc-dev` et `medidoc-recette` (projet `medidoc`, synchronisation automatique avec `prune` et `selfHeal`, `ServerSideApply=true`) ; la reprise de `medidoc-dev` ne recrée aucun pod.
4. L'AppProject `medidoc` n'autorise que les destinations `medidoc-dev` et `medidoc-recette` de `in-cluster`, et la fenêtre de E29 reste en place pour une future production.
5. MédiDoc recette répond : `GET /readyz` → 200 par le nom publié ; un document déposé en recette n'est pas visible en dev.
6. Livrable : la fiche d'équipe `docs/kubernetes/equipes/medidoc.md` (M14-E33) mise à jour (environnements, dépôts, Application, qui synchronise quoi) et une note `docs/livraison/gitops/accueil-equipe-gitops.md` qui généralise la procédure pour la prochaine équipe.

**Contraintes**
- Aucune commande `kubectl apply` sur `medidoc-*` hors de la plateforme (espace et garde-fous) et de `secrets-k8s.sh`.
- MédiDoc dev ne doit pas être interrompu.

**Critères de réussite**
- [ ] `medidoc-recette` porte les étiquettes d'équipe et Pod Security `restricted`, un ResourceQuota, un LimitRange et un refus réseau par défaut.
- [ ] Les Applications `medidoc-dev` et `medidoc-recette`, générées par l'ApplicationSet `medidoc` (projet `medidoc`), sont `Synced`/`Healthy`.
- [ ] Aucun manifeste de `kind: Secret` dans l'arbre de `main` de `medidoc/deploiement` ; l'overlay `recette` y existe.
- [ ] Un pod MédiDoc prêt tourne dans `medidoc-recette` sur une image `registry.par1.medisphere.internal/medisphere/medidoc@sha256:…`.
- [ ] La note d'accueil GitOps est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 20 33`

**Pour aller plus loin** (facultatif) : une fenêtre `allow` propre à l'équipe ; la promotion dev → recette de MédiDoc par le composant `promotion` du M19 ; [ApplicationSet — Git Generator](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Git/).

---

### M20-E34 — Une mise en production en temps limité  `CHRONO` `★★★`

> **Ticket CHG-2134** — *De : Claire Morel* — *Copie : Julien Petit, Nadia Roussel*
> La version suivante de MédiAgenda est validée en recette. Je veux te voir la mettre en production toi-même, avec le canary et les analyses que tu as construits, la notification à l'équipe, et un compte rendu — en une heure, sans corrigé, comme un vrai changement.

**Objectifs pédagogiques**
- Enchaîner sous contrainte de temps une mise en production GitOps complète : changement, promotion par MR, canary piloté par la Gateway, analyses, notification, compte rendu.
- Mesurer ses gestes lents et ses hésitations.

**Règles de l'exercice**
- Conditions d'examen : pas de corrigé ; seulement **tes** runbooks (RB-200, RB-201), tes livrables du module et la documentation officielle (argo-cd.readthedocs.io, argoproj.github.io/argo-rollouts, rollouts-plugin-trafficrouter-gatewayapi.readthedocs.io).
- Durée : **60 minutes** entre l'ouverture du sujet (T0) et la fin (T1). Lance-le **hors** de la fenêtre `deny` de E29 (sinon, c'est la première chose à traiter, et elle compte dans ton temps).
- Tout passe par Git et par Argo CD : aucune commande `kubectl apply`, `edit`, `patch`, `scale` sur `mediagenda-*`. Les commandes `kubectl argo rollouts get|promote|abort` et les actions d'Argo CD sur le Rollout sont permises.
- Avant T0 : `lab/bin/check 20 16`, `20 18` et `20 19` verts ; `mediagenda-prod` `Synced`/`Healthy` ; une version `vX.Y.Z` de `mediagenda/api` construite, signée et validée en **recette** (overlay `recette` à jour) et **pas encore** en production.

**Prérequis** : paliers 1 à 3 du module (E14 promotion, E16 canary, E18 analyses, E19 notifications, E24 RBAC, E29 fenêtres).
**Durée** : 60 minutes chronométrées + 30 minutes de retour d'expérience.

**Sujet** : [`ressources/E34-mise-en-production/sujet.md`](../ressources/E34-mise-en-production/sujet.md) (le changement, les huit tâches, leur poids, la feuille de temps). Lis-le à T0, pas avant.

**Critères de réussite**
- [ ] `lab/bin/check 20 34`, lancé à T1, valide au moins 70 % des points (le script affiche le score par tâche).
- [ ] La feuille de temps du sujet est remplie (heure de fin de chaque tâche), avec les tâches abandonnées et pourquoi.
- [ ] Le retour d'expérience (une demi-page dans `docs/livraison/gitops/tests/mise-en-production-chrono.md`) liste les gestes lents ou hésitants et ce que tu vas travailler.

**Vérification** : `lab/bin/check 20 34` (à lancer à T1).

**Pour aller plus loin** (facultatif) : refais l'exercice une semaine plus tard avec un **retour arrière** imposé à 50 % (analyse en échec provoquée), en visant 45 minutes.
