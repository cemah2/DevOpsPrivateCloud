# Module 01 — Palier 1 : Découverte — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Ce corrigé suit l'ordre de l'énoncé. Pour les questionnaires (E01, E09), chaque réponse est argumentée et les QCM expliquent pourquoi les autres options sont fausses. Pour les labs, la section **Solution** donne une démarche complète ; les scripts et fichiers complets sont dans [`fichiers/`](fichiers/).

Points non testés en conditions réelles au moment de la rédaction, à vérifier sur ta version et à signaler s'ils diffèrent :
- E04 : le paquet `gitlab-ce` conserve un `/etc/gitlab/gitlab.rb` créé **avant** son installation (comportement documenté pour les mises à jour, déduit pour une première installation) ; le nom exact du fichier de dépôt créé par `script.deb.sh` sur Debian 13 ; le titre des processus Puma en mode simple (utilisé par le check) ; la mémoire consommée au repos avec ce profil.
- E05 : la lecture de `GET /application/settings` avec un jeton `read_api` d'administrateur (le check a un repli en base si elle est refusée) ; la confirmation automatique de l'adresse d'un compte créé depuis *Admin → Users*.
- E06 : la forme exacte du champ `key` renvoyé par `GET /user/keys` (avec ou sans commentaire ; le check compare seulement la partie base64).

---

### M01-E01 — Test de positionnement Git

**Barème** : chaque question vaut 2 points. 2 = réponse complète et justifiée ; 1 = idée juste mais incomplète (QCM juste sans justification, une seule des deux situations…) ; 0 = faux ou blanc. Total sur 50.

**Réponses argumentées**

**1. `fetch` et `pull`.** `git fetch` télécharge les objets et met à jour les **références de suivi** (`origin/main`) ; il ne touche ni à tes branches ni à ton arbre de travail. `git pull` = `fetch` puis **intégration** de la branche amont dans la branche courante. Depuis Git 2.33/2.34, sans réglage explicite (`pull.rebase`, `pull.ff`), `pull` fait une avance rapide si c'est possible ; si les historiques ont **divergé**, il refuse (« *Need to specify how to reconcile divergent branches* ») et te demande de choisir entre fusion, rebase et avance rapide seule. C'est pour cela que l'E03 fixe un comportement explicite. Les anciennes versions fusionnaient en silence et parsemaient l'historique de commits « *Merge branch 'main' of …* ».

**2. Réponse B.** Un commit contient l'empreinte d'**un arbre racine** (l'instantané complet du projet), zéro, un ou plusieurs parents, auteur et validateur avec leurs dates, le message (et éventuellement une signature). A est faux : Git stocke des **instantanés**, pas des différences ; les diffs sont calculés à la volée (la compression delta des *packfiles* est une optimisation de stockage, sans rapport avec le modèle). C est faux : les fichiers inchangés ne sont pas recopiés, l'arbre pointe sur les mêmes blobs. D est faux pour la même raison que A.

**3. L'index.** C'est la proposition du prochain commit. Il permet de **composer** un commit : n'enregistrer qu'une partie des modifications pour faire des commits atomiques (« un commit = une intention »), relire ce qui part (`git diff --staged`) avant de commiter, et sert pendant une fusion à tenir les trois versions d'un fichier en conflit (*stages* 1, 2, 3). `git add -p` (ou `--patch`) indexe morceau par morceau.

**4. `HEAD` détaché.** `HEAD` pointe directement sur un commit au lieu de pointer sur une branche. On s'y retrouve en extrayant une étiquette ou une empreinte (`git switch --detach v1.2.0`), pendant un rebase, un `bisect`, et dans la plupart des jobs de CI. Les commits faits dans cet état ne sont référencés que par `HEAD` : en basculant sur `main`, plus rien ne les désigne, sauf le reflog de `HEAD`. Git prévient et propose de créer une branche (`git switch -c sauvetage <empreinte>`). Sans cela, ils disparaîtront au prochain ramasse-miettes, une fois le délai du reflog écoulé.

**5. Trois façons d'intégrer.** Branche `f` de trois commits `F1-F2-F3` partie de `M1`, `main` n'ayant pas bougé :
```
fast-forward :   M1─F1─F2─F3            (main avance simplement jusqu'à F3, aucun commit créé)
--no-ff :        M1─────────────M       (M : commit de fusion, parents M1 et F3)
                  └─F1─F2─F3───┘
squash :         M1─S                   (S : un seul commit ordinaire, contenu F1+F2+F3,
                                          aucun lien avec F1..F3 qui restent hors de main)
```
L'avance rapide n'est possible que si `main` n'a pas bougé ; sinon, une fusion classique crée de toute façon un commit à deux parents. `--no-ff` garde la trace de la branche (utile pour `git log --first-parent`). Le *squash* produit un historique compact mais perd le détail et le lien : Git ne sait plus que `f` a été intégrée (`git branch --merged` ne la liste pas).

**6. Rebase.** `git rebase main` rejoue un à un les commits de ta branche absents de `main` **par-dessus** la pointe de `main` : ce sont de **nouveaux** commits (nouvelles empreintes, même contenu de modification), et la branche est déplacée sur le dernier. Règle d'or : **ne jamais rebaser des commits que d'autres ont déjà récupérés** (branche partagée, `main`). Sinon, le `push` exige `--force` ; tes collègues ont les anciens commits, leur prochain `pull` mélange anciennes et nouvelles versions (commits en double, conflits incompréhensibles) ou, pire, leur `push --force` écrase ton travail.

**7. Réponse B.** `A..B` = commits accessibles depuis `B` mais pas depuis `A` : ici, ce qu'apporte `fonction` par rapport à `main`. A correspond à `fonction..main`. C est la différence symétrique `main...fonction`. D correspond à `git merge-base` et à ses ancêtres.

**8. `.gitignore` sans effet.** Il ne concerne que les fichiers **non suivis** : `app.log` a été commité avant la règle, Git continue donc de le suivre. Correction : `git rm --cached app.log` (retire de l'index, garde le fichier sur le disque), puis commit avec le `.gitignore`. Le fichier reste dans l'historique passé ; s'il contenait des données sensibles, voir la question 9.

**9. Mot de passe commité.** *Non poussé* : on réécrit localement avant que quiconque ne l'ait : `git rm --cached fichier` (ou retirer la ligne), ajouter le fichier au `.gitignore`, `git commit --amend` ; si le commit n'est plus le dernier, rebase interactif (E12). Vérifier avec `git log -p` qu'il n'en reste rien, et se demander si le secret n'a pas fui ailleurs (sauvegarde du poste, partage d'écran). *Déjà poussé* : le secret est **compromis**. L'ordre change : (1) **révoquer et remplacer** le secret immédiatement (c'est la seule mesure qui protège vraiment) ; (2) prévenir la RSSI ; (3) seulement ensuite, nettoyer l'historique (`git filter-repo`), forcer la publication de façon coordonnée, faire nettoyer la forge (références de MR, pipelines, caches). Nettoyer sans révoquer ne sert à rien : clones, forks et caches ont déjà le secret. C'est l'E17.

**10. Réponse B.** `reset --hard` déplace la branche ; les trois commits ne sont plus référencés par elle, mais ils existent toujours dans la base d'objets et le reflog garde les anciennes positions : `git reflog`, puis `git reset --hard HEAD@{1}` (ou `git branch sauvetage <empreinte>`). Ils ne disparaissent qu'au ramasse-miettes, après expiration des entrées de reflog (30 jours pour des commits devenus inaccessibles, par défaut). A est faux pour cette raison. C est faux : `stash` n'a rien à voir (et un `reset --hard` détruit, lui, les modifications **non commitées**, irrécupérables). D est faux : ils n'ont jamais été poussés, mais la copie locale suffit.

**11. Les trois `reset`.** Tous déplacent la branche courante (donc `HEAD`) sur la cible. `--soft` : rien d'autre ; l'index et l'arbre de travail gardent leur contenu, les changements des commits défaits apparaissent comme indexés. `--mixed` (défaut) : l'index est aussi remis à l'état de la cible ; les changements restent dans l'arbre de travail, non indexés. `--hard` : index **et** arbre de travail remis à l'état de la cible ; toute modification non commitée des fichiers suivis est perdue.

**12. Annuler un commit publié.** `reset` + `push --force` réécrit une histoire que d'autres ont déjà : leurs clones divergent, et sur `main` la forge l'interdit de toute façon (branche protégée, E11). On utilise `git revert <commit>` : un **nouveau** commit qui applique l'inverse du commit visé. L'historique reste intact, l'erreur et sa correction sont tracées, et chacun récupère l'annulation par un simple `pull`. Pour annuler une fusion : `git revert -m 1 <fusion>`.

**13. `ours` et `theirs` pendant un rebase.** Un rebase extrait d'abord la base (`main`) puis y **rejoue** tes commits un par un, comme des *cherry-pick*. Pendant un conflit, `--ours` désigne donc la branche en construction (`main` plus tes commits déjà rejoués), et `--theirs` le commit **de ta branche** en cours de rejeu : l'inverse de l'intuition, et l'inverse d'un `git merge` lancé depuis ta branche, où `ours` est ta branche. Sorties : résoudre, `git add`, puis `git rebase --continue` ; `git rebase --skip` (abandonner ce commit-là) ; `git rebase --abort` (revenir exactement à l'état d'avant le rebase).

**14. Étiquettes.** Une étiquette **légère** n'est qu'une référence vers un commit. Une étiquette **annotée** est un objet à part entière : auteur de l'étiquette, date, message, et éventuellement une signature. Pour une version publiée : annotée (et signée, E27) — on sait qui l'a posée et quand, `git describe` la prend en compte par défaut, et la signature permet de la vérifier. `git push` ne pousse **pas** les étiquettes : `git push origin v1.2.0`, `git push --tags` (toutes), ou `git push --follow-tags` (les annotées accessibles depuis ce qui est poussé ; réglable par `push.followTags`).

**15. `cherry-pick`.** Pour recopier un commit précis sur une autre branche sans fusionner tout le reste : rétroporter un correctif sur une branche de maintenance (E19), récupérer un commit fait sur la mauvaise branche. Risque d'un usage répété entre branches longues : chaque copie est un **commit différent** (autre empreinte) avec le même changement ; à la fusion suivante, Git peut produire des conflits sur des modifications « déjà là », et l'historique devient difficile à suivre. `git cherry-pick -x` ajoute au message l'empreinte d'origine, ce qui garde la traçabilité.

**16. `bisect`.** Recherche dichotomique : chaque test divise l'intervalle par deux, soit ⌈log2(1000)⌉ = **10** étapes au plus. Automatisation : `git bisect start <mauvais> <bon>` puis `git bisect run ./test.sh`, où le script renvoie 0 si le commit est bon, de 1 à 127 (sauf 125) s'il est mauvais, et 125 pour « impossible à tester » (le commit est sauté). C'est l'E44.

**17. Reflog.** Journal **local** de chaque déplacement de `HEAD` et de chaque branche (commit, reset, rebase, checkout, pull…), avec l'ancienne et la nouvelle valeur. Il n'est **jamais** transmis par `push` ni par `clone` : un clone neuf a un reflog vide. Par défaut, les entrées sont conservées 90 jours (`gc.reflogExpire`), et 30 jours quand elles désignent des commits devenus inaccessibles (`gc.reflogExpireUnreachable`).

**18. Réponse B.** L'empreinte d'un commit est le SHA-1 de **tout** son contenu : arbre, parents, auteur, validateur, dates, message. Changer le message, c'est créer un autre objet, donc une autre empreinte (et la date de validation change aussi). A et C sont faux pour cette raison. D est faux : `gc` ne modifie aucun objet, il compacte et supprime l'inaccessible.

**19. `git branch -vv`.** Pour chaque branche locale : son commit, sa branche amont (*upstream*) et l'écart avec elle. `ahead 2, behind 3` : deux commits locaux absents de `origin/main`, trois commits de `origin/main` absents de la branche locale (les historiques ont divergé). L'information est calculée **localement**, à partir de la référence de suivi `origin/main` telle qu'elle était au dernier `fetch` : elle peut être périmée. `git fetch` d'abord, pour savoir où en est vraiment la forge.

