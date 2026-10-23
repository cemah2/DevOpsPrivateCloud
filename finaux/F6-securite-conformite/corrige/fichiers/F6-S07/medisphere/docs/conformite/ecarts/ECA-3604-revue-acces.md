# ECA-3604 — Revue des accès non périodique, comptes orphelins

> Audit à blanc (Auditia Santé), constat du 2026-11-18, formalisé en F6-S07 (SEC-3607).

## Constat
La revue des accès `revue-acces/2026-11.md` est complète (neuf systèmes) et outillée, mais c'est la **première** : aucune revue antérieure n'est retrouvée. Elle a relevé cinq comptes orphelins et quatre comptes non justifiés, dont des accès créés par le prestataire AxiomDev que son départ (F2-S12) n'avait pas retirés (jeton de projet GitLab, liaison RBAC, ligne de la politique d'Argo CD). La périodicité est écrite depuis le 2026-11-10 seulement.

## Référence
- ISO/IEC 27001:2022 : **5.18** (droits d'accès : revue à intervalles planifiés), 5.15, 6.5, 8.2.
- HDS : maîtrise des accès d'administration (activité 5).

## Preuves
- `revue-acces/2026-11.md` (date, résultat, décisions) ; état brut P-IAM-06.
- Historique de `docs/` : aucune revue avant novembre 2026.
- Les corrections de la revue (MR et commandes datées du 2026-11-10 au 2026-11-12).

## Gravité
**Mineure** : le processus existe désormais, il est outillé et a produit ses effets ; il n'a pas encore été appliqué deux fois. Le constat d'orphelins, lui, montre qu'il manquait.

## Cause
Les droits étaient gérés par le code (équipe en code, F2) et l'on a supposé que le code suffisait ; les accès créés hors du code (essais, jetons, robots) n'avaient aucun contrôle.

## Correction
Comptes et accès orphelins retirés (lignes 1 à 9 de la revue).

## Action corrective
Revue mensuelle des privilèges et des prestataires, trimestrielle pour tous (pipeline `revue-acces` du 1er du mois) ; ajout des jetons de projet et robots à `depart-externe.sh` ; couverture étendue (PBS, NetBox, royaume `master`, certificats SSH).

## Responsable
Sophie Laurent (décisions), Plateforme (outil).

## Échéance
Deuxième revue (2026-12) faite et documentée : 2026-12-11.

## Statut
en cours
