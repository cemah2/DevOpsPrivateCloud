### M25-E39 — Panne : la grappe n'a plus de leader  `BF` `★★★`

> **Ticket INC-5239** — *De : Nadia Roussel* — *Copie : Karim Benali*
> 6 h 52 : l'alerte `OpenBaoSansLeader` a sonné. Depuis, plus rien ne passe par `openbao.par1.medisphere.internal` : les pipelines échouent sur `bao kv get`, ESO met ses `ExternalSecret` en erreur, et MédiAgenda recette n'aura plus d'identifiants de base dans moins d'une heure. Lucas a fait cette nuit la maintenance des nœuds du coffre ; il est en congé jusqu'à lundi et ne répond pas. Remets le coffre en route **sans rien perdre**, puis explique-moi ce qui s'est passé. *(Le détail s'affiche à l'injection.)*

**Objectifs pédagogiques**
- Comprendre le **quorum** d'une grappe Raft (majorité des électeurs : 2 sur 3) et pourquoi un nœud vivant, descellé et à jour ne sert **rien** quand il est seul.
- Diagnostiquer un coffre sans nœud actif **sans** la CLI habituelle : codes de `sys/health` nœud par nœud, `sys/leader`, journaux d'élection, état des services, pare-feu local, flux du port de grappe 8201 testés **entre** nœuds.
- Distinguer dans les journaux un pair **arrêté** d'un pair **injoignable** (connexion refusée contre délai dépassé).
- Rétablir le quorum par le geste le **moins** risqué, un geste à la fois, puis rétablir la **marge** ; savoir ce qu'on ne fait **pas** (retrait de pair, réinitialisation, restauration) et quand la procédure de récupération par `peers.json` devient légitime.

**Prérequis** : M25-E24 (grappe, VIP, autopilot), M25-E25 (seal `transit`, RB-251), M25-E26 (instantanés horaires), M25-E27 (alertes du coffre) ; `lab/bin/check 25 24` vert avant l'injection.
**Durée indicative** : 60 min (temps cible).

