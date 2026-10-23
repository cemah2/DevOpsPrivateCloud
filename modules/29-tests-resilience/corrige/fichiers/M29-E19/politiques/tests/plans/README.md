# Plans de référence des politiques OpenTofu (M29-E19, SEC-3019)

| Fichier | Ce qu'il fait | Verdict attendu |
|---|---|---|
| `plan-dangereux.json` | supprime `nbx01` (socle, protégée) et crée une VM sans étiquette dans la plage du socle | **refusé** (au moins un `FAIL`) |
| `plan-sain.json` | modifie la description de `nbx01` | **accepté** |

Rejoués par le job `non-regression-plans` (`.gitlab-ci.yml`) avec **les mêmes espaces** que le composant `validation` (`CONFTEST_ESPACES`). Un plan de référence se régénère par `tofu show -json` sur un vrai plan de `plateforme/infra` (en retirant toute donnée sensible : ici, aucune) ; il ne s'écrit pas à la main au-delà des champs lus par les règles.
