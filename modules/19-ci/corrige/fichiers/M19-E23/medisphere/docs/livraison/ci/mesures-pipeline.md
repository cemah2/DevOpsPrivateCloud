# Mesures du pipeline de MR de MédiAgenda

> M19-E23 (DEV-2023). **Exemple de corrigé** : valeurs plausibles pour le lab ; remplace-les par
> **tes** mesures (`~/m19/e23/mesurer.sh mediagenda/api 5`). Objectif : −40 % sur la durée médiane des
> pipelines de MR, sans retirer une seule vérification.

## Référence (avant)

5 pipelines de MR réussis, commits vides sur la branche `essai-mesures` (MR !57), composants v2.5.0.

| Mesure | Médiane |
|---|---|
| Durée du pipeline | 545 s |
| Attente du premier job | 14 s |
| Chemin critique | `qualite:lint` (52 s) → `qualite:tests` (71 s) → `qualite:tests-integration` (96 s) → `image:construction` (188 s) → `securite:trivy` (95 s) |

| Job (avant) | Durée | Attente | Observation |
|---|---|---|---|
| `qualite:commitlint` | 18 s | 6 s | clone complet nécessaire |
| `qualite:lint` | 52 s | 7 s | `uv sync` à froid : la clé de cache change avec la branche |
| `qualite:tests` | 71 s | 45 s | attend la fin du stage `lint` |
| `qualite:tests-integration` | 96 s | 44 s | idem ; démarrage de PostgreSQL ≈ 8 s |
| `securite:semgrep` | 64 s | 6 s | téléchargement des règles |
| `securite:gitleaks` | 21 s | 6 s | historique complet |
| `image:hadolint` | 9 s | 5 s | |
| `image:construction` | 188 s | 120 s | attend lint + tests ; pas de cache de registre dans les MR (robot protégé) |
| `securite:trivy` | 95 s | 8 s | base Trivy en cache ; conversion de l'archive |
| `securite:sbom` | 38 s | 8 s | |

Seuil : 327 s

(545 s × 0,6 ; ligne lue par `lab/bin/check 19 23`.)

## Leviers, un par un (3 pipelines de MR chacun)

| # | Levier | Où | Médiane après | Gain | Coût, risque | Décision |
|---|---|---|---|---|---|---|
| 1 | `needs: []` pour `qualite:tests`, `qualite:tests-integration` et `image:construction` ; la **publication** attend les tests (`needs` optionnels) | composants `qualite`, `construction-image` | 412 s | −133 s | aucun : on ne publie toujours pas d'image non testée | gardé |
| 2 | Clé de cache `uv` calculée sur `uv.lock` (+ préfixe), écriture sur `main` seulement (`policy: pull` ailleurs), `uv cache prune --ci` | `qualite` | 371 s | −41 s | le premier pipeline après une montée de dépendances est froid | gardé |
| 3 | Cache BuildKit **en lecture** dans les MR (robot `cache-buildkit-lecture`, variables d'instance non protégées) | `construction-image` + Harbor (état `registre`) | 268 s | −103 s | un robot de plus (lecture seule, inscrit au registre des secrets) ; aucune écriture possible depuis une MR | gardé |
| 4 | `GIT_DEPTH: 1` par défaut (0 seulement pour commitlint et Gitleaks) | `qualite` | 262 s | −6 s | aucun | gardé |
| 5 | `FF_USE_FASTZIP` et niveaux de compression `fast` / `fastest` (archive OCI déjà compressée) | composants | 255 s | −7 s | aucun (valeur par défaut des Runner récents : à vérifier sur ta version) | gardé |
| 6 | Artefacts limités (rapports, `coverage.xml`, `image.tar` 1 jour) | composants | 254 s | ≈ 0 | — | gardé (stockage) |
| 7 | `interruptible` + `workflow:auto_cancel:on_new_commit: interruptible` | projet | — | — (gain sur la file, pas sur la durée) | une poussée annule le pipeline précédent de la même branche | gardé |

## Résultat

| | Avant | Après | Écart |
|---|---|---|---|
| Durée médiane (3 derniers pipelines de MR) | 545 s | 254 s | −53 % |
| Nombre de jobs | 10 | 10 | identique (liste comparée : aucune vérification retirée) |

Chemin critique après : `image:construction` (≈ 85 s avec cache) → `securite:trivy` (95 s) ; prochain
levier : base Trivy servie par un miroir interne (`TRIVY_DB_REPOSITORY` vers Harbor) et analyse en
parallèle de la conversion.
