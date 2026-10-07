# Collection `medisphere.socle`

Plugins et rôles partagés par les projets Ansible de la plateforme MédiSphère (M04-E18).
Elle vit dans le dépôt `plateforme/ansible`, sous `collections/ansible_collections/medisphere/socle/`,
et se trouve grâce à `collections_path = ./collections` (ansible.cfg).

| Contenu | Nom complet | Rôle |
|---|---|---|
| Filtre | `medisphere.socle.regle_nft` | Transforme un flux de la matrice (dictionnaire) en règle nftables, en refusant les flux mal formés. Utilisé par le rôle `pare_feu`. |
| Rôle | `medisphere.socle.ca_lab` | Installe des autorités de certification dans le magasin système (CA provisoire MédiSphère, CA de `pve01`). Utilisé par le rôle `gitlab_runner`. |

## Documentation

```
ansible-doc -t filter medisphere.socle.regle_nft
ansible-doc -t role medisphere.socle.ca_lab
```

## Tests

```
cd ~/src/ansible
PYTHONPATH=collections uv run --with pytest pytest collections/ansible_collections/medisphere/socle/tests/unit
```

## Versions

Le numéro de `galaxy.yml` suit SemVer. Un changement incompatible (champ de flux renommé, variable
de rôle supprimée) est une version majeure.
