# RB-270 — PostgreSQL (`mediagenda-db`) : maintenance et bascule

> `docs/donnees/runbooks/RB-270-postgresql-maintenance-bascule.md` — M27-E12 (PLAT-2812). Propriétaire : plateforme (Karim Benali). Testé à froid le <AAAA-MM-JJ> par <QUI> (voir Historique).
> Durées : mesurées en recette au M27-E02 (`docs/donnees/postgresql.md`) — remplace les `<N>` par les tiennes.

## Quand ouvrir ce runbook

- Alertes : `PostgresqlPrimaireAbsent`, `PostgresqlReplicationEnRetard`, `PostgresqlSynchroneSansReplica`, `PostgresqlInstanceIsolee` (règles de plateforme, M27-E14) ; taux de 5xx de MédiAgenda (M21) avec `/pret` en 503 ; événements de bascule sur le `Cluster` (`kubectl get events`).
- Maintenance **planifiée** : nœud à redémarrer ou à drainer, mise à jour mineure de l'image PostgreSQL, redémarrage de toutes les instances.

Variables : `NS=mediagenda-recette` (ou `mediagenda-prod`), `C=mediagenda-db`.

## 1. L'état en une minute

```
admin@adm01:~$ kubectl cnpg status $C -n $NS
admin@adm01:~$ kubectl get cluster $C -n $NS -o jsonpath='{.status.phase}{"  primaire="}{.status.currentPrimary}{"  cible="}{.status.targetPrimary}{"\n"}'
admin@adm01:~$ kubectl get events -n $NS --field-selector involvedObject.name=$C --sort-by=.lastTimestamp | tail -5
admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' https://mediagenda-<env>.apps.par1.medisphere.internal/pret
```

À lire, dans cet ordre :

| Question | Où | Bon signe |
|---|---|---|
| L'API répond-elle ? | `/pret` | `200` |
| Y a-t-il un primaire ? | `status` : `Primary instance`, `phase` | `Cluster in healthy state`, `currentPrimary` = `targetPrimary` |
| Une bascule est-elle en cours ? | `phase` : `Failing over`, `Switchover in progress` ; événements | non, ou terminée depuis moins de `<N>` s |
| Les réplicas suivent-elles ? | `Streaming Replication status` : `Replay Lag`, `Sync State` (`quorum`/`sync` pour une, `potential` pour l'autre) | lag de quelques ms, une réplique synchrone |
| L'archivage marche-t-il ? | `Continuous Backup status` : dernier WAL archivé, échecs | WAL récent, `Failed WAL: 0` |
| Une instance est-elle bloquée ? | `Instances status` ; `kubectl get pods -n $NS -l cnpg.io/cluster=$C -o wide` | 3 pods `Running`, 3 nœuds différents |

## 2. Procédures planifiées

**Prérequis communs** : fenêtre annoncée (prod : CHG approuvé, heures creuses) ; sauvegarde `Completed` de moins d'une heure en prod :
```
admin@adm01:~$ kubectl cnpg backup $C -n $NS --method plugin --plugin-name barman-cloud.cloudnative-pg.io
admin@adm01:~$ kubectl get backups -n $NS --sort-by=.metadata.creationTimestamp | tail -1     # phase completed
```
Une sonde `/pret` qui tourne pendant l'opération (une requête par seconde) : c'est elle qui mesure la coupure.

### 2.1 Bascule volontaire (*switchover*)

```
admin@adm01:~$ kubectl cnpg promote $C <instance-cible> -n $NS        # ex. mediagenda-db-2 ; une réplique SYNCHRONE à jour
```
Attendu : écritures impossibles pendant `<N>` s (E02), quelques erreurs côté pooler puis reprise **sans** redémarrer l'API ; l'ancien primaire redevient réplique. Vérifier §1.

### 2.2 Nœud à drainer (redémarrage, maintenance Proxmox)

```
admin@adm01:~$ kubectl drain <noeud> --ignore-daemonsets --delete-emptydir-data
```
- Nœud d'une **réplique** : l'instance évincée reste `Pending` (anti-affinité requise, trois travailleurs) jusqu'au `uncordon` ; aucune coupure. Le PDB des réplicas n'en laisse partir qu'une à la fois.
- Nœud du **primaire** : CloudNativePG **bascule avant** l'éviction (le PDB du primaire la retient) : coupure d'écriture `<N>` s, comme 2.1.
- Après : `kubectl uncordon <noeud>` ; l'instance revient sur son nœud (même PVC) et rattrape. §1.
- Un seul nœud à la fois ; attendre `Cluster in healthy state` avant le suivant.

### 2.3 Mise à jour mineure de l'image (ex. 18.6 → 18.7)

MR qui change `imageName` (étiquette **et** empreinte ; recette : `plateforme/k8s`, prod : patch de `overlays/prod` de `mediagenda/deploiement`). L'opérateur met à jour les réplicas une à une, puis **bascule** (`primaryUpdateMethod: switchover`), puis l'ancien primaire. Coupure : `<N>` s (E02). Vérifier `SELECT version();` (`kubectl cnpg psql $C -n $NS -- -c 'select version()'`). **Jamais** de changement de majeure par ce chemin.

### 2.4 Redémarrer toutes les instances (paramètre qui l'exige)

```
admin@adm01:~$ kubectl cnpg restart $C -n $NS          # par roulement, réplicas puis primaire (bascule)
```

## 3. Bascule subie (*failover*)

Ce que fait CloudNativePG seul : primaire en échec (pod supprimé, disque, `postgres` arrêté) → le contrôleur arrête l'ancien primaire, élit la réplique la plus avancée et la promeut (`failoverDelay: 0`). **Nœud injoignable** : l'opérateur ne voit le primaire « non prêt » qu'après ≈ 40 à 55 s (délai de Kubernetes pour déclarer le nœud `Unknown`), puis bascule.

1. **Attendre** : 2 minutes après le début de l'incident (heure de l'alerte), sans rien toucher. Suivre §1 toutes les 30 s.
2. Bascule terminée (`currentPrimary` = `targetPrimary`, nouvelle instance) → `/pret` revient à 200 en `<N>` s ; vérifier la réplication (une réplique synchrone), puis s'occuper de l'**ancienne** instance (pod `Pending` sur un nœud perdu : voir 4).
3. Rien ne bouge après 5 minutes (`phase` figée, pas de `targetPrimary` nouveau) → journaux de l'opérateur :
   ```
   admin@adm01:~$ kubectl cnpg logs cluster $C -n $NS --tail 200 | jq -r '.msg' | tail -30
   admin@adm01:~$ kubectl -n cnpg-system logs deploy/cnpg-controller-manager --tail 100
   ```
   et **escalader** (§6). Ne promouvoir à la main (`kubectl cnpg promote`) que sur décision de l'astreinte de niveau 2, vers une réplique dont le `Replay LSN` est le plus avancé : promouvoir une réplique en retard **perd** les transactions qu'elle n'a pas reçues.

