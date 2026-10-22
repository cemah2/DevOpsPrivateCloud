# Composant `release`

semantic-release sur la branche par défaut **protégée** : analyse des Conventional Commits, étiquette
`vX.Y.Z`, notes de version (selon les greffons de ton `.releaserc.json`, M01-E25).

```yaml
include:
  - component: $CI_SERVER_FQDN/plateforme/ci-templates/release@v2.0.0
```

- Le job `release:semantic-release` n'existe que si `.releaserc.json` est présent.
- `GITLAB_TOKEN` : jeton de projet `bot-release` (Maintainer, `api` + `write_repository`),
  variable **protégée et masquée** du projet.
- Paquets npm installés à chaque job, versions exactes en entrée `paquets` (Renovate les suit).
- Pour un dépôt de **composants** (ce dépôt), le `.releaserc.json` ne garde que
  `@semantic-release/commit-analyzer` : la release elle-même est créée par le mot-clé `release:`
  du pipeline d'étiquette, seule voie de publication au catalogue.
