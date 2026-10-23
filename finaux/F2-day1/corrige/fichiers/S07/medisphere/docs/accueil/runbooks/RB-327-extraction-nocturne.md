# RB-327 — Extraction pseudonymisée nocturne vers l'équipe Data

*Propriétaire : équipe Plateforme (côté MédiAgenda) et équipe Data (côté chargement). Relu par : Julien Petit, Sophie Laurent. Version F2-S07 (DEV-3207). Décision : ADR-0327.*

## 1. Chaîne

| Heure (Paris) | Étape | Où | Identité |
|---|---|---|---|
| 01:20 | sauvegarde de base de `statistiques-db` | `data-traitements` | identité S3 `cnpg-data` |
| 02:30 | CronJob `extraction-data` : lecture de `extraction.rendez_vous_pseudo` sur `mediagenda-db-secours`, dépôt `rendez-vous/AAAA-MM-JJ.csv.gz` + `.json` | `mediagenda-secours` | rôle PostgreSQL `extraction_data` ; identité S3 `extraction-ecriture` (écriture seule) |
| 03:30 | CronJob `chargement-extraction` : vérification de l'empreinte, remplacement de `stats.rendez_vous`, ligne dans `stats.chargements` | `data-traitements` | identité S3 `extraction-lecture` ; compte dynamique `db-data/creds/data-traitement` |
| en continu | métriques `cnpg_stats_extraction_*`, alertes `ExtractionData*` | Prometheus | — |

Les dates des fichiers sont en **UTC** (`date -u +%F`) des deux côtés.

## 2. Diagnostic d'une alerte `ExtractionDataEnRetard`

```
admin@adm01:~$ kubectl -n mediagenda-secours get cronjob,jobs -l app.kubernetes.io/name=extraction-data
admin@adm01:~$ kubectl -n mediagenda-secours logs job/<JOB> -c lecture
admin@adm01:~$ kubectl -n mediagenda-secours logs job/<JOB> -c depot
admin@adm01:~$ kubectl cnpg status mediagenda-db-secours -n mediagenda-secours        # rejeu en retard ? promu ?
admin@adm01:~$ kubectl -n data-traitements get cronjob,jobs -l app.kubernetes.io/name=chargement-extraction
admin@adm01:~$ kubectl -n data-traitements logs job/<JOB> -c recuperation
```

| Message | Cause probable | Action |
|---|---|---|
| `canceling statement due to conflict with recovery` | rejeu des WAL pendant la lecture | le Job réessaie (3 fois) ; si c'est systématique, relever `max_standby_archive_delay` du secours (au prix d'un rejeu retardé pendant la lecture) |
| `password authentication failed for user "extraction_data"` | rotation du mot de passe pas encore rejouée sur le secours (≤ 5 min) ou Secret pas à jour | relancer le Job après le prochain segment archivé ; vérifier l'ExternalSecret |
| `permission denied for view rendez_vous_pseudo` | V5 jouée avant la création du rôle (GRANT conditionnel sauté) | rejouer les deux GRANT de V5 en tant que `mediagenda` (MR d'une migration V suivante, jamais à la main) |
| `extraction vide` | vue vide (fenêtre de 13 mois, prod vide en recette) | normal hors prod ; en prod, incident |
| `empreinte … différente du manifeste` | fichier tronqué ou remplacé | ne rien charger ; prévenir la plateforme et la RSSI ; comparer avec le journal d'accès de s3-01 |
| `NoSuchKey` au chargement | l'extraction n'a pas déposé ce jour-là | remonter à l'extraction |

Relancer à la main (après correction) : `kubectl -n mediagenda-secours create job --from=cronjob/extraction-data extraction-manuelle-$(date +%s)`, puis de même pour `chargement-extraction` (l'équipe Data).

## 3. Rotation des secrets

- Mot de passe `extraction_data` : nouvelle version de `kv/mediagenda/prod/extraction-data`, ESO met à jour le Secret de `mediagenda-prod` (CloudNativePG applique) et celui de `mediagenda-secours`. Le secours ne connaît le nouveau mot de passe qu'au prochain segment archivé : faire la rotation **de jour**, jamais entre 02:00 et 03:00.
- Identités S3 : nouvelle clé dans `seaweedfs.yml` (Vault `critique`), application du rôle sur `s3-01`, mise à jour d'OpenBao, puis retrait de l'ancienne clé.
- Clé de pseudonymisation : ne tourne **pas** sans décision écrite (tous les pseudonymes changent : historique de l'équipe Data rompu). Migration dédiée : `UPDATE extraction.cle_pseudonyme SET cle = gen_random_bytes(32), creee_le = now();`.

## 4. Suspension d'urgence (fuite suspectée, colonne identifiante)

1. `kubectl -n mediagenda-secours patch cronjob extraction-data -p '{"spec":{"suspend":true}}'` (puis la même modification dans `80-extraction-data.yaml`, par MR) ;
2. vider le sas (`aws s3 rm s3://data-extractions/rendez-vous/ --recursive` avec une identité d'administration) ;
3. l'équipe Data vide `stats.rendez_vous` ; prévenir Sophie Laurent et le DPO (notification CNIL sous 72 h si violation avérée).

## 5. Réplica de secours promu (RB-275)

Après une promotion, `mediagenda-db-secours` devient la production : l'extraction le lit encore, mais **sur un primaire**. Décision : la suspendre le temps de la reprise (§4, étape 1 seulement), puis la repointer vers le nouveau réplica de secours quand il existe.
