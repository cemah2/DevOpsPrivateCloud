# Module 21 — Palier 3 : Production

Les paliers 1 et 2 ont donné à MédiSphère une supervision qui marche les jours où tout va bien : un Prometheus, un Alertmanager, des tableaux, des alertes routées, un témoin sur `mon01`. Elle n'est pas encore **de production**. Un seul Prometheus : s'il redémarre, il y a un trou dans les courbes et aucune alerte pendant ce temps. Quinze jours d'historique sur un volume : Claire Morel veut **deux ans** pour les contrats HDS et les tendances de capacité. Aucun objectif chiffré : on alerte sur des seuils, pas sur ce que l'on a promis aux centres de santé. Personne ne surveille la supervision elle-même. Grafana accepte des sessions sans fin, les API de Prometheus n'ont pas d'authentification, et une équipe peut écrire une règle qui lit les métriques de toutes les autres. Personne ne sait combien de séries Prometheus peut tenir avant de tomber. Ce palier fait passer la supervision en production : redondance et conservation longue avec **Thanos** sur le RGW, **SLO** et alertes de **budget d'erreur**, **supervision de la supervision**, sécurité, capacité, puis l'ADR, la politique d'alerte, les questions de production et un diagnostic chronométré.

> ⚠️ **Rappel** : à partir d'ici, la supervision **est** l'astreinte. Chaque changement de ce palier peut la rendre muette sans bruit : un Prometheus qui ne démarre plus, une politique réseau qui coupe Alertmanager, une règle refusée. Avant **tout** changement de `kps/values.yaml` ou des politiques de l'espace `supervision` : (1) vérifie que l'alerte `Watchdog` est active (`ALERTS{alertname="Watchdog"}`) et que le témoin de `mon01` est vert ; (2) passe par une MR, relis le rendu (`helm template … | diff`) ; (3) après la synchronisation, revérifie `Watchdog`, les cibles (`up == 0`) et un envoi d'alerte d'essai. Les deux réplicas de Prometheus **doublent** sa mémoire : vérifie la marge des travailleurs (`kubectl top nodes`) avant E24.

