# Journal de diagnostic — INC-5239 « le coffre ne répond plus » (Nadia Roussel)

> Modèle de journal (M25-E39), rempli pour la **variante 3** (un nœud arrêté, 8201 filtré sur un autre).
> Une ligne par geste : heure, hypothèse, commande (sans secret), résultat, conclusion. Aucun jeton.

| Heure | Hypothèse | Commande | Résultat | Conclusion |
|---|---|---|---|---|
| 07:02 | — | `outils/etat-grappe.sh` (adm01) | vault01 429, vault02 000, vault03 429 ; VIP 000 ; aucun scellé | **aucun actif** : quorum ou verrou, pas le seal |
| 07:03 | — | `bao operator raft list-peers -address=https://vault01…:8200` | `local node not active but active cluster node not found` | sans actif, la CLI ne voit plus Raft : lire les nœuds |
| 07:04 | kms01 | `curl …/kms01…/v1/sys/health` | 200 | `kms01` hors de cause, **on ne le touche pas** |
| 07:06 | vault02 arrêté | `systemctl status openbao` (vault02) | `inactive (dead)` depuis 03:41, arrêt demandé (`Stopped openbao.service`) | arrêt volontaire, pas un plantage |
| 07:08 | 2 sur 3 vivants : il devrait y avoir un leader | `journalctl -u openbao --since -1h` (vault01) | élections en boucle ; vers vault02 `connection refused`, vers vault03 `i/o timeout` | deux causes **différentes** |
| 07:11 | flux 8201 vault01 → vault03 | `timeout 3 bash -c '</dev/tcp/vault03…/8201'` (vault01) | échec ; vers vault01 depuis vault03 : échec aussi | vault03 isolé sur 8201 |
| 07:12 | — | `nft list ruleset` (vault03) | `table inet maintenance` : `tcp dport 8201 drop`, `tcp sport 8201 drop` | filtrage hors Ansible (pas dans `filtre_local`) |
| 07:14 | — | décision écrite : **pas** de remove-peer, **pas** de peers.json (aucun nœud perdu, données intactes) | — | un geste à la fois |
| 07:15 | — | `systemctl start openbao` (vault02) | descellé seul (seal transit) en 6 s ; vault01 200 à 07:15:40 ; VIP 200 | **service rétabli**, tolérance 0 |
| 07:18 | — | `bao operator raft autopilot state` | `Healthy false`, `Failure Tolerance 0`, vault03 `Healthy false` (dernier contact 3 h 30) | pas fini : vault03 isolé |
| 07:20 | — | `nft delete table inet maintenance` (vault03), annoncé dans le canal | vault03 rattrape (journaux Raft) en 4 s | — |
| 07:22 | — | `autopilot state` ; écriture/lecture `kv/wb-essais/inc-5239` par la VIP | `Healthy true`, tolérance 1 ; écriture OK | coffre sain |

**Chronologie de la panne** (journaux des nœuds) : 03:38 table `inet maintenance` créée sur vault03
(la grappe tient : vault01 + vault02) ; 03:41 openbao arrêté sur vault02 → vault01 seul, il perd le
quorum (`failed to contact quorum of nodes, stepping down`), plus d'actif, VIP retirée par keepalived ;
03:42 `OpenBaoSansLeader`. Rien n'a été perdu : aucune écriture n'a été acceptée sans quorum.

**Causes** : deux gestes de maintenance, chacun inoffensif seul, cumulés sur une grappe de trois.
**Correctif** : relance de vault02, suppression du filtrage de vault03 (puis `playbooks/coffre.yml`
en `--check --diff` : aucune différence, la table était hors du rôle).
**Prévention** : fiche [`maintenance-grappe.md`](../../securite/secrets/maintenance-grappe.md) (vérifier
la tolérance avant **chaque** geste, un nœud à la fois) ; tout filtrage passe par `pare_feu_local`
(un `nft` à la main ne survit qu'au hasard et ne se voit pas dans Git) ; alerte `OpenBaoToleranceNulle`
lue avant toute maintenance.

**Si un nœud avait été perdu pour de bon** (deux nœuds détruits) : récupération par `peers.json` sur le
seul survivant, décrite dans la fiche (§ Dernier recours) — décidée avec Karim, après un instantané
vérifié, jamais seul la nuit.
