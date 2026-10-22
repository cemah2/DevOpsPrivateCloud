# formation/ci-pannes — le canari de la CI

Projet **témoin** du palier 4 du module 19 (pannes M19-E35 à M19-E43), créé à la première injection
par `lab/bin/break 19 …`. Il n'est jamais supprimé par les pannes ; tu peux le supprimer après la
recette du module (M19-E46).

- `templates/canari/template.yml` : composant CI/CD `canari` (publié par étiquettes `X.Y.Z`) ;
- `.gitlab-ci.yml` : consomme `canari` à une version donnée ;
- `outils/canari.py` : ce que fait le job (accès au dépôt, mémoire, disque, durée) ;
- variable `CANARI_JETON` (masquée, protégée) : jeton d'accès de projet `canari-lecture`
  (`read_repository`) ;
- pipeline planifié `canari-quotidien` (05:17, Europe/Paris).

Le job affiche `CANARI cache restauré : oui|non` : c'est l'indicateur suivi par les pannes de cache.
