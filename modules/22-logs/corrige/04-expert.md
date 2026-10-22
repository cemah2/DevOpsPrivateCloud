# Module 22 — Palier 4 : Expert — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les corrigés des pannes suivent la trame habituelle : **symptômes → hypothèses → commandes de diagnostic dans l'ordre → cause racine (par variante) → correctif → prévention**. La démarche compte plus que le correctif. Avec une plateforme de journaux, deux réflexes évitent la moitié des fausses pistes : **prouver d'abord si les données existent** (dans Loki, directement, par locataire) avant de croire à une perte, et **regarder les deux côtés** d'un refus (ce qu'Alloy a envoyé et reçu, ce que Loki a compté).

Les scripts d'injection sont dans `corrige/pannes/` : `_m22-commun.sh` contient les fonctions partagées — lecture de Loki (`/config/tenant/v1/limits`, `/metrics`, requêtes), état des Applications Argo CD, exécution sur les nœuds (prélude de `pannes-lib.sh` : `sauver`, `restaurer_fichiers`, `journal`), et surtout les **commits de Lucas** : le fichier est lu sur `main` de `plateforme/observabilite`, transformé (`yq` de mikefarah, `sed`, `awk`), poussé par l'API de GitLab avec l'auteur « Lucas Martin » et le marqueur `M22-EXX` — directement sur `main` si la branche l'accepte, sinon par une MR fusionnée automatiquement après son pipeline —, puis Argo CD est invité à relire Git (annotation `argocd.argoproj.io/refresh`). L'annulation remet le contenu d'origine par un nouveau commit (jamais de réécriture d'historique), **seulement** si le fichier est encore exactement dans l'état injecté (empreinte SHA-256) : ta réparation n'est jamais défaite.

> **Remarque sur les traces** : le commit porte l'auteur « Lucas Martin », mais c'est **ton** jeton d'administration qui l'a poussé (le *committer* et le journal d'audit de GitLab le montrent) ; de même, les gestes sur le cluster sont faits avec ton kubeconfig. En production, ce serait l'identité de Lucas : c'est pour cela que chacun a un compte nominatif et qu'aucun jeton n'est partagé.

Les sorties reproduites sont **représentatives** (Loki 3.7.9, Alloy 1.21.1, Kubernetes 1.36, Debian 13).

**Validé hors du lab** : messages d'erreur de Loki 3.7.9 (limite de débit, limite de flux, entrée trop ancienne, durée de plage, nombre de séries, délai) obtenus sur une instance locale ; format des clés de chunks (`<locataire>/<empreinte>/<début>:<fin>:<somme>`, code de `pkg/storage/config/schema_config.go`), des tables d'index (`index/loki_index_<N>/<locataire>/<ns>-compactor-<début>-<fin>-<somme>.tsdb.gz`) et des demandes d'effacement (`index/delete_requests/delete_requests.gz`) observés sur cette instance ; transformations `yq`/`sed`/`awk` des pannes rejouées sur les fichiers de référence de M22-E07 à E09 ; `shellcheck -x` et `bash -n` sur tous les scripts ; code Python d'E23 compilé ; règle `AlloyAbsentDUnNoeud` par `promtool check rules` et `promtool test rules` (Prometheus 3.15).

**Points non testés en conditions réelles** (signale tes retours) :
- délai entre un commit, la synchronisation d'Argo CD, la mise à jour des ConfigMaps par le kubelet et le rechargement par Loki ou Alloy (les scripts attendent jusqu'à 7 à 8 minutes) ;
- fusion automatique d'une MR par l'API (`auto_merge`, ou `merge_when_pipeline_succeeds` sur une version qui ne connaît pas encore le premier) quand `main` est protégée ;
- comportement de journald (systemd 257) quand `/var/log/journal` disparaît puis réapparaît, et de `loki.source.journal` d'Alloy 1.21 quand son répertoire disparaît ;
- autorisation d'un `kubectl exec` par WebSocket (kubectl 1.36) avec un Role qui donne `get` et `create` sur `pods/exec` ;
- présence de l'identité, de la ressource et de `exec` dans la ligne d'audit telle que la transforme le pipeline d'Alloy de M22-E07 ;
- `chunks-inspect` (Loki 3.7) sur un chunk au format v13 avec métadonnées structurées.

---

### M22-E19 — Panne : plus aucun journal d'un nœud

**Démarche de diagnostic**

*Symptômes* : un nœud (ou les trois nœuds de contrôle) ne produit plus rien dans Loki ; parfois seuls ses journaux **système** manquent, ses pods journalisant encore.

*Hypothèses, par étage* : (a) pas de pod Alloy sur le nœud (planification) ; (b) Alloy tourne mais un composant est en erreur ; (c) Alloy tourne mais la source n'a plus rien (journald) ; (d) Alloy envoie mais Loki refuse (→ E20).

*Commandes, dans l'ordre*

```
admin@adm01:~$ logcli query --org-id=plateforme --since=30m --quiet --limit=1 '{node="k8s-w02"}'          # muet depuis quand ?
admin@adm01:~$ logcli query --org-id=plateforme --since=30m --quiet --limit=1 '{node="k8s-w02", job="pods"}' # pods
admin@adm01:~$ logcli query --org-id=plateforme --since=30m --quiet --limit=1 '{node="k8s-w02", job="journald"}'
admin@adm01:~$ kubectl -n journaux get ds alloy
NAME    DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
alloy   5         5         5       5            5           <none>          9d
admin@adm01:~$ kubectl -n journaux get pods -o wide -l app.kubernetes.io/name=alloy
admin@adm01:~$ kubectl describe node k8s-w02 | sed -n '/Taints/,/Unschedulable/p'
Taints:             medisphere.internal/maintenance=disque:NoSchedule
admin@adm01:~$ kubectl get node k8s-w02 -o jsonpath='{.metadata.annotations.medisphere\.internal/maintenance-ticket}{"\n"}'
CHG-2319 changement du disque de données (Lucas)
```

`DESIRED 5` pour six nœuds : le DaemonSet a **renoncé** à un nœud. Si `DESIRED` vaut 6 et que le pod du nœud est prêt, l'étage est la source :

```
admin@k8s-w02:~$ logger -t essai "ligne de test $(date +%T)"; sudo journalctl -t essai -n 1 --no-pager
-- No entries --
admin@k8s-w02:~$ sudo systemd-analyze cat-config systemd/journald.conf | grep -v '^#' | grep -i storage
Storage=none
admin@k8s-w02:~$ ls -l /etc/systemd/journald.conf.d/
-rw-r--r-- 1 root root 141 nov.  5 09:12 60-economie-disque.conf
```

ou, quatrième cas :

```
admin@k8s-w02:~$ sudo journalctl --header | grep 'File path'
File path: /run/log/journal/3f1c…/system.journal
admin@k8s-w02:~$ ls -ld /var/log/journal* /run/log/journal
ls: impossible d'accéder à '/var/log/journal': Aucun fichier ou dossier de ce nom
drwxr-sr-x+ 3 root systemd-journal 60 nov.  5 09:12 /var/log/journal.archive-20261105
drwxr-sr-x+ 3 root systemd-journal 60 nov.  5 09:12 /run/log/journal
admin@adm01:~$ kubectl -n journaux logs <alloy-du-nœud> | grep -i journal | tail -3     # erreur d'ouverture du journal
```

*Cause racine, par variante*

| Variante | Cause | Ce qui le prouve |
|---|---|---|
| 1 | Taint `medisphere.internal/maintenance=disque:NoSchedule` posée sur un travailleur pour un changement de disque qui n'a pas eu lieu, puis pod Alloy du nœud supprimé : le DaemonSet ne recrée pas un pod qui ne tolère pas la taint (il ne tolère d'office que les taints posées par Kubernetes : `not-ready`, `unreachable`, pressions, `unschedulable`…) | `DESIRED` = nœuds − 1, `Taints` du nœud, annotation `maintenance-ticket` |
| 2 | Commit de Lucas dans `alloy/values.yaml` : tolérance `node-role.kubernetes.io/control-plane` retirée de `controller.tolerations` : le DaemonSet supprime ses pods des nœuds de contrôle ; journaux des nœuds de contrôle **et** journal d'audit de l'API arrêtés | `DESIRED 3`, `git log -p -- alloy/values.yaml`, historique de l'Application `alloy` |
| 3 | Fichier `/etc/systemd/journald.conf.d/60-economie-disque.conf` avec `Storage=none` : journald jette tout (ni disque, ni mémoire) ; Alloy n'a plus rien à lire ; `journalctl` sur le nœud est vide aussi | `systemd-analyze cat-config`, date du fichier |
| 4 | `/var/log/journal` renommé (`journal.archive-AAAAMMJJ`) puis journald relancé : en `Storage=auto` (défaut), journald n'écrit sur disque que si le répertoire existe, il bascule en volatil (`/run/log/journal`) ; Alloy lit `/var/log/journal` (`path` du composant `loki.source.journal`) et ne voit plus rien | `journalctl --header`, `ls -ld` |

