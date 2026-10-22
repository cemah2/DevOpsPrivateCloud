# Composant `construction-image`

Lint du Dockerfile (`image:hadolint`), puis construit une image par le démon **BuildKit partagé** du cluster (`buildkitd.buildkit`, TLS mutuel,
M19-E08) et la publie dans Harbor **par empreinte**.

```yaml
include:
  - component: $CI_SERVER_FQDN/plateforme/ci-templates/construction-image@v2.0.0
    inputs:
      image_nom: medisphere/mediagenda-api
```

| Référence | `image:construction` | `image:publication` |
|---|---|---|
| merge request | archive OCI, sans cache d'écriture | — |
| `main` | archive + cache | `main-<sha court>` |
| étiquette `vX.Y.Z` | archive + cache | `vX.Y.Z` (refus si elle existe) |

Sorties (rapports `dotenv`) : `IMAGE_EMPREINTE` (construction), `IMAGE_REF`
(`registry.par1.medisphere.internal/<projet>/<dépôt>@sha256:…`) et `IMAGE_ETIQUETTE` (publication).
Les jobs suivants (signature, promotion) travaillent **sur `IMAGE_REF`**, jamais sur une étiquette.

Si le composant `securite` est inclus, la publication attend `securite:trivy` (entrée `job_analyse`).
L'archive porte la provenance SLSA de BuildKit (`attest:provenance=mode=max`).
