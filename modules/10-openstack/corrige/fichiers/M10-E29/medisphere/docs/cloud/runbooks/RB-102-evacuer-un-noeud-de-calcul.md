# RB-102 — Évacuer un nœud de calcul (maintenance, panne, réintégration)

| | |
|---|---|
| Portée | `oscmp01`, `oscmp02` (groupe `compute` de Kolla). Pas le contrôleur. |
| Durée | Maintenance planifiée : 30 à 60 min hors intervention matérielle |
| Qui | Équipe Plateforme, astreinte |
| Outils | `outils/vider-noeud-calcul.sh` et `outils/mesure-continuite.sh` de `plateforme/openstack` ; CLI `openstack` avec le greffon `osc-placement` |
| Historique | §6 |

> ⚠️ Un seul autre calcul : vérifier **avant** qu'il peut tout absorber (§1). Ne jamais retirer d'OpenStack un nœud qui porte encore une instance.

## 1. Avant : capacité

```
admin@adm01:~/src/openstack$ outils/vider-noeud-calcul.sh -n oscmp02 "PLAT-XXXX maintenance"
```

Lire, pour l'autre calcul, VCPU et MEMORY_MB utilisés / allouables (ratios compris). Pour la mémoire **réelle** : `free -m` sur l'autre calcul (VM imbriquée de 8 Go, ratio de mémoire 1.0) ; si l'allocation passe au-delà de ~85 % de l'allouable, prévenir les équipes et reporter les instances non critiques (arrêt planifié) plutôt que de saturer.

Instantané des trois nœuds : `ms-snapshot --prefix avant-maint 2101 2102 2103`.

## 2. Maintenance planifiée

### 2.1 Vider

```
admin@adm01:~/src/openstack$ outils/mesure-continuite.sh lancer -d /tmp/maint -f <IP-FLOTTANTE-D'UNE-INSTANCE-DU-NŒUD>
admin@adm01:~/src/openstack$ outils/vider-noeud-calcul.sh oscmp02 "PLAT-XXXX remplacement mémoire"
admin@adm01:~$ openstack server migration list --host oscmp02        # suivi ; journaux : /var/log/kolla/nova/nova-compute.log des deux calculs
```

Échec de migration : lire le journal de `nova-compute` de la **source** (CPU des invités incompatible, résolution du nom de la cible, flux libvirt entre calculs bloqué).

### 2.2 Sortir d'OpenStack

```
admin@adm01:~/src/openstack$ uv run kolla-ansible stop -i inventaire/multinode --configdir etc/kolla \
                               --yes-i-really-really-mean-it --limit oscmp02
```

⚠️ Relire `--limit oscmp02` avant de valider : sans limite, cette commande arrête **tout** le cloud.

MR sur `plateforme/openstack` : `oscmp02` retiré du groupe `[compute]` (commentaire avec le ticket). Puis :

```
admin@adm01:~$ openstack network agent list --host oscmp02 -f value -c ID | xargs -r -n1 openstack network agent delete
admin@adm01:~$ openstack compute service list --os-compute-api-version 2.53 --host oscmp02 -f value -c ID \
                 | xargs -r -n1 openstack compute service delete --os-compute-api-version 2.53
admin@adm01:~$ openstack resource provider list --name oscmp02           # vide attendu
admin@adm01:~$ openstack hypervisor list                                 # oscmp02 absent
root@osctl01:~# docker exec ovn_sb_db ovn-sbctl show | grep -A2 oscmp02   # plus de châssis (sinon : ovn-sbctl chassis-del <nom>)
```

