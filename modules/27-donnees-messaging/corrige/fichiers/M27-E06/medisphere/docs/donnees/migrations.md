# Migrations de schéma de MédiAgenda (Flyway)

> `docs/donnees/migrations.md` — M27-E05 (DEV-2805) ; règles *expand/contract* : M27-E06 (DEV-2806).

## Outil et chaîne

| Élément | Valeur |
|---|---|
| Outil | **Flyway 13.11.1**, édition OSS (licence Apache 2.0 : `/flyway/licenses/LICENSE.md` de l'image), JRE 25 |
| Fichiers | `migrations/V<n>__<description>.sql` de `mediagenda/api` ; rappel `flyway/rappels/beforeBaseline.sql` |
| Image | `registry.par1.medisphere.internal/medisphere/mediagenda-migrations:vX.Y.Z` — même version que l'API, construite par le pipeline enfant `ci/migrations.yml`, signée |
| CI | `migrations:verifier` : `migrate`, `validate`, `info` sur un PostgreSQL 18 jetable à chaque MR qui touche aux migrations ; `migrations:compatibilite` (M27-E06) : les migrations de la branche contre le code de la version **en production** |
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

## Évolutions sans interruption : *expand/contract* (M27-E06)

Pendant un *canary*, deux versions de l'API tournent sur **le même** schéma, et le Job de migration passe **avant** la nouvelle (vague −1). Un retour arrière ne défait pas le schéma. D'où :

> **Chaque migration est compatible avec la version de l'API en production (N−1).** Un changement cassant se livre en deux fois : **expand** avec la version N (ajouter), **contract** avec une version ultérieure (retirer, durcir), quand plus aucune instance N−1 ne tourne **dans aucun environnement**.

| Étape | Livrée avec | Versions qui tournent | Si on inverse |
|---|---|---|---|
| `V3` *expand* : colonnes `canal_rappel` (défaut `aucun`) et `contact_rappel` (facultative), contraintes `NOT VALID` | API N | N−1 et N (*canary*), puis N | — |
| `V4` *contract* : contraintes validées, défaut de `canal_rappel` retiré | API N+1 | N et N+1 | N−1 ne peut plus créer de rendez-vous (`NOT NULL` violé) ; retour arrière impossible |

### En tête de chaque migration

```sql
SET LOCAL lock_timeout = '5s';        -- échouer vite plutôt que geler toutes les requêtes de la table
SET LOCAL statement_timeout = '30s';  -- '5min' pour une validation qui parcourt la table
```

Un `ALTER TABLE` demande un verrou `ACCESS EXCLUSIVE` ; s'il attend (derrière une transaction longue), **toutes** les requêtes sur la table attendent derrière lui. Avec `lock_timeout`, la migration échoue au bout de 5 s, sa transaction est annulée (rien n'est écrit dans `flyway_schema_history`), le Job réessaie (`backoffLimit: 2`) et l'ancienne version continue de servir.

### Interdits dans une seule migration

- renommer ou supprimer une colonne lue par N−1 ; changer son type ;
- ajouter `NOT NULL` sans défaut sur une table existante, ou une contrainte sans `NOT VALID` sur une grosse table ;
- `CREATE INDEX` sans `CONCURRENTLY` sur une grosse table (et `CONCURRENTLY` exige une migration hors transaction : `executeInTransaction=false` dans un fichier `V…__….sql.conf` de Flyway, seule instruction du fichier) ;
- livrer *expand* et *contract* dans la même version.

### Le garde-fou de la CI

`migrations:compatibilite` lance l'image publiée de la version en production (`VERSION_N_MOINS_1`, à tenir à jour après chaque promotion en prod), applique les migrations de la branche à un PostgreSQL 18 jetable avec l'outil de cette image, puis `ci/fumee_n_moins_1.py` : créer, relire, lister, supprimer un rendez-vous **avec le code N−1**. Prouvé en E06 : une MR avec `V3` seul est verte ; avec `V3` + `V4`, rouge (`NotNullViolation … "canal_rappel"`).

### Annexe : `V3` et `V4` (M27-E06)

```sql
-- V3__rappel_expand.sql
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
ALTER TABLE rendez_vous
    ADD COLUMN canal_rappel   text NOT NULL DEFAULT 'aucun',
    ADD COLUMN contact_rappel text;
ALTER TABLE rendez_vous
    ADD CONSTRAINT rendez_vous_canal_rappel_ck
        CHECK (canal_rappel IN ('sms', 'mail', 'aucun')) NOT VALID,
    ADD CONSTRAINT rendez_vous_contact_rappel_ck
        CHECK ((canal_rappel = 'aucun') = (contact_rappel IS NULL)
               AND (contact_rappel IS NULL OR length(contact_rappel) <= 254)) NOT VALID;
COMMENT ON COLUMN rendez_vous.canal_rappel IS 'Canal de rappel choisi par le patient : sms, mail ou aucun (consentement explicite)';
COMMENT ON COLUMN rendez_vous.contact_rappel IS 'Téléphone ou courriel de rappel (donnée personnelle, RGPD) ; NULL si aucun rappel';

-- V4__rappel_contract.sql (version suivante de l'API)
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '5min';
ALTER TABLE rendez_vous VALIDATE CONSTRAINT rendez_vous_canal_rappel_ck;
ALTER TABLE rendez_vous VALIDATE CONSTRAINT rendez_vous_contact_rappel_ck;
ALTER TABLE rendez_vous ALTER COLUMN canal_rappel DROP DEFAULT;
```

Ordre de `V4` : les `VALIDATE` (verrou `SHARE UPDATE EXCLUSIVE`, lectures et écritures continuent pendant le parcours) **avant** le `DROP DEFAULT` (instantané mais `ACCESS EXCLUSIVE`, gardé jusqu'à la fin de la transaction) : dans l'ordre inverse, la table serait fermée à tous pendant tout le parcours.
