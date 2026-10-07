# Rôle `node_exporter`

Installe l'exportateur de métriques système de Prometheus **tel que packagé par Debian 13**
(`prometheus-node-exporter` 1.9.x), restreint son écoute à l'adresse IPv4 principale de l'hôte, choisit
ses collecteurs et publie une métrique d'inventaire `medisphere_info`. Préparation de la supervision
du module 21. Rôle écrit en M04-E34.

## Variables

| Variable | Défaut | Rôle |
|---|---|---|
| `node_exporter_port` | `9100` | Port d'écoute (1024-65535, vérifié avant toute action) |
| `node_exporter_adresse` | IPv4 de la route par défaut | Adresse d'écoute (jamais toutes les adresses) |
| `node_exporter_collecteurs_desactives` | `[infiniband, zfs, nfs, nfsd]` | Collecteurs désactivés ; liste vide permise |
| `node_exporter_unites_systemd` | `[ssh, chrony, nftables, dnsmasq, gitlab-runner, semaphore]` | Unités publiées par le collecteur systemd (sans `.service`) |
| `node_exporter_site` | `par1` | Étiquette `site` de `medisphere_info` |
| `node_exporter_dossier_textfile` | `/var/lib/prometheus/node-exporter` | Dossier du collecteur textfile (défaut Debian) |

Validation : `meta/argument_specs.yml` (types), première tâche (plage du port, forme de l'adresse).

## Exemple

```yaml
- name: Exportateur de métriques sur le socle
  hosts: socle
  become: true
  roles:
    - role: node_exporter
      vars:
        node_exporter_unites_systemd: [ssh, chrony, nftables]
```

`medisphere_info{role="role_dns",site="par1"} 1` : l'étiquette `role` reprend le ou les groupes `role_*`
de l'hôte dans l'inventaire (séparés par des virgules), `aucun` s'il n'en a pas.

## Tests

`uv run molecule test -s node_exporter` (instance 2049) : idempotence, écoute sur la seule adresse
principale, contenu de `/metrics`. Job CI `molecule:node_exporter`.

## Limites

- Ni TLS ni authentification (`--web.config.file`) : à traiter au module 21 avec la PKI du module 06.
- Le filtrage réseau n'est **pas** géré ici : sur `gw01`, le port 9100 reste fermé tant que la matrice des
  flux ne l'ouvre pas vers Prometheus.
- Échappement : `/etc/default/prometheus-node-exporter` est lu par systemd ; une barre oblique inverse
  devrait y être quadruplée. Le rôle n'en produit aucune (`[.]` pour un point littéral) : garde cette règle
  si tu ajoutes des expressions régulières.
