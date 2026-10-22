# Module 22 — Palier 2 : Opérationnel — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Ce corrigé suit l'ordre de l'énoncé. Les fichiers complets sont dans [`fichiers/`](fichiers/) : `M22-E06/` (MédiAgenda : correctif `request_id`, overlay dev ; Alloy et Loki version E06), `M22-E07/` (Alloy version E07 : audit, événements, clustering), `M22-E08/` (Loki avec ruler, règles, kustomization), `M22-E09/` (Alloy version E09 avec masquage, gabarit des VMs, politique), `M22-E10/` (essai Fluent Bit, comparatif), `M22-E11/` (revue et version corrigée), `M22-E12/` (RB-220). La configuration `alloy/config.alloy` est donnée **en entier** à chaque étape (E06, E07, E09) : la dernière est la configuration de référence.

**Ce qui a été vérifié à la rédaction** :
- le correctif `request_id` de MédiAgenda appliqué par `git apply` sur `apps/mediagenda` (le code du dépôt), puis `uv run pytest` (29 tests verts, dont les deux nouveaux), `ruff check` et `ruff format --check` ;
- l'overlay `dev` (deux correctifs) construit par `kustomize build` 5.8.1 sur une base représentative (ConfigMap passée en `DEBUG`, annotation ajoutée au gabarit de pod, `checksum/config` conservée) ;
- les trois versions de `config.alloy` : `alloy fmt --test` et `alloy validate` 1.21.1 ; leurs étapes de traitement **exécutées** par Alloy 1.21.1 sur des lignes représentatives (MédiAgenda en JSON avec sondes, MédiDoc en `slog`, journal d'audit, événements, journald simulé, pod témoin de E09) vers un Loki 3.7.9 local multi-locataire, puis interrogées : sondes écartées (compteur `loki_process_dropped_lines_total{reason="sonde"}`), métadonnées structurées `request_id`, `niveau` (et `detected_level` calculé par Loki à partir de `niveau` grâce à `log_level_fields`), horodatage de l'application, champs d'audit (`verb`, `user`, `code`, `resource`, `object_ns`, `object_name`), événements d'un espace `mediagenda-*` routés vers le locataire `mediagenda` sans étiquette `instance`, masquage (NIR avec et sans espaces, courriels externes, champ `patient`) en conservant `astreinte@medisphere.internal`, `plateforme@par1.medisphere.internal` et un horodatage de 19 chiffres ;
- le **ruler** : un Loki 3.7.9 local avec les règles de `loki/regles/<locataire>/` en stockage local et un faux Alertmanager : règles chargées par locataire (`/prometheus/api/v1/rules`, `health: ok`), `AuditEchecsAuthentification` et `AuditSuppressionManuelleProd` passées à `firing` et **reçues** sur `/api/v2/alerts` avec `equipe`, `gravite` et l'étiquette externe `source: loki` ;
- le chart Loki avec les valeurs de E06 et E08 rendu par `helm template` (section `ruler` générée, *sidecar* avec `RESOURCE=configmap`, Role au lieu de la ClusterRole) ; la `kustomization.yaml` de E08 construite (une ConfigMap de règles par locataire, étiquette et annotation) ; le chart Fluent Bit 0.58.3 rendu avec les valeurs de l'essai (empreinte de l'archive vérifiée : `99e025e4…`) ; le chart Alloy avec les valeurs de E07 (Service `alloy-cluster`, `--cluster.enabled=true`) ;
- le gabarit du rôle `alloy` version E09 rendu par Ansible (bloc `raw`) puis validé par `alloy validate` ; `ansible-lint` profil `production` ;
- les requêtes du RB-220 sur l'audit (expressions `json ip="sourceIPs[0]"`) exécutées contre le Loki local ;
- les checks : `shellcheck -x`, `bash -n`, exécution à vide et contre le Loki local ; E09 testé dans les deux sens (vert sur des lignes masquées, rouge après l'envoi d'une ligne non masquée).

**Points non testés en conditions réelles**, à vérifier sur ton lab :
- la chaîne complète de E06 sur le lab (pipeline de MédiAgenda, promotion, synchronisation de `mediagenda-dev`) et le comportement de la variable de contexte dans les points d'entrée **synchrones** de FastAPI sous uvicorn réel (vérifié par `TestClient`) ;
- le clustering d'Alloy dans le DaemonSet (élection du membre qui lit les événements, reprise quand il disparaît) ;
- la recopie des ConfigMaps par le *sidecar* dans `/rules/<locataire>` et la relecture par le ruler (intervalle `poll_interval`), ainsi que le Service `kps-alertmanager` (nom tiré de `fullnameOverride: kps` du M21) ;
- le rendu du courriel par l'Alertmanager du M21 (le contrôle cherche le nom de l'alerte dans le sujet ou le corps) ;
- les options de la sortie `loki` de Fluent Bit 5.1 (`structured_metadata`, `drop_single_key raw`, accesseurs `$kubernetes['labels']['app.kubernetes.io/name']`) : relevées dans la documentation de Fluent Bit (branche principale), non exécutées ; et l'image `fluent/fluent-bit:5.1.3` sur Docker Hub ;
- le comportement de `stage.replace` quand une ligne contient **plusieurs** NIR ou courriels (essai local : chaque occurrence a été remplacée ; vérifie sur une ligne longue).

---

### M22-E06 — Des journaux structurés : MédiAgenda en JSON

**Solution**

*A. L'application.*

1. Correctif complet : [`mediagenda-api/request-id.patch`](fichiers/M22-E06/mediagenda-api/request-id.patch).
   ```
   admin@adm01:~/src/mediagenda-api$ git switch -c journaux-request-id
   admin@adm01:~/src/mediagenda-api$ git apply --index ~/DevOpsPrivateCloud/modules/22-logs/corrige/fichiers/M22-E06/mediagenda-api/request-id.patch
   admin@adm01:~/src/mediagenda-api$ uv run pytest -q && uv run ruff check . && uv run ruff format --check .
   29 passed, 2 deselected
   ```
   - `journal.py` : une `ContextVar` `request_id_courant` et un `logging.Filter` (`FiltreRequete`) qui ajoute `request_id` à tout enregistrement émis pendant la requête ;
   - `app.py` : le filtre posé sur les journaux `mediagenda` et `mediagenda.acces` ; dans le middleware, la valeur de `X-Request-ID` reprise si elle respecte `[A-Za-z0-9._-]{8,64}`, sinon un `uuid4().hex` ; la variable posée avant `call_next`, l'en-tête renvoyé dans la réponse, la variable remise à zéro **après** la ligne d'accès ;
   - deux tests : la ligne d'accès **et** la ligne métier « rendez-vous créé » portent le même identifiant ; une valeur sûre est reprise, une valeur avec espaces et accolades est remplacée.
