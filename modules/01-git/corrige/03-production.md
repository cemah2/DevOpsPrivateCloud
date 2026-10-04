# Module 01 — Corrigé du palier 3 : Production

> ⚠️ Corrigé — à lire après avoir cherché.

Les fichiers complets cités ici sont dans [`fichiers/`](fichiers/). Plusieurs sont des **fichiers de référence** réutilisés par les modules suivants : le projet [`plateforme/ci-templates`](fichiers/M01-E24/ci-templates/) (gabarits [`qualite.yml`](fichiers/M01-E24/ci-templates/templates/qualite.yml) et [`release.yml`](fichiers/M01-E25/ci-templates/templates/release.yml), outillage [`outils/release-tools/`](fichiers/M01-E24/ci-templates/outils/release-tools/)), le [`.releaserc.json`](fichiers/M01-E25/.releaserc.json) de référence, les [hooks serveur](fichiers/M01-E26/forge/hooks/), la [sauvegarde de GitLab](fichiers/M01-E28/) et les runbooks RB-010 à RB-012.

**Ce qui a été testé, ce qui ne l'a pas été.** Testés hors de la forge : les hooks `pre-receive` et leur banc d'essai (Git 2.43), la logique des jobs `commitlint` et `gitleaks` (rejouée dans un dépôt local avec commitlint 21.2.3 et Gitleaks 8.30.0), la résolution des modules par commitlint et semantic-release depuis `/opt/release-tools` (`NODE_PATH`), le chargement du `.releaserc.json` par semantic-release 25.0.9 en simulation, l'installation `npm ci --ignore-scripts` du verrou (npm 11), la validation des configurations pre-commit. **Non rejoués sur une instance GitLab 19 réelle** : le comportement exact des pipelines (variables prédéfinies, `include`, ancres), les appels d'API, la configuration de Gitaly, la restauration, la mise à jour et les réglages de supervision. Les points incertains sont signalés « ⚠️ À vérifier sur ta version » : signale tes retours.

---

### M01-E23 — Installer GitLab Runner sur `runner01`

**Solution**

*1. La VM* : [`fichiers/M01-E23/creer-runner01.sh`](fichiers/M01-E23/creer-runner01.sh), en root sur `pve01` (`git01` a l'ordre de démarrage 4 en M01-E04, d'où 5 par défaut). Puis la déclaration DNS ([`dnsmasq-runner01.extrait`](fichiers/M01-E23/dnsmasq-runner01.extrait)) et l'alias SSH ([`ssh-config-runner01.extrait`](fichiers/M01-E23/ssh-config-runner01.extrait)) :

```
root@pve01:~# qm status 1007 || echo "VMID libre"
root@pve01:~# ./creer-runner01.sh
admin@dns01:~$ sudo nano /etc/dnsmasq.d/medisphere.conf && sudo dnsmasq --test && sudo systemctl restart dnsmasq
admin@adm01:~$ dig +short runner01.par1.medisphere.internal @10.10.20.10 ; dig +short -x 10.10.20.15 @10.10.20.10
admin@adm01:~$ ssh runner01 hostname -f
```

Pourquoi une VM distincte : un job de CI exécute du code arbitraire venu d'une branche. Sur `git01`, il tournerait à côté de la base, des dépôts et de `gitlab-secrets.json` ; un job gourmand affamerait GitLab (8 Go déjà justes). Séparer, c'est limiter le rayon d'impact et pouvoir détruire et recréer le runner sans toucher à la forge.

*2 à 6. Paquets, outils, garde-fous* : [`fichiers/M01-E23/installer-runner.sh`](fichiers/M01-E23/installer-runner.sh), rejouable :

```
admin@adm01:~$ scp ~/pki-provisoire/ca.crt runner01:/tmp/medisphere-provisoire.crt
admin@adm01:~$ scp installer-runner.sh runner01:
admin@runner01:~$ sudo RUNNER_VERSION=19.4.<Z> GITLEAKS_VERSION=8.30.1 ./installer-runner.sh
```

Le script du dépôt de paquets dépose la clé de signature du dépôt (trousseau dans `/usr/share/keyrings/` ou `/etc/apt/keyrings/` selon sa version) et un fichier de sources `runner_gitlab-runner` dans `/etc/apt/sources.list.d/`, puis lance `apt update`. Le lire avant de l'exécuter en root est le minimum : c'est un script téléchargé qui modifie la confiance d'APT.

`gitlab-runner-helper-images` : le paquet `gitlab-runner` en dépend (installer des versions différentes donne une erreur de dépendances). Les images d'assistance servent aux exécuteurs à conteneurs (clonage, cache, artefacts) ; avec `shell`, elles ne servent pas, mais les avoir à la bonne version évite un téléchargement le jour où un exécuteur Docker est ajouté (M12).

`apt-mark hold` : le runner suit GitLab (règle de compatibilité : même `major.minor`, voir E29) ; une mise à jour non planifiée par `apt upgrade` le désynchroniserait.

*4. Création et enregistrement.* Dans l'interface : *Admin → CI/CD → Runners → Create instance runner*, étiquettes `shell,socle`, *Run untagged jobs* décoché, description `runner01-shell`, *Maximum job timeout* 3600. GitLab affiche le jeton `glrt-…` **une fois**. Sur `runner01` :

```
admin@runner01:~$ read -rs JETON          # coller le jeton, Entrée
admin@runner01:~$ sudo gitlab-runner register --non-interactive \
                    --url https://git01.par1.medisphere.internal \
                    --token "$JETON" --executor shell --description runner01-shell
admin@runner01:~$ unset JETON
admin@runner01:~$ sudo gitlab-runner list
admin@runner01:~$ sudo gitlab-runner verify
Verifying runner... is valid                        runner=…
admin@runner01:~$ sudo ls -l /etc/gitlab-runner/config.toml
-rw------- 1 root root … /etc/gitlab-runner/config.toml
```

