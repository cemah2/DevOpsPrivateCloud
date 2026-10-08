# Module 08 — Palier 4 : Expert

`ceph-par1` est en service : trois nœuds permanents et `ceph04` (retiré au mini-projet), douze OSD, des pools répliqués et à codes d'effacement, des images RBD, un CephFS, une passerelle S3 derrière sa VIP, une supervision et des sauvegardes. Nadia Roussel pose la question qu'elle avait posée au début du module : « Et à 3 h du matin, quand un disque, un moniteur ou un client tombe, qui sait quoi faire ? » Karim Benali a préparé huit pannes, toutes de celles que les forums et les post-mortems publics racontent : un OSD qui disparaît, des PG qui restent inactifs, un cluster qui refuse d'écrire, des moniteurs sans quorum, un client RBD refusé, un S3 en erreur, un CephFS figé, un cluster lent. Une astreinte les combine. Puis tu descends sous le capot, jusqu'à l'endroit précis où un objet est rangé, et tu passes les questions qu'on pose en entretien.

La méthode reste celle des modules précédents : observer avant d'agir, formuler une hypothèse, la tester par la mesure la moins invasive, corriger à la racine, prévenir la récidive. Avec trois règles propres au stockage distribué :
- **Ceph dit presque toujours ce qui ne va pas.** `ceph health detail` donne un code (`OSD_DOWN`, `PG_AVAILABILITY`, `POOL_FULL`, `MON_CLOCK_SKEW`…) et la liste des objets concernés. Lis-le en entier avant de lancer quoi que ce soit, et cherche le code dans la [liste des contrôles de santé](https://docs.ceph.com/en/tentacle/rados/operations/health-checks/).
- **Ne transforme jamais une panne en perte de données.** Un OSD « down » n'est pas un disque mort ; un PG inactif n'est pas un PG perdu. Les commandes qui effacent (`ceph osd purge`, `ceph osd destroy`, `ceph orch osd rm --zap`, `ceph-volume lvm zap`, `ceph osd pool delete`) et celles qui renoncent à des données (`ceph osd lost`, `ceph pg … mark_unfound_lost`, `ceph osd force-create-pg`) sont **interdites** dans ce palier. Aucune des pannes n'en a besoin.
- **Distingue le démon, le conteneur, l'unité et l'orchestrateur.** Avec cephadm, un démon Ceph est un conteneur Podman lancé par une unité systemd `ceph-<fsid>@<type>.<id>.service`, que l'orchestrateur (`ceph orch`) observe et pilote. Une panne peut se loger à chacun de ces étages, et chacun a son outil : `ceph orch ps`, `systemctl status`, `podman ps`, `cephadm logs --name …`, `journalctl -u …`.

> **Rappels** : tout se lance depuis `adm01`. Le trousseau admin est sur `ceph01` (variable `WB_CEPH_ADMIN` de `lab/lab.env`) ; les commandes `ceph` s'y lancent directement ou dans `sudo cephadm shell`. Les spécifications du cluster sont dans le projet `plateforme/ceph` (`~/src/ceph`, M08-E23) ; la documentation dans `~/medisphere` (variable `WB_DEPOT`). Une réparation à chaud est permise pour rétablir le service ; si elle touche ce qui est décrit par le code (spécification cephadm, règle CRUSH, réglage de pool), elle doit être reportée ensuite dans `plateforme/ceph` par une MR, sinon le prochain `ceph orch apply` ou la prochaine revue la défera.

## Règles du jeu des pannes (M08-E35 à M08-E43)

- Les pannes s'injectent **depuis `adm01`**, à la racine de ta copie du workbook :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ lab/bin/break 08 35
  ```
  Le script tire une variante au hasard et n'affiche que le **symptôme**, comme un ticket. Chaque panne a 3 ou 4 variantes : refais l'exercice jusqu'à les avoir toutes rencontrées (`--variante N` force une variante, sans dire laquelle est laquelle). Si une variante n'a pas d'effet sur ton lab, le script en essaie une autre. Une injection prend de quelques secondes à trois minutes (il attend que Ceph constate la panne).
- **Avant d'injecter**, lance le contrôle de l'exercice (`lab/bin/check 08 35`) : il doit être vert. Le script de panne refuse d'ailleurs de casser un cluster qui n'est pas `HEALTH_OK` (quorum complet, OSD tous `up` et `in`, PG tous `active+clean`, aucun drapeau `noout`/`pause`).
- **Témoins.** À la première injection, le script crée (s'ils n'existent pas) des **témoins** qui jouent le rôle des applications et qu'il ne supprime jamais :
  - le compte `client.sonde` (droits RBD sur le pool `rbd-test`) et l'image `rbd-test/sonde` (1 Gio, ext4), montée sur `cephcli01` en `/mnt/sonde` ;
  - le compte `client.sonde-fs` (racine du CephFS `cephfs` en lecture-écriture), monté sur `cephcli01` en `/mnt/sonde-fs` ;
  - l'utilisateur RGW `sonde-s3`, son compartiment `sonde` et l'objet `temoin` ; ses identifiants sont sur `cephcli01` dans `/etc/workbook/sonde-s3.curl` (mode 600, format de configuration de `curl`, à lire avec `curl -K`, jamais à afficher) ;
  - la sonde `/usr/local/sbin/wb-sonde-stockage` sur `cephcli01` : `sudo wb-sonde-stockage` écrit et relit sur les deux montages et fait un GET et un PUT S3, avec un délai de 20 s par essai. C'est ton premier instrument de reproduction : lis-la, elle ne contient aucune cause.

  Les témoins restent après le palier (ils servent aussi à l'astreinte). Ils ne gênent pas le mini-projet ; tu peux les supprimer après la recette (M08-E46), toi-même, en vérifiant deux fois ce que tu supprimes.
- **Ne lis pas** les scripts de `corrige/pannes/`, ni `/var/lib/workbook/` sur les hôtes, ni `~/.local/state/workbook/` sur `adm01` : ils contiennent la cause.
- Une seule panne active à la fois par exercice. Si tu abandonnes : `lab/bin/break 08 35 --annuler` remet l'état sain (filet de sécurité, pas un correctif : compte l'exercice comme non réussi). **Quand tu as réparé**, lance aussi `--annuler` pour **clore** la panne (sinon elle reste marquée active et bloque l'astreinte M08-E43 et le mini-projet) : l'annulation ne rétablit que ce qui est encore dans l'état cassé et ne revient jamais sur ta réparation.
- Les pannes n'agissent que sur `ceph01-03` et `cephcli01` (SSH, utilisateur `admin` + sudo), et sur la configuration du cluster par le trousseau admin. Jamais sur `pve01`, son réseau ou son pare-feu, jamais sur `pbs01`, jamais sur une VM hors du pool `lab`. **Aucune donnée n'est détruite** : aucun disque n'est détaché ni effacé, aucun OSD purgé, aucun pool ni objet supprimé ; toute valeur modifiée est sauvegardée avant.
- **Tiens un journal de diagnostic** pour chaque panne, dans `docs/socle/journal/` de `~/medisphere` (publié par MR) : heure, hypothèse, commande, résultat observé, conclusion. Il alimente le post-mortem de M08-E43.
- Le **temps cible** est indicatif. Le dépasser n'est pas un échec ; corriger sans comprendre en est un.

> ⚠️ **Accès de secours** : M08-E38 peut te priver de toute commande `ceph` (plus de quorum), et M08-E42 peut rendre un nœud très lent à répondre. Vérifie **avant** d'injecter que tu sais entrer sur `ceph01-03` sans SSH : console série (`qm terminal 2081` depuis `pve01`, sortie par `Ctrl+O`) et agent QEMU (`qm guest cmd 2081 ping` doit répondre). Sur un nœud Ceph, les sockets d'administration des démons (`ceph daemon <démon> …`, dans `sudo cephadm shell --name <démon>`) répondent même sans quorum.

> ⚠️ **Pare-feu des nœuds Rocky** : `firewalld` gère ses propres tables nftables (`inet firewalld`). Pour retirer une règle posée à côté de lui, supprime **la** table ou **la** règle en cause (`nft delete table …`, `nft delete rule … handle N`), jamais `nft flush ruleset` : cette commande efface aussi les règles de `firewalld` et coupe l'accès aux services du nœud jusqu'au prochain `firewall-cmd --reload`.

> ⚠️ **Avant toute action sur un OSD ou une règle CRUSH**, pose-toi deux questions et écris la réponse dans ton journal : « combien de copies de chaque PG restent disponibles si je fais ça ? » et « est-ce que ça déclenche un déplacement de données, et de combien ? ». `ceph osd ok-to-stop <id>` et `ceph osd safe-to-destroy <id>` répondent à la première pour les OSD.

---

### M08-E35 — Panne : un OSD a disparu  `BF` `★★`

> **Ticket INC-3541** — *De : Nadia Roussel*
> *(Le détail du ticket s'affiche à l'injection : selon le cas, une alerte « 1 osds down » de la nuit, ou une capacité utile en baisse sans alerte rouge.)* Lucas propose de « purger l'OSD et de le recréer » : n'en fais rien avant d'avoir compris ce qui est arrivé.

**Objectifs pédagogiques**
- Distinguer les états d'un OSD : `up`/`down` (le démon répond-il ?) et `in`/`out` (reçoit-il des données ?), et ce que fait Ceph de lui-même entre les deux (`mon_osd_down_out_interval`).
- Remonter du symptôme Ceph à l'étage en cause : orchestrateur, unité systemd, conteneur, démon, périphérique (noyau de l'invité), décision d'un administrateur.
- Faire revenir un OSD sans perte et sans déplacement de données inutile, et savoir quand il faut au contraire le remplacer (RB-080, M08-E22).

**Prérequis** : M08-E04, M08-E07, M08-E19, M08-E22 ; `lab/bin/check 08 35` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : chaque nœud porte trois OSD (deux sur `ssd-lab`, un sur `hdd-bulk`), sur des disques SCSI de l'invité (`/dev/sdb` à `/dev/sdd`) découpés en volumes LVM par `ceph-volume`. L'unité systemd d'un OSD s'appelle `ceph-<fsid>@osd.<id>.service` ; `cephadm ls` (sur le nœud, en root) liste les démons du nœud et leur état. Le journal d'audit du cluster garde la trace des commandes passées par les administrateurs (`ceph log last … audit` : consulte `ceph log last --help`).

**Injection** : `lab/bin/break 08 35` (3 variantes).

**Travail demandé**
1. Constate l'état sans rien toucher : santé détaillée, arbre des OSD, occupation par OSD. Quel OSD, sur quel hôte ? Est-il `down`, `out`, les deux ? Depuis quand (journal du cluster) ? Que va faire Ceph de lui-même si personne n'intervient, et dans combien de temps ?
2. Avant toute action, protège le cluster d'un déplacement de données inutile si c'est pertinent, et note pourquoi (ou pourquoi ce n'est pas nécessaire ici).
3. Descends les étages sur l'hôte concerné : que dit l'orchestrateur, que dit systemd, le conteneur existe-t-il, que disent les journaux du démon et du noyau ? Le disque est-il vu par l'invité, dans quel état ?
4. Trouve la cause racine et fais revenir l'OSD **sans** le recréer. Si la cause est une décision d'un administrateur, retrouve-la (qui, quand, quelle commande).
5. Retire toute protection posée à l'étape 2, attends le retour à `HEALTH_OK` et note le temps de récupération.
6. Rédige `RB-083 — OSD hors service` dans `docs/stockage/runbooks/` : arbre de décision « l'OSD peut-il revenir ? » (démon, unité, disque, décision humaine) avant de renvoyer vers RB-080 (remplacement).

**Critères de réussite**
- [ ] Tous les OSD sont `up` et `in`, aucune unité `ceph-*` n'est masquée ou en échec sur `ceph01-03`, tous les disques SCSI des nœuds sont en état `running`.
- [ ] Aucun drapeau `noout` (ni `noup`, `noin`, `nodown`) n'est resté posé ; la santé ne signale ni `OSD_DOWN` ni PG dégradé.
- [ ] Ton journal contient la sortie de `ceph health detail` initiale, l'étage en cause et la preuve (ligne de journal, état de l'unité, état du disque ou entrée du journal d'audit) ; RB-083 est publié.

**Vérification** : `lab/bin/check 08 35`

<details><summary>Indice 1</summary>

`ceph osd tree` (colonnes `STATUS` et `REWEIGHT`) et `ceph osd df tree` (colonne `PGS`) répondent à « down ou out ? ». `ceph orch ps --daemon-type osd` donne l'état vu par l'orchestrateur, `systemctl status 'ceph-*@osd.*'` sur le nœud celui vu par systemd. Un message comme `Unit … is masked` n'est pas une erreur de Ceph.
</details>

<details><summary>Indice 2</summary>

`cephadm logs --name osd.<id>` (sur le nœud) montre la fin de vie du démon. `dmesg -T | tail` et `lsblk` disent ce que le noyau de l'invité pense du disque ; `cat /sys/block/sdX/device/state` donne l'état du périphérique SCSI. Un OSD `up` mais sans aucun PG n'est pas en panne : quelqu'un, ou quelque chose, l'a sorti du placement.
</details>

<details><summary>Indice 3</summary>

`ceph osd set noout` empêche le passage automatique à `out` pendant que tu travailles ; il se retire par `ceph osd unset noout`. Un OSD revenu `up` qui avait été sorti automatiquement est remis `in` par Ceph ; un OSD sorti à la main ne l'est pas.
</details>

**Pour aller plus loin** : compare le temps de retour à `HEALTH_OK` selon que l'OSD revient avant ou après `mon_osd_down_out_interval`, et mesure le volume déplacé dans chaque cas (`ceph -s`, ligne `recovery`). Lis la page [Troubleshooting OSDs](https://docs.ceph.com/en/tentacle/rados/troubleshooting/troubleshooting-osd/).

---

### M08-E36 — Panne : des PG restent inactifs  `BF` `★★★`

> **Ticket INC-3542** — *De : Julien Petit*
> Depuis ce matin, toute écriture sur le volume RBD de test de `cephcli01` (`/mnt/sonde`, image `rbd-test/sonde`) reste bloquée : pas d'erreur, rien ne bouge. Lucas dit avoir « appliqué la nouvelle politique de stockage » sur ce pool hier soir. `ceph -s` parle de PG inactifs. Remets le pool en service sans perdre une seule donnée, puis dis-moi ce qu'il fallait faire pour appliquer proprement ce que Lucas voulait.

**Objectifs pédagogiques**
- Lire les états de PG (`active`, `peered`, `undersized`, `degraded`, `remapped`, `unknown`, `stale`) et ce que chacun implique pour les clients.
- Relier un PG inactif à sa cause de placement : `size` et `min_size` du pool, règle CRUSH (racine, classe, domaine de panne), OSD disponibles.
- Tester une règle CRUSH **avant** de l'appliquer (`crushtool --test`) et mesurer le déplacement qu'elle provoquera.

**Prérequis** : M08-E05, M08-E14, M08-E21 ; `lab/bin/check 08 36` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : un PG est `active` quand il a au moins `min_size` copies disponibles dans son ensemble actif (*acting set*) ; en dessous, il est seulement `peered` et refuse les E/S. Les clients RBD n'échouent pas : ils **attendent**. Le cluster a trois baies CRUSH (`par1-baie-a` à `-c`, M08-E14 ; `ceph04` partage la baie A tant qu'il existe), chaque hôte avec des OSD de classe `ssd` et `hdd` ; `rbd-test` suit la règle `ssd-baie`.

**Injection** : `lab/bin/break 08 36` (3 variantes).

**Travail demandé**
1. Constate : combien de PG, de quels pools, dans quels états ? Prends un PG inactif et demande à Ceph son ensemble *up* et *acting* ; compare-le à un PG sain d'un autre pool.
2. Pour ce PG, explique pourquoi il n'est pas actif : combien de copies Ceph veut-il, combien en exige-t-il pour servir, combien la règle CRUSH peut-elle en placer ? Montre les trois nombres.
3. Lis la règle CRUSH du pool (et sa source : classe, racine, domaine de panne). Prouve hors ligne, avec la carte CRUSH extraite et `crushtool`, ce que cette règle sait placer.
4. Remets le pool en service par la correction la plus sûre, sans supprimer de donnée, de règle utilisée ou de classe dont un autre pool dépend. Vérifie que les écritures reprennent sur `/mnt/sonde`.
5. Réponds à Julien : comment aurait-il fallu appliquer la « politique » de Lucas (simulation préalable, mesure du déplacement, fenêtre, MR sur `plateforme/ceph`) ? Si elle était irréalisable sur ce cluster, dis-le et propose une alternative.

**Critères de réussite**
- [ ] Aucun PG inactif, tous les PG `active+clean` ; `rbd-test` en `size 3` / `min_size 2` sur une règle qui part de la racine `default`.
- [ ] Aucun OSD dans une classe sans équivalent matériel, aucune règle ne vise une racine vide.
- [ ] `sudo wb-sonde-stockage` est vert pour RBD ; ton journal contient les trois nombres de l'étape 2, la sortie `crushtool --test` qui prouve la cause et ta réponse à Julien.

**Vérification** : `lab/bin/check 08 36`

<details><summary>Indice 1</summary>

`ceph health detail` liste les PG concernés ; `ceph pg ls-by-pool rbd-test` et `ceph pg dump_stuck inactive` donnent leurs états ; `ceph pg map <pgid>` et `ceph pg <pgid> query` donnent les ensembles *up* et *acting*. Un ensemble vide ou plus court que `size` est un indice de placement, pas de panne matérielle.
</details>

<details><summary>Indice 2</summary>

`ceph osd pool get rbd-test all`, `ceph osd crush rule dump <règle>`, `ceph osd crush tree --show-shadow` (les arbres « fantômes » par classe, `default~ssd`…), `ceph osd crush class ls-osd <classe>`. Pour tester : `ceph osd getcrushmap -o crush.bin` puis `crushtool -i crush.bin --test --rule <id> --num-rep <n> --show-bad-mappings`.
</details>

<details><summary>Indice 3</summary>

Change d'abord ce qui rend les PG actifs le plus vite et le plus sûrement (la règle ou la réplication du pool), puis seulement les objets qui ont servi à la manœuvre ratée. Une règle ne se supprime que si aucun pool ne l'utilise ; une classe se rend à un OSD par `rm-device-class` puis `set-device-class`.
</details>

**Pour aller plus loin** : écris dans `plateforme/ceph` un test de pipeline qui, pour chaque pool et sa règle, lance `crushtool --test --show-bad-mappings` avec la `size` du pool sur la carte CRUSH courante et échoue s'il y a une seule mauvaise correspondance. Lis [Placement Groups — stuck](https://docs.ceph.com/en/tentacle/rados/troubleshooting/troubleshooting-pg/).

---

### M08-E37 — Panne : plus aucune écriture  `BF` `★★★`

> **Ticket INC-3543** — *De : Nadia Roussel*
> Les écritures sur le stockage de test sont bloquées depuis 20 minutes : la sonde de `cephcli01` (`sudo wb-sonde-stockage`) reste sans réponse, sans message d'erreur côté client. Karim a fait une intervention de maintenance cette nuit et dit avoir « tout remis comme avant ». Rétablis les écritures, et dis-moi si on risque que ça recommence demain.

**Objectifs pédagogiques**
- Connaître les mécanismes qui suspendent les écritures **par conception** : seuils `nearfull`/`backfillfull`/`full` des OSD, quotas de pool, drapeaux de la carte des OSD (`pause`, `full`), et ce que chacun bloque (lectures ? écritures ? récupération ?).
- Distinguer occupation brute (`RAW USED`), données stockées (`STORED`) et disponible utile (`MAX AVAIL`) dans `ceph df`.
- Lever un blocage sans créer le suivant (un seuil remonté trop haut, un quota supprimé sans réflexion, un `noout` oublié).

**Prérequis** : M08-E20, M08-E24, M08-E26 ; `lab/bin/check 08 37` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : quand un OSD dépasse `full_ratio`, Ceph marque pleins les pools qui l'utilisent et refuse les écritures des clients (ils attendent) ; la suppression de données reste possible. Les valeurs par défaut sont 0,85 (`nearfull`), 0,90 (`backfillfull`) et 0,95 (`full`) ; `ceph-par1` a les siennes depuis M08-E20 (`config/cluster.yaml` de `plateforme/ceph`). Elles sont stockées dans la carte des OSD (`ceph osd dump | grep ratio`), pas dans la base de configuration.

**Injection** : `lab/bin/break 08 37` (3 variantes).

**Travail demandé**
1. Reproduis avec la sonde, puis confirme côté Ceph : quel contrôle de santé, sur quels OSD ou quels pools ? Les lectures passent-elles encore ? (Essaie de lire le témoin avec un délai.)
2. Compare l'occupation réelle (`ceph df detail`, `ceph osd df`) aux seuils et aux quotas. L'espace manque-t-il vraiment ?
3. Retrouve ce qui a été changé pendant la « maintenance », et par qui (journal d'audit).
4. Corrige en remettant la valeur **juste** (pas « la plus grande possible ») et justifie-la. Vérifie que la sonde repasse au vert.
5. Rédige `RB-084 — Écritures bloquées (cluster ou pool plein)` dans `docs/stockage/runbooks/` : diagnostic en trois commandes, cas « vraiment plein » (que supprimer, quoi ajouter, jusqu'où remonter temporairement `full_ratio` et pourquoi c'est dangereux), cas « faux plein » (seuil, quota, drapeau), retour arrière.

**Critères de réussite**
- [ ] `full_ratio` entre 0,90 et 0,97, seuils ordonnés (`nearfull` < `backfillfull` < `full`), aucun OSD ni pool plein ou presque plein.
- [ ] Quota de `rbd-test` absent ou supérieur à 1 Gio ; aucun drapeau `pause` ni `noout`.
- [ ] La sonde est verte ; ton journal contient le contrôle de santé initial, la preuve de la modification (audit) et la justification de la valeur remise ; RB-084 est publié.

**Vérification** : `lab/bin/check 08 37`

<details><summary>Indice 1</summary>

`ceph health detail` ; `ceph osd dump | grep -E 'flags|ratio'` ; `ceph osd pool get-quota rbd-test` ; `ceph df detail`. Un drapeau de la carte des OSD apparaît aussi dans `ceph -s` (ligne `flags`).
</details>

<details><summary>Indice 2</summary>

`ceph log last 100 debug audit` (adapte selon `ceph log last --help`) montre les commandes `osd set`, `osd set-full-ratio`, `osd pool set-quota` avec l'entité qui les a passées. Les commandes pour remettre en ordre ont la même forme que celles qui ont cassé.
</details>

**Pour aller plus loin** : ajoute à `ms-verif-ceph` (M08-E24) un contrôle des seuils (valeurs attendues), des quotas proches de la saturation (> 80 %) et des drapeaux de maintenance posés depuis plus de 4 h.

---

### M08-E38 — Panne : les moniteurs perdent le quorum  `BF` `★★★`

> **Ticket INC-3544** — *De : Nadia Roussel*
> *(Le détail s'affiche à l'injection : selon le cas, un moniteur hors quorum et des commandes lentes, ou plus aucune réponse de `ceph -s` ni du tableau de bord.)* InfoGér a travaillé sur les nœuds cette nuit (« durcissement », « mises à jour »).

**Objectifs pédagogiques**
- Comprendre le quorum Paxos des moniteurs : majorité stricte de la *monmap*, élections, baux (*leases*), et pourquoi l'horloge compte (`mon_clock_drift_allowed`).
- Interroger un moniteur **sans quorum** par son socket d'administration, et lire `mon_status` (état, rang, quorum, pairs connus).
- Diagnostiquer une partition réseau partielle (ports msgr2 3300 et msgr1 6789) et un décalage d'horloge, sans toucher à la *monmap*.

**Prérequis** : M08-E03, M08-E07, M08-E24, M08-E27 ; M00-E31 (temps synchronisé) ; `lab/bin/check 08 38` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : trois moniteurs (`mon.ceph01`, `mon.ceph02`, `mon.ceph03`) : le quorum exige deux d'entre eux. Les nœuds se synchronisent par chrony sur la passerelle du VLAN 30 (10.10.30.1). Dans `sudo cephadm shell --name mon.<hôte>` (sur l'hôte du moniteur), `ceph daemon mon.<hôte> mon_status` interroge le moniteur localement, quorum ou pas.

> ⚠️ **Attention** : n'utilise **jamais** `monmaptool`, `ceph-mon --extract-monmap`/`--inject-monmap` ni la suppression d'un moniteur (`ceph mon remove`, `ceph orch daemon rm mon.…`) pour « retrouver le quorum ». Ces procédures de dernier recours existent pour la perte définitive de moniteurs ; ici, tous les magasins des moniteurs sont intacts.

**Injection** : `lab/bin/break 08 38` (3 variantes).

**Travail demandé**
1. Constate depuis `ceph01` : `ceph -s` répond-il, en combien de temps ? Si non, interroge chaque moniteur par son socket d'administration et note son état (`leader`, `peon`, `probing`, `electing`…) et le quorum qu'il voit.
2. Pour chaque moniteur hors quorum ou muet : son unité tourne-t-elle ? Joint-il les autres sur 3300 et 6789, et eux le joignent-ils ? Son horloge est-elle juste ?
3. Trouve la cause racine. Si c'est une règle réseau, identifie-la précisément (table, chaîne, règle) et retire **elle seule** ; si c'est l'horloge, remets la synchronisation en service et explique pourquoi l'horloge a dérivé ; si ce sont des démons arrêtés, relance-les en sachant pourquoi ils l'ont été.
4. Vérifie le retour : trois moniteurs en quorum, aucun `MON_CLOCK_SKEW`, et les OSD du nœud concerné toujours `up` (sinon, explique pourquoi ils sont tombés et fais-les revenir).
5. Rédige `RB-085 — Perte de quorum des moniteurs` dans `docs/stockage/runbooks/` : comment interroger un moniteur sans quorum, l'ordre des vérifications (unité, réseau, horloge, disque du moniteur), ce qu'il ne faut **pas** faire, et quand escalader vers une restauration de *monmap*.

**Critères de réussite**
- [ ] Trois moniteurs dans la carte, tous dans le quorum ; aucun `MON_CLOCK_SKEW` ni `MON_DOWN`.
- [ ] Sur `ceph01-03` : chronyd actif et synchronisé, ports 3300 et 6789 joignables depuis `adm01`, aucune règle nftables qui jette les ports Ceph, aucune unité `ceph-*` masquée ou en échec.
- [ ] Ton journal contient le `mon_status` d'au moins un moniteur pris pendant la panne et la cause racine ; RB-085 est publié.

**Vérification** : `lab/bin/check 08 38`

<details><summary>Indice 1</summary>

`timeout 20 ceph -s` évite d'attendre indéfiniment. `ceph quorum_status -f json-pretty` (avec quorum) et `ceph daemon mon.<hôte> mon_status` (sans) donnent `quorum_names`, `outside_quorum`, `state`. `ceph time-sync-status` compare les horloges vues par le chef.
</details>

<details><summary>Indice 2</summary>

Sur chaque nœud : `systemctl list-units 'ceph-*@mon.*'`, `ss -tlnp | grep -E ':3300|:6789'`, `timedatectl`, `chronyc tracking`, `sudo nft list ruleset` (cherche ce qui n'appartient pas à `firewalld`). Depuis un autre nœud : `timeout 3 bash -c '</dev/tcp/10.10.30.5X/3300' && echo ouvert`.
</details>

<details><summary>Indice 3</summary>

Un moniteur dont l'horloge avance voit les baux du chef expirer avant l'heure : il provoque des élections à répétition. chrony ne rattrape pas forcément un grand écart d'un coup : regarde la directive `makestep` de sa configuration et `chronyc makestep`.
</details>

**Pour aller plus loin** : mesure avec `ceph mon dump` et `ceph quorum_status` le temps d'une élection après l'arrêt du chef (`ceph orch daemon stop mon.<chef>`, avec deux autres moniteurs sains), puis relance-le. Lis [Troubleshooting Monitors](https://docs.ceph.com/en/tentacle/rados/troubleshooting/troubleshooting-mon/).

---

### M08-E39 — Panne : le client RBD est refusé  `BF` `★★`

> **Ticket INC-3545** — *De : Julien Petit*
> Après le redémarrage planifié de cette nuit, le volume RBD de test de `cephcli01` n'est plus monté : `/mnt/sonde` est vide et `sudo rbd device map --id sonde rbd-test/sonde` échoue. Le compte `client.sonde` n'a pas changé depuis des semaines, paraît-il. Remonte le volume, sans recréer l'image ni le compte : les données de l'image doivent rester intactes.

**Objectifs pédagogiques**
- Suivre l'ouverture d'une image RBD par le client noyau : lecture de `ceph.conf` et du trousseau, authentification cephx auprès des moniteurs, droits (`caps`) sur les moniteurs et les OSD, ouverture de l'en-tête de l'image, contrôle des fonctionnalités par le pilote `krbd`.
- Lire les deux moitiés du message : la commande `rbd` et le journal du noyau (`dmesg`).
- Corriger côté cluster ou côté client, selon où est l'écart, sans élargir les droits.

**Prérequis** : M08-E06, M08-E13 ; `lab/bin/check 08 39` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : `cephcli01` (Debian 13) utilise le client Ceph de Debian (`ceph-common`) et le pilote noyau `rbd` ; `rbd device map --id sonde` lit `/etc/ceph/ceph.conf` et `/etc/ceph/ceph.client.sonde.keyring`. Le montage n'est pas persistant (pas d'entrée `fstab`) : le remonter fait partie du travail (`mount /dev/rbdN /mnt/sonde`).

**Injection** : `lab/bin/break 08 39` (3 variantes).

**Travail demandé**
1. Reproduis la commande du ticket et relève **les deux** messages : celui de `rbd` et celui du noyau.
2. Teste l'authentification seule, sans le pilote noyau : une commande `rbd` en espace utilisateur avec le même compte (lister le pool, afficher l'image) réussit-elle ? Qu'est-ce que ça élimine ?
3. Compare ce que le client présente (trousseau) et ce que le cluster attend (`ceph auth get client.sonde`), sans afficher la clé à l'écran ni dans ton journal. Compare les droits accordés et ce que demande l'opération.
4. Corrige à l'endroit de l'écart (cluster ou client), au plus juste. Remonte le volume et vérifie que le fichier témoin est intact.
5. Prévention : quel test de `ms-verif-ceph` ou de pipeline aurait vu cet écart avant le redémarrage ?

**Critères de réussite**
- [ ] `client.sonde` a les droits `profile rbd` sur les moniteurs et `profile rbd pool=rbd-test` sur les OSD, rien de plus.
- [ ] Sur `cephcli01`, `rbd --id sonde info rbd-test/sonde` réussit, le trousseau est en mode 600, l'image n'a aucune fonctionnalité refusée par `krbd`, `/mnt/sonde` est monté depuis `/dev/rbd*` et le témoin y est lisible.
- [ ] Ton journal contient les deux messages d'erreur et la comparaison (sans clé).

**Vérification** : `lab/bin/check 08 39`

<details><summary>Indice 1</summary>

`dmesg -T | tail -n 20` juste après l'échec : `libceph` y parle d'authentification, `rbd` de fonctionnalités. `rbd --id sonde ls rbd-test` et `rbd --id sonde info rbd-test/sonde` testent le compte sans le noyau.
</details>

<details><summary>Indice 2</summary>

Pour comparer deux clés sans les afficher : `sha256sum` de chacune (côté cluster : `ceph auth get-key client.sonde | sha256sum`). `ceph auth get client.sonde` affiche aussi les droits : compare-les caractère par caractère au nom du pool. `rbd info` liste les `features` ; `rbd feature disable` existe.
</details>

**Pour aller plus loin** : passe le montage en persistant avec l'unité `rbdmap` de `ceph-common` (`/etc/ceph/rbdmap`) et une entrée `fstab` en `noauto,x-systemd.automount`, puis prouve qu'un redémarrage le remonte.

---

### M08-E40 — Panne : le S3 de Ceph répond en erreur  `BF` `★★★`

> **Ticket INC-3546** — *De : Julien Petit (pour l'équipe MédiDoc)*
> Les essais d'intégration de MédiDoc contre le S3 de Ceph échouent depuis ce matin. La sonde de `cephcli01` le confirme (`sudo wb-sonde-stockage`, lignes S3) : le message d'erreur est dans sa sortie. Le S3 du socle (`s3-01`) fonctionne, lui. Rien n'a été déployé côté MédiDoc.

**Objectifs pédagogiques**
- Découper le chemin d'une requête S3 : résolution du nom, VIP portée par keepalived, haproxy (TLS, répartition, contrôles de santé), démons RGW, authentification SigV4 (signature, horloge), compte et utilisateur RGW, puis RADOS.
- Associer chaque symptôme à un étage : délai dépassé, connexion refusée, `503`, `403` avec un code S3 précis (`RequestTimeTooSkewed`, `UserSuspended`, `SignatureDoesNotMatch`, `InvalidAccessKeyId`, `AccessDenied`).
- Utiliser l'orchestrateur pour l'état des services (`ceph orch ls`, `ceph orch ps`) et `radosgw-admin` pour l'état des utilisateurs.

**Prérequis** : M08-E11, M08-E12 ; M06-E18 (certificats) ; `lab/bin/check 08 40` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : `rgw.par1.medisphere.internal` résout la VIP 10.10.30.200, portée par le service `ingress` de cephadm (démons `haproxy.rgw.…` et `keepalived.rgw.…`) devant deux démons RGW sur `ceph02` et `ceph03`. La sonde signe ses requêtes en SigV4 (`curl --aws-sigv4`, configuration dans `/etc/workbook/sonde-s3.curl`). Pour tes propres essais, `sudo curl -K /etc/workbook/sonde-s3.curl …` réutilise ces identifiants sans les afficher.

**Injection** : `lab/bin/break 08 40` (4 variantes).

**Travail demandé**
1. Reproduis avec la sonde, puis avec `curl -v` depuis `cephcli01` et depuis `adm01` : une requête anonyme (`GET /`) et une requête signée. Classe le symptôme : pas de réponse, refus, réponse HTTP (code, code S3 dans le corps XML).
2. Remonte le chemin étage par étage, en commençant par celui que désigne le symptôme : la VIP est-elle portée, et par qui ? haproxy écoute-t-il ? Que dit-il de ses serveurs ? Les démons RGW tournent-ils ? L'utilisateur est-il actif ? L'horloge du client est-elle juste ?
3. Corrige la cause racine. Si un démon a été arrêté, découvre pourquoi l'orchestrateur ne l'a pas relancé de lui-même et comment il sait qu'il devrait tourner.
4. Prouve le retour avec la sonde et avec une requête signée depuis `cephcli01` ; vérifie aussi que le certificat présenté sur la VIP est toujours vérifié depuis `adm01`.
5. Prévention : quelle sonde, à quel étage, aurait distingué chacune des variantes possibles (pense à celles que tu n'as pas encore rencontrées) ?

**Critères de réussite**
- [ ] `https://rgw.par1.medisphere.internal/` répond 200 depuis `adm01` avec un certificat vérifié.
- [ ] Au moins deux démons RGW et tous les démons de l'ingress en marche ; aucune unité `ceph-*` masquée ou en échec ; l'utilisateur `sonde-s3` est actif.
- [ ] L'horloge de `cephcli01` est synchronisée, et la lecture signée de `s3://sonde/temoin` répond 200 ; ton journal associe le symptôme initial (code, message) à l'étage en cause.

**Vérification** : `lab/bin/check 08 40`

<details><summary>Indice 1</summary>

`curl -v` dit à quelle étape la requête s'arrête : résolution, connexion TCP, poignée de main TLS, réponse HTTP. Le corps d'une erreur S3 contient `<Code>…</Code>` : c'est le diagnostic de RGW lui-même. `ceph orch ps --daemon-type rgw` et `--daemon-type haproxy` donnent l'état vu par l'orchestrateur.
</details>

<details><summary>Indice 2</summary>

`ip -br addr` sur `ceph02` et `ceph03` montre qui porte la VIP. Sur l'hôte d'un démon, `systemctl status ceph-<fsid>@<démon>.service`. `radosgw-admin user info --uid=sonde-s3` (champ `suspended`). SigV4 refuse une requête dont l'horodatage s'écarte de plus de 15 minutes de l'horloge du serveur.
</details>

**Pour aller plus loin** : active les statistiques de haproxy du service ingress (`monitor_port` de la spécification) et ajoute une sonde par étage à `ms-verif-ceph` : VIP joignable, haproxy « UP » pour chaque RGW, requête signée.

---

### M08-E41 — Panne : le montage CephFS est figé  `BF` `★★★`

> **Ticket INC-3547** — *De : Nadia Roussel*
> Le partage CephFS de `cephcli01` (`/mnt/sonde-fs`) ne répond plus : un `ls` reste bloqué ou échoue, et la sonde (`sudo wb-sonde-stockage`) est rouge sur la ligne CephFS. Les volumes RBD et le S3 vont bien. Ne redémarre pas `cephcli01` « pour voir » : je veux comprendre.

**Objectifs pédagogiques**
- Comprendre le rôle du MDS : métadonnées, *capabilities* accordées aux clients, sessions, rangs actifs et démons en attente (*standby*, *standby-replay*).
- Diagnostiquer côté cluster (`ceph fs status`, `ceph fs dump`, sessions du MDS, liste de blocage) **et** côté client (`dmesg`, `/sys/kernel/debug/ceph/`, état du montage).
- Savoir ce qu'est une éviction, pourquoi elle entraîne une mise en liste de blocage (*blocklist*), et comment un client noyau s'en remet.

**Prérequis** : M08-E10, M08-E13, M08-E31 ; `lab/bin/check 08 41` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : le système de fichiers `cephfs` a un rang actif et (au moins) un démon MDS en attente, déployés par cephadm. Le client noyau de `cephcli01` est monté avec la syntaxe `sonde-fs@<fsid>.cephfs=/` et le fichier de secret `/etc/ceph/sonde-fs.secret`. Un montage figé ne se démonte pas toujours normalement : `umount -f` (forcé) et `umount -l` (paresseux) ont des effets différents ; lis `man umount` avant.

**Injection** : `lab/bin/break 08 41` (3 variantes).

**Travail demandé**
1. Reproduis **sans te bloquer toi-même** : lance tes essais sur le montage avec un délai (`timeout 10 ls /mnt/sonde-fs`), dans un second terminal si besoin. Relève le journal du noyau.
2. Côté cluster : état du système de fichiers, des rangs et des démons en attente ; sessions ouvertes sur le MDS actif (quel client, depuis quand) ; liste de blocage ; droits de `client.sonde-fs`.
3. Établis la cause racine et corrige-la côté cluster si elle y est, côté client sinon. Si le client doit être remonté, fais-le proprement et explique pourquoi un simple « attendre » ne suffisait pas.
4. Vérifie : la sonde est verte, le témoin est lisible, et le système de fichiers a de nouveau un démon en attente.
5. Explique dans ton journal ce que l'éviction d'un client protège (cohérence des données, verrous) et ce qu'elle coûte (écritures non vidées), et quand l'administrateur doit la déclencher lui-même.

**Critères de réussite**
- [ ] `cephfs` a un MDS actif et au moins un en attente, `standby_count_wanted` ≥ 1, la santé ne signale ni `FS_DEGRADED` ni `MDS_ALL_DOWN` ni `MDS_INSUFFICIENT_STANDBY` ; aucune unité `ceph-*` masquée ou en échec.
- [ ] `client.sonde-fs` a des droits MDS en lecture-écriture sans restriction de chemin.
- [ ] Sur `cephcli01`, `/mnt/sonde-fs` est un montage `ceph` qui répond en moins de 10 s ; ton journal contient les lignes de `dmesg` et l'état du MDS relevés pendant la panne.

**Vérification** : `lab/bin/check 08 41`

<details><summary>Indice 1</summary>

`ceph fs status cephfs` et `ceph health detail` disent s'il reste un MDS actif. `ceph tell mds.cephfs:0 session ls` liste les clients (champ `client_metadata`). `ceph osd blocklist ls` liste les adresses bloquées et leur échéance.
</details>

<details><summary>Indice 2</summary>

Côté client : `dmesg -T | grep -i ceph` (« evicted », « blocklisted », « permission denied », « mds0 hung »…), `cat /sys/kernel/debug/ceph/*/mdsc` (requêtes en attente, en root, `debugfs` monté). Un client noyau évincé ne se reconnecte pas tout seul par défaut : regarde l'option de montage `recover_session` dans `man mount.ceph`.
</details>

**Pour aller plus loin** : passe le MDS en attente en mode *standby-replay* (`ceph fs set cephfs allow_standby_replay true`) et mesure, avec la sonde en boucle, le temps de bascule quand tu arrêtes le MDS actif, avec et sans ce mode.

---

### M08-E42 — Panne : le cluster est lent  `BF` `★★★`

> **Ticket INC-3548** — *De : Julien Petit*
> Depuis hier soir, tout ce qui touche au stockage Ceph est très lent : la sonde de `cephcli01` met des secondes à écrire quelques octets, nos essais de charge sur RBD ont des latences multipliées par dix ou plus, et la supervision a vu passer des « slow ops ». Rien de cassé en apparence. InfoGér a livré hier « un profil réseau et des optimisations Ceph ». Mesure avant et après : je veux des chiffres, pas une impression.

**Objectifs pédagogiques**
- Mesurer avant de régler : `rados bench`, `rbd bench`, `ceph osd perf`, opérations lentes (`dump_historic_ops`, `dump_ops_in_flight`), temps de ping entre OSD (`OSD_SLOW_PING_TIME_*`).
- Localiser la lenteur : un OSD, un nœud, un réseau (public ou cluster), un réglage de l'ordonnanceur mClock.
- Vérifier une MTU de bout en bout et reconnaître un « trou noir » de PMTU.

**Prérequis** : M08-E28, M08-E29 ; M07-E15 (MTU 9000 sur les VLAN 30 et 31) ; `lab/bin/check 08 42` vert avant l'injection.
**Durée indicative** : 60 min (temps cible).

**Contexte technique** : réseau public sur `ens18` (VLAN 30), réseau cluster sur `ens19` (VLAN 31), MTU 9000 sur les deux, de bout en bout (M07-E15). Les mesures de référence de M08-E28 sont dans ton dépôt de documentation : reprends le même protocole (mêmes commandes, même pool, même durée). `rados bench … write --no-cleanup` laisse des objets de test : nettoie-les ensuite (`rados -p <pool> cleanup`).

**Injection** : `lab/bin/break 08 42` (3 variantes).

**Travail demandé**
1. Mesure : `rados bench` (écriture 30 s, puis lecture séquentielle) et `rbd bench` sur `rbd-test`, avec le protocole de M08-E28. Compare aux mesures de référence.
2. Localise : la lenteur est-elle uniforme ou concentrée sur un OSD, un nœud ? Que disent `ceph osd perf`, les opérations lentes (sur quel OSD, bloquées à quelle étape : `waiting for sub ops`, `queued_for_pg`…), les temps de ping entre OSD ?
3. Selon ce que tu as localisé : teste le réseau de ce nœud (tailles de paquets, débit avec `iperf3` si tu l'installes sur deux nœuds, files d'attente, filtrage) ou la configuration des OSD (`ceph config show osd.<id>` contre `ceph config dump`).
4. Corrige la cause racine, puis **mesure de nouveau** avec le même protocole. Range les deux séries de chiffres dans ton journal.
5. Explique pourquoi cette panne ne déclenche aucune alerte franche dans la supervision de M08-E24, et ajoute (ou décris) l'alerte qui l'aurait vue.

**Critères de réussite**
- [ ] Sur `ceph01-03`, `ens19` est en MTU 9000, un ping de 8972 octets sans fragmentation passe entre chaque paire de nœuds sur le réseau cluster ; aucune file `tbf`/`netem`, aucun filtrage par taille ni limitation de débit, délestages GRO/GSO/TSO actifs.
- [ ] Aucune limite client artificielle dans mClock, pas de profil `custom` ; ni `SLOW_OPS` ni `OSD_SLOW_PING_TIME_*` ; tous les OSD `up`.
- [ ] Ton journal contient les mesures avant/après (même protocole) et la ligne de diagnostic qui a localisé la cause ; les objets de `rados bench` ont été nettoyés.

**Vérification** : `lab/bin/check 08 42`

<details><summary>Indice 1</summary>

`ceph health detail` peut signaler des temps de ping anormaux entre OSD, par réseau (`BACK` = cluster, `FRONT` = public). `ceph daemon osd.<id> dump_osd_network` (dans `cephadm shell --name osd.<id>`) donne ces temps. `ping -M do -s 8972 <ip>` et `ping -M do -s 1472 <ip>` encadrent la MTU utile.
</details>

<details><summary>Indice 2</summary>

`ceph config dump | grep -i mclock` et `ceph config show osd.0 osd_mclock_profile`. Sur un nœud : `tc qdisc show dev ens19`, `ethtool -k ens19 | grep -E 'segmentation|receive-offload'`, `sudo nft list ruleset` (ce qui n'est pas à `firewalld`).
</details>

<details><summary>Indice 3</summary>

Les battements de cœur entre OSD sont volontairement plus gros que 1500 octets (`osd_heartbeat_min_size`) : c'est ce qui fait apparaître un défaut de MTU. Un équipement qui jette les grandes trames sans renvoyer d'ICMP « fragmentation nécessaire » laisse passer l'établissement des connexions TCP, puis bloque les gros segments.
</details>

**Pour aller plus loin** : refais la mesure de M08-E28 « jumbo contre 1500 » en sachant maintenant ce qu'une MTU hétérogène provoque, et ajoute au rôle Ansible des nœuds Ceph une vérification de MTU de bout en bout (ping `-M do` vers chaque pair) qui fait échouer le passage.

---

### M08-E43 — Astreinte : le stockage en détresse  `BF` `★★★★`

> **Ticket INC-3550** — *De : Nadia Roussel (responsable astreinte)* — priorité P2
> Tu es d'astreinte. Mardi, 2 h 40 : plusieurs remontées sur le stockage `ceph-par1` (le détail s'affiche à l'injection). La sauvegarde nocturne de MédiAgenda démarre à 5 h et écrit sur ce cluster : il doit être sain d'ici là. Tiens-moi informée toutes les 30 minutes, puis rédige le post-mortem avec le modèle de l'équipe.

**Objectifs pédagogiques**
- Gérer un incident de stockage à causes multiples : trier, prioriser par dépendances (quorum avant tout, puis OSD et placement, puis services d'accès, puis clients), éviter qu'une panne en masque une autre.
- Protéger les données pendant l'incident (aucune commande destructive, pas de récupération massive déclenchée sans réflexion).
- Communiquer pendant l'incident et rédiger un post-mortem sans recherche de coupable.

**Prérequis** : M08-E35 à M08-E42 (au moins une variante de chacun).
**Durée indicative** : 2 h de rétablissement + 45 min de post-mortem.

**Contexte technique** : le script tire **deux** pannes distinctes parmi celles de M08-E35 à M08-E42 (variantes aléatoires) et les injecte ensemble. Les symptômes peuvent se recouvrir ou s'amplifier (un quorum perdu masque tout le reste ; un OSD tombé pendant que le réseau cluster est malade ressemble à une panne de disque). `--variante N` (1 à 27) force la paire, pas les variantes. `--annuler` retire les deux. Modèle de post-mortem : [`modules/00-lab/ressources/M00-E46/modele-post-mortem.md`](../../00-lab/ressources/M00-E46/modele-post-mortem.md).

**Injection** : `lab/bin/break 08 43`

**Travail demandé**
1. **Triage (10 min max)** : liste les symptômes, leur impact métier (qui ne peut plus faire quoi ?) et une hypothèse de regroupement. Vérifie d'abord tes instruments : SSH vers chaque nœud (par IP), console de secours, `timeout 20 ceph -s` depuis `ceph01`, sonde du client. Envoie la première communication.
2. **Diagnostic** : traite les pannes dans un ordre que tu justifies par les dépendances. Tiens ton journal horodaté ; garde les sorties de `ceph health detail` à chaque étape.
3. **Rétablissement** : corrige chaque cause racine ; après chaque correction, relance **tous** tes tests de départ.
4. **Clôture** : communication de fin d'incident, `--annuler` pour clore, puis post-mortem enregistré dans `docs/socle/post-mortems/AAAA-MM-JJ-INC-3550.md` et publié par MR.

**Critères de réussite**
- [ ] Toutes les vérifications de M08-E35 à M08-E42 sont vertes (le contrôle les rejoue toutes) et aucune panne n'est encore marquée active.
- [ ] Le post-mortem existe, contient une chronologie horodatée, les deux causes racines, des extraits de `ceph health detail`, l'analyse de la détection (qu'est-ce qui aurait dû alerter avant Nadia ?) et des actions correctives avec responsable et échéance.
- [ ] Le journal contient au moins trois communications d'incident espacées d'environ 30 minutes.

**Vérification** : `lab/bin/check 08 43`

<details><summary>Indice 1</summary>

Ordre des dépendances de Ceph : moniteurs (quorum, horloge) → réseau des OSD (public, cluster) → OSD → placement (règles, `size`, seuils, drapeaux) → services d'accès (MDS, RGW, ingress) → clients (droits, trousseaux, montages). Une panne plus bas fausse les tests de tout ce qui est au-dessus.
</details>

<details><summary>Indice 2</summary>

Les contrôles `lab/bin/check 08 35` à `08 42` sont des sondes ciblées : lance-les pendant le triage pour cartographier ce qui est rouge. Un contrôle rouge n'est pas forcément une panne injectée : ce peut être la conséquence d'une autre.
</details>

**Pour aller plus loin** : fais-toi injecter une astreinte par quelqu'un d'autre (`--variante` tirée par lui), et chronomètre le temps jusqu'au **premier diagnostic juste** en plus du temps de rétablissement : c'est le chiffre que la supervision doit faire baisser.

---

### M08-E44 — Sous le capot : où est rangé cet objet ?  `LAB` `★★★`

> **Ticket PLAT-980** — *De : Karim Benali*
> Pendant les pannes, tout le monde a parlé de « PG », de « règle CRUSH » et d'« OSD primaire » comme de choses magiques. Je veux que tu saches **montrer** le chemin complet d'un objet : de son nom au PG, du PG aux OSD, et jusqu'à l'intérieur d'un OSD, en le prouvant à chaque étape avec un outil différent. Compte rendu pour les prochains arrivants.

**Objectifs pédagogiques**
- Calculer le placement d'un objet : hachage du nom, `pg_num`, PG, carte CRUSH, ensembles *up* et *acting*, OSD primaire.
- Reproduire ce calcul **hors du cluster** avec la carte des OSD (`osdmaptool`) et la carte CRUSH (`crushtool`), et simuler une modification avant de l'appliquer.
- Retrouver les objets RADOS qui composent une image RBD, et lire le contenu d'un PG directement dans le BlueStore d'un OSD arrêté (`ceph-objectstore-tool`), en lecture seule.

**Prérequis** : M08-E05, M08-E06, M08-E14, M08-E19 ; M08-E35 et M08-E36 conseillés.
**Durée indicative** : 3 h.

**Contexte technique**
- Tout se fait sur `ceph01`, dans `sudo cephadm shell` (les outils `osdmaptool`, `crushtool`, `ceph-objectstore-tool` et `rados` sont dans l'image Ceph) ; travaille dans un dossier temporaire du conteneur (`/tmp/analyse`), qui disparaît avec lui.
- L'objet d'étude s'appelle `analyse-placement`, dans le pool `rbd-test` (un objet RADOS « nu », à côté des objets des images RBD : il ne gêne pas RBD).
- `ceph-objectstore-tool` ouvre directement le magasin d'un OSD : l'OSD doit être **arrêté**. Dans `sudo cephadm shell --name osd.<id>` (sur l'hôte de l'OSD), le dossier de l'OSD est monté sous `/var/lib/ceph/osd/ceph-<id>`.

> ⚠️ **Attention** : `ceph-objectstore-tool` sait aussi **modifier** et **supprimer** (`--op remove`, `--op export-remove`, `set-bytes`, `remove-omap`…). Dans cet exercice, seules les opérations de lecture sont permises : `--op list-pgs`, `--op list`, `--op info`, `--op log`, `get-bytes`, `dump`, `list-attrs`. Avant d'arrêter l'OSD, vérifie que tu peux le faire (`ceph osd ok-to-stop <id>`) et pose `noout` ; ensuite, relance-le, attends `HEALTH_OK` et retire `noout`. Ne garde aucune copie de carte ni de données hors du conteneur temporaire, et aucune clé dans le compte rendu.

**Travail demandé**
1. **Du nom au PG.** Écris l'objet (`rados -p rbd-test put analyse-placement /etc/os-release`) et relève l'empreinte du fichier envoyé (`sha256sum`, dans le même conteneur). Demande à Ceph où il est (`ceph osd map rbd-test analyse-placement`) : relève l'époque de la carte, l'identifiant du pool, le hachage, le PG, les ensembles *up* et *acting*, le primaire. Explique comment `pg_num` intervient (et ce que change un `pg_num` qui n'est pas une puissance de 2).
2. **Du PG aux OSD, hors ligne.** Extrais la carte des OSD (`ceph osd getmap -o …`) et retrouve le même placement avec `osdmaptool … --test-map-object analyse-placement --pool <id>`. Regarde aussi la répartition de tous les PG du pool sur les OSD (`--test-map-pgs`) : est-elle équilibrée ?
3. **Simulations CRUSH.** Extrais et décompile la carte CRUSH (`ceph osd getcrushmap`, `crushtool -d`). Pour la règle du pool, montre avec `crushtool -i … --test` : les correspondances de 10 entrées pour 3 copies, l'utilisation des OSD sur 1024 entrées, et les mauvaises correspondances pour 4 copies (relie-les à M08-E36). Simule la perte d'un hôte (poids nul de ses OSD, options `--weight`) et estime la part de PG qui changeraient d'OSD.
4. **Une image RBD en objets.** Pour `rbd-test/sonde` : retrouve son identifiant interne, son en-tête (`rbd_header.<id>`), l'objet qui associe son nom à son identifiant (`rbd_id.sonde`), la liste de ses objets de données (`rbd_data.<id>.<numéro>`). Quelle taille d'objet, combien d'objets existent réellement et pourquoi pas 256 ? Place l'un d'eux comme à l'étape 1.
5. **Dans l'OSD.** Choisis un OSD du jeu *acting* de `analyse-placement` qui n'est pas le primaire. Avec les précautions de l'avertissement, arrête-le, ouvre son magasin en lecture : liste ses PG, liste les objets du PG de l'étape 1, lis le contenu de `analyse-placement` (`get-bytes`) et compare son empreinte à celle relevée à l'étape 1. Relance l'OSD et rends le cluster à `HEALTH_OK`.
6. **Compte rendu.** Rédige `docs/stockage/analyses/placement-objet.md` : `## Du nom à l'OSD` (étapes 1-2, sorties annotées, le PG réel de l'objet), `## Simulations CRUSH` (étape 3), `## Une image RBD en objets` (étape 4), `## Dans l'OSD (BlueStore)` (étape 5), puis `## Réponses aux questions`. Publie-le par MR.

**Questions d'analyse** (à traiter dans le compte rendu)
1. Pourquoi Ceph place-t-il des PG et non des objets ? Que se passerait-il avec CRUSH appliqué à chaque objet (taille de la carte, recalcul, suivi de l'état) ?
2. Pourquoi un client n'a-t-il besoin de demander à personne où se trouve un objet ? Qu'est-ce qu'il doit avoir, et que se passe-t-il quand sa carte est en retard d'une époque ?
3. Quelle différence entre l'ensemble *up* et l'ensemble *acting* ? Dans quel cas diffèrent-ils (*pg_temp*, *upmap*), et pourquoi est-ce utile pendant un remplissage (*backfill*) ?
4. Que fait le mode `upmap` de l'équilibreur (`ceph balancer status`) par rapport à une modification des poids CRUSH ?
5. `ceph osd map` pour un objet qui **n'existe pas** répond quand même : pourquoi ? Qu'est-ce que ça dit du calcul ?
6. Pourquoi une image RBD de 1 Gio n'occupe-t-elle presque rien juste après sa création (allocation à la demande) ? Que coûte en objets une écriture aléatoire de 4 Kio ?
7. Pourquoi `ceph-objectstore-tool` exige-t-il un OSD arrêté ? Cite une situation de production où on l'utilise vraiment (export d'un PG d'un OSD mourant, par exemple) et la précaution qui l'accompagne.

**Critères de réussite**
- [ ] Le compte rendu existe, est commité, contient les sections demandées, cite `ceph osd map`, `osdmaptool`, `crushtool` et `ceph-objectstore-tool`, et mentionne le **PG réel** de `analyse-placement`.
- [ ] Les 7 questions sont traitées.
- [ ] L'objet `analyse-placement` existe dans `rbd-test` ; tous les OSD sont `up` et `in`, aucun drapeau `noout`/`norebalance`/`nodown`/`norecover`, aucune unité masquée ou en échec, aucun `ceph-objectstore-tool` en cours ; aucune clé dans le compte rendu.

**Vérification** : `lab/bin/check 08 44`

<details><summary>Indice 1</summary>

Dans la sortie de `ceph osd map`, le PG s'écrit `<pool>.<hachage>` puis `(<pool>.<pg>)` : le second est le PG réel (le hachage réduit par `pg_num`). `ceph osd pool ls detail` donne l'identifiant numérique du pool, et `ceph osd crush rule dump` l'identifiant de sa règle, dont `crushtool` a besoin.
</details>

<details><summary>Indice 2</summary>

`crushtool -i crush.bin --test --rule <id> --num-rep 3 --min-x 0 --max-x 9 --show-mappings`, puis `--show-utilization` (sur `--max-x 1023`), puis `--num-rep 4 --show-bad-mappings`. Pour une image : `rbd info rbd-test/sonde` (`block_name_prefix`, `order`), `rados -p rbd-test ls | grep <id>`, `rados -p rbd-test listomapvals rbd_header.<id>`.
</details>

<details><summary>Indice 3</summary>

`ceph-objectstore-tool --data-path /var/lib/ceph/osd/ceph-<id> --op list-pgs`, puis `--pgid <pg> --op list`, qui affiche chaque objet sous la forme d'un JSON ; ce JSON se passe tel quel (entre apostrophes) devant `get-bytes`. Consulte `ceph-objectstore-tool --help` et la [page de manuel](https://docs.ceph.com/en/tentacle/man/8/ceph-objectstore-tool/).
</details>

**Pour aller plus loin** : refais l'étape 1 pour un objet d'un pool à codes d'effacement (M08-E15) : que représentent les positions de l'ensemble *acting* (fragments `k` et `m`), et que montre `ceph-objectstore-tool` dans un OSD qui ne porte qu'un fragment ?

---

### M08-E45 — Questions expert : Ceph  `Q` `★★★`

> **Ticket PLAT-981** — *De : Karim Benali*
> Dernière étape avant la recette du stockage v1 : ces questions, je les pose en entretien pour un poste d'ingénieur stockage. Réponds par écrit, en argumentant. Pas de recherche pendant la première passe ; vérifie ensuite dans la documentation et corrige-toi en couleur.

**Objectifs pédagogiques**
- Consolider la compréhension des mécanismes internes de Ceph manipulés dans ce module (RADOS, CRUSH, PG, BlueStore, moniteurs, cephx, RBD, CephFS, RGW, cephadm).
- S'entraîner à argumenter une réponse technique comme en entretien ou en revue d'architecture.

**Prérequis** : paliers 1 à 3 du module, M08-E44.
**Durée indicative** : 2 h 30.

**Questions**

1. Explique pourquoi Ceph n'a pas de table centrale de localisation des objets, et ce que cela change pour l'extensibilité et pour la récupération après une panne.
2. QCM — Un pool répliqué `size 3`, `min_size 2`, domaine de panne `host`, sur 3 hôtes. Un hôte entier tombe. Que se passe-t-il ?
   a) les PG passent `inactive` jusqu'au retour de l'hôte ; b) les PG restent actifs, dégradés, et ne peuvent pas retrouver trois copies tant que l'hôte n'est pas revenu ; c) Ceph recrée aussitôt la troisième copie sur un des deux hôtes restants ; d) les écritures sont refusées mais les lectures continuent.
3. Pourquoi `min_size 1` est-il dangereux, même « juste pendant une maintenance » ? Décris le scénario de perte de données qu'il rend possible.
4. Qu'est-ce que le *peering* d'un PG, quand a-t-il lieu, et pourquoi un PG peut-il rester `peering` ou `incomplete` ? Que demande-t-il aux OSD (journal des PG, `last_epoch_started`) ?
5. Compare réplication et codes d'effacement : surcoût de capacité, coût en écriture (petites écritures, réécritures partielles), récupération, nombre minimal d'hôtes pour `k=4, m=2` avec domaine `host`. Qu'apporte l'option `allow_ec_optimizations` de Tentacle ?
6. QCM — `osd_memory_target` vaut 1 Gio sur `ceph-par1`. Qu'est-ce que ce réglage garantit ?
   a) un plafond strict de mémoire, l'OSD est tué au-delà ; b) une cible pour le dimensionnement des caches de BlueStore, la mémoire réelle pouvant dépasser lors d'une récupération ; c) la mémoire réservée par cephadm au conteneur ; d) la taille du cache de RocksDB seulement.
