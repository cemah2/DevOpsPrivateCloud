# Rôle `gitlab_runner`

Runner de CI du socle (`runner01`, exécuteur `shell`) et **tous** les outils des pipelines de la plateforme (modules 01 à 03). Remplace les scripts `installer-runner.sh` (M01-E23), `installer-release-tools.sh` (M01-E24, réutilisé tel quel), `installer-outils-runner01.sh` (M02-E24) et `installer-packer-runner01.sh` (M03-E15).

## Ce qu'il installe

| Élément | Provenance | Intégrité | Variable |
|---|---|---|---|
| GitLab Runner + images d'assistance (figés) | dépôt APT `packages.gitlab.com/runner/gitlab-runner/debian` | clé du dépôt vérifiée par son empreinte | `gitlab_runner_version`, `gitlab_runner_cle_empreinte` |
| ShellCheck 0.11 | `trixie-backports` | signature Debian | `gitlab_runner_shellcheck_version` |
| gitleaks, shfmt, jq, Task, uv | releases GitHub, dans `/opt/ci-outils/<nom>-<version>/`, liens dans `/usr/local/bin` | SHA-256 | `gitlab_runner_outils` |
| bats-core | archive de l'étiquette | SHA-256 relevée par l'équipe (aucune publiée) | `gitlab_runner_bats_version`, `gitlab_runner_bats_sha256` |
| pre-commit | PyPI, `uv tool install` dans `/opt/uv-tools` | — | `gitlab_runner_precommit_version` |
| Node.js 24 | NodeSource (`node_24.x`, priorité 600) | clé vérifiée par son empreinte | `gitlab_runner_node_majeure`, `gitlab_runner_nodesource_empreinte` |
| `/opt/release-tools` | verrou `package-lock.json` de `plateforme/ci-templates` (clone du contrôleur) | empreintes du verrou, `npm ci --ignore-scripts` | `gitlab_runner_release_tools_source` |
| Packer 1.16 | dépôt APT HashiCorp | clé vérifiée par son empreinte | `gitlab_runner_packer_version`, `gitlab_runner_hashicorp_empreinte` |
| CA provisoire, CA de `pve01` | fichiers du contrôleur | — | `gitlab_runner_ca_provisoire`, `gitlab_runner_ca_pve01` |

## Ce qu'il ne fait pas

- Il ne génère pas `/etc/gitlab-runner/config.toml` : GitLab Runner le réécrit lui-même (rotation du jeton). Le rôle n'enregistre le runner que si `name = "runner01-shell"` est absent, et ne règle que `concurrent`.
- Il ne crée pas l'objet runner dans GitLab (étiquettes `shell`, `socle`, jobs sans étiquette refusés) : *Admin → CI/CD → Runners*, une fois, par une personne identifiée.

## Monter une version

1. Changer la ligne (version **et** empreinte) dans `defaults/main.yml`, ou `gitlab_runner_version` dans `host_vars/runner01/`.
2. MR ; `ansible-playbook playbooks/runner01.yml --check --diff` ; application hors des heures de pipelines.
3. Retour arrière : remettre l'ancienne ligne (les anciens dossiers de `/opt/ci-outils/` sont toujours là).

## Recréer `runner01`

1. `pve01` : clone de l'image dorée `current` en 1007 (M01-E23 pour les paramètres : `vinfra`, 10.10.20.15, 2 vCPU, 4 Go, ordre de démarrage 5, étiquettes `socle`, `role-runner`).
2. GitLab : supprimer l'ancien runner, en créer un neuf (mêmes réglages), ranger son jeton `glrt-…` dans le Vault (`vault_gitlab_runner_jeton`).
3. `adm01` : `ssh-keygen -R 10.10.20.15` (nouvelle clé d'hôte, à vérifier par la console), puis `uv run ansible-playbook playbooks/site.yml --limit runner01`.
4. Contrôle : runner en ligne dans GitLab, pipeline d'un projet `plateforme/*` rejoué avec succès.
