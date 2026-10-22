# M25-E14 — Observations en recette (modèle ; aucun mot de passe)

| Essai | Commande (résumé) | Résultat |
|---|---|---|
| 3 identifiants `api` | `bao read db-mediagenda/creds/mediagenda-api-recette` ×3 | trois comptes `v-…`, `rolvaliduntil` = création + 1 h |
| baux | `bao list sys/leases/lookup/db-mediagenda/creds/mediagenda-api-recette` | 3 baux (+ ceux d'ESO) |
| renouvellement | `bao lease renew -increment=24h <bail>` répété | plafonné à 24 h après la création (`max_ttl`) ; `rolvaliduntil` suit (instruction de renouvellement par défaut) |
| migrateur | `CREATE TABLE essai_e14 (id int);` puis `SELECT tableowner FROM pg_tables WHERE tablename = 'essai_e14';` | `mediagenda` (propriétaire), pas le compte temporaire |
| api | `INSERT` dans une table de l'application | réussi |
| api | `DROP TABLE essai_e14;` | `ERROR: must be owner of table essai_e14` |
| ménage | `DROP TABLE essai_e14;` avec un identifiant `migrateur` | réussi |
