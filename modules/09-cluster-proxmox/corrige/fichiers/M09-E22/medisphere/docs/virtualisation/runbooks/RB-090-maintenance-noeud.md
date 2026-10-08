# RB-090 — Maintenance d'un nœud du cluster `hv-par1`

| | |
|---|---|
| **Objet** | Sortir un nœud du cluster pour une intervention (logicielle ou matérielle) et le remettre en service, sans interruption des VMs ni reconstruction Ceph inutile |
| **Ticket d'origine** | PLAT-1032 (M09-E22) |
| **Propriétaire** | Équipe Plateforme ; exécutable par l'astreinte (groupe `hv-admins` requis) |
| **Durée** | 20 à 40 min hors intervention ; prévoir une fenêtre de changement |
| **Révision** | à chaque montée de version de Proxmox VE ou de Ceph, et après chaque exécution qui a hésité |

## Quand l'utiliser

- Redémarrage planifié (noyau, micrologiciel, paramètre de démarrage) : **intervention courte** (< 30 min).
- Arrêt pour intervention matérielle (mémoire, disque système, carte réseau) : **intervention longue** (> 30 min).
- Mise à jour de paquets d'un seul nœud. Pour tous les nœuds : `playbooks/hv-mise-a-jour.yml` (M09-E19), qui applique ce runbook automatiquement.

## Quand **ne pas** l'utiliser