Exemple de résultat : [`config.toml.exemple`](fichiers/M01-E23/config.toml.exemple). Les étiquettes, « jobs sans étiquette », le verrouillage, le niveau d'accès et le délai maximal **ne sont plus** dans `config.toml` ni dans la commande : ils appartiennent à l'objet runner côté serveur, créé par un utilisateur identifié (traçabilité) avec un jeton propre à ce runner. Avec l'ancien jeton d'enregistrement (un secret partagé par toute l'instance), n'importe quel détenteur pouvait enregistrer autant de runners qu'il voulait et choisir lui-même ses étiquettes : un runner pirate pouvait capter des jobs (et leurs secrets). L'ancien flux est déprécié, et sa suppression annoncée pour la 20.0.

*5. Concurrence* : `concurrent = 2` dans `config.toml` (redémarrage du service ou rechargement automatique du fichier). Deux jobs `lint` en parallèle sur 2 vCPU restent raisonnables ; au-delà, chaque job ralentit l'autre et le temps total ne baisse plus. C'est une valeur à mesurer quand les pipelines grossiront (M02-M05).

*6. Outils.* `uv` s'installe avec son installeur officiel (`UV_INSTALL_DIR=/usr/local/bin`, `UV_NO_MODIFY_PATH=1`), `pre-commit` par `uv tool install` avec `UV_TOOL_DIR=/opt/uv-tools` et `UV_TOOL_BIN_DIR=/usr/local/bin`. Le Python imposé (`--python /usr/bin/python3`) évite que `uv` télécharge un Python géré dans le dossier personnel de root, illisible par `gitlab-runner` : l'outil fonctionnerait pour root et pas pour les jobs. Gitleaks : binaire officiel, somme vérifiée contre le fichier de sommes de la version (le paquet Debian, 8.16, est trop ancien : commandes `gitleaks git`/`dir` absentes).

*7. Essai* : [`essai-runner.gitlab-ci.yml`](fichiers/M01-E23/essai-runner.gitlab-ci.yml). Le job `etiquette-shell` réussit ; le job `sans-etiquette` reste *pending* avec le message « This job is stuck because… no runners… that can run untagged jobs » (formulation à vérifier selon ta version). Réponses :
- utilisateur : `gitlab-runner` (`id` → `uid=…(gitlab-runner)`), sans privilèges ;
- dossier : `/home/gitlab-runner/builds/<court-jeton>/<n>/<groupe>/<projet>` ;
- le job du projet A peut **lire** les dossiers de build du projet B (même utilisateur), les caches, le dossier personnel de `gitlab-runner` (`~/.cache/pre-commit`…), et y **écrire** : empoisonner un cache ou un environnement pre-commit utilisé ensuite par un autre projet ;
- `rm -rf ~` détruit les builds, les caches et les environnements de tous les projets : les jobs suivants les reconstruisent (lenteur), mais rien hors de `/home/gitlab-runner` n'est touché, parce que l'utilisateur n'a aucun droit ailleurs.

*8. Garde-fous* : `id -nG gitlab-runner` ne doit afficher que `gitlab-runner` ; `sudo -l -U gitlab-runner` : « not allowed ». Avec l'exécuteur `shell`, **tout** code poussé dans **n'importe quelle** branche s'exécute sous cet utilisateur : un `sudo` sans mot de passe en ferait root de `runner01` pour tout développeur, et donc maître de tous les jobs, de leurs secrets et du réseau INFRA.

*9. Documentation* : ligne `runner01 | 1007 | 10.10.20.15 | GitLab Runner 19.4.z (shell) | socle, role-runner` dans `inventaire.md` ; flux `runner01 → git01:443` (API des runners, clone HTTPS par jeton de job ; intra-VLAN, non filtré par `gw01`), `runner01 → Internet:443` (paquets, npm, dépôts des hooks pre-commit), `adm01 → runner01:22`.

**Explications**

Un runner ne reçoit aucune connexion : il **interroge** GitLab (`POST /api/v4/jobs/request`, toutes les 3 s par défaut), reçoit un job avec ses variables et un jeton de job éphémère, clone le dépôt avec ce jeton, exécute le script, renvoie journal et statut. C'est pourquoi aucun flux entrant n'est ouvert vers `runner01`, et pourquoi un runner derrière un NAT fonctionne. L'exécuteur décide **où** tourne le script : `shell` directement sur l'hôte, `docker` dans un conteneur jetable, `kubernetes` dans un pod. `shell` est le plus simple et le plus rapide, et le moins isolé.

**Alternatives**
- Exécuteur `docker` sur `runner01` : isolation par conteneur, images d'outils versionnées ; reporté au M12 (conteneurs pas encore enseignés).
- Runner de projet ou de groupe plutôt que d'instance : limite qui peut l'utiliser (utile pour un runner qui porte des droits de déploiement).
- Runner créé par l'API (`POST /user/runners`, portée `create_runner`), reproductible par script.

**Pièges classiques**
- Coller le jeton `glrt-` dans la commande : il reste dans `~/.bash_history` et dans `ps` pendant l'exécution.
- Passer `--tag-list` ou `--run-untagged` à `register` avec un jeton `glrt-` : sans effet, les réglages sont côté serveur.
- Versions différentes de `gitlab-runner` et `gitlab-runner-helper-images` : apt refuse (dépendances non satisfaites).
- Installer les outils pour root seulement (`pip install --user`, `uv tool install` sans variables) : « command not found » dans les jobs.
- Ajouter `gitlab-runner` au groupe `sudo` « pour que le pipeline puisse installer un paquet ».
- Fichier `~/.bash_logout` de `gitlab-runner` qui vide l'écran : sur les anciennes versions, les jobs échouaient en *prepare environment* ; les paquets récents n'utilisent plus `/etc/skel` pour cet utilisateur (à vérifier si le dossier personnel a été créé autrement).

**En production chez MédiSphère**
Runners éphémères (une VM ou un pod par job, M19) pour les projets qui exécutent du code tiers ; runners dédiés et `ref_protected` pour les déploiements ; outils des runners installés par Ansible (M04) depuis le même verrou ; supervision du dernier contact de chaque runner (E30) ; rotation du jeton de runner (`gitlab-runner reset-token` ou API).

---

### M01-E24 — Pipeline de qualité obligatoire avant fusion

**Solution**

Projet complet : [`fichiers/M01-E24/ci-templates/`](fichiers/M01-E24/ci-templates/) (`templates/qualite.yml`, `.gitlab-ci.yml` d'auto-test, `README.md`, `outils/release-tools/`) ; les fichiers de référence `.pre-commit-config.yaml` et `commitlint.config.mjs` sont ceux de M01-E15 et M01-E14. CI de `plateforme/medisphere` : [`fichiers/M01-E24/medisphere/.gitlab-ci.yml`](fichiers/M01-E24/medisphere/.gitlab-ci.yml).

*1. Node et `/opt/release-tools`.* Node.js 24 par le dépôt NodeSource, comme sur `adm01` en M01-E14 (mêmes fichiers de sources et de préférence APT). Puis, dans un clone de `ci-templates` :

```
admin@adm01:~/src/ci-templates/outils/release-tools$ npm install --package-lock-only   # génère/actualise le verrou (npm 11)
admin@runner01:~$ git clone https://git01.par1.medisphere.internal/plateforme/ci-templates.git
admin@runner01:~$ sudo ci-templates/outils/release-tools/installer-release-tools.sh
medisphere-release-tools@1.0.0 /opt/release-tools
├── @commitlint/cli@21.2.3
├── @commitlint/config-conventional@21.2.3
├── @semantic-release/gitlab@13.3.3
├── conventional-changelog-conventionalcommits@10.4.0
└── semantic-release@25.0.9
```

[`package.json`](fichiers/M01-E24/ci-templates/outils/release-tools/package.json) fixe des versions exactes ; [`package-lock.json`](fichiers/M01-E24/ci-templates/outils/release-tools/package-lock.json) fige **tout l'arbre** (≈ 390 paquets) avec leurs empreintes d'intégrité. `npm ci` installe exactement le verrou, échoue s'il ne correspond pas à `package.json`, et repart d'un `node_modules` vide ; `npm install` peut résoudre de nouvelles versions des dépendances transitives et réécrire le verrou. `--ignore-scripts` empêche les scripts `preinstall`/`postinstall` des paquets de s'exécuter en root : c'est le vecteur classique des paquets npm compromis, et aucun de ces outils n'en a besoin pour fonctionner (vérifié). Le [script d'installation](fichiers/M01-E24/ci-templates/outils/release-tools/installer-release-tools.sh) installe dans un dossier neuf puis bascule, pour ne jamais exposer un `node_modules` à moitié écrit à un job en cours. ⚠️ À vérifier : un verrou généré par npm 10 a été refusé par `npm ci` lors des essais (incohérence sur une dépendance transitive) ; avec npm 11 (fourni avec Node 24), aucun problème.

*3. `templates/qualite.yml`* : [fichier](fichiers/M01-E24/ci-templates/templates/qualite.yml). Points clés :

- `workflow` : pipeline de MR si `CI_PIPELINE_SOURCE == "merge_request_event"` ; **pas** de pipeline de branche si une MR est ouverte (`CI_OPEN_MERGE_REQUESTS`), sinon chaque push produirait deux pipelines ; pipeline de branche sinon ; rien sur les étiquettes.
- Plage de commits (ancre `&plage-commits`, partagée par `commitlint` et `gitleaks`) :

  | Situation | Début (exclu) | Pourquoi |
  |---|---|---|
  | Pipeline de MR | `CI_MERGE_REQUEST_DIFF_BASE_SHA` | point de divergence avec la cible : exactement les commits de la MR |
  | Branche sans MR | `git merge-base` avec la branche par défaut | idem, calculé |
  | `main` après fusion | `CI_COMMIT_BEFORE_SHA` | ce qui vient d'arriver (commit de fusion ignoré par commitlint) |
  | Premier push d'un projet | aucun (`CI_COMMIT_BEFORE_SHA` = zéros) | commitlint : dernier commit (`--last`) ; gitleaks : tout l'historique |

- Profondeur : GitLab clone par défaut avec une profondeur limitée (20 commits) ; la base de la MR ou `CI_COMMIT_BEFORE_SHA` peuvent ne pas être dans le clone (`fatal: bad revision`, ou pire une plage tronquée qui « passe »). D'où `GIT_DEPTH: "0"` dans ces deux jobs.
- `pre-commit` : `SKIP: gitleaks`. Le hook `gitleaks` de pre-commit lance `gitleaks git --pre-commit --staged` : il ne regarde que les modifications indexées, et en CI il n'y en a aucune. Le job `gitleaks` fait le vrai travail, sur l'historique. `--show-diff-on-failure` affiche les modifications qu'un hook correcteur (espaces, fin de fichier) aurait faites : le développeur voit quoi corriger sans relancer chez lui.
- `commitlint` : `NODE_PATH=/opt/release-tools/node_modules`. commitlint résout `extends` depuis le dossier du projet (aucun `node_modules`) puis le dossier global de npm (pas `/opt/release-tools`) : sans aide, `Cannot find module "@commitlint/config-conventional"`. Sa résolution passe par le mécanisme CommonJS de Node, qui honore `NODE_PATH` (vérifié avec commitlint 21.2.3). `--default-config` sert de filet si un projet n'a pas de configuration : sans configuration ni option, commitlint s'arrête avec le code 9 (« Please add rules »). Après commitlint, une étape refuse les `fixup!`/`squash!`/`amend!` restés dans la plage (commitlint les ignore volontairement, M01-E12).
- `gitleaks` : `gitleaks git --log-opts="<plage>" --redact`, rapport JUnit en artefact (affiché dans la MR), secret jamais en clair.

*4. Auto-test* : [`.gitlab-ci.yml`](fichiers/M01-E24/ci-templates/.gitlab-ci.yml) de `ci-templates` : `include: local` (la version de la branche en cours, et non `v1`), plus le job `outils-a-jour` qui compare le verrou versionné à celui de `/opt/release-tools`. Un gabarit cassé échoue dans **sa propre** MR, avant d'atteindre les autres projets.

*5. Branche `v1`* : *Code → Branches → New branch* `v1` depuis `main`, puis *Settings → Repository → Protected branches* : `v1`, *Allowed to merge* et *Allowed to push* : Maintainers, *Allowed to force push* : non.

*6. Projets consommateurs* : *Settings → Merge requests → Merge checks* : *Pipelines must succeed* coché, *Skipped pipelines are considered successful* décoché (ou API : `only_allow_merge_if_pipeline_succeeds=true`, `allow_merge_on_skipped_pipeline=false`). Le second compte : un commit qui ne déclenche aucun job (règles qui excluent tout, `[skip ci]`, option de push `ci.skip`) produirait un pipeline « ignoré », considéré comme réussi : un contournement trivial de la CI obligatoire.

*7. Blocage* : la MR montre `commitlint` en échec (« type may not be empty ») et `gitleaks` en échec (`RuleID: private-key`, `Secret: REDACTED`), *Merge blocked: pipeline must succeed*. Ce qui subsiste après fermeture : les commits restent accessibles par la référence `refs/merge-requests/<iid>/head` et dans l'interface de la MR ; la clé jetable reste dans les objets du dépôt jusqu'au nettoyage (M01-E17). Pour un vrai secret : rotation immédiate, la purge ne suffit jamais.

*8. Mesure* : premier passage du job `pre-commit` : 1 à 3 minutes (création des environnements des hooks, téléchargés depuis GitHub, dans `~gitlab-runner/.cache/pre-commit`) ; ensuite quelques secondes (environnements en cache, partagés entre projets : voir E23 et E34).

**Explications**

La CI ne remplace pas pre-commit : pre-commit donne un retour en quelques secondes **avant** le commit, la CI garantit que personne ne l'a contourné. Les deux exécutent **la même configuration** (le `.pre-commit-config.yaml` du projet, la même configuration commitlint), sinon on finit avec des écarts « ça passe chez moi ». Mutualiser par `include: project` donne un seul endroit à corriger, et `ref: v1` donne aux consommateurs une version stable plutôt que l'état courant de `main` de `ci-templates`.

**Alternatives**
- Composants CI/CD (`include: component`, catalogue) : entrées typées, versions sémantiques natives ; plus moderne, à envisager quand les gabarits se multiplieront (M19).
- Outils dans une image de conteneur plutôt que sur l'hôte : reproductible sans `/opt/release-tools` ; nécessite l'exécuteur Docker (M12).
- `npx commitlint` dans le job : télécharge à chaque pipeline, non figé, dépend du registre npm.

**Pièges classiques**
- `rules` et `workflow` mal combinés : deux pipelines par push (branche + MR), ou aucun pipeline de MR (le blocage ne s'applique jamais).
- `commitlint --from X --to X` : plage vide, job vert, rien contrôlé.
- Contrôler seulement `HEAD` (`--last`) : les commits intermédiaires de la MR passent.
- `gitleaks dir .` (état final) : un secret ajouté puis retiré dans la MR passe.
- `include` d'une `ref: main` : toute fusion dans `ci-templates` s'applique immédiatement à tous les projets.
- `check-yaml` de pre-commit sur des gabarits qui utilisent des balises GitLab (`!reference`) : échec ; option `--unsafe` (syntaxe seule), ou ancres YAML comme ici.

**En production chez MédiSphère**
Les règles « pipeline obligatoire » et « pipeline ignoré ≠ réussi » sont appliquées par script à chaque création de projet (M02) puis vérifiées par le mini-projet (E47) ; `ci-templates` est relu par deux personnes ; les outils des runners sont installés par Ansible depuis le même verrou ; la durée des pipelines est suivie (M21).

---

### M01-E25 — semantic-release : versions, changelog et releases automatiques

**Solution**

Fichiers : [`templates/release.yml`](fichiers/M01-E25/ci-templates/templates/release.yml), [`.releaserc.json`](fichiers/M01-E25/.releaserc.json) (copié dans les deux projets), [`.gitlab-ci.yml` de `ci-templates`](fichiers/M01-E25/ci-templates/.gitlab-ci.yml), [`.gitlab-ci.yml` de `medisphere`](fichiers/M01-E25/medisphere/.gitlab-ci.yml).

*1. Les étapes* (semantic-release 25) :

| Étape | Extension (ici) | Rôle |
|---|---|---|
| `verifyConditions` | `@semantic-release/gitlab` | jeton présent, droits suffisants sur le projet |
| `analyzeCommits` | `@semantic-release/commit-analyzer` | type de version d'après les commits depuis la dernière étiquette |
| `verifyRelease` | — | (contrôles supplémentaires, aucun ici) |
| `generateNotes` | `@semantic-release/release-notes-generator` | notes de version (préréglage `conventionalcommits`) |
| `prepare` | — | (modifications de fichiers : aucune, volontairement) |
| *(étiquette)* | cœur de semantic-release | crée `vX.Y.Z` sur le commit et la pousse |
| `publish` | `@semantic-release/gitlab` | Release GitLab avec les notes |
| `success` / `fail` | `@semantic-release/gitlab` | commentaire sur les MR et tickets livrés / ticket « La release automatique échoue » |

Que des `docs:` et `chore:` : aucune version (« There are no relevant changes »), aucun tag : c'est voulu. `feat!:` ou `BREAKING CHANGE:` : version majeure (avec le préréglage `conventionalcommits` ; le préréglage `angular` par défaut ne comprend pas `!`). `socle-v0` ne correspond pas au `tagFormat` `v${version}` : ignorée, la première version de `medisphere` sera `1.0.0`.

*2. Simulation* sur `adm01` (même verrou, dans `~/.local/release-tools`) :

```
admin@adm01:~$ mkdir -p ~/.local/release-tools && cp ~/src/ci-templates/outils/release-tools/package*.json ~/.local/release-tools/
admin@adm01:~$ (cd ~/.local/release-tools && npm ci --omit=dev --ignore-scripts)
admin@adm01:~/medisphere$ GITLAB_TOKEN="$(<~/.config/workbook/gitlab-admin.token)" \
    NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt \
    ~/.local/release-tools/node_modules/.bin/semantic-release --dry-run --no-ci
… The next release version is 1.0.0
… Release note for version 1.0.0: …
```

La variable n'existe que pour cette commande (pas d'`export`) et n'est pas affichée. Le mode simulation vérifie quand même les droits et l'accès en push (`git push --dry-run`) : c'est utile.

*3. Jeton et protections.* *Settings → Access tokens* : nom `bot-release`, rôle *Maintainer*, portées `api` et `write_repository`, expiration dans un an au plus (note la date dans le runbook et dans l'agenda de l'équipe). *Settings → CI/CD → Variables* : `GITLAB_TOKEN`, *Protect variable* et *Mask variable* cochés (et *Masked and hidden* si ta version le propose : la valeur ne se relit plus dans l'interface). *Settings → Repository → Protected tags* : `v*`, *Allowed to create* : Maintainers.
- Maintainer : seuls les Maintainers peuvent créer des étiquettes `v*` protégées ; Developer suffirait pour l'API des Releases, pas pour l'étiquette.
- Jeton de projet plutôt que personnel : il n'agit que sur ce projet (un vol n'expose pas les autres), il appartient à un bot (pas à une personne qui peut partir), et ses actions sont tracées comme celles du bot. Le jour de l'expiration, le job `release` échoue (`401`) et la publication s'arrête : le ticket créé par l'étape `fail` ne pourra même pas être ouvert (même jeton). D'où le runbook de rotation.

*4. Le gabarit* : job `release` sur la branche par défaut protégée (`CI_COMMIT_REF_PROTECTED == "true"`), si `.releaserc.json` existe ; `resource_group: release` (deux pipelines de `main` rapprochés ne publient jamais en même temps) ; `GIT_DEPTH: "0"` et `GIT_STRATEGY: clone` (tout l'historique, toutes les étiquettes, pas d'étiquette locale périmée d'un ancien build sur l'exécuteur shell) ; `NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt` (Node n'utilise pas le magasin du système : sans cela, `unable to get local issuer certificate` vers `git01` ; le paquet de Debian contient la racine provisoire, et contiendra celle de step-ca au M06 sans changer le gabarit). Dans un pipeline de MR, le job n'existe pas (règle), et la variable protégée n'est de toute façon pas fournie à une référence non protégée : une MR malveillante ne peut ni publier ni lire le jeton.

*5. Première publication* : après fusion, le job `release` affiche « Published release 1.0.0 », l'étiquette `v1.0.0` apparaît (protégée), la Release contient les notes groupées par type, et chaque MR livrée reçoit le commentaire « Livré dans la version 1.0.0 ».

*6. Canal majeur* : job `publier-branche-majeure` de `ci-templates` : après `release`, si une étiquette `vX.Y.Z` pointe sur le commit du pipeline, pousse ce commit sur `refs/heads/vX` (avance rapide, sans `--force`), avec `-o ci.skip`. Une branche plutôt qu'une étiquette mobile : une étiquette protégée ne se déplace pas sans être supprimée et recréée (et une étiquette qui bouge trompe tous ceux qui l'ont déjà récupérée : Git ne met pas à jour une étiquette existante lors d'un `fetch`) ; une branche est faite pour avancer, se protège, et son historique montre chaque version adoptée.

*7. Cycle* : `fix:` → `1.0.1`, `feat:` → `1.1.0`, `v1` suit ; un projet consommateur prend la nouvelle version au pipeline suivant. MR `docs:` seule : aucune version, `v1` ne bouge pas.

*8. Runbook* : section « Renouveler le jeton `bot-release` » (créer le nouveau jeton, remplacer la variable, relancer le job `release` d'un pipeline de `main`, révoquer l'ancien, noter la nouvelle date).

**Explications**

semantic-release transforme une convention (les messages) en décision (la version). C'est ce qui rend Conventional Commits rentable : le message écrit pour le relecteur sert aussi à la machine. Pas de commit de release dans `main` : `main` est protégée (push : personne, M01-E11), un commit du bot exigerait de lui ouvrir le push direct ; il relancerait aussi un pipeline (boucle à casser par `[skip ci]`), et ajouterait du bruit à l'historique. Les notes vivent dans les Releases, consultables et liées aux MR.

Résolution des extensions : semantic-release charge ses extensions et ses préréglages **d'abord à côté de lui-même**, puis depuis le projet : tous installés dans `/opt/release-tools/node_modules`, ils sont trouvés sans `NODE_PATH` (vérifié avec 25.0.9).

**Alternatives**
- `@semantic-release/changelog` + `@semantic-release/git` : `CHANGELOG.md` dans le dépôt, au prix d'un push direct du bot sur `main` (règle de protection avec exception pour le bot) et d'un commit par version.
- Publier depuis les étiquettes posées à la main (job sur `$CI_COMMIT_TAG`) : plus simple, mais le numéro de version redevient un choix humain.
- release-please ou Changesets : MR de release préparée par un bot, relue puis fusionnée : la publication passe par une revue.

**Pièges classiques**
- `GIT_DEPTH` par défaut : « no previous release » alors que des étiquettes existent, ou version recalculée depuis le début.
- Variable protégée et job lancé sur une branche non protégée : `ENOGLTOKEN`.
- Variable masquée refusée : la valeur doit respecter les contraintes de masquage (longueur, caractères) ; un jeton de projet les respecte.
- Jeton Developer : la création de l'étiquette protégée `v*` échoue.
- Oublier `preset: conventionalcommits` dans **les deux** extensions : analyse et notes incohérentes.
- `semantic-release --version` affiche parfois la version du `package.json` du dossier courant : pour connaître la version installée, `npm ls --prefix /opt/release-tools --depth=0`.

**En production chez MédiSphère**
Jetons `bot-release` inventoriés (date d'expiration suivie par la sonde ou un script hebdomadaire), rotation par runbook, ruptures de `ci-templates` décidées par ADR, notes de version liées aux tickets (traçabilité exigée par l'audit HDS : qui a livré quoi, quand, relu par qui).

---

### M01-E26 — Hooks côté serveur : imposer les règles même sans pre-commit

**Solution**

Fichiers à versionner dans `plateforme/medisphere` sous `forge/hooks/` : [`pre-receive.d/10-messages-conventionnels`](fichiers/M01-E26/forge/hooks/pre-receive.d/10-messages-conventionnels), [`pre-receive.d/20-taille-fichiers`](fichiers/M01-E26/forge/hooks/pre-receive.d/20-taille-fichiers), [`tester-hooks.sh`](fichiers/M01-E26/forge/hooks/tester-hooks.sh) (14 scénarios), [`deployer-hooks.sh`](fichiers/M01-E26/forge/hooks/deployer-hooks.sh). Configuration : [`gitlab.rb.extrait`](fichiers/M01-E26/gitlab.rb.extrait).

*1. Lecture.*
- Entrée : une ligne par référence, `<ancien> <nouveau> <référence>` ; ancien = zéros pour une création, nouveau = zéros pour une suppression.
- Ordre : hooks intégrés de GitLab (droits, protections), hook du projet, hooks `<projet>.d/`, puis hooks globaux de `pre-receive.d/` **par ordre alphabétique** ; le premier code non nul arrête tout et refuse **tout** le push (pas seulement la référence fautive).
- Variables : `GL_ID`, `GL_USERNAME`, `GL_PROTOCOL` (`ssh`, `http` ou `web`), `GL_PROJECT_PATH`, `GL_REPOSITORY`, et `GIT_PUSH_OPTION_COUNT`/`GIT_PUSH_OPTION_<i>`.
- Quarantaine : pendant `pre-receive`, les objets reçus sont dans un dossier temporaire (variables `GIT_OBJECT_DIRECTORY`, `GIT_ALTERNATE_OBJECT_DIRECTORIES`) ; s'ils sont refusés, ils disparaissent sans avoir jamais été dans le dépôt. Les références ne sont pas encore mises à jour : `--not --all` exclut tout ce qui était accessible **avant** ce push, il reste exactement les commits nouveaux.
- Fusion dans l'interface : GitLab crée le commit de fusion et met à jour `main` en passant par les mêmes hooks, avec `GL_PROTOCOL=web`. Le seul commit nouveau est le commit de fusion `Merge branch '…' into 'main'` : d'où l'exception, sinon plus aucune fusion ne passe.

*2-3. Écriture et tests* : voir les fichiers. Choix notables : périmètre testé en premier (`GL_PROJECT_PATH` commençant par `plateforme/`), puis aucune commande réseau ; un seul `git log -z` pour tous les messages (rapide même pour des centaines de commits) ; `git rev-list --objects | git cat-file --batch-check` pour les tailles (taille **décompressée** du blob, ce qui compte pour le dépôt) ; dédoublonnage des commits présents dans plusieurs références ; messages `GL-HOOK-ERR:` avec la liste des fautifs et la correction ; si `git` est introuvable, refus explicite plutôt qu'acceptation silencieuse. Le banc d'essai simule la quarantaine par `GIT_ALTERNATE_OBJECT_DIRECTORIES` :

```
admin@adm01:~/medisphere$ forge/hooks/tester-hooks.sh
[OK]  message conforme accepté
[OK]  message non conforme refusé (plateforme)
…
[OK]  gros fichier accepté hors périmètre

Tous les scénarios sont conformes.
```

*4. Gitaly.* Le `gitlab.rb` de M01-E04 contient déjà `gitaly['configuration'] = { concurrency: [...] }`. On **ajoute** la clé `hooks:` dans ce même hash ([extrait](fichiers/M01-E26/gitlab.rb.extrait)) :

```
admin@git01:~$ sudo cp -a /etc/gitlab/gitlab.rb /etc/gitlab/gitlab.rb.$(date +%F-%H%M)
admin@git01:~$ sudo nano /etc/gitlab/gitlab.rb
admin@git01:~$ sudo gitlab-ctl reconfigure
admin@git01:~$ sudo grep -E 'custom_hooks_dir|max_per_repo' /var/opt/gitlab/gitaly/config.toml
custom_hooks_dir = '/var/opt/gitlab/gitaly/custom_hooks'
max_per_repo = 3
max_per_repo = 3
```

Écrire un second `gitaly['configuration'] = { hooks: … }` plus bas **remplacerait** le premier : les limites de concurrence disparaîtraient en silence (aucun message de `reconfigure`), et on ne s'en apercevrait qu'au premier pic de clones. D'où le contrôle sur le fichier **généré**. ⚠️ À vérifier sur ta version : le format exact de `config.toml` (guillemets simples ou doubles).

*5. Déploiement* : `forge/hooks/deployer-hooks.sh` (tests locaux, copie, installation `git:git 0755` dans un dossier neuf puis bascule avec sauvegarde de l'ancien, tests sur `git01` en tant que `git`). `git` sur `git01` : les hooks ont un repli sur `/opt/gitlab/embedded/bin/git`, mais ce binaire est interne au paquet (son chemin et sa présence peuvent changer d'une version à l'autre, Gitaly embarquant désormais ses propres binaires Git) ; installer le paquet `git` de Debian donne une dépendance explicite et stable. ⚠️ À vérifier sur ta version : la présence de `/opt/gitlab/embedded/bin/git` et le `PATH` fourni aux hooks par Gitaly.

*6. Épreuve réelle* :

```
admin@adm01:~/medisphere$ git push origin essai-hook
remote: GitLab: push refusé par la forge MédiSphère : messages de commit non conformes (projets plateforme/*).
remote: GitLab:   3f2a1c9d0e « Ajoute l'essai » (essai-hook) : en-tête non conforme
…
 ! [remote rejected] essai-hook -> essai-hook (pre-receive hook declined)
```

(Préfixe exact de l'affichage côté client à vérifier sur ta version.) Vers `formation/git-labo` : accepté. Un fichier de 6 Mio : refusé. Une MR conforme fusionnée dans l'interface : acceptée (commit de fusion ignoré).

*7. Bris de glace* : option de push `git push -o derogation=<TICKET>` acceptée seulement pour les comptes listés dans `/etc/gitlab/wb-hooks/derogations.txt` (fichier de root, sauvegardé par `backup-etc`), journalisée par `logger` (`journalctl -t wb-hooks`). On ne désactive jamais un contrôle pour tout le monde parce qu'un cas l'exige.

**Explications**

Le hook serveur est le seul contrôle que le client ne peut pas contourner : il voit les objets avant qu'ils existent dans le dépôt. Il est volontairement **minimal** (format de l'en-tête, taille) : une règle serveur trop riche bloque tout le monde au moindre bogue, se teste mal et se met à jour moins souvent que la CI. Le contrôle complet (casse, pied de page, secrets) reste en CI, où un faux positif ne coûte qu'un pipeline rouge.

**Alternatives**
- Hook par projet (*Admin → Projects → Server hooks*, ou API Gitaly) : ciblé, mais à maintenir projet par projet.
- Lancer commitlint dans le hook : règles identiques à la CI, mais Node.js sur `git01`, quelques centaines de millisecondes par push, et une dépendance de plus dans le chemin critique de toute la forge.
- Gitleaks dans le hook : bloquerait un secret avant même qu'il soit stocké ; coûteux sur un gros push et source de faux positifs bloquants. À considérer avec une liste blanche soignée.

**Pièges classiques**
- Contrôler `<ancien>..<nouveau>` : pour une nouvelle branche, l'ancien vaut zéro (erreur), et pour une branche qui reprend des commits déjà présents ailleurs, on recontrôle tout l'historique.
- Oublier les commits de fusion de GitLab : plus aucune MR ne fusionne.
- Contrôler seulement l'arbre du dernier commit pour la taille : un gros fichier ajouté puis supprimé reste dans le dépôt.
- Hook non exécutable, ou appartenant à root : ignoré (ou erreur) selon les cas — un contrôle qui ne tourne pas.
- `echo` du message sans le préfixe `GL-HOOK-ERR:` : selon la version, l'utilisateur ne voit qu'un refus générique.
- Écrire le hook sur `git01` à la main sans le versionner : perdu à la prochaine reconstruction (E28 sauvegarde le dossier, mais la source de vérité est le dépôt).

**En production chez MédiSphère**
Hooks déployés par le rôle Ansible de la forge (M04) depuis `forge/hooks/`, tests rejoués en CI de `plateforme/medisphere` à chaque modification, dérogations revues mensuellement par la RSSI, temps d'exécution des hooks surveillé (journaux de Gitaly).

---

### M01-E27 — Signer commits et étiquettes, vérifier dans GitLab

**Solution**

Fichiers : [`gitconfig-signature.extrait`](fichiers/M01-E27/gitconfig-signature.extrait), [`allowed_signers.exemple`](fichiers/M01-E27/allowed_signers.exemple), [`politique-signature.md`](fichiers/M01-E27/politique-signature.md).

*1. Clé dédiée* (en place depuis M01-E03, on ne la recrée pas) :

```
admin@adm01:~$ git config --show-origin --get-regexp '^(user|gpg|commit|tag)\.'
file:/home/admin/.gitconfig	user.signingkey /home/admin/.ssh/id_ed25519_signature.pub
file:/home/admin/.gitconfig	gpg.format ssh
file:/home/admin/.gitconfig	gpg.ssh.allowedsignersfile /home/admin/.config/git/allowed_signers
file:/home/admin/.gitconfig	commit.gpgsign true
file:/home/admin/.gitconfig	tag.gpgsign true
admin@adm01:~$ ssh-add -l | grep -i signature        # la clé est-elle dans l'agent ?
```

(Sortie indicative : `user.name` et `user.email` apparaissent aussi.) Si une valeur manque, reprends la configuration de M01-E03 (chemin **absolu** pour `user.signingkey`).

Une clé dédiée se révoque sans couper l'accès SSH à la forge (et inversement), peut porter une phrase de passe chargée dans `ssh-agent` sans gêner les scripts qui utilisent la clé d'authentification, et rend le sens d'un badge non ambigu. Même clé pour les deux : plus simple, mais la compromission de la clé d'accès devient aussi une usurpation de signature.

*2.* *Preferences → SSH Keys → Add new key* : contenu de `id_ed25519_signature.pub`, *Usage type* : *Signing*, *Expiration date* : un an. *Preferences → Emails* : l'adresse de `user.email` doit y figurer comme vérifiée (en M01-E05, l'administrateur a confirmé les adresses ; sinon *Admin → Users → <MOI> → Confirm user*).

*3.* Après le commit (ajout de `docs/socle/securite/allowed_signers`) :

```
admin@adm01:~/medisphere$ git log --show-signature -1
Good "git" signature for <MOI>@medisphere.internal with ED25519 key SHA256:…
admin@adm01:~/medisphere$ curl -s -H "PRIVATE-TOKEN: $(<~/.config/workbook/gitlab-checks.token)" \
    "https://git01.par1.medisphere.internal/api/v4/projects/plateforme%2Fmedisphere/repository/commits/<SHA>/signature" | jq
{ "signature_type": "SSH", "verification_status": "verified", "key": { … }, "commit_source": "gitaly" }
```

*4.* `gpg.ssh.allowedSignersFile = ~/.config/git/allowed_signers`, copie **volontaire** de la liste de l'équipe. Pointer sur le fichier du clone : le contenu change avec la branche extraite ; une branche où quelqu'un a ajouté sa clé (ou une fausse clé au nom de Karim) ferait apparaître ses commits comme « Good signature » dans ton terminal. La liste de confiance ne doit changer que par une action délibérée, après relecture de la MR qui la modifie.

*5.* `%G?` : `G` bonne signature d'un signataire autorisé ; `U` bonne signature, validité inconnue (clé absente du fichier de signataires) ; `N` pas de signature ; `B` signature invalide ; `E` impossible de vérifier (programme absent, fichier de signataires non configuré) ; `X`/`Y`/`R` signature ou clé expirée, clé révoquée. Les commits de fusion créés par GitLab, les suggestions appliquées dans l'interface et les commits antérieurs à la politique sont `N`. Pour un auditeur : la signature prouve l'auteur des commits **humains** ; pour le reste, la preuve est la MR (auteur, relecteurs, pipeline, journal d'audit).

*6.*

```
admin@adm01:~/src/git-labo$ git tag -s essai-signature-e27 -m "Essai de signature SSH (SEC-254)"
admin@adm01:~/src/git-labo$ git push origin essai-signature-e27
admin@adm01:~/src/git-labo$ git tag -v essai-signature-e27
Good "git" signature for <MOI>@medisphere.internal with ED25519 key SHA256:…
```

*7. Révocation ou suppression* (constat attendu, conforme à la documentation) : clé **révoquée** → les commits qu'elle a signés passent « Unverified » (on ne sait plus qui les a signés) ; clé **supprimée** → les commits déjà vérifiés restent « Verified », les nouveaux ne le sont plus. En cas de compromission, on **révoque**.

*8. Politique* : [`politique-signature.md`](fichiers/M01-E27/politique-signature.md).

**Explications**

La signature SSH (Git 2.34+) réutilise `ssh-keygen -Y sign/verify` : pas de trousseau GPG, pas de serveur de clés. Git signe l'objet commit (ou étiquette) ; GitLab vérifie avec les clés publiques déclarées dans le compte **et** exige que l'adresse du commit appartienne au compte : sans cette seconde condition, n'importe qui pourrait signer un commit attribué à `karim.benali@…` avec sa propre clé.

**Alternatives**
- GPG : plus ancien, sous-clés et expiration fines, plus lourd à gérer.
- X.509 (S/MIME) avec la PKI de l'entreprise (step-ca au M06, certificats d'utilisateur) : révocation centralisée.
- Signature des commits faits dans l'interface par une clé de GitLab (configuration de Gitaly) : ferme le trou des commits de fusion. ⚠️ À vérifier sur ta version.

