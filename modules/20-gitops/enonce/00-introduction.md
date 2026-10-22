# Module 20 — Introduction : GitOps et déploiement continu

## Qui applique quoi, et comment le savoir ?

Mardi, 9 h 10. Le module 19 a livré une CI propre : les images de MédiAgenda sont construites sans privilège, analysées, signées, et chaque étiquette `vX.Y.Z` ouvre une MR de promotion dans `mediagenda/deploiement`. Lundi pourtant, Nadia a passé une heure sur un incident de recette : un Deployment tournait avec trois réplicas au lieu de deux et une variable d'environnement que personne ne retrouvait dans Git. Lucas avait « corrigé vite fait » avec `kubectl edit` la semaine précédente. Personne ne l'avait vu.

> **De** : Claire Morel — Responsable infrastructure
> **À** : toi
> **Cc** : Karim Benali, Sophie Laurent, Julien Petit, Nadia Roussel
> **Objet** : GitOps — le cluster doit ressembler à Git, tout le temps
>
> Bonjour,
>
> L'incident de lundi n'est pas un problème de personne, c'est un problème de méthode : aujourd'hui, le cluster est dans l'état que le dernier `kubectl apply` ou le dernier job de CI lui a donné, et rien ne nous dit quand il s'en écarte. On passe au **GitOps** :
> 1. **Git est la seule source de vérité** : ce qui tourne est décrit dans un dépôt, relu en MR, et rien d'autre ;
> 2. un **contrôleur dans le cluster** tire (*pull*) cet état et le fait converger **en continu** ; une modification à la main est détectée, signalée, et effacée ;
> 3. les **promotions** de dev à la production se font par MR, par digest, et le retour arrière par `git revert` ;
> 4. les **déploiements progressifs** (canary, blue/green) s'arrêtent seuls quand les indicateurs se dégradent ;
> 5. la **CI n'a plus aucun droit d'écriture** sur les espaces applicatifs : c'est la demande de Sophie, et c'est la condition pour que le point 1 soit vrai.
>
> Le comité d'architecture a retenu **Argo CD** (Karim te fera comparer avec Flux, l'ADR tranchera). La couche de base du cluster reste sous Helmfile, Argo CD compris : on ne demande pas à un outil de se réparer lui-même. Tout ce qui vient ensuite (applications, Argo Rollouts, puis la supervision des modules 21 à 23) passera par Argo CD.
>
> Premier jalon : Argo CD installé proprement et sécurisé (pas de compte `admin` qui traîne), un dépôt `plateforme/gitops` qui décrit tout ce qu'il gère, des projets qui cloisonnent les équipes, et MédiAgenda dev repris sous Argo CD **sans redémarrer un seul pod** : Julien a une démonstration client jeudi.
> Claire

---

## Ce que tu construis dans ce module

À la fin du module 20, MédiSphère livre ses applications en **GitOps v1** (étiquette `gitops-v1` du dépôt `plateforme/medisphere`), socle des modules d'observabilité (21-23) et des blocs suivants :

- **Argo CD 3.5** dans l'espace `argocd`, installé par la release Helmfile `argocd` de `plateforme/k8s`, publié en `https://argocd.apps.par1.medisphere.internal` derrière la Gateway `gw-par1` ; comptes locaux jusqu'au SSO du M24 ;
- le dépôt **`plateforme/gitops`** : l'application **racine** (*App of Apps*) qui se gère elle-même, les **AppProjects** des équipes, les Applications et **ApplicationSets** ;
- MédiAgenda en `dev`, `recette` et `prod` sous Argo CD, promu par MR et par digest, avec des **canary** pilotés par **Argo Rollouts** et le plugin Gateway API, et des analyses qui interrompent un déploiement défaillant ;
- des **notifications** vers Mailpit, des **fenêtres de synchronisation**, un **RBAC** par équipe, un **cluster distant** (agence de Lyon) et une comparaison écrite avec **Flux** ;
- la CI réduite à la **validation** : plus aucun gestionnaire de champs que celui d'Argo CD sur les objets applicatifs ;
- ADR-0200, runbooks RB-200 et suivants, documentation dans `docs/livraison/gitops/`.

