# Module 02 — Palier 3 : Production

Les outils existent, ils sont testés sur ton poste. Pour Karim Benali, ce n'est encore que du code « qui marche chez toi » : tant que la forge ne le vérifie pas à chaque MR, qu'il n'est pas livré en versions installables, et qu'il ne tourne pas tout seul la nuit, ce n'est pas de l'outillage de production. Nadia Roussel, qui l'utilisera d'astreinte, veut des outils qu'on peut relancer sans crainte, qui ne laissent rien traîner quand on les interrompt, qui se documentent eux-mêmes ; Sophie Laurent veut qu'aucun d'eux ne devienne une porte vers `root` ou vers les sauvegardes. Ce palier fait passer `plateforme/outils` en production : CI complète sur `runner01`, paquet versionné dans le registre de GitLab, contrôle planifié des sauvegardes, idempotence, parallélisme, durcissement, signaux, documentation et décision d'architecture. Il se termine par une épreuve chronométrée.

> **Rappels** : tout se fait depuis `adm01`, dans `~/src/outils` ; chaque exercice se termine par une MR fusionnée dans `main`, pipeline vert. Conventions communes (codes retour 0/1/2/3, stdout pour les données, secrets dans `~/.config/workbook/` en 600, TLS vérifié) : voir [`00-introduction.md`](00-introduction.md). Bibliothèque commune : `lib/ms-commun.sh` (E10, E13). VMs jetables de ce palier : **2027** `m02-idem` (E27) et **2028** `m02-attente` (E30), pool `lab`, VNet `vsandbox`, étiquette `env-m02`, à détruire après validation.

---

### M02-E24 — CI du projet outils : lint et tests sur `runner01`  `LAB` `★★`

> **Ticket PLAT-354** — *De : Karim Benali*
> Le pipeline de `plateforme/outils` ne fait que ce que font les gabarits communs : pre-commit, commitlint, gitleaks. Personne ne lance `bats` ni `pytest` avant de fusionner, et la semaine dernière une MR a cassé `ms-snapshot` sans que rien ne bouge.
> Je veux sur chaque MR : ShellCheck, ruff, bats, pytest et la construction du paquet, sur `runner01`, avec les résultats des tests **dans la MR**. Mêmes commandes qu'en local : la CI appelle le Taskfile, elle ne le recopie pas. Et je ne veux jamais voir un job de test parler au vrai Proxmox.

**Objectifs pédagogiques**
- Outiller un runner `shell` de façon reproductible : versions figées, provenance et empreintes vérifiées.
- Écrire les jobs d'un projet qui étendent des gabarits partagés (`include: project`), avec `rules`, `extends`, artefacts.
- Remonter les résultats de tests dans GitLab (`artifacts:reports:junit`) et le taux de couverture.
- Garantir l'isolement des tests vis-à-vis de l'infrastructure réelle.

**Prérequis** : M01-E23/E24/E25 (`runner01`, gabarits `qualite.yml` et `release.yml`), M02-E14, M02-E18, M02-E20 (Taskfile : tâches `lint:sh`, `lint:py`, `test:bats`, `test:py`, `build`, rapports dans `rapports/`).
**Durée indicative** : 2 h.

