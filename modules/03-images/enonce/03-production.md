# Module 03 — Palier 3 : Production

Les images existent : une image de base par famille, une image dorée Debian versionnée, un test minimal, une publication qui pose `current`. Claire Morel fixe la barre pour la suite : « Une image qui sort de chez nous, c'est un produit de sécurité. Je veux qu'elle soit durcie selon nos règles, testée sans humain, construite par la forge et pas par ton poste, retirée quand elle vieillit, et que la stratégie soit écrite avant qu'Ansible et OpenTofu ne s'en servent. » Ce palier industrialise : durcissement (E13), tests automatiques complets (E14), pipeline planifié (E15), cycle de vie et retrait (E16), décision d'architecture (E17), et les questions de chaîne de confiance qu'un auditeur posera (E18).

> **Rappels** : tout se fait depuis `adm01`, dans `~/src/images` (variable `WB_SRC`), par MR fusionnée dans `main` avec pipeline vert. Accès Proxmox de l'outillage : `~/.config/workbook/pve-packer.env` (jeton `wb-packer@pve!packer`). VMs de test : 2030-2039 (2030-2033 réservées à `tests/tester-image.sh`), étiquette `env-m03`, **toujours détruites** après usage. Templates d'essai : 9090-9099, supprimés en fin d'exercice. Règles du module : [`00-introduction.md`](00-introduction.md).

---

### M03-E13 — Durcir une image  `LIBRE` `★★★`

> **Ticket SEC-450** — *De : Sophie Laurent* — *Copie : Karim Benali*
> L'image dorée v1 refuse root et les mots de passe en SSH : c'est un début. Pour l'audit HDS, je veux une image durcie selon un référentiel reconnu, avec la liste de ce qui est appliqué, de ce qui ne l'est pas et pourquoi. Mes exigences minimales, pour **toutes** les VMs :
> - SSH : ni redirection X11, ni transfert d'agent, ni redirection de ports ; trois essais d'authentification au plus, trente secondes pour s'authentifier ; aucun algorithme à base de SHA-1 ; les sessions abandonnées sont fermées ; une bannière légale avant l'authentification.
> - Noyau : pas de redirections ICMP acceptées ni émises, pas de routage par la source, paquets martiens journalisés, adresses du noyau cachées à **tous** les utilisateurs (root compris), journal du noyau réservé aux administrateurs.
> - Modules : protocoles réseau rares (DCCP, SCTP, RDS, TIPC), systèmes de fichiers exotiques, stockage USB et FireWire : impossibles à charger, même à la main.
> - `/dev/shm` sans exécution, sans setuid, sans périphériques.
> - Traçabilité : un audit noyau actif qui trace au moins les changements d'identités, de sudo, de configuration SSH et le chargement de modules.
> - Surface : rien d'autre que SSH n'écoute sur le réseau.
> Et une mesure objective avant/après avec un outil d'audit du marché. Rien de tout ça ne doit casser cloud-init, l'agent, Packer ou vos tests.

