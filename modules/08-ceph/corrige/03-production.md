# Module 08 — Corrigé du palier 3 : Production

> ⚠️ Corrigé — à lire après avoir cherché.

**Points non testés en conditions réelles** (signale tes retours, ils corrigent le workbook) :
- format JSON exact de certaines sorties de Tentacle sur lesquelles s'appuient les checks et les scripts : `ceph health detail` (champs `mutes[].sticky` et `ttl`), `ceph fs subvolumegroup info` (`bytes_quota`), `radosgw-admin account get` (`quota.enabled`, `quota.max_size`), `ceph mon dump` (`auth_allowed_ciphers`), `ceph orch upgrade status` (`is_paused`) ;
- procédure cephx de 20.2.4 (`aes256k`) : ce que cephadm fait **seul** pendant la mise à jour (clés des démons) ; capacité des clients de Debian 13 (bibliothèques Ceph 18.2 du paquet `ceph-common` de Debian, noyau 6.12 pour krbd et CephFS) à utiliser une clé `aes256k` — le corrigé suppose que **non** (hypothèse prudente) ; syntaxe d'une capacité moniteur combinant `profile rbd` et `allow r fsname=…` (E31) ;
- comportement d'un mgr en attente du module `prometheus` avec `standby_behaviour = default` (le corrigé ne s'appuie que sur le mode `error`, documenté) ; présence des métriques `ceph_pool_stored` / `ceph_pool_max_avail` / `ceph_pg_clean` sous ces noms en 20.2 ;
- application du certificat du tableau de bord par l'entrée standard (`ceph dashboard set-ssl-certificate -i -` à travers ssh) et relecture après `mgr module disable/enable` ; politique `x509.allow.dns` du provisioner `ceph-dashboard` avec trois noms ;
- `cephadm version` qui affiche la version du **binaire** sans lancer de conteneur ; URL `download.ceph.com/rpm-20.2.4/el9/noarch/cephadm` (pas de somme de contrôle publiée à côté au moment de la rédaction) ;
- redéploiement d'un OSD chiffré par `ceph orch osd rm --replace --zap` avec une spécification `encrypted: true` (identifiant conservé) ;
- noms et réglages posés par les paliers précédents et repris ici : règles CRUSH `ssd-baie` / `hdd-baie` (domaine `rack`, une baie par nœud, E14), seuils 0,75 / 0,85 / 0,95 (E20), image de test `rbd-test/disque01` (E06), étiquette `mgr` sur les trois nœuds et deux mgr (E23), `outils/lib.sh`, `config/cluster.yaml` et `outils/pool-repliquee.sh` de `plateforme/ceph` (E05, E23), rôle des nœuds Ceph (E02). Si les tiens diffèrent, la logique est la même.

**Rappel** : aucune nouvelle VM dans ce palier. Fichiers de solution : `corrige/fichiers/M08-E24/` à `M08-E31/`, `M08-E33/`.

---

### M08-E24 — Superviser Ceph

**Solution**

Fichiers (projet `plateforme/outils`) : [`bin/ms-verif-ceph`](fichiers/M08-E24/outils/bin/ms-verif-ceph), [`etc/ms-verif-ceph.conf`](fichiers/M08-E24/outils/etc/ms-verif-ceph.conf), tests [`tests/bats/ms-verif-ceph.bats`](fichiers/M08-E24/outils/tests/bats/ms-verif-ceph.bats) (18 tests, sans réseau), unités [`ms-verif-ceph.service`](fichiers/M08-E24/outils/systemd/ms-verif-ceph.service) et [`.timer`](fichiers/M08-E24/outils/systemd/ms-verif-ceph.timer), [extrait du Taskfile](fichiers/M08-E24/outils/Taskfile-install-extrait.yml), [section Ceph de `docs/astreinte.md`](fichiers/M08-E24/outils/docs/astreinte-extrait.md). Projet `plateforme/ceph` : [`outils/cert-dashboard.sh`](fichiers/M08-E24/ceph/outils/cert-dashboard.sh), unités [`ceph-cert-dashboard.service`](fichiers/M08-E24/ceph/outils/systemd/ceph-cert-dashboard.service) et [`.timer`](fichiers/M08-E24/ceph/outils/systemd/ceph-cert-dashboard.timer). Projet `plateforme/ansible` : [provisioner `ceph-dashboard`](fichiers/M08-E24/ansible/inventories/lab/group_vars/role_pki/step_ca.yml.extrait).

*1. Lecture de la santé.* `ceph health` donne l'état et un résumé ; `health detail` liste chaque contrôle avec son code (`OSD_DOWN`, `PG_DEGRADED`…) et les objets concernés ; la sortie JSON donne `checks.<CODE>.severity`, `summary`, `detail`, `muted` — c'est elle qu'on exploite dans un script. Classement retenu (repris dans l'astreinte) : immédiat = perte d'accès ou risque imminent (`PG_AVAILABILITY`, `OSD_FULL`, `POOL_FULL`, `MON_DOWN` qui menace le quorum, `OSD_DOWN` sur deux hôtes, S3 en erreur) ; le matin = redondance réduite mais service rendu (`OSD_DOWN` d'un seul hôte, `PG_DEGRADED`, `*_NEARFULL`, `RECENT_CRASH`, `AUTH_INSECURE_*`). `ceph health mute OSD_DOWN 4h` masque un contrôle pour 4 h ; sans durée, il reste masqué jusqu'à ce qu'il disparaisse ; avec `--sticky`, il reste masqué **même** s'il disparaît puis revient : à proscrire. Un plantage de démon laisse un rapport (`ceph crash ls`) qui maintient `RECENT_CRASH` 2 semaines : on le lit (`crash info`), on ouvre un ticket si besoin, puis `ceph crash archive <id>` (ou `archive-all` après lecture).

*2. Métriques.*

```
[admin@ceph01 ~]$ sudo ceph mgr module enable prometheus
[admin@ceph01 ~]$ sudo ceph config set mgr mgr/prometheus/standby_behaviour error
[admin@ceph01 ~]$ sudo ceph mgr stat
admin@adm01:~$ for h in ceph01 ceph02 ceph03; do printf '%s ' "$h"; curl -s -o /dev/null -w '%{http_code} %{size_download}\n' "http://$h.par1.medisphere.internal:9283/metrics"; done
ceph01 200 41893
ceph02 500 …
ceph03 000 0
```

Hôte sans mgr : connexion refusée (`000`). Mgr en attente : avec `standby_behaviour = default`, une réponse **sans** métriques du cluster (ce qui peut piéger une sonde naïve) ; avec `error`, un code HTTP d'erreur (`standby_error_status_code`, 500 par défaut). Métriques utiles : `ceph_health_status` (0, 1, 2), `ceph_health_detail{name,severity}` (1 si actif), `ceph_mon_quorum_status{ceph_daemon}`, `ceph_osd_up` / `ceph_osd_in{ceph_daemon}`, `ceph_pg_total` / `ceph_pg_active` / `ceph_pg_clean{pool_id}`, `ceph_pool_metadata{pool_id,name}` (nom des pools), `ceph_pool_stored` et `ceph_pool_max_avail` (occupation, comme `%USED` de `ceph df`), `ceph_cluster_total_bytes` / `ceph_cluster_total_used_bytes`. Les compteurs de performance par démon ne sont plus exportés par ce module (`exclude_perf_counters`, défaut `true`) : c'est le rôle du service `ceph-exporter`.

*3. La sonde.* Points de conception :
- **Un seul mgr actif** : la sonde interroge tous les hôtes de la configuration et exige qu'**un et un seul** serve `ceph_health_status`. Zéro : aucun contrôle de cluster possible, donc KO (« rien vu » n'est pas « tout va bien », M02-E26). Deux : réglage `standby_behaviour` perdu, résultat non fiable, KO.
- **Pas d'identité cephx** : la sonde ne lit que les métriques HTTP, pas besoin d'une clé sur `adm01`. Le revers : pas de détail fin (quels PG, quel objet) — c'est le rôle de l'humain d'astreinte, avec `ceph health detail`.
- **Seuils dans la configuration** : nombre de MON et d'OSD attendus (un OSD absent des métriques est une anomalie, pas un « tout va bien » silencieux), seuil de pool (80 %, option `--seuil-pool`), seuil d'occupation brute (40 %, voir la politique de stockage : avec 2 OSD SSD par nœud, la perte de l'un charge l'autre, qui doit rester sous `backfillfull`, 0,85 depuis E20), points TLS.
- **Tests** : `curl` et `openssl` sont remplacés par des fonctions dans les tests `bats`, qui produisent un texte de métriques à partir de variables d'état ; chaque contrôle a un test rouge, plus les cas « aucun mgr », « deux mgr », « configuration vide », « option inconnue ».

*4. Planification et preuve.* `task install:systeme` installe script, configuration et unités ; `sudo systemctl enable --now ms-verif-ceph.timer`. Test :

```
[admin@ceph01 ~]$ sudo ceph orch daemon stop osd.4
admin@adm01:~$ journalctl -u ms-verif-ceph -n 5 ; journalctl -t ms-alerte -n 3
… KO  osd          osd.4:down
… ÉCHEC ms-verif-ceph.service …
[admin@ceph01 ~]$ sudo ceph orch daemon start osd.4
```

Délai mesuré : de quelques secondes à 5 minutes, dicté par le **timer** (un OSD arrêté proprement prévient lui-même les moniteurs ; un OSD qui disparaît brutalement est déclaré `down` par ses pairs en une vingtaine de secondes, `osd_heartbeat_grace`). 5 minutes laissent à l'astreinte le temps de réagir avant que l'OSD soit marqué `out` (10 minutes, `mon_osd_down_out_interval`).

