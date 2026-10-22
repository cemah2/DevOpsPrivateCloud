# Sous le capot : du `git push` au pod de job

> Compte rendu de M19-E44 (PLAT-2044). Projet d'étude : `formation/ci-labo`, branche `capot`.
> Job étudié : `<ID-JOB>` (pipeline `<ID-PIPELINE>`), runner `k8s-par1`, nœud `<NŒUD>`.
> Règle : des heures, des routes, des statuts, des durées, des noms de classes ; **jamais** un jeton,
> une URL signée ou une ligne de journal recopiée en entier.

## Réception du push

| Heure | Où | Ce qui se passe | Preuve (ligne raccourcie) |
|---|---|---|---|
| | gitlab-shell | | |
| | API interne (`/internal/allowed`) | | |
| | Gitaly, *hook* `post-receive` | | |
| | API interne (`/internal/post_receive`) | | |

## Création du pipeline

| Heure | Travail Sidekiq | Ce qu'il fait | `correlation_id` / durée |
|---|---|---|---|

Durée poussée → job `pending` : …

## File d'attente et runner (long polling)

- Durée de maintien d'une requête `POST /api/v4/jobs/request` sans job : …
- Requête qui reçoit le job (statut, durée) : …
- Lignes du gestionnaire (prise du job, création du pod) : …

## Le pod de job (Kubernetes)

- Conteneurs, conteneurs d'initialisation, volumes, compte de service, jeton monté ou non, `activeDeadlineSeconds`, priorité : …
- Requêtes du compte de service du gestionnaire dans le journal d'audit (heure, verbe, ressource, sous-ressource, code) : …

## Artefacts et fin du job

- Envoi du journal (`PATCH …/trace`) : …
- Téléversement de `capot.txt` (`authorize`, puis `artifacts`) : …
- État final (`PUT /jobs/:id`) et emplacement de l'artefact : …

## Réponses aux questions

1. …
