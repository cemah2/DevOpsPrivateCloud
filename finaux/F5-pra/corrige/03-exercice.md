# Final F5 — Phase 3 : L'exercice — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché. Les documents de référence portent les heures et les mesures d'un lab **imaginé** (exercice du mardi 2026-12-15, T0 à 10:07, heure de Paris) pour montrer la forme : remplace-les par les tiennes.

**Validé hors du lab** (à la rédaction, 23/10/2026) :
- CloudNativePG 1.30, page « Replica clusters » : topologie distribuée (`spec.replica.primary`, `source`, `self` facultatif) ; rétrogradation = changer `primary` sur l'ancien primaire, jeton dans `.status.demotionToken` ; promotion = `primary` **et** `promotionToken` dans la même modification ; **sans jeton, la promotion est un basculement (*failover*) et l'ancien primaire doit être reconstruit** ; `minApplyDelay` incompatible avec `promotionToken` ; avertissement sur un défaut de PostgreSQL (réplicas en cascade restaurant depuis l'archive) corrigé en 18.6 ;
- PowerDNS Authoritative 5.0 (page « Upgrading ») : nouvelle syntaxe `pdnsutil <objet> <action>` (`zone set-kind`, `rrset replace`, `zone increase-serial`), anciens noms encore acceptés ; **`rrset replace` et `zone increase-serial` refusent d'agir sur une zone secondaire sans `--force`** ; types de zone `primary`, `secondary`, `native`, `producer`, `consumer` ;
- SeaweedFS (code de `weed/s3api/auth_signature_v4.go`) : une requête signée à plus de **15 minutes** de l'heure du serveur est refusée (`RequestTimeTooSkewed`) ;
- API de gestion de RabbitMQ : `POST /api/exchanges/<vhost>/<échange>/publish` (réponse `{"routed": true}`) ;
- scripts : `bash -n` et `shellcheck` ; YAML valides.

---

### F5-S08 — Panne : la reprise qui ne reprend pas

**Démarche de diagnostic**

*Symptômes → hypothèses.* Une répétition échoue de trois façons différentes selon la variante : les **données** n'arrivent plus (le témoin de PAR2 ne bouge pas), le **calcul** ne démarre pas (pods en attente), le **coffre** ne démarre pas (VM refusée). Dans les trois cas, les voyants de « processus » étaient verts : c'est la leçon. On ne relance rien avant d'avoir la cause, et on note l'heure de chaque constat (le compte rendu en a besoin).

#### Variante 1 — le témoin ne bouge plus à PAR2 (filer.sync arrêté)

1. Mesurer l'effet, côté destination. Sur la réplique de PAR2, le dernier témoin (requête de RB-356) :
   ```
   admin@adm01:~$ kubectl --kubeconfig ~/.kube/k8s-par2.config -n mediagenda-prod exec \
       "$(kubectl --kubeconfig ~/.kube/k8s-par2.config -n mediagenda-prod get cluster mediagenda-db-par2 -o jsonpath='{.status.currentPrimary}')" \
       -c postgres -- psql -d mediagenda -Atc "SELECT max(cree_le) FROM rendez_vous WHERE praticien = 'PRA-TEMOIN'"
   ```
   Il date d'avant la répétition. La réplique rejoue-t-elle ? `kubectl cnpg status mediagenda-db-par2 -n mediagenda-prod` (avec le contexte de PAR2) : réplique saine, en attente du WAL suivant. Le problème est **en amont** de la base.
2. Le WAL suivant existe-t-il à PAR1, et à PAR2 ? Compare le dernier objet de `cnpg-k8s-par1/mediagenda-db-prod-day0/wals/` sur `s3-01` et sur `s3-02` (`aws s3api list-objects-v2` avec chaque profil, ou la mesure de retard de S04). PAR1 a des WAL récents, PAR2 s'arrête à la même heure que le témoin.
3. Le copieur :
   ```
   admin@s3-02:~$ systemctl list-units --all --type=service | grep -i filer
   admin@s3-02:~$ systemctl status filer-sync@cnpg-k8s-par1.service     # nom de ton unité de S04
   admin@s3-02:~$ journalctl -u filer-sync@cnpg-k8s-par1.service --since -3h | tail
   ```
   `inactive (dead)`, `disabled`, arrêt propre (« Stopped … ») sans erreur : quelqu'un l'a arrêté, rien ne l'a relancé.
4. **Cause racine** : la réplication des objets de PAR1 vers PAR2 est arrêtée ; la base de PAR2 n'a plus rien à rejouer ; aucune alerte, parce que la supervision regardait l'état « en échec » et que la mesure du retard côté destination ne couvrait pas l'archive de la base.
5. **Correctif** : `sudo systemctl enable --now <unité>` ; `filer.sync` reprend à son **point de contrôle** (rien n'est perdu, il rattrape les événements du journal de métadonnées de `s3-01`) ; suivre le rattrapage par l'âge du dernier objet, puis par le témoin à PAR2 (quelques minutes).
6. **Prévention** : mesurer le retard **par l'effet** (âge du dernier témoin vu à PAR2, de bout en bout) et l'alerter ; toute intervention sur une VM de PAR2 passe par une fiche dont le retour dit « réplications relancées » ; contrôle de préparation (ci-dessous).

#### Variante 2 — les pods d'essai restent en attente (nœud cordonné)

1. `kubectl --kubeconfig ~/.kube/k8s-par2.config -n mediagenda-prod get pods` : `Pending` ; `kubectl … describe pod <POD>` : événement `FailedScheduling … 0/1 nodes are available: 1 node(s) were unschedulable`.
2. `kubectl … get nodes` : `Ready,SchedulingDisabled` ; `kubectl … get node k8s-par2-n01 -o yaml | grep -A2 -e unschedulable -e annotations` : cordonné, et une annotation dit par qui et quand.
3. **Cause racine** : un `kubectl cordon` (maintenance de `hp01`) jamais défait. Sur un cluster d'un seul nœud, cordonner revient à interdire tout nouveau pod — la base, déjà démarrée, tourne encore, ce qui rend la panne invisible en veille.
4. **Correctif** : `kubectl --kubeconfig ~/.kube/k8s-par2.config uncordon k8s-par2-n01`, puis observer les pods passer `Running`.
5. **Prévention** : le contrôle de préparation exige « Ready **et** planifiable **et** sans *taint* bloquant » ; une maintenance de `hp01` a une fiche dont la dernière ligne est `uncordon`.

#### Variante 3 — `bao-par2` refuse de démarrer (verrou de sauvegarde)

1. `qm start 1055` sur `hp01` (ou l'interface) : « VM is locked (backup) ».
2. `qm config 1055 | grep lock` : `lock: backup`. Une sauvegarde est-elle en cours ? `pvesh get /nodes/pbs01/tasks --typefilter vzdump --limit 5` et `ps aux | grep vzdump` : non, la dernière tâche s'est arrêtée en erreur (ou il n'y en a pas) — le verrou est **orphelin**.
3. **Cause racine** : une sauvegarde vzdump interrompue laisse son verrou dans la configuration de la VM ; une VM arrêtée verrouillée ne gêne personne… jusqu'au jour où l'on veut la démarrer.
4. **Correctif** : **après** avoir vérifié qu'aucune sauvegarde ne tourne, `qm unlock 1055` ; démarrer pour la répétition, puis l'arrêter (veille).
5. **Prévention** : le contrôle de préparation lit `qm config` des VMs de veille (verrou, état) ; alerte sur les tâches vzdump en erreur de `hp01`.

**Contrôle de préparation** (prévention commune) : [`controle-preparation.sh`](fichiers/F5-S08/k8s/outils/pra/controle-preparation.sh) (`plateforme/k8s`, `outils/pra/`) — sept contrôles par l'effet (témoin vu à PAR2, `filer.sync`, nœud planifiable, `bao-par2` démarrable, série DNS, Argo CD, mémoire de `hp01`), sortie lisible et fichier `--textfile` pour le textfile collector de `adm02` (`pra_par2_pret`). Compte rendu de référence : [`repetition.md`](fichiers/F5-S08/medisphere/docs/pra/exercices/2026-exercice-1/repetition.md).

**Explications**

Une répétition à blanc teste ce que la veille ne teste jamais : **démarrer**. Un site tiède passe ses journées à recevoir des données ; personne n'y démarre de VM ni de pod. Les trois pannes ont la même forme : un état laissé par une intervention humaine (arrêt, cordon, verrou), parfaitement normal pendant l'intervention, et oublié ensuite. Elles ne se voient que par leur **effet** (la donnée n'arrive plus, le pod ne se place pas, la VM ne démarre pas) — d'où un contrôle de préparation qui mesure des effets.

**Alternatives**
- Variante 1 : redémarrer `filer.sync` sans comprendre pourquoi il était arrêté — on répare, mais la prochaine montée de `s3-02` refera la même chose.
- Faire la répétition **avec** promotion de la base (dans un espace d'essai, par une récupération à un instant donné depuis l'archive de `s3-02`) : plus complet, plus long ; c'est l'essai trimestriel de S14.

**Pièges classiques**
- Regarder `systemctl is-failed` : une unité arrêtée proprement n'est pas « en échec ».
- Mesurer le retard sur `s3-02` par l'âge de **n'importe quel** objet : un compartiment qui reçoit encore (MédiDoc par `rclone`) masque celui qui ne reçoit plus.
- `qm unlock` pendant une vraie sauvegarde : on casse la sauvegarde en cours ; on vérifie d'abord.
- Laisser `bao-par2` démarré ou la VM 3501 en place après la répétition : la veille n'est plus la veille (mémoire, et une seconde copie du coffre qui vit sa vie).

**En production chez MédiSphère**
Le contrôle de préparation tourne chaque nuit, son résultat est une alerte (« PAR2 non prêt depuis 30 min ») et un voyant du tableau de bord d'astreinte ; RB-350 commence par lui. Les répétitions à blanc sont trimestrielles (calendrier de S14), les exercices réels annuels.

---

### F5-S09 — Le sinistre : perte de PAR1

**Solution** (déroulé de référence ; les gestes détaillés sont ceux de **ton** RB-350)

*0. La veille et le matin (hors chronomètre).* `controle-preparation` vert ; `lab/bin/check F5 8` vert ; sur ton poste, le VPN `wg1` de `hp01` essayé ; sur `adm02` : le dépôt du workbook (`git clone` depuis GitHub), son `lab/lab.env` (au moins `WB_F5_KUBECONFIG_PAR2`, et `WB_F5_SOURCE_DOC=miroir` pour les checks des phases 1-2 que tu relancerais), les alias SSH des VMs de PAR2 et de `pbs01`, le kubeconfig d'administration de `k8s-par2` (enveloppe), un clone de travail `~/medisphere` du **miroir** de `plateforme/medisphere`. Sur `pve01` : `git pull` de `/root/DevOpsPrivateCloud` (l'annulation s'y lancera). Sophie a son relevé (heure, étape, preuve).

*1. T0 → décision (≈ 15-20 min).*
```
admin@adm02:~$ tail -n 6 /var/lib/ms-sonde-pra/mesures.csv           # code 000 sur les trois noms depuis T0
root@pbs01:~# wg show wg0 latest-handshakes                           # plus de poignée de main
admin@adm02:~$ sudo cat /var/lib/workbook/f5-t0                       # T0 écrit par l'injection
```
Main courante : `[état]` T0, `[ouverture]` INC-6109 (gravité 1), `[action]` cellule ouverte. Le critère de RB-350 (PAR1 injoignable depuis PAR2 et de l'extérieur pendant N minutes, pas de retour avant M heures) est vérifié et écrit ; Claire décide : `[décision]` avec l'heure, l'auteur et le point de non-retour accepté. Pendant l'attente, on **prépare** sans rien rendre irréversible : vérification de l'enveloppe, de la mémoire de `hp01`, relevé du dernier témoin sur la réplique (il servira au RPO).

*2. Vague 1 — confiance et secrets (RB-355).* Restauration de `kms01` en **3501** depuis PBS, carte réseau **coupée** au premier démarrage, adresse changée en 10.20.20.24, carte rebranchée sur `vmbr2` ; descellement par les parts de l'enveloppe (seuil Shamir, gardiens présents) ; démarrage de `bao-par2` (1055), restauration du dernier instantané Raft (`bao operator raft snapshot restore` d'après RB-252/RB-355), descellement automatique par le transit de 3501 ; lecture d'un secret de contrôle. Si les applications de PAR2 utilisent les identifiants **dynamiques** de la base : le moteur `db-mediagenda` restauré pointe vers la base de **PAR1** — sa connexion est reconfigurée vers la base de PAR2 (RB-356), sans quoi les ExternalSecrets de PAR2 ne se renouvellent pas.

*3. Vague 2 — les noms.* dns03 est **secondaire** : PowerDNS 5.0 refuse `rrset replace` et `zone increase-serial` sur une zone secondaire (sauf `--force`, qui serait écrasé au prochain transfert si PAR1 revenait). On change d'abord le type de zone, puis les enregistrements :
```
admin@dns03:~$ sudo pdnsutil zone set-kind medisphere.internal native
admin@dns03:~$ sudo pdnsutil zone set-kind par2.medisphere.internal native
admin@dns03:~$ for n in mediagenda medidoc rdv; do
>   sudo pdnsutil rrset replace medisphere.internal $n.medisphere.internal. CNAME 60 $n.apps.par2.medisphere.internal.
> done
admin@dns03:~$ sudo pdnsutil zone increase-serial medisphere.internal
admin@dns03:~$ sudo pdns_control purge 'medisphere.internal$'             # cache de paquets de l'autoritaire
admin@dns03:~$ sudo rec_control wipe-cache 'medisphere.internal$'          # cache du récurseur
admin@adm02:~$ dig +short @10.20.20.11 mediagenda.medisphere.internal CNAME
```
`native` plutôt que `primary` : personne n'est à notifier pendant le PRA ; `par2.medisphere.internal` passe aussi en `native` pour qu'elle **n'expire pas** si le PRA dure (une zone secondaire sans primaire meurt au bout de son *expire*). Relis la zone (`pdnsutil zone list medisphere.internal`) : `rrset replace` attend un nom **absolu** ou relatif selon les versions — un nom absolu terminé par un point est sans ambiguïté. Les clients gardent l'ancienne réponse au plus 60 s (TTL).

*4. Vague 3 — la base (point de non-retour).* Dans le **miroir** de `mediagenda/deploiement` (clone de travail sur `adm02`, poussé comme RB-350 le prévoit), le fichier de site de PAR2 passe `spec.replica.primary` de `mediagenda-db` à `mediagenda-db-par2`, **sans** `promotionToken` (PAR1 n'a pas été rétrogradé : il ne peut pas l'être) ; Argo CD de `k8s-par2` synchronise. Un `kubectl patch` direct serait défait par l'auto-réparation d'Argo CD si le miroir dit l'inverse : la source de vérité de PAR2, c'est le miroir.
```
admin@adm02:~$ kubectl cnpg status mediagenda-db-par2 -n mediagenda-prod      # primaire, nouvelle ligne temporelle
admin@adm02:~$ kubectl get cluster mediagenda-db-par2 -n mediagenda-prod \
    -o jsonpath='{.status.currentPrimary}{"\n"}{.status.timelineID}{"\n"}'
```
L'archivage de PAR2 part dans `cnpg-k8s-par2` (`s3-02`) ; condition `ContinuousArchiving` à `True`. Main courante : `[action]` promotion, et ce qu'elle rend irréversible (PAR1 sera reconstruit, S12).

*5. Mesure du RPO, tout de suite après la promotion* ([`mesures-pra.sh`](fichiers/F5-S09/k8s/outils/pra/mesures-pra.sh), `plateforme/k8s`, `outils/pra/`) :
```
admin@adm02:~/k8s$ outils/pra/mesures-pra.sh rpo
T0                          : 2026-12-15 10:07:00 CET
dernier témoin à PAR2       : 2026-12-15 09:58:02 CET
RPO (borne haute)           : 8 min 58 s
```
La valeur exacte (dernier témoin écrit à PAR1 **avant T0**) n'est lisible qu'à PAR1 : au retour (S12). Avec un témoin par minute, l'écart entre la borne et la vérité est d'au plus une minute. `[mesure]` dans la main courante.

*6. Vague 4 — les applications.* Fichiers de site de PAR2 dans les miroirs : MédiAgenda (Rollout et HPA de prod réactivés à PAR2), puis MédiDoc (compartiment `medidoc-documents` de `s3-02`), puis Legacy-RDV (restauration de la sauvegarde MariaDB du jour depuis `mariadb-legacy-rdv` de `s3-02` par un objet `Restore` de mariadb-operator, pièces jointes par Velero), MédiNotif ensuite (S11). Le Job de migrations de MédiAgenda ne trouve rien à appliquer : la base est une copie physique. Valkey repart vide (cache). Contrôle : `/pret` à 200 sur `mediagenda.apps.par2…`, puis création et suppression d'un rendez-vous de contrôle par Julien **depuis un poste hors du lab** (critère de reprise d'`objectifs.md`). `temoin-rpo` réactivé à PAR2 (fichier de site), premier témoin vérifié.

*7. RTO et preuves.*
```
admin@adm02:~/k8s$ outils/pra/mesures-pra.sh rto
mediagenda.medisphere.internal     reprise 11:19:45  RTO 73 min
medidoc.medisphere.internal        reprise 11:37:30  RTO 91 min
rdv.medisphere.internal            reprise 12:25:45  RTO 139 min
```
Le check prend la première réponse 2xx « par2 » de la sonde ; `objectifs.md` exige en plus une **création** réussie confirmée par Julien : le rapport (S13) retient la plus tardive des deux. Sophie copie la sonde (`sonde-mesures.csv`) dans `docs/pra/mesures/2026-exercice-1/` à la fin de la journée. Main courante de référence : [`2026-12-15.md`](fichiers/F5-S09/medisphere/docs/pra/journal/2026-12-15.md) (elle couvre aussi S10 et S11).

**Explications**

- **Pourquoi l'isolement plutôt que l'arrêt** : arrêter `pve01` serait plus réaliste et bien plus risqué (le lab entier) ; l'isolement rend PAR1 invisible depuis PAR2 et pour les « patients », tout en le gardant intact pour le retour. Le prix : PAR1 **continue d'écrire** (témoin, archivage vers `s3-01`) — exactement ce qu'il ferait dans un sinistre partiel. C'est le cas difficile du retour (S12).
- **Promotion sans jeton** : en topologie distribuée, un jeton de rétrogradation garantit que le nouveau primaire a rejoué jusqu'au dernier LSN de l'ancien ; sans lui, on promeut ce qu'on a — un basculement. Les écritures de PAR1 entre le dernier WAL arrivé à PAR2 et T0 (le RPO) et **toutes** celles d'après T0 n'existent pas à PAR2, et l'ancien primaire a divergé : il ne pourra que être reconstruit.
- **Le DNS est une dépendance de tout** : avant la base même, pour que `s3-02`, `reg02` et `bao-par2` se résolvent à PAR2 (zone `par2`, servie par dns03) ; après la base, pour que les patients arrivent (zone globale).
- **Le RTO se mesure de T0**, pas de la décision : le temps de décider fait partie de ce que subissent les patients. RB-350 le sait (critère temporel), le rapport le dira (T décision − T0).

**Alternatives**
- Bascule DNS **avant** la promotion (page de maintenance servie par PAR2) : les patients voient « maintenance » au lieu d'une erreur pendant la reprise ; plus propre, demande une route de maintenance prête à PAR2.
- Promotion par `kubectl patch` puis mise à jour du miroir : plus rapide de quelques minutes ; acceptable si RB-350 le prévoit **et** si Argo CD est mis en pause sur l'Application pendant l'intervalle (sinon il remet l'état du miroir).
- `primary` au lieu de `native` pour les zones de dns03 : utile si un second DNS de secours devait suivre dns03.

**Pièges classiques**
- Promouvoir avant la décision « pour gagner du temps » : faute de procédure, et point de non-retour franchi sans mandat.
- `pdnsutil rrset replace … --force` sur la zone **secondaire** : marche, puis le premier transfert depuis PAR1 (au retour) écrase tout sans prévenir.
- Oublier le cache du récurseur (TTL anciens plus longs) ou ceux des clients : la sonde voit encore PAR1 « en erreur » plusieurs minutes.
- Oublier que les identifiants dynamiques d'OpenBao restauré visent la base de PAR1 : l'API démarre, puis échoue au premier renouvellement.
- Lire le RPO **après** avoir réactivé le témoin à PAR2 sans filtrer `cree_le < T0` : on trouve un témoin « récent » et un RPO nul.
- Utiliser `pve01` « juste pour regarder » : l'exercice ne prouve plus qu'on sait reprendre sans PAR1.

**En production chez MédiSphère**
Le déclenchement est une décision de direction, tracée ; la cellule s'ouvre par un pont téléphonique qui ne dépend pas de PAR1 ; les mesures sont automatiques (sonde, témoin, horodatage de chaque vague par le runbook outillé) ; un vrai sinistre ajoute ce que l'exercice n'a pas : l'information des clients HDS, l'éventuelle déclaration d'incident, l'assurance, et la reconstruction d'un site principal (des semaines).

---

### F5-S10 — Panne : les surprises de la crise

**Démarche de diagnostic**

*Symptômes → hypothèses.* Pendant un PRA, on n'a ni PAR1 pour comparer ni la supervision complète. Trois familles expliquent la plupart des surprises d'un site de repli : le **temps** (horloges sans source), les **noms** (une dépendance à PAR1 qui revient), les **accès** (un compte ou un secret absent). On les vérifie dans cet ordre, du moins cher au plus cher. INC-6110 s'ouvre dans la main courante d'INC-6109.

#### Variante 1 — MédiDoc n'enregistre plus, la base n'archive plus (horloge de s3-02)

1. Journaux de MédiDoc à PAR2 (`kubectl logs`) : erreurs S3 `RequestTimeTooSkewed` (« The difference between the request time and the server's time is too large ») ; `kubectl cnpg status mediagenda-db-par2` : archivage en échec, même message dans les journaux du plugin.
2. Le temps des deux côtés :
   ```
   admin@adm02:~$ date -u; ssh s3-02 date -u
   admin@s3-02:~$ chronyc tracking ; chronyc -n sources
   ```
   `s3-02` a 25 min d'avance ; `Leap status : Not synchronised` ; une seule source, `10.10.20.1`, marquée injoignable (`?`).
3. **Cause racine** : la seule source de temps de `s3-02` est la passerelle de PAR1 (variable `ms_serveurs_ntp` de `group_vars/all` appliquée aussi à PAR2) ; en veille le tunnel la rendait joignable ; depuis T0, `s3-02` dérive, et un redémarrage avec une horloge matérielle fausse l'a décalé d'un coup. SeaweedFS refuse toute signature à plus de 15 min.
4. **Correctif** : source de PAR2 (`10.20.20.1`, `hp01`) par le rôle `base` avec la variable de site ([`group_vars/site_par2/temps.yml`](fichiers/F5-S10/ansible/inventories/lab/group_vars/site_par2/temps.yml)) ; puis recaler :
   ```
   admin@s3-02:~$ sudo chronyc -a makestep && chronyc tracking
   ```
   ⚠️ Recaler en arrière de 25 min une machine qui a écrit des objets « dans le futur » : les dates de ces objets restent fausses (sans effet sur leur contenu) ; note-le. Vérifie ensuite que l'archivage a rattrapé (`Last Archived WAL` récent, les WAL accumulés dans `pg_wal` de PAR2 se vident) et préviens le support : les dépôts refusés pendant la panne sont à refaire.
5. **Prévention** : deux sources de temps de PAR2 au moins ; alerte d'écart d'horloge (`node_timex_offset_seconds`, `node_timex_sync_status`) dans la supervision de PAR2 (S11) ; le contrôle de préparation compare les horloges de PAR2.

#### Variante 2 — les noms internes ne se résolvent plus (récurseur de dns03 renvoyé vers PAR1)

1. Le symptôme est progressif : les réponses en cache survivent jusqu'à leur TTL, puis tout casse.
   ```
   admin@adm02:~$ dig @10.20.20.11 s3-02.par2.medisphere.internal          # SERVFAIL après délai
   admin@dns03:~$ dig @127.0.0.1 -p 5300 s3-02.par2.medisphere.internal    # l'autoritaire local répond
   ```
   L'autoritaire va bien : c'est le **récurseur**.
2. `sudo cat /etc/powerdns/recursor.yml` : `forward_zones` renvoie `medisphere.internal`, `par1…` et `par2…` vers `10.10.20.10:5300` et `10.10.20.16:5300` ; `journalctl -u pdns-recursor` : délais dépassés vers ces adresses.
3. **Cause racine** : la configuration de temps normal (récurseur de PAR2 qui interroge les autoritaires de PAR1) a été réappliquée pendant la crise ; sans PAR1, plus rien ne se résout.
4. **Correctif** : variables du rôle `powerdns_recursor` pour le site ([`powerdns_recursor.yml.extrait`](fichiers/F5-S10/ansible/inventories/lab/group_vars/site_par2/powerdns_recursor.yml.extrait)) → relais vers `127.0.0.1:5300` ; rôle rejoué (ou, en urgence, le fichier corrigé à la main puis le rôle rejoué pour que le code dise la même chose) ; redémarrage du récurseur, cache vidé, contrôle par `dig`.
5. **Prévention** : pendant un PRA, **gel** d'Ansible sur `site_par2` sauf décision de la cellule ; test (Molecule ou contrôle de préparation) qui refuse un `recursor.yml` de PAR2 contenant une adresse de PAR1.

#### Variante 3 — Argo CD de PAR2 ne lit plus les miroirs (compte miroir refusé par sshd)

1. `kubectl -n argocd get applications.argoproj.io` : toutes en `Unknown`/`ComparisonError` ; détail : `ssh: handshake failed: ssh: unable to authenticate`.
2. Sur `adm02` :
   ```
   admin@adm02:~$ sudo journalctl -u ssh --since -1h | grep miroir         # « not allowed because not listed in AllowUsers »
   admin@adm02:~$ sudo sshd -T -C user=miroir,host=k8s-par2-n01,addr=10.20.20.50 | grep -i allowusers
   admin@adm02:~$ ls /etc/ssh/sshd_config.d/
   ```
3. **Cause racine** : un durcissement SSH (`AllowUsers` limité au compte d'administration) a exclu le compte technique `miroir` : plus aucun changement GitOps n'atteint PAR2. Les applications tournent (rien n'est supprimé), mais la crise ne se pilote plus.
4. **Correctif** : ajouter `miroir` à la liste (ou retirer le fichier s'il n'a pas de raison d'être), `sudo sshd -t && sudo systemctl reload ssh` ; `argocd app get <APP> --hard-refresh` (ou attendre le cycle) ; vérifier que le changement poussé pendant la panne est appliqué.
5. **Prévention** : le durcissement liste les comptes techniques dans une variable de site ; le contrôle de préparation fait un `git ls-remote` avec la clé de lecture d'Argo CD.

**Explications**

Ces trois pannes ne se produisent qu'**en** PRA : en temps normal, PAR1 masque la dépendance (le temps et les noms passent par le tunnel ; la configuration fautive est sans effet). C'est la définition d'une dépendance oubliée : on ne la voit qu'en coupant. Le diagnostic sans référence repose sur des comparaisons **locales** (autoritaire contre récurseur, horloge de deux VMs de PAR2, compte qui marche contre compte refusé).

**Alternatives**
- Variante 1 : corriger l'horloge des clients plutôt que du serveur — faux remède ; c'est le serveur qui n'a plus de source.
- Variante 3 : faire pointer Argo CD vers un dépôt local de `k8s-par2` — contourne `adm02` mais crée une seconde source de vérité à réconcilier au retour.

**Pièges classiques**
- Redémarrer SeaweedFS ou MédiDoc « pour voir » : l'horloge reste fausse.
- `makestep` sans corriger la source : la dérive recommence.
- Vider le cache du récurseur et conclure que « ça remarche » parce que la première réponse vient du cache négatif expiré… puis tout recasse.
- Retirer tout le fichier de durcissement sans demander pourquoi il existait (Sophie l'a peut-être demandé).

**En production chez MédiSphère**
Les variables de site sont testées par un contrôle « aucune adresse 10.10.x.x dans la configuration de PAR2 » ; la supervision de PAR2 alerte sur l'horloge ; en crise, tout changement de configuration passe par la cellule (une ligne `[décision]`), même automatisé.

---

### F5-S11 — Tenir en mode dégradé

**Solution**

Document de référence : [`mode-degrade.md`](fichiers/F5-S11/medisphere/docs/pra/exercices/2026-exercice-1/mode-degrade.md).

*1. Sauvegarder PAR2.* La base de PAR2 archive déjà (vague 3) ; ajouter une sauvegarde de base immédiate et vérifier le `ScheduledBackup` du fichier de site :
```
admin@adm02:~$ kubectl cnpg backup mediagenda-db-par2 -n mediagenda-prod
admin@adm02:~$ kubectl get backups.postgresql.cnpg.io -n mediagenda-prod
```
Les VMs du pool `par2` : une sauvegarde vzdump vers le PBS de `hp01` (stockage PBS de l'hyperviseur de PAR2, namespace `par2`) — **sans** modifier `ds-lab` ni la configuration de PBS (seulement un travail de sauvegarde côté Proxmox VE de `hp01`). Tout est sur les disques de `hp01` : la vraie question est la copie **hors** de `hp01`, à décider et à écrire (disque chiffré de l'enveloppe, compartiment chiffré chez un tiers HDS…), avec le risque accepté.

*2. Superviser a minima.* Paquets Debian sur `adm02` (`prometheus`, `prometheus-alertmanager`, `prometheus-blackbox-exporter`) et Mailpit de secours : [`prometheus.yml`](fichiers/F5-S11/adm02/prometheus/prometheus.yml), [`regles-pra.yml`](fichiers/F5-S11/adm02/prometheus/regles-pra.yml), [`alertmanager.yml`](fichiers/F5-S11/adm02/prometheus/alertmanager.yml), [`blackbox.yml`](fichiers/F5-S11/adm02/prometheus/blackbox.yml), [`mailpit.service`](fichiers/F5-S11/adm02/systemd/mailpit.service) ; exportateur de la base publié par [`metriques-cnpg.yaml`](fichiers/F5-S11/k8s/sites/par2/supervision/metriques-cnpg.yaml) (`LoadBalancer` 10.20.20.210, réservé à `adm02`). Valide avant de lancer : `promtool check config`, `promtool check rules`, `amtool check-config`. **Essaie** une alerte (arrêt de 4 min d'une application, ou règle de test) jusqu'au courriel dans Mailpit. Mémoire : ≈ 300 Mio ; décision écrite si `adm02` passe de 1 à 1,5 Go.

*3. MédiNotif.* RabbitMQ à un nœud dans `k8s-par2` (manifestes du M27, fichier de site : `replicas: 1`), topologie par le Topology Operator depuis le miroir de `plateforme/donnees`, puis le worker. MédiAgenda recommence à publier dès que son `MEDIAGENDA_AMQP_URL` vise un courtier joignable : note l'heure de la première publication réussie (journaux de l'API). Rejeu ([`rejouer-notifications.sh`](fichiers/F5-S11/k8s/outils/pra/rejouer-notifications.sh)) : compter d'abord, publier ensuite.
```
admin@adm02:~/k8s$ outils/pra/rejouer-notifications.sh 2026-12-15T08:50:00Z 2026-12-15T13:14:00Z
admin@adm02:~/k8s$ outils/pra/rejouer-notifications.sh 2026-12-15T08:50:00Z 2026-12-15T13:14:00Z --publier
```
(bornes en UTC : 08:50 UTC = 09:50 heure de Paris, huit minutes avant le dernier témoin retrouvé ; 13:14 UTC = première publication réussie à PAR2 ; adapte-les à ta journée.) La fenêtre part un peu **avant** le dernier témoin retrouvé à PAR2 (messages publiés à PAR1 mais peut-être pas consommés avant T0) et s'arrête à la première publication réussie à PAR2 : on accepte quelques doublons, jamais un trou.

*4. Les demandes des métiers.* Une réponse par demande, datée, avec son auteur et sa raison (tableau de `mode-degrade.md`) : non au correctif non urgent (gel), non à l'extraction Data (périmètre), explication et ressaisie pour le rendez-vous de la fenêtre perdue (et liste préparée pour le retour), oui à la traçabilité des accès (journaux SSH, audit OpenBao, audit de l'API de `k8s-par2`, poignées de main `wg1`), une date de retour qui dépend du runbook de retour, pas de l'envie d'en finir.

*5. Le journal.* Messages d'état à heure fixe, entrées `[état]` à chaque point de situation, décisions tracées ; `mode-degrade.md` poussé dans le miroir.

**Explications**

Le mode dégradé est l'état le plus long d'un PRA et le moins préparé : un site de repli est dimensionné pour **reprendre**, rarement pour **durer**. Trois choses se dégradent avec le temps à PAR2 et méritent d'être écrites : les copies de données qui n'existent que là (un serveur, un bâtiment), les échéances (zones DNS secondaires, signatures DNSSEC, certificats émis par `ca01`, baux d'OpenBao), et la mémoire de `hp01` qu'on est tenté de remplir avec « juste un service de plus ». `objectifs.md` disait « pas de Prometheus à PAR2 » : c'est un écart à porter au rapport (S13) — l'incident INC-6110 l'a montré.

**Alternatives**
- Supervision dans `k8s-par2` (Prometheus mononœud par le chart de la plateforme) : cohérent avec PAR1, mais dans le même nœud que ce qu'il surveille, et plus lourd.
- Rejeu par MédiAgenda elle-même (une commande d'administration qui republie) : meilleur à terme (PLAT-35xx au rapport), absent aujourd'hui.
- Mailpit sur le poste de l'apprenant à travers `wg1` : marche, mais la boîte de la cellule ne doit dépendre d'aucun poste personnel.

**Pièges classiques**
- Croire que la sauvegarde vers `ds-lab` protège de la perte de `hp01` : même machine.
- Journaliser les destinataires pendant le rejeu, ou les écrire dans la main courante : données personnelles.
- Rejouer les témoins (`PRA-TEMOIN`) : du bruit dans MédiNotif et dans les mesures.
- Promettre à la direction une heure de retour sans RB-351 : le retour est un changement, avec ses propres préalables.
- Démarrer MédiVisio « puisqu'il reste de la mémoire » : hors périmètre, et la mémoire est celle de la marge de PAR2.

**En production chez MédiSphère**
Une supervision de PAR2 permanente (pas seulement en PRA) qui alerte aussi sur l'état de préparation ; une cible de sauvegarde hors des deux sites ; une fonction de rejeu des notifications dans MédiAgenda ; des réponses types aux demandes fréquentes en crise dans `cellule-de-crise.md`.

---

## Points non testés en conditions réelles

- **Table `inet f5_sinistre` sur `gw01`/`gw02`** : interaction avec la traduction des tunnels vers la VIP WAN (M07-E26) et `conntrackd` — les règles jettent les paquets dans les chaînes `input`/`forward`/`output` à la priorité −150, sans toucher à VRRP, BGP (VLAN 40, `wg2`) ni au NAT ; la règle `ct direction original` sur `ens18` (connexions ouvertes depuis le LAN, sauf `pve01`) est à confirmer avec ton plan de bordure (adresse source de `pve01` lue par `ip route get 10.10.10.10`). Un rechargement de `/etc/nftables.conf` (qui commence par `flush ruleset`) efface la table.
- Variante 1 de S08 : le nom de l'unité `filer.sync` est trouvé par son `ExecStart` dans `/etc/systemd/system/` (une unité modèle `@` de S04 est détectée par son fichier modèle ; une instance activée par un lien est relancée sous le nom du modèle — vérifie l'annulation sur ton lab).
- Variante 3 de S08 : `qm set 1055 --lock backup` sur une VM arrêtée, puis `qm unlock` (comportement documenté de `qm`, non essayé sur le Proxmox VE installé à côté de PBS).
- Variante 1 de S10 : `date -s '+25 minutes'` alors que chrony tourne sans source joignable ; recalage arrière par `chronyc -a makestep` (la configuration du rôle `base` contient `makestep 1 3`) ; effet d'un recul d'horloge sur le journal de métadonnées du filer de `s3-02`.
- Variante 2 de S10 : réécriture de `recursor.yml` par `python3` + `yaml` (PyYAML, dépendance de cloud-init sur les images du lab) ; nom de l'unité `pdns-recursor`.
- Variante 3 de S10 : nom de l'unité SSH `ssh` (Debian 13) et forme exacte du message de refus dans le journal.
- `pdnsutil rrset replace` de PowerDNS 5.0 : NAME absolu accepté (relis la zone après) ; `pdns_control purge` et `rec_control wipe-cache` avec le suffixe `$`.
- Promotion de `mediagenda-db-par2` sans jeton par le miroir et Argo CD (temps de synchronisation) ; archivage immédiat sous `mediagenda-db-par2` dans `cnpg-k8s-par2`.
- Métriques `cnpg_pg_stat_archiver_seconds_since_last_archival` et `cnpg_pg_replication_lag` des requêtes par défaut de CloudNativePG 1.30 ; Service `LoadBalancer` avec `externalTrafficPolicy: Local` et annotation `lbipam.cilium.io/ips` en annonces L2.
- Options de Mailpit `--listen`, `--smtp`, `--database`, `--ui-auth-file` (relues dans `mailpit --help` de la version de `mon01`).
- Publication par l'API de gestion de RabbitMQ à travers la route HTTPS de PAR2 (port et authentification de l'interface de gestion de la grappe de PAR2).
