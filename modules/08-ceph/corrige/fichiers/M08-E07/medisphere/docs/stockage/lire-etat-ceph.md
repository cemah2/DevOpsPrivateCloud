# Lire l'état du cluster `ceph-par1` — fiche d'astreinte

> Fiche courte, à garder ouverte pendant une astreinte (M08-E07, demande de Nadia Roussel).
> Où lancer les commandes : sur un nœud `_admin` (`ceph01`, `ceph02` ou `ceph03`), en root
> (`sudo -i`), ou par `cephadm shell` si la commande `ceph` manque.
> **Règle d'or** : on observe d'abord, on agit ensuite, et on n'agit jamais avec une commande
> qu'on ne comprend pas (`purge`, `zap`, `pool delete`, `mark_unfound_lost` : appel à l'équipe).

## 1. Les trente premières secondes

| Question | Commande | Ce qu'on lit |
|---|---|---|
| Le cluster va-t-il bien ? | `ceph -s` | `health`, `mon` (quorum), `mgr` (actif + en attente), `osd` (N up / N in), `pgs` (états), `io` (client, récupération) |
| Pourquoi pas `HEALTH_OK` ? | `ceph health detail` | chaque alerte par son **code** (`OSD_DOWN`, `PG_DEGRADED`, `MON_CLOCK_SKEW`…) et les objets concernés |
| Ça bouge ? | `ceph -w` (Ctrl-C pour sortir) | le journal du cluster en direct |
| Que s'est-il passé ? | `ceph log last 50` · `ceph crash ls-new` | les derniers événements, les plantages de démons non encore acquittés |

États de santé : `HEALTH_OK` (rien à faire), `HEALTH_WARN` (dégradé, le service continue
le plus souvent), `HEALTH_ERR` (données inaccessibles ou en danger : appel immédiat).

## 2. Où est le problème ?

| Brique | Commandes | Signes d'alerte |
|---|---|---|
| Moniteurs | `ceph mon stat` · `ceph quorum_status -f json-pretty` | un MON hors quorum ; **moins de 2 sur 3** : plus aucune commande ne répond |
| Gestionnaires | `ceph mgr stat` | pas de mgr actif : `ceph orch`, le tableau de bord et les métriques ne répondent plus (les données restent servies) |
| OSD | `ceph osd tree` · `ceph osd df tree` · `ceph osd stat` | un OSD `down` ; un OSD `out` ; un OSD > 85 % (`nearfull`) |
| PG | `ceph pg stat` · `ceph pg dump_stuck` · `ceph pg ls degraded` | `active+clean` partout = sain ; `degraded`, `undersized` (copies manquantes), `peering`, `inactive` (bloquant !) |
| Pools | `ceph df` · `ceph osd pool ls detail` | `MAX AVAIL` qui fond ; `size`/`min_size` ; quota |
| Démons (cephadm) | `ceph orch ps` · `ceph orch ls` · `ceph orch host ls` | démon `stopped`/`error` ; hôte `offline` |
| Drapeaux | `ceph osd dump \| grep flags` | `noout`, `norebalance`, `pause`… posés et oubliés |

## 3. Lire un état de PG

`active` : les E/S passent · `clean` : toutes les copies sont là et à jour ·
`degraded` : des objets ont moins de copies que `size` · `undersized` : le PG a moins d'OSD que
`size` · `peering` : les OSD se mettent d'accord (transitoire) · `recovering`/`backfilling` :
recopie en cours · `remapped` : données en route vers d'autres OSD · `inactive`/`incomplete`/`down` :
**plus d'E/S** sur ce PG → incident majeur.

## 4. Les gestes sûrs (et seulement ceux-là sans l'équipe)

- Maintenance courte d'un nœud (redémarrage) : `ceph osd set noout` **avant**, `ceph osd unset noout`
  **après** que tous les OSD du nœud sont revenus. `noout` empêche Ceph de recopier les données
  d'un OSD absent ; oublié, il empêche aussi de les recopier lors d'une **vraie** panne.
- Redémarrer un démon : `ceph orch daemon restart <démon>` (ex. `osd.4`).
- Acquitter un plantage déjà analysé : `ceph crash archive <id>`.
- Faire taire une alerte comprise et suivie (avec une durée !) : `ceph health mute <CODE> 4h`.

## 5. Ce qu'on note dans le ticket

Sortie de `ceph -s` et de `ceph health detail` **au début**, heure, ce qui a été fait (commande
exacte), sortie de `ceph -s` **à la fin**.

## Références

- Surveillance d'un cluster : <https://docs.ceph.com/en/tentacle/rados/operations/monitoring/>
- États des PG : <https://docs.ceph.com/en/tentacle/rados/operations/pg-states/>
- Codes de santé : <https://docs.ceph.com/en/tentacle/rados/operations/health-checks/>
