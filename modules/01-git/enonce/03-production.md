# Module 01 — Palier 3 : Production

La forge existe : `git01` sert GitLab, l'équipe travaille par MR, les contrôles tournent sur les postes (pre-commit, commitlint, Gitleaks) et les règles d'équipe sont écrites. Mais rien n'empêche encore un `git commit --no-verify`, il n'y a pas d'usine pour exécuter des pipelines, les versions sont posées à la main, et personne n'a jamais restauré ni mis à jour GitLab. Claire Morel veut une forge **de production** avant que les modules suivants y déposent les scripts, les images, les rôles Ansible et le code OpenTofu de la plateforme : un runner, une CI obligatoire et partagée, des versions automatiques, des règles imposées par le serveur, des signatures vérifiables, une sauvegarde restaurée, une mise à jour maîtrisée, une supervision et un durcissement argumenté.

> ⚠️ **Rappel mémoire** : `pve01` porte déjà le socle (~12 Go avec `git01` et `runner01`). M01-E28 crée une VM de test de **8 Go** (VMID 2010) : n'aie pas de profil lourd démarré à ce moment-là, et détruis-la à la fin de l'exercice.

> ⚠️ **Rappel jetons** : plusieurs exercices manipulent des jetons (runner, bot de release, PBS). Un jeton ne s'écrit **jamais** dans un dépôt, un ticket, une capture ou l'historique du shell (`read -rs`, fichiers `600` sous `~/.config/workbook/` ou `/etc/…`, variables CI protégées et masquées).

Les vérifications de ce palier se lancent **depuis `adm01`** (`lab/bin/check 01 XX`). Les livrables documentaires vont dans `plateforme/medisphere` par MR, comme tout le reste : `docs/socle/` (runbooks `RB-010` à `RB-012`, ADR-0010, rapports) et un nouveau dossier `forge/` pour les scripts et configurations de la forge (hooks, sauvegarde, supervision, durcissement).

---

### M01-E23 — Installer GitLab Runner sur `runner01`  `LAB` `★★`

> **Ticket PLAT-250** — *De : Karim Benali*
> On a une forge, pas d'usine. Il faut un runner pour les pipelines du socle : une VM dédiée, l'exécuteur `shell` (les conteneurs arrivent au module 12), enregistré avec le nouveau flux de jetons, et rien de plus sur la machine que ce dont les jobs ont besoin. Et je veux savoir ce qu'un job peut faire sur cette machine, en bien comme en mal.

**Objectifs pédagogiques**
- Comprendre l'architecture d'un runner : il interroge GitLab en HTTPS sortant, aucun port entrant.
- Créer un runner d'instance dans l'interface et l'enregistrer avec un jeton d'authentification `glrt-`.
- Mesurer ce qu'implique l'exécuteur `shell` (utilisateur, dossiers de build, isolation entre projets).
- Préparer un hôte de build reproductible : versions figées, outils installés pour tous, sans privilèges.

