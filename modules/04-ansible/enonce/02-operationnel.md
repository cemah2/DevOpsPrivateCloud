# Module 04 — Palier 2 : Opérationnel

Les playbooks du palier 1 marchent, mais ce sont des fichiers isolés : chacun refait sa propre collecte de faits, ses propres listes, et rien ne dit lequel s'applique à quel hôte. Karim Benali veut des **rôles** : une unité réutilisable, testable, avec un contrat clair, que la CI pourra vérifier et que Molecule pourra tester au palier 3. Ce palier transforme le socle en code, rôle après rôle : la configuration commune (`base`), le durcissement SSH (`ssh_durci`), le runner de CI (`gitlab_runner`) et, en dernier parce que c'est le plus dangereux, le pare-feu de `gw01` (`pare_feu`). En chemin, tu ranges les secrets dans Ansible Vault, tu remplaces l'inventaire statique par celui que Proxmox connaît déjà, tu crées la collection interne de l'équipe, et tu écris le runbook que l'astreinte suivra pour appliquer un changement. Les tickets sont ceux d'une équipe qui reprend la main sur des machines configurées « à la main, chacune un peu différemment ».

> **Avant de commencer.** Ce palier part de l'état de fin du palier 1 : projet `plateforme/ansible` cloné dans `~/src/ansible`, environnement `uv` (`uv sync --locked`), collections installées dans `./collections`, inventaire statique `inventories/lab/hosts.yml`, variables du site `ms_…` dans `group_vars/all/main.yml`, et les playbooks `trousse-diagnostic.yml` (E05/E06), `identite-hotes.yml` (E07) et `chrony-client.yml` (E08). Les commandes se lancent depuis la racine du projet (`admin@adm01:~/src/ansible$`), par `uv run ansible-…`.
>
> **Règles du palier.** Tout passe par une MR sur `plateforme/ansible` (pipeline vert, Conventional Commits). Avant chaque application : `--check --diff`, puis un seul hôte (le moins critique, `runner01`), puis les autres ; `gw01` toujours seul et en dernier. Un instantané avant tout changement risqué (`ms-snapshot --prefix avant-m04 <VMID>…`). Les vérifications (`lab/bin/check 04 XX`) lancent les playbooks en `--check` et attendent `changed=0` : elles ne passent que si ton rôle a été appliqué **et** qu'il est idempotent.

---

### M04-E10 — Premier rôle : `base`  `LAB` `★★`

> **Ticket PLAT-520** — *De : Karim Benali*
> Tes playbooks du palier 1 font le travail, mais on ne réutilise pas un playbook : on réutilise un rôle. Regroupe ce qui doit être vrai sur **toutes** les VMs du socle dans un rôle `base` : la trousse de diagnostic, l'identité de l'hôte, le client de temps. Ajoute ce que l'audit HDS va nous demander et qu'on n'a nulle part de façon homogène : fuseau horaire, journaux qui survivent à un redémarrage, mises à jour de sécurité automatiques, et la liste des clés SSH autorisées pour `admin` — **exactement** celles qu'on a décidées, pas une de plus. Un seul playbook l'applique à tout le socle. Les trois anciens playbooks disparaissent.

**Objectifs pédagogiques**
- Connaître la structure d'un rôle et le rôle de chacun de ses dossiers (`tasks`, `handlers`, `templates`, `defaults`, `vars`, `meta`).
- Choisir entre `defaults/` et `vars/` en fonction de la précédence voulue.
- Écrire un rôle qui fonctionne avec ses seules valeurs par défaut, et qui reprend les données du site quand elles existent.
- Gérer une ressource de façon **exclusive** (les clés autorisées) sans risquer de se verrouiller dehors.

**Prérequis** : M04-E05 à M04-E08.
**Durée indicative** : 3 h.

