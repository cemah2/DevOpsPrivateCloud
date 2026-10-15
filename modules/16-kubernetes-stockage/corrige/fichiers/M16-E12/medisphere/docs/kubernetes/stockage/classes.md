# Catalogue des classes de stockage de `k8s-par1`

> Propriétaire : équipe Plateforme. Source : `plateforme/k8s` (`composants/ceph-csi/classes/`). Ticket d'origine : PLAT-1712 (M16-E12). Toute nouvelle classe passe par une MR relue et met ce catalogue à jour.

## Règles générales

- **Une seule classe par défaut : `ceph-rbd`.** Un PVC sans `storageClassName` la reçoit à la création (contrôleur d'admission `DefaultStorageClass`) ou, s'il a été créé pendant une absence de classe par défaut, dès qu'elle revient (attribution rétroactive, GA en 1.28). Avec deux classes par défaut, Kubernetes prend la plus récente (depuis 1.26) : c'est une erreur de configuration, jamais un choix.
- `storageClassName: ""` (chaîne vide) signifie « un PV statique sans classe » : jamais de provisionnement ni d'attribution rétroactive. Interdit dans les espaces d'équipe (VAP `classes-stockage`, M16-E20).
- Les champs d'une StorageClass sont immuables. La « modifier », c'est la supprimer et la recréer sous le même nom : les PV existants ne bougent pas (ils portent ce qu'il leur faut), les nouveaux PVC prennent la nouvelle définition. À faire en MR, hors des heures de déploiement.
- Les classes autorisées par espace d'équipe sont dans l'annotation `medisphere.internal/classes-stockage` de l'espace (M16-E20) ; les plafonds dans `quota-stockage`.

## Les classes

| Classe | Pilote | Usage | Modes d'accès | Récupération | Agrandissement | Instantanés (classe) | Qui |
|---|---|---|---|---|---|---|---|
| `ceph-rbd` (défaut) | `rbd.csi.ceph.com`, pool `k8s-rbd` de `ceph-par1` | Bases de données, files, cache persistant : tout volume d'un seul pod | RWO, RWOP ; RWX **en mode bloc seulement** | `Delete` : le volume Ceph est détruit avec le PVC | oui, en ligne | `ceph-rbd-snap` (copie sur écriture, instantané rapide) | toutes les équipes |
| `ceph-rbd-retain` | idem | Données qu'on ne doit pas perdre par une suppression de PVC (archives réglementaires, migrations) | idem | `Retain` : le PV passe `Released`, l'image RBD reste ; nettoyage **manuel** par la plateforme | oui | `ceph-rbd-snap` | plateforme seulement (quota 0 pour les équipes) |
| `cephfs` | `cephfs.csi.ceph.com`, volume CephFS `cephfs`, groupe de sous-volumes `csi` | Fichiers partagés entre plusieurs pods (MédiDoc, traitements par lots) | RWO, RWX, ROX | `Delete` | oui (quota du sous-volume, immédiat) | `cephfs-snap` (restauration = **copie complète**, lente) | toutes les équipes, sur demande justifiée |

### Paramètres significatifs (`ceph-rbd`)

| Paramètre | Valeur | Pourquoi |
|---|---|---|
| `clusterID` | fsid de `ceph-par1` | Clé d'entrée de la ConfigMap `ceph-csi-config` (moniteurs) |
| `pool` | `k8s-rbd` | Pool dédié au cluster, identité `client.k8s` limitée à lui |
| `imageFeatures` | `layering,exclusive-lock,object-map,fast-diff,deep-flatten` | Gérées par krbd 6.12 ; **jamais `journaling`** (non géré par le pilote noyau : le montage échoue) |
| `mapOptions` | `krbd:ms_mode=secure` | Le noyau mappe l'image en msgr2 chiffré (port 3300), sans repli en clair |
| `csi.storage.k8s.io/fstype` | `ext4` | Système de fichiers créé au premier montage |
| `…/provisioner-secret-*`, `…/controller-expand-secret-*`, `…/controller-publish-secret-*`, `…/node-stage-secret-*` | `csi-rbd-secret` (`ceph-csi`) | Identité Ceph (`client.k8s`) pour créer, agrandir, attacher, mapper ; jamais `client.admin` |
| `mountOptions` | `discard` | Les blocs libérés par ext4 sont rendus au pool (images allouées à la demande) |
| `reclaimPolicy` | `Delete` | Les volumes suivent leur PVC |
| `allowVolumeExpansion` | `true` | Agrandissement à chaud (M16-E11) |
| `volumeBindingMode` | `Immediate` | Voir ci-dessous |

### Position sur `WaitForFirstConsumer` pour `ceph-rbd`

Le pilote ceph-csi n'annonce **aucune topologie** (`CSINode.spec.drivers[].topologyKeys` vide) : tous les travailleurs joignent `ceph-par1` par le VLAN 30, un volume RBD est montable partout. `WaitForFirstConsumer` n'apporte donc pas de placement correct ; il apporte seulement qu'un volume n'est pas créé pour un pod qui ne pourra jamais démarrer (quota consommé pour rien, image orpheline si le PVC est oublié). En face, il change le comportement observé par les équipes (PVC `Pending` normal tant qu'aucun pod ne le consomme) et imposerait de recréer la classe.

**Décision** : `ceph-rbd` reste en `Immediate` en v1 ; toute nouvelle classe liée à une topologie (stockage local, Ceph par baie) sera en `WaitForFirstConsumer`. À revoir dans l'ADR-0160 (M16-E30).

### `allowedTopologies`

Avec un pilote sans topologie, `allowedTopologies` n'est lu que par **l'ordonnanceur** (avec `WaitForFirstConsumer`) : il contraint le pod du **premier** montage, pas le volume (le PV n'a pas de `nodeAffinity`). Un pod suivant peut monter le volume ailleurs. Ce n'est donc pas un moyen de garder des données dans une baie avec `ceph-rbd` : pour cela, il faut que les données soient physiquement dans la baie (règle CRUSH par baie et pool dédié) et que le pilote annonce une topologie.

## Ce qu'on ne fait pas

- Créer une classe « rapide » qui pointe vers le même pool : elle n'est pas plus rapide.
- Utiliser `ceph-rbd` en RWX en mode fichier (le provisionnement échoue) ; demander `cephfs`.
- Marquer une deuxième classe par défaut, ou retirer l'annotation de `ceph-rbd` « pour essayer ».
- Créer un PV `hostPath` à la main pour débloquer un PVC (RB-160).
