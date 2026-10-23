# Rapport d'écarts — audit à blanc HDS v2 et ISO/IEC 27001:2022

> SEC-3607 (F6-S07). Audit à blanc réalisé du 16 au 20 novembre 2026 par **Auditia Santé** (auditrice principale : Hélène Mercier), accompagnée par l'auditeur interne de la Plateforme. Rapport rédigé par MédiSphère à partir des notes de l'auditrice, relu par elle ; approuvé par Sophie Laurent (RSSI), présenté à la direction le 2026-11-26.

## 1. Synthèse pour la direction

MédiSphère **n'est pas prête** pour l'audit de certification, mais elle peut l'être dans les délais : sur six écarts, **quatre sont majeurs** et chacun a une solution connue, un responsable et une échéance avant fin janvier 2027. Aucun écart ne révèle une compromission ; trois touchent la capacité à **prouver** (journaux, réponse à incident, transferts), deux la **confidentialité des copies** et la **gestion des vulnérabilités**, un la **revue des accès** (déjà engagée).

Une question demande une décision de la direction dès cette semaine : des captures d'écran de dossiers patients arrivent dans l'outil de tickets du support, hébergé par une société soumise au droit américain (ECA-3606). La consigne et la purge sont lancées ; l'avenant aux contrats clients et le choix éventuel d'un autre outil relèvent de la direction.

| Gravité | Nombre | Écarts |
|---|---|---|
| Non-conformité majeure | 4 | ECA-3601, ECA-3603, ECA-3605, ECA-3606 |
| Non-conformité mineure | 2 | ECA-3602, ECA-3604 |
| Écarts trouvés et clos pendant l'audit | 4 | ECA-3611 à ECA-3614 (dérives récentes, § 5) |
| Observations | 6 | § 6 |

## 2. Méthode et périmètre

- **Référentiels** : ISO/IEC 27001:2022 (chapitres 4 à 10, annexe A) ; référentiel de certification HDS de 2024, activités 2 à 6.
- **Périmètre** : celui de [`perimetre.md`](../perimetre.md) (plateforme PAR1 et PAR2, applications hébergées) ; DataCampus (activité 1) vu sur pièces (certificat, contrat).
- **Méthode** : revue documentaire (SoA, périmètre, catalogue des preuves, revue des accès, runbooks, post-mortems) ; vérification des preuves par échantillonnage (lots `ms-preuves` du 2026-11-01 au 2026-11-19, vérifiés par l'auditrice avec la clé publique et l'identité `preuves-lecture`) ; observation de l'état réel avec un compte de **lecture** ; audit technique outillé de l'équipe ([`audit-technique.md`](audit-technique.md)) ; entretien d'une heure (SEC-3606) ; échanges avec le DPO.
- **Limites** : PAR2 et OpenStack non audités sur place ; aucun test d'intrusion (prévu au plan annuel) ; la sécurité physique repose sur le certificat de DataCampus.
- **Classement** : *majeure* = exigence non satisfaite, ou doute sérieux sur la capacité du système à atteindre ses résultats ; *mineure* = manquement ponctuel qui ne remet pas en cause le système ; *observation* = piste d'amélioration.

## 3. Points forts

- **Tout par le code** : infrastructure, configurations, politiques, équipes ; l'historique relu de Git est une preuve de date et d'auteur de premier ordre (8.9, 8.32).
- **Preuves automatiques** : collecte quotidienne signée, dans un compartiment en `COMPLIANCE` ; l'auditrice a pu vérifier elle-même les lots (5.33, 5.36).
- **Processus de changement** mesuré (F4) et **PRA exercé** (F5) : rares à ce niveau de maturité (5.30, 8.32).
- **Défense en profondeur** dans le cluster : admission (images signées, PSA `restricted`), détection (Falco, Tetragon), chiffrement entre nœuds.
- **Revue des accès** outillée et reproductible, même si elle est la première.

## 4. Écarts de l'audit

