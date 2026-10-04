# Module 01 — Palier 2 : Opérationnel — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les fichiers complets cités ici sont dans [`fichiers/`](fichiers/). Plusieurs sont des **fichiers de référence** réutilisés par tous les projets `plateforme/*` des modules suivants : [`commitlint.config.mjs`](fichiers/M01-E14/commitlint.config.mjs) (E14), [`.pre-commit-config.yaml`](fichiers/M01-E15/.pre-commit-config.yaml) (E15), [`.gitleaks.toml`](fichiers/M01-E16/.gitleaks.toml) (E16), [`CONTRIBUTING.md`](fichiers/M01-E22/CONTRIBUTING.md) et [`Default.md`](fichiers/M01-E22/.gitlab/merge_request_templates/Default.md) (E22), et le script [`gitlab-proteger-projet.sh`](fichiers/M01-E11/gitlab-proteger-projet.sh) (E11).

**Choix structurant du palier (repris dans tout le workbook)** : méthode de fusion **« commit de fusion avec historique semi-linéaire »** (`merge_method: rebase_merge`, décision de l'équipe appliquée en E11), squash autorisé, message des suggestions `chore(revue): …`, modèle de commit de fusion qui conserve la première ligne `Merge branch …` et ajoute les approbateurs. Justification en E11.

Les scripts de fabrication (E12, E13, E18, E19), les configurations commitlint, pre-commit et Gitleaks, et les checks correspondants ont été testés sur des dépôts locaux (Git 2.43 à 2.47, pre-commit 4.6.2, commitlint 21.2.3, Gitleaks 8.30.1). Les appels à l'API GitLab suivent la documentation de GitLab 19 mais n'ont pas été rejoués sur une instance réelle : les points incertains sont signalés « ⚠️ À vérifier sur ta version ».

---

### M01-E10 — Le cycle d'une merge request : branche, revue, suggestions, fusion

**Solution**

1. Branche et fiche (exemple complet : [`fichiers/M01-E10/forge.md`](fichiers/M01-E10/forge.md), version **après** la revue de Karim) :
   ```
   admin@adm01:~/medisphere$ git switch main && git pull
   admin@adm01:~/medisphere$ git switch -c docs/fiche-forge
   admin@adm01:~/medisphere$ $EDITOR docs/socle/forge.md
   admin@adm01:~/medisphere$ git add docs/socle/forge.md
   admin@adm01:~/medisphere$ git commit -m "docs(socle): fiche de service de la forge GitLab"
   ```
2. Push et création de la MR en une commande :
   ```
   admin@adm01:~/medisphere$ git push -u origin docs/fiche-forge \
       -o merge_request.create -o merge_request.target=main \
       -o merge_request.title="docs(socle): fiche de service de la forge" \
       -o merge_request.draft -o merge_request.remove_source_branch
   remote: View merge request for docs/fiche-forge:
   remote:   https://git01.par1.medisphere.internal/plateforme/medisphere/-/merge_requests/1
   ```
   Puis description, *assignee* (toi), *reviewer* (`karim.benali`) dans l'interface. La description donne le contexte (PLAT-220), ce que contient la fiche et comment tu l'as vérifiée (rendu Markdown relu, URL et adresses contrôlées).
3. Sortie du brouillon (*Mark as ready*), puis `revue-karim.sh` : trois fils apparaissent (une suggestion sur la ligne 1, une demande de section « En cas d'indisponibilité », une question).
4. Traitement :
   - *Apply suggestion* crée **sur la branche distante** un commit dont tu es l'auteur, avec le message par défaut `Apply 1 suggestion(s) to 1 file(s)` (et un pied `Co-authored-by: Karim Benali …`). Ton clone est désormais en retard d'un commit.
   - Réponse à la question dans le fil (par exemple : « une fiche par service, liée depuis l'inventaire : l'inventaire reste un tableau d'une ligne par hôte, la fiche porte l'exploitation »).
   - Section ajoutée en local, puis :
     ```
     admin@adm01:~/medisphere$ git push
      ! [rejected]        docs/fiche-forge -> docs/fiche-forge (fetch first)
     admin@adm01:~/medisphere$ git pull --rebase      # ou git pull, avec pull.rebase=true (E03)
     admin@adm01:~/medisphere$ git push
     ```
   - Les fils sont résolus. Règle de l'équipe (reprise dans CONTRIBUTING) : **celui qui a ouvert le fil le résout** ; l'auteur répond et signale « corrigé dans <commit> ». Ici, Karim étant simulé, tu les résous toi-même.
5. Onglet *Changes* : le menu « Compare … and … » permet d'afficher la différence entre deux **versions** de la MR (une par push), utile pour ne relire que ce qui a changé depuis sa revue.
6. `revue-karim.sh --approuver` : Karim vérifie qu'il ne reste aucun fil ouvert et que la section existe, puis approuve.
7. Fusion avec suppression de la branche source, puis :
   ```
   admin@adm01:~/medisphere$ git switch main && git pull
   admin@adm01:~/medisphere$ git branch -d docs/fiche-forge
   admin@adm01:~/medisphere$ git fetch --prune
   admin@adm01:~/medisphere$ git log --graph --oneline -5
   *   8c1d2e4 Merge branch 'docs/fiche-forge' into 'main'
   |\
   | * 5b7a9f0 docs(socle): section en cas d'indisponibilité
   | * 2f43c11 Apply 1 suggestion(s) to 1 file(s)
   | * a91e3b2 docs(socle): fiche de service de la forge GitLab
   |/
   * 77d0c5a docs(socle): …
   ```
   Méthode par défaut d'un projet neuf : *Merge commit* ; GitLab a créé un commit de fusion (`--no-ff`) même si une avance rapide était possible.
8. *Assignee* : celui qui porte la MR jusqu'à la fusion (en général l'auteur). *Reviewer* : celui dont on attend une relecture ; GitLab lui affiche la MR dans sa liste « à relire ». Le message `Apply 1 suggestion(s) to 1 file(s)` n'a pas de type : commitlint le refusera en CI (E14, E24). D'où le réglage du message des suggestions en E11.

**Explications**
- Une MR n'est pas un objet Git : c'est une demande d'intégrer une branche dans une autre, plus une discussion. GitLab garde pour chaque MR une référence `refs/merge-requests/<IID>/head` (la pointe de la branche source) et les **versions** successives du diff en base : on peut relire l'historique de la revue même après la suppression de la branche.
- Les *push options* sont transmises au serveur par le protocole Git (`git push -o`) et interprétées par GitLab à la réception : utile en script et sans navigateur.
- La suggestion est appliquée par GitLab **côté serveur** : c'est un vrai commit, avec ton identité de compte. C'est pour cela qu'il faut récupérer la branche avant de pousser à nouveau.
- L'approbation, dans CE, est un signal : elle s'affiche, elle peut être exigée par une règle d'équipe, mais elle ne bloque pas le bouton de fusion (les règles d'approbation obligatoires sont Premium).

**Alternatives**
- Créer la MR depuis l'interface (lien affiché par `git push`) : plus guidé, moins reproductible.
- `glab mr create` : la CLI officielle, scriptable, qui lit aussi les modèles de description.
- Revue groupée (*Start a review*) : le relecteur publie tous ses commentaires en une fois, l'auteur reçoit une seule notification.

**Pièges classiques**
- Oublier que la suggestion a créé un commit distant, puis « résoudre » le refus de push par `--force` : on efface la suggestion appliquée.
- Laisser la MR en brouillon : le relecteur ne la voit pas comme « à relire », et la fusion est bloquée.
- Résoudre soi-même les fils du relecteur sans répondre : il ne sait pas ce qui a été fait.
- Écrire un mot de passe (celui de `root`) dans la fiche : la documentation d'exploitation dit **où** est le secret, jamais **ce qu'il est**.
- Valeur de *push option* avec espaces non protégée : seul le premier mot devient le titre.

**En production chez MédiSphère**
- Toute modification de `plateforme/*` passe par ce cycle, y compris la documentation : c'est la trace d'audit (qui a demandé, qui a relu, quand).
- Les fiches de service sont liées depuis l'inventaire et revues à chaque changement majeur (montée de version de GitLab, E29).
- La revue a un délai cible (un jour ouvré) : une MR qui attend une semaine est une MR qui va diverger.

---

### M01-E11 — Protéger `main` : branches protégées et règles de fusion (limites de CE)

**Solution**

1. État initial par l'API (jeton des checks) :
   ```
   admin@adm01:~$ T=$(<~/.config/workbook/gitlab-checks.token)
   admin@adm01:~$ U=https://git01.par1.medisphere.internal/api/v4
   admin@adm01:~$ curl -s -H "PRIVATE-TOKEN: $T" "$U/projects/plateforme%2Fmedisphere/protected_branches/main" \
       | jq '{push: [.push_access_levels[].access_level_description], merge: [.merge_access_levels[].access_level_description], allow_force_push}'
   admin@adm01:~$ curl -s -H "PRIVATE-TOKEN: $T" "$U/projects/plateforme%2Fmedisphere" \
       | jq '{merge_method, squash_option, only_allow_merge_if_all_discussions_are_resolved, remove_source_branch_after_merge, suggestion_commit_message, merge_commit_template}'
   admin@adm01:~$ curl -s -H "PRIVATE-TOKEN: $T" "$U/groups/plateforme" | jq .default_branch_protection_defaults
   ```
   (Le jeton dans une variable du shell reste acceptable sur `adm01` pour une session interactive ; il n'apparaît pas dans `ps`, mais il est dans l'environnement du shell : ferme la session ou `unset T` après.) Valeurs typiques d'un projet neuf : `main` protégée avec push et fusion Maintainers, `merge_method: merge`, `squash_option: default_off`, fils non obligatoires. ⚠️ À vérifier sur ta version : la protection par défaut de l'instance et du groupe.
