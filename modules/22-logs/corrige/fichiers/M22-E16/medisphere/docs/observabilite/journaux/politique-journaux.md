# Politique des journaux de MédiSphère

> Propriétaire : équipe Plateforme. Validée par Sophie Laurent (RSSI). Version 1 : M22-E09 (SEC-2309).
> Les sections 2 (rétentions et effacement), 3 (accès) et 4 (sauvegarde) sont ajoutées par M22-E13 et M22-E16. Version 2 : M22-E13 (SEC-2313). Version 3 : M22-E16 (SEC-2316).

## 1. Données de santé et données personnelles

### 1.1 La règle

**Aucune donnée personnelle de patient n'entre dans Loki.** Ni nom, ni prénom, ni date de naissance,
ni NIR, ni adresse de courriel ou de téléphone d'un patient, ni contenu de document. Un journal sert à
comprendre ce que fait un système, pas qui est soigné.

Deux lignes de défense, dans cet ordre :

1. **Les applications ne journalisent pas de données personnelles** (contrat des applications,
   `apps/README.md`) : on journalise des **identifiants techniques** (`rdv_id`, `request_id`, plus tard
   `trace_id`), jamais la donnée. C'est la seule défense complète : elle est vérifiée en revue de code
   et par des tests (« pas de donnée patient dans le journal », `tests/test_api.py` de MédiAgenda).
2. **La collecte masque ce qui passe quand même** (exception non rattrapée, bibliothèque bavarde,
   erreur humaine) : étape `loki.process "masquage"` d'Alloy, **dernière** étape avant l'envoi, sur
   toutes les sources (pods, journald des nœuds et des VMs, audit, événements).

### 1.2 Ce que la collecte masque (Alloy, M22-E09)

| Motif | Remplacé par | Remarque |
|---|---|---|
| NIR (13 chiffres + clé, espaces ou points facultatifs, Corse 2A/2B) | `[NIR-MASQUE]` | bornes de mot : un nombre plus long (horodatage en ns) n'est pas touché |
| adresse de courriel **hors** `medisphere.internal` | `[COURRIEL-MASQUE]` | les adresses de service (`astreinte@`, `plateforme@`…) restent lisibles |
| valeur des champs JSON `patient`, `nom`, `prenom`, `nom_patient`, `nom_naissance`, `date_naissance`, `telephone` | `[MASQUE]` | liste convenue avec les équipes : un nouveau champ nominatif se déclare ici d'abord |

Limites assumées, écrites pour ne tromper personne :

- un **nom en texte libre** (« patient Jeanne Martin ») n'est pas reconnaissable par une expression
  régulière : seule la ligne de défense n° 1 le traite ;
- un faux positif (un numéro de 15 chiffres qui ressemble à un NIR) est masqué : on préfère perdre une
  information technique que garder une donnée de santé ;
