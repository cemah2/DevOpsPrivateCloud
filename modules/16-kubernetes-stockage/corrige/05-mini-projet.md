# Module 16 — Palier 5 : Mini-projet — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

### M16-E46 — Mini-projet : données Kubernetes MédiSphère v1

Il n'y a pas de solution unique : ce corrigé donne un **plan de travail** éprouvé, les points de contrôle de chaque étape, la préparation des deux démonstrations, et la **grille de revue** avec laquelle Claire, Karim, Sophie, Nadia et Julien évaluent la livraison. Les fichiers de référence sont ceux des exercices du module ; les seuls nouveaux sont dans [`fichiers/M16-E46/`](fichiers/M16-E46/) : les manifestes de MédiDoc sur le RGW ([`30-medidoc.yaml`](fichiers/M16-E46/k8s/espaces/medidoc-dev/30-medidoc.yaml)) et le script de son Secret ([`secret-medidoc-s3.sh`](fichiers/M16-E46/k8s/outils/secret-medidoc-s3.sh)), la planification Velero de la recette ([`planifications-recette.yaml`](fichiers/M16-E46/k8s/composants/velero/planifications-recette.yaml)) et le modèle de procès-verbal ([`recette-k8s-stockage-v1.md`](fichiers/M16-E46/medisphere/docs/kubernetes/stockage/recette-k8s-stockage-v1.md)).

