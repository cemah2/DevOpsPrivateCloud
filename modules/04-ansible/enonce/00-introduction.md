# Module 04 — Introduction : gestion de configuration avec Ansible

## Cinq machines, cinq façons de faire

Jeudi, 14 h 05. La réunion de préparation de l'audit HDS vient de se terminer. Sophie a posé une question que personne n'avait vue venir.

> **De** : Claire Morel — Responsable infrastructure
> **À** : toi
> **Cc** : Karim Benali, Sophie Laurent, Nadia Roussel, Lucas Martin
> **Objet** : La configuration du socle passe en code — projet `plateforme/ansible`
>
> Bonjour à tous,
>
> Sophie a demandé tout à l'heure : « Prouvez-moi que toutes vos machines appliquent la même politique SSH, la même source de temps, les mêmes mises à jour de sécurité. » Nous avons cinq VMs dans le socle, configurées à la main en trois mois, et j'ai dû répondre : « Je crois que oui. » Ce n'est pas une réponse d'audit.
>
> Hier soir, Nadia a passé quarante minutes sur un incident parce que `dig` n'était pas installé sur `runner01` et que `tcpdump` manquait sur `gw01`. Chacune de nos machines a sa petite histoire, et personne ne sait la raconter en entier.
>
> Décision : à partir d'aujourd'hui, la configuration du socle est du **code**, dans le projet **`plateforme/ansible`** sur la forge. Relue en MR comme le reste, testée, appliquée par une chaîne traçable, et vérifiée régulièrement pour détecter ce qui dérive. Les images dorées du module 03 donnent une base commune ; Ansible apporte ce qui est propre à chaque rôle, et tient la configuration dans le temps.
>
> Karim fixe les règles techniques ; je le cite : « un rôle qui n'est pas idempotent et testé n'entre pas dans `main` ». Lucas va écrire ses premiers rôles ; tu les reliras. Nadia veut pouvoir appliquer un changement la nuit sans avoir à deviner ce qu'il va faire.
>
> On commence comme d'habitude par un test de positionnement.
> Claire

---

## Ce que tu construis dans ce module

À la fin du module 04 :

- le projet **`plateforme/ansible`** existe sur `git01`, configuré comme tous les projets de la plateforme, avec un **environnement d'exécution reproductible** (ansible-core 2.21, collections épinglées) ;
- un **inventaire** du socle, statique puis **dynamique** (lu dans Proxmox à partir des étiquettes posées au module 02), avec ses `group_vars` et `host_vars` ;
- des **rôles** idempotents : `base` (trousse commune, temps, mises à jour de sécurité, journaux, comptes), `ssh_durci`, `pare_feu` pour `gw01` (la matrice des flux devient du code, rechargée sans risque de se couper), `gitlab_runner`, puis ceux du mini-projet ; une **collection interne** `medisphere.socle` ;
- les secrets dans **Ansible Vault** ;
- une chaîne de qualité : **ansible-lint** en pre-commit et en CI, **Molecule** qui teste chaque rôle sur des VMs jetables clonées de l'image dorée `current` ;
- une exécution **traçable** : `--check --diff` en MR, application par un pipeline protégé ou par **Semaphore UI**, et une **détection de dérive** planifiée ;
- la capacité à diagnostiquer les pannes classiques : hôtes injoignables, variables inattendues, Vault, inventaire vide, configuration qui casse un service.

## Architecture du module

```
                ┌─────────────────── git01 (1004) · 10.10.20.12 ───────────────────┐
                │ GitLab — plateforme/ansible : MR, pipeline (lint, Molecule,       │
                │ --check du socle, application manuelle protégée), dérive (E29)    │
                └──────────────┬──────────────────────────────────▲───────────────┘
                               │ jobs (étiquette shell)            │ clone (clé de déploiement)
       ┌───────────────────────▼─── runner01 (1007) ───┐   ┌──────┴──── sem01 (2041) ─────┐
       │ 10.10.20.15 · CI : ansible-lint, Molecule,     │   │ 10.10.20.41 · Semaphore UI   │
       │ ansible-playbook (clé ansible-ci, E27)         │   │ (E28, environnement M04)     │
       └───────────────┬───────────────────────────────┘   └──────────────┬───────────────┘
                       │ SSH (E27)                                          │ SSH (E28)
┌──────────────────────▼─────────── adm01 (1001) · 10.10.10.10 ───────────▼───────────────────┐
│ ~/src/ansible : uv (.venv : ansible-core 2.21, ansible-lint, Molecule), collections/        │
│ ~/.config/workbook/ : ansible-vault.pass (E12), pve-ansible.env (E13)  · Ansible en local   │
└──────┬───────────────────────────┬─────────────────────────────┬──────────────────────────┘
       │ SSH (admin + sudo)         │ API Proxmox :8006, TLS vérifié│ SSH vers vsandbox (E24)
       ▼                            ▼                               ▼
  gw01 10.10.10.1     pve01 — jeton wb-ansible@pve!ansible   instances Molecule 2045-2049
  dns01 10.10.20.10     (inventaire dynamique, clonage de     (clones de l'image dorée
  git01 10.10.20.12      l'image dorée gold+debian13+current)  current, VNet vsandbox, DHCP)
  runner01 10.10.20.15
```

