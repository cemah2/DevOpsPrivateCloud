# Document d'architecture — réponse à la consultation GHSV-DSI-2026-014

> Version `<N>` du `<AAAA-MM-JJ>`, pour le RSSI et l'architecte du GHSV. S'appuie sur `architecture.md` (cible de production) et les ADR-0370 à ADR-0374 sans les recopier : ce document dit ce que la **preuve de concept** a confirmé, infirmé ou laissé ouvert. Les preuves citées (`P-nn`) sont dans `annexes-preuves.md`. Prix : ordres de grandeur d'octobre 2026, à vérifier (`chiffrage.md`).

## 1. Périmètre

Dans l'offre : prise de rendez-vous des patients (web et API), interface des agents, API v1 du DPI (annexe A1), rappels, pièces jointes, reprise des données, exploitation sur deux sites, réversibilité. Dans la preuve de concept (lab) : **l'API** de MédiAgenda hébergée pour le GHSV, l'identité fédérée des agents, le contrat d'interface testé, les clés dédiées, les engagements mesurés, la reprise sur PAR2, la réaction aux incidents. **Pas** dans la preuve de concept : écrans patients et agents, pièces jointes, comptes des patients, reprise de l'outil actuel (§5).

## 2. Traçabilité exigence → décision → preuve

