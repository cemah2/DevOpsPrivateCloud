# Exigences non fonctionnelles de l'offre GHSV — chiffrées, mesurables, traçables

> PLAT-3702 (F7-S02). Auteur : équipe Plateforme. Relu par Karim Benali (ensemble) et Sophie Laurent (§6).
> Entrées : CCTP GHSV-DSI-2026-014 (exigences `ENF-nn`, `ESC-nn`…), réponses du GHSV du 20/11/2026 (`R-nn`), hypothèses `H-nn` de [`analyse-cdc.md`](analyse-cdc.md).
> Les valeurs « mesuré aujourd'hui » entre crochets viennent du **lab de référence** du corrigé ou attendent **ta** mesure (`<…>`) : remplace-les par les tiennes, avec leur source.
> Ce document est la référence de la phase 3 : F7-S10 implémente les `NF-nn` au statut *à construire*.

## 1. Synthèse

| ID | Engagement mesurable | Source CDC | Cible contractuelle | Objectif interne | Statut |
|---|---|---|---|---|---|
| NF-01 | Disponibilité mensuelle de la prise de rendez-vous, vue de l'extérieur | ENF-03, ENF-10, EXP-07 | ≥ 99,9 % des minutes du mois | ≥ 99,95 % | à construire |
| NF-02 | Requêtes valides servies sans erreur serveur | ENF-03 | — (indicateur du rapport) | ≥ 99,95 % sur 28 j glissants | à construire |
| NF-03 | Maintenances programmées | ENF-04 | ≤ 240 min/mois, 22 h-6 h, annoncées 5 jours ouvrés avant | ≤ 120 min/mois | tenue (processus F4) |
| NF-04 | Latence de l'API (p95) | ENF-05 | 95 % < 300 ms par mois | 95 % < 250 ms (28 j) | tenue en recette, à construire pour le GHSV |
| NF-05 | Latence de queue de l'API (p99) | ENF-05 (reformulée, R-10) | 99 % < 1 s par mois | 99 % < 500 ms | à construire |
| NF-06 | Affichage des pages des patients | ENF-05 | < 2 s (4G simulée) au p75 | < 1,5 s | réserve (interfaces hors lab) |
| NF-07 | Capacité nominale de PAR1 | ENF-01, ENF-02, ENF-09, EXP-08 | 300 req/s, p95 < 250 ms, erreurs < 0,1 %, avec un nœud en moins | test à 400 req/s | à construire |
| NF-08 | Capacité de PAR2 en PRA | ENF-06, ENF-02 | 300 req/s, p95 < 300 ms | test à 300 req/s | à construire |
| NF-09 | Volumes à cinq ans | ENF-01, EF-07, ESC-08 | base ≤ 50 Go, pièces jointes ≈ 3 To utiles, journaux ≈ 60 Go/an | revue trimestrielle | calcul |
| NF-10 | RTO (sinistre du site principal) | ENF-06, ENF-08 | ≤ 4 h | ≤ 2 h 30 | mesuré au F5 (à refaire pour le GHSV) |
| NF-11 | RPO (sinistre du site principal) | ENF-06, ENF-08 | ≤ 15 min | ≤ 5 min | mesuré au F5 (à refaire) |
| NF-12 | Aucun rendez-vous confirmé finalement perdu | ENF-07 | 100 % des rendez-vous confirmés retrouvés ou traités sous 24 h après une bascule | — | à construire (procédure) |
| NF-13 | Test annuel du PRA | ENF-08 | 1/an, rapport sous 15 jours avec RTO et RPO mesurés | 2/an (dont un sans préavis interne) | tenue (F5) |
| NF-14 | Désactivation d'un agent | ESC-04 | ≤ 15 min | ≤ 10 min | à construire |
| NF-15 | Journaux conservés et restitués | ESC-08, ESC-11 | 365 j, inaltérables, restitution ≤ 5 jours ouvrés | restitution ≤ 2 jours ouvrés | à construire (base F6) |
| NF-16 | Délais de correction des vulnérabilités | ESC-09 | critiques ≤ 15 j, élevées ≤ 30 j | critiques ≤ 7 j | tenue (F6, ECA-3602) |
| NF-17 | Information d'un incident de sécurité | ESC-10 | ≤ 24 h après détection | ≤ 4 h | tenue (RB-360, F6) |
| NF-18 | Clés dédiées : rotation et destruction | ESC-06, ERV-04 | rotation ≤ 12 mois ; destruction sur demande avec procès-verbal ≤ 5 jours ouvrés | rotation automatique annuelle, `rewrap` dans le mois | à construire |
| NF-19 | Flux chiffrés | ESC-07 | 100 % des flux en TLS ≥ 1.2 (1.3 en façade) | 0 flux en clair dans le cluster | à construire |
| NF-20 | Délais de support | EXP-01, EXP-02 | P1 : prise en compte 15 min, rétablissement 4 h ; P2 : 1 h ouvrée, 1 jour ouvré | P1 pris en compte en 5 min | à construire (organisation, S06) |
| NF-21 | Rapport mensuel | EXP-03 | remis avant le 10 du mois | généré le 2 | à construire |
| NF-22 | Export de réversibilité | ERV-02, ERV-03 | export complet ≤ 30 j, format ouvert, vérifié par un tiers | essai annuel (pas seulement en 3e année) | à construire |
| NF-23 | Pas de donnée réelle hors production | ESC-13, EXP-06 | 0 donnée réelle en recette | contrôle mensuel | tenue (F2, extraction pseudonymisée) |

