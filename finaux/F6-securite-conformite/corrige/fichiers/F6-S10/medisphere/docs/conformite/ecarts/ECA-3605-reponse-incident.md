---
id: ECA-3605
titre: "Aucune réponse à incident de sécurité testée, pas de kit forensique"
origine: audit-2026 (Auditia Santé, Hélène Mercier)
mesures: [5.24, 5.25, 5.26, 5.27, 5.28, 6.8, HDS information du client]
gravite: majeur
statut: clos
ouvert-le: 2026-11-18
echeance: 2027-01-15
responsable: sophie.laurent
remediation: SEC-3610
clos-le: 2027-01-13
preuve: lots/2027/01/13/20270113T013007Z-quotidienne/
valideur: sophie.laurent
---

# ECA-3605 — Aucune réponse à incident de sécurité testée, pas de kit forensique

> Audit à blanc (Auditia Santé), constat du 2026-11-18, formalisé en F6-S07 (SEC-3607).

## Constat
La gestion des incidents d'exploitation existe et est pratiquée (F3 : gravités, rôles, main courante, post-mortems). Pour un incident de **sécurité** : aucune procédure de confinement d'une charge compromise n'a été exercée (la quarantaine réseau du M26 n'a jamais servi hors de l'exercice du module), aucun moyen de capturer l'état d'un conteneur avant de le détruire n'est prêt, aucun modèle de message aux clients ni de décision de notification (CNIL, clients, signalement santé) n'existe. À la question 13 de l'entretien, l'équipe n'a pas su dire qui notifie la CNIL.

## Référence
- ISO/IEC 27001:2022 : **5.24** (planification et préparation), **5.26** (réponse), **5.28** (recueil des preuves), 5.25, 5.27, 6.8.
- HDS : information du client en cas d'incident ; RGPD art. 33 (le client notifie, l'hébergeur l'informe sans délai).

## Preuves
- Absence de runbook de réponse à incident de sécurité et de forensique (`docs/securite/runbooks/`).
- Registre des exercices : aucun exercice de sécurité.
- Compte rendu de l'entretien du 2026-11-19 (questions 13 et 7).

## Gravité
**Majeure** : la capacité à répondre à un incident de sécurité n'est pas démontrée, sur un périmètre qui héberge des données de santé.

## Cause
Les outils de détection ont été installés (Falco, Tetragon, alertes d'audit) sans que le « et ensuite ? » soit préparé ; l'astreinte est organisée pour la disponibilité, pas pour la sécurité.

## Correction
Aucune immédiate ; la RSSI est désignée pilote de tout incident de sécurité en attendant la procédure.

## Action corrective
F6-S10 : RB-360 (réponse à incident) et RB-361 (forensique de conteneur), kit et droits prêts, modèles de notification, exercice ; puis F6-S11 à S13 (incident réel du lab).

## Responsable
Sophie Laurent, avec Nadia Roussel (support) et Thomas Renaud (notifications).

## Échéance
2027-01-15.

## Statut
clos le 2027-01-13 (SEC-3610, F6-S10), validé par Sophie Laurent.

## Preuve de clôture
Le lot `lots/2027/01/13/20270113T013007Z-quotidienne/` contient :
- **P-CTL-01** — dernier pipeline planifié de `plateforme/outils` (job `kit:verifier`, `bin/ms-verifier-kit-forensique`) : réussi (image d'outils signée, dépôt possible et suppression d'une version refusée, modèles présents).

Pièces versionnées citées : RB-360, RB-361 (capture éprouvée sur `wb-essais`, résultat écrit), compte rendu `docs/securite/incidents/exercices/2027-01-exercice-table.md` et ses actions datées.
