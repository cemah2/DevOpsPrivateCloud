# Module 09 — Palier 4 : Expert

Le cluster `hv-par1` tourne : trois nœuds Proxmox VE 9.2, deux liens Corosync, Ceph hyperconvergé monté en Tentacle, HA avec règles d'affinité, réplication ZFS, sauvegardes vers `pbs01`, SDN, droits, pare-feu et supervision. Claire Morel a validé la recette du palier 3 avec une phrase que Nadia Roussel a épinglée dans le canal d'astreinte : « Un cluster, c'est une machine à transformer une panne simple en panne compliquée. Un serveur qui tombe, on sait faire. Un quorum perdu à 3 h du matin, un `/etc/pve` en lecture seule ou une VM HA en erreur, il faut l'avoir déjà vu. »

Karim Benali a donc préparé huit pannes, toutes inspirées d'incidents réels du forum Proxmox et des post-mortems d'InfoGér : quorum perdu, nœud qui ne revient pas, HA qui abandonne, migration impossible, VMs figées par Ceph, réplication en échec, sauvegarde nocturne ratée, configuration impossible à modifier. Une astreinte les combine. Puis tu descends sous le capot (pmxcfs, votequorum, gestionnaire HA, watchdog) et tu passes les questions d'entretien.

La méthode est celle des modules précédents : observer avant d'agir, formuler une hypothèse, la tester par la mesure la moins invasive, corriger à la racine, prévenir la récidive. Avec trois règles propres aux clusters :
- **Établis d'abord la vue du cluster, nœud par nœud.** Chaque nœud a sa propre vision de la membre (*membership*) et du quorum : `corosync-quorumtool -s`, `corosync-cfgtool -s` et `pvecm status` sur **chacun** des trois nœuds, avant toute conclusion. Une interface web te montre la vue d'**un** nœud, celui qui te sert la page.
- **Ne force jamais le quorum par réflexe.** `pvecm expected 1` rend `/etc/pve` inscriptible sur un nœud isolé : c'est un outil de dernier recours, qui peut créer exactement le *split-brain* que le quorum empêche. Tu ne l'emploies que sur une partition dont tu as prouvé qu'elle est la seule vivante, et tu notes pourquoi.
- **La HA et le stockage amplifient tout.** Un nœud sans quorum qui porte des ressources HA se clôture (*fencing*) en une minute ; un pool Ceph sous `min_size` fige toutes les VMs qui y écrivent. Avant chaque action, demande-toi ce que la HA et Ceph vont en faire.

> **Rappels** : tout se lance depuis `adm01`. Les nœuds se joignent en `root@10.10.10.51` à `53` (clé de `adm01` posée par le fichier de réponse de M09-E03, certificat d'hôte signé par step-ca) : une panne DNS ne te coupe pas d'eux. Projets : `~/src/ansible` (rôles `pve_noeud`, `pve_cluster`), `~/src/infra` (états `hv` et `hv-invites`), `~/src/outils` (sonde `ms-verif-cluster` de M09-E25), documentation `~/medisphere` (variable `WB_DEPOT`), runbooks RB-090 à RB-092. Tout correctif durable passe par le code (rôle Ansible, état OpenTofu) et une MR ; une réparation à chaud est permise pour rétablir le service, à condition d'être reportée ensuite dans le code.

## Règles du jeu des pannes (M09-E35 à M09-E43)

- Les pannes s'injectent **depuis `adm01`**, à la racine de ta copie du workbook :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ lab/bin/break 09 35
  ```
  Le script tire une variante au hasard et n'affiche que le **symptôme**, comme un ticket. Chaque panne a 3 ou 4 variantes : refais l'exercice jusqu'à les avoir toutes rencontrées (`--variante N` force une variante, sans dire laquelle est laquelle). Si une variante n'a pas d'effet sur ton lab (selon tes choix des paliers précédents), le script en essaie une autre. Certaines injections prennent plusieurs minutes (création de VMs de test, attente de l'état `error` de la HA, première réplication).
- **Avant d'injecter**, lance le contrôle de l'exercice (`lab/bin/check 09 35`) : il doit être vert, sauf les lignes « runbook » et « panne close » qui dépendent de l'exercice lui-même. Une panne posée sur un cluster déjà malade fausse tout le diagnostic. `ceph01-03` peuvent rester arrêtées : aucune panne ne les concerne.
- **Invités de test** : les VMID **191 à 197** du cluster sont réservés aux pannes (étiquette `pannes-m09`, VMs sans système, 256 Mio). Ne les utilise pas pour autre chose ; ils sont détruits à l'annulation.
- **HA gelée** : les pannes qui privent un nœud de quorum (M09-E35, une variante de M09-E36, deux de M09-E42) commencent par désarmer la pile HA (`ha-manager crm-command disarm-ha freeze`, nouveauté de Proxmox VE 9.2), sinon le nœud isolé se clôturerait au bout d'une minute et son redémarrage effacerait la panne. Ce désarmement est annoncé dans le symptôme ; ce n'est pas la cause. Il est levé par `--annuler`.
- **Ne lis pas** les scripts de `corrige/pannes/`, ni `/var/lib/workbook/` sur les nœuds, ni `~/.local/state/workbook/` sur `adm01` : ils contiennent la cause.
- Une seule panne active à la fois par exercice. Si tu abandonnes : `lab/bin/break 09 35 --annuler` remet l'état sain (filet de sécurité, pas un correctif : compte l'exercice comme non réussi). **Quand tu as réparé**, lance aussi `--annuler` pour **clore** la panne : elle retire les VMs de test, réarme la HA si l'injection l'avait désarmée, et ne rétablit que ce qui est encore dans l'état cassé (jamais elle ne revient sur ta réparation).
- Périmètre : les pannes agissent **à l'intérieur** des nœuds imbriqués `hv01-03` (fichiers sauvegardés avant modification sous `/var/lib/workbook/`, règles nftables posées à chaud, services, configuration du cluster) et sur les VMs de test 191-197. **Jamais** sur `pve01` (ni son réseau, ni son pare-feu, ni ses VMs hors `hv01-03`), **jamais** sur `pbs01`, jamais sur `ceph-par1`. Aucune donnée n'est détruite, aucune sauvegarde n'est supprimée.
- **Tiens un journal de diagnostic** pour chaque panne, dans `docs/virtualisation/journal/` de `~/medisphere` (publié par MR) : heure, nœud, hypothèse, commande, résultat observé, conclusion. Il alimente le post-mortem de M09-E43.
- Le **temps cible** est indicatif. Le dépasser n'est pas un échec ; corriger sans comprendre en est un.

> ⚠️ **Gestes interdits pendant ces pannes**, sauf mention contraire dans l'exercice : `pvecm delnode` (retirer un nœud ne « répare » rien et oblige à le réinstaller, M09-E29), réinstaller un nœud, `rm` dans `/etc/pve` ou `/var/lib/pve-cluster/`, `ceph osd out`/`purge` d'un OSD, `pvecm expected 1` sans avoir prouvé que la partition est seule. Chacun de ces gestes peut transformer une panne de 30 minutes en reconstruction.

> ⚠️ **Accès de secours** : aucune panne ne coupe le SSH de `adm01` vers les nœuds. Si tu t'enfermes toi-même dehors (règle nftables, `sshd` cassé, réseau d'un nœud), il reste la console du nœud imbriqué depuis `pve01` : console série (`root@pve01:~# qm terminal 2093`, `Ctrl+O` pour sortir) ou noVNC de la VM 2091, 2092 ou 2093 dans l'interface. **Vérifie ce chemin avant de commencer** : ouvre la console de `hv03` et connecte-toi en root (mot de passe du fichier de réponse, rangé au registre des secrets). Toute utilisation est consignée dans ton journal. La console de `pve01` est un accès en lecture : tu ne modifies **rien** sur `pve01` lui-même.

---

### M09-E35 — Panne : le cluster a perdu le quorum  `BF` `★★★`

> **Ticket INC-3641** — *De : Nadia Roussel*
> Depuis 7 h 05, plus aucune action n'aboutit sur le cluster `hv-par1` : démarrer, arrêter ou modifier une VM échoue avec `cluster not ready - no quorum? (500)`, quel que soit le nœud sur lequel on se connecte. L'interface affiche les autres nœuds en rouge ou avec un point d'interrogation. Les VMs qui tournaient tournent toujours. Rien dans le calendrier des changements ; Lucas « n'a rien touché, juste appliqué des consignes d'InfoGér hier soir ».

**Objectifs pédagogiques**
- Lire l'état de Corosync et de votequorum sur chaque nœud : membre, votes attendus, votes présents, quorum, état de chaque lien knet.
- Distinguer une perte de quorum par **réseau** (liens coupés), par **configuration** (votes attendus) et par **chiffrement** (clé de Corosync divergente), à partir des journaux et de l'état chargé.
- Modifier `corosync.conf` quand `/etc/pve` est en lecture seule, sans créer de *split-brain* ; comprendre `config_version` et la propagation par pmxcfs.

**Prérequis** : M09-E04, M09-E08, M09-E09, M09-E24 ; `lab/bin/check 09 35` vert avant l'injection (sauf la ligne RB-093).
**Durée indicative** : 45 min (temps cible), plus 30 min pour le runbook.

**Contexte technique** : Corosync 3 utilise le transport knet ; le lien 0 passe par le VLAN 32 (10.10.32.51-53), le lien 1 par MGMT (10.10.10.51-53). Le fichier qui fait foi est `/etc/pve/corosync.conf` ; pmxcfs le recopie dans `/etc/corosync/corosync.conf` de chaque nœud quand son `config_version` augmente, et Corosync le relit. La clé partagée est `/etc/corosync/authkey` (copiée à l'adhésion d'un nœud, hors de `/etc/pve`). Les journaux : `journalctl -u corosync -u pve-cluster`.

**Injection** : `lab/bin/break 09 35` (3 variantes).

**Travail demandé**
1. Établis la vue de **chaque** nœud : qui voit qui, sur quel lien, combien de votes sont attendus et présents. Note les écarts d'un nœud à l'autre. Constate ce qui marche encore (VMs en cours, lecture de `/etc/pve`) et ce qui ne marche plus.
2. Formule tes hypothèses (réseau, configuration, clé) et départage-les par des mesures **non invasives** : journaux de Corosync, état des liens, comparaison des fichiers entre nœuds, filtrage local.
3. Trouve la cause racine et corrige-la. Si la correction exige d'écrire dans `/etc/pve` alors qu'il est en lecture seule, explique dans ton journal comment tu as obtenu le droit d'écrire, sur quel nœud, pourquoi c'était sans danger, et comment tu as rendu la main à votequorum ensuite.
4. Vérifie le retour : quorum sur les trois nœuds, deux liens connectés partout, configuration identique partout. Puis lance `--annuler` (il réarme la HA).
5. Rédige le runbook **RB-093 « Perte de quorum du cluster hv-par1 »** dans `docs/virtualisation/runbooks/` : symptômes, vue par nœud, arbre de décision (réseau / configuration / clé / nœuds arrêtés), gestes autorisés et interdits, condition d'emploi de `pvecm expected`, retour à la normale.

**Critères de réussite**
- [ ] Les trois nœuds sont quorate, avec 3 votes attendus et 3 présents ; les liens 0 et 1 sont connectés vers les deux autres nœuds, sur chaque nœud.
- [ ] `/etc/corosync/corosync.conf` est identique à `/etc/pve/corosync.conf` sur chaque nœud, sans `expected_votes` forcé ; la clé de Corosync est la même partout ; aucun filtrage parasite.
- [ ] La pile HA est réarmée et RB-093 est commité ; ton journal contient la vue par nœud initiale.

**Vérification** : `lab/bin/check 09 35`

<details><summary>Indice 1</summary>

Trois chiffres disent presque tout : `Expected votes`, `Total votes` et `Quorum` dans `corosync-quorumtool -s`. Si `Total votes` vaut 1 sur chaque nœud, les nœuds ne se parlent plus ; si `Total votes` vaut 3 et que le quorum manque quand même, ce n'est pas le réseau.
</details>

<details><summary>Indice 2</summary>

`corosync-cfgtool -s` montre l'état de chaque lien vers chaque nœud. Si les liens sont « disconnected » alors que `ping` passe, cherche ce qui peut laisser passer l'ICMP et pas l'UDP 5405/5406 (`nft list ruleset` sur chaque nœud), ou ce qui empêche les nœuds de se **comprendre** (journal de Corosync au démarrage, sommes de contrôle des fichiers partagés).
</details>

<details><summary>Indice 3</summary>

Pour retirer une ligne d'un `corosync.conf` qu'on ne peut plus écrire : les votes attendus se changent aussi **en mémoire** (`corosync-quorumtool -e`, `pvecm expected`), le temps de réécrire le fichier par la méthode de la documentation (copie `.new`, `config_version` incrémentée, renommage).
</details>

**Pour aller plus loin** : ajoute à `ms-verif-cluster` (M09-E25) une sonde « par nœud » qui compare `Expected votes`, `Total votes`, l'état des deux liens et la somme de contrôle de `authkey` et de `corosync.conf` sur les trois nœuds : elle aurait localisé chacune des trois variantes en une ligne. Documentation : [Cluster Manager](https://pve.proxmox.com/pve-docs/chapter-pvecm.html), `man votequorum`, `man corosync.conf`.

---

### M09-E36 — Panne : un nœud ne rejoint plus le cluster  `BF` `★★★`

> **Ticket INC-3642** — *De : Karim Benali*
> Après une intervention de nuit sur `hv03`, ce nœud n'est plus « dans » le cluster comme avant : depuis l'interface de `hv01`, `hv03` est marqué en rouge ou avec un point d'interrogation, et ses VMs ne se consultent plus (erreurs 401, 595 ou délai dépassé, selon l'écran). Je n'ai pas le détail de ce qui a été fait cette nuit, le prestataire est injoignable avant 10 h. Interdiction de retirer `hv03` du cluster (`pvecm delnode`) pour « repartir propre ».

