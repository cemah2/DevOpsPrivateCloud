# Module 04 — Palier 4 : Expert

La configuration du socle est en code : `plateforme/ansible` est relu en MR, ses rôles sont testés par Molecule, la CI vérifie chaque changement en `--check`, la dérive est surveillée chaque nuit et Semaphore trace chaque exécution. Claire Morel en tire la conséquence : « Maintenant, quand la chaîne de configuration casse, plus personne ne peut corriger le socle. C'est un incident de production. » Karim Benali a préparé des pannes, toutes vécues un jour ou l'autre par une équipe qui fait de l'Ansible : une machine qu'on ne joint plus, un playbook vert qui ne fait rien, une variable qui ne vaut pas ce qu'on croit, un coffre qui ne s'ouvre plus, un inventaire vide qui ne se plaint pas, un `sshd` qui ne revient pas, un playbook qui se traîne, des tests qui ne démarrent même pas. Une astreinte les combine. Puis tu descends sous le capot : ce qu'Ansible envoie réellement sur la machine cible, et comment écrire ton propre module.

La méthode est celle des modules précédents : observer avant d'agir, formuler une hypothèse, la tester par la mesure la moins invasive, corriger à la racine, prévenir la récidive. Avec deux règles propres à Ansible :
- **« ok » ne veut pas dire « fait ».** Un récapitulatif vert prouve seulement qu'aucune tâche n'a échoué. Ce qui compte est l'état **effectif** de la cible (`sshd -T`, `systemctl show`, `timedatectl`), et la question « quelles tâches ont tourné, sur quelle machine, avec quelles valeurs ? ».
- **Avant de rejouer, regarde ce que tu rejoues.** Un correctif « par relance du playbook » sur un projet dont tu ne connais pas l'état peut propager la panne à tout le socle : `--check --diff --limit` d'abord.

> **Rappels** : tout se lance depuis `adm01`, à la racine du projet `~/src/ansible` (variable `WB_SRC`), avec l'environnement `uv` du projet (`uv run ansible-…` ou environnement activé, M04-E02). Inventaire statique `inventories/lab/hosts.yml`, inventaire dynamique `inventories/lab/proxmox.yml` (M04-E13), secrets en Vault (`~/.config/workbook/ansible-vault.pass`, M04-E12). Tout correctif durable passe par une MR fusionnée dans `main`, pipeline vert.

## Règles du jeu des pannes (M04-E35 à M04-E43)