2. Comparaison des méthodes (deux MR A et B fusionnées l'une après l'autre) :

   | Méthode | Graphe de `main` | `--first-parent` | Contrainte auteur | Commits relus conservés |
   |---|---|---|---|---|
   | *Merge commit* | commits de fusion, branches qui se croisent si non rebasées | une ligne par MR | aucune | oui |
   | *Merge commit with semi-linear history* | commits de fusion, chaque branche part de la pointe précédente : « échelle » propre | une ligne par MR | rebase si `main` a avancé (bouton *Rebase* de GitLab) | oui |
   | *Fast-forward* | ligne droite, aucun commit de fusion | perd la notion de MR | rebase si `main` a avancé | oui (mais sans regroupement) |

   **Choix retenu : semi-linéaire.** `git log --first-parent main` donne une ligne par MR (avec le titre de la MR et, grâce au modèle, les approbateurs) ; chaque commit relu reste intact et testable par `git bisect` (la branche était à jour, donc chaque commit a été construit sur l'état réel de `main`) ; semantic-release (E25) lit les commits conventionnels de la branche et ignore les messages `Merge branch …`. Le fast-forward donne un graphe plus simple mais efface la frontière des MR, ce qui complique un retour arrière (« annuler la MR » = annuler N commits) et l'audit.
3. Interface : *Settings > Repository > Protected branches* : `main`, *Allowed to merge* = Maintainers, *Allowed to push and merge* = No one, *Allowed to force push* décoché. *Settings > Merge requests* : méthode, squash « Allow », « All threads must be resolved », « Enable 'Delete source branch' option by default », message des suggestions `chore(revue): appliquer %{suggestions_count} suggestion(s) de revue`, modèle de commit de fusion :
   ```
   Merge branch '%{source_branch}' into '%{target_branch}'

   %{title}

   %{issues}

   See merge request %{reference}

   %{approved_by}
   ```
4. Tests :
   ```
   admin@adm01:~/medisphere$ git push origin HEAD:main
   remote: GitLab: You are not allowed to push code to protected branches on this project.
    ! [remote rejected] HEAD -> main (pre-receive hook declined)
   ```
   Le push forcé est refusé avec le même type de message (le texte exact dépend de la version). Une MR avec un fil ouvert affiche « Merge blocked: all threads must be resolved ». En empruntant l'identité de `lucas.martin` (Developer), le bouton de fusion n'apparaît pas sur une MR vers `main`.
5. Groupe : *Settings > Repository > Default branch* propose des niveaux par rôle (Developer, Maintainer) et l'autorisation du premier push aux Developers ; « No one » n'y figure pas (un projet neuf doit pouvoir recevoir son premier push). Réglage retenu : push et fusion Maintainers, pas de push forcé, premier push par les Developers refusé (*Fully protected*). Le script fait ensuite passer chaque projet en « No one ».
6. Script : [`fichiers/M01-E11/gitlab-proteger-projet.sh`](fichiers/M01-E11/gitlab-proteger-projet.sh), à copier dans `~/lab-scripts/` (`chmod 700`). Points clés : jeton passé par un descripteur (`-H @<(…)`), réglages en un seul `PUT /projects/:id`, protection comparée à la règle avant d'agir (idempotence), suppression puis recréation si elle diffère, option `--pipeline-obligatoire` prévue pour E24, `--ff` si l'équipe changeait d'avis.
   ```
   admin@adm01:~$ ~/lab-scripts/gitlab-proteger-projet.sh plateforme/medisphere --dry-run
   admin@adm01:~$ ~/lab-scripts/gitlab-proteger-projet.sh plateforme/medisphere
   OK  réglages des MR de plateforme/medisphere (méthode : rebase_merge)
   OK  main déjà protégée selon la règle
   ```
7. Réponse au ticket (extrait du tableau attendu) :

   | Besoin de Sophie | Dans CE ? | Compensation |
   |---|---|---|
   | Approbation obligatoire (N relecteurs) | non (Premium) | règle d'équipe (CONTRIBUTING), approbateurs inscrits dans le commit de fusion (`%{approved_by}`), contrôle a posteriori par une requête API mensuelle |
   | Interdire l'approbation par l'auteur | non (Premium) | idem, la requête mensuelle compare auteur et approbateurs |
   | *Code Owners* obligatoires | non (Premium ; le fichier `CODEOWNERS` est lu mais pas bloquant) | relecteurs désignés dans CONTRIBUTING par dossier |
   | *Push rules* : format des messages, taille des fichiers, secrets, commits signés | non (Premium) | pre-commit (E15), Gitleaks (E16), pipeline obligatoire (E24), hooks côté serveur (E26), signature vérifiée (E27) |
   | Interdire le push direct et le push forcé | **oui** | branche protégée « No one », push forcé interdit |
   | Fils résolus avant fusion | **oui** | réglage du projet |

**Explications**
- Une branche protégée est vérifiée par GitLab à la réception (hook interne *pre-receive*) : la règle s'applique à tout push, quels que soient l'outil et la machine. C'est une garantie serveur, contrairement aux hooks locaux.
- Niveaux d'accès de l'API : `0` personne, `30` Developer, `40` Maintainer, `60` Admin (auto-géré uniquement). Dans CE, seuls les **rôles** sont disponibles (pas d'utilisateur ou de groupe nommé), et les champs `allowed_to_push`/`allowed_to_merge` de l'API, qui permettent de modifier une protection existante, sont marqués Premium : d'où la suppression puis recréation, qui laisse `main` sans protection quelques secondes (acceptable hors activité, à éviter sur un projet très actif).
- Avec le semi-linéaire, GitLab refuse la fusion tant que la branche n'est pas à jour de `main` et propose un bouton *Rebase* (rebase côté serveur, sans conflit) : c'est la seule contrainte supplémentaire pour l'auteur.

**Alternatives**
- **Fast-forward** : historique parfaitement linéaire ; choix valable si l'équipe squashe systématiquement (une MR = un commit). Dans ce cas, le titre de MR devient le seul message, et le modèle de squash doit être conventionnel.
- **Squash imposé** : historique de `main` très propre, mais les commits relus disparaissent, `git bisect` perd en finesse, et semantic-release ne voit qu'un type par MR.
- **Terraform/OpenTofu** (provider `gitlabhq/gitlab`) pour gérer projets et protections comme du code : ce sera cohérent avec le module 05.

**Pièges classiques**
- Protéger `main` avant d'avoir poussé un travail local en attente : il faut ensuite passer par une branche et une MR.
- Croire qu'un administrateur passe outre « No one » : non, il doit lever la protection.
- Modifier le modèle de commit de fusion en commençant par autre chose que `Merge branch` : commitlint ne l'ignore plus et le refuse.
- `%{approved_by}` est vide si l'approbation est donnée après le calcul du message par l'interface : recharge la page avant de fusionner. ⚠️ À vérifier sur ta version.
- Oublier que le réglage de groupe ne s'applique qu'aux **nouveaux** projets.

**En production chez MédiSphère**
- Le script (ou un module OpenTofu au M05) est lancé à la création de chaque projet, et en contrôle hebdomadaire en `--dry-run` pour détecter une dérive.
- Les événements d'audit (protections modifiées, emprunts d'identité) sont exportés vers le SIEM ; dans CE, les événements d'audit disponibles sont limités : les journaux `production_json.log` et `audit_json.log` de `git01` complètent.
- Si l'entreprise passe en Premium, les compensations deviennent des règles natives : approbations obligatoires, *push rules*, *Code Owners*.

---

### M01-E12 — Rebase interactif : préparer une branche pour la revue

**Solution**

1. Récupération et lecture :
   ```
   admin@adm01:~/DevOpsPrivateCloud$ modules/01-git/ressources/M01-E12/fabriquer-depot.sh
   admin@adm01:~/src/git-labo$ git fetch --prune
   admin@adm01:~/src/git-labo$ git switch e12/verif-sauvegardes
   admin@adm01:~/src/git-labo$ git log --oneline origin/main..
   29a087b fixup! ajout option datastore
   b82e7c8 nettoyage
   7540bb4 doc
   605f7a6 debug
   0d35eb8 fix typo
   d7e8e10 ajout option datastore
   99ee2e4 wip
   ```
   Lecture des diffs : `wip` crée le script avec un `if` sans `fi` ; `ajout option datastore` ajoute l'option (valeur par défaut `local`, fausse) ; `fix typo` ajoute le `fi` ; `debug` ajoute `set -x` et une ligne qui affiche `PBS_PASSWORD` ; `doc` crée le mode d'emploi ; `nettoyage` retire les deux lignes de débogage ; `fixup!` corrige la valeur par défaut en `ds-lab`. Plan : un commit « script » = `wip` + option + `fix typo` + `fixup!` ; `debug` et `nettoyage` supprimés **tous les deux** ; un commit « doc ».
2. Filet : `git branch sauvegarde/e12-avant-rebase`.
3. Rebase :
   ```
   admin@adm01:~/src/git-labo$ git rebase -i --autosquash --exec 'bash -n rebase/verif-pbs.sh' origin/main
   ```
   Liste éditée (ordre du plus ancien au plus récent ; `--autosquash` a déjà placé le `fixup!` sous son commit) :
   ```
   reword 99ee2e4 wip
   fixup d7e8e10 ajout option datastore
   fixup 29a087b fixup! ajout option datastore
   fixup 0d35eb8 fix typo
   exec bash -n rebase/verif-pbs.sh
   drop 605f7a6 debug
   drop b82e7c8 nettoyage
   reword 7540bb4 doc
   exec bash -n rebase/verif-pbs.sh
   ```
   Messages : `feat(sauvegarde): script de vérification des sauvegardes PBS` et `docs(sauvegarde): mode d'emploi de verif-pbs.sh`. Le `exec` n'est exécuté qu'**après** les `fixup` qui le précèdent : c'est l'état du commit final qui est testé, pas les états intermédiaires disparus. Version finale : [`fichiers/M01-E12/verif-pbs.sh`](fichiers/M01-E12/verif-pbs.sh) et [`verif-pbs.md`](fichiers/M01-E12/verif-pbs.md).
4. Preuves :
   ```
   admin@adm01:~/src/git-labo$ git log --oneline origin/main..
   c8ffe02 docs(sauvegarde): mode d'emploi de verif-pbs.sh
   deecec3 feat(sauvegarde): script de vérification des sauvegardes PBS
   admin@adm01:~/src/git-labo$ git diff sauvegarde/e12-avant-rebase HEAD -- rebase/verif-pbs.sh rebase/verif-pbs.md
   admin@adm01:~/src/git-labo$ git range-diff origin/main sauvegarde/e12-avant-rebase HEAD
   ```
   Dans `range-diff`, `1: 99ee2e4 ! 1: deecec3 wip` signale un commit « apparié mais modifié » : le message a changé (`-    wip` / `+    feat(…)`) et le contenu aussi (lignes `++` ajoutées par les `fixup`). Les commits supprimés apparaissent avec `<` seuls.
5. Publication : le push simple est refusé (*non-fast-forward*), car l'ancienne pointe n'est plus une ancêtre de la nouvelle.
   ```
   admin@adm01:~/src/git-labo$ git push --force-with-lease --force-if-includes
   ```
   `--force` écrase quoi qu'il y ait sur le serveur : un commit poussé par Karim entre-temps serait perdu sans avertissement. `--force-with-lease` refuse si la branche distante n'est plus là où ton clone la croit (`origin/e12/…`). Mais un `git fetch` fait entre-temps met à jour cette référence et « endort » la protection : `--force-if-includes` vérifie en plus que la pointe distante a bien été intégrée localement.
6. MR vers `main`, non fusionnée.
7. Rattrapage :
   ```
   admin@adm01:~/src/git-labo$ git reflog show e12/verif-sauvegardes | head
   admin@adm01:~/src/git-labo$ git reset --hard e12/verif-sauvegardes@{1}     # ou ORIG_HEAD juste après le rebase
   ```
8. `squash` fusionne le commit dans le précédent **et ouvre l'éditeur** pour combiner les messages ; `fixup` jette le message du commit absorbé (`fixup -C` garde au contraire le sien). commitlint ignore par défaut les messages `fixup!` et `squash!` (`defaultIgnores`) : un tel commit oublié passerait le hook et la CI de commitlint, puis arriverait dans `main` avec la méthode semi-linéaire. Le job de CI (E24) doit donc refuser explicitement les commits `fixup!`/`squash!` d'une MR.

**Explications**
- Un rebase ne « déplace » pas des commits : il en **crée de nouveaux** (nouvelles empreintes) en rejouant les diffs, puis déplace la branche. Les anciens restent accessibles par le reflog jusqu'au ramasse-miettes (90 jours par défaut pour les entrées accessibles, 30 pour les autres).
- Pourquoi supprimer `debug` **et** `nettoyage` plutôt que les fusionner : fusionnés, ils s'annulent et le résultat est le même ; supprimés, la liste est plus claire et le diff du mot de passe n'est jamais rejoué. Dans les deux cas, aucun commit restant ne contient la ligne.
- Le but n'est pas l'esthétique : chaque commit de `main` doit construire et passer les tests, sinon `git bisect` (E44) tombe sur des commits cassés qui n'ont rien à voir avec le défaut cherché.

**Alternatives**
- `git reset --soft origin/main` puis deux commits refaits à la main : rapide pour une petite branche, mais on perd la discipline du plan et l'auteur/la date des commits.
- Squash à la fusion (bouton GitLab) : un seul commit, sans effort. Inadapté ici : la règle de l'équipe est d'avoir des commits significatifs, et le commit `debug` aurait quand même été visible dans la MR (et dans `refs/merge-requests`).
- `git commit --fixup` dès le départ : la branche se range presque toute seule avec `--autosquash`.

**Pièges classiques**
- Lancer `git rebase -i main` avec un `main` local périmé : la branche n'est pas à jour du serveur. Toujours `origin/main` après un `fetch`.
- Supprimer `nettoyage` mais garder `debug` : la ligne réapparaît.
- `git push --force` « parce que ça marche » : un jour, il écrase le travail d'un collègue.
- Réécrire une branche sur laquelle quelqu'un d'autre a basé son travail : il devra rebaser la sienne avec `--onto` (ou `git pull --rebase`, qui sait détecter les commits réécrits).
- Oublier que la ligne `DEBUG token=…` est déjà sur le serveur dans l'ancienne version de la branche (et dans `refs/merge-requests` si une MR existait) : si un vrai secret avait été affiché ou écrit, la réécriture ne suffirait pas (E17).

**En production chez MédiSphère**
- La CI vérifie chaque commit d'une MR (commitlint, refus des `fixup!`), pas seulement la pointe.
- Les branches personnelles sont réécrites librement **avant** la revue ; après les premiers commentaires, on ajoute des commits `fixup!` pour que le relecteur voie le delta, et on range juste avant la fusion.

---

### M01-E13 — Résoudre des conflits de fusion et de rebase (`rerere`, outils)

**Solution**

1. Réglages globaux :
   ```
   admin@adm01:~$ git config --global rerere.enabled true          # rejoue une résolution déjà faite
   admin@adm01:~$ git config --global merge.conflictStyle zdiff3    # montre l'ancêtre commun dans les marqueurs
   ```
2. Prédiction sans toucher à la copie de travail :
   ```
   admin@adm01:~/src/git-labo$ git fetch --prune
   admin@adm01:~/src/git-labo$ git log --oneline --graph --left-right origin/main...origin/e13/inventaire-runner01
   admin@adm01:~/src/git-labo$ git merge-tree --write-tree --name-only origin/main origin/e13/inventaire-runner01
   <arbre>
   conflits/inventaire.md

   Auto-merging conflits/inventaire.md
   CONFLICT (content): Merge conflict in conflits/inventaire.md
   Auto-merging conflits/sauvegarde.sh
   ```
   Un seul fichier en conflit, `sauvegarde.sh` fusionne **sans conflit** : c'est le piège.
3. Essai par fusion :
   ```
   admin@adm01:~/src/git-labo$ git switch -c essai/e13-fusion origin/e13/inventaire-runner01
   admin@adm01:~/src/git-labo$ git merge origin/main
   ```
   Les marqueurs `zdiff3` montrent, entre `|||||||` et `=======`, la ligne `dns01` d'origine (`1 Go`, rôle court) : Karim a changé le **rôle** et ajouté `git01`, toi la **mémoire** et ajouté `runner01`. `git log --merge` liste les commits des deux côtés qui touchent le fichier en conflit. Puis `git merge --abort`, `git switch e13/inventaire-runner01`, `git branch -D essai/e13-fusion`.
4. Rebase et premiers arrêts :
   ```
   admin@adm01:~/src/git-labo$ git switch e13/inventaire-runner01 && git reset --hard origin/e13/inventaire-runner01
   admin@adm01:~/src/git-labo$ git rebase origin/main
   CONFLICT (content): Merge conflict in conflits/inventaire.md
   Recorded preimage for 'conflits/inventaire.md'
   Could not apply 81bfe40... docs(inventaire): ajouter runner01
   ```
   Pendant le rebase, `HEAD` est la branche en construction (`main` de Karim, plus tes commits déjà rejoués) ; le commit rejoué (le tien) est « theirs ». Résolution du premier arrêt : garder la ligne `dns01` de Karim, sa ligne `git01`, et ajouter `runner01`. Au second arrêt (`corriger la mémoire de dns01`) : ligne `dns01` avec `2 Go` **et** le rôle de Karim, en gardant `git01` qui fait partie du bloc. Après chaque résolution, relire tout le tableau, `git add`, `git rebase --continue` (« Recorded resolution for 'conflits/inventaire.md' »). Résultat : [`fichiers/M01-E13/inventaire.md`](fichiers/M01-E13/inventaire.md).
5. Test :
   ```
   admin@adm01:~/src/git-labo$ SIMULATION=1 conflits/sauvegarde.sh 2011
   conflits/sauvegarde.sh: line 23: DEST: unbound variable
   ```
   **Conflit sémantique** : Karim a renommé `DEST` en `STOCKAGE` (définition et usages qu'il connaissait) ; ton commit ajoute une fonction `verifier_stockage` qui utilise `$DEST`, dans une zone du fichier qu'il n'a pas touchée. Git fusionne des **lignes**, pas du sens : aucun conflit textuel, mais la variable n'existe plus, et `set -u` arrête le script.
6. Correction dans le bon commit, en refaisant le rebase :
   ```
   admin@adm01:~/src/git-labo$ git reset --hard origin/e13/inventaire-runner01
   admin@adm01:~/src/git-labo$ git rebase -i origin/main      # « edit » sur feat(sauvegarde): vérifier le stockage…
   Resolved 'conflits/inventaire.md' using previous resolution.
   Could not apply 81bfe40... docs(inventaire): ajouter runner01
   admin@adm01:~/src/git-labo$ git diff                        # relire ce que rerere a réappliqué
   admin@adm01:~/src/git-labo$ git add conflits/inventaire.md && git rebase --continue
   Resolved 'conflits/inventaire.md' using previous resolution.
   …
   Stopped at cf24db9...  feat(sauvegarde): vérifier le stockage avant de sauvegarder
   admin@adm01:~/src/git-labo$ sed -i 's/\$DEST/$STOCKAGE/g' conflits/sauvegarde.sh   # ou à la main, en relisant
   admin@adm01:~/src/git-labo$ SIMULATION=1 conflits/sauvegarde.sh 2011
   Sauvegarde de 1 VM(s) vers pbs-par2
   + vzdump 2011 --storage pbs-par2 --mode snapshot
   admin@adm01:~/src/git-labo$ git commit --amend -a --no-edit && git rebase --continue
   ```
   `rerere` a réappliqué les deux résolutions ; il laisse le fichier « non fusionné » pour que tu valides (sauf `rerere.autoUpdate`). Script final : [`fichiers/M01-E13/sauvegarde.sh`](fichiers/M01-E13/sauvegarde.sh).
7. `git push --force-with-lease`, MR vers `main`.

**Explications**
- Fusion à trois versions : Git compare chaque côté à l'**ancêtre commun**. Une zone modifiée d'un seul côté est prise telle quelle ; modifiée des deux côtés (ou dans des lignes adjacentes), c'est un conflit. `zdiff3` affiche l'ancêtre, ce qui transforme une devinette (« quelle ligne est la bonne ? ») en lecture (« qui a changé quoi »).
- `rerere` (*reuse recorded resolution*) mémorise, pour un conflit donné (sa « préimage » normalisée), la résolution choisie (« postimage »). Il est précieux quand on refait un rebase, qu'on teste une fusion puis qu'on l'annule, ou qu'on rebase régulièrement une branche longue.
- Pourquoi corriger dans le commit fautif : avec la méthode semi-linéaire, chaque commit arrive dans `main`. Le commit `feat(sauvegarde)` cassé suivi d'un `fix` serait un commit sur lequel `git bisect` tomberait.

**Alternatives**
- Fusionner `main` dans ta branche au lieu de rebaser : un seul conflit à résoudre, mais un commit de fusion dans la branche, contraire à la règle de l'équipe. GitLab l'accepterait (la méthode semi-linéaire exige seulement que la branche contienne la pointe de `main`), et ce commit « Merge branch 'main' into … » arriverait tel quel dans l'historique de `main`.
- `git mergetool` (`vimdiff`, `meld` sur un poste graphique) : utile pour de gros conflits ; la compréhension reste la même.
- Faire la correction de `DEST` dans un commit `fixup!` puis `rebase -i --autosquash` : équivalent, et souvent plus simple qu'un `edit`.

**Pièges classiques**
- Prendre « un côté » entier (`git checkout --ours/--theirs`) : on perd `git01` ou `runner01`. Et pendant un rebase, `--ours` désigne `main`, pas toi.
- Résoudre le second arrêt en remplaçant tout le bloc par la seule ligne `dns01` : la ligne `git01`, qui faisait partie du bloc, disparaît. C'est exactement ce que le check détecte.
- Enregistrer une mauvaise résolution avec `rerere` : elle sera rejouée à chaque fois. `git rerere forget conflits/inventaire.md` pendant le conflit, puis résoudre à nouveau.
- S'arrêter quand les marqueurs ont disparu sans tester : le conflit sémantique passe.
- Laisser des marqueurs dans un fichier Markdown : il « s'affiche » quand même ; le hook `check-merge-conflict` (E15) les arrête.

**En production chez MédiSphère**
- Des branches courtes, rebasées souvent : moins de conflits, plus petits.
- Les tests (ShellCheck, tests du projet, au M02 `bats`) tournent en CI sur le résultat de la fusion : c'est ce qui attrape les conflits sémantiques que personne n'a vus.
- Les fichiers de données partagés (inventaire) deviennent des données d'une source de vérité (NetBox, M06) : on supprime le conflit à la racine.

---

### M01-E14 — Conventional Commits et commitlint en local

**Solution**

1. Tableau (versions à partir de `1.4.2`, préréglage `conventionalcommits` de semantic-release) ; résultats vérifiés avec commitlint 21.2.3 :

   | # | Conforme ? | Raison (règle commitlint) | Version produite |
   |---|---|---|---|
   | 1 | oui | | aucune (`docs`) |
   | 2 | oui | | **1.5.0** (`feat` → mineure) |
   | 3 | non | type en majuscule (`type-case`), donc type inconnu (`type-enum`) | (refusé) ; sinon aucune : semantic-release ne reconnaît pas `Fix` |
   | 4 | oui | `!` signale une rupture | **2.0.0** (rupture → majeure, même sur un `fix`) |
   | 5 | non | point final (`subject-full-stop`) ; et « mise à jour » n'informe de rien | — |
   | 6 | non | ni type ni sujet (`type-empty`, `subject-empty`) | — |
   | 7 | oui | pied `BREAKING CHANGE:` | **2.0.0** |
   | 8 | non | sujet qui commence par une majuscule (`subject-case`) | — |
   | 9 | oui | | **1.4.3** (`perf` → correctif) |
   | 10 | **ignoré** | message de fusion de GitLab (`defaultIgnores`) | aucune |
   | 11 | **ignoré** | `fixup!` est dans `defaultIgnores` : il passe, ce qui est un problème (voir E12) | aucune |
   | 12 | oui | | aucune (`ci`) |
   | 13 | non | en-tête de plus de 100 caractères (`header-max-length`) : le détail va dans le corps | — |

2. Node.js 24 :
   ```
   admin@adm01:~$ curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key -o /tmp/nodesource.asc
   admin@adm01:~$ gpg --show-keys /tmp/nodesource.asc            # empreinte à noter (et à comparer à la documentation de NodeSource)
   admin@adm01:~$ sudo gpg --dearmor -o /usr/share/keyrings/nodesource.gpg /tmp/nodesource.asc
   admin@adm01:~$ sudo cp nodesource.sources /etc/apt/sources.list.d/nodesource.sources
   admin@adm01:~$ sudo cp nodejs.pref /etc/apt/preferences.d/nodejs
   admin@adm01:~$ sudo apt update && sudo apt install -y nodejs
   admin@adm01:~$ apt policy nodejs
   nodejs:
     Installed: 24.x.y-1nodesource1
     Candidate: 24.x.y-1nodesource1
    Version table:
    *** 24.x.y-1nodesource1 600
           600 https://deb.nodesource.com/node_24.x nodistro/main amd64 Packages
        20.19.2+dfsg-1+deb13u… 500
           500 http://deb.debian.org/debian trixie/main amd64 Packages
   ```
   Fichiers : [`nodesource.sources`](fichiers/M01-E14/nodesource.sources), [`nodejs.pref`](fichiers/M01-E14/nodejs.pref) (repris de ce que fait le script officiel `setup_24.x`, sans l'exécuter en `curl | sudo bash`). La priorité 600 garde NodeSource même si Debian publiait une version plus haute.
3. Outils npm sans `sudo` :
   ```
   admin@adm01:~$ npm config set prefix ~/.local                  # écrit prefix=/home/admin/.local dans ~/.npmrc
   admin@adm01:~$ npm install -g @commitlint/cli@21.2.3 @commitlint/config-conventional@21.2.3
   admin@adm01:~$ commitlint --version
   @commitlint/cli@21.2.3
   ```
   Fichier : [`npmrc`](fichiers/M01-E14/npmrc). Si `commitlint` est introuvable, `~/.local/bin` n'était pas encore dans le `PATH` à l'ouverture de session (Debian l'ajoute dans `~/.profile` s'il existe) : reconnecte-toi.
4. Configuration de référence : [`fichiers/M01-E14/commitlint.config.mjs`](fichiers/M01-E14/commitlint.config.mjs) (`extends`, plus `helpUrl` vers la section du CONTRIBUTING de E22).
   ```
   admin@adm01:~/medisphere$ printf '%s\n' 'refactor: Renommer DEST en STOCKAGE' | commitlint
   ⧗   input: refactor: Renommer DEST en STOCKAGE
   ✖   subject must not be sentence-case, start-case, pascal-case, upper-case [subject-case]
   admin@adm01:~/medisphere$ commitlint --print-config | grep -A3 subject-case
   ```
5. Hook artisanal : [`fichiers/M01-E14/commit-msg`](fichiers/M01-E14/commit-msg), copié dans `.git/hooks/commit-msg` (`chmod +x`). Il ne protège que ce clone : `.git/hooks/` n'est ni versionné ni cloné, et `git commit --no-verify` le contourne.
6. Historique :
   ```
   admin@adm01:~/medisphere$ commitlint --from "$(git rev-list --max-parents=0 HEAD)" --to HEAD
   ```
   (le premier commit lui-même n'est pas contrôlé : `--from` est exclu). Les anciens messages de M00 ne sont pas conformes : on **ne réécrit pas** `main` (protégée, publiée, étiquette `socle-v0`, clones existants). La règle s'applique à partir du commit qui ajoute la configuration ; la CI (E24) ne contrôlera que les commits de chaque MR.
7. MR (branche `build/commitlint` ou `chore/commitlint`), fusion, puis contrôle :
   ```
   admin@adm01:~/medisphere$ git fetch && git switch main && git pull
   admin@adm01:~/medisphere$ commitlint --from "$(git log --diff-filter=A --format=%H -1 -- commitlint.config.mjs)^" --to origin/main
   ```

**Explications**
- Conventional Commits ajoute une **structure** (type, portée, `!`, pied `BREAKING CHANGE:`) qu'un programme peut lire. Couplée à SemVer : rupture → majeure, `feat` → mineure, `fix`/`perf` → correctif ; le reste ne publie rien. semantic-release calcule ainsi la version suivante, et les notes de version se rédigent seules.
- Où commitlint trouve `extends` : il résout `@commitlint/config-conventional` depuis le dossier courant (le dépôt, sans `node_modules`), puis dans le dossier des paquets npm **globaux**, qu'il déduit du préfixe npm (variable `npm_config_prefix`, puis `~/.npmrc`, puis préfixe par défaut de Node). Avec le préfixe `~/.local`, les deux paquets sont dans `~/.local/lib/node_modules` : trouvés. Installés dans un projet npm à part (`npm install` dans un autre dossier), ils ne seraient **pas** trouvés : `Cannot find module "@commitlint/config-conventional"`. ⚠️ Ce comportement (repli sur les paquets globaux) a été vérifié avec commitlint 21.2.3 ; c'est aussi ce qui permet au hook pre-commit de E15 de fonctionner.
- Les messages ignorés par défaut (`Merge …`, `Revert …`, `fixup!`, `squash!`, `Initial commit`…) évitent de bloquer les messages produits par les outils.

**Alternatives**
- `npx --yes @commitlint/cli@21.2.3` sans installation : chaque appel télécharge ou lit le cache npm, pas de version figée par poste.
- `sudo npm install -g` : marche, mais écrit dans `/usr/lib/node_modules` en root, et mélange paquets système et outils personnels.
- `@commitlint/prompt-cli` ou `commitizen` : assistants interactifs pour écrire le message ; utiles pour débuter, vite pénibles.

**Pièges classiques**
- `curl … | sudo bash` (script `setup_24.x`) sans le lire : on donne root à un script distant ; ici on reproduit à la main ce qu'il fait.
- Oublier l'épinglage : un `apt full-upgrade` peut un jour préférer le `nodejs` de Debian.
- Sujet qui commence par un nom propre (« GitLab… ») : refusé par `subject-case` ; reformuler (« sauvegarde de GitLab »).
- Écrire `prefix=${HOME}/.local` dans `~/.npmrc` à la main : npm le comprend, mais pas la bibliothèque qui donne à commitlint le dossier global (aucune expansion) : garder un chemin absolu.
- Penser qu'un hook local est une garantie : `--no-verify`, un clone sans hook, une MR créée par l'API (E21) passent outre.

**En production chez MédiSphère**
- La configuration est identique dans tous les projets `plateforme/*` (fichier de référence), et la CI rejoue commitlint sur chaque commit de chaque MR (E24).
- Les messages servent aux notes de version (E25) et aux recherches d'audit (`git log --grep`, liens vers les tickets dans le pied `Refs:`).

---

### M01-E15 — pre-commit : des contrôles versionnés avec le dépôt

**Solution**

1. Installation :
   ```
   admin@adm01:~$ curl -LsSf https://astral.sh/uv/<VERSION>/install.sh -o /tmp/uv-install.sh
   admin@adm01:~$ less /tmp/uv-install.sh && sh /tmp/uv-install.sh       # installe uv dans ~/.local/bin
   admin@adm01:~$ uv tool install pre-commit==4.6.2
   admin@adm01:~$ pre-commit --version
   pre-commit 4.6.2
   ```
2. `rm ~/medisphere/.git/hooks/commit-msg` : sinon `pre-commit install` renomme le hook existant en `commit-msg.legacy` et continue de l'appeler (« mode migration », sauf `--overwrite`) : commitlint tournerait deux fois, avec deux versions potentiellement différentes, et un hook non versionné resterait caché dans le clone.
3. Configuration de référence : [`fichiers/M01-E15/.pre-commit-config.yaml`](fichiers/M01-E15/.pre-commit-config.yaml). Empreintes des étiquettes :
   ```
   admin@adm01:~$ git ls-remote https://github.com/pre-commit/pre-commit-hooks refs/tags/v6.0.0
   3e8a8703264a2f4a69428a0aa4dcb512790b2c8c	refs/tags/v6.0.0
   admin@adm01:~$ git ls-remote https://github.com/gitleaks/gitleaks refs/tags/v8.30.1
   83d9cd684c87d95d656c1458ef04895a7f1cbd8e	refs/tags/v8.30.1
   ```
   (étiquettes légères : l'empreinte est directement celle du commit ; pour une étiquette annotée, prendre la ligne `^{}`.)
   ```
   admin@adm01:~/medisphere$ pre-commit validate-config .pre-commit-config.yaml
   admin@adm01:~/medisphere$ pre-commit install
   pre-commit installed at .git/hooks/pre-commit
   pre-commit installed at .git/hooks/commit-msg
   admin@adm01:~/medisphere$ head -3 .git/hooks/commit-msg
   #!/usr/bin/env bash
   # File generated by pre-commit: https://pre-commit.com
   ```
4. ```
   admin@adm01:~/medisphere$ pre-commit run --all-files --show-diff-on-failure
   admin@adm01:~/medisphere$ git add -A && git commit -m "style: espaces et fins de fichiers normalisés par pre-commit"
   admin@adm01:~/medisphere$ git rev-parse HEAD >> .git-blame-ignore-revs && git add .git-blame-ignore-revs
   admin@adm01:~/medisphere$ git config blame.ignoreRevsFile .git-blame-ignore-revs
   ```
   Séparé pour que la revue du changement fonctionnel ne soit pas noyée dans 200 lignes d'espaces, et pour pouvoir l'écarter de `git blame` (GitLab sait aussi lire `.git-blame-ignore-revs` dans sa vue *Blame*, ⚠️ à vérifier sur ta version).
5. Cas fautifs (sur des fichiers de test non commités) :

   | Cas | Hook qui l'arrête |
   |---|---|
   | espace en fin de ligne | `trailing-whitespace` (corrige le fichier : il faut ré-indexer) |
   | pas de saut de ligne final | `end-of-file-fixer` (corrige) |
   | YAML invalide | `check-yaml` |
   | fichier de 600 Ko | `check-added-large-files` (seuil 500 Ko par défaut) |
   | `<<<<<<<` en début de ligne | `check-merge-conflict` |
   | clé privée jetable | `detect-private-key` **et** `gitleaks` (règle `private-key`) |
   | faux jeton `glpat-XXXX…` | `gitleaks` (règle `gitlab-pat`) |
   | message `Ajout` | `commitlint` (étape `commit-msg`) |

6. `git commit --no-verify` saute **tous** les hooks ; `SKIP=gitleaks git commit …` saute ceux qu'on nomme. Conclusion : les hooks locaux sont un confort pour le développeur (retour immédiat), pas un contrôle. Le contrôle, c'est la CI obligatoire (E24) et les hooks côté serveur (E26).
7. ```
   admin@adm01:~/medisphere$ git log -1 --format=%B > /tmp/msg && pre-commit run commitlint --hook-stage commit-msg --commit-msg-filename /tmp/msg
   ```
   C'est le geste de diagnostic local. En CI (E24), le job `commitlint` du gabarit n'utilise pas pre-commit : il appelle le commitlint figé de `/opt/release-tools` sur toute la plage de commits de la MR (`--from`/`--to`), avec le même `commitlint.config.mjs` et les mêmes versions (21.2.3).
8. MR `build: contrôles pre-commit (espaces, YAML, secrets, messages)`, fusion.

**Explications**
- pre-commit installe chaque dépôt de hooks dans un **environnement isolé** (virtualenv Python, environnement Node, binaire Go compilé), indexé par dépôt et révision, dans `~/.cache/pre-commit`. La version de chaque outil est donc celle du fichier, pas celle du poste : c'est ce qui rend les contrôles identiques chez tous et en CI.
- `default_stages: [pre-commit]` : sans lui, les hooks qui ne déclarent pas d'étape (`detect-private-key`, `gitleaks`) tourneraient aussi quand Git appelle le hook `commit-msg`.
- Le hook local `commitlint` avec `language: node` installe `@commitlint/cli` et `@commitlint/config-conventional` dans son environnement, qui sert de « préfixe global » : la résolution de `extends` fonctionne sans `node_modules` dans le dépôt (même mécanisme qu'en E14). `language_version: system` utilise le Node 24 du poste au lieu d'en télécharger un.
- Pourquoi figer par empreinte : une étiquette Git peut être déplacée par l'amont (ou par un attaquant qui a pris le contrôle du dépôt, comme lors des compromissions de chaînes d'approvisionnement de 2025-2026) ; une empreinte de commit ne peut pas.

**Alternatives**
- `gitleaks-system` (binaire du poste) au lieu de `gitleaks` (compilé) : plus rapide à installer, mais la version dépend du poste.
- Le hook tiers `alessandrojcm/commitlint-pre-commit-hook` : pratique, mais il fige sa propre version de commitlint et ajoute un intermédiaire.
- Lefthook, Husky : équivalents ; Husky suppose un projet Node, ce que nos dépôts ne sont pas.

**Pièges classiques**
- Un hook qui **corrige** fait échouer le commit : relire, `git add`, recommencer.
- `check-added-large-files` ne voit que les fichiers ajoutés dans le commit : avec `pre-commit run --all-files` en CI, il ne voit rien (ajouter `--enforce-all` dans le job de CI, ou laisser la limite au hook serveur de E26).
- Première exécution du hook `gitleaks` sans accès Internet : la compilation échoue (téléchargement de Go et des modules).
- Oublier `pre-commit install` après un nouveau clone : rien ne tourne. Le CONTRIBUTING le rappelle ; certaines équipes ajoutent `init.templateDir` pour l'automatiser.
- Lancer `pre-commit autoupdate` sur `main` sans revue : c'est une mise à jour d'outils comme une autre.

**En production chez MédiSphère**
- Chaque projet `plateforme/*` part de ce fichier et y ajoute ses outils (ShellCheck et shfmt au M02, ansible-lint au M04, tflint au M05).
- La CI exécute `pre-commit run --all-files --show-diff-on-failure` avec un cache de `~/.cache/pre-commit` (E24).
- Les mises à jour des hooks passent par une MR dédiée, mensuelle (Renovate au M13).

---

### M01-E16 — Gitleaks : arrêter un secret avant qu'il parte

**Solution**

1. Installation vérifiée : [`fichiers/M01-E16/installer-gitleaks.sh`](fichiers/M01-E16/installer-gitleaks.sh) (téléchargement de l'archive et du fichier de sommes, `sha256sum -c`, `install -m 0755` dans `/usr/local/bin`).
   ```
   admin@adm01:~$ sudo ~/lab-scripts/installer-gitleaks.sh 8.30.1
   gitleaks_8.30.1_linux_x64.tar.gz: OK
   8.30.1
   ```
2. Historique complet :
   ```
   admin@adm01:~/medisphere$ gitleaks git --redact -v -f json -r /tmp/gitleaks-medisphere.json .
   admin@adm01:~/medisphere$ jq '.[] | {RuleID, File, Commit, Fingerprint}' /tmp/gitleaks-medisphere.json
   ```
   L'empreinte (*Fingerprint*) `commit:fichier:règle:ligne` identifie une détection de façon stable : c'est elle qu'on mettrait dans `.gitleaksignore`. Sur le dépôt du socle, un résultat typique est « no leaks found » ; une détection `generic-api-key` sur une ligne de documentation est un faux positif à examiner, pas à ignorer d'office.
3. `gitleaks dir --redact ~/.config/workbook` : les jetons GitLab (`gitlab-pat`) sont détectés ; le `PVE_TOKEN_SECRET=<UUID>` de `pve-api.env` peut l'être par la règle générique selon l'entropie, ou pas ; un mot de passe court et lisible ne l'est pas. Leçon : l'outil voit les formats connus, pas « les secrets ».
4. Couverture des règles par défaut (faux secrets générés) :

   | Faux secret | Règles par défaut | Avec `.gitleaks.toml` |
   |---|---|---|
   | `PVE_TOKEN_SECRET=<UUID>` | souvent `generic-api-key` (entropie), sans garantie | `proxmox-api-token` |
   | `Authorization: PVEAPIToken=wb-automation@pve!lab=<UUID>` | **non détecté** | `proxmox-api-token` |
   | `PrivateKey = <44 caractères base64>` | souvent `generic-api-key` (entropie), sans garantie ni nom parlant | `wireguard-private-key` |
   | `GITLAB_TOKEN=glpat-XXXX…` (20 caractères) | `gitlab-pat` | `gitlab-pat` |

   ```
   admin@adm01:~$ printf 'curl -H "Authorization: PVEAPIToken=wb-automation@pve!lab=%s"\n' "$(cat /proc/sys/kernel/random/uuid)" \
       | gitleaks stdin --no-banner --redact -v
   ```
5. Configuration de référence : [`fichiers/M01-E16/.gitleaks.toml`](fichiers/M01-E16/.gitleaks.toml) : `[extend] useDefault = true`, règle `proxmox-api-token` (les deux formats, l'UUID en groupe de capture `secretGroup = 1`, mots-clés `pveapitoken`, `pve_token_secret`), règle `wireguard-private-key`, et une seule exception, ciblée sur la règle Proxmox, pour l'UUID nul des exemples de documentation.
6. Politique d'exceptions (à reprendre dans CONTRIBUTING) :
   - une exception se justifie par écrit dans la MR, et Sophie (ou un Maintainer désigné) la valide ;
   - préférer, dans l'ordre : modifier l'exemple pour qu'il ne ressemble plus à un secret (`<UUID>`, `XXXX…`) ; une exception **ciblée** dans `.gitleaks.toml` (règle + motif précis, commentée) ; une empreinte dans `.gitleaksignore` pour un faux positif historique ; en dernier recours, `gitleaks:allow` sur une ligne de test ;
   - jamais d'exception sur un chemin entier : tout ce qui y arrivera plus tard sera invisible.
7. ```
   admin@adm01:~/medisphere$ printf 'PVEAPIToken=wb-automation@pve!lab=%s\n' "$(cat /proc/sys/kernel/random/uuid)" > test-fuite.txt
   admin@adm01:~/medisphere$ git add test-fuite.txt && git commit -m "test: fuite"
   Detect hardcoded secrets.................................................Failed
   RuleID:      proxmox-api-token
   admin@adm01:~/medisphere$ git restore --staged test-fuite.txt && rm test-fuite.txt
   ```
   Le hook lance `gitleaks git --pre-commit --staged` depuis la racine du dépôt : il lit `.gitleaks.toml` de la racine (ordre de priorité : `--config`, variable `GITLEAKS_CONFIG`, `GITLEAKS_CONFIG_TOML`, puis `<cible>/.gitleaks.toml`).
8. MR, fusion.

**Explications**
- Gitleaks applique des expressions régulières (plus un seuil d'entropie pour certaines règles) au contenu de `git log -p` (mode `git`), à des fichiers (mode `dir`) ou à l'entrée standard. Une détection est une **correspondance de format** : sans format reconnaissable, pas de détection. D'où les règles propres à l'entreprise.
- `--redact` remplace le secret par `REDACTED` dans la sortie et le rapport : un scan ne doit pas lui-même devenir une fuite.
- Par défaut `gitleaks git` lit toutes les références (`git log --all`) : un secret sur une branche oubliée ou une branche de suivi distante compte.

**Alternatives**
- TruffleHog : plus de détecteurs, vérification active de la validité des secrets trouvés (appel au service émetteur), plus lourd.
- Détection de secrets de GitLab (*Secret Detection* en CI, disponible dans tous les tiers ; *secret push protection* au push, Ultimate).
- Betterleaks, successeur annoncé par l'auteur de Gitleaks : à surveiller, pas encore la référence du workbook.

**Pièges classiques**
- Tester avec un vrai secret « juste pour voir » : il est dans l'historique du shell et peut-être dans un rapport.
- Regex écrite pour PCRE (avec `(?=…)`) : refusée par le moteur RE2 de Go.
- `keywords` en majuscules : le pré-filtre compare en minuscules, la règle ne se déclenche jamais.
- Utiliser le paquet Debian (8.16) : pas de sous-commande `git`/`dir`/`stdin`, syntaxe de configuration ancienne (`[allowlist]` au lieu de `[[allowlists]]`).

**En production chez MédiSphère**
- Même configuration en local (hook), en CI sur chaque MR (plage de commits de la MR, E24) et dans un scan complet hebdomadaire de tous les projets.
- Toute nouvelle forme de secret introduite par un module (jeton Proxmox d'un nouvel outil au M03-M05, secret NetBox au M06) ajoute sa règle au fichier de référence.

---

### M01-E17 — Un secret a été poussé : purge, rotation, communication

**Solution**

1. **Contenir** (noter l'heure à chaque étape) :
   ```
   admin@adm01:~/DevOpsPrivateCloud$ modules/01-git/ressources/M01-E17/fabriquer-depot.sh
   admin@adm01:~$ git clone git@git01.par1.medisphere.internal:formation/labo-fuite.git /tmp/fuite && cd /tmp/fuite
   admin@adm01:/tmp/fuite$ gitleaks git --redact -v .        # gitlab-pat dans config/collecte.env, commit « feat: configuration… »
   ```
   Révocation : *Settings > Access tokens* du projet, « collecte-medisphere », *Revoke* (ou `DELETE /projects/:id/access_tokens/:id` avec le jeton d'administration). Vérification sans réutiliser le secret : le jeton apparaît dans la liste des jetons inactifs (`GET /projects/:id/access_tokens?state=inactive`, `revoked: true`). Le mot de passe de base de test est signalé à Julien pour changement. On révoque **avant** de purger parce que la purge ne touche que GitLab : les clones déjà faits, les caches, une sauvegarde, la mémoire d'un poste compromis gardent le secret. La révocation est la seule action qui le rend inutile partout, et elle prend dix secondes.
2. **Évaluer** :
   ```
   admin@adm01:~$ install -d -m 700 ~/fuite-e17 && cd ~/fuite-e17
   admin@adm01:~/fuite-e17$ git clone --mirror git@git01.par1.medisphere.internal:formation/labo-fuite.git sauvegarde.git
   admin@adm01:~/fuite-e17$ cd sauvegarde.git
   admin@adm01:~/fuite-e17/sauvegarde.git$ git log --all --format='%h %ad %an %s' --date=iso -- config/collecte.env
   admin@adm01:~/fuite-e17/sauvegarde.git$ git for-each-ref --contains <commit-qui-ajoute-le-fichier>
   refs/heads/feat/export-csv
   refs/heads/main
   refs/merge-requests/1/head
   refs/tags/v0.1.0
   ```
   Accès : membres du projet (toi, Julien) et administrateurs. Usage du jeton : champ `last_used_at` dans la liste des jetons du projet ; sur `git01`, recherche des accès au projet par le compte « bot » du jeton :
   ```
   admin@git01:~$ sudo grep -h 'labo-fuite' /var/log/gitlab/gitlab-rails/production_json.log /var/log/gitlab/gitlab-rails/api_json.log | jq -c '{time, method, path, username, remote_ip}' | tail
   admin@git01:~$ sudo grep -h 'labo-fuite' /var/log/gitlab/gitlab-shell/gitlab-shell.log | tail
   ```
3. **Préparer** : la sauvegarde miroir est faite (dossier 700). Blobs à supprimer côté serveur, relevés **avant** réécriture :
   ```
   admin@adm01:~/fuite-e17/sauvegarde.git$ git rev-list --objects --all | grep ' config/collecte.env$' | cut -d' ' -f1 | sort -u > ../blobs.txt
   ```
   Choix : supprimer le fichier de tout l'historique (`--invert-paths`), parce qu'un fichier de configuration réel n'a **jamais** eu sa place dans le dépôt ; un remplacement de texte (`--replace-text`) se justifie quand le secret est au milieu d'un fichier légitime.
4. **Purger côté Git** :
   ```
   admin@adm01:~/fuite-e17$ sudo apt install -y git-filter-repo
   admin@adm01:~/fuite-e17$ git clone --mirror git@git01.par1.medisphere.internal:formation/labo-fuite.git purge.git && cd purge.git
   admin@adm01:~/fuite-e17/purge.git$ git filter-repo --sensitive-data-removal --invert-paths --path config/collecte.env
   NOTICE: Fetching all refs from origin to make sure we rewrite
           all history that may reference the sensitive data, …
   NOTE: First Changed Commit(s) is/are:
     <empreinte>
   NEXT STEPS FOR YOUR SENSITIVE DATA REMOVAL:
     * Force push the rewritten history to the server:
         git push --force --mirror origin
   admin@adm01:~/fuite-e17/purge.git$ gitleaks git --redact . ; git grep -I -c 'Collecte-2026' $(git rev-list --all)
   ```
   Lever l'interdiction de push forcé sur `main` (*Protected branches*, *Allowed to force push*), puis :
   ```
   admin@adm01:~/fuite-e17/purge.git$ git push --force --mirror origin
    + 1a2b3c4...5d6e7f8 main -> main (forced update)
    + …                 feat/export-csv -> feat/export-csv (forced update)
    + …                 v0.1.0 -> v0.1.0 (forced update)
    ! [remote rejected] refs/merge-requests/1/head -> refs/merge-requests/1/head (deny updating a hidden ref)
   ```
   Rétablir aussitôt l'interdiction. GitLab gère lui-même `refs/merge-requests/*` (et d'autres références internes) : un push ne peut pas les réécrire. ⚠️ À vérifier sur ta version : le libellé exact du refus.
   Variante sans `--mirror` : `git push --force origin 'refs/heads/*' 'refs/tags/*'` (les références internes ne sont alors même pas tentées).
5. **Purger côté GitLab** : *Settings > Repository > Repository maintenance > Remove blobs*, coller le contenu de `blobs.txt`, confirmer avec le chemin du projet ; attendre la fin ; puis *Settings > General > Advanced > Run housekeeping*, et enfin *Prune unreachable objects*. Les blobs disparaissent aussi des références internes (MR). La MR !1 : ses anciennes versions de diff sont stockées en base de GitLab et peuvent encore afficher le contenu supprimé ; la solution la plus sûre est de la **fermer et la supprimer** (Owner : *Edit > Delete*), puis de demander à Julien de la recréer depuis la branche réécrite. ⚠️ À vérifier sur ta version : ce que *Remove blobs* fait des diffs déjà stockés en base.
   Alternative serveur : *Redact text* avec la valeur du jeton et du mot de passe (le texte est remplacé par `***REMOVED***` dans tout l'historique), puis ménage et élagage. Elle évite la réécriture locale mais laisse le fichier (vidé de ses secrets) dans l'historique.
6. **Vérifier** :
   ```
   admin@adm01:~$ git clone --mirror git@git01.par1.medisphere.internal:formation/labo-fuite.git /tmp/verif.git
   admin@adm01:~$ gitleaks git --redact /tmp/verif.git ; git -C /tmp/verif.git grep -I -c 'Collecte-2026' $(git -C /tmp/verif.git rev-list --all)
   admin@adm01:~$ git -C /tmp/verif.git show-ref | grep -E 'v0.1.0|merge-requests'
   admin@adm01:~$ rm -rf /tmp/verif.git ~/fuite-e17 /tmp/fuite
   ```
   La suppression de `~/fuite-e17` détruit la sauvegarde miroir, qui contenait le secret.
7. **Prévenir** : MR de Julien (ou la tienne) qui ajoute `config/*.env` dans `.gitignore` et un `config/collecte.env.example` aux valeurs vides ; le script lit la configuration depuis l'environnement. Julien et toi supprimez vos clones et reclonez (un `git pull` ramènerait l'ancien historique en le fusionnant au nouveau).
8. **Communiquer** : modèle complet dans [`fichiers/M01-E17/communication-SEC-227.md`](fichiers/M01-E17/communication-SEC-227.md).

**Explications**
- Un secret poussé est **compromis** : on ne sait pas qui l'a lu ou copié. La purge réduit l'exposition future ; seule la rotation supprime le risque.
- `git filter-repo` réécrit tous les commits concernés (nouvelles empreintes) ; `--sensitive-data-removal` (2.47+) récupère d'abord **toutes** les références de l'origine (y compris celles de MR) pour ne rien oublier, puis indique les « premiers commits modifiés », utiles aux administrateurs du serveur et aux collègues qui ont des clones.
- Côté GitLab, un objet supprimé de toutes les références reste sur le disque jusqu'au ménage (*housekeeping*) et à l'élagage (*prune*), et les références internes (MR, *keep-around*) le maintiennent accessible : d'où les outils de *Repository maintenance*.
- Pourquoi garder `v0.1.0` : supprimer l'étiquette aurait été plus simple, mais elle désigne une version livrée. On la réécrit (même nom, nouveau commit) et on l'annonce : la version publiée n'a plus la même empreinte.

**Alternatives**
- Si le dépôt n'avait jamais été cloné par personne d'autre et ne contenait que quelques commits : supprimer et recréer le projet. Rarement possible en vrai.
- BFG Repo-Cleaner : ancien outil Java de purge, remplacé par `git filter-repo` (recommandé par la documentation de Git).
- *Redact text* seul, côté serveur : moins d'étapes, mais pas d'historique local à vérifier avant publication.

**Pièges classiques**
- Purger d'abord, révoquer ensuite (ou jamais) : le secret reste valide dans tous les clones existants.
- « Supprimer le fichier dans un nouveau commit » : c'est ce qu'avait fait Julien ; ça ne retire rien.
- Oublier les étiquettes, les autres branches, les références de MR : `git log -- fichier` sur `main` seul ne montre pas tout.
- Laisser le push forcé autorisé sur `main` après l'opération.
- Garder la sauvegarde miroir indéfiniment : elle est elle-même une copie du secret.
- Ne pas prévenir les détenteurs de clones : un `git push` depuis un ancien clone réintroduit tout l'historique purgé.

**En production chez MédiSphère**
- Runbook « Secret exposé dans un dépôt » (à créer dans `docs/socle/runbooks/`) suivant exactement cet ordre, avec Sophie comme décisionnaire.
- Détection en amont : pre-commit + Gitleaks (E15, E16), Gitleaks en CI sur chaque MR (E24), hook serveur (E26).
- Le compte rendu alimente le registre des incidents de sécurité (ISO 27001, exigence de traçabilité HDS) ; un incident touchant des données de santé suivrait en plus la procédure de notification RGPD.

---

### M01-E18 — Worktrees : un correctif urgent sans abandonner son travail

**Solution**

1. État de départ :
   ```
   admin@adm01:~/src/labo-worktrees$ git status --short
   MM worktrees/capacite.md
   ?? worktrees/notes-brouillon.md
   ```
   `MM` : une partie indexée **et** une partie non indexée du même fichier. `git stash` met les deux de côté (le non suivi seulement avec `-u`) ; `git stash pop` **sans `--index`** restaure tout comme non indexé : la frontière soigneusement choisie disparaît. Un commit « wip » mélange aussi les deux et finit souvent poussé par erreur.
2. Worktree du correctif :
   ```
   admin@adm01:~/src/labo-worktrees$ git fetch
   admin@adm01:~/src/labo-worktrees$ git worktree add -b e18/correctif-seuil ../labo-worktrees-correctif origin/main
   admin@adm01:~/src/labo-worktrees$ git worktree list
   /home/admin/src/labo-worktrees            1a2b3c4 [e18/rapport-capacite]
   /home/admin/src/labo-worktrees-correctif  9f8e7d6 [e18/correctif-seuil]
   admin@adm01:~/src/labo-worktrees$ cat ../labo-worktrees-correctif/.git
   gitdir: /home/admin/src/labo-worktrees/.git/worktrees/labo-worktrees-correctif
   ```
   `.git/worktrees/<nom>/` contient le `HEAD`, l'index et les journaux propres au worktree ; objets, références (branches, étiquettes) et configuration sont **partagés**.
3. Diagnostic et correctif :
   ```
   admin@adm01:~/src/labo-worktrees-correctif$ printf '1001 %s\n2011 %s\n' "$(date -d '-3 hours' +%s)" "$(date -d '-30 hours' +%s)" | worktrees/verifier-sauvegardes.sh
   ALERTE : VM 1001, dernière sauvegarde il y a 180 h (seuil : 26 h)
   ALERTE : VM 2011, dernière sauvegarde il y a 1800 h (seuil : 26 h)
   ```
   « 180 h » pour une sauvegarde de 3 h : l'âge est calculé en **minutes** (`/ 60`) puis comparé à un seuil en heures. Toute sauvegarde de plus de 26 **minutes** déclenche l'alerte : à 2 h 30, la sauvegarde de 1 h a 90 minutes. Correctif : diviser par 3600. Version corrigée : [`fichiers/M01-E18/verifier-sauvegardes.sh`](fichiers/M01-E18/verifier-sauvegardes.sh).
   ```
   admin@adm01:~/src/labo-worktrees-correctif$ printf '1001 %s\n2011 %s\n' "$(date -d '-3 hours' +%s)" "$(date -d '-30 hours' +%s)" | worktrees/verifier-sauvegardes.sh; echo "code=$?"
   ALERTE : VM 2011, dernière sauvegarde il y a 30 h (seuil : 26 h)
   code=1
   admin@adm01:~/src/labo-worktrees-correctif$ git commit -am "fix(supervision): calculer l'âge des sauvegardes en heures"
   admin@adm01:~/src/labo-worktrees-correctif$ git push -u origin e18/correctif-seuil -o merge_request.create -o merge_request.target=main
   ```
   MR fusionnée dans `formation/git-labo`.
4. Dans `~/src/labo-worktrees`, `git status --short` affiche toujours `MM` et `??`. `git log --oneline -1 e18/correctif-seuil` y fonctionne : la branche et son commit sont dans le dépôt partagé.
5. ```
   admin@adm01:~/src/labo-worktrees-correctif$ git switch e18/rapport-capacite
   fatal: 'e18/rapport-capacite' is already used by worktree at '/home/admin/src/labo-worktrees'
   ```
   Deux worktrees sur la même branche se marcheraient dessus : un commit dans l'un déplacerait la branche sous les pieds de l'autre (index et fichiers devenus incohérents).
6. Rangement :
   ```
   admin@adm01:~/src/labo-worktrees$ git worktree remove ../labo-worktrees-correctif
   admin@adm01:~/src/labo-worktrees$ git fetch --prune && git branch -d e18/correctif-seuil
   admin@adm01:~/src/labo-worktrees$ git worktree prune --dry-run -v      # rien à nettoyer
   ```
   (`git branch -d` peut refuser si la fusion par commit de fusion n'est pas encore connue localement : le `fetch` l'apporte ; sinon `-D` après avoir vérifié la MR.) Après un `rm -rf` du dossier : `git worktree prune`.
7. Situations : correctif urgent pendant un travail en cours ; relire ou tester la MR d'un collègue sans toucher à sa propre copie ; garder une longue compilation ou une suite de tests qui tourne sur une version pendant qu'on travaille sur une autre ; comparer deux versions côte à côte. Limites : les sous-modules sont mal gérés, les hooks et la configuration sont partagés (un `pre-commit install` vaut pour tous), certains IDE se perdent.

**Explications**
- Un worktree est une copie de travail supplémentaire attachée au même dépôt : pas de second clone, pas de second téléchargement, et les commits faits dans l'un sont immédiatement visibles dans l'autre. Chaque worktree a son propre `HEAD` et son propre index, ce qui préserve exactement l'état de chacun.
- Le check vérifie, dans le journal des références de `HEAD` du worktree principal, qu'aucun `checkout: moving from e18/rapport-capacite to …` n'a eu lieu après la préparation : c'est la trace d'un changement de branche « sur place ».

**Alternatives**
- `git stash push --staged` / `git stash pop --index` : conserve la frontière index/copie de travail si on y pense ; fragile en cas de conflit au `pop`.
- Un second clone : fonctionne, mais double l'espace et les `fetch`, et les branches locales ne sont pas partagées.
- Corriger dans l'interface web de GitLab : acceptable pour une ligne, mais sans test local.

**Pièges classiques**
- Créer le worktree **dans** le dossier du dépôt : il apparaît comme non suivi.
- Partir de `main` local périmé au lieu de `origin/main`.
- Supprimer le dossier à la main et oublier `git worktree prune` : Git croit la branche toujours extraite ailleurs.
- Corriger sans reproduire d'abord : impossible de prouver que le correctif corrige.

**En production chez MédiSphère**
- Le correctif urgent suit le même chemin qu'un autre changement (MR, revue rapide, pipeline) : l'urgence raccourcit les délais, pas les contrôles.
- Le défaut (unité mal interprétée) aurait été arrêté par un test automatisé (`bats`, M02) avec exactement le jeu de test de l'énoncé.

---

### M01-E19 — Cherry-pick et rétroportage vers une branche de maintenance

**Solution**

1. Inventaire :
   ```
   admin@adm01:~/src/git-labo$ git fetch --prune
   admin@adm01:~/src/git-labo$ git log --oneline --reverse origin/e19/1.x..origin/main -- cherry/
   b1c2d3e feat(cherry): option --pool pour sauvegarder tout un pool
   ad63f16 fix(cherry): refuser un VMID hors des plages du workbook
   4e5f6a7 refactor(cherry): renommer verifier_vmid en controler_vmid
   7e2041f fix(cherry): message clair quand vzdump échoue
   9a8b7c6 feat(cherry): journaliser chaque sauvegarde dans syslog
   ```
   À prendre : les deux `fix`. À écarter : les deux `feat` (fonctionnalités, interdit sur une branche de maintenance) et le `refactor` : inoffensif à l'exécution, il change un nom de fonction que les scripts de l'équipe MédiAgenda appellent (rupture pour eux).
2. Rétroportage :
   ```
   admin@adm01:~/src/git-labo$ git switch -c e19/retroportage-1.x origin/e19/1.x
   admin@adm01:~/src/git-labo$ git cherry-pick -x ad63f16
   admin@adm01:~/src/git-labo$ git cherry-pick -x 7e2041f
   CONFLICT (content): Merge conflict in cherry/sauvegarde-vm.sh
   ```
   Le correctif modifie la ligne `vzdump` ; la ligne juste au-dessus (`controler_vmid "$vmid"`) a été renommée par la refactorisation, absente de 1.x : lignes adjacentes modifiées des deux côtés, donc conflit. Résolution : garder `verifier_vmid "$vmid"` et prendre la nouvelle ligne `vzdump … || { echo "échec de vzdump…" ; exit 1; }`. Puis `git add cherry/sauvegarde-vm.sh && git cherry-pick --continue` (le message garde `(cherry picked from commit 7e2041f…)`). Version finale : [`fichiers/M01-E19/sauvegarde-vm.sh`](fichiers/M01-E19/sauvegarde-vm.sh).
3. Tests :
   ```
   admin@adm01:~/src/git-labo$ bash -n cherry/sauvegarde-vm.sh && shellcheck cherry/sauvegarde-vm.sh
   admin@adm01:~/src/git-labo$ bash cherry/sauvegarde-vm.sh 42; echo "code=$?"
   VMID hors des plages du workbook : 42
   code=2
   ```
4. ```
   admin@adm01:~/src/git-labo$ git cherry -v origin/main HEAD
   + ba924b5 docs(cherry): règles de la branche de maintenance 1.x
   - 159f26a fix(cherry): refuser un VMID hors des plages du workbook
   + 3701aff fix(cherry): message clair quand vzdump échoue
   ```
   `-` : un commit de même *patch-id* (même diff) existe sur `main` : le premier correctif s'est appliqué tel quel. `+` pour le second : en résolvant le conflit, son diff a changé (`verifier_vmid` dans le contexte), donc son *patch-id* aussi. `git cherry` ne voit pas l'équivalence ; la mention `-x` est là pour la tracer.
5. MR de `e19/retroportage-1.x` **vers `e19/1.x`** (changer la cible proposée par défaut), fusion.
6. Pourquoi le cherry-pick : fusionner `main` dans `1.x` importerait tout (fonctionnalités, refactorisation) ; rebaser `1.x` sur `main` la transformerait en `main`. Règle proposée : un correctif se fait **d'abord sur `main`** (par MR), puis se rétroporte par `cherry-pick -x` vers les branches de maintenance encore supportées, par une MR dédiée ; le responsable de la branche (ici Julien) décide de ce qui est rétroporté. semantic-release (E25) reconnaît par défaut les branches de maintenance nommées `N.x` ou `N.N.x` et y publie des versions de correctif dans la plage de cette branche (1.x.y) ; le nom `e19/1.x` du bac à sable ne correspondrait pas à ce motif.

**Explications**
- `cherry-pick` calcule le diff entre un commit et son parent, puis l'applique par fusion à trois versions sur la branche courante : il dépend du **contexte** autour des lignes modifiées.
- `-x` ajoute la ligne `(cherry picked from commit <empreinte>)` au message : la trace survit au changement d'empreinte et permet, des mois plus tard, de savoir d'où vient un correctif.

**Alternatives**
- Corriger d'abord sur la branche la plus ancienne supportée, puis fusionner vers le haut (`1.x` → `main`) : modèle de certains projets (« fusion vers l'amont »). Il évite les doublons, mais suppose que les branches restent fusionnables, ce qui n'est pas le cas après une refactorisation.
- `git format-patch`/`git am` : même principe que le cherry-pick, entre dépôts distincts.

**Pièges classiques**
- Rétroporter la refactorisation « pour que le correctif passe sans conflit » : rupture pour les utilisateurs de la 1.x.
- Fusionner la MR dans `main` au lieu de `e19/1.x` (cible par défaut).
- Oublier `-x` : plus aucun lien entre les deux commits.
- Rétroporter dans le désordre : le second correctif peut dépendre du premier.

**En production chez MédiSphère**
- Les branches de maintenance sont protégées comme `main` et ne reçoivent que des MR de rétroportage.
- Une étiquette de suivi (*label* GitLab « à rétroporter 1.x ») sur la MR d'origine évite les oublis.

---

### M01-E20 — Jetons et clés : personnels, de projet, de déploiement

**Solution**

1. Tableau des identifiants :

   | Identifiant | Propriétaire | Portées / rôle | Durée | Préfixe | Usage dans notre forge |
   |---|---|---|---|---|---|
   | Jeton d'accès personnel | un humain | portées (`api`, `read_api`, `read_repository`, `write_repository`…), droits de l'humain | 365 j max. | `glpat-` | checks (`read_api`), scripts d'administration (`api`) |
   | Jeton d'emprunt d'identité | créé par un admin pour un compte | portées choisies, droits du compte | obligatoire | `glpat-` | scripts de `ressources/` (personnages) |
   | Jeton d'accès de projet / de groupe | utilisateur « bot » du projet / groupe | rôle + portées, limité au projet / groupe | obligatoire | `glpat-` | `bot-release` (E25), accès machine à un projet |
   | Clé de déploiement | projet(s) | lecture (ou écriture) Git en SSH | sans expiration côté clé SSH (expiration possible à la déclaration) | — | serveur qui clone un dépôt |
   | Jeton de déploiement | projet / groupe | `read_repository`, registres | expiration facultative | `gldt-` | registres de paquets et de conteneurs (M13) |
   | Clé SSH d'utilisateur | un humain | ses droits, en Git SSH | expiration facultative | — | travail quotidien |
   | Jeton de runner | runner | exécuter des jobs | selon l'instance | `glrt-` | `runner01` (E23) |
   | Jeton de job CI | un job | droits limités de l'utilisateur qui lance le pipeline, durée du job | durée du job | `glcbt-` | appels API depuis la CI |

2. Audit :
   ```
   admin@adm01:~$ api() { curl -s -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(<~/.config/workbook/gitlab-admin.token)") "https://git01.par1.medisphere.internal/api/v4/$1"; }
   admin@adm01:~$ uid=$(api user | jq .id)
   admin@adm01:~$ api "personal_access_tokens?user_id=$uid&state=active" \
       | jq -r '.[] | [.id, .name, (.scopes|join(",")), .expires_at, .last_used_at] | @tsv'
   ```
   Révoque ce qui ne sert plus (`DELETE /personal_access_tokens/<id>` ou l'interface).
3. Écriture avec le jeton des checks :
   ```
   admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' -X POST \
       -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(<~/.config/workbook/gitlab-checks.token)") \
       "https://git01.par1.medisphere.internal/api/v4/projects/formation%2Fgit-labo/repository/branches?branch=essai&ref=main"
   403
   ```
   Réponse `insufficient_scope` : la portée `read_api` n'autorise que les requêtes de lecture.
4. Rotation : [`fichiers/M01-E20/gitlab-rotation-jeton.sh`](fichiers/M01-E20/gitlab-rotation-jeton.sh), copié dans `~/lab-scripts/`.
   ```
   admin@adm01:~$ ~/lab-scripts/gitlab-rotation-jeton.sh ~/.config/workbook/gitlab-admin.token 90
   Nouveau jeton « workbook-admin » (id 12), portées api, expire le 2027-01-02
   ```
   L'ancien jeton répond `401` (le garder une minute dans une variable pour ce test, puis `unset`). Si on relançait une rotation **avec l'ancien jeton**, GitLab y verrait une réutilisation et révoquerait toute la famille, y compris le nouveau.
5. Clé SSH : *Préférences > Clés SSH*, retirer puis redéclarer la même clé publique avec une date d'expiration et l'usage *Authentication*. ⚠️ À vérifier sur ta version : l'impossibilité de modifier la date d'une clé existante.
6. Clé de déploiement :
   ```
   admin@adm01:~$ ssh-keygen -t ed25519 -N '' -C "deploy labo-lecture adm01" -f ~/.ssh/id_ed25519_deploy_gitlabo
   ```
   Déclaration dans `formation/git-labo` > *Settings > Repository > Deploy keys*, titre `labo-lecture`, **sans** « Grant write permissions ». Test :
   ```
   admin@adm01:~$ GIT_SSH_COMMAND='ssh -i ~/.ssh/id_ed25519_deploy_gitlabo -o IdentitiesOnly=yes' \
       git clone git@git01.par1.medisphere.internal:formation/git-labo.git /tmp/labo-deploy
   admin@adm01:/tmp/labo-deploy$ git commit --allow-empty -m "test: écriture" && \
       GIT_SSH_COMMAND='ssh -i ~/.ssh/id_ed25519_deploy_gitlabo -o IdentitiesOnly=yes' git push
   remote: … This deploy key does not have write access to this project.
   ```
   Sans phrase de passe, parce qu'elle sert à une machine sans humain pour la saisir : compensée par les droits du fichier (600), la lecture seule et le périmètre d'un seul projet. ⚠️ Libellé exact du refus à vérifier sur ta version.
7. Jeton de projet `lecture-labo` (*Settings > Access tokens*, Reporter, `read_repository`, 7 jours). Clone sans exposer le jeton :
   ```
   admin@adm01:~$ install -m 600 /dev/null /tmp/jeton-labo && $EDITOR /tmp/jeton-labo      # coller le jeton
   admin@adm01:~$ printf '#!/bin/sh\ncat /tmp/jeton-labo\n' > /tmp/askpass && chmod 700 /tmp/askpass
   admin@adm01:~$ GIT_ASKPASS=/tmp/askpass git -c credential.helper= clone \
       https://jeton@git01.par1.medisphere.internal/formation/git-labo.git /tmp/labo-https
   admin@adm01:~$ git -C /tmp/labo-https remote get-url origin     # https://jeton@… : nom d'utilisateur, pas de secret
   ```
   Le projet a un nouveau membre « bot » (`project_<id>_bot_…`). Après révocation, le même clone échoue (`HTTP Basic: Access denied`). Nettoyage : `rm -rf /tmp/labo-https /tmp/labo-deploy /tmp/jeton-labo /tmp/askpass`.
8. Registre : [`fichiers/M01-E20/registre-secrets.md`](fichiers/M01-E20/registre-secrets.md), par MR.

**Explications**
- Un jeton personnel porte **les droits de son propriétaire** sur tout ce qu'il voit : celui d'un administrateur avec `api` peut tout faire. Pour une machine, on veut un identifiant attaché au **projet** (jeton de projet, clé de déploiement), qui survit au départ d'une personne et ne voit que ce projet.
- La rotation par l'API garde nom et portées, et crée une « famille » de jetons : c'est ce qui permet la détection de réutilisation.
- Le registre est un document d'exploitation (où, qui, comment remplacer), pas un coffre : il ne contient aucune valeur.

**Alternatives**
- Comptes de service (*service accounts*) : comptes non humains avec leurs propres jetons, gérés au niveau du groupe ou de l'instance (disponibilité selon l'édition, à vérifier) ; plus souples que les jetons de projet pour un outil qui touche plusieurs projets.
- Coffre de secrets (Vault/OpenBao au M25) qui délivre des jetons à durée courte : le registre devient en grande partie automatique.

**Pièges classiques**
- Rotation sans `expires_at` : le nouveau jeton expire au bout d'une semaine, et les checks tombent en panne le samedi suivant.
- Jeton dans l'URL du dépôt (`https://user:glpat-…@…`) : il reste dans `.git/config`, dans l'historique du shell et dans les journaux de proxy.
- Clé de déploiement en écriture « pour plus tard » : une machine compromise peut alors réécrire le dépôt.
- Tester la clé de déploiement sans `IdentitiesOnly=yes` : l'agent propose ta clé personnelle, le clone marche, le test ne prouve rien.

**En production chez MédiSphère**
- Politique d'instance : durée maximale des jetons réduite (90 jours pour les jetons d'administration), revue trimestrielle du registre, alertes d'expiration (sans SMTP dans le lab : un job planifié qui interroge l'API).
- Les jetons des pipelines vivent en variables CI protégées et masquées, puis dans Vault (M25).

---

### M01-E21 — Revue de la merge request d'un stagiaire

**Solution**

1. Préparation et lecture :
   ```
   admin@adm01:~/DevOpsPrivateCloud$ modules/01-git/ressources/M01-E21/creer-mr-lucas.sh
   Lucas a ouvert la MR !4 dans plateforme/medisphere. À toi de la relire (ticket PLAT-231).
   ```
2. Outils en local :
   ```
   admin@adm01:~/medisphere$ git fetch origin merge-requests/4/head:revue-lucas
   admin@adm01:~/medisphere$ git log --format='%h %an <%ae> %s' origin/main..revue-lucas
   admin@adm01:~/medisphere$ git diff --stat origin/main...revue-lucas
   admin@adm01:~/medisphere$ git ls-tree -l revue-lucas -- scripts/ docs/socle/certificats.md docs/socle/capture-certificats.png
   admin@adm01:~/medisphere$ git show revue-lucas:docs/socle/certificats.md | file -
   /dev/stdin: ASCII text, with CRLF line terminators
   admin@adm01:~/medisphere$ git show revue-lucas:scripts/verifier-certificats.sh | shellcheck -
   admin@adm01:~/medisphere$ gitleaks git --redact --log-opts="origin/main..revue-lucas" .
   admin@adm01:~/medisphere$ pre-commit run --from-ref origin/main --to-ref revue-lucas
   ```
   (Le dernier exige d'être sur une copie de travail qui contient les fichiers : `git switch revue-lucas` le temps de l'analyse, puis retour sur `main` et `git branch -D revue-lucas`.)
3. et 4. Grille complète des 18 défauts, gravités, raisons, et commentaire de synthèse modèle : [`fichiers/M01-E21/grille-revue.md`](fichiers/M01-E21/grille-revue.md). Exemple de commentaire sur une ligne, avec suggestion :
   > **bloquant** — `curl -k` désactive la vérification du certificat : le jeton part vers un serveur qu'on n'authentifie pas. La CA provisoire est installée sur `adm01`, le nom de `git01` est couvert par le certificat :
   > ````
   > ```suggestion:-0+0
   >     curl -sSf -X POST -H @<(printf 'PRIVATE-TOKEN: %s\n' "$GITLAB_TOKEN") --data-urlencode "title=Certificat de $h : expiration dans $jours jours" "$GITLAB_URL/api/v4/projects/plateforme%2Fmedisphere/issues"
   > ```
   > ````
5. L'action qui n'attend pas : le jeton écrit dans le script est sur le serveur (branche, `refs/merge-requests/4/head`, diffs de la MR). Dans la réalité : **révocation immédiate** par son propriétaire (Lucas, ou un administrateur s'il n'est pas joignable), information de Sophie, puis traitement selon E17. La correction de la MR vient après. Ici le jeton est factice : écris ce que tu aurais fait. Les contrôles de E15/E16 auraient arrêté le jeton, la fin de ligne CRLF, l'image de 700 Ko et les messages de commit ; ils n'ont rien vu parce que les commits ont été créés **par l'API** (aucun hook local ne tourne), exactement comme avec un `--no-verify` ou un clone sans `pre-commit install`. D'où la CI obligatoire (E24) et les hooks côté serveur (E26).
6. Barème : un point par défaut de la grille trouvé et correctement qualifié ; les trois bloquants (jeton, `-k`, matrice des flux) et le défaut 8 (échec silencieux) sont indispensables. 14/18 : revue solide ; 18/18 : niveau relecteur senior.

**Explications**
- Une revue utile classe ses remarques : l'auteur sait ce qui empêche la fusion et ce qui est une préférence. Elle explique le **pourquoi** (Lucas apprend) et propose une solution quand c'est possible (les suggestions s'appliquent en un clic).
- Les défauts les plus graves ne sont pas toujours dans le code : un flux réseau trop large dans la matrice ou une adresse personnelle dans les commits ont des conséquences d'exploitation et d'audit.
- La synthèse donne une décision claire : « changements demandés », pas une liste de remarques sans conclusion.

**Alternatives**
- Revue en binôme (appel vidéo, écran partagé) pour une première MR de stagiaire, puis compte rendu écrit dans la MR : plus humain, aussi traçable.
- Fermer la MR et en demander une nouvelle, plus petite : justifié ici, la MR mélange trois sujets (script, documentation, matrice des flux).

**Pièges classiques**
- Ne relire que le script et passer à côté de la matrice des flux, de l'image et des métadonnées des commits.
- Corriger soi-même la branche de Lucas : il n'apprend rien, et la responsabilité du changement devient floue.
- Trente commentaires « détail » qui noient les trois bloquants.
- Ton condescendant ou ironique : la revue est publique et durable.

**En production chez MédiSphère**
- Un stagiaire a un parrain (ici toi) qui relit ses premières MR ; les autres relecteurs interviennent après.
- Une MR qui touche la sécurité (secret, flux, droits) demande l'avis de Sophie (CONTRIBUTING, E22).

---

### M01-E22 — Rédiger le CONTRIBUTING et le modèle de MR de l'équipe

**Solution**

Fichiers de référence : [`fichiers/M01-E22/CONTRIBUTING.md`](fichiers/M01-E22/CONTRIBUTING.md) et [`fichiers/M01-E22/.gitlab/merge_request_templates/Default.md`](fichiers/M01-E22/.gitlab/merge_request_templates/Default.md). Ils sont copiés tels quels dans chaque projet `plateforme/*` (M02 et suivants) ; le lien `helpUrl` de `commitlint.config.mjs` pointe vers la section « 3. Messages de commit ».

Livraison : branche `docs/contributing`, MR dont la description reprend le modèle, fusion. Vérification du modèle : une MR brouillon de test depuis une branche vide est préremplie (le fichier `Default.md` est lu sur la branche par défaut), puis fermée et sa branche supprimée.

**Grille d'auto-évaluation (15 points)**

| # | Critère | Point |
|---|---|---|
| 1 | Préparation du poste : identité, clé SSH avec expiration, outils, `pre-commit install` | 1 |
| 2 | Branches : `main` protégée, nommage `type/description`, durée de vie courte | 1 |
| 3 | Messages : Conventional Commits, exemples, tableau type → effet sur la version | 1 |
| 4 | MR : brouillon, titre conventionnel (squash), description par le modèle, taille | 1 |
| 5 | Mise à jour d'une branche par rebase et `--force-with-lease` | 1 |
| 6 | Revue : approbation exigée **et** mention que CE ne la fait pas respecter, compensation | 1 |
| 7 | Revue : gravités, délai, qui résout un fil | 1 |
| 8 | Fusion : méthode semi-linéaire, pipeline, qui fusionne, suppression de la branche | 1 |
| 9 | Secrets : jamais dans un dépôt, où ils vivent, Gitleaks et politique d'exceptions | 1 |
| 10 | Fuite : révoquer d'abord, prévenir Sophie, procédure de purge (cohérent avec E17) | 1 |
| 11 | Branches de maintenance et `cherry-pick -x` | 1 |
| 12 | Interdits explicites (`--no-verify`, push sur `main`, étiquettes manuelles) | 1 |
| 13 | Modèle de MR : « comment c'est vérifié » avec commandes et résultats | 1 |
| 14 | Modèle de MR : impacts (sécurité, matrice des flux, inventaire, sauvegarde, rupture) et retour arrière | 1 |
| 15 | Forme : moins de 200 lignes, chaque règle avec sa raison, contacts | 1 |

**Explications**
- Un CONTRIBUTING sert le premier jour d'un nouveau venu et tranche les débats ensuite. Il reste court parce qu'il renvoie aux outils (les hooks et la CI appliquent la plupart des règles) et à la documentation (fiche de la forge, runbooks).
- Le modèle de MR est un outil de **revue** : la section « comment c'est vérifié » oblige l'auteur à tester et permet au relecteur de refaire le test ; la liste d'impacts transforme les oublis fréquents (matrice des flux, inventaire) en cases à cocher.
- `Default.md` est lu par GitLab CE dans `.gitlab/merge_request_templates/` de la branche par défaut ; le modèle défini dans les réglages du projet (prioritaire) est Premium.

**Alternatives**
- Plusieurs modèles (`Correctif.md`, `Fonctionnalite.md`, `Securite.md`) choisis dans une liste : plus précis, plus de maintenance.
- CONTRIBUTING au niveau du groupe (projet de documentation commun) avec un lien depuis chaque dépôt : une seule source, mais moins visible au moment du clone.

**Pièges classiques**
- Recopier la documentation de Git ou de GitLab : personne ne lit, et elle vieillit mal.
- Une règle sans raison (« pas de merge de `main` dans les branches ») : elle sera contournée à la première difficulté.
- Promettre ce que l'outil ne fait pas (« deux approbations obligatoires ») sans dire que c'est une règle humaine.
- Oublier les personnes externes (InfoGér) : droits limités, mêmes règles.

**En production chez MédiSphère**
- Le CONTRIBUTING est versionné, revu comme du code, et sa mise à jour accompagne chaque décision structurante (ADR, E33).
- Les nouveaux arrivants font une première MR qui corrige ou précise le CONTRIBUTING : c'est le meilleur test de sa clarté.
