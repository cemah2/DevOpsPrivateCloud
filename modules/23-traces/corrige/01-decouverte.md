# Module 23 — Traces et profilage : palier 1 — Découverte — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Ce corrigé suit l'ordre de l'énoncé. Le questionnaire (E01) est argumenté et les QCM expliquent pourquoi les autres options sont fausses. Les fichiers complets sont dans [`fichiers/`](fichiers/), exercice par exercice : `observabilite/` reproduit `plateforme/observabilite`, `gitops/` `plateforme/gitops`, `charts-miroir/` les entrées de `charts.yaml`, `k8s/` `plateforme/k8s`, `deploiement-mediagenda/` `mediagenda/deploiement`, `mediagenda-api/` des **correctifs** (`git apply`) sur `mediagenda/api`, `medisphere/` la documentation. Un fichier n'apparaît que dans l'exercice qui le crée ou le modifie.

**Ce qui a été vérifié à la rédaction** :
- chart de l'opérateur **0.126.1** rendu par `helm template` (Helm 4.3.1) avec `otel/operateur/values.yaml` (images de Harbor, ServiceMonitor étiqueté, certificats par cert-manager), CRD lues dans le rendu (`OpenTelemetryCollector` v1beta1 servie et stockée, `Instrumentation` v1alpha1) ; source de l'opérateur 0.161.0 lue pour les noms des Services (`<nom>-collector`, `-headless`, `-monitoring`), les étiquettes de sélection (`app.kubernetes.io/instance: <espace>.<nom>`) et `internalTrafficPolicy: Local` posé sur le Service d'un Collector en mode `daemonset` ;
- configurations des Collectors extraites des CR et validées par **`otelcol-contrib validate` 0.161.0** ; agent et passerelle exécutés localement : métriques internes `otelcol_receiver_accepted_spans`, `otelcol_exporter_sent_spans`, `otelcol_receiver_refused_spans` (sans suffixe `_total` en texte), alias dépréciés signalés au démarrage ; span OTLP/HTTP JSON envoyée par `curl` acceptée (`{"partialSuccess":{}}`) ; `telemetrygen` v0.161.0 (options vérifiées dans `--help`) ;
- tous les manifestes : `kustomize build` (5.8.3) et `kubeconform -strict` avec les schémas des CRD de l'opérateur 0.161, de Cilium, de prometheus-operator et d'Argo CD ;
- chart Tempo **3.2.1** rendu avec `tempo/values.yaml` ; `tempo.yaml` extrait de la ConfigMap rendue et validé par **`tempo -config.verify`** de Tempo **3.1.1** (une clé fausse est bien refusée) ; Tempo 3.1.1 monolithique lancé en local : blocs `single-tenant/<uuid>/data.parquet` au format **vParquet5**, `meta.json`, `index.json.gz` ; recherche disponible ≈ 30 s après l'envoi ;
- MédiAgenda instrumentée (correctif de M23-E04 appliqué sur `apps/mediagenda` **plus** le correctif `request_id` de M22-E06) : `uv run pytest` (34 tests), `ruff check`, `ruff format --check` ; exécutée contre PostgreSQL 16 et Redis 7 locaux, spans reçues par un Collector puis Tempo : noms, portées, attributs relevés tels quels (anciennes et nouvelles conventions selon `OTEL_SEMCONV_STABILITY_OPT_IN`) ; FastAPI 0.142.4 lu : sa télémétrie native s'efface devant l'instrumentation contrib et avertit sans `telemetry={"auto_configure": False}` ;
- les 11 requêtes de `E05.traceql` et celles des checks exécutées sur Tempo 3.1.1 avec des données réelles de MédiAgenda ; `check-E05.sh` rejoué contre ce Tempo (16 OK) ;
- scripts : `shellcheck -x` et `bash -n` ; tous les checks exécutés à vide (sans lab) sous `set -euo pipefail` : aucun faux OK, aucune erreur d'exécution.

**Points non testés en conditions réelles**, à vérifier sur ton lab et à signaler s'ils diffèrent :
- le déploiement dans `k8s-par1` (webhooks de l'opérateur avec cert-manager, Pod Security `restricted` des Collectors et de Tempo, politiques Cilium, LB IPAM de 10.10.41.63) : l'environnement de rédaction n'avait pas de cluster ; les sorties montrées sont **représentatives** ;
- l'entrée de l'image `telemetrygen` (`/telemetrygen` attendu en point d'entrée) ;
- la recherche par le mandataire de la source Grafana (`/api/datasources/proxy/uid/tempo/…`) avec le jeton Viewer : documentée, utilisée par les checks avec un repli sur le mandataire de l'API Kubernetes ;
- l'écriture des blocs dans le RGW (TLS par `tls_ca_path`, style chemin) : configuration validée par Tempo, pas exécutée contre Ceph.

---

### M23-E01 — Test de positionnement : traces distribuées

**Barème** : 2 points par question (2 = complet et justifié ; 1 = idée juste mais incomplète ; 0 = faux ou blanc), sur 28. En dessous de 14, relis les « Concepts clés » de l'introduction avant E04. Les questions 1 à 3 sont reprises en E04-E05, 4 à 6 en E06 et E20, 7-8 en E02, 9 en E09, 10 en E02 et E24, 11 en E04-E05, 12 en E07, 13 en E08, 14 en E10.

**1. Trace, span, racine.** Une trace est l'arbre (plus exactement le graphe orienté) des opérations d'une requête, de son entrée dans le système à sa dernière action ; une span est une de ces opérations ; la span racine n'a pas de parent (la première, souvent la span serveur de l'entrée). Une span porte : `trace_id`, `span_id`, `parent_span_id`, nom, *kind*, début et fin (donc durée), statut (et message), attributs, événements, liens vers d'autres spans, et elle appartient à une ressource et à une portée.

**2. Réponse B.** La requête reçue est une span `SERVER` ; chaque appel sortant (deux requêtes SQL, deux `DEL` Valkey) est une span `CLIENT`, fille de la span serveur ou d'une span `INTERNAL` intermédiaire (l'invalidation du cache en E04). A est faux : on perdrait la durée de chaque appel, c'est-à-dire tout ce qui permet de dire où passe le temps. C est faux : ce ne sont pas des opérations internes, et sœurs elles perdraient le lien à la requête. D est faux : le `request_id` (M22) relie des lignes de journal, pas des spans ; une requête = une trace.

