# Journal de diagnostic — INC-5238 « MédiAgenda (recette) perd sa base » (Julien Petit)

> Modèle de journal (M25-E38), ici pour la variante 1. Une ligne par geste : heure, hypothèse,
> commande (sans secret), résultat, conclusion. Aucun mot de passe, aucun identifiant de bail complet
> (les 6 premiers caractères suffisent), aucune URL de connexion avec son mot de passe.

| Heure | Hypothèse | Commande | Résultat | Conclusion |
|---|---|---|---|---|
| 10:02 | — | `kubectl -n mediagenda-recette logs` (API, 15 min) | `password authentication failed for user "v-k8s-par1-mediagen-…"` depuis 09:58 | le compte de l'API est refusé, pas la base entière |
| 10:04 | ESO ne délivre plus | `kubectl -n mediagenda-recette get es mediagenda-db-api` | `Ready`, rafraîchi à 09:48 | ESO délivre ; le compte vit moins longtemps que prévu ? |
| 10:06 | le compte a disparu | `SELECT … rolvaliduntil FROM pg_roles …` (membres `v-…` de `mediagenda_api`) | compte de 09:48 : `VALID UNTIL 09:58` | vie de 10 min au lieu d'1 h |
| 10:08 | bail raccourci | `bao list sys/leases/lookup/db-mediagenda/creds/mediagenda-api-recette` puis lookup d'un bail | `ttl` 600 à l'émission | le coffre délivre des baux de 10 min |
| 10:09 | rôle modifié | `bao read db-mediagenda/roles/mediagenda-api-recette` | `default_ttl 3600`, `max_ttl 600` | max_ttl < cycle d'ESO (30 min) : 20 min de trou par cycle |
| 10:11 | — | audit Loki : `chemin=~"db-mediagenda/roles/.+"` | `update` à 09:47 (jeton d'un administrateur) | modification à la main, hors pipeline |
| 10:12 | dérive | `tofu plan` (plateforme/secrets) | `vault_database_secret_backend_role.mediagenda["mediagenda-api-recette"]` : `max_ttl 600 -> 86400` | le dépôt a raison |
| 10:20 | — | pipeline de `main` (apply) | rôle à 3600 / 86400 | — |
| 10:21 | — | `kubectl annotate es mediagenda-db-api force-sync=…` | nouveau Secret, Reloader redémarre le Rollout (≈ 2 min) | bail d'1 h |
| 10:24 | — | boucle `curl …/pret` | 200 continu | réparé |

**Cause** : `max_ttl` du rôle `mediagenda-api-recette` ramené à 10 min à la main ; chaque identifiant
mourait 20 min avant d'être remplacé par ESO (rafraîchissement toutes les 30 min). **Correctif** :
`tofu apply` de `main`, rafraîchissement forcé. **Prévention** : règle `MoteurDatabaseModifie` et
`IdentifiantsDynamiquesEnEchec` (ruler de Loki), règle de durée dans `identifiants-dynamiques.md` § 6
(vie d'un identifiant ≥ 2 cycles d'ESO), plan planifié de `plateforme/secrets` (M25-E40).
