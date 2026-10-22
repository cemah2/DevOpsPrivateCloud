# Module 22 — Palier 2 : Opérationnel

Les journaux arrivent ; il faut maintenant qu'ils servent. Ce palier traite les demandes du quotidien : exploiter les journaux **structurés** de MédiAgenda (un identifiant par requête, des sondes qui n'encombrent plus), faire entrer le **journal d'audit** de l'API et les événements du cluster, **alerter** sur ce que disent les journaux, garantir qu'aucune **donnée de santé** n'entre dans Loki, essayer un autre collecteur (**Fluent Bit**) pour pouvoir argumenter le choix d'Alloy, relire la configuration du stagiaire, et écrire le runbook de recherche de l'astreinte.

Prérequis : palier 1 terminé (`lab/bin/check 22 02` à `22 05` verts). Les exercices E06, E07 et E09 modifient tous `alloy/config.alloy` : fais-les dans l'ordre, une MR par exercice.

---

### M22-E06 — Des journaux structurés : MédiAgenda en JSON  `LAB` `★★★`

> **Ticket DEV-2306** — *De : Julien Petit* — *Copie : Karim Benali*
> Nos journaux sont en JSON depuis le premier jour, mais dans Loki on les lit comme du texte. Trois demandes. Un : pouvoir suivre **une** requête de bout en bout — on ajoute un `request_id` dans l'API, je vous laisse le ranger côté Loki, et je ne veux pas apprendre que ça a fait exploser vos flux. Deux : en dev on passe en `DEBUG` pour comprendre le cache, et là les sondes du kubelet (`/sante`, `/pret`) et la collecte de Prometheus noient tout ; je ne veux plus les voir, sans perdre le reste du DEBUG. Trois : l'heure d'une ligne doit être celle de l'application, pas celle de la collecte. Et faites pareil pour MédiDoc, qui écrit en `slog`.

**Objectifs pédagogiques**
- Décider ce qui devient étiquette, métadonnée structurée ou reste dans la ligne, et le justifier par la cardinalité.
- Traiter différemment les journaux d'une application (`stage.match`) : analyse JSON, filtrage, horodatage.
- Mesurer ce qu'un filtre écarte (métriques d'Alloy) plutôt que le supposer.
- Faire passer un changement applicatif par le chemin normal (MR, image, promotion GitOps).

**Prérequis** : M22-E03, M22-E04 ; M20 (promotion par MR dans `mediagenda/deploiement`, synchronisation de `mediagenda-dev`).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Format de MédiAgenda | `apps/mediagenda/src/mediagenda/journal.py` : une ligne JSON par événement, clés `horodatage` (ISO 8601, ms, UTC), `niveau` (`DEBUG`, `INFO`, `WARNING`, `ERROR`…), `journal`, `message`, puis les champs passés en `extra` ; les sondes `/sante`, `/pret` et `/metrics` sont journalisées en **DEBUG** (`ROUTES_SONDES` dans `app.py`) |
| Format de MédiDoc | `slog` JSON : `time`, `level`, `msg`, `route` (`GET /healthz`, `GET /readyz`, `GET /metrics` en DEBUG) |
| Conteneurs | MédiAgenda : conteneur `api` (espaces `mediagenda-dev`, `-recette`, `-prod`) ; MédiDoc : conteneur `medidoc` |
| Niveau de dev | ConfigMap `mediagenda` de `mediagenda-dev` (clé `MEDIAGENDA_LOG_LEVEL`), rendue par le chart (M17) ; modifiable **seulement** par l'overlay `dev` de `mediagenda/deploiement` |
| Identifiant de requête | en-tête `X-Request-ID` : repris s'il est sûr, sinon créé ; renvoyé dans la réponse ; présent sur **toutes** les lignes journalisées pendant la requête |
| Trafic | `ressources/E04-trafic/trafic.sh <URL-MEDIAGENDA-DEV>` ; sans nom publié pour dev : `kubectl --context k8s-par1 -n mediagenda-dev port-forward svc/mediagenda 18000:80` puis `http://127.0.0.1:18000` (lecture seule, autorisé) |

**Travail demandé**

*A. L'application*

1. Dans `mediagenda/api`, sur une branche : ajoute l'identifiant de requête (middleware de `app.py`, et un mécanisme qui le pose sur toutes les lignes journalisées pendant la requête, pas seulement sur la ligne d'accès). Une valeur reçue qui contient autre chose que des lettres, chiffres, `.`, `_`, `-`, ou qui fait plus de 64 caractères, est remplacée. Ajoute les tests. `uv run pytest`, `ruff`.
2. MR relue par Julien (compte `julien.petit`), fusion : la CI construit, signe et ouvre la MR de promotion dans `mediagenda/deploiement` (M19-M20). Fusionne-la pour `dev`.
3. Dans `mediagenda/deploiement`, overlay `dev` : passe MédiAgenda en `DEBUG`. Le chart rend une annotation `checksum/config` au rendu : un correctif kustomize de la ConfigMap redémarre-t-il les pods ? Fais en sorte qu'ils redémarrent **sans** commande manuelle sur l'espace. MR, synchronisation d'Argo CD.
4. Lance le trafic sur dev. Dans Explore (`Loki — mediagenda`) : les lignes de sonde arrivent-elles ? Combien par minute ? Retrouve, à partir de l'en-tête `X-Request-ID` d'une réponse (`curl -i`), toutes les lignes de cette requête.

