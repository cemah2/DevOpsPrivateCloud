# Analyse du cahier des charges — GHSV-DSI-2026-014

> PLAT-3701 (F7-S01). Auteur : équipe Plateforme. Relu par Claire Morel et Julien Petit.
> Source : CCTP v1.0 du 26/10/2026, annexes A1 (`api-rendez-vous-v1.yaml`) et A2 (`volumetrie.csv`). Mis à jour le 20/11/2026 avec les réponses du GHSV (`R-nn`).
> Ce document est **interne** : il ne part pas chez le client. Les questions envoyées au GHSV sont dans [`questions-client.md`](questions-client.md).

## 1. Le besoin en cinq lignes

Le GHSV (12 établissements, ≈ 1,8 million de rendez-vous par an) veut un service unique de prise de rendez-vous en ligne, à ses couleurs, pour ses patients et ses secrétariats, synchronisé en temps réel avec son DPI par une API contractuelle. Il veut l'héberger chez un hébergeur HDS, sur deux sites, avec des clés dédiées, des journaux conservés un an, une réversibilité complète et des engagements mesurés et pénalisés (99,9 % par mois, RTO 4 h / RPO 15 min). Le marché dure cinq ans à partir du 1er mars 2027, date à laquelle l'outil actuel de cinq établissements s'arrête.

## 2. Périmètre

| | Ce que dit le CDC | Ce que nous en comprenons |
|---|---|---|
| Dans le périmètre | Interface web des patients, interface des agents, API DPI (EF-01 à EF-10) ; hébergement HDS ; exploitation, sauvegarde, PRA ; reprise des données (EF-08) ; support N2/N3 ; réversibilité | Un **produit** (fonctionnel) et un **service** (hébergement, run). Pour MédiSphère : MédiAgenda (API) + interfaces web du produit commercial + plateforme |
| Hors périmètre (CDC §2.2) | DPI, IdP du GHSV, support N1, téléconsultation | Le GHSV adapte son DPI à l'API A1 **à ses frais** : notre contrat d'API est un engagement fort (EF-05, 12 mois de recouvrement) |
| Options | Option 1 FHIR R4 (EF-11) ; option 2 trois établissements de plus (ENF-11) | Option 1 : chiffrée à part, « non proposée » acceptée (R-08) ; option 2 : prix unitaire P5 |

### Ce que nous proposons de laisser hors périmètre (réserves de l'offre)

1. **Option 1 FHIR** : proposée en option chiffrée en année 2, pas en tranche ferme.
2. **Transmission des pièces jointes au DPI** : hors API v1 (R-06) ; une API 1.1 est à définir dans les six premiers mois, chiffrée en jours (P6) au-delà de 20 jours.
3. **Accès direct du centre de services de Tunis aux journaux** (ESC-12) : remplacé par une extraction filtrée, voir §4.
4. **Rendez-vous de l'EHPAD Les Tilleuls (GHSV-12) synchronisés avec le DPI** : impossible avant son raccordement au DPI commun (2028) ; agendas tenus dans l'interface des agents seulement.

## 3. Besoin ↔ solution

État au 20/11/2026, vérifié dans `mediagenda/api` (`main`), `mediagenda/deploiement` et `plateforme/gitops`. Légende : **D** disponible et publié en production · **R** disponible en recette seulement · **À dév.** à développer · **À nég.** à négocier · **H** hors produit (dans le lab).

### 3.1 Exigences fonctionnelles

