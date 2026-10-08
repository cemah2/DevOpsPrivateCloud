# CHG-1005 — QDevice du cluster hv-par1 sur pbs01

| Champ | Valeur |
|---|---|
| Demandeur | Claire Morel (PLAT-1005) |
| Exécutant | `<MOI>` |
| Date prévue | `<AAAA-MM-JJ>`, hors fenêtre de sauvegarde nocturne de `pbs01` |
| Catégorie | Normal (touche un hôte du socle hors lab : `pbs01`, et la matrice des flux) |
| Systèmes touchés | `pbs01` (paquet, service, pare-feu, `authorized_keys` de root le temps de l'installation), `gw01`/`gw02` (matrice des flux), cluster `hv-par1` |

## Objet

Donner un troisième vote au cluster `hv-par1` (deux nœuds) : `corosync-qnetd` sur `pbs01` (site PAR2), `corosync-qdevice` sur `hv01` et `hv02`.

## Risques

| Risque | Parade |
|---|---|
| Règle nftables de `pbs01` fautive : perte des sauvegardes ou de l'accès SSH | `nft -c -f` avant chargement ; copie de `/etc/nftables.conf` ; session SSH ouverte pendant le chargement ; retour : recopie et `nft -f` |
| Service supplémentaire sur le serveur de sauvegarde | `corosync-qnetd` n'écoute que le port 5403 ; filtré par source ; supervision (M09-E25) |
| Clé SSH de `hv01` laissée sur `pbs01` | retirée en fin de changement (étape 7), vérifiée |
| Paquets en conflit avec PBS | `apt install --simulate` lu avant installation ; un seul paquet et ses dépendances (`corosync-qnetd`, `libnss3-tools`…) |

## Étapes

1. Instantané : sans objet (`pbs01` est physique) ; sauvegarde de `/etc/nftables.conf` et de `/root/.ssh/authorized_keys` sur `pbs01`.
2. `gw01`/`gw02` : MR sur `pare_feu.yml` (règle 5403 explicite ; écart « règle du bastion sans source » inscrit au registre), pipeline.
3. `pbs01` : `apt install --simulate corosync-qnetd`, lecture, installation ; `systemctl status corosync-qnetd`.
4. `pbs01` : règle d'entrée 5403 depuis 10.10.10.51-53, `nft -c -f`, chargement.
5. `hv01`, `hv02` : `apt install corosync-qdevice`.
6. Clé publique de root de `hv01` ajoutée temporairement à `/root/.ssh/authorized_keys` de `pbs01` ; `pvecm qdevice setup 10.20.10.10` sur `hv01`.
7. Retrait de la clé de `hv01` (et de toute clé de nœud ajoutée par la commande) sur `pbs01`.
8. Vérifications : `pvecm status` (Qdevice, 3 votes), `corosync-qnetd-tool -l` sur `pbs01`, sauvegarde de test vers `pbs01` toujours fonctionnelle.

## Retour arrière

`pvecm qdevice remove` sur un nœud ; sur `pbs01` : `systemctl disable --now corosync-qnetd`, `apt purge corosync-qnetd`, recopie de `/etc/nftables.conf` sauvegardé et `nft -f /etc/nftables.conf`, recopie de `authorized_keys` ; MR inverse sur `pare_feu.yml`.

## Vérification après changement

- [ ] `pvecm status` : `Flags: Quorate Qdevice`, `Total votes: 3`.
- [ ] Arrêt de `hv02` : `hv01` reste quorate (2 votes sur 3).
- [ ] Sauvegarde PBS de test réussie (le serveur de sauvegarde n'a pas été dégradé).
- [ ] Aucune clé de nœud dans `/root/.ssh/authorized_keys` de `pbs01`.
