# Module 01 — Palier 2 : Opérationnel

La forge tourne, le dépôt du socle y est migré, et tu sais lire et défaire un historique. Il faut maintenant que l'équipe **travaille** avec : chaque changement passe par une merge request relue, `main` ne se touche plus à la main, les messages de commit deviennent une donnée exploitable, et les secrets sont arrêtés avant de quitter un poste. Les tickets de ce palier sont ceux des premières semaines d'une forge en production : Karim relit tes MR et t'en fait relire, Sophie surveille tout ce qui ressemble à un jeton, Nadia a besoin d'un correctif pour cette nuit, Julien d'un rétroportage pour son équipe. Tu termines en écrivant les règles du jeu pour ceux qui arrivent.

> **Où travailler ?** Toujours depuis `adm01`. Les projets de la plateforme (`plateforme/medisphere`, clone `~/medisphere`) ne reçoivent que des changements **réels** et propres. Les manipulations d'historique se font dans le bac à sable `formation/git-labo` (clone `~/src/git-labo`, branches `eXX/…`) ou dans les projets d'exercice créés par les scripts de `ressources/`.
>
> **Scripts de ressources.** Ils se lancent depuis le dépôt du workbook (`~/DevOpsPrivateCloud`), lisent `lab/lab.env` et, quand ils agissent sur GitLab, ton **jeton d'administration** (`~/.config/workbook/gitlab-admin.token`, E05). Quand un personnage commente ou ouvre une MR, le script crée un **jeton d'emprunt d'identité** valable un jour et le révoque en sortant. Lis chaque script avant de le lancer.

---

### M01-E10 — Le cycle d'une merge request : branche, revue, suggestions, fusion  `LAB` `★`

> **Ticket PLAT-220** — *De : Karim Benali*
> La forge est en place, mais personne d'autre que toi ne sait s'en servir. Écris la fiche de service de la forge dans `plateforme/medisphere`. Et fais-le comme on fera désormais **tout** : une branche, une merge request, ma relecture, tes corrections, mon accord, puis la fusion. Je veux voir le cycle complet, pas seulement le résultat.

**Objectifs pédagogiques**
- Parcourir le cycle de vie d'une merge request (MR) : brouillon, relecteurs, fils de discussion, suggestions, nouvelles versions, approbation, fusion.
- Créer une MR depuis la ligne de commande avec les *push options* de GitLab.
- Comprendre ce que GitLab écrit dans ton dépôt à ta place (commits de suggestion, commit de fusion).

