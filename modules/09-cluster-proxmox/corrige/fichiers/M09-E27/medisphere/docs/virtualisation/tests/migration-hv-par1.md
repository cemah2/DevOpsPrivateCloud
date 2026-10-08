# Réseau de migration du cluster `hv-par1` (PLAT-1053)

> Modèle de compte rendu (corrigé M09-E27). Les chiffres sont **indicatifs** (lab imbriqué : tous les « liens » sont le pont `vmbr1` de `pve01`) ; remplace-les par tes mesures.

## Configuration retenue

| Réglage | Valeur | Où |
|---|---|---|
| `migration` | `type=secure,network=10.10.30.0/24` | `datacenter.cfg`, rôle `pve_cluster` |
| `bwlimit` | `migration=307200,restore=204800` (Kio/s) | idem |
| Corosync | lien 0 10.10.32.0/24, lien 1 10.10.10.0/24 | `corosync.conf` (E04), inchangé |
| Pare-feu | SSH entre nœuds autorisé depuis l'IPSet `hv_noeuds` (VLAN 30 compris) | `pve_pare_feu` |

## Mesures (VM 122 `migr01`, 4 Go, disque `ceph-vm`)

| Essai | Réseau | Charge mémoire | Durée | Débit moyen | *downtime* | Latence Corosync lien 1 (moy./max.) |
|---|---|---|---|---|---|---|
| 1 | MGMT (défaut) | aucune | 38 s | 115 Mio/s | 45 ms | 0,3 / 2 ms → 0,9 / 41 ms |
| 2 | MGMT (défaut) | 2 Go réécrits | 4 min 05 | 120 Mio/s | 610 ms | 0,3 / 2 ms → 4 / 380 ms, jetons retransmis |
| 3 | VLAN 30, `secure`, 300 Mio/s | aucune | 17 s | 260 Mio/s | 40 ms | inchangée |
| 4 | VLAN 30, `secure`, 300 Mio/s | 2 Go réécrits | 52 s | 290 Mio/s | 280 ms | inchangée |
| 5 | VLAN 30, `insecure` (une fois, en argument) | 2 Go réécrits | 31 s | 480 Mio/s | 210 ms | inchangée |

Preuve du réseau utilisé (journal de la tâche) :

```
use dedicated network address for sending migration traffic (10.10.30.73)
```

## Lecture

- Essai 2 : avec 2 Go réécrits en boucle et ~120 Mio/s, chaque passe recopie presque tout ce qu'elle vient de copier : la convergence est lente, le *downtime* final élevé. Le même lien porte le lien 1 de Corosync : latence maximale à 380 ms, jetons retransmis. Avec un seul lien Corosync, c'était une perte de membre en vue.
- Essais 3-4 : en `secure`, le chiffrement SSH limite le débit (un cœur de chiffrement par flux), mais le réseau dédié et le MTU 9000 font plus que doubler le débit, et Corosync ne voit plus rien.
- Essai 5 : `insecure` gagne encore ~ 60 % : pas de chiffrement, flux direct de QEMU sur les ports 60000-60050 (à ouvrir entre nœuds dans `pve_pare_feu`). **Non retenu** : données de santé en clair sur un VLAN partagé avec le réseau public de Ceph ; décision à revoir si un réseau de migration **dédié et isolé** (lien physique point à point ou VLAN non routé réservé) existe sur le matériel réel, et après avis de la RSSI.
- Charge qui ne converge pas (limite abaissée à 50 Mio/s, 3 Go réécrits) : la tâche tourne sans fin, QEMU annonce à chaque passe autant de pages modifiées ; on l'annule. Pistes : *auto-converge* (QEMU ralentit les vCPU de l'invité), *postcopy*, ou migrer hors des heures de charge.

## Décisions

1. Migration `secure` sur le VLAN 30, limite de 300 Mio/s (laisse au moins la moitié du lien réel à Ceph).
2. Jamais de migration sur un réseau qui porte un lien Corosync.
3. Matériel réel : réseau de migration dédié (ou au minimum VLAN dédié sur les interfaces de stockage), à prévoir dans le dossier d'achat.
