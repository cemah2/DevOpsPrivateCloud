# Module 04 — Palier 1 : Découverte

Karim veut d'abord savoir ce que tu sais déjà de la gestion de configuration. Ensuite, tu ouvres le projet `plateforme/ansible` avec un environnement que toute l'équipe (et la CI) reconstruira à l'identique, tu décris le socle dans un inventaire, tu apprends à interroger les machines sans rien écrire, puis tu écris tes premiers playbooks. Ils ne sont pas jetables : la trousse de diagnostic (E05), les variables du site (E06), l'identité des hôtes (E07) et le client de temps (E08) deviendront les briques du rôle `base` au palier 2. Le palier se termine par un questionnaire sur la précédence des variables et sur ce qui a changé dans ansible-core depuis la 2.19.

Prérequis : module 03 terminé ; module 01 (forge, `runner01`, gabarits `plateforme/ci-templates` en `v1`, pre-commit sur `adm01`) ; module 02 (uv, script de configuration d'un projet, `ms-snapshot`). Lis [`00-introduction.md`](00-introduction.md), en particulier les conventions du projet, les règles du module et la section « Préparer `adm01` ».

---

### M04-E01 — Test de positionnement : gestion de configuration  `Q` `★★`

> **Ticket PLAT-501** — *De : Karim Benali*
> Même rituel qu'aux modules précédents. Gestion de configuration en général, Ansible en particulier, YAML et Jinja2 : par écrit, sans moteur de recherche ni IA, sans rien exécuter. Une heure maximum, puis tu te corriges avec la grille. Si tu n'as jamais touché à Ansible, réponds quand même : le raisonnement compte.

**Objectifs pédagogiques**
- Évaluer tes acquis en gestion de configuration (idempotence, convergence, dérive, modèles *push* et *pull*).
- Repérer les notions d'Ansible, de YAML et de Jinja2 à travailler avant les exercices qui les mobilisent.

**Prérequis** : aucun.
**Durée indicative** : 1 h (+ 30 min d'auto-correction).

**Travail demandé**

Réponds aux 20 questions. Pour les QCM, justifie ton choix en une ou deux phrases.

*Gestion de configuration*

1. Définis **idempotence** et **convergence**. Un script qui lance `apt-get install -y tcpdump` à chaque exécution est-il idempotent ? Dans quel sens oui, dans quel sens non ?

2. Qu'est-ce que la **dérive de configuration** ? Donne deux causes réalistes dans une équipe d'exploitation, et explique pourquoi « on configure tout au premier démarrage avec cloud-init, ensuite on n'y touche plus » ne suffit pas.

3. Compare le modèle *push* (Ansible) et le modèle *pull* avec agent (Puppet, Salt en mode agent) : deux avantages et deux inconvénients pour chacun.

4. *(QCM)* De quoi Ansible a-t-il besoin, au minimum, sur un serveur Linux qu'il gère avec les modules habituels (`apt`, `template`, `service`…) ?
   - A. Un agent Ansible qui tourne en permanence
   - B. Un accès SSH et un interpréteur Python
   - C. Rien du tout
   - D. Un accès SSH, Python et la collection `ansible.builtin` installée sur le serveur

5. Pourquoi dit-on qu'un playbook est « déclaratif » ? Où cette affirmation devient-elle fausse ?

*Ansible*

6. Explique les rôles respectifs de : l'inventaire, un play, une tâche, un module, un handler, un rôle, une collection.

7. Quelles différences entre les modules `command`, `shell`, `raw` et `script` ? Dans quelle situation `raw` est-il légitime ?

8. *(QCM)* `ansible all -m ansible.builtin.ping` répond `pong` pour un hôte. Qu'est-ce que cela prouve ?
   - A. Que l'hôte répond aux paquets ICMP
   - B. Qu'Ansible peut s'y connecter, s'y authentifier et y exécuter un module Python
   - C. Que l'élévation de privilèges (`sudo`) fonctionne sur l'hôte
   - D. Que le nom de l'hôte se résout dans le DNS

9. Que fait `become: true` ? Quelle différence avec `become_user` ? Pourquoi écrire `sudo` dans une commande `shell` est-il une mauvaise idée ?

10. *(QCM)* Tu lances `ansible-playbook site.yml --check`. Que deviennent les tâches `ansible.builtin.command` qui n'ont ni `creates` ni `removes` ?
    - A. Elles sont exécutées normalement
    - B. Elles sont sautées (*skipped*)
    - C. Elles provoquent une erreur : le mode simulation ne les accepte pas
    - D. Elles sont exécutées, mais toujours marquées `ok`

11. Que sont les **faits** (*facts*) ? Comment sont-ils collectés, que coûtent-ils, et comment s'en passer dans un play qui n'en a pas besoin ?

12. Quand un **handler** s'exécute-t-il ? Que se passe-t-il si trois tâches le notifient ? Et si une tâche échoue après l'avoir notifié ?

13. Pourquoi utiliser le module `template` plutôt que `copy` pour un fichier de configuration ? À quoi sert son paramètre `validate` ?

14. Dans un rôle, quelle différence entre `defaults/main.yml` et `vars/main.yml` ? Où mets-tu le port d'écoute d'un service que les utilisateurs du rôle doivent pouvoir changer ?

15. *(QCM)* Quelle est la différence entre le paquet Python `ansible` et le paquet `ansible-core` ?
    - A. Aucune : ce sont deux noms pour le même logiciel
    - B. `ansible` contient `ansible-core` plus un ensemble de collections sélectionnées par la communauté
    - C. `ansible-core` contient `ansible` plus les modules réseau
    - D. `ansible` est la version commerciale, `ansible-core` la version libre

16. Que protège Ansible Vault ? Cite deux façons dont un secret « vaulté » peut quand même fuiter à l'exécution, et la parade.

17. Ces tâches sont-elles idempotentes ? Pour chacune, oui ou non, et pourquoi.
    ```yaml
    - ansible.builtin.file:
        path: /var/lib/medisphere/marqueur
        state: touch
    - ansible.builtin.lineinfile:
        path: /etc/environment
        line: "HTTP_PROXY=http://proxy.par1.medisphere.internal:3128"
    - ansible.builtin.shell: echo "vm.swappiness=10" >> /etc/sysctl.d/90-medisphere.conf
    - ansible.builtin.command: /usr/local/bin/initialiser-base.sh
      args:
        creates: /var/lib/medisphere/base-initialisee
    ```

18. Tu dois appliquer une modification sur 200 serveurs. Que règlent `forks`, `serial` et `strategy: free` ? Lequel protège d'une erreur qui casserait tout le parc d'un coup ?

*YAML et Jinja2*

19. Donne la valeur **et le type** que reçoit Ansible pour chacune de ces lignes d'un fichier de variables, et dis lesquelles sont des pièges :
    ```yaml
    mode_a: 0644
    mode_b: 644
    mode_c: "0644"
    version_python: 3.10
    code_pays: NO
    actif: yes
    duree: 1:30
    ```

20. Que donnent ces expressions Jinja2, avec `serveurs: [web03, web01, web02]` et `proxy: null` (et `inconnue` jamais définie) ?
    ```jinja
    {{ serveurs | sort | first }}
    {{ "web" ~ 1 }}
    {{ serveurs | length > 2 }}
    {{ inconnue | default("aucune") }}
    {{ proxy | default("direct") }}
    {{ proxy | default("direct", true) }}
    ```

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 20 questions avant d'ouvrir le corrigé.
- [ ] Tu as noté chaque réponse avec la grille (0, 1 ou 2 points) et calculé ton score sur 40.
- [ ] Tu as noté les thèmes à retravailler et les exercices du module qui les mobilisent.

<details><summary>Indice 1</summary>

Pour l'idempotence, distingue deux choses : l'**état** obtenu après deux exécutions, et ce que l'outil **rapporte** à chaque exécution. Un outil de gestion de configuration doit avoir les deux propriétés, pas seulement la première.
</details>

<details><summary>Indice 2</summary>

Ansible lit le YAML avec PyYAML, qui suit la spécification YAML **1.1**, plus permissive (et plus piégeuse) que la 1.2 sur les booléens, les nombres en base 8 et les nombres en base 60.
</details>

**Pour aller plus loin** (facultatif) : refais ce test à la fin du module (E46), sans relire le corrigé, et compare.

---

### M04-E02 — Créer le projet `plateforme/ansible` et un environnement reproductible  `LAB` `★`

> **Ticket PLAT-502** — *De : Karim Benali*
> Ouvre `plateforme/ansible` avec la configuration standard de la forge, comme `outils` et `images`. Et règle tout de suite la question de l'outil : chez InfoGér, chacun avait « son » Ansible (celui de Debian, un `pip install` de 2021, un conteneur…), et le même playbook ne donnait pas le même résultat d'un poste à l'autre. Chez nous, la version d'ansible-core, des outils de test et de chaque collection est **dans le dépôt**, et `adm01`, `runner01` et la future console Semaphore exécutent exactement la même chose.

**Objectifs pédagogiques**
- Créer un projet de la plateforme avec sa configuration standard, sans en oublier un élément.
- Construire un environnement d'exécution d'Ansible reproductible avec uv (`pyproject.toml`, `uv.lock`) et des collections épinglées.
- Comprendre comment Ansible trouve sa configuration, et lire la configuration effective.
- Distinguer `ansible-core`, le paquet `ansible`, les collections et leurs versions.

**Prérequis** : M02-E02 (projet de la plateforme, script de configuration), M02-E07 (projet géré par uv), M01-E15 (pre-commit).
**Durée indicative** : 1 h 30.

**Contexte technique**
- Projet : `plateforme/ansible`, privé, configuration standard (M02-E02 : réglages de fusion, protections, étiquettes `v*`, jeton `bot-release` et variable `GITLAB_TOKEN`). Clone : `~/src/ansible` (`git@git01.par1.medisphere.internal:plateforme/ansible.git`).
- Fichiers standard attendus sur `main` : `README.md`, `.gitignore`, `.gitlab-ci.yml` (gabarits `qualite.yml` et `release.yml` de `plateforme/ci-templates`, `ref: v1`), `.pre-commit-config.yaml`, `commitlint.config.mjs`, `.releaserc.json`, `CONTRIBUTING.md`, `.gitlab/merge_request_templates/Default.md`. Le contrôle `ansible-lint` arrivera dans pre-commit et en CI en E20.
- Environnement Python, géré par uv, **qui n'est pas un paquet** (aucune construction) :

| Élément | Exigence |
|---|---|
| Python | 3.13 de Debian uniquement (`.python-version`, aucun Python téléchargé) |
| Dépendances d'exécution | `ansible-core` limité à la série **2.21** ; `proxmoxer` ≥ 2.3 et `requests` (inventaire dynamique et modules Proxmox, E13) |
| Outils de qualité (groupe `dev`) | `ansible-lint` 26.x, `molecule` 26.x |
| Verrou | `uv.lock` versionné ; `.venv/` jamais versionné |

- Collections : fichier `collections/requirements.yml`, **versions exactes**, installées dans `collections/` à la racine du projet. Au moment de la rédaction : `community.proxmox` 2.1.0, `community.general` 13.5.0, `ansible.posix` 2.2.2 (une version plus récente **de la même série** convient). Seule une future collection interne (`collections/ansible_collections/medisphere/`, E18) sera versionnée.
- `ansible.cfg` à la racine du projet. Effets attendus : inventaire `inventories/lab/hosts.yml` ; rôles et collections cherchés **dans le projet uniquement** ; 10 connexions en parallèle ; faits accessibles **seulement** par `ansible_facts['…']` ; modules exécutés sur chaque hôte par le Python **du système** (`/usr/bin/python3`), désigné explicitement plutôt que découvert (lis la description de `INTERPRETER_PYTHON` et de sa liste de repli) ; résultats des tâches affichés en YAML ; *pipelining* SSH activé ; vérification des clés d'hôte **laissée par défaut**.
- Inventaire minimal pour tester l'environnement : `inventories/lab/hosts.yml` contenant le seul hôte `adm01` (10.10.10.10), géré en connexion locale. Il sera complété en E03.

**Travail demandé**
1. Crée le projet et applique la configuration standard. Le plus court : le script de M02-E02 (`configurer-projet.sh plateforme/ansible`), qui est rejouable. Clone-le dans `~/src/ansible`, crée la branche `chore/configuration-initiale` et ajoute les fichiers standard (copiés ou adaptés depuis `~/src/outils`, comme en M02-E02).
2. Crée l'environnement avec uv : `uv init --bare` produit un `pyproject.toml` minimal, `uv add` et `uv add --dev` y ajoutent les dépendances. Complète la section `[tool.uv]` (projet non empaqueté, Python du système uniquement), puis :
   ```
   admin@adm01:~/src/ansible$ uv sync --locked
   admin@adm01:~/src/ansible$ uv run ansible --version
   admin@adm01:~/src/ansible$ uv run molecule --version
   ```
   Dans ton journal (`~/m04/e02/notes.md`) : pourquoi `~=2.21.0` plutôt que `>=2.21` ? Que contient `uv.lock` que `pyproject.toml` ne dit pas ? Lance aussi `.venv/bin/molecule --version` directement, sans `uv run` : que se passe-t-il, et pourquoi ?
3. Lis la sortie de `uv run ansible --version` ligne à ligne : quelle configuration est utilisée, où sont cherchées les collections, quel Python exécute Ansible ?
4. Écris `ansible.cfg`. Pour trouver le nom exact de chaque réglage et sa section, utilise `uv run ansible-config list` (ou `ansible-config init --disabled -t all` pour un fichier entièrement commenté) et la documentation des plugins (`ansible-doc -t callback ansible.builtin.default`, `ansible-doc -t connection ansible.builtin.ssh`). Commente **chaque** ligne : pourquoi cette valeur. Puis :
   ```
   admin@adm01:~/src/ansible$ uv run ansible-config dump --only-changed -t all
   admin@adm01:~/src/ansible$ uv run ansible-config validate -t all
   ```
   Questions pour le journal : dans quel ordre Ansible cherche-t-il son fichier de configuration ? Que se passe-t-il si on lance `ansible` depuis `~/src/ansible/playbooks` ? Pourquoi Ansible refuse-t-il un `ansible.cfg` placé dans un dossier modifiable par tous ?
5. Écris `collections/requirements.yml` et installe les collections dans le projet :
   ```
   admin@adm01:~/src/ansible$ uv run ansible-galaxy collection install -r collections/requirements.yml -p collections
   admin@adm01:~/src/ansible$ uv run ansible-galaxy collection list
   ```
   Combien de collections ont été installées ? D'où vient celle que tu n'as pas demandée ? Vérifie dans `meta/runtime.yml` de chaque collection la version d'ansible-core qu'elle exige.
6. Écris `.gitignore` : environnement, collections de Galaxy (mais pas la future collection interne), fichiers de travail d'Ansible et de ses outils, filet contre les fichiers de secrets. Vérifie tes règles avec `git check-ignore -v`.
7. Écris l'inventaire minimal, puis :
   ```
   admin@adm01:~/src/ansible$ uv run ansible adm01 -m ansible.builtin.ping
   ```
8. `pre-commit install`, `pre-commit run --all-files`, commit conventionnel, MR avec le modèle, pipeline vert, fusion. Complète le `README.md` : comment reconstruire l'environnement sur un poste neuf, en trois commandes.
9. Réfléchis, dans ton journal : Debian 13 propose les paquets `ansible` et `ansible-core` (2.19). Pourquoi ne pas simplement les installer avec `apt` ? Dans quel cas ce serait le bon choix ?

**Critères de réussite**
- [ ] Le projet `plateforme/ansible` a la configuration standard de la plateforme ; `main` contient les fichiers standard, `ansible.cfg`, `pyproject.toml`, `uv.lock`, `.python-version`, `collections/requirements.yml`.
- [ ] `uv lock --check` passe ; `uv run ansible --version` affiche `core 2.21.x` et la configuration du projet.
- [ ] `ansible-lint` 26 et `molecule` 26 répondent dans l'environnement du projet.
- [ ] Les trois collections sont installées dans `collections/`, aux versions de `requirements.yml`, et ne sont pas versionnées.
- [ ] `ansible-config validate -t all` ne signale rien ; la configuration effective correspond aux effets attendus.
- [ ] `uv run ansible adm01 -m ansible.builtin.ping` répond `pong`.

**Vérification** : `lab/bin/check 04 02`

<details><summary>Indice 1</summary>

Le module 02 a déjà résolu presque tout : relis ton `pyproject.toml` de `plateforme/outils` (section `[tool.uv]`) et la documentation de uv sur les projets qui ne sont pas des paquets (*virtual projects*). La seule nouveauté, c'est le groupe de dépendances `dev`.
</details>

<details><summary>Indice 2</summary>

Dans `ansible-config list`, chaque réglage indique son nom dans `ansible.cfg` (`ini:`, avec la section) et sa variable d'environnement. Les réglages des **plugins** (format de sortie du callback, *pipelining* de la connexion SSH) ne sont reconnus par `ansible-config validate` qu'avec `-t all` ; et une même option peut être acceptée dans plusieurs sections : préfère celle que reconnaît le cœur d'Ansible.
</details>

<details><summary>Indice 3</summary>

Pour ignorer tout le contenu d'un dossier sauf un sous-dossier, Git exige d'ignorer les **enfants** du dossier (`dossier/*`), pas le dossier lui-même : un dossier ignoré n'est jamais parcouru, et une exception à l'intérieur ne peut plus s'appliquer.
</details>

**Pour aller plus loin** (facultatif) : `ansible-galaxy collection verify -r collections/requirements.yml -p collections` compare les fichiers installés aux empreintes publiées par Galaxy. Que vérifie-t-il exactement, et que ne vérifie-t-il pas (lis la partie sur les signatures de collections dans la documentation de Galaxy) ?

---

### M04-E03 — Inventaire statique du socle  `LAB` `★`

> **Ticket PLAT-503** — *De : Karim Benali*
> Décris le socle dans un inventaire. Deux contraintes. Un : les groupes doivent être **exactement** ceux que produira l'inventaire dynamique Proxmox à partir de nos étiquettes (module 02), pour qu'on puisse basculer de l'un à l'autre sans toucher aux playbooks. Deux : quand le DNS tombe, c'est précisément le jour où on a besoin d'Ansible ; l'inventaire ne doit pas en dépendre. Et je ne veux voir nulle part `host_key_checking = False`.

**Objectifs pédagogiques**
- Écrire un inventaire YAML : hôtes, groupes, variables de connexion.
- Interroger un inventaire (`ansible-inventory`) et cibler des hôtes avec des motifs (*patterns*).
- Comprendre comment Ansible se connecte : SSH, compte, clé, Python de l'hôte, clés d'hôte.
- Placer chaque variable à l'endroit qui survivra au changement de source d'inventaire.

**Prérequis** : M04-E02 ; M02-E05 (étiquettes Proxmox du socle).
**Durée indicative** : 1 h 30.

**Contexte technique**

| Hôte | `ansible_host` | Groupes |
|---|---|---|
| `gw01` | 10.10.10.1 | `socle`, `role_routeur` |
| `adm01` | 10.10.10.10 | `socle`, `role_bastion` — géré en connexion **locale** |
| `dns01` | 10.10.20.10 | `socle`, `role_dns` |
| `git01` | 10.10.20.12 | `socle`, `role_gitlab` |
| `runner01` | 10.10.20.15 | `socle`, `role_runner` |

- L'inventaire dynamique (E13) produira ces groupes à partir des étiquettes Proxmox `socle` et `role-<rôle>`, **tous au même niveau** (enfants directs de `all`). L'inventaire statique fait de même : `role_*` n'est pas un sous-groupe de `socle`.
- Compte de connexion : `admin` (sudo sans mot de passe), clé de `adm01` chargée dans l'agent SSH. L'élévation est demandée par chaque play (`become: true`), pas dans l'inventaire.
- L'inventaire dynamique fournira lui-même `ansible_host` ; tout le reste (compte, connexion locale de `adm01`) doit vivre dans `group_vars/` ou `host_vars/`, voisins de l'inventaire, qui servent aux deux.

**Travail demandé**
1. Avant d'écrire, regarde ce qu'Ansible devra traverser : pour chaque adresse IP, `ssh-keygen -F <IP>` (la clé d'hôte est-elle connue sous cette adresse ?), puis `ssh -G <IP> | grep -Ei '^(user|identityfile|stricthostkeychecking|controlpath) '`. Quelle partie de ton `~/.ssh/config` s'applique quand on se connecte par l'adresse et non par l'alias ?
2. Écris `inventories/lab/hosts.yml` (format YAML), `inventories/lab/group_vars/all/main.yml` et ce qu'il faut dans `inventories/lab/host_vars/`. Pourquoi un **dossier** `group_vars/all/` plutôt qu'un fichier `group_vars/all.yml` ?
3. Interroge l'inventaire :
   ```
   admin@adm01:~/src/ansible$ uv run ansible-inventory --graph
   admin@adm01:~/src/ansible$ uv run ansible-inventory --host adm01
   admin@adm01:~/src/ansible$ uv run ansible-inventory --list | jq '._meta.hostvars.gw01'
   ```
4. Motifs : sans rien exécuter (`--list-hosts`), trouve l'expression qui sélectionne : tout le socle sauf le routeur ; `dns01` et `git01` seulement ; les hôtes qui sont à la fois dans `socle` et dans `role_gitlab` ; les hôtes du VLAN INFRA (un motif peut-il s'appuyer sur leur adresse ? sinon, que faudrait-il ?). Note-les dans `~/m04/e03/notes.md`.
5. Teste la connexion :
   ```
   admin@adm01:~/src/ansible$ uv run ansible socle -m ansible.builtin.ping
   admin@adm01:~/src/ansible$ uv run ansible socle -m ansible.builtin.ping -vvv --limit dns01
   ```
   Dans la sortie détaillée, retrouve la commande `ssh` complète lancée par Ansible : quelles options ajoute-t-il, où est son *socket* de multiplexage, quel Python est utilisé sur `dns01` ? Si un hôte n'a pas de Python (`/usr/bin/python3: not found`), quel module permet malgré tout d'en installer un, et pourquoi lui seulement ?
6. Observe ce que fait Ansible face à une clé d'hôte inconnue, sans rien casser : relance le `ping` sur `runner01` en lui faisant utiliser un fichier `known_hosts` vide (`-e 'ansible_ssh_common_args="-o UserKnownHostsFile=/dev/null"'`). Lis la question posée et réponds **no**. Puis réponds dans ton journal : comment accueillir proprement la clé d'une nouvelle VM du socle sans la valider « à l'aveugle » ? (Pense aux moyens que tu as de lire l'empreinte depuis Proxmox, sans passer par le réseau.)
7. Commit, MR, fusion.

**Critères de réussite**
- [ ] `ansible-inventory --graph` montre `socle` et les cinq groupes `role_*`, tous enfants directs de `all`, avec les bons hôtes.
- [ ] Chaque hôte a son adresse IP en `ansible_host` ; `adm01` est en connexion locale ; le compte `admin` est défini une fois pour tous.
- [ ] `ansible socle -m ansible.builtin.ping` répond `pong` pour les cinq hôtes.
- [ ] Aucun réglage du projet ni de ton compte ne désactive la vérification des clés d'hôte.
- [ ] L'inventaire est sur `main`.

**Vérification** : `lab/bin/check 04 03`

<details><summary>Indice 1</summary>

Dans un inventaire YAML, un hôte peut apparaître dans plusieurs groupes : ses variables ne se déclarent qu'une fois, les autres mentions sont de simples clés vides. `ansible-inventory --list` montre où chaque hôte a atterri et quelles variables il porte.
</details>

<details><summary>Indice 2</summary>

Les variables de `host_vars/<hôte>/` sont lues pour tout inventaire situé dans le même dossier, quelle que soit sa source (fichier statique ou plugin). C'est le bon endroit pour ce qui décrit **comment** joindre un hôte sans dépendre de l'endroit où on a trouvé son adresse.
</details>

<details><summary>Indice 3</summary>

Pour les motifs, lis la page *Patterns: targeting hosts and groups* de la documentation : opérateurs `:`, `:&`, `:!`, jokers `*`, et expressions régulières préfixées par `~`. Mets le motif entre apostrophes dans le shell.
</details>

**Pour aller plus loin** (facultatif) : écris le même inventaire au format INI et compare avec `ansible-inventory --list` : les deux donnent-ils exactement les mêmes types de variables (essaie une variable `ansible_port: 22` dans les deux formats) ?

---

### M04-E04 — Commandes ad hoc, modules et facts  `LAB` `★`

> **Ticket PLAT-504** — *De : Nadia Roussel*
> Revue de capacité lundi. Pour chaque machine du socle, il me faut : distribution et version, noyau, nombre de vCPU, mémoire, place libre sur `/`, depuis combien de temps elle tourne, et si elle attend un redémarrage. Et pas en ouvrant cinq sessions SSH : je veux voir comment on obtient ça en une commande, pour pouvoir le refaire seule en astreinte.

**Objectifs pédagogiques**
- Lancer des commandes ad hoc et choisir le bon module (`command`, `shell`, `stat`, `setup`, `file`).
- Lire la documentation des modules et des plugins sans quitter le terminal (`ansible-doc`).
- Collecter et exploiter les faits d'un parc ; comprendre leur coût.
- Observer l'idempotence (ou son absence), le parallélisme et la façon dont Ansible rapporte un échec.

**Prérequis** : M04-E03.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Dossier de travail : `~/m04/e04/` (non versionné) : `notes.md` (ton journal), `facts/` (faits enregistrés), `capacite.csv` (le relevé de Nadia).
- `capacite.csv` : une ligne d'en-tête, puis une ligne par hôte du socle, colonnes dans cet ordre : `hote,distribution,version,noyau,vcpu,memoire_mo,disque_libre_go,uptime_jours`. La mémoire est en Mo, telle que la rapportent les faits.
- `jq` est installé sur `adm01` (M02).
- Les commandes se lancent depuis `~/src/ansible` (configuration et inventaire du projet).

**Travail demandé**
1. **La documentation.** Combien de modules connaît ton installation (`ansible-doc -l | wc -l`) ? Pourquoi si peu par rapport à « Ansible a des milliers de modules » ? Lis `ansible-doc ansible.builtin.stat` jusqu'aux sections `EXAMPLES` et `RETURN`. À quoi sert `ansible-doc -s` ? Et `ansible-doc -t` ?
2. **Commandes.** Sur le socle, en ad hoc : `uptime`, puis la ligne de `df -h /` qui concerne la racine (sans l'en-tête). Essaie d'abord avec le module `command`, puis avec `shell`. Explique la différence de résultat. Beaucoup de tutoriels ajoutent `-o` pour avoir une ligne par hôte : essaie, et lis les avertissements. Pour une sortie exploitable par un script, essaie plutôt le callback JSON (collection `ansible.posix`) : `ANSIBLE_LOAD_CALLBACK_PLUGINS=1 ANSIBLE_STDOUT_CALLBACK=ansible.posix.json`, et extrais avec `jq` la sortie d'`uptime` de chaque hôte. Pourquoi faut-il la première variable pour une commande ad hoc, et pas pour `ansible-playbook` ?
3. **Élévation.** `ls /root` sur `dns01`, sans puis avec `-b`. Que dit Ansible dans chaque cas ? Où est configuré le droit qui fait réussir le second ?
4. **Redémarrage attendu.** Avec le module `ansible.builtin.stat`, trouve quels hôtes ont un fichier `/run/reboot-required`. Pourquoi `stat` plutôt que `command: test -f …` ?
5. **Faits.** Affiche les faits de distribution de `dns01` (`-m ansible.builtin.setup -a 'filter=ansible_distribution*'`). Puis collecte pour tout le socle les sous-ensembles `distribution`, `kernel` et `hardware` seulement (paramètre `gather_subset`) et enregistre-les avec l'option `--tree ~/m04/e04/facts`. Compare la durée avec une collecte complète (`time`). Que contient un fichier de `facts/` ?
   > ⚠️ **Attention** : dans `gather_subset`, le `!` qui exclut un sous-ensemble est aussi le caractère de l'historique de Bash. Mets toujours l'argument entre apostrophes.
6. **Le relevé.** Écris un filtre `jq` qui produit une ligne CSV par fichier de `facts/` (le nom de l'hôte est le nom du fichier : regarde la fonction `input_filename` de jq), puis génère `~/m04/e04/capacite.csv` avec son en-tête. Les noms de faits ont-ils le préfixe `ansible_` dans ces fichiers ? Et dans un playbook avec la configuration du projet ?
7. **Idempotence observée.** Sur `dns01` seulement, avec le module `ansible.builtin.file` et `-b` : crée le dossier `/tmp/m04-e04` deux fois de suite (`state=directory`), puis « touche » le fichier `/tmp/m04-e04/marqueur` deux fois de suite (`state=touch`). Compare `changed` à chaque fois et explique. Fais en sorte que le second `touch` ne compte plus comme un changement (lis la documentation du module), puis supprime le dossier.
8. **Parallélisme.** Mesure `time uv run ansible socle -m ansible.builtin.command -a 'sleep 3'` avec la configuration du projet, puis avec `-f 1`. Explique les deux durées et l'ordre d'affichage des hôtes.
9. **Échec.** `uv run ansible socle -m ansible.builtin.command -a 'test -f /etc/nftables.conf'`. Combien d'hôtes « échouent » ? Est-ce une erreur ? Quel code retour donne la commande `ansible` elle-même, et qu'en déduis-tu pour un script qui l'appellerait ?
10. Dans `notes.md`, réponds à Nadia : quel hôte a le moins de place libre, lequel attend un redémarrage, et les commandes à retenir pour l'astreinte.

**Critères de réussite**
- [ ] `~/m04/e04/facts/` contient les faits des cinq hôtes du socle, avec distribution, noyau et matériel.
- [ ] `~/m04/e04/capacite.csv` a une ligne par hôte, et la mémoire relevée correspond aux faits actuels.
- [ ] `notes.md` répond aux questions des étapes 1 à 10.
- [ ] `/tmp/m04-e04` n'existe plus sur `dns01`.

**Vérification** : `lab/bin/check 04 04`

<details><summary>Indice 1</summary>

Le module `command` n'utilise pas de shell : pas de tube, pas de redirection, pas de variable d'environnement développée. Ce qui ressemble à un `|` lui est transmis comme un argument ordinaire.
</details>

<details><summary>Indice 2</summary>

Dans `jq`, `input_filename` donne le chemin du fichier en cours de lecture ; `sub(".*/"; "")` en garde le nom. Pour la place libre de `/`, cherche dans la liste des points de montage (`ansible_mounts`) l'élément dont `mount` vaut `/`. `@csv` met une liste au format CSV.
</details>

<details><summary>Indice 3</summary>

Pour `state=touch`, le module `file` a deux paramètres qui disent quoi faire des dates d'accès et de modification ; avec la valeur qui les préserve, un fichier qui existe déjà n'est plus modifié.
</details>

**Pour aller plus loin** (facultatif) : refais l'étape 5 avec `--tree` remplacé par un cache de faits (`fact_caching = jsonfile`, voir E26) : à quoi servirait ce cache dans un pipeline qui lance plusieurs playbooks de suite ?

---

### M04-E05 — Premier playbook idempotent  `LAB` `★`

> **Ticket PLAT-505** — *De : Nadia Roussel* — *Copie : Sophie Laurent, Lucas Martin*
> Suite à l'incident de mardi : je veux la même trousse de diagnostic sur **toutes** les machines du socle (liste ci-dessous). Sophie ajoute deux demandes : plus aucun client de protocole en clair (telnet, rsh), et l'historique bash horodaté partout, pour savoir **quand** une commande a été tapée. Lucas a déjà écrit un playbook (`trousse-lucas.yml`) ; Karim l'a refusé en revue. Reprends-le proprement : un second passage ne doit rien changer.

**Objectifs pédagogiques**
- Écrire un playbook : play, cible, élévation, tâches nommées, modules en FQCN.
- Remplacer des commandes shell par des modules qui décrivent un état.
- Vérifier l'idempotence : simulation (`--check --diff`), second passage à `changed=0`.
- Déployer progressivement : un hôte d'abord, puis tout le socle.

**Prérequis** : M04-E04.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Playbook : `playbooks/trousse-diagnostic.yml`, cible : groupe `socle`.
- Trousse : `bind9-dnsutils`, `tcpdump`, `mtr-tiny`, `curl`, `jq`, `lsof`, `strace`, `htop`.
- Interdits (à retirer s'ils sont présents) : `telnet`, `inetutils-telnet`, `rsh-client`.
- Historique horodaté : la ligne `export HISTTIMEFORMAT='%F %T '` présente **une seule fois** dans `/etc/bash.bashrc`.
- Le playbook de Lucas : [`ressources/M04-E05/trousse-lucas.yml`](../ressources/M04-E05/trousse-lucas.yml). **Ne le lance pas.**
- Pour ce palier, les listes peuvent vivre dans le playbook ; elles passeront dans l'inventaire en E06.

**Travail demandé**
1. Lis le playbook de Lucas. Dans ton journal (`~/m04/e05/notes.md`) : que donnerait un **second** passage, tâche par tâche (état des machines **et** ce qu'Ansible afficherait) ? Liste au moins six défauts. Confirme une partie de ton analyse avec `uv run ansible-lint ~/DevOpsPrivateCloud/modules/04-ansible/ressources/M04-E05/trousse-lucas.yml`.
2. Écris `playbooks/trousse-diagnostic.yml`. Décide si le play a besoin de collecter les faits. Une seule tâche par intention, chacune avec un `name:` qui dit l'état voulu.
3. Avant toute exécution :
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/trousse-diagnostic.yml --syntax-check
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/trousse-diagnostic.yml --list-hosts --list-tasks
   ```
4. Déploie progressivement : `--check --diff --limit runner01`, lis le résultat ; puis réel sur `runner01` ; puis `--check --diff` sur tout le socle ; puis réel sur tout le socle. Si le mode `--check` échoue sur un hôte avec un message à propos de `python3-apt`, lis-le jusqu'au bout et explique pourquoi l'exécution réelle, elle, réussirait.
5. Relance le playbook. Le récapitulatif doit afficher `changed=0` partout. Si une tâche reste « changed », trouve pourquoi et corrige.
6. Expériences sur `runner01` seulement, puis remise en état :
   - modifie à la main la ligne `HISTTIMEFORMAT` (un autre format), relance en `--check --diff` : que propose Ansible ?
   - ajoute à la main une **seconde** ligne `export HISTTIMEFORMAT=…` identique : que fait ton playbook ? Lis la documentation de `lineinfile` sur le cas de plusieurs lignes correspondantes. Que faudrait-il pour qu'Ansible corrige aussi ce cas ? Remets `runner01` dans l'état attendu (une seule ligne).
7. Commit, MR, fusion.

**Critères de réussite**
- [ ] Les cinq hôtes du socle ont la trousse complète, aucun client telnet ou rsh, et la ligne `HISTTIMEFORMAT` une seule fois.
- [ ] Le playbook n'utilise ni `shell`, ni `command`, ni `sudo` pour gérer les paquets ; les modules sont en FQCN.
- [ ] Un passage en `--check` sur le socle n'annonce aucun changement et aucun échec.
- [ ] `notes.md` contient l'analyse du playbook de Lucas et le résultat des expériences de l'étape 6.

**Vérification** : `lab/bin/check 04 05`

<details><summary>Indice 1</summary>

Le module `ansible.builtin.apt` accepte une **liste** de paquets dans `name` : une seule tâche, une seule transaction APT. Il sait aussi rafraîchir l'index des paquets dans la même tâche, mais seulement s'il est trop vieux : regarde ses paramètres `update_cache` et `cache_valid_time`.
</details>

<details><summary>Indice 2</summary>

Une tâche qui rafraîchit l'index APT **seule** (sans paquet) est toujours « changed » dès que l'index a été rafraîchi. Rattachée à la tâche qui installe, elle ne compte que si un paquet est réellement installé.
</details>

<details><summary>Indice 3</summary>

`lineinfile` cherche les lignes qui correspondent à `regexp` ; sans `regexp`, il ne connaît que la ligne exacte de `line`. Une ligne existante mais différente est alors laissée telle quelle, et la tienne s'ajoute à côté.
</details>

**Pour aller plus loin** (facultatif) : un fichier `/etc/profile.d/medisphere-historique.sh` géré par `ansible.builtin.copy` plutôt qu'une ligne dans `/etc/bash.bashrc` : avantages, inconvénients, et quels shells le liraient ?

---

### M04-E06 — Variables et précédence  `LAB` `★★`

> **Ticket PLAT-506** — *De : Karim Benali*
> J'ai refusé la MR de Lucas qui ajoutait `conntrack` à la trousse avec un `when: inventory_hostname == 'gw01'`. Règle de l'équipe : **le code est générique, les données sont dans l'inventaire.** Profites-en pour poser les variables du site dont les rôles du palier 2 auront besoin (domaine, résolveur, passerelle du VLAN, sources de temps). Et avant de toucher au projet, je veux que tu saches prédire qui gagne quand une variable est définie à plusieurs endroits : c'est la première cause d'incident avec Ansible.

**Objectifs pédagogiques**
- Connaître les principaux niveaux de précédence des variables et savoir les **prédire**, puis les vérifier.
- Comprendre la fusion des variables de groupes (profondeur, ordre alphabétique, `ansible_group_priority`).
- Ranger les variables d'un projet : valeurs par défaut, spécificités de rôle et d'hôte, sans `vars:` de play qui écrase tout.
- Distinguer la valeur **brute** d'une variable (inventaire) et sa valeur **évaluée** pour un hôte.

**Prérequis** : M04-E05.
**Durée indicative** : 2 h.

**Contexte technique**
- Bac à sable : [`ressources/M04-E06/precedence/`](../ressources/M04-E06/precedence/) (trois hôtes fictifs en connexion locale : rien ne touche le lab). Copie-le dans `~/m04/e06/` et lance Ansible **depuis ce dossier** (il a son propre `ansible.cfg`), avec l'environnement du projet : `~/src/ansible/.venv/bin/ansible…`, ou `uv run --project ~/src/ansible ansible…`.
- Variables du site à créer dans `inventories/lab/group_vars/all/main.yml` (noms contractuels : les vérifications et les rôles suivants s'en servent) :

| Variable | Valeur |
|---|---|
| `ms_site` | `par1` |
| `ms_domaine` | `par1.medisphere.internal` |
| `ms_resolveur` | `10.10.20.10` |
| `ms_passerelle` | passerelle du VLAN de l'hôte : son adresse `ansible_host` avec `.1` en dernier octet, **calculée**, jamais écrite hôte par hôte |
| `ms_serveurs_ntp` | liste des sources de temps : `[ms_passerelle]` pour tous ; pour `gw01`, qui est la source de temps du lab (M00-E31), des serveurs Internet |

- Trousse : `trousse_paquets` (liste commune), `trousse_paquets_role` (outils propres à un rôle, vide par défaut), `trousse_paquets_interdits`. Le routeur reçoit en plus `conntrack` et `ethtool`.

**Travail demandé**

*Partie A — prédire, puis vérifier (bac à sable)*

1. Lis tous les fichiers du bac à sable **sans rien lancer**. Pour `alpha`, `beta` et `gamma`, écris dans `~/m04/e06/notes.md` la valeur de `couleur` que tu prévois avec `ansible all -m ansible.builtin.debug -a var=couleur`. Puis lance la commande et compare.
2. Pour chacune des manipulations suivantes, **prédis d'abord**, puis vérifie (et remets en place après chaque essai) :
   - a. renomme `host_vars/alpha.yml` en `alpha.yml.off` ;
   - b. en plus de (a), renomme `group_vars/socle.yml` ;
   - c. en plus de (b), renomme `group_vars/role_web.yml` ;
   - d. en plus de (c), renomme `group_vars/all.yml` ;
   - e. retour à l'état initial, puis (a) seulement, et ajoute `ansible_group_priority: 10` dans les variables du groupe `role_web` **de l'inventaire** ; puis déplace ce réglage dans `group_vars/role_web.yml`.
3. Lance `ansible-playbook precedence.yml`, puis avec `-e couleur=extra`, puis après avoir renommé `roles/demo/vars/main.yml.off` en `main.yml`. Pour chaque tâche, prédis puis vérifie. Que remarques-tu sur ce que voient les tâches du play **après** l'exécution du rôle ?
4. Résume dans ton journal, en une dizaine de lignes, l'ordre de précédence tel que tu l'as observé, et les deux résultats qui t'ont le plus surpris.

*Partie B — ranger les variables du projet*

5. Sur une branche, déplace les listes de la trousse dans `group_vars/all/main.yml`, crée `group_vars/role_routeur/main.yml` avec les outils du routeur, et fais utiliser au playbook la liste commune **et** celle du rôle. Fais-le dans cet ordre, et observe : ajoute d'abord les fichiers de `group_vars/` **sans** retirer les listes de `vars:` du playbook, et lance `--check --diff --limit gw01`. Pourquoi `conntrack` n'apparaît-il pas ? Retire ensuite les `vars:` du playbook.
6. Ajoute les variables du site du tableau. `ms_passerelle` est calculée à partir d'`ansible_host` ; `ms_serveurs_ntp` réutilise `ms_passerelle`, et `gw01` reçoit ses propres sources dans `host_vars/gw01/`.
7. Compare, pour `gw01` puis pour `dns01` :
   ```
   admin@adm01:~/src/ansible$ uv run ansible-inventory --host dns01 | jq '.ms_passerelle, .ms_serveurs_ntp'
   admin@adm01:~/src/ansible$ uv run ansible dns01 -m ansible.builtin.debug -a 'var=ms_serveurs_ntp'
   ```
   Pourquoi les deux commandes ne donnent-elles pas la même chose ? Laquelle utiliser pour diagnostiquer « la variable n'a pas la valeur attendue » ? La seconde se connecte-t-elle à `dns01` ?
8. Journal : pourquoi l'équipe s'interdit-elle un `group_vars/socle/` qui définirait les mêmes variables qu'un `group_vars/role_*/` ? Pourquoi une valeur qui dépend de l'hôte ne doit-elle jamais être dans `vars:` d'un play ?
9. Applique la trousse sur `gw01` (`--check --diff`, puis réel), vérifie `changed=0` partout, commit, MR, fusion.

**Critères de réussite**
- [ ] Les valeurs prédites et observées du bac à sable sont dans `notes.md`, écarts expliqués.
- [ ] `ms_passerelle` vaut 10.10.10.1 pour `adm01` et 10.10.20.1 pour `dns01`, `git01`, `runner01`, sans être écrite hôte par hôte.
- [ ] `ms_serveurs_ntp` vaut `[passerelle]` pour les clients et ne contient aucune adresse du lab pour `gw01`.
- [ ] Le playbook de la trousse ne contient plus de liste ; `conntrack` et `ethtool` sont installés sur `gw01` seulement par l'effet de l'inventaire.
- [ ] Un passage en `--check` de la trousse n'annonce aucun changement ; le tout est sur `main`.

**Vérification** : `lab/bin/check 04 06`

<details><summary>Indice 1</summary>

La page *Using variables* de la documentation donne la liste complète des niveaux de précédence (22 lignes) ; la page *How to build your inventory*, section *How variables are merged*, explique comment se départagent deux **groupes** qui définissent la même variable. Les deux sont nécessaires pour la partie A.
</details>

<details><summary>Indice 2</summary>

Une variable peut contenir une expression Jinja2 qui référence une autre variable : elle n'est évaluée qu'au moment où on la lit, **pour l'hôte concerné**. Pour découper une adresse IP, les méthodes de chaîne de Python (`split`) et les filtres `join` suffisent ; aucune collection supplémentaire n'est nécessaire.
</details>

<details><summary>Indice 3</summary>

`ansible-inventory` montre les variables telles qu'elles sont **écrites** dans l'inventaire, sans les évaluer. Le module `debug` est une action exécutée sur le nœud de contrôle : il évalue les variables pour l'hôte visé sans s'y connecter.
</details>

**Pour aller plus loin** (facultatif) : lis la documentation du réglage `DEFAULT_PRIVATE_ROLE_VARS` et refais l'étape 3 avec `ANSIBLE_PRIVATE_ROLE_VARS=True`. Pourquoi certaines équipes l'activent-elles ?

---

### M04-E07 — Templates Jinja2  `LAB` `★★`

> **Ticket SEC-507** — *De : Sophie Laurent* — *Copie : Nadia Roussel, Karim Benali*
> Lors de l'audit, chaque connexion à une machine doit afficher : où l'on est (nom complet, adresse), le rôle de la machine, l'environnement, qu'elle est gérée par Ansible, l'avertissement légal, et qui appeler. Nadia veut aussi la liste des runbooks du rôle quand il y en a. Karim demande en plus que chaque machine **sache elle-même** son rôle : un fait local que nos scripts et Ansible pourront lire sans interroger l'inventaire.

**Objectifs pédagogiques**
- Écrire des templates Jinja2 : variables, filtres, conditions, boucles, commentaires, contrôle des espaces.
- Produire un fichier structuré (JSON) sans risque d'erreur de syntaxe.
- Garder un template idempotent : rien qui change à chaque passage.
- Créer et relire un fait local (`/etc/ansible/facts.d/`).

**Prérequis** : M04-E06.
**Durée indicative** : 2 h.

**Contexte technique**
- Playbook : `playbooks/identite-hotes.yml` ; templates dans `playbooks/templates/` (dossier cherché automatiquement à côté du playbook).
- `/etc/motd` de chaque hôte du socle, contenu attendu :
  - en tête, un commentaire qui dit que le fichier est géré par Ansible (projet `plateforme/ansible`) et qu'une modification manuelle sera écrasée ;
  - le site et l'environnement ;
  - une ligne `Hôte : <nom>.par1.medisphere.internal (<adresse>)` ;
  - une ligne `Rôle : <rôle>`, où `<rôle>` est le nom du groupe `role_*` sans son préfixe (`routeur`, `bastion`, `dns`, `gitlab`, `runner`) ;
  - une ligne `Système : <distribution> <version majeure>` ;
  - sur le routeur **seulement**, un avertissement : toute erreur y coupe le lab, et la commande de validation du pare-feu (`nft -c -f /etc/nftables.conf`) ;
  - l'avertissement légal : « Accès réservé aux personnes autorisées. Toute action est journalisée. » ;
  - le contact d'astreinte ;
  - les runbooks du rôle, s'il y en a : pour `gitlab`, RB-010 Restaurer GitLab, RB-011 Mettre à jour GitLab, RB-012 Diagnostiquer la forge, RB-013 La forge est en panne.
- Fait local : `/etc/ansible/facts.d/medisphere.fact`, JSON, clés `role`, `site`, `environnement`, `gere_par` (`plateforme/ansible`).
- Nouvelles variables dans `group_vars/all/main.yml` : `ms_environnement` (`lab`), `ms_role` (calculée à partir des groupes de l'hôte, `aucun` si aucun groupe `role_*`), `ms_gere_par` (texte de l'en-tête), `ms_contact_astreinte`, `ms_runbooks` (dictionnaire rôle → liste de runbooks).

**Travail demandé**
1. Écris `motd.j2` par petites étapes. Pour voir le résultat sans rien écrire sur un hôte, rends-le en simulation :
   ```
   admin@adm01:~/src/ansible$ uv run ansible gw01,git01 -m ansible.builtin.template \
       -a 'src=playbooks/templates/motd.j2 dest=/etc/motd' --check --diff
   ```
   Cette commande sans `-b` se connecte-t-elle aux hôtes ? Et les faits (`ansible_facts['distribution']`) sont-ils disponibles en ad hoc ? Trouve comment faire pour que la ligne « Système » s'affiche.
2. `ms_role` : construis l'expression à partir de `group_names`. Teste-la avec `ansible socle -m ansible.builtin.debug -a 'var=ms_role'`.
3. Contrôle des espaces : place une condition `{% if %}` indentée au milieu du texte et regarde les lignes vides ou les espaces parasites dans le `--diff`. Le module `template` active-t-il `trim_blocks` ? `lstrip_blocks` ? Choisis une façon d'écrire et applique-la partout.
4. En-tête : la documentation d'Ansible propose la variable `ansible_managed`. Regarde ce que dit `uv run ansible-config list` du réglage `DEFAULT_MANAGED_STR`, et décide comment produire ton en-tête (filtre `comment`).
5. Écris `medisphere.fact.j2`. Pourquoi ne pas écrire le JSON « à la main » avec des guillemets et des virgules autour des variables ? Quel mode donner au fichier, et pourquoi ce choix change-t-il la façon dont `setup` le lit ?
6. Écris le playbook : motd, dossier des faits locaux, fait local, puis relecture des faits locaux et contrôle (`assert`) que le fait relu correspond à `ms_role`. Les faits ont été collectés **avant** l'écriture du fichier : comment les relire sans tout recollecter ? Comment faire pour que le contrôle ne fasse pas échouer un `--check` ?
7. Déploie (`--check --diff`, `--limit runner01`, puis tout le socle). Connecte-toi à `gw01` et à `git01` pour lire le résultat.
8. Expérience : ajoute dans `motd.j2` la date de génération (`{{ now() }}` ou un fait `ansible_date_time`). Lance deux fois. Que devient l'idempotence ? Retire-la.
9. `uv run ansible socle -m ansible.builtin.setup -a 'filter=ansible_local'` : où apparaît ton fait ? Sous quel nom le liras-tu dans un playbook, avec la configuration du projet ?
10. Commit, MR, fusion.

**Critères de réussite**
- [ ] `/etc/motd` de chaque hôte du socle contient son nom complet, une ligne `Rôle : <rôle>` juste, l'en-tête « géré par Ansible » ; l'avertissement du routeur n'apparaît que sur `gw01` ; les runbooks de la forge apparaissent sur `git01`.
- [ ] `/etc/ansible/facts.d/medisphere.fact` est un JSON valide, non exécutable, dont la clé `role` est juste, et Ansible le relit dans ses faits.
- [ ] Un passage en `--check` du playbook n'annonce aucun changement.
- [ ] Le playbook et ses templates sont sur `main`.

**Vérification** : `lab/bin/check 04 07`

<details><summary>Indice 1</summary>

En ad hoc, Ansible ne collecte aucun fait : seules les variables d'inventaire sont disponibles. Un module de collecte lancé juste avant (dans un playbook) ou le cache de faits les rendent disponibles ; pour un essai rapide, un mini-playbook de deux tâches suffit.
</details>

<details><summary>Indice 2</summary>

`group_names` est la liste des groupes de l'hôte. Les filtres `select('match', …)`, `map('regex_replace', …)`, `first` et `default` permettent de passer de `['role_gitlab', 'socle']` à `gitlab` en une expression. Pense au cas d'une liste vide.
</details>

<details><summary>Indice 3</summary>

Un fichier de `/etc/ansible/facts.d/` dont le nom finit par `.fact` est **exécuté** s'il est exécutable (sa sortie doit être du JSON), sinon **lu** comme du JSON ou de l'INI. Pour produire du JSON sûr, construis un dictionnaire Jinja2 et passe-le à un filtre de sérialisation.
</details>

**Pour aller plus loin** (facultatif) : affiche aussi la bannière avant l'authentification SSH (`Banner` de `sshd_config`) : quel fichier, quel risque pour les clients automatiques, et pourquoi ce sera plutôt le travail du rôle `ssh_durci` (E11) ?

---

### M04-E08 — Handlers et validation avant rechargement  `LAB` `★★`

> **Ticket PLAT-508** — *De : Nadia Roussel* — *Copie : Karim Benali*
> Mardi soir, quelqu'un a modifié à la main le `chrony.conf` de `dns01` pour essayer une option, avec une faute de frappe, puis redémarré : chrony ne repartait plus et personne n'a regardé. Deux jours plus tard, le serveur avait une minute d'avance et les jetons de la forge expiraient bizarrement. Je veux que la configuration du temps des clients du socle soit faite par Ansible, **validée avant d'être installée**, que chrony ne redémarre **que** si quelque chose a changé, et que le playbook vérifie à la fin que l'heure est bien synchronisée. Ne touche pas à `gw01` : c'est le serveur de temps.

**Objectifs pédagogiques**
- Déclencher une action seulement en cas de changement : `notify`, handlers, `meta: flush_handlers`.
- Valider un fichier de configuration **avant** de l'installer (`validate`).
- Comprendre ce qui arrive aux handlers quand le play échoue, et s'en protéger.
- Vérifier l'effet d'un changement à la fin d'un playbook, sans fausser son idempotence.

**Prérequis** : M04-E06 (`ms_serveurs_ntp`), M04-E07 (`ms_gere_par`) ; M00-E31 (chrony dans le lab).
**Durée indicative** : 2 h.

**Contexte technique**
- Cible : tout le socle **sauf** le routeur (`adm01`, `dns01`, `git01`, `runner01`). `gw01` garde sa configuration de serveur (M00-E31).
- État actuel des clients (M00-E31, M01) : lignes `pool` commentées dans `/etc/chrony/chrony.conf`, source déclarée dans `/etc/chrony/sources.d/lab.sources`.
- État voulu : `/etc/chrony/chrony.conf` produit par un template à partir du fichier de Debian 13 (chrony 4.6), avec pour seules sources celles de `ms_serveurs_ntp` ; plus aucune source déposée ailleurs (le fichier `lab.sources` disparaît, et aucune source ne doit pouvoir être ajoutée sans passer par Ansible).
- Playbook : `playbooks/chrony-client.yml`, template `playbooks/templates/chrony.conf.j2`. En fin de playbook, une vérification attend que chrony soit synchronisé (au plus une minute environ).
- Brouillons : `~/m04/e08/`.

**Travail demandé**
1. Récupère la configuration actuelle d'un client sans te connecter à la main :
   ```
   admin@adm01:~/src/ansible$ uv run ansible dns01 -b -m ansible.builtin.fetch -a 'src=/etc/chrony/chrony.conf dest=~/m04/e08/'
   ```
   Où le fichier est-il rangé, et pourquoi ce chemin ? Compare-le à celui de Debian (`/usr/share/doc/chrony/` ou les sources du paquet) : qu'est-ce que M00-E31 avait modifié ?
2. Trouve dans `man chronyd` une option qui lit la configuration, signale les erreurs et s'arrête sans démarrer de service. Teste-la **à la main** sur `dns01`, sur une copie du fichier dans `/tmp`, avec puis sans une faute de frappe dans une directive. Note les codes retour.
3. Écris `chrony.conf.j2` (en-tête `ms_gere_par`, sources tirées de `ms_serveurs_ntp`, directives de Debian conservées sauf celles qui iraient contre l'état voulu ; justifie chaque directive retirée dans un commentaire).
4. Écris le playbook : contrôle qu'il existe au moins une source, installation de chrony, template **validé** avant installation (garde aussi une copie de l'ancien fichier), suppression de `lab.sources`, un **handler** qui redémarre chrony, puis la vérification finale de synchronisation (lis `chronyc help` : une commande attend justement la synchronisation). Pourquoi la vérification doit-elle venir **après** le redémarrage, et comment l'obtenir sans attendre la fin du play ? Comment faire pour qu'elle ne compte jamais comme un changement, et qu'elle s'exécute aussi en `--check` ?
5. Déploie sur `runner01` : `--check --diff`, puis réel. Observe le handler dans la sortie. Relance : le handler s'exécute-t-il ? Pourquoi ?
6. **Validation.** Introduis une faute de frappe dans une directive du template (par exemple `makestp`) et relance sur `runner01`. Que dit Ansible ? Le fichier en place a-t-il changé ? chrony tourne-t-il toujours (`systemctl is-active chrony`, `chronyc -n tracking`) ? Corrige le template.
7. **Handlers et échec.** Sur `runner01`, ajoute temporairement une source de test (`-e '{"ms_serveurs_ntp": ["10.10.20.1", "10.10.10.1"]}'`) **et** une tâche `ansible.builtin.fail` placée juste avant `meta: flush_handlers`. Lance. Puis retire la tâche `fail` et relance avec la même source de test.
   - Que contient `/etc/chrony/chrony.conf` ? Que montre `chronyc -n sources` ? Pourquoi ?
   - Comment ce piège arrive-t-il en vrai, et quelles sont les deux façons de s'en protéger (une option de ligne de commande, un mot-clé de play) ?
   - Remets `runner01` dans l'état normal (sans la source de test) et vérifie `chronyc -n sources`.
8. Déploie sur les quatre clients, relance pour vérifier `changed=0`, vérifie `chronyc -n sources` sur chacun et sur `gw01` (qui ne doit pas avoir bougé). Commit, MR, fusion.

**Critères de réussite**
- [ ] Sur `adm01`, `dns01`, `git01`, `runner01` : `chrony.conf` porte l'en-tête « géré par Ansible », déclare la passerelle du VLAN comme seule source, aucune ligne de pool ; `lab.sources` n'existe plus ; `chronyc -n sources` montre une seule source, sélectionnée (`^*`).
- [ ] Le playbook valide la configuration avec `chronyd` avant de l'installer et redémarre chrony par un handler ; il ne vise pas `gw01`.
- [ ] `gw01` est toujours synchronisé et sert toujours le lab.
- [ ] Un passage en `--check` n'annonce aucun changement et confirme la synchronisation.
- [ ] `notes.md` explique le résultat des étapes 6 et 7.

**Vérification** : `lab/bin/check 04 08`

<details><summary>Indice 1</summary>

Dans `man chronyd`, cherche une option qui « imprime la configuration et s'arrête ». Combinée avec l'option qui désigne le fichier de configuration à lire, elle fait un excellent contrôle de syntaxe. Dans `validate`, `%s` est remplacé par le chemin du fichier temporaire rendu par le template.
</details>

<details><summary>Indice 2</summary>

Un handler notifié ne s'exécute pas tout de suite : par défaut, à la fin de la section de tâches du play. `ansible.builtin.meta: flush_handlers` les exécute à l'endroit où tu la places. Pour une commande de lecture, deux mots-clés de tâche règlent son statut et son comportement en simulation.
</details>

<details><summary>Indice 3</summary>

Quand le play échoue sur un hôte, les handlers notifiés pour cet hôte sont abandonnés. Au passage suivant, le template n'a plus rien à changer : rien ne notifie plus le handler. Cherche dans la documentation des handlers la section sur leur comportement en cas d'échec.
</details>

**Pour aller plus loin** (facultatif) : chrony sait relire ses sources sans redémarrer (`chronyc reload sources`) quand elles sont dans un `sourcedir`. Écris une variante avec deux handlers (redémarrage si `chrony.conf` change, rechargement si seules les sources changent) et le mot-clé `listen`. Le gain vaut-il la complexité ?

---

### M04-E09 — Questions : précédence et nouveautés d'ansible-core  `Q` `★★`

> **Ticket PLAT-509** — *De : Karim Benali*
> Avant de passer aux rôles, on vérifie que les bases sont solides. Et comme la moitié des exemples que tu trouveras sur Internet ont été écrits avant ansible-core 2.19, je veux que tu saches reconnaître ce qui ne marche plus, et pourquoi. Par écrit, sans exécuter : tu as tout pratiqué.

**Objectifs pédagogiques**
- Raisonner sur la précédence des variables dans des cas réalistes.
- Connaître les changements de comportement d'ansible-core 2.19 à 2.21 qui touchent les playbooks, et savoir corriger le code ancien.

**Prérequis** : M04-E06, M04-E07, M04-E08.
**Durée indicative** : 1 h (+ 30 min d'auto-correction).

**Travail demandé**

Réponds aux 15 questions. Pour les QCM, justifie ton choix.

*Précédence*

1. Avec l'inventaire ci-dessous (tous les fichiers sont voisins de `hosts.yml`), quelle valeur de `ntp` voient `web1`, `web2` et `db1` ? Justifie chaque cas.
   ```yaml
   # hosts.yml
   all:
     children:
       web:
         hosts: { web1: {}, web2: { ntp: "inventaire-hote" } }
       prod:
         vars: { ntp: "inventaire-prod" }
         hosts: { web1: {}, db1: {} }
   # group_vars/all.yml   →  ntp: "gv-all"
   # group_vars/web.yml   →  ntp: "gv-web"
   # host_vars/db1.yml    →  (vide)
   ```

2. Un play déclare `vars: { ntp: "play" }` et cible `web1`, qui a `ntp: "hv"` dans `host_vars/web1.yml`. Quelle valeur voit une tâche du play ? Lucas trouve ça « illogique : la valeur de l'hôte est plus précise ». Que lui réponds-tu, et quelle règle de rangement en tires-tu ?

3. Un rôle `ntp_client` a `ntp_serveurs` dans `defaults/main.yml` ; un autre rôle, `durcissement`, a `ntp_serveurs` dans `vars/main.yml` et s'exécute **avant** dans le même play. Quelle valeur voit `ntp_client` ? Quel défaut de conception révèle cette situation ?

4. *(QCM)* Tu lances `ansible-playbook site.yml -e paquets=[htop,jq]`. Quel est le type de `paquets` dans les tâches ?
   - A. Une liste de deux chaînes
   - B. Une chaîne de caractères
   - C. Une erreur de syntaxe à l'analyse de la ligne de commande
   - D. Une liste, seulement si la variable est déjà définie comme liste ailleurs

5. Un hôte appartient à `zone_a` et `zone_b`, deux groupes de même niveau qui définissent tous deux `dns_secondaire`. Quelle valeur gagne par défaut ? Où peux-tu agir pour inverser le résultat, et où **ne peux-tu pas** ? Pourquoi ce piège apparaît-il souvent au moment où on passe d'un inventaire statique avec des sous-groupes à un inventaire dynamique ?

6. Quelle différence entre `ansible-inventory --host web1` et `ansible web1 -m ansible.builtin.debug -a var=ntp` pour une variable qui vaut `"{{ ms_passerelle }}"` ? Laquelle prouve ce que verra un playbook ?

*Nouveautés d'ansible-core (2.19 à 2.21)*

7. Pour chacune de ces conditions, dis si ansible-core 2.21 l'accepte, et sinon pourquoi et comment la corriger (`utilisateurs` est une liste, `activer` vaut la chaîne `"false"`, `resultat` est le résultat enregistré d'une commande) :
   ```yaml
   when: utilisateurs
   when: activer
   when: "{{ version }} == '13'"
   when: resultat.stdout
   when: resultat is changed
   when: ansible_facts['distribution'] == 'Debian'
   ```

8. *(QCM)* Avec la configuration du projet (`inject_facts_as_vars = False`), la tâche `debug: msg="{{ ansible_distribution }}"` :
   - A. Affiche `Debian`, avec un avertissement de dépréciation
   - B. Échoue : la variable n'est pas définie
   - C. Affiche une chaîne vide
   - D. Affiche `Debian` sans avertissement
   
   Et sans réglage, avec ansible-core 2.21 ? Avec ansible-core 2.24 ?

9. Ce code fonctionnait en 2.18 et échoue en 2.19. Explique pourquoi il « fonctionnait », et corrige-le.
   ```yaml
   - ansible.builtin.stat:
       path: /etc/medisphere/active
     register: marqueur
     failed_when: marqueur.exists is false
   ```

10. Pourquoi ansible-core 2.19 n'évalue-t-il plus un template contenu dans une valeur qui vient d'un module (par exemple la sortie d'une commande contenant `{{ … }}`) ? Quel risque de sécurité cette évaluation créait-elle ?

11. Un rôle de Lucas passe `mode: "{{ item.mode | default(omit) }}"` dans une boucle dont certains éléments ont `mode: "{{ omit }}"`. Qu'est-ce qui a changé en 2.19 pour `omit` dans les boucles, et ce code est-il correct ?

12. Le réglage `ansible_managed` de `ansible.cfg` est déprécié. Par quoi le remplaces-tu, et pourquoi la nouvelle façon est-elle plus souple ?

13. Que signifie, pour un module maison (E44), la dépréciation en 2.21 de « l'inférence d'échec à partir d'un `rc` non nul » ? Que doit faire le module à la place ?

14. ansible-core 2.20 exige Python 3.12 sur le nœud de contrôle et 3.9 sur les hôtes gérés. Quelles conséquences pour MédiSphère (Debian 13 partout, et une vieille VM Legacy-RDV sous CentOS 7 avec Python 3.6 à reprendre au module 12) ? Donne deux options pour cette VM.

15. Le projet hérite de 300 playbooks d'InfoGér écrits pour ansible 2.9. Propose une démarche de migration vers ansible-core 2.21 : outils, ordre, critère de fin. Quels réglages de compatibilité existent pour avancer par étapes, et pourquoi ne faut-il pas les laisser en place ?

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 15 questions avant d'ouvrir le corrigé.
- [ ] Tu as noté chaque réponse avec la grille (0, 1 ou 2 points) et calculé ton score sur 30.
- [ ] Pour chaque erreur sur la précédence, tu as reproduit le cas dans le bac à sable de E06 pour le voir de tes yeux.

<details><summary>Indice 1</summary>

Pour la précédence, raisonne en deux temps : d'abord la **catégorie** de chaque source (variables de l'inventaire fichier, `group_vars`, `host_vars`, play…), ensuite, entre groupes, leur **profondeur** puis leur **nom**. La catégorie l'emporte toujours sur la profondeur.
</details>

<details><summary>Indice 2</summary>

Les guides de portage d'ansible-core 2.19, 2.20 et 2.21 répondent à presque toutes les questions de la seconde partie. Le premier est long : lis au moins les sections *Playbook*, *Engine* et *Plugins*.
</details>

**Pour aller plus loin** (facultatif) : lis la section *Command Line* et *Deprecated* des notes de version de la prochaine version d'ansible-core (2.22) et liste ce qui toucherait le projet.
