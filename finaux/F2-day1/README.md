# Final F2 — Day 1 : accueillir les équipes

| | |
|---|---|
| **Type** | Workbook final (scénarios longs) |
| **Profil de lab** | Profil de travail des blocs F et G (socle v5 + `ceph-par1` + `k8s-par1`, ≈ 111 Go) ; rien en plus : les nouvelles équipes vivent dans les travailleurs (bilan de capacité en S02) |
| **Prérequis** | F1 (`day0-v1`) ; blocs E et F (observabilité, identité, secrets, durcissement) ; M28 (Capsule, Backstage, modèle `nouveau-service`) |
| **Durée indicative** | 55 à 75 heures |

## Contexte MédiSphère

La plateforme tient debout et se reconstruit. Il faut maintenant qu'elle serve. Trois arrivées tombent le même mois : **MédiVisio**, la nouvelle équipe produit de téléconsultation menée par Inès Garnier, qui veut livrer son premier service en jours et non en semaines ; l'**équipe Data** d'Hugo Bernard, qui doit produire les statistiques d'activité demandées par la direction et voudrait « juste un accès en lecture à la base de prod » ; et **AxiomDev**, le prestataire choisi par Julien Petit pour développer une fonctionnalité de MédiAgenda pendant trois mois, représenté par Marc Vidal. Claire Morel ne veut pas d'accueil artisanal : une équipe doit se créer en un changement relu, recevoir des droits par ses groupes, des quotas, un chemin balisé, et repartir sans laisser de traces. Sophie Laurent surveille le prestataire et les données de santé.

## Objectifs

À la fin de ce final, tu sais :
- définir l'offre de service d'une plateforme interne et le parcours d'accueil d'une équipe ;
- décrire une équipe en code (identité, dépôts, locataire, quotas, secrets, déploiement, observabilité) et l'appliquer en un changement ;
- mener une équipe du modèle de service à la production en autonomie, avec ses alertes et son SLO ;
- offrir des bases de données et des traitements par lots en libre-service sans exposer la production ;
- ouvrir à un tiers des accès bornés dans le temps et le périmètre, les auditer et les retirer ;
- mesurer l'accueil (délai jusqu'au premier déploiement, tickets) et en tirer une feuille de route.

## Carte des scénarios

| ID | Titre | Type | Diff. | Phase |
|---|---|---|---|---|
| F2-S01 | L'offre de service de la plateforme | RED | ★★★ | 1. Cadre |
| F2-S02 | Une équipe en un changement | LIBRE | ★★★★ | 1. Cadre |
| F2-S03 | Questions de conception : jusqu'où partager ? | Q | ★★★ | 1. Cadre |
| F2-S04 | MédiVisio : du modèle au premier déploiement | LIBRE | ★★★ | 2. MédiVisio |
| F2-S05 | MédiVisio en production, avec ses alertes et son SLO | LIBRE | ★★★ | 2. MédiVisio |
| F2-S06 | Panne : les premiers pas qui coincent | BF | ★★★ | 2. MédiVisio |
| F2-S07 | Des bases en libre-service pour l'équipe Data | LIBRE | ★★★★ | 3. Data |
| F2-S08 | Traitements par lots et refacturation interne | LIBRE | ★★★ | 3. Data |
| F2-S09 | Réponse à la demande d'accès à la production | RED | ★★ | 3. Data |
| F2-S10 | Des accès bornés pour AxiomDev | LIBRE | ★★★★ | 4. Prestataire |
| F2-S11 | Panne : le prestataire voit trop de choses | BF | ★★★ | 4. Prestataire |
| F2-S12 | Le départ d'AxiomDev | LIBRE | ★★★ | 4. Prestataire |
| F2-S13 | Recette Day 1 | LIBRE | ★★★ | 5. Recette |
| F2-S14 | Retour d'expérience et feuille de route | RED | ★★ | 5. Recette |

**Répartition** : 14 scénarios · 2 break & fix · 1 questionnaire · 3 rédactions.

## Ce qui change dans le lab

| Élément | Après |
|---|---|
| Annuaire et SSO | groupes `medivisio`, `data`, `ext-axiomdev` dans FreeIPA ; personnes `ines.garnier`, `hugo.bernard`, `marc.vidal` (+ un développeur par équipe) ; comptes d'AxiomDev **datés**, désactivés en S12 |
| GitLab | groupes `medivisio`, `data` ; AxiomDev en utilisateurs externes sur `mediagenda/api` seulement |
| Cluster | locataires Capsule `medivisio` (`medivisio-dev`, `-recette`, `-prod`) et `data` (`data-traitements`) ; espace `mediagenda-axiomdev` (locataire `mediagenda`), retiré en S12 |
| Plateforme | modèle Backstage `nouvelle-equipe` (ou dossier `plateforme/equipes/` appliqué par la CI) ; outil `ms-verif-equipe` |
| Documentation | `docs/accueil/` de `plateforme/medisphere` : offre de service, parcours d'accueil, réponses aux demandes, retour d'expérience, RB-320 et suivants, ADR-0320 et suivants ; étiquette **`day1-v1`** |

Détails figés : [`PLAN.md`](../../PLAN.md) §4.14.

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check F2 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break F2 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.
