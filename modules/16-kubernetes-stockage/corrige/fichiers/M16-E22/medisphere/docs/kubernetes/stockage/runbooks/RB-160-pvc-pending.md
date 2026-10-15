# RB-160 — Un PVC reste `Pending`

| | |
|---|---|
| **Objet** | Diagnostiquer et corriger un PersistentVolumeClaim qui ne passe pas `Bound` (ou un pod `Pending` à cause de son volume) sur `k8s-par1` |
| **Déclencheur** | Ticket d'un développeur (« mon pod est Pending », « `unbound immediate PersistentVolumeClaims` », « `waiting for a volume to be created` ») ; alerte PVC Pending > 10 min (M21) |
| **Public** | Astreinte niveau 1 (support), droits `medisphere:lecture` + `describe` dans les espaces d'équipe ; pas d'accès à `ceph01` |
| **Durée cible** | 15 min pour qualifier, escalade au-delà |
| **Propriétaire** | Équipe Plateforme — dernière révision : M16-E22 (PLAT-1722) |

## 0. Entrée rapide : message → section

| Ce que tu vois | Section |
|---|---|
| PVC `Pending`, événement `WaitForFirstConsumer` / « waiting for first consumer to be created before binding » | [2](#2-attente-normale) |
| PVC `Pending`, `storageclass.storage.k8s.io "…" not found` | [3.1](#31-classe-inexistante) |
| PVC `Pending` **sans aucun événement**, `spec.storageClassName` absent ou `""` | [3.2](#32-pas-de-classe) |
| L'objet PVC n'existe pas ; `kubectl apply` ou le contrôleur dit `exceeded quota` | [4.1](#41-quota) |
| … dit `maximum storage usage per PersistentVolumeClaim` / `minimum storage` | [4.2](#42-limitrange) |
| … dit `ValidatingAdmissionPolicy 'classes-stockage' … denied` / `classe de stockage « … » refusée` | [4.3](#43-classe-refusée-par-la-politique) |
| `ProvisioningFailed` … ``multi node access modes are only supported on rbd `block` type volumes`` (code `InvalidArgument`) | [5.1](#51-mode-daccès-impossible) |
| `ExternalProvisioning` : « waiting for a volume to be created … by external provisioner » qui dure | [6.1](#61-le-provisionneur-ne-répond-pas) |
| `ProvisioningFailed` … `rpc error` … `permission denied`, `secrets "…" not found`, `failed to get credentials` | [6.2](#62-identité-ou-secret) |
| `ProvisioningFailed` … `context deadline exceeded`, `connection timed out`, `EDQUOT`, `No space left` | [7](#7-ceph-injoignable-ou-plein) |
| `ProvisioningFailed` … `VolumeSnapshot … not found` / `not ready` / `source is from a different driver` | [5.2](#52-restauration-ou-clone-impossible) |

## 1. Qualifier (toujours, 2 minutes)

```
kubectl -n <ESPACE> get pvc <PVC> -o wide
kubectl -n <ESPACE> describe pvc <PVC>            # lire la section Events, de bas en haut
kubectl -n <ESPACE> get pvc <PVC> -o jsonpath='{.spec.storageClassName}{"\n"}{.spec.accessModes}{"\n"}{.spec.volumeMode}{"\n"}{.spec.dataSource}{"\n"}'
kubectl get storageclass
```

Note dans le ticket : espace, PVC, classe, modes d'accès, taille, qui l'a créé (manifeste, StatefulSet, opérateur CNPG, Velero), heure. **Si le PVC n'existe pas du tout**, l'erreur est chez celui qui l'a demandé : section [4](#4-le-pvc-na-pas-été-créé).

Où trouver l'erreur quand un **contrôleur** crée le PVC :

```
kubectl -n <ESPACE> describe statefulset <STS>       # événements FailedCreate
kubectl -n <ESPACE> describe cluster <CLUSTER-CNPG>  # (CRD postgresql.cnpg.io) et journal de l'opérateur :
kubectl -n cnpg-system logs deploy/cnpg-cloudnative-pg --since=15m | grep <CLUSTER-CNPG>
kubectl -n velero logs deploy/velero --since=15m | grep -i persistentvolumeclaim   # restauration
```

## 2. Attente normale

Événement `WaitForFirstConsumer` : la classe lie le volume au premier pod. **Ce n'est pas une panne** tant qu'aucun pod n'utilise le PVC.

- Un pod l'utilise et il est `Pending` : `kubectl -n <ESPACE> describe pod <POD>` ; le problème est l'**ordonnancement** du pod (ressources, *taints*, `nodeSelector`, `allowedTopologies` de la classe), pas le stockage → RB-140/runbooks de l'équipe, ou escalade.
- Correctif : aucun côté stockage. Réponds au développeur.

## 3. La classe

### 3.1 Classe inexistante

`kubectl get sc <CLASSE>` → `NotFound`. Typiquement une faute (`ceph-rdb`, `ceph-rbd-retian`) ou une classe d'un autre cluster (kind, `standard`, `local-path`).

- **Qui corrige** : le développeur (son manifeste). Un PVC est immuable sur ce champ : il faut le **supprimer et le recréer** (s'il n'a jamais été lié, aucune donnée n'est perdue).
- Contrôle : le nouveau PVC passe `Bound` en moins d'une minute.

### 3.2 Pas de classe

- `spec.storageClassName` **absent** et `kubectl get sc` ne montre **aucune** classe `(default)` : quelqu'un a retiré l'annotation de `ceph-rbd`. **Escalade plateforme immédiate** (tous les nouveaux PVC sans classe sont concernés). Quand l'annotation revient, les PVC sans classe la reçoivent seuls (attribution rétroactive) : ne les supprime pas.
- `spec.storageClassName: ""` : le PVC demande un PV **statique sans classe** ; il n'y en a pas (et il ne doit pas y en avoir). Le développeur recrée son PVC sans le champ (ou avec `ceph-rbd`).

## 4. Le PVC n'a pas été créé

### 4.1 Quota

Message `exceeded quota: quota-stockage, requested: …, used: …, limited: …`.

```
kubectl -n <ESPACE> describe quota quota-stockage
kubectl -n <ESPACE> get pvc -o custom-columns=NOM:.metadata.name,CLASSE:.spec.storageClassName,TAILLE:.spec.resources.requests.storage,ETAT:.status.phase
```

- Le quota compte la **taille demandée** des PVC existants, liés ou non, y compris les PVC `Released` ou oubliés. Souvent : des PVC d'essai à supprimer (par l'équipe), ou des PVC d'un StatefulSet réduit (rétention `Retain`).
- **Qui corrige** : l'équipe (ménage) ; une augmentation passe par une demande à la plateforme (`docs/kubernetes/stockage/quotas.md`), jamais par l'astreinte.
- `ceph-rbd-retain` à 0 : normal, la classe est réservée à la plateforme.

### 4.2 LimitRange

Message `maximum storage usage per PersistentVolumeClaim is …` (ou `minimum`) : la taille demandée sort des bornes de `limites-pvc`. Le développeur ajuste la taille ; une exception passe par la plateforme.

### 4.3 Classe refusée par la politique

Message de la VAP `classes-stockage` : la classe n'est pas dans l'annotation `medisphere.internal/classes-stockage` de l'espace.

```
kubectl get namespace <ESPACE> -o jsonpath='{.metadata.annotations.medisphere\.internal/classes-stockage}{"\n"}'
```

- Le développeur choisit une classe autorisée. Ouvrir une nouvelle classe à une équipe : demande à la plateforme (MR sur `plateforme/k8s`, `espaces/<ESPACE>/00-namespace.yaml`).

## 5. La demande est impossible

### 5.1 Mode d'accès impossible

`ReadWriteMany` sur `ceph-rbd` en mode fichier : RBD ne le sait pas (un système de fichiers ext4 monté par deux nœuds se corrompt). Le développeur recrée le PVC sur `cephfs` (fichiers partagés) ; `ReadWriteMany` sur `ceph-rbd` n'existe qu'en `volumeMode: Block` (cas très spécifiques : escalade).

### 5.2 Restauration ou clone impossible

`dataSource` vers un `VolumeSnapshot` absent, pas prêt (`readyToUse: false`), d'un autre espace, ou d'un autre pilote (instantané `cephfs-snap` vers un PVC `ceph-rbd`) ; taille demandée inférieure à la source.

```
kubectl -n <ESPACE> get volumesnapshot <INSTANTANE> -o wide
```

Le développeur corrige la source ou la taille. Changer de classe passe par une copie (RB-163), pas par un clone.

## 6. Le pilote

À partir d'ici, ce n'est plus le manifeste : **la plateforme est concernée**, même si tu peux qualifier.

### 6.1 Le provisionneur ne répond pas

```
kubectl -n ceph-csi get pods -o wide
kubectl -n ceph-csi get lease                                    # qui est leader ?
kubectl -n ceph-csi logs deploy/ceph-csi-rbd-provisioner -c csi-provisioner --since=15m | tail -50
kubectl -n ceph-csi logs deploy/ceph-csi-rbd-provisioner -c csi-rbdplugin --since=15m | tail -50
```

(`ceph-csi-cephfs-provisioner` pour CephFS.) Pods absents, `CrashLoopBackOff`, `Pending`, ou aucun leader : **escalade plateforme**. N'essaie pas de redémarrer les pods du pilote toi-même.

### 6.2 Identité ou Secret

Messages `secrets "csi-rbd-secret" not found`, `permission denied`, `failed to get credentials` : le Secret du provisionneur a disparu ou ne correspond plus à l'identité Ceph. **Escalade plateforme** (correctif : `outils/ceph-csi-secrets.sh appliquer` depuis le Vault, par la plateforme).

## 7. Ceph injoignable ou plein

Messages `context deadline exceeded`, `connection timed out` (moniteurs injoignables depuis les nœuds), `EDQUOT` ou `No space left on device` (quota du pool `k8s-rbd` atteint, cluster plein) : **escalade équipe Ceph** (Karim). Joins : nom du PVC, classe, heure, extrait des journaux de la section 6.1.

## 8. Gestes interdits

- Créer à la main un PV (`hostPath`, `local`, NFS…) « pour débloquer » : données hors sauvegarde, hors chiffrement, liées à un nœud.
- Retirer un *finalizer* d'un PVC ou d'un PV (`kubernetes.io/pvc-protection`, `external-provisioner…`) : volumes orphelins ou données détruites sous un pod.
- Retirer ou ajouter l'annotation de classe par défaut, supprimer/recréer une StorageClass en urgence.
- Mettre la clé `client.admin` (ou toute autre clé) dans un Secret du pilote.
- Augmenter un quota ou modifier l'annotation d'un espace sans ticket de la plateforme.

## 9. Escalade

| Cas | Vers | À joindre |
|---|---|---|
| Plus de classe par défaut, provisionneur absent ou sans leader, Secret du pilote | Plateforme (astreinte N2) | Sorties des sections 1 et 6 |
| Ceph injoignable, plein, `EDQUOT` | Équipe Ceph | Sorties 1, 6.1, heure de début |
| Plusieurs équipes touchées en même temps | Plateforme **et** incident `INC-` | Liste des PVC concernés |

## 10. Retour arrière

Les correctifs de niveau 1 ne modifient que des objets de l'équipe (PVC recréé, PVC d'essai supprimé) : le retour arrière est la recréation de l'objet d'origine (manifeste de l'équipe). Avant de supprimer un PVC `Pending`, vérifie qu'il n'a **jamais** été lié (`kubectl get pvc -o jsonpath='{.spec.volumeName}'` vide) : sinon, ne supprime rien et escalade.

## Historique

| Date | Auteur | Changement |
|---|---|---|
| 2026-10 | <MOI> | Création (M16-E22), joué sur trois cas dans `wb-essais` : classe mal orthographiée, quota, RWX sur `ceph-rbd` |