**20. `--force` et `--force-with-lease`.** `--force` écrase la branche distante quoi qu'il y ait dessus, y compris les commits poussés par un collègue entre-temps. `--force-with-lease` n'écrase que si la branche distante est encore à la valeur que tu crois (celle de ta référence de suivi) : si quelqu'un a poussé depuis ton dernier `fetch`, le push est refusé. Faille : si un `fetch` a eu lieu **en arrière-plan** (éditeur, outil graphique), la référence de suivi est à jour sans que tu aies intégré ces commits, et la « garantie » passe quand même. `--force-if-includes` (Git 2.30+) vérifie en plus que la pointe distante fait partie de l'historique local (via le reflog), c'est-à-dire que tu l'as réellement intégrée.

**21. Fins de ligne.** Windows utilise CRLF, Linux LF. Avec des réglages `core.autocrlf` différents selon les postes, chaque fichier touché sous Windows peut être réécrit avec d'autres fins de ligne : diff de toutes les lignes, conflits, scripts Bash qui échouent (`$'\r': command not found`). Solution robuste, **versionnée** dans le dépôt et donc identique pour tous : un fichier `.gitattributes`, par exemple `* text=auto eol=lf` (avec des exceptions, `*.bat text eol=crlf`, `*.png binary`), puis `git add --renormalize .` et un commit dédié. Le réglage personnel `core.autocrlf` ne doit pas être la seule protection.

**22. Gros binaire.** Un objet commité reste dans l'historique **pour toujours** : le supprimer au commit suivant n'enlève rien, chaque clone télécharge toujours les 600 Mo, et seule une réécriture de l'historique (coordonnée avec toute l'équipe) l'en retire. Les ISO vont sur un stockage d'artefacts (`hdd-bulk`, stockage objet S3 au M05, registre de paquets), le dépôt ne contenant que leur URL et leur somme de contrôle. Si l'équipe doit vraiment versionner des binaires : Git LFS. Prévention : le hook `check-added-large-files` (E15) et une limite de taille côté serveur (E26).

**23. `blame` et pioche.** `git blame -w` ignore les changements d'espaces ; `-M` et `-C` suivent les lignes déplacées ou copiées ; un fichier `.git-blame-ignore-revs` (réglage `blame.ignoreRevsFile`) liste les commits de pur reformatage à ignorer. Pour trouver le commit qui a introduit ou supprimé une chaîne : `git log -S SEUIL_ALERTE` (*pickaxe* : commits qui changent le **nombre** d'occurrences), ou `git log -G <regex>` (commits dont le diff contient une ligne correspondante). Ajouter `--all` pour chercher sur toutes les branches, `-p` pour voir le diff.

**24. Conventional Commits.**
- `fix(dns): corriger <le comportement précis>` — un message utile dit **quoi** (« correction bug DNS » ne dit rien).
- `feat(deploiement): ajouter l'option --dry-run au script de déploiement`
- `feat!: remplacer PVE_HOST par PVE_API_URL`, avec en pied de message `BREAKING CHANGE: PVE_HOST n'est plus lue ; les scripts appelants doivent définir PVE_API_URL.`

Seul le troisième déclenche une version **majeure** : un `!` après le type ou un pied `BREAKING CHANGE:` signale une rupture de compatibilité. `feat` donne une mineure, `fix` une corrective. Le type exact du troisième (`feat!`, `refactor!`) se discute ; la rupture, non.

**25. Hooks côté client.** Dans `.git/hooks/` (ou le dossier désigné par `core.hooksPath`). Ce dossier n'est **pas** versionné ni transmis par `clone` : chacun doit installer ses hooks (c'est ce qu'outille pre-commit, E15). Et rien n'oblige à les exécuter : `git commit --no-verify` les court-circuite, un poste mal installé ne les a pas, et quelqu'un peut les modifier. Un hook local est un **confort** (erreurs détectées tôt) ; la **garantie** vient des contrôles côté serveur : hooks de pré-réception (E26) et pipeline obligatoire avant fusion (E24).

**Grille d'auto-évaluation**

| Score /50 | Lecture | Conseil |
|---|---|---|
| 42 à 50 | Maîtrise solide | Concentre-toi sur la forge (E04 à E06) et les paliers 3 et 4. |
| 30 à 41 | Bon usage quotidien, lacunes ciblées | Fais E02 et E08 lentement, en lisant les sections « Explications » ; reprends les thèmes faibles ci-dessous. |
| 20 à 29 | Usage de base | Lis les chapitres 2, 3 et 7 de *Pro Git* avant le palier 2. |
| Moins de 20 | Écart important avec le prérequis | Chapitres 1 à 3 de *Pro Git* et le tutoriel `gittutorial(7)`, puis refais le test. |

| Thème | Questions | Où il est travaillé |
|---|---|---|
| Modèle objet, références, reflog | 2, 4, 17, 18 | E02, E08, E42, E45, E46 |
| Index et annulations | 3, 8, 10, 11, 12 | E08, E42 |
| Fusion, rebase, réécriture | 5, 6, 13, 20 | E07, E12, E13 |
| Lecture d'historique et recherche | 7, 16, 19, 23 | E07, E44 |
| Étiquettes, cherry-pick, versions | 14, 15, 24 | E19, E25 |
| Secrets, gros fichiers, fins de ligne | 9, 21, 22 | E15, E16, E17 |
| Hooks et garanties | 1, 25 | E03, E15, E24, E26 |