- le masquage s'applique à la **ligne** ; les métadonnées structurées posées par Alloy ne contiennent
  que des identifiants techniques (liste fermée : `pod`, `stream`, `niveau`, `request_id`, `unite`,
  champs de l'audit).

### 1.3 Vérification

- en continu : le contrôle `lab/bin/check 22 09` (motifs recherchés dans tous les locataires sur 1 h) ;
- à chaque changement de la configuration d'Alloy : le pod témoin `wb-essais/temoin-donnees`
  (`ressources/E09-temoin`) écrit des valeurs **factices** ; ses lignes doivent arriver masquées ;
- en revue de code des applications : refus de toute ligne de journal qui contient une donnée patient.

### 1.4 Si une donnée personnelle est trouvée dans Loki

C'est un **incident de sécurité** (ticket `SEC-`, Sophie Laurent prévenue le jour même) :
1. corriger la source (application ou masquage) et le vérifier avec le témoin ;
2. demander la suppression des lignes concernées par l'API de suppression de Loki (M22-E13), dans le
   locataire touché, sur la plage de temps exacte ;
3. consigner dans le registre des incidents : quoi, depuis quand, qui a pu le lire (journal d'audit de
   Grafana et de l'API Kubernetes).

## 2. Rétentions et effacement

> M22-E13 (SEC-2313). La configuration fait foi : `plateforme/observabilite/loki/values.yaml`, sections `loki.compactor`, `loki.limits_config` et `loki.runtimeConfig`.

### 2.1 Locataires, contenu et durées

| Locataire | Contenu | Rétention | Effacement par l'API | Limites d'ingestion (débit / rafale / flux actifs) | Justification de la durée |
|---|---|---|---|---|---|
| `audit` | Journal d'audit de l'API de `k8s-par1` (nœuds de contrôle), événements de sécurité | **365 jours** | **fermé** (`deletion_mode: disabled`) | 2 Mo/s / 4 Mo / 500 | Exigence de traçabilité HDS et ISO 27001 (A.8.15) : savoir qui a fait quoi sur la plateforme pendant un an ; durée validée par la RSSI |
| `mediagenda` | Journaux des pods `mediagenda-*` (JSON, sans donnée patient) | **30 jours** | ouvert (`filter-and-delete`) | 4 Mo/s / 6 Mo / 2 000 | Diagnostic des incidents et des réclamations (délai de réponse support : 15 jours ouvrés) ; au-delà, les métriques (Thanos) suffisent |
| `medidoc` | Journaux des pods `medidoc-*` | **30 jours** | ouvert (`filter-and-delete`) | 4 Mo/s / 6 Mo / 2 000 | Idem |
| `plateforme` | Tout le reste : nœuds (journald), composants du cluster, VMs du socle, événements Kubernetes | **14 jours** (24 h pour l'espace `wb-essais`) | fermé | 8 Mo/s / 12 Mo / 10 000 | Exploitation et post-mortems (un incident est analysé dans la semaine) ; volume le plus gros |
| `essai` | Essais (Fluent Bit, effacement, formations) | **24 h** (minimum du compactor) | ouvert | 1 Mo/s / 2 Mo / 500 | Jetable par nature |

Valeurs par défaut (tout locataire non listé) : celles de `plateforme`, effacement fermé. Un nouveau locataire se déclare par MR dans `loki/values.yaml` **et** dans ce tableau, avant d'envoyer la moindre ligne.

Ce que ces durées veulent dire concrètement :
- la rétention est appliquée par le **compactor** toutes les 10 minutes sur l'index, puis les chunks marqués sont supprimés **2 heures** plus tard (`retention_delete_delay`) : c'est la seule fenêtre où une erreur de réglage se rattrape en remettant la configuration ;
- la profondeur de requête (`max_query_lookback`) est alignée sur la rétention : une requête ne renvoie jamais une donnée « en sursis » ;
- Loki refuse une ligne datée de plus de 7 jours (`reject_old_samples_max_age: 168h`) : on ne réinjecte pas d'anciens journaux.

### 2.2 Limites d'ingestion

Les limites protègent les autres locataires d'un locataire bavard. Un dépassement fait répondre Loki **429** (débit) ou **429** sur les nouveaux flux (`max_global_streams_per_user`) ; Alloy réessaie puis abandonne (lignes perdues, compteur `loki_write_dropped_entries_total`). Les seuils d'alerte sont dans `performance.md` (M22-E14). Toute hausse de limite se fait par MR, avec la mesure qui la justifie.

### 2.3 Effacement (droit à l'effacement, RGPD art. 17)

- **Quand** : une donnée personnelle a été journalisée malgré le masquage (fuite, voir § 1.4), ou une personne exerce son droit à l'effacement et une trace la concernant est identifiée dans les journaux.
- **Qui demande** : le DPO ou la RSSI (ticket `SEC-` daté) ; **qui exécute** : un membre de l'équipe Plateforme d'astreinte, jamais l'équipe applicative seule.
- **Où c'est possible** : `mediagenda`, `medidoc`, `essai`. **Jamais** sur `audit` (pièce de preuve : on y documente l'événement, on ne l'efface pas — si une donnée personnelle y figurait, la RSSI décide d'une purge exceptionnelle hors API, tracée).
- **Comment** : RB-221 — demande ciblée (sélecteur + filtre de ligne + fenêtre minimale), vérification immédiate par requête (la ligne n'est plus renvoyée), annulation possible pendant **24 h** (`delete_request_cancel_period`), suppression physique au passage suivant du compactor.
- **Délai** : demande créée sous 72 h après le ticket ; effacement physique sous 48 h ensuite.
- **Trace** : la demande (identifiant, requête, fenêtre, date) reste listée par l'API ; le ticket `SEC-` en garde la copie et la preuve de vérification. On ne recopie **jamais** la donnée effacée dans le ticket.

### 2.4 Ce qui n'est jamais dans Loki

- Corps de requêtes et de réponses applicatives, documents de MédiDoc, contenu des rendez-vous.
- Secrets (jetons, mots de passe, clés) : Alloy n'en ajoute pas, les applications n'en écrivent pas ; une fuite est un incident `SEC-` (rotation du secret **et** effacement).
- Journaux de `pve01` et de `pbs01` (hors du lab virtualisé, voir M21).

## 3. Accès aux journaux

> M22-E16 (SEC-2316).

| Qui | Quoi | Par où | Remarque |
|---|---|---|---|
| Équipes MédiAgenda, MédiDoc, Plateforme | locataires `mediagenda`, `medidoc`, `plateforme` en lecture | Grafana, organisation principale (sources « Loki — <locataire> ») | Grafana OSS ne restreint pas une source à une équipe : tout compte de l'organisation principale peut interroger les trois locataires. **Risque accepté** par la RSSI : ces journaux ne contiennent ni donnée de santé ni donnée personnelle (masquage M22-E09, contrat des applications) |
| Sophie Laurent (RSSI, administratrice), Nadia Roussel, Karim Benali, Claire Morel | locataire `audit` en lecture | Grafana, organisation **Sécurité** (OpenTofu `observabilite-grafana`, M22-E16) | Seule organisation qui porte la source « Loki — audit » |
| Équipe Plateforme (administration, astreinte) | tous les locataires, API complète (dont effacement RB-221) | `adm01` (MGMT) : `logcli`, `curl` | Accès tracé par le journal de `adm01` ; la politique réseau ouvre MGMT sans filtre HTTP |
| Collecteurs (Alloy du cluster et des VMs) | écriture seulement | `POST /loki/api/v1/push` | Règle HTTP de Cilium (M22-E16) : un collecteur ne peut pas lire |
| Prometheus | `/metrics` | réseau du cluster | |

Transport : le Service 10.10.41.62 parle **HTTP en clair** (règle 6 du module). Décision : accepté, parce que les journaux sont masqués avant l'envoi (§ 1.2), qu'ils ne quittent pas les réseaux du lab, et que les écritures depuis les VMs sont limitées au `push` par la politique réseau. À revoir avec la passerelle authentifiante du M24 (TLS et identité des agents au même endroit) ; dans le cluster, le chiffrement des flux entre nœuds relève de Cilium (WireGuard, hors périmètre de ce module).

Ce qui reste faible, et pourquoi c'est accepté jusqu'au M24 :
- l'en-tête `X-Scope-OrgID` n'authentifie personne : depuis MGMT ou depuis Grafana, on peut lire n'importe quel locataire en le changeant. Le cercle des personnes qui ont ces accès est réduit (équipe Plateforme) ;
- une VM du socle compromise peut **écrire** dans n'importe quel locataire (pollution, pas lecture) ;
- M24 (Keycloak) : passerelle authentifiante devant Loki qui pose l'en-tête à partir de l'identité, et SSO de Grafana avec rôles par équipe.

## 4. Sauvegarde

> M22-E16 (SEC-2316).

| Élément | Où | Sauvegarde | Restauration |
|---|---|---|---|
| Configuration de Loki et d'Alloy, règles, politiques réseau | `plateforme/observabilite`, `plateforme/gitops` | Git (GitLab, lui-même sauvegardé) | Argo CD resynchronise |
| Secrets (`loki-objstore`, comptes) | Ansible Vault `critique` | avec le dépôt `plateforme/ansible` | `secrets-k8s.sh` |
| Données (chunks, index, règles du *ruler*, demandes d'effacement) | compartiment `loki-k8s-par1` du RGW | **pas de copie** ; **versionnage** + expiration des versions non courantes à **7 jours** | restauration d'objets par version (voir ci-dessous) |
| WAL et index actif de l'ingester (≤ 2 h de journaux pas encore vidés) | PVC `storage-loki-0` (`ceph-rbd`) | non (rejoué au redémarrage) | perte de ≤ 2 h si le PVC est détruit |

Décision : les journaux ne sont **pas** copiés hors site. Leur valeur d'exploitation décroît vite ; la seule exigence de durée forte (audit, 1 an) est couverte par le versionnage contre l'erreur humaine et par la réplication de `ceph-par1` contre la panne d'un disque. Risque accepté (Claire Morel, Sophie Laurent) : la perte totale de `ceph-par1` emporte les journaux ; la copie du locataire `audit` vers PAR2 est inscrite au plan du PRA (F5).

- **RPO** : ≤ 2 h de journaux (vidage des chunks) en cas de perte du pod et de son volume ; 0 pour une suppression d'objets par erreur dans les 7 jours.
- **RTO** : 30 min pour reconstruire Loki depuis Git (nouveau pod, même compartiment) ; 1 h pour restaurer des objets supprimés par erreur.

Restaurer des objets supprimés par erreur (rétention mal réglée, suppression manuelle), dans les 7 jours :
1. **Arrêter la cause** : remettre la bonne rétention (revert) **et** suspendre le compactor si la suppression continue (`retention_enabled: false` le temps de l'opération).
2. Lister les marqueurs de suppression : `aws s3api list-object-versions --bucket loki-k8s-par1 --prefix <locataire>/ --endpoint-url https://rgw.par1.medisphere.internal` (identifiants `s3-loki.env`).
3. Supprimer les **marqueurs** de suppression (`aws s3api delete-object --version-id <ID-DU-MARQUEUR>`) : la version précédente redevient courante.
4. L'index : les tables d'index réécrites par le compactor sont elles aussi versionnées ; restaurer la version de la table du jour concerné de la même façon, puis redémarrer `loki-0` pour vider son cache d'index. À répéter sur un essai avant d'en avoir besoin.