Ansible ne demande **aucun agent** sur les machines gérées : il se connecte en SSH avec le compte `admin` (sudo sans mot de passe), envoie un petit programme Python par tâche, l'exécute et récupère le résultat. `adm01` se gère lui-même, sans SSH (connexion locale).

### Flux réseau du module

| Flux | Exercice | État |
|---|---|---|
| `adm01` → socle, SSH | dès E03 | existant (MGMT joint tout le lab, M00) |
| `adm01` → `pve01` TCP 8006 | E13 | existant (M00) |
| `adm01` → `vsandbox` SSH (instances Molecule) | E24 | existant (M00) |
| `runner01` → `pve01` TCP 8006, `runner01` → `vsandbox` TCP 22 | E24, E27 | ouverts en M03-E15 |
| `runner01` → `adm01` TCP 22 et `runner01` → `gw01` TCP 22 (chaîne `input`) | E27 | **à ouvrir**, ciblés et commentés |
| `sem01` → socle TCP 22 | E28 | **à ouvrir** sur le modèle de `runner01` |

Tout nouveau flux est ouvert de façon ciblée sur `gw01`, validé (`nft -c -f`) avant rechargement, et reporté dans `docs/socle/matrice-flux.md` de `plateforme/medisphere`. À partir de E17, c'est le rôle `pare_feu` qui écrit `/etc/nftables.conf` : un flux s'ajoute alors **dans le code**, par MR.

## Le projet `plateforme/ansible`

Arborescence visée en fin de module (chaque exercice indique ce qu'il ajoute) :

```
ansible/
├── ansible.cfg                  configuration d'Ansible pour le projet (E02, complétée en E12, E26)
├── pyproject.toml, uv.lock      environnement d'exécution : ansible-core, ansible-lint, Molecule (E02)
├── .python-version              3.13 (Python de Debian)
├── collections/
│   ├── requirements.yml         collections de Galaxy, versions exactes (E02)
│   └── ansible_collections/     installées ici, non versionnées… sauf medisphere/ (E18)
├── inventories/lab/
│   ├── hosts.yml                inventaire statique (E03)
│   ├── proxmox.yml              inventaire dynamique community.proxmox (E13)
│   ├── group_vars/all/          main.yml (E03, E06, E07), vault.yml chiffré (E12)
│   ├── group_vars/role_<rôle>/  spécificités d'un rôle (E06…)
│   └── host_vars/<hôte>/        spécificités d'un hôte (E03, E06…)
├── playbooks/                   trousse-diagnostic.yml (E05), identite-hotes.yml (E07),
│   └── templates/               chrony-client.yml (E08), puis site.yml et les playbooks par rôle
├── roles/                       base, ssh_durci, pare_feu, gitlab_runner… (E10 →)
├── .ansible-lint, .pre-commit-config.yaml, .gitlab-ci.yml   qualité et CI (E02, E20, E27)
└── README.md
```

### Conventions du projet

Elles sont fixées dès maintenant ; les vérifications et les exercices suivants en dépendent.

| Convention | Règle |
|---|---|
| Lancement | Toujours depuis la racine du projet (`cd ~/src/ansible`), par `uv run ansible-…` ou avec le venv activé (`source .venv/bin/activate`) |
| Modules | Nom complet (FQCN) : `ansible.builtin.apt`, `community.proxmox.proxmox_kvm`, jamais `apt` tout court |
| Faits | `ansible_facts['distribution']`, jamais `ansible_distribution` (désactivé dans `ansible.cfg`, E02) |
| Conditions | Expressions **booléennes** sans `{{ }}` : `when: ma_liste \| length > 0`, pas `when: ma_liste` |
| Variables | Préfixe `ms_` pour les données du site (`ms_domaine`, `ms_passerelle`…) ; préfixe du rôle pour les variables d'un rôle (`base_…`, `ssh_durci_…`) |
| Élévation | `become: true` déclaré par chaque play qui en a besoin, jamais globalement |
| Tâches | Chaque tâche et chaque play a un `name:` qui dit **ce qu'on veut obtenir** (« Installer chrony »), pas la commande |
| YAML | Booléens `true`/`false` ; modes de fichiers entre guillemets (`mode: "0644"`) ; fichiers en `.yml` |
| Secrets | Jamais en clair dans le dépôt : Ansible Vault (E12), mot de passe dans `~/.config/workbook/ansible-vault.pass` |

---

## Concepts clés

Une synthèse pour se repérer, pas un cours : les exercices et les liens « Pour aller plus loin » approfondissent.

**Gestion de configuration.** On décrit l'**état attendu** d'une machine (ce paquet est installé, ce fichier a ce contenu, ce service tourne) et un outil fait converger la machine vers cet état. Un bon outil est **idempotent** : appliquer deux fois la même description ne change rien la seconde fois. Ce qui s'écarte de la description sans passer par elle s'appelle la **dérive** ; l'outil sait la détecter (mode simulation) et la corriger (nouvelle application).

**Le modèle d'Ansible.** Un **nœud de contrôle** (ici `adm01`, puis `runner01` et `sem01`) lit un **inventaire** (les hôtes, rangés en groupes, avec leurs variables) et exécute des **playbooks**. Un playbook contient des **plays** (« sur tel groupe d'hôtes ») qui enchaînent des **tâches** ; chaque tâche appelle un **module** (`apt`, `template`, `service`…) avec des paramètres. Ansible **pousse** la configuration en SSH, sans agent ; Puppet ou Salt, eux, reposent sur un agent qui **tire** sa configuration d'un serveur (E32).

