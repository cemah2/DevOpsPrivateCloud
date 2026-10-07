# Module 04 — Palier 1 : Découverte — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Ce corrigé suit l'ordre de l'énoncé. Les questionnaires (E01, E09) sont argumentés et les QCM expliquent pourquoi les autres options sont fausses. Les fichiers complets du projet sont dans [`fichiers/`](fichiers/), exercice par exercice (`fichiers/M04-EXX/ansible/` reproduit l'arborescence du projet : ne copie que ce que l'exercice ajoute ou modifie).

Ce qui a été testé à la rédaction : tous les playbooks passent `ansible-playbook --syntax-check` avec ansible-core **2.21.5 et 2.19.14**, et `ansible-lint` 26.9 avec le profil `production` ; l'inventaire, les variables (`ansible-inventory`, module `debug`) et le rendu des templates (`--check --diff`) ont été vérifiés avec des hôtes simulés en connexion locale ; le bac à sable de E06 a été exécuté et ses résultats sont ceux du corrigé ; la validation `chronyd -p` a été testée avec un vrai binaire chrony. Les collections et l'environnement uv ont été installés et verrouillés pour de vrai.

Points **non testés en conditions réelles**, à vérifier sur ta version et à signaler s'ils diffèrent :
- l'exécution des playbooks sur les vraies VMs Debian 13 du socle (en particulier la présence de `python3-apt` sur `gw01` et sur les VMs issues du template, E05) ;
- la directive `leapseclist` du template chrony : elle figure dans le `chrony.conf` de Debian 13 (chrony 4.6) mais est **refusée** par chrony 4.5 (testé) : si ta validation échoue sur cette ligne, vérifie `chronyd --version` (E08) ;
- la question posée par Ansible face à une clé d'hôte inconnue (E03, étape 6), dont la forme dépend de la version d'OpenSSH ;
- `uv init --bare` et `uv python pin` ont été testés avec uv 0.11 ; uv 0.12 n'annonce pas de changement sur ces commandes.

---

### M04-E01 — Test de positionnement : gestion de configuration

**Barème** : 2 points par question. 2 = complet et justifié ; 1 = idée juste mais incomplète ; 0 = faux ou blanc. Total sur 40. En dessous de 20, lis attentivement les introductions des exercices E04 à E08 avant de les faire ; au-dessus de 30, tu peux aller vite sur E04.

**Réponses argumentées — gestion de configuration**

**1. Idempotence et convergence.** Une opération est *idempotente* si l'appliquer une fois ou dix fois donne le même état. La *convergence*, c'est la capacité à amener un système vers l'état décrit **quel que soit son état de départ** (paquet absent, présent dans une autre version, fichier modifié à la main…). `apt-get install -y tcpdump` est idempotent *sur l'état* dans le cas simple : la seconde fois, le paquet est déjà là. Mais (a) il ne l'est pas tout à fait : si une version plus récente est disponible, la commande **met à jour** le paquet ; (b) il ne l'est pas *dans ce qu'il rapporte* : il s'exécute à chaque fois, sans dire s'il a changé quelque chose, sans simulation possible, sans différence affichée. Un outil de gestion de configuration doit savoir dire « rien à faire » : c'est ce qui permet de détecter la dérive (un passage qui annonce un changement imprévu est une alerte).

**2. Dérive.** C'est l'écart, apparu avec le temps, entre l'état réel d'une machine et l'état décrit. Causes : modification à la main pendant un incident jamais reportée dans le code ; mise à jour d'un paquet qui change une valeur par défaut ou réécrit un fichier ; outil tiers qui écrit dans la même configuration ; correctif d'urgence appliqué sur une machine et pas sur les autres. cloud-init ne suffit pas : il s'exécute **une fois par instance** (au premier démarrage), donc (a) une politique qui change (nouvelle règle SSH) ne s'applique pas aux machines existantes, (b) rien ne détecte ni ne corrige ce qui a bougé depuis. Il faut un outil qu'on rejoue régulièrement, en simulation pour détecter (E29), en réel pour corriger.

**3. *Push* contre *pull*.**

| | *Push* (Ansible) | *Pull* avec agent (Puppet, Salt) |
|---|---|---|
| Avantages | aucun agent à installer et maintenir ; orchestration naturelle (ordre entre machines, mises à jour progressives) ; exécution à la demande, résultat immédiat | application **continue** (toutes les 30 min) : la dérive est corrigée sans intervention ; passe à l'échelle (des milliers d'agents) ; fonctionne pour des machines qu'on ne peut pas joindre (NAT, portables) |
| Inconvénients | le nœud de contrôle doit joindre toutes les machines (flux, clés) et devient très privilégié ; rien ne se passe si personne ne lance Ansible (il faut un planificateur : CI, Semaphore) ; plus lent à grande échelle (SSH, Python par tâche) | un agent à installer, superviser, mettre à jour et sécuriser ; une PKI pour authentifier les agents ; orchestration entre machines plus difficile ; consommation de ressources permanente |

**4. Réponse B.** Ansible a besoin d'une connexion (SSH sous Linux) et d'un interpréteur Python pour exécuter ses modules. A est faux : Ansible est *agentless*. C est faux dans le cas général : seul le module `raw` (et les équipements réseau gérés par des plugins de connexion spécifiques) se passe de Python. D est faux : les collections sont installées sur le **nœud de contrôle** ; Ansible envoie à chaque tâche le code du module nécessaire, empaqueté (AnsiballZ, E44).

**5. Déclaratif.** Chaque module décrit un état (`state: present`, `state: started`) et décide lui-même s'il y a quelque chose à faire : c'est déclaratif. Mais l'ensemble ne l'est pas complètement : les tâches s'exécutent **dans l'ordre** ; `command` et `shell` sont impératifs ; et surtout, **retirer une tâche ne défait pas ce qu'elle a fait** : supprimer la ligne qui installait `telnet` ne le désinstalle pas (il faut une tâche `state: absent`). C'est une différence majeure avec OpenTofu (M05), qui garde un état et détruit ce qui n'est plus décrit.

**Réponses argumentées — Ansible**

**6. Vocabulaire.** *Inventaire* : la liste des hôtes, rangés en groupes, avec leurs variables. *Play* : associe un ensemble d'hôtes (motif) à une liste de tâches et à des réglages (élévation, faits, stratégie). *Tâche* : un appel à un module avec ses paramètres, plus des mots-clés (`when`, `loop`, `notify`…). *Module* : le code qui fait le travail sur l'hôte et rapporte `changed`/`failed`. *Handler* : une tâche qui ne s'exécute que si elle a été notifiée par une tâche qui a changé quelque chose. *Rôle* : un ensemble réutilisable (tâches, handlers, templates, variables par défaut, métadonnées) pour une fonction. *Collection* : l'unité de distribution (modules, plugins, rôles), avec un espace de noms (`community.general`).

**7. `command`, `shell`, `raw`, `script`.** `command` exécute un programme avec ses arguments, **sans shell** (pas de tube, pas de redirection, pas de `$VAR`) : plus sûr. `shell` passe la ligne à `/bin/sh -c` : tubes et redirections possibles, risques d'injection et de comportements dépendant du shell. `raw` envoie la commande telle quelle par SSH, sans Python, sans module, sans gestion de `changed`. `script` copie un script local sur l'hôte et l'exécute. `raw` est légitime pour **amorcer** une machine sans Python (installer `python3`) ou pour des équipements qui n'en ont pas.

**8. Réponse B.** Le module `ping` d'Ansible n'a rien à voir avec ICMP (A) : il prouve que la connexion, l'authentification, le transfert et l'exécution d'un module Python fonctionnent, et que l'hôte répond. Il ne prouve pas `sudo` (C) tant qu'on ne lui ajoute pas `-b`. Il ne prouve pas le DNS (D) si l'inventaire donne une adresse IP dans `ansible_host`, ce qui est notre cas.

**9. `become`.** `become: true` exécute la tâche avec une élévation de privilèges, par la méthode `become_method` (défaut `sudo`) vers l'utilisateur `become_user` (défaut `root`). `become_user: postgres` permet de devenir un autre compte que root. Écrire `sudo` dans une commande `shell` contourne ce mécanisme : Ansible ne sait pas gérer un éventuel mot de passe (la commande se bloque ou échoue), le module tourne avec les droits de l'utilisateur de connexion (il ne peut pas, par exemple, écrire son fichier temporaire là où il faut), les tâches ne sont plus portables (`doas`, `su`), et ansible-lint le signale.

**10. Réponse B.** En mode simulation, `command` (et `shell`) ne peut pas savoir ce que ferait la commande : la tâche est sautée (*skipped*). Exception : avec `creates` ou `removes`, le module peut prédire (« le fichier existe, je ne ferais rien »). Pour une commande de **lecture** qu'on veut exécuter même en simulation (relever une version, attendre une synchronisation), on ajoute `check_mode: false` et `changed_when: false` (E08). A et D sont faux pour cette raison ; C est faux : le mode simulation accepte la tâche, il la saute.

**11. Faits.** Ce sont les informations sur l'hôte (système, réseau, matériel, montages, Python…) collectées par le module `setup` au début de chaque play (`gather_facts: true` par défaut). Elles coûtent l'exécution d'un module assez lourd sur chaque hôte (de quelques dixièmes de seconde à plusieurs secondes selon le matériel et les montages réseau). On s'en passe avec `gather_facts: false` quand le play n'en utilise aucune, on les restreint avec `gather_subset`, ou on les met en cache (E26).

**12. Handlers.** Un handler notifié s'exécute à la fin de la section de tâches en cours (`pre_tasks`, tâches et rôles, `post_tasks`), ou à l'endroit d'un `meta: flush_handlers`. Notifié trois fois, il ne s'exécute **qu'une fois**. Les handlers s'exécutent dans l'ordre où ils sont **définis**, pas dans l'ordre des notifications. Si une tâche échoue après la notification, l'hôte sort du play et ses handlers ne s'exécutent pas (sauf `--force-handlers` ou `force_handlers: true`) : la configuration est changée mais le service n'a pas été redémarré, et au passage suivant plus rien ne le notifiera (piège de E08).

**13. `template` et `validate`.** `template` produit le fichier **par hôte** à partir de variables et de faits (Jinja2) ; `copy` dépose un contenu identique partout (ou un `content:` évalué une fois). `validate` exécute une commande sur le fichier **temporaire** avant de le mettre en place (`%s` = son chemin) : si la commande échoue, le fichier en place n'est pas touché et la tâche échoue. Exemples : `visudo -cf %s`, `sshd -t -f %s`, `nginx -t -c %s`, `chronyd -p -f %s`.

**14. `defaults/` et `vars/`.** `defaults/main.yml` a la **plus basse** précédence de toutes : ce sont les valeurs proposées, que l'inventaire ou le play peuvent remplacer. `vars/main.yml` a une précédence élevée (au-dessus de l'inventaire et des variables de play) : on y met des constantes internes au rôle, qu'on ne veut pas voir remplacées par accident (noms de paquets par distribution, chemins). Le port d'écoute réglable va dans `defaults/`.

**15. Réponse B.** `ansible-core` contient le moteur, les commandes et la collection `ansible.builtin`. Le paquet `ansible` installe un `ansible-core` d'une série donnée **plus** une sélection de collections maintenues par la communauté (Ansible 12 → ansible-core 2.19, 13 → 2.20, 14 → 2.21). A et D sont faux (ce sont deux paquets distincts, tous deux libres) ; C inverse la relation. Le workbook utilise `ansible-core` et installe **seulement** les collections nécessaires, à des versions fixées.

**16. Vault.** Ansible Vault chiffre (AES-256) des fichiers ou des valeurs **au repos**, dans le dépôt : sans le mot de passe, rien n'est lisible. À l'exécution, la valeur est déchiffrée en mémoire et peut fuiter : (a) dans la sortie d'une tâche (paramètres affichés avec `-v`, message d'erreur d'un module qui reprend ses arguments, `debug`) → `no_log: true` sur les tâches qui manipulent un secret ; (b) sur l'hôte, dans un fichier produit par un template ou dans la ligne de commande d'un processus (visible dans `ps`) → droits restreints sur les fichiers (`mode: "0600"`), secrets passés par fichier ou entrée standard plutôt qu'en argument ; (c) dans un journal (`log_path`) ou un artefact de CI.