**Points non testés en conditions réelles** : la sortie des pods de MédiDoc vers 10.10.30.200 par la carte VLAN 30 des travailleurs (traduction d'adresse de Cilium sur cette interface : à vérifier avec Hubble et dans le journal d'accès du RGW ; si l'adresse source vue par le RGW est une adresse de pod, la réponse repart par la bordure et la connexion échoue) ; le sélecteur `cnpg.io/cluster DoesNotExist` de la planification Velero (objets générés par CloudNativePG tous étiquetés : à vérifier avec `velero backup describe --details`).

**Solution**

*Plan de travail recommandé* (dans cet ordre : chaque étape libère de la mémoire ou sécurise la suivante)

1. **État des lieux** (1 h) : `lab/bin/check 16 46`, puis les contrôles détaillés rouges, et `lab/bin/check 15 46` (réseau, publication) et `lab/bin/check 08 46` (`ceph-par1`). Liste des restes : `kubectl get ns` (`rook-ceph`, `longhorn-system`, `wb-restauration`), `kubectl get crd | grep -E 'rook|longhorn'`, `kubectl get sc`, `kubectl get cluster -A` (clusters PostgreSQL d'essai : `mediagenda-db-pitr`, montée de version du M16-E25), `kubectl get pvc -A`, `qm config 2144` à `2146` (disques `scsi1`/`scsi2`), `ls /var/lib/rook`, `findmnt /var/lib/longhorn` sur les travailleurs, `ls ~/.local/state/workbook/pannes-actives/`.
2. **Sauvegarde d'abord** (30 min) : une sauvegarde de base CloudNativePG et une sauvegarde Velero complètes et vérifiées **avant** toute suppression ; c'est le filet si un retrait emporte plus que prévu.
3. **Retirer Longhorn puis Rook** (2 à 3 h) : volumes qui y vivent encore migrés (M16-E29) ou déclarés jetables par écrit ; Longhorn par sa procédure officielle (réglage `deleting-confirmation-flag`, puis désinstallation du chart, CRD, espace) ; Rook par l'ordre officiel de démontage pratiqué au M16-E14 (`CephCluster` avec `cleanupPolicy`, suppression des objets, de l'opérateur, des CRD, puis sur chaque travailleur `/var/lib/rook` et `sgdisk --zap-all` du disque). Ensuite seulement : les disques `scsi1` (`ssd-lab`) et `scsi2` (`hdd-bulk`) retirés par OpenTofu (état `k8s`, MR sur `plateforme/infra`), les montages et paquets d'essai (`/var/lib/longhorn` dans `fstab`) retirés par Ansible. Vérifier par `qm config` qu'aucun disque de ces stockages ne reste attaché, et que le contenu des stockages Proxmox n'a pas de disque orphelin (`pvesm list ssd-lab | grep 214[4-6]`).
4. **Stockage du cluster** (1 h) : `task appliquer` de `plateforme/k8s` rejoue ceph-csi, classes, classes d'instantanés, contrôleur, quotas et Secrets (`outils/ceph-csi-secrets.sh appliquer` puis `verifier`) ; `outils/ceph-allocations.sh verifier` côté `plateforme/ceph`. Un pipeline vert sur `main`.
5. **MédiAgenda et la base** (1 à 2 h) : deux répliques de l'API sur le Secret `mediagenda-db-app`, `mediagenda-db` à trois instances (`kubectl cnpg status`), Valkey en StatefulSet sur `ceph-rbd` ; bascule maîtrisée répétée (RB-167, partie A) ; archivage continu vérifié (`pg_stat_archiver`), sauvegarde planifiée réussie.
6. **MédiDoc sur le RGW** (1 à 2 h) : `outils/secret-medidoc-s3.sh`, ConfigMap de la CA, [manifestes](fichiers/M16-E46/k8s/espaces/medidoc-dev/30-medidoc.yaml), politique de sortie ; test depuis un pod jetable de `medidoc-dev` (`curl --cacert … https://rgw.par1.medisphere.internal`), puis `/readyz` ; dépôt d'un document, suppression de tous les pods (`kubectl delete pod -l app.kubernetes.io/name=medidoc`), relecture du document : il était dans S3, pas dans le pod. Chemin réseau choisi et décrit dans la matrice des flux (variante « carte VLAN 30 » : aucun flux de bordure à ouvrir ; variante « bordure » : VLAN 40 → 10.10.30.200:443 à ouvrir dans `group_vars/role_routeur/pare_feu.yml`).
7. **Velero** (1 h) : [planification de la recette](fichiers/M16-E46/k8s/composants/velero/planifications-recette.yaml) (base exclue : sa sauvegarde est CloudNativePG), exécution manuelle immédiate (`velero backup create --from-schedule recette-quotidienne --wait`), lecture de `velero backup describe --details` (aucun objet `cnpg.io/cluster`, volume de Valkey déplacé).
8. **Restaurations de la livraison** (2 h) : restauration à un instant donné de `mediagenda-db` dans un nouveau cluster (M16-E19, RB-162), comparaison des données (nombre de lignes, dernier identifiant, somme de contrôle) ; restauration Velero de `medidoc-dev` dans `wb-restauration` (M16-E24, RB-161), relecture d'un document. Chronométrer chacune, remplir le [procès-verbal](fichiers/M16-E46/medisphere/docs/kubernetes/stockage/recette-k8s-stockage-v1.md), puis nettoyer (cluster de restauration, espace `wb-restauration`).
9. **Exploitation et documentation** (3 h) : `ms-verif-k8s-stockage` avec les contrôles ajoutés au palier 4 (pilotes par nœud, quota de `k8s-rbd`, PDB sans propriétaire, instances clôturées, âge du dernier WAL), planifiée et verte ; RB-160 à RB-167 à jour ; architecture, ADR-0160, politique, note `du-pvc-au-bloc.md`, matrice des flux, registre des secrets ; MR, pipelines verts, étiquette `k8s-stockage-v1`.

*Démonstration de Nadia — restauration à l'heure donnée* (à répéter **avant** la revue)

| Étape | Action | Attendu |
|---|---|---|
| 1 | Nadia annonce une heure H passée (après la dernière sauvegarde de base) | — |
| 2 | Vérifier que H est dans la fenêtre : `kubectl cnpg status` (première date de restauration, dernier WAL archivé) | H entre les deux |
| 3 | Manifeste `mediagenda-db-pitr` (copie de M16-E19 : `bootstrap.recovery` depuis l'`ObjectStore` `cnpg-s3`, `recoveryTarget.targetTime: H`, plugin en lecture seule) appliqué | cluster créé, instance en restauration |
| 4 | Suivre `kubectl cnpg status mediagenda-db-pitr` | instance primaire prête |
| 5 | Comparer : rendez-vous créés avant H présents, après H absents | conforme |
| 6 | Temps total noté, comparé au RTO de la politique ; nettoyage du cluster de restauration (sans toucher à `cnpg-k8s-par1` : la restauration ne doit **pas** archiver dans le même chemin) | — |

*Démonstration de Julien — espace supprimé* : `kubectl delete namespace medidoc-dev` ; `velero restore create --from-backup <dernière de recette-quotidienne> --include-namespaces medidoc-dev --wait` ; vérifier le Secret, la ConfigMap, le Deployment, `/readyz`, la relecture du document témoin (empreinte SHA-256 identique). Les documents n'ont jamais quitté le RGW : la restauration ne ramène que les objets Kubernetes, en quelques minutes.

**Explications**

Le mini-projet vérifie surtout la **cohérence** : chaque brique a été construite dans un exercice, la livraison exige qu'elles tiennent ensemble. La sauvegarde de la base n'est pas celle de l'espace (Velero exclut ce que CloudNativePG sauvegarde mieux, et la restauration d'un espace ne doit pas faire démarrer une base vide) ; la donnée de MédiDoc vit dans S3, son espace Kubernetes n'est que de la configuration ; les volumes de Valkey sont un cache qu'on peut perdre mais qu'on sauvegarde quand même (le coût est faible). Retirer Rook et Longhorn **après** une sauvegarde vérifiée et **avant** les restaurations libère la mémoire des travailleurs et prouve que le cluster se suffit de ceph-csi. Le contrôle global revérifie le réseau de stockage des travailleurs (MTU 9000 sans fragmentation) parce que c'est la dépendance la plus fragile des volumes RBD.

**Alternatives**
- Garder Longhorn pour les volumes « jetables et rapides » (données locales) : écarté par l'ADR-0160 (deux systèmes de stockage à exploiter, prérequis iSCSI sur les nœuds) ; à reconsidérer si un besoin de latence locale apparaît.
- Sauvegarder aussi la base par Velero (instantané CSI cohérent au crash) en plus de CloudNativePG : une seconde copie indépendante de barman-cloud, au prix d'un stockage double et d'une procédure de restauration différente ; à écrire dans la politique si on le retient.
- MédiDoc sur `s3-01` (SeaweedFS) plutôt que le RGW : le RGW est retenu pour ses quotas par compte, sa redondance Ceph et le chiffrement des OSD (M08) ; `s3-01` reste la cible des sauvegardes, ce qui sépare donnée et copie.

**Pièges classiques**
- Supprimer `rook-ceph` avant d'avoir vidé les CRD et les finaliseurs : espace bloqué en `Terminating`, CRD orphelines.
- Retirer les disques par `qm set --delete` à la main : l'état OpenTofu les recrée au prochain `apply`.
- Restaurer `mediagenda-recette` par Velero avec le `Cluster` inclus : une base vide démarre, et l'API s'y connecte sans erreur visible.
- Restauration à un instant donné qui archive dans le même chemin que la base de production : mélange de timelines dans `cnpg-k8s-par1`.
- Clés S3 de MédiDoc dans le manifeste ou dans `kubectl create secret --from-literal` (historique du shell).
- Démonstrations jamais répétées : H hors de la fenêtre de restauration, ou sauvegarde Velero qui ne contenait pas `medidoc-dev`.

**En production chez MédiSphère**
Tests de restauration automatisés et mensuels (M29), avec leurs résultats ajoutés au procès-verbal ; réplication des compartiments de sauvegarde vers PAR2 (F5) ; Secrets S3 et cephx gérés par External Secrets depuis Vault (M25) ; supervision des RPO réels par Prometheus (âge du dernier WAL, de la dernière sauvegarde réussie par planification, M21) ; revue annuelle de la politique de sauvegarde avec Sophie.

**Grille de revue (auto-évaluation si tu travailles seul)**

| Relecteur | Critère | Attendu |
|---|---|---|
| Claire | Contrôle global | `lab/bin/check 16 46` entièrement vert, sans contrôle ignoré |
| Claire | Rien de provisoire | Rook, Longhorn, leurs disques et leurs restes sur les nœuds absents ; essais supprimés ou justifiés ; aucune panne ouverte |
| Claire | Points uniques de défaillance | listés dans l'architecture (un hyperviseur, un site, `s3-01` unique) avec le module qui les traitera |
| Karim | Code | `plateforme/k8s` décrit tout (valeurs, classes, quotas, Secrets par script), `task appliquer` idempotent, pipeline vert ; disques retirés par OpenTofu |
| Karim | Ceph | droits de `client.k8s` et de l'identité CephFS égaux à `allocations.yaml`, `k8s-rbd` sous quota avec marge |
| Sophie | Documents | ADR-0160, politique de sauvegarde (RPO, RTO, rétention, chiffrement en transit et au repos), registre des secrets (emplacements seulement), matrice des flux (VLAN 30, S3, RGW) |
| Sophie | Secrets | aucune clé dans un dépôt, un manifeste ou un journal ; Secrets créés depuis Vault ou `~/.config/workbook/` |
| Nadia | Restauration de la base | à l'heure donnée, données vérifiées, temps sous le RTO, procédure RB-162 suivie |
| Nadia | Exploitation | `ms-verif-k8s-stockage` vert et planifiée ; RB-160 à RB-167 à jour ; post-mortem INC-4350 publié |
| Julien | MédiDoc | documents sur le RGW survivant à la suppression des pods, `medidoc-dev` restauré par Velero en quelques minutes |
| Julien | MédiAgenda | API en recette sur `mediagenda-db`, Valkey persistant, bascule sans perte, coupure mesurée |
| Tous | Présentation | 10 minutes : architecture, compromis de l'ADR-0160, ce qui n'est pas redondant, ce que M17, M20, M21, M25, M27 et F5 consommeront |

Une livraison est acceptée quand tous les critères sont remplis ; un critère manquant est noté comme action (responsable, échéance) dans le procès-verbal, jamais passé sous silence.