2. MR relue par `julien.petit` ; la CI (composants du M19) construit `vX.Y.Z`, signe, pousse, ouvre la MR de promotion de l'overlay `dev`.
3. Overlay `dev` : [`journalisation-debug.yaml`](fichiers/M22-E06/mediagenda-deploiement/overlays/dev/journalisation-debug.yaml) (ConfigMap `mediagenda`, `MEDIAGENDA_LOG_LEVEL: DEBUG`) et [`redemarrage-debug.yaml`](fichiers/M22-E06/mediagenda-deploiement/overlays/dev/redemarrage-debug.yaml) (annotation `medisphere.internal/journalisation: debug` sur le gabarit de pod) ; [`kustomization.yaml.extrait`](fichiers/M22-E06/mediagenda-deploiement/overlays/dev/kustomization.yaml.extrait). Le chart pose `checksum/config` **au rendu** (M17) : le correctif kustomize ne la change pas, l'application ne relit son niveau qu'au démarrage, donc sans le second correctif rien ne se passe. L'annotation change le gabarit de pod : Argo CD applique, le Deployment remplace ses pods. `kubectl rollout restart` ferait la même chose **hors de Git**, sur un espace applicatif (interdit depuis M20-E30), et Argo CD verrait l'annotation `restartedAt` comme une dérive à corriger.
4. Trafic sur dev (`port-forward` puis `trafic.sh http://127.0.0.1:18000 10`). Les sondes apparaissent : avec une sonde de vivacité et une de disponibilité toutes les 10 s par pod, plus la collecte de Prometheus toutes les 30 s, environ 14 lignes par minute et par pod, avant toute autre activité. Suivi d'une requête :
   ```
   admin@adm01:~$ curl -si http://127.0.0.1:18000/api/v1/rendez-vous/999999 | grep -i x-request-id
   x-request-id: 3f6c1a0e9b2d4c7e8a5f1b2c3d4e5f60
   ```
   puis, dans `Loki — mediagenda` : `{namespace="mediagenda-dev", container="api"} | request_id="3f6c1a0e9b2d4c7e8a5f1b2c3d4e5f60"`.

*B. La collecte.*

5. Décision (à écrire avec tes chiffres) :

   | Champ | Choix | Raison |
   |---|---|---|
   | `request_id` | métadonnée structurée | une valeur par requête : en étiquette, un flux par requête ; en métadonnée, filtrable sans analyse |
   | `niveau` | métadonnée structurée | 5 valeurs : en étiquette, ×5 flux (et des flux d'`ERROR` presque vides, donc de petits chunks) ; en métadonnée structurée, le filtre est presque aussi rapide et Loki en tire `detected_level` |
   | `route`, `code`, `methode` | rien (dans la ligne) | filtrés à la requête (`| json | code >= 500`) ; en étiquettes, routes × codes × méthodes, et `non-routee` pour chaque URL inconnue |
   | `journal`, `message`, `duree_ms`, `client` | rien | contenu ; `client` est une adresse IP (donnée personnelle indirecte) qui n'a pas à devenir un index |

   ```
   admin@adm01:~$ logcli --org-id=mediagenda series --since=1h --analyze-labels '{namespace=~"mediagenda-.+"}'
   Total Streams:  9
   ```
   (Trois espaces × conteneurs `api` et `migrate`, PostgreSQL, Valkey : un ordre de grandeur de dix flux ; avec `niveau` en étiquette, une quarantaine ; avec `request_id`, des millions.)
6. Configuration complète : [`M22-E06/observabilite/alloy/config.alloy`](fichiers/M22-E06/observabilite/alloy/config.alloy). Dans `loki.process "pods"`, après `stage.cri`, deux `stage.match` :
   ```alloy
   stage.match {
   	pipeline_name = "mediagenda"
   	selector      = "{namespace=~\"mediagenda-.+\", container=\"api\"}"

   	stage.json {
   		expressions = { horodatage = "", niveau = "", route = "", request_id = "" }
   	}
   	stage.drop {
   		source              = "route"
   		expression          = "^/(sante|pret|metrics)$"
   		drop_counter_reason = "sonde"
   	}
   	stage.timestamp {
   		source            = "horodatage"
   		format            = "RFC3339"
   		action_on_failure = "skip"
   	}
   	stage.structured_metadata {
   		values = { niveau = "", request_id = "" }
   	}
   }
   ```
   (Le fichier les écrit sur plusieurs lignes, comme le veut `alloy fmt`.) MédiDoc : même forme, `time` en `RFC3339Nano`, routes `GET /healthz|readyz|metrics`. La MR passe la CI ; Argo CD met à jour la ConfigMap `alloy-config` ; le *config-reloader* voit le fichier changer et appelle `/-/reload` : les pods ne redémarrent pas (`kubectl -n journaux get pods` : même âge), et les journaux d'Alloy montrent `msg="config reloaded"`.
7. [`M22-E06/observabilite/loki/values.yaml`](fichiers/M22-E06/observabilite/loki/values.yaml) : `log_level_fields` reprend la liste par défaut de Loki 3.7 et ajoute `niveau`. Loki range alors le niveau de chaque ligne de MédiAgenda dans la métadonnée `detected_level` (`info`, `debug`, `warn`, `error`) : Grafana colore les lignes et Logs Drilldown les répartit par niveau. Sans cela, Loki devine le niveau dans le texte, avec des erreurs (le mot « error » dans un message `INFO`).
8. Preuve par la métrique d'Alloy (Prometheus, M21) :
   ```
   sum by (reason) (increase(loki_process_dropped_lines_total[15m]))
   {reason="sonde"}           820
   {reason="journald_debug"}  35
   ```
   Une absence de lignes ne prouve rien (le niveau aurait pu rester `INFO`) ; un compteur qui monte prouve que les lignes **sont** écrites et **sont** écartées.
9. Horodatage : la valeur de l'entrée (`values[i][0]`, en nanosecondes) correspond à `horodatage` à la milliseconde près (Alloy ajoute 1 ns aux entrées de même milliseconde pour garder l'ordre : `action_on_duplicate_timestamp = "fudge"`, défaut).
10. Étiquettes indexées de `mediagenda` : `app`, `cluster`, `container`, `job`, `namespace`, `node` — ni `request_id` ni `niveau`. `| request_id="…"` compare une métadonnée structurée (aucune analyse de ligne, exact) ; `|= "…"` cherche la chaîne dans **toute** la ligne : plus coûteux, et il trouverait aussi la chaîne ailleurs (dans un message).

**Explications**

Le choix « étiquette, métadonnée structurée ou ligne » est un choix de **coût** : une étiquette coûte un flux par valeur, pour toujours ; une métadonnée structurée coûte quelques octets par ligne et un filtre rapide ; un champ de la ligne coûte une analyse à chaque requête. La règle de la plateforme : en étiquette, seulement ce qui **sélectionne** une source (où ça tourne, quoi) et qui a peu de valeurs ; en métadonnée, les identifiants qu'on filtre souvent ; le reste dans la ligne.

