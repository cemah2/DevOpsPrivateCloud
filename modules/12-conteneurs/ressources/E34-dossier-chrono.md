# M12-E34 — Dossier de l'exercice chronométré : MédiAnnuaire

> À ouvrir à **T0**. Note l'heure tout de suite dans la feuille de temps ci-dessous.

## Le besoin (ticket CHG-1360, Julien Petit)

« Voici **MédiAnnuaire** (`ressources/E34-mediannuaire/`) : l'annuaire des praticiens que la prise de rendez-vous interrogera. Python 3.13, bibliothèque standard seulement, tests compris (lis son README, tout y est : variables, sondes, codes de sortie). On le veut en recette sur `ctr01` cette semaine, construit et publié par la CI, conforme à vos normes. Les données de recette sont dans `donnees/praticiens.csv` (fictives). Le jeton d'administration de la recette, vous le générez ; nous, on ne veut jamais le voir dans un dépôt. »

## Exigences

| N° | Exigence | Comment c'est vérifié |
|---|---|---|
| 1 | Projet GitLab **`mediagenda/annuaire`** créé, code de l'application poussé tel quel (tu ne modifies pas `src/` ni `tests/`) | API GitLab |
| 2 | `Dockerfile` multi-étapes et `.dockerignore` conformes aux normes : image de base du catalogue `bibliotheque/` (E27) épinglée, utilisateur non root numérique, forme *exec*, sonde de santé, étiquettes OCI de version et de révision | fichiers sur `main`, configuration de l'image publiée |
| 3 | Pipeline sur `main` : tests de l'application, Hadolint, contrôle des images autorisées (E27), construction **sans privilège** (gabarit E21) et publication de **`ctr01.par1.medisphere.internal:5000/mediagenda/annuaire:1.0.0`** ; aucune étiquette `latest` | dernier pipeline de `main` réussi, registre |
| 4 | `compose.yaml` de recette dans le projet ; la recette tourne sur `ctr01` (projet Compose `annuaire`, port **8090** de l'hôte) avec **l'image publiée** : non root, aucune capacité, `no-new-privileges`, racine en lecture seule, limites de mémoire et de processus, données en lecture seule | `docker inspect` sur `ctr01` |
| 5 | Le jeton d'administration n'apparaît ni dans le dépôt, ni dans l'environnement du conteneur (`docker inspect`) ; il est inscrit au registre des secrets (emplacement, pas la valeur) | dépôt, `docker inspect`, `docs/socle/registre-secrets.md` |
| 6 | Le service répond : `/sante` 200, `/pret` 200, liste des praticiens non vide ; un `POST /admin/recharger` avec le jeton rend 200, sans jeton 401 | HTTP depuis `ctr01` |
| 7 | Arrêt propre : `docker compose stop` rend la main en moins de 15 s et le conteneur sort avec le code 0 | à constater et noter dans la feuille de temps |
| 8 | Supervision : le conteneur est ajouté à la configuration de `ms-verif-conteneurs` (E28) par MR, et la sonde est verte | sonde sur `adm01` |

## Feuille de temps (à recopier dans le ticket)

| Jalon | Heure | Contenu | Gestes manuels (et pourquoi) |
|---|---|---|---|
| T0 | | Ouverture du dossier | |
| T1 | | Projet créé, Dockerfile et `.dockerignore` écrits, image construite et essayée **localement** | |
| T2 | | Pipeline vert sur `main`, image publiée | |
| T3 | | Recette lancée sur `ctr01` avec l'image publiée, exigences 4 à 7 constatées | |
| T4 | | Sonde mise à jour, registre des secrets, `lab/bin/check 12 34` vert | |

## Retour d'expérience (une demi-page, après T4)

- Ce qui t'a pris le plus de temps, et pourquoi.
- Ce qui manquait à tes normes (E33), à tes gabarits (E21, E27) ou à ta sonde (E28) : ouvre les MR correspondantes.
- Ce que l'application a de **différent** de MédiAgenda et qui t'a surpris (indice : relis la ligne `MEDIANNUAIRE_CACHE_DIR` du README avant de passer la racine en lecture seule).