Si le fournisseur de ressources `oscmp02` subsiste : `openstack resource provider show <uuid> --allocations` montre qui le retient (allocation d'une instance migrée mal nettoyée : `openstack resource provider allocation show <instance>` puis correction, ou `nova-manage placement heal_allocations` dans `nova_api`) ; ne supprimer le fournisseur qu'une fois sans allocations.

### 2.3 Intervention

Arrêt de la VM (`qm shutdown 2103` sur `pve01`), intervention, redémarrage. Dans le lab, la « maintenance » est une modification sans effet par OpenTofu (description de la VM) : `plan` doit n'annoncer qu'elle.

### 2.4 Réintégrer

MR : `oscmp02` de retour dans `[compute]`. Puis, limités au nœud (la documentation l'autorise pour un **calcul**) :

```
admin@adm01:~/src/openstack$ uv run kolla-ansible bootstrap-servers -i inventaire/multinode --configdir etc/kolla --limit oscmp02
admin@adm01:~/src/openstack$ uv run kolla-ansible pull -i inventaire/multinode --configdir etc/kolla --limit oscmp02
admin@adm01:~/src/openstack$ uv run kolla-ansible deploy -i inventaire/multinode --configdir etc/kolla --limit oscmp02
```

`bootstrap-servers` sur un système existant peut redémarrer Docker et modifier `/etc/hosts` des nœuds visés : jamais sans `--limit` sur une plateforme en service (voir *Bootstrap servers* dans la documentation de Kolla).

Vérifications : `openstack compute service list --service nova-compute` (un seul `oscmp02`, `up`, **désactivé** si le service avait été désactivé avant suppression : sinon activé) ; `openstack resource provider list --name oscmp02` (un seul) et son inventaire ; `openstack network agent list --host oscmp02` (OVN Controller et métadonnées vivants). Kolla enregistre le calcul dans la cellule (`discover_hosts`) pendant `deploy`.

```
admin@adm01:~$ openstack compute service set --enable oscmp02 nova-compute
admin@adm01:~$ openstack server migrate --live-migration --host oscmp02 --wait <INSTANCE>    # rééquilibrage
admin@adm01:~/src/openstack$ outils/mesure-continuite.sh arreter -d /tmp/maint && outils/mesure-continuite.sh analyser -d /tmp/maint
```

## 3. Panne d'un calcul (non planifiée)

1. Confirmer la panne : `openstack compute service list` (`down` depuis plus de `service_down_time`), console Proxmox (`qm status 2103`, `qm terminal 2103`). Un calcul « down » parce que RabbitMQ ou l'horloge l'isole n'est **pas** mort : ne pas évacuer (les instances tournent encore, une évacuation créerait des doublons sur le même disque Ceph).
2. S'assurer que le nœud est **réellement arrêté** (clôture : `qm stop 2103`) avant toute évacuation.
3. Marquer le service : `openstack compute service set --down oscmp02 nova-compute` (*force down*, micro-version 2.11+), puis désactiver avec raison.
4. Évacuer : `openstack server evacuate <INSTANCE>` (récente CLI) pour chaque instance ; avec Ceph, le disque est partagé : l'instance redémarre sur l'autre calcul avec son disque (pas de reconstruction depuis l'image).
5. Au retour du nœud : Nova détecte les instances évacuées et nettoie leurs domaines locaux au démarrage de `nova-compute` ; lever le *force down* (`--up`), réactiver.

## 4. Contrôles finaux

- `ms-verif-openstack` : tout OK.
- Un seul `nova-compute` par hôte, un seul fournisseur de ressources par hôte, un agent OVN Controller par hôte.
- Instances réparties, aucune en `ERROR` ou `MIGRATING`.

## 5. Ce qui peut mal tourner

| Symptôme | Cause probable | Action |
|---|---|---|
| Migration refusée « No valid host » | capacité de l'autre calcul, ou service source seul activé | §1 ; arrêter des instances non critiques |
| Migration bloquée en `migrating` | flux libvirt/QEMU entre calculs, mémoire trop active (page sale) | journaux des deux `nova-compute` ; `openstack server migration abort` |
| `oscmp02` réintégré mais aucune instance n'y va | service resté désactivé, ou deux fournisseurs `oscmp02` | `compute service list --long` ; `resource provider list` |
| Agent OVN de `oscmp02` « mort » en double | ancien agent non supprimé | `network agent delete` de l'ancien |

## 6. Historique des exécutions

| Date | Ticket | Nœud | Instances migrées | Coupure mesurée (nord-sud) | Durée totale | Remarques |
|---|---|---|---|---|---|---|
| 2026-10-23 | PLAT-1155 | `oscmp02` | 2 (`evac-essai01`, `evac-essai02`) | 0,4 s (deux paquets perdus) | 52 min | fournisseur Placement supprimé avec le service ; châssis OVN absent sans `chassis-del` |
