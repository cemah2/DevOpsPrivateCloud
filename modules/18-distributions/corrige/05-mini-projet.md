# Module 18 — Corrigé du palier 5 : Mini-projet

> ⚠️ Corrigé — à lire après avoir cherché.

### M18-E25 — Mini-projet : distributions MédiSphère v1

**Solution de référence** (elle suit la proposition d'ADR-0180 du corrigé de E17 : k3s pour Lyon, kubeadm conservé pour la production, k3d pour les recettes, Cluster API non retenu ; templates et `wb-capi` supprimés).

Fichiers : [comparatif](fichiers/M18-E25/medisphere/docs/kubernetes/distributions/comparatif.md), [ordre de démontage](fichiers/M18-E25/medisphere/docs/kubernetes/distributions/demontage.md), [Taskfile de la démonstration](fichiers/M18-E25/distributions/Taskfile.yml), [script de démonstration](fichiers/M18-E25/distributions/demo/demo.sh), [variables du banc de démonstration](fichiers/M18-E25/distributions/demo/demo.env), [`lab.env` (extrait)](fichiers/M18-E25/lab.env.extrait).

*1. Mesures.* Le [modèle de comparatif](fichiers/M18-E25/medisphere/docs/kubernetes/distributions/comparatif.md) donne les lignes et les sources ; les chiffres sont les tiens. Règle d'écriture : un chiffre, une source (`tests/restaurations.md`, `tests/cycle-de-vie-capi.md`, `durcissement.md`, feuille de temps de E18, mesures des paliers 1 et 2). Une case vide dit pourquoi (« non mesuré : Talos détruit avant la mesure de mémoire au repos »).

*2. Décision* : MR de l'ADR-0180 avec le statut « Accepté », la date du comité, les approbateurs ; `lab/lab.env` : `WB_M18_TEMPLATES_CONSERVES=0`, `WB_M18_WBCAPI_CONSERVE=0`.

*3. Démonstration* : `task demo:construire` lance [`demo.sh construire`](fichiers/M18-E25/distributions/demo/demo.sh) :
- `tofu apply` d'`envs/m18` avec `k3s_ha_noeuds = ["k3s-ha01", "k3s-ha02", "k3s-ha03"]` (fichier de variables `demo.auto.tfvars` écrit par le script) ;
- rôle `k3s` (trois serveurs, etcd intégré, instantanés vers `etcd-m18/demo/`) ;
- kubeconfig en 600 ;
- charge témoin (Deployment `pause` + PDB) ;
- instantané à la demande ;
- affichage de la durée totale.

Ordre de grandeur attendu sur le lab : 8 à 12 minutes (clones liés, k3s en une minute par nœud). `task demo:detruire` remet `k3s_ha_noeuds = []`, applique, et supprime le kubeconfig. La démonstration n'a pas besoin de RKE2, Talos ni Cluster API.

*4. Démontage* ([`demontage.md`](fichiers/M18-E25/medisphere/docs/kubernetes/distributions/demontage.md)), l'ordre et sa raison :
1. **Essais et recettes** : `task recette:detruire`, `kind delete clusters --all` et `k3d cluster delete --all` sur `m18-dev01`, espace `wb-essais` de chaque cluster encore vivant.
2. **`capi-essai` par Cluster API** :
   ```
   admin@adm01:~$ export KUBECONFIG=~/.config/workbook/m18/k3s01.kubeconfig
   admin@adm01:~$ kubectl delete cluster capi-essai -n capi-essai --wait=false
   admin@adm01:~$ kubectl get cluster,machines,proxmoxmachines -n capi-essai -w     # jusqu'à « No resources found »
   root@pve01:~# qm list | awk '$1 >= 5180 && $1 <= 5189'                          # vide
   ```
   Puis `kubectl delete -f capi/capi-essai/` pour les objets sans propriétaire (gabarits, `ClusterResourceSet`, `MachineHealthCheck`) et l'espace `capi-essai`. Si une suppression reste bloquée sur un finaliseur, RB-180 (cause d'abord), jamais un retrait de finaliseur « pour aller plus vite » sans avoir vérifié que la VM n'existe plus.
