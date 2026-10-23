# Maintenance de la grappe OpenBao et perte de quorum

> Projet `plateforme/medisphere`, `docs/securite/secrets/maintenance-grappe.md` — M25-E39 (INC-5239).
> Complète RB-251 (descellement, redémarrage) ; sera repris dans RB-255 § 4 (coffre fermé, M25-E43).

## Règle d'or

Trois électeurs, quorum de **deux**. La grappe tolère **une** absence ; la deuxième arrête tout, lectures
comprises. Avant **chaque** geste qui retire un nœud (arrêt, redémarrage, mise à jour, essai de
pare-feu, migration de VM) :

```
admin@adm01:~$ bao operator raft autopilot state | grep -Ei 'healthy|tolerance'
```

On ne touche à un nœud que si `Healthy` vaut `true` **et** `Failure Tolerance` vaut au moins 1. Après le
geste, on attend le retour de ces deux valeurs avant le nœud suivant. Les nœuds en attente d'abord,
l'actif en dernier, après `bao operator step-down` (RB-253).

Tout filtrage réseau d'un nœud passe par le rôle `pare_feu_local` (Git, MR) : jamais de `nft` à la main
sur un nœud du coffre.

## Plus de leader : reconnaître

- La VIP ne répond plus ; aucun nœud ne répond 200 à `sys/health` ; `bao operator raft list-peers` et
  `autopilot state` échouent (`local node not active but active cluster node not found`) : ils sont
  transmis à un actif qui n'existe pas.
- `sys/leader` d'un nœud en attente peut encore citer l'**ancien** actif (copie locale du verrou) :
  ne pas s'y fier seul.
- `outils/etat-grappe.sh` donne l'état sans jeton ; les journaux (`journalctl -u openbao`) disent le
  reste : élections répétées, `connection refused` (rien n'écoute : service arrêté) ou `i/o timeout`
  (rien ne revient : filtrage, réseau, VM figée) vers le 8201 des autres.

## Rétablir (dans l'ordre)

1. **Compter les vivants** : processus lancé et descellé sur chaque nœud (`systemctl status openbao`,
   `seal-status`). `kms01` descellé (sinon RB-255 § 6, on ne le redémarre pas).
2. **Rendre la majorité** par le geste le plus simple et le moins risqué : relancer le service d'un nœud
   arrêté (il se descelle seul), ou lever le filtrage d'un nœud isolé. **Un** geste, puis observer :
   un leader est élu en quelques secondes, la VIP revient.
3. **Rendre la marge** : le troisième nœud aussi ; `autopilot state` sain, tolérance 1.
4. **Vérifier** : un actif, deux en attente, VIP sur l'actif, une écriture et une lecture par la VIP,
   pipelines et ExternalSecret relancés.

## Ce qu'on ne fait pas

- `bao operator raft remove-peer` sur un nœud « qui ne répond pas » : sans actif, la commande échoue de
  toute façon ; avec un actif, elle retire un électeur qui reviendra… et ne pourra plus voter.
- Effacer `/var/lib/openbao`, relancer `bao operator init`, restaurer un instantané sur la production :
  on perd des données pour un problème qui n'en a pas perdu.
- Redémarrer le nœud survivant « pour voir » : il ne trouvera pas plus de majorité, et il lui faut
  `kms01` pour se desceller.
- Toucher `kms01`.

## Dernier recours : `peers.json` (perte définitive de la majorité)

**Quand** : deux nœuds **détruits** sans retour possible (disques perdus, VM supprimées sans
sauvegarde utilisable), et le survivant a des données saines. Pas pour une panne qu'un redémarrage ou
un flux rouvert réparent. Décision avec Karim, instantané récent vérifié (RB-252), écrite dans le
ticket.

1. Arrêter openbao sur **tous** les nœuds encore présents (ici le survivant).
2. Sur le survivant, écrire `/var/lib/openbao/raft/peers.json` (propriétaire `openbao`, 0600), avec
   la liste des pairs à **garder** — `id` = `node_id` du stockage Raft, `address` = adresse de grappe :
   ```json
   [
     { "id": "vault01", "address": "vault01.par1.medisphere.internal:8201", "non_voter": false }
   ]
   ```
3. Démarrer openbao : à l'ouverture du stockage Raft, le nœud lit le fichier, **réécrit** sa
   configuration de grappe (`raft recovery initiated`, `raft recovery found new config`), supprime le
   fichier (`raft recovery deleted peers.json`), se descelle (seal transit) et s'élit seul.
4. Vérifier `list-peers` (un seul pair), lire un secret ; puis reconstruire `vault02` et `vault03`
   **vides** (VM neuves, rôle `openbao`) : ils rejoignent par `retry_join` et rattrapent par Raft.
5. Ce qu'on risque : les écritures que le survivant n'avait pas reçues sont perdues, et la récupération
   **valide** d'office les entrées de journal Raft qu'il détenait sans qu'elles aient été validées
   (une écriture qui avait échoué côté client peut réapparaître). Le noter dans le post-mortem.

Ce qu'il ne faut pas faire : écrire `peers.json` sur un nœud alors que les autres tournent encore (deux
grappes divergentes), y laisser un pair qui ne reviendra pas (pas de majorité au redémarrage).
S'il reste **plusieurs** nœuds, chacun reçoit le **même** fichier, listant tous les survivants, et ils
redémarrent ensemble. L'`id` se lit dans le fichier `node-id` du dossier de données (ou `node_id` de la
configuration). Références : [*Integrated storage*, récupération manuelle par peers.json](https://openbao.org/docs/concepts/integrated-storage/),
code de `physical/raft/raft.go` d'OpenBao (lecture puis suppression de `<path>/raft/peers.json`),
tutoriel [*Lost quorum recovery*](https://developer.hashicorp.com/vault/tutorials/raft/raft-lost-quorum) de Vault, dont OpenBao hérite le mécanisme.
