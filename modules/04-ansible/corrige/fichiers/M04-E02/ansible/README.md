# plateforme/ansible

Configuration du socle MédiSphère en code : inventaires, playbooks, rôles et collections Ansible qui décrivent l'état attendu de `gw01`, `adm01`, `dns01`, `git01`, `runner01` (et des hôtes ajoutés ensuite).

## Règles du projet

- Tout changement passe par une merge request vers `main` (branche protégée), relue, avec un pipeline vert.
- Messages de commit au format Conventional Commits ; les versions `vX.Y.Z` sont publiées par semantic-release.
- **Rien n'est appliqué au socle sans un passage `--check --diff` lu au préalable.**
- Un playbook est **idempotent** : un second passage ne change rien (`changed=0`).
- Modules appelés par leur nom complet (FQCN : `ansible.builtin.apt`), faits lus par `ansible_facts['…']`, conditions booléennes.
- **Aucun secret en clair** : Ansible Vault (à partir de M04-E12), mots de passe hors du dépôt.

## Démarrer (sur adm01)

Prérequis : `uv` (M02), Python 3.13 de Debian, agent SSH chargé avec ta clé (`ssh-add -l`).

```
admin@adm01:~$ git clone git@git01.par1.medisphere.internal:plateforme/ansible.git ~/src/ansible
admin@adm01:~$ cd ~/src/ansible
admin@adm01:~/src/ansible$ pre-commit install
admin@adm01:~/src/ansible$ uv sync --locked
admin@adm01:~/src/ansible$ uv run ansible-galaxy collection install -r collections/requirements.yml -p collections
admin@adm01:~/src/ansible$ uv run ansible --version
```

Toujours lancer Ansible **depuis la racine du projet** : c'est là qu'il trouve `ansible.cfg`.

## Contenu

| Chemin | Rôle |
|---|---|
| `ansible.cfg` | Configuration d'Ansible pour ce projet |
| `pyproject.toml`, `uv.lock`, `.python-version` | Environnement d'exécution (ansible-core 2.21, ansible-lint, Molecule) |
| `collections/requirements.yml` | Collections de Galaxy, versions exactes (installées dans `collections/`, non versionnées) |
| `inventories/lab/` | Inventaire du lab, `group_vars/`, `host_vars/` |
| `playbooks/` | Playbooks |
| `roles/` | Rôles du projet (à partir de M04-E10) |

## Mettre à jour une dépendance

1. Branche `build/…`, modification de `pyproject.toml` (puis `uv lock`) ou de `collections/requirements.yml`.
2. Notes de version de l'outil lues (en particulier les guides de portage d'ansible-core).
3. `--check --diff` de tous les playbooks sur le lab, puis MR.
