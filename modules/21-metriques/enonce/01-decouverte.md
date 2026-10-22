# Module 21 — Palier 1 : Découverte

Avant d'écrire une alerte, il faut des mesures qu'on sait lire. Ce palier déploie la pile de supervision du cluster par Argo CD, apprend à interroger Prometheus (cibles, étiquettes, PromQL), branche Grafana et Alertmanager jusqu'au premier courriel, fait collecter MédiAgenda et MédiDoc par les dépôts des équipes, et passe node_exporter en TLS sur toutes les VMs du socle. Il s'ouvre et se ferme sur un questionnaire.

Prérequis : module 20 terminé (`lab/bin/check 20 46` vert : Argo CD, `plateforme/charts-miroir`, Rollouts) ; module 19 (`mon01`, Mailpit) ; modules 14 à 17 (cluster, réseau, stockage `ceph-rbd`, Helmfile). Lis [`00-introduction.md`](00-introduction.md), en particulier le chemin imposé, les faits techniques, les règles du module et l'**ordre conseillé** (E06 et E07 avant E04 et E05).

---

### M21-E01 — Test de positionnement : supervision  `Q` `★★`

> **Ticket PLAT-2201** — *De : Karim Benali*
> Comme d'habitude : une heure, par écrit, sans moteur de recherche ni IA. Tout le monde « connaît Prometheus » ; je veux savoir si tu sais pourquoi un `rate` sur une jauge est faux, et pourquoi une alerte sur le CPU à 90 % réveille les gens pour rien. Réponds même là où tu hésites.

**Objectifs pédagogiques**
- Évaluer tes acquis sur la mesure (types de métriques, échantillonnage, quantiles) et sur l'alerte (symptôme ou cause, bruit).
- Repérer les notions à travailler et les exercices du module qui les mobilisent.

