# RB-190 — Un pipeline reste en attente

| | |
|---|---|
| Propriétaire | Équipe Plateforme (Karim Benali) |
| Relu par | Nadia Roussel (astreinte), 2026-10 |
| Déclencheur | « mon pipeline ne démarre pas », job `pending` ou `created` depuis plus de 5 min, alerte de file d'attente (M21) |
| Durée cible | diagnostic ≤ 15 min |
| Liens | RB-191 (runner hors ligne), M19-E05 (anatomie d'un pod de job), M14 RB-14x (pod `Pending`) |

## 1. Périmètre et symptômes

| Ce que voit l'utilisateur | Où | Ce que ça veut dire |
|---|---|---|
| Aucun pipeline après une poussée | *Build > Pipelines* vide | le pipeline n'a pas été **créé** (§2.A) |
| Pipeline « bloqué » avec un message d'erreur de configuration | page du pipeline | YAML ou `include`/`component` invalide (§2.A) |
| Job `created` (gris) | page du job | il attend un job dont il dépend (`needs`, stage précédent) ou un `resource_group` (§2.B) |
| Job `pending` + « *This job is stuck because…* » | page du job | **aucun runner éligible** (§2.C) |
| Job `pending` sans message, longtemps | page du job | runner éligible mais **occupé** (§2.D) |
| Job `running` dont le journal reste à « Preparing the "kubernetes" executor » / « Waiting for pod » | journal du job | le **pod** ne démarre pas (§2.E) |

## 2. Arbre de décision

```
Pipeline créé ?
├── non → A. création (workflow, YAML, droits, CI désactivée)
└── oui → état du job ?
    ├── created → B. dépendances (needs, stage, resource_group, job manuel bloquant)
    └── pending → message « stuck » ?
        ├── oui → C. aucun runner éligible (étiquettes, protection, pause, verrou, hors ligne)
        └── non → D. runner occupé (concurrent, limit, request_concurrency, autres jobs)
                   └── journal « Waiting for pod » → E. pod (quota, LimitRange, Pending, image, Secret, VAP)
                                                      └── pod Running mais job muet → F. dépendances externes
```

Variables du runbook (sur `adm01`) :

```
admin@adm01:~$ export GL=https://git01.par1.medisphere.internal/api/v4
admin@adm01:~$ alias glapi='curl -sSf -H @<(printf "PRIVATE-TOKEN: %s\n" "$(<~/.config/workbook/gitlab-checks.token)")'
admin@adm01:~$ P=mediagenda%2Fapi        # projet concerné, encodé
```

### A. Le pipeline n'est pas créé

| Cause | Constat | Action en astreinte | Jour ouvré |
|---|---|---|---|
| `workflow:rules` excluent l'événement (ex. étiquette, MR) | `glapi "$GL/projects/$P/pipelines?per_page=5"` : aucun pipeline pour le commit ; lire `workflow:` du projet | relancer à la main (*Run pipeline*) sur la branche si le besoin est urgent | corriger `workflow:` par MR |
| Configuration invalide, composant introuvable (`@2.0.0` au lieu de `@v2.0.0`), entrée refusée | pipeline en échec « *yaml invalid* » ; `POST /projects/:id/ci/lint` (jeton `api`) | aucune (pas de correction de code la nuit) ; informer l'équipe | MR de correction |
| CI/CD désactivée, chemin de configuration CI changé | `glapi "$GL/projects/$P" \| jq '.builds_access_level, .ci_config_path'` | aucune | rétablir par l'administrateur, avec l'équipe |
| Auteur bloqué ou sans droit (pipeline planifié, aval multi-projets) | `glapi "$GL/projects/$P/pipeline_schedules"` (propriétaire), message du job déclencheur | — | changer de propriétaire (`take_ownership`) |

### B. Job `created`

| Cause | Constat | Action en astreinte |
|---|---|---|
| Il attend un job (`needs`, stage précédent) | graphe du pipeline ; `glapi "$GL/projects/$P/pipelines/<id>/jobs?per_page=100" \| jq -r '.[] \| "\(.stage) \(.name) \(.status)"'` | traiter le job amont |
| Job manuel **bloquant** en amont (`when: manual` sans `allow_failure`) | statut `manual` en amont | le lancer si c'est voulu (avec le demandeur) |
| `resource_group` occupé | message « *Waiting for resource* » ; `glapi "$GL/projects/$P/resource_groups/<clé>/upcoming_jobs"` | attendre le job qui tient la ressource ; **ne pas** annuler un déploiement en cours |

### C. Aucun runner éligible (« *This job is stuck* »)

```
admin@adm01:~$ glapi "$GL/projects/$P/jobs/<id-job>" | jq '{tag_list, ref, protected: .pipeline.ref, runner}'
admin@adm01:~$ glapi "$GL/runners/all?type=instance_type&per_page=100" \
    | jq -r '.[] | "\(.id) \(.description) \(.status) paused=\(.paused) "'
admin@adm01:~$ glapi "$GL/runners/<id>" | jq '{tag_list, run_untagged, access_level, locked, paused, maximum_timeout}'
admin@adm01:~$ glapi "$GL/runners/<id>/managers" | jq -r '.[] | "\(.system_id) \(.status) \(.version) \(.contacted_at)"'
```

| Cause | Constat | Action en astreinte | Jour ouvré |
|---|---|---|---|
| Étiquette du job inconnue (faute de frappe, `docker` au lieu de `k8s`) | `tag_list` du job ⊄ étiquettes d'un runner en ligne | aucune (le projet corrige) ; **ne pas** ajouter l'étiquette au runner | MR du projet |
| Job **sans** étiquette, runners en `run_untagged: false` | `tag_list` vide | idem | composants (étiquette `k8s`) |
| Seul runner candidat **protégé** (`ref_protected`), référence non protégée | `access_level` du runner, branche non protégée | aucune : c'est le comportement voulu (E24) | expliquer ; branche protégée si légitime |
| Runner en pause | `paused=true` | le réactiver **si** la pause n'est pas une maintenance annoncée (canal Plateforme) | — |
| Runner verrouillé à un autre projet | `locked=true`, projets du runner | — | déverrouiller ou rattacher, avec Karim |
| Gestionnaire hors ligne (`status: offline`, `contacted_at` ancien) | API ci-dessus ; `kubectl -n gitlab-runner get pods` ; journaux | RB-191 : `kubectl -n gitlab-runner rollout restart deploy/gitlab-runner` (sans perte : les jobs en cours finissent, `terminationGracePeriodSeconds`) | cause racine (jeton révoqué, `git01:443` filtré, certificat) |
| Délai maximal du runner < `timeout` du job | `maximum_timeout` | — | ajuster le job |

### D. Runner éligible mais occupé

```
admin@adm01:~$ kubectl --context k8s-par1 -n ci-jobs get pods -l medisphere.internal/ci=job
admin@adm01:~$ kubectl --context k8s-par1 -n gitlab-runner logs deploy/gitlab-runner --since=15m | grep -Ei 'concurrent|limit|request|job'
admin@adm01:~$ kubectl --context k8s-par1 -n gitlab-runner get cm gitlab-runner -o jsonpath='{.data.config\.template\.toml}' | grep -E 'concurrent|limit|request_concurrency'
```

| Cause | Constat | Action en astreinte | Jour ouvré |
|---|---|---|---|
| `concurrent`/`limit` atteint (pic de pipelines) | autant de pods de job que la limite ; journaux « *limit reached* » | attendre ; annuler des pipelines **dépassés** (`interruptible`) avec l'accord des équipes | capacité (E27) |
| Un job qui ne se termine pas occupe une place | pod de job ancien (`kubectl get pods --sort-by=.metadata.creationTimestamp`) | annuler **ce** job (GitLab), jamais supprimer le pod à la main | délai du job |
| `request_concurrency` trop bas (gestionnaire lent à prendre les jobs) | journaux : requêtes `jobs/request` espacées | — | réglage (E27) |

### E. Le pod de job ne démarre pas

```
admin@adm01:~$ kubectl --context k8s-par1 -n ci-jobs get events --sort-by=.lastTimestamp | tail -20
admin@adm01:~$ kubectl --context k8s-par1 -n ci-jobs describe pod <runner-…-project-…-concurrent-…>
admin@adm01:~$ kubectl --context k8s-par1 -n ci-jobs describe quota quota-ci ; kubectl --context k8s-par1 -n ci-jobs get limitrange limites-ci -o yaml
admin@adm01:~$ kubectl --context k8s-par1 top nodes
```

| Cause | Constat | Action en astreinte | Jour ouvré |
|---|---|---|---|
| Quota de `ci-jobs` épuisé | événement `FailedCreate … exceeded quota: quota-ci` ; le pod **n'existe pas** | annuler des jobs dépassés ; ne **pas** relever le quota la nuit sans Claire | revoir quota et demandes (E27) |
| Demande hors des bornes du LimitRange (`KUBERNETES_*` d'un job) | `forbidden: maximum memory usage per Container` | — | corriger le job |
| Pas de place sur les nœuds | pod `Pending`, `FailedScheduling: Insufficient memory` | vérifier qu'aucun composant temporaire (SonarQube, Jenkins) ne tourne en trop ; le mettre à 0 si c'est le cas, avec l'accord de l'équipe | capacité |
| Image introuvable ou refusée (`ErrImagePull`, `ImagePullBackOff`, refus de la VAP `medisphere-images`) | événements du pod ; image hors Harbor ou sans version | — (le pod finit en échec, `poll_timeout`) | corriger l'image ; Harbor (RB-13x) si c'est lui |
| Secret ou ConfigMap monté absent (`buildkit-client`, `medisphere-racine`) | `FailedMount` | recréer depuis le code (`helmfile -l composant=buildkitd apply`, `task appliquer`) | cause (suppression ?) |
| Compte de service `ci-job` absent | `FailedCreate … serviceaccount "ci-job" not found` | `task appliquer` (espaces) | — |

### F. Le pod tourne, le job ne progresse pas

Clonage qui pend (`git01:443` filtré, certificat), cache S3 injoignable (`s3-01:8333`), buildkitd
injoignable ou saturé (`kubectl -n buildkit logs deploy/buildkitd`), Harbor lent : voir RB-191 à RB-19x
et les journaux du conteneur `helper` (`kubectl -n ci-jobs logs <pod> -c helper`).

## 3. Ce qu'on a le droit de faire en astreinte

Autorisé (réversible, sans perte) : réactiver un runner en pause non annoncée ; redémarrer le
gestionnaire (`rollout restart`) ; annuler des jobs ou pipelines **dépassés** ; mettre à 0 un composant
**temporaire** (SonarQube, Jenkins) ; réappliquer depuis `main` un objet de plateforme disparu.
Interdit la nuit : modifier `.gitlab-ci.yml` ou un composant, changer étiquettes, quotas, LimitRange
ou droits d'un runner, supprimer des pods de job à la main, désactiver la protection d'une branche.

## 4. Communication

- Canal Plateforme, à l'ouverture : « *CI : pipelines de <projet> en attente depuis HH:MM, diagnostic en cours (RB-190 §x). Prochain point dans 30 min.* »
- À la résolution : cause, action, pipelines relancés, ce qui reste pour le jour ouvré (ticket INC).
- Si plusieurs projets sont touchés : prévenir Julien Petit (équipes de développement) et Claire Morel.

**Sortie** : un pipeline de test (`formation/ci-labo`, *Run pipeline*) passe de `pending` à `running`
en moins de 60 s, et les pipelines bloqués sont relancés ou annulés avec leurs équipes.

## 5. Pièges

- Ajouter une étiquette au runner pour « débloquer » un job : on ouvre le runner à des jobs non prévus.
- Relever le quota de `ci-jobs` : les jobs démarrent, puis ce sont les applications qui manquent de place.
- Un quota dépassé ne crée **pas** de pod `Pending` : le pod n'existe pas, l'erreur est dans les
  événements du gestionnaire (`FailedCreate`), pas dans `kubectl get pods`.
- Supprimer un pod de job : GitLab croit le job vivant jusqu'au délai ; annule le job dans GitLab.
- « *This job is stuck* » s'affiche aussi quand le **seul** runner compatible est hors ligne.
- Un job d'une branche non protégée qui vise l'étiquette `protege` ne sera **jamais** pris (E24).

## 6. Documentation

- GitLab : *Troubleshooting CI/CD* (« job stuck »), API *Runners* (`/runners/:id/managers`), API *Resource groups*.
- GitLab Runner : *Kubernetes executor* (`poll_timeout`, ressources), *Advanced configuration* (`concurrent`, `limit`, `request_concurrency`).
- Kubernetes : *Resource Quotas*, *Limit Ranges*, *Debug Pods*.
