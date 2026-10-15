# MR !42 — feat(medidoc-dev) : stockage et base de données de l'environnement de dev MédiDoc

**Auteur** : Lucas Martin — **Relecteur demandé** : Karim Benali

Salut Karim,

Voici tout ce qu'il faut pour l'environnement de dev de MédiDoc (`medidoc-dev`). J'ai tout testé sur mon cluster kind (`kind create cluster`, image par défaut) : tous les pods sont `Running`, tous les PVC `Bound`. 🎉

Ce que contient la MR :

- `00-storageclass.yaml` : une classe `rapide` pour les devs. J'ai mis toutes les fonctions RBD pour avoir les meilleures performances, et je l'ai mise par défaut pour qu'ils n'aient pas à y penser. J'ai repris le Secret du chart en le renommant pour que ce soit plus clair.
- `10-secrets.yaml` : les identifiants. Je sais qu'on ne met pas de secrets dans Git, mais c'est un dépôt privé et c'est l'environnement de dev, donc c'est pas grave.
- `20-pvc-partage.yaml` : un volume partagé entre l'API MédiDoc et le futur traitement par lots (miniatures).
- `30-postgres-maison.yaml` : une base PostgreSQL « en attendant » que CNPG soit prêt chez eux (deux réplicas pour la haute disponibilité).
- `40-cnpg-cluster.yaml` : la vraie base, avec la sauvegarde comme dans les exemples que j'ai trouvés sur un blog.
- `50-objectstore.yaml` : j'ai copié celui de la recette de MédiAgenda pour aller plus vite.
- `60-scheduledbackup.yaml` : une sauvegarde par nuit, à 2 h.
- `70-velero-schedule.yaml` : Velero toutes les nuits, avec les volumes.

À appliquer avec `kubectl apply -f .` dans l'ordre alphabétique.

Merci !
