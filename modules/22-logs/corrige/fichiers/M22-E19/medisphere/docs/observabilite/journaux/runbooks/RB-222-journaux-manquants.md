# RB-222 — Des journaux manquent (nœud, équipe)

| | |
|---|---|
| Déclencheurs | Ticket « plus de journaux de X » ; alertes `AlloyAbsentDUnNoeud`, `NoeudMuet` (à créer, voir § 4) |
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
- Une **équipe** ne voit plus ses journaux → § 2.

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

*(ajouté en M22-E22)*

## 3. Clore

`lab/bin/check 22 19` ; réponse écrite à l'équipe : ce qui a été perdu (rien, ou quoi), ce qui a été mal rangé et où, ce qui est rétabli.

## 4. Ce qui aurait dû alerter

- `kube_daemonset_status_number_ready{daemonset="alloy"} < kube_daemonset_status_desired_number_scheduled` et nombre de pods Alloy < nombre de nœuds (Prometheus).
- Nœud muet : `count by (node) (count_over_time({job="journald"}[10m]))` absent pour un nœud `Ready` (règle du *ruler*, locataire `plateforme`).
