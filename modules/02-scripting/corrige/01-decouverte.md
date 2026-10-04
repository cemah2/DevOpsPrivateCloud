# Module 02 — Palier 1 : Découverte — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Ce corrigé suit l'ordre de l'énoncé. Les questionnaires (E01, E09) sont argumentés et les QCM expliquent pourquoi les autres options sont fausses. Pour les labs, les fichiers complets sont dans [`fichiers/`](fichiers/) ; ils ont été testés (ShellCheck 0.11, shfmt 3.14.1, jq 1.7.1, yq 4.54.1, uv 0.12.23, Python 3.13, proxmoxer 2.3.0) contre des réponses d'API enregistrées et un serveur HTTPS de test, pas contre un vrai GitLab ni un vrai Proxmox.

Points non testés en conditions réelles, à vérifier sur ta version et à signaler s'ils diffèrent :
- lecture des jetons de projet (`GET /projects/:id/access_tokens`) et des variables CI (`GET /projects/:id/variables`) avec un jeton `read_api` (E02 ; la vérification passe ces contrôles en « ignoré » si l'API refuse) ;
- présence ou absence de l'extension *Key Usage* dans l'autorité générée par ton `pve01` (E08 : dépend de la version de `pve-cluster` qui l'a créée ; un correctif était en revue chez Proxmox début 2026) ;
- empreintes exactes des fichiers de release (introduction) : vérifie-les toujours, ne les recopie jamais d'un document.

---

### M02-E01 — Test de positionnement : Bash et Python

**Barème** : 2 points par question. 2 = complet et justifié ; 1 = idée juste mais incomplète ; 0 = faux ou blanc. Total sur 50.

**Réponses argumentées — Bash**

**1. `"$@"`, `$*`, `"$*"`.** `printf '[%s]\n' "$@"` → `[un deux]` `[trois]` : chaque argument reste un mot. `$*` non protégé → `[un]` `[deux]` `[trois]` : les arguments sont recollés puis redécoupés (et soumis au développement des noms de fichiers). `"$*"` → `[un deux trois]` : un seul mot, arguments joints par le premier caractère d'`IFS`. Pour transmettre ses arguments : toujours `"$@"`, seule forme qui préserve exactement la liste reçue.

**2. Réponses C et D.** C : le statut d'une affectation `var=$(cmd)` est celui de la substitution ; `false` échoue, `set -e` arrête. D : avec `pipefail`, le tube prend le statut du dernier élément en échec ; il échoue, le script s'arrête. A est faux : `false` est l'opérande gauche d'un `||`, son échec est « géré ». B est faux : une commande testée par `if` ne déclenche jamais `set -e`. E est faux, et c'est le piège majeur : dans une fonction appelée comme condition (`if f`), `set -e` est **ignoré dans tout le corps de la fonction** ; `false` passe, `echo suite` s'exécute, `f` renvoie 0. (À noter aussi : `local x=$(false)` ne déclenche rien, voir question 10.)

**3. `rm $f`.** Le shell développe `$f`, découpe sur les blancs (`rapport`, `du`, `3`, `octobre`, `*.txt`), puis développe les noms de fichiers : `*.txt` devient **tous** les fichiers `.txt` du dossier courant. `rm` reçoit donc quatre noms inexistants et tous les `.txt` : il supprime tout ce qui se termine par `.txt`, mais pas le fichier visé. Correct : `rm -- "$f"` (guillemets contre le découpage et les jokers, `--` contre un nom commençant par `-`).

**4. `[ ]` contre `[[ ]]`.** `[[ ]]` est une syntaxe du shell, `[` une commande. Conséquences : (1) pas de découpage ni de jokers sur les variables dans `[[ ]]` (`[[ -n $x ]]` marche avec `x` vide ou contenant des espaces ; `[ -n $x ]` est vrai pour `x` vide !) ; (2) `==` et `!=` comparent à un **motif** (`[[ $f == *.log ]]`) ; (3) `=~` pour les expressions rationnelles étendues, avec `BASH_REMATCH` ; (4) `&&` et `||` à l'intérieur, et `<`/`>` sans échappement. `[ ]` reste nécessaire en `sh` POSIX.

**5. Expansions.** `${chemin##*/}` = `journal.log.gz` ; `${chemin%/*}` = `/var/log/app` ; `${chemin%.*}` = `/var/log/app/journal.log` ; `${chemin%%.*}` = `/var/log/app/journal` (le plus long suffixe commençant par un point, donc depuis le **premier** point) ; `${#chemin}` = 27. `${VAR:-defaut}` donne `defaut` si `VAR` est vide ou non définie, sans l'affecter ; `${VAR:=defaut}` l'affecte en plus ; `${VAR:?message}` écrit `message` sur la sortie d'erreur et, dans un script, le termine avec un code non nul.

**6. Ordre des redirections.** Elles s'appliquent de gauche à droite. `cmd >sortie.log 2>&1` : la sortie standard va dans le fichier, puis la sortie d'erreur est **copiée** sur ce que désigne la sortie standard à cet instant, le fichier : tout va dans le fichier. `cmd 2>&1 >sortie.log` : la sortie d'erreur est copiée sur la sortie standard **actuelle** (le terminal), puis seule la sortie standard est redirigée : les erreurs restent à l'écran.

**7. `while` après un tube.** Chaque élément d'un tube s'exécute dans un sous-shell : `total` est modifié dans le sous-shell de la boucle, puis perdu. Corrections : `while … done < <(df -P | tail -n +2)` (substitution de processus : la boucle tourne dans le shell courant) ; `shopt -s lastpipe` (le dernier élément du tube s'exécute dans le shell courant, en script non interactif) ; ou faire le calcul entièrement dans `awk`.

**8. `trap … EXIT`.** Le code s'exécute quand le shell se termine : fin du script, `exit`, arrêt par `set -e`, et aussi sur les signaux fatals reçus (SIGTERM, SIGHUP, SIGINT) : Bash exécute le piège EXIT avant de mourir. Jamais sur SIGKILL (non interceptable). Si le script attend une commande au premier plan, Bash ne traite le signal qu'**au retour** de cette commande : un `kill -TERM` sur le seul script peut donc attendre la fin d'un `ssh` de plusieurs minutes. Ctrl-C est envoyé à tout le groupe de processus (le script **et** la commande en cours), d'où une réaction immédiate. Bonne pratique : `trap 'exit 130' INT` et `trap 'exit 143' TERM` pour un code explicite, le nettoyage restant dans le piège EXIT.

**9. Codes de sortie.** 1 : erreur générale ; 2 : mauvais usage (commandes internes de Bash, et convention « usage » des outils) ; 126 : trouvé mais non exécutable ; 127 : commande introuvable ; 130 = 128+2 (SIGINT) ; 137 = 128+9 (SIGKILL, souvent l'OOM killer ou un `kill -9`) ; 143 = 128+15 (SIGTERM). `$?` après un tube donne le statut du dernier élément (ou du dernier en échec avec `pipefail`) ; le tableau `PIPESTATUS` donne celui de chaque élément, à lire **immédiatement** après le tube.

**10. Réponse B.** `local` est lui-même une commande, dont le statut (0) remplace celui de la substitution : l'échec de `curl` est masqué, `set -e` ne voit rien. Écrire `local reponse` puis `reponse=$(curl …)`. A est faux : on est bien dans une fonction. C est faux : dans une affectation, la substitution n'est pas découpée (les guillemets restent recommandés, mais ce n'est pas l'objet de SC2155). D n'a aucun sens.

**11. Tableau d'arguments.** `args=(-o ConnectTimeout=5)` ; `[[ -n "$cle" ]] && args+=(-i "$cle")` ; `[[ ! -t 0 ]] && args+=(-o BatchMode=yes)` ; puis `ssh "${args[@]}" "$hote" …`. Chaque élément reste un mot, quels que soient les espaces. Une chaîne `opts="-i $cle"` non protégée se découpe mal (chemin avec espaces), et protégée devient un seul argument faux.

**12. `find | xargs rm`.** `xargs` découpe sur les blancs et interprète les guillemets et barres obliques inverses : noms avec espaces, retours à la ligne, apostrophes, ou commençant par `-` posent problème (et une liste vide lance `rm` sans argument). Formes correctes : `find /srv/exports -name '*.csv' -mtime +30 -delete` ; `find … -exec rm -- {} +` ; `find … -print0 | xargs -0 -r rm --`.

**13. Substitution de processus.** `<(cmd)` exécute `cmd` et présente sa sortie comme un nom de fichier (`/dev/fd/63`). Exemple : `diff <(ssh gw01 sudo nft list ruleset) <(ssh gw02 sudo nft list ruleset)` ; ou `while read …; done < <(cmd)` (question 7), ou `curl -H @<(printf 'Authorization: …')` pour qu'un secret n'apparaisse pas dans `ps`.

**14. cron et systemd.** `PATH` réduit (pas de `~/.local/bin`, parfois pas de `/usr/local/bin` sous cron) ; pas de terminal ni d'agent SSH (`SSH_AUTH_SOCK` absent : clé protégée inutilisable) ; dossier courant `/` ; variables de `.bashrc`/`.profile` absentes ; locale minimale ; sous systemd, `HOME` et l'utilisateur dépendent de `User=` ; `umask` différent. Ce sera la panne E35.

**15. Fragment.** Pas de guillemets (`$DIR`, `$f`) ; `cd $DIR` non contrôlé ; `rm -rf $DIR/tmp/*` sans garde-fou ; boucle sur `ls` (noms avec espaces), anciens accents graves ; pas de mode strict, pas d'usage. Avec `$1` vide : `cd` sans argument va dans `$HOME`, puis `rm -rf /tmp/*` (car `$DIR` est vide) **vide tout ce que l'utilisateur peut supprimer dans `/tmp`**, et la boucle compresse les `.log` de `$HOME`. Correction : `[[ -n ${1:-} && -d $1 ]] || exit 2`, `cd -- "$1" || exit 1`, `rm -rf -- "${DIR:?}/tmp/"*`, `for f in ./*.log; do [[ -e $f ]] || continue; gzip -- "$f"; done`.

**Réponses argumentées — Python**

**16. PEP 668.** Debian marque son Python comme « géré par le système » (fichier `EXTERNALLY-MANAGED`) : `pip` installé globalement écraserait des paquets gérés par `apt` et casserait des outils du système. Pour un **outil** : `uv tool install` (environnement isolé par outil, commande dans le `PATH`), `pipx`, ou le paquet Debian `python3-…` s'il existe. Pour un **projet** : un environnement virtuel propre au projet, géré par uv (`uv add`, `uv sync`). `--break-system-packages` existe ; son nom dit tout.

**17. Trois fichiers.** `pyproject.toml` déclare le projet et ses dépendances **directes** sous forme de contraintes (`requests>=2.32`). `uv.lock` fige la résolution **complète** (dépendances transitives comprises) : versions exactes, sources, empreintes, pour toutes les plateformes. `.venv/` est le résultat installé, jetable, reconstruit depuis le verrou. On versionne `pyproject.toml` et `uv.lock`, jamais `.venv/`.

**18. Réponse C.** `requests` n'impose **aucun** délai par défaut (`timeout=None`) : un serveur qui accepte la connexion sans répondre bloque l'appel indéfiniment, et l'astreinte avec. A, B et D décrivent des comportements qui n'existent pas sans configuration explicite (délais, adaptateur `Retry`). D'où la règle bandit S113 de ruff (« requête sans délai »).

**19. Exceptions.** `except:` attrape aussi `KeyboardInterrupt` et `SystemExit` (on ne peut plus interrompre le programme proprement) ; `except Exception:` attrape presque tout, y compris les bogues de programmation (`KeyError`, `TypeError`) qu'on ferait mieux de voir ; une exception précise (`requests.exceptions.ConnectionError`) ne traite que le cas prévu. `raise ConfigError("…") from exc` remplace une erreur technique par un message métier clair tout en conservant la cause (`__cause__`) pour le diagnostic.

**20. `__name__`.** Vaut `"__main__"` quand le fichier est exécuté directement, le nom du module quand il est importé : le bloc ne s'exécute que dans le premier cas (le module reste importable par les tests). Une commande installée vient de `[project.scripts]` (`medictl = "medictl.cli:app"`) : à l'installation, un petit script est généré dans le `bin/` de l'environnement ; il importe `medictl.cli` et appelle `app()`.

**21. Argument par défaut mutable.** Affiche `[2021]` puis `[2021, 2022]`. La valeur par défaut est évaluée **une fois**, à la définition de la fonction : la même liste est réutilisée d'un appel à l'autre. Correction : `liste: list | None = None` puis `if liste is None: liste = []`. ruff le signale (B006).

**22. `shell=True`.** Un `hote` valant `x; rm -rf ~` est exécuté par le shell : injection de commande. Correct : `subprocess.run(["ssh", "-o", "BatchMode=yes", "--", hote, "uptime"], check=True, capture_output=True, text=True, timeout=30)` : liste d'arguments sans shell, exception `CalledProcessError` si le code n'est pas 0, sortie dans `.stdout`, délai maximal.

**23. Clé absente.** `vm["tags"]` lève `KeyError` ; `vm.get("tags")` renvoie `None` ; `vm.get("tags", "")` renvoie une chaîne vide. Pour un champ **facultatif** par nature (étiquettes, pool), `get` avec une valeur par défaut du bon type. Pour un champ **obligatoire** (`vmid`, `status`), il faut échouer : `[]` ou une validation explicite, avec un message clair. Masquer une absence anormale par une valeur par défaut produit des résultats faux en silence.

**24. `logging`.** Niveaux (DEBUG à CRITICAL) réglables à l'exécution (`-v`), horodatage et nom du module, destination configurable, et par défaut la **sortie d'erreur** : la sortie standard reste réservée aux données (exploitables par `jq`, un tube, un autre outil). On n'y écrit jamais de secret : jeton, en-tête `Authorization`, mot de passe, URL contenant un identifiant.

**25. Code retour.** `sys.exit(n)` ; une exception non rattrapée affiche la trace et sort en **1** ; `sys.exit("message")` écrit le message sur la sortie d'erreur et sort en **1**. Un Ctrl-C non rattrapé (`KeyboardInterrupt`) fait sortir le processus par le signal SIGINT (code 130 vu du shell, depuis Python 3.8). Un outil propre rattrape ses erreurs prévues et choisit son code (convention de l'équipe : 1, 2 ou 3).

**Grille d'auto-évaluation**

| Score /50 | Lecture | Conseil |
|---|---|---|
| 42 à 50 | Solide | Lis surtout les « Pièges classiques » des corrigés. |
| 30 à 41 | Bon niveau, lacunes ciblées | Retravaille les thèmes faibles (tableau ci-dessous) avant les exercices indiqués. |
| 20 à 29 | Bases à consolider | Fais le palier 1 lentement, en lisant les pages de wiki de ShellCheck et le tutoriel Python officiel sur les exceptions. |
| Moins de 20 | Écart important | Prends une à deux semaines sur *BashGuide* (wiki de Greg) et le tutoriel Python officiel, puis refais le test. |

| Thème | Questions | Où il est mobilisé |
|---|---|---|
| Expansions, guillemets, tableaux | 1, 3, 5, 11, 12, 15 | E03, E04, E12 |
| Erreurs, `set -e`, codes retour, signaux | 2, 8, 9, 10 | E03, E30, E39, E44 |
| Processus, redirections, environnement | 6, 7, 13, 14 | E13, E26, E35 |
| Environnements et paquets Python | 16, 17, 20 | E07, E25, E42 |
| Python robuste (erreurs, HTTP, sous-processus, journaux) | 18, 19, 21, 22, 23, 24, 25 | E08, E15 à E19 |

Ressources : *BashGuide* et *BashPitfalls* (<https://mywiki.wooledge.org/BashGuide>), manuel de Bash (sections *Shell Expansions*, *The Set Builtin*), tutoriel officiel de Python (chapitres 8 et 10), documentation de `subprocess` et `logging`.

---

### M02-E02 — Créer le projet `plateforme/outils`

**Solution**

1. **Création** (interface) : *New project → Create blank project*, groupe `plateforme`, nom `outils`, visibilité *Private*, case *Initialize repository with a README* cochée. `main` existe avec un commit, sans poussée de ta part.

2. **Configuration standard.** Deux voies, au choix :
   - réutiliser le script du module 01, [`../../01-git/corrige/fichiers/M01-E11/gitlab-proteger-projet.sh`](../../01-git/corrige/fichiers/M01-E11/gitlab-proteger-projet.sh) `plateforme/outils --pipeline-obligatoire`, puis créer le jeton et la variable comme en M01-E25 ;
   - ou le script complet de ce corrigé, [`fichiers/M02-E02/configurer-projet.sh`](fichiers/M02-E02/configurer-projet.sh), qui crée le projet s'il n'existe pas et applique **toute** la configuration par l'API, de façon rejouable :
     ```
     admin@adm01:~$ MERGE_METHOD=rebase_merge ~/DevOpsPrivateCloud/modules/02-scripting/corrige/fichiers/M02-E02/configurer-projet.sh plateforme/outils
     [09:12:03] projet plateforme/outils : existe déjà
     [09:12:03] règles de fusion : rebase_merge, pipeline réussi et discussions résolues obligatoires
     [09:12:04] main : remplacement de la protection existante ({"push":[40],"merge":[40],"force":false})
     [09:12:04] main : protégée (push : personne ; fusion : Maintainers)
     [09:12:04] étiquettes v* : protégées (création : Maintainers)
     [09:12:05] jeton bot-release : création (Maintainer, api + write_repository, expire le 2027-10-03)
     [09:12:05] variable CI GITLAB_TOKEN : enregistrée (protégée, masquée)
     [09:12:05] projet plateforme/outils configuré : https://git01.par1.medisphere.internal/plateforme/outils
     ```

   | Réglage | Interface | API |
   |---|---|---|
   | Méthode de fusion, squash, suppression de la branche source | Settings → Merge requests | `PUT /projects/:id` (`merge_method`, `squash_option`, `remove_source_branch_after_merge`) |
   | Pipeline réussi, discussions résolues | Settings → Merge requests → *Merge checks* | `only_allow_merge_if_pipeline_succeeds`, `only_allow_merge_if_all_discussions_are_resolved` |
   | Protection de `main` | Settings → Repository → *Protected branches* | `POST /projects/:id/protected_branches` (CE : supprimer puis recréer pour changer les niveaux) |
   | Étiquettes `v*` | Settings → Repository → *Protected tags* | `POST /projects/:id/protected_tags` |
   | Jeton `bot-release` | Settings → Access tokens | `POST /projects/:id/access_tokens` |
   | `GITLAB_TOKEN` | Settings → CI/CD → Variables | `POST /projects/:id/variables` |

   Au niveau du groupe, GitLab CE permet notamment la protection par défaut de la branche initiale des nouveaux projets (*Settings → Repository → Default branch*) et des variables CI de groupe. Les règles de fusion et le jeton de projet restent par projet (un jeton de projet n'appartient qu'à un projet). D'où l'intérêt d'un script rejouable.

3. **Contenu, sur une branche** :
   ```
   admin@adm01:~$ git clone git@git01.par1.medisphere.internal:plateforme/outils.git ~/src/outils
   admin@adm01:~$ cd ~/src/outils && git switch -c chore/configuration-initiale
   admin@adm01:~/src/outils$ cp ~/medisphere/{.pre-commit-config.yaml,commitlint.config.mjs,.releaserc.json,CONTRIBUTING.md} .
   admin@adm01:~/src/outils$ mkdir -p .gitlab/merge_request_templates
   admin@adm01:~/src/outils$ cp ~/medisphere/.gitlab/merge_request_templates/Default.md .gitlab/merge_request_templates/
   ```

   | Fichier | Décision | Référence |
   |---|---|---|
   | `.pre-commit-config.yaml` | copié, puis **complété** par le projet (E04, E07) | [`M01-E15`](../../01-git/corrige/fichiers/M01-E15/.pre-commit-config.yaml) |
   | `commitlint.config.mjs` | copié à l'identique | [`M01-E14`](../../01-git/corrige/fichiers/M01-E14/commitlint.config.mjs), ou [`fichiers/M02-E02/outils/commitlint.config.mjs`](fichiers/M02-E02/outils/commitlint.config.mjs) |
   | `.releaserc.json` | copié à l'identique | `M01-E25`, ou [`fichiers/M02-E02/outils/.releaserc.json`](fichiers/M02-E02/outils/.releaserc.json) (version minimale équivalente) |
   | `CONTRIBUTING.md`, modèle de MR | copiés, la section « projet » **adaptée** (scripts, `medictl`, codes retour) | [`M01-E22`](../../01-git/corrige/fichiers/M01-E22/CONTRIBUTING.md) |
   | `.gitlab-ci.yml` | **écrit** : trois lignes d'inclusion | [`fichiers/M02-E02/outils/.gitlab-ci.yml`](fichiers/M02-E02/outils/.gitlab-ci.yml) |
   | `.gitignore` | **écrit** pour Python et contre les secrets | [`fichiers/M02-E02/outils/.gitignore`](fichiers/M02-E02/outils/.gitignore) |
   | `README.md` | **écrit** (remplace celui de l'initialisation) | [`fichiers/M02-E02/outils/README.md`](fichiers/M02-E02/outils/README.md) |

   `.gitlab-ci.yml` n'a presque rien à contenir parce que tout le contrôle qualité et la release vivent dans `plateforme/ci-templates` (branche `v1`) ; `qualite.yml` définit même les étapes standard. Le projet n'écrira que ses jobs propres (E24).

4. **Hooks, commit, MR** :
   ```
   admin@adm01:~/src/outils$ pre-commit install
   pre-commit installed at .git/hooks/pre-commit
   pre-commit installed at .git/hooks/commit-msg
   admin@adm01:~/src/outils$ pre-commit run --all-files
   admin@adm01:~/src/outils$ git add -A && git commit -m "chore: configuration standard de la plateforme"
   admin@adm01:~/src/outils$ git push
   ```
   Ouvre la MR depuis le lien affiché par `git push`, avec le modèle `Default`. Pipeline de MR : `pre-commit`, `commitlint`, `gitleaks` (étape `lint`). Fusion une fois vert.

5. **Pipeline de `main`** : le job `release` lance semantic-release, qui analyse les commits depuis la dernière étiquette ; `chore:` ne déclenche aucune version (seuls `fix:` → correctif, `feat:` → mineure, `!`/`BREAKING CHANGE` → majeure). Il se termine en succès avec « There are no relevant changes, so no new version is released ». La première version viendra avec le premier `feat:` (E03).

6. **Divergence dans six mois** (question 8) : un fichier copié diverge forcément. Pistes, de la plus simple à la plus solide : (a) un job de CI dans chaque projet qui compare sa configuration à la référence (`curl` du fichier brut de `plateforme/medisphere`, ou mieux d'un projet `plateforme/standards`) et échoue ou avertit en cas d'écart ; (b) des hooks pre-commit **maison** dans un dépôt commun (`repo: https://git01…/plateforme/hooks`), référencés par étiquette ; (c) un outil de mise à jour automatique (Renovate, module 13) qui ouvre des MR quand la référence change ; (d) les modèles de projet de groupe, réservés à l'édition Premium. Le choix fera partie de la réflexion monodépôt/multidépôts (ADR-0010, M01-E33).

**Explications**

- **Initialiser avec un README** évite la seule poussée directe sur `main` de la vie du projet : la protection peut être posée tout de suite, et toute la configuration passe par une MR, comme le demande Karim.
- **Protection par défaut de GitLab** : à la création, la branche par défaut est protégée avec les réglages de l'instance (souvent « Maintainers » pour le push). Elle doit être **remplacée** par celle de l'équipe (push : personne) ; en CE, l'API ne permet pas de modifier les niveaux d'une protection existante, d'où « supprimer puis recréer ».
- **Variable protégée** : `GITLAB_TOKEN` n'est exposée qu'aux pipelines des branches et étiquettes protégées. Le pipeline d'une MR (branche non protégée) ne la voit pas : c'est voulu, une MR malveillante ne peut pas exfiltrer le jeton de release.
- **Masquée** : remplacée par `[MASKED]` dans les journaux de job ; ce n'est pas un chiffrement, juste un filet contre l'affichage accidentel.

**Alternatives**

- Tout par l'API dès le départ (script de ce corrigé) : reproductible, documentable, réutilisable pour `plateforme/images`, `ansible`, `infra` (modules 03 à 05). À terme, cette configuration sera décrite en code (provider GitLab d'OpenTofu, module 05).
- Un monodépôt `plateforme` unique éviterait la copie de configuration, au prix d'autres contraintes (droits, CI, versions) : voir ADR-0010.

**Pièges classiques**

- Créer le projet vide, pousser `main` à la main, puis oublier de protéger : la « première fois » devient la règle.
- Garder la protection par défaut de l'instance (Maintainers peuvent pousser) : la règle « tout passe par une MR » n'est pas appliquée.
- Variable `GITLAB_TOKEN` non protégée « pour que ça marche dans la MR » : le jeton est alors lisible par n'importe quelle branche.
- Jeton `bot-release` avec le rôle Developer : semantic-release ne peut pas pousser l'étiquette `v*` protégée.
- Copier `.pre-commit-config.yaml` sans lancer `pre-commit install` : les hooks ne tournent pas en local, seule la CI rattrape.
- Oublier `uv.lock` ou `.venv/` dans `.gitignore`… dans le mauvais sens : `.venv/` s'ignore, `uv.lock` se versionne.

**En production chez MédiSphère**

- Un script (ou un module OpenTofu) unique applique la configuration standard à tous les projets `plateforme/*`, et une tâche planifiée signale les écarts.
- Rotation annuelle du jeton `bot-release` (son expiration est obligatoire) avec alerte un mois avant ; un jeton expiré arrête toutes les releases du projet.
- Revue obligatoire par un pair, même sans les approbations obligatoires de Premium : règle d'équipe dans CONTRIBUTING, vérifiée en revue mensuelle des MR fusionnées.

---

### M02-E03 — Un script Bash robuste : mode strict, `trap`, codes retour, usage

**Solution**

Script complet : [`fichiers/M02-E03/bin/ms-collecte-config`](fichiers/M02-E03/bin/ms-collecte-config) (déjà formaté selon le style de l'équipe défini en E04). Ses choix :

1. **Arguments** : boucle `while`/`case` plutôt que `getopts`, pour accepter `--help`, `--dossier=…` et `--`. `getopts` (interne, portable) ne gère que les options courtes ; `getopt` de util-linux gère les longues mais n'est pas portable. Erreur d'usage → message, rappel de `--help`, code 2. Les noms d'hôte sont validés (`^[A-Za-z0-9][A-Za-z0-9._-]*$`) : un nom commençant par `-` serait lu par `ssh` comme une option (`-oProxyCommand=…` exécute une commande locale).
2. **Mode strict** `set -Eeuo pipefail` :
   - `-e` : arrêt sur la première commande en échec non testée (évite de continuer après un `mkdir` ou un `cd` raté) ;
   - `-u` : variable non définie = erreur (évite `rm -rf "$DOSIER/"*` avec une faute de frappe qui devient `rm -rf /*`) ;
   - `-o pipefail` : un tube échoue si l'un de ses éléments échoue (évite l'archive vide de Lucas, voir ci-dessous) ;
   - `-E` : le piège `ERR` est hérité par les fonctions et sous-shells (sinon le message « erreur inattendue ligne … » ne s'affiche pas pour une erreur dans une fonction).
3. **Collecte** : `ssh … "$commande" 2>"$err" | gzip -c >"$tmp"`. La commande distante est construite avec `printf -v commande '%q ' sudo -n tar -C / --create --file=- --ignore-failed-read "${CHEMINS[@]}"` : `ssh` concatène ses arguments en une chaîne que le shell distant réinterprète, `%q` protège chaque élément. `--ignore-failed-read` transforme les chemins absents en avertissements (code 0), comptés et signalés.

   Expérience de l'étape 3, **sans** `pipefail`, hôte inexistant :
   ```
   admin@adm01:~$ ssh hote-inexistant.invalid 'sudo -n tar -C / -cf - etc/hostname' | gzip -c >/tmp/x.tar.gz; echo "code $?"; ls -l /tmp/x.tar.gz
   ssh: Could not resolve hostname hote-inexistant.invalid: Name or service not known
   code 0
   -rw-r--r-- 1 admin admin 20 oct.   4 09:31 /tmp/x.tar.gz
   ```
   Code 0 et un fichier de 20 octets : un gzip valide… d'un flux vide. C'est exactement l'incident du ticket. Avec `pipefail`, le code vaut 255 (celui de `ssh`).
4. **Atomicité** : dossier de travail `mktemp -d "$DOSSIER/.ms-collecte.XXXXXX"` (même système de fichiers que la destination, donc `mv` = renommage atomique) ; contrôle de l'archive (`tar -tzf` dans un fichier, puis `grep -qx etc/hostname`) ; refus d'écraser une archive existante ; `mv` vers le nom final. Personne ne voit jamais une archive partielle sous son nom final.
5. **Pièges** : `trap nettoyer EXIT` supprime le dossier de travail dans tous les cas ; `trap 'sur_erreur "$LINENO" "$?" "$BASH_COMMAND"' ERR` dit où une erreur inattendue s'est produite ; `INT` → code 130, `TERM` → code 143, avec un message. Pendant une collecte, Ctrl-C est immédiat (le signal atteint aussi `ssh` et `gzip`, du même groupe de processus) ; un `kill -TERM` envoyé au seul script n'est traité qu'à la fin de la commande au premier plan : Bash attend que le tube `ssh | gzip` se termine avant d'exécuter le piège. Pour un arrêt immédiat, il faudrait lancer la commande en arrière-plan et `wait` (interruptible par un signal) : sujet de l'E30.
6. **Un hôte en échec n'arrête pas les autres** : `if collecter "$h"; then … else echecs=$((echecs + 1)); fi`, puis code 1 si `echecs > 0`. Conséquence sur la fonction : appelée comme condition, **`set -e` est désactivé dans tout son corps**. Une étape ratée ne l'arrêterait pas : chaque étape est donc testée explicitement (`if ! …; then journal …; return 1; fi`, `mv … || return 1`). ShellCheck le signale si on active la vérification optionnelle `check-set-e-suppressed` (SC2310).
7. **Garde-fou** : on remonte jusqu'au premier dossier existant du chemin demandé, on demande à Git s'il est dans une copie de travail, et on refuse (code 3) **avant** `mkdir -p` : sinon le refus laisserait un dossier vide dans le dépôt.
8. **Essais** :
   ```
   admin@adm01:~/src/outils$ bin/ms-collecte-config gw01 dns01 git01 runner01
   2026-10-04T09:40:12+02:00 ms-collecte-config : gw01 : 9 chemin(s) absent(s) ignoré(s)
   /home/admin/collectes/gw01-20261004-094012.tar.gz
   2026-10-04T09:40:12+02:00 ms-collecte-config : gw01 : collecte terminée
   …
   admin@adm01:~/src/outils$ echo $?
   0
   admin@adm01:~/src/outils$ bin/ms-collecte-config -o ~/src/outils/x dns01; echo $?
   2026-10-04T09:41:02+02:00 ms-collecte-config : refus : /home/admin/src/outils/x est dans un dépôt Git (les archives contiennent des secrets)
   3
   ```
   Commit `feat: outil ms-collecte-config` : c'est un `feat`, la fusion déclenche la première version, `v1.0.0` (semantic-release part de 1.0.0).

**Explications**

- **Sortie standard propre** : seuls les chemins y sont écrits, les messages vont sur la sortie d'erreur avec un horodatage. On peut donc écrire `for a in $(ms-collecte-config gw01); do …` ou `ms-collecte-config gw01 | xargs …` sans filtrer du bruit.
- **Le contrôle de l'archive** est la vraie garantie : `pipefail` attrape l'échec de `ssh`, mais pas un `sudo` qui répondrait 0 avec une sortie vide, ni une archive tronquée. On vérifie le **résultat**, pas seulement les codes.
- **`--ignore-failed-read`** est un compromis : il ne faut pas qu'un `etc/gitlab/gitlab.rb` absent sur `dns01` fasse échouer la collecte, mais il ne faut pas non plus masquer un fichier illisible pour une mauvaise raison ; d'où le décompte des avertissements dans le journal.
- **Mode 600 et dossier 700** viennent de `umask 077`, posé en tête : tout ce que crée le script est privé, sans `chmod` après coup (qui laisserait une fenêtre).

**Alternatives**

- `rsync -a --rsync-path="sudo rsync"` vers un dossier daté : incrémental, mais plus de fichiers à gérer et la même question d'atomicité.
- **etckeeper** sur chaque VM : `/etc` versionné localement par Git à chaque `apt` ; complémentaire (historique sur l'hôte), pas une copie hors de l'hôte.
- Ansible (`fetch`, module 04) : collecte parallèle et inventaire, mais un outil d'astreinte doit rester utilisable quand Ansible ou son inventaire sont en panne.
- `bash -s` : envoyer un script distant sur l'entrée standard (`ssh hote 'sudo -n bash -s' <<'EOF' … EOF`) évite les problèmes de guillemets, mais l'entrée standard n'est plus disponible pour autre chose.

**Pièges classiques**

- `tar -tzf … | grep -q …` avec `pipefail` : `grep -q` s'arrête à la première correspondance et ferme le tube, `tar` reçoit SIGPIPE et sort en erreur, le tube « échoue » alors que l'archive est bonne. Échec **aléatoire**, selon la position du fichier dans l'archive et la taille des tampons. Écrire la liste dans un fichier, ou `grep` sans `-q`.
- Fonction appelée dans un `if` et écrite en comptant sur `set -e` : les étapes ratées passent inaperçues.
- `trap "rm -rf $TRAVAIL" EXIT` entre guillemets doubles **avant** d'avoir affecté `TRAVAIL` : le piège supprime… la valeur vide du moment (SC2064). Apostrophes, ou fonction de nettoyage qui lit la variable au moment du nettoyage.
- `mktemp` dans `/tmp` puis `mv` vers `~/collectes` : deux systèmes de fichiers possibles, `mv` devient copie + suppression, plus atomique.
- Messages sur la sortie standard : ils polluent les chemins renvoyés et cassent les scripts appelants.
- Écrire l'archive avec un `umask` par défaut (022) puis `chmod 600` : pendant un instant, les secrets sont lisibles par tous.

**En production chez MédiSphère**

- Les collectes partent sur un stockage chiffré et sauvegardé (PBS, ou le S3 du socle au module 05), avec une rétention ; elles contiennent des secrets et relèvent de la même politique que les sauvegardes.
- Le runbook « avant intervention » appelle `ms-collecte-config` puis `ms-snapshot` (E11), et le guide d'astreinte (E31) explique les codes retour.
- La liste des chemins devient une donnée (fichier de configuration par rôle d'hôte, alimenté par l'inventaire), plutôt qu'une constante du script.

---

### M02-E04 — ShellCheck et shfmt : lire, corriger, configurer

**Solution**

1. **Diagnostic** (ShellCheck 0.11, sévérité par défaut) et classement :

   | Script | Code (lignes) | Catégorie | Commentaire |
   |---|---|---|---|
   | `purge_logs.sh` | SC2164 (`cd $DIR`) | **bogue** | si `cd` échoue, la suite s'exécute dans le dossier courant |
   | | SC2045 (`for f in $(ls …)`) | **bogue** | noms avec espaces découpés ; `rm` sur des morceaux de noms |
   | | SC2086 (×8) | **bogue/fragilité** | variables non protégées : découpage et jokers |
   | | SC2035 (`ls *.log`) | fragilité | un fichier nommé `-r.log` devient une option |
   | | SC2006, SC2003 | style | accents graves, `expr` |
   | `check_disk.sh` | SC2155 (`local usage=$(…)`) | fragilité | code retour masqué |
   | | SC2086 (×4) | fragilité | `$ligne` non protégé |
   | | SC2162 (`read` sans `-r`) | fragilité | barres obliques inverses mangées |
   | | SC2181 (`if [ $? -ne 0 ]`) | style | test indirect, cassé si on insère une ligne entre les deux |
   | `sauvegarde_config.sh` | SC3030, SC3054, SC3010 | **bogue** | tableaux et `[[ ]]` dans un script `#!/bin/sh` : sur Debian, `/bin/sh` est `dash` |
   | | SC2068 (`${FICHIERS[@]}`) | **bogue** | éléments redécoupés |
   | | SC2206 (`FICHIERS=($@)`) | **bogue** | arguments redécoupés et soumis aux jokers |
   | | SC2064 (`trap "rm -rf $TMP" EXIT`) | fragilité | développé à la pose du piège |
   | | SC2024 (`sudo echo … > fichier`) | **bogue** | la redirection est faite par ton shell, sans privilège |
   | | SC2029 (`ssh … "… $(hostname)"`) | **bogue** | développé **localement** : le message annonce `adm01` |
   | | SC2059 (`printf "$msg\n"`) | **bogue** | le `%` du message est lu comme une directive |
   | | SC2086 (×7) | fragilité | variables non protégées |

   Cinq scénarios concrets :
   - `purge_logs.sh` sans argument : `cd` sans argument va dans `$HOME`, la boucle supprime les `.log` de plus de 30 jours **du dossier personnel** de l'utilisateur de cron, puis `rm -rf /archives/*` (car `$DIR` est vide) vise la racine ;
   - un journal nommé `app 2023.log` : `ls` le rend en deux mots, `stat app` et `stat 2023.log` échouent, le fichier n'est jamais purgé (et `rm` pourrait toucher un autre fichier nommé `app`) ;
   - `sauvegarde_config.sh gw01 /etc/nftables.conf` lancé par `sh` : `dash` s'arrête sur `FICHIERS=($@)` avec `Syntax error: "(" unexpected`, code 2 : **le script n'a jamais fonctionné** tel que livré, sauf lancé explicitement par `bash` ;
   - le fichier d'état `/srv/sauvegardes/ETAT` n'est jamais écrit : `sudo echo … > fichier` ouvre le fichier avec les droits de l'utilisateur (Permission denied) ;
   - le message final : `printf "…terminee a 100%\n"` répond `printf: '\': invalid format character`, code 1, message tronqué.
2. **Défauts invisibles pour ShellCheck** :
   - `check_disk.sh` : la boucle `while` est après un tube, donc dans un sous-shell ; `alertes` y est incrémenté puis perdu. Résultat : le script affiche les `ALERTE …` **et** « OK : aucune partition au-dessus… », et sort toujours en 0. La supervision ne voit jamais rien. (`check_disk.sh 1` le montre immédiatement.)
   - `check_disk.sh` : `df -P` liste aussi `tmpfs`, `devtmpfs`, `overlay`… ; un point de montage avec espace décale les colonnes ; certains montages affichent `-` en pourcentage (`[ - -ge 90 ]` : « integer expression expected ») ; et `exit $alertes` repasse à 0 au-delà de 255 alertes (code modulo 256).
   - `purge_logs.sh` : `rm -rf $DIR/archives/*` supprime **toutes** les archives, alors que le commentaire parle des « vieux » dossiers ; `DAYS` n'est pas validé (`purge_logs.sh /var/log/app 3O` avec la lettre O) ; aucun code retour significatif.
   - `sauvegarde_config.sh` : les échecs de `scp` sont ignorés (et le test `[[ -f $fichier ]]` « fichier local ignoré » n'a aucun sens pour un fichier distant) ; `cp $TMP/*` échoue si rien n'a été copié ; l'archive distante dans `/tmp` n'est jamais rapatriée.
3. **Versions corrigées** : [`fichiers/M02-E04/infoger-corrige/`](fichiers/M02-E04/infoger-corrige/). Toutes en `#!/usr/bin/env bash` et `set -euo pipefail`, usage et codes retour (2 pour l'usage, 3 pour le refus de purger `/`). Décisions notées : `purge_logs.sh` ne supprime plus que les **anciennes** archives (intention du commentaire), avec `find -mtime +N -delete` qui compte ce qu'il supprime ; `check_disk.sh` lit `df --output=pcent,target` par une substitution de processus et sort en 1 au moindre dépassement ; `sauvegarde_config.sh` refuse les chemins non absolus, protège l'expansion distante (seule directive `disable` : SC2016, justifiée) et écrit l'état avec `sudo tee`.

   `shellcheck -f diff purge_logs.sh` propose les corrections mécaniques (guillemets, `$(…)`). On les accepte pour les guillemets ; on refuse de s'en contenter pour `cd` (un `|| exit` ne suffit pas : il faut aussi valider l'argument) et pour la boucle sur `ls`, qui doit être réécrite (`find`). Un correctif automatique traite le symptôme, pas la conception.
4. **`.shellcheckrc`** : [`fichiers/M02-E04/.shellcheckrc`](fichiers/M02-E04/.shellcheckrc). `external-sources=true` et `source-path=SCRIPTDIR` : ShellCheck suit `source "…/../lib/ms-commun.sh"` (E10), avec une directive `# shellcheck source=../lib/ms-commun.sh` au-dessus de la ligne, chemin relatif au script. Vérifications optionnelles retenues : `require-double-brackets`, `avoid-nullary-conditions`, `deprecate-which`. Pas `enable=all` : certaines sont des choix de style contestables (`require-variable-braces`) ou très bruyantes (`check-extra-masked-returns` sur chaque `$(date)`), et une règle qu'on contourne en permanence n'est plus lue. `check-set-e-suppressed` (SC2310) est instructive : lance-la ponctuellement (`shellcheck -o check-set-e-suppressed`).
5. **`.editorconfig`** : [`fichiers/M02-E04/.editorconfig`](fichiers/M02-E04/.editorconfig). Deux sections pour le même style : `[*.{sh,bash}]` (toute profondeur) et `[bin/**]` (motif avec `/`, donc relatif à la racine : il ne peut pas être fusionné dans la première accolade sans perdre l'effet « toute profondeur »). Les `.bats` ont `shell_variant = bats` : en dialecte `bash`, shfmt refuse les blocs `@test`. Contrôle :
   ```
   admin@adm01:~/src/outils$ shfmt -d bin/        # aucune sortie = conforme
   admin@adm01:~/src/outils$ shfmt -w bin/
   ```
6. **pre-commit** : extrait à ajouter, [`fichiers/M02-E04/pre-commit-extrait.yaml`](fichiers/M02-E04/pre-commit-extrait.yaml). Le hook `shellcheck` de `shellcheck-py` télécharge **son propre** binaire 0.11.0 (paquet Python), le hook `shfmt` celui de la release 3.14.1 : ni la version de `adm01`, ni celle de `runner01` n'interviennent. C'est voulu : poste, pre-commit et CI donnent le même verdict. La contrepartie : deux versions à suivre (celle du poste pour l'éditeur, celle épinglée dans pre-commit) ; on les aligne à chaque mise à jour.

**Explications**

- **Sévérités** : `error` (syntaxe, presque toujours un bogue), `warning` (bogue probable), `info` (fragilité), `style`. La vérification utilise `-S style` : on vise zéro remarque, quitte à justifier une directive.
- **`--norc` dans la vérification** : les scripts d'InfoGér ne sont pas dans le dépôt, mais on s'assure qu'aucune configuration n'en masque un défaut.
- **shfmt et EditorConfig** : shfmt n'applique `.editorconfig` que si aucune option de formatage n'est passée en ligne de commande (`-i 2` désactive toute la section). D'où un hook pre-commit **sans** arguments de style.

**Alternatives**

- Bash Language Server dans l'éditeur (ShellCheck et shfmt intégrés) : le retour arrive pendant l'écriture, pas au commit.
- `checkbashisms` (paquet `devscripts`) pour les scripts qui doivent rester en `sh` POSIX.
- Imposer `[[ ]]` par revue plutôt que par `require-double-brackets` : moins de bruit, mais dépend de la vigilance du relecteur.

**Pièges classiques**

- Ajouter `# shellcheck disable=SC2086` en tête de fichier « pour avoir la paix » : on masque la famille de bogues la plus fréquente. Une directive se pose au plus près, avec sa justification.
- Corriger par `"$var"` partout sans réfléchir : `rm -rf "$DIR"/*` avec `DIR` vide reste `rm -rf /*`. Il faut `"${DIR:?}"` ou une validation en amont.
- `[*.sh]` seul dans `.editorconfig` : les scripts sans extension de `bin/` sont formatés avec les tabulations par défaut de shfmt.
- Un script `#!/bin/sh` testé avec `bash script.sh` : il marche chez soi, échoue en production.
- Faire confiance à un ShellCheck vert : il ne voit ni la logique (sous-shell de `check_disk.sh`), ni les données.

**En production chez MédiSphère**

- ShellCheck et shfmt tournent aussi en CI (E24) : un poste sans pre-commit ne contourne rien.
- Les scripts hérités d'InfoGér encore utilisés sont recensés et réécrits dans `plateforme/outils` avec des tests (E14), puis déployés par Ansible (module 04) ; les originaux sont retirés des serveurs.
- Revue annuelle des vérifications optionnelles activées, au fil des versions de ShellCheck (0.11 a, par exemple, rendu SC2002 optionnelle).

---

### M02-E05 — jq : interroger l'API Proxmox

**Solution**

1. **Exploration.** `jq -c '.data[] | {vmid, name, pool, type, tags}' cluster-resources.json` montre que `pool` est **absent** pour les VMs hors pool (100, 101), `tags` absent pour les VMs sans étiquette (2022, 5003), et que la réponse contient aussi des conteneurs (`type: "lxc"`). Un filtre qui suppose la présence d'un champ produit `null`, qui s'affiche `null` en sortie brute ou fait échouer `split`.

2. **Filtres** (fichiers complets, avec en-têtes : [`fichiers/M02-E05/lib/jq/`](fichiers/M02-E05/lib/jq/)) :
   ```jq
   # vms-lab.jq
   .data
   | map(select(.type == "qemu" and .pool == "lab" and (.template // 0) != 1 and .template != true))
   | sort_by(.vmid)
   | .[]
   | [.vmid, .name, .status, (.maxmem / 1048576 | floor), (.tags // "")]
   | @tsv
   ```
   ```jq
   # bilan-lab.jq (extrait du cœur)
   [.data[] | select(.type == "qemu" and .pool == "lab" and (.template // 0) != 1 and .template != true)]
   | { vms: length,
       en_marche: (map(select(.status == "running")) | length),
       memoire_en_marche_mio: (map(select(.status == "running") | .maxmem) | add // 0 | . / 1048576 | floor),
       par_etiquette: ([.[] | (.tags // "") | split(";")[] | select(. != "")]
                       | group_by(.) | map({key: .[0], value: length}) | from_entries),
       sans_etiquette: (map(select((.tags // "") == "") | .vmid) | sort) }
   ```
   `ipv4-invite.jq` parcourt `.data.result[]`, écarte `lo`, prend `.["ip-addresses"][]?` (le `?` tolère une interface sans adresse, comme `eth2` dans le fichier fourni), garde `ipv4` puis écarte `127.` et `169.254.`. `taches-echec.jq` garde `starttime >= $depuis`, `has("status")` (une tâche en cours n'en a pas), statut ni `OK` ni `WARNINGS…`, trie par `starttime` décroissant et formate avec `todate`.

   Contrôle :
   ```
   admin@adm01:~/src/outils$ R=~/DevOpsPrivateCloud/modules/02-scripting/ressources/M02-E05
   admin@adm01:~/src/outils$ diff <(jq -r -f lib/jq/vms-lab.jq $R/cluster-resources.json) $R/attendu/vms-lab.tsv && echo identique
   identique
   admin@adm01:~/src/outils$ diff <(jq -S . <(jq -f lib/jq/bilan-lab.jq $R/cluster-resources.json)) <(jq -S . $R/attendu/bilan-lab.json) && echo identique
   identique
   admin@adm01:~/src/outils$ jq -r --argjson depuis 1790812800 -f lib/jq/taches-echec.jq $R/taches.json
   2026-10-03T07:20:00Z	qmclone	9000	wb-automation@pve!lab	unable to create VM 2021: config file already exists
   2026-10-02T23:50:00Z	qmsnapshot	1004	wb-automation@pve!lab	VM is locked (backup)
   ```

3. **API réelle**, secret jamais sur la ligne de commande ni dans un fichier de travail :
   ```
   admin@adm01:~$ ( . ~/.config/workbook/pve-api.env
       curl -sSf --cacert "$PVE_CACERT" \
         -H @<(printf 'Authorization: PVEAPIToken=%s=%s\n' "$PVE_TOKEN_ID" "$PVE_TOKEN_SECRET") \
         "$PVE_API_URL/cluster/resources?type=vm" ) > ~/m02/e05/reel.json
   admin@adm01:~$ jq -r -f ~/src/outils/lib/jq/vms-lab.jq ~/m02/e05/reel.json | column -t -s $'\t'
   ```
   Questions, une commande chacune :
   ```
   jq -r '[.data[] | select(.pool == "lab" and .type == "qemu")] | max_by(.maxmem) | "\(.name) \(.maxmem / 1073741824) Gio"' reel.json
   jq '[.data[] | select(.pool == "lab" and .type == "qemu" and (.template // 0) != 1)]
       | (map(select((.tags // "") | split(";") | index("socle"))) | map(.maxmem) | add) / (map(.maxmem) | add) * 100 | round' reel.json
   jq -r '.data[] | select(.pool == "lab" and .status == "stopped" and (.template // 0) != 1) | "\(.vmid) \(.name)"' reel.json
   ```
   (Dans le lab, c'est en principe `git01`, avec 8 Gio, qui réserve le plus.)

4. **Étiquettes du socle.** Repérage, puis génération des appels :
   ```
   admin@adm01:~/m02/e05$ jq -r '.data[] | select(.type == "qemu" and .pool == "lab" and .vmid >= 1000 and .vmid <= 1099)
       | ((.tags // "") | split(";")) as $t
       | select(($t | index("socle")) == null or ($t | any(startswith("role-")) | not))
       | [.vmid, .name, (.tags // "")] | @tsv' reel.json | tee anciennes-etiquettes.tsv
   1000	gw01	reseau;socle
   1001	adm01	socle;admin
   1002	dns01	socle;dns
   ```
   Correspondance voulue, puis commandes générées (relues avant exécution) :
   ```
   admin@adm01:~/m02/e05$ jq -r --arg node "$(. ~/.config/workbook/pve-api.env; echo "$PVE_NODE")" '
       {"gw01": "socle;role-routeur", "adm01": "socle;role-bastion", "dns01": "socle;role-dns"} as $voulu
       | .data[] | select(.type == "qemu" and .pool == "lab" and ($voulu[.name] != null))
       | ["api_put", "/nodes/\($node)/qemu/\(.vmid)/config", "tags=\($voulu[.name])"] | @sh' reel.json > corrections.sh
   admin@adm01:~/m02/e05$ cat corrections.sh
   'api_put' '/nodes/pve01/qemu/1000/config' 'tags=socle;role-routeur'
   …
   ```
   où `api_put` est une petite fonction de ta session qui fait le `curl -X PUT --data-urlencode "$2"` avec l'en-tête lu par descripteur (comme ci-dessus). `@sh` protège chaque élément du tableau : un `;` dans la valeur ne peut pas devenir un séparateur de commandes. Retour arrière : la même génération à partir de `anciennes-etiquettes.tsv`. Alternative acceptable : `ssh pve01 qm set 1000 --tags 'socle;role-routeur'`.

5. **Contrôle et tâches** : `bilan-lab.jq` sur une nouvelle réponse montre `"socle": 5` et les trois `role-…` ajoutés. Pour les tâches : `jq -r --argjson depuis "$(date -d '-24 hours' +%s)" -f lib/jq/taches-echec.jq taches-reelles.json` (réponse de `GET /nodes/<NŒUD>/tasks`).

6. **Notions** :
   - `-r` écrit les chaînes sans guillemets JSON (pour le shell) ; sans `-r`, la sortie reste du JSON valide (pour un autre `jq`) ;
   - `-e` : code retour 1 si le dernier résultat est `false` ou `null`, 4 s'il n'y a aucun résultat : utile dans un `if jq -e … ; then` ;
   - `--arg n v` passe une **chaîne** ; `--argjson n v` passe une valeur JSON (nombre, objet). `--arg depuis 1790812800` comparerait une chaîne à un nombre : en jq, tout nombre est inférieur à toute chaîne, le filtre ne renverrait rien ;
   - `.x // "défaut"` remplace `null` **et `false`** : pour un champ booléen, `.actif // true` vaut toujours `true`. Écrire `if .actif == null then true else .actif end` ;
   - `@sh` formate une valeur ou un tableau en mots protégés pour le shell ; concaténer des guillemets à la main casse au premier caractère spécial.

**Explications**

- **`/cluster/resources`** renvoie toutes les ressources visibles par le jeton : avec un jeton limité au pool, les VMs personnelles n'apparaissent normalement pas. Les fichiers fournis en contiennent quand même (100, 101) : un filtre ne doit pas dépendre des droits du jeton qui a produit la réponse.
- **Templates** : le champ `template` vaut 1 pour un template (selon les versions et les clients, il peut aussi arriver en booléen) ; le filtre traite les deux formes.
- **Étiquettes** : chaîne unique dont les valeurs sont séparées par `;`. Proxmox les trie ou non selon la configuration du centre de données (`tag-style`) : ne compte jamais sur leur ordre.
- **`todate`** formate en UTC (`Z`). Pour l'heure locale : `strflocaltime("%F %T")`.

**Alternatives**

- `pvesh get /cluster/resources --type vm --output-format json` sur `pve01` : même JSON, mais il faut un accès root à l'hyperviseur, ce qu'on évite pour l'outillage.
- Le même travail en Python (E15, E21) : plus lisible au-delà de quelques lignes de filtre, testable avec pytest.
- `gron` (aplatit le JSON pour `grep`) ou `jaq` (réimplémentation rapide de jq) pour l'exploration.

**Pièges classiques**

- Oublier `-r` : les champs TSV arrivent entre guillemets.
- `select(.pool == "lab")` d'abord oublié, puis le template 9000 compté comme une VM.
- `split(";")` sur `null` : erreur « cannot be split » ; toujours `(.tags // "")`.
- `.[]` sur un objet absent : `[]?` ou `// []`.
- Écrire le secret dans un fichier de travail (`curl -H "Authorization: …"` dans un script de `~/m02/e05/`) ou l'historique du shell.
- Modifier les étiquettes sans noter les anciennes : pas de retour arrière.

**En production chez MédiSphère**

- Les filtres versionnés sont testés en CI sur les réponses enregistrées (bats, E14) : une évolution de l'API Proxmox est détectée avant l'astreinte.
- La conformité des étiquettes devient une règle automatique : l'inventaire dynamique Ansible (M04) et les sources de données OpenTofu (M05) en dépendent ; un contrôle planifié signale toute VM du socle mal étiquetée.

---

### M02-E06 — yq : modifier du YAML sans le casser

**Solution**

Tout est rejouable avec [`fichiers/M02-E06/commandes-yq.sh`](fichiers/M02-E06/commandes-yq.sh) ; les résultats attendus sont dans [`fichiers/M02-E06/resultats/`](fichiers/M02-E06/resultats/) (la clé SSH y est un exemple).

1. **Quel yq ?** `yq --version` → `yq (https://github.com/mikefarah/yq/) version v4.54.1`. `apt show yq` décrit le paquet Debian : « Command-line YAML/XML/TOML processor - jq wrapper for YAML », c'est-à-dire l'outil Python de kislyuk, qui transforme le YAML en JSON pour `jq`. Syntaxe et options différentes : un script écrit pour l'un échoue avec l'autre.

2. **Lire, et la clé de fusion.**
   ```
   admin@adm01:~/m02/e06$ yq -r 'explode(.) | .all.children[].hosts | to_entries | .[] | [.key, .value.ansible_host, .value.ntp_serveur] | @tsv' inventaire-infoger.yml
   time=… level=WARN msg="--yaml-fix-merge-anchor-to-spec is false; causing merge anchors to override the existing values which isn't to the yaml spec. …"
   gw01	10.10.10.1	10.10.20.1
   …
   ```
   Pour `gw01`, la clé `ntp_serveur: pool.ntp.org` est écrite **avant** `<<: *defaut`. Selon la spécification YAML (et pour PyYAML, donc Ansible), une clé explicite l'emporte toujours sur la fusion : la bonne valeur est `pool.ntp.org`. yq 4.54, par défaut, laisse la fusion écraser la clé si `<<` vient après. D'où :
   ```
   admin@adm01:~/m02/e06$ yq --yaml-fix-merge-anchor-to-spec=true -r '…même expression…' inventaire-infoger.yml > hotes.tsv
   ```
   L'avertissement annonce que ce comportement deviendra le défaut ; en attendant, un fichier dont la lecture dépend de l'outil est un fichier ambigu (étape 4).

3. **Types.** `yq '.all.vars.defaut | map_values(tag)'` :

   | Clé | yq (YAML 1.2) | PyYAML / Ansible (YAML 1.1) | Conséquence |
   |---|---|---|---|
   | `sauvegarde: yes` | `!!str` « yes » | booléen `True` | un outil qui teste `== "yes"` et Ansible ne voient pas la même chose ; `no` (sbx01) donne `False` d'un côté, la chaîne « no » de l'autre |
   | `version_python: 3.10` | `!!float` 3.10 | flottant `3.1` | « 3.10 » devient « 3.1 » dans un modèle Jinja2 : mauvaise version installée |
   | `mode_cles: 0600` | `!!int` 600 (décimal en 1.2) | entier **384** (octal en 1.1, soit 0o600) | `mode: "{{ mode_cles }}"` donne 384 ou 600 selon l'outil ; les modules Ansible recommandent une chaîne `"0600"` |

4. **Inventaire corrigé** (yq, puis lecture du diff) :
   ```
   admin@adm01:~/m02/e06$ cp inventaire-infoger.yml inventaire-corrige.yml
   admin@adm01:~/m02/e06$ yq -i '
       (.. | select(tag == "!!map" and has("sauvegarde")) | .sauvegarde) |= (. == "yes" or . == true)
       | .all.vars.defaut.version_python |= to_string
       | .all.vars.defaut.mode_cles |= to_string
       | .all.children.socle.hosts.gw01 |= sort_keys(.)' inventaire-corrige.yml
   ```
   `to_string` garde le texte d'origine (`"3.10"`, `"0600"`), alors qu'une conversion numérique aurait donné `3.1`. `sort_keys` sur `gw01` place `<<` en tête (le caractère `<` précède les lettres) : la lecture devient identique pour tous les outils. Le diff montre aussi des changements **non demandés** : alignement des commentaires de fin de ligne réduit à une espace, lignes vides supprimées. Ce n'est pas faux, mais c'est du bruit dans une revue ; on le signale dans la MR, ou on accepte le style de yq une fois pour toutes.

5. **user-data** :
   ```
   admin@adm01:~/m02/e06$ CLE="$(head -n 1 ~/.ssh/id_ed25519.pub)" yq -i '
       .ntp.servers = ["10.10.99.1"]
       | (.users[] | select(.name == "admin") | .ssh_authorized_keys) += [strenv(CLE)]
       | .package_upgrade = true' user-data-sandbox.yaml
   admin@adm01:~/m02/e06$ head -n 1 user-data-sandbox.yaml
   #cloud-config
   admin@adm01:~/m02/e06$ cloud-init schema -c user-data-sandbox.yaml
   Valid schema user-data-sandbox.yaml
   ```
   La première ligne survit (yq conserve les commentaires d'en-tête) ; les `permissions: '0644'` restent entre apostrophes. Le diff montre que le commentaire `# clés ajoutées au déploiement`, attaché à l'ancienne liste vide, a été déplacé sur la ligne `ntp:`, et que le commentaire du premier serveur NTP a disparu avec la liste remplacée : yq attache les commentaires aux nœuds, et remplacer un nœud déplace ou perd ses commentaires. Relire le diff après chaque transformation n'est pas facultatif.

6. **Fusion** :
   ```
   admin@adm01:~/m02/e06$ yq ea '. as $f ireduce ({}; . * $f)' parametres-defaut.yml parametres-par2.yml > parametres-effectifs-par2.yml
   ```
   `*` fusionne les objets en profondeur et **remplace** les listes : `ntp.serveurs: [10.20.20.1]`, `supervision.contacts: [astreinte@…]`, et `retention` fusionnée clé par clé (`jours: 14`, `semaines: 4`, `mois: 6`). Avec `*+`, les listes sont **concaténées** : `ntp.serveurs: [10.10.20.1, 10.20.20.1]`, PAR2 interrogerait le serveur de temps de PAR1, ce qu'on ne veut pas. (`*d` fusionne les listes élément par élément, `*n` n'ajoute que les clés absentes.)

7. **JSON → YAML** :
   ```
   admin@adm01:~/m02/e06$ yq -p json -o yaml '[.data[] | select(.type == "qemu" and .pool == "lab" and .template == 0)
       | {"vmid": .vmid, "nom": .name, "etiquettes": ((.tags // "") | split(";") | map(select(. != "")))}]
       | sort_by(.vmid)' ~/m02/e05/cluster-resources.json > vms-lab.yml
   ```
   `split(";")` sur une chaîne vide donne `[""]` : le `map(select(. != ""))` produit la liste vide attendue pour 2022 et 5003.

**Explications**

- **YAML 1.1 contre 1.2** : la 1.2 (2009) a réduit les booléens à `true`/`false` et les octaux à la forme `0o…`. PyYAML, donc Ansible et cloud-init, suivent toujours la 1.1. Règle de l'équipe : dans tout YAML lu par Ansible ou cloud-init, booléens `true`/`false`, versions et modes **entre guillemets**. ansible-lint (module 04) le vérifiera (règle `yaml[truthy]`).
- **Ancres et alias** : `&nom` étiquette un nœud, `*nom` le réutilise, `<<: *nom` fusionne une table dans une autre. `explode(.)` développe tout ; sans lui, yq suit les alias à la lecture mais conserve la structure à l'écriture.
- **`-i`** réécrit le fichier : yq relit, transforme et resérialise tout le document. D'où les changements de style.

**Alternatives**

- Ansible lui-même pour lire l'inventaire (`ansible-inventory -i inventaire.yml --list`) : la vérité de l'outil qui le consommera, mais sans modification.
- Python avec `ruamel.yaml` (conserve commentaires et ordre, YAML 1.2) pour des transformations complexes et testées.
- Ne pas modifier : **générer** le YAML à partir d'une source de vérité (NetBox au module 06, modèles Jinja2), plutôt que l'éditer.

**Pièges classiques**

- Installer le paquet Debian `yq` et passer une heure sur des erreurs de syntaxe.
- `.version_python = 3.10` : yq écrit le nombre `3.10`, toujours lu `3.1` par PyYAML. Il faut une chaîne.
- `yq -i` sans relire le diff : commentaires déplacés, lignes vides perdues, guillemets changés.
- Une clé SSH collée dans l'expression yq : les espaces et le `+` de la clé cassent la commande ; `strenv` lit la variable telle quelle.
- `#cloud-config` perdu après une génération par un autre outil : cloud-init ignore alors silencieusement tout le fichier.
- `*+` au lieu de `*` pour fusionner des paramètres de site.

**En production chez MédiSphère**

- Les fichiers YAML du dépôt passent `yamllint` dans pre-commit (règles `truthy`, `octal-values`) en plus de `check-yaml`.
- Les inventaires et gabarits cloud-init sont générés (NetBox, M06 ; Packer, M03), versionnés, relus en MR : plus personne ne les édite à la main sur un serveur.

---

### M02-E07 — Un environnement Python moderne avec uv

**Solution**

1. `uv --version` → `uv 0.12.23`. `uv python find 3.13` → `/usr/bin/python3.13` si aucun Python « géré » n'a été téléchargé ; `uv python list` montre aussi les versions téléchargeables.
2. **Initialisation** :
   ```
   admin@adm01:~/src/outils$ git switch -c feat/projet-python
   admin@adm01:~/src/outils$ uv init --name medictl --python 3.13
   Initialized project `medictl`
   admin@adm01:~/src/outils$ git status --short
   ?? .python-version
   ?? pyproject.toml
   ?? src/
   ```
   uv 0.12 crée un projet **empaqueté** : `pyproject.toml` (avec `[build-system]` `uv_build` et `[project.scripts] medictl = "medictl:main"`), `.python-version` (`3.13`), `src/medictl/__init__.py` (une fonction `main` d'exemple). Le `README.md` existant n'est pas touché ; dans un dépôt Git existant, ni `git init` ni `.gitignore`. `--no-package` aurait créé un `main.py` à la racine sans système de construction (application non installable) ; `--lib` une bibliothèque (marqueur `py.typed`, pas de commande). Une CLI qu'on installera sur d'autres postes (E25) doit être un paquet : elle se construit en *wheel*, s'installe avec `uv tool install`, et sa commande est créée par le point d'entrée.
3. **Python du système** : dans `pyproject.toml`,
   ```toml
   [tool.uv]
   python-preference = "only-system"
   python-downloads = "never"
   ```
   uv refusera de télécharger un interpréteur et n'utilisera que ceux du système. Justification (ticket) : les correctifs de sécurité de Python arrivent par `apt` avec ceux du reste du système, et `runner01` (Debian 13) aura exactement le même interpréteur. Contrepartie : la version de Python du projet suit Debian (3.13 jusqu'à Debian 14).
4. **Dépendances** :
   ```
   admin@adm01:~/src/outils$ uv add typer proxmoxer requests
   admin@adm01:~/src/outils$ uv add --dev pytest responses ruff
   admin@adm01:~/src/outils$ uv tree --depth 2
   ```
   `pyproject.toml` reçoit des contraintes minimales (`typer>=0.27.2`…) et un groupe `[dependency-groups] dev`. `uv.lock` contient pour **chaque** paquet, dépendances transitives comprises : version exacte, source (index PyPI), empreintes SHA-256 des archives et *wheels*, dépendances et marqueurs. `uv tree` montre que `rich` (et `shellingham`) viennent de `typer`. Depuis Typer 0.26, Click est intégré à Typer : `click` n'apparaît plus comme dépendance.
5. **Code** : [`fichiers/M02-E07/outils/src/medictl/`](fichiers/M02-E07/outils/src/medictl/). `__init__.py` lit la version installée avec `importlib.metadata.version("medictl")` ; `cli.py` déclare l'application Typer, son *callback* et l'option `--version` (`is_eager=True`, rappel qui affiche puis lève `typer.Exit()`). Dans `pyproject.toml` : `medictl = "medictl.cli:app"`. `uv run medictl --version` → `medictl 0.1.0`. Avant d'exécuter, `uv run` vérifie que le verrou correspond à `pyproject.toml` (et le met à jour si besoin), synchronise `.venv` sur le verrou (en y installant le projet lui-même en mode éditable), puis lance la commande dans cet environnement. Sans argument, `medictl` affiche l'aide et sort en 2 (convention « usage »).
6. **ruff et pytest** : `pyproject.toml` complet dans [`fichiers/M02-E07/outils/pyproject.toml`](fichiers/M02-E07/outils/pyproject.toml) (`select = ["E", "W", "F", "I", "B", "UP", "S", "SIM", "RUF"]`, `S101` autorisé dans les tests, `testpaths = ["tests/python"]`).
7. **pre-commit** : extrait [`fichiers/M02-E07/pre-commit-extrait.yaml`](fichiers/M02-E07/pre-commit-extrait.yaml), `rev: v0.16.10` = la version de ruff dans `uv.lock`. `.gitignore` (E02) contient déjà `.venv/` et les caches.
8. **Reproductibilité** :
   ```
   admin@adm01:~/src/outils$ rm -rf .venv && uv sync --locked
   admin@adm01:~/src/outils$ uv lock --check && echo "verrou à jour"
   admin@adm01:~/src/outils$ cat .venv/pyvenv.cfg | grep ^home
   home = /usr/bin
   ```
   `--locked` : échoue si le verrou ne correspond plus à `pyproject.toml` (on le veut en CI : une dépendance ajoutée sans verrou est refusée). `--frozen` : utilise le verrou **sans vérifier** qu'il est à jour (plus rapide, mais peut installer un état qui ne correspond pas au `pyproject.toml`). Si quelqu'un modifie `pyproject.toml` sans `uv lock`, le prochain `uv run` sur un poste met le verrou à jour en silence ; seule la CI (`uv sync --locked`, E24) ou `uv lock --check` le détecte : c'est elle qui doit faire foi.

**Explications**

- **Projet, verrou, environnement** : trois niveaux distincts. On modifie le premier (à la main ou par `uv add`), uv calcule le deuxième, et le troisième n'est qu'un cache reconstructible.
- **`uv_build`** : système de construction de uv, rapide et strict sur la disposition `src/<nom>/`. Le nom du module doit correspondre au nom du projet normalisé.
- **ruff `select` explicite** : le jeu de règles par défaut a changé avec ruff 0.16 ; une liste explicite rend le résultat indépendant des versions. `S` (bandit) signalera `verify=False` (S501), une requête sans délai (S113), un `subprocess` avec `shell=True` (S602).

**Alternatives**

- `python3 -m venv` + `pip` + `requirements.txt` (avec `pip-tools` pour verrouiller) : classique, plus lent, sans gestion des groupes ni du Python.
- Poetry, PDM, Hatch : gestionnaires de projets complets ; uv est retenu pour sa vitesse et parce qu'il couvre aussi les outils (`uv tool`) et les scripts (PEP 723).
- Python « géré » par uv (`uv python install 3.13`) : version exacte identique partout, indépendante de Debian, mais correctifs à suivre soi-même.

**Pièges classiques**

- `uv init` dans un sous-dossier : le `pyproject.toml` n'est pas à la racine, la CI ne le trouve pas.
- Versionner `.venv/`, ou oublier de versionner `uv.lock`.
- `uv pip install …` à la main dans `.venv` : invisible dans le verrou, perdu au prochain `uv sync`.
- Garder le `main` d'exemple et le point d'entrée `medictl:main` : la commande imprime « Hello from medictl! ».
- Hook ruff de pre-commit à une version différente de celle du verrou : pre-commit et CI ne s'accordent pas.
- Laisser uv télécharger un Python (préférence par défaut `managed`) sur un poste, et pas sur un autre : deux interpréteurs différents, des différences de comportement « inexplicables ».

**En production chez MédiSphère**

- La CI (E24) fait `uv sync --locked` et échoue si le verrou n'est pas à jour.
- Les mises à jour de dépendances passent par une MR dédiée (`uv lock --upgrade-package …`), relue avec le diff du verrou ; Renovate les proposera (module 13).
- Les empreintes du verrou protègent contre un paquet remplacé sur l'index ; un miroir interne de PyPI viendra avec les services de plateforme (blocs C et G).

---

### M02-E08 — Premier client Python de l'API Proxmox, TLS vérifié

**Solution**

1. **requests** : [`fichiers/M02-E08/essai_requests.py`](fichiers/M02-E08/essai_requests.py).
   ```
   admin@adm01:~/src/outils$ uv run python ~/m02/e08/essai_requests.py
   GET /version → 200 OK
      dict de 3 élément(s)
   GET /cluster/resources?type=vm → 200 OK
      list de 9 élément(s)
   GET /nodes/pve01/status → 403 Permission check failed (/nodes/pve01, Sys.Audit)
   ```
   Le 403 est normal : le jeton n'a aucun droit sur le nœud (M00-E17). Proxmox place le motif du refus dans la ligne de statut, d'où l'intérêt d'afficher `reason`. Le `verify=` est passé à **chaque** appel : un `session.verify` serait écrasé par `REQUESTS_CA_BUNDLE` ou `CURL_CA_BUNDLE` si l'une de ces variables est définie (comportement documenté de `requests`).

2. **Si TLS refuse.** Message typique avec une autorité Proxmox ancienne :
   ```
   requests.exceptions.SSLError: … [SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed: CA cert does not include key usage extension (_ssl.c:1032)
   ```
   Diagnostic :
   ```
   admin@adm01:~$ openssl x509 -in ~/.config/workbook/pve-root-ca.pem -noout -ext keyUsage,basicConstraints
   No extensions in certificate with keyUsage      # ou absence de la ligne X509v3 Key Usage
   X509v3 Basic Constraints: critical
       CA:TRUE
   admin@adm01:~$ ssh pve01 cat /etc/pve/local/pve-ssl.pem > /tmp/pve-ssl.pem
   admin@adm01:~$ openssl verify -CAfile ~/.config/workbook/pve-root-ca.pem /tmp/pve-ssl.pem
   /tmp/pve-ssl.pem: OK
   admin@adm01:~$ openssl verify -x509_strict -CAfile ~/.config/workbook/pve-root-ca.pem /tmp/pve-ssl.pem
   error 92 at 1 depth lookup: CA cert does not include key usage extension
   ```
   La RFC 5280 exige qu'un certificat d'autorité porte l'extension *Key Usage* avec `keyCertSign`. Python 3.13 (et urllib3 2, qui reproduit son comportement) active `VERIFY_X509_STRICT` ; `curl` non. L'autorité générée par `pve-cluster` n'avait pas cette extension (bogue Proxmox n° 6701, correctif en revue début 2026, qui ne régénère pas les autorités existantes).

   **Correction retenue : une ancre de confiance conforme, même clé, même sujet.** Sur `pve01`, on fabrique un certificat auto-signé avec la **même clé** et le **même sujet** que l'autorité, en y ajoutant les extensions conformes ; rien ne change sur `pve01`, seul le certificat public voyage :
   ```
   root@pve01:~# printf '%s\n' 'basicConstraints=critical,CA:true' 'keyUsage=critical,keyCertSign,cRLSign' 'subjectKeyIdentifier=hash' > /root/ku.ext
   root@pve01:~# openssl x509 -in /etc/pve/pve-root-ca.pem -signkey /etc/pve/priv/pve-root-ca.key \
                   -clrext -extfile /root/ku.ext -days 3650 -out /root/pve-root-ca-ku.pem
   root@pve01:~# openssl verify -x509_strict -CAfile /root/pve-root-ca-ku.pem /etc/pve/local/pve-ssl.pem
   /etc/pve/local/pve-ssl.pem: OK
   root@pve01:~# rm /root/ku.ext
   admin@adm01:~$ scp pve01:/root/pve-root-ca-ku.pem ~/.config/workbook/pve-root-ca.pem && chmod 600 ~/.config/workbook/pve-root-ca.pem
   ```
   Pourquoi ça marche : la validation d'une chaîne vérifie que le certificat du serveur est signé par la **clé** de l'ancre et que l'émetteur correspond au **sujet** de l'ancre (et à son identifiant de clé, calculé sur la même clé). Une nouvelle ancre avec la même clé et le même sujet valide donc le certificat existant de `pve01`. `curl`, M00-E17 et les vérifications continuent de fonctionner avec ce fichier. Limites : à refaire si l'autorité de `pve01` est régénérée ; c'est une ancre **locale** à `adm01` (et à `runner01` si un jour il parle à Proxmox) ; au module 06, `pve01` recevra un certificat émis par step-ca et ce contournement disparaîtra. Si l'erreur stricte suivante porte sur le certificat du **nœud** (« Missing Authority Key Identifier », certificat produit par une très ancienne version d'OpenSSL), c'est lui qu'il faudrait régénérer (`pvecm updatecerts --force`), opération qui touche l'interface web : ⚠️ à vérifier sur ta version, et à planifier.

   Alternative acceptable si tu ne veux pas toucher à l'ancre : un `ssl.SSLContext` créé par `ssl.create_default_context(cafile=…)` dont on retire uniquement `ssl.VERIFY_X509_STRICT`, monté sur la session par un adaptateur `requests` : la chaîne et le nom restent vérifiés, seule la conformité RFC 5280 est relâchée. Moins propre (code spécifique, accès à la session interne de proxmoxer), à documenter.

3. **Le module** : [`fichiers/M02-E08/pve.py`](fichiers/M02-E08/pve.py), à placer dans `src/medictl/pve.py`. Points clés :
   - `PveConfig` est une `dataclass(frozen=True)` ; `token_secret: str = field(repr=False)` l'exclut de `repr()` (donc des traces de débogage et des journaux qui affichent l'objet) ;
   - `lire_fichier_env()` analyse le fichier ligne par ligne (`CLE=valeur`, `export` facultatif, guillemets doubles avec `os.path.expandvars`, apostrophes sans développement, commentaire de fin de ligne), sans jamais l'exécuter : un fichier de configuration piégé ne peut pas exécuter de code ;
   - `charger_config()` choisit le fichier (argument, `MEDICTL_ENV_FILE`, défaut), signale les variables **manquantes par leur nom**, valide l'URL (`https`, `/api2/json`), la forme du jeton (`utilisateur@domaine!jeton`) et l'existence de l'autorité ; ses messages ne contiennent jamais de valeur ;
   - `connexion()` découpe l'URL (`urllib.parse`) en hôte et port, le jeton en utilisateur et nom, et passe `verify_ssl=str(cfg.cacert)` : dans proxmoxer 2.3, `verify_ssl` est transmis tel quel au paramètre `verify` de `requests`, qui accepte un chemin d'autorité. Délai par défaut de proxmoxer : 5 s ; on le fixe explicitement (10 s).

4. **proxmoxer** : [`fichiers/M02-E08/essai_proxmoxer.py`](fichiers/M02-E08/essai_proxmoxer.py).
   ```
   admin@adm01:~/src/outils$ uv run python ~/m02/e08/essai_proxmoxer.py
   configuration lue : PveConfig(api_url='https://192.168.1.20:8006/api2/json', node='pve01', token_id='wb-automation@pve!lab', cacert=PosixPath('/home/admin/.config/workbook/pve-root-ca.pem'))
   Proxmox VE 9.0.10
    1000  gw01                 running
    1001  adm01                running
   …
   refus de l'API : 403 Forbidden: Permission check failed (/nodes/pve01, Sys.Audit) - {'errors': b''}
   ```
   proxmoxer lève `proxmoxer.core.ResourceException`, avec `status_code`, `status_message` et `content` (le motif de Proxmox). Les erreurs réseau et TLS restent celles de `requests` (`ConnectionError`, `SSLError`, `Timeout`).

5. **Échecs provoqués** :

   | Cas | Exception | Ce qu'elle affiche |
   |---|---|---|
   | Autorité étrangère | `requests.exceptions.SSLError` | `certificate verify failed: unable to get local issuer certificate` |
   | Secret faux | `ResourceException` 401 | `401 Unauthorized: authentication failure` |
   | Nom absent du certificat | `SSLError` | `Hostname mismatch, certificate is not valid for '…'` |
   | Port fermé | `requests.exceptions.ConnectionError` | `… Connection refused` (ou délai dépassé si filtré) |

   Dans aucun cas le secret n'apparaît : les exceptions de `requests` contiennent l'URL, jamais les en-têtes ; `repr(cfg)` l'omet. Un `logging` en niveau DEBUG de `urllib3` n'affiche pas non plus les en-têtes. Le risque reste l'affichage explicite d'un objet session ou d'un dictionnaire d'en-têtes : c'est à la revue de code de l'interdire.

6. **ruff** : S501 (`requests` avec `verify=False`), S113 (requête sans `timeout`), S105/S106 (secret en dur) ; S323 pour un contexte SSL non vérifié (`ssl._create_unverified_context`).

7. **Réponse au ticket** (dans la MR) : « Jeton `wb-automation@pve!lab` uniquement ; secret lu dans `~/.config/workbook/pve-api.env` (600), jamais en argument ni affiché (`repr=False`, messages sans valeur) ; vérification TLS complète (chaîne et nom) contre l'autorité de `pve01`, rendue conforme RFC 5280 côté client (même clé, même sujet), aucune option de désactivation dans le code ; délai de 10 s ; erreurs typées (`ConfigError`, `SSLError`, `ResourceException`). »

**Explications**

- **Pourquoi ne pas `source` le fichier** : exécuter un fichier de configuration, c'est exécuter du code. Un lecteur dédié limite le format à ce qui est attendu et produit des erreurs précises.
- **`frozen=True`** : la configuration ne change pas après son chargement ; les modifications volontaires passent par `dataclasses.replace()` (c'est ce que fait la vérification pour tester une autre autorité).
- **Vérification stricte** : elle protège contre des autorités mal formées qui pourraient signer ce qu'elles ne devraient pas ; le refus de Python 3.13 est une bonne nouvelle, pas un obstacle.

**Alternatives**

- `httpx` à la place de `requests`, ou le client HTTP de la bibliothèque standard : même logique, autres API.
- Faire confiance à l'autorité au niveau du système (`/usr/local/share/ca-certificates/`, `update-ca-certificates`, comme la PKI provisoire au M01) et laisser `verify_ssl=True` avec `REQUESTS_CA_BUNDLE` pointant sur le magasin système : pratique pour plusieurs outils, mais toute la machine fait alors confiance à cette autorité.
- Épinglage de l'empreinte du certificat (comme `PBS_FINGERPRINT`) : robuste, mais à mettre à jour à chaque renouvellement du certificat du nœud.

**Pièges classiques**

- `verify=False` « le temps de comprendre » : il reste, et le jeton part en clair vers quiconque s'interpose.
- `session.verify = chemin` avec `REQUESTS_CA_BUNDLE` défini dans l'environnement (fréquent derrière un proxy d'entreprise) : la session ignore l'autorité voulue.
- Passer l'URL complète à `ProxmoxAPI(host=…)` : proxmoxer attend un nom d'hôte (et éventuellement `:port`), pas `https://…/api2/json`.
- `user="wb-automation@pve!lab"` : le nom du jeton va dans `token_name`, l'utilisateur seul dans `user`.
- `PVE_CACERT="$HOME/…"` lu sans développement de `$HOME` : fichier introuvable.
- Régénérer l'autorité de `pve01` pour « corriger » : tous les clients existants (navigateurs, PBS, scripts, M00-E17) cessent de lui faire confiance.

**En production chez MédiSphère**

- Certificats d'hyperviseur émis par la PKI interne (step-ca, module 06), conformes RFC 5280, renouvelés automatiquement ; ancre de confiance distribuée par Ansible.
- Secret délivré par Vault/OpenBao (module 25) au lancement de l'outil, jamais stocké sur le poste.
- Un test automatique (E18) vérifie qu'une autorité étrangère est refusée : une régression qui désactiverait la vérification casserait la CI.

---

### M02-E09 — Questions : Bash ou Python ?

**Barème** : 2 points par question, total sur 28. Les réponses ci-dessous sont des positions argumentées : une réponse différente mais justifiée par les mêmes critères vaut les points.

**1.** (a) **Bash** : enchaînement de commandes système (`chronyc tracking`, `systemctl restart`) sur quelques hôtes, peu de données ; à terme, Ansible (question 10). (b) **Python** : appel d'API, regroupements, totaux, génération de Markdown : manipulation de données, à tester (c'est l'E21). (c) **Bash**, et très court (`mountpoint -q /srv/donnees`) : systemd l'exécute à chaque démarrage, aucune dépendance acceptable. (d) **Python** (Typer) : sous-commandes, validation, garde-fous, tests : c'est `medictl`. (e) **ni l'un ni l'autre d'abord** : `awk '{print $1}' access.log | sort | uniq -c | sort -rn | head` (ou `awk` seul avec un tableau associatif) ; les outils en flux traitent 2 Go en quelques secondes avec une mémoire constante. Python convient si le traitement se complique.

**2. Signaux de réécriture** : structures de données (tableaux associatifs, JSON construit à la main) ; logique de gestion d'erreurs fine (plusieurs cas, reprises) ; appels HTTP/API au-delà de quelques `curl` ; fonctions longues et nombreuses (au-delà de 150 à 200 lignes au total) ; besoin de tests unitaires ; traitement de dates, d'encodages ; réutilisation par d'autres outils (bibliothèque). Dans `ms-collecte-config` : la gestion d'erreurs par hôte et la validation d'archive commencent à peser, mais le cœur reste un enchaînement de commandes (`ssh`, `tar`, `gzip`, `mv`) : Bash reste un bon choix.

**3. Réponse B.** `jq` est conçu pour cela, rapide, et des filtres versionnés se testent (E05). A est faux : `grep`/`sed` sur du JSON cassent au premier changement de mise en forme. C est faux : un processus Python par champ, lent et illisible. D est excessif : un peu de JSON ne justifie pas une réécriture ; c'est l'accumulation des signaux de la question 2 qui le justifie.

**4. Erreurs.** Bash : par défaut, une erreur **n'arrête rien** ; `set -e` aide mais a des exceptions nombreuses (conditions, `&&`/`||`, substitutions en argument, `local`), et les codes retour se perdent facilement (tubes, sous-shells). Python : une erreur non traitée **arrête** le programme avec une trace (plus sûr par défaut), mais un `except Exception: pass` peut tout masquer. Dans les deux : décider quelles erreurs sont attendues, les traiter explicitement avec un message clair, laisser remonter les autres, choisir le code de sortie.

**5. Sans rien installer.** Bibliothèque standard seule (`urllib.request`, `json`, `argparse`) : rien à déployer, mais plus de code et pas de bibliothèques confortables. Script PEP 723 avec `uv run` : dépendances déclarées dans le script, environnement créé à la volée, mais il faut `uv` sur l'hôte et un accès à l'index (ou un cache). Paquet installé par `uv tool install` : propre, versionné (E25), mais c'est une installation. Binaire autonome (PyInstaller, ou un autre langage) : un seul fichier, mais lourd à construire et à mettre à jour, et dépendant de la glibc. Pour les VMs du socle : stdlib pour les petits contrôles, sinon déploiement par Ansible d'un paquet versionné.

**6. bats et pytest.** bats teste un script **de l'extérieur** : arguments, codes retour, sorties, fichiers produits ; les commandes externes s'isolent par des faux programmes placés en tête du `PATH` (comme `ssh` dans la vérification d'E03). Difficile : les interactions réseau et `sudo`, la concurrence. pytest teste aussi l'**intérieur** (fonctions) ; les appels externes s'isolent par simulation (`responses` pour HTTP, `monkeypatch` pour l'environnement, `tmp_path` pour les fichiers). Difficile : ce qui dépend du vrai comportement de Proxmox (tâches asynchrones, verrous), qu'on simule par des réponses enregistrées.

**7. Réponse C.** Des tests de comportement d'abord figent ce que fait le script (y compris ses bizarreries utiles) ; la réécriture est alors vérifiable. A est faux : ShellCheck ne dit rien de la maintenabilité. B est risqué : une réécriture sans filet change des comportements dont dépend quelqu'un. D déplace le problème : le JSON et les tableaux associatifs restent du Bash fragile.

**8. Injections.** Bash : une donnée non protégée est découpée et développée (jokers) ; dans `ssh hote "cmd $donnee"` ou `eval`, elle est **exécutée** par un shell. Parade : guillemets partout, `--` avant les noms, tableaux d'arguments, `printf %q` pour une commande distante, validation par expression rationnelle, jamais d'`eval`. Python : `shell=True` avec une f-string, `os.system`, construction de commandes SSH en chaîne ; parade : `subprocess.run([...])` avec une liste, `shlex.quote` pour une commande distante, validation des entrées. Dans les deux cas : une donnée externe ne devient jamais du code.

**9. Performance.** Chaque `$(jq …)`, `grep`, `date` dans la boucle crée un processus (fork + exec, quelques millisecondes) : 10 000 itérations × 3 commandes = 30 000 processus. Mesure : `time`, ou `strace -c -f` pour compter les `execve`. Corrections : traiter tout le flux en **une** commande (`jq` sur tout le document, `awk` sur tout le fichier) ; ou utiliser les capacités internes de Bash (`printf '%(%F)T'`, expansions `${…}`, `[[ =~ ]]`) au lieu de commandes externes. C'est la panne E40.

**10. Ni Bash ni Python.** **Ansible** quand on décrit l'**état** de configuration de machines, à rendre idempotent et répétable : installer les outils du module sur `adm01` et `runner01` (versions, empreintes) ; configurer `chrony` ou `dnsmasq` sur les VMs du socle. **OpenTofu** quand on décrit l'**existence** de ressources et leur cycle de vie, avec un état : créer les VMs d'un environnement de module ; gérer les projets, protections et variables GitLab (provider GitLab). Les scripts restent pour le diagnostic, les gestes ponctuels et la colle entre outils.

**11. Interpréteurs.** `#!/usr/bin/env bash` : nos scripts utilisent des fonctionnalités de Bash (`[[ ]]`, tableaux) ; `env` trouve `bash` dans le `PATH`. `#!/bin/sh` seulement pour des scripts réellement POSIX (testés avec `dash`, `checkbashisms`). Python : pas de script lancé directement dans `plateforme/outils` ; `medictl` est un paquet dont le point d'entrée est généré par l'installateur avec le bon interpréteur (celui de l'environnement). Un `#!/usr/bin/env python3` ne prendrait pas l'environnement du projet.

**12. Mêmes règles** : `.editorconfig` commun ; ShellCheck + shfmt pour Bash, ruff (lint + formatage) pour Python ; configuration versionnée à la racine (`.shellcheckrc`, `pyproject.toml`) ; appliquées au même endroit trois fois : éditeur, pre-commit (versions épinglées), CI obligatoire (E24) ; tests bats et pytest en CI ; même convention de codes retour et de sorties, vérifiée en revue (CONTRIBUTING).

**13. Go.** Pour : binaire statique unique (distribution triviale, pas d'environnement Python), performances, typage, bonnes bibliothèques (le provider Terraform `bpg/proxmox` est en Go). Contre, pour l'équipe actuelle : personne ne le pratique couramment, Python est déjà requis par Ansible (module 04), les tests et l'itération sont plus lents à écrire, et `uv tool install` règle l'essentiel du problème de distribution. Décision raisonnable : Python maintenant, réévaluation si la distribution devient un vrai frein (ADR).

**14. Règle proposée** (exemple) : « Bash pour enchaîner des commandes système, sans structures de données ni appels d'API au-delà de quelques `curl` + `jq`, et sous 200 lignes. Python (projet uv, `medictl` ou paquet dédié) dès qu'il y a des données structurées, une API, des erreurs à distinguer, ou des tests unitaires à écrire. `jq`/`awk` pour le traitement de flux. Ansible pour l'état d'une machine, OpenTofu pour l'existence d'une ressource. Dans tous les cas : ShellCheck/ruff, tests en CI, codes retour 0/1/2/3, aucun secret en argument. Un script Bash qui accumule les signaux de réécriture est d'abord couvert par des tests bats, puis réécrit. »

**Grille d'auto-évaluation**

| Score /28 | Lecture |
|---|---|
| 22 à 28 | Tu sais choisir et argumenter : l'ADR-0020 (E32) sera rapide. |
| 14 à 21 | Critères justes mais incomplets : relis les questions 2, 4 et 10 avant E32. |
| Moins de 14 | Refais ce questionnaire après le palier 2 (bibliothèque Bash, `medictl`), qui donne la matière concrète. |
