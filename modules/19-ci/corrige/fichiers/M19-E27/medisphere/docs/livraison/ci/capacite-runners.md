# Capacité et disponibilité des runners

| | |
|---|---|
| Ticket | PLAT-2027 (M19-E27) |
| Propriétaire | Équipe Plateforme |
| Code | `plateforme/k8s` : `composants/gitlab-runner/values.yaml`, `ordonnancement/priorite-ci.yaml`, `espaces/ci-jobs/10-quota.yaml` |
| Runbook | RB-193 « saturation des runners » |

## 1. Les trois réglages

| Réglage | Où | Ce qu'il borne |
|---|---|---|
| `concurrent` | global, par **processus** gestionnaire (`values.yaml` : `concurrent`) | jobs simultanés de ce processus, tous `[[runners]]` confondus |
| `limit` | par `[[runners]]` (TOML) | jobs simultanés de cette entrée ; `0` = pas de limite propre (seul `concurrent` joue) |
| `request_concurrency` | par `[[runners]]` (TOML) | requêtes de *long polling* simultanées vers `/api/v4/jobs/request` ; à `1` (défaut), un gestionnaire ne demande qu'un job à la fois, même avec des places libres |

Deux réplicas du gestionnaire = deux **gestionnaires** (`/runners/:id/managers`) du même runner `k8s-par1`, chacun avec ses propres `concurrent`/`limit`/`request_concurrency` : la capacité théorique est **2 × 8 = 16**. GitLab remet chaque job au premier gestionnaire qui le demande : la répartition n'est pas équitable, mais aucun job n'est pris deux fois.

Au-delà de ce que l'espace peut accueillir, deux cas : quota dépassé, l'API **refuse de créer** le pod (`exceeded quota`) et le job échoue aussitôt à la préparation ; mémoire des nœuds insuffisante, le pod est créé mais reste `Pending` (`Insufficient memory`), le gestionnaire attend `poll_timeout` (600 s) puis fait échouer le job (« timed out waiting for pod to start »). D'où : `concurrent` × réplicas ≤ ce que le quota et les nœuds tiennent.

## 2. Calcul de la capacité soutenable

Hypothèses (relevées le AAAA-MM-JJ ; remplace par tes valeurs) :

| Donnée | Valeur |
|---|---|
| Quota de `ci-jobs` (E02) | `requests.memory: 12Gi`, `requests.cpu: 6`, `pods: 20` |
| Demandes d'un pod de job typique | build 256 Mi + helper 64 Mi (+ service PostgreSQL 256 Mi pour `tests-integration`) ≈ **320 Mi** (576 Mi avec service) ; CPU 0,15 (0,25) |
| Mémoire allouable libre des 3 travailleurs (applications, plateforme et buildkitd déduits, `kubectl describe nodes`) | ≈ 3 × 3,5 Gi = 10,5 Gi |
| buildkitd | au-delà de 4 constructions simultanées, chaque construction ralentit nettement (mesure de E23) |

- Par le quota : 12 Gi / 576 Mi ≈ 21 pods (cas défavorable) ; `pods: 20`.
- Par les nœuds : 10,5 Gi / 576 Mi ≈ 18.
- Par buildkitd : les jobs de construction ne sont qu'une partie du pipeline (≈ 1 sur 6 dans celui de MédiAgenda).

**Retenu : 16 jobs simultanés** (2 gestionnaires × `concurrent = limit = 8`), `request_concurrency = 4`. Le runner protégé a son propre quota (`ci-jobs-protege`, 4 jobs).

## 3. Disponibilité

- Deux réplicas répartis par `topologySpreadConstraints` (un par nœud), PDB `maxUnavailable: 1`, mise à jour `maxUnavailable: 0`.
- Arrêt gracieux : à `SIGQUIT`, un gestionnaire ne prend plus de job et attend la fin des siens ; mais Kubernetes envoie `SIGTERM`, qui est un arrêt **forcé** pour GitLab Runner (jobs abandonnés). D'où le `preStop` du chart (`deploymentLifecycle`) qui envoie `SIGQUIT` et attend, dans la limite de `terminationGracePeriodSeconds: 3600`.
- Essai de drainage (AAAA-MM-JJ) : nœud `k8s-w02` drainé pendant un job de 5 min pris par le gestionnaire de ce nœud. Le **gestionnaire** est déplacé (l'autre réplica continue de prendre des jobs) ; le **pod de job** sur `k8s-w02` est un pod nu : `kubectl drain` exige `--force`, et l'expulsion fait échouer le job (« pod … deleted »). Conséquence : on draine un nœud **après** avoir laissé finir les jobs (cordon, attente), RB-193 §4 ; l'option `pod_disruption_budget` de l'exécuteur protégerait les jobs mais bloquerait les drainages : non retenue.

## 4. Priorité

Pods de job en `medisphere-ci` (1000, `preemptionPolicy: Never`) : un job ne déloge jamais un pod applicatif ; un pod `medisphere-standard` ou `medisphere-critique` en attente de place peut déloger un job (le job échoue, il est relancé). Le quota de `ci-jobs` ne dépend pas de la priorité (pas de `scopeSelector` par PriorityClass : une seule classe dans l'espace).

## 5. Mesures (essai `charge`, 20 jobs, `bin/ci-mesurer-pipeline.sh`)

| Configuration | Jobs | Attente médiane | Attente p95 | Durée totale du pipeline |
|---|---|---|---|---|
| Avant : 1 réplica, `concurrent = 10`, `request_concurrency = 1` | 20 | … s | … s | … min |
| Après : 2 réplicas, `concurrent = limit = 8`, `request_concurrency = 4` | 20 | … s | … s | … min |

(Ordre de grandeur attendu : avant, les 10 premiers jobs démarrent en quelques dizaines de secondes, un à un, les 10 suivants attendent une minute de plus ; après, 16 démarrent quasi ensemble, 4 attendent une minute.)

Répartition par gestionnaire (après) : `s_…` : … jobs ; `s_…` : … jobs.

## 6. Seuil

**Attente p95 des jobs de MR de `mediagenda/api` ≤ 60 s** sur une heure ouvrée. Au-delà, deux fois dans la semaine : RB-193. Le module 21 en fera une alerte (métriques du gestionnaire `gitlab_runner_jobs`, `gitlab_runner_concurrent`, et durée d'attente).
