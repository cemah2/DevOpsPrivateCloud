# Module 21 — Introduction : métriques et alerting

## Personne n'avait de courbe

Lundi, 8 h 40. Le comité de direction a lu le compte rendu de l'incident du mois dernier : la production de MédiAgenda a répondu en dix secondes pendant toute une matinée, et ce sont les centres de santé qui ont prévenu le support. Nadia Roussel a écrit à toute l'équipe Plateforme le soir même ; Claire Morel répond ce matin.

> **De** : Claire Morel — Responsable infrastructure
> **À** : toi
> **Cc** : Karim Benali, Sophie Laurent, Julien Petit, Nadia Roussel
> **Objet** : Supervision — on arrête de piloter à l'aveugle
>
> Bonjour,
>
> Nadia a raison : nous avons livré un cloud privé, une CI, du GitOps, et nous n'avons **aucune** mesure de ce qui s'y passe. `kubectl top` et des intuitions, ce n'est pas une astreinte. Le contrat HDS que nous signons au printemps exige des **objectifs de niveau de service** chiffrés, et la preuve qu'on les tient.
>
> Ce que je veux à la fin du module :
> 1. des **métriques** de tout le lab : le cluster, les VMs du socle, Proxmox, Ceph, le réseau, et surtout nos applications ;
> 2. des **alertes** qui réveillent pour de bonnes raisons (un symptôme que les utilisateurs voient), routées vers la bonne équipe, avec un runbook ;
> 3. des **tableaux de bord** versionnés, pas bricolés à la souris sur un poste ;
> 4. une conservation longue sur notre stockage objet, et une supervision **de la supervision** qui ne tombe pas avec le cluster.
>
> Les règles de la maison s'appliquent : tout ce qui tourne dans le cluster passe par Argo CD ; les charts tiers par notre miroir ; les VMs par Ansible ; les secrets hors de Git. Sophie veut du TLS partout où transitent des métriques et un accès restreint aux API. Julien veut voir les métriques de MédiAgenda **sans ticket**, depuis son propre dépôt.
>
> Premier jalon : la pile de base dans le cluster, MédiAgenda collecté, un premier tableau de bord, un premier courriel d'alerte, et toutes les VMs du socle visibles. Karim te fait d'abord passer le test habituel.
> Claire

---

## Ce que tu construis dans ce module

À la fin du module 21, MédiSphère a sa supervision **v1** (étiquette `metriques-v1` de `plateforme/medisphere`), reprise par les modules 22 (journaux) et 23 (traces) et par les workbooks finaux :

- **kube-prometheus-stack** déployé par **Argo CD** dans l'espace `supervision` : prometheus-operator 0.94, **Prometheus 3.15**, **Alertmanager 0.34**, kube-state-metrics 2.20, node-exporter 1.12, **Grafana 13.2** ;
- le projet GitLab **`plateforme/observabilite`** : values du chart, règles, `ScrapeConfig`, routes, tableaux de bord *as code*, SLO, tests ; les **ServiceMonitor** des applications dans les dépôts `…/deploiement` des équipes ;
- des cibles hors cluster : **node_exporter** en TLS sur toutes les VMs, exportateurs natifs (Ceph, HAProxy, PowerDNS, GitLab, Harbor), Proxmox par pve-exporter ;
- une supervision **témoin** sur `mon01`, hors du cluster ; **Thanos** sur le RGW de `ceph-par1` ; **Pyrra** pour les SLO ;
- ADR-0210, `politique-alerte.md`, `politique-budget-erreur.md`, runbooks RB-210 et suivants.

Le **palier 1** (ce fichier et `01-decouverte.md`) déploie la pile, apprend à lire Prometheus et à écrire du PromQL, branche Grafana et Alertmanager, fait collecter MédiAgenda et MédiDoc par leurs propres dépôts, et passe node_exporter en TLS sur le socle. Il s'ouvre et se ferme sur un questionnaire.

## Architecture du module (fin du palier 1)

