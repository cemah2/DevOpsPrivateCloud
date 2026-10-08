# etc/kolla/config/ — surcharges de configuration des services

Kolla-Ansible fusionne les fichiers de ce dossier avec la configuration qu'il génère (`node_custom_config`) :
`<service>.conf` pour tous les conteneurs du service, `<service>/<conteneur>.conf` pour un seul, `<service>/<hôte>/…` pour un hôte. Vide au palier 1 ; rempli au palier 2 (Ceph, Neutron, Nova…).

Règle : aucune valeur secrète en clair ici. Un secret vient de `passwords.yml` (chiffré) par une expression Jinja.
