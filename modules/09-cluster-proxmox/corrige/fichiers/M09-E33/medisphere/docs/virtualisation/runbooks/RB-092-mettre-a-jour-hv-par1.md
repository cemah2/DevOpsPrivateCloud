# RB-092 — Mettre à jour le cluster `hv-par1`

| | |
|---|---|
| Version | 1.0 (M09-E33) — complète la procédure de M09-E19 |
| Usage | mises à jour mineures et de sécurité (changement standard CHG-1059) ; § 6 pour une montée majeure (changement normal) |
| Outils | `ms-verif-cluster`, `ms-capacite-cluster`, playbook `hv-mise-a-jour.yml` (M09-E19, automatise le § 3 nœud par nœud), `hv-chien-de-garde.yml` (modèle de redémarrage contrôlé), `ceph-squid-vers-tentacle.yml` (modèle de montée Ceph) |

## 1. Préalables

1. Conditions de CHG-1059 vérifiées et collées au compte rendu.
2. Notes de version de Proxmox VE (*Roadmap*, forum « Announcements ») et de Ceph lues ; aucun « known issue » touchant nos fonctions (HA rules, SDN EVPN, Ceph RBD, ZFS, PBS).
3. Dépôts identiques sur les trois nœuds :
   ```
   root@hvNN:~# cat /etc/apt/sources.list.d/*.sources | grep -E '^(URIs|Suites|Components)'
   ```
4. Simulation sur un nœud : `apt update && apt full-upgrade -s | grep -E '^(Inst|Remv)'` : aucune ligne `Remv` de paquet Proxmox ou Ceph.

## 2. Ordre des nœuds

1. Le nœud qui **ne porte pas** le maître HA ni la VIP, et le moins chargé (`ha-manager status` : ligne `master` ; `ip -br a` : VIP).
2. Le second.
3. En dernier, celui qui porte le maître HA et la VIP : ils basculeront une fois, à la fin.

Raison : chaque bascule du maître HA ou de la VIP est un petit risque ; on n'en provoque qu'une.

## 3. Traiter un nœud (`<NŒUD>`)

| Étape | Commande | Contrôle |
|---|---|---|
| 1. Maintenance | `ha-manager crm-command node-maintenance enable <NŒUD>` | `ha-manager status` : plus aucune ressource `started` sur `<NŒUD>` |
| 2. VMs non HA | `qm migrate <VMID> <AUTRE> --online` (ou arrêt annoncé) | `qm list` sur `<NŒUD>` : aucune VM en marche |
| 3. Ceph | `ceph osd set noout` (une fois pour toute l'opération) | `ceph -s` : seul `OSDMAP_FLAGS` |
| 4. Paquets | `apt update && apt full-upgrade` | `pveversion -v` ; noter le noyau installé |
| 5. Redémarrage | `reboot` (dans le nœud) | console sur `pve01` ; `pvecm status` quorate 3/3 sous 10 min |
| 6. Noyau | `uname -r` = noyau attendu ; sinon : retour arrière § 5 | |
| 7. Ceph | les démons du nœud redémarrés avec la nouvelle version (`ceph versions`) ; PG `active+clean` | `ceph -s` |
| 8. Fin de maintenance | `ha-manager crm-command node-maintenance disable <NŒUD>` | ressources revenues selon leurs règles ; `ms-verif-cluster` vert sauf `noout` |

Une mise à jour de paquet Ceph **ne redémarre pas** les démons : c'est le redémarrage du nœud qui les fait passer à la nouvelle version, nœud par nœud — l'ordre MON → MGR → OSD de la procédure officielle est respecté parce que chaque nœud porte les trois (pour une mise à jour **mineure**, Ceph tolère ce mélange ; pour une majeure, voir § 6).

## 4. Contrôle final

```
root@hv01:~# ceph osd unset noout
root@hv01:~# for n in hv01 hv02 hv03; do ssh $n pveversion; done
root@hv01:~# ceph versions                         # une seule version par type de démon
admin@adm01:~$ ms-verif-cluster                    # code 0
```

Compte rendu dans CHG-1059 (ou la fiche du changement).

## 5. Retour arrière

- **Noyau** : au démarrage, choisir le noyau précédent ; puis l'épingler le temps de l'analyse :
  ```
  root@<NŒUD>:~# proxmox-boot-tool kernel list
  root@<NŒUD>:~# proxmox-boot-tool kernel pin <VERSION-PRÉCÉDENTE>
  ```
  (et `proxmox-boot-tool kernel unpin` ensuite).
- **Paquet isolé** : `apt install <paquet>=<version>` si la version est encore publiée ; à tracer en incident.
- **Ce qui n'est pas réversible** : démons Ceph redémarrés dans une nouvelle version (on corrige en avant), migrations de format de configuration. D'où la règle : on ne passe au nœud suivant que sur un nœud entièrement vert.

## 6. Montée majeure (changement normal)

- Proxmox VE : suivre le guide officiel de la version (pour la précédente : [Upgrade from 8 to 9](https://pve.proxmox.com/wiki/Upgrade_from_8_to_9), avec son outil de contrôle `pve8to9 --full`) ; le guide de la majeure suivante aura son propre outil. Répéter d'abord sur un cluster de test (le lab imbriqué en est un).
- Ceph : guide officiel de la montée (ex. [Ceph Squid to Tentacle](https://pve.proxmox.com/wiki/Ceph_Squid_to_Tentacle)) et playbook `ceph-squid-vers-tentacle.yml` adapté ; jamais en même temps qu'une montée de Proxmox VE.
- Fiche de changement normale (modèle CHG-1054), passage en comité, fenêtre dédiée.
