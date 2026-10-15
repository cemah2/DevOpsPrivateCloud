# Caches des registres publics

> Service : `registry.par1.medisphere.internal` (Harbor, `reg01`). Mis en place : M13-E04 (PLAT-1404).

## Noms à utiliser

| Amont | Projet cache | Exemple |
|---|---|---|
| Docker Hub (`docker.io`) | `dockerhub` | `registry.par1.medisphere.internal/dockerhub/library/debian:trixie-slim` (images officielles : préfixe `library/`) |
| Quay (`quay.io`) | `quay` | `registry.par1.medisphere.internal/quay/skopeo/stable:v1.18.0` |
| GitHub (`ghcr.io`) | `ghcr` | `registry.par1.medisphere.internal/ghcr/astral-sh/uv:0.12.23` |
| Kubernetes (`registry.k8s.io`) | `k8s` | `registry.par1.medisphere.internal/k8s/pause:3.10` |

Règle : **toujours** une empreinte en plus de l'étiquette dans un Dockerfile ou un gabarit de CI (`…:3.13-slim-trixie@sha256:…`). Renovate (M13-E11) tient les empreintes à jour.

Podman, Buildah, Skopeo : les miroirs sont déclarés dans `/etc/containers/registries.conf.d/50-miroirs-medisphere.conf` (rôle `podman_hote`) : on peut garder les noms d'origine (`docker.io/…`). Docker : **pas** de miroir possible (`registry-mirrors` ne vise que Docker Hub et la racine du registre) : on écrit le nom du cache.

`runner02` n'accepte que des images de `registry.par1.medisphere.internal` (`allowed_images`).

## Comportement

- **Premier tirage** : Harbor tire l'amont, sert et garde l'image. Les suivants sont servis localement.
- **Tirage par étiquette** : Harbor demande à l'amont l'empreinte actuelle de l'étiquette (requête légère, sans couche) ; si elle a changé, il tire la nouvelle version.
- **Tirage par empreinte** : servi depuis le cache s'il l'a, sans contacter l'amont.
- **Amont injoignable ou limite atteinte** : ce qui est déjà en cache reste servi ; une image jamais tirée échoue.
- **Image disparue de l'amont** : le cache ne la sert plus (option « servir depuis le cache » laissée désactivée, voir l'ADR-0130).
- Les images peu tirées sont supprimées par la rétention par défaut du cache (7 jours sans tirage) et le ramasse-miettes (M13-E10).

## Demander un nouvel amont

Ticket `PLAT-` à l'équipe Plateforme : registre amont, usage, propriétaire. Ajout par MR sur `plateforme/infra` (`registre/caches.tf`) et sur `group_vars/all/miroirs-registres.yml`. Les images de `gcr.io` (distroless) sont copiées dans `bibliotheque` par le pipeline des images de base, sans cache.