*Correctif*
- V1 : vérifier avec l'auteur que la maintenance n'a pas lieu, retirer la taint (`kubectl taint node k8s-w02 medisphere.internal/maintenance-`) ; le DaemonSet recrée le pod dans la minute. **Et** décider si Alloy doit tolérer toutes les taints : pour un agent de journaux, oui (`- operator: Exists` dans `controller.tolerations`), sauf `NoExecute` d'éviction volontaire — c'est le réglage de la plupart des agents ; le choix se fait par MR.
- V2 : revert du commit par MR ; Argo CD remet les tolérances, les pods reviennent sur les nœuds de contrôle.
- V3 : supprimer le fichier, `systemctl restart systemd-journald` ; vérifier `journalctl -n 5`. Ce qui n'a jamais été écrit est perdu.
- V4 : remettre le répertoire (`mv /var/log/journal.archive-… /var/log/journal`), `systemctl restart systemd-journald`, puis `journalctl --flush` (le journal volatil accumulé pendant la panne part sur le disque) ; Alloy reprend à son curseur. Rien n'est perdu sur le nœud ; dans Loki, les lignes de la panne arrivent avec du retard si elles sont plus jeunes que `max_age` (7 h).
- V3 et V4 : reporter dans le rôle Ansible des nœuds (`k8s_noeud`) un état explicite de journald (`Storage=persistent`, limites de taille), pour que la prochaine dérive soit corrigée par Ansible.

