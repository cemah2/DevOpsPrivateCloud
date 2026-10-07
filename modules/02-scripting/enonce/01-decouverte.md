# Module 02 — Palier 1 : Découverte

Karim veut d'abord savoir où tu en es en Bash et en Python. Ensuite, tu ouvres le projet `plateforme/outils` avec la configuration standard de la forge, tu écris un premier script qui échoue proprement, tu installes les garde-fous d'analyse statique, tu apprends à interroger et à modifier du JSON et du YAML sans les casser, puis tu poses les fondations Python de `medictl` : un environnement reproductible géré par uv et un premier client de l'API Proxmox qui vérifie vraiment les certificats. Le palier se termine par une réflexion argumentée : Bash ou Python, quand et pourquoi.

Prérequis : module 01 terminé (forge `git01`, `runner01`, gabarits `plateforme/ci-templates` en `v1`, pre-commit sur `adm01`), outils du module installés sur `adm01` (voir [`00-introduction.md`](00-introduction.md), section « Préparer `adm01` »).

---

### M02-E01 — Test de positionnement : Bash et Python  `Q` `★★`

> **Ticket PLAT-301** — *De : Karim Benali*
> Même rituel qu'au module 00 : avant d'écrire des outils d'astreinte, je veux savoir sur quoi t'épauler. Bash et Python, par écrit, sans moteur de recherche ni IA, sans exécuter de code. 1 h 30 maximum, puis tu te corriges avec la grille.

**Objectifs pédagogiques**
- Évaluer tes acquis en Bash (expansions, erreurs, redirections, processus) et en Python (environnements, exceptions, HTTP, sous-processus).
- Repérer les notions à travailler avant les exercices qui les mobilisent.