**Pièges classiques**
- `user.email` différent de l'adresse vérifiée : « Unverified » malgré une signature valide.
- Clé déclarée avec l'usage *Authentication* seul : non utilisée pour vérifier.
- `allowedSignersFile` absent : `git log --show-signature` affiche une erreur (« gpg.ssh.allowedSignersFile needs to be configured »), statut `E`.
- Clé de signature sans agent et avec phrase de passe : chaque commit demande la phrase, les rebases interactifs deviennent pénibles, on finit par désactiver la signature.
- Supprimer une clé compromise au lieu de la révoquer.

**En production chez MédiSphère**
Signature obligatoire contrôlée par hook serveur sur `plateforme/` (avec une liste de signataires synchronisée depuis les clés GitLab), clés de signature matérielles (FIDO2, `ed25519-sk`) pour les administrateurs, expiration annuelle, liste des signataires relue à chaque arrivée ou départ.

---

### M01-E28 — Sauvegarder et restaurer GitLab

**Solution**

Fichiers : script [`wb-backup-gitlab.sh`](fichiers/M01-E28/wb-backup-gitlab.sh), unités [`.service`](fichiers/M01-E28/wb-backup-gitlab.service) et [`.timer`](fichiers/M01-E28/wb-backup-gitlab.timer), [`pbs-git01.env.exemple`](fichiers/M01-E28/pbs-git01.env.exemple), [`gitlab.rb.extrait`](fichiers/M01-E28/gitlab.rb.extrait), extraits nftables pour [`gw01`](fichiers/M01-E28/gw01-nftables-extrait.nft) et [`pbs01`](fichiers/M01-E28/pbs01-nftables-extrait.nft), runbook [`RB-010-restaurer-gitlab.md`](fichiers/M01-E28/RB-010-restaurer-gitlab.md).