**Prérequis** : M01-E04 (`git01`, PKI provisoire), M01-E05 (compte administrateur `<MOI>`), M00-E12 et M00-E13 (clonage d'une VM du socle, DNS), M00-E15 (`~/.ssh/config`).
**Durée indicative** : 1 h 30.

**Contexte technique**
- `runner01` : VMID **1007**, clone complet de 9000 sur `local-nvme`, 2 vCPU, 4096 Mo, disque 30 Go, `--net0 virtio,bridge=vinfra`, `10.10.20.15/24` (passerelle 10.10.20.1), étiquettes Proxmox `socle;role-runner`, pool `lab`, démarrage automatique **après** `git01` (ordre de démarrage 5, `git01` ayant l'ordre 4). Nom `runner01.par1.medisphere.internal` dans dnsmasq (A + PTR), alias SSH `runner01` (utilisateur `admin`).
- Paquets officiels du dépôt `packages.gitlab.com` (Debian 13 pris en charge) : `gitlab-runner` **et** `gitlab-runner-helper-images`, à la **même** version exacte, la dernière **19.4.z**. Le runner est en 19.4 alors que GitLab est encore en 19.3 : c'est temporaire, M01-E29 aligne GitLab.
- Runner **d'instance**, description `runner01-shell`, étiquettes `shell` et `socle`, « exécuter les jobs sans étiquette » **désactivé**, délai maximal d'un job : 1 h. Flux d'enregistrement : *Admin → CI/CD → Runners → Create instance runner*, puis `gitlab-runner register` avec le jeton `glrt-…` affiché (une seule fois). L'ancien jeton d'enregistrement (`--registration-token`) est déprécié : ne l'utilise pas.
- Outils exigés par les pipelines du bloc A, utilisables par l'utilisateur système `gitlab-runner` : `git` ; `uv` installé pour tous dans `/usr/local/bin` ; `pre-commit` 4.6.x installé par `uv tool install` avec `UV_TOOL_DIR=/opt/uv-tools` et `UV_TOOL_BIN_DIR=/usr/local/bin` ; `gitleaks` 8.30.x (binaire officiel de GitHub, empreinte vérifiée) dans `/usr/local/bin`. Node.js et les outils npm arrivent en M01-E24.
- La racine de la PKI provisoire (`~/pki-provisoire/ca.crt` sur `adm01`) s'installe comme sur `git01` : `/usr/local/share/ca-certificates/medisphere-provisoire.crt` puis `update-ca-certificates`.

**Travail demandé**
1. **La VM.** Crée `runner01` avec la même procédure que `git01` en M01-E04 (vérifie d'abord que le VMID 1007 est libre). Déclare le nom dans dnsmasq, ajoute l'alias SSH, et vérifie `ssh runner01 hostname -f`. Note dans ton journal pourquoi le runner est une VM **distincte** de `git01`.
2. **Confiance TLS.** Installe la racine de la PKI provisoire et prouve que `curl https://git01.par1.medisphere.internal/users/sign_in` réussit sans `-k`.
3. **Dépôt de paquets.** Télécharge le script d'installation du dépôt de GitLab Runner (voir la documentation « Install GitLab Runner using the official GitLab repositories »), **lis-le avant de l'exécuter** et note ce qu'il installe (clé, fichier de sources). Liste les versions disponibles (`apt-cache madison gitlab-runner`), installe la dernière 19.4.z des **deux** paquets, puis fige-les (`apt-mark hold`). Pourquoi installer les images d'assistance alors que l'exécuteur `shell` n'utilise pas de conteneur ?
4. **Création et enregistrement.** Crée le runner d'instance dans l'interface avec les réglages du contexte. Enregistre-le sur `runner01` en mode non interactif, exécuteur `shell`, sans que le jeton passe dans l'historique du shell ni dans un fichier autre que `config.toml`. Observe :
   ```
   admin@runner01:~$ sudo gitlab-runner list
   admin@runner01:~$ sudo gitlab-runner verify
   admin@runner01:~$ sudo ls -l /etc/gitlab-runner/config.toml
   admin@runner01:~$ sudo journalctl -u gitlab-runner -n 20
   ```
   Dans l'interface, le runner doit apparaître *Online*. Où sont passés les étiquettes et le réglage « jobs sans étiquette » : dans `config.toml` ou côté serveur ? Pourquoi ce changement de modèle par rapport aux anciens jetons d'enregistrement ?
5. **Concurrence.** Règle le nombre de jobs simultanés de ce runner en fonction de ses 2 vCPU et justifie ton choix.
6. **Outils des jobs.** Installe `git`, `uv`, `pre-commit` et `gitleaks` comme indiqué dans le contexte. Vérifie chacun **en tant que** `gitlab-runner` (`sudo -u gitlab-runner -H …`). Pourquoi faut-il imposer à `uv` le Python du système pour `pre-commit` ?
7. **Essai.** Dans `formation/git-labo`, sur une branche jetable, pousse un `.gitlab-ci.yml` avec deux jobs : l'un étiqueté `shell` qui affiche `id`, `hostname -f`, `pwd` et les versions des outils, l'autre **sans** étiquette. Observe le sort de chacun, puis annule le second et supprime la branche. Réponds dans ton journal : sous quel utilisateur tourne un job ? Dans quel dossier ? Que peut lire un job du projet A dans les builds du projet B ? Que se passerait-il si un job faisait `rm -rf ~` ?
8. **Garde-fous.** Vérifie que `gitlab-runner` n'appartient à aucun groupe privilégié et n'a aucun droit `sudo`. Explique pourquoi c'est non négociable avec un exécuteur `shell`.
9. **Documentation.** Par une MR dans `plateforme/medisphere` : `runner01` dans `docs/socle/inventaire.md` (VMID, IP, rôle, versions) et ses flux dans `docs/socle/matrice-flux.md` (vers `git01`, vers Internet pour les paquets).

**Critères de réussite**
- [ ] La VM 1007 `runner01` existe avec les caractéristiques du contexte, démarre automatiquement après `git01`, résout et répond en SSH par son alias.
- [ ] `gitlab-runner` et `gitlab-runner-helper-images` sont en 19.4.z, même version, figés ; le service est actif.
- [ ] `config.toml` (root, 600) déclare l'exécuteur `shell` et un jeton `glrt-` ; aucun jeton dans l'historique du shell.
- [ ] Dans GitLab, un runner d'instance étiqueté `shell` et `socle`, en ligne, refuse les jobs sans étiquette et a exécuté un job avec succès.
- [ ] `git`, `uv`, `pre-commit` 4.x et `gitleaks` 8.30.x fonctionnent pour l'utilisateur `gitlab-runner`, qui n'a aucun droit d'administration.
- [ ] L'inventaire et la matrice des flux de `plateforme/medisphere` mentionnent `runner01`.

**Vérification** : `lab/bin/check 01 23`

<details><summary>Indice 1</summary>

Avec le flux actuel, un runner est d'abord un **objet de GitLab** (créé dans l'interface ou par l'API), puis une installation qui s'authentifie avec le jeton de cet objet. Tout ce qui décrit « quels jobs ce runner accepte » appartient à l'objet côté serveur.
</details>

<details><summary>Indice 2</summary>

Pour garder le jeton hors de l'historique : `read -rs` dans une variable, puis passe la variable à la commande, et `unset` après. Pour la version exacte d'un paquet Debian : `apt-get install paquet=<version>` avec la chaîne affichée par `apt-cache madison`.
</details>

<details><summary>Indice 3</summary>

Un outil installé « pour root » vit souvent dans des dossiers de `/root` (Python téléchargé, environnement virtuel, cache) que `gitlab-runner` ne peut pas lire. Regarde les variables d'environnement documentées de l'installeur de `uv` et de `uv tool`, et l'option qui choisit l'interpréteur Python.
</details>

**Pour aller plus loin** (facultatif) : créer le runner par l'API (`POST /user/runners`, portée `create_runner`) pour pouvoir le recréer par script ; niveau d'accès `ref_protected` d'un runner (il ne prend que les jobs des branches et étiquettes protégées : utile pour un runner qui porte des secrets de déploiement) ; [installation](https://docs.gitlab.com/runner/install/linux-repository/), [enregistrement](https://docs.gitlab.com/runner/register/), [exécuteur shell](https://docs.gitlab.com/runner/executors/shell/).

---

### M01-E24 — Pipeline de qualité obligatoire avant fusion  `LAB` `★★`

> **Ticket PLAT-251** — *De : Karim Benali*
> pre-commit sur les postes, c'est bien, mais un `--no-verify` et tout passe. Je veux qu'aucune MR ne puisse être fusionnée sans que les **mêmes** contrôles aient tourné sur la forge. Et je ne veux pas cinq copies de la CI qui divergent : la définition des contrôles vit à un seul endroit, versionnée, et chaque projet de la plateforme l'inclut.

**Objectifs pédagogiques**
- Écrire une CI GitLab : stages, jobs, `rules`, `workflow`, pipelines de MR, variables prédéfinies.
- Mutualiser la CI par `include: project` et figer la version consommée.
- Rejouer en CI ce que pre-commit, commitlint et Gitleaks font en local, sur la bonne plage de commits.
- Rendre le pipeline obligatoire avant fusion et prouver qu'il bloque.
- Fournir aux jobs un outillage Node.js reproductible et non modifiable par les jobs.

**Prérequis** : M01-E23, M01-E11 (protections et méthode de fusion semi-linéaire), M01-E14 (commitlint), M01-E15 (pre-commit), M01-E16 (Gitleaks), M01-E22 (CONTRIBUTING).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Nouveau projet privé **`plateforme/ci-templates`**, protégé comme les autres projets `plateforme/*` (M01-E11). Arborescence attendue : `templates/qualite.yml` (cet exercice), `templates/release.yml` (M01-E25), `outils/release-tools/` (`package.json` et `package-lock.json` des outils Node des runners), `README.md`, et sa propre CI (`.gitlab-ci.yml`), plus les fichiers de référence `.pre-commit-config.yaml` (M01-E15) et `commitlint.config.mjs` (M01-E14).
- `templates/qualite.yml` (contrat repris par tous les modules suivants) : règles `workflow` (pipelines de MR, pipelines de branche sans MR ouverte, **pas de pipeline en double**) ; stages standard `lint`, `test`, `build`, `release` ; trois jobs du stage `lint`, étiquette `shell` :
  - `pre-commit` : `pre-commit run --all-files --show-diff-on-failure`, seulement si le projet a un `.pre-commit-config.yaml` ;
  - `commitlint` : les messages de **tous les commits de la MR** (ou du push, hors MR), avec la configuration du projet, et refus des commits `fixup!`/`squash!`/`amend!` restés dans la branche (commitlint les ignore, M01-E12) ;
  - `gitleaks` : `gitleaks git` sur **la même plage de commits** (un secret ajouté puis retiré dans la MR doit être trouvé), sans jamais afficher le secret en clair.
- Inclusion, à l'identique dans chaque projet consommateur :
  ```yaml
  include:
    - project: plateforme/ci-templates
      ref: v1
      file: templates/qualite.yml
  ```
  `v1` est une **branche** protégée de `ci-templates` qui désigne la version des gabarits que consomment les projets (M01-E25 la fera avancer automatiquement à chaque version `1.x.y`).
- Outils Node sur `runner01` : Node.js **24 LTS** (dépôt NodeSource, comme sur `adm01` en M01-E14) ; dans **`/opt/release-tools`**, un projet npm figé par `package-lock.json` : `@commitlint/cli` 21.x, `@commitlint/config-conventional` 21.x, `semantic-release` 25.x, `@semantic-release/gitlab` 13.x, `conventional-changelog-conventionalcommits`. Le dossier appartient à `root` et n'est **pas** modifiable par `gitlab-runner`. Les binaires s'appellent par leur chemin ou via `PATH` ; à toi de découvrir comment faire trouver à commitlint la configuration partagée installée là (l'`extends` de `commitlint.config.mjs`), sans `npm install` dans chaque pipeline.
- Variables prédéfinies utiles (à lire dans la documentation) : `CI_PIPELINE_SOURCE`, `CI_MERGE_REQUEST_DIFF_BASE_SHA`, `CI_COMMIT_BEFORE_SHA`, `CI_COMMIT_SHA`, `CI_DEFAULT_BRANCH`, `CI_OPEN_MERGE_REQUESTS`.

**Travail demandé**
1. **Node et `/opt/release-tools`.** Installe Node.js 24 sur `runner01`. Écris `outils/release-tools/package.json` avec des versions **exactes**, génère le verrou, et installe le dossier par `npm ci` (pas `npm install`). Réponds : que garantit `npm ci` que `npm install` ne garantit pas ? Que risques-tu avec les scripts d'installation des paquets npm, et comment t'en passer ici ?
2. **Le projet des gabarits.** Crée `plateforme/ci-templates` avec ses protections, son CONTRIBUTING et ses fichiers de référence.
3. **`templates/qualite.yml`.** Écris le gabarit. Pour chaque job, note dans ton journal :
   - la plage de commits contrôlée dans un pipeline de MR, sur une branche sans MR, sur `main` après fusion, et lors du tout premier push d'un projet ;
   - pourquoi la profondeur de clone par défaut de GitLab casse `commitlint` et `gitleaks` ;
   - pourquoi le hook `gitleaks` de pre-commit ne sert à rien dans le job `pre-commit`, et comment l'y désactiver proprement ;
   - ce que fait `--show-diff-on-failure`.
4. **Auto-test.** La CI de `ci-templates` applique ses propres gabarits **depuis la branche en cours** (et non depuis `v1`), et ajoute un job qui échoue si l'outillage installé sur `runner01` ne correspond plus au verrou versionné. Fais passer le tout par une MR, pipeline vert, fusion.
5. **Branche `v1`.** Crée `v1` à partir de `main` et protège-la (fusion et push : Maintainers, pas de force).
6. **Brancher les projets.** Dans `plateforme/medisphere`, ajoute l'inclusion par MR. Sur `plateforme/medisphere` et `plateforme/ci-templates`, active « Pipelines must succeed » et désactive « Skipped pipelines are considered successful ». Pourquoi le second réglage compte-t-il ?
7. **Prouver le blocage.** Sur une branche de `plateforme/medisphere`, crée en contournant tes hooks locaux (`--no-verify`) un commit au message non conforme, puis un commit qui ajoute une **clé privée jetable** générée pour l'occasion (`ssh-keygen -t ed25519 -N '' -f /tmp/cle-jetable`) et un troisième qui la retire. Ouvre la MR : le pipeline doit échouer sur `commitlint` et `gitleaks`, et le bouton de fusion doit être bloqué. Vérifie que la clé n'apparaît pas en clair dans le journal du job. Ferme ensuite la MR sans fusionner, supprime la branche et la clé jetable, et note ce qui subsiste malgré tout sur la forge (pense aux références des MR, M01-E17).
   > ⚠️ **Attention** : uniquement une clé générée pour ce test, jamais un vrai secret.
8. **Mesure.** Compare la durée du premier pipeline et du suivant (job `pre-commit`) et explique l'écart.

**Critères de réussite**
- [ ] `runner01` a Node.js 24 et un `/opt/release-tools` installé depuis le verrou versionné dans `ci-templates`, non modifiable par `gitlab-runner`.
- [ ] `plateforme/ci-templates` contient `templates/qualite.yml` (workflow, jobs `pre-commit`, `commitlint`, `gitleaks` sur l'étiquette `shell`) et une branche `v1` protégée.
- [ ] `plateforme/medisphere` inclut `templates/qualite.yml` de `ci-templates` en `ref: v1` ; son dernier pipeline de `main` est vert.
- [ ] Les deux projets exigent un pipeline réussi pour fusionner, et un pipeline ignoré ne compte pas comme réussi.
- [ ] Un pipeline de MR a exécuté `commitlint` et `gitleaks` (et `pre-commit` si le projet a sa configuration) ; un échec de `commitlint` ou de `gitleaks` a bloqué une MR.

**Vérification** : `lab/bin/check 01 24`

<details><summary>Indice 1</summary>

Une ancre YAML (`&nom` / `*nom`) évite de répéter le calcul de la plage dans deux jobs : elle fonctionne à l'intérieur d'un même fichier. Pour qu'un job hérite de réglages communs, regarde `extends` et les clés cachées (préfixées par un point).
</details>

<details><summary>Indice 2</summary>

commitlint cherche les configurations partagées à partir du dossier du projet, puis du dossier global de npm. Le dossier du projet n'a pas de `node_modules`, et `/opt/release-tools` n'est pas le préfixe global. Il existe une variable d'environnement historique de Node qui ajoute des dossiers à la résolution des modules CommonJS : vérifie si commitlint en profite. Et sans configuration du tout, lis bien le code de sortie de commitlint.
</details>

<details><summary>Indice 3</summary>

`commitlint --from A --to B` contrôle les commits de `A` (exclu) à `B` : si `A` et `B` sont égaux, il ne contrôle **rien** et réussit. Le premier push d'une branche a un `CI_COMMIT_BEFORE_SHA` fait de zéros. Pour Gitleaks, l'option `--log-opts` accepte une plage au format de `git log`.
</details>

**Pour aller plus loin** (facultatif) : les composants CI/CD et le catalogue (`include: component`), alternative moderne à `include: project` ; les rapports JUnit dans le widget de MR ; [référence `.gitlab-ci.yml`](https://docs.gitlab.com/ci/yaml/), [variables prédéfinies](https://docs.gitlab.com/ci/variables/predefined_variables/), [pipelines de MR](https://docs.gitlab.com/ci/pipelines/merge_request_pipelines/).

---

### M01-E25 — semantic-release : versions, changelog et releases automatiques  `LAB` `★★★`

> **Ticket DEV-252** — *De : Julien Petit*
> Mon équipe va consommer vos gabarits CI et bientôt vos outils. Aujourd'hui, quand vous changez quelque chose, je ne sais ni quelle version j'utilise, ni ce qui a changé, ni si ça va casser chez moi. Je veux des numéros de version qui ont un sens, des notes de version lisibles, et la garantie qu'une rupture ne me tombe pas dessus sans que je l'aie choisie.

**Objectifs pédagogiques**
- Relier Conventional Commits, SemVer et publication automatique.
- Comprendre les étapes de semantic-release et le rôle de chaque extension.
- Donner à la CI un jeton de bot au moindre privilège, protégé et masqué.
- Publier sans jamais écrire dans `main` (protégée) : étiquettes, Releases GitLab, notes de version.
- Offrir aux consommateurs un canal « majeur » stable.

**Prérequis** : M01-E24, M01-E20 (jetons de projet), M01-E14 (types de commits et versions produites).
**Durée indicative** : 2 h 30.

**Contexte technique**
- `.releaserc.json` à la racine de chaque projet publié : extensions `@semantic-release/commit-analyzer` et `@semantic-release/release-notes-generator` avec le préréglage `conventionalcommits`, puis `@semantic-release/gitlab` ; `tagFormat` `v${version}` ; branche de publication `main`. **Aucun commit** dans `main` (pas de `CHANGELOG.md` commité : les notes vivent dans les Releases GitLab), **aucune** publication npm.
- `templates/release.yml` dans `ci-templates` : un job `release`, stage `release`, étiquette `shell`, **uniquement** sur la branche par défaut protégée et seulement si le projet a un `.releaserc.json`, deux publications jamais simultanées.
- Jeton : **jeton d'accès de projet** `bot-release` (rôle Maintainer, portées `api` et `write_repository`, expiration ≤ 1 an), stocké dans la variable CI `GITLAB_TOKEN` du projet, **protégée et masquée**. Un jeton par projet publié.
- Étiquettes `v*` protégées (création : Maintainers).
- Projets publiés dans cet exercice : `plateforme/ci-templates` et `plateforme/medisphere`. Dans `ci-templates`, après chaque version `vX.Y.Z` publiée, la branche `vX` doit pointer sur le commit publié (la branche `v1` créée en M01-E24 avance donc toute seule).
- ⚠️ Ne publie **pas** de version majeure de `ci-templates` : tous les projets et les modules suivants consomment `v1`. Une rupture s'essaie dans `formation/` ou en simulation (`--dry-run`).

**Travail demandé**
1. **Comprendre avant d'installer.** Lis la documentation de semantic-release (*Release steps*, *Plugins*, *CI configuration*). Dans ton journal : les étapes dans l'ordre et l'extension qui agit à chacune ; quelle version produit une série de commits ne contenant que `docs:` et `chore:` ; ce que fait `feat!:` ou un pied `BREAKING CHANGE:` ; pourquoi l'étiquette `socle-v0` de `plateforme/medisphere` sera ignorée.
2. **Simulation.** Sur `adm01` (Node 24, M01-E14), installe les mêmes outils que sur `runner01` à partir du verrou de `ci-templates`, puis lance semantic-release en `--dry-run` sur un clone de `plateforme/medisphere`. Quelle version serait publiée, avec quelles notes ? (Un jeton est exigé même en simulation : lis-le depuis ton fichier de jeton d'administration sans l'afficher ni l'exporter durablement.)
3. **Jeton et protections.** Pour chacun des deux projets : crée le jeton de projet `bot-release`, la variable `GITLAB_TOKEN`, la protection des étiquettes `v*`. Note la date d'expiration du jeton et ce qui se passera ce jour-là. Pourquoi Maintainer, et pas Developer ? Pourquoi un jeton de projet plutôt que ton jeton personnel ?
4. **Le gabarit.** Écris `templates/release.yml` et le `.releaserc.json` de référence. Explique ce que deviennent la variable protégée et le job dans un pipeline de MR.
5. **Première publication.** Par MR, ajoute `.releaserc.json` et l'inclusion de `release.yml` dans les deux projets. Après fusion, observe le job `release` : étiquette, Release, notes, commentaires sur les MR et tickets concernés.
6. **Canal majeur.** Dans la CI propre à `ci-templates`, ajoute ce qui fait avancer la branche `vX` après chaque publication `vX.Y.Z`, sans pipeline inutile sur cette branche. Pourquoi une **branche** `v1` plutôt qu'une étiquette `v1` qu'on déplacerait ?
7. **Cycle complet.** Publie dans `ci-templates` un correctif (`fix:`) puis une évolution (`feat:`) ; vérifie les versions produites, la position de `v1`, et qu'un projet consommateur récupère la nouvelle version sans changer son `.gitlab-ci.yml`. Fais aussi fusionner une MR `docs:` seule et explique le résultat.
8. **Runbook.** Ajoute au CONTRIBUTING de `ci-templates` la règle sur les ruptures, et dans `docs/socle/runbooks/` (`plateforme/medisphere`) une section « renouveler le jeton `bot-release` » dans un runbook existant ou nouveau, au choix.

**Critères de réussite**
- [ ] `ci-templates` contient `templates/release.yml` ; les deux projets ont un `.releaserc.json` conforme au contexte et incluent `release.yml`.
- [ ] Chaque projet a un jeton de projet `bot-release` actif (Maintainer, `api` + `write_repository`, avec expiration), une variable `GITLAB_TOKEN` protégée et masquée, des étiquettes `v*` protégées.
- [ ] Chaque projet a au moins une Release `vX.Y.Z`, et le job `release` du dernier pipeline de `main` a réussi.
- [ ] Dans `ci-templates`, la branche `v1` pointe sur la dernière version `1.x.y` ; aucune version `2.x` n'a été publiée.
- [ ] Aucun commit de release n'a été ajouté à `main`.

**Vérification** : `lab/bin/check 01 25`

<details><summary>Indice 1</summary>

semantic-release a besoin de tout l'historique et de toutes les étiquettes. Sur un exécuteur `shell`, le dossier de build est réutilisé d'un job à l'autre : pense à la stratégie de récupération du dépôt.
</details>

<details><summary>Indice 2</summary>

Si le job échoue avec une erreur de certificat (`unable to get local issuer certificate`, `self-signed certificate in certificate chain`) alors que `curl` et `git` fonctionnent sur `runner01`, c'est que Node.js n'utilise pas le magasin de certificats du système. Une variable d'environnement de Node permet de lui fournir des autorités supplémentaires.
</details>

<details><summary>Indice 3</summary>

Pour retrouver, dans un job ultérieur du même pipeline, la version que `release` vient de publier : l'étiquette pointe sur le commit du pipeline (`git tag --points-at`). Une option de push de GitLab évite de déclencher un pipeline sur la référence poussée.
</details>

**Pour aller plus loin** (facultatif) : branches de maintenance (`1.x`) et de préversion (`next`) de semantic-release ; fichiers attachés aux Releases (`assets`) ; [semantic-release](https://semantic-release.gitbook.io/semantic-release/), [`@semantic-release/gitlab`](https://github.com/semantic-release/gitlab), [jetons d'accès de projet](https://docs.gitlab.com/user/project/settings/project_access_tokens/).

---

### M01-E26 — Hooks côté serveur : imposer les règles même sans pre-commit  `LAB` `★★★`

> **Ticket SEC-253** — *De : Sophie Laurent*
> La CI arrive **après** le push : le binaire de 200 Mo ou le commit « wip » sont déjà sur le serveur, dans l'historique d'une branche. Et GitLab CE n'a pas les règles de push de la version payante. Je veux que le serveur lui-même refuse, pour les projets de la plateforme, les messages non conformes et les fichiers de plus de 5 Mo, avec un message qui dit quoi faire. Et que ça ne bloque pas les exercices de l'équipe ailleurs.

**Objectifs pédagogiques**
- Comprendre le hook `pre-receive` : entrée, quarantaine des objets, code de sortie, ordre d'exécution.
- Configurer les hooks globaux de Gitaly sur GitLab 19.
- Écrire un hook robuste : ne contrôler que les objets nouveaux, borner le périmètre, rester rapide, expliquer le refus.
- Tester un hook hors ligne avant de le déployer, et modifier `gitlab.rb` sans casser l'existant.

**Prérequis** : M01-E04 (`gitlab.rb` avec le profil mémoire contrainte), M01-E14 (règles de messages), M01-E24.
**Durée indicative** : 2 h.

**Contexte technique**
- Hooks globaux de Gitaly : un répertoire déclaré dans la configuration de Gitaly (`gitlab.rb`), dans lequel chaque type de hook a son sous-dossier (`pre-receive.d/`) ; fichiers exécutables appartenant à `git`. La documentation propose `/var/opt/gitlab/gitaly/custom_hooks` : utilise ce chemin.
- Règles à imposer, **uniquement** pour les projets dont le chemin commence par `plateforme/` (les projets `formation/` servent aux exercices et doivent rester libres) :
  1. tout commit **nouveau** pour le dépôt a un en-tête Conventional Commits : types de `@commitlint/config-conventional` (`build`, `chore`, `ci`, `docs`, `feat`, `fix`, `perf`, `refactor`, `revert`, `style`, `test`), portée facultative, `!` facultatif, 100 caractères au plus ; les commits que commitlint ignore par défaut (fusions et retours arrière générés par Git ou GitLab, `fixup!`/`squash!`/`amend!`) sont acceptés ;
  2. aucun fichier (blob) de plus de **5 Mio** (5 242 880 octets) parmi les objets poussés, même s'il est supprimé par un commit suivant du même push ;
  3. chaque refus explique la règle, cite les commits ou fichiers en cause et la façon de corriger, sur des lignes préfixées `GL-HOOK-ERR:` ;
  4. la suppression d'une branche ou d'une étiquette n'est jamais bloquée ; les fusions faites dans l'interface de GitLab doivent continuer de fonctionner.
- Les hooks sont versionnés dans `plateforme/medisphere` sous `forge/hooks/` (scripts, tests, déploiement).

> ⚠️ **Attention** : un hook global défaillant (erreur de syntaxe, binaire introuvable, boucle lente) bloque **tous** les pushes de la forge, y compris les fusions dans l'interface. Teste hors ligne avant de déployer, garde une session sur `git01`, et sache comment retirer un hook en urgence (déplacer le dossier `pre-receive.d`). Sauvegarde `gitlab.rb` avant de le modifier.

**Travail demandé**
1. **Lire.** Documentation « Git server hooks » de GitLab et `man githooks` (section *pre-receive*). Dans ton journal : le format de l'entrée standard ; l'ordre d'exécution des hooks (intégrés, par projet, globaux) et l'effet d'un code non nul ; les variables `GL_*` disponibles ; ce qu'est la quarantaine et pourquoi `git rev-list <nouveau> --not --all` y désigne exactement les commits nouveaux ; ce que reçoit le hook lors d'une fusion faite dans l'interface (`GL_PROTOCOL`).
2. **Écrire** les deux règles, en un ou plusieurs scripts Bash, dans `forge/hooks/pre-receive.d/` de ton clone de `plateforme/medisphere`. Ils ne font aucun appel réseau et doivent répondre en moins d'une seconde pour un push ordinaire.
3. **Tester hors ligne.** Écris `forge/hooks/tester-hooks.sh`, qui rejoue la chaîne des hooks sur un dépôt temporaire, dans les conditions de Gitaly (dépôt nu, objets nouveaux visibles mais non référencés, variables `GL_*`), avec au moins : message conforme, non conforme, fusion GitLab, `fixup!`, en-tête trop long, gros fichier, gros fichier ajouté puis retiré, projet hors périmètre, suppression de branche. ShellCheck sans avertissement.
4. **Configurer Gitaly.** Relis le `gitlab.rb` de M01-E04 **avant** d'écrire quoi que ce soit : où se trouve déjà la configuration de Gitaly ? Ajoute le répertoire des hooks sans rien perdre, applique, et vérifie la configuration **générée** (`/var/opt/gitlab/gitaly/config.toml`), pas seulement celle que tu as écrite.
5. **Déployer** les hooks (propriétaire, droits), de préférence par un script rejouable depuis `adm01`, et rejoue les tests sur `git01`, avec le `git` du serveur et l'utilisateur `git`. Faut-il installer `git` sur `git01` ? Décide et justifie.
6. **Éprouver en vrai.** Un push non conforme vers une branche de `plateforme/medisphere` (refusé, message lisible côté client), le même vers `formation/git-labo` (accepté), un fichier de 6 Mio (refusé), puis une MR conforme fusionnée dans l'interface (acceptée). Fais une capture texte des refus pour le CONTRIBUTING.
7. **Bris de glace.** Imagine le cas de l'import d'un dépôt historique dans `plateforme/` (anciens messages non conformes). Propose une dérogation **tracée** plutôt que la désactivation du hook, et implémente-la si tu as le temps.
8. **Documenter** dans le CONTRIBUTING de `plateforme/medisphere` : règles imposées par le serveur, message d'erreur type, correction.

**Critères de réussite**
- [ ] `custom_hooks_dir` figure dans la configuration générée de Gitaly, et les réglages de concurrence de M01-E04 y sont toujours.
- [ ] Les hooks de `pre-receive.d/` appartiennent à `git` et sont exécutables.
- [ ] Rejoués sur `git01`, ils acceptent un message conforme et un commit de fusion, refusent avec `GL-HOOK-ERR:` un message non conforme et un fichier de plus de 5 Mio (même retiré ensuite), et laissent tout passer pour un projet `formation/`.
- [ ] Les hooks et leurs tests sont versionnés sous `forge/hooks/` dans `plateforme/medisphere`.

**Vérification** : `lab/bin/check 01 26`

<details><summary>Indice 1</summary>

`gitaly['configuration']` est un hash Ruby unique : deux affectations successives ne se fusionnent pas, la seconde remplace la première.
</details>

<details><summary>Indice 2</summary>

Pour lister les objets nouveaux avec leur chemin, puis leur type et leur taille : `git rev-list --objects` puis `git cat-file --batch-check` avec un format. Pour les messages : `git log -z --format=…` évite de découper à la main sur des messages multilignes.
</details>

<details><summary>Indice 3</summary>

Pour simuler la quarantaine sans GitLab : crée les commits dans un dépôt « travail », et rends ses objets visibles depuis le dépôt nu « serveur » par la variable `GIT_ALTERNATE_OBJECT_DIRECTORIES`, sans y créer de référence. C'est exactement ce que fait Git pendant un push.
</details>

**Pour aller plus loin** (facultatif) : un troisième hook qui exige des commits signés sur `plateforme/` (M01-E27), avec un fichier de signataires autorisés sur `git01` ; la limite globale de taille de push de l'instance (`receive_max_input_size`) ; [Git server hooks](https://docs.gitlab.com/administration/server_hooks/), [githooks](https://git-scm.com/docs/githooks#pre-receive).

---

### M01-E27 — Signer commits et étiquettes, vérifier dans GitLab  `LAB` `★★`

> **Ticket SEC-254** — *De : Sophie Laurent*
> Dans Git, l'auteur d'un commit est une simple déclaration : n'importe qui peut écrire `karim.benali` dans `user.name`. Pour l'audit HDS, je veux savoir qui a **vraiment** écrit le code de la plateforme. Commits et étiquettes signés, vérifiés par GitLab, une liste des signataires de l'équipe, et une procédure le jour où une clé est compromise.

**Objectifs pédagogiques**
- Signer commits et étiquettes avec une clé SSH, et vérifier localement (fichier de signataires autorisés).
- Faire afficher « Verified » par GitLab : usage de la clé, adresse vérifiée.
- Connaître les limites : commits créés par GitLab, étiquettes de bot, révocation ou suppression d'une clé.

**Prérequis** : M01-E03 (configuration de Git sur `adm01`), M01-E05, M01-E06, M01-E20 (clés).
**Durée indicative** : 1 h 15.

**Contexte technique**
- GitLab vérifie une signature SSH si la clé est déclarée dans le compte avec l'usage **Signing** ou **Authentication & Signing**, et si l'adresse de *committer* est une adresse **vérifiée** du compte. Sans SMTP, les adresses des comptes ont été confirmées par l'administrateur (M01-E05).
- La vérification des étiquettes signées en SSH est affichée par GitLab depuis la 19.1 ; l'API expose la signature d'un commit (`/projects/:id/repository/commits/:sha/signature`).
- M01-E03 a configuré la signature SSH sur `adm01` : clé dédiée `~/.ssh/id_ed25519_signature`, fichier `~/.config/git/allowed_signers`, commits et étiquettes signés par défaut. Ici, on vérifie cette configuration et on la fait reconnaître par GitLab ; on ne recrée pas la clé.
- Clé de signature attendue : un **fichier** de clé publique désigné par `user.signingkey` ; signataires autorisés : un fichier local désigné par `gpg.ssh.allowedSignersFile`, et la liste de l'équipe versionnée dans `plateforme/medisphere` sous `docs/socle/securite/allowed_signers`.
- Étiquette d'essai : `essai-signature-e27`, annotée et signée, dans `formation/git-labo`.

**Travail demandé**
1. **État des lieux.** `git config --show-origin --get-regexp '^(user|gpg|commit|tag)\.'`. M01-E03 a imposé une clé de signature dédiée : justifie ce choix face à une clé unique pour l'authentification et la signature (révocation, usage, phrase de passe et agent).
2. **Déclarer** la clé de signature dans ton compte GitLab, usage *Signing*, avec une date d'expiration. Vérifie que ton adresse Git (`user.email`) est une adresse vérifiée du compte.
3. **Signer par défaut** commits et étiquettes. Fais un commit signé dans `plateforme/medisphere` par MR (par exemple l'ajout de `docs/socle/securite/allowed_signers`), puis observe : `git log --show-signature -1`, `git verify-commit`, le badge dans GitLab, et la réponse de l'API pour ce commit.
4. **Signataires.** Configure `gpg.ssh.allowedSignersFile`. Faut-il le faire pointer directement sur le fichier du dépôt cloné ? Réfléchis à ce qui se passe quand tu bascules sur une branche où quelqu'un a ajouté une clé.
5. **Lire un historique.** Sur `main` de `plateforme/medisphere`, `git log --format='%h %G? %GS %s'` : interprète chaque lettre (`G`, `U`, `N`, `E`…). Quels commits ne sont pas signés, et pourquoi (commits de fusion, suggestions acceptées, étiquettes de semantic-release) ? Qu'en conclut un auditeur ?
6. **Étiquette signée.** Crée et pousse `essai-signature-e27` dans `formation/git-labo`, vérifie-la (`git tag -v`) et dans l'interface.
7. **Exercice de compromission**, avec une clé **jetable** créée pour l'occasion : déclare-la, signe un commit dans `formation/git-labo`, pousse, puis **révoque** la clé dans GitLab et observe le statut du commit. Compare avec une **suppression**. Supprime la clé jetable ensuite.
8. **Politique.** Rédige en 5 à 10 lignes la politique de signature de l'équipe (ce qui doit être signé, ce qui ne peut pas l'être, contrôle, compromission), à ajouter au CONTRIBUTING.

**Critères de réussite**
- [ ] Git sur `adm01` signe commits et étiquettes en SSH par défaut, avec une clé désignée par un fichier et un fichier de signataires qui la contient.
- [ ] La clé est déclarée dans GitLab avec l'usage *Signing* et une expiration.
- [ ] Ton dernier commit arrivé sur `main` de `plateforme/medisphere` est « Verified » (SSH) ; la liste des signataires y est versionnée.
- [ ] L'étiquette annotée `essai-signature-e27` de `formation/git-labo` se vérifie avec `git tag -v`.
- [ ] La politique de signature et le constat de l'exercice de révocation sont écrits.

**Vérification** : `lab/bin/check 01 27`

<details><summary>Indice 1</summary>

« Unverified » avec une signature pourtant valide localement : compare l'adresse du commit (`git log --format=%ce -1`) et les adresses vérifiées de ton profil GitLab.
</details>

<details><summary>Indice 2</summary>

Le format du fichier de signataires est décrit dans `man ssh-keygen`, section *ALLOWED SIGNERS* (principaux, options comme `namespaces`, `valid-after`, `valid-before`, puis la clé).
</details>

**Pour aller plus loin** (facultatif) : faire signer par GitLab les commits qu'il crée lui-même (clé de signature de Gitaly) ; [signature SSH dans GitLab](https://docs.gitlab.com/user/project/repository/signed_commits/ssh/), [`git config gpg.ssh.*`](https://git-scm.com/docs/git-config#Documentation/git-config.txt-gpgsshallowedSignersFile).

---

### M01-E28 — Sauvegarder et restaurer GitLab  `LAB` `★★★`

> **Ticket PLAT-255** — *De : Nadia Roussel*
> Si `git01` meurt, on perd le code, l'historique des revues, les pipelines, les jetons. La sauvegarde de nuit de la VM existe, mais personne n'a jamais restauré un GitLab. Je veux une sauvegarde **applicative** quotidienne, chiffrée, envoyée à PAR2, et une restauration testée sur une machine à part, chronométrée. Avec un runbook que je peux suivre à 3 h du matin.

**Objectifs pédagogiques**
- Savoir ce que `gitlab-backup` sauvegarde, et surtout ce qu'il ne sauvegarde pas.
- Envoyer une sauvegarde de fichiers vers PBS avec `proxmox-backup-client` (espace de noms, jeton minimal, chiffrement côté client).
- Ouvrir un flux réseau au plus juste à travers deux pare-feu.
- Restaurer sur une VM isolée, à la même version, et mesurer le RTO.

**Prérequis** : M00-E21 (tunnel `wg0`, pare-feu de `pbs01`), M00-E22 (datastore `ds-lab`, espace de noms `par1`, compte `wb-backup@pbs`), M00-E30 (sauvegarde de fichiers vers PBS), M00-E36 (chiffrement côté client, *paperkey*), M01-E04.
**Durée indicative** : 3 h.

**Contexte technique**
- Noms imposés (vérification) : script `/usr/local/sbin/wb-backup-gitlab.sh`, unités `wb-backup-gitlab.service` et `wb-backup-gitlab.timer` sur `git01` ; secrets PBS dans `/etc/wb-backup/pbs-git01.env` (`PBS_REPOSITORY`, `PBS_PASSWORD`, `PBS_FINGERPRINT`) et clé de chiffrement `/etc/wb-backup/pbs-git01.key`, tous deux `root:root 600`.
- Côté PBS : espace de noms **`par1/git01`** dans `ds-lab`, jeton **`wb-backup@pbs!git01`** dont les droits se limitent à cet espace de noms (rôle `DatastoreBackup`), groupe de sauvegarde `host/git01`.
- Flux à ouvrir : `git01` (10.10.20.12) → `pbs01` (10.20.10.10) TCP/8007, à travers `wg0`. Rappel M00-E21 : `gw01` ne masque vers `wg0` que le LAN maison ; `pbs01` filtre lui-même ses entrées.
- `proxmox-backup-client` : dépôt `pbs-client` de Proxmox pour Debian 13 (documentation *Installation → Debian Package Repositories → Proxmox Backup Client-only Repository*), sur `git01` et sur `adm01`.
- Restauration de test : VM **2010** `git-restore`, clone de 9000, 4 vCPU, **8192 Mo**, disque 60 Go, VNet `vsandbox` (DHCP), pool `lab`, étiquette `env-m01`. Le VLAN SANDBOX ne joint pas PAR2 : les données passent par `adm01`. Une sauvegarde GitLab ne se restaure que sur la **même version exacte** de GitLab CE.
- Livrables dans `plateforme/medisphere` : `docs/socle/runbooks/RB-010-restaurer-gitlab.md`, une section datée dans `docs/socle/tests/restauration.md` (feuille de temps, RTO, RPO), matrice des flux à jour.

> ⚠️ **Attention** : (1) modification de deux pare-feu : `nft -c -f` avant chaque rechargement, session ouverte, retour arrière programmé comme en M00-E21 ; (2) la VM 2010 restaurée contient **les mêmes secrets** que `git01` (jetons, clés d'hôte, certificat) : elle reste sur `vsandbox`, ne prend jamais l'adresse ni le nom de `git01` dans le DNS, et est détruite à la fin ; (3) `gitlab-backup restore` **efface** la base de l'instance où il tourne : jamais sur `git01` ; (4) une clé de chiffrement perdue rend les sauvegardes illisibles : paperkey et copie hors ligne **avant** la première sauvegarde.

**Travail demandé**
1. **Inventaire.** Lis la documentation de sauvegarde de GitLab. Dresse la liste de ce qui est dans l'archive de `gitlab-backup create` et de ce qui n'y est pas mais est indispensable à une reconstruction (pense aux secrets, à la configuration, aux certificats, aux clés d'hôte SSH, aux hooks de M01-E26). Réponds : pourquoi la sauvegarde de VM nocturne (`lab-nuit`) ne suffit-elle pas ? Dans quels cas est-elle au contraire le meilleur moyen de revenir en arrière ?
2. **Local.** Mesure la place (`du -sh` des données de GitLab), règle une rétention locale courte, lance une sauvegarde et une sauvegarde de configuration à la main, et inspecte les archives (nom, version, `backup_information.yml`). Quelle option de `gitlab-backup` améliore la déduplication par PBS d'une nuit à l'autre ?
3. **PBS.** Crée l'espace de noms et le jeton avec ses droits (à vérifier avec `proxmox-backup-manager user permissions`). Vérifie que la tâche de purge du namespace `par1` (M00-E22) s'appliquera aussi à `par1/git01`.
4. **Réseau.** Ouvre le flux sur `gw01` et sur `pbs01`, au plus juste. Prouve que `git01` joint 8007 et que `runner01` ne le joint pas. Mets à jour la matrice des flux.
5. **Client et chiffrement.** Installe `proxmox-backup-client` sur `git01`, crée les fichiers de secrets et la clé de chiffrement (paperkey, copie hors ligne, empreinte notée), puis fais une première sauvegarde à la main. Vérifie côté client que l'instantané est chiffré.
6. **Automatisation.** Écris le script et les unités systemd (heure choisie et justifiée par rapport à `lab-nuit` et aux tâches de PBS ; rattrapage ; priorité basse). Le script ne contient aucun secret, échoue au moindre problème, et laisse un journal lisible. Lance le service, lis `journalctl`.
7. **Restauration de test**, chronométrée (feuille de temps comme en M00-E37) :
   1. vérifie la mémoire libre de `pve01`, crée la VM 2010 ;
   2. sur `adm01`, récupère la dernière sauvegarde avec la copie **hors ligne** de la clé (scénario « `git01` est perdue ») et contrôle les empreintes ;
   3. sur 2010, remets la configuration et les secrets, installe la même version de GitLab, restaure, reconfigure ;
   4. vérifie : `gitlab-rake gitlab:check SANITIZE=true`, `gitlab:doctor:secrets`, puis depuis `adm01` sans toucher au DNS (`curl --resolve`, `git ls-remote` vers l'adresse de 2010) : projets, MR, pipelines, jetons, variables CI ;
   5. détruis la VM 2010 et la copie de la clé sur `adm01`.
8. **Runbook et compte rendu.** RB-010 (prérequis, étapes, vérifications, pièges, durée mesurée) et la section du test dans `docs/socle/tests/restauration.md`, par MR.

**Critères de réussite**
- [ ] Le timer `wb-backup-gitlab.timer` est actif, le dernier passage du service a réussi ; secrets et clé sont en `root:root 600`, aucun secret dans le script ; la rétention locale est réglée.
- [ ] PBS contient dans `par1/git01` un instantané `host/git01` de moins de 48 h, chiffré ; le jeton `wb-backup@pbs!git01` n'a de droits que sur cet espace de noms ; la clé n'est pas sur `pbs01`.
- [ ] `git01` joint `pbs01:8007`, `runner01` ne le joint pas.
- [ ] Une VM 2010 a servi au test de restauration et n'existe plus.
- [ ] RB-010, le compte rendu du test et la matrice des flux sont sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 01 28`

<details><summary>Indice 1</summary>

`gitlab-ctl backup-etc` existe pour la configuration ; il accepte un dossier de destination. Les deux sauvegardes appliquent la même durée de rétention locale si on le leur demande.
</details>

<details><summary>Indice 2</summary>

Pour envoyer « les derniers fichiers seulement » sans les copier : un dossier d'envoi avec des **liens physiques** vers les archives du jour (même système de fichiers). `proxmox-backup-client backup` accepte un type et un identifiant de sauvegarde, un espace de noms et un fichier de clé.
</details>

<details><summary>Indice 3</summary>

L'ordre de la restauration compte : si `gitlab-secrets.json` n'est pas en place lors de la première configuration de GitLab sur la nouvelle machine, de nouveaux secrets sont générés et les données chiffrées restaurées (variables CI, jetons de runner, secrets 2FA) deviennent illisibles.
</details>

**Pour aller plus loin** (facultatif) : sauvegarde incrémentale des dépôts (`INCREMENTAL=yes`) ; alerte sur échec (`OnFailure=`) ; synchronisation de `par1/git01` vers un second datastore ; [sauvegarde](https://docs.gitlab.com/administration/backup_restore/backup_gitlab/), [restauration](https://docs.gitlab.com/administration/backup_restore/restore_gitlab/), [`backup-etc`](https://docs.gitlab.com/omnibus/settings/backups/), [client PBS](https://pbs.proxmox.com/docs/backup-client.html).

---

### M01-E29 — Mettre à jour GitLab en suivant le chemin de montée de version  `LAB` `★★`

> **Ticket CHG-256** — *De : Claire Morel*
> GitLab 19.4 est sortie, et ses correctifs contiennent des corrections de sécurité. Monte `git01` en 19.4 jeudi soir. Je veux le plan avant (risques, retour arrière, critères de décision), et la preuve après. Et je veux qu'on sache désormais à quel rythme on fait ça.

**Objectifs pédagogiques**
- Connaître la cadence de GitLab (mineures mensuelles, correctifs, sécurité) et les arrêts obligatoires.
- Préparer une mise à jour : migrations d'arrière-plan, santé, sauvegarde, instantané, communication.
- Savoir qu'on ne redescend pas de version, et en tirer un plan de retour arrière réaliste.
- Vérifier après coup, y compris ce qu'une reconfiguration peut avoir défait.

**Prérequis** : M01-E28 (sauvegarde testée), M01-E23, M01-E26.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Version cible : le **dernier correctif 19.4.z** ; paquet `gitlab-ce=19.4.z-ce.0` ; `gitlab-ce` est figé depuis M01-E04.
- Arrêts obligatoires des versions récentes : `x.2`, `x.5`, `x.8`, `x.11` (outil *Upgrade Path* de GitLab).
- Le paquet sauvegarde la base avant de migrer (sauf fichier `/etc/gitlab/skip-auto-backup`) : ce n'est pas une sauvegarde complète.
- Instantané de VM autorisé pendant la fenêtre : `avant-maj-19-4` sur la VM 1004, **sans** la mémoire, supprimé à la clôture.
- Runbook à livrer : `docs/socle/runbooks/RB-011-mettre-a-jour-gitlab.md`.

**Travail demandé**
1. **Préparer** (sans rien changer) : version actuelle, versions disponibles, chemin de montée (outil officiel), notes de version et notes de mise à jour de la série 19, dépréciations qui touchent ton `gitlab.rb` ; état des migrations d'arrière-plan (interface *Admin → Monitoring → Background migrations* et ligne de commande, selon ta version) ; santé (`gitlab:check`, `gitlab:doctor:secrets`, espace disque).
2. **Plan de retour arrière** : pour chaque situation (échec pendant les migrations, régression découverte une heure après, une semaine après), ce que tu fais et ce que tu perds. Où se situe le point de non-retour ?
3. **Jour J** : sauvegarde applicative fraîche (M01-E28) vérifiée dans PBS, instantané de la VM, runner en pause, puis mise à jour (en gérant le gel du paquet). Lis la sortie : qu'a fait le paquet, dans quel ordre ?
4. **Contrôles** : services, sondes, `gitlab:check`, secrets, migrations de la nouvelle version, connexion web, clone et push en SSH et HTTPS, MR, pipeline complet avec release, **hooks de M01-E26 toujours actifs** (`lab/bin/check 01 26`). Fais-en une liste à cocher réutilisable.
5. **Runner** : compare les versions de GitLab et de `runner01`, et note la règle de compatibilité que tu retiens.
6. **Clôture** : runner réactivé, instantané supprimé (pourquoi ne pas le garder « au cas où » ?), inventaire mis à jour, RB-011 par MR.
7. **Cadence** : propose en cinq lignes la politique de mise à jour de la forge (correctifs de sécurité, mineures, majeures), compatible avec les arrêts obligatoires.

**Critères de réussite**
- [ ] GitLab répond en 19.4.z ; le paquet est de nouveau figé ; aucun service arrêté.
- [ ] Les migrations d'arrière-plan sont terminées.
- [ ] Les hooks globaux sont toujours configurés ; le dernier pipeline de `main` de `plateforme/medisphere` est vert.
- [ ] Aucun instantané `avant-maj*` ne subsiste sur la VM 1004 ; `runner01` est en 19.4.z.
- [ ] RB-011 (avec plan de retour arrière et liste de contrôles) est sur `main`.

**Vérification** : `lab/bin/check 01 29`

<details><summary>Indice 1</summary>

`apt-get install paquet=version` sur un paquet figé : selon les options, apt refuse ou demande confirmation. Défige, installe la version exacte, refige.
</details>

<details><summary>Indice 2</summary>

`gitlab-ctl reconfigure`, lancé par la mise à jour, régénère toutes les configurations des services à partir de `gitlab.rb`. Tout ce qui a été modifié à la main dans un fichier généré disparaît ; tout ce qui est dans `gitlab.rb` reste.
</details>

**Pour aller plus loin** (facultatif) : tester la mise à jour sur la VM de restauration de M01-E28 avant la production ; [chemins de montée](https://docs.gitlab.com/update/upgrade_paths/), [migrations d'arrière-plan](https://docs.gitlab.com/update/background_migrations/), [mise à jour du paquet](https://docs.gitlab.com/update/package/).

---

### M01-E30 — Superviser GitLab : sondes de santé, services, journaux, métriques  `LAB` `★★`

> **Ticket PLAT-257** — *De : Nadia Roussel*
> Hier, GitLab a été lent tout l'après-midi ; on l'a appris par Julien. Je veux savoir **avant** les utilisateurs que la forge va mal : une sonde que je lance (et qu'un outil de supervision pourra lancer), les premiers gestes quand elle est rouge, et des métriques prêtes pour la supervision centrale du module 21. Sans faire exploser la mémoire de `git01`.

**Objectifs pédagogiques**
- Connaître les composants d'une installation GitLab et où lire leurs journaux.
- Utiliser les sondes de santé (`/-/readiness`, `/-/liveness`) et leur liste d'adresses autorisées.
- Mesurer le coût mémoire des composants de supervision embarqués et choisir.
- Écrire une sonde au format d'une supervision (codes de sortie, une ligne par contrôle).

**Prérequis** : M01-E04 (profil mémoire, supervision embarquée désactivée), M01-E23, M01-E28, M01-E29.
**Durée indicative** : 2 h.

**Contexte technique**
- Sondes HTTP : `/-/readiness` (avec `?all=1` pour le détail par dépendance), `/-/liveness` ; accessibles seulement depuis les adresses de `gitlab_rails['monitoring_whitelist']` (par défaut : boucle locale).
- Contraintes : **ne réactive pas le serveur Prometheus embarqué** (la supervision centrale arrive au module 21) ; expose les **métriques système** de `git01` au format Prometheus sur **10.10.20.12:9100**, joignables depuis `adm01`.
- Sonde : `~/lab-scripts/sonde-forge.sh` sur `adm01`, versionnée dans `plateforme/medisphere` sous `forge/supervision/`. Contrat : une ligne par contrôle `OK|WARN|CRIT <contrôle> : <détail>` ; code 0 si tout va bien, 1 si au moins un avertissement, 2 si au moins un critique, 3 si la sonde ne peut pas s'exécuter ; aucun secret affiché ; jeton des checks (`~/.config/workbook/gitlab-checks.token`). À couvrir au minimum : sondes HTTP, expiration du certificat, runner(s), disque et mémoire de `git01`, services GitLab, âge de la dernière sauvegarde applicative.
- Runbook à livrer : `docs/socle/runbooks/RB-012-diagnostiquer-la-forge.md`.

**Travail demandé**
1. **Carte.** `sudo gitlab-ctl status` : pour chaque service, son rôle et son journal (`/var/log/gitlab/…`, `gitlab-ctl tail`). Où regardes-tu en premier pour une erreur 502 ? pour un push SSH refusé ? pour un job qui ne démarre pas ?
2. **Mémoire.** Relève la mémoire consommée par service (`ps -eo rss,user,comm --sort=-rss`, `free -m`). Garde ces chiffres : ils serviront de référence.
3. **Sondes.** Interroge `/-/readiness?all=1` depuis `git01` puis depuis `adm01`. Que répond GitLab à une adresse non autorisée ? Autorise `adm01` (et seulement ce qu'il faut) et explique pourquoi ces sondes ne sont pas publiques.
4. **Métriques.** Étudie les composants de supervision du paquet (serveur Prometheus, Alertmanager, *exporters* système, Redis, PostgreSQL, GitLab) et ce que coûterait chacun. Expose les métriques système sur 10.10.20.12:9100 de la façon la plus économe (paquet GitLab ou paquet Debian : choisis et justifie), puis mesure à nouveau la mémoire. Tableau avant/après.
5. **Sonde.** Écris `sonde-forge.sh`. Pour le runner, pourquoi le statut « online » de l'API ne suffit-il pas à détecter vite un runner arrêté ? Quel champ utiliser à la place ?
6. **La faire rougir.** Provoque, un à la fois et en revenant à l'état sain après chacun : un arrêt du service `gitlab-runner` sur `runner01` pendant 6 minutes ; un arrêt de Gitaly (`sudo gitlab-ctl stop gitaly`, 1 minute). Observe la sonde et les sondes HTTP.
   > ⚠️ **Attention** : Gitaly arrêté = plus aucun accès aux dépôts pour personne. Préviens, reste moins d'une minute, et relance (`sudo gitlab-ctl start gitaly`) avant de faire quoi que ce soit d'autre.
7. **Runbook.** RB-012 : premiers gestes par ligne rouge de la sonde, carte des composants, arbre de décision « la forge ne répond pas », métriques exposées.

**Critères de réussite**
- [ ] `adm01` obtient HTTP 200 sur `/-/readiness?all=1` et `/-/liveness`, toutes dépendances « ok ».
- [ ] Les métriques système de `git01` sont lisibles sur `http://10.10.20.12:9100/metrics` depuis `adm01` ; le serveur Prometheus embarqué ne tourne pas.
- [ ] La sonde renvoie 0 sur une forge saine, n'affiche aucun secret, et est versionnée sous `forge/supervision/`.
- [ ] Le tableau mémoire avant/après est dans ton journal ; RB-012 est sur `main`.

**Vérification** : `lab/bin/check 01 30`

<details><summary>Indice 1</summary>

Dans le paquet GitLab, un interrupteur général coupe la supervision embarquée et tous ses *exporters* ; chaque composant a ensuite son propre interrupteur et, pour certains, une adresse d'écoute. Regarde `/opt/gitlab/etc/gitlab.rb.template` (copie du modèle complet) sur `git01`.
</details>

<details><summary>Indice 2</summary>

GitLab considère un runner « online » s'il l'a contacté dans les deux dernières heures. Un runner sain interroge GitLab toutes les quelques secondes : la date du dernier contact est bien plus parlante.
</details>

**Pour aller plus loin** (facultatif) : l'endpoint `/-/metrics` de l'application ; les tableaux de bord officiels GitLab pour Grafana (module 21) ; [sondes de santé](https://docs.gitlab.com/administration/monitoring/health_check/), [liste d'adresses autorisées](https://docs.gitlab.com/administration/monitoring/ip_allowlist/), [environnements à mémoire contrainte](https://docs.gitlab.com/omnibus/settings/memory_constrained_envs/).

---

### M01-E31 — Durcir GitLab  `LIBRE` `★★★`

> **Ticket SEC-258** — *De : Sophie Laurent*
> Audit interne de la forge : beaucoup de réglages par défaut, aucune trace de ce qui a été décidé. Fais-moi un durcissement **argumenté** : chaque mesure, la menace qu'elle traite, son coût pour l'équipe, comment on la vérifie. Et je veux que ce soit reproductible : si on reconstruit la forge (M01-E28), les réglages reviennent sans clic.

**Objectifs pédagogiques**
- Construire un durcissement à partir d'un modèle de menace, pas d'une liste copiée.
- Distinguer réglages de fichier (`gitlab.rb`), réglages d'application (en base) et système.
- Rendre les réglages applicatifs reproductibles et vérifiables (API).
- Mesurer et traiter les effets de bord sur l'outillage.

**Prérequis** : M01-E05, M01-E20, M01-E23, M01-E28.
**Durée indicative** : 3 h.

**Contraintes**
- Comptes : pas d'auto-inscription ; second facteur **obligatoire** pour tous les comptes humains (dont `root` et `<MOI>`), avec un délai d'enrôlement raisonnable ; privilèges d'administration soumis à réauthentification (*Admin Mode*).
- Sessions : pas d'option « se souvenir de moi », durée de session de 12 h au plus.
- Visibilité : aucun projet ni groupe public, et impossible d'en créer pour un non-administrateur.
- Git : pas d'authentification par mot de passe en HTTPS (jetons ou SSH) ; clés SSH DSA interdites, RSA de moins de 3072 bits refusées.
- Runners : plus d'enregistrement par l'ancien jeton d'enregistrement.
- Souveraineté (HDS) : aucune donnée ne part vers l'éditeur ou un tiers à l'insu de l'équipe ; statistiques d'usage et avatars externes désactivés ; tout autre flux sortant de l'application est listé et justifié.
- Réseau : la forge ne peut pas servir de rebond vers le réseau interne (webhooks, intégrations) ; requêtes non authentifiées limitées en débit.
- Reproductibilité : les réglages applicatifs sont appliqués **et vérifiés** par un script idempotent versionné dans `plateforme/medisphere` sous `forge/durcissement/` ; les réglages de fichier sont dans `gitlab.rb`.
- Livrable : `docs/socle/securite/durcissement-gitlab.md` dans `plateforme/medisphere` : modèle de menace, tableau mesure / menace / coût / vérification, mesures écartées avec la raison (dont les fonctions Premium indisponibles), effets de bord traités.
- Effets de bord : avec *Admin Mode*, les jetons d'API d'un administrateur perdent l'accès aux points d'administration, sauf portée dédiée (documentation *Admin Mode*). Le jeton des checks, le jeton d'administration et les scripts de ressources et de panne du workbook en dépendent : l'outillage doit rester fonctionnel (relance `lab/bin/check 01 23` après coup).
- Ne fais rien qui empêche les comptes des personnages d'être utilisés par jetons d'emprunt d'identité (scripts de ressources et de panne).

**Points à traiter** (chacun avec un choix et sa justification)
- Comptes, second facteur, codes de secours de `root` (bris de glace).
- *Admin Mode* et jetons.
- Visibilité, exports et imports de projets.
- Authentification Git, clés SSH, jetons et leur inventaire.
- Flux sortants de l'application, données envoyées à des tiers, vérification de version (et ce qui la remplace).
- Limitation de débit, requêtes vers le réseau local.
- TLS, HSTS, en-têtes (`gitlab.rb` ; attention aux clés NGINX déplacées en 19.2).
- Système de `git01` (SSH, mises à jour de sécurité, comptes).
- Ce qui n'est pas faisable en CE, et la compensation.

**Critères de réussite**
- [ ] Les réglages d'instance respectent toutes les contraintes, vérifiables par l'API avec le jeton des checks.
- [ ] `root` et ton compte ont un second facteur actif ; aucun projet ni groupe public.
- [ ] Le script d'application et de vérification est versionné sous `forge/durcissement/` et réussit en mode vérification.
- [ ] Le rapport est sur `main` de `plateforme/medisphere`, relu par MR.
- [ ] Les checks des exercices précédents qui utilisent l'API d'administration fonctionnent toujours.

**Vérification** : `lab/bin/check 01 31`

<details><summary>Indice 1</summary>

L'API `PUT /application/settings` couvre l'essentiel des réglages de l'interface d'administration ; `GET` permet de vérifier. Un jeton d'administration ne s'élargit pas : on en crée un nouveau avec les portées voulues, puis on révoque l'ancien.
</details>

<details><summary>Indice 2</summary>

Une mesure « dormante » (désactivation automatique des comptes inactifs, par exemple) peut casser des comptes qui ne se connectent jamais mais travaillent par jetons. Lis ce que fait exactement chaque option avant de l'activer.
</details>

**Pour aller plus loin** (facultatif) : [durcissement de GitLab](https://docs.gitlab.com/security/hardening/), [API des réglages](https://docs.gitlab.com/api/settings/), [Admin Mode](https://docs.gitlab.com/administration/settings/sign_in_restrictions/#admin-mode).

---

### M01-E32 — Revue de la configuration CI et pre-commit d'un projet  `REV` `★★`

> **Ticket PLAT-259** — *De : Karim Benali*
> Lucas a préparé la CI, le pre-commit et la configuration de release de `plateforme/outils`, le futur projet de scripts du module 02. Il trouve qu'il a « tout mis » et que « ça marche sur sa branche ». Fais-lui une vraie revue avant qu'il ouvre sa MR : chaque défaut, sa gravité, l'impact concret, la correction. Puis la version corrigée.

**Objectifs pédagogiques**
- Relire une configuration de CI comme un attaquant, comme un exploitant et comme un développeur pressé.
- Repérer les défauts de reproductibilité, de sécurité de la chaîne et de cohérence avec les règles de l'équipe.
- Proposer une version corrigée qui réutilise les gabarits partagés.

**Prérequis** : M01-E15, M01-E16, M01-E24, M01-E25, M01-E26.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Fichiers à relire : [`ressources/M01-E32/`](../ressources/M01-E32/) (`.gitlab-ci.yml`, `.pre-commit-config.yaml`, `.releaserc.json`).
- Ils contiennent une vingtaine de défauts de gravités variées, plus des maladresses mineures.
- Le projet sera écrit en Python (géré par `uv`, M02) et en Bash ; il tournera sur `runner01`.

> ⚠️ **Attention** : ne pousse pas ces fichiers dans un projet de la forge. Pour valider ta version corrigée : éditeur de pipeline de GitLab (*Build → Pipeline editor*, validation) ou API `ci/lint` d'un projet existant, et `pre-commit validate-config`.

**Travail demandé**
1. Lis les trois fichiers une première fois sans rien noter. Puis réponds pour chacun de ces événements : Lucas pousse une branche sans MR ; il ouvre la MR ; un collègue ouvre une MR depuis une autre branche ; la MR est fusionnée ; un développeur clone le projet et lance `pre-commit install` ; une nouvelle version de semantic-release sort ; le job `debug` tourne.
2. Rédige la revue en tableau : n°, fichier et ligne(s), défaut, catégorie (sécurité, fonctionnement, reproductibilité, cohérence), gravité (critique, élevée, moyenne, faible), impact concret, correction.
3. Classe les défauts par ordre de traitement et explique ton ordre. Que faut-il faire **immédiatement**, avant même la revue, à cause d'un de ces défauts ?
4. Propose la version corrigée des trois fichiers, validée.
5. Trois conseils à Lucas sur sa façon de tester une CI.

**Critères de réussite** (auto-évaluation avec le corrigé)
- [ ] Au moins 14 défauts identifiés, dont tous les défauts critiques et élevés du corrigé.
- [ ] Chaque défaut a un impact concret et une correction précise.
- [ ] L'action immédiate est identifiée.
- [ ] La version corrigée passe la validation et ne réintroduit aucun défaut.

<details><summary>Indice 1</summary>

Lis le mot-clé `when` dans la référence de `.gitlab-ci.yml` : `always` ne veut pas dire « à chaque pipeline ». Et demande-toi ce que GitLab masque dans les journaux, et ce qu'il ne peut pas masquer.
</details>

<details><summary>Indice 2</summary>

Pour pre-commit : que se passe-t-il au **deuxième** `pre-commit run` d'un dépôt dont un `rev` est un nom de branche ? Quels types de hooks `pre-commit install` installe-t-il par défaut ? Que demande le hook `gitleaks-docker` sur `adm01` ?
</details>

<details><summary>Indice 3</summary>

Pour la release : relis la décision de M01-E25 sur les écritures dans `main`, et la protection de `main` de M01-E11. Lequel des deux préréglages de commit-analyzer comprend `feat!:` ?
</details>

---

### M01-E33 — ADR : monodépôt ou multidépôts pour la plateforme  `RED` `★★`

> **Ticket PLAT-260** — *De : Claire Morel*
> Avant que les modules 02 à 06 créent cinq projets de plus (`outils`, `images`, `ansible`, `tofu-modules`, `infra`), tranchons : un seul dépôt pour le code de la plateforme, ou un dépôt par composant ? Le plan actuel dit « plusieurs » ; je veux que ce soit une **décision**, pas un accident. Karim relira comme une MR.

**Objectifs pédagogiques**
- Rédiger un ADR au format MADR sur une question d'organisation du code.
- Relier la décision aux contraintes réelles : GitLab CE, CI, versions, droits, HDS, taille de l'équipe.
- Écrire honnêtement les conséquences négatives et les actions qui les compensent.

**Prérequis** : M00-E33 (gabarit MADR), M01-E11, M01-E24, M01-E25.
**Durée indicative** : 1 h 30.

**Travail demandé**
Rédige `docs/socle/adr/ADR-0010-organisation-des-depots.md` dans `plateforme/medisphere`, avec le gabarit de M00-E33, et fais-le passer par une MR (pipeline vert, au moins une discussion de relecture résolue). Il doit traiter au moins :
- trois options réelles (dont une hybride), chacune avec ses « pour » et ses « contre » ;
- les limites de GitLab CE qui pèsent sur le choix (propriétaires de code, approbations, *merge trains*) ;
- le versionnage des composants (semantic-release) et la façon dont un composant en consomme un autre ;
- le cloisonnement des droits (qui peut modifier ce qui touche la production) ;
- le coût CI avec un runner unique ;
- les changements transverses (un module OpenTofu et son utilisation) ;
- une condition de révision de la décision.

**Critères de réussite**
- [ ] L'ADR suit le gabarit et tient en deux pages au plus.
- [ ] Les facteurs de décision précèdent les options et servent à trancher.
- [ ] Les conséquences négatives de l'option retenue sont écrites, avec leurs actions compensatoires (et le module du workbook où elles seront traitées).
- [ ] L'ADR est cohérent avec PLAN.md §4.8, ou propose explicitement de le modifier.
- [ ] Il a été relu par MR et fusionné.

Auto-évaluation : grille fournie dans le corrigé.

<details><summary>Indice 1</summary>

Un monodépôt n'est pas un mauvais choix en soi (de très grandes entreprises l'ont fait) : il demande de l'outillage et des fonctions de forge. Liste ce que tu n'as pas.
</details>

---

### M01-E34 — Questions de production : Git et GitLab à l'échelle  `Q` `★★★`

> **Ticket PLAT-261** — *De : Karim Benali*
> Avant de te confier l'astreinte de la forge, je veux t'entendre sur ces questions. Réponds comme en revue d'architecture : argumente, chiffre quand tu peux, et dis quand « ça dépend » — mais de quoi.

**Objectifs pédagogiques**
- Raisonner sur la disponibilité, la sécurité et la capacité d'une forge et de sa CI.
- Évaluer les limites du dispositif actuel et ce qu'il faudrait pour grandir.

**Prérequis** : M01-E23 à M01-E31.
**Durée indicative** : 1 h 30.

**Questions**

1. Le runner `shell` sert tous les projets. Décris trois attaques qu'un développeur malveillant (ou une dépendance compromise) peut mener depuis un job d'une MR, et pour chacune la mesure qui la limite aujourd'hui et celle qui la supprimerait.
2. QCM — Une variable CI **protégée et masquée** `GITLAB_TOKEN` existe dans un projet. Un développeur (rôle Developer) ouvre une MR depuis une branche non protégée et ajoute `echo $GITLAB_TOKEN | base64` dans un job. Le jeton :
   a) apparaît encodé dans le journal ;
   b) apparaît `[MASKED]` ;
   c) n'est pas disponible dans ce pipeline ;
   d) est disponible mais le job échoue à cause du masquage.
   Et si le développeur pousse directement sur `main` ?
3. Comparez, pour notre forge : sauvegarde de VM (`lab-nuit`), sauvegarde applicative (`gitlab-backup`), réplication (Geo). Pour chacune : RPO, RTO, ce qu'elle protège, ce qu'elle ne protège pas, disponibilité en CE.
4. `gitlab-backup create` pendant que des développeurs poussent : l'archive est-elle cohérente ? Qu'est-ce que `STRATEGY=copy` change, et que ne change-t-il pas ?
5. QCM — Pour passer de GitLab 19.1 à 19.6 :
   a) installer directement 19.6 ;
   b) 19.2, puis 19.5, puis 19.6, en attendant la fin des migrations d'arrière-plan à chaque étape ;
   c) 19.2, 19.3, 19.4, 19.5, 19.6 obligatoirement ;
   d) 19.5 puis 19.6.
6. L'équipe passe de 5 à 60 développeurs et 300 projets. Qu'est-ce qui casse en premier sur notre forge (mémoire, Gitaly, PostgreSQL, Sidekiq, runner) ? Quelles sont les étapes d'évolution (architectures de référence, Gitaly séparé, PostgreSQL externe, stockage objet, runners autoscalés) et lesquelles sont possibles en CE ?
7. Un dépôt fait 4 Go à cause d'anciens binaires. Quelles options côté client (clone partiel, *sparse checkout*, profondeur) et côté serveur (nettoyage, LFS, réécriture d'historique) ? Quel est le coût humain d'une réécriture d'historique sur un dépôt partagé ?
8. Pourquoi la CI contrôle-t-elle **chaque commit** de la MR et pas seulement l'état final, pour Gitleaks comme pour commitlint ? Que faudrait-il de plus pour qu'un secret poussé sur une branche jamais fusionnée ne reste pas sur la forge ?
9. QCM — Les règles de push « messages conformes » et « commits signés » sont des fonctions Premium. En CE :
   a) impossible de les imposer ;
   b) hooks serveur globaux de Gitaly, au prix d'une maintenance sur l'hôte ;
   c) pipeline obligatoire, qui les impose avant la fusion mais pas au push ;
   d) b et c, complémentaires.
   Explique ce que chaque mécanisme voit et ne voit pas.
