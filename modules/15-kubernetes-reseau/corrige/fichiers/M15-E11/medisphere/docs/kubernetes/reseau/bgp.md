# BGP entre `k8s-par1` et la bordure

| | |
|---|---|
| **Portée** | Annonce des adresses de service (LB IPAM, 10.10.41.0/24) de `k8s-par1` à `gw01`/`gw02` |
| **Propriétaire** | Équipe Plateforme |
| **Références** | PLAT-1611 (M15-E11), RB-073 (session BGP de la bordure), RB-152 (BGP du cluster) |

## Qui parle à qui

```
 k8s-w01 10.10.40.61 ─┐                         ┌─ gw01 10.10.40.2  (AS 65000, groupe K8S, écoute passive)
 k8s-w02 10.10.40.62 ─┼── eBGP AS 65040 ───────┤
 k8s-w03 10.10.40.63 ─┘   (l'agent Cilium      └─ gw02 10.10.40.3  (idem)
                           initie, TCP 179)
 k8s-cp01..03 : aucune session (pas d'étiquette bgp=par1)
```

- Six sessions (trois travailleurs × deux passerelles), adresses propres des passerelles, jamais la VIP .1.
- Annonces : les adresses `LoadBalancer` de tous les Services, en /32, par **chaque** travailleur (`externalTrafficPolicy: Cluster`) ; la bordure installe jusqu'à 8 chemins égaux (ECMP).
- Politiques de la bordure : `RM-K8S-IN` n'accepte que 10.10.41.0/24 jusqu'aux /32 ; `RM-K8S-OUT` refuse tout (le cluster ne reçoit aucune route : sa route par défaut est la VIP .1) ; au plus 200 préfixes par nœud (la session du nœud tombe au-delà).
- Temporisateurs : 3 s / 9 s (proposés par Cilium, retenus par négociation) ; pas de *graceful restart* (voir M15-E25).
- Pas de TCP-MD5 : le VLAN 40 ne porte que les nœuds et les passerelles, la bordure n'accepte que ce préfixe et le pare-feu n'ouvre TCP 179 qu'au VLAN 40. Réévalué dans l'ADR-0150.

## Où est la configuration

| Côté | Fichier | Projet |
|---|---|---|
| Bordure | `inventories/lab/group_vars/role_routeur/frr.yml` (groupe `K8S`), `pare_feu.yml` (TCP 179) | `plateforme/ansible` |
| Cluster | `composants/cilium/values.yaml` (`bgpControlPlane.enabled`), `composants/cilium/bgp/`, `cluster/noeuds.yaml` (`bgp=par1`) | `plateforme/k8s` |
| Supervision | `etc/ms-verif-reseau.conf` (`MS_BGP_TOUS`) | `plateforme/outils` |

## Vérifier

```
admin@adm01:~$ cilium bgp peers                               # 6 lignes « established »
admin@adm01:~$ kubectl get ciliumbgpnodeconfigs -o wide
admin@gw01:~$ sudo vtysh -c 'show bgp summary'               # 3 voisins *10.10.40.6x
admin@gw01:~$ sudo vtysh -c 'show ip route 10.10.41.10'      # 3 prochains sauts
```

## Retirer un nœud de l'annonce (maintenance)

`kubectl drain` du nœud, puis retrait de `bgp: par1` dans `cluster/noeuds.yaml` (MR) et `task etiquettes` : la session du nœud se ferme, la bordure retire ses chemins (quelques secondes). Remettre l'étiquette après la maintenance. Procédure détaillée : documentation Cilium *BGP Control Plane Operation → Shutting Down a Node*.
