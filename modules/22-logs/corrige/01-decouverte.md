# Module 22 — Palier 1 : Découverte — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Ce corrigé suit l'ordre de l'énoncé. Le questionnaire (E01) est argumenté et les QCM expliquent pourquoi les autres options sont fausses. Les fichiers complets sont dans [`fichiers/`](fichiers/), exercice par exercice ; chaque dossier reproduit l'arborescence du projet concerné (`observabilite/` pour `plateforme/observabilite`, `gitops/` pour `plateforme/gitops`, `charts-miroir/`, `k8s/` pour `plateforme/k8s`, `ansible/` pour `plateforme/ansible`, `medisphere/` pour la documentation). Un fichier n'apparaît que dans l'exercice qui le crée ou le modifie : `M22-E02/` (Loki, sources Grafana), `M22-E03/` (Alloy, CI), `M22-E04/` (logcli, requêtes), `M22-E05/` (rôle `alloy`, bordure).

**Ce qui a été vérifié à la rédaction** :
- les charts réels, téléchargés depuis leurs dépôts et vérifiés par l'empreinte de l'index (`loki-19.0.3.tgz` `bf3e8a09…`, `alloy-1.14.1.tgz` `4b31686f…`), rendus par `helm template` (Helm 4) avec les valeurs des corrigés : configuration de Loki générée (ConfigMap `loki` : `auth_enabled`, `common.storage.s3` avec `${LOKI_S3_…}`, `http_config.ca_file`, schéma v13, `limits_config`), arguments du conteneur (`-config.expand-env=true` posé par le chart, `-target=all`), absence de passerelle, de memcached, de canari, du *sidecar* et de sa ClusterRole quand ils sont coupés ; DaemonSet d'Alloy (arguments `--storage.path`, montages, tolérances, contexte de sécurité, ClusterRole réduite) ;
- les sources kustomize (`loki/`, `alloy/`) construites par `kustomize build` 5.8.1 (avec un certificat factice pour la racine) ;
- `config.alloy` : `alloy fmt --test` et `alloy validate` du binaire **v1.21.1** (somme vérifiée) ; `validate` refuse bien un attribut mal orthographié ;
- **fonctionnement réel** des étapes de traitement : Alloy 1.21.1 lancé sur des fichiers au format CRI et JSON (MédiAgenda, MédiDoc, Loki, audit, journald simulé), écrivant dans un **Loki 3.7.9 local multi-locataire** (stockage fichiers) : étiquettes indexées par locataire (API `labels`, `series`), métadonnées structurées (`pod`, `stream`, `niveau`, `unite`), ajout de l'étiquette `stream` par `stage.cri` (d'où son déplacement en métadonnée), routage des locataires, niveau `debug` écarté (compteur `loki_process_dropped_lines_total{reason="journald_debug"}`), `/-/ready`, rechargement sur `SIGHUP` ;
- les 12 requêtes de `requetes/E04.logql` exécutées contre ce Loki local (espace `mediagenda-dev` à la place de `mediagenda-recette`) : toutes valides, toutes renvoient des données ;
- le rôle `alloy` et le playbook : `ansible-lint` 26.10 profil `production` (ansible-core 2.21) et `--syntax-check` ; gabarit `config.alloy.j2` rendu par Ansible puis validé par `alloy validate` et `alloy fmt --test` ; le rôle `outils_k8s` modifié passe `ansible-lint` ;
- empreintes relevées le 22/10/2026 : `alloy-linux-amd64.zip` v1.21.1 `83e7ad16…`, `logcli-linux-amd64.zip` v3.7.9 `176bc538…` (fichiers `SHA256SUMS` des publications) ;
- les checks : `shellcheck -x` et `bash -n` ; exécutés « à vide » (lab injoignable) sous `set -euo pipefail` sans erreur, et contre le Loki local (E04 : 26 contrôles verts sur 27, seul le lien `logcli` manquant).

**Points non testés en conditions réelles**, à vérifier sur ton lab et à signaler s'ils diffèrent :
- le déploiement complet sur `k8s-par1` (Argo CD, RGW, BGP, ExternalDNS) : l'environnement de rédaction n'avait ni cluster ni Ceph ; les sorties montrées sont **représentatives** ;
- la règle HTTP de la CiliumNetworkPolicy `loki-entree` (proxy Envoy de Cilium sur un port reçu par un Service `LoadBalancer` à `externalTrafficPolicy: Local`) et l'adresse source vue pour `gw01`/`gw02` (10.10.40.2/.3 supposées) ;
- l'accès du *client S3 de Loki* au RGW avec `s3forcepathstyle: true` et la région `us-east-1` (le RGW de M08 l'accepte pour Thanos et MédiDoc) ; le préfixe exact des objets d'index (`index/…`) que vérifie le check ;
- la persistance du journal systemd sur l'image dorée Debian 13 (`/var/log/journal` présent : le rôle `alloy` refuse sinon) ;
- la lecture des fichiers de `/var/log/pods` par Alloy en UID 0 **sans aucune capacité** (fichiers 0640 de root : la lecture par le propriétaire ne demande pas `CAP_DAC_OVERRIDE`) ; si ton runtime pose d'autres droits, ajoute `DAC_READ_SEARCH` et note-le ;
- l'unité systemd durcie des VMs (`MemoryDenyWriteExecute`, `RestrictAddressFamilies`) avec la lecture du journal par `libsystemd` : vérifie `systemctl status alloy` et la présence des lignes après le premier passage.

---

### M22-E01 — Test de positionnement : journaux

**Barème** : 2 points par question. 2 = complet et justifié ; 1 = idée juste mais incomplète ; 0 = faux ou blanc. Total sur 28. En dessous de 14, relis les « Concepts clés » de l'introduction avant E02 ; les questions 4 à 7 sont reprises en E03, E06 et M22-E14 ; 8 et 9 en E03, E05 et E07 ; 10 à 14 en E02, E09, M22-E13 et M22-E16.

**Réponses argumentées — journaux, métriques, traces**

