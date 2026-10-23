---
chg: CHG-3405
titre: "Composants de plateforme : Argo CD, Kyverno, CloudNativePG (ou correctives) et KEDA par GitOps"
categorie: normal
statut: termine
decision: go
demandeur: Karim Benali
executant: équipe Plateforme
approbateurs: Claire Morel, Karim Benali, Sophie Laurent
fenetre-debut: 2026-11-12T20:00:00+01:00
fenetre-fin: 2026-11-12T23:00:00+01:00
mesure-source: cluster
mesure-groupes: ""
mesure-debut: 2026-11-12T20:00:00+01:00
mesure-fin: 2026-11-12T22:30:00+01:00
mesure-objectif-s: 30
mesure-interruption-s: 0
---

# CHG-3405 — Composants de plateforme par GitOps

> Fiche de **référence** (lab imaginé). Les versions réellement publiées le jour où tu fais F4 décident
> du contenu : au relevé (23/10/2026), Argo CD 3.6 était annoncée pour le 03/11, Kyverno 1.20 pour
> novembre, CloudNativePG 1.31 non publiée. Règle : une mineure seulement si **publiée** et déclarée
> compatible avec 1.36 (et, si possible, la cible suivante) ; sinon la dernière corrective.

## 1. Résumé

Trois montées, une par vague, chacune par MR : **Argo CD 3.5 → 3.6** (Helmfile, `plateforme/k8s`), **Kyverno 1.19 → 1.20** (`plateforme/charts-miroir` puis `plateforme/gitops`), **CloudNativePG** dernière corrective 1.30 (1.31 non publiée ce jour-là : la mineure attend) ; et **KEDA** à la mineure qui déclare 1.37 (prépare la révision de CHG-3403).

## 2. Lecture des notes de version (avant toute MR)

| Composant | Lu | Ce qui touche MédiSphère | Action |
|---|---|---|---|
| Argo CD 3.6 | guide « v3.5 to 3.6 » (operator-manual/upgrading), notes du chart `argo/argo-cd` | à relever : changements de valeurs par défaut, RBAC, suivi des ressources | `helmfile diff` relu ligne à ligne ; valeurs ajustées |
| Kyverno 1.20 | notes de version 1.20, CHANGELOG du chart | **`ClusterPolicy` supprimée** : sans effet si aucune n'existe (M26 : politiques CEL seulement) | `outils/inventaire-api-supprimees.sh` : 0 objet |
| CloudNativePG 1.30.x | notes de la corrective ; pour 1.31 (plus tard) : **`barmanObjectStore` supprimé** | aucun `Cluster` n'utilise l'archivage intégré (M16 : plugin Barman Cloud) | même script : 0 objet ; plugin compatible |
| KEDA | notes de version de la mineure, matrice Kubernetes | à relever : `ScaledObject` de MédiNotif (déclencheur `rabbitmq`) | essai en recette d'abord |

## 3. Risque

| Risque | Probabilité | Gravité | Réduction | Signal |
|---|---|---|---|---|
| Argo CD indisponible pendant sa propre montée | certaine (courte) | faible : les applications tournent sans lui | aucune synchronisation de prod en même temps | `argocd-server` prêt |
| Webhook Kyverno indisponible (« Fail ») pendant le roulement | faible | forte (admissions refusées dans les espaces visés) | 3 réplicas + PDB du chart, roulement | sonde, événements `FailedCreate` |
| CRD montées qui ne redescendent pas | certaine | moyenne (retour arrière limité) | lecture : la version précédente accepte-t-elle les CRD nouvelles ? | — |
| Redémarrage des instances PostgreSQL à la montée de l'opérateur | moyenne | faible (bascule) | RB-164 : mise à jour en place du gestionnaire d'instance | sonde, 5xx prod |

## 4. Fenêtre

Jeudi 12/11/2026, 20 h-23 h. Hors gel. Trois vagues séparées de 20 minutes de mesure : on doit pouvoir attribuer une erreur à **un** composant.

## 5. Préparation

