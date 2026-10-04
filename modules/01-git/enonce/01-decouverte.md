# Module 01 — Palier 1 : Découverte

Karim commence par mesurer ton niveau Git, puis te fait descendre sous le capot : avant de confier l'historique de toute la plateforme à un outil, on sait comment il est stocké. Tu configures ensuite ton poste comme un professionnel (identité, conventions, signature), tu installes la forge `git01` derrière un certificat signé par une PKI provisoire, tu l'administres proprement et tu y migres le dépôt de documentation du socle sans perdre un seul commit. Le palier se termine dans le bac à sable `formation/git-labo` : lire un historique, en construire un, et savoir défaire ce qu'on a fait.

Prérequis : socle v0 livré (`lab/bin/check 00 50` vert), agent SSH chargé sur `adm01`. Lis [`00-introduction.md`](00-introduction.md) avant de commencer, en particulier les règles du module.

---

### M01-E01 — Test de positionnement Git  `Q` `★★`

> **Ticket PLAT-201** — *De : Karim Benali*
> Comme pour Linux et le réseau, je te fais passer notre questionnaire Git avant de te confier la forge. On va beaucoup réécrire d'historique dans les mois qui viennent : je veux savoir où tu en es sur le modèle de Git, les fusions, le rebase et la récupération après erreur.
> Par écrit, sans moteur de recherche ni IA, 1 h 30 maximum. Puis corrige-toi avec la grille.

**Objectifs pédagogiques**
- Évaluer honnêtement tes acquis Git, au-delà de l'usage quotidien.
- Identifier les notions à retravailler et les exercices du module qui les traitent.

