# RB-196 — Construction d'image et cache de CI

| | |
|---|---|
| Portée | Démon `buildkitd` (espace `buildkit`), cache de construction `plateforme/cache-buildkit` (Harbor), cache des jobs `ci-cache` (`s3-01`) |
| Déclencheur | Job de construction en échec ; pipelines soudain plus lents ; « cache restauré : non » sur le canari |
| Auteur / relecture | Équipe Plateforme (M19-E37, M19-E38) / Karim Benali |

## buildkitd

Chaîne : client `buildctl` (pod de job) → TLS mutuel (certificat client émis par `buildkit-ca`) → Service `buildkitd.buildkit:1234` (CiliumNetworkPolicy) → démon (stockage local) → registre (identifiants **du client**, passés par la session).

| Message de `buildctl` (représentatif) | Maillon | Preuve | Correctif |
|---|---|---|---|
| `tls: bad certificate`, `unknown certificate authority` | certificat client d'un autre émetteur, expiré, Secret absent | `kubectl get certificates -A -o wide` ; `openssl x509 -noout -issuer -dates` sur `tls.crt` | `issuerRef: buildkit-ca` dans le code ; `cmctl renew` |
| `context deadline exceeded`, délai de connexion | politique réseau, Service, démon arrêté | `hubble observe --namespace buildkit --verdict DROPPED` ; `kubectl -n buildkit get cnp,svc,endpoints` | politiques du code seulement (pas d'`ingressDeny` hors code) |
| `401 Unauthorized` à l'export du cache ou à la poussée | robot désactivé, expiré, sans droit | `GET /api/v2.0/robots` (champ `disable`, `expires_at`) | état OpenTofu `registre` ; Vault pour le secret |
| `no space left on device` | volume du démon plein | `kubectl -n buildkit exec … -- df -h <racine>` ; `du` | retirer ce qui n'est pas du cache ; `buildctl prune --keep-storage` ; ramasse-miettes dans `buildkitd.toml` |

Pod de diagnostic : `sonde-buildctl.yaml` (profil `restricted`, sans privilège, sans jeton), supprimé après usage.

Interdits : conteneur privilégié, TLS désactivé, contournement de Harbor, `rm -rf` dans le dossier du démon.

## Cache

| Ligne de journal (représentative) | Étage | Correctif |
|---|---|---|
| `Checking cache for <clé>` : la clé change à chaque pipeline | clé (variable par pipeline ou job) | `cache:key:files` (fichier de verrou) dans une **nouvelle version** du composant |
| `WARNING: <chemin>: no matching files. Ensure that the artifact path is relative to the working directory` | chemins hors de `$CI_PROJECT_DIR` | rediriger le cache de l'outil dans le projet |
| `WARNING: Retrying… 403 Forbidden` | identité S3 `ci-cache` sans droits | rôle Ansible `seaweedfs` (`s3.json`) |
| `404 … NoSuchBucket` | compartiment faux dans `[runners.cache.s3]` | values Helmfile du runner |
| `No URL provided, cache will not be downloaded from shared cache server` | `[runners.cache]` absent ou incomplet | values Helmfile |

Preuve côté stockage : `aws --endpoint-url https://s3-01.par1.medisphere.internal:8333 s3 ls s3://ci-cache/` avec `~/.config/workbook/s3-ci-cache.env`.

Rappel : un cache en échec ne fait **jamais** échouer le job. Seul un indicateur explicite (canari) le rend visible.