*1. Inventaire.*

| Dans l'archive `gitlab-backup` | Hors archive, indispensable |
|---|---|
| base PostgreSQL (projets, MR, tickets, utilisateurs, pipelines, variables CI **chiffrées**) | `/etc/gitlab/gitlab-secrets.json` (clés qui déchiffrent les variables CI, jetons de runner, secrets 2FA) |
| dépôts Git, wikis, extraits | `/etc/gitlab/gitlab.rb` (toute la configuration) |
| pièces jointes, artefacts et journaux de CI, LFS, paquets, Terraform states | certificat TLS (`/etc/gitlab/ssl/`), racine de confiance |
| | clés d'hôte SSH de `/etc/ssh` (sinon tous les clients refusent la forge reconstruite) |
| | hooks globaux de Gitaly (E26), fichier de dérogations |

La sauvegarde de VM (`lab-nuit`) restaure **toute la machine telle qu'elle était** : idéale pour revenir en arrière après un incident sur `git01` (mise à jour ratée, corruption) quand on accepte de perdre ce qui a été fait depuis. Elle ne permet pas de reconstruire GitLab sur une autre machine ou un autre système (migration Debian 14, PRA sur PAR2), de restaurer **une partie** (un projet supprimé), ni de garantir la cohérence de PostgreSQL (instantané de disque pris pendant les écritures, gelé par l'agent QEMU mais sans transaction terminée côté base : récupération au démarrage, généralement saine, jamais garantie). Les deux se complètent.

*2. Local* : `sudo du -sh /var/opt/gitlab/{git-data,postgresql,gitlab-rails/shared}` ; rétention `gitlab_rails['backup_keep_time'] = 259200` (3 jours) ; puis :

```
admin@git01:~$ sudo gitlab-backup create GZIP_RSYNCABLE=yes
… Backup 1759446000_2026_10_03_19.3.2 is done.
admin@git01:~$ sudo gitlab-ctl backup-etc --backup-path /var/opt/gitlab/config_backup
admin@git01:~$ sudo tar -tf /var/opt/gitlab/backups/*_gitlab_backup.tar | head
admin@git01:~$ sudo tar -xOf /var/opt/gitlab/backups/<ID>_gitlab_backup.tar backup_information.yml
```

(Format exact de l'identifiant à vérifier sur ta version : horodatage, date, version, et un suffixe d'édition selon les versions.) `GZIP_RSYNCABLE=yes` rend la compression « resynchronisable » : une petite modification ne change qu'une petite partie du fichier compressé, et la déduplication de PBS (blocs de taille variable) retrouve le reste.

*3. PBS* :

```
root@pbs01:~# proxmox-backup-client namespace create par1/git01 --repository root@pam@localhost:ds-lab
root@pbs01:~# proxmox-backup-manager user generate-token wb-backup@pbs git01 --comment "Sauvegarde applicative GitLab (PLAT-255)"
root@pbs01:~# proxmox-backup-manager acl update /datastore/ds-lab/par1/git01 DatastoreBackup --auth-id 'wb-backup@pbs!git01'
root@pbs01:~# proxmox-backup-manager user permissions 'wb-backup@pbs!git01' --path /datastore/ds-lab/par1/git01
root@pbs01:~# proxmox-backup-manager prune-job show prune-par1
```

L'utilisateur `wb-backup@pbs` a déjà `DatastoreBackup` sur `par1` (M00-E22) ; les droits d'un jeton sont l'intersection des siens et de ceux de l'utilisateur : le jeton `git01` ne voit que `par1/git01`, et ne peut ni lire ni purger les sauvegardes de `pve01`. Purge : une tâche de purge sans profondeur maximale (`max-depth` vide) descend dans les sous-espaces de noms ; sinon, crée une tâche dédiée. ⚠️ À vérifier sur ta version : `max-depth` de `prune-par1`.

*4. Réseau* (avec les précautions de M00-E21 : `nft -c -f`, session ouverte, retour arrière programmé) : règle de transfert sur `gw01` limitée à la source 10.10.20.12 et au port 8007, règle d'entrée sur `pbs01` limitée à la même source. `gw01` ne masque pas ce flux (le masquage vers `wg0` ne concerne que le LAN maison), donc `pbs01` voit la vraie source et répond par sa route `10.10.0.0/16` via `wg0` (source 10.20.10.10, M00-E21). Preuves :

