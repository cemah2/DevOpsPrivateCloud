# Module 01 — Palier 4 : Expert — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les corrigés des pannes suivent la trame du module 00 : **symptômes → hypothèses → commandes de diagnostic dans l'ordre → cause racine (par variante) → correctif → prévention**. La démarche compte plus que le correctif : « j'ai lancé `gitlab-ctl reconfigure` et ça remarche » ou « j'ai réenregistré le runner » sont des échecs pédagogiques tant que tu ne sais pas **ce qui** était cassé.

Les scripts d'injection sont dans `corrige/pannes/` : `break-E36.sh` à `break-E43.sh`, et `_m01-commun.sh` (appels à l'API GitLab avec le jeton d'administration, dossier d'état local). Ils utilisent la bibliothèque commune `lab/lib/pannes-lib.sh`. Sur `git01` et `runner01`, chaque modification est journalisée dans `/var/lib/workbook/pannes.log`, avec une copie de l'état d'origine dans `/var/lib/workbook/M01-EXX.*` ; côté `adm01`, l'état d'origine (identifiants GitLab, ancienne configuration, archives des dépôts d'exercice) est dans `~/.local/state/workbook/M01-EXX/` (700).

Les sorties de commandes reproduites ci-dessous sont **représentatives** : identifiants, empreintes, horodatages et formulations exactes varient selon ta version et ton installation. Les sorties de E41, E42, E44 et E45 ont été obtenues réellement (Git 2.43 et 2.47 produisent les mêmes empreintes pour les dépôts fabriqués à dates fixes).

**Points non testés en conditions réelles** (signale-les si ton comportement diffère) : mise en forme exacte des messages renvoyés au client par GitLab 19 (`remote: GitLab: …`, cadre `=====` de gitlab-shell, affichage du préfixe `GL-HOOK-ERR:`) ; message de sshd pour un compte expiré (E40 v1) ; message de `gitlab-shell` quand l'API interne est injoignable (E40 v3) ; nom du fichier de configuration NGINX qui porte l'amont `gitlab-workhorse` (E37 v3, le script le cherche) ; possibilité de renouveler (*rotate*) un jeton de projet avec un jeton personnel d'administrateur non membre du projet (E39 v1) ; comportement de la suppression différée des projets dans GitLab 19 (E45).

---

## Méthode commune aux pannes de forge

La forge est un empilement de maillons. Avant le détail par exercice, la grille qui sert partout :

1. **Reproduire avec l'outil le plus bas niveau possible** : `curl -sv` plutôt que le navigateur, `ssh -vT git@…` plutôt que `git push`, `git ls-remote` plutôt qu'un clone. Moins il y a de couches, plus le message est précis.
2. **Attribuer chaque message à son émetteur.** Une ligne préfixée par `remote:` vient du serveur ; `GL-HOOK-ERR:` vient d'un hook côté serveur ; `[remote rejected] … (pre-receive hook declined)` signifie seulement « refusé pendant la phase pre-receive », qui inclut **aussi** les contrôles d'accès de GitLab lui-même (branches protégées, rôle), pas seulement les hooks personnalisés. Une ligne sans préfixe vient de ton client Git ou de `ssh`.
3. **Délimiter le périmètre** : une personne (configuration locale), un projet (réglages du projet), toute la forge (service, hooks globaux, compte système). Un deuxième clone dans `/tmp` et un push vers `formation/git-labo` tranchent en une minute.
4. **Lire les journaux du bon composant.** Sur `git01`, `sudo gitlab-ctl status` puis `sudo gitlab-ctl tail <service>` ; les journaux bruts sont dans `/var/log/gitlab/<service>/current` (format JSON pour Workhorse, Gitaly, gitlab-shell). Sur `runner01`, `journalctl -u gitlab-runner`.
5. **Distinguer la source et le généré.** Sur GitLab omnibus, `/etc/gitlab/gitlab.rb` est la source ; tout ce qui est sous `/var/opt/gitlab/*/` (configuration de Puma, NGINX, gitlab-shell, Gitaly) est **généré** par `gitlab-ctl reconfigure` et écrasé à la prochaine exécution. Une modification à la main d'un fichier généré est une panne en sursis.
6. **Corriger à la racine, puis vérifier le symptôme initial et les chemins voisins** (web, API, SSH, runner, release).
7. **Prévenir** : quelle sonde, quel contrôle de dérive, quel processus aurait détecté ou empêché la panne ?

---

### M01-E36 — Panne : `git push` est refusé

**Démarche de diagnostic**

*Symptômes rapportés* : `git push` d'une branche de travail de `~/medisphere` vers `plateforme/medisphere` est refusé ; `git fetch` fonctionne.

*Hypothèses initiales* : URL de poussée erronée ; clé SSH non reconnue ; droits insuffisants sur le projet ; projet en lecture seule (archivé, dépôt en lecture seule) ; règle de protection qui s'applique à la branche ; hook côté serveur qui refuse ; espace disque de Gitaly.

Le fait que `fetch` fonctionne élimine déjà une partie des hypothèses : la clé SSH est acceptée, le projet existe et tu peux le lire… **par l'URL de fetch**. Garde cette nuance en tête.

**Étape 1 — Reproduire et lire le message en entier.**

```
admin@adm01:~/medisphere$ git switch -c fix/essai-e36
admin@adm01:~/medisphere$ git commit --allow-empty -m "chore: essai de poussée (INC-2781)"
admin@adm01:~/medisphere$ git push -v -u origin HEAD
```

**Étape 2 — Délimiter.**

```
admin@adm01:~$ git -C ~/medisphere remote -v
admin@adm01:~$ git clone -q git@git01.par1.medisphere.internal:plateforme/medisphere.git /tmp/e36 \
                 && git -C /tmp/e36 switch -c fix/essai-e36b \
                 && git -C /tmp/e36 commit -q --allow-empty -m "chore: essai depuis un autre clone" \
                 && git -C /tmp/e36 push -u origin HEAD
admin@adm01:~$ # même essai sur formation/git-labo
```

| Test | V1 | V2 | V3 | V4 |
|---|---|---|---|---|
| push depuis `~/medisphere` | KO | KO | KO | KO |
| push depuis un clone neuf de `plateforme/medisphere` | KO | KO | KO | **OK** |
| push vers `formation/git-labo` | **OK** | KO | **OK** | OK |
| `git remote -v` : URL de push = URL de fetch | oui | oui | oui | **non** |

Quatre causes, quatre périmètres : un réglage de **projet** (V1, V3), toute la **forge** (V2), un **clone** (V4).

**Variante 1 — règle de protection générique « `*` ».**

```
remote: GitLab: You can only create protected branches using the web interface and API.
To git01.par1.medisphere.internal:plateforme/medisphere.git
 ! [remote rejected] fix/essai-e36 -> fix/essai-e36 (pre-receive hook declined)
error: failed to push some refs to 'git01.par1.medisphere.internal:plateforme/medisphere.git'
```

Le message parle de branches **protégées** alors que tu crées une branche de travail : il faut donc qu'une règle couvre son nom. **Settings > Repository > Protected branches** (ou l'API) en liste deux :

```
admin@adm01:~$ curl -s -H "PRIVATE-TOKEN: $(cat ~/.config/workbook/gitlab-checks.token)" \
    https://git01.par1.medisphere.internal/api/v4/projects/plateforme%2Fmedisphere/protected_branches \
  | jq -r '.[] | [.name, (.push_access_levels[0].access_level_description), (.merge_access_levels[0].access_level_description)] | @tsv'
main	No one	Maintainers
*	No one	Maintainers
```

