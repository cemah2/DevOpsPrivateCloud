# Module 17 — Introduction : livrer des paquets, pas des copies

## Trois copies du même fichier

Lundi, 9 h 15. Le cluster `k8s-par1` tourne depuis trois modules : réseau Cilium, Gateway `gw-par1`, certificats automatiques, stockage Ceph, base PostgreSQL CloudNativePG. MédiAgenda tourne en recette. Julien Petit a demandé un créneau à Claire Morel, et il est arrivé avec trois fichiers ouverts côte à côte.

> **De** : Claire Morel — Responsable infrastructure
> **À** : toi
> **Cc** : Karim Benali, Julien Petit, Sophie Laurent, Nadia Roussel
> **Objet** : Packaging — un paquet par application, un fichier pour la plateforme
>
> Bonjour,
>
> Julien m'a montré ce matin les manifestes de MédiAgenda. Il y en a trois copies, une par environnement, modifiées à la main : la recette a des limites mémoire que la copie de dev n'a plus, le nom publié est écrit en dur à quatre endroits, et personne ne sait dire quelle version de l'image tourne où sans aller lire le cluster. Ce n'est pas tenable pour une production HDS.
>
> Côté plateforme, ce n'est pas mieux. Depuis le module 14, nous avons installé Cilium, cert-manager, ExternalDNS, ceph-csi, CloudNativePG, Velero et metrics-server avec des commandes `helm install` copiées depuis les énoncés. Karim m'a posé une question simple : « quelle version de cert-manager tourne, avec quelles valeurs, et qui l'a décidé ? ». Personne n'a pu répondre sans se connecter au cluster.
>
> Ce que je veux à la fin du module :
> 1. un **chart Helm** `mediagenda`, versionné, testé (tests unitaires, `helm test`, chart-testing), publié en OCI dans Harbor et **signé** avec la clé MédiSphère ;
> 2. un dépôt **`mediagenda/deploiement`** qui décrit dev, recette et une nouvelle **production** par Kustomize, sans copie : une base, des overlays, des composants ;
> 3. toute la plateforme installée par Helm décrite dans **un seul `helmfile.yaml`** du projet `plateforme/k8s`, repris **sans réinstaller** quoi que ce soit, relu en MR ;
> 4. les migrations de schéma qui passent **avant** la nouvelle version, et un retour arrière qui fonctionne ;
> 5. un pipeline du chart, et une réponse écrite à la question « Helm, Kustomize ou les deux ? » (ADR-0170).
>
> Sophie rappelle deux règles : pas un mot de passe dans un paquet, et rien ne se déploie en production qui ne soit signé. Nadia veut savoir comment on débloque une release Helm à 3 h du matin. Ce module prépare directement la CI sur Kubernetes (M19) et GitOps (M20) : Argo CD consommera exactement ce que tu vas produire.
>
> Premier jalon : Helm maîtrisé sur un chart public, puis un premier chart MédiAgenda installé en dev.
> Claire

---

## Ce que tu construis dans ce module

À la fin du module 17, MédiSphère a son **packaging v1** (étiquette `packaging-v1` du dépôt `plateforme/medisphere`) :

- le **chart `mediagenda`** (projet GitLab `mediagenda/chart`) : valeurs validées par un schéma JSON, gabarits factorisés (dont un chart de bibliothèque `medisphere-commun`), dépendance facultative Valkey, base CloudNativePG facultative, migrations de schéma par *hook*, politiques réseau, tests ; publié dans le projet Harbor `charts` (`oci://registry.par1.medisphere.internal/charts/mediagenda`) et signé par Cosign ;
- le **dépôt de déploiement** `mediagenda/deploiement` : le rendu vérifié du chart, des overlays `dev`, `recette`, `prod` et des *components* (`dependances`, `haute-disponibilite`, `debogage`, `livraison`) ; l'espace **`mediagenda-prod`** ;
- la **plateforme sous Helmfile** : `helmfile.yaml` de `plateforme/k8s` qui décrit les releases des modules 14 à 16, avec un `helmfile diff` vide ;
- le pipeline du chart (palier 3), l'ADR-0170, le runbook RB-170 (release bloquée), et la compréhension de ce que Helm range dans le cluster.

