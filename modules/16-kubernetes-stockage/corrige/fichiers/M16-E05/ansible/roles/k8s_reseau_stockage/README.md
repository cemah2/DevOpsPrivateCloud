# Rôle `k8s_reseau_stockage`

Carte du réseau de stockage (VLAN 30, STOR-PUB) des **travailleurs** de `k8s-par1`, pour que
ceph-csi joigne `ceph-par1` sans traverser la bordure (M16-E05, PLAT-1705).

| Étape | Ce que fait le rôle | Interruption |
|---|---|---|
| `cloud_init.yml` | `/etc/cloud/cloud.cfg.d/99-medisphere-k8s.cfg` : réseau figé, clés d'hôte SSH conservées | aucune |
| `modules.yml` | `/etc/modules-load.d/ceph-csi.conf` (`rbd`, `ceph`) et chargement immédiat | aucune |
| `reseau.yml` | `/etc/netplan/60-stockage.yaml` (carte reconnue par sa MAC, renommée `ens19`, MTU 9000, sans passerelle), validé par `netplan generate --root-dir` ; **si** la carte existe et n'a pas son adresse : drain, redémarrage, attente `Ready` | seulement quand la carte vient d'apparaître |
| `verifications.yml` | adresse et MTU, une seule route par défaut (pas par `ens19`), `ping -M do -s 8972` vers les trois moniteurs, adresse interne du nœud inchangée ; étiquette `medisphere.fr/stockage-ceph=oui` ; `uncordon` si le rôle a drainé | aucune |

Règle d'adressage partagée avec `plateforme/infra` (`envs/k8s/noeuds.tf`) : suffixe = dernier
octet de l'adresse VLAN 40 ; adresse 10.10.30.<suffixe + 20> ; MAC `bc:24:11:30:00:<suffixe>`.

Exécution (depuis `adm01`, avec ton identité Kubernetes : le rôle lance `kubectl` en local) :

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/k8s-reseau-stockage.yml --check --diff
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/k8s-reseau-stockage.yml -l k8s-w01
```

Le playbook est en `serial: 1`. Il ne pose **pas** la carte : c'est OpenTofu (un travailleur par MR,
nœud drainé). Si l'`apply` a déjà redémarré la VM, la carte est configurée au démarrage et le rôle
ne redémarre pas : remets alors le nœud en service toi-même (`kubectl uncordon`) après les
vérifications.
