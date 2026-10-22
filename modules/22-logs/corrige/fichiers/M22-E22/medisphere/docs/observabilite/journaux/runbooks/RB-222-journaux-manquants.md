# RB-222 — Des journaux manquent (nœud, équipe)

| | |
|---|---|
| Déclencheurs | Ticket « plus de journaux de X » ; alertes `AlloyAbsentDUnNoeud` (Prometheus) et `NoeudMuet` (ruler), voir § 4 |
| Durée | 20 à 45 min |
| Références | RB-220 (chercher), RB-223 (Loki refuse les écritures), RB-224 (requêtes), politique des journaux § 2 et § 3 |

**Règle d'or : on ne répare jamais un problème de vue en touchant à la rétention ou au compartiment.** D'abord prouver si les données existent.

## 0. Les données existent-elles ?

```
admin@adm01:~$ export LOKI_ADDR=http://loki.apps.par1.medisphere.internal:3100
admin@adm01:~$ for t in plateforme mediagenda medidoc audit; do echo "== $t"; logcli query --org-id=$t --since=1h --quiet --limit=3 '{node="<NŒUD>"}'; done
admin@adm01:~$ for t in plateforme mediagenda medidoc; do echo "== $t"; logcli query --org-id=$t --since=1h --quiet --limit=3 '{namespace=~"<ESPACES>"}'; done
```

- Rien nulle part pour un **nœud** → § 1 (collecte).
- Les lignes d'une **équipe** sont dans un **autre** locataire → § 2.1.
- Les lignes sont dans le bon locataire mais Grafana ne les montre pas → § 2.2.
- Les lignes récentes sont là, les anciennes « ont disparu » → § 2.3.

## 1. Un nœud est muet

| Étage | Question | Preuve | Correctif |
|---|---|---|---|
| Planification | Le DaemonSet a-t-il un pod sur ce nœud ? | `kubectl -n journaux get ds alloy` (souhaités = nœuds ?), `kubectl -n journaux get pods -o wide -l app.kubernetes.io/name=alloy`, `kubectl describe node <N>` (`Taints`) | Taint oubliée : la retirer (après avoir vérifié avec son auteur). Tolérance manquante dans `alloy/values.yaml` (`controller.tolerations`) : MR. Un agent de journaux doit tolérer **toutes** les taints de **tous** les nœuds |
| État d'Alloy | Le pod est-il prêt, ses composants sains ? | `kubectl -n journaux logs <pod>` ; interface `kubectl -n journaux port-forward <pod> 12345` → composants en erreur | Configuration invalide : revert de la MR ; positions illisibles : voir les journaux du composant |
| Sources (pods) | Les fichiers des pods sont-ils lus ? | métriques `loki_source_file_*` du pod Alloy ; `ls /var/log/pods/` sur le nœud | Montage `hostPath` manquant (`alloy.mounts.varlog`) : MR |
| Sources (journald) | journald écrit-il, et là où Alloy lit ? | sur le nœud : `logger -t essai test; journalctl -t essai -n1` ; `journalctl --header \| grep 'File path'` ; `ls -ld /var/log/journal /run/log/journal` ; `systemd-analyze cat-config systemd/journald.conf \| grep -i storage` | `Storage=none`/`volatile` posé à la main : retirer le fichier de configuration, relancer `systemd-journald` ; répertoire `/var/log/journal` déplacé : le remettre, puis `journalctl --flush` (le journal volatil part sur le disque). Reporter dans le rôle Ansible des nœuds |
| Envoi | Alloy envoie-t-il, Loki accepte-t-il ? | `loki_write_sent_entries_total`, `loki_write_dropped_entries_total` du pod ; erreurs `429`/`500` | RB-223 |

Ce qui n'a pas été lu pendant la panne : les fichiers des pods sont repris à la **position** enregistrée (sur `/var/lib/alloy` du nœud) tant que le kubelet ne les a pas fait tourner ; journald, dans la limite de `max_age` (7 h par défaut) et de ce que journald a gardé. Ce qui n'a jamais été écrit (journald en `Storage=none`) est perdu.

## 2. Une équipe ne voit plus ses journaux

### 2.1 Les lignes arrivent dans un autre locataire (collecte)

```
admin@adm01:~$ logcli query --org-id=plateforme --since=1h --quiet '{namespace=~"(mediagenda|medidoc)-.+"}' --limit=5
```

Si des lignes reviennent : la règle d'affectation du locataire d'Alloy (`alloy/config.alloy`, règles `regex` qui posent l'étiquette temporaire `locataire`, puis `stage.tenant`) a changé. `git log -p -- alloy/` ; revert par MR. Les lignes écrites dans `plateforme` pendant la panne y **restent** (rétention de 14 jours) : les signaler à l'équipe (requête dans `plateforme`), ne pas les effacer sauf décision écrite (RB-221 ne s'applique pas : `plateforme` est fermé à l'effacement).

### 2.2 Les lignes sont là, Grafana ne les montre pas (consultation)

- L'inspecteur de requête (*Query inspector*) de Grafana montre la requête ; le **locataire** est dans la définition de la source : `grafana/sources-loki.yaml` (en-tête `X-Scope-OrgID`, `httpHeaderValue1`). `git log -p -- grafana/` ; revert par MR ; le *sidecar* de Grafana recharge la source.
- Preuve rapide : la même requête par `logcli --org-id=<locataire>` renvoie des lignes, la source non.

### 2.3 Les lignes anciennes « ont disparu » (limites)

```
admin@adm01:~$ curl -s -H 'X-Scope-OrgID: medidoc' $LOKI_ADDR/config/tenant/v1/limits | grep -E '^(retention_period|max_query_lookback):'
```

`max_query_lookback` plus court que la rétention : les données sont **toujours** dans le compartiment, seule la requête est bornée. Corriger la surcharge dans `loki/values.yaml` (`runtimeConfig`) par MR. Si c'est `retention_period` qui a été raccourcie : ce n'est plus un problème de vue — arrêter la rétention (revert immédiat), puis la procédure de restauration de la politique § 4.

## 3. Clore

`lab/bin/check 22 19` et `lab/bin/check 22 22` ; réponse écrite à l'équipe : ce qui a été perdu (rien, ou quoi), ce qui a été mal rangé et où, ce qui est rétabli.

## 4. Ce qui aurait dû alerter

- `AlloyAbsentDUnNoeud` (Prometheus, `plateforme/observabilite/regles/alloy-collecte.yaml`) : pods Alloy prêts < nombre de nœuds `Ready` (`kube_daemonset_status_number_ready` contre `kube_node_status_condition`). Comparer à `desiredNumberScheduled` ne suffit pas : une taint ou une tolérance retirée le fait baisser aussi.
- Nœud muet : `count by (node) (count_over_time({job="journald"}[10m]))` absent pour un nœud `Ready` (règle du *ruler*, locataire `plateforme`).
- Flux d'une équipe dans `plateforme` : `sum(count_over_time({namespace=~"(mediagenda|medidoc)-.+"}[5m])) > 0` (*ruler*, locataire `plateforme`).