**17. Idempotence de quatre tâches.**
- `file: state=touch` : **non** ; chaque passage met à jour les dates du fichier et compte « changed » (sauf avec `access_time: preserve` et `modification_time: preserve`, E04).
- `lineinfile` sans `regexp` : **oui** tant que la ligne exacte existe ; mais si une autre ligne `HTTP_PROXY=…` existe déjà (ancienne adresse), la nouvelle s'ajoute à côté : idempotent mais **pas convergent**. Ajouter `regexp: '^HTTP_PROXY='`.
- `shell: echo … >> fichier` : **non** ; une ligne de plus à chaque passage, et toujours « changed ».
- `command` avec `creates` : **oui**, la commande ne s'exécute plus quand le marqueur existe. Limite : si ce que fait le script doit évoluer, il ne sera jamais rejoué ; et le marqueur peut exister alors que le travail a échoué à moitié.

**18. `forks`, `serial`, `strategy: free`.** `forks` : nombre d'hôtes traités **en parallèle** pour chaque tâche (défaut 5). `serial` : taille des **lots** d'hôtes qui traversent tout le play avant de passer au lot suivant (mise à jour progressive) ; avec `max_fail_percentage`, Ansible arrête au premier lot en erreur. `strategy: free` : chaque hôte enchaîne ses tâches sans attendre les autres (plus rapide, moins lisible). C'est `serial` (avec un premier lot petit, par exemple `serial: [1, 10%, 100%]`) qui protège d'une erreur qui casserait tout le parc ; E25 y est consacré.

**Réponses argumentées — YAML et Jinja2**

**19. Types YAML 1.1** (vérifiés avec ansible-core 2.21) :

