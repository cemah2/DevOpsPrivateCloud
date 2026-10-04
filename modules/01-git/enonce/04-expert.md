# Module 01 — Palier 4 : Expert

La forge tourne : `git01` sert l'équipe, `runner01` fait passer les pipelines, les versions sortent toutes seules, les sauvegardes partent vers PAR2. Claire Morel prévient : « La forge est devenue un service critique. Si elle tombe, plus personne ne livre rien, et l'audit HDS demandera comment on l'a remise sur pied. Nadia te met en astreinte d'entraînement sur la forge, et Karim a des questions sur les entrailles de Git. » Ce palier est celui des incidents et du « sous le capot » : sept pannes de forge et de dépôt, une astreinte où elles se combinent, puis la bisection d'une régression, l'anatomie d'un gros dépôt et des questions d'entretien. La méthode est celle du module 00 : observer avant d'agir, formuler une hypothèse, la tester par la mesure la moins invasive, corriger à la racine, prévenir la récidive. Avec une règle de plus, propre à Git : **on ne détruit jamais une copie de travail qu'on n'a pas sauvegardée.**

## Règles du jeu des pannes (M01-E36 à M01-E43)

- Les pannes s'injectent **depuis `adm01`**, à la racine de ta copie du workbook :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ lab/bin/break 01 36
  ```
  Le script tire une variante au hasard et n'affiche que le **symptôme**, comme un ticket. Chaque panne a 3 ou 4 variantes : refais l'exercice jusqu'à les avoir toutes rencontrées (`--variante N` force une variante, sans dire laquelle est laquelle).
- **Avant d'injecter**, lance le contrôle de l'exercice (`lab/bin/check 01 36`) : il doit être vert. Exception : E41 et E42 fabriquent eux-mêmes le dépôt de Lucas à l'injection ; leur contrôle n'a de sens qu'après.
- **Ne lis pas** les scripts de `corrige/pannes/`, ni `/var/lib/workbook/` sur `git01` et `runner01`, ni `~/.local/state/workbook/` sur `adm01` : ils contiennent la cause.
- Une seule panne active à la fois par exercice. Si tu abandonnes : `lab/bin/break 01 36 --annuler` remet l'état sain (filet de sécurité, pas un correctif : compte l'exercice comme non réussi).
- Les pannes agissent sur `git01`, `runner01`, sur GitLab par l'API (avec ton jeton d'administration, `WB_GITLAB_ADMIN_TOKEN_FILE`), et sur `adm01` : configuration de `~/medisphere`, `~/.ssh/config` et `~/.ssh/known_hosts` (sauvegardés avant modification), dépôts d'exercice de `~/src`. Elles ne suppriment aucun projet, ne lancent jamais `gitlab-ctl reconfigure` et ne détruisent aucune donnée.
- Ton **jeton d'administration** doit être valide (il expire au plus tard 90 jours après sa création, M01-E05) : s'il a expiré, les injections échouent proprement. Renouvelle-le d'abord.
- N'injecte pas pendant qu'un pipeline tourne : certaines variantes redémarrent des services.
- **Tiens un journal de diagnostic** pour chaque panne, comme au module 00, dans `docs/socle/journal/` de ton clone `~/medisphere` : heure, hypothèse, commande, résultat observé, conclusion. Tu le publieras par MR (le dépôt est maintenant sur la forge). Ce journal alimente le post-mortem de M01-E43.
- Le **temps cible** est indicatif. Le dépasser n'est pas un échec ; corriger sans comprendre en est un.

> ⚠️ **Accès de secours** : la forge a plusieurs portes, et une panne n'en ferme généralement qu'une. L'administration de `git01` passe par l'alias SSH `git01` (compte `admin`, adresse IP), qui ne dépend ni de GitLab, ni du DNS, ni du compte `git`. Si SSH tombe aussi, il reste la console de la VM (`qm terminal 1004` sur `pve01`) et l'agent QEMU. Pour le code, un clone en HTTPS avec un jeton personnel (`read_repository`/`write_repository`) contourne une panne SSH. Repère ces chemins **avant** d'en avoir besoin.

---

### M01-E36 — Panne : `git push` est refusé  `BF` `★★`

> **Ticket INC-2781** — *De : Karim Benali*
> Tu m'as dit ce matin que tu ne pouvais plus pousser ta branche de travail sur `plateforme/medisphere` depuis `~/medisphere` : `git push` est refusé, alors que `git fetch` fonctionne. Je ne peux pas tester de mon poste avant ce soir. Trouve la cause, corrige, et dis-moi si d'autres personnes sont touchées.

**Objectifs pédagogiques**
- Lire un refus de push et attribuer le message à son émetteur : client Git, serveur SSH, GitLab (contrôles d'accès), hooks côté serveur.
- Suivre le trajet d'un push : configuration du dépôt local, transport, contrôles de GitLab sur le projet et la référence, hooks globaux de Gitaly.
- Distinguer une panne qui touche une personne, un projet ou toute la forge.

**Prérequis** : M01-E06, M01-E11, M01-E26 ; `lab/bin/check 01 36` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Injection** : `lab/bin/break 01 36` (4 variantes). Le script vérifie l'effet par une vraie poussée d'une branche jetable, qu'il supprime si elle passe.

**Travail demandé**
1. Reproduis le symptôme avec une branche de travail réelle (`git switch -c fix/essai-e36`, un commit conforme, `git push -u origin HEAD`). Recopie **tout** le message d'erreur dans ton journal et souligne la ligne qui porte l'information utile.
2. Pour chaque ligne du message, indique qui l'a produite : ton client Git, `ssh`, GitLab, un hook. Les préfixes (`remote:`, `ERROR:`, `GL-HOOK-ERR:`, `! [remote rejected]`) sont des indices.
3. Délimite le périmètre **sans attendre Karim** : un push vers `formation/git-labo` passe-t-il ? Un push vers `plateforme/medisphere` depuis un autre clone (par exemple `git clone` dans `/tmp`) ? Que te disent ces deux tests ?
4. Trouve la cause racine et corrige-la à l'endroit où elle a été introduite. Si la correction passe par la configuration de GitLab, fais-la par l'interface ou l'API, pas en contournant la protection.
5. Dans ton journal, réponds à Karim : qui d'autre était touché, depuis quand (cherche des traces : journal d'audit de GitLab, `git01`, configuration du dépôt), et quelle mesure aurait détecté la panne avant toi.

**Critères de réussite**
- [ ] Une nouvelle branche de `~/medisphere` se pousse vers `plateforme/medisphere` et la MR peut être ouverte.
- [ ] `main` reste protégée (personne ne pousse directement) ; aucune règle de protection ne couvre les branches de travail.
- [ ] Les hooks globaux de `git01` acceptent une poussée conforme et refusent toujours une poussée non conforme (rejoue un test de M01-E26).
- [ ] Ton journal attribue chaque ligne du message d'erreur à son émetteur et répond à la question « qui d'autre ? ».

**Vérification** : `lab/bin/check 01 36`

<details><summary>Indice 1</summary>

`git push -v` et `GIT_TRACE=1 git push` montrent quelle URL est réellement utilisée et à quel moment l'échec arrive. `git remote -v` affiche **deux** colonnes d'URL : relis-les attentivement.
</details>

<details><summary>Indice 2</summary>

Côté GitLab, un refus a toujours une raison écrite. Le projet est-il dans un état particulier (bandeau en haut de la page) ? Quelles règles de **Settings > Repository > Protected branches** s'appliquent au nom de ta branche ? Côté `git01`, les hooks globaux sont dans le dossier `custom_hooks_dir` de Gitaly (`/var/opt/gitlab/gitaly/config.toml`) : `ls -l` sur `pre-receive.d/`, et les journaux de Gitaly (`sudo gitlab-ctl tail gitaly`) pendant une tentative.
</details>

<details><summary>Indice 3</summary>

Si le message parle de branches protégées alors que tu pousses une branche de travail toute neuve, demande-toi quelles règles un nom comme `fix/essai-e36` peut rencontrer : une règle de protection ne porte pas forcément un nom de branche exact.
</details>

**Pour aller plus loin** : écris une sonde (script de 20 lignes, lancé toutes les 15 minutes depuis `adm01` ou `runner01`) qui pousse une branche jetable sur un projet de test de `formation` avec l'option `ci.skip`, puis la supprime, et alerte en cas d'échec. Quelles variantes aurait-elle détectées ?

---

### M01-E37 — Panne : GitLab répond « 502 »  `BF` `★★★`

> **Ticket INC-2782** — *De : Nadia Roussel*
> Depuis une dizaine de minutes, `https://git01.par1.medisphere.internal` affiche une page d'erreur 502 pour tout le monde. Julien demande si ses `git push` sont concernés. Personne n'a annoncé d'intervention. Rétablis le service et donne-moi la cause.