7. BlueStore : où sont les données, les métadonnées (RocksDB) et le journal d'écriture (WAL) ? Pourquoi placer DB/WAL sur un SSD devant des disques durs, et que se passe-t-il quand la partition DB déborde (*spillover*) ?
8. Pourquoi les moniteurs sont-ils en nombre impair ? Que se passe-t-il avec 4 moniteurs dont 2 tombent ? Pourquoi ne pas en mettre 7 « pour être tranquille » ?
9. Qu'est-ce que cephx protège et ne protège pas ? Quelle différence entre `profile rbd`, `allow rwx pool=…` et `allow *` ? Que corrigeait CVE-2025-30156, et pourquoi la mise à jour 20.2.4 a-t-elle des étapes particulières (M08-E26) ?
10. msgr2 : modes `crc` et `secure`, ports 3300 et 6789. Que faut-il vérifier côté clients noyau avant d'imposer `secure` partout ?
11. QCM — Un client RBD écrit, et le PG est `active+undersized+degraded`. L'écriture :
    a) échoue avec `EIO` ; b) est acceptée et acquittée quand toutes les copies de l'ensemble *acting* l'ont écrite ; c) attend que la troisième copie soit recréée ; d) est acceptée par le seul primaire, les autres copies suivront.
12. Décris le cycle de vie d'une écriture RADOS répliquée : client → primaire → répliques → acquittement. Où se loge la latence, et pourquoi le réseau cluster compte-t-il ?
13. `noout`, `norebalance`, `nobackfill`, `norecover`, `pause` : que bloque chacun, et lesquels poser pour redémarrer un nœud pendant 10 minutes ? Lequel ne faut-il jamais oublier ?
14. mClock : que règlent les profils `balanced`, `high_client_ops`, `high_recovery_ops` ? Pourquoi l'ancien réglage `osd_max_backfills` n'est-il plus pris en compte par défaut, et comment le reprendre en main si besoin ?
15. CephFS : rôle du MDS, des *capabilities*, d'un rang, d'un *standby-replay*. Pourquoi un MDS lent rend-il **tout** le système de fichiers lent, et que faire contre ?
16. QCM — Un client CephFS a été évincé par le MDS. Quelle affirmation est vraie ?
    a) il se reconnecte seul dès que le réseau revient ; b) son adresse est mise en liste de blocage dans la carte des OSD, ce qui empêche ses écritures en retard d'atteindre les OSD ; c) ses écritures non vidées sont rejouées par le MDS ; d) l'éviction n'a d'effet que sur les métadonnées.
