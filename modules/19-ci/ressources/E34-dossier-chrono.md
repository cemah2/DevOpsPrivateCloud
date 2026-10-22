# M19-E34 — Dossier de l'exercice chronométré : MédiAnnuaire dans la chaîne standard

> À ouvrir à **T0**. Note l'heure tout de suite dans la feuille de temps ci-dessous.

## Le besoin (ticket DEV-2034, Julien Petit)

« MédiAnnuaire (`mediagenda/annuaire`, M12-E34) se construit encore avec le pipeline d'urgence du module 12 : gabarits v1, `runner02`, image construite sans provenance. On veut qu'il soit traité exactement comme MédiAgenda et MédiDoc : pipeline par composants, image signée par la chaîne, et qu'il sorte vert du contrôle de conformité de Sophie. Pas de déploiement à faire dans ce ticket. »

## Exigences

| N° | Exigence | Comment c'est vérifié |
|---|---|---|
| 1 | Le `.gitlab-ci.yml` de `mediagenda/annuaire` n'inclut **que** des composants de `plateforme/ci-templates` en **v2.8.0** (ou plus) : `qualite` (Python), `construction-image`, `securite`. Aucun `include: project`/`file` vers les gabarits v1. Tu ne modifies ni `src/` ni `tests/` ; tu peux modifier `pyproject.toml`, `uv.lock`, le `Dockerfile` et le `.gitlab-ci.yml` | configuration fusionnée (API `ci/lint`) |
| 2 | Aucun job sur `runner02` (étiquette `docker`), aucun job privilégié, aucune image `latest` dans le pipeline | jobs du dernier pipeline |
| 3 | Pipeline de `main` vert ; puis étiquette **`v1.1.0`** dont le pipeline publie `registry.par1.medisphere.internal/medisphere/annuaire:v1.1.0`, signée et attestée (SBOM, provenance) **par le runner protégé** | pipelines, Harbor (`cosign tree`) |
| 4 | Pipeline de MR : lint, tests et analyse de l'image, sans publication ; durée totale **< 10 min** | une MR de ton choix |
| 5 | Le projet exige un pipeline réussi pour fusionner et sort **conforme** du contrôle de E32 (lancement manuel du pipeline planifié de `plateforme/outils`) ; le ticket `conformite-ci` du projet, s'il existait, est fermé par l'outil | réglage du projet, ticket |
| 6 | L'ancien pipeline est entièrement retiré (plus de référence à `ctr01`, au registre de travail ni aux gabarits v1) | fichier sur `main` |

Remarques : le composant `qualite` attend `ruff` et `pytest` dans le groupe de dépendances `dev` du projet ; les tests de MédiAnnuaire sont écrits avec `unittest`, que `pytest` sait exécuter. Si ruff signale des écarts dans `src/`, configure ruff dans `pyproject.toml` (règles, exclusions justifiées) plutôt que de toucher au code, et note-le.

## Feuille de temps (à recopier dans le ticket)

| Jalon | Heure | Contenu | Gestes manuels (et pourquoi) |
|---|---|---|---|
| T0 | | Ouverture du dossier | |
| T1 | | `.gitlab-ci.yml` et `pyproject.toml` modifiés, pipeline de MR vert | |
| T2 | | Fusion, pipeline de `main` vert | |
| T3 | | Étiquette `v1.1.0` : image publiée, signée et attestée sur `protege` | |
| T4 | | Réglage du projet, contrôle de conformité vert, `lab/bin/check 19 34` vert | |

## Retour d'expérience (une demi-page, après T4)

- Ce qui t'a pris le plus de temps, et pourquoi (composants, documentation, image, runner protégé ?).
- Ce qui manquait à ta documentation (`docs/livraison/ci/`) ou aux composants (entrées, README) pour qu'une équipe le fasse **seule** : ouvre les MR correspondantes.
- Combien de lignes compte ton `.gitlab-ci.yml` avant et après.