**Objectifs pédagogiques**
- Séparer les étages d'appartenance d'un nœud : membre Corosync, pmxcfs (`/etc/pve/.members`), API et proxy (`pveproxy`, port 8006, tickets), stockage (Ceph sur ce nœud).
- Savoir ce qui, sur un nœud Proxmox VE, dépend du nom d'hôte, de l'horloge, de la clé de Corosync et des certificats du nœud.
- Réparer un nœud **sans** le retirer du cluster.

**Prérequis** : M09-E04, M09-E08, M09-E26 (certificats ACME des nœuds) ; `lab/bin/check 09 36` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : quand tu affiches un nœud depuis l'interface d'un autre, le `pveproxy` du nœud qui te sert relaie la requête vers le port 8006 du nœud visé, à l'adresse que celui-ci annonce dans `/etc/pve/.members`, avec un ticket signé par la clé du cluster et daté. Les certificats des nœuds sont dans `/etc/pve/nodes/<nœud>/` (`pve-ssl.pem` signé par la CA du cluster, `pveproxy-ssl.pem` s'il existe : ici le certificat ACME de M09-E26), leurs clés à côté.

**Injection** : `lab/bin/break 09 36` (4 variantes, toutes sur `hv03`).

**Travail demandé**
1. Depuis `hv01`, puis depuis `hv03`, établis à quel étage `hv03` « décroche » : membre Corosync, quorum de `hv03`, `.members` (adresse et état annoncés), réponse de son API en direct (`https://10.10.10.53:8006`) et relayée.
2. Lis les journaux de l'étage fautif (`corosync`, `pve-cluster`, `pveproxy`, `pvedaemon`, `chrony`) **autour de l'heure de l'intervention**. Cherche ce qui a changé sur `hv03` (fichiers récents dans `/etc`, services arrêtés, heure).
3. Corrige à la racine sur `hv03`, en reconstruisant l'élément fautif par l'outil prévu (pas par un fichier copié au hasard depuis un autre nœud sans comprendre ce qu'il contient). Relance seulement ce qui doit l'être.
4. Prouve le retour : `hv03` membre et quorate, bonne adresse dans `.members`, API directe et relayée, heure juste. Vérifie aussi Ceph (`ceph -s`) : selon la variante, la panne a pu l'affecter.
5. Prévention : quelle sonde, quelle tâche du rôle `pve_noeud` ou quelle règle de pare-feu aurait évité ou détecté la variante rencontrée ?

**Critères de réussite**
- [ ] Les trois nœuds sont membres de la partition quorate à 3 votes et annoncent leur adresse MGMT dans `/etc/pve/.members` ; chaque nom se résout localement vers la bonne adresse.
- [ ] Chrony est actif et activé partout, l'écart d'horloge avec `adm01` est inférieur à 5 s ; `pveproxy` répond sur chaque nœud et les appels relayés depuis `hv01` aboutissent.
- [ ] La clé de Corosync est identique partout ; ton journal situe l'étage en cause avec la mesure qui le prouve.

**Vérification** : `lab/bin/check 09 36`

<details><summary>Indice 1</summary>

`corosync-quorumtool -l` sur `hv01` (qui est dans la membre ?), `cat /etc/pve/.members` (quelle adresse, quel état ?), `curl -sS -o /dev/null -w '%{http_code}\n' --resolve hv03.par1.medisphere.internal:8006:10.10.10.53 https://hv03.par1.medisphere.internal:8006/` depuis `adm01` (l'API répond-elle en direct ?) : trois étages, trois réponses.
</details>

<details><summary>Indice 2</summary>

Une erreur 401 sur des appels relayés, alors que le mot de passe est bon, parle de **temps** (un ticket daté hors de sa fenêtre de validité). Une erreur 595 parle de **connexion** (adresse, port, TLS). Un nœud absent de la membre parle de **Corosync** (réseau, clé, configuration). `find /etc -newermt '-12 hours' -type f` sur `hv03` raconte la nuit.
</details>

<details><summary>Indice 3</summary>

`pvecm updatecerts` régénère les certificats du nœud signés par la CA du cluster ; `pvenode cert` gère le certificat personnalisé ; la clé de Corosync d'un nœud se reprend sur un nœud sain du cluster (et seulement là). Pour l'heure, regarde `timedatectl` et `chronyc tracking` avant de toucher à `date`.
</details>

**Pour aller plus loin** : mesure jusqu'à quel écart d'horloge les appels relayés fonctionnent encore, et retrouve dans la documentation la durée de validité d'un ticket d'API. Documentation : [Certificate Management](https://pve.proxmox.com/wiki/Certificate_Management), [Cluster Manager — adding nodes](https://pve.proxmox.com/pve-docs/chapter-pvecm.html).

---

### M09-E37 — Panne : une VM HA reste en erreur  `BF` `★★★`

> **Ticket INC-3643** — *De : Julien Petit*
> Ma VM de recette sous HA (`pan-ha*`, VMID 191 à 193) est marquée `error` dans l'écran HA et ne redémarre plus. J'ai cliqué sur « Démarrer » : la demande est refusée ou rien ne se passe. Elle doit tourner avant midi pour les tests de charge. Ne la recrée pas : je veux comprendre pourquoi la HA a abandonné, et que ça ne se reproduise pas sur les vraies VMs.

**Objectifs pédagogiques**
- Suivre la machine à états du gestionnaire HA (`request_start`, `started`, `relocate`, `error`…) et ses compteurs (`max_restart`, `max_relocate`).
- Lire le journal du CRM et du LRM et les tâches qu'ils lancent, pour trouver **pourquoi** chaque tentative a échoué.
- Sortir une ressource de l'état `error` par la procédure documentée, et vérifier qu'une règle d'affinité reste satisfiable dans toutes les situations prévues (maintenance d'un nœud, perte d'un nœud).

**Prérequis** : M09-E13, M09-E20 (maintenance), M09-E22 (RB-090) ; `lab/bin/check 09 37` vert avant l'injection (HA armée, aucun nœud en maintenance).
**Durée indicative** : 40 min (temps cible). L'injection prend 3 à 6 minutes (le temps que la HA épuise ses tentatives).

**Contexte technique** : le CRM maître (`pve-ha-crm`) décide, les LRM (`pve-ha-lrm`) exécutent sur chaque nœud ; l'état partagé est dans `/etc/pve/ha/` (`resources.cfg`, `rules.cfg`, `manager_status`) et `/etc/pve/nodes/<nœud>/lrm_status`. Les VMs 191-193 n'ont pas de système : une fois démarrées, elles tournent dans leur BIOS, ce qui suffit à la HA.

**Injection** : `lab/bin/break 09 37` (3 variantes).

**Travail demandé**
1. Reconstitue la chronologie de la ressource en erreur : `ha-manager status -v`, journal du CRM maître et des LRM (`journalctl -u pve-ha-crm -u pve-ha-lrm`), tâches des nœuds (`pvenode task list`, `/var/log/pve/tasks/`). Pour chaque tentative : quel nœud, quelle action, quel message d'échec.
2. Explique pourquoi la HA s'est arrêtée là (quel compteur, quelle contrainte) et pourquoi c'est un comportement **voulu**.
3. Corrige la cause (configuration de la VM, emplacement de ses disques, règle d'affinité, maintenance…) puis sors la ressource de l'état `error` par la procédure de la documentation. Ne supprime pas la ressource HA pour la recréer.
4. Prouve le retour : la ressource est `started` sur un nœud permis par les règles, sans erreur dans le journal.
5. Prévention : quelle vérification ajouterais-tu à RB-090 (maintenance) ou à la revue des règles HA pour que cela n'arrive pas sur une VM de production ?

**Critères de réussite**
- [ ] Aucune ressource HA en état `error`, `fence` ou `recovery` ; chaque LRM est `active` ou `idle` ; aucun nœud oublié en maintenance ; la HA est armée.
- [ ] Aucune règle HA en conflit.
- [ ] Ton journal contient la chronologie des tentatives, la cause et la procédure de sortie d'erreur appliquée (avant `--annuler`, qui détruit les VMs 191-193).

**Vérification** : `lab/bin/check 09 37` (après `--annuler`)

<details><summary>Indice 1</summary>

L'état `error` n'est pas une panne de la HA : c'est la HA qui **s'interdit** de continuer à essayer une ressource qu'elle ne sait plus faire tourner, pour ne pas aggraver les choses. La question n'est donc pas « comment la redémarrer », mais « qu'est-ce qui faisait échouer chaque tentative ».
</details>

<details><summary>Indice 2</summary>

La tâche de démarrage (`qmstart`) ou de migration (`qmigrate`) qui a échoué a un journal complet : `pvenode task log <UPID>` sur le nœud qui l'a lancée. Pour une contrainte de placement, `ha-manager rules config` et `ha-manager status` (lignes `lrm`) disent quels nœuds étaient possibles à ce moment-là.
</details>

<details><summary>Indice 3</summary>

La documentation de `ha-manager` décrit comment récupérer une ressource en `error` : la faire passer par un état où la HA ne la pilote plus, corriger, puis la remettre en `started`.
</details>

**Pour aller plus loin** : écris un test (script ou Molecule) qui, pour un jeu de règles HA donné, vérifie qu'en retirant n'importe quel nœud chaque ressource garde au moins un nœud possible. Documentation : [High Availability](https://pve.proxmox.com/pve-docs/chapter-ha-manager.html) (sections *Rules*, *Error Recovery*, *Maintenance Mode*).

---

### M09-E38 — Panne : la migration à chaud échoue  `BF` `★★`

> **Ticket INC-3644** — *De : Julien Petit*
> Je dois libérer `hv01` pour la maintenance de cet après-midi. La migration à chaud de ma VM `pan-mig` (VMID 194, `hv01`) vers `hv02` ne passe pas : selon l'essai, elle est refusée tout de suite ou elle démarre et n'avance plus. Les autres VMs, je ne les ai pas encore essayées. Hors de question de l'arrêter : elle doit être migrée à chaud.

**Objectifs pédagogiques**
- Connaître les conditions d'une migration à chaud : stockage partagé ou copie des disques locaux, périphériques locaux, réseau et canal de migration (SSH, type `secure`), bande passante.
- Utiliser le contrôle préalable de l'API (`GET /nodes/{nœud}/qemu/{vmid}/migrate`) et le journal de la tâche `qmigrate`.
- Choisir entre corriger la VM, corriger la plateforme, ou migrer autrement (`--with-local-disks`), et en mesurer le coût.

**Prérequis** : M09-E11, M09-E27 ; `lab/bin/check 09 38` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : la configuration du réseau de migration (M09-E27) est dans `/etc/pve/datacenter.cfg` (lignes `migration:` et `bwlimit:`), la VM 194 a son disque principal sur `ceph-vm`. La migration à chaud *secure* ouvre une session SSH root du nœud source vers le nœud cible, à l'adresse du nœud cible dans le réseau de migration.

**Injection** : `lab/bin/break 09 38` (4 variantes ; la VM 194 est créée et démarrée par l'injection).

**Travail demandé**
1. Lance la migration et lis le journal **complet** de la tâche. Interroge aussi le contrôle préalable de l'API pour la VM 194 vers `hv02`. Qu'est-ce qui bloque, à quelle étape (avant le transfert, pendant l'établissement du canal, pendant la copie de la mémoire) ?
2. Si la migration démarre puis stagne, mesure son débit réel et trouve d'où vient la limite (VM, nœud, cluster).
3. Corrige, en préférant ce qui rend **toutes** les VMs migrables à nouveau quand la cause est dans la plateforme, et ce qui ne dégrade pas la VM quand la cause est dans la VM.
4. Migre la VM 194 à chaud vers `hv02` et relève la durée et l'interruption (*downtime*) annoncées dans le journal de la tâche.
5. Vérifie qu'aucune autre VM du cluster n'a le même obstacle (pour la variante rencontrée), et note comment `ms-verif-cluster` pourrait le détecter.

**Critères de réussite**
- [ ] SSH root fonctionne entre tous les nœuds sur le réseau de migration ; aucune limite de migration inférieure à 10 Mio/s n'est configurée ; aucun filtrage parasite.
- [ ] La VM 194 (tant qu'elle existe) n'a ni disque ni périphérique local qui bloque sa migration ; elle a été migrée à chaud vers `hv02` (tâche `qmigrate` réussie dans le journal de `hv01`).
- [ ] Ton journal contient le message d'échec initial, la cause et le débit mesuré.

**Vérification** : `lab/bin/check 09 38`

<details><summary>Indice 1</summary>

`pvesh get /nodes/hv01/qemu/194/migrate --target hv02` renvoie, avant toute migration, les disques locaux (`local_disks`), les ressources locales (`local_resources`) et les nœuds refusés. Ce qui n'y apparaît pas se voit dans le journal de la tâche : connexion, `migration status`, débit.
</details>

<details><summary>Indice 2</summary>

Une migration qui « n'avance plus » affiche une ligne `migration status: active (transferred …)` toutes les secondes : calcule le débit. Une limite de bande passante peut venir de la commande, de la VM, du stockage ou du **centre de données** (`datacenter.cfg`). Une migration qui échoue à l'établissement du canal se rejoue à la main : `ssh -o HostKeyAlias=hv02 root@<IP de migration de hv02>` depuis `hv01`.
</details>

**Pour aller plus loin** : compare la durée de migration de la VM 194 avec et sans `--migration_type insecure` sur le VLAN 30, et rapproche-la du débit théorique ; reviens à ton ADR de M09-E27. Documentation : [qm(1) migrate](https://pve.proxmox.com/pve-docs/qm.1.html), [Migration](https://pve.proxmox.com/pve-docs/chapter-qm.html#qm_migration).

---

### M09-E39 — Panne : les VMs se figent  `BF` `★★★`

> **Ticket INC-3645** — *De : Nadia Roussel*
> Depuis 6 h 40, plusieurs VMs du cluster `hv-par1` sont figées : la console répond mal, les invités journalisent `task … blocked for more than 120 seconds` et certains programmes restent bloqués en écriture. Le tableau de bord Ceph de l'interface n'est plus vert. Aucune VM n'est arrêtée. Les équipes demandent si elles doivent redémarrer leurs VMs : la réponse est non tant que tu n'as pas compris.

**Objectifs pédagogiques**
- Relier un symptôme d'invité (E/S bloquées) à l'état des PG Ceph (`active`, `peered`, `undersized`, `inactive`) et à la règle `min_size`.
- Diagnostiquer un problème de MTU (« trou noir » : petits paquets OK, gros paquets perdus) sur le réseau cluster de Ceph, et reconnaître ses signatures dans les journaux des OSD.
- Rétablir le service Ceph sans perte de données ni geste destructif (`ceph osd out`, `purge`, `min_size 1` interdits).

**Prérequis** : M09-E10, M09-E28 ; M08 (états des PG, `noout`, MTU) ; `lab/bin/check 09 39` vert avant l'injection (Ceph `HEALTH_OK`).
**Durée indicative** : 45 min (temps cible), plus 30 min pour le runbook.

**Contexte technique** : Ceph hyperconvergé de `pveceph` : MON et MGR sur les trois nœuds, deux OSD par nœud, réseau public 10.10.30.0/24 et réseau cluster 10.10.31.0/24 en MTU 9000 ; le stockage `ceph-vm` du cluster utilise un pool répliqué 3/2 (domaine de panne : l'hôte). Les commandes `ceph` se lancent en root sur n'importe quel nœud.

**Injection** : `lab/bin/break 09 39` (3 variantes).

**Travail demandé**
1. Avant tout geste : `ceph -s`, `ceph health detail`, `ceph osd tree`, `ceph pg stat`. Combien de PG sont inactifs, pourquoi, et quelles VMs sont concernées (lesquelles ont leurs disques sur `ceph-vm`) ?
2. Explique, avec les chiffres de ton cluster (size, min_size, OSD up/in par hôte), pourquoi les écritures sont bloquées et pas seulement ralenties. Si les OSD « vont et viennent », cherche pourquoi ils se déclarent mutuellement morts.
3. Corrige la cause racine en respectant l'ordre sûr (drapeaux, OSD, paramètres du pool) et sans geste destructif. Note chaque commande et son effet sur `ceph -s`.
4. Attends le retour à `HEALTH_OK` et vérifie qu'une VM figée reprend **sans redémarrage** (une VM de ton choix sur `ceph-vm`, ou un `rados bench` court sur le pool).
5. Rédige le runbook **RB-094 « Ceph hyperconvergé : PG inactifs, VMs figées »** dans `docs/virtualisation/runbooks/` : symptômes, commandes de lecture, arbre de décision (OSD arrêtés, `min_size`, réseau/MTU, disque plein), gestes interdits, retour à la normale.

**Critères de réussite**
- [ ] Ceph est `HEALTH_OK`, 6 OSD `up` et `in`, tous les PG `active+clean`, aucun drapeau (`noout`, `norecover`…) oublié ; le pool de `ceph-vm` est en size 3 / min_size 2.
- [ ] Sur chaque nœud, les OSD sont actifs et activés au démarrage ; les trames de 9000 octets passent sans fragmentation entre `hv01` et les deux autres nœuds, sur les réseaux public et cluster.
- [ ] RB-094 est commité ; ton journal contient la sortie initiale de `ceph health detail` commentée.

**Vérification** : `lab/bin/check 09 39`

<details><summary>Indice 1</summary>

Un PG `undersized+degraded+peered` (sans `active`) a trouvé ses copies mais pas **assez** pour accepter des écritures : il en faut au moins `min_size`. `ceph pg dump_stuck inactive` liste les PG concernés et leurs OSD ; `ceph osd tree` dit lesquels manquent et sur quel hôte.
</details>

<details><summary>Indice 2</summary>

Des OSD qui se plaignent `wrongly marked me down`, des battements de cœur (*heartbeats*) perdus entre certains hôtes seulement, des `slow ops` : pense au réseau. `ping -M do -s 8972` (taille maximale sans fragmentation pour une MTU de 9000) entre adresses du réseau cluster, puis `ping -M do -s 1472` : si l'un passe et pas l'autre, cherche **qui** perd les gros paquets.
</details>

<details><summary>Indice 3</summary>

Avant de relancer des OSD arrêtés, demande-toi pourquoi ils l'ont été (journal, `systemctl is-enabled`), et si un paramètre du pool n'a pas été « durci » au même moment (`ceph osd pool get <pool> all`, `ceph osd dump | grep -E 'flags|pool'`).
</details>

**Pour aller plus loin** : reproduis sur la VM de test de ton choix l'effet de `min_size 1` (en lecture seule : sur le papier) et explique à Lucas pourquoi la documentation de Ceph le déconseille. Documentation : [Deploy Hyper-Converged Ceph Cluster](https://pve.proxmox.com/pve-docs/chapter-pveceph.html), [Placement Group States](https://docs.ceph.com/en/tentacle/rados/operations/pg-states/), [Troubleshooting OSDs](https://docs.ceph.com/en/tentacle/rados/troubleshooting/troubleshooting-osd/).

---

### M09-E40 — Panne : la réplication est en échec  `BF` `★★`

> **Ticket INC-3646** — *De : Julien Petit*
> La réplication de ma VM de recette `pan-rep` (196, `hv01` → `hv02`, job `196-0`) est en échec : l'onglet « Réplication » affiche une erreur et le compteur d'échecs monte. On m'a vendu un RPO de 15 minutes pour cette VM. Je veux la réplication rétablie sans repartir de zéro si c'est possible, et savoir si d'autres jobs du cluster sont touchés.

**Objectifs pédagogiques**
- Connaître le mécanisme de la réplication de Proxmox VE (`pvesr`) : instantanés `__replicate_<job>_<horodatage>__`, envoi ZFS complet puis incrémental, transport par SSH entre nœuds, planificateur `pvescheduler`.
- Lire l'état d'un job (`pvesr status`, journal du job) et les journaux ZFS (`zpool history`, `zfs list -t snapshot`).
- Choisir entre rétablir l'incrémental et accepter un renvoi complet, et l'expliquer (RPO, volume, temps).

**Prérequis** : M09-E14 ; `lab/bin/check 09 40` vert avant l'injection.
**Durée indicative** : 30 min (temps cible). L'injection crée la VM 196 et sa première réplication (2 à 4 min).

**Contexte technique** : le stockage `zfs-local` pointe vers le pool ZFS `tank` de chaque nœud, avec le même nom partout (condition de la réplication). Le journal d'un job se lit avec `pvesr status` et dans `/var/log/pve/replicate/`. Les nœuds se connectent entre eux en root par SSH avec les clés du cluster (`/etc/pve/priv/authorized_keys`).

**Injection** : `lab/bin/break 09 40` (3 variantes).

**Travail demandé**
1. Lis l'erreur du job et son journal. À quelle étape échoue-t-il : connexion, recherche de l'instantané de base, envoi, réception ?
2. Vérifie de chaque côté (`hv01` et `hv02`) : instantanés de réplication présents, place disponible, connexion SSH du nœud source vers le nœud cible **comme le fait `pvesr`**.
3. Corrige la cause racine. Si la base commune a disparu, choisis entre un renvoi complet et une autre voie, et justifie (taille, RPO, risque).
4. Relance le job (`pvesr schedule-now`) et prouve qu'il revient à `OK` avec un compteur d'échecs à 0.
5. Vérifie les **autres** jobs de réplication du cluster : sont-ils touchés par la même cause ?

**Critères de réussite**
- [ ] Aucun job de réplication en échec sur aucun nœud ; les pools ZFS sont sains et remplis à moins de 80 %.
- [ ] Chaque nœud ouvre une session SSH root vers chacun des deux autres avec les clés du cluster.
- [ ] Ton journal indique l'étape en échec, la cause, et ton choix (incrémental rétabli ou renvoi complet) justifié.

**Vérification** : `lab/bin/check 09 40`

<details><summary>Indice 1</summary>

`zfs list -t snapshot -o name,creation -s creation | grep vm-196` sur les **deux** nœuds : l'incrémental exige que le dernier instantané de réplication de la source existe aussi sur la cible. `zfs list -o space` et `zpool list` disent où est passée la place.
</details>

<details><summary>Indice 2</summary>

`pvesr` se connecte comme tout le cluster : `ssh -o BatchMode=yes -o HostKeyAlias=hv02 root@<IP de hv02> true` depuis `hv01`. Si cela échoue, regarde côté `hv02` ce que `sshd` accepte (`ls -l /root/.ssh/`, journal de `ssh`) et compare avec un nœud sain.
</details>

**Pour aller plus loin** : calcule le RPO réel de tes jobs (horodatages de `last_sync`) sur 24 h et ajoute une alerte dans `ms-verif-cluster` quand il dépasse deux intervalles. Documentation : [Storage Replication](https://pve.proxmox.com/pve-docs/chapter-pvesr.html).

---

### M09-E41 — Panne : la sauvegarde nocturne a échoué  `BF` `★★`

> **Ticket INC-3647** — *De : Nadia Roussel*
> Courriel de 2 h 14 : « vzdump backup status : backup failed » pour toutes les VMs du cluster `hv-par1` vers `pbs-par2`. Le PBS de PAR2 est en bonne santé (les sauvegardes de `pve01` sont passées cette nuit) : le problème est de notre côté. Sophie rappelle qu'une nuit sans sauvegarde se déclare au registre des écarts ; deux nuits, c'est un incident HDS. Interdiction de toucher à `pbs01` sans fiche de changement.

**Objectifs pédagogiques**
- Décomposer l'accès d'un client Proxmox VE à PBS : adresse et port (8007), vérification TLS (empreinte ou chaîne de confiance), authentification par jeton (identifiant dans `storage.cfg`, secret dans `/etc/pve/priv/storage/`), datastore et namespace, droits.
- Diagnostiquer **depuis le client**, sans privilège sur le serveur : `pvesm status`, `pvesm list`, journal de la tâche `vzdump`, `proxmox-backup-client` en lecture.
- Réparer sans exposer le secret du jeton (pas en argument de commande, pas dans le journal).

**Prérequis** : M09-E15 (au moins une sauvegarde dans `par1/hv`) ; M00 (PBS, jeton) ; `lab/bin/check 09 41` vert avant l'injection (sauf la ligne « sauvegarde de moins de 24 h » si ta dernière date d'hier).
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : la définition du stockage est dans `/etc/pve/storage.cfg` (section `pbs: pbs-par2`), le secret du jeton `wb-hv@pbs!<nom>` dans `/etc/pve/priv/storage/pbs-par2.pw` (lisible par root seulement), la clé de chiffrement côté client dans `/etc/pve/priv/storage/pbs-par2.enc` (M09-E15). Les valeurs attendues (empreinte du certificat de `pbs01`, namespace, identifiant du jeton) sont dans ton registre des secrets et ta documentation de M09-E15 ; l'empreinte se lit aussi sans privilège sur le serveur.

**Injection** : `lab/bin/break 09 41` (3 variantes).

**Travail demandé**
1. Reproduis l'échec : sauvegarde manuelle d'une petite VM vers `pbs-par2` (mode `snapshot`), puis lecture du journal de la tâche. Note le message exact.
2. Situe l'étage : connexion, TLS, authentification, datastore/namespace, droits. Pour chacun, trouve une mesure faite **depuis un nœud** qui le confirme ou l'écarte.
3. Compare la définition du stockage et son secret avec ce que dit ta documentation de M09-E15. Identifie ce qui a changé (et, si possible, quand : `/etc/pve` garde une date de modification).
4. Corrige par l'outil prévu (`pvesm set`, ou réécriture du fichier de secret par une méthode qui ne fait pas passer le secret en argument), puis relance une sauvegarde et restaure-en un fichier (restauration de fichier unique) pour prouver la chaîne complète.
5. Rédige la note d'écart pour Sophie (5 lignes dans ton journal : nuit concernée, VMs non sauvegardées, cause, rétablissement, prévention).

**Critères de réussite**
- [ ] `pbs-par2` est actif sur les trois nœuds, pointe vers le datastore `ds-lab` et le namespace `par1/hv`, et ses sauvegardes sont listées.
- [ ] Une sauvegarde de moins de 24 h existe dans `par1/hv`.
- [ ] Le secret du jeton n'apparaît dans aucun historique de commande ni journal ; ton journal contient le message d'échec initial et la note d'écart.

**Vérification** : `lab/bin/check 09 41`

<details><summary>Indice 1</summary>

`pvesm status` et `pvesm list pbs-par2` sur un nœud donnent souvent déjà l'étage (le message d'erreur cite TLS, `401` ou le namespace). `openssl s_client -connect 10.20.10.10:8007 </dev/null | openssl x509 -noout -fingerprint -sha256` lit l'empreinte présentée par le serveur, sans aucun droit sur lui.
</details>

<details><summary>Indice 2</summary>

Ce qui ne change pas tout seul : l'empreinte d'un certificat (sauf renouvellement), le secret d'un jeton (sauf régénération), un namespace (sauf renommage). Si le serveur n'a pas bougé (les sauvegardes de `pve01` passent), ce qui a changé est dans `/etc/pve` : `ls -l --time-style=full-iso /etc/pve/storage.cfg /etc/pve/priv/storage/`.
</details>

**Pour aller plus loin** : ajoute à `ms-verif-sauvegardes` (M00/M02) un contrôle quotidien « dernière sauvegarde de chaque VM du cluster de moins de 26 h », et fais-le alerter ce matin. Documentation : [Backup and Restore](https://pve.proxmox.com/pve-docs/chapter-vzdump.html), [Proxmox Backup Server storage](https://pve.proxmox.com/pve-docs/chapter-pvesm.html#storage_pbs).

---

### M09-E42 — Panne : impossible de modifier une VM  `BF` `★★★`

> **Ticket INC-3648** — *De : Julien Petit*
> *(Le détail du ticket s'affiche à l'injection : il dit par quelle adresse Julien travaille et ce qui marche ailleurs.)* Impossible de modifier une VM : ajouter un disque, changer la mémoire ou même une description échoue, avec une erreur qui change selon l'écran. Le `tofu apply` de la recette échoue aussi. Karim, connecté directement à un autre nœud, modifie ses VMs sans problème.

**Objectifs pédagogiques**
- Comprendre pmxcfs : système de fichiers FUSE adossé à une base SQLite locale (`/var/lib/pve-cluster/config.db`), répliqué par Corosync (CPG), monté sur `/etc/pve`, inscriptible seulement avec le quorum.
- Distinguer les causes d'un `/etc/pve` non inscriptible : perte de quorum, pmxcfs arrêté ou incapable d'écrire sa base, point de montage absent.
- Repérer une panne **masquée** par un point d'accès (VIP keepalived) dont le contrôle de santé ne regarde pas ce qui est en panne.

**Prérequis** : M09-E04, M09-E18 (VIP de l'API), M09-E44 peut être lu avant ; `lab/bin/check 09 42` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : la VIP 10.10.10.200 (`hv.par1.medisphere.internal`, VRID 110) est portée par keepalived sur l'un des nœuds (rôle `pve_cluster`, M09-E18) ; OpenTofu (`hv-invites`) l'utilise comme point d'accès. Le service `pve-cluster` lance `pmxcfs`. Les messages d'erreur d'écriture viennent de `pvedaemon` et apparaissent dans le journal de la tâche ou de `pvedaemon`.

**Injection** : `lab/bin/break 09 42` (3 variantes ; selon la variante, Julien passe par la VIP ou travaille en direct sur un nœud : le ticket affiché le dit).

**Travail demandé**
1. Identifie le nœud qui sert réellement Julien (en direct, ou celui qui porte la VIP). Reproduis l'échec en ligne de commande sur ce nœud (une modification inoffensive : la description d'une VM de test) et note le message exact.
2. Sur ce nœud : quorum, état de `pve-cluster`, montage de `/etc/pve`, place disque, journal de `pve-cluster`. Compare avec un nœud où l'écriture fonctionne.
3. Corrige la cause racine. Si tu dois relancer `pve-cluster`, vérifie avant que rien ne l'en empêche (et lis son journal s'il refuse).
4. Prouve le retour : modification possible par la VIP, `/etc/pve` identique sur les trois nœuds (même `.version` après une modification).
5. Le script de santé de keepalived (M09-E18) aurait-il déplacé la VIP pour la variante rencontrée ? Explique pourquoi (ce qu'il teste, ce qu'il ne teste pas) et propose une amélioration du rôle `pve_cluster`, sans l'appliquer dans cet exercice si tu ne l'as pas testée en Molecule.

**Critères de réussite**
- [ ] Sur chaque nœud : `pve-cluster` actif, `/etc/pve` monté, nœud quorate ; disque système rempli à moins de 90 % ; rien de caché sous le point de montage `/etc/pve`.
- [ ] La VIP est portée par un nœud quorate ; la HA est armée.
- [ ] Ton journal contient le message d'échec initial, la mesure qui a désigné la cause, et ta réponse argumentée sur le script de santé de keepalived.

**Vérification** : `lab/bin/check 09 42`

<details><summary>Indice 1</summary>

`ip -br a | grep 10.10.10.200` sur chaque nœud dit qui sert la VIP. Puis, sur ce nœud : `corosync-quorumtool -s`, `systemctl status pve-cluster`, `findmnt /etc/pve`, `df -h /`, `journalctl -u pve-cluster -n 50`.
</details>

<details><summary>Indice 2</summary>

pmxcfs écrit chaque modification dans sa base SQLite **avant** de la diffuser : s'il ne peut plus écrire sur le disque local, `/etc/pve` refuse les écritures même avec le quorum. Et un point de montage FUSE peut cacher des fichiers écrits dans le dossier pendant que pmxcfs était arrêté.
</details>

**Pour aller plus loin** : complète le script de santé de `pve_cluster` pour qu'il vérifie aussi que pmxcfs peut écrire (service, montage, place libre sous `/var/lib/pve-cluster`) sans écrire lui-même dans `/etc/pve` toutes les deux secondes ; teste-le en Molecule sur des VMs jetables avant toute MR. Documentation : [Proxmox Cluster File System (pmxcfs)](https://pve.proxmox.com/pve-docs/chapter-pmxcfs.html).

---

### M09-E43 — Astreinte : le cluster en détresse  `BF` `★★★★`

> **Ticket INC-3650** — *De : Nadia Roussel (responsable astreinte) — priorité P2*
> *(Le détail s'affiche à l'injection : deux remontées, deux pannes indépendantes parmi celles des exercices M09-E35 à M09-E42.)* La recette de MédiAgenda tourne sur ce cluster à partir de 9 h. Tiens-moi informée toutes les 30 min (`#astreinte`), puis rédige le post-mortem avec le modèle de l'équipe.

**Objectifs pédagogiques**
- Trier deux pannes simultanées : laquelle masque ou aggrave l'autre, laquelle traiter d'abord (quorum et stockage avant tout le reste).
- Communiquer pendant l'incident (points d'étape datés, hypothèses, prochaine action) et rédiger un post-mortem sans blâme.
- Réutiliser les runbooks RB-090 à RB-094.

**Prérequis** : M09-E35 à M09-E42 réussis (au moins une variante de chacun) ; RB-093 et RB-094 rédigés ; `lab/bin/check 09 43` vert avant l'injection (sauf la ligne du post-mortem).
**Durée indicative** : 2 h (rétablissement) + 45 min (post-mortem).

**Injection** : `lab/bin/break 09 43` (25 paires possibles, `--variante N` pour en forcer une ; certaines injections prennent dix minutes).

**Travail demandé**
1. Prends l'astreinte : triage en moins de 15 minutes (vue par nœud du quorum, `ceph -s`, `ha-manager status`, `pvesr status`, `pvesm status`). Premier message dans ton journal (format de canal d'astreinte) : impact, hypothèses, prochaine action.
2. Traite les pannes dans l'ordre que tu justifies. Un point d'étape daté toutes les 30 minutes dans ton journal.
3. Clos les deux pannes (`--annuler`) quand tout est réparé, puis vérifie l'ensemble.
4. Rédige le post-mortem `docs/virtualisation/post-mortems/AAAA-MM-JJ-INC-3650.md` avec le modèle (`modules/00-lab/ressources/M00-E46/modele-post-mortem.md`) : résumé, impact, chronologie, causes racines (les deux), détection (qui a vu quoi, quand, et ce que la supervision aurait dû voir), actions correctives avec responsable et échéance.

**Critères de réussite**
- [ ] Tous les contrôles de M09-E35 à M09-E42 sont verts et aucune panne M09 n'est marquée active.
- [ ] Le post-mortem est commité et contient les sections chronologie, causes, détection et actions.
- [ ] Ton journal contient le premier message de triage et les points d'étape.

**Vérification** : `lab/bin/check 09 43`

<details><summary>Indice 1</summary>

L'ordre des dépendances d'un cluster : réseau Corosync → quorum → pmxcfs (`/etc/pve`) → stockage (Ceph, ZFS, PBS) → HA → migrations, réplication, sauvegardes. Une panne plus bas dans la pile fausse les tests de tout ce qui est au-dessus : un job de réplication échoue aussi quand le quorum manque.
</details>

<details><summary>Indice 2</summary>

Les contrôles `lab/bin/check 09 35` à `09 42` sont des sondes ciblées : lance-les pendant le triage pour cartographier ce qui est rouge. Un contrôle rouge n'est pas forcément une panne injectée : ce peut être la conséquence d'une autre.
</details>

**Pour aller plus loin** : fais-toi injecter une astreinte par quelqu'un d'autre (`--variante` tirée par lui) et chronomètre le temps jusqu'au **premier diagnostic juste** ; compare-le au temps de rétablissement.

---

### M09-E44 — Sous le capot : pmxcfs, votequorum et le gestionnaire HA  `LAB` `★★★`

> **Ticket PLAT-1081** — *De : Karim Benali*
> Pendant les pannes, tu as vu `/etc/pve` passer en lecture seule, des votes attendus changer en mémoire, une HA qui abandonne et des nœuds qui se clôturent. Je veux que tu saches **montrer** ce qu'il y a dessous : où vit vraiment `/etc/pve`, comment Corosync décide du quorum, comment le CRM et les LRM se parlent, et qui tient le watchdog. Compte rendu pour les prochains arrivants, sans rien casser.

**Objectifs pédagogiques**
- Observer pmxcfs : base SQLite locale, fichiers virtuels (`.members`, `.vmlist`, `.version`, `.clusterlog`, `.rrd`), droits imposés, propagation d'une écriture.
- Lire l'état interne de Corosync et de votequorum dans la base de configuration et d'exécution (`corosync-cmapctl`) et avec `corosync-quorumtool`.
- Suivre le gestionnaire HA : `manager_status`, `lrm_status`, verrous de l'agent, watchdog (`watchdog-mux`, `softdog`) et chronologie d'une clôture.

**Prérequis** : M09-E13, M09-E24 ; paliers 1 à 3 ; idéalement M09-E35 et M09-E42.
**Durée indicative** : 3 h.

**Contexte technique**
- La base de pmxcfs est `/var/lib/pve-cluster/config.db` (SQLite, table `tree`). Elle contient **tout** `/etc/pve`, y compris `/etc/pve/priv` (clés, secrets de stockage) : on ne la copie jamais hors du nœud, on ne l'ouvre qu'en lecture seule.
- `corosync-cmapctl` lit la base clé-valeur de Corosync (configuration chargée `totem.*`, `quorum.*`, `nodelist.*`, et état d'exécution `runtime.*`).
- L'état du gestionnaire HA est dans `/etc/pve/ha/manager_status` (JSON écrit par le CRM maître) et `/etc/pve/nodes/<nœud>/lrm_status` (JSON écrit par chaque LRM).

> ⚠️ **Attention** : cet exercice est en **lecture seule** sur le cluster de production du module. Seule écriture permise : la description d'une VM de test que tu crées pour l'occasion (VMID 198, sans disque, supprimée à la fin), et une migration HA de cette VM si tu en as besoin. Ouvre la base SQLite exclusivement avec l'URI en lecture seule (`file:…?mode=ro`), installe `sqlite3` sur **un** nœud seulement si tu en as besoin (et note-le), et n'active **pas** le journal de débogage de Corosync dans `/etc/pve/corosync.conf` : si tu veux plus de détails, utilise `corosync-cmapctl` et `journalctl`.

**Travail demandé**
1. **pmxcfs.** Sur `hv01` : `findmnt /etc/pve`, `ls -la /etc/pve`, `cat /etc/pve/.members`, `cat /etc/pve/.version`, `head /etc/pve/.vmlist`. Ouvre la base en lecture seule et relève le schéma de la table `tree` et le nombre d'entrées :
   ```
   root@hv01:~# sqlite3 'file:/var/lib/pve-cluster/config.db?mode=ro' '.schema tree'
   root@hv01:~# sqlite3 'file:/var/lib/pve-cluster/config.db?mode=ro' 'SELECT count(*), max(version) FROM tree;'
   ```
   Crée la VM de test 198 (sans disque), change trois fois sa description depuis `hv02`, et observe sur `hv01` et `hv03` la valeur de `.version` et la ligne correspondante de la base. Essaie (et note l'erreur) un `chmod 777 /etc/pve/nodes/hv01/qemu-server/198.conf`.
2. **Corosync et votequorum.** Sur chaque nœud : `corosync-quorumtool -s` et `-l`, `corosync-cfgtool -s`. Puis `corosync-cmapctl | grep -E '^(totem\.|quorum\.|nodelist\.node\.[0-9]+\.(name|nodeid|ring)|runtime\.votequorum)'`. Relève : `token`, `token_coefficient`, le *token timeout* effectif (`runtime.config.totem.token`), les votes de chaque nœud, l'identifiant de nœud qui décide en cas d'égalité, l'état des liens knet.
3. **Calcule** le temps qu'il faut à Corosync pour déclarer un nœud perdu avec ta configuration (3 nœuds), puis le temps avant qu'un nœud isolé qui porte une ressource HA se clôture, puis le temps avant que ses ressources redémarrent ailleurs. Compare avec ta mesure de M09-E24.
4. **Gestionnaire HA.** `ha-manager status -v`, `cat /etc/pve/ha/manager_status | python3 -m json.tool` (ou `jq` sur `adm01` après copie de **ce seul fichier**), `cat /etc/pve/nodes/*/lrm_status`. Déplace la VM 198 (mise sous HA pour l'occasion) avec `ha-manager crm-command migrate vm:198 hv03` et relève la suite des états dans `manager_status` (une lecture par seconde, `watch -n1`). Retire-la de la HA et supprime-la.
5. **Watchdog.** `systemctl status watchdog-mux`, `ls -l /run/watchdog-mux.sock`, `lsmod | grep -E 'softdog|wdt'`, `cat /etc/default/pve-ha-manager`. Explique qui ouvre `/dev/watchdog`, qui le « nourrit », dans quelles conditions il cesse de l'être, et pourquoi un `softdog` dans une VM est acceptable pour le lab et pas pour la production.
6. **Compte rendu.** Rédige `docs/virtualisation/analyses/cluster-hv-par1-sous-le-capot.md` : une section `## pmxcfs`, une section `## Corosync et votequorum`, une section `## Gestionnaire HA et watchdog` (extraits annotés, schéma des échanges CRM/LRM), puis `## Réponses aux questions`. Aucun secret, aucune clé, aucun extrait de `/etc/pve/priv`.

**Questions d'analyse** (à traiter dans le compte rendu)
1. Pourquoi `/etc/pve` est-il limité en taille (fichiers de quelques centaines de Kio au plus, base de quelques dizaines de Mio) et qu'est-ce que cela interdit d'y ranger ?
2. Qu'est-ce qui garantit que deux nœuds n'écrivent pas en même temps le même fichier de `/etc/pve` ? Que se passe-t-il quand une partition minoritaire revient avec des modifications ?
3. Pourquoi `/etc/pve/corosync.conf` porte-t-il un `config_version`, et pourquoi l'édite-t-on par copie `.new` puis renommage ?
4. Quelle est la différence entre `expected_votes` (configuration), `pvecm expected` (mémoire) et `Total votes` ? Quel risque prend-on avec `pvecm expected 1` sur un nœud isolé d'un cluster de trois ?
5. Avec deux liens knet en mode `passive`, que se passe-t-il quand le lien 0 tombe ? Quel lien Corosync utilise-t-il et comment le vois-tu ?
6. Pourquoi le CRM est-il un **maître unique** élu (verrou dans pmxcfs), et que fait un LRM qui perd le contact avec lui ?
7. Décris la chronologie d'une clôture : de la perte du quorum à la reprise des ressources ailleurs, avec les délais de ta configuration. Pourquoi le CRM attend-il que le verrou de l'agent du nœud perdu expire avant de relancer ses ressources ?
8. Cite une panne de M09-E35 à M09-E42 que chacune des trois parties de ton exploration aurait permis de localiser en moins de 5 minutes, et la ligne décisive.

**Critères de réussite**
- [ ] Le compte rendu existe, est commité, contient les quatre sections et cite `config.db`, `corosync-cmapctl`, `corosync-quorumtool`, `manager_status` et `watchdog-mux` avec des extraits annotés.
- [ ] Les 8 questions sont traitées ; le compte rendu ne contient ni clé, ni jeton, ni secret.
- [ ] La VM 198 est supprimée, aucune capture ne tourne, aucune copie de `config.db` n'existe hors de `/var/lib/pve-cluster/` (ni sur les nœuds, ni sur `adm01`), le débogage de Corosync n'est pas activé.

**Vérification** : `lab/bin/check 09 44`

<details><summary>Indice 1</summary>

Dans la table `tree`, chaque entrée a un `inode`, un `parent`, une `version`, un `name` et des `data`. `.version` de `/etc/pve` suit la plus grande version de la base. `corosync-cmapctl -g <clé>` lit une seule clé.
</details>

<details><summary>Indice 2</summary>

Le *token timeout* effectif d'un cluster de N nœuds vaut `token + (N − 2) × token_coefficient` (voir `man corosync.conf`). Le délai du watchdog et celui du verrou de l'agent HA sont dans la documentation de `ha-manager` (section *Fencing*).
</details>

**Pour aller plus loin** : lis le code de `pve-ha-manager` (fichiers `Manager.pm` et `LRM.pm` du dépôt git de Proxmox) et retrouve la boucle qui écrit `manager_status` ; compare les noms d'états avec ceux que tu as observés. Documentation : [pmxcfs](https://pve.proxmox.com/pve-docs/chapter-pmxcfs.html), [High Availability — How It Works et Fencing](https://pve.proxmox.com/pve-docs/chapter-ha-manager.html), `man corosync-cmapctl`, `man votequorum`.

---

### M09-E45 — Questions expert : cluster Proxmox  `Q` `★★★`

> **Ticket PLAT-1082** — *De : Karim Benali*
> Dernière étape avant la recette du module : ces questions, je les pose en entretien pour un poste d'ingénieur plateforme senior qui aura la main sur nos hyperviseurs. Réponds par écrit, en argumentant. Pas de recherche pendant la première passe ; vérifie ensuite dans la doc et corrige-toi en couleur.

**Objectifs pédagogiques**
- Consolider la compréhension des mécanismes internes manipulés dans ce module (quorum, Corosync, pmxcfs, HA, fencing, Ceph hyperconvergé, migration, réplication, sauvegarde).
- S'entraîner à argumenter une réponse technique comme en entretien ou en revue d'architecture.

**Prérequis** : paliers 1 à 3 du module, M09-E44.
**Durée indicative** : 2 h 30.

**Questions**

1. Explique la différence entre *membership* (membre Corosync) et *quorum*. Peut-on avoir l'un sans l'autre ? Donne un exemple de chaque cas sur un cluster de trois nœuds.
2. QCM — Un cluster de quatre nœuds (un vote chacun, sans QDevice) est coupé en deux moitiés de deux nœuds. Que se passe-t-il ?
   a) la moitié qui contient le nœud d'identifiant le plus bas garde le quorum ; b) aucune moitié n'a le quorum ; c) les deux moitiés gardent le quorum ; d) la moitié qui porte le CRM maître garde le quorum.
3. Pourquoi un QDevice est-il recommandé pour un nombre **pair** de nœuds et déconseillé pour un nombre impair ? Explique l'algorithme `ffsplit` et ce qu'il change pour un cluster de trois nœuds.
4. Deux liens knet : à quoi sert `link_mode: passive`, et pourquoi le réseau Corosync ne doit-il pas partager un lien saturé avec la migration ou le stockage ? Que se passe-t-il concrètement quand le *token* expire ?
5. QCM — Sur un nœud sans quorum, laquelle de ces actions réussit ?
   a) démarrer une VM ; b) lire `/etc/pve/qemu-server/100.conf` ; c) modifier la mémoire d'une VM arrêtée ; d) créer un jeton d'API.
6. Que contient `/etc/pve/priv` et pourquoi ce dossier n'est-il lisible que par root ? Quelles conséquences pour la sauvegarde de `config.db` (M09-E29) ?
7. Décris la procédure correcte pour modifier `/etc/pve/corosync.conf` (par exemple ajouter un lien), et ce qui se passe si on édite directement `/etc/corosync/corosync.conf` sur un nœud.
8. Fencing : pourquoi Proxmox VE se contente-t-il d'un watchdog (matériel ou `softdog`) plutôt que d'un fencing externe (IPMI, PDU) ? Dans quel cas un watchdog seul est-il insuffisant ?
9. QCM — Une ressource HA est en `error`. Quelle séquence la remet en service proprement après correction ?
   a) `ha-manager remove` puis `ha-manager add` ; b) passage à l'état `disabled`, correction, puis passage à `started` ; c) `qm start` directement sur un nœud ; d) redémarrer `pve-ha-crm` sur le maître.
10. HA *rules* de Proxmox VE 9 : compare une règle `node-affinity` stricte et non stricte, et une règle `resource-affinity` positive et négative. Donne un jeu de règles qui devient impossible pendant la maintenance d'un nœud, et une façon de l'écrire qui ne l'est pas.
11. Mode maintenance (`node-maintenance enable`), `disarm-ha` (`freeze`, `ignore`) et `ha-manager set --state ignored` : quand utiliser chacun ?
12. Ceph hyperconvergé dans un cluster de trois nœuds : pourquoi `size 3 / min_size 2` avec un domaine de panne « hôte » ? Que se passe-t-il pour les écritures quand un nœud est en maintenance, puis quand un second OSD tombe sur un autre nœud ?
13. Pourquoi ne faut-il **pas** placer le réseau Corosync sur le même lien que le réseau cluster de Ceph, même avec de la QoS ? Pourquoi un OSD remplit-il ses battements de cœur jusqu'à 2000 octets ?
14. QCM — Une migration à chaud échoue avec un disque sur `local-lvm`. Quelle option est la bonne pour une VM de production à migrer maintenant ?
    a) `--with-local-disks` après avoir vérifié la place et la durée du transfert ; b) `--force` ; c) arrêter la VM et migrer hors ligne ; d) changer le type de migration en `insecure`.
