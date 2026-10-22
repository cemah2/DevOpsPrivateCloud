# formation/ci-labo

Projet d'exercice du module 19 (intégration continue) du workbook MédiSphère.

- `src/labo/` : une petite bibliothèque Python (créneaux de rendez-vous) ;
- `tests/` : ses tests (pytest) ;
- `docs/` : une documentation minimale (sert aux règles `changes:` de M19-E06) ;
- `pyproject.toml` et `uv.lock` : projet géré par `uv` (PLAN §4.8), dépendances verrouillées.

Le `.gitlab-ci.yml` est écrit par toi, exercice après exercice (M19-E04 à E07, puis E10, E21, E22).

En local :

    uv sync --locked
    uv run pytest
