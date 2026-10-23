**Points non testés en conditions réelles (M25-E39)** — signale tes retours, ils corrigent le workbook :
- **Vérifié dans le code d'OpenBao** (tag v2.4.1, `physical/raft/raft.go`, `vault/ha.go`, `http/handler.go`) et la documentation : récupération par `<chemin de données>/raft/peers.json` (lecture à l'ouverture du stockage Raft, journal `raft recovery initiated` / `found new config` / `deleted peers.json`, fichier supprimé ensuite) ; un nœud en attente lit l'actif dans le verrou HA de **sa copie locale** de l'état Raft (`RaftLock.Value`, « TODO: how to tell if held? ») ; une requête transmise sans actif connu répond 500 `local node not active but active cluster node not found`.
- **Non joué sur une grappe** : le script de panne (`bash -n` et `shellcheck -x` propres, syntaxe de la table nftables validée par `nft -c`) ; le délai exact de perte de l'actif (attendu : quelques secondes, bail du leader Raft multiplié par `performance_multiplier`, 5 par défaut) ; le texte exact des lignes de la bibliothèque Raft dans `journalctl` (cités d'après hashicorp/raft : `failed to contact quorum of nodes, stepping down`, `entering candidate state`, `failed to make requestVote RPC`) ; ce que renvoie `sys/leader` sur chaque nœud pendant la panne (attendu : l'ancien actif sur les nœuds en attente, peut-être vide) ; le code de `sys/health` de l'ancien actif après sa perte de direction (attendu : 429).

---

### M25-E39 — Panne : la grappe n'a plus de leader

**Démarche de diagnostic**

*Symptômes* : VIP muette (connexion impossible : keepalived l'a retirée, aucun nœud ne passe son script de suivi), `OpenBaoSansLeader` puis, selon la variante, `OpenBaoScelle` pour les nœuds dont le processus est arrêté (`up == 0`). Consommateurs en échec : CI, ESO, baux de MédiAgenda qui ne se renouvellent plus.

*Hypothèses* : (a) nœuds **scellés** (seal `transit`, `kms01`) ; (b) nœuds **arrêtés** ; (c) nœuds vivants mais qui ne **se parlent** plus sur le 8201 (pare-feu, réseau, certificat de grappe) ; (d) **configuration Raft** amputée (pair retiré) ; (e) un actif élu mais qui ne prend pas le verrou (audit, montage, horloge) ; (f) seulement la **VIP** (keepalived) alors qu'un nœud répond 200.

**Étape 1 — Constater, sans jeton et sans rien changer**

```
admin@adm01:~$ ~/src/secrets/outils/etat-grappe.sh
NŒUD     CODE  SCELLÉ  LEADER (vu par le nœud)
vault01  429   false   vault01.par1.medisphere.internal self=false
vault02  000   ?       -
vault03  000   ?       -
openbao  000   ?       -
```

([`outils/etat-grappe.sh`](fichiers/M25-E39/outils/etat-grappe.sh), lecture seule, à ranger dans `plateforme/secrets/outils/`.) Aucun 200 : il n'y a **pas d'actif**. Aucun 503 : ce n'est **pas** le seal ; `kms01` répond 200 : on ne le touche pas. L'hypothèse (f) tombe (aucun nœud à 200, la VIP a raison de ne pas exister).

```
admin@adm01:~$ BAO_ADDR=https://vault01.par1.medisphere.internal:8200 bao operator raft list-peers
Error reading the raft cluster configuration: Error making API request.
Code: 500. Errors:
* local node not active but active cluster node not found
```

`list-peers`, `autopilot state`, la lecture d'un secret : tout ce qu'un nœud en attente ne sait pas servir est **transmis** à l'actif, et il n'y en a pas. `sys/leader` d'un nœud en attente lit le verrou d'actif dans **sa** copie de l'état Raft, qui n'a plus pu être mise à jour depuis la perte de majorité : il peut encore désigner l'ancien actif (ici `vault01` lui-même, avec `self=false`). Ne jamais conclure sur ce seul champ.

**Étape 2 — Les nœuds** (SSH `admin`, consultation)

```
admin@vault02:~$ systemctl status openbao --no-pager | head -n 4
admin@vault01:~$ sudo journalctl -u openbao --since "today 00:00" --no-pager | grep -Ei 'raft|quorum|election|candidate|leader|active' | tail -n 30
admin@vault01:~$ sudo nft list ruleset
admin@vault01:~$ sudo ss -tlnp 'sport = :8201'
admin@vault01:~$ for p in vault02 vault03; do timeout 3 bash -c "</dev/tcp/$p.par1.medisphere.internal/8201" && echo "$p ouvert" || echo "$p KO"; done
```

Ce qu'on lit sur l'ancien actif : `failed to contact quorum of nodes, stepping down`, puis des élections en boucle (`entering candidate state`, `failed to make requestVote RPC`) avec, pour chaque pair, la **raison** réseau :
- `connect: connection refused` : la machine répond mais rien n'écoute sur 8201 → **service arrêté** (à confirmer par `systemctl status` : `inactive (dead)`, `Stopped openbao.service` à l'heure de la maintenance, aucune erreur : arrêt volontaire) ;
- `i/o timeout` : rien ne revient → **filtrage** (ou réseau) ; sur le nœud concerné, `nft list ruleset` montre une seconde table, hors du rôle :

```
table inet maintenance {
	chain entree {
		type filter hook input priority -10; policy accept;
		tcp dport 8201 drop
		tcp sport 8201 drop
	}
}
```

Priorité `-10` : elle passe **avant** `filtre_local`, et un `drop` dans n'importe quelle chaîne de base est définitif — l'`accept` de `filtre_local` pour 8200-8201 n'y peut rien. Les deux règles coupent les deux sens : `dport 8201` refuse les connexions reçues, `sport 8201` jette les **réponses** aux connexions que le nœud ouvre lui-même vers le 8201 des autres. Le nœud est seul au monde sur le port de grappe, alors que 8200, SSH et VRRP passent.

**Étape 3 — Raisonner** (dans le journal, avant le premier geste)

Raft n'élit un leader qu'avec la **majorité des électeurs** de la configuration : ⌊3/2⌋ + 1 = 2. Une écriture n'est validée que lorsqu'elle est dans le journal d'une majorité : c'est pour cela qu'**aucune écriture acceptée n'a pu être perdue** — pendant la panne, aucune n'a été acceptée. Un nœud seul, même descellé et parfaitement à jour, ne peut ni être élu, ni rester leader (il renonce dès qu'il ne joint plus la majorité pendant son bail), donc ne peut pas prendre le verrou d'actif d'OpenBao, qui est lui-même stocké dans Raft. Il répond 429 (« en attente »), mais personne ne l'attend.