**Objectifs pédagogiques**
- Connaître la chaîne de traitement d'une requête dans GitLab omnibus (NGINX → Workhorse → Puma) et savoir quel maillon répond quoi.
- Lire les journaux de chaque composant (`gitlab-ctl status`, `gitlab-ctl tail <service>`, `/var/log/gitlab/<service>/current`) et y trouver la ligne décisive.
- Comprendre la différence entre la configuration source (`/etc/gitlab/gitlab.rb`) et les fichiers **générés** par `gitlab-ctl reconfigure`.

**Prérequis** : M01-E04, M01-E30 ; `lab/bin/check 01 37` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Injection** : `lab/bin/break 01 37` (3 variantes). L'injection redémarre parfois un service : compte jusqu'à 4 minutes avant l'affichage du ticket.

**Travail demandé**
1. Reproduis le symptôme depuis `adm01` avec `curl -sv` (et pas seulement le navigateur) : code HTTP, en-têtes, en-tête `Server`, contenu de la page. Teste aussi Git en SSH (`git ls-remote git@git01.par1.medisphere.internal:plateforme/medisphere.git`) : la réponse à la question de Julien est un premier indice.
2. Sur `git01`, fais l'état des services. Un service « en marche » peut redémarrer en boucle : comment le vois-tu ?
3. Remonte la chaîne maillon par maillon : quel composant produit la 502, et quel composant il n'arrive pas à joindre. Appuie chaque étape sur **une ligne de journal** citée dans ton journal de diagnostic.
4. Trouve la cause racine. Avant de corriger, demande-toi si la modification fautive est dans un fichier que tu as le droit de modifier à la main.
5. Corrige de la façon la plus sûre pour une installation omnibus, puis vérifie toute la chaîne : interface web, API, Git en SSH, sonde `/-/readiness` (depuis `git01`, adresse autorisée par la liste blanche de supervision).
6. Propose une prévention : comment détecter qu'un fichier généré a été modifié à la main, et comment alerter sur une 502 avant les utilisateurs ?

> ⚠️ **Attention** : `gitlab-ctl reconfigure` applique **toute** la configuration de `/etc/gitlab/gitlab.rb` et redémarre les services concernés. Avant de le lancer, vérifie que `gitlab.rb` n'a pas été modifié depuis la dernière application (`sudo ls -l /etc/gitlab/` et ta sauvegarde de configuration de M01-E28), sinon tu appliquerais en plus des changements que tu ne connais pas.

**Critères de réussite**
- [ ] L'interface web et l'API répondent 200 depuis `adm01`, Git en SSH fonctionne.
- [ ] `gitlab-ctl status` ne montre aucun service arrêté ni redémarrant en boucle (Puma en marche depuis plus d'une minute).
- [ ] La sonde `/-/readiness` est au vert.
- [ ] Ton journal cite, pour chaque maillon traversé, la ligne de journal qui prouve son état.

**Vérification** : `lab/bin/check 01 37`

<details><summary>Indice 1</summary>

`sudo gitlab-ctl status` affiche pour chaque service son PID et depuis combien de secondes il tourne. Relance la commande dix secondes plus tard et compare. Puis `sudo gitlab-ctl tail nginx`, `sudo gitlab-ctl tail gitlab-workhorse` et `sudo gitlab-ctl tail puma`, chacun pendant une requête de `curl`.
</details>

<details><summary>Indice 2</summary>

Les composants se parlent par des **sockets Unix** sous `/var/opt/gitlab/`. Une ligne de journal du type « dial unix …: connect: … » ou « connect() to unix:… failed » donne le chemin attendu : vérifie qu'il existe (`ls -l`), qui l'a créé et avec quels droits, et quel processus est censé y écouter (`sudo ss -xlp | grep gitlab`).
</details>

<details><summary>Indice 3</summary>

Les fichiers de `/var/opt/gitlab/*/` (configuration de Puma, de NGINX, de gitlab-shell…) sont produits à partir de `gitlab.rb` et des modèles du paquet. Compare la date de modification d'un fichier suspect avec celle de la dernière exécution de `reconfigure`, et regarde ce que `reconfigure` ferait (il affiche les différences qu'il applique).
</details>

**Pour aller plus loin** : refais l'exercice jusqu'à avoir les trois variantes. Pour chacune, note le premier maillon qui ment (il répond « je vais bien ») et le premier qui dit la vérité. C'est l'ébauche de ton runbook « GitLab répond 502 ».

---

### M01-E38 — Panne : le runner ne prend plus les jobs  `BF` `★★`

> **Ticket INC-2783** — *De : Julien Petit*
> Depuis ce matin, les jobs du pipeline de ma MR restent « en attente » (*pending*) et ne démarrent jamais. J'ai relancé deux fois, rien. Tu peux regarder ? Sans pipeline vert, on ne peut plus rien fusionner. (Pour reproduire : ouvre une MR sur `plateforme/medisphere`.)

