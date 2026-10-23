# Module 28 — Introduction : plateforme développeurs

## Six tickets et dix jours

Lundi, 9 h 15. Julien Petit pose sur la table de la réunion d'équipe un tableau qu'il a fait le week-end : la dernière création de service (le prototype de vignettes de MédiDoc) a demandé six tickets à la Plateforme — projet GitLab, base Kustomize, espaces et quotas, Application Argo CD, secrets, accès — et dix jours calendaires. À côté, un graphe du M21 : pendant la campagne de rappels de jeudi, la file `notifications` de MédiNotif est montée à 4 000 messages avec un seul consommateur ; la nuit, trois pods de MédiAgenda attendent des patients qui dorment. Claire Morel écrit le soir même.

> **De** : Claire Morel — Responsable infrastructure
> **À** : toi
> **Cc** : Karim Benali, Sophie Laurent, Julien Petit, Nadia Roussel
> **Objet** : Plateforme développeurs — libre-service encadré
>
> Bonjour,
>
> Je ne veux plus que la Plateforme soit un guichet. Ce que j'attends du module :
> 1. que le cluster **suive la charge** : MédiAgenda sur son CPU, MédiNotif sur sa file, et des requêtes de ressources mesurées plutôt que devinées ;
> 2. que chaque équipe ait **son locataire** : ses espaces, ses quotas, le droit de créer elle-même des espaces de travail, dans un cadre que nous posons (Pod Security, Kyverno, stockage, réseau) — Sophie relira ;
> 3. un **portail** qui dise qui possède quoi, où ça tourne, où est la doc, et qui crée un service complet **par MR**, sans ticket ;
> 4. une comparaison honnête avec les **clusters virtuels**, que Karim veut essayer avant d'en reparler.
>
> Rien de tout cela ne doit contourner GitOps : tout passe par Git et Argo CD, comme depuis le M20. Karim te fait d'abord passer le test habituel.
> Claire

---

## Ce que tu construis dans ce module

À la fin du module 28, MédiSphère a sa plateforme développeurs **v1** (étiquette `plateforme-dev-v1` de `plateforme/medisphere`, posée au mini-projet M28-E25). Les paliers 1 et 2 (ce fichier, `01-decouverte.md`, `02-operationnel.md`) en posent les briques :

| Brique | Où | Exercice |
|---|---|---|
| **HPA** `autoscaling/v2` `mediagenda` sur le Rollout `mediagenda` (recette, prod), avec `behavior` | `mediagenda/deploiement` (component `autoscaling`) | E02 |
| **KEDA 2.21** (Application `keda`, espace `keda`) ; `ScaledObject` `medinotif` sur la file `notifications` (recette), `TriggerAuthentication` `medinotif-rabbitmq` alimentée par ESO | `plateforme/gitops`, `medinotif/deploiement`, `plateforme/donnees` | E03 |
| **VPA 1.7.1** (Application `vpa`, espace `vpa`) en `Off` sur MédiAgenda, MédiNotif, MédiDoc ; essai de redimensionnement en place dans `wb-essais` | `plateforme/gitops`, dépôts `…/deploiement` | E04 |
| **Capsule 0.15** (Application `capsule`, espace `capsule-system`) ; locataires `mediagenda`, `medidoc`, `medinotif` | `plateforme/k8s/locataires/` (Application `locataires`) | E05 |
| **Backstage 1.56** : projet `plateforme/portail`, image signée, base CNPG `portail-db`, `https://portail.apps.par1.medisphere.internal`, connexion Keycloak (client `backstage`) | `plateforme/portail`, `plateforme/gitops` (Application `portail`) | E06 |
| Catalogue : découverte GitLab (`svc-portail`), organisation LDAP (`ipa01`), `catalog-info.yaml` des projets | dépôts applicatifs et de plateforme | E07 |
| Modèle « nouveau service » (*scaffolder*), essayé sur `medidoc-vignettes` | `plateforme/portail-modeles` | E08 |
| **vCluster 0.37** `vc-essai` dans `medidoc-vc-essai` (locataire `medidoc`), comparé puis **retiré** | `plateforme/gitops` (temporaire) | E09 |
| Plugins Kubernetes et TechDocs (compartiment `portail-techdocs` de `s3-01`) | `plateforme/portail`, CI des projets | E10 |
| Revue des manifestes de Lucas ; guide d'accueil d'une équipe et RB-280 | `docs/plateforme-dev/` | E11, E12 |