**3. Ressource et span.** La ressource décrit **l'émetteur** et vaut pour toutes ses spans : `service.name`, `k8s.pod.name`, `deployment.environment.name` en sont. L'attribut de span décrit **l'opération** : `http.response.status_code`. En TraceQL : `resource.service.name`, `span.http.response.status_code`. Mettre `deployment.environment.name` sur chaque span serait du volume inutile ; mettre le code de réponse sur la ressource n'a pas de sens.

**4. `traceparent`.** `00-<trace_id 32 hex>-<span_id du parent 16 hex>-<drapeaux 2 hex>` (version, identifiants, `01` = échantillonné). L'instrumentation **client** de MédiAgenda (httpx) l'écrit dans la requête sortante, avec le `span_id` de sa span `CLIENT` ; l'instrumentation **serveur** de MédiDoc (otelhttp) le lit et crée sa span `SERVER` comme fille. Si un relais le supprime, MédiDoc démarre une **nouvelle trace** : deux morceaux, aucun lien, et la span `CLIENT` de MédiAgenda semble durer sans rien dessous (M23-E20).

**5. Réponse B.** B ne trouve pas d'en-tête B3, il crée un nouveau contexte : deux traces. A est faux : les formats portent la même information mais pas dans les mêmes en-têtes ; un service ne lit que ce que ses propagateurs connaissent (on peut en configurer plusieurs). C est faux : un contexte absent n'est pas une erreur HTTP. D est faux : aucun outil ne rattache des spans par l'heure.

**6. Baggage.** Des paires clé-valeur propagées avec le contexte, à tous les services en aval (en-tête `baggage`), lisibles par le code et recopiables en attributs. Usage : un canal (`web`, `mobile`), un identifiant de locataire, un drapeau d'essai, pour filtrer ou décider en aval. Risque : tout ce qui y est mis voyage **en clair** dans chaque appel, y compris vers des tiers, et finit dans des journaux de mandataires : jamais d'identifiant de patient. D'où une liste blanche de clés.

**7. Pourquoi un Collector.** Découpler l'application du stockage (changer de Tempo à Jaeger sans redéployer les applications) ; regrouper et compresser les envois (moins de connexions) ; tamponner et réessayer quand le stockage est lent ou absent ; enrichir (métadonnées Kubernetes que l'application ignore) ; filtrer et masquer avant stockage (sondes, données sensibles, M23-E10) ; échantillonner en queue (M23-E09) ; ses propres métriques (combien reçu, refusé, perdu) ; un seul point de sécurité (TLS, authentification) vers l'extérieur.

**8. Agent et passerelle.** L'agent (DaemonSet) est au plus près de l'application : envoi local et rapide, il voit l'adresse de connexion du pod (enrichissement `k8sattributes` fiable), il protège l'application d'une passerelle lente (file d'attente) et peut filtrer dès le nœud. La passerelle (Deployment) a la vue d'ensemble : échantillonnage en queue (toutes les spans d'une trace), export unique vers le stockage, entrée pour les émetteurs hors cluster, configuration lourde en un seul endroit.

**9. Réponse B.** Seul un Collector qui a vu **toute** la trace sait qu'elle contient une erreur. A est faux : en tête, la décision précède l'erreur, on garderait 10 % des erreurs. C est faux : la rétention supprime selon l'âge, pas selon le contenu. D est faux : Grafana filtre l'affichage, les données sont déjà stockées (et payées).

**10. OTLP.** *OpenTelemetry Protocol* : messages Protobuf (ou JSON) pour traces, métriques, journaux et profils ; transport gRPC (port 4317) ou HTTP (4318, chemins `/v1/traces`…). Normalisé : un seul format entre SDK, Collectors et stockages de tous les éditeurs ; c'est ce qui permet de changer de stockage sans réinstrumenter (exigence de Claire).

**11. Conventions sémantiques.** Des noms et des valeurs d'attributs communs à tous les langages et outils. Les conventions HTTP (puis base de données) ont été **stabilisées en renommant** des attributs (`http.status_code` → `http.response.status_code`, `http.method` → `http.request.method`, `db.system` → `db.system.name`, `db.statement` → `db.query.text`). Des instrumentations plus anciennes, ou réglées par défaut (Python sans `OTEL_SEMCONV_STABILITY_OPT_IN`), émettent les anciens : une requête sur un seul nom manque la moitié des spans, et une règle de masquage aussi (M23-E10). On choisit un jeu de noms et on l'impose.

**12. Dans le code ou automatique.** Dans le code : spans et attributs **métier**, attributs maîtrisés (données de santé), versions figées et testées en CI ; mais du travail par application et par langage, et une compétence à maintenir. Automatique : immédiat, sans toucher au code, uniforme ; mais seulement les spans des bibliothèques (pas de métier), versions décidées par l'outil (un agent qui change sans qu'on l'ait testé), surcoût et fragilité au démarrage, droits élevés pour certains langages (eBPF pour Go), double instrumentation possible.

**13. Métriques et traces.** Une span n'est pas une métrique, mais on peut **compter** des spans pour en tirer des métriques (M23-E13), avec le biais de l'échantillonnage. Un **exemplar** est un échantillon d'une série (ex. une observation de l'histogramme de latence) accompagné d'étiquettes supplémentaires, ici le `trace_id` de la requête observée : Grafana en fait un lien du graphe à la trace. Journal → trace : écrire `trace_id` (et `span_id`) dans chaque ligne de journal émise pendant la requête, puis en faire un lien (M23-E08).

