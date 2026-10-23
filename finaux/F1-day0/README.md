# Final F1 — Day 0 : construire MédiSphère

| | |
|---|---|
| **Type** | Workbook final (scénarios longs) |
| **Profil de lab** | Profil de travail des blocs F et G (socle v5 + `ceph-par1` + `k8s-par1`, ≈ 111 Go) ; `pxe01` (2111, 1 Go) allumé pendant la phase 2 ; `k8s-par1` **détruit puis reconstruit** sur ses VMID d'origine (2141-2146) en phase 3 |
| **Prérequis** | Blocs A à D (le code de tout ce qui est reconstruit) ; dans les faits, l'état de fin du bloc G : `lab/bin/check 29 25`, `28 25`, `27 25`, `26 46`, `25 46`, `24 46` verts |
| **Durée indicative** | 60 à 85 heures (dont de longues attentes de sauvegarde, d'installation et de construction) : phase 1 12 à 19 h, phase 2 11 à 15 h, phase 3 25 à 35 h, phase 4 10 à 16 h |

## Contexte MédiSphère

La plateforme a été construite brique par brique pendant dix-huit mois. Avant l'audit de certification HDS, Sophie Laurent pose une question simple : « Si on perd tout le cluster demain, est-ce qu'on sait le reconstruire, et en combien de temps ? Montrez-moi. » Claire Morel prend la question au mot : MédiSphère va faire son **Day 0** pour de bon. Le cluster `k8s-par1` sera détruit et reconstruit **à partir du code seul** (Git, états OpenTofu, rôles Ansible, Helmfile, Argo CD, OpenBao), avec un filet de sécurité vérifié avant, deux VMs redondantes du socle seront refaites de la même façon, un nœud passera même par l'usine de provisioning comme un serveur physique sorti du carton, puis la première livraison de MédiAgenda en production empruntera le chemin normal. Tout ce qui demande une main humaine sera chronométré, écrit, et devient de la dette à résorber.

## Objectifs

À la fin de ce final, tu sais :
- établir la carte d'amorçage d'une plateforme (ordre, dépendances circulaires, secrets hors du code) ;
- détecter et résorber la dérive entre le code et l'existant ;
- préparer une opération destructive à grande échelle : sauvegardes prouvées, critères de go/no-go, retour arrière écrit ;
- reconstruire un cluster Kubernetes de production et sa plateforme à partir du code, et y remettre les données ;
- faire passer un serveur « nu » par toute la chaîne (NetBox → PXE → Ansible → cluster) ;
- mesurer une reconstruction et en tirer un rapport et un runbook exploitables.

## Carte des scénarios

| ID | Titre | Type | Diff. | Phase |
|---|---|---|---|---|
| F1-S01 | La carte d'amorçage de MédiSphère | RED | ★★★ | 1. Préparer |
| F1-S02 | Chasse à la dérive | LIBRE | ★★★ | 1. Préparer |
| F1-S03 | Panne : les mains de quelqu'un sont passées par là | BF | ★★★ | 1. Préparer |
| F1-S04 | Le filet : sauvegardes prouvées, go/no-go et retour arrière | LIBRE | ★★★ | 1. Préparer |
| F1-S05 | Reconstruire `lb02` et `dns02` depuis le code | LIBRE | ★★★ | 2. Socle et usine |
| F1-S06 | L'usine prépare un nœud Kubernetes | LIBRE | ★★★★ | 2. Socle et usine |
| F1-S07 | Détruire et reconstruire les nœuds de `k8s-par1` | LIBRE | ★★★★ | 3. Cluster |
| F1-S08 | La couche de base et Argo CD | LIBRE | ★★★ | 3. Cluster |
| F1-S09 | Raccrocher l'identité et les secrets | LIBRE | ★★★★ | 3. Cluster |
| F1-S10 | Laisser Argo CD reconstruire la plateforme | LIBRE | ★★★ | 3. Cluster |
| F1-S11 | Remettre les données | LIBRE | ★★★★ | 3. Cluster |
| F1-S12 | Panne : la reconstruction coince | BF | ★★★★ | 3. Cluster |
| F1-S13 | Première livraison en production | LIBRE | ★★★ | 4. Livrer et recetter |
| F1-S14 | Recette Day 0 | LIBRE | ★★★ | 4. Livrer et recetter |
| F1-S15 | Rapport de reconstruction et runbook Day 0 | RED | ★★★ | 4. Livrer et recetter |

**Répartition** : 15 scénarios · 2 break & fix · 2 rédactions (+ le plan de retour arrière de S04 et le compte rendu de dérive de S02, publiés dans le dépôt).

## Ce qui change dans le lab

| Élément | Avant | Après |
|---|---|---|
| `k8s-par1` (2141-2146) | cluster construit au fil des modules 14 à 29 | **reconstruit à blanc** depuis le code, mêmes noms, adresses et VMID ; `k8s-w03` installé par l'usine PXE |
| `lb02`, `dns02` | VMs d'origine | recréées par OpenTofu et Ansible (CI), rien à la main |
| `pxe01` | conservé (M11) | profil de nœud Kubernetes ajouté à l'usine |
| Documentation | — | `docs/day0/` de `plateforme/medisphere` : carte d'amorçage, comptes rendus de dérive, plan de retour arrière, rapport de reconstruction, RB-310 et suivants, ADR-0310 et suivants ; étiquette **`day0-v1`** |

Détails figés : [`PLAN.md`](../../PLAN.md) §4.14.

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check F1 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break F1 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.
