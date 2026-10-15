# MR !42 de Lucas Martin — « conteneurisation rapide des applis + script de sauvegarde »

> Salut ! J'ai repris les Dockerfiles qu'on trouve sur Internet et je les ai adaptés pour nos
> applis, plus une petite image qui sauvegarde PostgreSQL toutes les nuits. Tout marche chez moi
> (`docker compose up` et c'est parti). J'ai mis le jeton de l'index PyPI et les mots de passe en
> variables pour que ce soit facile à changer. Le compose lance tout d'un coup, avec Portainer pour
> que l'équipe de Julien puisse voir les conteneurs. Je n'ai pas fait de `.dockerignore`, ça me
> paraissait inutile. — Lucas

Fichiers de la MR :

| Fichier | Rôle |
|---|---|
| `mediagenda-api/Dockerfile` | image de l'API MédiAgenda |
| `medidoc/Dockerfile` | image de MédiDoc |
| `sauvegarde-pg/Dockerfile` et `sauvegarde-pg/sauvegarde.sh` | image qui fait un `pg_dump` chaque nuit et l'envoie sur le S3 du socle |
| `compose.yaml` | la pile de recette « tout-en-un » sur `ctr01` |

Ces fichiers sont **fictifs** et ne sont pas à construire ni à lancer : c'est une revue de code.
Les identifiants qu'ils contiennent sont des valeurs d'exemple sans valeur réelle.