17. RGW : rôle des *zones*, *zonegroups* et *realms*. Qu'apportent les *accounts* de Tentacle par rapport aux utilisateurs et aux *tenants* ? Pourquoi `RequestTimeTooSkewed` existe-t-il ?
18. cephadm : que se passe-t-il quand tu arrêtes un démon par `systemctl stop` plutôt que par `ceph orch daemon stop` ? Et quand tu modifies à la main un fichier de configuration d'un conteneur ? Qui fait foi, la spécification ou l'état des hôtes ?
19. Une mise à jour `ceph orch upgrade` : dans quel ordre les démons sont-ils mis à jour, et pourquoi ? Que vérifies-tu avant de la lancer, et comment la mets-tu en pause ou l'arrêtes-tu ?
20. Un OSD est `down`. Décris ta démarche, des premières commandes jusqu'à la décision « le relancer » ou « le remplacer », et les commandes que tu t'interdis tant que tu n'as pas la réponse.

**Critères de réussite**
- [ ] Les 20 questions ont une réponse écrite et argumentée (pour les QCM : la bonne réponse **et** pourquoi les autres sont fausses).
- [ ] Après correction, tu as identifié tes trois points les plus faibles et noté un exercice ou une lecture pour chacun.

<details><summary>Indice 1</summary>