```
admin@git01:~$ timeout 5 bash -c 'exec 3<>/dev/tcp/10.20.10.10/8007' && echo ouvert
ouvert
admin@runner01:~$ timeout 5 bash -c 'exec 3<>/dev/tcp/10.20.10.10/8007' || echo fermé
fermé
```

Matrice des flux : `git01 → pbs01 | TCP 8007 | via gw01 (wg0) | sauvegarde applicative GitLab | M01-E28`.

*5. Client et chiffrement* : dépôt `pbs-client` (suite `trixie`, trousseau Proxmox dont l'empreinte se compare à celle de la documentation), puis :

```
admin@git01:~$ sudo install -d -m 0700 /etc/wb-backup
admin@git01:~$ sudo install -m 0600 /dev/null /etc/wb-backup/pbs-git01.env && sudo nano /etc/wb-backup/pbs-git01.env
admin@git01:~$ sudo proxmox-backup-client key create /etc/wb-backup/pbs-git01.key --kdf none
admin@git01:~$ sudo chmod 600 /etc/wb-backup/pbs-git01.key
admin@git01:~$ sudo proxmox-backup-client key paperkey /etc/wb-backup/pbs-git01.key --output-format text
admin@git01:~$ sudo proxmox-backup-client key show /etc/wb-backup/pbs-git01.key
```

`--kdf none` : la clé doit être lisible par le timer sans intervention, exactement comme celle de `pbs-par2` en M00-E36 ; c'est pour cela qu'elle ne doit **jamais** se trouver sur PAR2, et qu'il en faut une copie hors ligne et une paperkey **avant** la première sauvegarde. Vérification après la première sauvegarde manuelle : `snapshot list … --output-format json`, champ `crypt-mode` = `encrypt` pour les archives `.pxar.didx`.

*6. Automatisation* : le [script](fichiers/M01-E28/wb-backup-gitlab.sh) enchaîne les deux sauvegardes, contrôle que les archives sont du jour, prépare un dossier d'envoi par **liens physiques** (pas de copie de plusieurs Go), y ajoute une archive `hors-gitlab.tar` (clés d'hôte SSH, hooks) et les empreintes, envoie `gitlab.pxar` vers `par1/git01`, nettoie. Timer à 01:15 (avant `lab-nuit` à 02:30 et la purge de PBS à 04:00 : un seul gros flux à la fois dans le tunnel), `Persistent=true` (rattrapage), `Nice`/`IOSchedulingClass=idle` (la forge reste utilisable). `journalctl -u wb-backup-gitlab.service` montre les quatre étapes et la durée.

*7. Restauration* : déroulé complet dans [RB-010](fichiers/M01-E28/RB-010-restaurer-gitlab.md). Ordre critique : **configuration et secrets avant l'installation du paquet** (le premier `reconfigure` lit `gitlab-secrets.json` ; s'il est absent, de nouveaux secrets sont générés et les données chiffrées restaurées deviennent illisibles), version **exacte**, `puma` et `sidekiq` arrêtés pendant `gitlab-backup restore`. Vérifications depuis `adm01` sans toucher au DNS : `curl --resolve git01.par1.medisphere.internal:443:<IP-2010> …` et `git ls-remote` vers l'adresse de 2010 avec `HostKeyAlias` (les clés d'hôte restaurées sont celles de `git01`). `gitlab:doctor:secrets` doit annoncer zéro échec de déchiffrement : c'est la preuve que `gitlab-secrets.json` a bien été restauré.

Feuille de temps typique (VM neuve sur NVMe, forge de quelques centaines de Mo) :

| Étape | Durée |
|---|---|
| Création de la VM 2010, démarrage | 3 min |
| Récupération depuis PBS sur `adm01`, empreintes, copie vers 2010 | 3 à 5 min |
| Configuration remise, dépôt et paquet GitLab installés (téléchargement ~1,5 Go) | 10 à 20 min |
| `gitlab-backup restore`, `reconfigure`, redémarrage | 5 à 10 min |
| Vérifications | 5 min |
| **RTO** | **30 à 45 min** (le téléchargement du paquet domine : un miroir local ou le paquet conservé le réduit) |

*8.* RB-010 et la section du test par MR, avec RTO et RPO mesurés (RPO ≤ 24 h : sauvegarde quotidienne).

**Explications**

Une sauvegarde applicative est **portable** (autre machine, autre système, même version de GitLab) et **cohérente** (la base est exportée par `pg_dump`, les dépôts par des *bundles* Git). PBS apporte le stockage hors site, la déduplication, le chiffrement côté client et la rétention gérée côté serveur. Le test de restauration est ce qui transforme « on a des sauvegardes » en « on sait reconstruire la forge en 45 minutes ».

**Alternatives**
- Copie des sauvegardes vers le stockage S3 du socle (M05) par la configuration native de GitLab (`backup_upload_connection`) : simple, mais pas de chiffrement client ni de déduplication.
- Instantanés de VM plus fréquents (plusieurs par jour) : RPO plus court pour un retour arrière sur place, sans la portabilité.
- Geo (réplication vers une instance secondaire) : RPO de quelques secondes, **Premium**.
- `gitlab-backup-cli` (nouvel outil de sauvegarde annoncé par GitLab) : ⚠️ à suivre, encore expérimental au moment de la rédaction.

**Pièges classiques**
- Ne sauvegarder que `/var/opt/gitlab/backups` : sans `gitlab-secrets.json`, la restauration « marche » mais variables CI, jetons de runner et 2FA sont perdus.
- Garder la seule copie des secrets à côté des données sur PAR2 **non chiffrée**.
- Restaurer sur une version différente d'un correctif.
- Restaurer la VM de test sur `vinfra` avec l'adresse de `git01`, ou la déclarer dans le DNS : les runners et les utilisateurs se répartissent entre deux forges.
- Ouvrir 8007 à tout le VLAN INFRA « pour aller plus vite ».
- Oublier la place disque : `STRATEGY=copy` ou plusieurs jours de rétention locale doublent ou triplent l'espace nécessaire.

