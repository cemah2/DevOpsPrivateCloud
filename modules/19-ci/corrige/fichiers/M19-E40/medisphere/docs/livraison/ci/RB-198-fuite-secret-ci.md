# RB-198 — Un secret apparaît dans un journal de CI

| | |
|---|---|
| Portée | Tous les projets GitLab de MédiSphère ; variables de CI, jetons de projet, de groupe et de déploiement, clés |
| Déclencheur | Valeur (ou forme dérivée : base64, URL, morceau) d'un secret vue dans un journal de job ou un artefact |
| Rôles | Plateforme (exécution), Sophie Laurent (RSSI, décision et communication), propriétaire du secret |

> Règle : un secret exposé est **compromis**. Il se remplace ; le remasquer ne suffit jamais.

## 1. Confiner (15 min)

- Identifier **tous** les jobs exposés (journaux récents du projet, pipelines planifiés et de MR, artefacts), sans jamais recopier la valeur : comparaison locale (`grep -F`) avec la valeur lue dans une variable shell, puis `unset`.
- Noter les identifiants des jobs et la fenêtre d'exposition dans le journal de l'incident.
- Si la cause est encore active (variable démasquée, `CI_DEBUG_TRACE`, `set -x` dans un composant) : la neutraliser immédiatement (le correctif propre viendra après).

## 2. Remplacer le secret

- Jeton d'accès de projet ou de groupe : `POST …/access_tokens/:id/rotate` (l'ancien est révoqué dans la même opération), nouvelle valeur dans la variable (masquée, protégée ; « masquée et cachée » si personne n'a besoin de la relire).
- Autre secret (robot Harbor, clé, mot de passe) : procédure de rotation de son registre des secrets ; Vault d'abord, puis les consommateurs.
- Vérifier : l'ancien est inutilisable (`active: false`, `revoked: true`, ou essai d'accès refusé).

## 3. Effacer les traces

- `POST /projects/:id/jobs/:job_id/erase` pour chaque job exposé (journal **et** artefacts) ; vérifier que `…/trace` est vide.
- Artefacts publiés ailleurs (registre de paquets, pages) : à retirer aussi.

## 4. Corriger la cause

| Cause | Pourquoi le masquage n'a pas suffi | Correctif |
|---|---|---|
| Variable démasquée | plus de masquage du tout | remasquer, et justifier qui a ce droit (Maintainers) |
| `set -x`, `set -o xtrace` dans un script ou un composant | la trace montre les expansions, y compris les formes dérivées (base64, concaténations) | retirer, publier une nouvelle version du composant ; règle Semgrep dans `securite` |
| `CI_DEBUG_TRACE` / `CI_DEBUG_SERVICES` | trace de débogage du runner : commandes et expansions | supprimer ; n'activer qu'au niveau d'un job, sur une référence sans secret, et effacer le journal ensuite |
| Secret écrit dans un fichier archivé en artefact | les fichiers ne sont pas masqués | ne jamais écrire de secret sur disque hors de `$CI_BUILDS_DIR` temporaire ; vérifier les `artifacts:paths` |

## 5. Communiquer et prévenir

- Réponse à la RSSI : cause, exposition (jobs, fenêtre, qui pouvait lire), actions horodatées, preuve de révocation, prévention.
- Prévention : règles Semgrep (refus de `set -x` et `CI_DEBUG_TRACE`), recherche périodique de motifs de jetons (`glpat-`, `glrt-`, `glcbt-`…) dans les journaux récents, `id_tokens` plutôt que des secrets durables (M25).

Outil : `plateforme/outils/ci/rotation-canari.sh` (modèle : rotation, mise à jour de la variable, effacement des jobs, sans afficher la valeur).