**Objectifs pédagogiques**
- Traduire une politique de sécurité en mesures techniques vérifiables, rattachées à un référentiel (guide ANSSI de configuration GNU/Linux, CIS Benchmark).
- Distinguer ce qui relève de l'image (commun à toutes les VMs) de ce qui relève du rôle (Ansible, M04), et documenter les exceptions.
- Durcir sans casser : connaître les dépendances de cloud-init, de l'agent QEMU et de la construction elle-même.
- Mesurer l'effet d'un durcissement (configuration **effective**, outil d'audit) plutôt que relire des fichiers.

**Prérequis** : M03-E09 (image dorée v1), M03-E10 (versionnage, publication, test minimal).
**Durée indicative** : 4 à 5 h.

**Contexte technique**
- Livrables dans `plateforme/images` : un script `scripts/durcir.sh` lancé par le build `debian13-gold` (et plus tard `rocky10-gold`, M03-E25), ses fichiers de configuration sous `fichiers/` et une documentation `docs/durcissement.md`.
- VM de recette : **2035 `m03-durci`**, clone complet de la version durcie (étiquette `env-m03`, VNet `vsandbox`, utilisateur cloud-init `admin` et ta clé), à garder jusqu'à la validation, puis à détruire. Le contrôle lit son état par l'agent QEMU.
- Le premier build durci donne une nouvelle version (`AAAAMMJJ-N`) ; ne la publie (`current`) qu'après la recette.

**Contraintes**
- Chaque mesure est **vérifiée par le script lui-même** pendant le build : un écart fait échouer le build (pas de template à moitié durci).
- Le script est idempotent, sans remarque ShellCheck, et ne dépend d'aucune version précise d'OpenSSH qu'il ne contrôle pas.
- Aucune mesure ne casse : le premier démarrage cloud-init d'un clone, l'agent QEMU, la connexion SSH par clé depuis `adm01`, le build Packer lui-même (qui se connecte en SSH pendant le durcissement), le test d'image.
- `docs/durcissement.md` contient, pour chaque mesure : ce qui est fait, où, la référence (thème ANSSI ou CIS), comment la vérifier ; puis un tableau des **exceptions** (référence, raison, compensation, date de revue) et le résultat de la mesure avant/après.
- La configuration SSH durcie complète celle de E09 sans la contredire ; relis l'ordre de lecture des fichiers de `sshd_config.d`.

**Critères de réussite**
- [ ] Sur la VM 2035, la configuration **effective** de sshd, les paramètres noyau (globaux **et** sur l'interface réseau), les modules, `/dev/shm`, l'audit et les ports en écoute respectent toutes les exigences du ticket.
- [ ] Sur la même VM, cloud-init a terminé sans erreur et l'agent répond.
- [ ] `scripts/durcir.sh` est sur `main`, appelé par `debian13-gold/build.pkr.hcl`, sans remarque ShellCheck.
- [ ] `docs/durcissement.md` est sur `main` : mesures, références, exceptions, mesure avant/après chiffrée.

**Vérification** : `lab/bin/check 03 13`

<details><summary>Indice 1</summary>

Une mesure de durcissement a trois états possibles : écrite dans un fichier, appliquée au système en cours, et **effective** au démarrage suivant d'un clone. Seul le troisième compte. Pour SSH, la commande qui donne la configuration effective est dans le corrigé de E09 ; pour le noyau, demande la valeur sur `all` **et** sur l'interface : la règle de combinaison n'est pas la même pour tous les paramètres (documentation `ip-sysctl` du noyau).
</details>

<details><summary>Indice 2</summary>

Quatre pièges connus : (1) une liste d'algorithmes contenant un nom que la version d'OpenSSH ne connaît pas empêche sshd de démarrer ; (2) « blacklist » n'empêche pas un `modprobe` explicite ; (3) le lecteur cloud-init de Proxmox est un CD : quel système de fichiers ne faut-il surtout pas interdire ? (4) `systemd-resolved` ouvre un port sur toutes les interfaces par défaut : lequel, et pour quoi faire ?
</details>

<details><summary>Indice 3</summary>

Pour la mesure avant/après, Lynis (paquet Debian) donne un indice et une liste de suggestions en quelques minutes, sans rien modifier. Lance-le sur un clone de la v1 et sur la VM 2035, avec la même version de l'outil. Chaque suggestion non suivie doit apparaître dans tes exceptions ou relever d'un rôle Ansible.
</details>

**Pour aller plus loin** : passe `ssh-audit` (dépôt Debian) contre la VM 2035 depuis `adm01` et compare avec la v1 ; lis la section « Durcissement » du guide ANSSI sur les paramètres de la mémoire (`init_on_alloc`, `slab_nomerge`…) et dis lesquels mériteraient une ligne de commande noyau dans l'image.

---

### M03-E14 — Tester automatiquement une image  `LAB` `★★`

> **Ticket PLAT-452** — *De : Karim Benali*
> Le test de E10 prouve qu'un clone démarre et s'administre. Il ne prouve pas qu'il est **différent de ses frères**, qu'il a l'heure, que notre autorité est là, que le durcissement de Sophie est effectif ou que le compte de construction a disparu. Je veux un test qui couvre tout ce qu'on promet dans le catalogue, qui tourne aussi bien sur `adm01` qu'en CI, qui produise un rapport lisible dans GitLab, et qui sache dire **non** : montre-moi qu'il rejette une image mal préparée.

**Objectifs pédagogiques**
- Écrire un test d'acceptation d'image qui vérifie des **propriétés** (unicité, synchronisation, configuration effective) plutôt que la présence de fichiers.
- Rendre un test autonome et portable : aucune dépendance au poste qui le lance (clé, `known_hosts`, multiplexage SSH).
- Garantir le nettoyage quoi qu'il arrive, et produire un rapport JUnit exploitable par la CI.
- Prouver qu'un test détecte un défaut (test du test).

**Prérequis** : M03-E10 (test minimal `tests/tester-image.sh`, `outils/pve.sh`), M03-E13.
**Durée indicative** : 3 h.

**Contexte technique**
- Point de départ : `tests/tester-image.sh` de E10 (un clone lié en 2030-2033, contrôles de base, destruction par piège `EXIT`). Interface inchangée : `tests/tester-image.sh <VMID-template>`, codes 0 (conforme), 1 (échec), 2 (usage), 3 (refus d'un garde-fou).
- Le test tournera en CI sur `runner01` (E15), sous l'utilisateur `gitlab-runner`, qui n'a **pas** de clé SSH : il ne doit pas en avoir besoin.
- Passerelle et serveur de temps du VLAN 99 : 10.10.99.1 ; DNS : 10.10.20.10.

**Travail demandé**
1. **Deux clones plutôt qu'un.** Fais créer au test **deux** clones liés du template, démarrés en parallèle. Note dans ton journal pourquoi un seul clone ne peut pas prouver l'unicité d'une identité, et quelles identités tu compares.
2. **Une clé jetable.** Remplace la clé de ton poste par une clé générée par le test, détruite à la fin. Le `known_hosts` est propre au test ; justifie ton choix pour la vérification de la clé d'hôte (`StrictHostKeyChecking`) et ce qu'il laisse comme risque. Garde `-o ControlPath=none` : explique dans ton journal ce qui arriverait sans.
3. **Les contrôles.** Ajoute au minimum, sur l'un ou les deux clones :
   - cloud-init `status` à 0, nom d'hôte égal au nom de la VM ;
   - `machine-id` initialisé et différent entre les clones ; clés d'hôte SSH différentes **et** générées au premier démarrage du clone ; adresses DHCP différentes ;
   - compte de construction absent, aucun historique de shell hérité ;
   - chrony synchronisé sur la passerelle du VLAN (avec une attente bornée) ;
   - résolution DNS d'un nom du lab ; CA provisoire présente **dans le magasin système** (pas seulement le fichier) ;
   - configuration effective de sshd (E09 et E13), quelques paramètres noyau et modules de E13, auditd, ports en écoute ;
   - journal persistant, correctifs de sécurité automatiques.
   Les commandes du système (`sysctl`, `modprobe`…) ne sont pas dans le `PATH` d'un utilisateur ordinaire sur Debian : traite-le.
4. **Le rapport.** Option `--junit FICHIER` : un `testsuite` JUnit, un `testcase` par contrôle, `failure` avec un message utile.
5. **Le nettoyage.** Les deux VMs sont détruites dans tous les cas (succès, échec, Ctrl-C), sans jamais détruire une VM que le test n'a pas créée. Option `--garder` : en cas d'échec seulement, les VMs restent pour analyse et le test affiche comment les détruire.
6. **Le test du test.** Fabrique une image volontairement mal préparée dans la zone d'essai (VMID 9091) : clone complet de la version `current`, démarré une fois, arrêté, converti en template **sans** préparation au clonage. Lance le test dessus : il doit échouer, et le rapport doit dire **pourquoi**. Lance-le ensuite sur la version `current` : il doit réussir. Supprime 9091.
7. Fusionne par MR. Note la durée totale d'un test dans ton journal : elle comptera dans le pipeline.

> ⚠️ **Attention** : la VM 9091 démarrée puis convertie porte une identité (clés d'hôte, `machine-id`) : ne la clone pour rien d'autre que ce test, et supprime-la à la fin (`qm destroy 9091 --purge` en root sur `pve01`, après avoir vérifié le VMID et le nom).

**Critères de réussite**
- [ ] `tests/tester-image.sh` est sur `main`, sans remarque ShellCheck, `--help` décrit l'usage, sans argument il sort avec le code 2.
- [ ] Il couvre au minimum les propriétés du point 3 et produit un rapport JUnit.
- [ ] Ton journal montre un échec motivé sur 9091 et un succès sur `current`, avec leurs durées.
- [ ] Aucune VM ne reste en 2030-2033 ni en 9090-9099.

**Vérification** : `lab/bin/check 03 14`

<details><summary>Indice 1</summary>

`/proc/uptime` donne le temps écoulé depuis le démarrage ; `stat -c %Y` l'heure de modification d'un fichier. Une clé d'hôte générée au premier démarrage du clone est plus récente que ce démarrage. Pour l'unicité, compare des empreintes (`ssh-keygen -lf`), pas des fichiers.
</details>

<details><summary>Indice 2</summary>

`chronyc waitsync` attend une synchronisation avec une limite d'essais ; la source sélectionnée est marquée `^*` dans `chronyc -n sources`. La passerelle du VLAN se lit dans la table de routage de la VM. Pour la CA, `openssl verify -CAfile <magasin consolidé> <certificat>` répond à la vraie question : « ce certificat est-il une ancre de confiance du système ? ».
</details>

<details><summary>Indice 3</summary>

Pour le nettoyage, un tableau des VMID créés, rempli **au fur et à mesure** des clonages, est plus sûr qu'une liste calculée à la fin : si le second clonage échoue, le premier doit quand même être détruit.
</details>

**Pour aller plus loin** : remplace les contrôles en SSH par une description déclarative (Goss ou Testinfra, module 29) ; compare lisibilité, vitesse et dépendances.

---

### M03-E15 — Pipeline de construction d'images  `LAB` `★★★`

> **Ticket PLAT-455** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent*
> Les images sortent encore de ton poste. Je veux que la forge les construise : chaque semaine sans que personne n'y pense, et à la demande quand un correctif critique sort. Une image n'est publiée que si ses tests passent, deux constructions ne se lancent jamais en même temps, et aucun secret n'apparaît dans un journal. Sophie veut que `runner01` n'ait accès à Proxmox que pour ça, et que ce soit écrit.

**Objectifs pédagogiques**
- Concevoir un pipeline de construction d'artefacts d'infrastructure : validation sur MR, construction planifiée ou manuelle, test, publication, rétention.
- Maîtriser les mécanismes GitLab CI utiles ici : `rules` selon la source du pipeline, jobs manuels, `needs`, `resource_group`, artefacts et `dotenv`, rapports JUnit, pipelines planifiés et leurs droits.
- Ouvrir à un runner un accès réseau et API minimal et justifié (pare-feu `gw01`, pare-feu Proxmox).
- Gérer les secrets de construction en CI (variables protégées, masquées) sans les exposer aux pipelines de MR.

**Prérequis** : M01-E24 (gabarits CI), M02-E24 (outils sur `runner01`), M03-E08 (`outils/construire.sh`), M03-E10, M03-E14.
**Durée indicative** : 4 à 5 h.

**Contexte technique**
- `runner01` (VMID 1007, 10.10.20.15, VLAN INFRA) : GitLab Runner 19.4, exécuteur `shell`, étiquette `shell`, utilisateur `gitlab-runner`.
- Flux à ouvrir (et seulement ceux-là) : `vsandbox` → `runner01` TCP 8100-8199 (serveur HTTP de Packer) ; `runner01` → `vsandbox` TCP 22 (communicateur de Packer, tests) ; `runner01` → `pve01` TCP 8006 sur `gw01` **et** dans le pare-feu Proxmox (IPSet `automation` contenant 10.10.20.15, règle d'entrée 8006). Rappel M00 : INFRA ne joint ni `vsandbox` ni `pve01` aujourd'hui.
- Sur `runner01`, Packer s'installe comme sur `adm01` (E02 : dépôt APT HashiCorp, clé vérifiée) ; l'autorité de `pve01` (ton ancre de M02-E08) doit être approuvée par son magasin système. L'URL de l'API utilise `<IP-PVE01>` (l'adresse présente dans le certificat).
- Le serveur HTTP de Packer doit écouter sur 10.10.20.15 en CI (la valeur par défaut du projet est l'adresse de `adm01`).
- Variables CI du projet : `PKR_VAR_proxmox_url`, `PKR_VAR_proxmox_username`, `PKR_VAR_proxmox_node` (protégées), `PKR_VAR_proxmox_token` (protégée, **masquée**, cachée si ta version le propose).
- Étapes attendues : `validate` (MR et `main`), `build` (images dorées : planifié chaque semaine et manuel sur `main` ; images de base : manuel seulement), `test`, `publish` (qui appelle `outils/publier-image.sh`, puis la rotation de E16 quand elle existe). La dette de E02 (hooks Packer sautés en CI) est soldée.

> ⚠️ **Attention** : tu modifies `gw01` et le pare-feu de `pve01`. Applique la procédure de M00-E21 : session ouverte, `nft -c -f` avant tout rechargement, retour arrière programmé. Pour le pare-feu Proxmox, une règle d'entrée mal écrite au niveau du centre de données peut te couper de l'interface web : garde une session SSH root sur `pve01` ouverte et `pve-firewall compile` pour relire avant d'activer. Retour arrière : `pve-firewall stop` depuis la console de l'hôte (pas depuis une session réseau).

**Travail demandé**
1. **Le runner.** Installe Packer sur `runner01` (clé HashiCorp vérifiée par son empreinte), approuve l'autorité de `pve01` dans son magasin système, et vérifie depuis `runner01`, sans `-k`, que l'API répond. Le plugin s'installe au premier `packer init` d'un job : où, pour quel utilisateur ?
2. **Les flux.** Ouvre les trois flux sur `gw01`, l'IPSet et la règle sur `pve01`, et reporte-les dans `docs/socle/matrice-flux.md`. Teste chaque flux depuis la bonne extrémité.
3. **Les secrets.** Crée les quatre variables CI. Explique dans la description de ta MR pourquoi un pipeline de MR n'y a pas accès, et comment le job de validation fonctionne quand même.
4. **Le pipeline.** Écris le `.gitlab-ci.yml` : étapes, règles par source de pipeline (MR, branche par défaut, planification), jobs manuels, transmission du VMID construit aux jobs suivants, rapport JUnit du test, artefacts de build conservés pour l'audit, un seul build à la fois sur `pve01` **quel que soit le pipeline** (`resource_group`), et un build qui n'est jamais interrompu par un pipeline plus récent. Une image qui échoue à ses tests ne doit pas pouvoir être prise pour une version utilisable.
5. **La planification.** Crée un pipeline planifié hebdomadaire sur `main` (heure creuse, fuseau Europe/Paris). Note qui en est propriétaire, avec quels droits il tourne, et ce qui arrive s'il quitte l'équipe.
6. **La preuve.** Lance un build manuel, puis observe une exécution planifiée (ou déclenche la planification avec *Run pipeline schedule*). Pendant un build, lance un second pipeline : décris ce que montre GitLab.
7. Mets à jour le registre des secrets (variables CI) et la matrice des flux ; fusionne.

**Critères de réussite**
- [ ] `runner01` construit : Packer 1.16, plugin, TLS vérifié, flux ouverts et documentés.
- [ ] Le pipeline de `main` construit, teste et publie une image Debian ; le rapport JUnit est visible dans l'onglet *Tests*.
- [ ] Un pipeline planifié hebdomadaire est actif sur `main`.
- [ ] Deux pipelines simultanés ne construisent jamais en même temps (« Waiting for resource » observé et noté).
- [ ] Aucun secret dans le dépôt ni dans les journaux de jobs ; `PKR_VAR_proxmox_token` est protégée et masquée.

**Vérification** : `lab/bin/check 03 15`

<details><summary>Indice 1</summary>

Dans un pipeline de MR, les variables protégées ne sont pas injectées (la branche source n'est pas protégée). `packer validate` a besoin d'une valeur pour chaque variable sans défaut, et applique les blocs `validation` : donne-lui des valeurs **factices de la bonne forme** au niveau du job. Les variables du projet ont priorité sur celles du fichier `.gitlab-ci.yml` : sur `main`, les vraies l'emportent.
</details>

<details><summary>Indice 2</summary>

Le build connaît son VMID avant même de lancer Packer (`outils/version-image.sh`). Un fichier `build.env` déclaré en `artifacts:reports:dotenv` le transmet aux jobs qui ont le build dans leurs `needs`. Et `when:` ne se met pas au niveau d'un job qui a des `rules` : il se met dans la règle.
</details>

<details><summary>Indice 3</summary>

`resource_group` limite à un job à la fois, **tous pipelines et branches confondus**, les jobs qui portent le même nom de groupe. `interruptible: false` protège un job de l'annulation automatique des pipelines redondants. Pour une image rejetée, une étiquette posée par un job `on_failure` suffit à la distinguer.
</details>

**Pour aller plus loin** : envoie le résultat du pipeline planifié dans le canal de l'équipe (intégration GitLab ou webhook), et alerte quand **aucun** pipeline planifié n'a réussi depuis 8 jours (préparation du module 21).

---

### M03-E16 — Cycle de vie : rotation et retrait des images  `LAB` `★★`

> **Ticket PLAT-458** — *De : Nadia Roussel* — *Copie : Claire Morel*
> Avec une image par semaine et par famille, `local-nvme` va se remplir de templates dont personne ne se sert. Il faut une règle de rétention automatique. Et j'ai besoin d'une procédure d'astreinte pour **retirer** une image en urgence (vulnérabilité, image cassée) sans casser les VMs qui en dépendent.

**Objectifs pédagogiques**
- Définir et outiller une politique de rétention (versions récentes, version publiée, retour arrière possible).
- Comprendre ce qu'est un clone lié selon le type de stockage, comment le détecter par l'API, et quand l'API ne suffit pas.
- Écrire un outil destructeur sûr : simulation par défaut, garde-fous, codes de retour, refus explicites.
- Rédiger le runbook de retrait d'urgence.

**Prérequis** : M03-E10, M03-E15 ; M00-E11 (clones liés et complets).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Règle de rétention : par famille, les **3 versions les plus récentes non rejetées**, plus la version `current` (où qu'elle soit), plus la plus récente version `rejete` (analyse). Plages : Debian 9010-9029, Rocky 9030-9049.
- Outil attendu : `outils/rotation-images.sh`, accès par `outils/pve.sh` (jeton `wb-packer`). Simulation par défaut ; suppression seulement avec une option explicite ; mode « retrait d'une version précise ».
- Refus obligatoires : supprimer la version `current` ; supprimer un template dont des clones liés sont détectés ; tout VMID hors des plages des images dorées.
- Runbook : `docs/socle/runbooks/RB-037-retrait-image.md` dans `plateforme/medisphere`.

**Travail demandé**
1. **Comprendre le lien.** Crée un clone lié de la version la plus ancienne (VMID 2033, nom `m03-lien`), puis compare, en root sur `pve01`, `qm config 2033`, `pvesm list local-nvme` et (selon ton stockage) `lvs -o lv_name,origin` ou `zfs list -o name,origin`. Où est inscrit le lien entre le clone et son template ? Est-il visible par l'API (`GET /nodes/<NOEUD>/qemu/2033/config`, `GET …/storage/local-nvme/content`) ? Note tes observations : elles décident de la méthode de détection.
2. **L'outil.** Écris `outils/rotation-images.sh` : tri des versions par date **puis** par numéro, calcul de ce qui est gardé, simulation, suppression par l'API avec attente de la tâche, refus motivés, code 3 si au moins un refus.
3. **La détection des clones liés.** Implémente la détection par l'API pour les stockages où elle est possible, et décide (en le justifiant dans l'en-tête du script et dans le runbook) ce que fait l'outil quand le stockage ne laisse aucune trace dans l'API.
4. **Les essais.** Avec la VM 2033 en place, lance l'outil en mode retrait sur la version la plus ancienne : selon ton stockage, il doit refuser, ou expliquer pourquoi il ne peut pas savoir. Essaie aussi de retirer la version `current` : refus. Détruis 2033, puis applique la rotation.
5. **En CI.** Ajoute la rotation au job de publication (après la pose de `current`).
6. **Le runbook.** Rédige RB-037 : rotation en échec, retrait d'urgence de la version `current` (republier la précédente d'abord), communication, VMs déjà créées depuis l'image retirée.

> ⚠️ **Attention** : une suppression de template est définitive (pas de corbeille, et les sauvegardes PBS du pool `lab` ne couvrent un template que s'il était présent lors de la dernière sauvegarde). Lance toujours la simulation d'abord, et lis la liste.

**Critères de réussite**
- [ ] `outils/rotation-images.sh` est sur `main` (ShellCheck propre, `--help`), appelé par le job de publication.
- [ ] Le catalogue Debian respecte la règle de rétention, avec une seule version `current`.
- [ ] Ton journal montre les refus (clone lié ou impossibilité de savoir, version `current`) et la rotation appliquée.
- [ ] RB-037 est fusionné dans `plateforme/medisphere`.

**Vérification** : `lab/bin/check 03 16`

<details><summary>Indice 1</summary>

Trier `deb13-gold-20261009-2` et `deb13-gold-20261009-10` comme des chaînes donne le mauvais ordre. Découpe le nom en `[date, numéro]` et trie le numéro comme un nombre (`jq` : `sort_by`, `tonumber`).
</details>

<details><summary>Indice 2</summary>

Sur la plupart des stockages, le volume d'un clone lié s'écrit `stockage:base-<TEMPLATE>-disk-N/vm-<ID>-disk-M` dans la configuration du clone. Ce n'est pas vrai partout : regarde ce que montre ton étape 1. La méthode de clonage de chaque plugin de stockage est lisible dans le code de `pve-storage` (`clone_image`).
</details>

**Pour aller plus loin** : ajoute une rotation des templates d'essai (9090-9099 de plus de 7 jours) et une alerte quand `local-nvme` dépasse 80 %.

---

### M03-E17 — ADR : stratégie d'images de MédiSphère  `RED` `★★`

> **Ticket PLAT-460** — *De : Claire Morel*
> Avant qu'Ansible et OpenTofu ne s'appuient sur les images, je veux la décision écrite : qu'est-ce qu'on met dans une image et qu'est-ce qu'on laisse au démarrage, combien d'images on maintient, à quel rythme, comment on les consomme et comment on les retire. Format ADR habituel, à faire relire par Karim et Sophie.

**Objectifs pédagogiques**
- Arbitrer entre image complète, image minimale et image dorée commune, avec des critères explicites (preuve, délai de correctif, temps de mise à disposition, coût, dérive).
- Fixer un contrat pour les consommateurs (sélection, type de clone, ce qu'ils ont le droit d'attendre).
- Assumer les conséquences négatives et les risques d'une décision.

**Prérequis** : M03-E01 à M03-E16 ; ADR-0010 et ADR-0020 (format).
**Durée indicative** : 2 h.

**Travail demandé**

Rédige `docs/socle/adr/ADR-0030-strategie-images.md` dans `plateforme/medisphere` (MR relue) avec : contexte, facteurs de décision, au moins trois options (dont une image par rôle et une image du fournisseur configurée au démarrage), décision, conséquences positives et négatives, risques suivis. La décision doit au minimum trancher : contenu d'une image et ce qui n'y entre jamais ; familles d'OS et règle pour en ajouter une ; rythme de reconstruction (base, dorée) ; versionnage et publication ; règles de consommation (sélection par étiquettes, clone complet ou lié, que faire d'une VM existante quand l'image change) ; rétention et retrait ; outil de construction (et sa licence).

**Critères de réussite**
- [ ] L'ADR est fusionné, au format des ADR précédents, avec au moins trois options comparées.
- [ ] Chaque point de la liste ci-dessus est tranché, et les choix des exercices E09 à E16 y sont justifiés (ou corrigés).
- [ ] Les conséquences négatives et les risques sont nommés, avec leur traitement.

<details><summary>Indice 1</summary>

Pars du délai entre la publication d'un correctif de sécurité et sa présence dans une VM neuve, puis dans une VM existante : chaque option donne une réponse différente, et c'est souvent elle qui départage.
</details>

<details><summary>Indice 2</summary>

Ton E16 a montré qu'un clone lié durable rend une image impossible à retirer (ou invisible). C'est une règle de consommation, donc une décision d'architecture, pas un détail d'outil.
</details>

**Pour aller plus loin** : ajoute une section « Revoir cette décision si… » (seuils qui rendraient l'option 1 ou un autre outil préférable).

---

### M03-E18 — Questions de production : images et chaîne de confiance  `Q` `★★`

> **Ticket SEC-463** — *De : Sophie Laurent*
> L'auditeur HDS revient dans un mois. Voici les questions qu'il m'a posées la dernière fois sur la « chaîne d'approvisionnement » de nos systèmes. Réponds par écrit, en argumentant ; pour les QCM, dis aussi pourquoi les autres réponses sont fausses.

**Objectifs pédagogiques**
- Raisonner en chaîne de confiance : de la source (ISO, dépôts, outils) à la VM en production.
- Identifier les fuites d'information et les identités partagées propres aux images.
- Préparer les réponses à un audit avec des preuves, pas des intentions.

**Prérequis** : paliers 1 à 3 du module.
**Durée indicative** : 2 h.

**Questions**

1. Décris la chaîne de confiance de l'ISO Debian que tu utilises, de la clé de signature jusqu'au fichier sur `hdd-bulk`. Quel maillon te protège d'un miroir compromis ? Lequel d'un attaquant qui contrôlerait aussi le site web où tu as lu l'empreinte de la clé ?
2. QCM — Le bloc `required_plugins` déclare `version = "~> 1.2.4"`. Que garantit `packer init` ?
   a) la version exacte 1.2.4, vérifiée par signature ; b) la plus récente version 1.2.x ≥ 1.2.4 disponible, dont l'archive est contrôlée par la somme publiée avec la version ; c) n'importe quelle version 1.x ; d) rien : le plugin est téléchargé sans vérification.
3. Pourquoi fige-t-on la version d'un plugin dans le code plutôt que de prendre la dernière ? Quelle est la contrepartie, et quel mécanisme la compense (indique où il vit dans la plateforme) ?
4. Cite quatre endroits où un secret ou une donnée personnelle peut se retrouver **dans une image** à l'issue d'un build, alors qu'aucun fichier du dépôt n'en contient.
5. Le journal de cloud-init (`/var/log/cloud-init.log`) et `/run/cloud-init/instance-data.json` d'une VM contiennent-ils les données utilisateur (*user-data*) ? Que se passerait-il si un mot de passe y était passé (`cipassword`) ? Quelle règle en tires-tu ?
6. QCM — Deux clones d'une image dont le `machine-id` n'a pas été réinitialisé démarrent sur le VLAN 99. Que se passe-t-il le plus probablement ?
   a) rien de visible : le `machine-id` ne sert qu'aux journaux ; b) ils reçoivent la même adresse IPv4, car `systemd-networkd` dérive l'identifiant DHCP du `machine-id` ; c) le second ne démarre pas ; d) cloud-init régénère le `machine-id` puisque l'identifiant d'instance a changé.
7. Pourquoi une image est-elle reconstruite **chaque semaine** alors que `unattended-upgrades` applique déjà les correctifs de sécurité dans les VMs ? Donne deux raisons indépendantes.
8. Une version `current` est publiée le lundi ; mardi, OpenTofu crée une VM ; mercredi, une nouvelle version est publiée. Que doit indiquer l'état d'OpenTofu (ou l'inventaire) pour la VM de mardi, et pourquoi la seule étiquette `current` n'y suffit-elle pas ?
9. QCM — Le pipeline de construction utilise `resource_group: packer-pve01`. Que se passe-t-il si un build planifié et un build manuel sont déclenchés à une minute d'intervalle ?
   a) le second échoue immédiatement ; b) le second attend que le premier se termine, puis s'exécute ; c) les deux tournent, GitLab ne sérialise que les déploiements avec environnement ; d) le second annule le premier.
10. Un pipeline de MR n'a pas accès aux variables protégées. Explique pourquoi c'est une protection contre un contributeur malveillant, et ce qu'il pourrait faire sans elle avec le jeton `wb-packer`.
11. Le jeton `wb-packer` peut-il, avec ses droits actuels, supprimer `gw01` ? Lire la configuration de `pbs-par2` ? Démarrer une VM du pool `lab` sur un autre VNet que `vsandbox` ? Justifie chaque réponse par les ACL de E02.
12. Que prouvent les notes d'un template ? Que ne prouvent-elles pas (qui peut les modifier) ? Comment rendre le manifeste d'une image infalsifiable par l'équipe elle-même ?
13. Packer est sous licence BUSL 1.1. MédiSphère a-t-elle le droit de l'utiliser pour construire ses images ? Que se passerait-il si elle voulait proposer un service de construction d'images à ses clients ? Quel risque à long terme, et quelle option de repli ?
14. L'éditeur de facturation exige « Rocky Linux 10 à jour ». Comment prouves-tu à sa date de mise en service que la VM l'était, puis qu'elle le reste ?

**Critères de réussite**
- [ ] Les 14 questions ont une réponse écrite et argumentée ; les QCM indiquent la bonne réponse **et** pourquoi les autres sont fausses.
- [ ] Après correction, trois points faibles identifiés, avec un exercice ou une lecture pour chacun.

<details><summary>Indice 1</summary>

Pour les questions 1 à 3, relis comment tu as vérifié l'ISO (E05) et Packer (E02) : distingue **intégrité** (le fichier n'a pas changé) et **authenticité** (il vient bien de qui tu crois).
</details>

<details><summary>Indice 2</summary>

Pour la question 11, rappelle-toi que les droits effectifs d'un jeton à privilèges séparés sont l'intersection de ceux du jeton et de son utilisateur, et que le pool `lab` contient aussi le socle.
</details>

**Pour aller plus loin** : prépare pour Sophie un schéma d'une page de la chaîne d'approvisionnement des images, avec pour chaque maillon la preuve qu'on peut montrer à l'auditeur.
