# Module 22 — Palier 3 : Production

Les paliers 1 et 2 ont centralisé les journaux de tout le lab : Loki multi-locataire sur le RGW, Alloy sur chaque nœud et sur chaque VM, des journaux applicatifs structurés, le journal d'audit de l'API, des alertes tirées des journaux, le masquage des données de santé. Il reste ce qui fait d'un Loki « qui marche » un service qu'on peut présenter à un auditeur HDS et confier à l'astreinte : **combien de temps** on garde quoi et comment on efface sur demande, ce qui se passe quand un locataire envoie dix fois trop, pourquoi une requête sur sept jours met trente secondes, ce que vaut la solution concurrente que l'ancien infogérant recommandait, **qui** peut lire le journal d'audit, et ce qu'on perd si le compartiment disparaît. Sophie Laurent veut des règles écrites et appliquées ; Karim Benali veut des mesures avant les réglages ; Claire Morel veut une décision d'architecture qu'elle peut défendre.

Prérequis : paliers 1 et 2 terminés (`lab/bin/check 22 02` à `22 11` verts, essai Fluent Bit de E10 retiré). Lis la règle 3 de l'[introduction](00-introduction.md) : on ne supprime pas de données pour réparer.

> ⚠️ **Rappel** : Loki porte maintenant la seule copie des journaux du lab ; plusieurs réglages de ce palier sont **destructeurs par nature** (rétention, effacement). Avant chaque changement de la configuration de Loki : (1) relis le diff que montrera Argo CD (`argocd app diff loki`) ; (2) vérifie que le versionnage du compartiment n'est pas ta seule protection — il n'existe pas encore avant M22-E16 ; (3) un seul changement à la fois, observé (`/config`, `/config/tenant/v1/limits`, métriques) avant le suivant. Une rétention trop courte appliquée par le compactor **ne se rattrape pas**.

