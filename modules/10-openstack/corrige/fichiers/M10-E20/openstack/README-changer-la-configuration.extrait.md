## Changer la configuration

> Section du README de `plateforme/openstack` (M10-E20, PLAT-1130).

**Interdit** : modifier un fichier sous `/etc/kolla/` sur un nœud (il sera écrasé au prochain passage, et personne ne le saura) ; lancer `reconfigure` ou `deploy` sans étiquette sur le cloud partagé hors fenêtre annoncée ; mettre un secret ailleurs que dans `passwords.yml` (chiffré).

**Où mettre un réglage** (du plus large au plus étroit, le dernier gagne) :

| Portée | Fichier (sous `etc/kolla/config/`) | Exemple |
|---|---|---|
| tous les services oslo | `global.conf` | `[database] max_pool_size` |
| un projet | `<projet>.conf` (ex. `nova.conf`, `neutron.conf`) | `global_physnet_mtu` (M10-E12) |
| un service | `<projet>/<service>.conf` (ex. `nova/nova-compute.conf`) | `reserved_host_memory_mb` |
| un hôte | `<projet>/<hôte>/<projet>.conf` (ex. `nova/oscmp02/nova.conf`) | `cpu_allocation_ratio` |
| fichier non INI | `<projet>/<fichier>` (ex. `nova/policy.yaml`, `nova/vendordata.json`, `horizon/_9999-custom-settings.py`) | |

Avant d'écrire une surcharge, chercher si une **variable** de `globals.yml` fait la même chose (elle est testée par Kolla). La liste exacte des fichiers lus est dans la tâche `config` du rôle (`share/kolla-ansible/ansible/roles/<rôle>/tasks/config.yml` dans l'environnement `uv`).

**Procédure** :
1. Branche, surcharge, MR (description : effet attendu, services redémarrés).
2. `kolla-ansible genconfig -t <rôle>` puis `outils/comparer-config.sh` sur chaque nœud concerné : seules les lignes voulues changent.
3. `kolla-ansible validate-config -t <rôle>` (options inconnues, valeurs hors bornes).
4. Après fusion : `kolla-ansible reconfigure -t <rôle>` dans la fenêtre annoncée ; jamais `--limit` pour Nova (avertissement de la documentation de Kolla).
5. Contrôle : `sudo docker ps --filter health=unhealthy` sur chaque nœud vide, services `up`, essai fonctionnel.

**Journaux** : `/var/log/kolla/<projet>/` sur chaque nœud (tournés par le conteneur `cron`), `sudo docker logs <conteneur>` pour le démarrage, suivi d'une requête par son identifiant `req-…`. Mode `debug` : surcharge temporaire, retirée dans la même journée (il journalise des corps de requêtes).
