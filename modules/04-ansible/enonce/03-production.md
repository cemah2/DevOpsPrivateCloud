# Module 04 — Palier 3 : Production

Les rôles existent, le socle se décrit en YAML, les secrets sont chiffrés, l'inventaire vient de Proxmox. Mais tout part encore de ton poste : c'est toi qui lances `ansible-playbook`, avec tes clés, ta version d'Ansible, et ce qui n'est pas dans le journal de ton terminal n'a jamais existé. Karim Benali le rappelle en revue : « un rôle qui n'est pas idempotent et testé n'entre pas dans `main` ». Sophie Laurent veut, pour l'audit HDS, savoir **qui** a changé **quoi** sur le socle, **quand**, et la preuve que les machines n'ont pas dérivé depuis. Nadia Roussel veut un bouton pour l'astreinte, pas un terminal. Ce palier industrialise la chaîne : tests sur des VMs jetables (E24), déploiements progressifs (E25), performances (E26), chaîne CI avec application contrôlée (E27), orchestrateur Semaphore UI (E28), détection de dérive (E29), Vault en production (E30), la décision d'architecture qui fixe tout ça (E31), et les questions qu'on te posera en entretien ou en revue (E32, E33). Un exercice chronométré clôt le palier (E34).

> **Rappels** : tout se fait depuis `adm01`, dans `~/src/ansible` (variable `WB_SRC`), par MR fusionnée dans `main` avec pipeline vert ; les commandes Ansible passent par l'environnement du projet (`uv run …`). Accès Proxmox d'Ansible : `~/.config/workbook/pve-ansible.env` (jeton `wb-ansible@pve!ansible`, E13), à charger avant toute commande qui parle à l'API : `set -a; . ~/.config/workbook/pve-ansible.env; set +a`. VMs du module : 2040-2049, étiquette `env-m04` ; dans ce palier 2041 `sem01`, 2042-2044 la flotte de démonstration (E25-E26), 2045-2049 les instances Molecule, **toujours détruites** après usage.

> ⚠️ **Ce palier modifie des choses qui peuvent te couper du socle** : le pare-feu de `gw01` (nouveaux flux pour `runner01` et `sem01`), les clés autorisées de `admin` sur toutes les VMs (rôle `base`), et il donne à des machines autres que `adm01` le pouvoir d'appliquer la configuration. Avant chaque application : session SSH ouverte sur l'hôte concerné, `--check --diff` relu, filet anti-coupure du rôle `pare_feu` (E17) actif. Retour arrière général : la console série de chaque VM (`ssh pve01 qm terminal <VMID>`, sortie par `Ctrl+O`) et l'étiquette Git du dernier état appliqué.

---

### M04-E24 — Molecule : tester un rôle sur des VMs éphémères  `LAB` `★★★`

> **Ticket PLAT-550** — *De : Karim Benali*
> Ta règle, c'est la mienne : un rôle non testé n'entre pas dans `main`. Aujourd'hui « testé » veut dire « Lucas l'a lancé sur `dns01` et ça n'a rien cassé ». Je veux un test reproductible : une VM neuve issue de l'image dorée `current`, le rôle appliqué, un second passage qui ne change rien, des vérifications de l'état obtenu, et la VM détruite quoi qu'il arrive. Pas de conteneurs : nos rôles touchent à systemd, sshd et nftables, on verra Docker au module 12. Commence par `base` et `ssh_durci`.

**Objectifs pédagogiques**
- Comprendre le cycle de vie d'un scénario Molecule (`create`, `prepare`, `converge`, `idempotence`, `verify`, `destroy`) et l'approche « ansible-native » de Molecule 26 (pilote `default`, création des instances par tes propres playbooks).
- Gérer des VMs Proxmox éphémères avec `community.proxmox` : clonage de l'image dorée, cloud-init, adresse via l'agent QEMU, destruction garantie.
- Écrire des vérifications qui portent sur l'**état** obtenu, pas sur les tâches exécutées.
- Donner à un jeton d'automatisation juste les droits nécessaires, et des garde-fous qui l'empêchent de détruire autre chose que ses instances.

**Prérequis** : M03-E25 (image dorée Debian `current`), M04-E10 et M04-E11 (rôles `base`, `ssh_durci`), M04-E13 (jeton `wb-ansible@pve!ansible`), M04-E20 (ansible-lint).
**Durée indicative** : 4 h.