Écarter les sondes à la collecte (et non dans l'application) : l'équipe garde le droit de passer en `DEBUG` pour **ses** besoins sans payer le bruit en stockage ; la règle est écrite une fois, pour tous les environnements.

**Alternatives**

- Filtrer les sondes dans l'application (ne pas les journaliser même en `DEBUG`) : plus économe encore, mais une décision applicative qui retire de la visibilité en dev ; on peut faire les deux.
- `niveau` en étiquette : défendable (5 valeurs, sélection très rapide des erreurs) sur un petit volume ; on y renonce pour la discipline (liste fermée) et parce que `detected_level` couvre le besoin.
- `stage.logfmt`/`stage.regex` au lieu de `stage.json` : pour MédiAgenda, le JSON est natif ; jamais de regex sur du JSON.
- Le `request_id` produit par la Gateway (Envoy génère un `x-request-id`) : un identifiant posé dès l'entrée, mais pas pour le trafic interne (Argo Rollouts, sondes) ; le middleware reprend l'en-tête s'il existe, ce qui marche dans les deux cas.

**Pièges classiques**

- `request_id` en étiquette « pour filtrer plus vite » : explosion du nombre de flux, refus d'ingestion (`max_global_streams_per_user`, M22-E20).
- `stage.json` sans `stage.match` : analyse JSON sur les lignes de Cilium, CoreDNS, Loki… erreurs et CPU.
- `stage.drop` avec une expression non ancrée (`sante`) : jette aussi `/api/v1/sante-patients` le jour où elle existe.
- `stage.timestamp` sans `action_on_failure = "skip"` : une ligne sans horodatage reçoit le dernier connu (« fudge ») ; pas grave, mais trompeur.
- Le niveau `DEBUG` qui ne s'applique pas : ConfigMap changée, pods non redémarrés (checksum calculée au rendu).
- Le *config-reloader* qui recharge une configuration **refusée** : Alloy garde l'ancienne et l'écrit dans ses journaux ; on croit que le changement est actif.

**En production chez MédiSphère**

`request_id` remplacé par le `trace_id` W3C (M23) et propagé entre services ; des noms de champs communs à toutes les applications (convention écrite : `niveau` ou `level`, pas les deux) ; un test dans la CI de chaque application qui vérifie le format d'une ligne d'accès ; `DEBUG` en dev seulement, par l'overlay, jamais en prod sans ticket.

---

### M22-E07 — Journal d'audit de l'API et événements Kubernetes

**Solution**

1. Sur `k8s-cp01` :
   ```
   admin@k8s-cp01:~$ sudo ls -lh /var/log/kubernetes/audit/
   -rw------- 1 root root  61M audit.log
   -rw------- 1 root root  9,1M audit-2026-10-21T22-14-03.120.log.gz
   …
   admin@k8s-cp01:~$ sudo tail -n 2000 /var/log/kubernetes/audit/audit.log | jq -r '.requestReceivedTimestamp[:16]' | sort | uniq -c | tail -3
   ```
   Quelques dizaines à quelques centaines de lignes par minute, selon l'activité (Argo CD, contrôleurs). La politique du M14 garde 10 rotations de 100 Mo, 30 jours au plus. Lire depuis le début au premier démarrage : des centaines de Mo envoyés d'un coup, bloqués par la limite d'ingestion (429, reprises), et tout ce qui a plus de 7 jours **refusé** par Loki : du travail pour rien.
2. Configuration complète : [`M22-E07/observabilite/alloy/config.alloy`](fichiers/M22-E07/observabilite/alloy/config.alloy), section 3 : `local.file_match "audit"` avec **une cible statique** (`__path__` = `/var/log/kubernetes/audit/audit.log`, étiquettes `cluster`, `job="kubernetes-audit"`, `node`) ; sur un travailleur, le fichier n'existe pas : la cible ne correspond à rien, le composant reste sain et ne lit rien. `loki.source.file "audit"` avec `tail_from_end = true`. `loki.process "audit"` : `stage.json` avec des expressions JMESPath (`user.username`, `objectRef.resource`, `responseStatus.code`…), `stage.timestamp` sur `requestReceivedTimestamp` (`RFC3339Nano`), `stage.structured_metadata` des six champs, `stage.tenant { value = "audit" }`, retrait de `filename`. Seul `audit.log` est lu : les rotations compressées ont déjà été lues quand elles étaient le fichier courant (Alloy suit le renommage).
3. Section 4 : `loki.source.kubernetes_events "evenements"` (`job_name = "kubernetes-events"`, `log_format = "logfmt"`, bloc `clustering { enabled = true }`) → `loki.relabel "evenements"` (ajoute `cluster`, calcule `locataire` d'après l'espace de l'objet, retire `instance`) → `loki.process "evenements"` (`stage.tenant`, retrait de `locataire`). Valeurs : [`M22-E07/observabilite/alloy/values.yaml`](fichiers/M22-E07/observabilite/alloy/values.yaml) — `alloy.clustering.enabled: true` (le chart crée le Service sans tête `alloy-cluster` et passe `--cluster.enabled=true --cluster.join-addresses=alloy-cluster`) et la règle RBAC `events` (lecture), sans Secrets.
4. Après synchronisation :
   ```
   admin@adm01:~$ logcli --org-id=audit series --since=15m '{job="kubernetes-audit"}'
   {cluster="k8s-par1", job="kubernetes-audit", node="k8s-cp01"}
   {cluster="k8s-par1", job="kubernetes-audit", node="k8s-cp02"}
   {cluster="k8s-par1", job="kubernetes-audit", node="k8s-cp03"}
   ```
   Interface d'un pod d'Alloy, page « Clustering » : six membres ; la page du composant `loki.source.kubernetes_events.evenements` n'indique une cible active que sur **un** pod.
5. L'enquête :
   ```
   admin@adm01:~$ kubectl --context k8s-par1 -n wb-essais create configmap m22-e07-temoin --from-literal=etat=cree
   admin@adm01:~$ kubectl --context k8s-par1 -n wb-essais patch configmap m22-e07-temoin -p '{"data":{"etat":"modifie"}}'
   admin@adm01:~$ kubectl --context k8s-par1 -n wb-essais delete configmap m22-e07-temoin
   admin@adm01:~$ logcli --org-id=audit query --since=10m \
       '{job="kubernetes-audit"} | verb="delete" | resource="configmaps" | object_ns="wb-essais" | object_name="m22-e07-temoin"
        | json ip="sourceIPs[0]" | line_format "{{.user}} depuis {{.ip}}"'
   2026-10-22T15:41:07Z {…} <MOI> depuis 10.10.10.10
   admin@adm01:~$ logcli --org-id=audit query --since=10m --forward \
       '{job="kubernetes-audit"} | object_ns="wb-essais" | object_name="m22-e07-temoin" | verb=~"create|update|patch|delete"'
   ```
   La seconde requête donne l'histoire complète de l'objet, dans l'ordre (`--forward`). Une minute suffit quand on sait que le locataire est `audit` et que les champs sont des métadonnées structurées. (Le `user` de la ligne vient des métadonnées structurées, que `line_format` lit comme des étiquettes.)
6. Pod de `wb-essais` supprimé : ses événements (`Killing`, `Scheduled`, `Pulled`, `Created`, `Started` du remplaçant) dans `Loki — plateforme`, `{job="kubernetes-events", namespace="wb-essais"}`. Ceux de `mediagenda-recette` sont dans `Loki — mediagenda` : la règle des locataires s'applique aux événements comme aux journaux, et l'équipe de Julien voit ainsi les `BackOff`, `Unhealthy`, `FailedScheduling` de **ses** pods sans accès au reste.
7. [`requetes/E07.logql`](fichiers/M22-E07/observabilite/requetes/E07.logql).
8. La politique d'audit du M14 ne journalise **jamais** le contenu des Secrets et ConfigMaps (niveau `Metadata` pour eux) ni les lectures des kubelets : le locataire `audit` ne contient donc aucun secret, ce qui rend acceptable de le stocker dans Loki et son compartiment (avec un accès restreint, M22-E16). Si la politique passait les Secrets en `Request`, le journal d'audit deviendrait lui-même un secret.

**Explications**

Le journal d'audit est le seul enregistrement de « qui a fait quoi » sur l'API ; il est écrit par **chaque** serveur d'API (chacun ne voit que les requêtes qu'il a reçues par la VIP) : il faut donc les trois flux. Les champs imbriqués sont extraits **à l'écriture** en métadonnées structurées parce que l'audit se requête par ces champs, souvent sur de longues périodes : les analyser à chaque requête sur des mois coûterait cher.

Les événements Kubernetes vivent une heure dans l'API (`--event-ttl`) : Loki leur donne la durée de rétention de leur locataire. Ils viennent d'une source **unique** : le clustering d'Alloy les fait lire par un seul membre ; si ce membre disparaît, un autre reprend (avec, au pire, quelques doublons : la position n'est pas partagée entre membres).

