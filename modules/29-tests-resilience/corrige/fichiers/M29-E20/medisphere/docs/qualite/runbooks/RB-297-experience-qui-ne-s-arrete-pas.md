# RB-297 — Une expérience de chaos ne s'arrête pas

| | |
|---|---|
| Ticket d'origine | INC-5620 (M29-E20) |
| Symptômes | la panne continue après « l'arrêt » (latence, pertes, CPU) ; ou une expérience reste en suppression (finaliseur) |
| Prérequis | RB-294 déjà appliqué (pause, suppression) sans effet |
| Règle d'or | ne jamais forcer un finaliseur avant d'avoir compris **pourquoi** il est là et **comment** on vérifiera le nœud ensuite |

## 1. Qui RECRÉE l'expérience ?

```
admin@adm01:~$ for t in $(kubectl api-resources --api-group=chaos-mesh.org -o name); do kubectl get "$t" -A --no-headers 2>/dev/null | sed "s|^|$t |"; done
admin@adm01:~$ kubectl -n chaos-experiences get networkchaos <nom> -o jsonpath='{.metadata.ownerReferences}{"\n"}{.metadata.labels}{"\n"}'
```

| Constat | Cause | Arrêt à la racine |
|---|---|---|
| `ownerReferences` vers un `Schedule`, étiquette `managed-by: <schedule>` | un `Schedule` recrée un enfant à chaque tick (avec `Forbid`, dès que l'enfant précédent a disparu) | pause du **Schedule** (`experiment.chaos-mesh.org/pause=true`), puis suppression du Schedule (ses enfants partent avec lui) |
| `ownerReferences` vers un `WorkflowNode`, étiquette `chaos-mesh.org/controlled-by` | un `Workflow` en cours | pause puis suppression du **Workflow** |
| annotation de pause présente mais `status.experiment.desiredPhase: Run`, condition `Paused` à `False` | pause mal posée : mauvaise clé (`chaos-mesh.org/pause` au lieu de `experiment.chaos-mesh.org/pause`) ou mauvaise valeur (seul `"true"` compte) | vraie pause, puis suppression ; retirer la fausse annotation |
| expérience dans un **autre espace** que `chaos-experiences` (`-A` !) | ne devrait pas exister : la VAP `medisphere-chaos-espaces` (M29-E09) la refuse ; si elle existe, la VAP a été contournée (liaison en `Warn`, exclusion trop large) | pause / suppression là où elle est ; incident de sécurité : qui, comment (ADR-0290) |

Ce que le contrôleur **veut** sur un pod se lit dans l'objet intermédiaire `PodNetworkChaos` (même nom que le pod, dans l'espace du pod) : `kubectl -n mediagenda-recette get podnetworkchaos <pod> -o yaml` (`spec.tcs`, `spec.ipsets`, `spec.iptables`, et `metadata.annotations`/`spec` qui disent de quelle expérience vient chaque règle).

## 2. Qui EMPÊCHE le retrait ?

```
admin@adm01:~$ kubectl -n chaos-experiences get networkchaos <nom> -o jsonpath='{.metadata.deletionTimestamp} {.metadata.finalizers}{"\n"}{.status.experiment.desiredPhase}{"\n"}'
admin@adm01:~$ kubectl -n chaos-experiences describe networkchaos <nom> | tail -20          # événements : Failed / Recovered
admin@adm01:~$ kubectl -n chaos-mesh logs deploy/chaos-controller-manager --since=15m | grep -i -E 'recover|error' | tail
admin@adm01:~$ kubectl -n chaos-mesh get pods -l app.kubernetes.io/component=chaos-daemon -o wide
admin@adm01:~$ kubectl -n chaos-mesh logs <daemon-du-nœud> --since=15m | tail -30
admin@adm01:~$ kubectl -n chaos-mesh get ds chaos-daemon -o jsonpath='{.spec.template.spec.containers[0].args}{"\n"}'
```

Le finaliseur `chaos-mesh/records` n'est levé que quand **chaque** enregistrement (`status.experiment.containerRecords`) est retiré. Il reste si le contrôleur n'arrive pas à faire retirer la panne par le `chaos-daemon` du nœud :