**En production chez MédiSphère**
Sauvegarde applicative quotidienne + instantanés de VM, copies vers un second site (synchronisation PBS, M09), test de restauration semestriel sur une VM jetable chronométré et consigné (preuve d'audit HDS), alerte si la dernière sauvegarde a plus de 26 h (sonde E30, puis M21).

---

### M01-E29 — Mettre à jour GitLab en suivant le chemin de montée de version

**Solution**

Runbook complet : [`RB-011-mettre-a-jour-gitlab.md`](fichiers/M01-E29/RB-011-mettre-a-jour-gitlab.md).

*1. Préparation.* 19.3.x → 19.4.z : aucun arrêt obligatoire entre les deux (le prochain est 19.5) ; on vise le **dernier** correctif 19.4. Notes de mise à jour : lire celles de chaque version **traversée** (19.4.0 à 19.4.z), en particulier les changements de configuration ; pour notre `gitlab.rb`, vérifier qu'aucune ancienne clé NGINX `nginx[…]` (déplacées sous `gitlab_rails['nginx'][…]` depuis 19.2, encore traduites avec un avertissement) ne traîne : M01-E04 utilise déjà la nouvelle forme ; les avertissements de dépréciation de `reconfigure` le confirment. Migrations d'arrière-plan : `sudo gitlab-rake gitlab:background_migrations:list` (18.9 et suivantes ; `:status` avant) ou la requête documentée dans `gitlab-psql` : zéro ligne non terminée, sinon **on attend**.

*2. Retour arrière* :

| Moment | Action | Perte |
|---|---|---|
| Échec pendant les migrations, forge encore fermée | `qm rollback 1004 avant-maj-19-4` | rien (aucune écriture utilisateur) |
| Régression vue une heure après réouverture | correctif (patch suivant) ou contournement ; rollback seulement si la forge est inutilisable, avec annonce de la perte | pushes, MR, pipelines de l'heure écoulée |
| Une semaine après | jamais de rollback de VM : correctif ; en dernier recours réinstallation de 19.3 + restauration E28 | une semaine : inacceptable |

Point de non-retour : la réouverture aux utilisateurs (les premières écritures). Le paquet ne se rétrograde pas : le schéma de la base a migré.

*3-4. Exécution et contrôles* : voir le runbook. La sortie du paquet montre, dans l'ordre : sauvegarde de la base (`Dumping PostgreSQL database…`), arrêt de certains services, dépaquetage, `gitlab-ctl reconfigure` (migrations de schéma), redémarrage des services, puis les migrations d'arrière-plan se poursuivent après coup (Sidekiq). Le contrôle des hooks (E26) est indispensable : `reconfigure` régénère `config.toml` de Gitaly à partir de `gitlab.rb`, ce qui est sans risque si la configuration y est, et fatal si quelqu'un l'avait ajoutée à la main dans le fichier généré.

*5. Runner* : règle retenue : `gitlab-runner` au même `major.minor` que GitLab ; un runner plus récent d'une mineure est toléré quelques jours (cas de E23), un runner plus ancien que GitLab de plus d'une mineure non. Après la mise à jour : 19.4 / 19.4, aligné.

*6. Clôture* : `qm delsnapshot 1004 avant-maj-19-4`. Un instantané conservé consomme de l'espace qui grossit à chaque écriture (LVM-thin ou ZFS), dégrade un peu les performances, et perd toute valeur dès que des données utiles ont été écrites après lui (le restaurer = les perdre).

*7. Cadence* (exemple) : correctifs de sécurité critiques sous 72 h, autres correctifs sous 7 jours ; une mineure par mois ou au plus par trimestre, sans jamais dépasser un arrêt obligatoire sans s'y arrêter ; majeure (mai) après lecture des ruptures et essai sur la VM de restauration ; runner dans la même fenêtre.

**Explications**

Les arrêts obligatoires existent parce que certaines migrations de données ne peuvent s'exécuter que dans une version donnée, et qu'une version ultérieure **suppose** qu'elles sont terminées. Sauter un arrêt, ou ne pas attendre la fin des migrations d'arrière-plan, donne des erreurs de migration au mieux, des données incohérentes au pire. Le reste de la procédure est générique : sauvegarde vérifiée, point de retour, contrôles écrits à l'avance, critère de décision.

**Alternatives**
- Mise à jour sans interruption (*zero-downtime*) : architectures multi-nœuds seulement.
- Tester d'abord sur une copie (VM de restauration de E28) : fortement conseillé pour les majeures.

**Pièges classiques**
- `apt upgrade` avec le paquet non figé : passage d'une mineure à l'autre non planifié, voire saut d'un arrêt obligatoire.
- Viser `19.4.0` au lieu du dernier correctif.
- Lancer la mise à jour pendant que des migrations d'arrière-plan tournent encore.
- Instantané **avec** la RAM : long, volumineux, inutile ici.
- Oublier de réactiver le runner (pipelines bloqués en *pending* le lendemain).

**En production chez MédiSphère**
Fenêtre de maintenance annoncée, mise à jour d'abord sur la forge de préproduction, contrôles automatisés (checks E23-E31 rejoués), changement tracé dans un ticket CHG avec la sortie des contrôles, veille des annonces de sécurité de GitLab (flux RSS des *security releases*).

---

### M01-E30 — Superviser GitLab : sondes de santé, services, journaux, métriques

**Solution**

Fichiers : [`sonde-forge.sh`](fichiers/M01-E30/sonde-forge.sh), [`gitlab.rb.extrait`](fichiers/M01-E30/gitlab.rb.extrait), [`RB-012-diagnostiquer-la-forge.md`](fichiers/M01-E30/RB-012-diagnostiquer-la-forge.md).

*1. Carte* : tableau des composants et de leurs journaux dans RB-012. Premier regard : 502 → `nginx/gitlab_error.log` puis `puma/current` et `gitlab-workhorse/current` (l'application est-elle démarrée ?) ; push SSH refusé → la sortie du client (`remote:`), `gitlab-shell/gitlab-shell.log`, `gitaly/current` (hooks) ; job qui ne démarre pas → la page du job (*stuck*, étiquettes), puis `journalctl -u gitlab-runner` sur `runner01`.

*2-4. Mémoire et métriques* : exemple de mesure (ordres de grandeur, à remplacer par les tiens) :

| Composant | RSS | Décision |
|---|---|---|
| Puma (mode simple) | 900 Mo à 1,2 Go | en place |
| Sidekiq | 600 à 800 Mo | en place |
| PostgreSQL | 200 à 400 Mo | en place |
| Gitaly | 150 à 300 Mo | en place |
| Redis, Workhorse, NGINX | ~100 Mo au total | en place |
| Serveur Prometheus + Alertmanager | 250 à 400 Mo | **non** (M21) |
| gitlab-exporter | 100 à 150 Mo | non (pour l'instant) |
| Exporters Redis et PostgreSQL | 20 à 40 Mo chacun | non (pour l'instant) |
| node_exporter | 15 à 25 Mo | **oui**, sur 10.10.20.12:9100 |

Sondes : depuis `git01` (127.0.0.1, autorisée par défaut) `curl -s --resolve git01.par1.medisphere.internal:443:127.0.0.1 https://git01.par1.medisphere.internal/-/readiness?all=1` → `{"status":"ok","master_check":[{"status":"ok"}],"db_check":[…],…}` ; depuis `adm01` avant l'autorisation : refus (HTTP 404 dans les versions récentes ; à vérifier sur ta version). Liste autorisée : `['127.0.0.0/8', '::1/128', '10.10.10.10/32']`. Ces sondes ne sont pas publiques parce qu'elles décrivent l'architecture interne (dépendances, état) et que `/-/metrics` expose des volumes d'activité : de l'information pour un attaquant, et un point d'appel coûteux.

Métriques système : l'option retenue dans le corrigé est l'exporter **du paquet GitLab** ([extrait](fichiers/M01-E30/gitlab.rb.extrait) : interrupteur général activé, chaque composant coûteux désactivé, `node_exporter` écoutant sur l'adresse INFRA). Alternative équivalente et plus indépendante des mises à jour de GitLab : le paquet Debian `prometheus-node-exporter` (même port, à restreindre à l'adresse INFRA). ⚠️ À vérifier sur ta version : l'effet exact de `prometheus_monitoring['enable']` sur chaque composant ; `gitlab-ctl status` après `reconfigure` fait foi.

*5. Sonde* : [`sonde-forge.sh`](fichiers/M01-E30/sonde-forge.sh) ; exemple :

```
admin@adm01:~$ ~/lab-scripts/sonde-forge.sh ; echo code=$?
OK    readiness : toutes les dépendances répondent
OK    liveness : Rails répond
OK    certificat : valide encore 371 j
OK    runner runner01-shell : contact il y a 2 s
OK    disque /var/opt/gitlab : 21 %
OK    mémoire git01 : 1630 Mo disponibles
OK    services GitLab : tous démarrés
OK    sauvegarde applicative : dernière il y a 9 h
code=0
```

Runner : GitLab le dit *online* tant qu'il l'a contacté dans les **deux dernières heures** ; un runner arrêté reste « online » longtemps. Le champ `contacted_at` (détail d'un runner, API d'administration) donne l'âge du dernier contact : au-delà de 5 minutes, alerte.

*6. Rougir* : `gitlab-runner` arrêté → après 5 min `CRIT runner runner01-shell : dernier contact il y a 312 s`, alors que l'interface affiche encore *Online*. Gitaly arrêté → `readiness` HTTP 503 avec `gitaly_check` en échec (`CRIT readiness : dépendance(s) en échec : gitaly_check`), `liveness` toujours 200 (Rails vit), `services GitLab : 1 service(s) arrêté(s)`. Leçon : `liveness` dit « faut-il redémarrer le processus ? », `readiness` dit « peut-il servir ? ».

**Explications**

Une sonde utile est **orientée service** (ce que vivent les utilisateurs : répondre, cloner, exécuter des jobs, être sauvegardé), produit un code exploitable par une machine, et ne crie pas pour rien. Le format Nagios (0/1/2/3) est compris par presque tous les outils ; au module 21, les mêmes contrôles deviennent des règles d'alerte Prometheus, à partir des métriques exposées ici.

**Alternatives**
- Serveur Prometheus embarqué de GitLab : complet et pré-configuré (tableaux de bord), mais 300 Mo de plus sur une VM de 8 Go et une supervision qui tombe avec la forge.
- Sonde synthétique de bout en bout (clone + push + pipeline sur un projet témoin) : la plus fidèle, plus lourde ; bonne candidate pour le M21 (blackbox exporter).

**Pièges classiques**
- Ouvrir la liste autorisée à `0.0.0.0/0` « pour que ça marche ».
- Se fier au statut *online* des runners.
- Une sonde qui affiche le jeton (en cas d'erreur de `curl` en mode verbeux, par exemple).
- Réactiver `prometheus_monitoring` sans désactiver les composants un par un : +300 Mo, et un `git01` qui swappe.

**En production chez MédiSphère**
Les contrôles de la sonde deviennent des alertes Prometheus/Alertmanager (M21) avec astreinte (Nadia), les journaux partent vers Loki (M22), un tableau de bord « forge » suit l'occupation, la durée des pipelines et l'âge des sauvegardes.

---

### M01-E31 — Durcir GitLab

**Solution** (exemple ; d'autres choix argumentés sont valables tant que les contraintes sont tenues)

Fichiers : script [`durcir-gitlab.sh`](fichiers/M01-E31/durcir-gitlab.sh) (à versionner sous `forge/durcissement/`), [`gitlab.rb.extrait`](fichiers/M01-E31/gitlab.rb.extrait), rapport [`durcissement-gitlab.md`](fichiers/M01-E31/durcissement-gitlab.md) (à ranger dans `docs/socle/securite/`).

Démarche recommandée :
1. **Modèle de menace d'abord** (rapport, §1) : sept menaces concrètes ; chaque mesure s'y rattache, et une mesure qui ne traite aucune menace identifiée n'entre pas.
2. **Préparer les effets de bord avant d'activer Admin Mode** : crée un nouveau jeton des checks `workbook-checks` (`read_api` + `admin_mode`) et un nouveau jeton d'administration `workbook-admin` (`api` + `admin_mode`), mêmes noms et mêmes durées qu'en M01-E05, remplace les fichiers `~/.config/workbook/gitlab-checks.token` et `gitlab-admin.token`, révoque les anciens ; enrôle le second facteur de `<MOI>` et de `root` (codes de secours de `root` sous enveloppe, coffre de l'équipe) **avant** de l'imposer.
3. **Appliquer** : `forge/durcissement/durcir-gitlab.sh` (réglages applicatifs par `PUT /application/settings`, puis vérification par `GET`), `gitlab.rb` pour le serveur web, redémarrage de Puma pour la durée de session.
4. **Vérifier** : `durcir-gitlab.sh --verifier` (code 0), `lab/bin/check 01 31`, puis `lab/bin/check 01 23` (API d'administration encore accessible avec le nouveau jeton) et un script de ressource du palier 2 (jetons d'emprunt d'identité toujours créables).
5. **Rapport** relu par MR (Sophie Laurent en relectrice).

Points de discussion attendus :
- **2FA et personnages** : les jetons d'emprunt d'identité et les jetons personnels ne passent pas par la 2FA ; les comptes des personnages, qui ne se connectent jamais à l'interface, ne sont pas gênés.
- **Désactivation des comptes dormants** : écartée, elle désactiverait les personnages (inactifs au sens de la connexion) et casserait les ressources et les pannes du workbook.
- **Vérification de version** : désactivée par souveraineté (l'interface interroge un service de l'éditeur) ; compensation : abonnement aux annonces de sécurité, rythme de E29. Choix inverse défendable s'il est écrit.
- **Git HTTPS sans mot de passe** : les outils (runner, scripts) utilisent déjà des jetons ; pour les humains, SSH.
- **Clés NGINX** : depuis 19.2, `gitlab_rails['nginx'][…]` (forme déjà utilisée en M01-E04 pour le certificat) ; les anciennes `nginx[…]` sont dépréciées mais encore traduites : ne pas écrire les deux formes pour la même clé.
- **Limites de CE** : pas d'approbations obligatoires, de politique de mot de passe avancée, de journal d'audit complet, de durée maximale de jeton réglable : compensations (pipeline obligatoire, hooks, 2FA, inventaire des jetons par l'API `personal_access_tokens`).

**Explications**

Les réglages de sécurité d'une forge sont surtout **en base** (réglages d'application), pas dans `gitlab.rb` : une restauration les ramène, une réinstallation non. Un script idempotent qui applique **et vérifie** en fait du code relu, versionné, rejouable après une reconstruction, et transforme l'audit en une commande.

**Alternatives**
- Provider OpenTofu GitLab (`gitlab_application_settings`) : même idée, avec plan et état (M05).
- Rôle Ansible de la forge (M04) qui porte `gitlab.rb` et appelle l'API.

**Pièges classiques**
- Activer Admin Mode avant d'avoir recréé les jetons : checks et scripts en 403, et plus de jeton pour réparer par l'API (il reste l'interface).
- Imposer la 2FA sans l'avoir enrôlée pour `root` : bris de glace inutilisable au pire moment.
- Désactiver l'authentification par mot de passe **web** (`password_authentication_enabled_for_web`) sans SSO : plus personne ne se connecte (M24).
- Interdire les clés RSA alors qu'un collègue n'a que cela.
- Recopier une liste de durcissement sans lire ce que fait chaque option.

**En production chez MédiSphère**
SSO avec MFA (M24), revue trimestrielle des comptes, jetons et clés, journaux d'authentification envoyés au SIEM (M22), script de durcissement rejoué en CI de `plateforme/medisphere` en mode vérification (dérive détectée chaque nuit).

---

### M01-E32 — Revue de la configuration CI et pre-commit d'un projet

**Lecture des événements demandés**

| Événement | Ce qui arrive avec la proposition |
|---|---|
| Push d'une branche sans MR | Pipeline de branche : gabarits de `ci-templates` **à leur état de `main`** ; `debug` affiche tout l'environnement, **dont `GITLAB_TOKEN` en clair** ; `secrets` peut échouer sans conséquence ; `tests` absent (seulement en MR) ; `release` lancé (`when: always`), qui installe semantic-release à la volée et tente de publier depuis une branche |
| Ouverture de la MR | Pipeline de MR : `tests` sans étiquette reste *pending* indéfiniment : le pipeline ne finit jamais, la MR ne peut pas être fusionnée (pipeline obligatoire) |
| MR d'un collègue depuis une autre branche | Même chose, et le jeton du bot est lisible par lui (dans le fichier et dans `debug`) |
| Fusion | Sur `main` : pas de tests ; `release` avec `@semantic-release/git` tente de pousser un commit de CHANGELOG sur `main` protégée : refus, job en échec — ou succès partiel selon l'ordre des étapes |
| Clone + `pre-commit install` | Seul le hook `pre-commit` est installé : commitlint n'est jamais lancé sur les messages ; à chaque commit, la suite de tests complète tourne ; `gitleaks-docker` échoue faute de Docker sur `adm01` |
| Nouvelle version de semantic-release | Installée automatiquement au prochain pipeline (`npm install -g` sans version) : rupture possible, ou paquet compromis exécuté avec le jeton du bot |
| Job `debug` | Affiche toutes les variables : celles **masquées** apparaissent `[MASKED]`, mais `GITLAB_TOKEN` défini dans le YAML n'est pas masqué |

**Revue**

| N° | Fichier : ligne(s) | Défaut | Catégorie | Gravité | Impact concret | Correction |
|---|---|---|---|---|---|---|
| 1 | `.gitlab-ci.yml` : `GITLAB_TOKEN` | Jeton du bot en clair dans le dépôt | Sécurité | **Critique** | Toute personne qui lit le dépôt (et son historique, pour toujours) peut publier, pousser des étiquettes, appeler l'API en Maintainer | Variable CI protégée et masquée ; **révoquer immédiatement** le jeton (il est déjà dans l'historique de la branche) |
| 2 | `.gitlab-ci.yml` : `debug` | `env` dans un job | Sécurité | **Élevée** | Affiche les variables non masquées (dont le jeton du n° 1) et l'environnement du runner dans un journal lisible par tous les membres | Supprimer ; déboguer avec des variables précises, jamais `env` |
| 3 | `.gitlab-ci.yml` : `release` | `when: always`, aucune règle | Fonctionnement / sécurité | **Élevée** | Tourne sur toutes les branches et MR, **même si les étapes précédentes ont échoué** : une version peut être publiée depuis une branche non relue, sans tests | `release.yml` de `ci-templates` (branche par défaut protégée seulement) |
| 4 | `.gitlab-ci.yml` : `release` | `npm install -g` sans versions, à chaque job | Reproductibilité / sécurité | **Élevée** | Outils différents d'un pipeline à l'autre ; code tiers téléchargé et exécuté avec le jeton du bot ; `-g` échoue (droits) ou écrit dans le dossier personnel partagé du runner | Outils figés de `/opt/release-tools` (E24) |
| 5 | `.gitlab-ci.yml` : `tests` | Pas d'étiquette | Fonctionnement | **Élevée** | Le runner refuse les jobs sans étiquette : job *pending* éternel, MR jamais fusionnable | `tags: [shell]` |
| 6 | `.gitlab-ci.yml` : `secrets` | `allow_failure: true` | Sécurité | **Élevée** | Un secret détecté ne bloque rien : le contrôle est décoratif | Supprimer ; le job `gitleaks` du gabarit bloque |
| 7 | `.gitlab-ci.yml` : `secrets` | `gitleaks dir .` | Sécurité | Moyenne | Ne voit que l'état final : un secret ajouté puis retiré dans la MR passe ; doublon du job `gitleaks` du gabarit | Supprimer (le gabarit contrôle la plage de commits) |
| 8 | `.gitlab-ci.yml` : `include` | `ref: main` | Reproductibilité | Moyenne | Toute fusion dans `ci-templates`, même cassée ou incompatible, s'applique immédiatement | `ref: v1` |
| 9 | `.gitlab-ci.yml` : `tests` | `only: merge_requests` | Fonctionnement | Moyenne | `main` n'est jamais testée après fusion (or c'est elle qu'on publie) ; syntaxe `only` obsolète, mélangée à un `workflow` en `rules` | Pas de restriction : le `workflow` du gabarit décide des pipelines |
| 10 | `.gitlab-ci.yml` : `tests` | `pip install -r requirements.txt` | Reproductibilité / cohérence | Moyenne | Installation hors environnement, versions non figées, pollution du dossier personnel partagé du runner ; contraire à la règle du workbook (`uv`, jamais `pip` global) | `uv sync --locked` puis `uv run pytest` |
| 11 | `.gitlab-ci.yml` : `variables` | `GIT_DEPTH: 1` global | Fonctionnement | Moyenne | Casse les jobs propres au projet qui ont besoin d'historique (release : « no previous release », version fausse) | Supprimer (chaque job du gabarit fixe ce dont il a besoin) |
| 12 | `.pre-commit-config.yaml` | Pas de `default_install_hook_types` | Fonctionnement | Moyenne | `pre-commit install` n'installe que le type `pre-commit` : commitlint ne tourne jamais | `default_install_hook_types: [pre-commit, commit-msg]` |
| 13 | `.pre-commit-config.yaml` : commitlint | `stages: [commit]` | Fonctionnement | Moyenne | Nom de stage obsolète (`pre-commit` 4), et mauvais stage : commitlint a besoin du message, donc de `commit-msg` | `stages: [commit-msg]` |
| 14 | `.pre-commit-config.yaml` : `rev: main` | Référence mobile | Reproductibilité / sécurité | Moyenne | pre-commit la résout une fois et ne la met plus à jour (avertissement « mutable reference ») : chaque poste a une version différente ; et on exécute le code de la branche du jour | Étiquette (`v6.0.0`), mise à jour par `pre-commit autoupdate` en MR |
| 15 | `.pre-commit-config.yaml` : gitleaks | `v8.16.0` et `gitleaks-docker` | Fonctionnement | Moyenne | Docker absent sur `adm01` (M12) : hook en échec, donc contourné ; version ancienne (règles de détection périmées) | `gitleaks` 8.30.x, hook `gitleaks` |
| 16 | `.pre-commit-config.yaml` : `--maxkb=50000` | Seuil de 50 Mo | Cohérence | Faible | Incohérent avec le hook serveur (5 Mio, E26) : le développeur découvre le refus au push au lieu du commit | `--maxkb=5120` |
| 17 | `.pre-commit-config.yaml` : `pytest` | Tests complets à chaque commit | Fonctionnement | Faible | Plusieurs secondes à minutes par commit : l'équipe finit par utiliser `--no-verify`, qui contourne aussi les autres hooks | Tests en CI (job `tests`) |
| 18 | `.releaserc.json` | `@semantic-release/changelog` + `@semantic-release/git` | Cohérence / fonctionnement | **Élevée** | Commit du bot dans `main` protégée (refusé, release en échec) ; extensions absentes de `/opt/release-tools` ; contraire à la décision de E25 | Supprimer ; notes dans les Releases GitLab |
| 19 | `.releaserc.json` | Préréglage par défaut (`angular`) | Fonctionnement | Moyenne | `feat!:` n'est pas reconnu comme rupture : version mineure au lieu de majeure, consommateurs cassés | `preset: conventionalcommits` dans les deux extensions |
| 20 | `.releaserc.json` | `branches: ["main", "develop"]` | Fonctionnement | Faible | `develop` n'existe pas dans notre modèle de branches (M01-E09) ; si elle existait, elle publierait une préversion sans canal configuré | `["main"]` |

Remarques mineures, non comptées : `fail_fast: true` (masque les autres erreurs du même commit), `detect-private-key` et `check-merge-conflict` absents par rapport à la référence de M01-E15, `stages` redéfinis sans `build` (sans effet aujourd'hui, mais incohérent avec le gabarit), `tagFormat` implicite (préférer l'écrire).

**Action immédiate** : le n° 1. Le jeton a été poussé dans une branche : il est compromis, quel que soit le sort de la MR. Révoquer `bot-release` (ou le jeton de Lucas, si c'était le sien), en créer un nouveau en variable protégée et masquée, vérifier dans le journal d'audit du projet qu'il n'a pas été utilisé, puis seulement faire la revue (M01-E17).

**Ordre de traitement** : ce qui expose (1, 2, 3, 4), puis ce qui bloque ou fausse le service (5, 18, 6, 7, 12, 13, 19, 9), puis la reproductibilité et la cohérence (8, 10, 11, 14, 15, 16, 17, 20).

**Version corrigée** : [`.gitlab-ci.yml`](fichiers/M01-E32/.gitlab-ci.yml) (gabarits `v1` + job `tests` étiqueté, `uv sync --locked`), [`.pre-commit-config.yaml`](fichiers/M01-E32/.pre-commit-config.yaml) (exemple autonome ; dans le projet réel, reprendre la référence de M01-E15), [`.releaserc.json`](fichiers/M01-E32/.releaserc.json) (= référence de E25). Validation : `pre-commit validate-config` (aucun avertissement) et éditeur de pipeline de GitLab.

**Conseils à Lucas**
- « Ça marche sur ma branche » ne teste qu'un événement : déroule les autres (MR, fusion, collègue, nouveau poste, nouvelle version d'outil) et vérifie ce qui **ne doit pas** se produire.
- Lis le journal complet d'un job et pose-toi la question « qui peut lire ça ? » avant d'y afficher quoi que ce soit.
- Réutilise les gabarits : tout ce que tu réécris est un endroit de plus où se tromper et à maintenir.

**Explications**

Une CI est du code qui s'exécute avec des secrets, sur une machine partagée, à chaque push de n'importe qui : elle se relit avec la même exigence qu'un script d'administration. Les défauts les plus graves ne se voient pas en testant « ce qui doit marcher » (le job `release` publie très bien… depuis n'importe où).

**Pièges classiques** (côté relecteur)
- Se concentrer sur la syntaxe et rater la question « qui peut déclencher ce job, avec quels secrets ? ».
- Corriger le fichier sans traiter le secret déjà poussé.

**En production chez MédiSphère**
Les projets ne contiennent presque plus de CI propre (gabarits) ; un contrôle automatique refuse `when: always` sur un job qui utilise une variable protégée, `env` dans un script, et les `include` non figés (M19, conftest au M29).

---

### M01-E33 — ADR : monodépôt ou multidépôts pour la plateforme

**Solution**

ADR exemplaire : [`fichiers/M01-E33/ADR-0010-organisation-des-depots.md`](fichiers/M01-E33/ADR-0010-organisation-des-depots.md). Grille d'auto-évaluation : [`fichiers/M01-E33/grille-evaluation.md`](fichiers/M01-E33/grille-evaluation.md). Note ton ADR **avant** de lire l'exemple.

**Explications**

Ce qui fait pencher vers les multidépôts **dans notre contexte** : les fonctions qui rendent un monodépôt gouvernable (propriétaires de code **obligatoires**, approbations obligatoires, *merge trains*) sont Premium ; semantic-release publie une suite de versions par dépôt ; un runner unique paie chaque job inutile ; le cloisonnement d'`infra` est une exigence de sécurité. Ce qui ferait pencher vers le monodépôt : beaucoup de changements transverses, une équipe qui grossit avec de l'outillage dédié, une forge Premium. L'important est que les conséquences négatives (coordination, divergence des conventions) aient chacune une action compensatoire : ici `ci-templates`, le modèle de projet, les dépendances par version publiée, Renovate (M13).

**Alternatives**
- Monodépôt avec `rules: changes` et étiquettes préfixées par composant (`outils-v1.2.0`) : faisable, demande une discipline et un outillage de versions par dossier.
- Hybride code / déploiement : bonne séparation du risque, découpage interne discutable.

**Pièges classiques**
- Trancher sur une préférence personnelle (« Google fait du monorepo »).
- Oublier la question des droits, qui est souvent la contrainte dure dans un contexte réglementé.
- Ne pas écrire de condition de révision : la décision devient un dogme.

**En production chez MédiSphère**
L'ADR est référencé par le modèle de projet et par le mini-projet ; chaque nouveau projet `plateforme/*` est créé par script (M02) avec gabarits, protections et `.releaserc.json`, ce qui réduit le coût principal des multidépôts.

---

### M01-E34 — Questions de production : Git et GitLab à l'échelle

1. **Attaques depuis un job de MR** (exécuteur `shell`) : (a) **vol ou empoisonnement** des données des autres projets : lire les dossiers de build voisins, modifier `~/.cache/pre-commit` pour qu'un hook d'un autre projet exécute du code — limité aujourd'hui par l'absence de secrets dans les pipelines de MR (variables protégées) ; supprimé par des exécuteurs éphémères (un conteneur ou une VM par job, M12/M19) ; (b) **persistance** : laisser un processus en arrière-plan qui survit au job et observe les jobs suivants (dont ceux de `main`, qui ont `GITLAB_TOKEN`) — limité par rien d'autre que la surveillance ; supprimé par les exécuteurs éphémères, ou réduit par un runner `ref_protected` séparé pour les jobs de `main` ; (c) **rebond réseau** : depuis INFRA, sonder `git01`, les futurs services du socle — limité par le pare-feu de `gw01` (INFRA ne joint ni MGMT ni `pve01`) ; supprimé par un VLAN dédié aux runners avec sorties filtrées.
2. **c)** : une variable protégée n'est fournie qu'aux pipelines des branches et étiquettes protégées ; dans une MR depuis une branche non protégée, `GITLAB_TOKEN` est vide (a et b supposent qu'elle est fournie ; d n'existe pas). C'est pour cela que le masquage seul ne suffit pas : encodée (`base64`), une variable masquée sortirait en clair. Pousser directement sur `main` : impossible (push : personne). C'est la combinaison « variable protégée + branche protégée + fusion par MR relue » qui protège le secret.
3. | | Sauvegarde de VM | `gitlab-backup` | Geo |
   |---|---|---|---|
   | RPO | 24 h (nuit) | 24 h (01:15) | secondes à minutes |
   | RTO | 10-20 min (restauration de VM) | 30-60 min (réinstallation + restauration) | minutes (bascule) |
   | Protège | panne ou erreur sur `git01`, mise à jour ratée | perte de la VM, migration, PRA, restauration partielle | perte du site |
   | Ne protège pas | migration, cohérence base garantie | ce qui s'est passé depuis la nuit | suppression logique (répliquée) |
   | CE | oui | oui | non (Premium) |
4. Non, pas parfaitement : la base est exportée par `pg_dump` (cohérente en elle-même), puis les dépôts un par un ; un push pendant la sauvegarde peut se retrouver dans un dépôt sans que la base le connaisse encore (ou l'inverse). GitLab le tolère à la restauration (les références sont relues), mais l'archive ne représente pas un instant unique. `STRATEGY=copy` copie les fichiers (artefacts, pièces jointes) avant de les archiver, ce qui évite l'erreur « file changed as we read it » de `tar` ; il ne rend pas l'ensemble cohérent avec la base. Pour un instant unique : fenêtre sans écriture, ou instantané du système de fichiers.
5. **b)** : 19.2 et 19.5 sont des arrêts obligatoires ; on s'y arrête, on attend la fin des migrations d'arrière-plan, puis on continue. a) saute deux arrêts ; c) est inutilement long (les mineures intermédiaires ne sont pas obligatoires) ; d) saute 19.2.
6. En premier : la **mémoire** de `git01` (Puma en mode simple : une seule file de requêtes ; Sidekiq à 10 fils ; plus de swap) et le **runner unique** (files d'attente de jobs). Ensuite Gitaly (CPU et disque sur les gros clones), PostgreSQL. Étapes : augmenter la VM et passer Puma en mode multi-processus ; plusieurs runners, puis autoscalés (M19, Kubernetes) ; séparer PostgreSQL (externe, M27) et Redis ; stockage objet pour artefacts, LFS, paquets (S3 du socle) ; Gitaly sur un nœud dédié ; architectures de référence de GitLab (au-delà de ~1 000 utilisateurs). Tout cela est possible en CE, sauf Geo et les fonctions de haute disponibilité avancées de Gitaly (Gitaly Cluster est disponible mais complexe : à évaluer).
7. Client : `git clone --filter=blob:none` (clone partiel, blobs à la demande), `--depth` (historique tronqué : rapide, mais limite `log`, `blame`, `bisect`), `git sparse-checkout` (ne matérialiser qu'une partie de l'arbre). Serveur : `git maintenance`/GC (ne retire pas ce qui est encore référencé), LFS pour les **futurs** binaires, réécriture d'historique (`git filter-repo`) pour retirer les anciens. Coût humain de la réécriture : tous les clones et toutes les branches en cours deviennent incompatibles (rebase ou reclonage de chacun, MR ouvertes à refaire), les SHA cités dans les tickets et la documentation ne pointent plus nulle part, les étiquettes signées ne sont plus valides : à faire une fois, annoncé, avec une fenêtre de gel.
8. Parce qu'un commit intermédiaire **est** dans le dépôt pour toujours dès la fusion (méthode semi-linéaire : chaque commit arrive dans `main`) : un secret ajouté puis retiré reste lisible par `git log -p`, et un message non conforme reste dans l'historique qui alimente les versions. Pour qu'un secret poussé sur une branche jamais fusionnée ne reste pas sur la forge : refuser **au push** (Gitleaks dans un hook serveur), car même supprimée, la branche laisse les objets (et les références de MR) jusqu'au nettoyage ; et de toute façon, rotation.
9. **d)** : le hook serveur voit **chaque push**, avant stockage, mais pas le contexte (MR, relecture) et se maintient sur l'hôte ; le pipeline voit la MR complète avec des outils riches, mais **après** le push (les objets sont déjà sur la forge) et seulement là où la CI est incluse. a) est faux (on peut), b) et c) seuls laissent chacun un trou.
10. Avec `api` et Maintainer sur **ce** projet : créer des étiquettes et des Releases (publier une fausse version, pointant éventuellement sur un commit piégé poussé sur une branche), lire et modifier les variables CI du projet (dont… ce jeton), modifier les réglages du projet (protections !), ajouter des membres, lire tout le code. Pas d'accès aux autres projets ni à l'administration. Dans l'heure : révoquer le jeton ; vérifier et rétablir les protections de branches et d'étiquettes ; lister les étiquettes, Releases, membres, variables, jetons créés depuis la fuite (journal d'audit du projet, événements) et supprimer ce qui est illégitime ; créer un nouveau jeton et mettre à jour la variable ; prévenir la RSSI et les consommateurs si une version suspecte a été publiée ; post-mortem (comment il a fuité).
11. Parce que `main` est protégée sans push direct (M01-E11) : un commit du bot exigerait une exception de protection (affaiblissement), relancerait un pipeline (boucle), et polluerait l'historique. Si un `CHANGELOG.md` est exigé : (a) `@semantic-release/changelog` + `@semantic-release/git` avec une exception de push pour le bot (coût : protection affaiblie, commit par version) ; (b) une MR de release créée par un bot (release-please) et fusionnée normalement (coût : une étape humaine par version) ; (c) générer le CHANGELOG en artefact ou dans la Release seulement (coût : nul, mais il n'est pas dans le dépôt).
12. `ref: v1.4.2` (étiquette protégée, immuable en pratique) ou, mieux encore pour la chaîne d'approvisionnement, le SHA du commit ; la mise à jour devient une MR explicite. Renovate (M13) ouvre ces MR automatiquement à chaque nouvelle version, avec les notes.
13. **c)** : la base et les dépôts reviennent, mais tout ce qui est chiffré avec les clés de `gitlab-secrets.json` (variables CI, jetons de runner, secrets 2FA, certaines intégrations) est illisible ; `gitlab:doctor:secrets` le montre. a) est faux (les clés ne sont pas dans la base, justement) ; b) faux ; d) faux (la restauration ne vérifie pas).
14. 4 h : pas de MR ni de pipeline ; les déploiements en GitOps (M20) se figent sur le dernier état connu (la production continue de tourner, mais on ne peut ni livrer un correctif ni revenir en arrière par la chaîne normale) ; le registre (M13) ne sert plus d'images : un redémarrage de pod qui doit tirer une image échoue. 3 jours : incident majeur, correctifs de sécurité impossibles à livrer, procédures dégradées (déploiement manuel documenté). Conséquences : la forge est une **brique critique** de la production, avec un niveau de service, une restauration testée (E28), une place dans le PRA (F5 : la reconstruire en premier, avant les applications), et un mode dégradé écrit.
15. « Verified » prouve que le commit a été signé par une clé déclarée dans le compte de l'auteur et que l'adresse du commit appartient à ce compte. Il ne prouve pas que le **contenu** est bon, ni que la personne était consciente de ce qu'elle signait (poste compromis), ni l'absence de modification **après** la fusion (qui relève des protections). Avec une session web volée, l'attaquant peut ajouter **sa** clé de signature au compte (si la 2FA n'est pas redemandée pour cette action) et produire des commits « Verified » : d'où la 2FA, les sessions courtes, la notification d'ajout de clé, et la revue des clés.
16. Lenteurs invisibles à la sonde : saturation CPU de `git01` (charge, `node_load1`), swap (`node_memory_SwapFree_bytes`, `vmstat`), latence disque (`node_disk_io_time_seconds_total`), file Sidekiq qui s'allonge (métriques Sidekiq, *Admin → Monitoring → Background jobs*), requêtes lentes de PostgreSQL (`pg_stat_statements`, exporter PostgreSQL), file de jobs CI en attente (durée *pending*, métriques du runner), réseau (pertes sur le tunnel ou le pont). La sonde dit « ça répond » ; les métriques disent « à quelle vitesse et pourquoi ».