10. Un jeton de projet `bot-release` (Maintainer, `api`) fuit. Que peut faire l'attaquant, que ne peut-il pas faire ? Tes actions dans l'heure, dans l'ordre.
11. Pourquoi semantic-release ne doit-il pas pousser de commit sur `main` dans notre configuration ? Si l'équipe exigeait un `CHANGELOG.md` dans le dépôt, quelles solutions, et à quel prix ?
12. Les étiquettes `v1.4.2` sont protégées et posées par un bot ; la branche `v1` avance toute seule. Un consommateur te dit : « je veux la reproductibilité totale ». Que lui proposes-tu, et quel outil du module 13 lui épargnera le travail de mise à jour ?
13. QCM — Après `gitlab-backup restore` sur une nouvelle machine, sans avoir restauré `gitlab-secrets.json` :
   a) tout fonctionne, les secrets sont dans la base ;
   b) les dépôts sont perdus ;
   c) les variables CI, les jetons de runner et les secrets 2FA sont illisibles, le reste fonctionne ;
   d) la restauration refuse de démarrer.
14. GitLab est un point unique de défaillance pour la livraison (CI, registre au M13, GitOps au M20). Que se passe-t-il pour la production si la forge tombe pendant 4 h ? Pendant 3 jours ? Qu'en déduis-tu pour son niveau de service et pour le PRA (F5) ?
15. Signature des commits : que prouve un badge « Verified », que ne prouve-t-il pas ? Un attaquant qui a volé une session web de `<MOI>` peut-il produire des commits « Verified » à ton nom ?
16. La sonde de M01-E30 est verte, mais les utilisateurs se plaignent de lenteurs. Liste cinq causes possibles que la sonde ne voit pas et la métrique qui les montrerait.

