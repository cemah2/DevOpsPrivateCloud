# Composant `qualite`

Messages de commit (`qualite:commitlint`), lint (`qualite:lint`) et tests (`qualite:tests`) d'un
projet **Python** (uv, ruff, pytest) ou **Go** (`gofmt`, `go vet`, `go test` par gotestsum).

```yaml
include:
  - component: $CI_SERVER_FQDN/plateforme/ci-templates/qualite@v2.0.0
    inputs:
      langage: python          # ou go
      repertoire: "."          # sous-dossier du projet, si besoin
```

- Python : `pyproject.toml` et `uv.lock` commités, `ruff` et `pytest` dans le groupe `dev`
  (`uv add --dev ruff pytest`). `uv sync --locked` refuse un verrou désynchronisé.
- Rapports : JUnit (`rapport-tests.xml`, onglet *Tests*), Code Quality de ruff (Python).
- Aucun job sur les étiquettes : le pipeline de `main` a déjà tout vérifié.
- `commitlint: false` pour un dépôt qui n'applique pas les Conventional Commits.

Entrées : voir l'en-tête `spec:inputs` de [`template.yml`](template.yml) ou la page du catalogue.
