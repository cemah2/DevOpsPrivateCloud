# Sous le capot : l'API de distribution OCI de Harbor

> Modèle de corrigé (M13-E23). Remplace les `<…>` par tes relevés. Outil : `outils/oci-inspecter.sh`.

Image étudiée : `registry.par1.medisphere.internal/medisphere/mediagenda-api:<vX.Y.Z>` — digest **`sha256:<…>`**.

## 1. Le défi et le jeton

```
$ curl -sI https://registry.par1.medisphere.internal/v2/
HTTP/2 401
www-authenticate: Bearer realm="https://registry.par1.medisphere.internal/service/token",service="harbor-registry"
$ curl -s -u '<IDENTITÉ>' 'https://registry.par1.medisphere.internal/service/token?service=harbor-registry&scope=repository:medisphere/mediagenda-api:pull'
{"token":"eyJ…","expires_in":1800,"issued_at":"…"}
```

Le jeton est un JWT signé par `harbor-core` (clé `/data/secret/core/private_key.pem`), valable 30 minutes ; sa charge contient `access: [{"type":"repository","name":"medisphere/mediagenda-api","actions":["pull"]}]`. Sans identité, `medisphere` étant privé, la liste `actions` est **vide** : le service de jetons ne refuse pas, il n'accorde rien ; c'est le registre qui répond ensuite `401`. On s'en sert ensuite en `Authorization: Bearer <jeton>`.

## 2. Le manifeste et la négociation de type

| `Accept` envoyé | `Content-Type` reçu | `Docker-Content-Digest` |
|---|---|---|
| index OCI | `application/vnd.oci.image.index.v1+json` | `sha256:<…>` |
| manifeste OCI | `<…>` | `<…>` |
| manifeste Docker v2 | `<…>` (pas de conversion par Harbor si l'image est en OCI) | `<…>` |
| aucun | `<…>` | `<…>` |

## 3. Le digest

```
$ curl -s -H "Authorization: Bearer $J" -H 'Accept: application/vnd.oci.image.index.v1+json' -o corps.json -D entetes.txt \
    https://registry.par1.medisphere.internal/v2/medisphere/mediagenda-api/manifests/<vX.Y.Z>
$ sha256sum corps.json                 # = Docker-Content-Digest
$ jq . corps.json | sha256sum          # différent
```

Le digest est l'empreinte SHA-256 des **octets** du manifeste, pas de son sens : reformater, réordonner une clé ou ajouter une espace produit un autre digest. C'est ce qui rend une référence `@sha256:…` immuable : une signature par digest porte sur ces octets-là, et tout ce qu'ils désignent (configuration, couches) est lui-même désigné par digest.

## 4. Les blobs

Configuration `sha256:<…>` : utilisateur `<…>`, commande `<…>`, étiquettes `org.opencontainers.image.source`, `…revision`, `…version`. Couches : la plus petite (`<taille>`) recalculée identique. `HEAD /v2/<dépôt>/blobs/<digest>` donne `Content-Length` et `Docker-Content-Digest` sans transférer.

## 5. Les référents (OCI 1.1)

```
$ curl -s -H "Authorization: Bearer $J" -H 'Accept: application/vnd.oci.image.index.v1+json' \
    https://registry.par1.medisphere.internal/v2/medisphere/mediagenda-api/referrers/sha256:<…>
```

| `artifactType` | Rôle |
|---|---|
| `application/vnd.dev.sigstore.bundle.v0.3+json` | signature Cosign 3 (bundle) — et attestations (même type, prédicat différent dans le DSSE) |
| `<…>` | SBOM générée par Harbor (`sbom.harbor`, M13-E06) |

Filtre : `?artifactType=application/vnd.dev.sigstore.bundle.v0.3%2Bjson`. `oras discover` et `cosign tree` donnent la même liste. Le bundle (`oras manifest fetch`, puis le blob) contient le message signé (DSSE ou signature de message), la **clé publique** ou son identifiant, et **aucune** entrée de journal de transparence (`tlogEntries` vide) : d'où `--insecure-ignore-tlog=true`.

## 6. Ce qu'on ne peut pas faire

- `GET /v2/_catalog` : `401`/`403` (réservé aux administrateurs du système dans Harbor) ; on liste par l'API des projets.
- `DELETE /v2/medisphere/mediagenda-api/manifests/<digest>` avec un jeton `pull` : `401` (`unauthorized`, l'action `delete` n'est pas dans le jeton) — et `v*` est immuable de toute façon.

## Schéma

```
étiquette vX.Y.Z ──► index (sha256:…) ──► manifeste linux/amd64 ──► configuration (sha256:…)
                         ▲                       └──────────────► couches (sha256:…) ×N
                         │ subject
            référents : signature, attestations SBOM et provenance (bundles Sigstore)
```