**Déclaratif… surtout.** Un module décrit un état (`state: present`) et décide seul s'il y a quelque chose à faire ; c'est ce qui rend un playbook idempotent. Mais un playbook reste une suite ordonnée de tâches, et les modules `command` et `shell` exécutent ce qu'on leur donne, sans savoir si c'est déjà fait : à éviter, ou à encadrer (`creates:`, `changed_when:`).

**Variables et précédence.** Une même variable peut venir d'une vingtaine d'endroits (valeurs par défaut d'un rôle, `group_vars`, `host_vars`, variables de play, faits, `-e`…). Ansible les fusionne pour **chaque hôte**, avec un ordre de précédence précis. C'est la première source de surprises : E06 et E09 y sont consacrés.

**Jinja2.** Les valeurs entre `{{ }}` et les fichiers modèles (*templates*) sont évalués par Jinja2, avec les filtres d'Ansible. Depuis ansible-core 2.19, le moteur de templates a été réécrit (*data tagging*) : il refuse ce qu'il tolérait en silence (conditions non booléennes, `{{ }}` dans un `when`, variables indéfinies masquées). Beaucoup de tutoriels ne fonctionnent plus tels quels : c'est pour ça que les conventions ci-dessus sont strictes.

**Rôles et collections.** Un **rôle** regroupe tâches, handlers, templates, variables par défaut et métadonnées d'une fonction (« serveur DNS », « base commune ») pour la réutiliser. Une **collection** est l'unité de distribution : modules, plugins, rôles, publiés sur Galaxy ou dans un dépôt interne. `ansible-core` ne contient que `ansible.builtin` ; le reste (Proxmox, `community.general`, `ansible.posix`) vient de collections que le projet installe à des versions **fixées**.

**Tester avant d'appliquer.** `ansible-playbook --check --diff` simule une exécution et montre les différences ; `ansible-lint` vérifie le code ; Molecule crée une machine jetable, y applique un rôle, vérifie l'idempotence et le résultat, puis détruit la machine. Rien n'arrive sur le socle sans être passé par là.

**Exécuter de façon traçable.** Lancer Ansible depuis un poste personnel ne laisse pas de trace exploitable. En production, on l'exécute depuis la CI (pipeline protégé, journal conservé) ou depuis un orchestrateur (Semaphore UI ici ; AWX, dont le développement est en pause, est présenté en fiche).

---

## Faits techniques du module

| Élément | Valeur |
|---|---|
| ansible-core | 2.21.x dans l'environnement `uv` du projet ; les corrigés fonctionnent aussi avec la 2.19 de Debian 13 |
| ansible-lint / Molecule | 26.x / 26.x (pilote `default` : création et destruction des instances par tes playbooks) |
| Collections | `community.proxmox` 2.x, `community.general` 13.x, `ansible.posix` 2.x (versions exactes dans `collections/requirements.yml`) |
| Python | 3.13 de Debian sur `adm01` (environnement du projet) ; sur les hôtes gérés, le Python du système `/usr/bin/python3`, désigné dans `ansible.cfg` |
| Connexion | compte `admin`, clé de `adm01` chargée dans l'agent SSH, `sudo` sans mot de passe ; `adm01` en connexion locale ; clés d'hôte **vérifiées** |
| Groupes d'inventaire | `socle` ; `role_routeur` (`gw01`), `role_bastion` (`adm01`), `role_dns` (`dns01`), `role_gitlab` (`git01`), `role_runner` (`runner01`) : les étiquettes Proxmox `socle` et `role-…` du module 02 |
| Compte Proxmox (E13, E24) | `wb-ansible@pve`, jeton `wb-ansible@pve!ansible`, rôle `WBAnsible` ; accès dans `~/.config/workbook/pve-ansible.env` (600) |
| Ansible Vault (E12) | mot de passe dans `~/.config/workbook/ansible-vault.pass` (600), identifiant `lab` |
| VMs du module | 2040-2049, pool `lab`, étiquette `env-m04` : 2041 `sem01` (10.10.20.41, VNet `vinfra`), 2045-2049 instances Molecule (`vsandbox`, DHCP, étiquette `molecule`) |
| Image consommée | template doré étiqueté `gold` + `debian13` + `current` (module 03) |
| Brouillons | `~/m04/eXX/` sur `adm01` (non versionnés) |

### Valeurs à adapter

| Valeur | Signification |
|---|---|
| `<MOI>` | Ton compte GitLab personnel (M01-E05) |
| `<NOEUD>` | Nom du nœud Proxmox de `pve01` |
| `<IP-PVE01>` | Adresse de `pve01` présente dans son certificat (comme `PVE_API_URL`, M00-E17) |

### Variables de `lab/lab.env`

Rien de nouveau : les vérifications utilisent `WB_SRC` (elles cherchent le projet dans `$WB_SRC/ansible` et y lancent Ansible **avec son environnement et sa configuration**), `WB_GITLAB_URL` et `WB_GITLAB_TOKEN_FILE` (projet sur la forge), `WB_PVE_HOST` (état de Proxmox, lu en root sur `pve01`), `WB_DEPOT` (documentation). Elles se connectent aux hôtes avec les alias SSH de `adm01` (`gw01`, `dns01`, `git01`, `runner01`).

---

## Règles du module

1. **`--check --diff` avant tout passage sur le socle**, et lecture du résultat. Un playbook qui n'a jamais tourné se teste d'abord sur un seul hôte (`--limit`), de préférence le moins critique (`runner01`), jamais d'abord sur `gw01`.
2. **Instantané avant un changement risqué** : `ms-snapshot --prefix avant-m04 <VMID>…` (M02-E11) sur les VMs concernées. Un instantané n'est pas une sauvegarde : supprime-le quand le changement est validé.
3. **`gw01` se touche avec un accès de secours ouvert** : console série `qm terminal 1000` depuis `pve01` (ou console noVNC), et une session SSH ouverte en parallèle. Le pare-feu passe sous Ansible en E17 seulement, avec un mécanisme de retour automatique.
4. **Ansible tourne sur `adm01` et gère `adm01`** : une erreur dans un rôle peut casser ton propre poste (sudo, SSH, résolution). Garde un accès à `adm01` par la console Proxmox (`qm terminal 1001`).
5. **On ne désactive jamais la vérification des clés d'hôte** (`host_key_checking = False`, `StrictHostKeyChecking=no`) : une clé qui change est un signal à comprendre, pas un obstacle à contourner.
6. **Aucun secret en clair**, ni dans le dépôt, ni dans une sortie de pipeline, ni dans un ticket. Les tâches qui manipulent un secret portent `no_log: true` (E12).
7. **Nettoie derrière toi** : VMs 2040-2049 détruites en fin d'exercice (sauf `sem01` tant que l'ADR de E31 ne l'a pas tranché), instances Molecule détruites même en cas d'échec.

---

## Préparer `adm01`

Les outils viennent des modules précédents ; il n'y a rien à installer à la main dans ce module (Ansible et ses outils s'installent **dans le projet**, en E02). Vérifie seulement :

