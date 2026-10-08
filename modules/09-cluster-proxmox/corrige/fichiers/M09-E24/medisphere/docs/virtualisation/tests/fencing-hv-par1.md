# Test de fencing du cluster `hv-par1` (PLAT-1050)

> Modèle de compte rendu (corrigé M09-E24). Les heures et durées sont **indicatives** : remplace-les
> par tes mesures. Ce qui compte, c'est la décomposition et son explication.

| | |
|---|---|
| Date | 2026-10-XX |
| Opérateur | `<MOI>` |
| Cluster | `hv-par1` (3 nœuds, Proxmox VE 9.2), Ceph `ceph-vm` size 3 / min_size 2 |
| VMs de test | 120 `fence01` (préfère `hv02`), 121 `fence02` (règle négative avec 120), 1 Go, disque `ceph-vm` |
| Mesure | `mesure-coupure.sh <IP-FENCE01> 22` depuis `adm01` (adresse IP : indépendant du DNS) |

## 1. Prédiction (écrite avant les essais)

Arrêt brutal de `hv02` qui porte `fence01` :

1. t0 : `hv02` disparaît ; Corosync constate la perte après le délai de jeton (*token*, une à quelques secondes) ; nouvelle appartenance à 2 nœuds, quorum conservé (2 votes sur 3).
2. Le CRM maître constate que le LRM de `hv02` ne renouvelle plus son verrou dans `pmxcfs` ; la ressource passe en `fence`.
3. Le CRM attend de pouvoir prendre le verrou du LRM de `hv02` : ce verrou expire au bout d'un délai calé sur celui du chien de garde (60 s) plus une marge ; c'est la **garantie** que `hv02`, s'il vivait encore sans quorum, s'est redémarré.
4. Ressource en `recovery`, choix du nœud (règles d'affinité, puis charge), puis `started` sur `hv01` ou `hv03` (pas sur le nœud de `fence02` : règle négative).
5. Démarrage de la VM (QEMU) puis de l'invité (≈ 15-25 s pour Debian 13), puis sshd.

Attendu : 2 à 3 minutes (la documentation annonce « environ 2 minutes » pour détection et bascule, plus le démarrage de l'invité).

## 2. Mesures

### Scénario A — coupure d'alimentation (`qm stop 2092` sur `pve01`)

| Heure | Écart | Événement (source) |
|---|---|---|
| 14:02:10 | 0 s | `qm stop 2092` |
| 14:02:12 | 2 s | sonde : INTERROMPU |
| 14:02:15 | 5 s | `pvecm status` (hv01) : 2 nœuds, quorate |
| 14:02:30 | 20 s | `ha-manager status` : `hv02` `unknown`, `vm:120` `fence` |
| 14:04:12 | 122 s | `pve-ha-crm` : verrou du LRM de `hv02` obtenu, `vm:120` `recovery` puis `started` sur `hv03` |
| 14:04:35 | 145 s | sonde : RÉTABLI après 143 s |

RTO mesuré : **143 s**. `hv02` redémarré : `vm:120` revient sur `hv02` après le retour du nœud (règle d'affinité non stricte, `failback` actif par défaut) — migration à chaud, sans interruption.

### Scénario B — isolement de `hv02` (Corosync bloqué, `softdog`)

Règle posée dans `hv02` (table à part, non persistante) :

```
root@hv02:~# nft add table inet m09e24
root@hv02:~# nft add chain inet m09e24 entree '{ type filter hook input priority -10; }'
root@hv02:~# nft add chain inet m09e24 sortie '{ type filter hook output priority -10; }'
root@hv02:~# nft add rule inet m09e24 entree udp dport 5405-5412 drop
root@hv02:~# nft add rule inet m09e24 sortie udp dport 5405-5412 drop
```

| Heure | Écart | Événement |
|---|---|---|
| 15:10:00 | 0 s | règles posées |
| 15:10:03 | 3 s | `hv02` : `pvecm status` → *Quorate: No*, 1 nœud ; `/etc/pve` en lecture seule |
| 15:10:05 | 5 s | `hv01` : 2 nœuds, quorate ; `vm:120` `fence` |
| 15:11:01 | 61 s | console de `hv02` : redémarrage (chien de garde expiré) |
| 15:12:10 | 130 s | `vm:120` `started` sur `hv03` |
| 15:12:31 | 151 s | sonde : RÉTABLI après 150 s |

Pendant 60 s, `fence01` **a continué de tourner** sur `hv02` (la sonde depuis `adm01` passait encore : SSH et MGMT n'étaient pas filtrés) : c'est normal, le nœud isolé n'a pas de quorum mais ses VMs tournent jusqu'au redémarrage. Le CRM n'a relancé `fence01` ailleurs qu'**après** ce redémarrage garanti : jamais deux copies.

Trace après redémarrage (`journalctl -b -1` sur `hv02`) : `pve-ha-lrm` signale la perte du verrou (*lost lock*), `watchdog-mux` signale que le client n'a plus nourri le chien de garde, puis le journal s'arrête net (redémarrage par le chien de garde, pas d'arrêt propre).

### Scénario C — isolement sans ressource HA sur `hv02`

`fence01` déplacée sur `hv01` avant l'isolement ; LRM de `hv02` en `idle`.

Résultat : `hv02` perd le quorum mais **ne redémarre pas**. Le LRM n'avait pas armé le chien de garde (aucune ressource HA à protéger) : il n'y a rien à « clôturer ». Les VMs non HA de `hv02` continuent de tourner, mais aucune action de gestion n'est possible (`/etc/pve` en lecture seule) ; elles ne sont redémarrées nulle part ailleurs. Au retrait de la règle, `hv02` rejoint le cluster sans redémarrage.

### Scénario B' — isolement avec le chien de garde émulé `i6300esb`

| Écart | Événement |
|---|---|
| 0 s | règles posées |
| 61 s | redémarrage de la VM `hv02` par QEMU (journal de `pve01` : aucune trace, c'est l'invité qui est réinitialisé ; console : écran de démarrage) |
| 128 s | `vm:120` `started` sur `hv03` |
| 149 s | sonde : RÉTABLI |

Chronologie identique à B pour un isolement réseau : le noyau de `hv02` fonctionnait, `softdog` aurait suffi. La différence se voit quand le **noyau** du nœud est bloqué (panique, gel, pause de la VM) : `softdog` est un minuteur du noyau, il se bloque avec lui ; la carte émulée est un minuteur de QEMU, extérieur au nœud.

## 3. Écart à la prédiction

- Délai dominant : l'attente du verrou (~ 2 min). Il est **voulu** : c'est le prix de l'absence de double démarrage.
- Démarrage de l'invité : 20-25 s, à ajouter au RTO « vu de l'utilisateur ».
- Le temps de détection par Corosync (quelques secondes) est négligeable devant le reste.

## 4. Recommandation pour le matériel réel

- Chien de garde **matériel** sur chaque serveur (iTCO de la carte mère, ou chien de garde IPMI du BMC : `WATCHDOG_MODULE=ipmi_watchdog`), validé avant mise en production par un test d'isolement.
- RTO à annoncer pour une VM HA : **3 minutes** (2 min de garantie + démarrage), à écrire dans le catalogue de services ; pour un RTO plus court, il faut une application redondante, pas une VM HA.
- Aucune VM sans HA ne doit porter un service qu'on annonce « hautement disponible ».