*B. La collecte*

5. Décide, pour chaque champ (`niveau`, `request_id`, `route`, `code`, `journal`, `client`, `duree_ms`) : étiquette, métadonnée structurée, ou rien (reste dans la ligne). Écris la décision et sa justification chiffrée dans `~/m22/e06/journal.md` (nombre de flux du locataire avant et après, avec `logcli series --analyze-labels`).
6. Dans `alloy/config.alloy`, ajoute un traitement réservé aux journaux de l'API de MédiAgenda : analyse JSON, écart des sondes, horodatage tiré de `horodatage`, métadonnées structurées selon ta décision. Puis un traitement pour MédiDoc. MR (la CI valide), synchronisation : le config-reloader recharge-t-il Alloy sans redémarrer les pods ?
7. Ajoute `niveau` aux champs où Loki cherche le niveau d'une ligne (limite `log_level_fields` de `loki/values.yaml`) : à quoi cela sert-il dans Grafana (« Logs Drilldown », colonne de niveau) ?
8. Prouve que les sondes sont **écartées par Alloy** et non simplement absentes : dans Prometheus, la métrique d'Alloy des lignes écartées, par raison.
9. Vérifie l'horodatage : pour une ligne, compare le temps de l'entrée Loki et le champ `horodatage`.
10. Lis les étiquettes indexées du locataire `mediagenda`, puis filtre `{namespace="mediagenda-dev", container="api"} | request_id="…"` : quelle différence avec `|= "…"` ?

