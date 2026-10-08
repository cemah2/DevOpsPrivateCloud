# ADR-0070 — Haute disponibilité de la bordure PAR1

- **Statut** : accepté (`<DATE>`), mis en œuvre par CHG-855 et CHG-856
- **Décideurs** : Claire Morel ; consultés : Karim Benali, Sophie Laurent, Nadia Roussel
- **Tickets** : PLAT-850 à PLAT-853, PLAT-860

## Contexte et problème

Tout le site PAR1 passe par une passerelle : routage inter-VLAN, filtrage, traduction vers Internet, VPN d'administration (`wg1`), tunnel vers PAR2 (`wg0`, sauvegardes), tunnel vers LYO1 (`wg2`), relais DHCP, NTP, BGP vers la fabric et bientôt vers Kubernetes. Un redémarrage de `gw01` coupait tout pendant six minutes (PLAT-850). Le bloc B ajoute du stockage distribué et un cluster de virtualisation qui ne tolèrent pas ces coupures.

Exigences : **(E1)** disponibilité de la bordure ≥ 99,95 % hors `pve01` ; **(E2)** perte ≤ 5 s lors d'une panne franche, ≤ 2 s lors d'une bascule planifiée ; **(E3)** les connexions TCP établies (SSH, transferts, réplication) survivent à une bascule planifiée ; **(E4)** aucun client à reconfigurer ; **(E5)** exploitable par l'astreinte avec un runbook ; **(E6)** contraintes du lab : un seul hyperviseur, aucun commutateur physique, LAN maison avec une box.

## Options envisagées

1. **Passerelle unique, restauration rapide** (instantané, sauvegarde PBS, reconstruction par le code).
2. **Deux passerelles Linux en VRRP actif-passif (keepalived) avec synchronisation des connexions (conntrackd)**.
3. **Routage actif-actif** : passerelles en ECMP vers une fabric BGP, passerelle *anycast* distribuée (EVPN).
4. **Appliance pare-feu redondante** (OPNsense/pfSense : CARP + `pfsync`).
5. **Passerelle unique sous la haute disponibilité de Proxmox** (cluster `hv-par1`, module 09).

| Critère | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| Perte sur panne franche | minutes | ≈ 4 s mesurés (E32) | < 1 s (ECMP) | ≈ 1-3 s | 1-3 min (redémarrage de VM) |
| Connexions établies (E3) | perdues | conservées (conntrackd, E27) | conservées si état partagé, sinon perdues ; asymétrie par nature | conservées (`pfsync`) | perdues |
| NAT et VPN | — | suivent le maître (VIP WAN, transition) | difficile : NAT avec état et tunnels sur plusieurs nœuds actifs | intégrés | — |
| Clients à reconfigurer (E4) | non | non | non si *anycast* ; sinon oui | non | non |
| Dépendances | PBS | aucune nouvelle | fabric L3 réelle (commutateurs, EVPN) : absente du lab | une autre pile (FreeBSD) hors outillage | cluster de virtualisation (M09), toujours sur `pve01` |
| Exploitation (E5) | simple | moyenne : scripts de transition, secrets dupliqués | élevée | moyenne, mais hors Ansible et matrice en code | simple |
| Cohérence avec l'outillage | oui | oui (Ansible, nftables, matrice unique) | partielle | non | oui |

## Décision

**Option 2.** Deux passerelles Debian `gw01`/`gw02`, keepalived (VRRP v3, unicast, un groupe de synchronisation pour les neuf VLAN et le WAN, `nopreempt`), `conntrackd` (FTFW sur le VLAN 10), traduction sortante vers une VIP WAN, tunnels WireGuard montés par la transition, matrice des flux unique. Mesures du lab (`docs/socle/tests/bascules.md`) : `<À REPORTER>` s en panne franche, `<À REPORTER>` s en bascule planifiée, sessions SSH et transferts conservés en bascule planifiée.

L'option 3 est la cible de long terme **pour le trafic est-ouest** des clusters (EVPN au module 09, BGP de Kubernetes au module 15), pas pour la bordure avec état. L'option 4 est écartée : elle sort la bordure de l'outillage (code, matrice, revue de MR) pour un gain faible. Les options 1 et 5 ne tiennent ni E2 ni E3.

## Conséquences

Positives : plus de coupure longue ; maintenance de jour d'une passerelle (RB-071) ; une seule matrice des flux ; la bordure est reconstructible par le code (`gw02` entièrement, `gw01` hors état OpenTofu, ADR-0051).

Négatives et actions :
- **Point unique restant : `pve01`** (les deux passerelles sont des VMs du même hôte), la box et le LAN maison. Accepté pour le lab ; traité par le PRA (F5) et, pour les VMs, par le cluster (M09).
- **Règle « rien ne vise une adresse propre »** (Ansible, voisins BGP, sondes, extrémités) : à respecter dans chaque module ; contrôle `lab/bin/check 07 46`. Les nœuds Kubernetes (M15) s'appairent aux adresses propres `.2`/`.3`, jamais à la VIP.
- **Secrets dupliqués** (clés WireGuard sur deux hôtes) : registre des secrets, rotation annuelle (M25).
- **Scripts de transition** : un point de fragilité ; supervisés (`ms-verif-reseau`, M07-E29), testés à chaque campagne (M07-E32, puis M29).
- **Cerveau divisé** possible si les annonces sont filtrées : supervisé, procédure dans RB-071 ; pas de *fencing* (accepté).
- **`nf_conntrack_tcp_loose=0`** : si `conntrackd` ne synchronise pas, une bascule coupe les connexions TCP ; supervisé.

## Révision

À revoir si : un second hyperviseur PAR1 existe (passerelles sur deux hôtes : la décision se renforce) ; la perte mesurée dépasse E2 deux fois de suite ; le trafic dépasse la capacité d'une passerelle (option 3 pour la bordure) ; une exigence d'audit impose un pare-feu certifié (option 4).
