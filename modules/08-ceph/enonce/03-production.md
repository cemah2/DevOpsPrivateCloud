# Module 08 — Palier 3 : Production

Le cluster `ceph-par1` tourne : trois nœuds, des OSD rangés par classe, du bloc, du fichier, de l'objet derrière une VIP, des clients aux droits minimaux, et un projet `plateforme/ceph` qui décrit le tout. Mais personne ne serait prévenu si un OSD tombait cette nuit, aucune donnée ne quitte le cluster (trois copies au même endroit ne sont pas une sauvegarde), la version 20.2.3 a des failles publiées, les échanges entre démons circulent en clair sur le réseau de stockage, et personne ne sait ce que le cluster encaisse vraiment. Claire Morel veut un stockage qu'on peut **exploiter** : surveillé, sauvegardé, mis à jour sans interruption, mesuré. Sophie Laurent veut le chiffrement de bout en bout, des clés renouvelées et des équipes qui ne voient que leurs propres données. Julien Petit, lui, attend son stockage. Ce palier fait passer Ceph en production.

> ⚠️ **Rappel** : `ceph-par1` porte déjà des données de test des paliers 1 et 2, et il sera consommé par OpenStack (M10) et Kubernetes (M16). Avant toute intervention qui redémarre des démons (mise à jour, changement de mode du messager, redéploiement d'OSD), vérifie `ceph -s` (HEALTH_OK, tous les PG `active+clean`), garde une session ouverte sur `ceph01` et note la commande de retour arrière. **Un seul nœud à la fois**, et jamais pendant une récupération. Les commandes destructives (`ceph osd purge`, `ceph orch device zap`, `ceph osd pool rm`) se vérifient deux fois (introduction du module).

**Chemin imposé** (introduction du module) : les spécifications cephadm vivent dans `plateforme/ceph` (MR, pipeline) ; la configuration des hôtes passe par un **rôle Ansible** de `plateforme/ansible` ; tout flux qui traverse les passerelles est déclaré dans `host_vars/gw01/pare_feu.yml` (même matrice pour `gw02`) ; tout nouveau secret (mot de passe du tableau de bord, clés cephx distribuées, clés de chiffrement des sauvegardes, jetons PBS) est en Vault (`critique`) et inscrit au **registre des secrets**. La documentation de stockage va dans `docs/stockage/` de `plateforme/medisphere` (`adr/`, `runbooks/`, `tests/`).

**Hôtes de ce palier** : `ceph01-03` (2081-2083), `cephcli01` (2085, client et poste de mesure), et `ceph04` (2084), toujours dans le cluster (baie A, conservé jusqu'au mini-projet) : il compte dans tout ce qui suit (4 nœuds, 12 OSD), et il est retiré en M08-E46. Aucune nouvelle VM. Les commandes `ceph` s'exécutent sur un hôte portant l'étiquette `_admin` (`ceph01`, variable `WB_CEPH_ADMIN` de `lab/lab.env`).

**Ordre conseillé** : E24 → E25 → E26 → E27 → E28 → E29 → E31 → E30 → E33 → E32 → E34. La sauvegarde (E25) précède la mise à jour (E26) ; la mise à jour précède la sécurisation des clés (E27), qui exige 20.2.4. **Durée totale indicative** : 28 à 34 h.

Les vérifications se lancent **depuis `adm01`** (`lab/bin/check 08 XX`).

---

### M08-E24 — Superviser Ceph  `LAB` `★★`

> **Ticket PLAT-950** — *De : Nadia Roussel*
> Pendant le palier 2, un OSD est resté arrêté deux jours sans que personne ne le remarque : on l'a vu en lisant `ceph -s` par hasard. Avec trois copies, ça ne se voyait pas. Avec deux OSD arrêtés sur deux nœuds différents, on aurait perdu l'écriture.
> Je veux être prévenue **avant** que ça devienne grave, comme pour les services socle : une sonde qui tourne seule, qui alerte, et qui dit en une ligne ce qui ne va pas. Et je veux pouvoir regarder le tableau de bord sans risquer de casser quoi que ce soit.

**Objectifs pédagogiques**
- Comprendre le modèle de santé de Ceph (états, contrôles nommés, sévérités, mise en sourdine) et ce qu'il ne dit pas.
- Exposer les métriques du cluster par le module `prometheus` du mgr et comprendre le comportement d'un mgr en attente.
- Écrire une sonde de service dans la lignée des `ms-verif-*`, testée, planifiée, branchée sur l'alerte.
- Mettre le tableau de bord en production : certificat de la PKI interne, compte personnel en lecture seule.

**Prérequis** : M08-E07 (lire l'état d'un cluster), M08-E11 (RGW, `outils/cert-ingress.sh`, provisioner `ceph-ingress`), M08-E23 (`outils/lib.sh`), M06-E27 (durées, renouvellement), M06-E29 (`ms-verif-services`, `ms-alerte@`), M02-E20 (`lib/ms-commun.sh`).
**Durée indicative** : 3 h 30.

**Contexte technique**
- Le cluster a été amorcé **sans** la pile de supervision de cephadm (`--skip-monitoring-stack`, introduction du module) : pas de Prometheus, Grafana ni Alertmanager dans le cluster. La plateforme d'observabilité arrive au module 21 ; d'ici là, la sonde tourne sur `adm01` comme `ms-verif-services`.
- Module `prometheus` du mgr : port **9283** (HTTP) sur chaque hôte portant un mgr ; seul le mgr **actif** sert des métriques. `adm01` (VLAN MGMT) joint le VLAN 30 sans règle supplémentaire.
- Sonde **`ms-verif-ceph`** dans `plateforme/outils` : script `bin/ms-verif-ceph`, configuration `etc/ms-verif-ceph.conf` installée sous `/usr/local/etc`, tests `tests/bats/ms-verif-ceph.bats`, unités `ms-verif-ceph.service` (utilisateur `admin`, `OnFailure=ms-alerte@%n.service`) et `ms-verif-ceph.timer` (toutes les 5 minutes, `Persistent=true`). Mêmes codes retour que `ms-verif-services` : 0 tout va bien, 1 anomalie **ou contrôle impossible**, 2 usage.
- Tableau de bord : `https://<hôte du mgr actif>:8443` (un mgr en attente redirige vers l'actif ; l'étiquette `mgr` est sur les trois nœuds, deux mgr tournent). Certificat de la PKI interne, valable pour **les trois** noms d'hôtes, émis et renouvelé **depuis `adm01`** sur le modèle de `outils/cert-ingress.sh` (M08-E11), par un provisioner JWK dédié `ceph-dashboard` limité à ces trois noms ; renouvellement à 15 jours de l'échéance (politique M06-E33). Comptes : `admin` (créé à l'amorçage, devient le compte de bris de glace) et `<MOI>` (ton identifiant, variable `WB_MOI` de `lab/lab.env`) avec le rôle `read-only`. Mots de passe en Vault, jamais sur une ligne de commande.

> ⚠️ **Attention** : (1) l'application du certificat du tableau de bord redémarre le module `dashboard` (quelques secondes sans interface, aucun effet sur les données) ; (2) une mise en sourdine (`ceph health mute`) sans durée cache un problème **pour toujours** : n'en pose aucune dans cet exercice sans `--ttl`… et sans ticket.

**Travail demandé**
1. **Lecture de la santé.** Sur `ceph01`, compare `ceph health`, `ceph health detail` et `ceph health detail --format json-pretty`. Dans la documentation (*Health checks*), relève les contrôles qui concernent les OSD, les PG, la capacité et les moniteurs, puis classe-les : lesquels exigent une action immédiate à 3 h du matin, lesquels peuvent attendre le matin ? Lis aussi ce que font `ceph health mute <CODE> <TTL>` et `--sticky`, et ce que deviennent les plantages de démons (`ceph crash ls`, `ceph crash info`, `ceph crash archive-all`) : un plantage ancien maintient `RECENT_CRASH` pendant deux semaines.
2. **Métriques.** Active le module `prometheus` du mgr, puis depuis `adm01` :
   ```
   admin@adm01:~$ for h in ceph01 ceph02 ceph03; do printf '%s ' "$h"; \
       curl -s -o /dev/null -w '%{http_code} %{size_download}\n' "http://$h.par1.medisphere.internal:9283/metrics"; done
   admin@adm01:~$ curl -s http://<HÔTE-MGR-ACTIF>.par1.medisphere.internal:9283/metrics | grep -E '^ceph_(health_status|health_detail|mon_quorum_status|osd_up|pg_active|pool_metadata)' | head -30
   ```
   `<HÔTE-MGR-ACTIF>` : l'hôte du mgr actif (`ceph mgr stat`). Que répond un hôte sans mgr ? un mgr en attente ? Lis l'option `standby_behaviour` du module et règle-la pour qu'une sonde distingue sans ambiguïté le mgr actif. Repère les métriques qui donnent : l'état global, chaque contrôle de santé actif, le quorum, l'état de chaque OSD, les PG actifs et propres, l'occupation de chaque pool (et son nom).
3. **La sonde.** Écris `ms-verif-ceph` sur le modèle de `ms-verif-services` (bibliothèque `ms-commun.sh`, configuration séparée, aucune valeur en dur dans le script). Elle doit au minimum signaler : aucun mgr actif trouvé (ou plusieurs) ; un état global différent de `HEALTH_OK`, **avec le nom** des contrôles actifs ; un quorum incomplet ; un OSD `down` ou `out` ; des PG qui ne sont pas `active+clean` ; un pool plein à plus d'un seuil (80 % par défaut) ; le point d'entrée S3 `https://rgw.par1.medisphere.internal` qui ne répond pas ; un certificat (RGW, tableau de bord) qui expire dans moins de 10 jours ou ne se vérifie pas contre la racine MédiSphère. Écris les tests `bats` (sans réseau, outils simulés) avec au moins un test « rouge » par contrôle.
4. **Planification.** Installe la sonde par `task install:systeme`, crée le service et le timer, et prouve la chaîne d'alerte : arrête **un** OSD (`ceph orch daemon stop osd.<N>`), attends le passage de la sonde, constate l'alerte de `ms-alerte` dans le journal, redémarre l'OSD et vérifie le retour au vert. Note le délai entre l'arrêt et l'alerte, et ce qui le détermine.
5. **Le tableau de bord.** Crée le provisioner `ceph-dashboard` (rôle `step_ca`, politique limitée aux trois noms), écris `outils/cert-dashboard.sh` dans `plateforme/ceph` (émission, renouvellement par le certificat lui-même, application au tableau de bord sans que la clé touche le disque des nœuds, contrôle du certificat présenté) et son timer quotidien sur `adm01`. Bascule le mgr actif (`ceph mgr fail`) : le nouveau mgr actif présente-t-il un certificat valide à son nom ? Crée le compte `<MOI>` en lecture seule, change le mot de passe d'`admin`, active la politique de mots de passe, et vérifie qu'avec `<MOI>` aucune action de modification n'est proposée.
6. **Astreinte.** Ajoute à `docs/astreinte.md` de `plateforme/outils` une section Ceph : lire le message de la sonde, les trois premières commandes à lancer, quand réveiller quelqu'un, quand attendre le matin (ta classification de l'étape 1).

**Critères de réussite**
- [ ] Le module `prometheus` est actif ; un seul hôte sert des métriques sur 9283, les mgr en attente répondent par une erreur HTTP.
- [ ] `ms-verif-ceph` est installé sous `/usr/local/bin` (nombre d'OSD attendu : celui du cluster actuel, 12 avec `ceph04`), sa configuration sous `/usr/local/etc` ; il rend 0 sur le cluster sain et 1 quand un OSD est arrêté ; une option inconnue donne 2.
- [ ] Le timer `ms-verif-ceph.timer` est actif et passe toutes les 5 minutes ; le service déclenche `ms-alerte@` en cas d'échec ; une alerte a été reçue pendant le test.
- [ ] Les tests `bats` de la sonde sont sur `main` de `plateforme/outils` et passent dans le pipeline.
- [ ] Chaque hôte qui porte un mgr présente sur 8443 un certificat émis par la PKI MédiSphère, valable 30 jours au plus, à son nom ; le renouvellement est planifié sur `adm01` ; le compte `<MOI>` existe avec le seul rôle `read-only`.
- [ ] Aucun plantage non acquitté (`ceph crash ls-new` vide) et aucune mise en sourdine sans durée.

**Vérification** : `lab/bin/check 08 24`

<details><summary>Indice 1</summary>

Le module `prometheus` tourne dans **chaque** mgr, mais un mgr en attente n'a pas de données de cluster à exposer. Avec le comportement par défaut, il répond quand même quelque chose : une sonde qui interroge « le premier hôte qui répond 200 » peut donc conclure à tort que tout va bien. Cherche l'option qui fait répondre un mgr en attente par un code d'erreur.
</details>

<details><summary>Indice 2</summary>

Les métriques par pool portent un identifiant (`pool_id`), pas un nom : une métrique dédiée associe identifiant et nom. L'occupation d'un pool se calcule à partir de ce qui est stocké et de ce qui reste disponible pour ce pool (deux métriques), comme le fait `ceph df`. Pour la santé, une métrique par contrôle actif (étiquette `name`) te donne les noms à afficher.
</details>

<details><summary>Indice 3</summary>

Le tableau de bord accepte un certificat global **ou** un certificat par instance de mgr (section *SSL/TLS Support* de sa documentation) ; un certificat global portant les trois noms suit le mgr actif où qu'il soit. Les sous-commandes `ceph dashboard set-ssl-certificate` et `set-ssl-certificate-key` lisent un fichier (`-i`), et `-i -` lit l'entrée standard : la fonction d'accès de `outils/lib.sh` la transmet à travers ssh. Pour les mots de passe, `ac-user-create` et `ac-user-set-password` lisent aussi le secret dans un fichier.
</details>

**Pour aller plus loin** (facultatif) : le service `ceph-exporter` de cephadm (compteurs de performance par démon) ; le service `mgmt-gateway` (point d'entrée unique et TLS pour le tableau de bord et la supervision) ; l'historique des contrôles (`ceph healthcheck history ls`) ; [Health checks](https://docs.ceph.com/en/tentacle/rados/operations/health-checks/), [module Prometheus](https://docs.ceph.com/en/tentacle/mgr/prometheus/), [tableau de bord](https://docs.ceph.com/en/tentacle/mgr/dashboard/), [module crash](https://docs.ceph.com/en/tentacle/mgr/crash/).

---

### M08-E25 — Sauvegarder hors du cluster  `LAB` `★★★`

> **Ticket PLAT-951** — *De : Claire Morel*
> L'auditeur HDS a posé la question simple : « si quelqu'un supprime un volume par erreur, ou si le cluster entier est perdu, que récupérez-vous, et en combien de temps ? ». Trois copies dans le même cluster, c'est de la **disponibilité**, pas une sauvegarde : une suppression se réplique en quelques millisecondes.
> Je veux les volumes RBD qui comptent sauvegardés hors du cluster, à PAR2, chiffrés, de façon incrémentale, et la configuration du cluster sauvegardée de quoi le reconstruire. Et je veux une restauration **faite**, pas promise.

**Objectifs pédagogiques**
- Distinguer haute disponibilité, réplication et sauvegarde ; fixer un RPO et un RTO.
- Comprendre les instantanés RBD et les exports incrémentaux (`rbd export-diff` / `rbd import-diff`), leur chaîne et leurs points de rupture.
- Envoyer ces exports vers PBS, chiffrés côté client, avec un jeton limité à un espace de noms.
- Sauvegarder la configuration du cluster sans exposer plus de secrets que nécessaire, et prouver la restauration.

**Prérequis** : M08-E06 (instantanés RBD), M08-E13 (cephx), M08-E23 (`plateforme/ceph`), M06-E28 (rôle `sauvegarde_pbs`, jetons PBS par hôte, chiffrement côté client), M00-E22 (PBS).
**Durée indicative** : 4 h.

**Contexte technique**
- Hôte de sauvegarde : **`cephcli01`** (10.10.30.20, Debian 13). Il porte déjà un client Ceph (E06). Les exports partent vers **`pbs01`** (10.20.10.10:8007, à travers les passerelles et le tunnel `wg0`), datastore `ds-lab`, espace de noms **`par1/ceph`**, jeton `wb-backup@pbs!cephcli01` limité à cet espace (rôle `DatastoreBackup`). Clé de chiffrement côté client propre à cet hôte (Vault `critique`, copie *paperkey* hors ligne).
- Images à sauvegarder : une liste explicite dans la configuration (au minimum les images de test de `rbd-test` créées en E06 ; les volumes des équipes s'y ajouteront en E31). Identité cephx dédiée **`client.sauvegarde`**, limitée aux pools concernés.
- Configuration du cluster : produite sur `ceph01` (seul hôte qui doit détenir la clé `client.admin`), récupérée par `cephcli01` au moyen d'une clé SSH **à commande forcée** (compte `wb-sauvegarde` sur `ceph01`). Contenu attendu : ce qui permet de **reconstruire** (configuration centrale, spécifications des services, carte CRUSH, pools, systèmes de fichiers, configuration RGW, identités et droits cephx) ; **pas** le magasin `config-key` des moniteurs (secrets de chiffrement des OSD, clé SSH de l'orchestrateur : voir E27).
- Horaires : `git01` 01:15, services socle 01:55-02:05, `lab-nuit` 02:30 ; la sauvegarde Ceph passe à **01:30**. Rétention côté PBS : la tâche de purge de `par1` (M00) s'applique.
- RPO visé : 24 h pour les volumes, 24 h pour la configuration ; RTO à **mesurer**.

> ⚠️ **Attention** : (1) un export complet lit toute l'image : lance le premier en dehors d'un test de performance et surveille `ceph -s` ; (2) l'espace de travail sur `cephcli01` contient des données en clair le temps de l'envoi : dossier `root` 700, nettoyé en sortie quoi qu'il arrive ; (3) la restauration de test se fait dans une **nouvelle** image (`rbd-test/restau-…`), jamais par-dessus l'originale ; (4) une règle d'entrée est nécessaire sur `pbs01` lui-même (PBS filtre ses entrées, M00-E21) : modifie-la par le même chemin qu'en M06-E28.

**Travail demandé**
1. **Lecture.** Dans la documentation RBD (*Snapshots*, et la page de manuel de `rbd` pour `export-diff`, `import-diff`, `diff`), réponds dans ton journal : que contient un fichier produit par `export-diff` sans `--from-snap` ? avec ? Que se passe-t-il si l'instantané de départ a été supprimé sur le cluster ? Pourquoi un instantané RBD seul n'est-il pas cohérent pour un système de fichiers monté et actif, et que fait `rbd snap create` (ou `fsfreeze`) pour l'aider ? Relève aussi le comportement de `rbd export` sur les zones jamais écrites.
2. **Conception.** Décide et écris (dans `docs/stockage/sauvegarde.md` de `plateforme/medisphere`) : le nommage des instantanés de sauvegarde, la fréquence des exports complets et incrémentaux, combien d'instantanés restent sur le cluster et pourquoi, comment une restauration à J-3 se reconstitue, et ce qui se passe quand la chaîne est rompue. Compare avec une autre approche : export complet quotidien vers PBS, dont la déduplication ne stocke que les blocs changés.
3. **Identités et flux.** Crée `client.sauvegarde` (droits minimaux pour lire et créer/supprimer **des instantanés** sur les pools listés), l'espace de noms `par1/ceph` et le jeton PBS dédié (script de M06-E28 étendu), la clé de chiffrement, la règle de `pare_feu.yml` (`cephcli01` → `pbs01`, 8007) et la règle d'entrée de `pbs01`. Inscris chaque secret au registre.
4. **Configuration du cluster.** Sur `ceph01`, un script d'export (lecture seule) écrit sur sa sortie standard une archive de la configuration ; le compte `wb-sauvegarde` ne peut **rien d'autre** que le lancer (clé à commande forcée, `restrict`, une seule entrée `sudo`). Vérifie depuis `cephcli01` qu'une autre commande est refusée.
5. **Le rôle et le script.** Un rôle Ansible pour `cephcli01` (client PBS, secrets, configuration, script, unités systemd avec `OnFailure=ms-alerte@%n.service`) et un rôle (ou des tâches) pour `ceph01` (compte, clé autorisée, `sudoers`, script d'export). Le script de sauvegarde : instantané du jour, export incrémental depuis l'instantané précédent (complet le dimanche ou si la base manque), export de la configuration, envoi vers PBS (une archive par nature de données), suppression des instantanés devenus inutiles **seulement après** un envoi réussi, code retour non nul au moindre échec.
6. **Restauration.** Sur une image de test, écris des données témoins (somme de contrôle connue), laisse passer au moins un complet et deux incrémentaux (ou force-les en relançant le service avec des dates simulées), puis restaure **l'état de J-1** dans `rbd-test/restau-<image>` depuis PBS : catalogue, téléchargement, `import-diff` dans l'ordre. Compare les sommes de contrôle de l'image restaurée et de l'instantané d'origine. Restaure aussi l'archive de configuration et compare les spécifications avec celles de `plateforme/ceph`. Chronomètre chaque étape et consigne le tout en tête de `docs/stockage/tests/restauration-ceph.md` (RTO mesuré, RPO). Supprime l'image restaurée.

**Critères de réussite**
- [ ] Sur `cephcli01`, le timer de sauvegarde est actif (01:30), son dernier passage a réussi, ses secrets PBS sont `root:root` en 600.
- [ ] `pbs01` contient dans `par1/ceph` une sauvegarde des volumes et une sauvegarde de la configuration de moins de 48 h, chiffrées.
- [ ] `client.sauvegarde` n'a pas de droit d'administration (pas de `allow *` côté moniteur ni OSD) ; le compte `wb-sauvegarde` de `ceph01` n'exécute que le script d'export.
- [ ] L'archive de configuration ne contient pas le magasin `config-key`.
- [ ] Une restauration de J-1 a été faite, sommes de contrôle identiques, RTO consigné dans `docs/stockage/tests/restauration-ceph.md` ; l'image restaurée n'existe plus.

**Vérification** : `lab/bin/check 08 25`

<details><summary>Indice 1</summary>

Une chaîne d'incrémentaux n'est restaurable que si **chaque** maillon l'est : un incrémental `B→C` ne s'applique que sur une image qui est exactement à l'état `B`, et `import-diff` crée sur l'image cible l'instantané de fin, ce qui permet d'enchaîner. Pense à la rétention de PBS : si le complet est purgé avant ses incrémentaux, ces derniers ne servent plus à rien.
</details>

<details><summary>Indice 2</summary>

Les profils cephx `rbd` et `rbd-read-only` s'appliquent par pool (`profile rbd pool=…`). Créer et supprimer un instantané est une écriture sur l'en-tête de l'image : un profil en lecture seule ne suffit pas. Pour la clé SSH, regarde `command=` et `restrict` dans `man authorized_keys` ; la commande forcée ignore ce que le client demande (`SSH_ORIGINAL_COMMAND`).
</details>

<details><summary>Indice 3</summary>

`proxmox-backup-client` sauvegarde des **dossiers** (archive `.pxar`) ou des **images** (`.img`). Prépare les exports dans un dossier de travail, une archive par nature (`rbd.pxar`, `config.pxar`) et un identifiant de sauvegarde explicite (`--backup-id`) ; `catalog dump`, `restore` et `--keyfile` servent à la restauration. `rbd export <image>@<instantané> - | sha256sum` donne la somme d'un état précis.
</details>

**Pour aller plus loin** (facultatif) : `rbd-mirror` en mode instantané vers un cluster PAR2 (réplication asynchrone, ce n'est toujours pas une sauvegarde) ; sauvegarde des compartiments S3 par `rclone` vers `s3-01` ou PBS ; instantanés de sous-volumes CephFS (`ceph fs subvolume snapshot create`) ; [instantanés RBD](https://docs.ceph.com/en/tentacle/rbd/rbd-snapshot/), [`rbd`(8)](https://docs.ceph.com/en/tentacle/man/8/rbd/), [client PBS](https://pbs.proxmox.com/docs/backup-client.html).

---

### M08-E26 — Mettre à jour Ceph sans interruption  `LAB` `★★★`

> **Ticket CHG-952** — *De : Claire Morel* — *Copie : Sophie Laurent*
> Ceph a publié la 20.2.4 le 19 août : quatre CVE, dont un contournement de l'authentification cephx et une élévation de privilèges par les URL S3 présignées. Sophie veut la mise à jour dans la semaine.
> Contrainte : MédiDoc et les tests de Julien écrivent en continu. Je veux une mise à jour **sans interruption de service**, préparée, avec un plan de retour arrière, et un runbook réutilisable pour la prochaine.

**Objectifs pédagogiques**
- Lire des notes de version et des avis de sécurité, et en extraire les étapes particulières.
- Comprendre l'orchestration d'une mise à jour par cephadm : ordre des démons, contrôles `ok-to-stop`, mise à jour échelonnée.
- Prouver l'absence d'interruption par une charge cliente continue et mesurée.
- Écrire RB-082 « mettre à jour Ceph ».

**Prérequis** : M08-E03 (cephadm), M08-E11 (RGW et ingress), M08-E23 (`plateforme/ceph`), M08-E24 (supervision), M08-E25 (sauvegarde réussie de moins de 24 h).
**Durée indicative** : 3 h.

**Contexte technique**
- Version actuelle : 20.2.3 (`quay.io/ceph/ceph:v20.2.3`) ; cible : **`quay.io/ceph/ceph:v20.2.4`**. Les nœuds tirent l'image depuis `quay.io` (sortie Internet du lab).
- Avis à lire **avant** de commencer : notes de version de 20.2.4 ([Tentacle](https://docs.ceph.com/en/latest/releases/tentacle/)) et les quatre avis liés (CVE-2025-30156, CVE-2026-39944, CVE-2026-50152, CVE-2026-54330), dont deux comportent des « étapes critiques ».
- Les paquets `cephadm` et `ceph-common` des nœuds sont épinglés par le rôle `ceph_noeud` (E02, variable `ceph_noeud_version`, dépôt `download.ceph.com/rpm-<version>`) : ils suivent la version du cluster **après** la mise à jour. Le client de `cephcli01` est celui choisi en E06 : note sa version.
- Charges de test pendant la mise à jour, depuis `cephcli01` : une écriture continue sur un RBD monté (une ligne horodatée par seconde, `fsync`), une boucle S3 (dépôt puis relecture d'un petit objet toutes les secondes, par le point d'entrée `https://rgw.par1.medisphere.internal`), et une boucle d'écriture sur le montage CephFS. Chaque boucle journalise les échecs et les latences supérieures à 2 s.
- La version de référence est dans le code : `ceph_image` et `ceph_noeud_version` (`group_vars/env_m08/ceph.yml` de `plateforme/ansible`, E02-E03), et le `README` de `plateforme/ceph`. La mise à jour est une MR.

> ⚠️ **Attention** : (1) vérifie **avant** : HEALTH_OK, deux mgr (un actif, un en attente), sauvegarde E25 de moins de 24 h, tous les hôtes joignables par cephadm (`ceph orch host ls`) ; (2) une mise à jour **ne se défait pas** par un retour à 20.2.3 une fois les moniteurs passés : le retour arrière, c'est la mise en pause, l'analyse, puis la reprise ; écris-le comme tel ; (3) n'interviens sur aucun démon à la main pendant que l'orchestrateur travaille.

**Travail demandé**
1. **Lecture.** Résume dans le ticket, pour chacune des quatre CVE : composant touché, condition d'exploitation, ce qui est corrigé par le seul passage en 20.2.4, et ce qui demande une **action supplémentaire** (avant, pendant ou après). Pour CVE-2026-54330, dis si l'étape préalable s'applique au cluster de MédiSphère et pourquoi. Pour CVE-2025-30156, lis la section *Upgrading and Rotating CephX Keys* de la documentation d'authentification : quelles étapes cephadm fait-il pour toi, lesquelles restent à ta charge (elles seront traitées en E27), et quels nouveaux contrôles de santé vas-tu voir apparaître ?
2. **Préparation.** Lis la page *Upgrading Ceph* de cephadm. Prépare le changement : liste des vérifications, commande qui contrôle que l'image cible est récupérable par tous les hôtes **sans rien démarrer**, gel de l'*autoscaler* PG pendant l'opération, comportement attendu de CephFS et de RGW. Ouvre la MR qui porte la nouvelle version (pipeline vert, pas encore fusionnée : elle le sera **après** la mise à jour, quand le code décrira la réalité).
3. **Charge témoin.** Lance les trois boucles sur `cephcli01` et laisse-les tourner 10 minutes **avant** : c'est ta ligne de base (latences normales, aucun échec).
4. **Mise à jour.** Lance la mise à jour vers `quay.io/ceph/ceph:v20.2.4`, d'abord limitée aux mgr (mise à jour échelonnée), vérifie, puis le reste. Suis-la (`ceph orch upgrade status`, `ceph -W cephadm`, `ceph -s`) et note l'ordre des démons, la durée de chaque étape, les contrôles de santé apparus et disparus. Mets-la en pause une fois au milieu des OSD, observe, reprends.
5. **Après.** Vérifie `ceph versions` et `ceph orch ps` (tous les démons en 20.2.4), réactive l'*autoscaler*, fusionne la MR et applique le rôle `ceph_noeud` (paquets `cephadm` et `ceph-common` en 20.2.4), relève l'état de la santé (contrôles `AUTH_INSECURE_*` attendus : ne les traite pas ici, ouvre le ticket SEC pour E27). Arrête les boucles et analyse leurs journaux : nombre d'échecs, latence maximale, à quel moment.
6. **Runbook.** Rédige `docs/stockage/runbooks/RB-082-mettre-a-jour-ceph.md` : préalables, lecture des avis, contrôle de l'image, ordre et échelonnement, suivi, pause et reprise, que faire si un démon ne redémarre pas, après la mise à jour (paquets des nœuds, clients, santé), et ce que la mise à jour **suivante** devra vérifier en plus (passage à une version majeure, clients).

**Critères de réussite**
- [ ] Tous les démons du cluster sont en 20.2.4 ; aucune mise à jour en cours ; l'*autoscaler* est de nouveau actif sur tous les pools.
- [ ] La commande `cephadm` des trois hôtes est en 20.2.4 (paquet épinglé par le rôle `ceph_noeud`).
- [ ] Le cluster n'a pas d'autre contrôle de santé actif que ceux de la famille `AUTH_INSECURE_*` (traités en E27).
- [ ] Les journaux des trois boucles montrent zéro échec d'écriture (des latences élevées pendant les bascules sont admises et commentées).
- [ ] Le code décrit la nouvelle version (`ceph_image`, `ceph_noeud_version`) sur `main` ; RB-082 est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 08 26`

<details><summary>Indice 1</summary>

L'orchestrateur met à jour d'abord les mgr (le mgr actif bascule vers un mgr déjà à jour, d'où l'exigence d'un mgr en attente), puis les moniteurs, puis les autres démons dans un ordre fixe. Pour chaque OSD, il demande au cluster si l'arrêt est sans danger avant de redémarrer. La mise à jour échelonnée accepte des filtres (types de démons, hôtes, services, nombre maximal) mais n'autorise pas à sauter un type dans l'ordre.
</details>

<details><summary>Indice 2</summary>

Les sous-commandes de `ceph orch upgrade` permettent de vérifier une image, de démarrer, de suivre, de mettre en pause, de reprendre et d'arrêter. La documentation recommande un réglage global sur les pools pendant l'opération, pour éviter des fusions ou divisions de PG au milieu des redémarrages : il se pose et se retire par `ceph osd pool set|unset`.
</details>

<details><summary>Indice 3</summary>

Pour les boucles, un `while` avec `date +%s.%N` avant et après chaque opération suffit. Côté RBD, écris dans un fichier du système de fichiers monté avec `dd … oflag=dsync` (ou `sync` après chaque ligne) : sans synchronisation, le cache de page masque les blocages. Côté S3, reprends l'outil et le profil de E11/E12.
</details>

**Pour aller plus loin** (facultatif) : une mise à jour « à blanc » sur une copie du cluster (ceph04 seul en mono-nœud, ou une maquette jetable) ; les politiques de version des clients (`ceph osd set-require-min-compat-client`) ; [Upgrading Ceph (cephadm)](https://docs.ceph.com/en/tentacle/cephadm/upgrade/), [avis de sécurité](https://docs.ceph.com/en/latest/security/).

---

### M08-E27 — Sécuriser Ceph : chiffrement et clés  `LAB` `★★★`

> **Ticket SEC-953** — *De : Sophie Laurent*
> Trois constats après la 20.2.4. Un : les réplications entre OSD et les échanges avec les clients circulent **en clair** sur les VLAN 30 et 31. Deux : les disques des OSD ne sont pas chiffrés ; un disque retiré de la baie (ou un fichier `qcow2` copié) se lit tel quel. Trois : nos clés cephx sont du type que la CVE-2025-30156 permet de forger, la santé du cluster le dit, et la clé SSH de l'orchestrateur a pu être lue par n'importe quelle identité ayant `mon allow r` (CVE-2026-50152).
> Je veux le chiffrement en transit et au repos, des clés cephx du nouveau type partout où c'est possible, la clé SSH de l'orchestrateur renouvelée, et la liste écrite de ce qui ne peut pas encore l'être, avec une date.

**Objectifs pédagogiques**
- Configurer le mode `secure` du messager v2 (msgr2) et comprendre ce qu'il ne couvre pas (msgr1).
- Chiffrer les OSD au repos (dm-crypt/LUKS par cephadm), comprendre où sont les clés et redéployer les OSD sans perte de redondance.
- Renouveler les clés cephx vers le type `aes256k` en suivant la procédure officielle, sans se couper l'accès.
- Renouveler la clé SSH de l'orchestrateur sans interrompre l'orchestration.

**Prérequis** : M08-E26 (cluster en 20.2.4), M08-E13 (cephx), M08-E19 (retirer et remplacer un OSD), M08-E23 (spécifications versionnées), M08-E25 (sauvegarde récente).
**Durée indicative** : 4 h 30.

**Contexte technique**
- Messager : options `ms_cluster_mode`, `ms_service_mode`, `ms_client_mode` (et leurs variantes `ms_mon_*` pour les moniteurs) ; valeurs `crc` et `secure`, par ordre de préférence. Elles s'appliquent au **démarrage** des démons. Les clients noyau (krbd, CephFS) choisissent leur mode par l'option `ms_mode` de `rbd device map` / `mount`.
- Chiffrement au repos : champ `encrypted: true` de la spécification des OSD (`specs/osd.yaml` de `plateforme/ceph`). Il ne s'applique qu'aux OSD **créés** après le changement. Dans cet exercice, tu redéploies chiffrés les **trois OSD de `ceph03`**, un par un ; ceux de `ceph01` et `ceph02` le seront au mini-projet (même procédure), ceux de `ceph04` disparaissent avec lui.
- Clés cephx : procédure *Upgrading and Rotating CephX Keys* (lue en E26). cephadm traite les clés des démons ; les clés des **clients** (`client.admin`, celles de E13, `client.sauvegarde`, celles des équipes) sont à ta charge, et un client ne peut utiliser une clé `aes256k` que si **sa** bibliothèque ou son noyau la comprend.
- Clé SSH de l'orchestrateur : la paire est stockée dans le magasin `config-key` des moniteurs ; la clé publique est autorisée pour le compte **`cephadm`** de chaque nœud (amorçage avec `--ssh-user cephadm`, E03), posée par le rôle `ceph_noeud` (variable `ceph_noeud_cle_orchestrateur`, liste exclusive).

> ⚠️ **Attention** : (1) avant de renouveler `client.admin`, crée une identité de secours et **vérifie-la** : une erreur et plus aucune commande `ceph` ne passe ; garde la session ouverte jusqu'à la fin ; (2) n'interdis jamais un type de clé (`auth_allowed_ciphers`) tant qu'une clé de démon, d'administration ou d'un client en service l'utilise encore : la documentation décrit un réglage de secours, lis-le **avant** ; (3) le redéploiement d'un OSD efface son disque : un seul OSD à la fois, HEALTH_OK et tous les PG `active+clean` entre deux, sauvegarde E25 de moins de 24 h ; (4) le changement de mode du messager se fait démon par démon, en vérifiant le quorum et `ok-to-stop` à chaque étape.

**Travail demandé**
1. **État des lieux.** Relève : les modes actuels du messager (`ceph config get` et `ceph config show` sur un démon), les adresses v1/v2 des moniteurs (`ceph mon dump`), qui se connecte en v1 (`ss` sur le port 6789 des moniteurs) ; le type de chiffrement des OSD (`lsblk` sur un nœud, `ceph-volume … list` dans `cephadm shell`) ; les contrôles `AUTH_INSECURE_*` actifs, `auth_allowed_ciphers` et `auth_preferred_cipher` (`ceph mon dump`) ; la liste des identités (`ceph auth ls`) avec, pour chacune, **qui** l'utilise et avec quel client (version). Supprime les identités qui ne servent plus.
2. **Transit.** Passe le cluster en mode `secure` pour les échanges entre démons, pour ce que les démons acceptent et pour ce qu'ils initient. Redémarre les démons un par un (moniteurs, mgr, OSD, MDS, RGW) et vérifie à chaque étape. Remonte les clients de `cephcli01` avec `ms_mode=secure`. Écris dans ton journal ce que ces réglages **ne** protègent **pas** (connexions msgr1) et ta décision à ce sujet.
3. **Repos.** Ajoute `encrypted: true` aux spécifications des OSD (MR sur `plateforme/ceph`), puis redéploie les trois OSD de `ceph03` un par un en conservant leur identifiant. Vérifie que chacun est chiffré, puis retrouve **où** est stockée sa clé LUKS. Écris dans ton journal ce que ce chiffrement protège (disque ou image retirés, `qcow2` copié) et ce qu'il ne protège pas (hôte compromis, identité qui lit le magasin `config-key` : lien avec CVE-2026-50152).
4. **Clés cephx.** D'abord, pour chaque client recensé à l'étape 1, établis s'il **peut** utiliser une clé `aes256k` (bibliothèque Ceph de quelle version ? client noyau ?) : c'est ce qui décide de tout le reste. Puis suis la procédure officielle : vérifie que le nouveau type est accepté, décide s'il devient le type **préféré** (conséquence pour les clés créées ensuite, en E31 par exemple), vérifie que les clés des démons et des tickets de service ne sont plus signalées, renouvelle `client.admin` (client de l'hôte `_admin` à jour d'abord, identité de secours ensuite, suppression de celle-ci à la fin), puis chaque clé de client **dont le logiciel le permet**, en redistribuant la nouvelle clé (Vault, rôle Ansible). N'interdis la création ni l'usage de l'ancien type que si **tous** les clients peuvent suivre ; sinon, mets les contrôles correspondants en sourdine **avec une durée**, et ouvre un ticket daté.
5. **Clé SSH de l'orchestrateur.** Renouvelle-la sans fenêtre d'aveuglement : nouvelle paire générée hors du cluster, clé publique **ajoutée** pour le compte `cephadm` des trois nœuds par le rôle `ceph_noeud`, bascule de l'orchestrateur sur la nouvelle paire, contrôle de chaque hôte, puis retrait de l'ancienne clé publique. La clé privée temporaire est détruite.
6. **Trace.** Mets à jour le registre des secrets (clés cephx renouvelées, emplacement des clés LUKS, clé SSH de l'orchestrateur, date du prochain renouvellement) et ajoute au ticket la liste de ce qui reste : OSD de `ceph01` et `ceph02`, clients à l'ancien type de clé, connexions msgr1.

**Critères de réussite**
- [ ] `ms_cluster_mode`, `ms_service_mode` et `ms_client_mode` (et leurs équivalents `ms_mon_*`) valent `secure` dans la configuration centrale, et les démons en cours d'exécution les appliquent.
- [ ] La spécification des OSD porte `encrypted: true` ; les trois OSD de `ceph03` sont chiffrés (périphériques `crypt` sur l'hôte), le cluster est HEALTH_OK ou seulement en sourdine justifiée.
- [ ] Les contrôles `AUTH_INSECURE_SERVICE_KEY_TYPE` et `AUTH_INSECURE_SERVICE_TICKETS` ont disparu ; ceux qui concernent les clients (`AUTH_INSECURE_CLIENT_KEY_TYPE`, `AUTH_INSECURE_KEYS_CREATABLE`, `AUTH_INSECURE_KEYS_ALLOWED`) ont disparu ou sont en sourdine **avec une durée**, justifiée par un ticket ; l'identité de secours n'existe plus.
- [ ] La clé publique de l'orchestrateur est la **seule** clé autorisée du compte `cephadm` sur les trois nœuds, et c'est la clé courante ; `ceph orch host ls` ne signale aucun hôte en erreur.
- [ ] Le registre des secrets et le ticket listent ce qui reste à faire, avec des dates.

**Vérification** : `lab/bin/check 08 27`

<details><summary>Indice 1</summary>

Les moniteurs préfèrent déjà `secure` par défaut ; les autres démons préfèrent `crc`. « `crc secure` » signifie « je préfère crc mais j'accepte secure » : pour **exiger** le chiffrement, la valeur ne doit plus contenir `crc`. `ceph config show <démon> <option>` donne la valeur **en vigueur** dans le démon, qui ne change qu'au redémarrage.
</details>

<details><summary>Indice 2</summary>

Pour redéployer un OSD en gardant son identifiant (et donc sa place dans CRUSH), l'orchestrateur sait retirer un OSD « pour remplacement » en effaçant son disque ; si la spécification correspondante n'est pas `unmanaged`, il recrée l'OSD sur le disque libéré, avec la spécification **actuelle**. Les clés LUKS des OSD créés par cephadm vivent dans le magasin `config-key` : `ceph config-key ls` en montre les noms (sans les afficher, ne lance pas `get`).
</details>

<details><summary>Indice 3</summary>

Pour la clé SSH, la page *Host Management* de cephadm (section *SSH Configuration*) décrit les sous-commandes `ceph cephadm …` qui génèrent, importent (`-i` fichier) ou affichent la paire, et `ceph cephadm check-host`. Si tu fais générer la nouvelle paire par cephadm, il perd l'accès aux hôtes jusqu'à ce que la clé publique y soit : c'est la fenêtre à éviter.
</details>

**Pour aller plus loin** (facultatif) : chiffrement côté serveur de RGW (SSE-S3 / SSE-KMS, avec Vault au module 25) ; chiffrement des images RBD par le client (`rbd encryption format`, LUKS2) ; désactivation de msgr1 (`ms_bind_msgr1`) et ses conséquences pour les clients anciens ; [modes du messager](https://docs.ceph.com/en/tentacle/rados/configuration/msgr2/), [OSD chiffrés (cephadm)](https://docs.ceph.com/en/tentacle/cephadm/services/osd/), [renouvellement des clés cephx](https://docs.ceph.com/en/latest/rados/configuration/auth-config-ref/), [CVE-2026-50152](https://docs.ceph.com/en/latest/security/CVE-2026-50152/).

---

### M08-E28 — Mesurer les performances  `LAB` `★★`

> **Ticket PLAT-954** — *De : Karim Benali*
> Julien demande « combien d'IOPS » il aura pour la base de MédiAgenda, OpenStack va demander des volumes, et la seule réponse qu'on a, c'est « ça dépend ». Avant de régler quoi que ce soit (E29), je veux une **mesure** : reproductible, documentée, avec la méthode, pour qu'on puisse refaire exactement la même dans six mois et comparer.
> Et je veux savoir si les jumbo frames du M07 servent à quelque chose ici, chiffres à l'appui.

**Objectifs pédagogiques**
- Mesurer chaque couche séparément : réseau, OSD seul, RADOS, RBD, et le client final.
- Choisir des tailles de bloc et des profondeurs de file qui correspondent à des usages réels (base de données, fichiers, sauvegarde).
- Interpréter : débit, IOPS, latence moyenne et centiles, et ce qui limite dans un lab virtualisé.
- Documenter une méthode reproductible.

**Prérequis** : M08-E05, M08-E06 (pools et RBD), M08-E14 (règles par classe), M07-E15 (MTU 9000 sur les VLAN 30/31), M08-E24 (la sonde signale un cluster dégradé pendant une mesure).
**Durée indicative** : 3 h 30.

**Contexte technique**
- Outils : `rados bench`, `rbd bench`, `ceph tell osd.<N> bench`, `iperf3` (paquet de Debian et de Rocky), `fio` sur `cephcli01` (moteur `libaio` sur un périphérique krbd ; moteur `rbd` par librbd si ton `fio` en dispose : `fio --enghelp`).
- Pool de mesure **jetable** `bench` (règle de la classe `ssd`, réplication 3), créé et **supprimé** dans l'exercice. Image de mesure `bench/fio01` de 10 Gio.
- Tout ce qui tourne sur `pve01` partage le même SSD physique (`ssd-lab`) : tous les « OSD SSD » de tous les nœuds sont des fichiers sur un seul disque physique. Les chiffres absolus ne disent rien d'un vrai cluster ; les **comparaisons** et la méthode, si.
- Résultats et méthode : `docs/stockage/performances.md` de `plateforme/medisphere`.

> ⚠️ **Attention** : (1) une mesure en écriture sature le SSD de `pve01` : préviens (l'apprenant, c'est toi… et les autres VMs du lab) et évite les heures de sauvegarde ; (2) la suppression d'un pool exige d'autoriser temporairement l'opération sur les moniteurs : réautorise-la pour le seul pool `bench`, vérifie son nom deux fois, puis remets l'interdiction ; (3) le passage temporaire en MTU 1500 du réseau de cluster se fait **sur les trois nœuds en même temps**, sans persistance (un redémarrage rétablit 9000), et se défait juste après la mesure. Un MTU différent entre deux nœuds produit des pertes silencieuses de gros paquets : c'est la panne de M08-E42.

**Travail demandé**
1. **Méthode.** Écris d'abord la méthode dans `performances.md` : ce qui est mesuré, avec quels paramètres, combien de répétitions, dans quelles conditions (cluster HEALTH_OK, aucune récupération, aucune autre charge, état du cache), et comment on lit les résultats. Une mesure non reproductible ne compte pas.
2. **Réseau.** Entre deux nœuds, sur le réseau public **et** sur le réseau de cluster : `iperf3` (débit, un flux puis quatre), et `ping -M do -s 8972` pour prouver le MTU de bout en bout.
3. **OSD.** `ceph tell osd.<N> bench` sur un OSD de chaque classe. Compare avec la capacité que mClock a mesurée au démarrage de l'OSD (`osd_mclock_max_capacity_iops_*`).
4. **RADOS.** Crée le pool `bench`, puis `rados bench` en écriture (objets de 4 Mio, 16 opérations simultanées, 60 s, en gardant les objets), en lecture séquentielle et en lecture aléatoire, puis avec des objets de 4 Kio. Nettoie les objets de mesure.
5. **RBD et client.** Crée `bench/fio01`, puis `rbd bench` (écriture aléatoire 4 Kio et séquentielle 4 Mio) ; puis, sur `cephcli01`, des profils `fio` qui ressemblent à des usages réels : « base de données » (4 Kio aléatoire, 70 % lecture, profondeur 16, `direct=1`), « séquentiel » (1 Mio, profondeur 4), « latence » (4 Kio, écriture synchrone, profondeur 1). Note les centiles 95 et 99 de latence, pas seulement la moyenne. Garde les fichiers de profils `fio` dans `plateforme/ceph` (`bench/`).
6. **Jumbo ou pas.** Refais `iperf3` et `rados bench` en écriture 4 Mio après être passé **temporairement** en MTU 1500 sur l'interface du réseau de cluster des trois nœuds. Reviens à 9000 et revérifie au `ping`. Conclus : gain mesuré, et pourquoi il est (ou n'est pas) significatif ici.
7. **Nettoyage.** Supprime `bench/fio01` puis le pool `bench`, remets l'interdiction de suppression, vérifie le MTU 9000 partout. Complète `performances.md` : tableau des résultats, interprétation (qu'est-ce qui limite : CPU des VMs, SSD unique de `pve01`, réseau, réplication ?), et la réponse à Julien en trois phrases.

**Critères de réussite**
- [ ] `docs/stockage/performances.md` est sur `main` : méthode, résultats `iperf3`, `ceph tell … bench`, `rados bench`, `rbd bench` et `fio` (avec centiles), comparaison MTU 9000/1500, conclusion.
- [ ] Les profils `fio` sont versionnés dans `plateforme/ceph` (`bench/`).
- [ ] Le pool `bench` n'existe plus, la suppression de pool est de nouveau interdite, et le réseau de cluster des trois nœuds est en MTU 9000.

**Vérification** : `lab/bin/check 08 28`

<details><summary>Indice 1</summary>

`rados bench … write` supprime ses objets à la fin, sauf si on lui demande de les garder : sans eux, les lectures `seq` et `rand` n'ont rien à lire. Les objets gardés se nettoient ensuite par une sous-commande de `rados`. Pour `rbd bench`, `--io-type`, `--io-size`, `--io-threads`, `--io-total` et `--io-pattern` suffisent.
</details>

<details><summary>Indice 2</summary>

Avec `fio`, `direct=1` contourne le cache de page du client, et `fsync=1` (ou `sync=1`) force l'écriture synchrone : c'est le profil qui ressemble à un journal de base de données. La section « clat percentiles » de la sortie donne les centiles ; `--output-format=json` facilite le report dans un tableau.
</details>

<details><summary>Indice 3</summary>

Une seule interface change de MTU, et elle seule : celle du VLAN 31 sur chaque nœud (`ip link set … mtu …` est non persistant). Les adresses du réseau public, `cephcli01` et les passerelles restent à 9000. Avant de comparer, vérifie que la récupération est nulle et que le cluster est revenu HEALTH_OK après le changement.
</details>

**Pour aller plus loin** (facultatif) : coût du mode `secure` du messager (E27) mesuré en le repassant en `crc` sur une fenêtre courte ; `ceph osd perf` et `ceph tell osd.N dump_historic_ops` pendant une mesure ; [Benchmark a Ceph storage cluster](https://docs.ceph.com/en/tentacle/start/hardware-recommendations/), [documentation de fio](https://fio.readthedocs.io/en/latest/fio_doc.html).

---

### M08-E29 — Régler la mémoire, la récupération et mClock  `LAB` `★★★`

> **Ticket PLAT-955** — *De : Nadia Roussel* — *Copie : Karim Benali*
> Deux soucis la semaine dernière. Un : `ceph02` a frôlé l'OOM ; la VM a 6 Go et les OSD en prennent ce qu'ils veulent. Deux : pendant la reconstruction après l'arrêt d'un OSD, les tests de MédiAgenda ont vu leurs latences multipliées par dix, et personne ne savait si on pouvait « ralentir la récupération » ou au contraire l'accélérer pour en finir.
> Je veux une mémoire maîtrisée, et un mode d'emploi : quel réglage, dans quelle situation, et comment revenir à la normale.

**Objectifs pédagogiques**
- Comprendre la gestion mémoire d'un OSD BlueStore (`osd_memory_target`, caches, réglage automatique de cephadm) et la dimensionner pour un hôte.
- Comprendre l'ordonnanceur mClock : profils, capacité mesurée, et pourquoi les options de récupération classiques sont verrouillées.
- Mesurer l'effet d'un profil sur la récupération et sur la latence cliente, puis revenir à l'état nominal.
- Utiliser les drapeaux de maintenance à bon escient.

**Prérequis** : M08-E28 (mesures de référence, profils `fio`), M08-E19 (retirer un OSD), M08-E24 (sonde).
**Durée indicative** : 3 h.

**Contexte technique**
- Chaque nœud : 6 Go, 3 OSD, un MON, un MGR (sur deux nœuds), un MDS, un RGW (sur deux nœuds) ou un haproxy/keepalived d'ingress. Cible du PLAN : `osd_memory_target` = **1 Gio** par OSD.
- cephadm sait régler `osd_memory_target` automatiquement selon la mémoire de l'hôte (`osd_memory_target_autotune`, ratio `mgr/cephadm/autotune_memory_target_ratio`). Une valeur fixée à la main et le réglage automatique ne doivent pas coexister.
- mClock : profils intégrés `balanced` (défaut), `high_client_ops`, `high_recovery_ops` ; profil `custom` déconseillé. Option `osd_mclock_override_recovery_settings` pour déverrouiller `osd_max_backfills` et `osd_recovery_max_active*`.
- Charge cliente : profil `fio` « base de données » de E28 sur `cephcli01`, pendant toute la phase de récupération.

> ⚠️ **Attention** : (1) une valeur de `osd_memory_target` trop basse fait chuter les performances (caches vides), trop haute provoque l'OOM : vérifie le minimum accepté par l'option avant de la poser ; (2) n'arrête qu'**un** OSD à la fois et remets-le en service avant d'en arrêter un autre ; (3) tout réglage posé « pour un test » sur un OSD précis (`osd.N`) ou un drapeau global (`noout`, `norebalance`, `nobackfill`) doit être retiré à la fin : la vérification le contrôle.

**Travail demandé**
1. **Mémoire, constat.** Relève, sur chaque nœud : mémoire totale et disponible, consommation de chaque démon (`ceph orch ps`, colonnes MEM USE et MEM LIM), `osd_memory_target` en vigueur pour chaque OSD (`ceph config show`), état du réglage automatique, et le détail des caches d'un OSD (`ceph tell osd.<N> dump_mempools`). Lis `ceph config help osd_memory_target` : quelle est la valeur minimale ? D'où vient la valeur en vigueur (défaut, automatique, configuration) ?
2. **Mémoire, décision.** Calcule le budget d'un nœud (système, MON, MGR, MDS, RGW ou ingress, 3 OSD) et décide : réglage automatique (avec quel ratio) ou valeur fixe de 1 Gio. Applique la décision **au bon niveau** de la configuration centrale (pas OSD par OSD), et vérifie la valeur en vigueur sur chaque OSD. Consigne le calcul dans `performances.md`.
3. **mClock, constat.** Relève le profil en vigueur, la capacité mesurée de chaque OSD (`osd_mclock_max_capacity_iops_ssd` / `_hdd`) et les valeurs effectives de `osd_max_backfills` et `osd_recovery_max_active`. Essaie de modifier `osd_max_backfills` sans déverrouillage : que se passe-t-il ?
4. **Récupération mesurée.** Charge cliente lancée, arrête un OSD SSD de `ceph02`, marque-le `out` et mesure, pour chaque profil (`balanced`, puis `high_client_ops`, puis `high_recovery_ops`, en remettant l'OSD en service et en attendant HEALTH_OK entre deux essais) : durée de la récupération, débit de récupération (`ceph -s`), latence p99 du client. Tableau dans `performances.md`.
5. **Maintenance.** Compare `ceph osd set noout`, `ceph osd add-noout osd.<N>`, `ceph osd set-group noout <hôte>` et `ceph orch host maintenance enter <hôte>` : portée, effet, retour. Lequel pour redémarrer `ceph03` pour une mise à jour du noyau ? Fais-le, puis reviens.
6. **Retour au nominal.** Reviens au profil nominal que tu choisis (justifié), retire tout réglage par OSD et tout drapeau, et écris dans `docs/stockage/runbooks/` (dans RB-080 ou un document de fiche réflexe) : « la récupération gêne les clients » et « la récupération est trop lente » — quel réglage, combien de temps, comment revenir.

**Critères de réussite**
- [ ] Tous les OSD ont `osd_memory_target` = 1 Gio en vigueur, posé au niveau `osd` de la configuration centrale ; le réglage automatique est désactivé pour les OSD.
- [ ] Aucun réglage mClock ou de récupération n'est posé sur un OSD particulier ; `osd_mclock_override_recovery_settings` n'est pas activé ; le profil en vigueur est celui documenté.
- [ ] Aucun drapeau `noout`, `norebalance`, `nobackfill`, `norecover`, `pause` n'est posé ; aucun hôte en maintenance ; HEALTH_OK.
- [ ] `performances.md` contient le budget mémoire et le tableau de récupération par profil ; la fiche réflexe est écrite.

**Vérification** : `lab/bin/check 08 29`

<details><summary>Indice 1</summary>

La configuration centrale a des niveaux : `global`, type de démon (`osd`), hôte (masque `osd/host:ceph02`), classe de périphérique, démon (`osd.3`). Le réglage automatique de cephadm écrit lui-même des valeurs **par hôte** : si tu le désactives, regarde ce qu'il laisse dans `ceph config dump`. Une valeur plus spécifique gagne toujours sur une valeur plus générale.
</details>

<details><summary>Indice 2</summary>

Avec mClock, la récupération et les clients se partagent la capacité de l'OSD selon des réservations, des poids et des limites exprimés en fraction de cette capacité : une capacité mal mesurée (fréquent en VM) fausse tous les profils. Le profil se change à chaud, sans redémarrage, au niveau `osd`.
</details>

<details><summary>Indice 3</summary>

Le mode maintenance de cephadm arrête **tous** les démons de l'hôte et pose le drapeau `noout` pour cet hôte ; il refuse si l'arrêt rendrait des données indisponibles. Pour mesurer la latence p99 pendant la récupération, lance `fio` avec une durée fixe et `--output-format=json`, et découpe la mesure en tranches (`--status-interval`).
</details>

**Pour aller plus loin** (facultatif) : l'ordonnanceur `wpq` et le cas des grosses récupérations en codes d'effacement sur HDD ; `osd_memory_cache_min` ; le réglage `bluestore_cache_autotune` ; [mClock config reference](https://docs.ceph.com/en/tentacle/rados/configuration/mclock-config-ref/), [réglage automatique de la mémoire (cephadm)](https://docs.ceph.com/en/tentacle/cephadm/services/osd/), [BlueStore config reference](https://docs.ceph.com/en/tentacle/rados/configuration/bluestore-config-ref/).

---

### M08-E30 — ADR : le stockage objet de MédiDoc  `RED` `★★`

> **Ticket PLAT-956** — *De : Claire Morel* — *Copie : Julien Petit, Sophie Laurent*
> MédiDoc va stocker les documents des patients (comptes rendus, ordonnances numérisées, imagerie légère) en S3. On a deux candidats chez nous : le SeaweedFS de `s3-01`, qui porte déjà l'état OpenTofu et les artefacts, et le RGW de `ceph-par1`. Julien veut « celui qui marche avec le SDK Go », Sophie veut « celui qui passe l'audit HDS ».
> Écris l'ADR-0080. Je veux une décision défendable devant l'auditeur, avec ce qu'elle coûte.

**Objectifs pédagogiques**
- Comparer deux solutions de stockage objet sur des critères explicites et pondérés (données de santé, disponibilité, isolement, exploitation, compatibilité S3).
- Séparer stockage de **plateforme** (outillage) et stockage de **données métier**.
- Rédiger une décision avec ses conséquences négatives et ses actions.

**Prérequis** : M05 (`s3-01`, SeaweedFS, état OpenTofu), M08-E11 et M08-E12 (RGW, comptes, politiques), M08-E25 (sauvegarde), M08-E27 (chiffrement).
**Durée indicative** : 2 h.

**Travail demandé**
Rédige `docs/stockage/adr/ADR-0080-stockage-objet-medidoc.md` (gabarit MADR de M00-E33, deux pages au plus), par MR sur `plateforme/medisphere`. L'ADR doit au minimum :
1. Énoncer le **contexte** : nature des données (données de santé, durée de conservation réglementaire, volumétrie estimée par Julien : 2 To la première année, objets de 50 Kio à 20 Mio), exigences de Sophie (chiffrement, cloisonnement, traçabilité des accès, sauvegarde hors site), exigences de Julien (API S3, URL présignées, versionnage).
2. Lister des **critères** pondérés : redondance et domaines de panne, chiffrement en transit et au repos, cloisonnement (comptes, politiques, quotas), versionnage et verrouillage d'objets (rétention), journalisation des accès, sauvegarde, exploitation (supervision, mises à jour, compétences), compatibilité S3 (SDK Go, présignage), dépendances (qu'est-ce qui tombe avec quoi), et coût mémoire/disque dans le lab et en cible.
3. Comparer au moins trois **options** (par exemple : SeaweedFS de `s3-01` ; RGW de `ceph-par1` ; un SeaweedFS ou un RGW **dédié** à MédiDoc), chacune évaluée sur les critères, avec les faits vérifiés dans les exercices (pas d'affirmation non prouvée).
4. **Trancher**, et dire ce que devient l'autre solution (qui reste pour quoi).
5. Lister les **conséquences** négatives et les actions induites, rattachées à un module (sauvegarde des compartiments, rotation des clés d'accès, verrouillage d'objets, supervision des quotas, PRA à PAR2 au final F5, identités par OIDC au module 24…).

**Critères de réussite**
- [ ] L'ADR suit le gabarit, tient en deux pages, et contient un tableau critères × options avec une pondération.
- [ ] Au moins trois options réellement envisagées ; chaque évaluation s'appuie sur un fait vérifiable (exercice, documentation).
- [ ] La décision dit ce qui reste sur `s3-01` et ce qui va sur l'autre solution, et pourquoi le mélange serait un risque.
- [ ] Les conséquences négatives sont écrites, avec des actions rattachées à un module ou datées.

Auto-évaluation : grille fournie dans le corrigé.

<details><summary>Indice 1</summary>

Demande-toi ce qui tombe **en même temps** : si le stockage des documents patients partage la machine (ou le cluster) qui porte l'état OpenTofu, une panne ou une saturation de l'un empêche de réparer l'autre. Une plateforme ne doit pas dépendre, pour se reconstruire, de ce qu'elle héberge.
</details>

<details><summary>Indice 2</summary>

Pour les critères réglementaires, relis ce que chaque solution offre **réellement** dans les versions du workbook (comptes et politiques IAM de RGW, verrouillage d'objets, journaux des opérations ; ce que SeaweedFS fournit en face), et ce que tu as **mis en place** (chiffrement E27, sauvegarde E25). Un critère « possible un jour » n'est pas un critère « satisfait ».
</details>

**Pour aller plus loin** (facultatif) : le verrouillage d'objets S3 (*Object Lock*) en mode conformité et son interaction avec le droit à l'effacement (RGPD) ; [Object Lock dans RGW](https://docs.ceph.com/en/tentacle/radosgw/s3/objectops/) ; [comptes RGW](https://docs.ceph.com/en/latest/radosgw/account/).

---

### M08-E31 — Cloisonner le stockage par équipe  `LIBRE` `★★★`

> **Ticket DEV-957** — *De : Julien Petit* — *Copie : Sophie Laurent*
> On arrive. MédiAgenda a besoin de volumes bloc pour ses environnements de recette (PostgreSQL) et d'un partage de fichiers pour les exports ; MédiDoc pareil, plus son S3 (déjà fait avec le compte de E12). On voudrait pouvoir créer nos volumes nous-mêmes, sans ticket à chaque fois.
> *Réponse de Sophie* : d'accord, à trois conditions. Une équipe ne voit **jamais** les données d'une autre, même par erreur de commande. Chaque équipe a un **plafond** de capacité. Et on sait à tout moment qui consomme quoi.

**Objectifs pédagogiques**
- Concevoir un cloisonnement multi-équipes dans Ceph (espaces de noms RBD, groupes de sous-volumes CephFS, identités cephx) et en connaître les limites.
- Traduire « un plafond par équipe » dans ce que Ceph sait faire réellement, et compléter ce qu'il ne sait pas faire.
- Prouver l'isolement par des essais négatifs.

**Prérequis** : M08-E10 (CephFS, sous-volumes), M08-E12 (comptes RGW), M08-E13 (cephx), M08-E14 (règles par classe), M08-E20 (quotas), M08-E25 (la liste des images sauvegardées s'étend).
**Durée indicative** : 4 h.

**Contexte technique**
- Équipes : **`mediagenda`** et **`medidoc`**. Identités cephx : `client.mediagenda` et `client.medidoc`.
- Bloc : un pool dédié aux équipes, **`rbd-equipes`** (classe `ssd`, réplication 3, application `rbd`), avec un espace de noms RBD par équipe.
- Fichier : volume `cephfs` (E10), un groupe de sous-volumes par équipe.
- Allocations décidées par Claire : `mediagenda` 40 Gio en bloc et 10 Gio en fichier ; `medidoc` 20 Gio en bloc et 20 Gio en fichier.
- Registre des allocations : `docs/stockage/allocations.md` de `plateforme/medisphere` (équipe, ressource, plafond, identité cephx, date, ticket). Il sert aussi pour les équipes suivantes.
- Les clés des équipes leur sont remises par Vault (chemin à ton choix, inscrit au registre des secrets) ; pour les essais, une copie de chaque trousseau est posée sur `cephcli01` (`/etc/ceph/`, 600).

**Contraintes**
- Une identité d'équipe ne peut ni lister, ni lire, ni écrire, ni supprimer les images ou les fichiers de l'autre équipe, ni ceux des autres usages du cluster (`rbd-test`, futurs pools OpenStack et Kubernetes) ; elle ne peut pas modifier ses propres droits ni créer de pool.
- Une équipe peut créer, agrandir, prendre un instantané et supprimer **ses** images et **ses** sous-volumes sans intervention de l'équipe Plateforme.
- Le plafond de chaque équipe est appliqué par Ceph **quand Ceph sait le faire**, et surveillé sinon : tu dois établir, pour le bloc et pour le fichier, ce que Ceph applique réellement, et compenser ce qui manque.
- Tout est décrit par le code (`plateforme/ceph`) et reproductible : ajouter une troisième équipe (E34) doit être l'affaire d'une MR.
- La sauvegarde (E25) couvre les volumes des équipes que l'équipe désigne : décide comment l'équipe les désigne.

**Critères de réussite**
- [ ] Les espaces de noms `mediagenda` et `medidoc` existent dans `rbd-equipes` ; chaque équipe a son groupe de sous-volumes dans `cephfs`, avec son plafond appliqué.
- [ ] Les droits de `client.mediagenda` et `client.medidoc` sont limités à leur espace de noms et à leur chemin CephFS ; aucun `allow *`.
- [ ] Depuis `cephcli01`, chaque identité réussit sur ses propres ressources et échoue sur celles de l'autre équipe et sur `rbd-test`.
- [ ] Le pool `rbd-equipes` a un quota ; la limite de ce que Ceph applique par espace de noms est documentée et compensée (contrôle, supervision ou processus).
- [ ] `docs/stockage/allocations.md` décrit les deux équipes ; le code est sur `main` de `plateforme/ceph`.

**Vérification** : `lab/bin/check 08 31`

<details><summary>Indice 1</summary>

Commence par lister ce qui porte un quota dans Ceph : un pool (octets, objets), un répertoire CephFS (attribut de quota, et la taille d'un groupe de sous-volumes ou d'un sous-volume qui s'appuie dessus), un compte ou un compartiment RGW. Un espace de noms RBD figure-t-il dans cette liste ?
</details>

<details><summary>Indice 2</summary>

Les profils cephx `rbd` acceptent une restriction par pool **et** par espace de noms. Pour CephFS, une restriction de chemin côté MDS ne suffit pas à elle seule : relis ce que deviennent les données (objets RADOS) d'un sous-volume, et l'option de création qui isole ses objets dans un espace de noms RADOS.
</details>

<details><summary>Indice 3</summary>

Pour prouver l'isolement, fais une matrice : identités en lignes, ressources en colonnes, actions (lister, lire, écrire, supprimer) dans les cases, résultat attendu et obtenu. Une case « attendu : refus » non testée est une case fausse.
</details>

**Pour aller plus loin** (facultatif) : des pools par équipe (quotas natifs) et leur coût en PG ; le module mgr `rbd_support` et les statistiques par image dans les métriques (`rbd_stats_pools`) ; [espaces de noms RBD](https://docs.ceph.com/en/tentacle/rbd/rados-rbd-cmds/), [FS volumes and subvolumes](https://docs.ceph.com/en/tentacle/cephfs/fs-volumes/), [capacités CephFS](https://docs.ceph.com/en/tentacle/cephfs/client-auth/).

---

### M08-E32 — Questions de production : stockage distribué  `Q` `★★★`

> **Ticket PLAT-958** — *De : Karim Benali*
> Avant de te confier l'astreinte sur `ceph-par1`, je veux t'entendre sur ces questions. Argumente, chiffre quand c'est possible, et dis de quoi dépend le « ça dépend ».

**Objectifs pédagogiques**
- Raisonner sur le comportement en production de Ceph : redondance, capacité, défaillances, mises à jour, sécurité.
- Relier les choix du module à des risques concrets.

**Prérequis** : paliers 1 et 2, M08-E24 à E31.
**Durée indicative** : 1 h 30.

**Questions**

1. Le cluster a 3 nœuds, des pools répliqués `size=3`, `min_size=2`, domaine de panne `rack` avec une baie par nœud (E14, autant dire `host`). Un nœud tombe. Que se passe-t-il pour les lectures, les écritures, et la reconstruction ? Un second nœud tombe une heure plus tard : même question. Qu'aurait changé `min_size=1` ?
2. QCM — Un OSD est `down` depuis 15 minutes. `mon_osd_down_out_interval` vaut sa valeur par défaut. Que fait Ceph ?
   a) rien tant qu'un humain ne l'a pas marqué `out` ;
   b) il l'a déjà marqué `out` et la reconstruction est en cours ;
   c) il le marque `out` au bout de 10 minutes, donc la reconstruction a commencé il y a 5 minutes ;
   d) il ne le marque jamais `out` sur un cluster de 3 nœuds car la règle ne pourrait pas être satisfaite.
   Justifie, puis dis ce que change le fait qu'il n'y ait que 3 baies (3 nœuds) pour une règle de taille 3.
3. `ceph df` annonce 384 Gio bruts en classe `ssd` et un `MAX AVAIL` de 95 Gio pour un pool répliqué 3 fois. Explique l'écart avec 384/3 = 128. Pourquoi `MAX AVAIL` baisse-t-il quand **un seul** OSD est plus rempli que les autres ? Quels seuils (`nearfull`, `backfillfull`, `full`) interviennent, dans quel ordre, et que se passe-t-il pour les clients à chacun ?
4. Pourquoi un cluster de 3 nœuds de capacité égale ne doit-il pas être rempli au-delà d'environ 66 % s'il doit survivre à la perte d'un nœud **avec** reconstruction ? Et pourquoi, avec 3 nœuds et `size=3`, la perte d'un nœud n'entraîne-t-elle pas de reconstruction du tout ?
5. Le mgr actif tombe. Qu'est-ce qui s'arrête (tableau de bord, orchestrateur, métriques, autoscaler, entrées/sorties des clients) ? Combien de temps avant la bascule ? Que se passe-t-il s'il n'y a pas de mgr en attente ?
6. QCM — Pendant la mise à jour E26, un OSD ne redémarre pas après le changement d'image. L'orchestrateur :
   a) revient automatiquement à l'image 20.2.3 sur tous les démons ;
   b) continue avec les OSD suivants et signale l'échec à la fin ;
   c) s'arrête et pose un contrôle de santé, la mise à jour est en pause jusqu'à intervention ;
   d) supprime l'OSD et le recrée.
   Justifie, et décris ta démarche.
7. Pourquoi une mise à jour de Ceph ne se défait-elle pas simplement en redéployant l'ancienne image ? Qu'est-ce qui, dans les moniteurs et les OSD, change de format ou de fonctionnalités (`require_osd_release`, fonctionnalités des moniteurs) ?
8. Le mode `secure` du messager est actif. Un attaquant capture tout le trafic du VLAN 31. Que voit-il ? Et sur le VLAN 30 si un client noyau s'est monté sans `ms_mode` ? Quel est le coût du chiffrement, et où se paie-t-il ?
9. Les OSD sont chiffrés par cephadm. Un administrateur de `pve01` copie le fichier disque d'un OSD. Peut-il lire les données ? Et un attaquant qui possède une clé cephx avec `mon 'allow r'` sur un cluster en 20.2.3 ? en 20.2.4 ? Que conclus-tu sur la séparation des clés et des données ?
10. QCM — Une identité a les droits `mon 'profile rbd' osd 'profile rbd pool=rbd-equipes namespace=mediagenda'`. Elle peut :
    a) lister toutes les images de `rbd-equipes` mais n'ouvrir que celles de `mediagenda` ;
    b) créer, ouvrir, agrandir et supprimer des images de `rbd-equipes/mediagenda` seulement ;
    c) créer un pool si elle le nomme `mediagenda` ;
    d) lire les images de `mediagenda` mais pas les créer, il manque `allow w`.
    Justifie, et dis ce que l'espace de noms ne limite **pas**.
11. Une équipe crée 40 images de 1 Tio dans son espace de noms, sur un pool qui a un quota de 100 Gio. Que se passe-t-il à la création ? à l'écriture ? Que voient les **autres** équipes du même pool quand le quota est atteint ? Qu'en conclus-tu sur le partage d'un pool entre équipes ?
12. La sauvegarde E25 exporte des incrémentaux depuis l'instantané de la veille. Quelqu'un supprime cet instantané à la main. Que fait le script ? Que vaut le RPO pendant ce temps ? Comment le détecterais-tu si le script, lui, était silencieux ?
13. QCM — Tu restaures dans un **nouveau cluster** l'archive de configuration de E25 (configuration centrale, spécifications, CRUSH, identités cephx). Qu'obtiens-tu ?
    a) le cluster d'origine, données comprises ;
    b) un cluster vide mais configuré comme l'ancien, dans lequel les clients d'origine peuvent s'authentifier si tu réimportes les identités ;
    c) rien d'utilisable, les identités cephx sont liées au `fsid` du cluster ;
    d) un cluster qui reprend automatiquement les OSD de l'ancien.
    Justifie, et dis ce qui manque pour retrouver le **service** (et pas seulement la configuration).
14. Compare, pour MédiSphère, un cluster de 3 gros nœuds et un cluster de 6 petits nœuds de même capacité totale : coût, temps de reconstruction après la perte d'un nœud, capacité utilisable en gardant la tolérance d'un nœud, codes d'effacement possibles.
15. Pourquoi Ceph recommande-t-il des disques entiers (et non des partitions, des RAID matériels ou des disques virtuels sur un même disque physique) ? Lesquelles de ces recommandations le lab enfreint-il, et quelles conclusions de E28 cela invalide-t-il ?
16. L'auditeur demande « qui a accédé aux documents de tel patient le 3 mars ». Qu'est-ce que Ceph (RGW) peut fournir, qu'est-ce qu'il ne peut pas, et où cette traçabilité doit-elle se faire ?

Les réponses argumentées sont dans le corrigé.

---

### M08-E33 — Politique de stockage de MédiSphère  `RED` `★★`

> **Ticket PLAT-959** — *De : Claire Morel* — *Copie : Sophie Laurent*
> Les équipes vont demander du stockage par dizaines de tickets. Je ne veux pas qu'on décide au cas par cas, ni qu'on découvre dans six mois qu'une base de production tourne sur des HDD en code d'effacement sans sauvegarde. Écris la **politique de stockage** : ce qu'on propose, à quelles conditions, avec quelles garanties, et ce qu'on refuse.

**Objectifs pédagogiques**
- Définir des classes de service de stockage à partir des capacités réelles du cluster.
- Relier chaque garantie annoncée à un mécanisme vérifiable (règle CRUSH, réplication, chiffrement, sauvegarde, supervision).
- Encadrer le cycle de vie d'une demande : allocation, extension, sauvegarde, restitution, effacement.

**Prérequis** : M08-E14, E15 (règles et codes d'effacement), M08-E20 (seuils), M08-E25 (sauvegarde), M08-E27 (chiffrement), M08-E31 (cloisonnement, allocations), M06-E33 (structure d'une politique).
**Durée indicative** : 2 h 30.

**Travail demandé**
Rédige `docs/stockage/politique-stockage.md` dans `plateforme/medisphere` (4 à 6 pages, par MR, relue par Claire et Sophie — joue leur rôle avec la grille du corrigé). Elle doit au minimum couvrir :
1. **Objet et périmètre** : ce qui est concerné (`ceph-par1` : bloc, fichier, objet) et ce qui ne l'est pas (`s3-01`, disques locaux des hyperviseurs, sauvegardes PBS).
2. **Classes de service** : pour chacune (par exemple « bloc performant », « bloc capacitif », « fichier partagé », « objet »), le support (classe de périphérique, réplication ou code d'effacement, domaine de panne), les usages autorisés et **interdits**, la redondance garantie (perte de quoi tolérée), les performances indicatives **mesurées** (E28, avec leur réserve), la sauvegarde incluse ou non.
3. **Données de santé** : quelles classes peuvent les accueillir, et à quelles conditions (chiffrement au repos et en transit, cloisonnement, sauvegarde hors site, journalisation).
4. **Capacité** : seuils de remplissage (cluster et pools), réserve pour la perte d'un nœud, quotas, ce qui déclenche une extension (E18, RB-081) et avec quel délai.
5. **Demandes et cycle de vie** : comment une équipe demande (ticket, MR sur le registre des allocations), délais, extension, restitution, **effacement** (suppression des images, des instantanés, des sauvegardes ; preuve), durée de conservation.
6. **Accès** : identités par équipe, droits minimaux, remise et renouvellement des clés, ce que l'équipe Plateforme peut voir.
7. **Exploitation** : supervision (E24), mises à jour (RB-082), sauvegarde et tests de restauration (E25), engagements de disponibilité et leurs limites honnêtes (un seul cluster, un seul site, un seul hyperviseur dans le lab).
8. **Exceptions et gestion du document** : qui décide d'une exception, comment elle est tracée ; version, propriétaire, date de revue.

**Critères de réussite**
- [ ] Les huit rubriques sont présentes ; chaque classe de service renvoie à une règle CRUSH, un pool ou un mécanisme **existant** du cluster.
- [ ] Les chiffres (seuils, réserve, performances, RPO/RTO) sont cohérents avec la configuration et les mesures réelles (E20, E25, E28, E29).
- [ ] Les usages interdits et les limites sont écrits (ce que le lab ne garantit pas).
- [ ] Le document est sur `main` de `plateforme/medisphere`, au chemin imposé.

Auto-évaluation : grille fournie dans le corrigé.

<details><summary>Indice 1</summary>

Pour chaque phrase « nous garantissons… », pose la question de M06-E33 : quel fichier, quelle règle ou quel contrôle le prouve ? Une classe de service qui n'existe que dans le document est une promesse vide ; une classe qui existe dans le cluster mais pas dans le document est une porte ouverte.
</details>

<details><summary>Indice 2</summary>

Les usages interdits sont souvent les plus utiles : une base de données sur du code d'effacement HDD, des données de santé dans un pool sans sauvegarde, un pool partagé entre production et recette. Écris-les explicitement, avec la raison.
</details>

**Pour aller plus loin** (facultatif) : un catalogue de services en libre-service (module 28) qui applique la politique par construction ; [placement groups et capacité](https://docs.ceph.com/en/tentacle/rados/operations/placement-groups/), [référentiel HDS](https://esante.gouv.fr/produits-services/hds).

---

### M08-E34 — Livrer du stockage à une équipe en temps limité  `CHRONO` `★★★`

> **Ticket CHG-960** — *De : Claire Morel*
> L'équipe MédiNotif démarre lundi. Elle a besoin de son stockage, et la direction veut savoir combien de temps il faut à la Plateforme pour livrer **proprement** une nouvelle équipe : identités, cloisonnement, plafonds, sauvegarde, supervision, documentation.
> Le dossier est prêt (ressources de l'exercice). Chrono en main.

**Règles de l'exercice**
- Conditions d'examen : pas de corrigé, pas d'autres notes que **tes** runbooks, ton code (`plateforme/ceph`), le registre des allocations et la documentation officielle.
- Durée cible : **1 h 30** entre l'ouverture du dossier (T0) et la livraison vérifiée (T4).
- Tout passe par le code et les MR (`plateforme/ceph`, `plateforme/ansible`, `plateforme/medisphere`). Une commande manuelle est permise pour **constater**, jamais pour créer ; s'il t'en faut une pour avancer, note-la dans la feuille de temps : c'est un défaut de ton outillage.
- Le stockage de MédiNotif est **conservé** après l'exercice (l'application arrive au module 12).

**Prérequis** : M08-E31 (cloisonnement, registre des allocations), M08-E12 (comptes RGW), M08-E24 (sonde), M08-E25 (sauvegarde), M08-E33 (politique).
**Durée** : 1 h 30 chronométrées + 30 minutes de retour d'expérience.

**Dossier** : [`ressources/M08-E34/dossier-chrono.md`](../ressources/M08-E34/dossier-chrono.md) (le besoin, les exigences, la feuille de temps). Lis-le à T0, pas avant.

**Critères de réussite**
- [ ] Toutes les exigences du dossier sont satisfaites à T4 (vérification ci-dessous).
- [ ] La feuille de temps est remplie (T0 à T4), avec les gestes manuels éventuels et leur raison ; le temps total est inférieur à 1 h 30 (sinon, améliore ton outillage et refais l'exercice sur une équipe fictive, détruite ensuite).
- [ ] Le retour d'expérience (une demi-page) est rédigé, et ta procédure d'accueil d'une équipe mise à jour par MR.

**Vérification** : `lab/bin/check 08 34` (à lancer à T4).

**Pour aller plus loin** (facultatif) : refais l'exercice en visant 30 minutes, puis demande-toi ce qu'il faudrait pour que MédiNotif le fasse **seule** à partir d'une MR sur le registre des allocations (pipeline qui applique, module 28).
