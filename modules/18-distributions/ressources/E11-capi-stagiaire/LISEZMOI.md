# MR !7 de `lucas.martin` sur `plateforme/distributions` : « capi : cluster de recette pour l'équipe MédiAgenda »

> Description de la MR (M18-E11). Fichiers : ce dossier.

Salut ! J'ai préparé un deuxième cluster Cluster API pour la recette de MédiAgenda, `recette-agenda`,
en partant du gabarit `cluster-template.yaml` de CAPMOX (`clusterctl generate cluster`) et de la doc.
J'ai mis tout ce qu'il faut dans le dépôt pour que n'importe qui puisse le recréer, y compris le
Secret, comme ça on n'a plus besoin du script d'identifiants. Le plan de contrôle a deux nœuds
pour la haute dispo. J'ai pris Kubernetes 1.36.5 parce que c'est la dernière 1.36.

Pour appliquer : `kubectl apply -f capi/recette-agenda/` sur le cluster de gestion.

Testé : `kubectl apply --dry-run=client` passe sans erreur.
