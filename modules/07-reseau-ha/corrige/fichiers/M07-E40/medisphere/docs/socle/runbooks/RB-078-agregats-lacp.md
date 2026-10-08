# RB-078 — Agrégat LACP dégradé

| | |
|---|---|
| **Portée** | Agrégats 802.3ad des hyperviseurs (bond Linux ou Open vSwitch) et, dans le lab, `net01` |
| **Déclencheur** | Sonde « ports dans l'agrégateur actif < attendu » ; débit divisé ; perte de redondance signalée |
| **Durée cible** | 10 min jusqu'au diagnostic |
| **Issu de** | INC-3406 (M07-E40) |

## 1. Lire les deux côtés

```
# côté serveur (bond Linux)
$ cat /proc/net/bonding/bond0
# côté commutateur virtuel (Open vSwitch) ou réel (show lacp neighbor / show etherchannel summary)
$ ovs-appctl bond/show ; ovs-appctl lacp/show ; ovs-vsctl list port <port agrégé>
```

## 2. Pour chaque membre

| Question | Où lire | Anomalie |
|---|---|---|
| Administrativement actif ? | `ip link` (drapeau `UP`) des deux extrémités | Extrémité distante `DOWN` → `NO-CARRIER` côté serveur |
| Porteuse ? | `MII Status` | `down` |
| Membre du bond ? | `/sys/class/net/bond0/bonding/slaves`, `ip -d link` (`master`) | Lien `UP` hors du bond |
| LACPDU échangées, même partenaire ? | `Aggregator ID`, `Partner Mac Address`, `details partner lacp pdu` | Agrégateurs différents, partenaire `00:00:00:00:00:00` |

## 3. Corriger

- Lien coupé : rétablir l'extrémité (ou le câble, ou le port du commutateur) ; vérifier que la configuration persistante (unité systemd, `/etc/network/interfaces`) le monte au démarrage.
- LACP désactivé ou passif des deux côtés : `lacp=active` (Open vSwitch, persistant dans sa base) ou mode `802.3ad` côté commutateur.
- Membre sorti : `ip link set <membre> down ; ip link set <membre> master bond0 ; ip link set <membre> up`, puis corriger la configuration persistante.

## 4. Prouver

Deux ports dans l'agrégateur actif, partenaire connu et identique, compteurs des deux membres qui avancent avec plusieurs flux (`iperf3 -P 4`). `lab/bin/check 07 40` sur la maquette.
