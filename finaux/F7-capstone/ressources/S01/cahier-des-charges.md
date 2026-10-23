# Groupement hospitalier Seine-et-Vallées — Consultation n° GHSV-DSI-2026-014

## Cahier des clauses techniques particulières (CCTP) et règlement de la consultation

**Objet** : hébergement et exploitation, en mode service, d'une solution de prise de rendez-vous en ligne en marque blanche pour les douze établissements du groupement, raccordée à l'annuaire et au dossier patient informatisé (DPI) du GHSV.

| | |
|---|---|
| Pouvoir adjudicateur | Groupement hospitalier Seine-et-Vallées (GHSV), établissement support : Centre hospitalier de Vernaison |
| Direction pilote | Direction des systèmes d'information (DSI) — Élodie Marchand, directrice |
| Procédure | Procédure avec négociation (code de la commande publique) ; le GHSV se réserve la possibilité d'attribuer sur la base des offres initiales sans négociation |
| Durée du marché | 5 ans à compter du **1er mars 2027** |
| Version du document | 1.0 du 26 octobre 2026 |
| Annexes | A1 — Contrat d'interface `api-rendez-vous-v1.yaml` (OpenAPI 3.1) ; A2 — Volumétrie `volumetrie.csv` ; A3 — Bordereau de prix (DPGF, à compléter par le candidat, modèle au §11.3) |

> Document fictif, produit pour le workbook « MédiSphère ». Le GHSV, ses établissements, ses personnes et ses données n'existent pas. Toute ressemblance avec un groupement réel serait fortuite.

---

## Sommaire

1. Contexte et objectifs
2. Périmètre de la consultation
3. Glossaire et conventions du document
4. Exigences fonctionnelles (EF)
5. Exigences non fonctionnelles (ENF)
6. Sécurité et conformité (ESC)
7. Réversibilité (ERV)
8. Exploitation, engagements de service et rapports (EXP)
9. Calendrier et mise en service (MES)
10. Pénalités
11. Modalités de réponse
12. Soutenance (audition des candidats)
13. Critères de jugement des offres

---

## 1. Contexte et objectifs

### 1.1 Le groupement

Le Groupement hospitalier Seine-et-Vallées réunit douze établissements publics de santé : trois centres hospitaliers de référence, cinq centres hospitaliers de proximité, deux établissements de soins de suite et de réadaptation et deux établissements d'hébergement pour personnes âgées dépendantes (EHPAD) disposant de consultations externes. Il emploie environ 9 200 agents, dont 1 150 praticiens, et réalise environ 1,8 million de consultations externes programmées par an (détail par établissement en annexe A2).

