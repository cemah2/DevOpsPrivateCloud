# Test de restauration de Harbor

> Modèle de corrigé (M13-E15). Remplace les `<…>` par tes mesures. Un test par trimestre, et à chaque
> livraison (M13-E25).

| | |
|---|---|
| Date | `<AAAA-MM-JJ>` |
| Opérateur | `<MOI>` |
| Source | `reg01`, sauvegarde `host/reg01/<date>` de `par1/registre` |
| Cible | `reg02` **reconstruite depuis zéro** (`tofu destroy` / `apply` de `envs/m13`, rôle `harbor` en `<version>`) |
| Volume | base `<X>` Mo, blobs `<X>` Go (`<X>` Go transférés après déduplication) |

## Chronologie

| Étape | Début | Durée |
|---|---|---|
| Recréation de la VM (OpenTofu) | | |
| Rôles `docker_engine`, `certificats_acme`, `harbor` (installation vide) | | |
| Rôle `sauvegarde_harbor` en mode restauration | | |
| `wb-restaurer-harbor.sh` : blobs et clés | | |
| `wb-restaurer-harbor.sh` : base (`pg_restore`) | | |
| Démarrage et santé `healthy` | | |
| Vérifications (ci-dessous) | | |
| **Total (RTO mesuré)** | | `<D>` |

## Vérifications

- [ ] Projets, membres et robots de `reg01` présents (`/api/v2.0/projects`, interface).
- [ ] Une image `medisphere/<app>:vX.Y.Z` se tire avec `robot$medisphere+ci` (les secrets des robots sont stockés hachés : ils survivent à la restauration).
- [ ] `cosign verify --key cosign.pub --insecure-ignore-tlog=true reg02.par1.medisphere.internal/medisphere/<app>@<digest>` réussit.
- [ ] L'endpoint `dockerhub` restauré se teste « healthy » ou son identifiant est lisible (preuve que `secretkey` est la bonne).
- [ ] Toutes les politiques de réplication restaurées sont **désactivées**.

## Résultat

- **RTO** : `<D>` mesuré ; objectif proposé : 2 h (dont l'essentiel en transfert des blobs).
- **RPO** : 24 h (sauvegarde quotidienne à 01:40) ; images en `v*` : le RPO de la réplication (`replication.md`) quand elle existe.
- **Écarts** : `<ce qui a coincé, et le ticket ouvert>`.
