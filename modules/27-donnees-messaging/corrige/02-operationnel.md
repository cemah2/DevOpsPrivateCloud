# Module 27 — Palier 2 : Opérationnel — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Mêmes conventions que le corrigé du palier 1 : fichiers complets dans [`fichiers/`](fichiers/), par exercice, avec l'arborescence du projet (`k8s/` = `plateforme/k8s`, `donnees/` = `plateforme/donnees`, `gitops/` = `plateforme/gitops`, `secrets/` = `plateforme/secrets`, `charts-miroir/`, `mediagenda-api/`, `mediagenda-deploiement/`, `medinotif-worker/`, `medinotif-deploiement/`, `medisphere/` = la documentation). Un nom en `.extrait` ne contient que ce qui change ; un `LISEZMOI` dit comment appliquer un correctif.

**Ce qui a été vérifié à la rédaction** (23/10/2026) :
- **Code** : `rappel.patch` (E06) et `notifications.patch` (E08) appliqués par `git apply` sur l'état de `mediagenda/api` à la fin du M26, puis `uv add "pika>=1.4.4,<2"` : **67 tests** verts, `ruff check` et `ruff format --check` propres ; l'essai d'intégration de la publication est vert contre un **RabbitMQ 4.3.7** réel (TLS, confirmations, `mandatory`, échange non lié → échec compté). `kafka.patch` (E10) appliqué sur `medinotif/worker` + `uv add "confluent-kafka>=2.16.0,<3"` : **32 tests** verts, `ruff` propre ; intégration contre **Kafka 4.3.1** (KRaft) : envoi, rebut, *commit*, reprise après redémarrage.
- **Migrations** : `V1` à `V4` appliquées par **Flyway 13.11.1** (UID 10004) sur **PostgreSQL 18.6** (`Success` ×4, contraintes validées, défaut retiré) ; file d'attente des verrous et `lock_timeout` reproduits (l'`ALTER` échoue au bout du délai, transaction annulée, migration toujours `Pending`). Essai **N−1** (`ci/fumee_n_moins_1.py` avec le code de l'API d'avant E06, schéma migré par `python -m mediagenda.migrate --repertoire`) : **vert** avec V1-V3, **rouge** avec V1-V4 (`NotNullViolation … "canal_rappel"`).
- **Valkey 9.1.2** réel (`valkey/valkey:9.1.2-trixie`, UID 999, racine en lecture seule) avec la configuration d'E07 (TLS seul, fichier ACL avec empreintes SHA-256, `maxmemory` + `allkeys-lru`, sans persistance) : module `lua` chargé ; la sonde (`valkey-cli --user sonde` + `grep PONG`) réussit, échoue sur un mauvais mot de passe — alors que `valkey-cli` rend 0 sur `NOAUTH` ; `BGSAVE` possible avec `save ""` ; **une RDB écrite par 8.1.10 est relue** par `valkey-check-rdb` 9.1.2 ; **`tls-auto-reload-interval`** : certificat remplacé sur disque, nouveau numéro de série servi sans redémarrage (`TLS materials reloaded successfully`), `INFO` expose `tls_server_cert_expires_in_seconds`. Client `redis` 8.1 de l'API en `rediss://` : nom vérifié, `SSL_CERT_FILE` honoré ; compte `mediagenda` : `SET autre:x`, `FLUSHALL`, `CONFIG GET`, `KEYS` refusés (`NOPERM`). **redis_exporter v1.95.0** avec le compte `exportateur` : `redis_up 1`, **aucune** erreur de droits (il exige `latency|histogram`), `redis_instance_info{valkey_version="9.1.2", redis_version="7.2.4", maxmemory_policy="allkeys-lru"}`, `redis_scripting_engine_info{module="lua"}`.
- **Kafka** : producteur du Job d'essai (`kafka-console-producer` 4.3.1, SCRAM-SHA-512 sur TLS, magasin de confiance PEM, `--command-config`, racine en lecture seule, UID 1000) contre un courtier 4.3.1 SASL_SSL : lot envoyé ; mot de passe faux → le script rend **1** (l'outil de Kafka, lui, rend 0).
- **Manifestes** : tous les objets des corrigés E07 à E10 et les manifestes de Lucas (E11) validés par `kubectl apply --dry-run=server` (validation **stricte** des champs) contre le kube-apiserver 1.36 *envtest* chargé des CRD exactes (Strimzi 1.3.0 : `operation` au singulier et `spec.kafka.replicas` sont bien refusés en `v1`) ; rendus Kustomize (5.8.1) des components `valkey`, `racine-medisphere`, `notifications` et de l'overlay de prod de MédiNotif ; `value: null` d'un correctif stratégique retire bien `value` au profit de `valueFrom`. Chart Strimzi 1.3.0 : empreinte de l'archive recalculée, rendu des valeurs (images `registry.par1…/quay/strimzi/…:1.3.0-kafka-4.3.1`, `STRIMZI_NAMESPACE` = l'espace de l'opérateur), CRD sans annotation de conservation.
- **Documentation amont lue** : Valkey (TLS : rechargement automatique ; notes de 9.1), RabbitMQ (files quorum : en 4.3, un `basic.nack` avec remise en file ne compte pas pour la limite de livraison, un `basic.reject` si), CloudNativePG 1.30 (bascule automatique, délais de détection d'un nœud injoignable ; archivage intégré retiré en **1.31**), External Secrets (fonctions de Sprig dans les modèles `v2`).
- **Scripts** : checks du palier passés à `shellcheck -x` et `bash -n` ; `messages.py` et `fumee_n_moins_1.py` exécutés.

**Points non testés en conditions réelles**, à vérifier sur ton lab :
- le job `migrations:compatibilite` dans GitLab (image de l'API comme image de job : `python` dans le `PATH`, `cd /tmp` possible) ;
- la bascule de la recette de Valkey (StatefulSet du M16 → component) et la durée de `503` ; la génération du fichier ACL par ESO (fonction `sha256sum` du modèle) dans le cluster ; Reloader sur un StatefulSet ;
- l'exportateur joignant `valkey.mediagenda-<env>.svc` par `hostAliases` (testé hors cluster par `--add-host`) ;
- tout Strimzi **en fonctionnement** (création de la grappe, *finalizers* des `KafkaTopic` au retrait, noms exacts des PVC, durée d'un rééquilibrage) et le retrait complet par Argo CD (suppression des CRD) ;
- les durées des runbooks (elles viennent de TES mesures d'E02).

---

### M27-E06 — Migrations sans interruption : *expand/contract*

**Solution**

*A. Le verrou.* Grappe [`schema-essai`](fichiers/M27-E06/essais/schema-essai.yaml) (une instance, V1 et V2 appliquées par `psql`, 20 000 lignes). Les trois sessions :
- (a) `BEGIN; SELECT count(*) FROM rendez_vous;` tient un verrou `ACCESS SHARE` jusqu'à la fin de sa transaction ;
- (b) l'`ALTER TABLE … ADD COLUMN` demande `ACCESS EXCLUSIVE`, incompatible : il **attend** ;
- (c) le `SELECT` demande `ACCESS SHARE`, compatible avec (a)… mais la file des demandes est servie dans l'ordre : il attend **derrière** (b). Dans `pg_stat_activity` : (b) et (c) `wait_event_type = Lock`, `wait_event = relation` ; `pg_blocking_pids(<pid de c>)` renvoie le pid de (b), celui de (b) renvoie (a).

Sur MédiAgenda, c'est toute l'API qui gèle tant qu'une transaction longue (un export, une session `psql` oubliée) n'a pas fini. Avec `SET lock_timeout = '2s'`, (b) échoue au bout de 2 s (`canceling statement due to lock timeout`), (c) passe aussitôt. `statement_timeout` borne la durée **totale** de l'instruction (attente comprise) : utile en plus, pour qu'un `VALIDATE` sur une grosse table ne dure pas des heures. Le Job d'E05 (`backoffLimit: 2`, `activeDeadlineSeconds: 600`) réessaie ; la transaction de la migration est annulée (PostgreSQL : DDL transactionnel), Flyway la laisse `Pending`, la synchronisation d'Argo CD s'arrête **avant** la nouvelle version de l'API : l'ancienne continue de servir.

Mesures (étape 4) : `ADD COLUMN … NOT NULL DEFAULT 'aucun'` est instantané depuis PostgreSQL 11 (défaut constant stocké dans le catalogue, pas de réécriture) mais prend `ACCESS EXCLUSIVE` ; `ADD CONSTRAINT CHECK` sans `NOT VALID` parcourt la table **sous** `ACCESS EXCLUSIVE` ; avec `NOT VALID`, aucun parcours ; `VALIDATE CONSTRAINT` parcourt sous `SHARE UPDATE EXCLUSIVE` (lectures et écritures continuent).

*B. Le découpage* (`~/m27/e06/plan.md`) :

| Étape | Migration | API déployée | Versions qui tournent | Si on inverse |
|---|---|---|---|---|
| 1 | `V3` (*expand*) | N (gère le rappel) | N−1 seule pendant le Job, puis N−1 et N (*canary*), puis N | N avant V3 : N lit `canal_rappel`, absente → 500 |
| 2 | — | (attente : N partout, dev, recette, prod) | N | — |
| 3 | `V4` (*contract*) | N+1 | N et N+1 | V4 avec N−1 encore en service : N−1 ne crée plus de rendez-vous (`NOT NULL` violé) |

Compatibilité : N−1 lit par une liste de colonnes **explicite** (les colonnes ajoutées ne la gênent pas) et écrit sans nommer `canal_rappel` (défaut `aucun`, `contact_rappel` nul : contraintes respectées). N lit les deux colonnes et écrit **toujours** le canal. Une ligne écrite par N avec un rappel est lue par N−1 sans le rappel (rien ne casse). Retour arrière après V3 : sans risque (N−1 ignore les colonnes). Après V4 : retour arrière vers N **seulement** (N écrit le canal) ; vers N−1, impossible — d'où l'attente de l'étape 2.

Fichiers : [`V3__rappel_expand.sql`](fichiers/M27-E06/mediagenda-api/migrations/V3__rappel_expand.sql), [`V4__rappel_contract.sql`](fichiers/M27-E06/mediagenda-api/migrations/V4__rappel_contract.sql). Contenu (aussi en annexe de [`migrations.md`](fichiers/M27-E06/medisphere/docs/donnees/migrations.md)) :

```sql
-- V3 : SET LOCAL lock_timeout = '5s'; SET LOCAL statement_timeout = '30s';
ALTER TABLE rendez_vous
    ADD COLUMN canal_rappel   text NOT NULL DEFAULT 'aucun',
    ADD COLUMN contact_rappel text;
ALTER TABLE rendez_vous
    ADD CONSTRAINT rendez_vous_canal_rappel_ck CHECK (canal_rappel IN ('sms', 'mail', 'aucun')) NOT VALID,
    ADD CONSTRAINT rendez_vous_contact_rappel_ck
        CHECK ((canal_rappel = 'aucun') = (contact_rappel IS NULL)
               AND (contact_rappel IS NULL OR length(contact_rappel) <= 254)) NOT VALID;
-- + COMMENT ON COLUMN … (dont « donnée personnelle, RGPD »)

-- V4 : SET LOCAL lock_timeout = '5s'; SET LOCAL statement_timeout = '5min';
ALTER TABLE rendez_vous VALIDATE CONSTRAINT rendez_vous_canal_rappel_ck;
ALTER TABLE rendez_vous VALIDATE CONSTRAINT rendez_vous_contact_rappel_ck;
ALTER TABLE rendez_vous ALTER COLUMN canal_rappel DROP DEFAULT;
```

L'ordre de V4 : les `VALIDATE` d'abord (verrou faible, gardé jusqu'à la fin de la transaction), le `DROP DEFAULT` (instantané, `ACCESS EXCLUSIVE`) en dernier. Dans l'autre ordre, l'`ACCESS EXCLUSIVE` pris en premier serait **gardé** pendant les deux parcours : table fermée à tous.

Code N : [`rappel.patch`](fichiers/M27-E06/mediagenda-api/rappel.patch) ([`LISEZMOI`](fichiers/M27-E06/mediagenda-api/LISEZMOI.md)) — modèle `Rappel` (`canal` ∈ `sms|mail|aucun`, défaut `aucun` ; contact obligatoire si canal ≠ `aucun`, interdit sinon ; formats de MédiNotif), colonnes explicites et `_depuis_ligne` dans le dépôt, canal toujours écrit, attribut de trace `mediagenda.rappel.canal`, tests (`422` sur les cas invalides, contact absent des journaux).

*C. Le garde-fou.* [`.gitlab-ci.yml.extrait-M27-E06`](fichiers/M27-E06/mediagenda-api/.gitlab-ci.yml.extrait-M27-E06) et [`ci/fumee_n_moins_1.py`](fichiers/M27-E06/mediagenda-api/ci/fumee_n_moins_1.py). L'image du job **est** l'image publiée de la version en production : son paquet `mediagenda` est le code N−1. Le dépôt cloné apporte les migrations de la branche. `cd /tmp` évite qu'un `src/` de la branche soit importé à la place (avec la disposition `src/` du projet, ce n'est pas le cas, mais le job ne doit pas en dépendre ; la ligne `print(m.version("mediagenda"), mediagenda.__file__)` le prouve dans le journal). Résultat attendu : MR `V3` seule → vert ; `V3` + `V4` → rouge :
```
fumée N−1 : ÉCHEC — NotNullViolation : null value in column "canal_rappel" of relation "rendez_vous" violates not-null constraint
```

*D. La livraison.* `vX.Y.0` (V3 + code) : image de migration et image de l'API signées, promotion en recette, *canary* : créations avec et sans rappel, `GET` croisés entre pods N−1 et N (en-tête `X-Pod` ou journaux) — tous `200`. Prod : MR approuvée, sauvegarde, synchronisation manuelle. Puis `VERSION_N_MOINS_1: vX.Y.0` dans le `.gitlab-ci.yml`, et `vX.Y+1.0` avec V4. Journal du Job :
```
| Versioned | 3       | rappel expand   | SQL      | … | Success | No |
| Versioned | 4       | rappel contract | SQL      | … | Success | No |
```

**Explications**

Le Job de migration passe **avant** la nouvelle version (vague −1) et le Rollout garde l'ancienne pendant le *canary* : le schéma doit servir deux versions à la fois, et rester compatible en cas de retour arrière. *Expand/contract* est la seule méthode générale ; les délais (`lock_timeout`) protègent la production d'une migration « instantanée » qui attend son verrou. Le job N−1 transforme une règle de revue (« cette migration est-elle compatible ? ») en preuve automatique.

**Alternatives**

- **Déclencheur** (*trigger*) pour remplir une nouvelle colonne depuis l'ancienne pendant la transition (renommage) : efficace, mais du code dans la base, à retirer au *contract*.
- **Vues de compatibilité** : l'ancienne version lit une vue qui a l'ancien schéma ; utile pour les renommages, lourd à maintenir.
- **pgroll**, **Reshape** : outils qui automatisent *expand/contract* (schémas versionnés par vues) ; intéressants, mais un outil de plus que Flyway, et PostgreSQL seulement.
- **Fenêtre de maintenance** : arrêter l'API, migrer, redémarrer ; acceptable pour un outil interne, pas pour la prise de rendez-vous.

**Pièges classiques**

- `SELECT *` dans le code : une colonne ajoutée change la forme du résultat (et un modèle Pydantic strict refuse le champ inconnu).
- `NOT NULL` sans défaut dans l'*expand* : N−1 casse dès la migration.
- `SET` au lieu de `SET LOCAL` : avec un *pooler* ou une connexion réutilisée, le réglage survit à la migration. (Flyway passe par la connexion directe, mais l'habitude compte.)
- Livrer V4 dès que la **prod** est en N, en oubliant dev ou une branche de recette encore en N−1.
- Croire que `lock_timeout` « annule la migration proprement » partout : sur un SGBD sans DDL transactionnel, une migration à moitié appliquée resterait. PostgreSQL annule tout.
- `CREATE INDEX CONCURRENTLY` dans une migration transactionnelle : refusé par PostgreSQL ; il faut une migration à part, hors transaction.

**En production chez MédiSphère**

La règle « une migration est compatible avec la version en production » est dans [`migrations.md`](fichiers/M27-E06/medisphere/docs/donnees/migrations.md), le job la vérifie, et la revue de MR demande pour chaque migration « *expand* ou *contract* ? ». `VERSION_N_MOINS_1` gagnerait à être tenue par la promotion (`outils/promouvoir.sh` ouvrant la MR sur `mediagenda/api`) plutôt qu'à la main. M27-E21 (palier 4) casse une migration qui attend son verrou : ce que tu as vu ici.

---

### M27-E07 — Valkey 9 : montée de version, ACL, TLS et éviction

**Solution**

*A. État des lieux.* Dev et prod : StatefulSet du component `dependances` (8.1, sans mot de passe, `emptyDir`, annotation de suivi d'Argo CD) ; recette : StatefulSet du M16 (`k8s/recette/30-valkey.yaml` de `mediagenda/api`, PVC `donnees-valkey-0` en `ceph-rbd-chiffre`, `managedFields` de `kubectl`, **pas** d'annotation de suivi). Aucune `maxmemory` (0 = illimité) et `noeviction` par défaut : la mémoire monte jusqu'à la limite du **conteneur** (128 Mio), le noyau tue Valkey (`OOMKilled`), le cache repart vide, `/pret` en 503 le temps du redémarrage — c'est ce que la règle `MediagendaValkeyMemoireHaute` du M21 essayait d'anticiper.

Sauvegarde de la recette (avant tout) — mot de passe inutile, il n'y en a pas encore :
```
admin@adm01:~$ kubectl -n mediagenda-recette exec valkey-0 -- valkey-cli BGSAVE
admin@adm01:~$ kubectl -n mediagenda-recette exec valkey-0 -- valkey-cli INFO persistence | grep rdb_last_bgsave_status
rdb_last_bgsave_status:ok
admin@adm01:~$ kubectl -n mediagenda-recette cp valkey-0:/data/dump.rdb ~/m27/e07/valkey-recette.rdb
```
Relecture par 9.1 (pod jetable `valkey:9.1.2-trixie` dans `wb-essais`, fichier copié par `kubectl cp`) : `valkey-check-rdb /data/dump.rdb` → `\o/ RDB looks OK! \o/`. Le format RDB a un numéro de version : une version récente relit les anciens formats, pas l'inverse (une 8.1 refuse une RDB d'un format qu'elle ne connaît pas). Si la RDB du M16 était vide (`save ""` en dev/prod), c'est normal : on sauvegarde par principe, on vérifie la **procédure**.

Notes 9.0/9.1 qui comptent : Lua devient un **module** chargé par défaut (`MODULE LIST` → `lua` ; les `EVAL` restent possibles), ACL par base, rechargement automatique des certificats (`tls-auto-reload-interval`), dates d'expiration des certificats dans `INFO`, authentification mTLS par SAN. `INFO server` répond `redis_version:7.2.4` **et** `valkey_version:9.1.2` : Valkey fige la première pour les clients et outils qui testent la « version de Redis » ; le client `redis` de l'API fonctionne sans changement.

*B. Le component.* Mots de passe (hexadécimaux : sûrs dans une URL et dans le fichier ACL) :
```
admin@adm01:~$ for env in recette prod dev; do
  M=$(openssl rand -hex 24) A=$(openssl rand -hex 24) E=$(openssl rand -hex 24) S=$(openssl rand -hex 24) ENV=$env \
    jq -n '{mot_de_passe: env.M, mot_de_passe_admin: env.A, mot_de_passe_exportateur: env.E,
            mot_de_passe_sonde: env.S,
            url: ("rediss://mediagenda:" + env.M + "@valkey.mediagenda-" + env.ENV + ".svc:6379/0")}' |
    bao kv put -mount=kv "mediagenda/$env/valkey" - >/dev/null
done
```
(Les mots de passe ne passent ni par l'historique ni par la ligne de commande d'un processus (visible par `ps`) : ils sont dans l'environnement de `jq`, puis sur l'entrée standard de `bao` — `-` : données JSON lues sur l'entrée.)

Fichiers ([`mediagenda-deploiement/`](fichiers/M27-E07/mediagenda-deploiement/)) :
- [`components/valkey/`](fichiers/M27-E07/mediagenda-deploiement/components/valkey/) : `valkey.conf` (ConfigMap générée), [`externalsecrets.yaml`](fichiers/M27-E07/mediagenda-deploiement/components/valkey/externalsecrets.yaml) (le fichier ACL est construit par le modèle : `#{{ .mot_de_passe | sha256sum }}`), [`statefulset.yaml`](fichiers/M27-E07/mediagenda-deploiement/components/valkey/statefulset.yaml) (sondes qui authentifient avec `sonde` et vérifient `PONG`, exportateur), `service.yaml`, `reseau.yaml`, `podmonitor.yaml`, et dans `kustomization.yaml` le correctif de l'API (`MEDIAGENDA_VALKEY_URL` lue dans `mediagenda-valkey`, `value: null`) et l'annotation de Reloader du Rollout ;
- [`components/racine-medisphere/`](fichiers/M27-E07/mediagenda-deploiement/components/racine-medisphere/kustomization.yaml) : ConfigMap de la racine, `SSL_CERT_FILE` dans l'API ;
- [`components/dependances/kustomization.extrait-E07.yaml`](fichiers/M27-E07/mediagenda-deploiement/components/dependances/kustomization.extrait-E07.yaml) : Valkey en sort ;
- overlays : [`valkey.yaml`](fichiers/M27-E07/mediagenda-deploiement/overlays/recette/valkey.yaml) (Certificate) et [`kustomization.extrait-E07.yaml`](fichiers/M27-E07/mediagenda-deploiement/overlays/recette/kustomization.extrait-E07.yaml) (chemin OpenBao, `hostAliases`, et en [prod](fichiers/M27-E07/mediagenda-deploiement/overlays/prod/kustomization.extrait-E07.yaml) les deux condensés) ;
- [`components/supervision/regle-valkey.yaml`](fichiers/M27-E07/mediagenda-deploiement/components/supervision/regle-valkey.yaml) ; documentation [`valkey.md`](fichiers/M27-E07/medisphere/docs/donnees/valkey.md).

Plateforme : port 9121 dans `collecte-prometheus` (déjà prévu au fichier d'[E02](fichiers/M27-E02/k8s/composants/reseau/politiques/collecte-prometheus.yaml)).

*C. La bascule de la recette* (journal écrit avant). L'Application `mediagenda-recette` synchronise seule, et l'ancien StatefulSet (M16) n'est pas suivi par Argo CD : la synchronisation tenterait de le **modifier** (même nom) et buterait sur son `volumeClaimTemplates` immuable. Ordre retenu : (1) sauvegarde (fait) ; (2) MR qui ajoute les components à l'overlay de recette, relue, **pas encore fusionnée** ; (3) `kubectl delete statefulset valkey -n mediagenda-recette` — début de la coupure (`valkey-0` s'arrête, `/pret` en 503) ; (4) fusion, synchronisation : Secrets, certificat, nouveau StatefulSet ; (5) `valkey-0` prêt : fin de la coupure ; (6) `kubectl delete pvc donnees-valkey-0 -n mediagenda-recette` (orphelin : un StatefulSet supprimé laisse ses PVC) ; (7) MR sur `mediagenda/api` qui supprime `k8s/recette/30-valkey.yaml`. Coupure mesurée par la boucle `curl` : synchronisation + émission du certificat + démarrage, quelques dizaines de secondes ; les pods de l'API redémarrent aussi (nouvelle variable, nouveau volume) par le *canary* de la recette. Variante sans coupure : un second Valkey sous un autre nom, bascule de l'URL, retrait de l'ancien — inutile pour un cache.

Vérifications (étapes 9-10), avec le compte d'administration (voir `valkey.md`) : `MODULE LIST` → `lua` ; `ACL LIST` → `user mediagenda on #<64 hex> …` (aucun mot de passe en clair) ; `CONFIG GET maxmemory*` → `100663296`, `allkeys-lru`. Avec `mediagenda` : `SET autre:x 1` → `NOPERM No permissions to access a key`, `FLUSHALL` → `NOPERM … 'flushall' command`. Sans mot de passe : `PING` → `NOAUTH Authentication required.` (utilisateur `default` désactivé). Depuis un pod de l'API, `rediss://mediagenda:…@valkey:6379/0` (nom court, absent du certificat) échoue (`certificate verify failed: Hostname mismatch`) : le client vérifie bien le nom.

*D.* Éviction, dans `valkey-0` de la recette (compte `admin` ; avec `valkey-benchmark`, `--user` exige `-a` : le mot de passe est visible par `ps` **dans le pod**, le temps de l'essai) :
```
valkey-benchmark --tls --cacert /etc/medisphere/racine/medisphere-root-ca.crt --user admin -a "$MDP" \
  -t set -n 150000 -d 1024 -r 1000000 -q
```
Clés aléatoires `key:000000xxxxxx` de 1 Kio : `INFO stats` → `evicted_keys` de l'ordre de plusieurs dizaines de milliers, `INFO memory` → `used_memory` plafonné juste sous `maxmemory` (relevé à la préparation : 68 299 clés évincées, `used_memory` 99,5 Mo pour `maxmemory` 100,7 Mo). Les clés `mediagenda:*` peu lues sont évincées aussi : un cache commun ne protège rien ; un essai de charge se fait dans une instance à part. Nettoyage sans `FLUSHALL` : `valkey-cli … --scan --pattern 'key:*' | xargs -n 500 valkey-cli … UNLINK`. Avec `noeviction` (le défaut) : les écritures sont **refusées** (`OOM command not allowed when used memory > 'maxmemory'`) et l'API passe en mode dégradé à chaque écriture du cache.

Certificat : `cmctl renew valkey-tls -n mediagenda-recette`, puis dans l'heure (`tls-auto-reload-interval 3600`) `tls_server_cert_serial` change, `uptime_in_seconds` ne retombe pas à 0. Prometheus : `redis_instance_info{valkey_version="9.1.2", maxmemory_policy="allkeys-lru"}` ; `redis_memory_used_bytes / redis_memory_max_bytes` (règle de plateforme d'E14) ; la règle d'équipe garde la mesure contre la limite du conteneur (ce que `maxmemory` ne protège pas).

**Explications**

Le cache est **borné** par `maxmemory` (Valkey évince) et **protégé** par la limite du conteneur (le noyau tue) : il faut une marge entre les deux (tampons des clients, fragmentation, et `fork` d'un `BGSAVE`). Les ACL au moindre privilège limitent les dégâts d'une fuite de l'URL de l'API (pas de `FLUSHALL`, pas d'autres clés). Le fichier ACL vient d'OpenBao sous forme d'**empreintes** : même le Secret Kubernetes `valkey-comptes` ne contient pas les mots de passe dans `users.acl` (il les contient pour la sonde et l'exportateur, qui doivent s'authentifier).

**Alternatives**

- Chart officiel `valkey-io/valkey-helm` (sous-chart du M17, désactivé depuis) : il gère ACL et TLS par valeurs ; un composant de plus à suivre, pour une configuration de 15 lignes.
- Opérateur (Valkey Operator, Dragonfly Operator) : utile pour des grappes et de la réplication ; surdimensionné pour un cache d'une instance.
- Mots de passe en clair dans le fichier ACL (`>motdepasse`) : fonctionne, mais le Secret contiendrait alors tous les mots de passe dans un même fichier lisible par quiconque peut monter ce Secret.

**Pièges classiques**

- Sonde `valkey-cli ping` sans vérifier la réponse : toujours « vraie » (`NOAUTH` rend 0).
- `--cacert` avec la CA **intermédiaire** (`ca.crt` du Secret de cert-manager) : `valkey-cli` exige une chaîne jusqu'à une racine ; d'où la racine MédiSphère.
- Garder `value` **et** `valueFrom` sur la même variable : Deployment refusé par l'API (d'où `value: null`).
- Composer l'annotation de Reloader du Rollout dans deux components dans le mauvais ordre : le dernier écrase.
- `maxmemory` égal à la limite du conteneur : `OOMKilled` avant toute éviction.
- Supprimer le PVC de la recette **avant** d'avoir vérifié la nouvelle instance : rien de grave pour un cache, mais l'habitude est mauvaise.

**En production chez MédiSphère**

Valkey reste un cache (PLAN, décision du bloc G). Montée de version : procédure de `valkey.md`, recette puis prod. Les comptes tournent par OpenBao (nouvelle version du secret → ESO → Reloader redémarre Valkey et l'API). M27-E22 casse une ACL, l'éviction et le certificat : tu as ici de quoi diagnostiquer.

---

### M27-E08 — MédiAgenda publie les notifications, MédiNotif en production

**Solution** (une solution parmi d'autres ; l'exercice est libre)

Dossier modèle : [`essais/dossier-e08.md`](fichiers/M27-E08/essais/dossier-e08.md) — MR dans l'ordre, décisions, panne simulée, preuves.

1. **Code** : [`notifications.patch`](fichiers/M27-E08/mediagenda-api/notifications.patch) ([`LISEZMOI`](fichiers/M27-E08/mediagenda-api/LISEZMOI.md), puis `uv add "pika>=1.4.4,<2"`). `PublieurAMQP` : une connexion par processus sous verrou, ouverte à la première publication ; `confirm_delivery()` + `mandatory=True` (`UnroutableError`, `NackError` = échec, sans nouvelle tentative) ; une seule reconnexion si la connexion a été perdue entre deux publications ; délais courts (connexion 2 s, courtier bloquant 5 s) ; message persistant, `message_id`, contexte de trace W3C dans les en-têtes ; compteur `mediagenda_notifications_total{resultat}` (séries à zéro au démarrage) ; journaux sans contact. `PublieurInactif` sans `MEDIAGENDA_AMQP_URL`. Dans `app.py` : publication **après** `depot.creer` (transaction validée), seulement si le canal ≠ `aucun` ; la réponse reste `201` quoi qu'il arrive.
2. **Déploiement de l'API** : [`components/notifications`](fichiers/M27-E08/mediagenda-deploiement/components/notifications/kustomization.yaml) (ExternalSecret `mediagenda-amqp`, NetworkPolicy `mediagenda-vers-rabbitmq`, variable), inclus en recette puis en prod ([extrait des overlays](fichiers/M27-E08/mediagenda-deploiement/overlays.extrait-E08.yaml)) ; la racine vient de `racine-medisphere` (E07).
3. **Plateforme** : [`topologie/medinotif-prod/`](fichiers/M27-E08/donnees/topologie/medinotif-prod/) et [`topologie/kustomization.yaml`](fichiers/M27-E08/donnees/topologie/kustomization.yaml) ; [`reseau.extrait-E08.yaml`](fichiers/M27-E08/donnees/rabbitmq/reseau.extrait-E08.yaml) (entrées depuis `medinotif-prod`, `mediagenda-prod`) ; [`eso-plateforme`](fichiers/M27-E08/secrets/politiques/eso-plateforme.hcl.extrait-M27-E08) et [`eso-espaces.tf`](fichiers/M27-E08/secrets/tofu/eso-espaces.tf.extrait) ; [`espaces/medinotif-prod/`](fichiers/M27-E08/k8s/espaces/medinotif-prod/) et [`isolement-medinotif-prod`](fichiers/M27-E08/k8s/composants/reseau/politiques/isolement-medinotif-prod.yaml) ; [ApplicationSet](fichiers/M27-E08/gitops/applications/medinotif.yaml) (élément `prod`, `auto: false`).
4. **MédiNotif en prod** : [`overlays/prod/`](fichiers/M27-E08/medinotif-deploiement/overlays/prod/kustomization.yaml) — deux réplicas, `topologySpreadConstraints` par nœud, `PodDisruptionBudget` `maxUnavailable: 1`, la même image (empreinte) que la recette. Secrets : `kv/medinotif/prod/amqp`, `kv/mediagenda/prod/amqp` (clés `utilisateur`, `mot_de_passe`, `url` ; utilisateurs `medinotif-prod`, `mediagenda-prod`).
5. **Preuves** : en recette, un `POST` avec `"rappel": {"canal": "sms", "contact": "+33600000042"}` → `notification publiée` (API) → `notification envoyée (simulation)` avec `+336******42` (MédiNotif) ; même chose en prod avec un rendez-vous d'essai supprimé ensuite. Documentation : [`messagerie-topologie.extrait-E08.md`](fichiers/M27-E08/medisphere/docs/donnees/messagerie-topologie.extrait-E08.md).

**Explications**

Le point dur n'est pas technique : c'est **le contrat** entre la base et le courtier. Publier après la validation garantit qu'on ne notifie que ce qui existe, et accepte de perdre une confirmation si le processus meurt entre les deux ou si RabbitMQ est injoignable — perte **comptée** quand elle est vue (échec de publication), **invisible** quand le processus meurt. L'*outbox* ferme ce trou (la demande est écrite dans la même transaction, un relais la publie ensuite, au moins une fois) ; elle coûte une table, un relais et un nettoyage : décision de l'ADR-0270 (E17). Côté consommateur, au moins une fois + idempotence (E17-E18).

**Alternatives**

- **Publication asynchrone** (file en mémoire + fil d'envoi) : la requête ne paie plus le délai d'un courtier injoignable, mais un arrêt perd ce qui est en mémoire.
- **aio-pika** (client asynchrone) : naturel avec FastAPI en `async` ; les routes de MédiAgenda sont synchrones, `pika` bloquant sous verrou suffit.
- **Publier depuis la base** (déclencheur + `LISTEN/NOTIFY` + relais) : variante d'*outbox*, à éviter derrière un *pooler* en mode transaction (`LISTEN` y est cassé, E02).

**Pièges classiques**

- Publier **avant** le `COMMIT` (ou dans la transaction) : notification d'un rendez-vous annulé par un conflit d'index unique.
- `/pret` qui dépend de RabbitMQ : une panne de messagerie coupe la prise de rendez-vous.
- Oublier `mandatory` : un message sans file est « confirmé » puis jeté.
- Partager une `BlockingConnection` entre fils sans verrou : erreurs de trame aléatoires sous charge.
- Copier l'overlay de recette en prod sans PDB ni deuxième réplica : un drainage arrête les notifications.
- Ouvrir le réseau d'un seul côté (NetworkPolicy de l'API **ou** CNP de la grappe) : délai de connexion, `AMQPConnectionError`.

**En production chez MédiSphère**

Alertes : `rate(mediagenda_notifications_total{resultat="echec"}[5m]) > 0` pendant 10 min (équipe MédiAgenda) ; file `notifications` sans consommateur et rebut qui grossit (plateforme, E14). M28 met MédiNotif à l'échelle sur la profondeur de la file (KEDA) ; M27-E23 rejoue un incident de notifications perdues.

---

### M27-E09 — Kafka avec Strimzi : KRaft, pools de nœuds, *topics* et utilisateurs

**Solution**

Capacité : relevé des requêtes par travailleur avant installation (introduction) ; ≈ 4,3 Gio demandés par l'essai (3 × 1 Gio + opérateur 384 Mio + opérateurs d'entité 2 × 256 Mio + Job de production). Si un nœud n'a pas 1,5 Gio réservables : arrêter les essais de `wb-essais`, ou réduire le pool à 1 Gio / `-Xmx` 256m — jamais les requêtes de la base ou de RabbitMQ.

Lecture : Strimzi 1.x ne sert que `kafka.strimzi.io/v1` (v1beta2 retirée en 1.0) ; un exemple en `v1beta2` est refusé à l'API (« no matches for kind … in version v1beta2 ») et un exemple converti à la main mais qui garde des champs anciens (`operation:` au singulier dans les ACL, `spec.kafka.replicas`) l'est aussi (validation stricte). `watchNamespaces: []` + `watchAnyNamespace: false` : l'opérateur ne surveille que son espace (`STRIMZI_NAMESPACE` = `metadata.namespace`). L'opérateur d'entité regroupe l'opérateur de *topics* (synchronise `KafkaTopic` → Kafka) et celui d'utilisateurs (`KafkaUser` → identifiants SCRAM, ACL, Secret).

Fichiers :
- [`charts-miroir/charts.extrait.yaml`](fichiers/M27-E09/charts-miroir/charts.extrait.yaml) (`sha256:42677cec73d2122f4a395d9891bbccfae18ec16b3582174d49ca04695f351192`) ;
- [`k8s/espaces/kafka-essai/00-espace.yaml`](fichiers/M27-E09/k8s/espaces/kafka-essai/00-espace.yaml) (sans étiquette d'équipe, `restricted`, quota avec stockage) ;
- [`gitops/valeurs/strimzi/values.yaml`](fichiers/M27-E09/gitops/valeurs/strimzi/values.yaml), [`gitops/plateforme/kafka-essai.yaml`](fichiers/M27-E09/gitops/plateforme/kafka-essai.yaml) (trois sources, `SkipDryRunOnMissingResource`), [`projets/plateforme.extrait-M27-E09.yaml`](fichiers/M27-E09/gitops/projets/plateforme.extrait-M27-E09.yaml) ;
- [`donnees/kafka-essai/`](fichiers/M27-E09/donnees/kafka-essai/) : [`kafka.yaml`](fichiers/M27-E09/donnees/kafka-essai/kafka.yaml) (4.3.1, `metadataVersion: 4.3-IV0`, écouteur `tls` 9093 SCRAM, `authorization: simple`, facteurs de réplication, `auto.create.topics.enable: false`), [`pool.yaml`](fichiers/M27-E09/donnees/kafka-essai/pool.yaml) (`double-role`, JBOD 10 Gio `kraftMetadata: shared`, `deleteClaim: false`, tas 384 Mio, anti-affinité), [`topics.yaml`](fichiers/M27-E09/donnees/kafka-essai/topics.yaml), [`utilisateurs.yaml`](fichiers/M27-E09/donnees/kafka-essai/utilisateurs.yaml) ;
- documentation [`kafka-essai.md`](fichiers/M27-E09/medisphere/docs/donnees/kafka-essai.md).

Constats (étapes 5-7) :
```
admin@adm01:~$ kubectl -n kafka-essai exec kafka-essai-double-role-0 -- /opt/kafka/bin/kafka-metadata-quorum.sh \
    --bootstrap-controller kafka-essai-double-role-0.kafka-essai-kafka-brokers.kafka-essai.svc:9090 describe --status
```
(le port des contrôleurs et le nom exact du Service sans tête sont à relever dans `kubectl -n kafka-essai get svc` et la configuration générée : le Secret ou la ConfigMap `kafka-essai-double-role-0` ; l'écouteur interne de réplication de Strimzi exige des certificats clients — l'outil se lance plus simplement **dans** le pod, avec la configuration que Strimzi y a écrite.) Le *leader* du quorum, l'époque, les *voters* (les trois nœuds). `kafka-topics.sh --describe` : leaders répartis, ISR `[0,1,2]` ; un pod supprimé → ISR à deux le temps de son retour, nouveau leader pour ses partitions. Deux nœuds indisponibles, `acks=all` : le producteur échoue (`NOT_ENOUGH_REPLICAS`) — la durabilité promise est tenue, au prix de la disponibilité en écriture.

**Explications**

KRaft remplace ZooKeeper par un quorum Raft **dans** Kafka ; avec trois nœuds aux deux rôles, le quorum tolère la perte d'un nœud. `min.insync.replicas` 2 + `acks=all` : une écriture confirmée est sur au moins deux disques. Le facteur 3 sur trois nœuds n'offre aucune marge de placement : un nœud en maintenance = toutes les partitions à deux répliques.

**Alternatives**

- **Deux pools** (contrôleurs légers séparés, courtiers) : recommandé en production, plus de pods.
- **Opérateur de grappe partagé** (`watchAnyNamespace`) : un seul opérateur pour plusieurs grappes ; plus de droits.
- **Certificat d'écouteur émis par la PKI de services** (`configuration.brokerCertChainAndKey`) au lieu de la CA de grappe de Strimzi : un seul magasin de confiance pour les clients (la racine MédiSphère).
- **Redpanda**, **AutoMQ** : compatibles avec le protocole Kafka ; licences et modèle à étudier.

**Pièges classiques**

- Exemples en `v1beta2` copiés d'anciens articles.
- `auto.create.topics.enable` laissé à `true` : une faute de frappe d'un client crée un *topic* à la configuration par défaut.
- Tas JVM égal à la limite du conteneur : `OOMKilled` (hors tas, cache de pages).
- Oublier l'opérateur d'entité : `KafkaTopic` et `KafkaUser` restent sans statut.
- `deleteClaim: true` « parce que c'est un essai », puis copié en production.

**En production chez MédiSphère**

Pas de Kafka en production (ADR-0270). S'il revenait : pools séparés, certificats de la PKI, exportateur et tableaux, rétention dimensionnée, procédure de montée (`metadataVersion` en dernier).

---

### M27-E10 — MédiNotif sur Kafka : *offsets*, rebut, comparaison, puis retrait

**Solution**

*A.* [`kafka.patch`](fichiers/M27-E10/medinotif-worker/kafka.patch) ([`LISEZMOI`](fichiers/M27-E10/medinotif-worker/LISEZMOI.md)). `enable.auto.commit: false` : aucun *commit* périodique en arrière-plan ; le *commit* est **synchrone**, message par message, après le résultat. `enable.auto.offset.store` (défaut `true`) range l'offset du dernier message rendu par `poll` pour le *commit* automatique : sans *commit* automatique, il n'a pas d'effet ici puisque `commit(message=…)` désigne explicitement l'offset. Rééquilibrage pendant un traitement : le *commit* échoue (journalisé), le nouveau propriétaire de la partition relit le message (doublon possible, pas de perte). Le traitement ne change pas : il rend un `Resultat`, la **source** le traduit (ack/nack pour RabbitMQ, commit/seek/rebut pour Kafka). La dépendance `confluent-kafka` embarque `librdkafka` (bibliothèque C) dans sa roue : elle apparaît dans le SBOM comme paquet Python ; ses vulnérabilités propres (C) ne sont pas toujours rattachées par les analyseurs — à lire dans le rapport de Trivy.

*B.* [`medinotif-kafka.yaml`](fichiers/M27-E10/donnees/kafka-essai/medinotif-kafka.yaml) dans [`kafka-essai/`](fichiers/M27-E10/donnees/kafka-essai/kustomization.yaml). Deux réplicas : 2 + 1 partitions ; quatre réplicas : trois actifs, un **inactif** (pas de partition). Production du lot : [`ressources/E09-kafka/`](../ressources/E09-kafka/) (`messages.py`, `produire.sh`, `produire-essai.yaml`). Décalage : `kafka-consumer-groups.sh --describe --group medinotif` (dans un pod courtier, avec une configuration cliente SCRAM — ou lire `kafka_consumergroup_lag` si l'exportateur de Strimzi est activé). Comparaison : [`comparatif-messagerie.md`](fichiers/M27-E10/medisphere/docs/donnees/comparatif-messagerie.md) (protocole, tableaux à remplir de tes mesures, comportements attendus, recommandation).

*C.* Plan de retrait : [`essais/retrait.md`](fichiers/M27-E10/essais/retrait.md) — *topics* et utilisateurs d'abord (finaliseurs de l'opérateur de *topics*), puis la grappe, puis les PVC (`deleteClaim: false`), puis l'Application (en cascade : opérateur, ClusterRoles, **CRD**), l'espace, l'entrée de `charts-miroir`, la destination de l'AppProject ; documentation (`kafka-essai.md` : « retrait effectif : <date> »). Backend du worker : retiré par une MR de *revert* (décision du comparatif).

**Explications**

Le même worker, le même traitement, deux sources : la comparaison porte sur le courtier. Avec 50 ms par envoi, les deux sont limités par le consommateur ; la différence est dans les **modes de défaillance** (message empoisonné qui bloque une partition, rebut par le courtier ou par l'application, ajout de consommateurs) et dans le **coût d'exploitation**. Le retrait fait partie de l'essai : un composant « temporaire » qu'on oublie devient permanent, sans propriétaire.

**Alternatives**

- **Kafka Streams / Connect** pour le rebut et les réessais (*topics* de réessai à délai) : plus de pièces.
- **RabbitMQ Streams** (flux à rétention dans RabbitMQ, relecture par offset) : si un jour un journal d'événements est nécessaire, à évaluer avant de réintroduire Kafka.
- Garder le backend Kafka **dormant** : coût faible, mais une dépendance native de plus à suivre dans chaque image.

**Pièges classiques**

- `enable.auto.commit` laissé à `true` : offset validé **avant** l'envoi → perte en cas de plantage.
- Valider l'offset du message (au lieu du suivant) avec l'API bas niveau : relecture du dernier message à chaque redémarrage (`commit(message=…)` fait le bon calcul).
- Copier vers le rebut sans attendre l'accusé (`flush`) puis valider : un message invalide peut disparaître.
- Plus de consommateurs que de partitions « pour aller plus vite ».
- Supprimer l'Application en premier : *topics* bloqués par leur finaliseur, PVC orphelins.

**En production chez MédiSphère**

Rien de Kafka ne reste. La question revient dans l'ADR-0270 avec ses critères de réouverture.

---

### M27-E11 — Revue : les manifestes de données du stagiaire

**Solution** (revue modèle)

| # | Fichier | Défaut | Pourquoi ici | Gravité | Admission | Correctif |
|---|---|---|---|---|---|---|
| 1 | `61-rappels-pooler.yaml` | `spec.cluster.name: mediagenda-db` | le *pooler* de Lucas vise la base de **MédiAgenda** ; avec `default_pool_size: 200` et `max_client_conn: 5000`, il peut épuiser `max_connections` de `mediagenda-db` (prod de la prise de rendez-vous en recette aujourd'hui, en prod demain) | **bloquant** (autre application) | accepté (CRD valide) | viser sa propre grappe, ou mieux : pas de *pooler* dédié (proposition) |
| 2 | `60-rappels-db.yaml` | `barmanObjectStore` vers `…/mediagenda-recette/mediagenda-db` avec les identifiants `mediagenda-db-s3` | archive WAL dans le **chemin de sauvegarde d'une autre base** ; CloudNativePG refuse d'archiver dans un dossier non vide (échec d'archivage → WAL qui s'accumulent → disque plein) ; au pire, mélange des sauvegardes de `mediagenda-db` | **bloquant** (autre application) | accepté | dossier propre ; et surtout… |
| 3 | `60-rappels-db.yaml` | `barmanObjectStore` (archivage **intégré**) | déprécié, **retiré en CloudNativePG 1.31** (note de version 1.30) ; MédiSphère utilise le **plugin Barman Cloud** depuis le M16 (`ObjectStore` + `spec.plugins`) | majeur | accepté (avertissement du webhook de l'opérateur) | plugin Barman Cloud, `ObjectStore` dédié |
| 4 | `60-rappels-db.yaml` | `postInitSQL: CREATE ROLE lucas LOGIN SUPERUSER PASSWORD 'Lucas2026!'` | mot de passe en clair dans Git, compte **superutilisateur** nominatif, permanent | **bloquant** (sécurité) | accepté | rôles par `managed.roles` sans privilège, identifiants dynamiques d'OpenBao (M25) ; accès temporaire comme `lucas_lecture` (E02) |
| 5 | `62-rabbitmq-rappels.yaml` | Secret avec `stringData` (`Lucas2026!`) | secret en clair dans Git (règle MédiSphère : OpenBao + ESO) ; même mot de passe que ci-dessus | **bloquant** (sécurité) | accepté | ExternalSecret depuis `kv/…` |
| 6 | `60-rappels-db.yaml` | `enableSuperuserAccess: true` | crée un Secret `rappels-db-superuser` exploitable par quiconque lit les Secrets de l'espace | majeur | accepté | `false` (défaut) |
| 7 | `60-rappels-db.yaml`, `62-…` | `imageName: ghcr.io/…:18` ; `image: bitnami/rabbitmq:4.1` | registre externe (le cluster ne tire **que** par Harbor : la VAP du M14 refuse les **pods**), étiquette mobile, pas d'empreinte (Kyverno en prod), **Bitnami interdit** (catalogue gratuit figé) | majeur | CR acceptées, **pods refusés** à la création (l'opérateur boucle en erreur) | images du cache Harbor, épinglées ; RabbitMQ officiel (`library/rabbitmq`) |
| 8 | `60-rappels-db.yaml` | `instances: 1` | aucune tolérance de panne ; contredit la règle « trois instances, synchrone » de MédiSphère pour une base de service | majeur | accepté | 3 instances… ou pas de base dédiée |
| 9 | `60-rappels-db.yaml` | `max_connections: 1000`, `shared_buffers: 2GB`, aucune ressource | sans `resources`, la `LimitRange` de l'espace (M14-E10) donne au conteneur 512 Mio de limite : `shared_buffers` de 2 Go ne tient pas, l'instance ne démarre pas ou est tuée (`OOMKilled`) — `exiger-limites` ne dit rien, les valeurs par défaut sont posées **avant** Kyverno ; 1000 connexions = mémoire non bornée | majeur | accepté (CR et pods), échec au démarrage | `resources` (requêtes = limites), paramètres dimensionnés (E16) |
| 10 | `60-rappels-db.yaml` | `monitoring.enablePodMonitor: true` | déprécié dans CloudNativePG 1.30 (« will be removed ») ; MédiSphère déclare ses `PodMonitor` (sélecteur `supervision: "oui"`) | mineur | accepté | `PodMonitor` explicite |
| 11 | `62-rabbitmq-rappels.yaml` | deuxième grappe RabbitMQ, 1 réplica, `service.type: LoadBalancer` | une grappe par application = double exploitation ; 1 nœud = file quorum impossible à répliquer ; `LoadBalancer` exposerait AMQP **en clair** hors du cluster (adresse LB IPAM annoncée en BGP) ; pas de TLS | **bloquant** | Service refusé par le quota `services.loadbalancers: "0"` de l'espace (M14-E10) — s'il a été relevé pour le Service `mediagenda-db-openbao` du M25, **accepté** : vérifie ton quota | vhost/file dans la grappe `messagerie/rabbitmq` |
| 12 | `63-topologie-rappels.yaml` | file `classic`, `durable: false`, `autoDelete: true` | les rappels disparaissent au redémarrage du nœud ou au départ du dernier consommateur ; pas de réplication | majeur | accepté (webhook : valide) | file **quorum** durable |
| 13 | `63-topologie-rappels.yaml` | `tags: [administrator]`, permission `.*/.*/.*` sur `/` | le compte de l'application administre toute la grappe | **bloquant** (sécurité) | accepté | aucun tag ; permissions minimales sur un vhost dédié (modèle `medinotif-<env>`) |
| 14 | tous | dans `plateforme/k8s/espaces/mediagenda-recette/` | objets **applicatifs** dans le dépôt de la plateforme, appliqués à la main (`task appliquer`), hors d'Argo CD | mineur | — | dépôt de l'application et Argo CD ; topologie dans `plateforme/donnees` |

Preuves à blanc (dans `wb-essais`, sans rien créer) : les trois CR passent l'API (validation de schéma) — c'est le piège : « accepté » ne veut pas dire « fonctionnera ». Le `LoadBalancer` est refusé par un quota `services.loadbalancers: "0"` (`exceeded quota … services.loadbalancers`), comme celui des espaces d'équipe depuis le M14 ; un **pod** construit avec l'image `bitnami/rabbitmq:4.1` est refusé par la VAP de registre du M14. (Dans `wb-essais`, vérifie quels contrôles s'appliquent : les politiques d'équipe de Kyverno visent les espaces étiquetés.)

Réponse à Lucas (extrait) : « Merci d'avoir tout isolé pour ne rien casser — l'intention est la bonne, et la base déclarée par CloudNativePG, les ressources nommées, c'est propre. Trois choses bloquent : ton *pooler* et ton archivage visent **notre** base `mediagenda-db` ; deux mots de passe sont dans Git ; le compte RabbitMQ est administrateur. Pour la suite, pas besoin d'une base ni d'une messagerie à toi : une table `rappels` dans la base de MédiAgenda (migration Flyway `V5__`, *expand* seulement), et une file quorum `rappels-veille` dans le vhost `medinotif-<env>`, déclarée dans `plateforme/donnees/topologie/` avec une liaison et une permission d'écriture pour `mediagenda-<env>`. Je te montre demain comment on écrit les deux. »

**Explications**

La revue la plus utile classe : ce qui met en danger **une autre** application ou les données d'abord, la sécurité ensuite, puis ce qui ne tiendra pas en production, puis le style. Et elle sépare « refusé à l'admission » (Lucas le verra tout de suite) de « accepté » (le danger silencieux : ici les n° 1, 2, 4, 9, 12, 13).

**Alternatives**

Automatiser une partie : Kyverno (images Bitnami, `enableSuperuserAccess`, `LoadBalancer` dans les espaces d'équipe, `barmanObjectStore`), conftest en CI (M29) sur les dépôts. Le n° 1 et le n° 2 (une référence vers l'objet d'une **autre** application) demandent une règle plus fine (référence à un `Cluster` qui ne porte pas l'étiquette de l'application) ou un humain.

**Pièges classiques**

- S'arrêter au premier défaut bloquant.
- « Ça marche sur minikube » : ni quota, ni Kyverno, ni VAP, ni base voisine.
- Un ton qui humilie : Lucas ne reviendra pas demander de relecture.

**En production chez MédiSphère**

Gabarit de MR « données » : base ou file nouvelle → justification, revue plateforme obligatoire, propriétaire (CODEOWNERS sur `topologie/` et `espaces/`).

---

### M27-E12 — Runbook : maintenance et bascule de PostgreSQL

**Solution**

[`RB-270-postgresql-maintenance-bascule.md`](fichiers/M27-E12/medisphere/docs/donnees/runbooks/RB-270-postgresql-maintenance-bascule.md) et, facultatif, [`RB-271-rabbitmq-redemarrage-roulement.md`](fichiers/M27-E12/medisphere/docs/donnees/runbooks/RB-271-rabbitmq-redemarrage-roulement.md). Structure : quand l'ouvrir, état en une minute (tableau « question → où regarder → bon signe »), procédures planifiées (bascule, drain, image, redémarrage) avec prérequis, bascule subie (ce que fait l'opérateur seul, **attendre** 2 minutes, quand escalader, promotion manuelle seulement vers la réplique la plus avancée), après la bascule, interdits, escalade, historique. Les durées sont **les tiennes** (E02) : le modèle garde `<N>`.

Faits qui fondent le runbook (documentation CloudNativePG 1.30) : *failover* automatique dès que le primaire est en échec (`failoverDelay` 0 par défaut) ; nœud injoignable : le primaire n'est vu « non prêt » qu'après 40 à 55 s (délai de Kubernetes), puis bascule ; un *switchover* volontaire arrête proprement l'ancien primaire (timeout `switchoverDelay`) ; un drain du nœud du primaire déclenche une bascule **avant** l'éviction.

**Explications**

Un runbook se lit sous stress : questions dans l'ordre où on se les pose, commandes copiables, décision explicite (« attendre 2 minutes », « au-delà de 5 minutes, escalader ») et **interdits** visibles. Tester à froid avec quelqu'un d'autre révèle ce qui manque (une variable non définie, une étape implicite).

**Alternatives**

Arbre de décision Mermaid en tête ; liens directs vers les tableaux Grafana préfiltrés ; runbook exécutable (Rundeck, scripts) — à éviter pour les gestes qui écrivent : l'humain doit décider.

**Pièges classiques**

- Commencer par « supprimer le pod du primaire » pour « débloquer » (c'est un *failover* forcé).
- Durées « de la documentation » au lieu des mesures du lab.
- Un runbook qui exige de savoir ce qu'est un *timeline* pour être suivi.

**En production chez MédiSphère**

`runbook_url` des alertes `Postgresql*` (E14) vers RB-270 ; revue du runbook après chaque usage réel (historique).
