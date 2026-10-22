# Module 21 — Palier 3 : Production — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Validé hors lab pour ce corrigé** : rendu du chart kube-prometheus-stack **92.11.0** (Helm 4.3.1) avec les values d'E02/E06 et les extraits de E24, E27, E28, E29, E30 fusionnés, puis `kubeconform` 0.8.0 (schémas Kubernetes et schémas tirés des CRD exactes de prometheus-operator 0.94.1 et de Pyrra 0.10.2 ; Cilium et Gateway API par le catalogue de schémas) ; `kustomize build` 5.8.1 des dossiers `thanos/`, `slo/`, `reseau/`, `regles/`, `scrape/` et `pyrra/` ; **Thanos 0.42.4** : démarrage réel de `query` (fichier de points d'accès), `store` et `compact` avec les options de ce corrigé et une configuration `objstore` produite par les scripts ; `promtool` 3.15.1 : `check rules`, `check config` (réétiquetage des alertes, Alertmanager témoin, jobs du témoin) et **tous** les tests `promtool test rules` de ce palier ; **Pyrra 0.10.2** (`pyrra generate`, compilé depuis l'étiquette) sur les trois SLO, règles générées testées ; **Sloth 0.16.0** (`sloth generate --default-slo-period=28d`) ; **blackbox_exporter 0.29.1** (`--config.check`, puis sonde réelle contre un Thanos Query 0.42.4 local : la requête encodée arrive intacte, la sonde échoue sur un résultat vide) ; `shellcheck -x` et `bash -n` de tous les scripts ; les checks rejoués sur un banc à fonctions simulées (cas sain et cas d'avant le palier).

**Points non testés en conditions réelles** (signale tes retours, ils corrigent le workbook) :
- le comportement du mode de compaction « retardée » de prometheus-operator 0.94 avec Thanos 0.42.4 (`--storage.tsdb.delay-compact-file.path` côté Prometheus, `--shipper.ignore-unequal-block-size` et `--shipper.meta-file-name` côté sidecar) : lu dans le code de l'opérateur, pas observé sur un cluster ; l'option du sidecar est **cachée** en 0.42.4 mais existe (elle n'est retirée que de Receive : l'annexe des versions du bloc E le dit trop largement) ;
- l'accès des pods au RGW par `eth1` pour les sidecars, le Store et le Compactor (même chemin que MédiDoc au M16) et le style d'adressage par chemin avec le RGW Tentacle ;
- la commande `radosgw-admin quota set --quota-scope=user` sur Tentacle 20.2.4 et la sortie JSON de `radosgw-admin user info` (`max_buckets`, `user_quota`) lues par le check ;
- `/api/v1/stores` de Thanos Query (forme de la réponse lue dans le code 0.42.4) et le dédoublonnage des règles par l'API `rules` à travers deux sidecars ;
- l'API `PUT /api/user/password` de Grafana 13.2 (dépréciation progressive de `/api` au profit de `/apis`) utilisée par le script de rotation ;
- l'identité Cilium vue pour les appels de webhooks du serveur d'API vers l'opérateur (`kube-apiserver`, ou `host`/`remote-node` selon la configuration de Cilium du M15 : la politique autorise les trois) ;
- les métriques `cnpg_backends_total{application_name}` et `cnpg_backends_waiting_total` de CloudNativePG 1.30 (requêtes par défaut, lues dans `default-monitoring.yaml`) et le comportement de MédiAgenda quand un verrou bloque ses écritures (épuisement des fils de travail) dans le scénario 2 d'E34 ;
- le nom du ConfigMap de configuration de Grafana (`kps-grafana`) et de sa source (`kps-grafana-datasource`) lus par les checks (rendu du chart, pas un cluster) ;
- la compatibilité de busybox (`date -d @…`, `$RANDOM`) dans l'image `curlimages/curl:8.22.0` utilisée par l'injection d'E34.

**Faits que ce palier fixe pour la suite** : CR Prometheus `kps` à 2 réplicas, sidecar Thanos 0.42.4 ; 10.10.41.60 = Thanos Query ; Services `thanos-query`, `thanos-store`, `thanos-compactor` ; Secret `thanos-objstore` ; utilisateur RGW `thanos`, compartiment `thanos-k8s-par1` ; Application Argo CD `pyrra` ; SLO `mediagenda-disponibilite`, `mediagenda-latence` (seuil **250 ms**, faute de seau 0.3), `medidoc-disponibilite` (recette) ; étiquette d'espace `medisphere.internal/supervision-regles: "oui"` ; alertes `Thanos*`, `ErrorBudgetBurn`/`SLOMetricAbsent` (Pyrra), `Temoin*` (cluster), `SupervisionCluster*` (témoin), `Prometheus*` (capacité) ; RB-214, RB-215, RB-216.

Fichiers de solution : `corrige/fichiers/M21-E24/` à `M21-E32/` ; script d'injection d'E34 : `corrige/pannes/break-E34.sh`. Les fichiers `*.extrait` ne montrent que ce qui change dans un fichier existant d'un autre exercice.

---

### M21-E24 — Prometheus redondant et Thanos sur le RGW

**Solution**

Fichiers : [`ceph/thanos-rgw.sh`](fichiers/M21-E24/ceph/thanos-rgw.sh) (utilisateur, quota, compartiment), [`adm01/s3-thanos.env.exemple`](fichiers/M21-E24/adm01/s3-thanos.env.exemple), [`k8s/outils/secrets-k8s.d/thanos.sh`](fichiers/M21-E24/k8s/outils/secrets-k8s.d/thanos.sh) et [`k8s/secrets/thanos.yml.exemple`](fichiers/M21-E24/k8s/secrets/thanos.yml.exemple) ; dans `plateforme/observabilite` : [`kps/values.yaml.extrait`](fichiers/M21-E24/observabilite/kps/values.yaml.extrait), [`thanos/`](fichiers/M21-E24/observabilite/thanos/) (Query, Store, ServiceMonitors, politiques), [`kustomization.yaml.extrait`](fichiers/M21-E24/observabilite/kustomization.yaml.extrait) ; documentation : [`thanos.md`](fichiers/M21-E24/medisphere/docs/observabilite/metriques/thanos.md).