Ce qu'il faut donc : **deux** électeurs vivants qui se parlent sur 8201. Le geste le plus sûr est celui qui **rend** à la grappe un nœud tel qu'il était, sans toucher aux données ni à la configuration Raft.

**Variante 1 — deux services arrêtés.** Les deux nœuds en attente ont été arrêtés l'un après l'autre (le premier arrêt passe inaperçu : tolérance 0, alerte `OpenBaoToleranceNulle` au bout de 10 min… si l'actif l'a émise avant de tomber à son tour). Correctif, un nœud à la fois :

```
admin@vault02:~$ sudo systemctl start openbao
admin@adm01:~$ ~/src/secrets/outils/etat-grappe.sh      # vault02 429 descellé (seal transit), puis vault01 ou vault02 à 200, VIP 200
admin@vault03:~$ sudo systemctl start openbao
admin@adm01:~$ bao operator raft autopilot state | grep -Ei 'healthy|tolerance'
```

Après le premier `start`, `vault02` se descelle seul par `kms01`, rejoint la configuration Raft qu'il connaît déjà, et l'élection aboutit en quelques secondes : le **service** revient. La **marge** ne revient qu'avec `vault03`. Vérifie `systemctl is-enabled openbao` : un service seulement arrêté redémarre au prochain démarrage de la VM ; un service désactivé, non.

**Variante 2 — 8201 filtré sur deux nœuds.** Tous les processus tournent, tous descellés, aucun service arrêté, et pourtant aucun actif : chaque nœud est isolé (les deux filtrés n'échangent avec personne ; le troisième ne joint qu'eux). Journaux : uniquement des `i/o timeout`. Correctif sur un nœud, puis l'autre :

```
admin@vault02:~$ sudo nft list table inet maintenance        # preuve pour le journal
admin@vault02:~$ sudo nft delete table inet maintenance
```