Le **palier 1** te fait manipuler Helm 4 sur un chart public, écrire le premier chart MédiAgenda, découvrir Kustomize et rendre le chart solide (schéma, helpers). Le **palier 2** traite les tickets courants : dépendances, tests, publication signée, Kustomize avancé, Helmfile, revue, migrations.

## Architecture du module

```
  Développement du chart                     Publication                     Déploiement
  ───────────────────────                    ───────────                     ───────────
  mediagenda/chart (GitLab)                  Harbor reg01                    k8s-par1
  charts/mediagenda/                         registry.par1.medisphere.internal
   Chart.yaml  values.yaml                   ┌──────────────────────────┐
   values.schema.json                        │ projet « charts » (OCI)  │    mediagenda-dev   ← release Helm
   templates/  tests/  ci/      helm push    │  mediagenda:0.5.0        │      « mediagenda » (banc d'essai
  charts/medisphere-commun/   ─────────────▶ │   + signature Cosign     │       du chart : helm upgrade,
   (bibliothèque)               cosign sign  │  valkey:0.12.0 (miroir)  │       hooks, helm test)
  ct.yaml                                    └────────────┬─────────────┘
         │ helm lint · helm unittest · ct lint            │ helm pull + cosign verify
         ▼                                                ▼
   adm01 (puis runner02 au palier 3)        mediagenda/deploiement (GitLab)
                                             chart.env (version + digest)
                                             base/rendu/   ← outils/rendre-base.sh
                                             components/   dependances · haute-disponibilite
                                                           debogage · livraison
                                             overlays/     dev · recette · prod
                                                    │ kubectl apply --server-side -k
                                                    ▼
                                             mediagenda-recette, mediagenda-prod (Kustomize)

  plateforme/k8s (GitLab) : helmfile.yaml + releases/*.yaml.gotmpl + composants/<nom>/values.yaml
      helmfile -e par1 diff | apply ───▶ releases existantes : cilium, cert-manager, external-dns,
                                         ceph-csi-rbd, ceph-csi-cephfs, cnpg, plugin-barman-cloud,
                                         velero, metrics-server
```

Qui gère quoi, pendant tout le module (règle à ne jamais enfreindre : **un seul gestionnaire par objet**) :

| Espace | Géré par | Pourquoi |
|---|---|---|
| `mediagenda-dev` | Helm (release `mediagenda`, `helm upgrade` depuis `adm01`) | Banc d'essai du chart : hooks, tests, retours arrière. Il passe sous Kustomize au mini-projet (M17-E25) |
| `mediagenda-recette` | Kustomize (`overlays/recette`, à partir de M17-E04) | Chemin de livraison ; reprend le MédiAgenda du M14 (`mediagenda-api`) par un déploiement à côté puis une bascule ; base et Valkey du M16 restent hors du dépôt |
| `mediagenda-prod` | Kustomize (`overlays/prod`, à partir de M17-E09) | Nouvelle production, créée ici |
| `kube-system`, `cert-manager`, `external-dns`, `ceph-csi`, `cnpg-system`, `velero` | Helmfile (`plateforme/k8s`, à partir de M17-E10) | Releases des modules 14 à 16, reprises sans réinstallation |
| `wb-essais`, `wb-ct` | Toi, temporairement | Essais (E02) et tests de chart-testing (E07), vidés en fin d'exercice |

## Concepts clés

### Helm 4

Un **chart** est un répertoire (ou une archive `.tgz`) : `Chart.yaml` (métadonnées, dépendances), `values.yaml` (valeurs par défaut), `templates/` (gabarits Go + fonctions Sprig), éventuellement `values.schema.json`, `crds/`, `charts/` (dépendances). `helm install` **rend** les gabarits avec les valeurs, envoie les objets à l'API, et enregistre une **release** : un nom, un espace de noms, un historique de **révisions** (stocké par défaut dans des Secrets de l'espace de la release ; tu l'ouvriras au palier 4).

Helm 4 (novembre 2025) change des choses que tu croiseras dans de vieux tutoriels. Les points qui comptent ici, vérifiés sur la documentation et sur `helm 4.3 --help` :

