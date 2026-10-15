# RB-164 — Mettre à jour ceph-csi, CloudNativePG et le plugin Barman Cloud (versions correctives)

| | |
|---|---|
| Propriétaire | Équipe Plateforme |
| Dernier usage | <AAAA-MM-JJ> (M16-E33, CHG-1733) |
| Liens | RB-142 (montée de version de Kubernetes), ADR-0141 (politique de versions), ADR-0160 |

## Périmètre

Versions **correctives** (3.18.x, 1.30.x, 0.15.x). Une version **mineure** (ceph-csi 3.19, CloudNativePG 1.31) est un projet : notes de rupture, compatibilités (Kubernetes, Ceph), répétition sur `pg-essai`/`wb-essais`, fenêtre annoncée. Rappel 1.31 : suppression de `barmanObjectStore` intégré.

## Avant (J-1)

1. Lire les notes de version de chaque corrective ; noter : correctifs de sécurité, changements de CRD, de valeurs du chart, d'images annexes (*sidecars* CSI, image du *sidecar* du plugin).
2. Matrice : composant, de → vers, compatibilité Kubernetes 1.36 / Ceph Tentacle / cert-manager 1.21, ce qui redémarre, retour arrière.
3. Annoncer la fenêtre (canal de Julien), hors démonstration.

## Prérequis (le jour même, tous verts)

- `ms-verif-k8s-stockage` et `ms-verif-ceph` verts.
- Sauvegarde Velero à la demande de `mediagenda-recette` `Completed` ; sauvegarde de base `completed` de chaque `Cluster` ; `ContinuousArchiving` `True`.
- Instantané etcd de moins d'une heure.
- Aucun `Cluster` en `barmanObjectStore` intégré : `kubectl get clusters.postgresql.cnpg.io -A -o json | jq '.items[] | select(.spec.backup.barmanObjectStore) | .metadata.name'` vide.

## Témoins (lancés avant, arrêtés après chaque composant)

- `outils/temoin-api.sh` (API publiée) ;
- `wb-essais/temoins-volumes.yaml` (écriture chaque seconde sur `ceph-rbd` et `cephfs`) ;
- `outils/temoins-stockage.sh provisionnement` (un PVC par minute).

## Étapes — un composant à la fois, sonde verte entre deux

| # | Composant | Geste | Ce qui redémarre | Attendu des témoins |
|---|---|---|---|---|
| 1 | ceph-csi **CephFS** | MR : version du chart `ceph-csi-cephfs` ; `task appliquer` | contrôleurs (Deployment, un réplica à la fois), *nodeplugins* (DaemonSet, un nœud à la fois) | écritures CephFS continues (client noyau) ; provisionnement CephFS interrompu quelques secondes |
| 2 | ceph-csi **RBD** | idem `ceph-csi-rbd` | idem | écritures RBD continues (`rbdN` du noyau) ; nouveaux montages sur un nœud impossibles pendant le redémarrage de son *nodeplugin* |
| 3 | Opérateur CloudNativePG | MR : version du chart `cloudnative-pg` ; `task appliquer` | CRD (gabarits du chart), Deployment de l'opérateur ; **instances** : en place si `ENABLE_INSTANCE_MANAGER_INPLACE_UPDATES=true`, sinon redémarrage progressif + **bascule** | en place : 0 erreur ; sinon : la coupure d'une bascule planifiée (E25) |
| 4 | Plugin Barman Cloud | MR : version du chart `plugin-barman-cloud` ; `task appliquer` | Deployment du plugin ; **sidecar** des instances si son image change (redémarrage des pods : à vérifier dans les notes) | archivage repris (`ContinuousArchiving` `True`), aucune erreur côté API si en place |

Suivi :
```
kubectl rollout status -n ceph-csi daemonset/<nodeplugin> ; kubectl rollout status -n ceph-csi deployment/<provisioner>
kubectl get pods -n ceph-csi -o custom-columns=NOM:.metadata.name,IMAGE:.spec.containers[*].image
kubectl rollout status -n cnpg-system deployment/<opérateur> ; kubectl cnpg status mediagenda-db -n mediagenda-recette
kubectl get clusters.postgresql.cnpg.io -A ; kubectl get pods -n mediagenda-recette -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[*].image}{"\n"}{end}'
```

## Contrôles finaux

- Toutes les images à la version cible ; DaemonSets `updatedNumberScheduled == desiredNumberScheduled`, tous prêts.
- Sonde verte ; sauvegarde de base à la demande `completed` ; un PVC `ceph-rbd-chiffre` créé, monté, supprimé.
- Témoins arrêtés, leurs journaux joints au compte rendu ; témoins supprimés de `wb-essais`.

## Retour arrière

- **ceph-csi** : `helm rollback <release> <révision>` sûr pour une corrective (pas de CRD propres au chart ; images et RBAC seulement). Mêmes redémarrages qu'à l'aller.
- **Opérateur CloudNativePG** : les CRD suivent le chart ; un retour arrière remet d'anciennes CRD sous des objets écrits par la nouvelle version. Préférer **corriger en avant** (corrective suivante, ou réglage). Si inévitable : `helm rollback` après lecture des notes, en sachant que les instances redémarreront.
- **Plugin** : `helm rollback`, puis vérifier l'archivage.

## Pièges

- Deux composants à la fois : impossible d'attribuer une coupure.
- Oublier que la mise à jour de l'opérateur touche **tous** les `Cluster` du lab en même temps (`CLUSTERS_ROLLOUT_DELAY`).
- Client CephFS FUSE ou `rbd-nbd` sur un nœud : le redémarrage du *nodeplugin* coupe les montages (documentation ceph-csi) ; vérifier `mounter` et les options des classes avant.