```
admin@adm01:~$ uv --version
admin@adm01:~$ python3 --version
admin@adm01:~$ pre-commit --version
admin@adm01:~$ ssh-add -l
```

- `uv` 0.12 et Python 3.13 (module 02), `pre-commit` 4.x (module 01).
- `ssh-add -l` doit lister ta clé `~/.ssh/id_ed25519` : elle est protégée par une phrase de passe (M00-E15) et Ansible, comme les vérifications, ne pose jamais de question. Sans agent chargé, tout échoue en `UNREACHABLE`.
- N'installe **pas** le paquet Debian `ansible` ni `ansible-core` avec `apt` ou `pip` : l'outil de référence est celui du projet, à la version fixée par `uv.lock`. Si `type -a ansible` trouve déjà un `ansible` ailleurs, note d'où il vient : il pourrait masquer celui du projet.

Contrôle d'accès préalable : Ansible se connecte par **adresse IP** (pas par les alias de `~/.ssh/config`), avec le compte `admin`. Chaque adresse doit donc déjà être connue de `~/.ssh/known_hosts` :

```
admin@adm01:~$ for ip in 10.10.10.1 10.10.20.10 10.10.20.12 10.10.20.15; do
>   ssh -o BatchMode=yes admin@$ip 'hostname; sudo -n true && echo sudo-ok'
> done
```

