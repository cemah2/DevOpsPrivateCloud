# M17-E18 — Dossier de la livraison chronométrée

> À ouvrir à **T0**, chrono lancé. Conditions d'examen : tes runbooks, ton code, la documentation officielle ; pas de corrigé.

## Le besoin (ticket DEV-1818, Julien Petit)

MédiAgenda **1.1.0** apporte deux changements :
1. **Canal de prise** : chaque rendez-vous enregistre son canal (`web`, `telephone`, `guichet`). C'est la migration de schéma `V3__canal.sql`, *additive* : une colonne avec une valeur par défaut.
2. **Environnement obligatoire** : l'API refuse de démarrer sans `MEDIAGENDA_ENVIRONNEMENT` (`dev`, `recette` ou `prod`). Elle l'affiche dans `/sante` et dans son journal de démarrage. Sans la variable, le processus sort avec le code 2.

Le code est dans [`E18-mediagenda-1.1.0.patch`](E18-mediagenda-1.1.0.patch) (format `git format-patch`, auteur Julien Petit). Il passe les tests et ruff. Il se fusionne dans `mediagenda/api` par une MR :

```
admin@adm01:~/src/mediagenda-api$ git switch -c feat/canal-environnement
admin@adm01:~/src/mediagenda-api$ git am ~/DevOpsPrivateCloud/modules/17-packaging/ressources/E18-mediagenda-1.1.0.patch
```

## Exigences à T4

| # | Exigence | Vérifiée par |
|---|---|---|
| 1 | L'image `registry.par1.medisphere.internal/medisphere/mediagenda-api:v1.1.0` existe, construite et signée par le pipeline de `mediagenda/api` (étiquette posée par semantic-release, pas à la main) | Harbor |
| 2 | Une nouvelle version du chart `mediagenda` (appVersion `1.1.0`, variable `MEDIAGENDA_ENVIRONNEMENT` fournie à l'API **et** aux migrations) est publiée et signée par le pipeline de `mediagenda/chart` | Harbor, Cosign |
| 3 | Le **dev** tourne `v1.1.0` depuis cette version du chart, par la release Helm `mediagenda` de `mediagenda-dev` (chart tiré de Harbor par sa version, pas depuis ta copie locale) | `helm status`, Deployment |
| 4 | La **recette** tourne `v1.1.0` depuis la même version du chart, par l'overlay `recette` de `mediagenda/deploiement` fusionné sur `main` : Deployment entièrement à jour, tous les pods prêts | Deployment |
| 5 | `https://mediagenda-recette.apps.par1.medisphere.internal/sante` répond `"version":"v1.1.0"` et `"environnement":"recette"` | HTTPS |
| 6 | La migration V3 est appliquée sur la base de recette (`mediagenda-db`), une seule fois | journaux des migrations |
| 7 | La **production ne bouge pas** : `mediagenda-prod` tourne toujours sa version précédente | Deployment |
| 8 | Aucun geste manuel ne subsiste : aucun champ des Deployments du dev et de la recette n'appartient à `kubectl-edit`, `kubectl-set`, `kubectl-patch` | `managedFields` |
| 9 | Le plan de retour arrière est écrit dans la MR de recette : quoi revenir, dans quel ordre, et ce que devient le schéma | MR |

## Feuille de temps

Recopie-la dans le retour d'expérience (`docs/kubernetes/packaging/retex-E18.md` de `plateforme/medisphere`).

| Jalon | Heure | Écart / geste manuel et raison |
|---|---|---|
| T0 — dossier ouvert | | |
| T1 — image `v1.1.0` publiée et signée | | |
| T2 — chart publié et signé | | |
| T3 — dev à jour et vérifié | | |
| T4 — recette à jour et vérifiée (`lab/bin/check 17 18` vert) | | |

## Retour d'expérience (une demi-page)

- Temps total, et part des pipelines dans ce temps.
- Ce qui t'a ralenti, et ce que tu changes dans ta chaîne (runbook de livraison, gabarits).
- Ce qui se serait passé si tu avais livré l'image avant le chart.