Le **palier 1** (ce fichier et `01-decouverte.md`) installe Argo CD par Helmfile, ouvre l'accès (interface, CLI, comptes locaux, jeton des vérifications), déploie une première application d'essai et en observe tous les états (synchronisation, santé, dérive, auto-réparation, suppression), crée le dépôt `plateforme/gitops` et l'application racine, cloisonne les équipes par des AppProjects, puis reprend MédiAgenda dev sans coupure. Il s'ouvre et se ferme sur un questionnaire.

## Architecture du module

```
                       adm01 (1001) 10.10.10.10 — MGMT
     argocd (CLI 3.5) · kubectl · helmfile · ~/src/{k8s,gitops,deploiement,ansible}
        │ https://argocd.apps.par1.medisphere.internal (gRPC-web)      │ helmfile -e par1 apply
        │                                                               │ (couche de base)
 ═══════╪═══════ gw01 / gw02 ═══════════════════════════════════════════╪══════════════════════
        │ 10.10.41.10:443 (gw-par1, joker *.apps)                       │ k8s-api…:8443
 ┌──────┴───────────────────────────── k8s-par1 ────────────────────────┴───────────────────┐
 │  passerelles/gw-par1 ──HTTPRoute (TLS terminé ici)──► argocd-server :80 (server.insecure) │
 │                                                                                           │
 │  espace argocd (release Helmfile « argocd », chart argo/argo-cd 10.10.5)                  │
 │   argocd-server ─────────── API, interface, RBAC, comptes locaux                          │
 │   argocd-repo-server ────── git clone + kustomize build / helm template ──► git01:443     │
 │   argocd-application-controller ── compare (diff côté serveur) et synchronise            │
 │   argocd-applicationset-controller · argocd-notifications-controller · argocd-redis      │
 │                                        │ server-side apply (gestionnaire argocd-controller)│
 │          ┌─────────────────────────────┼───────────────────────────┐                      │
 │          ▼                             ▼                           ▼                      │
 │   argocd (Applications,         wb-essais (labo)          mediagenda-dev (MédiAgenda)     │
 │   AppProjects : racine…)        E04-E05                   E08 · recette/prod : palier 2   │
 └───────────────────────────────────────────────────────────────────────────────────────────┘
 git01 (GitLab) : plateforme/gitops · formation/gitops-labo · mediagenda/deploiement
                  jetons de déploiement « argocd-lecture » (read_repository) par groupe
```

```
plateforme/gitops (main protégée)
├── racine/          racine.yaml (se gère elle-même) · applications.yaml · projets.yaml (E07)
├── projets/         plateforme · mediagenda · medidoc · labo · default (verrouillé)     (E07)
├── plateforme/      une Application par service de plateforme                       (E15 →)
└── applications/    labo.yaml (E06) · mediagenda-dev.yaml (E08) → ApplicationSets (E10 →)
```

Points structurants :

- **Le modèle *pull*.** Personne ne pousse dans le cluster : le contrôleur d'Argo CD, dans le cluster, lit Git et applique. La CI n'a plus besoin d'identifiants du cluster, et toute écriture hors de Git est une **dérive** visible.
- **Helmfile pour la couche de base, Argo CD pour le reste.** Argo CD tourne sur Cilium, cert-manager, ceph-csi… et sur lui-même : s'il les gérait, une erreur dans ses propres valeurs pourrait le rendre incapable de la réparer. La couche de base reste donc sous `helmfile` (M17), Argo CD compris (PLAN §4.11).
- **Une seule entrée HTTPS.** TLS est terminé par la Gateway Cilium (certificat joker de `gw-par1`), Argo CD sert en clair **derrière** elle (`server.insecure`). La CLI passe en **gRPC-web** (`--grpc-web`), que la route HTTP transporte sans configuration particulière.
- **Des Secrets hors de Git.** Les identifiants des dépôts sont des jetons de déploiement GitLab rangés en Ansible Vault `critique` et poussés dans le cluster par `plateforme/k8s/outils/secrets-k8s.sh` ; Git ne contient que des noms.

---

## Le chemin imposé

