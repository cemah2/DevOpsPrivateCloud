# Réplication du registre

> Modèle de corrigé (M13-E13). Remplace les `<…>` par tes mesures.

## Ce qui est en place

| | |
|---|---|
| Source | `reg01` — `https://registry.par1.medisphere.internal` |
| Destination | `reg02` — `https://reg02.par1.medisphere.internal` (Harbor de **test**, VLAN 99, temporaire) |
| Sens | **poussée** depuis `reg01` (`reg02` n'est jamais une source de confiance : pas de *pull* vers `reg01`) |
| Politique | `medisphere-vers-reg02` (état OpenTofu `registre`, `registre/replication.tf`) |
| Filtres | ressources `medisphere/**`, étiquettes `v*`, type `artifact` |
| Déclencheur | planifié, chaque nuit à 03:15 (cron Harbor à six champs `0 15 3 * * *`) |
| Écrasement | oui (les accessoires ajoutés après coup suivent) ; immuabilité `v*` aussi sur `reg02` |
| Suppressions | **non propagées** |
| Identité | robot système `robot$replication` de `reg02` (lister, tirer, pousser sur `medisphere`) ; secret en Vault `critique` |
| TLS | vérifié : racine MédiSphère donnée à l'endpoint (`ca_certificate`), jamais `insecure` |
| Flux | `reg01` → `reg02:443` (bordure, temporaire) |

## Ce qui voyage, ce qui ne voyage pas

- **Répliqué** : manifestes et blobs des artefacts sélectionnés, leurs **accessoires** (signatures Cosign, attestations SBOM et provenance, rangées en référents OCI 1.1). Le digest est identique des deux côtés : la signature, qui porte sur le digest, reste valable.
- **Non répliqué** : les caches publics (inutile, et coûteux), les robots, membres et politiques de projet (ils sont dans le code : état `registre-reg02`), l'historique des analyses (Trivy de `reg02` réanalyse), les journaux d'audit, les étiquettes de suivi non `v*`.

## Mesures

| Mesure | Valeur |
|---|---|
| Première exécution (manuelle) : artefacts, accessoires, volume, durée | `<N>` artefacts, `<N>` accessoires, `<X>` Mo, `<D>` min |
| Publication `vX.Y.Z` → disponible **signée** sur `reg02` | `<D>` (au pire 24 h + durée d'exécution) |
| **RPO images** (déclencheur planifié) | 24 h, plus la durée d'une exécution |

## Ce qui remplacera `reg02`

`reg02` est détruite au mini-projet (M13-E25). La cible durable est un Harbor de **PAR2** (finaux, PRA) : même politique, déclencheur sur événement (`event_based`) en plus du planifié pour ramener le RPO à quelques minutes, flux à travers `wg0`, robot propre à PAR2.