**Contexte technique**
- Molecule 26 (déjà dans le groupe `dev` de `pyproject.toml`, E02) : `uv run molecule --version`. Documentation : <https://docs.ansible.com/projects/molecule/> (pages *Ansible-native configuration* et *Configuration*).
- Instances : VMID **2045-2049** (2045 `base`, 2046 `ssh_durci`, 2047 `pare_feu`, 2048 `gitlab_runner`, 2049 réservé à l'E34), noms `m04-mol-<rôle abrégé>`, pool `lab`, étiquettes `molecule` et `env-m04` (et **aucune** autre : le clone hérite de celles du template), VNet `vsandbox` (DHCP 10.10.99.100-199), clone de l'image dorée étiquetée `gold`, `debian13`, `current`.
- Le jeton `wb-ansible@pve!ansible` (rôle `WBAnsible`, E13) lit l'inventaire ; il devra aussi **cloner, configurer, démarrer, interroger l'agent et détruire** des VMs du pool `lab`. Proxmox VE 9 a scindé l'ancien `VM.Monitor` : l'adresse IP d'une VM, lue par l'agent, demande un privilège `VM.GuestAgent.*`.
- Flux : `adm01` (MGMT) joint `vsandbox` et l'API de `pve01` depuis le module 00 ; `runner01` aussi depuis M03-E15 (`vsandbox` TCP 22, `pve01` TCP 8006) : rien à ouvrir ici.
- Molecule écrit son propre `ansible.cfg` dans son dossier éphémère et **n'utilise pas** celui du projet.

**Travail demandé**
1. **Le jeton.** Liste les appels d'API qu'il faut pour cloner un template, poser étiquettes et cloud-init, démarrer, lire l'adresse par l'agent, arrêter et supprimer (aide : la section *permissions* de chaque chemin dans la documentation de l'API, <https://pve.proxmox.com/pve-docs/api-viewer/>). Étends le rôle `WBAnsible` en conséquence, sans privilège de trop ; note dans ton journal chaque privilège ajouté et l'appel qui l'exige. Vérifie avec `pveum user token permissions`.
2. **La structure.** Les scénarios vivent dans `molecule/<rôle>/` à la racine du projet. Ce qui est commun à tous (playbooks `create.yml`, `prepare.yml`, `destroy.yml`, inventaire du groupe `molecule`, séquence de test, ce qu'il faut d'`ansible.cfg`) ne doit être écrit **qu'une fois** : cherche dans la documentation où Molecule lit une configuration de base qu'il fusionne avec chaque `molecule.yml`, et comment un scénario désigne des playbooks qui ne sont pas dans son dossier.
3. **`create.yml`** (sur `localhost`) : trouve l'image dorée courante par ses étiquettes (exactement une, sinon échec explicite), clone-la sous le VMID de l'instance, remplace les étiquettes, injecte par cloud-init le compte `admin` et une clé SSH **générée pour le scénario**, démarre la VM, attends son adresse IPv4 dans `10.10.99.0/24` puis son port SSH. Les étapes suivantes de Molecule sont des processus `ansible-playbook` **distincts** : réfléchis à la façon dont l'adresse trouvée leur parvient.
4. **`destroy.yml`** : supprime les instances, réussit quand il n'y a rien à supprimer, et **refuse** (échec bruyant, rien de supprimé) de toucher une VM hors 2045-2049 ou qui n'est pas une instance du scénario. Teste ce garde-fou : crée à la main une VM 2047 nommée autrement, lance le destroy du scénario qui l'utiliserait, constate le refus, puis supprime-la.
5. **`prepare.yml`** : attends la fin de cloud-init (que signifie chacun des codes retour de `cloud-init status --wait` ?) et mets à jour le cache APT.
6. **Les scénarios `base` et `ssh_durci`** : `converge.yml` applique le rôle **sans** variable de test (si le rôle en exige, c'est son `meta/argument_specs.yml` qui doit le dire) ; `verify.yml` lit l'état comme le ferait un auditeur : fuseau, sources de chrony, configuration **effective** de journald et de sshd, mise à jour automatique active, et, pour `ssh_durci`, un refus d'authentification par mot de passe constaté **depuis le contrôleur**.
7. **Lance** `uv run molecule test -s base`, puis `-s ssh_durci`. Pendant un test, observe la VM dans Proxmox (étiquettes, notes, pool). Interromps un test par `Ctrl+C` pendant `converge` : que reste-t-il ? Comment le nettoies-tu ? Note dans ton journal le temps de chaque étape.
8. **Prouve que le test sert** : introduis volontairement un défaut d'idempotence dans `base` (une tâche `command` sans `changed_when`), relance, lis le rapport de l'étape `idempotence`, puis annule le défaut.
9. Fais en sorte qu'aucun fichier produit par un test n'apparaisse dans `git status`, puis fusionne par MR.

**Critères de réussite**
- [ ] `uv run molecule test -s base` et `uv run molecule test -s ssh_durci` réussissent de bout en bout depuis `adm01`, idempotence comprise.
- [ ] Pendant un test, l'instance porte exactement les étiquettes `env-m04` et `molecule`, est dans le pool `lab` sur `vsandbox` ; après le test, aucune VM 2045-2049 n'existe.
- [ ] Le destroy refuse de supprimer une VM 2045-2049 qui n'est pas une instance du scénario (constaté et noté).
- [ ] Le rôle `WBAnsible` contient les privilèges nécessaires et pas `VM.Console`, `Sys.Modify`, `Permissions.Modify` ni `VM.GuestAgent.Unrestricted`.
- [ ] Sur `main` : configuration de base Molecule, playbooks communs, deux scénarios ; `git status` propre après un test.

**Vérification** : `lab/bin/check 04 24`

<details><summary>Indice 1</summary>

Molecule cherche une configuration de base dans `.config/molecule/config.yml` à la racine du dépôt Git, et accepte dans `molecule.yml` des variables d'environnement comme `${MOLECULE_SCENARIO_DIRECTORY}` ou `${MOLECULE_PROJECT_DIRECTORY}`. Les chemins des playbooks (`ansible: playbooks:`) sont relatifs au dossier du scénario. Dans l'approche ansible-native, l'inventaire est un inventaire Ansible ordinaire, passé par `ansible: executor: args: ansible_playbook: [--inventory=…]`.
</details>

<details><summary>Indice 2</summary>

`community.proxmox.proxmox_kvm` clone (`clone`, `newid`, `full`, `pool`), met à jour (`update: true`, `tags`, `ciuser`, `sshkeys`, `ipconfig`), démarre et supprime. `community.proxmox.proxmox_vm_info` sait interroger l'agent (`network: true`) : lis son code ou sa documentation, il y a une condition supplémentaire pour que le réseau soit renvoyé. Une adresse découverte dans `create.yml` ne sert aux étapes suivantes que si elle est **écrite** dans une source d'inventaire (un fichier `host_vars`, par exemple).
</details>

<details><summary>Indice 3</summary>

Pour la clé d'hôte des instances, ni `StrictHostKeyChecking=no` ni le `~/.ssh/known_hosts` de ton compte : regarde `accept-new` et un `UserKnownHostsFile` propre au scénario, effacé au destroy. Et pour la clé de connexion, `ssh-keygen` dans le dossier éphémère du scénario rend le test indépendant de la machine qui le lance (ton poste ou `runner01`).
</details>

**Pour aller plus loin** : un scénario `pare_feu` (2047) qui vérifie que le filet anti-coupure de l'E17 restaure l'ancienne configuration quand la confirmation n'arrive pas ; un scénario Rocky 10 du rôle `base` (`mol_famille: rocky10`, CPU `x86-64-v3` déjà porté par l'image) pour mesurer ce que ton rôle suppose de Debian.

---

### M04-E25 — Mises à jour progressives : `serial` et tolérance aux échecs  `LAB` `★★`

> **Ticket DEV-553** — *De : Julien Petit* — *Copie : Nadia Roussel*
> Quand MédiAgenda tournera sur plusieurs frontaux, on ne pourra pas tous les mettre à jour en même temps : les patients prennent rendez-vous la nuit aussi. Avant que ça arrive, je voudrais qu'on sache faire une mise à jour « au fil de l'eau » : un nœud sorti de la répartition, mis à jour, vérifié, remis en service, puis le suivant. Et si un nœud casse, on s'arrête là, on ne casse pas les autres. Tu peux t'entraîner sur trois petites VMs ?

**Objectifs pédagogiques**
- Maîtriser l'exécution par lots : `serial` (nombre, pourcentage, liste), `max_fail_percentage`, `any_errors_fatal`, `order`, `throttle`, `run_once`.
- Construire un déploiement sans interruption : retrait du service, mise à jour, contrôle de santé, remise en service, arrêt au premier échec.
- Observer précisément ce qui arrive aux hôtes d'un lot quand l'un d'eux échoue.

**Prérequis** : M04-E08 (handlers), M04-E15 (gestion d'erreurs), M04-E23 (`delegate_to`, `run_once`), M04-E24 (jeton `wb-ansible` capable de cloner et détruire).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Flotte de démonstration : trois VMs `m04-web1`, `m04-web2`, `m04-web3`, VMID **2042-2044**, adresses fixes **10.10.99.42-44**/24 sur `vsandbox` (passerelle 10.10.99.1), étiquettes `env-m04` et `flotte`, clones de l'image dorée `current`.
- Fournis dans `~/DevOpsPrivateCloud/modules/04-ansible/ressources/M04-E25/` :
  - `flotte.yml` : crée la flotte (`-e etat=present`) ou la détruit (`-e etat=absent`) par l'API Proxmox, avec des garde-fous de VMID ;
  - `flotte-hosts.yml` : l'inventaire de la flotte (groupe `flotte`) ;
  - `sonde-flotte.sh` : simule une répartition de charge en interrogeant `http://<nœud>/sante` chaque seconde, et affiche combien de nœuds sont en service ;
  - `demo/medisphere-demo.conf.j2` et `demo/index.html.j2` : le site de démonstration (nginx), dont la page `/sante` répond `503` quand le fichier `/var/www/medisphere-demo/MAINTENANCE` existe, et `200 ok <version>` sinon.
- La flotte n'appartient pas au socle : son inventaire reste hors du projet, dans `~/m04/e25/`.

**Travail demandé**
1. Copie les ressources dans `~/m04/e25/`, crée la flotte depuis la racine du projet (`uv run ansible-playbook ~/m04/e25/flotte.yml -e etat=present`) et vérifie : `uv run ansible -i ~/m04/e25/flotte-hosts.yml flotte -m ansible.builtin.ping`.
2. Écris `playbooks/maj-progressive.yml` (dans le projet : c'est un patron réutilisable) qui déploie la version `-e version=<X>` du site sur le groupe `flotte` :
   - un premier lot d'**un** nœud (canari), puis le reste ;
   - pour chaque nœud : sortie de la répartition, attente que le contrôleur la constate, mise à jour (paquet nginx présent, configuration et page, rechargement validé), remise en service, contrôle de santé **depuis le contrôleur** qui exige la nouvelle version ;
   - arrêt immédiat dès qu'un nœud échoue, sans toucher aux lots suivants ; un nœud en échec **reste** hors service ;
   - une ligne de journal de déploiement (date, version, opérateur) écrite **une seule fois** par exécution dans `~/m04/e25/deploiements.log` ;
   - une variable de test `echec_sur` (liste de nœuds) qui provoque l'échec de la mise à jour sur ces nœuds.
3. Dans un second terminal, lance `~/m04/e25/sonde-flotte.sh`. Déploie la version `1.0` puis `2.0`. La sonde ne doit jamais afficher moins de deux nœuds en service.
4. **Expériences** (note pour chacune la commande, ce que tu prévois **avant** de lancer, ce que tu observes) :
   1. `version=2.1` avec `echec_sur=['m04-web1']` : que devient le reste de la flotte ?
   2. `version=2.2` avec `echec_sur=['m04-web2']` et ton découpage en lots : `m04-web3` a-t-il été mis à jour ? Pourquoi ?
   3. Même chose avec `serial: 1`, puis avec `any_errors_fatal: true` et des lots de deux.
   4. Que vaut, pour un lot de trois nœuds, `max_fail_percentage: 30` quand un nœud échoue ? et `max_fail_percentage: 34` ? Vérifie ta réponse.
   5. À quoi servent `order: shuffle` et `throttle: 1` ? Trouve dans ton playbook une tâche où `throttle` aurait du sens.
5. Remets toute la flotte en service sur une version saine. **Garde la flotte** : l'E26 s'en sert, et la détruit à la fin.

**Critères de réussite**
- [ ] `playbooks/maj-progressive.yml` est sur `main` et passe ansible-lint ; il utilise des lots, une tolérance d'échec nulle et un contrôle de santé fait depuis le contrôleur.
- [ ] Les trois nœuds répondent `200 ok <même version>` sur `/sante`.
- [ ] `~/m04/e25/deploiements.log` contient une ligne par exécution, pas une par nœud.
- [ ] Les réponses aux cinq expériences sont dans ton journal, avec ta prévision et l'observation.

**Vérification** : `lab/bin/check 04 25`

<details><summary>Indice 1</summary>

`serial` accepte une liste (`[1, 2]`, `[1, "50%"]`) : chaque élément est la taille d'un lot, le dernier se répète. `max_fail_percentage` s'évalue **lot par lot**, et l'échec doit **dépasser** la valeur. Les `pre_tasks`, `tasks` et `post_tasks` d'un play s'exécutent lot par lot.
</details>

<details><summary>Indice 2</summary>

Un contrôle de santé « depuis le contrôleur » est une tâche `ansible.builtin.uri` déléguée à `localhost`, avec `until`/`retries`. Une tâche qui ne doit tourner qu'une fois pour toute l'exécution (et pas une fois par lot) se combine mal avec `serial` : regarde ce que fait `run_once` dans un play à plusieurs lots, et pense à un play dédié.
</details>

**Pour aller plus loin** : remplace la sonde par un vrai répartiteur (HAProxy, module 07) et pilote la sortie de la répartition par son socket d'administration avec `delegate_to`.

---

### M04-E26 — Performances d'Ansible  `LAB` `★★`

> **Ticket PLAT-555** — *De : Karim Benali*
> `site.yml` met déjà plusieurs minutes sur cinq machines. On en aura une quarantaine à la fin du bloc B. Avant d'acheter du matériel ou de changer d'outil, mesure : où passe le temps, ce que chaque réglage apporte vraiment, et ce qu'il coûte. Je veux des chiffres, pas des impressions.

**Objectifs pédagogiques**
- Mesurer une exécution Ansible (callbacks `ansible.posix.profile_tasks`, `profile_roles`, `timer`) et identifier où passe le temps.
- Comprendre et mesurer l'effet de `forks`, du *pipelining*, du multiplexage SSH (`ControlPersist`), de la collecte de faits (`gather_subset`, `gathering = smart`, cache de faits), de la stratégie `free` et de `async`.
- Connaître le coût de chaque optimisation (faits périmés, ordre d'exécution, lisibilité, sécurité).

**Prérequis** : M04-E19, M04-E25 (flotte de démonstration active).
**Durée indicative** : 2 h.

**Contexte technique**
- Cible de mesure : le socle (5 hôtes) et la flotte (3 hôtes), soit 8 hôtes. Les mesures se font en lecture seule (`--check`) ou avec des tâches sans effet, jamais en appliquant sur le socle.
- Rappel : `ansible.cfg` (E02) a déjà `forks = 10` et `pipelining = True` (section `[connection]`). `ansible-config dump --only-changed -t all` montre ce qui s'écarte des défauts.
- Callbacks utiles : collection `ansible.posix` (installée en E02). Un callback s'active par `callbacks_enabled` (ou `ANSIBLE_CALLBACKS_ENABLED` pour une exécution).
- Depuis ansible-core 2.19, `gather_subset` ne se règle plus dans `ansible.cfg` : c'est un mot-clé de play (ou un paramètre de `ansible.builtin.setup`).

**Travail demandé**
1. Écris `playbooks/mesure-perf.yml` : sur le socle et la flotte (deux inventaires : `-i inventories/lab/hosts.yml -i ~/m04/e25/flotte-hosts.yml`), une collecte de faits puis une dizaine de tâches courtes **sans effet** (lecture de fichiers, `stat`, commandes en lecture, `package_facts`…). Chaque exécution doit donner `changed=0`.
2. Écris `outils/mesurer-perf.sh` qui lance ce playbook N fois pour une configuration donnée (variables d'environnement `ANSIBLE_…`) et affiche la médiane du temps écoulé.
3. Mesure, en ne changeant **qu'un paramètre à la fois** par rapport à la configuration du projet : `forks` 1, 5, 10, 20 ; *pipelining* désactivé ; multiplexage SSH désactivé ; collecte de faits complète, réduite (`gather_subset`), désactivée, et en cache (`jsonfile`, `gathering = smart`, deux exécutions de suite) ; stratégie `free`. Active `ansible.posix.profile_tasks` sur une exécution : quelles sont les trois tâches les plus lentes ?
4. Explique pour chaque réglage le mécanisme (combien de connexions SSH, combien d'allers-retours, quels fichiers copiés) et son coût. Mesure en particulier ce que deviennent les faits mis en cache quand une adresse change (indice : modifie le `/etc/motd` d'un nœud de la flotte, il apparaît dans un fait ?) et décide du délai d'expiration.
5. Fixe dans `ansible.cfg` la configuration retenue (et seulement ce qui est justifié par une mesure), avec le cache de faits dans `~/.cache/ansible/faits` (dossier 700). Documente les mesures dans `docs/performances.md` du projet : tableau, méthode, conclusion, et ce qu'il ne faut **pas** activer en CI.
6. Détruis la flotte : `uv run ansible-playbook ~/m04/e25/flotte.yml -e etat=absent`.

**Critères de réussite**
- [ ] `docs/performances.md` est sur `main` avec un tableau de mesures (au moins `forks`, *pipelining*, multiplexage, faits) et une conclusion chiffrée.
- [ ] `ansible.cfg` sur `main` active le cache de faits `jsonfile` avec une expiration explicite, `gathering = smart` et au moins un callback de mesure.
- [ ] Le cache de faits sur `adm01` est dans `~/.cache/ansible/faits`, en 700, et contient les hôtes du socle.
- [ ] La flotte (VMID 2042-2044) est détruite.

**Vérification** : `lab/bin/check 04 26`

<details><summary>Indice 1</summary>

Avec `ANSIBLE_SSH_ARGS=""`, Ansible ne passe plus ses options par défaut (`-C -o ControlMaster=auto -o ControlPersist=60s`). Mais ton `~/.ssh/config` de `adm01` (M00-E15) a peut-être son propre `ControlMaster` : pour mesurer vraiment l'absence de multiplexage, regarde aussi `-o ControlMaster=no` et `ControlPath=none`.
</details>

<details><summary>Indice 2</summary>

`gathering = smart` ne collecte les faits que s'ils ne sont pas déjà dans le cache. Avec le cache par défaut (`memory`), il ne survit pas à l'exécution : la seconde exécution n'en profite pas. Le plugin `jsonfile` écrit un fichier par hôte ; sa durée de vie se règle par `fact_caching_timeout`.
</details>

**Pour aller plus loin** : Mitogen promet de grands gains en remplaçant le transport ; vérifie sa matrice de compatibilité avec ansible-core 2.21 avant de l'envisager, et explique pourquoi une équipe hésiterait à en dépendre.

---

### M04-E27 — Chaîne CI Ansible : lint, Molecule, `--check` en MR, application contrôlée  `LAB` `★★★`

> **Ticket PLAT-558** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent*
> Plus aucun changement du socle ne part d'un poste. Le chemin normal : une MR, des tests automatiques (lint, Molecule pour les rôles touchés), un aperçu exact de ce qui changera sur les machines, relu par un pair, puis une application déclenchée à la main depuis `main`, tracée, une seule à la fois. Sophie a deux conditions : la forge n'a la clé du socle que pour ça, et une branche quelconque ne doit pas pouvoir s'en servir.

**Objectifs pédagogiques**
- Concevoir un pipeline d'infrastructure : contrôles statiques, tests sur VMs jetables limités aux rôles modifiés, aperçu `--check --diff` en MR, application manuelle sur `main` avec environnement et verrou.
- Donner à un exécutant CI un accès au socle minimal et révocable : clé dédiée restreinte par `from=`, flux réseau ciblés, clés d'hôte vérifiées.
- Protéger les secrets dans GitLab CE : variables protégées et masquées, variables de type fichier, accès des pipelines de MR aux ressources protégées, portée d'environnement ; savoir ce qui, dans CE, n'existe pas (environnements protégés) et comment s'en passer.
- Rendre l'application vérifiable : journaux en artefacts, rapport JUnit, contrôle de convergence après application.

**Prérequis** : M01-E24 (gabarits CI), M03-E15 (flux de `runner01`), M04-E12 (Vault), M04-E17 (rôle `pare_feu`), M04-E20 (job `ansible-lint`), M04-E24 (Molecule).
**Durée indicative** : 5 h.

**Contexte technique**
- `runner01` (10.10.20.15, VLAN INFRA, exécuteur `shell`, utilisateur `gitlab-runner`, `uv` dans `/usr/local/bin`) : il joint déjà `dns01`, `git01` et lui-même (même VLAN), `vsandbox` en SSH et l'API de `pve01` (M03-E15). Il ne joint **pas** `adm01` (MGMT) ni le SSH de `gw01` (la chaîne `input` de `gw01` n'accepte SSH que depuis MGMT et le VPN).
- Identité de la CI sur le socle : une clé ed25519 dédiée, commentaire **`ansible-ci`**, autorisée pour `admin` sur toutes les VMs du socle par le rôle `base`, restreinte à la source 10.10.20.15. Sa partie privée n'existe que dans GitLab.
- `inventories/lab/host_vars/adm01/main.yml` (E03) dit `ansible_connection: local` : vrai quand Ansible tourne **sur** `adm01`, dangereux ailleurs.
- GitLab CE 19.4 : les **environnements protégés** et la protection des jobs manuels par environnement sont réservés aux éditions payantes. Disponibles dans CE : branches protégées (un job manuel d'une branche protégée ne peut être lancé que par qui peut fusionner dans cette branche), variables protégées, masquées, cachées, de type fichier, à **portée d'environnement** au niveau du projet, `resource_group`, et (GitLab ≥ 18.1) l'option *Allow merge request pipelines to access protected variables and runners* : un pipeline de MR reçoit alors les variables protégées si la branche source **et** la branche cible sont protégées (même projet) et que celui qui déclenche le pipeline peut pousser ou fusionner sur la branche cible.
- Variables CI à créer (protégées) : `ANSIBLE_CI_SSH_KEY` (fichier : clé privée `ansible-ci`), `VAULT_PASS_LAB` (fichier : mot de passe Vault, E12), `PROXMOX_URL`, `PROXMOX_USER`, `PROXMOX_TOKEN_ID` et `PROXMOX_TOKEN_SECRET` (masquée et cachée), pour Molecule.

> ⚠️ **Attention** : tu ouvres le SSH de `gw01` et de `adm01` à une machine qui exécute du code venu de la forge. La première modification des flux de `gw01` se fait **depuis `adm01`**, par le rôle `pare_feu` et son filet anti-coupure, session ouverte. Ne place la clé `ansible-ci` sur les hôtes qu'**après** avoir créé les variables protégées et vérifié qu'aucune branche non protégée ne les reçoit.

**Travail demandé**
1. **Identité.** Génère la clé `ansible-ci` sur `adm01` (hors de tout dépôt), ajoute sa partie publique, restreinte par `from=`, aux clés autorisées du rôle `base`. Crée les variables CI. Règle `adm01` pour qu'Ansible s'y connecte en SSH quand il ne tourne pas sur `adm01` lui-même.
2. **Flux.** Ajoute à la description des flux du rôle `pare_feu` (E17) les deux flux nécessaires (`runner01` → `gw01` SSH, `runner01` → `adm01` SSH), applique depuis `adm01`, et reporte-les dans `docs/socle/matrice-flux.md`. Teste chaque flux depuis `runner01`.
3. **Clés d'hôte.** La CI ne désactive pas la vérification des clés d'hôte. Fournis à `runner01` les clés d'hôte du socle **vérifiées** (pas un `ssh-keyscan` aveugle) : explique comment tu prouves qu'elles sont les bonnes.
4. **Le pipeline** (`.gitlab-ci.yml`, en plus des gabarits communs) :
   - `ansible-lint` sur toute MR et sur `main` (rapport de qualité de code dans la MR) ;
   - un job Molecule **par rôle testé**, lancé seulement quand le rôle, son scénario ou l'infrastructure Molecule changent, jamais deux fois le même scénario en même temps, instances détruites même si le job échoue ou est annulé ;
   - `check-socle` : `site.yml --check --diff` sur les MR et sur `main` ; journal complet en artefact, échec si un hôte est injoignable ou en erreur ;
   - `appliquer` : sur `main` seulement, manuel, environnement `lab/socle` (palier de déploiement `production`), un seul à la fois **avec la détection de dérive** (E29) ; après l'application, une seconde passe en `--check` doit montrer **zéro** changement, sinon le job échoue ;
   - un job planifié de ménage des instances Molecule orphelines ;
   - aucune variable protégée hors des branches protégées : une MR issue d'une branche non protégée ne lance ni Molecule ni `check-socle`, et le pipeline le dit clairement au lieu de passer en silence.
5. **Branches.** Protège le motif `conf/*` (le flux de travail de l'équipe pour les changements du socle) et active l'option d'accès des pipelines de MR aux variables protégées. Note dans ton journal qui peut désormais, concrètement, lire la clé `ansible-ci`.
6. **La preuve.** Une MR depuis `conf/…` qui change une valeur anodine du rôle `base` (le texte du motd, par exemple) : Molecule `base` tourne, `check-socle` montre le *diff* attendu sur les cinq hôtes ; fusionne, lance `appliquer`, constate la seconde passe à zéro. Une MR depuis une branche **non** protégée : constate ce qui se passe. Lance deux `appliquer` presque en même temps : que montre GitLab ?
7. Mets à jour `docs/socle/registre-secrets.md` (clé `ansible-ci`, variables CI) et rédige dans la MR la liste de ce que la clé `ansible-ci` permet à qui la possède.

**Critères de réussite**
- [ ] Sur `main`, `.gitlab-ci.yml` contient les jobs `ansible-lint`, Molecule (au moins `base` et `ssh_durci`), `check-socle`, `appliquer`, le ménage planifié ; `appliquer` est manuel, sur `main`, avec l'environnement `lab/socle` et un `resource_group`.
- [ ] Un déploiement réussi existe pour l'environnement `lab/socle` ; un pipeline de MR a exécuté `check-socle` avec succès.
- [ ] Les variables `ANSIBLE_CI_SSH_KEY` et `VAULT_PASS_LAB` sont protégées et de type fichier, `PROXMOX_TOKEN_SECRET` protégée et masquée ; `main` et `conf/*` sont protégées.
- [ ] `runner01` joint en SSH `gw01` et `adm01` ; la clé `ansible-ci` est autorisée sur les cinq hôtes du socle avec `from=` ; les clés d'hôte du socle sont connues de `runner01`.
- [ ] Matrice des flux et registre des secrets à jour.

**Vérification** : `lab/bin/check 04 27`

<details><summary>Indice 1</summary>

Les variables protégées absentes ne font pas échouer un job : elles sont vides. Une règle `rules: - if: $PROXMOX_TOKEN_SECRET` teste leur **présence**. `rules:changes` compare, dans un pipeline de MR, avec la branche cible ; ses chemins acceptent des jokers (`roles/base/**/*`). `!reference [job, before_script]` réutilise des lignes d'un autre job.
</details>

<details><summary>Indice 2</summary>

Une variable de type fichier arrive dans le job comme un **chemin** vers un fichier temporaire. Une clé privée collée sans saut de ligne final est refusée par `ssh` (« invalid format ») ; une clé lisible par d'autres aussi. `ANSIBLE_PRIVATE_KEY_FILE` et `ANSIBLE_VAULT_IDENTITY_LIST` remplacent pour un job les valeurs de `ansible.cfg`. Les commandes de `after_script` tournent dans un **nouveau** shell, y compris quand le job est annulé.
</details>

<details><summary>Indice 3</summary>

Pour `adm01`, une valeur de `ansible_connection` peut être une expression Jinja évaluée sur le contrôleur. Pour les clés d'hôte, `adm01` les connaît déjà (tu t'y es connecté depuis le module 00) : `ssh-keygen -F <adresse>` et `ssh-keygen -lf` permettent de comparer ce qu'annonce un hôte avec ce que tu as déjà accepté.
</details>

**Pour aller plus loin** : remplace le `--check` des MR par un pipeline enfant par hôte touché (`trigger:include` généré), pour que l'aperçu d'une MR qui ne change que `dns01` ne se connecte pas à `gw01`.

---

### M04-E28 — Semaphore UI : exécuter Ansible avec traçabilité  `LAB` `★★★`

> **Ticket PLAT-561** — *De : Nadia Roussel* — *Copie : Sophie Laurent*
> À l'astreinte, je n'ouvrirai ni un terminal ni une MR à 3 h du matin pour relancer la configuration de `dns01`. Je veux une interface : je choisis une tâche préparée par vous, je la lance, je vois la sortie, et tout est historisé avec mon nom. Sophie veut que l'outil soit derrière TLS, que les secrets n'y soient lisibles par personne, et que chacun n'y ait que le rôle qu'il lui faut. Pas AWX : InfoGér l'avait installé, personne n'a su le mettre à jour.

**Objectifs pédagogiques**
- Installer un orchestrateur Ansible auto-hébergé **par Ansible** (rôle `semaphore`) : paquet officiel vérifié, base PostgreSQL, TLS, service systemd durci, secrets en Vault.
- Configurer un projet Semaphore : magasin de clés, dépôt en lecture seule, inventaire, groupe de variables, modèles de tâches, équipe et rôles.
- Lire le code d'un outil pour savoir ce qu'il fait réellement de tes clés d'hôte, de tes secrets et de tes dépôts, et corriger ses défauts de configuration.
- Comparer cet exécutant avec la CI de l'E27.

**Prérequis** : M01-E04 (CA provisoire), M04-E12 (Vault), M04-E27 (clé dédiée, flux, clés d'hôte).
**Durée indicative** : 4 h.

**Contexte technique**
- VM `sem01` : VMID **2041**, VNet `vinfra`, **10.10.20.41**/24 (passerelle 10.10.20.1), 2 vCPU, 2 Go, disque 20 Go, clone complet de l'image dorée `current`, pool `lab`, étiquettes `env-m04` et `role-semaphore`. Nom DNS `sem01.par1.medisphere.internal` (dnsmasq de `dns01`). Dans l'inventaire statique, groupe `role_semaphore`.
- Semaphore UI **2.19** : paquet `.deb` de la page des versions du projet (<https://github.com/semaphoreui/semaphore/releases>), à vérifier par le fichier `semaphore_<version>_checksums.txt`. Le paquet ne contient **que** le binaire (`/usr/bin/semaphore`) : utilisateur, configuration et service sont à ta charge. Documentation : <https://semaphoreui.com/docs/>. BoltDB n'est plus accepté depuis la 2.19 (SQLite par défaut, MySQL ou PostgreSQL au choix).
- Exigences : base **PostgreSQL** locale (paquet Debian), TLS **intégré** à Semaphore sur le port 443 avec un certificat de la CA provisoire (SAN `sem01.par1.medisphere.internal`, `sem01`, `IP:10.10.20.41`), redirection HTTP 80 → HTTPS, `ansible-core` installé depuis Debian sur `sem01`.
- Accès au socle : une clé dédiée, commentaire **`ansible-semaphore`**, déployée par le rôle `base`, restreinte à la source 10.10.20.41. Mêmes flux que `runner01` en E27, pour 10.10.20.41.
- Lecture du dépôt `plateforme/ansible` : accès **en lecture seule**, à toi de choisir la méthode après avoir lu comment Semaphore lance `git`.

> ⚠️ **Attention** : `sem01` détiendra une clé qui ouvre une session `root` sur tout le socle. Toute la configuration de Semaphore qui contient un secret (`config.json`, base) doit être illisible pour les autres comptes de la VM ; la clé `access_key_encryption` qui chiffre le magasin de clés est un secret de premier rang (perdue : tout le magasin est perdu ; volée avec la base : tout est lisible).

**Travail demandé**
1. **La VM.** Crée `sem01` (clone complet, réseau, étiquettes), déclare-la dans le DNS, l'inventaire statique et `~/.ssh/config`, et applique-lui les rôles `base` et `ssh_durci`.
2. **Le certificat.** Émets le certificat de `sem01` avec la CA provisoire (`~/pki-provisoire/`, comme pour `git01` en M01-E04). La clé privée rejoint Vault ; le certificat (public) peut être en clair dans le dépôt.
3. **Le rôle `semaphore`** (dans `roles/`, appliqué par `playbooks/sem01.yml`), idempotent, testé à la main par deux passages successifs :
   - paquet officiel téléchargé avec vérification de la somme, version en variable ;
   - PostgreSQL local, base et compte dédiés, mot de passe en Vault, sans jamais l'exposer dans la ligne de commande d'un processus ni dans un *diff* ;
   - compte système `semaphore`, configuration `/etc/semaphore/config.json` lisible par ce seul compte (et root), clés de chiffrement (`cookie_hash`, `cookie_encryption`, `access_key_encryption`) générées une fois (`head -c32 /dev/urandom | base64`) et rangées en Vault ;
   - TLS intégré sur 443, redirection depuis 80, `web_host` à l'URL publique, fuseau des planifications `Europe/Paris` ;
   - service systemd qui tourne sous `semaphore` (pas root) avec juste la capacité d'écouter sur 443 ;
   - compte administrateur initial créé une seule fois.
4. **Lis le code** de Semaphore 2.19 (fichiers `db_lib/AnsiblePlaybook.go` et `pkg/ssh/agent.go`, étiquette `v2.19.16`) et réponds dans ton journal : quelle variable d'environnement Semaphore impose-t-il à `ansible-playbook` au sujet des clés d'hôte ? Avec quelles options lance-t-il `git` sur un dépôt SSH ? Quelles conséquences pour la sécurité du socle, et comment les neutralises-tu (configuration du serveur, méthode d'accès au dépôt, clés d'hôte connues de `sem01`) ?
5. **Le projet « Socle MédiSphère »** dans l'interface : clés (accès au dépôt, `ansible-semaphore`, mot de passe Vault), dépôt `plateforme/ansible` sur `main`, inventaire de type fichier `inventories/lab/hosts.yml`, groupe de variables, deux modèles : « Socle — vérifier » (`--check --diff`) et « Socle — appliquer ». Fais-les tourner. Si une tâche échoue parce que le mot de passe Vault est introuvable, lis le message, relis `ansible.cfg`, et trouve comment le contourner **sans** modifier le dépôt.
6. **Équipe.** Crée des comptes locaux `nadia.roussel` (lancer des tâches seulement) et `karim.benali` (gérer le projet), plus un compte technique `workbook-checks` (lecture seule) avec un jeton d'API de 90 jours rangé dans `~/.config/workbook/semaphore-checks.token` (600). Active le second facteur (TOTP) pour l'administrateur.
7. **Comparaison.** Dans un tableau de ton journal : qui peut lancer une application du socle par la CI, par Semaphore ; où sont les journaux et combien de temps ; qui voit les secrets ; ce qui empêche deux applications simultanées par les **deux** chemins. Cette dernière ligne est un problème ouvert : l'E31 le tranchera.
8. Mets à jour la matrice des flux, le registre des secrets (dont l'emplacement de la clé `access_key_encryption` et la procédure de sauvegarde de `sem01` : `semaphore projects export`, `pg_dump`) et l'inventaire du socle.

**Critères de réussite**
- [ ] `https://sem01.par1.medisphere.internal/api/ping` répond `pong` depuis `adm01` **sans** désactiver la vérification TLS ; le port 80 redirige vers HTTPS.
- [ ] Le service `semaphore` est actif sous l'utilisateur `semaphore`, avec PostgreSQL ; `/etc/semaphore/config.json` n'est lisible ni par les autres comptes ni par le groupe « autres ».
- [ ] Les tâches lancées par Semaphore vérifient les clés d'hôte.
- [ ] Le projet contient un dépôt `plateforme/ansible` accessible en lecture seule, un inventaire de type fichier, et au moins une tâche réussie de chacun des deux modèles.
- [ ] `nadia.roussel` ne peut que lancer des tâches ; le jeton de `workbook-checks` fonctionne.
- [ ] `sem01` résout dans le DNS ; flux, registre des secrets et inventaire à jour.

**Vérification** : `lab/bin/check 04 28` (renseigne `WB_SEMAPHORE_URL` et `WB_SEMAPHORE_TOKEN_FILE` dans `lab/lab.env` si tu t'écartes des valeurs par défaut).

<details><summary>Indice 1</summary>

`semaphore users add` et `semaphore users token create` existent en ligne de commande (`semaphore users --help`) et prennent `--config`. `semaphore users list` permet de savoir si un compte existe déjà. Le service peut écouter sur 443 sans être root avec `AmbientCapabilities=CAP_NET_BIND_SERVICE`. La section `tls` de `config.json` a les clés `enabled`, `cert_file`, `key_file`, `http_redirect_port`.
</details>

<details><summary>Indice 2</summary>

Dans Go, quand une variable d'environnement est présente deux fois, la **dernière** l'emporte. Regarde l'ordre dans lequel Semaphore assemble l'environnement de `ansible-playbook`, et l'option `env_vars` de `config.json`. Pour Git, une option passée par `-o` sur la ligne de commande de `ssh` ne peut pas être annulée par un fichier de configuration.
</details>

<details><summary>Indice 3</summary>

Quand un modèle a un mot de passe Vault, Semaphore ajoute `--vault-id=<nom>@prompt` et répond lui-même à l'invite. Mais `ansible.cfg` du dépôt contient déjà une identité Vault qui pointe vers un fichier de `adm01`… Une variable d'environnement `ANSIBLE_VAULT_IDENTITY_LIST` définie dans le groupe de variables remplace la valeur de `ansible.cfg`.
</details>

**Pour aller plus loin** : authentification OIDC (Keycloak, module 24) à la place des comptes locaux ; notifications des échecs ; sauvegarde planifiée de la base vers PBS.

---

### M04-E29 — Détecter la dérive de configuration  `LIBRE` `★★★`

> **Ticket SEC-564** — *De : Sophie Laurent*
> Pour l'audit, « le socle est configuré par Ansible » ne suffit pas : l'auditeur me demandera comment je sais qu'il l'est **encore**. Quelqu'un qui corrige un fichier à la main à 3 h du matin, un paquet qui réécrit sa configuration, un rôle qui n'a pas été réappliqué depuis un mois… Je veux une vérification automatique, chaque jour, une preuve conservée, et une alerte qu'on ne peut pas rater quand ça diverge.

**Objectifs pédagogiques**
- Définir la dérive (écart entre l'état réel et l'état décrit dans `main`) et ses limites de détection par `--check`.
- Concevoir une détection planifiée : exécution, rapport exploitable, conservation des preuves, alerte, distinction « dérive » / « erreur d'exécution ».
- Fiabiliser le mode `--check` d'un rôle (tâches qui ne savent pas simuler, dépendances entre tâches).

**Prérequis** : M04-E27.
**Durée indicative** : 3 h.

**Contraintes**
- Exécution quotidienne par un **pipeline planifié** de `plateforme/ansible` sur `main`, en heures creuses (fuseau Europe/Paris), sans écrire quoi que ce soit sur les hôtes.
- Résultat sans ambiguïté : « conforme », « dérive » (au moins une tâche changerait quelque chose) ou « erreur » (hôte injoignable, tâche en échec) — trois issues distinctes, que l'on peut aussi obtenir à la main sur `adm01` et dans Semaphore avec le même outil.
- Preuve : journal complet et rapport JUnit (un changement = un cas en échec) conservés **au moins 90 jours**.
- Alerte : en cas de dérive ou d'erreur, un ticket GitLab étiqueté `derive` dans `plateforme/ansible` (un seul ticket ouvert à la fois : les détections suivantes y ajoutent un commentaire), avec le lien vers le rapport. Le jeton qui crée le ticket a le minimum de droits.
- Aucun secret dans le rapport, le ticket ou le journal du job.
- La détection ne doit pas lire des faits périmés, ni tourner pendant une application (E27).
- Démontre le fonctionnement complet : une dérive provoquée à la main sur un hôte (motd modifié, option sshd ajoutée hors du rôle), détectée, signalée, puis corrigée **par une application** (pas en défaisant à la main) ; puis une journée « conforme ».
- Si un rôle produit de faux positifs en `--check` (changement annoncé à chaque fois, ou tâche en échec en simulation), corrige le rôle, pas la détection.

**Critères de réussite**
- [ ] Un pipeline planifié actif sur `main` lance la détection chaque jour ; un pipeline planifié a déjà produit un rapport (artefact) conservé 90 jours.
- [ ] Un ticket étiqueté `derive` a été créé par une détection, puis fermé après correction.
- [ ] La détection donne « conforme » sur le socle actuel (`changed=0` partout).
- [ ] Le même outil se lance à la main sur `adm01` et renvoie un code distinct pour chacune des trois issues.

**Vérification** : `lab/bin/check 04 29`

<details><summary>Indice 1</summary>

Le *PLAY RECAP* contient pour chaque hôte `changed=`, `unreachable=` et `failed=` : c'est la donnée la plus stable pour décider. Le callback `ansible.builtin.junit` sait considérer une tâche « changed » comme un échec (`JUNIT_FAIL_ON_CHANGE`).
</details>

<details><summary>Indice 2</summary>

Un jeton d'accès de projet avec le rôle *Reporter* et la portée `api` suffit pour créer un ticket et le commenter. Il n'apparaît pas dans un pipeline de MR s'il est protégé. Les tâches `command`/`shell` sont ignorées en `--check` sauf `check_mode: false` : utile pour une lecture, dangereux pour une écriture.
</details>

**Pour aller plus loin** : publie le nombre d'hôtes en dérive comme métrique (fichier texte pour le collecteur `textfile` de node_exporter, module 21).

---

### M04-E30 — Vault en production : séparation et rotation  `LAB` `★★`

> **Ticket SEC-567** — *De : Sophie Laurent*
> Trois constats après ma revue. Un : le même mot de passe Vault ouvre tous les secrets, du motd au magasin de clés de Semaphore. Deux : il est maintenant à quatre endroits (ton poste, GitLab, Semaphore, ta mémoire) et personne n'a jamais essayé de le changer. Trois : j'ai trouvé dans le journal d'un job `check-socle` une ligne qui ressemblait beaucoup à un secret. Je veux : des secrets séparés selon leur gravité, une rotation testée et écrite, et une garantie automatique qu'aucun secret ne sort dans un journal.

**Objectifs pédagogiques**
- Séparer les secrets par identité Vault (`--vault-id`, `vault_id_match`) et faire correspondre chaque identité à ses consommateurs.
- Distribuer les mots de passe Vault par un script client unique (`*-client`) qui s'adapte au poste, à la CI et à Semaphore.
- Pratiquer une rotation : changement du mot de passe Vault (`rekey`) **et** changement des secrets eux-mêmes ; comprendre ce que l'historique Git implique.
- Empêcher les fuites de secrets par `--diff`, `-v` ou les messages d'erreur, et le détecter automatiquement.

**Prérequis** : M04-E12, M04-E27, M04-E28.
**Durée indicative** : 2 h 30.

**Contexte technique**
- Deux identités Vault : **`lab`** (secrets d'exploitation du socle) et **`critique`** (secrets dont la fuite compromet la plateforme entière ; au minimum les trois clés de chiffrement de Semaphore, la clé TLS de `sem01` et le jeton d'authentification `glrt-…` de `runner01` : qui le détient peut se faire passer pour le runner et recevoir les jobs de `main`, variables protégées comprises). Mots de passe : `~/.config/workbook/ansible-vault.pass` (`lab`, existant) et `~/.config/workbook/ansible-vault-critique.pass` (600).
- Script client : `outils/vault-pass-client.sh` dans le projet. Ansible passe `--vault-id <identité>` à un script dont le nom se termine par `-client` (avec ou sans extension) et lit le mot de passe sur sa sortie standard. Un chemin relatif dans `vault_identity_list` est résolu depuis le **dossier courant**.
- Variables CI : `VAULT_PASS_LAB` (E27) et `VAULT_PASS_CRITIQUE` (fichier, protégée, portée d'environnement `lab/socle`). Semaphore : secrets de type variable d'environnement du groupe de variables.
- Runbook à écrire : **RB-041** « Rotation des secrets Ansible Vault », dans `docs/socle/runbooks/` de `plateforme/medisphere`.

**Travail demandé**
1. **Inventaire.** Pour chaque variable `vault_*` du projet : hôte consommateur, gravité, qui détient aujourd'hui de quoi la lire, fréquence de rotation souhaitée. Classe-les en `lab` / `critique` et inscris le résultat dans le registre des secrets.
2. **Séparation.** Ré-chiffre les secrets `critique` sous leur propre identité (fichier `vault.yml` dédié, en-tête `$ANSIBLE_VAULT;1.2;AES256;critique`), configure `vault_identity_list` (deux identités, script client) et `vault_id_match`. Décide qui reçoit `critique` : la CI (seulement les jobs de l'environnement `lab/socle`), Semaphore, ton poste. Puis observe : que fait Ansible quand le mot de passe d'une identité est introuvable mais qu'aucune variable de cette identité n'est utilisée ? Et quand une tâche en utilise une ? Fais en sorte qu'un job `check-socle` de MR réussisse **sans** l'identité `critique`, même si un rôle de `site.yml` utilise un secret `critique` (le jeton d'enregistrement du runner, par exemple).
3. **Le script client** : un seul script pour les trois contextes, qui cherche le mot de passe de l'identité demandée dans, au choix, une variable contenant un chemin (CI), une variable contenant la valeur (Semaphore), puis le fichier de `~/.config/workbook/` (poste), refuse un fichier lisible par d'autres, et échoue clairement (code non nul, message sur la sortie d'erreur, jamais le mot de passe) si rien n'est trouvé. Bascule la CI et Semaphore dessus et retire les contournements de l'E27 et de l'E28.
4. **Fuites.** Reproduis la fuite signalée par Sophie : trouve une tâche de tes rôles dont `--diff` ou un message d'erreur affiche un secret. Corrige (`no_log`, `diff: false`, ou les deux, selon la tâche). Puis écris `outils/secrets-dans-journal.py` qui déchiffre les fichiers Vault du projet et cherche leurs valeurs dans un journal donné (en n'affichant que les **noms** des variables trouvées), et fais en sorte que `check-socle` et `appliquer` n'affichent leur journal qu'après ce contrôle.
5. **Rotation.** Change le mot de passe de l'identité `lab` (`ansible-vault rekey`), distribue-le aux trois consommateurs, vérifie chacun ; puis change réellement un secret `critique` (par exemple le mot de passe PostgreSQL de Semaphore) et applique. Rédige RB-041 à partir de ce que tu viens de faire (préparation, ordre des étapes, vérification, retour arrière, que faire de l'historique Git).

**Critères de réussite**
- [ ] Sur `main`, au moins un fichier chiffré sous l'identité `lab` et un sous `critique` ; `ansible.cfg` déclare les deux identités via `outils/vault-pass-client.sh`, avec `vault_id_match`.
- [ ] `~/.config/workbook/ansible-vault-critique.pass` existe en 600 et diffère du mot de passe `lab`.
- [ ] `VAULT_PASS_CRITIQUE` est protégée, de type fichier, de portée `lab/socle` ; un pipeline de MR réussit sans elle.
- [ ] Le script client échoue proprement sans mot de passe disponible ; `secrets-dans-journal.py` détecte un secret injecté dans un journal de test.
- [ ] RB-041 est fusionné dans `plateforme/medisphere`, le registre des secrets indique l'identité de chaque secret et sa dernière rotation.

**Vérification** : `lab/bin/check 04 30`

<details><summary>Indice 1</summary>

`ansible-vault rekey` ne s'applique qu'aux **fichiers** entièrement chiffrés : une valeur chiffrée en ligne (`!vault |`) doit être déchiffrée puis rechiffrée. `ansible-vault encrypt --vault-id critique@…` et `--encrypt-vault-id` choisissent l'identité utilisée pour chiffrer. Avec `vault_id_match = True`, Ansible n'essaie que le mot de passe de l'identité inscrite dans l'en-tête.
</details>

<details><summary>Indice 2</summary>

Une valeur chiffrée n'est déchiffrée qu'au moment où elle est **utilisée** (une tâche sautée par son `when` ne développe pas ses arguments). Si le `check-socle` de MR ne doit pas avoir `critique`, les tâches qui consomment ces variables doivent pouvoir être sautées : une étiquette commune et `--skip-tags` font l'affaire, à condition que le rôle soit écrit pour (pas de variable `critique` dans un `when` ou un nom de tâche d'une tâche non étiquetée).
</details>

**Pour aller plus loin** : remplacer le script client par une lecture dans OpenBao (module 25) avec un jeton par consommateur : la rotation d'un consommateur ne touche plus les autres.

---

### M04-E31 — ADR : comment exécuter Ansible chez MédiSphère  `RED` `★★`

> **Ticket PLAT-570** — *De : Claire Morel*
> Aujourd'hui, le socle peut être modifié depuis ton poste, par la CI, et par Semaphore. Trois chemins, trois journaux, et rien qui empêche deux applications simultanées. Il faut trancher et l'écrire : par où passe un changement de configuration chez nous, qui peut le déclencher, comment on le trace, et ce qu'on fait des autres chemins. Je veux aussi savoir si on garde `sem01` après ce module. Format ADR habituel ; Karim, Sophie et Nadia relisent.

**Objectifs pédagogiques**
- Comparer des modes d'exécution d'une gestion de configuration (poste, CI, orchestrateur, agent en mode *pull*) sur des critères explicites : traçabilité, séparation des rôles, secrets, disponibilité, coût d'exploitation.
- Trancher une question de concurrence entre exécutants et une question de cycle de vie (conserver ou détruire `sem01`).
- Prévoir les exceptions (urgence, panne de la forge) sans vider la règle de son sens.

**Prérequis** : M04-E27, M04-E28, M04-E29, M04-E30 ; ADR précédents (format).
**Durée indicative** : 2 h.

**Travail demandé**

Rédige `docs/socle/adr/ADR-0040-execution-ansible.md` dans `plateforme/medisphere` (MR relue). Au moins quatre options : application depuis les postes ; CI GitLab seule ; Semaphore seul ; CI pour les changements et Semaphore pour l'exploitation. Mentionne AWX et `ansible-pull` dans l'analyse (retenus ou écartés, avec la raison). La décision doit trancher au minimum :
- le chemin **normal** d'un changement (de la MR à l'application) et qui peut déclencher l'application ;
- ce qui reste permis depuis `adm01`, et dans quelles conditions (procédure de bris de glace : qui, comment c'est tracé, comment on revient au chemin normal) ;
- comment on empêche deux applications simultanées par des chemins différents ;
- la détection de dérive et ce qu'on fait d'une dérive constatée ;
- la place des secrets (identités Vault, qui détient quoi) ;
- le sort de `sem01` (conservé comme service du socle, avec ce que ça implique : VMID et adresse définitifs, sauvegarde, supervision, mises à jour ; ou détruit en fin de module, avec ce qu'on perd).

**Critères de réussite**
- [ ] L'ADR est fusionné, au format des ADR précédents, avec au moins quatre options comparées sur des facteurs explicites.
- [ ] Chacun des six points ci-dessus est tranché ; la procédure de bris de glace tient en dix lignes et est vérifiable après coup.
- [ ] Les conséquences négatives sont nommées avec leur traitement, et la décision sur `sem01` est cohérente avec le plan d'adressage (PLAN §4.5, §4.8).

<details><summary>Indice 1</summary>

Un verrou partagé entre GitLab et Semaphore n'existe pas tout fait. Trois familles de réponses : un seul exécutant capable d'**appliquer** (l'autre ne fait que vérifier) ; un verrou sur la cible elle-même (un fichier verrou posé par un premier play sur chaque hôte, avec expiration) ; une discipline organisationnelle. Évalue chacune sur « que se passe-t-il à 3 h du matin quand GitLab est en panne ».
</details>

<details><summary>Indice 2</summary>

Pour `sem01`, le PLAN réserve 1000-1099 au socle et 10.10.20.10-49 aux services statiques : conserver `sem01` en 2041 contredit la convention des VMs d'environnement. Une décision « on le garde » implique une mise à jour du PLAN.
</details>

**Pour aller plus loin** : ajoute un tableau RACI (qui décide, qui exécute, qui est consulté, qui est informé) pour un changement standard et pour une urgence.

---

### M04-E32 — Questions : Ansible, Puppet (OpenVox), Salt, AWX  `Q` `★★`

> **Ticket PLAT-573** — *De : Karim Benali*
> Le prestataire InfoGér nous a laissé des manifestes Puppet pour les anciens serveurs, et la direction a reçu une offre commerciale pour AWX « clés en main ». Avant qu'on me demande pourquoi on n'a pas pris tel ou tel outil, je veux que tu saches le défendre. Réponds par écrit ; pour les QCM, dis aussi pourquoi les autres réponses sont fausses.

**Objectifs pédagogiques**
- Situer Ansible parmi les gestionnaires de configuration : modèle *push*/*pull*, agent, langage, état, convergence.
- Connaître l'état actuel des projets (licences, forks, maintenance) et ce qu'il implique pour un choix durable.
- Savoir lire et migrer une configuration d'un autre outil.

**Prérequis** : M04-E01, M04-E28.
**Durée indicative** : 1 h 30.

**Questions**

1. Explique les modèles *push* (Ansible) et *pull* (Puppet, `ansible-pull`). Pour chacun : qui initie la connexion, où vit la vérité, comment une machine éteinte pendant un changement le rattrape, quels flux réseau il faut ouvrir.
2. QCM — Puppet est distribué depuis 2025 :
   a) sous licence Apache 2.0 comme avant, par Perforce ; b) sous une licence propriétaire « Puppet Core », avec un fork communautaire, OpenVox, qui reprend le code libre ; c) uniquement en SaaS ; d) le projet est abandonné sans successeur.
3. Un manifeste Puppet décrit une ressource `file` avec `ensure => file` et `source => 'puppet:///modules/ntp/ntp.conf'`. Quel est l'équivalent Ansible ? Quelle différence de **moment** d'évaluation entre le catalogue Puppet et un playbook Ansible, et quelle conséquence pour les dépendances entre ressources (`require`, `notify` contre l'ordre des tâches et les handlers) ?
4. Salt peut fonctionner avec agents (*minions*) ou sans (`salt-ssh`). Quels avantages apporte son bus d'événements (ZeroMQ) par rapport à Ansible ? Quel inconvénient de sécurité a montré l'histoire du *master* Salt (cherche les CVE de 2020) ?
5. QCM — AWX en 2026 :
   a) est la version libre et maintenue d'Ansible Automation Platform, avec des versions mensuelles ; b) n'a plus publié de version depuis la 24.6.1 (juillet 2024), son développement étant suspendu pour une refonte ; c) a été remplacé par Semaphore UI chez Red Hat ; d) ne fonctionne que sur OpenShift.
6. Cite trois choses qu'AWX (ou Ansible Automation Platform) fait et que Semaphore UI 2.19 édition libre ne fait pas, puis trois raisons de préférer Semaphore dans le contexte de MédiSphère aujourd'hui.
7. Ansible est dit « sans agent ». Qu'est-ce qui doit pourtant être présent sur l'hôte géré ? Que se passe-t-il pour `gw01` si Python est désinstallé ? Quel module permet de s'en sortir ?
8. Que signifie l'idempotence pour Puppet et pour Ansible ? Pourquoi un module `command` d'Ansible ne l'est-il pas par défaut, et quelles sont les trois façons de le rendre idempotent ?
9. QCM — Quel outil applique une configuration **même si personne ne lance rien**, par défaut ?
   a) Ansible avec `ansible-playbook` ; b) Puppet avec son agent ; c) Semaphore UI sans planification ; d) Molecule.
10. Tu dois reprendre les manifestes Puppet d'InfoGér. Propose une démarche de migration en cinq étapes vers des rôles Ansible, avec la manière de prouver que rien n'a été oublié.
11. Chef et CFEngine existent toujours. En une phrase chacun : leur modèle, et pourquoi ils ne sont pas retenus ici.
12. Qu'est-ce qu'une « exécution de convergence » dans un outil *pull* toutes les 30 minutes, du point de vue de la dérive ? Comparé à ta détection de l'E29, qu'est-ce qui change pour l'audit HDS ?

**Critères de réussite**
- [ ] Les 12 questions ont une réponse écrite et argumentée ; les QCM indiquent la bonne réponse **et** pourquoi les autres sont fausses.
- [ ] Après correction, un tableau comparatif d'une demi-page (Ansible, OpenVox, Salt, CFEngine) est rangé dans ton journal.

<details><summary>Indice 1</summary>

Les changements de licence et de gouvernance récents sont résumés dans `annexes/versions-bloc-A.md` du workbook ; vérifie les dates sur les sites des projets.
</details>

<details><summary>Indice 2</summary>

Pour la question 7, pense aux modules qui n'utilisent pas Python côté hôte géré, et à la façon dont tu as installé Python sur des images minimales.
</details>

**Pour aller plus loin** : installe OpenVox sur une VM jetable (2049, après l'E34) et écris le même rôle `motd` dans les deux langages.

---

### M04-E33 — Questions de production : configuration à l'échelle  `Q` `★★★`

> **Ticket PLAT-576** — *De : Karim Benali*
> Questions de revue d'architecture, pour quand on passera de cinq machines à cinq cents. Argumente, chiffre quand tu peux, et dis quand « ça dépend » — mais de quoi.

**Objectifs pédagogiques**
- Raisonner sur le passage à l'échelle d'Ansible : inventaires, performances, organisation du code, gouvernance des changements.
- Anticiper les pannes d'une chaîne de configuration et leur rayon d'impact.

**Prérequis** : paliers 1 à 3 du module.
**Durée indicative** : 1 h 30.

**Questions**

1. Avec 500 hôtes et `forks = 50`, une collecte de faits prend 3 s par hôte. Estime la durée de la seule collecte avec la stratégie `linear`, puis ce que changent `gather_subset: [min]`, un cache de faits et `strategy: free`. Quelle ressource du **contrôleur** devient alors le facteur limitant ?
2. QCM — Un play a `serial: "25%"` sur 10 hôtes et `max_fail_percentage: 20`. Dans le deuxième lot, un hôte échoue. Que se passe-t-il ?
   a) le play continue, 1 sur 10 = 10 % < 20 % ; b) le play s'arrête à la fin du lot : 1 échec sur 2 hôtes du lot dépasse 20 % ; c) le play s'arrête immédiatement sur tous les hôtes ; d) `max_fail_percentage` ne fonctionne pas avec `serial` en pourcentage.
3. Un rôle partagé par trois équipes reçoit un changement incompatible. Comment versionnes-tu et distribues-tu les rôles (collection, `requirements.yml`, étiquettes, branches) pour qu'une équipe ne casse pas les autres ? Quelle place pour la collection `medisphere.socle` ?
4. Pourquoi `--check` ne prouve-t-il pas qu'une application réussira ? Donne trois exemples concrets tirés de tes rôles.
5. Un `site.yml` unique pour tout le parc, ou un playbook par service ? Arguments, et ce que tu fais de `site.yml` à 500 hôtes.
6. L'inventaire dynamique Proxmox met 40 s à se construire et l'API tombe parfois. Quelles options (cache du plugin d'inventaire, inventaire matérialisé, NetBox au module 06) et quels risques pour chacune ?
7. QCM — Où placer une variable « serveur NTP du VLAN » pour qu'un hôte puisse la surcharger, qu'un groupe puisse la surcharger, et qu'un `-e` de dépannage l'emporte toujours ?
   a) `defaults/main.yml` du rôle, puis `group_vars`, `host_vars`, `-e` ; b) `vars/main.yml` du rôle ; c) `group_vars/all` uniquement ; d) `set_fact` dans le rôle.
8. Un collègue propose `ignore_errors: true` sur les tâches qui échouent « parfois ». Que réponds-tu ? Quelles alternatives selon la cause (réseau, verrou APT, service lent à démarrer) ?
9. La forge est en panne et `gw01` doit être reconfiguré en urgence. Que permet ton ADR-0040 ? Que faut-il avoir **avant** la panne pour que ce soit possible sans improvisation ?
10. Pourquoi les tests Molecule sur VMs sont-ils plus fiables mais plus lents que sur conteneurs ? Comment organises-tu une CI qui teste 30 rôles en moins de 15 minutes ?
11. QCM — `check-socle` affiche dans le journal d'une MR le *diff* d'un modèle qui contient un jeton. Qui peut le lire ?
   a) personne, GitLab masque les secrets ; b) les membres du projet qui ont accès aux journaux de jobs (par défaut, au moins les *Reporters*, voire tout le monde si le projet est public) ; c) seulement les *Maintainers* ; d) seulement l'auteur de la MR.
12. Comment mesures-tu, chaque mois, que la gestion de configuration « fonctionne » ? Propose quatre indicateurs et leur seuil d'alerte.

**Critères de réussite**
- [ ] Les 12 questions ont une réponse écrite et argumentée ; les QCM indiquent la bonne réponse **et** pourquoi les autres sont fausses.
- [ ] Après correction, trois points faibles identifiés, avec un exercice ou une lecture pour chacun.

<details><summary>Indice 1</summary>

Pour les questions 1 et 2, relis tes mesures de l'E26 et tes expériences de l'E25 : un pourcentage de `serial` donne un nombre entier d'hôtes, et `max_fail_percentage` se compare **par lot**.
</details>

<details><summary>Indice 2</summary>

Pour la question 11, regarde ce que GitLab masque réellement : des **valeurs de variables CI** déclarées masquées, pas des chaînes déchiffrées par Ansible au milieu d'un journal.
</details>

**Pour aller plus loin** : lis la documentation d'Ansible sur les *execution environments* (`ansible-builder`, `ansible-navigator`) et dis ce qu'ils apporteraient à ton E27.

---

### M04-E34 — Un rôle complet en temps limité  `CHRONO` `★★★`

> **Ticket PLAT-579** — *De : Karim Benali*
> Au module 21, on supervisera tout le socle avec Prometheus. Il faudra un exportateur de métriques système sur chaque machine. Fais-moi le rôle maintenant, dans les conditions d'une vraie journée : un cahier des charges, un temps limité, et à la fin une MR que je puisse fusionner sans rien te demander.

**Règles de l'exercice**
- Conditions d'examen : pas de corrigé, pas de rôle de l'Internet copié ; tes rôles, tes notes, la documentation officielle (Ansible, Debian, node_exporter) et `ansible-doc` sont permis.
- Durée : **2 h 30** entre l'ouverture du cahier des charges (T0) et la MR prête à fusionner, pipeline vert (T4). Les pauses ne comptent pas, les attentes de la CI comptent.
- Le cahier des charges est dans `~/DevOpsPrivateCloud/modules/04-ansible/ressources/M04-E34/cahier-des-charges.md`. **Ne l'ouvre qu'au démarrage du chrono.**
- Instance Molecule : VMID **2049**, nom `m04-mol-nodeexp`.

**Prérequis** : M04-E10 à M04-E24, M04-E27.
**Durée** : 2 h 30 chronométrées + 30 minutes de retour d'expérience.

**Déroulé**
1. Prépare ta feuille de temps (ci-dessous) et un chronomètre. Vérifie que la VM 2049 n'existe pas et que le pipeline de `main` est vert.
2. T0 : ouvre le cahier des charges.
3. Livre : le rôle, son scénario Molecule, ses tests, la MR.
4. Arrête le chrono quand la MR est prête à fusionner (pipeline vert, description complète). Fusionne-la ensuite (hors chrono). **N'applique pas** le rôle au socle : ce sera le travail du module 21.

**Feuille de temps à remplir**

| Jalon | Définition | Heure | Écart depuis T0 | Commentaire |
|---|---|---|---|---|
| T0 | Ouverture du cahier des charges | | 0 | |
| T1 | Rôle écrit, appliqué une première fois sur l'instance Molecule | | | |
| T2 | Idempotence et `verify.yml` au vert en local | | | |
| T3 | ansible-lint (profil `production`) sans erreur, MR ouverte | | | |
| T4 | Pipeline de la MR vert, description complète | | | |

**Retour d'expérience à rédiger** (une demi-page, dans ton journal) : ce qui a pris le plus de temps, ce que tu as dû chercher dans la documentation, ce que tu automatiserais (un gabarit de rôle ? `ansible-galaxy role init` avec ton propre squelette ?), ce que tu ferais différemment.

**Critères de réussite**
- [ ] Le rôle `node_exporter` et le scénario `molecule/node_exporter` sont sur `main` (fusionnés après le chrono).
- [ ] Le scénario réussit en CI (job Molecule du rôle) ; la VM 2049 n'existe plus.
- [ ] Chaque exigence du cahier des charges est couverte par une tâche **et** par une vérification de `verify.yml`.
- [ ] T4 − T0 ≤ 2 h 30 (sinon, refais l'exercice sur un autre rôle de ton choix après avoir lu la grille du corrigé).

**Vérification** : `lab/bin/check 04 34`

**Pour aller plus loin** : refais l'exercice en binôme « auteur / relecteur » : l'un écrit, l'autre ne relit que la MR finale avec la grille du corrigé.