Le **palier 3** (`03-production.md`) met KEDA en production (zéro, cron, Prometheus, repli), règle la capacité et l'équité (PriorityClasses `medisphere-critique`, `-standard`, `-lot`), éprouve l'isolation des locataires, exploite Backstage (mise à jour, sauvegarde, supervision) et écrit l'ADR-0280. Le **palier 4** (`04-expert.md`) casse l'autoscaling, un locataire et le portail, puis descend dans la boucle de l'HPA et les webhooks de Capsule. Le **mini-projet** (`05-mini-projet.md`) livre l'ensemble.

## Architecture du module

```
                                   adm01 (MGMT) ── navigateur ──┐
                                                                ▼  https://portail.apps.par1.medisphere.internal
 ┌──────────────── k8s-par1 ───────────────────────────────────────────────────────────────────────────────┐
 │  gw-par1 (passerelles, 10.10.41.10) ──HTTPRoute──▶ portail : Backstage 1.56 ──▶ portail-db (CNPG, 1 inst.)│
 │                                                      │   │   │                                           │
 │   plugins : catalog ◀── découverte GitLab (svc-portail, git01:443) ── catalog-info.yaml des projets       │
 │             catalog ◀── LDAPS (svc-portail, ipa01:636) ── personnes et groupes de l'annuaire              │
 │             auth (OIDC) ── sso.par1.medisphere.internal (client backstage)                                │
 │             kubernetes (lecture) ── API du cluster ;  techdocs ── s3-01:8333 (portail-techdocs)           │
 │             scaffolder ── crée le projet GitLab, ouvre les MR dans plateforme/gitops et plateforme/k8s    │
 │                                                                                                          │
 │  kube-controller-manager ── boucle HPA (15 s) ──┬─ metrics.k8s.io ◀── metrics-server (CPU, mémoire)      │
 │                                                 └─ external.metrics.k8s.io ◀── KEDA (adaptateur)         │
 │      HPA mediagenda ──scale──▶ Rollout mediagenda (mediagenda-recette, -prod)                           │
 │      HPA keda-hpa-medinotif (créé par KEDA) ──scale──▶ Deployment medinotif (medinotif-recette)         │
 │  keda : opérateur ── HTTPS 15671 ──▶ messagerie/rabbitmq (API de gestion, file notifications)           │
 │  vpa  : recommender (lit metrics-server) → VerticalPodAutoscaler.status ; updater ; admission-controller│
 │  capsule-system : webhooks (espaces, PVC, …) ; Tenant mediagenda ⊃ mediagenda-dev/-recette/-prod/-secours│
 │                   Tenant medinotif ⊃ medinotif-recette/-prod ; Tenant medidoc ⊃ medidoc-dev/-recette     │
 │                   + espaces de libre-service <locataire>-…  (E09 : medidoc-vc-essai ⊃ vCluster vc-essai) │
 └──────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

Points structurants :

- **Un seul fournisseur par API de métriques.** `metrics.k8s.io` reste à metrics-server (installé par Helmfile au M17) ; `external.metrics.k8s.io` est enregistrée par l'adaptateur de KEDA. Un second fournisseur (prometheus-adapter, un autre KEDA) écraserait l'`APIService` et casserait les ScaledObjects en silence.
- **Personne ne se bat pour `replicas`.** Dès qu'un HPA (ou un ScaledObject, qui crée un HPA) pilote une charge, le champ `spec.replicas` ne doit plus être déclaré par Git, ou Argo CD doit l'ignorer : sinon chaque synchronisation remet la valeur du dépôt.
- **VPA et HPA ne pilotent jamais la même ressource.** Le VPA est en `Off` (recommandations) partout ; il n'agit qu'en essai.
- **Le locataire est une enveloppe, pas un nouveau chemin de livraison.** Capsule rattache les espaces existants à leur équipe et ouvre un libre-service préfixé ; les environnements restent livrés par Argo CD, avec leurs quotas posés par la plateforme.
- **Le portail lit, propose, et passe par des MR.** Backstage ne déploie rien lui-même : il crée un projet, ouvre des MR, et affiche ce qu'Argo CD a déployé.

---

## Concepts clés

Une synthèse pour se repérer ; les exercices approfondissent, la documentation officielle (liens en fin de fichier) fait foi.

**La boucle de l'HPA.** Le contrôleur d'autoscaling horizontal tourne dans `kube-controller-manager` et réévalue chaque HPA toutes les 15 s (`--horizontal-pod-autoscaler-sync-period`). Pour chaque métrique, il calcule `désiré = ceil(actuel × valeur_mesurée / valeur_cible)`, ignore les écarts sous la tolérance (10 %), retient **le maximum** des métriques, puis applique le `behavior`. Une utilisation CPU s'exprime **en pourcentage des `requests`** : sans `requests` CPU sur chaque conteneur, pas de calcul. La cible est désignée par `scaleTargetRef` et passe par la sous-ressource **`scale`** : tout objet qui l'expose (Deployment, StatefulSet, Rollout d'Argo…) peut être piloté.

**`behavior`.** La vitesse de réaction, séparément à la montée et à la descente : `stabilizationWindowSeconds` (la recommandation retenue est le maximum, à la descente, ou le minimum, à la montée, des recommandations de la fenêtre : c'est ce qui empêche l'oscillation), `policies` (au plus N pods ou N % par période) et `selectPolicy` (`Max`, `Min`, `Disabled`). Défauts : montée immédiate (fenêtre 0, +100 % ou +4 pods par 15 s), descente après 300 s de stabilisation.

**Trois familles de métriques.** *Resource* (CPU, mémoire des pods, via `metrics.k8s.io` servie par metrics-server) ; *Pods* et *Object* (métriques personnalisées attachées à des objets du cluster, via `custom.metrics.k8s.io`) ; *External* (une valeur extérieure au cluster — longueur d'une file, résultat d'une requête Prometheus —, via `external.metrics.k8s.io`). Chaque API est une `APIService` servie par **un** seul adaptateur.

**KEDA.** Un opérateur et un adaptateur de métriques. Tu déclares un **`ScaledObject`** (cible, bornes, déclencheurs) ; l'opérateur crée et tient à jour un **HPA** `keda-hpa-<nom>` dont les métriques sont externes, et l'adaptateur répond aux requêtes de l'HPA en interrogeant le **scaler** (RabbitMQ, Prometheus, cron… plus de soixante). KEDA gère lui-même le passage **de 0 à 1 et de 1 à 0** (l'« activation »), ce qu'un HPA ne sait pas faire. Les identifiants des scalers sont dans une **`TriggerAuthentication`** (ou `ClusterTriggerAuthentication`) qui référence des Secrets, jamais dans le `ScaledObject`.

**VPA.** Trois composants : le **recommender** observe la consommation (metrics-server, historique en `VerticalPodAutoscalerCheckpoint`) et écrit des recommandations (`target`, `lowerBound`, `upperBound`) dans le statut de chaque `VerticalPodAutoscaler` ; l'**updater** applique (évince, ou redimensionne en place) quand le mode le permet ; l'**admission-controller** (webhook) réécrit les `requests` des pods à leur création. Modes (`updatePolicy.updateMode`) : `Off` (recommander seulement), `Initial` (à la création des pods), `Recreate` (éviction), **`InPlaceOrRecreate`** (en place si possible, sinon éviction ; GA depuis VPA 1.6), `InPlace` (alpha) ; `Auto` est un ancien nom.

**Redimensionnement en place.** Depuis Kubernetes 1.35 (GA), les `resources` d'un conteneur en marche se modifient par la sous-ressource **`resize`** du pod, sans le recréer. Le champ `resizePolicy` de chaque conteneur dit, par ressource, si le changement exige un redémarrage du conteneur (`RestartContainer`) ou non (`NotRequired`). La classe de QoS du pod ne peut pas changer.

**Multi-locataire souple ou dur.** *Souple* : plusieurs équipes d'une même entreprise partagent un plan de contrôle ; on les sépare par espaces, RBAC, quotas, politiques réseau et d'admission (c'est le cas de MédiSphère). *Dur* : des locataires qui ne se font pas confiance ; il faut séparer aussi le plan de contrôle (clusters virtuels), voire les nœuds et le noyau (clusters dédiés, bacs à sable comme gVisor ou Kata).

**Capsule.** Un opérateur et des webhooks qui ajoutent la notion de **`Tenant`** (objet de cluster) : des **propriétaires** (utilisateurs, groupes, comptes de service) qui créent eux-mêmes des espaces rattachés au locataire (préfixe imposé, nombre limité), des quotas agrégés, des classes de stockage, de priorité ou de passerelle autorisées, des liaisons RBAC distribuées dans chaque espace, des règles par sous-ensemble d'espaces. Les règles de création et de propriété ne s'appliquent qu'aux **utilisateurs Capsule** (groupes déclarés dans la `CapsuleConfiguration`) : Argo CD et la plateforme ne sont pas contraints par elles, mais leurs objets dans un espace rattaché passent quand même par les webhooks de Capsule (classe de stockage d'un PVC, par exemple).

**vCluster.** Un plan de contrôle Kubernetes complet (API, contrôleurs, stockage) qui tourne **dans un espace** du cluster hôte, plus un **syncer** qui recopie dans cet espace les objets qui doivent vraiment tourner (pods, Services, PVC…) en les renommant. Le locataire est administrateur de *son* cluster (CRD, ClusterRoles, webhooks), mais ses pods tournent sur les nœuds de l'hôte, sous les quotas et politiques de l'espace hôte.

**Portail développeurs et chemins balisés.** Un portail regroupe ce qu'une équipe doit savoir et faire : qui possède quoi, où ça tourne, où est la doc, comment créer un service. Un **chemin balisé** (*golden path*) est la façon recommandée et outillée de faire une chose courante (créer un service, l'exposer, lui donner une base) : il n'est pas obligatoire, mais il est si commode qu'on n'a pas envie d'en sortir.

**Le catalogue de Backstage.** Des **entités** décrites en YAML (`apiVersion: backstage.io/v1alpha1`) : `Component` (un logiciel déployable), `API`, `Resource` (une base, une file, un compartiment), `System` (un ensemble cohérent), `Domain`, `Group` et `User` (l'organisation), `Location` (un pointeur vers d'autres fichiers), `Template`. Chaque entité a un **propriétaire** (`spec.owner`, un groupe de préférence) ; les relations (`partOf`, `dependsOn`, `ownedBy`, `memberOf`…) sont calculées par le catalogue. Les entités viennent de **fournisseurs** (*entity providers* : découverte GitLab, LDAP) et d'**emplacements** lus par des processeurs ; des **règles** limitent les types acceptés.

**Modèles (*scaffolder*).** Un `Template` décrit un formulaire (paramètres) et des **étapes** (*actions*) : récupérer un squelette et le remplir (`fetch:template`), publier un dépôt (`publish:gitlab`), ouvrir une MR (`publish:gitlab:merge-request`), enregistrer l'entité dans le catalogue (`catalog:register`). Les actions s'exécutent dans le backend avec **son** jeton : les droits du compte de service bornent ce qu'un modèle peut faire.

---

## Faits techniques du module (paliers 1 et 2)

| Élément | Valeur |
|---|---|
| Versions (PLAN §6) | KEDA **2.21.0** (chart `kedacore/keda` **2.21.0**) ; VPA **1.7.1** (chart `fairwinds-stable/vpa` **5.1.0**) ; Capsule **0.15.1** (chart `projectcapsule/capsule` **0.15.1**) ; Backstage **1.56.2** (`@backstage/create-app` **0.9.3**, Node.js **24**) et chart `backstage` **2.10.2** (OCI `ghcr.io/backstage/charts`) ; vCluster **0.37.4** (chart `loft/vcluster` **0.37.4**, image `vcluster-oss`, CLI `vcluster` 0.37.4) |
| Changements de version | [`annexes/versions-bloc-G.md`](../../../annexes/versions-bloc-G.md), section « Plateforme développeurs » |
| Espaces de plateforme | `keda`, `vpa`, `capsule-system`, `portail` (PSA `restricted`, créés dans `plateforme/k8s/espaces/`) |
| Dépôts | `plateforme/charts-miroir`, `plateforme/gitops` (`plateforme/<composant>.yaml`, `valeurs/<composant>/`), `plateforme/k8s` (`espaces/`, `locataires/`, `rbac/`), `plateforme/donnees` (topologie RabbitMQ), `mediagenda/deploiement`, `medinotif/deploiement`, `medidoc/deploiement`, **`plateforme/portail`** (application Backstage), **`plateforme/portail-modeles`** (modèles), `plateforme/identite` (client Keycloak, compte système), `plateforme/medisphere` (`docs/plateforme-dev/`) |
| Identités | client Keycloak **`backstage`** ; compte de service GitLab **`svc-portail`** ; compte système FreeIPA **`svc-portail`** (`uid=svc-portail,cn=sysaccounts,cn=etc,dc=par1,dc=medisphere,dc=internal`) ; utilisateurs RabbitMQ **`keda-recette`** (puis `keda-prod` au palier 3) ; secrets `kv/plateforme/portail`, `kv/medinotif/<env>/keda` |
| Groupes OIDC dans Kubernetes | `oidc:mediagenda` (Julien Petit ; possède aussi MédiNotif), `oidc:medidoc`, `oidc:plateforme`, `oidc:plateforme-admins` (M24-E17) |
| Documentation | `docs/plateforme-dev/` : `capacite.md`, `autoscaling.md`, `recommandations-ressources.md`, `locataires.md`, `portail.md`, `catalogue.md`, `modeles.md`, `comparatif-capsule-vcluster.md`, `revue-autoscaling-lucas.md`, `guide-accueil-equipe.md`, `runbooks/RB-280-creer-un-locataire.md` (puis `adr/ADR-0280-…` au palier 3) |
| Tickets | `PLAT-29xx`, `DEV-29xx`, `SEC-29xx`, `INC-55xx` (xx = numéro de l'exercice) |

### Valeurs à adapter

| Valeur | Signification |
|---|---|
| `<MOI>` | Ton compte personnel (GitLab, FreeIPA) |
| `<DIGEST-…>` | Empreintes d'images relevées dans Harbor (`crane digest`, `skopeo inspect`) |
| `<VERSION-PORTAIL>` | Étiquette `vX.Y.Z` de l'image `plateforme/portail` posée par semantic-release |
| `<RACINE-MEDISPHERE-EN-BASE64>` | Racine « MédiSphère Root CA » encodée en base64 (déjà utilisée par les SecretStore du M25) |

### Variables de `lab/lab.env`

Facultatives ; les valeurs par défaut conviennent :

```
WB_M28_RABBITMQ_SVC=rabbitmq.messagerie.svc.cluster.local      # Service de la grappe RabbitMQ (M27)
WB_M28_S3_TECHDOCS="$HOME/.config/workbook/s3-techdocs.env"    # identité de LECTURE du compartiment portail-techdocs (E10)
WB_M28_PORTAIL_URL=https://portail.apps.par1.medisphere.internal
WB_M28_APP_MEDINOTIF_RECETTE=medinotif-recette                  # Application Argo CD de MédiNotif en recette (ApplicationSet du M27)
WB_M28_IMAGE_BB=registry.par1.medisphere.internal/dockerhub/library/busybox:1.37   # essais (E14) et pannes (E23)
WB_M28_E21_WEBHOOK=                                              # « oui » autorise la variante 4 de la panne E21 (voir palier 4) : laisse vide
```

Les checks lisent aussi le cluster (compte `wb-checks` ; la ClusterRole agrégée `wb-checks-services-m28` que tu poses en E03 couvre KEDA, VPA et Capsule ; le reste — `APIService`, événements, PriorityClasses, politiques Kyverno, objets CNPG — est lisible depuis M14, M16 et M26), Argo CD par ses objets, Prometheus (`WB_PROM_URL`), GitLab (jeton `read_api`), l'API de gestion de RabbitMQ (`rabbitmq-checks.env`, M27), l'API du catalogue de Backstage (`backstage-checks.token`, créé en E06) et `s3-01` (`WB_S3_ENDPOINT`).

Fichiers créés dans `~/.config/workbook/` (700, fichiers en 600) : `backstage-checks.token` (E06), `s3-techdocs.env` (E10, identité de lecture).

---

## Règles du module

1. **Tout par Git.** Composants : charts recopiés par `plateforme/charts-miroir`, Application dans `plateforme/gitops`. Espaces, locataires, rôles : `plateforme/k8s` (`task espaces`, Application `locataires`). Objets des applications : leurs dépôts `…/deploiement`. Un `kubectl apply` à la main n'est permis que dans `wb-essais` et dans les espaces de **libre-service** des équipes (c'est leur raison d'être).
2. **Jamais deux pilotes pour un même champ.** Un HPA ou un ScaledObject possède `replicas` ; un VPA qui agit possède `requests`. Avant d'en ajouter un, vérifie qui écrit déjà ce champ (`managedFields`, `ignoreDifferences`).
3. **Pas de charge sur la production.** Les essais de charge visent `mediagenda-recette` et `medinotif-recette`, avec des données factices (`Essai-…`). La production reçoit les mêmes objets, par MR, sans essai de charge.
4. **Mémoire.** Profil du bloc G ≈ 111 Go. Ce palier ajoute ≈ 3 Gi de `requests` (KEDA ≈ 0,3, VPA ≈ 1,2, Capsule ≈ 0,1, Backstage ≈ 0,8 et sa base ≈ 0,5) ; le vCluster `vc-essai` ≈ 1 Gi de E09 à la fin du palier 2. Fais le bilan de capacité ci-dessous **avant** E02 et refais-le avant E06 et E09.
5. **Le locataire ne retire jamais un droit à la plateforme ni à Argo CD.** Avant d'appliquer un `Tenant` qui touche des espaces existants, relis ce que Capsule va y poser (RoleBindings, quotas) et ce qu'il bloquera.

---

## Préparer l'environnement

### État d'entrée : `donnees-v1`

Le mini-projet du M27 doit être vert : RabbitMQ en marche, MédiNotif en recette et en production, MédiAgenda qui publie.

```
admin@adm01:~$ lab/bin/check 27 25
admin@adm01:~$ git -C ~/medisphere fetch --tags && git -C ~/medisphere tag -l 'donnees-v1'
admin@adm01:~$ kubectl get applications.argoproj.io -n argocd | grep -E 'rabbitmq|medinotif|mediagenda|keda|vpa|capsule|portail'
admin@adm01:~$ kubectl -n messagerie get rabbitmqclusters.rabbitmq.com rabbitmq
admin@adm01:~$ kubectl -n medinotif-recette get deploy medinotif && kubectl -n medinotif-prod get deploy medinotif
admin@adm01:~$ kubectl get apiservices | grep -E 'metrics.k8s.io'
```

La dernière commande doit montrer `v1beta1.metrics.k8s.io` (metrics-server) **et aucune** `v1beta1.external.metrics.k8s.io` : si elle existe déjà, trouve qui la sert avant E03.

### Bilan de capacité

Avant d'ajouter quoi que ce soit, compare ce qui est **réservé** (`requests`) à ce qui est **allouable** sur chaque travailleur, et note la marge dans `docs/plateforme-dev/capacite.md` (tu le complèteras à chaque palier) :

```
admin@adm01:~$ kubectl describe nodes -l '!node-role.kubernetes.io/control-plane' | grep -A7 'Allocated resources'
admin@adm01:~$ kubectl top nodes
admin@adm01:~$ ssh root@pve01 'free -g | head -2'
```

Écris, par travailleur : allouable CPU et mémoire, `requests` actuelles, marge, et ce que tu prévois d'ajouter dans ce palier (tableau de la règle 4). Si la marge mémoire d'un travailleur passe sous 1,5 Gi, arrête ce qui ne sert pas avant E06 (composants temporaires des modules précédents, essais oubliés dans `wb-essais`).

---

## Indices, corrigé, vérifications

- Les vérifications se lancent depuis `adm01` : `lab/bin/check 28 <XX>`. Elles sont en lecture seule et ne lisent jamais un Secret.
- Celles d'E02 et E03 regardent l'historique des métriques (Prometheus) : lance les essais de charge **avant** de vérifier.
- Le corrigé (`corrige/`) donne une solution, le *pourquoi*, les alternatives, les pièges et la vision production. Les fichiers complets sont dans `corrige/fichiers/M28-EXX/` : `gitops/` reproduit `plateforme/gitops`, `k8s/` `plateforme/k8s`, `charts-miroir/`, `donnees/`, `identite/`, `mediagenda-deploiement/`, `medinotif-deploiement/`, `medidoc-deploiement/`, `portail/`, `portail-modeles/`, `medisphere/` la documentation.

## Ordre conseillé

```
E01 ─ E02 ─ E03 ─ E04 ─ E05                       (palier 1)
E06 ─ E07 ─┬─ E08
           ├─ E10
           └─ E09 (après E05) ─ E11 ─ E12          (palier 2)