**Objectifs pédagogiques**
- Comprendre le dialogue runner ↔ GitLab : le runner **interroge** GitLab (il n'est jamais contacté), s'authentifie avec son jeton, et ne reçoit que les jobs compatibles (étiquettes, branches protégées, jobs sans étiquette).
- Lire l'explication de GitLab sur un job bloqué, l'état d'un runner (interface, API) et les journaux du service `gitlab-runner`.
- Diagnostiquer côté GitLab **et** côté runner, sans réenregistrer le runner à l'aveugle.

**Prérequis** : M01-E23, M01-E24 ; `lab/bin/check 01 38` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Injection** : `lab/bin/break 01 38` (4 variantes). Une variante redémarre le service `gitlab-runner` : n'injecte pas pendant un pipeline.

**Travail demandé**
1. Reproduis : ouvre une petite MR sur `plateforme/medisphere`. Clique sur un job en attente et recopie l'explication que GitLab affiche. Un pipeline sur `main` (relance du dernier) se comporte-t-il pareil ?
2. Côté GitLab : état du runner dans **Admin > CI/CD > Runners** (statut, dernier contact, étiquettes, options) ou par l'API (`GET /runners/all`, `GET /runners/:id`).
3. Côté `runner01` : état du service, journaux (`journalctl -u gitlab-runner`), et `gitlab-runner verify` (sans option de suppression). Que fait réellement le runner toutes les trois secondes, et que lui répond GitLab ?
4. Trouve la cause racine et corrige au bon endroit. **Ne réenregistre pas le runner** : un nouvel enregistrement « répare » plusieurs variantes en masquant leur cause, et change l'identité du runner.
5. Vérifie que le pipeline de la MR passe, puis note dans ton journal pour chaque variante rencontrée : où était le symptôme le plus parlant (GitLab ou `runner01`) ?

**Critères de réussite**
- [ ] Le pipeline d'une MR et celui de `main` démarrent et réussissent.
- [ ] Un seul runner d'instance porte les étiquettes `shell` et `socle` ; il est en ligne, actif, accepte les branches non protégées et refuse les jobs sans étiquette.
- [ ] Sur `runner01`, `git01.par1.medisphere.internal` résout vers 10.10.20.12 et le jeton du runner est accepté par GitLab.

**Vérification** : `lab/bin/check 01 38`

<details><summary>Indice 1</summary>

Le message d'un job bloqué liste trois familles de causes : aucun runner en ligne, aucun runner pour une branche protégée ou non, aucun runner portant **toutes** les étiquettes du job. Compare les étiquettes demandées par le job (`tags:` dans le gabarit de `plateforme/ci-templates`) avec celles du runner.
</details>

<details><summary>Indice 2</summary>

Sur `runner01`, `journalctl -u gitlab-runner --since -10min` : une ligne toutes les quelques secondes avec `forbidden`, `dial tcp`, `x509` ou `no route to host` ne raconte pas la même histoire qu'un journal silencieux. Si le runner semble joindre « GitLab », vérifie que c'est le bon (`getent hosts`, `curl -v`).
</details>

**Pour aller plus loin** : dans GitLab, le statut « en ligne » d'un runner tolère un long silence. Écris une sonde qui détecte en moins de 5 minutes qu'aucun job n'a démarré alors que des jobs attendent (API : `GET /projects/:id/jobs?scope[]=pending` et dates de création).

---

### M01-E39 — Panne : la release automatique échoue  `BF` `★★★`

> **Ticket INC-2784** — *De : Karim Benali*
> Lucas me signale que la release automatique de `plateforme/medisphere` est cassée depuis l'intervention d'hier. Je viens d'ouvrir une petite MR « fix(docs): … » : relis-la, fusionne-la, et vérifie qu'une version patch sort toute seule (étiquette + Release GitLab). Si le job `release` échoue, trouve pourquoi et répare sans contourner la chaîne.

**Objectifs pédagogiques**
- Lire le journal d'un job semantic-release et identifier l'étape en échec : vérification des conditions, analyse des commits, création de l'étiquette, publication de la Release.
- Vérifier une chaîne d'identité CI : jeton de projet, variable protégée et masquée, portée d'environnement, protection des étiquettes, outils installés sur le runner.
- Réparer sans affaiblir la sécurité (pas de jeton personnel d'administrateur dans la CI, pas d'étiquette posée à la main).

**Prérequis** : M01-E20, M01-E24, M01-E25 ; `lab/bin/check 01 39` vert avant l'injection.
**Durée indicative** : 45 min (temps cible), hors durée des pipelines.

**Contexte technique** : l'injection ouvre, au nom de Karim, une MR qui modifie `docs/socle/escalade.md` (commit `fix(docs): …`). Sa fusion déclenche sur `main` le pipeline qui contient le job `release` du gabarit `templates/release.yml`. Si la MR est fusionnée, elle reste : c'est un vrai changement.

**Injection** : `lab/bin/break 01 39` (4 variantes).

**Travail demandé**
1. Relis la MR de Karim comme une vraie revue (périmètre, message, pipeline), puis fusionne-la. Attends le pipeline de `main`.
2. Ouvre le journal du job `release` et recopie dans ton journal le **premier** message d'erreur, avec son code s'il en a un (`E…`). Identifie l'étape de semantic-release (ou du script du job) qui a échoué.
3. Vérifie un à un les maillons de la chaîne : jeton `bot-release` (**Settings > Access tokens**), variable `GITLAB_TOKEN` (**Settings > CI/CD > Variables** : drapeaux, portée), étiquettes protégées (**Settings > Repository > Protected tags**), outils de `/opt/release-tools` sur `runner01`. Pour chacun, note la preuve qu'il est sain ou en cause.
4. Corrige la cause racine **sans contourner** : pas de jeton personnel dans la variable, pas d'étiquette créée à la main, pas de suppression de la protection des étiquettes.
5. Relance le pipeline de `main` (ou le job `release`) et vérifie que la version patch est publiée : étiquette `vX.Y.Z`, Release avec ses notes, commentaire du bot sur la MR.
6. Dans ton journal, explique pourquoi le pipeline de la **MR** était vert alors que la chaîne de release était cassée, et ce que cela implique pour la détection.

> ⚠️ **Attention** : si tu renouvelles ou recrées un jeton, sa valeur ne s'affiche **qu'une fois**. Colle-la directement dans la variable CI (protégée, masquée), jamais dans un fichier, un ticket ou ton journal. L'ancien jeton doit finir révoqué.

**Critères de réussite**
- [ ] Le dernier pipeline de `main` a réussi, job `release` compris, et la plus récente étiquette `v*` a sa Release GitLab.
- [ ] Un seul jeton `bot-release` actif (Maintainer, portées `api` et `write_repository`), effectivement utilisé par la CI.
- [ ] `GITLAB_TOKEN` est protégée, masquée et valable pour tous les environnements ; les étiquettes `v*` sont protégées (création : Maintainers).
- [ ] Ton journal contient le message d'erreur initial et la preuve de la cause.

**Vérification** : `lab/bin/check 01 39`

<details><summary>Indice 1</summary>

Les erreurs de semantic-release ont un code (`ENOGLTOKEN`, `EINVALIDGLTOKEN`, `EGLNOPUSHPERMISSION`…) documenté par le plugin `@semantic-release/gitlab`. Une erreur qui arrive **avant** la ligne `semantic-release` dans le journal vient du script du job, pas de semantic-release.
</details>

<details><summary>Indice 2</summary>

Une variable peut exister dans les réglages et pourtant être absente d'un job : protection (le job tourne-t-il sur une référence protégée ?), portée d'environnement (le job déclare-t-il un environnement ?). Un jeton peut exister et pourtant ne plus être celui que contient la variable : compare les dates de création et de dernière utilisation.
</details>

<details><summary>Indice 3</summary>

Si semantic-release calcule la version et échoue au moment de **pousser l'étiquette**, le refus vient de GitLab : relis les règles qui s'appliquent à la création d'une étiquette `v*` et au rôle du bot. Sur `runner01`, `npm ls --prefix /opt/release-tools --depth=0` dit si l'installation est complète.
</details>

**Pour aller plus loin** : les jetons de projet expirent (365 jours au plus). Écris un job planifié (*scheduled pipeline*) qui échoue 30 jours avant l'expiration de `bot-release` (API `GET /projects/:id/access_tokens`), et décris la procédure de rotation sans interruption des releases.

---

### M01-E40 — Panne : clone et push en SSH impossibles  `BF` `★★`

> **Ticket INC-2785** — *De : Lucas Martin*
> Je voulais cloner `plateforme/medisphere` sur `adm01` pour relire une MR, mais `git clone git@git01.par1.medisphere.internal:plateforme/medisphere.git` échoue, et `git push` depuis `~/medisphere` aussi. L'interface web, elle, marche très bien. Je n'ai touché à rien (promis).

**Objectifs pédagogiques**
- Décomposer une connexion Git en SSH : configuration du client (`~/.ssh/config`), résolution, vérification de la clé d'hôte, authentification, compte système `git`, `gitlab-shell` et son appel à l'API interne de GitLab.
- Utiliser `ssh -vT`, `ssh -G` et `GIT_SSH_COMMAND="ssh -v"` comme instruments de mesure.
- Réagir correctement à un changement de clé d'hôte : **vérifier par un autre canal** avant d'accepter.

**Prérequis** : M00-E15, M01-E04, M01-E06 ; `lab/bin/check 01 40` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Injection** : `lab/bin/break 01 40` (4 variantes).

**Travail demandé**
1. Reproduis avec la commande la plus courte : `ssh -T git@git01.par1.medisphere.internal`. Que doit-elle afficher quand tout va bien ?
2. Relance-la en mode verbeux (`-v`, puis `-vvv` si besoin) et découpe la sortie en étapes : configuration appliquée, connexion TCP, échange de clés et vérification de l'hôte, authentification, session. Note dans ton journal la **dernière étape réussie**.
3. Compare avec `ssh git01` (ton accès d'administration) : qu'est-ce qui diffère entre les deux connexions (nom, adresse, utilisateur, options) ? Sers-toi de `ssh -G <hôte>` pour le voir sans te connecter.
4. Trouve la cause racine et corrige à l'endroit où elle se trouve : sur `adm01` ou sur `git01`.
5. Vérifie : `ssh -T`, `git ls-remote`, un `git push` d'une branche de travail, et un `git clone` dans `/tmp` (à supprimer ensuite).

> ⚠️ **Attention** : si `ssh` t'annonce que l'identification de l'hôte a changé, **n'efface pas** l'ancienne clé avant d'avoir comparé l'empreinte présentée avec celle de `git01`, obtenue par un autre chemin (`ssh git01 ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`, console de la VM). C'est exactement le message qu'afficherait une interception.

**Critères de réussite**
- [ ] `ssh -T git@git01.par1.medisphere.internal` affiche l'accueil de GitLab avec ton identifiant ; clone et push en SSH fonctionnent.
- [ ] La clé d'hôte enregistrée pour `git01.par1.medisphere.internal` est bien celle de `git01` (empreinte vérifiée par un autre canal, notée dans le journal).
- [ ] La configuration SSH de `adm01` n'impose aucun rebond vers la forge ; le compte `git` de `git01` n'a pas d'expiration dépassée ; `gitlab-shell` joint l'API interne.

**Vérification** : `lab/bin/check 01 40`

<details><summary>Indice 1</summary>

Si la sortie verbeuse s'arrête avant « Authenticated to … », le problème est dans le client ou le transport ; si elle va au-delà, il est côté serveur (compte, `gitlab-shell`). Sur `git01`, `sudo journalctl -u ssh --since -10min` montre ce que sshd pense de ta tentative, et `/var/log/gitlab/gitlab-shell/gitlab-shell.log` ce qu'en pense `gitlab-shell`.
</details>

<details><summary>Indice 2</summary>

`ssh -G git01.par1.medisphere.internal | grep -iE '^(hostname|user|port|proxyjump|proxycommand|identityfile) '` affiche la configuration effective, bloc par bloc appliqué. Les blocs `Host` sont évalués dans l'ordre du fichier, et pour la plupart des options **la première valeur trouvée l'emporte**.
</details>

**Pour aller plus loin** : la vérification de la clé d'hôte reste manuelle. Lis la documentation des certificats SSH d'hôte (`ssh-keygen -h`, `@cert-authority` dans `known_hosts`) : le module 06 les mettra en place avec step-ca. Explique dans ton journal ce qui aurait changé pour la variante concernée.

---

### M01-E41 — Panne : le dépôt local est corrompu  `BF` `★★★`

> **Ticket INC-2786** — *De : Lucas Martin*
> Coupure de courant cette nuit sur mon poste (j'avais copié mon dépôt sur `adm01` : `~/src/labo-e41`). Depuis, Git m'affiche des erreurs que je ne comprends pas, selon les commandes. J'ai 3 commits jamais poussés sur `feature/sauvegarde-gitlab`, un stash et des modifications en cours dans le runbook. Surtout, ne me dis pas de re-cloner !

**Objectifs pédagogiques**
- Diagnostiquer l'intégrité d'un dépôt : `git fsck --full`, `git cat-file`, lecture directe de `.git/` (références, objets libres, index, `HEAD`).
- Réparer en s'appuyant sur ce que Git conserve ailleurs : reflogs, arbre de travail, autres copies des objets.
- Appliquer la règle d'or de la réparation : copie de sauvegarde **avant** toute intervention, une modification à la fois.

**Prérequis** : M01-E02, M01-E08.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : la panne (re)fabrique le dépôt de Lucas avec `ressources/M01-E41/fabriquer-depot.sh` : `~/src/labo-e41` (variable `WB_SRC`) et son « serveur » `~/src/labo-e41-origine.git` (dépôt nu local, déclaré comme `origin`). Puis elle simule l'effet d'une coupure de courant. Aucune action réseau.

**Injection** : `lab/bin/break 01 41` (4 variantes). Pas de contrôle préalable : le dépôt est créé à l'injection.

> ⚠️ **Attention** : avant **toute** commande de réparation, fais une copie complète : `cp -a ~/src/labo-e41 ~/src/labo-e41.avant-reparation`. Plusieurs commandes de « nettoyage » trouvées sur Internet (`git gc --prune=now`, `git reflog expire`, `rm -rf .git/…`, re-clonage) détruisent précisément ce dont tu as besoin pour récupérer le travail.

**Travail demandé**
1. Fais la copie de sauvegarde. Puis établis l'état des lieux : `git status`, `git log`, `git stash list`, `git fsck --full`. Recopie les messages exacts.
2. Classe la panne : Git ne reconnaît plus le dépôt ? Une référence est cassée ? Un objet est illisible ? L'index est illisible ? Pour chaque cas, liste ce qui est en danger (commits, stash, modifications en cours) et ce qui ne l'est pas.
3. Avant de réparer, cherche **où d'autre** l'information perdue existe encore : reflogs (`.git/logs/`), arbre de travail, origine, autres fichiers de `.git/`. Écris ton plan de réparation dans le journal.
4. Répare, puis prouve que rien n'est perdu : `git fsck --full` propre, les 3 commits sur la branche, le stash, la modification du runbook.
5. Sécurise le travail de Lucas : pousse sa branche vers l'origine. Puis supprime ta copie de sauvegarde.

**Critères de réussite**
- [ ] `git status` et `git fsck --full` fonctionnent sans erreur dans `~/src/labo-e41`.
- [ ] La branche courante est `feature/sauvegarde-gitlab` avec ses 3 commits non publiés ; le stash « essai option --dry-run » et la modification en cours du runbook sont intacts.
- [ ] La branche est publiée sur l'origine.
- [ ] Ton journal explique, pour la variante rencontrée, d'où vient l'information qui a permis la réparation.

**Vérification** : `lab/bin/check 01 41`

<details><summary>Indice 1</summary>

`git fsck --full` désigne l'objet ou la référence en cause. Un objet libre est un fichier `.git/objects/xx/yyyy…` (compressé zlib) ; une référence est un fichier texte de 41 octets (`.git/refs/heads/…`) ou une ligne de `.git/packed-refs` ; `HEAD` contient normalement `ref: refs/heads/<branche>`. Regarde leur taille et leur contenu.
</details>

<details><summary>Indice 2</summary>

Les reflogs (`.git/logs/HEAD`, `.git/logs/refs/heads/<branche>`) sont de simples fichiers texte : chaque ligne contient l'ancienne et la nouvelle valeur de la référence. Pour un objet disparu, demande-toi s'il est identique à un fichier de l'arbre de travail : `git hash-object` calcule l'empreinte qu'aurait ce fichier.
</details>

<details><summary>Indice 3</summary>

Git refuse parfois de réécrire un objet ou une référence qu'il croit déjà présent, même abîmé. Si une commande de réparation « réussit » sans rien changer, mets d'abord l'élément endommagé de côté (déplace-le, ne le supprime pas).
</details>

**Pour aller plus loin** : refais l'exercice jusqu'à avoir les quatre variantes, et classe-les de la plus facile à la plus dangereuse à réparer. Puis cherche quel réglage du système de fichiers ou de Git (`core.fsync`, `core.fsyncMethod`) réduit le risque de ce type de corruption, et à quel coût.

---

### M01-E42 — Panne : « tout mon travail a disparu »  `BF` `★★`

> **Ticket INC-2787** — *De : Lucas Martin*
> Au secours : j'ai voulu « nettoyer » mon dépôt `~/src/labo-e42` avant de pousser, et une partie de mon travail a disparu (je ne sais plus exactement ce que j'ai tapé, j'ai recopié des commandes d'un forum). Je n'avais encore rien poussé de ma branche `feature/rotation-jetons`. Est-ce que c'est récupérable ? Je n'ose plus rien toucher.

**Objectifs pédagogiques**
- Reconstituer ce qui s'est passé à partir des traces locales : reflog de `HEAD` et des branches, `ORIG_HEAD`, objets orphelins.
- Récupérer des commits, une branche supprimée, un stash supprimé et du contenu indexé jamais commité.
- Savoir ce que Git ne peut **pas** récupérer, et pourquoi.

**Prérequis** : M01-E08, M01-E12.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : la panne (re)fabrique le dépôt de Lucas avec `ressources/M01-E42/fabriquer-depot.sh` (`~/src/labo-e42` et son origine locale `~/src/labo-e42-origine.git`), puis rejoue sa fausse manœuvre. Avant celle-ci, la branche `feature/rotation-jetons` portait 4 commits non publiés et un stash de notes de conception existait.

**Injection** : `lab/bin/break 01 42` (4 variantes). Pas de contrôle préalable.

> ⚠️ **Attention** : n'exécute **aucune** commande de maintenance (`git gc`, `git prune`, `git reflog expire`, `git stash clear`) pendant la récupération : elles suppriment justement les objets et les traces dont tu as besoin. Fais d'abord une copie (`cp -a`).

**Travail demandé**
1. Reconstitue la chronologie de la fausse manœuvre à partir des traces que Git a laissées, **avant** de réparer. Écris-la dans ton journal (commande probable, heure, effet).
2. Dresse l'inventaire de ce qui manque par rapport à la description de Lucas : commits, branche, stash, fichiers.
3. Récupère chaque élément manquant. Choisis à chaque fois la méthode la moins risquée, et explique pourquoi elle est sûre.
4. Vérifie que la branche contient bien les 4 commits, dans le bon ordre, et que rien d'autre n'a été perdu.
5. Écris à Lucas (5 lignes dans le journal) : ce qui s'est passé, ce qui a été récupéré, et les deux réflexes qui lui auraient évité la panique.

**Critères de réussite**
- [ ] `feature/rotation-jetons` existe et porte les 4 commits de Lucas.
- [ ] Les notes de conception du stash sont récupérées (en stash ou dans un commit).
- [ ] Aucun contenu de Lucas ne subsiste uniquement dans un objet orphelin.
- [ ] Ton journal contient la chronologie reconstituée et la commande qui a prouvé chaque récupération.

**Vérification** : `lab/bin/check 01 42`

<details><summary>Indice 1</summary>

`git reflog` (de `HEAD`) et `git reflog show <branche>` racontent les déplacements de références, avec la commande qui les a causés. Une branche supprimée emporte son propre reflog… mais pas celui de `HEAD`.
</details>

<details><summary>Indice 2</summary>

Un stash supprimé et un fichier indexé puis effacé ne sont plus référencés par rien, mais leurs objets existent encore : `git fsck` sait lister les objets **orphelins** (*dangling*, *unreachable*), et une option de `git fsck` les dépose dans un dossier de `.git/` où tu peux les lire.
</details>

**Pour aller plus loin** : combien de temps ces traces survivent-elles ? Cherche dans `git help gc` les réglages `gc.reflogExpire`, `gc.reflogExpireUnreachable` et `gc.pruneExpire`, et calcule le délai maximal dont aurait disposé Lucas pour chaque variante.

---

### M01-E43 — Astreinte : la forge en difficulté  `BF` `★★★★`

> **Ticket INC-2788** — *De : Nadia Roussel (responsable astreinte)* — priorité P2
> Tu es d'astreinte. Depuis 7 h, plusieurs remontées sur la forge (le détail s'affiche à l'injection). Je ne sais pas si c'est lié. Rétablis le service, tiens-moi informée toutes les 30 minutes (un message court dans le canal #astreinte suffit), puis rédige le post-mortem et publie-le par MR.

**Objectifs pédagogiques**
- Gérer un incident à causes multiples sur un service dont dépend toute l'équipe : trier, prioriser, éviter qu'une panne en masque une autre.
- Choisir ses instruments quand l'outil de travail lui-même (la forge) est en panne.
- Rédiger et faire relire un post-mortem sans recherche de coupable.

**Prérequis** : M01-E36 à M01-E42 (au moins une variante de chacun), M00-E46.
**Durée indicative** : 90 min de rétablissement + 45 min de post-mortem.

**Contexte technique** : le script tire **deux** pannes distinctes parmi celles de M01-E36 à M01-E42 (variantes aléatoires) et les injecte ensemble. Les symptômes peuvent se recouvrir. `--variante N` (1 à 21) force la paire, pas les variantes. `--annuler` retire les deux. Le modèle de post-mortem de l'équipe est celui du module 00 : `modules/00-lab/ressources/M00-E46/modele-post-mortem.md`.

**Injection** : `lab/bin/break 01 43`

**Travail demandé**
1. **Triage (10 min max)** : avant toute correction, liste les symptômes, leur impact (qui ne peut plus faire quoi : pousser, fusionner, livrer, consulter ?) et une première hypothèse de regroupement. Envoie la première communication (statut, impact, actions en cours, prochaine communication).
2. **Diagnostic** : traite les pannes dans l'ordre que tu justifies. Pense à ce dont **toi** tu as besoin pour diagnostiquer (interface web, API, SSH, runner) : rétablis d'abord tes instruments. Journal horodaté.
3. **Rétablissement** : corrige chaque cause racine. Après chaque correction, rejoue **tous** les tests du triage, pas seulement celui que tu viens de réparer.
4. **Clôture** : communication de fin d'incident, puis post-mortem `docs/socle/post-mortems/AAAA-MM-JJ-INC-2788.md` dans `plateforme/medisphere`, sur une branche, fusionné par MR (pipeline vert, relecture de « Karim » simulée : relis-toi le lendemain).

**Critères de réussite**
- [ ] Toutes les vérifications de M01-E36 à M01-E42 sont vertes (le contrôle les rejoue ; E41 et E42 seulement si leur dépôt existe).
- [ ] Le post-mortem est fusionné dans `main` ; il contient une chronologie horodatée, les deux causes racines, l'analyse de la détection et des actions avec responsable et échéance.
- [ ] Le journal contient au moins trois communications d'incident espacées d'environ 30 minutes.

**Vérification** : `lab/bin/check 01 43`

<details><summary>Indice 1</summary>

Une forge en panne peut t'empêcher de publier ton journal et ton post-mortem : prévois où tu écris pendant l'incident (fichier local dans `~/medisphere`, commit local), et publie quand la forge est revenue.
</details>

<details><summary>Indice 2</summary>

Les contrôles `lab/bin/check 01 36` à `01 42` sont des sondes ciblées : lance-les tous au début pour cartographier ce qui est rouge, puis après chaque correction. Attention aux sondes qui mentent quand un maillon commun est cassé (l'API pour les unes, SSH pour les autres).
</details>

<details><summary>Indice 3</summary>

Après avoir corrigé une première cause, un symptôme qui persiste peut avoir une seconde cause ; un symptôme qui **apparaît** était peut-être masqué par la première. Vérifie-le avant de revenir sur ta correction.
</details>

**Pour aller plus loin** : fais-toi injecter une astreinte par quelqu'un d'autre (`--variante` tirée par lui), sans regarder l'écran pendant l'injection, et chronomètre ton temps de rétablissement. Compare avec ton temps de M00-E46.

---

### M01-E44 — Trouver le commit fautif avec `git bisect run`  `LAB` `★★★`

> **Ticket DEV-280** — *De : Julien Petit*
> L'outil `flux-check` (il transforme la matrice des flux en règles lisibles) donne des plages de ports fausses : `30000-32767` devient `30000-30000`. La v1.0.0 était correcte, et il y a plus de cent commits depuis, avec des fusions. Personne ne sait quand c'est arrivé. Trouve le commit fautif sans relire tout l'historique, et propose un correctif propre.

**Objectifs pédagogiques**
- Mener une bisection manuelle puis automatique (`git bisect run`), et en comprendre l'algorithme (dichotomie sur le graphe des commits).
- Écrire un script de test de bisection robuste : codes de sortie `0`, `1`-`127` (sauf `125`), `125` (« non testable ») ; script placé hors du dépôt.
- Comprendre l'effet des fusions sur la bisection (`--first-parent`) et choisir le bon correctif (`git revert` d'un commit ou d'une fusion).

**Prérequis** : M01-E07, M01-E08 ; M01-E12 utile.
**Durée indicative** : 2 h.

**Contexte technique**
- Fabrique le dépôt (sans réseau, environ 10 secondes) :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ modules/01-git/ressources/M01-E44/fabriquer-depot.sh
  ```
  Il crée `~/src/labo-e44` (`WB_SRC`). Exception à la règle n° 7 du module : **ne lis pas ce script avant la fin de l'exercice**, il contient la réponse.
- Le test de bout en bout est `tests/test.sh` (code 0 si la sortie de `bin/flux-check tests/flux-exemple.csv` est celle attendue). La version de référence correcte est l'étiquette `v1.0.0`.

**Travail demandé**
1. Constate la régression : `tests/test.sh` sur `main`, puis sur `v1.0.0` (`git switch --detach v1.0.0`). Combien de commits séparent les deux (`git rev-list --count`) ? Combien d'étapes de bisection prévois-tu ?
2. **Bisection manuelle** : `git bisect start`, marque `main` mauvais et `v1.0.0` bon, puis teste à la main les trois premières étapes. Observe `git bisect visualize --oneline` (ou `git bisect view`) et `git bisect log`. Arrête avec `git bisect reset`.
3. **Script de test** : écris `~/src/bisect-e44.sh` (exécutable, **hors** du dépôt). Il doit répondre « bon », « mauvais » ou « non testable » : un commit dont le code ne se charge même pas (erreur de syntaxe dans un fichier sans rapport) n'est ni bon ni mauvais. Note dans ton journal pourquoi le script ne doit pas vivre dans le dépôt.
4. **Bisection automatique** : `git bisect run ~/src/bisect-e44.sh`. Enregistre `git bisect log` dans ton journal, avec le commit trouvé et le nombre d'étapes.
5. **Contre-épreuve** : refais la bisection avec un script naïf qui se contente de lancer `tests/test.sh`. Quel commit désigne-t-il ? Explique l'erreur.
6. **Fusions** : refais la bisection avec `git bisect start --first-parent`. Quel commit est désigné ? Quand cette option est-elle préférable ?
7. **Correctif** : depuis `main`, crée la branche `fix/regression-plages` et annule **le commit fautif seul** avec `git revert`. Donne au commit un message Conventional Commits (`revert: …`) en conservant la ligne `This reverts commit <empreinte>.` produite par Git. Vérifie que `tests/test.sh` passe.
8. **Journal** : dans `docs/socle/journal/` de `~/medisphere`, une entrée « DEV-280 » avec l'empreinte du commit fautif, le `git bisect log`, ta réponse aux questions des étapes 3, 5 et 6, et le choix entre annuler le commit et annuler la fusion.

> ⚠️ **Attention** : pendant une bisection, Git déplace `HEAD` sur des commits anciens (tête détachée). Ne commite rien pendant une bisection et termine toujours par `git bisect reset`, sinon ton prochain commit partira d'un commit du passé.

**Critères de réussite**
- [ ] `~/src/bisect-e44.sh` existe, est exécutable, et distingue « non testable » (code 125).
- [ ] La branche `fix/regression-plages` part de `main`, annule le commit fautif (et pas la fusion entière), et ses tests passent.
- [ ] Aucune bisection n'est en cours dans `~/src/labo-e44`.
- [ ] Le journal contient l'empreinte du commit fautif, le `git bisect log` et les réponses aux questions.

**Vérification** : `lab/bin/check 01 44`

<details><summary>Indice 1</summary>

`git bisect run` interprète le code de sortie du script : relis la section « bisect run » de `git help bisect` pour la signification exacte de 0, 125, des valeurs de 1 à 127 et des valeurs supérieures à 127. Un script qui plante pour une raison sans rapport doit le dire.
</details>

<details><summary>Indice 2</summary>

Pour savoir si un commit est testable, `bash -n` vérifie la syntaxe d'un script sans l'exécuter. Teste chaque fichier chargé par `bin/flux-check`.
</details>

<details><summary>Indice 3</summary>

Avec `--first-parent`, la bisection ne descend pas dans les branches fusionnées : elle désigne la fusion qui a fait entrer la régression dans `main`. Pour annuler une fusion, `git revert` exige `-m 1` et annule **toute** la branche fusionnée.
</details>

**Pour aller plus loin** : fabrique une seconde fois le dépôt dans un autre dossier et compare les empreintes des commits : pourquoi sont-elles identiques ? Puis mesure combien d'étapes coûte chaque commit « non testable » supplémentaire, et propose une règle d'équipe qui rend la bisection fiable (indice : chaque commit de `main` doit passer les tests).

---

### M01-E45 — Sous le capot : packfiles, maintenance et gros dépôts  `LAB` `★★★`

> **Ticket PLAT-281** — *De : Karim Benali*
> InfoGér nous a enfin livré l'historique Git de Legacy-RDV : 4 000 commits, et un dépôt qui pèse lourd. Avant de l'importer dans la forge, je veux comprendre ce qu'il contient, ce qui le rend gros, et ce qu'il coûtera à chaque clone et à chaque job de CI. Mesure tout, importe-le proprement dans `formation/legacy-rdv` (les fichiers de plus de 5 Mio n'ont rien à faire dans Git, c'est la règle de la forge), et fais-moi un rapport.

**Objectifs pédagogiques**
- Lire le stockage d'un dépôt : objets libres et empaquetés, fichiers `.pack`/`.idx`/`.rev`, deltas et chaînes de deltas, références empaquetées.
- Trouver ce qui pèse dans **tout** l'historique, mesurer l'effet de `git gc` et `git repack`, et expliquer pourquoi certains contenus se compressent et d'autres non.
- Comparer les stratégies de clone (complet, superficiel, partiel, avec `sparse-checkout`) et leurs coûts.
- Déplacer des binaires vers Git LFS en réécrivant l'historique, et mesurer le gain côté serveur.
- Connaître la maintenance de Git (`git maintenance`, `commit-graph`) et celle de GitLab (*housekeeping*).

**Prérequis** : M01-E02, M01-E06, M01-E26.
**Durée indicative** : 3 h.

**Contexte technique**
- Fabrique le dépôt (sans réseau, 30 à 60 secondes, environ 200 Mo sur le disque) :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ modules/01-git/ressources/M01-E45/fabriquer-depot.sh
  ```
  Il crée `~/src/legacy-rdv`. L'option `--commits N` fabrique un historique plus long (utile pour l'étape 8).
- Git LFS : paquet `git-lfs` de Debian sur `adm01`. GitLab omnibus active LFS par défaut ; vérifie-le dans **Admin > Settings** et sur le projet.
- Projets à créer dans le groupe `formation` (privés) : `formation/legacy-rdv-brut` (temporaire, pour les mesures avant migration) et `formation/legacy-rdv` (cible). Les hooks de M01-E26 ne s'appliquent qu'au groupe `plateforme` : ici, c'est à toi d'appliquer la règle des 5 Mio.
- Espace disque : vérifie `df -h ~` sur `adm01` et `df -h /var/opt/gitlab` sur `git01` avant de commencer (prévois 1 Go et 300 Mo).

**Travail demandé**
1. **État des lieux.** Dans `~/src/legacy-rdv` : nombre de commits, `git count-objects -vH`, `du -sh .git`, contenu de `.git/objects/pack/`. À quoi servent les fichiers `.idx` et `.rev` à côté du `.pack` ?
2. **Anatomie d'un paquet.** `git verify-pack -v .git/objects/pack/pack-*.idx | sort -k3 -n | tail` et le résumé de fin (`chain length`). Repère un objet stocké en delta : de quel objet de base dépend-il ? Que signifient les colonnes ?
3. **Ce qui pèse dans l'historique.** Liste les 10 plus gros blobs de **tout** l'historique avec leur chemin :
   ```
   admin@adm01:~/src/legacy-rdv$ git rev-list --objects --all \
       | git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(objectsize:disk) %(rest)' \
       | awk '$1 == "blob"' | sort -k3 -n -r | head
   ```
   Explique l'écart entre `objectsize` et `objectsize:disk` pour `db/dump-demo.sql` et pour `assets/video/presentation.mp4`. Pourquoi la vidéo pèse-t-elle encore alors qu'elle a été supprimée de l'arbre ?
4. **Compression.** Mesure taille et durée de `git gc`, puis de `git repack -a -d -f --depth=50 --window=250`. Qu'est-ce qui a gagné, qu'est-ce qui n'a pas bougé, et pourquoi ?
5. **Coût côté forge, avant migration.** Crée `formation/legacy-rdv-brut`, pousse l'historique tel quel, et relève la taille du dépôt dans GitLab (page du projet, ou `GET /projects/:id?statistics=true`). Mesure (`time`, `du -sh`) dans `/tmp` : clone complet, `--depth 1`, `--filter=blob:none`, `--filter=blob:limit=1m`, et `--filter=blob:none --sparse` suivi de `git sparse-checkout set src`. Supprime les clones de mesure.
6. **Migration vers LFS.** Sur une **copie** du dépôt, inventorie (`git lfs migrate info --everything --above=5mb`) puis migre (`git lfs migrate import --everything --above=5mb`). Vérifie `.gitattributes`, `git lfs ls-files`, la taille de `.git` après `git gc`. Puis remplace `~/src/legacy-rdv` par la copie migrée, crée `formation/legacy-rdv`, et pousse branches et étiquettes. Vérifie dans GitLab : taille du dépôt Git, taille des objets LFS.
7. **Clone partiel.** Clone `formation/legacy-rdv` dans `~/src/legacy-rdv-partiel` avec `--filter=blob:none`. Lance `git log -p -5 -- db/dump-demo.sql` et observe le réseau (`GIT_TRACE=1` ou la durée) : que se passe-t-il ? Lis `git config --get-regexp 'remote.origin.*'`.
8. **Maintenance locale.** Dans `~/src/legacy-rdv`, mesure `time git log --oneline -- src/Module7.php | wc -l`, puis écris le graphe de commits avec les filtres de chemins modifiés (`git commit-graph write --reachable --changed-paths`) et remesure. Lance `git maintenance start`, observe ce qui a été planifié (`systemctl --user list-timers`, `git config --global --get-all maintenance.repo`) et décide si tu le gardes sur `adm01` (justifie).
9. **Maintenance côté GitLab.** Lis ce que fait le *housekeeping* d'un projet (**Settings > General > Advanced**) et quand GitLab le déclenche seul. Lance-le sur `formation/legacy-rdv-brut`, puis supprime ce projet temporaire.
10. **Rapport.** `docs/socle/analyses/git-gros-depot.md` dans `~/medisphere`, publié par MR : tableau des mesures (tailles, durées, nombre d'objets, pour chaque étape), explication de ce qui pèse, comparaison des stratégies de clone, migration LFS (avant/après côté forge), maintenance, et **recommandations** pour MédiSphère (règle des gros fichiers, stratégie de clone en CI, maintenance).

> ⚠️ **Attention** : `git lfs migrate import --everything` **réécrit tout l'historique** : toutes les empreintes de commits changent, les étiquettes aussi. Sur un dépôt partagé, cela impose une communication, un nouveau clone pour tout le monde et la purge des anciennes références côté serveur. Ici, tu travailles sur une copie et tu pousses dans un projet neuf : c'est le scénario sûr.

**Critères de réussite**
- [ ] `formation/legacy-rdv` contient l'historique complet ; ses gros fichiers sont dans LFS et son dépôt Git pèse moins de 30 Mio.
- [ ] `~/src/legacy-rdv` suit les fichiers volumineux par LFS et possède un graphe de commits ; `~/src/legacy-rdv-partiel` est un clone partiel.
- [ ] `formation/legacy-rdv-brut` a été supprimé.
- [ ] Le rapport contient les mesures de chaque étape et des recommandations argumentées.

**Vérification** : `lab/bin/check 01 45`

<details><summary>Indice 1</summary>

Un delta n'est efficace qu'entre versions proches d'un même contenu **compressible** : du texte qui change peu d'une version à l'autre se réduit à presque rien, des données aléatoires ou déjà compressées (vidéo, archive) ne se réduisent pas. Et un objet atteignable depuis n'importe quelle référence ou n'importe quel reflog reste dans le dépôt.
</details>

<details><summary>Indice 2</summary>

Après une réécriture, les anciens objets restent tant que quelque chose les référence : branches de suivi distantes (`refs/remotes/`), reflogs, `refs/original/`, stash. `git for-each-ref` liste toutes les références d'un dépôt.
</details>

<details><summary>Indice 3</summary>

Les filtres de chemins modifiés (*changed-path Bloom filters*) accélèrent surtout `git log -- <chemin>` sur de longs historiques. Avec 4 000 commits, l'écart est faible : fabrique un historique de 50 000 commits dans un autre dossier (`--commits 50000`) pour une mesure parlante.
</details>

**Pour aller plus loin** : refais l'étape 6 avec `git filter-repo` (paquet `git-filter-repo`) pour **supprimer** l'export SQL de l'historique au lieu de le déplacer. Compare la démarche, le résultat et ce qu'il faut ensuite faire côté GitLab pour vraiment libérer l'espace (documentation « Reduce repository size »).

---

### M01-E46 — Questions expert : les entrailles de Git  `Q` `★★★`

> **Ticket PLAT-282** — *De : Karim Benali*
> Dernière étape avant la recette de la forge : ces questions, je les pose en entretien pour un poste d'ingénieur plateforme senior. Réponds par écrit, en argumentant. Pas de recherche pendant la première passe ; vérifie ensuite dans la documentation et corrige-toi en couleur.

**Objectifs pédagogiques**
- Consolider la compréhension des mécanismes internes de Git et de GitLab manipulés dans le module.
- S'entraîner à argumenter une réponse technique comme en entretien ou en revue d'architecture.

**Prérequis** : paliers 1 à 3 du module, M01-E41, M01-E44, M01-E45.
**Durée indicative** : 2 h 30.

**Questions**

1. Un commit est modifié par `git commit --amend` sans changer aucun fichier, seulement le message. Quels objets sont créés, lesquels restent, et pourquoi l'empreinte du commit change-t-elle ? Qu'arrive-t-il aux commits **enfants** éventuels ?
2. QCM — Deux fichiers différents du dépôt ont exactement le même contenu. Combien de blobs Git stocke-t-il ?
   a) deux, un par chemin ; b) un seul, le chemin est dans l'arbre ; c) un seul, mais seulement après `git gc` ; d) deux, sauf si `core.deduplicate` est activé.
3. Explique la différence entre un objet **libre** et un objet **empaqueté**, puis le rôle des fichiers `.idx`, `.rev` et `multi-pack-index`. Pourquoi Git peut-il stocker un objet en delta par rapport à un objet **plus récent** ?
4. `git gc` ne supprime pas un commit que tu viens d'abandonner par `git reset --hard`. Cite les réglages qui fixent les délais (`gc.reflogExpire`, `gc.reflogExpireUnreachable`, `gc.pruneExpire`), leurs valeurs par défaut, et explique pourquoi deux délais différents s'appliquent avant qu'un objet disparaisse vraiment.
5. QCM — Après `git branch -D feature`, quelle trace permet le plus sûrement de retrouver la pointe de la branche ?
   a) `git reflog show feature` ; b) `git reflog` (celui de `HEAD`), si la branche a été extraite ; c) `.git/refs/heads/feature.bak` ; d) `git stash list`.