| Sujet | Helm 3 | Helm 4.3 |
|---|---|---|
| Application des objets | *client-side* (fusion à trois voies, annotation de dernier état) | ***server-side apply* par défaut** pour une **nouvelle** release (`--server-side=true`) ; une release créée par Helm 3 garde sa méthode (`upgrade --server-side=auto`) ; conflits de champs signalés, `--force-conflicts` pour passer outre |
| Retour arrière automatique | `--atomic` | **`--rollback-on-failure`** (`--atomic` accepté avec un avertissement de dépréciation) |
| Remplacement forcé | `--force` | **`--force-replace`** |
| Attente | `--wait` (booléen) | `--wait=watcher` (par défaut quand `--wait` est donné seul ; fondé sur *kstatus*), `hookOnly` (par défaut sans `--wait`), `legacy` |
| Post-rendu | `--post-renderer <exécutable>` | `--post-renderer <nom d'un plugin>` : les post-rendus sont des **plugins** |
| Plugins | installés sans vérification | **vérifiés** à l'installation : `--verify=false` obligatoire pour un plugin non signé installé depuis Git (helm-unittest, helm-diff) |
| Registres OCI | `helm registry login <URL>` | `helm registry login <nom de domaine>` seulement ; installation **par digest** (`…@sha256:…`) |
| Charts | `apiVersion: v2` | `v2` inchangé (c'est celui du module) ; charts `v3` expérimentaux (`HELM_EXPERIMENTAL_CHART_V3`) |

Helm 3 ne reçoit plus que des correctifs de sécurité jusqu'au 10 février 2027 : on n'écrit plus rien de neuf pour lui. Documentation : <https://helm.sh/docs/overview> (aperçu de Helm 4), <https://helm.sh/docs/topics/charts/>, <https://helm.sh/docs/chart_template_guide/>.

### Kustomize

Kustomize ne connaît **pas de gabarits** : il part de manifestes complets (une **base**) et leur applique des transformations déclarées dans un `kustomization.yaml` (un **overlay**) : espace de noms, étiquettes, préfixe de noms, images, réplicas, correctifs (*patches* stratégiques ou JSON 6902), générateurs de ConfigMap et de Secret (avec un **suffixe d'empreinte** qui force le redéploiement quand le contenu change), **components** (morceaux réutilisables qu'on inclut ou non), **replacements** (recopier un champ dans d'autres). `kubectl apply -k` embarque Kustomize (5.8.1 dans kubectl 1.36) ; le binaire autonome est en 5.8.2 : `kustomize version` et `kubectl version` ne disent pas la même chose, c'est normal. Documentation : <https://kubectl.docs.kubernetes.io/references/kustomize/>.

### Helm *et* Kustomize

Les deux ne s'opposent pas : Helm sait **paramétrer et empaqueter** (un chart versionné, des valeurs typées, des dépendances, des hooks), Kustomize sait **décliner sans gabarit** (un overlay lisible, une différence par fichier). MédiSphère va utiliser Helm pour produire le paquet et Kustomize pour le décliner par environnement. Pour les brancher, MédiSphère a retenu un **rendu vérifié et commité** du chart signé, que les overlays déclinent ; tu le confronteras en M17-E09 à l'autre montage (Kustomize qui appelle Helm, `helmCharts`) et tu défendras le choix dans l'ADR-0170.

### Helmfile

Helmfile 1.8 décrit **un ensemble de releases** (chart, version, espace, valeurs, dépendances d'ordre) dans un fichier versionné, par environnement. `helmfile diff` (par le plugin helm-diff) montre l'écart avec le cluster, `helmfile apply` ne touche que les releases qui diffèrent. Helmfile 1.x a rompu avec 0.x sur un point visible : un fichier n'est rendu comme gabarit Go **que** s'il porte l'extension `.gotmpl`. Il prend en charge Helm 4 depuis la série 1.5 (option `--server-side`) et teste Helm 4.3 depuis 1.8.0. Documentation : <https://helmfile.readthedocs.io/>.

### Publication et signature

Harbor 2.15 n'a plus de ChartMuseum : un chart se publie comme **artefact OCI** (`helm push mediagenda-0.5.0.tgz oci://registry.par1.medisphere.internal/charts`). Il se signe comme une image, par **Cosign 3** et la clé MédiSphère du M13, **par digest**, sans journal de transparence public. Helm a aussi son propre mécanisme de *provenance* (fichier `.prov` signé par PGP, `helm verify`, `helm pull --verify`) : tu compareras les deux en M17-E08.

## Préparer l'environnement

**Profil de lab** : socle + `k8s-par1` démarré (6 nœuds) + `ceph-par1` démarré (volumes de MédiAgenda) + `reg01` (Harbor). Rien de nouveau côté VMs : ce module ne crée aucune VM.

**État d'entrée** : `lab/bin/check 16 46` doit être vert (`k8s-stockage-v1`). Vérifie en particulier :

```
admin@adm01:~$ kubectl get nodes
admin@adm01:~$ helm version --short                       # v4.3.x (installé au M14)
admin@adm01:~$ helm list -A                               # les releases des modules 14 à 16
admin@adm01:~$ kubectl -n mediagenda-recette get cluster.postgresql.cnpg.io,deploy,sts,httproute
admin@adm01:~$ curl -fsS https://mediagenda-recette.apps.par1.medisphere.internal/sante
```

Note la sortie de `helm list -A` dans `~/m17/journal.md` : c'est l'inventaire que M17-E10 reprendra (neuf releases attendues : `cilium`, `cert-manager`, `external-dns`, `ceph-csi-rbd`, `ceph-csi-cephfs`, `cnpg`, `plugin-barman-cloud`, `velero`, `metrics-server`). Ce qui a été installé par manifeste (CRD de la Gateway API, external-snapshotter) n'y figure pas : note-le aussi.

**Outils à ajouter sur `adm01`** (binaires amont vérifiés par leur somme, comme au M13 ; installés dans `~/.local/bin`, déjà dans le `PATH`) :

| Outil | Version | Source |
|---|---|---|
| Kustomize (autonome) | 5.8.2 | `kustomize_v5.8.2_linux_amd64.tar.gz` + `checksums.txt` de la release GitHub `kubernetes-sigs/kustomize` (étiquette `kustomize/v5.8.2`) |
| Helmfile | 1.8.1 | `helmfile_1.8.1_linux_amd64.tar.gz` + `helmfile_1.8.1_checksums.txt` (GitHub `helmfile/helmfile`) |
| chart-testing (`ct`) | 3.15.0 | `chart-testing_3.15.0_linux_amd64.tar.gz` + `checksums.txt` (GitHub `helm/chart-testing`) ; ses fichiers `etc/chart_schema.yaml` et `etc/lintconf.yaml` vont dans `~/.ct/` |
| yamllint, yamale | dernières | `uv tool install yamllint` et `uv tool install yamale` (exigés par `ct lint`) |
| Plugin helm-unittest | 1.2.1 | `helm plugin install https://github.com/helm-unittest/helm-unittest.git --version v1.2.1 --verify=false` |
| Plugin helm-diff | 3.15.x | `helm plugin install https://github.com/databus23/helm-diff --version v3.15.15 --verify=false` (Helmfile 1.8 a été validé avec 3.15.13 et plus récent) |

```
admin@adm01:~$ mkdir -p ~/m17 ~/.ct && cd ~/m17
admin@adm01:~/m17$ curl -fsSLO https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.8.2/kustomize_v5.8.2_linux_amd64.tar.gz
admin@adm01:~/m17$ curl -fsSLO https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.8.2/checksums.txt
admin@adm01:~/m17$ sha256sum --check --ignore-missing checksums.txt && tar -xzf kustomize_v5.8.2_linux_amd64.tar.gz -C ~/.local/bin kustomize
```

Fais de même pour Helmfile et `ct` (pour `ct` : `tar -xzf … ct etc/` puis `mv etc/*.yaml ~/.ct/`), puis installe les plugins. Contrôle :

```
admin@adm01:~$ kustomize version; helmfile --version; ct version | head -1
admin@adm01:~$ helm plugin list            # unittest 1.2.1, diff 3.15.x
```

> ⚠️ **Attention** : `--verify=false` désactive la vérification de signature du plugin, que Helm 4 a introduite justement pour les plugins tiers. On l'accepte ici pour deux plugins bien identifiés, épinglés par version, installés depuis leur dépôt officiel. Ne prends pas l'habitude de l'ajouter par réflexe : un plugin s'exécute avec tes droits et ton `~/.kube/config`.

**Clones de travail** (créés au fil des exercices) : `~/src/mediagenda-chart` (`mediagenda/chart`, E03), `~/src/mediagenda-deploiement` (`mediagenda/deploiement`, E04), `~/src/k8s` (`plateforme/k8s`, existant depuis le M14). Brouillons et journaux : `~/m17/eXX/`.

## Faits communs du module

| Élément | Valeur |
|---|---|
| Chart | `mediagenda` dans `charts/mediagenda/` du projet `mediagenda/chart` ; bibliothèque `medisphere-commun` dans `charts/medisphere-commun/` ; `ct.yaml` à la racine |
| Release de dev | `mediagenda` dans `mediagenda-dev` (objets nommés `mediagenda`) ; elle remplace le MédiAgenda du M14 (`mediagenda-api`, manifestes `k8s/dev/` de `mediagenda/api`), retiré en M17-E03 |
| Objets et étiquettes du chart | objets `mediagenda` ; étiquettes `app.kubernetes.io/name: mediagenda`, `app.kubernetes.io/instance: <release>`, `app.kubernetes.io/component: api` (le M14 avait `mediagenda-api`) ; Service en **port 80** vers le port `http` (8000) du conteneur, comme au M14 ; filtrage L7 de l'entrée repris du M15-E17 |
| Image | `registry.par1.medisphere.internal/medisphere/mediagenda-api:v<version>` (étiquettes `v*` immuables, signées, M13) ; `<VERSION-API>` = celle qui tourne en recette, par exemple `v1.0.0` |
| Base PostgreSQL | CNPG `mediagenda-db`, Secret `mediagenda-db-app` (clé `uri` : URL complète) ; recette : celle du M16 |
| Valkey | Service `valkey` (StatefulSet, étiquette `app.kubernetes.io/name: valkey`) hors chart ; `mediagenda-valkey` quand le sous-chart est activé |
| Noms publiés | `mediagenda-dev.apps.par1.medisphere.internal`, `mediagenda-recette.apps…`, `mediagenda.apps.par1.medisphere.internal` (prod) ; Gateway `gw-par1` (espace `passerelles`), écouteur `https` |
| Harbor | projet `charts` (privé, OCI) : `charts/mediagenda`, miroir `charts/valkey` ; robot `robot$charts+ci` (palier 2, pour la CI du palier 3) |
| Signature | Cosign 3.1, clé MédiSphère (`cosign.pub` dans `plateforme/medisphere`, `docs/registre/cosign.pub`), par digest, sans Rekor public : configuration de signature sans service `docs/registre/signing-config.json` et chargement de la clé par `outils/cosign-cle.sh` (M13-E07) ; en CI, image outillée `plateforme/outils-supply-chain` (M13-E09) |
| Plateforme | `plateforme/k8s` : `helmfile.yaml`, `releases/*.yaml.gotmpl`, `environnements/par1.yaml` ; valeurs dans `composants/` aux chemins des modules 14 à 16 (`composants/cilium/values.yaml`, `composants/ceph-csi/values-rbd.yaml`, `composants/cloudnative-pg/values.yaml`…) |
| Tickets | PLAT-18xx, DEV-18xx, SEC-18xx, INC-44xx |
| Documentation | `plateforme/medisphere`, `docs/kubernetes/packaging/` ; ADR-0170 ; RB-170 |

**Vérifications** : depuis `adm01`, `lab/bin/check 17 <XX>`. Les checks lisent le cluster avec le compte `wb-checks` (pas d'accès aux Secrets, donc **pas** à l'historique Helm : ils lisent les objets et leurs annotations `meta.helm.sh/*`), GitLab (jeton en lecture) et Harbor (robot en lecture). Certains lisent aussi les fichiers que tu déposes dans `~/m17/eXX/`. **Exception documentée** (paliers 3 à 5) : les contrôles qui ont besoin de l'état d'une release (`helm status`, `helm history`, `helm get`, `helmfile diff`, `kubectl diff --server-side`) utilisent ton kubeconfig personnel (`WB_K8S_ADMIN_KUBECONFIG`, `~/.kube/config` par défaut), en lecture seule. Les droits de lecture de `wb-checks` viennent des modules 14 à 16 (ClusterRoles `wb-checks-base`, `wb-checks-reseau` pour la Gateway API et cert-manager, `wb-checks-stockage` pour CloudNativePG) : ce module n'en ajoute pas.

Ordre conseillé : palier 1 dans l'ordre (E01 à E05), puis au palier 2 : E06 → E07 → E08 → E12 → E09 ; E10 et E11 quand tu veux (E10 ne dépend que du palier 1). E09 consomme la version 0.5.0 du chart, qui contient les migrations de E12.
