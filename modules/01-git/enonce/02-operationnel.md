# Module 01 — Palier 2 : Opérationnel

La forge tourne, le dépôt du socle y est migré, et tu sais lire et défaire un historique. Il faut maintenant que l'équipe **travaille** avec : chaque changement passe par une merge request relue, `main` ne se touche plus à la main, les messages de commit deviennent une donnée exploitable, et les secrets sont arrêtés avant de quitter un poste. Les tickets de ce palier sont ceux des premières semaines d'une forge en production : Karim relit tes MR et t'en fait relire, Sophie surveille tout ce qui ressemble à un jeton, Nadia a besoin d'un correctif pour cette nuit, Julien d'un rétroportage pour son équipe. Tu termines en écrivant les règles du jeu pour ceux qui arrivent.

> **Où travailler ?** Toujours depuis `adm01`. Les projets de la plateforme (`plateforme/medisphere`, clone `~/medisphere`) ne reçoivent que des changements **réels** et propres. Les manipulations d'historique se font dans le bac à sable `formation/git-labo` (clone `~/src/git-labo`, branches `eXX/…`) ou dans les projets d'exercice créés par les scripts de `ressources/`.
>
> **Scripts de ressources.** Ils se lancent depuis le dépôt du workbook (`~/DevOpsPrivateCloud`), lisent `lab/lab.env` et, quand ils agissent sur GitLab, ton **jeton d'administration** (`~/.config/workbook/gitlab-admin.token`, E05 ; avec la portée `admin_mode` en plus si tu as déjà activé l'*Admin Mode*, M01-E31). Ils ne signent pas les commits qu'ils fabriquent et n'exécutent pas tes hooks locaux. Quand un personnage commente ou ouvre une MR, le script crée un **jeton d'emprunt d'identité** valable un jour et le révoque en sortant. Lis chaque script avant de le lancer.

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
> Validé en réunion d'équipe (suite à ta note de l'E09) : plus aucun push direct sur `main` dans le groupe `plateforme`, fusion uniquement par MR relue, discussions closes avant fusion, et un historique lisible : **commit de fusion avec historique semi-linéaire**, une bulle par MR sur une ligne principale droite. Sophie voulait aussi des approbations obligatoires et des responsables de code par dossier : vérifie ce que notre édition permet, et propose des compensations pour le reste. Les prochains projets (`plateforme/outils` dès le module 02) doivent naître avec ces règles, sans que personne ait à y penser.

**Objectifs pédagogiques**
- Configurer une branche protégée : qui pousse, qui fusionne, push forcé.
- Comparer les méthodes de fusion de GitLab (commit de fusion, commit de fusion semi-linéaire, fast-forward), argumenter celle retenue par l'équipe et régler les MR en conséquence.
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
| Méthode de fusion | commit de fusion avec historique semi-linéaire (*Merge commit with semi-linear history*) : décision de l'équipe, reprise par tous les projets `plateforme/*` et par tout le workbook |
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
2. Dans ton journal, dessine le graphe obtenu sur `main` après la fusion de deux MR avec chacune des trois méthodes de fusion. Pour chacune : lisibilité de `git log --first-parent`, utilisabilité de `git bisect`, contrainte imposée aux auteurs (rebase avant fusion), conservation des commits relus, conséquences pour semantic-release (E25) qui lit les messages de commit. Écris en cinq lignes la justification de la méthode retenue par l'équipe, et ce qui te ferait proposer d'en changer.
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
- [ ] Un fil ouvert empêche la fusion ; la méthode de fusion est le commit de fusion avec historique semi-linéaire, et sa justification est dans ton journal.
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

### M01-E14 — Conventional Commits et commitlint en local  `LAB` `★★`

> **Ticket PLAT-224** — *De : Karim Benali*
> En E25, les numéros de version seront calculés à partir des messages de commit. Un message, ce n'est donc plus de la prose : c'est une donnée. Installe commitlint sur ton poste, mets sa configuration dans `plateforme/medisphere`, et fais-moi un tableau des messages qu'on voit passer : lesquels passent, lesquels non, et quel numéro de version ils produiraient.

**Objectifs pédagogiques**
- Connaître la spécification Conventional Commits 1.0.0 et son lien avec la gestion sémantique de version (SemVer).
- Installer Node.js 24 LTS depuis un dépôt tiers proprement (deb822, épinglage) et des outils npm sans droits root.
- Configurer commitlint, comprendre comment il trouve sa configuration et les règles qu'il hérite.
- Mesurer les limites d'un hook Git local.

**Prérequis** : M01-E11.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Node.js : branche 24 LTS du dépôt NodeSource, déclarée au format deb822 dans `/etc/apt/sources.list.d/nodesource.sources`, clé dans `/usr/share/keyrings/nodesource.gpg` (clé publiée sur `https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key`), dépôt `https://deb.nodesource.com/node_24.x`, suite `nodistro`, composant `main`. Le paquet `nodejs` de Debian 13 (20.x) est trop ancien : commitlint 21 exige Node.js 22.12 ou plus.
- Outils npm de l'utilisateur : préfixe npm `~/.local` (binaires dans `~/.local/bin`, déjà dans ton `PATH` à la connexion sous Debian). Pas de `sudo npm`.
- Versions figées pour tout le module : `@commitlint/cli` et `@commitlint/config-conventional` **21.2.3**.
- Configuration : `commitlint.config.mjs` à la racine de `plateforme/medisphere`, qui étend `@commitlint/config-conventional`, types standard. Ce fichier deviendra la référence de tous les projets `plateforme/*`.
- Point de départ des versions pour le tableau : `1.4.2`.

