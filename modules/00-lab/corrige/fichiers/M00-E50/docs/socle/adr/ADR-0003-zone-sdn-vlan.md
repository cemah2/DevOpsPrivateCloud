# ADR-0003 — Réseau du lab géré par Proxmox SDN (zone VLAN)

| | |
|---|---|
| Statut | Accepté |
| Date | AAAA-MM-JJ |
| Décideurs | Claire Morel, Karim Benali, <apprenant> |
| Contexte de | M00-E28 |

## Contexte

Les VMs du lab étaient branchées sur `vmbr1` avec une étiquette (`tag=<VLAN>`) saisie à la main
dans chaque configuration. Treize VLANs (PLAN §4.2), des dizaines de VMs à venir, plusieurs
nœuds au module 09 : les erreurs d'étiquette (M00-E39 variante 1) et l'absence de nommage
deviennent un risque, et les droits sont impossibles à déléguer par réseau.

## Options

1. **Statu quo** : `vmbr1` + `tag` par VM.
2. **Proxmox SDN, zone VLAN** sur `vmbr1`, un VNet nommé par VLAN.
3. **Proxmox SDN, zone EVPN/VXLAN** (overlay routé).
4. **Open vSwitch** à la place du bridge Linux.

## Décision

Option 2 : zone `lab` de type VLAN sur `vmbr1`, VNets `vmgmt`… `vsandbox` (PLAN §4.3 bis).

## Justification

- Nommage explicite (`bridge=vinfra` au lieu de `tag=20`) : moins d'erreurs, configuration lisible.
- Droits par VNet (`SDN.Use` sur `/sdn/zones/lab/<vnet>`) : un jeton d'automatisation peut être limité aux réseaux sandbox.
- Même modèle sur plusieurs nœuds (module 09) sans reconfigurer chaque hôte.
- Pas de changement du plan d'adressage ni du routage (`gw01` reste le routeur) : migration réversible.
- EVPN/VXLAN (option 3) apporterait le routage distribué mais ajoute FRR, un overlay et une MTU réduite, sans besoin à ce stade (à réévaluer au module 09). OVS (option 4) n'apporte rien ici et diverge du standard Proxmox.

## Conséquences

- Les VMs référencent des VNets ; toute nouvelle VM doit utiliser un VNet (RB-001 mis à jour).
- La configuration réseau de l'hôte est en partie générée (`/etc/network/interfaces.d/sdn`) : on ne l'édite pas à la main, on modifie la configuration SDN puis on l'applique.
- Le diagnostic doit tenir compte de l'implémentation générée (voir M00-E47).
- Retour arrière : repasser les cartes en `bridge=vmbr1,tag=<VLAN>` (script de migration de M00-E28).
