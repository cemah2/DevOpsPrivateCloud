# RB-294 — Arrêter une expérience de chaos

| | |
|---|---|
| Ticket d'origine | PLAT-3013 (M29-E13), complété par INC-5620 (M29-E20) |
| Quand | une expérience dépasse son critère d'arrêt, quelqu'un demande l'arrêt, ou on ne sait plus ce qui tourne |
| Qui | toute personne de la plateforme ; l'astreinte en dehors des heures ouvrées |
| Durée | 2 à 5 minutes |

## 1. Arrêter tout, tout de suite

```
admin@adm01:~/src/resilience$ outils/chaos-arret.sh            # pause de tout chaos-experiences + bilan
admin@adm01:~/src/resilience$ outils/chaos-arret.sh --supprimer # si l'on ne reprendra pas
```

La **pause** (`experiment.chaos-mesh.org/pause=true`) fait passer la phase désirée de l'expérience à `Stop` : le contrôleur demande à chaque `chaos-daemon` de **retirer** la panne (règles `tc`, `iptables`/`ipset`, processus de stress). L'objet reste, on peut reprendre (`pause=false`). Sur un `Schedule`, la pause empêche les **nouvelles** exécutions ; les enfants déjà créés se mettent en pause chacun. Sur un `Workflow`, la pause suspend les nœuds en cours.

La **suppression** fait la même chose, puis retire l'objet quand le finaliseur `chaos-mesh/records` est levé (toutes les pannes retirées). Supprime d'abord ce qui **crée** (`Schedule`, `Workflow`), puis les expériences : sinon un enfant revient au tick suivant.

## 2. Une seule expérience

```
admin@adm01:~$ kubectl -n chaos-experiences annotate networkchaos <nom> experiment.chaos-mesh.org/pause=true
admin@adm01:~$ kubectl -n chaos-experiences delete networkchaos <nom>
```

`container-kill` et `pod-kill` sont instantanés : la pause n'arrête que les **prochaines** actions (une expérience `pod-kill` avec durée tue aussi les pods qui la rejoignent pendant la durée : pause ou suppression).

## 3. Vérifier que la panne est retirée

```
admin@adm01:~$ kubectl -n chaos-experiences get networkchaos <nom> -o jsonpath='{.status.experiment.desiredPhase}{"\n"}'
Stop
admin@adm01:~$ kubectl -n chaos-experiences get networkchaos <nom> \
    -o jsonpath='{range .status.experiment.containerRecords[*]}{.id}{" "}{.phase}{" injecté:"}{.injectedCount}{" retiré:"}{.recoveredCount}{"\n"}{end}'
mediagenda-recette/mediagenda-7f9c…-x2kqz Not Injected injecté:1 retiré:1
```

Chaque enregistrement doit être `Not Injected` avec `recoveredCount` = `injectedCount`. Puis la **mesure** : p95 et 5xx revenus à la ligne de base (requêtes de `chaos/catalogue.md`), pods prêts.

Pour une panne réseau, la preuve ultime est sur le nœud (lecture seule) :

```
admin@adm01:~$ kubectl -n mediagenda-recette get pod <pod> -o jsonpath='{.spec.nodeName}{"\n"}'
admin@k8s-w02:~$ id=$(sudo crictl pods --namespace mediagenda-recette --name '^<pod>$' -q)
admin@k8s-w02:~$ pid=$(sudo crictl inspectp "$id" | jq .info.pid)
admin@k8s-w02:~$ sudo nsenter -t "$pid" -n tc qdisc show dev eth0      # plus de « netem »
```

## 4. Si la suppression reste bloquée, ou si l'effet continue

Ne force pas le finaliseur à l'aveugle : applique **RB-297** (qui recrée l'expérience ? qui empêche son retrait ? retrait manuel prouvé sur le nœud, forçage en dernier recours).

## 5. Après

- Note l'heure d'arrêt et la raison dans `docs/qualite/journal/` et dans `chaos/catalogue.md`.
- Si le critère d'arrêt a été atteint : l'hypothèse est réfutée, ouvre l'action corrective (ticket).