**14. Pourquoi les traces sont plus dangereuses.** Une métrique a des étiquettes fermées et peu de valeurs ; une trace porte, **par requête**, des valeurs libres : URL avec paramètres (`?nom=compte-rendu-dupont.pdf`), texte des requêtes SQL (littéraux si la requête n'est pas paramétrée), en-têtes capturés (`Authorization`, cookies), messages d'exception (« patient Jeanne Dupont introuvable »), noms de span construits avec une variable, *baggage*. D'où les interdits écrits (E04), les réglages des instrumentations et le filet du Collector (E10).

---

### M23-E02 — L'opérateur OpenTelemetry et le Collector

**Solution**

1. **Le chart.** Entrée de `charts.yaml` (forme du M20-E13, avec `usage`) : [`charts-miroir/charts-M23.yaml`](fichiers/M23-E02/charts-miroir/charts-M23.yaml). Empreinte relevée puis vérifiée :
   ```
   admin@adm01:~$ curl -s https://open-telemetry.github.io/opentelemetry-helm-charts/index.yaml \
     | yq '.entries."opentelemetry-operator"[] | select(.version == "0.126.1") | .digest'
   8bd4312051bea439c0471826341cc875298373e938cd33e3ace82c11a4e42fca
   admin@adm01:~$ helm pull opentelemetry-operator --repo https://open-telemetry.github.io/opentelemetry-helm-charts --version 0.126.1 -d /tmp/m23
   admin@adm01:~$ sha256sum /tmp/m23/opentelemetry-operator-0.126.1.tgz
   ```
   MR sur `plateforme/charts-miroir`, pipeline (recopie, signature) ; `helm show values oci://registry.par1.medisphere.internal/charts/opentelemetry-operator --version 0.126.1` pour la suite.
2. **L'opérateur.** [`otel/operateur/values.yaml`](fichiers/M23-E02/observabilite/otel/operateur/values.yaml) et l'Application [`opentelemetry-operator.yaml`](fichiers/M23-E02/gitops/plateforme/opentelemetry-operator.yaml) (vague −1, `ServerSideApply`, `CreateNamespace`). Rendu local :
   ```
   admin@adm01:~/src/observabilite$ helm template opentelemetry-operator oci://registry.par1.medisphere.internal/charts/opentelemetry-operator \
     --version 0.126.1 -n opentelemetry-operator-system -f otel/operateur/values.yaml > /tmp/m23/operateur.yaml
   admin@adm01:~/src/observabilite$ grep -E '^\s+image:' /tmp/m23/operateur.yaml | sort -u
           image: "registry.par1.medisphere.internal/ghcr/open-telemetry/opentelemetry-operator/opentelemetry-operator:0.161.0"
         image: "registry.par1.medisphere.internal/dockerhub/library/busybox:1.37"
   ```
   Après synchronisation : `kubectl get crd | grep opentelemetry.io` (quatre CRD : `opentelemetrycollectors`, `instrumentations`, `opampbridges`, `targetallocators`), `kubectl get mutatingwebhookconfigurations,validatingwebhookconfigurations | grep opentelemetry`, `kubectl -n opentelemetry-operator-system get certificate` (`READY True`).
3. **L'agent.** [`espace.yaml`](fichiers/M23-E02/observabilite/otel/espace.yaml), [`rbac-agent.yaml`](fichiers/M23-E02/observabilite/otel/rbac-agent.yaml), [`otel-agent.yaml`](fichiers/M23-E02/observabilite/otel/otel-agent.yaml). Les points qui comptent : `endpoint: 0.0.0.0:4317` (sinon `localhost`), `memory_limiter` en premier, `k8sattributes` avec `filter.node_from_env_var: K8S_NODE_NAME` (variable posée depuis `spec.nodeName`) et `pod_association` par la connexion, `resourcedetection` (`env`, `k8snode`), `resource/cluster` (`k8s.cluster.name=k8s-par1`), `batch` en dernier, file d'attente et reprises vers la passerelle, lecteur Prometheus sur `0.0.0.0:8888`, `GOMEMLIMIT` sous la limite du conteneur.
4. **La passerelle.** [`otel-passerelle.yaml`](fichiers/M23-E02/observabilite/otel/otel-passerelle.yaml), avec `debug` en `basic`, `sampling_initial: 5`, `sampling_thereafter: 200`.
5. **Le réseau.** [`service-otlp-externe.yaml`](fichiers/M23-E02/observabilite/otel/service-otlp-externe.yaml), [`politiques.yaml`](fichiers/M23-E02/observabilite/otel/politiques.yaml), [`telemetrie-applications.yaml`](fichiers/M23-E02/observabilite/otel/telemetrie-applications.yaml), [`servicemonitor.yaml`](fichiers/M23-E02/observabilite/otel/servicemonitor.yaml), [`racine-medisphere.yaml`](fichiers/M23-E02/observabilite/otel/racine-medisphere.yaml) (servira à Tempo), la [`kustomization.yaml`](fichiers/M23-E02/observabilite/otel/kustomization.yaml) et l'Application [`otel.yaml`](fichiers/M23-E02/gitops/plateforme/otel.yaml). Contrôle avant MR :
   ```
   admin@adm01:~/src/observabilite$ kustomize build otel | kubeconform -strict -summary \
     -schema-location default -schema-location '<CATALOGUE-DE-SCHEMAS>/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
   Summary: 12 resources found in 1 file - Valid: 12, Invalid: 0, Errors: 0, Skipped: 0
   ```
   (Catalogue des schémas des CRD : celui que tu utilises depuis le M20 ; à défaut, ceux de `datreeio/CRDs-catalog` et, pour `opentelemetry.io`, des schémas tirés des CRD du chart.)
6. **Ce que l'opérateur fabrique.**
   ```
   admin@adm01:~$ kubectl -n traces get daemonset,deployment,service,configmap -l app.kubernetes.io/managed-by=opentelemetry-operator
   NAME                                  DESIRED   CURRENT   READY ...
   daemonset.apps/otel-agent-collector   3         3         3
   NAME                                       READY   UP-TO-DATE   AVAILABLE
   deployment.apps/otel-passerelle-collector  1/1     1            1
   NAME                                           TYPE        CLUSTER-IP     PORT(S)
   service/otel-agent-collector                   ClusterIP   10.96.41.12    4317/TCP,4318/TCP
   service/otel-agent-collector-headless          ClusterIP   None           4317/TCP,4318/TCP
   service/otel-agent-collector-monitoring        ClusterIP   10.96.88.3     8888/TCP
   service/otel-passerelle-collector              ClusterIP   10.96.17.40    4317/TCP,4318/TCP
   service/otel-passerelle-collector-headless     ClusterIP   None           4317/TCP,4318/TCP
   service/otel-passerelle-collector-monitoring   ClusterIP   10.96.120.9    8888/TCP
   NAME                                            DATA
   configmap/otel-agent-collector-1a2b3c4d          1
   configmap/otel-passerelle-collector-5e6f7a8b     1
   admin@adm01:~$ kubectl -n traces get svc otel-agent-collector -o jsonpath='{.spec.internalTrafficPolicy}{"\n"}'
   Local
   ```
   L'opérateur déduit les **ports** des Services de la configuration (récepteurs, lecteur de métriques), nomme la ConfigMap d'après l'empreinte de la configuration (un changement de configuration redéploie les pods) et, pour un DaemonSet, pose `internalTrafficPolicy: Local` : un pod n'est servi que par l'agent de son nœud ; s'il n'y en a pas, la connexion échoue au lieu d'aller ailleurs (c'est voulu : l'agent du nœud est la seule source fiable de l'adresse du pod).
7. **Des spans.**
   ```
   admin@adm01:~$ kubectl apply -f ~/DevOpsPrivateCloud/modules/23-traces/ressources/E02-essai/telemetrygen.yaml
   admin@adm01:~$ kubectl -n traces logs deploy/otel-passerelle-collector | grep -m3 'Traces'
   … info Traces {… "otelcol.component.id": "debug", … "resource spans": 1, "spans": 3}
   ```
   Dans Prometheus : `sum by (pod) (rate(otelcol_receiver_accepted_spans{namespace="traces"}[5m]))` montre l'agent du nœud du Job et la passerelle (≈ 15 spans/s : 5 traces/s de 3 spans). Une span à la main :
   ```
   admin@adm01:~$ debut=$(date +%s%N); fin=$((debut + 250000000)); tid=$(openssl rand -hex 16); sid=$(openssl rand -hex 8)
   admin@adm01:~$ curl -sS http://10.10.41.63:4318/v1/traces -H 'Content-Type: application/json' -d '{"resourceSpans":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"essai-adm01"}}]},"scopeSpans":[{"scope":{"name":"curl"},"spans":[{"traceId":"'"$tid"'","spanId":"'"$sid"'","name":"essai-otlp-http","kind":2,"startTimeUnixNano":"'"$debut"'","endTimeUnixNano":"'"$fin"'"}]}]}]}'
   {"partialSuccess":{}}
   ```
   En OTLP/JSON, `traceId` et `spanId` sont en hexadécimal (pas en base64 comme dans le JSON générique de Protobuf) ; `kind` 2 = `SERVER`.
8. [`architecture.md`](fichiers/M23-E02/medisphere/docs/observabilite/traces/architecture.md), et dans `matrice-flux-cluster.md` les lignes : applications → `otel-agent` 4317/4318 ; `otel-agent` → `otel-passerelle` 4317 ; `otel-agent` → API 6443 ; MGMT → 10.10.41.63 4317/4318 ; Prometheus → 8888. Aucune règle de bordure : MGMT joint déjà tout le lab (M00).

**Explications**

L'opérateur transforme un CR de haut niveau en objets Kubernetes ordinaires et les **réconcilie** : modifier le DaemonSet à la main est annulé, on modifie le CR (par Git). Ses webhooks valident les CR (une configuration invalide est refusée par l'API, pas découverte au redémarrage) et injecteront l'auto-instrumentation (E07) ; leur certificat vient de cert-manager, déjà là (M15), plutôt que d'un certificat généré par Helm qui expirerait sans `helm upgrade`.

L'ordre des processeurs est **le** point de configuration : `memory_limiter` d'abord, parce qu'il refuse les données (le client réessaie, rien n'est perdu) avant qu'elles occupent la mémoire ; `batch` en dernier, parce qu'il regroupe ce qui sort. `k8sattributes` dans l'agent plutôt que dans la passerelle : seul l'agent voit l'adresse du pod émetteur (la passerelle voit celle de l'agent). Son RBAC est en lecture, sur tout le cluster (les pods de toutes les équipes), mais le filtre par nœud réduit ce qu'il garde en mémoire.