6. Quelle différence entre `git fsck --unreachable`, `--dangling` (comportement par défaut) et `--lost-found` ? Pourquoi `git fsck --no-reflogs` montre-t-il plus d'objets ?
7. Décris l'algorithme de `git bisect` : combien d'étapes pour 1 000 commits linéaires ? Comment les commits « non testables » (code 125) et les fusions modifient-ils le déroulement ? Que fait `--first-parent` ?
8. `git push --force` contre `--force-with-lease` contre `--force-if-includes` : que vérifie chacun, et dans quel scénario précis `--force-with-lease` **seul** ne protège plus (indice : un `git fetch` automatique de ton éditeur) ?
9. QCM — Sur une branche protégée de GitLab, `push` est réglé sur « No one » et `merge` sur « Maintainers ». Un administrateur de l'instance fait `git push origin main`. Que se passe-t-il ?
   a) accepté : les administrateurs contournent toutes les protections ; b) refusé : « No one » s'applique à tout le monde, y compris aux administrateurs ; c) accepté seulement en *Admin Mode* ; d) refusé, sauf avec `--force`.
10. Explique la différence entre un clone superficiel (`--depth`) et un clone partiel (`--filter`). Lequel convient à un job de CI qui lance semantic-release, lequel à un développeur sur un gros dépôt, et pourquoi ? Que signifie « promisor » ?
11. Comment fonctionne Git LFS : que contient le fichier versionné (le *pointeur*), où va le contenu, quel rôle jouent les filtres `clean`/`smudge` et le hook `pre-push` ? Que perd-on par rapport à des fichiers ordinaires ?
12. Le protocole Git v2 : qu'apporte-t-il par rapport au v0 (annonce des références, `ls-refs`, filtres) et pourquoi le gain est-il important pour un dépôt qui a des milliers d'étiquettes ?
13. Quelle stratégie de fusion Git utilise-t-il par défaut depuis la 2.34, et qu'apporte-t-elle par rapport à `recursive` ? Que fait `rerere` et où stocke-t-il ses résolutions ?
14. Le format de stockage des références : fichiers libres, `packed-refs`, et le nouveau *reftable*. Quels problèmes le *reftable* résout-il, et comment migrer un dépôt existant avec Git 2.47 ?
15. SHA-1 dans Git : pourquoi la collision « SHAttered » n'a-t-elle pas permis de casser Git en pratique (détection de collision `sha1dc`), et où en est le passage à SHA-256 (`extensions.objectFormat`, interopérabilité, prise en charge par les forges) ?
16. Une signature SSH de commit (M01-E27) : qu'est-ce qui est signé exactement ? Que vérifie GitLab pour afficher « Verified », et que se passe-t-il si la clé de signature est supprimée du compte ?
17. Où GitLab omnibus stocke-t-il un dépôt sur le disque (*hashed storage*) ? Pourquoi un `ls /var/opt/gitlab/git-data/repositories/` ne montre-t-il pas les noms de projets, et comment retrouver le chemin d'un projet ?
18. Quels sont les rôles respectifs de Gitaly, de `gitlab-shell` et de Workhorse lors d'un `git push` en SSH, puis en HTTPS ? Dans quel ordre interviennent l'authentification, les contrôles de branche protégée et les hooks globaux ?
19. QCM — Un hook global `pre-receive` sort avec le code 1 sans rien afficher. Que voit l'utilisateur qui pousse ?
   a) rien, le push réussit ; b) un refus « pre-receive hook declined », sans explication ; c) un message d'erreur générique de GitLab dans l'interface uniquement ; d) le push réussit mais la MR est bloquée.
