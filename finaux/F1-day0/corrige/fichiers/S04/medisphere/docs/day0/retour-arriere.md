# Plan de retour arrière de la fenêtre CHG-3107 (F1-S04)

> Version de référence (corrigé F1-S04). Jouable seule par l'astreinte (Nadia), sans connaissance
> préalable du final. Durées à remplacer par TES mesures.

## 1. Quand le déclencher

| Critère | Seuil |
|---|---|
| Heure | **H+5 h** après le début de la destruction : si l'étape « couche de base » (S08) n'est pas verte, on revient. |
| Échec bloquant | kubeadm ne forme pas un plan de contrôle à trois membres en 2 h ; ou ESO ne lit plus le coffre après 1 h de diagnostic ; ou les données (S11) ne reviennent pas au compte de `reference-avant.md`. |
| Décision | Claire (ou, la nuit, l'astreinte après appel à Karim). Notée dans `journal/` avec l'heure. |

Au-delà de H+5 h, le retour arrière prend plus longtemps que la fin de la reconstruction : on termine en avant.

## 2. Ce qu'on restaure, et ce qu'on perd

- Les **six VMs** 2141-2146 depuis PBS (`pbs01`, `ds-lab`, espace `par1/k8s`), sauvegardes de la veille (CHG-3104).
- Les **volumes de `ceph-par1`** n'ont pas été effacés (règle 4 de l'introduction) : les PVC de l'ancien cluster retrouvent leurs images RBD.
- **Perte** (RPO) : ce qui a été écrit dans le cluster entre la sauvegarde PBS et la destruction. La production est **gelée** pendant la fenêtre (CHG-3107) : RPO attendu = 0 côté données métier ; etcd revient à l'état de la sauvegarde PBS (objets créés pendant la fenêtre perdus, ce sont ceux de la reconstruction).

## 3. Procédure

1. **Arrêter** ce qui a été reconstruit : par OpenTofu, `envs/k8s` (les nouvelles VMs 2141-2146 sont détruites ; noter que leurs objets NetBox et DNS sont recréés par l'étape 5).
2. Vérifier que `ceph-par1` est `HEALTH_OK` et que les images RBD de l'ancien cluster sont toujours là (`rbd ls k8s-rbd | wc -l` = valeur notée dans `reference-avant.md`).
3. **Restaurer** depuis l'interface de `pve01` ou en root :
   `qmrestore <STOCKAGE-PBS-K8S>:backup/vm/2141/<HORODATAGE> 2141 --storage local-nvme` (`<STOCKAGE-PBS-K8S>` : le stockage PBS de `pve01` qui pointe sur l'espace `par1/k8s` ; `pvesm list <STOCKAGE-PBS-K8S> --vmid 2141` donne le volume), idem 2142 à 2146, **sans** `--unique` (on veut les mêmes MAC).
4. **Démarrer** dans l'ordre d'arrêt inverse documenté par le M14 : nœuds de contrôle 2141, 2142, 2143 (attendre le quorum etcd et la VIP 10.10.40.200), puis travailleurs 2144, 2145, 2146.
5. **Réaligner le code** : état `envs/k8s` (import des VMs restaurées, ou `tofu apply` du code d'avant la fenêtre : étiquette `avant-chg3107` de `plateforme/infra`), NetBox, DNS. La dérive est attendue : elle se constate (S02) et se résorbe avant de clore.
6. **Vérifier** : `kubectl get nodes` (six `Ready`) ; Argo CD `Synced/Healthy` ; `lab/bin/check 29 25` ; comptes de `reference-avant.md` ; MédiAgenda prod répond.
7. **Communiquer** : Nadia au support (fin de fenêtre, retour à l'état de la veille), Julien.

Durée mesurée de la restauration d'une VM (S04) : <N> min ; estimation totale : <N> min pour six VMs (deux restaurations en parallèle au plus : disque et `wg0` vers `pbs01`).

## 4. Ce que ce plan ne couvre pas

- Une perte de `ceph-par1` pendant la fenêtre : restauration des données depuis CNPG et Velero (S11), pas depuis PBS.
- Une perte de `pbs01` : F5.