**Prérequis** : aucun.
**Durée indicative** : 1 h 30 (+ 30 min d'auto-correction).

**Travail demandé**

Réponds aux 25 questions. Pour les QCM, justifie ton choix en une ou deux phrases.

1. Quelle est la différence entre `git fetch` et `git pull` ? Que fait exactement `git pull` avec la configuration par défaut de Git 2.47, et que se passe-t-il quand ta branche locale et la branche distante ont toutes deux de nouveaux commits ?

2. *(QCM)* Que contient un objet *commit* ?
   - A. La liste des fichiers modifiés et leurs différences par rapport au parent
   - B. L'empreinte d'un arbre racine, les empreintes des parents, l'auteur, le validateur (*committer*) avec leurs dates, et le message
   - C. Une copie complète de tous les fichiers du projet
   - D. L'empreinte du commit parent et un diff compressé

3. À quoi sert l'index (*staging area*) ? Donne deux situations concrètes où il t'est utile, et la commande qui permet d'indexer seulement une partie des modifications d'un fichier.

4. Que signifie « `HEAD` détaché » (*detached HEAD*) ? Dans quelles situations s'y retrouve-t-on ? Que deviennent les commits faits dans cet état si on bascule ensuite sur `main` ?

5. Explique la différence entre une fusion en avance rapide (*fast-forward*), une fusion avec commit de fusion (`--no-ff`) et une fusion « squash ». Dessine le graphe obtenu dans chaque cas à partir d'une branche de trois commits.

6. Que fait `git rebase main` sur une branche de fonctionnalité ? Énonce la « règle d'or » du rebase et explique ce qui se passe concrètement pour tes collègues si tu la violes.

7. *(QCM)* Que liste `git log main..fonction` ?
   - A. Les commits de `main` absents de `fonction`
   - B. Les commits de `fonction` absents de `main`
   - C. Les commits présents dans l'une des deux branches mais pas dans les deux
   - D. Les commits communs aux deux branches

8. Tu ajoutes `*.log` à `.gitignore`, mais `app.log` continue d'apparaître dans `git status` comme modifié. Pourquoi ? Comment corriger sans supprimer le fichier de ton disque ?

9. Tu viens de commiter (sans pousser) un fichier contenant un mot de passe. Que fais-tu ? Et si tu l'avais déjà poussé sur la forge partagée, qu'est-ce qui change dans ta réponse et dans l'ordre de tes actions ?

10. *(QCM)* Tu as lancé `git reset --hard HEAD~3` sur ta branche locale, par erreur, il y a cinq minutes. Les trois commits n'avaient jamais été poussés. Que se passe-t-il ?
    - A. Ils sont définitivement perdus
    - B. Ils sont récupérables avec `git reflog`, tant que le ramasse-miettes ne les a pas supprimés
    - C. Ils sont récupérables avec `git stash pop`
    - D. Ils sont récupérables seulement si la forge en a une copie

11. Quelle différence entre `git reset --soft`, `--mixed` et `--hard` ? Pour chacun, dis ce qui arrive à `HEAD`, à l'index et à l'arbre de travail.

12. Pourquoi ne faut-il pas utiliser `git reset` (puis `push --force`) pour annuler un commit déjà poussé sur `main` ? Que fais-tu à la place, et que produit cette commande dans l'historique ?

13. Pendant un `git rebase main`, un conflit survient. Dans ce contexte, que désignent `--ours` et `--theirs` ? Pourquoi est-ce l'inverse d'une fusion ? Quelles sont les trois façons de sortir de l'état « rebase en cours » ?

14. Différence entre une étiquette légère et une étiquette annotée ? Laquelle utiliser pour une version publiée, et pourquoi ? `git push` pousse-t-il les étiquettes ?

15. Dans quel cas utilises-tu `git cherry-pick` ? Cite un risque de son usage répété entre deux branches longues.

16. Un bogue est apparu entre la version d'il y a trois mois et aujourd'hui ; 1 000 commits les séparent. Avec `git bisect`, combien d'étapes de test au maximum pour trouver le commit fautif ? Comment automatiser la recherche ?

17. Qu'est-ce que le *reflog* ? Est-il partagé avec la forge lors d'un `push` ? Combien de temps conserve-t-il les entrées par défaut ?

18. *(QCM)* Tu corriges le message de ton dernier commit avec `git commit --amend`. Que devient l'empreinte du commit ?
    - A. Elle ne change pas : seul le message a changé
    - B. Elle change, car le message fait partie du contenu haché de l'objet commit
    - C. Elle change seulement si des fichiers ont aussi été modifiés
    - D. Elle change seulement après un `git gc`

19. Que montre `git branch -vv` ? Que signifie `[origin/main: ahead 2, behind 3]`, et comment en es-tu informé sans faire de `fetch` ? Quelle est la limite de cette information ?

20. Quelle différence entre `git push --force` et `git push --force-with-lease` ? Dans quel scénario `--force-with-lease` seul ne te protège plus, et quelle option le complète ?

21. Une équipe mélange des postes Windows et Linux ; des diffs entiers apparaissent sur des fichiers que personne n'a modifiés. Explique le phénomène et la solution robuste, versionnée dans le dépôt.

22. Pourquoi ne versionne-t-on pas une image ISO de 600 Mo dans un dépôt Git, même une seule fois puis supprimée au commit suivant ? Que proposes-tu à la place ?

23. `git blame` attribue une ligne à Lucas, qui jure ne pas l'avoir écrite : il a seulement réindenté le fichier. Comment retrouver le véritable auteur ? Et comment retrouver le commit qui a introduit (ou supprimé) la chaîne `SEUIL_ALERTE`, quel que soit le fichier ?

24. Réécris ces trois messages de commit selon Conventional Commits, et dis lequel déclencherait une nouvelle version **majeure** avec semantic-release :
    - « correction bug DNS »
    - « Ajout de l'option --dry-run au script de déploiement »
    - « Suppression de l'ancienne variable PVE_HOST, remplacée par PVE_API_URL (les scripts appelants doivent être modifiés) »

25. Où se trouvent les hooks Git côté client ? Sont-ils versionnés avec le dépôt ? Pourquoi un hook `pre-commit` local ne suffit-il pas à **garantir** une règle d'équipe ?

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 25 questions avant d'ouvrir le corrigé.
- [ ] Tu as noté chaque réponse avec la grille du corrigé (0, 1 ou 2 points) et calculé ton score sur 50.
- [ ] Tu as reporté dans tes notes les notions à retravailler et les exercices du module associés.

<details><summary>Indice 1</summary>

Pour les questions sur `reset`, `restore`, `rebase`, raisonne avec les « trois arbres » : `HEAD`, l'index, l'arbre de travail. Chaque commande copie quelque chose de l'un vers l'autre, ou déplace une référence.
</details>

<details><summary>Indice 2</summary>

Pour les questions de récupération, souviens-toi qu'un objet Git n'est jamais modifié : on en crée de nouveaux et on déplace des pointeurs. La vraie question est toujours « quelque chose pointe-t-il encore sur l'ancien objet ? ».
</details>

**Pour aller plus loin** (facultatif) : refais le test à la fin du module, sans relire le corrigé, et compare les deux scores.

---

### M01-E02 — Le modèle objet de Git : blobs, arbres, commits, références  `LAB` `★`

> **Ticket PLAT-202** — *De : Karim Benali*
> Dans six mois, quelqu'un te dira « j'ai perdu mon travail » ou « le dépôt est corrompu ». Ce jour-là, il faudra savoir ce qu'il y a dans `.git`. Je te propose un exercice que je fais faire à tous les arrivants : construire un commit **à la main**, sans `git add` ni `git commit`, avec les commandes de « plomberie ».

**Objectifs pédagogiques**
- Comprendre les quatre types d'objets Git et la façon dont ils sont identifiés.
- Construire un commit avec les commandes de bas niveau (*plumbing*) et relier chaque commande de haut niveau à ce qu'elle fait réellement.
- Comprendre ce qu'est une branche, une étiquette et `HEAD` sur le disque.

**Prérequis** : M00-E15 (`git` configuré sur `adm01`).
**Durée indicative** : 1 h 30.

**Contexte technique**
- Dépôt de travail : `~/src/labo-objets` sur `adm01` (local, jamais publié). Crée `~/src` s'il n'existe pas : c'est l'emplacement des clones de travail du bloc A (`WB_SRC`).
- Contenus imposés (le check en recalcule les empreintes) :

| Fichier | Contenu exact (une ligne, terminée par un retour à la ligne) |
|---|---|
| `LISEZMOI.txt` | `Bonjour MédiSphère` |
| `docs/notes.txt` | `Les objets Git sont immuables.` |

- Commandes de plomberie utiles : `git hash-object`, `git cat-file`, `git update-index`, `git write-tree`, `git ls-tree`, `git commit-tree`, `git update-ref`, `git symbolic-ref`. Leur page de manuel : `git help <commande>`.

**Travail demandé**

1. Crée le dépôt et observe-le avant tout objet :
   ```
   admin@adm01:~$ mkdir -p ~/src && git init -b main ~/src/labo-objets && cd ~/src/labo-objets
   admin@adm01:~/src/labo-objets$ find .git -type f | sort
   admin@adm01:~/src/labo-objets$ cat .git/HEAD
   ```
   Note dans ton journal le rôle de `HEAD`, `config`, `objects/` et `refs/`. Vers quoi pointe `HEAD` alors que la branche `main` n'existe pas encore ?

2. **Blob.** Calcule l'empreinte du contenu de `LISEZMOI.txt` **sans rien écrire**, puis écris l'objet dans la base :
   ```
   admin@adm01:~/src/labo-objets$ printf 'Bonjour MédiSphère\n' | git hash-object --stdin
   admin@adm01:~/src/labo-objets$ printf 'Bonjour MédiSphère\n' | git hash-object -w --stdin
   admin@adm01:~/src/labo-objets$ find .git/objects -type f
   ```
   Retrouve l'objet sur le disque, puis interroge-le avec `git cat-file` (type, taille, contenu). Le fichier sur disque est compressé (zlib) : décompresse-le (par exemple avec `python3` et le module `zlib`) et observe l'en-tête qui précède le contenu.
   Puis **recalcule l'empreinte sans Git**, avec `sha1sum`, en reconstituant exactement ce que Git hache. Note dans ton journal la taille indiquée dans l'en-tête et explique pourquoi elle diffère du nombre de caractères de la phrase.

3. Écris de même le blob de `docs/notes.txt`. Vérifie qu'un fichier `LISEZMOI.txt` n'existe toujours pas dans l'arbre de travail : où est le contenu ?

4. **Arbres.** Inscris les deux blobs dans l'index sous leurs noms de fichiers (`git update-index` avec `--add` et `--cacheinfo`), puis fabrique l'arbre correspondant :
   ```
   admin@adm01:~/src/labo-objets$ git ls-files --stage
   admin@adm01:~/src/labo-objets$ git write-tree
   ```
   Affiche l'arbre racine puis le sous-arbre `docs` avec `git cat-file -p`. Combien d'objets *tree* ont été créés, et pourquoi ?

5. **Commit racine.** Crée un commit qui pointe sur cet arbre, avec le message `Premier commit construit à la main`, à l'aide de `git commit-tree`. Affiche-le avec `git cat-file -p` et repère chaque champ. Lance `git log` : que se passe-t-il, et pourquoi ?

6. **Branche.** Fais pointer `main` sur ce commit avec `git update-ref`. Relance `git log`, puis `git status`. Explique l'état affiché par `git status` (les fichiers sont-ils « supprimés » ?) et remets l'arbre de travail en cohérence avec une commande de haut niveau.

7. **Deuxième commit.** Modifie `docs/notes.txt` (ajoute une ligne de ton choix), puis crée un second commit **toujours en plomberie** (blob, index, arbre, `commit-tree` avec un parent) et avance `main`. Combien de nouveaux objets ont été créés ? Lesquels ont été réutilisés ?

8. **Étiquettes.** Pose une étiquette légère `v0-leger` et une étiquette annotée `v0-annote` (message libre) sur le premier commit, avec `git tag`. Compare ce qu'elles sont sur le disque (`.git/refs/tags/`, `git cat-file -t`).

9. **Déduplication.** Copie `LISEZMOI.txt` en `COPIE.txt`, indexe-la (`git add` est autorisé ici) et regarde l'empreinte de son blob. Combien d'objets ont été créés ? Annule l'indexation (`git rm --cached COPIE.txt`) et supprime la copie.

10. **Références.** Crée une branche `essai` avec `git branch`, puis regarde ce qui a été créé sur le disque. Exécute `git pack-refs --all` et observe où sont passées les références. Supprime `essai`.

**Critères de réussite**
- [ ] `~/src/labo-objets` est un dépôt dont la branche par défaut est `main`.
- [ ] Le commit racine de `main` a pour message `Premier commit construit à la main` et pour arbre exactement les deux fichiers imposés (empreinte d'arbre vérifiée par le check).
- [ ] `main` contient au moins deux commits ; le second a le commit racine pour parent.
- [ ] `v0-annote` est un objet étiquette ; `v0-leger` pointe directement sur un commit ; les deux désignent le commit racine.
- [ ] L'arbre de travail est propre (`git status` sans modification).
- [ ] Ton journal contient l'empreinte recalculée avec `sha1sum` et l'explication de la taille de l'en-tête.

**Vérification** : `lab/bin/check 01 02`

<details><summary>Indice 1</summary>

Un objet Git est haché sous la forme `<type> <taille en octets>\0<contenu>`. `printf` sait écrire un octet nul (`\0`) ; `wc -c` compte des octets, pas des caractères. En UTF-8, certains caractères accentués occupent plusieurs octets.
</details>

<details><summary>Indice 2</summary>

`git update-index --add --cacheinfo <mode>,<empreinte>,<chemin>` : le mode d'un fichier ordinaire est `100644`. Le chemin peut contenir un `/` : `write-tree` construit lui-même les sous-arbres. `git commit-tree <arbre> -m "<message>"` affiche l'empreinte du commit créé ; l'option `-p` donne un parent.
</details>

<details><summary>Indice 3</summary>

À l'étape 6, l'index contient les fichiers, mais l'arbre de travail est vide : pour Git, ils ont été supprimés de l'arbre de travail. Ramener les fichiers de l'index (ou de `HEAD`) vers l'arbre de travail est le rôle de `git restore`.
</details>

**Pour aller plus loin** (facultatif) : refais l'étape 2 dans un dépôt créé avec `git init --object-format=sha256` et compare. Lis la section *Git Internals* de *Pro Git* (chapitre 10) ; on y reviendra avec les *packfiles* en E45.

---

### M01-E03 — Configurer Git sur `adm01` (identité, `main`, alias, signature SSH)  `LAB` `★`

> **Ticket PLAT-203** — *De : Karim Benali* — *Cc : Sophie Laurent*
> Avant d'ouvrir la forge, chacun configure son poste selon les conventions de l'équipe : identité nominative, branche par défaut `main`, des réglages qui évitent les mauvaises surprises au `pull` et au conflit, et la **signature des commits**. Sophie veut pouvoir prouver qui a écrit quoi dans le code qui pilote l'infrastructure : on signe avec une clé SSH dédiée.

**Objectifs pédagogiques**
- Comprendre les niveaux de configuration de Git (système, global, local) et savoir d'où vient une valeur.
- Choisir des réglages de confort et de sûreté, et les justifier.
- Signer ses commits avec une clé SSH et vérifier une signature localement.

**Prérequis** : M01-E02.
**Durée indicative** : 1 h.

**Contexte technique**

| Réglage | Valeur imposée |
|---|---|
| Identité | `user.name` = ton prénom et ton nom ; `user.email` = `<MOI>@medisphere.internal` |
| `<MOI>` | ton identifiant sur la forge, sur le modèle `prénom.nom` (ex. `camille.durand`), en minuscules, sans accent ; reporté dans `lab/lab.env` : `WB_MOI=<MOI>` |
| Branche par défaut des nouveaux dépôts | `main` |
| Clé de signature | `~/.ssh/id_ed25519_signature` (ed25519, **distincte** de ta clé de connexion `~/.ssh/id_ed25519`, protégée par une phrase de passe) |
| Signataires de confiance | `~/.config/git/allowed_signers` |
| Ignorés globaux | `~/.config/git/ignore` |

Il n'y a pas de serveur de messagerie dans le lab : l'adresse `<MOI>@medisphere.internal` ne reçoit rien, mais elle doit être **identique** à celle de ton compte GitLab (E05). C'est elle qui relie tes commits à ton compte et qui permettra à GitLab d'afficher tes signatures comme vérifiées (E27).

**Travail demandé**

1. Fais l'état des lieux : affiche toute la configuration effective **avec son origine** (`git config --list --show-origin --show-scope`). Note d'où vient chaque valeur actuelle (M00-E15 a déjà fixé une identité).

2. Choisis `<MOI>`, renseigne `WB_MOI` dans `lab/lab.env`, puis fixe ton identité et la branche par défaut au niveau **global**.

3. Ajoute les réglages suivants au niveau global, et justifie chacun dans ton journal en une ligne (quel problème il évite) :
   - un comportement explicite de `git pull` quand les historiques ont divergé (choisis entre `pull.ff=only` et `pull.rebase=true`, et argumente) ;
   - la suppression automatique des références distantes disparues lors d'un `fetch` ;
   - la création automatique de la branche distante de suivi au premier `push` d'une nouvelle branche ;
   - un style de marqueurs de conflit qui affiche aussi la version **ancêtre commune** (`zdiff3`) ;
   - l'algorithme de diff `histogram` ;
   - ton éditeur préféré.

4. Crée au moins trois alias, dont `lg` qui affiche **le graphe de toutes les branches**, une ligne par commit, avec les références. Teste-le sur `~/src/labo-objets`.

5. Crée le fichier d'ignorés globaux `~/.config/git/ignore` avec au minimum les fichiers d'éditeur et `.env`, `*.token`. Explique dans ton journal pourquoi ce fichier **ne remplace pas** le `.gitignore` d'un projet.

6. **Signature SSH.**
   - Génère la clé de signature (ed25519, avec phrase de passe, commentaire explicite) et charge-la dans ton agent.
   - Configure Git : format de signature `ssh`, clé de signature (chemin **absolu** de la clé publique), fichier des signataires de confiance, signature automatique des commits **et** des étiquettes annotées.
   - Écris `~/.config/git/allowed_signers` : une ligne qui associe ton adresse à ta clé publique de signature, limitée à l'espace de noms `git`.
   ```
   admin@adm01:~$ ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_signature -C "<MOI> signature Git"
   admin@adm01:~$ man ssh-keygen       # section ALLOWED SIGNERS
   ```

7. Dans `~/src/labo-objets`, crée un commit (vide ou non) avec le message `test: premier commit signé`. Vérifie la signature (`git log --show-signature -1`, `git verify-commit HEAD`). Puis retire la clé de l'agent (`ssh-add -d`) et tente un nouveau commit : que se passe-t-il ? Que se passerait-il dans un script lancé sans terminal ? Recharge la clé.

8. Relis `git config --global --list` : chaque ligne doit pouvoir être justifiée.

**Critères de réussite**
- [ ] `git config --global user.email` vaut `<MOI>@medisphere.internal`, `WB_MOI` est renseigné dans `lab/lab.env`.
- [ ] `init.defaultBranch` vaut `main` ; un comportement de `pull` explicite est choisi ; `fetch.prune`, `push.autoSetupRemote`, `merge.conflictStyle` et `diff.algorithm` sont fixés.
- [ ] L'alias `lg` affiche un graphe ; le fichier d'ignorés global contient `.env`.
- [ ] La clé de signature existe, est distincte de la clé de connexion et protégée par une phrase de passe.
- [ ] `gpg.format` vaut `ssh` ; commits et étiquettes sont signés par défaut ; `allowed_signers` contient ta clé publique de signature.
- [ ] `git verify-commit HEAD` réussit dans `~/src/labo-objets`.

**Vérification** : `lab/bin/check 01 03`

<details><summary>Indice 1</summary>

`git help config` documente toutes les clés : cherche `pull.ff`, `pull.rebase`, `fetch.prune`, `push.autoSetupRemote`, `merge.conflictStyle`, `diff.algorithm`, `gpg.format`, `user.signingKey`, `gpg.ssh.allowedSignersFile`, `commit.gpgSign`, `tag.gpgSign`. Un alias qui appelle une sous-commande Git s'écrit sans le mot `git` : `git config --global alias.st 'status -sb'`.
</details>

<details><summary>Indice 2</summary>

Le format d'une ligne de `allowed_signers` est `<principal> [options] <type de clé> <clé publique>` : le principal est l'adresse de l'auteur, l'option qui limite l'usage est `namespaces="git"`. Le fichier `.pub` de ta clé fournit les deux derniers champs.
</details>

<details><summary>Indice 3</summary>

Pour vérifier qu'une clé privée a une phrase de passe, demande à `ssh-keygen` d'en extraire la clé publique avec une phrase de passe vide (`-y -P ''`) : il doit échouer.
</details>

**Pour aller plus loin** (facultatif) : versionne tes fichiers de configuration personnels (`~/.gitconfig`, `~/.config/git/`) dans un dépôt de *dotfiles* privé, sans jamais y mettre de clé privée. Compare la signature SSH avec la signature GPG (gestion des clés, expiration, révocation, outils de vérification).

---

### M01-E04 — Installer GitLab CE sur `git01` avec une PKI provisoire  `LAB` `★★`

> **Ticket PLAT-204** — *De : Claire Morel* — *Cc : Sophie Laurent, Karim Benali*
> Feu vert pour la forge : une VM `git01` dans le VLAN INFRA, GitLab CE installé par le paquet officiel, HTTPS obligatoire. On n'aura notre PKI définitive (step-ca) qu'au module 06 : en attendant, monte une **CA provisoire** avec `openssl` sur `adm01`, propre, documentée, et qu'on pourra retirer sans douleur.
> Karim : installe la **19.3**, pas la dernière. On s'entraînera à monter de version proprement le moment venu (CHG prévu au palier 3).
> Sophie : la clé de la CA ne quitte pas `adm01`, et je veux un certificat serveur de 397 jours maximum.

**Objectifs pédagogiques**
- Créer une autorité de certification minimale et un certificat serveur conformes aux exigences actuelles des navigateurs et des clients TLS (SAN, durée, extensions).
- Ajouter un hôte permanent au socle en respectant toutes les conventions (VMID, VNet, DNS, alias, étiquettes, documentation).
- Installer GitLab CE *omnibus* en version choisie, avec une configuration minimale lisible, adaptée à 8 Go de mémoire.
- Vérifier l'installation de bout en bout : services, TLS, mémoire, santé applicative.

**Prérequis** : M01-E03, M00-E31 (temps synchronisé), M00-E50 (socle livré).
**Durée indicative** : 4 h (dont une demi-heure d'attentes).

**Contexte technique**

*La VM*

| Paramètre | Valeur |
|---|---|
| VMID / nom | 1004 / `git01`, clone **complet** du template 9000 sur `local-nvme`, pool `lab` |
| Ressources | 4 vCPU, 8192 Mo **fixes** (pas de *ballooning* : GitLab supporte mal qu'on lui reprenne de la mémoire), disque agrandi à 60 Go |
| Réseau | `net0` VirtIO sur le VNet `vinfra` ; `ipconfig0` : 10.10.20.12/24, passerelle 10.10.20.1 |
| Étiquettes | `socle`, `role-gitlab` |
| Démarrage | automatique, **après** `dns01` (ordre 4) |
| DNS | `git01.par1.medisphere.internal` → 10.10.20.12 (A et PTR) dans `/etc/dnsmasq.d/medisphere.conf` de `dns01` |
| Accès SSH depuis `adm01` | alias `git01` (HostName 10.10.20.12, utilisateur `admin`), comme les autres VMs du socle |
| Temps | client chrony de 10.10.20.1, comme toute VM d'INFRA (procédure de M00-E31) |
| Swap | fichier `/swapfile` de 4 Go, `vm.swappiness=10` (recommandations de la documentation « mémoire contrainte ») |

*La PKI provisoire (sur `adm01`)*

| Élément | Exigence |
|---|---|
| Dossier | `~/pki-provisoire/`, mode 700 ; fichiers de clés en 600 |
| Clé de la CA | `ca.key` : RSA 4096 **ou** ECDSA P-256, au choix (justifie le tien) |
| Certificat de la CA | `ca.crt` : sujet `CN=MédiSphère CA provisoire, O=MédiSphère`, validité 2 ans, `basicConstraints = critical, CA:true`, `keyUsage = critical, keyCertSign, cRLSign` |
| Clé et certificat de `git01` | `git01.key` (600), `git01.crt` : validité **397 jours au plus**, SAN `DNS:git01.par1.medisphere.internal`, `DNS:git01`, `IP:10.10.20.12` ; `extendedKeyUsage = serverAuth` ; `basicConstraints = CA:false` |
| Racine de confiance | `ca.crt` installé sous `/usr/local/share/ca-certificates/medisphere-provisoire.crt` sur `adm01` et `git01` (puis `runner01` en E23), suivi de `update-ca-certificates` |

*GitLab*

| Élément | Valeur |
|---|---|
| Paquet | `gitlab-ce`, dépôt officiel `packages.gitlab.com` pour Debian 13 ; **dernière version 19.3.x** ; mises à jour automatiques bloquées (`apt-mark hold`) |
| URL externe | `https://git01.par1.medisphere.internal` |
| Let's Encrypt | désactivé explicitement |
| Certificat | `/etc/gitlab/ssl/git01.par1.medisphere.internal.crt` (certificat serveur **suivi** du certificat de la CA) et `.key` (600) |
| Profil mémoire | réglages de la page « Running GitLab in a memory-constrained environment » de la documentation officielle : Puma en mode simple, concurrence de Sidekiq réduite, limites de Gitaly, `MALLOC_CONF` |
| Supervision embarquée | **désactivée** : Prometheus, les *exporters*, Alertmanager (l'E30 réactivera seulement l'utile) ; agent Kubernetes (`gitlab_kas`) désactivé |
| Courriel | aucun serveur SMTP : envoi de courriels désactivé dans `gitlab.rb` |
| Confiance interne | la racine provisoire est aussi déposée dans `/etc/gitlab/trusted-certs/` (GitLab embarque son propre magasin de certificats) |

> ⚠️ **Attention** : `git01` consomme 8 Go **réservés** sur `pve01`. Vérifie la mémoire disponible avant de créer la VM, en tenant compte de tes VMs perso et du profil lourd éventuellement actif (PLAN §3.3). Si la marge est insuffisante, arrête d'abord le profil lourd ; ne descends pas sous 8 Go pour GitLab.

**Travail demandé**

*A. PKI provisoire (sur `adm01`)*

1. Crée `~/pki-provisoire/` avec les bons droits **avant** d'y générer quoi que ce soit (pense à `umask`).
2. Génère la clé et le certificat auto-signé de la CA. Rédige un fichier de configuration OpenSSL plutôt que d'empiler des options en ligne de commande : il documente ce que tu as fait et se rejoue. Note dans ton journal ton choix d'algorithme.
3. Génère la clé de `git01`, une demande de certificat, puis signe-la avec la CA en appliquant les extensions du tableau.
4. Vérifie : `openssl x509 -noout -text` sur les deux certificats (extensions, dates, sujet, émetteur) et `openssl verify -CAfile ca.crt git01.crt`.
5. Installe la racine sur `adm01` et vérifie qu'elle est dans le magasin du système (`/etc/ssl/certs/`).
6. Réponds dans ton journal : pourquoi 397 jours ? Pourquoi les noms dans le SAN et pas seulement dans le CN ? Pourquoi `CA:false` sur le certificat serveur ? Que pourrait faire un attaquant qui volerait `ca.key` ?

*B. La VM et son intégration au socle*

7. Vérifie que le VMID 1004 et l'adresse 10.10.20.12 sont libres, et que `pve01` a la mémoire nécessaire.
8. Crée la VM depuis `adm01`, à la manière de M00-E12 :
   ```
   admin@adm01:~$ ssh pve01 qm clone 9000 1004 --name git01 --pool lab --full 1 --storage local-nvme
   admin@adm01:~$ ssh pve01 qm set 1004 --cores 4 --memory 8192 --balloon 0 --tags "socle;role-gitlab" \
       --net0 virtio,bridge=vinfra --ipconfig0 ip=10.10.20.12/24,gw=10.10.20.1 \
       --onboot 1 --startup order=4
   admin@adm01:~$ ssh pve01 qm disk resize 1004 scsi0 60G
   admin@adm01:~$ ssh pve01 qm start 1004
   ```
   (Remplace `local-nvme` par ton stockage si tu l'as déclaré autrement dans `WB_STORAGE_NVME`.)
9. Déclare `git01` dans le DNS de `dns01` (A et PTR, une seule ligne), recharge dnsmasq et vérifie les deux résolutions depuis `adm01`.
10. Ajoute l'alias `git01` à `~/.ssh/config`, connecte-toi, vérifie la fin de cloud-init, l'agent QEMU, la taille du système de fichiers racine.
11. Configure chrony (serveur 10.10.20.1), le fichier de swap et `vm.swappiness`, de façon persistante.

*C. GitLab*

12. Installe la racine provisoire sur `git01`, puis dépose le certificat et la clé du serveur aux emplacements attendus, avec les bons droits. Le fichier `.crt` contient la **chaîne** : certificat de `git01`, puis certificat de la CA.
13. Ajoute le dépôt de paquets officiel. Le script d'installation de GitLab est conçu pour un `curl … | sudo bash` : **ne l'exécute pas à l'aveugle**. Télécharge-le, lis ce qu'il fait (quels fichiers il crée, quelle clé il importe), puis exécute-le.
   ```
   admin@git01:~$ curl -fsSLo /tmp/script.deb.sh https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh
   admin@git01:~$ less /tmp/script.deb.sh
   ```
14. Liste les versions disponibles (`apt-cache madison gitlab-ce`) et repère la dernière 19.3.x. Note-la.
15. **Avant** d'installer le paquet, écris `/etc/gitlab/gitlab.rb` (dossier `/etc/gitlab` en 755, fichier en 600, propriétaire root) : un fichier **court**, commenté, qui ne contient que ce qui s'écarte des valeurs par défaut et répond au tableau ci-dessus. Va chercher les noms exacts des réglages dans la documentation officielle (liens en fin d'exercice) : n'invente aucune clé.
16. Installe la version notée, bloque-la, puis applique la configuration :
   ```
   admin@git01:~$ sudo EXTERNAL_URL="https://git01.par1.medisphere.internal" apt-get install gitlab-ce=<VERSION>
   admin@git01:~$ sudo apt-mark hold gitlab-ce
   admin@git01:~$ sudo gitlab-ctl reconfigure
   ```
   `<VERSION>` est la chaîne complète affichée par `apt-cache madison` (forme `19.3.X-ce.0`). L'installation et la première configuration prennent plusieurs minutes.
17. Vérifie :
   - les services (`sudo gitlab-ctl status`) : lesquels tournent, lesquels sont absents grâce à ta configuration ?
   - l'auto-diagnostic : `sudo gitlab-rake gitlab:check SANITIZE=true` ;
   - depuis `adm01`, le TLS **sans** option `-k` : `curl -sSI https://git01.par1.medisphere.internal/users/sign_in` et `openssl s_client -connect git01.par1.medisphere.internal:443 -verify_return_error </dev/null` ;
   - la mémoire au repos (`free -h`) dix minutes après le démarrage. Note le chiffre : l'E30 le comparera.
18. Lis le mot de passe initial de `root` (`/etc/gitlab/initial_root_password`), connecte-toi une première fois depuis ton navigateur (VPN actif) et **change-le immédiatement**. Range le nouveau dans ton gestionnaire de mots de passe. La suite de l'administration est l'objet de l'E05.
   > ⚠️ **Attention** : ce fichier contient un mot de passe administrateur en clair. GitLab le supprime lui-même lors d'une reconfiguration lancée plus de 24 h après l'installation ; ne le copie nulle part.
19. **Documentation.** Dans `~/medisphere` (encore local), ajoute `git01` à `docs/socle/inventaire.md` (VM, accès, secrets : *emplacements* seulement, la CA provisoire) et ses flux à `docs/socle/matrice-flux.md` (accès depuis MGMT et le VPN, sortie Internet, DNS, NTP), puis commite. Le push viendra en E06.

**Critères de réussite**
- [ ] La VM 1004 `git01` est un clone complet du pool `lab`, étiquetée `socle` et `role-gitlab`, 4 vCPU, 8192 Mo sans *ballooning*, disque ≥ 60 Go, sur `vinfra` en 10.10.20.12/24, démarrage automatique après `dns01`.
- [ ] `git01.par1.medisphere.internal` résout en 10.10.20.12 et 10.10.20.12 en `git01.par1.medisphere.internal.` ; `ssh git01 sudo -n true` fonctionne ; chrony est synchronisé sur 10.10.20.1 ; le swap est actif.
- [ ] `~/pki-provisoire` est en 700, `ca.key` en 600 ; `ca.crt` est un certificat de CA (`CA:TRUE`, critique) ; le certificat servi par `git01` est émis par la CA provisoire, porte les trois SAN et dure 397 jours au plus.
- [ ] La racine provisoire est installée sur `adm01` et `git01` (magasin système) et dans `/etc/gitlab/trusted-certs/`.
- [ ] `gitlab-ce` 19.x est installé (19.3.x tant que l'E29 n'est pas faite) et bloqué ; tous les services de `gitlab-ctl status` sont `run` ; Prometheus n'en fait pas partie ; Puma tourne en mode simple.
- [ ] Depuis `adm01`, `https://git01.par1.medisphere.internal/users/sign_in` répond 200 **sans désactiver la vérification TLS**.
- [ ] Le mot de passe initial de `root` a été changé.
- [ ] `docs/socle/inventaire.md` et `matrice-flux.md` mentionnent `git01` (commit local).

**Vérification** : `lab/bin/check 01 04`

<details><summary>Indice 1</summary>

Avec un fichier de configuration OpenSSL, une section par usage : `[req]` et `[dn]` pour le sujet, une section d'extensions pour la CA (`v3_ca`), une autre pour le serveur (`v3_serveur`). On les applique avec `openssl req -x509 -config … -extensions …` pour la CA, et `openssl x509 -req … -extfile … -extensions …` pour signer la demande du serveur. Le caractère « é » du sujet demande l'option `-utf8` (ou `string_mask = utf8only` et `utf8 = yes` dans la configuration). Pages utiles : `man openssl-req`, `man openssl-x509`, `man x509v3_config`.
</details>

<details><summary>Indice 2</summary>

Dans `gitlab.rb`, chaque réglage est une affectation Ruby. Une clé affectée deux fois garde la **dernière** valeur : si la documentation te donne deux blocs `gitaly['env'] = {…}`, fusionne-les en un seul. Même remarque pour `gitaly['configuration']`, que d'autres exercices compléteront (E26) : un seul hash, enrichi au fil du temps. La documentation liste les services à désactiver un par un : `prometheus_monitoring['enable'] = false` ne suffit pas à tout couper.
</details>

<details><summary>Indice 3</summary>

Si `gitlab-ctl reconfigure` échoue, la fin de sa sortie nomme la ressource *Chef* en échec et le fichier de journal ; une clé mal orthographiée dans `gitlab.rb` produit une erreur explicite. Si le navigateur refuse le certificat alors que `curl` l'accepte depuis `adm01`, c'est que ton **poste** ne fait pas confiance à la CA provisoire : importe `ca.crt` dans son magasin (ou dans celui du navigateur), en connaissance de cause, et retire-le au M06.
</details>

**Pour aller plus loin** (facultatif) : prends un instantané Proxmox de `git01` juste avant l'installation du paquet, et supprime-le une fois l'E05 validée (un instantané oublié grossit sans fin). Lis la documentation d'`nginx['ssl_protocols']` et des en-têtes HSTS, et note ce que tu durciras en E31. Réfléchis aux *name constraints* (`nameConstraints`) pour limiter une CA à `medisphere.internal` : pourquoi le SAN `git01` imposé ici serait-il alors refusé ?
Documentation : <https://docs.gitlab.com/install/package/debian/>, <https://docs.gitlab.com/omnibus/settings/memory_constrained_envs/>, <https://docs.gitlab.com/omnibus/settings/ssl/>, <https://docs.gitlab.com/omnibus/settings/smtp/>.

---

### M01-E05 — Premiers pas d'administration GitLab : comptes, groupes, inscriptions  `LAB` `★`

> **Ticket SEC-205** — *De : Sophie Laurent*
> Avant que quiconque pousse une ligne de code sur `git01` : pas d'inscription libre, pas de projet public, pas d'usage quotidien de `root`, des comptes nominatifs pour toute l'équipe et des jetons à portée minimale avec une date d'expiration. Et des groupes privés : le code de l'infrastructure n'est pas une vitrine.

**Objectifs pédagogiques**
- Sécuriser une instance GitLab neuve (inscriptions, visibilité par défaut, compte de bris de glace).
- Gérer comptes, groupes et rôles, dans l'interface **et** par l'API.
- Créer et ranger des jetons d'accès personnels à portée minimale.

**Prérequis** : M01-E04.
**Durée indicative** : 1 h 30.

**Contexte technique**

*Comptes* : les personnages sont listés dans [`ressources/M01-E05/personnages.tsv`](../ressources/M01-E05/personnages.tsv) (identifiant, nom, adresse, rôle dans chaque groupe). Ils n'auront jamais de mot de passe connu : les scripts du workbook agiront « en leur nom » avec des **jetons d'emprunt d'identité** (*impersonation tokens*), créés par ton jeton d'administration. Pas de SMTP : les adresses `@medisphere.internal` ne reçoivent rien.

*Groupes et rôles*

| Compte | `plateforme` | `formation` |
|---|---|---|
| `<MOI>` | Owner (créateur du groupe) | Owner (créateur du groupe) |
| `karim.benali` | Maintainer | Maintainer |
| `lucas.martin` | Developer | Developer |
| `claire.morel`, `sophie.laurent`, `nadia.roussel`, `julien.petit` | Reporter | — |

Les deux groupes sont **privés**. `plateforme` accueillera les projets de l'équipe (`plateforme/medisphere` en E06, puis `outils`, `images`, `ansible`, `infra`… aux modules suivants) ; `formation` est le bac à sable des exercices Git.

*Jetons de ton compte `<MOI>`* (et non de `root`)

| Nom du jeton | Portée | Expiration | Fichier sur `adm01` |
|---|---|---|---|
| `workbook-checks` | `read_api` uniquement | 1 an au plus | `~/.config/workbook/gitlab-checks.token` |
| `workbook-admin` | `api` | 90 jours au plus | `~/.config/workbook/gitlab-admin.token` |

Les deux fichiers sont en 600, sans retour à la ligne superflu, et ne contiennent que le jeton.

*Paramètres de l'instance* (*Admin → Settings → General*) : inscriptions désactivées ; niveau de visibilité **Public** interdit ; visibilité par défaut des nouveaux projets et groupes : **Private**.

**Travail demandé**

1. Connecté en `root`, applique les paramètres de l'instance. Vérifie en navigation privée que la page de connexion ne propose plus de créer un compte.
2. Crée ton compte `<MOI>` dans *Admin → Users* : nom complet, identifiant `<MOI>`, adresse `<MOI>@medisphere.internal` (la même que `git config user.email`), niveau d'accès **Administrator**. Sans SMTP, aucun lien d'activation ne partira : fixe un mot de passe provisoire depuis la fiche du compte, et vérifie que l'adresse est confirmée (sinon, confirme-la depuis la fiche).
3. Connecte-toi avec `<MOI>` (navigation privée), change le mot de passe provisoire. Déconnecte `root` : désormais tu ne l'utilises plus.
4. Avec `<MOI>`, crée les deux jetons du tableau (*Avatar → Edit profile → Access → Personal access tokens*, menu *Generate token → Legacy token* : un jeton à portées classiques ; les jetons « à granularité fine » sont une autre famille, non utilisée ici). Range-les immédiatement dans leurs fichiers, sans les faire passer par l'historique du shell ni par un fichier temporaire lisible. Teste le jeton des checks :
   ```
   admin@adm01:~$ curl -sS --header "PRIVATE-TOKEN: $(<~/.config/workbook/gitlab-checks.token)" \
       https://git01.par1.medisphere.internal/api/v4/user | jq '{username, is_admin}'
   ```
   Note dans ton journal pourquoi ce jeton ne peut pas créer de projet, même si ton compte est administrateur.
5. **Par l'API**, avec le jeton d'administration, crée les six comptes de `personnages.tsv` : sans confirmation d'adresse, avec un mot de passe aléatoire que personne ne connaîtra. Écris une petite boucle sur le fichier plutôt que six commandes. Documentation : *Users API → Create a user*.
6. Crée les groupes `plateforme` et `formation` (interface ou API) et affecte les membres selon le tableau. Pour les niveaux d'accès dans l'API, cherche la table des valeurs numériques dans la documentation des membres.
7. Supprime `/etc/gitlab/initial_root_password` sur `git01` (le mot de passe a changé, le fichier n'a plus de raison d'exister).
8. Lance le check.

**Critères de réussite**
- [ ] Les inscriptions sont fermées, la visibilité **Public** est interdite, les nouveaux projets sont privés par défaut.
- [ ] Ton compte `<MOI>` est administrateur, son adresse est `<MOI>@medisphere.internal`, identique à ton `user.email` Git.
- [ ] Le jeton des checks n'a que la portée `read_api` et expire dans moins d'un an ; le jeton `workbook-admin` a la portée `api` et expire dans moins de 90 jours ; les deux fichiers sont en 600 dans un dossier en 700.
- [ ] Les six comptes des personnages existent et sont actifs.
- [ ] Les groupes `plateforme` et `formation` sont privés et leurs membres ont les rôles du tableau.
- [ ] `/etc/gitlab/initial_root_password` n'existe plus.

**Vérification** : `lab/bin/check 01 05`

<details><summary>Indice 1</summary>

Pour écrire un jeton dans un fichier sans qu'il passe par l'historique ni par un fichier lisible par d'autres : `umask 077` dans le shell courant, puis une commande qui lit l'entrée standard (`cat > fichier`), dans laquelle tu colles le jeton, terminée par `Ctrl+D`. Contrôle avec `ls -l` et `wc -c`.
</details>

<details><summary>Indice 2</summary>

`POST /users` accepte `force_random_password` et `skip_confirmation`. Avec `curl`, envoie les paramètres en `--data-urlencode` (les noms contiennent des espaces et des accents) et ajoute `--fail-with-body` pour qu'une erreur de l'API fasse échouer la commande. Dans une boucle `while read`, `IFS=$'\t'` découpe sur les tabulations.
</details>

<details><summary>Indice 3</summary>

Les niveaux d'accès s'expriment par des entiers : 10, 20, 30, 40, 50 (voir *Group and project members API*, *Roles*). Les membres d'un groupe s'ajoutent par `POST /groups/:id/members` avec `user_id` et `access_level` ; l'identifiant numérique d'un compte s'obtient par `GET /users?username=…`.
</details>

**Pour aller plus loin** (facultatif) : active l'authentification à deux facteurs pour `<MOI>` ; lis la documentation du « mode administrateur » (*Admin Mode*), qui impose une ré-authentification avant les actions d'administration, et ce qu'il change pour les jetons (portée `admin_mode`). Ne l'active pas maintenant : les scripts du workbook supposent qu'il est désactivé.

---

### M01-E06 — Migrer `~/medisphere` vers GitLab sans rien perdre  `LAB` `★`

> **Ticket CHG-206** — *De : Claire Morel*
> Le dépôt de documentation du socle doit vivre sur la forge : projet `plateforme/medisphere`, **tout l'historique**, l'étiquette `socle-v0`, et rien qui n'ait à y être. Sophie vérifiera qu'aucun secret n'est publié : un push, ça ne se reprend pas vraiment.

**Objectifs pédagogiques**
- Préparer une migration de dépôt : sauvegarde, inventaire des références, recherche de secrets et de gros fichiers dans **tout** l'historique.
- Configurer l'accès Git en SSH à GitLab et vérifier l'identité du serveur.
- Publier branches et étiquettes, et prouver que rien n'a été perdu.

**Prérequis** : M01-E05.
**Durée indicative** : 1 h.

**Contexte technique**
- Dépôt source : `~/medisphere` sur `adm01` (`WB_DEPOT`), créé en M00-E25, étiqueté `socle-v0` en M00-E50, enrichi en E04 (documentation de `git01`).
- Projet cible : `plateforme/medisphere`, **vide** (sans README initial), privé, description « Documentation et code du socle MédiSphère ».
- URL Git : `git@git01.par1.medisphere.internal:plateforme/medisphere.git`. L'utilisateur SSH est toujours `git` ; GitLab t'identifie par ta **clé**. Ta clé de connexion `~/.ssh/id_ed25519.pub` (pas la clé de signature) est déclarée dans ton profil GitLab avec l'usage *Authentication*.
- Le dépôt a été créé en M00 avec Git 2.47 : selon ta configuration de l'époque, sa branche s'appelle peut-être `master`. Elle doit s'appeler `main` sur la forge.

**Travail demandé**

1. **Sauvegarde avant migration** : crée un *bundle* de tout le dépôt hors du dépôt (`git bundle create ~/medisphere-avant-migration.bundle --all`) et vérifie-le (`git bundle verify`).
2. **Inventaire** : branches, étiquettes (légères ou annotées ?), nombre de commits accessibles depuis toutes les références, état de l'arbre de travail, intégrité (`git fsck --full`). Note-le : c'est ta référence pour prouver l'absence de perte.
3. **Ce que tu vas publier** : cherche dans **tout l'historique** (pas seulement dans les fichiers actuels) les motifs de secrets évidents (blocs `PRIVATE KEY`, `PrivateKey =` de WireGuard, `token`, `password`, `secret` suivis d'une valeur) et les objets de plus de 1 Mo. Si tu trouves un secret : **arrête-toi**, ne pousse rien, et lis l'E17 avant de continuer.
4. Si la branche s'appelle `master`, renomme-la en `main`.
5. Déclare ta clé de connexion dans ton profil GitLab. Avant la première connexion SSH à `git01.par1.medisphere.internal`, récupère l'empreinte de la clé d'hôte ed25519 **par un autre canal** (sur `git01` lui-même, par ton alias d'administration) et compare-la à celle que `ssh` te présentera. Teste : `ssh -T git@git01.par1.medisphere.internal`.
6. Crée le projet vide `plateforme/medisphere` dans GitLab (décoche l'initialisation avec un README).
7. Ajoute le remote `origin`, pousse `main` avec suivi, puis **toutes** les autres branches et **toutes** les étiquettes. Explique dans ton journal la différence entre `git push --tags` et `git push --follow-tags`.
8. **Preuve d'absence de perte** : compare les références locales et distantes (`git show-ref` et `git ls-remote origin`), clone le projet dans un dossier temporaire, lance `git fsck` et compare le nombre de commits avec ton inventaire. Supprime le clone temporaire.
9. Vérifie dans l'interface : branche par défaut `main`, étiquette `socle-v0`, nombre de commits, visibilité privée.
10. Ajoute dans `docs/socle/README.md` l'adresse du projet et la commande de clonage, commite et pousse : ton dépôt local suit désormais la forge.

**Critères de réussite**
- [ ] Le projet `plateforme/medisphere` est privé, sa branche par défaut est `main`.
- [ ] `~/medisphere` a pour `origin` le projet sur `git01` ; `main` locale est poussée (rien en avance).
- [ ] L'étiquette `socle-v0` existe sur la forge et désigne le même objet qu'en local (même type, même empreinte).
- [ ] Ta clé de connexion est déclarée dans ton profil ; `ssh -T git@git01.par1.medisphere.internal` t'accueille par ton identifiant.
- [ ] `docs/socle/inventaire.md` sur la forge mentionne `git01` et 10.10.20.12.
- [ ] Un bundle de sauvegarde existe hors du dépôt.

**Vérification** : `lab/bin/check 01 06`

<details><summary>Indice 1</summary>

Pour chercher dans tout l'historique : `git log --all -p` produit le contenu de chaque modification de chaque commit, filtrable par `grep -E`. Pour les gros objets : `git rev-list --objects --all` liste tous les objets avec leur chemin ; `git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)'` donne leur taille.
</details>

<details><summary>Indice 2</summary>

La clé d'hôte que présente `git@git01…` est celle du sshd du système de `git01` : `ssh-keygen -lf` sur le fichier public correspondant dans `/etc/ssh/` donne l'empreinte à comparer. Ton `~/.ssh/config` contient un bloc `Host git01` (utilisateur `admin`) : l'URL Git utilise le nom complet, qui ne correspond pas à cet alias. C'est voulu : `git@` ne doit pas hériter de l'utilisateur `admin`.
</details>

**Pour aller plus loin** (facultatif) : compare avec un `git push --mirror` (qu'aurait-il poussé de plus, et quel danger dans l'autre sens ?) et avec l'importation de projet de GitLab par URL.

---

### M01-E07 — Lire et construire un historique : branches, fusions, graphe  `LAB` `★`

> **Ticket PLAT-207** — *De : Karim Benali*
> On a récupéré d'InfoGér un petit outil d'inventaire, `inventaire`, avec son historique Git. Lucas et moi y avons déjà travaillé. Je t'en ai fait une copie d'exercice : publie-la dans le bac à sable `formation/git-labo`, puis dis-moi ce que tu lis dans cet historique. Ensuite, montre-moi que tu sais intégrer deux branches de deux façons différentes, en le faisant exprès.

**Objectifs pédagogiques**
- Lire un historique non linéaire : graphe, parents d'une fusion, branches fusionnées ou non, plages de commits.
- Retrouver l'origine d'une ligne ou d'une chaîne (`blame`, recherche « pioche » `-S`).
- Produire volontairement une avance rapide et une fusion avec commit de fusion, et savoir les reconnaître.

**Prérequis** : M01-E06.
**Durée indicative** : 2 h.

**Contexte technique**
- Script de fabrication : [`ressources/M01-E07/fabriquer-depot.sh`](../ressources/M01-E07/fabriquer-depot.sh). Il construit le dépôt **en local** dans `~/src/git-labo`, avec des auteurs et des dates fixés : ton historique est identique, empreinte pour empreinte, à celui du corrigé.
- Projet cible : `formation/git-labo`, privé, **vide**. C'est un bac à sable : sa branche `main` n'est pas protégée, et plusieurs exercices du module y créeront des branches `eXX/…`.

**Travail demandé**

1. Lis le script, puis lance-le :
   ```
   admin@adm01:~$ bash ~/DevOpsPrivateCloud/modules/01-git/ressources/M01-E07/fabriquer-depot.sh
   ```
2. Crée le projet vide `formation/git-labo`, ajoute le remote `origin` à `~/src/git-labo` et publie **toutes** les branches et **toutes** les étiquettes. Vérifie dans l'interface (*Code → Repository graph*).
3. **Lire.** Réponds dans ton journal, en notant pour chaque question la ou les commandes utilisées :
   1. Combien de commits sont accessibles depuis `main` ? Combien sont des commits de fusion ? Combien en compte `main` si l'on ne suit que le **premier parent** de chaque fusion, et que représente cette vue ?
   2. Quelles branches sont entièrement fusionnées dans `main` ? Lesquelles ne le sont pas ?
   3. `correctif/espaces-noms` est fusionnée dans `main`, pourtant aucun commit de fusion ne la mentionne. Comment est-ce possible ? Comment le prouves-tu ?
   4. Quel commit a introduit la variable `SEUIL_ALERTE` ? Qui, quand, avec quel message ? Pourquoi la lecture des messages ne t'aurait-elle pas aidé ?
   5. Qui a écrit la ligne `SEPARATEUR=','` de `conf/inventaire.conf`, dans quel commit ?
   6. Le commit de fusion de `fonction/sortie-json` : quels sont ses deux parents, dans quel ordre, et que signifie cet ordre ? Y a-t-il eu un conflit, et comment a-t-il été résolu ? (Git 2.47 sait montrer une résolution de conflit.)
   7. Quels commits de `fonction/tri` ne sont pas dans `main` ? Quels commits de `main` ne sont pas dans `infoger/ancien-format` ? Donne les deux notations de plage utilisées.
   8. Que s'est-il passé avec « la purge des anciens exports » ? Le code de la purge existe-t-il encore dans l'historique ? Dans l'arbre de travail de `main` ?
   9. `v0.1.0` et `livraison-infoger` : quelle différence de nature ? Qui a créé `v0.1.0`, et quand ?
4. **Marquer.** Pose une étiquette **légère** `e07/seuil` sur le commit trouvé à la question 4, et publie-la.
5. **Construire.** À partir de `main` :
   - crée une branche `e07/ajout-pbs` avec un commit qui ajoute une ligne de ton choix dans `README.md` ;
   - crée une branche `e07/ajout-dns`, partie elle aussi de `main`, avec un commit qui ajoute un fichier `docs/dns.md` ;
   - crée une branche `e07/integration` à partir de `main`, et intègre-y `e07/ajout-pbs` **par avance rapide**, puis `e07/ajout-dns` **par un commit de fusion** (message par défaut) ;
   - publie les trois branches. Ne modifie pas `main`.
6. Affiche le graphe (`git lg` de l'E03) et explique-le à voix haute comme si Karim était à côté de toi : pourquoi n'y a-t-il pas de commit de fusion pour la première intégration ?

**Critères de réussite**
- [ ] `formation/git-labo` est privé et contient les six branches et les trois étiquettes du script.
- [ ] L'étiquette `e07/seuil` est publiée et désigne le commit qui a introduit `SEUIL_ALERTE`.
- [ ] Sur la forge, `e07/integration` se termine par un commit de fusion dont le premier parent est le dernier commit de `e07/ajout-pbs` et le second celui de `e07/ajout-dns`.
- [ ] `e07/ajout-pbs` et `e07/ajout-dns` partent toutes deux de `main` et ne contiennent chacune qu'un commit propre.
- [ ] Ton journal répond aux neuf questions, avec les commandes.

**Vérification** : `lab/bin/check 01 07`

<details><summary>Indice 1</summary>

`git log --oneline --graph --all` (ou ton alias `lg`) donne la vue d'ensemble. `git rev-list --count` compte, avec `--merges` ou `--first-parent` pour filtrer. `git branch --merged main` et `--no-merged main` répondent à la question 2.
</details>

<details><summary>Indice 2</summary>

`git log -S <chaîne>` (*pickaxe*) trouve les commits qui changent le nombre d'occurrences d'une chaîne. `git blame <fichier>` attribue chaque ligne. `A..B` = accessible depuis B mais pas depuis A ; `A...B` = la différence symétrique, à combiner avec `--left-right`. `git show --remerge-diff <fusion>` montre ce que l'auteur de la fusion a changé par rapport à une fusion automatique.
</details>

<details><summary>Indice 3</summary>

Une fusion ne crée pas de commit quand la branche cible n'a pas bougé depuis le départ de la branche fusionnée : Git se contente d'avancer la référence. Pour l'interdire, une option dédiée de `git merge` ; pour l'exiger, une autre. Les deux branches `e07/ajout-*` doivent partir **du même** commit de `main`.
</details>

**Pour aller plus loin** (facultatif) : essaie `git log --graph --simplify-by-decoration --all` et `git log --ancestry-path`. Lis la page `gitrevisions(7)` : `HEAD^2`, `HEAD~3`, `main@{yesterday}`, `:/message`.

---

### M01-E08 — Annuler proprement : `restore`, `reset`, `revert`, `reflog`  `LAB` `★★`

> **Ticket PLAT-208** — *De : Karim Benali*
> Ce qui distingue quelqu'un qui « utilise » Git de quelqu'un qui le maîtrise, c'est la capacité à défaire une erreur sans en créer une pire. J'ai préparé cinq situations réelles, toutes vécues dans l'équipe. Pour chacune : la bonne commande, et surtout **pourquoi pas les autres**.

**Objectifs pédagogiques**
- Choisir l'outil d'annulation selon ce qu'on veut défaire (arbre de travail, index, commit local, commit publié) et selon que c'est publié ou non.
- Récupérer du travail « perdu » grâce au reflog.
- Distinguer réécriture (locale) et annulation par ajout (publiée).

**Prérequis** : M01-E07.
**Durée indicative** : 2 h.

**Contexte technique**
- Script de préparation : [`ressources/M01-E08/fabriquer-situations.sh`](../ressources/M01-E08/fabriquer-situations.sh), à lancer sur ton clone `~/src/git-labo` (arbre propre). Il crée quatre branches `e08/…` à partir de `origin/main` et en **publie une** (`e08/publiee`). La branche active, à la fin, est `e08/travail`.
- Le fichier `secret.env` créé par le script est un faux secret d'exercice. Fais comme s'il était vrai.

> ⚠️ **Attention** : certaines commandes d'annulation détruisent des modifications non commitées sans retour possible (le reflog ne connaît que les commits). Avant chaque commande, demande-toi : « qu'est-ce qui sera perdu si je me trompe ? », et regarde `git status` avant **et** après.

**Travail demandé**

Lance le script, lis sa sortie, puis traite les situations **dans l'ordre**. Pour chacune, note dans ton journal : le diagnostic (commandes et ce qu'elles montrent), la commande choisie, et pourquoi les autres candidates étaient mauvaises.

1. **Situation 1 — une modification involontaire.** Sur `e08/travail`, `README.md` a été modifié par erreur (une ligne en trop). Personne ne veut cette modification. Fais revenir le fichier à son état du dernier commit, sans toucher à rien d'autre.

2. **Situation 2 — une indexation malheureuse.** `secret.env` a été ajouté à l'index. Il ne doit **jamais** être commité, mais le fichier lui-même doit rester sur le disque (une autre personne en a besoin). Retire-le de l'index sans le supprimer, et fais en sorte que l'erreur ne puisse plus se reproduire **dans ce projet** (commit dédié, type `chore`).

3. **Situation 3 — un commit raté, mais pas publié.** Le dernier commit « métier » de `e08/travail` (avant celui de la situation 2) a un message fautif et il lui manque un fichier, `conf/exclusions.conf`, resté non suivi. Corrige ce commit pour que son message soit exactement `fix: correction du filtre d'exclusion` et qu'il contienne le fichier. Attention : le commit de la situation 2 est arrivé par-dessus. L'ordre final de la branche doit être : commit corrigé, puis commit `chore`. Publie ensuite `e08/travail`.

4. **Situation 4 — un brouillon à nettoyer avant revue.** `e08/brouillon` contient trois commits « wip », « wip 2 », « correction faute ». Remplace-les par **un seul** commit propre (`feat: liste d'exclusion de l'inventaire`), avec exactement le même contenu final, **sans** utiliser le rebase interactif (il sera vu en E12). Publie la branche.

5. **Situation 5 — un commit publié à annuler.** Sur `e08/publiee`, déjà publiée et que Karim utilise, le commit « feat: activer la purge automatique des exports » ne devait pas partir. Annule son effet **sans réécrire** l'historique publié, puis publie.

6. **Situation 6 — « tout mon travail a disparu ».** Sur `e08/precieux`, deux commits de travail ont disparu après une mauvaise manipulation. Trouve ce qui s'est passé, récupère les deux commits sur la branche, puis publie-la.

7. **Bilan.** Construis dans ton journal un tableau de décision : « je veux défaire… » (une modification non indexée / une indexation / le dernier commit local / plusieurs commits locaux / un commit publié / une branche déplacée par erreur) → commande → ce qui est perdu en cas d'erreur.

**Critères de réussite**
- [ ] Sur la forge, `e08/travail` a pour avant-dernier commit `fix: correction du filtre d'exclusion`, qui contient `conf/exclusions.conf`, et pour dernier commit un commit `chore` qui fait ignorer `secret.env` ; `secret.env` n'apparaît dans aucun commit, et `README.md` n'a pas la ligne parasite.
- [ ] `secret.env` existe toujours dans `~/src/git-labo`.
- [ ] Sur la forge, `e08/brouillon` compte un seul commit de plus que `main`, avec le contenu des trois commits d'origine.
- [ ] Sur la forge, `e08/publiee` contient toujours ses trois commits d'origine, suivis d'un commit qui annule la purge automatique.
- [ ] Sur la forge, `e08/precieux` contient les deux commits « travail précieux ».
- [ ] Ton journal contient le tableau de décision.

**Vérification** : `lab/bin/check 01 08`

<details><summary>Indice 1</summary>

Reprends les « trois arbres ». `git restore` copie de l'index vers l'arbre de travail, ou (avec `--staged`) de `HEAD` vers l'index. `git reset` déplace la branche courante ; `--soft`, `--mixed` et `--hard` disent jusqu'où il recopie ensuite. `git revert` crée un nouveau commit inverse. Un fichier `.gitignore` versionné vaut pour toute l'équipe ; `.git/info/exclude`, seulement pour toi.
</details>

<details><summary>Indice 2</summary>

Situation 3 : tu ne peux pas « amender » un commit qui n'est plus le dernier… sauf à retirer d'abord le commit qui est par-dessus (note son empreinte avant !), puis à le réappliquer par-dessus le commit corrigé : `git cherry-pick` recopie un commit existant. Pour retirer un commit sans perdre les fichiers non suivis ni les modifications locales, regarde l'option `--keep` de `git reset`. Situation 4 : un `reset` qui garde tout dans l'index, puis un commit.
</details>

<details><summary>Indice 3</summary>

Situation 6 : `git reflog show e08/precieux` liste les positions successives de la branche ; `e08/precieux@{N}` désigne l'une d'elles. Pour remettre la branche sur un commit précis sans perdre de modification en cours, assure-toi d'abord que l'arbre de travail est propre.
</details>

**Pour aller plus loin** (facultatif) : provoque un `reset --hard` sur des modifications **non commitées** dans un dossier jetable, puis cherche à les récupérer (`git fsck --lost-found`) : qu'est-ce qui revient, qu'est-ce qui est perdu, et pourquoi `git stash` aurait tout changé ?

---

### M01-E09 — Questions : modèles de branches et choix pour l'équipe Plateforme  `Q` `★★`

> **Ticket PLAT-209** — *De : Claire Morel* — *Cc : Karim Benali*
> Avant de fixer les règles de la forge (protection de `main`, méthode de fusion, versions), je veux qu'on se mette d'accord sur notre façon de travailler. Karim penche pour un modèle très simple, Julien m'explique que son équipe de développement fait du Git Flow depuis des années. Prépare-moi une réponse argumentée : on en discutera en réunion d'équipe, et la décision sera appliquée au palier suivant.

**Objectifs pédagogiques**
- Connaître les principaux modèles de branches et le contexte pour lequel chacun a été conçu.
- Comprendre les méthodes de fusion de GitLab et leurs effets sur l'historique et l'outillage.
- Argumenter un choix pour une équipe d'infrastructure.

**Prérequis** : M01-E07, M01-E08 ; lecture de la documentation GitLab sur les méthodes de fusion (*Merge methods*).
**Durée indicative** : 1 h 30.

**Contexte** : l'équipe Plateforme compte cinq personnes (dont un stagiaire). Ses dépôts contiennent de la documentation, des scripts, des rôles Ansible, du code OpenTofu et des gabarits CI. Il n'y a qu'**une** plateforme de production par site ; les modules réutilisables (rôles, modules OpenTofu, gabarits CI) sont **consommés par version** par d'autres dépôts. Les versions seront produites par semantic-release (E25).

**Travail demandé**

Réponds par écrit aux 15 questions.

1. Décris Git Flow : branches permanentes, branches temporaires, circulation d'un correctif urgent. Pour quel type de logiciel a-t-il été conçu ? Que dit aujourd'hui son auteur de son usage pour des applications livrées en continu ?
2. Décris GitHub Flow. Quelle hypothèse sur la mise en production fait-il ?
3. Décris le développement « sur le tronc » (*trunk-based development*). Quelle durée de vie pour une branche ? Comment livre-t-on une fonctionnalité inachevée ?
4. GitLab propose des branches d'environnement (`staging`, `production`…) dans sa présentation du « GitLab Flow ». Pourquoi est-ce une mauvaise idée pour du code d'infrastructure (OpenTofu, Ansible) ? Que proposes-tu à la place pour distinguer les environnements ?
5. *(QCM)* Une branche de fonctionnalité de l'équipe Plateforme vit trois semaines. Quel est le risque principal ?
   - A. Le dépôt grossit inutilement
   - B. Les conflits d'intégration et la revue d'une MR énorme, avec un historique qui diverge de plus en plus de la réalité de `main`
   - C. GitLab supprime automatiquement les branches inactives
   - D. Aucun, tant que la branche est poussée chaque jour
6. GitLab CE propose trois méthodes de fusion : *Merge commit*, *Merge commit with semi-linear history*, *Fast-forward merge*. Pour chacune, dessine le graphe obtenu après la fusion de deux MR successives, et dis ce qu'elle exige de la branche source.
7. L'option *squash* : qu'apporte-t-elle, que fait-elle perdre ? Quel message porte le commit obtenu, et quelle conséquence avec semantic-release ?
8. Pour mettre ta branche à jour avec `main` avant la revue : rebase ou fusion de `main` dans ta branche ? Dans quel cas l'un est-il interdit ?
9. Quel impact la méthode de fusion a-t-elle sur `git bisect` et sur `git log --first-parent main` ?
10. Quand une équipe a-t-elle besoin de **branches de maintenance** ? Comment s'y propage un correctif ? Quelle convention de nommage permet à semantic-release de publier des versions de maintenance ?
11. Qui pose les étiquettes de version dans le modèle cible, et pourquoi doivent-elles être protégées ?
12. *(QCM)* Laquelle de ces règles est **impossible** à imposer avec GitLab CE seul ?
    - A. Personne ne pousse directement sur `main`
    - B. Une MR ne peut être fusionnée que si son pipeline a réussi
    - C. Une MR doit être approuvée par au moins un autre membre que son auteur
    - D. Toutes les discussions d'une MR doivent être résolues avant la fusion
13. Comment compenses-tu, dans l'équipe, l'absence de la règle trouvée à la question 12 ?
14. Propose, en dix lignes au plus, le modèle de branches et de fusion de l'équipe Plateforme : branches autorisées et leur nommage, durée de vie, méthode de fusion, mise à jour des branches, étiquettes, maintenance.
15. Réponds à Julien, qui utilise Git Flow pour MédiAgenda : faut-il que son équipe change de modèle ? Sous quelles conditions Git Flow reste-t-il défendable ?

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 15 questions avant d'ouvrir le corrigé.
- [ ] Ta proposition (question 14) tient en dix lignes et chaque choix y est justifié.
- [ ] Tu as noté avec la grille du corrigé (sur 30) et listé les points à revoir avant l'E11.

<details><summary>Indice 1</summary>

Pour les méthodes de fusion, la documentation de GitLab (*Merge requests → Methods*) contient des schémas. Distingue bien deux choses : ce que la méthode **crée** (un commit de fusion ou non) et ce qu'elle **exige** (une branche source à jour par rapport à la cible, ou non).
</details>

<details><summary>Indice 2</summary>

Raisonne à partir du contexte : qu'est-ce qui est « livré » par l'équipe Plateforme ? Un état de l'infrastructure (appliqué en continu depuis `main`) et des modules versionnés (consommés par étiquette). Il n'y a pas de « version 2 de la production » à maintenir en parallèle.
</details>

**Pour aller plus loin** (facultatif) : lis l'article original *A successful Git branching model* (Vincent Driessen, 2010) et sa note de 2020 ; le site <https://trunkbaseddevelopment.com/> ; la page *Merge methods* de la documentation GitLab.