Une ligne en erreur (« Host key verification failed », « Permission denied ») se règle **maintenant**, en comprenant pourquoi (E03 y revient).

---

## Indices, corrigé, vérifications

- Les vérifications se lancent depuis `adm01` : `lab/bin/check 04 <XX>`. Elles lancent `ansible`, `ansible-inventory` et `ansible-playbook` **depuis ta copie de travail**, avec l'environnement du projet, et uniquement en lecture : module `ping`, collecte de faits, module `debug`, et playbooks en mode `--check`. Plusieurs d'entre elles prennent une à deux minutes pour cette raison.
- Une vérification qui lance un playbook en `--check` attend `changed=0` : c'est la preuve que le playbook a été appliqué **et** qu'il est idempotent.
- Les indices sont progressifs : ouvre-les un par un, seulement quand tu bloques.
- Le corrigé (`corrige/`) donne une solution, le *pourquoi*, les alternatives, les pièges et la vision production. Les fichiers complets du projet sont dans `corrige/fichiers/M04-EXX/ansible/`. Même quand ta vérification est verte, lis « Pièges classiques ».
- Les scripts de panne (`corrige/pannes/`) révèlent les causes : ne les lis pas avant d'avoir résolu. Au palier 4, `lab/bin/break 04 XX --annuler` sert aussi à **clore** une panne que tu as réparée : il ne restaure que ce qui est encore dans l'état cassé, sans écraser ta réparation.

## Ordre conseillé

```
E01 ─ E02 ─ E03 ─ E04 ─ E05 ─ E06 ─ E07 ─ E08 ─ E09 ─ palier 2 : E10 (rôle base) …
```

1. **E01** — positionnement, à froid, avant de lire la suite.
2. **E02 → E03** — le projet et son environnement, puis l'inventaire : rien ne marche sans eux.
3. **E04** — manipuler Ansible sans rien écrire : modules, faits, parallélisme.
4. **E05 → E08** — quatre playbooks qui deviennent les briques du rôle `base` en E10 : idempotence, variables, templates, handlers.
5. **E09** — à faire en dernier : il demande d'avoir pratiqué.

Durée indicative du palier 1 : 12 à 15 heures.

## Pour aller plus loin

- Documentation d'Ansible (ansible-core 2.21) : <https://docs.ansible.com/ansible/latest/>
- Guides de portage d'ansible-core 2.19, 2.20, 2.21 (à lire avant toute montée de version) : <https://docs.ansible.com/ansible/latest/porting_guides/porting_guides.html>
- Bonnes pratiques (*Tips and tricks*) : <https://docs.ansible.com/ansible/latest/tips_tricks/index.html>
- ansible-lint : <https://docs.ansible.com/projects/lint/> · Molecule : <https://docs.ansible.com/projects/molecule/>
- Collection `community.proxmox` : <https://docs.ansible.com/ansible/latest/collections/community/proxmox/>
- Semaphore UI : <https://semaphoreui.com/docs/>