**Alternatives**

- Envoi direct de l'audit par le serveur d'API (`--audit-webhook-config-file`) vers un récepteur : pas de fichier, mais un composant critique de plus sur le chemin des requêtes de l'API (mode `batch`, perte possible si le récepteur tombe) ; le fichier reste la référence, l'agent le lit.
- Un *Deployment* `kubernetes-event-exporter` (projet communautaire) pour les événements : un seul lecteur, sans clustering ; un composant de plus à maintenir.
- `log_format = "json"` pour les événements : plus simple à analyser (`| json`), un peu plus volumineux ; logfmt suffit et s'analyse aussi.

**Pièges classiques**

- Lire `audit*.log*` : les rotations `.gz` sont du binaire pour `loki.source.file` sans décompression, et déjà lues.
- Un composant d'événements sans bloc `clustering` alors que le chart a le clustering activé : chaque pod lit tout quand même.
- Le droit `events` oublié : le composant journalise des refus (`forbidden`) et n'envoie rien.
- Les événements de `mediagenda-*` envoyés dans `plateforme` : l'équipe ne les voit pas, et le cloisonnement est faux dans l'autre sens.
- `requestReceivedTimestamp` ignoré : l'horodatage devient celui de la lecture (secondes à minutes plus tard), et l'ordre des événements d'audit de trois nœuds se mélange.

**En production chez MédiSphère**

Locataire `audit` à rétention d'un an (M22-E13), lisible seulement par la Plateforme et la RSSI (M22-E16) ; règles d'alerte sur les gestes sensibles (E08) ; une copie de l'audit hors de la plateforme qui l'observe (site PAR2, compartiment en écriture seule et verrouillé) : un administrateur qui efface ses traces ne doit pas pouvoir effacer la copie.

---

### M22-E08 — Alerter sur les journaux

**Solution**

1. Lecture : en Monolithic, `ruler.enabled` n'ajoute pas de pod (`ruler.replicas: 0`) ; il fait écrire la section `ruler` de la configuration, dont le stockage (`loki.rulerConfig.storage`, par défaut celui des chunks : il exigerait `bucketNames.ruler`). Le *sidecar* (`sidecar.rules`) surveille les ConfigMaps **et** les Secrets étiquetés `loki_rule` ; avec `rbac.namespaced: false` (défaut), le chart lui donne une **ClusterRole** de lecture des ConfigMaps et des Secrets de **tout** le cluster. Sophie refuserait : un conteneur de Loki compromis lirait tous les secrets.
2. [`M22-E08/observabilite/loki/values.yaml`](fichiers/M22-E08/observabilite/loki/values.yaml) :
   ```yaml
   loki:
     rulerConfig:
       storage: {type: local, local: {directory: /rules}}
       rule_path: /var/loki/ruler-tmp
       wal: {dir: /var/loki/ruler-wal}
       alertmanager_url: http://kps-alertmanager.supervision.svc.cluster.local:9093
       enable_api: true
       enable_alertmanager_discovery: false
       evaluation_interval: 1m
       poll_interval: 1m
       external_labels: {source: loki}
   ruler: {enabled: true}
   sidecar:
     rules: {enabled: true, label: loki_rule, labelValue: "1", folder: /rules, resource: configmap}
   rbac: {namespaced: true}
   ```
   Rendu : la section `ruler` apparaît dans la ConfigMap `loki` ; le pod `loki-0` gagne un conteneur `loki-sc-rules` (pas un pod de plus) ; une `Role` + `RoleBinding` dans `journaux` remplacent la ClusterRole. (La `Role` du chart cite encore `secrets` : le conteneur, réglé sur `configmap`, ne les lit pas ; le droit reste trop large d'un cran, limité à l'espace `journaux`, à signaler en amont.)
3. Règles : [`loki/regles/mediagenda/alertes.yaml`](fichiers/M22-E08/observabilite/loki/regles/mediagenda/alertes.yaml), [`loki/regles/audit/alertes.yaml`](fichiers/M22-E08/observabilite/loki/regles/audit/alertes.yaml), [`loki/regles/plateforme/alertes.yaml`](fichiers/M22-E08/observabilite/loki/regles/plateforme/alertes.yaml) :
   - `MediagendaErreurs5xxRafale` : `sum by (namespace) (count_over_time({namespace=~"mediagenda-.+", container="api"} | json | journal="mediagenda.acces" | code >= 500 [5m])) > 10`, `for: 2m` (une rafale qui dure, pas une erreur isolée pendant un déploiement), `avertissement`, `equipe: mediagenda` ;
   - `AuditEchecsAuthentification` : `sum(count_over_time({job="kubernetes-audit"} | code="401" [5m])) > 20`, sans `for` (chaque minute compte), `avertissement`, `equipe: plateforme` ; et `AuditSuppressionManuelleProd` (bonus utile en M22-E23) ;
   - `CollecteJournauxArretee` : `absent_over_time({job="pods", namespace="journaux"}[15m])`, `for: 5m`, `critique`, `equipe: plateforme`.
   Les annotations donnent la requête d'enquête et le lien vers RB-220.