**Prérequis** : aucun.
**Durée indicative** : 1 h 30 (+ 30 min d'auto-correction).

**Travail demandé**

Réponds aux 25 questions. Pour les QCM, justifie ton choix en une ou deux phrases.

*Bash*

1. Avec `set -- "un deux" trois`, qu'affichent `printf '[%s]\n' "$@"`, `printf '[%s]\n' $*` et `printf '[%s]\n' "$*"` ? Lequel utiliser pour transmettre ses arguments à une autre commande, et pourquoi ?

2. *(QCM, plusieurs réponses possibles)* Dans un script en `set -euo pipefail`, la commande `false` échoue. Dans quels cas le script s'arrête-t-il **à cette ligne** ?
   - A. `false || echo "raté"`
   - B. `if false; then echo oui; fi`
   - C. `resultat=$(false)`
   - D. `false | cat`
   - E. Dans une fonction `f() { false; echo suite; }` appelée par `if f; then …`

3. `f="rapport du 3 octobre *.txt"`, puis `rm $f`. Que se passe-t-il exactement, étape par étape ? Qu'aurait-il fallu écrire ?

4. Donne quatre différences concrètes entre `[ … ]` et `[[ … ]]` en Bash.

5. Pour `chemin=/var/log/app/journal.log.gz`, donne la valeur de `${chemin##*/}`, `${chemin%/*}`, `${chemin%.*}`, `${chemin%%.*}`, `${#chemin}`. Que font `${VAR:-defaut}`, `${VAR:=defaut}` et `${VAR:?message}` ?

6. Explique la différence entre `cmd >sortie.log 2>&1` et `cmd 2>&1 >sortie.log`. Où partent les erreurs dans chaque cas ?

7. Ce fragment affiche toujours `total : 0`. Pourquoi ? Donne deux corrections.
   ```bash
   total=0
   df -P | tail -n +2 | while read -r _ _ _ _ pct _; do
     total=$((total + ${pct%\%}))
   done
   echo "total : $total"
   ```

8. Quand le code d'un `trap … EXIT` s'exécute-t-il ? Et après un `kill -TERM` ? un `kill -KILL` ? un Ctrl-C ? Que se passe-t-il si le script attend une commande longue au moment où il reçoit SIGTERM ?

9. Que signifient les codes de sortie 1, 2, 126, 127, 130, 137 et 143 ? Comment obtiens-tu le code de chaque commande d'un tube ?

10. *(QCM)* Pourquoi ShellCheck signale-t-il `local reponse=$(curl -sf "$url")` (SC2155) ?
    - A. `local` est interdit hors d'une fonction
    - B. Le code retour de `curl` est remplacé par celui de `local`, toujours 0
    - C. La variable n'est pas protégée par des guillemets
    - D. `curl` doit être appelé avec `command`

11. Tu dois appeler `ssh` avec des options qui dépendent du contexte (clé, port, `-o BatchMode=yes` seulement en mode non interactif). Comment construis-tu la liste d'arguments sans risque de découpage ?

12. `find /srv/exports -name '*.csv' -mtime +30 | xargs rm` : quels noms de fichiers posent problème ? Donne deux formes correctes.

13. Qu'est-ce qu'une substitution de processus `<( … )` ? Donne un usage où elle évite un fichier temporaire.

14. Dans un script lancé par `cron` ou par systemd, cite trois différences d'environnement avec ton terminal qui font échouer des scripts « qui marchent à la main ».

15. Trouve au moins quatre défauts dans ce fragment, et dis ce qui se passe si `$1` est vide.
    ```bash
    #!/bin/bash
    DIR=$1
    cd $DIR
    rm -rf $DIR/tmp/*
    for f in `ls *.log`; do gzip $f; done
    ```

*Python*

16. Sur Debian 13, `sudo pip install requests` répond `error: externally-managed-environment`. Pourquoi ? Quelles sont les bonnes façons d'installer une dépendance pour un outil, et pour un projet ?

17. Quel est le rôle respectif de `pyproject.toml`, d'un fichier de verrouillage (`uv.lock`) et d'un environnement virtuel (`.venv/`) ? Lequel versionne-t-on ?

18. *(QCM)* `requests.get(url)` sans paramètre `timeout`, vers un serveur qui accepte la connexion mais ne répond jamais :
    - A. lève une exception au bout de 30 s
    - B. lève une exception au bout de 5 s
    - C. peut attendre indéfiniment
    - D. réessaie trois fois puis abandonne

19. Différence entre `except:`, `except Exception:` et `except requests.exceptions.ConnectionError:` ? Que fait `raise MonErreur(…) from exc`, et pourquoi est-ce utile dans un outil ?

20. Que signifie `if __name__ == "__main__":` ? Comment une commande `medictl` installée par un paquet trouve-t-elle la fonction à exécuter ?

21. Qu'affiche ce code, et pourquoi ?
    ```python
    def ajouter(vm, liste=[]):
        liste.append(vm)
        return liste

    print(ajouter(2021)); print(ajouter(2022))
    ```

22. `subprocess.run(f"ssh {hote} uptime", shell=True)` avec `hote` lu dans un fichier : quel risque ? Écris l'appel correct, qui lève une exception si la commande échoue et récupère sa sortie en texte.

23. Une réponse d'API JSON contient parfois la clé `tags`, parfois non. Compare `vm["tags"]`, `vm.get("tags")` et `vm.get("tags", "")`. Laquelle choisir, et quand faut-il au contraire échouer ?

24. Pourquoi un outil d'exploitation utilise-t-il le module `logging` plutôt que `print` pour ses messages ? Sur quel flux doivent-ils partir ? Que ne doit-on jamais y écrire ?

25. Comment un programme Python indique-t-il un échec au shell qui l'a lancé ? Que vaut `$?` après une exception non rattrapée ? Après `sys.exit("message")` ?

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 25 questions avant d'ouvrir le corrigé.
- [ ] Tu as noté chaque réponse avec la grille (0, 1 ou 2 points) et calculé ton score sur 50.
- [ ] Tu as noté les thèmes à retravailler et les exercices du module qui les mobilisent.

<details><summary>Indice 1</summary>

Pour les questions de Bash, raisonne dans l'ordre des expansions du shell : accolades, tilde, paramètres et variables, substitutions de commande, arithmétique, découpage en mots, développement des noms de fichiers, retrait des guillemets. La plupart des pièges viennent des deux avant-dernières étapes.
</details>

<details><summary>Indice 2</summary>

Pour `set -e`, demande-toi si l'échec de la commande est « attendu » par le code qui l'entoure (une condition, un opérande de `&&` ou `||`). Si oui, Bash considère que l'erreur est gérée.
</details>

**Pour aller plus loin** (facultatif) : refais ce test à la fin du module (E46), sans relire le corrigé, et compare.

---

### M02-E02 — Créer le projet `plateforme/outils`  `LAB` `★`

> **Ticket PLAT-302** — *De : Karim Benali*
> Crée le projet `plateforme/outils` avec exactement la même configuration que `plateforme/medisphere` : même protection de `main`, mêmes hooks, mêmes gabarits CI, même release automatique. Pas de passe-droit parce que « c'est juste des scripts » : ces scripts toucheront la production. Toute la configuration initiale passe déjà par une MR.

**Objectifs pédagogiques**
- Appliquer la configuration standard d'un projet de la plateforme, sans en oublier un élément.
- Identifier ce qui se copie d'un projet à l'autre et ce qui se partage (gabarits inclus) pour éviter les divergences.
- Pratiquer le cycle complet : branche, commit conventionnel, MR, pipeline, fusion.

**Prérequis** : M01-E11 (règles de `main`), M01-E15 (pre-commit), M01-E24 et E25 (gabarits `qualite.yml` et `release.yml`, jeton `bot-release`), M01-E22 (CONTRIBUTING et modèle de MR).
**Durée indicative** : 1 h 30.

**Contexte technique**
- Projet : `plateforme/outils`, privé, branche par défaut `main`. Clone de travail : `~/src/outils` sur `adm01` (en SSH : `git@git01.par1.medisphere.internal:plateforme/outils.git`).
- Référence : ta copie de `plateforme/medisphere` (`~/medisphere`), configurée au module 01.
- Configuration standard (module 01) : méthode de fusion choisie en M01-E11 (historique semi-linéaire ou *fast-forward*), pipeline réussi et discussions résolues obligatoires, `main` protégée (push : personne ; fusion : Maintainers ; pas de poussée forcée), étiquettes `v*` protégées, jeton d'accès de projet `bot-release` (Maintainer, portées `api` et `write_repository`) dans la variable CI `GITLAB_TOKEN` protégée et masquée.
- Fichiers attendus sur `main` après la MR : `README.md`, `.gitignore`, `.gitlab-ci.yml`, `.pre-commit-config.yaml`, `commitlint.config.mjs`, `.releaserc.json`, `CONTRIBUTING.md`, `.gitlab/merge_request_templates/Default.md`.
- `.gitlab-ci.yml` : inclusion de `templates/qualite.yml` et `templates/release.yml` du projet `plateforme/ci-templates`, référence `v1`. Les jobs propres au projet viendront en E24.
- `.gitignore` : prévois dès maintenant ce que produira un projet Python (environnement virtuel, caches, `dist/`) et un filet contre les fichiers de secrets (`*.env`).

**Travail demandé**
1. Crée le projet dans le groupe `plateforme`, initialisé avec un `README.md` (case « Initialize repository with a README ») : ainsi `main` existe sans que tu y pousses quoi que ce soit.
2. Applique la configuration standard (réglages de fusion, protections, étiquettes, jeton `bot-release`, variable `GITLAB_TOKEN`). Note dans ton journal chaque réglage et l'endroit où il se trouve dans l'interface (ou le point d'API correspondant). Lesquels pourrais-tu définir une fois pour toutes au niveau du groupe `plateforme` dans GitLab CE ?
3. Clone le projet dans `~/src/outils` et crée une branche `chore/configuration-initiale`.
4. Ajoute les fichiers attendus. Pour chacun, décide s'il se **copie à l'identique** depuis `~/medisphere`, s'il s'**adapte**, ou s'il s'**écrit**. Note ta décision dans le journal. Pourquoi `.gitlab-ci.yml` n'a-t-il presque rien à contenir ?
5. Installe les hooks (`pre-commit install`), puis `pre-commit run --all-files`. Corrige ce qui doit l'être.
6. Commite avec un message conforme (Conventional Commits), pousse, ouvre la MR avec le modèle. Attends le pipeline.
7. Fusionne la MR une fois le pipeline vert (dans la vraie vie, Karim relirait). Observe le pipeline de `main` : que fait le job de release, et pourquoi ne publie-t-il aucune version ?
8. Réfléchis, dans ton journal : dans six mois, `plateforme/medisphere` aura fait évoluer son `.pre-commit-config.yaml`. Comment éviter que les projets divergent sans que personne ne s'en rende compte ?

**Critères de réussite**
- [ ] Le projet `plateforme/outils` est privé, sur `main`, avec les réglages de fusion de l'équipe.
- [ ] `main` est protégée (aucune poussée directe, fusion par les Maintainers, poussée forcée interdite) ; les étiquettes `v*` sont protégées.
- [ ] Le jeton `bot-release` est actif et `GITLAB_TOKEN` est une variable protégée et masquée.
- [ ] `main` contient les huit fichiers attendus ; `.gitlab-ci.yml` inclut les gabarits en `v1`.
- [ ] Au moins une MR a été fusionnée et le dernier pipeline de `main` est vert.
- [ ] `~/src/outils` est un clone dont `origin` pointe vers `git01`, avec les hooks `pre-commit` et `commit-msg` installés.

**Vérification** : `lab/bin/check 02 02`

<details><summary>Indice 1</summary>

Compare les réglages de `plateforme/medisphere` (Settings → Repository, Settings → Merge requests, Settings → CI/CD, Settings → Access tokens) avec ceux du nouveau projet, page par page. L'API donne la même chose plus vite : `GET /projects/:id`, `GET /projects/:id/protected_branches`, `GET /projects/:id/protected_tags`.
</details>

<details><summary>Indice 2</summary>

GitLab protège automatiquement la branche par défaut d'un nouveau projet avec les réglages par défaut de l'instance, qui ne sont pas forcément ceux de l'équipe. Regarde ce qui est déjà protégé avant d'ajouter une règle.
</details>

<details><summary>Indice 3</summary>

Si le pipeline de la MR ne démarre pas ou reste « pending », vérifie l'étiquette des jobs (les gabarits ciblent le runner `shell`) et que `runner01` est en ligne. Si le job de release échoue sur `main`, relis la configuration de `GITLAB_TOKEN` : une variable **protégée** n'est visible que des pipelines de branches et d'étiquettes protégées.
</details>

**Pour aller plus loin** (facultatif) : écris un script qui applique toute la configuration standard par l'API GitLab (idempotent : rejouable sans effet de bord), pour les projets des modules 03 à 05.

---

### M02-E03 — Un script Bash robuste : mode strict, `trap`, codes retour, usage  `LAB` `★`

> **Ticket PLAT-303** — *De : Nadia Roussel* — *Copie : Karim Benali*
> Avant chaque intervention, l'astreinte doit pouvoir prendre une « photo » de la configuration des machines du socle. Le script de Lucas a produit la semaine dernière une archive **vide** pour `gw01` (il était injoignable) et a quand même affiché « terminé ». On a cru avoir une sauvegarde, on n'avait rien. Je veux un outil qui dit la vérité : ce qui a marché, ce qui a échoué, et un code retour exploitable.

**Objectifs pédagogiques**
- Écrire un script Bash qui échoue tôt et clairement : mode strict, codes retour, messages sur la sortie d'erreur.
- Comprendre les limites de `set -e` et vérifier explicitement ce qui compte.
- Gérer proprement les fichiers temporaires et les interruptions avec `trap`.
- Donner à un script une interface d'outil : aide, analyse des arguments, garde-fous.

**Prérequis** : M02-E02.
**Durée indicative** : 2 h.

**Contexte technique**

Contrat de l'outil (les vérifications s'y fient) :

| Élément | Exigence |
|---|---|
| Fichier | `bin/ms-collecte-config` dans `plateforme/outils`, exécutable, première ligne `#!/usr/bin/env bash` |
| Usage | `ms-collecte-config [-o DOSSIER] HÔTE...` ; `-h` / `--help` affiche une aide qui commence par `Usage` |
| Hôtes | alias SSH de `adm01` (`gw01`, `dns01`, `git01`, `runner01`…) ; lecture des fichiers avec `sudo -n` ; un nom qui commence par `-` est refusé (erreur d'usage, code 2) |
| Fichiers collectés | `etc/hostname etc/hosts etc/resolv.conf etc/network/interfaces etc/network/interfaces.d etc/nftables.conf etc/dnsmasq.d etc/chrony etc/wireguard etc/ssh/sshd_config etc/ssh/sshd_config.d etc/sudoers.d etc/systemd/system etc/gitlab/gitlab.rb etc/gitlab-runner/config.toml` (chemins relatifs à `/` ; les absents sont ignorés) |
| Archive | une par hôte : `DOSSIER/<HÔTE>-AAAAMMJJ-HHMMSS.tar.gz`, mode 600 ; `DOSSIER` vaut `~/collectes` par défaut et est créé en 700 s'il manque |
| Sorties | sortie standard : le chemin de chaque archive créée, une par ligne, **rien d'autre** ; tous les messages sur la sortie d'erreur |
| Codes retour | `0` tous les hôtes collectés ; `1` au moins un hôte en échec (les autres sont tout de même collectés) ; `2` usage ; `3` refus : `DOSSIER` se trouve dans un dépôt Git |
| Atomicité | jamais d'archive partielle ou vide sous son nom final, jamais de fichier temporaire laissé derrière, même après Ctrl-C |

Les archives contiennent des secrets (clés privées WireGuard de `gw01`, jeton du runner) : d'où le mode 600 et le refus d'écrire dans une copie de travail Git.

**Travail demandé**
1. Sur une branche `feat/ms-collecte-config`, commence par l'aide (`usage`) et l'analyse des arguments, avant toute logique. Choisis entre `getopts` et une boucle `while`/`case` ; note ton choix et ce qu'il permet (options longues ? `--` ?).
2. Active le mode strict (`set -Eeuo pipefail`). Écris dans ton journal ce que fait chacune des quatre options, avec un exemple de bogue que chacune évite.
3. Écris la collecte d'un hôte : `ssh` exécute `sudo -n tar` à distance et envoie l'archive non compressée sur sa sortie, que tu compresses localement avec `gzip`. Expérience : lance ta commande vers un hôte inexistant, **sans** `pipefail`, et regarde le code retour et le fichier produit. Puis avec. Note le résultat.
4. Rends l'écriture atomique : fichier temporaire, contrôle de l'archive (lisible, et contenant au moins `etc/hostname`), puis renommage. Où créer le fichier temporaire pour que le renommage soit atomique ?
5. Ajoute le nettoyage par `trap … EXIT`, un message utile sur erreur inattendue (`trap … ERR`, avec la ligne et la commande), et le traitement de `INT` et `TERM`. Teste : interromps une collecte avec Ctrl-C, puis avec `kill -TERM <PID>` depuis un autre terminal. Combien de temps le script met-il à réagir à `TERM`, et pourquoi ?
6. Fais en sorte qu'un hôte en échec n'empêche pas la collecte des autres, et que le code final le signale. Question pour le journal : si tu appelles ta fonction de collecte dans `if collecter "$h"; then`, que devient `set -e` **à l'intérieur** de la fonction ? Quelle conséquence sur ta façon d'écrire cette fonction ?
7. Ajoute le garde-fou (code 3) : la décision doit être prise **avant** de créer quoi que ce soit.
8. `shellcheck bin/ms-collecte-config` doit être muet. Teste tous les codes retour à la main, puis collecte `gw01 dns01 git01 runner01` pour de vrai et inspecte une archive (`tar -tzvf`).
9. Commit conventionnel, MR, pipeline vert, fusion.

**Critères de réussite**
- [ ] `ms-collecte-config --help` affiche l'aide et sort en 0 ; sans argument ou avec une option inconnue, il sort en 2.
- [ ] La collecte de `dns01` produit une seule ligne sur la sortie standard (le chemin), une archive en mode 600 qui contient `etc/dnsmasq.d/`, et aucun fichier parasite.
- [ ] Avec un hôte injoignable parmi d'autres, le code est 1, l'échec est expliqué sur la sortie d'erreur et les autres hôtes ont leur archive.
- [ ] Une destination dans un dépôt Git est refusée (code 3) sans rien créer.
- [ ] ShellCheck ne signale rien ; le script est sur `main` par MR.

**Vérification** : `lab/bin/check 02 03`

<details><summary>Indice 1</summary>

Une commande passée à `ssh` est une **chaîne** que le shell distant réinterprète : les guillemets locaux ne protègent rien là-bas. Construis la commande distante avec `printf -v cmd '%q ' …` ou envoie un script sur l'entrée standard (`bash -s`). Pour les fichiers absents, regarde l'option `--ignore-failed-read` de GNU tar.
</details>

<details><summary>Indice 2</summary>

`mktemp -d` dans le dossier de destination donne un dossier de travail sur le même système de fichiers : `mv` y est un simple renommage, atomique. Pour savoir si un dossier est dans un dépôt Git : `git -C <dossier> rev-parse --is-inside-work-tree`. Mais le dossier n'existe peut-être pas encore…
</details>

<details><summary>Indice 3</summary>

Si ton contrôle d'archive échoue de temps en temps sans raison apparente, regarde s'il ressemble à `tar -tzf … | grep -q …` : avec `pipefail`, que se passe-t-il pour `tar` quand `grep -q` a trouvé ce qu'il cherchait et ferme le tube ?
</details>

**Pour aller plus loin** (facultatif) : ajoute une option `--liste FICHIER` pour remplacer la liste des chemins collectés, et une option `-j N` pour collecter plusieurs hôtes en parallèle (attends E28 avant de la rendre robuste).

---

### M02-E04 — ShellCheck et shfmt : lire, corriger, configurer  `LAB` `★`

> **Ticket PLAT-304** — *De : Karim Benali*
> InfoGér nous a laissé trois scripts qui tournent encore sur les anciens serveurs (purge de journaux, alerte disque, sauvegarde de configuration). On ne les déploiera pas tels quels. Passe-les à ShellCheck, comprends **chaque** remarque, corrige-les, puis installe dans `plateforme/outils` les règles qui feront que ça ne se reproduira plus : ShellCheck et shfmt, configurés une fois, appliqués partout pareil (poste, pre-commit, CI).

**Objectifs pédagogiques**
- Lire un diagnostic ShellCheck, le relier à un scénario de panne concret, et distinguer bogue, fragilité et style.
- Repérer ce que l'analyse statique ne voit pas.
- Configurer ShellCheck (`.shellcheckrc`) et shfmt (`.editorconfig`) au niveau du dépôt, et les brancher dans pre-commit.

**Prérequis** : M02-E03.
**Durée indicative** : 2 h.

**Contexte technique**
- Scripts fournis : `~/DevOpsPrivateCloud/modules/02-scripting/ressources/M02-E04/infoger/` (`purge_logs.sh`, `check_disk.sh`, `sauvegarde_config.sh`). Copie-les dans `~/m02/e04/` et travaille sur ces copies : elles ne vont **pas** dans le dépôt.
- Comportement attendu des versions corrigées : celui que le script et ses commentaires annoncent, sauf bogue manifeste (note alors ta décision). En particulier, `check_disk.sh` doit sortir avec un code **non nul** dès qu'au moins une partition dépasse le seuil.
- Versions : ShellCheck 0.11.0 et shfmt 3.14.1 sur `adm01` (voir l'introduction). Dans pre-commit : dépôts `https://github.com/shellcheck-py/shellcheck-py` (rev `v0.11.0.1`, hook `shellcheck`) et `https://github.com/scop/pre-commit-shfmt` (rev `v3.14.1-1`, hook `shfmt`).
- Style shell retenu par l'équipe : indentation de 2 espaces, `case` indentés, opérateurs binaires (`&&`, `|`) en début de ligne lors d'un retour à la ligne, dialecte `bash` (et `bats` pour les fichiers `.bats` qui arriveront en E14).

> ⚠️ **Attention** : n'exécute pas `purge_logs.sh` ni `sauvegarde_config.sh` dans leur version d'origine. Avec un argument vide ou mal choisi, le premier supprime des fichiers ailleurs que prévu ; le second écrit avec `sudo` hors de ton dossier. Raisonne sur le code ; teste seulement tes versions corrigées, dans des dossiers temporaires. `check_disk.sh` ne fait que lire : tu peux l'exécuter.

**Travail demandé**
1. Lance `shellcheck` sur les trois scripts d'origine (essaie aussi `-f gcc` et `-W 0`, et la page de wiki d'un code : `https://www.shellcheck.net/wiki/SC2164`). Dans ton journal, fais un tableau : code, ligne, catégorie (**bogue** : casse en production ; **fragilité** : casse dans un cas particulier ; **style**), et pour au moins cinq remarques, le **scénario concret** (entrées → conséquence) qui casse.
2. Trouve au moins **trois** défauts que ShellCheck ne signale pas. Indice : exécute `check_disk.sh 1` et regarde son code retour ; imagine `purge_logs.sh` lancé sans argument ; lis le message final de `sauvegarde_config.sh`.
3. Corrige les trois scripts dans `~/m02/e04/`. Contraintes : `shellcheck --norc -S style` muet ; au plus une directive `# shellcheck disable=…` par fichier, justifiée en commentaire sur la même ligne ; garde-fous ajoutés là où le script peut détruire des données. Essaie `shellcheck -f diff` pour les corrections mécaniques : qu'accepterais-tu tel quel, que refuserais-tu ?
4. Dans `~/src/outils`, sur une branche, crée `.shellcheckrc` : ShellCheck doit suivre les fichiers chargés par `source` (relatifs au script analysé) ; choisis au moins une vérification optionnelle (`shellcheck --list-optional`) et justifie-la en commentaire. Pourquoi ne pas tout activer (`enable=all`) ?
5. Crée `.editorconfig` selon le style de l'équipe, lisible par les éditeurs **et** par shfmt. Vérifie que shfmt l'applique bien à `bin/ms-collecte-config` (qui n'a pas d'extension) : `shfmt -d bin/`. Puis formate (`shfmt -w`).
6. Ajoute les hooks ShellCheck et shfmt au `.pre-commit-config.yaml`, puis `pre-commit run --all-files`. Question : le hook ShellCheck utilise-t-il le `shellcheck` installé sur `adm01` ? Quelle conséquence pour la CI sur `runner01` ?
7. MR, pipeline vert, fusion.

**Critères de réussite**
- [ ] Les trois scripts corrigés de `~/m02/e04/` passent `shellcheck --norc -S style` sans remarque, avec au plus une directive `disable` chacun.
- [ ] `check_disk.sh` corrigé sort avec un code non nul quand une partition dépasse le seuil.
- [ ] `.shellcheckrc` et `.editorconfig` sont sur `main` ; ShellCheck et shfmt sont dans pre-commit.
- [ ] Tous les scripts de `bin/` passent ShellCheck (configuration du dépôt) et `shfmt -d bin/` ne montre aucune différence.
- [ ] Ton journal contient le tableau de classement, les cinq scénarios et les défauts invisibles pour ShellCheck.

**Vérification** : `lab/bin/check 02 04`

<details><summary>Indice 1</summary>

Pour chaque remarque, pose-toi la question : « avec quelle valeur de variable, quel nom de fichier, quel état du système cette ligne fait-elle autre chose que prévu ? ». Les noms de fichiers avec espaces, les variables vides et les commandes qui échouent sans qu'on regarde sont les trois grandes familles.
</details>

<details><summary>Indice 2</summary>

shfmt n'utilise `.editorconfig` que si tu ne lui passes **aucune** option de formatage en ligne de commande. Dans `.editorconfig`, un motif qui contient un `/` est relatif au dossier du fichier ; un motif sans `/` s'applique à toute profondeur.
</details>

<details><summary>Indice 3</summary>

Dans `check_disk.sh`, cherche dans quel processus s'exécute le corps de la boucle `while` placée après un tube, et donc ce que devient la variable modifiée dedans. Dans `sauvegarde_config.sh`, regarde la première ligne : quel shell exécute vraiment ce script ?
</details>

**Pour aller plus loin** (facultatif) : passe ShellCheck sur les scripts de `~/lab-scripts/` du module 00 (`vm-api.sh`…) avec la configuration du dépôt, et sur le script `extract-checksum.sh` téléchargé avec yq. Lis l'article de wiki « Directive » de ShellCheck sur la portée des directives `disable`.

---

### M02-E05 — jq : interroger l'API Proxmox  `LAB` `★★`

> **Ticket PLAT-305** — *De : Nadia Roussel*
> En astreinte, je pose toujours les mêmes questions : quelles VMs du lab tournent, combien de mémoire elles réservent, quelles tâches Proxmox ont échoué cette nuit, quelle est l'adresse de telle VM. Aujourd'hui on clique dans l'interface. Je veux des filtres jq versionnés, testés sur des réponses enregistrées, que tout le monde utilise de la même façon. Et au passage, les étiquettes des VMs du socle ne suivent pas toutes la convention de PLAN : profites-en.

**Objectifs pédagogiques**
- Maîtriser jq : navigation, `select`, `map`, `sort_by`, `group_by`, `reduce`, valeurs par défaut, formats `@tsv`/`@sh`, paramètres `--arg`/`--argjson`.
- Écrire des filtres réutilisables (`jq -f`) et les tester sur des données enregistrées.
- Interroger l'API Proxmox réelle avec le jeton d'automatisation, sans exposer le secret.

**Prérequis** : M00-E17 (jeton `wb-automation@pve!lab`, `~/.config/workbook/pve-api.env`), M02-E02.
**Durée indicative** : 2 h.

**Contexte technique**
- Réponses d'API enregistrées : `~/DevOpsPrivateCloud/modules/02-scripting/ressources/M02-E05/` — `cluster-resources.json` (`GET /cluster/resources?type=vm`), `agent-interfaces.json` (`GET /nodes/{node}/qemu/{vmid}/agent/network-get-interfaces`), `taches.json` (`GET /nodes/{node}/tasks`) ; résultats attendus dans `attendu/`.
- Filtres à livrer dans `lib/jq/` de `plateforme/outils`, avec un commentaire d'en-tête (entrée, sortie, usage) :

| Fichier | Appel | Sortie attendue |
|---|---|---|
| `vms-lab.jq` | `jq -r -f vms-lab.jq` sur `/cluster/resources?type=vm` | une ligne par VM **QEMU** du pool `lab`, **hors templates**, triées par VMID ; champs séparés par une tabulation : VMID, nom, état, mémoire maximale en Mio (entier), étiquettes telles quelles (vide si aucune) |
| `bilan-lab.jq` | `jq -f bilan-lab.jq` sur la même réponse | un objet : `vms` (nombre de ces VMs), `en_marche` (nombre à l'état `running`), `memoire_en_marche_mio` (somme des mémoires maximales des VMs en marche, en Mio, entier), `par_etiquette` (objet étiquette → nombre de VMs), `sans_etiquette` (liste triée des VMID sans étiquette) |
| `ipv4-invite.jq` | `jq -r -f ipv4-invite.jq` sur la réponse de l'agent | les adresses IPv4 de l'invité, une par ligne, dans l'ordre de l'agent, hors interface `lo`, hors 127.0.0.0/8 et hors 169.254.0.0/16 |
| `taches-echec.jq` | `jq -r --argjson depuis <ÉPOQUE> -f taches-echec.jq` sur `/nodes/{node}/tasks` | les tâches commencées à partir de `<ÉPOQUE>` (secondes Unix), **terminées**, dont le statut n'est ni `OK` ni `WARNINGS…` ; la plus récente d'abord ; champs séparés par une tabulation : début en ISO 8601 UTC (`2026-10-03T07:20:00Z`), type, identifiant, utilisateur, statut |

- Convention d'étiquettes du socle (PLAN.md §4.8) : chaque VM permanente porte `socle` et `role-<rôle>` (`role-routeur` pour `gw01`, `role-bastion` pour `adm01`, `role-dns` pour `dns01`, `role-gitlab`, `role-runner`). Les VMs créées au module 00 portent encore d'anciennes étiquettes. Le template 9000 n'est pas concerné (module 03).
- Le jeton `wb-automation@pve!lab` possède `VM.Config.Options` sur le pool `lab` : il peut modifier les étiquettes de ces VMs par `PUT /nodes/{node}/qemu/{vmid}/config` (paramètre `tags`, valeurs séparées par `;`).

**Travail demandé**
1. Vérifie que tu utilises bien jq 1.8 (`type -a jq`, `jq --version`). Copie les réponses enregistrées dans `~/m02/e05/` et explore-les : `jq 'keys'`, `jq '.data[0]'`, `jq '.data | length'`, `jq -c '.data[] | {vmid, name, pool, type}'`. Quels champs sont **absents** (et non vides) pour certaines VMs ? Pourquoi est-ce important pour tes filtres ?
2. Écris les quatre filtres dans `~/src/outils/lib/jq/` (branche `feat/filtres-jq`), un par un, et compare au résultat attendu : `diff <(jq -r -f lib/jq/vms-lab.jq …/cluster-resources.json) …/attendu/vms-lab.tsv`. Pour `bilan-lab.jq`, compare les objets triés (`jq -S`).
3. Interroge l'API réelle depuis `adm01` : dans un sous-shell qui charge `~/.config/workbook/pve-api.env`, appelle `curl` avec `--cacert "$PVE_CACERT"` et l'en-tête d'authentification passé **par un fichier ou un descripteur** (comme en M00-E18), et enregistre la réponse de `/cluster/resources?type=vm` dans `~/m02/e05/reel.json`. Applique tes filtres. Réponds dans ton journal, chaque fois par une seule commande jq : quelle VM du lab réserve le plus de mémoire ? quelle part de la mémoire du lab est réservée par le socle ? quelles VMs du lab sont arrêtées ?
4. Produis avec jq la liste des VMs du socle (VMID 1000 à 1099) dont les étiquettes ne respectent pas la convention, puis, toujours avec jq (`@sh`, `@uri`), **génère** les commandes de correction plutôt que de les taper. Relis-les, puis applique-les par l'API avec le jeton.
   > ⚠️ **Attention** : ne modifie que le paramètre `tags`, et seulement des VMs du socle membres du pool `lab`. Note les étiquettes d'origine avant de commencer : `PUT …/config` avec `tags=<ANCIENNES>` remet l'état initial.
5. Vérifie le résultat avec `bilan-lab.jq` sur une nouvelle réponse de l'API, puis lance `taches-echec.jq` sur `GET /nodes/{node}/tasks` (tes propres tâches sont visibles avec le jeton) pour les dernières 24 heures.
6. Dans ton journal, explique : `-r` vs sortie JSON ; `jq -e` et son code retour ; `--arg` vs `--argjson` ; pourquoi `.x // "défaut"` est piégeux quand `.x` vaut `false` ; pourquoi `@sh` plutôt que de concaténer des guillemets.
7. MR, pipeline vert, fusion.

**Critères de réussite**
- [ ] Les quatre filtres sont sur `main` dans `lib/jq/` et donnent exactement les résultats attendus sur les réponses enregistrées.
- [ ] `taches-echec.jq` tient compte de `$depuis`.
- [ ] Sur l'API réelle, `vms-lab.jq` liste les VMs du lab (dont `adm01`) sans le template 9000.
- [ ] Toutes les VMs du socle portent `socle` et une étiquette `role-…`.
- [ ] Le secret du jeton n'apparaît dans aucun fichier de `~/m02/e05/`, ni dans l'historique du shell.

**Vérification** : `lab/bin/check 02 05`

<details><summary>Indice 1</summary>

Dans `/cluster/resources`, une VM hors pool n'a pas de champ `pool`, une VM sans étiquette n'a pas de champ `tags`, et `type=vm` renvoie aussi les conteneurs LXC. `select(.pool == "lab")` règle le premier cas ; `(.tags // "")` le deuxième ; regarde le champ `type` pour le troisième.
</details>

<details><summary>Indice 2</summary>

Pour compter par étiquette : éclater la chaîne (`split(";")`), aplatir la liste de toutes les étiquettes, `group_by(.)`, puis `map({key: .[0], value: length}) | from_entries`. Pour la date : `todate`. Un élément peut ne pas avoir de clé `ip-addresses` du tout : `[]?`.
</details>

<details><summary>Indice 3</summary>

Pour générer des commandes : `jq -r '… | "curl … --data-urlencode \("tags=" + $nouvelles | @sh) …"'` est fragile ; préfère construire un **tableau** d'arguments et le formater d'un coup avec `@sh`. Une tâche encore en cours n'a ni `endtime` ni `status`.
</details>

**Pour aller plus loin** (facultatif) : écris `lib/jq/vms-lab-csv.jq` qui produit un CSV avec en-tête (`@csv`), et compare les performances de `jq` et de `jaq` (réimplémentation en Rust) sur un gros fichier. Lis la section « Destructuring » du manuel jq.

---

### M02-E06 — yq : modifier du YAML sans le casser  `LAB` `★`

> **Ticket PLAT-306** — *De : Lucas Martin* — *Copie : Karim Benali*
> J'ai voulu changer le serveur NTP dans l'inventaire YAML d'InfoGér avec `sed`, j'ai cassé l'indentation et Ansible a refusé le fichier. Karim dit qu'on ne modifie jamais du YAML avec `sed` et qu'il faut « yq, le bon ». Il m'a aussi montré que `sauvegarde: no` ne veut pas dire la même chose pour tous les outils… Tu peux me montrer comment faire proprement ? J'ai mis les fichiers dans le ticket.

**Objectifs pédagogiques**
- Lire, interroger et modifier du YAML avec yq (mikefarah) en conservant commentaires, ancres et types.
- Connaître les pièges du YAML : types implicites (YAML 1.1 contre 1.2), ancres et clés de fusion, documents multiples.
- Fusionner des fichiers de paramètres et convertir JSON ↔ YAML.

**Prérequis** : M02-E05 (filtres jq : la syntaxe de yq en est très proche).
**Durée indicative** : 1 h 30.

**Contexte technique**
- Fichiers fournis : `~/DevOpsPrivateCloud/modules/02-scripting/ressources/M02-E06/` — `inventaire-infoger.yml` (inventaire au format YAML d'Ansible, avec une ancre `&defaut`), `user-data-sandbox.yaml` (gabarit cloud-init des VMs jetables), `parametres-defaut.yml` et `parametres-par2.yml` (paramètres communs et surcharges du site PAR2).
- Copie-les dans `~/m02/e06/` ; tous les résultats y sont attendus. Aucune modification à la main : uniquement yq (sauf mention contraire).
- yq de mikefarah 4.54 (voir l'introduction). Ansible et cloud-init lisent le YAML avec PyYAML, qui applique les règles de **YAML 1.1** ; yq suit **YAML 1.2**.
- Serveur NTP des VMs de la sandbox : la passerelle du VLAN 99, 10.10.99.1 (M00-E31).

**Travail demandé**
1. Vérifie que `yq --version` mentionne mikefarah. Lis la sortie de `apt show yq` sans l'installer : de quel outil s'agit-il ?
2. **Lire.** Liste les hôtes du groupe `socle` (`yq '.all.children.socle.hosts | keys'`). Puis produis `~/m02/e06/hotes.tsv` : pour chaque hôte de l'inventaire (tous groupes), une ligne `hôte<TAB>ansible_host<TAB>ntp_serveur` avec la valeur **effective** de `ntp_serveur` une fois l'ancre fusionnée (`explode`). Lis attentivement l'avertissement que yq affiche, compare la valeur obtenue pour `gw01` avec ce qu'en dirait la spécification YAML, et produis le fichier **conforme à la spécification**.
3. **Types.** Pour `sauvegarde: yes`, `version_python: 3.10` et `mode_cles: 0600`, donne dans ton journal le type et la valeur vus par yq (`tag`), puis par PyYAML (`python3 -c 'import yaml…'`, si `python3-yaml` est présent ; sinon, raisonne avec la spécification YAML 1.1). Quelles conséquences dans un playbook Ansible ?
4. **Corriger l'inventaire.** Produis `~/m02/e06/inventaire-corrige.yml` à partir de l'original, sans ambiguïté pour aucun outil : booléens explicites (`true`/`false`) pour `sauvegarde` partout, `version_python` et `mode_cles` en chaînes, et une lecture de `gw01` identique quel que soit le mode de lecture des clés de fusion. Commentaires et ancre conservés. Compare avec `diff` : qu'est-ce que yq a changé en plus de ce que tu demandais ?
5. **Modifier en place le user-data.** Dans `~/m02/e06/user-data-sandbox.yaml` (copie) : serveurs NTP = la seule passerelle du VLAN 99 ; ajoute la clé publique de `adm01` (`~/.ssh/id_ed25519.pub`, lue par yq depuis une variable d'environnement, pas collée dans l'expression) aux clés de `admin` ; ajoute `package_upgrade: true`. La première ligne `#cloud-config` doit survivre, les droits de `write_files` doivent rester des chaînes. Valide avec `cloud-init schema -c` (cloud-init est installé sur `adm01`) et relis le `diff` : quel commentaire a bougé ?
6. **Fusionner.** Produis `~/m02/e06/parametres-effectifs-par2.yml` : fusion profonde de `parametres-defaut.yml` puis `parametres-par2.yml`, où les **listes** de PAR2 remplacent celles par défaut. Compare les opérateurs `*` et `*+` : lequel convient, et que donnerait l'autre pour `ntp.serveurs` ?
7. **JSON → YAML.** À partir de `cluster-resources.json` de E05, produis `~/m02/e06/vms-lab.yml` : une liste, triée par VMID, des VMs QEMU du pool `lab` hors templates, chaque élément avec les clés `vmid`, `nom` et `etiquettes` (une **liste** ; vide si aucune étiquette).
8. Rassemble toutes tes commandes dans `~/m02/e06/commandes-yq.sh`, rejouable de zéro (il recopie les fichiers fournis, puis applique les transformations).

**Critères de réussite**
- [ ] `hotes.tsv` donne les valeurs effectives conformes à la spécification YAML (dont `pool.ntp.org` pour `gw01`).
- [ ] Dans `inventaire-corrige.yml`, `sauvegarde` est un booléen, `version_python` vaut la chaîne `3.10`, `mode_cles` la chaîne `0600`, l'ancre et les commentaires sont conservés, et `gw01` se lit pareil avec ou sans l'option de conformité de yq.
- [ ] `user-data-sandbox.yaml` commence toujours par `#cloud-config`, utilise 10.10.99.1 comme seul serveur NTP, autorise la clé d'`adm01`, et passe `cloud-init schema`.
- [ ] `parametres-effectifs-par2.yml` contient le domaine et les listes de PAR2, et la rétention fusionnée clé par clé.
- [ ] `vms-lab.yml` liste les 8 VMs attendues avec leurs étiquettes en liste.

**Vérification** : `lab/bin/check 02 06`

<details><summary>Indice 1</summary>

L'option qui fait suivre la spécification à yq pour la clé de fusion apparaît dans l'avertissement lui-même. Selon la spécification, une clé écrite explicitement dans un nœud l'emporte toujours sur celle qui vient de `<<`, où que `<<` soit placé.
</details>

<details><summary>Indice 2</summary>

Pour garder le texte exact d'un nombre en le transformant en chaîne : `to_string` (et non une affectation `= "3.10"` tapée à la main). Pour une variable d'environnement : `strenv(NOM)`. Pour parcourir tous les nœuds : `..`, filtré par `select(tag == "!!map" and has("sauvegarde"))`. Pour l'ordre des clés d'un seul hôte : `sort_keys` sur ce nœud.
</details>

<details><summary>Indice 3</summary>

Fusionner plusieurs fichiers demande `eval-all` (`ea`) et `ireduce` : `yq ea '. as $f ireduce ({}; . * $f)' a.yml b.yml`. Pour lire du JSON : `-p json` ; pour écrire du YAML : `-o yaml`.
</details>

**Pour aller plus loin** (facultatif) : traite un fichier à plusieurs documents (`---`) avec `yq 'select(document_index == 1)'` ; lis la page « Merge » et « Traverse - Read » de la documentation de yq sur les clés de fusion ; essaie `yq --front-matter=process` sur un fichier Markdown avec en-tête YAML.

---

### M02-E07 — Un environnement Python moderne avec uv  `LAB` `★`

> **Ticket PLAT-307** — *De : Karim Benali* — *Copie : Sophie Laurent*
> `medictl` sera un vrai projet Python : déclaré dans `pyproject.toml`, dépendances verrouillées, environnement jetable reconstruit à l'identique sur n'importe quel poste et en CI. On utilise **uv**, rien d'autre (pas de `pip install` à la main, pas de venv bricolé). Exigence de Sophie : le Python utilisé est celui de Debian, qui reçoit les correctifs de sécurité par `apt`, pas un interpréteur téléchargé à côté.

**Objectifs pédagogiques**
- Créer un projet Python empaqueté avec uv et comprendre chaque fichier produit.
- Gérer dépendances, groupe de développement, verrou et environnement ; garantir la reproductibilité.
- Configurer ruff (lint et formatage) avec une liste de règles explicite, et le brancher dans pre-commit.

**Prérequis** : M02-E02, M02-E04 (pre-commit étendu).
**Durée indicative** : 1 h 30.

**Contexte technique**
- Le projet Python vit à la racine de `plateforme/outils` : `pyproject.toml`, `uv.lock`, `.python-version`, code dans `src/medictl/`.
- Nom du projet et de la commande : `medictl`. Python 3.13 (Debian 13), version de départ `0.1.0` (la publication automatique des versions arrive en E25).
- Dépendances : `typer`, `proxmoxer`, `requests` ; groupe de développement `dev` : `pytest`, `responses`, `ruff`. Versions de référence : Typer 0.27, proxmoxer 2.3, pytest 9, ruff 0.16 (PLAN.md §6).
- uv 0.12 : `uv init` crée par défaut un projet **empaqueté** (dossier `src/`, système de construction `uv_build`).
- Point d'entrée : `medictl = "medictl.cli:app"`, où `app` est une application Typer qui, pour l'instant, n'offre que `--version` (version lue dans les métadonnées du paquet installé). Les commandes `vm …` viendront en E15.
- pre-commit : `https://github.com/astral-sh/ruff-pre-commit`, hooks `ruff-check` et `ruff-format`, `rev` = la version de ruff verrouillée dans `uv.lock`.

**Travail demandé**
1. `uv --version`, puis `uv python list` et `uv python find 3.13` : quel interpréteur uv trouve-t-il ?
2. Sur une branche `feat/projet-python`, dans `~/src/outils` : `uv init --name medictl --python 3.13`. Liste ce que la commande a créé et lis chaque fichier. Qu'auraient produit `--no-package` et `--lib` ? Pourquoi un projet empaqueté convient-il à une CLI qu'on installera ailleurs ?
3. Dans `pyproject.toml`, impose le Python du système (section `[tool.uv]` : interdire les interpréteurs téléchargés et n'utiliser que ceux du système). Vérifie l'effet avec `uv python find`.
4. Ajoute les dépendances (`uv add …`, `uv add --dev …`). Lis le diff de `pyproject.toml` (contraintes ajoutées), puis `uv.lock` : qu'y trouve-t-on pour chaque paquet (version, source, empreintes) ? `uv tree` : d'où vient `rich` ? Et `click` ?
5. Remplace le code généré par `src/medictl/__init__.py` (qui expose `__version__` lue avec `importlib.metadata`) et `src/medictl/cli.py` (application Typer avec l'option `--version`). Adapte `[project.scripts]`. `uv run medictl --version` doit afficher `medictl 0.1.0`. Que fait `uv run` avant d'exécuter ta commande ?
6. Configure ruff dans `pyproject.toml` : `line-length`, `target-version`, et une liste **explicite** de familles de règles dans `[tool.ruff.lint] select` (au minimum pyflakes, pycodestyle, tri des imports, bugbear, pyupgrade et bandit `S`). Configure pytest dans `[tool.pytest.ini_options]` (dossier `tests/python`). `uv run ruff check` et `uv run ruff format --check` doivent passer.
7. Ajoute les hooks ruff à pre-commit et `.venv/` doit être ignoré par Git (vérifie `.gitignore`).
8. Reproductibilité : `rm -rf .venv && uv sync --locked`, puis `uv lock --check`. Dans ton journal : différence entre `--locked` et `--frozen` ; que se passe-t-il si quelqu'un modifie `pyproject.toml` sans mettre à jour le verrou, et qui s'en aperçoit (poste ? CI ?).
9. MR (avec `uv.lock`), pipeline vert, fusion.

**Critères de réussite**
- [ ] `pyproject.toml`, `uv.lock`, `.python-version` et `src/medictl/` sont sur `main` ; `.venv/` n'est pas versionné.
- [ ] Le projet impose le Python du système ; `.venv` repose sur `/usr/bin/python3.13`.
- [ ] `uv lock --check` passe ; `.venv/bin/medictl --version` affiche `medictl 0.1.0`.
- [ ] ruff a une liste de règles explicite ; `ruff check` et `ruff format --check` passent sur `src/`.
- [ ] Les hooks ruff sont dans pre-commit.

**Vérification** : `lab/bin/check 02 07`

<details><summary>Indice 1</summary>

Les réglages `python-preference` et `python-downloads` de uv acceptent la table `[tool.uv]` de `pyproject.toml` (documentation : *Settings*). Le fichier `.venv/pyvenv.cfg` indique, ligne `home`, d'où vient l'interpréteur.
</details>

<details><summary>Indice 2</summary>

Avec Typer, une option globale comme `--version` se déclare dans le *callback* de l'application, avec `is_eager=True` et une fonction de rappel qui affiche la version puis lève `typer.Exit()`. La version se lit avec `importlib.metadata.version("medictl")`.
</details>

<details><summary>Indice 3</summary>

Si `uv run` se plaint d'un `pyproject.toml` à la racine qui n'aurait pas de section `[project]`, ou si `uv init` refuse d'écrire, vérifie que tu es bien à la racine du dépôt et qu'aucun `pyproject.toml` n'existe déjà. ruff du hook et ruff du projet doivent être à la même version : `uv tree --depth 1 | grep ruff`.
</details>

**Pour aller plus loin** (facultatif) : lis la page « Scripts » de la documentation de uv : un script isolé peut déclarer ses dépendances dans un commentaire (PEP 723) et se lancer avec `uv run script.py`. Compare avec un projet complet.

---

### M02-E08 — Premier client Python de l'API Proxmox, TLS vérifié  `LAB` `★★`

> **Ticket SEC-308** — *De : Sophie Laurent* — *Copie : Karim Benali*
> Avant que `medictl` ne fasse quoi que ce soit, je veux valider sa façon de parler à Proxmox : jeton d'API d'automatisation (jamais un compte humain), secret lu dans le fichier protégé existant et jamais affiché, ni en argument, ni dans une trace d'erreur, et certificat **vérifié** contre l'autorité de `pve01`. J'ai vu trop de `verify=False` « temporaires » chez InfoGér. Montre-moi aussi ce qui se passe quand ça doit échouer.

**Objectifs pédagogiques**
- Appeler une API REST en Python (`requests`, puis `proxmoxer`) avec un jeton, un délai maximal et la vérification TLS.
- Lire une configuration secrète sans l'exécuter, et garder le secret hors de `repr()`, des messages et des journaux.
- Diagnostiquer un refus TLS et le corriger **sans** désactiver la vérification.

**Prérequis** : M00-E17, M02-E07.
**Durée indicative** : 2 h.

**Contexte technique**
- Configuration : `~/.config/workbook/pve-api.env` (M00-E17), mode 600, variables `PVE_API_URL`, `PVE_NODE`, `PVE_TOKEN_ID`, `PVE_TOKEN_SECRET`, `PVE_CACERT` (cette dernière contient `$HOME`). Chemin modifiable par la variable d'environnement `MEDICTL_ENV_FILE`.
- Module à livrer : `src/medictl/pve.py`, avec cette interface (les exercices suivants et la vérification s'y fient) :

| Élément | Rôle |
|---|---|
| `class ConfigError(Exception)` | configuration absente, incomplète ou invalide ; le message nomme le fichier en cause, jamais le secret |
| `@dataclass(frozen=True) class PveConfig` | champs `api_url`, `node`, `token_id`, `token_secret` (exclu de `repr()`), `cacert` (`Path` ou `None`) |
| `charger_config(chemin: Path \| None = None) -> PveConfig` | lit l'argument, sinon `$MEDICTL_ENV_FILE`, sinon `~/.config/workbook/pve-api.env`, **sans l'exécuter** ; valide les valeurs |
| `connexion(cfg: PveConfig, timeout: float = 10) -> ProxmoxAPI` | client proxmoxer authentifié par jeton, certificat vérifié avec `cfg.cacert` |

- Python 3.13 et urllib3 2 appliquent par défaut les contrôles **stricts** de la RFC 5280 sur les certificats (`VERIFY_X509_STRICT`), que `curl` n'applique pas. Selon la date d'installation de `pve01`, l'autorité que Proxmox a générée peut ne pas les satisfaire (correctif de Proxmox en cours au moment de la rédaction). Si c'est ton cas, désactiver la vérification reste interdit : trouve une solution qui garde la vérification complète (chaîne **et** nom), applique-la et documente-la.
- Brouillons d'essai : `~/m02/e08/`, lancés dans l'environnement du projet (`uv run python ~/m02/e08/…` depuis `~/src/outils`).

**Travail demandé**
1. **requests d'abord.** Écris `~/m02/e08/essai_requests.py` : lecture minimale du fichier, session `requests`, en-tête `Authorization: PVEAPIToken=<ID>=<SECRET>`, `verify=` l'autorité, `timeout=`, appels à `/version`, `/cluster/resources?type=vm` et `/nodes/<NŒUD>/status`. Affiche le code HTTP et le motif (`reason`) de chaque réponse. Lequel est refusé, et pourquoi est-ce normal ?
2. **Si TLS refuse.** Lis le message exact. Inspecte l'autorité utilisée (`openssl x509 -in "$PVE_CACERT" -noout -text`, et compare avec ce que vérifie `openssl verify -x509_strict`). Explique dans ton journal ce qui manque, choisis une correction qui conserve la vérification, et justifie-la (avantages, limites, ce qu'il faudra refaire si l'autorité de `pve01` change).
   > ⚠️ **Attention** : la clé privée de l'autorité de Proxmox (`/etc/pve/priv/pve-root-ca.key`) ne quitte jamais `pve01`. Ne régénère pas l'autorité ni les certificats de `pve01` (`pvecm updatecerts --force`…) sans avoir compris les conséquences pour l'interface web et pour les autres clients.
3. **Le module.** Écris `src/medictl/pve.py` selon l'interface ci-dessus. Le lecteur du fichier : lignes vides et commentaires ignorés, `export` facultatif, valeurs entre guillemets doubles (avec `$HOME` développé) ou simples (sans développement), commentaire possible en fin de ligne. Il **n'exécute rien** (pas de `bash -c "source …"`). Messages d'erreur précis : fichier absent, variable manquante (nommée), URL invalide, autorité introuvable.
4. **proxmoxer.** Écris `~/m02/e08/essai_proxmoxer.py` qui utilise ton module : version de Proxmox, liste des VMs QEMU du pool `lab` hors templates, puis un appel refusé. Quelle exception lève proxmoxer, et que contient-elle ?
5. **Faire échouer exprès**, et noter chaque fois l'exception et ce qu'elle affiche : autorité étrangère (`/etc/ssl/certs/ca-certificates.crt`), secret faux, nom d'hôte absent du certificat (si tu as une autre façon de joindre `pve01`), port fermé. Le secret apparaît-il quelque part (message, trace, `repr`) ?
6. `uv run ruff check` doit passer sur `src/` : quelles règles `S` (bandit) auraient signalé un `verify=False` ou un appel sans délai ?
7. MR, pipeline vert, fusion. Dans la description de la MR, réponds au ticket de Sophie (vérification TLS, emplacement et protection du secret, comportement en erreur).

**Critères de réussite**
- [ ] `src/medictl/pve.py` est sur `main` et respecte l'interface demandée.
- [ ] `connexion(charger_config()).version.get()` répond depuis `adm01`, certificat vérifié ; la liste des ressources contient `adm01`.
- [ ] Avec une autorité qui n'a pas signé le certificat de `pve01`, la connexion échoue par une erreur TLS.
- [ ] Le secret n'apparaît ni dans `repr()` de la configuration, ni dans les messages d'erreur ; aucune désactivation de la vérification TLS dans `src/`.
- [ ] `MEDICTL_ENV_FILE` vers un fichier absent donne une `ConfigError` qui nomme le fichier.

**Vérification** : `lab/bin/check 02 08`

<details><summary>Indice 1</summary>

`proxmoxer.ProxmoxAPI` accepte `host`, `port`, `user` (`utilisateur@domaine`), `token_name`, `token_value`, `verify_ssl` et `timeout`. Lis le code de son *backend* HTTPS (`proxmoxer/backends/https.py` dans `.venv`) : que devient `verify_ssl` quand il arrive à `requests` ? Un chemin de fichier y est-il accepté ?
</details>

<details><summary>Indice 2</summary>

Avec `requests`, un `session.verify = …` est **écrasé** par les variables d'environnement `REQUESTS_CA_BUNDLE` ou `CURL_CA_BUNDLE` si elles sont définies ; un `verify=` passé à chaque appel ne l'est pas. Pour `dataclass`, cherche le paramètre `repr` de `field()`.
</details>

<details><summary>Indice 3</summary>

Si l'erreur TLS parle d'une extension manquante dans le certificat de l'autorité : une ancre de confiance n'est qu'un certificat auto-signé contenant une clé publique. Le certificat du serveur reste valide pour **toute** ancre portant le même sujet et la même clé. Regarde ce que permet `openssl x509` avec `-signkey`, `-clrext` et `-extfile`, exécuté sur `pve01` ; seul le certificat public produit voyage vers `adm01`.
</details>

**Pour aller plus loin** (facultatif) : compare avec le client `httpx` (vérification TLS par `ssl.SSLContext`) ; lis la RFC 5280 §4.2.1.3 (*Key Usage*) et la note de version de Python 3.13 sur `VERIFY_X509_STRICT`. Au module 06, `pve01` recevra un certificat émis par step-ca.

---

### M02-E09 — Questions : Bash ou Python ?  `Q` `★★`

> **Ticket PLAT-309** — *De : Claire Morel*
> Dans six mois, on aura cinquante outils. Je ne veux pas d'un débat à chaque MR sur le langage. Réponds à ces questions par écrit, en t'appuyant sur ce que tu viens de pratiquer : elles serviront de matière à l'ADR qu'on rédigera en fin de palier 3.

**Objectifs pédagogiques**
- Choisir le langage d'un outil selon des critères explicites (nature du travail, erreurs, données, tests, distribution, environnement d'exécution).
- Connaître les alternatives (jq, awk, Ansible, OpenTofu) et savoir quand aucun script n'est la bonne réponse.

**Prérequis** : M02-E03 à M02-E08.
**Durée indicative** : 1 h.

**Travail demandé**

Réponds aux 14 questions, en justifiant.

1. Pour chacun de ces besoins, Bash ou Python ? Justifie en une ou deux phrases chacun :
   (a) redémarrer `chrony` sur cinq VMs si leur décalage dépasse 100 ms ;
   (b) produire chaque semaine un rapport Markdown de l'occupation des VMs à partir de l'API Proxmox, avec tri, regroupements et totaux ;
   (c) un `ExecStartPre=` systemd qui vérifie qu'un point de montage est présent ;
   (d) un outil interactif de création de VM, avec sous-commandes, options, validations et tests ;
   (e) extraire les 10 adresses IP les plus fréquentes d'un journal nginx de 2 Go.
2. Donne cinq **signaux** qui indiquent qu'un script Bash devrait être réécrit en Python. Lesquels as-tu rencontrés dans `ms-collecte-config` ?
3. *(QCM)* Un script Bash appelle l'API Proxmox avec `curl` puis traite le JSON. Quel est le meilleur choix ?
   - A. `grep` et `sed` sur la sortie de `curl`
   - B. `jq`, avec les filtres versionnés dans le dépôt
   - C. `python3 -c` pour chaque champ
   - D. réécrire en Python dès qu'il y a du JSON
4. Compare la gestion des erreurs de Bash (`set -e`, codes retour, `trap`) et de Python (exceptions) : qu'est-ce qui est plus sûr par défaut dans chaque langage, et qu'est-ce qui reste de ta responsabilité ?
5. Un outil Python doit tourner sur des VMs du socle où l'on ne veut rien installer. Quelles options as-tu (bibliothèque standard seule, script PEP 723 avec `uv run`, paquet installé par `uv tool`, binaire autonome) ? Avantages et limites de chacune.
6. Compare bats et pytest : ce qu'on teste avec chacun, comment on isole les appels externes (commandes, API), ce qui est difficile à tester dans chaque cas.
7. *(QCM)* Ce script Bash de 400 lignes manipule des tableaux associatifs, construit du JSON par concaténation de chaînes et compte trois fonctions de plus de 80 lignes. Quelle est la meilleure décision ?
   - A. Le laisser tel quel tant qu'il passe ShellCheck
   - B. Le réécrire intégralement en Python cette semaine
   - C. Geler les évolutions, écrire des tests de comportement (bats) sur l'existant, puis réécrire en Python en vérifiant que les tests passent toujours
   - D. Le découper en plusieurs scripts Bash plus courts
8. Quels risques d'injection existent en Bash et en Python quand une donnée externe (nom de VM, nom de fichier, réponse d'API) finit dans une commande ? Donne la parade dans chaque langage.
9. Performance : pourquoi une boucle Bash qui appelle `jq`, `grep` ou `date` sur 10 000 lignes est-elle lente ? Comment le mesures-tu, et quelles sont les deux corrections typiques ?
10. Quand la bonne réponse n'est-elle **ni** Bash **ni** Python, mais Ansible (module 04) ou OpenTofu (module 05) ? Donne deux exemples de besoins de MédiSphère pour chacun.
11. Portabilité : `#!/bin/sh` ou `#!/usr/bin/env bash` ? `#!/usr/bin/python3` ou `#!/usr/bin/env python3` ? Que choisis-tu pour `plateforme/outils`, et pourquoi ?
12. Comment imposes-tu les mêmes règles de qualité aux deux langages dans le dépôt (outils, configuration, endroits où elles s'appliquent) ?
13. Un collègue propose d'écrire `medictl` en Go « pour avoir un binaire unique ». Quels arguments pour et contre, pour l'équipe Plateforme telle qu'elle est aujourd'hui ?
14. Rédige, en dix lignes au plus, la règle de choix que tu proposerais pour l'équipe (elle servira à l'ADR-0020, en E32).

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 14 questions avant d'ouvrir le corrigé.
- [ ] Tu t'es noté avec la grille du corrigé (score sur 28).
- [ ] Ta règle de choix (question 14) est dans ton journal, prête pour l'ADR.

<details><summary>Indice 1</summary>

Pour chaque besoin, demande-toi : le travail consiste-t-il surtout à **enchaîner des commandes** ou à **manipuler des données** ? Qui l'exécute, où, avec quel environnement installé ? Qui le maintiendra, et comment le testera-t-on ?
</details>

<details><summary>Indice 2</summary>

Pense au coût total : écrire, relire, tester, distribuer, diagnostiquer à 3 h du matin. Un outil n'est pas meilleur parce qu'il est plus court ou plus élégant ; il l'est s'il échoue clairement et se corrige vite.
</details>

**Pour aller plus loin** (facultatif) : lis le *Google Shell Style Guide*, section « When to use Shell », et compare ses critères aux tiens.