- Les pannes s'injectent **depuis `adm01`**, à la racine de ta copie du workbook :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ lab/bin/break 04 35
  ```
  Le script tire une variante au hasard et n'affiche que le **symptôme**, comme un ticket. Chaque panne a 4 variantes : refais l'exercice jusqu'à les avoir toutes rencontrées (`--variante N` force une variante, sans dire laquelle est laquelle). Si une variante n'a pas d'effet sur ton lab (selon tes choix d'organisation du projet), le script en essaie une autre.
- **Avant d'injecter**, lance le contrôle de l'exercice (`lab/bin/check 04 35`) : il doit être vert. Une panne posée sur un lab déjà malade fausse tout le diagnostic. Exception : le contrôle de M04-E36 vérifie aussi ce que demande son ticket (la bannière SSH) ; avant l'injection, ses deux premiers points et le quatrième sont rouges, les autres doivent être verts.
- **Ta copie de travail `~/src/ansible` doit être propre** (`git status` sans modification) : l'injection le vérifie. Plusieurs pannes modifient cette copie de travail comme le ferait un collègue qui travaille sur `adm01` (Lucas a un compte sur le bastion et « dépanne » volontiers) : fichiers modifiés ou ajoutés, **jamais** de commit. Tout ce qu'elles touchent est sauvegardé avant et restauré à l'annulation.
- **Ne lis pas** les scripts de `corrige/pannes/`, ni `/var/lib/workbook/` sur les hôtes, ni `~/.local/state/workbook/` sur `adm01` : ils contiennent la cause.
- Une seule panne active à la fois par exercice. Si tu abandonnes : `lab/bin/break 04 35 --annuler` remet l'état sain (filet de sécurité, pas un correctif : compte l'exercice comme non réussi). **Quand tu as réparé**, lance aussi `--annuler` pour **clore** la panne (sinon elle reste marquée active et bloque la suivante, l'astreinte E43 et le mini-projet) : l'annulation ne rétablit que ce qui est encore dans l'état cassé et ne revient jamais sur ta réparation.
- Les pannes agissent sur les hôtes du socle (fichiers sauvegardés avant modification, sous `/var/lib/workbook/`), sur ta copie de travail `~/src/ansible` et sur `~/.config/workbook/` (sauvegardés), et sur `pve01` : ACL et jeton du compte `wb-ansible@pve`, rôle `WBAnsible`, étiquettes et réglages de l'image dorée `current`, VMs jetables 2040 et 2045-2049. Jamais sur le réseau de `pve01`, son pare-feu ou une VM hors du pool `lab` ; aucune donnée détruite.
- **Tiens un journal de diagnostic** pour chaque panne, dans `docs/socle/journal/` de `~/medisphere` (publié par MR) : heure, hypothèse, commande, résultat observé, conclusion. Il alimente le post-mortem de M04-E43.
- Le **temps cible** est indicatif. Le dépasser n'est pas un échec ; corriger sans comprendre en est un.

> ⚠️ **Accès de secours** : M04-E35 et M04-E40 coupent l'accès SSH à une VM. Tu as alors l'agent QEMU depuis `pve01` : `qm guest exec <VMID> -- <commande>` (sortie JSON, champ `out-data`) et `qm guest exec-status`. La console série (`qm terminal <VMID>`, sortie par `Ctrl+O`) ne te servira que si le compte a un mot de passe : les VMs clonées par cloud-init n'en ont pas. Si tu dois en poser un temporairement (`qm guest passwd <VMID> admin`), note-le dans ton journal et **verrouille-le** à la fin (`passwd -l admin`). Repère ces chemins **avant** d'en avoir besoin : `qm guest cmd 1007 ping` doit répondre.

> ⚠️ **Avant toute relance « pour voir »** : `--check --diff`, et `--limit` sur la machine en cause. Plusieurs pannes de ce palier font qu'un passage complet de `site.yml` **propagerait** l'erreur au reste du socle.

---

### M04-E35 — Panne : « UNREACHABLE » sur une partie du socle  `BF` `★★`

> **Ticket INC-3141** — *De : Julien Petit*
> Je voulais passer le playbook du socle en vérification (`--check`) avant la mise à jour de ce soir : une des machines sort en « UNREACHABLE! », les autres répondent normalement. Je n'ai rien changé au projet, et personne ne sait me dire ce qui a bougé. La mise à jour de ce soir doit passer sur **tout** le socle.

**Objectifs pédagogiques**
- Savoir ce que signifie exactement `UNREACHABLE` pour Ansible (échec du transport, pas d'une tâche) et le distinguer de `FAILED`.
- Reconstituer la connexion qu'Ansible tente réellement (adresse, compte, clé, options SSH) à partir de l'inventaire et de la configuration, puis la rejouer à la main.
- Diagnostiquer les causes SSH classiques : clé d'hôte changée, mauvais compte, mauvaise adresse, compte refusé par PAM, sans affaiblir la vérification des clés d'hôte.

**Prérequis** : M04-E03, M04-E04, M04-E06 ; M00-E15 (alias SSH et multiplexage) ; `lab/bin/check 04 35` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Injection** : `lab/bin/break 04 35` (4 variantes).

**Travail demandé**
1. Reproduis le symptôme avec la commande la plus courte possible (un module `ping` sur tout le socle). Note le message **complet** d'`UNREACHABLE` pour la machine touchée.
2. Avant de toucher à quoi que ce soit, établis ce qu'Ansible **croit** savoir de cette machine : `ansible-inventory --host <hôte>` et `ansible-config dump --only-changed`. D'où vient chaque paramètre de connexion (adresse, compte) ? Dans quel fichier ?
3. Rejoue la connexion avec `-vvvv` et retrouve la commande `ssh` exacte qu'Ansible lance. Rejoue-la à la main **sans multiplexage** (`-o ControlPath=none`) : la panne est-elle dans Ansible, dans SSH, ou dans la machine ?
4. Si la machine elle-même est en cause et que SSH ne passe plus, entres-y par l'agent QEMU. Trouve la cause racine, corrige-la à l'endroit où elle a été introduite.
5. Si la cause est une clé d'hôte qui a changé : **prouve** que la nouvelle clé est légitime (empreinte lue sur la machine par un autre canal) avant de l'accepter. Écris dans ton journal pourquoi `host_key_checking = False` n'est pas un correctif.
6. Rejoue le `--check` complet du socle : plus aucun `UNREACHABLE`.

**Critères de réussite**
- [ ] `ansible socle -m ansible.builtin.ping` répond `pong` pour tous les hôtes.
- [ ] Une nouvelle connexion SSH (sans multiplexage) aboutit vers chaque hôte, clé d'hôte vérifiée.
- [ ] Ton journal contient le message d'erreur initial, la commande `ssh` reconstituée et la preuve de légitimité de la clé d'hôte si la variante l'exigeait.

**Vérification** : `lab/bin/check 04 35`

<details><summary>Indice 1</summary>

`UNREACHABLE!` veut dire qu'Ansible n'a pas pu **exécuter** quoi que ce soit sur la machine. Le texte qui suit (`Failed to connect to the host via ssh: …`) est en général le message de `ssh` lui-même : lis-le comme tu lirais celui de `ssh -v`.
</details>

<details><summary>Indice 2</summary>

`ansible-inventory --host <hôte>` affiche toutes les variables d'inventaire de l'hôte, après fusion de tous les fichiers. Si une valeur te surprend, `grep -rn` dans `inventories/` (et `git status`) te dira d'où elle vient. Côté machine, `chage -l admin` et `journalctl -u ssh` racontent ce que `sshd` a refusé et pourquoi.
</details>

<details><summary>Indice 3</summary>

Pour comparer une clé d'hôte sans faire confiance au réseau : `qm guest exec <VMID> -- ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` sur `pve01`, et `ssh-keygen -F <adresse> -l` sur `adm01`.
</details>

**Pour aller plus loin** : ajoute au projet un playbook `playbooks/verifier-acces.yml` (connexion, `sudo`, Python, espace disque de `~/.ansible/tmp`) à lancer en premier pendant une astreinte, et une tâche CI qui échoue si un hôte est `UNREACHABLE` au lieu de l'ignorer.

---

### M04-E36 — Panne : le playbook passe mais rien ne change  `BF` `★★★`

> **Ticket SEC-580** — *De : Sophie Laurent*
> Exigence de l'audit HDS : un avertissement légal doit s'afficher **avant** l'authentification SSH (« Accès réservé aux personnes autorisées par MédiSphère. Toute connexion est journalisée. »). Ajoute-le au rôle `ssh_durci` **lui-même** (c'est une règle pour toutes les machines, pas un réglage d'inventaire) et applique-le sur `dns01` d'abord, comme d'habitude.
> *(Note de Lucas, qui a essayé hier : « le playbook passe, tout est vert, mais sur `dns01` `sudo sshd -T | grep -i banner` répond toujours `none`. Je n'y comprends rien. »)*
> Je veux la bannière effective sur `dns01`, et l'explication.

**Objectifs pédagogiques**
- Distinguer « le playbook s'est terminé sans erreur » de « l'état voulu est en place » : mesurer l'état **effectif** du service.
- Savoir quel code Ansible exécute vraiment (résolution des rôles), quelles tâches il sélectionne (étiquettes, configuration), sur quelle machine (inventaire), et comment un service fusionne ses fichiers de configuration.
- Utiliser `--list-tasks`, `--list-hosts`, `-v`, `ansible-config dump --only-changed` et la sortie `--diff` comme instruments.

**Prérequis** : M04-E08, M04-E11 (rôle `ssh_durci`), M04-E19 (étiquettes, `--limit`, `--check`, `--diff`).
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : la valeur effective de `sshd` se lit avec `sudo sshd -T` (configuration complète calculée, tous fichiers inclus). Le fichier principal `/etc/ssh/sshd_config` de Debian 13 inclut `/etc/ssh/sshd_config.d/*.conf` **en tête**.

**Injection** : `lab/bin/break 04 36` (4 variantes ; l'une d'elles crée une VM jetable 2040, pool `lab`, étiquette `env-m04` : l'injection peut prendre deux minutes).

**Travail demandé**
1. Fais la demande de Sophie : le rôle `ssh_durci` dépose le texte de la bannière et la déclare à `sshd` (ton rôle de M04-E11 a peut-être déjà une variable prévue pour cela) ; applique le rôle à `dns01` comme d'habitude. Constate le symptôme : récapitulatif sans erreur, bannière absente (`ssh -o ControlPath=none dns01 true` n'affiche rien, `sshd -T` dit `banner none`).
2. Établis, **par des mesures**, la chaîne complète entre ta modification et la valeur effective : la tâche qui porte le réglage a-t-elle tourné ? A-t-elle changé un fichier ? Lequel, sur quelle machine ? Le service l'a-t-il pris en compte ? Chaque maillon a sa commande : note-la dans ton journal.
3. Trouve la cause racine et corrige-la **à sa source** (pas en contournant : un `--tags` en ligne de commande ou un `lineinfile` de plus ne sont pas des corrections).
4. Applique, vérifie la valeur effective, puis vérifie que le rôle est **idempotent** (second passage : `changed=0`).
5. Écris dans ton journal, pour la variante rencontrée, quel contrôle automatique aurait détecté le problème (Molecule, `--check` en CI, test d'état effectif).

**Critères de réussite**
- [ ] Sur `dns01`, la bannière s'affiche avant l'authentification ; `sudo sshd -T` donne le chemin de son fichier, et aucun fichier de configuration de `sshd` ne la désactive.
- [ ] La valeur vient du rôle `ssh_durci` du dépôt (MR) ; un second passage ne change rien.
- [ ] Rien dans le projet ne détourne plus l'exécution (copie de rôle, filtre d'étiquettes, cible erronée) ; la VM 2040 éventuelle est détruite.

**Vérification** : `lab/bin/check 04 36`

<details><summary>Indice 1</summary>

Trois questions, trois instruments : **quel code ?** (`ansible-playbook … --list-tasks` affiche les tâches et leur rôle ; avec `-vv`, chaque tâche est précédée de `task path:`, le fichier exact qui la contient), **quelles tâches ?** (`ansible-config dump --only-changed`, `--list-tasks`), **quelle machine ?** (`ansible-inventory --host dns01`, puis `ansible dns01 -m ansible.builtin.command -a hostname`).
</details>

<details><summary>Indice 2</summary>

Si le fichier du rôle a bien changé sur la bonne machine mais que `sshd -T` ne bouge pas, la question devient : dans quel ordre `sshd` lit-il ses fichiers, et **quelle** valeur garde-t-il quand un réglage apparaît deux fois ? `man sshd_config`, premier paragraphe.
</details>

<details><summary>Indice 3</summary>

`git status` dans `~/src/ansible` et `ls -la /etc/ssh/sshd_config.d/` sur `dns01` sont deux photographies de « ce qui a bougé ». Les rôles sont cherchés dans un ordre précis, documenté dans *Roles → Storing and finding roles* : le dossier du playbook n'est pas le dernier.
</details>

**Pour aller plus loin** : ajoute au scénario Molecule de `ssh_durci` (M04-E24) une vérification de la valeur **effective** (`sshd -T`) plutôt que du contenu du fichier ; ajoute une règle `ansible-lint` ou un test de dépôt qui refuse un dossier `playbooks/roles/`.

---

### M04-E37 — Panne : la variable n'a pas la valeur attendue  `BF` `★★★`

> **Ticket INC-3143** — *De : Nadia Roussel*
> En corrélant les journaux de cette nuit, `dns01` a deux heures de décalage avec le reste du socle : il est en UTC, les autres en Europe/Paris. Lucas dit qu'il a « juste rejoué le rôle `base` » sur `dns01` hier, et que le rôle force pourtant Europe/Paris. Remets `dns01` à l'heure de Paris **de façon durable** (un nouveau passage du rôle ne doit pas le casser), et explique-moi d'où vient cette valeur.
> ⚠️ Avant de rejouer quoi que ce soit, regarde ce que le rôle ferait sur les **autres** machines.

**Objectifs pédagogiques**
- Maîtriser l'ordre de précédence des variables d'Ansible, y compris les niveaux qu'on oublie : `vars/` d'un rôle, `group_vars` voisins du playbook, groupes enfants.
- Trouver la valeur **effective** d'une variable pour un hôte dans un vrai jeu, et l'endroit qui la définit.
- Évaluer l'impact d'un passage avant de le lancer (`--check --diff`, `--limit`).

**Prérequis** : M04-E06 (précédence), M04-E09, M04-E10 (rôle `base`, variable de fuseau horaire).
**Durée indicative** : 45 min (temps cible).

**Injection** : `lab/bin/break 04 37` (4 variantes).

**Travail demandé**
1. Constate le symptôme (`timedatectl` sur `dns01` et sur un autre hôte). Retrouve le nom de la variable qui porte le fuseau dans le rôle `base`.
2. **Avant toute relance**, mesure l'étendue : `--check --diff` du rôle `base` sur **tout** le socle. Quelles machines passeraient en UTC si tu relançais « pour corriger » ? Note-le : c'est la première ligne de ton analyse d'impact.
3. Trouve la valeur effective de la variable pour `dns01` **dans un jeu qui applique le rôle** (une commande ad hoc ne voit pas tout : pourquoi ?), puis l'endroit qui la définit. Classe dans ton journal tous les endroits du projet où cette variable apparaît, du moins prioritaire au plus prioritaire.
4. Corrige à la racine (retire ou corrige la définition fautive, au bon niveau), applique sur `dns01`, puis vérifie qu'un `--check` sur tout le socle ne prévoit plus aucun changement de fuseau.
5. Propose une règle d'équipe (ou un contrôle automatique) qui aurait empêché cette erreur.

**Critères de réussite**
- [ ] Tous les hôtes du socle sont en Europe/Paris.
- [ ] Dans un jeu qui applique le rôle `base`, la variable vaut Europe/Paris pour `dns01` ; aucune autre valeur n'est définie dans le projet.
- [ ] Ton journal contient le classement des définitions par précédence et l'analyse d'impact faite **avant** la correction.

**Vérification** : `lab/bin/check 04 37`

<details><summary>Indice 1</summary>

`ansible-inventory --host dns01` ne montre que les variables **d'inventaire**. Les `vars/` des rôles, les `group_vars` placés à côté du playbook, les `vars` de jeu n'existent que pendant l'exécution d'un playbook : pour les voir, il faut un jeu (une tâche `debug` étiquetée, lancée en `--check --tags …`).
</details>

<details><summary>Indice 2</summary>

`grep -rn '<nom_de_variable>' inventories/ playbooks/ roles/` puis `git status`. Pour chaque résultat, place-le dans la liste officielle *Understanding variable precedence* de la documentation d'Ansible. Attention : `group_vars` peut exister à **deux** endroits, et ils n'ont pas la même priorité.
</details>

**Pour aller plus loin** : écris un test (pytest ou playbook) qui charge le projet et échoue si une variable préfixée par un nom de rôle (`base_…`) est définie ailleurs que dans `defaults/` du rôle ou dans `group_vars/`/`host_vars/` de l'inventaire.

---

### M04-E38 — Panne : « Decryption failed »  `BF` `★★`

> **Ticket INC-3144** — *De : Julien Petit*
> Plus aucun playbook ne passe depuis `adm01` : tout s'arrête avant la première tâche, sur une erreur du coffre (« Decryption failed » chez moi ; Karim dit avoir eu un message différent hier soir, il ne l'a pas noté). Même `ansible-inventory --graph` échoue. Lucas a « fait un peu de ménage dans les secrets » cette semaine, mais il est en congé. Il me faut les playbooks pour 16 h, **sans** affaiblir la protection des secrets.

**Objectifs pédagogiques**
- Connaître la chaîne de déchiffrement d'Ansible Vault telle que tu l'as construite en M04-E12 et E30 : identités (`vault_identity_list`), script client et fichiers qu'il lit, en-tête des fichiers chiffrés (format, étiquette), correspondance des identités (`vault_id_match`).
- Diagnostiquer un échec de déchiffrement sans jamais afficher un secret en clair dans un terminal partagé ni dans le journal.
- Mener ou annuler proprement une rotation de mot de passe de coffre.

**Prérequis** : M04-E12, M04-E30 (séparation, script client, rotation).
**Durée indicative** : 30 min (temps cible).

**Injection** : `lab/bin/break 04 38` (4 variantes).

**Travail demandé**
1. Reproduis l'erreur avec la commande la plus courte (`ansible-vault view` sur le fichier chiffré du projet). Note le message **exact** : il ne dit pas la même chose selon la cause.
2. Inventorie, sans les afficher, les éléments de la chaîne : identités déclarées et leur source (`ansible-config dump --only-changed`), ce que fournit le script client pour l'identité `lab` (son code retour, pas le secret), fichier de mot de passe (droits, date de modification, voisins), en-tête du fichier chiffré (`head -n 1`), état Git du fichier chiffré et de `ansible.cfg`.
3. Trouve la cause racine. Si une opération a été faite à moitié (rotation), décide en le justifiant : la terminer proprement ou revenir à l'état précédent ? Dans les deux cas, la CI (variable de type fichier, M04-E27) doit rester cohérente.
4. Corrige, puis vérifie que `ansible-inventory --graph` et un `--check` du socle passent.
5. Vérifie qu'aucun secret ne traîne (ancien fichier de mot de passe, copie déchiffrée, historique du shell).

**Critères de réussite**
- [ ] `ansible-vault view inventories/lab/group_vars/all/vault.yml` réussit avec la configuration du projet, sans option supplémentaire.
- [ ] Le fichier de mot de passe est en 600, à toi, et n'est pas exécutable ; aucun ancien fichier de mot de passe ne traîne.
- [ ] Le fichier chiffré est identique à celui du dépôt (ou la rotation est terminée, commitée et répercutée en CI).

**Vérification** : `lab/bin/check 04 38`

<details><summary>Indice 1</summary>

`Decryption failed (no vault secrets were found that could decrypt)` dit « j'ai essayé des secrets, aucun ne convient » : lesquels a-t-il essayés ? Les **avertissements** affichés juste avant (chargement d'un secret refusé, script client en échec) sont souvent plus parlants que l'erreur elle-même. `Vault format unhexlify error` parle d'un tout autre maillon.
</details>

<details><summary>Indice 2</summary>

Ton script client de M04-E30 refuse certains fichiers, et le dit ; un fichier de mot de passe lu directement par Ansible n'est pas lu s'il est **exécutable** : il est exécuté. L'étiquette d'un fichier chiffré (`$ANSIBLE_VAULT;1.2;AES256;<étiquette>`) n'est qu'une indication… sauf quand la configuration exige qu'elle corresponde (`vault_id_match`), et elle ne change rien au mot de passe qui a servi à chiffrer.
</details>

**Pour aller plus loin** : remplace le fichier de mot de passe en clair par un **script** client de mot de passe qui lit le secret dans le trousseau de `adm01` (`secret-tool`, ou `pass`) ; décris ce que cela change pour la CI et pour Semaphore.

---

### M04-E39 — Panne : l'inventaire dynamique est vide  `BF` `★★`

> **Ticket INC-3145** — *De : Karim Benali*
> Le contrôle de dérive de cette nuit dit « 0 hôte, 0 changement » : trop beau pour être vrai. `ansible-inventory -i inventories/lab/proxmox.yml --graph` ne montre plus aucun hôte dans `socle` ni dans les groupes `role_*`, alors que toutes les VMs tournent dans Proxmox. Un inventaire vide qui ne lève pas d'erreur, c'est une supervision aveugle : trouve la cause, et dis-moi comment on fera pour qu'un inventaire vide fasse **échouer** le contrôle.

**Objectifs pédagogiques**
- Comprendre le fonctionnement d'un plugin d'inventaire (`community.proxmox.proxmox`) : vérification du nom du fichier, appels d'API, faits collectés, groupes construits (`keyed_groups`, `groups`, `compose`, `filters`).
- Distinguer « l'API refuse » (erreur, avertissement), « l'API répond vide » (droits effectifs d'un jeton à privilèges séparés) et « l'API répond mais les groupes ne se construisent pas ».
- Rendre un inventaire vide **bruyant**.

**Prérequis** : M04-E13 (inventaire dynamique, compte `wb-ansible@pve`), M02-E36 (jetons Proxmox à privilèges séparés).
**Durée indicative** : 30 min (temps cible).

**Injection** : `lab/bin/break 04 39` (4 variantes).

**Travail demandé**
1. Reproduis le symptôme et lis **tout** ce qu'affiche `ansible-inventory -i inventories/lab/proxmox.yml --graph -vvv` (les avertissements comptent). Compare avec `--list` : y a-t-il des hôtes hors groupes ?
2. Interroge l'API **avec le même jeton**, sans Ansible (`curl`, en-tête `Authorization: PVEAPIToken=…`, CA vérifiée) sur `/cluster/resources?type=vm` : code HTTP, nombre de VMs, présence des étiquettes.
3. Selon le résultat, cherche du côté de Proxmox (`pveum user token list`, `pveum user token permissions`, `pveum acl list`) ou du côté du fichier d'inventaire et de la documentation du plugin (`ansible-doc -t inventory community.proxmox.proxmox`).
4. Corrige à la racine avec le moindre privilège.
5. Rends l'inventaire vide **bloquant** : propose (et ajoute par MR) un garde-fou dans le playbook de dérive ou dans le job CI, qui échoue si le groupe `socle` ne contient pas le nombre d'hôtes attendu.

**Critères de réussite**
- [ ] L'inventaire dynamique seul place les cinq hôtes du socle dans `socle` et chacun dans son groupe `role_*`.
- [ ] Le compte `wb-ansible@pve` a ses ACL d'origine sur `/pool/lab` ; son jeton est valide encore au moins 30 jours.
- [ ] Un garde-fou fait échouer le contrôle de dérive (ou la CI) si l'inventaire est vide ou incomplet.

**Vérification** : `lab/bin/check 04 39`

<details><summary>Indice 1</summary>

Un plugin d'inventaire qui échoue **n'arrête pas** Ansible : l'erreur devient un avertissement (`Unable to parse … as an inventory source`) et l'exécution continue avec ce qui reste (parfois rien). Un plugin qui réussit avec une réponse vide n'affiche rien du tout.
</details>

<details><summary>Indice 2</summary>

Dans la documentation du plugin, lis attentivement les options `want_facts` et la phrase sur les faits utilisables dans `keyed_groups` ; regarde aussi ce que vérifie le plugin sur le **nom** du fichier source (`-vvv` le dit).
</details>

**Pour aller plus loin** : active le cache d'inventaire du plugin (`cache: true`, `cache_plugin`, `cache_timeout`) et décris le nouveau mode de panne qu'il introduit (inventaire **périmé**) et comment le détecter.

---

### M04-E40 — Panne : `sshd` ne redémarre plus après le playbook  `BF` `★★★`

> **Ticket INC-3146** — *De : Nadia Roussel*
> Alerte à 6 h 12 : `runner01` refuse toutes les connexions SSH (« Connection refused »). Le runner GitLab, lui, prend encore les jobs. Hier soir, Lucas a passé le rôle `ssh_durci` et « fait un peu de ménage » sur la machine ; cette nuit, la mise à jour de sécurité d'`openssh-server` a redémarré le service. Lucas jure que le rôle valide la configuration complète avant de recharger `sshd`. Rétablis l'accès **sans réinstaller la VM**, et explique pourquoi toutes ces validations n'ont rien empêché.

**Objectifs pédagogiques**
- Reprendre la main sur une VM sans SSH par l'agent QEMU, proprement et en laissant une trace.
- Savoir ce que valident exactement `validate: sshd -t -f %s` (le fichier du rôle seul), `sshd -t` (la configuration complète, à un instant donné) et ce qu'aucun des deux ne voit (l'adresse d'écoute, un défaut introduit après le passage, l'état révélé au prochain redémarrage).
- Renforcer un rôle pour qu'il protège ce dont dépend l'accès à la machine, et qu'il détecte la dérive avant le prochain redémarrage.

**Prérequis** : M04-E08 (handlers et validation), M04-E11 (rôle `ssh_durci`), M04-E29 (dérive), M00-E39 (agent QEMU).
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : `runner01` est la VM 1007 (10.10.20.15). Sur `pve01`, `qm guest exec 1007 -- <commande>` exécute une commande dans la VM (root) et renvoie un JSON (`exitcode`, `out-data`, `err-data`) ; pour une commande longue, `--timeout` et `qm guest exec-status`. Le service SSH de Debian 13 s'appelle `ssh.service` ; son démarrage commence par un `sshd -t`.

**Injection** : `lab/bin/break 04 40` (4 variantes).

> ⚠️ **Attention** : sur une machine où `sshd` est arrêté, une mauvaise manipulation par l'agent (redémarrage de la VM, suppression des clés d'hôte, `chmod` récursif) peut aggraver la situation. Note chaque commande dans ton journal **avant** de la lancer, et préfère les commandes de lecture tant que la cause n'est pas prouvée.

**Travail demandé**
1. Constate le symptôme depuis `adm01` (`ssh -o ControlPath=none runner01`, test du port 22). Pourquoi le runner GitLab fonctionne-t-il encore ?
2. Par l'agent QEMU, lis l'état du service (`systemctl status ssh`, `journalctl -u ssh -n 50`) et valide la configuration **complète** (`sshd -t`). Note le message exact.
3. Trouve la cause racine. Corrige par l'agent, redémarre le service, vérifie depuis `adm01` avec une **nouvelle** connexion. Si les clés d'hôte ont changé, applique la démarche de M04-E35 (preuve de légitimité avant d'accepter).
4. Explique dans ton journal, pour la variante rencontrée, pourquoi ni `validate:`, ni le `sshd -t` du handler, ni le contrôle de `sshd -T` du rôle n'ont empêché la panne.
5. **Renforce le rôle `ssh_durci`** (MR) contre ce que tu as trouvé : ce dont dépend le démarrage de `sshd` (clés d'hôte et leurs droits, adresses d'écoute) est contrôlé ou géré par le rôle ; la configuration complète est validée **à chaque passage**, y compris en `--check` (pour que le contrôle de dérive nocturne voie un défaut avant le prochain redémarrage) ; et le rôle prouve que `sshd` écoute encore après un rechargement.
6. Rédige la ligne de runbook « plus de SSH sur une VM du socle » (symptôme, accès de secours, premières commandes, retour à la normale).

**Critères de réussite**
- [ ] `runner01` accepte une nouvelle connexion SSH, clé d'hôte vérifiée ; `sshd -t` y passe ; ses clés privées d'hôte sont en 600 ; `sshd` n'écoute que sur des adresses de la machine.
- [ ] Ansible joint `runner01` ; le runner GitLab est toujours actif.
- [ ] Le rôle `ssh_durci` renforcé est fusionné, et ton journal explique la limite de chaque validation.

**Vérification** : `lab/bin/check 04 40`

<details><summary>Indice 1</summary>

`qm guest exec 1007 -- systemctl status ssh --no-pager` puis `qm guest exec 1007 -- sshd -t`. Attention, le JSON renvoie la sortie dans `out-data` **et** `err-data` : `sshd` écrit ses erreurs sur la sortie d'erreur.
</details>

<details><summary>Indice 2</summary>

Une validation ne vaut que pour **l'instant** où elle tourne et **ce** qu'elle teste. `validate:` lit le fichier candidat seul ; `sshd -t` lit toute la configuration et charge les clés, mais ne lie aucun port ; et rien de ce que fait le rôle hier soir ne couvre un fichier modifié après son passage. Le démarrage réel, lui, a lieu au prochain redémarrage du service.
</details>

<details><summary>Indice 3</summary>

Pour le renforcement : une tâche de lecture `sshd -t` avec `changed_when: false` **et** `check_mode: false` s'exécute aussi pendant un `--check` ; `ansible.builtin.wait_for` délégué au contrôleur prouve qu'un port répond ; les adresses de la machine sont dans `ansible_facts['all_ipv4_addresses']`.
</details>

**Pour aller plus loin** : teste ton rôle renforcé dans Molecule en injectant toi-même un fichier invalide dans `sshd_config.d` (étape `prepare`) : le rôle doit échouer **avant** de toucher au service.

---

### M04-E41 — Panne : le playbook est devenu très lent  `BF` `★★★`

> **Ticket INC-3147** — *De : Karim Benali*
> Le passage complet de `site.yml` prenait environ 4 minutes. Depuis hier, c'est interminable (j'ai arrêté au bout de 20 minutes) : aucune erreur, tout est « ok », mais chaque tâche se traîne. Le pipeline de dérive dépasse son délai. Trouve ce qui ralentit, **prouve-le par la mesure** (pas d'intuition), et donne-moi les chiffres avant/après.

**Objectifs pédagogiques**
- Mesurer où passe le temps d'une exécution Ansible : par tâche, par hôte, par connexion (`profile_tasks`, `timer`, `-vvvv` horodaté).
- Connaître les leviers de performance et l'endroit où chacun peut être réglé (configuration, environnement, variables d'inventaire) : `forks`, multiplexage SSH, `pipelining`, stratégie d'exécution.
- Comprendre l'effet d'un hôte lent sur la stratégie `linear`.

**Prérequis** : M04-E26 (performances), M04-E25 (`serial`, stratégies).
**Durée indicative** : 45 min (temps cible).

**Injection** : `lab/bin/break 04 41` (4 variantes).

**Travail demandé**
1. Mesure avant de chercher : une commande simple avec élévation sur tout le socle (`ansible socle -b -m ansible.builtin.command -a true`), chronométrée, puis le rôle `base` en `--check` avec les callbacks `ansible.posix.profile_tasks` et `ansible.posix.timer` activés **pour cette commande** (variable d'environnement). Garde les chiffres.
2. Décompose : le temps est-il réparti sur tous les hôtes ou concentré sur un seul ? Sur l'établissement des connexions ou sur l'exécution des modules ? (`-vvvv` montre chaque `SSH: EXEC` ; compte-les.)
3. Établis la configuration **effective** de connexion : `ansible-config dump --only-changed`, `ansible-config dump -t connection ssh`, et les variables de connexion de l'inventaire (`ansible-inventory --host <hôte>`). Rappelle-toi quelle source l'emporte sur quelle autre.
4. Trouve la cause racine, corrige-la à sa source, puis remesure exactement comme à l'étape 1. Consigne le tableau avant/après.
5. Si un seul hôte ralentissait tout : explique l'effet de la stratégie `linear` et dis ce qu'auraient changé `strategy: free` et `serial`, et pourquoi ni l'un ni l'autre n'est la correction.

**Critères de réussite**
- [ ] `ansible socle -b -m ansible.builtin.command -a true` prend moins de 20 secondes.
- [ ] Parallélisme (`forks` ≥ 5), multiplexage SSH et `pipelining` sont effectifs pour tous les hôtes, quelle que soit la source de configuration ; `sudo` répond en moins de 2 secondes sur chaque hôte.
- [ ] Ton journal contient le tableau de mesures avant/après et la commande qui a prouvé la cause.

**Vérification** : `lab/bin/check 04 41`

<details><summary>Indice 1</summary>

`ANSIBLE_CALLBACKS_ENABLED=ansible.posix.profile_tasks,ansible.posix.timer ansible-playbook …` (vérifie le nom exact de la variable dans `ansible-config list`). Si toutes les tâches sont lentes de façon uniforme, c'est le transport ; si une tâche l'est, c'est la tâche ; si un hôte l'est, regarde ce qui est propre à cet hôte.
</details>

<details><summary>Indice 2</summary>

Une variable d'inventaire nommée comme une option de connexion (`ansible_ssh_args`, `ansible_pipelining`…) l'emporte sur `ansible.cfg`. `ansible-config dump` ne la montre pas : il faut la chercher dans l'inventaire. Et sur l'hôte cible, `time sudo -n true` mesure ce que chaque tâche avec `become` paie.
</details>

<details><summary>Indice 3</summary>

Si `sudo` est lent sur une seule machine : `journalctl -t sudo`, `/etc/pam.d/sudo`, et ce qu'une session PAM peut lancer à l'ouverture et à la fermeture.
</details>

**Pour aller plus loin** : ajoute au pipeline de dérive un seuil de durée (le job échoue s'il dépasse 2 fois sa durée habituelle) et exporte la durée de chaque passage, pour une future métrique (module 21).

---

### M04-E42 — Panne : Molecule échoue avant même de tester  `BF` `★★`

> **Ticket DEV-580** — *De : Julien Petit*
> Toutes les MR de `plateforme/ansible` sont bloquées : le job `molecule` échoue, et pas sur mes tests, il n'arrive même pas à les lancer. En local, `molecule test` sur le rôle `base` fait pareil : il s'arrête pendant la création des instances. Personne n'a touché à `molecule/` depuis des semaines. Il faut débloquer la CI, et que ça ne se reproduise pas sans prévenir.

**Objectifs pédagogiques**
- Connaître la séquence de `molecule test` (dépendances, nettoyage, destruction, syntaxe, création, préparation, convergence, idempotence, vérification…) et savoir isoler une étape (`molecule create`, `molecule destroy`, `--debug`).
- Diagnostiquer ce dont dépend la création d'instances sur Proxmox : image source et ses étiquettes, droits du jeton, VMID libres, agent QEMU.
- Rendre ces dépendances explicites (vérifications préalables, messages d'erreur utiles) dans `create.yml`.

**Prérequis** : M04-E24 (Molecule sur VMs éphémères, `create.yml`/`destroy.yml`), M03-E10 (publication de l'image `current`).
**Durée indicative** : 30 min (temps cible).

**Injection** : `lab/bin/break 04 42` (4 variantes ; tout se passe sur `pve01`).

**Travail demandé**
1. Reproduis en local, étape par étape, depuis la racine du projet et avec le fichier d'accès Proxmox chargé : `molecule destroy -s base`, puis `molecule create -s base` seul (avec `--debug` si besoin). Note la tâche de `molecule/_commun/create.yml` qui échoue (ou qui attend jusqu'à épuiser ses essais) et son message.
2. Vérifie chaque dépendance de la création **sans Molecule** : l'image source attendue existe-t-elle (avec les étiquettes que `create.yml` cherche) ? le jeton a-t-il le droit de cloner ? les VMID 2045-2049 sont-ils libres ? un clone obtient-il une adresse par l'agent ?
3. Trouve la cause racine et corrige-la au bon endroit. Si des VMs traînent, détruis-les après avoir vérifié **ce qu'elles sont** (une instance Molecule oubliée, pas une VM de quelqu'un d'autre).
4. Relance `molecule test` en entier, puis le pipeline de la MR bloquée.
5. Complète `create.yml` (MR) pour que **chaque** dépendance rencontrée soit vérifiée avant le clonage, avec un message qui dit quoi faire (et renvoie à un runbook) ; en particulier, une image dont l'agent QEMU est désactivé ou un droit de clonage manquant doivent être signalés comme tels, pas par un délai d'attente épuisé ou une erreur d'API brute.

**Critères de réussite**
- [ ] Une seule image dorée `gold`+`debian13`+`current`, agent QEMU activé ; le rôle `WBAnsible` permet le clonage ; les VMID 2045-2049 sont libres.
- [ ] `molecule test` passe pour le rôle `base`, et un job `molecule` a réussi en CI depuis.
- [ ] `create.yml` vérifie aussi l'agent de l'image et le droit de clonage, et échoue avec un message explicite (MR fusionnée).

**Vérification** : `lab/bin/check 04 42`

<details><summary>Indice 1</summary>

Molecule enchaîne des playbooks ordinaires : l'échec de `create` est l'échec d'une tâche Ansible, avec son module et son message. Lis-le comme tel : ton `create.yml` de M04-E24 vérifie déjà plusieurs prérequis et dit lequel manque. `molecule --debug create -s base` montre la commande `ansible-playbook` lancée et ses variables.
</details>

<details><summary>Indice 2</summary>

Sur `pve01` : `pvesh get /cluster/resources --type vm --output-format json` (étiquettes, templates), `qm config <template>`, `pveum role list`, `pveum user token permissions wb-ansible@pve ansible --path /vms/<id>`, `qm list | awk '$1 >= 2045 && $1 <= 2049'`.
</details>

**Pour aller plus loin** : ajoute à `destroy.yml` la destruction des instances **orphelines** (étiquette `molecule`, plus anciennes que 2 heures) et un job planifié qui la lance chaque nuit.

---

### M04-E43 — Astreinte : la chaîne de configuration en panne  `BF` `★★★★`

> **Ticket INC-3150** — *De : Nadia Roussel (responsable astreinte)* — priorité P2
> Tu es d'astreinte. Mardi, 7 h 40 : plusieurs remontées sur la chaîne de configuration du socle (le détail s'affiche à l'injection). La fenêtre de maintenance de ce soir (mises à jour de sécurité par `site.yml`) est menacée. Je ne sais pas si c'est lié. Rétablis la chaîne, tiens-moi informée toutes les 30 minutes, puis rédige le post-mortem avec le modèle de l'équipe.

**Objectifs pédagogiques**
- Gérer un incident à causes multiples : trier, prioriser, éviter qu'une panne en masque une autre.
- Choisir l'ordre de traitement selon les dépendances de la chaîne (accès aux hôtes, coffre, inventaire, code, exécution, tests).
- Communiquer pendant l'incident et rédiger un post-mortem sans recherche de coupable.

**Prérequis** : M04-E35 à M04-E42 (au moins une variante de chacun) ; M00-E46 (méthode d'astreinte et modèle de post-mortem).
**Durée indicative** : 2 h de rétablissement + 45 min de post-mortem.

**Contexte technique** : le script tire **deux** pannes distinctes parmi celles de M04-E35 à M04-E42 (variantes aléatoires) et les injecte ensemble ; l'injection peut prendre plusieurs minutes. Les symptômes peuvent se recouvrir (deux pannes peuvent toucher le même fichier ou le même hôte). `--variante N` (1 à 28) force la paire, pas les variantes. `--annuler` retire les deux. Ta copie de travail doit être propre avant l'injection. Modèle de post-mortem : [`modules/00-lab/ressources/M00-E46/modele-post-mortem.md`](../../00-lab/ressources/M00-E46/modele-post-mortem.md).

**Injection** : `lab/bin/break 04 43`

**Travail demandé**
1. **Triage (10 min max)** : liste les symptômes, leur impact (qu'est-ce qui ne peut plus être fait ce soir ?), une première hypothèse de regroupement, et les contrôles `lab/bin/check 04 35` à `04 42` en rouge. Envoie la première communication.
2. **Diagnostic** : traite les pannes dans l'ordre que tu justifies. Commence par ce qui conditionne tes instruments : si Ansible ne peut ni lire son coffre ni joindre les hôtes, aucun autre test n'est fiable.
3. **Rétablissement** : corrige chaque cause racine ; après chaque correction, relance **tous** les tests du triage. Ne relance `site.yml` qu'après un `--check --diff` complet lu ligne à ligne.
4. **Clôture** : communication de fin, `--annuler` pour clore, post-mortem dans `docs/socle/post-mortems/AAAA-MM-JJ-INC-3150.md` de `~/medisphere`, commité et publié par MR.

**Critères de réussite**
- [ ] Toutes les vérifications de M04-E35 à M04-E42 sont vertes (le contrôle les rejoue) ; aucune panne `M04` n'est encore marquée active.
- [ ] Le post-mortem contient une chronologie horodatée, les deux causes racines prouvées, l'analyse de la détection et des actions avec responsable et échéance ; il est commité.
- [ ] Ton journal contient au moins trois communications espacées d'environ 30 minutes.

**Vérification** : `lab/bin/check 04 43`

<details><summary>Indice 1</summary>

`git status` et `git diff` dans `~/src/ansible` sont ton premier instrument de triage : ce qui a changé dans la copie de travail depuis le dernier commit est une liste de suspects. Mais toutes les pannes ne passent pas par là (hôtes, `pve01`).
</details>

<details><summary>Indice 2</summary>

Les contrôles `lab/bin/check 04 35` à `04 42` sont des sondes de triage. Certains lancent Ansible : si le coffre ne s'ouvre pas, ils seront tous rouges pour la même raison. Commence par ce qui fausse les autres.
</details>

**Pour aller plus loin** (facultatif) : fais-toi injecter une astreinte par quelqu'un d'autre (`--variante` tirée par lui), sans regarder l'écran pendant l'injection, et chronomètre ton temps de rétablissement.

---

### M04-E44 — Sous le capot : AnsiballZ et un module maison  `LAB` `★★★★`

> **Ticket PLAT-580** — *De : Karim Benali*
> Deux choses. Un : pendant les pannes, j'ai entendu trop de « Ansible exécute le module sur la machine ». Je veux que tu saches **montrer** ce qui part de `adm01`, ce qui est écrit sur la cible, ce qui est exécuté et ce qui revient. Deux : Nadia veut que `chrony` redémarre tout seul s'il tombe, sur tout le socle. Fais-le avec un **module maison** de notre collection `medisphere.socle`, `systemd_dropin`, qui gère un fichier de surcharge systemd proprement : idempotent, `--check`, `--diff`, testé. Oui, un `template` et un handler suffiraient ; justement, je veux qu'on sache quand un module vaut mieux, et qu'on sache l'écrire.

**Objectifs pédagogiques**
- Comprendre le cycle d'exécution d'un module Python : construction du paquet AnsiballZ sur le contrôleur (module + `module_utils` + arguments), transfert ou *pipelining*, extraction et exécution sur la cible, retour JSON.
- Déboguer un module **sur la cible** (`ANSIBLE_KEEP_REMOTE_FILES`, sous-commandes `explode` et `execute`).
- Écrire un module conforme : `AnsibleModule`, `argument_spec`, documentation (`DOCUMENTATION`, `EXAMPLES`, `RETURN`), mode vérification, `--diff`, écriture atomique, arguments de fichier communs, codes d'erreur ; le tester unitairement.

**Prérequis** : M04-E18 (collection `medisphere.socle`), M04-E26 (pipelining), M02-E14/E15 (tests).
**Durée indicative** : 4 à 5 h.

**Contexte technique**
- Le module se place dans `collections/ansible_collections/medisphere/socle/plugins/modules/systemd_dropin.py` (versionné, comme toute la collection interne), ses tests dans `collections/ansible_collections/medisphere/socle/tests/unit/plugins/modules/`. `ansible.module_utils.testing.patch_module_args` (ansible-core ≥ 2.19) fournit les arguments à `AnsibleModule` dans un test.
- **Contrat du module** (Karim relira la MR contre ce contrat) :

  | Option | Type | Défaut | Rôle |
  |---|---|---|---|
  | `unit` | str, obligatoire | — | unité surchargée, suffixe compris (`chrony.service`) |
  | `name` | str | `50-medisphere` | nom du fichier de surcharge, sans `.conf` |
  | `settings` | dict | — | `{Section: {Clé: valeur}}` ; une valeur liste donne une ligne par élément ; obligatoire si `state=present` |
  | `state` | `present` / `absent` | `present` | `absent` supprime le fichier (et le dossier `.d/` s'il devient vide) |
  | `daemon_reload` | bool | `true` | lancer `systemctl daemon-reload` après une modification **du contenu** |
  | `unit_dir` | path | `/etc/systemd/system` | dossier des unités (sert aux tests) |
  | arguments de fichier communs | | | `owner`, `group`, `mode` (défaut `0644`)… |

  Valeurs de retour : `changed`, `path`, `content`, `daemon_reloaded` ; `diff` (avant/après) avec `--diff`. Le module ne redémarre **jamais** le service : c'est le rôle d'un handler.
- Squelette fourni (facultatif) : [`ressources/M04-E44/squelette_systemd_dropin.py`](../ressources/M04-E44/squelette_systemd_dropin.py).

**Travail demandé**
1. **Ce qui part et ce qui arrive.** Sur `dns01`, sans pipelining pour cette commande :
   ```
   admin@adm01:~/src/ansible$ ANSIBLE_KEEP_REMOTE_FILES=1 uv run ansible dns01 -m ansible.builtin.ping -a data=octobre -e ansible_pipelining=false -vvv
   ```
   Repère dans la sortie : la création du dossier temporaire, le transfert (`PUT`), le `chmod`, l'exécution, la suppression (absente ici : pourquoi ?). Sur `dns01`, retrouve le fichier `AnsiballZ_ping.py`. Lis sa fin : quels paramètres reçoit `_ansiballz_main` ? Où sont les arguments de la tâche ? Que contient `zip_data` ?
2. **Explode / execute.** Toujours sur `dns01` : `python3 …/AnsiballZ_ping.py explode`, parcours le dossier produit (quels fichiers de `module_utils` ont été embarqués, et pourquoi ceux-là ?), modifie `debug_dir/args` pour passer `data` à `crash`, puis `python3 …/AnsiballZ_ping.py execute`. Que se passe-t-il ? Supprime ensuite le dossier temporaire conservé.
3. **Avec pipelining.** Relance la commande de l'étape 1 sans `-e ansible_pipelining=false`. Qu'est-ce qui disparaît de la sortie `-vvv` ? Le module est-il encore extrait quelque part sur la cible (relis le début de `_ansiballz_main`) ? Pourquoi le pipelining exige-t-il que `sudo` n'impose pas `requiretty` ?
4. **Le module.** Écris `systemd_dropin` selon le contrat. Exigences : contenu entièrement généré dans un ordre stable (idempotence), refus des valeurs qui contiennent un saut de ligne, écriture atomique (`module.atomic_move`), droits par `load_file_common_arguments` / `set_fs_attributes_if_different`, aucune écriture ni `daemon-reload` en mode vérification, `diff` avant/après, erreurs par `fail_json` avec un message utile. `ansible-doc medisphere.socle.systemd_dropin` doit afficher ta documentation.
5. **Les tests.** Au moins 6 tests unitaires (pytest) : création puis idempotence, mode vérification sans effet, `--diff`, correction d'une modification manuelle, changement de droits seul (sans `daemon-reload`), suppression, erreurs de paramètres. `systemctl` ne doit jamais être réellement appelé par les tests. Ajoute `pytest` aux dépendances de développement du projet et un job CI (ou une étape du job existant) qui les lance.
6. **L'usage.** Dans le rôle `base`, utilise le module pour que `chrony.service` redémarre seul (`Restart=on-failure`, `RestartSec=5s`, et une limite de redémarrages raisonnable dans `[Unit]`), avec un handler de redémarrage de `chrony`. Teste-le dans Molecule, passe `--check --diff` sur le socle, applique par la chaîne habituelle, vérifie l'idempotence. Enfin, prouve l'effet sur `dns01` : `sudo systemctl kill -s KILL chrony` puis, après quelques secondes, `systemctl status chrony`.
7. **Déboguer ton module sur la cible.** Provoque une fois une erreur de ton module (par exemple une section invalide) et suis-la avec `explode`/`execute` sur `dns01`, comme à l'étape 2.
8. **L'analyse.** Rédige `docs/analyses/ansiballz.md` dans `plateforme/ansible` : un schéma du cycle d'exécution d'une tâche (contrôleur → cible → contrôleur), tes observations des étapes 1 à 3, puis une section `## Réponses aux questions` traitant les questions ci-dessous (une réponse numérotée par question).

> ⚠️ **Attention** : `systemctl kill -s KILL chrony` (étape 6) arrête brutalement le service de temps de `dns01` pendant quelques secondes. Fais-le sur `dns01` seulement, après avoir vérifié que la surcharge est en place (`systemctl show chrony -p Restart`), et contrôle ensuite `chronyc tracking`. Si le service ne revient pas : `sudo systemctl start chrony`.

**Questions** (à traiter dans l'analyse)
1. Pourquoi Ansible empaquette-t-il le module **et** des fichiers de `module_utils` dans une archive zip encodée en base64 plutôt que de copier le fichier du module ? Comment détermine-t-il quels `module_utils` embarquer ?
2. Que sont les arguments `_ansible_check_mode`, `_ansible_diff`, `_ansible_no_log`, `_ansible_remote_tmp` que tu as vus dans `args` ? Qui les lit ?
3. Où le paquet est-il écrit et exécuté sans pipelining, avec pipelining, et avec `become` vers un utilisateur **non privilégié** (problème des droits sur les fichiers temporaires) ?
4. Pourquoi un module ne doit-il rien écrire sur la sortie standard en dehors de son JSON final ? Que se passe-t-il sinon ?
5. Que fait Ansible d'une tâche en `--check` si le module ne déclare pas `supports_check_mode=True` ? Quelle conséquence pour un rôle qui en dépend ?
6. Pourquoi `atomic_move` plutôt qu'une écriture directe dans le fichier cible ? Quel risque concret pour un fichier lu par systemd ou `sshd` ?
7. Quand écrire un module plutôt qu'un `template` + handler, un rôle, ou un plugin de filtre ? Donne deux critères pour, deux contre, appliqués à `systemd_dropin`.
8. Qu'est-ce qu'un *action plugin* (exemple : `template`, `copy`) et en quoi diffère-t-il d'un module ? Pourquoi `template` en a-t-il besoin ?
9. Comment Ansible choisit-il l'interpréteur Python de la cible (`interpreter_python`, découverte, avertissement) ? Que se passe-t-il si la cible n'a pas de Python, et quels modules fonctionnent quand même ?
10. Qu'apporte `ansible-test sanity` à une collection ? Cite trois contrôles qu'il fait sur un module.

**Critères de réussite**
- [ ] Le module est versionné dans la collection `medisphere.socle`, se documente (`ansible-doc`), déclare le mode vérification et gère `--diff`.
- [ ] Ses tests unitaires (au moins 6) passent en local et en CI.
- [ ] Le rôle `base` l'utilise : `chrony` a `Restart=on-failure` sur tous les hôtes du socle, un second passage ne change rien, et le redémarrage automatique a été démontré sur `dns01`.
- [ ] `docs/analyses/ansiballz.md` contient le schéma, les observations et au moins 8 réponses numérotées.

**Vérification** : `lab/bin/check 04 44`

<details><summary>Indice 1</summary>

La documentation *Developing modules* d'Ansible (sections *Ansible module architecture*, *Debugging modules*, *Conventions, tips and pitfalls*) décrit AnsiballZ, `explode`/`execute` et les attentes envers un module. Le code du « wrapper » est lisible tel quel dans le fichier `AnsiballZ_*.py` conservé.
</details>

<details><summary>Indice 2</summary>

`module.check_mode` et `module._diff` portent les deux modes ; un `diff` peut être une **liste** de dictionnaires (contenu, puis attributs). `set_fs_attributes_if_different(file_args, changed, diff=…)` remplit lui-même un dictionnaire de différences d'attributs : ne lui passe pas celui du contenu.
</details>

<details><summary>Indice 3</summary>

Pour les tests : `with patch_module_args({...}):` puis appel de `main()` ; remplace `exit_json`/`fail_json` par des fonctions qui lèvent une exception portant le résultat (sinon `sys.exit` interrompt pytest), et `run_command`/`get_bin_path` par des doublures.
</details>

**Pour aller plus loin** : fais passer `ansible-test sanity --docker` (ou `--venv`) à la collection et corrige ses remarques ; ajoute une option `verify` qui lance `systemd-analyze verify` sur l'unité avec la surcharge candidate avant de l'installer (comme `validate:`), et discute ses limites (unités qui référencent des fichiers absents dans un environnement de test).

---

### M04-E45 — Questions expert : moteur d'Ansible  `Q` `★★★`

> **Ticket PLAT-581** — *De : Karim Benali*
> Dernière étape avant la recette de la chaîne de configuration : ces questions, je les pose en entretien pour un poste d'ingénieur plateforme senior. Réponds par écrit, en argumentant. Pas de recherche pendant la première passe ; vérifie ensuite dans la doc et corrige-toi en couleur.

**Objectifs pédagogiques**
- Consolider la compréhension du moteur d'exécution d'Ansible : variables, templates, stratégies, handlers, connexions, élévation, coffre, inventaire.
- S'entraîner à argumenter une réponse technique comme en entretien ou en revue de code.

**Prérequis** : paliers 1 à 3 du module, M04-E35 à M04-E44.
**Durée indicative** : 2 h 30.

**Questions**

1. Classe ces sources de la variable `base_fuseau_horaire`, de la moins prioritaire à la plus prioritaire : `roles/base/defaults/main.yml` ; `roles/base/vars/main.yml` ; `inventories/lab/group_vars/all/main.yml` ; `inventories/lab/group_vars/role_dns/main.yml` ; `playbooks/group_vars/all/main.yml` ; `inventories/lab/host_vars/dns01/main.yml` ; `vars:` du jeu ; `set_fact` dans une tâche précédente ; `-e base_fuseau_horaire=UTC`. Lesquelles de ces sources sont visibles par `ansible-inventory --host dns01` ?
2. QCM — Une variable de jeu est définie par `vars: { horodatage: "{{ lookup('ansible.builtin.pipe', 'date +%s') }}" }`. Deux tâches successives affichent `horodatage` à 3 secondes d'intervalle. Elles affichent :
   a) la même valeur, calculée au chargement du jeu ; b) deux valeurs différentes, l'expression étant évaluée à chaque utilisation ; c) la même valeur, mise en cache par `lookup` ; d) une erreur, les lookups étant interdits dans `vars`.
   Comment figer la valeur une fois pour toutes ?
3. ansible-core 2.19 a introduit le *data tagging* et un modèle de **confiance** des modèles Jinja2. Pourquoi `when: "{{ resultat.stdout }} == 'ok'"` ne fonctionne-t-il plus, et qu'est-ce qu'une chaîne « non fiable » (*untrusted*) ? Pourquoi une condition `when: ma_liste` (liste non vide) est-elle désormais une erreur ?
4. Décris les stratégies `linear`, `free` et `host_pinned`. Sur le socle (5 hôtes, `forks = 5`), un hôte met 6 s par tâche (pannes de M04-E41), les autres 0,5 s : estime la durée d'un rôle de 40 tâches avec chacune.
5. Différence entre `forks`, `serial`, `throttle` et `run_once` ? Que se passe-t-il pour une tâche `run_once` dans un jeu avec `serial: 2` ?
6. QCM — Dans un jeu, deux tâches notifient le même handler `Recharger ssh`, puis une troisième tâche échoue sur l'hôte. Par défaut :
   a) le handler s'exécute une fois, à la fin du jeu ; b) il s'exécute deux fois ; c) il ne s'exécute pas sur cet hôte ; d) il s'exécute immédiatement après chaque notification.
   Quels réglages changent ce comportement, et quel risque concret pour `ssh_durci` ?
7. `import_tasks` contre `include_tasks` : moment de l'analyse, effet de `when` et des `tags` posés sur l'instruction, visibilité dans `--list-tasks`, boucles. Lequel choisir pour un fichier de tâches choisi d'après un fait (`ansible_facts['os_family']`) ?
8. `delegate_to: localhost` dans une tâche qui itère sur le socle : quelles variables voit la tâche (celles de l'hôte d'inventaire ou de `localhost`) ? Où vont les faits collectés, et à quoi sert `delegate_facts` ?
9. Que fait `--check` pour un module qui ne le gère pas ? Pour `ansible.builtin.command` ? Pourquoi un passage `--check` peut-il échouer là où le vrai passage réussirait, et comment l'écrire proprement (`check_mode: false`, `ansible_check_mode`) ?
10. Explique le *pipelining* : ce qu'il supprime, pourquoi il n'est pas activé par défaut, et pourquoi il ne fonctionne pas avec `become` si `sudo` impose `requiretty`.
11. Comment Ansible appelle-t-il `sudo` (forme de la commande, rôle de `-n`, de `-S`, de la chaîne `BECOME-SUCCESS-…`) ? Pourquoi `become_user: postgres` (non privilégié) pose-t-il un problème de fichiers temporaires sans pipelining, et quelles sont les solutions ?
12. Multiplexage SSH : rôle de `ControlMaster`, `ControlPersist`, `ControlPath` ; pourquoi Ansible place-t-il ses propres sockets dans `~/.ansible/cp` ; quelle panne classique vient d'un socket orphelin, et laquelle d'un chemin trop long ?
13. Format d'un fichier chiffré par Ansible Vault : en-tête, algorithme de chiffrement, dérivation de clé, contrôle d'intégrité. Sur un fichier abîmé (une ligne supprimée, un caractère changé), pourquoi `ansible-vault view` ne répond-il pas toujours « Decryption failed » ? Que protège réellement Vault, et que ne protège-t-il pas (mémoire, journaux, `-vvv`, `no_log`) ?
14. Un plugin d'inventaire peut-il échouer sans faire échouer la commande ? Explique le comportement par défaut et les options qui le rendent strict (`unparsed_is_failed` et `any_unparsed_is_failed` de la section `[inventory]`, `strict` des plugins *constructed*). Lesquelles activer pour le contrôle de dérive ?
15. Comment `keyed_groups` transforme-t-il l'étiquette Proxmox `role-dns` en nom de groupe ? Pourquoi les caractères non valides sont-ils remplacés, et quel piège cela crée-t-il (deux étiquettes, un seul groupe) ?
16. `hash_behaviour = merge` : que fait-il, pourquoi est-il déconseillé, et que proposer à la place pour fusionner des dictionnaires de configuration (filtre `combine`, conventions de nommage) ?
17. Idempotence : pourquoi `ansible.builtin.command` est-il toujours `changed` ? Donne trois façons de le rendre idempotent, et explique pourquoi `changed_when: false` partout est une faute.
18. Collecte des faits : coût, `gather_subset`, délai, cache de faits (`fact_caching`, `gathering = smart`). Quel nouveau mode de panne le cache introduit-il ? Et pourquoi écrire `ansible_facts['distribution']` plutôt que `ansible_distribution` ?
19. `ignore_errors`, `failed_when`, `ignore_unreachable`, `any_errors_fatal`, `max_fail_percentage` : pour chacun, un cas d'usage légitime sur le socle et un abus.
20. Push (Ansible classique, Semaphore, CI) contre pull (`ansible-pull`, agents Puppet/Salt) : pour le socle de MédiSphère, quels arguments de sécurité (qui détient les clés et les secrets ?), de détection de dérive et de résilience (le contrôleur est en panne) ?

**Critères de réussite**
- [ ] Les 20 questions ont une réponse écrite et argumentée (pour les QCM : la bonne réponse **et** pourquoi les autres sont fausses).
- [ ] Après correction, tu as identifié tes trois points les plus faibles et noté un exercice ou une lecture pour chacun.

<details><summary>Indice 1</summary>

Pour les questions 1 à 9 : *Using variables* (*Understanding variable precedence*), *Templating* et le *porting guide* d'ansible-core 2.19, *Controlling playbook execution: strategies and more*, *Handlers*, *Re-using Ansible artifacts*, *Controlling where tasks run*, *Validating tasks: check mode and diff mode*.
</details>

<details><summary>Indice 2</summary>

Pour les questions 10 à 18 : documentation du plugin de connexion `ansible.builtin.ssh` et du plugin d'élévation `ansible.builtin.sudo` (`ansible-doc -t connection ssh`, `ansible-doc -t become sudo`), *Vault* (*Format of files encrypted with Ansible Vault*), `ansible-config list` pour les options d'inventaire et de cache, et tes observations de M04-E39, E41 et E44.
</details>

**Pour aller plus loin** (facultatif) : choisis trois questions et transforme chacune en démonstration reproductible de 5 minutes dans le projet (`playbooks/demos/`), à présenter à Karim.