20. Que fait le *housekeeping* de GitLab (repack incrémental ou complet, élagage des objets inatteignables, graphe de commits) et pourquoi « Prune unreachable objects » peut-il être dangereux si une opération de fusion est en cours ?

**Critères de réussite**
- [ ] Les 20 questions ont une réponse écrite et argumentée (pour les QCM : la bonne réponse **et** pourquoi les autres sont fausses).
- [ ] Après correction, tu as identifié tes trois points les plus faibles et noté un exercice ou une lecture pour chacun.

<details><summary>Indice 1</summary>

Pour les questions 1 à 6, tes manipulations de M01-E02, M01-E41 et M01-E42 contiennent l'essentiel : refais une expérience de 5 minutes quand tu doutes, dans un dépôt jetable.
</details>

<details><summary>Indice 2</summary>

Pour les questions 3, 4, 10 et 14, les pages de manuel `git help gc`, `git help repack`, `git help clone`, `git help refs` et le chapitre 10 de *Pro Git* (« Les tripes de Git ») sont la référence. Pour 17 à 20, la documentation d'administration de GitLab (« Repository storage », « Housekeeping », « Git server hooks »).
</details>

**Pour aller plus loin** : choisis trois questions et transforme chacune en mini-démonstration sur le lab (5 minutes, reproductible), à présenter à Karim.