```
 adm01 (MGMT 10.10.10.10)                                     mon01 (10.10.20.19) — Mailpit SMTP 25
  │  promtool · amtool · navigateur                             ▲        (témoin Prometheus : palier 2)
  │                                                             │ SMTP STARTTLS (racine MédiSphère)
  │ http://prometheus.apps…:9090   http://alertmanager.apps…:9093   https://grafana.apps…
  ▼                ▼                          ▼                            ▼
 ════ gw01/gw02 (BGP : 10.10.41.0/24 appris des nœuds) ═══════════════════════════════════════
  │ 10.10.41.60:9090        10.10.41.61:9093                 10.10.41.10:443 (gw-par1, M15)
  │ Service LB              Service LB                        HTTPRoute grafana.apps…
  │ prometheus-externe      alertmanager-externe              │
  │ (eTP Local, CNP :       (eTP Local, CNP :                 │
  │  MGMT + mon01)           MGMT + mon01)                    │
 ┌┴──────────────────────────┴──────── k8s-par1 ─ espace supervision (PSA restricted) ──┴──────┐
 │ prometheus-kps-0 ──règles──► alertmanager-kps-0 ──courriels──► mon01:25                       │
 │   ▲   ▲    ▲   ▲               kps-operator (CRD, webhooks cert-manager)  kps-grafana (PVC)  │
 │   │   │    │   └ ScrapeConfig vms (HTTPS) ─────────────────────► VMs du socle :9100 (TLS)    │
 │   │   │    └ ServiceMonitor/PodMonitor des équipes ─► mediagenda-{dev,recette,prod}, medidoc │
 │   │   └ kube-state-metrics, kubelet/cAdvisor, kube-apiserver                                 │
 │   └ node-exporter (DaemonSet, espace supervision-noeuds, PSA privileged : exception écrite)  │
 └──────────────────────────────────────────────────────────────────────────────────────────────┘
        ▲ Argo CD : Application kube-prometheus-stack (chart OCI Harbor charts/ + $values)
        │           Application observabilite (kustomize de plateforme/observabilite)
   git01 : plateforme/gitops · plateforme/observabilite · mediagenda/deploiement · medidoc/deploiement
```

Points structurants :

- **Prometheus tire** (*pull*) : il va chercher les métriques sur chaque cible, à intervalle fixe, et sait donc quand une cible ne répond plus (`up == 0`). Il ne reçoit rien qu'on lui pousse (sauf réception *remote write*, qu'on n'active pas ici).
- **L'opérateur traduit des objets en configuration.** On ne touche jamais `prometheus.yml` : on écrit des `ServiceMonitor`, `PodMonitor`, `ScrapeConfig`, `PrometheusRule` ; l'opérateur les sélectionne **par étiquette** et régénère la configuration. Le sélecteur de MédiSphère est **`medisphere.internal/supervision: "oui"`** : un objet sans cette étiquette n'existe pas pour Prometheus, sans aucune erreur.
- **Les équipes déclarent, la plateforme collecte.** Le ServiceMonitor de MédiAgenda vit dans `mediagenda/deploiement` (`components/supervision`) ; le flux réseau qui le rend possible est posé par la plateforme.
- **Pas de Gateway pour les API de supervision.** Prometheus et Alertmanager sont publiés par deux Services `LoadBalancer` à adresse fixe, filtrés par CiliumNetworkPolicy (MGMT et `mon01` seulement) : ce sont des API d'exploitation, sans authentification, que seules l'équipe Plateforme et la supervision témoin doivent joindre. Grafana, lui, passe par la Gateway `gw-par1` (HTTPS, comptes).

### Ports et flux du palier 1

