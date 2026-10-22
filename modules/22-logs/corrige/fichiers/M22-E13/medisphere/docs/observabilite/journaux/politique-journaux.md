# Politique des journaux de MédiSphère

> Propriétaire : équipe Plateforme. Validée par Sophie Laurent (RSSI). Version 1 : M22-E09 (SEC-2309).
> Les sections 2 (rétentions et effacement), 3 (accès) et 4 (sauvegarde) sont ajoutées par M22-E13 et M22-E16. Version 2 : M22-E13 (SEC-2313).

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

*(M22-E16)*

## 4. Sauvegarde

*(M22-E16)*