*Prévention* : alertes du runbook RB-222 § 4 — « Alloy absent d'un nœud » en règle Prometheus [`regles/alloy-collecte.yaml`](fichiers/M22-E19/observabilite/regles/alloy-collecte.yaml) (`AlloyAbsentDUnNoeud`, avec son test [`tests/alloy-collecte.test.yaml`](fichiers/M22-E19/observabilite/tests/alloy-collecte.test.yaml), à ajouter à `regles/kustomization.yaml`) : elle compare les pods prêts au nombre de nœuds `Ready`, car les alertes `KubeDaemonSet*` de kube-prometheus-stack ne voient rien quand une taint ou une tolérance retirée fait baisser `desiredNumberScheduled` ; « nœud muet » en règle du *ruler* ; revue des MR de `alloy/` par la plateforme, politique « un agent de journaux tolère tout ».

**Livrable** : [`RB-222`](fichiers/M22-E19/medisphere/docs/observabilite/journaux/runbooks/RB-222-journaux-manquants.md) (version complétée en E22 : [`fichiers/M22-E22/…/RB-222-journaux-manquants.md`](fichiers/M22-E22/medisphere/docs/observabilite/journaux/runbooks/RB-222-journaux-manquants.md)).

**Pièges classiques**
- Redémarrer le nœud : la taint ou le fichier de journald sont toujours là.
- Ajouter la tolérance à la main dans le DaemonSet (`kubectl edit`) : Argo CD la retire au passage suivant.
- Recréer `/var/log/journal` vide (`mkdir`) au lieu de remettre l'ancien : le nœud perd l'accès simple à son historique (il reste lisible par `journalctl -D` dans le répertoire renommé).
- Conclure « Alloy est cassé » parce que ses journaux disent `no such file` : c'est la source qui a bougé.

---

### M22-E20 — Panne : Loki refuse les écritures

**Démarche de diagnostic**

*Symptômes* : lignes manquantes pour une équipe (V1), journaux des **nouveaux** déploiements absents (V3), erreurs 500 dans Grafana dès qu'on remonte loin et erreurs de stockage dans `loki-0` (V2).

*Hypothèses* : limite de débit du locataire, limite de flux, refus de validation (taille, âge), stockage objet inaccessible.

*Commandes, dans l'ordre*

```
admin@adm01:~$ kubectl -n journaux logs -l app.kubernetes.io/name=alloy --since=10m --prefix | grep -E 'status=|error' | tail -3
[pod/alloy-q8m2c/alloy] … component_id=loki.write.loki … msg="final error sending batch" status=429 tenant=mediagenda
  error="server returned HTTP status 429 Too Many Requests (429): ingestion rate limit exceeded for user mediagenda (limit: 104 bytes/sec) while attempting to ingest '12' lines totaling '3381' bytes, reduce log volume or contact your Loki administrator to see if the limit can be increased"
admin@adm01:~$ curl -s $LOKI_ADDR/metrics | grep '^loki_discarded_samples_total' | grep -v ' 0$'
loki_discarded_samples_total{format="loki",policy="",reason="rate_limited",retention_hours="720",tenant="mediagenda"} 2318
admin@adm01:~$ kubectl -n journaux get cm loki-runtime -o jsonpath='{.data.runtime-config\.yaml}' | yq '.overrides.mediagenda'
admin@adm01:~$ git -C ~/src/observabilite log -3 --format='%h %an %ad %s' -- loki/values.yaml
```

V3 : le message dit `maximum active stream limit exceeded when trying to create stream {app="journal-temoin", …}, … user: 'plateforme'` ; `loki_ingester_memory_streams{tenant="plateforme"}` est au-dessus de la limite lue dans `loki-runtime`. Les flux **anciens** passent toujours ; seuls les nouveaux sont refusés.

V2 :

