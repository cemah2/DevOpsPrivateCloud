# RB-163 — Migrer un volume RWO vers une autre classe de stockage

| | |
|---|---|
| Propriétaire | Équipe Plateforme |
| Dernier usage | <AAAA-MM-JJ> (M16-E29, SEC-1729 : Valkey de la recette vers `ceph-rbd-chiffre`, coupure <DURÉE>) |
| Liens | RB-161, RB-160, `chiffrement.md`, politique de sauvegarde |

## D'abord : est-ce vraiment une migration ?

| Demande | Migration ? | Geste |
|---|---|---|
| Passer un volume en `Retain` (ou l'inverse) | **non** | `kubectl patch pv <pv> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'` |
| Agrandir | non | modifier `spec.resources.requests.storage` du PVC (classe avec `allowVolumeExpansion`) |
| Réduire | oui | copie vers un volume plus petit |
| Chiffrer (vers `ceph-rbd-chiffre`) | **oui** | ceph-csi ne chiffre pas un volume existant ; un clone d'une source en clair n'est pas une voie documentée |
| Changer de pilote (RBD ↔ CephFS, autre fournisseur) | **oui** | un instantané ne traverse pas les pilotes |
| Base CloudNativePG | **pas par ce runbook** | changer `storage.storageClass` du `Cluster` puis faire recréer les instances une à une par l'opérateur (à valider sur un cluster d'essai : documentation CNPG 1.30), ou import vers un nouveau cluster |

## Choisir la voie

| Voie | Coupure | Quand |
|---|---|---|
| Copie `rsync` à chaud puis à froid (ce runbook) | arrêt de l'application le temps de la copie finale et du redémarrage (secondes à minutes) | cas général RWO |
| Velero : sauvegarde, suppression, restauration avec la ConfigMap `change-storage-class` | toute la durée sauvegarde + restauration | espace entier, coupure acceptée |
| Réplication applicative (réplica sur le nouveau volume, bascule) | quasi nulle | applications qui savent se répliquer (Valkey, PostgreSQL) |

## Prérequis

- Sauvegarde récente de l'espace (Velero) ; quota du pool `k8s-rbd` ≥ taille du volume (deux copies coexistent).
- **Répétition** : coupure de l'application mesurée sur une copie (effet sur les sondes des applications qui en dépendent : si une sonde de disponibilité dépend de ce volume, l'adapter temporairement, par MR, et la rétablir).
- Utilisateur et groupe des fichiers (contexte de sécurité du pod), nœud du pod (RWO).

## Étapes (exemple : StatefulSet `<STS>`, PVC `<MODÈLE>-<STS>-0`)

1. **Retour arrière d'abord** : `kubectl patch pv <PV-SOURCE> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'`.
2. PVC cible temporaire sur la nouvelle classe, même taille ; Job de copie **à chaud** sur le nœud du pod (`nodeName`), source montée en lecture seule.
3. **Point de non-retour 1 (coupure)** : `kubectl scale sts <STS> --replicas=0` ; attendre la fin du pod (arrêt propre : l'application écrit ses données).
4. Job de copie **à froid** (`--delete`) ; contrôler la sortie (`--stats`).
5. Rattacher le volume cible sous le nom attendu :
   ```
   kubectl patch pv <PV-CIBLE> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
   kubectl delete pvc <PVC-TEMPORAIRE>
   kubectl patch pv <PV-CIBLE> --type json -p '[{"op":"remove","path":"/spec/claimRef"}]'
   kubectl delete pvc <MODÈLE>-<STS>-0                       # PV source conservé (Retain)
   kubectl apply -f pvc-final.yaml                           # même nom, volumeName: <PV-CIBLE>
   ```
6. `kubectl delete sts <STS> --cascade=orphan` (aucun pod ne tourne à ce stade) ; MR qui change `storageClassName` dans `volumeClaimTemplates` ; `task appliquer` ; `kubectl scale sts <STS> --replicas=1` si la MR ne le fait pas.
7. **Fin de coupure** : pod prêt. Contrôles : données témoins, volume monté depuis la bonne classe, chiffrement (`lsblk` : `crypt`), sonde de supervision verte.
8. Rétablir les sondes adaptées à l'étape « prérequis » (MR).
9. **Point de non-retour 2** (après validation, et au plus tard J+7) : remettre le PV source (`Released`) en `Delete` : `kubectl patch pv <PV-SOURCE> -p '{"spec":{"persistentVolumeReclaimPolicy":"Delete"}}'` ; le provisionneur supprime alors l'image RBD et ses entrées de journal, puis le PV. Contrôle : `rbd ls k8s-rbd` sur `ceph01`. (Un `kubectl delete pv` d'un PV `Retain` laisse l'image dans Ceph.) Remettre le PV cible en `Delete` si c'est la politique de la classe.

## Retour arrière (avant le point de non-retour 2)

Arrêter l'application, supprimer le PVC final, retirer le `claimRef` du PV source, recréer le PVC d'origine avec `volumeName: <PV-SOURCE>` et l'ancienne classe, recréer le StatefulSet d'origine (`--cascade=orphan` puis MR de retour), redémarrer.

## Pièges

- Supprimer un PVC dont le PV est en `Delete` : l'image disparaît, pas de retour arrière.
- Monter un RWO sur un autre nœud pendant que l'application tourne : *Multi-Attach*.
- `rsync` non root avec `-a` : erreurs de `chown` ; ou copie en root : fichiers illisibles par l'application.
- Oublier `--cascade=orphan` : la suppression du StatefulSet arrête les pods (et selon `persistentVolumeClaimRetentionPolicy`, supprime les PVC).
- Oublier l'image RBD d'un PV `Retain` supprimé : elle consomme le quota du pool pour toujours.
