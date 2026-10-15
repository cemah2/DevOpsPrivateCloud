# Chaîne de livraison des images

> DEV-1409 (M13-E09). Gabarit `plateforme/ci-templates`, fichier `templates/supply-chain.yml`. Premier client : `mediagenda/api`.

## Utiliser la chaîne

```yaml
include:
  - project: plateforme/ci-templates
    ref: v1.<Y>.<Z>               # étiquette épinglée (pas la branche v1)
    file:
      - templates/qualite.yml
      - templates/release.yml
      - templates/supply-chain.yml
variables:
  SC_IMAGE_NOM: medisphere/<application>
stages: [lint, test, construction, analyse, publication, signature, verification, release]
```

Le projet déclare la liste complète des stages : chaque gabarit inclus déclare les siens, et seul le dernier compterait.

Prérequis du projet : un `Dockerfile` qui accepte `ARG VERSION` ; les variables de groupe `HARBOR_ROBOT_USER` (non développée), `HARBOR_ROBOT_TOKEN` (masquée), `COSIGN_PRIVATE_KEY` (fichier), `COSIGN_PASSWORD` (masquée), toutes **protégées** ; les étiquettes `v*` **protégées** dans le projet GitLab (sinon une étiquette poussée par un développeur n'a pas accès aux secrets, et c'est voulu).

| Variable | Défaut | Rôle |
|---|---|---|
| `SC_IMAGE_NOM` | — | `<projet Harbor>/<dépôt>` |
| `SC_CONTEXTE` | `.` | contexte de construction |
| `SC_DOCKERFILE` | `Dockerfile` | relatif au contexte |
| `SC_PLATEFORME` | `linux/amd64` | plateforme construite et analysée |
| `SC_SEVERITE_BLOQUANTE` | `CRITICAL` | sévérités bloquantes (avec correctif) |

## Ce que fait la chaîne

```
construction ──▶ analyse (Trivy, bloquante) ──┐
     │         └▶ sbom (Syft SPDX + CycloneDX) ┴▶ publication (robot, empreinte préservée, refus si l'étiquette existe)
     │                                                 └▶ signature + attestations (Cosign, sans journal) ──▶ vérification
     └ empreinte de l'index (provenance SLSA incluse), transmise de job en job (dotenv)
```

- Une merge request construit, analyse et produit la SBOM ; elle ne publie rien.
- `main` publie `main-<sha court>` (suivi ; la rétention garde les 10 derniers).
- Une étiquette `vX.Y.Z` (semantic-release) publie `vX.Y.Z`, **une seule fois** (le pipeline refuse, Harbor aussi : immuabilité, M13-E10).

## Vérifier une image publiée

Voir `signature.md`. En une ligne : `cosign verify --key docs/registre/cosign.pub --insecure-ignore-tlog=true registry.par1.medisphere.internal/medisphere/<app>@<empreinte>`.

## Exceptions de vulnérabilités

`.trivyignore` du projet, format et revue dans `analyse.md`. Le seuil se change par MR (variable `SC_SEVERITE_BLOQUANTE`), jamais en rendant un job `allow_failure`.

## Outils

Image `plateforme/outils-supply-chain` (Cosign 3.1.3, Trivy 0.75.0, Syft 1.54.1, Grype 0.120.1, Skopeo 1.18), construite par cette même chaîne, épinglée par empreinte dans le gabarit ; elle contient la clé publique et la configuration de signature. Construction : BuildKit rootless (`moby/buildkit:v0.34.0-rootless`) par le cache Docker Hub.