## 2. Disponibilité (NF-01 à NF-03)

### NF-01 — Disponibilité contractuelle (ENF-03, ENF-10, EXP-07)

- **Définition** : une minute est **disponible** si, sur cette minute, au moins la moitié des sondes synthétiques réussissent depuis **chacun** des deux points de mesure. Disponibilité du mois = minutes disponibles ÷ (minutes du mois − minutes de maintenance programmée conforme à ENF-04).
- **Sondes** (toutes les 15 s, délai de réponse 5 s) : `GET /api/v1/creneaux?date=<J+7>&praticien=P999001` (praticien fictif « sonde », sans donnée de santé) ; parcours d'écriture complet (création puis annulation) toutes les minutes sur le praticien fictif `P999002`, comme le témoin de RPO du F5 ; page d'accueil des patients (production seulement).
- **Points de mesure** : (1) `adm02` à PAR2 (sonde `ms-sonde-pra` du F5, étendue) ; (2) une sonde **hors de nos deux sites** (hébergement léger dans l'EEE, H-09) — sans elle, une coupure de l'accès Internet de PAR1 vue depuis PAR2 par le lien inter-sites resterait invisible. La sonde du GHSV (R-09) est comparée en comité.
- **Budget d'erreur** (0,1 %) : mois de 31 j : **44,6 min** ; 30 j : **43,2 min** ; 29 j : 41,8 min ; 28 j : 40,3 min. Une seule panne de 45 minutes fait perdre le mois.
- **Méthode** : séries 0/1 par sonde et par point, évaluées toutes les 15 s, enregistrées dans Prometheus (`ghsv:minute_disponible` au pas de 60 s) ; disponibilité du mois = `avg_over_time(ghsv:minute_disponible[<mois>])` en excluant les fenêtres de maintenance déclarées (série `ghsv:maintenance_programmee`, posée par la fiche CHG du F4). Même principe que la mesure d'interruption du F4 (une série 0/1 à pas fixe, `or vector(0)`), mêmes pièges.
- **Mesuré aujourd'hui** : MédiAgenda prod, sonde de continuité du F4 : `<ta disponibilité des 28 derniers jours>` ; SLO Pyrra `mediagenda-disponibilite` (99,5 % sur 28 j) : `<budget restant>`.

### NF-02 — SLO interne en requêtes (ENF-03)

- **Définition** : bonnes = réponses non 5xx ; valides = toutes les requêtes de l'API du GHSV hors `/sante`, `/pret`, `/metrics` et hors 4xx (une erreur du client n'est pas une indisponibilité, mais un taux de 4xx anormal se surveille à part : un 401 généralisé est une panne). Point de mesure : métriques de la Gateway (vues **avant** l'application, une API absente y compte) et histogramme de MédiAgenda (`mediagenda_http_requests_total`).
- **Budget** (H-01, 22 req/s en moyenne journalière ≈ 57 millions de requêtes par mois) : 0,05 % ≈ **28 500 requêtes en erreur par mois**.
- **Politique de budget d'erreur** : budget consommé à 50 % → changements non urgents du GHSV soumis à l'avis de Karim ; à 100 % → gel des changements du locataire `ghsv` hors correctifs, post-mortem, actions prioritaires ; alertes de consommation rapide (multi-fenêtres, Pyrra, M21).

### NF-03 — Maintenances (ENF-04, R-12)

Fiches CHG (processus du F4) : préavis de 5 jours ouvrés **au GHSV** (en plus du processus interne), fenêtre 22 h-6 h, durée prévue + durée mesurée par la sonde (F4-S02). Cumul mensuel dans le rapport. Objectif interne 120 min/mois : la moitié du droit, pour garder de la marge en cas de dépassement. Une maintenance de sécurité urgente compte comme indisponibilité si elle interrompt le service (H-07).

## 3. Temps de réponse (NF-04 à NF-06)

### NF-04 — p95 (ENF-05)

- **Contrat** : 95 % des requêtes de l'API < 300 ms sur le mois, au point d'entrée (Gateway).
- **Objectif interne** : 95 % < **250 ms**, déjà celui de MédiAgenda (M21) : l'histogramme de MédiAgenda n'a pas de seau à 0,3 s ; le seau 0,25 s rend l'objectif interne plus strict que le contrat, donc sûr. Pour le rapport, la latence de la Gateway (histogramme d'Envoy) est la mesure qui fait foi : elle inclut le temps hors application.
- **Mesuré aujourd'hui** : recette, référence du M29-E14 : p95 serveur **112 ms**, p99 **205 ms** à ≈ 158 req/s (parcours avec écriture). Prod : `<p95 de mediagenda-latence>`.