*5. Le tableau de bord.* Même chemin que le certificat du point d'entrée S3 (M08-E11) : provisioner JWK dédié `ceph-dashboard` (clé chiffrée en Vault `critique`, mot de passe dans `~/.config/workbook/step-ceph-dashboard.pass`, [extrait](fichiers/M08-E24/ansible/inventories/lab/group_vars/role_pki/step_ca.yml.extrait)), dont la politique n'autorise que les trois noms des nœuds ; **un** certificat de 30 jours portant les trois noms en SAN, posé **globalement** : quel que soit le mgr actif, il présente un certificat à son nom. Le script [`cert-dashboard.sh`](fichiers/M08-E24/ceph/outils/cert-dashboard.sh) émet (ou renouvelle par TLS mutuel à 15 jours de l'échéance), applique par l'entrée standard de ssh (la clé ne touche jamais le disque des nœuds ; le mgr la stocke dans sa configuration), redémarre le module et vérifie l'empreinte présentée par le mgr actif :

```
admin@adm01:~/src/ceph$ outils/cert-dashboard.sh --force
admin@adm01:~/src/ceph$ ssh ceph01 sudo ceph mgr services          # "dashboard": "https://ceph02.par1.medisphere.internal:8443/"
admin@adm01:~$ openssl s_client -connect ceph02.par1.medisphere.internal:8443 -verify_hostname ceph02.par1.medisphere.internal \
    -CAfile /usr/local/share/ca-certificates/medisphere-root-ca.crt </dev/null 2>/dev/null | grep -E 'Verify return|subject='
admin@adm01:~$ ssh ceph01 sudo ceph mgr fail ; sleep 30 ; ssh ceph01 sudo ceph mgr services   # même vérification sur le nouvel actif
admin@adm01:~$ sudo systemctl enable --now ceph-cert-dashboard.timer
```

Aucun flux nouveau : `adm01` joint `ca01` et le VLAN 30. Pourquoi pas l'ACME **sur** les nœuds ? Le défi HTTP-01 demande le port 80 de chaque nœud (ouvert dans `firewalld` et dans `pare_feu.yml` depuis `ca01`), un client `step` sur Rocky et un crochet qui pousse le certificat dans Ceph depuis chaque nœud : trois fois plus de pièces pour le même résultat. C'est l'alternative si la politique de certification interdit les provisioners JWK pour des serveurs.

Comptes (mot de passe dans un fichier temporaire 600 sur un hôte `_admin`, puis `shred`) :

```
[root@ceph01 ~]# install -m 600 /dev/null /root/mdp ; vi /root/mdp           # mot de passe tiré de Vault
[root@ceph01 ~]# ceph dashboard ac-user-create <MOI> -i /root/mdp read-only
[root@ceph01 ~]# ceph dashboard ac-user-set-password admin -i /root/mdp-admin   # même méthode, autre fichier
[root@ceph01 ~]# ceph dashboard set-pwd-policy-enabled true
[root@ceph01 ~]# shred -u /root/mdp /root/mdp-admin
[root@ceph01 ~]# ceph dashboard ac-user-show <MOI>
```

Connecté en `<MOI>`, les boutons de création et de modification sont absents ou grisés ; une action forcée par l'API renvoie 403. Le mot de passe d'`admin` reste en Vault `lab` (`vault_ceph_dashboard_admin_mdp`, E03) et dans `~/.config/workbook/ceph-dashboard.pass` : compte de bris de glace, usage tracé.

*6. Astreinte* : voir l'[extrait](fichiers/M08-E24/outils/docs/astreinte-extrait.md).

**Explications**

Le modèle de santé de Ceph est **déclaratif** : chaque démon et chaque module publie des contrôles nommés, le moniteur les agrège, et l'état global est le pire des contrôles non masqués. C'est très riche, mais ce n'est pas une supervision : personne n'est prévenu, rien n'est historisé (hors `healthcheck history`), et un cluster `HEALTH_OK` peut très bien être injoignable de l'extérieur (VIP S3, certificat). D'où une sonde qui regarde **aussi** le service rendu (S3, TLS), comme `ms-verif-services` le fait pour le socle. Le module `prometheus` est la passerelle naturelle vers la future pile d'observabilité (M21) : la sonde d'aujourd'hui lit déjà les métriques que Prometheus moissonnera demain.

**Alternatives**
- Déployer la pile de supervision de cephadm (Prometheus, Alertmanager, Grafana, `node-exporter`, `ceph-exporter`) : complète et préconfigurée (tableaux et alertes de Ceph), mais ~1,5 à 2 Gio de mémoire de plus sur des nœuds de 6 Gio, et une seconde pile à maintenir à côté de celle du M21. Choix du workbook : non en v1.
- Sonde par `ceph health detail --format json` via SSH depuis `adm01` : détail plus fin, mais il faut une identité cephx (même en lecture) sur `adm01` et l'accès SSH ; les métriques HTTP suffisent pour alerter.
- Mettre le module `prometheus` en TLS (`ceph prometheus set-ssl-certificate`, port 9284) ou derrière le service `mgmt-gateway` : à faire quand les métriques sortiront du VLAN de stockage (M21).
- Certificat par instance de mgr (`ceph dashboard set-ssl-certificate <mgr> -i …`), émis par ACME sur chaque nœud : plus conforme à « ACME pour tout serveur », mais trois clients, trois défis HTTP-01 (port 80 ouvert dans `firewalld`) et un crochet par nœud.
- Certificat pour un nom générique (`ceph.par1…`) : impossible à faire suivre au mgr actif sans répartiteur (le service `mgmt-gateway` de cephadm le fait).

**Pièges classiques**
- Sonde qui prend « le premier hôte qui répond 200 » : avec le comportement par défaut d'un mgr en attente, elle peut conclure que tout va bien sans aucune métrique.
- Seuils codés en dur dans le script ; nombre d'OSD attendu absent (un OSD retiré par erreur disparaît des métriques : rien n'est « down »).
- Mise en sourdine sans durée « le temps de regarder », jamais retirée.
- Certificat du tableau de bord au nom d'un seul hôte : erreur de nom dès qu'un autre mgr devient actif (on ne le voit qu'au premier `mgr fail`).
- Mot de passe passé en argument (`ac-user-create … <mot de passe>` : ancienne syntaxe refusée, et visible dans `ps` et l'historique).
- Renouvellement qui réussit mais n'est pas appliqué (ou appliqué sans redémarrer le module) : le fichier est neuf, le tableau de bord sert l'ancien jusqu'à expiration ; d'où le contrôle de l'empreinte présentée.

**En production chez MédiSphère**
Moissonnage des métriques du mgr actif par Prometheus (M21), règles d'alerte reprises du *mixin* officiel de Ceph, tableaux de bord Grafana, `ceph-exporter` pour la latence par OSD ; tableau de bord derrière le SSO (M24, OIDC) avec des rôles par équipe ; la sonde reste comme contrôle de bout en bout indépendant.

---

### M08-E25 — Sauvegarder hors du cluster

**Solution**

Fichiers : rôle [`sauvegarde_ceph`](fichiers/M08-E25/ansible/roles/sauvegarde_ceph/) (script [`wb-backup-ceph.sh`](fichiers/M08-E25/ansible/roles/sauvegarde_ceph/files/wb-backup-ceph.sh), gabarits, unités) pour `cephcli01` ; rôle [`ceph_export_config`](fichiers/M08-E25/ansible/roles/ceph_export_config/) (script [`wb-ceph-export-config`](fichiers/M08-E25/ansible/roles/ceph_export_config/files/wb-ceph-export-config)) pour `ceph01` ; variables [`cephcli01`](fichiers/M08-E25/ansible/inventories/lab/host_vars/cephcli01/sauvegarde_ceph.yml) et [`ceph01`](fichiers/M08-E25/ansible/inventories/lab/host_vars/ceph01/ceph_export_config.yml), [modèle de Vault](fichiers/M08-E25/ansible/inventories/lab/vault-critique-m08-e25.yml.exemple), [`playbooks/sauvegarde-ceph.yml`](fichiers/M08-E25/ansible/playbooks/sauvegarde-ceph.yml) ; PBS : [`pbs-jeton-ceph.sh`](fichiers/M08-E25/pbs01/pbs-jeton-ceph.sh), [règle d'entrée](fichiers/M08-E25/pbs01/pbs01-nftables-extrait.nft) ; [extrait de `pare_feu.yml`](fichiers/M08-E25/ansible/inventories/lab/host_vars/gw01/pare_feu.yml.extrait) ; documentation : [`sauvegarde.md`](fichiers/M08-E25/medisphere/docs/stockage/sauvegarde.md), [`tests/restauration-ceph.md`](fichiers/M08-E25/medisphere/docs/stockage/tests/restauration-ceph.md).

*1. Lecture* (réponses attendues) :
- `export-diff` **sans** `--from-snap` : tous les blocs écrits depuis la création de l'image jusqu'à l'instantané (un « complet », mais au format différentiel, qui s'applique sur une image vide) ; **avec** : seulement les blocs modifiés entre les deux instantanés. Les zones jamais écrites ne sont pas transportées ; `rbd export` (image brute) les écrit comme des zéros ou des trous selon la destination.
- Instantané de départ supprimé sur le cluster : `export-diff --from-snap` échoue (il ne peut plus calculer la différence) ; il faut repartir d'un complet.
- Un instantané RBD est **cohérent en cas de panne** : il fige les blocs à un instant, comme une coupure de courant ; un système de fichiers journalisé s'en remet, une base de données aussi en général, mais rien ne garantit que les écritures applicatives en cours sont complètes. Geler le système de fichiers (`fsfreeze -f` depuis la machine qui l'a monté) pendant la prise d'instantané le rend cohérent au niveau du système de fichiers.

*2. Conception* : voir [`sauvegarde.md`](fichiers/M08-E25/medisphere/docs/stockage/sauvegarde.md). Instantané `sauv-AAAAMMJJ` ; complet le dimanche ou quand la base manque, incrémental sinon ; un seul instantané de sauvegarde conservé sur le cluster (la base du lendemain) ; restauration à J-n = complet du dimanche précédent + incrémentaux jusqu'à J-n, d'où une rétention PBS d'au moins 14 jours.

*3. Identités et flux* :

```
[admin@ceph01 ~]$ sudo ceph auth get-or-create client.sauvegarde mon 'profile rbd' osd 'profile rbd pool=rbd-test, profile rbd pool=rbd-equipes' >/dev/null
admin@adm01:~/src/ansible$ ssh ceph01 'sudo ceph auth print-key client.sauvegarde' \
    | uv run ansible-vault encrypt_string --vault-id critique@outils/vault-pass-client.sh --stdin-name vault_ceph_cle_client_sauvegarde
admin@adm01:~$ ssh-keygen -t ed25519 -N '' -C wb-sauvegarde@cephcli01 -f /tmp/export-config    # privée → Vault, puis shred -u
admin@adm01:~$ proxmox-backup-client key create /tmp/pbs-cephcli01.key --kdf none              # paperkey, Vault, shred -u
root@pbs01:~# ./pbs-jeton-ceph.sh
```

`profile rbd` (et non `rbd-read-only`) : créer et supprimer un instantané écrit dans l'en-tête de l'image. Le pool `rbd-equipes` (E31) peut ne pas encore exister : une capacité peut citer un pool futur. Flux : `cephcli01` → `pbs01:8007` dans `pare_feu.yml` (entrée VLAN 30, sortie tunnel `wg0`) **et** règle d'entrée de `pbs01` ; `cephcli01` → `ceph01:22` reste dans le VLAN 30 (pas de passerelle).

*4. Configuration du cluster* : compte `wb-sauvegarde` sur `ceph01`, clé autorisée `restrict,from="10.10.30.20",command="sudo -n /usr/local/sbin/wb-ceph-export-config"`, une seule ligne `sudoers` (validée par `visudo -cf`). Preuve :

```
root@cephcli01:~# ssh -i /etc/wb-backup/ssh-export-config wb-sauvegarde@ceph01.par1.medisphere.internal 'id; cat /etc/shadow' | tar -tf - | head -3
./
./versions.json
./status.json
```

La commande demandée (`id; cat /etc/shadow`) est **ignorée** (et tracée par `logger`) : seul l'export s'exécute. Si `ssh_durci` (M04) restreint un jour les comptes autorisés, `wb-sauvegarde` doit y figurer. Le script n'appelle jamais le magasin clé-valeur des moniteurs (clés LUKS des OSD, clé SSH de l'orchestrateur, secrets des modules) : inutile sans les disques et c'est le contenu le plus sensible du cluster (CVE-2026-50152). Les identités cephx, elles, y sont, avec leurs clés : c'est ce qui permet aux clients existants de se réauthentifier sur un cluster reconstruit ; l'archive est chiffrée côté client.