| Flux | Port | Exercice | État sur `gw01`/`gw02` |
|---|---|---|---|
| MGMT → 10.10.41.60, 10.10.41.61 | 9090, 9093 | E02 | existant : MGMT joint tout le lab ; filtré par CiliumNetworkPolicy |
| MGMT → Grafana par `gw-par1` (10.10.41.10) | 443 | E02, E05 | existant (M15) |
| Alertmanager (travailleurs, `K8S_TRAV`) → `mon01` | 25 | E06 | existant (M19-E03 : VLAN 40 → `mon01` 25) |
| Prometheus → pods des espaces d'équipe | 8000, 8080, 9187 | E07 | interne au cluster : CiliumClusterwideNetworkPolicy `collecte-prometheus` |
| `K8S_TRAV` → VMs du socle, et les passerelles elles-mêmes | 9100 (HTTPS) | E08 | **nouveau** : `pare_feu_transit` et `pare_feu_entree` + pare-feu local des VMs |
| `ca01` → VMs du socle (défi ACME HTTP-01, première émission) | 80 | E08 | existant pour les hôtes qui ont déjà un certificat ACME ; à vérifier pour les autres |

Les flux internes au cluster vont dans `docs/kubernetes/reseau/matrice-flux-cluster.md`, ceux de la bordure dans `group_vars/role_routeur/pare_feu.yml` et `docs/socle/matrice-flux.md`.

---

## Le chemin imposé

1. **Argo CD** (M20) : une Application par composant de plateforme dans `plateforme/gitops/plateforme/`, projet `plateforme`. Le chart **kube-prometheus-stack** est d'abord recopié et signé dans Harbor `charts/` par `plateforme/charts-miroir` : Argo CD ne tire rien d'Internet.
2. **`plateforme/observabilite`** (créé en E02, structuré en E07) : `kps/values.yaml` (lu par Argo CD comme source `$values`), puis `regles/`, `scrape/`, `alertmanager/`, `tableaux/`, `requetes/`, `tests/`, un pipeline de validation ; l'Application **`observabilite`** applique ce qui doit l'être.
3. **`plateforme/k8s`** (couche de base, M14-M17) : les espaces de noms (`espaces/`), les ClusterRoles des vérifications (`rbac/`), les politiques réseau transverses (`composants/reseau/politiques/`), les Secrets par `outils/secrets-k8s.sh` (Ansible Vault `critique`, `secrets/<composant>.yml`).
4. **Dépôts des équipes** : `mediagenda/deploiement` et `medidoc/deploiement` reçoivent un component kustomize `components/supervision`, par MR relue par Julien Petit.
5. **Ansible** (`plateforme/ansible`, pipeline protégé, ADR-0040) : le rôle `node_exporter` passe en version 2 (TLS), le playbook `supervision-cibles.yml` génère la liste des cibles depuis NetBox.
6. **Documentation** dans `plateforme/medisphere`, dossier **`docs/observabilite/metriques/`**.

Une manipulation à la main n'est permise que pour **explorer** (interface de Prometheus, `amtool` en lecture, une alerte d'essai envoyée par `amtool alert add`) ou quand l'énoncé la demande.

---

## Concepts clés

Une synthèse pour se repérer ; la documentation officielle (liens en fin de fichier) et les exercices approfondissent.

**Série temporelle.** Une métrique est un nom et un ensemble d'**étiquettes** : `mediagenda_http_requests_total{namespace="mediagenda-prod", route="/api/v1/creneaux", code="200"}`. Chaque combinaison distincte d'étiquettes est une **série**, qui reçoit un **échantillon** (horodatage, valeur flottante) à chaque collecte. Le coût de Prometheus se compte en séries actives : c'est la **cardinalité**.