La DSI du groupement (62 agents) exploite un DPI commun à onze établissements (le douzième, l'EHPAD des Tilleuls, rejoindra le DPI commun en 2028), un annuaire central et un fournisseur d'identité OpenID Connect (OIDC) commun, `https://idp.ghsv.example`, avec authentification multifacteur pour tous les agents.

### 1.2 La situation actuelle

Aujourd'hui, la prise de rendez-vous se fait :
- par téléphone auprès des secrétariats médicaux (≈ 70 % des rendez-vous) ;
- en ligne pour cinq établissements, par une plateforme commerciale dont le contrat s'achève le **28 février 2027** et ne sera pas renouvelé (le fournisseur a annoncé la fin de son offre « établissements publics ») ;
- par des formulaires de contact pour les autres.

Chaque établissement a ses propres pratiques ; les patients suivis dans plusieurs établissements ont plusieurs comptes.

### 1.3 Les objectifs du groupement

1. Offrir à tous les patients du groupement **un service unique** de prise de rendez-vous en ligne, aux couleurs du GHSV, pour l'ensemble des consultations externes.
2. Libérer du temps de secrétariat : objectif de 45 % des rendez-vous pris en ligne à la fin de la troisième année du marché.
3. **Synchroniser** les rendez-vous avec le DPI en temps réel par une API contractuelle.
4. Héberger les données dans des conditions conformes au référentiel HDS et sous le contrôle du GHSV (clés, journaux, réversibilité).
5. Disposer d'engagements de service **mesurés** et d'un pilotage mensuel.

---

## 2. Périmètre de la consultation

### 2.1 Dans le périmètre

- La fourniture, en mode service (SaaS), de la solution de prise de rendez-vous : interface web des patients, interface des agents (secrétariats, cadres de consultation), API d'interconnexion avec le DPI.
- L'hébergement des données de santé correspondantes (rendez-vous, comptes des patients, pièces jointes).
- L'exploitation, la supervision, la sauvegarde, le plan de reprise d'activité.
- La reprise des données de l'outil actuel (EF-08).
- Le support de niveaux 2 et 3, la maintenance corrective et évolutive de la solution.
- La réversibilité en fin de marché.

### 2.2 Hors périmètre

- Le DPI et ses évolutions (le GHSV adapte son DPI à l'API de l'annexe A1, à ses frais).
- Le fournisseur d'identité du GHSV et l'annuaire des agents.
- Le support de niveau 1 aux patients et aux agents (assuré par le centre de services du GHSV).
- La téléconsultation.

### 2.3 Tranches et options

- **Tranche ferme** : l'ensemble des exigences du présent CCTP.
- **Option 1** : API conforme au standard **HL7 FHIR R4** (ressources `Appointment`, `Slot`, `Schedule`) en plus de l'API v1, souhaitée pour la deuxième année.
- **Option 2** : extension à trois établissements supplémentaires susceptibles de rejoindre le groupement pendant la durée du marché (ENF-11).

---

## 3. Glossaire et conventions du document

| Terme | Sens dans ce document |
|---|---|
| Titulaire | Le candidat retenu, signataire du marché |
| Rendez-vous confirmé | Rendez-vous dont la confirmation a été affichée au patient ou à l'agent (et, pour le DPI, dont la création a reçu une réponse `201`) |
| Patient actif | Patient ayant au moins un rendez-vous dans les 24 derniers mois |
| Agent | Personnel du GHSV qui utilise l'interface des agents (secrétariat, cadre, administrateur fonctionnel) |
| Prise de rendez-vous | Les parcours de recherche de créneau, de création, de déplacement et d'annulation, par le web ou par l'API |
| Heures ouvrées | Du lundi au samedi, de 8 h à 19 h, hors jours fériés |
| Mois | Mois civil |

Les exigences sont identifiées (`EF-nn`, `ENF-nn`, `ESC-nn`, `ERV-nn`, `EXP-nn`, `MES-nn`). Le candidat y répond **une par une** dans le cadre de réponse technique (§11.2), en indiquant : *conforme*, *conforme avec réserve* (réserve explicite) ou *non conforme*. Le verbe « doit » marque une exigence ; « souhaité » marque un élément apprécié dans la notation, non éliminatoire.

---

## 4. Exigences fonctionnelles (EF)

**EF-01 — Prise de rendez-vous en ligne en marque blanche.** Les patients prennent rendez-vous depuis un site web adapté aux ordiphones, aux couleurs et sous le nom de domaine du GHSV (le GHSV fournit le nom ; le titulaire en assure la publication et les certificats). Le parcours est accessible (RGAA 4.1, niveau AA visé).

**EF-02 — Recherche de créneaux.** Recherche par établissement, spécialité, praticien et date ; affichage des créneaux libres des 90 jours suivants. Les créneaux sont ouverts par les agents ou importés du DPI.

**EF-03 — Annulation et déplacement par le patient.** Le patient annule ou déplace son rendez-vous jusqu'à 24 heures avant l'heure prévue. Au-delà, il contacte le secrétariat.

**EF-04 — Interface des agents.** Les agents consultent les agendas de leurs services, créent, déplacent et annulent des rendez-vous pour le compte des patients, et ouvrent ou ferment des plages. Les droits dépendent des groupes de l'annuaire du GHSV (un agent ne voit que les agendas de ses services).

**EF-05 — API d'interconnexion avec le DPI.** Le titulaire met à disposition l'API REST décrite en annexe A1 (`api-rendez-vous-v1.yaml`). Il s'engage sur ce contrat : toute évolution est **rétrocompatible** pendant la durée du marché ; une évolution incompatible fait l'objet d'une version v2 publiée en parallèle de la v1, maintenue au moins **12 mois** après la mise à disposition de la v2. Le DPI s'authentifie auprès de l'API selon le schéma décrit dans l'annexe A1. Un environnement de recette de l'API (EXP-06) est disponible en permanence.

**EF-06 — Rappels.** Un rappel par SMS ou par courriel est envoyé au patient deux jours avant son rendez-vous, s'il y a consenti lors de la prise de rendez-vous. Le coût d'envoi des SMS est compris dans le prix.

**EF-07 — Pièces jointes.** Le patient peut joindre à sa demande des documents (ordonnance, courrier d'adressage, résultats) : 10 Mo au plus par fichier, formats PDF, JPEG, PNG. Volume estimé : **environ 2 To par an** (annexe A2). Les pièces jointes sont transmises au DPI avec le rendez-vous et conservées par le titulaire pendant la durée du marché.

**EF-08 — Reprise des données existantes.** Le titulaire reprend les rendez-vous futurs et les trois dernières années d'historique de l'outil actuel (export CSV fourni par le GHSV, ≈ 1,6 million de lignes), ainsi que les comptes des patients des cinq établissements concernés (≈ 140 000 comptes ; les mots de passe ne sont pas transmis).

**EF-09 — Comptes des patients.** Les patients disposent de comptes locaux à la solution (création, vérification de l'adresse de courriel, réinitialisation du mot de passe). Un second facteur d'authentification doit être proposé aux patients qui le souhaitent.

**EF-10 — Statistiques d'activité.** Un export mensuel des statistiques par établissement et par spécialité (rendez-vous pris, annulés, honorés, part prise en ligne) est mis à disposition au format CSV.

**EF-11 — Interopérabilité FHIR (option 1).** Voir §2.3. Souhaitée pour la deuxième année du marché.

---

## 5. Exigences non fonctionnelles (ENF)

**ENF-01 — Volumétrie.** La solution est dimensionnée pour la volumétrie de l'annexe A2 : **1,8 million de rendez-vous par an**, **400 000 patients actifs**, et une croissance prévisionnelle de **6 % par an** du nombre de rendez-vous pendant la durée du marché.

**ENF-02 — Pointe de charge.** La pointe observée est de **150 requêtes par seconde**, le lundi de 8 h à 10 h. La solution doit absorber cette pointe sans dégradation des temps de réponse (ENF-05).

**ENF-03 — Disponibilité.** La disponibilité **mensuelle** de la prise de rendez-vous (web et API) est d'au moins **99,9 %**, hors maintenances programmées conformes à ENF-04. La méthode de mesure est décrite par le candidat dans son offre (EXP-07).

**ENF-04 — Maintenances programmées.** Les maintenances qui interrompent ou dégradent le service sont annoncées au GHSV **5 jours ouvrés** à l'avance, réalisées entre 22 h et 6 h, et ne dépassent pas **4 heures par mois** au total. Une maintenance qui ne respecte pas ces conditions est une indisponibilité.

**ENF-05 — Temps de réponse.** Mesurés au point d'entrée du titulaire : **95 %** des requêtes de l'API servies en moins de **300 ms** sur le mois ; **aucune** requête ne doit dépasser **1 seconde**. Les pages web des patients s'affichent en moins de 2 secondes sur une connexion 4G.

**ENF-06 — Plan de reprise d'activité.** La solution est hébergée sur au moins deux sites distincts. En cas de sinistre du site principal, le service est rétabli sur le second site avec une durée maximale d'interruption (**RTO**) de **4 heures** et une perte de données maximale (**RPO**) de **15 minutes**.

**ENF-07 — Intégrité des rendez-vous.** Aucun rendez-vous confirmé à un patient ne peut être perdu, quelles que soient les circonstances.

**ENF-08 — Test du PRA.** Le PRA est testé au moins **une fois par an** en conditions réelles, en présence d'un représentant du GHSV ; le rapport de test (RTO et RPO mesurés) est remis sous 15 jours.

**ENF-09 — Pics saisonniers.** Pendant les campagnes de vaccination (trois semaines par an, en octobre), la charge est multipliée par trois. La solution doit l'absorber dans les mêmes conditions de qualité de service.

**ENF-10 — Service continu.** Le service est accessible 24 heures sur 24, 7 jours sur 7.

**ENF-11 — Évolutivité.** La solution doit permettre d'accueillir jusqu'à trois établissements supplémentaires (option 2) sans modification de l'architecture ni du prix unitaire.

---

## 6. Sécurité et conformité (ESC)

**ESC-01 — Certification HDS.** Le titulaire est certifié **Hébergeur de données de santé** selon le référentiel en vigueur (arrêté du 26 avril 2024) pour les **activités 1 à 6**. Il joint son certificat (ou ceux de ses sous-traitants pour les activités qu'il ne réalise pas lui-même, avec la répartition des activités) à son offre.

**ESC-02 — ISO/IEC 27001.** Le titulaire est certifié ISO/IEC 27001:2022 sur un périmètre qui couvre la solution, ou s'engage à l'être au plus tard **12 mois** après le début du marché (plan de certification joint à l'offre).

**ESC-03 — Localisation des données.** Les données de santé, leurs sauvegardes et leurs copies sont hébergées exclusivement dans l'Espace économique européen. Le titulaire déclare tout accès possible depuis un pays tiers et toute soumission à une législation extra-européenne (cartographie des transferts).

**ESC-04 — Authentification des agents.** Les agents s'authentifient **exclusivement** par le fournisseur d'identité OIDC du GHSV, avec authentification multifacteur. Aucun compte local d'agent n'est créé dans la solution. Les droits sont déduits des groupes transmis par le fournisseur d'identité (EF-04). La désactivation d'un agent dans l'annuaire du GHSV supprime son accès en moins de **15 minutes**.

**ESC-05 — Authentification des patients.** Comptes locaux (EF-09). Politique de mots de passe conforme aux recommandations de la CNIL ; protection contre les attaques par force brute et par bourrage d'identifiants.

**ESC-06 — Chiffrement et clés dédiées.** Les données de santé du GHSV (base de données, pièces jointes, sauvegardes) sont chiffrées au repos avec des **clés dédiées au GHSV**, distinctes de celles des autres clients du titulaire. Le titulaire décrit la gestion de ces clés (génération, stockage, rotation au moins annuelle, révocation, destruction). Le GHSV doit pouvoir demander la révocation de ses clés.

**ESC-07 — Chiffrement des flux.** Tous les flux sont chiffrés (TLS 1.2 au minimum, TLS 1.3 souhaité), y compris à l'intérieur de l'infrastructure du titulaire.

**ESC-08 — Journaux.** Les journaux d'accès aux données, d'administration et de sécurité sont conservés **un an**, protégés contre la modification et la suppression, et mis à disposition du GHSV sur demande sous **5 jours ouvrés**.

**ESC-09 — Test d'intrusion.** Un test d'intrusion est réalisé **chaque année** par un prestataire qualifié PASSI, à la charge du titulaire ; le rapport est transmis au GHSV. Les vulnérabilités critiques sont corrigées sous **15 jours**, les élevées sous 30 jours.

**ESC-10 — Incidents de sécurité.** Le titulaire informe le GHSV de tout incident de sécurité affectant ses données **sans délai et au plus tard 24 heures** après sa détection, et lui fournit les éléments nécessaires à ses propres déclarations (CERT Santé, CNIL).

**ESC-11 — Accès du personnel du titulaire.** Les accès du personnel du titulaire aux données de santé sont nominatifs, justifiés, tracés et revus au moins tous les trimestres.

**ESC-12 — Diagnostic des échanges avec le DPI.** Le prestataire de maintenance du DPI du GHSV (centre de services situé à **Tunis**) doit pouvoir consulter les journaux techniques de l'API pour diagnostiquer les échanges entre le DPI et la solution.

**ESC-13 — Données de recette.** Aucune donnée de santé réelle n'est utilisée dans les environnements de recette ou de développement.

---

## 7. Réversibilité (ERV)

**ERV-01 — Plan de réversibilité.** Le candidat joint à son offre un plan de réversibilité (périmètre, formats, calendrier, rôles), mis à jour chaque année.

**ERV-02 — Export complet.** À la demande du GHSV ou en fin de marché, le titulaire livre un **export complet** des données du GHSV (rendez-vous, comptes des patients sans mot de passe, consentements, pièces jointes, historique) dans un **format ouvert et documenté**, sous **30 jours**. Le format est décrit dans le plan de réversibilité ; il permet une reprise par un tiers sans outil du titulaire.

**ERV-03 — Essai de réversibilité.** Un export complet d'essai est réalisé au cours de la troisième année ; le GHSV en vérifie l'exploitabilité.

**ERV-04 — Destruction des données.** Après la livraison de l'export de fin de marché et sa validation par le GHSV, le titulaire **détruit toutes les données du GHSV**, y compris les sauvegardes, les copies du second site et les journaux, sous **30 jours**, et remet un procès-verbal de destruction.

**ERV-05 — Accompagnement.** Le titulaire assiste le GHSV et le nouveau prestataire pendant la réversibilité (jusqu'à 20 jours de prestation, au prix du bordereau).

---

## 8. Exploitation, engagements de service et rapports (EXP)

**EXP-01 — Organisation du support.** Le centre de services du GHSV assure le niveau 1 et transmet au titulaire, par un outil de tickets commun, les demandes de niveaux 2 et 3. Le support du titulaire est joignable en heures ouvrées ; une **astreinte 24 h/24** traite les incidents de priorité P1.

**EXP-02 — Délais d'intervention.**

| Priorité | Définition | Prise en compte | Rétablissement |
|---|---|---|---|
| P1 | Prise de rendez-vous indisponible pour tout ou partie des établissements, ou incident de sécurité | 15 min, 24 h/24 | 4 h |
| P2 | Fonction dégradée (rappels, pièces jointes, API lente, interface des agents) | 1 h ouvrée | 1 jour ouvré |
| P3 | Anomalie sans impact sur la prise de rendez-vous | 1 jour ouvré | 10 jours ouvrés |

**EXP-03 — Rapport mensuel.** Avant le 10 de chaque mois, le titulaire remet un rapport sur le mois écoulé : disponibilité mesurée (ENF-03) et sa méthode, temps de réponse (ENF-05), incidents et leurs causes, maintenances réalisées, capacité (charge observée, marge restante, prévision), sécurité (vulnérabilités, accès du personnel du titulaire, incidents), changements réalisés et à venir, état des actions en cours.

**EXP-04 — Gouvernance.** Comité de suivi mensuel (DSI du GHSV, responsable du compte chez le titulaire) ; comité de pilotage trimestriel (direction du GHSV) ; revue annuelle de sécurité.

**EXP-05 — Gestion des changements.** Les changements qui touchent le GHSV (versions de la solution, de l'API, maintenances) lui sont annoncés ; l'API respecte EF-05.

**EXP-06 — Environnement de recette.** Un environnement de recette permanent, fonctionnellement identique à la production, est mis à disposition du GHSV (ESC-13). Les nouvelles versions y sont livrées au moins **10 jours ouvrés** avant la production.

**EXP-07 — Mesure des engagements.** Le candidat décrit dans son offre comment il mesure la disponibilité (ENF-03) et les temps de réponse (ENF-05) : point de mesure, fréquence, outillage, calcul. Le GHSV peut mettre en place ses propres sondes.

**EXP-08 — Capacité.** Le titulaire surveille la capacité et l'adapte à la charge réelle et prévisionnelle sans surcoût dans la limite de la volumétrie de l'annexe A2 et de sa croissance (ENF-01).

---

## 9. Calendrier et mise en service (MES)

**MES-01 — Mise en service.** La solution est en service pour **l'ensemble des douze établissements le 1er mars 2027**, date de fin du contrat de l'outil actuel.

**MES-02 — Déploiement.** Le déploiement se fait par vagues de trois établissements, sur quatre mois à compter de la notification du marché, chaque vague comprenant la reprise des données (EF-08), la formation des référents et une période de vérification de service régulier de deux semaines.

**MES-03 — Planning.** Le candidat joint un planning détaillé de la notification à la fin du déploiement, avec ses jalons, ses dépendances vis-à-vis du GHSV (DPI, fournisseur d'identité, nom de domaine, données) et les risques identifiés.

**MES-04 — Équipe projet.** Le candidat présente l'équipe affectée au projet et au service (rôles, disponibilité, astreinte) et son plan de continuité en cas de départ d'une personne clé.

---

## 10. Pénalités

Sauf cas de force majeure, les manquements suivants donnent lieu à pénalités, déduites de la redevance mensuelle :

| Manquement | Pénalité |
|---|---|
| Disponibilité mensuelle (ENF-03) inférieure à 99,9 % | 5 % de la redevance mensuelle par tranche entamée de 0,1 point sous l'engagement |
| Délai de rétablissement d'un incident P1 dépassé (EXP-02) | 1 % de la redevance mensuelle par heure de retard |
| RTO ou RPO dépassés lors d'un sinistre ou d'un test (ENF-06, ENF-08) | 10 % de la redevance mensuelle |
| Rapport mensuel remis en retard (EXP-03) | 200 € par jour ouvré de retard |
| Information tardive d'un incident de sécurité (ESC-10) | 2 000 € par jour de retard |

Le cumul des pénalités d'un mois est plafonné à **30 %** de la redevance mensuelle.

---

## 11. Modalités de réponse

### 11.1 Calendrier de la consultation

| Étape | Date |
|---|---|
| Publication de la consultation | lundi 26 octobre 2026 |
| Date limite des questions écrites des candidats | vendredi 13 novembre 2026, 12 h |
| Publication des réponses (à tous les candidats) | vendredi 20 novembre 2026 |
| Date limite de remise des offres | vendredi 4 décembre 2026, 12 h |
| Soutenances (auditions) | du 14 au 16 décembre 2026 |
| Notification prévisionnelle | fin janvier 2027 |
| Début d'exécution | lundi 1er mars 2027 |

Les questions sont posées **par écrit**, sur le profil d'acheteur du GHSV. Les questions et les réponses sont publiées, anonymisées, à l'ensemble des candidats.

### 11.2 Contenu de l'offre

1. **Mémoire technique** (40 pages au plus, hors annexes) : compréhension du besoin ; architecture et dimensionnement ; sécurité et conformité ; PRA ; réversibilité ; exploitation et engagements de service, avec leur méthode de mesure ; organisation et planning ; risques.
2. **Cadre de réponse technique** : réponse à chaque exigence (§3).
3. **Plan de réversibilité** (ERV-01), **plan d'assurance qualité et sécurité**, **plan de PRA**.
4. **Certificats** HDS et ISO/IEC 27001 (ou plan de certification), liste des sous-traitants et des activités HDS qu'ils réalisent.
5. **Décomposition du prix** (annexe A3, §11.3).

### 11.3 Décomposition du prix (DPGF)

| Ligne | Nature | Unité |
|---|---|---|
| P1 | Mise en service (projet, reprise des données, raccordements, formation des référents) | forfait |
| P2 | Redevance mensuelle de service, jusqu'à 2 000 000 de rendez-vous par an | mois |
| P3 | Supplément de redevance par tranche entamée de 100 000 rendez-vous annuels au-delà de 2 000 000 | tranche et mois |
| P4 | Option 1 — API FHIR R4 (mise en service, puis supplément de redevance mensuelle) | forfait + mois |
| P5 | Option 2 — Établissement supplémentaire (mise en service, puis supplément de redevance mensuelle) | établissement |
| P6 | Jour de prestation d'accompagnement (évolutions, réversibilité ERV-05) | jour |
| P7 | Export de réversibilité de fin de marché et destruction (ERV-02, ERV-04) | forfait |

Les prix sont fermes la première année, puis révisés annuellement selon l'indice Syntec. Le prix comprend toutes les licences, l'hébergement, l'exploitation, les SMS, le test d'intrusion annuel et le test annuel du PRA.

---

## 12. Soutenance (audition des candidats)

Les candidats dont l'offre est recevable sont auditionnés : **45 minutes de présentation**, suivies de **30 minutes de questions** du jury.

- Jury : la DSI du GHSV (présidente), le responsable de la sécurité des systèmes d'information du GHSV, le délégué à la protection des données, un représentant des directions des affaires médicales, un représentant des secrétariats médicaux.
- La présentation couvre au moins : l'architecture et sa capacité à tenir les engagements, la sécurité et la conformité, le PRA et sa dernière mesure, la réversibilité, l'organisation du service et le planning.
- Une **démonstration** est attendue : prise de rendez-vous par l'API sur l'environnement de recette, connexion d'un agent par le fournisseur d'identité du GHSV (un fournisseur d'identité de test est fourni sur demande), tableau de bord des engagements de service.
- Les supports sont remis au GHSV au début de la soutenance. Rien de ce qui est dit en soutenance ne modifie l'offre écrite, sauf confirmation écrite dans la phase de négociation.

---

## 13. Critères de jugement des offres

| Critère | Pondération |
|---|---|
| **Valeur technique** | **50 %** |
| — Architecture, dimensionnement et tenue des engagements de service (ENF, EXP-07) | 15 % |
| — Sécurité, conformité, gestion des clés et des journaux (ESC) | 15 % |
| — PRA et réversibilité (ENF-06 à ENF-08, ERV) | 10 % |
| — Organisation du service, planning, gestion des risques (EXP, MES) | 10 % |
| **Prix** (coût total sur la durée du marché : P1 + 60 × P2 + volumétrie prévisionnelle × P3 + P7) | **35 %** |
| **Soutenance** (clarté, démonstration, réponses au jury) | **15 %** |

Une offre non conforme à ESC-01, ESC-03 ou ESC-04 est irrégulière.

---

*Fin du CCTP. Contact pour les questions : profil d'acheteur du GHSV, consultation GHSV-DSI-2026-014.*