*5. Rôle et script* : voir les fichiers. Ordre du script : liste des images (explicite + découverte par métadonnée dans `rbd-equipes`, tous espaces de noms — c'est le mécanisme que les équipes utiliseront en E31), instantanés, exports, configuration, envoi (`rbd.pxar` dans `host/ceph-par1-rbd`, `config.pxar` dans `host/ceph-par1-config`), **puis seulement** suppression des instantanés antérieurs. Un échec à n'importe quelle étape laisse les instantanés en place : l'incrémental du lendemain repart de la dernière base **envoyée**… à condition que la base de la veille n'ait pas été supprimée (sinon complet).

*6. Restauration* (feuille complète dans le [modèle](fichiers/M08-E25/medisphere/docs/stockage/tests/restauration-ceph.md)). Pour simuler une chaîne sans attendre une semaine, lance le script à la main avec des dates **passées** (un dimanche puis les deux jours suivants), sinon les instantanés « du futur » fausseraient le choix de la base les nuits suivantes :

```
root@cephcli01:~# WB_DATE=20260927 /usr/local/sbin/wb-backup-ceph.sh      # dimanche : complet
root@cephcli01:~# WB_DATE=20260928 /usr/local/sbin/wb-backup-ceph.sh      # incrémental
root@cephcli01:~# WB_DATE=20260929 /usr/local/sbin/wb-backup-ceph.sh      # incrémental
root@cephcli01:~# set -a; . /etc/wb-backup/pbs-cephcli01.env; set +a
root@cephcli01:~# proxmox-backup-client snapshot list --ns par1/ceph
root@cephcli01:~# for s in <INSTANTANE-PBS-1> <INSTANTANE-PBS-2>; do \
      proxmox-backup-client restore "$s" rbd.pxar "/var/lib/wb-backup/restau/${s##*/}" --ns par1/ceph --keyfile /etc/wb-backup/pbs-cephcli01.key; done
root@cephcli01:~# rbd --id sauvegarde create --size 10G rbd-test/restau-disque01
root@cephcli01:~# rbd --id sauvegarde import-diff /var/lib/wb-backup/restau/<…>/rbd-test__disque01.complet.sauv-20260927.diff rbd-test/restau-disque01
root@cephcli01:~# rbd --id sauvegarde import-diff /var/lib/wb-backup/restau/<…>/rbd-test__disque01.sauv-20260927.sauv-20260928.diff rbd-test/restau-disque01
root@cephcli01:~# rbd --id sauvegarde export rbd-test/restau-disque01@sauv-20260928 - | sha256sum
```

`<INSTANTANE-PBS-n>` : les sauvegardes `host/ceph-par1-rbd/<horodatage>` contenant le complet et les incrémentaux voulus (lues dans `snapshot list` et `catalog dump`). L'instantané `sauv-20260928` de l'original a été supprimé par le passage suivant : la somme de référence est donc celle notée **au moment de l'écriture** des données témoins (ou celle de `MANIFESTE.tsv` pour les fichiers d'export). Configuration : `restore … config.pxar`, extraction du `tar`, puis `diff` entre `orch-ls-export.yaml` et les fichiers `specs/` de `plateforme/ceph` (écart attendu : aucun, sinon le code ne décrit pas tout). Enfin `rbd rm rbd-test/restau-disque01` (après `rbd snap purge`).

**Explications**

Les instantanés RBD sont des objets copiés à l'écriture (*copy-on-write*) dans le cluster : peu coûteux, instantanés, mais **dans** le cluster. `export-diff` lit, entre deux instantanés, la liste des extents modifiés (grâce à la carte des objets, `object-map`/`fast-diff`, qui évite de tout relire) et les écrit dans un format simple que `import-diff` rejoue en vérifiant l'instantané de départ. On obtient des sauvegardes incrémentales sans lire l'image entière. PBS apporte ce que le cluster n'a pas : un autre site, un chiffrement dont la clé n'est pas sur le serveur de sauvegarde, une rétention, et la déduplication.

**Alternatives**
- Export complet quotidien vers PBS en `.img` (déduplication de PBS) : restauration sans chaîne, mais relecture complète de chaque image chaque nuit ; bon choix pour quelques dizaines de Gio.
- `rbd-mirror` (mode instantané) vers un cluster à PAR2 : RPO de quelques minutes, bascule possible ; mais c'est de la **réplication** (une suppression ou un chiffrement malveillant se répliquent à l'instantané suivant) et cela suppose un second cluster.
- Sauvegarde dans les invités (agent PBS dans la VM, `pg_dump`) : cohérence applicative, restauration fine ; complémentaire, à la charge des équipes.
- Backy2 / Benji (outils dédiés aux sauvegardes RBD différentielles) : intéressants, mais une brique de plus, peu maintenue.

**Pièges classiques**
- Supprimer les instantanés **avant** la confirmation de l'envoi : un échec de PBS et la chaîne est rompue.
- Rétention PBS plus courte que l'intervalle entre deux complets : des incrémentaux orphelins, inutilisables.
- Restaurer « par-dessus » l'image d'origine pour tester.
- Une clé cephx d'administration sur `cephcli01` « pour aller plus vite », ou une clé SSH qui ouvre un shell sur `ceph01`.
- Exporter le magasin clé-valeur des moniteurs avec la configuration : une archive de sauvegarde devient le plus gros secret de l'entreprise.
- Ne vérifier que la présence de la sauvegarde (la sonde est verte) sans jamais restaurer.

**En production chez MédiSphère**
Sauvegarde des compartiments S3 de MédiDoc (ADR-0080, action F5), restauration de test trimestrielle chronométrée (preuve HDS), alerte « sauvegarde Ceph de plus de 26 h » dans `ms-verif-sauvegardes`, synchronisation de `par1/ceph` vers un second datastore hors site, et gel applicatif (`fsfreeze` ou point de cohérence de la base) orchestré avec les équipes pour les volumes de bases de données.

---

### M08-E26 — Mettre à jour Ceph sans interruption

**Solution**

Fichiers : [RB-082](fichiers/M08-E26/medisphere/docs/stockage/runbooks/RB-082-mettre-a-jour-ceph.md), [boucles témoins](fichiers/M08-E26/cephcli01/boucles-temoins.sh), [variables de version](fichiers/M08-E26/ansible/inventories/lab/group_vars/env_m08/ceph.yml.extrait) (`ceph_image`, `ceph_noeud_version`).

*1. Lecture des avis* (à la date de rédaction ; relis-les, ils peuvent avoir évolué) :

| CVE | Composant | Exploitation | Corrigé par la mise à jour seule ? | Action supplémentaire |
|---|---|---|---|---|
| CVE-2025-30156 | cephx (AES-128-CBC sans authentification, IV fixe) | une clé cephx de bas privilège, ou l'écoute du trafic cephx, permet de forger des titres | non : le correctif ajoute un **nouveau type de clé** `aes256k` ; les clés existantes restent du type vulnérable | procédure *Upgrading and Rotating CephX Keys* : cephadm traite les démons, **pas** les clients ; six contrôles `AUTH_INSECURE_*` apparaissent, attendus → E27 |
| CVE-2026-54330 | RGW, vérification SigV4 | quiconque détient une URL présignée peut ajouter des en-têtes `x-amz-*` non signés (élévation) | oui | **avant** la mise à jour, en multisite seulement : `rgw_sigv4_insecure = true`, puis `false` après tous les sites. Non applicable ici (un seul site, pas de multisite) |
| CVE-2026-39944 | RGW STS | jetons de session modifiables (CBC, bascule de bits) | oui | aucune listée |
| CVE-2026-50152 | moniteurs | une identité `mon 'allow r'` lit tout le magasin clé-valeur (clés LUKS, clé SSH de l'orchestrateur) | oui pour la faille | **renouveler la clé SSH de l'orchestrateur** (et évaluer les autres secrets du magasin) → E27 |

Le passage à 20.2.3 → 20.2.4 ne change pas de série : pas de `require_osd_release` à relever, clients compatibles.

*2. Préparation* :

```
[admin@ceph01 ~]$ sudo ceph -s ; sudo ceph mgr stat ; sudo ceph orch host ls
[admin@ceph01 ~]$ sudo ceph orch upgrade check --image quay.io/ceph/ceph:v20.2.4
[admin@ceph01 ~]$ sudo ceph osd pool set noautoscale
```

`upgrade check` tire l'image sur les hôtes et liste les démons qui seraient mis à jour, sans rien redémarrer. `noautoscale` évite qu'une fusion ou division de PG ne commence au milieu des redémarrages (recommandation de la page *Upgrading Ceph*). CephFS : par défaut l'orchestrateur ramène `max_mds` à 1 le temps de la mise à jour des MDS (sans effet ici, `max_mds` vaut déjà 1) ; RGW : les démons sont redémarrés un par un, haproxy retire et réintègre chacun.

*3-4. Mise à jour échelonnée* :

```
[admin@ceph01 ~]$ sudo ceph orch upgrade start --image quay.io/ceph/ceph:v20.2.4 --daemon-types mgr
[admin@ceph01 ~]$ sudo ceph orch upgrade status ; sudo ceph versions        # mgr en 20.2.4, le reste en 20.2.3
[admin@ceph01 ~]$ sudo ceph orch upgrade start --image quay.io/ceph/ceph:v20.2.4
[admin@ceph01 ~]$ sudo ceph -W cephadm
[admin@ceph01 ~]$ sudo ceph orch upgrade pause ; sleep 120 ; sudo ceph -s ; sudo ceph orch upgrade resume
```

Ordre observé : mgr (bascule vers le mgr à jour), mon (un par un, quorum vérifié), crash, osd (un par un, `ok-to-stop` avant chacun, `OSD_DOWN` et PG `degraded` passagers), mds (actif puis attente : bascule de quelques secondes), rgw. Haproxy et keepalived de l'ingress gardent **leur** image (ce ne sont pas des démons Ceph). Durée typique dans le lab : 40 à 70 minutes, dont l'essentiel pour les 9 OSD.

*5. Après* :

```
[admin@ceph01 ~]$ sudo ceph versions
[admin@ceph01 ~]$ sudo ceph osd pool unset noautoscale
[admin@ceph01 ~]$ sudo ceph health detail          # AUTH_INSECURE_* attendus → ticket SEC-953 (E27)
admin@cephcli01:~$ ./boucles-temoins.sh stop ; ./boucles-temoins.sh bilan
rbd      3900 opérations, 0 échec(s), 6 lente(s), max 3.412 s à …
cephfs   3900 opérations, 0 échec(s), 4 lente(s), max 5.104 s à …
s3       3880 opérations, 0 échec(s), 9 lente(s), max 4.870 s à …
```

(Valeurs indicatives.) Les latences hautes tombent pendant les redémarrages d'OSD primaires (le client attend la nouvelle carte et le nouveau primaire), la bascule de MDS et le redémarrage du RGW derrière haproxy ; **aucun échec** est le critère. Paquets des nœuds : fusion de la MR (`ceph_image`, `ceph_noeud_version: "20.2.4"`), pipeline de `plateforme/ansible`, rôle `ceph_noeud` appliqué aux trois nœuds (dépôt `rpm-20.2.4`, `cephadm` et `ceph-common` mis à jour, contrôle de `cephadm version` par le rôle lui-même). `ceph-common` en 20.2.4 sur les hôtes `_admin`, c'est aussi le client qui utilisera la nouvelle clé `client.admin` en E27. La MR n'est fusionnée qu'**après** la mise à jour : avant, le code aurait décrit un état que le cluster n'avait pas encore.

*6. RB-082* : voir le fichier.

**Explications**

cephadm met à jour démon par démon en remplaçant l'image du conteneur et en redémarrant ; la sécurité vient des contrôles que le cluster lui-même fournit (`ok-to-stop` pour les OSD et les MON, présence d'un mgr en attente, santé entre deux étapes). L'absence d'interruption tient à trois choses : réplication 3 avec `min_size` 2 (un OSD arrêté ne bloque aucun PG), quorum de 3 MON (un MON arrêté laisse 2 sur 3), et redondance des services d'accès (2 mgr, MDS en attente, 2 RGW derrière une VIP). Un composant non redondant (un seul RGW, un seul MDS) aurait produit une vraie coupure.

**Alternatives**
- Mise à jour d'un seul coup (sans échelonnement) : plus simple, même résultat dans une même série ; l'échelonnement prend tout son sens pour une version majeure (valider les mgr, puis un hôte d'OSD, avant le reste).
- Mise à jour par `--ceph-version 20.2.4` plutôt que par image : équivalent avec le registre officiel ; l'image explicite (voire l'empreinte `@sha256:`) est plus traçable.
- Registre local (miroir de `quay.io`) : indispensable sans accès Internet, et pour figer exactement ce qui est déployé (M13).

