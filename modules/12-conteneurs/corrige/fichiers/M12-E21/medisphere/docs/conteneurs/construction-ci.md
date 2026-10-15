# Construire les images en CI, sans mode privilégié

> M12-E21 (SEC-1321). Gabarit `templates/image.yml` de `plateforme/ci-templates` (branche `v1`), exécuté sur `runner02` (étiquette `docker`).

## Chaîne

```
MR      : lint (pre-commit, commitlint, gitleaks, hadolint) → test → build (construction, rien n'est poussé)
main    : … → build : image main-<SHA court> + cache poussés → release (semantic-release : étiquette vX.Y.Z)
vX.Y.Z  : … → build : image X.Y.Z poussée (amd64 + arm64 pour MédiAgenda et MédiDoc)
```

## Pourquoi BuildKit sans privilège, et pas Docker-in-Docker

| Méthode | Privilège demandé au runner | Retenue |
|---|---|---|
| Docker-in-Docker (`docker:dind`) | `privileged = true` : le job a toutes les capacités et les périphériques de `runner02` | **non** (PLAN §4.10) |
| Socket de l'hôte monté (`/var/run/docker.sock`) | aucun « privilège », mais le job pilote le démon root de l'hôte : root sur `runner02` | **non** |
| BuildKit sans privilège (`moby/buildkit:rootless`, `buildctl-daemonless.sh`) | deux exceptions : `seccomp=unconfined`, `apparmor=unconfined` ; démon sous l'UID 1000, sans capacité | **oui** |
| Buildah (`--isolation=chroot`, stockage `vfs`) | mêmes exceptions en pratique ; plus lent | alternative |
| Kaniko | ni mode privilégié ni option de sécurité, mais l'exécuteur tourne en **root** dans le conteneur du job (il réécrit le système de fichiers du conteneur) ; dépôt `GoogleContainerTools/kaniko` archivé (lecture seule) par Google en juin 2025, maintenu depuis par des forks (Chainguard, autres) à évaluer | non |

Exceptions accordées (`host_vars/runner02/gitlab_runner.yml`), et **seulement** celles-ci : le profil seccomp par défaut de Docker interdit `unshare` et `mount` sans `CAP_SYS_ADMIN` (BuildKit en a besoin pour isoler chaque `RUN` dans un espace de noms utilisateur), le profil AppArmor `docker-default` interdit `mount`. Le démon BuildKit est lancé avec `--oci-worker-no-process-sandbox` : pas de nouvel espace PID par `RUN` (le masque de `/proc` de Docker l'empêcherait) ; conséquence acceptée : un `RUN` voit les processus du démon de son propre job. Ce qui n'est **pas** accordé : capacités, périphériques, `/sys` en écriture, réseau de l'hôte.

Amélioration prévue : un profil seccomp dédié (profil par défaut + `unshare`, `mount`, `umount2`, `pivot_root`, `setns`) à la place de `seccomp=unconfined` (recommandation de la documentation de GitLab) ; à éprouver sur `runner02` avant de le généraliser.

## Identifiants

- Publication : compte `ci` du registre, variables **protégées et masquées** `REGISTRE_UTILISATEUR` / `REGISTRE_MOT_DE_PASSE` sur les groupes `mediagenda`, `medidoc`, `medinotif`, `legacy`, `plateforme` (outil `ms-variables-registre`) ; elles n'existent que dans les pipelines des références protégées : une MR ne peut rien publier.
- Tirage des images de jobs privées : `/root/.docker/config.json` de `runner02` (rôle `gitlab_runner`), jamais une variable `environment` de `config.toml` (que tout job lirait).
- Le fichier d'authentification du job (`~/.docker/config.json`, 0600) n'existe que dans le conteneur du job et est effacé en fin de job.

## Reproductibilité

`SOURCE_DATE_EPOCH` = date du commit, `rewrite-timestamp=true` à l'export : deux pipelines sur le même commit produisent la même empreinte d'index (vérifié sur MédiDoc et MédiAgenda 0.2.0, M12-E11).