---

### M01-E35 — Workflow complet en temps limité

**Solution** — déroulé de référence (45 à 55 minutes)

| Jalon | Ce qu'on fait | Temps typique |
|---|---|---|
| T0 → T1 | Lire le ticket, la MR, la revue de Karim, l'historique (`git log --oneline --graph --all`), le pipeline de MR (rouge : `commitlint` sur « WIP sms », « fix typo », « retire le jeton du dépôt » ; `gitleaks` : `gitlab-pat` dans `config/medisms.env`). Diagnostic complet : messages non conformes, `fixup!` à intégrer, jeton dans un commit intermédiaire, `main` a avancé (conflit attendu sur `heure_rappel`), revue (URL surchargeable), MR en brouillon, pas de `GITLAB_TOKEN` dans le projet (la release ne pourra pas sortir) | 8 à 12 min |
| (en parallèle) | Traiter le jeton comme réel : le noter pour rotation (action après le chrono), **ne pas** le recopier ailleurs | — |
| T1 → T2 | Récupérer la branche, rebase interactif **sur `main` à jour** : fusionner « WIP sms », « fix typo », le `fixup!` et « retire le jeton » dans un seul commit `feat(sms): envoie les rappels par SMS` dont **aucune** version ne contient `config/medisms.env` ; résoudre le conflit en gardant **les deux** changements (`TZ=Europe/Paris` de Karim et le format ISO de Julien) ; ajouter `MEDISMS_URL="${MEDISMS_URL:-https://api.medisms.example/v1/sms}"` ; lancer les tests en local ; `git push --force-with-lease` | 15 à 20 min |
| T2 → T3 | Pipeline de MR vert ; répondre à la discussion de Karim (ce qui a été fait pour les deux points) et la résoudre ; retirer le statut brouillon ; fusionner | 5 à 8 min |
| (avant ou pendant T3) | Créer le jeton de projet `bot-release` (Maintainer, `api` + `write_repository`, expiration) et la variable `GITLAB_TOKEN` protégée et masquée | 3 à 5 min |
| T3 → T4 | Pipeline de `main` : job `release` → `v1.1.0` (le `fix:` de Karim et le `feat(sms):` depuis `v1.0.0`) ; vérifier la Release et ses notes | 3 à 5 min |

