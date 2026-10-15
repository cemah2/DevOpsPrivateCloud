# RB-161 — Restaurer un espace de noms

| | |
|---|---|
| Propriétaire | Équipe Plateforme |
| Dernier essai | <AAAA-MM-JJ> (M16-E24, PLAT-1724), RTO mesuré : <DURÉE> |
| Liens | RB-162 (PostgreSQL à un instant donné), politique de sauvegarde (`../politique-sauvegarde.md`), ADR-0160 |

## Quand l'utiliser

- Un espace de noms applicatif a été supprimé, ou ses objets abîmés au point qu'un `git revert` du déploiement ne suffit pas (données de volumes perdues ou corrompues).
- Une copie d'un espace est demandée pour une enquête ou un essai (**copie inactive**, jamais publiée).
- Pas pour : quelques lignes supprimées dans une base (→ RB-162, récupération sélective) ; un cluster entier perdu (→ restauration etcd RB-141 ou reconstruction + ce runbook espace par espace).

## Décisions à prendre (et à écrire dans le ticket) avant de toucher à quoi que ce soit

1. **Où** restaurer : dans l'espace d'origine (il n'existe plus ou a été vidé) ou dans `wb-restauration` (enquête, essai, ou original encore présent). Par défaut : `wb-restauration`.
2. **Quelle sauvegarde** Velero : `velero backup get` ; la plus récente `Completed` antérieure à l'incident. Une sauvegarde `PartiallyFailed` se lit (`velero backup describe --details`) avant d'être utilisée.
3. **Quel instant pour la base** : la base n'est **pas** restaurée par Velero mais par CloudNativePG depuis ses archives (`cnpg-s3`), au plus récent ou à un instant donné (RB-162). Choisir l'instant : juste avant l'incident.
4. **Qui prévenir** : l'équipe propriétaire (Julien pour MédiAgenda), Sophie si la copie contient des données de santé (toujours, pour `mediagenda-*`).

## Prérequis

- Velero sain (`velero backup-location get` : `s3-01` `Available`) ; node-agent prêt sur chaque travailleur.
- Opérateur CloudNativePG et plugin Barman Cloud sains ; `ObjectStore` présent dans la sauvegarde.
- Marge du quota du pool `k8s-rbd` (`ceph osd pool get-quota k8s-rbd`, `ceph df`) ≥ taille des PVC de l'espace.
- Cible : `wb-restauration` existe (code `plateforme/k8s/espaces/`), vide.

## Étapes

| # | Action | Commande / fichier | Durée mesurée |
|---|---|---|---|
| 1 | Vérifier la cible vide | `kubectl get all,pvc -n wb-restauration` | |
| 2 | Relire et adapter le manifeste `Restore` (sauvegarde, `namespaceMapping`) | `plateforme/k8s/composants/velero/restaurations/` | |
| 3 | Vérifier la ConfigMap de modificateurs (noms d'hôtes, CronJobs) | `kubectl get cm modificateurs-restauration -n velero -o yaml` | |
| 4 | Appliquer et suivre | `kubectl apply -f <restore>.yaml` ; `velero restore describe <nom> --details` ; `kubectl get datadownloads -n velero -w` | |
| 5 | Lire avertissements et erreurs | `velero restore logs <nom> \| grep -Ei 'error\|warn'` | |
| 6 | Créer le `Cluster` de récupération (une instance, **sans** `.spec.plugins`) | `kubectl apply -f composants/cnpg/wb-restauration/mediagenda-db-recuperation.yaml` | |
| 7 | Suivre la récupération | `kubectl cnpg status mediagenda-db -n wb-restauration` ; journaux du pod `mediagenda-db-1-full-recovery-*` | |
| 8 | Attendre que tout soit prêt | `kubectl get deploy,sts,pods -n wb-restauration` | |

**RTO** = de la décision (étape 1) à l'étape 8 terminée et aux contrôles faits.

## Contrôles (tous, avant de déclarer la restauration réussie)

- Pods prêts ; l'API répond par `kubectl port-forward` (`/pret` 200, liste des rendez-vous).
- Empreintes identiques à la source ou à l'état attendu : `outils/empreinte-mediagenda.sh <espace>` (nombre de lignes, empreinte de table, clés Valkey).
- L'API de la copie vise la base de la copie (Secret `mediagenda-db-app` de la copie : hôte `mediagenda-db-rw.wb-restauration`) ; `pg_stat_activity` de la copie montre les connexions de l'API.
- Copie **non publiée** : HTTPRoute non acceptée (`kubectl get httproute -n wb-restauration -o yaml` : condition `Accepted` à `False`), aucun enregistrement `mediagenda-restauration` dans `apps.par1.medisphere.internal`.
- Copie **inactive** : CronJobs suspendus ; aucun `ScheduledBackup` ; aucun nouveau WAL sous un autre préfixe que celui de l'original dans `cnpg-k8s-par1`.
- Original intact (si présent) : `kubectl cnpg status mediagenda-db -n mediagenda-recette`, API publiée prête.

## Retour arrière

Une restauration dans `wb-restauration` ne modifie rien ailleurs : le retour arrière est la suppression de la copie. Une restauration **dans l'espace d'origine** se fait sur un espace vide ou supprimé : si elle échoue à mi-chemin, supprimer l'espace (les PVC restaurés partent avec, classes en `Delete`) et recommencer.

## Nettoyage (obligatoire : la copie contient des données de santé)

```
admin@adm01:~$ kubectl delete cluster mediagenda-db -n wb-restauration
admin@adm01:~$ kubectl delete all,pvc,cm,secret,networkpolicy,ciliumnetworkpolicy,httproute,objectstore -n wb-restauration --all
admin@adm01:~$ kubectl get pv | grep wb-restauration          # rien
[admin@ceph01 ~]$ sudo rbd ls k8s-rbd | wc -l                 # revenu au nombre d'avant
```

L'espace `wb-restauration` lui-même reste (il est décrit par le code), vide. Les objets `Restore` de l'espace `velero` sont conservés comme trace.

## Pièges connus

- Oublier `namespaceMapping` : les objets manquants sont recréés **dans l'original**.
- Restaurer le `Cluster` CloudNativePG et ses PVC par Velero : l'opérateur reçoit des volumes sans l'état qui va avec ; et une copie qui archive écrirait dans les archives de l'original.
- Secrets générés qui contiennent le nom de l'espace (chaîne de connexion) : restaurés tels quels, ils font viser l'original par la copie.
- HTTPRoute restaurée avec le nom public : deux routes pour un même nom sur `gw-par1`.
