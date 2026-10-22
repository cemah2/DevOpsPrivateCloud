# Module 20 — Palier 1 : Découverte

Avant de confier la production à un contrôleur, il faut l'avoir installé soi-même, l'avoir vu réagir à chaque situation et savoir ce qu'il fait des objets qui existent déjà. Ce palier installe Argo CD par Helmfile comme le reste de la couche de base, ouvre l'accès (interface, CLI, comptes locaux, jeton des vérifications) et ferme le compte `admin`. Il fait vivre une application d'essai dans tous ses états (synchronisation manuelle puis automatique, dérive, auto-réparation, suppression d'objets), range tout ce qu'Argo CD gère dans le dépôt `plateforme/gitops` derrière une application racine qui se gère elle-même, cloisonne les équipes par des AppProjects, puis reprend MédiAgenda dev sans redémarrer un seul pod. Le palier s'ouvre et se ferme sur un questionnaire.

Prérequis : module 19 terminé (`lab/bin/check 19 46` vert) ; modules 14 à 17 (cluster `k8s-par1`, Gateway `gw-par1` et cert-manager, Helmfile de `plateforme/k8s`, overlays de `mediagenda/deploiement`). Lis [`00-introduction.md`](00-introduction.md), en particulier le chemin imposé, les faits techniques et les règles du module.

---

### M20-E01 — Test de positionnement : déploiement et GitOps  `Q` `★★`

> **Ticket PLAT-2101** — *De : Karim Benali*
> Avant de toucher à Argo CD : une heure, par écrit, sans moteur de recherche ni IA, sans rien exécuter. Déploiement, réconciliation, Kustomize et Helm, promotion, secrets. Ce que tu crois savoir du GitOps parce que tu as lu une page de présentation compte aussi : je veux voir où tu en es, pas une note.

**Objectifs pédagogiques**
- Évaluer tes acquis sur ce que le GitOps suppose (modèle déclaratif, boucles de contrôle, *server-side apply*, rendu de manifestes, gestion des versions) avant de l'installer.
- Repérer les notions à travailler et les exercices du module qui les mobilisent.

