# M25-E15 — Journal des rotations (modèle ; AUCUNE valeur ni clé d'accès)

## Identifiants dynamiques (recette)

| Heure | Événement | Observation |
|---|---|---|
| 14:00 | ESO rafraîchit `mediagenda-db-api` (30 min) | nouveau compte `v-…`, nouveau `resourceVersion` du Secret |
| 14:00 | Reloader : `spec.restartAt` posé sur le Rollout | journal de Reloader : « Changes detected in 'mediagenda-db-api' … rollout-strategy restart » |
| 14:00 → 14:02 | Argo Rollouts évince les pods un à un | révision inchangée (`kubectl argo rollouts get rollout mediagenda`) ; boucle `curl /pret` : 0 erreur sur 240 requêtes |
| 15:00 | fin du bail de l'avant-dernier compte | `DROP ROLE` ; aucune session active de ce compte (`pg_stat_activity`) |

Écart rafraîchissement → fin du redémarrage : ~2 min (marge avant la fin du bail : 28 min).

## Clés S3 de MédiDoc (recette)

| Heure | Étape | Preuve |
|---|---|---|
| 15:10 | nouvelle clé IAM créée (2 clés actives) | `aws iam list-access-keys --user-name medidoc-recette` : 2 entrées (identifiants tronqués) |
| 15:10 | nouvelle version KV | `bao kv metadata get -mount=kv medidoc/recette/s3` : version 2 |
| 15:14 | ESO relit (≤ 5 min), Reloader redémarre `medidoc` | 2 pods neufs |
| 15:16 | envoi d'un document de test | 201 ; le journal d'accès du RGW montre la NOUVELLE clé (préfixe) |
| 15:20 | ancienne clé supprimée | `list-access-keys` : 1 entrée ; `/readyz` 200 |

## Racine de la connexion (recette)

| Heure | Action | Observation |
|---|---|---|
| 15:30 | `bao write -f db-mediagenda/rotate-root/mediagenda-recette` | identifiants déjà délivrés : toujours valides (ce sont d'autres comptes) ; nouvelle demande `creds` : réussie |
