# M27-E06 — fichiers de `mediagenda/api`

| Fichier | Rôle |
|---|---|
| `migrations/V3__rappel_expand.sql` | *expand* : livré avec la version N de l'API (celle qui gère le rappel) |
| `migrations/V4__rappel_contract.sql` | *contract* : livré avec la version **suivante** (N+1), quand plus rien ne tourne en N−1 |
| `rappel.patch` | code N : modèle `Rappel`, dépôt (colonnes explicites, canal toujours écrit), attribut de trace, tests (`tests/test_rappel.py`) |
| `ci/fumee_n_moins_1.py` | essai de fumée du job `migrations:compatibilite` |
| `.gitlab-ci.yml.extrait-M27-E06` | le job `migrations:compatibilite` |

```
admin@adm01:~/src/mediagenda-api$ git switch -c dev-2806-rappel
admin@adm01:~/src/mediagenda-api$ git apply --index ~/DevOpsPrivateCloud/modules/27-donnees-messaging/corrige/fichiers/M27-E06/mediagenda-api/rappel.patch
admin@adm01:~/src/mediagenda-api$ cp …/M27-E06/mediagenda-api/migrations/V3__rappel_expand.sql migrations/
admin@adm01:~/src/mediagenda-api$ mkdir -p ci && cp …/M27-E06/mediagenda-api/ci/fumee_n_moins_1.py ci/
admin@adm01:~/src/mediagenda-api$ uv run pytest -q && uv run ruff check . && uv run ruff format --check .
```

Le correctif s'applique sur l'état du dépôt à la fin du M26 (correctifs des M22 et M23 compris) ; il ne
touche ni `pyproject.toml` ni `uv.lock` (aucune dépendance nouvelle). `V4` n'est copié que pour la
livraison suivante.
