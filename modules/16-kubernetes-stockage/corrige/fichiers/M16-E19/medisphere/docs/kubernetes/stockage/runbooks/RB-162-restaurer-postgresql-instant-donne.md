# RB-162 — Restaurer une base PostgreSQL (CloudNativePG) à un instant donné

| | |
|---|---|
| **Objet** | Retrouver l'état d'une base CNPG à un instant `T` (erreur humaine, migration ratée, données corrompues) dans un **cluster d'enquête** séparé, puis réinjecter ce qui manque, ou basculer l'application si la base est perdue |
| **Déclencheur** | Ticket `INC-` ou `DEV-` : « des données ont disparu / ont été modifiées à telle heure » ; échec d'une migration de schéma |
| **Public** | Équipe Plateforme (droits `medisphere:plateforme-admins`), avec l'équipe applicative pour valider les données |
| **Durée cible** | Base de recette : < 30 min de l'ouverture du ticket à la vérification ; RTO mesuré à chaque essai mensuel |
| **Liens** | RB-161 (espace de noms complet), politique de sauvegarde (`../politique-sauvegarde.md`), M16-E19, M16-E34 |

## 0. Ne pas faire

- **Ne jamais** restaurer « par-dessus » la base vivante (supprimer `mediagenda-db` pour la recréer depuis la sauvegarde) : on perdrait tout ce qui a été écrit depuis `T`, et la restauration peut échouer.
- **Ne jamais** donner au cluster d'enquête le plugin d'archivage (`.spec.plugins`) avec le nom de serveur de la base d'origine : ses WAL écraseraient l'archive de production.
- Ne pas supprimer le cluster d'enquête avant que l'équipe applicative ait validé.

## 1. Qualifier (5 min)

1. Instant `T` **avec son fuseau** (`2026-11-04T14:32:10+01:00`) : demande à l'équipe l'heure de l'erreur et prends une marge **avant** (une minute). Une heure sans fuseau est lue en UTC par CNPG.
2. Vérifier que `T` est dans la fenêtre de restauration :
   ```
   kubectl -n <ESPACE> get objectstore <OBJECTSTORE> -o jsonpath='{.status.serverRecoveryWindow}{"\n"}'
   ```
   `firstRecoverabilityPoint` ≤ `T`, et le dernier WAL archivé est **après** `T` :
   ```
   kubectl -n <ESPACE> get cluster <CLUSTER> -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")].status}{"\n"}'   # True
   kubectl cnpg psql <CLUSTER> -n <ESPACE> -- -c 'SELECT pg_switch_wal();'     # pousse le WAL courant dans l'archive
   ```
   Si `ContinuousArchiving` n'est pas `True` : **escalade** (l'archive peut ne pas contenir `T`), et ne touche à rien d'autre.
3. Place disponible : quota de stockage de l'espace (`kubectl describe quota quota-stockage -n <ESPACE>`) pour un PVC de la taille de la base.

## 2. Créer le cluster d'enquête (10 min)

Manifeste (modèle : `mediagenda-db-pitr.yaml` de M16-E19) : **une** instance, même image et même classe que la base d'origine, `bootstrap.recovery.source` vers un `externalClusters` qui lit l'`ObjectStore` avec `serverName: <CLUSTER>`, `recoveryTarget.targetTime: "<T>"`, **sans** `.spec.plugins`.

```
sed "s/<T>/$T/" <CLUSTER>-enquete.yaml | kubectl apply -f -
kubectl -n <ESPACE> get jobs -w                                 # <CLUSTER>-enquete-1-full-recovery : Complete
kubectl -n <ESPACE> logs job/<CLUSTER>-enquete-1-full-recovery --all-containers | grep -E 'backup|restored log file|recovery stopping'
kubectl cnpg status <CLUSTER>-enquete -n <ESPACE>               # Cluster in healthy state
```

Contrôle : le journal montre la sauvegarde de base choisie (la dernière terminée avant `T`) et `recovery stopping before commit … time <T'>` avec `T'` juste après `T`. Échec typique : `T` hors fenêtre, Secret `cnpg-s3`/`medisphere-ca` absent de l'espace, politique réseau qui bloque la sortie vers `s3-01:8333`.

## 3. Vérifier avec l'équipe applicative (5 min)

```
kubectl cnpg psql <CLUSTER>-enquete -n <ESPACE> -- -d <BASE> -c '<REQUÊTE DE CONTRÔLE>'
kubectl cnpg psql <CLUSTER>         -n <ESPACE> -- -d <BASE> -c '<MÊME REQUÊTE>'
```

Les données perdues sont présentes dans l'enquête et absentes de la production ; ce qui a été créé après `T` est absent de l'enquête. Note les deux résultats dans le ticket (comptes, identifiants ; **jamais** de données de patient dans un ticket).

## 4. Réparer

**Cas A — la base vit, il manque des lignes (le plus fréquent)** : recopier **seulement** ce qui manque, sans rien écraser (modèles : `reinjecter.sh` de M16-E19, `outils/recuperer-lignes.sh` de M16-E34) : `COPY … TO STDOUT` depuis l'enquête → table temporaire dans la production → `INSERT … OVERRIDING SYSTEM VALUE … ON CONFLICT DO NOTHING`, dans une transaction, d'abord en simulation (`ROLLBACK`), puis pour de bon. Contrôle : la requête de l'étape 3 donne le résultat attendu en production.

**Cas B — la base est perdue ou inutilisable** (décision de Claire Morel ou de l'astreinte N2) : faire du cluster d'enquête la nouvelle base :
1. le passer à trois instances et lui ajouter le plugin d'archivage avec un **nouveau** `serverName` (paramètre `serverName: <CLUSTER>-v2`) — CNPG refuse d'archiver dans un emplacement qui contient déjà une autre archive ;
2. vérifier `ContinuousArchiving=True`, lancer une sauvegarde de base (`kubectl cnpg backup … --method=plugin --plugin-name=barman-cloud.cloudnative-pg.io`) ;
3. repointer l'application : Secret `<CLUSTER>-enquete-app` (clé `uri`) dans le Deployment, ou renommage par une MR qui remplace le `Cluster` dans `plateforme/k8s` ; la `ScheduledBackup` vise le nouveau cluster ;
4. garder l'ancienne base arrêtée (ou ses PVC) jusqu'à la clôture de l'incident.

## 5. Clôturer

- Supprimer le cluster d'enquête (cas A) : `kubectl -n <ESPACE> delete cluster <CLUSTER>-enquete` (ses PVC partent avec lui).
- Ticket : `T`, sauvegarde de base utilisée, heures (début, enquête prête, réparation faite), **RTO mesuré**, lignes réinjectées (nombre), écarts au runbook.
- Post-mortem si production (`docs/kubernetes/post-mortems/`).

## Retour arrière

Le cluster d'enquête n'écrit nulle part ailleurs que dans son propre volume : le supprimer suffit. La réinjection (cas A) se fait dans une transaction ; en cas de doute, `ROLLBACK`. Le cas B garde l'ancienne base jusqu'à la clôture.

## Escalade

| Cas | Vers |
|---|---|
| `ContinuousArchiving` faux, `T` hors fenêtre, archive illisible | Plateforme N2 (et équipe S3) |
| Décision de basculer sur le cluster d'enquête (cas B) | Claire Morel |
| Doute sur les données à réinjecter | Équipe applicative (Julien Petit) |

## Historique

| Date | Auteur | Changement |
|---|---|---|
| 2026-10 | <MOI> | Création (M16-E19), joué sur `mediagenda-db` → `mediagenda-db-pitr` |