La politique de sortie est une **politique de cluster** portée par la plateforme : les espaces applicatifs sont en refus par défaut (M15) et la politique du chart de MédiAgenda ne laisse sortir que DNS, PostgreSQL et Valkey. `enableDefaultDeny.egress: false` (Cilium 1.15 et plus) évite le piège inverse : une politique qui sélectionne un pod sans politique de sortie le ferait passer en refus par défaut.

**Alternatives**

- **Chart `opentelemetry-collector` sans opérateur** : un DaemonSet et un Deployment rendus par Helm, tout aussi valables ; l'opérateur apporte la validation des CR, la gestion des Services et l'auto-instrumentation (E07). Le workbook prend l'opérateur pour pratiquer les deux.
- **Agent en `hostNetwork`** avec envoi à `$(HOST_IP):4317` : classique, mais il faut ouvrir l'hôte, Pod Security `privileged` ou `baseline`, et Cilium voit alors l'identité « hôte » (les politiques par étiquettes ne s'appliquent plus). Le Service local fait la même chose sans ces défauts.
- **Résolution par `k8sattributes` dans la passerelle** avec `pod_association` sur `k8s.pod.ip` envoyé par le SDK : possible, mais il faut que chaque application pose cet attribut.

**Pièges classiques**

- Récepteur sans adresse : `localhost:4317` ; les applications voient `connection refused`, l'agent est « sain ».
- Métriques internes restées sur `localhost:8888` : le ServiceMonitor trouve le Service, Prometheus marque la cible `down`.
- Exportateur nommé `otlp` : accepté, avec `"otlp" alias is deprecated; use "otlp_grpc" instead` au démarrage ; un jour, refusé.
- `debug` en `detailed` laissé « juste pour voir » : chaque span (attributs compris) dans les journaux du pod, donc dans Loki, avec ses données.
- Application `otel` synchronisée avant l'opérateur : `no matches for kind "OpenTelemetryCollector"` ; la vague `-1` et le réessai le règlent.
- Kustomize avec un `namespace:` global : il l'ajoute aussi à la `CiliumClusterwideNetworkPolicy` (il ne connaît pas la portée des CRD). D'où des espaces écrits dans chaque manifeste.
- Image `otel/opentelemetry-collector-contrib:0.161.0` sans le préfixe de Harbor : refusée par `medisphere-images`, et l'erreur n'apparaît que dans les événements du DaemonSet.

**En production chez MédiSphère**

Une alerte sur `otelcol_receiver_refused_spans` et `otelcol_exporter_send_failed_spans` (palier 3), un tableau « chaîne de traces » ; l'entrée 10.10.41.63 en TLS avec jeton avant d'y laisser entrer quoi que ce soit d'autre que des essais (M23-E16) ; la montée de version de l'opérateur et des Collectors ensemble, d'abord en `wb-essais` avec un CR de test, en lisant les notes de version (les noms et valeurs par défaut bougent souvent).

---

### M23-E03 — Tempo sur le RGW

**Solution**

1. **Le RGW.**
   ```
   admin@ceph01:~$ sudo cephadm shell -- radosgw-admin user create --uid=tempo --display-name="Tempo k8s-par1" --max-buckets=1 \
     | jq '{AWS_ACCESS_KEY_ID: .keys[0].access_key, AWS_SECRET_ACCESS_KEY: .keys[0].secret_key}' > /tmp/tempo.json
   admin@ceph01:~$ sudo cephadm shell -- radosgw-admin quota set --quota-scope=user --uid=tempo --max-size=20G
   admin@ceph01:~$ sudo cephadm shell -- radosgw-admin quota enable --quota-scope=user --uid=tempo
   ```
   Le fichier `/tmp/tempo.json` est recopié sur `adm01` par `scp` puis **effacé** (`shred -u`) ; sur `adm01`, `install -m 600 /dev/null ~/.config/workbook/s3-tempo.env` et deux lignes `AWS_ACCESS_KEY_ID=…` / `AWS_SECRET_ACCESS_KEY=…`. Le compartiment, avec cette identité :
   ```
   admin@adm01:~$ (set -a; . ~/.config/workbook/s3-tempo.env; set +a; aws --endpoint-url https://rgw.par1.medisphere.internal s3api create-bucket --bucket tempo-k8s-par1)
   ```
   Le Secret : [`secrets/tempo.yml.exemple`](fichiers/M23-E03/k8s/secrets/tempo.yml.exemple) (forme du fichier Vault) et un composant `tempo` de `secrets-k8s.sh`, copié de `loki` (espace `traces`, Secret `tempo-objstore`, clés `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`).
2. **Le chart** : entrée `tempo` 3.2.1 dans `charts.yaml` (même fichier qu'en E02). Défaut de `tempo.retention` : `24h`, rendu dans `backend_scheduler` et `backend_worker` (`block_retention`).
3. **Les values** : [`tempo/values.yaml`](fichiers/M23-E03/observabilite/tempo/values.yaml) ; l'Application [`tempo.yaml`](fichiers/M23-E03/gitops/plateforme/tempo.yaml). Validation hors cluster, avec le binaire de la même version :
   ```
   admin@adm01:~/src/observabilite$ helm template tempo oci://registry.par1.medisphere.internal/charts/tempo --version 3.2.1 \
     -n traces -f tempo/values.yaml > /tmp/m23/tempo.yaml
   admin@adm01:~/src/observabilite$ yq 'select(.kind == "ConfigMap" and .metadata.name == "tempo") | .data."tempo.yaml"' /tmp/m23/tempo.yaml > /tmp/m23/tempo-conf.yaml
   admin@adm01:~/src/observabilite$ yq 'select(.kind == "ConfigMap" and .metadata.name == "tempo") | .data."overrides.yaml"' /tmp/m23/tempo.yaml > /tmp/m23/overrides.yaml
   admin@adm01:~/src/observabilite$ sed -i 's#/conf/overrides.yaml#/tmp/m23/overrides.yaml#' /tmp/m23/tempo-conf.yaml
   admin@adm01:~/src/observabilite$ AWS_ACCESS_KEY_ID=x AWS_SECRET_ACCESS_KEY=y ~/bin/tempo-3.1.1 -config.file /tmp/m23/tempo-conf.yaml -config.expand-env=true -config.verify=true && echo valide
   valide
   ```
   (Binaire de la page des versions de Tempo, vérifié par sa somme ; une clé mal écrite donne `field forcepathstyl not found in type s3.Config`.)
4. **La passerelle** : [`otel-passerelle.yaml`](fichiers/M23-E03/observabilite/otel/otel-passerelle.yaml) (exportateur `otlp_grpc/tempo`, `sending_queue` de 5000 lots, reprises jusqu'à 5 min) et [`politiques.yaml`](fichiers/M23-E03/observabilite/otel/politiques.yaml) avec `traces-tempo`.
5. **La source** : [`grafana/sources-tempo.yaml`](fichiers/M23-E03/observabilite/grafana/sources-tempo.yaml), ajoutée à la kustomization racine de `plateforme/observabilite`. Dans Explore : `{ resource.service.name = "essai-telemetrygen" }`, une trace de trois spans (une racine, deux filles).
6. **Sous le capot.**
   ```
   admin@adm01:~$ (set -a; . ~/.config/workbook/s3-tempo.env; set +a; aws --endpoint-url https://rgw.par1.medisphere.internal s3 ls --recursive s3://tempo-k8s-par1/ | head)
   2026-11-03 10:42:11       1873 single-tenant/03521b7a-f119-459d-a096-35ad83b3be46/bloom-0
   2026-11-03 10:42:11      28403 single-tenant/03521b7a-f119-459d-a096-35ad83b3be46/data.parquet
   2026-11-03 10:42:11        412 single-tenant/03521b7a-f119-459d-a096-35ad83b3be46/index
   2026-11-03 10:42:11        690 single-tenant/03521b7a-f119-459d-a096-35ad83b3be46/meta.json
   2026-11-03 10:47:30        331 single-tenant/index.json.gz
   ```
   `single-tenant` : le locataire par défaut quand `multitenancy_enabled` est faux. Le `meta.json` donne `"format": "vParquet5"`, `totalObjects` (nombre de traces), `startTime`/`endTime`, `compactionLevel` ; après compaction, les blocs d'origine deviennent `meta.compacted.json` puis disparaissent. Journaux : `live-store` (traces tenues en mémoire puis écrites dans le WAL), `backend_scheduler` et `backend_worker` (tâches de compaction et de rétention).

**Explications**

Tempo 3 a remplacé l'*ingester* et le *compactor* de Tempo 2 : le **live-store** tient les traces récentes (en mémoire puis dans un WAL local) et répond aux requêtes sur elles ; les blocs complets partent dans le stockage objet ; un **ordonnanceur** distribue à des **travailleurs** la compaction (fusion des petits blocs) et la **rétention** (suppression des blocs plus vieux que `block_retention`). En microservices, Kafka sert de file entre le distributeur et ces composants ; en monolithique, tout est dans le processus, sans Kafka. Le WAL sur un volume évite de perdre les dernières minutes à chaque redémarrage du pod. Les blocs sont du Parquet en colonnes : une recherche TraceQL ne lit que les colonnes des attributs qu'elle teste (et les filtres de Bloom évitent d'ouvrir les blocs qui ne contiennent pas un identifiant cherché).

`-config.expand-env` remplace `${AWS_ACCESS_KEY_ID}` au démarrage : les clés ne sont ni dans Git ni dans la ConfigMap, seulement dans le Secret et l'environnement du pod.

**Alternatives**

- Laisser Tempo trouver les clés seul (variables `AWS_*` lues par le client S3 quand `access_key` est vide) : fonctionne, mais rend la configuration implicite.
- Stockage local (`backend: local`) : réservé aux essais ; pas de rétention partagée, perte au remplacement du volume.
- Microservices avec Kafka (ou Redpanda) : le chart `tempo-distributed` ; hors budget mémoire du lab.

**Pièges classiques**

- Rétention non écrite : 24 h par défaut avec le chart 3.2 (auparavant, le chart ne l'appliquait pas : des tutoriels montrent des données gardées indéfiniment).
- `forcepathstyle` oublié : le client cherche `tempo-k8s-par1.rgw.par1.medisphere.internal`, qui n'existe ni dans le DNS ni dans le certificat.
- Certificat du RGW non vérifié faute de racine montée : la tentation `tls_insecure_skip_verify: true`, interdite (règle 5 du M14).
- Retirer la clé `receivers.jaeger` : le rendu échoue (`nil pointer evaluating interface {}.protocols`).
- Chercher une trace dix secondes après l'avoir envoyée : rien, ce n'est pas une panne.
- Grafana en refus par défaut de sortie (si ton `supervision` filtre les sorties depuis M21-E29) : ajoute la sortie vers `traces` 3200.

**En production chez MédiSphère**

Supervision de Tempo (son ServiceMonitor) : `tempo_distributor_spans_received_total`, erreurs d'écriture vers le RGW, retard de compaction ; alerte sur le quota RGW de l'utilisateur `tempo` ; dimensionnement (M23-E16) ; sauvegarde : les traces ne sont **pas** sauvegardées (donnée de diagnostic, rétention courte, reconstruite par l'usage), décision écrite dans l'ADR-0230.

---

### M23-E04 — Instrumenter MédiAgenda avec le SDK Python

**Solution**

1. **Le code** : correctif [`mediagenda-api/traces.patch`](fichiers/M23-E04/mediagenda-api/traces.patch), à appliquer **après** le correctif `request_id` de M22-E06, et dépendances par `uv add` ([`pyproject.toml.extrait`](fichiers/M23-E04/mediagenda-api/pyproject.toml.extrait)) :
   ```
   admin@adm01:~/src/mediagenda-api$ git switch -c traces-otel
   admin@adm01:~/src/mediagenda-api$ uv add "opentelemetry-sdk>=1.45.1,<2" "opentelemetry-exporter-otlp-proto-grpc>=1.45.1,<2" \
     "opentelemetry-instrumentation-fastapi>=0.66b1,<0.67" "opentelemetry-instrumentation-psycopg>=0.66b1,<0.67" \
     "opentelemetry-instrumentation-redis>=0.66b1,<0.67"
   admin@adm01:~/src/mediagenda-api$ git apply --index ~/DevOpsPrivateCloud/modules/23-traces/corrige/fichiers/M23-E04/mediagenda-api/traces.patch
   admin@adm01:~/src/mediagenda-api$ uv run pytest -q && uv run ruff check . && uv run ruff format --check .
   ..................................                                       [100%]
   34 passed, 2 deselected in 0.65s
   ```
   Ce que fait le correctif : `telemetrie.py` (fournisseur, ressource `Resource.create({"service.version": …})`, `BatchSpanProcessor(OTLPSpanExporter())` seulement si `OTEL_EXPORTER_OTLP_ENDPOINT` est posée, `PsycopgInstrumentor` et `RedisInstrumentor`) ; `__main__.py` (`configurer` avant `create_app`, `arreter` après `uvicorn.run`) ; `app.py` (`FastAPIInstrumentor.instrument_app(app, excluded_urls="/sante$,/pret$,/metrics$", exclude_spans=["receive", "send"])`, `FastAPI(…, telemetry={"auto_configure": False})`, spans métier) ; `tests/test_telemetrie.py`.
2. **FastAPI 0.142** : sa télémétrie native (paramètre `telemetry` de `FastAPI()`) crée des spans serveur et des spans d'« opération » dès qu'un fournisseur est configuré ; elle **détecte** le `OpenTelemetryMiddleware` de l'instrumentation contrib dans la pile et se retire (traces, métriques et journaux). Mais au démarrage, avec des variables `OTEL_*` et sans l'extra `fastapi[opentelemetry]`, elle avertit : `FastAPI automatic telemetry configuration failed: Automatic OpenTelemetry export requires fastapi[opentelemetry] …`. `auto_configure: False` lui interdit d'ajouter un exportateur : c'est `telemetrie.py` qui configure.
3. **Spans métier** : voir le correctif (le `409` est levé après la span, l'événement `mediagenda.conflit_creneau` reste).
4. **Tests** : dans le correctif.
5. **Livraison.** MR, pipeline (image `v1.1.0` signée), MR de promotion vers dev par la CI. Component [`components/telemetrie`](fichiers/M23-E04/deploiement-mediagenda/components/telemetrie/kustomization.yaml), inclus dans `overlays/dev` et `overlays/recette` :
   ```yaml
   components:
     - ../../components/dependances      # dev seulement (M17)
     - ../../components/debogage         # dev seulement (M17)
     - ../../components/telemetrie
     - ../../components/livraison        # toujours le dernier
   ```
   ```
   admin@adm01:~/src/deploiement$ kustomize build overlays/recette | yq 'select(.kind == "Deployment") | .spec.template.spec.containers[0].env[] | select(.name | test("^(OTEL|MEDISPHERE)_")) | .name'
   MEDISPHERE_ENVIRONNEMENT
   OTEL_SERVICE_NAME
   OTEL_RESOURCE_ATTRIBUTES
   OTEL_EXPORTER_OTLP_ENDPOINT
   OTEL_TRACES_SAMPLER
   OTEL_PROPAGATORS
   OTEL_SEMCONV_STABILITY_OPT_IN
   ```
6. **Constat.** Une création de rendez-vous (relevé sur l'instrumentation réelle) :
   ```
   POST /api/v1/rendez-vous               SERVER    37,7 ms  http.request.method=POST http.route=/api/v1/rendez-vous http.response.status_code=201
   └─ mediagenda.rendez_vous.creer        INTERNAL  35,1 ms  mediagenda.praticien=dr-morel mediagenda.rendez_vous.duree_minutes=30 mediagenda.rendez_vous.id=1
      ├─ INSERT                           CLIENT     3,3 ms  db.system.name=postgresql db.namespace=mediagenda db.query.text=INSERT INTO rendez_vous (…) VALUES (%s, %s, %s, %s, %s) RETURNING …
      └─ mediagenda.cache.invalider       INTERNAL   5,4 ms
         ├─ DEL                           CLIENT     4,9 ms  db.system.name=redis db.query.text=DEL ?
         └─ DEL                           CLIENT     0,2 ms
   ```
   Ressource : `service.name`, `service.version`, `service.namespace`, `deployment.environment.name`, `telemetry.sdk.*` viennent de l'application ; `k8s.namespace.name`, `k8s.pod.name`, `k8s.deployment.name`, `k8s.node.name`, `k8s.cluster.name`, `medisphere.equipe` de l'agent. Le texte SQL est **paramétré** (`%s`) : aucune valeur ; la commande Valkey est assainie (`DEL ?`) par l'instrumentation.
7. [`conventions-telemetrie.md`](fichiers/M23-E04/medisphere/docs/observabilite/traces/conventions-telemetrie.md).

**Explications**

Le SDK est **configuré par l'environnement** (spécification `OTEL_*`) : l'application ne fait qu'installer un fournisseur et choisir ses instrumentations ; la plateforme décide où envoyer, comment échantillonner, quel nom donner. L'envoi par lots (`BatchSpanProcessor`) se fait dans un fil séparé : une requête n'attend jamais le Collector ; si l'agent est absent, les spans sont perdues après la file, l'application continue. Les instrumentations remplacent les fonctions de connexion des bibliothèques : elles doivent être actives **avant** que le pool PostgreSQL et le client Valkey soient créés (d'où l'appel dans `main` avant `create_app`). `psycopg_pool` crée ses connexions par `Connection.connect`, que l'instrumentation enveloppe. Sans fournisseur (tests, `uv run` sans variables), l'API d'OpenTelemetry renvoie des traceurs qui ne font rien : le code ne teste jamais « est-ce que les traces sont actives ».

`OTEL_SEMCONV_STABILITY_OPT_IN=http,database` fait émettre aux instrumentations Python les noms **stables** (`http.request.method`, `url.path`, `db.system.name`, `db.query.text`) : ceux de Go (`otelhttp` 0.72), ceux des requêtes du workbook, ceux que reconnaît le *metrics-generator* de Tempo. Sans elle : `http.method`, `http.target`, `db.system`, `db.statement`.

**Alternatives**

- Télémétrie **native de FastAPI** au lieu de l'instrumentation contrib : moins de dépendances, conventions stables d'office, `url.query` déjà caviardé pour quelques paramètres sensibles. Le workbook garde la contrib pour rester comparable à l'auto-instrumentation (E07) et à la PLAN ; à réévaluer (ADR-0230).
- Exportateur OTLP **HTTP** (`opentelemetry-exporter-otlp-proto-http`) : sans `grpcio` (image plus légère) ; point d'envoi en 4318.
- `opentelemetry-instrument` (distribution, démarrage sans code) : c'est l'auto-instrumentation, dans l'image ; E07 en montre les limites.

**Pièges classiques**

- Instrumenter après la création du pool : aucune span SQL, sans erreur.
- `excluded_urls="sante,pret"` : expression cherchée **dans l'URL entière**, `sante` exclurait aussi `/api/v1/…/sante-xyz` ; ancrer (`/sante$`).
- Mettre le nom du patient en attribut « pour le diagnostic » ; ou `capture_parameters=True` sur psycopg : les valeurs SQL partent dans Tempo.
- Lever le 409 dans la span métier : elle apparaît en erreur, et les requêtes « erreurs » de l'astreinte se remplissent de conflits normaux.
- Fournisseur global posé deux fois dans les tests (« Overriding of current TracerProvider is not allowed ») : une *fixture* de module.
- Oublier `arreter()` : les dernières spans d'un pod qui s'arrête sont perdues (celles d'un déploiement raté, justement).
- Placer le component après `livraison` : sans effet ici, mais la règle du M17 est que `livraison` reste le dernier.

**En production chez MédiSphère**

L'instrumentation est une **dépendance** comme une autre : Renovate (M13) propose les montées, le SDK et les instrumentations bougent **ensemble** (1.45 ↔ 0.66b), tests verts obligatoires. La prod reçoit le component au mini-projet, après une semaine de recette sans régression de latence (le surcoût mesuré : quelques centaines de microsecondes par requête, à vérifier sur ton lab avec les métriques du M21).

---

### M23-E05 — Explorer les traces dans Grafana : TraceQL

**Solution**

Le fichier : [`requetes/E05.traceql`](fichiers/M23-E05/observabilite/requetes/E05.traceql) (11 requêtes, deux requêtes de métriques en commentaire). Résultats relevés sur des données réelles de MédiAgenda (Tempo 3.1.1), après `trafic.sh` :

| Q | Requête (abrégée) | Ce qu'elle montre |
|---|---|---|
| 1 | `{ resource.service.name = "mediagenda-api" && resource.deployment.environment.name = "dev" }` | sélection par ressource |
| 2 | `… && kind = server && duration > 100ms` | intrinsèques ; les premières requêtes après un démarrage (connexions à ouvrir) |
| 3 | `span.http.response.status_code >= 400` | les 409 et 404 du générateur ; **rien** si l'application émet encore `http.status_code` (E04, conventions) |
| 4 | `{ span.db.system.name = "postgresql" && duration > 2ms } \| select(span.db.query.text)` | `select` ajoute l'attribut aux résultats sans filtrer |
| 5 | `span.http.route = "/api/v1/creneaux" && span.mediagenda.cache.resultat = "miss"` | attribut métier posé sur la span serveur |
| 6 | `{ event:name = "mediagenda.conflit_creneau" }` | événements de span (vParquet4 et plus) |
| 7 | `{ … kind = server } >> { span.db.system.name = "postgresql" }` | descendants, à n'importe quelle profondeur |
| 8 | `{ name = "mediagenda.cache.invalider" } > { span.db.system.name = "redis" }` | enfants directs |
| 9 | `{ resource.service.name = "mediagenda-api" } \| count() > 4` | agrégat par ensemble de spans |
| 10 | `{ trace:rootService = "mediagenda-api" && trace:duration > 50ms }` | intrinsèques de trace |
| 11 | `{ span.http.request.method = "POST" } && { span.db.system.name = "redis" }` | deux conditions sur deux spans de la même trace |

Lecture d'une création : la span serveur dure ≈ 38 ms, dont ≈ 35 dans `mediagenda.rendez_vous.creer` ; l'`INSERT` prend 3 ms, l'invalidation 5 ms ; le reste est du temps **non instrumenté** (validation Pydantic, sérialisation, ouverture d'une connexion du pool à la première requête). Une trace « lente » sans span fille lente désigne justement ce temps-là (ou un manque d'instrumentation).

Requêtes de métriques (onglet Metrics, Tempo 3 calcule sur le *live-store* et les blocs) : `| rate() by (span.http.route)` et `| quantile_over_time(duration, .95) by (span.http.route)`.

**Explications**

TraceQL sélectionne des **ensembles de spans** (*spansets*) par trace : `{ … }` filtre les spans d'une trace, les opérateurs combinent les ensembles d'une même trace, les fonctions après `|` filtrent ou enrichissent les ensembles. Le résultat d'une recherche est une liste de traces, chacune avec les spans qui ont satisfait la requête. Les attributs sont typés : `span.http.response.status_code >= 400` compare des entiers, `= "400"` ne trouverait rien. Un attribut absent n'est ni égal ni différent : `!= nil` teste la présence.

**Alternatives**

L'éditeur de recherche de Grafana (*Search*) construit des requêtes simples sans les écrire ; la recherche par identifiant (`trace_id` collé depuis un journal) ; `tempo-cli` pour des recherches hors Grafana (palier 4).

**Pièges classiques**

- `span.service.name` au lieu de `resource.service.name` : aucun résultat, aucune erreur.
- Mélanger anciennes et nouvelles conventions (`http.status_code` / `http.response.status_code`) : écrire `(span.a = x || span.b = x)` le temps d'une migration.
- Une fenêtre de temps trop courte dans Grafana : les traces de la nuit ne sont pas dans « Last 15 minutes ».
- `>>` au lieu de `>` : `>>` trouve aussi les petits-enfants.
- Conclure sur des **comptes** après l'échantillonnage en queue (M23-E09) : les traces rapides et sans erreur sont sous-représentées.

**En production chez MédiSphère**

Le fichier devient la source du runbook « l'API est lente » (palier 3) et des panneaux « traces » des tableaux de l'astreinte ; les requêtes sont rejouées par le check de ce module à chaque montée de Tempo (une syntaxe qui change se voit tout de suite).