4. [`M22-E08/observabilite/loki/kustomization.yaml`](fichiers/M22-E08/observabilite/loki/kustomization.yaml) : `configMapGenerator` d'une ConfigMap par locataire, `labels: {loki_rule: "1"}`, `annotations: {k8s-sidecar-target-directory: /rules/<locataire>}`, sans suffixe d'empreinte. Si `supervision` filtre l'entrée d'Alertmanager : [`kps/politique-alertmanager.extrait.yaml`](fichiers/M22-E08/observabilite/kps/politique-alertmanager.extrait.yaml).
5. Après synchronisation :
   ```
   admin@adm01:~$ for t in mediagenda audit plateforme; do curl -s -H "X-Scope-OrgID: $t" $L/prometheus/api/v1/rules | jq -c '.data.groups[].rules[] | {name, health, state}'; done
   {"name":"MediagendaErreurs5xxRafale","health":"ok","state":"inactive"}
   {"name":"AuditEchecsAuthentification","health":"ok","state":"inactive"}
   {"name":"AuditSuppressionManuelleProd","health":"ok","state":"inactive"}
   {"name":"CollecteJournauxArretee","health":"ok","state":"inactive"}
   ```
   La règle d'audit n'existe que dans le locataire `audit` : le ruler évalue les règles d'un locataire **dans** ce locataire (le dossier `/rules/audit` = locataire `audit`) ; elle ne pourrait d'ailleurs rien voir ailleurs.
6. Essai, avec un kubeconfig jetable (le jeton faux n'est pas en argument) :
   ```
   admin@adm01:~$ kubectl --context k8s-par1 config view --minify --raw | yq '.users[0].user = {"token": "jeton-faux-m22-e08"}' > ~/m22/e08/faux.kubeconfig
   admin@adm01:~$ for i in $(seq 30); do kubectl --kubeconfig ~/m22/e08/faux.kubeconfig get pods -n wb-essais >/dev/null 2>&1; done
   admin@adm01:~$ curl -s -H 'X-Scope-OrgID: audit' $L/prometheus/api/v1/alerts | jq -c '.data.alerts[] | {labels, state}'
   {"labels":{"alertname":"AuditEchecsAuthentification","equipe":"plateforme","gravite":"avertissement","source":"loki"},"state":"firing"}
   admin@adm01:~$ amtool --alertmanager.url=http://alertmanager.apps.par1.medisphere.internal:9093 alert query alertname=AuditEchecsAuthentification
   ```
   Le courriel arrive dans Mailpit (`plateforme@medisphere.internal`, route `equipe=plateforme` du M21). Délais : écriture de l'audit et lecture par Alloy (secondes), envoi par lots (1 s), évaluation de la règle (`evaluation_interval` : jusqu'à 1 min), envoi du ruler, `group_wait` de la route d'Alertmanager (fixé au M21-E06, souvent 30 s) : une à deux minutes en tout.
7. Si Loki est arrêté, le ruler l'est aussi : `CollecteJournauxArretee` ne peut pas sonner. C'est Prometheus qui alerte (cible `journaux/loki` absente : alerte générique du M21 sur `up == 0` des ServiceMonitors), et Alloy accumule puis abandonne les lots (`loki_write_dropped_entries_total`). Superviser la chaîne de supervision par **une autre** chaîne : même principe que le témoin de `mon01` au M21.

**Explications**