| Ligne | Ansible reçoit | Piège ? |
|---|---|---|
| `mode_a: 0644` | `420` (entier, lu en base 8) | fonctionne la plupart du temps (Ansible interprète l'entier), fragile dans les boucles et les templates |
| `mode_b: 644` | `644` (entier **décimal**) | **oui** : 644 en décimal vaut `0o1204` → droits absurdes (`--w----r-T` : écriture seule pour le propriétaire, lecture pour les autres, bit *sticky*) |
| `mode_c: "0644"` | `"0644"` (chaîne) | non : Ansible convertit lui-même la chaîne en base 8 ; c'est la forme à utiliser |
| `version_python: 3.10` | `3.1` (flottant) | **oui** : le zéro final disparaît ; écrire `"3.10"` |
| `code_pays: NO` | `false` (booléen) | **oui** (le « problème norvégien ») ; écrire `"NO"` |
| `actif: yes` | `true` (booléen) | toléré, mais `yamllint`/`ansible-lint` exigent `true` |
| `duree: 1:30` | `90` (entier, base 60) | **oui** ; écrire `"1:30"` |

**20. Jinja2.** `web01` (tri puis premier) ; `web1` (`~` concatène en convertissant en chaîne) ; `True` (un vrai booléen : c'est la bonne façon d'écrire une condition) ; `aucune` (`default` s'applique à une variable **indéfinie**) ; `None` (ou une chaîne vide selon le contexte d'affichage) : `proxy` est **définie**, sa valeur est nulle, donc `default` ne s'applique pas ; `direct` : le second argument `true` fait aussi remplacer les valeurs « fausses » (`null`, `""`, `0`, `[]`).

---

### M04-E02 — Créer le projet `plateforme/ansible` et un environnement reproductible

**Solution**

1. **Projet et fichiers standard.**
   ```
   admin@adm01:~$ MERGE_METHOD=rebase_merge ~/DevOpsPrivateCloud/modules/02-scripting/corrige/fichiers/M02-E02/configurer-projet.sh plateforme/ansible
   admin@adm01:~$ git clone git@git01.par1.medisphere.internal:plateforme/ansible.git ~/src/ansible
   admin@adm01:~$ cd ~/src/ansible && git switch -c chore/configuration-initiale
   admin@adm01:~/src/ansible$ cp ~/src/outils/{.pre-commit-config.yaml,commitlint.config.mjs,.releaserc.json,CONTRIBUTING.md} .
   admin@adm01:~/src/ansible$ mkdir -p .gitlab/merge_request_templates
   admin@adm01:~/src/ansible$ cp ~/src/outils/.gitlab/merge_request_templates/Default.md .gitlab/merge_request_templates/
   ```
   `.pre-commit-config.yaml` : reprends la configuration **de référence** (celle de M01-E15), pas les ajouts propres à `outils` (ShellCheck, shfmt, ruff), sauf si tu comptes avoir des scripts dans ce projet. `CONTRIBUTING.md` : section « projet » adaptée (conventions de l'introduction du module). `.gitlab-ci.yml` et `README.md` : [`fichiers/M04-E02/ansible/`](fichiers/M04-E02/ansible/).

2. **Environnement uv.** Fixe d'abord la politique Python (sinon uv peut télécharger un Python s'il ne trouve pas celui qu'il veut) :
   ```
   admin@adm01:~/src/ansible$ export UV_PYTHON_PREFERENCE=only-system UV_PYTHON_DOWNLOADS=never
   admin@adm01:~/src/ansible$ uv init --bare --name medisphere-ansible
   admin@adm01:~/src/ansible$ uv python pin 3.13
   admin@adm01:~/src/ansible$ uv add 'ansible-core~=2.21.0' 'proxmoxer>=2.3.0' 'requests>=2.32.0'
   admin@adm01:~/src/ansible$ uv add --dev 'ansible-lint>=26.9,<27' 'molecule>=26.9,<27'
   ```
   Puis complète `[tool.uv]` (`package = false`, `python-preference = "only-system"`, `python-downloads = "never"`) : fichier complet [`fichiers/M04-E02/ansible/pyproject.toml`](fichiers/M04-E02/ansible/pyproject.toml). `uv sync --locked` reconstruit `.venv` à l'identique de `uv.lock`.
   ```
   admin@adm01:~/src/ansible$ uv run ansible --version
   ansible [core 2.21.5]
     config file = /home/admin/src/ansible/ansible.cfg
     configured module search path = ['/home/admin/.ansible/plugins/modules', '/usr/share/ansible/plugins/modules']
     ansible python module location = /home/admin/src/ansible/.venv/lib/python3.13/site-packages/ansible
     ansible collection location = /home/admin/src/ansible/collections
     executable location = /home/admin/src/ansible/.venv/bin/ansible
     python version = 3.13.5 (main, …) [GCC 14.2.0] (/home/admin/src/ansible/.venv/bin/python3)
     jinja version = 3.1.6
     pyyaml version = 6.0.3 (with libyaml v0.2.5)
   ```
   (Avant l'écriture d'`ansible.cfg`, la deuxième ligne affiche `config file = None` et les collections sont cherchées dans `~/.ansible/collections` et `/usr/share/ansible/collections`.)

   Réponses du journal :
   - `~=2.21.0` signifie `>=2.21.0, <2.22` : on reçoit les correctifs de la série 2.21, jamais une nouvelle version mineure d'ansible-core, qui peut changer des comportements (guides de portage). `>=2.21` laisserait passer la 2.22 au prochain `uv lock --upgrade`.
   - `uv.lock` fige la version **exacte** de chaque paquet, y compris les dépendances indirectes (Jinja2, PyYAML, cryptography, resolvelib… une quarantaine), avec l'empreinte SHA-256 de chaque fichier téléchargé : deux machines obtiennent exactement les mêmes octets.
   - `.venv/bin/molecule --version` lancé directement échoue (`FileNotFoundError: … 'ansible-config'`) : Molecule appelle les commandes d'Ansible **par le `PATH`**, qui ne contient pas `.venv/bin` tant que le venv n'est pas activé. `uv run` (ou `source .venv/bin/activate`) ajoute `.venv/bin` en tête du `PATH`.

3. **Lecture de `ansible --version`** : la configuration utilisée (ligne `config file`), l'endroit où Ansible cherche les collections (`ansible collection location`), le Python **du nœud de contrôle** qui exécute Ansible (celui du venv, lui-même le 3.13 de Debian). Le Python des hôtes gérés est une autre affaire (`interpreter_python`, E03).

4. **`ansible.cfg`** : [`fichiers/M04-E02/ansible/ansible.cfg`](fichiers/M04-E02/ansible/ansible.cfg), chaque ligne commentée.
   ```
   admin@adm01:~/src/ansible$ uv run ansible-config dump --only-changed -t all
   ANSIBLE_PIPELINING(/home/admin/src/ansible/ansible.cfg) = True
   COLLECTIONS_PATHS(/home/admin/src/ansible/ansible.cfg) = ['/home/admin/src/ansible/collections']
   CONFIG_FILE() = /home/admin/src/ansible/ansible.cfg
   DEFAULT_FORKS(/home/admin/src/ansible/ansible.cfg) = 10
   DEFAULT_HOST_LIST(/home/admin/src/ansible/ansible.cfg) = ['/home/admin/src/ansible/inventories/lab/hosts.yml']
   DEFAULT_ROLES_PATH(/home/admin/src/ansible/ansible.cfg) = ['/home/admin/src/ansible/roles']
   INJECT_FACTS_AS_VARS(/home/admin/src/ansible/ansible.cfg) = False
   INTERPRETER_PYTHON(/home/admin/src/ansible/ansible.cfg) = /usr/bin/python3
   …
   CALLBACK:
   ========
   default:
   _______
   result_format(/home/admin/src/ansible/ansible.cfg) = yaml
   …
   CONNECTION:
   ==========
   …
   ssh:
   ___
   pipelining(/home/admin/src/ansible/ansible.cfg) = True
   admin@adm01:~/src/ansible$ uv run ansible-config validate -t all
   All configurations seem valid!
   ```
   Les réglages des **plugins** (`result_format` du callback, `pipelining` des connexions) apparaissent sous le nom de chaque plugin : c'est pour eux que `-t all` est nécessaire.

   Réponses du journal :
   - Ordre de recherche : variable `ANSIBLE_CONFIG`, puis `ansible.cfg` du **dossier courant**, puis `~/.ansible.cfg`, puis `/etc/ansible/ansible.cfg`. **Le premier trouvé gagne, les autres sont ignorés** (pas de fusion).
   - Depuis `~/src/ansible/playbooks`, le dossier courant n'a pas d'`ansible.cfg` : Ansible prend `~/.ansible.cfg` ou `/etc/ansible/ansible.cfg`, ou ses valeurs par défaut. Plus d'inventaire du lab, plus de collections du projet, faits injectés… D'où la règle « toujours depuis la racine du projet ». Les chemins relatifs **dans** `ansible.cfg`, eux, sont résolus par rapport au fichier, pas au dossier courant.
   - Un dossier modifiable par tous (`chmod o+w`, `/tmp` sans précaution, dossier partagé monté) permettrait à n'importe quel utilisateur d'y déposer un `ansible.cfg` qui charge ses propres plugins, donc d'exécuter du code avec les droits de celui qui lance Ansible : Ansible ignore alors ce fichier, avec un avertissement.

5. **Collections** : [`fichiers/M04-E02/ansible/collections/requirements.yml`](fichiers/M04-E02/ansible/collections/requirements.yml).
   ```
   admin@adm01:~/src/ansible$ uv run ansible-galaxy collection install -r collections/requirements.yml -p collections
   …
   community.general:13.5.0 was installed successfully
   community.library_inventory_filtering_v1:1.1.5 was installed successfully
   admin@adm01:~/src/ansible$ uv run ansible-galaxy collection list

   # /home/admin/src/ansible/collections/ansible_collections
   Collection                               Version
   ---------------------------------------- -------
   ansible.posix                            2.2.2
   community.general                        13.5.0
   community.library_inventory_filtering_v1 1.1.5
   community.proxmox                        2.1.0
   ```
   Quatre collections : `community.library_inventory_filtering_v1` est une **dépendance** déclarée par `community.general` (son `MANIFEST.json`), installée automatiquement. Exigences d'ansible-core (`meta/runtime.yml`, `requires_ansible`) : `community.proxmox` ≥ 2.17, `community.general` ≥ 2.18, `ansible.posix` ≥ 2.16 : toutes compatibles avec la 2.19 de Debian et la 2.21 du projet.

6. **`.gitignore`** : [`fichiers/M04-E02/ansible/.gitignore`](fichiers/M04-E02/ansible/.gitignore). La règle clé :
   ```
   /collections/ansible_collections/*
   !/collections/ansible_collections/medisphere/
   ```
   ```
   admin@adm01:~/src/ansible$ git check-ignore -v collections/ansible_collections/community/general/MANIFEST.json
   .gitignore:10:/collections/ansible_collections/*	collections/ansible_collections/community/general/MANIFEST.json
   admin@adm01:~/src/ansible$ git check-ignore -v collections/ansible_collections/medisphere/socle/galaxy.yml || echo "non ignoré"
   non ignoré
   ```
   `.ansible/` : ansible-lint et Molecule y rangent leur cache dans le projet.

7. **Inventaire minimal** : [`fichiers/M04-E02/ansible/inventories/lab/hosts.yml`](fichiers/M04-E02/ansible/inventories/lab/hosts.yml).
   ```
   admin@adm01:~/src/ansible$ uv run ansible adm01 -m ansible.builtin.ping
   adm01 | SUCCESS =>
       changed: false
       ping: pong
   ```
   (Sortie en YAML grâce à `callback_result_format = yaml`.)

8. **MR** : comme en M02-E02. Le pipeline de `main` lance semantic-release, qui ne publie rien (`chore:`).

9. **Paquets Debian.** Debian 13 fournit `ansible-core` 2.19 et `ansible` 12 : paquets signés, mis à jour par les correctifs de sécurité de Debian, sans outil supplémentaire. Mais (a) la version est **celle de Debian** pendant toute la vie de trixie (2.19), alors que le projet veut choisir la sienne et la monter par MR ; (b) installés au niveau du système, ils sont les mêmes pour tous les projets du poste (un projet ne peut pas passer en 2.21 sans les autres) ; (c) `runner01` et `sem01` devraient avoir **exactement** la même version, ce qu'un verrou dans le dépôt garantit et que `apt` ne garantit pas (deux machines mises à jour à des dates différentes). Le paquet Debian est le bon choix pour un poste qui gère un petit parc stable, sans CI, où la stabilité de la distribution prime sur la maîtrise de la version.

**Explications**

- **Un environnement par projet.** Ansible est un programme Python : son comportement dépend de la version d'ansible-core, de Jinja2, de PyYAML et de chaque collection. Avec `pyproject.toml` + `uv.lock` (Python) et `requirements.yml` épinglé (collections), le dépôt décrit l'outil exact. La CI (E27) et Semaphore (E28) reconstruiront le même environnement avec `uv sync --locked`.
- **Le nœud de contrôle et les hôtes gérés.** Le venv ne concerne que `adm01` : rien n'est installé sur les hôtes gérés, qui n'ont besoin que de leur Python système. Ansible y envoie à chaque tâche le code du module à exécuter.
- **Des réglages justifiés, rien de plus.** `inject_facts_as_vars = False` prépare la 2.24 et fait échouer tout de suite le code copié d'un vieux tutoriel (`ansible_distribution`) ; `interpreter_python = /usr/bin/python3` évite que la découverte automatique choisisse un jour un `python3.14` installé à la main, sans `python3-apt` (la liste de repli essaie `python3.14`, `python3.13`… **avant** `/usr/bin/python3`) ; `pipelining = True` divise par deux ou trois les allers-retours SSH ; il est placé dans la section `[connection]`, reconnue par le cœur d'Ansible (la section historique `[ssh_connection]` marche aussi, mais seul le plugin SSH la comprend : `ansible-config validate` sans `-t all` la signale comme inconnue).
- **Ce qui n'y est pas.** `host_key_checking` reste à `True`. Aucune clé privée désignée : sur `adm01`, l'agent SSH ; en CI (E27), une clé dédiée fournie par une variable protégée. Pas de `ansible_managed` (déprécié, E07). Pas de `retry_files_enabled` (désactivé par défaut depuis longtemps).

**Alternatives**

- **`pip` + `requirements.txt` avec empreintes** (`pip-compile --generate-hashes`) : même résultat que uv, plus lent et en deux outils.
- **Environnements d'exécution en conteneur** (*Execution Environments* : `ansible-builder`, `ansible-navigator`) : l'image contient ansible-core, les collections **et** les dépendances système. C'est le modèle d'AWX et d'Ansible Automation Platform ; il prendra tout son sens après le module 12 (conteneurs).
- **`uv tool install ansible-core`** : un Ansible global pour l'utilisateur, simple, mais une seule version pour tous les projets et rien dans le dépôt.
- **Paquets Debian** : voir la réponse 9.

**Pièges classiques**

- Lancer Ansible depuis un sous-dossier, ou avec un `ANSIBLE_CONFIG` resté exporté dans le shell : la configuration du projet est ignorée sans message d'erreur. `ansible --version` (ligne `config file`) le montre en une seconde.
- Un `ansible` du système (paquet Debian, `pip install --user` d'un ancien tutoriel) qui passe devant celui du projet dans le `PATH` : `type -a ansible`. `uv run` lève l'ambiguïté.
- Des collections présentes dans `~/.ansible/collections` (installées un jour sans `-p`) : sans `collections_path` dans le projet, elles seraient utilisées, à une version inconnue, sur ton poste et pas en CI.
- Ignorer le dossier `collections/ansible_collections/` en entier : l'exception pour `medisphere/` ne s'applique plus (Git ne parcourt pas un dossier ignoré).
- Le hook `check-yaml` de pre-commit refuse les fichiers Ansible Vault (balise `!vault`) : il faudra l'option `--unsafe` en E12.
- Mettre `ansible-lint` et `molecule` dans les dépendances d'exécution : Semaphore (E28) installerait des outils de test inutiles. Le groupe `dev` les isole (`uv sync --no-dev` pour un exécutant).

**En production chez MédiSphère**

- Les mises à jour d'ansible-core, des outils et des collections arrivent par MR automatiques (Renovate, module 13), avec le guide de portage lu et le pipeline complet (lint, Molecule, `--check` du socle).
- Un dépôt de collections interne (GitLab, Galaxy NG ou Pulp) sert de miroir : les collections ne viennent plus d'Internet au moment du pipeline, et on peut en vérifier les signatures.
- À terme, un *Execution Environment* (image de conteneur construite par la CI) devient l'unité livrée aux exécutants (CI, Semaphore, AWX).

---

### M04-E03 — Inventaire statique du socle

**Solution**

1. **Ce qu'Ansible traverse.**
   ```
   admin@adm01:~$ ssh-keygen -F 10.10.20.15
   # Host 10.10.20.15 found: line 7
   |1|kq3…=|Wd1…= ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA…
   admin@adm01:~$ ssh -G 10.10.20.15 | grep -Ei '^(user|identityfile|stricthostkeychecking) '
   user admin
   identityfile ~/.ssh/id_ed25519
   stricthostkeychecking ask
   ```
   Les clés sont connues **sous l'adresse IP** : les alias de M00-E15 ont `HostName <IP>`, et OpenSSH enregistre la clé sous le nom réellement contacté (ici l'adresse ; les lignes sont hachées sur Debian, `HashKnownHosts yes`). En se connectant par l'adresse, seul le bloc `Host *` de `~/.ssh/config` s'applique : les blocs d'alias (`Host dns01`) ne correspondent pas. Note que `user admin` vient ici de ton nom d'utilisateur local, qui est le même : **coïncidence** sur `adm01`, qui ne tiendra pas en CI (l'utilisateur sera `gitlab-runner`). D'où `ansible_user: admin` explicite dans l'inventaire.

2. **Fichiers** : [`fichiers/M04-E03/ansible/inventories/lab/`](fichiers/M04-E03/ansible/inventories/lab/).
   - `hosts.yml` : le groupe `socle` porte les adresses, les groupes `role_*` reprennent les hôtes par leur nom ; tous enfants directs de `all`.
   - `group_vars/all/main.yml` : `ansible_user: admin`.
   - `host_vars/adm01/main.yml` : `ansible_connection: local`.

   Un **dossier** `group_vars/all/` permet de séparer plusieurs fichiers pour un même groupe : `main.yml` en clair et `vault.yml` chiffré (E12), sans tout chiffrer. Ansible lit tous les fichiers du dossier.

3. **Interrogation.**
   ```
   admin@adm01:~/src/ansible$ uv run ansible-inventory --graph
   @all:
     |--@ungrouped:
     |--@socle:
     |  |--gw01
     |  |--adm01
     |  |--dns01
     |  |--git01
     |  |--runner01
     |--@role_routeur:
     |  |--gw01
     |--@role_bastion:
     |  |--adm01
     |--@role_dns:
     |  |--dns01
     |--@role_gitlab:
     |  |--git01
     |--@role_runner:
     |  |--runner01
   admin@adm01:~/src/ansible$ uv run ansible-inventory --host adm01
   {
       "ansible_connection": "local",
       "ansible_host": "10.10.10.10",
       "ansible_user": "admin"
   }
   ```
   (Avec `inject_facts_as_vars = False`, `ansible-inventory` affiche aussi une clé `ansible_local` vide : c'est un artefact sans conséquence.)

4. **Motifs.**

   | Sélection | Motif |
   |---|---|
   | Le socle sauf le routeur | `'socle:!role_routeur'` |
   | `dns01` et `git01` | `'dns01:git01'` (ou `dns01,git01`) |
   | À la fois dans `socle` et `role_gitlab` | `'socle:&role_gitlab'` |
   | Les hôtes du VLAN INFRA | **pas par l'adresse** : un motif porte sur les **noms** d'hôtes et de groupes, jamais sur `ansible_host`. `'~10\.10\.20\.'` ne sélectionne rien |

   Pour le VLAN : un groupe dédié (mais il n'existerait pas dans l'inventaire dynamique, sauf à le construire), un groupe calculé (`groups:` du plugin d'inventaire `constructed` ou de `community.proxmox.proxmox` : `vlan_infra: ansible_host.startswith('10.10.20.')`, E13), ou un `ansible.builtin.group_by` dans un play. Pour une intervention ponctuelle, `--limit dns01,git01,runner01` suffit.
   ```
   admin@adm01:~/src/ansible$ uv run ansible 'socle:!role_routeur' --list-hosts
     hosts (4):
       adm01
       dns01
       git01
       runner01
   ```

5. **Connexion.**
   ```
   admin@adm01:~/src/ansible$ uv run ansible socle -m ansible.builtin.ping
   adm01 | SUCCESS =>
       changed: false
       ping: pong
   gw01 | SUCCESS =>
   …
   admin@adm01:~/src/ansible$ uv run ansible socle -m ansible.builtin.ping -vvv --limit dns01
   …
   <10.10.20.10> SSH: EXEC ssh -C -o ControlMaster=auto -o ControlPersist=60s -o KbdInteractiveAuthentication=no
     -o PreferredAuthentications=gssapi-with-mic,gssapi-keyex,hostbased,publickey -o PasswordAuthentication=no
     -o 'User="admin"' -o ConnectTimeout=10 -o 'ControlPath="/home/admin/.ansible/cp/3f2a9c1b7e"' 10.10.20.10
     '/bin/sh -c '"'"'/usr/bin/python3 && sleep 0'"'"''
   ```
   Ansible ajoute la compression, son **propre** multiplexage (`ControlMaster`, `ControlPersist=60s`, *socket* dans `~/.ansible/cp/`, qui prime sur le `ControlPath` de ton `~/.ssh/config` puisqu'il est passé en option), interdit les méthodes d'authentification interactives, force l'utilisateur et un délai de connexion. Avec le *pipelining*, le module est envoyé sur l'entrée standard de `/usr/bin/python3` au lieu d'être copié dans un fichier temporaire. Le Python est celui de `interpreter_python`.
   Un hôte sans Python répond `/usr/bin/python3: not found` (« MODULE FAILURE »). Seul `ansible.builtin.raw` fonctionne alors, puisqu'il n'exécute pas de module :
   ```
   admin@adm01:~/src/ansible$ uv run ansible gw01 -b -m ansible.builtin.raw -a 'apt-get install -y python3'
   ```

6. **Clé d'hôte inconnue.**
   ```
   admin@adm01:~/src/ansible$ uv run ansible runner01 -m ansible.builtin.ping -e 'ansible_ssh_common_args="-o UserKnownHostsFile=/dev/null"'
   The authenticity of host '10.10.20.15 (10.10.20.15)' can't be established.
   ED25519 key fingerprint is SHA256:Qm8…
   This key is not known by any other names.
   Are you sure you want to continue connecting (yes/no/[fingerprint])? no
   runner01 | UNREACHABLE! =>
       changed: false
       msg: 'Failed to connect to the host via ssh: Host key verification failed.'
       unreachable: true
   ```
   Ansible ne décide pas à ta place : il relaie la question d'OpenSSH (une seule à la fois, même avec plusieurs hôtes) ou échoue en mode non interactif. Pour accueillir une nouvelle VM **sans valider à l'aveugle**, il faut comparer l'empreinte reçue par le réseau à une empreinte obtenue par un **autre canal** :
   - par l'agent QEMU, depuis `pve01` : `qm guest exec <VMID> -- ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` ;
   - dans la console série au premier démarrage (cloud-init y affiche les empreintes des clés générées) ou dans `qm terminal` ;
   puis `ssh-keyscan -t ed25519 <IP>`, comparaison, et ajout à `known_hosts`. Au module 06, des **certificats d'hôte SSH** signés par la CA rendront cette étape inutile (une seule ligne `@cert-authority` dans `known_hosts`).

7. MR, fusion.

**Explications**

- **Mêmes groupes, même niveau.** L'inventaire dynamique de E13 produit des groupes « plats » (un par étiquette Proxmox), tous enfants de `all`. Si l'inventaire statique imbriquait `role_*` sous `socle`, la précédence des `group_vars` ne serait pas la même dans les deux cas (un groupe enfant l'emporte sur son parent, deux groupes de même niveau se départagent par ordre alphabétique, E06) : la bascule de E13 changerait silencieusement des valeurs.
- **L'adresse IP, pas le nom.** `ansible_host` en adresse : Ansible marche quand `dns01` est en panne, c'est-à-dire quand on en a le plus besoin (pour le réparer). Le nom d'inventaire (`dns01`) reste lisible.
- **Ce qui dépend de la source, ce qui n'en dépend pas.** `ansible_host` vient de la source (fichier ou Proxmox) ; le compte et la connexion locale de `adm01` sont des choix de l'équipe : dans `group_vars/` et `host_vars/`, chargés pour l'un comme pour l'autre.

**Alternatives**

- **Format INI** : plus court, mais les variables y sont des chaînes devinées (`ansible_port=22` est converti, une liste ne s'écrit pas) ; YAML est explicite et se valide.
- **Alias SSH dans l'inventaire** (`ansible_host: gw01`, utilisant `~/.ssh/config`) : réutilise la configuration de `adm01`, mais lie l'inventaire à un fichier personnel que la CI et Semaphore n'ont pas.
- **Plusieurs fichiers d'inventaire** dans un dossier (`inventories/lab/` entier comme source) : pratique pour combiner statique et dynamique ; à éviter ici tant qu'on veut **basculer** de l'un à l'autre (les deux se mélangeraient).

**Pièges classiques**

- Les clés d'hôte connues **sous l'alias** seulement (si l'alias utilise `HostKeyAlias`), pas sous l'adresse : Ansible pose la question pour chaque hôte.
- L'agent SSH non chargé (nouvelle session, `tmux` sans `SSH_AUTH_SOCK`) : `UNREACHABLE` avec « Permission denied (publickey) » alors que `ssh dns01` marchait dans un autre terminal.
- `ansible_connection: local` sans `ansible_host` cohérent : sans conséquence pour la connexion, mais `ms_passerelle` (E06) en dépend.
- Déclarer les variables d'un hôte à deux endroits de `hosts.yml` (sous `socle` et sous `role_routeur`) : la dernière lue gagne, et la relecture devient un jeu de piste.
- `host_key_checking = False` « pour aller plus vite » : la première attaque de l'homme du milieu passe sans bruit, et l'habitude se propage dans la CI.

**En production chez MédiSphère**

- L'inventaire vient de la source de vérité (Proxmox en E13, puis NetBox au module 06) ; l'inventaire statique ne sert plus qu'au secours, documenté dans le runbook.
- Clés d'hôte signées par une autorité SSH (step-ca, module 06) : plus aucune question au premier contact, et une révocation possible.
- Un inventaire par environnement (`inventories/lab`, `inventories/preprod`, `inventories/prod`) avec les mêmes groupes : le code est commun, seules les données changent.

---

### M04-E04 — Commandes ad hoc, modules et facts

**Solution**

Toutes les commandes se lancent depuis `~/src/ansible`. Pour alléger, on active le venv une fois (`source .venv/bin/activate`) ; `uv run …` revient au même.

1. **Documentation.**
   ```
   (ansible) admin@adm01:~/src/ansible$ ansible-doc -l | wc -l
   (ansible) admin@adm01:~/src/ansible$ ansible-doc -l ansible.builtin | wc -l
   (ansible) admin@adm01:~/src/ansible$ ansible-doc -s ansible.builtin.stat
   (ansible) admin@adm01:~/src/ansible$ ansible-doc -t callback -l
   ```
   `ansible-doc -l` ne liste que les modules **installés** : ceux d'`ansible.builtin` (environ 70) et ceux des collections du projet (`community.general` en apporte plusieurs centaines). Les « milliers de modules » d'Ansible sont répartis dans des centaines de collections, qu'on n'installe que si on en a besoin. `-s` affiche un squelette de tâche avec tous les paramètres ; `-t` choisit le **type** de plugin (`callback`, `connection`, `inventory`, `filter`, `lookup`…) : les modules ne sont qu'un type de plugin parmi d'autres.

2. **`command` contre `shell`.**
   ```
   (ansible) admin@adm01:~/src/ansible$ ansible socle -m ansible.builtin.command -a 'df -h / | tail -1'
   dns01 | FAILED | rc=1 >>
   df: '|': No such file or directory
   df: tail: No such file or directory
   df: -1: No such file or directory
   …
   (ansible) admin@adm01:~/src/ansible$ ansible socle -m ansible.builtin.shell -a 'df -h / | tail -1'
   dns01 | CHANGED | rc=0 >>
   /dev/sda1        19G  2.1G   16G  12% /
   ```
   `command` passe `|`, `tail` et `-1` comme arguments à `df` ; `shell` confie la ligne à `/bin/sh`. Les deux annoncent `CHANGED` : ils ne savent pas si la commande a modifié quelque chose.
   `-o` affiche une ligne par hôte, mais il est **déprécié** (option et callback `oneline` retirés en 2.23, avertissement depuis 2.19). Pour un script, la sortie JSON :
   ```
   (ansible) admin@adm01:~/src/ansible$ ANSIBLE_LOAD_CALLBACK_PLUGINS=1 ANSIBLE_STDOUT_CALLBACK=ansible.posix.json \
       ansible socle -m ansible.builtin.command -a uptime \
       | jq -r '.plays[0].tasks[0].hosts | to_entries[] | "\(.key)\t\(.value.stdout)"'
   adm01	 10:42:11 up 12 days,  2:03,  2 users,  load average: 0.08, 0.05, 0.01
   dns01	 10:42:11 up 12 days,  2:01,  0 users,  load average: 0.00, 0.00, 0.00
   …
   ```
   `ansible-playbook` charge toujours les callbacks configurés ; la commande `ansible` (ad hoc), par défaut, n'utilise que l'affichage minimal et ignore `ANSIBLE_STDOUT_CALLBACK` : `ANSIBLE_LOAD_CALLBACK_PLUGINS=1` (réglage `bin_ansible_callbacks`) lève cette restriction.

3. **Élévation.**
   ```
   (ansible) admin@adm01:~/src/ansible$ ansible dns01 -m ansible.builtin.command -a 'ls /root'
   dns01 | FAILED | rc=2 >>
   ls: cannot open directory '/root': Permission denied
   (ansible) admin@adm01:~/src/ansible$ ansible dns01 -b -m ansible.builtin.command -a 'ls /root'
   dns01 | CHANGED | rc=0 >>
   ```
   Le second réussit grâce à la règle `sudo` sans mot de passe posée par cloud-init pour `admin` (`/etc/sudoers.d/90-cloud-init-users` sur les VMs issues du template ; `/etc/sudoers.d/90-workbook` sur `gw01`, M00-E10/E15).

4. **Redémarrage attendu.**
   ```
   (ansible) admin@adm01:~/src/ansible$ ansible socle -m ansible.builtin.stat -a 'path=/run/reboot-required'
   ```
   Lire `stat.exists` dans la sortie (`true` sur les hôtes qui attendent un redémarrage). `stat` est un module de **lecture** : il ne compte jamais « changed », il fonctionne en simulation, et son résultat est structuré ; `command: test -f` échouerait sur les hôtes sans le fichier (c'est l'étape 9) et compterait « changed » sur les autres.

5. **Faits.**
   ```
   (ansible) admin@adm01:~/src/ansible$ ansible dns01 -m ansible.builtin.setup -a 'filter=ansible_distribution*'
   (ansible) admin@adm01:~/src/ansible$ time ansible socle -m ansible.builtin.setup \
       -a 'gather_subset=!all,!min,distribution,kernel,hardware' --tree ~/m04/e04/facts >/dev/null
   real	0m4,1s
   (ansible) admin@adm01:~/src/ansible$ time ansible socle -m ansible.builtin.setup >/dev/null
   real	0m6,8s
   ```
   (Durées indicatives ; l'écart grandit avec le nombre de montages et d'interfaces.) Chaque fichier de `facts/` est le résultat JSON brut du module pour un hôte : `{"ansible_facts": {"ansible_distribution": "Debian", …}, "changed": false}`. `!all,!min` retire tout, y compris le socle minimal ; on ajoute ensuite seulement ce qu'on veut.

6. **Le relevé** : filtre [`fichiers/M04-E04/capacite.jq`](fichiers/M04-E04/capacite.jq).
   ```
   admin@adm01:~/m04/e04$ { echo 'hote,distribution,version,noyau,vcpu,memoire_mo,disque_libre_go,uptime_jours'
   >   jq -r -f ~/DevOpsPrivateCloud/modules/04-ansible/corrige/fichiers/M04-E04/capacite.jq facts/*; } > capacite.csv
   admin@adm01:~/m04/e04$ column -s, -t capacite.csv
   hote        distribution  version  noyau             vcpu  memoire_mo  disque_libre_go  uptime_jours
   "adm01"     "Debian"      "13.1"   "6.12.48+deb13-…"  2     3911        14               12
   "dns01"     "Debian"      "13.1"   "6.12.48+deb13-…"  1     1949        16               12
   …
   ```
   Dans les fichiers du module `setup`, les faits **gardent** le préfixe `ansible_` (`ansible_memtotal_mb`). Dans un playbook avec la configuration du projet, on les lit par `ansible_facts['memtotal_mb']`, **sans** préfixe : le dictionnaire `ansible_facts` retire le préfixe, et `inject_facts_as_vars = False` supprime les variables `ansible_memtotal_mb` de premier niveau.

7. **Idempotence observée.**
   ```
   (ansible) admin@adm01:~/src/ansible$ ansible dns01 -b -m ansible.builtin.file -a 'path=/tmp/m04-e04 state=directory'
   dns01 | CHANGED => …        (1re fois)
   dns01 | SUCCESS => …        (2e fois : déjà dans l'état demandé)
   (ansible) admin@adm01:~/src/ansible$ ansible dns01 -b -m ansible.builtin.file -a 'path=/tmp/m04-e04/marqueur state=touch'
   dns01 | CHANGED => …        (1re fois)
   dns01 | CHANGED => …        (2e fois : dates mises à jour)
   (ansible) admin@adm01:~/src/ansible$ ansible dns01 -b -m ansible.builtin.file \
       -a 'path=/tmp/m04-e04/marqueur state=touch access_time=preserve modification_time=preserve'
   dns01 | SUCCESS => …
   (ansible) admin@adm01:~/src/ansible$ ansible dns01 -b -m ansible.builtin.file -a 'path=/tmp/m04-e04 state=absent'
   ```
   `state=directory` décrit un **état** (le dossier existe) ; `state=touch` décrit une **action** (« mets à jour les dates »), donc il change à chaque fois, sauf si on lui demande de préserver les dates d'un fichier existant.

8. **Parallélisme.** Avec `forks = 10`, les cinq `sleep 3` tournent en même temps : environ 3,5 s au total, et les hôtes s'affichent **dans l'ordre où ils finissent**. Avec `-f 1`, ils s'enchaînent : environ 15 s, dans l'ordre de l'inventaire. Dans un playbook, la stratégie par défaut (`linear`) attend que tous les hôtes aient fini une tâche avant de passer à la suivante : le plus lent impose son rythme.

9. **Échec.** Quatre hôtes sont `FAILED | rc=1`, `gw01` est `CHANGED | rc=0`. Ce n'est pas une erreur d'Ansible, c'est la **réponse** à la question posée : le fichier n'existe pas ailleurs. La commande `ansible` sort avec le code **2** (au moins un hôte en échec ; 4 s'il y a des hôtes injoignables, les deux bits se combinent). Un script qui l'appellerait en `set -e` s'arrêterait : pour une question de ce genre, un module de lecture (`stat`) et l'analyse de son résultat sont la bonne approche.

10. **Réponse à Nadia** (exemple de `notes.md`) : hôte le moins pourvu en place libre, hôtes qui attendent un redémarrage (`stat` de l'étape 4), et la fiche « astreinte » : `ansible socle -m ansible.builtin.setup -a 'filter=…'`, `ansible <hôte> -b -m ansible.builtin.command -a '…'`, sortie JSON + `jq` pour les relevés.

**Explications**

- **Ad hoc ou playbook.** L'ad hoc sert à **interroger** et aux gestes ponctuels ; tout ce qui modifie durablement un hôte va dans un playbook versionné. Une commande ad hoc qui change quelque chose ne laisse pas de trace dans le dépôt : c'est de la dérive créée à la main, juste plus vite.
- **Un module de lecture rapporte `changed: false`** ; `command` et `shell` rapportent `changed: true` par défaut (`changed_when` permet de corriger dans un playbook).
- **Les faits ont un coût**, proportionnel à ce qu'on collecte : `gather_subset` et `filter` (qui ne fait que filtrer l'affichage : la collecte a quand même lieu pour le sous-ensemble demandé) ne sont pas la même chose.

**Alternatives**

- `ansible-console` : une console interactive qui garde l'inventaire et le motif entre deux commandes.
- Le cache de faits (E26) ou l'inventaire dynamique (E13) pour les informations qui viennent de Proxmox (vCPU, mémoire allouée) sans se connecter aux hôtes.
- `medictl inventaire` (M02) pour la vue « hyperviseur » ; les faits donnent la vue « système invité » : les deux se complètent (mémoire allouée et mémoire vue par le noyau).

**Pièges classiques**

- `gather_subset=!all` entre guillemets doubles dans Bash : `!all` est interprété par l'historique. Toujours des apostrophes.
- Confondre `filter` (filtre l'affichage) et `gather_subset` (limite la collecte).
- Lancer une commande ad hoc qui modifie un hôte (`-m apt -a 'name=…'`) « juste pour tester » : c'est exactement la dérive que le module combat.
- Compter sur `-o` dans un script : déprécié, retiré en 2.23.

**En production chez MédiSphère**

- Les relevés de capacité viennent de la supervision (module 21, exporters) et de NetBox (module 06) ; l'ad hoc reste l'outil du diagnostic.
- Une liste blanche de commandes ad hoc « sûres » figure dans le guide d'astreinte (RB-040, E22), avec la sortie attendue.

---

### M04-E05 — Premier playbook idempotent

**Solution**

1. **Analyse du playbook de Lucas** (second passage, tâche par tâche) :

   | Tâche | État après le 2e passage | Ce qu'Ansible affiche |
   |---|---|---|
   | `sudo apt-get update` | index rafraîchi (inutilement) | `changed` |
   | `sudo apt-get install -y …` | paquets présents, **éventuellement mis à jour** | `changed` |
   | `sudo apt-get remove …` + `ignore_errors` | rien (déjà absents) ; une vraie erreur serait masquée | `changed` (ou `failed` puis `...ignoring`) |
   | `echo … \| sudo tee -a /etc/bash.bashrc` | **une ligne de plus** à chaque passage | `changed` |
   | `command: dpkg -l tcpdump` | rien | `changed` |
   | `debug` | — | message |

   Défauts : play sans nom et `hosts: all` (vise aussi des hôtes futurs hors socle) ; `sudo` dans les commandes au lieu de `become` ; `shell` et `command` au lieu de modules (pas d'idempotence, toujours `changed`, pas de simulation possible : en `--check`, toutes ces tâches seraient **sautées**) ; `ignore_errors: yes` qui masque les vraies erreurs (et booléen YAML non canonique) ; ajout d'une ligne à chaque passage ; `apt-get update` séparé ; une tâche de vérification inutile (le module le sait) qui de plus échoue si le paquet manque, au lieu de rapporter ; tâches sans nom ; modules sans FQCN ; tube sans `pipefail`. ansible-lint 26.9 en relève 26 :
   ```
   name[play]: All plays should be named.
   command-instead-of-shell: Use shell only when shell functionality is required.
   fqcn[action-core]: Use FQCN for builtin module actions (shell).
   name[missing]: All tasks should be named.
   no-changed-when: Commands should not change things if nothing needs doing.
   ignore-errors: Use failed_when and specify error conditions instead of using ignore_errors.
   yaml[truthy]: Truthy value should be one of [false, true]
   risky-shell-pipe: Shells that use pipes should set the pipefail option.
   …
   ```
   ansible-lint ne voit pas tout : il ne dit pas que la ligne s'ajoute à chaque passage. La relecture humaine reste nécessaire.

2. **Playbook** : [`fichiers/M04-E05/ansible/playbooks/trousse-diagnostic.yml`](fichiers/M04-E05/ansible/playbooks/trousse-diagnostic.yml). Trois tâches : installer (avec `update_cache` et `cache_valid_time`), retirer, `lineinfile` avec `regexp`. `gather_facts: false` : aucune tâche n'utilise de fait.

3. **Contrôles préalables.**
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/trousse-diagnostic.yml --list-hosts --list-tasks

   playbook: playbooks/trousse-diagnostic.yml

     play #1 (socle): Trousse de diagnostic sur le socle	TAGS: []
       pattern: ['socle']
       hosts (5):
         gw01
         adm01
         dns01
         git01
         runner01
       tasks:
         Installer les outils de diagnostic	TAGS: []
         Retirer les clients de protocoles en clair	TAGS: []
         Horodater l'historique bash (traçabilité des interventions)	TAGS: []
   ```

4. **Déploiement progressif.**
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/trousse-diagnostic.yml --check --diff --limit runner01
   TASK [Installer les outils de diagnostic] *************************************
   The following additional packages will be installed:
     …
   The following NEW packages will be installed:
     htop lsof mtr-tiny strace tcpdump
   changed: [runner01]
   TASK [Horodater l'historique bash (traçabilité des interventions)] *************
   --- before: /etc/bash.bashrc (content)
   +++ after: /etc/bash.bashrc (content)
   @@ -55,3 +55,4 @@
   +export HISTTIMEFORMAT='%F %T '
   changed: [runner01]
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/trousse-diagnostic.yml --limit runner01
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/trousse-diagnostic.yml --check --diff
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/trousse-diagnostic.yml
   ```
   **`python3-apt` en simulation.** Si un hôte n'a pas `python3-apt` (les bindings Python d'APT, dont le module `apt` a besoin), le module sait l'installer lui-même… en exécution réelle seulement : en `--check`, il refuse (« python3-apt must be installed to use check mode. If run normally this module can auto-install it… »), puisqu'installer serait une modification. Solution : une exécution réelle sur cet hôte (après lecture du `--check` des autres), ou installer `python3-apt` au préalable (une tâche `apt` dédiée en tête de playbook, qui deviendra une tâche du rôle `base`).

5. **Second passage** :
   ```
   PLAY RECAP ***********************************************************************
   adm01      : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
   dns01      : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
   git01      : ok=3    changed=0    …
   gw01       : ok=3    changed=0    …
   runner01   : ok=3    changed=0    …
   ```
   Causes classiques d'un `changed` persistant : `apt` avec `update_cache: true` **sans** `cache_valid_time` dans une tâche **sans paquet** (toujours `changed`), `lineinfile` sans `regexp` alors qu'une ligne différente existe, `state: latest` (qui change dès qu'une mise à jour sort : on veut `present` pour une trousse).

6. **Expériences.**
   - Ligne modifiée à la main (`export HISTTIMEFORMAT='%d/%m %H:%M '`) : `--check --diff` propose de **remplacer** la ligne (la `regexp` la retrouve) ; Ansible ramène l'état décrit.
   - Ligne **en double** : `lineinfile` avec `regexp` ne modifie que la **dernière** ligne correspondante et laisse les autres ; si les deux sont identiques à `line`, il ne fait rien (`ok`). La dérive « deux lignes » n'est ni détectée ni corrigée. Pour garantir l'unicité : supprimer d'abord toutes les lignes correspondantes puis ajouter la bonne (deux tâches, plus jamais idempotentes au sens de l'affichage), ou mieux, ne pas partager le fichier : un fichier **dédié** (`/etc/profile.d/medisphere-historique.sh` par `copy`) dont Ansible possède tout le contenu. Remise en état sur `runner01` : `sed -i '0,/^export HISTTIMEFORMAT=/{//d}' /etc/bash.bashrc` (supprime la première occurrence), puis vérification `grep -c`.

7. MR, fusion.

**Explications**

- **Un état, pas une action.** `apt: name=… state=present` dit « ces paquets doivent être installés » : le module compare avec la base dpkg et ne fait que ce qui manque. C'est ce qui rend la simulation possible (le module sait **prédire**) et l'affichage honnête (`changed` seulement s'il a agi).
- **Une seule transaction APT.** Une liste dans `name` installe tout en un appel : plus rapide et cohérent (pas d'état à moitié installé si un paquet manque dans les dépôts).
- **`cache_valid_time`.** Évite de rafraîchir l'index APT à chaque passage (lent, et dépendant du réseau) tout en garantissant un index récent pour une installation.
- **`--limit` d'abord.** Le premier passage d'un playbook neuf est celui où l'on découvre les surprises (paquet renommé, `python3-apt` absent) : sur un hôte, pas sur cinq.

**Alternatives**

- `ansible.builtin.package` (générique) au lieu d'`apt` : utile pour un rôle multi-distributions (Rocky Linux), mais sans `cache_valid_time` ni les options propres à APT.
- `blockinfile` : gère un **bloc** délimité par des marqueurs dans un fichier partagé ; plus robuste que `lineinfile` pour plusieurs lignes.
- Un fichier dédié dans un dossier `*.d` (étape 6) : la meilleure option quand le logiciel le permet ; Ansible possède le fichier entier.

**Pièges classiques**

- `state: latest` dans une trousse : chaque mise à jour publiée rend le playbook « changed » et met à jour des paquets sans fenêtre de maintenance.
- Oublier `become: true` : `apt` échoue (« Failed to lock apt for exclusive operation ») ou ne voit pas les fichiers protégés.
- `hosts: all` dans un playbook du socle : le jour où l'inventaire contient des VMs d'exercice ou des instances Molecule, elles reçoivent aussi la configuration.
- Croire qu'un `--check` vert garantit l'exécution réelle : le module ne simule que ce qu'il sait prédire (une tâche qui dépend du résultat d'une autre peut différer).

**En production chez MédiSphère**

- La trousse devient une variable du rôle `base` (E10), testée par Molecule (E24) et appliquée par la CI (E27) ; personne n'installe plus d'outil à la main.
- L'historique horodaté ne suffit pas pour l'audit (l'utilisateur peut l'effacer) : journalisation des commandes privilégiées par `sudo` (`log_output`, `logfile`) ou `auditd`, centralisée (module 22).

---

### M04-E06 — Variables et précédence

**Solution**

*Partie A — bac à sable (résultats obtenus avec ansible-core 2.21.5 et 2.19.14)*

1. **État initial** :

   | Hôte | `couleur` | Pourquoi |
   |---|---|---|
   | `alpha` | `host_vars/alpha` | `host_vars/` (fichier voisin de l'inventaire) l'emporte sur tout l'inventaire |
   | `beta` | `inventaire : hôte beta` | variable d'**hôte** dans le fichier d'inventaire, au-dessus de toutes les variables de **groupe**, même celles de `group_vars/` |
   | `gamma` | `group_vars/role_web` | `group_vars/role_web.yml` (catégorie « inventory group_vars/* ») bat les variables de groupe écrites dans le fichier d'inventaire et `group_vars/all` |

2. **Manipulations** :

   | Essai | `alpha` | `gamma` | Explication |
   |---|---|---|---|
   | a. sans `host_vars/alpha` | `group_vars/socle` | `group_vars/role_web` | `alpha` est dans `socle` et `role_web`, deux groupes de **même niveau** : ils sont fusionnés par ordre **alphabétique**, `role_web` puis `socle` ; le dernier chargé gagne |
   | b. + sans `group_vars/socle` | `group_vars/role_web` | `group_vars/role_web` | il reste pour `socle` la variable du **fichier d'inventaire** (catégorie plus basse) : `group_vars/role_web` gagne, quel que soit l'ordre des groupes |
   | c. + sans `group_vars/role_web` | `group_vars/all` | `group_vars/all` | surprise : `group_vars/all.yml` (« inventory group_vars/all ») est **au-dessus** des variables de groupe du fichier d'inventaire, même de `socle`, groupe plus précis |
   | d. + sans `group_vars/all` | `inventaire : groupe socle` | `inventaire : all` | à l'intérieur du fichier d'inventaire, l'enfant (`socle`) bat le parent (`all`) |
   | e. `ansible_group_priority: 10` sur `role_web` dans l'inventaire | `group_vars/role_web` | — | la priorité remplace l'ordre alphabétique entre groupes de même niveau ; déplacée dans `group_vars/role_web.yml`, elle est **sans effet** (`group_vars/socle` regagne) : ce réglage n'est lu que dans la source d'inventaire |

   `beta` reste `inventaire : hôte beta` dans tous les essais.

3. **Playbook** (`alpha` ; `beta` et `gamma` donnent la même chose) :

   | Tâche | Normal | `-e couleur=extra` | Avec `roles/demo/vars/main.yml` |
   |---|---|---|---|
   | dans le rôle `demo` | `play : vars` | `extra` | `rôle demo : vars` |
   | tâche du play | `play : vars` | `extra` | `rôle demo : vars` |
   | tâche avec ses `vars` | `tâche : vars` | `extra` | `tâche : vars` |
   | après `set_fact` | `set_fact` | `extra` | `set_fact` |

   Ce qu'il faut retenir : les variables de **play** battent `host_vars` (et à plus forte raison les `defaults` du rôle) ; les `vars/` d'un rôle battent les variables de play **et restent visibles** pour les tâches du play exécutées après le rôle (elles ne sont pas privées au rôle, sauf `DEFAULT_PRIVATE_ROLE_VARS`) ; `set_fact` bat tout sauf `-e` ; `-e` gagne toujours, même contre `set_fact`.

4. **Ordre observé** (du plus faible au plus fort, version courte) : `defaults` de rôle < variables de groupe du fichier d'inventaire (enfant > parent) < `group_vars/all` < `group_vars/<groupe>` (enfant > parent, puis alphabétique, ou `ansible_group_priority`) < variables d'hôte du fichier d'inventaire < `host_vars/` < faits < `vars` de play < `vars/` de rôle < `vars` de bloc et de tâche < `include_vars` < `set_fact` et `register` < paramètres de rôle < `-e`. La liste officielle complète compte 22 niveaux (page *Using variables*).

*Partie B — le projet* : fichiers complets dans [`fichiers/M04-E06/ansible/`](fichiers/M04-E06/ansible/).

5. **Le piège des `vars:` de play.** Tant que le playbook garde `vars: trousse_paquets_role: …` (ou toute liste de la trousse), `group_vars/role_routeur/` n'a aucun effet : les variables de play sont au-dessus des `group_vars`. Le `--check --diff --limit gw01` n'annonce donc pas `conntrack`. Une fois les `vars:` retirées, `conntrack` et `ethtool` apparaissent pour `gw01` seulement.

6. **Variables du site** ([`group_vars/all/main.yml`](fichiers/M04-E06/ansible/inventories/lab/group_vars/all/main.yml), [`host_vars/gw01/main.yml`](fichiers/M04-E06/ansible/inventories/lab/host_vars/gw01/main.yml)) :
   ```yaml
   ms_passerelle: "{{ (ansible_host.split('.')[:3] + ['1']) | join('.') }}"
   ms_serveurs_ntp:
     - "{{ ms_passerelle }}"
   ```
   et pour `gw01` : `ms_serveurs_ntp: [2.debian.pool.ntp.org]` (la source Internet de la configuration Debian, que `gw01` utilise depuis M00-E31).

7. **Valeur brute et valeur évaluée.**
   ```
   admin@adm01:~/src/ansible$ uv run ansible-inventory --host dns01 | jq '.ms_passerelle, .ms_serveurs_ntp'
   "{{ (ansible_host.split('.')[:3] + ['1']) | join('.') }}"
   [
     "{{ ms_passerelle }}"
   ]
   admin@adm01:~/src/ansible$ uv run ansible dns01 -m ansible.builtin.debug -a 'var=ms_serveurs_ntp'
   dns01 | SUCCESS =>
       ms_serveurs_ntp:
       - 10.10.20.1
   ```
   `ansible-inventory` montre les variables **telles qu'elles sont écrites** (il ne les évalue pas) ; `debug` les évalue **pour l'hôte**, avec toute la précédence : c'est lui qu'il faut utiliser pour diagnostiquer. `debug` est une action exécutée sur le nœud de contrôle : il ne se connecte pas à `dns01` (essaie avec un hôte éteint : il répond quand même).

8. **Rangement.**
   - Pas de `group_vars/socle/` concurrent des `role_*` : `socle` et `role_*` sont au même niveau, et `socle` vient **après** `role_*` dans l'ordre alphabétique : une valeur de `group_vars/socle` écraserait silencieusement la valeur spécifique d'un rôle (essai a.). Les valeurs communes vont dans `group_vars/all`, le niveau le plus bas.
   - Pas de valeur qui dépend de l'hôte dans `vars:` de play : elle écrase `group_vars` et `host_vars` pour **tous** les hôtes du play, et on ne peut plus la spécialiser dans l'inventaire (essai du point 5).

9. Application sur `gw01`, second passage à `changed=0`, MR.

**Explications**

- **Deux mécanismes à ne pas confondre.** La *précédence* classe les **catégories** de sources (22 niveaux) ; la *fusion des groupes* départage, **à l'intérieur** d'une même catégorie, les groupes d'un hôte : profondeur d'abord (enfant > parent), puis ordre alphabétique, ou `ansible_group_priority`. La catégorie l'emporte toujours (essai c. : `group_vars/all` bat le groupe `socle` du fichier d'inventaire).
- **Évaluation paresseuse.** `ms_passerelle` contient une expression, évaluée au moment où on la lit, avec les variables de l'hôte concerné. Écrite une fois dans `group_vars/all`, elle donne la bonne valeur pour chaque hôte, y compris les hôtes futurs. Depuis 2.19, cette évaluation est faite à la demande (*lazy templating*) et mise en cache pendant l'opération.
- **`inventory_hostname`, `ansible_host`, `group_names`** sont des variables « magiques » de l'inventaire, disponibles sans collecte de faits : idéales pour des valeurs calculées.

**Alternatives**

- Le filtre `ansible.utils.ipaddr` / `ansible.utils.ipmath` calcule proprement une passerelle à partir d'un préfixe (`10.10.20.10/24` → `10.10.20.1`) ; il demande la collection `ansible.utils` et la bibliothèque Python `netaddr`. Ici, le plan d'adressage (`.1` = passerelle) rend le calcul simple ; avec NetBox (module 06), la passerelle viendra de la source de vérité.
- Écrire la passerelle dans `host_vars/` de chaque hôte : explicite, mais cinq fois la même règle, et un hôte nouveau sans la variable échoue.

**Pièges classiques**

- Chercher la valeur d'une variable avec `ansible-inventory --host` et y voir une expression non évaluée ; ou avec un `debug` dans un **autre** play, qui n'a pas les mêmes `vars:`.
- `-e liste=[a,b]` : la forme `clé=valeur` donne toujours une **chaîne**. Pour une liste, `-e '{"liste": ["a", "b"]}'` ou `-e @fichier.yml`.
- Variable définie dans deux groupes de même niveau : le résultat dépend de l'ordre alphabétique des **noms** de groupes ; renommer un groupe change la valeur.
- `ansible_group_priority` dans `group_vars/` : sans effet, sans avertissement.
- Les `vars/` d'un rôle qui « fuient » dans le play : une variable de rôle nommée sans préfixe (`port`, `paquets`) écrase celle d'un autre rôle exécuté plus tard. D'où la convention de préfixe par rôle.

**En production chez MédiSphère**

- Règles de rangement écrites dans `CONTRIBUTING.md` et vérifiées en revue ; préfixes de variables imposés par ansible-lint (`var-naming[no-role-prefix]`, E20).
- Le bac à sable de précédence est conservé dans le dépôt (`docs/precedence/`) : un nouvel arrivant le rejoue en dix minutes.
- Les données propres à un environnement (lab, préproduction, production) vivent dans l'inventaire de cet environnement, jamais dans le code.

---

### M04-E07 — Templates Jinja2

**Solution**

Fichiers complets : [`fichiers/M04-E07/ansible/`](fichiers/M04-E07/ansible/) (`playbooks/identite-hotes.yml`, `playbooks/templates/motd.j2`, `playbooks/templates/medisphere.fact.j2`, et les variables ajoutées à `group_vars/all/main.yml`).

1. **Rendu en simulation.** La commande ad hoc se connecte bien aux hôtes : pour afficher la différence, le module `template` lit le fichier en place (`/etc/motd` est lisible par tous, donc pas besoin de `-b`). Mais elle échoue sur la ligne « Système » : en ad hoc, **aucun fait n'est collecté**, `ansible_facts` est vide (« object of type 'dict' has no attribute 'distribution' »). Solutions : un petit playbook (collecte de faits, puis `template` en `--check --diff`), ou simplement le playbook final lancé en `--check --diff --limit gw01,git01`.

2. **`ms_role`** :
   ```yaml
   ms_role: "{{ group_names | select('match', '^role_') | map('regex_replace', '^role_', '') | first | default('aucun') }}"
   ```
   `group_names` vaut par exemple `['role_gitlab', 'socle']` ; `select('match', '^role_')` garde `['role_gitlab']` ; `map('regex_replace', …)` donne `['gitlab']` ; `first` prend le premier, et sur une liste vide renvoie une valeur indéfinie, que `default('aucun')` remplace.
   ```
   admin@adm01:~/src/ansible$ uv run ansible socle -m ansible.builtin.debug -a 'var=ms_role'
   gw01 | SUCCESS =>
       ms_role: routeur
   adm01 | SUCCESS =>
       ms_role: bastion
   …
   ```

3. **Espaces.** Le module `template` active par défaut `trim_blocks` (la fin de ligne qui suit une balise `{% … %}` est supprimée) mais **pas** `lstrip_blocks` (les espaces **avant** une balise restent). Une balise indentée laisse donc ses espaces sur la ligne suivante. Deux styles cohérents : balises en colonne 0 (choix du corrigé, le plus lisible dans un fichier texte), ou `#jinja2: lstrip_blocks: True` en première ligne du template (option propre au module `template`), ou les tirets `{%- … -%}` au cas par cas.

4. **En-tête.** `ansible-config list` indique que `DEFAULT_MANAGED_STR` (réglage `ansible_managed` d'`ansible.cfg`) est **déprécié**, retrait prévu en 2.23 : « Set the `ansible_managed` variable, or use any custom variable in templates. » Le corrigé définit `ms_gere_par` dans `group_vars/all` et l'affiche avec le filtre `comment`, qui encadre le texte de lignes `#` :
   ```
   #
   # Fichier géré par Ansible (projet plateforme/ansible). Toute modification manuelle sera écrasée au prochain passage.
   #
   ```
   (Le filtre accepte un style : `comment('c')`, `comment('xml')`… pour d'autres syntaxes de commentaire.)

5. **Fait local.** Écrire le JSON à la main (`"role": "{{ ms_role }}",`) casse dès qu'une valeur contient un guillemet ou une barre oblique inverse, et une virgule de trop rend le fichier illisible **sans erreur visible** (setup ignore un fait local invalide avec un simple avertissement). On construit un dictionnaire Jinja2 et on le sérialise avec `to_nice_json`, qui échappe correctement. Mode `0644` : un fichier `.fact` **exécutable** est exécuté par `setup` (sa sortie doit être du JSON) ; non exécutable, il est lu comme du JSON (ou de l'INI). Un `0755` par habitude transformerait ce JSON en « programme » qui échoue.

6. **Playbook.** Les faits sont collectés au début du play, **avant** que le fichier existe. On relit uniquement les faits locaux, ce qui est rapide :
   ```yaml
   - name: Relire les faits locaux
     ansible.builtin.setup:
       filter: ansible_local
   ```
   Le contrôle `assert` est conditionné par `when: not ansible_check_mode` : en simulation, le fichier n'est pas écrit, la relecture ne trouverait rien. (Une variante est un *handler* « relire les faits » notifié par la tâche du fait, suivi de `meta: flush_handlers` ; un `when: resultat is changed` marche aussi, mais ansible-lint le signale — règle `no-handler` — et préfère le handler.)

7. **Résultat sur `git01`** :
   ```
   #
   # Fichier géré par Ansible (projet plateforme/ansible). Toute modification manuelle sera écrasée au prochain passage.
   #

     MédiSphère — site PAR1 — environnement lab

     Hôte    : git01.par1.medisphere.internal (10.10.20.12)
     Rôle    : gitlab
     Système : Debian 13

     Accès réservé aux personnes autorisées. Toute action est journalisée.
     Astreinte : astreinte Plateforme (Nadia Roussel) — runbooks : plateforme/medisphere, docs/socle/runbooks/
     Runbooks de ce rôle :
       - RB-010 Restaurer GitLab
       - RB-011 Mettre à jour GitLab
       - RB-012 Diagnostiquer la forge
       - RB-013 La forge est en panne
   ```
   Sur `gw01`, l'avertissement du routeur remplace la liste de runbooks.

8. **Date dans le template.** Avec `{{ now() }}`, le fichier rendu diffère à chaque passage : `changed` partout, à chaque fois. Le playbook n'est plus idempotent, la détection de dérive (E29) crie en permanence, et plus personne ne regarde ses alertes. Une information qui change (date de dernière application, version du commit) a sa place dans un **journal** ou un fait mis à jour par un mécanisme séparé, pas dans un fichier comparé à chaque passage. Même raisonnement pour `distribution_version` (13.1, 13.2…) : la version **majeure** suffit dans un motd.

9. **Faits locaux.**
   ```
   admin@adm01:~/src/ansible$ uv run ansible git01 -m ansible.builtin.setup -a 'filter=ansible_local'
   git01 | SUCCESS =>
       ansible_facts:
           ansible_local:
               medisphere:
                   environnement: lab
                   gere_par: plateforme/ansible
                   role: gitlab
                   site: par1
   ```
   Dans un playbook : `ansible_facts['ansible_local']['medisphere']['role']`. Attention : contrairement aux autres faits, la clé garde son préfixe **dans** `ansible_facts` (vérifié avec 2.19 et 2.21).

10. MR, fusion.

**Explications**

- **Jinja2 dans Ansible.** Les templates sont rendus **sur le nœud de contrôle**, avec les variables de l'hôte ; seul le résultat est envoyé. Les filtres d'Ansible (`to_nice_json`, `comment`, `regex_replace`…) s'ajoutent à ceux de Jinja2.
- **Un template doit être une fonction pure des variables** : mêmes variables, même fichier. Tout ce qui varie hors des variables (date, hasard, ordre d'un dictionnaire non trié) casse l'idempotence.
- **`is defined` sur une clé de dictionnaire** (`ms_runbooks[ms_role] is defined`) évite une erreur pour les rôles sans runbook : sans ce test, accéder à une clé absente fait échouer le rendu du template.

**Alternatives**

- `copy` avec `content:` pour un fichier très court sans logique.
- Le dossier `/etc/update-motd.d/` (scripts exécutés à la connexion par `pam_motd`) pour une information **dynamique** (charge, mises à jour en attente) : c'est là, et non dans `/etc/motd`, qu'on mettrait une information qui change.
- Un fait local **exécutable** (script) pour une information calculée sur l'hôte à chaque collecte.

**Pièges classiques**

- Un `{% if %}` indenté qui laisse des espaces ou des lignes vides parasites (étape 3).
- `ansible_managed` dans un template avec le réglage par défaut : déprécié en 2.19 ; et, dans d'anciennes versions, il contenait la date et le nom de l'utilisateur, ce qui cassait l'idempotence.
- Écrire `ansible_local.medisphere.role` en supposant que l'hôte a déjà le fait : au premier passage (ou sur un hôte neuf), il n'existe pas encore ; `default()` ou un test `is defined`.
- Fait local en `0755` : exécuté au lieu d'être lu.

**En production chez MédiSphère**

- Le texte légal est validé par la RSSI et le service juridique, versionné comme une variable unique.
- Le fait local `medisphere` sert d'étiquette côté système : un script d'astreinte ou un exporter de supervision (module 21) sait le rôle d'une machine sans interroger l'inventaire.

---

### M04-E08 — Handlers et validation avant rechargement

**Solution**

1. **Configuration actuelle.**
   ```
   admin@adm01:~/src/ansible$ uv run ansible dns01 -b -m ansible.builtin.fetch -a 'src=/etc/chrony/chrony.conf dest=~/m04/e08/'
   admin@adm01:~$ ls ~/m04/e08/dns01/etc/chrony/
   chrony.conf
   ```
   `fetch` range le fichier sous `dest/<hôte>/<chemin complet>` : on peut récupérer le même fichier de dix hôtes sans collision (option `flat: true` pour un seul hôte). Comparé au fichier de Debian 13 (ci-dessous), M00-E31 a commenté la ligne `pool` et ajouté la source dans `/etc/chrony/sources.d/lab.sources`.

2. **Validation à la main.** `man chronyd` : l'option `-p` « affiche la configuration et s'arrête » ; elle ne démarre rien et ne demande pas de droits particuliers ; avec `-f`, elle lit le fichier indiqué.
   ```
   admin@dns01:~$ cp /etc/chrony/chrony.conf /tmp/essai.conf && chronyd -p -f /tmp/essai.conf >/dev/null; echo $?
   0
   admin@dns01:~$ sed -i 's/^makestep/makestp/' /tmp/essai.conf && chronyd -p -f /tmp/essai.conf >/dev/null; echo $?
   2026-10-08T09:14:02Z Fatal error : Invalid directive at line 33 in file /tmp/essai.conf
   1
   admin@dns01:~$ rm /tmp/essai.conf
   ```
   (Si `chronyd` n'est pas dans ton `PATH` d'utilisateur, c'est `/usr/sbin/chronyd`.)

3. **Template** : [`fichiers/M04-E08/ansible/playbooks/templates/chrony.conf.j2`](fichiers/M04-E08/ansible/playbooks/templates/chrony.conf.j2). Directives de Debian conservées : `keyfile`, `driftfile`, `ntsdumpdir`, `logdir`, `maxupdateskew`, `rtcsync`, `makestep 1 3`, `leapseclist`, `confdir`. Retirées : `pool 2.debian.pool.ntp.org` (sources Internet, contraire à PLAN §4.3 bis), `sourcedir /run/chrony-dhcp` (sources apprises par DHCP : les VMs du socle ont des adresses statiques) et `sourcedir /etc/chrony/sources.d` (une source déposée là échapperait à Ansible). Les sources viennent de `ms_serveurs_ntp`.

4. **Playbook** : [`fichiers/M04-E08/ansible/playbooks/chrony-client.yml`](fichiers/M04-E08/ansible/playbooks/chrony-client.yml). Les points clés :
   ```yaml
   - name: Configuration de chrony (validée avant d'être mise en place)
     ansible.builtin.template:
       src: chrony.conf.j2
       dest: /etc/chrony/chrony.conf
       mode: "0644"
       backup: true
       validate: chronyd -p -f %s
     notify: Redémarrer chrony
   …
   - name: Appliquer maintenant les redémarrages en attente
     ansible.builtin.meta: flush_handlers

   - name: Attendre la synchronisation (20 essais espacés de 3 s, correction < 0,1 s)
     ansible.builtin.command: chronyc -n waitsync 20 0.1 0 3
     changed_when: false
     check_mode: false
   ```
   La vérification doit voir **la nouvelle configuration en service** : sans `flush_handlers`, le redémarrage n'aurait lieu qu'à la fin du play, après la vérification. `changed_when: false` : c'est une lecture. `check_mode: false` : elle s'exécute aussi en `--check` (sinon `command` serait sauté), ce qui transforme la simulation en contrôle de santé. `chronyc waitsync N CORRECTION SKEW INTERVALLE` attend que chrony soit synchronisé avec une correction restante inférieure à 0,1 s, au plus 20 fois toutes les 3 s.

5. **Sur `runner01`** :
   ```
   TASK [Configuration de chrony (validée avant d'être mise en place)] ****************
   --- before: /etc/chrony/chrony.conf
   +++ after: /home/admin/.ansible/tmp/…/chrony.conf.j2
   @@ -1,8 +1,17 @@
   +#
   +# Fichier géré par Ansible (projet plateforme/ansible). …
   …
   -# pool 2.debian.pool.ntp.org iburst
   +server 10.10.20.1 iburst
   …
   changed: [runner01]
   TASK [Retirer la source posée à la main (M00-E31), remplacée par le template] ******
   changed: [runner01]
   RUNNING HANDLER [Redémarrer chrony] ************************************************
   changed: [runner01]
   TASK [Attendre la synchronisation (20 essais espacés de 3 s, correction < 0,1 s)] **
   ok: [runner01]
   ```
   Deux tâches ont notifié le handler ; il ne s'exécute **qu'une fois**. Au second passage, rien ne change, rien n'est notifié : le handler ne s'exécute pas, chrony n'est pas redémarré pour rien.

6. **Validation.**
   ```
   TASK [Configuration de chrony (validée avant d'être mise en place)] ****************
   fatal: [runner01]: FAILED! =>
       changed: false
       exit_status: 1
       msg: failed to validate
       stderr: |-
           2026-10-08T09:31:47Z Fatal error : Invalid directive at line 31 in file /home/admin/.ansible/tmp/…/source
   ```
   Le fichier en place n'a pas changé, chrony tourne toujours (`systemctl is-active chrony` → `active`, `chronyc -n tracking` → `Leap status : Normal`). Et le handler ? La tâche a échoué : rien n'a été notifié. Sans `validate`, le mauvais fichier aurait été installé, le handler aurait redémarré chrony… qui ne serait pas reparti : exactement l'incident du ticket.

7. **Handlers et échec.**
   - Premier lancement (source de test + `fail`) : le template change (deux `server`), le handler est notifié, puis `fail` arrête le play pour `runner01` : **les handlers notifiés ne s'exécutent pas**. Le fichier contient deux sources ; chrony tourne avec l'ancienne configuration.
   - Second lancement (sans `fail`, même source de test) : le template est **déjà** dans l'état voulu (`ok`), rien ne notifie le handler. `chrony.conf` déclare deux sources, mais `chronyc -n sources` n'en montre qu'une : la configuration en service ne correspond plus au fichier, et Ansible annonce `changed=0`. C'est une dérive **invisible** à Ansible.
   - En vrai, ce piège arrive dès qu'une tâche postérieure échoue (réseau, dépôt APT indisponible, erreur de frappe dans une autre tâche) ou qu'on interrompt le playbook (Ctrl-C).
   - Protections : `--force-handlers` en ligne de commande, ou `force_handlers: true` au niveau du play (ou dans `ansible.cfg`) : les handlers notifiés s'exécutent même pour un hôte en échec. Complément : un `meta: flush_handlers` juste après les tâches de configuration réduit la fenêtre, et la vérification finale (étape 4) détecte une partie des incohérences.
   - Remise en état : relancer sans la source de test (le template change, le handler redémarre chrony), puis `chronyc -n sources` : une seule source, `^*`.

8. **Les quatre clients** :
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/chrony-client.yml
   …
   PLAY RECAP ***************************************************************************
   adm01      : ok=5    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
   dns01      : ok=5    changed=0    …
   git01      : ok=5    changed=0    …
   runner01   : ok=5    changed=0    …
   admin@dns01:~$ chronyc -n sources
   MS Name/IP address         Stratum Poll Reach LastRx Last sample
   ===============================================================================
   ^* 10.10.20.1                    3   6   377    12    -35us[  -51us] +/-   11ms
   ```
   `gw01` : inchangé (`chronyc -n sources` montre ses sources Internet, `chronyc accheck 10.10.20.10` → `208 Access allowed`).

**Explications**

- **Handlers.** Un handler est une tâche nommée, déclenchée par `notify` quand la tâche qui notifie rapporte `changed`. Il s'exécute une fois, à la fin de la section (ou à un `flush_handlers`), dans l'ordre de **définition** des handlers. C'est ce qui permet « redémarrer seulement si la configuration a changé » sans logique conditionnelle dans les tâches. Le mot-clé `listen` permet de regrouper plusieurs handlers derrière un même nom de notification.
- **`validate`.** Le module rend le fichier dans un fichier temporaire **sur l'hôte**, exécute la commande en remplaçant `%s` par son chemin, et ne remplace le fichier en place que si elle réussit. La validation porte sur le fichier **seul** : si la configuration en inclut d'autres (`confdir`), une erreur dans un fichier inclus serait aussi détectée par `chronyd -p`, mais pas une incompatibilité avec l'état du système (port déjà pris…). D'où la vérification après redémarrage.
- **`backup: true`** garde une copie horodatée (`chrony.conf.12345.2026-10-08@09:31:02~`) : retour arrière en une commande. Ces copies s'accumulent : à surveiller, ou à supprimer par une tâche de ménage.
- **Pourquoi pas `chronyc reload sources` ?** Il ne relit que les fichiers de `sourcedir` ; une modification de `chrony.conf` exige un redémarrage. Le handler redémarre donc le service (quelques secondes sans synchronisation, sans effet sur l'horloge).

**Alternatives**

- Garder `sourcedir /etc/chrony/sources.d` et gérer seulement le fichier de sources (sans redémarrage : handler `chronyc reload sources`, avec `listen`) : plus léger, mais rien n'empêche une autre source d'apparaître à côté, et la validation de `chronyd -p` ne lit pas les `sourcedir`.
- Un fichier dans `/etc/chrony/conf.d/` plutôt que tout `chrony.conf` : on ne touche pas au fichier du paquet (pas de conflit à la mise à jour de chrony), mais les directives du fichier principal (le `pool`) restent actives à moins de le modifier aussi.
- `systemd-timesyncd` : client SNTP simple, sans validation de configuration ni statistiques ; chrony reste la référence (M00-E31).

**Pièges classiques**

- Un handler qui s'appelle comme une tâche, ou dont le nom change sans que les `notify` suivent : « The requested handler 'Redemarrer chrony' was not found » (erreur), ou pire, un handler orphelin jamais appelé.
- `validate` sans `%s` : la commande valide le fichier **en place** (l'ancien), et le nouveau est installé sans contrôle.
- Croire que `validate` protège du redémarrage raté : il protège de la **syntaxe**, pas de la sémantique (une source injoignable est syntaxiquement valide). La vérification finale couvre ce cas.
- Oublier `check_mode: false` sur une commande de lecture : sautée en `--check`, elle ne contrôle rien quand on en a besoin.
- La directive `leapseclist` n'existe qu'à partir de chrony 4.6 : réutiliser ce template sur une distribution plus ancienne échoue… à la validation, ce qui est exactement le but.

**En production chez MédiSphère**

- Trois sources de temps internes (passerelles redondantes, module 07), distribuées par la variable `ms_serveurs_ntp` de l'inventaire ; supervision de l'écart (`chrony_exporter`, module 21).
- `force_handlers: true` posé dans les plays qui redémarrent des services, et règle de revue : « toute tâche qui notifie a un `validate` quand le logiciel le permet ».
- Les copies `backup` sont collectées puis nettoyées par le rôle `base` (pas plus de cinq par fichier).

---

### M04-E09 — Questions : précédence et nouveautés d'ansible-core

**Barème** : 2 points par question, total sur 30. Les comportements décrits ont été vérifiés avec ansible-core 2.21.5 et 2.19.14.

**Réponses argumentées — précédence**

**1.** `web1` → **`gv-web`** : il est dans `web` et `prod`. `prod` n'a qu'une variable écrite dans le **fichier d'inventaire** (catégorie basse), `web` a `group_vars/web.yml` (catégorie « inventory group_vars/* », au-dessus) : `gv-web` gagne sans même considérer l'ordre des groupes. `web2` → **`inventaire-hote`** : variable d'**hôte** du fichier d'inventaire, au-dessus de toutes les variables de groupe. `db1` → **`gv-all`** : piège ; `db1` n'est que dans `prod`, dont la variable est dans le fichier d'inventaire ; or `group_vars/all.yml` (« inventory group_vars/all ») est **au-dessus** des variables de groupe du fichier d'inventaire, même d'un groupe plus précis. Un `host_vars/db1.yml` vide ne change rien.

**2.** La tâche voit **`play`** : les variables de play sont au-dessus de `host_vars`. La logique d'Ansible n'est pas « le plus précis gagne » mais « le plus **explicite et le plus récent** gagne » : le play est écrit pour cette exécution, l'inventaire décrit l'état général. Règle : `vars:` de play pour ce qui est propre **au play** (et identique pour tous ses hôtes), jamais pour une valeur qui dépend de l'hôte ou de l'environnement.

**3.** `ntp_client` voit la valeur de `vars/main.yml` de `durcissement` : les `vars/` d'un rôle sont au-dessus des `defaults/` et ne sont pas privées par défaut (elles restent dans la portée du play après l'exécution du rôle, comme l'a montré le bac à sable de E06). Défauts révélés : deux rôles qui utilisent le **même nom** de variable (sans préfixe de rôle), et un rôle qui met en `vars/` une valeur que d'autres doivent pouvoir régler. Corrections : préfixes (`durcissement_…`, `ntp_client_…`), valeurs réglables en `defaults/`, éventuellement `DEFAULT_PRIVATE_ROLE_VARS`.

**4. Réponse B.** Avec la forme `clé=valeur`, `-e` produit toujours une **chaîne** : `paquets` vaut `"[htop,jq]"` (vérifié : `type_debug` → `str`). Une boucle sur cette valeur… itérerait sur des caractères, ou échouerait. Pour une liste : `-e '{"paquets": ["htop", "jq"]}'` (JSON) ou `-e @fichier.yml`. A est faux pour cette raison ; C est faux (aucune erreur) ; D est faux (les extra vars remplacent sans fusion de type).

**5.** Par défaut, `zone_b` (ordre alphabétique, le dernier chargé gagne). Pour inverser : `ansible_group_priority` (plus grand = chargé plus tard) **dans la source d'inventaire** (fichier ou plugin) ; **pas** dans `group_vars/` (ignoré sans avertissement). Le piège du passage au dynamique : avec des sous-groupes, l'enfant battait le parent ; un inventaire dynamique (`keyed_groups`) produit des groupes **à plat**, de même niveau : c'est alors l'alphabet qui tranche, et des valeurs changent sans qu'aucun fichier n'ait bougé (panne E37).

**6.** `ansible-inventory --host web1` affiche la valeur **brute**, `"{{ ms_passerelle }}"`, sans l'évaluer, et ignore tout ce qui n'est pas l'inventaire (variables de play, de rôle, faits). `ansible web1 -m ansible.builtin.debug -a var=ntp` évalue l'expression pour `web1` avec la précédence complète de l'inventaire : c'est la valeur qu'un playbook **sans** `vars:` propres verra. La seule preuve absolue reste un `debug` placé dans le play concerné, à l'endroit concerné.

**Réponses argumentées — nouveautés d'ansible-core**

**7. Conditions.**

| Condition | 2.21 | Correction |
|---|---|---|
| `when: utilisateurs` | **erreur** : « Conditional result (True) was derived from value of type 'list' … Conditionals must have a boolean result. » | `when: utilisateurs \| length > 0` |
| `when: activer` (chaîne `"false"`) | **erreur** (résultat de type `str`) ; avant 2.19, la chaîne était réinjectée dans l'expression puis réévaluée (le « templating en plusieurs passes » supprimé en 2.19) : le résultat dépendait du contenu de la chaîne, par accident | `when: activer \| bool` (ou mieux, stocker un vrai booléen) |
| `when: "{{ version }} == '13'"` | **erreur** de syntaxe : « Template delimiters are not supported in expressions » | `when: version == '13'` |
| `when: resultat.stdout` | **erreur** (chaîne) | `when: resultat.stdout \| length > 0`, ou un test précis (`'actif' in resultat.stdout`) |
| `when: resultat is changed` | accepté (un test renvoie un booléen) | — |
| `when: ansible_facts['distribution'] == 'Debian'` | accepté | — |

Une condition **entièrement** entourée de moustaches (`when: "{{ x == 1 }}"`) fonctionne encore, avec un avertissement de dépréciation (retrait annoncé en 2.23). Le réglage `ALLOW_BROKEN_CONDITIONALS` ramène les erreurs au rang d'avertissement, le temps d'une migration.

**8. Réponse B** avec la configuration du projet : `ansible_distribution` n'existe pas (`'ansible_distribution' is undefined`). Sans réglage en 2.21 : **A**, la valeur s'affiche avec l'avertissement « INJECT_FACTS_AS_VARS default to `True` is deprecated … will be removed from ansible-core version 2.24 … Use `ansible_facts["fact_name"]` (no `ansible_` prefix) instead. » En 2.24 : **B**, le défaut passe à `False`. C n'arrive jamais (une variable indéfinie est une erreur) ; D n'arrive qu'avec `inject_facts_as_vars = True` écrit explicitement (le choix est alors assumé, plus d'avertissement).

**9.** Le résultat de `stat` range ses informations sous `stat` : `marqueur.stat.exists`. `marqueur.exists` est **indéfini**. Avant 2.19, le test `false` ignorait silencieusement une valeur indéfinie : `marqueur.exists is false` valait toujours faux, la tâche **n'échouait jamais**, et l'erreur de logique passait inaperçue. Depuis 2.19, l'indéfini est détecté et la tâche échoue avec un message qui pointe l'expression. Correction : `failed_when: not marqueur.stat.exists`.

**10.** Avant 2.19, toute chaîne était un template potentiel, et Ansible enveloppait les données « non sûres » (résultats de modules, faits) dans un type spécial que chaque bout de code devait préserver ; un oubli suffisait pour qu'une chaîne contenant `{{ … }}` venue d'un hôte (sortie de commande, fichier lu, fait modifiable par un utilisateur de l'hôte) soit **évaluée sur le nœud de contrôle** : exécution de code arbitraire avec les droits de l'opérateur (plusieurs CVE). Depuis 2.19, le modèle est inversé : seules les chaînes venues de sources de confiance (playbooks, rôles, fichiers de variables) peuvent être des templates ; une donnée venue d'un module est référencée, jamais évaluée.

**11.** Depuis 2.19, une valeur qui se résout en `omit` **dans un élément de boucle** est retirée de l'élément au moment où la boucle est évaluée, au lieu de « fuir » jusqu'aux paramètres de la tâche. Dans l'élément concerné, `item.mode` n'existe donc plus. Le code de Lucas, `"{{ item.mode | default(omit) }}"`, est **correct** et compatible avec toutes les versions : l'indéfini devient `omit` au niveau de la tâche. Ce qui ne marche plus : `mode: "{{ item.mode }}"` en comptant sur l'`omit` de l'élément.

**12.** Une **variable** : `ansible_managed` peut être définie comme n'importe quelle variable (dans `group_vars/all`), ou on utilise sa propre variable (`ms_gere_par`, E07) avec le filtre `comment`. Plus souple : on peut la spécialiser par groupe ou par rôle (texte différent sur les hôtes d'un client), la traduire, et elle suit la précédence normale au lieu d'un réglage global du nœud de contrôle.

**13.** Jusqu'ici, un module qui renvoyait `rc` non nul sans `failed` était considéré comme en échec. En 2.21 ce comportement est **déprécié** (avertissements à l'exécution à partir de 2.22, retrait ensuite) : un module doit dire explicitement qu'il échoue, par `module.fail_json(…)` (ou `failed: true` dans son résultat), ou en laissant une exception non rattrapée (que le *wrapper* AnsiballZ transforme désormais en résultat d'échec structuré). `rc` redevient une simple information.

**14.** Debian 13 a Python 3.13 : le nœud de contrôle (`adm01`, `runner01`, `sem01`) et les hôtes gérés sont dans les clous. La VM CentOS 7 (Python 3.6) ne peut plus être gérée par les modules Python d'ansible-core 2.20+. Options : (a) la gérer avec un nœud de contrôle à part sous une ancienne version d'ansible-core (2.16 accepte encore Python 3.6 côté hôte géré ; à vérifier dans la matrice de support), isolé et temporaire ; (b) n'utiliser que `raw` pour les gestes indispensables ; (c) installer un Python récent sur la VM (paquets tiers), au prix d'une dépendance non supportée ; (d) accélérer sa migration (module 12), la vraie réponse.

**15.** Démarche : (1) inventaire du code (playbooks, rôles, modules et collections utilisés, `ansible-lint --profile min` pour mesurer) ; (2) environnement cible verrouillé (2.21 + collections récentes) et `ansible-lint` avec les règles de migration : FQCN (`fqcn`), `no-jinja-when`, conditions, `yaml[truthy]`, faits injectés ; (3) correction par lots (un rôle par MR), chaque lot rejoué en `--check --diff` sur un environnement de test, puis Molecule ; (4) critère de fin : `ansible-lint --profile production` vert, aucun avertissement de dépréciation à l'exécution (`ANSIBLE_DEPRECATION_WARNINGS` laissé actif, journal vérifié), `--check` sans changement inattendu sur le parc. Réglages de compatibilité temporaires : `ALLOW_BROKEN_CONDITIONALS=True`, `inject_facts_as_vars = True` explicite. À retirer **avant** la fin : ils masquent des erreurs de logique (une condition fausse évaluée vraie) et disparaîtront avec les versions suivantes (2.23, 2.24) ; laissés en place, ils transforment la migration suivante en big bang.