**Types de métriques.** Un **compteur** (*counter*) ne fait que croître (sauf remise à zéro au redémarrage) : on ne regarde jamais sa valeur, on calcule sa vitesse (`rate`, `increase`). Une **jauge** (*gauge*) monte et descend (mémoire, file d'attente). Un **histogramme** répartit des observations (durées) dans des compartiments cumulés (`_bucket{le="0.25"}`), avec leur somme et leur nombre (`_sum`, `_count`) : on en tire des quantiles **après agrégation**. Un **résumé** (*summary*) calcule ses quantiles côté client : impossible à agréger entre pods.

**PromQL.** Un langage de requêtes sur ces séries : sélecteurs (`{job="mediagenda", code=~"5.."}`), vecteurs instantanés et intervalles (`[5m]`), fonctions (`rate`, `histogram_quantile`, `absent`), agrégations (`sum by (namespace)`), opérations entre vecteurs (qui ne se correspondent que sur des étiquettes identiques, sauf `on`/`ignoring`/`group_left`).

**Découverte et relabeling.** Prometheus découvre ses cibles (API Kubernetes, fichiers, DNS, listes statiques), chacune avec des étiquettes temporaires (`__meta_kubernetes_pod_name`, `__address__`…). Le **relabeling** décide quelles cibles garder et quelles étiquettes finales leur donner ; le *metric relabeling* fait de même sur les séries collectées.

**L'opérateur.** prometheus-operator gère Prometheus et Alertmanager comme des objets Kubernetes (`Prometheus`, `Alertmanager`) et traduit les `ServiceMonitor` (cibles derrière un Service), `PodMonitor` (pods sans Service), `ScrapeConfig` (tout le reste : VMs, fichiers, DNS), `Probe` (sondes blackbox) et `PrometheusRule` (règles) en configuration.

**Règles et alertes.** Prometheus évalue des **règles d'alerte** (une expression qui renvoie des séries = des alertes actives, éventuellement après une durée `for`) et les envoie à **Alertmanager**, qui les **regroupe**, les **route** vers un récepteur (courriel, webhook…), les **inhibe** (une alerte en cache une autre) et les **tait** (silences). Prometheus détecte, Alertmanager notifie.

**Grafana.** Il interroge Prometheus (source de données) et affiche des tableaux de bord ; il ne stocke aucune métrique.

**Symptôme et cause.** On alerte sur ce que l'utilisateur subit (taux d'erreurs, latence, indisponibilité) ; les causes (CPU, disque, pod redémarré) servent au diagnostic et aux tableaux de bord. Les **SLI/SLO** (palier 3) formalisent cette idée.

---

## Faits techniques du module