3. **Archive finale de `k3s01`** si l'ADR la garde (30 jours dans `gestion/`), puis plus rien n'est fait sur `k3s01`.
4. **VMs** : groupes et listes de `envs/m18` vidés (`k3s_ha_noeuds = []`, plus de `rke2`, `talos`, `k3s01`, `m18-dev01`), `tofu plan` relu (que des destructions), `tofu apply`. DNS : les baux DHCP de `vsandbox` expirent seuls, mais les enregistrements DDNS restent jusqu'à leur suppression par Kea à l'expiration ; les enregistrements A de Talos (créés par OpenTofu) partent avec l'état. NetBox : objets des VMs retirés par le même code que celui qui les a créés (M06).
5. **Templates 9060, 9061** : `qm destroy` après vérification qu'aucun clone ne les référence (clones complets : aucun), ou par le code d'image-builder s'il gère la suppression.
6. **`wb-capi`** : ACL, jeton, utilisateur, rôle `WBCapi` (`pveum acl delete`, `pveum user token remove`, `pveum user delete`, `pveum role delete`), par le code de M18-E08 si c'est lui qui les a créés ; `~/.config/workbook/pve-capi.env` effacé ; registre des secrets mis à jour.
7. **`etcd-m18`** : selon l'ADR. Proposition : supprimé (les instantanés de bancs détruits ne servent plus) par l'identité d'administration de `s3-01` (l'identité `etcd-m18` ne peut pas supprimer), puis identité retirée du rôle `seaweedfs`.
8. **Flux** : règles `ref: M18-E08` (et leurs définitions `M18_GESTION`, `CAPI_ESSAI_API`), `ref: M18-E14` et `ref: M18-E16` retirées de `group_vars/role_routeur/pare_feu.yml`, rôle `pare_feu` rejoué sur les deux passerelles (une à la fois, la passive d'abord, comme au M07) ; sur `pve01`, règle 8006 `+capi` puis IPSet `capi` supprimés (`pvesh delete /cluster/firewall/rules/<POS>` après lecture de la position, `pvesh delete /cluster/firewall/ipset/capi/<CIDR>` pour chaque entrée, puis `pvesh delete /cluster/firewall/ipset/capi`) ; matrice des flux mise à jour. Même si l'ADR garde `wb-capi`, ces règles partent : les clusters de gestion qu'elles visaient n'existent plus.
9. **Fichiers locaux** : kubeconfig des clusters détruits et `talosconfig*` effacés ; `talos-secrets.yaml` effacé de `~/.config/workbook/m18/` (la copie chiffrée reste dans le dépôt, Vault `lab`, si l'ADR garde Talos en option).

*5. `k8s-par1`* : redémarrage selon `docs/kubernetes/cluster.md` (M14-E05 : nœuds de contrôle d'abord, au moins deux pour le quorum, puis travailleurs). Ton identité personnelle (certificat de 7 jours) a expiré pendant le module : renouvelle-la d'abord avec `outils/kubeconfig-personnel.sh <MOI>` de `plateforme/k8s` (M14-E06, il passe par `k8s-cp01` en SSH). Puis :
```
admin@k8s-cp01:~$ sudo kubeadm certs check-expiration    # un cluster arrêté longtemps peut avoir des certificats proches de l'échéance
admin@adm01:~/DevOpsPrivateCloud$ lab/bin/check 14 46
```
Si `check 14 46` signale des certificats du kubelet à renouveler ou des pods `Pending`, c'est l'effet de l'arrêt (CSR en attente, PVC à rattacher) : RB-143 et RB-145.

*6. Livraison* : MR fusionnées, pipelines verts, étiquette `distributions-v1`.

**Grille de revue** (sur 20)

| Critère | Points |
|---|---|
| Comparatif complet, chaque chiffre sourcé | 4 |
| ADR accepté, cohérent avec les réglages et le démontage | 3 |
| Démonstration reconstruite en revue, durée conforme | 4 |
| Démontage dans le bon ordre, prouvé, sans orphelin (VMs, adresses, finaliseurs, droits, flux) | 5 |
| `k8s-par1` vert, registre des secrets à jour, étiquette posée | 2 |
| Réponses de la revue (procédure de restauration au hasard, registre des secrets) | 2 |

**Pièges classiques**
- Détruire `k3s01` (ou faire `tofu destroy` de tout `envs/m18`) avant d'avoir supprimé `capi-essai` : VMs 5180-5189 orphelines, à supprimer à la main en vérifiant chaque VMID.
- Supprimer le jeton `wb-capi` pendant que CAPMOX supprime encore des VMs : objets bloqués sur leurs finaliseurs.
- Oublier les règles provisoires de la bordure : un flux `vsandbox` → `s3-01` ouvert pour un module terminé, c'est une porte que personne ne surveille.
- Laisser les kubeconfig d'administration de clusters détruits dans `~/.config/workbook/m18/` : sans danger aujourd'hui, mais un futur cluster qui réutiliserait les mêmes adresses ne serait pas le même.
- Démonstration « préparée » : un cluster déjà construit qu'on montre en revue ne prouve pas la reconstruction.

**En production chez MédiSphère**
La reconstruction de l'option retenue devient un test planifié (pipeline nocturne sur un banc jetable, M19), le démontage d'un environnement est une procédure du catalogue de la plateforme, et le registre des secrets est contrôlé par un outil (M25) plutôt que relu.