**Prérequis** : aucun.
**Durée indicative** : 1 h (+ 30 min d'auto-correction).

**Travail demandé**

Réponds aux 18 questions. Pour les QCM, justifie ton choix en une ou deux phrases.

*Pousser ou tirer*

1. Aujourd'hui, le job `deployer-dev` (M19-E18) applique l'overlay `dev` dans le cluster depuis la CI. Décris ce modèle (*push*) et le modèle *pull* d'un contrôleur GitOps : qui détient quels identifiants, qui initie le changement, que se passe-t-il quand le cluster est modifié à la main une heure après ?

2. *(QCM)* Laquelle de ces affirmations sur le modèle *pull* est **fausse** ?
   - A. La CI n'a plus besoin d'identifiants capables d'écrire dans le cluster
   - B. Une modification faite à la main dans le cluster peut être détectée et effacée automatiquement
   - C. Le contrôleur doit être joignable depuis la forge pour recevoir les déploiements
   - D. Le contrôleur doit pouvoir lire le dépôt qui décrit l'état voulu

3. Qu'est-ce qu'une **boucle de réconciliation** ? Cite deux boucles que tu as déjà vues tourner dans `k8s-par1` sans les appeler ainsi.

4. Définis la **dérive** (*drift*). Donne trois façons dont un objet de `mediagenda-dev` peut s'écarter de Git sans que personne ne commette d'erreur dans le dépôt.

*Rendre et appliquer*

5. `mediagenda/deploiement` contient un **rendu commité** du chart `mediagenda` et des overlays Kustomize (M17-E09). Un outil GitOps doit-il savoir lancer `helm` et `kustomize` ? Que gagne-t-on, que perd-on à lui donner un rendu déjà fait plutôt qu'un chart et des valeurs ?

6. Rappelle la différence entre `kubectl apply` (*client-side*) et `kubectl apply --server-side`. Où chacun garde-t-il la mémoire de « ce que j'ai appliqué la dernière fois » ? Pourquoi est-ce important pour un outil qui applique en boucle ?

7. *(QCM)* Deux outils appliquent le même Deployment en *server-side apply*, sous deux noms de gestionnaire différents, avec des nombres de réplicas différents. Que se passe-t-il au second `apply` (sans option particulière) ?
   - A. Le second écrase silencieusement la valeur du premier
   - B. L'API refuse avec un conflit sur `spec.replicas`, sauf si le second force la reprise des champs
   - C. L'API garde la plus grande des deux valeurs
   - D. Les deux gestionnaires deviennent copropriétaires et la valeur ne change pas

8. Un objet existe dans le cluster, créé par `kubectl apply` il y a six mois. Un outil GitOps commence à le gérer à partir d'un fichier **identique**. Le pod sera-t-il recréé ? De quoi cela dépend-il ?

*Versions et promotion*

9. Pourquoi référencer une image par **digest** (`@sha256:…`) plutôt que par étiquette dans un dépôt GitOps, même quand les étiquettes `v*` sont immuables dans Harbor (M13) ?

10. Deux façons de promouvoir une version de `recette` en `prod` dans un dépôt GitOps : **une branche par environnement** (`recette`, `prod`, fusion de l'une dans l'autre) ou **un dossier par environnement** sur une seule branche (overlays). Donne un avantage et un inconvénient de chacune.

11. *(QCM)* En GitOps, comment revient-on en arrière après une mauvaise mise en production ?
    - A. On relance le pipeline de CI de la version précédente
    - B. On annule le commit de promotion (`git revert`) et le contrôleur applique l'état précédent
    - C. On utilise `kubectl rollout undo`, puis on prévient l'équipe
    - D. On supprime l'application dans l'outil GitOps et on la recrée

12. Qu'est-ce qu'une synchronisation **automatique** avec **suppression** (*prune*) ? Donne un scénario où elle détruit quelque chose qu'on voulait garder.

*Secrets et sécurité*

13. Pourquoi ne peut-on pas mettre un Secret Kubernetes tel quel dans un dépôt Git, même privé, même si « le base64, ce n'est pas lisible » ? Cite trois approches qu'on rencontre pour concilier GitOps et secrets.

14. Le contrôleur GitOps du cluster a, par construction, des droits très larges sur le cluster. Qui peut donc, indirectement, créer n'importe quel objet dans `k8s-par1` ? Quelles protections faut-il autour du dépôt ?

15. *(QCM)* Le dépôt GitOps est lu en HTTPS avec un jeton. Quelle portée de jeton GitLab convient ?
    - A. Un jeton personnel d'administrateur, portée `api`
    - B. Un jeton de déploiement, portée `read_repository`, avec une date d'expiration
    - C. Le jeton de runner `glrt-` du M19
    - D. Pas de jeton : rendre le dépôt public dans l'instance

*Ce que tu sais d'Argo CD*

16. Cite les composants d'Argo CD que tu connais, avec une phrase sur le rôle de chacun. Lequel a besoin de joindre la forge ? Lequel a besoin de droits sur l'API Kubernetes ?

17. Une application Argo CD est `Synced` et `Degraded`. Que dit chacun de ces deux statuts ? Donne un exemple concret de cette combinaison, puis un exemple de `OutOfSync` et `Healthy`.

18. Argo CD installe des CRD, des ClusterRoles et des webhooks… et pourrait se gérer lui-même par une Application. Pourquoi MédiSphère a-t-il décidé de le laisser sous Helmfile, avec la couche de base du cluster ?

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 18 questions avant d'ouvrir le corrigé.
- [ ] Tu as noté chaque réponse avec la grille (0, 1 ou 2 points) et calculé ton score sur 36.
- [ ] Tu as noté les thèmes à retravailler et les exercices du module qui les mobilisent.

<details><summary>Indice 1</summary>

Pour les questions 1 à 4, raisonne sur « qui a le dernier mot » : la personne qui tape une commande, le pipeline qui vient de passer, ou un programme qui compare en permanence deux états.
</details>

<details><summary>Indice 2</summary>

Pour les questions 6 à 8, relis ce que tu as observé au M17 (`managedFields`, `kubectl diff --server-side`) : un objet appliqué en *server-side apply* garde, par champ, le nom de celui qui l'a posé.
</details>

**Pour aller plus loin** (facultatif) : refais ce test à la fin du module (M20-E46), sans relire le corrigé, et compare.

---

### M20-E02 — Installer Argo CD par Helmfile  `LAB` `★★`

> **Ticket PLAT-2102** — *De : Karim Benali* — *Copie : Sophie Laurent*
> Argo CD rejoint la couche de base : une release Helmfile `argocd` dans `plateforme/k8s`, comme cert-manager ou Cilium, relue en MR. Les images passent par Harbor, pas de Dex (le SSO, c'est pour le M24), un réplica partout pour l'instant, des ressources demandées et plafonnées. On le publie sur `argocd.apps.par1.medisphere.internal` derrière `gw-par1`, avec notre certificat. Je sais que le chart sait générer son propre certificat et faire du TLS de bout en bout : écris-moi pourquoi on ne le fait pas, et ce qu'on perd. Et je veux voir le `helmfile diff` avant l'`apply`.

**Objectifs pédagogiques**
- Lire un chart tiers avant de l'installer : valeurs par défaut, images, objets créés, ce qui diffère des habitudes de MédiSphère.
- Ajouter une release à un Helmfile existant (base commune, environnement, valeurs par composant).
- Publier un service par la Gateway API avec TLS terminé à la Gateway, et en mesurer les conséquences.
- Vérifier qu'une installation respecte les règles de la plateforme (Pod Security, images, ressources).

**Prérequis** : M17-E10 (Helmfile de `plateforme/k8s`) ; M15-E12 à E15 (Gateway `gw-par1`, joker, ExternalDNS) ; M14-E10 (espaces de noms par `task espaces`) ; M14-E14 (PriorityClasses).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Chart | `argo/argo-cd` **10.10.5** (Argo CD v3.5.5), dépôt `https://argoproj.github.io/argo-helm` |
| Fichiers | `plateforme/k8s` : `releases/argocd.yaml.gotmpl` (inclut `_communs.yaml` en base, comme les autres fichiers de `releases/`), `composants/argocd/values.yaml`, `espaces/argocd.yaml` ; étiquettes de release `groupe=livraison`, `composant=argocd` |
| Espace | `argocd` : PSA `restricted` appliqué, étiquette `medisphere.internal/exposition: oui`, pas d'étiquette d'équipe |
| Images | caches Harbor : `quay` pour Argo CD, `dockerhub` pour Redis |
| Publication | HTTPRoute vers le Service `argocd-server` sur `passerelles/gw-par1`, écouteur `https`, nom `argocd.apps.par1.medisphere.internal` ; ExternalDNS publie le nom |
| Racine MédiSphère | à fournir à Argo CD pour lire `git01` (et, au palier 2, les charts OCI de `registry.par1.medisphere.internal`) : fichier public `/usr/local/share/ca-certificates/medisphere-root-ca.crt` de `adm01` |

**Travail demandé**

*A. Lire le chart avant d'écrire*

1. Ajoute le dépôt et lis les valeurs par défaut du chart, à la version visée :
   ```
   admin@adm01:~$ helm repo add argo https://argoproj.github.io/argo-helm && helm repo update argo
   admin@adm01:~$ helm show values argo/argo-cd --version 10.10.5 > ~/m20/e02/values-defaut.yaml
   admin@adm01:~$ helm template argocd argo/argo-cd --version 10.10.5 -n argocd > ~/m20/e02/rendu-defaut.yaml
   ```
   Dans ton journal : la liste des objets rendus par type (`grep '^kind:' … | sort | uniq -c`), les images et leurs registres, ce que font par défaut Dex, Redis, les NetworkPolicy, le compte `admin`, le TLS du serveur (`configs.params`), les ressources (*requests*/*limits*). Quels objets sont des **hooks** Helm, et que font-ils ?
2. Vérifie que les images passent par les caches Harbor **avant** d'installer : `skopeo inspect --format '{{.Digest}}' docker://registry.par1.medisphere.internal/quay/argoproj/argocd:v3.5.5`, et de même pour Redis par le cache `dockerhub`. Le chart tire Redis d'un autre registre que Docker Hub : lequel, et pourquoi peux-tu quand même passer par le cache `dockerhub` ?

*B. La release*

3. Écris `espaces/argocd.yaml` et applique-le (`task espaces`). Vérifie, avant l'installation, que les pods du rendu respectent `restricted` : `kubectl apply --dry-run=server` d'un rendu sur un espace `restricted` affiche les avertissements de Pod Security, ou lis les `securityContext` du rendu.
4. Écris `composants/argocd/values.yaml` : uniquement ce qui diffère des défauts, chaque écart justifié en commentaire. Exigences :
   - images par les caches Harbor ; PriorityClass `medisphere-critique` ; journaux au format JSON ;
   - Dex désactivé ; compte `admin` encore actif (E03 le fermera) ; terminal web désactivé ; suivi des ressources par annotation, écrit explicitement ;
   - un réplica pour chaque composant ; des demandes et des limites de mémoire pour chaque composant (justifie tes chiffres) ;
   - serveur en HTTP derrière la Gateway (`server.insecure`) ; HTTPRoute fournie par le chart (cherche `httproute` dans les valeurs), attachée à l'écouteur `https` de `gw-par1`, nom `argocd.apps.par1.medisphere.internal`.
5. Écris `releases/argocd.yaml.gotmpl` sur le modèle des autres fichiers de `releases/` : base `_communs.yaml`, dépôt `argo`, chart épinglé, étiquettes, valeurs. Le domaine (`global.domain`) vient de l'environnement (`domaineApps`). La racine MédiSphère doit atterrir dans `configs.tls.certificates` pour les noms `git01.par1.medisphere.internal` et `registry.par1.medisphere.internal` : versionne une copie du certificat **public** dans `composants/argocd/` et lis-la depuis le gabarit.
6. Lis le rendu Helmfile (`helmfile -e par1 -l composant=argocd template`) : ta route, tes images, ta ConfigMap `argocd-tls-certs-cm`. Puis `diff`, MR, relecture, fusion, et :
   ```
   admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=argocd diff
   admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=argocd apply
   ```
   Suis le démarrage : `kubectl --context k8s-par1 -n argocd get pods -w`. Quels pods démarrent en premier, et pourquoi le *Job* `argocd-redis-secret-init` passe-t-il avant tous les autres ?

*C. Constater*

7. La route : `kubectl -n argocd get httproute argocd-server -o yaml` (conditions `Accepted`, `ResolvedRefs`) ; le nom : `dig +short argocd.apps.par1.medisphere.internal` ; le service : `curl -sS https://argocd.apps.par1.medisphere.internal/healthz`. Ouvre l'interface dans le navigateur de ton poste (par le VPN) : quel certificat présente-t-elle ?
8. Réponds à Karim dans le ticket : pourquoi le TLS est terminé à la Gateway plutôt que de bout en bout, ce qui circule en clair et où, ce qu'il faudrait pour du bout en bout avec la Gateway Cilium, et où tu le notes (M20-E25 y reviendra).

**Critères de réussite**
- [ ] L'espace `argocd` existe, en Pod Security `restricted` appliqué, avec l'étiquette d'exposition et sans étiquette d'équipe.
- [ ] La release `argocd` (chart 10.10.x) est installée par Helmfile ; serveur, *repo-server*, contrôleur (StatefulSet), ApplicationSet, notifications et Redis ont chacun un réplica prêt ; Dex est absent.
- [ ] Toutes les images des pods de l'espace `argocd` viennent de `registry.par1.medisphere.internal/`.
- [ ] `argocd-cmd-params-cm` porte `server.insecure: "true"`, `argocd-tls-certs-cm` la racine MédiSphère pour `git01`.
- [ ] La HTTPRoute est acceptée par `gw-par1`, le nom résout en 10.10.41.10, `https://argocd.apps.par1.medisphere.internal/healthz` répond 200 avec un certificat vérifié.
- [ ] Les trois fichiers sont sur `main` de `plateforme/k8s` ; un second `helmfile diff` est vide.

**Vérification** : `lab/bin/check 20 02`

<details><summary>Indice 1</summary>

`helm show values` est long : cherche d'abord les clés de premier niveau (`grep -n '^[a-z]' …`), puis `image:`, `resources:`, `networkPolicy`, `httproute`, `params:`. La clé `global.image.repository` s'applique à tous les composants qui utilisent l'image d'Argo CD ; Redis a la sienne.
</details>

<details><summary>Indice 2</summary>

Helmfile sait lire un fichier dans un gabarit `.gotmpl` (`readFile`), chemin relatif au fichier de release ; `nindent` en garde l'indentation dans un bloc YAML littéral (`|`). Attention : dans un fichier de `releases/`, la liste `repositories` déclarée **remplace** celle de la base au lieu de s'y ajouter (constate-le avec `helmfile … build`).
</details>

<details><summary>Indice 3</summary>

Si la route reste sans `Accepted`, relis l'étiquette de l'espace et le `sectionName`. Si `/healthz` répond mais que l'interface reste blanche ou boucle en redirections, regarde `server.insecure` : sans lui, le serveur redirige vers HTTPS et la Gateway lui parle en HTTP.
</details>

**Pour aller plus loin** (facultatif) : le chart sait aussi créer une `GRPCRoute` (`server.grpcroute`) et un second port de Service en `h2c` (`server.service.servicePortHttp2`) : de quoi utiliser la CLI sans `--grpc-web`. Essaie dans une branche, et compare les deux montages.

---

### M20-E03 — Accéder à Argo CD : interface, CLI et comptes locaux  `LAB` `★★`

> **Ticket SEC-2103** — *De : Sophie Laurent* — *Copie : Karim Benali*
> Un outil qui peut écrire partout dans le cluster ne garde pas un compte `admin` partagé dont le mot de passe traîne dans un Secret. Je veux des comptes **nominatifs** (le SSO arrive au M24, en attendant des comptes locaux), le compte `admin` désactivé, le Secret du mot de passe initial supprimé. Les vérifications automatiques du workbook passent par un compte technique en **lecture seule**, avec un jeton qui **expire**. Et la CLI sur `adm01` comme tous nos outils : version épinglée, empreinte vérifiée.

**Objectifs pédagogiques**
- Installer la CLI `argocd` par le rôle Ansible `outils_k8s`, à la version du serveur, empreinte vérifiée.
- Se connecter par l'interface et par la CLI (gRPC-web derrière une Gateway).
- Déclarer des comptes locaux, leurs capacités et leurs rôles ; régler leurs mots de passe sans les exposer.
- Créer un compte technique et un jeton d'API à durée limitée ; désactiver `admin`.
- Étendre le compte des vérifications du workbook aux objets d'Argo CD, sans accès aux Secrets.

**Prérequis** : M20-E02 ; M14-E05 (rôle `outils_k8s`), M14-E06 (compte `wb-checks`, ClusterRoles agrégées) ; M19-E02 (`wb-checks-livraison`).
**Durée indicative** : 2 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| CLI | `argocd` **3.5.5**, binaire `argocd-linux-amd64` publié seul (pas d'archive) avec `cli_checksums.txt` sur les versions GitHub d'Argo CD ; installé par `outils_k8s` dans `/opt/outils_k8s/argocd-3.5.5/`, lien `/usr/local/bin/argocd` |
| Comptes | `<MOI-ARGO>` et `karim-benali` : `login`, `role:admin` ; `julien-petit`, `nadia-roussel` : `login`, `role:readonly` (E24 affinera) ; `ci-lecture` : `apiKey` seulement, `role:readonly` ; `policy.default` vide |
| Jeton des vérifications | compte `ci-lecture`, identifiant `checks-<AAAAMMJJ>`, durée 90 jours, fichier `~/.config/workbook/argocd-checks.token` (600) |
| Mots de passe | réglés par `argocd account update-password` (saisis au clavier), conservés dans Vault `critique` (`plateforme/k8s/secrets/argocd-comptes.yml`, non lu par les scripts) |
| Vérifications | ClusterRole `wb-checks-livraison` (`plateforme/k8s/rbac/`) : ajouter la lecture des `applications`, `applicationsets`, `appprojects` d'`argoproj.io` |

**Travail demandé**

*A. La CLI*

1. Lis le fichier `cli_checksums.txt` de la v3.5.5 : quelle ligne correspond au binaire de `adm01` ? Le rôle `outils_k8s` (M14-E05) ne sait installer que des archives : ajoute-lui une liste `outils_k8s_binaires_nus` (nom, version, URL, empreinte `sha256:` écrite dans les valeurs) traitée par un fichier de tâches à part, et la complétion bash d'`argocd`. MR, puis le playbook `outils-k8s.yml` ; second passage : `changed=0`.
   ```
   admin@adm01:~$ argocd version --client --short
   ```

*B. Les comptes*

2. Ajoute les comptes et leurs rôles aux valeurs (`configs.cm`, `configs.rbac`) **sans encore désactiver `admin`**. Lis la page « Local users/accounts » de la documentation : quelles sont les deux capacités possibles d'un compte ? Que se passe-t-il pour un compte authentifié qui n'a aucun rôle quand `policy.default` est vide ?
   > ⚠️ **Attention** : écris les noms des personnes **avec des tirets** (`karim-benali`), pas avec des points. Lis la sortie de `argocd account list` après l'`apply` et explique ce qui arriverait avec `karim.benali`.
3. `helmfile diff`, MR, `apply`. Connecte-toi une première fois avec `admin` : le mot de passe initial est dans un Secret (`argocd admin initial-password -n argocd`, ou `kubectl -n argocd get secret argocd-initial-admin-secret`). Puis :
   ```
   admin@adm01:~$ argocd login argocd.apps.par1.medisphere.internal --grpc-web --username admin
   admin@adm01:~$ argocd account list
   admin@adm01:~$ argocd account update-password --account <MOI-ARGO>
   ```
   Que fait `--grpc-web`, et pourquoi ta connexion échoue-t-elle (ou se bloque) sans lui ? Où la CLI range-t-elle ta session ?
4. Reconnecte-toi avec `<MOI-ARGO>`, puis règle les mots de passe de `karim-benali`, `julien-petit`, `nadia-roussel` (tu les transmettras par le canal habituel : ils changent le leur à la première connexion). Range-les dans le Vault. Vérifie avec `argocd account get-user-info` et `argocd account can-i sync applications '*'` sous deux comptes différents.

*C. Le compte des vérifications*

5. Génère le jeton de `ci-lecture` : identifiant explicite, **durée limitée**, écrit directement dans un fichier 600, jamais affiché.
   ```
   admin@adm01:~$ install -m 600 /dev/null ~/.config/workbook/argocd-checks.token
   admin@adm01:~$ argocd account generate-token --account ci-lecture --id checks-$(date +%Y%m%d) --expires-in 90d > ~/.config/workbook/argocd-checks.token
   ```
   Teste-le sur l'API, sans le mettre en argument (l'en-tête passe par un fichier de configuration de `curl`) : `GET /api/v1/session/userinfo`, puis `GET /api/v1/account`. Comment révoque-t-on ce jeton s'il fuit ? Que contient `argocd account get --account ci-lecture` ?
6. Étends `rbac/wb-checks-livraison.yaml` (lecture des Applications, ApplicationSets et AppProjects) et applique-le (`task appliquer`). Pourquoi ces objets peuvent-ils être lus par `wb-checks` alors que les Secrets d'Argo CD, jamais ?

*D. Fermer `admin`*

7. Désactive `admin` dans les valeurs, `diff`, MR, `apply`. Vérifie qu'une connexion `admin` est refusée, puis supprime le Secret du mot de passe initial.
   > ⚠️ **Attention** : désactive `admin` seulement après avoir vérifié que `<MOI-ARGO>` se connecte et a `role:admin` (`argocd account can-i update projects '*'` → `yes`). Sinon, tu n'as plus d'administrateur : il faudrait réactiver `admin` par Helmfile (retour arrière : `admin.enabled: true`, `apply`) puis lui donner un mot de passe connu (`argocd admin` sur le cluster, voir la documentation). Le Secret initial, une fois supprimé, ne revient pas : c'est voulu.
8. Note dans `docs/livraison/gitops/acces.md` (dépôt `plateforme/medisphere`) : l'URL, la commande de connexion, les comptes et leurs rôles, le jeton des vérifications (identifiant, échéance, procédure de rotation), la procédure de bris de glace.

**Critères de réussite**
- [ ] `argocd version --client` donne 3.5.x sur `adm01`, installé par le rôle `outils_k8s` (version et empreinte dans `plateforme/ansible`).
- [ ] Les comptes `<MOI-ARGO>`, `karim-benali`, `julien-petit`, `nadia-roussel` sont actifs en connexion interactive ; `ci-lecture` n'a que la capacité `apiKey` ; aucun compte au nom tronqué.
- [ ] Le jeton de `~/.config/workbook/argocd-checks.token` (600) ouvre une session `ci-lecture`, ne permet pas de synchroniser, et a une date d'expiration.
- [ ] `admin` est désactivé (`admin.enabled: "false"` dans les valeurs et dans `argocd-cm`) ; `argocd-initial-admin-secret` n'existe plus.
- [ ] `wb-checks` liste les Applications et AppProjects, et ne lit toujours aucun Secret.

**Vérification** : `lab/bin/check 20 03`

<details><summary>Indice 1</summary>

Le module `get_url` accepte une empreinte sous la forme `sha256:<hex>` : écrite dans les valeurs du rôle, elle se met à jour avec la version, dans la même MR. Les clés de comptes vont dans `configs.cm` (elles finissent dans `argocd-cm`), les rôles dans `configs.rbac."policy.csv"` (`g, <compte>, role:<rôle>`).
</details>

<details><summary>Indice 2</summary>

Sans `--new-password`, `update-password` demande le mot de passe actuel **de la personne connectée** puis le nouveau, deux fois, au clavier. La durée de `--expires-in` s'écrit avec une unité (`h`, `d`). Un fichier de configuration `curl` peut contenir une ligne `header = "Authorization: Bearer …"` : avec une substitution de processus (`-K <(…)`), le jeton n'apparaît ni dans `ps` ni dans l'historique.
</details>

<details><summary>Indice 3</summary>

`argocd account list` montre les comptes que le serveur a compris : un nom inattendu y apparaît si une clé `accounts.…` a été mal découpée. Un compte désactivé n'a pas de champ `enabled` dans la réponse JSON de l'API (la valeur fausse est omise).
</details>

**Pour aller plus loin** (facultatif) : `argocd admin settings rbac can` teste une politique **sans serveur**, à partir des fichiers de valeurs : c'est l'outil de M20-E24. Essaie-le sur `ci-lecture` et `<MOI-ARGO>`.

---

### M20-E04 — Première Application  `LAB` `★`

> **Ticket PLAT-2104** — *De : Karim Benali*
> Avant de confier MédiAgenda à Argo CD, on apprend sur une application qui ne compte pas. Je t'ai préparé `labo` : un nginx sans privilège, une page, un Service. Mets-le dans un projet `formation/gitops-labo`, donne à Argo CD de quoi le lire (un jeton de déploiement du groupe `formation`, lecture seule), crée l'Application, synchronise à la main, puis passe-la en automatique et change la page par un commit. Rien d'autre : pas de `kubectl apply`.

**Objectifs pédagogiques**
- Donner à Argo CD l'accès en lecture à un dépôt privé avec un jeton de déploiement à portée minimale.
- Créer une Application et lire ses statuts de synchronisation et de santé.
- Comparer (`diff`) et synchroniser à la main, puis automatiquement sur un commit.
- Reconnaître les objets gérés par Argo CD (annotation de suivi).

**Prérequis** : M20-E03.
**Durée indicative** : 1 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Projet GitLab | `formation/gitops-labo` (privé), contenu : `ressources/E04-gitops-labo/` du workbook, copié tel quel |
| Jeton | jeton de déploiement du **groupe** `formation`, nom `argocd-lecture`, nom d'utilisateur `argocd-formation`, portée `read_repository`, expiration dans un an ; rangé dans le Vault (`plateforme/k8s/secrets/argocd.yml`, clé `argocd_depots.formation`) |
| Application | `labo`, projet `default` (E07 créera `labo`), source `https://git01.par1.medisphere.internal/formation/gitops-labo.git`, `main`, dossier `k8s` ; destination ce cluster (`https://kubernetes.default.svc`), espace `wb-essais` |

**Travail demandé**

1. Crée le projet `formation/gitops-labo` et pousse le contenu fourni. Lis `k8s/` : quel outil Argo CD utilisera-t-il pour rendre ce dossier, et à quoi le reconnaîtra-t-il ?
2. Crée le jeton de déploiement du groupe `formation` (interface : *Settings* > *Repository* > *Deploy tokens* du groupe) et range-le dans le Vault. Pourquoi un jeton de **groupe** plutôt que de projet, et pourquoi pas ton jeton personnel ?
3. Déclare le dépôt dans Argo CD **à la main**, cette fois (l'E06 fera mieux) :
   ```
   admin@adm01:~$ argocd repo add https://git01.par1.medisphere.internal/formation/gitops-labo.git --username argocd-formation
   admin@adm01:~$ argocd repo list
   ```
   La CLI demande le jeton au clavier. Où Argo CD l'a-t-il rangé ? (`kubectl -n argocd get secrets -l argocd.argoproj.io/secret-type`). Comment a-t-il vérifié le certificat de `git01` ?
4. Crée l'Application en synchronisation manuelle :
   ```
   admin@adm01:~$ argocd app create labo --project default \
       --repo https://git01.par1.medisphere.internal/formation/gitops-labo.git --revision main --path k8s \
       --dest-server https://kubernetes.default.svc --dest-namespace wb-essais
   admin@adm01:~$ argocd app get labo
   admin@adm01:~$ argocd app diff labo
   ```
   Quels statuts de synchronisation et de santé lis-tu, objet par objet ? Que montre le diff qui n'est pas dans tes fichiers ?
5. Synchronise (`argocd app sync labo`), puis regarde l'application dans l'interface (arbre des objets, journaux d'un pod, événements). Lis les annotations du Deployment : laquelle a été posée par Argo CD, et que contient-elle ? Quel est le gestionnaire de champs du Deployment, et quelle opération ?
6. Passe l'application en synchronisation automatique (`argocd app set labo --sync-policy automated`), puis change le titre de la page dans `k8s/configmap.yaml` (« version 2 »), commit, push. Mesure le temps avant qu'Argo CD applique le changement. D'où vient ce délai, et comment l'accélérer sans rien changer à la configuration ?
7. Vérifie la page servie : `kubectl -n wb-essais port-forward svc/labo 8080:80`, puis `curl -s localhost:8080`. Combien de temps la page met-elle à changer après la synchronisation, et pourquoi les pods n'ont-ils pas été recréés ?

**Critères de réussite**
- [ ] `formation/gitops-labo` contient les manifestes de `labo` sur `main`.
- [ ] L'Application `labo` existe (projet `default`), source `formation/gitops-labo`/`main`/`k8s`, destination `wb-essais` de ce cluster, en synchronisation automatique.
- [ ] `labo` est `Synced` et `Healthy` sur la dernière révision de `main` ; son historique compte au moins deux révisions (synchronisation manuelle, puis automatique après ton commit).
- [ ] Le Deployment `labo` porte l'annotation de suivi de l'Application `labo`, ses pods sont prêts, son image vient du cache Harbor.

**Vérification** : `lab/bin/check 20 04`

<details><summary>Indice 1</summary>

Un jeton de déploiement a un **nom** (pour toi) et un **nom d'utilisateur** (pour Git) : c'est ce dernier qu'on donne à `--username`. La racine MédiSphère est déjà dans `argocd-tls-certs-cm` depuis l'E02.
</details>

<details><summary>Indice 2</summary>

Argo CD interroge le dépôt à intervalle régulier : regarde `timeout.reconciliation` dans `argocd-cm`. `argocd app get labo --refresh` (ou le bouton *Refresh* de l'interface) demande une comparaison immédiate. Le kubelet ne relit pas un volume ConfigMap instantanément.
</details>

**Pour aller plus loin** (facultatif) : `argocd app manifests labo` affiche ce que le *repo-server* a rendu ; compare avec `kubectl kustomize` de ta copie locale.

---

### M20-E05 — Synchronisation, santé, dérive et auto-réparation  `LAB` `★★`

> **Ticket INC-4705** — *De : Nadia Roussel*
> Retour sur l'incident de lundi (réplicas changés à la main en recette, vu trop tard). Avant qu'on mette MédiAgenda sous Argo CD, je veux savoir exactement ce qu'il fait quand quelqu'un touche au cluster, quand un fichier disparaît de Git, et ce qu'il ne fait **pas**. Démontre-le sur `labo`, et écris-moi les réglages qu'on retiendra.

**Objectifs pédagogiques**
- Provoquer une dérive et observer la réaction d'Argo CD avec et sans auto-réparation.
- Comprendre la suppression d'objets (*prune*) et ses conditions de déclenchement.
- Passer une Application au *server-side apply* et lire la migration des gestionnaires de champs.
- Activer le diff côté serveur et comprendre les faux `OutOfSync` qu'il évite.

**Prérequis** : M20-E04.
**Durée indicative** : 2 h.

**Contexte technique** : tout se passe sur `labo` (`wb-essais`), par la CLI ; le réglage global du diff côté serveur passe par la release Helmfile `argocd` (`configs.params`). Les changements de l'application `labo` faits ici à la main seront décrits dans Git en E06.

**Travail demandé**

*A. Dérive*

1. `labo` est en synchronisation automatique **sans** auto-réparation. Provoque une dérive : `kubectl --context k8s-par1 -n wb-essais scale deploy/labo --replicas=4`. Que deviennent le statut de synchronisation, la santé, le nombre de pods ? `argocd app diff labo` : que montre-t-il ? Pourquoi la synchronisation automatique ne corrige-t-elle rien ?
2. Active l'auto-réparation (`argocd app set labo --self-heal`). Combien de temps avant le retour à deux réplicas ? Refais la dérive : même chose ? Lis l'historique (`argocd app history labo`) : une ligne de plus, ou non ? Explique.
3. Autre dérive, sur les étiquettes du Deployment : ajoute une étiquette **nouvelle** (`kubectl label deploy/labo essai=main`), puis change la **valeur** d'une étiquette que Git déclare (`app.kubernetes.io/part-of`). Argo CD efface-t-il les deux ? Explique la différence (tu y reviendras à la question 6).

*B. Suppression*

4. Ajoute à `formation/gitops-labo` une ConfigMap `labo-essai` (fichier `k8s/configmap-essai.yaml`, déclaré dans `kustomization.yaml`), commit : elle est créée. Retire-la de Git, commit. Que devient-elle dans le cluster ? Quel statut porte-t-elle dans `argocd app get labo` (regarde `requiresPruning` dans `-o json`) ?
5. Active la suppression automatique (`argocd app set labo --auto-prune`). La ConfigMap disparaît-elle tout de suite ? Sinon, pourquoi, et que faut-il pour qu'elle disparaisse (lis la section « Automated Sync Semantics » de la documentation) ?
   > ⚠️ **Attention** : avec `prune`, retirer un fichier de Git **supprime** l'objet. Sur une application qui porte des données, c'est une perte de données. On le pratique ici sur une ConfigMap jetable ; l'E08 protège la base de MédiAgenda.

*C. Méthode d'application et comparaison*

6. Lis les `managedFields` du Deployment (`kubectl get … --show-managed-fields -o json | jq '.metadata.managedFields[] | {manager, operation}'`) et ses annotations. Passe `labo` en *server-side apply* et écris explicitement que l'espace n'est pas créé par l'application :
   ```
   admin@adm01:~$ argocd app set labo --sync-option ServerSideApply=true --sync-option CreateNamespace=false
   admin@adm01:~$ argocd app sync labo
   ```
   Relis les `managedFields` et les annotations : qu'est-ce qui a changé, et quel mécanisme a fait la migration (Argo CD, ou la bibliothèque `kubectl` qu'il embarque) ? Les pods ont-ils été recréés ?
7. Le diff côté serveur : compare `argocd app diff labo` et `argocd app diff labo --server-side-diff`. Puis active-le pour toutes les Applications par les valeurs de la release (`configs.params`, clé `controller.diff.server.side`), `helmfile diff`, MR, `apply`. Le contrôleur redémarre-t-il ? (Lis les annotations du modèle de pod du StatefulSet.) Pourquoi ce réglage évite-t-il des `OutOfSync` permanents sur des objets dont l'API ou une CRD remplit des valeurs par défaut (une HTTPRoute, par exemple) ?
8. Écris pour Nadia, dans `~/m20/e05/reglages.md` (tu le reverseras dans la documentation à l'E22) : ce que fait Argo CD dans chaque cas observé, et les réglages retenus pour `dev`, `recette` et `prod` (synchronisation automatique, auto-réparation, suppression), justifiés.

**Critères de réussite**
- [ ] `labo` est en synchronisation automatique avec `selfHeal` et `prune`, options `ServerSideApply=true` et `CreateNamespace=false`.
- [ ] Le diff côté serveur est actif pour toutes les Applications (`controller.diff.server.side: "true"` dans les valeurs, sur `main` de `plateforme/k8s`).
- [ ] Le nombre de réplicas de `labo` est celui de Git ; `labo` est `Synced` et `Healthy`.
- [ ] Le Deployment `labo` est géré en *server-side apply* par `argocd-controller`, sans annotation `last-applied-configuration`.
- [ ] `labo-essai` a été créée puis supprimée par Argo CD (au moins quatre révisions dans l'historique de `labo`), et plus aucun objet n'attend de suppression.

**Vérification** : `lab/bin/check 20 05`

<details><summary>Indice 1</summary>

La synchronisation automatique ne se déclenche que lorsque **Git** change (une nouvelle révision) ; l'auto-réparation ajoute la réaction aux changements **du cluster**. Après un changement de réglage, un rafraîchissement (`argocd app get labo --refresh`) évite d'attendre la prochaine réconciliation.
</details>

<details><summary>Indice 2</summary>

En *server-side apply*, un champ que ton manifeste ne mentionne pas n'appartient pas à Argo CD : il n'a aucune raison de l'effacer. En *client-side apply*, c'est l'annotation `last-applied-configuration` qui sert de mémoire. Lis la section « Client-Side Apply Migration » des *Sync Options* : quel gestionnaire migre-t-elle par défaut ? Est-ce celui qui a appliqué `labo` jusqu'ici ? `kubectl apply --server-side` sait aussi migrer de lui-même le gestionnaire qui possède l'annotation `last-applied-configuration`.
</details>

**Pour aller plus loin** (facultatif) : `retry` dans la politique de synchronisation (`--sync-retry-limit`) : dans quel cas une synchronisation automatique échouée n'est-elle jamais retentée sans lui ?

---

### M20-E06 — Le dépôt `plateforme/gitops` et l'application racine  `LAB` `★★`

> **Ticket PLAT-2106** — *De : Karim Benali* — *Copie : Claire Morel*
> `labo` existe parce que tu as tapé une commande. Si on réinstalle Argo CD demain, il n'existe plus, et personne ne sait comment il était réglé. Je veux un dépôt `plateforme/gitops` qui décrit **tout** ce qu'Argo CD gère, une seule Application créée à la main — la racine —, et tout le reste qui en découle, la racine comprise. Et plus de jeton tapé dans la CLI : des modèles d'identifiants par groupe GitLab, créés depuis le Vault.

**Objectifs pédagogiques**
- Organiser un dépôt GitOps (racine, groupes d'Applications, projets, applications).
- Mettre en place le motif *App of Apps* avec une racine qui se gère elle-même.
- Reprendre dans Git une Application créée à la main, sans la recréer.
- Donner à Argo CD l'accès aux dépôts par des modèles d'identifiants (`repo-creds`) créés hors Git.

**Prérequis** : M20-E05 ; M19-E04 (`plateforme/k8s/outils/secrets-k8s.sh`, Vault `critique`) ; M01 (branches protégées).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Projet GitLab | `plateforme/gitops`, `main` protégée (poussée directe interdite, fusion par les Maintainers : toi et Karim Benali) |
| Arborescence | `README.md` ; `racine/` (`racine.yaml`, `applications.yaml`) ; `applications/` (`labo.yaml`) ; `projets/` et `plateforme/` viendront en E07 et E15 |
| Applications de premier niveau | `racine` (dossier `racine/`, se gère elle-même) ; `applications` (dossier `applications/`) ; toutes en projet `default` jusqu'à l'E07, destination `argocd` de ce cluster, synchronisation automatique, `prune`, `selfHeal`, *server-side apply*, **sans** finaliseur de suppression en cascade |
| Accès aux dépôts | un jeton de déploiement `argocd-lecture` (`read_repository`, expiration) par groupe : `plateforme`, `mediagenda`, `medidoc` (et `formation`, déjà fait) ; un Secret `repo-creds-<groupe>` (étiquette `argocd.argoproj.io/secret-type: repo-creds`, URL `https://git01.par1.medisphere.internal/<groupe>/`) par groupe |
| Création des Secrets | `outils/secrets-k8s.sh appliquer argocd` (composant `argocd`, Vault `secrets/argocd.yml`, clé `argocd_depots`) : la table `secrets-k8s.conf` ne sait pas poser d'étiquettes ; le composant `argocd` a donc son module `outils/secrets-k8s.d/argocd.sh`, sourcé par le script |

**Travail demandé**

*A. Les identifiants*

1. Crée les jetons de déploiement des groupes `plateforme`, `mediagenda` et `medidoc` (même nom, même portée, même règle d'expiration que celui de `formation`), et ajoute-les au Vault. Pourquoi des modèles d'identifiants **par groupe** plutôt qu'un Secret par dépôt ? Quel modèle Argo CD choisit-il quand plusieurs préfixes correspondent à une URL ?
2. Étends `secrets-k8s.sh` : un composant qui a un module `outils/secrets-k8s.d/<composant>.sh` est accepté même sans ligne dans la table, le Vault est déchiffré, et le module fournit `secrets_<composant>_appliquer` et `secrets_<composant>_verifier`. Écris le module `argocd.sh` : un Secret `repo-creds-<groupe>` par groupe, en *server-side apply*, sans jamais afficher ni passer un jeton en argument. Puis :
   ```
   admin@adm01:~/src/k8s$ outils/secrets-k8s.sh appliquer argocd && outils/secrets-k8s.sh verifier argocd
   admin@adm01:~$ argocd repocreds list
   ```
3. Retire le dépôt déclaré à la main en E04 (`argocd repo rm …`). `labo` lit-elle toujours son dépôt ? Comment le vérifies-tu sans attendre trois minutes ?

*B. Le dépôt et la racine*

4. Crée `plateforme/gitops`, protège `main`, écris le `README.md` (rôle du dépôt, arborescence, règles : tout par MR, jamais de Secret, pas de finaliseur sur la racine). Pourquoi ce dépôt donne-t-il des droits d'**administrateur** d'Argo CD à qui peut y fusionner (lis l'avertissement de la page « Cluster Bootstrapping ») ?
5. Écris `racine/racine.yaml` (l'Application `racine` : dossier `racine/`, fichiers `*.yaml` seulement, non récursif) et `racine/applications.yaml` (l'Application `applications` : dossier `applications/`). Écris `applications/labo.yaml` : la **même** spécification que l'application `labo` actuelle (relis-la : `argocd app get labo -o yaml`), plus le finaliseur `resources-finalizer.argocd.argoproj.io`. Pourquoi ce finaliseur sur `labo`, et surtout pas sur `racine` ni sur `applications` ?
6. MR, fusion. Puis crée la racine, **une seule fois**, à la main :
   ```
   admin@adm01:~/src/gitops$ kubectl --context k8s-par1 apply --server-side --field-manager=amorcage -f racine/racine.yaml
   admin@adm01:~$ argocd app list
   ```
   Lis l'annotation de suivi de `racine`, d'`applications` et de `labo` : qui gère qui ? `labo` a-t-elle été recréée (ses pods, son historique) ?
7. Démontre que la racine se gère elle-même : change un détail inoffensif de `racine/racine.yaml` par une MR (une étiquette), et vérifie qu'il est appliqué sans geste manuel. Démontre ensuite que la racine protège `labo` : supprime l'Application `labo` **sans cascade** (`argocd app delete labo --cascade=false`) et observe.
   > ⚠️ **Attention** : `--cascade=false` est indispensable. Sans lui, le finaliseur de `labo` supprimerait ses objets avant que la racine ne la recrée. Sur `labo`, ce n'est pas grave ; c'est précisément pour cela que la racine et MédiAgenda n'ont pas ce finaliseur.

**Critères de réussite**
- [ ] `plateforme/gitops` existe, `main` protégée (poussée interdite), avec `README.md`, `racine/racine.yaml`, `racine/applications.yaml`, `applications/labo.yaml`.
- [ ] L'Application `racine` (dossier `racine`, `main`) est `Synced` et `Healthy`, en synchronisation automatique, sans finaliseur, et se gère elle-même (annotation de suivi `racine:…/racine`).
- [ ] `applications` est gérée par `racine`, `labo` par `applications` ; `labo` est restée `Synced` et `Healthy`.
- [ ] Quatre jetons de déploiement `argocd-lecture` actifs (`read_repository` seul, avec expiration) et quatre modèles d'identifiants `repo-creds` ; plus aucun dépôt enregistré avec ses propres identifiants.

**Vérification** : `lab/bin/check 20 06`

<details><summary>Indice 1</summary>

Un Secret d'Argo CD n'est reconnu qu'à son étiquette `argocd.argoproj.io/secret-type` (`repository`, `repo-creds`, `cluster`) ; ses clés (`type`, `url`, `username`, `password`) sont décrites dans « Declarative Setup ». `kubectl create secret generic … --dry-run=client -o yaml | kubectl label --local -f - … -o yaml | kubectl apply --server-side -f -` compose les trois.
</details>

<details><summary>Indice 2</summary>

Une Application dont le dossier source contient le fichier qui la décrit se gère elle-même : la créer à la main la première fois avec le **même** contenu évite toute différence à la première synchronisation. `directory.include` limite les fichiers lus ; sans `recurse`, les sous-dossiers sont ignorés.
</details>

<details><summary>Indice 3</summary>

Après `argocd repo rm`, la prochaine comparaison de `labo` dira si les identifiants hérités fonctionnent : `argocd app get labo --hard-refresh` force une nouvelle lecture du dépôt. Si elle échoue, lis la condition `ComparisonError`.
</details>

**Pour aller plus loin** (facultatif) : l'amorçage pourrait aussi être fait par Helmfile (`extraObjects` du chart, ou le chart `argocd-apps` du même dépôt). Quels avantages, et pourquoi ce dépôt-ci ne doit-il pas dépendre de la release d'Argo CD ?

---

### M20-E07 — AppProjects : cloisonner les équipes  `LAB` `★★★`

> **Ticket SEC-2107** — *De : Sophie Laurent* — *Copie : Julien Petit, Karim Benali*
> Aujourd'hui, toutes les Applications sont dans le projet `default`, qui permet tout : n'importe quel dépôt, n'importe quel espace, n'importe quel objet, y compris des ClusterRoles. Je veux un projet par équipe : MédiAgenda ne déploie que depuis `mediagenda/deploiement`, que dans ses trois espaces, jamais d'objet de cluster, et rien de ce que la plateforme gouverne dans ses espaces (quotas, limites). Pareil pour MédiDoc, et pour vos essais. `default` doit devenir inutilisable. Et je veux savoir quand un objet traîne dans un espace sans que personne ne le gère.

**Objectifs pédagogiques**
- Décrire des AppProjects : sources, destinations, listes blanches d'objets de cluster, listes noires d'objets d'espace, ressources orphelines.
- Ordonner des changements interdépendants dans un dépôt GitOps (un projet doit exister avant qu'une Application s'y range).
- Vérifier une restriction par un refus réel, sans effet de bord.
- Ramener dans la plateforme des objets gouvernés que portait encore un dépôt d'équipe.

**Prérequis** : M20-E06 ; M14-E10 (espaces, quotas, limites des équipes), M17-E09 (overlays de `mediagenda/deploiement`).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Fichiers | `plateforme/gitops` : `projets/plateforme.yaml`, `projets/mediagenda.yaml`, `projets/medidoc.yaml`, `projets/labo.yaml`, `projets/default.yaml`, `racine/projets.yaml` (Application `projets`, dossier `projets/`) |
| `mediagenda` | source `mediagenda/deploiement` ; destinations `mediagenda-dev`, `mediagenda-recette`, `mediagenda-prod` |
| `medidoc` | source `medidoc/deploiement` ; destinations `medidoc-dev`, `medidoc-recette` (créé en M20-E33) |
| `labo` | source `formation/gitops-labo` ; destination `wb-essais` (M20-E26 ajoutera le cluster de l'agence) |
| `plateforme` | source `plateforme/gitops` ; destination `argocd` (chaque service de plateforme ajoutera la sienne) ; tout objet de cluster permis ; projet de `racine`, `applications`, `projets` |
| Objets gouvernés par la plateforme | dans les espaces d'équipe : `ResourceQuota`, `LimitRange` (`plateforme/k8s/espaces/`) ; les objets de cluster (dont `Namespace`) |

**Travail demandé**

*A. Concevoir*

1. Pour chaque overlay de `mediagenda/deploiement` (`dev`, `recette`, `prod`), liste les types d'objets rendus (`kubectl kustomize overlays/<env> | grep '^kind:' | sort | uniq -c`). Lesquels seraient refusés par un projet sans objet de cluster et sans `ResourceQuota` ni `LimitRange` ? Qui doit les porter ?
2. Le ticket de Sophie parle aussi des NetworkPolicy « gérées par la plateforme ». Regarde qui pose des NetworkPolicy dans `mediagenda-dev` aujourd'hui (le chart ? le component `dependances` ? `plateforme/k8s` ?). Peux-tu interdire le type `NetworkPolicy` au projet `mediagenda` sans casser MédiAgenda ? Propose une réponse et écris-la dans la MR ; quelle protection de la plateforme reste hors d'atteinte d'une équipe, quoi qu'elle mette dans son dépôt (M15-E28) ?
3. Lis la page « Orphaned Resources Monitoring » : qu'est-ce qu'une ressource orpheline pour Argo CD, lesquelles ne le sont jamais, et quel est le coût de la surveillance ? Sur quels projets l'actives-tu ? Pour MédiAgenda, quels objets que la plateforme crée hors Git faut-il exclure de l'alerte ?

*B. Ramener les objets d'espace de la production dans la plateforme*

4. `overlays/prod/espace.yaml` (M17-E09) crée encore l'espace `mediagenda-prod`, son ResourceQuota et sa LimitRange. Déplace ces trois objets dans `plateforme/k8s/espaces/mediagenda-prod/`, **mêmes noms, mêmes valeurs** ; `task espaces` d'abord (MR de `plateforme/k8s`), puis retire-les de l'overlay (MR de `mediagenda/deploiement`). Pourquoi cet ordre, et que se passe-t-il pour les objets du cluster quand tu les retires de l'overlay ? Lis les `managedFields` du ResourceQuota avant et après.

*C. Les projets, en trois MR*

5. **MR 1** : les quatre projets d'équipe et de plateforme (`projets/*.yaml`, avec le finaliseur qui empêche de supprimer un projet encore utilisé) et l'Application `projets` (`racine/projets.yaml`, **en projet `default`** pour l'instant). Fusion, puis `argocd proj list`.
6. **MR 2** : range les Applications dans leurs projets : `racine`, `applications`, `projets` dans `plateforme`, `labo` dans `labo`. Pourquoi n'était-ce pas possible dans la MR 1 ?
7. **MR 3** : verrouille `default` (`projets/default.yaml` : aucune source, aucune destination). Pourquoi en dernier ?
   > ⚠️ **Attention** : si `racine` (ou `projets`) est encore dans `default` quand `default` est verrouillé, elle ne peut plus se synchroniser… y compris pour appliquer la correction. Retour arrière, dans cet ordre : (1) une MR qui **rouvre** `default` dans Git (une source et une destination dans `projets/default.yaml` ; ne retire **pas** le fichier : avec `prune`, l'AppProject `default` serait supprimé) ; (2) si `projets` ne peut plus synchroniser, rends à la main une source et une destination à `default` (`argocd proj add-source default …`, `argocd proj add-destination default …`) — sans l'étape 1, l'auto-réparation de `projets` reverrouillerait aussitôt `default` ; (3) laisse `projets` puis `racine` converger (`argocd app get <app> --refresh`) ; (4) refais la MR 2, puis la MR 3.

*D. Prouver*

8. Fais refuser quelque chose, sans rien casser :
   - une destination : `argocd app create essai-destination --project labo --repo https://git01.par1.medisphere.internal/formation/gitops-labo.git --path k8s --dest-server https://kubernetes.default.svc --dest-namespace mediagenda-dev` ; lis le message ;
   - un type d'objet : dans une branche `essai-projet` de `formation/gitops-labo`, un dossier **à part** `essai/` qui ne contient qu'un ResourceQuota ; une Application `essai-projet` (projet `labo`, révision `essai-projet`, dossier `essai`) ; `argocd app sync essai-projet` ; lis le message ; supprime l'Application et la branche.
   Pourquoi un dossier à part, et pas la branche entière avec `k8s/` ? (Indice : regarde les conditions d'une Application qui déploierait les mêmes objets que `labo`.)
9. Note la conception dans `plateforme/gitops/README.md` (projets, ce qu'ils permettent, la procédure pour ajouter une équipe).

**Critères de réussite**
- [ ] Les AppProjects `plateforme`, `mediagenda`, `medidoc`, `labo` sont gérés depuis `plateforme/gitops` par l'Application `projets` ; chacun n'a qu'une source et ses seules destinations.
- [ ] `mediagenda`, `medidoc` et `labo` n'autorisent aucun objet de cluster et interdisent `ResourceQuota` et `LimitRange` ; `mediagenda` et `medidoc` signalent les ressources orphelines.
- [ ] `default` est verrouillé et plus aucune Application n'y est ; `racine`, `applications`, `projets` sont dans `plateforme`, `labo` dans `labo`, toutes `Synced`.
- [ ] L'espace `mediagenda-prod`, son quota et ses limites sont décrits dans `plateforme/k8s` et plus dans l'overlay `prod`.

**Vérification** : `lab/bin/check 20 07`

<details><summary>Indice 1</summary>

Une liste blanche **vide** (`clusterResourceWhitelist: []`) interdit tout objet de cluster ; une liste blanche d'objets d'espace vide, elle, ne restreint rien (il faut alors une liste noire). Le groupe d'API d'un objet compte : `NetworkPolicy` est dans `networking.k8s.io`, pas dans le groupe vide (un exemple de la documentation s'y trompe).
</details>

<details><summary>Indice 2</summary>

Le champ `orphanedResources`, même avec `warn: false`, **active** la surveillance (visible dans l'interface) : omets-le là où tu n'en veux pas. Les objets d'un type interdit par le projet ne sont jamais orphelins ; les objets qui ont un propriétaire (`ownerReferences`) non plus.
</details>

<details><summary>Indice 3</summary>

Chaque Application voit le nouveau commit à sa propre réconciliation : après la MR 1, attends que `projets` soit `Synced` (ou rafraîchis-la) avant la MR 2. `argocd proj get <projet>` résume ce qu'un projet permet.
</details>

**Pour aller plus loin** (facultatif) : les `destinationServiceAccounts` d'un projet (synchronisation sous l'identité d'un compte de service de l'espace cible, option `application.sync.impersonation.enabled`) : ce que cela changerait pour MédiAgenda, et pourquoi la fonction est encore marquée alpha.

---

### M20-E08 — Reprendre MédiAgenda dev sous Argo CD sans coupure  `LAB` `★★★`

> **Ticket DEV-2108** — *De : Julien Petit* — *Copie : Karim Benali*
> On passe `mediagenda-dev` sous Argo CD, d'accord, mais jeudi je fais une démonstration au client sur dev : **aucun redémarrage**, aucune coupure, la base intacte. Aujourd'hui c'est le job `deployer-dev` qui applique l'overlay à chaque fusion ; après, ce sera Argo CD et lui seul. Et je veux une procédure écrite, parce qu'on refera la même chose pour la recette, la prod et MédiDoc.

**Objectifs pédagogiques**
- Préparer une reprise : état de départ photographié, un seul écrivain, données protégées.
- Lire un diff de reprise et décider si une synchronisation recrée des pods.
- Comprendre ce que la synchronisation change réellement (annotation de suivi, gestionnaires de champs, génération) et ce qu'elle ne change pas.
- Écrire une procédure de reprise réutilisable.

**Prérequis** : M20-E07 ; M19-E18 (agent GitLab et job `deployer-dev`), M17-E09 et M17-E25 (overlay `dev`, component `dependances`, base CNPG `mediagenda-db`).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Charge | espace `mediagenda-dev` : Deployment `mediagenda`, StatefulSet `valkey`, Cluster CNPG `mediagenda-db`, Services, HTTPRoute `mediagenda` (`mediagenda-dev.apps.par1.medisphere.internal`), politiques réseau ; appliqués aujourd'hui par `kubectl apply --server-side -k overlays/dev` (job `deployer-dev`, contexte de l'agent `k8s-par1`) |
| Application | `mediagenda-dev`, fichier `plateforme/gitops/applications/mediagenda-dev.yaml`, projet `mediagenda`, source `mediagenda/deploiement`/`main`/`overlays/dev`, destination `mediagenda-dev` ; `ServerSideApply=true`, `CreateNamespace=false` ; **pas** de finaliseur ; `spec.info` : `reprise` (date ISO 8601 UTC), `revision-avant-reprise` (révision du Deployment), `ticket` |
| Données | `mediagenda-db` (component `dependances`) : `argocd.argoproj.io/sync-options: Prune=false,Delete=false` |
| Outil fourni | `ressources/E08-reprise/instantane.sh <espace> <deployment>` : photographie en lecture seule (révision, ReplicaSets, pods, gestionnaires de champs) |
| Procédure | `plateforme/medisphere` : `docs/livraison/gitops/reprise-sans-coupure.md` |

**Travail demandé**

*A. Avant*

1. Photographie l'état de départ :
   ```
   admin@adm01:~$ mkdir -p ~/m20/e08
   admin@adm01:~$ ~/DevOpsPrivateCloud/modules/20-gitops/ressources/E08-reprise/instantane.sh mediagenda-dev mediagenda > ~/m20/e08/avant.txt
   ```
   Note la révision du Deployment, son ReplicaSet, ses pods, et le nom du gestionnaire de champs du job `deployer-dev`. Fais de même pour le StatefulSet `valkey` (`kubectl get sts,pods`).
2. **Un seul écrivain.** Retire `deployer-dev` du pipeline de `mediagenda/deploiement` (MR) : le job vient du composant `deploiement` (M19-E18). Comment le désactives-tu sans toucher au composant, ni aux autres jobs (validation) ? Vérifie que le pipeline de la fusion ne contient plus `deployer-dev`. Vérifie aussi que **le dernier `deployer-dev` réussi a porté sur le dernier commit de `main`** (environnement `dev` de GitLab) : sinon, que ferait la première synchronisation ?
3. **Protéger les données.** Ajoute à `mediagenda-db`, dans le component `dependances`, l'annotation `argocd.argoproj.io/sync-options: Prune=false,Delete=false` (MR). Que protège chacune des deux options ? Qui appliquera cette annotation, puisque `deployer-dev` ne tourne plus ?

*B. La reprise*

4. Écris `applications/mediagenda-dev.yaml` **sans synchronisation automatique**, avec `spec.info` (date prévue de la reprise, révision notée à l'étape 1, ticket). MR dans `plateforme/gitops`, fusion. L'Application apparaît : quel statut, et pourquoi ?
5. Lis le diff, objet par objet :
   ```
   admin@adm01:~$ argocd app diff mediagenda-dev
   ```
   Classe chaque différence : attendue (laquelle ?) ou bloquante. Quelle différence, si tu la voyais, devrait t'arrêter net ? Tu ne continues que si **aucune** ne touche le modèle de pod (`spec.template`) d'un Deployment ou d'un StatefulSet.
6. Synchronise d'abord à blanc (`argocd app sync mediagenda-dev --dry-run`), puis pour de bon. Rephotographie (`instantane.sh … > ~/m20/e08/apres.txt`), et compare :
   ```
   admin@adm01:~$ diff ~/m20/e08/avant.txt ~/m20/e08/apres.txt
   ```
   Quelles lignes ont changé, lesquelles non ? Explique la **génération** du Deployment (elle a peut-être bougé) et les **gestionnaires de champs** (pourquoi l'ancien est-il toujours là ?). Vérifie `/sante` sur `https://mediagenda-dev.apps.par1.medisphere.internal`.
7. Passe l'Application en synchronisation automatique (`prune`, `selfHeal`) par une MR, avec la date réelle de la reprise dans `spec.info`. Fais une dernière vérification de l'absence de recréation (âge des pods, ReplicaSet).

*C. Écrire*

8. Rédige `docs/livraison/gitops/reprise-sans-coupure.md` : prérequis, photographie, un seul écrivain, données protégées, création sans automatisme, lecture du diff (ce qui est attendu, ce qui arrête), synchronisation, vérification, passage en automatique, retour arrière.

**Critères de réussite**
- [ ] L'Application `mediagenda-dev` (projet `mediagenda`, `overlays/dev` de `main`, *server-side apply*, sans finaliseur) est `Synced` et `Healthy`, en synchronisation automatique (`prune`, `selfHeal`).
- [ ] La reprise est consignée dans `spec.info` ; le ReplicaSet de la révision notée a été créé **avant** la reprise ; MédiAgenda dev répond sur `/sante`.
- [ ] Le Deployment et la base portent l'annotation de suivi de `mediagenda-dev` ; la base porte `Prune=false,Delete=false` ; `argocd-controller` gère les champs du Deployment.
- [ ] Le dernier pipeline de `main` de `mediagenda/deploiement` ne contient plus de job `deployer-dev`.
- [ ] La procédure `docs/livraison/gitops/reprise-sans-coupure.md` est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 20 08`

<details><summary>Indice 1</summary>

Un job venu d'un `include` (composant compris) se surcharge dans le `.gitlab-ci.yml` qui l'inclut : redéclarer le job avec les seuls mots-clés à changer (par exemple ses `rules`) suffit. Le retrait complet des jobs de déploiement viendra en M20-E30.
</details>

<details><summary>Indice 2</summary>

Avant la reprise, **chaque** objet est `OutOfSync` : Argo CD veut y poser son annotation de suivi. C'est la seule différence acceptable (avec l'annotation que tu as ajoutée exprès). Un ReplicaSet porte dans son nom l'empreinte du modèle de pod : même modèle, même ReplicaSet.
</details>

<details><summary>Indice 3</summary>

Pour un Deployment, l'API augmente `metadata.generation` quand la spécification **ou les annotations** changent ; la révision (`deployment.kubernetes.io/revision`), elle, ne bouge que si le modèle de pod change. En *server-side apply*, deux gestionnaires qui posent la même valeur sur un champ en sont copropriétaires.
</details>

**Pour aller plus loin** (facultatif) : relis les `managedFields` du Deployment. Que faudrait-il faire pour que l'ancien gestionnaire (celui du job) ne possède plus aucun champ, et pourquoi est-ce risqué si son manifeste différait de celui d'Argo CD ? (M20-E30 le fera pour tous les espaces applicatifs.)

---

### M20-E09 — Questions : les principes du GitOps  `Q` `★★`

> **Ticket PLAT-2109** — *De : Claire Morel*
> Le comité d'architecture me demande si nous sommes « vraiment GitOps ». Réponds-moi par écrit, à partir des principes d'OpenGitOps et de ce que tu as construit cette semaine, sans complaisance : ce qui est conforme, ce qui ne l'est pas encore, et ce qui ne le sera jamais tout à fait.

**Objectifs pédagogiques**
- Connaître les quatre principes d'OpenGitOps et leur vocabulaire.
- Confronter une installation réelle à ces principes et en repérer les écarts.

**Prérequis** : M20-E02 à E08.
**Durée indicative** : 1 h.

**Travail demandé**

Réponds aux 12 questions, en t'appuyant sur ce que tu as mis en place (cite les objets et les fichiers).

1. Énonce les quatre principes d'OpenGitOps. Pour chacun, un exemple de ce qui, chez MédiSphère, le respecte.
2. Le mot « Git » apparaît-il dans les principes ? Qu'est-ce qu'un « magasin d'état » (*state store*) au sens d'OpenGitOps, et qu'est-ce qui pourrait en tenir lieu à la place d'un dépôt Git ?
3. « Versionné et immuable » : la branche `main` de `plateforme/gitops` l'est-elle ? Qu'est-ce qui permettrait de réécrire l'historique, et qu'est-ce qui l'empêche dans notre forge ?
4. L'application `racine` a été créée par un `kubectl apply`. Est-ce une entorse au principe « tiré automatiquement » ? Où s'arrête l'amorçage, où commence la réconciliation ?
5. La couche de base (Cilium, cert-manager, Argo CD lui-même…) reste sous `helmfile apply`, lancé par une personne depuis `adm01`. Quels principes ne sont pas respectés pour elle ? Quelles compensations MédiSphère a-t-il mises en place (M17), et que faudrait-il pour aller plus loin ?
6. Les Secrets sont créés hors de Git par `secrets-k8s.sh`. Quel principe est en défaut ? Quelle est la solution prévue (M25), et en quoi rétablit-elle le principe ?
7. « Réconcilié en continu » : à quelle fréquence Argo CD compare-t-il Git et le cluster ? Qu'est-ce qui raccourcit ce délai ? Une synchronisation **manuelle** (prévue pour `prod`) est-elle compatible avec le principe ?
8. L'auto-réparation (`selfHeal`) efface les modifications faites à la main. Donne un cas où c'est exactement ce qu'on veut et un cas d'urgence où c'est un obstacle. Comment le gérer sans abandonner le principe ?
9. Un HorizontalPodAutoscaler change `spec.replicas` d'un Deployment dont Git fixe aussi `replicas`. Que se passe-t-il ? Est-ce une violation du principe déclaratif ? Comment le résoudre (deux réponses) ?
10. Le *server-side apply* et l'annotation de suivi : en quoi aident-ils à respecter les principes « déclaratif » et « réconcilié » quand d'autres acteurs (opérateurs, contrôleurs) écrivent aussi dans les objets ?
11. La CI du M19 pousse encore des MR de promotion dans `mediagenda/deploiement`. Est-ce une entorse au modèle *pull* ? Distingue l'écriture dans **Git** et l'écriture dans **le cluster**.
12. Rédige, en dix lignes au plus, la réponse à Claire : « sommes-nous GitOps ? », avec les trois écarts principaux et l'exercice ou le module qui les traitera.

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 12 questions, en citant des objets et fichiers réels de ton lab.
- [ ] Tu as comparé tes réponses au corrigé et noté les écarts.

<details><summary>Indice 1</summary>

Les principes portent sur l'**état voulu** et sur les **agents**, pas sur un outil. Relis-les sur <https://opengitops.dev/> et leur glossaire (*desired state*, *state store*, *pull*, *reconciliation*, *drift*).
</details>

<details><summary>Indice 2</summary>

Pour chaque écart, demande-toi : « si le cluster disparaît, est-ce que je le reconstruis à l'identique à partir de ce qui est versionné, sans geste qui dépende de ma mémoire ? »
</details>

**Pour aller plus loin** (facultatif) : lis la page « Source Hydrator » d'Argo CD (bêta en 3.5) : un dépôt « sec » (gabarits) et un dépôt « hydraté » (manifestes rendus, commités par Argo CD). Rapproche-la du rendu commité de MédiAgenda (M17-E09) et du principe « versionné et immuable ».