- Le nœud est **déjà** en panne ou injoignable : **RB-091** (perte d'un nœud). La HA a déjà agi ; ne pas le « mettre en maintenance ».
- Le cluster n'a pas le quorum, ou Ceph n'est pas `HEALTH_OK` : on ne retire pas un deuxième pied à une table bancale. Escalade (Karim Benali), pas de maintenance.
- Un autre nœud est déjà en maintenance : **jamais deux à la fois** (Ceph passe sous `min_size` 2, plus de place pour la HA).
- Changement de configuration du **réseau du cluster** ou de Corosync : procédure de changement dédiée, avec désarmement de la HA (`ha-manager crm-command disarm-ha freeze`).

## Prérequis

- [ ] Fiche de changement validée (CHG-…), fenêtre annoncée à `#exploitation` et à Nadia Roussel (astreinte).
- [ ] Compte nominatif du groupe `hv-admins` ; SSH `root@hvNN` depuis `adm01`.
- [ ] **Accès de secours vérifié** : console série du nœud depuis `pve01` (`qm terminal <VMID>` : 2091, 2092, 2093) ; en production, iLO/IPMI du serveur.
- [ ] Sauvegarde de la nuit réussie pour les VMs du nœud (tâche `hv-nuit`, `pbs-par2`).

## Contrôles d'entrée (à faire sur n'importe quel nœud **autre** que celui à arrêter)

| # | Commande | Attendu | Sinon |
|---|---|---|---|
| E1 | `pvecm status` | `Quorate: Yes`, 3 nœuds membres | STOP — RB-091 ou escalade |
| E2 | `ceph -s` | `HEALTH_OK`, 6 OSD `up`/`in` | STOP — traiter Ceph d'abord |
| E3 | `ha-manager status` | maître présent, aucun LRM en `maintenance`, aucune ressource en `error` | STOP |
| E4 | `pvesh get /cluster/resources --type node --output-format json-pretty` | mémoire libre des deux **autres** nœuds ≥ mémoire utilisée par les VMs du nœud à vider | réduire la charge (arrêter des VMs non critiques) avant de continuer |
| E5 | `pvesr status` (sur le nœud) | aucune tâche de réplication en échec | relancer la tâche, attendre son succès |
| E6 | `qm list` et `pct list` (sur le nœud) | liste des invités notée dans la fiche de changement | — |

## Étapes

Remplace `<NŒUD>` par le nœud concerné (ex. `hv02`).

1. **Annoncer** le début sur le canal d'exploitation (heure, nœud, durée prévue).
2. **Mode maintenance HA** (depuis n'importe quel nœud) :
   ```
   root@hv01:~# ha-manager crm-command node-maintenance enable <NŒUD>
   ```
   Attendu en moins de 5 minutes : `ha-manager status` montre `lrm <NŒUD> (maintenance mode…)` et plus aucune ligne `service … (<NŒUD>, started)`. Le journal du nœud affiche `watchdog closed (disabled)` (`journalctl -u pve-ha-lrm`).
   Sinon : une ressource ne peut pas partir (règle d'affinité **stricte** limitée à ce nœud, disque local non répliqué) → la migrer à la main vers un nœud autorisé ou l'arrêter proprement **avec l'accord du métier**. Ne jamais forcer l'arrêt du nœud avec une ressource HA dessus.
3. **Invités non HA** (la maintenance ne les déplace pas) :
   ```
   root@<NŒUD>:~# pvenode migrateall <CIBLE> --max-workers 2 --with-local-disks
   ```
   Attendu : `qm list` sur le nœud ne montre plus aucune VM `running`. Une VM à disque local **répliqué** (ex. `rep01`, M09-E14) migre en ne transférant que le delta ; une VM à disque local **non** répliqué copie tout son disque : vérifier la place sur la cible, ou l'arrêter si son propriétaire l'accepte.
4. **Ceph** — choisir selon la durée :
   - *Intervention courte* (< 30 min) : empêcher le passage `out` des OSD **de ce nœud seulement** :
     ```
     root@hv01:~# ceph osd set-group noout <NŒUD>
     ```
     Attendu : `ceph health detail` affiche `OSD_FLAGS … host <NŒUD> has flags noout`.
   - *Intervention longue* : décider avec Karim. Deux options : (a) `noout` comme ci-dessus — les données n'ont que **deux** copies pendant toute l'intervention, une seconde panne bloque les écritures ; (b) laisser Ceph reconstruire (pas de drapeau) — il recopie les données des OSD absents sur les deux autres nœuds : avec trois nœuds et `size 3`, **il ne le peut pas** (pas de troisième hôte) ; les PG restent `undersized`. Dans ce cluster, l'option (a) est donc la seule utile ; noter l'heure de pose du drapeau.
5. **Intervention** : `reboot` (courte) ou `shutdown -h now` (longue) depuis la console du nœud ou en SSH. Suivre le démarrage sur la console série.
6. **Retour** (sur le nœud revenu) :
   | # | Commande | Attendu |
   |---|---|---|
   | R1 | `pvecm status` | `Quorate: Yes`, 3 membres |
   | R2 | `systemctl is-active pve-cluster pvedaemon pveproxy pve-ha-lrm pve-ha-crm` | `active` × 5 |
   | R3 | `ceph osd tree` | les deux OSD de `<NŒUD>` `up` |
   | R4 | `pvesm status` | tous les stockages `active` (dont `ceph-vm`, `zfs-local`, `pbs-par2`) |
   | R5 | `ip -br addr` | adresses MGMT, COROSYNC, Ceph conformes ; MTU 9000 sur les cartes Ceph |
   Sinon : laisser le nœud en maintenance et le drapeau posé, ouvrir un incident, appliquer RB-091 si le nœud ne revient pas dans le délai annoncé.
7. **Ceph** : retirer le drapeau, attendre `HEALTH_OK` (quelques minutes de récupération des écritures faites pendant l'absence) :
   ```
   root@hv01:~# ceph osd unset-group noout <NŒUD>
   root@hv01:~# watch -n 5 ceph -s
   ```
8. **Sortie de maintenance HA** :
   ```
   root@hv01:~# ha-manager crm-command node-maintenance disable <NŒUD>
   ```
   Attendu : les ressources HA qui étaient sur le nœud y **reviennent** (comportement documenté). Les invités non HA migrés à l'étape 3 ne reviennent pas seuls : les remettre à la main si leur placement compte (`qm migrate <VMID> <NŒUD> --online`).
9. **Annoncer** la fin.

## Contrôles de sortie (obligatoires)

- [ ] `ha-manager status` : aucun LRM en maintenance, toutes les ressources `started`, fencing armé.
- [ ] `ceph -s` : `HEALTH_OK` ; `ceph osd dump | grep flags` sans `noout` ; `ceph health detail` sans `OSD_FLAGS`.
- [ ] `pvesr status` : tâches de réplication à jour (lancer `pvesr schedule-now <ID>` au besoin).
- [ ] Règles HA respectées (`app02` et `app03` sur deux nœuds différents).
- [ ] Fiche de changement complétée (heures, écarts, durée réelle).

## Retour arrière (abandon en cours de route)

| Abandon après l'étape | Faire |
|---|---|
| 2 (maintenance) | `node-maintenance disable <NŒUD>` ; les ressources reviennent |
| 3 (migration des non HA) | remigrer les invités vers `<NŒUD>` si nécessaire |
| 4 (drapeau Ceph) | `ceph osd unset-group noout <NŒUD>` |
| 5 (nœud éteint) | le redémarrer, puis étapes 6 à 9 ; s'il ne redémarre pas : RB-091, en laissant drapeau et maintenance |

## Pièges connus

- `ceph osd set noout` (sans `-group`) pose le drapeau sur **tout** le cluster : une vraie panne d'un autre nœud pendant la fenêtre ne déclencherait aucune reconstruction. Toujours limiter au nœud.
- Oublier le drapeau ou la maintenance en fin d'intervention : rien ne le signale tout de suite. D'où les contrôles de sortie (et la sonde `ms-verif-cluster`, M09-E25).
- La politique d'arrêt `migrate` (M09-E20) migre les ressources HA lors d'un `reboot`, mais **pas** les invités non HA, et pas une ressource bloquée par une règle stricte : l'arrêt reste suspendu jusqu'à intervention.
- Redémarrer un nœud qui porte la **VIP de l'API** (`hv.par1.medisphere.internal`, M09-E18) : elle bascule en quelques secondes ; un `tofu apply` en cours peut échouer — prévenir l'équipe ou geler les pipelines de `plateforme/infra` pendant la fenêtre.
- Mode maintenance HA et `disarm-ha` ne sont pas la même chose : le premier vide un nœud, le second suspend la HA de **tout** le cluster.