**Prérequis** : M01-E05 (comptes, jeton d'administration), M01-E06 (`plateforme/medisphere`).
**Durée indicative** : 1 h 30.

**Contexte technique**
- Projet `plateforme/medisphere`, clone `~/medisphere` (`WB_DEPOT`). Pas encore de règle de protection : c'est l'objet de E11. Ne pousse quand même rien sur `main`.
- Branche : `docs/fiche-forge`. Fichier à créer : `docs/socle/forge.md`.
- Contenu attendu de la fiche : identité du service (URL, accès Git en SSH, hôte, VMID, adresse), certificat et autorité qui le signe, comptes d'administration (sans aucun mot de passe), organisation des groupes `plateforme` et `formation`, commandes d'exploitation de base.
- Relecture : [`ressources/M01-E10/revue-karim.sh`](../ressources/M01-E10/revue-karim.sh). Sans option, Karim dépose sa revue sur la MR ouverte depuis `docs/fiche-forge` ; avec `--approuver`, il vérifie que ses remarques sont traitées, puis approuve (ou explique pourquoi il n'approuve pas).
- Dans GitLab CE, l'approbation existe mais n'est **pas bloquante** : c'est une règle d'équipe (voir E11).

**Travail demandé**
1. Mets ton clone à jour, crée la branche, rédige la fiche. Fais un ou deux commits avec des messages de la forme `docs(socle): …` (la convention sera imposée en E14 ; prends l'habitude).
2. Pousse la branche en créant la MR **en brouillon** directement depuis la ligne de commande, avec les *push options* de GitLab (cible `main`, titre, brouillon, suppression de la branche source à la fusion). Puis, dans l'interface : description (contexte, contenu, comment tu as vérifié), toi en *assignee*, `karim.benali` en relecteur (*reviewer*).
   ```
   admin@adm01:~/medisphere$ git push -u origin docs/fiche-forge -o merge_request.create -o …
   ```
3. Relis toi-même le diff dans l'onglet *Changes* avant de solliciter Karim. Puis sors la MR du mode brouillon et lance la revue :
   ```
   admin@adm01:~/DevOpsPrivateCloud$ modules/01-git/ressources/M01-E10/revue-karim.sh
   ```
4. Traite les trois fils de Karim :
   - applique sa **suggestion** avec le bouton de l'interface, puis regarde dans ton clone ce que GitLab a fait (`git fetch`, `git log origin/docs/fiche-forge`) : auteur, message, emplacement du commit ;
   - réponds à sa question dans le fil ;
   - complète la fiche dans ton clone et pousse un nouveau commit. Si le push est refusé, comprends pourquoi avant d'agir ;
   - résous les fils. Note dans ton journal : qui **devrait** résoudre un fil, l'auteur de la MR ou celui qui l'a ouvert ?
5. Compare la première et la dernière version de la MR (sélecteur de versions de l'onglet *Changes*).
6. Demande l'approbation :
   ```
   admin@adm01:~/DevOpsPrivateCloud$ modules/01-git/ressources/M01-E10/revue-karim.sh --approuver
   ```
7. Fusionne. Nettoie ton clone : retour sur `main` à jour, branche locale supprimée, références distantes élaguées. Regarde le graphe (`git log --graph --oneline -5`) : quel commit GitLab a-t-il créé, avec quel message ?
8. Dans ton journal : la différence entre *assignee* et *reviewer* ; le message du commit de suggestion et le problème qu'il posera quand les messages seront contrôlés (E14).

**Critères de réussite**
- [ ] Une MR depuis `docs/fiche-forge` est fusionnée dans `main`, avec une description utile.
- [ ] Les trois fils de `karim.benali` ont reçu une réponse et sont résolus.
- [ ] La MR a été approuvée par `karim.benali` avant la fusion.
- [ ] `docs/socle/forge.md` est sur `main`, avec le titre suggéré par Karim et la section qu'il a demandée.
- [ ] La branche `docs/fiche-forge` n'existe plus, ni sur GitLab ni dans ton clone.

**Vérification** : `lab/bin/check 01 10`

<details><summary>Indice 1</summary>

Les *push options* se passent avec `git push -o <option>` (ou `--push-option`), une option par `-o`. La liste est dans la documentation de GitLab, page « Push options » : cherche celles qui commencent par `merge_request.`. Une valeur contenant des espaces doit être entre guillemets.
</details>

<details><summary>Indice 2</summary>

Appliquer une suggestion crée un commit **sur la branche distante**. Ton clone ne le connaît pas : ton prochain push est refusé (*non-fast-forward*). Récupère d'abord ce commit, puis rejoue ou fusionne tes changements locaux. Le réglage `pull.rebase` choisi en E03 décide de ce que fait `git pull`.
</details>

<details><summary>Indice 3</summary>

Si le script répond « aucune MR ouverte depuis la branche docs/fiche-forge », vérifie le nom exact de la branche source et que la MR n'est ni fusionnée ni fermée. S'il échoue sur la création du jeton d'emprunt d'identité, vérifie la portée de ton jeton d'administration (`api`) et qu'il n'a pas expiré.
</details>

**Pour aller plus loin** (facultatif) : récupère la MR d'un collègue sans connaître sa branche : `git fetch origin merge-requests/<IID>/head:mr-<IID>`. Essaie le mode « Démarrer une revue » (*Start a review*), qui publie tous tes commentaires d'un coup. Installe la CLI officielle `glab` et refais le cycle sans l'interface. Documentation : <https://docs.gitlab.com/user/project/merge_requests/>.

---

### M01-E11 — Protéger `main` : branches protégées et règles de fusion (limites de CE)  `LAB` `★★`

> **Ticket CHG-221** — *De : Claire Morel* — *Cc : Sophie Laurent, Karim Benali*
> Validé en réunion d'équipe : plus aucun push direct sur `main` dans le groupe `plateforme`, fusion uniquement par MR relue, discussions closes avant fusion, historique lisible. Sophie voulait aussi des approbations obligatoires et des responsables de code par dossier : vérifie ce que notre édition permet, et propose des compensations pour le reste. Les prochains projets (`plateforme/outils` dès le module 02) doivent naître avec ces règles, sans que personne ait à y penser.

**Objectifs pédagogiques**
- Configurer une branche protégée : qui pousse, qui fusionne, push forcé.
- Choisir et argumenter une méthode de fusion (commit de fusion, commit de fusion semi-linéaire, fast-forward) et les réglages de MR associés.
- Distinguer ce que fait GitLab CE de ce qui est réservé aux éditions payantes, et compenser.
- Rendre la configuration reproductible par l'API.

**Prérequis** : M01-E10.
**Durée indicative** : 2 h.

**Contexte technique**
- Règles à appliquer à `plateforme/medisphere` (et à tout futur projet `plateforme/*`) :

| Règle | Valeur |
|---|---|
| `main` : push direct | personne (*No one*) |
| `main` : fusion | Maintainers |
| `main` : push forcé | interdit |
| Méthode de fusion | commit de fusion avec historique semi-linéaire **ou** fast-forward : à toi de choisir et d'argumenter, le choix vaudra pour tout le workbook |
| Fusion | impossible tant qu'un fil de discussion est ouvert |
| Squash | autorisé, pas imposé |
| Branche source | supprimée par défaut à la fusion |
| Message des suggestions appliquées | conforme à Conventional Commits (E14) |
| Pipeline réussi obligatoire | pas encore : il arrive en E24 |

- Script à écrire : `~/lab-scripts/gitlab-proteger-projet.sh GROUPE/PROJET`, qui applique ces règles par l'API avec le jeton d'administration, sans l'afficher. Il doit être **idempotent** (relancé, il ne casse rien et le dit), proposer un mode `--dry-run`, et passer `shellcheck`.
- Le bac à sable `formation/git-labo` reste **sans protection** : n'y applique pas ces règles.
- Approbations obligatoires, règles d'approbation, *push rules* (contrôle du message, de la taille des fichiers, des secrets, de la signature au push) et *Code Owners* obligatoires sont des fonctions **Premium** : elles n'existent pas dans GitLab CE.

> ⚠️ **Attention** : une fois `main` protégée en « No one », **toi non plus** ne peux plus y pousser, même en administrateur. Tout passe par une MR. Si une urgence l'exige, un Maintainer peut lever la protection le temps d'une opération : c'est visible, et il faut la remettre aussitôt. Avant de commencer, vérifie que ton clone `~/medisphere` n'a aucun commit local non publié sur `main`.

**Travail demandé**
1. Inspecte l'état actuel par l'API (branche protégée `main` du projet, réglages de MR du projet, réglage de protection par défaut du groupe `plateforme`). Note les valeurs par défaut : ce sont celles que tu vas remplacer.
2. Dans ton journal, dessine le graphe obtenu sur `main` après la fusion de deux MR avec chacune des trois méthodes de fusion. Pour chacune : lisibilité de `git log --first-parent`, utilisabilité de `git bisect`, contrainte imposée aux auteurs (rebase avant fusion), conservation des commits relus, conséquences pour semantic-release (E25) qui lit les messages de commit. Choisis, et écris ta justification en cinq lignes.
3. Applique les règles à `plateforme/medisphere` **dans l'interface** (*Settings > Repository > Protected branches* ; *Settings > Merge requests*). Pour le message des suggestions, consulte la liste des variables disponibles.
4. Teste chaque règle et note le message obtenu :
   - un `git push` direct sur `main` depuis ton clone ;
   - un `git push --force` sur `main` ;
   - une MR avec un fil ouvert (bouton de fusion) ;
   - le point de vue d'un Developer : dans *Admin > Users*, emprunte l'identité de `lucas.martin` (*Impersonate*), ouvre une MR existante, observe, puis reviens à ton compte. Cet emprunt est journalisé : c'est voulu.
5. Groupe `plateforme` : regarde le réglage de protection par défaut de la branche principale (*Settings > Repository > Default branch*). Que recevra un projet créé demain ? Pourquoi « No one » n'est-il pas proposé à ce niveau ? Règle-le au plus strict possible.
6. Écris `gitlab-proteger-projet.sh`. Teste-le en `--dry-run` sur `plateforme/medisphere`, puis pour de vrai (il doit répondre que tout est déjà en place). Teste-le enfin sur un projet jetable `formation/essai-protection` que tu crées puis supprimes (selon le réglage de l'instance, la suppression peut être différée de quelques jours).
7. Réponds au ticket : ce que tu as mis en place, ce que CE ne permet pas, et pour chaque manque la compensation proposée (règle d'équipe, trace dans les messages de fusion, CI obligatoire en E24, hooks côté serveur en E26, signature en E27…).

**Critères de réussite**
- [ ] `main` de `plateforme/medisphere` : push « No one », fusion « Maintainers », push forcé interdit.
- [ ] Un fil ouvert empêche la fusion ; la méthode de fusion est semi-linéaire ou fast-forward, et ton choix est argumenté.
- [ ] Le message des suggestions appliquées est conforme à Conventional Commits.
- [ ] Un push direct sur `main` est refusé avec un message explicite.
- [ ] `~/lab-scripts/gitlab-proteger-projet.sh` existe, est exécutable, ne contient aucun jeton, passe `shellcheck`, et relancé sur `plateforme/medisphere` ne change rien.
- [ ] La réponse au ticket liste les fonctions Premium manquantes et une compensation pour chacune.

**Vérification** : `lab/bin/check 01 11`

<details><summary>Indice 1</summary>

Documentation de l'API : « Protected branches API » (niveaux d'accès : 0, 30, 40, 60) et « Projects API » (attributs `merge_method`, `squash_option`, `only_allow_merge_if_all_discussions_are_resolved`, `suggestion_commit_message`, `merge_commit_template`). Pour le groupe, attribut `default_branch_protection_defaults` de la « Groups API ».
</details>

<details><summary>Indice 2</summary>

Dans CE, les champs de l'API qui permettent de **modifier** les niveaux d'accès d'une protection existante sont marqués Premium. Pour changer « qui peut pousser » sur une branche déjà protégée, il faut une autre approche : laquelle, et quel est le risque pendant l'opération ?
</details>

<details><summary>Indice 3</summary>

commitlint ignore par défaut certains messages produits par Git et GitLab. Vérifie lesquels (`defaultIgnores` dans la documentation de commitlint) avant de toucher au modèle du commit de fusion : sa première ligne compte.
</details>

**Pour aller plus loin** (facultatif) : ajoute au modèle de message de fusion la variable qui liste les approbateurs : l'historique Git garde alors la preuve de la relecture, utile en audit HDS. Lis la page « Protected branches » sur les branches protégées par motif (`release/*`) et sur qui peut retirer une protection. Documentation : <https://docs.gitlab.com/user/project/repository/branches/protected/>.

---

### M01-E12 — Rebase interactif : préparer une branche pour la revue  `LAB` `★★`

> **Ticket PLAT-222** — *De : Karim Benali*
> J'ai regardé ta branche `e12/verif-sauvegardes` dans le bac à sable : 7 commits, dont « wip », « debug », « oups »… et un commit qui affiche le mot de passe PBS sur la sortie d'erreur. Avec notre méthode de fusion, chaque commit de la branche arrive **tel quel** dans `main`. Avant que je relise : un commit = un changement qui tient debout seul, des messages propres, plus aucune trace du débogage, et la branche à jour de `main`.

**Objectifs pédagogiques**
- Réécrire une branche personnelle avec `git rebase -i` : réordonner, fusionner, renommer, supprimer des commits.
- Vérifier chaque commit pendant le rebase, et prouver que le résultat final n'a pas changé.
- Publier une branche réécrite sans écraser le travail d'un autre (`--force-with-lease`).
- Se rattraper après un rebase raté.

**Prérequis** : M01-E07 (`~/src/git-labo`), M01-E08 (`reflog`), M01-E10.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Préparation : [`ressources/M01-E12/fabriquer-depot.sh`](../ressources/M01-E12/fabriquer-depot.sh). Il pousse dans `formation/git-labo` la branche `e12/verif-sauvegardes` (7 commits à ton nom, dossier `rebase/`) et fait avancer `main` d'un commit de Karim. `--reinitialiser` remet la branche dans son état de départ.
- Résultat attendu : la branche, rebasée sur le `main` actuel, contient **deux** commits au format Conventional Commits : le script (`rebase/verif-pbs.sh`) d'un côté, son mode d'emploi (`rebase/verif-pbs.md`) de l'autre. Chaque commit passe `bash -n`. Aucun commit ne contient `set -x` ni la ligne de débogage. Le contenu final des deux fichiers est **identique** à celui de la branche de départ.
- Tu peux réécrire cette branche parce qu'elle est à toi et que personne ne travaille dessus. On ne réécrit jamais `main` ni une branche partagée.

**Travail demandé**
1. Lance le script, puis récupère la branche dans ton clone. Lis chaque commit (`git log -p origin/main..origin/e12/verif-sauvegardes`). Dans ton journal, écris ton plan : quels commits fusionner, lesquels supprimer, lesquels renommer, dans quel ordre.
2. Pose un filet de sécurité : une branche locale `sauvegarde/e12-avant-rebase` sur l'état actuel de ta branche.
3. Lance le rebase interactif sur `origin/main`. Fais vérifier `bash -n rebase/verif-pbs.sh` automatiquement après chaque commit réécrit.
4. Prouve le résultat :
   - `git log --oneline origin/main..HEAD` : deux commits, messages conformes ;
   - `git diff sauvegarde/e12-avant-rebase HEAD -- rebase/verif-pbs.sh rebase/verif-pbs.md` : vide ;
   - `git range-diff` entre l'ancienne et la nouvelle série : lis-le et explique une ligne `!` dans ton journal.
5. Publie. Un `git push` simple est refusé : pourquoi ? Compare `--force`, `--force-with-lease` et `--force-if-includes` : que se passerait-il avec chacun si Karim avait poussé un commit sur ta branche entre-temps ?
6. Ouvre une MR vers `main` (ne la fusionne pas : c'est un exercice).
7. Exercice de rattrapage : sur une copie de la branche, fais exprès un rebase désastreux (supprime le mauvais commit), puis retrouve l'état précédent **sans** utiliser ta branche de sauvegarde.
8. Dans ton journal : différence entre `squash` et `fixup` ; pourquoi un commit `fixup! …` oublié passerait commitlint (E14) et ce qu'il faut pour l'empêcher d'arriver dans `main`.

**Critères de réussite**
- [ ] `e12/verif-sauvegardes` part du dernier commit de `main` et contient deux commits (trois au plus) au format Conventional Commits.
- [ ] Aucun commit de la branche ne contient `set -x`, la ligne de débogage, ni une erreur de syntaxe.
- [ ] Le contenu final de `rebase/verif-pbs.sh` et `rebase/verif-pbs.md` est identique à celui de départ (diff vide avec ta sauvegarde).
- [ ] Une MR est ouverte depuis la branche.
- [ ] Ton journal explique le choix de `--force-with-lease` et la procédure de rattrapage.

**Vérification** : `lab/bin/check 01 12`

<details><summary>Indice 1</summary>

Dans la liste du rebase interactif, les commits sont du **plus ancien au plus récent**. Commandes utiles : `pick`, `reword`, `squash`, `fixup`, `drop`, `exec`. Un commit dont le message commence par `fixup! <titre>` peut être placé automatiquement par une option de `git rebase` (ou par le réglage `rebase.autoSquash`).
</details>

<details><summary>Indice 2</summary>

Un commit qui retire exactement ce qu'un commit précédent avait ajouté : demande-toi ce qui reste si tu fusionnes les deux, et ce qui reste si tu ne gardes ni l'un ni l'autre. Option `--exec` de `git rebase` : elle insère une ligne `exec` après chaque commit de la liste.
</details>

<details><summary>Indice 3</summary>

Après un rebase, `ORIG_HEAD` et le *reflog* de la branche (`git reflog show <branche>`) gardent l'ancienne pointe. `git rebase --abort` ne sert que pendant un rebase en cours.
</details>

**Pour aller plus loin** (facultatif) : `git commit --fixup=amend:<commit>` et `--fixup=reword:<commit>` ; `git rebase --update-refs` pour une pile de branches dépendantes ; l'outil tiers `git absorb`. Documentation : <https://git-scm.com/docs/git-rebase#_interactive_mode>.

---

### M01-E13 — Résoudre des conflits de fusion et de rebase (`rerere`, outils)  `LAB` `★★`

> **Ticket PLAT-223** — *De : Karim Benali*
> Pendant que tu travaillais sur `e13/inventaire-runner01`, j'ai complété l'inventaire de l'atelier et renommé une variable du script de sauvegarde. Ta branche ne passe plus. Mets-la à jour **par rebase**, sans perdre ni mon travail ni le tien, et vérifie que le script fonctionne encore : un conflit résolu n'est pas un conflit compris.

**Objectifs pédagogiques**
- Lire un conflit à trois versions (`zdiff3`) : savoir qui a changé quoi par rapport à l'ancêtre commun.
- Résoudre des conflits pendant une fusion et pendant un rebase, et savoir ce que désignent « ours » et « theirs » dans chaque cas.
- Détecter un **conflit sémantique** (aucun marqueur, mais un code cassé).
- Faire rejouer une résolution par `rerere`.

**Prérequis** : M01-E12.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Préparation : [`ressources/M01-E13/fabriquer-depot.sh`](../ressources/M01-E13/fabriquer-depot.sh). Dans `formation/git-labo` (dossier `conflits/`) : ta branche `e13/inventaire-runner01` (3 commits à ton nom) et deux commits de Karim sur `main`. `--reinitialiser` remet ta branche dans son état de départ.
- Attendu : l'inventaire garde **toutes** les modifications des deux côtés ; le script `conflits/sauvegarde.sh` fonctionne avec le renommage de Karim ; la branche est rebasée sur `main` (aucun commit de fusion) ; chaque commit corrige ce qu'il doit corriger.
- Test du script sans rien sauvegarder : `SIMULATION=1 conflits/sauvegarde.sh 2011` (il affiche les commandes au lieu de les lancer).
- Réglages Git à mettre au niveau global : `rerere.enabled` et `merge.conflictStyle` (`zdiff3`, disponible depuis Git 2.35). Outil de fusion facultatif : `vimdiff` si `vim` est installé.

**Travail demandé**
1. Règle `rerere` et le style de conflit, et justifie chacun en une ligne dans ton journal.
2. Lance le script et récupère les branches. Observe la divergence (`git log --oneline --graph --left-right origin/main...origin/e13/inventaire-runner01`). **Avant toute fusion**, prédis les conflits avec `git merge-tree --write-tree` : quels fichiers ? Note ta prédiction.
3. Essai par fusion, sur une branche jetable `essai/e13-fusion` créée depuis ta branche : `git merge origin/main`. Lis les marqueurs : quelles lignes viennent de l'ancêtre, de toi, de Karim ? Essaie `git log --merge` et `git diff`. Puis abandonne la fusion et supprime la branche d'essai.
4. Rebase ta branche sur `origin/main` et résous chaque arrêt. À chaque arrêt, note ce que contient `HEAD` et ce que désigne `--theirs`. Ne te contente pas de faire disparaître les marqueurs : relis le tableau complet.
5. Une fois le rebase terminé, teste le script en simulation. S'il échoue, trouve pourquoi alors qu'aucun conflit n'a été signalé sur ce fichier.
6. La correction doit aller **dans le commit qui a introduit le problème**, pas dans un commit « fix » de plus. Repars de l'état d'origine de ta branche (`origin/e13/inventaire-runner01`) et refais le rebase en mode interactif pour pouvoir t'arrêter sur ce commit. Observe ce que fait `rerere` aux arrêts que tu as déjà résolus.
7. Vérifie (simulation, `bash -n`, relecture de l'inventaire), publie avec `--force-with-lease`, ouvre une MR vers `main`.

**Critères de réussite**
- [ ] `rerere` est actif et a enregistré au moins une résolution ; le style de conflit est `zdiff3` (ou `diff3`).
- [ ] La branche est rebasée sur le dernier `main`, sans commit de fusion.
- [ ] L'inventaire contient les lignes `git01` (Karim) et `runner01` (toi), et la ligne `dns01` combine les deux modifications.
- [ ] `conflits/sauvegarde.sh` ne référence plus l'ancienne variable, garde ta vérification du stockage et fonctionne en simulation.
- [ ] Aucun marqueur de conflit ne subsiste ; une MR est ouverte.

**Vérification** : `lab/bin/check 01 13`

<details><summary>Indice 1</summary>

Avec `zdiff3`, le bloc entre `|||||||` et `=======` est l'**ancêtre commun**. Compare chaque côté à l'ancêtre : ce qui diffère est ce que ce côté a changé. La bonne résolution contient en général les deux changements.
</details>

<details><summary>Indice 2</summary>

Pendant un rebase, Git rejoue **tes** commits sur la branche cible : `HEAD` est la branche en cours de construction (le côté de `main`), et tes commits arrivent comme « theirs ». C'est l'inverse d'une fusion.
</details>

<details><summary>Indice 3</summary>

`rerere` enregistre une résolution dans `.git/rr-cache` au moment du `git add` / de la poursuite. Au conflit suivant identique, il réapplique la résolution mais laisse le fichier « non fusionné » pour que tu la relises (sauf réglage `rerere.autoUpdate`). `git rerere diff` montre ce qu'il a fait ; `git rerere forget <fichier>` efface une résolution enregistrée par erreur.
</details>

**Pour aller plus loin** (facultatif) : `git checkout --conflict=zdiff3 <fichier>` pour recréer les marqueurs d'un fichier mal résolu ; `git mergetool` et le réglage `mergetool.keepBackup` ; les stratégies et options de fusion (`-X ours`, `-X theirs`, `-X ignore-space-change`) et pourquoi elles sont dangereuses ici. Documentation : <https://git-scm.com/docs/git-rerere>, <https://git-scm.com/docs/git-merge#_how_conflicts_are_presented>.

---