**Contexte technique**
- Grappe : `vault01` (10.10.20.21), `vault02` (.22), `vault03` (.23), stockage Raft dans `/var/lib/openbao`, API 8200, **grappe 8201** (Raft et transfert de requêtes, TLS interne), trois électeurs ; VIP 10.10.20.200 portée par keepalived sur le **seul** nœud qui répond 200 à `sys/health`. Auto-descellement par `kms01` (10.10.20.24). Autopilot : `cleanup_dead_servers = true`, `min_quorum = 3`.
- Pare-feu local des nœuds : table `inet filtre_local` produite par le rôle `pare_feu_local` (M06-E30, flux du coffre au M25-E24) ; le 8201 n'y est ouvert qu'**entre** les trois nœuds : il ne se teste pas depuis `adm01`.
- La panne ne touche **ni** les données Raft, **ni** la configuration Raft, **ni** `kms01`, ni les VMs (elles restent allumées). Avant d'agir, le script vérifie que la grappe est saine, qu'un instantané de moins de 2 h existe et que les nœuds qu'il arrête sauront se desceller seuls.
- Documentation à garder ouverte : [stockage intégré et quorum](https://openbao.org/docs/concepts/integrated-storage/), [`bao operator raft`](https://openbao.org/docs/commands/operator/raft/), [`/sys/health`](https://openbao.org/api-docs/system/health/), [`/sys/leader`](https://openbao.org/api-docs/system/leader/), RB-251, ton `grappe.md` (M25-E24).

> ⚠️ **Attention** : ici, chaque geste de trop peut coûter des données ou des heures. **Ne fais jamais**, pendant cet exercice : `bao operator raft remove-peer`, `bao operator init`, effacement ou déplacement de quoi que ce soit sous `/var/lib/openbao`, restauration d'un instantané, redémarrage ou scellement de `kms01`, arrêt d'un nœud qui tourne. Ne crée pas de fichier `peers.json` : la question 6 le **décrit**, elle ne le fait pas exécuter. Retour arrière à tout moment : `lab/bin/break 25 39 --annuler` (relance les services, retire le filtrage, attend une grappe saine).

**Injection** : `lab/bin/break 25 39` (3 variantes ; compte 1 à 3 minutes : le script attend la perte effective du leader).

**Travail demandé**
1. **Constate sans rien changer.** Pour chaque nœud (adresse propre, pas la VIP) : code de `sys/health`, `seal-status`, réponse de `sys/leader`. Puis essaie `bao operator raft list-peers` et `bao operator raft autopilot state` (avec `BAO_ADDR` sur un nœud). Note les erreurs exactes et explique-les : pourquoi un nœud **descellé** ne sait-il plus répondre ? Que vaut `leader_address` sur chaque nœud, et peux-tu t'y fier ? Où est passée la VIP ? Note l'heure : c'est le T0 de ton journal.
2. **Lis les nœuds.** Sur chacun : état du service `openbao` depuis quand et pourquoi, journal d'`openbao` depuis le début de la nuit (élections, candidats, erreurs vers les pairs), règles nftables **complètes**, écoute du 8201. Teste le flux 8201 d'un nœud vers chacun des deux autres. Range chaque pair dans une case : *vivant et joignable*, *arrêté*, *vivant mais injoignable*.
3. **Raisonne avant d'agir.** Combien de nœuds faut-il pour élire un leader ? Lesquels peux-tu rendre à la grappe, par quel geste, avec quel risque ? Écris l'ordre de tes gestes dans ton journal **avant** le premier. Explique aussi pourquoi aucune écriture n'a pu être perdue pendant la panne.
4. **Rétablis le quorum**, un geste à la fois, en observant entre deux gestes (`sys/health` des trois nœuds, VIP). Un geste sur un nœud passe par ce qu'il est (service, pare-feu) : avant de retirer un filtrage, établis s'il vient du rôle `pare_feu_local` (compare la règle active avec `/etc/nftables.conf` et avec Git) ou d'ailleurs : on ne défait pas à la main ce que Git a voulu.
5. **Rétablis la marge.** Le service rendu ne suffit pas : `autopilot state` doit être sain avec une tolérance d'au moins une panne, chaque serveur sain. Vérifie une écriture et une lecture par la VIP (`kv/wb-essais/…`), relance un pipeline et force le rafraîchissement d'un `ExternalSecret`.
6. **Dernier recours, sur le papier.** Supposons que `vault02` et `vault03` aient été **détruits** (disques perdus, pas de sauvegarde utilisable). Décris, d'après la documentation d'OpenBao (et ce qu'elle hérite de Vault), comment remettre `vault01` seul en service : quel fichier, où, avec quel contenu (identifiants et adresses de **ta** grappe), dans quel état doivent être les nœuds, ce que le serveur fait du fichier, ce qu'on risque de perdre, et ce qui distingue cette situation de celle d'aujourd'hui.
7. **Préviens.** Une fiche « maintenance de la grappe » dans `docs/securite/secrets/` : la vérification à faire avant **chaque** geste sur un nœud, l'ordre des nœuds, ce qu'on ne fait jamais, la procédure de la question 6 en dernier recours. Dis si les alertes du M25-E27 ont sonné au bon moment (et lesquelles sont restées muettes, et pourquoi).

**Critères de réussite**
- [ ] Les trois nœuds répondent, descellés ; un seul actif (200), deux en attente (429) ; `sys/leader` lu par la VIP désigne le nœud qui la porte.
- [ ] `vault01`, `vault02` et `vault03` sont toujours les trois pairs Raft, tous électeurs, avec un leader ; autopilot sain, tolérance d'au moins une panne, chaque serveur sain.
- [ ] `openbao` est actif et activé au démarrage sur les trois nœuds ; plus aucune règle nftables ne bloque le port 8201.
- [ ] Ton journal de diagnostic (un fichier dont le nom contient `INC-5239`, dans `docs/socle/journal/` de `plateforme/medisphere`) donne la chronologie de la panne lue dans les journaux des nœuds, la cause par nœud, tes gestes dans l'ordre et la réponse à la question 6.

**Vérification** : `lab/bin/check 25 39`

<details><summary>Indice 1</summary>

`sys/health` ne dépend pas d'un actif : chaque nœud répond pour lui-même (lis la page de l'API pour la signification de 200, 429, 503 et des paramètres qui changent ces codes). En revanche, presque tout le reste, `list-peers` et `autopilot state` compris, est **transmis** à l'actif par un nœud en attente. Et `sys/leader` d'un nœud en attente lit une information que ce nœud garde **localement** : demande-toi si elle a pu être mise à jour depuis que la grappe a perdu sa majorité.
</details>

<details><summary>Indice 2</summary>

Dans `journalctl -u openbao`, cherche les lignes de la bibliothèque Raft : passage en candidat, élection relancée, échec des demandes de vote vers chaque pair, et sur l'ancien leader le moment où il renonce faute de majorité. L'erreur réseau qui suit chaque échec dit **pourquoi** le pair ne répond pas : une connexion refusée (rien n'écoute sur ce port) n'a pas la même cause qu'un délai dépassé (rien ne revient). Pour le second cas, `nft list ruleset` en entier : le rôle `pare_feu_local` ne produit qu'une table.
</details>

<details><summary>Indice 3</summary>

Pour élire un leader, il faut deux électeurs **vivants qui se parlent** sur le 8201. Le geste le plus sûr est celui qui ne fait que **rendre** à la grappe ce qu'elle avait : un service relancé (il se descelle seul par `kms01`) ou un filtrage parasite retiré. Après le premier geste, regarde `autopilot state` : si le service revient avec une tolérance de 0, il te reste un nœud à rendre. Pour la question 6, cherche « *lost quorum* » et « *peers.json* » dans la documentation du stockage Raft (celle de Vault détaille le format ; vérifie l'emplacement attendu par OpenBao).
</details>

**Pour aller plus loin** (facultatif) : mesure, sur la grappe saine et par la boucle d'écriture du M25-E24, le temps entre le retour du deuxième électeur et la première écriture réussie par la VIP ; décompose-le (élection Raft, prise du verrou d'actif, script de keepalived). Lis la page [*Integrated storage*](https://openbao.org/docs/concepts/integrated-storage/) sur les non-électeurs et l'option `performance_multiplier` du [stockage Raft](https://openbao.org/docs/configuration/storage/raft/) : qu'est-ce que changerait une grappe de **cinq** électeurs, ici, sur un seul hyperviseur ?
