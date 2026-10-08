# Proposition InfoGér — « Cloud privé OpenStack clé en main »

> Document remis par le prestataire InfoGér avec son offre (archive « kolla-medisphere.tar.gz »). **Les secrets qu'il contient sont fictifs.**

Bonjour,

Comme convenu, voici notre configuration Kolla-Ansible de référence, éprouvée chez un autre client du secteur de la santé (12 nœuds, en production depuis 2023). Nous l'avons adaptée à vos trois serveurs :

- `globals.yml` : configuration générale, déjà renseignée avec vos adresses ;
- `multinode` : inventaire pour `osctl01`, `oscmp01`, `oscmp02` ;
- `config/glance/` : connexion à votre Ceph.

Points forts :
- **tout-en-un** : supervision (Prometheus, Grafana) et journaux centralisés (OpenSearch) inclus ;
- **images optimisées** servies par notre registre, plus rapide que le registre public ;
- **réseau simple** : une seule carte réseau utilisée partout, aucune configuration de VLAN supplémentaire ;
- connexion Ceph avec le compte d'administration du cluster, « pour éviter les problèmes de droits » ;
- mot de passe administrateur déjà positionné pour que vos équipes puissent se connecter tout de suite.

Déploiement : `kolla-ansible bootstrap-servers`, `prechecks`, `deploy`. Comptez une demi-journée.

L'équipe InfoGér