Puis rejoue le rôle pour être sûr que l'état des nœuds est celui de Git :

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/coffre.yml --check --diff
```

`--check` sans différence attendu : la table parasite était **à côté** de `filtre_local`, qu'elle ne modifiait pas, et le rôle ne compare que son fichier `/etc/nftables.conf`. Elle aurait disparu au prochain rechargement de ce fichier (`flush ruleset` en tête) ou au redémarrage du nœud : un filtrage à la main n'a ni trace dans Git ni durée de vie prévisible.

**Variante 3 — un arrêté, un isolé.** Le piège : `systemctl start openbao` sur le nœud arrêté **rend le service** (deux électeurs joignables) et la VIP revient ; beaucoup s'arrêtent là. `autopilot state` dit pourtant `Healthy: false`, `Failure Tolerance: 0`, et le troisième nœud a un dernier contact de plusieurs heures. On cherche alors **pourquoi** il est vivant mais absent : `i/o timeout` dans les journaux, table `inet maintenance`. On la retire ; le nœud rattrape par Raft (journaux ou instantané envoyé par le leader) en quelques secondes ; tolérance 1.

**Clôture commune** : trois nœuds descellés, un actif, deux en attente, VIP sur l'actif ; `list-peers` montre toujours les **trois** électeurs ; écriture et lecture par la VIP :

```
admin@adm01:~$ bao kv put -mount=kv wb-essais/inc-5239 etat=ok && bao kv get -mount=kv -field=etat wb-essais/inc-5239
admin@adm01:~$ kubectl -n wb-essais annotate externalsecret premier-secret force-sync="$(date +%s)" --overwrite
```

Puis un pipeline relancé, `lab/bin/check 25 39`, `lab/bin/break 25 39 --annuler` (idempotent, ne fait rien si tout est réparé), journal ([modèle](fichiers/M25-E39/medisphere/docs/socle/journal/AAAA-MM-JJ-INC-5239.md)).

*Les alertes.* `OpenBaoSansLeader` a sonné au bon moment (`absent(vault_core_active…)` couvre aussi le cas où aucun nœud n'émet). `OpenBaoScelle` a sonné pour les nœuds **arrêtés** (`up == 0`), pas pour les nœuds isolés (vivants, descellés) : en variante 2, seule `OpenBaoSansLeader` parle. `OpenBaoToleranceNulle` reste **muette** pendant la panne : `vault_autopilot_*` n'est émis que par l'actif, et il n'y en a plus ; elle aurait pu sonner **avant**, entre les deux gestes de Lucas, si l'écart avait duré plus de ses 10 minutes de `for`.

**Étape 4 — Pourquoi ne pas « réparer plus fort »**

- `bao operator raft remove-peer vault02` : sans actif, la commande échoue (elle est transmise) ; avec un actif retrouvé, elle retire un électeur sain qui ne pourra plus voter à son retour — la grappe passe à deux électeurs, quorum de **deux sur deux**, plus aucune tolérance. Autopilot ne l'aurait jamais fait (`min_quorum = 3`) : c'est voulu.
- `bao operator init`, effacer `/var/lib/openbao` d'un nœud « pour qu'il rejoigne propre » : on détruit une copie saine des données pour un problème qui n'en a perdu aucune ; effacer **deux** nœuds sans quorum perd tout ce que le troisième n'avait pas.
- Restaurer un instantané : retour arrière jusqu'à une heure d'écritures (baux, rotations, émissions PKI), pour une panne qui se réparait par un `start`.
- Redémarrer le survivant ou `kms01` : le premier ne trouvera pas plus de majorité ; le second reviendrait **scellé** (trois dépositaires), et plus aucun nœud ne pourrait se desceller.

**Étape 5 — Le dernier recours : `peers.json`** (question 6)

Légitime seulement si la majorité est **définitivement** perdue (ici : `vault02` et `vault03` détruits sans sauvegarde utilisable). Différence avec aujourd'hui : aujourd'hui, les pairs absents pouvaient **revenir** ; un `peers.json` écrit alors qu'ils peuvent revenir crée deux grappes qui divergent.

1. Arrêter openbao sur tous les nœuds restants (ici `vault01`).
2. Sur chacun d'eux, `/var/lib/openbao/raft/peers.json` (propriétaire `openbao`, 0600), **identique** partout, ne listant que les survivants ; `id` = identifiant Raft du nœud (`node_id` de la configuration, ou fichier `node-id` du dossier de données), `address` = nom et **port de grappe** :
   ```json
   [
     { "id": "vault01", "address": "vault01.par1.medisphere.internal:8201", "non_voter": false }
   ]
   ```
3. Démarrer : à l'ouverture du stockage Raft, OpenBao lit le fichier, remplace la configuration de grappe (`raft recovery initiated`, `raft recovery found new config`), **supprime** le fichier (`raft recovery deleted peers.json`), se descelle par `kms01`, s'élit seul et prend le verrou d'actif.
4. `list-peers` (un pair), lecture d'un secret ; puis reconstruire `vault02` et `vault03` **vides** (OpenTofu, rôle `openbao`) : `retry_join` les fait rejoindre, ils rattrapent par Raft ; autopilot les rend électeurs après 10 s de stabilité.
5. Risques, dans le post-mortem : les écritures que `vault01` n'avait pas reçues sont perdues ; la récupération **valide d'office** les entrées de son journal Raft qui ne l'étaient pas (une écriture qui avait échoué côté client peut réapparaître). Décision avec Karim, instantané vérifié d'abord, jamais automatisé, jamais seul la nuit.

**Prévention**
- [Fiche « maintenance de la grappe »](fichiers/M25-E39/medisphere/docs/securite/secrets/maintenance-grappe.md) : `autopilot state` sain et tolérance ≥ 1 **avant chaque** geste sur un nœud, un nœud à la fois, en attente d'abord, l'actif après `step-down` ; gestes interdits ; `peers.json` en dernier recours. Elle sera reprise dans RB-255 § 4 (M25-E43).
- Aucun filtrage à la main sur un nœud du coffre : tout passe par `pare_feu_local` (Git, MR, matrice des flux).
- Lire `OpenBaoToleranceNulle` comme un **arrêt de maintenance** ; la planifier dans la fenêtre de maintenance avec le canal de l'astreinte.

**Explications**

OpenBao confie à Raft deux choses : les **données** (chiffrées par la barrière) et le **verrou d'actif** (clé `core/lock`). Raft élit un leader à la majorité des électeurs et ne valide une écriture qu'une fois répliquée sur une majorité ; un leader qui ne joint plus la majorité pendant la durée de son bail (`LeaderLeaseTimeout`, multiplié par `performance_multiplier`) **renonce** de lui-même, précisément pour qu'une partition ne laisse pas deux leaders écrire chacun de son côté. Le nœud actif d'OpenBao perd alors son verrou, repasse en attente, et la grappe ne sert plus rien, lectures comprises : un nœud en attente ne sert pas de lecture lui-même dans OpenBao (les *performance standby* sont une fonction de Vault Enterprise), il transmet. C'est le prix de la cohérence : le coffre préfère se taire que répondre une valeur périmée ou accepter une écriture qui pourrait disparaître. Les données, elles, sont intactes sur chaque nœud : dès que deux électeurs se reparlent, l'élection reprend, le nouveau leader confirme son journal, le nœud actif reprend le verrou et reconstruit son état (montages, baux).

**Alternatives**
- Diagnostiquer par la métrique (`vault_raft_*`, `up`, `vault_core_active` dans Grafana) plutôt que par les nœuds : utile pour la chronologie, mais muet sur la **cause** (un processus arrêté et un nœud isolé se ressemblent dans les métriques de grappe).
- Cinq électeurs : tolérance de deux pannes, mais sur un seul hyperviseur, le domaine de panne reste `pve01` (M25-E24, corrigé) ; plus de mémoire, écritures un peu plus lentes.
- Un nœud non électeur supplémentaire : copie des données, aucune voix ; il ne sauve pas le quorum.

**Pièges classiques**
- Croire `sys/leader` d'un nœud en attente et chercher la panne sur l'« actif » qu'il désigne.
- Redémarrer le survivant (ou les trois) en série : rien ne change, et chaque redémarrage dépend de `kms01`.
- Rendre le service et oublier la marge (variante 3) : la grappe reste à tolérance 0 jusqu'au prochain geste de maintenance.
- `remove-peer` « pour que les deux qui restent fassent une majorité » : fausse bonne idée (étape 4).
- Retirer la table parasite sur un nœud et oublier de chercher la même chose sur les deux autres.
- Écrire `peers.json` alors que les pairs absents sont seulement arrêtés : deux grappes divergentes à leur retour.

**En production chez MédiSphère**

Maintenance des nœuds du coffre dans une fenêtre annoncée, un nœud à la fois, avec la vérification d'autopilot avant chaque geste et la fiche ouverte ; aucun `nft` à la main sur un nœud du coffre ; `OpenBaoToleranceNulle` routée à l'astreinte comme un « ne touche plus à rien » ; la procédure `peers.json` répétée **sur une grappe jetable** (comme la restauration de RB-252), jamais découverte un jour de panne.
