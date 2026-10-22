# plateforme/charts-miroir

Recopie dans Harbor (`oci://registry.par1.medisphere.internal/charts`) les charts Helm **tiers** dont
la plateforme a besoin, à une version exacte, après contrôle de leur empreinte, puis les signe par la
clé MédiSphère (Cosign 3, sans journal de transparence public). Argo CD ne lit que ce registre.

## Ajouter un chart ou une version

1. Relève l'empreinte de l'archive amont : champ `digest` de l'`index.yaml` du dépôt, ou
   `helm pull <chart> --repo <dépôt> --version <X.Y.Z>` puis `sha256sum`.
2. MR sur `charts.yaml` (une entrée : `nom`, `depot`, `version`, `empreinte`, `usage`). Le job `lister`
   contrôle le fichier.
3. Après fusion, le pipeline de `main` recopie (`recopier`) et signe (`signer`) sur le runner protégé.
4. Vérifie : `cosign verify --key ~/medisphere/docs/registre/cosign.pub --insecure-ignore-tlog=true registry.par1.medisphere.internal/charts/<nom>@<digest>`.

Un pipeline **planifié** (hebdomadaire) rejoue la liste : rien n'est republié (étiquettes immuables dans
Harbor), une signature manquante est ajoutée.

## Secrets

| Variable (projet, protégée) | Contenu |
|---|---|
| `HARBOR_MIROIR_USER` | `robot$charts+miroir` (non masquable à cause du `$`, « Expand variable reference » désactivé) |
| `HARBOR_MIROIR_TOKEN` | jeton du robot (masqué), push + pull sur `charts`, 180 jours, inscrit au registre des secrets |
| `COSIGN_PRIVATE_KEY`, `COSIGN_PASSWORD` | clé de signature MédiSphère (M13), héritées du groupe `plateforme` |

## Ne pas faire

- Une version avec intervalle (`2.43.x`) : on ne recopie que ce qu'on a relu.
- Pousser à la main dans `charts/` un chart tiers : il n'aurait ni empreinte relue ni signature.