| Exigence | Ce que nous faisons | Décision | Preuve | Statut |
|---|---|---|---|---|
| EF-01 marque blanche | instance dédiée, nom du GHSV, titre de l'API du GHSV | ADR-0370 | P-01 (locataire en code), P-02 (`/openapi.json` de la recette) | confirmé (API) ; écrans : lot de construction |
| EF-05 API v1, rétrocompatibilité, v2 ≥ 12 mois | API adaptée sans rupture pour nos cabinets, tests de contrat bloquants en CI, politique de versionnage | `versionnage.md` | P-05 (pipeline vert), P-06 (MR fautive refusée) | confirmé |
| ENF-02 pointe 150 req/s | dimensionnement par coût mesuré par requête × facteur écrit | `architecture.md` §5 | P-07 (référence de charge M29, charge `demo-ghsv`) | **à confirmer** en préproduction : le lab ne tient pas 150 req/s (§5) |
| ENF-03 99,9 %/mois hors maintenances | sondes externes (30 s), calcul calendaire, maintenances conformes retirées | `engagements.md` | P-08 (rapport mensuel), P-09 (SLO) | confirmé (méthode) ; valeur réelle : à mesurer en production |
| ENF-05 95 % < 300 ms | seau 0,3 s ajouté à l'histogramme ; centile 99,9 % < 1 s proposé (R-10) | `engagements.md` | P-08, P-10 (k6 : écart client/serveur) | confirmé (méthode) |
| ENF-06 RTO 4 h / RPO 15 min | réplication continue vers PAR2, témoin de RPO, essai isolé | ADR-0373 | P-11 (essai de reprise : RPO `<MIN>`, reprise `<MIN>`), P-12 (exercice PRA du F5) | confirmé pour les données ; **ouvert** pour l'identité à PAR2 (§5, RSQ-17) |
| ENF-07 aucun rendez-vous perdu | rejeu depuis le DPI de la fenêtre perdue | ADR-0373 | — | ouvert : procédure à valider avec le GHSV |
| ESC-03 données dans l'EEE | deux salles en France ; aucun accès hors EEE hors ESC-12 | `analyse-cdc.md` | P-13 (cartographie des transferts, F6) | confirmé ; réserve ESC-12 |
| ESC-04 agents par l'IdP du GHSV, MFA, révocation < 15 min | courtier OIDC, refus des agents sur nos outils, session de 15 min | ADR-0372 | P-14 (constat de cloisonnement), P-15 (révocation chronométrée) | confirmé |
| ESC-06 clés dédiées, révocables | `transit/ghsv-*`, non exportables, rotation annuelle, effacement cryptographique | ADR-0371 | P-16 (configuration des clés), P-17 (essai de réversibilité) | confirmé pour les exports ; **écart** base et archives (§4) |
| ESC-08 journaux 1 an inaltérables | Loki (audit) + `preuves-conformite` en `COMPLIANCE` | F6 (ECA-3601) | P-18 | confirmé |
| ESC-10 incident < 24 h | RB-360 du F6, information contractuelle | F6 | P-19 (exercice INC-6211) | confirmé |
| ERV-02 export ouvert ≤ 30 jours | `ms-reversibilite`, JSON Lines + CSV, manifeste signé, chiffré | ADR-0374 | P-17 (durée `<MIN>`, relecture par une base vierge) | confirmé (volume du lab) ; extrapolé au volume réel |
| ERV-04 destruction prouvée | RB-371 : destruction physique + clés | ADR-0371, ADR-0374 | P-20 (essai de destruction de clé sur une clé d'essai) | confirmé (procédure) |
| EXP-03 rapport avant le 10 | rapport généré le 1er, MR, relecture | RB-374 | P-08 | confirmé |

## 3. Architecture cible de production (résumé)

Deux salles en France, PAR1 (production) et PAR2 (repli tiède), reliées par une liaison chiffrée ; à chacune, Kubernetes (Cilium, CloudNativePG, OpenBao, Keycloak), stockage objet, sauvegardes, supervision. Le GHSV est un **locataire** isolé (Capsule, réseau, quotas, Argo CD), avec son instance de MédiAgenda, sa base, son cache, ses mandataires d'accès, ses clés et ses journaux. Les agents passent par l'IdP du GHSV (courtier), le DPI par un client OAuth 2.0 dédié. Détails, schémas et dimensionnement : `architecture.md` ; décisions : ADR-0370 à ADR-0374.

## 4. Données et chiffrement

| Données | Cible | Preuve de concept | Écart |
|---|---|---|---|
| Base (champs identifiants) | chiffrement applicatif par `transit/ghsv-donnees` (ADR-0371) | volume chiffré LUKS (clé de la plateforme) | **oui** : développement DEV-3704 du lot de construction |
| Archives de la base, pièces jointes | SSE-KMS par `transit/ghsv-sauvegardes` (compatibilité RGW à confirmer) | compartiment dédié, non chiffré par une clé du client | **oui** |
| Exports | enveloppe `transit/ghsv-exports`, manifeste signé | idem | non |

Tant que les écarts existent, la destruction en fin de contrat se fait par destruction physique **et** destruction des clés, procès-verbal à l'appui.

## 5. Ce que le lab ne montre pas, et pourquoi on peut quand même s'engager… ou pas

| Sujet | Lab | Production | Engagement |
|---|---|---|---|
| Capacité | 1 hyperviseur, 3 travailleurs, quelques req/s | serveurs dimensionnés (`architecture.md` §5) | **conditionné** à une campagne de charge en préproduction (avril 2027), écrite dans le planning |
| Exposition | réseau privé, noms `.internal` | Internet, anti-DDoS, domaine du GHSV | méthode identique, mesures à refaire |
| Identité à PAR2 | absente (PRA v1 du F5) | instance Keycloak de repli | **non tenu aujourd'hui** : écrit comme écart et chiffré (RSQ-17) |
| Écrans patients et agents | absents | produits existants de MédiSphère | hors démonstration ; RGAA à auditer |

## 6. Réversibilité

Export complet en format ouvert (JSON Lines et CSV aux champs de l'API v1, annexe technique, manifeste signé), chiffré, remis par un canal séparé ; relecture par un tiers à chaque essai annuel ; destruction prouvée sous 30 jours après validation (RB-371, ADR-0374). Ce qui reste chez nous après la fin du contrat : journaux de sécurité pseudonymisés jusqu'à leur échéance d'un an, documents contractuels.

## 7. Risques résiduels principaux (identifiants de `risques.md`)

| ID | Risque | Traitement |
|---|---|---|
| RSQ-17 | Pas d'authentification à PAR2 pendant un PRA (agents et DPI) | Keycloak de repli à PAR2 restauré depuis PBS, intégré au RB-350 avant la mise en production |
| RSQ-13 | Capacité réelle non démontrée dans le lab | campagne de charge en préproduction ; clause de revue au comité de suivi |
| RSQ-18 | Clés du client non appliquées à la base et aux archives | développement du chiffrement applicatif, SSE-KMS ; destruction physique en attendant |
| RSQ-01 | Notification tardive | travaux préparatoires engagés à nos risques sur le lot commun |
