# CHG-2026 — Montée de GitLab, des runners et de l'agent en 19.5

| | |
|---|---|
| Demandeur | Claire Morel |
| Exécutant | <MOI> ; en appui : Karim Benali |
| Fenêtre | mardi AAAA-MM-JJ, 07:00-08:00 ; annonce J-3 et J-1 (courriel `plateforme@`, équipes) |
| Périmètre | `git01` (GitLab CE 19.4.z → 19.5.z) ; runners `k8s-par1` et `k8s-par1-protege` (chart 0.93 → 0.94) ; `runner01`, `runner02` (paquets 19.4 → 19.5) ; agent `k8s-par1` (chart 2.32 → 2.33, `wss://` → `grpcs://`) |
| Hors périmètre | Kubernetes, Harbor, composants (sauf correctif `CI_RUNNER_TAGS` si nécessaire) |
| Point de non-retour | la réouverture de GitLab aux utilisateurs (fin de l'étape 4) |

## Lecture préalable (J-7)

| Sujet | Effet sur nous | Action |
|---|---|---|
| 19.5 = arrêt obligatoire du chemin de montée | on ne la saute pas ; la 19.8 sera le prochain | calendrier : 19.8 en janvier |
| Migrations d'arrière-plan | la 19.4 doit avoir fini les siennes | contrôle à J-1 et à H-10 min |
| Agent 19.5 : `grpcs://` par défaut | notre agent est en `wss://` explicite : il continue de marcher ; on migre (étape 6) | valeur du chart |
| `CI_RUNNER_TAGS` rendue en JSON strict (changement amont à confirmer dans les notes de la 19.5 ; `CI_JOB_TAGS`, 19.3, est déjà un tableau JSON) | nos étiquettes sont simples (`k8s`, `protege`…) : sortie identique ; aucun script ne découpe ces variables (recherche ci-dessous) | job témoin `etiquettes-job` |
| Runner 19.5 (exécuteur Kubernetes) : message explicite quand le *helper* est tué par manque de mémoire ; classe QoS corrigée | aucun réglage à changer | — |
| Chart 0.94 : `image.image` → `image.repository` (ancienne clé encore lue) | deux fichiers de values | MR `values-runner-0.94` |

Recherche des usages : `grep -rn 'CI_JOB_TAGS\|CI_RUNNER_TAGS'` sur les clones de `plateforme/ci-templates`, `mediagenda/*`, `medidoc/*`, `formation/ci-labo` (et la recherche de code de GitLab, si active) : aucun hors du job témoin.

## Déroulé

| # | Étape | Durée estimée | Critère de passage | Retour arrière |
|---|---|---|---|---|
| 0 | Vérifs : santé, migrations = 0, aucun pipeline de `main`/étiquette en cours | 10 min | tout vert | report |
| 1 | Sauvegarde PBS de `git01` (tâche manuelle) **vérifiée** ; `gitlab-backup create` + secrets ; `qm snapshot 1004 avant-19-5` | 15 min | sauvegarde « ok » dans PBS ; archive dans `/var/opt/gitlab/backups` | — |
| 2 | Pause des 4 runners (API `PUT /runners/:id paused=true`) | 2 min | plus aucun job en cours | réactiver |
| 3 | `apt-get install gitlab-ce=19.5.Z-ce.0` (après `unhold`), `hold` | 15 min | sortie sans erreur, `gitlab-ctl status` | `qm rollback 1004 avant-19-5` |
| 4 | Contrôles GitLab (RB-192 §4) puis **réouverture** | 10 min | tous les contrôles verts | jusqu'ici : rollback ; après : RB-010 |
| 5 | Runners : `gitlab-runner`, puis `gitlab-runner-protege`, puis `runner01`, `runner02` ; réactivation un par un | 15 min | gestionnaire en 19.5 en ligne, job témoin vert | release précédente (`helmfile` sur le commit d'avant), paquet 19.4 (le runner accepte un GitLab plus récent d'une mineure) |
| 6 | Agent : chart 2.33, puis `kasAddress` en `grpcs://` | 10 min | agent connecté, `deployer-dev` vert | `wss://` (commit précédent) |
| 7 | Pipelines témoins, compte rendu | 15 min | MR + étiquette `mediagenda/api`, pipeline `mediagenda/deploiement` verts | — |

## Compte rendu (à remplir)

| Étape | Début | Fin | Écart / remarque |
|---|---|---|---|
| 1 | | | taille de `gitlab-backup` : … Go, durée … |
| 3 | | | durée des migrations : … |
| 5 | | | |
| 6 | | | |

Instantané `avant-19-5` supprimé le AAAA-MM-JJ (après 48 h sans incident).