**Prérequis** : aucun.
**Durée indicative** : 1 h (+ 30 min d'auto-correction).

**Travail demandé**

Réponds aux 18 questions. Pour les QCM, justifie ton choix en une ou deux phrases.

*Collecte*

1. Prometheus va chercher les métriques (*pull*) ; d'autres systèmes les reçoivent (*push* : StatsD, Graphite, OTLP). Donne deux avantages du *pull* pour une équipe d'exploitation, et un cas où le *push* est préférable.

2. *(QCM)* Une cible ne répond plus. Que voit-on dans Prometheus ?
   - A. Rien : la série disparaît simplement
   - B. La série `up` de la cible passe à 0, et les séries de la cible deviennent « périmées » (*stale*) à la collecte suivante
   - C. Les dernières valeurs sont recopiées jusqu'au retour de la cible
   - D. Une alerte part automatiquement

3. Un traitement par lots tourne 40 secondes toutes les heures. Pourquoi Prometheus le voit-il mal, et quelles sont les deux façons habituelles de le superviser ?

*Types de métriques et calculs*

4. Compteur, jauge, histogramme, résumé : donne pour chacun un exemple tiré de MédiAgenda ou de la plateforme, et la fonction PromQL qu'on lui applique d'ordinaire.

5. *(QCM)* `rate(node_memory_MemAvailable_bytes[5m])` :
   - A. donne la vitesse de consommation de la mémoire, c'est la bonne façon de la suivre
   - B. est faux : `rate` suppose un compteur, et interprète chaque baisse comme une remise à zéro
   - C. est équivalent à `deriv(node_memory_MemAvailable_bytes[5m])`
   - D. renvoie toujours 0

6. Quelle est la différence entre `rate(x[5m])` et `irate(x[5m])` ? Lequel mettrais-tu dans une alerte, lequel sur un graphique de diagnostic, et pourquoi ?

7. Un collègue calcule le temps de réponse au 95e centile de MédiAgenda en faisant la **moyenne** des p95 de ses trois pods. Pourquoi est-ce faux ? Comment fait-on avec un histogramme ?

8. Pourquoi `increase(x[1h])` peut-il renvoyer 41,7 pour un compteur de requêtes qui ne compte que des entiers ?

*Étiquettes et cardinalité*

9. Qu'est-ce que la **cardinalité** d'une métrique ? Donne une étiquette qu'il ne faut jamais mettre sur une métrique de MédiAgenda, et explique ce qui se passerait.

10. *(QCM)* Une métrique a les étiquettes `methode` (5 valeurs), `route` (12), `code` (8), et elle est exposée par 6 pods. Combien de séries au plus ?
    - A. 31
    - B. 480
    - C. 2 880
    - D. 6

*Alerter*

11. Alerter sur un **symptôme** ou sur une **cause** : définis les deux, donne un exemple de chaque pour MédiAgenda, et dis lequel doit réveiller quelqu'un la nuit.

12. À quoi sert le `for: 10m` d'une règle d'alerte ? Que se passe-t-il si on l'oublie ? Et s'il vaut 2 heures ?

13. *(QCM)* Trois cents pods tombent en même temps parce qu'un nœud s'arrête. Quelle fonction d'Alertmanager évite trois cents courriels ?
    - A. Les silences
    - B. Le regroupement (*grouping*), éventuellement complété par une inhibition
    - C. Le `repeat_interval`
    - D. Aucune : c'est à Prometheus de n'envoyer qu'une alerte

14. Que doit contenir une notification d'alerte pour être utile à 3 h du matin ?

*Niveaux de service*

15. Définis SLI, SLO et SLA. Lequel est un engagement contractuel ? Lequel l'équipe Plateforme se fixe-t-elle à elle-même ?

16. Un SLO de disponibilité de 99,5 % sur 28 jours : combien de minutes d'indisponibilité cela autorise-t-il ? Que veut dire « budget d'erreur » ?

*Architecture*

17. Pourquoi superviser la supervision ? Que se passe-t-il si Prometheus et Alertmanager tombent en même temps que le cluster qu'ils surveillent ?

18. Prometheus garde 15 jours de données sur un disque local. Claire veut deux ans pour les tendances de capacité. Cite deux approches et leur principal inconvénient.

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 18 questions avant d'ouvrir le corrigé.
- [ ] Tu as noté chaque réponse avec la grille (0, 1 ou 2 points) et calculé ton score sur 36.
- [ ] Tu as noté les thèmes à retravailler et les exercices du module qui les mobilisent.

<details><summary>Indice 1</summary>

Pour les questions de calcul, demande-toi ce que vaut la métrique **entre deux collectes**, et ce que Prometheus sait vraiment : des échantillons, à intervalle régulier, rien entre eux.
</details>

<details><summary>Indice 2</summary>

Pour les questions d'alerte, mets-toi à la place de Nadia : elle est réveillée, elle a deux minutes pour savoir si les patients sont touchés et quoi faire.
</details>

**Pour aller plus loin** (facultatif) : refais ce test à la fin du module (M21-E46), sans relire le corrigé, et compare.

---

### M21-E02 — Déployer kube-prometheus-stack par Argo CD  `LAB` `★★`

> **Ticket PLAT-2202** — *De : Karim Benali* — *Copie : Claire Morel, Sophie Laurent*
> On part de **kube-prometheus-stack** : opérateur, Prometheus, Alertmanager, Grafana, kube-state-metrics, node-exporter, et des règles et tableaux de bord pour Kubernetes tout faits. Mêmes règles que pour Argo Rollouts : chart recopié par le miroir, Application Argo CD dans `plateforme/gitops`, values dans un dépôt à nous. Je veux des **noms courts et stables** (on va les écrire partout pendant des semaines), un stockage persistant, et un Prometheus qui ne prend que ce qu'on lui désigne explicitement. Sophie ajoute deux exigences : les API de Prometheus et d'Alertmanager ne sont joignables que du réseau d'administration et de `mon01` ; et aucun espace de la plateforme ne passe en Pod Security « privileged » sans une exception écrite.

**Objectifs pédagogiques**
- Lire les valeurs d'un gros chart et n'en changer que le nécessaire, en justifiant chaque écart.
- Comprendre comment prometheus-operator sélectionne les objets qu'il traduit en configuration.
- Publier une API sans la Gateway (Service `LoadBalancer` à adresse demandée, `externalTrafficPolicy: Local`) et la filtrer par CiliumNetworkPolicy.
- Déployer sous Argo CD un chart qui livre des CRD et des webhooks d'admission (synchronisation côté serveur, différences ignorées).

**Prérequis** : M20-E46 (Argo CD, `plateforme/charts-miroir`, projet `plateforme`) ; M15 (LB IPAM `lb-par1`, ExternalDNS, Gateway `gw-par1`, cert-manager) ; M16 (`ceph-rbd`) ; M14-E06 (compte `wb-checks`, ClusterRoles agrégées).
**Durée indicative** : 4 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Chart | `kube-prometheus-stack` **92.11.0**, dépôt amont `https://prometheus-community.github.io/helm-charts` ; recopié dans Harbor `charts/` (OCI) par `plateforme/charts-miroir` |
| Application | `kube-prometheus-stack` dans `plateforme/gitops/plateforme/`, projet `plateforme`, destination `supervision` ; release **`kps`** ; values `kps/values.yaml` du nouveau projet **`plateforme/observabilite`** (source `$values`) |
| Noms | tous les objets préfixés `kps` ; CR `Prometheus` et `Alertmanager` nommés **`kps`** (cherche dans les values du chart comment éviter les suffixes `-prometheus`/`-alertmanager` des CR) |
| Sélecteur | étiquette **`medisphere.internal/supervision: "oui"`** pour les `ServiceMonitor`, `PodMonitor`, `PrometheusRule`, `ScrapeConfig`, `Probe`, dans tous les espaces |
| Prometheus | 1 réplica, rétention 15 j, volume `ceph-rbd` de 40 Gio, étiquettes externes `cluster=k8s-par1`, `site=par1`, PriorityClass `medisphere-critique` |
| Alertmanager | 1 réplica, volume `ceph-rbd` de 1 Gio (configuration des routes : E06) |
| Grafana | `grafana.apps.par1.medisphere.internal` par une HTTPRoute sur `gw-par1` (écouteur `https`) ; base SQLite sur un volume `ceph-rbd` de 5 Gio ; mot de passe d'`admin` dans le Secret **`grafana-admin`** (clés `admin-user`, `admin-password`), créé par `outils/secrets-k8s.sh` (composant `grafana`, Vault `critique`) |
| Accès | Services `LoadBalancer` **`prometheus-externe`** (10.10.41.60:9090, `prometheus.apps.par1.medisphere.internal`) et **`alertmanager-externe`** (10.10.41.61:9093, `alertmanager.apps.par1.medisphere.internal`), `externalTrafficPolicy: Local` ; entrée autorisée depuis 10.10.10.0/24 et 10.10.20.19/32 seulement |
| Cibles désactivées | kube-controller-manager, kube-scheduler, etcd, kube-proxy, CoreDNS (M21-E20 activera le plan de contrôle ; kube-proxy n'existe plus depuis M15) |
| Espaces | `supervision` (existant, M15-E26 ; PSA `restricted`) ; **`supervision-noeuds`** (nouveau) |
| Vérifications | ClusterRole agrégée **`wb-checks-observabilite`** (lecture des CRD `monitoring.coreos.com`, `pyrra.dev`, `opentelemetry.io`) dans `plateforme/k8s/rbac/` |

**Travail demandé**

*A. Lire avant d'écrire*

1. Recopie le chart : ajoute `kube-prometheus-stack` 92.11.0 à `charts.yaml` de `plateforme/charts-miroir` (empreinte relevée dans l'index amont **et** recalculée), MR, pipeline. Contrôle : `helm show chart oci://registry.par1.medisphere.internal/charts/kube-prometheus-stack --version 92.11.0` et la signature (`cosign verify`, M20-E13). Quels sous-charts contient l'archive ? Argo CD devra-t-il tirer quelque chose de `ghcr.io` ?
2. Dans `~/m21/e02/`, extrais les values par défaut (`helm show values …`) et lis `UPGRADE.md` du chart pour les majeures 90 à 92. Note dans ton journal : la section qui contrôle la sélection des `ServiceMonitor` (et le rôle des options `…SelectorNilUsesHelmValues`), où se règlent le stockage et la rétention, comment le sous-chart node-exporter accède à l'hôte, comment sont gérés les certificats des webhooks d'admission.
3. Rends le chart avec les values par défaut (`helm template kps … -n supervision`) et compte les objets par type. Lesquels sont sans espace de noms (*cluster-scoped*) ? Que faudra-t-il autoriser dans l'AppProject `plateforme` ?

*B. Les espaces et les droits*

4. Rends le DaemonSet de node-exporter : quels champs sont refusés par le profil de Pod Security `restricted` de l'espace `supervision` ? Décide où le placer pour ne pas abaisser tout l'espace. Écris les fichiers d'espaces dans `plateforme/k8s/espaces/` (l'espace `supervision` y migre depuis `rbac/supervision/`, avec l'étiquette qui permet à `gw-par1` d'accepter la route de Grafana), avec l'exception écrite en annotation. `task espaces`.
5. Ajoute la ClusterRole `wb-checks-observabilite` dans `plateforme/k8s/rbac/` (lecture seule, aucune ressource `secrets`) ; applique-la par la procédure de `plateforme/k8s`.
6. Crée le Secret `grafana-admin` par `outils/secrets-k8s.sh` (nouveau composant `grafana` : fichier `secrets/grafana.yml` du Vault `critique`, et ce qu'il faut dans la table `secrets-k8s.conf` ou dans `secrets-k8s.d/` selon la forme du Secret — M19-E04, M20-E06 ; mot de passe d'au moins 24 caractères). Inscris-le au registre des secrets.

*C. Les values*

7. Crée le projet GitLab `plateforme/observabilite` (branche `main` protégée, fusion par MR) avec un `README.md` et `kps/values.yaml`. Exigences sur les values (chaque écart aux défauts est commenté) :
   - noms courts et stables (contexte technique) ;
   - sélecteurs de Prometheus sur l'étiquette de MédiSphère, pour les cinq types d'objets, dans tous les espaces ; l'étiquette posée sur **tous** les moniteurs et règles livrés par le chart, sous-charts compris (sinon Prometheus ne collecterait même plus le kubelet) ;
   - Prometheus et Alertmanager comme au contexte technique, ressources demandées et limites mémoire fixées ;
   - cibles du plan de contrôle et de kube-proxy désactivées ; systèmes d'exploitation inutiles de node-exporter désactivés ;
   - webhooks d'admission de l'opérateur avec un certificat de **cert-manager** (pas les Jobs `certgen`) ;
   - Grafana : Secret d'admin existant, volume persistant **et** une stratégie de déploiement compatible avec un volume RWO, HTTPRoute, aucun conteneur root (PSA), pas d'appel à grafana.com ;
   - les deux Services `LoadBalancer` d'accès et leurs politiques d'entrée Cilium, déclarés dans les values (le chart permet d'ajouter des manifestes) — les clients **du cluster** (Grafana, Prometheus vers Alertmanager) doivent rester autorisés.
8. Valide hors ligne : `helm template` avec tes values, puis `kubeconform -strict` sur le rendu, et un contrôle de Pod Security (écris une petite requête `yq`/`jq` sur les gabarits de pods rendus : `runAsNonRoot`, `allowPrivilegeEscalation`, `capabilities.drop`, `seccompProfile`, `host*`). Rien ne part en MR avant que les trois passent.

*D. L'Application*

9. Complète l'AppProject `plateforme` (sources, destinations `supervision` et `supervision-noeuds`, liste fermée des types sans espace nécessaires). Écris l'Application `kube-prometheus-stack` à deux sources (chart OCI de Harbor, et `plateforme/observabilite` en `ref: values`). Exigences : synchronisation automatique avec `prune` et `selfHeal` ; aucun espace créé par Argo CD ; ce qu'il faut pour que les **CRD** de l'opérateur s'appliquent ; le champ que cert-manager remplit dans les webhooks ne doit pas rendre l'Application `OutOfSync` en permanence ; une première synchronisation qui survit au webhook pas encore prêt ; et la suppression de l'Application ne doit **jamais** supprimer les CRD en cascade.
   > ⚠️ **Attention** : relis ta MR en pensant au jour où quelqu'un supprimera cette Application par erreur dans l'interface d'Argo CD. Que perdrait-on, dans quels espaces ?
10. MR dans `plateforme/gitops`, fusion, puis suis la synchronisation (`argocd app get kube-prometheus-stack`, `kubectl -n supervision get pods -w`). Lis les événements de la première synchronisation : y a-t-il eu des erreurs transitoires, et pourquoi ont-elles disparu ?

*E. Constater*

11. Depuis `adm01` :
    ```
    admin@adm01:~$ dig +short prometheus.apps.par1.medisphere.internal alertmanager.apps.par1.medisphere.internal
    admin@adm01:~$ curl -s http://prometheus.apps.par1.medisphere.internal:9090/api/v1/status/buildinfo | jq .data.version
    admin@adm01:~$ curl -s http://alertmanager.apps.par1.medisphere.internal:9093/api/v2/status | jq .versionInfo.version
    admin@adm01:~$ curl -s 'http://prometheus.apps.par1.medisphere.internal:9090/api/v1/targets?state=active' \
    >   | jq -r '.data.activeTargets[] | [.labels.job, .health] | @tsv' | sort | uniq -c
    ```
    Toutes les cibles sont-elles `up` ? Depuis un pod de `wb-essais`, essaie la même requête sur 10.10.41.60 : que se passe-t-il, et qui l'a décidé ?
12. Ouvre `https://grafana.apps.par1.medisphere.internal`, connecte-toi en `admin` (mot de passe du Secret), ouvre un tableau de bord livré par le chart (*Kubernetes / Compute Resources / Cluster*). Ne crée encore rien : c'est E05.
13. Documente : une ligne par flux dans `docs/kubernetes/reseau/matrice-flux-cluster.md` (MGMT et `mon01` vers les deux Services ; clients internes) ; le Secret au registre ; l'exception de Pod Security de `supervision-noeuds`.

**Critères de réussite**
- [ ] Le chart 92.11.0 est dans Harbor `charts/`, signé ; l'Application `kube-prometheus-stack` (projet `plateforme`) le tire de là et lit ses values dans `plateforme/observabilite` ; elle est `Synced` et `Healthy`, synchronisée côté serveur, sans création d'espace.
- [ ] Le CR `Prometheus` s'appelle `kps`, sélectionne les cinq types d'objets par `medisphere.internal/supervision: "oui"` dans tous les espaces, garde 15 jours sur un volume `ceph-rbd` ; Alertmanager `kps` a son volume ; opérateur, kube-state-metrics, Grafana et les six node-exporter sont prêts.
- [ ] `supervision` reste en PSA `restricted` ; node-exporter tourne seul dans `supervision-noeuds`, exception écrite.
- [ ] 10.10.41.60:9090 et 10.10.41.61:9093 répondent depuis `adm01`, sont publiés dans le DNS, et ne sont autorisés en entrée que depuis MGMT et `mon01` (et les clients du cluster qui en ont besoin).
- [ ] Les cibles `kubelet` (6), `node-exporter` (6), `apiserver` (3), et les composants de `supervision` sont `up` ; aucune cible en échec ; aucune cible du plan de contrôle désactivé.
- [ ] Grafana répond en HTTPS par `gw-par1` ; la ClusterRole `wb-checks-observabilite` existe.

**Vérification** : `lab/bin/check 21 02`

<details><summary>Indice 1</summary>

Le chart a une option qui supprime les suffixes de noms des objets de l'opérateur ; combinée à `fullnameOverride`, elle donne les noms demandés. Pour la sélection, distingue « sélecteur vide » et « sélecteur absent » : l'opérateur et le chart ne les interprètent pas de la même façon. Les sous-charts ne lisent pas les valeurs de leur parent : leurs moniteurs ont leurs propres clés d'étiquettes (`prometheus.monitor.additionalLabels`, `serviceMonitor.labels`…).
</details>

<details><summary>Indice 2</summary>

Le sous-chart `prometheus-node-exporter` accepte un `namespaceOverride`. Grafana : cherche `initChownData`, `deploymentStrategy` et la section `route` de ses values. Le chart accepte une liste `extraManifests`, passée dans le moteur de gabarits de Helm (pas de `{{` dedans). Pour les politiques Cilium : une source externe arrive avec son adresse d'origine seulement si le Service est en `externalTrafficPolicy: Local` ; une règle `fromCIDR` la désigne.
</details>

<details><summary>Indice 3</summary>

Côté Argo CD : `ServerSideApply=true` (annotations trop longues pour l'application côté client), `ignoreDifferences` avec `jqPathExpressions` sur `.webhooks[]?.clientConfig.caBundle` et `RespectIgnoreDifferences=true`, `retry` dans `syncPolicy`. Le finaliseur `resources-finalizer.argocd.argoproj.io` est ce qui déclenche la suppression en cascade : décide s'il doit être là.
</details>

**Pour aller plus loin** (facultatif) : compare avec l'installation par les manifestes de `kube-prometheus` (jsonnet) : ce que le chart ajoute, ce qu'il cache.

---

### M21-E03 — Explorer Prometheus : cibles, séries et étiquettes  `LAB` `★`

> **Ticket PLAT-2203** — *De : Karim Benali*
> Avant d'écrire la moindre requête, je veux que tu saches lire ce que Prometheus a dans le ventre : qui il collecte, avec quelles étiquettes, d'où elles viennent, combien de séries ça fait. Rends-moi un compte rendu court, avec des chiffres, pas des captures d'écran sans légende. Tes requêtes de travail vont dans le dépôt : elles serviront aux suivants.

**Objectifs pédagogiques**
- Lire les pages *Target health*, *Service discovery*, *Configuration*, *Command-line flags* et *TSDB status* de Prometheus 3.
- Comprendre le passage des étiquettes découvertes (`__meta_*`) aux étiquettes finales.
- Retrouver la configuration générée par l'opérateur.
- Mesurer la cardinalité de ce qui est collecté.

**Prérequis** : M21-E02.
**Durée indicative** : 2 h.

**Contexte technique** : modèle du compte rendu dans [`ressources/E03-exploration/exploration-modele.md`](../ressources/E03-exploration/exploration-modele.md). Format des fichiers de requêtes de `plateforme/observabilite` : `requetes/EXX.promql`, une requête par bloc, blocs séparés par une ligne vide, une ou plusieurs lignes de commentaire `#` au-dessus de chaque requête (la question à laquelle elle répond).

**Travail demandé**

1. Ouvre `http://prometheus.apps.par1.medisphere.internal:9090` depuis ton poste (VPN d'administration ou MGMT). *Status > Runtime & build information* et *Command-line flags* : relève la version, la rétention (en temps et en taille), le chemin de la TSDB. Qui a choisi ces options ?
2. *Status > Target health* : combien de jobs, de cibles, d'échecs ? Pour une cible du job `kubelet`, note l'URL collectée, la durée de la dernière collecte et les étiquettes finales.
3. *Status > Service discovery* : pour la même cible, compare les étiquettes **découvertes** et les étiquettes **finales**. Combien de cibles ont été découvertes puis écartées par ce job ? Pourquoi celles-là ?
4. Retrouve la configuration générée : *Status > Configuration*, puis l'objet Kubernetes où l'opérateur la range (`kubectl -n supervision get secrets` : lequel, et sous quelle forme est-elle stockée ?). Lis-la avec ton identité d'administrateur, **sans** l'écrire sur disque. Repère le job produit par le ServiceMonitor `kps-kubelet` et explique trois de ses règles de relabeling.
5. Avec l'API :
   ```
   admin@adm01:~$ P=http://prometheus.apps.par1.medisphere.internal:9090/api/v1
   admin@adm01:~$ curl -s "$P/status/tsdb" | jq '.data.headStats, .data.seriesCountByMetricName[:5]'
   admin@adm01:~$ curl -s "$P/label/__name__/values" | jq '.data | length'
   admin@adm01:~$ curl -s "$P/targets/metadata?match_target=%7Bjob%3D%22kubelet%22%7D&metric=kubelet_running_pods" | jq '.data[0]'
   admin@adm01:~$ promtool query instant http://prometheus.apps.par1.medisphere.internal:9090 'count by (job) (up)'
   ```
   Que représentent les séries de « tête » (*head*) ? Quelles sont les cinq métriques qui ont le plus de séries, et pourquoi celles-là ?
6. Écris `requetes/E03.promql` dans `plateforme/observabilite` : au moins **six** requêtes qui répondent, dans l'ordre, à ces questions : cibles par job ; cibles qui répondent par job ; les cinq collectes les plus lentes ; échantillons gardés par collecte, par job ; séries actives de la tête ; les dix noms de métriques qui ont le plus de séries. Chaque requête doit renvoyer des données. Vérifie la syntaxe avant la MR (`promtool --experimental promql format '<requête>'`).
7. Rédige `docs/observabilite/metriques/exploration.md` dans `plateforme/medisphere` à partir du modèle, avec tes chiffres, et pousse-le par MR.

**Critères de réussite**
- [ ] `docs/observabilite/metriques/exploration.md` est sur `main` de `plateforme/medisphere` : cibles, étiquettes avant et après relabeling (`__meta_kubernetes_*`, `__address__`), emplacement de la configuration générée, chiffres de la TSDB.
- [ ] `requetes/E03.promql` est sur `main` de `plateforme/observabilite`, contient au moins six requêtes, et chacune s'évalue sans erreur et renvoie des données.

**Vérification** : `lab/bin/check 21 03`

<details><summary>Indice 1</summary>

Une cible « écartée » (*dropped*) a été découverte (un point de terminaison d'un Service, par exemple) mais une règle `keep` ou `drop` du relabeling l'a éliminée : le ServiceMonitor ne désigne qu'un **port**, les autres ports du même Service sont des cibles découvertes puis écartées.
</details>

<details><summary>Indice 2</summary>

L'opérateur stocke la configuration compressée (gzip) dans un Secret dont le nom reprend celui du CR. `kubectl get secret … -o jsonpath='{.data.…}' | base64 -d | gunzip | less`. Pour la cardinalité, `count by (__name__) ({__name__=~".+"})` coûte cher sur un gros Prometheus : en production on lit plutôt la page *TSDB status*.
</details>

**Pour aller plus loin** (facultatif) : `promtool check service-discovery` rejoue la découverte et le relabeling d'un job à partir d'un fichier de configuration : essaie-le sur la configuration générée (tu verras ce qui lui manque pour tourner hors du cluster).

---

### M21-E04 — PromQL : sélecteurs, taux et agrégations  `LAB` `★★`

> **Ticket DEV-2204** — *De : Julien Petit* — *Copie : Nadia Roussel*
> Maintenant que vous collectez MédiAgenda, j'ai des questions simples auxquelles personne ne sait répondre : combien de requêtes par seconde en recette, combien d'erreurs, quel temps de réponse pour 95 % des utilisateurs, est-ce que le cache des créneaux sert à quelque chose, et quel nœud porte le plus de trafic. Une requête par question, commentée, dans votre dépôt : je veux pouvoir les relire et les réutiliser.

**Objectifs pédagogiques**
- Écrire des sélecteurs justes (égalité, expressions régulières, exclusions).
- Appliquer `rate` et `increase` aux compteurs, `histogram_quantile` aux histogrammes, et agréger avec `by`/`without`.
- Gérer l'absence de séries (`absent`, `or`), décaler dans le temps (`offset`), utiliser une sous-requête.
- Joindre deux métriques (`on`, `group_left`) pour enrichir un résultat.

**Prérequis** : M21-E07 (MédiAgenda collecté : job `mediagenda`) ; M21-E03.
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Métriques de MédiAgenda | `mediagenda_http_requests_total{methode, route, code}` (compteur), `mediagenda_http_request_duration_seconds` (histogramme, bornes par défaut du client Python : 5 ms à 10 s), `mediagenda_cache_total{resultat}` (`hit`, `miss`, `erreur`), plus `process_*` et `python_*` ; étiquettes ajoutées par la collecte : `job="mediagenda"`, `namespace`, `pod`, `instance`, `service`, `endpoint` |
| Trafic | [`ressources/E04-trafic/trafic-mediagenda.sh`](../ressources/E04-trafic/trafic-mediagenda.sh) : lectures (créneaux, rendez-vous), quelques 404 et 422, vers la **recette** seulement ; à lancer depuis `adm01` au moins 15 minutes avant de répondre |
| Livrable | `requetes/E04.promql` de `plateforme/observabilite`, format de E03 |

**Travail demandé**

1. Lance le trafic : `ressources/E04-trafic/trafic-mediagenda.sh` (lis-le d'abord : que fait-il, que ne fait-il pas ?). Pendant qu'il tourne, ouvre `/metrics` d'un pod de l'API (`kubectl -n mediagenda-recette port-forward …`) et repère les trois métriques ci-dessus : type, aide, étiquettes, compartiments de l'histogramme.
2. Dans l'onglet *Query* de Prometheus (vue *Graph* et *Table*), puis avec `promtool query instant`, écris une requête pour chacune des questions suivantes. Range-les dans `requetes/E04.promql`, dans l'ordre, chacune sous son commentaire.
   1. Débit total de MédiAgenda en recette, en requêtes par seconde, sur une fenêtre de 5 minutes.
   2. Le même débit, par route et par code de réponse.
   3. Part des réponses 5xx, par environnement — elle doit valoir 0 (et non « pas de données ») quand il n'y a aucune erreur.
   4. Nombre de requêtes de la dernière heure en recette, par code. Pourquoi le résultat n'est-il pas entier ?
   5. Latence au 95e centile, par route, en recette.
   6. Latence moyenne en recette.
   7. Part des requêtes servies en moins de 250 ms en recette.
   8. Taux de succès du cache des créneaux, par environnement.
   9. Les trois couples (environnement, route) les plus sollicités.
   10. Nombre de pods de l'API collectés et joignables, par environnement.
   11. Une requête qui vaut 1 tant qu'**aucune** cible MédiNotif n'est collectée.
   12. Évolution du CPU consommé par chaque pod de l'API : maintenant, moins il y a 10 minutes.
   13. Le pic du débit total sur la dernière heure, mesuré minute par minute.
   14. La mémoire de travail de chaque pod de l'API, avec le nom du nœud qui le porte (pris dans `kube_pod_info`).
   15. Le débit de MédiAgenda par nœud du cluster.
3. Pour la question 5, essaie aussi la version **fausse** qui agrège sans garder `le`, puis celle qui calcule le quantile par pod avant de faire la moyenne. Note les écarts dans ton journal et explique-les.
4. Pour les questions 14 et 15, essaie sans `group_left` (en gardant `on (namespace, pod)`) : que devient l'étiquette `node` dans le résultat de la 14 ? Quel message d'erreur obtiens-tu pour la 15, et pourquoi ?
5. Vérifie la syntaxe de tout le fichier (`promtool --experimental promql format`), MR, fusion.

**Critères de réussite**
- [ ] `requetes/E04.promql` est sur `main` de `plateforme/observabilite`, avec au moins 15 requêtes commentées ; chacune s'évalue sans erreur et renvoie des données.
- [ ] Le fichier contient au moins un `histogram_quantile` sur une agrégation qui garde `le`, une jointure `group_left` avec `kube_pod_info`, un `offset`, une sous-requête, un `absent`, un `increase`.
- [ ] Ton journal explique les écarts entre les trois calculs de la question 5, et ce que change `group_left` pour les questions 14 et 15.

**Vérification** : `lab/bin/check 21 04`

<details><summary>Indice 1</summary>

Une opération entre deux vecteurs n'apparie que les séries qui ont **exactement** les mêmes étiquettes. Un vecteur vide divisé par quelque chose reste vide : `or` permet de fournir une valeur de repli, à condition qu'elle ait les mêmes étiquettes que ce qu'elle remplace.
</details>

<details><summary>Indice 2</summary>

`histogram_quantile` attend des séries qui ont une étiquette `le` ; tout ce que tu gardes en plus dans le `by` donne un quantile par valeur de cette étiquette. Une sous-requête s'écrit `<expression>[<fenêtre>:<pas>]` et s'utilise avec une fonction `…_over_time`.
</details>

<details><summary>Indice 3</summary>

`kube_pod_info` vaut toujours 1 et porte l'étiquette `node` : multiplier par lui ne change pas la valeur. Une correspondance un-à-un ne garde que les étiquettes du côté gauche : pour **recopier** `node`, il faut `group_left(<étiquettes à recopier>)` et un `on(namespace, pod)`. Et « plusieurs séries d'un côté pour une de l'autre » (une série par route et par code pour un seul pod) exige `group_left`, sinon Prometheus refuse l'opération.
</details>

**Pour aller plus loin** (facultatif) : réécris la question 5 avec la vue *Explain* de l'interface de Prometheus 3, et lis la page « Histograms and summaries » de la documentation : quand un résumé (*summary*) serait-il acceptable ?

---

### M21-E05 — Grafana : sources de données, exploration, premier tableau de bord  `LAB` `★★`

> **Ticket DEV-2205** — *De : Nadia Roussel* — *Copie : Julien Petit*
> Les requêtes de Julien, c'est bien ; à 3 h du matin, je veux un écran. Un tableau « MédiAgenda — aperçu » que je choisis par environnement : pods qui répondent, erreurs, temps de réponse, débit, cache, CPU et mémoire. Et que plus personne n'utilise le compte `admin` de Grafana au quotidien.

**Objectifs pédagogiques**
- Comprendre ce que Grafana stocke (tableaux, comptes, préférences) et ce qu'il ne stocke pas (les métriques).
- Explorer des métriques avec *Explore* et construire des panneaux (série temporelle, statistique) avec unités et légendes.
- Utiliser des variables de tableau de bord (source de données, environnement).
- Créer des comptes nominatifs et un compte de service à droits minimaux.

**Prérequis** : M21-E07 (MédiAgenda collecté), M21-E04 (requêtes de MédiAgenda), M21-E02.
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Source de données | `Prometheus` (UID `prometheus`), provisionnée par le chart (non modifiable dans l'interface) ; `Alertmanager` (UID `alertmanager`) |
| Comptes | `admin` (bris de glace, mot de passe du Secret `grafana-admin`) ; **`<MOI>`** (Admin de l'organisation) ; les comptes locaux des personnages (Karim, Nadia, Claire, Julien) sont créés au début d'E17, les équipes et les droits par OpenTofu en E17 |
| Compte de service | **`wb-checks`**, rôle **Viewer**, jeton à durée limitée → `~/.config/workbook/grafana-checks.token` (600) |
| Tableau | **« MédiAgenda — aperçu »**, dans un dossier **« MédiAgenda »** (créé à la main pour l'instant : E17 passera tout *as code*) |
| Version | Grafana 13.2 : schéma de tableau de bord v2 actif par défaut ; `grafana-cli` n'existe plus |

**Travail demandé**

1. Connecte-toi en `admin`. Crée ton compte `<MOI>` (rôle Admin de l'organisation, mot de passe fort, rangé dans ton gestionnaire de mots de passe), déconnecte-toi, reconnecte-toi avec lui. Range ses identifiants dans `~/.config/workbook/grafana-admin.env` (600 : `GRAFANA_USER=…`, `GRAFANA_PASSWORD=…`) pour les scripts d'administration. Pourquoi ne pas garder `admin` ?
2. *Connections > Data sources* : ouvre `Prometheus`. Pourquoi ne peux-tu pas la modifier ? D'où vient-elle (cherche le ConfigMap qui la déclare et le conteneur qui le lit) ? Lance le test de connexion.
3. *Explore* : reprends trois requêtes de E04 ; compare le mode *Code* et le *Builder* ; affiche la question 2 en mode « séries » puis « tableau ». Qu'est-ce que `$__rate_interval`, et pourquoi le préférer à `[5m]` dans un panneau ?
4. Crée le dossier « MédiAgenda » puis le tableau « MédiAgenda — aperçu » :
   - deux variables : `datasource` (type source de données, Prometheus) et `environnement` (valeurs des espaces où le job `mediagenda` est collecté) ;
   - en tête, des statistiques : pods qui répondent, part des 5xx, latence p95, succès du cache ;
   - puis des séries temporelles : débit par code (sans les sondes `/sante`, `/pret`, `/metrics`), latences p50 et p95 par route, CPU et mémoire par pod ;
   - chaque panneau a une unité (requêtes/s, secondes, pourcentage, octets), un titre qui dit ce qu'on regarde, et toutes les requêtes suivent la variable d'environnement ;
   - rafraîchissement 30 s, dernière heure par défaut.
5. Change d'environnement : les panneaux suivent-ils ? Coupe le trafic d'essai : que deviennent la part de 5xx et la latence quand il n'y a plus de requêtes ? Corrige ce qui affiche une valeur trompeuse (ou écris pourquoi « pas de données » est la bonne réponse).
6. Exporte le tableau (*Export > Export as JSON*) dans `~/m21/e05/` et lis-le : quelle version de schéma ? Les requêtes référencent-elles la source par son UID ou par la variable ? Garde ce fichier : E17 le reprendra.
7. Crée le compte de service `wb-checks` (rôle Viewer) et un jeton de 90 jours, écrit dans `~/.config/workbook/grafana-checks.token` (600) sans passer par l'historique du shell ni par l'écran si tu le scriptes. Vérifie qu'il peut chercher des tableaux et qu'il ne peut **pas** lister les sources de données.
8. Note dans `docs/observabilite/metriques/acces.md` (`plateforme/medisphere`) : les adresses de Prometheus, Alertmanager et Grafana, qui peut y accéder et comment, l'usage du compte `admin` (bris de glace seulement), le compte de service et sa rotation.

**Critères de réussite**
- [ ] Le tableau « MédiAgenda — aperçu » est dans le dossier « MédiAgenda », avec au moins quatre panneaux (dont un débit en `rate(mediagenda_http_requests_total…)` et une latence par `histogram_quantile` sur l'histogramme de MédiAgenda) et une variable `environnement` suivie par les requêtes.
- [ ] La source de données Prometheus est saine.
- [ ] `~/.config/workbook/grafana-checks.token` (600) est le jeton d'un compte de service Viewer : il cherche des tableaux, il ne liste pas les sources de données.
- [ ] Ton compte nominatif existe ; `acces.md` est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 21 05`

<details><summary>Indice 1</summary>

Une variable de type *Query* sur la source Prometheus peut lister les valeurs d'une étiquette pour un sélecteur donné (`label_values(<sélecteur>, <étiquette>)`). Dans les requêtes, `$environnement` est remplacé par sa valeur avant l'envoi à Prometheus.
</details>

<details><summary>Indice 2</summary>

Les comptes de service et leurs jetons se gèrent dans *Administration > Users and access > Service accounts*, ou par l'API HTTP (`/api/serviceaccounts`, puis `/api/serviceaccounts/<id>/tokens`) avec une authentification d'administrateur passée par un fichier de configuration de `curl` (`-K`), jamais en argument. La réponse de création du jeton contient la clé **une seule fois**.
</details>

**Pour aller plus loin** (facultatif) : ouvre le même tableau dans la vue « schéma v2 » (*Edit > Settings > JSON Model*) et compare la structure à celle de l'export classique.

---

### M21-E06 — Alertmanager : routes, regroupement et courriels  `LAB` `★★`

> **Ticket PLAT-2206** — *De : Nadia Roussel* — *Copie : Karim Benali*
> Prometheus sait déjà qu'il y a des problèmes (le chart a amené ses règles) ; personne ne le sait. Je veux recevoir les courriels : l'astreinte pour ce qui est critique, l'équipe Plateforme pour le reste, rien du tout pour le chien de garde qui sonne en permanence. Pas trente courriels pour un incident : regroupés. Et je veux une preuve, avec une alerte d'essai, que la chaîne fonctionne jusqu'à la boîte de réception.

**Objectifs pédagogiques**
- Écrire une configuration d'Alertmanager : SMTP, récepteurs, arbre de routage, regroupement, inhibitions, gabarits.
- Comprendre `group_by`, `group_wait`, `group_interval`, `repeat_interval` et leur effet sur le nombre de notifications.
- Tester une configuration hors ligne (`amtool check-config`, `amtool config routes test`) puis en vrai (`amtool alert add`).

**Prérequis** : M21-E02 ; M19-E03 (Mailpit sur `mon01`, `smtp.par1.medisphere.internal:25`, STARTTLS, compte de lecture des checks).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Où | clé `alertmanager.config` de `kps/values.yaml` (le chart la rend dans le Secret `alertmanager-kps`) ; gabarits dans `alertmanager.templateFiles` |
| SMTP | `smtp.par1.medisphere.internal:25`, STARTTLS **exigé**, certificat vérifié contre la racine MédiSphère ; expéditeur `alertmanager-k8s@medisphere.internal` ; Mailpit n'exige pas d'authentification SMTP dans le lab (comme pour GitLab, M19-E03) |
| Racine | ConfigMap **`racine-medisphere`** (clé `ca.crt`) dans `supervision`, déclarée dans les values, montée dans Alertmanager (elle servira aussi à Prometheus en E08) |
| Récepteurs | `plateforme-mail` → `plateforme@medisphere.internal` (par défaut) ; `astreinte-mail` → `astreinte@` ; `mediagenda-mail` → `mediagenda@` ; `medidoc-mail` → `medidoc@` (déclarés maintenant, routés en E16) ; un récepteur sans notification pour `Watchdog` et `InfoInhibitor` |
| Étiquettes | nos alertes porteront `gravite` (`critique`, `avertissement`, `info`) et `equipe` ; celles du chart portent `severity` (`critical`, `warning`, `info`) jusqu'à E15 |
| Essais | alertes nommées `EssaiPLAT2206` (avertissement, équipe plateforme) et `EssaiCritiquePLAT2206` (critique) |

**Travail demandé**

1. Lis la configuration chargée aujourd'hui : `amtool config show` (et l'interface, page *Status*). Quel récepteur reçoit tout ? Combien d'alertes sont actives (`amtool alert query`) ? Pourquoi `Watchdog` est-elle toujours là ?
2. Ajoute la ConfigMap `racine-medisphere` aux values et monte-la dans Alertmanager (`alertmanagerSpec`). Où apparaît-elle dans le pod ?
3. Écris la configuration :
   - `global` : SMTP du contexte, STARTTLS exigé, CA de la racine montée, nom annoncé au serveur ;
   - route racine : récepteur par défaut `plateforme-mail`, regroupement par nom d'alerte et par espace, `group_wait` court, `group_interval` de quelques minutes, `repeat_interval` de quelques heures (justifie chaque valeur dans un commentaire) ;
   - sous-routes : `Watchdog` et `InfoInhibitor` vers le récepteur muet ; critiques (`gravite="critique"` **ou** `severity="critical"`) vers `astreinte-mail` ;
   - inhibitions : une alerte critique fait taire les avertissements et infos de même nom dans le même espace, pour nos deux conventions d'étiquettes ;
   - les quatre récepteurs de courriel, avec `send_resolved`, et un **sujet en français** produit par un gabarit (`templateFiles`) qui montre l'état, le nombre d'alertes, le nom, la gravité et l'espace.
4. Avant la MR, hors ligne :
   ```
   admin@adm01:~/src/observabilite$ yq '.alertmanager.config' kps/values.yaml > ~/m21/e06/am.yml
   admin@adm01:~/src/observabilite$ yq '.alertmanager.templateFiles["medisphere.tmpl"]' kps/values.yaml > ~/m21/e06/medisphere.tmpl
   admin@adm01:~/m21/e06$ amtool check-config am.yml
   admin@adm01:~/m21/e06$ amtool config routes test --config.file=am.yml alertname=Watchdog severity=none
   admin@adm01:~/m21/e06$ amtool config routes --config.file=am.yml
   ```
   (Adapte le chemin des gabarits dans la copie locale.) Teste au moins quatre jeux d'étiquettes et garde-les : ils deviendront les tests de routage de la CI en E07.
5. MR, fusion, synchronisation. Vérifie que la nouvelle configuration est **chargée** (`amtool config show`, et la métrique `alertmanager_config_last_reload_successful`). Si elle ne l'est pas : où lis-tu l'erreur ?
6. Envoie l'alerte d'essai, avec une fin dans 5 minutes :
   ```
   admin@adm01:~$ amtool alert add alertname=EssaiPLAT2206 gravite=avertissement equipe=plateforme namespace=wb-essais \
   >   --annotation=resume="Alerte d'essai du ticket PLAT-2206" --end="$(date -u -d '+5 min' +%Y-%m-%dT%H:%M:%SZ)"
   ```
   Observe dans l'interface d'Alertmanager le groupe créé, puis dans Mailpit (`https://mon01.par1.medisphere.internal:8025`) le courriel de déclenchement, puis celui de résolution. Mesure les délais : lesquels des paramètres de la route les expliquent ?
7. Envoie `EssaiCritiquePLAT2206` (`gravite=critique`) : à qui arrive-t-il ? Envoie ensuite, dans la minute, trois alertes `EssaiPLAT2206` qui ne diffèrent que par une étiquette `pod` : combien de courriels, et pourquoi ?
8. Note dans ton journal le parcours complet d'une alerte (règle → Prometheus → Alertmanager → route → récepteur → SMTP → boîte) et l'endroit où regarder quand le courriel n'arrive pas, étape par étape.

**Critères de réussite**
- [ ] La configuration chargée par Alertmanager envoie par `smtp.par1.medisphere.internal:25` en STARTTLS exigé, avec vérification par un fichier de CA ; elle déclare les quatre récepteurs ; la route par défaut va à `plateforme-mail`, regroupe par `alertname` et `namespace`, avec `group_wait` ≤ 1 min, `group_interval` ≥ 1 min, `repeat_interval` ≥ 1 h.
- [ ] `Watchdog` ne part jamais par courriel ; les alertes critiques vont à `astreinte-mail`.
- [ ] La ConfigMap `racine-medisphere` existe dans `supervision` et est montée dans Alertmanager.
- [ ] Mailpit a reçu, pour `EssaiPLAT2206`, un courriel de déclenchement et un de résolution adressés à `plateforme@` ; et pour `EssaiCritiquePLAT2206`, un courriel adressé à `astreinte@`.

**Vérification** : `lab/bin/check 21 06`

<details><summary>Indice 1</summary>

Les options SMTP globales ont toutes le préfixe `smtp_` ; la vérification du certificat du serveur SMTP se règle dans un bloc de configuration TLS global (cherche-le dans la page *Configuration* de la documentation d'Alertmanager 0.34). Les fichiers d'une ConfigMap déclarée dans `alertmanagerSpec.configMaps` sont montés sous `/etc/alertmanager/configmaps/<nom>/`.
</details>

<details><summary>Indice 2</summary>

Les gabarits sont montés à côté de la configuration et chargés par la liste `templates` ; dans les values, ils ne passent pas par le moteur de Helm (le chart les encode tels quels). Un en-tête de courriel se fixe par `headers` dans `email_configs`, et peut appeler un gabarit (`{{ template "nom" . }}`).
</details>

<details><summary>Indice 3</summary>

Trois alertes du même nom dans le même espace forment **un** groupe si `pod` n'est pas dans `group_by` : une seule notification, qui les liste. Le premier envoi attend `group_wait` ; un changement du groupe attend `group_interval` ; un groupe inchangé n'est renvoyé qu'après `repeat_interval`.
</details>

**Pour aller plus loin** (facultatif) : colle ta configuration dans l'éditeur d'arbre de routage de la documentation de Prometheus (*Routing tree editor*) et vérifie visuellement où vont tes alertes d'essai.

---

### M21-E07 — Les métriques de MédiAgenda : ServiceMonitor et PodMonitor  `LAB` `★★`

> **Ticket DEV-2207** — *De : Julien Petit* — *Copie : Karim Benali*
> MédiAgenda expose `/metrics` depuis le premier jour ; personne ne le lit. Je veux que la collecte soit déclarée **dans notre dépôt** `mediagenda/deploiement`, pour nos trois environnements, et que ça marche aussi pendant un canary (c'est là qu'on en a le plus besoin). Même chose pour MédiDoc. Et la base CloudNativePG expose des métriques aussi : je les veux. De votre côté, structurez `plateforme/observabilite` pour que les règles et les cibles hors cluster aient leur place, avec une CI qui vérifie avant que ça parte.

**Objectifs pédagogiques**
- Écrire un `ServiceMonitor` et un `PodMonitor` et comprendre ce que l'opérateur en fait (rôle de découverte, étiquettes ajoutées, nom du job).
- Livrer la supervision d'une application avec l'application (component kustomize), dans le dépôt de l'équipe.
- Gérer les cas où un Service ne désigne pas tous les pods à collecter (Argo Rollouts).
- Ouvrir le flux de collecte dans des espaces en refus par défaut.
- Structurer un dépôt de configuration de supervision et sa CI.

**Prérequis** : M21-E02, M21-E06 (configuration d'Alertmanager et essais de routage) ; M20-E16 (Rollout de MédiAgenda en recette et prod, Services `mediagenda` et `mediagenda-canary`) ; M17 (`mediagenda/deploiement`, components) ; M15-E17, M15-E28 (refus par défaut, cloisons entre espaces d'équipe).
**Durée indicative** : 4 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| MédiAgenda | conteneur `api`, port nommé `http` (8000), `/metrics` ; étiquettes des pods du chart : `app.kubernetes.io/name: mediagenda`, `app.kubernetes.io/instance: mediagenda`, `app.kubernetes.io/component: api` ; espaces `mediagenda-dev`, `mediagenda-recette`, `mediagenda-prod` |
| Base | Cluster CloudNativePG `mediagenda-db` : chaque instance expose ses métriques sur le port nommé `metrics` (9187) |
| MédiDoc | `/metrics` sur 8080 ; `medidoc-dev` et `medidoc-recette` (M20-E33 ; la recette portera le SLO de MédiDoc au palier 3) |
| Noms | ServiceMonitor **`mediagenda`** (job **`mediagenda`**), PodMonitor **`mediagenda-db`** (job `mediagenda-db`), ServiceMonitor **`medidoc`** (job **`medidoc`**) ; component **`components/supervision`** dans chaque dépôt `…/deploiement` |
| Réseau | les espaces d'équipe sont en refus par défaut : la collecte (Prometheus de `supervision` vers 8000, 8080, 9187) est autorisée par la **plateforme**, dans `plateforme/k8s` |
| `plateforme/observabilite` | arborescence : `kps/`, `regles/`, `scrape/`, `alertmanager/`, `tableaux/`, `requetes/`, `tests/`, `outils/` ; une `kustomization.yaml` à la racine ; Application Argo CD **`observabilite`** (projet `plateforme`, destination `supervision`) |

**Travail demandé**

*A. Comprendre le piège du canary*

1. En recette, compare les sélecteurs des Services `mediagenda` et `mediagenda-canary` (`kubectl -n mediagenda-recette get svc -o wide`) hors canary, puis pendant un canary en pause si tu peux en lancer un (M20-E16). Un ServiceMonitor qui collecterait le Service `mediagenda` verrait-il les pods canary ? Et s'il collectait les deux Services ? Écris ta conclusion et la solution retenue dans ton journal **avant** d'écrire du YAML.

*B. Le dépôt des équipes*

2. Dans `mediagenda/deploiement`, crée le component `components/supervision` : de quoi collecter **tous** les pods de l'API (stables et canary, une seule fois chacun), le ServiceMonitor `mediagenda` (port nommé, intervalle 30 s, nom de job `mediagenda`, une étiquette de série qui porte la révision du pod d'après Argo Rollouts, pour comparer canary et stable en M21-E18) et le PodMonitor `mediagenda-db` des instances CNPG. Inclus-le dans les trois overlays (où, par rapport au component `livraison` ?). `kustomize build` des trois overlays, MR relue par Julien, synchronisation (prod : à la main, M20).
3. Même chose pour `medidoc/deploiement` (ServiceMonitor `medidoc`). Vérifie d'abord les étiquettes réelles des pods de MédiDoc.
4. Les cibles apparaissent-elles dans Prometheus ? Si elles sont absentes ou en échec, diagnostique dans l'ordre : l'objet est-il sélectionné (étiquette) ? la configuration générée contient-elle le job ? la découverte trouve-t-elle des points de terminaison ? la connexion aboutit-elle (Hubble : `hubble observe --namespace mediagenda-recette --verdict DROPPED`) ?

*C. Le flux*

5. Dans `plateforme/k8s/composants/reseau/politiques/`, écris **une** politique Cilium qui autorise Prometheus (`supervision`) à joindre les ports de collecte de **tous** les espaces d'équipe (étiquette d'espace `medisphere.internal/equipe`), sans faire passer aucun pod en refus par défaut s'il ne l'était pas. Pourquoi la plateforme et pas les équipes ? Applique, reporte dans `docs/kubernetes/reseau/matrice-flux-cluster.md`.

*D. `plateforme/observabilite`*

6. Structure le dépôt : `kustomization.yaml` racine (espace `supervision`, étiquette de sélection posée sur tout ce qu'elle produit, ressources `regles/` et `scrape/` vides pour l'instant), `README.md` qui dit ce qui va où, les dossiers du contexte technique.
7. Écris la CI (`.gitlab-ci.yml`) : composant `qualite` de `plateforme/ci-templates` ; syntaxe de toutes les requêtes `requetes/*.promql` (un script `outils/verifier-promql.sh` en POSIX `sh`, qui tourne dans l'image `prometheus`) ; configuration d'Alertmanager **extraite** des values, vérifiée par `amtool check-config`, et rejouée contre tes essais de routage d'E06 (`alertmanager/routes-tests.txt`, `outils/tester-routes.sh`). Images épinglées, tirées par les caches de Harbor.
8. Écris l'Application `observabilite` dans `plateforme/gitops` (kustomize, racine du dépôt). Pourquoi une Application distincte de `kube-prometheus-stack`, et pourquoi ici un finaliseur de suppression alors qu'E02 l'a refusé ?
9. Casse volontairement une route dans une branche (récepteur inexistant) : la CI doit échouer ; ne fusionne pas.

**Critères de réussite**
- [ ] `components/supervision` est sur `main` de `mediagenda/deploiement` et de `medidoc/deploiement`, inclus dans les overlays ; les ServiceMonitor `mediagenda` portent l'étiquette de sélection et un port nommé dans les trois environnements.
- [ ] Dans chaque environnement de MédiAgenda, il y a autant de cibles `up{job="mediagenda"}` que de pods prêts de l'API, et une seule série `up` par pod ; aucune cible `mediagenda` ou `medidoc` en échec ; `mediagenda_http_requests_total` existe dans les trois environnements ; `medidoc-dev` et `medidoc-recette` sont collectés.
- [ ] Le PodMonitor `mediagenda-db` existe en recette et les instances PostgreSQL sont collectées (`cnpg_collector_up`).
- [ ] Une politique Cilium à l'échelle du cluster autorise la collecte depuis `supervision`.
- [ ] `plateforme/observabilite` a sa structure, sa CI (dernier pipeline de `main` réussi) ; l'Application `observabilite` est `Synced` et `Healthy`.

**Vérification** : `lab/bin/check 21 07`

<details><summary>Indice 1</summary>

Un ServiceMonitor ne collecte pas « un Service » : il collecte les **points de terminaison** des Services qu'il sélectionne. Un Service sans adresse (*headless*) dédié à la collecte, qui sélectionne les pods par les étiquettes du chart (sans l'empreinte de révision qu'Argo Rollouts ajoute aux sélecteurs de `mediagenda` et `mediagenda-canary`), désigne chaque pod une fois. `spec.jobLabel` nomme le job d'après une étiquette du Service.
</details>

<details><summary>Indice 2</summary>

Les étiquettes des pods découverts sont disponibles au relabeling sous `__meta_kubernetes_pod_label_<nom>` (caractères non alphanumériques remplacés par `_`). Pour les instances CNPG, regarde les étiquettes `cnpg.io/…` des pods ; l'option `enablePodMonitor` du Cluster est dépréciée par CNPG.
</details>

<details><summary>Indice 3</summary>

Une `CiliumClusterwideNetworkPolicy` peut sélectionner les pods par une étiquette de leur espace (`io.cilium.k8s.namespace.labels.<clé>`). Une politique qui sélectionne un pod en entrée le fait passer en refus par défaut pour tout le reste, sauf si elle le dit autrement (`enableDefaultDeny`, comme les cloisons de M15-E28).
</details>

**Pour aller plus loin** (facultatif) : la fonction `scrapeClass` de prometheus-operator permet d'imposer des réglages à tous les moniteurs (TLS, relabeling communs) : lis sa documentation et dis si elle aurait simplifié ce que tu viens de faire.

---

### M21-E08 — Superviser les VMs : node_exporter partout  `LAB` `★★`

> **Ticket PLAT-2208** — *De : Karim Benali* — *Copie : Sophie Laurent*
> Le rôle `node_exporter` du module 04 a fait son temps : paquet Debian en 1.9, HTTP en clair. On passe au binaire amont 1.12, vérifié par son empreinte, sous un utilisateur dédié, dans une unité durcie, et **en TLS** avec un certificat de notre PKI — Sophie ne veut plus de métriques en clair sur le réseau. Toutes les VMs du socle, sans exception. Et la liste des cibles ne s'écrit pas à la main : elle se tire de NetBox, et elle passe en MR comme le reste.

**Objectifs pédagogiques**
- Faire évoluer un rôle Ansible existant (installation amont épinglée, bascule depuis un paquet, TLS, durcissement systemd) sans coupure longue.
- Réutiliser le rôle `certificats_acme` du M06 depuis un autre rôle.
- Générer une configuration de collecte depuis la source de vérité (NetBox) et la livrer par MR.
- Ouvrir un flux de collecte de bout en bout : bordure, pare-feu local, vérification TLS côté Prometheus.

**Prérequis** : M21-E06 (ConfigMap `racine-medisphere`), M21-E07 (`plateforme/observabilite` et sa CI) ; M04-E34 (rôle `node_exporter` v1) ; M06-E18/E27 (rôle `certificats_acme`), M06-E30 (rôle `pare_feu_local`) ; M07 (matrice commune des passerelles).
**Durée indicative** : 4 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| node_exporter | **1.12.1**, `node_exporter-1.12.1.linux-amd64.tar.gz` de la publication GitHub du projet ; empreinte dans `sha256sums.txt` de la publication |
| Hôtes | toutes les VMs étiquetées `socle` dans NetBox (15 dans un lab conforme au PLAN : `gw01`, `gw02`, `adm01`, `dns01`, `dns02`, `ca01`, `git01`, `nbx01`, `s3-01`, `runner01`, `runner02`, `reg01`, `lb01`, `lb02`, `mon01`) ; **pas** les nœuds Kubernetes (DaemonSet), ni `pve01`/`pbs01` (M21-E12) |
| TLS | certificat `node-exporter` par ACME (step-ca, rôle `certificats_acme`), nom `<hôte>.par1.medisphere.internal`, renouvelé par `cert-renewer@node-exporter` ; HTTPS seulement sur 9100 |
| Compatibilité | garder le dossier du collecteur textfile de la v1 (`/var/lib/prometheus/node-exporter`, les outils `ms-verif-*` y écrivent) et la métrique `medisphere_info` ; sur `git01`, node_exporter vient de l'omnibus de GitLab (M01-E30, `gitlab.rb` géré à la main) et non du paquet Debian |
| Cibles | ScrapeConfig **`vms`** (job **`vms`**) dans `plateforme/observabilite/scrape/vms.yaml`, **générée** par `playbooks/supervision-cibles.yml` depuis NetBox (jeton en lecture `netbox-ansible.env`), étiquettes **`site`**, **`role`** (de l'étiquette NetBox `role-<rôle>`), **`equipe`** (`plateforme`) |
| Flux | Prometheus sort par les travailleurs (`K8S_TRAV`, adresses des nœuds) : bordure (transit vers les VLAN 10, 20, 70 ; entrée des passerelles elles-mêmes) et pare-feu local des VMs (`pare_feu_local_communes`) ; MGMT pour tes vérifications |

**Travail demandé**

*A. Préparer*

1. Relis le rôle v1 et son scénario Molecule. Sur une VM du socle, relève ce qui tourne (`systemctl status prometheus-node-exporter`, `ss -ltnp | grep 9100`, `ls /var/lib/prometheus/node-exporter/`). Quels fichiers `.prom` y trouves-tu, et qui les écrit ? Fais le même relevé sur `git01` : qui y fournit node_exporter depuis le M01-E30, sur quelle adresse, et que se passera-t-il quand ton rôle voudra écouter au même endroit ?
2. Télécharge l'archive et `sha256sums.txt` de la 1.12.1 ; vérifie ; note l'empreinte. Pourquoi ne pas faire confiance à la seule connexion HTTPS vers GitHub ?

*B. Le rôle, version 2*

3. Réécris le rôle `node_exporter`. Exigences :
   - refus de toute cible non prise en charge avant d'agir (famille Debian ou EL, x86_64, port, adresse, empreinte bien formée) ;
   - archive téléchargée **une fois** sur le contrôleur et vérifiée par son empreinte, copiée sur les hôtes (ils n'ont pas besoin de sortir vers GitHub) ; une version par dossier, un lien vers la version active (retour arrière = rejouer avec l'ancienne version) ;
   - utilisateur système dédié, sans shell ;
   - certificat obtenu par le rôle `certificats_acme` appelé **depuis** ce rôle, avec une seule entrée, sans écraser la liste de certificats de l'hôte, et en réutilisant les commandes qui libèrent le port 80 quand l'hôte en a déjà ;
   - configuration web en TLS 1.2 minimum ; plus de HTTP en clair ;
   - bascule depuis le paquet Debian de la v1 sans laisser deux processus se disputer le port ;
   - unité systemd **durcie** (aucune capacité, système de fichiers en lecture seule, espaces de noms restreints, filtre d'appels système) qui laisse fonctionner les collecteurs systemd, filesystem et textfile ;
   - contrôle final **depuis le contrôleur** : `/metrics` en HTTPS avec certificat vérifié pour le nom de l'hôte, bonne version, HTTP refusé.
   Mets à jour `README.md` et `meta/argument_specs.yml` ; le scénario Molecule désactive le TLS (pas d'ACME dans une instance de test) : dis-le dans le README.
4. Les passerelles : leur route par défaut est le WAN. Sur quelle adresse doivent-elles écouter, et qu'est-ce qui les protège alors ?
5. `playbooks/node-exporter.yml` sur le groupe `socle` (sans les nœuds Kubernetes), **un hôte à la fois**. Pourquoi un hôte à la fois, ici plus qu'ailleurs ?

*C. Les flux*

6. Bordure (`group_vars/role_routeur/pare_feu.yml`) : transit `K8S_TRAV` → VMs du socle en 9100 ; entrée des passerelles en 9100 depuis `K8S_TRAV` et MGMT. Pare-feu local (`pare_feu_local_communes`) : 9100 depuis les travailleurs et MGMT. Vérifie aussi que `ca01` joint le port 80 des hôtes qui n'avaient pas encore de certificat ACME (sinon l'émission échoue : lis le message). Applique la bordure une passerelle à la fois.
   > ⚠️ **Attention** : une erreur dans la matrice des passerelles coupe tout le lab. `--check --diff` sur `gw01` d'abord, puis `gw01`, contrôle (`ping`, SSH, accès à GitLab), puis `gw02`. Retour arrière : `git revert` de la MR et même playbook, une passerelle à la fois.
7. Déploie d'abord sur `mon01` seul (`--limit mon01`), vérifie depuis `adm01` :
   ```
   admin@adm01:~$ curl -s https://mon01.par1.medisphere.internal:9100/metrics | grep ^node_exporter_build_info
   admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' http://mon01.par1.medisphere.internal:9100/metrics
   admin@adm01:~$ ssh mon01 'systemd-analyze security node_exporter.service | tail -1'
   ```
   puis tout le socle.

*D. Les cibles*

8. Écris `playbooks/supervision-cibles.yml` : lit dans NetBox les VMs du socle actives, en déduit une cible par VM (nom complet, port 9100) avec les étiquettes `site`, `role`, `equipe` et `hote`, écrit `scrape/vms.yaml` (une `ScrapeConfig` en HTTPS, certificat vérifié par la ConfigMap `racine-medisphere`, nom de job `vms`, `instance` = nom court) dans ta copie de `plateforme/observabilite`, et, **si le fichier a changé**, pousse une branche qui ouvre elle-même une MR. Un garde-fou refuse d'écrire une liste vide ou tronquée. Ajoute `vms.yaml` à `scrape/kustomization.yaml`.
9. Lance-le, relis la MR (diff), fusionne. Dans Prometheus : `count(up{job="vms"} == 1)`, `node_exporter_build_info{job="vms"}`, `medisphere_info`. Arrête node_exporter sur une VM (`systemctl stop`) une minute : que voit Prometheus ? Relance-le.
10. Documente les flux (matrice des flux du socle), le rôle (README) et, dans ton journal, ce que tu ferais pour une VM d'environnement de module (pas étiquetée `socle`).

**Critères de réussite**
- [ ] Le rôle `node_exporter` v2 et les deux playbooks sont sur `main` de `plateforme/ansible` ; `scrape/vms.yaml` (généré) est sur `main` de `plateforme/observabilite`.
- [ ] La ScrapeConfig `vms` (job `vms`, étiquette de sélection) collecte en HTTPS avec vérification du certificat par la racine MédiSphère, sans `insecureSkipVerify`, au moins 15 cibles désignées par leur nom complet sur le port 9100.
- [ ] Au moins 15 VMs du socle sont `up{job="vms"}`, aucune en échec, toutes étiquetées `site`, `role`, `equipe` ; toutes en node_exporter 1.12 ; `medisphere_info` toujours publiée.
- [ ] Depuis `adm01`, `https://<hôte>.par1.medisphere.internal:9100/metrics` répond avec un certificat vérifié, et le HTTP en clair est refusé.

**Vérification** : `lab/bin/check 21 08`

<details><summary>Indice 1</summary>

`get_url` accepte `checksum: sha256:<empreinte>` et refuse un fichier différent ; `delegate_to: localhost` et `run_once: true` le cantonnent au contrôleur ; `unarchive` copie depuis le contrôleur par défaut. Pour appeler un autre rôle avec une seule entrée : `include_role` avec `vars:` — mais une variable qui se référence elle-même (la liste de l'hôte lue pour construire la liste passée au rôle) boucle : calcule l'entrée avant, par `set_fact`.
</details>

<details><summary>Indice 2</summary>

node_exporter lit sa configuration TLS dans un fichier passé par `--web.config.file` (format d'*exporter-toolkit*), relu à chaque connexion ; `promtool check web-config` le valide. Un serveur Go en TLS répond `400` à une requête HTTP en clair. Côté systemd : `systemd-analyze security` note chaque directive ; le collecteur systemd parle à systemd par un socket Unix (D-Bus), le collecteur filesystem fait `statfs()` sur les points de montage.
</details>

<details><summary>Indice 3</summary>

Le greffon de recherche `netbox.netbox.nb_lookup` interroge l'API de NetBox (`api_filter` : mêmes filtres que l'API). Les options de poussée de GitLab (`git push -o merge_request.create -o merge_request.target=main`) créent la MR au moment de la poussée. Dans une `ScrapeConfig`, `jobName` fixe le nom du job, `tlsConfig.ca.configMap` désigne la racine.
</details>

**Pour aller plus loin** (facultatif) : NetBox peut servir directement de source de découverte à Prometheus (`http_sd_configs` vers un greffon de NetBox qui expose les cibles) : compare avec la génération par MR (ce qu'on gagne en fraîcheur, ce qu'on perd en relecture).

---

### M21-E09 — Questions : modèle de données et architecture de Prometheus  `Q` `★★`

> **Ticket PLAT-2209** — *De : Karim Benali*
> Tu as monté la pile, écrit des requêtes, reçu tes premiers courriels. Avant d'attaquer l'opérationnel, je veux vérifier que tu as compris ce qu'il y a sous le capot : comment Prometheus range ce qu'il collecte, ce que fait l'opérateur, et ce qui se passe quand une cible disparaît. Par écrit, sans exécuter, en t'appuyant sur ce que tu as observé.

**Objectifs pédagogiques**
- Expliquer le modèle de données (séries, étiquettes, échantillons, types) et ses conséquences.
- Décrire l'architecture d'un Prometheus (découverte, collecte, TSDB locale, WAL, règles) et celle de l'opérateur.
- Raisonner sur la péremption (*staleness*), les intervalles et les fenêtres.

**Prérequis** : M21-E02 à E08.
**Durée indicative** : 1 h 30.

**Travail demandé**

Réponds aux 14 questions, en t'appuyant sur ce que tu as vu dans ton lab quand c'est possible.

1. Écris, au format d'exposition texte, deux échantillons de `mediagenda_http_requests_total` que tu as vus dans `/metrics`. Qu'est-ce qui identifie une série ? L'horodatage figure-t-il dans `/metrics` ?
2. Qu'est-ce qu'une étiquette « cible » (`job`, `instance`, `namespace`, `pod`) et une étiquette « métrique » (`route`, `code`) ? Qui pose les unes et les autres ? Que se passe-t-il quand les deux portent le même nom (`honorLabels`) ?
3. *(QCM)* Le nom d'une métrique est, pour Prometheus :
   - A. un attribut à part, qu'on ne peut pas sélectionner par une expression régulière
   - B. une étiquette comme une autre, `__name__`
   - C. le nom du fichier où la série est stockée
   - D. un préfixe facultatif
4. Décris le chemin d'un échantillon, de la collecte au disque : *head block*, WAL, blocs de 2 h, compaction. Pourquoi le WAL ? Que perd-on si le pod Prometheus est tué brutalement ?
5. Pourquoi ne faut-il pas poser un volume NFS sous la TSDB de Prometheus ? Quel stockage as-tu choisi en E02 ?
6. Une cible disparaît (pod supprimé). Que deviennent ses séries dans une requête instantanée, une minute après ? Et dans une requête sur la dernière heure ? Explique la péremption (*staleness markers*) et la fenêtre de recherche de 5 minutes.
7. Pourquoi une fenêtre de `rate` doit-elle couvrir au moins quatre intervalles de collecte ? Qu'arrive-t-il avec `rate(x[30s])` et une collecte toutes les 30 s ?
8. Qu'est-ce qu'une règle d'**enregistrement** ? Donne un exemple utile pour le tableau de bord d'E05, et la convention de nommage que tu lui donnerais.
9. Comment l'opérateur passe-t-il d'un `ServiceMonitor` à une configuration chargée par Prometheus ? Cite les composants et objets en jeu (CR, Secret, conteneur de rechargement), et où regarder quand un ServiceMonitor n'est pas pris en compte.
10. *(QCM)* Le ServiceMonitor `mediagenda` existe, mais aucune cible n'apparaît, sans aucune erreur nulle part. La cause la plus probable dans notre lab :
    - A. Prometheus n'a pas les droits de lire les Services
    - B. Le ServiceMonitor n'a pas l'étiquette `medisphere.internal/supervision: "oui"`
    - C. Le port `http` n'existe pas
    - D. La politique réseau bloque la collecte
11. Pourquoi Prometheus a-t-il besoin de droits RBAC en lecture sur `endpoints` (ou `endpointslices`), `services`, `pods` ? Et pourquoi `nodes/metrics` ?
12. Que gagne-t-on à un Prometheus par cluster plutôt qu'un Prometheus central qui collecte tous les clusters à travers le réseau ? Qu'est-ce que la **fédération**, et sa limite ?
13. Prometheus n'est pas un système de stockage durable ni distribué : qu'en déduis-tu pour la haute disponibilité (deux réplicas qui collectent les mêmes cibles) ? Comment Alertmanager évite-t-il les doublons de notification avec deux Prometheus ?
14. Quelles sont les limites du modèle *pull* que tu as rencontrées en E08 (pare-feu, TLS, découverte), et comment les as-tu traitées ?

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 14 questions avant d'ouvrir le corrigé.
- [ ] Tu as noté chaque réponse avec la grille (0, 1 ou 2 points) : au moins 20 sur 28 avant de passer au palier 2.

<details><summary>Indice 1</summary>

Pour la TSDB, pense à ce qui est en mémoire et ce qui est sur disque à un instant donné, et à ce qu'il faut relire au démarrage.
</details>

<details><summary>Indice 2</summary>

Pour l'opérateur, relis ce que tu as observé en E03 (le Secret de configuration) et en E07 (le diagnostic d'une cible absente) : chaque étape a laissé une trace.
</details>

**Pour aller plus loin** (facultatif) : lis l'article « Prometheus TSDB » de Ganesh Vernekar (série en plusieurs parties, sur son blog) ; M21-E44 ouvre ces fichiers pour de vrai.