| Élément | Valeur |
|---|---|
| Versions (PLAN §6) | chart **kube-prometheus-stack 92.11.0** (prometheus-operator **0.94.1**, Prometheus **3.15.0** (image `-distroless`), Alertmanager **0.34.1**, kube-state-metrics **2.20.0**, node-exporter **1.12.1**, Grafana **13.2.4** du sous-chart `grafana-community/grafana` 14.0.1) ; node_exporter amont **1.12.1** sur les VMs ; `promtool` 3.15.1 et `amtool` 0.34.1 sur `adm01` |
| Changements de version | [`annexes/versions-bloc-DE.md`](../../../annexes/versions-bloc-DE.md), section « Métriques et alertes » : images distroless, `ScrapeConfig` en `v1alpha1`, sous-chart Grafana déménagé, schéma de tableau de bord v2 de Grafana 13, `grafana-cli` supprimé |
| Application Argo CD | **`kube-prometheus-stack`** (projet `plateforme`, release `kps`, espace `supervision`) ; **`observabilite`** (E07) |
| Noms des objets (fixés par E02) | CR `Prometheus` **`supervision/kps`** (StatefulSet `prometheus-kps`, pods `prometheus-kps-N`) ; CR `Alertmanager` **`supervision/kps`** (pods `alertmanager-kps-N`, configuration dans le Secret `alertmanager-kps`) ; Services internes `kps-prometheus:9090`, `kps-alertmanager:9093`, `kps-grafana:80`, `prometheus-operated` ; Deployments `kps-operator`, `kps-kube-state-metrics`, `kps-grafana` ; DaemonSet `kps-prometheus-node-exporter` (espace **`supervision-noeuds`**) |
| Sélecteur de l'opérateur | étiquette **`medisphere.internal/supervision: "oui"`** sur tout `ServiceMonitor`, `PodMonitor`, `PrometheusRule`, `ScrapeConfig`, `Probe`, dans **tous** les espaces |
| Accès | `prometheus.apps.par1.medisphere.internal` → **10.10.41.60**:9090 (Service `prometheus-externe`) ; `alertmanager.apps.par1.medisphere.internal` → **10.10.41.61**:9093 (Service `alertmanager-externe`) ; `https://grafana.apps.par1.medisphere.internal` (HTTPRoute sur `gw-par1`) |
| Stockage | Prometheus : 40 Gio `ceph-rbd`, rétention **15 j** (et 32 Go au plus) ; Alertmanager : 1 Gio ; Grafana : 5 Gio (SQLite) |
| Étiquettes d'alerte | **`gravite`** (`critique`, `avertissement`, `info`), **`equipe`** (`plateforme`, `mediagenda`, `medidoc`) ; annotations `resume`, `description`, `runbook_url` |
| Récepteurs (E06) | `plateforme-mail` (`plateforme@medisphere.internal`), `astreinte-mail` (`astreinte@`), `mediagenda-mail` (`mediagenda@`), `medidoc-mail` (`medidoc@`) ; SMTP `smtp.par1.medisphere.internal:25` (STARTTLS, racine MédiSphère) |
| Jobs Prometheus | `kubelet`, `apiserver`, `node-exporter`, `kube-state-metrics`… (chart) ; **`mediagenda`**, **`mediagenda-db`**, **`medidoc`** (E07) ; **`vms`** (E08) |
| Projets | `plateforme/observabilite` (E02, E07) ; `plateforme/gitops` (`plateforme/kube-prometheus-stack.yaml`, `plateforme/observabilite.yaml`) ; `plateforme/charts-miroir` ; `plateforme/k8s` (`espaces/supervision.yaml`, `espaces/supervision-noeuds.yaml`, `rbac/wb-checks-observabilite.yaml`, `composants/reseau/politiques/collecte-prometheus.yaml`) ; `plateforme/ansible` (rôle `node_exporter` v2, playbooks `node-exporter.yml`, `supervision-cibles.yml`) |
| Documentation | `docs/observabilite/metriques/` de `plateforme/medisphere` : `exploration.md` (E03), `acces.md` (E05) ; runbooks RB-210 et suivants au palier 2 ; ADR-0210 au palier 3 |
| Tickets | PLAT-22xx, DEV-22xx, SEC-22xx, INC-48xx (xx = exercice) |
| Brouillons | `~/m21/eXX/` sur `adm01` (non versionnés, sans secret) |

### Valeurs à adapter

