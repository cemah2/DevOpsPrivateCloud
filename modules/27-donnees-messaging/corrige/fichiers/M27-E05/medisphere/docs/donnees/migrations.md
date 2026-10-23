# Migrations de schéma de MédiAgenda (Flyway)

> `docs/donnees/migrations.md` — M27-E05 (DEV-2805) ; règles *expand/contract* : M27-E06.

## Outil et chaîne

| Élément | Valeur |
|---|---|
| Outil | **Flyway 13.11.1**, édition OSS (licence Apache 2.0 : `/flyway/licenses/LICENSE.md` de l'image), JRE 25 |
| Fichiers | `migrations/V<n>__<description>.sql` de `mediagenda/api` ; rappel `flyway/rappels/beforeBaseline.sql` |
| Image | `registry.par1.medisphere.internal/medisphere/mediagenda-migrations:vX.Y.Z` — même version que l'API, construite par le pipeline enfant `ci/migrations.yml`, signée |
| CI | `migrations:verifier` : `migrate`, `validate`, `info` sur un PostgreSQL 18 jetable à chaque MR qui touche aux migrations |
| Exécution | Job **`mediagenda-migrations`** (`mediagenda/deploiement`, component `migrations`), hook Argo CD **Sync, vague −1** : avant la nouvelle version de l'API |
| Connexion | **directe** au primaire (`mediagenda-db-rw`, TLS `verify-full` avec la CA de la grappe), jamais par le pooler |
| Compte | dev : propriétaire `mediagenda` ; recette, prod : migrateur **dynamique** d'OpenBao (`mediagenda-migrateur-<env>`, devient `mediagenda` à la connexion) |
| Historique | table `flyway_schema_history` (propriétaire `mediagenda`) ; l'ancienne `mediagenda_historique_schema` est gardée en lecture (preuve de la reprise), jamais modifiée |

## La reprise (*baseline*) du M27-E05

Recette, prod et dev étaient à la version 2 par l'ancien outil (`python -m mediagenda.migrate`). Le Job a fait une **reprise à la version 2** au premier passage (`baselineOnMigrate`, `baselineVersion: 2`), protégée par `beforeBaseline.sql` : la reprise échoue si `mediagenda_historique_schema` ne contient pas V1 **et** V2. Résultat attendu dans chaque base :

```
 installed_rank | version |              description                 |   type   | installed_by | success
              1 | 2       | reprise de mediagenda.migrate (M27-E05)  | BASELINE | mediagenda   | t
```

`baselineOnMigrate` a été **retiré** du Job ensuite (MR du <AAAA-MM-JJ>) : laissé en place, il referait silencieusement une reprise à la version 2 sur une base dont l'historique aurait été perdu — en sautant des migrations réelles.

## Diagnostic

```
admin@adm01:~$ kubectl -n mediagenda-recette get jobs mediagenda-migrations
admin@adm01:~$ kubectl -n mediagenda-recette logs job/mediagenda-migrations
admin@adm01:~$ kubectl cnpg psql mediagenda-db -n mediagenda-recette -- -d mediagenda -c \
    'SELECT installed_rank, version, description, type, installed_by, installed_on, execution_time, success
       FROM flyway_schema_history ORDER BY installed_rank'
```

Le journal du Job se termine par le tableau de `flyway info` (état final). Un Job en échec arrête la synchronisation **avant** l'API : l'ancienne version continue de servir.

## Règles

1. On n'édite **jamais** une migration publiée (Flyway refuse : somme de contrôle) ; on écrit la suivante.
2. Chaque migration est compatible avec la version de l'API **en production** (M27-E06, job CI de compatibilité).
3. `flyway repair` (réaligne les sommes de contrôle, retire les lignes en échec) : seulement avec un ticket `INC-`/`CHG-`, en sachant **pourquoi** l'historique diverge.
4. `clean` est désactivé (défaut de Flyway 10 et plus) et le reste.
5. Les migrations ne passent jamais par le pooler.