**Pièges classiques**
- Lancer sans mgr en attente (`UPGRADE_NO_STANDBY_MGR`) ou avec un hôte injoignable (la mise à jour se met en pause).
- Oublier `noautoscale`… ou oublier de le retirer (l'autoscaler reste figé des mois).
- Traiter les nouveaux `AUTH_INSECURE_*` par une sourdine permanente pour « revenir au vert ».
- Intervenir à la main sur un démon pendant que l'orchestrateur travaille (redémarrage manuel, `systemctl`) : états incohérents.
- Oublier les paquets des nœuds (`ceph_noeud_version`) : `cephadm` et `ceph` locaux restent en 20.2.3 (et le rôle, au passage suivant, ne dit rien tant que la variable n'a pas changé).
- Croire qu'on peut « revenir en 20.2.3 » en relançant une mise à jour vers l'ancienne image.

**En production chez MédiSphère**
Miroir local des images (Harbor, M13) avec empreintes figées, mise à jour d'abord sur un cluster de préproduction, fenêtre annoncée, échelonnement par hôte (`--hosts`) sur un vrai parc, supervision des latences clientes (SLO, M21) pendant l'opération, et veille de sécurité (liste `ceph-announce`) qui ouvre le CHG.

---

### M08-E27 — Sécuriser Ceph : chiffrement et clés

**Solution**

Fichiers : [`specs/osd.yaml`](fichiers/M08-E27/ceph/specs/osd.yaml) (`plateforme/ceph`), [clé de l'orchestrateur](fichiers/M08-E27/ansible/inventories/lab/group_vars/env_m08/cle-orchestrateur.yml.extrait) (variable du rôle `ceph_noeud`, `plateforme/ansible`).

*1. État des lieux* :

```
[admin@ceph01 ~]$ sudo ceph config get osd ms_cluster_mode ; sudo ceph config show osd.0 ms_cluster_mode    # crc secure
[admin@ceph01 ~]$ sudo ceph config get mon ms_mon_service_mode                                            # secure crc
[admin@ceph01 ~]$ sudo ceph mon dump            # v2:10.10.30.51:3300 et v1:10.10.30.51:6789 ; auth_allowed_ciphers…
[admin@ceph01 ~]$ sudo ss -tn state established '( sport = :6789 )'                                      # clients en msgr1
[admin@ceph01 ~]$ lsblk -o NAME,TYPE,SIZE                                                                 # pas de « crypt »
[admin@ceph01 ~]$ sudo ceph health detail | grep -A3 AUTH_INSECURE
[admin@ceph01 ~]$ sudo ceph auth ls | grep -E '^(client|osd|mgr|mds|mon)'
```

Tableau à produire : identité → utilisateur → client et version. Dans le lab : `client.admin` (CLI des hôtes `_admin`, Tentacle 20.2.4 après E26), `client.sauvegarde` (CLI `rbd` de `cephcli01`, version du client choisi en E06), les identités de E13 (krbd et CephFS **noyau** de `cephcli01`, noyau 6.12 de Debian 13 ; outils de Debian 13 en 18.2 si c'est ton choix de E06), `client.rgw.*`, `client.crash.*`, `client.ceph-exporter.*` (démons gérés par cephadm). Les identités d'essai devenues inutiles (E13, E19…) sont supprimées (`ceph auth rm`).

*2. Transit* :

```
[admin@ceph01 ~]$ for o in ms_cluster_mode ms_service_mode ms_client_mode ms_mon_cluster_mode ms_mon_service_mode ms_mon_client_mode; do
                    sudo ceph config set global "$o" secure; done
[admin@ceph01 ~]$ for m in $(sudo ceph orch ps --daemon-type mon --format json | jq -r '.[].daemon_name'); do
                    sudo ceph orch daemon restart "$m"; sleep 30; sudo ceph quorum_status --format json | jq -r '.quorum_names|length'; done
[admin@ceph01 ~]$ for i in $(sudo ceph osd ls); do
                    until sudo ceph osd ok-to-stop "$i" >/dev/null 2>&1; do sleep 10; done
                    sudo ceph orch daemon restart "osd.$i"
                    sleep 20; until sudo ceph health | grep -q HEALTH_OK; do sleep 10; done; done
[admin@ceph01 ~]$ sudo ceph orch restart mds.cephfs ; sudo ceph mgr fail ; sudo ceph orch restart rgw.<SERVICE>
[admin@ceph01 ~]$ sudo ceph config show osd.0 ms_cluster_mode                                               # secure
admin@cephcli01:~$ sudo rbd device map rbd-test/disque01 --id <ID-E13> -o ms_mode=secure
admin@cephcli01:~$ sudo mount -t ceph <ID-E13>@.cephfs=/ /mnt/cephfs -o ms_mode=secure
```

`<SERVICE>` : nom de ton service RGW (`ceph orch ls rgw`). Réglé au niveau `global`, `ms_client_mode` s'applique aussi aux clients librados qui lisent la configuration centrale ; les clients noyau, eux, choisissent par `ms_mode`. Ce que ces réglages **ne** protègent **pas** : les connexions msgr1 (port 6789), qui n'ont pas de mode sécurisé. Décision du corrigé : pas de désactivation de msgr1 en v1 (risque de couper un client ancien), mais aucune connexion v1 tolérée en exploitation : vérification par `ss` intégrée à la recette, et désactivation (`ms_bind_msgr1 false` + monmap sans adresses v1) inscrite au ticket.

*3. Repos* : MR sur `plateforme/ceph` (`encrypted: true` dans les deux services d'OSD), pipeline, puis `outils/appliquer.sh specs/osd.yaml` depuis `adm01` (E23). Puis, pour chaque OSD de `ceph03`, **un par un** :

```
[admin@ceph01 ~]$ sudo ceph osd tree | grep -A4 ceph03
[admin@ceph01 ~]$ sudo ceph osd ok-to-stop 6 && sudo ceph orch osd rm 6 --replace --zap
[admin@ceph01 ~]$ sudo ceph orch osd rm status                       # vidage, puis retrait
[admin@ceph01 ~]$ sudo ceph -s                                       # l'OSD 6 revient (même identifiant), récupération, HEALTH_OK
[admin@ceph03 ~]$ lsblk -o NAME,TYPE,SIZE | grep -B1 crypt
[admin@ceph01 ~]$ sudo ceph config-key ls | grep -c dm-crypt          # noms des entrées, jamais « get »
```

`--replace` garde l'identifiant (l'OSD passe à `destroyed` dans la carte, sa place CRUSH est conservée) ; `--zap` efface le disque ; cephadm recrée l'OSD sur le disque libéré selon la spécification **actuelle**, donc chiffré. Avec 3 hôtes, le vidage de l'OSD reporte ses PG sur l'autre OSD de même classe de `ceph03` : vérifie qu'il a la place (`ceph osd df`). La clé LUKS de chaque OSD est dans le magasin clé-valeur des moniteurs (`dm-crypt/osd/<fsid de l'OSD>/luks`) : un disque ou un fichier `qcow2` copié ne se lit plus, mais une identité capable de lire ce magasin (toute identité `mon 'allow r'` avant 20.2.4) a les clés **et**, si elle peut joindre les OSD, les données ; d'où l'importance de E26.

*4. Clés cephx* : la question préalable décide de tout. Hypothèse du corrigé (à vérifier sur ton lab) : les bibliothèques Ceph de Debian 13 (18.2) et le client noyau 6.12 **ne savent pas** utiliser une clé `aes256k`. Conséquences : le type préféré **reste** `aes` (sinon toute identité créée ensuite, celles des équipes en E31 par exemple, serait inutilisable par `cephcli01`), la création de clés de l'ancien type reste permise, l'ancien type reste accepté.

```
[admin@ceph01 ~]$ sudo ceph --format=json mon dump | jq '.auth_allowed_ciphers, .auth_preferred_cipher, .auth_service_cipher'
[admin@ceph01 ~]$ sudo ceph health detail | grep -E 'AUTH_INSECURE_(SERVICE_KEY_TYPE|SERVICE_TICKETS)'   # cephadm a renouvelé les démons ?
[admin@ceph01 ~]$ sudo ceph mon set auth_service_cipher aes256k                                         # tickets de service (étape 5 de la doc)
```

Si un démon reste signalé, la procédure officielle (arrêt, `ceph auth rotate --key-type=aes256k <démon>`, import du trousseau, redémarrage) s'applique ; cephadm propose aussi `ceph orch daemon rotate-key <démon>` (à confirmer pour ce cas). Les clés de rotation des services expirent seules en quelques heures : inutile d'utiliser `wipe-rotating-service-keys`.

Renouvellement de `client.admin` (sur `ceph01`, `ceph-common` en 20.2.4) :

```
[root@ceph01 ~]# umask 077
[root@ceph01 ~]# ceph auth get-or-create client.admin-backup mon 'allow *' osd 'allow *' mgr 'allow *' mds 'allow *' > /root/admin-backup.keyring
[root@ceph01 ~]# ceph -n client.admin-backup -k /root/admin-backup.keyring -s                    # fonctionne ?
[root@ceph01 ~]# ceph auth rotate --key-type=aes256k client.admin > /root/client.admin.keyring.nouveau
[root@ceph01 ~]# ceph-authtool /etc/ceph/ceph.client.admin.keyring --import-keyring /root/client.admin.keyring.nouveau
[root@ceph01 ~]# ceph -s                                                                         # la nouvelle clé fonctionne
[root@ceph01 ~]# ceph -n client.admin-backup -k /root/admin-backup.keyring auth rm client.admin-backup   # ou avec admin
[root@ceph01 ~]# shred -u /root/admin-backup.keyring /root/client.admin.keyring.nouveau
```

cephadm redistribue ensuite la clé d'administration sur les autres hôtes `_admin` (`ceph02`) ; vérifie `ceph -s` sur `ceph02`. Clés clientes : `client.sauvegarde` et les identités de E13 servent des clients de Debian 13 → **non renouvelées** en `aes256k` ; sourdines temporaires et ticket :

```
[admin@ceph01 ~]$ sudo ceph health mute AUTH_INSECURE_CLIENT_KEY_TYPE 8w
[admin@ceph01 ~]$ sudo ceph health mute AUTH_INSECURE_KEYS_CREATABLE 8w
[admin@ceph01 ~]$ sudo ceph health mute AUTH_INSECURE_KEYS_ALLOWED 8w
```

Ticket SEC daté (8 semaines) : « clients de Debian 13 et noyau : vérifier la prise en charge de `aes256k` (paquets, noyau), sinon client conteneurisé en 20.2.x pour la CLI ; renouveler alors `client.sauvegarde`, les identités d'équipes et de E13 ; interdire ensuite l'ancien type (`mon_auth_allow_insecure_key false`, `ceph mon set auth_allowed_ciphers aes256k`) ». Si ton lab montre que tes clients **savent** utiliser `aes256k`, va jusqu'au bout de la procédure : aucune sourdine.

*5. Clé SSH de l'orchestrateur*, sans fenêtre d'aveuglement (le compte est `cephadm`, amorçage `--ssh-user cephadm`, E03) :

```
[root@ceph01 ~]# ceph cephadm get-pub-key                                      # ancienne clé publique (pour la transition)
admin@adm01:~$ ssh-keygen -t ed25519 -N '' -C ceph-par1-orchestrateur-2026-10 -f /tmp/orch-nouvelle
admin@adm01:~/src/ansible$ # MR 1 : ceph_noeud_cle_orchestrateur = ancienne + nouvelle (une par ligne), pipeline, rôle ceph_noeud
admin@adm01:~$ scp /tmp/orch-nouvelle /tmp/orch-nouvelle.pub ceph01:/tmp/ && shred -u /tmp/orch-nouvelle
[root@ceph01 ~]# ceph cephadm set-priv-key -i /tmp/orch-nouvelle
[root@ceph01 ~]# ceph cephadm set-pub-key -i /tmp/orch-nouvelle.pub
[root@ceph01 ~]# for h in ceph01 ceph02 ceph03; do ceph cephadm check-host "$h"; done
[root@ceph01 ~]# shred -u /tmp/orch-nouvelle /tmp/orch-nouvelle.pub
admin@adm01:~/src/ansible$ # MR 2 : ceph_noeud_cle_orchestrateur = nouvelle seule (liste exclusive), pipeline
[admin@ceph02 ~]$ sudo cat /var/lib/cephadm/.ssh/authorized_keys          # une seule ligne : la nouvelle clé
```

La clé privée n'existe plus qu'en un endroit : le magasin des moniteurs (pas de copie en Vault : l'orchestrateur en génère une nouvelle si le cluster est reconstruit ; choix écrit au registre). Rappel du rôle `ceph_noeud` : le compte `cephadm` a `sudo` sans mot de passe sur chaque nœud, donc qui lit cette clé est `root` partout — c'est exactement ce que CVE-2026-50152 rendait possible avec `mon 'allow r'`.

*6. Trace* : registre des secrets (entrées « clé `client.admin` (aes256k, renouvelée le …, hôtes `_admin`) », « clés LUKS des OSD : magasin clé-valeur des moniteurs, jamais exportées », « clé SSH de l'orchestrateur : magasin des moniteurs, renouvelée le …, prochaine le … »), ticket listant : OSD de `ceph01`/`ceph02` (mini-projet), clés clientes à l'ancien type (date), msgr1.

**Explications**

msgr2 négocie pour chaque connexion un mode **crc** (intégrité contre la corruption accidentelle, pas contre un attaquant) ou **secure** (AES-GCM après l'authentification cephx : confidentialité et intégrité). Chaque côté annonce ses modes par ordre de préférence ; « `secure` » seul côté service **impose** le chiffrement. Le chiffrement au repos par cephadm (LUKS via `ceph-volume`) chiffre le périphérique sous BlueStore ; la clé est dans le cluster lui-même, ce qui protège contre le vol de support mais pas contre un administrateur du cluster. Enfin cephx authentifie par secret partagé et tickets à durée limitée ; la faille de 2025 portait sur la construction cryptographique des tickets, d'où un nouveau type de clé plutôt qu'un simple correctif, et une migration à piloter client par client.

**Alternatives**
- Chiffrement côté client (`rbd encryption format luks2`) : la clé reste chez le client, Ceph ne voit que du chiffré ; idéal pour des données de santé, mais gestion des clés à la charge de chaque application et pas de clones entre formats.
- Chiffrement au niveau de l'hyperviseur (disques des VMs `ssd-lab` chiffrés sur `pve01`) : protège le support physique du lab, pas un `qcow2` copié par un administrateur de `pve01`.
- Désactiver msgr1 immédiatement : plus strict, au prix d'une vérification exhaustive des clients.
- Clés cephx gérées par un coffre (Vault, M25) et distribuées au démarrage : renouvellement plus fréquent possible.

**Pièges classiques**
- Mettre `ms_service_mode` à `secure` sans redémarrer les démons : la configuration centrale ment, `config show` dit la vérité.
- Redéployer plusieurs OSD en même temps « pour aller vite » : PG sous `min_size`, écritures bloquées.
- Oublier `--replace` : nouvel identifiant, rééquilibrage de toute la carte.
- Lancer `ceph config-key get` pour « voir » une clé LUKS : elle s'affiche en clair dans le terminal et l'historique.
- Faire de `aes256k` le type préféré alors que des clients ne le comprennent pas : chaque nouvelle identité est inutilisable par eux.
- Interdire l'ancien type avant d'avoir renouvelé **toutes** les clés, ou renouveler `client.admin` sans identité de secours testée.
- Générer la nouvelle clé SSH par `ceph cephadm generate-key` : l'orchestrateur perd l'accès aux nœuds jusqu'à la distribution de la clé publique.
- Poser la nouvelle clé pour `root` (tutoriels écrits pour `--ssh-user root`) : ici l'orchestrateur se connecte avec le compte `cephadm`.

**En production chez MédiSphère**
Chiffrement côté client pour les volumes de données de santé les plus sensibles, clés dans Vault (M25) ; renouvellement annuel planifié des clés cephx et de la clé SSH de l'orchestrateur ; recette de sécurité qui vérifie l'absence de connexion msgr1 et l'absence de toute identité `allow *` hors administration ; revue d'exposition à chaque avis de sécurité Ceph.

---

### M08-E28 — Mesurer les performances

**Solution**

Fichiers : profils [`bench/`](fichiers/M08-E28/ceph/bench/) (`plateforme/ceph`) et modèle de [`performances.md`](fichiers/M08-E28/medisphere/docs/stockage/performances.md) (sans aucun chiffre : ce sont **tes** mesures qui comptent).

```
[admin@ceph02 ~]$ iperf3 -s                                                   # serveur, à arrêter ensuite
[admin@ceph01 ~]$ iperf3 -c 10.10.31.52 -t 30 ; iperf3 -c 10.10.31.52 -t 30 -P 4 ; iperf3 -c 10.10.30.52 -t 30 -P 4
[admin@ceph01 ~]$ ping -c 3 -M do -s 8972 10.10.31.52
[admin@ceph01 ~]$ sudo ceph tell osd.0 bench ; sudo ceph tell osd.2 bench         # un ssd, un hdd (ceph osd tree)
[admin@ceph01 ~]$ sudo ceph config show osd.0 osd_mclock_max_capacity_iops_ssd
[admin@ceph01 ~]$ sudo ceph osd pool create bench --autoscale-mode on ; sudo ceph osd pool set bench crush_rule ssd-baie
[admin@ceph01 ~]$ sudo ceph osd pool application enable bench rbd ; sudo rbd pool init bench
[admin@ceph01 ~]$ sudo rados bench -p bench 60 write -b 4M -t 16 --no-cleanup
[admin@ceph01 ~]$ sudo rados bench -p bench 60 seq -t 16 ; sudo rados bench -p bench 60 rand -t 16
[admin@ceph01 ~]$ sudo rados -p bench cleanup
[admin@ceph01 ~]$ sudo rados bench -p bench 60 write -b 4K -t 16 ; sudo rados -p bench cleanup
[admin@ceph01 ~]$ sudo rbd create --size 10G bench/fio01
[admin@ceph01 ~]$ sudo rbd bench --io-type write --io-size 4K --io-threads 16 --io-total 2G --io-pattern rand bench/fio01
[admin@ceph01 ~]$ sudo rbd bench --io-type write --io-size 4M --io-threads 4 --io-total 4G --io-pattern seq bench/fio01
admin@cephcli01:~$ sudo FIO_DEV=/dev/rbd0 fio --output-format=json --output=bdd.json ~/src/ceph/bench/base-de-donnees.fio
```

Identité de mesure jetable `client.bench` (`profile rbd pool=bench`) pour `cephcli01`, supprimée au nettoyage. Jumbo/1500, sur les **trois** nœuds en même temps (commande Ansible ad hoc, non persistante) :

```
admin@adm01:~/src/ansible$ uv run ansible 'ceph0[1-3]' -b -m ansible.builtin.command -a 'ip link set ens19 mtu 1500'
… iperf3 cluster, rados bench write 4M …
admin@adm01:~/src/ansible$ uv run ansible 'ceph0[1-3]' -b -m ansible.builtin.command -a 'ip link set ens19 mtu 9000'
[admin@ceph01 ~]$ ping -c 3 -M do -s 8972 10.10.31.53
```

Nettoyage :

```
[admin@ceph01 ~]$ sudo rbd rm bench/fio01
[admin@ceph01 ~]$ sudo ceph config set mon mon_allow_pool_delete true
[admin@ceph01 ~]$ sudo ceph osd pool rm bench bench --yes-i-really-really-mean-it
[admin@ceph01 ~]$ sudo ceph config set mon mon_allow_pool_delete false
[admin@ceph01 ~]$ sudo ceph auth rm client.bench
```

(`ceph config rm mon mon_allow_pool_delete` revient aussi au défaut `false`.)

**Explications**

Mesurer couche par couche localise la limite : si `iperf3` donne 10 Gbit/s et `rados bench` 300 Mio/s en écriture, ce n'est pas le réseau ; si `ceph tell osd.N bench` est déjà bas, c'est le disque (ici, le SSD unique de `pve01` partagé par 6 OSD et toutes les autres VMs). En écriture répliquée, chaque octet écrit par un client est écrit 3 fois et traverse 2 fois le réseau de cluster : le débit d'écriture d'un client est au mieux le tiers de ce que les disques encaissent ensemble. La latence d'une écriture synchrone en profondeur 1 est la borne basse de ce que verra une base de données : réseau client → OSD primaire, réplication vers deux secondaires, écriture des trois, acquittements. Les jumbo frames réduisent le nombre de paquets (donc le CPU par octet) ; sur un pont Linux en mémoire, l'effet sur le débit est faible, sur le CPU mesurable.

**Alternatives**
- `fio` avec le moteur `rbd` (librbd, sans krbd) : mesure le chemin d'un client QEMU/OpenStack ; krbd mesure celui d'un client noyau (Kubernetes, `cephcli01`).
- `cbt` (Ceph Benchmarking Tool) : orchestre des campagnes reproductibles ; pertinent sur un vrai parc.
- `ceph osd perf` et `dump_historic_ops` pendant la mesure : où passent les millisecondes dans un OSD.

**Pièges classiques**
- Mesurer avec le cache de page du client (`direct=0`) : on mesure la mémoire de `cephcli01`.
- Lire les objets de `rados bench` en lecture après un `write` sans `--no-cleanup` : rien à lire, chiffres absurdes.
- Mesurer pendant une récupération, une sauvegarde ou un scrub (`ceph -s`).
- Changer le MTU d'un seul nœud : pertes de gros paquets, OSD qui « flappent » (panne E42).
- Oublier de supprimer le pool `bench` ou de remettre l'interdiction de suppression.
- Annoncer à Julien des chiffres de lab comme des promesses de production.

**En production chez MédiSphère**
Campagne de mesure à la réception du matériel (référence), puis à chaque changement majeur, avec les mêmes profils versionnés ; mesures de latence p99 continues côté client (M21) plutôt que des campagnes ponctuelles ; capacité mClock vérifiée par OSD à la mise en service.

---

### M08-E29 — Régler la mémoire, la récupération et mClock

**Solution**

Fichiers : sections 6 et 7 du [modèle de `performances.md`](fichiers/M08-E28/medisphere/docs/stockage/performances.md), [fiche réflexe récupération](fichiers/M08-E29/medisphere/docs/stockage/runbooks/fiche-recuperation.md).

*1-2. Mémoire* :

```
[admin@ceph01 ~]$ sudo ceph orch ps --hostname ceph02          # MEM USE / MEM LIM par démon
[admin@ceph02 ~]$ free -m
[admin@ceph01 ~]$ sudo ceph config get osd osd_memory_target_autotune
[admin@ceph01 ~]$ sudo ceph config dump | grep -E 'osd_memory_target|autotune'
osd       host:ceph02   basic  osd_memory_target  …                    # écrit par cephadm (réglage automatique)
[admin@ceph01 ~]$ sudo ceph config show osd.3 osd_memory_target
[admin@ceph01 ~]$ sudo ceph tell osd.3 dump_mempools | jq '.mempool.total'
[admin@ceph01 ~]$ sudo ceph config help osd_memory_target         # min., défaut (4 Gio), description
```

Budget (détail dans le modèle) : système 0,5 + MON 0,7 + MGR 0,5 + MDS 0,6 (après `ceph config set mds mds_cache_memory_limit 536870912` : le défaut de 4 Gio est fait pour des serveurs dédiés) + RGW ou ingress 0,3 + 3 OSD × 1,2 ≈ 6,2 Gio : à la limite. Décision : valeur fixe, au niveau `osd`, réglage automatique coupé, valeurs par hôte retirées :

```
[admin@ceph01 ~]$ sudo ceph config set osd osd_memory_target_autotune false
[admin@ceph01 ~]$ for h in ceph01 ceph02 ceph03; do sudo ceph config rm osd/host:$h osd_memory_target; done
[admin@ceph01 ~]$ sudo ceph config set osd osd_memory_target 1073741824
[admin@ceph01 ~]$ for i in $(sudo ceph osd ls); do echo "osd.$i $(sudo ceph config show osd.$i osd_memory_target)"; done
```

L'option se relit à chaud (le cache de BlueStore se redimensionne). Le minimum de l'option (`osd_memory_target_min`) est inférieur à 1 Gio : la valeur est acceptée, mais elle est **basse** pour BlueStore ; c'est un compromis de lab, écrit comme tel.

*3. mClock* :

```
[admin@ceph01 ~]$ sudo ceph config show osd.0 osd_mclock_profile                          # balanced
[admin@ceph01 ~]$ sudo ceph config dump | grep osd_mclock_max_capacity_iops
[admin@ceph01 ~]$ sudo ceph config show osd.0 osd_max_backfills ; sudo ceph config show osd.0 osd_recovery_max_active
[admin@ceph01 ~]$ sudo ceph config set osd osd_max_backfills 8 ; sudo ceph config show osd.0 osd_max_backfills   # inchangé
[admin@ceph01 ~]$ sudo ceph config rm osd osd_max_backfills
```

Sans `osd_mclock_override_recovery_settings`, la valeur posée est ignorée (avertissement dans le journal de l'OSD) : mClock fixe ces options selon le profil. Les capacités mesurées au démarrage en VM sont souvent aberrantes (cache de l'hôte) ; Tentacle signale les valeurs hors des seuils bas et hauts (`osd_mclock_iops_capacity_*threshold_*`). Si c'est le cas, fixe une capacité réaliste par classe (`ceph config set osd/class:ssd osd_mclock_max_capacity_iops_ssd <valeur de E28>`), et note-le.

*4. Récupération mesurée* :

```
admin@cephcli01:~$ sudo FIO_DEV=/dev/rbd0 fio --output-format=json --status-interval=10 --output=recup-balanced.json base-de-donnees.fio &
[admin@ceph01 ~]$ sudo ceph orch daemon stop osd.4 ; sudo ceph osd out 4
[admin@ceph01 ~]$ watch -n 5 sudo ceph -s                     # débit de récupération, PG restants ; noter début et fin
[admin@ceph01 ~]$ sudo ceph osd in 4 ; sudo ceph orch daemon start osd.4   # puis attendre HEALTH_OK
[admin@ceph01 ~]$ sudo ceph config set osd osd_mclock_profile high_client_ops      # essai suivant, idem
```

Attendu : `high_recovery_ops` raccourcit nettement la récupération et dégrade le p99 client ; `high_client_ops` l'inverse ; `balanced` entre les deux. Profil nominal retenu par le corrigé : `balanced` (un cluster de 3 nœuds sans marge de redondance pendant une récupération ne doit pas la laisser traîner).

*5. Maintenance* : `set noout` (global : toute panne ailleurs pendant la maintenance ne sera pas traitée), `add-noout osd.N` (un OSD), `set-group noout ceph03` (un hôte), `orch host maintenance enter` (arrête les démons de l'hôte, pose `noout` pour lui, vérifie d'abord que c'est sans danger, et se défait proprement par `exit`) : c'est le bon outil pour redémarrer `ceph03`.

*6. Retour au nominal* :

```
[admin@ceph01 ~]$ sudo ceph config set osd osd_mclock_profile balanced
[admin@ceph01 ~]$ sudo ceph config dump | grep -E '^osd\.[0-9]+ '            # aucune ligne de réglage par OSD
[admin@ceph01 ~]$ sudo ceph osd dump | grep flags ; sudo ceph orch host ls ; sudo ceph -s
```

**Explications**

Un OSD BlueStore gère lui-même son cache (métadonnées RocksDB, onodes, données) pour approcher `osd_memory_target` ; ce n'est pas une limite dure : la mémoire réelle dépasse la cible de 10 à 30 % selon la charge et la récupération. cephadm, pour les hôtes qu'il gère, peut calculer cette cible (ratio de la mémoire de l'hôte moins les autres démons) et l'écrire **par hôte** dans la configuration centrale. mClock est un ordonnanceur à réservation, poids et limite : chaque classe de travail (client, récupération, tâches de fond) reçoit une part de la **capacité mesurée** de l'OSD ; les profils sont des jeux de parts. D'où l'importance d'une capacité juste, et le verrouillage des anciennes options (qui court-circuiteraient l'ordonnanceur).

**Alternatives**
- Garder le réglage automatique de cephadm avec un ratio ajusté (`mgr/cephadm/autotune_memory_target_ratio`) : s'adapte si la mémoire des VMs change, mais la valeur effective n'est plus lisible d'un coup d'œil et dépend des autres démons.
- Profil `custom` de mClock : réglage fin des réservations ; à réserver aux équipes qui mesurent en continu.
- Ordonnanceur `wpq` : l'ancien ordonnanceur, encore recommandé dans certains cas de récupération massive en codes d'effacement sur HDD.

**Pièges classiques**
- Poser `osd_memory_target` à la main **et** laisser le réglage automatique : la valeur par hôte, plus spécifique, gagne.
- Croire que `osd_memory_target` limite la mémoire : OOM quand même si le budget est faux.
- Oublier le MDS (4 Gio de cache par défaut) dans le budget.
- Changer `osd_max_backfills` et croire que ça marche (mClock l'ignore).
- Laisser `high_recovery_ops` après la récupération, ou un réglage par OSD posé pendant l'essai.
- `ceph osd set noout` global pour une maintenance d'hôte.

**En production chez MédiSphère**
Nœuds de stockage dimensionnés à 4-8 Gio par OSD (cible BlueStore par défaut 4 Gio) et dédiés (pas de MDS ni de RGW sur les nœuds d'OSD au-delà de quelques nœuds) ; capacité mClock mesurée à la réception du matériel et figée ; alerte sur la mémoire des nœuds (M21) ; fiche réflexe intégrée à l'astreinte.

---

### M08-E30 — ADR : le stockage objet de MédiDoc

**Solution**

Modèle : [`ADR-0080-stockage-objet-medidoc.md`](fichiers/M08-E30/medisphere/docs/stockage/adr/ADR-0080-stockage-objet-medidoc.md). Décision : **RGW de `ceph-par1`** pour les documents de MédiDoc ; **`s3-01` reste le stockage de la plateforme** (état OpenTofu, artefacts), sans donnée métier. Les arguments décisifs : redondance réelle (3 copies sur 3 hôtes contre une VM unique), chiffrement en transit et au repos déjà en place (E27), cloisonnement par comptes (E12), et surtout **l'indépendance** : une plateforme qui stocke ses propres moyens de reconstruction au même endroit que la donnée métier ne peut plus se réparer quand ce stockage sature ou tombe.

**Explications**

Une bonne ADR ne compare pas des produits « dans l'absolu » mais **dans ce contexte** : avec ce que l'équipe a construit et vérifié. C'est pourquoi chaque note s'appuie sur un exercice. Le score pondéré sert à rendre les compromis visibles ; il ne remplace pas la décision (une option à 112 points qui ferait sauter un critère éliminatoire serait écartée quand même).

**Alternatives** (décisions également défendables)
- RGW dédié à MédiDoc (O3) : cloisonnement maximal, coût d'exploitation double ; à reconsidérer si MédiDoc impose des contraintes propres (rétention légale stricte, chiffrement par un KMS dédié).
- SeaweedFS rendu redondant (plusieurs volumes, réplication) : possible, mais c'est construire un second stockage distribué à côté de Ceph.

**Pièges classiques**
- Comparer sur des fonctionnalités « possibles » et non mises en œuvre (verrouillage d'objets, chiffrement côté serveur).
- Oublier le critère d'indépendance (dépendances croisées entre la plateforme et ce qu'elle héberge).
- Ne pas dire ce que devient l'autre solution, ni qui la garde pour quoi.
- Taire les conséquences négatives (pas de sauvegarde hors site des objets en v1).

**En production chez MédiSphère**
Revue de l'ADR à la mise en place du PRA (F5) et de la sauvegarde des objets ; avis du DPO sur la conservation et l'effacement ; indicateurs de capacité et de latence S3 dans les SLO de MédiDoc (M21).

**Grille d'auto-évaluation**

| Critère | Attendu |
|---|---|
| Gabarit | MADR, statut, date, décideurs, ticket ; deux pages au plus |
| Contexte | nature des données, volumétrie, exigences de Sophie et de Julien |
| Critères | au moins 8, pondérés, dont l'indépendance et la sauvegarde |
| Options | au moins 3, chaque note justifiée par un fait vérifié |
| Décision | tranchée, avec le devenir de l'autre solution |
| Conséquences | négatives écrites, actions rattachées à un module ou datées |

---

### M08-E31 — Cloisonner le stockage par équipe

**Solution** (une solution possible ; `LIBRE` : d'autres choix sont valables s'ils respectent les contraintes)

Fichiers (`plateforme/ceph`) : [`allocations.yaml`](fichiers/M08-E31/ceph/allocations.yaml), outil [`outils/ceph-allocations.sh`](fichiers/M08-E31/ceph/outils/ceph-allocations.sh) (s'appuie sur `outils/lib.sh` de E23), pool `rbd-equipes` ajouté à `config/cluster.yaml` (même modèle que l'[extrait du mini-projet](fichiers/M08-E46/ceph/config-cluster-pools-extrait.yaml)) ; registre : [`allocations.md`](fichiers/M08-E31/medisphere/docs/stockage/allocations.md).

*Ce que Ceph applique réellement* (le cœur de l'exercice) :

| Besoin | Mécanisme Ceph | Plafond natif ? |
|---|---|---|
| Bloc isolé par équipe | espace de noms RBD dans un pool partagé + `profile rbd pool=… namespace=…` | **non** : un quota ne se pose que sur un **pool** (octets, objets) |
| Fichier isolé par équipe | groupe de sous-volumes CephFS + capacité MDS `path=/volumes/<équipe>` | **oui** : la taille du groupe (et de chaque sous-volume) est un quota CephFS |
| Données des fichiers isolées | sous-volumes `--namespace-isolated` + capacité OSD limitée à leurs espaces de noms RADOS | — |
| Objet | compte RGW | **oui** : quota de compte et de compartiment |

Le plafond bloc est donc compensé : (1) un quota sur `rbd-equipes` égal à la somme des plafonds (aucune équipe ne peut faire tomber les autres usages du cluster), (2) un contrôle nocturne `ceph-allocations verifier` qui compare la taille **provisionnée** de chaque espace de noms (`rbd du`) au plafond et alerte (pas de blocage : l'équipe a déjà ses images), (3) la règle « provisionné ≤ plafond » écrite dans la politique. Limite assumée : à l'intérieur de `rbd-equipes`, une équipe qui remplit le quota du pool bloque **les autres équipes du pool** ; c'est la raison d'un quota égal à la somme des plafonds et du contrôle. L'alternative (un pool par équipe, quota natif) coûte des PG et une règle de plus par équipe : retenue au-delà d'une dizaine d'équipes ou pour une équipe qui exige un plafond dur.

*Mise en œuvre* : le pool `rbd-equipes` suit le chemin des pools de `plateforme/ceph` (entrée dans `config/cluster.yaml` avec règle `ssd-baie`, application `rbd` et quota ; création par `outils/pool-repliquee.sh rbd-equipes rbd` sur le nœud `_admin` (E05) ; réglage par `outils/config-cluster.sh --appliquer`). L'outil `ceph-allocations.sh`, lancé sur `adm01` comme les autres outils du projet, lit `allocations.yaml` et, pour chaque équipe, crée l'espace de noms, le groupe de sous-volumes plafonné, les sous-volumes isolés, puis **calcule** les droits de l'identité :

```
mon 'profile rbd, allow r fsname=cephfs'
osd 'profile rbd pool=rbd-equipes namespace=mediagenda, allow rw pool=cephfs.cephfs.data namespace=fsvolumens_exports'
mds 'allow rw fsname=cephfs path=/volumes/mediagenda'
```

(La capacité moniteur combinée est à confirmer sur ton lab : si `ceph auth caps` la refuse, `profile rbd` seul suffit au bloc et `allow r fsname=cephfs` est nécessaire au montage CephFS.) `ceph auth caps` remplace **tous** les droits : l'outil les réécrit en entier depuis la description, jamais par ajout. Il ne supprime rien (une équipe retirée du fichier est signalée par `verifier`) et ne crée pas d'identifiants S3 (secrets : procédure du registre).

```
[root@ceph01 ~]# ./pool-repliquee.sh --simuler rbd-equipes rbd                # sur le nœud _admin, comme en E05 ; puis sans --simuler (fiche de changement)
admin@adm01:~/src/ceph$ outils/config-cluster.sh --verifier ; outils/config-cluster.sh --appliquer
admin@adm01:~/src/ceph$ outils/ceph-allocations.sh appliquer --simuler        # à blanc, sortie collée dans la MR
admin@adm01:~/src/ceph$ outils/ceph-allocations.sh appliquer                  # après fusion ; « oui »
admin@adm01:~/src/ceph$ outils/ceph-allocations.sh appliquer                  # second passage : droits OSD des sous-volumes créés
admin@adm01:~/src/ceph$ outils/ceph-allocations.sh verifier
admin@adm01:~$ ssh ceph01 'sudo ceph auth get client.mediagenda' | ssh cephcli01 'sudo install -m 600 /dev/stdin /etc/ceph/ceph.client.mediagenda.keyring'
```

(La même sortie va dans Vault pour l'équipe ; elle ne transite que par des tubes.) Pourquoi `pool-repliquee.sh` puis l'outil d'allocation, et pas un seul outil ? Parce que `plateforme/ceph` a décidé en E23 que la création d'un pool reste un geste humain avec fiche de changement (elle déplace des données et consomme des PG), alors qu'ajouter une équipe dans un pool existant ne déplace rien : c'est l'affaire d'une MR. Le contrôle nocturne : le job de dérive du pipeline de `plateforme/ceph` (E23, identité `client.ci-lecture`, en lecture seule) lance aussi `outils/ceph-allocations.sh verifier` ; un écart rend le pipeline rouge et prévient l'équipe. `rbd du` et la lecture des droits demandent seulement `mon 'allow r'` et la lecture des pools : à vérifier avec `client.ci-lecture` (sinon, timer sur `adm01`).

*Désignation pour la sauvegarde* : l'équipe pose la métadonnée `medisphere.sauvegarde=oui` sur ses images ; `wb-backup-ceph` découvre ces images dans tous les espaces de noms de `rbd-equipes` (E25). `client.sauvegarde` a `profile rbd pool=rbd-equipes` **sans** espace de noms (elle doit voir toutes les équipes) : c'est l'identité la plus puissante sur les données des équipes, gardée sur un seul hôte.

*Matrice d'isolement* (extrait, depuis `cephcli01`) :

| Identité → ressource | lister | lire | écrire | supprimer |
|---|---|---|---|---|
| mediagenda → `rbd-equipes/mediagenda` | ✓ | ✓ | ✓ | ✓ |
| mediagenda → `rbd-equipes/medidoc` | refus (`EPERM`) | refus | refus | refus |
| mediagenda → `rbd-equipes` (défaut) | refus | — | refus (`rbd create`) | — |
| mediagenda → `rbd-test` | refus | refus | refus | refus |
| mediagenda → `/volumes/medidoc` (montage) | refus | refus | refus | refus |
| mediagenda → objets RADOS de `fsvolumens_archives` (`rados -p cephfs.cephfs.data --namespace …`) | refus | refus | refus | refus |
| mediagenda → `ceph osd pool create` / `ceph auth caps` | refus | | | |

La ligne « objets RADOS » est celle qu'on oublie : sans `--namespace-isolated` et avec la capacité classique `allow rw tag cephfs data=cephfs`, une équipe pourrait lire directement les objets des fichiers d'une autre, sans passer par le MDS.

**Explications**

Ceph a trois niveaux d'isolement : le **pool** (le plus fort : règles, quotas, PG propres), l'**espace de noms RADOS** (un préfixe logique dans un pool, sur lequel portent les capacités OSD ; RBD l'utilise pour ses espaces de noms, CephFS pour les sous-volumes isolés), et le **chemin** (capacités MDS, qui ne contrôlent que l'arborescence vue par le MDS, pas l'accès direct aux objets). Les quotas, eux, existent par pool, par répertoire CephFS et par compte/compartiment RGW, pas par espace de noms. Toute la conception consiste à combiner ces niveaux et à compenser l'absence de quota par espace de noms.

**Alternatives**
- Un pool RBD par équipe : quota dur natif, règles différentes possibles (classe, réplication) ; coût en PG et en complexité.
- Délégation via OpenStack (Cinder, projets et quotas) ou Kubernetes (StorageClass, ResourceQuota) : la manière « produit » de faire du libre-service ; arrive aux modules 10 et 16, et c'est souvent là que les équipes consommeront le stockage.
- `ceph fs subvolume authorize` pour générer l'identité CephFS : pratique pour un sous-volume, mais crée une identité par sous-volume ; moins adapté à une identité d'équipe unique.

**Pièges classiques**
- Croire qu'un espace de noms RBD a un quota.
- Capacité MDS par chemin sans isolement des objets RADOS (`--namespace-isolated` oublié).
- `ceph auth caps` partiel qui efface les droits d'un autre service (il remplace tout).
- Tester seulement les cas positifs (« mediagenda voit ses images ») et jamais les refus.
- Quota de pool partagé trop large : une équipe remplit le pool, les autres équipes sont bloquées.
- Clé d'équipe envoyée par messagerie, ou laissée lisible sur `cephcli01` (mode 644).

**En production chez MédiSphère**
Libre-service par un catalogue (M28) qui écrit dans `allocations.yaml` par MR ; alertes de plafond dans la supervision (M21) ; identités d'équipe renouvelées annuellement ; volumes de bases de données plutôt via Kubernetes (M16, CloudNativePG M27) que par RBD direct.

---

### M08-E32 — Questions de production : stockage distribué

1. **Un nœud tombe** : chaque PG a perdu une copie sur trois ; lectures et écritures continuent (2 copies ≥ `min_size` 2), PG `active+undersized+degraded`. **Pas de reconstruction** : la règle exige 3 hôtes distincts et il n'en reste que 2 ; le cluster attend le retour du nœud (après 10 minutes, les OSD sont marqués `out`, sans effet sur le placement faute d'hôte). **Un second nœud** une heure plus tard : 1 copie par PG, sous `min_size` → PG inactifs, **toutes les E/S bloquées** (pas de perte : la copie restante est intacte) ; et le quorum des MON est perdu (1 sur 3) : le cluster se fige complètement. `min_size=1` aurait laissé écrire sur une seule copie : la moindre panne de cet OSD aurait alors perdu des écritures acquittées. C'est le compromis disponibilité/durabilité, et la raison du défaut 2.
2. **c)** au bout de `mon_osd_down_out_interval` (600 s par défaut), le MON marque l'OSD `out` et ses PG sont réaffectés : la reconstruction a commencé il y a 5 minutes **si** un emplacement existe. a) est faux (c'est automatique, sauf `noout`) ; b) faux (10 minutes, pas immédiatement) ; d) faux : Ceph le marque `out` quand même. Avec 3 baies d'un nœud chacune et une règle de taille 3 (domaine `rack`), la reconstruction se fait **dans le même nœud** (sur l'autre OSD de même classe), ce qui charge cet OSD.
3. `MAX AVAIL` = espace que le pool peut encore recevoir **avant que le premier OSD concerné atteigne `full_ratio`**, compte tenu de la répartition CRUSH et de la réplication : 384/3 = 128 Gio est un plafond théorique (OSD vides, répartition parfaite) ; on retranche l'occupation des autres pools de la même classe, la marge jusqu'au ratio, et le déséquilibre. Il suffit d'un OSD plus rempli pour que tout le pool soit limité par lui (les données sont réparties uniformément ; quand **un** OSD est plein, les écritures qui y vont échouent). Seuils (valeurs par défaut de Ceph, ramenées à 0,75 / 0,85 / 0,95 en E20) : `nearfull` (alerte), `backfillfull` (la récupération ne remplit plus cet OSD), `full` ( **toutes** les écritures du cluster vers les PG concernés sont refusées ; en pratique le cluster passe en lecture seule). D'où le rééquilibreur (`balancer`, actif par défaut en `upmap`).
4. Avec **plus** d'hôtes que la taille de réplication, perdre un nœud reconstruit ses données sur les survivants : il faut que la capacité restante absorbe la part du nœud perdu (avec 4 nœuds égaux, ~75 % × ratio ; avec 3 nœuds et une taille 2, 66 %). Avec 3 hôtes et `size=3`, il n'y a nulle part où mettre la troisième copie : aucune reconstruction, la capacité n'est pas le problème de la perte d'un **nœud**, mais celle d'un **OSD** (report sur l'autre OSD de même classe du même nœud : d'où 40 % dans la politique, avec `backfillfull` à 0,85).
5. Mgr actif perdu : tableau de bord, orchestrateur (cephadm), métriques, autoscaler, `balancer`, `ceph -s` partiel (statistiques de PG) s'arrêtent ; **les E/S des clients continuent** (elles passent par MON et OSD). Bascule vers le mgr en attente en quelques secondes (`mon_mgr_beacon_grace`, 30 s par défaut). Sans mgr en attente : pas de bascule, `HEALTH_WARN` (`MGR_DOWN`), le cluster sert toujours les données mais sans supervision ni orchestration, et les statistiques de PG se figent.
6. **c)** l'orchestrateur ne poursuit pas sur un démon en échec : la mise à jour se met en pause avec un message (et un contrôle de santé), en attendant l'intervention. a) faux : il n'y a pas de retour arrière automatique ; b) faux : continuer en laissant des OSD arrêtés ferait tomber des PG sous `min_size` ; d) faux : cephadm ne détruit jamais un OSD de lui-même. Démarche : `ceph orch upgrade status`, `ceph orch ps --refresh` (état du démon), journal du démon sur l'hôte (`cephadm logs --name osd.N`), cause (image, disque, mémoire), correction, `ceph orch upgrade resume`.
7. Les MON écrivent leur base (RocksDB) et la carte avec les fonctionnalités de la nouvelle version ; une fois toutes les MON passées, des fonctionnalités de la carte des moniteurs peuvent être activées, qu'une version plus ancienne ne sait plus lire ; pour une version **majeure**, `require_osd_release` relevé interdit les OSD plus anciens. On ne « redescend » donc pas une version de façon supportée ; dans une même série, c'est techniquement souvent possible, mais non garanti ni testé : le retour arrière d'une mise à jour, c'est la pause, la correction, la reprise — et une sauvegarde.
8. Sur le VLAN 31 en `secure` : des paquets chiffrés (AES-GCM) après une négociation en clair ; il voit **qui** parle à qui, quand, et combien (métadonnées), pas le contenu. Un client noyau monté sans `ms_mode` : selon sa version, il se connecte en msgr1 (aucun chiffrement possible : contenu en clair) ou en msgr2 `crc` si le service l'accepte ; avec `ms_service_mode secure`, un msgr2 `crc` est refusé, mais msgr1 reste ouvert tant que les MON l'annoncent. Coût : CPU (AES-GCM, accéléré par AES-NI) sur les OSD, les clients et les MON, quelques pourcents de débit et un peu de latence ; il se mesure (E28, pour aller plus loin).
9. Copie du fichier disque d'un OSD chiffré : un volume LUKS, illisible sans la clé, qui est dans le magasin des moniteurs. Une identité `mon 'allow r'` en 20.2.3 : par CVE-2026-50152, elle peut lire tout le magasin clé-valeur, **donc** les clés LUKS (et la clé SSH de l'orchestrateur) ; combinée au fichier copié, elle lit les données. En 20.2.4 : faille corrigée, plus d'accès au magasin. Conclusion : quand la clé et les données sont dans le même système, le chiffrement au repos ne protège que contre la perte du support ; pour séparer, il faut un KMS externe (Vault, M25) ou le chiffrement côté client.
10. **b)** `profile rbd pool=rbd-equipes namespace=mediagenda` donne les opérations RBD (création, ouverture, agrandissement, instantanés, suppression) limitées à cet espace de noms ; `mon 'profile rbd'` donne la lecture des cartes et le droit de mettre un client en liste de blocage (nécessaire au verrou exclusif). a) faux : le listage d'un autre espace de noms est refusé ; c) faux : aucun droit de création de pool ; d) faux : le profil inclut l'écriture. L'espace de noms ne limite **pas** la capacité consommée (pas de quota), ni les ressources du pool partagé (une équipe qui sature le pool gêne les autres), ni la classe de stockage (c'est la règle du pool).
11. Création : rien n'est refusé (provisionnement fin : une image de 1 Tio ne consomme rien tant qu'on n'écrit pas). Écriture : quand le pool atteint son quota (100 Gio de données stockées), le pool passe en `POOL_FULL` et **toutes** les écritures dans ce pool sont refusées — pour **toutes** les équipes qui le partagent, pas seulement la fautive. Conclusion : un pool partagé exige un contrôle par équipe (provisionné ≤ plafond) ou un pool par équipe ; c'est la limite traitée en E31.
12. Le script détecte que la base manque (pas d'instantané `sauv-*` antérieur) et fait un **complet** : RPO intact (24 h), mais un export plus lourd cette nuit-là. Pendant la journée où l'instantané manque, rien ne change pour le RPO : la dernière sauvegarde envoyée est dans PBS. Si le script avait été silencieux (complet raté, incrémental impossible) : on le détecterait par l'âge de la dernière sauvegarde dans PBS (alerte « plus de 26 h », `ms-verif-sauvegardes`) et, mieux, par la restauration de test régulière.
13. **b)** un cluster vide configuré comme l'ancien ; en réimportant les identités (`ceph auth import`), les clients s'authentifient avec leurs clés d'origine. a) faux : aucune donnée (elles sont dans les OSD) ; c) faux : une clé cephx n'est pas liée au `fsid`, elle s'importe ; d) faux : de nouveaux OSD sont créés vides (reprendre d'anciens OSD est une procédure de reconstruction des MON très différente). Pour retrouver le **service** : recréer pools et règles (depuis l'archive ou `plateforme/ceph`), restaurer les volumes depuis PBS (`import-diff`), les données CephFS et S3 (non sauvegardées hors site en v1 : c'est la limite), et repointer les clients (adresses des MON, `fsid` nouveau dans leur configuration).
14. 3 gros nœuds : moins cher par To (moins de châssis, de ports), mais perte d'un nœud = un tiers de la capacité et aucune reconstruction possible en `size=3` (redondance réduite jusqu'au retour) ; la tolérance d'un nœud impose de garder la capacité sous ~45-66 % selon les disques. 6 petits nœuds : coût unitaire plus élevé, mais la perte d'un nœud (1/6) se reconstruit sur les 5 autres, plus vite (parallélisme) ; capacité utile à garder sous ~80 % × 5/6 ; codes d'effacement possibles (`k=4, m=2` tolère 2 pannes pour 1,5× de surcoût au lieu de 3×). Pour MédiSphère : au moins 5-6 nœuds en production.
15. Disques entiers : Ceph suppose que chaque OSD est un domaine de panne et de performance **indépendant** ; un RAID matériel masque les pannes et double la redondance, des partitions ou des disques virtuels sur un même disque physique font croire à de l'indépendance qui n'existe pas (une panne du disque physique emporte plusieurs OSD, et ils se disputent les mêmes E/S). Le lab enfreint tout : 6 OSD SSD sur un seul SSD, 3 HDD sur un seul HDD, tous sur un seul hôte. E28 ne vaut que pour des comparaisons ; aucune conclusion de capacité de production, ni de comportement en panne matérielle (la panne de `ssd-lab` arrêterait tous les OSD SSD à la fois).
16. RGW peut fournir le journal des opérations (`rgw_enable_ops_log` : qui — l'identité S3 —, quoi, quand, d'où) et les journaux d'accès HTTP de l'ingress ; il ne sait pas **quel patient** concerne un objet (il ne voit qu'un nom d'objet opaque), ni quel utilisateur final derrière l'identité de l'application. La traçabilité « qui a consulté le dossier de tel patient » se fait **dans l'application** (MédiDoc journalise l'utilisateur, le patient, le document), dans un journal protégé et conservé (M22) ; Ceph fournit la traçabilité technique en complément.

---

### M08-E33 — Politique de stockage de MédiSphère

**Solution**

Modèle : [`politique-stockage.md`](fichiers/M08-E33/medisphere/docs/stockage/politique-stockage.md). Points structurants : quatre classes de service reliées chacune à une règle et à des pools **existants** ; conditions explicites pour les données de santé (chiffrement en transit et au repos, cloisonnement, sauvegarde, traçabilité) ; seuil de capacité à 40 % justifié par la topologie et les seuils de E20 (perte d'un OSD SSD absorbée par l'autre OSD du même nœud) ; cycle de vie jusqu'à l'**effacement** (instantanés de sauvegarde compris, délai réel lié à la rétention de PBS) ; limites honnêtes (un site, un hyperviseur, pas de sauvegarde hors site des objets en v1).

**Explications**

Une politique de stockage protège autant la Plateforme que les équipes : elle transforme des décisions au cas par cas en règles relisibles, et chaque garantie écrite engage l'équipe. D'où l'exigence de relier chaque phrase à un mécanisme vérifiable, et d'écrire ce qui n'est **pas** garanti.

**Alternatives**
- Une politique courte (une page de classes de service) et les détails dans les runbooks : plus lisible, moins utilisable par un auditeur.
- Classes de service exprimées en SLO chiffrés (disponibilité, latence p99) : la cible, une fois la supervision du M21 en place.

**Pièges classiques**
- Promettre une disponibilité ou des performances que le lab ne peut pas tenir.
- Oublier les instantanés et les sauvegardes dans l'effacement (RGPD).
- Classes de service sans usages interdits.
- Seuils recopiés de la documentation sans les relier à la topologie réelle.

**En production chez MédiSphère**
Politique revue en comité (Claire, Sophie, DPO) ; classes de service exposées dans le catalogue (M28) ; indicateurs mensuels (occupation par classe, demandes, délais) ; contrôle annuel par l'auditeur interne.

**Grille d'auto-évaluation**

| Relecteur | Critère | Attendu |
|---|---|---|
| Claire | Classes de service | chacune reliée à une règle et des pools existants, usages autorisés et interdits |
| Claire | Capacité | seuils justifiés par la topologie, déclencheur d'extension, surallocation écrite |
| Claire | Demandes | chemin (ticket + MR), délais, libre-service, restitution |
| Sophie | Données de santé | 5 conditions vérifiables, renvoi aux exercices |
| Sophie | Effacement | instantanés et sauvegardes inclus, délai réel, preuve |
| Sophie | Accès | identités par équipe, remise par Vault, renouvellement, visibilité de la Plateforme écrite |
| Tous | Limites | ce qui n'est pas garanti est écrit ; exceptions tracées avec une date de fin |

---

### M08-E34 — Livrer du stockage à une équipe en temps limité

**Solution** (déroulé de référence ; à ne lire qu'après ta tentative chronométrée)

| Jalon | Actions | Temps de référence |
|---|---|---|
| T0 → T1 | Lecture du dossier ; branche sur `plateforme/ceph` : équipe `medinotif` dans `allocations.yaml` (bloc `rbd-equipes` 30 Gio, fichier `cephfs` 5 Gio avec `modeles` 2 Gio, objet `medinotif` 10 Gio), quota de `rbd-equipes` porté à 90 Gio (40 + 20 + 30) dans `config/cluster.yaml` après vérification de `ceph df` ; ligne(s) dans `allocations.md` ; `outils/ceph-allocations.sh appliquer --simuler` dans la MR | 15 min |
| T1 → T2 | Fusion, `outils/config-cluster.sh --appliquer` (quota), `outils/ceph-allocations.sh appliquer` (deux passages) ; trousseau `client.medinotif` vers Vault et vers `cephcli01` (600) ; l'**équipe** (toi avec son identité) crée `rabbitmq-recette` de 20 Gio et pose `medisphere.sauvegarde=oui` ; matrice d'isolement (lister, lire, écrire, supprimer) | 25 min |
| T2 → T3 | Utilisateur racine du compte `medinotif` (`radosgw-admin user create --uid=medinotif-root --display-name=… --account-id=<ID> --account-root --gen-access-key --gen-secret`, sortie directement chiffrée dans Vault) ; passage forcé de la sauvegarde (`systemctl start wb-backup-ceph`) et image vue dans le journal ; `ms-verif-ceph` vert | 20 min |
| T3 → T4 | Registre des secrets (identité cephx, identifiants S3 : emplacements), `allocations.md` fusionné, `lab/bin/check 08 34` | 10 min |

Total de référence : ~1 h 10 avec l'outil d'allocation de E31. Sans outil (commandes une à une), compter 2 h et des oublis typiques : droits OSD des sous-volumes isolés, quota du pool partagé, `allocations.md`.

```
admin@cephcli01:~$ sudo rbd create --size 20G rbd-equipes/medinotif/rabbitmq-recette --id medinotif
admin@cephcli01:~$ sudo rbd image-meta set rbd-equipes/medinotif/rabbitmq-recette medisphere.sauvegarde oui --id medinotif
admin@cephcli01:~$ sudo rbd ls rbd-equipes/mediagenda --id medinotif
rbd: listing images failed: (1) Operation not permitted
```

**Explications**

L'exercice mesure l'**outillage** autant que l'opérateur : chaque geste manuel noté dans la feuille de temps est un défaut à corriger dans le code (création de l'utilisateur racine RGW, distribution des trousseaux). La création de l'image par l'identité de l'équipe n'est pas un geste « Plateforme » : c'est l'usage normal du libre-service, ce qui prouve au passage que l'équipe a les bons droits.

**Alternatives**
- Distribution des trousseaux par Vault avec une politique par équipe (M25), lue par l'équipe elle-même : supprime l'étape de copie.
- Pipeline qui applique `allocations.yaml` à la fusion (job protégé) : supprime l'étape manuelle ; écarté en E23 tant qu'il n'existe pas d'exécuteur dédié au stockage.

**Pièges classiques**
- Oublier de relever le quota de `rbd-equipes` : la nouvelle équipe est provisionnée au-delà de ce que le pool permet, sans que personne le voie avant la saturation.
- Créer l'utilisateur racine S3 avec une sortie affichée dans le terminal partagé ou un journal de CI.
- Identité `medinotif` créée à la main avec `allow rw tag cephfs data=cephfs` « pour que ça marche ».
- Image créée par `client.admin` au lieu de l'identité de l'équipe (on ne prouve rien).

**En production chez MédiSphère**
Accueil d'équipe entièrement par MR sur le registre, pipeline qui applique, secrets remis par Vault, objectif « moins de 30 minutes sans intervention » (module 28).