- [x] Inventaire des API supprimées : 0 `ClusterPolicy`, 0 `barmanObjectStore`, 0 `ScheduledBackup` sans `method: plugin`.
- [x] `plateforme/charts-miroir` : entrées Kyverno et KEDA (versions, empreintes vérifiées), pipeline vert, charts signés dans Harbor ; anciennes versions **conservées**.
- [x] MR `plateforme/k8s` (Argo CD, CNPG), `plateforme/gitops` (Kyverno, KEDA) : pipelines verts (`validation` avec les schémas actuels), non fusionnées.
- [x] Essai de chaque chart par `helm template` avec nos valeurs ; `helmfile diff` relu.
- [x] Sauvegarde Argo CD (`argocd-export`, M20-E28) de la nuit ; sauvegarde `mediagenda-db` `Completed`.
- [x] Sonde lancée (RB-340), objectif 30 s.

## 6. Étapes

| # | Étape | Comment | Contrôle de passage |
|---|---|---|---|
| 1 | Go/no-go | ligne de base 30 min à 0 s | vert |
| 2 | Vague 1 — Argo CD | fusion MR `plateforme/k8s`, `helmfile -e par1 -l composant=argocd apply` | `argocd-*` prêts, toutes les Applications `Synced/Healthy`, webhook GitLab reçu |
| 3 | Vague 2 — Kyverno | fusion MR `plateforme/gitops` (Application `kyverno`), synchronisation | 3 réplicas prêts, `ValidatingPolicy` toutes `Ready`, rapports à jour, pod de test signé accepté en recette, non signé refusé |
| 4 | Vague 3 — CloudNativePG | fusion MR `plateforme/k8s`, `helmfile -e par1 -l composant=cnpg apply` | opérateur prêt, `kubectl cnpg status` de chaque base, archivage `ContinuousArchiving=True` |
| 5 | Vague 4 — KEDA (recette d'abord) | MR `plateforme/gitops` | `ScaledObject` `medinotif` `Ready` en recette puis prod, mise à l'échelle sur la file |
| 6 | Après | `paquet schemas-crd` republié (nouvelles CRD) ; matrice CHG-3403 mise à jour | — |

## 7. Critères d'abandon

Une vague qui dépasse 30 s d'erreur cumulées ou laisse une Application `Degraded` plus de 10 min : retour arrière de **cette** vague, les suivantes sont reportées.

## 8. Retour arrière

- **Argo CD** (Helmfile) : revert de la MR, `helmfile apply` ; ses CRD restent dans la version montée (à vérifier compatibles avec 3.5 dans le guide de montée).
- **Applications gérées par Argo CD** (Kyverno, KEDA) : **revert Git** (la vérité reste dans Git), pas le « rollback » de l'interface (refusé quand la synchronisation automatique est active, et il désynchroniserait Git du cluster) ; les CRD ne redescendent pas : une CRD qui a reçu une nouvelle version stockée garde les objets dans cette version.
- **CNPG** : revert + `helmfile apply` ; les instances déjà mises à jour gardent leur gestionnaire tant qu'elles ne redémarrent pas.
- Testé : revert de Kyverno essayé en recette (`wb-essais`) sur un cluster jetable ? **Non** : retour arrière testé dans sa logique seulement (limite écrite).

## 9. Communication

Annonce J-2 (Julien, Inès, Nadia) : « Argo CD indisponible quelques minutes, ne fusionnez pas de promotion entre 20 h et 23 h ».

## 10. Mesure de l'interruption

| Moment | Fenêtre | Secondes d'erreur cumulées | Requêtes en erreur (k6) | p95 MédiAgenda prod | Remarques |
|---|---|---|---|---|---|
| avant | 19 h 30 → 20 h 00 | 0 | 0 | 40 ms | |
| pendant | 20 h 00 → 22 h 30 | 0 | 0 | 44 ms | aucune vague n'a touché le chemin des requêtes |
| après | 22 h 30 → 23 h 00 | 0 | 0 | 41 ms | |

## 11. Journal

20 h 05 Argo CD (5 min, interface indisponible 40 s) ; 20 h 35 Kyverno (roulement 4 min, aucun refus d'admission) ; 21 h 10 CNPG corrective (opérateur seul, instances en place) ; 21 h 45 KEDA recette puis prod.

## 12. Clôture et revue

Réussi, 0 s. CloudNativePG 1.31 reportée (non publiée) : PLAT-3405-1. Matrice CHG-3403 : Argo CD et KEDA passent en « D ».