```
admin@adm01:~$ kubectl -n journaux logs loki-0 -c loki --since=15m | grep -E 'level=error' | head -3
… msg="failed to flush" … err="… SignatureDoesNotMatch: The request signature we calculated does not match the signature you provided …"
admin@adm01:~$ kubectl -n journaux get secret loki-objstore -o json | jq '.metadata.annotations'
{ "medisphere.internal/rotation": "2026-10-lucas" }
admin@adm01:~$ kubectl -n journaux get secret loki-objstore -o jsonpath='{.data.LOKI_S3_SECRET_ACCESS_KEY}' | base64 -d | sha256sum
admin@adm01:~$ ansible-vault view --vault-id critique@~/medisphere/outils/vault-pass-client.sh secrets/loki.yml | yq '.loki_s3_secret_access_key' | tr -d '\n' | sha256sum
```

Empreintes différentes : le Secret ne contient plus la clé du compte RGW `loki`.

*Cause racine, par variante*

| Variante | Cause |
|---|---|
| 1 | Commit de Lucas : surcharge `mediagenda` `ingestion_rate_mb: 0.0001`, `ingestion_burst_size_mb: 0.0002` (« 100 Mo par jour converti » : l'unité est le **Mo par seconde**) : ~104 octets/s, rafale de 209 octets, presque chaque lot d'Alloy dépasse |
| 2 | Secret `loki-objstore` remplacé par une version à la clé secrète périmée (« rotation » de Lucas), puis `loki-0` redémarré : le RGW refuse toutes les signatures ; les vidages échouent (les chunks restent en mémoire et dans le WAL), les lectures du stockage échouent (500) |
| 3 | Commit de Lucas : `max_global_streams_per_user` de `plateforme` ramené à 80 % des flux actifs : tout **nouveau** flux (nouveau déploiement, nouveau nœud, nouvelle valeur d'étiquette) est refusé |

*Correctif*
- V1 et V3 : revert par MR (ou remise des valeurs de `performance.md`) ; vérifier que le rechargement est fait (`loki_runtime_config_last_reload_successful`, `/config/tenant/v1/limits` pour ce qui y est publié, sinon le ConfigMap) et que les rejets cessent.
- V2 : recréer le Secret depuis Vault par `plateforme/k8s/outils/secrets-k8s.sh` (composant `loki`), puis `kubectl -n journaux delete pod loki-0` (les variables d'environnement ne se relisent qu'au démarrage) ; le WAL est rejoué, les vidages en attente partent (`loki_ingester_chunks_flushed_total` fait un bond), la lecture d'hier revient. Rien n'est perdu de ce que Loki avait **accepté** ; ce qu'Alloy a abandonné pendant les redémarrages l'est.
- Chiffrer la perte : `sum by (pod) (increase(loki_write_dropped_entries_total[1h]))` (Prometheus, métriques d'Alloy).

*Prévention* : test de CI sur `loki/values.yaml` (bornes minimales des limites, unité en commentaire) ; la rotation des identifiants passe par Vault **et** `secrets-k8s.sh`, jamais par une édition du Secret ; alerte `LokiEchantillonsRejetes` plus réactive pour `rate_limited` sur les locataires applicatifs ; alerte sur `loki_ingester_chunks_flush_failures_total`.

**Livrable** : [`RB-223`](fichiers/M22-E20/medisphere/docs/observabilite/journaux/runbooks/RB-223-ingestion-refusee.md).

**Pièges classiques**
- Lever toutes les limites de tous les locataires : un locataire bavard peut alors saturer Loki pour tout le monde.
- Supprimer le PVC ou le WAL « pour débloquer » Loki : c'est la seule copie de ce qui n'a pas été vidé.
- Afficher la clé du Secret pour la comparer : elle finit dans l'historique du terminal ou dans le ticket. Comparer des empreintes.
- Chercher les journaux du problème dans Loki : c'est Loki qui refuse ; lire `kubectl logs`.

---

### M22-E21 — Panne : les requêtes expirent

**Démarche de diagnostic**

*Symptômes* : le tableau de 24 h de Nadia échoue, les requêtes de plus de quelques heures échouent dans Explore, celles de 5 minutes passent ; les autres locataires vont bien.

*Hypothèses* : limite de requête du locataire (délai, durée de plage, séries), découpage désactivé, Loki surchargé (mais alors tous les locataires souffriraient).

*Commandes, dans l'ordre*

```
admin@adm01:~$ q='sum by (namespace) (count_over_time({namespace=~".+"}[10m]))'
admin@adm01:~$ for t in plateforme mediagenda; do printf '%s : ' $t; curl -s -G -H "X-Scope-OrgID: $t" $LOKI_ADDR/loki/api/v1/query_range --data-urlencode "query=$q" --data-urlencode since=24h -o /dev/null -w '%{http_code}\n'; done
plateforme : 400
mediagenda : 200
admin@adm01:~$ curl -s -G -H 'X-Scope-OrgID: plateforme' $LOKI_ADDR/loki/api/v1/query_range --data-urlencode "query=$q" --data-urlencode since=24h
the query time range exceeds the limit (query length: 24h0m0s, limit: 6h)
admin@adm01:~$ diff <(curl -s -H 'X-Scope-OrgID: plateforme' $LOKI_ADDR/config/tenant/v1/limits) <(curl -s -H 'X-Scope-OrgID: mediagenda' $LOKI_ADDR/config/tenant/v1/limits)
< max_query_length: 6h
> max_query_length: 30d1h
admin@adm01:~$ git -C ~/src/observabilite log -1 -p -- loki/values.yaml | head -30
```

*Cause racine, par variante* (commit de Lucas « protéger Loki des requêtes trop lourdes », surcharge du locataire `plateforme`)

| Variante | Réglage | Message |
|---|---|---|
| 1 | `query_timeout: 1s` | `504` — `request timed out, decrease the duration of the request or add more label matchers (prefer exact match over regex match) to reduce the amount of data processed` |
| 2 | `max_query_length: 6h` | `400` — `the query time range exceeds the limit (query length: 24h0m0s, limit: 6h)` |
| 3 | `max_query_series: 3` | `400` — `maximum number of series (3) reached for a single query; consider reducing query cardinality…` |

*Correctif* : revert par MR, avec dans la description les valeurs de `performance.md` et leur mesure (délai de 2 min, plage de 30 jours, 500 séries). Vérifier `/config/tenant/v1/limits` puis le tableau de Nadia et une requête de 7 jours.

*Prévention* : toute modification de limite de requête cite une mesure ; test de CI qui refuse un `query_timeout` < 30 s ou un `max_query_length` < 7 jours ; tableau « Loki — santé » avec le taux d'erreurs des requêtes par locataire (`loki_request_duration_seconds_count{status_code=~"4..|5..", route=~"loki_api_v1_query.*"}`).

**Livrable** : [`RB-224`](fichiers/M22-E21/medisphere/docs/observabilite/journaux/runbooks/RB-224-requetes-loki.md).

**Pièges classiques**
- Augmenter `query_timeout` **global** à 10 min « pour que ça passe » : la vraie cause (surcharge du locataire) reste, et une requête mal écrite peut bloquer les requêteurs pour tous.
- Se fier au message résumé de Grafana : le message brut de Loki (par `curl` ou l'inspecteur) nomme la limite.
- Oublier qu'une limite peut être surchargée par locataire : `/config` (global) dit « 30d1h », le locataire a « 6h ».

---

### M22-E22 — Panne : les journaux d'une équipe ont disparu

**Démarche de diagnostic**

*Symptômes* : la source « Loki — mediagenda » ne montre plus rien de récent (V1, V2) ; MédiDoc ne voit plus que les dernières minutes (V3). Julien croit à une perte de données.

*Première question : les données existent-elles ?*

```
admin@adm01:~$ logcli query --org-id=mediagenda --since=30m --quiet --limit=3 '{namespace=~"mediagenda-.+"}'
admin@adm01:~$ logcli query --org-id=plateforme --since=30m --quiet --limit=3 '{namespace=~"mediagenda-.+"}'
2026-11-05T10:42:11Z {app="mediagenda", container="api", namespace="mediagenda-recette", …} {"horodatage": …}
```

- V1 : les lignes récentes de MédiAgenda sont **dans `plateforme`** (et plus dans `mediagenda`) → collecte.
- V2 : les lignes sont bien dans `mediagenda` (`logcli`), mais la source Grafana ne les montre pas → consultation.
- V3 : dans `medidoc`, `logcli --since=24h` ne renvoie que les 10 dernières minutes, quelle que soit la plage → limite.

*Commandes de confirmation*

```
admin@adm01:~$ git -C ~/src/observabilite log -3 --format='%h %an %ad %s' -- alloy/ grafana/ loki/
admin@adm01:~$ git -C ~/src/observabilite show <commit> -- alloy/config.alloy | grep -E '^[-+].*regex'
-		regex         = "(mediagenda|medidoc)-.+"
+		regex         = "(medidoc)-.+"
admin@adm01:~$ kubectl -n supervision get cm sources-loki -o jsonpath='{.data.sources-loki\.yaml}' | grep -A1 'httpHeaderValue1'
admin@adm01:~$ curl -s -H 'X-Scope-OrgID: medidoc' $LOKI_ADDR/config/tenant/v1/limits | grep -E '^(retention_period|max_query_lookback):'
max_query_lookback: 10m
retention_period: 30d
```

*Cause racine, par variante*

| Variante | Cause | Données |
|---|---|---|
| 1 | Commit de Lucas dans `alloy/config.alloy` : MédiAgenda retiré de la règle d'affectation du locataire (`(mediagenda|medidoc)-.+` devient `(medidoc)-.+`) « parce qu'il a son propre pipeline » ; le pipeline `stage.match` traite le format, pas le locataire : les lignes partent avec le locataire par défaut, `plateforme` | **Rien de perdu**, mal rangé : les lignes de la panne sont dans `plateforme` (14 jours) |
| 2 | Commit de Lucas dans `grafana/sources-loki.yaml` : `httpHeaderValue1: mediagenda-prod` (locataire inexistant) ; Grafana interroge un locataire vide | **Rien de perdu**, ni mal rangé : problème de vue |
| 3 | Commit de Lucas : surcharge `medidoc` `max_query_lookback: 10m` ; Loki tronque toute requête aux 10 dernières minutes sans erreur | **Rien de perdu** : la rétention (30 jours) n'a pas bougé, les chunks sont dans le compartiment |

*Correctif* : revert par MR dans les trois cas ; pour V2, le *sidecar* de Grafana recharge la source (sinon redémarrer le pod Grafana) ; pour V1, décider du sort des lignes rangées dans `plateforme` pendant la panne : les **laisser** (elles disparaîtront avec la rétention de 14 jours de `plateforme`, l'effacement y est fermé et elles ne contiennent pas de donnée personnelle), et donner à l'équipe la requête qui les retrouve pour la fenêtre de la panne.

*Réponse à Julien (extrait du journal)* : « Rien n'a été supprimé. Entre 9 h 58 et 10 h 47, vos journaux ont été écrits dans le locataire de la plateforme à la suite d'une modification de la collecte ; ils sont consultables par la plateforme jusqu'au 19/11 (requête jointe). Depuis 10 h 47, tout arrive de nouveau dans votre locataire. »

*Prévention* : alerte du *ruler* sur des flux `mediagenda-*`/`medidoc-*` dans `plateforme` (RB-222 § 4) ; test de CI de la configuration d'Alloy (`alloy validate` + un test d'affectation du locataire) ; revue obligatoire des MR touchant `stage.tenant` ou les sources Grafana.

**Livrable** : RB-222 complété, [`fichiers/M22-E22/…/RB-222-journaux-manquants.md`](fichiers/M22-E22/medisphere/docs/observabilite/journaux/runbooks/RB-222-journaux-manquants.md).

**Pièges classiques**
- Toucher à la **rétention** « pour récupérer » les journaux : elle n'y est pour rien, et la changer peut, elle, supprimer des données.
- Corriger la source Grafana dans l'interface : elle est provisionnée (`editable: false`) et le code la remettrait.
- Effacer les lignes mal rangées dans `plateforme` par réflexe : l'effacement y est fermé à dessein, et elles sont la seule copie de ces journaux.

---

### M22-E23 — Astreinte : enquête par les journaux

**Démarche de diagnostic**

*1. Rétablir l'outillage* : appliquer le corrigé de la panne enchaînée (E19 à E22), dans l'ordre « prouver que les données existent, puis réparer » ; vérifier qu'on interroge `mediagenda` et `audit` sur la période de l'incident. Les preuves ont été enregistrées **avant** la panne d'outillage : aucune ne manque si l'on ne touche ni à la rétention ni au compartiment.

*2. Enquêter dans les journaux de MédiAgenda (quand, comment)*

```
admin@adm01:~$ logcli query --org-id=mediagenda --since=6h --step=5m --quiet \
    'sum(count_over_time({namespace="mediagenda-recette"} |= "rendez-vous supprimé" [5m]))' -o raw
admin@adm01:~$ logcli query --org-id=mediagenda --from=<T-10min> --to=<T+10min> --quiet \
    '{namespace="mediagenda-recette"} |~ "rendez-vous (créé|supprimé)|DELETE" | json | line_format "{{.horodatage}} {{.message}} rdv={{.rdv_id}} {{.methode}} {{.chemin}} client={{.client}}"'
2026-11-05T09:13:41.208+00:00 rendez-vous créé rdv=412 …
…
2026-11-05T09:14:53.112+00:00 requête rdv= DELETE /api/v1/rendez-vous/412 client=127.0.0.1
2026-11-05T09:14:53.114+00:00 rendez-vous supprimé rdv=412 …
```

Lecture : quatre créations à 09:13 (UTC), quatre suppressions une minute plus tard, **client 127.0.0.1** pour les deux séries : les requêtes ne viennent ni de la Gateway ni d'un autre pod (on y verrait leur adresse), elles sont nées **dans le pod** — un `kubectl exec` (ou un conteneur ajouté au pod, ce que l'audit dira).

*3. Enquêter dans le journal d'audit (qui)*

```
admin@adm01:~$ logcli query --org-id=audit --from=<T-10min> --to=<T+10min> --quiet \
    '{job="kubernetes-audit"} |= "mediagenda-recette" |= "exec"'
… "user":{"username":"system:serviceaccount:wb-pannes:outillage-recette", …},"objectRef":{"resource":"pods","namespace":"mediagenda-recette","name":"mediagenda-7c9d…-x2k4p","subresource":"exec"} …
admin@adm01:~$ logcli query --org-id=audit --since=48h --quiet \
    '{job="kubernetes-audit"} |= "outillage-recette" |~ "rolebindings|roles|serviceaccounts" |~ "\"verb\":\"create\""'
```

(avec les métadonnées structurées d'E07, `| user=~"system:serviceaccount:.*" | resource="pods"` est plus rapide que des filtres de ligne). L'exec du compte de service tombe à la même seconde que les suppressions ; un exec précédent (09:13, **ton** identité : celle du script, en production celle de la personne qui a préparé la démo) a créé les rendez-vous. Les objets RBAC ont été créés par ton identité (le script) : en production, l'auteur de « l'outil de purge ».

*Cause racine* : un compte de service d'outillage (`wb-pannes/outillage-recette`) disposait d'un droit d'`exec` dans `mediagenda-recette` (Role et RoleBinding `outillage-recette`, étiquette `medisphere.internal/ticket: DEV-2323`) ; il a appelé l'API de MédiAgenda depuis l'intérieur d'un pod pour supprimer les rendez-vous de démonstration. Aucun contrôle n'empêchait ce droit, aucune alerte ne l'a vu.

*4. Remédier*

```
admin@adm01:~$ kubectl -n mediagenda-recette get rolebindings -o json | jq -r '.items[] | select(any(.subjects[]?; .kind=="ServiceAccount" and .namespace!="mediagenda-recette")) | .metadata.name'
outillage-recette
admin@adm01:~$ kubectl -n mediagenda-recette delete rolebinding,role outillage-recette
admin@adm01:~$ kubectl auth can-i create pods/exec -n mediagenda-recette --as=system:serviceaccount:wb-pannes:outillage-recette
no
```

(trace dans le ticket ; si `plateforme/k8s` décrit les droits de l'espace, la correction y passe par MR). Vérifier les autres espaces applicatifs avec la même requête `jq`.

*5. Prévenir* : règle du *ruler* (locataire `audit`) — `sum by (user) (count_over_time({job="kubernetes-audit"} | resource="pods" | subresource="exec" | object_ns=~"mediagenda-.+|medidoc-.+" | user!~"…équipe…" [5m])) > 0` (adapter aux champs d'E07) ; ValidatingAdmissionPolicy (M14) qui refuse un RoleBinding donnant `pods/exec` dans un espace d'équipe à un sujet hors de l'équipe (traité en M26).

**Livrable** : exemple de post-mortem [`2026-11-05-INC-4923-…`](fichiers/M22-E23/medisphere/docs/kubernetes/post-mortems/2026-11-05-INC-4923-rendez-vous-supprimes-recette.md).

**Pièges classiques**
- Enquêter avant d'avoir rétabli l'outillage : on conclut « pas de trace » alors que les traces sont dans un autre locataire ou au-delà d'une profondeur réduite.
- Chercher l'auteur dans les journaux de MédiAgenda : une application ne sait pas qui l'appelle depuis `127.0.0.1` ; c'est l'audit de l'API qui le sait.
- Confondre l'identité qui a **créé** les droits (ou les rendez-vous) et celle qui a **supprimé**.
- Recopier une ligne d'audit complète dans le post-mortem : elle peut contenir des jetons ou des en-têtes ; ne garder que les champs utiles.
- Supprimer le compte de service avant d'avoir les preuves : les journaux restent, mais le contexte (RoleBinding, annotations) disparaît de l'API.

---

### M22-E24 — Sous le capot : ingestion, chunks et index TSDB

**Solution**

*1. Écrire une ligne et la suivre*

```
admin@adm01:~$ m=e24-$(date +%s); curl -s -H 'X-Scope-OrgID: essai' -H 'Content-Type: application/json' $LOKI_ADDR/loki/api/v1/push \
    --data "{\"streams\":[{\"stream\":{\"job\":\"e24\",\"namespace\":\"wb-essais\"},\"values\":[[\"$(date +%s%N)\",\"$m\"]]}]}" -w '%{http_code}\n'
204
admin@adm01:~$ curl -s $LOKI_ADDR/metrics | grep -E '^loki_(distributor_lines_received_total|ingester_memory_streams)\{.*essai'
admin@adm01:~$ kubectl debug -it loki-0 -n journaux --image=registry.par1.medisphere.internal/dockerhub/library/busybox:1.37 --target=loki -- sh
/ # ls -la /proc/1/root/var/loki/ /proc/1/root/var/loki/wal/
compactor  rules  ruler-tmp  ruler-wal  tsdb-shipper-active  tsdb-shipper-cache  wal
00000041  00000042  checkpoint.000040
/ # exit
```

Le conteneur éphémère reste attaché au pod (visible dans `kubectl describe pod`) jusqu'à son redémarrage : c'est normal, il ne tourne plus. Après 30 minutes d'inactivité du flux (`chunk_idle_period`), le chunk est vidé :

```
admin@adm01:~$ set -a; . ~/.config/workbook/s3-loki.env; set +a; E=https://rgw.par1.medisphere.internal
admin@adm01:~$ aws s3api list-objects-v2 --bucket loki-k8s-par1 --prefix essai/ --endpoint-url $E \
    --query 'sort_by(Contents,&LastModified)[-3:].[Key,Size,LastModified]' --output text
essai/a3f09c11d2e4b7c8/19a2f1b47e2:19a2f1b47e2:8d41c2e0   287   2026-11-05T10:31:12Z
```

*2. Lire un chunk*

```
admin@adm01:~$ mkdir -p ~/m22/e24 && cd ~/m22/e24
admin@adm01:~/m22/e24$ aws s3 cp "s3://loki-k8s-par1/essai/a3f09c11d2e4b7c8/19a2f1b47e2:19a2f1b47e2:8d41c2e0" chunk --endpoint-url $E
admin@adm01:~/m22/e24$ git clone --depth 1 --branch v3.7.9 https://github.com/grafana/loki.git src-loki   # par le miroir si Internet est filtré
admin@adm01:~/m22/e24$ (cd src-loki/cmd/chunks-inspect && go build -o ~/m22/e24/chunks-inspect .)
admin@adm01:~/m22/e24$ ./chunks-inspect -l chunk
```

Clé : `<locataire>/<empreinte du flux en hexadécimal>/<début ms hex>:<fin ms hex>:<somme CRC32 hex>` ; `printf '%d\n' 0x19a2f1b47e2` donne l'horodatage en millisecondes. L'empreinte est un hachage de l'ensemble des étiquettes : deux flux qui diffèrent d'une étiquette ont deux empreintes, donc deux préfixes.

*3-4. Index et compactor*

```
admin@adm01:~$ aws s3 ls s3://loki-k8s-par1/index/ --endpoint-url $E | tail -3
admin@adm01:~$ N=$(( $(date -u +%s) / 86400 )); date -u -d @$((N * 86400))
admin@adm01:~$ aws s3 ls s3://loki-k8s-par1/index/loki_index_$N/ --recursive --summarize --endpoint-url $E | tail -4
admin@adm01:~$ aws s3 ls s3://loki-k8s-par1/index/delete_requests/ --endpoint-url $E
```

Chaque table `loki_index_N` (N = jours depuis l'époque Unix, période de 24 h) a un dossier par locataire ; l'ingester y téléverse ses fichiers TSDB, le compactor les fusionne en **un** fichier par locataire et par jour (`<ns>-compactor-<début>-<fin>-<somme>.tsdb.gz`), en y appliquant la rétention et les demandes d'effacement (`index/delete_requests/delete_requests.gz`). Le volume d'index d'une journée est de l'ordre du pour-cent de celui des chunks.

*5. Chemin de lecture* : `logcli query --stats` sur les 10 dernières minutes (`Ingester.TotalReached: 1`, aucun chunk téléchargé) contre hier (chunks téléchargés du stockage, `TotalBytesProcessed` plus grand).

*6. Livrable* : exemple [`sous-le-capot.md`](fichiers/M22-E24/medisphere/docs/observabilite/journaux/sous-le-capot.md).

**Explications**

Loki est un « Prometheus pour les journaux » : l'index ne connaît que les flux (ensembles d'étiquettes) et les intervalles de leurs chunks ; tout le contenu est dans les chunks, compressés par blocs. Le WAL protège ce qui est en mémoire ; le vidage transforme les flux en objets immuables ; l'index d'une journée est petit et se met en cache sur le disque du requêteur ; le compactor réduit le nombre de fichiers d'index et applique rétention et effacement. Comprendre cela, c'est comprendre pourquoi une étiquette coûte cher (un flux de plus partout), pourquoi la rétention est quotidienne, pourquoi le compactor doit être unique, et pourquoi les requêtes récentes passent par l'ingester.

**Pièges classiques**
- Ouvrir un chunk du compartiment avec un éditeur ou le recopier **vers** le compartiment : on corrompt le locataire.
- Oublier `--target=loki` dans `kubectl debug` : le conteneur éphémère ne voit pas le système de fichiers de Loki.
- Forcer `POST /flush` pour « voir le chunk tout de suite » sur une plateforme partagée : petits chunks pour tous les flux.

**En production chez MédiSphère**
La lecture du compartiment par un humain se fait avec un compte RGW **en lecture seule** dédié à l'exploration (à créer au M25 avec les secrets), jamais avec le compte d'écriture de Loki.