1. **Helmfile** (`plateforme/k8s`) : la release `argocd` (`releases/argocd.yaml.gotmpl`, `composants/argocd/values.yaml`), l'espace `argocd` (`espaces/argocd.yaml`), l'extension de la ClusterRole `wb-checks-livraison` (`rbac/`). Relus en MR, appliqués depuis `adm01` (`task espaces`, `task appliquer`, `helmfile -e par1 … apply`) comme au M17.
2. **`plateforme/gitops`** (créé en E06) : tout ce qu'Argo CD gère. Une modification d'Application, de projet ou de politique de synchronisation est une **MR**, jamais un `argocd app set` (sauf à l'E04-E05, sur l'application d'essai, pour apprendre).
3. **Les dépôts des équipes** (`mediagenda/deploiement`, `formation/gitops-labo`) restent la source des manifestes ; Argo CD ne fait que les lire.
4. **Secrets** : jetons de déploiement et mots de passe en Vault `critique` (`plateforme/k8s/secrets/argocd.yml`), Secrets créés par `secrets-k8s.sh` (composant `argocd`), jeton des vérifications dans `~/.config/workbook/argocd-checks.token` (600). Jamais de secret en argument de commande : les commandes `argocd` qui en demandent un le lisent au clavier si on ne le donne pas.
5. **Documentation** : `plateforme/medisphere`, dossier `docs/livraison/gitops/` (procédures, ADR-0200 au palier 3, runbooks RB-200 et suivants).

Une manipulation à la main n'est permise que pour **explorer** (`argocd app get`, `kubectl get`), pour l'application d'essai `labo` aux E04-E05, ou quand l'énoncé la demande comme geste à connaître (créer la racine une fois).

---

## Concepts clés

Une synthèse pour se repérer ; la documentation officielle (liens en fin de fichier) et les exercices approfondissent.

**GitOps.** Une façon d'opérer un système dont l'état voulu est **déclaratif**, **versionné et immuable**, **tiré automatiquement** par des agents et **réconcilié en continu** (les quatre principes d'OpenGitOps, E09). Git n'est qu'une réalisation possible du « magasin d'état » ; c'est la nôtre.

**Application.** L'objet central d'Argo CD (CRD `applications.argoproj.io`, dans l'espace `argocd`) : une **source** (dépôt, révision, chemin — dossier de manifestes, Kustomize ou chart Helm), une **destination** (cluster, espace) et un **projet**. Argo CD rend la source en manifestes (le *repo-server*), les compare aux objets vivants (le *controller*) et peut les appliquer (*sync*).

**Deux statuts indépendants.** Le **statut de synchronisation** (`Synced`, `OutOfSync`) dit si le cluster ressemble à Git. Le **statut de santé** (`Healthy`, `Progressing`, `Degraded`, `Missing`, `Suspended`, `Unknown`) dit si les objets fonctionnent (un Deployment dont les pods sont prêts, un Service, un PVC lié…). Une application peut être `Synced` et `Degraded` (Git décrit une image qui plante) ou `OutOfSync` et `Healthy` (quelqu'un a modifié un objet à la main et ça marche).

**Synchronisation automatique, auto-réparation, suppression.** Avec `automated`, Argo CD synchronise de lui-même quand **Git change**. Avec `selfHeal`, il corrige aussi quand **le cluster change** (une dérive). Avec `prune`, il supprime les objets qu'il a créés et qui ont disparu de Git ; sans lui, ils restent, signalés. Ce sont trois décisions distinctes : la production de MédiSphère n'aura pas les mêmes que le dev.

**Suivi des ressources.** Argo CD reconnaît « ses » objets à l'annotation `argocd.argoproj.io/tracking-id` (`<application>:<groupe>/<type>:<espace>/<nom>`), posée à la synchronisation. C'est elle qui fait d'un objet existant un objet géré, et qui permet de reprendre une charge sans la recréer (E08).

**Application du manifeste et comparaison.** Par défaut, Argo CD applique comme `kubectl apply` (côté client, annotation `last-applied-configuration`). L'option `ServerSideApply=true` utilise le *server-side apply* (gestionnaire de champs `argocd-controller`) : c'est la méthode de MédiSphère depuis le M17. Pour **comparer**, le diff « côté serveur » demande à l'API ce que donnerait l'application (*dry-run*), valeurs par défaut des CRD comprises : il évite les faux `OutOfSync`.

**AppProject.** Le cloisonnement : depuis quels dépôts, vers quels clusters et espaces, quels types d'objets (de cluster et d'espace) une Application peut déployer. Le projet `default` permet tout : on le verrouille (E07).

**App of Apps et ApplicationSet.** Une Application peut avoir pour manifestes… d'autres Applications : c'est l'*App of Apps*, qui amorce tout depuis une racine. Un **ApplicationSet** fabrique des Applications à partir d'un **générateur** (liste, dossiers Git, clusters) : une seule définition pour `dev`, `recette` et `prod` (palier 2).

**Argo Rollouts et Flux** (palier 2). Argo Rollouts remplace la stratégie d'un Deployment par des étapes (poids de trafic, pauses, analyses) ; Flux est l'autre grand outil GitOps de la CNCF, sans interface, fait de contrôleurs spécialisés : tu le compares à Argo CD sur une VM jetable.

---

## Faits techniques du module

| Élément | Valeur |
|---|---|
| Versions (PLAN §6) | **Argo CD 3.5.5** (chart `argo/argo-cd` **10.10.5**, dépôt `https://argoproj.github.io/argo-helm`) ; CLI `argocd` 3.5.5 sur `adm01` (rôle `outils_k8s`) ; Kustomize 5.8.1 et Helm 4.2.1 embarqués dans le *repo-server* ; Argo Rollouts 1.10.x (chart 2.43.x) et plugin Gateway API 0.17.0 au palier 2 ; Flux 2.9 (palier 2) |
| Changements de version | voir [`annexes/versions-bloc-DE.md`](../../../annexes/versions-bloc-DE.md), section « GitOps » : suivi par annotation par défaut depuis la 3.0, Helm 4 embarqué, *Source Hydrator* en bêta ; et pour le chart 10.10 : NetworkPolicy d'entrée créées par défaut pour chaque composant, routes Gateway API (`server.httproute`, `server.grpcroute`) intégrées |
| Release | `argocd` (Helmfile `plateforme/k8s`, `releases/argocd.yaml.gotmpl`, étiquettes `groupe=livraison`, `composant=argocd`), espace **`argocd`** (PSA `restricted`, `medisphere.internal/exposition=oui`) |
| Composants | `argocd-server`, `argocd-repo-server`, `argocd-application-controller` (StatefulSet), `argocd-applicationset-controller`, `argocd-notifications-controller`, `argocd-redis` ; Dex désactivé (SSO au M24) ; un réplica chacun jusqu'au M20-E27 |
| Images | par les caches Harbor : `registry.par1.medisphere.internal/quay/argoproj/argocd:v3.5.5`, `registry.par1.medisphere.internal/dockerhub/library/redis:8.6.4-alpine` |
| Accès | `https://argocd.apps.par1.medisphere.internal` : HTTPRoute `argocd-server` (espace `argocd`) sur `passerelles/gw-par1`, écouteur `https` (certificat joker `apps-joker`) ; serveur en HTTP derrière la Gateway (`server.insecure: true`) ; CLI : `argocd login argocd.apps.par1.medisphere.internal --grpc-web` |
| Comptes locaux (E03) | `<MOI-ARGO>` et `karim-benali` (`role:admin`), `julien-petit` et `nadia-roussel` (`role:readonly` en attendant le RBAC d'E24), `ci-lecture` (jetons d'API seulement, `role:readonly`) ; `admin` désactivé. **Aucun point dans un nom de compte** (voir E03) |
| Dépôts lus par Argo CD | `https://git01.par1.medisphere.internal/<groupe>/<projet>.git` ; un **jeton de déploiement** GitLab `argocd-lecture` (`read_repository`, avec expiration) par groupe (`plateforme`, `mediagenda`, `medidoc`, `formation`) ; modèles d'identifiants `repo-creds-<groupe>` ; racine MédiSphère dans `argocd-tls-certs-cm` (clés `git01.par1.medisphere.internal`, `registry.par1.medisphere.internal`) |
| Projets GitLab | `plateforme/gitops` (E06) ; `formation/gitops-labo` (E04, application d'essai `labo` dans `wb-essais`) ; `mediagenda/deploiement` (overlay `dev` en E08) ; `plateforme/k8s` ; `plateforme/ansible` (rôle `outils_k8s`) ; `plateforme/medisphere` (`docs/livraison/gitops/`) |
| Vérifications | `wb-checks` lit `applications`, `applicationsets`, `appprojects` d'`argoproj.io` (ClusterRole agrégée `wb-checks-livraison`, étendue en E03) ; API d'Argo CD en GET avec le jeton `ci-lecture` |
| Flux réseau | aucun nouveau au palier 1 : `K8S_TRAV` → `git01` 443 existe depuis le M19 (runners, agent), MGMT → 10.10.41.10:443 depuis le M15 |
| Secrets du palier | Vault `critique` : `plateforme/k8s/secrets/argocd.yml` (jetons de déploiement) et mots de passe des comptes locaux ; `adm01` (600) : `~/.config/workbook/argocd-checks.token`, `~/.config/argocd/config` (session de la CLI) |
| Numérotation | tickets `PLAT-21xx`, `INC-47xx`, `CHG-21xx`, `SEC-21xx`, `DEV-21xx` (xx = exercice) ; ADR-0200 ; RB-200 et suivants |
| Brouillons | `~/m20/eXX/` sur `adm01` (non versionnés, sans secret) |

### Valeurs à adapter

| Valeur | Signification |
|---|---|
| `<MOI>` | Ton compte GitLab personnel (M01-E05), aussi ton identité Kubernetes (M14-E06) |
| `<MOI-ARGO>` | Ton compte local Argo CD : `<MOI>` dont les points sont remplacés par des tirets (`jean.dupont` → `jean-dupont`) |

### Variables de `lab/lab.env`

Deux variables nouvelles, communes à tous les modules qui lisent Argo CD (les valeurs par défaut conviennent au lab) :

```
WB_ARGOCD_URL="https://argocd.apps.par1.medisphere.internal"     # serveur d'Argo CD (checks, M20 →)
WB_ARGOCD_TOKEN_FILE="$HOME/.config/workbook/argocd-checks.token" # jeton du compte ci-lecture (E03)
```

`WB_MOI` (bloc A) doit être renseigné : le check d'E03 en déduit le nom de ton compte local.

---

## Règles du module

1. **Un `delete` dans Argo CD peut supprimer des charges.** Supprimer une Application qui porte le finaliseur `resources-finalizer.argocd.argoproj.io` supprime **tous** ses objets ; activer `prune` supprime ce qui a disparu de Git. Avant tout `argocd app delete`, tout retrait de fichier dans `plateforme/gitops`, toute activation de `prune` : lis les finaliseurs (`kubectl -n argocd get application <A> -o jsonpath='{.metadata.finalizers}'`) et le diff (`argocd app diff`).
   > ⚠️ **Attention** : `argocd app delete` demande une confirmation ; `--cascade=false` laisse les objets en place. La racine et MédiAgenda n'ont **pas** de finaliseur, par construction. Les données (Cluster CNPG, PVC) portent `Prune=false,Delete=false` (E08).
2. **Argo CD ne se gère pas lui-même.** Les valeurs d'Argo CD changent par Helmfile (`helmfile -e par1 -l composant=argocd diff`, puis `apply`), jamais par `kubectl edit configmap argocd-cm` : la release écraserait la modification, et le dépôt ne ferait plus foi.
3. **À partir de l'E08, plus d'écriture concurrente.** Une charge reprise par Argo CD n'est plus modifiée par `kubectl apply` ni par un job de CI : Argo CD effacerait la modification (auto-réparation) ou se battrait avec elle. À partir de l'E30, c'est vrai pour tous les espaces applicatifs.
4. **Pas de vérification TLS désactivée** (`argocd login --insecure`, `--insecure-skip-server-verification`, `curl -k`) ni de secret en argument de commande. La racine MédiSphère est dans le magasin de `adm01` (M06) et dans `argocd-tls-certs-cm`.
5. **Le contexte est toujours explicite** pour `kubectl` (`--context k8s-par1`) ; pour `argocd`, vérifie le serveur courant (`argocd context`).
6. **Mémoire.** Profil des blocs D et E (≈ 100 Go, PLAN §4.11) : socle v4, `ceph-par1`, `k8s-par1` avec des travailleurs à 10 Go. Argo CD demande ≈ 1,1 Gio (somme des *requests*) et peut monter à ≈ 2,6 Gio (somme des limites). SonarQube et Jenkins (M19) doivent être retirés (`lab/bin/check 19 46` vert). `lyo-k3s01` et `flux01` (2 Go chacune) n'arrivent qu'au palier 2-3, jamais ensemble.

---

## Préparer `adm01`

Vérifie l'état d'entrée (fin du module 19, et ce qu'il suppose des modules 15 et 17) :

```
admin@adm01:~$ lab/bin/check 19 46
admin@adm01:~$ kubectl --context k8s-par1 get nodes
admin@adm01:~$ kubectl --context k8s-par1 -n passerelles get gateway gw-par1
admin@adm01:~$ kubectl --context k8s-par1 -n mediagenda-dev get deploy,rs,pods
admin@adm01:~$ cd ~/src/k8s && git pull && helmfile -e par1 list
admin@adm01:~$ ssh root@pve01 'free -g | head -2'
```

Le premier contrôle (mini-projet du module 19) doit être vert : runners, agent GitLab, promotion par MR dans `mediagenda/deploiement`, et SonarQube et Jenkins retirés. La Gateway doit être `Programmed`, MédiAgenda dev servi (pods prêts) : c'est lui que tu reprendras en E08 sans le redémarrer. `helmfile list` montre les releases de la couche de base (dont `gitlab-runner`, `buildkitd`, `gitlab-agent`) ; `argocd` n'y est pas encore. Il te faut une douzaine de gigaoctets libres sur `pve01` en plus du profil.

Prépare le dossier de brouillons :

```
admin@adm01:~$ mkdir -p ~/m20 && chmod 700 ~/m20
```

---

## Indices, corrigé, vérifications

- Les vérifications se lancent depuis `adm01` : `lab/bin/check 20 <XX>`. Elles sont en lecture seule : objets du cluster par le compte `wb-checks` (Applications et AppProjects à partir de E03), API d'Argo CD en GET avec le jeton `ci-lecture`, GitLab en lecture. Le seul accès avec ton identité personnelle constate l'**absence** d'un Secret (E03), sans jamais en lire le contenu.
- Les indices sont progressifs : ouvre-les un par un, seulement quand tu bloques.
- Le corrigé (`corrige/`) donne une solution, le *pourquoi*, les alternatives, les pièges et la vision production. Les fichiers complets sont dans `corrige/fichiers/M20-EXX/` : `k8s/` reproduit l'arborescence de `plateforme/k8s`, `gitops/` celle de `plateforme/gitops`, `deploiement/` celle de `mediagenda/deploiement`, `ansible/` celle de `plateforme/ansible`, `medisphere/` celle de la documentation. Un fichier n'apparaît que dans l'exercice qui le crée ou le modifie.
- Ressources fournies : `ressources/E04-gitops-labo/` (l'application d'essai), `ressources/E08-reprise/instantane.sh` (photographie en lecture seule d'un Deployment avant et après une reprise).

## Ordre conseillé

```
E01 ─ E02 ─ E03 ─ E04 ─ E05 ─ E06 ─ E07 ─ E08 ─ E09
```

1. **E01** — positionnement, à froid.
2. **E02 → E03** — installer, puis sécuriser l'accès : les checks suivants ont besoin du jeton `ci-lecture` et de l'extension de `wb-checks-livraison` faits en E03.
3. **E04 → E05** — l'application d'essai : tous les états d'une Application, sans risque.
4. **E06 → E07** — tout dans Git : la racine, puis les projets (dans cet ordre : les projets sont livrés par la racine).
5. **E08** — la reprise de MédiAgenda dev, quand tout le reste est en place.
6. **E09** — en dernier.

Durée indicative du palier 1 : 15 à 19 heures.

## Pour aller plus loin

- Documentation d'Argo CD (version stable) : <https://argo-cd.readthedocs.io/en/stable/> — en particulier *Core Concepts*, *Declarative Setup*, *Sync Options*, *Diff Strategies*, *Resource Tracking*, *Projects*.
- Chart Helm `argo-cd` : <https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd> (lis le `README.md` et les notes de montée de version du chart avant chaque changement de majeure).
- Comptes locaux et désactivation d'`admin` : <https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/>
- Amorçage d'un cluster, *App of Apps* : <https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/>
- Principes OpenGitOps : <https://opengitops.dev/>
- *Server-side apply* et gestionnaires de champs : <https://kubernetes.io/docs/reference/using-api/server-side-apply/>
