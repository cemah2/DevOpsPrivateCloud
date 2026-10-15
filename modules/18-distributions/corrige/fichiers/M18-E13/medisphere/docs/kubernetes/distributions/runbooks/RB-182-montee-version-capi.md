# RB-182 — Monter de version un cluster Cluster API (CAPMOX)

| | |
|---|---|
| Portée | Clusters de charge de travail créés par Cluster API 1.12 + CAPMOX 0.9 depuis le cluster de gestion `k3s01` (aujourd'hui : `capi-essai`) |
| Déclencheur | Nouveau correctif Kubernetes (ADR-0141), image de nœud reconstruite (sécurité de l'OS), changement de gabarit |
| Durée | 20 à 40 min pour 1 nœud de contrôle + 2 travailleurs (mesuré en M18-E13), plus la construction de l'image (≈ 45 min) |
| Rédigé par | Équipe Plateforme — M18-E13 |

## 1. Principe

Cluster API ne met jamais un nœud à jour en place : il **remplace** les machines dont la spécification a changé (version, gabarit d'infrastructure, configuration d'amorçage). Une montée de version, c'est donc : une image de nœud neuve, de nouveaux gabarits sous de nouveaux noms, puis le changement de la version et des références, plan de contrôle d'abord, travailleurs ensuite.

## 2. Préalables (tous obligatoires)

1. **Compatibilité** : la version visée est acceptée par Cluster API 1.12 (≤ 1.36) et par CAPMOX 0.9 ; Cilium 1.20 la supporte ; le décalage avec le plan de contrôle respecte la politique de Kubernetes (une mineure à la fois).
2. **Image** : template construit par image-builder (`tpl-capi-ubuntu2404-k1NN-R`, VMID dans 9060-9069), avec la bonne version de `kubeadm`/`kubelet` (`qm config <VMID>` : description ; ou un clone d'essai), étiqueté `capi` + `k8s-vX.Y.Z`. L'ancien template est **conservé** jusqu'à la fin du §6.
3. **Capacité** : mémoire libre sur `pve01` ≥ taille d'une machine + 2 Go ; au moins **deux** VMID libres dans `vmIDRange` (5180-5189) et deux adresses libres dans le pool `capi-essai-v4-icip` (`kubectl get inclusterippool -n capi-essai -o wide`) : un remplacement crée avant de supprimer.
4. **Santé** : `clusterctl describe cluster <CLUSTER> -n <ESPACE>` entièrement vert ; aucune machine en cours de suppression ; `MachineHealthCheck` au vert (sinon une réparation peut se mêler au remplacement).
5. **Sauvegarde** : instantané etcd du cluster de charge de travail (ou de ses objets par Velero) et archive du cluster de gestion (RB-181 §5) de moins de 24 h.
6. **Fenêtre** annoncée ; charge témoin ou sonde de l'application en place.

## 3. Préparer (MR 1 et MR 2, relues avant la fenêtre)

- Nouveaux `ProxmoxMachineTemplate` (copie des actuels, `templateID` et nom changés) : `capi/<cluster>/gabarits-<suffixe>.yaml`.
- MR 1 : `KubeadmControlPlane` → `spec.version`, `spec.machineTemplate.spec.infrastructureRef.name`, stratégie `rollout.strategy.rollingUpdate.maxSurge: 1`.
- MR 2 : `MachineDeployment` → `spec.template.spec.version`, `spec.template.spec.infrastructureRef.name`, `maxSurge: 1`, `maxUnavailable: 0`.
- Contrôle : `kubectl apply --dry-run=server -f …` pour chaque fichier.

## 4. Exécuter

1. Appliquer les gabarits, puis la MR 1 :
   ```
   admin@adm01:~$ export KUBECONFIG=~/.config/workbook/m18/k3s01.kubeconfig
   admin@adm01:~/src/distributions$ kubectl apply -f capi/<cluster>/gabarits-<suffixe>.yaml
   admin@adm01:~/src/distributions$ kubectl apply -f capi/<cluster>/plan-controle.yaml
   ```
2. Suivre jusqu'à la fin du plan de contrôle :
   ```
   admin@adm01:~$ kubectl get kcp -n <ESPACE> -w            # UPTODATE = REPLICAS, VERSION = cible
   admin@adm01:~$ clusterctl describe cluster <CLUSTER> -n <ESPACE>
   admin@adm01:~$ kubectl get machines -n <ESPACE> -o wide -w
   ```
   Côté cluster de charge de travail : `kubectl get nodes -o wide` (kubelet à la cible), membres etcd (`etcdctl member list` dans le pod etcd), pods du `kube-system` prêts.
3. Appliquer la MR 2, suivre `kubectl get md -n <ESPACE> -w` jusqu'à `UPTODATE = REPLICAS`, nœuds `Ready`.

## 5. Critères d'arrêt (on n'appuie pas sur la suite)

- Une machine reste en `Provisioning` plus de 15 min → RB-180.
- Le nouveau nœud de contrôle ne rejoint pas etcd, ou etcd perd un membre : **ne rien supprimer à la main**. Mettre le KCP en pause (`kubectl annotate kcp <NOM> -n <ESPACE> cluster.x-k8s.io/paused=""`), diagnostiquer, puis retirer l'annotation.
- La charge témoin descend sous son PDB : vérifier les PDB et les sondes avant de continuer.

## 6. Après

- Laisser tourner 24 h ; puis retirer l'étiquette `current` de l'ancien template (déjà fait à la construction) et, quand plus aucune machine ni gabarit ne le référence (`kubectl get proxmoxmachines -A -o jsonpath='{..templateID}'`), le supprimer ou le garder selon l'ADR-0180.
- Supprimer les anciens `ProxmoxMachineTemplate` une fois qu'aucun `MachineSet` ni KCP ne les référence.
- Mettre à jour le tableau des versions et l'inventaire.

## 7. Retour arrière

Remettre l'ancienne version **et** les anciens gabarits (qui pointent sur l'ancien template) dans le KCP et le MD : nouveau remplacement, vers l'ancienne image. Une **descente** de mineure n'est pas permise par kubeadm : le retour arrière ne vaut qu'entre correctifs de la même mineure, ou avant que le plan de contrôle n'ait fini sa montée. Au-delà, c'est une restauration (RB-181).