Ressources : *Pro Git* (chapitres 2, 3, 7, 10) ; pages `gitglossary(7)`, `gitrevisions(7)`, `git-reset(1)`, `git-rebase(1)` ; *Oh Shit, Git!?!* (<https://ohshitgit.com/>) pour les réflexes de récupération.

---

### M01-E02 — Le modèle objet de Git : blobs, arbres, commits, références

**Solution**

Script complet et commenté, qui rejoue tout l'exercice : [`fichiers/M01-E02/objets-a-la-main.sh`](fichiers/M01-E02/objets-a-la-main.sh).

*1. Dépôt vide.* `.git/HEAD` contient `ref: refs/heads/main` : une **référence symbolique** vers une branche qui n'existe pas encore (branche « à naître », *unborn*). `config` porte la configuration locale, `objects/` la base d'objets (vide, hors sous-dossiers `info` et `pack`), `refs/` les références (`heads/` pour les branches, `tags/`).

*2. Blob.*
```
admin@adm01:~/src/labo-objets$ printf 'Bonjour MédiSphère\n' | git hash-object -w --stdin
2453cbd5850643ef5792a0fc58ccc3fcc8f58004
admin@adm01:~/src/labo-objets$ find .git/objects -type f
.git/objects/24/53cbd5850643ef5792a0fc58ccc3fcc8f58004
admin@adm01:~/src/labo-objets$ git cat-file -t 2453cbd ; git cat-file -s 2453cbd
blob
21
admin@adm01:~/src/labo-objets$ python3 -c 'import sys,zlib; print(zlib.decompress(open(sys.argv[1],"rb").read()))' .git/objects/24/53cbd5850643ef5792a0fc58ccc3fcc8f58004
b'blob 21\x00Bonjour M\xc3\xa9diSph\xc3\xa8re\n'
admin@adm01:~/src/labo-objets$ printf 'blob 21\0Bonjour MédiSphère\n' | sha1sum
2453cbd5850643ef5792a0fc58ccc3fcc8f58004  -
```
La phrase compte 18 caractères plus le retour à la ligne, soit 19 caractères, mais **21 octets** : `é` et `è` occupent chacun deux octets en UTF-8 (`\xc3\xa9`, `\xc3\xa8`). Git compte des octets. L'objet est rangé sous `objects/<2 premiers caractères>/<38 suivants>`.

*3.* Le contenu est dans la base d'objets, pas dans l'arbre de travail : `hash-object -w` n'a créé aucun fichier `LISEZMOI.txt`. Empreinte de `docs/notes.txt` : `f9c491da6f019e9368ae66d33f00cbb648e0bb6b`.

*4. Arbres.*
```
admin@adm01:~/src/labo-objets$ git update-index --add --cacheinfo 100644,2453cbd5850643ef5792a0fc58ccc3fcc8f58004,LISEZMOI.txt
admin@adm01:~/src/labo-objets$ git update-index --add --cacheinfo 100644,f9c491da6f019e9368ae66d33f00cbb648e0bb6b,docs/notes.txt
admin@adm01:~/src/labo-objets$ git write-tree
9d90ff95f2a92e967102d836e837607d0109aaf6
admin@adm01:~/src/labo-objets$ git cat-file -p 9d90ff9
100644 blob 2453cbd5850643ef5792a0fc58ccc3fcc8f58004	LISEZMOI.txt
040000 tree 4b5d1905e7be4f785ab60e8ad0ccf5cbf0a01206	docs
```
**Deux** arbres ont été créés : un par répertoire (la racine et `docs`). Un arbre ne contient que des noms, des modes et des empreintes ; `040000` désigne un sous-arbre. Ces empreintes sont identiques chez tous les apprenants : elles ne dépendent que des contenus, des noms et des modes. C'est ce que vérifie le check.

*5. Commit racine.*
```
admin@adm01:~/src/labo-objets$ git commit-tree 9d90ff9 -m "Premier commit construit à la main"
a1f881e…                                   ← différent chez toi : auteur et date sont hachés
admin@adm01:~/src/labo-objets$ git cat-file -p a1f881e
tree 9d90ff95f2a92e967102d836e837607d0109aaf6
author Camille Durand <camille.durand@medisphere.internal> 1791068588 +0200
committer Camille Durand <camille.durand@medisphere.internal> 1791068588 +0200

Premier commit construit à la main
admin@adm01:~/src/labo-objets$ git log
fatal: your current branch 'main' does not have any commits yet
```
Pas de ligne `parent` : c'est un commit racine. `git log` part de `HEAD`, qui désigne `main`… qui n'existe toujours pas. Le commit existe, mais **rien ne pointe dessus**.

*6. Branche.* `git update-ref refs/heads/main a1f881e` crée le fichier `.git/refs/heads/main` (41 octets : l'empreinte et un retour à la ligne). `git log` affiche le commit. `git status` montre les deux fichiers « supprimés » : ils sont dans l'index et dans `HEAD`, mais pas dans l'arbre de travail. `git restore .` (index → arbre de travail) remet les fichiers sur le disque.

*7. Deuxième commit.* Nouveaux objets : 1 blob (le nouveau `notes.txt`), 2 arbres (le nouveau `docs` et la nouvelle racine qui le référence), 1 commit : **4 objets**. Réutilisé : le blob de `LISEZMOI.txt`, inchangé, référencé tel quel par le nouvel arbre racine. Avec `git commit-tree <arbre> -p <commit racine> -m "…"` puis `git update-ref refs/heads/main <nouveau> <ancien>` (la forme à trois arguments ne met à jour que si la valeur actuelle est bien `<ancien>` : c'est un « compare-and-swap »).

*8. Étiquettes.* `v0-leger` est un simple fichier `.git/refs/tags/v0-leger` contenant l'empreinte du commit (`git cat-file -t v0-leger` → `commit`). `v0-annote` pointe sur un **objet** `tag` (`git cat-file -t` → `tag`) qui contient l'objet visé, son type, le nom de l'étiquette, l'auteur, la date et le message. Avec la configuration de l'E03 (`tag.gpgSign`), une étiquette annotée posée plus tard sera aussi signée.

*9. Déduplication.* `COPIE.txt` a la même empreinte que `LISEZMOI.txt` : **aucun** nouvel objet. Un contenu identique n'est stocké qu'une fois, quel que soit son nom ou son emplacement.

*10. Références.* `git branch essai` crée `.git/refs/heads/essai` (41 octets). `git pack-refs --all` regroupe toutes les références dans `.git/packed-refs` (une ligne par référence ; la ligne `^…` sous une étiquette annotée donne le commit visé, « épluché »). C'est ce que fait `git gc` sur les dépôts qui ont des milliers d'étiquettes. Bilan final : `git count-objects -v` compte 10 objets en vrac (3 blobs, 4 arbres, 2 commits, 1 étiquette annotée).

**Explications**

Git est un **système de fichiers adressé par le contenu** : l'identifiant d'un objet est l'empreinte de son contenu. Conséquences directes :
- *Intégrité* : un objet modifié, même d'un bit, n'a plus la même empreinte ; `git fsck` le détecte. Comme un commit contient l'empreinte de son arbre et de ses parents, l'empreinte du dernier commit « signe » tout l'historique (structure en arbre de Merkle). C'est pour cela que signer un commit (E03, E27) engage tout ce qui le précède.
- *Immutabilité* : on ne modifie jamais un objet. `--amend`, `rebase`, `reset` créent de nouveaux objets et déplacent des références ; les anciens restent jusqu'au ramasse-miettes (E08).
- *Branches gratuites* : une branche est un fichier de 41 octets. Créer ou supprimer une branche ne touche pas aux données.
- *Déduplication* : les contenus identiques sont partagés entre fichiers, commits et branches.

SHA-1 est cassé en théorie (collision SHAttered, 2017) : Git utilise depuis la 2.13 une variante qui détecte les tentatives de collision connues (*SHA-1DC*), et sait créer des dépôts SHA-256 (`--object-format=sha256`). Le passage par défaut à SHA-256 est annoncé pour Git 3.0 (voir `annexes/versions-bloc-A.md`) ; la compatibilité avec les forges reste le frein.

**Alternatives**

- `git mktree` construit un arbre à partir d'une description textuelle, sans passer par l'index.
- `git hash-object -w <fichier>` lit un fichier plutôt que l'entrée standard.
- `git cat-file --batch-all-objects --batch-check` liste tous les objets de la base avec leur type et leur taille.

**Pièges classiques**

- `echo` au lieu de `printf` : `echo` ajoute toujours un retour à la ligne, `echo -n` n'en met pas ; selon le shell, `echo` interprète ou non les `\n`. Avec un retour à la ligne de plus ou de moins, l'empreinte change et le check signale un arbre différent.
- Compter les caractères au lieu des octets dans l'en-tête recalculé avec `sha1sum`.
- `git hash-object` sans `-w` : l'empreinte est affichée, mais rien n'est écrit ; `update-index` refuse ensuite une empreinte absente de la base.
- Oublier `-p` dans `commit-tree` pour le deuxième commit : on obtient un second commit racine, et `main` n'a plus qu'un commit (l'ancien n'est plus référencé).
- Mode `100755` au lieu de `100644` : l'arbre change (et donc son empreinte).
- `git status` qui affiche des fichiers « supprimés » après `update-ref` : ce n'est pas une erreur, c'est l'arbre de travail qui n'a jamais été rempli.

**En production chez MédiSphère**

Ces commandes ne servent pas au quotidien, mais elles reviennent dans les moments difficiles : diagnostiquer un dépôt corrompu (`git fsck`, objets manquants, E41), récupérer un objet perdu (`git cat-file -p <empreinte>`), écrire un hook côté serveur qui inspecte ce qui arrive sans arbre de travail (`git cat-file`, `git ls-tree` sur les empreintes reçues, E26), ou un script de CI qui lit un fichier d'une autre branche sans l'extraire (`git show origin/main:chemin`).

---

### M01-E03 — Configurer Git sur `adm01` (identité, `main`, alias, signature SSH)

**Solution**

Fichiers d'exemple : [`fichiers/M01-E03/gitconfig`](fichiers/M01-E03/gitconfig) (le `~/.gitconfig` obtenu), [`allowed_signers`](fichiers/M01-E03/allowed_signers), [`ignore`](fichiers/M01-E03/ignore).

```
admin@adm01:~$ git config --list --show-origin --show-scope
admin@adm01:~$ git config --global user.name "Camille Durand"
admin@adm01:~$ git config --global user.email camille.durand@medisphere.internal
admin@adm01:~$ git config --global init.defaultBranch main
admin@adm01:~$ git config --global pull.ff only
admin@adm01:~$ git config --global fetch.prune true
admin@adm01:~$ git config --global push.autoSetupRemote true
admin@adm01:~$ git config --global merge.conflictStyle zdiff3
admin@adm01:~$ git config --global diff.algorithm histogram
admin@adm01:~$ git config --global core.editor vim
admin@adm01:~$ git config --global alias.lg 'log --graph --oneline --decorate --all'
admin@adm01:~$ git config --global alias.st 'status -sb'
admin@adm01:~$ git config --global alias.ds 'diff --staged'
admin@adm01:~$ mkdir -p ~/.config/git && $EDITOR ~/.config/git/ignore
```
Et dans `lab/lab.env` : `WB_MOI=camille.durand`.

*Signature SSH.*
```
admin@adm01:~$ ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_signature -C "camille.durand signature Git"
admin@adm01:~$ ssh-add ~/.ssh/id_ed25519_signature
admin@adm01:~$ git config --global gpg.format ssh
admin@adm01:~$ git config --global user.signingKey "$HOME/.ssh/id_ed25519_signature.pub"
admin@adm01:~$ git config --global gpg.ssh.allowedSignersFile "$HOME/.config/git/allowed_signers"
admin@adm01:~$ git config --global commit.gpgSign true
admin@adm01:~$ git config --global tag.gpgSign true
admin@adm01:~$ printf '%s namespaces="git" %s\n' "$(git config user.email)" "$(cut -d' ' -f1,2 ~/.ssh/id_ed25519_signature.pub)" > ~/.config/git/allowed_signers
admin@adm01:~$ cd ~/src/labo-objets && git commit --allow-empty -m "test: premier commit signé"
admin@adm01:~/src/labo-objets$ git log --show-signature -1
commit 5e1c…
Good "git" signature for camille.durand@medisphere.internal with ED25519 key SHA256:Xq3…
admin@adm01:~/src/labo-objets$ git verify-commit HEAD && echo signature OK
```
(Sortie indicative.) Sans la clé dans l'agent (`ssh-add -d ~/.ssh/id_ed25519_signature`), Git appelle toujours `ssh-keygen -Y sign` avec la clé **publique** ; `ssh-keygen` ne trouve pas la clé correspondante dans l'agent et se rabat sur le fichier de clé privée voisin : il **demande la phrase de passe** sur le terminal. Phrase correcte : le commit est créé et signé. Phrase fausse ou `Ctrl+C` : `fatal: failed to write commit object`, aucun commit n'est créé (jamais de commit non signé en silence). Sans terminal (script, cron, job de CI), la question ne peut pas être posée et le commit échoue : c'est pour cela que l'agent est indispensable, et que les commits des automates ne sont pas signés avec ta clé. ⚠️ À vérifier sur ta version d'OpenSSH : ce repli vers le fichier de clé privée est le comportement des versions récentes. Pour les sessions longues, `ssh-add -t 8h` limite la durée de présence de la clé dans l'agent.

**Explications**

*Niveaux de configuration.* Système (`/etc/gitconfig`, `--system`), global (`~/.gitconfig` ou `~/.config/git/config`, `--global`), dépôt (`.git/config`, `--local`), et *worktree* (E18). La valeur la plus spécifique l'emporte : un dépôt peut surcharger ton identité globale (utile pour un dépôt personnel), ce qui explique parfois un commit « au mauvais nom ». `--show-origin --show-scope` est la commande de diagnostic.

*Les réglages.*
- `pull.ff=only` : en cas de divergence, `pull` échoue au lieu de créer une fusion ou de rebaser sans que tu l'aies décidé. Tu choisis ensuite en connaissance de cause (`git rebase origin/main` sur une branche personnelle, fusion sinon). `pull.rebase=true` est aussi défendable pour qui rebase toujours ses branches locales ; c'est un choix de méthode, pas de sûreté. L'important est qu'il soit **explicite**.
- `fetch.prune` : les branches supprimées sur la forge (après fusion des MR) disparaissent de `origin/*` ; sinon des dizaines de références mortes s'accumulent.
- `push.autoSetupRemote` : `git push` sur une nouvelle branche crée la branche distante et le suivi, sans le fastidieux `--set-upstream origin <branche>`.
- `merge.conflictStyle=zdiff3` : les marqueurs de conflit montrent aussi la version de l'**ancêtre commun** (section `|||||||`). C'est souvent la seule façon de comprendre ce que chacun a voulu changer (E13).
- `diff.algorithm=histogram` : diffs plus lisibles quand des blocs semblables se répètent (accolades, lignes vides) ; même résultat en contenu, meilleure présentation.

*Ignorés globaux.* `~/.config/git/ignore` est lu par défaut. Il protège **ton** poste (fichiers d'éditeur, `.env` oubliés). Il ne remplace pas le `.gitignore` du projet : les collègues ne l'ont pas, la CI non plus ; ce qui doit être ignoré par tous est versionné dans le projet.

*Signature SSH.* Depuis Git 2.34, une clé SSH peut signer commits et étiquettes : pas de GPG, pas de trousseau, l'agent SSH que tu utilises déjà. La signature couvre le contenu du commit (donc tout l'historique qui le précède, E02). `allowed_signers` est l'équivalent local du trousseau de confiance : `git verify-commit` refuse une signature dont la clé n'y figure pas associée à l'adresse de l'auteur (« *No principal matched* »). L'option `namespaces="git"` empêche que la même ligne serve à valider des signatures d'un autre usage (fichiers, `ssh-keygen -Y` pour autre chose). La **clé dédiée** permet de révoquer ou de remplacer la clé de signature sans toucher à tes accès SSH, et inversement ; elle peut aussi avoir une politique différente (durée dans l'agent, clé matérielle FIDO plus tard).

Dans GitLab, tes commits apparaîtront « *Unverified* » tant que la clé de signature n'est pas déclarée dans ton profil avec l'usage *Signing* : c'est l'objet de l'E27.

**Alternatives**

- Signature GPG (`gpg.format openpgp`, défaut historique) : sous-clés, expiration et révocation intégrées, toile de confiance ; mais gestion des clés plus lourde. Signature X.509 (`gpg.format x509`, avec `gpgsm`) quand une PKI d'entreprise délivre des certificats de signature.
- Clé de signature sur un jeton matériel FIDO2 (`ssh-keygen -t ed25519-sk`) : la clé privée ne quitte jamais le jeton.
- Configuration conditionnelle (`[includeIf "gitdir:~/src/perso/"]`) pour utiliser une autre identité dans certains dossiers.

**Pièges classiques**

- `user.signingKey = ~/.ssh/…` : le tilde n'est pas développé partout ; écris un chemin absolu (le shell développe `$HOME` au moment du `git config`).
- Signer avec la clé de connexion : ça marche, mais révoquer l'une révoque l'autre.
- `allowed_signers` sans l'adresse **exacte** de `user.email`, ou avec la clé privée (!) au lieu de la publique.
- Une identité définie au niveau **local** d'un vieux dépôt qui surcharge la globale : les commits partent sous l'ancienne adresse et ne sont pas reliés à ton compte GitLab.
- `init.defaultBranch` fixé après coup : il ne renomme pas les dépôts déjà créés (voir E06 pour `~/medisphere`).
- Phrase de passe vide « pour aller plus vite » : une clé de signature non protégée, copiée avec une sauvegarde du poste, permet de signer en ton nom.

**En production chez MédiSphère**

La configuration Git des postes est fournie par un fichier versionné (ou un rôle Ansible pour les postes Linux, M04), avec les mêmes réglages pour toute l'équipe ; les clés publiques de signature de l'équipe sont publiées dans un `allowed_signers` commun, versionné, et la vérification des signatures est faite côté forge (E27) et en CI. La rotation d'une clé de signature (départ, perte) est une procédure écrite : retrait de l'ancienne clé dans GitLab et dans `allowed_signers`, sans invalider la vérification des commits anciens.

---

### M01-E04 — Installer GitLab CE sur `git01` avec une PKI provisoire

**Solution**

Fichiers : [`fichiers/M01-E04/`](fichiers/M01-E04/)
- `pki-provisoire.cnf` et `pki-provisoire.sh` : la PKI (CA, certificat de `git01`, installation de la racine) ;
- `creer-git01.sh` : la VM, depuis `adm01` ;
- `dnsmasq-git01.conf`, `ssh-config-git01` : DNS et alias ;
- `preparer-git01.sh` : temps, swap, racine et certificats sur `git01` ;
- `gitlab.rb` et `installer-gitlab.sh` : GitLab ;
- `docs-socle-extraits.md` : les ajouts à l'inventaire et à la matrice des flux.

*A. PKI provisoire*
```
admin@adm01:~$ install -d -m 700 ~/pki-provisoire
admin@adm01:~$ cp ~/DevOpsPrivateCloud/modules/01-git/corrige/fichiers/M01-E04/pki-provisoire.{cnf,sh} ~/pki-provisoire/
admin@adm01:~$ cd ~/pki-provisoire && ./pki-provisoire.sh ca
subject=O = MédiSphère, CN = MédiSphère CA provisoire
notAfter=Oct  2 23:01:19 2028 GMT
admin@adm01:~/pki-provisoire$ ./pki-provisoire.sh git01
…/git01.crt: OK
subject=O = MédiSphère, CN = git01.par1.medisphere.internal
notAfter=Nov  4 23:01:19 2027 GMT
X509v3 Subject Alternative Name:
    DNS:git01.par1.medisphere.internal, DNS:git01, IP Address:10.10.20.12
admin@adm01:~/pki-provisoire$ ./pki-provisoire.sh racine
```
Les commandes OpenSSL sous-jacentes (lis le script) : `openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256` pour les clés ; `openssl req -x509 -new -config pki-provisoire.cnf -key ca.key -days 730 -extensions v3_ca` pour la racine ; `openssl req -new -config pki-provisoire.cnf -section req_git01` pour la demande du serveur ; `openssl x509 -req … -CA ca.crt -CAkey ca.key -CAcreateserial -days 397 -extfile pki-provisoire.cnf -extensions v3_serveur_git01` pour la signature. `umask 077` en tête de script : aucune clé n'existe, même un instant, avec des droits trop larges.

*Choix de l'algorithme.* ECDSA P-256 dans ce corrigé : clés et signatures courtes, négociation TLS plus rapide, accepté par tous les clients du lab (OpenSSL, Git, curl, navigateurs, et Go pour GitLab Runner). RSA 4096 est aussi valable (compatibilité maximale avec de vieux clients, mais signatures plus lentes et plus lourdes) ; dans ce cas, le certificat serveur ajoute `keyEncipherment` dans `keyUsage`.

*Réponses aux questions de l'étape 6.*
- **397 jours** : plafond imposé depuis septembre 2020 aux certificats serveur des autorités **publiques** (exigences du CA/Browser Forum, appliquées par Apple, Google, Mozilla). Les navigateurs ne l'imposent pas aux autorités ajoutées localement, mais on s'aligne : c'est la bonne pratique, et ce plafond baisse (le CA/Browser Forum a voté en 2025 une réduction progressive : 200 jours depuis mars 2026, 100 jours en 2027, 47 jours en 2029). Une durée courte limite la fenêtre d'exploitation d'une clé volée et oblige à **automatiser** le renouvellement ; ce sera le rôle d'ACME avec step-ca (M06, certificats de 30 jours).
- **SAN plutôt que CN** : les clients modernes ignorent le CN dès qu'un SAN existe, et beaucoup refusent un certificat sans SAN (Chrome depuis 2017, et surtout Go depuis la 1.15 : **GitLab Runner** refuserait la connexion en E23). Le SAN porte plusieurs noms et des adresses IP.
- **`CA:false`** : un certificat serveur ne doit pas pouvoir signer d'autres certificats. Sans cette extension, un client laxiste pourrait accepter une chaîne où le certificat de `git01` sert d'autorité.
- **Vol de `ca.key`** : l'attaquant fabrique des certificats valides pour **n'importe quel nom** aux yeux de toutes les machines qui font confiance à la racine (`adm01`, `git01`, `runner01`, ton poste) : interception transparente des flux HTTPS (jetons GitLab, mots de passe) par un intermédiaire. D'où la clé en 600 dans un dossier en 700, jamais copiée, et une racine installée sur le moins de machines possible. Les *name constraints* limiteraient la casse (voir « Pour aller plus loin »).

*B. La VM*
```
admin@adm01:~$ ssh pve01 qm list | grep -w 1004 ; ping -c 2 -W 2 10.10.20.12     # doivent être vides / échouer
admin@adm01:~$ ssh pve01 free -g
admin@adm01:~$ bash ~/DevOpsPrivateCloud/modules/01-git/corrige/fichiers/M01-E04/creer-git01.sh
admin@adm01:~$ ssh dns01 "echo 'host-record=git01.par1.medisphere.internal,10.10.20.12' | sudo tee -a /etc/dnsmasq.d/medisphere.conf && sudo systemctl restart dnsmasq"
admin@adm01:~$ dig +short git01.par1.medisphere.internal ; dig +short -x 10.10.20.12
10.10.20.12
git01.par1.medisphere.internal.
```
(Range plutôt la ligne `host-record` dans la section « Enregistrements A + PTR » du fichier, avec un éditeur : l'ajout en fin de fichier fonctionne, mais le fichier se lit moins bien.) Puis l'alias `git01` dans `~/.ssh/config` (bloc avant `Host *`), et :
```
admin@adm01:~$ ssh git01 'hostname -f; cloud-init status; df -h /; systemctl is-active qemu-guest-agent'
git01.par1.medisphere.internal
status: done
/dev/sda1        59G  1.6G   55G   3% /
active
admin@adm01:~$ scp ~/pki-provisoire/{ca.crt,git01-chaine.crt,git01.key} git01:/tmp/
admin@adm01:~$ scp ~/DevOpsPrivateCloud/modules/01-git/corrige/fichiers/M01-E04/preparer-git01.sh git01:
admin@adm01:~$ ssh git01 sudo bash preparer-git01.sh
```

*C. GitLab*
```
admin@git01:~$ curl -fsSLo /tmp/script.deb.sh https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh
admin@git01:~$ less /tmp/script.deb.sh
```
Ce que fait le script : il détecte la distribution (`/etc/os-release`), installe les prérequis (`curl`, `gnupg`, `apt-transport-https` selon les versions), télécharge la clé de signature du dépôt dans `/usr/share/keyrings/` et écrit une source APT qui y fait référence (`signed-by=`), puis lance `apt-get update`. Rien d'autre : c'est vérifiable, et c'est la raison de le lire.
```
admin@git01:~$ sudo bash /tmp/script.deb.sh
admin@git01:~$ apt-cache madison gitlab-ce | grep ' 19\.3\.' | head -n 3
 gitlab-ce | 19.3.X-ce.0 | https://packages.gitlab.com/gitlab/gitlab-ce/debian trixie/main amd64 Packages
admin@git01:~$ sudo install -m 600 -o root -g root gitlab.rb /etc/gitlab/gitlab.rb      # fichier du corrigé, copié par scp
admin@git01:~$ sudo EXTERNAL_URL="https://git01.par1.medisphere.internal" apt-get install gitlab-ce=19.3.X-ce.0
admin@git01:~$ sudo apt-mark hold gitlab-ce
admin@git01:~$ sudo gitlab-ctl reconfigure
admin@git01:~$ sudo gitlab-ctl status
run: gitaly: (pid 4521) 312s; run: log: (pid 4129) 401s
run: gitlab-workhorse: (pid 4602) 298s; run: log: (pid 4244) 389s
run: logrotate: (pid 4060) 415s; run: log: (pid 4071) 412s
run: nginx: (pid 4620) 296s; run: log: (pid 4262) 385s
run: postgresql: (pid 4166) 396s; run: log: (pid 4180) 393s
run: puma: (pid 4560) 305s; run: log: (pid 4220) 392s
run: redis: (pid 4096) 409s; run: log: (pid 4105) 406s
run: sidekiq: (pid 4581) 301s; run: log: (pid 4232) 390s
```
(Sortie indicative : `X` est le dernier correctif de la 19.3 au moment où tu installes.) Huit services, et pas de `prometheus`, `alertmanager`, `node-exporter`, `redis-exporter`, `postgres-exporter`, `gitlab-exporter`, ni `gitlab-kas` : c'est l'effet de la configuration. Vérifications :
```
admin@git01:~$ sudo gitlab-rake gitlab:check SANITIZE=true        # tout doit finir par « yes » ou « OK »
admin@adm01:~$ curl -sSI https://git01.par1.medisphere.internal/users/sign_in | head -n 1
HTTP/2 200
admin@adm01:~$ openssl s_client -connect git01.par1.medisphere.internal:443 -verify_return_error </dev/null 2>&1 | grep -E 'Verify return code|subject=|issuer='
admin@git01:~$ free -h
```
Au repos, après quelques minutes, compte de l'ordre de 3 à 4 Gio utilisés sur 8 (à mesurer chez toi et à noter pour l'E30), et un swap peu ou pas utilisé.

Enfin, le mot de passe de `root` : `sudo cat /etc/gitlab/initial_root_password`, connexion depuis le navigateur, changement immédiat (*Avatar → Edit profile → Password*), rangement dans le gestionnaire de mots de passe. Et la documentation (extraits complets dans `docs-socle-extraits.md`) :
```
admin@adm01:~/medisphere$ git add docs/socle/inventaire.md docs/socle/matrice-flux.md
admin@adm01:~/medisphere$ git commit -m "docs(socle): ajouter git01 à l'inventaire et à la matrice des flux"
```

**Explications**

*Pourquoi `gitlab.rb` avant le paquet.* À la première installation, le paquet lance une configuration complète (base PostgreSQL initialisée, services démarrés). Si `gitlab.rb` existe déjà, cette première configuration applique directement le bon profil : Prometheus ne démarre jamais, Puma démarre en mode simple, et Let's Encrypt n'est jamais tenté. La variable `EXTERNAL_URL` passée à `apt-get` ne fait que réécrire la ligne `external_url`, ici avec la même valeur. Le `gitlab-ctl reconfigure` final est idempotent : il garantit que la configuration appliquée est bien celle du fichier, quelle que soit la façon dont le paquet s'est comporté.

*Un `gitlab.rb` court.* Le modèle complet (plus de 3 000 lignes, presque toutes commentées) reste disponible dans `/opt/gitlab/etc/gitlab.rb.template`. Un fichier qui ne contient que les écarts aux valeurs par défaut se relit en une minute, se compare facilement entre deux versions, et se versionnera (sans secret : `gitlab.rb` n'en contient pas ici ; les secrets sont dans `gitlab-secrets.json`). Point d'attention pour la suite : une clé affectée deux fois garde la **dernière** valeur. Le hash `gitaly['configuration']` sera enrichi en E26 (hooks côté serveur) : on y ajoute une clé, on n'écrit pas une seconde affectation.

*Le profil mémoire.* Puma en mode simple : un seul processus Ruby au lieu d'un maître et de plusieurs *workers* (gain de 100 à 400 Mo selon la documentation ; contrepartie : un seul processus traite les requêtes web, suffisant pour une équipe de cinq). Sidekiq à 10 fils. Gitaly limité dans ses opérations simultanées par dépôt et dans le nombre de processus Git lancés en parallèle. `MALLOC_CONF` règle jemalloc pour rendre la mémoire libérée plus vite au système. La supervision embarquée (Prometheus et ses *exporters*) coûte à elle seule plusieurs centaines de Mo : l'E30 la réintroduira de façon mesurée.

*Mémoire fixe et swap.* Sans *ballooning*, Proxmox ne reprend pas de mémoire à la VM : GitLab, qui garde ses processus Ruby chauds, réagit mal à une mémoire qui rétrécit (swap, puis OOM). Le swap sert d'amortisseur aux pics (migrations de base pendant une mise à jour, E29), `vm.swappiness=10` pour qu'il ne serve qu'à cela.

*`apt-mark hold`.* GitLab impose un **chemin de montée de version** : certaines versions intermédiaires (*required upgrade stops*) doivent être installées et leurs migrations de fond terminées avant d'aller plus loin. Un `apt upgrade` distrait qui saute une étape peut laisser l'instance dans un état dont on ne sort que par une restauration. Le blocage force à passer par la procédure de l'E29.

*Deux magasins de confiance.* `update-ca-certificates` alimente le magasin du **système** (`/etc/ssl/certs`), utilisé par `curl`, `git` et les outils de la VM. GitLab embarque sa propre bibliothèque OpenSSL et son propre magasin : quand l'application appelle un service HTTPS interne (webhook, intégration, et plus tard un fournisseur d'identité, M24), elle ne fait confiance qu'à ce qui est dans `/etc/gitlab/trusted-certs/`, recopié à chaque `reconfigure`.

*La chaîne dans le `.crt`.* Ici, la CA signe directement le serveur : un client qui fait confiance à la racine vérifie le certificat seul. Servir aussi le certificat de la CA est sans inconvénient et suit la recommandation de la documentation de GitLab (chaîne complète, dans l'ordre) ; ce sera indispensable au M06, quand une CA **intermédiaire** signera les certificats.

*`gitlab-secrets.json`.* Créé à la première configuration, il contient les clés qui chiffrent en base les jetons, les variables CI, les secrets 2FA. Une sauvegarde de la base sans ce fichier est inexploitable pour tout ce qui est chiffré : il se sauvegarde **à part**, et c'est l'un des sujets de l'E28.

**Alternatives**

- *PKI* : `step certificate create` (CLI de Smallstep) pour une CA provisoire plus confortable qu'OpenSSL ; Easy-RSA ; ou attendre step-ca. Le choix d'OpenSSL ici est pédagogique : c'est l'outil qu'on retrouve partout, y compris pour diagnostiquer.
- *GitLab* : l'image conteneur officielle (module 12) ; l'opérateur ou le chart Helm sur Kubernetes (lourd, réservé aux grandes instances) ; Forgejo ou Gitea, beaucoup plus légers (quelques centaines de Mo), mais sans la CI intégrée de GitLab ni son écosystème.
- *Données* : un second disque dédié à `/var/opt/gitlab` (données, dépôts, base) facilite l'agrandissement, les sauvegardes et une éventuelle migration. Non retenu ici pour rester simple ; à considérer en production.
- *SSH* : `gitlab-sshd`, le serveur SSH intégré à GitLab, sur un port distinct, plutôt que le sshd du système. Le workbook garde le sshd du système sur le port 22 (PLAN §4.8) : un seul démon à durcir, et l'administration (`admin@`) et Git (`git@`) cohabitent sans conflit.

**Pièges classiques**

- Clé privée générée **avant** de régler `umask` ou les droits du dossier : elle a existé lisible par tous, même brièvement.
- Certificat sans SAN (seulement le CN) : les navigateurs l'acceptent parfois, Git et curl aussi, mais GitLab Runner (Go) le refuse en E23. Le check vérifie les trois SAN.
- Avec ECDSA, `keyUsage = keyEncipherment` copié d'un tutoriel RSA : certains clients rejettent la poignée de main.
- `-days 397` oublié : OpenSSL émet pour 30 jours par défaut, et la forge tombe un mois plus tard.
- `letsencrypt['enable']` absent : la reconfiguration tente une émission ACME vers Internet pour un nom `.internal`, qui échoue.
- Deux blocs `gitaly['env']` recopiés tels quels de la documentation : le premier est silencieusement écrasé par le second.
- Pas de swap : un OOM pendant la première configuration (migrations de base) laisse une installation à moitié faite. `sudo gitlab-ctl reconfigure` se relance sans danger.
- `qm clone` sans `--full 1` : clone lié au template, qui ne pourra plus être supprimé ni reconstruit (M03) sans casser `git01`.
- Résolveur ou heure faux sur `git01` : téléchargement des paquets impossible, ou certificat « pas encore valide » quand l'horloge retarde.
- Navigateur qui refuse le certificat : c'est **ton poste** qui ne connaît pas la CA. N'ajoute jamais d'exception de sécurité permanente ; importe la racine en connaissance de cause et retire-la au M06.
- Mot de passe initial de `root` laissé tel quel « pour plus tard » : le fichier disparaît au bout de 24 h lors d'une reconfiguration, et avec lui la seule trace du mot de passe ; il faudra alors le réinitialiser (`sudo gitlab-rake "gitlab:password:reset[root]"`).

**En production chez MédiSphère**

`git01` serait installé par un rôle Ansible (M04) à partir d'une image dorée (M03), avec `gitlab.rb` versionné et ses secrets en coffre (M25) ; le certificat serait émis et renouvelé automatiquement par ACME (M06) ; les données sur un volume dédié, sauvegardées par la sauvegarde applicative de GitLab **et** par la sauvegarde de VM (E28) ; la montée de version planifiée dans une fenêtre de changement (E29) ; la supervision branchée sur la plateforme commune (M21). Pour plus de quelques centaines d'utilisateurs, GitLab passe en architecture de référence (PostgreSQL, Redis et Gitaly séparés), dimensionnée selon la documentation.

---

### M01-E05 — Premiers pas d'administration GitLab : comptes, groupes, inscriptions

**Solution**

Scripts : [`fichiers/M01-E05/parametres-instance.sh`](fichiers/M01-E05/parametres-instance.sh) (paramètres de l'instance par l'API) et [`creer-comptes.sh`](fichiers/M01-E05/creer-comptes.sh) (comptes, groupes, appartenances ; idempotent).

*1 à 3. Paramètres et compte nominatif.* En `root` : *Admin → Settings → General → Sign-up restrictions* (décocher *Sign-up enabled*), puis *Visibility and access controls* (*Restricted visibility levels* : cocher *Public* ; *Default project visibility* et *Default group visibility* : *Private*). *Admin → Users → New user* pour `<MOI>`, niveau *Administrator* ; puis *Edit* sur la fiche pour fixer un mot de passe provisoire (à la première connexion, GitLab exige de le changer). Si la fiche indique une adresse non confirmée, le bouton *Confirm user* la confirme. Connexion avec `<MOI>` en navigation privée, changement du mot de passe, déconnexion de `root`.

*4. Jetons.*
```
admin@adm01:~$ umask 077
admin@adm01:~$ cat > ~/.config/workbook/gitlab-checks.token      # coller le jeton, Entrée, Ctrl+D
admin@adm01:~$ cat > ~/.config/workbook/gitlab-admin.token
admin@adm01:~$ ls -l ~/.config/workbook/gitlab-*.token
-rw------- 1 admin admin 27 … gitlab-admin.token
-rw------- 1 admin admin 27 … gitlab-checks.token
admin@adm01:~$ curl -sS --header "PRIVATE-TOKEN: $(<~/.config/workbook/gitlab-checks.token)" \
    https://git01.par1.medisphere.internal/api/v4/user | jq '{username, is_admin}'
{
  "username": "camille.durand",
  "is_admin": true
}
```
(La taille dépend du format de jeton de ta version ; le retour à la ligne final ajouté par la saisie est sans conséquence : `$(<fichier)` le retire.) Pourquoi le jeton des checks ne peut pas créer de projet : un jeton porte **ses propres** portées ; les droits effectifs d'une requête sont l'intersection des droits du compte et des portées du jeton. `read_api` n'autorise que les lectures, même pour un administrateur. C'est tout l'intérêt : un check qui fuit ne peut rien casser.

*5 à 6. Comptes, groupes, appartenances.*
```
admin@adm01:~$ bash ~/DevOpsPrivateCloud/modules/01-git/corrige/fichiers/M01-E05/creer-comptes.sh
compte claire.morel : créé (id 3, active)
…
groupe plateforme : créé (private)
groupe formation : créé (private)
plateforme : claire.morel = Reporter
plateforme : karim.benali = Maintainer
formation : karim.benali = Maintainer
…
```
Le cœur de la boucle :
```bash
api POST users --data-urlencode "username=$identifiant" --data-urlencode "name=$nom" \
  --data-urlencode "email=$adresse" -d force_random_password=true -d skip_confirmation=true
```
où `api` passe le jeton à `curl` par un en-tête lu sur l'entrée standard (`-H @-`), pour qu'il n'apparaisse pas dans la liste des processus. Niveaux d'accès : 10 Guest, 20 Reporter, 30 Developer, 40 Maintainer, 50 Owner (15 *Planner* existe aussi dans les versions récentes). Le créateur d'un groupe en devient Owner : `<MOI>` n'a pas à s'ajouter.

*7.* `ssh git01 sudo rm /etc/gitlab/initial_root_password`.

**Explications**

*Pourquoi pas `root` au quotidien.* Un compte partagé ne trace personne : le journal d'audit dit « root » et on ne sait pas qui. `root` reste le compte de **bris de glace** (perte de l'accès des administrateurs nominatifs, SSO en panne au M24), avec un mot de passe fort rangé hors du lab, et son usage est un événement qui se justifie.

*Les rôles.* Owner : administration du groupe (membres, suppression, paramètres) ; Maintainer : gestion des projets, des branches protégées, fusion sur `main` (E11) ; Developer : branches, MR, pas de fusion sur une branche protégée ; Reporter : lecture, tickets, commentaires (Claire, Sophie, Nadia, Julien : ils relisent, commentent, ne poussent pas). Un rôle accordé sur un groupe est hérité par tous ses projets.

*Les personnages sans mot de passe.* `force_random_password` leur donne un mot de passe que personne ne connaît : personne ne peut se connecter à leur place par l'interface. Les scripts du workbook agiront en leur nom avec des **jetons d'emprunt d'identité** (*impersonation tokens*), que seul un administrateur peut créer, qui sont tracés comme tels et révocables. C'est exactement le mécanisme qu'un administrateur utilise pour reproduire un problème « vu par » un utilisateur.

*Inscriptions et visibilité.* Une instance neuve accepte les inscriptions : n'importe qui ayant accès à la page pourrait se créer un compte et voir les projets *internal*. Interdire *Public* empêche qu'un projet devienne visible sans authentification par une erreur de clic ; la visibilité privée par défaut fait le reste.

*Jetons.* Les jetons personnels ont une date d'expiration **obligatoire** (365 jours au plus par défaut). Celui des checks dure longtemps parce qu'il ne peut que lire ; celui d'administration, puissant, expire vite : son renouvellement est une occasion de vérifier qu'il sert encore.

**Alternatives**

- Créer les comptes par la console Rails (`gitlab-rails console`) : puissant, mais sans validation de l'API, et sans trace d'audit aussi claire.
- Gérer comptes et groupes en code : provider OpenTofu `gitlabhq/gitlab` (M05) — groupes, membres, projets, protections décrits et revus en MR.
- Annuaire et SSO (LDAP, OIDC avec Keycloak au M24) : plus de comptes locaux, appartenance aux groupes synchronisée.
- Jetons de **service** (*service accounts*) plutôt que jetons personnels pour l'automatisation : disponibilité selon l'édition, à vérifier sur ta version.

**Pièges classiques**

- Créer les jetons sous `root` : l'automatisation se retrouve liée au compte de bris de glace.
- Jeton collé dans la commande (`echo glpat-… > fichier`) : il est dans l'historique du shell. Ou écrit sans `umask 077` : lisible un instant par tous.
- Jeton des checks avec la portée `api` « pour être tranquille » : un script de check bogué pourrait alors modifier l'instance. Le check exige `read_api` seule.
- Adresse du compte différente de `git config user.email` : les commits ne sont pas reliés au compte, et les signatures ne seront jamais « *Verified* » (E27).
- Oublier que le créateur d'un groupe en est Owner : le retirer laisse un groupe sans Owner nominatif.
- `POST /users` sans `skip_confirmation` sur une instance sans SMTP : comptes bloqués en attente d'une confirmation qui n'arrivera jamais.
- Activer le *mode administrateur* (*Admin Mode*) sans adapter les jetons : les appels d'administration des scripts échouent (portée `admin_mode` nécessaire).

**En production chez MédiSphère**

Authentification unique (M24) avec MFA obligatoire, comptes créés et désactivés automatiquement depuis l'annuaire (arrivées, départs), revue trimestrielle des membres des groupes et des jetons actifs, journal d'audit exporté vers la plateforme de logs (M22), jetons d'automatisation portés par des comptes techniques documentés dans l'inventaire, rotation planifiée. Le compte `root` est protégé par une procédure : mot de passe sous double contrôle, usage déclaré, mot de passe changé après chaque usage.

---

### M01-E06 — Migrer `~/medisphere` vers GitLab sans rien perdre

**Solution**

Scripts : [`fichiers/M01-E06/recherche-secrets.sh`](fichiers/M01-E06/recherche-secrets.sh) (étape 3) et [`verifier-migration.sh`](fichiers/M01-E06/verifier-migration.sh) (étape 8).

```
admin@adm01:~$ cd ~/medisphere
admin@adm01:~/medisphere$ git bundle create ~/medisphere-avant-migration.bundle --all && git bundle verify ~/medisphere-avant-migration.bundle
admin@adm01:~/medisphere$ git status --short ; git fsck --full
admin@adm01:~/medisphere$ git branch -a ; git tag -n ; git cat-file -t socle-v0
admin@adm01:~/medisphere$ git rev-list --all --count
admin@adm01:~/medisphere$ bash ~/DevOpsPrivateCloud/modules/01-git/corrige/fichiers/M01-E06/recherche-secrets.sh
admin@adm01:~/medisphere$ git branch -m master main            # seulement si la branche s'appelle master
```
Clé de connexion : *Avatar → Edit profile → SSH Keys → Add new key*, coller `~/.ssh/id_ed25519.pub`, usage *Authentication* (pas *Signing*), avec une date d'expiration si ta politique le demande. Empreinte de la clé d'hôte, par l'alias d'administration :
```
admin@adm01:~$ ssh git01 ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
256 SHA256:k2f…Q8 root@git01 (ED25519)
admin@adm01:~$ ssh -T git@git01.par1.medisphere.internal
The authenticity of host 'git01.par1.medisphere.internal (10.10.20.12)' can't be established.
ED25519 key fingerprint is SHA256:k2f…Q8.                     ← identique : on accepte
Welcome to GitLab, @camille.durand!
```
(Avec `StrictHostKeyChecking accept-new` de M00-E15, la question n'est pas posée et la clé est acceptée d'office : compare alors l'empreinte affichée par `ssh-keygen -F git01.par1.medisphere.internal -l` après coup.) Projet : *New project → Create blank project*, groupe `plateforme`, nom `medisphere`, visibilité *Private*, **décocher** *Initialize repository with a README*. Puis :
```
admin@adm01:~/medisphere$ git remote add origin git@git01.par1.medisphere.internal:plateforme/medisphere.git
admin@adm01:~/medisphere$ git push -u origin main
admin@adm01:~/medisphere$ git push origin --all
admin@adm01:~/medisphere$ git push origin --tags
admin@adm01:~/medisphere$ bash ~/DevOpsPrivateCloud/modules/01-git/corrige/fichiers/M01-E06/verifier-migration.sh
OK  références identiques (2 références)
OK  27 commits de part et d'autre, clone intègre
OK  socle-v0 : 4c1e… (tag)
```
(Nombres indicatifs.) Enfin, l'adresse du projet et la commande de clonage dans `docs/socle/README.md`, un commit `docs(socle): …` et un `git push` : c'est le premier push « normal », qui part directement grâce au suivi.

**Explications**

*`--tags` et `--follow-tags`.* `--tags` pousse **toutes** les étiquettes locales, y compris des étiquettes de travail que tu n'avais pas l'intention de publier. `--follow-tags` pousse les étiquettes **annotées** accessibles depuis les commits poussés : c'est le bon réflexe au quotidien (réglable par `push.followTags=true`). Ici, pour une migration complète, `--tags` est voulu ; vérifie d'abord la liste (`git tag`).

*Pourquoi un projet vide.* Si GitLab crée un README initial, la branche `main` du projet a un commit qui n'a rien à voir avec ton historique : ton push est refusé (non *fast-forward*), et la tentation de « forcer » ou de fusionner deux historiques sans rapport (`--allow-unrelated-histories`) est grande. Un projet vide reçoit ton historique tel quel.

*La clé d'hôte.* Le premier contact SSH est le moment où un intermédiaire pourrait se faire passer pour `git01`. Comparer l'empreinte par un **autre canal** (l'alias d'administration, déjà de confiance depuis l'E04, ou la console Proxmox) ferme cette porte. Le sshd de `git01` sert à la fois `admin@` et `git@` : c'est la même clé d'hôte, mais `known_hosts` l'enregistre sous deux noms (`10.10.20.12` et `git01.par1.medisphere.internal`).

*Comment GitLab sait qui tu es.* L'utilisateur SSH est toujours `git`. GitLab a écrit ta clé publique dans le fichier `authorized_keys` de l'utilisateur `git`, avec une commande forcée qui lance `gitlab-shell` et lui passe l'identifiant de la clé. C'est la **clé** qui t'identifie, d'où le message d'accueil à ton nom.

*Le bundle.* Un fichier unique, autoporteur, qui contient tout l'historique et toutes les références : on peut en cloner (`git clone medisphere-avant-migration.bundle`). C'est le filet de sécurité de la migration, et un excellent format d'archive ou de transfert hors ligne.

**Alternatives**

- `git push --mirror` : pousse **toutes** les références locales, y compris les branches de suivi et les notes, et **supprime** côté forge ce qui n'existe pas en local. Pratique pour une copie exacte d'un dépôt *nu* ; dangereux depuis un clone de travail (on publie ses références locales) et dans le mauvais sens.
- Importer le projet depuis une URL ou un fichier d'export GitLab : utile pour migrer d'une autre forge (tickets et MR compris), inutile pour un dépôt local.
- Cloner en HTTPS avec un jeton : à réserver aux automates ; pour un humain, la clé SSH avec phrase de passe et agent est plus sûre et plus simple.

**Pièges classiques**

- Pousser sans avoir cherché les secrets **dans l'historique** : un fichier supprimé il y a six mois est toujours dans un ancien commit, donc publié.
- Oublier les étiquettes : `git push -u origin main` ne pousse pas `socle-v0`.
- Pousser `master`, puis renommer sur la forge : branche par défaut à corriger, protections à refaire, collègues désorientés. On renomme **avant** de publier.
- URL `git@git01:plateforme/medisphere.git` : `git01` est ton alias d'administration (utilisateur `admin`, adresse IP). Le `git@` explicite l'emporte sur l'utilisateur de l'alias, donc ça fonctionne… jusqu'au jour où l'alias change. L'URL de référence est le nom complet.
- Déclarer la clé **de signature** au lieu de la clé de connexion : `Permission denied (publickey)`.
- Ajouter la clé dans le profil de `root` au lieu du tien : le message d'accueil le trahit.

**En production chez MédiSphère**

Une migration de dépôt est un changement : annoncée, avec gel des écritures sur l'ancien emplacement, vérification d'absence de perte (références et nombre de commits, comme ici), et ancien dépôt passé en lecture seule avec un renvoi vers le nouveau, puis archivé. Avant publication, l'historique est passé à Gitleaks (E16) et non à un simple `grep`. Les dépôts critiques sont en plus copiés vers PAR2 par la fonction *push mirror* de GitLab, qui complète les sauvegardes (E28).

---

### M01-E07 — Lire et construire un historique : branches, fusions, graphe

**Solution**

Script des étapes 4 et 5 : [`fichiers/M01-E07/construire-integration.sh`](fichiers/M01-E07/construire-integration.sh).

*Publication (étape 2).*
```
admin@adm01:~$ cd ~/src/git-labo
admin@adm01:~/src/git-labo$ git remote add origin git@git01.par1.medisphere.internal:formation/git-labo.git
admin@adm01:~/src/git-labo$ git push -u origin --all
admin@adm01:~/src/git-labo$ git push origin --tags
```
L'historique est reproductible : tes empreintes sont celles ci-dessous.
```
admin@adm01:~/src/git-labo$ git lg
* 7353370 (fonction/tri) feat: tri des VM par nom
* cfbeff6 (HEAD -> main) docs: ajout du contact d'astreinte
*   8a4a5d6 Merge branch 'fonction/sortie-json'
|\
| * f078db0 (fonction/sortie-json) feat: sortie JSON
* | 4018fe1 feat: sortie YAML
|/
* 6a45d5e Revert "feat: purge des anciens exports"
* 53be6f0 feat: purge des anciens exports
*   9c734ec (tag: v0.2.0) Merge branch 'fonction/export-csv'
|\
| * 3017846 (fonction/export-csv) test: jeu de données d'exemple
| * c842a7e feat: séparateur configurable
| * de0e84c feat: fonction exporter_csv
* | 656fede (correctif/espaces-noms) fix: noms de VM contenant des espaces
|/
* 5cd68d8 docs: reprise du projet par l'équipe Plateforme
| * 0d498a2 (infoger/ancien-format) WIP XML suite
| * 1d6a27e WIP format XML
|/
* fa9efed (tag: v0.1.0) Documentation
* 8eb01cd (tag: livraison-infoger) Corrections diverses
* f697bcc Ajout de la configuration
* 025a507 Version initiale du script d'inventaire
```

*Réponses (étape 3).*
1. `git rev-list --count main` → **16** commits ; `git rev-list --count --merges main` → **2** fusions ; `git rev-list --count --first-parent main` → **12**. La vue « premier parent » (`git log --first-parent main`) montre l'histoire **de `main` elle-même** : chaque fusion y apparaît comme un seul pas (« la fonctionnalité X est arrivée »), sans le détail des commits de la branche fusionnée. C'est la vue du journal des changements d'une branche intégrée par MR.
2. `git branch --merged main` → `correctif/espaces-noms`, `fonction/export-csv`, `fonction/sortie-json` (et `main`) ; `git branch --no-merged main` → `fonction/tri`, `infoger/ancien-format`.
3. Fusion en **avance rapide** : quand Karim a intégré le correctif, `main` n'avait pas bougé depuis le départ de la branche ; Git a simplement avancé `main` sur `656fede`. Preuve : `git merge-base --is-ancestor correctif/espaces-noms main && echo fusionnée`, et `656fede` apparaît **sur la ligne des premiers parents** de `main` (`git log --first-parent --oneline main`), comme si le commit avait été fait directement sur `main`.
4. `git log -S SEUIL_ALERTE --oneline` → `8eb01cd Corrections diverses`, InfoGér Support, 2 avril 2024 à 9 h 05 (`git log -1 --format='%an %ad' 8eb01cd`). Le message « Corrections diverses » ne dit rien de l'ajout d'une fonctionnalité d'alerte : seule la recherche dans le **contenu** des modifications le trouve. Leçon pour Conventional Commits (E14).
5. `git blame conf/inventaire.conf` → ligne 4 `SEPARATEUR=','` : `c842a7e`, Karim Benali, 15 janvier 2026, « feat: séparateur configurable ».
6. `git log -1 --format='%p' 8a4a5d6` → `4018fe1 f078db0`. Premier parent `4018fe1` (« feat: sortie YAML ») : la branche **sur laquelle** la fusion a été faite (`main`) ; second parent `f078db0` (« feat: sortie JSON ») : la branche fusionnée. Conflit : oui, dans `inventaire.sh` et `lib/format.sh`, les deux branches ayant ajouté une ligne au même endroit. `git show --remerge-diff 8a4a5d6` montre la fusion automatique avec ses marqueurs de conflit, et ce que Karim en a fait : il a gardé les deux formats, YAML puis JSON, et les deux fonctions.
7. `git log --oneline main..fonction/tri` → `7353370 feat: tri des VM par nom`. `git log --oneline infoger/ancien-format..main` → les 12 commits de `main` postérieurs à `v0.1.0` (de `5cd68d8` à `cfbeff6`). La différence symétrique avec repérage du côté : `git log --oneline --left-right main...infoger/ancien-format` (`<` côté `main`, `>` côté `infoger/ancien-format`, avec ses deux commits `WIP`).
8. `git log -S purger_exports --oneline` → `53be6f0` (ajout par Lucas) puis `6a45d5e` (annulation par Karim, avec la raison dans le message). Le code est **toujours dans l'historique** (`git show 53be6f0`) mais plus dans l'arbre de `main` : `git grep purger_exports main` ne trouve rien. Un `revert` ajoute, il n'efface pas.
9. `git cat-file -t v0.1.0` → `tag` (étiquette annotée : un objet, avec son auteur `InfoGér Support`, sa date du 15 mai 2024 à 14 h 20 et son message, visibles par `git cat-file -p v0.1.0` ou `git show v0.1.0`) ; `git cat-file -t livraison-infoger` → `commit` (étiquette légère : une simple référence, sans auteur ni date propres).

*Construction (étapes 4 et 5)* : voir le script. L'essentiel :
```
admin@adm01:~/src/git-labo$ git tag e07/seuil 8eb01cd && git push origin e07/seuil
admin@adm01:~/src/git-labo$ git switch -c e07/integration main
admin@adm01:~/src/git-labo$ git merge --ff-only e07/ajout-pbs
admin@adm01:~/src/git-labo$ git merge --no-ff --no-edit e07/ajout-dns
admin@adm01:~/src/git-labo$ git push -u origin e07/ajout-pbs e07/ajout-dns e07/integration
admin@adm01:~/src/git-labo$ git lg -n 5 e07/integration
*   b31c… Merge branch 'e07/ajout-dns' into e07/integration
|\
| * 9e0a… docs: ajouter une note sur la résolution DNS
* | 41d7… docs: mentionner la sauvegarde des exports sur PBS
|/
* cfbeff6 (origin/main, main) docs: ajout du contact d'astreinte
```
Pas de commit de fusion pour `e07/ajout-pbs` : quand on l'a intégrée, `e07/integration` était encore sur le commit de départ de `e07/ajout-pbs` ; il suffisait d'avancer la référence. Pour `e07/ajout-dns`, `e07/integration` avait bougé (elle contenait le commit PBS) : une vraie fusion était nécessaire, et `--no-ff` l'aurait de toute façon imposée.

**Explications**

*Parents d'une fusion.* L'ordre compte : le premier parent est toujours la branche courante au moment de la fusion. C'est ce qui rend `--first-parent` utile, et c'est ce que `git revert -m 1 <fusion>` désigne (« annule par rapport au premier parent »). Une fusion faite « à l'envers » (`main` fusionnée dans la branche, puis la branche avancée en *fast-forward* sur `main`) inverse les parents et brouille la vue `--first-parent` : c'est un argument pour laisser la forge faire les fusions (E10, E11).

*Plages.* `A..B` et `A...B` ne veulent pas dire la même chose pour `git log` (accessibles depuis B mais pas A ; différence symétrique) et pour `git diff` (`git diff A..B` = `git diff A B` ; `git diff A...B` = changements de B depuis l'ancêtre commun, ce que montre une MR). Source d'erreurs classique.

*`-S` et `-G`.* `-S` compte les occurrences : un commit qui déplace une ligne contenant la chaîne sans en changer le nombre n'est pas listé. `-G` liste les commits dont le diff contient une ligne ajoutée ou retirée correspondant à l'expression : plus bavard, mais il voit les déplacements.

**Alternatives**

- Outils graphiques (`gitk --all`, `tig`, le *Repository graph* de GitLab) pour explorer ; la ligne de commande pour répondre précisément et pour scripter.
- `git log --graph --simplify-by-decoration` pour ne garder que les commits étiquetés ou en tête de branche : la carte d'un gros dépôt.
- `git log --ancestry-path A..B` : seulement les commits qui sont à la fois descendants de A et ancêtres de B (« comment est-on passé de A à B »).

**Pièges classiques**

- Créer `e07/ajout-dns` à partir de `e07/ajout-pbs` (en oubliant de revenir sur `main`) : la seconde intégration devient elle aussi une avance rapide. Le check vérifie que les deux branches partent du même commit.
- `git merge e07/ajout-pbs` sans `--ff-only` : identique ici, mais si une condition change, une fusion est créée en silence ; `--ff-only` échoue au lieu de « faire autre chose ».
- Pousser l'étiquette avec `git push --follow-tags` : `e07/seuil` est **légère**, elle n'est pas poussée par `--follow-tags`.
- Poser une étiquette **annotée** pour `e07/seuil` : avec `tag.gpgSign` (E03), elle est même signée. Le check attend une étiquette légère, comme demandé ; corrige par `git tag -d`, `git push origin :refs/tags/e07/seuil`, puis recrée.
- Confondre « le commit qui a introduit » et « le dernier commit qui a touché » : `git log -S` sans `--reverse` liste du plus récent au plus ancien.

**En production chez MédiSphère**

Ces lectures sont le quotidien du diagnostic : « depuis quand ce paramètre existe-t-il, qui l'a introduit, dans quelle MR, pourquoi ? ». Elles ne marchent que si l'historique est **lisible** : messages explicites (E14), MR liées aux tickets, pas de commits « Corrections diverses ». C'est le premier argument des règles du palier 2.

---

### M01-E08 — Annuler proprement : `restore`, `reset`, `revert`, `reflog`

**Démarche et solution**

Script de la solution complète : [`fichiers/M01-E08/solution-e08.sh`](fichiers/M01-E08/solution-e08.sh). Au départ :
```
admin@adm01:~/src/git-labo$ git status
On branch e08/travail
Changes to be committed:
	new file:   secret.env
Changes not staged for commit:
	modified:   README.md
Untracked files:
	conf/exclusions.conf
admin@adm01:~/src/git-labo$ git lg -n 6 --branches='e08/*'
```

*Situation 1.* Diagnostic : `git diff README.md` montre la ligne parasite, non indexée. Commande : `git restore README.md` (copie la version de l'index sur le disque, pour ce fichier seulement). Pas `git reset --hard` (qui jetterait aussi l'indexation de `secret.env` : ici sans gravité, mais par principe on ne détruit que ce qu'on vise), pas `git checkout .` (tous les fichiers), pas `git stash` (garderait la modification qu'on veut jeter).

*Situation 2.* Diagnostic : `git diff --staged --stat` → `secret.env` en nouveau fichier indexé. Commande : `git restore --staged secret.env` (copie `HEAD` vers l'index pour ce chemin : comme le fichier n'existe pas dans `HEAD`, il est retiré de l'index), le fichier reste sur le disque. Puis `secret.env` dans le `.gitignore` du projet et `git commit -m "chore: ignorer secret.env"`. `git rm --cached secret.env` donne le même résultat ici ; `git rm secret.env` (sans `--cached`) **supprime le fichier** : c'est le piège. `.git/info/exclude` ne protégerait que ton clone : l'équipe ne serait pas protégée.

*Situation 3.* Diagnostic : `git log --oneline --stat -3` → le commit `fix: corection du filtre d'exclusion` ne touche que `inventaire.sh`, et le commit `chore` est par-dessus ; rien n'est publié (`git status` : pas de branche amont). Commandes :
```
admin@adm01:~/src/git-labo$ chore=$(git rev-parse HEAD)
admin@adm01:~/src/git-labo$ git reset --keep HEAD~1
admin@adm01:~/src/git-labo$ git add conf/exclusions.conf
admin@adm01:~/src/git-labo$ git commit --amend -m "fix: correction du filtre d'exclusion"
admin@adm01:~/src/git-labo$ git cherry-pick "$chore"
admin@adm01:~/src/git-labo$ git push
```
`reset --keep` recule la branche en gardant les fichiers non suivis et refuse de s'exécuter si une modification locale serait écrasée (plus sûr que `--hard`). `--amend` remplace le commit (nouvelle empreinte), `cherry-pick` recrée le commit `chore` par-dessus. Après le `reset`, `secret.env` n'est plus ignoré (le `.gitignore` est revenu à son état antérieur) jusqu'au `cherry-pick` : ne lance pas de `git add -A` entre-temps. Le premier `git push` crée la branche distante grâce à `push.autoSetupRemote`.

*Situation 4.*
```
admin@adm01:~/src/git-labo$ git switch e08/brouillon
admin@adm01:~/src/git-labo$ git reset --soft "$(git merge-base HEAD origin/main)"
admin@adm01:~/src/git-labo$ git status --short          # les trois changements, indexés
admin@adm01:~/src/git-labo$ git commit -m "feat: liste d'exclusion de l'inventaire"
admin@adm01:~/src/git-labo$ git push
```
`--soft` ne touche ni à l'index ni au disque : le contenu final des trois commits est intact, prêt à être recommité en un seul. Vérification : `git diff <ancienne pointe> HEAD` est vide (l'ancienne pointe est dans `git reflog`).

*Situation 5.*
```
admin@adm01:~/src/git-labo$ git switch e08/publiee
admin@adm01:~/src/git-labo$ git log --oneline origin/main..
admin@adm01:~/src/git-labo$ git revert --no-edit <EMPREINTE>   # celle de « feat: activer la purge automatique des exports »
admin@adm01:~/src/git-labo$ git push
```
`<EMPREINTE>` est à lire dans ton `git log` : les commits fabriqués pour l'E08 dépendent de la date à laquelle tu as lancé le script (empreintes ci-dessous indicatives, pour la même raison). La branche est publiée et utilisée par Karim : on **ajoute** un commit inverse. Pas de `reset` + `push --force` : Karim aurait encore l'ancien historique, et son prochain push le réintroduirait.

*Situation 6.*
```
admin@adm01:~/src/git-labo$ git reflog show e08/precieux
cfbeff6 e08/precieux@{0}: reset: moving to HEAD~2
1c6b828 e08/precieux@{1}: commit: feat: travail précieux (2/2)
d2a628b e08/precieux@{2}: commit: feat: travail précieux (1/2)
cfbeff6 e08/precieux@{3}: branch: Created from origin/main
admin@adm01:~/src/git-labo$ git switch e08/precieux
admin@adm01:~/src/git-labo$ git reset --hard 'e08/precieux@{1}'
admin@adm01:~/src/git-labo$ git push
```
Le reflog dit exactement ce qui s'est passé : un `reset` de deux commits. On remet la branche sur sa position précédente. `--hard` est acceptable **parce que** l'arbre de travail est propre (vérifié par `git status` juste avant) ; `git branch -f e08/precieux 1c6b828` depuis une autre branche ferait la même chose sans toucher au disque.

*Tableau de décision (étape 7)*

| Je veux défaire… | Commande | Si je me trompe, je perds… |
|---|---|---|
| une modification non indexée d'un fichier | `git restore <fichier>` | la modification (irrécupérable : jamais commitée) |
| une indexation | `git restore --staged <fichier>` | rien (le fichier reste sur le disque) |
| le dernier commit local (message, oubli) | `git commit --amend` | rien (l'ancien commit est dans le reflog) |
| plusieurs commits locaux, en gardant le travail | `git reset --soft <base>` (ou `--mixed`) | rien |
| plusieurs commits locaux, en jetant le travail | `git reset --hard <base>` | les modifications **non commitées** ; les commits restent dans le reflog |
| un commit publié | `git revert <commit>` (fusion : `-m 1`) | rien : on ajoute |
| une branche déplacée par erreur | `git reflog show <branche>` puis `git reset --hard <branche>@{N}` ou `git branch -f` | rien, tant que le reflog n'a pas expiré |

**Explications**

Les trois arbres : `HEAD` (le dernier commit de la branche), l'**index**, l'**arbre de travail**. `git restore` copie vers l'arbre de travail (depuis l'index, ou depuis un commit avec `--source`) ou, avec `--staged`, vers l'index (depuis `HEAD`). `git reset <commit>` déplace la branche puis recopie, selon le mode, vers l'index (`--mixed`) et l'arbre de travail (`--hard`). `git revert` ne déplace rien en arrière : il crée un commit. `restore` et `switch` (Git 2.23) ont été introduits pour séparer les deux rôles de l'ancien `checkout` (changer de branche / restaurer des fichiers), source de catastrophes (`git checkout -- .`).

Seuls les **commits** sont protégés par le reflog. Ce qui n'a jamais été commité (ni mis en *stash*) est perdu par un `restore` ou un `reset --hard` : d'où le réflexe « commit ou stash avant toute manipulation risquée ». Un `git add` crée bien des blobs, que `git fsck --lost-found` retrouve parfois, mais sans noms de fichiers.

**Alternatives**

- Situation 3 : `git commit --fixup=<commit>` puis `git rebase -i --autosquash` (E12) : l'outil normal pour corriger un commit ancien non publié.
- Situation 4 : `git merge --squash` depuis une nouvelle branche partie de `main`, ou le rebase interactif (E12) ; ou l'option *squash* de la MR (E09, E11), qui laisse la branche intacte et fusionne un seul commit.
- Situation 5 : si le commit fautif n'avait pas été publié, un rebase interactif l'aurait simplement retiré.
- Situation 6 : `git branch sauvetage 1c6b828` pour récupérer sans toucher à la branche, puis comparer.

**Pièges classiques**

- `git rm secret.env` au lieu de `git rm --cached secret.env` : le fichier disparaît du disque.
- `git reset --hard` « pour repartir propre » pendant la situation 3 : la modification de `README.md` (si la situation 1 n'est pas faite) est perdue, et le `.gitignore` aussi.
- Oublier de noter l'empreinte du commit `chore` avant de reculer : elle est dans `git reflog`, mais il faut la chercher.
- `git commit --amend` sur un commit **publié** : la branche distante diverge, et la tentation du `push --force` suit.
- Situation 5 par `reset` + `push --force` : le check voit disparaître le commit d'origine. Sur une vraie branche partagée, l'erreur est réintroduite par le premier collègue qui pousse.
- `git reset --hard HEAD@{1}` au lieu de `e08/precieux@{1}` : le reflog de `HEAD` contient aussi les changements de branche (`switch`) ; `HEAD@{1}` n'est pas forcément la position de la branche avant l'accident.

**En production chez MédiSphère**

Sur les branches protégées (E11), la question ne se pose pas : la forge refuse les réécritures, on annule par `revert` en MR, avec un message qui explique pourquoi. Sur les branches personnelles, chacun réécrit librement avant la revue. Et le tableau de décision est affiché dans le CONTRIBUTING de l'équipe (E22) : les incidents « j'ai tout perdu » (E42) sont presque toujours un `reset --hard` ou un `checkout` sur des modifications jamais commitées.

---

### M01-E09 — Questions : modèles de branches et choix pour l'équipe Plateforme

**Barème** : 2 points par question, total sur 30. 2 = réponse argumentée et appliquée au contexte de l'équipe ; 1 = définition correcte sans application ; 0 = faux ou blanc.

**Réponses argumentées**

**1. Git Flow.** Branches permanentes `master` (versions publiées, étiquetées) et `develop` (intégration) ; branches temporaires `feature/*` (depuis et vers `develop`), `release/*` (stabilisation d'une version, depuis `develop`, fusionnée dans `master` **et** `develop`), `hotfix/*` (depuis `master`, fusionnée dans `master` et `develop`). Un correctif urgent part de `master`, est étiqueté, puis réintégré dans `develop`. Conçu en 2010 pour des logiciels **livrés par versions**, avec plusieurs versions en circulation. En 2020, son auteur a ajouté en tête de l'article une note : pour des applications livrées en continu (applications web), il recommande un modèle plus simple comme GitHub Flow, Git Flow restant adapté aux logiciels explicitement versionnés et maintenus en plusieurs versions.

**2. GitHub Flow.** Une seule branche durable, `main`, toujours déployable ; tout changement part d'une branche courte, passe par une *pull request* relue et testée, est fusionné puis **déployé immédiatement**. Hypothèse : on déploie `main` (ou la branche juste avant fusion) en continu ; il n'y a qu'une version en production.

**3. Trunk-based development.** Tout le monde intègre sur le tronc (`main`) au moins une fois par jour, soit directement (petites équipes très outillées), soit par des branches de très courte durée (quelques heures à deux jours) et de petites MR. Une fonctionnalité inachevée est livrée **désactivée** derrière un *feature flag*, ou découpée pour que chaque étape soit utile ou inerte. Prérequis : une CI rapide et fiable, et des revues rapides.

**4. Branches d'environnement pour l'IaC.** Avec une branche par environnement (`staging`, `production`), on promeut en fusionnant d'une branche à l'autre. Pour du code d'infrastructure, les branches **dérivent** : correctifs faits directement sur `production` et jamais remontés, fusions partielles, conflits ; personne ne sait plus ce que contient vraiment chaque environnement, et le `diff` entre branches mélange code et configuration. On préfère **une seule branche** (`main`) et des environnements distingués par des **dossiers ou des fichiers de variables** (`inventories/lab/`, `envs/prod/`, M04 et M05), le même code étant appliqué à chaque environnement avec sa configuration ; la promotion se fait par **version** des modules (étiquettes) ou par étapes de pipeline.

**5. Réponse B.** Une branche de trois semaines s'éloigne de `main` : conflits d'intégration croissants, MR énorme que personne ne relit vraiment, décisions de conception découvertes trop tard, et code testé sur une base qui n'existe plus. A est négligeable (Git déduplique). C est faux (GitLab ne supprime pas les branches inactives de lui-même). D est faux : pousser sauvegarde, mais n'**intègre** rien.

**6. Méthodes de fusion de GitLab.** Deux MR successives `A` (commits a1, a2) puis `B` (b1), parties de `M` :
```
Merge commit :                       M ─────────── MA ────── MB         (MA, MB : commits de fusion)
                                      ├─ a1 ─ a2 ─┘          │
                                      └─ b1 ────────────────┘           (b1 part toujours de M)
   → n'exige rien ; historique fidèle, mais branches entrelacées.

Merge commit with semi-linear history :
                                     M ─────────── MA ─────────── MB
                                      └─ a1 ─ a2 ─┘└─ b1' ───────┘      (b1' : B rebasée sur MA)
   → exige que la source soit à jour (rebase sur la cible) ; chaque MR reste visible
     comme une « bulle » par son commit de fusion, et la ligne principale est linéaire.

Fast-forward merge :                 M ─ a1 ─ a2 ─ b1'                  (aucun commit de fusion)
   → exige que la source soit à jour (rebase) ; historique parfaitement linéaire,
     mais la frontière entre MR n'apparaît plus dans le graphe.
```
Dans les deux derniers cas, GitLab propose un bouton *Rebase* dans la MR quand la cible a avancé.

**7. *Squash*.** Les commits de la MR sont réduits à **un seul** commit au moment de la fusion. Apport : un historique de `main` sans les « wip » et « correction typo », un commit par changement livré, facile à annuler. Perte : le découpage en étapes (utile au `bisect` et à la compréhension), et le lien Git avec la branche (elle n'apparaît pas comme fusionnée). Le message du commit obtenu est, par défaut, le **titre de la MR** (modèle réglable par projet). Conséquence avec semantic-release : c'est ce message qui décide de la version ; un titre de MR non conforme à Conventional Commits fait « disparaître » le changement des notes de version, ou mal calculer le numéro. Il faut donc imposer aussi la convention sur les **titres de MR** (E22, E24).

**8. Mettre sa branche à jour.** Rebase sur `main` : historique propre, conflits résolus commit par commit, réécriture de **ta** branche (acceptable tant que personne d'autre ne travaille dessus ; avec `--force-with-lease`). Fusion de `main` dans la branche : aucune réécriture, mais des commits « *Merge branch 'main' into …* » qui encombrent la MR. Le rebase est interdit quand la branche est **partagée** (deux personnes poussent dessus) sans accord explicite ; et inutile si la méthode de fusion de la forge s'en charge.

**9. Impact sur `bisect` et `--first-parent`.** Historique linéaire (*fast-forward*, semi-linéaire) : `bisect` parcourt une ligne simple ; avec des commits atomiques qui compilent chacun, il désigne précisément le fautif. Avec des fusions entrelacées, `bisect` doit aussi tester des commits de branches qui n'ont jamais été dans cet état sur `main` (`git bisect start --first-parent` existe pour l'éviter). Avec *squash*, `bisect` trouve la **MR** fautive, pas l'étape. `git log --first-parent main` donne « une ligne par MR » avec les méthodes à commit de fusion ; avec *fast-forward*, tous les commits de toutes les MR.

**10. Branches de maintenance.** Quand une ancienne version doit continuer à recevoir des correctifs alors que `main` a avancé (un module consommé en `1.x` par un projet qui ne peut pas encore passer en `2.x`). Le correctif est fait sur `main`, puis **rétroporté** par `cherry-pick -x` sur la branche de maintenance (E19), et une version corrective est publiée depuis celle-ci. semantic-release reconnaît par défaut les branches nommées `N.x` ou `N.N.x` (par exemple `1.x`, `1.2.x`) comme branches de maintenance et y publie des versions dans la plage correspondante (E25).

**11. Étiquettes de version.** Dans le modèle cible, c'est **le pipeline de release** (semantic-release, E25) qui calcule la version, pose l'étiquette `vX.Y.Z` et publie la release, avec un jeton dédié. Les étiquettes sont **protégées** (E25) : seuls ce jeton et les Maintainers peuvent les créer, personne ne peut les déplacer ou les supprimer par erreur. Une étiquette de version est une **promesse** : `v1.4.0` doit désigner pour toujours le même code, sinon les dépôts qui consomment ce module par version reçoivent autre chose que ce qu'ils ont testé.

**12. Réponse C.** Les approbations **obligatoires** (règles d'approbation, nombre minimal d'approbateurs) sont réservées aux éditions payantes ; dans CE, on peut approuver une MR, mais rien ne l'exige. A est possible (branche protégée : *Allowed to push* = personne, E11). B est possible (*Pipelines must succeed*, E24). D est possible (*All threads must be resolved*, E11).

**13. Compenser l'absence d'approbation obligatoire.** Règle d'équipe écrite (CONTRIBUTING, E22) : « on ne fusionne pas sa propre MR » ; fusion réservée aux Maintainers (branche protégée), l'auteur étant le plus souvent Developer ; discussions résolues obligatoires (le relecteur ouvre au moins un fil) ; pipeline obligatoire ; et un contrôle **a posteriori** : un job ou un script qui vérifie, via l'API, que chaque MR fusionnée l'a été par quelqu'un d'autre que son auteur, et alerte sinon. C'est un contrôle compensatoire : il se documente comme tel dans l'ADR et pour l'audit de Sophie.

**14. Proposition (exemple en dix lignes).**
1. Une seule branche durable : `main`, protégée, toujours applicable.
2. Branches courtes `<type>/<sujet>` (`feat/…`, `fix/…`, `docs/…`, `chore/…`), deux à trois jours au plus.
3. Tout passe par une MR, petite, relue par un autre membre, discussions résolues, pipeline vert.
4. Méthode de fusion : celle arrêtée en E11 (commit de fusion avec historique semi-linéaire, ou *fast-forward*), la même sur tous les projets `plateforme/*`.
5. Branche mise à jour par rebase sur `main` avant fusion ; jamais de rebase d'une branche partagée sans accord.
6. Commits et titres de MR en Conventional Commits.
7. Versions et étiquettes `vX.Y.Z` posées par semantic-release, étiquettes protégées.
8. Environnements distingués par des dossiers et des variables, jamais par des branches.
9. Branches de maintenance `N.x` seulement pour un module dont une ancienne majeure est encore consommée ; correctifs rétroportés par `cherry-pick -x`.
10. Fonctionnalités inachevées : découpées ou désactivées, jamais de branche longue.

**15. Réponse à Julien.** Pas d'obligation de changer : le modèle d'une équipe se juge à son contexte. Git Flow reste défendable si MédiAgenda est **livrée par versions** (et non déployée en continu), avec plusieurs versions maintenues en parallèle chez des clients, et une phase de stabilisation réelle. Mais si l'application est déployée sur la plateforme dès qu'elle est prête (ce sera le cas avec GitOps au M20), `develop` et `release/*` ajoutent des fusions, des conflits et du délai sans valeur : l'évolution naturelle est GitHub Flow ou le tronc, avec des *feature flags*. L'important pour la plateforme est l'interface entre les équipes : versions étiquetées, Conventional Commits, et pipelines qui consomment les gabarits CI communs.

**Grille d'auto-évaluation**

| Score /30 | Lecture | Conseil |
|---|---|---|
| 25 à 30 | Vision claire des modèles et de leurs effets | Tu peux arbitrer en E11 sans relire la documentation. |
| 18 à 24 | Bonne connaissance, application au contexte à affiner | Relis les questions 4, 6 et 7 : ce sont elles qui fondent les réglages de l'E11. |
| Moins de 18 | Notions à consolider | Lis la page *Merge methods* de GitLab et l'article de Driessen avec sa note de 2020, puis refais les questions 6 à 9. |

Ressources : *A successful Git branching model* (V. Driessen) et sa note de 2020 ; <https://trunkbaseddevelopment.com/> ; documentation GitLab, *Merge requests → Merge methods* et *Squash and merge* ; documentation de semantic-release, *Workflow configuration* (branches de maintenance).