| Constat | Cause | Correctif |
|---|---|---|
| daemon `CrashLoopBackOff` ou erreurs « connection refused / no such file » vers le socket | configuration du daemon : `--runtime-socket-path` faux (valeurs `chaosDaemon.socketPath`/`runtime` du chart), socket containerd déplacé | corriger les **valeurs** dans `plateforme/gitops/valeurs/chaos-mesh/values.yaml` (revert par MR), attendre les daemons prêts : le contrôleur réessaie et lève le finaliseur seul |
| daemon absent d'un nœud (taint, ressources) | le DaemonSet ne couvre pas le nœud | tolérances / ressources du daemon |
| le pod visé n'existe plus | rien à retirer | le contrôleur doit le constater seul ; sinon forçage (§ 4) |

## 3. Preuve sur le nœud (lecture)

```
admin@adm01:~$ kubectl -n mediagenda-recette get pod <pod> -o jsonpath='{.spec.nodeName}{"\n"}'
admin@k8s-w0N:~$ id=$(sudo crictl pods --namespace mediagenda-recette --name '^<pod>$' --state ready -q)
admin@k8s-w0N:~$ pid=$(sudo crictl inspectp "$id" | jq .info.pid)
admin@k8s-w0N:~$ sudo nsenter -t "$pid" -n tc qdisc show dev eth0
qdisc netem 1: root refcnt 2 limit 1000 delay 300ms  20ms
   (expérience SANS cible : netem à la racine ; AVEC cible : arbre « prio » + « sfq », netem sur une
    bande, et règles iptables TC-TABLES-* qui y classent les paquets vers l'ipset de la cible — M29-E24)
   (sans netem : rien n'est posé ; la racine par défaut est « noqueue » ou « fq_codel » selon le noyau)
admin@k8s-w0N:~$ sudo nsenter -t "$pid" -n iptables-legacy -S | grep CHAOS     # partitions (iptables « legacy » du daemon)
```

## 4. Retrait manuel et forçage (dernier recours)

Seulement si le contrôleur ne peut plus retirer (pod disparu, daemon impossible à réparer à temps) **et** que la panne fait mal :

1. Retirer ce qui est posé, pod par pod, depuis le nœud (le `chaos-daemon` utilise la racine `qdisc` de `eth0` ; la supprimer remet la file par défaut) :
   ```
   admin@k8s-w0N:~$ sudo nsenter -t "$pid" -n tc qdisc del dev eth0 root
   admin@k8s-w0N:~$ sudo nsenter -t "$pid" -n iptables-legacy -S | grep -q CHAOS && echo "partition : voir 4 bis"
   ```
   4 bis (partition) : redémarrer le **pod** visé est plus sûr que d'éditer ses chaînes : un nouveau bac à sable = un nouvel espace réseau vierge (`kubectl -n <espace> delete pod <pod>` ; le Rollout/StatefulSet le recrée).
2. Forcer le finaliseur par l'annotation prévue par Chaos Mesh (le contrôleur lève alors le finaliseur sans attendre le retrait) :
   ```
   admin@adm01:~$ kubectl -n chaos-experiences annotate networkchaos <nom> chaos-mesh.chaos-mesh.org/cleanFinalizer=forced
   ```
   En tout dernier recours : `kubectl patch … --type=merge -p '{"metadata":{"finalizers":null}}'`.
3. Supprimer l'objet `PodNetworkChaos` du pod s'il porte encore la règle (sinon le contrôleur la reposera au prochain passage).
4. **Vérifier** : § 3 sur chaque pod visé (plus de `netem`, plus de `CHAOS-*`), p95 et 5xx revenus.

## 5. Après

Post-mortem court si l'effet a duré plus de 30 min ; ajouter au catalogue la cause et la prévention (Schedules en pause, durée obligatoire, revue des valeurs de Chaos Mesh, alerte « expérience active depuis plus de 30 min » sur `chaos_controller_manager_chaos_experiments`).