**Contexte technique**
- `runner01` (10.10.20.15), GitLab Runner 19.4, exécuteur `shell`, étiquettes `shell` et `socle`, compte système `gitlab-runner` ; `uv` y est déjà (M01). Il lui manque : ShellCheck 0.11, shfmt 3.14, jq 1.8, bats-core 1.13, Task 3.54. **Mêmes versions et même provenance que sur `adm01`** (voir l'introduction du module : rétroportages Debian pour ShellCheck, binaires de release vérifiés pour les autres, `/opt/bats` pour bats).
- Gabarits partagés (M01) : `qualite.yml` définit le `workflow` (pipelines de MR et de branche, pas de doublon), les stages `lint`, `test`, `build`, `release` et les jobs `pre-commit`, `commitlint`, `gitleaks` ; `release.yml` définit `release` (semantic-release, sur `main` seulement).
- Noms de jobs imposés (vérification) : `shellcheck`, `ruff`, `bats`, `pytest`, `build`.
- GitLab nomme une suite de tests du rapport d'après le job qui l'a produite.

**Travail demandé**
1. **Outiller `runner01`.** Écris un script d'installation idempotent (versionné dans le projet, par exemple `outils-ci/installer-outils-runner01.sh`) qui installe les cinq outils aux versions de l'introduction et **refuse** d'installer un binaire dont l'empreinte SHA-256 n'est pas celle que tu as vérifiée en installant `adm01`. Lance-le, puis contrôle ce que voit réellement le compte qui exécute les jobs :
   ```
   admin@runner01:~$ sudo -u gitlab-runner -H bash -lc 'command -v shellcheck shfmt jq bats task uv'
   ```
   Note dans ton journal : pourquoi tester avec `gitlab-runner` et pas avec `admin` ?
2. **Les jobs.** Dans `.gitlab-ci.yml`, garde l'inclusion des gabarits (`ref: v1`) et ajoute les cinq jobs. Chacun appelle une tâche du Taskfile. Exigences :
   - un modèle commun (`extends`) pour l'étiquette du runner et l'interruption des pipelines obsolètes ;
   - dans une MR, les jobs Bash ne tournent que si des fichiers Bash (ou la CI, le Taskfile) ont changé, les jobs Python de même ; sur `main`, tout tourne toujours. Avant d'écrire tes `rules`, réponds dans ton journal : avec « Pipelines must succeed », un job **absent** d'un pipeline de MR bloque-t-il la fusion ? Et un job en échec ?
   - `bats` et `pytest` publient leur rapport JUnit, **même quand des tests échouent** ;
   - `pytest` expose le taux de couverture (mot-clé `coverage`, à partir de la ligne `TOTAL` de pytest-cov) ;
   - `build` conserve `dist/` une semaine.
3. **Doublon ou pas ?** Le job `pre-commit` lance peut-être déjà ShellCheck, shfmt et ruff (selon tes hooks de E04/E07). Garde ou supprime la redondance, mais justifie ton choix en trois lignes (versions des outils, lisibilité des échecs, coût).
4. **Isolement.** Vérifie et note les trois barrières qui empêchent un test de toucher le vrai Proxmox : dans le code des tests, dans la configuration du projet (variables CI), dans le réseau (d'où vient un job, où est `pve01`, que dit la matrice des flux ?).
5. **Preuve.** Ouvre une MR qui casse volontairement un test bats (une assertion fausse) : le pipeline doit échouer, l'onglet *Tests* de la MR doit montrer le test fautif par son nom, et la fusion doit être impossible. Corrige, pousse : tout repasse au vert. Une MR qui ne modifie que `src/` ne doit pas lancer `bats` ni `shellcheck`.

**Critères de réussite**
- [ ] Sur `runner01`, `gitlab-runner` dispose de ShellCheck 0.11, shfmt 3.14, jq 1.8, bats 1.13, Task 3.x et uv.
- [ ] Le dernier pipeline réussi de `main` contient les jobs `shellcheck`, `ruff`, `bats`, `pytest` et `build`, réussis, sur un runner `shell`.
- [ ] Le rapport de tests de ce pipeline contient des tests des suites `bats` et `pytest`, sans échec ; `build` a archivé `dist/`.
- [ ] Le projet n'a aucune variable CI `PVE_*`, et `.gitlab-ci.yml` ne contient aucun secret.
- [ ] La MR de démonstration (test cassé) est restée bloquée tant que le test échouait.

**Vérification** : `lab/bin/check 02 24`

<details><summary>Indice 1</summary>

Un runner `shell` exécute les jobs avec le `PATH` d'un shell de connexion de `gitlab-runner`, pas avec le tien. Regarde aussi ce que fait `sudo` à l'environnement, et où l'introduction a installé chaque outil sur `adm01`.
</details>

<details><summary>Indice 2</summary>

`rules:changes` ne s'évalue de façon fiable que dans les pipelines de MR (comparaison avec la branche cible) ; ailleurs, il est toujours vrai ou dépend du dernier push. Les mots-clés `artifacts:when`, `artifacts:reports:junit` et `coverage` sont décrits dans la référence `.gitlab-ci.yml`.
</details>

<details><summary>Indice 3</summary>

Le gabarit `qualite.yml` fixe déjà `stages` et `workflow` : un projet qui les redéfinit remplace ceux du gabarit. Ne le fais que si tu en as besoin.
</details>

**Pour aller plus loin** (facultatif) : `needs` pour démarrer `pytest` sans attendre `shellcheck` ; cache de `uv` (`UV_CACHE_DIR`) et nettoyage des répertoires de build d'un runner `shell` ; [référence `.gitlab-ci.yml`](https://docs.gitlab.com/ci/yaml/), [rapports JUnit](https://docs.gitlab.com/ci/testing/unit_test_reports/), [couverture](https://docs.gitlab.com/ci/testing/code_coverage/).

---

### M02-E25 — Empaqueter, versionner et distribuer `medictl`  `LAB` `★★★`

> **Ticket DEV-355** — *De : Julien Petit*
> Mon équipe voudrait utiliser `medictl` pour créer ses VMs de recette dans la sandbox. Aujourd'hui, il faut cloner votre dépôt et lancer `task install` : on se retrouve avec « la version de la branche de quelqu'un ». On voudrait un `medictl` installable en une commande, avec un vrai numéro de version, et une mise à jour aussi simple.
> *Karim, en commentaire* : publication par la CI uniquement, à chaque release semantic-release, dans le registre de paquets de GitLab. Personne ne publie depuis son poste.

**Objectifs pédagogiques**
- Comprendre la chaîne « commit conventionnel → étiquette → paquet » et choisir où vit le numéro de version.
- Publier un paquet Python dans le registre PyPI de GitLab depuis la CI, avec le jeton de job.
- Installer et mettre à jour un outil depuis un index privé avec `uv tool`, sans exposer de secret.
- Mesurer les risques d'un index privé : confusion de dépendances, redirection vers PyPI, certificats.

**Prérequis** : M02-E07, M02-E15 (`medictl --version` lit les métadonnées du paquet installé), M02-E24, M01-E25 (semantic-release, jeton `bot-release`, étiquettes `v*` protégées).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Registre PyPI du projet : publication sur `https://git01.par1.medisphere.internal/api/v4/projects/<ID-PROJET>/packages/pypi`, installation depuis `…/packages/pypi/simple`. `<ID-PROJET>` : identifiant numérique de `plateforme/outils` (page d'accueil du projet, ou API).
- Authentification documentée par GitLab : jeton de job CI (utilisateur `gitlab-ci-token`), jeton de déploiement (portées `read_package_registry` / `write_package_registry`), jeton personnel (portée `api`). Publier deux fois le même fichier est refusé (`400`).
- Par défaut, GitLab **redirige vers pypi.org** les demandes de paquets qu'il ne connaît pas (« Package forwarding », réglage de groupe).
- uv 0.12 : `uv version`, `uv build`, `uv publish` (variables `UV_PUBLISH_*`), `uv tool install --index <NOM>=<URL>`, `uv auth login`. **uv n'utilise pas le magasin de certificats du système par défaut** (racines Mozilla embarquées) : vois l'option `system-certs`.
- Le gabarit `release.yml` (M01) lance semantic-release dans le pipeline de `main` ; le gabarit `qualite.yml` ne crée **pas** de pipeline sur les étiquettes. Rien n'est commité dans `main` par la release.

**Travail demandé**
1. **Où vit la version ?** Avant d'écrire une ligne, compare dans ton journal trois mécanismes : (a) un plugin semantic-release qui modifie `pyproject.toml` puis commite ; (b) une version calculée à la construction depuis l'étiquette Git (plugin de *build* dynamique) ; (c) la version de l'étiquette injectée dans la copie de travail du job de publication, sans commit. Pour chacun : qui écrit le numéro, que devient `main`, que se passe-t-il si la publication échoue après la pose de l'étiquette, quels outils supplémentaires faut-il sur `runner01`. Choisis, et respecte les contraintes de M01 (rien n'est commité dans `main`).
2. **Le paquet.** Vérifie les métadonnées de `pyproject.toml` (description, `readme`, `requires-python`, point d'entrée `medictl`) et que `medictl --version` affiche la version des **métadonnées** du paquet installé. Construis en local (`uv build`) et inspecte la roue : que contient-elle, que ne contient-elle pas (tests, `bin/`) ?
3. **La publication.** Ajoute à la CI un job de publication qui ne tourne que sur `main` protégée, après `release`, ne fait rien si ce pipeline n'a pas produit de version, construit le paquet **à la version de l'étiquette**, vérifie que c'est bien elle, et le publie avec le jeton de job, **sans** secret en argument de commande. Il doit pouvoir être relancé sans erreur si une partie des fichiers est déjà publiée.
4. **Une release.** Fusionne une MR `feat(medictl): …` (une petite amélioration réelle, par exemple un message d'aide). Suis la chaîne : étiquette, release GitLab, job de publication, paquet dans *Deploy → Package registry* avec une roue et une archive source.
5. **Le registre en lecture.** Désactive la redirection vers pypi.org pour le groupe `plateforme`. Crée un **jeton de déploiement** du projet limité à la lecture du registre, avec une expiration, et inscris-le au registre des secrets (M01). Explique dans ton journal ce qu'un attaquant pourrait faire si la redirection restait active et que quelqu'un publiait un paquet `medictl` sur pypi.org, et ce qui t'en protège aussi côté uv.
6. **L'installation sur `adm01`.** Retire l'installation de développement (`uv tool uninstall medictl`), puis installe `medictl` **depuis le registre** (désormais, sur `adm01`, les scripts s'installent par `task install:systeme` seule : `task install` remettrait le `medictl` du clone) : identifiants rangés par `uv auth login` (secret lu sur l'entrée standard, jamais en argument), magasin d'identifiants en 600, certificats du système activés dans `~/.config/uv/uv.toml`. Vérifie `medictl --version`. Lis le reçu d'installation de uv (`uv tool dir`) : qu'y trouve-t-on, et qu'est-ce qui n'y est pas ?
7. **La mise à jour.** Publie une seconde version (correctif `fix(medictl): …`), puis mets à jour sur `adm01` avec `uv tool upgrade medictl`. Note la procédure de retour à la version précédente.

**Critères de réussite**
- [ ] La dernière étiquette `vX.Y.Z` de `plateforme/outils` a sa release GitLab et son paquet `medictl` X.Y.Z dans le registre du projet (roue + archive source), publié par un pipeline de `main`.
- [ ] `medictl --version` sur `adm01` affiche cette version ; l'outil a été installé depuis le registre de `git01`, pas depuis un répertoire.
- [ ] Aucun identifiant dans le reçu d'installation ni dans `.gitlab-ci.yml` ; le magasin d'identifiants de uv n'est lisible que par toi.
- [ ] La redirection vers pypi.org est désactivée pour le groupe `plateforme` ; le jeton de déploiement n'a que la portée de lecture du registre.
- [ ] Le choix du mécanisme de version est justifié dans ton journal.

**Vérification** : `lab/bin/check 02 25`

<details><summary>Indice 1</summary>

Regarde comment le projet `plateforme/ci-templates` (M01-E25) avance sa branche `v1` après une release : un job qui suit `release` dans le même pipeline et qui cherche l'étiquette posée sur le commit courant. Le même schéma convient ici.
</details>

<details><summary>Indice 2</summary>

`uv version --help` : regarde ce que font `--frozen` et `--dry-run`. `uv publish --help` : toutes les options ont une variable d'environnement équivalente, dont l'URL de vérification des fichiers déjà publiés. Dans `variables:` d'un job, une variable peut en référencer une autre (`$CI_JOB_TOKEN`).
</details>

<details><summary>Indice 3</summary>

Une erreur `invalid peer certificate: UnknownIssuer` sur `git01` ne vient ni de GitLab ni du jeton : relis le contexte technique sur les certificats. Pour les identifiants, `uv auth login --help` ; vérifie ensuite les droits du fichier créé (`uv auth dir`).
</details>

**Pour aller plus loin** (facultatif) : lien vers le paquet dans la release (option `assets` de `@semantic-release/gitlab`) ; registre au niveau du groupe pour plusieurs projets ; signature et attestation des paquets ; [registre PyPI de GitLab](https://docs.gitlab.com/user/packages/pypi_repository/), [uv : index](https://docs.astral.sh/uv/concepts/indexes/), [uv : publication](https://docs.astral.sh/uv/guides/package/), [uv : certificats](https://docs.astral.sh/uv/concepts/authentication/certificates/).

---

### M02-E26 — Contrôle planifié des sauvegardes PBS avec un timer systemd  `LAB` `★★`

> **Ticket PLAT-356** — *De : Nadia Roussel*
> Les notifications de PBS (M00-E29) me disent quand une sauvegarde **échoue**. Elles ne me disent pas quand une sauvegarde **n'a pas eu lieu** : VM sortie du pool, tâche désactivée, `pbs01` éteint toute la nuit… Silence radio.
> Je veux un contrôle chaque matin à 07:30 : chaque VM du socle a-t-elle une sauvegarde de moins de 26 h ? Si non, ou si le contrôle lui-même n'a pas pu se faire, je veux une alerte, pas une ligne perdue dans un journal.
> *Sophie Laurent, en commentaire* : ce contrôle tourne tous les jours sans surveillance. Il n'aura que des droits de **lecture**. Pas question de lui confier le jeton qui crée et détruit des VMs.

**Objectifs pédagogiques**
- Écrire un contrôle qui ne confond jamais « rien à signaler » et « rien vu ».
- Concevoir des jetons Proxmox VE et PBS à privilèges minimaux, et vérifier ce que l'API laisse réellement voir.
- Épingler le certificat autosigné de PBS sans désactiver la vérification TLS.
- Planifier avec un service et un timer systemd (oneshot, `Persistent`, durcissement), et brancher une alerte sur l'échec (`OnFailure=`).

**Prérequis** : M00-E17 (jetons, rôle `WBAutomation`), M00-E20/E22 (PBS, `ds-lab`, namespace `par1`, stockage `pbs-par2`, tâche `lab-nuit` à 02:30), M00-E30 (timer systemd), M02-E10 (`pve_api`, `MS_PVE_ENV_FILE`), M02-E14.
**Durée indicative** : 2 h 30.

**Contexte technique**
- VMs à contrôler : celles du pool `lab` portant l'étiquette Proxmox `socle` (pas les templates).
- Script : `bin/ms-verif-sauvegardes [-a|--age-max HEURES] [-e|--etiquette ETIQUETTE]`, seuil par défaut 26 h, codes 0 (tout est sauvegardé), 1 (au moins une VM en défaut **ou** contrôle impossible), 2 (usage).
- Configuration (600) : `~/.config/workbook/pve-lecture.env` (même format que `pve-api.env`, jeton dédié `wb-automation@pve!lecture`), et un fichier pour l'accès à PBS si tu en as besoin, `~/.config/workbook/pbs-lecture.env`.
- `adm01` joint `pbs01` (10.20.10.10) sur 8007 à travers le tunnel (M00-E20/E21). Le certificat de PBS est autosigné ; son empreinte SHA-256 est enregistrée dans le stockage `pbs-par2` de `pve01` (`/etc/pve/storage.cfg`).
- Unités système sur `adm01` : `/etc/systemd/system/ms-verif-sauvegardes.service` (oneshot, `User=admin`) et `.timer` (07:30 tous les jours, rattrapage). Gestionnaire d'échec imposé : unité gabarit `ms-alerte@.service`, déclenchée par `OnFailure=` (systemd ≥ 251 transmet au gestionnaire des variables `MONITOR_*` : vois `man systemd.exec`).

> ⚠️ **Attention** : tu crées des jetons et des ACL sur `pve01` et `pbs01`. Ne modifie **pas** les droits du jeton `wb-automation@pve!lab` ni ceux de `wb-backup@pbs!pve01` (sauvegardes de `pve01`) : crée des identités nouvelles, et note comment les révoquer.

**Travail demandé**
1. **Le jeton naïf.** Crée le jeton `wb-automation@pve!lecture` (séparation des privilèges, expiration) et range-le dans `pve-lecture.env`. Donne-lui le rôle `PVEAuditor` sur `/pool/lab` ; sur `/storage/pbs-par2`, donne ce même rôle **au jeton et à l'utilisateur** `wb-automation@pve` (rappel de M00-E17 : les droits d'un jeton à privilèges séparés sont l'intersection des siens et de ceux de son utilisateur). Avec lui, liste les VMs du pool et le contenu de sauvegarde du stockage :
   ```
   admin@adm01:~$ MS_PVE_ENV_FILE=~/.config/workbook/pve-lecture.env bash -c \
       'source ~/src/outils/lib/ms-commun.sh; pve_api GET /nodes/<NOEUD>/storage/pbs-par2/content content=backup | jq length'
   ```
   Compare avec le même appel fait avec ton compte `wb-admin` dans l'interface. Explique l'écart en lisant la section *Permissions* de cet appel dans la documentation de l'API, puis le code qui filtre chaque volume (`check_volume_access` dans `PVE/Storage.pm`, dépôt `pve-storage`). Quels privilèges faudrait-il pour voir les sauvegardes par cette voie, et que permettraient-ils d'autre ? Écris la conclusion dans ton journal et présente-la à Sophie : quelle source interroger, avec quelle identité ?
2. **Les bons jetons.** Mets en œuvre ta conclusion : chaque jeton ne doit avoir **que** des privilèges de lecture (`*.Audit`). Vérifie les droits effectifs de chacun (`pveum user token permissions`, `proxmox-backup-manager user permissions`). Si tu interroges PBS directement, établis la confiance TLS : récupère le certificat présenté par `pbs01`, **compare son empreinte** à celle de `storage.cfg` avant de lui faire confiance, et épingle-le côté client (`curl --pinnedpubkey`, lis sa documentation : que se passe-t-il quand la vérification de chaîne est désactivée ?). Aucun secret en argument de commande. Inscris chaque nouveau jeton (portée, emplacement, expiration, commande de révocation) au registre des secrets de `plateforme/medisphere` (M01).
3. **Le script.** Écris `bin/ms-verif-sauvegardes`, avec ses tests bats (API simulées). Il doit au minimum : refuser un fichier de secrets lisible par d'autres ; ne pas hériter par erreur des variables `PVE_*` de l'appelant ; signaler par VM la date et l'âge de la dernière sauvegarde, et l'état de sa dernière vérification PBS si elle existe ; échouer si une VM n'a pas de sauvegarde récente, si la dernière vérification a échoué, si une API ne répond pas, **et si la liste des VMs du socle est vide**.
4. **L'installation.** Le service n'exécute jamais la copie de travail : il exécute ce que la tâche `install:systeme` du Taskfile (E20) a copié dans `/usr/local` (propriétaire root). Vérifie qu'elle installe bien les nouveaux scripts de cet exercice, puis lance-la. Note dans ton journal pourquoi un lien vers `~/src/outils` serait une mauvaise idée pour un service planifié.
5. **Les unités.** Écris le service, le timer et `ms-alerte@.service` (+ son script, qui écrit dans le journal une alerte de priorité `crit` contenant le nom de l'unité, son résultat et les dernières lignes de **son** exécution). Durcis le service (`ProtectSystem`, `ProtectHome`, `NoNewPrivileges`…) sans l'empêcher de lire ce dont il a besoin. Valide avec `systemd-analyze verify`, active le timer, vérifie la prochaine échéance (`systemctl list-timers`).
6. **Les deux chemins.** Lance le service par `systemctl start` : il doit réussir. Puis provoque un échec **sans casser les sauvegardes** (un seuil volontairement trop bas, posé par un *drop-in* temporaire que tu retires ensuite) et vérifie que l'alerte arrive dans le journal avec les lignes utiles. Retire le drop-in.
7. **Le guide.** Ajoute à `docs/astreinte.md` (créé en E31, ou une première version maintenant) : que faire quand l'alerte tombe.

**Critères de réussite**
- [ ] Le service est oneshot, tourne en `admin`, exécute une copie installée sous `/usr/local`, et déclenche `ms-alerte@…` en cas d'échec.
- [ ] Le timer est activé, actif, planifié à 07:30 chaque jour, avec rattrapage ; le service a déjà tourné sous systemd.
- [ ] Le journal contient une alerte `ms-alerte` de moins de 30 jours issue du test d'échec.
- [ ] Les fichiers de secrets sont en 600 ; les jetons utilisés n'ont que des privilèges `*.Audit` ; le script installé ne contient aucun secret.
- [ ] Lancé maintenant, le contrôle répond 0 (le socle est sauvegardé) ; un argument absurde donne 2.

**Vérification** : `lab/bin/check 02 26`

<details><summary>Indice 1</summary>

Une liste vide renvoyée avec un code HTTP 200 n'est pas une erreur pour l'API. Pour un contrôle, c'est le pire des cas : « je n'ai rien vu » ressemble à « tout va bien ». Chaque fois qu'un ensemble attendu est vide, ton script doit s'en inquiéter.
</details>

<details><summary>Indice 2</summary>

PBS a sa propre API (port 8007, `/api2/json`) et ses propres rôles ; l'en-tête d'un jeton y a la forme `Authorization: PBSAPIToken=<utilisateur>@<royaume>!<jeton>:<secret>`. La documentation de l'API PBS indique, pour chaque appel, les privilèges requis : cherche ceux qui listent les instantanés ou les groupes d'un datastore. Les droits d'un jeton PBS sont l'intersection des siens et de ceux de son utilisateur (M00-E22).
</details>

<details><summary>Indice 3</summary>

`systemctl edit ms-verif-sauvegardes.service` crée un drop-in dans `/etc/systemd/system/ms-verif-sauvegardes.service.d/`. Une variable d'environnement ou une option du script suffit à abaisser le seuil. Pour le gestionnaire d'échec, la forme `OnFailure=ms-alerte@%n.service` est recommandée par la documentation : pourquoi une unité gabarit plutôt qu'une unité unique ?
</details>

**Pour aller plus loin** (facultatif) : envoyer aussi l'alerte vers la cible webhook de M00-E29 (une variable `MS_ALERTE_WEBHOOK` dans un fichier d'environnement root) ; exposer l'âge de la dernière sauvegarde comme métrique (collecteur de fichiers texte de node_exporter, module 21) ; [systemd.timer](https://www.freedesktop.org/software/systemd/man/latest/systemd.timer.html), [API PBS](https://pbs.proxmox.com/docs/api-viewer/), [gestion des utilisateurs PBS](https://pbs.proxmox.com/docs/user-management.html).

---

### M02-E27 — Idempotence et `--dry-run`  `LIBRE` `★★★`

> **Incident INC-2801, transmis en ticket PLAT-357** — *De : Nadia Roussel*
> Mardi soir, intervention sur `git01`. J'ai lancé `ms-snapshot 1004` ; la session SSH a sauté pendant l'attente. Je l'ai relancé deux fois (on ne savait pas s'il avait fini). Résultat : trois instantanés en cinq minutes, et la rotation (`--keep 3`) a supprimé celui de la veille, notre vrai point de retour. Le lendemain, un `--dry-run` m'a annoncé une suppression qui n'a pas eu lieu à l'exécution réelle.
> Je veux un `ms-snapshot` que je peux relancer autant de fois que je veux sans rien perdre, et un `--dry-run` qui dit **exactement** ce que fera la vraie commande.

**Objectifs pédagogiques**
- Raisonner en état visé plutôt qu'en actions : définir ce qu'« idempotent » veut dire pour un outil donné.
- Séparer le calcul d'un plan de son application, pour une simulation qui ne peut pas mentir.
- Rendre un outil sûr face aux relances, aux interruptions, aux verrous et aux échecs partiels.
- Prouver ces propriétés par des tests automatisés.

**Prérequis** : M02-E11, M02-E13 (verrou), M02-E14 (tests bats de `ms-snapshot`), M02-E16 (`medictl vm create`), M02-E24.
**Durée indicative** : 3 h.

**Contraintes**
- L'interface de `ms-snapshot` reste compatible : mêmes options, mêmes codes retour, même format de nom `<PRÉFIXE>-AAAAMMJJ-HHMMSS`. Tu peux ajouter des options.
- Une relance de la même commande **dans la demi-heure** ne crée pas de nouvel instantané si celui de la première exécution existe : le point de retour d'avant l'intervention est conservé (un moyen de forcer un nouvel instantané reste possible).
- Relancée après une interruption (perte de session, Ctrl-C, arrêt) à n'importe quel moment, la commande termine le travail sans doublon ni perte.
- `--dry-run` n'envoie aucune requête d'écriture à l'API et affiche **sur la sortie standard** le plan, une action par ligne, sous une forme exploitable par un programme ; ce plan est identique à ce que ferait l'exécution réelle dans le même état.
- Une VM verrouillée par Proxmox (tâche en cours ou interrompue) n'est jamais touchée ; si la création échoue, rien n'est supprimé sur cette VM.
- Seuls les instantanés au format exact sont concernés par la rotation : les instantanés posés à la main ne disparaissent jamais, même si leur nom commence par le préfixe.
- Les tests bats prouvent ces propriétés sans toucher au vrai Proxmox : au moins un test dont le nom contient « dry-run » et trois dont le nom contient « idempotence » (vérification).
- **Démonstration** sur une VM jetable **2027** `m02-idem` (clonée du template 9000 avec `medictl vm create`, pool `lab`, VNet `vsandbox`, étiquette `env-m02`) : pose à la main deux instantanés `avant-manuel` et `avant-maj-demo`, puis mène un scénario d'au moins cinq exécutions avec `--keep 2` (dont une interrompue pendant l'attente de la tâche, une relance immédiate, et une forcée). État final attendu : exactement deux instantanés gérés, les deux manuels intacts, aucun verrou. Vérifie (`lab/bin/check 02 27`), **puis détruis la VM 2027**.

**Critères de réussite**
- [ ] Le scénario de démonstration et son état final sont notés dans ton journal (commandes, sorties de `--dry-run`, état après chaque exécution).
- [ ] La VM 2027 a, à la vérification, exactement deux instantanés `avant-AAAAMMJJ-HHMMSS`, `avant-manuel` et `avant-maj-demo`, et aucun verrou.
- [ ] Les tests bats de dry-run et d'idempotence passent dans le dernier pipeline de `main`.
- [ ] Ta définition de l'idempotence de `ms-snapshot` (l'état visé, en une phrase) est écrite dans l'aide de l'outil ou dans son en-tête.
- [ ] La VM 2027 est détruite après la vérification.

**Vérification** : `lab/bin/check 02 27` (avant de détruire la VM 2027)

<details><summary>Indice 1</summary>

« Créer un instantané » n'est pas idempotent par nature. « Garantir qu'un point de retour récent existe et qu'il n'y en a pas plus de N » l'est. Commence par écrire cet état visé, puis demande-toi, pour chaque état de départ possible, quelles actions y mènent.
</details>

<details><summary>Indice 2</summary>

Si la simulation et l'exécution prennent deux chemins de code différents, elles finiront par diverger. Une fonction qui reçoit l'état (configuration de la VM, liste des instantanés avec leur `snaptime`, heure courante) et produit le plan, sans appel réseau, se teste aussi très bien.
</details>

<details><summary>Indice 3</summary>

Une tâche Proxmox continue côté serveur quand le client qui l'a lancée disparaît. Pendant qu'elle tourne, la configuration de la VM porte un champ `lock`. Pour interrompre proprement une attente, relis ce que la bibliothèque commune fait d'un signal… et ce qu'elle n'en fait pas.
</details>

**Pour aller plus loin** (facultatif) : un mode `--json` du plan ; le même raisonnement appliqué à `medictl vm create` (relancer une création interrompue) ; la notion de *convergence* d'Ansible (module 04) et le `plan` d'OpenTofu (module 05).

---

### M02-E28 — Paralléliser sans se tirer une balle dans le pied  `LAB` `★★★`

> **Ticket PLAT-358** — *De : Karim Benali*
> Lucas a écrit `ms-etat-hotes`, un relevé rapide du socle (noyau, date de démarrage, disque, mises à jour en attente). Il interroge les hôtes l'un après l'autre : quand un hôte ne répond pas, on attend son délai, puis le suivant… Au M06, on aura le double d'hôtes.
> Parallélise-le. Mais je veux la même sortie, dans le même ordre, le même code retour, et pas de surprise : pas de lignes mélangées, pas de connexions qui survivent à un Ctrl-C, pas de serveur assommé.

**Objectifs pédagogiques**
- Paralléliser des tâches indépendantes avec trois outils : `xargs -P`, GNU parallel, et Bash seul (`wait -n`).
- Préserver l'ordre et l'intégrité des sorties, et ne perdre aucun code d'erreur.
- Limiter la concurrence, et connaître les limites des serveurs (sshd, multiplexage SSH, API).
- Mesurer avant et après.

**Prérequis** : M02-E10, M02-E13 (fichiers temporaires, `trap`), M02-E14, M02-E24.
**Durée indicative** : 2 h 30.

**Contexte technique**
- Version séquentielle fournie : [`ressources/M02-E28/ms-etat-hotes`](../ressources/M02-E28/ms-etat-hotes). Lis son en-tête : format de sortie (TSV, une ligne par hôte, ordre des arguments, champ `ETAT` = `ok`, `injoignable` ou `erreur`) et codes retour. Copie-la dans `bin/` du projet.
- Interface cible : `ms-etat-hotes [-j|--jobs N] HOTE...`, `N` de 1 à 32, défaut 4 ; sortie et codes retour **identiques** à la version séquentielle.
- Hôtes réels : `gw01`, `dns01`, `git01`, `runner01` (alias SSH de `adm01`). Hôte injoignable pour les essais : `admin@10.10.99.250` (plage réservée aux tests du VLAN SANDBOX, aucune machine ne la porte).
- GNU parallel : paquet Debian `parallel` (version 20240222 sur Debian 13).
- `adm01` multiplexe ses connexions SSH (M00-E15 : `ControlMaster`/`ControlPersist`).

**Travail demandé**
1. **Mesure de départ.** Chronomètre la version séquentielle sur les quatre hôtes réels, puis avec deux hôtes injoignables en plus. Note les temps.
2. **Version `xargs`.** Parallélise avec `xargs -P`. Avant d'écrire, lis dans `man xargs` ce qui se passe quand une commande lancée sort avec le code 255, et ce que renvoie `ssh` quand la connexion échoue. Teste avec un hôte injoignable placé **au milieu** de la liste : tous les hôtes suivants sont-ils interrogés ? Garde l'ordre de sortie.
3. **Version GNU parallel.** Même chose avec `parallel`. Quelles options remplacent ce que tu as dû bricoler avec `xargs` (ordre, étiquettes, journal des jobs, délai maximal par job) ? Que vaut son code retour ?
4. **Version Bash.** Même chose en Bash seul, avec `wait -n` : au plus `N` connexions en vol, une sortie par hôte dans un fichier d'un répertoire temporaire supprimé quoi qu'il arrive, assemblage dans l'ordre des arguments. Qu'arrive-t-il aux connexions en cours si l'on fait Ctrl-C ? Fais en sorte qu'il n'en reste aucune (vérifie avec `pgrep -a ssh`).
5. **Choix.** Retiens une version pour `bin/ms-etat-hotes` (dépendances, lisibilité, robustesse) et justifie-la dans la MR. Écris ses tests bats **sans réseau**, en remplaçant `ssh` par un faux programme placé en tête du `PATH` : ordre, hôte injoignable au milieu, borne `-j`, absence de fichiers temporaires résiduels, gain de temps mesurable.
6. **Les limites.** Lance ta version avec `-j 16` sur **un même hôte** répété seize fois (`git01` × 16). Observe et explique : ce que disent `MaxStartups` et `MaxSessions` de `sshd` (`man sshd_config`), et ce que change le multiplexage de `adm01`. Quelle valeur par défaut de `-j` retiens-tu, et quelle règle donnerais-tu pour paralléliser des appels à l'API Proxmox ?
7. **Mesure finale.** Refais les mesures de l'étape 1 et note le gain.

**Critères de réussite**
- [ ] `bin/ms-etat-hotes -j 8` sur 8 hôtes (dont 2 injoignables) produit 8 lignes dans l'ordre des arguments, 6 `ok` et 2 `injoignable`, un code 1, en nettement moins de temps que la version séquentielle.
- [ ] Un hôte injoignable au milieu de la liste n'empêche pas d'interroger les suivants.
- [ ] `-j` borne réellement le nombre de connexions simultanées ; `-j 0` est une erreur d'usage (2).
- [ ] Les tests bats de `ms-etat-hotes` passent en CI, sans réseau.
- [ ] Les mesures, le choix de l'outil et l'analyse des limites (sshd, multiplexage, API) sont dans ton journal.

**Vérification** : `lab/bin/check 02 28` (il lance ta version avec un faux `ssh` qui dure 2 s par hôte, puis un relevé réel du socle)

<details><summary>Indice 1</summary>

`xargs` ne lance que des programmes, pas des fonctions Bash : un script peut s'appeler lui-même avec une option interne (« fais un seul hôte »). Pour retrouver l'ordre, chaque ligne peut porter l'index de son hôte, retiré après un tri.
</details>

<details><summary>Indice 2</summary>

Dans un script non interactif, les commandes lancées en arrière-plan ignorent SIGINT : un Ctrl-C tue le script, pas forcément ses enfants. `jobs -p` donne les PID des jobs ; chaque job peut lui-même avoir des enfants (le `ssh`).
</details>

<details><summary>Indice 3</summary>

Le code retour d'un job qui s'est mal terminé peut se perdre (ordre de `wait`, sous-shells). Le résultat de chaque hôte est déjà écrit dans sa ligne : le code final peut se déduire des lignes elles-mêmes.
</details>

**Pour aller plus loin** (facultatif) : la même collecte en Python avec `concurrent.futures.ThreadPoolExecutor` et `subprocess.run(timeout=…)` ; `bats --jobs` pour paralléliser… les tests ; [GNU parallel](https://www.gnu.org/software/parallel/parallel.html), `man xargs`, `help wait`.

---

### M02-E29 — Durcir un script lancé avec `sudo`  `LAB` `★★★`

> **Ticket SEC-359** — *De : Sophie Laurent*
> Lucas propose d'autoriser l'astreinte à lancer son script de collecte de diagnostic `ms-diag` en root par `sudo`, « pour que Nadia puisse envoyer un dossier au support sans avoir les droits root ». L'idée est bonne. La mise en œuvre (ressource jointe) donne root à quiconque sait taper une commande.
> Je veux un `ms-diag` que je peux autoriser en `sudo` sans craindre qu'on s'en serve pour devenir root, lire ce qu'on ne doit pas lire, ou écrire où l'on ne doit pas écrire. Démontre-moi que les attaques ne passent plus.

**Objectifs pédagogiques**
- Identifier les chemins d'élévation de privilèges d'un script lancé par `sudo` : fichiers modifiables, environnement, arguments, programmes interactifs, chemins choisis par l'appelant, fichiers temporaires.
- Écrire une règle `sudoers` minimale et la valider sans risquer de se verrouiller.
- Durcir un script privilégié : environnement, validation par liste blanche, sorties, audit.
- Vérifier par l'attaque que les protections tiennent.

**Prérequis** : M02-E03, M02-E10, M02-E13, M02-E22 (revue de script).
**Durée indicative** : 3 h.

**Contexte technique**
- Version de Lucas : [`ressources/M02-E29/ms-diag`](../ressources/M02-E29/ms-diag), avec son installation proposée en en-tête. ⚠️ **Ne l'installe pas telle quelle** en dehors des essais de l'étape 2.
- Cible : `/usr/local/sbin/ms-diag [--depuis HEURES] UNITE...` sur `adm01`, autorisé par `sudo` au groupe local `astreinte`. Compte de test **sans privilège** : `astreinte01`, membre de `astreinte` seulement, shell `/usr/sbin/nologin`, sans mot de passe (tu l'utilises par `sudo -u astreinte01 …` depuis `admin`).
- Règle dans `/etc/sudoers.d/ms-diag` ; `sudo` de Debian 13 accepte des expressions régulières dans les arguments d'une règle (`man sudoers`, section *Regular expressions*).
- Exigences de Sophie : l'archive de diagnostic ne contient aucune clé privée (hôte ou utilisateur), aucun fichier de mots de passe, aucun fichier `.env` ; chaque utilisation laisse une trace dans le journal sous l'identifiant `ms-diag`, avec le nom de l'appelant.

> ⚠️ **Attention — sudo** : une erreur de syntaxe dans un fichier de `/etc/sudoers.d/` peut désactiver `sudo` pour tout le monde. Écris toujours le fichier ailleurs, valide-le avec `visudo -cf <FICHIER>`, et ne l'installe qu'ensuite (`install -m 0440`) ; garde une session root ouverte (`sudo -i`) pendant les essais. En cas de problème : `pkexec` n'est pas là pour te sauver ; la console Proxmox de `adm01` et le mot de passe root (ou un démarrage en mode secours) le sont.

**Travail demandé**
1. **Lecture.** Lis le script et son installation. Lance `shellcheck` dessus : que trouve-t-il, et que ne trouve-t-il **pas** ? Liste dans ton journal au moins six faiblesses de sécurité, chacune avec son scénario d'attaque concret (qui, quelle commande, quel résultat).
2. **Preuves.** Installe la version de Lucas dans un état contrôlé (le lien de son en-tête, la règle sudo de son en-tête, le compte `astreinte01`), et démontre **trois** attaques depuis `astreinte01` : une écriture arbitraire en root, une lecture de secret, et l'obtention d'un shell root. Désinstalle tout ensuite (lien, règle) et vérifie avec `sudo -l -U astreinte01`.
3. **Le script durci.** Écris `ms-diag` durci et installe-le dans `/usr/local/sbin`. À toi de concevoir, mais chaque faiblesse de l'étape 1 doit être traitée. Interrogations à trancher (et justifier) : où écrire l'archive, et avec quels droits ? Quels arguments accepter ? Quel `PATH`, quelles variables d'environnement, quel `umask` ? Quel shebang ? Faut-il charger `lib/ms-commun.sh`, et d'où ? Que collecter, que retirer ou masquer ?
4. **La règle sudo.** Écris `/etc/sudoers.d/ms-diag` : le groupe `astreinte`, ce seul programme, en root seulement. Valide-la, installe-la, vérifie `sudo -l -U astreinte01`. Décide si tu restreins aussi les arguments dans la règle (et pourquoi la validation dans le script reste nécessaire).
5. **Contre-preuves.** Rejoue les trois attaques de l'étape 2 contre ta version, plus : un argument qui contient `;`, `../`, une option `--…` ; une unité qui n'existe pas ; une sortie vers un terminal. Tout doit être refusé proprement (code ≠ 0, aucune archive). Montre dans le journal la ligne d'audit d'une collecte réussie.
6. **Le projet.** Versionne le script (par exemple `sbin/ms-diag`) et la règle dans `plateforme/outils`, avec des tests bats de la validation des arguments. Note : comment le script est-il livré sur une machine, et qui a le droit de le modifier ?

**Critères de réussite**
- [ ] `/usr/local/sbin/ms-diag` est un fichier ordinaire appartenant à root, que personne d'autre ne peut modifier (dossiers parents compris), et qui ne dépend d'aucun fichier sous `/home`.
- [ ] `/etc/sudoers.d/ms-diag` est valide, en 0440 ; `astreinte01` (membre de `astreinte`, pas de `sudo`) n'a que ce droit-là, en root.
- [ ] `sudo ms-diag ssh.service` lancé par `astreinte01` produit une archive d'au moins trois fichiers, sans clé privée, `shadow` ni `.env` ; une ligne d'audit `ms-diag` nomme `astreinte01`.
- [ ] Les arguments malveillants et une sortie vers un terminal sont refusés, sans archive.
- [ ] Les six faiblesses, les trois attaques et leurs contre-preuves sont dans ton journal.

**Vérification** : `lab/bin/check 02 29`

<details><summary>Indice 1</summary>

Pour chaque fichier que `sudo` fera exécuter ou lire à root (le script, ce qu'il charge, les dossiers qui les contiennent), pose la question : qui peut le modifier ? Un lien symbolique vers un clone de travail répond « admin ». Et pour chaque programme lancé : peut-il ouvrir un pager, un éditeur, un shell ?
</details>

<details><summary>Indice 2</summary>

Quand `root` écrit dans un chemin choisi par l'appelant, l'appelant choisit ce que root écrase. Il existe un endroit où l'appelant peut recevoir des données sans que root écrive le moindre fichier : sa propre sortie standard, redirigée par **son** shell.
</details>

<details><summary>Indice 3</summary>

`sudo` nettoie déjà l'environnement (`env_reset`, `secure_path`) : regarde `sudo -V` en root. Ce n'est pas une raison pour que le script s'en remette à lui : il peut être lancé un jour par systemd, cron, ou root directement. `systemctl` et `journalctl` ont une option et une variable d'environnement pour ne jamais ouvrir de pager.
</details>

**Pour aller plus loin** (facultatif) : journalisation des entrées/sorties de sudo (`log_output`) et ses limites ; `systemd-run --uid` comme alternative à sudo pour une tâche privilégiée ponctuelle ; [GTFOBins](https://gtfobins.github.io/) pour mesurer ce qu'un programme apparemment anodin permet sous `sudo` ; `man sudoers`.

---

### M02-E30 — Signaux, délais et sous-processus  `LAB` `★★`

> **Ticket PLAT-360** — *De : Nadia Roussel*
> Après un `medictl vm create`, on attend que la VM réponde en SSH avec une boucle bricolée à la main. Hier, un `ssh` a bloqué la boucle vingt minutes sur une VM à moitié démarrée, et mon Ctrl-C n'a rien arrêté : il a fallu fermer le terminal, et le `ssh` tournait encore le lendemain.
> Je veux un outil d'attente propre : un délai total garanti, chaque essai borné, et un Ctrl-C ou un arrêt qui arrête **tout**, tout de suite.

**Objectifs pédagogiques**
- Comprendre la livraison des signaux : groupe de processus, premier et arrière-plan, signaux ignorés à l'entrée d'un shell.
- Savoir quand un `trap` Bash s'exécute réellement, et ne rien laisser derrière soi.
- Borner la durée d'une commande (`timeout`, codes 124 et 137) et d'une boucle.
- Piloter des sous-processus depuis Python (`subprocess`, délais, sessions, `killpg`) et traiter SIGTERM proprement.

**Prérequis** : M02-E03 (`trap`), M02-E10 (`retry`), M02-E17, M02-E18.
**Durée indicative** : 2 h.

**Contexte technique**
- Ressources : [`ressources/M02-E30/demo-signaux.sh`](../ressources/M02-E30/demo-signaux.sh) (trois modes d'attente d'un enfant) et [`ressources/M02-E30/demo_sous_processus.py`](../ressources/M02-E30/demo_sous_processus.py) (quatre cas commentés).
- Interface imposée de l'outil (vérification) : `ms-attendre [-d|--delai S] [-i|--intervalle S] [-e|--essai S] -- COMMANDE [ARG...]` : délai total (1-3600 s, défaut 300), pause entre essais (1-300, défaut 5), durée maximale d'un essai (1-600, défaut 30). Codes : 0 la commande a réussi, 1 délai total dépassé, 2 usage, 130 interrompu par SIGINT, 143 arrêté par SIGTERM.
- Exemple d'usage visé : `ms-attendre -d 300 -- ssh -o BatchMode=yes -o ConnectTimeout=5 admin@<IP-VM> true`.

**Travail demandé**
1. **Bash, observation.** Lance `demo-signaux.sh` dans ses trois modes. Pour chacun, envoie depuis un autre terminal `kill -TERM <PID>`, puis recommence avec Ctrl-C dans son terminal. Remplis un tableau : moment où le `trap` s'exécute, code de sortie, `sleep` orphelin ou non (`pgrep -a sleep`). Explique chaque case (groupe de processus du terminal, attente d'un enfant au premier plan par Bash, SIGINT des tâches d'arrière-plan d'un script).
2. **`timeout`.** Lis `man timeout` : codes 124 et 137, `--kill-after`, `--foreground`. Dans quel groupe de processus `timeout` place-t-il la commande, et quelle conséquence pour un Ctrl-C tapé au clavier ?
3. **Python, observation.** Lis puis lance les quatre cas de `demo_sous_processus.py`. Explique : pourquoi le petit-enfant survit dans le cas 1 ; ce que changent `start_new_session` et `os.killpg` ; pourquoi le bloc `finally` ne s'exécute pas dans le cas 3, et ce qui se passerait pour `medictl` arrêté par `systemctl stop` au milieu d'une création de VM.
4. **L'outil.** Écris `bin/ms-attendre` selon l'interface imposée, en t'appuyant sur tes observations : le délai total est tenu même si un essai bloque ; un essai qui dépasse sa durée est tué avec ses sous-processus ; SIGINT et SIGTERM arrêtent l'essai en cours et sortent **immédiatement** avec le bon code, sans orphelin ; les essais et la sortie sont journalisés sur la sortie d'erreur. Explique dans l'en-tête pourquoi `retry` de la bibliothèque ne suffisait pas.
5. **Les tests, en Python.** Écris `tests/python/test_ms_attendre.py` : `pytest` pilote `bin/ms-attendre` par `subprocess` (succès, délai dépassé, essai bloqué tué, usage) et vérifie la réaction aux signaux SIGTERM **et** SIGINT : code de sortie, délai de réaction, et absence de sous-processus orphelin. Le test doit nettoyer derrière lui même s'il échoue.
6. **Utilisation.** Crée la VM jetable **2028** `m02-attente` avec `medictl vm create … --no-wait` (étiquette `env-m02`), attends-la avec `ms-attendre` jusqu'à ce qu'elle réponde en SSH, puis détruis-la. Note les temps.

**Critères de réussite**
- [ ] `ms-attendre -- true` rend 0 immédiatement ; `-d 3 -i 1 -- false` rend 1 en 3 à 6 s ; `-d 4 -e 1 -- sleep 30` rend 1 en moins de 9 s ; un argument invalide rend 2.
- [ ] SIGTERM (resp. SIGINT) pendant un essai : sortie en moins de 2 s avec le code 143 (resp. 130), sans processus orphelin.
- [ ] Les tests pytest de `ms-attendre`, dont au moins un sur les signaux, passent dans le dernier pipeline de `main`.
- [ ] Le tableau d'observations et les explications des étapes 1 à 3 sont dans ton journal.

**Vérification** : `lab/bin/check 02 30`

<details><summary>Indice 1</summary>

Bash n'exécute le `trap` d'un signal qu'entre deux commandes : s'il attend un enfant au premier plan, le `trap` attend aussi. Le builtin `wait`, lui, est interrompu par un signal intercepté. Lance donc ce que tu veux pouvoir interrompre en arrière-plan, et attends-le.
</details>

<details><summary>Indice 2</summary>

`timeout` relaie à la commande surveillée les signaux qu'il reçoit lui-même, puis s'arrête. Il te suffit donc de savoir à qui envoyer le signal dans ton `trap`.
</details>

<details><summary>Indice 3</summary>

Dans un test pytest, `subprocess.Popen(…, start_new_session=True)` met l'outil dans sa propre session : le test peut l'arrêter avec tout son groupe (`os.killpg`) dans un `finally`. Pour retrouver un sous-processus précis, donne-lui une signature unique (par exemple `sleep 47.25`) et parcours `/proc`.
</details>

**Pour aller plus loin** (facultatif) : `KillMode=`, `TimeoutStopSec=` et `SendSIGKILL=` des services systemd ; gestion de SIGTERM dans `medictl` (annuler proprement l'attente d'une tâche Proxmox) ; [`subprocess`](https://docs.python.org/3/library/subprocess.html), [`signal`](https://docs.python.org/3/library/signal.html), `man 7 signal`, `man bash` (section SIGNALS).

---

### M02-E31 — Documenter un outil : aide, README, guide d'astreinte  `RED` `★★`

> **Ticket PLAT-361** — *De : Nadia Roussel*
> Ce week-end, d'astreinte, l'alerte de `ms-verif-sauvegardes` est tombée. J'ai ouvert le dépôt : pas de README, `--help` différent d'un outil à l'autre, rien sur « que faire quand ça sonne ». J'ai appelé Karim un dimanche.
> Je veux pouvoir me débrouiller seule, la nuit, avec la documentation.

**Objectifs pédagogiques**
- Écrire pour un lecteur précis (l'astreinte, la nuit, sans l'auteur) et dans le bon support (aide intégrée, README, guide).
- Harmoniser l'aide de tous les outils (usage, options, codes retour, configuration, exemples).
- Transformer les modes de défaillance connus en procédures de diagnostic.

**Prérequis** : M02-E24 à M02-E30 (les outils documentés), M00-E25 (runbooks).
**Durée indicative** : 2 h.

**Travail demandé**
1. **Aide intégrée.** Fais l'inventaire du `--help` de chaque outil (`bin/ms-*`, `medictl` et ses sous-commandes). Harmonise : ligne d'usage, description d'une phrase, options, **codes retour**, fichiers de configuration et variables lus, un exemple. `--help` écrit sur la sortie standard et rend 0 ; une erreur d'usage écrit l'aide sur la sortie d'erreur et rend 2.
2. **README.md** du projet, pour un nouvel arrivant : ce que contient le projet (un tableau des outils : rôle, écrit-il quelque chose, qui le lance), le contrat commun à tous les outils, l'installation (version publiée sur un poste d'administration ; scripts planifiés ; environnement de développement), la configuration et les secrets (où, quels droits, aucun secret dans le dépôt), comment contribuer, où sont les décisions (ADR).
3. **`docs/astreinte.md`**, pour l'astreinte : réflexes communs (signification des codes retour, où lire les journaux, comment connaître la version installée) ; pour chaque alerte ou outil critique, « ce que ça veut dire », les premiers gestes dans l'ordre, et un tableau symptôme → causes probables → vérification ; ce qu'il ne faut **pas** faire (contourner un garde-fou, élargir les droits d'un jeton) ; l'escalade (qui, quand).
4. **Test par un tiers.** Fais relire le guide à quelqu'un qui n'a pas écrit les outils (ou relis-le toi-même dans une semaine) avec un scénario : « alerte `ms-verif-sauvegardes` à 07:31, cause inconnue ». Corrige ce qui a bloqué.
5. Fusionne le tout par une MR (`docs: …`) ; vérifie que l'unité `ms-verif-sauvegardes.service` pointe vers le guide (`Documentation=`).

**Critères de réussite**
- [ ] Tous les outils ont une aide harmonisée qui cite leurs codes retour.
- [ ] Le README permet d'installer, configurer et contribuer sans autre source.
- [ ] Le guide d'astreinte couvre au moins : l'alerte de contrôle des sauvegardes (vraie absence de sauvegarde **et** contrôle en panne), `ms-snapshot` avant une intervention, `medictl` en échec, l'escalade.
- [ ] Le scénario de relecture et les corrections apportées sont notés dans ton journal.

Auto-évaluation : grille fournie dans le corrigé.

<details><summary>Indice 1</summary>

Un bon guide d'astreinte se lit de haut en bas sous stress : commence par ce que voit la personne (le texte de l'alerte), pas par l'architecture de l'outil. Chaque étape est une action vérifiable, avec la commande exacte.
</details>

<details><summary>Indice 2</summary>

Reprends les pannes que tu as rencontrées en écrivant les outils (droits d'un jeton, certificat, environnement de systemd, verrou) : ce sont les premières qui arriveront en production. Le palier 4 t'en fera vivre d'autres : prévois de compléter le guide.
</details>

**Pour aller plus loin** (facultatif) : pages de manuel générées (`help2man`) ; aide de Typer enrichie (`rich_help_panel`, épilogue) ; [Diátaxis](https://diataxis.fr/), cadre pour distinguer tutoriel, guide pratique, référence et explication.

---

### M02-E32 — ADR : langages des outils de la plateforme  `RED` `★★`

> **Ticket PLAT-362** — *De : Claire Morel*
> À chaque nouvel outil, le même débat : Bash ou Python ? Et la semaine dernière, Julien a proposé de tout réécrire en Go. Je veux une décision écrite, avec des critères, que Karim appliquera en revue de MR. Format habituel : un ADR.

**Objectifs pédagogiques**
- Formaliser une décision d'outillage en ADR (MADR simplifié, M00-E33), avec des critères applicables.
- Relier la décision aux contraintes de l'équipe (compétences, astreinte, sécurité, distribution) et à la suite du parcours (Ansible, OpenTofu).
- Présenter honnêtement les conséquences négatives.

**Prérequis** : M00-E33 (gabarit d'ADR), M02-E09, paliers 1 à 3 du module.
**Durée indicative** : 1 h 30.

**Travail demandé**
Rédige `docs/socle/adr/ADR-0020-langages-outils-plateforme.md` dans `plateforme/medisphere` (MR, relue comme du code), au format de M00-E33 :
1. Contexte : l'héritage InfoGér, les deux familles d'outils de `plateforme/outils`, ce que le débat récurrent coûte.
2. Au moins quatre options réellement envisagées (dont « tout Bash », « tout Python », et une option compilée), chacune avec pour et contre.
3. Une décision **applicable en revue** : des critères observables qui disent, pour un outil donné, quel langage utiliser (et pas « selon le contexte »).
4. Les exigences communes à tous les langages retenus (qualité, tests, contrat de sortie, distribution).
5. La frontière avec la gestion de configuration et l'IaC (modules 04 et 05) : qu'est-ce qui ne doit **pas** être un script ?
6. Conséquences positives, négatives, et actions induites (avec qui, quand).

**Critères de réussite**
- [ ] L'ADR suit le gabarit de M00-E33 et tient en deux pages.
- [ ] Au moins quatre options, avec pour et contre.
- [ ] Les critères de décision permettent de trancher un cas concret sans débat (essaie-les sur trois outils existants et un outil imaginaire).
- [ ] Les conséquences négatives sont écrites, avec des actions compensatoires.
- [ ] L'ADR est fusionné dans `plateforme/medisphere`.

Auto-évaluation : grille fournie dans le corrigé.

<details><summary>Indice 1</summary>

Un critère applicable se vérifie en lisant le code ou le besoin : nombre de lignes, nature des données, nombre d'API, présence de parallélisme, exécution en root… « Quand c'est complexe » n'en est pas un.
</details>

<details><summary>Indice 2</summary>

Un ADR de bonne foi dit aussi ce qu'il faudrait pour revenir sur la décision (la date ou l'événement de révision).
</details>

**Pour aller plus loin** (facultatif) : [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html), qui fixe justement une limite de taille au-delà de laquelle un script devrait changer de langage ; [MADR](https://adr.github.io/madr/).

---

### M02-E33 — Questions de production : outillage d'exploitation  `Q` `★★★`

> **Ticket PLAT-363** — *De : Karim Benali*
> Avant que je te laisse publier seul des outils que toute l'équipe installera, on fait le point. Argumente comme en revue : chiffre quand c'est possible, et dis quand « ça dépend », mais de quoi.

**Objectifs pédagogiques**
- Raisonner sur la sûreté de la chaîne de distribution d'un outil interne.
- Évaluer les compromis d'exécution (planification, concurrence, secrets, droits) en production.

**Prérequis** : paliers 1 à 3 du module.
**Durée indicative** : 1 h 30.

**Questions**

1. QCM — `uv tool install medictl --index outils=<URL-REGISTRE>` sur un poste où la redirection de GitLab vers pypi.org est active. Un attaquant publie `medictl` 99.0.0 sur pypi.org. Que se passe-t-il au prochain `uv tool upgrade medictl` ?
   a) uv installe 99.0.0, car il prend la version la plus haute tous index confondus ;
   b) uv reste sur le registre interne, où il a trouvé `medictl`, quelle que soit la version publiée ailleurs ;
   c) uv échoue, car deux index proposent le même nom ;
   d) cela dépend de `--index-strategy` et de ce que le registre interne répond.
   Puis : que change la redirection de GitLab dans ce raisonnement, et pour les **dépendances** de `medictl` (`typer`, `requests`) ?
2. Le paquet `medictl` déclare `typer>=0.27.2`, et le projet a un `uv.lock`. Lequel des deux est utilisé quand quelqu'un fait `uv tool install medictl` ? Quelle conséquence pour la reproductibilité de l'outil installé, et quelles parades existent ?
3. `medictl inventaire --format json` est utilisé par un script de Julien. Tu renommes le champ `vmid` en `id`. Quel numéro de version semantic-release doit produire, avec quel type de commit ? Qu'est-ce qui, dans une CLI, fait partie de l'« API publique » au sens de SemVer ?
4. Un collègue propose de publier le paquet depuis son poste « quand la CI est en panne ». Donne trois raisons de refuser, et ce qu'il faut à la place.
5. QCM — Le contrôle `ms-verif-sauvegardes` passe en cron au lieu de systemd. Qu'est-ce qu'on **perd** sûrement ?
   a) l'exécution à 07:30 ;
   b) le rattrapage d'une exécution manquée et la journalisation structurée par exécution ;
   c) la possibilité de lancer le script en `admin` ;
   d) l'accès au réseau.
   Et qu'est-ce qu'on perd encore, côté alerte et durcissement ?