**Travail demandé**
1. Lis la spécification (<https://www.conventionalcommits.org/fr/v1.0.0/>). Pour chaque message ci-dessous, indique dans ton journal : conforme ou non (et pourquoi), et la version produite à partir de `1.4.2` si ce commit était le seul depuis la dernière version.

   | # | Message (première ligne, sauf mention) |
   |---|---|
   | 1 | `docs(socle): ajouter git01 à l'inventaire` |
   | 2 | `feat: sauvegarde automatique de GitLab vers PBS` |
   | 3 | `Fix: seuil d'alerte PBS` |
   | 4 | `fix(pbs)!: le seuil se donne désormais en heures` |
   | 5 | `chore: mise à jour.` |
   | 6 | `update inventaire` |
   | 7 | `feat(ci): pipeline de qualité obligatoire`, avec dans le pied `BREAKING CHANGE: une MR sans pipeline réussi ne peut plus être fusionnée` |
   | 8 | `refactor: Renommer DEST en STOCKAGE` |
   | 9 | `perf(dns): cache négatif de 60 s` |
   | 10 | `Merge branch 'docs/fiche-forge' into 'main'` |
   | 11 | `fixup! feat: sauvegarde automatique de GitLab vers PBS` |
   | 12 | `ci: ajouter le job gitleaks` |
   | 13 | `feat(sauvegarde): planifier la sauvegarde de git01 chaque nuit à 1 h 30 sur pbs01 avec rétention de 14 jours et vérification` |

2. Installe Node.js 24 sur `adm01` depuis NodeSource. Avant d'importer la clé, affiche son empreinte et note-la. Fais en sorte qu'APT préfère durablement le paquet de NodeSource à celui de Debian, et vérifie-le (`apt policy nodejs`).
3. Règle le préfixe npm, installe commitlint et sa configuration partagée aux versions figées, vérifie `commitlint --version`.
4. Sur une branche de `~/medisphere`, écris `commitlint.config.mjs`. Teste ton tableau de l'étape 1 en passant chaque message à `commitlint` sur l'entrée standard. Affiche la configuration effective (`commitlint --print-config`) : retrouve la règle qui refuse le message 8.
5. Installe un hook `commit-msg` « à la main » dans `~/medisphere/.git/hooks/`, qui appelle commitlint. Vérifie qu'un mauvais message est refusé. Dans ton journal : pourquoi ce hook ne protège-t-il que toi ? Comment le contourner en une option ?
6. Contrôle l'historique existant de `main` avec commitlint (plage de commits). Décide ce que tu fais des anciens messages non conformes, sachant que `main` est protégée et que l'étiquette `socle-v0` pointe dans cet historique. Note ta décision.
7. MR, revue par toi-même avec le modèle de E10, fusion. Après fusion et `git fetch`, tous les commits de `main` arrivés depuis la configuration doivent passer commitlint.

**Critères de réussite**
- [ ] `node --version` affiche une 24.x ; `apt policy nodejs` montre NodeSource prioritaire.
- [ ] `commitlint --version` affiche la 21.x, installée sans `sudo`.
- [ ] `commitlint.config.mjs` est sur `main` de `plateforme/medisphere` et étend la configuration conventionnelle.
- [ ] Dans `~/medisphere`, un message conforme passe, un message sans type ou à type inconnu est refusé.
- [ ] Les commits de `main` depuis l'arrivée de la configuration passent commitlint.
- [ ] Le tableau des 13 messages est rempli et argumenté.

**Vérification** : `lab/bin/check 01 14`

<details><summary>Indice 1</summary>

Pour épingler un paquet sur une origine : `man apt_preferences` (`Package:`, `Pin: origin …`, `Pin-Priority:`). Une priorité supérieure à 500 suffit à préférer un dépôt à un autre de même version ou plus récent ; réfléchis à ce qui se passe si Debian publie une version plus haute.
</details>

<details><summary>Indice 2</summary>

« Cannot find module "@commitlint/config-conventional" » : commitlint cherche les configurations partagées depuis le dossier courant (le dépôt, qui n'a pas de `node_modules`), puis dans le dossier des paquets npm **globaux**, qu'il déduit du préfixe npm. Où as-tu installé le paquet, et commitlint peut-il le savoir ?
</details>

<details><summary>Indice 3</summary>

Plage de commits : `commitlint --from <commit exclu> --to <commit inclus>`. Les messages de fusion de GitLab, les `Revert …` et les `fixup!` sont ignorés par défaut : cherche `defaultIgnores` dans la documentation.
</details>

**Pour aller plus loin** (facultatif) : ajoute une règle `scope-enum` qui limite les portées à une liste (socle, forge, pbs, dns…) et mesure le coût pour l'équipe. Lis le préréglage `conventionalcommits` de semantic-release pour voir quels types déclenchent une version. Documentation : <https://commitlint.js.org/>.

---

### M01-E15 — pre-commit : des contrôles versionnés avec le dépôt  `LAB` `★★`

> **Ticket PLAT-225** — *De : Karim Benali*
> Ton hook commitlint n'existe que dans ton clone. Je veux des contrôles **versionnés avec le dépôt**, identiques pour tous et rejouables en CI : espaces et fins de fichiers, YAML valide, pas de gros fichiers, pas de marqueurs de conflit, pas de clé privée, pas de secret (gitleaks), et les messages de commit. Ce fichier servira de référence à tous nos projets : fais-le propre.

**Objectifs pédagogiques**
- Comprendre le modèle de pre-commit : dépôts de hooks, révisions figées, environnements isolés, étapes (*stages*).
- Écrire un hook local qui embarque ses dépendances (commitlint).
- Appliquer les correctifs automatiques à un dépôt existant sans brouiller l'historique.
- Savoir ce qu'un hook local ne garantit pas.

**Prérequis** : M01-E14.
**Durée indicative** : 2 h.

**Contexte technique**
- `uv` 0.12.x pour ton utilisateur (installateur officiel versionné : `https://astral.sh/uv/<VERSION>/install.sh`, où `<VERSION>` est la dernière 0.12.x), puis pre-commit **4.6.x** par `uv tool install` (jamais `pip` global). Le paquet Debian (4.2) n'est pas utilisé.
- Hooks attendus :

| Dépôt | Révision | Hooks |
|---|---|---|
| `https://github.com/pre-commit/pre-commit-hooks` | v6.0.0 | `trailing-whitespace` (en gardant les sauts de ligne Markdown), `end-of-file-fixer`, `check-yaml`, `check-added-large-files`, `check-merge-conflict`, `detect-private-key` |
| `https://github.com/gitleaks/gitleaks` | v8.30.1 | `gitleaks` |
| local | — | `commitlint` à l'étape `commit-msg`, commitlint et sa configuration en 21.2.3 |

- Les révisions sont **figées sur une empreinte de commit**, la version lisible en commentaire. `default_install_hook_types` installe `pre-commit` **et** `commit-msg`.
- Le hook `gitleaks` est compilé depuis ses sources par pre-commit à la première utilisation (il télécharge une chaîne Go si besoin) : compte une à deux minutes la première fois.
- Le fichier `.pre-commit-config.yaml` de `plateforme/medisphere` deviendra la référence des projets `plateforme/*` (M02 et suivants), et la CI le rejouera (E24).

**Travail demandé**
1. Installe `uv` (télécharge l'installateur, lis-le, puis exécute-le), puis pre-commit. Vérifie les versions.
2. Retire le hook artisanal de E14. Pourquoi ne doit-il pas cohabiter avec pre-commit ?
3. Sur une branche de `~/medisphere`, écris `.pre-commit-config.yaml`. Obtiens les empreintes des révisions sans les recopier d'Internet à la main. Valide le fichier, installe les hooks, regarde ce que pre-commit a écrit dans `.git/hooks/`.
4. Lance tous les hooks sur tous les fichiers. Mets les correctifs automatiques dans un commit **séparé**, de type `style`. Dans ton journal : pourquoi séparé ? Que fait `git blame` de ce commit, et comment l'écarter (`blame.ignoreRevsFile`) ?
5. Teste chaque contrôle avec un cas volontairement fautif, et note le hook qui l'arrête : espace en fin de ligne, fichier sans saut de ligne final, YAML invalide, fichier de 600 Ko, marqueur de conflit, clé privée, faux jeton GitLab, message de commit invalide.
   > ⚠️ **Attention** : pour la clé privée, génère une clé **jetable** pour l'occasion (`ssh-keygen -f /tmp/cle-test -N ''`), jamais une vraie clé ; pour le faux jeton, fabrique une chaîne au format `glpat-` suivie de 20 caractères aléatoires. Annule ces tests (`git restore --staged`, suppression des fichiers) : rien de tout cela ne doit être commité.
6. Contourne un hook avec `--no-verify`, puis avec la variable `SKIP`. Conclusion pour la CI ?
7. Rejoue le hook commitlint sur un message enregistré dans un fichier, sans faire de commit : c'est le geste de diagnostic quand un message est refusé. (En CI, l'E24 appellera commitlint directement sur la plage de commits de la MR, avec la même configuration.)
8. MR, fusion. Vérifie que `main` ne contient plus d'espaces en fin de ligne ni de fichier de plus de 500 Ko.

**Critères de réussite**
- [ ] `pre-commit --version` affiche une 4.x, installée par `uv tool`.
- [ ] `.pre-commit-config.yaml` est sur `main`, avec les huit hooks, des révisions figées et l'installation de `commit-msg` par défaut.
- [ ] Dans `~/medisphere`, `pre-commit validate-config` passe et les hooks `pre-commit` et `commit-msg` sont installés par pre-commit.
- [ ] `main` ne contient plus d'espaces en fin de ligne (hors Markdown) ni de fichier de plus de 500 Ko.
- [ ] Ton journal donne, pour chacun des huit cas fautifs, le hook qui l'a arrêté.

**Vérification** : `lab/bin/check 01 15`

<details><summary>Indice 1</summary>

`pre-commit autoupdate --freeze` remplace chaque `rev:` par l'empreinte du commit correspondant ; il met aussi à jour vers la dernière version. Pour figer **une version donnée**, l'empreinte d'une étiquette s'obtient avec `git ls-remote <dépôt> refs/tags/<étiquette>`.
</details>

<details><summary>Indice 2</summary>

Un hook « local » qui a besoin de paquets npm : `language: node` et `additional_dependencies`. Un hook de l'étape `commit-msg` reçoit le chemin du fichier du message en argument. Lis aussi `default_stages` dans la documentation : sans lui, que font les hooks qui ne déclarent pas d'étape quand Git appelle `commit-msg` ?
</details>

<details><summary>Indice 3</summary>

`check-added-large-files` ne regarde que les fichiers **ajoutés** dans le commit en cours. Pour rejouer commitlint hors commit : options `--hook-stage` et `--commit-msg-filename` de `pre-commit run`.
</details>

**Pour aller plus loin** (facultatif) : `pre-commit gc`, le cache `~/.cache/pre-commit` et ce qu'il faudra garder en CI ; le hook `no-commit-to-branch` ; `pre-commit try-repo`. Documentation : <https://pre-commit.com/>.

---

### M01-E16 — Gitleaks : arrêter un secret avant qu'il parte  `LAB` `★★`

> **Ticket SEC-226** — *De : Sophie Laurent*
> Le hook gitleaks, c'est bien, mais je veux savoir ce qu'il voit et surtout ce qu'il ne voit pas. Nos secrets à nous (secrets de jetons Proxmox, clés WireGuard) ne ressemblent à rien de connu. Je veux : un scan complet de l'historique de `plateforme/medisphere` avec rapport, des règles propres à notre socle, et une politique d'exceptions écrite.

**Objectifs pédagogiques**
- Scanner un historique, un dossier ou un flux avec Gitleaks 8.30, et lire un résultat (règle, empreinte, commit).
- Mesurer la couverture des règles par défaut sur les secrets propres au socle.
- Écrire des règles personnalisées et des exceptions justifiées dans `.gitleaks.toml`.
- Installer un binaire tiers en vérifiant son intégrité.

**Prérequis** : M01-E15.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Gitleaks **8.30.1**, binaire officiel de la release GitHub (`gitleaks_8.30.1_linux_x64.tar.gz` et le fichier `gitleaks_8.30.1_checksums.txt`), installé dans `/usr/local/bin`. Le paquet Debian (8.16) est trop ancien : sous-commandes `git`, `dir`, `stdin` absentes.
- Formats à couvrir : en-tête `Authorization: PVEAPIToken=<UTILISATEUR>@<DOMAINE>!<ID>=<UUID>` et variable `PVE_TOKEN_SECRET=<UUID>` (M00-E17) ; clé privée WireGuard (`PrivateKey = ` suivi de 44 caractères base64, M00-E16).
- Configuration : `.gitleaks.toml` à la racine de `plateforme/medisphere`, qui **étend** les règles par défaut. Gitleaks la lit automatiquement quand il analyse ce dossier (et donc dans le hook pre-commit).
- Faux secrets de test : génère-les (`cat /proc/sys/kernel/random/uuid`, `head -c 32 /dev/urandom | base64`). Ne teste jamais avec un vrai secret.

> ⚠️ **Attention** : lance toujours Gitleaks avec `--redact` et écris les rapports hors des dépôts (`/tmp`). Sans `--redact`, un vrai secret trouvé s'affiche en clair dans ton terminal, ton historique de session et le rapport.

**Travail demandé**
1. Installe le binaire en vérifiant sa somme SHA-256 avant de l'installer. Fais-en un petit script réutilisable dans `~/lab-scripts/`.
2. Scanne **tout** l'historique de `~/medisphere` (toutes les branches), avec un rapport JSON dans `/tmp`. Lis une entrée : `RuleID`, `Fingerprint`, `Commit`, `File`. Si un vrai secret apparaît : arrête-toi, et applique d'abord M01-E17.
3. Scanne en mode dossier `~/lab-scripts` et `~/.config/workbook`. Qu'est-ce qui est détecté dans ce dernier, et qu'est-ce qui ne l'est pas ?
4. Mesure la couverture des règles par défaut : passe sur l'entrée standard de Gitleaks un faux secret Proxmox dans chacun des deux formats, une fausse clé WireGuard, un faux jeton GitLab. Tableau dans ton journal : détecté ou non, par quelle règle.
5. Écris `.gitleaks.toml` : règles par défaut + une règle par format non couvert. Rejoue le test de l'étape 4 avec ta configuration.
6. Exceptions : la documentation du socle contient des exemples. Écris ta politique (quand une exception est acceptable, laquelle des trois formes utiliser : liste d'autorisation dans la configuration, commentaire `gitleaks:allow`, fichier `.gitleaksignore`, et qui valide). Si tu en ajoutes une, elle est ciblée et commentée.
7. Vérifie que le hook pre-commit de E15 applique bien **ta** configuration : un faux en-tête `PVEAPIToken` indexé doit être refusé.
8. MR, fusion.

**Critères de réussite**
- [ ] `gitleaks version` affiche 8.30.x, binaire dans `/usr/local/bin`, somme vérifiée.
- [ ] `.gitleaks.toml` est sur `main`, étend les règles par défaut et détecte les deux formats de secret Proxmox (et la clé WireGuard).
- [ ] L'historique de `main` ne contient aucun secret détecté par ta configuration.
- [ ] Ton journal contient le tableau de couverture et la politique d'exceptions.

**Vérification** : `lab/bin/check 01 16`

<details><summary>Indice 1</summary>

Une règle Gitleaks : `id`, `description`, `regex` (moteur RE2 de Go : pas d'assertion avant/arrière), `secretGroup` (le groupe de capture qui contient le secret), `keywords` (pré-filtre en minuscules, accélère beaucoup). Exemple complet dans le README du projet, section « Configuration ».
</details>

<details><summary>Indice 2</summary>

Depuis la 8.25, les listes d'autorisation globales s'écrivent `[[allowlists]]` et peuvent viser certaines règles seulement (`targetRules`). Une liste d'autorisation sur un **chemin** entier est rarement une bonne idée : pourquoi ?
</details>

<details><summary>Indice 3</summary>

`gitleaks git` analyse par défaut toutes les références (`git log --all`) ; `--log-opts` restreint la plage (par exemple `origin/main` seulement, ou une plage de commits de MR). Code de sortie : 1 si des fuites sont trouvées (modifiable par `--exit-code`).
</details>

**Pour aller plus loin** (facultatif) : les règles composites (`[[rules.required]]`, 8.28+) ; l'option `--baseline-path` pour n'alerter que sur les nouvelles fuites d'un vieux dépôt ; le successeur annoncé par l'auteur de Gitleaks (Betterleaks). Documentation : <https://github.com/gitleaks/gitleaks>.

---

### M01-E17 — Un secret a été poussé : purge, rotation, communication  `LAB` `★★★`

> **Ticket SEC-227** — *De : Sophie Laurent* — *Cc : Claire Morel*
> Julien a poussé un fichier de configuration contenant un **vrai** jeton GitLab dans `formation/labo-fuite`, puis l'a « retiré » dans un commit suivant. Je veux, dans cet ordre : le secret neutralisé, l'exposition évaluée, l'historique purgé partout (branches, étiquettes, merge requests), la preuve que plus rien ne traîne, et un compte rendu que je verserai au registre des incidents de sécurité.

**Objectifs pédagogiques**
- Appliquer l'ordre de traitement d'une fuite : contenir, évaluer, purger, vérifier, prévenir, communiquer.
- Réécrire un historique avec `git filter-repo` en mode suppression de données sensibles.
- Purger aussi ce que le serveur garde hors des branches (références de MR, objets inaccessibles) avec les outils de GitLab.
- Rédiger un compte rendu d'incident factuel.

**Prérequis** : M01-E16 ; M01-E05 (jeton d'administration, utilisé par le script de préparation). Les jetons de projet sont détaillés en M01-E20 : ici, il suffit de savoir en révoquer un.
**Durée indicative** : 3 h.

**Contexte technique**
- Préparation : [`ressources/M01-E17/fabriquer-depot.sh`](../ressources/M01-E17/fabriquer-depot.sh). Il crée le projet privé `formation/labo-fuite`, un **vrai** jeton d'accès de projet (« collecte-medisphere », rôle Reporter, `read_repository`, valable 7 jours, limité à ce projet), puis l'historique de Julien : le fichier `config/collecte.env` (jeton et mot de passe de base de test), l'étiquette `v0.1.0`, la branche `feat/export-csv` et une MR ouverte par Julien. Il refuse de tourner si le projet existe déjà.
- Outils : `git-filter-repo` 2.47 (paquet Debian `git-filter-repo`), option `--sensitive-data-removal` ; Gitleaks (E16).
- GitLab 19, rôle Owner du projet : *Settings > Repository > Repository maintenance* (*Remove blobs*, *Redact text*), puis *Settings > General > Advanced* (*Run housekeeping*, *Prune unreachable objects*). Ces opérations sont **irréversibles**.
- Journaux de `git01` utiles : `/var/log/gitlab/gitlab-rails/production_json.log`, `/var/log/gitlab/gitlab-rails/api_json.log`, `/var/log/gitlab/gitlab-shell/gitlab-shell.log`, `/var/log/gitlab/nginx/gitlab_access.log`.
- Attendu : jeton révoqué ; plus aucune révision accessible du dépôt (branches, étiquettes, références de MR) ne contient le jeton ni le mot de passe ; l'étiquette `v0.1.0` existe toujours ; `main` de nouveau protégée sans push forcé ; le fichier ne peut plus être recommité par erreur.

> ⚠️ **Attention** : la purge réécrit l'historique et invalide tous les clones. Fais d'abord une copie de sauvegarde du dépôt (`git clone --mirror`) **dans un dossier 700**, sache qu'elle contient le secret, et détruis-la à la fin. Le push forcé exige de lever temporairement l'interdiction sur `main` : remets-la immédiatement après.

**Travail demandé**
1. **Contenir.** Note l'heure. Repère les secrets (Gitleaks sur un clone neuf). Révoque le jeton. Vérifie qu'il est refusé. Dans ton journal : pourquoi révoquer **avant** de purger, même si la purge est rapide ?
2. **Évaluer.** Sur un clone miroir : quels commits, quelles références contiennent le secret (y compris `refs/merge-requests/*`) ? Depuis quand ? Qui avait accès au projet ? Le jeton a-t-il servi (date de dernière utilisation du jeton, journaux de `git01`) ? Qui a pu cloner ?
3. **Préparer la purge.** Sauvegarde miroir. Relève les identifiants des blobs qui contiennent le secret, **avant** toute réécriture. Décide : supprimer le fichier de tout l'historique, ou remplacer seulement les valeurs ? Justifie.
4. **Purger côté Git.** Avec `git filter-repo --sensitive-data-removal` sur un clone miroir, réécris l'historique ; lis les instructions qu'il affiche. Vérifie localement avec Gitleaks. Pousse la réécriture (branches et étiquettes), en levant puis rétablissant l'interdiction de push forcé. Note les références que GitLab refuse de mettre à jour, et pourquoi.
5. **Purger côté GitLab.** Fais disparaître ce qui reste accessible sur le serveur (références de MR, objets devenus inaccessibles) avec les outils de *Repository maintenance*, puis le ménage et l'élagage. Décide du sort de la MR de Julien (ses versions de diff sont conservées en base) et justifie.
6. **Vérifier.** Nouveau clone miroir : Gitleaks et une recherche du mot de passe sur **toutes** les révisions. Détruis ta sauvegarde miroir.
7. **Prévenir.** Le fichier réel ne doit plus pouvoir être commité ; un fichier d'exemple sans valeur le remplace. Julien et toi refaites vos clones.
8. **Communiquer.** Rédige le compte rendu pour Sophie : résumé en trois lignes, chronologie horodatée, exposition (portée du jeton, qui pouvait le lire, usage constaté), actions, cause et prévention, risques résiduels (sauvegardes, clones).

**Critères de réussite**
- [ ] Le jeton « collecte-medisphere » est révoqué.
- [ ] Aucune révision accessible de `formation/labo-fuite` ne contient le jeton ni le mot de passe.
- [ ] L'étiquette `v0.1.0` existe toujours ; `main` contient le script de collecte ; `main` est protégée sans push forcé.
- [ ] `.gitignore` empêche de recommiter le fichier de configuration.
- [ ] Le compte rendu est rédigé, horodaté, et distingue ce qui est prouvé de ce qui est supposé.

**Vérification** : `lab/bin/check 01 17`

<details><summary>Indice 1</summary>

Supprimer le fichier dans un nouveau commit ne retire rien : chaque ancien commit pointe toujours vers le blob. Pour voir où vit un blob : `git log --all --raw -- <chemin>` ou `git rev-list --objects --all | grep <chemin>`, puis `git for-each-ref --contains <commit>`. Un clone `--mirror` récupère aussi les références de MR que GitLab publie.
</details>

<details><summary>Indice 2</summary>

`--sensitive-data-removal` récupère d'abord **toutes** les références du dépôt d'origine, puis affiche les étapes suivantes (push en miroir, « First Changed Commit(s) »). GitLab n'accepte pas qu'on réécrive par un push ses références internes (`refs/merge-requests/…`) : c'est le rôle des outils de *Repository maintenance*.
</details>

<details><summary>Indice 3</summary>

*Remove blobs* attend une liste d'identifiants de **blobs** (pas de commits), un par ligne. *Run housekeeping* puis *Prune unreachable objects* : sans ces deux étapes, les objets restent sur le disque de `git01`. La documentation GitLab « Reduce repository size » décrit l'ordre exact.
</details>

**Pour aller plus loin** (facultatif) : la détection de secrets au push (*secret push protection*) de GitLab est réservée à Ultimate : compare avec un hook côté serveur (E26). Certains outils (TruffleHog) testent la validité d'un secret trouvé : quels risques et quel intérêt ? Documentation : <https://docs.gitlab.com/user/project/repository/repository_size/>, <https://github.com/newren/git-filter-repo/blob/main/Documentation/git-filter-repo.txt>.

---

### M01-E18 — Worktrees : un correctif urgent sans abandonner son travail  `LAB` `★★`

> **Ticket PLAT-228** — *De : Nadia Roussel* — *Priorité : haute*
> Toutes les nuits vers 2 h 30, `verifier-sauvegardes.sh` réveille l'astreinte : il signale **toutes** les VMs en retard, alors que la tâche PBS de 1 h s'est bien passée. Il me faut un correctif aujourd'hui.
>
> *Karim, en commentaire* : tu es en plein milieu du rapport de capacité, avec des modifications non commitées. Pas de `stash`, pas de commit « wip » : prends un worktree.

**Objectifs pédagogiques**
- Travailler sur deux branches en même temps dans deux dossiers, avec un seul dépôt (`git worktree`).
- Savoir ce qui est partagé entre worktrees (objets, références, configuration) et ce qui ne l'est pas (`HEAD`, index, fichiers).
- Mesurer ce que `stash` aurait fait à un travail en cours partiellement indexé.
- Livrer un correctif urgent proprement (test, MR, fusion) et ranger derrière soi.

**Prérequis** : M01-E10, M01-E14.
**Durée indicative** : 1 h.

**Contexte technique**
- Préparation : [`ressources/M01-E18/fabriquer-depot.sh`](../ressources/M01-E18/fabriquer-depot.sh). Il ajoute `worktrees/verifier-sauvegardes.sh` sur `main` de `formation/git-labo`, puis crée un **nouveau clone** `~/src/labo-worktrees` sur la branche locale `e18/rapport-capacite` : deux commits non poussés, une modification indexée, une modification non indexée, un fichier non suivi. C'est ton travail en cours : il doit en sortir intact.
- Entrée du script : des lignes `VMID HORODATAGE_UNIX` (dernière sauvegarde de chaque VM). Jeu de test : une VM sauvegardée il y a 3 h ne doit pas alerter, une VM sauvegardée il y a 30 h doit alerter.
  ```
  admin@adm01:~$ printf '1001 %s\n2011 %s\n' "$(date -d '-3 hours' +%s)" "$(date -d '-30 hours' +%s)" | worktrees/verifier-sauvegardes.sh
  ```
- Worktree du correctif : `~/src/labo-worktrees-correctif`, branche `e18/correctif-seuil` partant de `origin/main`. Le correctif passe par une MR vers `main` de `formation/git-labo`.

**Travail demandé**
1. Observe ton état (`git status`, `git log --oneline -3`, `git diff --cached`, `git diff`). Dans ton journal : que deviendraient la partie indexée et la partie non indexée après `git stash` puis `git stash pop` sans option ? Et avec un commit « wip » ?
2. Crée le worktree du correctif. Liste les worktrees. Regarde ce qu'est `.git` dans le nouveau dossier, et ce que contient `~/src/labo-worktrees/.git/worktrees/`.
3. Dans le worktree du correctif : reproduis le défaut avec le jeu de test, trouve la cause, corrige, teste, committe (message conforme), pousse, ouvre la MR, fusionne.
4. Pendant ce temps, dans `~/src/labo-worktrees` : vérifie que ton travail en cours n'a pas bougé. Le commit du correctif est-il visible depuis ce dossier ? Pourquoi ?
5. Essaie d'extraire `e18/rapport-capacite` dans le worktree du correctif. Lis le refus et explique-le.
6. Range : supprime le worktree proprement, supprime la branche locale du correctif une fois fusionnée, récupère `main`. Que faire si quelqu'un a supprimé le dossier d'un worktree à la main (`rm -rf`) ?
7. Dans ton journal : trois situations où un worktree vaut mieux qu'un `stash` ou un second clone, et une limite.

**Critères de réussite**
- [ ] Le correctif est sur `main` de `formation/git-labo`, via une MR fusionnée, et le jeu de test donne le résultat attendu.
- [ ] `~/src/labo-worktrees` est toujours sur `e18/rapport-capacite`, avec ses deux commits, sa modification indexée, sa modification non indexée et son fichier non suivi.
- [ ] La copie de travail principale n'a jamais changé de branche pendant l'opération.
- [ ] Il ne reste aucun worktree supplémentaire ni entrée orpheline.

**Vérification** : `lab/bin/check 01 18`

<details><summary>Indice 1</summary>

`git worktree add [-b <nouvelle-branche>] <chemin> [<point-de-départ>]`. Une même branche ne peut être extraite que dans un seul worktree à la fois.
</details>

<details><summary>Indice 2</summary>

Le défaut est une question d'**unités**. `date +%s` compte en secondes ; regarde ce que le script divise, et par quoi.
</details>

<details><summary>Indice 3</summary>

`git worktree remove` refuse de supprimer un worktree qui contient des modifications (sauf `--force`). Après une suppression manuelle du dossier, `git worktree prune` nettoie les métadonnées (`--dry-run -v` pour voir avant).
</details>

**Pour aller plus loin** (facultatif) : `git worktree lock` pour un worktree sur un disque amovible ; un worktree « détaché » (`--detach`) pour relire l'état d'une étiquette ou d'une MR sans créer de branche. Documentation : <https://git-scm.com/docs/git-worktree>.

---

### M01-E19 — Cherry-pick et rétroportage vers une branche de maintenance  `LAB` `★★`

> **Ticket DEV-229** — *De : Julien Petit*
> L'équipe MédiAgenda reste sur la 1.x de `sauvegarde-vm.sh` jusqu'à la fin du trimestre (branche `e19/1.x` du bac à sable). Deux correctifs de `main` nous concernent : le contrôle des plages de VMID, et le message quand `vzdump` échoue. **Rien d'autre** : pas de `--pool`, pas de syslog, et ne touchez pas aux noms de fonctions, nos scripts les appellent.

**Objectifs pédagogiques**
- Rétroporter des commits précis avec `git cherry-pick -x` et garder la trace de leur origine.
- Résoudre un conflit de cherry-pick dû à un changement qu'on ne rétroporte pas.
- Vérifier ce qui a été rétroporté (`git cherry`, `git log --cherry-mark`).
- Choisir une politique de correctifs entre une branche principale et des branches de maintenance.

**Prérequis** : M01-E13.
**Durée indicative** : 1 h.

**Contexte technique**
- Préparation : [`ressources/M01-E19/fabriquer-depot.sh`](../ressources/M01-E19/fabriquer-depot.sh). Dans `formation/git-labo` (dossier `cherry/`) : la branche de maintenance `e19/1.x`, et `main` qui a reçu cinq commits depuis (fonctions, correctifs, refactorisation).
- Ta branche : `e19/retroportage-1.x`, créée depuis `origin/e19/1.x`, fusionnée par MR **vers `e19/1.x`** (attention à la branche cible proposée par défaut).
- Chaque commit rétroporté porte la mention `(cherry picked from commit …)`.
- Test sans rien sauvegarder : un VMID hors plage doit être refusé avant tout appel à `vzdump` (`bash cherry/sauvegarde-vm.sh 42`).

**Travail demandé**
1. Lance le script et récupère les branches. Liste les commits de `main` absents de `e19/1.x` qui touchent `cherry/`, et lis chacun. Dans ton journal : lesquels prendre, lesquels écarter, et pourquoi la refactorisation, bien qu'inoffensive, ne doit pas partir.
2. Crée ta branche et rétroporte les deux correctifs, du plus ancien au plus récent. L'un d'eux va s'arrêter sur un conflit : explique-le (qu'est-ce qui a changé autour des lignes modifiées ?), résous-le dans l'esprit de la 1.x, poursuis.
3. Teste : `bash -n`, `shellcheck`, et le cas du VMID hors plage.
4. Compare avec `git cherry -v origin/main HEAD`. Pourquoi un des deux correctifs apparaît-il comme « déjà présent » et l'autre non ?
5. Pousse, ouvre la MR vers `e19/1.x`, fusionne.
6. Dans ton journal : cherry-pick, fusion de `main` dans `1.x`, ou rebase de `1.x` : pourquoi le premier seulement ? Quelle règle d'équipe proposes-tu (où corriger d'abord, comment rétroporter, qui décide) ? Comment semantic-release (E25) traite-t-il une branche nommée `1.x` ?

**Critères de réussite**
- [ ] `e19/1.x` contient les deux correctifs, chacun avec la mention de son commit d'origine sur `main`.
- [ ] Les correctifs sont arrivés par une MR fusionnée vers `e19/1.x`.
- [ ] Sur `e19/1.x`, le script est valide, refuse un VMID hors plage, affiche le message d'échec de `vzdump`, garde `verifier_vmid` et ne contient ni `--pool` ni syslog.
- [ ] Ton journal explique le résultat de `git cherry`.

**Vérification** : `lab/bin/check 01 19`

<details><summary>Indice 1</summary>

`git log --oneline --cherry-pick --right-only origin/e19/1.x...origin/main -- cherry/` liste ce qui est sur `main` et pas (encore) sur `1.x`. `git show <commit>` pour lire un correctif seul.
</details>

<details><summary>Indice 2</summary>

Un cherry-pick applique la différence entre un commit et son parent. Si les lignes **voisines** ont changé entre-temps sur `main` (par un commit que tu ne prends pas), le contexte ne correspond plus. Pendant l'arrêt : `git cherry-pick --continue`, `--skip`, `--abort`.
</details>

<details><summary>Indice 3</summary>

`git cherry` compare des *patch-id* : l'empreinte du **contenu** d'un diff, pas du commit. Qu'est-ce qui change dans le diff d'un commit dont tu as résolu le conflit ?
</details>

**Pour aller plus loin** (facultatif) : `git cherry-pick -m 1` pour reprendre une fusion entière ; `git rebase --onto` pour transplanter une série ; les branches de maintenance (`N.x`, `N.N.x`) dans la configuration de semantic-release. Documentation : <https://git-scm.com/docs/git-cherry-pick>.

---

### M01-E20 — Jetons et clés : personnels, de projet, de déploiement  `LAB` `★★`

> **Ticket SEC-230** — *De : Sophie Laurent*
> Avant d'ouvrir la forge à d'autres équipes, je veux l'inventaire de tout ce qui donne accès à `git01` : quoi, à qui, pour faire quoi, jusqu'à quand, rangé où, et comment on le remplace. Et pour les machines, des accès **de machine**, pas le jeton personnel d'un humain qui part en vacances (ou quitte l'entreprise).

**Objectifs pédagogiques**
- Distinguer les identifiants de GitLab (jeton personnel, d'emprunt d'identité, de projet, de groupe, clé et jeton de déploiement, clé SSH, jeton de runner) et leurs usages.
- Appliquer le moindre privilège : portée, rôle, durée, périmètre.
- Faire tourner un jeton sans interruption ni fuite, et vérifier une révocation.
- Tenir un registre des accès sans jamais y écrire un secret.

**Prérequis** : M01-E05, M01-E11.
**Durée indicative** : 2 h.

**Contexte technique**
- Préfixes des jetons GitLab (documentation « GitLab token overview ») : `glpat-` (jetons d'accès personnels, d'emprunt d'identité, de projet et de groupe), `gldt-` (jeton de déploiement), `glrt-` (runner, E23)…
- Jetons existants (E05) : `workbook-checks` (`read_api`, 1 an au plus) et `workbook-admin` (`api`, 90 jours au plus), fichiers `~/.config/workbook/gitlab-checks.token` et `gitlab-admin.token` (600, dossier 700). Quand l'*Admin Mode* sera activé (M01-E31), ils seront recréés avec la portée `admin_mode` en plus : c'est la seule portée supplémentaire admise.
- Rotation par l'API : sans date explicite, GitLab donne au nouveau jeton une validité d'**une semaine**. Faire tourner un jeton déjà révoqué révoque toute sa « famille » (détection de réutilisation).
- Clé de déploiement : `~/.ssh/id_ed25519_deploy_gitlabo` (ed25519, usage machine), déclarée en **lecture seule** sur `formation/git-labo`, titre `labo-lecture`.
- Jeton de projet de test : `lecture-labo` sur `formation/git-labo`, rôle Reporter, portée `read_repository`, 7 jours.
- Registre : `docs/socle/registre-secrets.md` dans `plateforme/medisphere`, par MR.

**Travail demandé**
1. Dans ton journal, fais le tableau des types d'identifiants : propriétaire (humain, compte de service, projet), portées possibles, durée, préfixe, usage typique dans notre forge.
2. Audite tes jetons par l'API : liste, portées, dates d'expiration, dernière utilisation. Révoque ce qui ne sert plus (jetons de test de E05, par exemple).
3. Prouve que le jeton des checks ne peut **rien écrire** : une requête d'écriture inoffensive doit être refusée. Note le code HTTP.
4. Fais tourner le jeton d'administration par l'API, avec une expiration de 90 jours au plus, en remplaçant le fichier sans qu'il soit jamais vide ni lisible par d'autres (script dans `~/lab-scripts/`). Vérifie que l'ancien jeton est refusé et que les scripts de ressources fonctionnent avec le nouveau.
   > ⚠️ **Attention** : si la réponse de l'API se perd entre la rotation et l'écriture du fichier, l'ancien jeton est déjà révoqué et le nouveau inconnu : il faudra en recréer un dans l'interface. Ne relance jamais une rotation avec l'ancien jeton.
5. Ta clé SSH dans GitLab : donne-lui une date d'expiration (un an). Elle ne se modifie pas : il faut la retirer puis la redéclarer.
   > ⚠️ **Attention** : entre le retrait et la redéclaration, tes accès Git en SSH sont coupés. Fais-le d'une traite, et ne déclare pas de date déjà passée.
6. Clé de déploiement : génère-la, déclare-la en lecture seule sur `formation/git-labo`, clone avec **cette clé seulement**, puis tente un push et lis le refus.
7. Jeton de projet : crée `lecture-labo`, clone `formation/git-labo` en HTTPS avec lui **sans** que le jeton apparaisse dans l'historique du shell, dans `.git/config` ni dans l'URL du dépôt. Regarde le membre « bot » apparu dans le projet. Révoque le jeton et vérifie que le clone est refusé.
8. Rédige le registre (tous les identifiants de la forge, y compris ceux qui viendront : jeton de runner, jeton `bot-release`), avec pour chacun la procédure de rotation. MR, fusion.

**Critères de réussite**
- [ ] `~/.config/workbook` est en 700, les deux fichiers de jetons en 600.
- [ ] Jeton des checks : actif, `read_api` seule (plus `admin_mode` après M01-E31), expiration dans un an au plus. Jeton d'administration : actif, `api` seule (plus `admin_mode` après M01-E31), expiration dans 90 jours au plus.
- [ ] Tes clés SSH d'authentification déclarées dans GitLab ont une date d'expiration.
- [ ] `formation/git-labo` a une clé de déploiement en lecture seule, aucune en écriture, et un jeton de projet Reporter / `read_repository` testé puis révoqué.
- [ ] `docs/socle/registre-secrets.md` est sur `main`, couvre au moins les deux jetons, la clé de déploiement et la rotation, et ne contient aucune valeur.

**Vérification** : `lab/bin/check 01 20`

<details><summary>Indice 1</summary>

API : `GET /personal_access_tokens` (avec `user_id` pour un administrateur), `GET /personal_access_tokens/self`, `POST /personal_access_tokens/self/rotate` (paramètre `expires_at`). Pour écrire un fichier secret sans fenêtre d'exposition : `umask`, fichier temporaire dans le **même** dossier, `mv`.
</details>

<details><summary>Indice 2</summary>

Pour forcer une clé SSH précise : `GIT_SSH_COMMAND='ssh -i <clé> -o IdentitiesOnly=yes'`. Sans `IdentitiesOnly`, ton agent propose aussi ta clé personnelle, et le test ne prouve rien.
</details>

<details><summary>Indice 3</summary>

En HTTPS, GitLab accepte un jeton comme mot de passe, avec n'importe quel nom d'utilisateur non vide. Laisse Git te le **demander** (invite de saisie, ou un petit programme `GIT_ASKPASS` qui lit un fichier 600) plutôt que de l'écrire dans la commande.
</details>

**Pour aller plus loin** (facultatif) : jetons de groupe ; jetons de déploiement (`gldt-`) pour un registre de paquets ou de conteneurs (M13) ; politique d'expiration maximale de l'instance (*Admin > Settings > General > Account and limit*). Documentation : <https://docs.gitlab.com/security/tokens/>.

---

### M01-E21 — Revue de la merge request d'un stagiaire  `REV` `★★`

> **Ticket PLAT-231** — *De : Karim Benali*
> Lucas a ouvert sa première MR sur `plateforme/medisphere` : un script qui vérifie l'expiration des certificats du socle. Fais-en la revue complète dans GitLab, comme je l'ai fait pour toi en E10 : commentaires sur les lignes, gravité de chaque remarque, suggestions quand c'est possible, et une synthèse avec ta décision. Bienveillant mais sans complaisance : c'est un stagiaire, il doit apprendre, et ce qu'il a écrit touche à la sécurité.

**Objectifs pédagogiques**
- Relire une MR complète : description, commits (messages, auteurs), fichiers, contenu, métadonnées.
- Classer des remarques par gravité et les rédiger de façon utile (le problème, pourquoi, une proposition).
- Utiliser les outils locaux pour appuyer une revue (ShellCheck, pre-commit, Gitleaks).
- Repérer ce qui ne peut pas attendre la fin de la revue.

**Prérequis** : M01-E10, M01-E15, M01-E16.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Préparation : [`ressources/M01-E21/creer-mr-lucas.sh`](../ressources/M01-E21/creer-mr-lucas.sh). Il crée au nom de `lucas.martin` la branche `lucas/verif-certificats`, quatre commits et la MR, avec toi (`WB_MOI`) comme relecteur. Le « jeton » que Lucas a écrit dans son script est factice (il ne donne accès à rien) : traite-le comme un vrai.
- Gravités de l'équipe : **bloquant**, **à corriger**, **suggestion**, **question**, **détail**.
- Ne pousse rien sur la branche de Lucas et ne fusionne pas : c'est sa MR.

**Travail demandé**
1. Lance le script. Lis la MR comme un relecteur : titre et description, liste des commits, onglet *Changes* fichier par fichier.
2. Récupère la MR en local (référence `merge-requests/<IID>/head`) et fais travailler les outils : ShellCheck sur le script, les hooks pre-commit sur les fichiers modifiés, Gitleaks sur la plage de commits de la MR, auteurs des commits, tailles et types des fichiers.
3. Rédige ta revue dans l'interface, en mode revue groupée : un commentaire par problème, placé sur la ligne concernée, avec sa gravité, la raison et une proposition. Au moins une **suggestion** applicable par Lucas en un clic.
4. Termine par un commentaire général : ce qui est bien, les points bloquants, la décision (fusion possible après corrections, ou MR à reprendre), et la suite proposée à Lucas.
5. Dans ton journal : l'action qui ne peut pas attendre que Lucas corrige sa MR, qui la fait, et pourquoi. Puis : quels défauts les contrôles automatiques (E15, E16) auraient-ils arrêtés, et pourquoi sont-ils quand même arrivés sur le serveur ?
6. Compare ta revue à la grille du corrigé.

**Critères de réussite**
- [ ] La MR de Lucas n'est pas fusionnée.
- [ ] Ta revue compte au moins six commentaires, dont au moins quatre sur des lignes précises du diff.
- [ ] Le jeton en clair, la vérification TLS désactivée et les messages de commit sont traités.
- [ ] Un commentaire général donne la synthèse et la décision.
- [ ] Auto-évaluation : au moins 14 des 18 défauts de la grille du corrigé trouvés, dont tous les bloquants.

**Vérification** : `lab/bin/check 01 21` (forme de la revue ; le fond s'évalue avec la grille du corrigé)

<details><summary>Indice 1</summary>

Ne te limite pas au script : chaque fichier de l'onglet *Changes* compte, et aussi ce qui n'apparaît pas dans le diff (auteur et adresse des commits, mode des fichiers, fins de ligne, taille).
</details>

<details><summary>Indice 2</summary>

`pre-commit run --from-ref origin/main --to-ref <ref-de-la-MR>` applique les hooks aux seuls fichiers modifiés ; `gitleaks git --log-opts="origin/main..<ref-de-la-MR>"` analyse les seuls commits de la MR ; `file` révèle les fins de ligne CRLF ; `git ls-tree -l` donne les tailles.
</details>

<details><summary>Indice 3</summary>

Pour chaque ligne de script : que se passe-t-il quand l'hôte ne répond pas ? Quand le certificat n'est pas valide ? Quand la commande est lancée par la supervision, qui ne lit que le code de sortie ?
</details>

**Pour aller plus loin** (facultatif) : la méthode « Conventional Comments » (<https://conventionalcomments.org/>) pour normaliser les étiquettes de commentaire ; la fonction *Request changes* de la revue GitLab et ce qu'elle bloque (ou non) dans ton édition. Documentation : <https://docs.gitlab.com/user/project/merge_requests/reviews/>.

---

### M01-E22 — Rédiger le CONTRIBUTING et le modèle de MR de l'équipe  `RED` `★★`

> **Ticket PLAT-232** — *De : Claire Morel*
> L'équipe MédiAgenda et deux personnes d'InfoGér arrivent sur la forge le mois prochain. Il nous faut un `CONTRIBUTING.md` et un modèle de merge request : tout ce qu'on a décidé depuis le début du module doit y être, de façon qu'un nouveau venu s'en serve **sans te demander**. Ces deux fichiers seront copiés dans chaque projet `plateforme/*`.

**Objectifs pédagogiques**
- Transformer des décisions éparses (E09 à E21) en règles écrites, courtes et justifiées.
- Écrire pour un lecteur qui ne connaît ni l'équipe ni l'historique des décisions.
- Faire d'un modèle de MR un outil de revue, pas un formulaire.

**Prérequis** : M01-E09, M01-E11 à M01-E21.
**Durée indicative** : 2 h.

**Contexte technique**
- Fichiers : `CONTRIBUTING.md` à la racine de `plateforme/medisphere` ; `.gitlab/merge_request_templates/Default.md`. Dans CE, un modèle nommé `Default.md` préremplit **toute nouvelle MR** du projet (le modèle par défaut défini dans les réglages du projet est une fonction Premium).
- Le `CONTRIBUTING.md` doit couvrir : préparation du poste, branches et nommage, messages de commit (avec l'effet de chaque type sur la version), merge requests (taille, brouillon, description, mise à jour de la branche), revue (qui, délais, gravités, résolution des fils), fusion (méthode, conditions, qui), secrets et conduite à tenir en cas de fuite, branches de maintenance, ce qui est interdit, contacts.
- Le modèle de MR doit faire apparaître : contexte et ticket, changements, **comment c'est vérifié**, impacts (sécurité, flux réseau → `docs/socle/matrice-flux.md`, inventaire → `docs/socle/inventaire.md`, sauvegarde, rupture), retour arrière, liste de contrôle avant revue.
- Contrainte de longueur : `CONTRIBUTING.md` lisible en dix minutes (moins de 200 lignes). Chaque règle a sa raison, en une phrase.

**Travail demandé**
1. Rassemble tes décisions (journal, tickets E09 à E21) et classe-les : règle, recommandation, ou détail à laisser dans la documentation.
2. Rédige les deux fichiers sur une branche. Signale explicitement ce que GitLab CE ne fait pas respecter (approbation obligatoire) et comment l'équipe le compense.
3. Ouvre la MR : la description doit déjà utiliser **ton** modèle (copie-le à la main pour cette première MR). Fusionne.
4. Vérifie l'effet du modèle : ouvre une MR de test (brouillon) depuis une branche vide, constate le préremplissage, ferme-la et supprime la branche.
5. Fais relire ton `CONTRIBUTING.md` par « quelqu'un qui ne sait rien » : relis-le en te demandant, à chaque paragraphe, « que dois-je faire concrètement ? ». Supprime ce qui ne répond pas à cette question.

**Critères de réussite**
- [ ] `CONTRIBUTING.md` et `.gitlab/merge_request_templates/Default.md` sont sur `main` de `plateforme/medisphere`.
- [ ] Tous les thèmes de la liste sont couverts, chaque règle avec sa raison, en moins de 200 lignes.
- [ ] Le modèle préremplit une nouvelle MR et contient la section « comment c'est vérifié ».
- [ ] La conduite à tenir en cas de fuite de secret est écrite et cohérente avec E17.
- [ ] Auto-évaluation avec la grille du corrigé : 12 points sur 15 au moins.

<details><summary>Indice 1</summary>

Commence par la question « que doit faire quelqu'un le premier jour ? » : le reste suit l'ordre d'un changement (branche, commits, MR, revue, fusion, version).
</details>

<details><summary>Indice 2</summary>

Une règle sans raison sera contournée ; une raison sans règle ne sera pas appliquée. Un tableau « type de commit → effet sur la version » remplace un long paragraphe.
</details>

**Pour aller plus loin** (facultatif) : ajoute un modèle de ticket (`.gitlab/issue_templates/Incident.md`) aligné sur le modèle de post-mortem de M00 ; regarde les fichiers `CONTRIBUTING.md` de projets connus (GitLab, Kubernetes) pour ce qu'ils disent et ce qu'ils ne disent pas. Documentation : <https://docs.gitlab.com/user/project/description_templates/>.
