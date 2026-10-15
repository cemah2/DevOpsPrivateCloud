# MR !12 — `mediagenda/api` : « Déploiement de MédiAgenda en recette »

**Auteur** : Lucas Martin — **Relecteurs** : Karim Benali, `<MOI>`
**Branche** : `lucas/recette-k8s` → `main` — **Dossier** : `k8s/recette/`

## Description

Salut ! Voici les manifestes pour déployer MédiAgenda dans `mediagenda-recette`, comme demandé par
Julien pour la campagne de recette de la semaine prochaine.

- J'ai repris ce qui marchait sur mon cluster kind, en simplifiant au maximum.
- J'ai mis le mot de passe de la base dans un Secret, comme ça il n'est pas dans le Deployment.
- La base a 2 réplicas pour la haute disponibilité, et un PDB pour que l'API ne soit jamais coupée.
- J'ai figé l'API sur `k8s-w01` parce que c'est celui qui a le plus de mémoire libre.
- La migration se fait au démarrage du conteneur, comme ça on ne peut pas l'oublier.
- Julien veut tester Valkey depuis son poste : je l'ai exposé en NodePort.
- Testé : `kubectl apply -f k8s/recette/` passe sur kind, et `curl localhost:8000/sante` répond.

## Fichiers

- `00-secret.yaml`
- `10-config.yaml`
- `20-postgresql.yaml`
- `30-valkey.yaml`
- `40-api.yaml`
- `45-pdb.yaml`