6. Pourquoi un secret passé en argument de commande (`curl -H "Authorization: …"`) est-il plus exposé qu'en variable d'environnement, et une variable d'environnement plus exposée qu'un fichier en 600 ? Où chacun est-il visible, par qui ?
7. Un jeton en lecture seule peut-il être dangereux ? Donne deux exemples dans le lab.
8. `set -e` est actif dans un script. Cite trois situations où une commande échoue sans arrêter le script. Comment les outils de `plateforme/outils` s'en protègent-ils ?
9. Tu dois interroger l'API Proxmox pour 200 VMs. Séquentiel, 20 threads, ou 200 threads ? Raisonne : latence, nombre de *workers* de `pveproxy`, verrous côté serveur, consommation de l'API par d'autres outils, reprise en cas d'erreur 5xx.
10. QCM — En Python, pour 200 appels HTTP indépendants, `ThreadPoolExecutor` ou `ProcessPoolExecutor` ?
    a) processus, à cause du GIL ;
    b) threads : les appels attendent le réseau et le GIL est relâché pendant les entrées-sorties ;
    c) aucun des deux, il faut `asyncio` ;
    d) peu importe.
    Et un `requests.Session` partagé entre threads, est-ce sûr ?
11. Le runner `shell` de `runner01` exécute les jobs de tous les projets avec le même compte `gitlab-runner`. Quels risques entre projets (fichiers, caches, variables, jobs de MR venant d'un développeur moins privilégié) ? Quelles mesures dès maintenant, et que changeront les exécuteurs Docker/Kubernetes (modules 12 et 19) ?
12. Pourquoi `CI_JOB_TOKEN` est-il préférable à un jeton de déploiement stocké en variable CI pour publier le paquet ? Que peut faire ce jeton, pendant combien de temps ?
13. `ms-snapshot` et `ms-verif-sauvegardes` tournent sur `adm01`. Pourquoi ne pas lancer `ms-verif-sauvegardes` depuis `pve01`, qui a tout ce qu'il faut ? Et depuis `pbs01` ? Raisonne en dépendances et en domaines de panne.
14. Un outil d'exploitation devrait-il avoir des métriques ? Lesquelles pour `ms-verif-sauvegardes` et `ms-snapshot`, et comment les exposer sans serveur (module 21) ?
15. Tu reprends un script InfoGér de 600 lignes de Bash, non testé, critique (purge de journaux sur 30 serveurs). Réécrire en Python, ajouter des tests bats d'abord, ou le remplacer par Ansible ? Donne une démarche par étapes, avec ses risques.

Les réponses argumentées sont dans le corrigé.

---

### M02-E34 — Un script de vérification en temps limité  `CHRONO` `★★★`

> **Ticket PLAT-364** — *De : Nadia Roussel*
> Ce soir, je prends l'astreinte et le contrôle de santé du socle n'existe pas. Tu as une heure et demie. Le cahier des charges est prêt.

**Règles de l'épreuve**
- Conditions d'examen : pas de corrigé, pas d'IA ; autorisés : la documentation officielle, les pages de manuel, **ton** dépôt `plateforme/outils` (bibliothèque, tests et scripts existants) et ton journal.
- Durée : **90 minutes** à partir de l'ouverture du cahier des charges.
- Le cahier des charges est dans [`ressources/M02-E34/cahier-des-charges.md`](../ressources/M02-E34/cahier-des-charges.md) : ne l'ouvre qu'en lançant le chronomètre.
- L'outil ne fait que lire : aucune écriture sur les hôtes contrôlés.

**Prérequis** : M02-E10, M02-E14, M02-E24 ; un socle sain (`gw01`, `dns01`, `git01`, `runner01`, `pbs01` joignables depuis `adm01`, chrony en place depuis M00-E31).
**Durée** : 90 minutes + 20 minutes de retour d'expérience.

**Déroulé**
1. Prépare une branche `feat/ms-verif-socle` dans `~/src/outils`, ton journal, un chronomètre.
2. T0 : ouvre le cahier des charges. Lis-le **en entier** avant d'écrire du code.
3. À T0 + 90 min, arrête-toi. Commite l'état atteint, même incomplet, et lance la vérification.
4. Retour d'expérience (hors chrono) : ce qui t'a fait perdre du temps, ce que la bibliothèque commune t'a fait gagner, ce que tu ferais autrement. Termine ensuite l'outil hors délai si nécessaire et fusionne-le par une MR (il resservira).

**Feuille de temps à remplir**

| Jalon | Heure | Écart depuis T0 | Commentaire |
|---|---|---|---|
| T0 — ouverture du cahier des charges | | 0 | |
| Interface et squelette (usage, codes, boucle sur les hôtes) | | | |
| Premier contrôle fonctionnel de bout en bout sur un hôte | | | |
| Les cinq contrôles | | | |
| Sortie JSON | | | |
| Tests bats | | | |
| ShellCheck propre, commit final | | | |

**Critères de réussite**
- [ ] `lab/bin/check 02 34` est entièrement vert à T0 + 90 min (ou, à défaut, le nombre de points verts est noté, et l'épreuve est refaite une semaine plus tard).
- [ ] La feuille de temps et le retour d'expérience sont dans ton journal.

**Vérification** : `lab/bin/check 02 34`

**Pour aller plus loin** (facultatif) : refais l'épreuve en Python (sous-commande `medictl socle verifier`) et compare le temps et la robustesse obtenus ; branche la sortie JSON sur la supervision au module 21.
