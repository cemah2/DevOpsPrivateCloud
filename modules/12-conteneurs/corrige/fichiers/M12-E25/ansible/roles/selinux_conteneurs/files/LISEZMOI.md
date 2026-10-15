# Modules CIL des conteneurs (rôle selinux_conteneurs)

Chaque fichier `<nom>.cil` est produit **sur l'hôte cible** par `udica`, à partir du conteneur tel
qu'il tourne en production (compte `app`, mêmes montages, mêmes ports, mêmes capacités) :

    [app@ctr03 ~]$ podman inspect legacy-rdv > /tmp/legacy-rdv.json
    [admin@ctr03 ~]$ cd /tmp && sudo udica -j /tmp/legacy-rdv.json legacy_rdv

puis relu (droits sur quels types, quel port) et versionné ici par MR, avec la liste des modèles
cités par udica dans `host_vars/<hôte>/selinux_conteneurs.yml`.

`legacy_rdv.cil` (M12-E25) : Legacy-RDV sur `ctr03` — lecture-écriture des pièces jointes
(`/srv/legacy-rdv/uploads`, `container_file_t`), lecture seule du dépôt SFTP d'InfoGér
(`/home/app/depot-infoger`, `user_home_t`), port 8080 de l'hôte (`http_cache_port_t` dans la
politique RHEL : à vérifier par `semanage port -l | grep -w 8080`), aucune capacité.
Régénérer à chaque changement de montage, de port ou de capacité de l'unité Quadlet.