15. Réplication ZFS (`pvesr`) et Ceph : compare RPO, RTO, consommation réseau, comportement en cas de perte de nœud avec la HA. Pour quelles VMs MédiSphère choisirais-tu l'une ou l'autre ?
16. Sauvegarde PBS : explique la sauvegarde incrémentale par *dirty bitmap*, ce qui la fait repartir en complet, et ce que protège le chiffrement côté client (et ce qu'il ne protège pas).
17. Un nœud doit être remplacé (carte mère morte, disques perdus). Décris la procédure complète : retrait du cluster, Ceph, nouvelle installation, réadhésion, et les pièges (même nom, même adresse, clés SSH connues, `known_hosts`).
18. QCM — Après la remise en route d'un nœud resté arrêté trois semaines, que faut-il vérifier **avant** de le laisser rejoindre ?
    a) rien, Corosync synchronise tout ; b) sa version de paquets, son heure, et que son `config_version` local ne soit pas incohérent avec celui du cluster ; c) seulement les OSD Ceph ; d) seulement les certificats.
19. Mises à jour du cluster : pourquoi un nœud à la fois, avec quel ordre pour Proxmox VE et pour Ceph, et quelles vérifications entre deux nœuds (RB-092) ?
20. Ton directeur te demande d'étendre le cluster à un quatrième nœud à PAR2, relié par le tunnel WireGuard. Que réponds-tu, chiffres de latence à l'appui, et que proposes-tu à la place ?

**Critères de réussite**
- [ ] Les 20 questions ont une réponse écrite et argumentée (pour les QCM : la bonne réponse **et** pourquoi les autres sont fausses).
- [ ] Après correction, tu as identifié tes trois points les plus faibles et noté un exercice ou une lecture pour chacun.

<details><summary>Indice 1</summary>

Pour 1 à 7, ton compte rendu de M09-E44, `man votequorum`, `man corosync.conf` et le chapitre *Cluster Manager* ; pour 8 à 11, le chapitre *High Availability* (sections *Fencing*, *Rules*, *Error Recovery*, *Maintenance*).
</details>

<details><summary>Indice 2</summary>

Pour 12 à 16, la documentation de Ceph (*Pools*, *Placement Group States*, *Network Configuration Reference*) et les chapitres *Storage Replication* et *Backup and Restore* ; pour 17 à 20, tes runbooks RB-090 à RB-094 et ton ADR-0090.
</details>

**Pour aller plus loin** : choisis trois questions et transforme chacune en mini-démonstration sur le lab (5 minutes, reproductible, sans geste destructif), à présenter à Karim.