### NF-05 — p99 (ENF-05 reformulée)

« Aucune requête > 1 s » (100e centile) est remplacée, avec l'accord du GHSV (R-10), par **99 % < 1 s** sur le mois. Exclusions écrites : opération `listerRendezVous` avec `limite` > 500 (comptée à part). Le maximum observé figure dans le rapport, sans engagement.

### NF-06 — Pages des patients (ENF-05)

Réserve : les interfaces web sont hors du lab (H-06). Méthode proposée : test synthétique de navigateur (module navigateur de k6) depuis la sonde externe, profil réseau 4G simulé, p75 sur le mois. Statut *réserve* : mesure à mettre en place à la mise en service.

## 4. Capacité et volumes (NF-07 à NF-09)

### NF-07 — Capacité nominale de PAR1

| Étape | Calcul | Résultat |
|---|---|---|
| Pointe de référence | ENF-02 (niveau 2026, H-03) | 150 req/s |
| Croissance sur la durée du marché | 6 %/an, année 5 : 1,06⁵ = 1,338 | 201 req/s |
| Pointe d'octobre | R-02 : 0,8 + 0,2 × 3 = 1,4 ; arrondi à 1,5 par prudence (H-02) | **≈ 300 req/s** |
| Interrogations du DPI | R-01 : 600 praticiens / 300 s = 2 req/s (mais des listes longues) | incluses |
| Marge de test | utilisation cible ≤ 75 % à la pointe | test à **400 req/s** |

- **Engagement** : 300 req/s (mélange H-01 : 85 % de lectures) avec p95 < 250 ms et < 0,1 % d'erreurs, **avec un nœud de calcul en moins** (N+1).
- **Méthode** : test de capacité k6-operator trimestriel et avant chaque version majeure, sur la recette du GHSV dimensionnée comme la production (le parcours du M29-E14 adapté au mélange H-01), verdict dans Prometheus comme RB-295 ; capacité observée en continu (rapport mensuel : pointe du mois, utilisation, marge restante).
- **Écart avec aujourd'hui** : le lab tient ≈ 158 req/s en recette avec un parcours qui écrit à chaque itération, sur un hyperviseur unique ; c'est une preuve d'architecture, pas de capacité. La transposition (S03) passe par le coût par requête mesuré (CPU de l'API et de PostgreSQL pour 100 req/s), pas par le débit brut.

### NF-08 — Capacité de PAR2 en PRA (ENF-06)