## 4. Après une bascule

- Instance sur un nœud perdu : son pod y reste jusqu'à l'éviction par Kubernetes (≈ 300 s), puis le volume RBD doit être détaché de l'ancien nœud avant de s'attacher ailleurs (cela peut prendre plus longtemps si le nœud est éteint brutalement). C'est une **réplique** désormais : pas d'urgence. Ne pas supprimer le PVC.
- Compter les erreurs côté API pendant la coupure (Grafana, `sum(rate(mediagenda_http_requests_total{code=~"5.."}[1m]))`) et noter les durées dans l'historique ci-dessous.

## 5. Interdits

- `kubectl delete pvc` d'une instance, `kubectl cnpg destroy`, `kubectl delete cluster` : **jamais** sans le niveau 2 et une sauvegarde vérifiée.
- Supprimer le pod du primaire « pour forcer » une bascule : c'est un *failover* (arrêt brutal), pas un *switchover*.
- Modifier à la main un objet géré par Argo CD (`Cluster` de prod) : `selfHeal` le remettra ; passer par une MR.
- Toucher au bucket `cnpg-k8s-par1` (archives WAL, sauvegardes).
- Changer `instances` ou la réplication synchrone pendant un incident.

## 6. Escalade

| Niveau | Qui | Quand |
|---|---|---|
| 1 | astreinte (Nadia) | §1 à §4 |
| 2 | Karim Benali (plateforme) | bascule bloquée > 5 min, promotion manuelle, perte de deux instances, archivage en échec > 30 min |
| 3 | Claire Morel | perte de données possible, restauration (RB-275) |

## Historique

| Date | Qui | Quoi | Correction du runbook |
|---|---|---|---|
| <AAAA-MM-JJ> | <QUI> (à froid, recette) | bascule volontaire §2.1 avec le seul runbook : <N> s sans écriture | <ce qui l'a arrêté → corrigé> |