```

1. **E01** à froid.
2. **E02 → E05** dans l'ordre : E03 pose la ClusterRole des checks que les suivants utilisent ; E04 vient après les deux autoscalers (il faut savoir ce qu'ils pilotent) ; E05 en dernier (il touche les espaces de tout le monde).
3. **E06** puis **E07** ; **E08** et **E10** dans l'ordre que tu veux ; **E09** après E05 (le vCluster vit dans un espace de libre-service) ; **E11** et **E12** à la fin.

Durée indicative : palier 1, 8 à 10 heures ; palier 2, 13 à 16 heures.

## Pour aller plus loin

- HPA : <https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/> · redimensionnement en place : <https://kubernetes.io/docs/tasks/configure-pod-container/resize-container-resources/>
- KEDA 2.21 : <https://keda.sh/docs/2.21/> (concepts, scaler RabbitMQ, opération)
- VPA : <https://github.com/kubernetes/autoscaler/tree/vertical-pod-autoscaler-1.7.1/vertical-pod-autoscaler>
- Capsule : <https://projectcapsule.dev/docs/>
- vCluster : <https://www.vcluster.com/docs/>
- Backstage : <https://backstage.io/docs/> (nouveau système de backend, *frontend system*, catalogue, scaffolder, TechDocs)
- Plateformes : *CNCF Platforms White Paper* (<https://tag-app-delivery.cncf.io/whitepapers/platforms/>), fiches [`crossplane.md`](../../../annexes/decouverte/crossplane.md) et [`tilt-skaffold.md`](../../../annexes/decouverte/tilt-skaffold.md)