**Chemin imposé** (introduction du module) : la configuration de la supervision vit dans **`plateforme/observabilite`** (`kps/values.yaml`, `regles/`, `scrape/`, `thanos/`, `slo/`, `pyrra/`, `reseau/`, `tests/`, `requetes/`), appliquée par Argo CD (Applications `kube-prometheus-stack`, `observabilite`, et `pyrra` créée ici) ; les espaces, le RBAC et les Secrets (hors Git, `outils/secrets-k8s.sh` et Ansible Vault `critique`) dans `plateforme/k8s` ; le témoin de `mon01` par le rôle `supervision_temoin` de `plateforme/ansible` ; les flux de la bordure dans `group_vars/role_routeur/pare_feu.yml` et `docs/socle/matrice-flux.md`, ceux du cluster dans `docs/kubernetes/reseau/matrice-flux-cluster.md` ; la documentation dans `docs/observabilite/metriques/` de `plateforme/medisphere` (`adr/`, `runbooks/`). Tout passe par une MR relue. Aucune modification à la main dans le cluster : ce que tu changes avec `kubectl`, Argo CD le défait.

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| kube-prometheus-stack | chart 92.11.0, release `kps` (`fullnameOverride: kps`, `cleanPrometheusOperatorObjectNames: true`) : CR Prometheus **`kps`** (StatefulSet `prometheus-kps`, pods `prometheus-kps-0` et `-1`, Service `kps-prometheus:9090`, job `kps-prometheus`), CR Alertmanager `kps` (pods `alertmanager-kps-N`), Grafana `kps-grafana` ; sélecteur de tous les objets de supervision : étiquette **`medisphere.internal/supervision: "oui"`** |
| Accès | `prometheus.apps.par1.medisphere.internal:9090` = **10.10.41.60** (Service `prometheus-externe`) : Prometheus jusqu'à E24, **Thanos Query** ensuite ; `alertmanager.apps.par1.medisphere.internal:9093` = 10.10.41.61 ; filtrés par CiliumNetworkPolicy (MGMT 10.10.10.0/24 et `mon01` 10.10.20.19 seulement) |
| Thanos (E24-E25) | **0.42.4**, image `registry.par1.medisphere.internal/quay/thanos/thanos:v0.42.4` (sidecar compris), manifestes écrits dans `plateforme/observabilite/thanos/` (jamais le chart ni les images Bitnami) ; Services `thanos-query` (9090 → 10902, gRPC 10901), `thanos-store` (*headless*), `thanos-compactor` ; sidecars découverts par le Service `kps-thanos-discovery` du chart ; étiquette de réplica **`prometheus_replica`** (posée par l'opérateur), étiquettes externes `cluster="k8s-par1"`, `site="par1"` |
| Stockage objet | RGW de `ceph-par1`, `https://rgw.par1.medisphere.internal` (VIP 10.10.30.200, certificat step-ca), joint par les travailleurs par `eth1` (M16) ; utilisateur RGW **`thanos`**, compartiment **`thanos-k8s-par1`** ; Secret **`thanos-objstore`** (clé `objstore.yml`) créé hors Git par `secrets-k8s.sh`, composant `thanos`, depuis le Vault `secrets/thanos.yml` ; sur `adm01` : `~/.config/workbook/s3-thanos.env` (600) |
| Rétentions | Prometheus : 15 jours en local ; compartiment : brut **30 j**, 5 min **180 j**, 1 h **2 ans** |
| Pyrra (E26-E27) | **0.10.2**, image `registry.par1.medisphere.internal/ghcr/pyrra-dev/pyrra:v0.10.2`, manifestes amont recopiés dans `plateforme/observabilite/pyrra/` (Application Argo CD `pyrra`), interface `https://slo.apps.par1.medisphere.internal` ; SLO dans `slo/` : **`mediagenda-disponibilite`**, **`mediagenda-latence`**, **`medidoc-disponibilite`** |
| Témoin (E28) | `mon01` : Prometheus 9090, Alertmanager 9093, blackbox_exporter 127.0.0.1:9115 (rôle `supervision_temoin`, E11-E12, HTTP) ; règles dans `/etc/prometheus/regles/` |
| Applications | MédiAgenda : compteur `mediagenda_http_requests_total` (étiquettes `methode`, `route`, `code`), histogramme `mediagenda_http_request_duration_seconds` (seaux par défaut du client Python), compteur `mediagenda_cache_total{resultat}` ; routes de sonde `/sante`, `/pret`, `/metrics` ; production dans `mediagenda-prod`, recette dans `mediagenda-recette` (CNPG `mediagenda-db`, base `mediagenda`). MédiDoc : `medidoc_http_requests_total`, routes `GET /healthz`, `GET /readyz`, `GET /metrics`, recette dans `medidoc-recette` |
| Documentation | `docs/observabilite/metriques/` : `thanos.md`, `slo.md`, `politique-budget-erreur.md`, `comparatif-pyrra-sloth.md`, `securite.md`, `dimensionnement.md`, `politique-alerte.md`, `adr/ADR-0210-*.md`, runbooks **RB-214** (Thanos), **RB-215** (supervision muette), **RB-216** (budget d'erreur) |

**Ordre conseillé** : E24 → E25 → E26 → E27 → E28 → E29 → E30 → E31 → E32 → E33 → E34. Thanos (E24) précède tout le reste : Pyrra lit Thanos Query, le témoin l'interroge, la capacité se mesure à deux réplicas. La sécurité (E29) vient après E28 pour que le témoin voie tout de suite si le cloisonnement casse quelque chose. **Durée totale indicative** : 24 à 29 h.

Les vérifications se lancent **depuis `adm01`** (`lab/bin/check 21 XX`). Variables facultatives de `lab/lab.env` : `WB_M21_S3_THANOS_FILE`, `WB_M21_RGW_URL`, `WB_M21_TEMOIN_URL`, `WB_M21_SLO_URL`, `WB_M21_RECETTE_URL`, `WB_M21_IMAGE_CURL` (valeurs par défaut dans `lab/lab.env.example`).

---

### M21-E24 — Prometheus redondant et Thanos sur le RGW  `LAB` `★★★`

> **Ticket PLAT-2224** — *De : Claire Morel* — *Copie : Karim Benali, Nadia Roussel*
> Mardi, Prometheus a redémarré pendant une montée de version de nœud : vingt minutes sans collecte, sans alerte, et un trou dans toutes les courbes du comité de direction. Et le contrat HDS nous demande de prouver nos niveaux de service sur un an au moins ; on garde quinze jours.
> Je veux deux Prometheus, un point de lecture unique qui ne montre jamais de trou tant que l'un des deux vit, et deux ans d'historique sur notre stockage objet. Pas de nouvelle adresse pour les utilisateurs : 10.10.41.60 reste « Prometheus ».

**Objectifs pédagogiques**
- Comprendre ce que deux réplicas de Prometheus donnent (et ne donnent pas) : redondance de la collecte, pas de partage de charge, dédoublonnage à la lecture et dans Alertmanager.
- Comprendre l'architecture de Thanos avec *sidecar* : envoi des blocs de 2 h, StoreAPI, Query, Store Gateway, étiquettes externes et de réplica.
- Préparer un stockage objet pour un composant : utilisateur RGW à droits et quota bornés, compartiment, configuration `objstore` hors Git, confiance TLS.
- Repointer un point d'accès (Service `LoadBalancer`, source Grafana) sans changer l'adresse vue par les clients.

**Prérequis** : M21-E02 (kube-prometheus-stack, Services `LoadBalancer`), M21-E05 (source Grafana), M21-E06 (ConfigMap `racine-medisphere`), M08-E12 (utilisateurs et quotas RGW), M16-E46 (pods → RGW par `eth1`), M20-E02 (`secrets-k8s.sh`).
**Durée indicative** : 4 h.

**Contexte technique**
- **Lecture obligatoire** : [Thanos — Sidecar](https://thanos.io/tip/components/sidecar.md/), [Querier](https://thanos.io/tip/components/query.md/), [Store](https://thanos.io/tip/components/store.md/), [Object storage, S3](https://thanos.io/tip/thanos/storage.md/#s3) ; la spécification `ThanosSpec` et le champ `replicaExternalLabelName` de l'[API de prometheus-operator](https://prometheus-operator.dev/docs/api-reference/api/) ; les clés `prometheus.thanosService` et `prometheus.prometheusSpec.thanos` du `values.yaml` de kube-prometheus-stack 92.
- **Thanos 0.42** : l'option `--endpoint` de Thanos Query est **dépréciée** ; les points d'accès se déclarent dans un fichier (`--endpoint.sd-config-file`, liste `endpoints:` avec des adresses `dnssrv+_grpc._tcp.<service>…`). Une option répétée sur la ligne de commande fait **refuser le démarrage**.
- **prometheus-operator 0.94** décide seul du mode de compaction locale quand le sidecar envoie des blocs : avec Prometheus ≥ 3.9 et Thanos ≥ 0.42, il garde la compaction de Prometheus active et la coordonne avec les envois. Lis dans `kubectl get sts prometheus-kps -o yaml` les options qu'il a posées sur les conteneurs `prometheus` et `thanos-sidecar`.
- **Utilisateur RGW** : un utilisateur RGW « classique » (`radosgw-admin user create`, pas un compte IAM du M08-E12), un seul compartiment (`--max-buckets`), un quota de taille (40 Gio pour commencer, à justifier en E30). Commandes sur `ceph01` en `sudo`. La clé secrète ne doit jamais s'afficher à l'écran : elle passe dans `~/.config/workbook/s3-thanos.env` (600), puis dans le Vault.
- **TLS** : le RGW présente un certificat step-ca. Les images de Thanos ne connaissent pas la racine MédiSphère : la ConfigMap `racine-medisphere` (clé `ca.crt`, E06) existe dans `supervision` ; montée au même chemin (`/etc/thanos/ca`) dans le sidecar et dans chaque composant, référencée par `http_config.tls_config.ca_file` de la configuration `objstore`. Le RGW du lab n'a pas de joker DNS : style d'adressage **par chemin**.
- **Point d'accès** : le Service `prometheus-externe` (10.10.41.60, `extraManifests` de `kps/values.yaml`, E02) garde son adresse, son nom et son port 9090 ; seul son sélecteur change. La politique `prometheus-entree` d'E02 n'ouvre aux pods Prometheus que 9090 et 8080 : Thanos Query doit joindre le sidecar en **10901**, Prometheus collecter le sidecar en **10902**.
- **Ce que Thanos Query ne sert pas** : `/federate`, `/api/v1/status/config`, l'API d'administration. Tout ce qui lisait ces chemins sur 10.10.41.60 doit être revu (cherche-les, notamment chez le témoin de `mon01`).

> ⚠️ **Attention** : (1) deux réplicas = deux fois la mémoire de Prometheus, sur deux travailleurs différents ; si un travailleur n'a pas la place, le second pod reste `Pending` — vérifie avant ; (2) le passage de 1 à 2 réplicas et l'ajout du sidecar **redémarrent** `prometheus-kps-0` : quelques minutes sans collecte, comme au ticket — fais-le en dehors d'un autre essai ; (3) ne mets **ni versionnage ni règle de cycle de vie** sur le compartiment : la rétention appartient au Compactor (E25) ; (4) retour arrière : `git revert` de la MR de `kps/values.yaml` (le Service `prometheus-externe` repart vers Prometheus), le compartiment et l'utilisateur RGW peuvent rester.

**Travail demandé**
1. **Lecture.** Réponds dans ton journal : que contient un bloc de 2 h, et pourquoi le sidecar ne l'envoie-t-il qu'une fois fermé ? Qu'est-ce que la StoreAPI et qui la parle ? Comment Thanos Query sait-il que deux séries viennent de deux réplicas du même Prometheus ? Que se passerait-il sans étiquette de réplica ? Pourquoi les **alertes** des deux réplicas n'arrivent-elles pas en double chez Alertmanager (lis la configuration générée par l'opérateur : `kubectl -n supervision get secret prometheus-kps -o jsonpath='{.data.prometheus\.yaml\.gz}' | base64 -d | gunzip | grep -A4 alert_relabel`) ? Qu'est-ce qui reste un point unique de défaillance ?
2. **Stockage objet.** Sur `ceph-par1` : utilisateur `thanos` (un compartiment au plus, quota de taille activé), identifiants écrits dans `~/.config/workbook/s3-thanos.env` sans passer par l'écran. Avec ces identifiants : crée `thanos-k8s-par1`, vérifie que tu peux le lister et que tu **ne peux pas** créer un second compartiment. Range la paire de clés dans le Vault `critique` (`plateforme/k8s`, `secrets/thanos.yml`) et au registre des secrets. Écris le tout dans un script rejouable (rangé dans `plateforme/ceph`).
3. **Secret.** Ajoute le composant `thanos` à `secrets-k8s.sh` : il construit `objstore.yml` (type S3, point d'accès, compartiment, style par chemin, CA) à partir du Vault, en mémoire, et crée le Secret `supervision/thanos-objstore`. Vérifie sa présence (jamais son contenu à l'écran).
4. **Prometheus ×2 et sidecar.** Dans `kps/values.yaml` : deux réplicas sur deux nœuds différents (anti-affinité stricte), sidecar Thanos (image et version explicites, configuration `objstore` par le Secret existant, CA montée), Service et ServiceMonitor des sidecars. Relis le rendu, MR, synchronisation. Vérifie les deux pods, les options du sidecar, puis attends le premier envoi (2 à 3 h) : `aws s3 ls s3://thanos-k8s-par1/` doit montrer des dossiers de blocs, et le `meta.json` d'un bloc ses étiquettes externes.
5. **Thanos Query et Store Gateway.** Écris dans `plateforme/observabilite/thanos/` (kustomization incluse par la racine) : Thanos Query (2 réplicas, sans état, sans jeton d'API Kubernetes, dédoublonnage sur `prometheus_replica`, réponse partielle si un point d'accès manque, budget de disruption), Store Gateway (StatefulSet, volume `ceph-rbd` de cache, tailles de cache adaptées au lab, configuration `objstore` et CA montées), leurs Services, leurs ServiceMonitors, leurs politiques d'entrée. Contexte de sécurité *restricted*, ressources, sondes `/-/ready` et `/-/healthy`.
6. **Bascule de 10.10.41.60 et de Grafana.** Repointe `prometheus-externe` vers Thanos Query, adapte `prometheus-entree`, puis la source Grafana par défaut (même uid : les tableaux d'E05 et d'E17 ne doivent pas changer). Contrôle depuis `adm01` : `curl -s http://prometheus.apps.par1.medisphere.internal:9090/api/v1/stores | jq` (deux sidecars, un Store, aucune erreur) ; une requête avec et sans dédoublonnage (`&dedup=false`) : explique la différence.
7. **Épreuve.** Supprime `prometheus-kps-0` et rafraîchis un tableau de Grafana de la dernière heure pendant son redémarrage : y a-t-il un trou ? Et dans les données d'un seul réplica (`dedup=false`, `prometheus_replica="prometheus-kps-0"`) ? Note dans ton journal ce qui a été perdu et ce qui ne l'a pas été.
8. **Documentation.** `docs/observabilite/metriques/thanos.md` : architecture (schéma), versions, étiquettes, rétentions, flux, ce que 10.10.41.60 ne sert plus. Mets à jour les matrices des flux (bordure et cluster) si besoin.

**Critères de réussite**
- [ ] Le CR Prometheus `kps` a 2 réplicas prêts sur deux nœuds différents, avec un sidecar Thanos 0.42 tiré par Harbor et configuré par le Secret `thanos-objstore`.
- [ ] `thanos-query` (2 réplicas) et `thanos-store` sont prêts ; 10.10.41.60:9090 répond comme Thanos (`/api/v1/status/buildinfo`) et voit 2 sidecars et 1 Store sans erreur ; la lecture est dédoublonnée.
- [ ] La source Grafana par défaut interroge Thanos Query, avec le même uid qu'avant.
- [ ] Le compartiment `thanos-k8s-par1` contient des blocs des **deux** réplicas, étiquetés `cluster="k8s-par1"` ; il n'est pas versionné ; l'utilisateur RGW `thanos` est limité à un compartiment, avec un quota actif ; `s3-thanos.env` est en 600.
- [ ] `thanos.md` et le script RGW sont sur `main` (`plateforme/medisphere`, `plateforme/ceph`) ; aucune clé dans un dépôt.

**Vérification** : `lab/bin/check 21 24` (le contrôle des blocs ne passe qu'après le premier envoi, 2 à 3 h après la mise en service)

<details><summary>Indice 1</summary>

Le chart sait créer le Service de découverte des sidecars et son ServiceMonitor : cherche `thanosService` et `thanosServiceMonitor`. Pour le sidecar lui-même, `prometheusSpec.thanos` est recopié tel quel dans le CR : lis les champs de `ThanosSpec` (image, version, `objectStorageConfig`, `volumeMounts`) ; le volume se déclare dans `prometheusSpec.volumes`.
</details>

<details><summary>Indice 2</summary>

Un enregistrement SRV se demande pour un **port nommé** d'un Service *headless* : `_grpc._tcp.<service>.<espace>.svc.cluster.local`. Si Thanos Query ne voit rien, lis ses journaux (« no such host » ou « connection refused ») et Hubble (`--verdict DROPPED`) : le DNS, puis la politique d'entrée des pods Prometheus.
</details>

<details><summary>Indice 3</summary>

« x509: certificate signed by unknown authority » dans les journaux du sidecar ou du Store : le fichier désigné par `ca_file` n'existe pas dans **ce** conteneur (volume monté dans `prometheus` mais pas dans `thanos-sidecar` ?). « The specified bucket does not exist » avec un nom d'hôte bizarre : style d'adressage virtuel au lieu du chemin.
</details>

**Pour aller plus loin** (facultatif) : Thanos Query Frontend (découpage et cache des requêtes longues) ; le mode `--query.mode=distributed` ; [Receive](https://thanos.io/tip/components/receive.md/) comme alternative au sidecar (et pourquoi pas ici) ; le chiffrement côté serveur du compartiment (SSE du RGW).

---

### M21-E25 — Thanos : vue globale, compaction, sous-échantillonnage, rétention  `LAB` `★★★`

> **Ticket PLAT-2225** — *De : Karim Benali*
> Les blocs arrivent dans le RGW, très bien. Sans Compactor, ils vont s'empiler par paquets de deux heures, en double (deux réplicas), pour toujours, et une requête sur six mois lira quatre mille petits blocs bruts. Je veux la compaction, le sous-échantillonnage et les rétentions du PLAN, une alerte si ça s'arrête, et la preuve qu'une requête d'un an reste rapide.
> Et je le répète : un Compactor. Pas deux. Jamais.

**Objectifs pédagogiques**
- Comprendre le rôle du Compactor : compaction (niveaux de blocs), dédoublonnage hors ligne des réplicas, sous-échantillonnage (5 min, 1 h), rétention par résolution, suppression différée.
- Savoir pourquoi deux Compactors sur un même compartiment détruisent des données, et le garantir par la conception (StatefulSet, stratégie de mise à jour, alerte).
- Lire un compartiment sans l'abîmer (`thanos tools bucket`, interface des blocs) et choisir la résolution d'une requête longue.
- Écrire et tester les alertes de la chaîne de conservation.

**Prérequis** : M21-E24, M21-E15 (alertes et tests de règles), M21-E14 (`outils/extraire-regles.sh`, dossier `build/`).
**Durée indicative** : 3 h.

**Contexte technique**
- Lecture : [Thanos — Compactor](https://thanos.io/tip/components/compact.md/) (en entier : *Downsampling*, *Retention*, *Vertical compaction*, *Risk*, *Halting*), [Bucket tools](https://thanos.io/tip/components/tools.md/#bucket), alertes d'exemple de Thanos (`examples/alerts/alerts.md` de la version 0.42.4).
- Rétentions du PLAN : brut **30 j**, 5 min **180 j**, 1 h **2 ans**. Un bloc 5 min n'est produit qu'à partir de blocs bruts de plus de **40 h** ; un bloc 1 h à partir de blocs 5 min de plus de **10 jours**. Le sous-échantillonnage ne réduit pas forcément la taille : il réduit le coût des requêtes longues.
- Le Compactor a besoin d'un espace de travail local (il télécharge les blocs qu'il fusionne) : volume `ceph-rbd`.
- Lecture du compartiment depuis `adm01` : `thanos` 0.42.4 (binaire amont vérifié par son empreinte, dans `~/.local/bin`) et une configuration `objstore` fabriquée à partir de `s3-thanos.env`, dans un fichier 600 en mémoire (`$XDG_RUNTIME_DIR`), jamais dans un dépôt. Les identifiants de l'utilisateur `thanos` permettent aussi d'**écrire** : n'emploie que les sous-commandes de lecture.
- Métriques utiles : `thanos_compact_halted`, `thanos_compact_iterations_total`, `thanos_compact_downsample_total`, `thanos_objstore_bucket_last_successful_upload_time`, `thanos_objstore_bucket_operation_failures_total`, `thanos_shipper_uploads_total` (sidecars), `thanos_store_nodes_grpc_connections` (Query, étiquette `store_type`).
- Noms imposés (vérifiés par le check, repris au palier 4) : PrometheusRule `thanos` (`regles/thanos.yaml`) avec au moins les alertes **`ThanosCompacteursMultiples`** (critique), **`ThanosCompacteurArrete`**, **`ThanosSidecarEnvoisArretes`**, **`ThanosQueryStoreManquant`** ; runbook **RB-214**.

> ⚠️ **Attention** : (1) **jamais deux Compactors** sur `thanos-k8s-par1` — pas de copie « pour essayer », pas de second cluster pointé sur le même compartiment, pas de `kubectl scale` à 2 ; (2) le premier passage du Compactor sur un compartiment de plusieurs jours télécharge beaucoup : surveille le volume de travail et la charge de `ceph-par1` ; (3) une rétention mal écrite **supprime** des blocs (après le délai de `--delete-delay`) : relis les trois valeurs deux fois, et sache qu'une valeur `0d` signifie « pour toujours » ; (4) retour arrière : mettre le StatefulSet à 0 réplica par Git ; rien n'est supprimé avant `--delete-delay`.

**Travail demandé**
1. **Lecture.** Dans ton journal : niveaux de compaction et pourquoi ; pourquoi le dédoublonnage hors ligne est nécessaire **en plus** de celui de Thanos Query ; ce que fait l'algorithme `penalty` et pourquoi le défaut ne convient pas à deux Prometheus ; ce qu'est un Compactor « halted » et pourquoi il s'arrête plutôt que de continuer ; pourquoi deux Compactors perdent des données.
2. **Inventaire avant.** Depuis `adm01`, en lecture : `thanos tools bucket ls` puis `inspect` (nombre de blocs, niveaux, résolutions, réplicas). Note les chiffres.
3. **Compactor.** Dans `thanos/` : StatefulSet à **un** réplica (mise à jour seulement à la suppression du pod), volume de travail, rétentions du PLAN, dédoublonnage sur `prometheus_replica` (algorithme adapté), fonctionnement continu, délai de suppression, Service, ServiceMonitor, politique d'entrée. MR, synchronisation, journaux du premier passage.
4. **Interface des blocs.** Ouvre l'interface du Compactor (`kubectl port-forward`) et compare à l'inventaire : quels blocs ont été fusionnés, lesquels dédoublonnés ? Combien de temps avant le premier bloc 5 min ? (Reviens-y deux jours plus tard.)
5. **Alertes.** `regles/thanos.yaml` : au moins les quatre alertes imposées, plus ce que tu juges utile (Compactor absent ou inactif, échecs d'opérations sur le compartiment, sidecar manquant pour Query). Étiquettes `gravite`, `equipe` ; annotations `resume`, `description`, `runbook_url`. Une seule est critique : laquelle et pourquoi ? Tests `promtool` dans `tests/` (dont un cas « sidecar redémarré il y a une heure : pas d'alerte »). Pipeline vert.
6. **Requêtes longues.** Dans Grafana et sur 10.10.41.60, une requête sur 30 jours puis sur la plus longue période disponible : mesure le temps de réponse et le nombre de séries lues avec et sans `max_source_resolution` (paramètre de l'API de Thanos Query) ; que choisit `--query.auto-downsampling` ? Note les chiffres.
7. **Runbook.** `RB-214` : blocs qui n'arrivent plus, Compactor arrêté ou inactif, Store ou sidecar invisible, deux Compactors. Pour chaque cas : constat, commandes de diagnostic (lecture seule), correctif, ce qu'il ne faut **pas** faire.

**Critères de réussite**
- [ ] Un seul pod `thanos-compactor` tourne dans tout le cluster ; ses arguments portent les trois rétentions du PLAN, le dédoublonnage sur `prometheus_replica` et le fonctionnement continu.
- [ ] `thanos_compact_halted` vaut 0, au moins un passage a réussi ; des blocs sous-échantillonnés existent dès que le compartiment a plus de 48 h de données.
- [ ] Les quatre alertes imposées sont chargées par Prometheus ; leurs tests sont dans `tests/` ; pipeline vert.
- [ ] RB-214 est sur `main` de `plateforme/medisphere` ; ton journal contient l'inventaire avant/après et les mesures des requêtes longues.

**Vérification** : `lab/bin/check 21 25`

<details><summary>Indice 1</summary>

`thanos compact --help` liste toutes les options : cherche « retention », « deduplication », « wait », « delete-delay ». Un StatefulSet garantit au plus un pod d'ordinal 0 ; ce qui reste à empêcher, c'est un **autre** objet qui lancerait un Compactor sur le même compartiment.
</details>

<details><summary>Indice 2</summary>

Pour une alerte « le sidecar n'envoie plus » : `thanos_objstore_bucket_last_successful_upload_time` vaut 0 après un redémarrage tant que rien n'est parti, ce qui ferait sonner une alerte naïve à chaque redémarrage. Un compteur d'envois sur une fenêtre, combiné à l'âge du processus (`process_start_time_seconds`), évite ce faux positif.
</details>

<details><summary>Indice 3</summary>

Une série qui n'existe pas ne vaut pas 0 : « aucune connexion de type store » fait **disparaître** la série au lieu de la mettre à 0. Pour comparer à un seuil, fabrique un 0 quand la série manque (`or` avec une autre série du même pod multipliée par 0).
</details>

**Pour aller plus loin** (facultatif) : `thanos tools bucket verify` (lecture) et ce que ferait `--repair` (ne le lance pas) ; marquer un bloc `no-compact` ; la compaction verticale et l'option `--compact.enable-vertical-compaction` ; le Compactor « bucketé » par étiquettes externes quand plusieurs clusters écrivent dans un même compartiment.

---

### M21-E26 — SLI et SLO de MédiAgenda avec Pyrra  `LAB` `★★★`

> **Ticket PLAT-2226** — *De : Claire Morel* — *Copie : Julien Petit*
> Le contrat HDS des centres de santé dit « 99,5 % de disponibilité mensuelle » et « temps de réponse inférieur à 300 ms pour 95 % des requêtes ». Je veux que ces deux phrases deviennent des objectifs mesurés en continu, avec ce qu'il nous reste de marge, visibles par l'équipe MédiAgenda sans passer par moi. Et pareil pour MédiDoc, même si ce n'est encore que de la recette.

**Objectifs pédagogiques**
- Passer d'une phrase de contrat à un SLI mesurable : bon événement, événement valide, exclusions, fenêtre.
- Déployer un outil sans chart officiel à partir de manifestes amont (recopie, écarts commentés, images par Harbor, sécurité).
- Comprendre ce que Pyrra génère (règles d'enregistrement par fenêtre, alertes) et où sont évaluées ces règles.
- Repérer les limites d'une mesure (seaux d'histogramme, trafic faible, rétention).

**Prérequis** : M21-E24 (Thanos Query), M21-E13 (étiquettes des séries de MédiAgenda), M21-E14 (règles d'enregistrement), M20-E13 (Applications Argo CD).
**Durée indicative** : 3 h.

**Contexte technique**
- Lecture : [Pyrra](https://github.com/pyrra-dev/pyrra) (README de l'étiquette `v0.10.2`, `examples/kubernetes/`), la CRD `ServiceLevelObjective` (`pyrra.dev/v1alpha1`) de la même étiquette, *The Site Reliability Workbook*, chapitre [Implementing SLOs](https://sre.google/workbook/implementing-slos/).
- Pyrra n'a **pas de chart officiel** (le chart communautaire pointe sur une ancienne version) : les manifestes amont (`examples/kubernetes/manifests/`, générés par jsonnet) affichent encore une image v0.9.0 et l'espace `monitoring`. Deux processus : `pyrra kubernetes` (l'opérateur : SLO → `PrometheusRule` du même nom, même espace, mêmes étiquettes) et `pyrra api` (interface et API de lecture, qui interroge un Prometheus — ici Thanos Query, pour la fenêtre de 28 jours).
- L'interface est publiée en lecture seule par la Gateway (`slo.apps.par1.medisphere.internal`, espace `supervision` déjà exposable).
- AppProject `plateforme` : la CRD, le ClusterRole et la liaison de Pyrra sont des objets sans espace déjà autorisés (E02). Pyrra a sa **propre** Application Argo CD : supprimer l'Application des règles ne doit pas supprimer la CRD (et avec elle tous les SLO).
- Objectifs (noms imposés) : **`mediagenda-disponibilite`** (99,5 % sur 28 jours, requêtes de production sans 5xx), **`mediagenda-latence`** (95 % des requêtes de production sous 300 ms… si tu peux le mesurer), **`medidoc-disponibilite`** (objectif à proposer, MédiDoc en recette). Les sondes et `/metrics` ne sont pas des requêtes d'utilisateurs.
- Dans ce palier, **aucune alerte** de SLO avant E27 (pas de routage, pas de politique) : désactive-les explicitement.

**Travail demandé**
1. **Lecture et définition.** Pour chaque objectif : bon événement, événement valide, ce qui est exclu et pourquoi, fenêtre, budget en nombre de requêtes et en durée d'indisponibilité équivalente. Écris-les dans `docs/observabilite/metriques/slo.md` **avant** de toucher au cluster.
2. **Mesurabilité.** Interroge l'histogramme de MédiAgenda : quels seaux (`le`) existent ? Peux-tu compter « moins de 300 ms » ? Décide (et écris) ce que tu mesures en attendant, et ce que tu demandes à l'équipe MédiAgenda (ticket DEV).
3. **Manifestes.** Recopie les manifestes amont de l'étiquette `v0.10.2` dans `plateforme/observabilite/pyrra/` : CRD sans modification, opérateur et API avec leurs écarts commentés (espace, image par le cache `ghcr`, contexte de sécurité *restricted*, ressources, URL de Thanos Query, règles génériques, URL externe pour les alertes), Services, ServiceMonitors, HTTPRoute, politiques d'entrée. Application Argo CD `pyrra` dans `plateforme/gitops` (pourquoi sans finaliseur ?).
4. **Objectifs.** Les trois `ServiceLevelObjective` dans `slo/` (inclus par la racine), alertes désactivées. Vérifie avec `pyrra generate` (même version, sur `adm01` ou dans un conteneur) ce que Pyrra produira, avant la MR.
5. **Règles générées.** Après synchronisation : `kubectl -n supervision get prometheusrules` (propriétaire, étiquettes), groupes chargés dans Prometheus. Lis une règle `…:burnrate1h` et la règle `…:increase4w` : sur quelle période la seconde calcule-t-elle **vraiment**, sachant la rétention locale de Prometheus ? Écris la conséquence dans `slo.md`.
6. **Interface.** Ouvre `https://slo.apps.par1.medisphere.internal` : disponibilité, budget restant, graphiques par fenêtre. Envoie dix minutes de trafic en erreur sur la **recette** (un objectif de recette temporaire, ou des requêtes vers une route qui répond 5xx) pour voir le budget bouger, puis retire l'essai.

**Critères de réussite**
- [ ] `pyrra-kubernetes` et `pyrra-api` (v0.10.x, images par Harbor) sont prêts ; `pyrra-api` interroge Thanos Query ; `https://slo.apps.par1.medisphere.internal` répond.
- [ ] Les trois SLO existent avec leurs objectifs et une fenêtre de 28 jours ; ceux de MédiAgenda portent sur `mediagenda-prod` et excluent les sondes ; celui de latence compte un seau qui **existe**.
- [ ] Pyrra a produit une PrometheusRule par SLO (propriétaire : le SLO), étiquetée pour Prometheus, et ses groupes sont chargés.
- [ ] `slo.md` est sur `main` de `plateforme/medisphere`, avec les définitions et les limites de mesure.

**Vérification** : `lab/bin/check 21 26`

<details><summary>Indice 1</summary>

Un SLI de latence se compte avec un histogramme : les requêtes « rapides » sont celles du seau `le="<seuil>"`, le total est `_count`. `histogram_quantile` interpole entre deux seaux : bien pour un tableau, pas pour compter des requêtes.
</details>

<details><summary>Indice 2</summary>

Les étiquettes du SLO sont recopiées sur la PrometheusRule générée : c'est par là que passe l'étiquette de sélection de Prometheus. Dans la CRD de la v0.10, regarde les champs de `alerting` : l'un d'eux est marqué déprécié.
</details>

**Pour aller plus loin** (facultatif) : un SLI côté Gateway (métriques d'Envoy de Cilium) comparé au SLI de l'application ; un SLO de latence sur histogramme natif (`latencyNative`) ; les tableaux Grafana fournis par Pyrra (règles génériques `pyrra_*`).

---

### M21-E27 — Budgets d'erreur et alertes multi-fenêtres ; Sloth en comparaison  `LAB` `★★★`

> **Ticket PLAT-2227** — *De : Julien Petit* — *Copie : Nadia Roussel, Claire Morel*
> On a des SLO, il faut qu'ils servent. Je ne veux pas être réveillé parce que trois requêtes ont échoué à 3 h du matin, mais je veux l'être si on brûle le budget du mois en une nuit. Et je veux une règle écrite : qu'est-ce qu'on fait quand il ne reste plus de budget ? Karim me dit que Sloth fait la même chose que Pyrra en plus simple : compare et dis-moi.

**Objectifs pédagogiques**
- Comprendre le taux de consommation (*burn rate*) et les alertes multi-fenêtres, multi-facteurs (pourquoi deux fenêtres, pourquoi plusieurs facteurs).
- Brancher les alertes générées sur la politique d'alerte existante (étiquettes `gravite`, `equipe`, runbook) sans modifier le générateur.
- Tester des alertes générées comme des règles écrites à la main.
- Comparer deux générateurs sur le même objectif et rédiger une politique de budget d'erreur.

**Prérequis** : M21-E26, M21-E15 et E16 (alertes, routage par `equipe`, heures ouvrées), M21-E22 (modèle de runbook).
**Durée indicative** : 3 h.

**Contexte technique**
- Lecture : *The Site Reliability Workbook*, [Alerting on SLOs](https://sre.google/workbook/alerting-on-slos/) (en entier, jusqu'à la stratégie 6) ; la fonction `Windows` de `slo/rules.go` de Pyrra v0.10.2 ; [Sloth](https://sloth.dev/) 0.16 (spécification `prometheus/v1`, option `--default-slo-period`).
- Pyrra pose l'étiquette **`severity`** sur ses alertes (valeurs choisies par fenêtre dans le SLO) ; il recopie dans les règles et les alertes les étiquettes et annotations du SLO préfixées **`pyrra.dev/`** (sans le préfixe). Notre routage lit **`gravite`** : la traduction se fait dans Prometheus, au moment de l'envoi des alertes (`alert_relabel_configs`, clé `additionalAlertRelabelConfigs` du chart), sans toucher aux alertes qui portent déjà `gravite`.
- Sloth : CLI seulement (binaire amont vérifié par empreinte, ou conteneur du cache `ghcr`), sur `adm01` ; rien de Sloth n'est appliqué dans le cluster.
- Les alertes de recette ne réveillent jamais personne.

**Travail demandé**
1. **Lecture.** Pour `mediagenda-disponibilite` (99,5 % sur 28 j) : budget, taux de consommation qui épuise le budget en 2 jours, en 4 jours, en 2 semaines. Pourquoi une fenêtre courte **et** une fenêtre longue ? Que se passerait-il avec une seule fenêtre d'1 h ? avec une seule fenêtre de 5 min ? Que donnent les quatre paires de fenêtres de Pyrra pour 28 jours ?
2. **Gravités et équipes.** Active les alertes des trois SLO avec des gravités choisies par fenêtre (justifie : qu'est-ce qui réveille, qu'est-ce qui attend le matin ?), l'équipe, le résumé, la description, le lien vers le runbook. Ajoute la traduction `severity` → `gravite` dans Prometheus. Vérifie le routage (`amtool config routes test`, essais de `alertmanager/routes-tests.txt`).
3. **Tests.** Dans la CI de `plateforme/observabilite` : produire les règles des SLO avec `pyrra generate` (même version que l'opérateur) et les tester avec `promtool test rules` : 8 % d'erreurs pendant une heure déclenchent l'alerte rapide critique, pas avant ; les sondes en erreur ne consomment pas le budget ; l'absence de mesure alerte.
4. **Sloth.** Écris le même objectif pour Sloth (`slo/sloth/`, non appliqué), génère ses règles pour 28 jours, valide-les avec `promtool`. Compare (nombre et nature des règles, fenêtres, facteurs, `for`, étiquettes, calcul de la disponibilité sur la fenêtre, absence de mesure, interface, vie du projet) dans `docs/observabilite/metriques/comparatif-pyrra-sloth.md`, et décide.
5. **Politique de budget d'erreur.** `docs/observabilite/metriques/politique-budget-erreur.md`, à faire valider par Julien Petit (MR) : qui est prévenu à quel rythme de consommation, ce qui se passe selon le budget restant (gel des fonctionnalités : à partir de quand, décidé par qui, avec quelles exceptions), revue périodique, limites connues.
6. **Runbook.** RB-216 « Un budget d'erreur brûle trop vite » : lire l'alerte (`short`, `long`, `exhaustion`), confirmer et localiser par les métriques, agir, après. Puis provoque l'alerte **rapide** sur un objectif de recette temporaire (copie de `medidoc-disponibilite` avec un objectif de 99,99 %, ou erreurs provoquées) et vérifie le courriel ; retire l'essai.

**Critères de réussite**
- [ ] Les trois SLO alertent ; `mediagenda-disponibilite` a sa consommation rapide en `critique` et lente en `avertissement` ; `medidoc-disponibilite` ne réveille jamais ; chaque SLO désigne son équipe et un runbook.
- [ ] Les quatre alertes `ErrorBudgetBurn` de `mediagenda-disponibilite` sont chargées et portent `equipe` ; Prometheus recopie `severity` dans `gravite` ; une alerte critique de MédiAgenda prod part à l'astreinte.
- [ ] La spécification Sloth, les tests des règles de SLO, le comparatif et la politique de budget d'erreur (gel, décideurs) sont sur `main` ; pipeline vert.

**Vérification** : `lab/bin/check 21 27`

<details><summary>Indice 1</summary>

La règle de réétiquetage ne doit s'appliquer qu'aux alertes **sans** `gravite` : avec deux étiquettes sources et un séparateur, une expression régulière peut exiger que la première soit vide (`;…`).
</details>

<details><summary>Indice 2</summary>

`promtool test rules` compare **toutes** les étiquettes et annotations des alertes attendues, et seulement les alertes en état `firing` au moment demandé. Calcule à quel moment chaque paire de fenêtres franchit son seuil avant d'écrire `eval_time`, sinon une autre alerte (plus lente) s'invitera dans le résultat.
</details>

**Pour aller plus loin** (facultatif) : la stratégie 6 du *Workbook* appliquée « à la main » (règles écrites sans générateur) ; OpenSLO comme format d'échange (Sloth sait le lire) ; un tableau Grafana du budget restant par équipe à partir de `pyrra_availability`.

---

### M21-E28 — Superviser la supervision  `LAB` `★★★`

> **Ticket PLAT-2228** — *De : Nadia Roussel* — *Copie : Karim Benali*
> Hier soir, Grafana affichait des courbes plates, toutes vertes. Le pod Prometheus était bloqué depuis 18 h sur un volume plein ; aucune alerte, évidemment, puisque c'est lui qui les fabrique. Je veux être prévenue par **autre chose** quand la supervision du cluster se tait. Et dans l'autre sens : si `mon01` tombe, je veux que le cluster me le dise. Et on l'essaie pour de vrai.

**Objectifs pédagogiques**
- Comprendre le *dead man's switch* : une alerte toujours active (`Watchdog`) dont l'**absence** est le signal, observée depuis un autre domaine de panne.
- Adapter le mécanisme à Thanos Query (pas de `/federate`) : sonde de l'API de requête par blackbox_exporter.
- Mettre en place une surveillance réciproque et un chemin de secours des notifications.
- Éprouver la chaîne par un essai planifié, piloté par le code.

**Prérequis** : M21-E11 et E12 (rôle `supervision_temoin`, fédération), M21-E24, M21-E06 (route `Watchdog`).
**Durée indicative** : 3 h 30.

**Contexte technique**
- `Watchdog` (règle du chart) est toujours en alerte ; sa route d'Alertmanager ne notifie personne (E06). Le PLAN prévoyait que le témoin **fédère** `ALERTS{alertname="Watchdog"}` depuis 10.10.41.60 : depuis E24, 10.10.41.60 est Thanos Query, qui ne sert pas `/federate`. À toi de trouver comment le témoin peut savoir, toutes les minutes, si Thanos Query renvoie encore cette alerte (indice : le témoin a un blackbox_exporter, et l'API de requête renvoie du JSON).
- Noms imposés côté **témoin** (rôle `supervision_temoin`) : jobs `watchdog-cluster` (la sonde de l'alerte Watchdog, une cible, `instance="k8s-par1"`) et `supervision-cluster` (sondes `/-/healthy` et `/-/ready` de 10.10.41.60:9090 et 10.10.41.61:9093, étiquette `composant`) ; alertes **`SupervisionClusterMuette`** et **`SupervisionClusterComposantKO`** (et ce que tu juges utile). Jobs **distincts** du job `blackbox` d'E11, pour ne pas doubler ses alertes.
- Noms imposés côté **cluster** : ScrapeConfig `temoin-mon01` (job `temoin-mon01`, métriques propres du Prometheus témoin, `mon01:9090`), alerte **`TemoinInjoignable`** (qui sonne aussi si la cible disparaît).
- Chemin de secours : Prometheus peut envoyer ses alertes à **plusieurs** Alertmanager (`additionalAlertManagerConfigs`) et filtrer celles qu'il envoie à chacun. Seules les alertes qui disent « l'Alertmanager du cluster ne notifie plus » doivent aussi partir vers l'Alertmanager témoin.
- Flux : `mon01` → 10.10.41.60:9090 et 10.10.41.61:9093 (prévus au PLAN : vérifie qu'ils sont dans ta matrice) ; `K8S_TRAV` → `mon01`:9090 (E12) ; `K8S_TRAV` → `mon01`:9093 (nouveau).
- Essai : arrêter l'Alertmanager du cluster **par le code** (MR qui met ses réplicas à 0, ticket CHG-2228), puis `git revert`. Un `kubectl scale` serait défait par l'opérateur et Argo CD en quelques secondes.

> ⚠️ **Attention** : pendant l'essai, **aucune** alerte du cluster n'est notifiée. Préviens Nadia, fais-le en heures ouvrées, borne-le à 20 minutes, ne lance aucun autre essai en même temps, et prépare le `git revert` avant de fusionner la MR. Si le courriel du témoin n'arrive pas au bout de 10 minutes, annule d'abord, cherche ensuite.

**Travail demandé**
1. **Lecture.** Dans ton journal : ce que prouve la présence de `Watchdog` dans Thanos Query (quels maillons sont vivants ?) et ce qu'elle ne prouve pas (Alertmanager, les courriels) ; pourquoi l'observateur doit être sur un autre domaine de panne ; ce qui reste aveugle quand le cluster **et** `mon01` tombent ensemble.
2. **La sonde Watchdog.** Dans le rôle `supervision_temoin` : un module blackbox qui ne réussit que si la réponse de l'API contient l'alerte `Watchdog`, le job `watchdog-cluster` (attention à l'encodage de la requête PromQL dans la cible), le job `supervision-cluster`. Vérifie à la main depuis `mon01` (`curl 'http://127.0.0.1:9115/probe?module=…&target=…&debug=true'`) : la sonde doit **échouer** sur une requête qui ne renvoie rien.
3. **Les règles du témoin.** `SupervisionClusterMuette`, `SupervisionClusterComposantKO`, et une alerte si la sonde elle-même disparaît. Fichier de règles déployé par le rôle (validé par `promtool`), testé par `promtool test rules` dans la CI de `plateforme/ansible`.
4. **Réciproque.** Côté cluster : ScrapeConfig `temoin-mon01`, alertes `TemoinInjoignable` et sur la santé du témoin (Alertmanager du témoin découvert, envois sans échec, règles sans erreur), tests.
5. **Chemin de secours.** `additionalAlertManagerConfigs` vers l'Alertmanager du témoin, filtré ; flux de la bordure ; vérifie dans la configuration générée de Prometheus (`/api/v1/status/config` sur un pod, par `port-forward`) que deux groupes d'Alertmanager existent et que le second n'accepte que les alertes voulues.
6. **Essai.** CHG-2228 : Alertmanager du cluster à 0 réplica par MR ; chronomètre ; attendu : courriel du **témoin** (`SupervisionClusterComposantKO`, composant `alertmanager`) à `astreinte@` dans Mailpit, et **pas** de `SupervisionClusterMuette` (pourquoi ?). `git revert`, courriel de résolution. Puis, pour la réciproque, arrête le service `prometheus` de `mon01` (`systemctl stop`, 10 minutes) : courriel `TemoinInjoignable` du cluster ; relance-le. Note les délais de détection.
7. **Runbook.** RB-215 « La supervision est muette ou le témoin est aveugle » : principe (schéma), chaque alerte, diagnostic, et la procédure de l'essai trimestriel.

**Critères de réussite**
- [ ] `Watchdog` est active dans le cluster et sa route n'envoie pas de courriel ; Prometheus envoie aussi les alertes `Alertmanager…` à l'Alertmanager témoin.
- [ ] Le cluster collecte le témoin (`up{job="temoin-mon01"} = 1`) et a chargé `TemoinInjoignable` (avec le cas de la cible absente).
- [ ] Le témoin a chargé `SupervisionClusterMuette` et `SupervisionClusterComposantKO` ; sa sonde Watchdog interroge l'API de requête de 10.10.41.60 et réussit ; ses quatre sondes de santé réussissent.
- [ ] Le courriel du témoin de l'essai est dans Mailpit ; l'Alertmanager du cluster est revenu ; RB-215 et les délais mesurés sont sur `main`.

**Vérification** : `lab/bin/check 21 28`

<details><summary>Indice 1</summary>

blackbox_exporter sait juger le **corps** d'une réponse HTTP (`fail_if_body_not_matches_regexp`). Un `200` avec `"result":[]` doit être un échec.
</details>

<details><summary>Indice 2</summary>

La cible d'une sonde est passée à blackbox en paramètre d'URL (`target=`) : Prometheus encode sa valeur, blackbox la décode **une** fois. Écris la requête PromQL déjà encodée dans la cible (`%7B`, `%22`…), et vérifie ce qui arrive vraiment chez Thanos Query (`debug=true`).
</details>

<details><summary>Indice 3</summary>

Pour le chemin de secours : chaque entrée de `alertmanagers` de la configuration de Prometheus accepte ses propres `alert_relabel_configs` ; une action `keep` sur `alertname` suffit.
</details>

**Pour aller plus loin** (facultatif) : un service externe de *dead man's switch* (abonnement hors site qui alerte quand il ne reçoit plus le Watchdog) et ce qu'il couvrirait que le témoin ne couvre pas ; une sonde « canari » volontairement en échec qui prouve que le témoin sait encore alerter.

---

### M21-E29 — Sécuriser la pile de supervision  `LAB` `★★★`

> **Ticket SEC-2229** — *De : Sophie Laurent* — *Copie : Claire Morel*
> J'ai fait le tour de la supervision. Les métriques ne contiennent pas de données de patients — c'est bien — mais elles sont la carte complète de notre infrastructure. Constats : Grafana garde les sessions indéfiniment et accepte les mots de passe faibles ; le compte `admin` a le mot de passe de l'installation ; n'importe quel pod du cluster peut parler à Prometheus et à Alertmanager ; une équipe peut écrire une règle qui lit les métriques de toutes les autres et se faire passer pour une autre ; l'API d'administration de Prometheus, je ne sais pas si elle est ouverte. Je veux un état des lieux corrigé, documenté, avec ce qui reste ouvert et pourquoi.

**Objectifs pédagogiques**
- Durcir Grafana par sa configuration (inscription, anonymes, cookies, sessions, mots de passe, instantanés) et faire tourner le mot de passe d'un compte d'administration correctement.
- Cloisonner un espace de plateforme (refus par défaut en entrée et en sortie, flux listés) sans casser la supervision.
- Ouvrir aux équipes l'écriture de leurs règles, sous garde-fous (espaces choisis, étiquette d'espace imposée, RBAC de lecture).
- Documenter les risques résiduels.

**Prérequis** : M21-E24 à E28, M15-E28 (CiliumNetworkPolicy, refus par défaut, `enableDefaultDeny`), M14-E11 (groupes `medisphere:mediagenda-devs`, `medisphere:medidoc-devs`), M20-E07 (AppProjects), M21-E08 (node_exporter en TLS).
**Durée indicative** : 3 h.

**Contexte technique**
- Grafana 13.2 : lis `conf/defaults.ini` de la version (sections `[security]`, `[users]`, `[auth]`, `[auth.basic]`, `[auth.anonymous]`, `[snapshots]`). Le SSO arrive au M24 (OIDC par Keycloak) : un réglage de cookie trop strict casserait la redirection de retour. Le chart rend `grafana.ini` dans la ConfigMap `kps-grafana` : relis le **rendu**, Helm a des surprises avec les grands nombres.
- Mot de passe `admin` : le Secret `grafana-admin` (E02) ne sert qu'à la **première** initialisation de la base ; changer le Secret ensuite ne change pas le mot de passe enregistré. Grafana 13 a supprimé `grafana-cli`.
- prometheus-operator : champs `enableAdminAPI`, `ruleNamespaceSelector`, `enforcedNamespaceLabel`, `excludedFromEnforcement` du CR Prometheus (et leurs clés dans les values du chart). Lis attentivement **à quoi** s'applique `enforcedNamespaceLabel` : règles, mais aussi séries collectées par les ServiceMonitor, PodMonitor, Probe et ScrapeConfig. Ce qui le rend dangereux pour les objets de la plateforme.
- Règles des équipes : dans leurs dépôts `…/deploiement` (composant `components/supervision`, E07), appliquées par Argo CD dans leurs espaces. Les espaces lus par Prometheus portent une étiquette posée par `plateforme/k8s` (`espaces/`), nom imposé : **`medisphere.internal/supervision-regles: "oui"`**.
- Réseau : refus par défaut **pour tout l'espace** `supervision`, en entrée et en sortie (deux politiques à `endpointSelector: {}` et règle vide) ; les autorisations d'entrée par composant existent déjà en partie (E02, E24, E25, E26) ; Grafana est joint par la Gateway (identité réservée `ingress`, M15) ; les webhooks de l'opérateur sont appelés par le serveur d'API.

> ⚠️ **Attention** : une politique de refus par défaut mal faite rend la supervision **muette** (Prometheus ne collecte plus, Alertmanager n'envoie plus, les PrometheusRule sont refusées par le webhook). (1) Applique d'abord les autorisations, observe Hubble (`hubble observe -n supervision --verdict DROPPED`) **avant** d'ajouter les deux refus par défaut ; (2) garde le témoin (E28) sous les yeux : c'est lui qui te dira si tu as coupé quelque chose ; (3) retour arrière : retirer le dossier des politiques de la kustomization racine (Argo CD les supprime). Pour `enforcedNamespaceLabel` : relis le rendu et liste ce qui sera exempté **avant** la synchronisation ; une erreur réécrit l'étiquette `namespace` de toutes les séries du kubelet.

**Travail demandé**
1. **État des lieux.** Pour chaque constat de Sophie : vérifie-le (commande et résultat dans ton journal). Ajoute ce que tu trouves en plus (API d'administration, accès sans authentification à Prometheus, Thanos Query, Alertmanager depuis MGMT, instantanés publics de Grafana…).
2. **Grafana.** Inscription et anonymes fermés (déjà en E02 : vérifie), cookies réservés à HTTPS, *SameSite* compatible avec le M24, sessions bornées (inactivité et durée maximale), politique de mots de passe, pas d'instantanés publics, pas de Gravatar, en-têtes HSTS et CSP, rôle par défaut `Viewer`. Vérifie le rendu de `grafana.ini` et, sans identifiants, que l'API refuse (`401`).
3. **Rotation d'`admin`.** Écris `outils/grafana-rotation-admin.sh` dans `plateforme/k8s` : ancien mot de passe lu dans le Secret, nouveau lu dans le Vault (déjà mis à jour), changement par l'API de Grafana, vérification (le nouveau marche, l'ancien non), puis Secret réaligné par `secrets-k8s.sh`. Aucun mot de passe sur la ligne de commande ni à l'écran. Fais la rotation.
4. **API d'administration.** Écris explicitement qu'elle est désactivée dans le cluster ; vérifie sur un pod (`port-forward`) qu'un appel à `/api/v1/admin/tsdb/snapshot` est refusé.
5. **Règles par équipe.** Étiquette `supervision-regles` sur `supervision` et les espaces des équipes ; `ruleNamespaceSelector`, `enforcedNamespaceLabel: namespace`, exemptions de la plateforme ; une PrometheusRule d'équipe MédiAgenda dans `mediagenda/deploiement` (deux alertes utiles à l'équipe, vocabulaire commun) ; RoleBindings de **lecture** des règles et moniteurs pour les équipes. Vérifie : la règle chargée a reçu `namespace="mediagenda-prod"` dans ses sélecteurs ; les séries du kubelet ont gardé leur `namespace` ; une règle posée (essai) dans un espace non étiqueté n'est pas chargée.
6. **Cloisonnement réseau.** Dans `plateforme/observabilite/reseau/` : refus par défaut en entrée et en sortie pour tout l'espace, sorties nécessaires (DNS par le proxy de Cilium, API Kubernetes, l'espace lui-même, collecte du cluster et du lab pour Prometheus, SMTP pour Alertmanager, RGW pour Store et Compactor), entrées manquantes (Grafana, kube-state-metrics, opérateur). Après synchronisation : aucune cible de `supervision` en échec, Thanos Query voit tout, une alerte d'essai arrive par courriel, le témoin est vert.
7. **Document.** `docs/observabilite/metriques/securite.md` : risques, mesures et où elles vivent, **limites acceptées** jusqu'au M24 (et ce qui est prévu), et ce qui concerne node_exporter (TLS d'E08 ; authentification ?).

**Critères de réussite**
- [ ] `grafana.ini` (rendu) : inscription et anonymes fermés, cookies sécurisés, politique de mots de passe, instantanés publics interdits, durée de session bornée ; une recherche anonyme reçoit `401`.
- [ ] Le CR Prometheus : API d'administration désactivée, `enforcedNamespaceLabel: namespace` avec les exemptions de la plateforme, `ruleNamespaceSelector` qui sélectionne `supervision` et `mediagenda-prod` ; une règle de `mediagenda-prod` est chargée, bornée à son espace ; `Watchdog` est toujours chargée ; l'équipe MédiAgenda lit ses règles.
- [ ] L'espace `supervision` est en refus par défaut en entrée et en sortie ; Grafana a son entrée depuis la Gateway ; après cloisonnement, Thanos Query voit 2 sidecars et le Store, aucune cible de `supervision` n'est en échec, Alertmanager notifie sans échec.
- [ ] `securite.md` est sur `main` ; le mot de passe `admin` a été changé (auto-évaluation : date au registre des secrets).

**Vérification** : `lab/bin/check 21 29`

<details><summary>Indice 1</summary>

Sous `[security]`, deux clés concernent les cookies ; sous `[auth]`, deux bornent les sessions ; sous `[auth.basic]`, une impose la politique de mots de passe. `strict_transport_security_max_age_seconds` est un **nombre** : écris-le entre guillemets dans les values, sinon relis le rendu.
</details>

<details><summary>Indice 2</summary>

Avec `enforcedNamespaceLabel`, l'opérateur exempte déjà les règles du chart s'il les connaît (regarde le rendu) ; il te reste les autres objets de `supervision` (tes règles, tes ScrapeConfig, les ServiceMonitor du chart — dont celui du kubelet) et ceux de `supervision-noeuds`. Une entrée d'exemption sans `name` couvre tout l'espace pour une ressource.
</details>

<details><summary>Indice 3</summary>

En sortie, Prometheus parle à des centaines de ports différents (kubelet, exportateurs du lab, `mon01`) : filtrer par port à la **source** n'apporte presque rien, le filtrage fin se fait à l'arrivée. Les entités Cilium `cluster` et `kube-apiserver` existent ; un `toCIDR` couvre le lab.
</details>

**Pour aller plus loin** (facultatif) : un proxy d'authentification (oauth2-proxy) devant Prometheus, Thanos Query et Alertmanager (prépare le M24) ; l'authentification par certificat client de node_exporter (`web-config`) et ce qu'elle coûte ; les permissions fines de Grafana (RBAC des dossiers, E17) contrôlées par un test.

---

### M21-E30 — Capacité et performance de Prometheus  `LAB` `★★★`

> **Ticket PLAT-2230** — *De : Karim Benali*
> Combien de séries Prometheus peut-il tenir avant de tomber ? Personne ne sait. Combien de jours tiennent sur son volume ? Personne ne sait non plus, et la `retentionSize` d'E02 a été écrite au doigt mouillé. Le jour où une équipe ajoutera une étiquette avec un identifiant de requête dedans, je veux que ce soit **sa** cible qui tombe, pas Prometheus.
> Mesure, écris le dimensionnement, pose les garde-fous, et alerte avant la saturation.

**Objectifs pédagogiques**
- Mesurer ce qui coûte dans Prometheus : séries actives (mémoire), échantillons par seconde et octets par échantillon (disque), requêtes.
- Appliquer la formule de dimensionnement du disque et en déduire `retention`, `retentionSize` et la taille du volume.
- Poser des garde-fous de collecte et de requête à l'échelle de l'instance (limites imposées) et en comprendre l'effet sur une cible fautive.
- Écrire des alertes de capacité qui préviennent avant la saturation.

**Prérequis** : M21-E24 (deux réplicas, Thanos Query), M21-E14 (cardinalité, `sampleLimit`/`labelLimit` par moniteur), M21-E23 (saturation).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Lecture : [Prometheus — Storage](https://prometheus.io/docs/prometheus/latest/storage/) (*Operational aspects*, formule de capacité, *Right-sizing retention size*), options `--query.max-samples` et `--query.timeout`, `scrape_config` (`sample_limit`, `label_limit`, `label_value_length_limit`, `body_size_limit`) ; dans l'API de prometheus-operator : `enforcedSampleLimit`, `enforcedLabelLimit`, `enforcedLabelValueLengthLimit`, `enforcedBodySizeLimit`, `query` (`QuerySpec`), `retentionSize` ; dans Thanos Query : `--store.limits.request-samples`, `--store.limits.request-series`, `--query.max-concurrent`.
- Métriques de Prometheus lui-même (job `kps-prometheus`, un résultat par réplica) : `prometheus_tsdb_head_series`, `prometheus_tsdb_head_samples_appended_total`, `prometheus_tsdb_compaction_chunk_size_bytes` et `prometheus_tsdb_compaction_chunk_samples` (histogrammes), `prometheus_tsdb_storage_blocks_bytes`, `prometheus_tsdb_size_retentions_total`, `process_resident_memory_bytes`, `scrape_samples_post_metric_relabeling`, `prometheus_target_scrapes_exceeded_sample_limit_total`, `prometheus_engine_query_duration_seconds` (un **résumé**).
- Volume de chaque réplica : 40 Gio (`ceph-rbd`, E02). Rétention locale : 15 jours (PLAN), à garder.
- Noms imposés : `requetes/E30.promql` (une requête par bloc, au format de `requetes/` d'E03-E04), PrometheusRule `capacite-prometheus` avec au moins **`PrometheusSeriesProchesDuBudget`**, **`PrometheusLimiteEchantillonsAtteinte`**, **`PrometheusMemoireProcheLimite`** ; `docs/observabilite/metriques/dimensionnement.md`.

> ⚠️ **Attention** : une `enforcedSampleLimit` trop basse met des cibles légitimes en échec **toutes ensemble** (kube-state-metrics en premier) ; une `query.maxSamples` trop basse casse les tableaux de bord longs. Mesure la plus grosse cible et la requête la plus lourde des tableaux **avant**, et regarde `prometheus_target_scrapes_exceeded_sample_limit_total` juste après la synchronisation. Retour arrière : `git revert`.

**Travail demandé**
1. **Mesures.** Écris `requetes/E30.promql` : séries actives, échantillons par seconde, octets par échantillon sur disque, mémoire par série, pic mémoire sur 7 jours, espace disque projeté pour 15 jours, taille des blocs, les 10 cibles les plus lourdes, les 10 métriques qui ont le plus de séries, durée des collectes, durée des requêtes. Relève les valeurs sur 7 jours (ou depuis E24).
2. **Disque.** Applique la formule : combien d'octets pour 15 jours ? Avec le WAL et une marge, la `retentionSize` d'E02 et le volume de 40 Gio sont-ils justes ? Et le compartiment Thanos et le quota RGW de 40 Gio (E24) ?
3. **Mémoire.** Mémoire par série mesurée → budget de séries pour la limite du conteneur ; demande et limite de mémoire justifiées (pourquoi la demande égale au pic ? pourquoi une limite au-dessus ?). Deux réplicas : quelle part du profil de 100 Go ?
4. **Garde-fous.** Dans `kps/values.yaml` : rétention en taille révisée, limites imposées de collecte (échantillons, étiquettes, longueur des valeurs, taille de réponse), limites de requêtes ; dans `thanos-query` : limites par point d'accès. Synchronise, puis vérifie qu'aucune cible n'est refusée.
5. **Essai.** Dans `wb-essais`, fais collecter (PodMonitor temporaire, étiquette de sélection) un pod qui expose plus d'échantillons que la limite (par exemple l'image `agnhost` du cache `k8s`, ou un petit serveur qui sert un fichier de métriques généré) : constate l'état de la cible, le message, et les compteurs. Retire l'essai.
6. **Alertes de capacité.** `regles/capacite-prometheus.yaml` : séries proches du budget, limite d'échantillons atteinte, mémoire proche de la limite, rétention par taille déclenchée, volume presque plein ; tests `promtool`.
7. **Dimensionnement.** `dimensionnement.md` : mesures, calculs, choix et leurs raisons, et la question du ticket E26 : avec 15 jours en local, que vaut la disponibilité « 28 jours » des SLO ? Options et décision.

**Critères de réussite**
- [ ] Le CR Prometheus a une `retentionSize` sous la taille du volume, des limites imposées d'échantillons et d'étiquettes, des limites de requêtes, une demande et une limite de mémoire ; Thanos Query borne ses lectures par point d'accès.
- [ ] Aucune cible refusée pour dépassement depuis une heure ; les trois alertes de capacité imposées sont chargées.
- [ ] `requetes/E30.promql` contient au moins six requêtes de mesure, toutes valides ; `dimensionnement.md` (séries, mémoire, disque, rétention) est sur `main`.

**Vérification** : `lab/bin/check 21 30`

<details><summary>Indice 1</summary>

Octets par échantillon : le rapport des sommes de deux histogrammes de compaction (`…_chunk_size_bytes_sum` / `…_chunk_samples_sum`) sur une journée. Mémoire par série : la mémoire résidente divisée par les séries actives, **par pod** (`on (pod)`).
</details>

<details><summary>Indice 2</summary>

Une cible qui dépasse `sample_limit` n'est pas « tronquée » : la collecte entière échoue (`up = 0`) et rien de cette collecte n'est gardé. C'est voulu.
</details>

**Pour aller plus loin** (facultatif) : la répartition (*sharding*, `shards: 2`) et ses conséquences sur les règles ; `promtool tsdb analyze` sur une copie de la base (le témoin, M21-E44) ; Thanos Query Frontend pour les tableaux longs.

---

### M21-E31 — ADR : l'architecture de supervision de MédiSphère  `RED` `★★`

> **Ticket PLAT-2231** — *De : Claire Morel*
> Le comité d'architecture veut une décision écrite, pas un état de fait : pourquoi kube-prometheus-stack et Thanos, pourquoi pas Mimir ou VictoriaMetrics dont tout le monde parle, pourquoi le RGW, pourquoi une machine à part pour surveiller la supervision. Et ce que cette décision nous coûte.

**Objectifs pédagogiques**
- Rédiger un ADR qui compare de vraies options sur des critères pondérés par le contexte (lab, équipe, conformité), avec les conséquences négatives.
- Relier les choix techniques du module aux exigences (HDS, souveraineté, durée de conservation, astreinte).

**Prérequis** : M21-E24 à E30 ; ADR-0200 (modèle, M20-E31).
**Durée indicative** : 1 h 30.

**Travail demandé**
Rédige `docs/observabilite/metriques/adr/ADR-0210-architecture-supervision.md` (format des ADR du dépôt) :
1. **Contexte** : l'incident d'origine, les exigences (symptômes, SLO, 2 ans, souveraineté, code et GitOps), les contraintes du lab et de l'équipe, ce qu'il faut superviser (dont ce qui est hors du cluster).
2. **Options** : au moins kube-prometheus-stack + Thanos (sidecar), Grafana Mimir 3, VictoriaMetrics (cluster), et un Prometheus seul sur VM. Critères : composants à exploiter, mémoire dans le lab, conservation longue et stockage objet, haute disponibilité, compatibilité Prometheus (PromQL, CRD de l'opérateur), intégration GitOps des équipes, licence, compétences, disponibilité des images et charts. Vérifie toi-même ce qui a changé récemment (Mimir 3 et Kafka, le catalogue Bitnami, annexe des versions du bloc E).
3. **Décision** et **justification**, y compris le stockage (RGW plutôt que `s3-01`), la supervision témoin, Pyrra, la place de la configuration (`plateforme/observabilite`, dépôts des équipes).
4. **Conséquences** : positives, et **négatives avec leur action** (double collecte, Thanos Query sans `/federate`, rétention locale et SLO, un seul Compactor, absence d'authentification jusqu'au M24, domaine de panne commun de `mon01` et du cluster, dépendance au RGW, montées de version).
5. **Conditions de révision** (chiffrées quand c'est possible).

**Critères de réussite**
- [ ] L'ADR est sur `main` de `plateforme/medisphere` (MR relue par un pair), avec au moins quatre options comparées sur au moins six critères.
- [ ] Chaque conséquence négative a une action ou une acceptation explicite ; les conditions de révision sont observables.

**Pour aller plus loin** (facultatif) : une annexe chiffrée (mémoire mesurée de chaque option dans un essai jetable) ; la place d'OpenTelemetry dans les métriques (M23) et ce qu'elle changerait.

---

### M21-E32 — Politique d'alerte et d'astreinte  `RED` `★★`

> **Ticket PLAT-2232** — *De : Nadia Roussel* — *Copie : Claire Morel, Julien Petit*
> Je prends l'astreinte le mois prochain. Avant, je veux un document que tout le monde a signé : ce qui me réveille et ce qui ne me réveille pas, qui fait quoi la nuit, quand j'appelle qui, comment on pose un silence, et comment on se débarrasse des alertes inutiles. Sinon dans trois mois je ne lirai plus mes courriels.

**Objectifs pédagogiques**
- Formaliser une politique d'alerte : gravités et leurs conséquences, propriétaires, horaires, escalade, silences, revue.
- Relier la politique à la configuration réelle (étiquettes, routes, intervalles, inhibitions) et à la politique de budget d'erreur.

**Prérequis** : M21-E15, E16, E22, E27, E28.
**Durée indicative** : 1 h 30.

**Travail demandé**
Rédige `docs/observabilite/metriques/politique-alerte.md` :
1. **Principes** : ce qui justifie une alerte qui réveille ; symptômes et causes ; propriétaire et runbook obligatoires ; tests.
2. **Gravités** (`critique`, `avertissement`, `info`) : signification, notification, délai de prise en compte, exemples **pris dans tes règles**.
3. **Qui est réveillé** : par équipe, heures ouvrées et nuit, environnements hors production.
4. **Regroupement, répétition, silences, inhibitions** : valeurs de ta configuration et règles d'usage (durée maximale d'un silence, auteur, commentaire, alertes qu'on ne fait jamais taire).
5. **Astreinte** : rotation, passation, droits, **escalade** (délais, personnes, cas de sécurité).
6. **Liste de contrôle** d'une MR qui ajoute une alerte.
7. **Revue** périodique des alertes : indicateurs, décisions possibles, objectif chiffré de bruit.

**Critères de réussite**
- [ ] La politique est sur `main` de `plateforme/medisphere`, validée par MR (relecteurs : Nadia, Julien, Claire).
- [ ] Chaque gravité est illustrée par des alertes qui **existent** dans tes dépôts ; les valeurs citées (intervalles, horaires) sont celles de ta configuration.

---

### M21-E33 — Questions de production : supervision  `Q` `★★★`

> *De : Karim Benali* — Avant de te laisser la supervision en production, quelques questions que je pose aux candidats. Réponds sans relire le module, puis vérifie.

1. Deux réplicas de Prometheus collectent les mêmes cibles. Donne trois raisons pour lesquelles leurs séries ne sont **pas** identiques échantillon par échantillon, et ce que cela implique pour le dédoublonnage.
2. Thanos Query renvoie une réponse avec un avertissement « partial response ». Que s'est-il passé, que vaut la réponse, et quand préférerait-on une erreur ?
3. Un collègue propose de réduire la rétention locale de Prometheus à 6 heures « puisque Thanos garde tout ». Qu'est-ce qui casse ou se dégrade ?
4. Le Compactor est en `halted` depuis trois jours. Quelles données sont en danger, lesquelles ne le sont pas, et quelle est la pire réaction possible ?
5. Pourquoi une alerte sur le seul taux d'erreurs des 5 dernières minutes est-elle une mauvaise alerte de SLO ? Et une alerte sur 30 jours ?
6. Le budget d'erreur de MédiAgenda est épuisé le 10 du mois à cause d'une panne du RGW (stockage). Le gel des fonctionnalités s'applique-t-il ? Argumente avec la politique.
7. `Watchdog` est présente dans Thanos Query, mais personne n'a reçu de courriel depuis deux jours alors que des alertes sont actives. Quels maillons sont prouvés vivants, lesquels sont suspects, et comment le témoin aurait-il dû le voir ?
8. Une équipe veut une alerte « pod redémarré » qui réveille l'astreinte. Que réponds-tu, et que proposes-tu à la place ?
9. Explique pourquoi `enforcedNamespaceLabel` ne protège pas contre une équipe qui écrit `equipe: plateforme` dans ses alertes, et ce qui pourrait le faire.
10. Prometheus est `OOMKilled` en boucle après le déploiement d'une nouvelle version d'une application. Ton plan, dans l'ordre, pour rétablir la supervision **puis** traiter la cause.
11. Pourquoi `histogram_quantile` ne convient-il pas pour calculer un SLO de latence, alors qu'il convient pour un tableau de bord ?
12. Un auditeur HDS demande la preuve de la disponibilité de MédiAgenda sur les 18 derniers mois. Que peux-tu fournir, avec quelle résolution, et quelle confiance accorder au chiffre ?
13. Quelle est la différence entre une alerte inhibée, une alerte réduite au silence et une alerte routée vers un récepteur sans intégration ? Donne un usage légitime de chacune.

**Durée indicative** : 1 h.

---

### M21-E34 — Un diagnostic en temps limité  `CHRONO` `★★★`

> **Incident INC-4834** — *De : Nadia Roussel*
> Les testeurs de la recette se plaignent : MédiAgenda est lente, certaines prises de rendez-vous n'aboutissent pas. Personne n'a rien déployé. Tu as une heure, et aujourd'hui, règle du jeu : **les métriques seulement**. Je veux le symptôme chiffré, la cause prouvée, l'action et ce qui aurait dû nous prévenir.

**Objectifs pédagogiques**
- Mener un diagnostic complet sous contrainte de temps avec les seuls outils de supervision construits dans le module.
- Prouver une cause par des requêtes (pas par une intuition) et la distinguer de ses conséquences.
- Écrire un journal exploitable par un collègue.

**Règles de l'exercice**
- Conditions d'examen : pas de corrigé. Tes runbooks, tes tableaux de bord, tes requêtes enregistrées, la documentation officielle sont permis.
- **Interdits jusqu'à ce que la cause soit écrite dans le journal** : `kubectl logs`, `describe`, `exec`, `port-forward`, SSH, `psql`, la lecture du script d'injection. Permis : Grafana, Thanos Query (10.10.41.60), Alertmanager, Pyrra, `kubectl get` des objets de **supervision** seulement (pour lire une règle). Ensuite seulement, l'action corrective (avec les outils que tu veux, en respectant GitOps).
- Durée : **60 min** entre l'injection (T0) et la cause écrite avec ses preuves ; 15 min de plus pour l'action et la prévention.

**Prérequis** : paliers 1 à 3 du module, en particulier E07 (métriques de MédiAgenda et de PostgreSQL), E19 (tableaux RED et USE), E23 (saturation), E24 (Thanos Query).
**Durée** : 1 h 15 chronométrées + 30 minutes de retour d'expérience.

**Injection** : `lab/bin/break 21 34` (le scénario dure au plus 75 minutes puis s'arrête seul ; `lab/bin/break 21 34 --annuler` le termine). Le symptôme s'affiche : c'est T0.

**Journal** : recopie [`ressources/E34-diagnostic/journal-modele.md`](../ressources/E34-diagnostic/journal-modele.md) dans `plateforme/medisphere`, `docs/kubernetes/journal/<AAAA-MM-JJ>-M21-E34-inc-4834.md`, et remplis-le au fil de l'eau (heure de chaque étape).

**Critères de réussite**
- [ ] Le journal est sur `main` de `plateforme/medisphere` : symptôme chiffré, chronologie horodatée (au moins quatre étapes), au moins quatre requêtes PromQL citées avec leurs valeurs, cause racine prouvée, action et prévention.
- [ ] La cause racine identifiée est la bonne (le check la compare au scénario injecté).
- [ ] Le service est revenu à la normale : la cause est neutralisée et la latence p95 de la recette est revenue sous 500 ms.
- [ ] Le retour d'expérience (section 7 du journal) dit ce qui t'a fait perdre du temps et la requête que tu aurais voulu avoir déjà enregistrée ; ajoute-la à `plateforme/observabilite` (règle d'enregistrement ou tableau).

**Vérification** : `lab/bin/check 21 34` (à lancer à la fin, après l'action corrective)

**Pour aller plus loin** (facultatif) : refais l'exercice une semaine plus tard (l'autre scénario sort peut-être) en visant 30 minutes ; écris l'alerte qui aurait prévenu Nadia avant les testeurs, et son test.
