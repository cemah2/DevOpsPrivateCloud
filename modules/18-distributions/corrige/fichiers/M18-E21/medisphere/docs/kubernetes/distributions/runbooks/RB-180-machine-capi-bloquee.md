# RB-180 — Une machine Cluster API reste bloquée

| | |
|---|---|
| Portée | Clusters créés par Cluster API 1.12 + CAPMOX 0.9 depuis le cluster de gestion `k3s01` |
| Symptôme | `Machine` en `Pending`, `Provisioning` ou `Provisioned` au-delà de 15 min ; `MachineDeployment` ou KCP avec des réplicas non prêts |
| Rédigé par | Équipe Plateforme — M18-E21 (INC-4521) |

## 1. Descendre la chaîne (lecture seule)

```
export KUBECONFIG=~/.config/workbook/m18/k3s01.kubeconfig
clusterctl describe cluster <CLUSTER> -n <ESPACE> --show-conditions all
kubectl get machines,proxmoxmachines -n <ESPACE> -o wide
kubectl get proxmoxmachine <PM> -n <ESPACE> -o yaml       # spec.virtualMachineID, status.conditions
kubectl get events -n <ESPACE> --sort-by=.lastTimestamp | tail -20
kubectl get ipaddressclaims,ipaddresses,inclusterippools -n <ESPACE>
kubectl logs -n capmox-system deploy/capmox-controller-manager --since=30m | grep <PM>
```

## 2. Tableau de décision

| Phase / condition (raison) | VM dans Proxmox ? | Étage | Preuve | Correctif |
|---|---|---|---|---|
| `Provisioning`, `VirtualMachineProvisioned` `CloningFailed`, erreurs 401 | non | identité Proxmox | `pveum user token list wb-capi@pve` (colonne `expire`), journal `pveproxy` | expiration remise (`--expire 0` ou date écrite dans le code) ; ne pas recréer le jeton |
| idem, erreurs 403 `Permission check failed` | non | droits, template | `pveum user permissions 'wb-capi@pve!capi' --path /vms/<TPL>` ; membres du pool `lab` | template remis dans le pool ; jamais d'ACL sur `/` ni de rôle élargi |
| idem, « template not found » / « multiple templates » | non | sélection du template | `qm config <TPL>` (étiquettes), `templateID` du gabarit | étiquettes ou `templateID` corrigés dans le code |
| `WaitingForStaticIPAllocation` | oui, arrêtée | adresses | `kubectl get inclusterippool -o jsonpath='{.status.ipAddresses}'`, réservations sans propriétaire | réservations étrangères retirées ; plage dédiée pour les autres besoins |
| VMID introuvable, clone refusé faute de VMID | non | plage `vmIDRange` pleine | `qm list` sur 5180-5189 | VMs orphelines nettoyées (après preuve), plage élargie dans le code |
| `WaitingForVMPowerUp`, `PoweringOnFailed`, `TaskFailed` | oui | Proxmox (mémoire, stockage) | tâches de `pve01`, `free -g` | libérer de la mémoire, réessayer |
| `WaitingForCloudInit` longtemps, puis `Provisioned` sans `Node` | oui, démarrée | amorçage kubeadm | console de la VM, `/var/log/cloud-init-output.log` | selon l'erreur kubeadm |
| `Provisioned`, `kubeadm join` en échec vers la VIP | oui | point d'accès de l'API | `arping -I <if> 10.10.40.210` (deux MAC = VIP occupée), `curl -k https://10.10.40.210:6443/livez`, flux de la bordure | libérer la VIP (hôte fautif), rouvrir le flux |

## 3. Pause

Mettre le cluster en pause (`kubectl patch cluster <CLUSTER> -n <ESPACE> --type merge -p '{"spec":{"paused":true}}'`) quand :
- on intervient à la main dans Proxmox sur ses VMs ;
- on soupçonne que les contrôleurs aggravent la situation (remplacements en boucle) ;
- on met le cluster au repos.

Avant de lever la pause, vérifier que tous les nœuds sont `Ready`, sinon le `MachineHealthCheck` les remplace.

## 4. Ce qu'on ne fait jamais

- Supprimer la `Machine` bloquée « pour qu'elle reparte » (sa remplaçante se bloque pareil ; risque de VM orpheline et d'adresse réservée).
- Supprimer une VM 5180-5189 dans Proxmox à la main.
- Élargir le rôle `WBCapi` ou poser une ACL sur `/`.
- Recréer le jeton Proxmox sans mettre à jour le Secret `capi-essai-proxmox` et le registre des secrets.
- Créer des `IPAddressClaim` à la main dans un pool de cluster.
