---
id: ECA-3602
titre: "Vulnérabilités sans délai de traitement, exceptions sans échéance"
origine: audit-2026 (Auditia Santé, Hélène Mercier)
mesures: [8.8, 5.36, 8.19, HDS activité 4]
gravite: mineur
statut: clos
ouvert-le: 2026-11-18
echeance: 2026-12-18
responsable: sophie.laurent
remediation: SEC-3609
clos-le: 2026-12-16
preuve: lots/2026/12/16/20261216T013011Z-quotidienne/
valideur: sophie.laurent
---

# ECA-3602 — Vulnérabilités sans délai de traitement, exceptions sans échéance

> Audit à blanc (Auditia Santé), constat du 2026-11-18, formalisé en F6-S07 (SEC-3607).

## Constat
Les vulnérabilités des images sont détectées (analyse de Harbor par Trivy, composant CI `securite`), et les critiques corrigeables bloquent la mise en production. Aucun document ne fixe de **délai de traitement** par gravité. L'audit technique (S05) relève, en `mediagenda-recette`, une vulnérabilité critique corrigeable connue depuis 38 jours, une critique sans correctif publié depuis 21 jours sur une image de plateforme sans dérogation ni mesure compensatoire écrite, et deux images en service sans analyse retrouvée. Les « exceptions » de vulnérabilités sont des lignes d'un tableur sans date de fin.

## Référence
- ISO/IEC 27001:2022 : **8.8** (gestion des vulnérabilités techniques), 5.36 (conformité aux politiques), 8.19.
- HDS : maintien en condition de sécurité de la plateforme d'hébergement (activité 4).

## Preuves
- `audit-2026/audit-technique.md`, constats I-1 à I-4 ; `technique/images-en-service.json`.
- Preuve P-VUL-01 des lots du 2026-11-01 au 2026-11-18 : la même critique présente chaque semaine.
- Absence de politique : aucun document `docs/conformite/vulnerabilites.md` ni équivalent.

## Gravité
**Mineure** : la détection et le blocage en production fonctionnent (la mesure est en place) ; c'est son pilotage (délais, exceptions, couverture) qui manque. Deviendrait majeure si une critique corrigeable restait en **production**.

## Cause
Le blocage à la publication (M13, M19) a été vu comme suffisant ; rien n'oblige à reconstruire une image **déjà** déployée quand une vulnérabilité est publiée après coup ; les dérogations du M26 couvrent l'admission, pas les vulnérabilités.

## Correction
Reconstruction et redéploiement de l'image de recette (I-1) ; analyse forcée des deux images sans analyse (I-4).

## Action corrective
F6-S09 : politique de délais par gravité, exceptions de vulnérabilité datées qui expirent d'elles-mêmes (reliées au registre `EXC-…`), tableau de suivi du retard alimenté sans saisie.

## Responsable
Sophie Laurent (politique), Plateforme (outillage).

## Échéance
2026-12-18.

## Statut
clos le 2026-12-16 (SEC-3609, F6-S09), validé par Sophie Laurent.

## Preuve de clôture
Le lot `lots/2026/12/16/20261216T013011Z-quotidienne/` contient :
- **P-VUL-03** — `cve_allowlist` de chaque projet Harbor avec son échéance ; aucune exception sans date ni échue ;
- **P-VUL-02** — dérogations Kyverno et leurs échéances ;
- **P-CTL-01** — dernier pipeline planifié de `plateforme/politiques` (job `exceptions-vuln-echues`) : réussi ; l'essai d'une exception datée dans le passé, rejetée par ce job, est lié au ticket SEC-3609.

Pièces versionnées citées : `docs/conformite/vulnerabilites.md`, `outils/exceptions-vuln-echues.sh` (`plateforme/politiques`), tableau Grafana `f6-vulnerabilites`, lignes `EXC-V-nnn` du registre des exceptions.