**1. Trois signaux.** Métrique : « le taux d'erreurs de MédiAgenda dépasse-t-il 1 % depuis 5 minutes ? » — un nombre, peu coûteux, comparable dans le temps, parfait pour **alerter**. Journal : « quelle exception, sur quelle route, pour quelle requête ? » — l'événement avec son contexte. Trace : « dans cette requête de 3 s, quel appel (PostgreSQL, Valkey, MédiDoc) a pris 2,8 s ? » — le chemin d'une requête à travers les services. On alerte sur des métriques parce qu'elles sont agrégées en amont (une série par combinaison d'étiquettes, quelques octets par point), évaluées en continu à faible coût, et qu'elles mesurent un **symptôme** (M21) ; une alerte sur journaux doit relire et compter des lignes à chaque évaluation, plus cher et plus fragile (format de ligne qui change). Les journaux alertent quand l'information **n'existe pas** en métrique (échecs d'authentification dans l'audit, message d'erreur précis : M22-E08).

**2. Réponse B.** Les lignes d'erreur donnent le message, la route, l'exception : la **cause**, ou presque. A dit **où** (quelle route) mais pas **pourquoi** ; C dit si des pods sont tombés (peut-être une conséquence) ; D décrit un autre symptôme. Le bon enchaînement : l'alerte vient de A (M21), l'enquête continue en B (M22), éventuellement dans une trace (M23).

**3. Fichier dans le conteneur.** (1) Il disparaît avec le conteneur (couche inscriptible) : un pod remplacé emporte ses journaux. (2) Ni `kubectl logs` ni l'agent du nœud ne le voient : il faudrait un *sidecar* ou un volume partagé. (3) Il remplit le disque du conteneur (ou l'`emptyDir`), sans rotation, jusqu'à l'éviction du pod ; et un système de fichiers racine en lecture seule (M14) l'interdit. Le facteur XI : une application ne gère pas ses fichiers de journaux, elle écrit un **flux d'événements** sur la sortie standard, et c'est l'environnement d'exécution qui le collecte et le route — ce que font nos trois applications (`apps/README.md`).

**Réponses argumentées — index et cardinalité**

**4. Index inversé ou index d'étiquettes.** OpenSearch découpe chaque ligne en termes et tient un **index inversé** (terme → documents) de tous les champs : écriture coûteuse (analyse, index qui pèse souvent autant que les données, mémoire), recherche plein texte **très rapide** sur n'importe quel mot, agrégations riches. Loki n'indexe que les **étiquettes** des flux (quelques valeurs par flux) ; les lignes sont compressées par blocs (chunks) dans le stockage objet : écriture et stockage **peu coûteux**, requête rapide quand le sélecteur d'étiquettes réduit beaucoup le volume à lire, lente quand on cherche un mot rare dans des téraoctets sans sélecteur précis (Loki parallélise la lecture brute). M22-E15 le mesure.

**5. Cardinalité.** Le nombre de flux est le produit des valeurs des étiquettes. `pod` : chaque déploiement crée de nouveaux noms de pods (et un `kubectl rollout` remplace tous les pods) : le nombre de flux suit le nombre de pods qui ont existé (des centaines par semaine) au lieu des conteneurs (quelques-uns). `request_id` : **un flux par requête**, des millions : chaque flux ne contient qu'une ligne, chaque ligne devient un chunk et une entrée d'index : Loki s'effondre (limites de flux, mémoire de l'ingester). `code_http` : une dizaine de valeurs, multiplie les flux par dix pour un filtre qu'une analyse (`| json | code >= 500`) ou une métadonnée structurée fait aussi bien. On refuse les trois ; `pod` et `request_id` vont en **métadonnées structurées** (M22-E03, E06).

**6. Réponse B.** Une métadonnée structurée est attachée à **chaque ligne**, stockée avec elle dans le chunk, **non indexée** : elle ne crée pas de flux et se filtre après le sélecteur (`{…} | pod="…"`), sans analyser la ligne. A est faux (non indexée, et visible dans Grafana) ; C décrit un analyseur à l'écriture que Loki ne fait pas (il le fait à la lecture) ; D décrit les étiquettes **extraites** par un analyseur à la requête.

**7. Journal structuré.** Une ligne JSON (ou logfmt) donne des champs nommés et typés : on filtre (`| json | code >= 500`), on compte, on extrait des nombres (`unwrap duree_ms`), sans expressions régulières fragiles ; les champs survivent aux changements de libellé du message. Ce que cela ne règle pas : le **contenu** (un champ peut contenir une donnée personnelle), le **volume** (un journal structuré bavard reste bavard), la **cohérence** entre applications (`niveau` chez MédiAgenda, `level` chez MédiDoc), la **corrélation** entre services (il faut un identifiant partagé : `request_id`, puis `trace_id` au M23).

**Réponses argumentées — collecte**

**8. Fichiers des conteneurs.** Le kubelet demande au runtime d'écrire la sortie de chaque conteneur dans `/var/log/pods/<espace>_<pod>_<uid>/<conteneur>/<n>.log` (format CRI : horodatage, flux, F/P, message), avec des liens dans `/var/log/containers/`. Quand le pod est **supprimé**, le kubelet supprime ses fichiers : ce qui n'a pas été lu est perdu. Le fichier de **positions** retient, par fichier, jusqu'où l'agent a lu et envoyé : au redémarrage de l'agent, il reprend là (ni trou ni doublon). Sans lui (ou s'il est dans un volume éphémère), l'agent relit tout (doublons) ou repart de la fin (trou).

**9. Événements dans un DaemonSet.** Les événements sont une **source unique** (l'API) : six pods qui la lisent envoient chacun chaque événement, six doublons, et six fois la charge sur l'API. Solutions : un seul lecteur (un Deployment à un réplica, à part), ou une répartition entre les pods de l'agent (clustering d'Alloy : un seul membre de la grappe prend la cible « tous les espaces », M22-E07).

**Réponses argumentées — multi-locataire, rétention, données personnelles**

**10. Réponse B.** Avec `auth_enabled: true`, une requête sans `X-Scope-OrgID` est refusée (HTTP 401, *no org id*). A est le comportement **inverse** : en mono-locataire (`auth_enabled: false`), tout va dans le locataire implicite `fake`. C n'existe pas (on peut lire plusieurs locataires explicitement, avec `a|b` et la fédération de requêtes activée, pas « tous ») ; D n'existe pas dans Loki.