La règle `*` capture **toutes** les branches. Comme personne ne peut y pousser mais que tu peux y fusionner (Maintainer), GitLab considère que tu tentes de **créer une branche protégée** par Git, ce qui n'est permis que par l'interface ou l'API. Pour une branche existante, le message aurait été « You are not allowed to push code to protected branches on this project. » Le refus s'applique à tout le monde, administrateurs compris : le niveau « No one » n'a pas d'exception (c'est ce que dit le code de GitLab, `ProtectedRefAccess#check_access`).

Cause racine : une règle de protection `*` ajoutée sur le projet (l'histoire plausible : quelqu'un voulait protéger `release/*` et a saisi `*`). Correctif : la supprimer (**Unprotect**), puis, si le besoin réel existe, créer la règle voulue. Le journal d'audit (**Admin > Monitoring > Audit events** en CE : événements limités, à vérifier sur ta version) et la date de création de la règle aident à répondre « depuis quand ». Tous les membres du projet étaient touchés ; les autres projets non.

**Variante 2 — hook global défaillant.**

```
remote: GL-HOOK-ERR: quota-depots : configuration /etc/gitlab/quota-depots.conf illisible, poussée refusée par sécurité.
 ! [remote rejected] fix/essai-e36 -> fix/essai-e36 (pre-receive hook declined)
```

Le préfixe `GL-HOOK-ERR:` désigne un hook côté serveur (selon les versions, GitLab retire le préfixe à l'affichage : à vérifier). Le même refus apparaît sur `formation/git-labo` : c'est global. Sur `git01` :

```
admin@git01:~$ sudo grep -A1 '^\[hooks\]' /var/opt/gitlab/gitaly/config.toml
[hooks]
custom_hooks_dir = "/var/opt/gitlab/gitaly/custom_hooks"
admin@git01:~$ sudo ls -l /var/opt/gitlab/gitaly/custom_hooks/pre-receive.d/
-rwxr-xr-x 1 git git  512 … 00-quota-depots
-rwxr-xr-x 1 git git 4310 … 10-messages-conventionnels
-rwxr-xr-x 1 git git 2788 … 20-taille-fichiers
```

Les hooks s'exécutent par ordre alphabétique et **le premier qui échoue arrête tout** : `00-quota-depots` passe avant les tiens. Il lit un fichier de configuration absent et refuse « par sécurité » (*fail-closed*), pour tous les projets, puisqu'il ne filtre pas sur `GL_PROJECT_PATH`. Il n'est pas versionné dans `plateforme/medisphere` (`forge/hooks/` de M01-E26) : il a été déposé à la main.

Correctif : **le retirer** du dossier actif, en le conservant pour analyse (`sudo mv … /root/quarantaine-hooks/`), puis le signaler (qui l'a déployé, pour quoi ?). Encore mieux, redéployer l'état de référence avec `forge/hooks/deployer-hooks.sh` (M01-E26), qui remplace le dossier par le contenu versionné : c'est exactement à cela que sert le versionnage des hooks. Inventer le fichier `quota-depots.conf` manquant pour « faire passer » serait corriger le symptôme d'un composant dont tu ne connais ni l'origine ni le comportement. Tout le monde était touché, sur tous les projets.

**Variante 3 — projet archivé.**

```
remote:
remote: ========================================================================
remote:
remote: ERROR: You can't push code to an archived project.
remote:
remote: ========================================================================
remote:
fatal: Could not read from remote repository.
```

Le refus arrive **avant** le transfert (contrôle d'accès de gitlab-shell, pas de `[remote rejected]`). La page du projet affiche un bandeau « This is an archived project. Repository and other project resources are read-only. » Correctif : **Settings > General > Advanced > Unarchive project**, ou `POST /projects/:id/unarchive`. Puis chercher pourquoi : un archivage est une décision (fin de vie d'un projet), pas un accident ; ici, une fausse manipulation. Tous les membres du projet étaient touchés.

**Variante 4 — URL de poussée distincte dans le clone.**

```
admin@adm01:~/medisphere$ git remote -v
origin	git@git01.par1.medisphere.internal:plateforme/medisphere.git (fetch)
origin	git@git01.par1.medisphere.internal:infoger/medisphere.git (push)
admin@adm01:~/medisphere$ git config --show-origin --get-all remote.origin.pushurl
file:.git/config	git@git01.par1.medisphere.internal:infoger/medisphere.git
```

Le message (« ERROR: The project you were looking for could not be found or you don't have permission to view it. ») parle d'un projet **introuvable** : c'est vrai, `infoger/medisphere` n'existe pas. `remote.origin.pushurl` remplace l'URL de poussée sans toucher à celle de récupération, d'où un `fetch` qui marche. Seul ton clone était touché : le clone neuf de l'étape 2 poussait sans problème.

Correctif : `git remote set-url --delete --push origin git@git01.par1.medisphere.internal:infoger/medisphere.git` (ou `git config --unset remote.origin.pushurl`), puis `git remote -v`. Vérifie aussi `~/.gitconfig` : la même panne existe en version globale avec `url.<base>.pushInsteadOf`, encore plus discrète.

**Vérification** : `lab/bin/check 01 36`, puis la MR de ta branche de test (que tu fermes) ; supprime `/tmp/e36` et les branches d'essai (`git push origin --delete fix/essai-e36`).

**Prévention**
- Sonde de poussée (« Pour aller plus loin ») sur un projet de test, dans **chaque** groupe concerné : elle aurait détecté V2 en 15 minutes, V1 et V3 si elle visait `plateforme/medisphere`, jamais V4 (problème de poste).
- Réglages de projet en code : l'état attendu des protections (M01-E11, script `gitlab-proteger-projet.sh`) rejoué chaque nuit en mode comparaison, avec alerte sur toute différence. Le module 05 fera la même chose avec OpenTofu (provider GitLab).
- Hooks globaux : uniquement déployés depuis le dépôt (`deployer-hooks.sh`), et un contrôle qui compare le dossier actif à `forge/hooks/` (somme de contrôle) ; un hook doit filtrer son périmètre et se tester avec une poussée vide (c'est ce que fait `lab/bin/check 01 36`).

**Explications**

Un push en SSH traverse : la configuration du clone (URL de push) → `ssh` → sshd et `gitlab-shell` (authentification, **contrôles d'accès au projet** : existe-t-il, as-tu le droit d'écrire, est-il archivé ?) → Gitaly `receive-pack`, qui reçoit les objets puis lance la phase **pre-receive** : les contrôles de GitLab sur chaque référence (branche protégée, étiquette protégée, taille…, appel à l'API interne `/internal/allowed`), puis les hooks personnalisés du projet et les hooks globaux. Les contrôles d'accès au projet échouent avant le transfert (message encadré de gitlab-shell) ; ceux sur les références échouent après le transfert, avec `[remote rejected] … (pre-receive hook declined)` : cette formule de Git ne veut **pas** dire qu'un hook personnalisé a refusé.

**Alternatives**
- `GIT_TRACE_PACKET=1 git push` montre l'échange de protocole et l'instant exact du refus.
- Côté serveur, `sudo gitlab-ctl tail gitlab-shell` et `sudo gitlab-ctl tail gitaly` pendant la tentative montrent la décision et sa raison, même quand le client affiche peu.

**Pièges classiques**
- Lire « pre-receive hook declined » et partir chercher dans `custom_hooks` alors que c'est une règle de protection (V1).
- « Corriger » V1 en supprimant aussi la protection de `main`, ou en passant `push` à « Maintainers » sur `*`.
- Créer `quota-depots.conf` pour faire taire le hook de V2.
- Ne regarder que la première colonne de `git remote -v` (V4).
- Désarchiver sans se demander qui a archivé et pourquoi.

**En production chez MédiSphère**

La forge est un service de production : chaque réglage de projet et chaque hook global vient d'un dépôt, passe en revue et est appliqué par un outil (scripts du module, OpenTofu au M05, Ansible au M04 pour `git01`). Une sonde de poussée par groupe alimente la supervision (M21), et les événements d'audit de GitLab (création de protections, archivage) sont collectés avec les journaux (M22).

---

### M01-E37 — Panne : GitLab répond « 502 »

**Démarche de diagnostic**

*Symptômes* : page d'erreur 502 pour tout le monde, sans intervention annoncée.

*Hypothèses* : GitLab en cours de démarrage (normal pendant 1 à 3 minutes) ; Puma arrêté, en boucle de redémarrage ou saturé (mémoire, OOM) ; Workhorse qui ne joint pas Puma ; NGINX qui ne joint pas Workhorse ; disque plein ; base de données injoignable (plutôt une 500).

**Étape 1 — Mesurer depuis `adm01`.**

```
admin@adm01:~$ curl -sv -o /dev/null https://git01.par1.medisphere.internal/users/sign_in 2>&1 | grep -E '^< (HTTP|Server)'
< HTTP/2 502
< server: nginx
admin@adm01:~$ git ls-remote git@git01.par1.medisphere.internal:plateforme/medisphere.git HEAD
```

L'en-tête `Server: nginx` est toujours là : NGINX répond, c'est lui qui transmet ou fabrique la 502. La page d'erreur est la même dans les trois variantes : elle ne dit pas quel maillon est en cause. Le test Git en SSH, lui, sépare déjà les variantes : il échoue en V1 et V2 (`gitlab-shell` appelle l'API interne de GitLab, servie par Puma derrière Workhorse), il **fonctionne** en V3 (gitlab-shell parle directement à la socket de Workhorse, sans passer par NGINX). Réponse à Julien : en V3 ses pushs passent, en V1 et V2 non.

**Étape 2 — État des services sur `git01`.**

```
admin@git01:~$ sudo gitlab-ctl status
run: gitaly: (pid 812) 86400s; run: log: (pid 790) 86400s
run: gitlab-workhorse: (pid 1544) 86390s; run: log: (pid 1530) 86400s
run: nginx: (pid 1601) 86385s; run: log: (pid 1590) 86400s
run: postgresql: (pid 760) 86400s; run: log: (pid 742) 86400s
run: puma: (pid 30211) 3s; run: log: (pid 1490) 86400s
…
```

Tout est `run:`. Mais relance la commande dix secondes plus tard : en **V2**, Puma a un nouveau PID et une durée de 1 à 5 secondes à chaque fois. Un service qui redémarre en boucle apparaît « en marche » à chaque instant. En V1, Puma tourne depuis le redémarrage de l'injection et ne bouge plus ; en V3, rien n'a redémarré.

**Étape 3 — Remonter la chaîne par les journaux.** Pendant un `curl` depuis `adm01` :

```
admin@git01:~$ sudo gitlab-ctl tail nginx            # puis gitlab-workhorse, puis puma
```

*Variante 1 — Puma écoute ailleurs que là où Workhorse l'attend.*

Workhorse (`/var/log/gitlab/gitlab-workhorse/current`, JSON) :

```
{"error":"badgateway: failed to receive response: dial unix /var/opt/gitlab/gitlab-rails/sockets/gitlab.socket: connect: no such file or directory","level":"error","method":"GET","msg":"","uri":"/users/sign_in", …}
```

Puma (`/var/log/gitlab/puma/puma_stdout.log` ou `current`) :

```
* Listening on unix:///var/opt/gitlab/gitlab-rails/sockets/gitlab.sock
* Listening on http://127.0.0.1:8080
```

```
admin@git01:~$ sudo ls -l /var/opt/gitlab/gitlab-rails/sockets/
srwxrwxrwx 1 git git 0 … gitlab.sock
admin@git01:~$ sudo grep -n "^bind" /var/opt/gitlab/gitlab-rails/etc/puma.rb
NN:bind 'unix:///var/opt/gitlab/gitlab-rails/sockets/gitlab.sock'
```

Workhorse cherche `gitlab.socket` (valeur par défaut de `puma['socket']`), Puma écoute sur `gitlab.sock`. Le fichier fautif est `/var/opt/gitlab/gitlab-rails/etc/puma.rb`, **généré** à partir de `gitlab.rb` : quelqu'un l'a modifié à la main (sa date de modification est postérieure au dernier `reconfigure`). Workhorse ne se rabat pas sur l'écoute TCP 8080 de Puma : quand une socket est configurée, il l'utilise seule.

*Variante 2 — Puma ne peut pas créer sa socket.*

Puma (`sudo gitlab-ctl tail puma`) en boucle :

```
… Errno::EACCES: Permission denied @ rb_sysopen - /var/opt/gitlab/gitlab-rails/sockets/gitlab.socket
```

(ou `Permission denied - bind(2)`, selon la version). Workhorse : `dial unix …/gitlab.socket: connect: permission denied` ou `no such file or directory`.

```
admin@git01:~$ sudo stat -c '%U:%G %a %n' /var/opt/gitlab/gitlab-rails/sockets
root:root 700 /var/opt/gitlab/gitlab-rails/sockets
```

Puma tourne sous l'utilisateur `git` : il ne peut plus écrire dans ce dossier, ni même le traverser. La recette omnibus le crée normalement avec le propriétaire `git` et le mode `0750` (fichier `recipes/puma.rb` du paquet). Un `chown -R`/`chmod -R` « de durcissement » trop large est l'histoire la plus probable.

*Variante 3 — NGINX ne trouve pas Workhorse.*

Workhorse et Puma ne voient **aucune** requête. NGINX (`/var/log/gitlab/nginx/gitlab_error.log`) :

```
… [crit] … connect() to unix:/var/opt/gitlab/gitlab-workhorse/socket failed (2: No such file or directory) while connecting to upstream, … upstream: "http://unix:/var/opt/gitlab/gitlab-workhorse/socket:/users/sign_in" …
```

```
admin@git01:~$ sudo ls /var/opt/gitlab/gitlab-workhorse/sockets/
socket
admin@git01:~$ sudo grep -rn "gitlab-workhorse" /var/opt/gitlab/nginx/conf/ | grep server
…: server unix:/var/opt/gitlab/gitlab-workhorse/socket;
```

L'amont `gitlab-workhorse` de la configuration NGINX **générée** pointe vers `…/gitlab-workhorse/socket` au lieu de `…/gitlab-workhorse/sockets/socket`. NGINX a été rechargé (`hup`) après la modification : il ne vérifie pas l'existence des sockets amont au chargement.

**Étape 4 — Correctif.** Les trois variantes ont la même famille de cause (un fichier ou un dossier géré par omnibus modifié à la main) et le même correctif sûr : **rejouer la configuration**.

```
admin@git01:~$ sudo ls -l --time-style=full-iso /etc/gitlab/gitlab.rb      # pas modifié depuis le dernier reconfigure ?
admin@git01:~$ sudo cp -a /etc/gitlab/gitlab.rb /root/gitlab.rb.$(date +%F-%H%M)
admin@git01:~$ sudo gitlab-ctl reconfigure 2>&1 | tee /tmp/reconfigure-inc2782.log | grep -E 'puma.rb|gitlab-http|sockets|Recipe|Running handlers'
admin@git01:~$ sudo gitlab-ctl restart puma        # V1, V2 : si reconfigure ne l'a pas redémarré
```

`reconfigure` affiche les différences qu'il applique : c'est la **preuve** de la modification à la main (`- bind 'unix:///…/gitlab.sock'` / `+ bind 'unix:///…/gitlab.socket'`, ou le changement de propriétaire du dossier). Garde cette sortie dans ton journal. Pour la V3, NGINX est rechargé par `reconfigure`. Compte 1 à 3 minutes avant que Puma réponde.

Correction à la main (remettre la ligne, `chown git:… && chmod 0750`, puis redémarrer) : acceptable en urgence, mais tu corriges ce que tu as vu, alors que `reconfigure` remet **tout** en conformité avec `gitlab.rb`, y compris ce que tu n'as pas vu. C'est pour cela que l'énoncé demande de vérifier d'abord que `gitlab.rb` n'a pas été modifié depuis la dernière application.

**Vérification** : `lab/bin/check 01 37` ; depuis `git01`, `curl -s --resolve git01.par1.medisphere.internal:443:127.0.0.1 https://git01.par1.medisphere.internal/-/readiness` (la sonde n'est servie qu'aux adresses de `gitlab_rails['monitoring_whitelist']`, 127.0.0.0/8 par défaut) ; `sudo gitlab-rake gitlab:check SANITIZE=true` pour un contrôle large.

**Prévention**
- Contrôle de dérive : `sudo gitlab-ctl reconfigure` n'a pas de mode « à blanc » officiel ; on surveille donc les fichiers générés (somme de contrôle après chaque `reconfigure` réussi, comparée chaque nuit) et on interdit les modifications manuelles par procédure (et par Ansible au M04, qui gérera `gitlab.rb`).
- Sondes : HTTP 200 sur `/users/sign_in` depuis `adm01` (point de vue utilisateur) **et** `/-/readiness` depuis `git01` (point de vue interne), toutes les minutes ; alerte sur l'uptime de Puma inférieur à 2 minutes trois fois de suite (boucle de redémarrage). L'E30 a posé les bases (*exporters*, sondes).

**Explications**

Chaîne d'une requête HTTPS : NGINX (TLS, port 443) → Workhorse (socket `/var/opt/gitlab/gitlab-workhorse/sockets/socket`, gère les transferts lourds : Git en HTTP, téléversements, archives) → Puma (application Rails, socket `/var/opt/gitlab/gitlab-rails/sockets/gitlab.socket`). Une 502 signifie « un mandataire n'a pas obtenu de réponse valable de son amont » : elle peut venir de NGINX (V3) ou de Workhorse (V1, V2). Les journaux de chaque maillon disent lequel. Git en SSH ne passe que par sshd → gitlab-shell → (API interne via Workhorse) → Gitaly : c'est un chemin de contrôle indépendant de NGINX.

**Alternatives**
- `sudo ss -xlp | grep -E 'gitlab|workhorse'` montre qui écoute sur quelle socket Unix, en une commande (V1 se voit immédiatement).
- `sudo gitlab-ctl tail` sans argument mélange tous les journaux : utile pour la chronologie, pénible pour l'analyse.

**Pièges classiques**
- Redémarrer toute la forge (`gitlab-ctl restart`) : V2 continue, V1 et V3 aussi (le fichier modifié reste), et on a perdu dix minutes.
- Conclure « Puma est en marche » sur une seule lecture de `gitlab-ctl status` (V2).
- Corriger le fichier généré à la main sans comprendre que le prochain `reconfigure` (ou la prochaine mise à jour, E29) le réécrira : bon ici, mais dangereux quand la modification manuelle était **voulue** par quelqu'un (alors elle doit migrer dans `gitlab.rb`).
- Lancer `reconfigure` sans vérifier que `gitlab.rb` est celui qu'on croit.
- Confondre 502 (amont injoignable) et 500 (erreur de l'application, voir `production.log` et `exceptions_json.log`) ou 503 (sonde de disponibilité en échec).

**En production chez MédiSphère**

`git01` est géré par Ansible à partir du M04 : `gitlab.rb` vient d'un modèle versionné, `reconfigure` n'est lancé que par le rôle, et les fichiers générés ne sont jamais touchés. Toute modification d'urgence est reportée dans `gitlab.rb` dans la journée, par MR. Le runbook « GitLab répond 502 » (section de RB-013, mini-projet) suit exactement l'ordre de l'étape 3.

---

### M01-E38 — Panne : le runner ne prend plus les jobs

**Démarche de diagnostic**

*Symptômes* : jobs de MR en attente (*pending*) indéfiniment.

*Hypothèses* : runner arrêté ; runner qui ne joint pas GitLab (DNS, réseau, TLS) ; jeton refusé ; runner en pause ; incompatibilité entre le job et le runner (étiquettes, branche protégée, jobs sans étiquette) ; runner saturé (`concurrent`).

**Étape 1 — Ce que dit GitLab du job.** Sur un job en attente :

```
This job is stuck because of one of the following problems. There are no active runners online,
no runners for the protected branch, or no runners that match all of the job's tags: shell
```

(formulation exacte selon la version). Le test sur `main` sépare déjà V4 : le pipeline de `main` **passe**, celui de la MR non.

**Étape 2 — Le runner vu par GitLab.**

```
admin@adm01:~$ T=$(cat ~/.config/workbook/gitlab-checks.token)
admin@adm01:~$ curl -s -H "PRIVATE-TOKEN: $T" "https://git01.par1.medisphere.internal/api/v4/runners/all?type=instance_type" \
  | jq '.[] | {id, description, status, paused, tag_list}'
admin@adm01:~$ curl -s -H "PRIVATE-TOKEN: $T" https://git01.par1.medisphere.internal/api/v4/runners/<ID> \
  | jq '{status, contacted_at, tag_list, access_level, run_untagged, paused}'
```

**Étape 3 — Le runner vu de `runner01`.**

```
admin@runner01:~$ systemctl status gitlab-runner --no-pager
admin@runner01:~$ sudo journalctl -u gitlab-runner --since -10min --no-pager | tail -n 20
admin@runner01:~$ sudo gitlab-runner verify
```

| Observation | V1 | V2 | V3 | V4 |
|---|---|---|---|---|
| Journal du runner | `dial tcp 10.10.20.120:443: … no route to host` (ou délai) | `… forbidden` / `403 Forbidden` | calme | calme |
| `gitlab-runner verify` | erreur de connexion | `is not valid` | `is valid` | `is valid` |
| Étiquettes du runner | `shell, socle` | `shell, socle` | **`bash, socle`** | `shell, socle` |
| `access_level` | `not_protected` | `not_protected` | `not_protected` | **`ref_protected`** |
| Pipeline de `main` | bloqué | bloqué | bloqué | **passe** |

Le statut « en ligne » ne t'aide pas en V1 et V2 : GitLab garde un runner « online » tant qu'il l'a contacté dans les deux dernières heures (valeur à vérifier sur ta version). C'est le champ `contacted_at`, qui ne bouge plus, qui trahit la panne.

**Variante 1 — le runner joint une mauvaise adresse.**

```
admin@runner01:~$ getent hosts git01.par1.medisphere.internal
10.10.20.120    git01.par1.medisphere.internal git01
admin@runner01:~$ grep -n git01 /etc/hosts
NN:# Migration forge (InfoGér, INF-4402) — à retirer après bascule
NN+1:10.10.20.120	git01.par1.medisphere.internal git01
```

`/etc/hosts` passe avant le DNS (`hosts: files dns` dans `/etc/nsswitch.conf`). L'entrée renvoie le nom de la forge vers une adresse qui ne répond pas. Le service a été redémarré : les connexions déjà ouvertes vers la bonne adresse ont disparu, d'où une panne franche. Correctif : retirer l'entrée (après avoir vérifié qu'elle ne sert à rien d'autre), sans redémarrer : le runner relit la résolution à la connexion suivante. Vérifie avec `getent hosts` et le journal.

**Variante 2 — jeton refusé.** Le journal montre des `403 Forbidden` toutes les trois secondes. Le jeton de `/etc/gitlab-runner/config.toml` ne correspond plus à aucun runner de GitLab. Il diffère d'un caractère de celui que GitLab connaît : une mauvaise copie (restauration d'un `config.toml` de travail, édition à la main). On ne peut pas relire le vrai jeton dans GitLab (il n'est affiché qu'à la création). Deux corrections propres :
- restaurer `config.toml` depuis la sauvegarde de `runner01` (VM sauvegardée chaque nuit par `lab-nuit`, M00) si elle est saine ;
- sinon, **réinitialiser le jeton d'authentification** du runner dans GitLab (**Admin > CI/CD > Runners > le runner > Edit** ; l'API propose aussi `POST /runners/:id/reset_authentication_token`, à vérifier sur ta version) et reporter le nouveau jeton dans `config.toml` (root:root 600). Le runner garde son identifiant, ses étiquettes et son historique, contrairement à un réenregistrement.

Le runner relit `config.toml` automatiquement quand le fichier change ; `sudo gitlab-runner verify` confirme.

**Variante 3 — étiquette renommée.** Le job demande `tags: [shell]` (gabarit `templates/qualite.yml`), le runner porte `bash` et `socle` : aucun runner ne porte **toutes** les étiquettes du job. Correctif : remettre l'étiquette `shell` sur le runner (interface ou `PUT /runners/:id` avec `tag_list`). Changer les gabarits CI pour demander `bash` serait corriger le mauvais côté : les étiquettes sont un contrat entre l'équipe et la flotte de runners, défini en E23.

**Variante 4 — runner réservé aux branches protégées.** `access_level: ref_protected` (case « Protected » dans l'interface) : le runner ne prend que les jobs des références protégées, donc les pipelines de `main` et pas ceux des MR. Correctif : `PUT /runners/:id` avec `access_level=not_protected`. C'est pourtant un réglage **utile** dans d'autres contextes : un runner qui détient des secrets de déploiement ne doit servir que des branches protégées. Ici, ce n'est pas son rôle (E23).

**Vérification** : `lab/bin/check 01 38`, puis relance du pipeline de la MR.

**Prévention**
- Sonde « jobs en attente depuis plus de 5 minutes » (« Pour aller plus loin ») plutôt que « runner en ligne ».
- `config.toml` et réglages du runner décrits en code (Ansible au M04 ; réglages GitLab au M05) ; `/etc/hosts` des VMs du socle géré et vérifié (aucune entrée hors `localhost` et le nom propre de l'hôte).
- Jamais de réenregistrement à l'aveugle : il crée un nouveau runner, laisse l'ancien orphelin, et efface la preuve.

**Explications**

Le runner fait du **long polling** : il appelle `POST /api/v4/jobs/request` avec son jeton toutes les `check_interval` secondes (3 par défaut). GitLab lui attribue un job seulement si toutes les conditions sont réunies : runner actif, étiquettes du job ⊆ étiquettes du runner, job non étiqueté accepté si `run_untagged`, référence protégée si le runner est `ref_protected`. GitLab ne contacte jamais le runner : c'est pour cela que le flux n'existe que dans le sens `runner01` → `git01` (443), et qu'un runner peut vivre derrière un NAT.

**Alternatives**
- `sudo gitlab-runner --debug run` (après arrêt du service) affiche chaque requête : utile pour V1 et V2, inutile pour V3 et V4 où le runner fonctionne parfaitement de son point de vue.
- Côté GitLab, `GET /runners/:id/managers` (gestionnaires d'un runner, avec leur dernier contact et leur adresse) : à vérifier sur ta version.

**Pièges classiques**
- Se fier au statut « online » (V1, V2).
- Réenregistrer le runner (« ça marche », sauf qu'il y a maintenant deux runners et que la cause est inconnue).
- Modifier les `tags:` des gabarits CI (V3) ou désactiver la protection d'un runner qui devrait l'avoir dans un autre contexte.
- Oublier que `/etc/hosts` passe avant le DNS (V1).

**En production chez MédiSphère**

Plusieurs runners par usage (qualité, release, déploiement), les runners de déploiement en `ref_protected` avec des étiquettes dédiées, et une alerte sur la file d'attente des jobs. Au module 19, les runners passent sur Kubernetes : le diagnostic reste le même (qui interroge qui, avec quel jeton, pour quelles étiquettes).

---

### M01-E39 — Panne : la release automatique échoue

**Démarche de diagnostic**

*Symptômes* : après fusion de la MR de Karim, pas de nouvelle version ; job `release` en échec.

*Hypothèses* (dans l'ordre du job) : le job ne tourne pas (règles) ; la variable `GITLAB_TOKEN` n'arrive pas dans le job ; le jeton est invalide (révoqué, expiré) ; le jeton n'a pas les droits ; les outils manquent sur le runner ; semantic-release ne trouve rien à publier ; la poussée de l'étiquette est refusée ; la publication de la Release échoue.

**Étape 1 — Le premier message d'erreur du job.**

| Variante | Premier message utile (journal du job `release`) | Étape |
|---|---|---|
| V1 | `[semantic-release] › ✘  EINVALIDGLTOKEN Invalid GitLab token.` | vérification des conditions (plugin GitLab) |
| V2 | `remote: GitLab: You are not allowed to create this tag as it is protected.` puis l'échec de `git push --tags` | publication de l'étiquette |
| V3 | `npm error missing: @semantic-release/gitlab@13.3.3, required by medisphere-release-tools@1.0.0` | script du job, avant semantic-release |
| V4 | `GITLAB_TOKEN absent : crée la variable CI du projet (protégée, masquée) avec le jeton bot-release.` | script du job, avant semantic-release |

En V3 et V4, semantic-release n'a même pas démarré : le message vient des lignes `npm ls` et du test de variable du gabarit `templates/release.yml` (M01-E25). Lire le journal **du haut** évite de chercher dans semantic-release une erreur qui n'y est pas.

**Étape 2 — Vérifier chaque maillon, avec une preuve.**

```
admin@adm01:~$ T=$(cat ~/.config/workbook/gitlab-checks.token); P=plateforme%2Fmedisphere; U=https://git01.par1.medisphere.internal/api/v4
admin@adm01:~$ curl -s -H "PRIVATE-TOKEN: $T" "$U/projects/$P/access_tokens?per_page=100" \
  | jq '.[] | select(.name == "bot-release") | {id, active, revoked, created_at, last_used_at, expires_at, access_level, scopes}'
admin@adm01:~$ curl -s -H "PRIVATE-TOKEN: $T" "$U/projects/$P/variables/GITLAB_TOKEN" | jq '{protected, masked, environment_scope}'
admin@adm01:~$ curl -s -H "PRIVATE-TOKEN: $T" "$U/projects/$P/protected_tags" | jq '.[] | {name, create_access_levels}'
admin@runner01:~$ npm ls --prefix /opt/release-tools --depth=0
```

(La lecture des variables demande le rôle Maintainer ; la valeur n'est jamais nécessaire au diagnostic : ne l'affiche pas.)

**Variante 1 — jeton renouvelé, variable restée sur l'ancien.** Deux jetons `bot-release` : l'ancien `revoked: true`, le nouveau actif, créé hier, `last_used_at: null`. La variable contient l'ancien. Un renouvellement (*rotate*) révoque l'ancien jeton **immédiatement** : celui qui l'a fait n'a pas mis la variable à jour (ou n'a pas noté le nouveau jeton, affiché une seule fois).

Correctif : renouveler à nouveau (le jeton actif est inconnu de tous, il est inutilisable), en copiant la nouvelle valeur **directement** dans la variable :

```
admin@adm01:~$ A=$(cat ~/.config/workbook/gitlab-admin.token)
admin@adm01:~$ ID=$(curl -s -H "PRIVATE-TOKEN: $A" "$U/projects/$P/access_tokens?state=active" | jq -r '.[] | select(.name=="bot-release") | .id')
admin@adm01:~$ curl -sf -X POST -H "PRIVATE-TOKEN: $A" "$U/projects/$P/access_tokens/$ID/rotate" | jq -j .token \
  | curl -sf -X PUT -H "PRIVATE-TOKEN: $A" "$U/projects/$P/variables/GITLAB_TOKEN" --data-urlencode value@- >/dev/null \
  && echo "jeton renouvelé et variable mise à jour"
```

Le jeton ne passe ni par l'écran, ni par un fichier, ni par l'historique du shell. L'interface (**Settings > Access tokens > Rotate**, puis **CI/CD > Variables > Edit**) convient aussi, à condition de ne coller la valeur nulle part ailleurs.

**Variante 2 — étiquettes `v*` interdites à la création.** semantic-release calcule bien la version (`The next release version is 1.4.1`), crée l'étiquette localement, et la poussée est refusée par GitLab. Les étiquettes protégées : `v*` avec `create_access_levels: [{access_level: 0, "No one"}]`. Le bot est Maintainer, mais « No one », c'est personne. L'API n'a pas de modification d'une protection d'étiquette : on la retire et on la recrée avec le bon niveau (dans l'interface : **Unprotect**, puis **Protect** `v*` avec « Maintainers »). Pendant les quelques secondes entre les deux, les étiquettes `v*` ne sont pas protégées : fais-le hors de toute release en cours (le `resource_group: release` du gabarit sérialise les jobs `release`, pas les actions humaines).

Point d'attention : semantic-release a créé l'étiquette **dans le clone du job** seulement ; rien n'est resté côté serveur. Relancer le job suffit.

**Variante 3 — plugin absent sur le runner.** `npm ls` liste `@semantic-release/gitlab` comme manquant (UNMET/missing). Le dossier `/opt/release-tools/node_modules/@semantic-release/gitlab` n'existe plus. Correctif : **réinstaller exactement** les outils figés par `package-lock.json` avec le script de M01-E24 (`sudo outils/release-tools/installer-release-tools.sh` depuis un clone de `plateforme/ci-templates`), pas un `npm install @semantic-release/gitlab` à la main qui prendrait une autre version que celle du verrou. Cherche ensuite qui a touché au dossier (il appartient à root et n'est pas modifiable par `gitlab-runner` : c'est donc une intervention d'administrateur).

**Variante 4 — variable limitée à un environnement.** La variable existe, protégée et masquée, mais `environment_scope: production`. Le job `release` ne déclare pas d'environnement (`environment:`) : il ne reçoit que les variables de portée `*`. Correctif : remettre la portée à « All (default) » (`*`). Si l'équipe veut un jour limiter les secrets par environnement (module 20), le job devra alors déclarer le sien.

**Étape 3 — Relancer et vérifier la publication.** Relance le job `release` du pipeline de `main` (ou tout le pipeline) :

```
[semantic-release] › ℹ  Found 1 commits since last release
[semantic-release] [@semantic-release/commit-analyzer] › ℹ  Analysis of 1 commits complete: patch release
[semantic-release] › ℹ  The next release version is 1.4.1
[semantic-release] › ✔  Created tag v1.4.1
[semantic-release] [@semantic-release/gitlab] › ℹ  Published GitLab release: v1.4.1
```

Puis la page **Deploy > Releases**, l'étiquette protégée, et le commentaire du bot sur la MR fusionnée.

**Réponse à la question 6** : le pipeline de la MR était vert parce que le job `release` ne tourne que sur la branche par défaut protégée (`rules:` du gabarit) ; aucune étape de la MR n'utilise le jeton, la variable protégée (absente des branches non protégées) ou la protection des étiquettes. La chaîne de release n'est testée **qu'en production**, à la fusion. Détection possible : un job planifié quotidien sur `main` qui lance `semantic-release --dry-run` (il vérifie les conditions, dont le jeton, sans rien publier) et un contrôle de l'expiration du jeton.

**Vérification** : `lab/bin/check 01 39`.

**Prévention**
- Procédure de rotation **outillée** (le pipeline de l'étape 1 de V1), jamais à la main en deux temps.
- Job planifié `semantic-release --dry-run` sur `main`, et alerte 30 jours avant l'expiration de `bot-release`.
- `/opt/release-tools` installé par script (et par Ansible au M04), vérifié par `npm ls` à chaque job (c'est déjà le cas : V3 est **détectée** par le gabarit, ce qui a rendu le diagnostic immédiat).
- Réglages du projet (protections, variables : drapeaux et portée, pas les valeurs) comparés chaque nuit à l'état attendu.

**Explications**

semantic-release enchaîne : `verifyConditions` (chaque plugin vérifie ses prérequis ; `@semantic-release/gitlab` appelle l'API avec le jeton et vérifie le niveau d'accès au projet), `analyzeCommits` (version suivante), `generateNotes`, création et **poussée de l'étiquette** (par Git, avec le jeton dans l'URL), puis `publish` (Release GitLab) et `success` (commentaires). Chaque variante casse un maillon différent ; le message d'erreur et le moment où il apparaît suffisent à les distinguer, à condition de lire le journal depuis le début.

**Alternatives**
- Tester le jeton sans l'exposer : un job manuel (`when: manual`, branche protégée) qui appelle `curl -sf -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$CI_API_V4_URL/projects/$CI_PROJECT_ID"` et n'affiche que le code de retour.
- `semantic-release --dry-run --no-ci` sur un clone local, avec un jeton de test : vérifie `verifyConditions` et l'analyse sans publier.

**Pièges classiques**
- Mettre ton jeton personnel d'administrateur dans `GITLAB_TOKEN` « pour que ça marche » : il donne tous les droits sur toute la forge à chaque job de `main`, et il expirera avec ton compte.
- Créer l'étiquette à la main : semantic-release publiera ensuite la version **suivante**, la Release de celle-ci n'aura pas de notes, et l'historique des versions devient faux.
- Supprimer la protection des étiquettes `v*` au lieu de la corriger.
- Afficher la valeur de la variable dans un job (`echo $GITLAB_TOKEN`) : masquée dans le journal, mais la pratique est mauvaise et le masquage ne protège pas contre une transformation (`base64`).

**En production chez MédiSphère**

Les jetons d'automatisation ont un propriétaire, une date d'expiration suivie, et une procédure de rotation outillée et testée. Au module 25, ils viendront de Vault (jetons à durée de vie courte, émis à la demande), ce qui supprime la rotation manuelle.

---

### M01-E40 — Panne : clone et push en SSH impossibles

**Démarche de diagnostic**

*Symptômes* : `git clone` et `git push` en SSH échouent depuis `adm01` ; l'interface web fonctionne.

*Hypothèses* : configuration SSH du client (hôte, port, rebond, identité) ; clé d'hôte inconnue ou différente ; clé utilisateur refusée (supprimée de GitLab, expirée) ; compte système `git` inutilisable (verrouillé, expiré, shell) ; `gitlab-shell` défaillant ; sshd de `git01` (configuration, `AllowUsers`) ; filtrage du port 22.

**Étape 1 — La commande la plus courte, en verbeux.**

```
admin@adm01:~$ ssh -vT git@git01.par1.medisphere.internal 2>&1 | less
```

En temps normal, elle se termine par `Welcome to GitLab, @<MOI>!` et un code de sortie 0. La dernière étape réussie dans la sortie verbeuse classe la panne :

| Dernière étape visible | Variante | Où chercher |
|---|---|---|
| `Reading configuration data …` puis `Setting implicit ProxyCommand from ProxyJump` et `Could not resolve hostname bastion-infoger.medisphere.internal` | V4 | `~/.ssh/config` sur `adm01` |
| `Server host key: ssh-ed25519 SHA256:…` puis `REMOTE HOST IDENTIFICATION HAS CHANGED` / `Host key verification failed.` | V2 | `~/.ssh/known_hosts` sur `adm01` |
| `Offering public key …` puis `Authentications that can continue: publickey` … `Permission denied (publickey)` | V1 (ou V3 avec recherche rapide des clés) | `git01` : sshd, compte `git` |
| `Authenticated to git01.par1.medisphere.internal` puis une erreur de `gitlab-shell` | V3 | `git01` : `gitlab-shell` |

**Étape 2 — Comparer avec l'accès d'administration.**

```
admin@adm01:~$ ssh -G git01 | grep -iE '^(hostname|user|port|proxyjump|identityfile) '
admin@adm01:~$ ssh -G git01.par1.medisphere.internal | grep -iE '^(hostname|user|port|proxyjump|identityfile) '
```

`ssh git01` vise l'alias (adresse IP, utilisateur `admin`, entrée `known_hosts` de l'IP) ; Git vise le **nom** `git01.par1.medisphere.internal` avec l'utilisateur `git` (entrée `known_hosts` du nom, blocs `Host` qui correspondent au nom). Les deux chemins se séparent sur la configuration, la clé d'hôte enregistrée et le compte distant : c'est pour cela que ton accès d'administration fonctionne encore dans les quatre variantes.

**Variante 1 — compte `git` expiré.** Sur `git01` :

```
admin@git01:~$ sudo journalctl -u ssh --since -10min --no-pager | tail -n 5
… sshd[…]: User git account has expired
… sshd[…]: Failed publickey for git from 10.10.10.10 port … ssh2: ED25519 SHA256:…
admin@git01:~$ sudo chage -l git | grep -i expire
Account expires						: Jan 01, 1970
```

(formulations à vérifier ; selon la locale, `chage` affiche en français). sshd refuse toute authentification pour un compte dont la date d'expiration (champ 8 de `/etc/shadow`) est passée, avant même d'examiner la clé. Correctif : `sudo chage -E -1 git` (aucune expiration). Puis chercher qui a fait ça : un script de « purge des comptes inactifs » qui ne connaît pas les comptes de service est l'histoire classique ; il faudra l'exclure.

**Variante 2 — clé d'hôte différente pour le nom de la forge.**

```
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
…
The fingerprint for the ED25519 key sent by the remote host is
SHA256:<EMPREINTE-PRÉSENTÉE>.
…
Offending ED25519 key in /home/admin/.ssh/known_hosts:NN
Host key verification failed.
```

**Ne supprime rien tout de suite.** Compare l'empreinte présentée avec la vraie, obtenue par un chemin indépendant :

```
admin@adm01:~$ ssh git01 ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
256 SHA256:<EMPREINTE-RÉELLE> root@git01 (ED25519)
admin@adm01:~$ ssh-keygen -F git01.par1.medisphere.internal -lf ~/.ssh/known_hosts
admin@adm01:~$ ssh-keygen -F 10.10.20.12 -lf ~/.ssh/known_hosts
```

Ici, l'empreinte **présentée** est la vraie (elle est identique à celle lue sur `git01` et à celle enregistrée pour 10.10.20.12) : c'est l'entrée enregistrée pour le **nom** qui est fausse. Le serveur n'a pas changé, ton fichier `known_hosts` a été altéré (restauration d'un vieux fichier, édition maladroite). Si l'empreinte présentée avait différé de celle lue sur `git01`, c'était une interception ou un serveur substitué : on arrête tout et on prévient Sophie.

Correctif, une fois la vérification faite et notée dans le journal :

```
admin@adm01:~$ ssh-keygen -R git01.par1.medisphere.internal
admin@adm01:~$ ssh -o StrictHostKeyChecking=ask -T git@git01.par1.medisphere.internal   # compare l'empreinte proposée, accepte
```

**Variante 3 — `gitlab-shell` ne joint plus l'API interne.** L'authentification réussit (avec le fichier `authorized_keys`, réglage par défaut), puis :

```
remote:
remote: ========================================================================
remote:
remote: ERROR: Internal API unreachable
remote:
remote: ========================================================================
```

(formulation à vérifier ; si tu as activé la recherche rapide des clés en base, `AuthorizedKeysCommand`, l'authentification elle-même échoue avec `Permission denied (publickey)`, car la recherche de la clé passe aussi par l'API). Sur `git01` :

```
admin@git01:~$ sudo tail -n 3 /var/log/gitlab/gitlab-shell/gitlab-shell.log
{"level":"error","msg":"…dial unix /var/opt/gitlab/gitlab-workhorse/workhorse.sock: connect: no such file or directory", …}
admin@git01:~$ sudo grep -n '^gitlab_url' /var/opt/gitlab/gitlab-shell/config.yml
NN:gitlab_url: "http+unix://%2Fvar%2Fopt%2Fgitlab%2Fgitlab-workhorse%2Fworkhorse.sock"
```

`gitlab_url` pointe vers une socket qui n'existe pas (la bonne : `…%2Fgitlab-workhorse%2Fsockets%2Fsocket`). `config.yml` est un fichier **généré** (son en-tête le dit : « This file is managed by gitlab-ctl. Manual changes will be erased! »). Correctif : `sudo gitlab-ctl reconfigure` (avec les précautions de M01-E37), qui le réécrit. Aucun service à redémarrer : `gitlab-shell` est lancé à chaque connexion SSH.

**Variante 4 — rebond SSH imposé par un bloc `Host`.** En tête de `~/.ssh/config` :

```
# Raccordement au bastion InfoGér (procédure INF-4411)
Host *.par1.medisphere.internal
    ProxyJump admin@bastion-infoger.medisphere.internal
```

Le bloc s'applique à **tout** nom en `.par1.medisphere.internal`, donc à la forge ; il ne s'applique pas à l'alias `git01`. Le bastion n'existe pas (`NXDOMAIN`). Correctif : retirer le bloc (ou le restreindre aux hôtes du prestataire, s'il en existe), après avoir sauvegardé le fichier. `ssh -G` confirme qu'aucun `proxyjump` ne s'applique plus.

**Vérification** : `lab/bin/check 01 40`, puis `git clone` dans `/tmp` (supprimé ensuite) et un `git push` d'une branche de travail.

**Prévention**
- `~/.ssh/config` et `known_hosts` de `adm01` sont des fichiers d'exploitation : ils seront gérés par Ansible (M04), et les clés d'hôte remplacées par des **certificats d'hôte** signés par la CA SSH de step-ca au M06 (`@cert-authority` dans `known_hosts`), ce qui supprime la vérification manuelle.
- Les comptes de service (`git`, `gitlab-runner`, `gitlab-www`…) sont exclus explicitement de toute politique d'expiration ; une sonde vérifie `ssh -T git@…` toutes les 5 minutes.
- Fichiers générés de GitLab : même contrôle de dérive qu'en M01-E37.

**Explications**

Une connexion Git en SSH, c'est : configuration du client → TCP 22 → échange de clés et **vérification de l'hôte** (le client compare la clé présentée à `known_hosts` pour le nom utilisé) → authentification de l'utilisateur `git` par clé publique (sshd vérifie le compte, puis la clé : fichier `authorized_keys` géré par GitLab, ou `AuthorizedKeysCommand`) → commande forcée `gitlab-shell` (qui identifie ta clé, demande à l'API interne si tu peux lire ou écrire le projet, puis lance Gitaly). Chaque variante casse une étape différente ; la sortie de `ssh -v` les montre dans l'ordre.

**Alternatives**
- `GIT_SSH_COMMAND="ssh -v" git ls-remote …` : même diagnostic depuis Git.
- Contournement temporaire pour continuer à travailler : clone en HTTPS avec un jeton personnel `read_repository`/`write_repository` (dans le gestionnaire d'identifiants de Git, pas dans l'URL).

**Pièges classiques**
- `ssh-keygen -R` puis acceptation de n'importe quelle nouvelle clé (V2) : c'est précisément ce qu'espère un attaquant.
- Mettre `StrictHostKeyChecking no` pour la forge « pour ne plus être embêté ».
- Tester avec `ssh git01` et conclure que SSH fonctionne : ce n'est ni le même nom, ni le même compte.
- Redémarrer sshd sur `git01` (inutile dans toutes les variantes, et risqué sans session de secours).

**En production chez MédiSphère**

L'accès Git passe par des clés **par personne**, déclarées dans GitLab, avec expiration ; les comptes de service sont inventoriés ; les clés d'hôte sont certifiées (M06). La sonde `ssh -T` fait partie des contrôles de la forge, au même titre que la sonde HTTP.

---

### M01-E41 — Panne : le dépôt local est corrompu

**Démarche de diagnostic**

*Règle préalable* : `cp -a ~/src/labo-e41 ~/src/labo-e41.avant-reparation`. Chaque tentative se fait sur l'original ; si elle aggrave, on repart de la copie.

**Étape 1 — État des lieux.** Les quatre variantes ont des signatures nettement différentes (sorties réelles, Git 2.43) :

| Commande | V1 (objet vide) | V2 (référence vide) | V3 (index abîmé) | V4 (`HEAD` vide) |
|---|---|---|---|---|
| `git status` | normal | tous les fichiers « A » (ajoutés) | `error: bad signature 0x00000000` / `fatal: index file corrupt` | `fatal: not a git repository` |
| `git log -1` | normal | `fatal: your current branch appears to be broken` | normal | `fatal: not a git repository` |
| `git fsck --full` | `error: object file .git/objects/b6/b41b16… is empty` … `missing blob b6b41b16…` | `error: refs/heads/feature/sauvegarde-gitlab: invalid sha1 pointer 0000…` / `invalid HEAD` | `fatal: index file corrupt` | `fatal: not a git repository` |
| `git push` | `fatal: unable to read b6b41b16…` | `… cannot be resolved to branch` | **fonctionne** | `fatal: not a git repository` |

**Étape 2 — Ce qui est en danger, et où l'information survit.**

*Variante 1 — objet libre tronqué.* L'objet `b6b41b16…` est le blob de `scripts/sauvegarde-gitlab.sh` dans `HEAD` (`git ls-tree HEAD scripts/` le montre). Il n'est pas sur l'origine (les 3 commits n'ont jamais été poussés). Mais `git status` ne signale aucune modification de ce fichier : le contenu de l'**arbre de travail** est exactement celui du commit. Or l'empreinte d'un blob ne dépend que de son contenu : on peut le recréer.

```
admin@adm01:~/src/labo-e41$ git hash-object scripts/sauvegarde-gitlab.sh
b6b41b16cd6cac00549cd5bce119cf71eea720c8                  # même empreinte : c'est bien ce contenu
admin@adm01:~/src/labo-e41$ git hash-object -w scripts/sauvegarde-gitlab.sh
admin@adm01:~/src/labo-e41$ git fsck --full                 # toujours en erreur !
admin@adm01:~/src/labo-e41$ mv .git/objects/b6/b41b16cd6cac00549cd5bce119cf71eea720c8 ~/objet-corrompu-b6b41b
admin@adm01:~/src/labo-e41$ git hash-object -w scripts/sauvegarde-gitlab.sh
admin@adm01:~/src/labo-e41$ git fsck --full && echo intègre
```

Le premier `hash-object -w` ne fait rien : Git voit qu'un fichier existe déjà pour cette empreinte et se contente de le « rafraîchir » (date). Il faut **mettre de côté** le fichier abîmé, puis réécrire (vérifié en conditions réelles). Si le contenu n'avait plus été dans l'arbre de travail, les autres sources possibles étaient : un autre clone, le stash (s'il contient la même version), une sauvegarde de la machine.

*Variante 2 — référence tronquée.* La branche courante pointe vers « rien » (fichier de 0 octet), d'où les fichiers tous « ajoutés » : Git compare l'index à un commit inexistant. Les commits sont intacts. Le reflog de la branche, lui, a survécu :

```
admin@adm01:~/src/labo-e41$ tail -n 1 .git/logs/refs/heads/feature/sauvegarde-gitlab
3b5ee849… 7ebfa136c2df90b6d62588b813872c25ae95a0e4 Lucas Martin <…> 1775062800 +0200	commit: docs(runbook): détailler la restauration de gitlab-secrets.json
admin@adm01:~/src/labo-e41$ git cat-file -t 7ebfa136c2df90b6d62588b813872c25ae95a0e4    # commit : il existe
admin@adm01:~/src/labo-e41$ git update-ref refs/heads/feature/sauvegarde-gitlab 7ebfa136c2df90b6d62588b813872c25ae95a0e4
fatal: update_ref failed for ref 'refs/heads/feature/sauvegarde-gitlab': … reference broken
admin@adm01:~/src/labo-e41$ mv .git/refs/heads/feature/sauvegarde-gitlab ~/ref-cassee
admin@adm01:~/src/labo-e41$ git update-ref refs/heads/feature/sauvegarde-gitlab 7ebfa136c2df90b6d62588b813872c25ae95a0e4
admin@adm01:~/src/labo-e41$ git status && git fsck --full
```

Même logique que V1 : `update-ref` refuse de modifier une référence qu'il ne sait pas lire ; on la met de côté d'abord. Le dernier enregistrement du reflog donne la **nouvelle** valeur (deuxième colonne). Le reflog de `HEAD` (`.git/logs/HEAD`) aurait donné la même chose.

*Variante 3 — index illisible.* L'index n'est qu'un cache de l'état indexé : rien de ce qui est commité ni de ce qui est dans l'arbre de travail n'est en danger. Ce qui est perdu, c'est seulement ce qui était **indexé et pas encore commité** (ici, rien : la modification du runbook n'était pas indexée).

```
admin@adm01:~/src/labo-e41$ mv .git/index ~/index-corrompu
admin@adm01:~/src/labo-e41$ git reset          # reconstruit l'index depuis HEAD, sans toucher à l'arbre de travail
admin@adm01:~/src/labo-e41$ git status         # la modification du runbook est toujours là
```

**Surtout pas** `git reset --hard` : il reconstruirait l'index **et** écraserait la modification en cours du runbook.

*Variante 4 — `HEAD` vide.* Git ne reconnaît un dossier `.git` comme dépôt que si `HEAD` est valide : d'où « not a git repository », alors que tout le reste est intact. La branche courante se lit dans le reflog de `HEAD` (dernière ligne : `checkout: moving from main to feature/sauvegarde-gitlab` ou dernier commit), ou simplement dans `ls .git/refs/heads/` et la description de Lucas.

```
admin@adm01:~/src/labo-e41$ tail -n 2 .git/logs/HEAD
admin@adm01:~/src/labo-e41$ echo 'ref: refs/heads/feature/sauvegarde-gitlab' > .git/HEAD
admin@adm01:~/src/labo-e41$ git status && git fsck --full
```

**Étape 3 — Prouver que rien n'est perdu, puis sécuriser.**

```
admin@adm01:~/src/labo-e41$ git log --oneline origin/main..feature/sauvegarde-gitlab     # 3 commits
admin@adm01:~/src/labo-e41$ git stash list                                                  # essai option --dry-run
admin@adm01:~/src/labo-e41$ git diff --stat                                                 # RB-010 modifié
admin@adm01:~/src/labo-e41$ git push -u origin feature/sauvegarde-gitlab
admin@adm01:~$ rm -rf ~/src/labo-e41.avant-reparation ~/objet-corrompu-* ~/ref-cassee ~/index-corrompu
```

**Vérification** : `lab/bin/check 01 41`.

**Prévention**
- Pousser tôt et souvent sur une branche de travail (même brouillon) : un commit poussé ne craint plus la coupure de courant.
- Systèmes de fichiers et Git : `core.fsync` (Git ≥ 2.36 ; par exemple `core.fsync=committed`, `core.fsyncMethod=batch`) force la synchronisation des objets et références sur disque, au prix d'un léger ralentissement. Les sauvegardes de `adm01` (M00) couvrent aussi `~/src`.

**Explications**

Un dépôt Git est un ensemble de fichiers simples : objets (compressés, nommés par leur empreinte), références (fichiers texte ou `packed-refs`), `HEAD` (texte), index (binaire, cache), reflogs (texte, une ligne par déplacement). Une coupure de courant pendant une écriture laisse typiquement un fichier vide ou tronqué. La réparation consiste à trouver une autre source de la même information : l'arbre de travail pour un blob, un reflog pour une référence, `HEAD` pour reconstruire l'index. Et à se souvenir que Git **refuse d'écraser** ce qu'il croit présent : on déplace le fichier abîmé avant de le recréer.

**Alternatives**
- Si un autre clone existe (origine, collègue), `git fetch` d'un objet manquant ne fonctionne que s'il est atteignable sur l'autre dépôt ; `.git/objects/info/alternates` permet d'emprunter les objets d'un autre dépôt local le temps de réparer (avancé, à manier avec précaution).
- `git fsck --lost-found` n'est utile qu'en complément (objets orphelins), pas pour réparer un objet corrompu.

**Pièges classiques**
- Re-cloner : on perd les 3 commits, le stash et la modification en cours (exactement ce que Lucas craignait).
- `git gc --prune=now` ou `git reflog expire` « pour nettoyer » : détruit les sources de réparation.
- `git reset --hard` pour V3.
- Supprimer l'objet ou la référence abîmés au lieu de les déplacer : on perd la possibilité d'analyser ou de revenir en arrière.

**En production chez MédiSphère**

Côté serveur, ce type de corruption est le rôle de Gitaly et des sauvegardes de GitLab (E28) ; `gitlab-rake gitlab:git:fsck` vérifie les dépôts de la forge. Côté poste, la règle d'équipe est dans `CONTRIBUTING.md` : on pousse sa branche de travail au moins chaque soir.

---

### M01-E42 — Panne : « tout mon travail a disparu »

**Démarche de diagnostic**

*Règle préalable* : copie (`cp -a`), et aucune commande de maintenance.

**Étape 1 — Reconstituer la manœuvre.** Les traces sont dans le reflog de `HEAD` (sorties réelles ; empreintes identiques chez toi, le dépôt est fabriqué à dates fixes) :

```
admin@adm01:~/src/labo-e42$ git reflog --date=iso | head -n 8
```

| Variante | Ce que montre le reflog (et `git fsck`) | Manœuvre |
|---|---|---|
| V1 | `HEAD@{0}: reset: moving to HEAD~3` ; `HEAD@{1}` = `87fe5f5` (dernier commit) | `git reset --hard HEAD~3` |
| V2 | `HEAD@{0}: checkout: moving from feature/rotation-jetons to main` ; `git branch` ne montre plus la branche | `git switch main && git branch -D feature/rotation-jetons` |
| V3 | rien dans le reflog de `HEAD` ; `git stash list` vide ; `git fsck --no-reflogs` : `dangling commit ab4a0ad…` | `git stash drop` |
| V4 | `HEAD@{0}: reset: moving to HEAD` ; `git fsck` : `dangling blob cfe1e84…` | `git add` d'un nouveau fichier, puis `git reset --hard` |

**Étape 2 — Récupérer.**

*V1 — commits retirés de la branche.* `ORIG_HEAD` (posé par `reset`) ou `HEAD@{1}` désignent l'état d'avant :

```
admin@adm01:~/src/labo-e42$ git log --oneline -4 HEAD@{1}          # vérifier avant d'agir
admin@adm01:~/src/labo-e42$ git reset --hard HEAD@{1}               # arbre de travail propre : sans risque ici
```

`git reset --hard` est sûr **parce que** `git status` est propre ; sinon, `git branch recuperation HEAD@{1}` puis fusion, ou `git reset --keep`.

*V2 — branche supprimée.* Le reflog de la branche a disparu avec elle, mais celui de `HEAD` contient la pointe de la branche au moment où on l'a quittée (ligne `checkout: moving from feature/rotation-jetons to main` : la valeur **avant** le déplacement, `HEAD@{1}`). Git l'affiche aussi au moment de `branch -D` (`Deleted branch feature/rotation-jetons (was 87fe5f5).`).

```
admin@adm01:~/src/labo-e42$ git branch feature/rotation-jetons HEAD@{1}
admin@adm01:~/src/labo-e42$ git switch feature/rotation-jetons
```

*V3 — stash supprimé.* Un stash est un commit (à deux ou trois parents) référencé par `refs/stash` ; supprimé, il devient orphelin. Avec `--no-reflogs`, `git fsck` liste aussi les objets que seuls les reflogs retiennent :

```
admin@adm01:~/src/labo-e42$ git fsck --no-reflogs 2>/dev/null | awk '/dangling commit/ {print $3}' \
    | xargs -r -n1 git log -1 --format='%H %ci %s'
ab4a0ad43a3535bf65aabc29bce56c34ebf67bc1 2026-04-07 … On feature/rotation-jetons: notes de conception de la rotation
admin@adm01:~/src/labo-e42$ git stash store -m "notes de conception de la rotation (récupéré)" ab4a0ad43a35
admin@adm01:~/src/labo-e42$ git stash show -p stash@{0}
```

`git stash store` remet le commit dans la pile de stash, sans toucher à l'arbre de travail ; `git stash apply ab4a0ad` l'appliquerait directement.

*V4 — fichier indexé jamais commité.* `git add` a créé un blob ; `git reset --hard` a vidé l'index et supprimé le fichier de l'arbre de travail (un fichier suivi par l'index est « connu » de Git, donc supprimé). Le blob est orphelin, **sans nom de fichier** (le nom était dans l'index) :

```
admin@adm01:~/src/labo-e42$ git fsck --lost-found
dangling blob cfe1e84633456e3f903c5477d8d4400633922548
admin@adm01:~/src/labo-e42$ head -n 3 .git/lost-found/other/cfe1e84633456e3f903c5477d8d4400633922548
#!/usr/bin/env bash
# Purge des jetons révoqués depuis plus de 90 jours (mode simulation par défaut).
admin@adm01:~/src/labo-e42$ cp .git/lost-found/other/cfe1e846… scripts/purge-jetons.sh && chmod +x scripts/purge-jetons.sh
admin@adm01:~/src/labo-e42$ git add scripts/purge-jetons.sh && git commit -m "feat(jetons): purger les jetons révoqués (mode simulation)"
```

Le nom du fichier se déduit du contenu (et du témoignage de Lucas) ; les droits d'exécution aussi sont perdus (le mode était dans l'index).

**Étape 3 — Vérifier et répondre à Lucas.**

```
admin@adm01:~/src/labo-e42$ git log --oneline origin/main..feature/rotation-jetons
87fe5f5 feat(jetons): produire le rapport hebdomadaire des expirations
ac7d72e docs(jetons): rappeler la mise à jour de la variable CI après rotation
bb52ad1 feat(jetons): renouveler un jeton de projet par l'API
1704d02 feat(jetons): signaler les jetons qui expirent sous 30 jours
```

Exemple de message : « Rien n'est perdu. Ta commande `git reset --hard HEAD~3` a seulement déplacé ta branche ; Git garde 30 jours au moins les commits abandonnés (reflog). Tout est revenu, vérifie `git log`. Deux réflexes : avant toute commande lue sur un forum, `git status` et `git stash list` ; et pousse ta branche de travail, même inachevée. »

**Ce que Git ne peut pas récupérer** : une modification **jamais indexée ni commitée** effacée par `git reset --hard`, `git checkout -- fichier`, `git restore` ou `git clean -fd` : aucun objet n'a jamais été créé. Seules une sauvegarde, la corbeille de l'éditeur ou l'historique local de l'IDE peuvent aider.

**Vérification** : `lab/bin/check 01 42` (il vérifie aussi qu'aucun contenu de Lucas ne reste seulement dans un objet orphelin).

**Prévention**
- Pousser sa branche de travail ; `git stash` est un brouillon, pas un rangement (mieux : un commit `wip` sur une branche).
- Alias de confort : `git config --global alias.undo 'reset --soft HEAD@{1}'` est tentant, mais la vraie prévention est de **lire** `git status` avant une commande destructrice.
- Ne jamais lancer `git gc --prune=now` ou `git reflog expire --expire=now` sur un dépôt de travail (ce sont des commandes de **purge**, utiles en E17 pour un secret, nulle part ailleurs).

**Explications**

Git ne supprime presque jamais rien immédiatement : les commandes « destructrices » déplacent des références ou vident l'index ; les objets restent, atteignables par les reflogs (90 jours par défaut, `gc.reflogExpire`), puis orphelins (encore 30 jours pour les entrées de reflog inatteignables, `gc.reflogExpireUnreachable`), puis élagués par `git gc` s'ils sont plus vieux que `gc.pruneExpire` (2 semaines par défaut). Pour Lucas : V1 et V2, au moins 30 jours (reflog de `HEAD`) ; V3 et V4, aucun reflog ne retient l'objet : jusqu'au prochain `gc` qui élague les objets de plus de 2 semaines (le `gc --auto` lancé par certaines commandes ne se déclenche qu'au-delà de 6 700 objets libres, `gc.auto`).

**Alternatives**
- `git log --walk-reflogs` ou `git reflog show --all` pour parcourir tous les reflogs.
- `git fsck --unreachable` montre **tous** les objets inatteignables (pas seulement les sommets orphelins), utile pour les arbres et blobs de V4.

**Pièges classiques**
- `git gc` « pour voir » pendant la récupération.
- Chercher le stash dans le reflog de `HEAD` (V3) : `git stash drop` ne touche pas `HEAD`.
- Recréer la branche au mauvais endroit (`HEAD@{0}` au lieu de `HEAD@{1}`).
- Oublier les droits d'exécution du fichier récupéré (V4).

**En production chez MédiSphère**

La formation des nouveaux arrivants (et de Lucas) inclut ce scénario. Côté serveur, GitLab garde aussi des traces : une branche supprimée sur la forge peut être recréée depuis l'empreinte visible dans l'activité du projet ou dans le journal d'audit, tant que le *housekeeping* n'a pas élagué les objets.

---

### M01-E43 — Astreinte : la forge en difficulté

**Démarche de diagnostic**

Comme en M00-E46, la difficulté est **méthodologique** : deux pannes simultanées, des symptômes qui se recouvrent, et ici un piège supplémentaire : la forge est à la fois le service en panne **et** ton outil de travail (tu publies tes correctifs, ton journal et ton post-mortem par elle).

**1. Triage (10 minutes maximum).** Lance les sondes ciblées et dresse la carte :

```
admin@adm01:~/DevOpsPrivateCloud$ for e in 36 37 38 39 40 41 42; do lab/bin/check 01 $e | tail -n 2; done
```

Un exemple de tableau de triage (paire E37 V2 + E38 V4) :

| Symptôme | Impact | Couche probable | Dépend de |
|---|---|---|---|
| 502 sur l'interface web | personne ne peut relire, fusionner, consulter | `git01` (NGINX/Workhorse/Puma) | — |
| Jobs de MR en attente | plus aucune MR ne peut être fusionnée (pipeline obligatoire) | runner ou GitLab | l'API de GitLab (502 !) |

Hypothèse de regroupement : « la 502 explique tout, le runner ne joint pas l'API ». C'est l'hypothèse la plus économique… et elle est fausse ici.

**2. Ordre de traitement.** Restaure d'abord tes **instruments** : l'API et l'interface (E37) conditionnent le diagnostic de E36, E38, E39 ; SSH (E40) conditionne les pushs de tes correctifs et la sonde de E36. Ordre typique : E37 → E40 → E38 → E36 → E39 → E41/E42 (locales, sans dépendance, mais qui comptent pour Lucas : on peut les confier à quelqu'un d'autre ou les traiter quand la forge est revenue).

**3. Pannes qui se masquent.** Après chaque correction, rejoue **toutes** les sondes du triage :

| Paire | Ce qu'on voit d'abord | Ce qui reste caché |
|---|---|---|
| E37 + E38 | 502 : « les jobs sont bloqués à cause de la 502 » | une fois l'API revenue, les jobs de MR restent en attente (étiquette, protection, jeton ou adresse du runner) |
| E37 + E39 | 502 : la MR de Karim ne peut même pas être fusionnée | une fois GitLab revenu, la release échoue pour sa propre cause |
| E37 (V1, V2) + E40 | Git en SSH échoue « à cause de la 502 » (gitlab-shell appelle l'API) | une fois Puma revenu, SSH échoue encore (configuration du poste, clé d'hôte, compte, gitlab-shell) |
| E36 (V2) + E39 | push refusé partout | la fusion de la MR de Karim est aussi refusée par le hook défaillant (les hooks globaux s'appliquent aux fusions faites dans l'interface) : la release « ne part pas » pour une raison qui n'est pas la sienne |
| E38 + E39 | jobs en attente : la release ne démarre pas | une fois le runner revenu, le job `release` échoue |
| E40 + E36 | SSH impossible | une fois SSH rétabli, le push est refusé par GitLab (protection, archive, hook, URL de poussée) |

Inversement, une correction peut faire **apparaître** un symptôme : il était masqué. Ce n'est pas ta correction qui l'a créé.

**4. Où écrire pendant l'incident ?** Dans `~/medisphere`, sur une branche locale (`incident/inc-2788`), commits locaux horodatés ; publication par MR quand la forge est revenue. Les communications à Nadia partent par un canal qui ne dépend pas de la forge.

**5. Communication.** Exemples :

> **[INC-2788] 07:25 — En cours.** Impact : interface web de la forge indisponible (502) depuis 07:00, pipelines bloqués. Les dépôts ne sont pas touchés (aucune perte de données). Cause en cours d'analyse sur `git01`. Prochain point : 07:55.

> **[INC-2788] 07:55 — Partiellement rétabli.** Interface web revenue à 07:41 (fichier de configuration généré modifié à la main, configuration réappliquée). Les pipelines de MR restent bloqués : seconde cause, côté runner, en cours. Prochain point : 08:25.

> **[INC-2788] 08:20 — Résolu.** Runner rétabli à 08:12 (réglage « branches protégées seulement » retiré). MR de test fusionnée, pipeline vert. Surveillance renforcée jusqu'à midi. Post-mortem demain.

**6. Post-mortem.** Exemple complet : [`fichiers/M01-E43/post-mortem-exemple.md`](fichiers/M01-E43/post-mortem-exemple.md) (paire E37 V2 + E38 V4). La grille d'évaluation de M00-E46 s'applique (sans recherche de coupable, chronologie sourcée, **deux** causes racines prouvées, détection, actions typées avec responsable et échéance, explication du masquage). Une sonde de triage réutilisable est fournie : [`fichiers/M01-E43/triage-forge.sh`](fichiers/M01-E43/triage-forge.sh).

**Annulation** si nécessaire : `lab/bin/break 01 43 --annuler`.

**Vérification** : `lab/bin/check 01 43` (rejoue les contrôles de E36 à E42 ; ceux de E41 et E42 seulement si leur dépôt existe).

**Explications**

La forge concentre les dépendances : quand elle tombe, on perd aussi la revue, la CI, la publication de la documentation. C'est un argument pour : des accès de secours indépendants (alias IP, console), des sondes qui ne passent pas toutes par la même porte (HTTP, SSH, runner), et une procédure d'incident qui n'a pas besoin de la forge pour fonctionner.

**Pièges classiques**
- Tout attribuer à la panne la plus visible (la 502), corriger, et déclarer l'incident clos.
- Réenregistrer le runner ou relancer `reconfigure` « au cas où » pendant l'incident : on change deux choses à la fois.
- Rédiger le post-mortem sans les heures du journal.
- Oublier Lucas (E41/E42) parce que sa panne « ne touche qu'une personne » : elle touche son travail de plusieurs jours.

**En production chez MédiSphère**

La forge a un niveau de service défini (heures ouvrées, rétablissement en 4 h), un runbook par symptôme (RB-013 du mini-projet), et figure dans le PRA (F5) : sa restauration (E28) est testée deux fois par an.

---

### M01-E44 — Trouver le commit fautif avec `git bisect run`

**Solution**

Dépôt fabriqué : 113 commits atteignables depuis `main` (107 en ne suivant que le premier parent), 3 branches fusionnées, `v1.0.0` au 11e commit. Toutes les sorties ci-dessous sont réelles et reproductibles (dates fixes : mêmes empreintes chez toi).

*1. Constat.*

```
admin@adm01:~/src/labo-e44$ tests/test.sh
--- …/attendu.txt
+++ /dev/fd/63
@@ … @@
-10.10.10.10 -> 10.10.40.0/24 tcp dport { 6443, 30000-32767 }  # API et NodePorts Kubernetes (futur)
+10.10.10.10 -> 10.10.40.0/24 tcp dport { 6443, 30000-30000 }  # API et NodePorts Kubernetes (futur)
tests : ÉCHEC
admin@adm01:~/src/labo-e44$ git rev-list --count v1.0.0..main
102
```

Environ log2(102) ≈ 7 étapes pour un historique linéaire.

*3. Script de test* ([`fichiers/M01-E44/bisect-e44.sh`](fichiers/M01-E44/bisect-e44.sh)) :

```bash
#!/usr/bin/env bash
# Commit non testable (code qui ne se charge pas) : 125 ; tests en échec : 1 ; sinon 0.
for f in bin/flux-check lib/*.sh; do
  bash -n "$f" 2>/dev/null || exit 125
done
tests/test.sh >/dev/null 2>&1 || exit 1
exit 0
```

Il vit **hors** du dépôt : pendant la bisection, Git extrait des commits anciens ; un script versionné changerait (ou disparaîtrait) d'un commit à l'autre, et un script non suivi dans le dossier risquerait d'être pris dans un `git add -A` ou de gêner une extraction.

*4. Bisection automatique.*

```
admin@adm01:~/src/labo-e44$ git bisect start main v1.0.0
admin@adm01:~/src/labo-e44$ git bisect run ~/src/bisect-e44.sh
…
14e633c7e3acb464dbc434fbced3faa99be5f58b is the first bad commit
commit 14e633c7e3acb464dbc434fbced3faa99be5f58b
Author: Karim Benali <karim.benali@medisphere.internal>
    refactor(ports): simplifier le découpage des plages
 lib/ports.sh | 4 ++--
admin@adm01:~/src/labo-e44$ git bisect log > /tmp/bisect-e44.log ; git bisect reset
```

11 étapes, dont 4 commits sautés (code 125) : la première moitié testée tombe dans la période où `lib/export.sh` contenait une erreur de syntaxe (commits `feat(export): préparer l'export JSON` … `fix(export): corriger la structure conditionnelle`).

*5. Contre-épreuve, script naïf* (`tests/test.sh` seul) : il désigne `1d404cb feat(export): préparer l'export JSON`, en 7 étapes. Faux : ce commit casse **tout** le programme (erreur de syntaxe), donc le test échoue, et la bisection en conclut que la régression est là ; or ce bogue a été corrigé 23 commits plus tard, et la régression des plages est bien postérieure. Un test qui échoue pour une autre raison que celle recherchée **ment** à la bisection. C'est tout l'intérêt du code 125.

*6. `--first-parent`* : désigne `c343e9e Merge branch 'refactor/ports'` (18 étapes, dont 10 sauts : chaque proposition qui tombe dans la période cassée coûte une étape de plus, et le chemin des premiers parents en contient davantage en proportion). La bisection ne descend pas dans la branche fusionnée : elle indique **quelle fusion** a fait entrer la régression dans `main`. Préférable quand les branches de fonctionnalité contiennent des commits intermédiaires non testables (pratique de l'équipe : on ne garantit que les commits de `main`), ou quand on veut savoir quelle livraison est en cause.

*7. Correctif.*

```
admin@adm01:~/src/labo-e44$ git switch -c fix/regression-plages main
admin@adm01:~/src/labo-e44$ git revert --edit 14e633c7e3ac
```

Message (éditeur) :

```
revert: annuler la simplification du découpage des plages

La refactorisation calculait la fin de plage comme son début (copier-coller) et
avait assoupli le contrôle début < fin : 30000-32767 devenait 30000-30000.
Trouvé par git bisect run (DEV-280).

This reverts commit 14e633c7e3acb464dbc434fbced3faa99be5f58b.
```

```
admin@adm01:~/src/labo-e44$ tests/test.sh
tests : OK
```

Annuler la fusion (`git revert -m 1 c343e9e`) aurait aussi corrigé, mais en retirant les deux autres commits de la branche (`extraire la normalisation d'un élément`, `documenter le format des plages`) qui sont bons ; et réintroduire plus tard une branche dont la fusion a été annulée demande d'« annuler l'annulation » (*revert the revert*), source d'erreurs. On annule le commit précis.

*8. Journal* : voir l'exemple de rapport dans la grille ci-dessous.

**Explications**

`git bisect` fait une dichotomie sur le **graphe** : à chaque étape, il choisit le commit qui partage au mieux l'ensemble des commits encore suspects (descendants du bon, ancêtres du mauvais). Avec des fusions, ce n'est plus une simple liste : la bisection peut proposer un commit d'une branche fusionnée. `git bisect run` lance le script à chaque étape : 0 = bon, 125 = « non testable » (`git bisect skip`), 1 à 127 sauf 125 = mauvais, au-delà de 127 (ou signal) = arrêt de la bisection. Un commit sauté n'est pas éliminé : il reste candidat ; si le seul candidat restant est un commit sauté, Git annonce qu'il ne peut conclure qu'à un ensemble de commits.

**Alternatives**
- `git bisect start --term-old=correct --term-new=faux` (termes personnalisés), utile pour chercher le commit qui a **corrigé** un bogue.
- `git log -S'fin="${p%-*}"' -- lib/ports.sh` (« pickaxe ») trouve directement le commit qui introduit une chaîne, quand on sait ce qu'on cherche.
- `git bisect skip` à la main, `git bisect replay` pour rejouer un journal corrigé.

**Pièges classiques**
- Script dans le dépôt, ou script qui modifie des fichiers suivis (il faut que `git status` reste propre entre deux étapes).
- Script qui renvoie 1 quand le **test lui-même** ne peut pas tourner (le piège de la contre-épreuve).
- Oublier `git bisect reset` et commiter sur une tête détachée.
- Annuler la fusion entière par réflexe.

**Grille d'auto-évaluation du journal** : empreinte complète du fautif ; `git bisect log` collé ; nombre d'étapes et explication des sauts ; résultat du script naïf et pourquoi il est faux ; résultat de `--first-parent` et quand l'utiliser ; justification « commit plutôt que fusion ».

**En production chez MédiSphère**

La bisection n'est fiable que si chaque commit de `main` est testable : c'est un argument de plus pour le pipeline obligatoire (M01-E24, qui contrôle chaque commit de la MR) et pour la méthode de fusion de l'équipe (M01-E11 : historique semi-linéaire, chaque branche est à jour de `main` au moment de la fusion, donc chaque commit a été construit sur l'état réel de `main`). Le script de test de bisection rejoint les outils de l'équipe, à côté des tests (module 02 : bats, pytest).

---

### M01-E45 — Sous le capot : packfiles, maintenance et gros dépôts

**Solution**

Mesures réelles sur un dépôt fabriqué avec les paramètres par défaut (4 000 commits ; les empreintes des binaires et les durées varient chez toi). Exemple de rapport complet : [`fichiers/M01-E45/git-gros-depot.md`](fichiers/M01-E45/git-gros-depot.md) ; script d'inventaire des gros objets : [`fichiers/M01-E45/gros-objets.sh`](fichiers/M01-E45/gros-objets.sh).

*1. État des lieux.*

```
admin@adm01:~/src/legacy-rdv$ git count-objects -vH
count: 0
in-pack: 16035
packs: 1
size-pack: 49.51 MiB
```

Aucun objet libre : `git fast-import` (qui a servi à fabriquer le dépôt, comme l'aurait fait un import depuis un autre outil) écrit directement un paquet. Le `.pack` contient les objets (compressés, éventuellement en delta) ; le `.idx` est l'index qui associe une empreinte à une position dans le paquet (recherche dichotomique) ; le `.rev` (*reverse index*, écrit par défaut depuis Git 2.41) associe une position à un objet, pour savoir rapidement la taille sur disque d'un objet ou servir un paquet sans le décompresser.

*2. Anatomie.* `git verify-pack -v` affiche pour chaque objet : empreinte, type, taille, taille dans le paquet, position, et pour un delta la profondeur et l'objet de base. Le résumé de fin compte les objets non deltifiés (`non delta: …`) et les chaînes (`chain length = N: … objects`), jusqu'à 50 (profondeur par défaut de `pack.depth`). Un delta peut avoir pour base un objet **plus récent** : Git cherche la meilleure base parmi des objets voisins (fenêtre de `pack.window`, triés par type, nom et taille), et préfère garder la version récente entière (accès rapide aux versions courantes).

*3. Ce qui pèse.*

```
blob 3780ca64… 18874368 18880138 assets/video/presentation.mp4
blob 2ed8e5d1… 18874368 18880138 assets/video/presentation.mp4
blob 1ef360cb…  9437184  9440074 vendor/sdk-legacy-1.2.tar.gz
blob d3f321ed…  2606736   158494 db/dump-demo.sql
blob 0363b5ca…  2606736   149077 db/dump-demo.sql
```

Les deux versions de la vidéo et l'archive du SDK font 46 Mio sur 49,5 : elles sont incompressibles (données aléatoires, comme une vraie vidéo ou une archive déjà compressée), leur taille sur disque dépasse même légèrement leur taille réelle (en-tête zlib). L'export SQL, du texte très répétitif, passe de 2,5 Mio à environ 150 Kio par version. La vidéo a été supprimée de l'arbre, mais chaque commit qui la contenait est toujours dans l'historique : ses blobs sont atteignables, donc conservés, et téléchargés par chaque clone complet.

*4. Compression.* `git gc` : moins d'une seconde, taille inchangée (il réutilise les deltas existants). `git repack -a -d -f --depth=50 --window=250` : 12 secondes, 49,5 → 48,7 Mio. Recalculer les deltas fait gagner un peu sur le texte ; rien ne peut réduire des données incompressibles. Le levier n'est pas la compression, c'est de **sortir les binaires** de l'historique.

*5. Coût des clones* (mesuré ici sur un serveur local `file://` avec `uploadpack.allowFilter` ; depuis GitLab, ajoute le réseau) :

| Stratégie | Durée | `.git` |
|---|---|---|
| clone complet | 3,8 s | 49 Mio |
| `--depth 1` | 0,8 s | 9,4 Mio (l'archive du SDK est dans `HEAD`) |
| `--filter=blob:none` | 1,2 s | 11 Mio (blobs de `HEAD` téléchargés à l'extraction) |
| `--filter=blob:limit=1m` | 1,6 s | 12 Mio |
| `--filter=blob:none --sparse` + `sparse-checkout set src` | 0,5 s | 1,8 Mio |

*6. Migration LFS.*

```
admin@adm01:~/src$ cp -a legacy-rdv legacy-rdv-lfs && cd legacy-rdv-lfs
admin@adm01:~/src/legacy-rdv-lfs$ git lfs migrate info --everything --above=5mb
*.mp4	38 MB 	2/2 files	100%
*.gz 	9.4 MB	1/1 file 	100%
admin@adm01:~/src/legacy-rdv-lfs$ git lfs migrate import --everything --above=5mb
admin@adm01:~/src/legacy-rdv-lfs$ cat .gitattributes
/vendor/sdk-legacy-1.2.tar.gz filter=lfs diff=lfs merge=lfs -text
/assets/video/presentation.mp4 filter=lfs diff=lfs merge=lfs -text
admin@adm01:~/src/legacy-rdv-lfs$ git reflog expire --expire=now --all && git gc -q --prune=now
admin@adm01:~/src/legacy-rdv-lfs$ git count-objects -vH | grep size-pack ; du -sh .git/lfs
size-pack: 3.66 MiB
46M	.git/lfs
```

De 49,5 à 3,7 Mio d'historique Git ; les 46 Mio sont dans `.git/lfs/objects` localement et iront dans le stockage LFS de GitLab. Ici, la purge des reflogs suivie de `gc --prune=now` est **voulue** : on se débarrasse de l'ancien historique dans une copie qui va remplacer l'original. Attention : sur un clone qui a un `origin`, les références `refs/remotes/origin/*` retiennent encore l'ancien historique (taille inchangée après `gc`) : `git for-each-ref` le montre.

```
admin@adm01:~/src$ mv legacy-rdv legacy-rdv.avant-lfs && mv legacy-rdv-lfs legacy-rdv && cd legacy-rdv
admin@adm01:~/src/legacy-rdv$ git remote add origin git@git01.par1.medisphere.internal:formation/legacy-rdv.git
admin@adm01:~/src/legacy-rdv$ git push -u origin --all && git push origin --tags
```

Le hook `pre-push` installé par `git lfs install` envoie les objets LFS avant les références (authentification par `git-lfs-authenticate` en SSH, puis transfert en HTTPS vers `https://git01…/formation/legacy-rdv.git/info/lfs`, avec la CA provisoire reconnue par `adm01`). Côté GitLab, `GET /projects/:id?statistics=true` montre `repository_size` de quelques Mio et `lfs_objects_size` d'environ 46 Mio (statistiques mises à jour avec quelques minutes de retard).

*7. Clone partiel.* `git log -p -5 -- db/dump-demo.sql` déclenche des téléchargements à la demande (les blobs des anciennes versions ne sont pas présents) : chaque objet manquant coûte un aller-retour vers la forge. `git config --get-regexp 'remote.origin.*'` montre `remote.origin.promisor=true` et `remote.origin.partialclonefilter=blob:none` : le dépôt d'origine est un *promisor remote*, qui « promet » de fournir plus tard les objets filtrés.

*8. Maintenance.* `git log --oneline -- src/Module7.php` : 0,25 s sans graphe, 0,06 s avec (`git commit-graph write --reachable --changed-paths`), soit quatre fois plus rapide dès 4 000 commits ; l'écart grandit avec la longueur de l'historique (essaie `--commits 50000`). Le graphe de commits stocke parents, arbres et dates dans un fichier compact (plus besoin de décompresser chaque commit) ; les filtres de Bloom des chemins modifiés permettent d'écarter sans les lire les commits qui ne touchent pas le chemin demandé. `git maintenance start` enregistre le dépôt (`maintenance.repo` dans la configuration globale) et crée des minuteurs systemd utilisateur (horaire, quotidien, hebdomadaire) qui lancent `prefetch`, `commit-graph`, `loose-objects`, `incremental-repack`. Sur `adm01`, c'est utile pour les gros clones de travail ; inutile pour des dépôts jetables (`git maintenance unregister` à la fin des exercices). Les minuteurs utilisateur ne tournent que si une session existe ou si le *lingering* est activé (`loginctl enable-linger admin`) : à vérifier sur ta configuration.

*9. Housekeeping de GitLab.* Lancé à la main (**Settings > General > Advanced > Housekeeping**), il fait une optimisation complète (*eager*) : repack, écriture du graphe de commits, nettoyage. GitLab le déclenche aussi tout seul : après un certain nombre de poussées, et par une optimisation planifiée de tous les dépôts (*heuristical* : seulement ce qui en a besoin). « Prune unreachable objects » supprime les objets inatteignables avec un délai de grâce réduit (30 minutes) : si un `git push` en cours a déjà écrit des objets sans encore créer la référence, le dépôt peut être corrompu. On l'évite en heures ouvrées.

**Grille d'auto-évaluation du rapport**

| Critère | Attendu |
|---|---|
| Mesures | chaque étape chiffrée (taille, durée, nombre d'objets), datée, avec la commande |
| Explication | pourquoi la vidéo supprimée pèse encore ; pourquoi le texte se compresse et pas les binaires |
| Clones | comparaison des stratégies, avec le cas d'usage de chacune (CI, développeur, revue) |
| LFS | avant/après côté forge, conséquences de la réécriture (empreintes, communication) |
| Maintenance | commit-graph mesuré, décision argumentée sur `git maintenance`, *housekeeping* expliqué |
| Recommandations | règle des gros fichiers (hook + LFS), stratégie de clone en CI (`GIT_DEPTH`, partiel), maintenance, purge |

**Explications**

Git est optimisé pour du texte qui évolue par petites touches : le stockage par deltas y est remarquable. Il est mauvais pour les gros binaires : pas de delta utile, et chaque version reste pour toujours dans l'historique, téléchargée par chaque clone complet. LFS remplace le contenu par un pointeur de quelques lignes (`version`, `oid sha256:…`, `size`) et stocke le contenu ailleurs, téléchargé seulement pour les versions extraites. Le clone partiel est l'approche native de Git pour le même problème, sans changer le dépôt, mais il demande une forge qui le permet et des allers-retours à la demande.

**Alternatives**
- `git filter-repo --path db/dump-demo.sql --invert-paths` pour supprimer un fichier de l'historique (cf. « Pour aller plus loin ») ; côté GitLab, la libération réelle de l'espace demande ensuite la procédure « Reduce repository size » (export, purge des références, *housekeeping* avec élagage).
- En CI : `GIT_DEPTH` (déjà réglé à 20 par défaut par GitLab pour les nouveaux projets, à vérifier dans **Settings > CI/CD > General pipelines**), `GIT_STRATEGY: fetch`, `GIT_LFS_SKIP_SMUDGE=1` si un job n'a pas besoin des binaires. Le job `release` a besoin de tout l'historique (`GIT_DEPTH: "0"` dans le gabarit de M01-E25).

**Pièges classiques**
- Mesurer après `git gc` sur un dépôt qui a encore ses reflogs ou ses références distantes : rien ne diminue, on conclut à tort que la migration n'a servi à rien.
- Réécrire l'historique d'un dépôt partagé sans prévenir : chaque collègue qui pousse depuis son ancien clone réintroduit les anciens objets.
- Oublier `git lfs install` sur une machine qui clone : on obtient des fichiers pointeurs au lieu du contenu.
- Laisser `git maintenance` enregistré sur des dépôts supprimés (avertissements dans les journaux de systemd).

**En production chez MédiSphère**

Règle de la forge : pas de fichier de plus de 5 Mio dans Git (hook de M01-E26 sur `plateforme/*`, à étendre aux groupes applicatifs), LFS pour les binaires indispensables, artefacts de construction dans le registre de paquets ou d'images (M13), jamais dans Git. Legacy-RDV rejoindra un groupe applicatif lors de sa migration (F4) : son historique migré vers LFS est prêt.

---

### M01-E46 — Questions expert : les entrailles de Git

**1.** `--amend` crée un **nouveau** commit : même arbre (aucun fichier changé, donc aucun nouveau blob ni arbre), même parent, nouveau message, nouvelle date de *committer*. L'empreinte d'un commit est le hachage de tout son contenu (arbre, parents, auteur, *committer*, message) : changer le message change l'empreinte. L'ancien commit n'est pas modifié (les objets sont immuables) : il reste dans l'entrepôt, référencé par le reflog, jusqu'à expiration. Un commit **enfant** contient l'empreinte de son parent : il faudrait le recréer aussi (c'est ce que fait `rebase`), d'où la règle « on ne réécrit pas ce qui est publié ».

**2. Réponse b.** Un blob ne contient que le contenu, sans nom : deux fichiers identiques donnent le même blob, stocké une fois. Le chemin et le mode sont dans l'arbre. a) est faux (le chemin n'est pas dans le blob) ; c) faux, la déduplication est immédiate (même empreinte = même nom de fichier dans `.git/objects`) ; d) `core.deduplicate` n'existe pas.

**3.** Un objet **libre** est un fichier par objet (`.git/objects/xx/…`, compressé zlib). Un objet **empaqueté** est dans un `.pack`, éventuellement sous forme de delta par rapport à un autre objet du paquet. Le `.idx` permet de trouver un objet dans le paquet par son empreinte ; le `.rev` fait l'inverse (position → objet), pour calculer des tailles et servir des paquets sans tout décompresser ; le `multi-pack-index` indexe plusieurs paquets à la fois, pour ne pas chercher dans chacun (utile avec `incremental-repack`). Les deltas ne suivent pas la chronologie : Git choisit la meilleure base dans une fenêtre d'objets voisins, et préfère garder entière la version la plus récente (la plus souvent lue), les anciennes devenant des deltas « à rebours ».

**4.** `gc.reflogExpire` (90 jours) : durée de vie des entrées de reflog atteignables depuis la pointe actuelle ; `gc.reflogExpireUnreachable` (30 jours) : celle des entrées qui pointent vers des commits **qui ne sont plus** dans la branche (cas du `reset --hard`) ; `gc.pruneExpire` (2 semaines) : âge minimal d'un objet orphelin avant que `git gc` le supprime. Deux délais successifs : tant qu'une entrée de reflog référence le commit, il n'est pas orphelin (30 jours ici) ; ensuite seulement, l'objet orphelin attend encore jusqu'à ce qu'il ait plus de 2 semaines (et qu'un `gc` passe). Le second délai protège aussi les opérations concurrentes (un objet fraîchement écrit, pas encore référencé).

**5. Réponse b.** `git branch -D` supprime la branche **et son reflog** (a est faux). Le reflog de `HEAD` garde la trace de la pointe si la branche a été extraite à un moment. c) n'existe pas ; d) n'a rien à voir (sauf si un stash a été posé sur la branche, ce qui rendrait ses commits atteignables : vu en M01-E42).

**6.** `git fsck` (défaut) signale les objets **orphelins** (*dangling*) : inatteignables et non référencés par un autre objet inatteignable (les « sommets »). `--unreachable` liste **tous** les objets inatteignables (un commit orphelin, son arbre, ses blobs). `--lost-found` écrit les objets orphelins dans `.git/lost-found/commit/` et `.git/lost-found/other/`. Par défaut, les reflogs comptent comme des références (un commit retenu par un reflog n'est pas orphelin) ; `--no-reflogs` les ignore, et fait donc apparaître les commits abandonnés récemment (stash supprimé, `reset`).

**7.** Dichotomie : à chaque étape, Git choisit le commit qui coupe au mieux en deux l'ensemble des suspects (ancêtres du mauvais, non ancêtres du bon). 1 000 commits linéaires : ⌈log2(1000)⌉ = 10 étapes. Un commit « non testable » est sauté (Git en propose un voisin) mais reste suspect : il peut coûter des étapes et, s'il est le dernier candidat, empêcher de conclure. Avec des fusions, les suspects forment un graphe : la bisection peut proposer des commits des branches fusionnées. `--first-parent` ne suit que les premiers parents des fusions : il désigne la fusion qui a introduit la régression dans la branche principale (M01-E44 : 113 commits, 11 étapes avec 4 sauts ; 18 étapes avec `--first-parent`).

**8.** `--force` écrase la référence distante quoi qu'elle contienne. `--force-with-lease` n'écrase que si la référence distante vaut toujours ce que **ta référence de suivi** (`origin/branche`) en dit : si quelqu'un a poussé entre-temps, refus. Faille : si un `git fetch` (lancé automatiquement par ton éditeur) a mis à jour `origin/branche` avec le travail du collègue, sans que tu l'aies intégré, la « location » correspond et ton push écrase son travail. `--force-if-includes` (Git ≥ 2.30) ajoute la vérification que la valeur distante a bien été **intégrée** dans ta branche locale (présente dans son reflog). Combinaison recommandée : `--force-with-lease --force-if-includes`.

**9. Réponse b.** Le niveau « No one » refuse l'accès à tout le monde : dans le code de GitLab, le contrôle d'un niveau d'accès renvoie « refusé » pour « No access » avant tout autre examen, y compris pour un administrateur (vérifié dans `ProtectedRefAccess#check_access` ; à revérifier si ta version diffère). a) est une croyance répandue (et a été vraie dans d'anciennes versions) ; c) l'*Admin Mode* concerne l'accès aux fonctions d'administration, pas les protections de branche ; d) `--force` ne contourne rien côté serveur (et une branche protégée interdit en plus la poussée forcée par défaut).

**10.** Superficiel (`--depth N`) : seulement les N derniers commits (historique tronqué, objets complets de ces commits). Partiel (`--filter=blob:none`) : **tout** l'historique des commits et arbres, mais les blobs sont téléchargés à la demande. Le job semantic-release a besoin de tout l'historique des commits et des étiquettes pour calculer la version : ni superficiel (sauf `GIT_DEPTH: 0`), et un clone partiel `blob:none` lui conviendrait (il lit les messages, pas les fichiers). Un développeur sur un gros dépôt : partiel (historique complet pour `log`, `blame` à la demande). « Promisor » : le dépôt distant est déclaré capable de fournir plus tard les objets filtrés ; les paquets reçus sont marqués `.promisor`, et Git sait qu'un objet absent n'est pas une corruption.

**11.** Le fichier versionné est un pointeur texte (`version https://git-lfs.github.com/spec/v1`, `oid sha256:<empreinte>`, `size <octets>`). Le filtre `clean` (au `git add`) remplace le contenu par le pointeur et range le contenu dans `.git/lfs/objects` ; le filtre `smudge` (à l'extraction) fait l'inverse, en téléchargeant si besoin ; le hook `pre-push` envoie les objets LFS au serveur avant les références. Pertes : les binaires ne sont plus dans le paquet Git (pas de delta, pas de `git log -p` utile, `git blame` sans objet), le dépôt dépend d'un second service (stockage LFS : sauvegarde, quotas), et un clone sans `git-lfs` installé n'a que des pointeurs.

**12.** En protocole v0, le serveur annonce **toutes** ses références dès la connexion, même pour récupérer une seule branche. Le v2 (par défaut côté client depuis Git 2.26) sépare les commandes : `ls-refs` avec des préfixes (`ref-prefix refs/heads/main`), puis `fetch`, et prend en charge les filtres (clone partiel), les *bundle URIs*. Avec des milliers d'étiquettes, l'annonce v0 représente des mégaoctets à chaque `fetch` ; en v2, seules les références demandées circulent.

**13.** `ort` (*Ostensibly Recursive's Twin*), stratégie par défaut depuis Git 2.34 : même résultat que `recursive` dans la plupart des cas, beaucoup plus rapide (surtout avec des renommages), sans toucher à l'arbre de travail pendant le calcul, et une gestion plus juste de certains conflits de renommage. `rerere` (*reuse recorded resolution*) mémorise la résolution d'un conflit (image du conflit → résolution) dans `.git/rr-cache/` et la rejoue quand le même conflit réapparaît (rebase répétés, M01-E13) ; activé par `rerere.enabled=true`.

**14.** Fichiers libres : un fichier par référence (problèmes avec beaucoup de références, noms insensibles à la casse sur certains systèmes, pas de mise à jour atomique de plusieurs références). `packed-refs` : un fichier texte unique pour les références anciennes, réécrit en entier à chaque suppression. *reftable* : format binaire en blocs, mises à jour atomiques de plusieurs références, lectures rapides même avec des millions de références, reflogs intégrés. Avec Git 2.47 : `git refs migrate --ref-format=reftable` (commande apparue en 2.46 ; certaines situations, comme les *worktrees*, peuvent bloquer la migration : à vérifier dans `git help refs`). Le format par défaut reste `files` jusqu'à Git 3.0.

**15.** SHAttered (2017) a produit deux PDF de même SHA-1 par une attaque à préfixe choisi coûteuse ; Git utilise depuis la version 2.13 l'implémentation `sha1dc`, qui **détecte** les motifs de collision de ce type et refuse l'objet : l'attaque connue ne passe pas. Mais SHA-1 reste affaibli, d'où le travail sur SHA-256 : `git init --object-format=sha256` existe depuis Git 2.29 (`extensions.objectFormat`), l'interopérabilité entre dépôts SHA-1 et SHA-256 (traduction des empreintes) est en cours, et la prise en charge par les forges est partielle (GitLab : prise en charge expérimentale, à vérifier sur ta version). Git 3.0 prévoit SHA-256 par défaut pour les nouveaux dépôts.

**16.** Est signé : l'objet commit lui-même (arbre, parents, auteur, *committer*, message), hors l'en-tête `gpgsig` qui contient la signature (`ssh-keygen -Y sign`, espace de noms `git`). GitLab affiche « Verified » si la signature est valide, si la clé est déclarée sur le compte avec l'usage « Signing » ou « Authentication & Signing », et si l'adresse du *committer* est une adresse **vérifiée** du compte. Supprimer la clé du compte ne change pas le statut des commits déjà signés ; la **révoquer** les fait passer à « Unverified » (documentation de GitLab, « Sign commits with SSH keys »).

**17.** *Hashed storage* : `/var/opt/gitlab/git-data/repositories/@hashed/<aa>/<bb>/<sha256 de l'identifiant du projet>.git`. Le chemin ne dépend pas du nom du projet : renommer ou déplacer un projet ne touche pas au disque, et le nom n'apparaît pas (les noms seraient aussi une fuite d'information). Pour le retrouver : `sudo gitlab-rails runner 'puts Project.find_by_full_path("plateforme/medisphere").disk_path'`, ou **Admin > Projects > le projet** (« Gitaly relative path ») ; le fichier `config` du dépôt nu contient aussi `fullpath`.

**18.** SSH : sshd authentifie la clé (avec l'aide de GitLab pour savoir à quel utilisateur elle appartient), `gitlab-shell` (commande forcée) demande à l'API interne (via Workhorse et Puma) si l'utilisateur peut écrire dans le projet, puis appelle Gitaly (`SSHReceivePack`). HTTPS : NGINX → Workhorse, qui demande l'autorisation à Puma puis relaie le flux vers Gitaly. Dans les deux cas, Gitaly reçoit les objets (en quarantaine), puis lance la phase pre-receive : contrôles de GitLab sur les références (appel `/internal/allowed` : branche et étiquette protégées, taille…), hooks personnalisés du projet, hooks globaux ; puis met à jour les références et lance `post-receive` (pipelines, notifications). Ordre : authentification → droits sur le projet → réception → contrôles des références → hooks → mise à jour.

**19. Réponse b.** Git affiche `! [remote rejected] <ref> -> <ref> (pre-receive hook declined)` sans autre explication : c'est pour cela que les hooks doivent écrire un message (préfixe `GL-HOOK-ERR:` pour l'afficher aussi dans l'interface). a) est faux (code non nul = refus) ; c) le refus est bien transmis au client Git ; d) il n'y a pas de MR concernée par un push refusé.

**20.** Le *housekeeping* : repack (incrémental ou complet selon l'état et le mode), écriture du graphe de commits et des index, empaquetage des références, nettoyage des fichiers temporaires et verrous périmés, mise à jour des *object pools* des projets dupliqués (forks). Manuel = optimisation complète (*eager*) ; automatique = après un nombre de poussées, et optimisation planifiée *heuristique* (seulement ce qui en a besoin). « Prune unreachable objects » supprime les objets inatteignables avec un délai de grâce de 30 minutes au lieu de deux semaines : un objet écrit par une opération en cours (push, fusion) mais pas encore référencé peut être supprimé, puis référencé : dépôt corrompu. À réserver aux opérations de réduction de taille, hors activité.

**Grille d'auto-évaluation** : une question est réussie si la réponse donne le mécanisme (pas seulement le nom de la commande) et, pour les QCM, réfute chaque mauvaise option. Points faibles typiques et lectures : questions 3, 4, 6 → *Pro Git*, chapitre 10 et `git help gc` ; 8 → `git help push` (section `--force-with-lease`) ; 17, 18, 20 → documentation d'administration de GitLab (Gitaly, *hashed storage*, *housekeeping*).