| Exigence | État | Preuve, écart |
|---|---|---|
| EF-01 web patients en marque blanche | H | Interface web du produit commercial (hors lab) ; publication sous un nom du GHSV : nouveau (certificats publics, DNS du GHSV, exposition Internet) |
| EF-02 recherche par établissement, spécialité, praticien, 90 jours | À dév. | `GET /api/v1/creneaux` : **un jour**, un praticien ou `tous` ; plages **fixes** 8 h-12 h / 14 h-18 h codées (`PLAGES` dans `app.py`) ; aucune notion d'établissement ni de spécialité ; plages non ouvertes par les agents ni importées du DPI |
| EF-03 annulation et déplacement par le patient (≥ 24 h) | À dév. | Annulation : `DELETE` existe, sans règle des 24 h ; déplacement : **absent** |
| EF-04 interface des agents, droits par groupes | H + À dév. | Pas d'interface dans le lab ; aucune autorisation dans l'API (ni rôle, ni périmètre par service) |
| EF-05 API A1 | partiel | Voir §3.2 : 3 opérations sur 6 conformes, 1 partielle, 1 absente, 1 sémantique à revoir ; aucune authentification |
| EF-06 rappels J-2 | partiel | Choix du patient stocké (`rappel` : `sms`/`mail`/`aucun`, M27-E06) ; MédiAgenda publie les notifications vers MédiNotif (M27-E08) **à la prise de rendez-vous** ; envoi planifié à J-2 : à développer ; passerelle SMS réelle : à contractualiser (Mailpit dans le lab) |
| EF-07 pièces jointes, ≈ 2 To/an | À dév. | MédiAgenda ne gère aucun fichier ; MédiDoc (Go + S3) sait stocker des documents : intégration à développer ; MédiDoc n'a pas de production dans le lab (`medidoc-recette` en tient lieu, F5) |
| EF-08 reprise des données | À dév. | Outil de reprise à écrire ; format de l'export inconnu (Q-09) ; mots de passe non transmis : 140 000 patients devront réinitialiser |
| EF-09 comptes patients locaux, MFA proposée | À dév. | Aucun compte patient dans MédiAgenda ; Keycloak sait gérer des comptes locaux et l'OTP (M24) : royaume dédié aux patients à concevoir (S04) |
| EF-10 statistiques mensuelles CSV | partiel | Extraction pseudonymisée de l'équipe Data (F2, ADR-0327) ; « honoré » et « établissement » n'existent pas dans le modèle |
| EF-11 FHIR (option) | H | Rien ; option chiffrée |

### 3.2 Annexe A1 opération par opération

