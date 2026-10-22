# RB-194 — Un pipeline ne se déclenche pas

| | |
|---|---|
| Portée | Tous les projets GitLab de MédiSphère |
| Déclencheur | Commit, MR, étiquette ou planification sans pipeline, et sans erreur visible |
| Auteur / relecture | Équipe Plateforme (M19-E41) / Karim Benali |

Un pipeline qui n'existe pas n'a pas de journal : la preuve est dans la configuration et les réglages.

## 1. Prouver l'absence

```
gl "projects/$P/pipelines?sha=<SHA>"            # rien pour ce commit ?
gl "projects/$P/pipelines?source=schedule&per_page=5"
```

## 2. Causes, preuves, correctifs

| Cause | Preuve | Correctif |
|---|---|---|
| Fonction CI/CD désactivée | `GET /projects/:id` → `builds_access_level: disabled` (l'onglet CI/CD disparaît) | `enabled` ; qui a les droits Maintainer ? |
| Chemin de configuration faux | `GET /projects/:id` → `ci_config_path` vers un fichier absent | valeur par défaut, ou déplacer le fichier **et** le réglage dans la même MR |
| `workflow:rules` qui ne retiennent pas cette source | création manuelle : « Pipeline filtered out by workflow rules » ; `POST /projects/:id/ci/lint` (`dry_run`, `ref`) | règles qui gardent les pipelines de branche et évitent les doublons (M19-E06) ; dans un composant : nouvelle version |
| `rules` de tous les jobs fausses (aucun job retenu) | `ci/lint` en `dry_run` : liste de jobs vide | corriger les règles |
| `[skip ci]` / `ci.skip` | message du commit, options de `git push` | — |
| Pipeline planifié dont le propriétaire est bloqué ou parti | `GET /projects/:id/pipeline_schedules` → `owner.state` | *Take ownership* par un membre permanent ou un compte de service d'équipe |

## 3. Règle d'équipe : propriétaires des pipelines planifiés

- Un pipeline planifié appartient à un membre **permanent** de l'équipe ou au compte de service de l'équipe (`svc-ci-<équipe>`), jamais à un stagiaire ou à un prestataire.
- Tout départ déclenche la reprise des pipelines planifiés de la personne (liste par l'API, *take ownership*), avant le blocage du compte.
- Contrôle hebdomadaire (M19-E32) : propriétaires bloqués ou non membres signalés par une issue.

## 4. Vérifier

Un commit sur `main` crée un pipeline ; une MR ne crée pas de doublon ; le prochain pipeline planifié apparaît à l'heure (ou `POST …/pipeline_schedules/:id/play`).
