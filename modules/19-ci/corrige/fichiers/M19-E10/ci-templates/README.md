# plateforme/ci-templates — composants CI/CD de MédiSphère

Composants CI/CD versionnés de l'équipe Plateforme, publiés dans le **catalogue CI/CD** de `git01`
(*Explore > CI/CD Catalog*). Les gabarits v1 (inclus par `include: project`) ont quitté `templates/`
pour `gabarits-v1/` en v2.0.0 : GitLab prend **tout** fichier de `templates/` pour un composant, et
`templates/qualite.yml` aurait masqué `templates/qualite/template.yml`. Les projets pas encore
migrés gardent leur référence épinglée (`ref: v1.x.y`) et ne voient pas ce changement ; la v1 est
gelée.

## Utiliser un composant

```yaml
include:
  - component: $CI_SERVER_FQDN/plateforme/ci-templates/qualite@v2.0.0
    inputs:
      langage: python
```

- **Épingle une version complète** (`@v2.0.0` : l'étiquette exacte, préfixe `v` compris). `@2` ou
  `@2.0` prennent la dernière version compatible publiée au catalogue ; `@~latest` la toute dernière
  (ruptures comprises) : réservé aux essais. `@2.0.0` **ne fonctionne pas** : aucune étiquette ne
  s'appelle ainsi.
- Les entrées (`inputs`) sont décrites dans l'en-tête `spec:inputs` de chaque composant et sur sa
  page du catalogue ; une entrée inconnue ou d'un mauvais type fait échouer la **création** du
  pipeline (message dans *Build > Pipelines*, jamais dans un job).
- Les jobs sont nommés `<composant>:<action>` ; les jobs d'environnement portent le nom de
  l'environnement (`deployer-dev`, `promouvoir-dev`). Un projet peut surcharger un job en
  redéfinissant une clé (ex. `variables:`) sous le même nom.
- Le `workflow:` et les `stages:` appartiennent au projet : aucun composant n'en définit.

## Composants

| Composant | Jobs | Rôle | Documentation |
|---|---|---|---|
| `qualite` | `qualite:commitlint`, `qualite:lint`, `qualite:tests` | Messages de commit, lint et tests (Python ou Go), rapport JUnit | [templates/qualite/README.md](templates/qualite/README.md) |
| `construction-image` | `image:hadolint`, `image:construction`, `image:publication` | Construction par buildkitd (archive OCI + provenance), publication par empreinte | [templates/construction-image/README.md](templates/construction-image/README.md) |
| `securite` | `securite:trivy`, `securite:sbom`, `securite:signature`, `securite:verification` | Analyse bloquante, SBOM, signature Cosign, vérification | [templates/securite/README.md](templates/securite/README.md) |
| `deploiement` | `deploiement:valider` | Rendu Kustomize et `kubeconform` de chaque overlay | [templates/deploiement/README.md](templates/deploiement/README.md) |
| `release` | `release:semantic-release` | semantic-release sur `main` protégée : étiquette `vX.Y.Z` (remplace le gabarit v1 `release.yml` de `runner01`) | [templates/release/README.md](templates/release/README.md) |

Stages utilisés par défaut : `lint`, `test`, `construction`, `analyse`, `publication`, `signature`, `release`.

## Publier une version

1. MR avec des commits conventionnels ; le pipeline teste les composants **depuis le commit de la
   MR** (`@$CI_COMMIT_SHA`) sur les échantillons de `tests/`.
2. À la fusion sur `main`, semantic-release calcule la version et pose l'étiquette `vX.Y.Z` (rien
   d'autre : pas de release par l'API, qui ne serait pas publiée au catalogue).
3. Le pipeline de l'étiquette rejoue les tests puis le job `publier-catalogue` crée la release par
   le mot-clé `release:` : la version apparaît au catalogue.

Une rupture (entrée renommée ou supprimée, job renommé, comportement par défaut changé) est un
`feat!:` ou porte `BREAKING CHANGE:` : nouvelle majeure. Les projets montent par MR (Renovate).

## Exigences

- Runner `k8s-par1` (étiquette `k8s`) : `BUILDKIT_HOST`, `BUILDKIT_TLS_DIR`, racine MédiSphère
  (`/etc/medisphere/ca/medisphere-root-ca.crt`), cache S3 (M19-E04 à E08).
- Images : uniquement Harbor (`registry.par1.medisphere.internal`), étiquette **et** empreinte.
- Variables protégées : `HARBOR_ROBOT_USER`, `HARBOR_ROBOT_TOKEN`, `COSIGN_PRIVATE_KEY`,
  `COSIGN_PASSWORD` (groupes) ; `BUILDKIT_CACHE_UTILISATEUR`, `BUILDKIT_CACHE_JETON` (instance).