Pour 1 à 8, l'[architecture](https://docs.ceph.com/en/tentacle/architecture/), la page [Placement Groups](https://docs.ceph.com/en/tentacle/rados/operations/placement-groups/) et la [configuration de BlueStore](https://docs.ceph.com/en/tentacle/rados/configuration/bluestore-config-ref/) ; ton compte rendu de M08-E44.
</details>

<details><summary>Indice 2</summary>

Pour 9 à 20 : [cephx](https://docs.ceph.com/en/tentacle/rados/configuration/auth-config-ref/), [msgr2](https://docs.ceph.com/en/tentacle/rados/configuration/msgr2/), [mClock](https://docs.ceph.com/en/tentacle/rados/configuration/mclock-config-ref/), [CephFS — éviction](https://docs.ceph.com/en/tentacle/cephfs/eviction/), [RGW — accounts](https://docs.ceph.com/en/tentacle/radosgw/account/), [cephadm — upgrade](https://docs.ceph.com/en/tentacle/cephadm/upgrade/), les [notes de version de Tentacle](https://docs.ceph.com/en/latest/releases/tentacle/) ; tes journaux de M08-E35 à M08-E42.
</details>

**Pour aller plus loin** : choisis trois questions et transforme chacune en mini-démonstration sur le lab (5 minutes, reproductible, sans commande destructive), à présenter à Karim.
