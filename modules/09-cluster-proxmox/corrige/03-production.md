# Module 09 — Corrigé du palier 3 : Production

> ⚠️ Corrigé — à lire après avoir cherché.

**Points non testés en conditions réelles** (signale tes retours, ils corrigent le workbook) :
- syntaxe exacte de `ha-manager crm-command disarm-ha` / `arm-ha` en 9.2 (mode `freeze` ou `ignore` en argument positionnel d'après les sources consultées : vérifie avec `ha-manager help crm-command disarm-ha`) ;
- champs JSON de `/cluster/ha/status/current` (`type`, `sid`, `state`, `node`, `status`), de `/nodes/<nœud>/replication` (`fail_count`, `last_sync`), de `pveum user list --full 1` (`tokens[].tokenid`) et de `pvesh get /cluster/options` (`migration`, `bwlimit` rendus comme objets) sur lesquels s'appuient la sonde, les rôles et les vérifications ;
- libellé du journal de migration « use dedicated network address for sending migration traffic (…) » ;
- règles automatiques du pare-feu pour Corosync quand le lien 0 n'est pas dans `local_network` (le corrigé ajoute une règle explicite par prudence) ; écriture de `cluster.fw` par le module `template` d'Ansible dans `/etc/pve` (renommage atomique dans `pmxcfs`) ;
- détection du chien de garde émulé par l'identifiant PCI `8086:25ab` ; comportement de `pveceph install --version tentacle` sur un nœud reconstruit après la montée d'E28 ;
- nom des jetons PBS et des variables Vault d'E15 (le corrigé suppose `wb-hv@pbs!hv-par1`, `vault_pbs_hv_par1_jeton_secret`, `vault_pbs_hv_par1_cle`) et nom du groupe d'inventaire des nœuds (`hv_par1`, surchargeable par `hv_groupe`) : adapte aux noms de ton palier 2 ;
- présence de `ms-alerte` (M02-E26) sur les nœuds, nécessaire à `OnFailure=ms-alerte@%n.service` de la sauvegarde de configuration ; `jq` sur les nœuds (utilisé dans certaines commandes de diagnostic : `apt install jq` si absent).

**Rappel des VMID du palier** (dans `hv-par1`) : 120 `fence01`, 121 `fence02` (E24, conservées jusqu'au mini-projet comme témoins), 122 `migr01` (E27), 123-126 `charge01-04` (E31), 127 `restau01` (E29).

---

### M09-E24 — Le fencing à l'épreuve

**Solution**

Fichiers : [`infra/hv/watchdog.tf.extrait`](fichiers/M09-E24/infra/hv/watchdog.tf.extrait) ; rôle `pve_noeud` : [`tasks/chien_de_garde.yml`](fichiers/M09-E24/ansible/roles/pve_noeud/tasks/chien_de_garde.yml), [extrait de `defaults/main.yml`](fichiers/M09-E24/ansible/roles/pve_noeud/defaults/main.yml.extrait) ; [`playbooks/hv-chien-de-garde.yml`](fichiers/M09-E24/ansible/playbooks/hv-chien-de-garde.yml) ; compte rendu modèle [`fencing-hv-par1.md`](fichiers/M09-E24/medisphere/docs/virtualisation/tests/fencing-hv-par1.md).

*1. Prédiction.* La chronologie attendue est écrite en tête du compte rendu modèle : détection par Corosync (secondes), ressource en `fence`, attente que le verrou du LRM perdu soit libérable (calé sur les 60 s du chien de garde, plus une marge : le CRM n'agit qu'une fois **sûr** que le nœud perdu s'est clôturé lui-même), `recovery`, choix du nœud (affinité de nœud, puis affinité de ressources, puis charge), démarrage. La documentation annonce « environ 2 minutes » pour détection et bascule ; s'y ajoute le démarrage de l'invité.

*2. Préparation.* VMs 120 et 121 dans l'état `hv-invites` (clones du 199, disques sur `ceph-vm`). Ressources et règles :

```
root@hv01:~# ha-manager add vm:120 --state started --max_restart 1 --max_relocate 1
root@hv01:~# ha-manager add vm:121 --state started --max_restart 1 --max_relocate 1
root@hv01:~# ha-manager rules add node-affinity fence01-prefere-hv02 --resources vm:120 --nodes hv02:2,hv01:1,hv03:1
root@hv01:~# ha-manager rules add resource-affinity fence-separes --affinity negative --resources vm:120,vm:121
root@hv01:~# ha-manager rules config
```

(Si ton code d'E18 gère les ressources HA — le provider `bpg/proxmox` a des ressources pour la HA, vérifie lesquelles couvrent les *rules* de 9.x dans sa version épinglée —, déclare-les dans `hv-invites` ; sinon, les commandes ci-dessus sont notées dans le compte rendu et reprises dans le rôle `pve_cluster`.) Sans `--strict`, une affinité de nœud est une **préférence** : avec les priorités, `fence01` va sur `hv02` s'il est disponible, sinon ailleurs.

Fenêtres d'observation :

```
admin@adm01:~$ ./mesure-coupure.sh <IP-FENCE01> 22
root@hv01:~# watch -n1 ha-manager status
root@hv01:~# journalctl -f -u pve-ha-crm -u pve-ha-lrm -u corosync
```

*3. Scénario A* (`qm stop 2092` sur `pve01`) : `pvecm status` sur `hv01` montre 2 nœuds, toujours quorate (2 votes sur 3) ; `hv02` passe `unknown`, `vm:120` en `fence` ; après ~2 min, le journal de `pve-ha-crm` montre l'obtention du verrou du LRM de `hv02`, puis `recovery` et `started` sur `hv03` (pas sur `hv01` si `fence02` y tourne : règle négative). RTO mesuré typique : 2 min 20 à 2 min 40. Au redémarrage de `hv02`, `fence01` y **revient** : l'affinité de nœud non stricte avec priorité, et l'option `failback` (vraie par défaut depuis 9.0, elle remplace `nofailback`), la ramènent sur le nœud préféré, par migration à chaud. Si tu ne veux pas ce retour automatique (pour examiner le nœud avant), mets `failback 0` sur la ressource.

*4. Scénario B* (isolement Corosync, commandes dans le compte rendu modèle : une table nftables **à part**, chaînes d'entrée et de sortie, UDP 5405-5412) : `hv02` perd le quorum en quelques secondes (`pvecm status` : *Quorate: No*, `/etc/pve` en lecture seule) ; son LRM, qui avait une ressource active, perd son verrou et cesse de nourrir le chien de garde ; ~60 s plus tard, `softdog` redémarre `hv02` (la table nftables disparaît avec le redémarrage). Pendant ces 60 s, `fence01` **tourne encore** sur `hv02` — le CRM attend justement ce délai avant de la relancer ailleurs : à aucun moment deux copies ne tournent. Après redémarrage : `journalctl -b -1 -u pve-ha-lrm -u watchdog-mux` montre la perte du verrou puis la fin du journal sans arrêt propre.

*5. Scénario C* : LRM de `hv02` en `idle` (aucune ressource HA) → il n'a **pas armé** le chien de garde → pas de redémarrage. C'est conforme à la documentation : un nœud sans quorum ne se redémarre que s'il a des services actifs (ou un LRM/CRM actif non planifié). Les VMs **non HA** de `hv02` continuent de tourner, ingérables (`/etc/pve` en lecture seule : ni démarrage, ni arrêt par l'API, ni migration) et ne sont relancées nulle part : la HA ne protège que ce qu'on lui confie. Au retrait de la table, `hv02` rejoint le cluster.

*6. Chien de garde émulé.* Lecture : sans chien de garde matériel, Proxmox VE utilise `softdog`, « moins fiable » parce qu'il ne fonctionne pas indépendamment du serveur ; un module matériel se choisit par `WATCHDOG_MODULE` dans `/etc/default/pve-ha-manager` (les modules matériels sont bloqués par défaut, `watchdog-mux` charge celui qu'on désigne au démarrage). Mise en œuvre :
1. OpenTofu (état `hv`) : bloc `watchdog { enabled = true, model = "i6300esb", action = "reset" }` dans la ressource des nœuds ; `tofu plan` doit annoncer une **modification en place** (aucune recréation !) ; appliquer par le pipeline. Sur `pve01`, `qm config 2092 | grep watchdog` → `watchdog: model=i6300esb,action=reset` ; le périphérique n'apparaîtra dans la VM qu'au prochain démarrage de QEMU (`qm showcmd 2092` le montre déjà dans la ligne de commande calculée).
2. Ansible : [`chien_de_garde.yml`](fichiers/M09-E24/ansible/roles/pve_noeud/tasks/chien_de_garde.yml) refuse d'écrire `WATCHDOG_MODULE=i6300esb` tant que `lspci` ne voit pas la carte (sinon `watchdog-mux` ne démarrerait plus, et avec lui… la HA du nœud), écrit le réglage et **signale** le redémarrage nécessaire sans jamais le faire.
3. [`hv-chien-de-garde.yml`](fichiers/M09-E24/ansible/playbooks/hv-chien-de-garde.yml), un nœud à la fois : contrôles (quorum, Ceph, aucune VM non HA en marche), maintenance, réglage, `poweroff` **dans** le nœud (un `reboot` garderait le même processus QEMU, donc les mêmes périphériques), démarrage par l'API de `pve01`, retour au cluster, contrôle du module, `HEALTH_OK`, fin de maintenance. Ordre : `hv02` d'abord, puis les autres. Le jeton d'Ansible (M04, `wb-ansible@pve!ansible`) a besoin de `VM.PowerMgmt` sur les VMs 2091-2093.

```
root@hv02:~# wdctl
Device:        /dev/watchdog0
Identity:      i6300ESB timer [version 0]
Timeout:       10 seconds
root@hv02:~# lsmod | grep -E 'softdog|i6300esb'
i6300esb               16384  1
root@hv02:~# journalctl -b -u watchdog-mux | head -3
```

(Libellés indicatifs. Le « Timeout » vu par `wdctl` est celui du périphérique ; le délai de 60 s de la HA est géré par `watchdog-mux` au-dessus.)

*7. Rejouer B* : même chronologie (le noyau de `hv02` fonctionnait). La différence n'apparaît que si le **noyau** du nœud se fige : voir E32, question 2.

*8. Compte rendu* : modèle fourni.

**Explications**

Le fencing de Proxmox VE est un **auto-fencing** : aucun nœud n'éteint un autre nœud (pas d'IPMI, pas de STONITH). Chaque LRM qui a du travail tient un verrou dans `pmxcfs` et nourrit un chien de garde via `watchdog-mux`. Un nœud qui perd le quorum ne peut plus renouveler son verrou ; il arrête donc de nourrir le chien de garde, qui le redémarre au bout de 60 s. De l'autre côté, le CRM (élu, un seul actif) sait que le verrou d'un LRM perdu ne devient libérable qu'après ce délai : quand il le prend, il a la **garantie** que le nœud perdu ne fait plus tourner de VM HA. Toute la sûreté repose sur un postulat : *le chien de garde du nœud perdu fonctionne*. `softdog` est un minuteur du noyau : si le noyau est figé (panique bloquée, gel, VM du nœud mise en pause), il ne se déclenche pas, et le postulat tombe. Un chien de garde matériel (ou émulé hors de l'invité par QEMU) ne dépend pas du noyau.

Les états d'une ressource pendant l'épreuve : `started` → `fence` (le nœud est perdu, on attend la garantie) → `recovery` (choix d'un nœud) → `started` ailleurs ; `freeze` apparaît lors d'un redémarrage planifié selon la `shutdown_policy`. Un nœud sans ressource HA n'arme pas le chien de garde : il n'a rien à protéger, et le redémarrer n'apporterait rien.

**Alternatives**
- Chien de garde matériel du serveur (iTCO, `ipmi_watchdog` du BMC) : la bonne réponse en production ; le lab ne peut que l'émuler.
- Fencing externe (IPMI, PDU) comme dans Pacemaker : Proxmox VE ne le fait pas nativement ; il existe des intégrations tierces, non retenues (complexité, double mécanisme).
- `shutdown_policy=migrate` dans `datacenter.cfg` : pour les arrêts **planifiés**, les ressources partent avant l'arrêt ; ne change rien aux pannes.

**Pièges classiques**
- Arrêter le nœud par `shutdown` dans l'invité pour « simuler une panne » : c'est un arrêt planifié, géré par la `shutdown_policy` (les ressources sont gelées ou migrées), pas un fencing.
- Bloquer aussi SSH/MGMT pendant l'isolement : on perd la main, et l'on confond isolement Corosync et coupure totale.
- Poser une règle nftables **persistante** (dans `/etc/nftables.conf`) : le nœud redémarre… et se réisole aussitôt.
- Écrire `WATCHDOG_MODULE=i6300esb` avant que la carte existe : `watchdog-mux` ne démarre pas, la HA du nœud non plus.
- Croire qu'un `reboot` du nœud suffit à ajouter un périphérique : il faut un arrêt complet de la VM (nouveau processus QEMU).
- Lire un RTO dans `ha-manager status` : le temps que voit l'utilisateur inclut le démarrage de l'invité et du service ; seule une sonde extérieure le mesure.

**En production chez MédiSphère**
Chien de garde matériel validé à la réception de chaque serveur (test d'isolement avant mise en service), RTO de 3 minutes inscrit au catalogue des services pour une « VM HA », alerte sur toute ressource en `fence` ou `recovery` (sonde E25), et test de fencing trimestriel inscrit au plan de tests de reprise (F5).

---

### M09-E25 — Superviser le cluster

**Solution**

Fichiers (`plateforme/outils`) : [`bin/ms-verif-cluster`](fichiers/M09-E25/outils/bin/ms-verif-cluster), [`etc/ms-verif-cluster.conf`](fichiers/M09-E25/outils/etc/ms-verif-cluster.conf), [`systemd/ms-verif-cluster.service`](fichiers/M09-E25/outils/systemd/ms-verif-cluster.service), [`.timer`](fichiers/M09-E25/outils/systemd/ms-verif-cluster.timer), [`tests/bats/ms-verif-cluster.bats`](fichiers/M09-E25/outils/tests/bats/ms-verif-cluster.bats) ; (`plateforme/ansible`) rôle `pve_cluster` : [`tasks/supervision.yml`](fichiers/M09-E25/ansible/roles/pve_cluster/tasks/supervision.yml), [extrait de `defaults/main.yml`](fichiers/M09-E25/ansible/roles/pve_cluster/defaults/main.yml.extrait) ; [`pve-hv-supervision.env.exemple`](fichiers/M09-E25/adm01/pve-hv-supervision.env.exemple). Dans le `Taskfile.yml` de `plateforme/outils`, ajoute `ms-verif-cluster` (et `ms-capacite-cluster`, E31) à `SCRIPTS` et l'installation de leurs configurations (même forme que pour `ms-verif-services`, M06-E29).

*1. Les chemins de l'API et la valeur saine* :

| Contrôle | Chemin | Champ | Sain |
|---|---|---|---|
| Quorum | `/cluster/status` | entrée `type: cluster`, `quorate` | `1` |
| Nœuds | idem | entrées `type: node`, `online` | 3 × `1` |
| HA | `/cluster/ha/status/current` | `type: master` (`status` contient `active`), `type: lrm`, `type: service` (`state`) | maître actif, aucun service en `error`/`fence`/`recovery` |
| Ceph | `/cluster/ceph/status` | `health.status` (+ `health.checks`) | `HEALTH_OK` |
| Stockages | `/cluster/resources?type=storage` | `status`, `disk`/`maxdisk` | `available`, < 85 % |
| Réplication | `/nodes/<nœud>/replication` (chaque nœud) | `fail_count`, `last_sync` | 0 ; < 1 h |
| Sauvegardes | `/cluster/tasks` (type `vzdump`), `/cluster/backup-info/not-backed-up` | `status`, `endtime` ; liste | `OK`, < 26 h ; aucun invité de `prod` |
| Certificats | `/nodes/<nœud>/certificates/info` (ou TLS directement) | `notafter` | > 10 jours |

*2. L'identité* : [`supervision.yml`](fichiers/M09-E25/ansible/roles/pve_cluster/tasks/supervision.yml) crée l'utilisateur, vérifie le jeton, pose deux ACL `PVEAuditor` sur `/` (utilisateur **et** jeton : privilèges séparés) et refuse toute autre ACL. Le jeton lui-même est créé une fois à la main, parce que son secret n'est affiché qu'à la création :

```
root@hv01:~# pveum user token add wb-supervision@pve hv --privsep 1 --comment "ms-verif-cluster"
┌──────────────┬──────────────────────────────────────┐
│ full-tokenid │ wb-supervision@pve!hv                │
│ value        │ <SECRET>                             │   → Vault critique + ~/.config/workbook/pve-hv-supervision.env (600)
└──────────────┴──────────────────────────────────────┘
```

Preuve avec le jeton (depuis `adm01`, la bibliothèque passe le secret par un descripteur) :

```
admin@adm01:~$ MS_PVE_ENV_FILE=~/.config/workbook/pve-hv-supervision.env bash -c \
    'source ~/src/outils/lib/ms-commun.sh; pve_api GET /access/permissions path=/ | jq -c ".[\"/\"]"'
{"Datastore.Audit":1,"Mapping.Audit":1,"Pool.Audit":1,"SDN.Audit":1,"Sys.Audit":1,"VM.Audit":1, …}
admin@adm01:~$ MS_PVE_ENV_FILE=… bash -c 'source …/ms-commun.sh; pve_api POST /nodes/hv01/qemu/120/status/stop'
… POST /nodes/hv01/qemu/120/status/stop → HTTP 403 Permission check failed (/vms/120, VM.PowerMgmt)
```

(La VM 120 tourne sur `hv02` : même un jeton autorisé aurait reçu une erreur de nœud, pas d'arrêt — on choisit toujours un essai d'écriture **sans effet possible**.)

*3. La sonde* : principes repris de `ms-verif-services` (codes, `ok`/`ko`, configuration séparée, « rien vu » = KO) et trois choix propres :
- **interroger les nœuds directement**, dans l'ordre, en gardant celui qui a répondu ; la VIP est surveillée à part (connexion TCP, et son certificat, qui porte son nom depuis E18) : si la VIP tombe, la sonde le dit au lieu de tomber avec elle ;
- **résultat dans une variable globale** (`_REP`), pas sur la sortie : un appel dans `$(…)` tourne dans un sous-shell et perdrait le nœud qui a répondu (piège réel, attrapé par le test bats « premier nœud muet ») ;
- si le quorum ne peut même pas être lu, les autres contrôles sont sautés (ils échoueraient tous pour la même raison : une seule alerte claire vaut mieux que dix).

Les tests bats remplacent `pve_api` et `openssl` par des fonctions ; chaque domaine a son test rouge. `task test:bats` dans le projet. Installation : `task install:systeme`, puis :

```
admin@adm01:~$ sudo install -m 0644 systemd/ms-verif-cluster.{service,timer} /etc/systemd/system/
admin@adm01:~$ sudo systemctl daemon-reload && sudo systemctl enable --now ms-verif-cluster.timer
admin@adm01:~$ /usr/local/bin/ms-verif-cluster
OK  quorum       cluster quorate (réponse de hv01.par1.medisphere.internal)
OK  noeuds       3 nœud(s) en ligne sur 3 attendu(s)
…
Bilan : 17 contrôle(s) OK, 0 anomalie(s).
```

*4. Elle voit les pannes* :
- OSD : `ceph osd set noout` puis `systemctl stop ceph-osd@<ID>` sur `hv03` → `KO ceph HEALTH_WARN — OSD_DOWN: 1 osds down ; OSDMAP_FLAGS: noout flag(s) set` ; `journalctl -t ms-alerte` sur `adm01` montre l'alerte. Retour : `systemctl start ceph-osd@<ID>`, `ceph osd unset noout`.
- Réplication : méthode réversible retenue = désactiver une tâche (`pvesr disable <ID>`) : elle ne s'exécute plus, `last_sync` vieillit, et le contrôle d'**ancienneté** alerte au bout d'une heure ; `pvesr enable <ID>` ensuite. Provoquer un **échec** (cible cassée) est possible mais revient à injecter la panne d'E40 : inutile ici, les tests bats couvrent le cas `fail_count > 0`.
- Nœud : `ha-manager crm-command node-maintenance enable hv03` puis arrêt propre de `hv03` → `KO noeuds 2 nœud(s) en ligne sur 3 attendu(s) ; hors ligne : hv03`.

*5. Notifications de Proxmox VE* : depuis 8.1, un système de notifications (cibles `sendmail`, `smtp`, `gotify`, `webhook` ; *matchers* par type d'événement et sévérité) couvre fencing, réplication, sauvegardes, mises à jour disponibles. Il **pousse** des événements ; il ne dit pas « tout va bien » et ne voit pas ce qui ne produit pas d'événement (stockage qui se remplit, certificat qui approche de l'expiration, VIP absente). La sonde reste l'outil de l'astreinte ; au module 21, les métriques (serveur de métriques externe ou exportateur) et les alertes remplaceront le minuteur, et le *webhook* des notifications sera branché sur l'outil d'alerte.

**Explications**

Un jeton à privilèges séparés est l'identité idéale pour une sonde : ses droits sont l'intersection de ceux de l'utilisateur et des siens, il se révoque seul, et il n'a pas de mot de passe ni de double authentification à contourner. `PVEAuditor` donne `*.Audit` partout : lire, jamais agir. Interroger chaque nœud pour la réplication est nécessaire parce que les tâches de réplication sont exécutées et suivies par leur nœud **source**.

**Alternatives**
- Exportateur Prometheus (`prometheus-pve-exporter`) : métriques plutôt que contrôles, adapté au module 21 ; il lit la même API avec le même type de jeton.
- Serveur de métriques externe (InfluxDB, Graphite) déclaré dans le datacenter : pousse les métriques des nœuds, invités et stockages ; pas d'état HA ni de contrôles logiques.
- Supervision par SSH (`pvecm status`, `ceph -s` sur un nœud) : plus simple, mais une clé SSH root de supervision est bien plus dangereuse qu'un jeton d'audit.

**Pièges classiques**
- Jeton à privilèges séparés **sans** ACL propre : il ne voit rien, la sonde dit « aucun nœud ne répond »… alors que le cluster va bien. Lire le motif de l'erreur (403 vs réseau).
- Sonde qui passe par la VIP : la VIP tombe, la sonde aussi, et l'alerte dit « API injoignable » au lieu de « VIP absente ».
- Alerter sur `HEALTH_WARN` sans le détail : l'astreinte doit savoir **quoi** (le corrigé joint les codes de `health.checks`).
- Compter les invités non sauvegardés sans filtre : les VMs de test alertent en permanence et l'alerte n'est plus lue.
- Secret dans la ligne de commande de `curl` (visible dans `ps`) : la bibliothèque le passe par un descripteur.

**En production chez MédiSphère**
La sonde tourne aussi depuis un point **extérieur** au site (PAR2) pour voir une panne de `adm01` ou du réseau MGMT ; les alertes vont vers l'outil d'astreinte (module 21) ; le jeton de supervision a une date d'expiration et une rotation annuelle inscrite au registre des secrets.

---

### M09-E26 — Sécuriser le cluster

**Solution**

Fichiers : rôle [`pve_pare_feu`](fichiers/M09-E26/ansible/roles/pve_pare_feu/) ; [`group_vars/hv_par1/pve_pare_feu.yml`](fichiers/M09-E26/ansible/inventories/lab/group_vars/hv_par1/pve_pare_feu.yml) (la matrice en code) ; [`group_vars/hv_par1/certificats.yml`](fichiers/M09-E26/ansible/inventories/lab/group_vars/hv_par1/certificats.yml) ; [`playbooks/hv-certificats.yml`](fichiers/M09-E26/ansible/playbooks/hv-certificats.yml) ; [extrait de `pare_feu.yml`](fichiers/M09-E26/ansible/inventories/lab/host_vars/gw01/pare_feu.yml.extrait) ; [`matrice-flux-hv-par1.md`](fichiers/M09-E26/medisphere/docs/virtualisation/matrice-flux-hv-par1.md).

*1. La matrice* : voir le document modèle. Points clés :
- Les **règles automatiques** ouvrent, depuis `local_network`, l'interface, SSH, les consoles et Corosync ; depuis l'IPSet `management`, 8006, 22, 5900-5999, 3128 et 60000-60050. Par défaut, `local_network` vaut le réseau de l'adresse principale du nœud, donc **tout MGMT** (passerelles, `adm01`, futurs hôtes) : c'est le constat (1) de Sophie. On le redéfinit à 10.10.10.48/28 (seuls `.51-.53` y sont affectés, dans la plage « nœuds de clusters » du PLAN).
- Les règles automatiques ne savent rien de Ceph (3300, 6789, 6800-7300), du VRRP de la VIP (protocole 112), de l'EVPN (BGP 179, VXLAN UDP 4789), ni du défi ACME (80 depuis `ca01`) : règles explicites, **entre nœuds seulement** (IPSet `hv_noeuds` qui regroupe leurs adresses sur les quatre réseaux).
- Sortie en `ACCEPT` au niveau du nœud : le filtrage de sortie est fait par la bordure (`pare_feu.yml`), qui voit les flux vers PBS, `ca01`, les dépôts.

*2. Le pare-feu* : le rôle écrit `cluster.fw` (une fois) et chaque `host.fw`, arme un **filet** sur chaque nœud (`systemd-run --on-active=10min … pve-firewall stop`), laisse `pve-firewall` recompiler (~10 s), contrôle (SSH depuis le contrôleur, quorum, Ceph sans OSD/MON perdu, **VIP sur un seul nœud**), puis désarme le filet ; en cas d'échec de contrôle, il arrête le pare-feu du nœud et échoue. Mise en service progressive : premier passage avec `pve_pare_feu_noeud_actif: false` dans `host_vars/hv02` et `hv03` (seul `hv01` filtre), vérification de chaque ligne de la matrice, puis retrait de ces surcharges. Pour voir ce qui est réellement appliqué :

```
root@hv01:~# pve-firewall status
Status: enabled/running
root@hv01:~# iptables-save | grep -c PVEFW            # règles générées
root@hv01:~# iptables-save | grep -E 'management|local_network|5405' | head
```

*3. La preuve négative* :

```
root@gw01:~# for n in 51 52 53; do for p in 8006 22; do timeout 3 bash -c "</dev/tcp/10.10.10.$n/$p" && echo "10.10.10.$n:$p OUVERT" || echo "10.10.10.$n:$p fermé"; done; done
admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' --cacert /usr/local/share/ca-certificates/medisphere-root-ca.crt https://hv.par1.medisphere.internal:8006/
200
```

*4. TOTP* : dans l'interface, *Datacenter → Permissions → Two Factor → Add → TOTP* pour `<MOI>@pve`, puis pour `root@pam` (connecté en `root@pam`), puis *Recovery Keys* pour chacun (affichées une fois : imprimées et rangées au coffre, emplacement au registre des secrets). Test : déconnexion, connexion avec mot de passe + code, puis avec une clé de récupération sur un compte de test (`essai-tfa@pve`, supprimé ensuite : une clé utilisée est consommée). Vérification sans interface :

```
root@hv01:~# pvesh get /access/tfa --output-format json | jq -r '.[] | "\(.userid): \([.entries[].type] | join(","))"'
root@pam: totp,recovery
<MOI>@pve: totp,recovery
```

Ce que la double authentification **ne** couvre **pas** : les jetons d'API (d'où des jetons à privilèges séparés, limités, avec expiration), les connexions SSH (clés et certificats, M06-E20), les échanges entre nœuds (clés root de `/etc/pve/priv/authorized_keys`). En cas de perte du second facteur : clé de récupération, ou `pveum user tfa unlock` (après trop d'échecs) par un administrateur, ou la console de `pve01` (`root@pam` local au nœud). Imposer TOTP au niveau du realm `pve` (option *TFA* du realm) est possible ; non retenu dans le lab (un compte de service humain sans TOTP serait bloqué), à reconsidérer avec Keycloak (M24).

*5. Certificats* : comparaison des deux outils —

| Critère | `pvenode acme` (client intégré) | `certificats_acme` (M06-E18) + `pvenode cert set` |
|---|---|---|
| Nom de la VIP | défi HTTP-01 sur 10.10.10.200 : ne réussit que sur le nœud qui porte la VIP **au moment du défi** | idem pour l'émission initiale… |
| Renouvellement | nouvelle **commande ACME** à chaque fois, donc nouveau défi ; déclenché par `pve-daily-update` quand il reste moins de 30 jours : avec des certificats de 30 jours, **chaque jour** | …mais renouvellement par mTLS (`step ca renew`) : **aucun défi**, la VIP n'a plus besoin d'être là |
| Défi DNS-01 | possible par les greffons d'acme.sh, mais il faut déposer une clé d'API DNS (PowerDNS : clé globale) sur les nœuds, interdit par le contexte ; le greffon `nsupdate` a des défauts connus sous Proxmox VE | non utilisé |
| Secrets sur les nœuds | aucun (compte ACME) | aucun (le certificat sert de preuve au renouvellement) |
| Cohérence avec le socle | nouvelle mécanique | même mécanique que tout le socle (supervision, seuil de 15 jours de M06-E27) |

**Passation avec le rôle `pve_cluster` d'E18** : jusqu'ici, ce rôle émettait lui-même `pveproxy-ssl.pem` avec l'autorité du cluster (noms du nœud **et** de la VIP), et son script de santé keepalived vérifie le certificat servi sur 8006 avec `pve_cluster_sante_ca`. Ordre impératif, sinon le rôle réémettrait par-dessus le certificat MédiSphère, ou le script de santé rejetterait le nouveau certificat et **la VIP tomberait sur tous les nœuds** : (1) MR qui pose dans `group_vars/hv_par1/certificats.yml` `pve_cluster_cert_gere: false` et `pve_cluster_sante_ca: /etc/wb-certs/ca-api.pem` ; puis, nœud par nœud, `hv-certificats.yml` (2) construit ce fichier (racine du cluster **et** racine MédiSphère : les deux sont acceptées pendant la transition), (3) réapplique le rôle `pve_cluster` (le script de santé prend le nouveau fichier), (4) seulement ensuite émet le certificat. Le fichier peut garder les deux racines ensuite (l'autorité du cluster signe toujours `pve-ssl.pem`, utilisé entre nœuds).

Choix : `certificats_acme`. L'émission initiale se fait nœud par nœud, la VIP amenée sur le nœud en arrêtant `keepalived` quelques secondes sur les autres ([`hv-certificats.yml`](fichiers/M09-E26/ansible/playbooks/hv-certificats.yml) ; coupure brève de l'accès par la VIP, annoncée) ; ensuite `cert-renewer@pveproxy.timer` renouvelle à 15 jours de l'expiration et la commande `recharger` réinstalle le certificat pour `pveproxy` :

```
pvenode cert set /etc/wb-certs/pveproxy.crt /etc/wb-certs/pveproxy.key --force 1 --restart 1
```

(`pvenode cert set` écrit `/etc/pve/local/pveproxy-ssl.pem` et `.key` ; les fichiers `pve-ssl.*` de l'autorité du cluster restent en place et servent toujours **entre** nœuds.) Flux : `ca01` → nœuds 80/TCP (bordure et `pve_pare_feu`), nœuds → `ca01` 443. Vérification :

```
admin@adm01:~$ for n in hv01 hv02 hv03 hv; do echo | openssl s_client -connect $n.par1.medisphere.internal:8006 \
     -servername $n.par1.medisphere.internal -CAfile /usr/local/share/ca-certificates/medisphere-root-ca.crt \
     -verify_hostname $n.par1.medisphere.internal -verify_return_error 2>/dev/null | openssl x509 -noout -issuer -enddate; done
```

Puis : `PVE_CACERT` de `pve-hv-supervision.env` et `MS_RACINE` de `ms-verif-cluster.conf` passent de la racine du cluster (`hv-par1-root-ca.crt`) à la racine MédiSphère ; dans `hv-invites`, le provider `bpg/proxmox` vérifie le certificat de la VIP avec le magasin système de `adm01`/`runner01` (racine MédiSphère déjà installée), sans option d'insécurité.

*6. SSH* : rien à écrire — le rôle `pve_noeud` pose depuis M09-E03 le fragment `/etc/ssh/sshd_config.d/03-pve-noeud.conf` (`PermitRootLogin prohibit-password`, `PasswordAuthentication no`, `KbdInteractiveAuthentication no`), validé par `sshd -t` avant rechargement. L'exercice consiste à **prouver** que ces valeurs sont effectives : un fragment de `sshd_config.d` n'est lu que si le fichier principal l'inclut, et c'est la **première** valeur lue qui l'emporte (une directive placée avant l'`Include`, ou dans un fragment au nom plus petit, gagnerait).

```
root@hv01:~# sshd -T | grep -E '^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication) '
permitrootlogin without-password
passwordauthentication no
kbdinteractiveauthentication no
admin@adm01:~$ ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password,keyboard-interactive root@hv01.par1.medisphere.internal
root@hv01.par1.medisphere.internal: Permission denied (publickey).
```

`PermitRootLogin prohibit-password` et pas `no` : migration `secure`, réplication et `pvecm` passent par SSH root entre nœuds. Après le passage, `qm migrate 120 hv03 --online` fonctionne toujours. Si une valeur manque (`MaxAuthTries`, par exemple), on l'ajoute au gabarit du rôle, pas dans un second fichier.

*7. Qui a fait quoi* : procédure en tête de la matrice documentée. Exemple :

```
root@hv01:~# pvesh get /cluster/tasks --output-format json | jq -r '.[] | select(.id=="120") | [(.starttime|todate), .node, .type, .user, .status] | @tsv'
2026-10-09T14:12:03Z  hv02  qmstop   <MOI>@pve  OK
root@hv02:~# grep 'qemu/120/status/stop' /var/log/pveproxy/access.log
10.255.1.2 - <MOI>@pve [09/10/2026:16:12:03 +0200] "POST /api2/json/nodes/hv02/qemu/120/status/stop HTTP/1.1" 200 …
```

L'adresse source est celle du poste de l'apprenant via le VPN ; si la requête est passée par la VIP ou par un autre nœud, `access.log` de **ce** nœud la contient (le nœud qui reçoit la requête la relaie au nœud cible) : regarder les trois.

**Explications**

Le pare-feu de Proxmox VE a trois niveaux (datacenter, nœud, VM) dans des fichiers de `/etc/pve` : une règle écrite une fois s'applique à tous les nœuds, parce que `pmxcfs` réplique le fichier. Le danger est symétrique : une erreur s'applique partout en dix secondes. D'où l'activation nœud par nœud (`enable` de `host.fw`) et le filet. Les règles automatiques existent pour qu'un cluster ne se coupe pas lui-même en activant le pare-feu ; leur portée (`local_network`) est large par défaut, et c'est précisément ce qu'un audit relève.

**Alternatives**
- Moteur nftables (`proxmox-firewall`, `nftables: 1`) : jeu de règles plus lisible, encore présenté comme aperçu dans la documentation au moment de la rédaction ; à essayer sur un nœud.
- Filtrage par la bordure seule : inutile ici, les hôtes de MGMT sont dans le même VLAN que les nœuds (comme INFRA en M06-E30).
- DNS-01 avec une zone ACME déléguée et un serveur `acme-dns` (identifiants limités à un enregistrement) : la solution propre pour un nom flottant si l'on tient au client ACME intégré ; un service de plus à opérer.
- Certificat par le provisioner `admin` (JWK) et renouvellement mTLS : contourne le défi, mais demande un jeton émis avec le mot de passe du provisioner à chaque émission initiale.

**Pièges classiques**
- Oublier VRRP : `keepalived` des deux nœuds de secours ne reçoit plus les annonces, **trois** nœuds portent la VIP (ARP en désordre, OpenTofu qui échoue au hasard).
- Oublier Ceph : OSD marqués `down`, PG inactifs, VMs figées — c'est la panne d'E39 qu'on s'inflige soi-même.
- Mettre `runner01` dans l'IPSet `management` en croyant n'ouvrir que 8006 : l'IPSet ouvre aussi SSH et les consoles (règles automatiques).
- `local_network` redéfini en une **liste** d'adresses : un alias ne porte qu'une adresse ou un réseau ; pour plusieurs, un IPSet (mais les règles automatiques n'utilisent que l'alias).
- Tester le TOTP de `root@pam` sans avoir généré les clés de récupération, ou dans la seule session ouverte.
- Remplacer `pve-ssl.pem` au lieu de `pveproxy-ssl.pem` : on casse la confiance entre nœuds.

**En production chez MédiSphère**
Interface et API des nœuds joignables seulement depuis le bastion et le VPN d'administration, réseau d'administration hors bande pour les BMC ; journaux d'accès et de tâches envoyés au puits central (M22) avec une rétention conforme à HDS ; revue trimestrielle des comptes, jetons (dates d'expiration) et ACL ; TOTP imposé par le fournisseur d'identité (M24) ; test annuel du bris de glace (`root@pam` + clé de récupération).

---

### M09-E27 — Le réseau de migration

**Solution**

Fichiers : rôle `pve_cluster` : [`tasks/options_datacenter.yml`](fichiers/M09-E27/ansible/roles/pve_cluster/tasks/options_datacenter.yml), [extrait de `defaults/main.yml`](fichiers/M09-E27/ansible/roles/pve_cluster/defaults/main.yml.extrait) ; compte rendu modèle [`migration-hv-par1.md`](fichiers/M09-E27/medisphere/docs/virtualisation/tests/migration-hv-par1.md).

*1. Lecture* :
- `type=secure` (défaut) : le flux de migration passe dans un tunnel **SSH** entre nœuds (chiffré, authentifié par les clés root du cluster) ; `insecure` : QEMU envoie directement, en clair, sur un port TCP de la plage 60000-60050 (à ouvrir dans le pare-feu), plus rapide (pas de chiffrement, pas de goulot d'un flux SSH mono-cœur).
- `network=<CIDR>` : Proxmox choisit, sur le nœud cible, l'adresse qui appartient à ce réseau ; il faut donc une adresse **par nœud** dans ce réseau. Le même réglage sert de repli pour la réplication si `replication:` n'a pas de réseau.
- Corosync a besoin d'une latence faible et **stable** ; un flux saturant partagé avec un lien Corosync fait monter la latence, retransmettre les jetons, et peut faire perdre un membre (puis le quorum et le fencing). La documentation recommande des réseaux séparés pour Corosync et pour les flux à gros débit (stockage, migration, sauvegarde).

*2. Mesure de référence* : migration sans charge sur MGMT, puis avec `stress-ng --vm 1 --vm-bytes 2G --vm-keep` dans la VM. Pendant la seconde :

```
root@hv01:~# corosync-cmapctl -m stats | grep -E 'link1.*latency_(ave|max)'
root@hv01:~# corosync-cfgtool -s
```

Le journal de tâche donne débit, passes et *downtime* (lignes `migration active, transferred … of … VM-state`, `average migration speed`, `migration finished … downtime …`).

*3. Configuration* par [`options_datacenter.yml`](fichiers/M09-E27/ansible/roles/pve_cluster/tasks/options_datacenter.yml) : lecture de `/cluster/options`, comparaison normalisée, `pvesh set /cluster/options --migration type=secure,network=10.10.30.0/24 --bwlimit migration=307200,restore=204800` seulement en cas d'écart (idempotent), contrôle dans `datacenter.cfg`. Résultat :

```
root@hv01:~# cat /etc/pve/datacenter.cfg
bwlimit: migration=307200,restore=204800
migration: network=10.10.30.0/24,type=secure
```

Justification de la limite : le VLAN 30 porte aussi le **réseau public de Ceph** (lectures et écritures des VMs) ; une migration à pleine vitesse pourrait affamer les I/O des VMs. 300 Mio/s ≈ 2,5 Gbit/s laisse plus de la moitié d'un lien 10 Gbit/s. Dans le lab (pont virtuel), le chiffre est indicatif : ce qui compte, c'est d'avoir **une** valeur, justifiée, dans le code.

*4. Nouvelle mesure* : voir le tableau du modèle. Preuve du réseau : `use dedicated network address for sending migration traffic (10.10.30.7x)` dans le journal. Essai `insecure`, pour une seule migration :

```
root@hv01:~# qm migrate 122 hv02 --online --migration_type insecure --migration_network 10.10.30.0/24
```

Il faut ouvrir TCP 60000-60050 entre nœuds dans `pve_pare_feu` (ou constater qu'il échoue sans) : on le fait le temps de l'essai, puis on retire la règle. Gain typique : +50 à +70 % de débit.

*5. Non-convergence* : avec une limite basse (ex. 51200 Kio/s) et 3 Go réécrits, chaque passe recopie presque tout ; la tâche ne finit pas, on l'interrompt (`qm migrate` s'annule par l'interface ou `qm unlock` après arrêt de la tâche). QEMU propose *auto-converge* (ralentir les vCPU de l'invité pour réduire le taux de pages modifiées) et *postcopy* (bascule d'abord, pages tirées ensuite à la demande, mais une panne réseau pendant la phase postcopy perd la VM). Proxmox VE n'expose pas tous ces réglages par VM : voir la documentation de ta version.

*6.* Compte rendu, destruction de 122.

**Explications**

Une migration à chaud copie la mémoire en plusieurs passes (pré-copie) : elle converge si le débit dépasse nettement le rythme de salissure de la mémoire ; la dernière passe se fait VM suspendue (*downtime*), d'autant plus courte que le reliquat est petit. Le disque, lui, ne bouge pas (stockage partagé `ceph-vm`). Le MTU 9000 réduit le coût par paquet ; le chiffrement SSH est souvent le vrai plafond en `secure`.

**Alternatives**
- Réseau de migration dédié (VLAN propre sur les interfaces de stockage, ou lien physique) : la bonne solution sur le matériel réel.
- Migration sur COROSYNC (VLAN 32) : **jamais** — c'est exactement ce qu'on veut éviter.
- `insecure` sur un réseau dédié, isolé et non routé : acceptable techniquement ; en contexte HDS, il faut l'accord de la RSSI (mémoire des VMs en clair : données de santé, clés).

**Pièges classiques**
- `network=` sans adresse des nœuds dans ce réseau : la migration échoue (« could not get migration ip ») ou part ailleurs.
- Pare-feu d'E26 qui n'autorise SSH entre nœuds que sur MGMT : la migration sur le VLAN 30 échoue (l'IPSet `hv_noeuds` du corrigé contient les adresses des quatre réseaux).
- Confondre Kio/s et Kbit/s dans `bwlimit`.
- Mesurer une seule migration à vide et conclure : c'est la charge mémoire qui fait la différence.

**En production chez MédiSphère**
Réseau de migration dédié dans le dossier d'achat, `secure` maintenu, limites ajustées aux mesures réelles, et migrations de masse (maintenance d'un nœud) hors des heures de pointe de MédiAgenda ; supervision de la latence Corosync (module 21) avec seuil d'alerte.

---

### M09-E28 — Monter Ceph de Squid à Tentacle

**Solution**

Fichiers : [`playbooks/ceph-squid-vers-tentacle.yml`](fichiers/M09-E28/ansible/playbooks/ceph-squid-vers-tentacle.yml), fiche modèle [`CHG-1054-ceph-tentacle.md`](fichiers/M09-E28/medisphere/docs/virtualisation/changements/CHG-1054-ceph-tentacle.md).

*1. Préalables* (wiki *Ceph Squid to Tentacle*) : Proxmox VE 9.1 ou plus sur tous les nœuds, `pve-manager` ≥ 9.1.4, paquets Ceph Squid ≥ 19.2.3-pve3, cluster sain. Relevés :

```
root@hv01:~# pveversion -v | grep -E '^(pve-manager|ceph):'
root@hv01:~# ceph versions ; ceph -s ; ceph osd dump | grep -E 'flags|require_osd_release' ; ceph mon dump | grep min_mon_release
```

*2. Filet du lab* : arrêt des trois VMs 2091-2093 **en même temps** (`qm shutdown` en parallèle sur `pve01`, après avoir arrêté proprement les VMs imbriquées ou accepté leur arrêt), instantané `avant-chg1054` de chacune (`qm snapshot 2091 avant-chg1054` ; disques sur `local-nvme` et `ssd-lab` : vérifier qu'ils acceptent les instantanés et la place libre), redémarrage. Ce filet n'existe que parce que le cluster est imbriqué : un retour arrière **cohérent** exige que les trois nœuds reviennent au même instant, cluster arrêté.

*3-4. Le playbook* (six jeux, chacun rejouable) : contrôles ; dépôt `ceph-tentacle` en deb822 et `apt full-upgrade` nœud par nœud (les démons gardent leurs binaires Squid) ; `noout` posé s'il reste un démon Squid ; MON nœud par nœud (redémarrage conditionné par la version renvoyée par `ceph tell mon.<nœud> version`), attente du quorum à trois et d'une santé sans autre code que `OSDMAP_FLAGS` ; `min_mon_release` = 20 ; MGR ; OSD nœud par nœud avec attente de tous les PG `active+clean` ; enfin, si plus aucun démon n'est en Squid, `require-osd-release tentacle`, retrait de `noout`, `HEALTH_OK`. Exécution :

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/ceph-squid-vers-tentacle.yml --check --diff
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/ceph-squid-vers-tentacle.yml --step
```

Avertissements observés et normaux : `OSDMAP_FLAGS` (noout) pendant toute l'opération ; PG `active+undersized+degraded` pendant le redémarrage des OSD d'un nœud ; `OSD_UPGRADE_FINISHED` (« all OSDs are running tentacle or later but require_osd_release < tentacle ») entre la fin des OSD et `require-osd-release`.

*5. Après* : `ceph versions` (une seule version 20.2.x par type), `ceph osd df` (colonne `META` : point connu de la procédure pour les OSD créés en Octopus ou avant, non concernés ici), suppression des instantanés du lab (`qm delsnapshot 209N avant-chg1054`), rejeu du playbook : `changed=0`.

**Explications**

L'ordre MON → MGR → OSD vient de la compatibilité : les moniteurs fixent la carte du cluster et doivent comprendre les nouveautés avant les autres ; les OSD Tentacle savent parler à des moniteurs Tentacle et à des OSD Squid pendant la transition. `noout` évite que les OSD redémarrés soient marqués `out` (et que Ceph lance une recopie inutile). `require-osd-release tentacle` autorise ensuite les fonctions et formats propres à Tentacle : après lui, plus aucun OSD Squid ne peut rejoindre — c'est le point de non-retour officiel, même si en pratique un retour arrière n'est déjà plus raisonnable dès le premier MON redémarré.

**Alternatives**
- Étapes manuelles du wiki (ce que fait le playbook, à la main) : acceptable pour un cluster unique ; le playbook se justifie par la répétition (cluster de production, autres sites).
- Reconstruire un cluster neuf en Tentacle et migrer les VMs : coûteux, mais sans risque de montée en place ; c'est ce que fait, d'une certaine façon, le mini-projet.

**Pièges classiques**
- Oublier les prérequis de version de Squid ou de Proxmox VE : erreurs de dépendances, ou paquets Tentacle qui ne s'installent qu'à moitié.
- Redémarrer tous les MON en même temps : perte de quorum Ceph, I/O gelées.
- Passer aux OSD du nœud suivant avant `active+clean` : deux copies indisponibles, PG inactifs.
- Lancer `require-osd-release` avant que tous les OSD soient en Tentacle (le playbook le refuse).
- Laisser `noout` posé « parce que tout va bien » : le prochain disque qui meurt ne sera jamais recopié.
- Deux dépôts Ceph (ancien `.list` et nouveau `.sources`).

**En production chez MédiSphère**
Répétition sur le cluster de préproduction, fenêtre dédiée, fiche normale, et attente de quelques semaines de retours sur la version (point release `.1` ou `.2`) avant de monter la production ; jamais une montée de Ceph et de Proxmox VE dans la même fenêtre.

---

### M09-E29 — Reconstruire un nœud, restaurer le cluster

**Solution**

Fichiers : rôle [`sauvegarde_pbs`](fichiers/M09-E29/ansible/roles/sauvegarde_pbs/) (celui de M06-E28, étendu de l'élément `pve` et de `sauvegarde_pbs_depot_client`), [`group_vars/hv_par1/sauvegarde_pbs.yml`](fichiers/M09-E29/ansible/inventories/lab/group_vars/hv_par1/sauvegarde_pbs.yml), [extrait de `vault-critique.yml`](fichiers/M09-E29/ansible/inventories/lab/group_vars/hv_par1/vault-critique.yml.extrait) ; runbook [RB-091](fichiers/M09-E29/medisphere/docs/virtualisation/runbooks/RB-091-reconstruire-un-noeud.md).

*Plan de travail retenu* :
1. **Avant** : sauvegarde de configuration. L'élément `pve` copie `config.db` par l'API de sauvegarde de SQLite (cohérente pendant que `pmxcfs` écrit), vérifie son intégrité, liste les fichiers `.conf` qu'elle contient (preuve lisible sans restaurer), copie l'arborescence `/etc/pve` (restauration de fichiers isolés) et les fichiers propres au nœud (Corosync, réseau, FRR, `pve-ha-manager`), puis tout part dans `host/<nœud>` de `par1/hv`, chiffré avec la clé du cluster. Sur un nœud Proxmox VE, le rôle ne configure **pas** le dépôt `pbs-client` (le client vient des dépôts de Proxmox VE, à la version testée avec elle). Côté PBS, le jeton du cluster (E15) a `DatastoreBackup` sur `par1/hv` : il peut créer les groupes `host/hvNN`, il ne peut rien effacer.
   ```
   root@hv01:~# systemctl start wb-backup-socle.service && journalctl -u wb-backup-socle -n 5 -o cat
   wb-backup-socle: pve : config.db (14 fichier(s) .conf), /etc/pve, fichiers du nœud
   wb-backup-socle: terminé en 9 s (pve)
   ```
2. **La perte** : sauvegarde de `restau01` (127) vérifiée, `qm stop 2093` sur `pve01`, puis destruction par le code (retrait de `hv03` de l'état `hv`, ou `tofu destroy -target=<ADRESSE>` : plan relu, une seule VM détruite).
3. **Pendant la perte** : HA relance les ressources de `hv03` (≈ 2-3 min, E24) ; Ceph : 2 hôtes sur 3, PG `undersized+degraded`, écritures possibles (`min_size 2`) ; aucune recopie possible (règle CRUSH par hôte, `size 3`) : le cluster est **vulnérable** à une seconde panne. Retrait selon RB-091 § 3 : OSD purgés (le disque n'existe plus : `safe-to-destroy` dira non, c'est attendu et c'est pour cela qu'on vérifie d'abord que la VM est détruite), MON retiré de la carte et de `ceph.conf`, hôte retiré de CRUSH, `pvecm delnode hv03`, répertoire `/etc/pve/nodes/hv03` mis de côté, entrées de `/etc/pve/priv/known_hosts` et `authorized_keys` nettoyées, `known_hosts` de `adm01` nettoyé.
4. **Reconstruction** : RB-091 § 4-5. Points d'attention : même version de paquets **avant** `pvecm add` ; `pveceph install` dans la version **actuelle** du cluster (Tentacle après E28) ; `host.fw` de `hv03` recréé par `pve_pare_feu` (il a disparu avec le répertoire du nœud) ; certificat 8006 réémis par `hv-certificats.yml` (VIP amenée sur `hv03`) ; SDN réappliqué ; tâches de réplication recréées (première synchronisation complète).
5. **Restaurations** : `qmrestore` de 127 sur `hv03` (stockage `local-lvm`) depuis `pbs-par2` ; fichier de VM supprimé par erreur retrouvé dans `socle.pxar` (`pve/etc-pve/nodes/<nœud>/qemu-server/<VMID>.conf`) et remis en place après avoir vérifié l'existence de ses disques.
6. **Mesures** typiques dans le lab : retrait 15 min, recréation et installation 20 min, réintégration 35 min, récupération Ceph 15-30 min (96 Go d'OSD peu remplis), restaurations 10 min.

**Explications**

L'identité d'un nœud dans le cluster tient à : son nom et ses adresses (Corosync, `/etc/hosts`), son entrée dans `corosync.conf` (identifiant de nœud, liens), son certificat `pve-ssl.pem` signé par l'autorité du cluster, ses clés SSH (dans `/etc/pve/priv`), son répertoire `/etc/pve/nodes/<nœud>` (configuration des VMs qu'il héberge, `host.fw`, certificats), et côté Ceph ses MON, MGR et OSD (identifiants, clés). `pvecm delnode` retire l'entrée Corosync mais laisse le répertoire du nœud et les entrées SSH : réutiliser le nom sans les nettoyer donne des avertissements d'empreinte, des fichiers de VM orphelins, ou un ancien `host.fw` appliqué au nouveau nœud. La sauvegarde de configuration ne sert presque à rien pour reconstruire **un** nœud (le cluster a tout dans `pmxcfs`) ; elle sert pour les erreurs humaines (un fichier supprimé) et pour la perte **totale**.

**Alternatives**
- Remettre `config.db` sauvegardé sur le nœud reconstruit : faux bon réflexe dans un cluster vivant (il écraserait l'état courant à la jonction, ou désynchroniserait le nœud) ; réservé à la perte totale.
- Nouveau nom (`hv04`) au lieu de réutiliser `hv03` : supprime les risques de restes ; mais casse tout ce qui cite le nom (règles HA, code, DNS, supervision) ; la réutilisation du nom, propre, est préférable quand tout est dans le code.
- Restaurer la VM `hv03` elle-même depuis une sauvegarde de `pve01` : tentant dans le lab, impossible sur du matériel réel, et dangereux (un nœud qui « revient » avec un ancien état de cluster).

**Pièges classiques**
- `pvecm delnode` alors que le nœud peut redémarrer : il revient avec une ancienne configuration Corosync et perturbe le cluster.
- Oublier le MON dans `ceph.conf` (`mon_host`) : les clients tentent un moniteur mort à chaque connexion.
- OSD « fantômes » (`ceph osd tree` montre des OSD `DNE` ou un hôte vide) : `ceph osd purge` et `ceph osd crush remove <hôte>`.
- Rejoindre le cluster avec des paquets plus anciens que les autres nœuds.
- Restaurer 127 avant que `local-lvm` de `hv03` soit disponible, ou sur un autre nœud sans changer le stockage.
- Réutiliser le vieux fichier `<VMID>.conf` de 127 (pointe vers des disques disparus).

**En production chez MédiSphère**
Pièce de rechange (ou contrat de remplacement sous 4 h), RB-091 joué deux fois par an par l'astreinte sur la préproduction, sauvegarde de configuration également **copiée** vers PAR2 hors de PBS (synchronisation de datastore, M00/F5), et clé de chiffrement sur papier dans deux coffres distincts.

---

### M09-E30 — ADR : cluster Proxmox ou OpenStack ?

**Solution**

ADR modèle : [`ADR-0090-cluster-proxmox-ou-openstack.md`](fichiers/M09-E30/medisphere/docs/virtualisation/adr/ADR-0090-cluster-proxmox-ou-openstack.md). Décision : **partage par usage** — socle, bases de production, VMs héritées, nœuds Kubernetes (au départ) sur `hv-par1` ; environnements éphémères des équipes de développement sur OpenStack ; règle : « une charge va sur OpenStack si elle est demandée par une équipe hors Plateforme, plus d'une fois par semaine, et si elle est remplaçable ».

**Explications**

La question « Proxmox ou OpenStack » est mal posée tant qu'on la pose en termes de technologie. Les deux font tourner des VMs KVM sur Ceph ; ils diffèrent par le **modèle d'exploitation** : Proxmox VE est un outil d'administrateurs (une équipe gère des VMs durables, avec HA de VM), OpenStack un service pour des locataires (projets, quotas, réseaux isolés, API stable, instances remplaçables). Le critère décisif est donc la demande : qui, combien de fois, avec quel modèle de disponibilité. Un point d'architecture renforce la décision : le socle (DNS, PKI, forge) ne peut pas dépendre d'OpenStack, puisqu'OpenStack dépend de lui.

**Alternatives** (et pourquoi elles perdent ici)
- Tout Proxmox : pas de libre-service ni de cloisonnement par équipe ; l'équipe Plateforme devient le goulot de chaque recette.
- Tout OpenStack : plan de contrôle lourd et compétences rares pour héberger aussi le socle ; pas de HA de VM unique par défaut ; dépendance circulaire avec le socle.
- OpenStack sur des VMs Proxmox : pertinent pour **apprendre** (c'est le lab du module 10) ou pour un petit plan de contrôle ; en production, deux couches à opérer pour les mêmes VMs.

**Pièges classiques**
- Une ADR qui compare des fonctionnalités sans dire **quelles charges** vont où.
- Oublier le coût d'astreinte et de compétences (le premier coût d'OpenStack).
- Pas de condition de remise en cause : la décision se fossilise.
- Ignorer la dépendance du socle (OpenStack ne peut pas héberger son propre DNS).

**En production chez MédiSphère**
L'ADR alimente le catalogue de services (module 28) : un formulaire « je veux une VM » qui oriente vers la bonne plateforme selon la règle ; revue de la décision à chaque changement d'échelle (nombre d'équipes, de VMs).

**Grille d'auto-évaluation**

| Critère | Attendu |
|---|---|
| Gabarit | MADR, deux pages au plus, statut, décideurs, date |
| Charges | les sept charges de l'énoncé au moins, chacune placée avec une raison |
| Options | trois au moins, comparées sur des critères **explicites** (pas « plus moderne ») |
| Décision | une règle générale applicable à une charge nouvelle |
| Remise en cause | seuils chiffrés ou événements observables |
| Conséquences | négatives écrites, chacune avec une action rattachée à un module |

---

### M09-E31 — Capacité et surallocation

**Solution**

Fichiers : [`bin/ms-capacite-cluster`](fichiers/M09-E31/outils/bin/ms-capacite-cluster), [`etc/ms-capacite-cluster.conf`](fichiers/M09-E31/outils/etc/ms-capacite-cluster.conf), [`tests/bats/ms-capacite-cluster.bats`](fichiers/M09-E31/outils/tests/bats/ms-capacite-cluster.bats) ; rôle `pve_noeud` : [`tasks/memoire.yml`](fichiers/M09-E31/ansible/roles/pve_noeud/tasks/memoire.yml), [extrait de `defaults/main.yml`](fichiers/M09-E31/ansible/roles/pve_noeud/defaults/main.yml.extrait) ; document modèle [`capacite-hv-par1.md`](fichiers/M09-E31/medisphere/docs/virtualisation/capacite-hv-par1.md).

*Mesures* : sur chaque nœud, RSS des processus de l'hôte et de Ceph (`ps -eo rss,comm --sort=-rss | head -20`, `systemd-cgtop -m`), état du cache ZFS :

```
root@hv01:~# awk '/^(c_max|size) / {printf "%s %.0f Mio\n", $1, $3/1048576}' /proc/spl/kstat/zfs/arcstats
c_max 1024 Mio
size 870 Mio
root@hv01:~# cat /sys/module/zfs/parameters/zfs_arc_max
1073741824
root@hv01:~# ceph config get osd osd_memory_target
1073741824
```

Le plafond de l'ARC est déjà posé par `pve_noeud` depuis M09-E03 (1 Gio) : la mesure le **confirme** (`c_max` = 1024 Mio, `zfs_arc_max` non nul). Sans ce réglage, sur une installation ext4 + LVM-thin, l'installateur n'aurait rien fixé (il ne plafonne l'ARC que pour une installation sur ZFS) et la valeur par défaut d'OpenZFS aurait laissé le cache occuper une large part de la RAM, rendue avec retard sous pression : à vérifier en lisant `zfs_arc_max` (0 = défaut du module). [`memoire.yml`](fichiers/M09-E31/ansible/roles/pve_noeud/tasks/memoire.yml) ne réécrit pas ce réglage : il **contrôle** que la valeur effective est celle qu'utilise le calcul de capacité, et garantit `ksmtuned`.

*Calcul* (document modèle) : capacité par nœud (12 288 − 1 536 − 3 072 − 1 024) × 0,9 = 5 990 Mio ; N+1 = 11 980 Mio. L'outil fait le même calcul depuis l'API :

```
admin@adm01:~$ ms-capacite-cluster
Capacité par nœud (Mio, après réserves de 5632 Mio et marge de 10 %) :
  hv01 5990
  hv02 5990
  hv03 5990
Capacité N+1 : 11980 Mio ; mémoire engagée : 5120 Mio ; disponible : 6860 Mio
SAIN : la perte du plus gros nœud serait absorbée (reste 6860 Mio).
admin@adm01:~$ ms-capacite-cluster --demande 20x2048 ; echo $?
NON : 20 × 2048 Mio (40960 Mio) dépassent la capacité N+1 de 34100 Mio.
1
```

*Surallocation* : ballon avec plancher (`qm set 123 --memory 2048 --balloon 1024`) sur les VMs de recette uniquement ; KSM par `ksmtuned` (paquet `ksm-control-daemon`, actif par défaut sur Proxmox VE : le rôle le garantit) ; vCPU : 2 par cœur en production, 4 en recette. Démonstration : sur `hv02`, remplir la mémoire (VMs 123-126 avec `stress-ng --vm 1 --vm-bytes 1800M`) ; `pvestatd` ajuste les ballons quand l'occupation de l'hôte dépasse son seuil (~80 %) ; l'invité voit `MemTotal` baisser ; `cat /sys/kernel/mm/ksm/pages_sharing` monte.

*Réponse à Julien* : dans le document modèle (6 VMs de 2 Go à plancher de 1 Go aujourd'hui, ou OpenStack).

**Explications**

La capacité d'un cluster HA n'est pas la somme de ses nœuds : il faut d'abord retirer ce que consomme chaque nœud pour fonctionner (hyperconvergé : Ceph est **dans** les nœuds), puis la réserve qui permet d'absorber la perte d'un nœud — sinon, la HA relance des VMs sur des nœuds déjà pleins, l'OOM killer frappe, et la panne d'un nœud devient la panne de tous. Le ballon et KSM ne changent pas cette arithmétique : ils permettent de surallouer des VMs **qui n'utilisent pas** leur mémoire, au prix d'une dégradation quand elles l'utilisent.

**Alternatives**
- Réserve N+1 par la HA elle-même (CRS `static`/`dynamic` qui tient compte de la mémoire) : aide à **placer**, ne garantit pas la place.
- Compter la mémoire réellement consommée (`mem`) plutôt qu'allouée : trompeur (cache de pages invisible pour l'hôte, pointes).
- Échange (*swap*) sur les nœuds pour absorber les pointes : dégrade toutes les VMs d'un nœud ; à éviter ou à limiter fortement.

**Pièges classiques**
- Oublier l'ARC sur une installation ext4 avec un pool ZFS ajouté ensuite (ici, E03 l'avait prévu : le calcul de capacité doit s'appuyer sur la valeur **effective**, d'où le contrôle de `memoire.yml`).
- Prendre `osd_memory_target` pour une limite : c'est une cible ; un OSD en récupération la dépasse.
- Ballon sans pilote dans l'invité (`virtio-balloon`) : rien n'est rendu.
- Surallouer les VMs HA : la réserve N+1 devient fictive.
- Un outil de capacité qui répond « oui » quand l'API ne répond pas (le corrigé : code 1, « contrôle impossible »).

**En production chez MédiSphère**
Revue mensuelle de capacité (rapport de `ms-capacite-cluster`, tendance), seuil d'achat déclenché à 70 % de la capacité N+1, et capacité calculée avec la mesure réelle des serveurs achetés (Ceph sur NVMe consomme davantage par OSD).

---

### M09-E32 — Questions de production : cluster de virtualisation

**Réponses**

1. **Lien 0 coupé** : Corosync (knet) bascule sur le lien 1 en quelques secondes, sans perte de membre ; rien d'autre ne se passe (la redondance des liens sert à ça). **Puis lien 1 coupé sur `hv02` seul** : `hv02` n'a plus aucun lien. En quelques secondes, nouvelle appartenance : `hv01`+`hv03` (2 votes sur 3, quorate) d'un côté, `hv02` seul (pas de quorum) de l'autre. Sur `hv02` : `/etc/pve` en lecture seule ; son LRM, s'il a des ressources actives, perd son verrou et cesse de nourrir le chien de garde ; à t+60 s, `hv02` redémarre. Ses VMs HA : continuent sur `hv02` jusqu'à t+60 s, puis `fence` → `recovery` → `started` sur `hv01`/`hv03` vers t+2 min, démarrage de l'invité ensuite. Ses VMs non HA : tournent jusqu'au redémarrage de `hv02` (si le chien de garde est armé) puis sont arrêtées et **non** relancées ailleurs ; si `hv02` n'avait aucune ressource HA, il ne redémarre pas et ses VMs non HA continuent, ingérables. Au retour du lien, `hv02` rejoint.
2. **Réponse b.** `softdog` est un minuteur du noyau de `hv02` : pendant la pause, le temps « ne passe pas » pour l'invité ; à la reprise, le noyau constate le dépassement et le chien de garde déclenche… mais pas avant que des instructions aient été exécutées. Pendant ce court instant, la VM HA ancienne (toujours vivante dans `hv02`) peut écrire sur son disque RBD alors que la nouvelle tourne déjà sur `hv01` : **double écriture**, corruption possible du système de fichiers de l'invité. a) faux : rien ne garantit l'ordre ; c) faux : le chien de garde n'est réarmé que par `watchdog-mux`, qui était en pause lui aussi ; d) faux : le verrou exclusif RBD (*exclusive-lock*) est coopératif — un client qui croit le détenir encore peut écrire tant qu'il n'a pas été mis sur liste noire (*blocklist*), et Proxmox VE ne pose pas de liste noire. Avec le chien de garde **émulé**, le minuteur est dans QEMU, sur `pve01`… qui met aussi la carte en pause avec la VM : `qm suspend` fige tout le processus ; dans ce cas précis, le chien de garde émulé ne fait pas mieux. Un vrai chien de garde matériel (minuteur du BMC) ou un fencing par IPMI/PDU, lui, coupe le serveur figé **pendant** le gel. Morale : le fencing par chien de garde suppose qu'un nœud ne peut pas « s'arrêter puis repartir » ; c'est vrai d'un serveur physique, faux d'une VM. Un cluster de production ne tourne pas en imbriqué.
3. Avec un nombre **pair** de nœuds, une partition en deux moitiés égales n'a de quorum nulle part : le QDevice apporte **un** vote qui départage (algorithme `ffsplit` : il vote pour exactement une moitié). Avec un nombre **impair** de nœuds, `pvecm qdevice setup` donne au QDevice **N−1** votes (algorithme `lms`) : le cluster survit alors à la perte de tous les nœuds sauf un… mais si le QDevice lui-même tombe, **aucun** nœud ne peut plus tomber sans perte immédiate du quorum, et le QDevice devient un point unique de défaillance ; c'est pourquoi la documentation le déconseille avec un nombre impair (et `pvecm` avertit). À 5 nœuds + QDevice (4 votes, total 9, quorum 5) : si le QDevice et deux nœuds tombent, il reste 3 votes sur 9 : **pas de quorum**, alors que sans QDevice (5 votes, quorum 3), les 3 nœuds restants l'auraient gardé. Le QDevice a fait perdre le cluster.
4. Un nœud en maintenance (`noout`) : ses 2 OSD sont `down` mais restent `in` ; chaque PG a 2 copies actives sur 3 (`undersized+degraded`), `min_size 2` atteint : les écritures continuent. Un OSD d'un autre nœud tombe : les PG qui avaient une copie sur cet OSD passent à 1 copie active < `min_size` → **inactifs** : les I/O des VMs qui touchent ces PG se figent (pas d'erreur, un blocage). Avec `min_size 1`, les écritures continueraient sur une seule copie : au moindre incident sur ce dernier disque, perte de données définitive, et retour de l'OSD ancien avec des données périmées (*divergence*) difficile à réconcilier. En production : `size 3 / min_size 2`, et on termine la maintenance d'un nœud avant tout autre travail.
5. La HA relance la VM sur un nœud qui a une **réplique** du disque (la HA tient compte de la réplication) à partir du dernier instantané répliqué : perte de données jusqu'à **15 minutes** (plus la durée de la dernière synchronisation non terminée). Au retour du nœud, la VM tourne ailleurs ; la réplication repart dans l'autre sens (le nouveau nœud devient source) ; si les instantanés communs existent encore, synchronisation incrémentale, sinon complète ; les données écrites sur l'ancien nœud après la dernière réplication sont **perdues** (écrasées). La réplication ZFS est une HA « avec perte » : acceptable pour un service sans état ou tolérant.
6. **Réponse b**, `error`. `max_restart 1` : une nouvelle tentative de démarrage sur le même nœud ; `max_relocate 1` : une relocalisation vers un autre nœud, qui échoue aussi ; politique épuisée → `error`, la ressource est arrêtée et attend un humain. a) faux (pas d'autre tentative) ; c) `stopped` est un état demandé, pas un état d'échec ; d) `fence` concerne un nœud perdu. Sortie, une fois la cause corrigée : `ha-manager set vm:<ID> --state disabled` (acquitte l'erreur, arrête), puis `ha-manager set vm:<ID> --state started`.
7. **Maintenance successive** : chaque nœud est vidé (migrations à chaud), redémarré, réintégré : aucune interruption, le plus sûr, plus long ; c'est la procédure standard (RB-092). **`shutdown_policy=migrate`** : à l'arrêt ou au redémarrage d'un nœud, ses ressources HA migrent d'elles-mêmes ; utile pour qu'un `reboot` lancé par erreur ou par une automatisation ne fige pas de VM ; ne couvre pas les VMs non HA. **`disarm-ha`** (9.2) : désarme la HA de tout le cluster (ressources gelées en `freeze`, ou ignorées en `ignore`), chiens de garde relâchés : pour une intervention où **tout le cluster** peut perdre le quorum ou s'arrêter (coupure électrique planifiée, maintenance du réseau Corosync, montée majeure) — sans elle, une perte de quorum pendant l'intervention déclencherait des redémarrages par les chiens de garde. On rearme (`arm-ha`) à la fin.
8. Mémoire des VMs en clair sur le réseau : données de santé, clés TLS, secrets applicatifs ; toute machine qui voit le VLAN (VM compromise si le VLAN est accessible, port miroir, autre nœud compromis) peut les capturer ; injection possible dans le flux (pas d'authentification). Acceptable seulement sur un lien **dédié et isolé** (point à point, non routé, sans autre hôte), documenté, avec l'accord de la RSSI, et si le gain mesuré est nécessaire.
9. Il peut lire : la configuration de toutes les VMs (dont les **utilisateurs, mots de passe ou clés cloud-init** s'ils sont dans la configuration, les notes, les étiquettes), la topologie du cluster, les stockages, les tâches (qui a fait quoi), les utilisateurs et ACL — une carte complète pour un attaquant. Il ne peut rien modifier, rien démarrer, ni ouvrir de console (VM.Console absent). Plus grave qu'il n'y paraît : un mot de passe cloud-init en clair ou un secret dans une note donnent un accès aux invités. Mesures : pas de secret dans cloud-init ni dans les notes (clés publiques seulement, secrets par Vault), expiration et rotation du jeton, jeton limité à des chemins si possible (ACL sur `/vms` plutôt que `/` ?) — un compromis avec les besoins de la sonde.
10. **Réponse b** dans notre configuration, à condition que la règle ne touche que MGMT : Corosync continue sur le lien 0 (VLAN 32) ; le lien 1 de `hv01` passe `disconnected`. a) faux tant que le lien 0 vit ; c) faux ; d) faux : l'ordre d'évaluation dépend de la position des règles et de la version, il ne faut pas compter dessus. Pour savoir : `corosync-cfgtool -s` sur `hv01` (état de chaque lien) et `iptables-save` (la règle est-elle avant les règles automatiques ?). La redondance a masqué l'erreur : une sonde doit surveiller l'état de **chaque** lien, pas seulement le quorum.
11. `pve-daily-update` renouvelle un certificat ACME quand il reste moins de 30 jours : un certificat de 30 jours est **toujours** dans ce cas, donc une nouvelle commande ACME (et un nouveau défi) chaque jour, avec la VIP impossible à valider sur les nœuds qui ne la portent pas. En E26 : émission initiale par `certificats_acme`, VIP amenée sur le nœud, puis renouvellement par mTLS sans défi, à 15 jours de l'expiration. Quand le certificat de `pveproxy` change, `pveproxy` redémarre (`--restart 1`) : les connexions en cours sont coupées et rétablies, les sessions de l'interface (ticket d'authentification) restent valides ; un client d'API qui épinglait l'**empreinte** du certificat échoue (d'où la vérification par la racine, jamais par l'empreinte).
12. Oui : un état mixte est prévu et supporté **pendant** la montée (c'est l'objet de l'ordre MON → MGR → OSD), mais pas comme état durable : quelques heures, le temps de l'opération ; les fonctions nouvelles ne sont pas actives et certaines opérations sont déconseillées (création de pools, changements de configuration). Le point de non-retour officiel est `ceph osd require-osd-release tentacle` (plus aucun OSD Squid ne peut rejoindre) ; en pratique, un retour en arrière n'est plus raisonnable dès qu'un moniteur Tentacle a écrit dans sa base.
13. « La mémoire réellement utilisée aujourd'hui ne compte pas : si un serveur tombe, ses VMs redémarrent sur les autres avec **toute** leur mémoire, et l'hôte ne voit pas le cache que tes VMs utilisent en interne. La capacité, c'est ce qui reste quand on a perdu un serveur, une fois servis Proxmox, Ceph et le cache disque : 11,7 Go pour tout le monde. Tes 20 VMs de 2 Go, c'est 40 Go : la bonne réponse est OpenStack (ou 6 VMs ici avec un plancher de ballon). »
14. Causes : perte de quorum (lien coupé, autres nœuds arrêtés, `expected_votes` faux) → `pvecm status` ; service `pve-cluster` arrêté ou en échec → `systemctl status pve-cluster`, `journalctl -u pve-cluster` ; `corosync` arrêté ou en erreur (clé `authkey`, configuration) → `systemctl status corosync`, `journalctl -u corosync` ; base `config.db` corrompue ou disque plein (`/var/lib/pve-cluster`) → `df -h /var/lib`, journal de `pmxcfs`. Une écriture dans `/etc/pve` sans quorum est refusée parce que `pmxcfs` réplique chaque écriture à tous les membres par Corosync avec un ordre total : sans majorité, deux partitions pourraient écrire des versions divergentes du même fichier (cerveau divisé de la configuration). La lecture seule protège l'unicité de l'état.
15. Le nouveau `hv03` a de nouvelles clés d'hôte SSH ; les autres nœuds ont l'ancienne dans `/etc/pve/priv/known_hosts` (partagé) : toute opération qui passe par SSH vers `hv03` échoue avec un avertissement de changement de clé (« REMOTE HOST IDENTIFICATION HAS CHANGED ») : migrations à chaud **vers** `hv03` (type `secure`), réplication ZFS vers `hv03`, console et shell de `hv03` ouverts depuis un autre nœud, `pvecm updatecerts`. Les fonctions qui passent par l'API (proxy entre nœuds en HTTPS) marchent. À corriger : `ssh-keygen -R` dans le `known_hosts` du cluster, puis `pvecm updatecerts` sur le nouveau nœud.
16. Tiennent : HA par règles, Ceph `size 3 / min_size 2`, réseau de migration séparé, pare-feu de cluster, certificats de la PKI, sonde, code. À revoir : **quorum** (6 nœuds : nombre pair → une salle contre l'autre sans majorité ; il faut un arbitre dans un **troisième** lieu, un QDevice à PAR2 ou un septième vote) ; **liens Corosync** (un lien par salle et un lien inter-salles redondant, latence inter-salles < 5 ms, à mesurer) ; **domaines de défaillance Ceph** (règle CRUSH par salle : `size 4` à 2 copies par salle ou `size 3` en 2+1 ; *stretch mode* de Ceph à étudier) ; **HA** (règles d'affinité par salle pour que les VMs redondantes d'une application soient dans deux salles) ; réseau de migration intersalles dimensionné.

**Explications**

Les questions se répondent toutes avec les mêmes principes : quorum par majorité, auto-fencing par chien de garde avec un délai de garantie, réplication Ceph par hôte avec `min_size`, et capacité calculée sur la panne. Les « ça dépend » viennent presque toujours d'une hypothèse sur le matériel (chien de garde réel ou non, réseaux séparés ou non) ou sur l'application (supporte-t-elle une perte de données de 15 minutes ?).

---

### M09-E33 — Fiche de changement : mise à jour du cluster

**Solution**

Modèles : [`CHG-1059-mise-a-jour-hv-par1.md`](fichiers/M09-E33/medisphere/docs/virtualisation/changements/CHG-1059-mise-a-jour-hv-par1.md) et [`RB-092-mettre-a-jour-hv-par1.md`](fichiers/M09-E33/medisphere/docs/virtualisation/runbooks/RB-092-mettre-a-jour-hv-par1.md).

Points essentiels :
- **Standard** = pré-approuvé parce que fréquent, à faible risque et toujours identique. Le périmètre exclut explicitement tout ce qui change de nature : version majeure, série de noyau, configuration, « known issue ». La condition n° 3 (`apt list --upgradable` sans paquet hors périmètre) est ce qui **décide**, à chaque fois, que le changement reste standard.
- Ordre des nœuds : le maître HA et la VIP **en dernier**, pour ne provoquer qu'une bascule de chacun.
- Critères d'arrêt observables (commande + seuil), testés **avant** de passer au nœud suivant.
- Retour arrière **réel** : noyau précédent épinglé (`proxmox-boot-tool kernel pin`) ; tout le reste se corrige en avant. Le dire honnêtement est la qualité principale d'une fiche.
- La répétition remplit le compte rendu (versions avant/après, durée par nœud, incidents).

**Explications**

La valeur d'un changement standard tient à sa **répétabilité** : la même personne ou une autre obtient le même résultat, et tout écart se voit (critère d'arrêt). La fiche et le runbook se complètent : la fiche dit **quand** et **à quelles conditions** (gouvernance), le runbook dit **comment** (exécution).

**Alternatives**
- Mises à jour automatiques (`unattended-upgrades`) sur les nœuds : déconseillé sur un hyperviseur en cluster (redémarrages et versions non maîtrisés, nœuds à des versions différentes).
- Miroir local figé (Proxmox Offline Mirror) : versions identiques entre préproduction et production, rejouables ; à prévoir quand il y aura plusieurs clusters.

**Pièges classiques**
- Une fiche « standard » qui couvre une montée majeure par paresse.
- Pas de simulation (`apt full-upgrade -s`) : la suppression d'un paquet `proxmox-ve` passe inaperçue.
- Retour arrière théorique (« on réinstalle la version précédente ») sans dire ce qui n'est pas réversible.
- Oublier `noout` pendant le redémarrage d'un nœud qui porte des OSD.

**En production chez MédiSphère**
Mises à jour de sécurité hebdomadaires en fenêtre fixe, d'abord sur la préproduction (une semaine de recul), tableau de bord des versions par nœud (module 21), revue annuelle de la fiche standard par le comité de changement.

**Grille d'auto-évaluation** (Nadia relit)

| Critère | Attendu |
|---|---|
| Périmètre | inclus et exclus explicites ; la règle de sortie du standard est écrite |
| Préalables | chacun avec sa preuve (commande, résultat attendu) |
| Ordre des nœuds | justifié (maître HA, VIP) |
| Critères d'arrêt | observables, testés entre chaque nœud |
| Retour arrière | réel ; ce qui n'est pas réversible est dit |
| Majeure | renvoi au guide officiel et au changement normal |
| Répétition | compte rendu rempli |

---

### M09-E34 — Remplacer un nœud en temps limité

Pas de corrigé pas à pas : c'est RB-091 (E29), section « remplacement planifié », qui fait foi, et c'est lui qui est évalué. Ce qui distingue un remplacement planifié d'une perte, et qui doit apparaître dans la feuille de temps :

- **Avant** la destruction : maintenance HA (les ressources partent par migration à chaud : 0 s d'interruption, contre 2-3 min en E29), VMs non HA migrées, tâches de réplication réorientées, OSD sortis (`out`) puis arrêtés proprement, MON et MGR retirés **pendant que le nœud vit** (`pveceph mon destroy hv02`, `pveceph mgr destroy hv02`), puis arrêt propre et `pvecm delnode`.
- Ceph : avec trois hôtes et `size 3`, sortir les OSD de `hv02` ne permet **pas** de rétablir trois copies (pas de troisième hôte) : les PG restent `undersized` jusqu'au retour de `hv02`. Le retour d'expérience doit le dire : la vraie protection serait un quatrième hôte ou une règle CRUSH qui le permette.
- Après réintégration, `fence01` revient sur `hv02` par sa règle d'affinité (failback), par migration à chaud.

Temps typiques dans le lab : T1 5 min, T2 25 min, T3 25 min, T4 30 min, T5 15-25 min (récupération Ceph). Les pertes de temps les plus fréquentes : attendre la récupération Ceph sans rien faire d'autre en parallèle (préparer les rôles pendant ce temps), empreinte SSH de l'ancien `hv02` oubliée, `host.fw` du nœud absent (pare-feu de cluster qui bloque des flux jusqu'au passage de `pve_pare_feu`), version de paquets différente au moment de `pvecm add`.

**Grille** : critères du dossier (vérifiés par `lab/bin/check 09 34`), feuille de temps complète, gestes manuels expliqués, RB-091 mis à jour par MR (section « remplacement planifié »), retour d'expérience qui propose au moins une amélioration de l'outillage (par exemple un playbook « vider un nœud » qui enchaîne maintenance, migrations et sortie des OSD).