**Contexte technique**
- Rôle `roles/base/`, appliqué par `playbooks/socle-base.yml` au groupe `socle`. Noms de variables imposés (d'autres exercices et Molecule, en M04-E24, s'en servent) : `base_fuseau_horaire` (`Europe/Paris`), `base_paquets`, `base_paquets_role`, `base_paquets_interdits` (les listes `trousse_…` de E05/E06, renommées), `base_ntp_serveurs`, `base_chrony_client`, `base_admin_cles`.
- Le rôle doit tourner **sans** les variables `ms_…` du projet (une VM de test Molecule n'a que les valeurs par défaut du rôle) : sources de temps = passerelle par défaut de l'hôte, rôle de l'hôte déduit des groupes `role_…`, etc. Quand `ms_serveurs_ntp`, `ms_gere_par`, `ms_role`… existent, il les reprend.
- `gw01` est le serveur de temps du lab (M00-E31) : le rôle ne touche pas à son chrony (`chrony-client.yml` l'excluait déjà).
- Fichiers de l'image dorée à reprendre **sous les mêmes noms** (M03-E09) : `/etc/systemd/journald.conf.d/50-medisphere.conf`, `/etc/apt/apt.conf.d/20auto-upgrades` et `/etc/apt/apt.conf.d/52medisphere-unattended-upgrades` (sécurité seulement, jamais de redémarrage automatique). Les VMs issues de l'image dorée ont aussi un service `ms-ntp-passerelle` qui recalcule la source de temps au démarrage.
- Clés autorisées : la clé publique de `admin@adm01` (`~/.ssh/id_ed25519.pub`) partout, sauf sur `adm01` où c'est la clé de **ton poste** (connexion par le VPN, M00-E16) ; Ansible gère `adm01` en connexion locale. Range-les dans une variable du site `ms_cles_admin` (une clé publique se versionne).

> ⚠️ **Attention** : une liste de clés **exclusive** retire toute clé qui n'y figure pas. Une liste vide, une variable mal surchargée, une faute dans une clé, et `admin` n'a plus aucune clé : tu perds l'accès SSH (et Ansible avec lui). Applique d'abord à `runner01` seul, avec une session SSH déjà ouverte ; la console reste disponible (`ssh pve01 qm terminal <VMID>`, M00-E11).

**Travail demandé**
1. Génère un squelette (`uv run ansible-galaxy role init --init-path roles base`) et lis-le. Supprime ce dont tu n'as pas besoin. Note dans ton journal (`~/m04/e10/`) : quelle différence de précédence entre `defaults/main.yml` et `vars/main.yml` ? Lequel choisis-tu pour chaque variable de ce rôle, et pourquoi presque jamais `vars/` ?
2. Reprends dans le rôle, un fichier de tâches par thème (`tasks/paquets.yml`, `temps.yml`, `identite.yml`…) assemblés par `tasks/main.yml` : la trousse (E05/E06), l'identité (E07, `motd` et fait local) et le client chrony (E08). Les templates passent dans `templates/`, le handler dans `handlers/`. Renomme les variables `trousse_…` (inventaire compris : `group_vars/role_routeur/`).
3. Décide comment le rôle trouve ses valeurs quand le projet ne les fournit pas (étape « Contexte technique »), et écris-le dans `defaults/main.yml`. Vérifie par un passage `--check --diff --limit dns01` que rien ne change de valeur par rapport au palier 1 (sources de temps, `motd`, fait local). Pourquoi `uv run ansible dns01 -m ansible.builtin.debug -a var=base_ntp_serveurs` ne t'aide-t-il pas ici ?
4. Ajoute : le fuseau horaire, le journal persistant (avec un plafond d'espace), les mises à jour de sécurité automatiques. Réponds : pourquoi reprendre exactement les noms de fichiers de l'image dorée ? Que se passerait-il sur une VM issue de l'image avec d'autres noms ?
5. Ajoute la gestion des clés autorisées de `admin`. Décide ce que fait le rôle quand la liste est vide, et justifie-le.
6. Écris `playbooks/socle-base.yml`. Puis, dans l'ordre : `--check --diff --limit runner01`, lecture du diff, application sur `runner01`, nouvelle connexion SSH (`ssh -o ControlPath=none runner01 true`), second passage ; puis le reste du socle.
7. Retire `trousse-diagnostic.yml`, `identite-hotes.yml` et `chrony-client.yml` du projet. MR, pipeline vert, fusion.

**Critères de réussite**
- [ ] `roles/base` (tâches, handlers, templates, `defaults`, `meta`) et `playbooks/socle-base.yml` sont sur `main` ; les trois playbooks du palier 1 n'y sont plus, ni aucune variable `trousse_…`.
- [ ] Sur les cinq VMs : fuseau `Europe/Paris`, journal persistant, mises à jour de sécurité automatiques actives (`apt-config dump`), fait local `medisphere` lisible.
- [ ] `admin` a exactement les clés déclarées ; tu te connectes toujours à `adm01` depuis ton poste.
- [ ] `chronyc -n sources` : chaque client est synchronisé sur sa passerelle ; `gw01` sert toujours le temps au lab.
- [ ] Un second passage de `socle-base.yml` donne `changed=0` sur les cinq hôtes.

**Vérification** : `lab/bin/check 04 10` (les vérifications de M04-E05 à E08 ne passent plus après cet exercice : leurs playbooks n'existent plus, c'est normal.)

<details><summary>Indice 1</summary>

`ansible-doc ansible.builtin.import_tasks` et `include_tasks` : l'un est lu à l'analyse du playbook, l'autre à l'exécution. Lequel permet que `--list-tasks` et `--tags` voient toutes les tâches du rôle ? Pour les clés : `ansible-doc ansible.posix.authorized_key`, option `exclusive`, et ce qu'attend le paramètre `key` quand il y a plusieurs clés.
</details>

<details><summary>Indice 2</summary>

Une variable de `defaults/` peut elle-même être un template : sa valeur est calculée au moment où on s'en sert, pour chaque hôte. Le filtre `default()` permet de reprendre une variable du projet si elle existe, une autre valeur sinon.
</details>

<details><summary>Indice 3</summary>

Si le second passage n'est pas à `changed=0`, cherche une tâche `command` sans `changed_when`, un template qui contient une date, ou un fichier que deux tâches écrivent différemment. `--diff` sur le second passage montre ce qui change.
</details>

**Pour aller plus loin** (facultatif) : lis la documentation des *role argument specs* (M04-E15 s'en sert) et la page « Roles » de la documentation d'Ansible (rôles dépendants, `allow_duplicates`). Compare avec la structure d'une collection (M04-E18).

---

### M04-E11 — Rôle `ssh_durci`  `LAB` `★★`

> **Ticket SEC-521** — *De : Sophie Laurent*
> J'ai lancé `sshd -T` sur les cinq VMs du socle : cinq configurations différentes. `gw01` a un fichier posé à la main au M00, les VMs de l'image dorée en ont deux, les autres aucun. Pour l'audit, je veux **une** politique SSH, la même partout, appliquée par Ansible et prouvée sur la configuration **effective** : root refusé, clés uniquement, peu d'essais, pas de transfert de session, journalisation de la clé utilisée. Seule exception : le bastion, qui doit pouvoir servir de rebond. Et je ne veux pas qu'un changement de cette politique puisse couper SSH.

**Objectifs pédagogiques**
- Gérer un fichier dans un dossier `*.d/` en comprenant l'ordre de lecture et la règle « première valeur gagnante » de sshd.
- Valider un fichier **avant** de le poser (`validate:`), puis la configuration complète avant de recharger.
- Distinguer `reload` et `restart`, et savoir ce que chacun fait aux sessions ouvertes.
- Contrôler l'état effectif plutôt que le fichier écrit.

**Prérequis** : M04-E10.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Fichier imposé : `/etc/ssh/sshd_config.d/01-ssh-durci.conf` (des exercices suivants s'en servent). Fichiers déjà présents selon les hôtes : `10-durcissement.conf` (`gw01`, M00-E10, à reprendre puis retirer), `05-durcissement.conf` et `10-medisphere.conf` (image dorée, M03-E09/E13), `50-cloud-init.conf` (cloud-init).
- Politique : `PermitRootLogin no`, clés uniquement (`PasswordAuthentication`, `KbdInteractiveAuthentication` à `no`, `AuthenticationMethods publickey`), `MaxAuthTries 3`, pas de redirection X11 ni d'agent, `PermitUserEnvironment no`, `LogLevel VERBOSE`, sessions inactives fermées. Transfert TCP refusé, **sauf** sur `adm01` (ProxyJump).
- `git01` reçoit le même rôle : les dépôts Git y passent par SSH (compte `git`), ils doivent continuer de fonctionner.
- Variables imposées : `ssh_durci_options` (dictionnaire de directives supplémentaires), `ssh_durci_fichiers_obsoletes` (fichiers à retirer), `ssh_durci_utilisateurs_refuses` (liste pour `DenyUsers`, vide par défaut, utilisée en E12).
- Service : `ssh` sur Debian 13.

> ⚠️ **Attention** : une directive inconnue ou mal écrite, et sshd refuse de démarrer **au prochain redémarrage** (M04-E40 en fait une panne). Garde une session ouverte sur l'hôte pendant les essais, et la console à portée de main.

**Travail demandé**
1. Sur chaque hôte, relève la configuration effective : `sudo sshd -T | sort > ~/m04/e11/<hôte>.avant`. Compare-les deux à deux. Quelle directive diffère, et quel fichier l'a fixée ? Explique l'ordre de lecture : `Include` en tête de `sshd_config`, ordre alphabétique des fichiers, première valeur gagnante (`man sshd_config`).
2. Écris le rôle : un template pour le fichier, posé **seulement s'il est valide** ; un handler qui revalide la configuration complète puis **recharge** sshd ; un contrôle final de la configuration effective. Les anciens fichiers de `gw01` sont retirés, mais seulement une fois le nouveau en place.
3. Ajoute `ssh_durci` à `socle-base.yml` avec l'étiquette `ssh`. Applique sur `runner01`, ouvre une **nouvelle** connexion (`ssh -o ControlPath=none runner01 true`), puis le reste du socle. Vérifie depuis ton poste que tu passes toujours par `adm01` en rebond (`ssh -J admin@10.10.10.10 admin@10.10.20.12 true`).
4. Prouve la validation : dans une branche, mets une faute de frappe dans `ssh_durci_options` (par exemple `{PermitRootLogn: "no"}`), lance sur `runner01` et lis l'erreur. Le fichier en place a-t-il changé ? Annule.
5. Réponds dans ton journal : que contrôle `sshd -t -f <fichier>` que ne contrôle pas `sshd -t`, et inversement ? Pourquoi `reload` ne coupe-t-il pas ta session Ansible, et qu'en serait-il avec `restart` ? Pourquoi le préfixe `01-` ?

**Critères de réussite**
- [ ] `sudo sshd -T` donne, sur les cinq hôtes, `permitrootlogin no`, `passwordauthentication no`, `kbdinteractiveauthentication no`, `authenticationmethods publickey`, `maxauthtries 3`, `x11forwarding no`, `allowagentforwarding no`, `loglevel VERBOSE`.
- [ ] `allowtcpforwarding yes` sur `adm01` seulement ; le rebond par `adm01` fonctionne.
- [ ] `gw01` n'a plus `10-durcissement.conf` ; `sshd -t` passe partout ; un `git clone` en SSH depuis `adm01` vers `git01` fonctionne toujours.
- [ ] Un fichier invalide est refusé avant d'être posé.
- [ ] `socle-base.yml --check --tags ssh` : `changed=0` partout.

**Vérification** : `lab/bin/check 04 11`

<details><summary>Indice 1</summary>

`ansible-doc ansible.builtin.template`, option `validate` : la commande reçoit le chemin du fichier **candidat** (`%s`), pas celui du fichier final. Que vaut alors `sshd -t -f %s` ?
</details>

<details><summary>Indice 2</summary>

Un handler peut porter `listen:` : plusieurs handlers répondent à la même notification, dans leur ordre de définition. Le contrôle final doit voir la configuration rechargée : regarde `meta: flush_handlers`.
</details>

<details><summary>Indice 3</summary>

`sshd -T` affiche les mots-clés en minuscules et les valeurs telles qu'interprétées. Pour un contrôle en `--check`, rien n'a été rechargé : un contrôle de l'état effectif n'a de sens qu'en exécution réelle (`ansible_check_mode`).
</details>

**Pour aller plus loin** (facultatif) : ajoute les listes d'algorithmes (`KexAlgorithms`, `Ciphers`, `MACs`) par `ssh_durci_options`, filtrées comme en M03-E13 par ce que la version d'OpenSSH connaît (`ssh -Q`) ; compare le résultat de `ssh-audit` avant et après. Le module 06 remplacera les clés individuelles par des certificats SSH.

---

### M04-E12 — Ansible Vault  `LAB` `★★`

> **Ticket SEC-522** — *De : Sophie Laurent* — *Copie : Nadia Roussel*
> Nadia veut un compte de secours sur chaque VM pour se connecter à la **console** quand SSH ne répond plus (aujourd'hui, `admin` n'a pas de mot de passe : la console ne sert à rien). D'accord, à trois conditions : le mot de passe ne figure en clair nulle part (ni dépôt, ni journaux de pipeline, ni sortie d'Ansible), le compte ne peut **jamais** se connecter par SSH, et le secret est inscrit au registre avec sa procédure de rotation. Profites-en pour mettre en place une fois pour toutes la façon dont le projet range ses secrets : le jeton du runner suivra (E16).

**Objectifs pédagogiques**
- Chiffrer des variables avec Ansible Vault, avec un identifiant de Vault et un fichier de mot de passe hors du dépôt.
- Organiser variables chiffrées et variables en clair pour que le code reste lisible et cherchable.
- Empêcher un secret d'apparaître dans la sortie d'Ansible (`no_log`) et comprendre ce que Vault ne protège pas.
- Gérer un compte avec mot de passe par son **empreinte**.

**Prérequis** : M04-E10, M04-E11.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Mot de passe du Vault : `~/.config/workbook/ansible-vault.pass` (600, dossier 700), identifiant `lab`. Une copie dans le coffre de l'équipe (pour le lab : ton gestionnaire de mots de passe).
- Variables chiffrées dans `inventories/lab/group_vars/all/vault.yml`, toutes préfixées `vault_` ; référencées en clair dans `group_vars/all/main.yml`. Premier secret : `vault_secours_mdp_hash`.
- Compte `secours` : membre de `sudo` (avec mot de passe), interpréteur `bash`, refusé par sshd (`ssh_durci_utilisateurs_refuses`, E11). Le mot de passe lui-même va dans le coffre de l'équipe et nulle part ailleurs.
- Empreinte : `mkpasswd` (paquet `whois`) sait produire une empreinte `yescrypt` (format par défaut de Debian 13) ou SHA-512. Le filtre `password_hash` d'Ansible demande `passlib` sous Python 3.13 (le module `crypt` a été retiré de Python).
- Registre des secrets : `docs/socle/registre-secrets.md` dans `plateforme/medisphere` (M01).

**Travail demandé**
1. Crée le fichier de mot de passe du Vault (mot de passe long, aléatoire ; regarde `openssl rand`), avec les bons droits. Déclare l'identité `lab` dans `ansible.cfg`. Vérifie avec `uv run ansible-config dump --only-changed`.
2. Génère le mot de passe du compte de secours et son empreinte **sans** que le mot de passe passe dans l'historique du shell ni dans un argument visible par `ps`. Range le mot de passe dans le coffre, l'empreinte dans `vault.yml` (`uv run ansible-vault create …`). Regarde la première ligne du fichier obtenu.
3. Référence la variable chiffrée dans `main.yml` et ajoute au rôle `base` la gestion du compte. Ajoute `secours` aux utilisateurs refusés par sshd.
4. Lance le rôle sur `runner01` avec `-v`, une fois **sans** `no_log` (dans une branche jetable), une fois avec. Que voit-on dans le premier cas ? Supprime cette branche.
5. Compare les deux façons de chiffrer : un fichier entier (`ansible-vault create`) ou une valeur dans un fichier en clair (`ansible-vault encrypt_string`). Choisis pour le projet, et justifie en trois lignes (relecture des MR, `grep`, outils qui lisent le YAML comme `check-yaml` de pre-commit).
6. Applique au socle. Teste le compte depuis la console de `dns01` (`ssh pve01 qm terminal 1002`, puis `Ctrl+O` pour sortir), puis vérifie qu'une connexion SSH avec ce compte est refusée.
7. Inscris au registre : le mot de passe du Vault et le compte `secours` (emplacement, propriétaire, rotation). Réponds : si `ansible-vault.pass` est perdu, que perds-tu ? S'il fuit, que fais-tu (ordre des actions) ?

**Critères de réussite**
- [ ] `vault.yml` commence par `$ANSIBLE_VAULT;1.2;AES256;lab`, sur `main` et dans **toutes** les versions de son historique.
- [ ] Aucune variable `vault_…` n'est définie ailleurs que dans `vault.yml` ; `main.yml` dit où chacune sert.
- [ ] Le mot de passe du Vault est en 600, hors du dépôt, et `uv run ansible-vault view …` fonctionne sans question.
- [ ] Compte `secours` sur les cinq VMs, avec mot de passe, dans `sudo`, refusé par sshd (`sshd -T | grep denyusers`) ; connexion console réussie.
- [ ] Aucune empreinte ni mot de passe dans la sortie d'un passage, même en `-v`.
- [ ] Les deux secrets sont au registre.

**Vérification** : `lab/bin/check 04 12`

<details><summary>Indice 1</summary>

`ansible-config list` : cherche `VAULT_IDENTITY_LIST` et la forme `identifiant@source`. Pour générer sans écho : `read -rs` ; `mkpasswd` lit le mot de passe sur l'entrée standard avec l'option `--stdin`.
</details>

<details><summary>Indice 2</summary>

`no_log` masque le résultat de la tâche, y compris le diff et le message d'erreur (qui recopie souvent les arguments). Sur une boucle, il masque **tout**, noms des éléments compris : sépare ce qui doit rester lisible de ce qui doit être caché.
</details>

<details><summary>Indice 3</summary>

Si `ansible-vault view` demande un mot de passe, l'identité n'est pas lue (mauvais dossier courant : `ansible.cfg` n'est lu que dans le dossier où tu lances la commande). Si l'erreur est « Decryption failed », le fichier a été chiffré avec un autre mot de passe.
</details>

**Pour aller plus loin** (facultatif) : un script client (`vault_identity_list = lab@outils/vault-pass-client.sh`) qui lit le mot de passe dans un gestionnaire au lieu d'un fichier ; M04-E30 sépare les identités par environnement et organise la rotation (`ansible-vault rekey`). Le module 25 remplacera Vault d'Ansible par OpenBao pour les secrets d'exécution.

---

### M04-E13 — Inventaire dynamique Proxmox  `LAB` `★★★`

> **Ticket PLAT-523** — *De : Karim Benali*
> Proxmox sait déjà quelles VMs existent, leur rôle (les étiquettes du module 02) et leur adresse. Maintenir `hosts.yml` à la main, c'est se garantir qu'un jour il mentira. Je veux l'inventaire **tiré de Proxmox**, avec exactement les mêmes groupes que l'inventaire statique, pour pouvoir basculer de l'un à l'autre. Le compte qui lit l'API ne doit rien pouvoir faire d'autre que lire, et rien voir hors du pool `lab`. Et je veux savoir ce qui se passe le jour où l'API ne répond pas.

**Objectifs pédagogiques**
- Configurer un plugin d'inventaire (`community.proxmox.proxmox`) : authentification par jeton, filtres, groupes construits (`keyed_groups`, `groups`) et variables calculées (`compose`).
- Déduire les privilèges Proxmox nécessaires des appels de l'API faits par le plugin.
- Faire cohabiter inventaire statique et dynamique (mêmes groupes, mêmes `group_vars`).
- Rendre l'échec de l'inventaire visible au lieu d'un « rien à faire » silencieux.

**Prérequis** : M04-E03, M04-E12, M02-E05 (étiquettes Proxmox), M00-E17 (jetons).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Compte `wb-ansible@pve`, jeton `wb-ansible@pve!ansible` (séparation des privilèges, date d'expiration), rôle `WBAnsible` sur `/pool/lab`. Ce palier n'a besoin que de **lire** ; les droits de clonage pour Molecule viendront en M04-E24. Si un appel exige un privilège sur un autre chemin, crée un second rôle à part (`WBAnsibleCluster`), le plus étroit possible.
- Accès dans `~/.config/workbook/pve-ansible.env` (600) : les variables d'environnement documentées par le plugin pour l'URL, l'utilisateur, l'identifiant et le secret du jeton. Un fichier, chargé par `set -a; . ~/.config/workbook/pve-ansible.env; set +a`.
- TLS vérifié (`validate_certs` vaut `true` par défaut dans la collection 2.x). L'autorité de `pve01` est dans le magasin système de `adm01` depuis M03-E02. Le plugin d'inventaire passe par la bibliothèque Python `requests`.
- Fichier `inventories/lab/proxmox.yml` (son nom n'est pas libre : lis `ansible-doc -t inventory community.proxmox.proxmox`).
- Groupes attendus : `socle`, `role_routeur`, `role_bastion`, `role_dns`, `role_gitlab`, `role_runner` (étiquettes `socle` et `role-…`). Ni templates, ni VMs d'autres modules, ni instances Molecule (étiquette `molecule`). `ansible_host` = adresse IP ; `gw01`, installé à la main au M00, n'a pas de configuration cloud-init.

**Travail demandé**
1. Lis la documentation du plugin (`uv run ansible-doc -t inventory community.proxmox.proxmox`), puis son code (`collections/ansible_collections/community/proxmox/plugins/inventory/proxmox.py`) : relève **chaque** appel de l'API qu'il fait, avec `want_facts` activé. Dans l'API viewer de Proxmox VE 9, note pour chacun le privilège exigé et sur quel chemin.
2. Sur `pve01`, crée rôle(s), utilisateur, jeton et ACL, par un script rejouable (comme en M03-E02). Justifie chaque privilège dans le script. Vérifie les droits effectifs du jeton sur `/`, `/pool/lab`, `/vms/1002` et sur une VM hors du lab (`pveum user token permissions`).
3. Crée le fichier d'accès. Puis `proxmox.yml` : aucun secret dedans. Construis les groupes, l'adresse de connexion, les filtres. Teste à chaque étape avec `uv run ansible-inventory -i inventories/lab/proxmox.yml --graph`, puis `--host gw01`.
4. Compare les deux inventaires : `--graph` et les variables d'hôte de chacun (`jq`). Ce qui dépend de la source (adresse de `gw01`, connexion locale de `adm01`) doit venir de `host_vars/`, commun aux deux.
5. Fais de l'inventaire dynamique l'inventaire par défaut dans `ansible.cfg`. `hosts.yml` reste, pour le secours.
6. Expériences, résultat dans ton journal : (a) décharge le fichier d'accès (`unset PROXMOX_TOKEN_SECRET`) et lance `uv run ansible-playbook playbooks/socle-base.yml --check ; echo $?` ; (b) retire temporairement l'étiquette `socle` de `runner01` dans Proxmox et regarde le graphe ; (c) remets tout. Que retiens-tu de (a) ? Règle `ansible.cfg` pour que (a) soit une erreur.
7. Inscris le jeton au registre des secrets.

**Critères de réussite**
- [ ] Le jeton voit les VMs du pool `lab` et rien d'autre ; il n'a aucun droit de modification ; sur `/`, seulement ce que le plugin exige.
- [ ] `uv run ansible-inventory --graph` (sans `-i`) donne les mêmes groupes et les mêmes hôtes que `hosts.yml`, sans template ni VM étrangère au socle.
- [ ] `ansible_host` vaut l'adresse IP de chaque hôte, `gw01` compris ; `uv run ansible dns01 -m ansible.builtin.ping` répond.
- [ ] `proxmox.yml` ne contient aucun secret ; le fichier d'accès est en 600.
- [ ] Un inventaire illisible fait échouer `ansible-playbook` (code non nul).

**Vérification** : `lab/bin/check 04 13`

<details><summary>Indice 1</summary>

Le premier appel du plugin n'est pas sur une VM. Regarde aussi quelle bibliothèque fait les requêtes HTTPS, et comment **elle** trouve les autorités de confiance : sa documentation cite deux variables d'environnement.
</details>

<details><summary>Indice 2</summary>

`keyed_groups` crée un groupe par valeur d'une clé ; une liste (les étiquettes analysées, disponibles avec `want_facts`) donne un groupe par élément. Un `-` n'est pas valide dans un nom de groupe : transforme la valeur toi-même plutôt que de dépendre du réglage `TRANSFORM_INVALID_GROUP_CHARS`. Avec `want_facts`, la configuration cloud-init `ipconfig0` arrive déjà découpée en dictionnaire.
</details>

<details><summary>Indice 3</summary>

Dans `compose`, une expression qui échoue est ignorée si `strict` est faux : utile pour `gw01`, dangereux pour une faute de frappe. Pour l'expérience (a) : `ansible-config list`, section `[inventory]`.
</details>

**Pour aller plus loin** (facultatif) : le cache d'inventaire (`cache: true`, plugin `jsonfile`) pour ne pas interroger l'API à chaque commande ; `want_facts` a un coût (un appel par VM) : mesure-le avec `time` et `facts_concurrency`. Au module 06, NetBox deviendra la source de vérité et un second inventaire dynamique (`netbox.netbox.nb_inventory`).

---

### M04-E14 — Boucles, conditions et filtres  `LAB` `★★`

> **Ticket SEC-524** — *De : Sophie Laurent*
> L'audit préparatoire a trouvé sur `dns01` et `git01` un compte `infoger` laissé par l'ancien infogérant, et une clé « infoger@legacy » dans les clés autorisées d'`admin`. Je veux que les comptes du socle soient décrits **par des données** : qui existe, qui ne doit plus exister, quelles clés, qui a le droit de se connecter en SSH. Ajouter ou retirer quelqu'un demain, ce doit être une ligne dans l'inventaire, pas une tâche de plus dans le rôle. Et le refus SSH du compte de secours ne doit pas être écrit deux fois.

**Objectifs pédagogiques**
- Piloter un rôle par une liste de dictionnaires : `loop`, `loop_control`, valeurs par défaut par élément.
- Filtrer et transformer des données avec les filtres Jinja2 et d'Ansible (`selectattr`, `rejectattr`, `map`, `combine`, `product`, `unique`, `difference`…).
- Écrire des conditions booléennes sur des faits et des données (ansible-core 2.19+).
- Dériver une variable d'une autre plutôt que de dupliquer une information.

**Prérequis** : M04-E12.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Reproduis d'abord l'héritage de l'infogérant (une fois, depuis `adm01`) : `~/DevOpsPrivateCloud/modules/04-ansible/ressources/M04-E14/semer-heritage-infoger.sh`. Il crée le compte `infoger` (avec une clé autorisée) sur `dns01` et `git01`, et ajoute une clé `infoger@legacy` à `admin`. La partie privée de ces clés est détruite aussitôt : personne ne peut s'en servir.
- Variable imposée : `base_utilisateurs` (liste commune, `group_vars/all/main.yml`). Champs à prévoir : nom, état (présent ou supprimé), commentaire, interpréteur, groupes, empreinte du mot de passe, clés autorisées (exclusives), droit SSH. Une liste vide ne gère aucun compte (instance de test). Prévois aussi des comptes propres à un hôte.
- Les clés de `admin` restent dans `ms_cles_admin` (E10), y compris l'exception de `adm01`.
- L'agent QEMU n'a de sens que dans une VM KVM : le rôle ne doit l'installer que là (une instance de test dans un conteneur, un serveur physique au module 11, n'en veulent pas).

**Travail demandé**
1. Lance le script de la ressource. Constate l'héritage : `getent passwd infoger`, `ssh-keygen -lf ~admin/.ssh/authorized_keys` sur `dns01`.
2. Remplace dans le rôle la gestion du compte `admin` et du compte `secours` (E10, E12) par des tâches qui ne connaissent **aucun** nom de compte et bouclent sur la liste. Chaque élément doit recevoir des valeurs par défaut (état présent, SSH autorisé, aucune clé) complétées par ses propres champs. Le contrôle anti-verrouillage de E10 devient : la liste est cohérente (pas de doublon, états connus) et `admin` y garde au moins une clé.
3. Décris dans `base_utilisateurs` : `admin`, `secours`, et `infoger` à supprimer (avec son dossier personnel).
4. Remplace la liste écrite à la main de `ssh_durci_utilisateurs_refuses` par une expression calculée à partir de `base_utilisateurs`.
5. Rends l'installation de l'agent QEMU conditionnelle (faits `virtualization_role` et `virtualization_type`).
6. Avant d'appliquer, prédis le résultat avec le module `debug` : écris dans un playbook jetable (`~/m04/e14/prevision.yml`, non versionné) une tâche qui affiche, pour chaque hôte, les comptes présents, les comptes supprimés et le nombre de clés de chacun, en une seule expression par information.
7. `--check --diff --tags base_utilisateurs`, lis le diff des clés, applique. Second passage à zéro.
8. Réponds : `loop` ou `with_items` ? À quoi sert `loop_control: label` ? Pourquoi `when: base_utilisateurs` est-il refusé par ansible-core 2.19+, et comment l'écrire ?

**Critères de réussite**
- [ ] Plus de compte `infoger` ni de `/home/infoger` sur `dns01` et `git01` ; plus de clé `infoger@legacy` nulle part.
- [ ] `admin` a exactement le nombre de clés déclarées dans `ms_cles_admin` pour chaque hôte ; `secours` n'a aucune clé autorisée.
- [ ] Les tâches du rôle ne contiennent aucun nom de compte ; aucune boucle `with_…` dans `roles/`.
- [ ] `ssh_durci_utilisateurs_refuses` est calculée et contient `secours`.
- [ ] Second passage `--tags base_utilisateurs` : `changed=0`.

**Vérification** : `lab/bin/check 04 14`

<details><summary>Indice 1</summary>

Ajouter des valeurs par défaut à chaque élément d'une liste : le filtre `combine` fusionne de gauche à droite (`défauts | combine(élément)`). Pour appliquer ça à toute une liste sans boucle `set_fact`, cherche ce que donnent `product` puis `map('combine')`.
</details>

<details><summary>Indice 2</summary>

`selectattr('champ', 'equalto', valeur)` garde les éléments dont le champ vaut la valeur ; `selectattr('champ')` ceux dont le champ est vrai ; `selectattr('champ', 'defined')` ceux qui l'ont. Une tâche de suppression et une tâche de création séparées se lisent mieux qu'une seule tâche à paramètres conditionnels.
</details>

<details><summary>Indice 3</summary>

Une tâche dont **toute** la boucle porte `no_log: true` cache aussi les noms des éléments : réserve-le à la tâche qui manipule l'empreinte. Pour la condition sur une liste : `| length > 0`.
</details>

**Pour aller plus loin** (facultatif) : comptes nominatifs pour l'équipe (un compte par personne, plutôt qu'`admin` partagé) avec la même liste : quelles conséquences pour la traçabilité exigée par HDS, pour le départ d'un collègue, pour `sudo` ? Le module 06 apportera les certificats SSH, et le module 24 l'identité centralisée.

---

### M04-E15 — Gestion d'erreurs : `block`, `rescue`, `assert`  `LAB` `★★`

> **Ticket PLAT-525** — *De : Nadia Roussel*
> Hier soir, pendant tes essais, `runner01` est resté vingt minutes sans heure synchronisée : le passage s'est arrêté en erreur sur l'attente de chrony, **après** avoir posé la nouvelle configuration. Personne n'a rien remis en place, et le message ne disait pas quoi faire. Je veux trois choses : qu'un rôle refuse de démarrer quand on lui donne des valeurs absurdes, qu'un changement qui échoue revienne de lui-même à l'état d'avant, et que le message d'erreur dise à l'astreinte ce qui s'est passé et quoi regarder.

**Objectifs pédagogiques**
- Déclarer le contrat d'entrée d'un rôle (`meta/argument_specs.yml`) et le faire vérifier par Ansible.
- Vérifier des préconditions avec `assert` avant toute modification.
- Structurer un changement risqué en `block` / `rescue` / `always`, avec retour arrière réel.
- Choisir entre `failed_when`, `ignore_errors`, `rescue`, `any_errors_fatal` et `max_fail_percentage`.

**Prérequis** : M04-E10, M04-E14.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Changement à sécuriser : la configuration de chrony du rôle `base` (template, redémarrage, attente de synchronisation par `chronyc waitsync`). Le template sait déjà garder une copie de l'ancien fichier (`backup: true`).
- `ansible_failed_task` et `ansible_failed_result` sont disponibles dans un `rescue`.
- Préconditions du socle : Debian 13, et une adresse de connexion IPv4 du lab (l'inventaire ne doit pas dépendre du DNS).

**Travail demandé**
1. Écris `roles/base/meta/argument_specs.yml` : chaque variable du rôle, son type, ses choix possibles, les champs des comptes. Lis le résultat avec `uv run ansible-doc -t role -r roles base`.
2. Lance `socle-base.yml --check --limit dns01` avec trois valeurs fausses passées en `-e` : `base_chrony_client` à `"peut-etre"`, `base_ntp_serveurs` à `"10.10.20.1"` (une chaîne, pas une liste), `base_paquets` à `{}`. Lesquelles sont refusées, et par quoi ? Explique le cas de la chaîne.
3. Mets la configuration de chrony dans un `block` : vérification des sources (une liste d'adresses ou de noms, sans espace), template, redémarrage **immédiat** si le fichier a changé, attente de la synchronisation. En `rescue` : remettre l'ancien fichier, redémarrer, puis **échouer** avec un message utile à l'astreinte. Ce qui ne doit disparaître qu'en cas de succès (l'ancienne source de M00-E31) est retiré à la fin du bloc.
4. Ajoute à `socle-base.yml` des `pre_tasks` qui vérifient les préconditions du socle, avant les rôles.
5. Provoque l'échec, sur `runner01` seulement : `-e '{"base_ntp_serveurs": ["10.10.20.13"]}'` (aucun serveur de temps à cette adresse). Observe le `rescue`, le message, et l'état de chrony après coup (`chronyc -n sources`, `cat /etc/chrony/chrony.conf`). Relance sans `-e` : tout revient.
6. Réponds en quelques lignes : pourquoi le redémarrage de chrony n'est-il plus un handler ? Que fait `ignore_errors: true` que ne fait pas un `rescue` ? Quand utiliserais-tu `any_errors_fatal: true` sur le socle, et quand `max_fail_percentage` ? Un hôte `UNREACHABLE` passe-t-il par le `rescue` ?

**Critères de réussite**
- [ ] `ansible-doc -t role` affiche le contrat du rôle `base`.
- [ ] Une variable du mauvais type est refusée avant la première tâche du rôle ; une source de temps mal formée est refusée avant toute modification ; une adresse de connexion qui n'est pas une IP du lab arrête l'hôte dès les `pre_tasks`.
- [ ] Une source injoignable laisse `runner01` dans son état d'avant (fichier et synchronisation), avec un message qui dit ce qui a été remis et quoi vérifier.
- [ ] Sans valeur fausse, `socle-base.yml --check` reste à `changed=0`.

**Vérification** : `lab/bin/check 04 15`

<details><summary>Indice 1</summary>

La validation des arguments convertit quand elle peut : regarde ce que la documentation dit du type `list` quand on lui donne une chaîne. Un `assert` dans le bloc complète ce que le type ne peut pas exprimer (format d'une adresse).
</details>

<details><summary>Indice 2</summary>

Le module `template` renvoie le chemin de la copie de sauvegarde (`backup_file`) **seulement** s'il a modifié le fichier. Dans le `rescue`, distingue « il y avait un ancien fichier à remettre » de « l'échec est arrivé avant toute modification ».
</details>

<details><summary>Indice 3</summary>

Un handler ne s'exécute qu'à la fin du play (ou à un `flush_handlers`) : une vérification placée dans le bloc passerait avant lui. Et une tâche en échec à l'intérieur d'un handler n'est pas rattrapée par le `rescue` du bloc qui l'a notifié.
</details>

**Pour aller plus loin** (facultatif) : la même mécanique pour sshd (E11) : poser le fichier, recharger, ouvrir une **nouvelle** connexion, revenir en arrière si elle échoue ; c'est ce que fait, en plus sûr, le rôle `pare_feu` de l'E17. Lis aussi la section « Handling errors in Ansible » de la documentation.

---

### M04-E16 — Rôle `gitlab_runner` : reprendre `runner01` en code  `LIBRE` `★★★`

> **Ticket PLAT-526** — *De : Claire Morel*
> `runner01` a été monté par quatre scripts différents (M01-E23, M01-E24, M02-E24, M03-E15), lancés à la main, chacun à sa version. Si la VM meurt demain, personne ne sait la refaire à l'identique. Je veux pouvoir **recréer `runner01` depuis le template, en une commande**, et que la même commande, lancée sur la VM actuelle, ne change rien. Toute la chaîne de CI de la plateforme en dépend : aucune approximation sur les versions et sur la provenance des outils.

**Objectifs pédagogiques**
- Concevoir un rôle complet à partir d'un existant hétérogène (scripts, installations manuelles).
- Installer des logiciels tiers de façon reproductible et vérifiée : dépôt signé, empreinte de clé, version figée, empreinte des binaires.
- Rendre idempotente une opération qui ne l'est pas (enregistrement d'un runner), sans exposer de secret.
- Distinguer ce qu'Ansible doit posséder de ce qu'il doit laisser au logiciel (fichier réécrit par le service lui-même).

**Prérequis** : M04-E10 à M04-E15 ; M01-E23, M01-E24, M02-E24, M03-E15 (ce que ces scripts installent).
**Durée indicative** : 4 à 6 h.

**Contexte technique**
- Cible : `runner01` (1007, 10.10.20.15), groupe `role_runner`. Tout ce qu'installaient les quatre scripts : GitLab Runner (même version majeure.mineure que GitLab, paquet et images d'assistance figés), Git, `uv` et `pre-commit` (dans `/opt/uv-tools`, pour tous les comptes), Gitleaks 8.30, ShellCheck 0.11 (rétroportages de Debian), shfmt, jq 1.8, bats-core, Task, Node.js 24 (NodeSource) et `/opt/release-tools` (verrou npm de `plateforme/ci-templates`, M01-E24), Packer 1.16 (dépôt HashiCorp) et l'autorité de `pve01` (M03-E15), la racine de la CA provisoire.
- Runner : description `runner01-shell`, exécuteur `shell`, deux jobs simultanés ; ses étiquettes et ses réglages côté serveur appartiennent à l'objet runner de GitLab (M01-E23), pas à `runner01`. Jeton d'authentification `glrt-…` : dans le Vault (`vault_gitlab_runner_jeton`).
- Le compte `gitlab-runner` exécute du code de n'importe quelle branche : aucun privilège, et rien de ce qu'utilisent les jobs ne doit être modifiable par lui.

**Contraintes**
- Le jeton n'apparaît jamais en clair : ni dans le dépôt, ni dans la sortie d'Ansible, ni dans la liste des processus de `runner01`.
- Aucun téléchargement exécuté sans vérification d'intégrité : signature de dépôt dont l'empreinte de clé est contrôlée, ou empreinte SHA-256 du fichier. Les versions sont figées dans des variables ; changer de version est une ligne.
- Un réglage que GitLab Runner réécrit lui-même ne doit pas être écrasé à chaque passage.
- Le rôle reprend sans conflit ce que les scripts avaient posé (fichiers de dépôt APT, binaires dans `/usr/local/bin`) ; aucun doublon ne doit rester.
- Les outils sont vérifiés **tels que les voit un job** (compte `gitlab-runner`, shell de connexion).
- Second passage et `--check` : `changed=0`. Le rôle passe ansible-lint (profil `production`) dès maintenant, même si E20 ne l'impose qu'après.

**Livrables**
- `roles/gitlab_runner/` et le playbook qui l'applique au groupe `role_runner`.
- Les variables propres à `runner01` dans `host_vars/runner01/`, le jeton dans le Vault.
- Une note dans le `README.md` du rôle : ce qu'il installe, d'où, à quelle version, comment monter une version, comment recréer `runner01` (de `qm clone` à la première exécution de job).

**Critères de réussite**
- [ ] Le playbook appliqué à la VM actuelle : `changed=0` au second passage ; `--check` : `changed=0`.
- [ ] Le runner `runner01-shell` est en ligne dans GitLab ; un pipeline de `plateforme/outils` passe.
- [ ] Chaque outil listé est visible du compte `gitlab-runner`, à la version attendue ; `/opt/release-tools` n'est pas modifiable par lui.
- [ ] Un seul fichier de dépôt pour chaque source APT ; `gitlab-runner` et ses images d'assistance figés.
- [ ] Aucun jeton `glrt-` dans l'historique du dépôt.
- [ ] (Facultatif mais recommandé) Le rôle appliqué à une VM jetable 2040 clonée de l'image dorée donne un runner fonctionnel ; VM détruite ensuite (et son runner supprimé de GitLab).

**Vérification** : `lab/bin/check 04 16`

<details><summary>Indice 1</summary>

Pour l'enregistrement, regarde ce que contient `/etc/gitlab-runner/config.toml` une fois le runner enregistré, et ce que `gitlab-runner register --help` dit des variables d'environnement qui correspondent à ses options.
</details>

<details><summary>Indice 2</summary>

`ansible.builtin.deb822_repository` écrit un fichier `.sources` (il demande `python3-debian` sur la cible) ; `ansible.builtin.get_url` vérifie une empreinte (`checksum:`) ; `ansible.builtin.dpkg_selections` fige un paquet. Une clé de dépôt téléchargée n'est fiable qu'une fois son empreinte comparée à celle publiée par l'éditeur, **avant** d'être utilisée par APT.
</details>

<details><summary>Indice 3</summary>

Installer chaque version d'outil dans son propre dossier et pointer un lien symbolique dessus rend le passage idempotent sans interroger la version installée, et le retour arrière immédiat. Pour le module `apt` avec `default_release`, le cache doit déjà connaître la version de Debian visée.
</details>

**Pour aller plus loin** (facultatif) : un scénario Molecule pour ce rôle (VMID 2048, M04-E24) ; un runner jetable par job (exécuteur `docker` au module 12, `kubernetes` au module 19) rendra une partie de ce rôle inutile : laquelle ?

---

### M04-E17 — Rôle `pare_feu` pour `gw01` sans se couper la branche  `LAB` `★★★`

> **Ticket CHG-527** — *De : Claire Morel* — *Copie : Sophie Laurent*
> Le pare-feu de `gw01` est le dernier fichier édité à la main sur le socle, et le plus dangereux : une erreur coupe tout le lab, et la matrice des flux de la documentation ne correspond plus tout à fait à ce qui tourne. Je veux que **la matrice des flux devienne le code** : une liste de flux dans l'inventaire, relue en MR, d'où Ansible génère `/etc/nftables.conf`. Sophie exige qu'un changement raté ne puisse **pas** nous couper durablement : si personne ne confirme que l'accès fonctionne après le rechargement, `gw01` revient tout seul à l'ancienne configuration. Et je veux voir ce mécanisme fonctionner pour de vrai avant de l'utiliser.

**Objectifs pédagogiques**
- Modéliser une configuration réseau comme des données (une matrice de flux) et générer le fichier à partir d'elles.
- Valider une configuration nftables avant de la charger (`nft -c`).
- Mettre en œuvre un filet de sécurité « homme mort » : retour automatique armé avant le changement, désarmé par une confirmation réelle.
- Prouver qu'un changement de génération est sans effet (équivalence des règles chargées).

**Prérequis** : M04-E15 ; M00-E10, M00-E21 (procédure de changement sur `gw01`), M00-E26.
**Durée indicative** : 3 h.

**Contexte technique**
- État de référence de `/etc/nftables.conf` : `modules/00-lab/corrige/fichiers/M00-E26/nftables.conf`, plus les ajouts de M00-E31 (NTP), M01-E28 (`git01` → PBS) et M03-E05/E15 (Packer). Ton fichier réel peut différer : c'est **lui** la référence.
- Données dans `inventories/lab/host_vars/gw01/pare_feu.yml` : les `define` (interfaces, adresses), les flux de la chaîne `input`, ceux de la chaîne `forward`, les règles de NAT. Modèle de flux proposé (adapte si tu as mieux, et justifie) : interface d'entrée et de sortie, source et destination (une valeur ou une liste, négation possible), protocole (`tcp`, `udp`, les deux, `icmp`), ports de destination et de source, action, **motif** (commentaire obligatoire) et référence (exercice ou ticket). Ce qui n'est pas un flux (états conntrack, `lo`, ICMP de diagnostic, journalisation finale) reste dans le template.
- Commentaires nftables : 128 octets au plus.
- Rôle `roles/pare_feu/`, playbook `playbooks/gw01-pare-feu.yml` (groupe `role_routeur`). Délai de retour automatique : 120 s.
- Noms imposés (vérifications, runbook RB-040, astreinte) : unités transitoires `pare-feu-retour.timer` et `.service`, script `/usr/local/sbin/pare-feu-retour`, qui journalise sous l'identifiant `pare-feu-retour` (`journalctl -t pare-feu-retour`) ; sauvegarde de la configuration précédente dans `/var/lib/pare-feu/nftables.conf.precedent`.
- Une session SSH déjà ouverte survit à un rechargement des règles (`ct state established`) : elle ne prouve rien.

> ⚠️ **Attention** : ce rôle modifie le pare-feu de tout le lab. Avant chaque application : instantané de `gw01` (`ms-snapshot --prefix avant-m04 1000`), console ouverte (`ssh pve01 qm terminal 1000`), session SSH ouverte sur `gw01`, `--check --diff` relu. En cas de coupure malgré tout : par la console, `sudo cp /var/lib/pare-feu/nftables.conf.precedent /etc/nftables.conf && sudo nft -f /etc/nftables.conf`, sinon `qm rollback 1000 <instantané>` depuis `pve01`.

**Travail demandé**
1. Relève l'état actuel : `sudo nft -j list ruleset > ~/m04/e17/avant.json` sur `gw01`. Transcris **tout** `/etc/nftables.conf` dans `pare_feu.yml`, flux par flux, en gardant leurs commentaires (avec la référence de l'exercice qui a ouvert chacun).
2. Écris le template, puis le rôle : validation du fichier généré par `nft -c` (y compris en `--check`), prévision du changement (`--diff`), puis, seulement s'il y a un changement, la séquence protégée :
   - sauvegarde de la configuration en place ;
   - armement d'un retour automatique sur `gw01` (une minuterie systemd transitoire, `systemd-run`, qui restaure le fichier sauvegardé **et** le recharge, et le journalise) ;
   - pose et chargement de la nouvelle configuration ;
   - confirmation : **nouvelle** connexion SSH, puis quelques flux traversants testés depuis `adm01` ;
   - désarmement de la minuterie ; en cas d'échec, retour immédiat si `gw01` répond encore, sinon attente de la minuterie, puis échec explicite.
3. `--check --diff` : relis le diff (il devrait être cosmétique). Applique. Prouve l'équivalence : `sudo nft -j list ruleset > ~/m04/e17/apres.json`, et compare les règles des deux fichiers en ignorant commentaires, ordre des critères et numéros (`jq`). Explique toute différence.
4. **Essai de coupure**, dans une branche jamais fusionnée : retire de la matrice le flux « SSH depuis MGMT » et applique. Chronomètre : que fait Ansible, combien de temps avant le retour, que dit `sudo journalctl -t pare-feu-retour` sur `gw01`, et ta session ouverte a-t-elle survécu ? Vérifie que `/etc/nftables.conf` est bien l'ancien. Supprime la branche.
5. Mets à jour `docs/socle/matrice-flux.md` (`plateforme/medisphere`) : la référence devient `host_vars/gw01/pare_feu.yml` ; le document garde la vue d'ensemble et renvoie au fichier. Réponds : que se passe-t-il si quelqu'un ajoute une règle à la main avec `nft add rule` ?

**Critères de réussite**
- [ ] `/etc/nftables.conf` de `gw01` est généré par Ansible ; `nft -c` le valide ; les règles chargées sont équivalentes à celles d'avant (preuve dans ton journal).
- [ ] L'essai de coupure a eu lieu : `gw01` est revenu seul à l'ancienne configuration, et le journal de `gw01` le montre.
- [ ] Aucun retour automatique en attente après un passage réussi ; un second passage ne fait rien (`changed=0`), et n'arme rien.
- [ ] Le lab fonctionne : DNS, HTTPS vers `git01`, sortie Internet, SSH vers `gw01`.
- [ ] La matrice des flux de la documentation renvoie à `host_vars/gw01/pare_feu.yml`.

**Vérification** : `lab/bin/check 04 17`

<details><summary>Indice 1</summary>

`nft -c -f -` lit le fichier sur l'entrée standard : le module `command` a un paramètre `stdin`, et la recherche `ansible.builtin.template` (lookup) rend un template sans l'écrire. Un template forcé en `check_mode: true` donne le diff sans rien écrire.
</details>

<details><summary>Indice 2</summary>

`man systemd-run` : `--on-active=`, `--unit=`, `--collect`. Une unité transitoire au même nom qu'une précédente restée en échec refuse de démarrer : `systemctl reset-failed`. Pour forcer une nouvelle connexion SSH : `meta: reset_connection`, puis `ansible.builtin.wait_for_connection`.
</details>

<details><summary>Indice 3</summary>

Un `rescue` ne rattrape pas un hôte injoignable : les tâches qui touchent `gw01` dans le `rescue` doivent tolérer l'injoignabilité (`ignore_unreachable`), et le `rescue` doit **attendre** que la minuterie ait agi avant de conclure. Pour une macro Jinja qui assemble une règle, une liste et `append` suffisent… mais retiens que c'est pénible à tester : E18 y revient.
</details>

**Pour aller plus loin** (facultatif) : générer aussi `docs/socle/matrice-flux.md` à partir de `pare_feu.yml` (une seule source, deux rendus) ; un scénario Molecule `pare_feu` (VMID 2047) qui vérifie le retour automatique ; au module 07, deux routeurs en VRRP : `serial: 1` et pourquoi on ne recharge jamais les deux à la fois.

---

### M04-E18 — Collections : utiliser et créer `medisphere.socle`  `LAB` `★★`

> **Ticket PLAT-528** — *De : Karim Benali*
> Deux choses me gênent dans ce qu'on a écrit. La macro Jinja qui fabrique les règles de `pare_feu` : illisible en revue, impossible à tester seule, et elle accepte n'importe quelle faute de frappe dans la matrice. Et l'installation des autorités de certification, recopiée dans deux rôles. On crée la collection interne de l'équipe, **`medisphere.socle`** : du code Python testé pour la logique, des rôles partagés pour ce qui se répète. Au passage, je veux savoir exactement d'où viennent les collections externes qu'on exécute.

**Objectifs pédagogiques**
- Comprendre ce qu'est une collection (espace de noms, contenu, métadonnées, version) et comment Ansible la trouve (`collections_path`).
- Maîtriser l'origine des collections externes : versions figées, installation, vérification d'intégrité.
- Écrire un plugin de filtre en Python, le documenter (`ansible-doc`) et le tester (pytest).
- Partager un rôle par une collection et l'appeler par son nom complet.

**Prérequis** : M04-E16, M04-E17 ; M02-E18 (pytest).
**Durée indicative** : 2 h.

**Contexte technique**
- Collection : `collections/ansible_collections/medisphere/socle/` dans le dépôt `plateforme/ansible`, **versionnée** (les collections externes, elles, sont installées et ignorées par Git). Le module 04 y ajoutera un module en M04-E44 (`plugins/modules/`), avec ses tests dans `tests/unit/plugins/`.
- Filtre imposé : `medisphere.socle.regle_nft` (un flux de la matrice → une ligne de règle), dans `plugins/filter/`, ses tests dans `tests/unit/plugins/filter/test_*.py`. Il refuse les champs inconnus, un motif absent ou trop long, les ports sans protocole.
- Rôle partagé : celui qui installe des autorités de certification dans le magasin système, utilisé par `gitlab_runner` (et demain par d'autres).
- Versions d'ansible-core visées : 2.19 (Debian 13) et 2.21 (projet).

**Travail demandé**
1. Collections externes : `uv run ansible-galaxy collection list`. D'où vient chaque collection, à quelle version ? Que se passe-t-il si une collection est aussi installée dans `~/.ansible/collections` ? Lance `uv run ansible-galaxy collection verify -r collections/requirements.yml` : que vérifie cette commande, et contre quoi ?
2. Crée le squelette (`uv run ansible-galaxy collection init medisphere.socle --init-path collections/ansible_collections`), puis allège-le. Renseigne `galaxy.yml` (version 1.0.0) et `meta/runtime.yml`. Vérifie que `.gitignore` versionne cette collection et pas les autres.
3. Écris le filtre `regle_nft` dans `plugins/filter/` : même sortie que ta macro de E17, plus les refus. Documente-le par un fichier YAML voisin (lu par `ansible-doc -t filter`). Écris ses tests (pytest), y compris les cas refusés, et lance-les avec `PYTHONPATH=collections`.
4. Remplace la macro du template de `pare_feu` par le filtre. Prouve que rien ne change : `playbooks/gw01-pare-feu.yml --check --diff` ne montre aucune différence sur `gw01`.
5. Déplace l'installation des autorités de certification de `gitlab_runner` dans un rôle de la collection, avec son contrat (`meta/argument_specs.yml`) ; appelle-le par son nom complet. `--check` sur `runner01` : rien ne change.
6. `uv run ansible-galaxy collection build` dans le dossier de la collection : que contient l'archive, et que deviendrait-elle si l'équipe d'une autre entité voulait l'utiliser (registre privé, Automation Hub, dépôt Git) ?

**Critères de réussite**
- [ ] `medisphere.socle 1.0.0` apparaît dans `ansible-galaxy collection list` ; elle est sur `main`, les collections externes non.
- [ ] `ansible-doc -t filter medisphere.socle.regle_nft` affiche sa documentation ; ses tests passent ; un champ mal orthographié dans un flux fait échouer le rendu avec un message clair.
- [ ] Le template de `pare_feu` n'a plus de macro ; `--check` sur `gw01` et `runner01` : `changed=0`.
- [ ] `collections/requirements.yml` fige des versions exactes.

**Vérification** : `lab/bin/check 04 18`

<details><summary>Indice 1</summary>

Un plugin de filtre est un fichier Python qui définit une classe `FilterModule` avec une méthode `filters()` renvoyant un dictionnaire `{nom: fonction}`. Lève `ansible.errors.AnsibleFilterError` pour refuser une entrée.
</details>

<details><summary>Indice 2</summary>

Pour que Python importe `ansible_collections.medisphere.socle…` dans les tests, le dossier qui **contient** `ansible_collections/` doit être dans son chemin de recherche. `ansible-test units` sait aussi le faire, s'il est lancé depuis le dossier de la collection.
</details>

<details><summary>Indice 3</summary>

Depuis ansible-core 2.14, `ansible-doc` lit la documentation d'un filtre dans un fichier `<nom>.yml` placé à côté du fichier Python, avec les clés `DOCUMENTATION`, `EXAMPLES` et `RETURN`.
</details>

**Pour aller plus loin** (facultatif) : publier la collection dans le registre de paquets de GitLab (format générique) ou la consommer par une URL Git dans `requirements.yml` d'un autre projet ; tester la collection avec `ansible-test sanity`.

---

### M04-E19 — Exploitation quotidienne : tags, limit, check, diff  `LAB` `★`

> **Ticket PLAT-529** — *De : Nadia Roussel*
> L'astreinte va devoir rejouer la configuration, pas seulement toi. Il me faut : un point d'entrée unique pour tout le socle, la façon de viser **un** hôte ou **une** partie d'un rôle, la façon de savoir ce qu'un passage ferait avant de le lancer, et une page qui résume tout ça. Pas un cours sur Ansible : ce qu'on tape, quand, et ce qu'il faut regarder dans la sortie.

**Objectifs pédagogiques**
- Assembler les playbooks du socle (`import_playbook`) et choisir une stratégie d'étiquettes cohérente.
- Viser précisément : motifs d'hôtes (`--limit`), étiquettes (`--tags`, `--skip-tags`), listes (`--list-hosts`, `--list-tasks`, `--list-tags`).
- Connaître les limites de `--check` et `--diff`.
- Écrire une aide-mémoire d'exploitation.

**Prérequis** : M04-E10 à M04-E17.
**Durée indicative** : 1 h.

**Contexte technique**
- Point d'entrée : `playbooks/site.yml`. Étiquettes des rôles posées dans les playbooks (`base`, `ssh`, `pare_feu`, `runner`), étiquettes fines dans les rôles (`base_temps`, `base_utilisateurs`…).
- Aide-mémoire : `docs/exploitation.md` dans le projet `plateforme/ansible`.

**Travail demandé**
1. Écris `site.yml`. Dans quel ordre importes-tu les playbooks, et pourquoi ?
2. Sans rien exécuter, réponds par une commande à chaque question (note commande et réponse dans ton journal) : quels hôtes touche `site.yml --tags pare_feu` ? Quelles tâches s'exécuteraient avec `--tags base_temps --limit dns01` ? Quelles étiquettes existent ? Quels hôtes vise `--limit 'socle:!gw01'` ? Et `--limit 'role_*'` ?
3. Lance `site.yml --check --diff` sur tout le socle : tout doit être à `changed=0`. Puis modifie à la main `/etc/motd` sur `dns01`, et relance `--check --diff --limit dns01` : lis le diff. Remets en ordre par Ansible.
4. Expériences : lance `--skip-tags always --check --limit dns01` et explique ce qui se passe. Trouve dans tes rôles une tâche que `--check` saute, et une que le rôle force à s'exécuter quand même en `--check` : pourquoi ce choix pour chacune ?
5. Écris `docs/exploitation.md` : règles d'or, tableau « playbook, cible, étiquettes », commandes du quotidien, ce que `--check` ne voit pas.

**Critères de réussite**
- [ ] `site.yml --check` : `changed=0` et aucun échec sur les cinq hôtes.
- [ ] `--list-tags` montre les étiquettes des rôles et les étiquettes fines ; `--tags pare_feu --list-tasks` ne montre, en dehors des tâches `always`, que des tâches du rôle `pare_feu`.
- [ ] `docs/exploitation.md` est sur `main` et explique `--check`, `--diff`, `--limit` et `--tags`.

**Vérification** : `lab/bin/check 04 19`

<details><summary>Indice 1</summary>

Une étiquette posée sur un `import_tasks` ou un rôle de la liste `roles:` est héritée par toutes leurs tâches. Les motifs de `--limit` : `ansible-doc` n'en parle pas, la page « Patterns: targeting hosts and groups » si.
</details>

<details><summary>Indice 2</summary>

La collecte des faits est une tâche implicite… étiquetée. Et une tâche `command` porte `check_mode: false` quand elle ne fait que lire.
</details>

**Pour aller plus loin** (facultatif) : `ANSIBLE_STDOUT_CALLBACK` (callbacks `default`, `yaml` de résultat, `ansible.posix.json`) et le récapitulatif `--diff` par hôte ; le palier 3 automatise ce `--check` en CI (E27) et en contrôle de dérive (E29).

---

### M04-E20 — ansible-lint en pre-commit et en CI  `LAB` `★★`

> **Ticket PLAT-530** — *De : Karim Benali*
> Je ne veux plus relire en MR des `with_items`, des modules sans nom complet ou des `mode: 644`. Ce que l'outil sait trouver, il le trouve avant moi : sur ton poste avant le commit, et en CI pour ceux qui auraient sauté pre-commit. Profil `production`, pas de règle désactivée « parce que ça gêne ». Une exception se justifie, sur la ligne, avec la raison.

**Objectifs pédagogiques**
- Configurer ansible-lint (profils, chemins exclus, exceptions locales).
- Brancher l'outil du projet (`uv`) comme hook pre-commit local et comme job de CI, avec les mêmes versions.
- Faire tourner Ansible en CI sans ses secrets ni son inventaire dynamique.

**Prérequis** : M04-E18 ; M01-E15, M01-E24 (pre-commit, gabarits de CI).
**Durée indicative** : 1 h 30.

**Contexte technique**
- ansible-lint est dans l'environnement du projet (groupe `dev` de `pyproject.toml`, M04-E02) : c'est **cette** version qui doit tourner partout.
- Le job de CI hérite des gabarits de `plateforme/ci-templates` (`ref: v1`) : son job `pre-commit` lance tous les hooks, avec `SKIP` (M01-E24).
- Sur `runner01`, le job n'a ni le mot de passe du Vault ni l'accès à Proxmox (et ne doit pas les avoir pour un simple lint). `ansible.cfg` déclare pourtant l'identité Vault et l'inventaire dynamique.

**Travail demandé**
1. Lance `uv run ansible-lint` sur le projet. Classe les résultats : vrais défauts (corrige-les), faux positifs (exception justifiée sur la ligne, `# noqa: <règle>`), fichiers qui ne sont pas à toi (exclusion).
2. Écris `.ansible-lint` : profil `production`, exclusions (environnement, collections externes, modèles `*.exemple`), et la règle de l'équipe sur `skip_list`.
3. Ajoute le hook à `.pre-commit-config.yaml` sous la forme d'un hook **local** qui lance l'ansible-lint du projet. Pourquoi pas le hook publié par le projet ansible-lint ? Teste-le : un commit qui introduit `mode: 644` est refusé.
4. Ajoute le job `ansible-lint` à `.gitlab-ci.yml`. Fais-le passer sans donner au job ni secret ni accès à Proxmox. Évite que le hook local soit aussi lancé par le job `pre-commit` du gabarit.
5. MR qui introduit volontairement un défaut : le pipeline est rouge, la fusion bloquée. Corrige, fusionne.

**Critères de réussite**
- [ ] `uv run ansible-lint` passe en profil `production` sur tout le projet, sans règle désactivée globalement.
- [ ] Le hook pre-commit refuse un commit fautif.
- [ ] Le dernier pipeline de `main` contient un job `ansible-lint` réussi ; le job n'a reçu aucune variable secrète.

**Vérification** : `lab/bin/check 04 20`

<details><summary>Indice 1</summary>

Un hook `repo: local` avec `language: system` exécute une commande telle quelle : `uv run --frozen ansible-lint`. `pass_filenames: false` : ansible-lint a besoin de tout le projet pour comprendre un rôle.
</details>

<details><summary>Indice 2</summary>

Une variable d'environnement `ANSIBLE_<RÉGLAGE>` remplace la valeur d'`ansible.cfg` (`ansible-config list` donne les noms). Une identité Vault dont le fichier n'existe pas fait échouer toute commande Ansible, même celles qui ne déchiffrent rien ; une identité dont le mot de passe est faux ne gêne que celles qui déchiffrent.
</details>

**Pour aller plus loin** (facultatif) : le rapport `--format codeclimate` affiché dans la MR (widget *Code Quality*) ; `yamllint` et sa configuration partagée avec ansible-lint ; la règle `galaxy` pour la collection interne.

---

### M04-E21 — Revue des rôles du stagiaire  `REV` `★★`

> **Ticket PLAT-531** — *De : Karim Benali* — *Copie : Lucas Martin*
> Lucas a ouvert une MR avec deux rôles « pour l'audit HDS » : `fail2ban` et `comptes_equipe`, plus un playbook qui les applique partout. Il dit que tout est vert sur sa VM d'essai. Fais-lui une vraie revue : chaque défaut, sa gravité, l'impact concret **sur notre socle**, la correction. Puis donne-moi ton avis sur le fond : a-t-on besoin de ces deux rôles ?

**Objectifs pédagogiques**
- Relire du code Ansible comme il s'exécutera sur le socle (ansible-core 2.21, `inject_facts_as_vars = False`, Python 3.13, rôles existants).
- Repérer les défauts de sécurité, d'idempotence et de comportement que l'outil ne voit pas.
- Remettre en cause le besoin et l'architecture, pas seulement le code.

**Prérequis** : M04-E10 à M04-E15, M04-E17.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Fichiers : `ressources/M04-E21/` (MR `MR-lucas.md`, `playbooks/durcir-socle.yml`, `roles/fail2ban/`, `roles/comptes_equipe/`). Le mot de passe qu'ils contiennent est **fictif**.
- Lucas a testé sur une VM Debian 12, avec l'Ansible du paquet Debian (2.14), en lançant le playbook **sur la VM elle-même**, qui avait rsyslog installé.

> ⚠️ **Attention** : ne lance pas ce playbook sur le socle. Pour observer un comportement, copie les fichiers dans `~/m04/e21/` et utilise une VM jetable (2040), ou `--check` sur `runner01` seulement.

**Travail demandé**
1. Lis les fichiers sans rien noter. Puis réponds : sur notre socle, que fait chaque tâche au premier passage ? Au deuxième ? Sur `gw01` ? Sur `adm01` ?
2. Lance `uv run ansible-lint` sur une copie : ce qu'il trouve, ce qui lui échappe.
3. Rédige la revue en tableau : n°, fichier et ligne(s), défaut, catégorie (sécurité, fonctionnement, idempotence, maintenabilité), gravité (critique, élevée, moyenne, faible), impact concret, correction.
4. Classe les défauts par ordre de traitement et justifie.
5. Propose une version corrigée de `fail2ban` qui conviendrait au socle (ou explique pourquoi tu n'en veux pas), et dis comment le besoin de `comptes_equipe` doit être couvert dans nos rôles existants.
6. Question de fond (dix lignes) : avec SSH par clé uniquement, filtré par `gw01` (MGMT et VPN seulement), que nous apporte fail2ban, et que risque-t-on ? Les comptes nominatifs sont-ils une bonne idée pour HDS ? Que recommandes-tu à Karim ?
7. Trois lignes de conseils à Lucas sur sa façon de tester.

**Critères de réussite** (auto-évaluation avec le corrigé)
- [ ] Au moins 14 défauts identifiés, dont tous les défauts critiques et élevés du corrigé.
- [ ] Chaque défaut a un impact concret sur **notre** socle et une correction précise.
- [ ] La question de fond reçoit une réponse argumentée, avec une recommandation.

<details><summary>Indice 1</summary>

Lis chaque tâche en te demandant **où** elle s'exécute : un *lookup* s'exécute sur le contrôleur, un module sur la cible. Puis ce que chaque condition vaut avec la configuration du projet (`ansible.cfg`, M04-E02).
</details>

<details><summary>Indice 2</summary>

Compare `jail.local` avec ce que Debian 13 fournit déjà dans `/etc/fail2ban/jail.d/defaults-debian.conf`, et demande-toi où sont les journaux de sshd sur une VM sans rsyslog. Regarde aussi qui fail2ban peut bannir, et ce que fait le rôle `pare_feu` au prochain rechargement de `gw01`.
</details>

<details><summary>Indice 3</summary>

Suis une clé SSH : d'où vient-elle, qui peut la changer, que se passe-t-il quand quelqu'un quitte l'équipe ? Et suis le mot de passe : où est-il écrit, qui le connaît, que vaut `mode: 644` sans zéro devant ?
</details>

**Pour aller plus loin** (facultatif) : écris le scénario Molecule qui aurait attrapé les trois défauts les plus graves.

---

### M04-E22 — Runbook : appliquer un changement de configuration sur le socle  `RED` `★★`

> **Ticket CHG-532** — *De : Nadia Roussel*
> Demain, c'est l'astreinte qui réappliquera la configuration après une restauration ou une dérive, sans toi au téléphone. Écris le runbook **RB-040** : de la MR fusionnée au second passage à zéro, avec les précautions propres à `gw01` et aux clés SSH, le retour arrière, et ce qu'on fait quand ça ne se passe pas comme prévu. Je le testerai moi-même en suivant chaque ligne.

**Objectifs pédagogiques**
- Transformer une pratique (les règles du palier) en procédure exécutable par quelqu'un d'autre.
- Rendre chaque étape vérifiable : commande, résultat attendu, que faire sinon.
- Prévoir le retour arrière avant d'en avoir besoin.

**Prérequis** : M04-E10 à M04-E19.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Emplacement : `docs/socle/runbooks/RB-040-appliquer-changement-configuration.md` dans `plateforme/medisphere`, sur le modèle des runbooks RB-010 à RB-013 (M01).
- Si tu as déjà écrit le playbook de l'E23, le runbook s'appuie dessus ; sinon, fais-le après l'E23 et complète.

**Travail demandé**
Rédige RB-040 avec au moins : quand l'utiliser (et quand ne pas l'utiliser), règles, prérequis (accès, secrets, outils), étapes numérotées (préparer, ouvrir l'accès de secours, simuler, appliquer à un hôte, étendre, contrôler), retour arrière (trois niveaux, du plus propre au plus brutal, avec leurs conséquences), symptômes fréquents et réponse, et ce qu'on consigne après. Chaque commande a son résultat attendu. Fais-le relire par MR (Nadia et Karim).

**Critères de réussite** (auto-évaluation avec le corrigé)
- [ ] Quelqu'un qui n'a pas fait le module peut l'exécuter sans question.
- [ ] Le cas de `gw01` et celui des clés SSH sont traités à part.
- [ ] Le retour arrière ne repose pas seulement sur un instantané.
- [ ] Les limites de `--check` sont écrites là où elles comptent.

**Pour aller plus loin** (facultatif) : fais exécuter le runbook par quelqu'un d'autre (ou toi dans une semaine, sans relire tes notes) et corrige chaque hésitation.

---

### M04-E23 — Déléguer et orchestrer : `delegate_to`, `run_once`  `LAB` `★★`

> **Ticket CHG-533** — *De : Nadia Roussel*
> Pour chaque changement appliqué au socle, je veux la même enveloppe, automatiquement : un numéro de changement obligatoire, un instantané Proxmox des VMs touchées **avant**, une vérification **de l'extérieur** après (l'hôte est toujours résolu par le DNS et joignable en SSH), et une ligne dans le journal des changements de la documentation. Une seule fois par changement, pas une fois par hôte.

**Objectifs pédagogiques**
- Exécuter une tâche pour un hôte, mais **sur** une autre machine (`delegate_to`), en sachant quelles variables et quelle connexion sont utilisées.
- Exécuter une tâche une seule fois pour tout un play (`run_once`) et connaître ses interactions avec `--limit` et `serial`.
- Composer des plays dans un même playbook, et lire l'état des hôtes depuis un autre play (`hostvars`).

**Prérequis** : M04-E13 (variable `vmid` ou équivalent de l'inventaire dynamique), M04-E19 ; M02-E11 (`ms-snapshot`).
**Durée indicative** : 1 h 30.

**Contexte technique**
- Playbook `playbooks/changement-socle.yml` : plays « avant », import de `site.yml`, plays « après » et « journal ». Usage : `-e changement=CHG-533`, avec les `--limit` et `--tags` habituels.
- Instantanés : `ms-snapshot` (M02) sur `adm01`, avec le jeton `wb-automation` (le jeton d'Ansible ne sait que lire) ; préfixe = numéro de changement en minuscules, deux instantanés gardés par préfixe.
- Vérifications : résolution du nom de l'hôte par `dns01` (`dig`), port 22 joignable depuis `adm01`.
- Journal : `docs/socle/journal/changements-ansible.md` dans `~/medisphere` (une ligne de tableau par changement : date UTC, numéro, hôtes visés, hôtes vérifiés, hôtes en échec).

**Travail demandé**
1. Écris le play « avant » : refus sans numéro de changement, puis **une** commande `ms-snapshot` pour toutes les VMs du play. Que se passerait-il sans `run_once` ? Et avec `run_once` mais sans `delegate_to` ?
2. Écris le play « après » : la vérification DNS exécutée **sur `dns01`** pour chaque hôte, le test de port **depuis `adm01`**. Dans la tâche déléguée à `dns01`, que vaut `inventory_hostname` ? `ansible_host` ? Sous quel compte et avec quelle élévation la commande s'exécute-t-elle ?
3. Écris le play « journal » : il doit écrire sa ligne même si des hôtes ont échoué en route, sans `sudo`, et ne rien écrire en `--check`.
4. Rends l'enveloppe insensible à `--tags` : lancée avec `--tags base_temps`, elle doit quand même prendre l'instantané, vérifier et journaliser.
5. Applique un vrai changement : passe `base_journal_taille_max` à `300M` par MR, puis `ansible-playbook playbooks/changement-socle.yml -e changement=CHG-533 --tags base_journal`. Constate l'instantané sur `pve01`, la ligne de journal, puis pousse le journal dans `plateforme/medisphere`.
6. Réponds : avec `serial: 2` sur le play « avant », combien d'instantanés seraient pris, et quand ? Que fait `delegate_facts: true`, et dans quel cas l'utiliserais-tu ici ?

**Critères de réussite**
- [ ] Sans `-e changement=…`, le playbook s'arrête avant toute action.
- [ ] Un changement réel a produit un instantané `chg-…` sur les VMs visées et une ligne dans le journal des changements.
- [ ] En `--check`, aucune action (ni instantané, ni écriture), mais les vérifications s'exécutent.
- [ ] Le playbook utilise `delegate_to` vers `dns01` et vers `adm01`, et `run_once`.

**Vérification** : `lab/bin/check 04 23`

<details><summary>Indice 1</summary>

`ansible_play_hosts` donne les hôtes du play encore actifs (après `--limit` et sans ceux qui ont échoué) ; `map('extract', hostvars, 'nom_de_variable')` va chercher une variable de chacun.
</details>

<details><summary>Indice 2</summary>

Une tâche déléguée à `localhost` hérite de `become: true` du play : regarde à qui appartiendrait le fichier du journal. Un play sur `localhost` s'exécute même quand tous les hôtes du socle ont échoué ; il lit leur état dans `hostvars`.
</details>

<details><summary>Indice 3</summary>

L'étiquette spéciale `always` fait exécuter une tâche quel que soit `--tags` (sauf `--skip-tags always`).
</details>

**Pour aller plus loin** (facultatif) : la stratégie `free` et `throttle` ; un handler de notification (message dans un ticket GitLab par l'API) déclenché en fin de changement ; au palier 3, cette enveloppe devient le job `appliquer` de la CI (E27).