Le ruler de Loki est le même moteur que celui de Prometheus, avec des expressions LogQL : il évalue périodiquement des requêtes **métriques** (une requête de journaux brute n'a pas de sens comme alerte) et envoie à Alertmanager par l'API v2. Une alerte de journaux est utile quand l'information n'existe que dans la ligne (un code de l'audit, un message) ; pour le taux d'erreurs global, l'alerte sur métriques du M21 reste la référence.

Le stockage local des règles + *sidecar* fait de Git la seule source : la ConfigMap est générée par kustomize, recopiée par le *sidecar*, relue par le ruler. L'API du ruler permettrait d'écrire des règles directement (`POST /loki/api/v1/rules/…`) : elles ne seraient alors nulle part dans Git.

**Alternatives**

- Stockage des règles dans le compartiment (type `s3`) et chargement par `lokitool rules sync` dans la CI : pas de *sidecar*, mais un jeton d'écriture vers Loki dans la CI.
- Alertes de journaux écrites dans **Grafana** (alerting unifié, source Loki) : interface simple pour les équipes, mais des règles stockées dans la base de Grafana (sauf provisionnement) et une dépendance de l'alerte à Grafana.
- Règles d'enregistrement envoyées à Prometheus (`remote_write` du ruler) : exige `enableRemoteWriteReceiver`, activé au M23 seulement.

**Pièges classiques**

- Ruler activé sans stockage : « Ruler storage is not configured; ruler will not be started », et aucune erreur visible ailleurs.
- La ConfigMap rangée dans `/rules` sans sous-dossier : le ruler la prend pour un locataire nommé d'après le fichier, ou l'ignore.
- `alertmanager_url` vers l'adresse externe 10.10.41.61 : sortie inutile du cluster, et la CNP de `supervision` (M21) ne l'autorise que depuis MGMT et `mon01`.
- Une règle sans `for` sur un phénomène bref : une alerte par redéploiement.
- Le *sidecar* avec ses droits par défaut : lecture de tous les Secrets du cluster.
- Tester avec un vrai mot de passe faux en argument : il reste dans l'historique du shell et dans `ps`.

**En production chez MédiSphère**

Règles testées en CI (`lokitool rules lint`, et des tests de règles sur des journaux enregistrés), relues comme du code ; chaque alerte avec un runbook ; les alertes de journaux revues chaque trimestre avec celles du M21 (`politique-alerte.md`) ; le ruler en composant séparé, à deux réplicas, quand Loki passe en mode distribué.

---

### M22-E09 — Données de santé dans les journaux : filtrer et masquer

**Démarche attendue (LIBRE)** : une défense en profondeur, une seule étape de masquage par où **toutes** les sources passent, les mêmes règles sur les VMs, une preuve par un témoin et par une recherche systématique, et une politique écrite qui dit aussi ce qui **n'est pas** couvert.

**Solution**

1. Le témoin :
   ```
   admin@adm01:~$ kubectl --context k8s-par1 -n wb-essais apply -f ~/DevOpsPrivateCloud/modules/22-logs/ressources/E09-temoin/temoin.yaml
   admin@adm01:~$ logcli --org-id=plateforme query --since=1m '{namespace="wb-essais", container="temoin"}'
   … "patient":"Jeanne Témoin","nir":"2 85 07 75 123 456 78","courriel":"jeanne.temoin@example.org" …
   ```
   Avant toute correction, les données arrivent en clair : la preuve que le risque est réel (et que le contrôle peut passer au rouge).
2. Configuration de référence : [`M22-E09/observabilite/alloy/config.alloy`](fichiers/M22-E09/observabilite/alloy/config.alloy), section 5 : un composant `loki.process "masquage"` ; toutes les sources (`pods`, `journal`, `audit`, `evenements`) y envoient (`forward_to = [loki.process.masquage.receiver]`), et lui seul écrit vers `loki.write`. Trois `stage.replace` :
   - NIR : `\b([12][ .]?[0-9]{2}[ .]?(?:0[1-9]|1[0-2]|[2-9][0-9])[ .]?(?:2[ABab]|[0-9]{2})[ .]?[0-9]{3}[ .]?[0-9]{3}[ .]?[0-9]{2})\b` → `[NIR-MASQUE]` ; un seul groupe capturant (les autres en `(?:…)`), des bornes de mot pour ne pas couper un horodatage de 19 chiffres ;
   - courriels : `([A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,})`, remplacés par un gabarit Go qui **garde** la valeur si son domaine est `medisphere.internal` ou un sous-domaine (`regexReplaceAll` + `eq`), et sinon écrit `[COURRIEL-MASQUE]` ;
   - champs nominatifs JSON (`patient`, `nom`, `prenom`, `nom_patient`, `nom_naissance`, `date_naissance`, `telephone`) → `[MASQUE]`.
   Pourquoi en dernier : après `stage.cri` (le préfixe CRI est retiré), après le traitement de chaque source, et avant **l'unique** sortie : aucune source ne peut le contourner, y compris une source ajoutée plus tard (traces au M23 : à refaire pour les attributs de spans).
3. VMs : [`M22-E09/ansible/roles/alloy/templates/config.alloy.j2`](fichiers/M22-E09/ansible/roles/alloy/templates/config.alloy.j2) : le même composant, entre `{% raw %}` et `{% endraw %}` (les `{{ }}` du gabarit Go d'Alloy ne sont pas pour Jinja) ; `validate` du rôle le contrôle à chaque passage. Une seule source de vérité pour les motifs serait mieux : voir « Alternatives ».
4. Preuve :
   ```
   admin@adm01:~$ logcli --org-id=plateforme query --since=2m '{namespace="wb-essais", container="temoin"}'
   … "patient":"[MASQUE]","nir":"[NIR-MASQUE]","courriel":"[COURRIEL-MASQUE]","copie":"astreinte@medisphere.internal","horodatage_ns":"1792683121000000000"}
   M22-E09 témoin : envoi du dossier à [COURRIEL-MASQUE] (NIR [NIR-MASQUE]), copie à plateforme@par1.medisphere.internal
   admin@adm01:~$ for t in plateforme mediagenda medidoc audit; do echo -n "$t : "; logcli --org-id=$t query --quiet --since=1h --limit=5 \
       '{job=~".+"} |~ `\b[12][ .]?[0-9]{2}[ .]?(0[1-9]|1[0-2]|[2-9][0-9])[ .]?(2[ABab]|[0-9]{2})[ .]?[0-9]{3}[ .]?[0-9]{3}[ .]?[0-9]{2}\b`' | wc -l; done
   plateforme : 0
   …
   ```
   Et le sens inverse : une ligne non masquée poussée à la main dans le locataire `essai` est bien trouvée par la même requête (le contrôle sait passer au rouge).
5. Politique : [`docs/observabilite/journaux/politique-journaux.md`](fichiers/M22-E09/medisphere/docs/observabilite/journaux/politique-journaux.md) (section 1 ; sections 2 et 3 réservées à E13 et E16) : la règle, les deux lignes de défense, ce qui est masqué et par quoi, les **limites** (un nom en texte libre n'est pas reconnaissable), la vérification, la conduite à tenir si une donnée est trouvée (incident SEC, suppression par l'API de Loki, registre).

**Explications**

Le masquage à la collecte est une **seconde** ligne de défense : il rattrape des formats connus (NIR, courriels), jamais un nom propre au milieu d'une phrase. La première ligne, c'est le code des applications (MédiAgenda a déjà un test « pas de donnée patient dans le journal »). L'exception pour `medisphere.internal` montre qu'un bon masquage est **ciblé** : masquer toutes les adresses détruirait l'information des enquêtes sur Alertmanager, Argo CD ou GitLab, sans gain pour la conformité.

Une preuve tient en deux parties : un **témoin** qui écrit en continu les motifs à masquer (si le masquage casse, on le voit dans les 15 secondes), et une **recherche** dans toutes les données récentes qui doit rester vide — et dont on a vérifié qu'elle sait trouver une fuite.

**Alternatives**

- Les motifs dans un **module Alloy** partagé (`declare` d'un composant personnalisé, importé par `import.git` depuis `plateforme/observabilite`) : une seule définition pour le cluster et les VMs ; plus élégant, une dépendance de plus au démarrage des agents (Git joignable).
- Le masquage dans **Loki** : impossible à l'écriture (Loki ne transforme pas les lignes) ; Loki ne peut que **supprimer** après coup (API de suppression, M22-E13).
- `stage.drop` des lignes qui contiennent un motif : « plus sûr », mais on perd la ligne et donc l'information de l'incident ; refusé par l'énoncé.
- `loki.secretfilter` pour les secrets (jetons, clés) : complémentaire, autre catégorie de données.
- Pseudonymiser (empreinte salée) plutôt que masquer : permet de corréler les lignes d'une même personne sans la nommer ; une empreinte d'un NIR (espace de valeurs réduit) se retrouve par force brute : à réserver à des identifiants à fort aléa.

**Pièges classiques**

- Un groupe capturant de trop : `stage.replace` remplace **chaque** groupe capturant, donc des morceaux de NIR, et laisse le reste.
- Pas de bornes de mot : les horodatages en nanosecondes, les identifiants numériques longs deviennent `[NIR-MASQUE]`.
- Masquer dans le pipeline des pods seulement : journald (un `sudo` avec une adresse en argument), l'audit (un nom dans un objet) et les VMs passent à côté.
- Les doubles accolades du gabarit Go dans un gabarit Jinja : erreur de rendu d'Ansible (« Expected an expression »).
- Un contrôle qui ne trouve rien parce que **rien** n'arrive (collecte arrêtée) : d'où le témoin exigé.
- Croire que le masquage dispense de la revue de code des applications.

**En production chez MédiSphère**

Le témoin tourne en permanence dans un espace de la plateforme ; une règle du ruler alerte si une ligne du témoin arrive **non masquée** (requête du check transformée en `count_over_time … > 0`) ; la politique est relue par le DPO ; les motifs suivent les données réellement manipulées (numéro RPPS des praticiens, identifiant national de santé INS) ; toute découverte de donnée personnelle dans Loki ouvre un incident de sécurité.

---

### M22-E10 — Fluent Bit : un autre collecteur

**Solution**

1. Valeurs par défaut du chart 0.58.3 : entrée `tail` sur `/var/log/containers/*.log` avec `multiline.parser docker, cri` (adapté à containerd grâce à `cri`), entrée `systemd` sur `kubelet.service`, filtre `kubernetes` (`Merge_Log On`), sorties **Elasticsearch** (`es`) vers `elasticsearch-master` ; volumes `hostPath` `/var/log`, `/var/lib/docker/containers` et `/etc/machine-id` ; image de `cr.fluentbit.io` ; un pod de test (`testFramework`). Rien de tout cela ne marche tel quel chez nous.
2. [`fluent-bit-essai/values.yaml`](fichiers/M22-E10/observabilite/fluent-bit-essai/values.yaml) : `Path` limité aux deux espaces (motifs séparés par des virgules), `multiline.parser cri`, base de positions `DB` sur un `hostPath`, filtre `kubernetes` (`Labels On` pour lire `app.kubernetes.io/name`), sortie `loki` : `tenant_id essai`, `labels job=fluent-bit, cluster=…, namespace=$kubernetes['namespace_name'], container=…, app=…, node=$kubernetes['host']`, `structured_metadata pod=$kubernetes['pod_name']`, `remove_keys kubernetes, stream, _p, time`, `drop_single_key raw` (la ligne d'origine, sans enveloppe JSON) ; image `fluent/fluent-bit:5.1.3` de Docker Hub ; UID 0 sans capacité ; tolérances ; ServiceMonitor ; PriorityClass `medisphere-essai`.
3. [`politique-reseau.extrait.yaml`](fichiers/M22-E10/observabilite/loki/manifestes/politique-reseau.extrait.yaml) (règle temporaire dans `loki-entree`) ; [`gitops/plateforme/fluent-bit-essai.yaml`](fichiers/M22-E10/gitops/plateforme/fluent-bit-essai.yaml) : finaliseur `resources-finalizer.argocd.argoproj.io` (le retrait du fichier supprime les objets), `CreateNamespace=true` avec `managedNamespaceMetadata` (Pod Security `privileged` appliqué, `restricted` en avertissement, étiquette `temporaire`) ; chart dans le miroir : [`charts-miroir/charts.yaml.extrait`](fichiers/M22-E10/charts-miroir/charts.yaml.extrait).
4. Mesures (Prometheus du M21) :
   ```
   avg_over_time(container_memory_working_set_bytes{namespace=~"journaux|journaux-essai", container=~"alloy|fluent-bit"}[2h])
   rate(container_cpu_usage_seconds_total{namespace=~"journaux|journaux-essai", container=~"alloy|fluent-bit"}[2h])
   ```
   et le nombre de lignes des mêmes pods dans les deux locataires (requêtes dans le comparatif).
5. Exemple de règle reproduite : la valeur de repli de `app` (Alloy : une règle de relabel à quatre sources) demande dans Fluent Bit un filtre `lua` (une fonction de dix lignes qui choisit la première étiquette présente) ou un filtre `modify` par condition — et le locataire par espace, un champ écrit par un filtre puis `tenant_id_key`.
6. Comparatif : [`docs/observabilite/journaux/comparatif-collecteurs.md`](fichiers/M22-E10/medisphere/docs/observabilite/journaux/comparatif-collecteurs.md) (exemple de forme : **mets tes mesures**). Décision : Alloy reste ; un seul agent pour journaux, traces et profils (M23), même modèle de découverte que Prometheus, locataire et masquage simples, validation en CI ; l'écart de mémoire n'est pas décisif à notre échelle.
7. Retrait :
   ```
   admin@adm01:~/src/gitops$ git rm plateforme/fluent-bit-essai.yaml && git commit -m "chore(journaux): retrait de l'essai Fluent Bit (M22-E10)"   # puis MR
   admin@adm01:~$ kubectl --context k8s-par1 -n argocd get application fluent-bit-essai     # disparaît une fois les objets supprimés
   admin@adm01:~$ kubectl --context k8s-par1 delete namespace journaux-essai
   admin@adm01:~$ kubectl --context k8s-par1 get clusterroles,clusterrolebindings | grep -i fluent || echo "rien"
   ```
   Puis MR qui retire la règle de `loki-entree` et le chart de `charts-miroir`. Les lignes du locataire `essai` restent dans Loki jusqu'à sa rétention (M22-E13 la fixe courte) ; elles ne contiennent rien de sensible (masquage… **absent** de Fluent Bit : c'est une raison de plus pour ne pas l'avoir laissé tourner sur les espaces des équipes, d'où le périmètre réduit à la recette et à `journaux`).

**Explications**

Fluent Bit est un collecteur en C, très léger, à base de *plugins* (entrées, analyseurs, filtres, sorties) ; il excelle comme agent généraliste vers de nombreuses destinations (Elasticsearch/OpenSearch, Kafka, S3, Loki). Alloy est plus lourd mais couvre métriques, journaux, traces et profils avec un modèle unique, et partage la logique de Prometheus. La comparaison honnête porte sur **la même charge** et sur **nos** besoins (locataires, masquage, liste d'étiquettes, CI), pas sur des chiffres de banc d'essai publiés.

**Alternatives**

- Comparer sur un nœud (un `nodeSelector`) plutôt que sur deux espaces : mesure plus propre de la consommation, moins de lignes à comparer.
- Vector (Rust, transformations en VRL) : autre collecteur courant, citable dans l'ADR.
- Garder Fluent Bit pour une destination que Loki n'est pas (OpenSearch, M22-E15).

**Pièges classiques**

- Laisser `es` en sortie : le pod boucle sur des erreurs de connexion.
- Garder `/var/log/containers/*.log` sans limite : tout le cluster en double dans Loki pendant l'essai.
- Oublier `drop_single_key` : les lignes arrivent enveloppées (`{"log":"…"}`), les requêtes `| json` de MédiAgenda ne marchent plus telles quelles.
- `auto_kubernetes_labels on` : toutes les étiquettes des pods deviennent des étiquettes Loki (le défaut 4 de la revue de E11, version Fluent Bit).
- Retirer l'Application sans finaliseur : les objets restent, orphelins ; ou croire que l'espace part avec l'Application.
- Oublier la règle temporaire de la CNP : une ouverture qui survit à son motif.

**En production chez MédiSphère**

Un essai de composant se fait dans un espace temporaire, par une Application marquée `temporaire`, avec une date de fin dans le ticket ; un contrôle périodique liste les objets marqués `temporaire` encore présents. Le comparatif alimente l'ADR-0220 (M22-E17).

---

### M22-E11 — Revue : la configuration Alloy du stagiaire

**Solution**

La revue complète, classée par gravité (22 défauts) : [`alloy/revue-lucas/REVUE.md`](fichiers/M22-E11/observabilite/alloy/revue-lucas/REVUE.md). Les défauts **critiques et élevés**, à trouver absolument :

| N° | Défaut | Gravité | Pourquoi |
|---|---|---|---|
| 1 | aucun locataire | critique | Loki est multi-locataire : tout est **refusé** (401) — la configuration « valide » n'envoie rien |
| 2 | aucun masquage | critique | données de santé dans Loki, le compartiment et les sauvegardes |
| 3 | mot de passe en clair (`basic_auth`) | critique | secret dans l'historique Git, et inutile |
| 4 | `labelmap` de toutes les étiquettes des pods | élevée | `pod-template-hash` & co : un flux par déploiement |
| 5 | `pod` en étiquette | élevée | un flux par pod |
| 6 | `route`, `code`, `level` en étiquettes | élevée | produit des valeurs : explosion des flux |
| 7 | `stage.docker` sur containerd | élevée | lignes non analysées, préfixe CRI conservé, horodatage de lecture |
| 17 | positions dans `/tmp` | élevée | relecture complète ou trous à chaque redémarrage |
| 18 | configuration « collée » à la main | élevée | ce qui tourne n'est pas dans Git |

Puis, moyens et faibles : analyse JSON sur tout, horodatage ignoré, sondes, découverte de tout le cluster, journald sur un an sans filtre ni étiquettes, événements en double, IP de l'entrée externe en dur, `filename`, niveau de journalisation `debug`, image `latest`, pas de tolérances (ni audit ni `k8s-w03`), pas de ressources, RBAC par défaut.

Version corrigée : [`alloy/revue-lucas/config.alloy`](fichiers/M22-E11/observabilite/alloy/revue-lucas/config.alloy) (la configuration de référence, état E09) et [`alloy/revue-lucas/values.yaml`](fichiers/M22-E11/observabilite/alloy/revue-lucas/values.yaml) (état E07). Branche :
```
admin@adm01:~/src/observabilite$ git switch -c revue-lucas
admin@adm01:~/src/observabilite$ mkdir -p alloy/revue-lucas && cp … alloy/revue-lucas/ && git add alloy/revue-lucas && git commit -m "docs(alloy): revue de la MR !41 et version corrigée (M22-E11)"
admin@adm01:~/src/observabilite$ git push -u origin revue-lucas
```
Le job `alloy-validation` de la CI valide aussi `alloy/revue-lucas/config.alloy`.

**Explications**

`alloy validate` est un analyseur de syntaxe et de types : il garantit que la configuration **démarre**, pas qu'elle **fonctionne**, ni qu'elle est **acceptable**. Les trois défauts critiques sont invisibles pour lui : le locataire manquant est une incompatibilité avec **notre** Loki, le masquage absent et le mot de passe en clair sont des violations de **notre** politique. Une revue de configuration de collecte se fait avec une grille : sécurité, données personnelles, cardinalité, fiabilité (redémarrage, premier démarrage, doublons), exploitation (Git, versions, supervision).

**Pièges classiques (du relecteur)**

- S'arrêter aux défauts de syntaxe ou de style alors que la configuration est valide.
- Lister les défauts sans impact concret : « mauvaise pratique » ne convainc pas un stagiaire ; « Loki refuse tout » oui.
- Corriger sans expliquer : Lucas refera la même chose pour les traces.
- Fusionner la version corrigée dans `main` : elle doublerait la configuration de référence ; la branche sert à la comparaison.

**En production chez MédiSphère**

Les règles objectivables de cette revue deviennent des **tests de la CI** de `plateforme/observabilite` : pas de `labelmap` vers des étiquettes Loki, pas de `password`, présence d'un `stage.tenant`, d'un masquage, d'un sélecteur de nœud (un script de quelques `grep`, ou des tests de politique sur la configuration).

---

### M22-E12 — Runbook : chercher dans les journaux pendant un incident

**Solution**

Un modèle complet : [`RB-220-chercher-dans-les-journaux.md`](fichiers/M22-E12/medisphere/docs/observabilite/journaux/runbooks/RB-220-chercher-dans-les-journaux.md). Ce qui le rend utilisable :
- la section « En 30 secondes » en tête : locataire, fenêtre, sélecteur — les trois erreurs qui font perdre le plus de temps ;
- des requêtes **testées**, chacune avec sa question et son locataire, en Grafana et en logcli ;
- les droits écrits (qui peut lire l'audit, où se note une recherche dans l'audit) ;
- les pièges sous forme « ce qui se passe / parade », dont les erreurs de cadre (UTC, absence de lignes qui n'est pas absence d'événement, rétention, masquage) ;
- la boucle d'amélioration : une requête utile deux fois devient un panneau ou une règle.

La question de Nadia (« qui a supprimé le déploiement `mediagenda` de la recette hier soir ? ») se résout avec la ligne « Qui a supprimé un objet ? » : locataire `audit`, `{job="kubernetes-audit"} | verb="delete" | object_ns="mediagenda-recette" | object_name="mediagenda"`, fenêtre d'hier soir en UTC. Si la réponse est `system:serviceaccount:argocd:argocd-application-controller`, la suppression vient d'Argo CD (un `prune` après un commit) : l'enquête continue dans l'historique de `mediagenda/deploiement`.

**Grille d'auto-évaluation**

| Critère | Oui / non |
|---|---|
| Le choix du locataire est la **première** chose dite | |
| Au moins 10 requêtes, chacune exécutée sur ton lab, avec son locataire | |
| Une requête par `request_id` et une d'audit « qui a supprimé » | |
| Les droits d'accès à l'audit sont écrits | |
| Au moins 6 pièges, dont UTC et « absence de lignes » | |
| Le chemin du fichier est celui des `runbook_url` des règles de E08 | |
| Une personne qui n'a pas fait le module retrouve l'auteur d'une suppression | |

**Pièges classiques**

- Un runbook qui enseigne LogQL au lieu de répondre aux questions de l'astreinte.
- Des requêtes jamais exécutées (une faute de frappe dans un nom d'étiquette, et la requête « ne trouve rien »).
- Oublier les droits : l'astreinte n'a pas accès au locataire `audit` à 3 h du matin si personne ne l'a prévu.

**En production chez MédiSphère**

RB-220 est relu à chaque post-mortem où une recherche dans les journaux a joué un rôle ; ses requêtes deviennent un tableau de bord « Enquête » ; l'astreinte s'y exerce lors des exercices d'incident (M22-E23, F3).
