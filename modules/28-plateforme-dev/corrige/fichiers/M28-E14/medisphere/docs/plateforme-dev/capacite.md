# Capacité, budgets et priorités — k8s-par1

> Rédigé en M28-E14 (PLAT-2914). Propriétaire : équipe Plateforme. Revue trimestrielle des budgets (et à chaque nouvelle équipe). Chiffres du lab de référence : remplace-les par ton bilan.

## 1. Bilan (relevé du 2026-11-03)

| Nœud | Allouable CPU / mémoire | Requests CPU / mémoire | Limits mémoire | Consommation p95 7 j (CPU / mémoire) |
|---|---|---|---|---|
| k8s-w01 | 3,8 / 9,1 Gi | 2,9 (76 %) / 6,8 Gi (75 %) | 11,2 Gi (123 %) | 1,1 / 5,9 Gi |
| k8s-w02 | 3,8 / 9,1 Gi | 3,1 (82 %) / 7,0 Gi (77 %) | 12,0 Gi (132 %) | 1,3 / 6,2 Gi |
| k8s-w03 (`dedie=bdd`) | 3,8 / 9,1 Gi | 1,9 (50 %) / 5,1 Gi (56 %) | 6,0 Gi (66 %) | 0,6 / 4,4 Gi |

Lecture : la réservation CPU (≈ 70 %) est trois fois la consommation : les `requests` des composants de plateforme et de MédiAgenda sont surévaluées (rapport VPA). La sur-réservation **mémoire** (limits > allouable sur w01 et w02) est le vrai risque : en cas de pic simultané, le kubelet évince (§ 4).

## 2. Budgets des locataires (GlobalResourceQuota « budget » de Capsule)

| Locataire | requests.cpu | requests.memory | limits.memory | pods | PVC | stockage | Espaces max |
|---|---|---|---|---|---|---|---|
| mediagenda (dev, recette, prod, bases comprises) | 5 | 10 Gi | 15 Gi | 60 | 10 | 60 Gi | 8 |
| medinotif | 2 | 3 Gi | 4 Gi | 30 | 10 | 60 Gi | 6 |
| medidoc | 3 | 6 Gi | 9 Gi | 40 | 10 | 60 Gi | 6 |
| **Total** | 10 (≈ 88 % de l'allouable des trois travailleurs) | 19 Gi (70 %) | 28 Gi (103 %) | | | | |

Le reste (≈ 1,4 vCPU, 8 Gi) est la part de la **plateforme** (supervision, journaux, Argo CD, KEDA, Capsule, portail…), qui n'est pas un locataire. Les quotas d'espace (`plateforme/k8s/espaces/*/10-quota.yaml`) restent en place : une création doit passer le quota de l'espace **et** le budget du locataire. Révision : MR sur `plateforme/k8s/locataires/<locataire>.yaml`, relue par Claire Morel si le total dépasse 90 % de l'allouable.

## 3. Classes de priorité

| Classe | Valeur | Préemption | Usage | Qui la pose |
|---|---|---|---|---|
| `medisphere-critique` | 100000 | oui | production : Rollout `mediagenda`, `mediagenda-db` (prod), MédiNotif prod | overlays prod, CNPG `priorityClassName` |
| `medisphere-standard` | 10000 | oui | recette, dev, libre-service | défaut des locataires (Capsule `priorityClasses.default`) |
| `medisphere-ci` | 1000 | non | pods de job de la CI | runners (M19) |
| `medisphere-lot` | 100 | non | traitements par lots, essais de charge (M29) | explicite dans le manifeste |
| *(aucune)* | 0 | — | composants de plateforme non classés | — |

Pas de `globalDefault` : une valeur globale aurait touché les composants de plateforme au prochain redémarrage, sans revue.

**Risque écrit** : un pod `standard` ou `critique` qui ne trouve pas de place peut préempter des pods de priorité 0 — donc des composants de plateforme (Argo CD, Kyverno, Prometheus…). Mesures : budgets (§ 2) qui gardent une marge, classe `lot` sans préemption, alerte « pods critiques en attente ». Évolution prévue : une classe `medisphere-plateforme` (entre `standard` et `critique`) pour les composants qui supportent mal un déplacement, posée chart par chart (ADR à écrire avant le F2).

## 4. Préemption et éviction

- **Préemption** (ordonnanceur) : un pod en attente de priorité supérieure fait supprimer des pods de priorité **inférieure** sur un nœud choisi pour en libérer la place ; les PDB sont respectés « au mieux » (pas garanti) ; délai de grâce respecté. Essai (E14, `wb-essais`) : 6 pods `lot` de 1 Gi sur k8s-w01, un pod `standard` de 2 Gi → 2 pods `lot` préemptés (`Preempted` dans les événements), le pod `standard` démarre en 11 s. L'inverse (`lot` contre `standard`) : rien, le pod `lot` reste `Pending`.
- **Éviction** (kubelet, pression mémoire ou disque) : le kubelet tue d'abord les pods qui **dépassent leurs requests**, par priorité croissante puis par dépassement ; il **ignore les PDB**. D'où la règle : des `requests` mémoire justes (rapport VPA), et pas de pod sans `requests` (LimitRange de chaque espace).

## 5. Recommandations du VPA

`outils/recommandations-vpa.sh` (plateforme/k8s) : le premier lundi du mois, `--seuil 30 --mr`. La MR « Recommandations du VPA » est relue en réunion de plateforme ; chaque ligne devient une MR de l'équipe dans son dépôt de déploiement (requests ; limite mémoire ≥ 1,5 × la cible). Le VPA reste en `Off` partout (ADR-0280).

## 6. Tableau de bord

Grafana « Capacité et locataires » (`plateforme-capacite-locataires`) : réservation par nœud et par locataire, quotas d'espace, pods en attente par priorité, évictions et préemptions, recommandations du VPA (si kube-state-metrics les exporte : voir `kps/values.yaml`).