| `operationId` | Contrat A1 | MédiAgenda (`main`) | État |
|---|---|---|---|
| `listerCreneaux` | `GET /creneaux?date&praticien` → `Creneaux` | `GET /api/v1/creneaux`, mêmes paramètres, même schéma | **D** (sans authentification) |
| `listerRendezVous` | `GET /rendez-vous?praticien&du&au&limite` | `GET /api/v1/rendez-vous?limite` seulement : **`praticien`, `du`, `au` sont ignorés sans erreur** (FastAPI ne rejette pas les paramètres inconnus) → le DPI recevrait les 100 premiers rendez-vous de **tous** les praticiens depuis le début, avec un `200` | **À dév.** (piège : un test qui ne vérifie que le code HTTP passerait) |
| `creerRendezVous` | `POST /rendez-vous` 201/409/422, `rappel` | identique (rappel depuis M27-E06) | **D** |
| `obtenirRendezVous` | `GET /rendez-vous/{id}` 200/404 | identique | **D** |
| `deplacerRendezVous` | `PATCH /rendez-vous/{id}` 200/404/409/422, atomique | **absent** : `405 Method Not Allowed` | **À dév.** (simple : `UPDATE` sous l'index unique `(praticien, debut)` → 409) |
| `annulerRendezVous` | `DELETE /rendez-vous/{id}` 204/404 | identique, mais **suppression physique** de la ligne | **À dév.** : une annulation doit rester tracée (statistiques EF-10 « annulés », journaux ESC-08, réconciliation ENF-07) → annulation logique (statut) |
| sécurité `dpi` | OAuth 2.0 client credentials, portées `rdv:lecture`, `rdv:ecriture` | aucune authentification dans l'API ; la plateforme sait émettre des jetons (Keycloak, M24) et protéger une route (OAuth2 Proxy, M24) | **À construire** (F7-S08, F7-S09) |
| `servers` | `rendez-vous(-recette).ghsv.example` | `ghsv(-recette).apps.par1.medisphere.internal` dans le lab | nom public : production seulement |

Autres écarts du contrat : `Erreur` reprend le format de FastAPI (`detail` chaîne ou liste) : conforme ; identifiants de praticiens `P` + 6 chiffres (R-07) : compatibles avec la chaîne libre de MédiAgenda (1 à 100 caractères) ; **aucune notion de client** dans l'API : l'isolation du GHSV ne peut venir que du déploiement (instance et base dédiées, ADR-0370).

**Charge de développement estimée** (Julien Petit, ordre de grandeur) : filtres et annulation logique 8 j ; déplacement 4 j ; établissements, spécialités, plages et import quotidien du DPI 35 j ; règle des 24 h 2 j ; rappels J-2 10 j ; pièces jointes (via MédiDoc) 20 j ; comptes patients 25 j ; outil de reprise 15 j ; statistiques 6 j ; marque blanche des interfaces 20 j ; tests de contrat 8 j. **≈ 155 jours**, hors interfaces web du produit. C'est le premier risque du planning (S06).

## 4. Incohérences

### 4.1 Contradictions

| # | Exigences | Contradiction | Impact | Proposition |
|---|---|---|---|---|
| C1 | **ENF-06** ↔ **ENF-07** | Un RPO de 15 min admet la perte de 15 min de données ; « aucun rendez-vous confirmé ne peut être perdu » exige un RPO nul | Un RPO nul entre deux sites demande une réplication **synchrone** inter-sites : latence ajoutée à chaque écriture, et arrêt des écritures si le site de repli est injoignable (ou perte de la garantie) | RPO technique 15 min maintenu (ENF-06) ; ENF-07 tenue **par procédure** : réconciliation après bascule avec le DPI (qui a reçu le `201`) et le journal des confirmations envoyées (MédiNotif), chaque rendez-vous retrouvé recréé ou le patient rappelé. R-11 maintient les deux : notre offre décrit ce mécanisme (ADR-0373) |
| C2 | **ESC-08** ↔ **ERV-04** | Journaux conservés 1 an, mais toutes les données, « y compris les journaux », détruites sous 30 jours en fin de marché | Destruction impossible à prouver pour les sauvegardes et le stockage inaltérable des journaux (verrouillage d'objets, F6) ; nos propres obligations de traçabilité (HDS) | Journaux du GHSV inclus dans l'export de réversibilité ; conservation par MédiSphère des seuls journaux de sécurité nécessaires à ses obligations, pseudonymisés, jusqu'à leur échéance d'un an ; sauvegardes rendues illisibles par **destruction des clés** dédiées (ADR-0371, ADR-0374). R-17 le confirme |
| C3 | **ESC-03** ↔ **ESC-12** | Données dans l'EEE, accès depuis un pays tiers à déclarer ; mais un centre de services à Tunis doit consulter les journaux de l'API | Accès depuis un pays tiers = transfert au sens du RGPD si les journaux contiennent des données personnelles (identifiants de rendez-vous, praticiens, adresses IP) ; HDS v2 : accès depuis un pays tiers fondé sur une décision d'adéquation ou des garanties appropriées (art. 46 du RGPD ; la Tunisie n'a pas de décision d'adéquation) et cartographie publique des transferts (exigence 31 du référentiel) | Pas d'accès direct : extractions filtrées (codes, durées, routes, identifiants techniques pseudonymisés) déposées pour le GHSV, qui les transmet sous sa responsabilité ; ou accès inscrit dans la cartographie des transferts (`docs/conformite/transferts-hors-eee.md`, F6) avec garanties. Q-06, R-15 |
| C4 | **MES-01** ↔ **MES-02** | Tous les établissements au 1er mars, mais déploiement en vagues sur quatre mois à partir d'une notification fin janvier | Calendrier impossible tel quel | Vague 1 = les 5 établissements de l'outil actuel au 1er mars, puis vagues. **Résolu par R-18** (MES-01 modifiée) |

### 4.2 Exigences irréalistes

| # | Exigence | Pourquoi | Proposition |
|---|---|---|---|
| I1 | **ENF-05** « aucune requête ne doit dépasser 1 s » | C'est un 100e centile : une bascule de base, un ramasse-miettes, une requête de liste à 1 000 éléments, un nœud perdu suffisent. Aucun hébergeur ne peut le mesurer honnêtement à 0 exception | p99 < 1 s par mois, mesuré et rapporté ; p95 < 300 ms maintenu. R-10 l'accepte |
| I2 | **MES-01** (avant R-18) | Un mois entre notification et mise en service de 12 établissements, reprise comprise | Voir C4 |
| I3 | **ENF-09** lu littéralement (×3 sur la pointe) | 450 requêtes/s pendant trois semaines, pour un pic dont on ne sait pas s'il touche la pointe du lundi | R-02 : ×3 sur 20 % de l'activité → ×1,4 |

### 4.3 Ambiguïtés

| # | Exigence | Ambiguïté | Suite |
|---|---|---|---|
| A1 | ENF-02 | 150 requêtes/s de quoi (web, API, DPI) ? Mesurées où ? Mélange lecture/écriture ? | Q-01 → R-01 : extrapolation × 2,5, pas de répartition : H-01 |
| A2 | ENF-03, EXP-07 | Point de mesure, qui fait foi en cas d'écart | Q-04 → R-09 |
| A3 | ENF-03, ENF-04 | Une maintenance mal annoncée est une indisponibilité : quid d'une maintenance urgente de sécurité ? | Q-05 (sans réponse : H-07) |
| A4 | ESC-06 | « Révocation » des clés : arrêt du service ? Détention par le GHSV (BYOK, HYOK) ? | Q-07 → R-14 |
| A5 | ESC-01 | Activités 1 à 6 par le titulaire ou ses sous-traitants ? | Q-08 → R-13 : oui |
| A6 | EF-07 | Pièces jointes transmises au DPI, mais A1 n'a aucune opération pour les fichiers ; conservées « pendant la durée du marché » (≈ 12 To à 5 ans avec la croissance de 6 %/an, 13 To avec une marge de 10 %) | Q-10 → R-06 : API 1.1, conservation 12 mois |
| A7 | EF-06 | SMS compris dans le prix, volume inconnu : risque financier non borné | Q-11 → R-05 : 55 % de consentements |
| A8 | DPGF P2/P3 | Qu'est-ce qu'un rendez-vous compté (créé, honoré, annulé) ? Avec 6 %/an, la tranche des 2 millions est dépassée dès la 2e année | Q-12 → R-04 |
| A9 | ESC-04 | Désactivation en 15 min : les sessions et jetons déjà émis ? | H-08 (durée de vie des jetons) |
| A10 | ESC-04, R-16 | MFA : comment la prouver ? | R-16 : responsabilité du GHSV |
| A11 | EXP-01 | Support « heures ouvrées » du **lundi au samedi** : effectif du samedi | Organisation du run (S06) |
| A12 | EF-02, R-07 | Identifiants de praticiens et rattachement aux établissements et spécialités | Q-13 → R-07 |

### 4.4 Données douteuses de l'annexe A2

- **GHSV-12 (EHPAD Les Tilleuls)** : 129 000 consultations pour 7 praticiens, soit ≈ 18 400 par praticien et par an (≈ 75 par jour ouvré), contre ≈ 1 450 à 2 100 dans les dix autres établissements (≈ 4 200 pour l'EHPAD Les Glycines, déjà élevé) : aberrant. Q-03 → R-03 : 12 900 (erreur de saisie), total réel 1 683 900, dimensionnement à 1,8 million maintenu.
- **Patients** : la somme des lignes (462 300) dépasse le total (400 000) : dédoublonnage, écart de 62 300 (≈ 15 % du total), cohérent si environ un patient sur six ou sept est suivi dans deux établissements.
- **Praticiens** : 1 050 (A2) contre 1 150 (§1.1) : R-03 (effectif total contre praticiens de consultations externes).
- **Pièces jointes** : 2 000 Go/an pour 176 600 rendez-vous pris en ligne aujourd'hui = 11 Mo par rendez-vous, plus que la taille maximale d'un fichier : l'estimation suppose la part en ligne de la 3e année (45 % de 1,8 million ≈ 810 000, soit ≈ 2,5 Mo par rendez-vous, plausible).

## 5. Conditions de recevabilité (§13 du CCTP)

| Condition | Notre situation | Preuve à joindre |
|---|---|---|
| ESC-01 HDS activités 1 à 6 | Certifiés HDS v2 activités 2 à 6 ; activité 1 par les hébergeurs des salles PAR1 et PAR2 (R-13) | Notre certificat ; certificats des deux hébergeurs ; tableau de répartition des activités |
| ESC-03 données dans l'EEE | PAR1 et PAR2 en France ; aucun sous-traitant hors EEE **à condition** de choisir une passerelle SMS dans l'EEE et de traiter ESC-12 sans accès direct depuis Tunis | Cartographie des transferts (F6) à jour |
| ESC-04 agents par l'IdP du GHSV | Fédération OIDC par Keycloak (courtier d'identité) : démontrée dans le lab en F7-S08 | Démonstration en soutenance |
| ESC-02 (non éliminatoire) | Audit de certification ISO 27001 en janvier 2027 | Plan de certification |

## 6. Hypothèses

| ID | Hypothèse | Source, réponse du GHSV |
|---|---|---|
| H-01 | Les 150 req/s sont **toutes** les requêtes HTTP au point d'entrée (web + API + DPI), et 85 % sont des lectures | R-01 : pas de répartition fournie ; 85 % : profil de l'outil actuel tel que décrit (recherches de créneaux) et de MédiAgenda en production (rapport lecture/écriture de `mediagenda_http_requests_total`) |
| H-02 | Pointe d'octobre = pointe du lundi × 1,4 | R-02 (×3 sur 20 % de l'activité) ; on dimensionne à 1,5 par prudence |
| H-03 | La volumétrie de 1,8 million est le niveau 2026 ; année 1 du marché = × 1,06 | ENF-01, R-03 |
| H-04 | Pièces jointes conservées 12 mois ; stock ≈ un an de dépôts | R-06 (remplace l'hypothèse initiale « 5 ans ») |
| H-05 | 55 % des rendez-vous donnent lieu à un SMS de rappel | R-05 |
| H-06 | Les interfaces web (patients, agents) sont celles du produit commercial de MédiSphère ; la preuve de concept porte sur l'API | Introduction du final |
| H-07 | Une maintenance de sécurité urgente (faille critique exploitée) peut être faite hors préavis, et compte comme indisponibilité si elle interrompt le service | Q-05 sans réponse : on l'écrit dans l'offre |
| H-08 | Jetons d'accès des agents de 5 min, sans jeton de rafraîchissement au-delà de la session de l'IdP du GHSV : une désactivation prend effet en ≤ 15 min | ESC-04 |
| H-09 | Mesure contractuelle de disponibilité = sondes synthétiques externes de MédiSphère, méthode validée en comité de suivi | R-09 |
| H-10 | Le DPI tolère une indisponibilité de l'API pendant une bascule (il rejoue ses écritures en échec) | Q-14 sans réponse : à confirmer à la notification |

## 7. Recommandation

**Répondre, avec réserves.** Le cœur du besoin (API de rendez-vous, hébergement HDS, PRA mesuré sur deux sites, clés et journaux maîtrisés) correspond à ce que notre plateforme sait faire **et a prouvé** (F4 : changements mesurés ; F5 : bascule sur PAR2 mesurée ; F6 : audit et preuves). Les réserves :

1. ≈ 155 jours de développement de MédiAgenda, dont une partie avant le 1er mars : sans engagement de l'équipe de Julien dès décembre, on ne tient pas la vague 1 ;
2. ENF-05 reformulé (p99), ENF-07 tenu par procédure, ESC-12 sans accès direct, FHIR en option ;
3. PAR2 doit passer d'un site de repli « tiède » à une capacité réelle : achat de matériel (délais de livraison longs en 2026, voir S05, S06) ;
4. le prix doit couvrir les SMS (≈ 1 million par an) et une astreinte renforcée.

**Conditions de « no-go »** à vérifier avant le 4 décembre : la direction refuse d'engager le développement avant notification ; le délai de livraison du matériel dépasse fin avril ; aucun accord possible sur ESC-12.
