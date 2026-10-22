# Composant `securite`

Analyse et preuves de l'image construite par `construction-image`.

```yaml
include:
  - component: $CI_SERVER_FQDN/plateforme/ci-templates/securite@v2.0.0
    inputs:
      severite_bloquante: CRITICAL
```

- `securite:trivy` : analyse de l'**archive** (avant toute publication) ; échec sur une
  vulnérabilité de la sévérité choisie **qui a un correctif** ; rapport complet en artefact ;
  exceptions dans `.trivyignore` du projet (une ligne = un identifiant + un commentaire + un ticket).
- `securite:sbom` : SBOM SPDX et CycloneDX (Syft), artefacts d'un an.
- `securite:signature` : sur `main` et les étiquettes protégées, après l'analyse de Harbor, signe
  l'index **et** chaque manifeste de plateforme (la politique de Harbor vérifie chaque manifeste
  tiré), sans journal de transparence public (configuration de signature MédiSphère, M13).
- `securite:verification` : `cosign verify` avec la clé publique, comme le fera le consommateur.

Secrets : variables protégées du groupe (`COSIGN_PRIVATE_KEY`, `COSIGN_PASSWORD`,
`HARBOR_ROBOT_*`) : jamais disponibles dans un pipeline de MR.