| Valeur | Signification |
|---|---|
| `<MOI>` | Ton compte GitLab personnel (M01-E05), aussi ton compte dans Grafana (E05) |
| `<CONTENU-DE-medisphere-root-ca.crt>` | Le certificat de la racine MédiSphère (`/usr/local/share/ca-certificates/medisphere-root-ca.crt` d'`adm01`), public, recopié dans `kps/values.yaml` (E06) |
| `<VERSION-CI-TEMPLATES>` | La dernière version publiée des composants de `plateforme/ci-templates` (v2.2.0 en fin de M19) |

### Variables de `lab/lab.env`

Les fonctions de vérification du bloc E existent déjà ; leurs adresses par défaut conviennent au lab. Le palier 1 ajoute trois variables facultatives :

```
WB_PROM_URL="http://prometheus.apps.par1.medisphere.internal:9090"     # prom_api, prom_requete
WB_AM_URL="http://alertmanager.apps.par1.medisphere.internal:9093"     # am_api
WB_GRAFANA_URL="https://grafana.apps.par1.medisphere.internal"         # grafana_api
WB_GRAFANA_TOKEN_FILE="$HOME/.config/workbook/grafana-checks.token"    # jeton Viewer (E05)
WB_M21_VMS_SOCLE=15                  # VMs du socle supervisées par node_exporter (E08)
WB_M21_HOTES_TLS="mon01 dns01"       # hôtes dont le check E08 vérifie le TLS depuis adm01
WB_M21_NOEUDS=6                      # nœuds de k8s-par1 (DaemonSet node-exporter, kubelets)
```

Si ton socle compte plus ou moins de 15 VMs (une VM ajoutée ou retirée dans un module précédent), ajuste `WB_M21_VMS_SOCLE` au nombre de VMs étiquetées `socle` dans NetBox.

---

## Règles du module

1. **La supervision ne supprime rien.** Les volumes de Prometheus, d'Alertmanager et de Grafana portent l'historique : pas de `kubectl delete pvc`, pas de suppression de l'Application `kube-prometheus-stack` en cascade.
   > ⚠️ **Attention** : supprimer l'Application `kube-prometheus-stack` avec suppression en cascade supprime aussi les **CRD** de l'opérateur, donc **tous** les `ServiceMonitor`, `PrometheusRule`… de **tous** les espaces, y compris ceux des équipes. C'est pourquoi cette Application n'a pas de finaliseur de suppression (E02).
2. **Ce qui est collecté se décide par étiquette.** Un objet de supervision sans `medisphere.internal/supervision: "oui"` est ignoré en silence. Quand une cible « n'apparaît pas », c'est la première chose à vérifier.
3. **Pas de vérification TLS désactivée** : ni `insecureSkipVerify` dans une configuration de collecte que tu écris, ni `curl -k`. La racine MédiSphère est distribuée là où il faut (ConfigMap `racine-medisphere`, magasin système des VMs). Seule exception héritée du chart : la collecte des kubelets (certificats auto-signés, discutée en E02 et traitée en E29).
4. **Pas de charge sur la production.** Le trafic d'essai (E04, E05) vise la **recette** ; les alertes d'essai portent un nom qui commence par `Essai`.
5. **Mémoire.** Profil des blocs D et E ≈ 100 Go (socle v4, `ceph-par1`, `k8s-par1` à travailleurs de 10 Go). La pile du palier 1 demande environ 2,5 Go de requêtes mémoire dans le cluster (Prometheus 1 Gio, Grafana, Alertmanager, opérateur, kube-state-metrics, six node-exporter). Aucun composant temporaire d'un module précédent ne doit tourner (Jenkins, SonarQube, `lyo-k3s01`, `flux01`).

---

## Préparer `adm01`

Vérifie d'abord l'état d'entrée :

```
admin@adm01:~$ lab/bin/check 20 46        # mini-projet du M20 : Argo CD, charts-miroir, Rollouts
admin@adm01:~$ lab/bin/check 19 03        # mon01 et Mailpit
admin@adm01:~$ kubectl --context k8s-par1 get nodes
admin@adm01:~$ kubectl --context k8s-par1 -n argocd get applications
admin@adm01:~$ kubectl --context k8s-par1 get ns supervision --show-labels
admin@adm01:~$ ssh root@pve01 'free -g | head -2'
```

Le premier contrôle doit être vert : Argo CD gère `plateforme/gitops`, le miroir de charts publie dans Harbor `charts/`, les Rollouts de MédiAgenda tournent en recette et en prod. L'espace `supervision` existe depuis M15-E26 (compte `ms-supervision`). Il te faut environ 10 Go libres sur `pve01` en plus du profil.

Installe `promtool` et `amtool` (ils servent à vérifier règles, requêtes et configuration d'Alertmanager **avant** une MR), depuis les archives amont, **vérifiées par empreinte** :

```
admin@adm01:~$ mkdir -p ~/m21/outils && cd ~/m21/outils
admin@adm01:~/m21/outils$ curl -fsSLO https://github.com/prometheus/prometheus/releases/download/v3.15.1/prometheus-3.15.1.linux-amd64.tar.gz
admin@adm01:~/m21/outils$ curl -fsSL -o sha256sums-prometheus.txt https://github.com/prometheus/prometheus/releases/download/v3.15.1/sha256sums.txt
admin@adm01:~/m21/outils$ curl -fsSLO https://github.com/prometheus/alertmanager/releases/download/v0.34.1/alertmanager-0.34.1.linux-amd64.tar.gz
admin@adm01:~/m21/outils$ curl -fsSL -o sha256sums-alertmanager.txt https://github.com/prometheus/alertmanager/releases/download/v0.34.1/sha256sums.txt
```

Vérifie chaque archive contre son fichier de sommes (`sha256sum -c --ignore-missing sha256sums-prometheus.txt`, idem pour Alertmanager), décompresse, et copie **seulement** `promtool` et `amtool` dans `~/.local/bin/` (qui est dans ton `PATH`). Contrôle : `promtool --version` (3.15.1), `amtool --version` (0.34.1). Si un rôle de `plateforme/ansible` gère déjà les outils d'`adm01` (`outils_k8s`, M14), ajoute-les plutôt à ce rôle, avec leurs empreintes.

Range enfin la configuration d'`amtool` (elle évite de répéter l'adresse d'Alertmanager) :

```
admin@adm01:~$ mkdir -p ~/.config/amtool
admin@adm01:~$ printf 'alertmanager.url: http://alertmanager.apps.par1.medisphere.internal:9093\nauthor: <MOI>\n' > ~/.config/amtool/config.yml
```

---

## Indices, corrigé, vérifications

- Les vérifications se lancent depuis `adm01` : `lab/bin/check 21 <XX>`. Elles sont en lecture seule : objets du cluster par le compte `wb-checks` (étendu en E02 par la ClusterRole agrégée `wb-checks-observabilite`), API de Prometheus, d'Alertmanager et de Grafana (jeton Viewer créé en E05), Mailpit en lecture, GitLab en lecture. Elles restent rejouables plus tard dans le module (après E24, Prometheus est servi par Thanos Query sur la même adresse).
- Les indices sont progressifs : ouvre-les un par un, seulement quand tu bloques.
- Le corrigé (`corrige/`) donne une solution, le *pourquoi*, les alternatives, les pièges et la vision production. Les fichiers complets sont dans `corrige/fichiers/M21-EXX/` : `observabilite/` reproduit l'arborescence de `plateforme/observabilite`, `gitops/` celle de `plateforme/gitops`, `k8s/` celle de `plateforme/k8s`, `ansible/` celle de `plateforme/ansible`, `mediagenda-deploiement/` et `medidoc-deploiement/` celles des dépôts de déploiement, `medisphere/` celle de la documentation.
- Les scripts de panne (`corrige/pannes/`, palier 4) révèlent les causes : ne les lis pas avant d'avoir résolu.

## Ordre conseillé

```
E01 ─ E02 ─ E03 ─ E07 ─ E04 ─ E05 ─ E06 ─ E08 ─ E09
```

1. **E01** — positionnement, à froid.
2. **E02 → E03** — la pile, puis l'exploration de ce qu'elle collecte d'elle-même.
3. **E07 avant E04 et E05** — PromQL et le premier tableau de bord portent sur les métriques de MédiAgenda : il faut d'abord que MédiAgenda soit collecté. Les numéros suivent la logique de la carte (les outils avant l'intégration), l'ordre de travail suit les dépendances.
4. **E06** — Alertmanager ; **E08** a besoin de la ConfigMap `racine-medisphere` qu'E06 crée.
5. **E09** — en dernier : il demande d'avoir pratiqué.

Durée indicative du palier 1 : 16 à 20 heures.

## Pour aller plus loin

- Prometheus, concepts (modèle de données, types de métriques, jobs et instances) : <https://prometheus.io/docs/concepts/data_model/> · PromQL : <https://prometheus.io/docs/prometheus/latest/querying/basics/>
- Bonnes pratiques de nommage et d'instrumentation : <https://prometheus.io/docs/practices/naming/> · histogrammes et résumés : <https://prometheus.io/docs/practices/histograms/>
- prometheus-operator, guide de démarrage et API : <https://prometheus-operator.dev/docs/developer/getting-started/> · <https://prometheus-operator.dev/docs/api-reference/api/>
- kube-prometheus-stack (README et `UPGRADE.md` du chart) : <https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack>
- Alertmanager, configuration : <https://prometheus.io/docs/alerting/latest/configuration/>
- Grafana 13, provisionnement et comptes de service : <https://grafana.com/docs/grafana/latest/administration/>
- *Site Reliability Engineering* (Google), chapitre 6 « Monitoring Distributed Systems » : les quatre signaux dorés.