**Critères de réussite**
- [ ] `mediagenda/api` (main) pose un `request_id` sur chaque ligne d'une requête et le renvoie dans `X-Request-ID` ; les tests passent.
- [ ] `mediagenda-dev` journalise en `DEBUG` (par l'overlay `dev`), `mediagenda-recette` en `INFO`.
- [ ] Dans Loki : `request_id` et `niveau` sont des métadonnées structurées, aucun n'est une étiquette indexée ; aucune ligne de sonde n'arrive, et le compteur d'Alloy montre qu'elles ont été écartées.
- [ ] L'horodatage des lignes de MédiAgenda est celui de l'application.
- [ ] `log_level_fields` de Loki contient `niveau`.

**Vérification** : `lab/bin/check 22 06` (après 10 minutes de trafic sur dev)

<details><summary>Indice 1</summary>

Côté Python, une variable de contexte (`contextvars`) suit une requête, y compris dans le fil d'exécution des points d'entrée synchrones de FastAPI ; un `logging.Filter` posé sur les journaux de l'application peut y lire l'identifiant et l'ajouter à chaque enregistrement. Le formateur JSON du projet écrit déjà tout attribut « extra ».
</details>

<details><summary>Indice 2</summary>

`stage.match` applique un sous-pipeline aux seules entrées dont les étiquettes correspondent à un sélecteur LogQL. Dedans : `stage.json` (extraction), `stage.drop` (avec `source` et `expression`, et un `drop_counter_reason` qui nommera la raison dans la métrique), `stage.timestamp`, `stage.structured_metadata`.
</details>

<details><summary>Indice 3</summary>

Pour faire redémarrer les pods par GitOps, il faut que le **gabarit de pod** change : une annotation du gabarit posée par un second correctif de l'overlay suffit. `kubectl rollout restart` écrirait hors de Git dans un espace applicatif, et Argo CD y verrait une dérive.
</details>

**Pour aller plus loin** (facultatif) : propage le `request_id` vers les appels sortants (PostgreSQL : `application_name` ou commentaire SQL ; Valkey : nom de client) ; c'est ce que le `trace_id` du M23 généralisera.

---

### M22-E07 — Journal d'audit de l'API et événements Kubernetes  `LAB` `★★★`

> **Ticket SEC-2307** — *De : Sophie Laurent*
> L'auditeur HDS veut la preuve de « qui a fait quoi » sur la plateforme, six mois en arrière. Le journal d'audit existe depuis le M14, mais il est dans des fichiers tournants sur trois nœuds, compressés au bout de 100 Mo : autant dire introuvable. Je le veux dans Loki, dans un **locataire à part** que les équipes ne lisent pas, avec de quoi filtrer sans tout analyser : le verbe, l'utilisateur, l'objet, le code de retour. Profites-en pour les **événements** du cluster : on les perd au bout d'une heure. Démonstration attendue : « qui a supprimé cette ConfigMap ? » en moins d'une minute.

**Objectifs pédagogiques**
- Collecter un fichier sur certains nœuds seulement (nœuds de contrôle) et l'envoyer dans un locataire dédié.
- Extraire des champs imbriqués d'une ligne JSON vers des métadonnées structurées.
- Collecter une source unique (événements de l'API) depuis un DaemonSet sans doublons.
- Mener une enquête d'audit avec LogQL.

**Prérequis** : M22-E06 ; M14-E27 (politique et fichiers d'audit).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Fichiers d'audit | `/var/log/kubernetes/audit/audit.log` sur `k8s-cp01-03` (JSON, une ligne par événement, étape `ResponseComplete`) ; rotations compressées `audit-<date>.log.gz` (`audit-log-compress`) |
| Champs utiles | `requestReceivedTimestamp`, `verb`, `user.username`, `objectRef.resource`, `objectRef.namespace`, `objectRef.name`, `responseStatus.code`, `sourceIPs` |
| Locataire | `audit` ; étiquettes `cluster`, `job="kubernetes-audit"`, `node` ; métadonnées structurées `verb`, `user`, `code`, `resource`, `object_ns`, `object_name` |
| Événements | `loki.source.kubernetes_events`, `job="kubernetes-events"`, locataire d'après l'espace de l'objet (même règle que les pods) |
| Ingestion | Loki refuse les entrées de plus de 7 jours (`reject_old_samples_max_age`) ; limite d'ingestion par défaut 4 Mo/s par locataire |

**Travail demandé**

1. Sur `k8s-cp01`, regarde le journal d'audit : taille, nombre de lignes par minute, rotations. Combien de jours d'historique contient-il ? Que se passerait-il si Alloy le lisait depuis le début au premier démarrage ?
2. Dans `alloy/config.alloy`, ajoute la lecture du journal d'audit : cible statique (le fichier n'existe que sur le plan de contrôle : qu'arrive-t-il sur un travailleur ?), départ de la fin du fichier au premier démarrage, analyse JSON des champs imbriqués, horodatage de la requête, métadonnées structurées, locataire `audit`, étiquettes de la liste seulement.
3. Ajoute les événements Kubernetes. Six pods Alloy les liraient tous : active le **clustering** d'Alloy (valeurs du chart et bloc du composant) pour qu'un seul les lise. Donne à Alloy le droit de lire les événements — et toujours pas les Secrets. Retire l'étiquette `instance` ; applique la règle des locataires.
4. MR (CI), synchronisation. Vérifie : un flux d'audit par nœud de contrôle ; l'interface d'Alloy d'un pod montre les membres de la grappe.
5. L'enquête, en direct :
   - crée la ConfigMap `m22-e07-temoin` dans `wb-essais`, modifie-la, supprime-la (ton identité, `kubectl`) ;
   - dans `Loki — audit`, retrouve **qui** l'a supprimée, **quand** et **d'où** (adresse source), en une requête ; puis toute l'histoire de l'objet (création, modifications, suppression) ;
   - chronomètre-toi.
6. Supprime un pod de `wb-essais` : retrouve ses événements dans `Loki — plateforme`. Ceux d'un espace `mediagenda-*` sont-ils dans `Loki — plateforme` ? Pourquoi est-ce voulu ?
7. Requêtes d'audit utiles (range-les dans `requetes/E07.logql`, même format qu'en E04) : les dix utilisateurs les plus actifs en écriture sur 24 h ; les accès `exec` aux pods ; les refus (403) par utilisateur ; les lectures de Secrets par des humains.
8. Lis `politique.yaml` de l'audit (M14-E27) : les lectures de Secrets par les kubelets ne sont pas auditées, les corps des Secrets jamais. Pourquoi est-ce cohérent avec un stockage de l'audit dans Loki ?

**Critères de réussite**
- [ ] Le locataire `audit` reçoit le journal des trois nœuds de contrôle (et d'aucun travailleur), avec `verb`, `user`, `code`, `resource`, `object_ns`, `object_name` en métadonnées structurées ; seules `cluster`, `job` et `node` sont indexées ; rien de l'audit dans `plateforme`.
- [ ] La suppression de `wb-essais/configmaps/m22-e07-temoin` se retrouve avec ton nom d'utilisateur.
- [ ] Les événements arrivent (`job="kubernetes-events"`), ceux des espaces `mediagenda-*` dans le locataire `mediagenda`, sans étiquette `instance`, lus par un seul pod (clustering actif).
- [ ] Alloy peut lire les événements, pas les Secrets.

**Vérification** : `lab/bin/check 22 07`

<details><summary>Indice 1</summary>

`local.file_match` accepte une liste de cibles statiques (`path_targets`), chacune avec `__path__` et des étiquettes. `loki.source.file` a un argument pour partir de la fin quand aucune position n'est enregistrée. `stage.json` accepte des expressions JMESPath (`user.username`).
</details>

<details><summary>Indice 2</summary>

Le clustering d'Alloy se déclare à deux endroits : dans le chart (les pods forment une grappe) et dans **chaque** composant qui doit se répartir le travail (bloc `clustering`). Un composant sans ce bloc continue de tout faire sur chaque pod.
</details>

**Pour aller plus loin** (facultatif) : l'audit de Grafana, d'Argo CD et de GitLab (les trois autres endroits où un humain change la plateforme) : où sont leurs journaux d'audit, et lesquels pourraient rejoindre le locataire `audit` ?

---

### M22-E08 — Alerter sur les journaux  `LAB` `★★★`

> **Ticket PLAT-2308** — *De : Nadia Roussel* — *Copie : Sophie Laurent, Julien Petit*
> Certaines choses ne se voient que dans les journaux. Je veux trois alertes, routées comme les autres par l'Alertmanager du M21 : une **rafale d'erreurs 5xx** de MédiAgenda (pour l'équipe de Julien), des **échecs d'authentification** en série sur l'API Kubernetes (pour nous et Sophie), et une alerte si **plus aucun journal** n'arrive — la collecte qui tombe en silence, c'est la pire des pannes. Chaque alerte avec sa gravité, son équipe et un lien vers le runbook. Et je veux la preuve qu'une alerte arrive vraiment dans une boîte aux lettres.

**Objectifs pédagogiques**
- Activer et configurer le *ruler* de Loki (stockage des règles, Alertmanager, API).
- Écrire des règles d'alerte en LogQL, par locataire, avec les conventions d'étiquettes du M21.
- Gérer les règles comme du code (ConfigMaps générées, chargées par le conteneur *sidecar*) avec des droits minimaux.
- Tester une alerte de bout en bout jusqu'à Mailpit.

**Prérequis** : M22-E07 ; M21-E06 et E16 (Alertmanager, routage par `equipe`, Mailpit).
**Durée indicative** : 2 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Ruler | dans le binaire Loki (monolithique) ; règles lues dans `/rules/<locataire>/` (stockage `local`) ; le conteneur `sidecar` du chart (k8s-sidecar) recopie les ConfigMaps étiquetées `loki_rule` |
| Alertmanager | `http://kps-alertmanager.supervision.svc.cluster.local:9093` (Service de kube-prometheus-stack, `fullnameOverride: kps`, M21) |
| Règles | `plateforme/observabilite`, `loki/regles/<locataire>/alertes.yaml` (format des règles Prometheus, expressions LogQL) |
| Étiquettes d'alerte | `gravite` (`critique`, `avertissement`, `info`), `equipe` (`plateforme`, `mediagenda`, `medidoc`) ; annotations `resume`, `description`, `runbook_url` (M21) |
| API du ruler | `GET /prometheus/api/v1/rules` et `/prometheus/api/v1/alerts` avec l'en-tête du locataire |
| Noms des alertes | `MediagendaErreurs5xxRafale` (locataire `mediagenda`), `AuditEchecsAuthentification` (`audit`), `CollecteJournauxArretee` (`plateforme`) |

**Travail demandé**

1. Lis la section `ruler` de la référence de configuration de Loki et les valeurs `ruler`, `loki.rulerConfig`, `sidecar.rules` et `rbac` du chart. Quel droit le *sidecar* reçoit-il par défaut, et sur quel périmètre ? Qu'en dirait Sophie ?
2. Dans `loki/values.yaml` : active le ruler (stockage local `/rules`, dossier de travail sur le PVC, Alertmanager du cluster, API), active le *sidecar* en ne surveillant que les ConfigMaps, et réduis ses droits à l'espace `journaux`. Rends le chart : que contient la section `ruler` de la configuration ? Combien de pods de plus ?
3. Écris les trois règles (une par locataire) ; donne à chacune une durée (`for`) justifiée, `gravite`, `equipe`, `resume`, `description` (avec la requête d'enquête), `runbook_url` (le RB-220 que tu écriras en E12).
4. Dans `loki/kustomization.yaml`, génère une ConfigMap par locataire, étiquetée pour le *sidecar*, avec l'annotation qui la range dans `/rules/<locataire>`. Si l'entrée d'Alertmanager est filtrée par une CNP (M21-E29), ouvre-la au ruler.
5. MR, synchronisation. Vérifie avec l'API du ruler (locataire par locataire) : règles chargées, `health: ok`. La règle d'audit apparaît-elle dans le locataire `mediagenda` ? Pourquoi ?
6. Essai : provoque plus de 20 échecs d'authentification en 5 minutes sur l'API (`kubectl` avec un jeton faux, en boucle, depuis `adm01`). Suis l'alerte : `pending`/`firing` dans l'API du ruler, puis dans Alertmanager (`amtool alert query`), puis le courriel dans Mailpit. Combien de temps entre la première requête refusée et le courriel ? D'où viennent ces délais ?
7. Que se passe-t-il pour `CollecteJournauxArretee` si **Loki** lui-même est arrêté ? Qui alerte alors ? (Relis les alertes du M21 sur les cibles disparues.)

**Critères de réussite**
- [ ] Le ruler envoie à l'Alertmanager du cluster ; les règles sont des ConfigMaps générées depuis `loki/regles/` (Git), chargées par le *sidecar*, sans ClusterRole.
- [ ] `MediagendaErreurs5xxRafale` (locataire `mediagenda`, `equipe: mediagenda`) et `AuditEchecsAuthentification` (locataire `audit`, `equipe: plateforme`) sont chargées et saines ; chaque règle d'alerte a `gravite`, `equipe` et `runbook_url`.
- [ ] La règle d'audit n'est chargée que dans le locataire `audit`.
- [ ] L'alerte de test `AuditEchecsAuthentification` est arrivée par courriel dans Mailpit.

**Vérification** : `lab/bin/check 22 08`

<details><summary>Indice 1</summary>

En mode monolithique, `ruler.enabled` ne crée pas de pod : il fait écrire la section `ruler` de la configuration, et le binaire unique démarre son ruler. Sans stockage de règles configuré, Loki écrit « Ruler storage is not configured; ruler will not be started ».
</details>

<details><summary>Indice 2</summary>

Le *sidecar* écrit chaque ConfigMap dans le dossier donné par une annotation (`k8s-sidecar-target-directory`) ; pour le ruler, le premier niveau sous le dossier des règles est le **locataire**. `configMapGenerator` de kustomize sait poser étiquettes et annotations (`options`).
</details>

<details><summary>Indice 3</summary>

Une requête refusée (401) par le serveur d'API est auditée avec `responseStatus.code` = 401, ce qui en fait une métadonnée structurée `code="401"` filtrable sans analyse. Un jeton faux s'écrit dans un kubeconfig jetable, pas en argument de commande.
</details>

**Pour aller plus loin** (facultatif) : écris une **règle d'enregistrement** (`record`) qui calcule chaque minute le taux de 5xx de MédiAgenda tiré des journaux, et envoie-la à Prometheus (`remote_write` du ruler) : à quoi cela servirait-il, et pourquoi n'est-ce pas activé ici (relis la note du M21 sur `enableRemoteWriteReceiver`) ?

---

### M22-E09 — Données de santé dans les journaux : filtrer et masquer  `LIBRE` `★★★`

> **Ticket SEC-2309** — *De : Sophie Laurent* — *Copie : Claire Morel, Julien Petit*
> Hier, dans une trace d'exception d'un prestataire, j'ai vu un NIR et une adresse de courriel de patiente. Chez nous, les applications sont propres — pour l'instant. Je veux une garantie : **aucune donnée personnelle de patient ne doit entrer dans Loki**, d'où qu'elle vienne, pods, nœuds ou VMs. Et je veux pouvoir le **prouver** à l'auditeur, avec un témoin qui écrit de fausses données en continu. Attention : les adresses de service de MédiSphère (`astreinte@`, `plateforme@`…) doivent rester lisibles, on en a besoin pour enquêter sur les notifications. Écris la règle dans une politique des journaux.

**Objectifs pédagogiques**
- Concevoir une défense en profondeur contre les fuites de données personnelles dans les journaux.
- Masquer à la collecte, pour toutes les sources, sans détruire l'information utile.
- Prouver l'efficacité d'un contrôle par un témoin et par une recherche systématique.

**Prérequis** : M22-E05, M22-E07.
**Durée indicative** : 2 h.

**Contexte technique**
- Témoin fourni : `ressources/E09-temoin/temoin.yaml` (Deployment `temoin-donnees`, espace `wb-essais`, image busybox par le cache Harbor) ; toutes les 15 s, une ligne JSON (nom de patient, NIR avec espaces, courriel externe, adresse `astreinte@medisphere.internal`, horodatage en nanosecondes) et une ligne de texte (courriel externe, NIR sans espaces, `plateforme@par1.medisphere.internal`). Valeurs **factices**.
- NIR : 13 chiffres et une clé de 2 chiffres (sexe, année, mois, département — dont 2A et 2B —, commune, ordre), souvent écrit avec des espaces.
- Locataires : `plateforme`, `mediagenda`, `medidoc`, `audit`.

**Travail demandé**

Garantis, et démontre, qu'aucune donnée personnelle de patient ne peut entrer dans Loki :
- quelle que soit la source collectée par la plateforme : pods, journald des nœuds, journal d'audit, événements, **et** VMs du socle ;
- sans masquer les adresses de courriel de MédiSphère, ni les horodatages, ni les identifiants techniques ;
- de façon vérifiable par l'équipe Plateforme à tout moment, et par l'auditeur ;
- en écrivant la règle (ce qui est interdit, ce qui est masqué et par quoi, ce qui n'est pas couvert, que faire si une donnée est trouvée) dans `docs/observabilite/journaux/politique-journaux.md` (section 1 ; les rétentions et l'effacement viendront en section 2 avec E13, les accès et la sauvegarde en sections 3 et 4 avec E16).

Contraintes :
- tout passe par le code (`plateforme/observabilite`, `plateforme/ansible`) et la CI ;
- aucune donnée réelle, même pour un essai ;
- les lignes du témoin doivent continuer d'arriver (masquées) : un filtre qui jette les lignes entières n'est pas une réponse acceptable.

**Critères de réussite**
- [ ] Le témoin tourne dans `wb-essais` ; ses lignes arrivent dans Loki avec le NIR (deux formes), le nom du patient et les courriels externes remplacés, et les adresses MédiSphère et l'horodatage en nanosecondes intacts.
- [ ] Sur la dernière heure, aucune ligne ressemblant à un NIR ou à une adresse de courriel externe dans aucun des quatre locataires.
- [ ] Le masquage est dans la configuration d'Alloy du cluster **et** dans celle des VMs (rôle `alloy`), sur `main`.
- [ ] `politique-journaux.md` est sur `main` de `plateforme/medisphere`, avec la règle des données de santé.

**Vérification** : `lab/bin/check 22 09` (la recherche des motifs couvre la dernière heure : les lignes du témoin arrivées **avant** le masquage la font échouer pendant une heure, ce qui prouve qu'elle sait passer au rouge)

<details><summary>Indice 1</summary>

Le meilleur endroit pour une étape commune à toutes les sources est un composant `loki.process` à part, par lequel elles passent toutes juste avant l'écriture. Sur les VMs, le gabarit Jinja du rôle contient la même étape : attention, Jinja et les gabarits d'Alloy utilisent tous deux les doubles accolades.
</details>

<details><summary>Indice 2</summary>

`stage.replace` remplace chaque groupe **capturant** de l'expression ; `(?:…)` ne capture pas. Son `replace` accepte des gabarits Go (`{{ .Value }}`, `regexReplaceAll`, `if`/`eq`) : de quoi garder une valeur qui se termine par `medisphere.internal`. Pense aux bornes de mots pour ne pas couper un nombre plus long.
</details>

<details><summary>Indice 3</summary>

Pour la preuve : une recherche LogQL par locataire, sur `{job=~".+"}` (toutes nos sources ont un `job`), avec le même motif que le masquage ; la recherche doit pouvoir passer au rouge (pousse une ligne non masquée dans le locataire `essai` pour vérifier que ta requête la trouve).
</details>

**Pour aller plus loin** (facultatif) : `loki.secretfilter` d'Alloy masque les secrets (jetons, clés) reconnus par les règles de Gitleaks : quels secrets pourraient fuir dans nos journaux, et à quel prix l'activer ?

---

### M22-E10 — Fluent Bit : un autre collecteur  `LAB` `★★`

> **Ticket PLAT-2310** — *De : Claire Morel*
> Avant d'écrire l'ADR, je veux qu'on ait essayé autre chose qu'Alloy. Fluent Bit est le collecteur le plus répandu, réputé très léger. Installe-le **à côté**, sur un périmètre réduit, vers un locataire d'essai ; mesure ; écris une comparaison honnête — ressources, configuration, fonctionnalités, ce qui nous manquerait. Puis retire **tout**. Une après-midi, pas plus.

**Objectifs pédagogiques**
- Configurer Fluent Bit sur Kubernetes (entrée `tail` au format CRI, filtre `kubernetes`, sortie Loki).
- Comparer deux collecteurs sur la même charge, avec des mesures.
- Mener un essai temporaire par GitOps et le retirer proprement.

**Prérequis** : M22-E06.
**Durée indicative** : 1 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Chart | `fluent/fluent-bit` **0.58.3** (Fluent Bit 5.1.3), dépôt `https://fluent.github.io/helm-charts`, recopié dans Harbor ; image `fluent/fluent-bit:5.1.3` de Docker Hub (par le cache Harbor ; `cr.fluentbit.io` n'a pas de cache) |
| Application | `fluent-bit-essai`, projet `plateforme`, espace **`journaux-essai`** (créé par Argo CD, Pod Security `privileged` appliqué), retirée à la fin |
| Périmètre | fichiers `/var/log/containers/*_mediagenda-recette_*.log` et `*_journaux_*.log` |
| Destination | Loki dans le cluster, locataire **`essai`**, `job="fluent-bit"`, mêmes autres étiquettes qu'Alloy |
| Livrable | `docs/observabilite/journaux/comparatif-collecteurs.md` (plateforme/medisphere) |

**Travail demandé**

1. Recopie le chart, lis ses valeurs : la configuration par défaut est-elle adaptée à containerd ? que monte-t-elle du nœud ? vers quoi envoie-t-elle ?
2. Écris les valeurs de l'essai (`fluent-bit-essai/values.yaml` de `plateforme/observabilite`) : périmètre réduit, analyse CRI, base des positions sur le nœud, filtre `kubernetes`, sortie Loki (locataire, étiquettes, nom du pod en métadonnée structurée, ligne d'origine sans enveloppe JSON), ressources, tolérances, contexte de sécurité, ServiceMonitor.
3. Ouvre temporairement la CNP `loki-entree` aux pods de `journaux-essai`. Écris l'Application (avec ce qu'il faut pour que son retrait supprime ses objets). MR, synchronisation.
4. Lance le trafic (`trafic.sh`, 20 min au moins), et pendant 2 heures, mesure pour les deux collecteurs : mémoire, CPU, lignes envoyées pour les mêmes pods (locataires `mediagenda` et `essai`).
5. Compare la configuration : découverte, étiquettes, locataire par entrée, masquage, rechargement, sources possibles (audit, événements, OTLP). Essaie de reproduire avec Fluent Bit **une** règle d'Alloy de ton choix (par exemple la valeur de repli de l'étiquette `app`, ou le locataire par espace) : combien de lignes, quel mécanisme ?
6. Écris le comparatif : versions, méthode de mesure, tableau des ressources, tableau de configuration, ce qui a été constaté, **décision** argumentée.
7. Retire l'essai : l'Application, l'espace `journaux-essai`, la règle temporaire de la CNP, le chart du miroir. Vérifie qu'il ne reste rien (ClusterRoles, espace, pods). Que deviennent les lignes du locataire `essai` ?

**Critères de réussite**
- [ ] Loki a reçu des journaux de Fluent Bit dans le locataire `essai` (`job="fluent-bit"`).
- [ ] `comparatif-collecteurs.md` est sur `main` : versions, mesures chiffrées (mémoire, CPU), une décision argumentée.
- [ ] L'essai est entièrement retiré : plus d'espace `journaux-essai`, plus d'Application `fluent-bit-essai`, plus de ClusterRole de Fluent Bit, plus de règle pour `journaux-essai` dans `loki-entree`, plus de chart `fluent-bit` dans le miroir.

**Vérification** : `lab/bin/check 22 10` (à la fin, une fois l'essai retiré)

<details><summary>Indice 1</summary>

La sortie `loki` de Fluent Bit accepte des étiquettes calculées à partir de l'enregistrement (accesseurs `$kubernetes['…']`), des métadonnées structurées, `remove_keys` et `drop_single_key`. Sans les deux derniers, la ligne envoyée est un objet JSON qui contient la ligne d'origine.
</details>

<details><summary>Indice 2</summary>

Une Application qui doit emporter ses objets quand on la retire porte le finaliseur `resources-finalizer.argocd.argoproj.io`. Un espace créé par `CreateNamespace=true` n'est **pas** supprimé avec l'Application.
</details>

**Pour aller plus loin** (facultatif) : refais la mesure avec Vector (0.60), troisième collecteur courant (Rust) : où se placerait-il ?

---

### M22-E11 — Revue : la configuration Alloy du stagiaire  `REV` `★★`

> **Ticket PLAT-2311** — *De : Karim Benali*
> Lucas a ouvert la MR !41 sur `plateforme/observabilite` : une « config simplifiée » de l'agent, qui récupère « tout ». Elle passe `alloy validate`, il est très content. Fais-lui une vraie revue — sécurité, coût, fonctionnement, exploitation —, du plus grave au moins grave, et pousse une version corrigée sur une branche `revue-lucas` pour qu'il voie la différence. Sois exigeant et pédagogue : il refera la même chose pour les traces au M23.

**Objectifs pédagogiques**
- Relire une configuration de collecte avec une grille : sécurité, données personnelles, cardinalité, fiabilité, exploitation.
- Distinguer ce qu'un outil de validation vérifie de ce qu'il ne peut pas vérifier.
- Rédiger une revue utile (impact concret, correction précise) et une version corrigée.

**Prérequis** : M22-E03 à M22-E09.
**Durée indicative** : 1 h.

**Contexte technique**
- Fichiers : `ressources/E11-alloy-lucas/` (`MR-lucas.md`, `config.alloy`, `values.yaml`). Le mot de passe qu'ils contiennent est **fictif**.
- Les deux fichiers sont syntaxiquement valides (`alloy validate` passe).

**Travail demandé**

1. Lis la MR et les deux fichiers sans rien exécuter. Pour chaque bloc, demande-toi : que ferait-il sur `k8s-par1`, avec notre Loki, nos locataires, notre politique ?
2. Rédige la revue en tableau dans `alloy/revue-lucas/REVUE.md` : n°, fichier et élément, défaut, catégorie (sécurité, conformité, performance, fonctionnel, exploitation, coût), gravité (critique, élevée, moyenne, faible), ce qui se passerait concrètement chez nous, correction. **Au moins 10 défauts**, classés du plus grave au moins grave.
3. Écris la version corrigée dans `alloy/revue-lucas/config.alloy` et `alloy/revue-lucas/values.yaml`, et fais-la passer par la CI (`alloy fmt --test`, `alloy validate`).
4. Pousse sur la branche `revue-lucas` de `plateforme/observabilite` (sans fusionner dans `main` : la configuration de référence reste `alloy/config.alloy`).
5. Termine la revue par trois lignes pour Lucas : ce qu'il a bien fait, ce qu'il doit lire avant la prochaine fois.

**Critères de réussite**
- [ ] La revue compte au moins 10 défauts, dont tous les défauts critiques et élevés du corrigé, chacun avec un impact concret et une correction précise.
- [ ] La version corrigée (branche `revue-lucas`) ne contient plus aucun des défauts objectivables : recopie des étiquettes, mot de passe, adresse IP en dur, mauvais format de journal, découverte de tout le cluster, absence de locataire, étiquettes à forte cardinalité, journald non borné, sondes et données personnelles non traitées, événements en double, positions dans `/tmp`, image `latest`, absence de limites et de tolérances, configuration hors Git.

**Vérification** : `lab/bin/check 22 11`

<details><summary>Indice 1</summary>

`alloy validate` charge la configuration et vérifie les noms de composants, les attributs et leurs types. Il ne connaît ni la configuration de Loki (multi-locataire ?), ni le format réel des fichiers, ni la politique de l'équipe, ni la charge que produira chaque étiquette.
</details>

<details><summary>Indice 2</summary>

Relis la configuration ligne par ligne avec ces questions : combien de flux cela crée-t-il ? que se passe-t-il au redémarrage du pod ? au premier démarrage ? si six pods font la même chose ? si Loki refuse ? qu'est-ce qui finit dans Git ?
</details>

---

### M22-E12 — Runbook : chercher dans les journaux pendant un incident  `RED` `★★`

> **Ticket PLAT-2312** — *De : Nadia Roussel*
> Toutes vos alertes de journaux pointent vers « RB-220 », qui n'existe pas encore. Je veux une page que l'astreinte peut suivre à 3 h du matin sans connaître LogQL par cœur : où chercher, dans quel locataire, les dix requêtes qui servent vraiment, qui a le droit de lire quoi, et les pièges qui font perdre une heure. Courte, testée, en français.

**Objectifs pédagogiques**
- Transformer les connaissances du module en une procédure utilisable sous pression.
- Choisir les requêtes types d'après les incidents réels et les vérifier.
- Écrire les limites (droits, rétention, masquage) pour éviter les fausses conclusions.

**Prérequis** : M22-E04, M22-E06, M22-E07, M22-E08.
**Durée indicative** : 1 h.

**Travail demandé**

Écris `docs/observabilite/journaux/runbooks/RB-220-chercher-dans-les-journaux.md` (plateforme/medisphere) :
1. **En 30 secondes** : comment choisir le locataire, la fenêtre de temps et le sélecteur.
2. **Préparer son poste** : Grafana et `logcli` (variables, contrôle de connexion).
3. **Requêtes types** (au moins 10), chacune avec sa question et son locataire : erreurs d'une application, une requête par son `request_id`, erreurs par route dans le temps, dernières lignes d'un pod disparu, événements d'un espace, kubelet d'un nœud, une VM du socle, qui a supprimé un objet, accès `exec`, échecs d'authentification, santé de la collecte elle-même. **Chacune exécutée** sur ton lab.
4. **Droits** : qui voit quoi (Grafana, `logcli`, locataire `audit`) et où se note une recherche dans l'audit.
5. **Pièges** (au moins 6) : avec le symptôme et la parade.
6. **Après la recherche** : quoi consigner, quand une requête devient un panneau ou une règle.

Fais-la relire par Nadia (MR, compte `nadia.roussel`) : elle doit pouvoir répondre, sans aide, à « qui a supprimé le déploiement `mediagenda` de la recette hier soir ? ».

**Critères de réussite** (auto-évaluation avec le corrigé)
- [ ] Le runbook est sur `main` de `plateforme/medisphere`, au chemin cité par les `runbook_url` des règles de E08.
- [ ] Il contient les six sections, au moins 10 requêtes types testées et au moins 6 pièges avec leur parade.
- [ ] Une personne qui n'a pas fait le module retrouve, avec lui seul, l'auteur d'une suppression dans l'audit.

<details><summary>Indice 1</summary>

Pars des incidents des modules précédents (post-mortems de `docs/kubernetes/post-mortems/`) : quelle question se posait-on, et quelle requête y aurait répondu ?
</details>

<details><summary>Indice 2</summary>

Les pièges les plus coûteux sont des erreurs de cadre, pas de syntaxe : mauvais locataire, mauvaise heure (UTC), mauvaise fenêtre, conclusion tirée d'une absence de lignes.
</details>

**Pour aller plus loin** (facultatif) : transforme les requêtes types en un tableau de bord Grafana « Enquête » (variables `locataire`, `namespace`, `request_id`), versionné dans `plateforme/observabilite/tableaux/` (M21-E17).