*1. Lecture* (réponses attendues) :
- Un bloc de 2 h est un répertoire immuable (index, morceaux compressés, `meta.json`) que Prometheus écrit quand la **tête** (mémoire + WAL) a couvert 2 h ; avant, les données ne sont que dans le WAL. Le sidecar n'envoie que des blocs fermés (immuables) : il surveille le répertoire de la base et envoie chaque nouveau bloc. Conséquence : le compartiment a 2 à 3 h de retard sur le temps réel ; les dernières heures ne sont servies que par les sidecars.
- La **StoreAPI** est l'interface gRPC (« donne-moi les séries qui correspondent à ces sélecteurs entre t1 et t2 ») que parlent le sidecar (sur la base locale, par l'API de lecture distante de Prometheus), le Store Gateway (sur le compartiment), Receive, Ruler et Query lui-même. Thanos Query est un client StoreAPI qui fusionne.
- Les deux réplicas ont des étiquettes externes identiques **sauf** `prometheus_replica` (posée par l'opérateur : `prometheus-kps-0` / `-1`). Avec `--query.replica-label=prometheus_replica`, Query retire cette étiquette et fusionne les séries devenues identiques (algorithme « penalty » : il suit un réplica et ne bascule sur l'autre qu'en cas de trou). Sans elle : chaque série deux fois, des `sum()` doublés, des taux d'erreurs faux.
- Les alertes : l'opérateur ajoute `alert_relabel_configs: [{action: labeldrop, regex: prometheus_replica}]` en tête de l'envoi ; les deux réplicas envoient **la même** alerte (mêmes étiquettes), qu'Alertmanager dédoublonne (empreinte des étiquettes).
- Points uniques restants : le compartiment (RGW, `ceph-par1`), Alertmanager (1 réplica), le Compactor (par construction, E25), et chaque **cible** (les deux réplicas collectent la même).

*2. Stockage objet* : [`thanos-rgw.sh`](fichiers/M21-E24/ceph/thanos-rgw.sh), lancé depuis `adm01` :

```
admin@adm01:~/src/ceph$ outils/thanos-rgw.sh
utilisateur RGW thanos créé ; identifiants dans /home/admin/.config/workbook/s3-thanos.env (600)
compartiment thanos-k8s-par1 créé
contrôles : liste autorisée, second compartiment refusé (max-buckets=1)
{ "user_id": "thanos", "max_buckets": 1, "user_quota": { "enabled": true, "check_on_raw": false, "max_size": 42949672960, … } }
```

Les gestes clés : `radosgw-admin user create --uid=thanos --max-buckets=1` dont la sortie va **directement** dans `jq`, puis dans un fichier temporaire 600 (jamais l'écran) ; `radosgw-admin quota set --quota-scope=user --uid=thanos --max-size=40G` puis `quota enable` ; compartiment créé **avec les identifiants de `thanos`** (il en est propriétaire) ; vérification inverse (un second `create-bucket` échoue). Puis la paire dans le Vault (`ansible-vault edit … secrets/thanos.yml`, modèle fourni) et au registre des secrets. Pourquoi un utilisateur « classique » et pas un compte IAM (M08-E12) : un composant, un compartiment, aucune délégation à faire ; le compte apporterait un utilisateur racine et des politiques IAM sans usage ici.

*3. Secret* : module [`secrets-k8s.d/thanos.sh`](fichiers/M21-E24/k8s/outils/secrets-k8s.d/thanos.sh) (fonctions `secrets_thanos_appliquer` et `secrets_thanos_verifier`, sur le modèle d'`argocd.sh` du M20 : la table `secrets-k8s.conf` ne sait pas décrire un document construit) : `yq -n` construit `objstore.yml` en mémoire à partir du Vault déchiffré, passé à `kubectl create secret … --from-file=objstore.yml=<(…) --dry-run=client -o yaml | kubectl apply --server-side -f -`. `outils/secrets-k8s.sh appliquer thanos`, puis `verifier thanos` (comparaison par empreintes). Contrôle : `kubectl -n supervision get secret thanos-objstore -o jsonpath='{.data}' | jq 'keys'` → `["objstore.yml"]` (les clés, pas les valeurs).

*4. Prometheus ×2 et sidecar* ([extrait des values](fichiers/M21-E24/observabilite/kps/values.yaml.extrait)) : `replicas: 2`, `podAntiAffinity: hard`, `thanosService.enabled`, `thanosServiceMonitor.enabled`, `prometheusSpec.thanos` (image et version explicites, `objectStorageConfig.existingSecret`, `volumeMounts` de la CA), `prometheusSpec.volumes` (ConfigMap `racine-medisphere`). Après synchronisation :

```
admin@adm01:~$ kubectl -n supervision get pods -l app.kubernetes.io/name=prometheus -o wide
NAME               READY   STATUS    RESTARTS   AGE   IP            NODE
prometheus-kps-0   3/3     Running   0          6m    10.0.1.84     k8s-w01
prometheus-kps-1   3/3     Running   0          5m    10.0.2.17     k8s-w02
admin@adm01:~$ kubectl -n supervision get sts prometheus-kps -o json \
    | jq -r '.spec.template.spec.containers[] | select(.name=="thanos-sidecar" or .name=="prometheus") | .name, (.args[] | select(test("tsdb|shipper|objstore")))'
```

Tu dois lire, côté `prometheus`, `--storage.tsdb.delay-compact-file.path=/prometheus/thanos.shipper.json` (et **pas** `--storage.tsdb.min-block-duration=2h`) et, côté `thanos-sidecar`, `--objstore.config=$(OBJSTORE_CONFIG)`, `--shipper.meta-file-name=…`, `--shipper.ignore-unequal-block-size` : c'est le mode de compaction retardée de l'opérateur 0.94 (Prometheus ≥ 3.9, Thanos ≥ 0.42). Si tu forces `disableCompaction: true`, il revient à l'ancien mode (blocs de 2 h seulement en local).

Trois conteneurs par pod : `prometheus`, `config-reloader`, `thanos-sidecar`. Deux à trois heures plus tard :

```
admin@adm01:~$ (set -a; . ~/.config/workbook/s3-thanos.env; set +a; aws s3 ls s3://thanos-k8s-par1/)
                           PRE 01M5KNGGR0K3M2N1P0Q9R8S7T6/
                           PRE 01M5KNGH40C1D2E3F4G5H6J7K8/
admin@adm01:~$ (set -a; . ~/.config/workbook/s3-thanos.env; set +a; aws s3 cp s3://thanos-k8s-par1/01M5KNGGR0K3M2N1P0Q9R8S7T6/meta.json - | jq .thanos.labels)
{ "cluster": "k8s-par1", "prometheus": "supervision/kps", "prometheus_replica": "prometheus-kps-0", "site": "par1" }
```

*5. Query et Store* : [`thanos-query.yaml`](fichiers/M21-E24/observabilite/thanos/thanos-query.yaml) (ConfigMap `thanos-query-points` lue par `--endpoint.sd-config-file`, deux adresses `dnssrv+_grpc._tcp…`, `--query.replica-label=prometheus_replica`, `--query.auto-downsampling`, `--query.partial-response`, PDB `minAvailable: 1`), [`thanos-store.yaml`](fichiers/M21-E24/observabilite/thanos/thanos-store.yaml) (`--index-cache-size=128MB`, `--chunk-pool-size=256MB` au lieu des 250 Mo et 2 Go par défaut, volume de cache de 10 Gio, sonde de disponibilité patiente au démarrage), [`servicemonitors.yaml`](fichiers/M21-E24/observabilite/thanos/servicemonitors.yaml), [`politiques.yaml`](fichiers/M21-E24/observabilite/thanos/politiques.yaml). Tous en `runAsNonRoot` (65534), système de fichiers en lecture seule, sans jeton d'API Kubernetes (la découverte passe par le DNS). L'image est réécrite par la kustomization (`images:`) : une seule version à changer.

*6. Bascule* : le Service `prometheus-externe` change de sélecteur (`app.kubernetes.io/name: thanos-query`) et de port cible (`http`, 10902) ; `prometheus-entree` ouvre 10901 et 10902 à l'espace `supervision` et 9090 à `argo-rollouts` (analyses d'E18 sur `kps-prometheus`), et **ferme** MGMT et `mon01` (ils passent par Thanos Query). La source Grafana garde l'uid `prometheus`, change d'URL (`http://thanos-query.supervision.svc.cluster.local:9090/`) et déclare `prometheusType: Thanos`.

```
admin@adm01:~$ curl -s http://prometheus.apps.par1.medisphere.internal:9090/api/v1/stores \
    | jq '.data | map_values(map({name, lastError}))'
{ "sidecar": [ {"name": "10.0.1.84:10901", "lastError": null}, {"name": "10.0.2.17:10901", "lastError": null} ],
  "store":   [ {"name": "10.0.3.41:10901", "lastError": null} ] }
admin@adm01:~$ q='count(count by (prometheus_replica) (up{job="kps-prometheus"}))'
admin@adm01:~$ curl -s -G http://prometheus.apps.par1.medisphere.internal:9090/api/v1/query --data-urlencode "query=$q" | jq -r '.data.result[0].value[1]'
1
admin@adm01:~$ curl -s -G http://prometheus.apps.par1.medisphere.internal:9090/api/v1/query --data-urlencode "query=$q" -d dedup=false | jq -r '.data.result[0].value[1]'
2
```

Avec le dédoublonnage (défaut), l'étiquette de réplica disparaît : une seule valeur ; sans, les deux réplicas apparaissent.

*7. Épreuve* : pendant le redémarrage de `prometheus-kps-0`, la courbe de Grafana n'a pas de trou (Query sert les données de `-1`) ; avec `dedup=false` et `prometheus_replica="prometheus-kps-0"`, un trou de 1 à 3 min (arrêt, relecture du WAL). Ce qui est perdu : les échantillons que `-0` n'a pas collectés pendant son arrêt, **dans sa propre base** (et donc dans ses blocs envoyés) ; rien n'est perdu pour la lecture dédoublonnée, ni pour les alertes (`-1` évaluait).

*8. Documentation* : [`thanos.md`](fichiers/M21-E24/medisphere/docs/observabilite/metriques/thanos.md). Flux : aucun nouveau flux de la bordure (RGW par `eth1` depuis M16, MGMT et `mon01` vers 10.10.41.60 inchangés) ; dans la matrice du cluster : Query → sidecars et Store (10901), Prometheus → Thanos (10902), pods → RGW.

**Explications**

Thanos ne remplace pas Prometheus : il lui ajoute une lecture globale (Query) et une mémoire longue (blocs dans le stockage objet, servis par le Store). La redondance vient de deux Prometheus **indépendants** qui ne se parlent pas ; la cohérence est reconstruite à la lecture (dédoublonnage) et dans Alertmanager. C'est simple et robuste, au prix d'une double collecte. Les étiquettes externes sont la clé de tout : elles identifient la source de chaque bloc pour Query, le Compactor et Alertmanager. Changer une étiquette externe plus tard crée un **nouveau flux** de blocs aux yeux du Compactor (il ne les fusionnera pas avec les anciens).

**Alternatives**
- **Thanos Receive** (Prometheus écrit en *remote write* vers Receive, qui envoie les blocs) : utile quand les Prometheus sont éphémères ou loin ; plus de composants, de la réplication à configurer, pas de lecture des dernières heures sans Receive.
- **Remote write vers Mimir ou VictoriaMetrics** : écarté par l'ADR-0210 (E31).
- **Un seul Prometheus avec un volume répliqué** : ne couvre pas la panne du processus ni les redémarrages, qui sont la cause du ticket.
- **Stockage sur `s3-01`** (SeaweedFS) : possible techniquement ; écarté pour ne pas mélanger les métriques avec les états OpenTofu et les sauvegardes sur une seule VM (ADR-0210).

**Pièges classiques**
- Monter la CA dans le conteneur `prometheus` (par `prometheusSpec.volumeMounts` ou `configMaps`) et pas dans `thanos-sidecar` : le sidecar échoue en `x509`.
- Utiliser `--endpoint` (déprécié) ou répéter une option de Thanos : refus de démarrer, message noyé dans l'aide affichée.
- Oublier d'ouvrir 10901 dans la politique d'E02 : Query ne voit aucun sidecar, `lastError: … i/o timeout`.
- Style d'adressage virtuel : le client cherche `thanos-k8s-par1.rgw.par1.medisphere.internal`, inconnu du DNS.
- Changer l'uid de la source Grafana : tous les tableaux qui la désignent par uid deviennent vides (c'est une variante de M21-E37).
- Versionnage ou règle de cycle de vie sur le compartiment : le premier remplit le quota de versions cachées, la seconde supprime des blocs que le Compactor croit présents (« halted »).
- Croire que 10.10.41.60 « est encore Prometheus » : `/federate` et `/api/v1/status/config` y répondent 404. La fédération d'E12 n'est pas touchée (c'est le cluster qui lit `mon01:9090/federate`) ; en revanche, tout ce que le témoin lit sur 10.10.41.60 doit passer par l'API de requête (c'est l'objet d'E28).

**En production chez MédiSphère**
Compartiment répliqué hors site (RGW multisite vers PAR2, F5) ; Thanos Query Frontend devant Query (cache des requêtes longues, découpage par jour) ; deux Alertmanager en grappe ; alertes de E25 ; quotas RGW suivis (`radosgw-admin user stats`) et inscrits au plan de capacité de `ceph-par1` ; montée de version de Thanos **simultanée** pour le sidecar (values) et les composants (kustomization), testée sur une copie du compartiment.

---

### M21-E25 — Thanos : vue globale, compaction, sous-échantillonnage, rétention

**Solution**

Fichiers : [`thanos/thanos-compactor.yaml`](fichiers/M21-E25/observabilite/thanos/thanos-compactor.yaml), kustomization, ServiceMonitors et politiques complétés ([`thanos/`](fichiers/M21-E25/observabilite/thanos/)) ; [`regles/thanos.yaml`](fichiers/M21-E25/observabilite/regles/thanos.yaml) et ses [tests](fichiers/M21-E25/observabilite/tests/thanos.test.yaml) ; [`outils/objstore-local.sh`](fichiers/M21-E25/observabilite/outils/objstore-local.sh) ; [RB-214](fichiers/M21-E25/medisphere/docs/observabilite/metriques/runbooks/RB-214-thanos.md).

*1. Lecture* :
- Compaction : les blocs de 2 h sont fusionnés en 8 h, puis 2 jours, puis 14 jours (niveaux) ; moins de blocs = moins d'index à charger par le Store et moins d'appels au stockage objet par requête.
- Le dédoublonnage de Query se fait **à chaque requête** ; dans le compartiment, les deux réplicas restent deux copies (place ×2, Store qui lit deux fois). Le Compactor (`--deduplication.replica-label`) fusionne les blocs qui ne diffèrent que par l'étiquette de réplica (compaction **verticale**) : la place est divisée par deux et les requêtes longues lisent moitié moins.
- `penalty` : même algorithme que Query, qui tolère les trous et les petits décalages d'horodatage entre réplicas. Le défaut (1 pour 1) suppose des échantillons **identiques**, ce que deux Prometheus indépendants ne produisent jamais (horodatages de collecte différents) : il garderait des doublons ou des incohérences.
- *Halted* : sur une erreur qu'il ne sait pas traiter sans risque (chevauchement de blocs, bloc corrompu), le Compactor s'arrête de compacter (`thanos_compact_halted 1`) mais reste en vie, pour qu'un humain décide. Continuer risquerait d'aggraver (fusionner des données incohérentes, supprimer).
- Deux Compactors : aucun verrou dans le stockage objet. Chacun planifie la compaction du même groupe, envoie un bloc fusionné, marque les sources à supprimer : on obtient des chevauchements (l'autre s'arrête en *halted*) ou la suppression de blocs que l'autre lisait encore.

*2. Inventaire* :

```
admin@adm01:~$ cfg="$(~/src/observabilite/outils/objstore-local.sh)"
admin@adm01:~$ thanos tools bucket inspect --objstore.config-file="$cfg" --sort-by=FROM | head -15
|            ULID            |        FROM         |        UNTIL        | RANGE  | … | RESOLUTION | LEVEL | COMPACTED |                       LABELS                        | SOURCE  |
| 01M5KNGGR0K3M2N1P0Q9R8S7T6 | 23-10-2026 06:00:00 | 23-10-2026 08:00:00 | 2h0m0s | … | 0s         | 1     | false     | cluster=k8s-par1,…,prometheus_replica=prometheus-kps-0 | sidecar |
…
admin@adm01:~$ rm -f "$cfg"
```

(Colonnes exactes : celles de ta version ; l'important est le niveau, la résolution, l'étiquette de réplica et la source.)

*3. Compactor* : StatefulSet à `replicas: 1`, `updateStrategy: OnDelete` (le pod n'est remplacé que lorsqu'on le supprime : pas de nouveau pod qui démarre pendant que l'ancien envoie un bloc), `--wait --wait-interval=5m`, `--retention.resolution-raw=30d`, `--retention.resolution-5m=180d`, `--retention.resolution-1h=2y`, `--deduplication.replica-label=prometheus_replica`, `--deduplication.func=penalty`, `--delete-delay=48h`, `--consistency-delay=30m`, volume de travail de 20 Gio. Au démarrage, les journaux disent :

```
msg="deduplication.replica-label specified, enabling vertical compaction" dedupReplicaLabels=prometheus_replica
msg="retention policy of raw samples is enabled" duration=720h0m0s
msg="retention policy of 5 min aggregated samples is enabled" duration=4320h0m0s
msg="retention policy of 1 hour aggregated samples is enabled" duration=17520h0m0s
```

(Relevé sur Thanos 0.42.4 avec ces options.)

*4. Interface des blocs* : `kubectl -n supervision port-forward pod/thanos-compactor-0 10902:10902`, puis `http://localhost:10902/blocks` : les blocs de niveau 1 des deux réplicas disparaissent au profit de blocs de niveau 2 (8 h) **sans** `prometheus_replica` dans les étiquettes (dédoublonnés) ; les blocs 5 min (`RESOLUTION 5m0s`) apparaissent pour des données de plus de 40 h. L'interface est en lecture : c'est la même que `thanos tools bucket web` (inutile de déployer un composant de plus).

*5. Alertes et tests* : [`regles/thanos.yaml`](fichiers/M21-E25/observabilite/regles/thanos.yaml) : `ThanosCompacteursMultiples` (critique : risque de perte), `ThanosCompacteurArrete`, `ThanosCompacteurAbsent`, `ThanosCompacteurInactif` (rien écrit depuis 24 h), `ThanosSidecarEnvoisArretes` (aucun envoi depuis 5 h **et** processus démarré depuis plus de 5 h), `ThanosCompartimentEnEchec`, `ThanosQuerySidecarManquant`, `ThanosQueryStoreManquant` (avec le `or … * 0` qui fabrique un zéro quand la série manque). Tout le reste en avertissement : un envoi arrêté laisse 15 jours de marge. [Tests](fichiers/M21-E25/observabilite/tests/thanos.test.yaml) avec le dossier `build/` d'E14 :

```
admin@adm01:~/src/observabilite$ outils/extraire-regles.sh && promtool test rules tests/thanos.test.yaml
règles : 4 fichier(s) extrait(s) dans build/regles/
Unit Testing:  tests/thanos.test.yaml
  SUCCESS
```

Ajoute `thanos.yaml` à `regles/kustomization.yaml` ([extrait](fichiers/M21-E25/observabilite/kustomizations.extrait.yaml)).

*6. Requêtes longues* : dans l'interface de Thanos Query (10.10.41.60), `sum(rate(mediagenda_http_requests_total[1h]))` sur 30 jours, case « Max Resolution » *raw* puis *5m* puis *1h* (ou `max_source_resolution=1h` dans l'API). Avec `--query.auto-downsampling`, Query choisit seul une résolution compatible avec le pas (pas de 1 h → blocs 5 min ou 1 h). L'écart de temps est faible sur un lab de quelques jours ; il devient net au-delà de quelques semaines de données (moins de morceaux à lire). Note aussi `stats=all` dans l'API (statistiques de requête) pour comparer les échantillons lus.

*7. Runbook* : [RB-214](fichiers/M21-E25/medisphere/docs/observabilite/metriques/runbooks/RB-214-thanos.md).

**Explications**

Le Compactor est le seul composant qui **modifie** le passé : c'est pour cela qu'il est seul, lent et prudent (délais de cohérence et de suppression, arrêt plutôt que réparation automatique). Le sous-échantillonnage garde, pour chaque intervalle de 5 min ou 1 h, plusieurs agrégats (min, max, somme, nombre, compteur) : `rate()` et `max_over_time()` restent justes à cette résolution, mais une requête qui suppose un échantillon toutes les 30 s (`[1m]`) n'a plus de sens sur des blocs 1 h. La rétention se fait par résolution : au bout de 30 jours il ne reste que les agrégats, au bout de 180 jours que l'heure.

**Alternatives**
- Pas de dédoublonnage hors ligne : plus simple, mais compartiment ×2 et requêtes longues plus lentes.
- Rétention par **cycle de vie** du stockage objet : interdit avec Thanos (le Compactor perd la trace des blocs).
- `thanos tools bucket retention` lancé par un CronJob : même effet que `--retention.*`, mais un acteur de plus sur le compartiment.

**Pièges classiques**
- Un Deployment au lieu d'un StatefulSet, avec la stratégie par défaut : pendant une mise à jour, l'ancien et le nouveau pod tournent ensemble quelques secondes.
- Oublier `--wait` : le pod s'arrête après un passage, Kubernetes le relance, `CrashLoopBackOff` permanent.
- `--retention.resolution-raw=30d` sans les deux autres : les blocs sous-échantillonnés sont gardés **pour toujours** (0d), ou inversement des blocs bruts supprimés avant que leur version 5 min existe (le sous-échantillonnage 5 min part de blocs bruts de plus de 40 h : une rétention brute plus courte n'en produit jamais).
- Volume de travail trop petit : « no space left on device » au premier gros groupe, puis *halted*.
- Une alerte « dernier envoi il y a plus de N heures » sur `last_successful_upload_time` qui sonne à chaque redémarrage (la métrique vaut 0).

**En production chez MédiSphère**
Compactor surveillé comme une base de données (sa panne ne se voit qu'à long terme) ; essai de restauration d'un bloc depuis la réplique hors site ; `thanos tools bucket verify` mensuel en lecture ; procédure écrite (RB-214 §3) pour les chevauchements, avec double validation.

---

### M21-E26 — SLI et SLO de MédiAgenda avec Pyrra

**Solution**

Fichiers : [`pyrra/`](fichiers/M21-E26/observabilite/pyrra/) (CRD amont non modifiée, `pyrra-kubernetes.yaml`, `pyrra-api.yaml` avec HTTPRoute, `surveillance-et-politiques.yaml`, kustomization), Application [`gitops/plateforme/pyrra.yaml`](fichiers/M21-E26/gitops/plateforme/pyrra.yaml), [`slo/`](fichiers/M21-E26/observabilite/slo/) (trois SLO, alertes désactivées), [`kustomization.yaml.extrait`](fichiers/M21-E26/observabilite/kustomization.yaml.extrait), [`slo.md`](fichiers/M21-E26/medisphere/docs/observabilite/metriques/slo.md).

*1. Définitions* (voir `slo.md`) : `mediagenda-disponibilite` — bon événement : requête de l'API de **production** sans code 5xx ; valide : toute requête hors `/sante`, `/pret`, `/metrics` ; 99,5 % sur 28 jours glissants ; budget 0,5 % des requêtes, soit l'équivalent de 0,005 × 28 × 24 h ≈ 3 h 22 min d'indisponibilité totale. Les 4xx ne consomment pas le budget (erreur du client) : c'est un choix à écrire (un 429 dû à notre limitation de débit serait discutable). `medidoc-disponibilite` : recette (pas de production de MédiDoc dans le lab), 99 %.

*2. Mesurabilité* :

```
admin@adm01:~$ curl -s -G http://prometheus.apps.par1.medisphere.internal:9090/api/v1/label/le/values \
    --data-urlencode 'match[]=mediagenda_http_request_duration_seconds_bucket' | jq -c .data
["+Inf","0.005","0.01","0.025","0.05","0.075","0.1","0.25","0.5","0.75","1.0","10.0","2.5","5.0","7.5"]
```

Seaux par défaut de `prometheus_client` : **pas de `0.3`**. On ne peut pas compter les requêtes de moins de 300 ms ; `histogram_quantile(0.95, …)` interpole entre 0,25 et 0,5 (il suppose une répartition uniforme dans le seau) : bon pour un tableau, faux pour compter. Décision : objectif mesuré à **250 ms** (plus strict que le contrat) en attendant le ticket DEV-2226 (ajouter `buckets=(…, 0.25, 0.3, 0.5, …)` à l'histogramme de MédiAgenda) ; remarque au passage que les valeurs `le` sont des chaînes : `1.0`, pas `1` (Prometheus 3 normalise les valeurs de `le` des histogrammes classiques).

*3. Manifestes* : recopie des fichiers de `examples/kubernetes/manifests/` de l'étiquette `v0.10.2` ; écarts commentés en tête de chaque fichier. Points à justifier : `pyrra-api --prometheus-url=http://thanos-query…` (fenêtre de 28 jours au-delà de la base locale), `pyrra kubernetes --generic-rules --external-url=https://slo.apps…` ; un seul réplica de l'opérateur (pas d'élection de chef activée) ; utilisateur 65533 de l'image ; politiques d'entrée (Gateway → API, API → opérateur 9444, Prometheus → métriques). Application `pyrra` **sans** finaliseur : supprimer l'Application ne supprime pas la CRD ; et Pyrra est séparé de l'Application `observabilite` (qui, elle, a un finaliseur et un `prune`) pour la même raison.

*4. Objectifs* : `alerting: {burnrates: false, absent: false}` (le champ `disabled` est **déprécié** dans la CRD v0.10 et ne coupe pas l'alerte d'absence). Vérification avant la MR :

```
admin@adm01:~/src/observabilite$ mkdir -p /tmp/slo-essai && pyrra generate --config-files='slo/m*.yaml' --prometheus-folder=/tmp/slo-essai/ --generic-rules
admin@adm01:~/src/observabilite$ promtool check rules /tmp/slo-essai/*.yaml
Checking /tmp/slo-essai/mediagenda-disponibilite.yaml
  SUCCESS: 14 rules found
…
admin@adm01:~/src/observabilite$ grep -c 'alert:' /tmp/slo-essai/*.yaml
/tmp/slo-essai/mediagenda-disponibilite.yaml:0
```

(« namespace must be set » s'affiche en avertissement : l'espace est posé par kustomize.)

*5. Règles générées* : une PrometheusRule par SLO, même nom, `ownerReferences` vers le SLO, étiquettes recopiées (dont `medisphere.internal/supervision: oui`, posée par la kustomization racine sur le SLO) ; groupes `<slo>-increase` (intervalle 2 min 30 s : `…:increase4w`, et l'alerte d'absence quand elle est active) et `<slo>` (taux par fenêtre `…:burnrate5m` … `…:burnrate4d`), plus `<slo>-generic` avec `--generic-rules`. La règle `mediagenda_http_requests:increase4w` est `increase(…[4w])` **évaluée par Prometheus sur sa base locale** : elle ne voit que 15 jours. La disponibilité affichée « sur 28 jours » est donc calculée sur 15 jours au plus (E30 y revient).

*6. Interface* : l'essai le plus simple est un SLO de recette temporaire (copie de `mediagenda-disponibilite` sur `mediagenda-recette`, objectif 99,9 %) et dix minutes de requêtes vers une route qui répond 5xx (un `POST /api/v1/rendez-vous` avec une date passée produit un 422, pas un 5xx : provoque plutôt un 503 en arrêtant Valkey **de recette** par Git, ou utilise la recette de MédiDoc avec un compartiment indisponible). Le budget restant baisse en quelques minutes dans l'interface. Retire l'essai par Git.

**Explications**

Un SLO est un contrat **interne** plus strict que l'engagement externe (SLA), mesuré sur ce que vit l'utilisateur. Pyrra traduit chaque SLO en règles d'enregistrement de taux d'erreurs sur plusieurs fenêtres (5 min à 4 jours) et en un compteur sur la fenêtre totale ; l'interface affiche disponibilité et budget à partir de ces séries. Le choix de la source (application, Gateway, sonde externe) fixe ce que le SLO voit et ne voit pas.

**Alternatives**
- Sloth (E27), OpenSLO + un générateur, règles écrites à la main ; Grafana SLO (Grafana Cloud, hors souveraineté).
- SLI côté Gateway (métriques d'Envoy de Cilium, si exposées) : voit aussi les 503 de la Gateway quand tous les pods sont tombés, ce que l'application ne compte pas.
- SLI par sonde blackbox (disponibilité « vue de dehors ») : simple mais ne compte qu'une requête par intervalle.

**Pièges classiques**
- Compter les sondes du kubelet dans le total : des milliers de requêtes `/sante` toujours réussies diluent les erreurs réelles (un SLO à 99,99 % sans rien mesurer).
- Utiliser `histogram_quantile` comme SLI : on ne compte pas des requêtes, on estime un quantile.
- Mettre `--prometheus-url` de l'API sur `kps-prometheus` : la fenêtre de 28 jours dépasse la base locale, graphiques tronqués.
- Laisser les alertes par défaut actives avant E27 : `severity: critical` part à l'astreinte par la route d'E06.
- Recopier les manifestes amont sans changer l'image (v0.9.0, tirée de `ghcr.io` sans passer par Harbor).

**En production chez MédiSphère**
SLO révisés chaque trimestre avec l'équipe produit et le support ; rapport mensuel au comité HDS (disponibilité, budget consommé, incidents rattachés) ; SLO de bout en bout (sonde externe hors site) en complément du SLI de l'application.

---

### M21-E27 — Budgets d'erreur et alertes multi-fenêtres ; Sloth en comparaison

**Solution**

Fichiers : [`slo/`](fichiers/M21-E27/observabilite/slo/) (alertes actives, gravités par fenêtre, `pyrra.dev/equipe`, annotations `pyrra.dev/resume|description|runbook_url`), [`slo/sloth/mediagenda-disponibilite.sloth.yaml`](fichiers/M21-E27/observabilite/slo/sloth/mediagenda-disponibilite.sloth.yaml), [`kps/values.yaml.extrait`](fichiers/M21-E27/observabilite/kps/values.yaml.extrait) (réétiquetage), [`outils/generer-regles-slo.sh`](fichiers/M21-E27/observabilite/outils/generer-regles-slo.sh), [`.gitlab-ci.yml.extrait`](fichiers/M21-E27/observabilite/.gitlab-ci.yml.extrait), [`tests/slo-mediagenda.test.yaml`](fichiers/M21-E27/observabilite/tests/slo-mediagenda.test.yaml), [`alertmanager/routes-tests.extrait.txt`](fichiers/M21-E27/observabilite/alertmanager/routes-tests.extrait.txt) ; documentation : [`politique-budget-erreur.md`](fichiers/M21-E27/medisphere/docs/observabilite/metriques/politique-budget-erreur.md), [`comparatif-pyrra-sloth.md`](fichiers/M21-E27/medisphere/docs/observabilite/metriques/comparatif-pyrra-sloth.md), [RB-216](fichiers/M21-E27/medisphere/docs/observabilite/metriques/runbooks/RB-216-budget-erreur.md).

*1. Lecture* : budget = 1 − 0,995 = 0,005. Un taux de consommation de 1 épuise le budget en exactement 28 jours ; 14 l'épuise en 2 jours (28/14) ; 7 en 4 jours ; 2 en 14 jours. Une fenêtre longue seule (1 h) réagit tard et **reste** en alerte longtemps après la fin de l'incident ; une fenêtre courte seule (5 min) sonne pour un pic de 30 secondes. Les deux ensemble : l'alerte ne sonne que si le problème est **important** (fenêtre longue au-dessus du seuil) **et toujours en cours** (fenêtre courte), et s'arrête vite. Pyrra pour 28 jours (code `Windows` de `slo/rules.go`) : (5 min, 1 h) ×14 `for` 2 min ; (30 min, 6 h) ×7 `for` 15 min ; (2 h, 1 j) ×2 `for` 1 h ; (6 h, 4 j) ×1 `for` 3 h.

*2. Gravités et équipes* : `mediagenda-disponibilite` : `fastBurn`/`mediumBurn` critique, `slowBurn`/`longTermBurn` avertissement, `absent` critique ; `mediagenda-latence` : seule la consommation la plus rapide réveille ; `medidoc-disponibilite` : avertissement et info, jamais critique (recette). Étiquettes et annotations par le préfixe `pyrra.dev/` (recopiées sans le préfixe). Réétiquetage dans Prometheus ([extrait](fichiers/M21-E27/observabilite/kps/values.yaml.extrait)) :

```yaml
additionalAlertRelabelConfigs:
  - source_labels: [gravite, severity]
    separator: ";"
    regex: ";(critique|avertissement|info)"
    target_label: gravite
    replacement: "$1"
```

L'expression ne correspond que si `gravite` est **vide** (rien avant le `;`) : les alertes qui ont déjà `gravite` ne bougent pas ; celles du chart (`critical`, `warning`) non plus (routées par E06/E16). Le chart en fait le Secret `kps-prometheus-am-relabel-confg`, que le CR désigne. Contrôle du routage :

```
admin@adm01:~/src/observabilite$ outils/extraire-regles.sh && sh outils/tester-routes.sh build/alertmanager.yml alertmanager/routes-tests.txt
OK  alertname=ErrorBudgetBurn severity=critique gravite=critique equipe=mediagenda slo=mediagenda-disponibilite namespace=mediagenda-prod -> astreinte-mail
…
```

*3. Tests* : la CI produit les règles avec l'image de Pyrra du cache (`slo:generer`, dossier `build/slo/`) et le job de tests d'E14/E15 les teste ([test](fichiers/M21-E27/observabilite/tests/slo-mediagenda.test.yaml)) : 600 requêtes/min, puis 8 % d'erreurs (52 sur 652) à partir de t = 2 h. À 2 h 30, la fenêtre d'1 h ne contient que ~4 % d'erreurs : aucune alerte. À 3 h, 8 % sur 5 min **et** sur 1 h (> 7 %) : `ErrorBudgetBurn` critique avec `short="5m"`, `long="1h"`, `exhaustion="2d"`. Les autres paires ne sont pas encore *firing* (6 h : ~2,8 % < 3,5 % ; (2 h, 1 j) : condition vraie depuis ~16 min seulement, `for` 1 h). Le test vérifie aussi que des 503 sur `/pret` ne consomment rien et que l'absence de mesure déclenche `SLOMetricAbsent`.

```
admin@adm01:~/src/observabilite$ outils/extraire-regles.sh && sh outils/generer-regles-slo.sh && promtool test rules tests/*.test.yaml
…
Unit Testing:  tests/slo-mediagenda.test.yaml
  SUCCESS
```

L'ordre compte : `extraire-regles.sh` d'E14 commence par vider `build/`.

*4. Sloth* :

```
admin@adm01:~/src/observabilite$ sloth generate -i slo/sloth/mediagenda-disponibilite.sloth.yaml --default-slo-period=28d -o /tmp/sloth.yml
admin@adm01:~/src/observabilite$ promtool check rules /tmp/sloth.yml
  SUCCESS: 17 rules found
```

Sloth produit 15 règles d'enregistrement (`slo:sli_error:ratio_rate5m` … `ratio_rate3d`, `ratio_rate4w`, et des méta-règles : objectif, budget, consommation, budget restant, `sloth_slo_info`) et **2** alertes : « page » = (5 min et 1 h au-dessus de 13,44 × budget) **ou** (30 min et 6 h au-dessus de 5,6 ×) ; « ticket » = (2 h et 1 j, 2,8 ×) **ou** (6 h et 3 j, 0,93 ×), sans `for`. Les facteurs sont exacts pour 28 jours (2 % du budget en 1 h = 0,02 × 672 h). Sa disponibilité sur 28 jours est une **moyenne de ratios de 5 min** (pas un ratio de comptes) et il n'a pas d'alerte d'absence. Décision et tableau complet : [comparatif](fichiers/M21-E27/medisphere/docs/observabilite/metriques/comparatif-pyrra-sloth.md) — Pyrra reste (interface, quatre niveaux alignés sur la politique, opérateur déjà en place), Sloth sert de contre-vérification.

*5. Politique* : [modèle](fichiers/M21-E27/medisphere/docs/observabilite/metriques/politique-budget-erreur.md) : rythmes et destinataires, quatre paliers de budget restant (> 50 %, 25-50 %, < 25 % gel des fonctionnalités, épuisé), décideurs (Julien Petit, Karim Benali, Claire Morel), exceptions (sécurité, fournisseur), revue hebdomadaire et rapport mensuel HDS, limites connues.

*6. Runbook et essai* : [RB-216](fichiers/M21-E27/medisphere/docs/observabilite/metriques/runbooks/RB-216-budget-erreur.md). L'essai le plus sûr : un SLO de recette temporaire à 99,99 % (budget de 0,01 % : la moindre erreur dépasse 14 ×) ; courriel attendu à l'équipe (avertissement) ou à l'astreinte selon la gravité que tu lui donnes ; retrait par Git.

**Explications**

L'alerte de budget remplace des dizaines d'alertes de seuil (« taux d'erreurs > 5 % pendant 10 min ») par une question unique : « à ce rythme, quand aurons-nous rompu notre promesse ? ». Le facteur et la fenêtre longue fixent la **précision** (peu de fausses alertes), la fenêtre courte le **temps de réinitialisation**, le facteur la **gravité**. Le budget donne aussi la règle de décision entre vitesse et fiabilité (la politique), qui est le vrai livrable.

**Alternatives**
- Écrire les règles à la main (stratégie 6 du *Workbook*) : complet, mais chaque nouvel objectif demande de recalculer et de tester.
- Sloth en production : générer en CI et commiter les règles ; routage plus simple (étiquettes libres), pas d'interface.
- Alertes de budget dans Grafana (règles gérées par Grafana) : une seconde évaluation d'alertes à exploiter, hors de Prometheus et d'Alertmanager.

**Pièges classiques**
- Laisser Pyrra poser `severity: critical` sans traduction : routage par la route `severity` d'E06 (astreinte pour tout, y compris la recette).
- Un réétiquetage qui écrase `gravite` sur toutes les alertes (regex sans le `;` de tête).
- Tester des règles régénérées à la main une fois, puis jamais : le test doit utiliser **les** règles de la version de Pyrra en service.
- Oublier que deux SLO de la même métrique produisent les mêmes noms de règles (`mediagenda_http_requests:burnrate5m`), distingués par l'étiquette `slo` : toute requête sur ces séries doit filtrer `slo=`.
- Croire qu'un SLO à faible trafic se comporte comme en heure de pointe : la nuit, une erreur sur vingt requêtes fait 5 %.

**En production chez MédiSphère**
La politique de budget est signée par la direction produit, pas seulement par la plateforme ; le gel est tracé (ticket CHG avec la mention du budget) ; les alertes de budget alimentent la revue mensuelle des alertes (politique d'alerte, E32).

---

### M21-E28 — Superviser la supervision

**Solution**

Fichiers : côté cluster, [`scrape/temoin-mon01.yaml`](fichiers/M21-E28/observabilite/scrape/temoin-mon01.yaml), [`regles/supervision-temoin.yaml`](fichiers/M21-E28/observabilite/regles/supervision-temoin.yaml) et ses [tests](fichiers/M21-E28/observabilite/tests/supervision-temoin.test.yaml), [`kps/values.yaml.extrait`](fichiers/M21-E28/observabilite/kps/values.yaml.extrait) (chemin de secours), [`kps/values.yaml.essai-extrait`](fichiers/M21-E28/observabilite/kps/values.yaml.essai-extrait) (l'essai), [`kustomizations.extrait.yaml`](fichiers/M21-E28/observabilite/kustomizations.extrait.yaml) ; côté témoin (rôle `supervision_temoin` d'E11), [`files/regles/supervision-cluster.yml`](fichiers/M21-E28/ansible/roles/supervision_temoin/files/regles/supervision-cluster.yml) et son [test](fichiers/M21-E28/ansible/roles/supervision_temoin/files/regles/supervision-cluster.test.yml), les extraits de [`prometheus.yml.j2`](fichiers/M21-E28/ansible/roles/supervision_temoin/templates/prometheus-jobs-supervision-cluster.yml.extrait), de [`blackbox.yml.j2`](fichiers/M21-E28/ansible/roles/supervision_temoin/templates/blackbox-modules-supervision-cluster.yml.extrait) et de [`tasks/configuration.yml`](fichiers/M21-E28/ansible/roles/supervision_temoin/tasks/configuration.yml.extrait) ; bordure : [`pare_feu.yml.extrait`](fichiers/M21-E28/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait) ; [RB-215](fichiers/M21-E28/medisphere/docs/observabilite/metriques/runbooks/RB-215-supervision-muette.md).

*1. Lecture* : `Watchdog` présente dans la réponse de Thanos Query prouve qu'au moins un Prometheus collecte et **évalue ses règles**, que son sidecar répond, que Thanos Query répond et que le réseau de `mon01` à 10.10.41.60 fonctionne. Elle ne prouve rien sur Alertmanager ni sur l'envoi des courriels (d'où les sondes `/-/healthy` et le chemin de secours). L'observateur doit être ailleurs parce qu'une supervision ne peut pas annoncer sa propre mort (le ticket). Le cas aveugle : cluster et `mon01` perdus ensemble — même hyperviseur `pve01` : limite écrite dans l'ADR-0210.

*2. La sonde Watchdog* : Thanos Query ne sert pas `/federate` (seulement l'API de requête) ; le témoin interroge donc l'API par blackbox_exporter, avec un module qui exige le **corps** :

```yaml
watchdog_cluster:
  prober: http
  timeout: 15s
  http:
    method: GET
    valid_status_codes: [200]
    preferred_ip_protocol: ip4
    fail_if_body_not_matches_regexp:
      - '"alertname":"Watchdog"'
```

Cible (déjà encodée) : `http://prometheus.apps.par1.medisphere.internal:9090/api/v1/query?query=ALERTS%7Balertname%3D%22Watchdog%22%2Calertstate%3D%22firing%22%7D`. Prometheus encode encore la valeur de `target`, blackbox la décode une fois et envoie la requête écrite (vérifié avec blackbox_exporter 0.29.1 contre un Thanos Query 0.42.4 : la requête arrive sous forme décodée, `ALERTS{alertname="Watchdog",…}` dans le journal de blackbox, Thanos Query l'accepte, `200`, et la sonde échoue, `probe_success 0`, quand le résultat est vide). Contrôle depuis `mon01` :

```
admin@mon01:~$ curl -s 'http://127.0.0.1:9115/probe?module=watchdog_cluster&debug=true&target=http%3A%2F%2Fprometheus.apps.par1.medisphere.internal%3A9090%2Fapi%2Fv1%2Fquery%3Fquery%3DALERTS%257Balertname%253D%2522Watchdog%2522%257D' | grep -E 'probe_success|Body|body'
admin@mon01:~$ curl -s 'http://127.0.0.1:9115/probe?module=watchdog_cluster&target=http%3A%2F%2Fprometheus.apps.par1.medisphere.internal%3A9090%2Fapi%2Fv1%2Fquery%3Fquery%3Dvector(0)' | grep '^probe_success'
probe_success 0
```

(Dans un `curl` à la main, la cible est encodée **deux** fois : c'est ce que fait Prometheus pour toi.) Les jobs `watchdog-cluster` et `supervision-cluster` sont distincts du job `blackbox` d'E11 : ses règles `SondeEnEchec` et `CertificatEcheanceProche` ne s'y appliquent pas (pas de doublon de courriel).

*3. Règles du témoin* : `SupervisionClusterMuette` (`probe_success{job="watchdog-cluster"} == 0` pendant 5 min, critique), `SupervisionClusterSondeAbsente` (`absent(…)`), `SupervisionClusterComposantKO` (par `composant`). Déposées par une tâche `copy` validée par `promtool check rules`, testées :

```
admin@adm01:~/src/ansible$ promtool test rules roles/supervision_temoin/files/regles/supervision-cluster.test.yml
  SUCCESS
```

*4. Réciproque* : ScrapeConfig `temoin-mon01` (métriques propres du Prometheus témoin, `honorLabels` inutile ici) ; alertes `TemoinInjoignable` (`up == 0 or absent(up{job="temoin-mon01"})`), `TemoinSansAlertmanager` (`prometheus_notifications_alertmanagers_discovered < 1`), `TemoinNotificationsEnEchec`, `TemoinReglesEnEchec` ; tests (dont le cas « ScrapeConfig supprimée » couvert par `absent()`).

*5. Chemin de secours* ([extrait](fichiers/M21-E28/observabilite/kps/values.yaml.extrait)) : `additionalAlertManagerConfigs` vers `mon01.par1.medisphere.internal:9093`, avec `alert_relabel_configs: [{source_labels: [alertname], regex: "Alertmanager.+", action: keep}]` : seules `AlertmanagerFailedToSendAlerts`, `AlertmanagerClusterDown`, `AlertmanagerFailedReload`… partent aussi vers le témoin, qui les envoie à `astreinte@` par sa route d'E11. Flux nouveau `K8S_TRAV` → `mon01`:9093 (bordure). Vérification :

```
admin@adm01:~$ kubectl -n supervision port-forward pod/prometheus-kps-0 9090 &
admin@adm01:~$ curl -s localhost:9090/api/v1/status/config | jq -r .data.yaml | yq '.alerting'
alert_relabel_configs:
  - action: labeldrop
    regex: prometheus_replica
  …
alertmanagers:
  - … (kubernetes_sd, alertmanager-kps) …
  - scheme: http
    static_configs: [{targets: [mon01.par1.medisphere.internal:9093]}]
    alert_relabel_configs: [{action: keep, regex: Alertmanager.+, source_labels: [alertname]}]
admin@adm01:~$ kill %1
```

*6. Essai* : MR « CHG-2228 : Alertmanager à 0 réplica » ([extrait](fichiers/M21-E28/observabilite/kps/values.yaml.essai-extrait)), synchronisation, chronomètre. Déroulé attendu : 30 s plus tard le pod `alertmanager-kps-0` est arrêté ; les sondes `/-/healthy` et `/-/ready` de 10.10.41.61 échouent ; 5 min plus tard `SupervisionClusterComposantKO{composant="alertmanager"}` passe *firing* sur le témoin ; le courriel du témoin arrive dans Mailpit (`astreinte@`) après le `group_wait` de l'Alertmanager témoin : **6 à 7 minutes** au total. `SupervisionClusterMuette` ne sonne pas : Prometheus évalue toujours Watchdog (il ne dépend pas d'Alertmanager pour cela). Aucune alerte `Alertmanager…` du cluster ne part non plus : celles-ci parlent d'un Alertmanager **qui tourne** et n'envoie plus ; ici il n'y en a plus aucun (`AlertmanagerClusterDown` ne sonne que si une partie de la grappe manque : à 0 réplica, il n'y a plus de série) — c'est précisément le cas couvert par la sonde du témoin. `git revert`, synchronisation, courriel de résolution du témoin. Réciproque : `sudo systemctl stop prometheus` sur `mon01` → `TemoinInjoignable` après 5 min, courriel de l'Alertmanager **du cluster** à l'astreinte ; `systemctl start prometheus`.

*7. Runbook* : [RB-215](fichiers/M21-E28/medisphere/docs/observabilite/metriques/runbooks/RB-215-supervision-muette.md) (principe, chaque alerte, diagnostic, essai trimestriel).

**Explications**

Le *dead man's switch* inverse la logique : au lieu d'attendre un message d'erreur (que la panne empêche d'envoyer), on attend un message de bonne santé, et c'est son **absence** qui alerte. Le témoin et le cluster forment deux supervisions qui se regardent : chacune couvre l'autre, sur deux domaines de panne distincts (VM du socle d'un côté, cluster de l'autre). Le chemin de secours couvre le maillon que Watchdog ne prouve pas : un Alertmanager vivant mais incapable de notifier.

**Alternatives**
- Watchdog routé vers un service externe (Healthchecks, Dead Man's Snitch, l'équivalent dans un outil d'astreinte) : couvre aussi la perte de `pve01`, mais sort du lab et de la souveraineté (aucune donnée de santé n'y part : seulement un battement).
- Fédérer depuis un pod Prometheus exposé à part (Service `LoadBalancer` supplémentaire) : possible, mais une adresse de plus à protéger, et cela ne prouve pas que Thanos Query sert.
- Thanos Ruler sur le témoin, branché sur la StoreAPI du cluster : bien plus lourd.

**Pièges classiques**
- Une sonde HTTP qui ne vérifie que le code 200 : Thanos Query répond 200 avec `"result":[]` quand Watchdog a disparu ; la sonde resterait verte.
- La requête PromQL écrite en clair dans la cible : selon l'encodage, `{` et `"` arrivent mal, ou la requête change de sens.
- Mettre ces sondes dans le job `blackbox` d'E11 : doublon de courriels avec `SondeEnEchec`.
- Envoyer **toutes** les alertes du cluster au témoin : chaque incident produit deux courriels.
- L'essai par `kubectl scale --replicas=0` : l'opérateur remet le StatefulSet à 1 en quelques secondes, l'essai ne prouve rien.

**En production chez MédiSphère**
Essai trimestriel planifié (RB-215 §4), délais mesurés suivis ; un battement Watchdog vers un service hors site (sans donnée) au PRA (F5) ; témoin sur PAR2 quand le site existera.

---

### M21-E29 — Sécuriser la pile de supervision

**Solution**

Fichiers : [`kps/values.yaml.extrait`](fichiers/M21-E29/observabilite/kps/values.yaml.extrait) (Grafana, API d'administration, règles par équipe), [`reseau/espace-supervision.yaml`](fichiers/M21-E29/observabilite/reseau/espace-supervision.yaml) et sa kustomization, [`kustomization.yaml.extrait`](fichiers/M21-E29/observabilite/kustomization.yaml.extrait) ; dans `plateforme/k8s` : [`espaces/supervision-regles.extrait.yaml`](fichiers/M21-E29/k8s/espaces/supervision-regles.extrait.yaml), [`rbac/supervision-equipes.yaml`](fichiers/M21-E29/k8s/rbac/supervision-equipes.yaml), [`outils/grafana-rotation-admin.sh`](fichiers/M21-E29/k8s/outils/grafana-rotation-admin.sh) ; dans `mediagenda/deploiement` : [`components/supervision/regles.yaml`](fichiers/M21-E29/mediagenda-deploiement/components/supervision/regles.yaml) ; [`securite.md`](fichiers/M21-E29/medisphere/docs/observabilite/metriques/securite.md).

*1. État des lieux* (exemples de preuves) :

```
admin@adm01:~$ kubectl -n supervision get cm kps-grafana -o jsonpath='{.data.grafana\.ini}' | grep -E 'cookie|lifetime|password_policy|external_enabled'   # rien
admin@adm01:~$ kubectl -n wb-essais run sonde --rm -it --image=registry.par1.medisphere.internal/dockerhub/nicolaka/netshoot:v0.16 -- \
    curl -s -o /dev/null -w '%{http_code}\n' http://kps-alertmanager.supervision:9093/api/v2/silences     # 200 avant E29
admin@adm01:~$ kubectl -n supervision get prometheus kps -o jsonpath='{.spec.enableAdminAPI}'                  # false (défaut)
```

En plus des constats de Sophie : Prometheus, Thanos Query et Alertmanager n'ont aucune authentification (toute machine de MGMT peut poser un silence) ; les instantanés publics de Grafana partent vers `snapshots.raintank.io` ; une règle d'équipe peut porter n'importe quelle étiquette `equipe`.

*2. Grafana* ([extrait](fichiers/M21-E29/observabilite/kps/values.yaml.extrait)) : `security.cookie_secure`, `cookie_samesite: lax` (pas `strict` : la redirection OIDC du M24 perdrait le cookie d'état), `disable_gravatar`, `strict_transport_security` (+ âge **entre guillemets** : sans eux, le chart écrit `3.1536e+07` dans `grafana.ini`, relevé au rendu), `content_security_policy`, `users.allow_org_create: false`, `auto_assign_org_role: Viewer`, `auth.login_maximum_inactive_lifetime_duration: 8h`, `login_maximum_lifetime_duration: 24h`, `auth.basic.password_policy`, `snapshots.external_enabled: false`. Contrôle :

```
admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' https://grafana.apps.par1.medisphere.internal/api/search
401
```

*3. Rotation* ([script](fichiers/M21-E29/k8s/outils/grafana-rotation-admin.sh)) : le Secret `grafana-admin` n'est lu qu'à la création de la base (variables `GF_SECURITY_ADMIN_*`) ; ensuite le mot de passe vit dans la base SQLite. Ordre : nouveau mot de passe dans le Vault (`ansible-vault edit … secrets/grafana.yml`), puis le script : ancien lu dans le Secret, nouveau lu dans le Vault, `PUT /api/user/password` (identifiants par `curl -K <(…)`, corps JSON par l'entrée standard), vérification (nouveau 200, ancien 401), Secret réaligné par `secrets-k8s.sh grafana`. Note la date au registre des secrets.

*4. API d'administration* : `enableAdminAPI: false` écrit explicitement (c'est le défaut : l'écrire rend un changement visible en revue). Preuve :

```
admin@adm01:~$ kubectl -n supervision port-forward pod/prometheus-kps-0 9090 &
admin@adm01:~$ curl -s -X POST localhost:9090/api/v1/admin/tsdb/snapshot
{"status":"error","errorType":"unavailable","error":"admin APIs disabled"}
```

*5. Règles par équipe* : étiquette `medisphere.internal/supervision-regles: "oui"` sur `supervision` et les espaces des équipes (`plateforme/k8s`, `espaces/`) ; `ruleNamespaceSelector` sur cette étiquette ; `enforcedNamespaceLabel: namespace` ; `excludedFromEnforcement` pour **tous** les objets de `supervision` (règles, ServiceMonitor, PodMonitor, Probe, ScrapeConfig) et les ServiceMonitor de `supervision-noeuds`. Au rendu, le chart ajoute de lui-même une exemption nominative pour chacune de ses PrometheusRule ; tes exemptions par espace couvrent le reste (dont le ServiceMonitor du **kubelet**, sans lequel toutes les séries de cAdvisor recevraient `namespace="supervision"`). Règle d'équipe ([modèle](fichiers/M21-E29/mediagenda-deploiement/components/supervision/regles.yaml)) : redémarrages du conteneur `api`, cache inefficace. Vérification :

```
admin@adm01:~$ curl -s http://prometheus.apps.par1.medisphere.internal:9090/api/v1/rules?type=alert \
    | jq -r '.data.groups[] | select(.file | test("mediagenda-prod-")) | .rules[] | .name + "  " + .query'
MediagendaRedemarrages  increase(kube_pod_container_status_restarts_total{container="api",namespace="mediagenda-prod",pod=~"mediagenda-.*"}[30m]) > 3
MediagendaCacheInefficace  sum(rate(mediagenda_cache_total{namespace="mediagenda-prod",resultat="miss"}[15m])) / sum(rate(mediagenda_cache_total{namespace="mediagenda-prod"}[15m])) > 0.8
admin@adm01:~$ curl -s -G http://prometheus.apps.par1.medisphere.internal:9090/api/v1/query \
    --data-urlencode 'query=count by (namespace) (container_cpu_usage_seconds_total)' | jq -r '.data.result[].metric.namespace' | head -4
kube-system
mediagenda-prod
…
```

L'opérateur a injecté `namespace="mediagenda-prod"` dans chaque sélecteur ; les séries de cAdvisor gardent leurs espaces (exemption effective). Essai négatif : la même règle posée (par `kubectl apply`, essai, puis supprimée) dans `wb-essais`, non étiqueté : absente de `/api/v1/rules`. RBAC : ClusterRole de lecture `supervision-lecture-equipe` lié par RoleBinding aux groupes des équipes dans leurs espaces ; l'écriture passe par Git et Argo CD.

*6. Cloisonnement* ([politiques](fichiers/M21-E29/observabilite/reseau/espace-supervision.yaml)) : `refus-par-defaut-entree` et `refus-par-defaut-sortie` (`endpointSelector: {}`, règle `{}`), `sortie-commune` (DNS par le proxy de Cilium, `kube-apiserver`, espace `supervision`), `prometheus-sortie` (`toEntities: [cluster]` et `toCIDR: 10.10.0.0/16`), `alertmanager-sortie` (`mon01`:25), `thanos-stockage-sortie` (RGW 443), `grafana-entree` (`fromEntities: [ingress]`), `kube-state-metrics-entree`, `operateur-entree` (webhooks depuis `kube-apiserver`, `host`, `remote-node`). Ordre : tout sauf les deux refus, observation Hubble, puis les refus. Après synchronisation :

```
admin@adm01:~$ hubble observe -n supervision --verdict DROPPED --last 50
admin@adm01:~$ curl -s -G http://prometheus.apps.par1.medisphere.internal:9090/api/v1/query --data-urlencode 'query=count(up{namespace="supervision"} == 0)' | jq .data.result
[]
admin@adm01:~$ amtool alert add EssaiSEC2229 gravite=avertissement equipe=plateforme --alertmanager.url=http://alertmanager.apps.par1.medisphere.internal:9093
```

(Le courriel d'essai arrive à `plateforme@` ; le témoin reste vert.)

*7. Document* : [`securite.md`](fichiers/M21-E29/medisphere/docs/observabilite/metriques/securite.md) (risques, mesures, limites acceptées jusqu'au M24 : pas d'authentification sur Prometheus, Thanos Query et Alertmanager, compensée par le filtrage réseau ; node_exporter en TLS sans authentification client).

**Explications**

La pile de supervision est une cible de choix : elle voit tout et parle à tout. On applique les mêmes principes que pour une application : moindre privilège (lecture pour les équipes, écriture par Git), cloisonnement réseau en refus par défaut, secrets tournés, et documentation des risques **résiduels**. `enforcedNamespaceLabel` est un mécanisme multi-locataire léger : il ne cache rien (les métriques restent lisibles par MGMT), mais il empêche une règle d'équipe de lire au-delà de son espace et de signer ses alertes au nom d'un autre espace.

**Alternatives**
- `AlertmanagerConfig` par équipe (routage propre à chaque espace, `alertmanagerConfigSelector`) : les équipes gèrent aussi leurs routes ; plus de pouvoir, plus de risque.
- Un Prometheus par équipe (opérateur, sélecteurs) : isolation forte, coût ×N.
- prom-label-proxy devant Thanos Query pour une lecture par locataire (préparation du M24).

**Pièges classiques**
- `enforcedNamespaceLabel` sans exemptions : le kubelet, node-exporter et kube-state-metrics perdent leur vraie étiquette `namespace` ; tous les tableaux par espace deviennent faux.
- Refus par défaut en sortie sans DNS : plus rien ne résout, symptôme « tout est en échec » ; sans `kube-apiserver` : l'opérateur ne voit plus rien, Prometheus ne découvre plus ses cibles.
- Oublier l'entrée de l'opérateur : le webhook de validation est en `failurePolicy: Fail` (E02) : plus **aucune** PrometheusRule ne peut être créée ou modifiée, Argo CD en échec de synchronisation (une variante de M21-E41).
- Changer le Secret `grafana-admin` en croyant faire la rotation.
- `cookie_samesite: strict` : connexion impossible au M24.

**En production chez MédiSphère**
Proxy d'authentification OIDC devant les trois API au M24 ; audit des silences (qui, quand, pourquoi) dans la revue des alertes ; contrôle automatique des réglages de sécurité de Grafana dans la CI (`grafana.ini` rendu, comparé à une liste) ; rotation des secrets suivie par le registre.

---

### M21-E30 — Capacité et performance de Prometheus

**Solution**

Fichiers : [`requetes/E30.promql`](fichiers/M21-E30/observabilite/requetes/E30.promql), [`kps/values.yaml.extrait`](fichiers/M21-E30/observabilite/kps/values.yaml.extrait), [`thanos/thanos-query.limites.extrait.yaml`](fichiers/M21-E30/observabilite/thanos/thanos-query.limites.extrait.yaml), [`regles/capacite-prometheus.yaml`](fichiers/M21-E30/observabilite/regles/capacite-prometheus.yaml) et ses [tests](fichiers/M21-E30/observabilite/tests/capacite-prometheus.test.yaml), [`kustomizations.extrait.yaml`](fichiers/M21-E30/observabilite/kustomizations.extrait.yaml), [`dimensionnement.md`](fichiers/M21-E30/medisphere/docs/observabilite/metriques/dimensionnement.md).

*1. Mesures* : les onze requêtes de `E30.promql` (syntaxe vérifiée par `promtool`). Les plus utiles :

```promql
# octets par échantillon
rate(prometheus_tsdb_compaction_chunk_size_bytes_sum{job="kps-prometheus"}[1d])
  / rate(prometheus_tsdb_compaction_chunk_samples_sum{job="kps-prometheus"}[1d])
# mémoire par série active
process_resident_memory_bytes{job="kps-prometheus"} / on (pod) prometheus_tsdb_head_series{job="kps-prometheus"}
# disque projeté pour 15 jours
rate(prometheus_tsdb_head_samples_appended_total{job="kps-prometheus"}[1d]) * 15 * 86400
  * on (pod) (rate(prometheus_tsdb_compaction_chunk_size_bytes_sum{job="kps-prometheus"}[1d])
              / rate(prometheus_tsdb_compaction_chunk_samples_sum{job="kps-prometheus"}[1d]))
```

`prometheus_engine_query_duration_seconds` est un **résumé** (étiquette `quantile`, par `slice`) : pas de `histogram_quantile`.

*2-3. Disque et mémoire* : voir [`dimensionnement.md`](fichiers/M21-E30/medisphere/docs/observabilite/metriques/dimensionnement.md) (ordres de grandeur du lab de la rédaction : ~150 000 séries, ~5 000 échantillons/s, ~1,3 o/échantillon, ~10 Kio par série tout compris → 8 à 9 Go de blocs pour 15 jours, budget de 300 000 séries pour 3 Gio). Remplace par tes mesures.

*4. Garde-fous* : `retentionSize: 30GB` sous le volume de 40 Gio, `enforcedSampleLimit: 50000` (plus grosse cible × 2,5), `enforcedLabelLimit: 40`, `enforcedLabelValueLengthLimit: 512`, `enforcedBodySizeLimit: 50MB`, `query: {maxSamples: 20000000, timeout: 1m, maxConcurrency: 10}`, mémoire `requests: 2Gi`, `limits: 3Gi` ; Thanos Query : `--store.limits.request-samples`, `--store.limits.request-series`, `--query.max-concurrent`, et `--query.timeout=1m` qui **remplace** celui d'E24 (une option répétée empêche le démarrage : relevé sur Thanos 0.42.4, « flag 'query.timeout' cannot be repeated »). Juste après la synchronisation :

```
admin@adm01:~$ curl -s -G http://prometheus.apps.par1.medisphere.internal:9090/api/v1/query \
    --data-urlencode 'query=sum(increase(prometheus_target_scrapes_exceeded_sample_limit_total[15m]))' | jq -r '.data.result[0].value[1]'
0
```

*5. Essai* : dans `wb-essais`, un pod `busybox` qui génère un fichier de 60 000 lignes (`essai_cardinalite{id="N"} 1`) et le sert par `httpd`, un PodMonitor temporaire étiqueté `medisphere.internal/supervision: "oui"`. Dans l'interface (*Targets* de Thanos Query ou d'un pod Prometheus) : cible `down`, erreur « sample limit exceeded » ; `prometheus_target_scrapes_exceeded_sample_limit_total` augmente ; rien de la collecte n'est gardé. Supprime le PodMonitor et le pod. (Si `wb-essais` est collecté par la politique `collecte-prometheus` d'E07 seulement pour les espaces d'équipe, ajoute l'autorisation le temps de l'essai, ou fais l'essai dans un espace d'équipe de **dev**.)

*6. Alertes* : [`capacite-prometheus.yaml`](fichiers/M21-E30/observabilite/regles/capacite-prometheus.yaml) (séries > 80 % du budget, limite d'échantillons atteinte, mémoire > 85 % de la limite, rétention par taille déclenchée, volume < 10 % libre) ; [tests](fichiers/M21-E30/observabilite/tests/capacite-prometheus.test.yaml) (les annotations utilisent `humanize`/`humanizePercentage` : le test vérifie aussi leur rendu, « 260k », « 90% »).

*7. Dimensionnement et SLO* : la question du 28/15 jours a trois réponses (rétention locale à 29 jours, Thanos Ruler, accepter et écrire) ; la décision du corrigé est d'accepter et d'écrire pour le lab, avec la rétention à 29 jours recommandée en production réelle (`dimensionnement.md` §4).

**Explications**

La mémoire de Prometheus suit le nombre de **séries actives** (tête : index et morceaux en cours), pas le nombre d'échantillons ; le disque suit les **échantillons** (et la compression : ~1 à 2 octets par échantillon). Les limites imposées sont des disjoncteurs : elles transforment une explosion de cardinalité (qui ferait tomber Prometheus **et** son réplica, puisqu'ils collectent la même cible) en une cible en échec, visible et attribuable. `retentionSize` protège le volume ; `retention` (durée) reste la règle normale.

**Alternatives**
- Limites par moniteur seulement (`sampleLimit` dans chaque ServiceMonitor, E14) : dépend de la discipline de chaque équipe ; les limites imposées s'appliquent à tous.
- Répartition (`shards`) : divise les séries par Prometheus, complique les règles (chaque shard ne voit qu'une partie).
- Agent mode + stockage central (remote write) : déplace le problème vers le récepteur.

**Pièges classiques**
- `retentionSize` égale à la taille du volume : le WAL et la compaction n'ont plus de place.
- `enforcedSampleLimit` posée au doigt mouillé (10 000) : kube-state-metrics tombe, avec lui toutes les alertes de Kubernetes.
- Lire `prometheus_engine_query_duration_seconds` comme un histogramme.
- Oublier que deux réplicas doublent la mémoire **réservée** sur les travailleurs.

**En production chez MédiSphère**
Revue de capacité mensuelle (tendance des séries par équipe : `count by (equipe) ({__name__=~".+"})` sur Thanos, une fois par mois, pas dans un tableau) ; budget de séries par équipe annoncé et suivi ; tests de charge de Prometheus avant chaque nouvelle équipe ou nouveau cluster.

---

### M21-E31 — ADR : l'architecture de supervision de MédiSphère

**Réponse attendue**

Exemple complet : [`ADR-0210-architecture-supervision.md`](fichiers/M21-E31/medisphere/docs/observabilite/metriques/adr/ADR-0210-architecture-supervision.md). Ce qui doit y être :

- **Contexte** factuel : l'incident, les exigences (dont 2 ans et la souveraineté), les contraintes du lab et de l'équipe, le périmètre hors cluster.
- **Quatre options** au moins, comparées sur les mêmes critères. Faits vérifiés pour octobre 2026 : Mimir 3 active l'ingestion par **Kafka** par défaut dans son chart 6.x (une dizaine de composants : disproportionné pour le lab) et est sous **AGPLv3** ; VictoriaMetrics est sobre, Apache 2.0, mais sans stockage objet en édition libre (le disque des `vmstorage` ; `vmbackup` vers S3 n'est qu'une sauvegarde) et son langage MetricsQL diffère légèrement de PromQL ; Bitnami a retiré son catalogue d'images gratuites en 2025 (d'où les manifestes Thanos écrits à la main) ; un Prometheus seul sur VM ne tient ni la redondance ni la conservation.
- **Décision** et **justification** reliées aux exigences (dont RGW plutôt que `s3-01`, et le témoin).
- **Conséquences négatives avec leur action** : double collecte (budget de séries), pas de `/federate` sur Thanos Query (sonde du témoin), rétention locale et SLO, Compactor unique (alerte critique), absence d'authentification (filtrage réseau, M24), domaine de panne commun `pve01` (accepté, F5), dépendance au RGW (15 jours de marge), montées de version coordonnées.
- **Conditions de révision** observables (seuils de séries, nombre de clusters, second site, SSO, besoins du M23).

**Pièges classiques** : un ADR qui décrit ce qui a été fait sans options réelles ; des critères choisis pour faire gagner la solution retenue (seulement ceux où elle est meilleure) ; aucune conséquence négative ; des « avantages » non vérifiés (« Mimir est plus performant »).

---

### M21-E32 — Politique d'alerte et d'astreinte

**Réponse attendue**

Exemple complet : [`politique-alerte.md`](fichiers/M21-E32/medisphere/docs/observabilite/metriques/politique-alerte.md). Contrôle de cohérence avec la configuration (à faire **toi-même** sur tes dépôts) :

| Politique | Configuration qui la porte |
|---|---|
| Gravités `critique`, `avertissement`, `info` | étiquette `gravite` de toutes les règles (E15), réétiquetage de Pyrra (E27) |
| Critique à toute heure → `astreinte@` | route `gravite = critique` → `astreinte-mail` (E06) |
| Avertissement en heures ouvrées → équipe | routes par `equipe` et `active_time_intervals` (E16) |
| Info sans courriel | route vers le récepteur `"null"` ou absence de route (E16) |
| Regroupement, rappel 4 h | `group_by`, `group_wait`, `group_interval`, `repeat_interval` (E06) |
| Inhibitions | `inhibit_rules` (E06, E16) |
| `Watchdog` sans courriel, surveillé par le témoin | route `Watchdog` → `"null"` (E06), RB-215 (E28) |
| Silences ≤ 24 h, auteur, ticket | règle d'usage (Alertmanager ne l'impose pas) : revue mensuelle des silences |

**Pièges classiques** : une politique qui promet ce que la configuration ne fait pas (« jamais de courriel la nuit pour les avertissements » sans `time_intervals`) ; des exemples d'alertes qui n'existent pas ; pas d'escalade sécurité (données de santé : la RSSI est prévenue **immédiatement**) ; pas de revue des alertes, donc une politique qui se dégrade en trois mois.

---

### M21-E33 — Questions de production : supervision

1. **Séries des deux réplicas.** Horodatages de collecte différents (chaque réplica a son propre calendrier de collecte, décalé) ; collectes réussies ou ratées indépendamment (un réplica peut manquer un échantillon, redémarrer) ; valeurs lues à des instants différents (compteurs : deux valeurs différentes au même « moment ») ; règles évaluées à des instants différents. D'où un dédoublonnage par **choix d'un réplica** avec bascule (algorithme *penalty*), et non par fusion échantillon par échantillon (le dédoublonnage 1 pour 1 suppose des données identiques). Un `rate()` sur un mélange naïf des deux séries serait faux.
2. **Réponse partielle.** Un point d'accès (sidecar, Store) n'a pas répondu ou a renvoyé une erreur ; Thanos Query a calculé avec ce qu'il avait. La réponse est juste si l'autre réplica couvrait la période (sidecar perdu) ; elle est **tronquée** si c'était le Store (pas de données anciennes) — sans signe visible dans un graphe. On préfère une erreur pour un calcul engageant (rapport de SLO, analyse de canary, check d'un audit) : paramètre `partial_response=false` (ou `--no-query.partial-response`).
3. **Rétention locale à 6 h.** Les règles et alertes sur des fenêtres plus longues (4 j de Pyrra, `increase[1d]`, `predict_linear` sur 6 h, `absent_over_time` long) ne s'évaluent plus correctement : Prometheus n'évalue que sur sa base locale ; perte de toute autonomie si le RGW est indisponible ; le Store lit plus souvent le stockage objet (requêtes plus lentes pour les tableaux du jour). Et pas d'économie de mémoire : la mémoire dépend des séries actives, pas de la rétention.
4. **Compactor *halted* depuis 3 jours.** En danger : rien d'immédiat. Les blocs bruts continuent d'arriver ; ce qui ne se fait plus : compaction (requêtes plus lentes, plus d'objets), dédoublonnage hors ligne (place ×2), sous-échantillonnage, **rétention** (le compartiment grossit jusqu'au quota RGW, puis les **sidecars** échouent à envoyer : c'est là que des données se perdent, après 15 jours de base locale). Pire réaction : supprimer à la main des blocs « en trop » ou lancer un second Compactor « pour rattraper ».
5. **5 minutes / 30 jours.** 5 min seule : sonne au moindre pic (fausse alerte), et ne dit rien de l'importance pour l'objectif (2 % d'erreurs pendant 5 min ne menace pas un objectif mensuel). 30 jours seule : sonne des jours après le début et reste active des jours après la fin ; un incident massif d'une heure peut passer sous le seuil. Le multi-fenêtres combine importance (longue) et actualité (courte).
6. **Budget épuisé par une panne du RGW.** La panne compte (l'utilisateur ne fait pas la différence : le SLO mesure son expérience). La politique prévoit une exception : panne d'un fournisseur **hors de notre périmètre** → pas de gel si elle est seule en cause, sur décision écrite. Mais le RGW est **notre** infrastructure : pas d'exception automatique ; le gel s'applique (sauf correctifs), et le post-mortem traite la dépendance de MédiAgenda (ou de MédiDoc) au stockage. Argumenter la différence entre « fournisseur externe » et « notre plateforme ».
7. **Watchdog présente, plus de courriel.** Prouvés vivants : collecte, évaluation des règles, sidecar, Thanos Query, réseau témoin → .60. Suspects : Prometheus → Alertmanager (découverte, réseau), Alertmanager lui-même (route, inhibition trop large, silence), l'envoi SMTP (Mailpit, STARTTLS, certificat), la boîte. Le témoin aurait dû le voir par : la sonde `/-/healthy` d'Alertmanager (s'il est arrêté), et le **chemin de secours** (`AlertmanagerFailedToSendAlerts` envoyée aussi à l'Alertmanager témoin, s'il tourne mais n'envoie plus). Un silence trop large ou une route fautive ne se voient **pas** : d'où la revue des silences et les essais de routage en CI.
8. **« Pod redémarré » qui réveille.** Une cause, pas un symptôme : Kubernetes redémarre et l'utilisateur ne voit souvent rien. Proposer : une alerte de **symptôme** (budget d'erreur, disponibilité) qui réveille, et une alerte « redémarrages répétés » en **avertissement** pour l'équipe (heures ouvrées), avec un runbook ; éventuellement une règle d'enregistrement pour le tableau de bord.
9. **`equipe: plateforme` dans une règle d'équipe.** `enforcedNamespaceLabel` force seulement `namespace` (sélecteurs et alertes) : l'étiquette `equipe` reste celle écrite par l'auteur. Défense possible : réétiquetage des alertes dans Prometheus qui **déduit** `equipe` de `namespace` (correspondance espace → équipe) et écrase l'étiquette, ou routage par `namespace` plutôt que par `equipe` ; contrôle en CI du dépôt de l'équipe (kube-linter, conftest) ; revue de MR.
10. **OOMKilled en boucle.** D'abord rétablir la supervision : identifier la cible fautive sans Prometheus (Thanos Query voit encore l'autre réplica… qui tombe aussi : même cible) — regarder `scrape_series_added` et `prometheus_tsdb_head_series` juste avant la chute dans Thanos (blocs ou dernier sidecar vivant), ou la nouvelle version déployée (Argo CD) ; neutraliser la collecte de cette cible par Git (retirer le ServiceMonitor, `metricRelabelings` qui supprime l'étiquette, ou `enforcedSampleLimit` si elle manquait) ; augmenter **temporairement** la limite mémoire pour que la relecture du WAL passe. Ensuite la cause, avec l'équipe : l'étiquette à forte cardinalité dans le code, le test qui l'aurait vue, la limite qui manquait.
11. **`histogram_quantile` et SLO.** Il **estime** un quantile par interpolation linéaire dans un seau, à partir de taux agrégés ; il ne compte pas des requêtes bonnes et mauvaises, et l'erreur peut être grande (seaux larges, 250-500 ms ici). Un SLO compte des événements : `seau(le=seuil) / count`. Pour un tableau, l'estimation suffit à voir une tendance.
12. **Preuve sur 18 mois.** Thanos garde 30 j brut, 180 j à 5 min, 2 ans à 1 h : sur 18 mois, la résolution 1 h ; `increase()` des compteurs reste juste à cette résolution (agrégats de compteurs). Fournir la disponibilité calculée par Thanos Query (`sum(increase(…[30d]))` par mois, `max_source_resolution=1h`), et dire les limites : trous de collecte (vérifiés par `up` et la présence des blocs), changements de définition du SLO dans la période (historique Git), mesure côté serveur seulement. Confiance : bonne sur les ordres de grandeur, à accompagner des incidents documentés (post-mortems) et des chiffres de la sonde externe.
13. **Inhibée, silencieuse, récepteur sans intégration.** Inhibée : une autre alerte active rend celle-ci redondante (nœud injoignable → pods de ce nœud) ; automatique, tant que la source est active. Silence : décision humaine, bornée dans le temps (maintenance planifiée, alerte connue en cours de traitement). Récepteur sans intégration (`"null"`) : choix de configuration permanent, l'alerte existe mais ne notifie personne (Watchdog, `InfoInhibitor`, alertes `info` consultées dans les tableaux). Mauvais usages : un silence permanent à la place d'une correction de règle ; une inhibition qui couvre des alertes sans rapport.

---

### M21-E34 — Un diagnostic en temps limité

**Démarche de diagnostic**

Le script d'injection est [`pannes/break-E34.sh`](pannes/break-E34.sh) (lancé par `lab/bin/break 21 34`, comme les pannes du palier 4). Dans les deux variantes, un trafic de testeurs réaliste tourne en permanence (Job `trafic-recette` dans `wb-pannes`, par la Gateway : créneaux de trois praticiens, liste des rendez-vous, une création toutes les 10 s). La démarche est la même pour les deux, et c'est elle qui compte.

*Symptôme, chiffré (5 min)* : tableau RED de MédiAgenda (E19) filtré sur `mediagenda-recette`, ou directement :

```promql
histogram_quantile(0.95, sum by (le) (rate(mediagenda_http_request_duration_seconds_bucket{namespace="mediagenda-recette", route!~"/sante|/pret|/metrics"}[5m])))
sum by (code) (rate(mediagenda_http_requests_total{namespace="mediagenda-recette", route!~"/sante|/pret|/metrics"}[5m]))
sum by (route, methode) (rate(mediagenda_http_requests_total{namespace="mediagenda-recette"}[5m]))
```

Note l'heure de début de la dégradation (`[5m]` sur un graphe d'1 h), la latence avant/pendant, les codes.

*Hypothèses dans l'ordre* (méthode RED puis USE, de l'utilisateur vers les ressources) : (1) un changement (Argo CD, Rollout) — les métriques d'Argo CD (`argocd_app_sync_total` si collectées) ou `kube_pod_created` / `kube_replicaset_created` des pods de l'API ; (2) **la demande** a-t-elle changé (débit par route) ; (3) les **ressources** de l'API (CPU, *throttling* `container_cpu_cfs_throttled_periods_total`, mémoire, redémarrages) ; (4) les **dépendances** : Valkey (`mediagenda_cache_total` par `resultat`), PostgreSQL (métriques de CloudNativePG : `cnpg_backends_total` par `state` et `application_name`, `cnpg_backends_waiting_total`, `cnpg_backends_max_tx_duration_seconds`) ; (5) le nœud (USE : CPU, PSI).

**Variante 1 — un client en boucle contourne le cache.**
- Débit : `/api/v1/creneaux` passe de quelques requêtes par seconde à plusieurs dizaines ; les autres routes ne bougent pas.
- Cache : `sum by (resultat) (rate(mediagenda_cache_total{namespace="mediagenda-recette"}[5m]))` : les *miss* explosent (chaque appel demande un praticien inconnu : `partenaire-NNNN`, mais tu ne vois **pas** la valeur du paramètre — seulement le ratio).
- Conséquences : CPU de l'API (et *throttling* si limitée), connexions et charge de PostgreSQL (`cnpg_backends_total{state="active"}`), latence de **toutes** les routes.
- Qui ? Les métriques de l'application n'ont pas l'adresse du client. Les métriques de conteneurs, si : `topk(5, sum by (namespace, pod) (rate(container_network_transmit_bytes_total[5m])))` met en tête un pod `export-creneaux-…` de `wb-pannes` ; ou les métriques HTTP de Hubble si tu les as activées en E20 (`hubble_http_requests_total` par `source`/`destination`, selon ta configuration).
- **Cause racine** : un client (« export des créneaux » d'un partenaire, `wb-pannes`) interroge `/api/v1/creneaux` en boucle avec des praticiens toujours différents, ce qui rend le cache inutile et reporte toute la charge sur PostgreSQL et l'API.
- Action : arrêter le client (ici : supprimer le Job `export-creneaux` de `wb-pannes`, objet de panne hors GitOps ; en vrai : bloquer le client à la Gateway et le contacter). Vérifier le retour : débit, ratio de *miss*, p95.
- Prévention : limitation de débit par client à la Gateway ; alerte sur le ratio de *miss* (la règle d'équipe `MediagendaCacheInefficace` d'E29 le fait, en `info`) et sur une hausse brutale du débit (`rate[5m] > 3 × rate[1h] offset 1d`) ; validation du paramètre `praticien` côté API (liste connue) ; un SLO de recette pour voir le budget brûler.

**Variante 2 — une transaction longue verrouille la table des rendez-vous.**
- Débit stable ; latence en hausse d'abord sur `POST /api/v1/rendez-vous` (les créations attendent), puis sur **toutes** les routes (les fils de travail de l'API, occupés par des créations bloquées, s'épuisent), puis des 5xx ou des délais dépassés côté client ; `/pret` peut échouer (pods non prêts).
- PostgreSQL : `cnpg_backends_waiting_total` > 0 et qui grandit ; `cnpg_backends_total{state="active"}` en hausse ; `max(cnpg_backends_max_tx_duration_seconds{namespace="mediagenda-recette"}) by (application_name)` montre une transaction ouverte depuis le début de l'incident, avec `application_name="export-rapports"` (et `state="active"` pour la session qui dort dans `pg_sleep`).
- CPU **bas** : ce n'est pas une saturation, c'est une attente (différence clé avec la variante 1).
- **Cause racine** : une session `export-rapports` a ouvert une transaction qui tient un verrou `SHARE` sur `rendez_vous` (les lectures passent, les écritures attendent), et ne se termine pas.
- Action (après avoir écrit la cause) : terminer la session (`kubectl cnpg psql mediagenda-db -n mediagenda-recette` puis `SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE application_name = 'export-rapports';`, ou `lab/bin/break 21 34 --annuler`). Vérifier : `cnpg_backends_waiting_total` à 0, p95 revenue.
- Prévention : `lock_timeout` et `statement_timeout` sur le rôle de l'application et des exports, `idle_in_transaction_session_timeout` ; un utilisateur PostgreSQL distinct pour les exports, en lecture seule sur une **réplique** ; alerte sur `cnpg_backends_waiting_total > 0` pendant 5 min et sur `cnpg_backends_max_tx_duration_seconds > 300` (hors sauvegardes) ; délai côté application pour ne pas épuiser les fils de travail.

*Journal* : modèle [`ressources/E34-diagnostic/journal-modele.md`](../ressources/E34-diagnostic/journal-modele.md) ; le check y cherche une chronologie horodatée, des requêtes PromQL, un symptôme chiffré, les mots de la cause de **ta** variante, une action et une prévention.

**Pièges classiques**
- Partir des ressources (CPU des nœuds) au lieu de l'utilisateur : la variante 2 a un CPU **bas**.
- S'arrêter à la conséquence (« PostgreSQL est chargé », « l'API est lente ») au lieu de la cause (qui charge, qui verrouille).
- Chercher l'adresse du client dans les métriques de l'application (elle n'y est pas, et ne doit pas y être : cardinalité).
- Oublier que le trafic de recette est faible : un p95 calculé sur 10 requêtes par minute saute d'une minute à l'autre ; regarde aussi le p50 et les comptes.
- Agir avant d'avoir écrit la cause (règle de l'exercice, et règle de l'astreinte : on garde la preuve).

**En production chez MédiSphère**
Les deux variantes sont des incidents classiques ; leurs préventions (limitation de débit à l'entrée, délais PostgreSQL, alertes sur les attentes de verrous et le ratio de cache) deviennent des tickets, et la requête « qui consomme le réseau de l'API » une règle d'enregistrement du tableau RED.
