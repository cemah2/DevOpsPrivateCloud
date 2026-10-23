# Final F3 — Day 2 : semaine d'astreinte

| | |
|---|---|
| **Type** | Workbook final (scénarios longs, incidents injectés) |
| **Profil de lab** | Profil de travail des blocs F et G (socle v5 + `ceph-par1` + `k8s-par1`, ≈ 111 Go), sain au départ (`lab/bin/check F3 1`) |
| **Prérequis** | F2 (`day1-v1`) ; tout le parcours (les incidents traversent les couches) |
| **Durée indicative** | 35 à 50 heures |

## Contexte MédiSphère

Lundi 8 h. Nadia Roussel te passe le téléphone d'astreinte : « Ta première semaine seul·e. Karim est en congé, je suis en formation jusqu'à jeudi. Le classeur est à jour, normalement. » La semaine va être longue : des incidents arrivent comme ils arrivent en vrai — un utilisateur qui se plaint avant toute alerte, une alerte qui n'a pas sonné, une panne qui en cache une autre, une correction trop rapide qui en provoque une troisième. Chaque incident se diagnostique, se corrige, **se communique** (messages d'état à Claire et aux équipes, au rythme convenu) et laisse une trace exploitable. Vendredi soir, il reste à écrire le post-mortem de l'incident le plus grave, le rapport de semaine et la passation.

Les incidents sont injectés par `lab/bin/break F3 <XX>` : lance-les dans l'ordre, sans lire les scripts, et fais comme si le symptôme t'arrivait par téléphone. Chaque injection contrôle d'abord que le lab est sain et refuse de s'exécuter sinon.

## Objectifs

À la fin de ce final, tu sais :
- prendre une astreinte : vérifier ses accès, ses alertes, ses runbooks et ses comptes de bris de glace ;
- mener un incident selon une procédure écrite (gravité, rôles, chronologie, messages d'état) ;
- diagnostiquer sous pression des pannes qui traversent les couches (application, base, cache, réseau, stockage, certificats, secrets, livraison) ;
- distinguer cause et symptôme quand deux pannes se superposent ;
- écrire un post-mortem sans recherche de coupable, mesurer MTTA et MTTR, réduire le bruit des alertes ;
- passer une astreinte.

## Carte des scénarios

| ID | Titre | Type | Diff. | Phase |
|---|---|---|---|---|
| F3-S01 | Prendre l'astreinte | LIBRE | ★★★ | 1. Prise de poste |
| F3-S02 | La procédure de gestion d'incident | RED | ★★ | 1. Prise de poste |
| F3-S03 | Lundi : « MédiAgenda rame » | BF | ★★★ | 2. Lundi |
| F3-S04 | Lundi : pourquoi personne n'a été prévenu ? | BF | ★★★★ | 2. Lundi |
| F3-S05 | Mardi : les certificats ne se renouvellent plus | BF | ★★★ | 3. Mardi |
| F3-S06 | Mardi : un nœud tombe malade | BF | ★★★ | 3. Mardi |
| F3-S07 | Mardi soir : incident chronométré | CHRONO | ★★★★ | 3. Mardi |
| F3-S08 | Mercredi : le stockage ralentit tout | BF | ★★★★ | 4. Mercredi |
| F3-S09 | Mercredi : la livraison est bloquée | BF | ★★★ | 4. Mercredi |
| F3-S10 | Jeudi : les secrets ne suivent plus | BF | ★★★★ | 5. Jeudi |
| F3-S11 | Jeudi : la moitié des noms ne répond plus | BF | ★★★★ | 5. Jeudi |
| F3-S12 | Vendredi : alerte Falco en production | BF | ★★★ | 6. Vendredi |
| F3-S13 | Vendredi : les notifications s'accumulent | BF | ★★★ | 6. Vendredi |
| F3-S14 | Le post-mortem de la semaine | RED | ★★★ | 7. Bilan |
| F3-S15 | Faire taire les alertes inutiles | LIBRE | ★★★ | 7. Bilan |
| F3-S16 | Rapport de semaine et passation | RED | ★★ | 7. Bilan |

**Répartition** : 16 scénarios · 10 break & fix · 1 chronométré · 3 rédactions.

## Ce qui change dans le lab

Rien de durable en dehors de ce que tes corrections et tes actions de post-mortem changent dans le code (règles d'alerte, runbooks, limites, politiques), toujours par MR. Documentation : `docs/exploitation/` de `plateforme/medisphere` (procédure de gestion d'incident, main courante `journal/`, `post-mortems/`, rapport de semaine, RB-330 et suivants) ; étiquette **`astreinte-v1`**.

Détails figés : [`PLAN.md`](../../PLAN.md) §4.14.

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check F3 <XX>`, depuis `adm01`.
- Incidents : `lab/bin/break F3 <XX>`, depuis `adm01` (`--annuler` si tu abandonnes).
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.