**Chemin imposé** : la configuration de Loki vit dans `plateforme/observabilite` (`loki/values.yaml`, `loki/regles/`), celle d'Alloy dans `alloy/` ; tout passe par une MR relue, appliquée par Argo CD (Applications `loki` et `alloy`, projet `plateforme`). Les charts tiers passent par `plateforme/charts-miroir`. Aucun secret dans Git : les identifiants vont dans Ansible Vault `critique` (`secrets/<composant>.yml`) et dans le cluster par `plateforme/k8s/outils/secrets-k8s.sh`. La documentation va dans `docs/observabilite/journaux/` de `plateforme/medisphere` (`adr/`, `runbooks/`).

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| Loki | Application Argo CD `loki` (chart + values + dossier `loki/` en kustomize), espace `journaux`, StatefulSet `loki` (un pod `loki-0`, conteneur `loki`), ConfigMaps `loki` (configuration) et `loki-runtime` (surcharges par locataire), Services `loki` et `loki-externe` (10.10.41.62), PVC `ceph-rbd` 20 Gio, politique réseau `loki-entree` (`loki/manifestes/politique-reseau.yaml`) |
| Accès depuis `adm01` | `http://loki.apps.par1.medisphere.internal:3100` (Service `LoadBalancer` 10.10.41.62) ; en-tête `X-Scope-OrgID` obligatoire ; `logcli` (M22-E04) avec `LOKI_ADDR` et `--org-id` |
| Locataires | `plateforme`, `mediagenda`, `medidoc`, `audit`, `essai` |
| Compartiment | `loki-k8s-par1` sur le RGW de `ceph-par1` (`https://rgw.par1.medisphere.internal`), utilisateur RGW `loki`, identifiants sur `adm01` dans `~/.config/workbook/s3-loki.env` |
| Points de lecture utiles | `/config` (configuration en vigueur), `/config/tenant/v1/limits` (limites effectives d'un locataire, avec son en-tête), `/services`, `/metrics`, `/ready` |
| Documentation | `docs/observabilite/journaux/` : `politique-journaux.md` (section 1 en E09, section 2 en E13, sections 3 et 4 en E16), `performance.md` (E14), `comparatif-opensearch.md` (E15), `adr/ADR-0220-*.md` (E17), `runbooks/RB-221-*.md` (E13) |
| Variables de `lab/lab.env` | `WB_LOKI_URL` (défaut ci-dessus) ; `WB_M22_S3_LOKI_ENV` (défaut `~/.config/workbook/s3-loki.env`) ; `WB_M22_RGW_URL` (défaut `https://rgw.par1.medisphere.internal`) |

---

### M22-E13 — Rétention, locataires et limites  `LAB` `★★★`

> **Ticket SEC-2313** — *De : Sophie Laurent* — *Copie : Claire Morel, Julien Petit*
> L'auditeur HDS passe en janvier. Aujourd'hui, Loki garde **tout, pour toujours**, au même endroit, et n'importe quel locataire peut remplir le stockage. Je veux des durées de conservation écrites et appliquées : **un an** pour le journal d'audit de l'API (preuve), **30 jours** pour les journaux applicatifs de MédiAgenda et MédiDoc, **14 jours** pour la plateforme. Je veux aussi savoir répondre à une demande d'effacement (article 17 du RGPD) si une donnée personnelle a fui dans un journal malgré le masquage : qui la traite, comment, en combien de temps, avec quelle preuve. Et je ne veux pas qu'un essai de Lucas puisse saturer Loki pour tout le monde.

**Objectifs pédagogiques**
- Comprendre qui applique la rétention dans Loki (le **compactor**, sur l'index), ce qui est supprimé, quand, et pourquoi la suppression est différée.
- Fixer une rétention globale, des surcharges **par locataire** et par flux (`retention_stream`), dans le fichier de configuration d'exécution (*runtime config*) rechargé à chaud.
- Poser des limites d'ingestion par locataire (débit, rafale, nombre de flux actifs) et savoir les lire.
- Ouvrir l'API d'effacement aux seuls locataires qui en ont besoin, l'éprouver sur des données d'essai et écrire la procédure.

**Prérequis** : M22-E02, M22-E03, M22-E09 (masquage) ; `lab/bin/check 22 02` et `lab/bin/check 22 03` verts.
**Durée indicative** : 2 h 30.

**Contexte technique**
- Loki 3.7 en mode `Monolithic` : le compactor tourne **dans** le pod `loki-0` (cible `all`). Sa rétention ne fonctionne qu'avec une période d'index de **24 h** (c'est le cas du schéma TSDB v13 posé en E02) et ne s'applique pas rétroactivement à ce qui a déjà été supprimé… mais elle s'applique bien aux données déjà présentes : une rétention de 14 jours supprime dès son premier passage tout ce qui a plus de 14 jours.
- Le chart 19 écrit le contenu de la valeur `loki.runtimeConfig` dans le ConfigMap `loki-runtime`, monté dans le pod ; Loki relit ce fichier toutes les 10 s. Le fichier de configuration principal (ConfigMap `loki`) ne se relit pas : le chart pose une annotation d'empreinte qui fait redémarrer le pod quand il change.
- Les limites effectives d'un locataire se lisent sans rien deviner :
  ```
  admin@adm01:~$ curl -s -H 'X-Scope-OrgID: audit' http://loki.apps.par1.medisphere.internal:3100/config/tenant/v1/limits
  ```
  (seule une partie des limites y est publiée ; les autres se lisent dans `/config` et dans le ConfigMap `loki-runtime`).
- `logcli` 3.7 sait créer, lister et annuler des demandes d'effacement (`logcli delete --help`).
- `ressources/E13-effacement/pousser-essai.sh` pousse dans le locataire `essai` cinq lignes **factices**, dont deux contiennent l'identifiant de patient inventé `PAT-E13-0042`.

**Travail demandé**
1. **État des lieux.** Relève dans `/config` (sections `compactor` et `limits_config`) et dans `/config/tenant/v1/limits` de chaque locataire ce qui est configuré aujourd'hui : rétention, effacement, limites d'ingestion. Compte ce qu'occupe le compartiment (`aws s3 ls --summarize --recursive` avec `s3-loki.env`, ou `radosgw-admin bucket stats` sur `ceph-par1`). Note ces valeurs : elles serviront de point de comparaison.
2. **Compactor.** Active la rétention du compactor dans `loki/values.yaml` : répertoire de travail **persistant**, intervalle, délai avant suppression des chunks marqués, magasin des demandes d'effacement, délai d'annulation. Justifie chaque valeur en commentaire.
3. **Rétentions.** Fixe une rétention globale égale à celle de la plateforme, puis des surcharges par locataire conformes au ticket ; ajoute une règle par flux qui ne garde les journaux de l'espace `wb-essais` que 24 h dans le locataire `plateforme`. Aligne la profondeur de requête autorisée (`max_query_lookback`) sur chaque rétention et explique pourquoi dans la MR.
4. **Limites d'ingestion.** Fixe pour chaque locataire un débit, une rafale et un nombre maximal de flux actifs adaptés à son volume réel (mesure-le d'abord : métriques `loki_distributor_bytes_received_total` et `loki_ingester_memory_streams` par locataire, ou requêtes `bytes_rate` / `count` en LogQL) ; `essai` doit être nettement plus contraint que les autres.
5. **Effacement.** Ferme l'API d'effacement par défaut et ouvre-la (mode qui filtre **et** supprime) aux seuls locataires `mediagenda`, `medidoc` et `essai`. Puis, sur `essai` : pousse les lignes d'essai, crée une demande d'effacement ciblée (sélecteur **et** filtre de ligne sur `PAT-E13-0042`, fenêtre de temps minimale), liste-la, vérifie ce qu'une requête renvoie avant et après, et vérifie qu'une demande identique sur `audit` est **refusée**.
6. **Fusionne, observe.** Après la synchronisation d'Argo CD : le pod a-t-il redémarré ? Quand les surcharges ont-elles été prises en compte (métriques `loki_runtime_config_*`) ? Le compactor tourne-t-il (`/services`, métriques `loki_boltdb_shipper_compactor_running`, `loki_compactor_apply_retention_last_successful_run_timestamp_seconds`) ?
7. **Politique.** Complète la section 2 « Rétentions et effacement » de `docs/observabilite/journaux/politique-journaux.md` (créée en E09) : tableau des locataires (contenu, rétention, effacement possible ou non, limites), justification de chaque durée (HDS, RGPD, besoin d'exploitation), ce qui n'est **jamais** dans Loki (renvoi à la section 1), et la procédure d'effacement résumée. Écris le runbook **RB-221** « Traiter une demande d'effacement dans les journaux » (`docs/observabilite/journaux/runbooks/RB-221-*.md`) : qui peut demander, qui exécute, commandes, délai d'annulation, vérification, trace conservée.

**Critères de réussite**
- [ ] `/config` montre le compactor avec la rétention activée et un magasin des demandes d'effacement ; le service `compactor` est `Running` et un passage de rétention a réussi.
- [ ] `/config/tenant/v1/limits` renvoie une rétention de 1 an pour `audit`, 30 jours pour `mediagenda` et `medidoc`, 14 jours pour `plateforme`, avec une profondeur de requête cohérente.
- [ ] Les surcharges de `loki-runtime` sont rechargées avec succès ; `essai` a un débit d'ingestion et un nombre de flux inférieurs à ceux de `plateforme` ; l'effacement est fermé pour `audit` et `plateforme`.
- [ ] Une demande d'effacement existe dans le locataire `essai` ; la même demande sur `audit` est refusée.
- [ ] `politique-journaux.md` et RB-221 sont sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 22 13`

<details><summary>Indice 1</summary>

La page « Log retention » de la documentation de Loki (*Operations → Storage → Retention*) donne la liste des réglages du compactor et l'ordre de priorité entre `retention_stream` et `retention_period`, globaux et par locataire. La page « Log entry deletion » dit où se règle le mode d'effacement : ce n'est pas dans la section `compactor`.
</details>

<details><summary>Indice 2</summary>

Une rétention se compte en heures dans la configuration ; `/config/tenant/v1/limits` l'affiche dans l'unité la plus grande qui tombe juste (`1y`, `30d`, `2w`). Pour l'effacement, l'API refuse une fenêtre qui se termine dans le futur : donne une fin égale à maintenant (`date -u +%Y-%m-%dT%H:%M:%SZ`). La sortie par défaut de `logcli delete list` ne montre pas l'identifiant d'une demande : l'API, elle, le renvoie en JSON.
</details>

<details><summary>Indice 3</summary>

Le statut d'une demande reste `received` tant que le délai d'annulation n'est pas écoulé ; la suppression réelle des chunks a lieu ensuite, au passage suivant du compactor. Ce qui change tout de suite, c'est ce que **renvoient les requêtes** : compare la même requête avant et après la création de la demande.
</details>

**Pour aller plus loin** (facultatif) : lis le compteur `loki_discarded_samples_total` et l'étiquette `retention_hours` de `loki_distributor_bytes_received_total` : Loki sait, dès l'ingestion, quelle rétention s'appliquera à chaque flux. Construis le tableau « volume reçu par rétention » de chaque locataire et déduis-en la taille du compartiment à l'équilibre.

---

### M22-E14 — Performance de Loki et cardinalité des étiquettes  `LAB` `★★★`

> **Ticket PLAT-2314** — *De : Karim Benali*
> Nadia dit que « Loki rame » : son tableau « Erreurs par espace sur 7 jours » met plus de 20 secondes, parfois il expire. Avant de toucher à quoi que ce soit, je veux des **mesures** : combien de flux par locataire, quelles étiquettes, quelle taille de chunks, combien de données lit une requête, où passe le temps. Ensuite des réglages justifiés par ces mesures, et un seuil écrit au-delà duquel on alerte. Et personne ne remet `pod` en étiquette.

**Objectifs pédagogiques**
- Mesurer la cardinalité d'un locataire (flux actifs, étiquettes, valeurs) avec `logcli series --analyze-labels`, l'API `index/volume` et les métriques de l'ingester.
- Lire les statistiques d'une requête (octets traités, chunks, temps par étage) et relier ce qu'on voit aux mécanismes : sélecteur, index TSDB, découpage par intervalle, filtres de ligne, analyseurs.
- Comprendre la vie d'un chunk (taille cible, âge maximal, inactivité, compression) et ce qu'une mauvaise étiquette lui fait.
- Régler le découpage des requêtes, le parallélisme et un cache des résultats adapté au lab ; fixer des seuils.

**Prérequis** : M22-E04 (`logcli`), M22-E06, M22-E13.
**Durée indicative** : 2 h.

**Contexte technique**
- Liste fermée des étiquettes (M22-E03) : `cluster`, `namespace`, `app`, `container`, `node`, `job`, et pour les VMs `host`, `role`, `site`. Tout le reste est en **métadonnées structurées** ou dans la ligne.
- Loki 3.7 sait **ajouter** des étiquettes tout seul : `service_name`, déduite d'une liste d'étiquettes connues (`discover_service_name`), et `__stream_shard__` quand un flux dépasse le débit souhaité et que le découpage automatique (`shard_streams`) est actif. Le niveau détecté (`detected_level`) est, lui, une métadonnée structurée.
- `logcli query --stats` affiche les statistiques d'une requête ; Grafana les montre dans l'inspecteur de requête (*Query inspector → Stats*).
- Pas de memcached dans le lab : le chart permet un cache des résultats **intégré** au processus.
- Le profil mémoire du lab est serré : tout réglage qui augmente la mémoire de `loki-0` doit tenir dans sa limite (relis-la dans les values).

**Travail demandé**
1. **Cardinalité.** Pour chaque locataire, sur la dernière heure puis sur 24 h : nombre de flux, étiquettes et nombre de valeurs (`logcli series '{namespace=~".+"}' --analyze-labels`, adapte le sélecteur aux VMs et à l'audit), flux actifs en mémoire (`loki_ingester_memory_streams`). Repère l'étiquette qui a le plus de valeurs et explique d'où elle vient.
2. **Étiquettes ajoutées par Loki.** `discover_service_name: []` est posé depuis E02 : vérifie qu'aucun locataire ne montre plus `service_name` ni aucune autre étiquette hors liste (sur 1 h, puis sur 7 jours : que reste-t-il des flux créés avant E02, et quand disparaîtront-ils ?). Écris ce que la décision coûte à *Logs Drilldown* de Grafana et dans quel cas tu la reverrais.
3. **Chunks.** Relève la distribution des tailles de chunks et des raisons de vidage (`loki_ingester_chunk_size_bytes`, `loki_ingester_chunks_flushed_total` par `reason`), le taux de compression, l'âge des chunks au vidage. Explique ce que donnerait une étiquette `pod` ajoutée sur ces trois mesures.
4. **Requêtes.** Mesure avec `--stats` trois requêtes types sur 24 h et sur 7 jours (sélecteur seul ; sélecteur + filtre `|= "error"` ; métrique `sum by (namespace) (count_over_time(... |= "error" [5m]))`) : octets traités, nombre de chunks, temps total. Reformule celle de Nadia pour qu'elle lise moins de données, sans changer son résultat.
5. **Réglages.** Ajuste dans `loki/values.yaml` le découpage des requêtes (`split_queries_by_interval`), le parallélisme du requêteur, le délai maximal des requêtes et un cache des résultats intégré ; mesure de nouveau les mêmes requêtes (une première fois, puis une deuxième pour voir le cache). Garde ce qui améliore, retire le reste.
6. **Seuils.** Rédige `docs/observabilite/journaux/performance.md` : tableau par locataire (flux actifs mesurés, limite posée en E13, **seuil d'alerte** à 50 % de la limite), mesures avant/après, réglages retenus et rejetés, règles d'or pour les équipes (étiquettes, sélecteurs, filtres). Ajoute une règle d'alerte sur le nombre de flux actifs par locataire (PrometheusRule dans `plateforme/observabilite/regles/`, sélection par l'étiquette de M21) et sur les échantillons rejetés.

**Critères de réussite**
- [ ] Pour chaque locataire, aucune étiquette hors de la liste fermée (exceptions décidées et écrites : `service_name`, `__stream_shard__`).
- [ ] Chaque locataire a moins de flux actifs que la moitié de sa limite `max_global_streams_per_user`.
- [ ] Le découpage des requêtes est actif et un cache des résultats est configuré ; la requête de Nadia sur 7 jours répond.
- [ ] `performance.md` est publié avec les mesures et les seuils ; une alerte de cardinalité est chargée dans Prometheus.

**Vérification** : `lab/bin/check 22 14`

<details><summary>Indice 1</summary>

Le temps d'une requête Loki se décompose en temps passé à **trouver** les chunks (index : quel sélecteur, combien de flux) et temps passé à les **lire** (octets décompressés, filtres, analyseurs). Les statistiques de `--stats` séparent les deux (`Summary`, `Querier`, `Ingester`, `Index`). Un sélecteur plus étroit réduit la première partie, un filtre de ligne placé **avant** l'analyseur réduit la seconde.
</details>

<details><summary>Indice 2</summary>

`split_queries_by_interval` découpe une requête en sous-requêtes exécutées en parallèle par les requêteurs ; avec un seul pod et quelques travailleurs, trop de petites sous-requêtes coûtent plus qu'elles ne rapportent. Le cache des résultats est indexé par ces intervalles : une deuxième exécution ne recalcule que l'intervalle courant (et ce qui est plus récent que `max_cache_freshness_per_query`).
</details>

<details><summary>Indice 3</summary>

La règle d'alerte se fait sur les métriques que Prometheus collecte déjà sur Loki (`loki_ingester_memory_streams{tenant=…}`, `loki_discarded_samples_total{reason=…}`). Le seuil ne peut pas lire la limite dans Loki : écris-le en dur dans la règle, avec un commentaire qui renvoie à `performance.md`.
</details>

**Pour aller plus loin** (facultatif) : compare le volume d'index et de chunks d'une journée dans le compartiment (`aws s3 ls --summarize --recursive s3://loki-k8s-par1/index/loki_index_<N>/`) avec le volume brut reçu ce jour-là (métriques du distributeur) : quel est le taux de compression réel de tes journaux ?

---

### M22-E15 — OpenSearch : la recherche plein texte en comparaison  `LAB` `★★★`

> **Ticket PLAT-2315** — *De : Claire Morel* — *Copie : Karim Benali*
> InfoGér nous a envoyé une proposition « journaux » à base d'OpenSearch : « recherche plein texte instantanée, tableaux de bord, alertes, tout inclus ». La direction me demande pourquoi nous ne la prenons pas. Je veux une réponse argumentée par **nos** mesures : monte un OpenSearch d'essai (un seul nœud, sécurisé — pas la configuration de démonstration), alimente-le avec **Fluent Bit** sur les mêmes journaux que Loki pendant une heure ou deux, compare la recherche, les ressources et l'exploitation, puis retire tout. Attention à la mémoire du lab.

**Objectifs pédagogiques**
- Déployer OpenSearch 3.9 en un nœud avec le plugin de sécurité activé et des certificats émis par cert-manager, sans la configuration de démonstration.
- Alimenter OpenSearch avec Fluent Bit 5.1 (entrée `tail` des journaux des pods, filtre `kubernetes`, sortie `opensearch` en TLS avec un compte à droits limités).
- Comparer **sur les mêmes données** : modèle d'indexation (index inversé de tout le texte contre index des seules étiquettes), recherche plein texte, recherche par champ, agrégations, place sur disque, mémoire, CPU, opérations quotidiennes.
- Retirer proprement un composant temporaire géré par Argo CD, y compris ses volumes.

**Prérequis** : M22-E10 (Fluent Bit), M22-E14 (mesures de Loki) ; `vm.max_map_count` posé sur les travailleurs (M19-E02) ; cert-manager (M15).
**Durée indicative** : 3 h.

**Contexte technique**
- Charts : `opensearch/opensearch` **3.9.0** (OpenSearch 3.9.0) et `fluent/fluent-bit` **0.58.x** (Fluent Bit 5.1), à recopier par `plateforme/charts-miroir` ; images par le cache Harbor `dockerhub` (`opensearchproject/opensearch`, `fluent/fluent-bit`).
- Espace **`opensearch-essai`** pour les deux (créé pour l'essai, supprimé à la fin) ; Fluent Bit lit des répertoires de l'hôte : le niveau de Pod Security de l'espace doit le permettre, et ce choix doit être écrit et temporaire.
- Le plugin de sécurité d'OpenSearch lit des certificats PEM ; il **refuse** les clés privées au format PKCS#1. Les comptes internes (`internal_users.yml`) portent des empreintes bcrypt.
- Mémoire : compte ≈ 3 Go pour l'essai (tas Java de 1 Go, cache du système de fichiers). Composant temporaire : **jamais** en même temps que Jaeger (M23) ni qu'un autre essai lourd.
- Le chart OpenSearch Dashboards existe (3.9.0) ; il n'est pas demandé (mémoire), les requêtes se font par l'API REST.

> ⚠️ **Attention** : OpenSearch réserve son tas Java au démarrage. Avant l'installation, vérifie la mémoire disponible sur les travailleurs (`kubectl top nodes`, `kubectl describe node` → *Allocated resources*) ; si un travailleur est au-delà de 85 % de mémoire demandée, ne lance pas l'essai. Retour arrière : supprimer l'Application `opensearch-essai` (avec son finaliseur) puis l'espace.

**Travail demandé**
1. **Préparer.** Ajoute les deux charts à `plateforme/charts-miroir` (versions exactes, empreintes) et vérifie leur présence signée dans Harbor `charts/`. Crée l'espace `opensearch-essai` (étiquettes MédiSphère, niveau de Pod Security justifié) et une autorité de certification **propre à l'essai** dans cert-manager (émetteur de l'espace), puis deux certificats : celui du nœud (noms DNS du Service et du pod) et un certificat d'administration du plugin de sécurité.
2. **OpenSearch.** Écris les values : un nœud (`singleNode`), tas de 1 Go, persistance de 10 Gi sur `ceph-rbd`, configuration de démonstration désactivée, TLS transport et HTTP avec les certificats montés, `admin_dn` et `nodes_dn`, configuration de sécurité (`config.yml`, `internal_users.yml`, `roles.yml`, `roles_mapping.yml`) avec un compte `admin` et un compte `fluentbit` qui ne peut qu'écrire dans les index `journaux-*`. Aucun mot de passe en clair dans Git : les empreintes seulement, les mots de passe dans Ansible Vault `critique`. Déploie par une Application Argo CD `opensearch-essai` (projet `plateforme`).
3. **Fluent Bit.** Déploie Fluent Bit dans le même espace (Application `fluent-bit-opensearch`) : entrée `tail` sur les journaux des pods des espaces `mediagenda-*`, filtre `kubernetes`, sortie `opensearch` en TLS vérifié, compte `fluentbit`, index quotidiens `journaux-AAAA.MM.JJ`, compatibilité OpenSearch 2+ (types de mapping). Vérifie que les documents arrivent (`_cat/indices`).
4. **Comparer.** Pendant au moins une heure de collecte, sur les **mêmes** journaux de MédiAgenda dans Loki et dans OpenSearch, exécute et chronomètre les recherches de `ressources/E15-comparaison/requetes.md` (mot rare, mot fréquent, champ JSON, agrégation par code HTTP sur 1 h, expression régulière). Relève : volume sur disque des deux côtés pour la même heure (`_cat/indices?v&bytes=b` contre les objets de la journée dans `loki-k8s-par1`), mémoire et CPU des pods (`kubectl top`), nombre de réglages qu'il a fallu toucher.
5. **Rédiger.** `docs/observabilite/journaux/comparatif-opensearch.md` : tableau des mesures, ce qu'OpenSearch fait mieux (et pour qui), ce que Loki fait mieux, coût d'exploitation (montées de version, mapping, rotation des index — ISM —, sécurité), recommandation. Ce document nourrit l'ADR de M22-E17.
6. **Retirer.** Supprime les Applications par Git (avec suppression en cascade des ressources), puis les volumes et l'espace `opensearch-essai` ; retire l'émetteur et les certificats ; retire les deux charts du miroir (même règle qu'en M22-E10 : un chart qu'aucune Application n'utilise n'a rien à faire dans `charts-miroir`). Vérifie qu'il ne reste **rien** (PVC, PV, volumes RBD orphelins).

**Critères de réussite**
- [ ] Pendant l'essai : OpenSearch répond en HTTPS avec un certificat de l'autorité de l'essai, refuse une requête anonyme, et l'index `journaux-*` reçoit des documents du compte `fluentbit`.
- [ ] `comparatif-opensearch.md` est publié avec des mesures chiffrées des deux côtés (temps, disque, mémoire) et une recommandation.
- [ ] À la fin : l'espace `opensearch-essai` n'existe plus, aucune Application `opensearch-essai` ni `fluent-bit-opensearch`, aucun PV orphelin de l'essai, aucun DaemonSet Fluent Bit dans le cluster, plus de chart `opensearch` ni `fluent-bit` dans `charts-miroir`.

**Vérification** : `lab/bin/check 22 15` (en fin d'exercice, après le retrait)

<details><summary>Indice 1</summary>

Le chart OpenSearch monte des Secrets là où tu veux (`secretMounts`) et accepte des fichiers de configuration (`config.opensearch.yml`) ; la variable d'environnement `DISABLE_INSTALL_DEMO_CONFIG` empêche l'installation des certificats de démonstration. Avec `plugins.security.allow_default_init_securityindex: true`, le plugin initialise son index de sécurité à partir des fichiers de `opensearch-security/` au premier démarrage.
</details>

<details><summary>Indice 2</summary>

Une `Certificate` de cert-manager choisit le format de la clé privée (`spec.privateKey.encoding`). Pour l'empreinte bcrypt d'un compte interne, l'outil `plugins/opensearch-security/tools/hash.sh` est dans l'image ; tu peux aussi produire une empreinte bcrypt sur `adm01`. Dans Fluent Bit, la sortie `opensearch` a besoin de `Suppress_Type_Name On` pour OpenSearch 2 et plus, et de `tls On` avec `tls.ca_file`.
</details>

<details><summary>Indice 3</summary>

Pour comparer le disque : `GET _cat/indices/journaux-*?v&bytes=b` donne la taille de l'index (avec ses réplicas, qu'un nœud unique n'a pas — vérifie `number_of_replicas`), et la même heure dans Loki se lit dans les métriques de l'ingester (octets de chunks stockés) ou dans le compartiment. Pour le retrait, un PVC de StatefulSet survit à la suppression de l'Application : c'est voulu.
</details>

**Pour aller plus loin** (facultatif) : active une politique ISM (*Index State Management*) qui supprime les index de plus de 30 jours, et compare l'effort avec la rétention par locataire de Loki (E13). Essaie la même agrégation en PPL (*Piped Processing Language*) et en LogQL.

---

### M22-E16 — Accès, sécurité et sauvegarde des journaux  `LAB` `★★★`

> **Ticket SEC-2316** — *De : Sophie Laurent* — *Copie : Claire Morel, Nadia Roussel*
> Trois constats de la revue de sécurité. Un : tout ce qui a le droit de parler à Loki peut lire le journal d'audit en écrivant `X-Scope-OrgID: audit` — Alloy, qui n'a pourtant qu'à écrire, Grafana, et toute machine de MGMT ; et dans Grafana, tous les comptes voient la source « Loki — audit ». Deux : Loki peut sortir vers n'importe quoi. Trois : si le compartiment `loki-k8s-par1` est vidé par erreur — un mauvais réglage de rétention suffit, la documentation de Loki le dit elle-même —, on perd tout, y compris un an de preuves. Je veux d'ici la fin du mois : l'accès réseau à Loki réduit au strict nécessaire dans les deux sens, le journal d'audit visible des seules personnes habilitées, une décision sur le chiffrement du Service 10.10.41.62, et une décision écrite sur ce qu'on sauvegarde et comment.

**Objectifs pédagogiques**
- Comprendre pourquoi l'en-tête `X-Scope-OrgID` n'est **pas** un mécanisme d'authentification et ce qu'on peut faire sans passerelle authentifiante (en attendant l'identité du M24).
- Écrire les CiliumNetworkPolicy de l'espace `journaux` : qui écrit, qui lit, depuis où, avec une règle de niveau 7 (méthode et chemin HTTP) pour les écritures venues des VMs.
- Cloisonner l'accès au locataire `audit` dans Grafana OSS, qui n'a pas de permissions par source de données.
- Décider de la sauvegarde des journaux (ce qui se reconstruit, ce qui se protège, ce qui se copie) et protéger le compartiment contre l'effacement accidentel.

**Prérequis** : M22-E02 (Service 10.10.41.62 et sa politique réseau), M22-E05 (VMs), M22-E13 ; M15 (CiliumNetworkPolicy, Hubble) ; M21 (Grafana, état OpenTofu `observabilite-grafana`).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Qui parle à Loki aujourd'hui (politique `loki-entree` d'E02) : Alloy (DaemonSet de `journaux`) et Grafana (`supervision`) sur tout le port 3100, Prometheus sur `/metrics`, les VMs du socle en `POST /loki/api/v1/push` seulement (règle HTTP posée dès E02), MGMT sans restriction. Aucune politique ne couvre la **sortie** de Loki. Le *ruler* de Loki tourne **dans** `loki-0` et parle à Alertmanager ; le conteneur `sidecar` du pod lit les ConfigMaps de règles par l'API Kubernetes.
- Le Service `LoadBalancer` a `externalTrafficPolicy: Local` : l'adresse source des VMs est conservée jusqu'au pod, ce qui permet de filtrer par CIDR.
- Cilium sait appliquer des règles HTTP (méthode, chemin) en faisant passer le trafic concerné par son proxy Envoy ; mesure ce que cela coûte et ce que cela casse (connexions longues, `tail`).
- Grafana OSS 13 : les permissions par source de données sont une fonction d'**Enterprise** ; les **organisations**, elles, sont dans l'édition libre, chacune avec ses sources de données et ses utilisateurs. Le fournisseur OpenTofu `grafana/grafana` (contrainte `~> 4.50` posée au M21-E17, 4.51.x de référence) gère organisations et sources de données (état `observabilite-grafana`). Les comptes locaux des personnages viennent du M21 ; si celui de Sophie Laurent n'existe pas encore, crée-le comme au M21 avant d'en faire une membre de l'organisation.
- Le compte des checks `wb-checks` de Grafana est *Viewer* dans l'organisation principale.

> ⚠️ **Attention** : une politique réseau Cilium qui sélectionne `loki-0` passe ce pod en **refus par défaut** dans le sens qu'elle couvre. Une règle oubliée coupe la collecte de tout le lab, ou les sondes du kubelet (pod redémarré en boucle). Avant d'appliquer : garde un terminal sur `hubble observe -n journaux --verdict DROPPED -f` ; applique d'abord l'entrée, observe 10 minutes, puis la sortie. Retour arrière : `git revert` du commit dans `plateforme/observabilite` (Argo CD supprime la politique) — prépare la commande avant de fusionner.

**Travail demandé**
1. **Constater.** Depuis `adm01`, lis une ligne du locataire `audit` avec `curl` et l'en-tête qui va bien ; depuis un pod jetable de `wb-essais`, essaie la même chose vers le Service interne de Loki ; avec Hubble, observe ce que `loki-0` émet vers l'extérieur pendant 10 minutes (`hubble observe --from-pod journaux/loki-0`). Note ce qui passe aujourd'hui, et ce qu'un compte d'équipe voit dans Grafana.
2. **Matrice des flux.** Écris la matrice des flux de l'espace `journaux` (source, destination, port, méthode/chemin, sens) dans `docs/kubernetes/reseau/matrice-flux-cluster.md`, y compris les sorties de Loki (RGW par la carte `eth1`, DNS, Alertmanager, API Kubernetes si le *sidecar* de règles est actif).
3. **Politiques réseau.** Fais évoluer `loki/manifestes/politique-reseau.yaml` (E02) : écritures d'Alloy limitées à `POST /loki/api/v1/push`, comme celles des VMs ; lectures de Grafana limitées aux chemins de l'API de requête et des règles ; Prometheus limité à `/metrics` ; MGMT (`adm01`) en accès complet (administration, checks) ; sondes du kubelet écrites explicitement ; et une **nouvelle** politique de sortie (DNS, RGW, Alertmanager, API Kubernetes, Loki lui-même). Aucune règle ouverte à `world` ni à `0.0.0.0/0`. Applique, observe, refais l'essai 1.
4. **Grafana.** Retire la source « Loki — audit » de l'organisation principale et recrée-la par OpenTofu dans une organisation **Sécurité** dont seuls Sophie Laurent, Nadia Roussel et les administrateurs de la plateforme sont membres ; les sources des autres locataires restent dans l'organisation principale. Vérifie avec un compte d'équipe que la source n'est plus visible.
5. **Sauvegarde.** Décide et écris ce qui est sauvegardé : configuration et règles (Git), secrets (Vault), données (compartiment), WAL (PVC). Protège le compartiment : **versionnage** activé et règle de cycle de vie qui expire les versions non courantes au bout de 7 jours (avec les identifiants de `s3-loki.env`) ; explique ce que cela protège (suppression par une rétention mal réglée, erreur humaine) et ce que cela ne protège pas (perte de `ceph-par1`, compromission du compte `loki`).
6. **Écrire.** Complète `politique-journaux.md` : section 3 « Accès aux journaux » (qui lit quoi, par quel chemin, ce qui reste falsifiable, ta décision sur le chiffrement du Service 10.10.41.62, ce que le M24 apportera) et nouvelle section 4 « Sauvegarde » (décision, RPO/RTO assumés, procédure de restauration d'un objet supprimé).

**Critères de réussite**
- [ ] Les CiliumNetworkPolicy de `journaux` qui sélectionnent Loki : aucune règle d'entrée ouverte à `world`, `all` ou `0.0.0.0/0` ; Alloy et les VMs limités à `POST /loki/api/v1/push` ; entrées depuis le cluster limitées aux espaces `journaux` et `supervision` ; une politique de sortie autorise le RGW (10.10.30.200:443) et rien en grand.
- [ ] Depuis un pod de `wb-essais`, Loki ne répond plus ; depuis `adm01`, les checks fonctionnent ; la collecte de toutes les VMs et de tous les nœuds continue.
- [ ] Le compte *Viewer* de l'organisation principale ne voit plus « Loki — audit ».
- [ ] Le versionnage de `loki-k8s-par1` est activé avec une expiration des versions non courantes ; `politique-journaux.md` contient les sections Accès (avec la décision sur le chiffrement) et Sauvegarde.

**Vérification** : `lab/bin/check 22 16`

<details><summary>Indice 1</summary>

Une règle de niveau 7 se pose dans `toPorts[].rules.http` (liste de `method` et `path`, ce dernier en expression régulière) ; une règle d'entrée par CIDR se pose avec `fromCIDR` ou `fromCIDRSet` (et `except`). Les sondes du kubelet viennent de l'entité `host`. Hubble montre le verdict de chaque flux, y compris les refus de niveau 7 (`--type l7`).
</details>

<details><summary>Indice 2</summary>

Dans le fournisseur OpenTofu de Grafana, une ressource de source de données prend un `org_id`, et un en-tête HTTP se pose par `http_headers` (ou par `json_data_encoded` / `secure_json_data_encoded`). Retirer « Loki — audit » de la ConfigMap `sources-loki` (E02) ne la supprime pas de Grafana : le format de provisionnement des sources a une liste prévue pour cela.
</details>

<details><summary>Indice 3</summary>

Le RGW de Ceph comprend `put-bucket-versioning` et `put-bucket-lifecycle-configuration` de l'API S3 (`aws s3api … --endpoint-url https://rgw.par1.medisphere.internal`). Avec le versionnage, une suppression par le compactor laisse un marqueur de suppression et une version non courante : c'est elle que la règle de cycle de vie expire.
</details>

**Pour aller plus loin** (facultatif) : mesure la latence de poussée d'Alloy (`loki_write_request_duration_seconds`) avant et après la règle de niveau 7 ; lis la page « Authentication » de la documentation de Loki et esquisse la passerelle authentifiante du M24 (qui pose l'en-tête, à partir de quelle identité).

---

### M22-E17 — ADR : l'architecture des journaux  `RED` `★★`

> **Ticket PLAT-2317** — *De : Claire Morel*
> J'ai besoin de l'ADR-0220 avant le comité d'architecture : ce que nous avons choisi pour les journaux, pourquoi, ce que nous avons écarté et ce que nous acceptons comme limites. Une page et demie, des faits, nos mesures.

**Objectifs pédagogiques**
- Formaliser une décision d'architecture à partir des essais du module (Loki, Alloy, OpenSearch, Fluent Bit), avec ses conséquences et ses limites.
- Relier la décision aux exigences : HDS (preuve, rétention), RGPD (minimisation, effacement), souveraineté, mémoire du lab, compétences de l'équipe.

**Prérequis** : M22-E10, M22-E13 à M22-E16.
**Durée indicative** : 1 h.

**Travail demandé**
Rédige `docs/observabilite/journaux/adr/ADR-0220-architecture-journaux.md` au format des ADR de l'équipe (contexte, décision, options étudiées, conséquences, statut) :
1. **Contexte** : volumes mesurés par locataire, exigences de rétention et d'effacement, contraintes du lab.
2. **Décision** : Loki 3.7 en mode `Monolithic`, multi-locataire, stockage RGW, rétention par le compactor ; Alloy comme collecteur unique (pods, nœuds, audit, événements, VMs) ; masquage à la collecte ; alertes par le *ruler*.
3. **Options écartées**, chacune avec la raison chiffrée : OpenSearch (+ Fluent Bit ou Data Prepper), Fluent Bit à la place d'Alloy, **Promtail** (fin de vie le 2 mars 2026), mode `SimpleScalable` (déprécié, supprimé en Loki 4) et mode distribué, service SaaS.
4. **Conséquences** : ce qui devient facile, ce qui reste difficile (recherche plein texte sur de longues périodes, cardinalité), les limites acceptées (un seul pod Loki : pas de haute disponibilité ; en-tête de locataire falsifiable jusqu'au M24 ; pas de copie hors site), et le déclencheur de révision (volume, nombre de locataires, exigence HDS nouvelle).

**Critères de réussite**
- [ ] L'ADR cite au moins trois mesures du module (volume par jour, mémoire, temps de requête ou disque comparé).
- [ ] Chaque option écartée a une raison vérifiable ; Promtail est écarté pour sa fin de vie, pas pour ses fonctions.
- [ ] Les limites acceptées sont explicites, avec le module qui les traitera.

<details><summary>Indice</summary>

Reprends les ADR du M21 (ADR-0210) et du M14 pour la forme. Un bon test : un lecteur qui n'a pas suivi le module doit pouvoir dire, après lecture, ce qui se passe si `loki-0` tombe et combien de temps on garde le journal d'audit.
</details>

---

### M22-E18 — Questions de production : journaux  `Q` `★★★`

> **Ticket PLAT-2318** — *De : Karim Benali*
> Avant de te mettre seul(e) d'astreinte sur les journaux, je te pose les questions que je pose à tout le monde. Réponses argumentées, pas de « ça dépend » sans dire de quoi.

**Objectifs pédagogiques**
- Raisonner sur les conséquences réelles (perte, perte de vue, refus) des réglages de Loki et d'Alloy.
- Relier un symptôme d'exploitation au mécanisme qui le produit, et à ce qui l'aurait évité.

**Prérequis** : M22-E13 à M22-E16.
**Durée indicative** : 45 min (+ 20 min d'auto-correction).

**Questions**
1. La rétention de `mediagenda` passe de 30 à 7 jours par une MR fusionnée lundi à 10 h. Quand les données de plus de 7 jours disparaissent-elles réellement du compartiment ? Peut-on revenir en arrière à 11 h ? À 14 h ? Qu'aurait-il fallu en place pour être tranquille ?
2. Un développeur propose d'ajouter `request_id` en étiquette « pour retrouver une requête plus vite ». Réponds-lui, chiffres à l'appui : ce que cela fait aux flux, aux chunks, à l'index, à la mémoire de l'ingester, et ce qu'il doit faire à la place.
3. Loki renvoie `429` à Alloy pour le locataire `mediagenda`. Que fait Alloy, combien de temps, et quand des lignes sont-elles perdues ? Où le vois-tu des deux côtés ?
4. Pourquoi `loki-0` a-t-il un volume persistant alors que les données sont dans le RGW ? Que perd-on si ce volume est détruit pendant que le pod tourne ? et s'il est détruit pendant un arrêt propre ?
5. Différence entre `retention_period`, `max_query_lookback` et `reject_old_samples_max_age` : donne pour chacune une situation où un mauvais réglage fait « disparaître » des journaux, en précisant si les données sont réellement perdues.
6. Une demande d'effacement (RGPD) est créée sur `mediagenda` à 9 h. À 9 h 05, la ligne apparaît-elle encore dans Grafana ? Et dans le compartiment ? Quand la suppression devient-elle irréversible ? Qu'est-ce qui reste comme trace de la demande ?
7. Pourquoi le compactor doit-il être unique ? Que se passe-t-il si deux pods Loki en mode `Monolithic` partagent le même compartiment sans anneau commun ?
8. Le journal d'audit de l'API représente 70 % du volume ingéré. Propose trois leviers pour le réduire **sans** perdre la valeur de preuve, et dis lequel tu refuses.
9. Un locataire dépasse `max_global_streams_per_user`. Quels flux sont refusés, les anciens ou les nouveaux ? Quel symptôme voient les équipes ? Pourquoi est-ce pire qu'une limite de débit ?
10. Loki ou OpenSearch pour chercher une chaîne rare (un identifiant de transaction) sur 30 jours dans tous les espaces ? Explique le coût de chacune des deux requêtes et propose une organisation des journaux qui rend la recherche Loki raisonnable.
11. Alloy tombe sur un nœud pendant 20 minutes puis redémarre. Les journaux des pods de ce nœud pendant ces 20 minutes sont-ils perdus ? Et ceux de journald ? De quoi cela dépend-il (deux réglages, un fichier) ?
12. Pourquoi la politique réseau de M22-E16 ne suffit-elle pas à protéger le locataire `audit` contre une VM du socle compromise (en écriture comme en lecture) ? Que faudrait-il, et quel module l'apporte ?
13. Le RGW de `ceph-par1` est indisponible 15 minutes. Que deviennent les écritures ? les requêtes sur la dernière heure ? sur hier ? Quelles alertes doivent sonner, et dans quel ordre ?

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 13 questions avant d'ouvrir le corrigé, en distinguant chaque fois perte réelle et perte de vue.
- [ ] Chaque réponse cite le réglage, la métrique ou la commande qui le prouve sur le lab.
