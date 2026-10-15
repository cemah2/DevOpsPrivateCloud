# Stockage du registre : quotas, rétention, immuabilité, ramasse-miettes

> PLAT-1410 (M13-E10). `/data` de `reg01` : 200 Gio (XFS, `hdd-bulk`). Code : `plateforme/infra`, `registre/projets.tf`, `caches.tf`, `politiques.tf`.

## Quotas

| Projet | Quota | Projet | Quota |
|---|---|---|---|
| `medisphere` | 40 Gio | `dockerhub` | 40 Gio |
| `plateforme` | 15 Gio | `ghcr` | 20 Gio |
| `bibliotheque` | 15 Gio | `quay` | 10 Gio |
| `charts` | 5 Gio | `k8s` | 15 Gio |

Somme : 160 Gio (80 % du disque). Le quota compte la taille **dédupliquée** des blobs du projet. Une poussée qui le dépasserait est **refusée** (erreur `quota exceeded` côté client) : rien n'est écrit, la CI échoue lisiblement. Alerte à 80 % d'un quota et à 80 % de `/data` (supervision, M13-E16 puis M21).

Relever un quota : MR sur `registre/projets.tf` ou `caches.tf`, avec la mesure actuelle (`GET /api/v2.0/projects/<projet>/summary`) et la place libre sur `/data` ; la somme reste sous 85 % du disque.

## Rétention (`medisphere`, chaque nuit à 1 h 30)

- Toujours garder : étiquettes `v*`.
- Garder aussi : les 10 artefacts poussés le plus récemment de chaque dépôt.
- Tout le reste est supprimé, avec ses signatures et attestations.
- Toute modification de règle : simulation (*dry run*) d'abord, journal joint à la MR.

## Immuabilité

Étiquettes `v*` immuables dans `medisphere` et `bibliotheque` : ni réécriture, ni suppression. La signature et les attestations restent possibles (accessoires de l'artefact). Retirer une version compromise : passer par l'administrateur du projet (désactiver la règle le temps de l'opération, tracé dans `docs/socle/journal/`), jamais en contournant la chaîne.

## Ramasse-miettes (dimanche 3 h)

La suppression d'une étiquette ou d'un artefact ne libère pas l'espace : le ramasse-miettes supprime ensuite les blobs qui ne sont plus référencés (et les artefacts sans étiquette). Depuis Harbor 2.1, il ne bloque plus les poussées, mais il charge le disque et la base : planifié hors des heures de construction. Historique : « Administration > Clean Up ».

## Caches

Chaque cache reçoit de Harbor une rétention par défaut qui supprime les images non tirées depuis 7 jours (à vérifier dans l'onglet « Policy » du projet cache) ; le ramasse-miettes libère ensuite la place.
