---
id: ECA-3606
titre: "Cartographie des transferts hors EEE absente"
origine: audit-2026 (Auditia Santé, Hélène Mercier)
mesures: [5.23, 5.19, 5.20, 5.21, 5.22, 5.31, 5.34, HDS souveraineté]
gravite: majeur
statut: en cours
ouvert-le: 2026-11-18
echeance: 2027-01-31
responsable: thomas.renaud
remediation: SEC-3607
clos-le:
preuve:
valideur:
---

# ECA-3606 — Cartographie des transferts hors EEE absente

> Audit à blanc (Auditia Santé), constat du 2026-11-18, formalisé en F6-S07 (SEC-3607).

## Constat
Aucune cartographie des transferts de données hors de l'EEE ni des accès depuis un pays tiers n'existe ; elle n'est donc pas publiée. Les fournisseurs n'ont pas été revus sous cet angle. La revue faite pour ce rapport (`transferts-hors-eee.md`) montre au moins : un outil de tickets SaaS dont la société mère est américaine et qui reçoit parfois des captures d'écran de dossiers patients ; un prestataire SMS dont les rapports de remise sont traités aux États-Unis ; une astreinte assurée depuis le Maroc deux semaines par an.

## Référence
- HDS (référentiel 2024) : exigences de souveraineté — localisation dans l'EEE, information contractuelle des clients sur les accès depuis un pays tiers et la soumission à une loi extra-européenne, **cartographie publiée** des transferts.
- ISO/IEC 27001:2022 : **5.23** (services en nuage), 5.19-5.22 (fournisseurs), 5.31 (exigences légales), 5.34.
- RGPD : chapitre V (transferts).

## Preuves
- Absence du document et de toute publication sur le site.
- Registre des fournisseurs : aucune colonne « pays, sous-traitants ultérieurs, loi applicable ».
- Exemples de tickets HelpNow avec pièces jointes de dossiers (constat de Thomas Renaud, 2026-11-18, sans copie des pièces).

## Gravité
**Majeure** : exigence explicite du nouveau référentiel non satisfaite, avec au moins un flux réel de données de santé vers un service soumis à une loi extra-européenne.

## Cause
La revue des fournisseurs date d'avant le référentiel de 2024 ; les outils « hors plateforme » (support, SMS) n'ont jamais été vus comme recevant des données de santé.

## Correction
Consigne immédiate au support : aucune pièce jointe de dossier patient dans HelpNow ; purge des pièces existantes (demande à l'éditeur, preuve de suppression) ; astreinte depuis un pays tiers suspendue jusqu'à décision.

## Action corrective
`transferts-hors-eee.md` validé par le DPO et publié ; information des clients (avenant) ; clauses des contrats HelpNow et SMS-Express revues ; revue annuelle des fournisseurs sous cet angle.

## Responsable
Thomas Renaud (DPO), avec Sophie Laurent.

## Échéance
Cartographie publiée : 2026-11-27 ; avenants : 2027-01-31.

## Statut
en cours

## Preuve de clôture
_(à la clôture : lot `ms-preuves` cité dans l'en-tête, et ce qu'il contient)_
