# Tests de bascule de la bordure PAR1

> Chiffres de référence pour ADR-0070, RB-071 et le PRA (F5). Une section datée par campagne ; la plus récente en tête. Valeurs ci-dessous : **modèle** (ordres de grandeur attendus), à remplacer par tes mesures.

## Campagne du `<DATE>` (M07-E32, PLAT-861)

**Conditions** : `gw01` maître, `nopreempt`, `advert_int 1`, `conntrackd` actif, `nf_conntrack_tcp_loose=0` ; aucune sauvegarde PBS en cours ; maquette en service (`leaf01`, `lyo-gw01`).

**Flux mesurés** (outil `ms-mesure-bascule`, 10 paquets/s) :
- F1 : VM jetable du VLAN 99 → 1.1.1.1 (traduit, sort par la VIP WAN) ;
- F2 : `adm01` → VM du VLAN 99 (routé entre VLAN) ;
- F3 : `adm01` → `pve01` (WAN, sans traduction) ;
- S1 : session SSH `adm01` → VM du VLAN 99 avec `watch -n1 date` ; S2 : téléchargement d'un fichier de 2 Go depuis Internet sur la VM, somme de contrôle à l'arrivée.

**Critères d'arrêt** (écrits avant) : une VIP sans porteur plus de 30 s ; perte de la session SSH de secours par le WAN ; comportement non expliqué. Retour à l'état nominal (RB-071 §3) après **chaque** scénario, `ms-verif-reseau` vert avant le suivant.

| # | Scénario | Moyen | F1 | F2 | F3 | S1 | S2 | BGP Lyon | `wg0` | État final | Alerte |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Bascule planifiée | `systemctl stop keepalived` sur `gw01` (RB-071) | 0,3 s | 0,2 s | 0,3 s | vit | vit | 9 s | 6 s | `gw02` | redondance perdue (attendu) |
| 2 | Retour planifié | RB-071 §3 | 0,3 s | 0,3 s | 0,2 s | vit | vit | 8 s | 5 s | `gw01` | — |
| 3 | Plantage de keepalived | `kill -9` de keepalived sur le maître | 3,5 s | 3,6 s | 3,6 s | vit | vit | 12 s | 7 s | `gw02` | oui |
| 4 | Coupure de courant | `qm stop 1000` | 3,6 s | 3,6 s | 3,7 s | vit | vit | 13 s | 8 s | `gw02` | oui |
| 5 | Trunk du maître coupé | `link_down=1` sur `net1` de 1000 | 3,6 s | 3,6 s | 3,6 s | vit | vit | 10 s | 6 s | `gw02` (FAULT sur `gw01`) | oui |
| 6 | WAN du maître coupé | `link_down=1` sur `net0` de 1000 | 3,6 s | 0,3 s | 3,6 s | vit | vit | 9 s | 6 s | `gw02` | oui |
| 7 | Cerveau divisé partiel (VLAN 99) | règle `TEST-E32` jetant le protocole 112 sur `ens19.99` de `gw02` | erratique | erratique | 0 s | coupée par moments | erratique | stable | stable | deux maîtres sur 99 | oui (`portée par 2 hôtes`) |
| 8 | Retour du nœud tombé | `gw01` redémarrée après le n° 4 | 0 s | 0 s | 0 s | vit | vit | stable | stable | `gw02` (nopreempt) | redondance retrouvée |

**Analyse**
- Panne franche (3, 4) : ≈ 3,6 s = *Master_Down_Interval* de `gw02` (3 × 1 s + *skew* (256 − 100)/256 ≈ 0,6 s). Bascule planifiée (1, 2) : l'annonce de priorité 0 fait basculer après le seul *skew*.
- Pannes de lien (5, 6) : `gw01` passe tout le groupe en `FAULT` dès la perte du lien suivi et rend ses VIP ; les instances dont l'interface est **encore active** envoient une annonce de priorité 0 (bascule en ≈ 0,3 s), celles du lien coupé ne peuvent rien envoyer : `gw02` attend son *Master_Down_Interval* (≈ 3,6 s). D'où, en 6, F2 rapide (VLAN 10 et 99 sur le trunk intact) et F1/F3 lents (ils ont besoin de la VIP WAN). À vérifier sur ton lab : c'est le genre de détail que la campagne sert à établir.
- BGP de Lyon : le tunnel reprend dès la première poignée de main (≤ 5 s avec un *keepalive* de 25 s côté LYO1 ou le premier paquet), puis la session BGP se rétablit (connexion TCP + OPEN) ; la durée dépend surtout de la détection de la session morte côté `lyo-gw01` (*hold time*).
- Cerveau divisé (7) : les VMs du VLAN 99 alternent entre deux MAC de passerelle au gré des ARP gratuits ; les flux sortent par l'une et reviennent par l'autre (groupe de synchronisation inopérant : chaque passerelle se croit maître du groupe entier, sauf le VLAN 99 en double). Détecté par `ms-verif-reseau` en moins de 5 minutes.
- Sans `conntrackd` (campagne M07-E27) : S1 et S2 coupés dans les scénarios 3 à 6 avec `nf_conntrack_tcp_loose=0`.

**Propositions** : objectif de niveau de service interne « perte ≤ 5 s par panne d'une passerelle, ≤ 1 s par bascule planifiée » ; *hold time* BGP de Lyon à 30 s (contre 180 s par défaut), à valider en E19 ; garder `advert_int 1` (0,5 s divise la perte mais double les annonces et rend le cerveau divisé plus probable sur une VM chargée).

**Non testé** : panne de `pve01` (hors du périmètre de la bordure, PRA F5), panne de la box, double panne, dégradation lente (perte partielle de paquets) — prévue au module 29 (Chaos Mesh, essais réseau).

## Campagne conntrackd (M07-E27, `<DATE>`)

| Flux pendant une bascule planifiée | Sans conntrackd, `tcp_loose=1` | Sans conntrackd, `tcp_loose=0` | Avec conntrackd, `tcp_loose=0` |
|---|---|---|---|
| SSH `adm01` → VM du VLAN 99 | vit (reprise) | coupée | vit |
| Téléchargement traduit (VM → Internet) | `<…>` | coupé | vit |
| HTTPS long depuis le LAN maison (redirigé) | `<…>` | coupé | vit |
