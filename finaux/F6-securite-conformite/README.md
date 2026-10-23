# Final F6 — Sécurité et conformité

| | |
|---|---|
| **Type** | Workbook final (scénarios longs) |
| **Profil de lab** | Profil de travail des blocs F et G (≈ 111 Go) ; `c2-simule01` (3601, 512 Mo) pendant l'incident (S11-S12) |
| **Prérequis** | F2 (`day1-v1`), bloc F (M24 identité, M25 secrets, M26 durcissement et sécurité à l'exécution) ; M22 (journaux), M21 (alertes), M08 (RGW). F5 conseillé (preuves de PRA) |
| **Durée indicative** | 50 à 65 heures |

## Contexte MédiSphère

Le certificat HDS de MédiSphère doit être renouvelé sous le nouveau référentiel, et deux grands clients exigent désormais une certification ISO 27001. Avant l'audit officiel, Sophie Laurent fait venir le cabinet **Auditia Santé** pour un audit à blanc : Hélène Mercier, auditrice principale, passera une semaine dans les dépôts, les consoles et les journaux. « Une politique sans preuve n'existe pas, dit-elle. Et une preuve qu'on fabrique la veille de l'audit non plus. » Thomas Renaud, le DPO, veut savoir ce qui se passerait si des données de patients fuitaient demain. La réponse arrivera plus tôt que prévu.

## Objectifs

À la fin de ce final, tu sais :
- traduire un référentiel (HDS v2, ISO/IEC 27001:2022) en périmètre, déclaration d'applicabilité et preuves ;
- produire des preuves automatiquement, horodatées et inaltérables ;
- mener une revue des accès et un audit technique outillé, puis répondre à un auditeur ;
- rédiger un rapport d'écarts et un plan de remédiation priorisé par le risque, et le mettre en œuvre ;
- détecter, contenir, investiguer et éradiquer une compromission de conteneur sans détruire les preuves ;
- décider des notifications réglementaires (CNIL, clients, signalement santé) et les rédiger.

## Carte des scénarios

| ID | Titre | Type | Diff. | Phase |
|---|---|---|---|---|
| F6-S01 | Périmètre, exigences et déclaration d'applicabilité | RED | ★★★ | 1. Préparer l'audit |
| F6-S02 | Les preuves se collectent seules | LIBRE | ★★★ | 1. Préparer l'audit |
| F6-S03 | La revue des accès | LIBRE | ★★★ | 1. Préparer l'audit |
| F6-S04 | Panne : les écarts cachés de l'audit à blanc | BF | ★★★★ | 2. Auditer |
| F6-S05 | L'audit technique outillé | LIBRE | ★★★ | 2. Auditer |
| F6-S06 | L'entretien d'audit | Q | ★★★ | 2. Auditer |
| F6-S07 | Rapport d'écarts et plan de remédiation | RED | ★★★ | 2. Auditer |
| F6-S08 | Une traçabilité inaltérable | LIBRE | ★★★ | 3. Remédier |
| F6-S09 | Vulnérabilités et exceptions sous contrôle | LIBRE | ★★★ | 3. Remédier |
| F6-S10 | Prêts pour l'incident | LIBRE | ★★★ | 4. L'incident |
| F6-S11 | Panne : un conteneur compromis | BF | ★★★★ | 4. L'incident |
| F6-S12 | Investigation et éradication | LIBRE | ★★★★ | 4. L'incident |
| F6-S13 | Notifications, communication et post-mortem | RED | ★★★ | 4. L'incident |
| F6-S14 | Recette `conformite-v1` : l'audit de suivi | LIBRE | ★★ | 5. Bilan |

**Répartition** : 14 scénarios · 2 break & fix · 3 rédactions · 1 questions.

## Hôtes et objets

| Élément | Nom | Adresse | Scénario |
|---|---|---|---|
| Compartiment de preuves | `preuves-conformite` (RGW de `ceph-par1`, verrouillage d'objets) | `https://rgw.par1.medisphere.internal` | S02, S08 |
| Outil de collecte | `ms-preuves` (`plateforme/outils`) | — | S02, S14 |
| « C2 » simulé | `c2-simule01`, VMID 3601, VLAN 99 | 10.10.99.66 | S11, S12 |
| Espace de l'incident | `mediagenda-recette` (jamais la production) | — | S11-S13 |

L'incident est **simulé sans code malveillant** : le script d'injection rejoue des commandes ordinaires (shell, lecture d'un jeton, connexion sortante vers le « C2 » qui ne fait que journaliser, binaire factice). Versions et textes réglementaires : [`annexes/versions-finaux-F5-F7.md`](../../annexes/versions-finaux-F5-F7.md). Détails figés : [`PLAN.md`](../../PLAN.md) §4.15.

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check F6 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break F6 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.