Commandes clés de l'étape T1 → T2 :

```
admin@adm01:~/src/chrono$ git fetch origin
admin@adm01:~/src/chrono$ git switch -c feature/rappel-sms origin/feature/rappel-sms
admin@adm01:~/src/chrono$ git rebase -i origin/main
#   pick   WIP sms                                   → (premier : le garder, renommer ensuite)
#   fixup  fix typo
#   pick   feat(sms): envoie les rappels par SMS     → réordonner pour tout regrouper
#   fixup  retire le jeton du dépôt
#   fixup  fixup! feat(sms): …
# (conflit sur rappel.sh : garder TZ=Europe/Paris ET le format '+%Y-%m-%dT%H:%M')
admin@adm01:~/src/chrono$ git log -p origin/main..HEAD | grep -c 'glpat-' # doit afficher 0
admin@adm01:~/src/chrono$ bash tests/test_rappel.sh
admin@adm01:~/src/chrono$ git push --force-with-lease origin feature/rappel-sms
```

Le plus sûr pour le jeton : commencer par `git rebase -i` avec le premier commit en `edit`, retirer `config/medisms.env` et la ligne `source` dès ce commit, puis laisser les suivants s'appliquer. Contrôle final indispensable : **aucun** commit de la nouvelle branche ne contient le jeton (`git log -p`), pas seulement la pointe.

**Explications**

L'épreuve combine tout le palier 2 sous contrainte de temps : lecture de pipeline, rebase interactif, résolution de conflit, secret dans l'historique, revue, règles de fusion, et la chaîne de release de E25 (dont le jeton de bot, absent volontairement : une release qui « ne sort pas » est un incident classique). Ce qui distingue une bonne performance : le diagnostic **complet** avant de toucher à quoi que ce soit (un seul rebase au lieu de trois), la vérification du résultat (tests, `git log -p`, pipeline), et le traitement du jeton au-delà de sa disparition de l'historique.

**Ce qui reste à faire après le chrono (jeton)** : même factice, le traiter comme réel : il a été poussé sur la forge (objets et référence de la MR) ; rotation auprès du fournisseur, vérification d'usage, purge des références si nécessaire (M01-E17), et une ligne au CONTRIBUTING si le retour d'expérience montre un manque.

**Pièges classiques**
- Fusionner `main` dans la branche au lieu de rebaser : un commit « Merge branch 'main' » arrive dans l'historique de `main` (la méthode semi-linéaire l'accepte, la règle de l'équipe non), et surtout le jeton reste dans l'historique.
- Résoudre le conflit en prenant « la version de Julien » : le correctif de Karim disparaît (le check le voit).
- Supprimer le jeton par un nouveau commit : il reste dans l'historique, `gitleaks` reste rouge.
- `git push --force` au lieu de `--force-with-lease`.
- Créer l'étiquette `v1.1.0` à la main : la Release n'a pas de notes, et la prochaine version sera calculée depuis une étiquette posée hors chaîne.
- Oublier que le brouillon (*Draft:*) bloque la fusion.

**En production chez MédiSphère**
Ce scénario (branche d'un collègue absent, secret, conflit, release bloquée) est un classique des reprises de travail ; il justifie le CONTRIBUTING (une MR = des commits propres), les hooks et la CI (le jeton n'aurait pas dû passer le poste de Julien), et un runbook de rotation des jetons de bot.

**Grille d'auto-évaluation** (en plus des critères du check)

| Critère | Oui / Non |
|---|---|
| Diagnostic complet écrit à T1, avant toute modification | |
| Un seul rebase pour tout régler | |
| Résultat vérifié localement (tests, `git log -p`) avant de pousser | |
| Réponse écrite à Karim avant de résoudre sa discussion | |
| Jeton traité comme réel dans le retour d'expérience (rotation, communication) | |
| RTO ≤ 60 min ; retour d'expérience avec au moins une amélioration concrète | |