Les réponses argumentées sont dans le corrigé.

---

### M01-E35 — Workflow complet en temps limité  `CHRONO` `★★★`

> **Ticket PLAT-262** — *De : Karim Benali*
> Examen blanc avant de te donner les droits de Maintainer sur tous les projets : Julien a laissé une branche inachevée avant son congé, j'ai ouvert la MR pour lui. Elle doit sortir aujourd'hui, propre, relue, en version 1.1.0. Tu as **60 minutes**.

**Règles de l'exercice**
- Conditions d'examen : pas de corrigé, pas d'indices ; tes notes, tes runbooks, le CONTRIBUTING et la documentation officielle sont autorisés.
- Durée : **60 minutes** entre la fin du script de préparation (T0) et la Release publiée.
- Préparation (hors chrono) : vérifie que `runner01` est en ligne et que la branche `v1` de `ci-templates` existe, puis lance depuis `adm01` :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ modules/01-git/ressources/M01-E35/fabriquer-depot.sh
  ```
  Il crée un projet neuf `formation/chrono-<AAAAMMJJ-HHMM>` (relancer le script en crée un autre), avec son historique, la branche de Julien, une MR ouverte par Karim et un commentaire de revue. La méthode de fusion est celle de l'équipe (M01-E11) ; pour une autre, voir l'en-tête du script.

**Mission** (tout ce qu'il faut savoir est dans le projet : ticket, MR, revue, historique, pipeline)
- Livrer la fonctionnalité de Julien dans `main`, sans perdre ce qui est arrivé dans `main` entre-temps.
- Respecter toutes les règles de la plateforme (messages, secrets, revue, pipeline) — et traiter un éventuel secret comme un vrai.
- Faire publier la version `v1.1.0` par la chaîne de release, sans la créer à la main.

**Feuille de temps à remplir**

| Jalon | Définition | Heure | Écart depuis T0 |
|---|---|---|---|
| T0 | Fin du script de préparation | | 0 |
| T1 | Diagnostic posé (pourquoi la MR ne peut pas être fusionnée en l'état : liste complète) | | |
| T2 | Branche réécrite et poussée, pipeline de MR vert | | |
| T3 | Revue traitée, discussions résolues, MR fusionnée | | |
| T4 | Release `v1.1.0` publiée | | |

**Après le chrono** (30 minutes) : retour d'expérience d'une demi-page (ce qui t'a ralenti, ce qui manque au CONTRIBUTING ou à tes runbooks, ce que tu automatiserais), et les actions à mener pour le jeton trouvé, comme s'il était réel (M01-E17).

**Critères de réussite**
- [ ] La MR est fusionnée dans `main`, toutes ses discussions résolues ; `main` est toujours protégée.
- [ ] Aucun jeton `glpat-…` dans l'historique de `main` ni des étiquettes.
- [ ] Les commits arrivés depuis `v1.0.0` sont tous conformes, sans `fixup!` ni « WIP ».
- [ ] Le correctif de fuseau horaire de Karim est toujours là ; la fonction SMS est livrée ; la demande de la revue est satisfaite.
- [ ] Le dernier pipeline de `main` est vert et la Release `v1.1.0` existe, publiée par le bot (variable protégée et masquée).
- [ ] T4 − T0 ≤ 60 min ; feuille de temps et retour d'expérience rédigés.

**Vérification** : `lab/bin/check 01 35`

**Pour aller plus loin** (facultatif) : refais l'épreuve avec `WB_MERGE_METHOD=ff`, puis en 40 minutes.