| Écart | Titre | Gravité | Mesures | Fiche |
|---|---|---|---|---|
| ECA-3601 | Journaux d'audit centralisés mais non inaltérables ; quatre sources non centralisées | **Majeure** | 8.15, 5.33, 5.28 | [ECA-3601](../ecarts/ECA-3601-journaux-audit.md) |
| ECA-3602 | Vulnérabilités sans délai de traitement ; exceptions sans échéance ; couverture incomplète | Mineure | 8.8, 5.36 | [ECA-3602](../ecarts/ECA-3602-vulnerabilites.md) |
| ECA-3603 | Sauvegardes Velero et exports non chiffrés côté serveur | **Majeure** | 8.13, 8.24 | [ECA-3603](../ecarts/ECA-3603-sauvegardes-chiffrement.md) |
| ECA-3604 | Revue des accès non périodique ; comptes orphelins | Mineure | 5.18, 6.5 | [ECA-3604](../ecarts/ECA-3604-revue-acces.md) |
| ECA-3605 | Aucune réponse à incident de sécurité testée ; pas de kit forensique ; pas de décision de notification | **Majeure** | 5.24-5.28 | [ECA-3605](../ecarts/ECA-3605-reponse-incident.md) |
| ECA-3606 | Cartographie des transferts hors EEE absente ; données de santé dans un outil soumis à une loi extra-européenne | **Majeure** | HDS (souveraineté), 5.23, 5.19-5.22 | [ECA-3606](../ecarts/ECA-3606-transferts-hors-eee.md) |

**Pourquoi ces gravités** : ECA-3601, 3603, 3605 et 3606 portent sur des exigences **non satisfaites** sur tout le périmètre (aucune source protégée, aucune copie chiffrée indépendamment du stockage, aucune capacité de réponse démontrée, aucune cartographie) ; ECA-3602 et 3604 portent sur des processus **en place** dont le pilotage ou la répétition manquent (détection et blocage fonctionnent ; une revue complète existe).

## 5. Écarts trouvés pendant l'audit (dérives récentes, clos)

L'auditrice a signalé le 2026-11-17 des dérives postérieures à la revue des accès, sans les nommer ; l'équipe les a retrouvées en moins de trois heures par comparaison avec les preuves quotidiennes, les a corrigées et formalisées.

| Écart | Dérive | Mesures | Clos le |
|---|---|---|---|
| ECA-3611 | silence de 60 jours sur les alertes de sécurité | 8.16, 5.25 | 2026-11-17 |
| ECA-3612 | dérogation Kyverno sans échéance, hors registre (signature des images non exigée en recette) | 5.36, 8.19 | 2026-11-17 |
| ECA-3613 | mot de passe en clair dans une ConfigMap de recette | 5.17, 8.24 | 2026-11-17 |
| ECA-3614 | planification Velero de la recette suspendue | 8.13 | 2026-11-17 |

*(Exemple : ton lot dépend du tirage.)* **Enseignement** : chaque dérive était visible dans une preuve quotidienne **le lendemain**, mais personne ne comparait les lots ; une détection est ajoutée pour chacune (fiches).

## 6. Observations

| N° | Observation | Mesure |
|---|---|---|
| O-1 | Exclusion de 8.23 discutable : `adm01` a une sortie Internet large ; à fermer (liste fermée) ou à réintégrer la mesure | 8.23 |
| O-2 | La date de confiance des preuves repose sur le stockage ; un horodatage indépendant (RFC 3161) renforcerait la valeur probante | 5.28 |
| O-3 | Administration de Ceph et production des preuves par la même équipe | 5.3 |
| O-4 | PBS, NetBox et le royaume `master` de Keycloak hors de la revue outillée | 5.18 |
| O-5 | Règles `auditd` absentes sur les VM Rocky ; base AIDE non réinitialisée après les montées | 8.15, 8.7 |
| O-6 | Profilage activé sur le plan de contrôle Kubernetes ; `--kubelet-certificate-authority` absent | 8.9 |

## 7. Suite

Plan de remédiation : [`plan-remediation.md`](../plan-remediation.md). Audit de suivi interne (F6-S14) trois mois après l'audit à blanc ; audit de certification à planifier après la clôture des quatre écarts majeurs.
