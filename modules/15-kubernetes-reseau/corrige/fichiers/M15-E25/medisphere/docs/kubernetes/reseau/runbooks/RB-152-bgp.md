# RB-152 — BGP et entrée du cluster : nœud, session ou passerelle perdus

| | |
|---|---|
| Portée | Annonces des adresses de service (10.10.41.0/24) de `k8s-par1` vers `gw01`/`gw02` |
| Déclencheurs | alerte `ms-verif-k8s-reseau` (session BGP, route absente de la bordure), sonde HTTP en échec, ticket « l'application ne répond plus » alors que les pods sont prêts |
| Exercices | M15-E11 (mise en place), M15-E25 (mesures), M15-E26 (sonde), M15-E27 (mise à jour) |
| Propriétaire | Équipe Plateforme — dernière revue <DATE> |

## Rappel du fonctionnement

- Chaque travailleur sélectionné par `CiliumBGPClusterConfig` `bgp-par1` ouvre une session eBGP (AS 65040 → 65000) avec **chaque** passerelle (10.10.40.2 et .3) et annonce en /32 les adresses `LoadBalancer` choisies par `CiliumBGPAdvertisement`.
- La bordure installe un chemin par nœud annonceur (`maximum-paths 8`) et répartit les flux par hachage. Le nœud qui reçoit remet le paquet à son Envoy (Gateway) ou au pod du Service (eBPF).
- `CiliumBGPPeerConfig` `bordure` : hold 9 s, keepalive 3 s, redémarrage en douceur 30 s.
- Route de rejet `10.10.41.0/24 blackhole 250` sur les deux passerelles : sans annonce, les paquets sont jetés à la bordure, jamais envoyés vers le WAN.

## Temps mesurés (M15-E25, sonde 200 ms depuis `adm01`)

Remplace par tes mesures ; valeurs indicatives d'un lab à trois travailleurs.

| Scénario | Défauts du plan de contrôle (hold 90 s, sans GR) — calculé | E11 (hold 9 s, sans GR) | Retenu (hold 9 s, GR 30 s) | Ce qui le détermine |
|---|---|---|---|---|
| Travailleur éteint brutalement | ~1/3 des requêtes perdues pendant ≈ 90 s | ~1/3 perdues pendant ≈ 9 s | ~1/3 perdues pendant 9 à 30 s (selon le traitement GR d'un *hold time* expiré par FRR : à mesurer) | hold time ; GR côté bordure |
| Redémarrage d'un agent Cilium (mise à jour) | idem E11 | quelques nouvelles connexions perdues pendant ≈ 1-3 s (retrait puis retour du chemin) | aucune interruption mesurée | GR ; plan de données eBPF qui continue |
| FRR arrêté sur la passerelle de **secours** | aucune | aucune | aucune | seule la table du maître sert |
| Bascule de la bordure gw01 → gw02 (RB-071) | ≈ 1-3 s (VRRP) | identique | identique | VRRP ; les deux passerelles ont déjà les routes |
| FRR arrêté sur la passerelle **maître** | **toutes** les adresses de service injoignables jusqu'au retour de FRR ou à la bascule manuelle | identique | identique | pas de surveillance de FRR par keepalived (décision ci-dessous) |

## Constat (dans l'ordre)

```
admin@adm01:~$ ms-verif-k8s-reseau                                        # quel contrôle est rouge ?
admin@adm01:~$ kubectl get ciliumbgpnodeconfigs -o custom-columns=NOEUD:.metadata.name,PAIRS:.status.bgpInstances[*].peers[*].peeringState
admin@adm01:~$ cilium bgp peers                                           # vue des agents (état, temporisateurs appliqués)
admin@adm01:~$ cilium bgp routes advertised ipv4 unicast                   # qui annonce quoi
admin@gw01:~$ sudo vtysh -c 'show bgp summary'                            # sur le MAÎTRE d'abord (ip -br a : qui porte .1 ?)
admin@gw01:~$ sudo vtysh -c 'show ip bgp 10.10.41.10/32'                   # chemins reçus, multipath
admin@gw01:~$ ip route show 10.10.41.10                                    # chemins installés dans le noyau
admin@gw01:~$ ip route get 10.10.41.10                                     # « blackhole » = plus aucune annonce
```

Lecture :

| Observation | Cause probable | Action |
|---|---|---|
| Sessions d'**un** nœud tombées, les autres `Established` | nœud éteint, agent Cilium en erreur, label BGP retiré | `kubectl get node`, `kubectl -n kube-system get pod -o wide -l k8s-app=cilium`, labels du nœud. Le service est rendu par les autres : pas d'urgence de nuit |
| Toutes les sessions tombées vers **une** passerelle | FRR arrêté ou en erreur sur cette passerelle, pare-feu (TCP 179) | `systemctl status frr`, `journalctl -u frr` ; si c'est le maître : bascule de la bordure (RB-071) **immédiate** |
| Toutes les sessions tombées vers les **deux** | réseau du VLAN 40, configuration Cilium (`bgpControlPlane`), opérateur | `cilium status`, `kubectl -n kube-system logs ds/cilium | grep -i bgp` ; escalade |
| Sessions établies, route absente de la bordure | annonce non sélectionnée (labels du Service), filtre `PL-DEPUIS-K8S`, plafond `maximum-prefix` atteint | `cilium bgp routes advertised`, `show ip bgp neighbors <IP> received-routes` (si `soft-reconfiguration`), journal FRR |
| Route présente, l'application ne répond pas | ce n'est pas BGP : RB-150 (Service), RB-151 (certificat) | — |

## Pendant l'incident

- Un nœud seul : rien à faire en urgence, le multichemin sert. Nouvelle connexion perdue = le client réessaie.
- Passerelle de secours : ticket de jour.
- Passerelle **maître** sans FRR : bascule de la bordure sur l'autre passerelle par RB-071 (la bascule déplace aussi les tunnels et la traduction d'adresses : prévenir), puis réparation de FRR.
- Ne jamais élargir `PL-DEPUIS-K8S` ni désactiver `ebgp-requires-policy` « pour voir ».

## Après

- Retour du nœud : `Ready`, sessions `Established` vers les deux passerelles, chemins revenus (`ip route show 10.10.41.10` sur les deux).
- Note dans le journal (`docs/kubernetes/journal/`) : heure, durée mesurée par la sonde ou estimée, cause.

## Décision : keepalived ne surveille pas FRR

Avec `nopreempt`, seule une transition en `FAULT` fait basculer ; dans le groupe `BORDURE`, tout le groupe bascule (tunnels, NAT, tous les VLAN). Un script de surveillance de FRR qui se tromperait (FRR lent à démarrer, `vtysh` qui ne répond pas) ferait basculer **toute** la bordure. On préfère : alerte de la sonde (session et route absentes **sur le maître**) et bascule manuelle par RB-071. À revoir si une panne réelle de FRR sur le maître se produit (post-mortem).
