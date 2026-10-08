# plateforme/openstack

Déploiement d'**OpenStack 2026.1 « Gazpacho »** sur PAR1 par **Kolla-Ansible 22** (ADR-0101).
Tout ce qu'il faut pour reconstruire le cloud est ici ; rien de ce qui se régénère n'y est.

## Prérequis

- `adm01`, avec `uv` et l'identité Vault `critique` (`~/.config/workbook/ansible-vault-critique.pass`, M04-E30) ;
- les nœuds `osctl01`, `oscmp01`, `oscmp02` créés par `plateforme/infra` (`envs/openstack`) et préparés par `plateforme/ansible` (`playbooks/openstack-noeuds.yml`) ;
- le DNS des VIP (`openstack.par1.medisphere.internal`, `openstack-int.par1.medisphere.internal`).

## Installer l'outillage

```
uv sync                                                   # Kolla-Ansible 22.2.0, ansible-core 2.20
uv run kolla-ansible install-deps                         # collections de Kolla → ./collections
uv run ansible-galaxy collection install -r requirements.yml   # openstack.cloud → ./collections
```

Pourquoi un environnement à part : Kolla-Ansible 22 exige ansible-core < 2.21, `plateforme/ansible` est en 2.21. Les collections sont **dans ce dépôt** (`collections_path = ./collections`), jamais dans `~/.ansible/collections`, partagé avec l'autre projet.

## Commande type

Depuis la racine du dépôt :

```
uv run kolla-ansible <action> -i inventaire/multinode --configdir etc/kolla [-t <étiquettes>]
```

L'identité Vault `critique` est fournie par `ansible.cfg` (`vault_identity_list`). Actions courantes : `prechecks`, `pull`, `deploy`, `reconfigure`, `post-deploy`, `validate-config`. La documentation de Kolla déconseille `--limit`.

## Ce qui est versionné

| Chemin | Contenu | Secret ? |
|---|---|---|
| `pyproject.toml`, `uv.lock` | versions figées de Kolla-Ansible et d'ansible-core | non |
| `ansible.cfg`, `requirements.yml` | réglages Ansible, collections du dépôt | non |
| `inventaire/groupes-principaux.ini` | nos groupes (qui fait quoi) | non |
| `inventaire/multinode` | **produit** par `outils/inventaire.sh` (nos groupes + groupes de services de la version installée) | non |
| `inventaire/host_vars/`, `inventaire/group_vars/` | valeurs propres à un hôte ou un groupe | non |
| `etc/kolla/globals.yml`, `etc/kolla/globals.d/` | configuration commune, commentée | non |
| `etc/kolla/passwords.yml` | mots de passe de tous les services | **oui** : Vault `critique` |
| `etc/kolla/config/` | surcharges de configuration des services | non (les clés viennent de `passwords.yml`) |
| `etc/kolla/certificates/haproxy.pem` | certificat externe **et sa clé** (M10-E04) | **oui** : Vault `critique` |
| `etc/kolla/certificates/ca/` | racine MédiSphère (publique) | non |
| `playbooks/`, `donnees/` | objets du cloud (identité, gabarits, réseau externe) ; `donnees/vault-*.yml` chiffrés | mots de passe : Vault `critique` |
| `outils/` | scripts (inventaire, chiffrement, certificat, images) | non |

Jamais versionnés : `.venv/`, `collections/`, et ce que `post-deploy` écrit dans `etc/kolla/` (`admin-openrc.sh`, `clouds.yaml` : mot de passe administrateur en clair).

## Pipeline

MR : `yamllint`, aucun secret en clair (`outils/verifier-chiffrement.sh`), inventaire à jour (`outils/inventaire.sh --verifier`). Le déploiement se lance depuis `adm01`.

## Documentation

`plateforme/medisphere`, `docs/cloud/` : ADR-0100 (réseau), ADR-0101 (Kolla-Ansible), runbooks RB-100 et suivants, comptes rendus de changement.