300 req/s, p95 < **300 ms** (le contrat, pas l'objectif interne) ; pas d'exigence N+1 pendant un PRA (écrit dans l'offre). Test annuel pendant l'exercice de PRA (NF-13). Aujourd'hui : PAR2 du lab = un nœud de 5 Go, applications à 0 réplica (F5) : **non représentatif**.

### NF-09 — Volumes à cinq ans (ENF-01, EF-07, ESC-08)

| Donnée | Hypothèses | Volume à 5 ans |
|---|---|---|
| Rendez-vous | reprise 1,6 million de lignes + 1,91 à 2,41 millions/an (1,06¹ à 1,06⁵) ≈ 12,4 millions de lignes × ≈ 1,5 Ko (index et marge compris) | ≈ 20 Go (50 Go provisionnés par instance) |
| Comptes des patients | 400 000 × 1,34 ≈ 540 000 comptes × ≈ 5 Ko | ≈ 3 Go |
| Pièces jointes | R-06 : conservées 12 mois ; flux de l'année 5 = 2 To × 1,34 ; + 10 % (versions, suppressions différées) | ≈ **3 To utiles** (×3 en réplication Ceph) |
| Journaux | ≈ 57 millions de requêtes/mois × 450 octets ≈ 26 Go/mois bruts, compressés ≈ 1/8 ; + journaux d'audit (IdP, OpenBao, API Kubernetes) | ≈ 40 Go/an (an 1) à 60 Go/an (an 5), conservés 365 j |
| Sauvegardes | PITR 30 jours (sauvegarde de base hebdomadaire + WAL) ; attention : un `archive_timeout` court archive un segment de 16 Mo à chaque échéance, même presque vide (compressé, il reste petit, mais le nombre d'objets grimpe) | ≈ 200 Go |

Le GHSV est un **petit** client en calcul et en base ; il est **moyen** en stockage objet et **lourd** en exigences (deux sites, clés, journaux, astreinte). Le coût suivra les exigences, pas les volumes (S05).

## 5. Reprise (NF-10 à NF-13)

### NF-10 — RTO (ENF-06)

- **Définition** : du **début de l'indisponibilité** (première minute indisponible de NF-01) au **retour du service sur PAR2** (première minute disponible vue des deux points de mesure, écritures comprises). Le temps de décision est **dans** le RTO.
- **Décomposition cible** : détection et qualification 15 min ; décision de bascule (cellule de crise, critères écrits du F5) ≤ 45 min ; bascule technique ≤ 1 h ; vérifications et réouverture 30 min ; marge 1 h 30.
- **Mesuré** : F5, exercice 2026-1 (`docs/pra/exercices/2026-exercice-1/rapport.md`) : MédiAgenda `<RTO-MESURÉ-F5>`. À refaire pour le locataire `ghsv` (F7-S10, NF-13).

### NF-11 — RPO (ENF-06)

- **Définition** : écart entre l'horodatage de la dernière transaction validée à PAR1 avant le sinistre et celui de la dernière transaction retrouvée à PAR2.
- **Méthode** : témoin de RPO du F5 (CronJob `temoin-rpo`, une écriture par minute sur un cabinet technique), décliné dans `ghsv-prod` ; RPO maximal théorique = délai d'archivage des WAL (`archive_timeout`, 5 min par défaut dans CloudNativePG) + délai de réplication de l'objet vers PAR2 ; mesuré à chaque test.
- **Mesuré** : F5 `<RPO-MESURÉ-F5>`.

### NF-12 — Intégrité des rendez-vous confirmés (ENF-07, R-11)

Le RPO technique n'est pas nul ; l'engagement porte sur le **résultat** : après une bascule, chaque rendez-vous confirmé dans la fenêtre perdue est **retrouvé** et recréé, ou le patient est **contacté**, sous 24 h. Sources de réconciliation : le DPI (qui a reçu le `201` et garde le rendez-vous), le journal des confirmations envoyées par MédiNotif (MédiAgenda publie un message par création : M27-E08), les journaux d'accès (horodatage des `POST` en `201`, sans donnée de santé). Procédure de réconciliation dans RB-374, le runbook du PRA du client écrit en F7-S10 (ADR-0373). Mesure : rapport de réconciliation de chaque test de PRA (nombre de rendez-vous de la fenêtre, retrouvés, recréés, patients contactés).

### NF-13 — Test annuel (ENF-08)

Un exercice par an en présence du GHSV (rapport sous 15 jours, format du rapport du F5), plus un exercice interne. Les deux mesurent NF-10, NF-11, NF-12 et NF-08.

## 6. Sécurité (NF-14 à NF-19)

| ID | Définition et méthode | Mesuré aujourd'hui |
|---|---|---|
| NF-14 (ESC-04) | Délai entre la désactivation d'un agent dans l'IdP du GHSV et le premier refus (401/403) de l'API ou de l'interface. Jetons d'accès de 5 min ; sessions du courtier liées à celles de l'IdP du GHSV (H-08). Test mensuel automatisé sur un agent de test du royaume `ghsv-idp` | à construire (F7-S08) |
| NF-15 (ESC-08, ESC-11) | Journaux d'accès aux données, d'administration et de sécurité du GHSV : locataire de journaux dédié, rétention 365 j, copie quotidienne en verrouillage d'objets (remédiation de ECA-3601, F6) ; restitution : export filtré sur une période, empreintes SHA-256, ≤ 5 jours ouvrés (exercice semestriel chronométré) ; accès de notre personnel : revue trimestrielle (revue des accès du F6) | rétention actuelle `<ta rétention Loki>` |
| NF-16 (ESC-09) | Âge des vulnérabilités critiques et élevées ouvertes sur les images du locataire `ghsv` (rapports Trivy de Harbor), exceptions datées (processus de ECA-3602, F6) ; test d'intrusion PASSI annuel | `<âge max des critiques>` |
| NF-17 (ESC-10) | De l'horodatage de détection (alerte ou signalement) au message envoyé à la DSI du GHSV ; modèle de message et contacts dans RB-360 (F6), contact du GHSV ajouté | exercice F6 : `<délai>` |
| NF-18 (ESC-06, ERV-04, R-14) | Clés `transit/ghsv-*` d'OpenBao : date de dernière rotation (métadonnées de la clé), rotation automatique ≤ 12 mois ; destruction sur demande : procédure à deux personnes, procès-verbal, preuve que les données et sauvegardes deviennent illisibles (ADR-0371) | à construire (F7-S07) |
| NF-19 (ESC-07) | TLS ≥ 1.2 partout (1.3 en façade publique, vérifié par la sonde blackbox, `probe_tls_version_info`) ; dans le cluster : PostgreSQL et Valkey déjà en TLS (M27), trafic entre pods à chiffrer (chiffrement transparent de Cilium, à évaluer) | partiel |

MFA des agents : responsabilité du GHSV (R-16) ; notre engagement est de **n'offrir aucun autre moyen d'authentification** aux agents (aucun compte local, aucun mot de passe de secours dans le royaume `medisphere` pour le fournisseur `ghsv`). Vérifiable : liste des utilisateurs liés au fournisseur `ghsv` sans identifiant local.

## 7. Exploitation et réversibilité (NF-20 à NF-23)

- **NF-20** (EXP-01, EXP-02) : horodatages de l'outil de tickets commun (création, prise en compte, rétablissement) ; P1 déclenchés aussi par les alertes (astreinte). Organisation : S06.
- **NF-21** (EXP-03) : rapport généré automatiquement le 2 du mois (disponibilité, latence, incidents, maintenances, capacité, sécurité, changements), relu et envoyé avant le 10 (F7-S10).
- **NF-22** (ERV-02, ERV-03) : export complet en format ouvert (ADR-0374), chronométré ; essai annuel sur une copie de la production restaurée, contrôle par un tiers (l'équipe Data, qui n'a jamais vu le schéma) avec la seule documentation.
- **NF-23** (ESC-13, EXP-06) : la recette du GHSV ne contient que des données fictives ; contrôle mensuel (aucun identifiant `P`+6 chiffres réel, aucun nom issu de l'export de reprise).

## 8. Matrice de traçabilité

| Exigence du CDC | Couverte par | Remarque |
|---|---|---|
| ENF-01 | NF-07, NF-09 | volumétrie et croissance |
| ENF-02 | NF-07, NF-08 | |
| ENF-03 | NF-01, NF-02 | |
| ENF-04 | NF-03 | |
| ENF-05 | NF-04, NF-05, NF-06 | « aucune requête > 1 s » reformulée (R-10) ; pages web en réserve |
| ENF-06 | NF-08, NF-10, NF-11 | |
| ENF-07 | NF-12 | tenue par procédure (R-11) |
| ENF-08 | NF-13 | |
| ENF-09 | NF-07 | facteur 1,5 sur la pointe (R-02, H-02) |
| ENF-10 | NF-01 | 24 h/24 : aucune exclusion hors maintenances |
| ENF-11 | — | non reprise comme engagement mesuré : capacité de trois établissements de plus couverte par la marge de NF-07 ; prix unitaire P5 |
| ESC-01 | — | non reprise : condition de recevabilité, prouvée par certificats |
| ESC-02 | — | non reprise : plan de certification (audit janvier 2027) |
| ESC-03 | — | non reprise comme mesure : cartographie des transferts (F6) |
| ESC-04 | NF-14 | MFA : R-16 |
| ESC-05 | — | non reprise ici : politique de mots de passe et anti-bourrage du royaume des patients (ADR-0372), contrôlée par le test d'intrusion |
| ESC-06 | NF-18 | |
| ESC-07 | NF-19 | |
| ESC-08 | NF-15 | |
| ESC-09 | NF-16 | |
| ESC-10 | NF-17 | |
| ESC-11 | NF-15 | |
| ESC-12 | — | non reprise : alternative à l'accès direct (analyse C3, R-15) |
| ESC-13 | NF-23 | |
| EXP-01, EXP-02 | NF-20 | |
| EXP-03 | NF-21 | |
| EXP-07 | NF-01 | méthode validée en comité (R-09) |
| EXP-08 | NF-07 | |
| ERV-02, ERV-03 | NF-22 | |
| ERV-04 | NF-18 | destruction par les clés |