**11. L'en-tête ne suffit pas.** Loki croit l'en-tête sur parole : quiconque peut parler à Loki peut lire ou écrire **n'importe quel** locataire. Il faut l'entourer : réseau (CNP : seuls Grafana, Alloy, les VMs en écriture et MGMT y accèdent, M22-E02), un point d'entrée qui **pose** l'en-tête d'après l'identité (Grafana pose le locataire de chaque source ; un mandataire authentifiant ou la passerelle d'Enterprise Logs en production, M24), et les droits dans Grafana (qui voit quelle source, M22-E16).

**12. Rétentions.** L'audit sert à **prouver** (HDS, ISO 27001 : traçabilité des actions sur la plateforme, enquêtes a posteriori) ; les exigences parlent en mois, voire en années. Les journaux applicatifs servent au **diagnostic** : leur valeur décroît vite, et ils contiennent davantage de données personnelles indirectes (adresses IP, identifiants). Tout garder un an : coût de stockage, requêtes plus lentes, et surtout **minimisation** du RGPD (on ne conserve pas au-delà de ce qui est nécessaire à la finalité) ; plus on garde, plus une fuite est grave et plus un effacement est difficile. D'où des rétentions par locataire (M22-E13).

**13. NIR dans un journal.** Le NIR et le nom associé à un rendez-vous médical sont des **données de santé** (catégorie particulière, article 9 du RGPD) ; leur hébergement exige un hébergeur certifié **HDS**, un accès restreint et tracé, une durée limitée ; et le NIR a un cadre d'usage propre. Le journal, lui, est copié partout (Loki, compartiment, sauvegardes, écrans), lu par toute l'équipe : violation de la minimisation et du besoin d'en connaître. Deux lignes de défense : (1) **l'application ne journalise pas** de données personnelles (revue de code, tests, identifiants techniques à la place) ; (2) **la collecte masque** ce qui passe malgré tout (motifs reconnaissables : NIR, courriels). Seule la première est complète : un nom en texte libre n'est pas reconnaissable par une expression régulière (M22-E09).

**14. Droit à l'effacement.** Il faut savoir **où** sont les données d'une personne pour les effacer ; une donnée dans des journaux répartis, compressés, sauvegardés est presque impossible à retrouver et à effacer proprement. Conséquences de conception : ne pas journaliser de données personnelles (identifiants techniques seulement, que l'application sait relier à la personne et effacer chez elle) ; des rétentions courtes qui effacent d'elles-mêmes ; une API de suppression (Loki en a une, M22-E13) pour le cas où une donnée est entrée par erreur ; et documenter tout cela dans la politique (M22-E09).

---

### M22-E02 — Loki multi-locataire sur le RGW

**Solution**

*A. Le stockage.*

1. Utilisateur RGW, quota, identifiants (sur `ceph01`, comme au M08 et pour Thanos au M21) :
   ```
   [root@ceph01 ~]# radosgw-admin user create --uid=loki --display-name="Loki k8s-par1 (M22)" | jq '.keys[0] | {access_key}'
   [root@ceph01 ~]# radosgw-admin quota set --quota-scope=user --uid=loki --max-size=50G
   [root@ceph01 ~]# radosgw-admin quota enable --quota-scope=user --uid=loki
   [root@ceph01 ~]# radosgw-admin user info --uid=loki | jq '.user_quota'
   ```
   La clé secrète ne s'affiche qu'une fois, dans ton terminal : recopie-la directement dans les deux fichiers, jamais dans un ticket.
   ```
   admin@adm01:~$ install -m 600 /dev/null ~/.config/workbook/s3-loki.env
   admin@adm01:~$ editor ~/.config/workbook/s3-loki.env        # AWS_ACCESS_KEY_ID=…  AWS_SECRET_ACCESS_KEY=…
   admin@adm01:~/src/k8s$ ansible-vault create --vault-id critique@outils/vault-pass-client.sh secrets/loki.yml
   ```
   Forme du fichier Vault : [`k8s/secrets/loki.yml.exemple`](fichiers/M22-E02/k8s/secrets/loki.yml.exemple).
2. Compartiment, avec les clés de `loki` (c'est lui qui en sera propriétaire) :
   ```
   admin@adm01:~$ set -a; . ~/.config/workbook/s3-loki.env; set +a
   admin@adm01:~$ aws --endpoint-url https://rgw.par1.medisphere.internal s3api create-bucket --bucket loki-k8s-par1
   admin@adm01:~$ aws --endpoint-url https://rgw.par1.medisphere.internal s3api list-objects-v2 --bucket loki-k8s-par1
   ```
   La seconde commande ne renvoie rien (compartiment vide). La racine MédiSphère est dans le magasin système de `adm01` (M06) : aucune option `--no-verify-ssl`.
3. Le composant `loki` de `secrets-k8s.sh` reprend le modèle de `thanos` (M21-E24) : lecture de `secrets/loki.yml` par `ansible-vault view`, puis `kubectl create secret generic loki-objstore -n journaux --from-env-file=/dev/stdin --dry-run=client -o yaml | kubectl apply -f -` avec `LOKI_S3_ACCESS_KEY_ID` et `LOKI_S3_SECRET_ACCESS_KEY`. L'espace `journaux` est créé par l'Application `loki` (étape 9) : on lance le script **après** la première synchronisation ; en attendant, le pod Loki reste en `CreateContainerConfigError` (« secret "loki-objstore" not found »), sans dommage.

*B. Le chart et ses valeurs.*

4. Entrée du miroir : [`charts-miroir/charts.yaml.extrait`](fichiers/M22-E02/charts-miroir/charts.yaml.extrait) (empreinte `bf3e8a09…` relevée dans l'index du dépôt `grafana-community`). Attention au **déménagement** du chart : `grafana/loki` ne sert plus qu'à l'édition Enterprise (versions 7.x, Loki 3.6) ; le chart de la communauté est `grafana-community/loki` 19.x.
5. Valeurs par défaut lues dans le chart 19.0.3 :

   | Valeur | Défaut | Conséquence |
   |---|---|---|
   | `deploymentMode` | `Monolithic` | un binaire unique — ce qu'on veut |
   | `loki.auth_enabled` | `true` | multi-locataire — ce qu'on veut |
   | `gateway.enabled` | `true` | un Deployment nginx devant Loki (auth basique, routage) |
   | `chunksCache.enabled`, `resultsCache.enabled` | `true` | deux StatefulSets memcached, **8 Gio** de mémoire allouée pour le cache de chunks |
   | `lokiCanary.enabled` | `true` | un DaemonSet qui écrit et relit des lignes de test |
   | `sidecar.rules.enabled` + `singleBinary.sidecar` | `true` | un conteneur `k8s-sidecar` dans le pod Loki… |
   | `rbac.namespaced` | `false` | …avec une **ClusterRole qui lit tous les Secrets et ConfigMaps du cluster** |
   | `minio.enabled` | `false` | (le sous-chart MinIO, déprécié, n'est pas déployé) |

   Avec les défauts et un stockage S3, le chart déploie donc six charges de travail et une ClusterRole trop large pour un lab qui veut un pod.
6. [`observabilite/loki/values.yaml`](fichiers/M22-E02/observabilite/loki/values.yaml). Ce qu'il faut retenir :
   - `loki.storage` : `type: s3`, `bucketNames.chunks`, bloc `s3` avec `endpoint`, `s3ForcePathStyle: true` (le RGW n'a pas de nom générique `*.rgw…` pour l'adressage virtuel), `region` (exigée par le client, ignorée par le RGW), `accessKeyId: ${LOKI_S3_ACCESS_KEY_ID}` et `secretAccessKey: ${LOKI_S3_SECRET_ACCESS_KEY}`, `http_config.ca_file` vers la racine montée ;
   - `singleBinary.extraEnvFrom` (le Secret) et `extraVolumes`/`extraVolumeMounts` (la racine) ;
   - `loki.schemaConfig` : `tsdb`, `v13`, `from` dans le passé proche (jamais une date future : les lignes arrivées avant ne seraient pas lisibles), période de 24 h ;
   - `loki.limits_config` : défauts du chart et `discover_service_name: []` — sans elle, Loki **ajoute** une étiquette `service_name` (copiée de `app`, `container`, `job`…) à chaque flux, hors de notre liste fermée ;
   - `ruler.enabled: false` (activé en E08), `sidecar.rules.enabled: false`, `rbac.namespaced: true`, `gateway`, caches, canari et test coupés ;
   - `monitoring.serviceMonitor` avec `medisphere.internal/supervision: "oui"` (le sélecteur du M21).
   Rendu et lecture de la configuration générée :
   ```
   admin@adm01:~/m22/e02$ helm pull oci://registry.par1.medisphere.internal/charts/loki --version 19.0.3 --untar
   admin@adm01:~/m22/e02$ helm template loki ./loki -n journaux -f ~/src/observabilite/loki/values.yaml > rendu.yaml
   admin@adm01:~/m22/e02$ yq 'select(.kind == "ConfigMap" and .metadata.name == "loki") | .data["config.yaml"]' rendu.yaml | head -40
   auth_enabled: true
   …
   common:
     compactor_grpc_address: 'loki.journaux.svc.cluster.local:9095'
     path_prefix: /var/loki
     replication_factor: 1
     storage:
       s3:
         access_key_id: ${LOKI_S3_ACCESS_KEY_ID}
         bucketnames: loki-k8s-par1
         endpoint: https://rgw.par1.medisphere.internal
         http_config:
           ca_file: /etc/loki/racine/medisphere-root-ca.crt
   …
   admin@adm01:~/m22/e02$ yq 'select(.kind == "StatefulSet") | .spec.template.spec.containers[0].args' rendu.yaml
   - -config.file=/etc/loki/config/config.yaml
   - -config.expand-env=true
   - -memberlist.advertise-addr=$(POD_IP)
   - -target=all
   ```
   (Le chart ajoute de lui-même `-config.expand-env=true`.)
7. La ConfigMap `loki` est dans Git (rendue par Argo CD depuis les valeurs) et lisible par tout ce qui lit les ConfigMaps de `journaux` ; `/config` de Loki est lisible depuis MGMT. Une clé en clair y serait copiée partout. Ici la ConfigMap ne contient que `${LOKI_S3_SECRET_ACCESS_KEY}` ; la valeur n'existe que dans le Secret, dans l'environnement du processus et, développée, en mémoire ; `/config` l'affiche **masquée** (les champs secrets de la configuration de Loki sont des types « secret » qui ne s'impriment pas).

*C. Ce que le chart ne fait pas.*

8. Manifestes : [`loki/manifestes/`](fichiers/M22-E02/observabilite/loki/manifestes/) et [`loki/kustomization.yaml`](fichiers/M22-E02/observabilite/loki/kustomization.yaml) :
   - **espace** `journaux` : Pod Security `enforce: privileged`, `warn`/`audit: restricted`. Le DaemonSet d'Alloy (E03) lit `/var/log` du nœud par `hostPath`, ce que `baseline` interdit déjà ; l'exception est **écrite** dans le manifeste, et l'avertissement `restricted` continue de signaler tout pod de Loki qui s'en écarterait. Annotations `sync-wave: "-1"` (créé avant le reste) et `Prune=false` (retirer l'Application ne supprime jamais l'espace) ;
   - **racine** : ConfigMap générée depuis le certificat **public** de la racine (copie de `/usr/local/share/ca-certificates/medisphere-root-ca.crt`), nom fixe ;
   - **Service** `loki-externe` : seul le port 3100 (le Service `loki` du chart publie aussi le gRPC 9095 et 9096) ; annotation `lbipam.cilium.io/ips: 10.10.41.62` (plage des services à adresse demandée du M15) ; `externalTrafficPolicy: Local` : l'adresse du client est conservée (la CNP filtre dessus) et seul le nœud qui porte le pod annonce la /32 en BGP ; annotation d'ExternalDNS pour le nom ;
   - **CNP** `loki-entree` (tableau en tête du fichier) : Alloy (même espace), Grafana et Prometheus (`supervision`, Prometheus limité à `GET /metrics`), Loki lui-même (memberlist 7946, gRPC 9095), MGMT en entier, et les autres réseaux du lab **seulement** en `POST /loki/api/v1/push` : la règle `rules.http` fait passer ce trafic par le proxy Envoy de Cilium, qui refuse tout le reste par un 403.
9. Application : [`gitops/plateforme/loki.yaml`](fichiers/M22-E02/gitops/plateforme/loki.yaml) : trois sources (chart OCI de Harbor, même forme que `kube-prometheus-stack` au M21 ; `ref: values` ; `path: loki`), `ServerSideApply=true`, `CreateNamespace=false` (l'espace est un manifeste), pas de finaliseur. Après la synchronisation :
   ```
   admin@adm01:~/src/k8s$ outils/secrets-k8s.sh loki
   admin@adm01:~$ kubectl --context k8s-par1 -n journaux get pods,pvc,svc
   NAME         READY   STATUS    RESTARTS   AGE
   pod/loki-0   1/1     Running   0          3m
   NAME                                  STATUS   VOLUME     CAPACITY   ACCESS MODES   STORAGECLASS
   persistentvolumeclaim/storage-loki-0  Bound    pvc-…      20Gi       RWO            ceph-rbd
   NAME                    TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)
   service/loki            ClusterIP      10.96.…        <none>        3100/TCP,9095/TCP,9096/TCP
   service/loki-externe    LoadBalancer   10.96.…        10.10.41.62   3100:3…/TCP
   service/loki-headless   ClusterIP      None           <none>        3100/TCP,9095/TCP,9096/TCP
   service/loki-memberlist ClusterIP      None           <none>        7946/TCP
   ```
   Dans les journaux du conteneur, au démarrage : `msg="Loki started"`, et l'absence d'erreur `AccessDenied`/`x509` sur le compartiment.

*D. Vérifier.*

10. Depuis `adm01` :
    ```
    admin@adm01:~$ L=http://loki.apps.par1.medisphere.internal:3100
    admin@adm01:~$ curl -s $L/ready
    ready
    admin@adm01:~$ curl -s $L/loki/api/v1/status/buildinfo | jq -c '{version, revision}'
    {"version":"3.7.9","revision":"d3b4a2f7"}
    admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' $L/loki/api/v1/labels
    401
    admin@adm01:~$ curl -s -H 'X-Scope-OrgID: plateforme' "$L/loki/api/v1/labels?since=1h" | jq -c .
    {"status":"success"}
    ```
    `buildinfo` et `/ready` ne sont pas propres à un locataire ; les API de données exigent l'en-tête (401 « no org id ») ; le locataire `plateforme` existe dès qu'on le nomme, mais il est vide (`data` absent).
11. Écriture et lecture à la main :
    ```
    admin@adm01:~$ jq -nc --arg t "$(date +%s%N)" '{streams: [{stream: {job: "essai-manuel"}, values: [[$t, "M22-E02 ligne de test"]]}]}' \
        | curl -s -X POST -H 'Content-Type: application/json' -H 'X-Scope-OrgID: essai' --data-binary @- $L/loki/api/v1/push -w '%{http_code}\n'
    204
    admin@adm01:~$ curl -s -G -H 'X-Scope-OrgID: essai' $L/loki/api/v1/query_range --data-urlencode 'query={job="essai-manuel"}' | jq -r '.data.result[].values[][1]'
    M22-E02 ligne de test
    admin@adm01:~$ curl -s -G -H 'X-Scope-OrgID: plateforme' $L/loki/api/v1/query_range --data-urlencode 'query={job="essai-manuel"}' | jq '.data.result | length'
    0
    ```
    Le cloisonnement est réel : la même requête ne voit rien dans un autre locataire. (adm01 est sur MGMT : la CNP lui permet de pousser ; depuis `dns01`, la même poussée passe, le `GET` reçoit un 403 d'Envoy.)
12. `curl -s $L/config` : `auth_enabled: true` (en tête), `schema_config.configs[0].schema: v13`, `common.storage.s3.bucketnames: loki-k8s-par1` ; `secret_access_key` y apparaît **masquée**. ⚠️ À vérifier sur ton lab : la forme exacte du masque.
13. [`observabilite/grafana/sources-loki.yaml`](fichiers/M22-E02/observabilite/grafana/sources-loki.yaml), ajoutée aux ressources de la `kustomization.yaml` racine ([extrait](fichiers/M22-E02/observabilite/kustomization.yaml.extrait)) : une ConfigMap étiquetée `grafana_datasource: "1"` dans `supervision`, lue par le *sidecar* de Grafana de kube-prometheus-stack (le même mécanisme qui provisionne la source Prometheus au M21) ; une source par locataire, l'en-tête `X-Scope-OrgID` en `httpHeaderName1`/`httpHeaderValue1` (la valeur est rangée dans `secureJsonData`, chiffrée dans la base de Grafana), UID stables `loki-<locataire>`, `editable: false`. Aucune des quatre ne montre la ligne de test : elle est dans `essai`, qui n'a pas de source (c'est voulu : `essai` est un bac à sable).
14. Après une à deux heures :
    ```
    admin@adm01:~$ aws --endpoint-url https://rgw.par1.medisphere.internal s3 ls s3://loki-k8s-par1/
                               PRE index/
                               PRE mediagenda/
                               PRE medidoc/
                               PRE plateforme/
    admin@adm01:~$ aws --endpoint-url https://rgw.par1.medisphere.internal s3 ls s3://loki-k8s-par1/index/
                               PRE loki_index_20748/
    ```
    Un préfixe par locataire pour les chunks, et `index/<table du jour>/` pour l'index TSDB (le numéro de table est le nombre de jours depuis le 1er janvier 1970 : 20748 pour le 22 octobre 2026). Pendant la première demi-heure, l'ingester accumule les lignes en mémoire (protégées par le WAL sur le PVC) : un chunk part quand il est plein, inactif depuis `chunk_idle_period` (30 min par défaut) ou âgé de `max_chunk_age` (2 h) ; l'index TSDB est construit et envoyé par lots (toutes les 15 min environ). ⚠️ À vérifier sur ton lab : les noms exacts des préfixes et de la table d'index.
15. Fiche du service : [`docs/observabilite/journaux/loki.md`](fichiers/M22-E02/medisphere/docs/observabilite/journaux/loki.md) ; matrice des flux du cluster : [`matrice-flux-cluster.extrait.md`](fichiers/M22-E02/medisphere/docs/kubernetes/reseau/matrice-flux-cluster.extrait.md).

**Explications**

Le mode **monolithique** fait tourner toutes les fonctions de Loki dans un processus : distributeur (valide et répartit les écritures), *ingester* (construit les chunks en mémoire, WAL, envoi au stockage), requêteur et *query-frontend* (découpe et exécute les requêtes), *compactor* (fusionne l'index, applique la rétention, E13), *ruler* (E08). C'est le mode recommandé jusqu'à quelques dizaines de Go par jour ; au-delà, le mode *microservices* sépare ces fonctions. Le mode « simple scalable » (lecture / écriture / *backend*) est déprécié et disparaîtra avec Loki 4.

Le **stockage objet** est la seule mémoire durable de Loki : chunks et index y sont tous deux (TSDB « shipper ») ; le PVC ne porte que le WAL et les fichiers en cours. Perdre le pod n'est pas grave ; perdre le compartiment, si. D'où un utilisateur RGW **dédié** (quota, révocation possible sans toucher Thanos ou MédiDoc) et la règle « une panne ne supprime jamais de données de `loki-k8s-par1` ».

Le **multi-locataire** est « gratuit » côté Loki (un préfixe et un index par locataire) ; tout le travail est autour : qui pose l'en-tête. Grafana pose celui de chaque source ; Alloy pose celui de chaque ligne (E03) ; le réseau empêche les autres de venir le poser à leur guise (CNP), et l'authentification réelle viendra au M24.

**Alternatives**

- **Passerelle nginx du chart** : utile pour une authentification basique par locataire (fichier `htpasswd` généré depuis `loki.tenants`) ; mais des mots de passe statiques, un composant de plus, et une sécurité que la CNP et le futur mandataire OIDC (M24) font mieux.
- **Mode `SimpleScalable`** avec trois cibles : déprécié ; **microservices** (distributed) : une dizaine de déploiements, pertinent au-delà du lab.
- **Stockage sur `s3-01`** (SeaweedFS du socle) plutôt que le RGW : possible, mais le socle porte l'état OpenTofu et les sauvegardes etcd ; les données d'observabilité vont sur `ceph-par1` (PLAN §4.11, comme Thanos).
- **Client « thanos objstore »** de Loki (`use_thanos_objstore: true`) : nouvelle bibliothèque de stockage, appelée à devenir le défaut ; on garde le client historique, le mieux documenté pour un RGW.

**Pièges classiques**

- Prendre le chart `grafana/loki` d'un tutoriel : il ne suit plus la version communautaire (7.x, Loki 3.6, orienté Enterprise).
- Laisser les défauts : passerelle, deux memcached (dont un de 8 Gio), canari, et une ClusterRole qui lit **tous les Secrets** pour un *sidecar* inutilisé.
- Un `from` de schéma dans le futur : Loki écrit avec le schéma précédent (aucun ici : erreur), ou les lignes deviennent illisibles au changement de date.
- Oublier `discover_service_name: []` : une étiquette `service_name` apparaît sur chaque flux, et les contrôles d'étiquettes « hors liste » passent au rouge.
- `insecure: true` ou `insecure_skip_verify` vers le RGW « pour que ça marche » : la racine se monte en dix lignes.
- Créer le Secret avant l'espace, ou l'espace à la main : Argo CD le prendrait ensuite en charge avec des étiquettes différentes de celles du dépôt.
- Conclure à une panne parce que le compartiment est vide la première heure.
- Croire que l'en-tête `X-Scope-OrgID` protège quoi que ce soit sans la CNP.

**En production chez MédiSphère**

Loki en mode distribué (au moins trois *ingesters*, réplication 3, *zone awareness* sur les baies), caches memcached dimensionnés, *query-frontend* et *query-scheduler* séparés ; la passerelle ou un mandataire authentifiant (OIDC, M24) qui pose le locataire d'après l'identité ; TLS de bout en bout (Service externe en HTTPS, certificat cert-manager) ; supervision de Loki par ses tableaux de bord et alertes officiels (« mixins ») ; le compartiment versionné et répliqué sur PAR2 (M22-E16).

---

### M22-E03 — Alloy dans le cluster : pods et nœuds

**Solution**

1. Lecture du chart `grafana/alloy` 1.14.1 : configuration dans une ConfigMap créée par le chart à partir de `alloy.configMap.content` (vide par défaut) ; positions sous `alloy.storagePath: /tmp/alloy`, c'est-à-dire dans le système de fichiers du conteneur (perdues à chaque redémarrage) ; RBAC : une ClusterRole qui lit pods, journaux de pods, services, *endpoints*, nœuds, événements, **ConfigMaps et Secrets** de tout le cluster, et les CRD de prometheus-operator ; CRD `PodLogs` (`monitoring.grafana.com`) créée par défaut (`crds.create: true`) ; un DaemonSet par défaut, plus un *config-reloader* qui recharge Alloy quand la ConfigMap change.
2. [`observabilite/alloy/config.alloy`](fichiers/M22-E03/observabilite/alloy/config.alloy), commenté bloc par bloc. Points clés :
   - `discovery.kubernetes` avec `selectors { role = "pod", field = "spec.nodeName=" + sys.env("NODE_NAME") }` : chaque pod d'Alloy ne surveille que les pods de son nœud ;
   - `discovery.relabel` : `cluster` et `job` constants, `namespace`, `container`, `node` ; `app` par une règle à quatre sources (`;*([^;]+).*` : la première valeur non vide) ; `pod` et `locataire` **temporaires** ; `__path__ = /var/log/pods/*<uid>/<conteneur>/*.log` ;
   - `local.file_match` puis `loki.source.file` ;
   - `loki.process "pods"` : `stage.cri { }` (analyse CRI, recollage des lignes partielles, horodatage du runtime) ; `stage.tenant { label = "locataire" }` ; `stage.structured_metadata` qui **déplace** `pod` et `stream` (ajoutée par `stage.cri`) en métadonnées structurées ; `stage.label_drop` de `filename` (ajoutée par `loki.source.file`) et de `locataire` ;
   - journald : `loki.relabel "journal"` (unité et niveau depuis `__journal__systemd_unit` et `__journal_priority_keyword`), `loki.source.journal` (`max_age = "12h"`, étiquettes `cluster`, `job`, `node`), `loki.process "journal"` qui écarte `debug` et range `unite`, `niveau` en métadonnées structurées ;
   - `loki.write` vers le Service interne, `tenant_id = "plateforme"` par défaut.
3. Validation locale :
   ```
   admin@adm01:~/m22/e03$ curl -sLO https://github.com/grafana/alloy/releases/download/v1.21.1/alloy-linux-amd64.zip
   admin@adm01:~/m22/e03$ curl -sL https://github.com/grafana/alloy/releases/download/v1.21.1/SHA256SUMS | grep ' alloy-linux-amd64.zip$' | sha256sum -c -
   alloy-linux-amd64.zip: OK
   admin@adm01:~/m22/e03$ unzip -q alloy-linux-amd64.zip && ./alloy-linux-amd64 fmt --test ~/src/observabilite/alloy/config.alloy && NODE_NAME=x ./alloy-linux-amd64 validate ~/src/observabilite/alloy/config.alloy && echo valide
   valide
   admin@adm01:~/m22/e03$ sed 's/max_age       = "12h"/max_agex = "12h"/' ~/src/observabilite/alloy/config.alloy > faux.alloy && ./alloy-linux-amd64 validate faux.alloy
   Error: faux.alloy:…: unrecognized attribute name "max_agex"
   ```
   `validate` vérifie les composants, les attributs, les types et les références entre composants ; il ne sait rien du **contenu** : ni le format réel des fichiers, ni si Loki accepte le locataire, ni la cardinalité des étiquettes (E11).
4. Job de CI : [`.gitlab-ci.yml.extrait`](fichiers/M22-E03/observabilite/.gitlab-ci.yml.extrait) (image `grafana/alloy:v1.21.1` par le cache Harbor, `fmt --test` puis `validate`).
5. [`observabilite/alloy/values.yaml`](fichiers/M22-E03/observabilite/alloy/values.yaml) et [`alloy/kustomization.yaml`](fichiers/M22-E03/observabilite/alloy/kustomization.yaml) : `configMap.create: false` + nom fixe `alloy-config` (générée par kustomize depuis `config.alloy`, `disableNameSuffixHash`) ; `storagePath: /var/lib/alloy/donnees` sur un `hostPath` `/var/lib/alloy` ; `mounts.varlog: true` (lecture seule) ; `NODE_NAME` depuis `spec.nodeName` ; UID 0 sans aucune capacité, racine en lecture seule ; tolérances du plan de contrôle et de `dedie=bdd` ; PriorityClass `medisphere-critique` ; RBAC réduit à pods, espaces et nœuds ; `crds.create: false` ; ServiceMonitor étiqueté pour le Prometheus du M21.
6. [`gitops/plateforme/alloy.yaml`](fichiers/M22-E03/gitops/plateforme/alloy.yaml). Après synchronisation :
   ```
   admin@adm01:~$ kubectl --context k8s-par1 -n journaux get ds alloy -o wide
   NAME    DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
   alloy   6         6         6       6            6           <none>          2m
   admin@adm01:~$ kubectl --context k8s-par1 -n journaux port-forward ds/alloy 12345:12345
   ```
   `http://127.0.0.1:12345` : le graphe des composants, tous « healthy » ; la page de `loki.source.file.pods` liste les fichiers suivis et leurs positions.
7. Dans Explore, `Loki — plateforme`, `{namespace="kube-system"}`, `{namespace="journaux", container="loki"}`, `{job="journald", node="k8s-cp02"}` ; `Loki — mediagenda`, `{namespace="mediagenda-recette"}`. Étiquettes indexées :
   ```
   admin@adm01:~$ for t in plateforme mediagenda medidoc; do echo -n "$t : "; curl -s -H "X-Scope-OrgID: $t" "$L/loki/api/v1/labels?since=15m" | jq -c .data; done
   plateforme : ["app","cluster","container","job","namespace","node"]
   mediagenda : ["app","cluster","container","job","namespace","node"]
   medidoc : ["app","cluster","container","job","namespace","node"]
   ```
   (`pod`, `stream`, `unite`, `niveau` n'y sont pas : ce sont des métadonnées structurées ; `{namespace="journaux"} | pod=~"loki-.+"` les filtre.)
8. Pod supprimé pendant le trafic : le nouveau pod relit le fichier de positions sur le disque du nœud et reprend à l'octet près ; les lignes écrites pendant la dizaine de secondes de coupure arrivent avec un léger retard, sans doublon ni trou (le fichier du conteneur est resté sur le disque). Avec les positions dans `/tmp`, le nouveau pod repartirait du **début** de chaque fichier encore présent : des milliers de lignes renvoyées (Loki écarte une entrée **identique** — même flux, même horodatage, même ligne — mais tout écart, par exemple un horodatage recalculé, produit un doublon visible) — et, au-delà de 7 jours, des refus.
9. `curl https://medidoc-dev.apps.par1.medisphere.internal/documents/inexistant` (ou l'adresse de MédiDoc publiée au M15) : une ligne `INFO` `"msg":"requête"` avec `code: 404` dans `Loki — medidoc`.

**Explications**

Alloy est un graphe de **composants** : chacun exporte des valeurs (`targets`, `receiver`, `rules`) que d'autres consomment ; les données circulent le long des `forward_to`. La découverte Kubernetes fournit des cibles avec des étiquettes internes (`__meta_kubernetes_*`) ; le *relabel* en fait des étiquettes Loki, exactement comme au M21 pour Prometheus. `stage.cri` est indispensable avec containerd : le fichier contient `2026-10-22T15:23:10.815930000Z stdout F {"horodatage": …}` ; sans lui, la ligne envoyée garde ce préfixe et l'horodatage est celui de la lecture.

Les **positions** dans un `hostPath` : le nouveau pod d'un DaemonSet tourne sur le même nœud que l'ancien, retrouve le même dossier, donc les mêmes positions. C'est la seule donnée d'état d'Alloy ; elle vaut quelques Ko.

Le **locataire par ligne** : `stage.tenant` écrit une étiquette réservée que `loki.write` lit pour choisir l'en-tête de chaque lot ; les lignes de locataires différents partent dans des requêtes différentes.

**Alternatives**

- `loki.source.kubernetes` (lecture par l'API du kubelet, sans `hostPath`, sans privilège) : plus simple à sécuriser, mais charge sur l'API et le kubelet, et une reprise moins fine après coupure ; pertinent pour un cluster où l'on n'a pas le droit de monter `/var/log`.
- Le chart `grafana/k8s-monitoring` (Alloy préconfiguré pour métriques, journaux, événements, traces) : rapide, mais une configuration générée moins lisible, et beaucoup de choses qu'on a déjà par kps.
- `alloy.configMap.content` (configuration dans les valeurs) : une seule source au lieu de deux, mais du code Alloy dans une chaîne YAML, sans `alloy fmt` ni coloration ; on garde un fichier `.alloy`.
- Le *clustering* d'Alloy dès maintenant : inutile pour les fichiers (chaque pod lit son nœud), utile pour les événements (E07).

**Pièges classiques**

- Découverte sans sélecteur de nœud : chaque pod surveille tous les pods du cluster ; ça « marche » (les fichiers des autres nœuds n'existent pas), mais l'API supporte six fois la charge.
- Oublier les **tolérances** : pas d'agent sur les nœuds de contrôle (donc pas d'audit en E07) ni sur `k8s-w03`.
- Les étiquettes ajoutées d'office : `filename` (par `loki.source.file`), `stream` (par `stage.cri`), `service_name` (par Loki si `discover_service_name` n'est pas vidé).
- `__journal_*` non relabelisées : elles sont **retirées** avant l'envoi ; l'unité systemd est perdue.
- Une valeur par défaut du chart qui donne à Alloy la lecture de tous les Secrets.
- Le *config-reloader* recharge la configuration, mais une configuration invalide est **refusée** par Alloy, qui garde l'ancienne : regarde ses journaux après chaque MR (et la CI l'aurait vue).

**En production chez MédiSphère**

Alloy supervisé (ServiceMonitor, alertes sur `loki_write_dropped_entries_total`, sur l'écart entre lignes lues et envoyées, sur les composants en échec) ; WAL de `loki.write` (expérimental en 1.21, donc pas encore) ; un pool de mémoire par nœud dimensionné sur les pics ; la même configuration étendue aux traces OTLP au M23 ; mise à jour d'Alloy par Renovate (M13) avec la CI de validation comme garde-fou.

---

### M22-E04 — LogQL : filtres, analyseurs et métriques de journaux

**Solution**

1. Rôle `outils_k8s` : une entrée `logcli` dans `outils_k8s_binaires` ([`defaults/main.yml.extrait`](fichiers/M22-E04/ansible/roles/outils_k8s/defaults/main.yml.extrait)) et une clé facultative `liens` dans [`tasks/binaire.yml`](fichiers/M22-E04/ansible/roles/outils_k8s/tasks/binaire.yml), qui nomme le lien `/usr/local/bin/logcli` (sinon il s'appellerait `logcli-linux-amd64`). `unarchive` lit les `.zip` (paquet `unzip` présent sur `adm01`).
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/outils-k8s.yml
   admin@adm01:~$ logcli --version
   logcli, version 3.7.9 (branch: release-3.7.x, revision: d3b4a2f7)
   admin@adm01:~$ echo 'export LOKI_ADDR=http://loki.apps.par1.medisphere.internal:3100' >> ~/.bashrc
   ```
2. `ressources/E04-trafic/trafic.sh` (lecture seule : des GET ; 404 et 422 volontaires).
3. [`requetes/E04.logql`](fichiers/M22-E04/observabilite/requetes/E04.logql), commenté question par question. Exemples avec logcli :
   ```
   admin@adm01:~$ logcli --org-id=plateforme query --since=15m --limit=5 '{namespace="journaux", container="loki"} | logfmt | level="info" | line_format "{{.caller}} {{.msg}}"'
   admin@adm01:~$ logcli --org-id=mediagenda query --since=15m '{namespace="mediagenda-recette", container="api"} | json | journal="mediagenda.acces" | code >= 400'
   admin@adm01:~$ logcli --org-id=mediagenda instant-query 'quantile_over_time(0.95, {namespace="mediagenda-recette", container="api"} | json | journal="mediagenda.acces" | unwrap duree_ms | __error__="" [5m]) by (route)'
   {route="/api/v1/creneaux"}  23.4
   {route="/api/v1/rendez-vous"}  11.8
   {route="/api/v1/rendez-vous/{rdv_id}"}  6.2
   {route="non-routee"}  1.9
   ```
   (Sorties représentatives.)
4. Une ligne sans `duree_ms` numérique (la ligne « rendez-vous créé », qui n'a pas ce champ) produit une erreur de conversion : l'étiquette `__error__` vaut `SampleExtractionErr` et la requête **échoue** si on ne filtre pas. `| __error__=""` après `unwrap` écarte ces lignes ; filtrer **avant** (`journal="mediagenda.acces"`) évite même de les analyser.
5. Coût : la réponse de l'API porte des statistiques (`data.stats.summary` : `execTime`, `totalBytesProcessed`, `bytesProcessedPerSecond`) ; `logcli query --stats` les affiche. `pattern` est le moins coûteux : il découpe la ligne par des littéraux fixes, sans analyser chaque paire clé-valeur ; `logfmt` analyse toute la ligne ; une `regexp` serait la plus chère. Sur une heure de journaux de Loki, l'écart est de l'ordre de 20 à 40 % ; il compte sur des téraoctets.
6. Analyse des étiquettes :
   ```
   admin@adm01:~$ logcli --org-id=plateforme series --since=1h --analyze-labels '{job=~".+"}'
   Total Streams:  ~150
   Unique Labels:  6
   Label Name  Unique Values  Found In Streams
   container   ~60            ~150
   app         ~45            ~150
   namespace   ~15            ~150
   node        6              ~150
   job         2              ~150
   cluster     1              ~150
   ```
   (Ordres de grandeur ; garde tes vrais chiffres pour M22-E14.)
7. MR sur `plateforme/observabilite`.

**Explications**

Une requête LogQL de journaux se lit de gauche à droite : le **sélecteur** choisit les flux dans l'index (la seule partie indexée), puis chaque étape du **pipeline** filtre ou transforme ligne par ligne. Mettre les filtres de ligne (`|=`, `!=`) **avant** les analyseurs est l'optimisation la plus rentable : un filtre de chaîne est bien moins cher qu'une analyse JSON. Une requête **métrique** (`count_over_time`, `rate`, `bytes_over_time`) agrège les lignes par fenêtre ; avec `unwrap`, elle agrège une **valeur** extraite (durée, taille). Les agrégations (`sum by`, `topk`) s'appliquent ensuite comme en PromQL.

**Alternatives**

- logcli installé par `uv tool` ou un paquet : pas de paquet Debian de logcli ; le binaire amont vérifié reste le plus simple, et le rôle `outils_k8s` en est le bon endroit (tous les outils d'administration).
- Grafana « Logs Drilldown » : exploration sans écrire de LogQL, utile pour découvrir ; les requêtes de l'astreinte restent écrites et versionnées.

**Pièges classiques**

- Un sélecteur qui n'a que des expressions régulières qui acceptent la chaîne vide (`{app=~".*"}`) : refusé.
- `| code >= 400` sans analyseur avant : `code` n'existe pas, le filtre ne garde rien.
- `unwrap` sans filtrer `__error__` : toute la requête échoue sur la première ligne non numérique.
- Une fenêtre `[5m]` plus courte que l'écart entre deux lignes : des trous dans le graphe, interprétés à tort comme des pannes.
- `logcli` sans `--org-id` : 401.
- Comparer `rate()` de journaux et `rate()` de Prometheus : le premier compte des **lignes** par seconde, pas des requêtes (une requête peut produire plusieurs lignes).

**En production chez MédiSphère**

Les requêtes utiles deviennent des panneaux de tableaux de bord versionnés (M21-E17), des règles du ruler (E08) ou des requêtes du runbook (E12). Les métriques tirées des journaux à fort volume deviennent des **règles d'enregistrement** évaluées une fois par minute plutôt que recalculées à chaque affichage.

---

### M22-E05 — Alloy sur les VMs du socle

**Solution**

1. Choix : **binaire amont vérifié par empreinte**, comme `node_exporter` au M21. Pour : même modèle que nos autres agents, version et retour arrière explicites (dossier versionné, lien), aucune dépendance à un dépôt tiers sur des VMs critiques (`gw01`, `ca01`). Contre : le rôle écrit lui-même l'unité systemd et le compte. Pour le paquet `.deb` d'`apt.grafana.com` : unité et compte fournis, mises à jour par APT ; contre : un dépôt de plus dont il faut vérifier la clé, une unité livrée moins durcie, et le risque d'une montée de version non décidée si l'épinglage manque.
2. Rôle : [`ansible/roles/alloy/`](fichiers/M22-E05/ansible/roles/alloy/) (`defaults`, `meta` avec `argument_specs`, `tasks/main.yml`, `handlers`, `templates/config.alloy.j2`, `templates/alloy.service.j2`). Points clés :
   - refus d'un système autre que Debian 13 et d'un journal volatil (`/var/log/journal` absent) ;
   - compte `alloy` membre de `systemd-journal` **et** `adm` (exigé par la documentation de `loki.source.journal` : sans eux, le composant démarre… et ne lit rien) ;
   - `get_url` avec `checksum: sha256:<URL de SHA256SUMS>`, `unarchive`, lien `/usr/local/bin/alloy` ;
   - gabarit validé **avant** d'être posé (`validate: /usr/local/bin/alloy validate %s`) ; rechargement par `systemctl reload` (unité : `ExecReload=/bin/kill -HUP $MAINPID`) ;
   - unité durcie : `ProtectSystem=strict` avec `ReadWritePaths=/var/lib/alloy`, aucune capacité, `MemoryMax=256M`, interface d'Alloy sur `127.0.0.1:12345` ;
   - contrôle final sur `/-/ready`.
   Le gabarit : `loki.source.journal` avec `host`, `role` (premier groupe `role_*` de l'inventaire NetBox), `site`, `job` ; niveaux écartés (variable) ; `unite` et `niveau` en métadonnées structurées ; écriture vers `loki.apps.par1.medisphere.internal:3100`, locataire `plateforme`.
3. [`playbooks/journaux-vms.yml`](fichiers/M22-E05/ansible/playbooks/journaux-vms.yml) (`hosts: socle`, `serial: 3`) :
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/journaux-vms.yml --limit mon01 --diff
   ```
4. Bordure : [`pare_feu.yml.extrait`](fichiers/M22-E05/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait) (transit VLAN 20 et VLAN 70 vers `LOKI` 10.10.41.62, TCP 3100, sortie VLAN 40) ; matrice : [`matrice-flux.extrait.md`](fichiers/M22-E05/medisphere/docs/socle/matrice-flux.extrait.md). `adm01` est sur MGMT, qui joint déjà tout le lab (M00). Les passerelles envoient **leur propre** trafic (chaîne `output`, ouverte) par leur interface du VLAN 40 : Loki voit 10.10.40.2 ou 10.10.40.3, que la CNP `loki-entree` autorise en `/32`.
5. Pipeline protégé, puis second passage :
   ```
   PLAY RECAP ****************************************************************
   adm01   : ok=14  changed=0  …
   dns01   : ok=14  changed=0  …
   …
   ```
6. Requêtes :
   ```
   {job="journald", host="git01"}
   sum by (host) (count_over_time({job="journald", host=~".+"} | niveau=~"error|crit|alert|emerg" [1h]))
   ```
   ```
   admin@dns01:~$ logger -p user.err "M22-E05 essai"
   admin@adm01:~$ logcli --org-id=plateforme query --since=5m '{job="journald", host="dns01"} |= "M22-E05"'
   2026-10-22T14:02:11Z {host="dns01", job="journald", role="dns", site="par1"} M22-E05 essai
   ```
7. Agent arrêté cinq minutes : à la reprise, Alloy relit le journal depuis la position enregistrée (le *curseur* journald, dans `/var/lib/alloy`) ; la ligne arrive avec **son** horodatage (celui du journal), pas celui de l'envoi. C'est l'intérêt de lire journald plutôt qu'un flux en direct.

**Explications**

Le journal systemd est la source unique d'une VM Debian moderne : services, noyau, `sshd`, `sudo`, `cron`. `loki.source.journal` le lit par la bibliothèque `libsystemd` et mémorise un **curseur** (position dans le journal), plus robuste qu'une position dans un fichier. `max_age` borne ce qu'il relit au **premier** démarrage. Les champs du journal arrivent en étiquettes internes `__journal_<champ>` (le champ `_SYSTEMD_UNIT` devient `__journal__systemd_unit`, avec deux soulignés) ; le niveau a une forme numérique et une forme en mot-clé (`error`, `warning`…).

**Alternatives**

- Paquet `.deb` d'`apt.grafana.com` (voir étape 1).
- `systemd-journal-upload` vers un `systemd-journal-remote` central, puis lecture par Alloy : natif, mais un serveur de plus et aucun traitement au départ.
- rsyslog qui transmet en syslog vers un `loki.source.syslog` d'Alloy dans le cluster : classique pour les équipements réseau (pas d'agent possible), moins riche (pas de champs du journal).

**Pièges classiques**

- Oublier les groupes : l'agent démarre, est « sain », et n'envoie rien.
- `max_age` par défaut (7 h) ou trop grand : un premier démarrage qui renvoie des jours de journal, refusés au-delà de 7 jours par Loki.
- Écouter l'interface d'Alloy sur `0.0.0.0` : elle expose la configuration et le graphe.
- Ouvrir la bordure sans mettre à jour la CNP (ou l'inverse) : le flux est coupé à l'autre bout, avec une erreur différente (délai dépassé à la bordure, 403 d'Envoy dans le cluster).
- `role` vide : un hôte sans groupe `role_*` dans NetBox — le gabarit écrit `inconnu`, que le check refuse.

**En production chez MédiSphère**

Agent déployé par la même pipeline que les autres rôles, version suivie par Renovate ; mêmes règles de masquage que dans le cluster (E09) ; un tableau de bord « dernière ligne reçue par VM » et une alerte quand une VM se tait ; à terme, TLS vers un point d'entrée authentifié.
