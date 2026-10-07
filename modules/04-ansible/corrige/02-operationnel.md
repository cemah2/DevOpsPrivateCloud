# Module 04 — Palier 2 : Opérationnel — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Les fichiers.** Les fichiers complets sont dans [`fichiers/`](fichiers/), un dossier par exercice, sous la forme d'un **extrait du projet** (`fichiers/M04-EXX/ansible/…` = chemins du dépôt `plateforme/ansible`). Les exercices font évoluer les mêmes fichiers : le projet de fin de palier s'obtient en **superposant** les dossiers dans l'ordre (projet de fin de palier 1, puis `M04-E10`, `E11`, `E12`… `E23`) ; un fichier d'un exercice plus récent remplace le précédent. Exemple : `roles/base/tasks/utilisateurs.yml` existe en version E10 (clés de `admin`), E12 (compte de secours) et E14 (liste de comptes) ; `roles/base/tasks/temps.yml` en version E10 puis E15. Les fichiers `*.extrait` sont des morceaux à intégrer dans un fichier existant (`ansible.cfg`, `.pre-commit-config.yaml`, `.gitignore`), les `*.exemple` des modèles sans valeur réelle. Hors projet : le script de compte Proxmox (`M04-E13/`), le runbook (`M04-E22/medisphere/…`), le rôle `fail2ban` corrigé (`M04-E21/`).

**Ce qui a été testé, ce qui ne l'a pas été.** Avec ansible-core 2.21.5, ansible-lint 26.9 et les collections `community.proxmox` 2.1.0, `community.general` 13.5.0, `ansible.posix` 2.2.2 :
- le projet de fin de palier (palier 1 compris) et chaque état intermédiaire (après E10, E11, E12, E14, E15, E17) passent `ansible-playbook --syntax-check` et `ansible-lint` en profil `production` sans exception globale ;
- les rôles `base`, `ssh_durci`, `gitlab_runner`, `pare_feu` et `fail2ban` (corrigé de E21) ont été **appliqués** à des conteneurs Debian 13 avec systemd, sshd et nftables : premier passage, second passage à `changed=0`, `--check` à `changed=0`, `rescue` de chrony (source injoignable : l'ancienne configuration est remise), nettoyage du compte `infoger` (script de E14), **filet de sécurité du pare-feu dans les deux sens** (changement confirmé ; coupure de SSH → minuterie → configuration précédente restaurée et rechargée au bout de 60 s, playbook en échec explicite) ;
- l'inventaire dynamique a été testé contre une **imitation** de l'API Proxmox (mêmes chemins et formats que l'API de PVE 9) : groupes, filtres, `compose`, comportement en cas d'erreur, `unparsed_is_failed` ;
- le filtre `regle_nft` (15 tests pytest) donne exactement le même fichier que la macro de E17, et les règles chargées par nftables sont identiques, à l'ordre près, à celles de la référence M00-E26 complétée (comparaison des sorties `nft -j`).

**Non rejoués sur le lab réel** : les privilèges Proxmox et les ACL (déduits de l'API viewer de PVE 9 et du code du plugin), l'enregistrement d'un runner auprès d'un vrai GitLab 19.4, la synchronisation chrony réelle sur `gw01`, le job de CI sur `runner01`, le comportement de `qm terminal`. Ils sont signalés « ⚠️ À vérifier sur ta version » : signale tes retours.

---

### M04-E10 — Premier rôle : `base`

**Solution**

Fichiers : [`fichiers/M04-E10/ansible/`](fichiers/M04-E10/ansible/) — rôle [`roles/base/`](fichiers/M04-E10/ansible/roles/base/), playbook [`playbooks/socle-base.yml`](fichiers/M04-E10/ansible/playbooks/socle-base.yml), inventaire : [`group_vars/all/main.yml`](fichiers/M04-E10/ansible/inventories/lab/group_vars/all/main.yml) (complet, version E10), [`group_vars/role_routeur/main.yml`](fichiers/M04-E10/ansible/inventories/lab/group_vars/role_routeur/main.yml), [`host_vars/gw01/base.yml`](fichiers/M04-E10/ansible/inventories/lab/host_vars/gw01/base.yml), [`host_vars/adm01/base.yml`](fichiers/M04-E10/ansible/inventories/lab/host_vars/adm01/base.yml).

1. **Squelette.** `ansible-galaxy role init` crée `defaults/`, `files/`, `handlers/`, `meta/`, `tasks/`, `templates/`, `tests/`, `vars/` et un `README.md`. On garde `defaults`, `handlers`, `meta`, `tasks`, `templates` ; `tests/` (un inventaire et un playbook factices) est remplacé par Molecule au palier 3 ; `vars/` reste vide.
   Précédence : `defaults/main.yml` du rôle est le niveau **le plus bas** de toutes les variables (rang 2 sur 22) ; `vars/main.yml` du rôle est très haut (rang 15, au-dessus de tout l'inventaire et des `vars:` de play). Une variable de `vars/` ne se surcharge donc plus que par `include_vars`, `set_fact`, les paramètres du rôle ou `-e` : c'est une **constante interne** du rôle (un chemin propre à la distribution, par exemple), jamais un réglage. Tous les réglages vont dans `defaults/`.
2. **Reprise du palier 1.** `tasks/main.yml` importe un fichier par thème avec une étiquette fine (`base_paquets`, `base_temps`, `base_journal`, `base_maj`, `base_utilisateurs`, `base_identite`) :
   ```yaml
   - name: Fuseau horaire et temps
     ansible.builtin.import_tasks: temps.yml
     tags: [base_temps]
   ```
   `paquets.yml` reprend la trousse (E05/E06) sous les noms `base_paquets`, `base_paquets_role`, `base_paquets_interdits` (liste par défaut dans `defaults/`, outils du routeur dans `group_vars/role_routeur/main.yml`) ; `identite.yml` reprend le `motd` et le fait local (E07), les templates passant de `ms_role`, `ms_site`… à des variables du rôle ; `temps.yml` reprend `chrony-client.yml` (E08) : template validé par `chronyd -p -f %s`, `backup: true`, suppression de `sources.d/lab.sources`, handler, `flush_handlers`, `chronyc waitsync`. En plus : désactivation de `ms-ntp-passerelle` s'il existe (VMs de l'image dorée), pour qu'un seul mécanisme décide de la source. Le template n'ayant pas de `sourcedir`, le fichier que ce service écrirait ne serait de toute façon plus lu.
3. **Valeurs par défaut qui reprennent le site.** Extrait de [`defaults/main.yml`](fichiers/M04-E10/ansible/roles/base/defaults/main.yml) :
   ```yaml
   base_entete: >-
     {{ ms_gere_par | default('Fichier géré par Ansible (projet plateforme/ansible).
     Toute modification manuelle sera écrasée au prochain passage.') }}
   base_ntp_serveurs: "{{ ms_serveurs_ntp | default([ansible_facts['default_ipv4']['gateway']]) }}"
   base_role_hote: >-
     {{ ms_role | default(group_names | select('match', '^role_') | map('regex_replace', '^role_', '')
        | first | default('aucun')) }}
   ```
   Avec l'inventaire du projet, `ms_serveurs_ntp` existe (passerelle calculée depuis `ansible_host`, M04-E06) ; sur une VM de test sans inventaire, la passerelle par défaut lue dans les faits donne le même résultat. Les `defaults` d'un rôle n'existent que **pendant** le rôle : une commande ad hoc ne les voit pas (`base_ntp_serveurs` y est « VARIABLE IS NOT DEFINED! »). On contrôle donc la source, puis la valeur vue par le rôle :
   ```
   admin@adm01:~/src/ansible$ uv run ansible dns01 -m ansible.builtin.debug -a "var=ms_serveurs_ntp"
   dns01 | SUCCESS => {
       "ms_serveurs_ntp": [
           "10.10.20.1"
       ]
   }
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/socle-base.yml --check --diff --limit dns01 --tags base_temps
   ```
   Le `--diff` du template de chrony ne doit montrer **aucune** ligne `server` modifiée par rapport à E08.
4. **Nouveaux thèmes.** `community.general.timezone` (il passe par `timedatectl`) ; `journal.yml` dépose `/etc/systemd/journald.conf.d/50-medisphere.conf` (`Storage=persistent`, `SystemMaxUse=200M`) et notifie un redémarrage de `systemd-journald` ; `mises_a_jour.yml` dépose `20auto-upgrades` et `52medisphere-unattended-upgrades` (avec `#clear` sur la liste des origines, comme en M03-E09).
   **Mêmes noms que l'image dorée** : sur une VM issue de l'image, le rôle **remplace** les fichiers de l'image au lieu d'en ajouter d'autres. Avec un autre nom, deux fichiers coexisteraient : pour journald, celui qui est lu en dernier l'emporte (ordre alphabétique) ; pour APT, les listes s'**ajoutent** (sauf `#clear`) et des réglages contradictoires se combineraient de façon peu lisible. Un seul nom = un seul propriétaire du réglage.
5. **Clés autorisées.**
   ```yaml
   - name: Clés autorisées du compte d'administration (liste exclusive)
     ansible.posix.authorized_key:
       user: "{{ base_admin_utilisateur }}"
       key: "{{ base_admin_cles | join('\n') }}"
       exclusive: true
     when: base_admin_cles | length > 0
   ```
   `exclusive: true` n'accepte qu'**un** appel du module par compte (toutes les clés dans `key`, séparées par des fins de ligne) : une boucle d'une clé par itération ne garderait que la dernière. Liste vide : le rôle ne touche à rien. C'est le seul choix sûr : une liste exclusive vide retirerait toutes les clés, et une liste vide est exactement ce qu'on obtient quand une variable est mal nommée ou absente (VM de test, inventaire incomplet). Données dans `group_vars/all/main.yml` (`ms_cles_admin`, puis `base_admin_cles: "{{ ms_cles_admin }}"`) ; `host_vars/adm01/base.yml` remplace `ms_cles_admin` par la clé de ton poste.
6. **Application.**
   ```
   admin@adm01:~/src/ansible$ ms-snapshot --prefix avant-m04 1007
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/socle-base.yml --check --diff --limit runner01
   …
   TASK [base : Clés autorisées du compte d'administration (liste exclusive)] *****
   ok: [runner01]
   TASK [base : Journal persistant avec plafond d'espace] *************************
   --- before
   +++ after: …/journald-medisphere.conf.j2
   @@ -0,0 +1,8 @@
   +#
   +# Fichier géré par Ansible (projet plateforme/ansible). Toute modification manuelle …
   …
   changed: [runner01]
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/socle-base.yml --limit runner01
   admin@adm01:~/src/ansible$ ssh -o ControlPath=none runner01 true && echo SSH-OK
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/socle-base.yml --limit runner01   # changed=0
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/socle-base.yml --check --diff --limit 'socle:!runner01'
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/socle-base.yml
   ```
   Le diff des clés autorisées est **le** diff à lire ligne à ligne : une ligne `-` inattendue, c'est quelqu'un qui perd son accès.
7. `git rm playbooks/trousse-diagnostic.yml playbooks/identite-hotes.yml playbooks/chrony-client.yml` (et `playbooks/templates/` s'il ne sert plus), MR `feat(base): rôle base, reprise des playbooks du palier 1`.

**Explications**

Un rôle est une convention de rangement que le moteur connaît : en citant `base`, Ansible charge `defaults/main.yml`, `vars/main.yml`, `tasks/main.yml`, `handlers/main.yml`, cherche les fichiers de `templates/` et `files/` à côté, lit les dépendances et le contrat dans `meta/`. C'est ce qui permet de le **tester seul** (Molecule), de le **réutiliser** (autre projet, collection) et d'en **lire le contrat** (`ansible-doc -t role`, E15).
`import_tasks` est statique : les tâches sont insérées à l'analyse du playbook, les étiquettes et les conditions posées sur l'import sont recopiées sur chacune, et `--list-tasks`, `--tags`, `--start-at-task` les voient. `include_tasks` est dynamique : le fichier n'est lu qu'à l'exécution (utile pour une boucle ou un nom de fichier calculé), et une étiquette posée sur l'include ne s'applique qu'à l'include lui-même.
Un rôle qui ne fonctionne qu'avec l'inventaire du projet n'est pas testable : Molecule (E24) l'applique à une VM neuve, avec ses seules valeurs par défaut. D'où la règle « défaut raisonnable, reprise des données du site quand elles existent ».

**Alternatives**
- Garder les variables `ms_…` directement dans les templates du rôle : plus court, mais le rôle exige alors l'inventaire du projet, et Molecule devrait le recopier.
- Un rôle par thème (`chrony`, `journald`, `motd`…), assemblés par un rôle `base` qui dépend d'eux (`meta/main.yml`, `dependencies`) : plus réutilisable, plus de fichiers ; à envisager quand un thème servira seul ailleurs.
- Rôles de la communauté (`geerlingguy.ntp`, etc.) : très bien pour un besoin standard, mais ils embarquent des choix (pools, fichiers) qu'il faudrait de toute façon surcharger, et une dépendance externe de plus à surveiller.

**Pièges classiques**
- Mettre un réglage dans `vars/main.yml` : il « ne se surcharge pas » depuis l'inventaire, et on cherche longtemps pourquoi (c'est la panne M04-E37).
- Une boucle `authorized_key` avec `exclusive: true` : seule la dernière clé reste.
- Une liste exclusive vide, ou une variable surchargée par erreur avec une valeur vide (`base_admin_cles: []` dans un `host_vars`) : verrouillage. D'où le garde-fou.
- Un template qui affiche la date ou l'uptime : `changed` à chaque passage.
- `ansible_distribution` au lieu de `ansible_facts['distribution']` : indéfini avec `inject_facts_as_vars = False` (M04-E02).
- `community.general.timezone` dans un **conteneur privilégié** (Molecule avec Docker, M12) : `timedatectl` agit sur l'hôte. Rencontré en testant ce corrigé : l'horloge de la machine de test a été décalée de deux heures. Sur une VM, aucun risque.

**En production chez MédiSphère**
Le rôle `base` est le premier appliqué à toute nouvelle VM (avant même les rôles de service), par la CI (E27). Ses paramètres sont relus par la RSSI (mises à jour, journaux, comptes). La liste des clés vient, à terme, de la PKI SSH (module 06 : certificats d'utilisateur à durée courte, plus de clés individuelles à distribuer).

---

### M04-E11 — Rôle `ssh_durci`

**Solution**

Fichiers : [`fichiers/M04-E11/ansible/`](fichiers/M04-E11/ansible/) — rôle [`roles/ssh_durci/`](fichiers/M04-E11/ansible/roles/ssh_durci/), [`playbooks/socle-base.yml`](fichiers/M04-E11/ansible/playbooks/socle-base.yml), [`host_vars/adm01/ssh_durci.yml`](fichiers/M04-E11/ansible/inventories/lab/host_vars/adm01/ssh_durci.yml) (`ssh_durci_transfert_tcp: true`), [`host_vars/gw01/ssh_durci.yml`](fichiers/M04-E11/ansible/inventories/lab/host_vars/gw01/ssh_durci.yml) (`ssh_durci_fichiers_obsoletes`).

1. **État des lieux.** `sudo sshd -T | sort > ~/m04/e11/gw01.avant` sur chaque hôte, puis `diff`. Différences typiques : `authenticationmethods publickey` sur `gw01` seulement (M00-E10) ; `maxauthtries 3`, `loglevel VERBOSE`, `clientaliveinterval 300`, `allowtcpforwarding no` sur les seules VMs de l'image dorée (M03-E13) ; `maxauthtries 6`, `loglevel INFO`, `x11forwarding yes` (valeur du `sshd_config` de Debian) ailleurs. `grep -rn` dans `/etc/ssh/` dit quel fichier fixe quoi.
   Ordre de lecture : `sshd_config` de Debian commence par `Include /etc/ssh/sshd_config.d/*.conf` ; les fichiers inclus sont lus par ordre alphabétique, **avant** la suite de `sshd_config` ; pour la plupart des mots-clés, la **première** valeur lue est retenue (`man sshd_config`, en tête). Un réglage de `01-…` l'emporte donc sur `05-durcissement.conf`, `10-…`, `50-cloud-init.conf` et sur `sshd_config` lui-même.
2. **Le rôle**, l'essentiel de [`tasks/main.yml`](fichiers/M04-E11/ansible/roles/ssh_durci/tasks/main.yml) :
   ```yaml
   - name: Fichier de durcissement de sshd
     ansible.builtin.template:
       src: ssh-durci.conf.j2
       dest: "{{ ssh_durci_fichier }}"          # /etc/ssh/sshd_config.d/01-ssh-durci.conf
       owner: root
       group: root
       mode: "0644"
       validate: /usr/sbin/sshd -t -f %s
     notify: Recharger sshd

   - name: Retirer les anciens fichiers de durcissement posés à la main
     ansible.builtin.file:
       path: "{{ item }}"
       state: absent
     loop: "{{ ssh_durci_fichiers_obsoletes }}"
     notify: Recharger sshd

   - name: Appliquer maintenant les changements en attente
     ansible.builtin.meta: flush_handlers
   ```
   puis `sshd -T` et un `assert` sur les directives qui comptent (hors `--check`). [`handlers/main.yml`](fichiers/M04-E11/ansible/roles/ssh_durci/handlers/main.yml) : deux handlers qui écoutent `Recharger sshd`, dans cet ordre : `sshd -t` (configuration **complète**), puis `state: reloaded`. Le [template](fichiers/M04-E11/ansible/roles/ssh_durci/templates/ssh-durci.conf.j2) écrit la politique ; `AllowTcpForwarding` dépend de `ssh_durci_transfert_tcp`, `DenyUsers` de `ssh_durci_utilisateurs_refuses`, et `ssh_durci_options` ajoute des directives libres.
   L'ordre « poser le nouveau, **puis** retirer l'ancien » compte : si la validation échoue, la tâche s'arrête avant la suppression, et `gw01` garde son ancien durcissement au lieu de se retrouver avec les valeurs de Debian (`PasswordAuthentication yes`) au prochain redémarrage de sshd.
3. **Application** : comme en E10, `runner01` d'abord ; nouvelle connexion :
   ```
   admin@adm01:~$ ssh -o ControlPath=none runner01 true && echo OK
   admin@poste:~$ ssh -J admin@10.10.10.10 admin@10.10.20.12 true && echo REBOND-OK
   ```
   Sans `-o ControlPath=none`, `ssh` réutiliserait la connexion maîtresse ouverte par la commande précédente (M00-E15) : le test ne prouverait rien.
4. **Validation** avec `{PermitRootLogn: "no"}` :
   ```
   TASK [ssh_durci : Fichier de durcissement de sshd] ******************************
   fatal: [runner01]: FAILED! => changed=false
     msg: 'failed to validate: rc:255 error:/tmp/…/ssh-durci.conf.j2: line 38: Bad configuration option: PermitRootLogn
       /tmp/…/ssh-durci.conf.j2: terminating, 1 bad configuration options'
   ```
   Le fichier en place n'a pas bougé (`ls -l --time-style=full-iso` ou `--diff` au passage suivant), aucun handler n'a été notifié.
5. **Réponses.**
   - `sshd -t -f <candidat>` valide le fichier **seul**, comme s'il était toute la configuration : syntaxe, mots-clés, valeurs. Il ne voit ni `sshd_config`, ni les autres fichiers du dossier, ni l'effet de l'ordre. `sshd -t` (sans `-f`) valide la configuration **réelle**, avec ses inclusions : c'est le handler qui la contrôle avant de recharger. Les deux sont nécessaires : le premier empêche de poser un fichier invalide, le second de recharger une combinaison invalide.
   - `reload` envoie `SIGHUP` au processus d'écoute : il relit sa configuration et s'applique aux **nouvelles** connexions ; les sessions existantes (des processus fils) continuent. Sur Debian, l'unité `ssh.service` lance d'abord `sshd -t` (`ExecReload=`) : une configuration invalide fait échouer le rechargement, le démon garde l'ancienne. `restart` arrête le démon : les sessions en cours survivent en général (processus séparés), mais si la nouvelle configuration est invalide, sshd **ne redémarre pas** et plus personne n'entre.
   - `01-` : passer devant tous les fichiers existants (`05-`, `10-`, `50-cloud-init.conf`), puisque la première valeur gagne. Le contrôle final (`assert` sur `sshd -T`) détecte le jour où quelqu'un ajoute un `00-…`.

**Explications**

Le dossier `sshd_config.d/` permet à plusieurs acteurs (paquet, cloud-init, image, Ansible) de contribuer sans réécrire le fichier principal du paquet (donc sans conflit à la mise à jour d'OpenSSH). En contrepartie, il faut raisonner sur l'ordre. Contrôler `sshd -T` plutôt que le fichier écrit, c'est contrôler ce que sshd **fait**, quelles que soient les contributions des autres. `AuthenticationMethods publickey` ferme la porte même si `PasswordAuthentication` était réactivé par un fichier lu plus tôt ; `DenyUsers` (E12) ajoute une barrière par compte.
`git01` : GitLab authentifie les pushes SSH par le compte `git` et ses clés (fichier `authorized_keys` géré par GitLab, ou recherche rapide par `AuthorizedKeysCommand` si elle a été activée) ; aucune directive du rôle ne touche à ce mécanisme, et `AllowTcpForwarding no` n'empêche pas Git, qui n'ouvre pas de canal de transfert.

**Alternatives**
- Réécrire `/etc/ssh/sshd_config` entièrement par template : une seule source, mais conflit à chaque mise à jour du paquet (fichier de configuration modifié), et on prend la responsabilité de tout le fichier.
- `lineinfile` sur `sshd_config` : à proscrire, fragile (la première occurrence d'un mot-clé gagne, peut-être dans un `Match`).
- Le rôle `devsec.hardening.ssh_hardening` (collection `devsec.hardening`) : complet, maintenu, mais il réécrit `sshd_config` et applique beaucoup de choix d'un coup ; bon point de départ pour comparer.

**Pièges classiques**
- `validate: sshd -t -f %s` oublié : un fichier invalide est posé, le `reload` échoue (rien ne change… jusqu'au prochain redémarrage, où sshd ne démarre plus : M04-E40).
- Tester avec une connexion multiplexée, ou avec la session déjà ouverte : tout « marche ».
- `MaxAuthTries 3` et un agent SSH chargé de nombreuses clés : le client essaie chaque clé, et la connexion échoue avant d'arriver à la bonne (`IdentitiesOnly yes` côté client).
- `AllowTcpForwarding no` sur le bastion : `ssh -J` échoue avec « channel 0: open failed: administratively prohibited ».
- `restarted` au lieu de `reloaded` dans un handler : une erreur de configuration coupe l'accès au lieu d'être refusée.

**En production chez MédiSphère**
Politique SSH relue par la RSSI à chaque MR (CODEOWNERS n'est pas dans CE : règle de revue d'équipe), contrôlée en continu par la détection de dérive (E29) et par un audit externe (`ssh-audit`, module 26). Les bastions ont leur propre politique (enregistrement des sessions, certificats courts, module 06 et 24).

---

### M04-E12 — Ansible Vault

**Solution**

Fichiers : [`fichiers/M04-E12/ansible/`](fichiers/M04-E12/ansible/) — [`ansible.cfg.extrait`](fichiers/M04-E12/ansible/ansible.cfg.extrait), [`group_vars/all/main.yml`](fichiers/M04-E12/ansible/inventories/lab/group_vars/all/main.yml), [`group_vars/all/vault.yml.exemple`](fichiers/M04-E12/ansible/inventories/lab/group_vars/all/vault.yml.exemple) (modèle **en clair**, valeurs non fonctionnelles), [`roles/base/tasks/utilisateurs.yml`](fichiers/M04-E12/ansible/roles/base/tasks/utilisateurs.yml) et [`defaults/main.yml`](fichiers/M04-E12/ansible/roles/base/defaults/main.yml) ; registre : [`M04-E13/registre-secrets-extrait.md`](fichiers/M04-E13/registre-secrets-extrait.md).

1. **Mot de passe du Vault.**
   ```
   admin@adm01:~$ ( umask 077 && openssl rand -base64 32 > ~/.config/workbook/ansible-vault.pass )
   admin@adm01:~$ ls -l ~/.config/workbook/ansible-vault.pass
   -rw------- 1 admin admin 45 … /home/admin/.config/workbook/ansible-vault.pass
   ```
   `umask 077` dans un sous-shell : le fichier naît en 600, il n'existe jamais un instant lisible par d'autres. Dans `ansible.cfg`, section `[defaults]` : `vault_identity_list = lab@~/.config/workbook/ansible-vault.pass` (le `~` est développé par Ansible).
   ```
   admin@adm01:~/src/ansible$ uv run ansible-config dump --only-changed | grep VAULT
   DEFAULT_VAULT_IDENTITY_LIST(/home/admin/src/ansible/ansible.cfg) = ['lab@~/.config/workbook/ansible-vault.pass']
   ```
2. **Empreinte et Vault.**
   ```
   admin@adm01:~$ sudo apt install -y whois                      # fournit mkpasswd
   admin@adm01:~$ read -rs MDP; echo                              # tape le mot de passe (ou colle-le depuis le coffre)
   admin@adm01:~$ printf '%s\n' "$MDP" | mkpasswd --method=yescrypt --stdin
   $y$j9T$…$…
   admin@adm01:~$ unset MDP
   admin@adm01:~/src/ansible$ uv run ansible-vault create inventories/lab/group_vars/all/vault.yml
   ```
   L'éditeur s'ouvre (`$EDITOR`) : `vault_secours_mdp_hash: "$y$j9T$…"`. Le mot de passe ne passe ni dans l'historique (`read -rs`), ni dans `ps` (entrée standard, pas d'argument). Une seule identité est déclarée : `ansible-vault` chiffre avec elle sans qu'on précise `--encrypt-vault-id`.
   ```
   admin@adm01:~/src/ansible$ head -n 2 inventories/lab/group_vars/all/vault.yml
   $ANSIBLE_VAULT;1.2;AES256;lab
   62306435653963383961393537303839643031343134656264313430663235363964346563363766
   ```
   Format `1.2` : la version qui porte l'identifiant (`lab`) ; `1.1` n'en a pas.
3. **Référence et rôle.** `main.yml` : `base_secours_mdp_hash: "{{ vault_secours_mdp_hash }}"` et `ssh_durci_utilisateurs_refuses: [secours]`. Dans le rôle, une tâche `ansible.builtin.user` (`groups: [sudo]`, `append: true`, `password`, `update_password: always`) avec `no_log: true`, exécutée seulement si l'empreinte n'est pas vide.
4. **Sans `no_log`**, en `-v` :
   ```
   changed: [runner01] => changed=true
     append: true
     comment: Compte de secours MédiSphère (console uniquement)
     …
     password: NOT_LOGGING_PASSWORD
   ```
   Le module `user` masque lui-même le paramètre `password` (option déclarée `no_log` dans le module)… mais pas le diff, ni un message d'erreur qui recopierait les arguments, ni une variable affichée par un autre module (`debug`, `command`). `no_log: true` sur la tâche est la règle de l'équipe : on ne dépend pas du soin de chaque auteur de module. Avec : `changed: [runner01] => (censored due to no_log)`.
5. **Fichier entier ou valeur chiffrée.** Choix : fichier entier (`vault.yml`) + références en clair (`main.yml`). Raisons : (a) `grep vault_secours` trouve où la variable sert sans rien déchiffrer, et une MR montre **quelle** variable change (dans `main.yml`) même si le Vault est opaque ; (b) un fichier entier reste un YAML valide pour `check-yaml` de pre-commit, alors qu'une valeur `!vault |` porte une balise que les outils YAML génériques refusent (ou ignorent) ; (c) un seul fichier à relancer en `rekey` (E30). Contre : toute modification du Vault est un bloc illisible en revue ; on compense par un message de commit précis.
6. **Console** : `ssh pve01 qm terminal 1002`, Entrée, `login: secours`, mot de passe : session ouverte ; `sudo -i` demande le mot de passe. `Ctrl+O` pour quitter. Puis :
   ```
   admin@adm01:~$ ssh -o ControlPath=none -o PreferredAuthentications=password secours@10.10.20.10
   secours@10.10.20.10: Permission denied (publickey).
   ```
   (Refus avant même la question du mot de passe : seule `publickey` est proposée, et `DenyUsers` refuserait de toute façon.) ⚠️ À vérifier sur ta version : `qm terminal` exige un port série `serial0` sur la VM (présent sur les VMs issues du template 9000 ; `gw01`, installé par ISO au M00, peut ne pas en avoir : console noVNC alors).
7. **Registre** : deux lignes (voir l'extrait). **Perte** du mot de passe du Vault : plus rien de ce qui est chiffré ne se lit ; les secrets eux-mêmes ne sont pas perdus s'ils sont aussi dans leur système d'origine (jeton `glrt-` recréable dans GitLab, mot de passe de secours dans le coffre) : on régénère chaque secret et on chiffre un nouveau Vault. D'où la copie dans le coffre de l'équipe. **Fuite** : (1) considérer **tous** les secrets du Vault comme compromis et les changer à la source (nouveau mot de passe de secours, nouveau jeton de runner…) ; (2) nouveau mot de passe de Vault (`ansible-vault rekey`) ; (3) mettre à jour la variable de CI ; (4) chercher l'origine. Changer seulement le mot de passe du Vault ne sert à rien : l'historique Git contient les anciennes versions chiffrées avec l'ancien mot de passe.

**Explications**

Ansible Vault chiffre en AES-256 (CTR + HMAC-SHA256, clé dérivée du mot de passe par PBKDF2) des fichiers ou des valeurs ; Ansible déchiffre **en mémoire**, sur le contrôleur, au moment de l'usage. Ce que Vault **ne** protège **pas** : le secret une fois envoyé à la cible (il est dans les arguments du module, dans le fichier qu'il écrit, éventuellement dans un journal), dans la sortie d'Ansible sans `no_log`, dans les faits ou les variables affichés, et dans la mémoire de quiconque connaît le mot de passe du Vault. Les identifiants de Vault (`lab`, plus tard `prod`) permettent plusieurs mots de passe dans un même projet : Ansible essaie les identités dont l'identifiant correspond à l'en-tête, puis les autres.
Une empreinte `yescrypt` (`$y$`) est le format par défaut de Debian 13 (`/etc/login.defs`, `ENCRYPT_METHOD YESCRYPT`) : coûteuse à attaquer par force brute, et le module `user` la compare telle quelle (idempotent tant que l'empreinte ne change pas). Le filtre `password_hash` d'Ansible générerait un **nouveau sel** à chaque passage (non idempotent) et demande `passlib` sous Python 3.13.

**Alternatives**
- Secrets hors du dépôt, lus à l'exécution : variables d'environnement de la CI (E27), lookup vers un gestionnaire de secrets (OpenBao, module 25 : `community.hashi_vault`), SOPS + age (module 25) qui chiffre seulement les valeurs avec des clés par personne.
- `ansible-vault encrypt_string` : lisible en contexte, pratique pour une valeur isolée dans un fichier de variables qui n'a pas d'autre secret.
- Pas de compte de secours mais un accès console par `root` avec mot de passe : refusé (compte partagé, non nominatif, et `PermitRootLogin` en dépendrait).

**Pièges classiques**
- Commiter `vault.yml` **avant** de le chiffrer, puis le chiffrer : le secret reste dans l'historique (la vérification parcourt toutes les versions). Rattrapage : changer le secret, réécrire l'historique (M01-E17) ne suffit pas.
- `vault_identity_list` sans `lab@` : l'identifiant devient `default` et les fichiers chiffrés avec `lab` se déchiffrent quand même… jusqu'au jour où il y en a deux.
- Fichier de mot de passe exécutable : Ansible l'**exécute** et lit sa sortie (c'est la fonctionnalité « script client ») ; un `chmod +x` par erreur donne « Problem running vault password script ».
- Lancer `ansible-vault` hors de la racine du projet : `ansible.cfg` n'est pas lu, on lui demande un mot de passe.
- `no_log` sur une boucle : plus aucun nom d'élément dans la sortie, dépannage aveugle.

**En production chez MédiSphère**
Un Vault par environnement (`lab`, `prod`), mots de passe dans le coffre de l'équipe et en variable de CI de type fichier (E27, E30), rotation annuelle et à chaque départ ; à terme les secrets d'exécution sortent d'Ansible pour OpenBao (module 25). Le compte de secours est testé à chaque exercice de PRA (F5), son mot de passe changé après chaque usage.

---

### M04-E13 — Inventaire dynamique Proxmox

**Solution**

Fichiers : [`fichiers/M04-E13/`](fichiers/M04-E13/) — [`pve-ansible-compte.sh`](fichiers/M04-E13/pve-ansible-compte.sh) (sur `pve01`), [`pve-ansible.env.exemple`](fichiers/M04-E13/pve-ansible.env.exemple), [`ansible/inventories/lab/proxmox.yml`](fichiers/M04-E13/ansible/inventories/lab/proxmox.yml), [`ansible/inventories/lab/host_vars/gw01/connexion.yml`](fichiers/M04-E13/ansible/inventories/lab/host_vars/gw01/connexion.yml), [`ansible/ansible.cfg.extrait`](fichiers/M04-E13/ansible/ansible.cfg.extrait), [`registre-secrets-extrait.md`](fichiers/M04-E13/registre-secrets-extrait.md).

1. **Appels de l'API** (`plugins/inventory/proxmox.py`, collection 2.1.0) et privilèges (API viewer de PVE 9) :

   | Appel | Pourquoi | Privilège exigé |
   |---|---|---|
   | `GET /cluster/status` | liste des nœuds (`_get_nodes`) | **`Sys.Audit` sur `/`** |
   | `GET /cluster/resources?type=vm` | liste des VMs | aucun (résultat **filtré** par `VM.Audit`) |
   | `GET /nodes/{nœud}/qemu/{vmid}/status/current` | état (`want_facts`) | `VM.Audit` sur `/vms/{vmid}` |
   | `GET /nodes/{nœud}/qemu/{vmid}/config` | configuration : étiquettes analysées, `ipconfig0` | `VM.Audit` |
   | `GET /nodes/{nœud}/qemu/{vmid}/snapshot` | instantanés | `VM.Audit` |
   | `GET /nodes/{nœud}/qemu/{vmid}/agent/network-get-interfaces` | adresses vues par l'agent (si `agent` activé) | `VM.GuestAgent.Audit` (PVE 8 : `VM.Monitor`) |
   | `GET /pools`, `GET /pools?poolid=lab` | groupes `proxmox_pool_…` | aucun pour la liste, `Pool.Audit` pour le contenu |

   Le piège est le premier : sans `Sys.Audit` sur `/`, la toute première requête répond 403 et **tout** l'inventaire échoue. Le poser avec un rôle large (`PVEAuditor` sur `/`, propagé) ferait voir au jeton **toutes** les VMs de l'hyperviseur, y compris tes VMs personnelles. D'où un second rôle d'un seul privilège, sur `/`, **sans propagation**.
2. **Compte** : le script crée `WBAnsible` (`VM.Audit`, `VM.GuestAgent.Audit`, `Pool.Audit`), `WBAnsibleCluster` (`Sys.Audit`), l'utilisateur, le jeton (`--privsep 1`, `--expire` à un an), et pose les ACL sur l'utilisateur **et** sur le jeton (intersection, M00-E17) :
   ```
   root@pve01:~# ./pve-ansible-compte.sh
   >>> Secret du jeton ci-dessous (« value ») : copie-le MAINTENANT dans pve-ansible.env sur adm01.
   ┌──────────────┬──────────────────────────────────────┐
   │ key          │ value                                │
   ╞══════════════╪══════════════════════════════════════╡
   │ full-tokenid │ wb-ansible@pve!ansible               │
   │ value        │ xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx │
   …
   == droits effectifs du jeton sur /vms
   root@pve01:~# pveum user token permissions wb-ansible@pve ansible --path /vms/1002
   ┌──────────┬────────────────────────────────────────┐
   │ ACL path │ Permissions                            │
   ╞══════════╪════════════════════════════════════════╡
   │ /vms/1002│ Pool.Audit,VM.Audit,VM.GuestAgent.Audit│
   root@pve01:~# pveum user token permissions wb-ansible@pve ansible --path /vms/<VMID-HORS-LAB>
   (aucune permission)
   ```
   (Sorties indicatives : la mise en forme exacte dépend de la version de `pveum`.)
3. **Fichier d'accès** : voir l'exemple. Le plugin lit `PROXMOX_URL`, `PROXMOX_USER`, `PROXMOX_TOKEN_ID` (le **nom** du jeton, `ansible` : le plugin compose `user!token_id=secret`), `PROXMOX_TOKEN_SECRET`. Les **modules** de la collection (Molecule, E24) lisent `PROXMOX_HOST` et `PROXMOX_CA_PATH`, pas `PROXMOX_URL` : le même fichier sert aux deux.
   **TLS** : le plugin fait ses requêtes avec `requests`, qui n'utilise pas le magasin du système mais son propre paquet d'autorités (`certifi`) ; et le plugin n'a pas d'option de chemin d'autorité. `requests` lit `REQUESTS_CA_BUNDLE` : on la fait pointer sur le magasin système de `adm01` (`/etc/ssl/certs/ca-certificates.crt`), qui contient l'autorité de `pve01` depuis M03-E02. Sans elle : `SSLError(… CERTIFICATE_VERIFY_FAILED …)`. Ne **jamais** contourner par `validate_certs: false`.
4. **`proxmox.yml`**, l'essentiel :
   ```yaml
   plugin: community.proxmox.proxmox
   validate_certs: true
   want_facts: true
   exclude_nodes: true
   filters:
     - not proxmox_template
     - "'socle' in (proxmox_tags_parsed | default([])) or 'env-m04' in (proxmox_tags_parsed | default([]))"
     - "'molecule' not in (proxmox_tags_parsed | default([]))"
   keyed_groups:
     - key: proxmox_tags_parsed | map('replace', '-', '_') | list
       prefix: ""
       separator: ""
   compose:
     ansible_host: proxmox_ipconfig0.ip.split('/') | first
     vmid: proxmox_vmid
   strict: false
   ```
   - `want_facts: true` est nécessaire pour `proxmox_tags_parsed` (liste) et `proxmox_ipconfig0`, que le plugin découpe déjà en dictionnaire (`{'ip': '10.10.20.10/24', 'gw': '10.10.20.1'}`). Sans lui, seule `proxmox_tags` (une chaîne `role-dns;socle`) existe.
   - `keyed_groups` avec `prefix: ""` et `separator: ""` : un groupe par étiquette, au nom exact de l'étiquette, `-` remplacé par `_` dans la clé elle-même. On obtient aussi des groupes `reseau`, `env_m04`, `role_semaphore`… : sans effet, aucun playbook ne les vise.
   - `gw01` n'a pas d'`ipconfig0` : l'expression échoue et, `strict: false`, `ansible_host` n'est pas défini par l'inventaire ; `host_vars/gw01/connexion.yml` le fixe à 10.10.10.1. Le revers de `strict: false` : une faute dans une expression passe aussi en silence ; la vérification de l'E15 (`ansible_host` doit être une IP du lab) l'attrape.
   - `vmid` sert à l'E23 (instantanés).
   ```
   admin@adm01:~/src/ansible$ set -a; . ~/.config/workbook/pve-ansible.env; set +a
   admin@adm01:~/src/ansible$ uv run ansible-inventory -i inventories/lab/proxmox.yml --graph
   @all:
     |--@ungrouped:
     |--@proxmox_all_qemu:
     …
     |--@role_routeur:
     |  |--gw01
     |--@socle:
     |  |--gw01
     |  |--adm01
     |  |--dns01
     |  |--git01
     |  |--runner01
     |--@role_bastion:
     |  |--adm01
     …
   ```
5. **Comparaison** :
   ```
   admin@adm01:~/src/ansible$ diff <(uv run ansible-inventory -i inventories/lab/hosts.yml --list | jq -S '.socle, .role_dns') \
                                   <(uv run ansible-inventory -i inventories/lab/proxmox.yml --list | jq -S '.socle, .role_dns')
   admin@adm01:~/src/ansible$ for h in gw01 adm01 dns01; do
   >   diff <(uv run ansible-inventory -i inventories/lab/hosts.yml --host $h | jq -S 'with_entries(select(.key|startswith("proxmox_")|not))') \
   >        <(uv run ansible-inventory -i inventories/lab/proxmox.yml --host $h | jq -S 'with_entries(select(.key|startswith("proxmox_")|not))')
   > done
   ```
   Restent comme différences : `vmid` (dynamique seulement) et l'ordre des hôtes. `ansible_connection: local` de `adm01` est déjà dans `host_vars/adm01/main.yml` (M04-E03) : commun aux deux sources.
6. **Inventaire par défaut** (`ansible.cfg`, `inventory = inventories/lab/proxmox.yml`). Pointer le **fichier**, pas le dossier : avec `inventories/lab/`, Ansible chargerait `hosts.yml` **et** `proxmox.yml`, fusionnerait les hôtes, et une erreur de l'un serait masquée par l'autre.
7. **Expériences.**
   (a) Sans secret :
   ```
   [WARNING]: Failed to parse inventory with 'auto' plugin: You must specify either a password or both token_id and token_secret.
   [WARNING]: Failed to parse inventory with 'ini' plugin: Failed to parse inventory: Invalid host pattern '---' supplied, '---' is normally a sign this is a YAML file.
   [WARNING]: Unable to parse /home/admin/src/ansible/inventories/lab/proxmox.yml as an inventory source
   [WARNING]: No inventory was parsed, only implicit localhost is available
   [WARNING]: Could not match supplied host pattern, ignoring: socle
   PLAY [Configuration commune du socle] ******************************************
   skipping: no hosts matched
   admin@adm01:~/src/ansible$ echo $?
   0
   ```
   Un pipeline planifié (E29) qui « réussit » sans avoir rien vérifié : le pire des résultats. Correctif dans `ansible.cfg` : `[inventory]` `unparsed_is_failed = True` → `[ERROR]: No inventory was parsed, please check your configuration and options.`, code 1.
   (b) Sans l'étiquette `socle`, `runner01` disparaît du groupe `socle` mais reste dans `role_runner` : `site.yml` ne le configurerait plus qu'à moitié (le play du runner, pas `socle-base.yml`). Les étiquettes Proxmox deviennent des **données de production** : qui peut les modifier (`VM.Config.Options`) peut sortir une VM de la configuration. C'est l'objet de la panne M04-E39.
8. **Registre** : ligne `wb-ansible@pve!ansible` (voir l'extrait).

**Explications**

Un plugin d'inventaire est un programme que l'inventaire **exécute** : il interroge une source (ici l'API), puis les options communes des plugins « construits » (`compose`, `groups`, `keyed_groups`, `filters`, `strict`) fabriquent variables et groupes à partir de ce qu'il a lu. Le nom de fichier (`…proxmox.yml`) est vérifié par le plugin (`verify_file`) ; le plugin `auto` lit la clé `plugin:` et lui passe la main. Les `group_vars/` et `host_vars/` voisins du fichier d'inventaire s'appliquent quelle que soit la source : c'est ce qui permet de garder `hosts.yml` en secours.
Un inventaire dynamique déplace la source de vérité : ce n'est plus un fichier relu en MR, c'est l'état de Proxmox. Avantage : il ne ment pas sur ce qui existe. Inconvénient : une étiquette changée dans l'interface change le périmètre d'Ansible sans revue. Le module 06 déplacera cette source de vérité dans NetBox, où les changements sont tracés.

**Alternatives**
- Garder `hosts.yml` comme source principale et ne s'en servir que pour comparer : plus simple, mais deux listes à maintenir.
- `want_facts: false` + groupes construits sur `proxmox_tags` (chaîne) : moins d'appels à l'API, mais pas d'`ipconfig0`, donc l'adresse viendrait du DNS ou des `host_vars`.
- Adresse tirée de l'agent QEMU (`proxmox_agent_interfaces`) : fonctionne pour toutes les VMs, mais `gw01` a une dizaine d'adresses, et l'agent arrêté fait disparaître l'adresse ; `ipconfig0` dit ce qui est **voulu**, l'agent ce qui **est**.
- Authentification par utilisateur et mot de passe : déconseillée (pas de séparation des privilèges, pas d'expiration propre).

**Pièges classiques**
- Nom de fichier `proxmox_lab.yml` : « Skipping due to inventory source not ending in "proxmox.yaml" nor "proxmox.yml" », visible seulement en `-vvv`.
- `PROXMOX_TOKEN_ID=wb-ansible@pve!ansible` : le plugin compose `wb-ansible@pve!wb-ansible@pve!ansible=…`, 401.
- Oublier les ACL sur l'utilisateur (seulement sur le jeton) : le jeton privsep n'a que l'intersection, donc rien.
- `PVEAuditor` sur `/` « pour aller vite » : le jeton lit toute l'infrastructure, VMs personnelles comprises.
- Groupes en `role-dns` (avec tiret) : avertissement « Invalid characters were found in group names », et selon le réglage `TRANSFORM_INVALID_GROUP_CHARS`, groupe renommé ou pas : les `group_vars/role_dns/` ne s'appliquent plus.
- Templates (`tpl-debian13`, images dorées) dans l'inventaire : `site.yml` tente de s'y connecter (`UNREACHABLE`), d'où le filtre.

**En production chez MédiSphère**
Inventaire dynamique avec cache (quelques minutes) pour la CI ; jeton d'inventaire en lecture seule, distinct de celui qui crée des VMs (Molecule, OpenTofu) ; supervision de l'expiration des jetons (alerte 30 jours avant) ; à partir du module 06, NetBox comme source de vérité et l'API Proxmox comme contrôle de cohérence.

---

### M04-E14 — Boucles, conditions et filtres

**Solution**

Fichiers : [`fichiers/M04-E14/ansible/`](fichiers/M04-E14/ansible/) — [`roles/base/tasks/utilisateurs.yml`](fichiers/M04-E14/ansible/roles/base/tasks/utilisateurs.yml), [`roles/base/tasks/paquets.yml`](fichiers/M04-E14/ansible/roles/base/tasks/paquets.yml), [`roles/base/defaults/main.yml`](fichiers/M04-E14/ansible/roles/base/defaults/main.yml), [`group_vars/all/main.yml`](fichiers/M04-E14/ansible/inventories/lab/group_vars/all/main.yml) ; ressource : [`semer-heritage-infoger.sh`](../ressources/M04-E14/semer-heritage-infoger.sh).

1. Après le script :
   ```
   admin@adm01:~$ ssh dns01 'getent passwd infoger; ssh-keygen -lf ~admin/.ssh/authorized_keys'
   infoger:x:1002:1002:InfoGer - astreinte N2:/home/infoger:/bin/bash
   256 SHA256:… admin@adm01 (ED25519)
   256 SHA256:… infoger@legacy (ED25519)
   ```
2. **Les données** (`group_vars/all/main.yml`) :
   ```yaml
   base_utilisateurs:
     - nom: admin
       cles: "{{ ms_cles_admin }}"
     - nom: secours
       commentaire: "Compte de secours MédiSphère (console uniquement)"
       shell: /bin/bash
       groupes: [sudo]
       mdp_hash: "{{ vault_secours_mdp_hash }}"
       ssh: false
     - nom: infoger
       etat: absent
   ssh_durci_utilisateurs_refuses: >-
     {{ base_utilisateurs | selectattr('ssh', 'defined') | rejectattr('ssh')
        | map(attribute='nom') | list }}
   ```
   `ssh_durci_utilisateurs_refuses` est **calculée** au moment où le rôle `ssh_durci` la lit : ajouter un compte `ssh: false` le refuse aussi dans sshd, sans y penser.
3. **Les tâches.** Normalisation, une seule expression :
   ```yaml
   - name: Assembler les comptes de cet hôte
     ansible.builtin.set_fact:
       _base_comptes: >-
         {{ [base_compte_defaut]
            | product(base_utilisateurs + base_utilisateurs_hote)
            | map('ansible.builtin.combine')
            | list }}
   ```
   `product` forme les paires `(défauts, compte)` ; `combine` accepte une liste de dictionnaires et les fusionne de gauche à droite : chaque compte reçoit `etat: present`, `ssh: true`, `cles: []`, puis ses propres champs par-dessus. Ensuite un `assert` (pas de nom en double : `map(attribute='nom') | unique | length == … | length` ; états connus : `difference(['present', 'absent']) | length == 0` ; `admin` présent avec au moins une clé), puis des boucles **filtrées** :

   | Tâche | Boucle sur |
   |---|---|
   | comptes présents (`user`, sans mot de passe) | `selectattr('etat', 'equalto', 'present')` |
   | mots de passe (`no_log: true`) | présents `| selectattr('mdp_hash', 'defined')` |
   | clés autorisées (`authorized_key`, `exclusive: true`) | présents `| selectattr('ssh') | selectattr('cles', 'truthy')` |
   | aucune clé pour les comptes sans SSH (`file: state=absent`) | présents `| rejectattr('ssh')` |
   | comptes supprimés (`user: state=absent, remove: true`) | `selectattr('etat', 'equalto', 'absent')` |

   `loop_control: label: "{{ item.nom }}"` : la sortie affiche le nom du compte au lieu du dictionnaire entier (et pas l'empreinte).
4. **Agent QEMU** :
   ```yaml
   - name: Agent QEMU (VM KVM uniquement)
     when:
       - base_agent_qemu
       - ansible_facts['virtualization_role'] == 'guest'
       - ansible_facts['virtualization_type'] == 'kvm'
     block: …
   ```
   Une liste sous `when` est un « et ». Chaque élément est une expression booléenne.
5. **Prévision** (`~/m04/e14/prevision.yml`, jetable) : les mêmes données, normalisées comme dans le rôle, puis une expression par information.
   ```yaml
   - name: Prévoir les comptes
     hosts: socle
     gather_facts: false
     vars:
       _comptes: "{{ [{'etat': 'present', 'cles': []}] | product(base_utilisateurs) | map('ansible.builtin.combine') | list }}"
     tasks:
       - name: Comptes par hôte
         ansible.builtin.debug:
           msg:
             presents: "{{ _comptes | selectattr('etat', 'equalto', 'present') | map(attribute='nom') | list }}"
             supprimes: "{{ _comptes | selectattr('etat', 'equalto', 'absent') | map(attribute='nom') | list }}"
             cles: "{{ dict(_comptes | map(attribute='nom') | zip(_comptes | map(attribute='cles') | map('length'))) }}"
   ```
   ```
   ok: [adm01] => msg:
     cles: {admin: 1, infoger: 0, secours: 0}
     presents: [admin, secours]
     supprimes: [infoger]
   ```
   (`zip` apparie deux listes, `dict()` transforme les paires en dictionnaire.) Prévoir avant d'appliquer, c'est le réflexe à garder : la même expression sert ensuite dans un `assert`.
6. Application :
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/socle-base.yml --check --diff --tags base_utilisateurs
   TASK [base : Clés SSH autorisées (liste exclusive)] ******************************
   --- before: /home/admin/.ssh/authorized_keys
   +++ after: /home/admin/.ssh/authorized_keys
   @@ -1,2 +1 @@
    ssh-ed25519 AAAA… admin@adm01
   -ssh-ed25519 AAAA… infoger@legacy
   changed: [dns01] => (item=admin (1 clé(s)))
   TASK [base : Comptes supprimés (et leur dossier personnel)] *********************
   changed: [dns01] => (item=infoger)
   ```
7. **Réponses.** `loop:` est la forme recommandée depuis Ansible 2.5 : une liste explicite, que l'on transforme avec des filtres ; les `with_<lookup>` restent valides mais mélangent récupération des données et itération, et `with_items` aplatit silencieusement un niveau de liste (source de surprises). `loop_control: label` limite ce qui est affiché pour chaque élément (lisibilité, et rien de sensible dans la sortie). `when: base_utilisateurs` : depuis la 2.19, une condition doit **produire un booléen** ; une liste non vide était « vraie » par conversion implicite, ce n'est plus accepté (« Conditional result … was derived from value of type 'list' »). Écrire `when: base_utilisateurs | length > 0`.

**Explications**

Le rôle devient un **moteur** et l'inventaire la **description** : ajouter, retirer, restreindre un compte se fait dans les données, relu en MR, sans toucher au code. Les filtres travaillent sur des listes de dictionnaires comme une petite base : `selectattr`/`rejectattr` (où), `map(attribute=…)` (quelle colonne), `combine` (fusion), `product`, `zip`, `items2dict`/`dict2items` (changement de forme). Les tests (`defined`, `equalto`, `truthy`, `match`) s'utilisent dans `selectattr` et dans les conditions.
Une suppression déclarée (`etat: absent`) est le seul moyen de **retirer** quelque chose avec un outil déclaratif : retirer la ligne de la liste ne supprimerait pas le compte sur les hôtes, il serait simplement « plus géré ».

**Alternatives**
- Un dictionnaire de comptes (`{admin: {…}, secours: {…}}`) plutôt qu'une liste : fusion par hôte plus naturelle (`combine` récursif), mais ordre et lisibilité moindres.
- Tâche `set_fact` dans une boucle pour normaliser (accumuler `_base_comptes + [defaut | combine(item)]`) : plus lisible pour certains, plus de lignes dans la sortie.
- `ansible.builtin.user` avec `state` calculé (`present`/`absent`) dans une seule tâche : possible, mais les paramètres sans objet pour une suppression rendent la tâche confuse.

**Pièges classiques**
- `selectattr('etat', 'equalto', 'present')` sur des comptes **non normalisés** : ceux qui n'ont pas de champ `etat` sont exclus (d'où la normalisation préalable).
- `no_log: true` sur la boucle des comptes présents : plus aucun nom visible, et un échec devient indéchiffrable.
- `remove: true` sur un compte encore connecté ou qui a des processus : `userdel` échoue ; arrêter ses processus d'abord (ou `force: true`, en sachant ce qu'on fait).
- Faire de `cles` une chaîne au lieu d'une liste : `join('\n')` sur une chaîne insère un saut de ligne entre chaque **caractère**.
- Calculer `ssh_durci_utilisateurs_refuses` dans un rôle à partir d'une variable d'un autre rôle : couplage caché ; la dériver dans l'**inventaire**, là où les deux se rencontrent.

**En production chez MédiSphère**
Les comptes humains viennent de l'annuaire (FreeIPA ou Keycloak, module 24) et les accès SSH de certificats à durée courte (module 06) ; la liste locale ne garde que les comptes techniques et de secours. Un contrôle périodique (E29) signale tout compte ou clé non déclaré : c'est exactement ce qu'a trouvé l'audit.

---

### M04-E15 — Gestion d'erreurs : `block`, `rescue`, `assert`

**Solution**

Fichiers : [`fichiers/M04-E15/ansible/`](fichiers/M04-E15/ansible/) — [`roles/base/meta/argument_specs.yml`](fichiers/M04-E15/ansible/roles/base/meta/argument_specs.yml), [`roles/base/tasks/temps.yml`](fichiers/M04-E15/ansible/roles/base/tasks/temps.yml), [`roles/base/handlers/main.yml`](fichiers/M04-E15/ansible/roles/base/handlers/main.yml), [`roles/base/defaults/main.yml`](fichiers/M04-E15/ansible/roles/base/defaults/main.yml), [`playbooks/socle-base.yml`](fichiers/M04-E15/ansible/playbooks/socle-base.yml).

1. **Contrat** : une entrée par variable (type, éléments, choix), les champs des comptes déclarés une fois (ancre YAML `&compte`) et réutilisés pour `base_utilisateurs_hote`. Ansible ajoute en tête du rôle une tâche implicite « Validating arguments against arg spec 'main' » (module `validate_argument_spec`).
   ```
   admin@adm01:~/src/ansible$ uv run ansible-doc -t role -r roles base
   > ROLE: base (/home/admin/src/ansible/roles/base)
   ENTRY POINT: main - Configuration commune des VMs du socle MédiSphère
   Options (red indicates it is required):
      base_admin_utilisateur  Compte qui doit toujours garder au moins une clé.
                              type: str
   …
   ```
2. **Les trois valeurs fausses** :
   - `base_chrony_client: "peut-etre"` : refusée par le contrat, avant la première tâche du rôle : « argument 'base_chrony_client' is of type str and we were unable to convert to bool: The value 'peut-etre' is not a valid boolean ».
   - `base_paquets: {}` : refusée (« unable to convert to list »).
   - `base_ntp_serveurs: "10.10.20.1"` : **acceptée** par le contrat. Le type `list` convertit une chaîne en liste en la découpant aux virgules : `"10.10.20.1"` devient `["10.10.20.1"]`, et le rôle fonctionne. C'est voulu par Ansible (compatibilité avec `-e cle=a,b`), mais ce n'est pas une validation de contenu : le format d'une adresse se vérifie par un `assert`.
3. **Le bloc** (extrait) :
   ```yaml
   - name: Client chrony
     when: base_chrony_client
     block:
       - name: Vérifier les sources de temps (adresses IPv4 ou noms, sans espace)
         ansible.builtin.assert:
           that:
             - base_ntp_serveurs | length > 0
             - base_ntp_serveurs | reject('match', '^[A-Za-z0-9.:-]+$') | list | length == 0
       - name: Configuration de chrony (validée avant d'être mise en place)
         ansible.builtin.template: { src: chrony.conf.j2, dest: /etc/chrony/chrony.conf, …, backup: true, validate: chronyd -p -f %s }
         register: _base_chrony_conf
       - name: Redémarrer chrony maintenant (configuration modifiée)  # noqa: no-handler
         ansible.builtin.systemd_service: { name: chrony, state: restarted, enabled: true }
         when: _base_chrony_conf is changed
       - name: Attendre la synchronisation (correction < 0,1 s)
         ansible.builtin.command: chronyc -n waitsync {{ base_chrony_essais_sync }} 0.1 0 3
         changed_when: false
         check_mode: false
         when: [base_chrony_attendre_sync, not ansible_check_mode]
       - name: Retirer la source posée à la main (M00-E31), remplacée par le template
         ansible.builtin.file: { path: /etc/chrony/sources.d/lab.sources, state: absent }
     rescue:
       - name: Remettre la configuration précédente de chrony
         ansible.builtin.copy: { src: "{{ _base_chrony_conf.backup_file }}", dest: /etc/chrony/chrony.conf, remote_src: true, … }
         when: _base_chrony_conf.backup_file is defined
       - name: Redémarrer chrony sur la configuration précédente
         …
       - name: Échouer en expliquant
         ansible.builtin.fail:
           msg: >-
             {{ inventory_hostname }} : la tâche « {{ ansible_failed_task.name }} » a échoué
             ({{ ansible_failed_result.msg | default('voir ci-dessus') }}). …
   ```
   Le `rescue` sans `fail` final « avalerait » l'erreur : le playbook continuerait en vert, et personne ne saurait que la source n'a pas été changée. On remet en état **et** on échoue.
4. **`pre_tasks`** : distribution (`ansible_facts['distribution'] == 'Debian'` et version majeure `'13'`) et `ansible_host is match('^10\.10\.[0-9]{1,3}\.[0-9]{1,3}$')`, étiquetées `always` (elles doivent tourner même avec `--tags`).
5. **L'échec provoqué** :
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/socle-base.yml --limit runner01 -e '{"base_ntp_serveurs": ["10.10.20.13"]}'
   TASK [base : Configuration de chrony (validée avant d'être mise en place)] ********
   changed: [runner01]
   TASK [base : Redémarrer chrony maintenant (configuration modifiée)] **************
   changed: [runner01]
   TASK [base : Attendre la synchronisation (correction < 0,1 s)] *******************
   fatal: [runner01]: FAILED! => changed=false
     cmd: [chronyc, -n, waitsync, '20', '0.1', '0', '3']
     msg: non-zero return code
     rc: 1
   TASK [base : Remettre la configuration précédente de chrony] *********************
   changed: [runner01]
   TASK [base : Redémarrer chrony sur la configuration précédente] ******************
   changed: [runner01]
   TASK [base : Échouer en expliquant] **********************************************
   fatal: [runner01]: FAILED! => changed=false
     msg: 'runner01 : la tâche « Attendre la synchronisation (correction < 0,1 s) » a échoué
       (non-zero return code). La configuration précédente de chrony a été remise
       (/etc/chrony/chrony.conf.4711.2026-10-07@21:42:10~). Vérifie le service NTP de 10.10.20.13
       et le flux UDP 123 sur gw01.'
   PLAY RECAP ***********************************************************************
   runner01 : ok=19 changed=4 unreachable=0 failed=1 skipped=6 rescued=1 ignored=0
   ```
   (Sortie réelle d'un essai sur conteneur, adaptée ; le délai d'attente est d'environ une minute.) `chronyc -n sources` montre de nouveau `^* 10.10.20.1`. `lab.sources`, retiré **après** la synchronisation seulement, n'a pas été touché : l'ancienne configuration retrouve exactement ses sources.
6. **Réponses.**
   - Le redémarrage n'est plus un handler parce que la vérification doit le **suivre** dans le bloc ; un handler ne s'exécute qu'en fin de play (ou à `flush_handlers`), et un échec dans un handler n'est pas rattrapé par le `rescue` du bloc qui l'a notifié. ansible-lint signale ce schéma (`no-handler`) : l'exception est justifiée sur la ligne.
   - `ignore_errors: true` **continue** comme si de rien n'était (la tâche reste rouge dans la sortie, le récapitulatif la compte en `ignored`) : aucune réparation. `rescue` exécute une réparation et permet de décider ensuite (échouer ou continuer). `failed_when` **redéfinit** ce qu'est un échec (un code retour 1 qui veut dire « rien à faire », par exemple).
   - `any_errors_fatal: true` : sur un play où un échec partiel est pire qu'un arrêt général, par exemple un changement de protocole qui doit être cohérent sur tous les hôtes (une nouvelle autorité de certification : moitié des hôtes avec, moitié sans, et plus rien ne se parle). `max_fail_percentage` : sur une mise à jour progressive (`serial`, E25) ; on arrête si plus de N % d'un lot échoue.
   - Un hôte `UNREACHABLE` ne passe **pas** par le `rescue` : il est retiré du play. Le rôle `pare_feu` (E17) doit en tenir compte.

**Explications**

Trois niveaux de défense, du moins cher au plus cher : le **contrat** (type et présence, sans connexion à l'hôte : on refuse avant de commencer), les **assertions** (le sens des valeurs, et l'état de l'hôte : bonne distribution, bonne adresse), le **rescue** (le changement a commencé, l'hôte doit revenir à un état connu). Un rescue n'est utile que s'il sait **ce qu'il défait** : ici la sauvegarde horodatée du template, et la règle « ce qui ne se défait pas facilement (supprimer `lab.sources`) arrive en dernier ».

**Alternatives**
- `validate:` seul (E08) : protège contre un fichier invalide, pas contre un fichier valide qui ne marche pas (mauvaise adresse).
- Un handler suivi de `meta: flush_handlers` et d'une vérification hors du bloc : plus idiomatique, mais pas de retour arrière automatique.
- Un `always:` pour nettoyer les sauvegardes horodatées (`chrony.conf.<pid>.<date>~`) : utile si elles s'accumulent ; ici on les garde (traçabilité), un nettoyage périodique peut s'en charger.

**Pièges classiques**
- Un `rescue` qui « répare » puis laisse le play réussir : l'erreur disparaît des rapports.
- Utiliser `_base_chrony_conf.backup_file` sans tester qu'il existe : quand l'échec arrive avant la modification (assert), le `rescue` échoue à son tour avec une variable indéfinie, et le message utile est perdu.
- `when:` sur un `block` : la condition est recopiée sur **chaque** tâche du bloc et réévaluée à chacune ; une condition qui dépend d'un résultat produit dans le bloc peut changer en cours de route.
- Tester l'erreur en `--check` : `chronyc waitsync` est sauté, rien n'échoue, et on croit le rescue inutile.

**En production chez MédiSphère**
Les rôles sensibles (temps, SSH, pare-feu, DNS) ont tous un contrat et un retour arrière automatique ; les messages d'erreur citent le runbook à suivre (RB-040). Les échecs rattrapés sont remontés en alerte (un `rescue` qui a servi est un incident, même s'il a tout remis en ordre).

---

### M04-E16 — Rôle `gitlab_runner` : reprendre `runner01` en code

**Solution**

Fichiers : [`fichiers/M04-E16/ansible/`](fichiers/M04-E16/ansible/) — rôle [`roles/gitlab_runner/`](fichiers/M04-E16/ansible/roles/gitlab_runner/) (`defaults/main.yml` documente chaque version et sa provenance), [`playbooks/runner01.yml`](fichiers/M04-E16/ansible/playbooks/runner01.yml), [`host_vars/runner01/gitlab_runner.yml`](fichiers/M04-E16/ansible/inventories/lab/host_vars/runner01/gitlab_runner.yml) ; le jeton dans `vault.yml` (`vault_gitlab_runner_jeton`, modèle dans [`M04-E12/…/vault.yml.exemple`](fichiers/M04-E12/ansible/inventories/lab/group_vars/all/vault.yml.exemple)). Livrable documentaire : [`roles/gitlab_runner/README.md`](fichiers/M04-E16/ansible/roles/gitlab_runner/README.md) (ce qui est installé, d'où, comment monter une version, comment recréer `runner01`).

**Découpage** ([`tasks/main.yml`](fichiers/M04-E16/ansible/roles/gitlab_runner/tasks/main.yml)) : préconditions (versions et empreintes renseignées, `python3-debian` et `gnupg` présents) → autorités de certification → GitLab Runner (dépôt, paquets, enregistrement) → outils APT → binaires → outils Python → Node.js et `/opt/release-tools` → Packer → contrôle final sous le compte `gitlab-runner`. Étiquettes `runner_service`, `runner_outils`, `runner_verifier`.

| Élément | Provenance | Vérification d'intégrité | Où |
|---|---|---|---|
| GitLab Runner + images d'assistance, `=<version>-1`, figés | dépôt `packages.gitlab.com/runner/gitlab-runner/debian`, suite `trixie` | signature APT, clé dont l'**empreinte** est comparée (`F640 3F65 44A3 8863 DAA0 B6E0 3F01 618A 5131 2F3F`, relevée le 2026-10-07) avant installation | `/etc/apt/sources.list.d/gitlab-runner.sources`, `/etc/apt/keyrings/gitlab-runner.asc` |
| ShellCheck `0.11.*` | `trixie-backports` (déclaré seulement s'il ne l'est pas déjà) | signature du dépôt Debian | `/usr/bin` |
| gitleaks 8.30.1, shfmt 3.14.1, jq 1.8.2, Task 3.54.0, uv 0.12.23 | releases GitHub | SHA-256 dans `defaults/` (fichiers de sommes des releases ; shfmt : empreinte de la page de release) | `/opt/ci-outils/<nom>-<version>/`, liens dans `/usr/local/bin` |
| bats-core 1.13.0 | archive de l'étiquette | SHA-256 **relevée par toi** en M02-E24 (aucune n'est publiée) | `/opt/ci-outils/bats-1.13.0/` |
| pre-commit 4.6.2 | PyPI par `uv tool install` | index PyPI en HTTPS | `/opt/uv-tools`, lien `/usr/local/bin/pre-commit` |
| Node.js 24 | `deb.nodesource.com/node_24.x`, suite `nodistro`, priorité 600 | clé d'empreinte `6F71 F525 2828 41EE DAF8 51B4 2F59 B5F9 9B1B E0B4` | `/etc/apt/sources.list.d/nodesource.sources` |
| `/opt/release-tools` | verrou `package-lock.json` de `plateforme/ci-templates` (copié depuis le clone `~/src/ci-templates` du contrôleur) | empreintes d'intégrité du verrou, `npm ci --ignore-scripts` (script de M01-E24, réutilisé tel quel) | `/opt/release-tools` (root, lecture seule pour les jobs) |
| Packer `1.16.*` | `apt.releases.hashicorp.com`, suite `trixie` | clé d'empreinte `D55C 0D1A C78A 8D81 26CB 631C FC9C A96A CA02 6560` (M03-E02) | `/usr/bin/packer` |
| CA provisoire, CA de `pve01` | fichiers du contrôleur (`~/pki-provisoire/ca.crt`, `~/.config/workbook/pve-root-ca.pem`) | — | `/usr/local/share/ca-certificates/` |

⚠️ À vérifier sur ta version : les empreintes de clés et de fichiers de ce tableau ont été relevées le 7 octobre 2026 ; compare-les avec les pages officielles (GitLab : *Package signatures* ; NodeSource : dépôt `distributions` ; HashiCorp : *PGP public keys*) avant de leur faire confiance. Une clé d'éditeur peut changer (rotation) : c'est alors l'assertion du rôle qui t'arrête, comme prévu.

**Points de conception**

1. **Clés de dépôt** ([`tasks/cle_apt.yml`](fichiers/M04-E16/ansible/roles/gitlab_runner/tasks/cle_apt.yml), inclus trois fois avec `vars:`) : téléchargement **à part** (`/var/tmp/cle-<nom>.asc`), lecture des empreintes (`gpg --batch --show-keys --with-colons`, lignes `fpr:`), `assert` sur l'empreinte attendue, **puis** copie dans `/etc/apt/keyrings/`. Une clé inattendue n'atteint jamais le trousseau d'APT. `deb822_repository` écrit le fichier `.sources` (et a besoin de `python3-debian` sur la cible).
2. **Reprise de l'existant** : le script de M01-E23 avait créé `runner_gitlab-runner.list` avec un autre trousseau ; deux déclarations du même dépôt avec deux `Signed-By` différents font échouer `apt update` (« Conflicting values set for option Signed-By »). Le rôle supprime l'ancien fichier et l'ancien trousseau. Pour NodeSource et HashiCorp, le rôle reprend **le même nom de fichier** que M01-E14 et M03-E15 : il le remplace au lieu d'en ajouter un.
3. **Paquets figés** : `apt` avec `name: gitlab-runner=<version>-1` et `allow_change_held_packages: true` (sans quoi un paquet figé ne peut pas changer de version, même voulu), puis `dpkg_selections: hold`. Monter de version = changer `gitlab_runner_version` dans `host_vars`, MR, passage.
4. **Enregistrement idempotent** ([`tasks/runner.yml`](fichiers/M04-E16/ansible/roles/gitlab_runner/tasks/runner.yml)) : `config.toml` est lu (`slurp`) ; si une section `name = "runner01-shell"` existe, rien à faire. Sinon : `assert` sur la présence d'un jeton `glrt-`, puis
   ```yaml
   - name: Enregistrer le runner
     ansible.builtin.command:
       argv: [gitlab-runner, register, --non-interactive, --url, "{{ gitlab_runner_url }}",
              --executor, "{{ gitlab_runner_executeur }}", --description, "{{ gitlab_runner_nom }}"]
     environment:
       CI_SERVER_TOKEN: "{{ gitlab_runner_jeton }}"
     no_log: true
     changed_when: true
     when: not _gitlab_runner_enregistre
   ```
   `--token` de `gitlab-runner register` correspond à la variable d'environnement `CI_SERVER_TOKEN` (`env:"CI_SERVER_TOKEN"` dans le code de GitLab Runner, `common/config.go`) : le jeton n'est pas dans la ligne de commande, donc pas dans `ps`. C'est la réponse au « ⚠️ À vérifier » laissé en M01-E23. ⚠️ À vérifier sur ta version : `sudo gitlab-runner register --help | grep -A1 -- '--token'` doit afficher `$CI_SERVER_TOKEN`.
5. **Ce que le rôle ne possède pas** : `config.toml` n'est **pas** un template. GitLab Runner le réécrit lui-même (rotation automatique du jeton, champs `token_obtained_at`, `id`) ; un template remettrait l'ancien contenu à chaque passage (`changed` permanent, voire jeton périmé réinjecté). Le rôle ne règle que ce qui lui appartient : `concurrent = 2` (`lineinfile`, en tête de fichier) et les droits du fichier (600, root).
6. **Binaires versionnés** ([`tasks/outils_binaires.yml`](fichiers/M04-E16/ansible/roles/gitlab_runner/tasks/outils_binaires.yml)) : `get_url` avec `checksum: sha256:…` dans `/opt/ci-outils/<nom>-<version>/` (ou `archives/` puis `unarchive` avec `creates:`), puis `file: state=link force=true` dans `/usr/local/bin`. Pas besoin d'interroger la version installée : si le fichier existe avec la bonne empreinte, `get_url` ne fait rien. `force: true` remplace aussi les fichiers ordinaires posés par les scripts de M01/M02. Changer de version = une ligne ; revenir en arrière = remettre l'ancienne ligne (l'ancien dossier est toujours là).
7. **Rétroportages** ([`tasks/outils_apt.yml`](fichiers/M04-E16/ansible/roles/gitlab_runner/tasks/outils_apt.yml)) : avec `default_release: trixie-backports`, le module `apt` refuse une version de Debian que le **cache** ne connaît pas encore (« The value 'trixie-backports' is invalid for APT::Default-Release as such a release is not available in the sources »), **avant** de mettre le cache à jour. D'où une tâche de mise à jour du cache, déclenchée si `apt-cache policy` ne connaît pas encore les rétroportages. Le test sur « le dépôt vient d'être ajouté » ne suffit pas : un passage interrompu juste après l'ajout laisserait le cache périmé pour toujours (rencontré en testant ce corrigé).
8. **pre-commit** : `uv tool list` → si `pre-commit v4.6.2` n'y est pas, `uv tool install --python /usr/bin/python3 pre-commit==4.6.2` (uv remplace une autre version installée). Les droits (`go+rX`) ne sont corrigés que si `find` trouve un fichier illisible : un `file: recurse: true` se déclare **toujours** « changed » en `--check`, ce qui fausserait le contrôle d'idempotence.
9. **Contrôle final** ([`tasks/verifier.yml`](fichiers/M04-E16/ansible/roles/gitlab_runner/tasks/verifier.yml)) : `sudo -u gitlab-runner -H bash -lc 'command -v <outil>'` pour chaque outil (le `PATH` d'un job est celui du shell de connexion de `gitlab-runner`) ; `test -w /opt/release-tools/node_modules` doit **échouer** pour ce compte ; `id -nG gitlab-runner` ne doit contenir ni `sudo`, ni `adm`, ni `docker`.

**Application**
```
admin@adm01:~/src/ansible$ uv run ansible-vault edit inventories/lab/group_vars/all/vault.yml   # vault_gitlab_runner_jeton: "glrt-…"
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/runner01.yml --check --diff
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/runner01.yml
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/runner01.yml          # changed=0
```
Le jeton du runner existant se lit dans `/etc/gitlab-runner/config.toml` (`sudo grep token …` sur `runner01`) : le copier dans le Vault avec `ansible-vault edit`, sans le faire transiter par un fichier.
**Recréer `runner01`** (critère facultatif, sur 2040) : `qm clone` de l'image dorée `current` (M03), réseau `vinfra`, puis un runner **neuf** dans GitLab (*Admin → CI/CD → Runners → Create instance runner*, mêmes étiquettes), son jeton dans une variable passée en `-e @fichier-chiffré` ou dans le Vault, et `ansible-playbook playbooks/runner01.yml --limit <hôte>`. Un runner = un objet GitLab : deux VMs ne partagent pas un jeton.

**Explications**

Ce rôle est l'occasion de voir les trois façons d'installer un logiciel tiers proprement : par un **dépôt signé** (la confiance porte sur une clé, qu'on vérifie une fois par son empreinte), par un **fichier dont on connaît l'empreinte** (la confiance porte sur une valeur relevée ailleurs, versionnée dans le dépôt), par un **verrou** (npm : chaque paquet a son empreinte d'intégrité dans le fichier de verrouillage). Dans les trois cas, le dépôt Git dit exactement ce qui est installé, et un changement passe par une MR.
L'idempotence d'une opération qui ne l'est pas (enregistrer un runner crée un objet côté GitLab) s'obtient en **observant** l'état avant d'agir (`slurp` + recherche), pas en ignorant l'erreur d'un second enregistrement.

**Alternatives**
- Le rôle de la communauté `riemers.gitlab-runner` : complet, mais il génère `config.toml` et suit ses propres conventions ; à étudier pour comparer.
- Créer le runner **par l'API** depuis Ansible (`community.general.gitlab_runner`, avec un jeton d'API) : plus aucune action manuelle, mais un jeton de création de runners de plus à protéger.
- Une image de VM « runner » construite par Packer (M03) : la VM se recrée en une minute, Ansible ne fait plus que l'enregistrement et les réglages. Complémentaire, pas opposé.
- Les outils de CI dans des **images de conteneurs** (exécuteur `docker`, M12/M19) : la meilleure réponse à long terme ; ce rôle fond alors à presque rien.

**Pièges classiques**
- `--registration-token` (ancien flux, déprécié, suppression annoncée en 20.0) au lieu de `--token glrt-…`.
- Templater `config.toml` : le runner et Ansible se battent, et le jeton tourné par GitLab est écrasé.
- `--token "{{ jeton }}"` dans `argv` : visible dans `ps` pendant l'enregistrement, et dans la sortie sans `no_log`.
- `get_url` sans `checksum`, ou avec une somme téléchargée depuis le même serveur que le fichier (protège de la corruption, pas d'une compromission du serveur).
- Installer pre-commit pour root seulement (`uv tool install` sans `UV_TOOL_DIR`) : « command not found » dans les jobs.
- `gitlab-runner` et `gitlab-runner-helper-images` à des versions différentes : dépendances non satisfaites.

**En production chez MédiSphère**
Runners recréés à partir d'une image et de ce rôle, régulièrement (une VM de CI n'a pas d'état à garder) ; mises à jour de GitLab Runner synchronisées avec celles de GitLab (même major.minor, RB-011) ; outils de CI dans des images signées (modules 13 et 19) ; jetons de runners tournés et supervisés.

---

### M04-E17 — Rôle `pare_feu` pour `gw01` sans se couper la branche

**Solution**

Fichiers : [`fichiers/M04-E17/ansible/`](fichiers/M04-E17/ansible/) — rôle [`roles/pare_feu/`](fichiers/M04-E17/ansible/roles/pare_feu/) (template avec macro, [`tasks/main.yml`](fichiers/M04-E17/ansible/roles/pare_feu/tasks/main.yml), [`tasks/appliquer.yml`](fichiers/M04-E17/ansible/roles/pare_feu/tasks/appliquer.yml), script [`files/pare-feu-retour`](fichiers/M04-E17/ansible/roles/pare_feu/files/pare-feu-retour)), la matrice [`host_vars/gw01/pare_feu.yml`](fichiers/M04-E17/ansible/inventories/lab/host_vars/gw01/pare_feu.yml), le playbook [`playbooks/gw01-pare-feu.yml`](fichiers/M04-E17/ansible/playbooks/gw01-pare-feu.yml).

1. **La matrice.** `pare_feu_definitions` (liste ordonnée `nom`/`valeur`/`commentaire`), `pare_feu_entree` (8 flux), `pare_feu_transit` (19 flux), `pare_feu_nat` (2 règles), `pare_feu_verifications` (flux testés depuis `adm01`). Un flux :
   ```yaml
   - {entree: $V_INFRA, source: $RUNNER01, sortie: $WAN, destination: $PVE01, proto: tcp, ports: 8006,
      motif: "runner01 vers l'API de pve01", ref: M03-E15}
   ```
   devient `iifname $V_INFRA oifname $WAN ip saddr $RUNNER01 ip daddr $PVE01 tcp dport 8006 accept comment "runner01 vers l'API de pve01 (M03-E15)"`. `proto: tcp_udp` donne `meta l4proto { tcp, udp } th dport …` ; une liste donne un ensemble `{ a, b }` ; `destination: "!= $LAN_MAISON"` passe tel quel. Restent dans le template : états conntrack, `lo`, ICMP et ICMPv6 de base, journalisation et compteur finals, chaîne `output`.
2. **Le rôle** ([`tasks/main.yml`](fichiers/M04-E17/ansible/roles/pare_feu/tasks/main.yml)) :
   - `assert` sur la matrice (chaque flux a un motif, sans guillemet, 100 caractères au plus ; délai de retour > délai de confirmation + 30 s) ;
   - `nft -c -f -` sur le fichier rendu (`stdin: "{{ lookup('ansible.builtin.template', 'nftables.conf.j2') }}"`, `check_mode: false`) : la validation tourne aussi en `--check`, sans rien écrire sur `gw01` ;
   - prévision : le module `template` forcé en `check_mode: true` (`register: _pare_feu_prevision`) — avec `--diff`, c'est le diff relu en MR ;
   - `include_tasks: appliquer.yml` **seulement** si la prévision annonce un changement et qu'on n'est pas en `--check`. Un `include` dynamique, parce que `meta: reset_connection` ignore les conditions (avertissement « reset_connection task does not support when conditional », et exécution quand même) : on ne charge le fichier que quand il doit s'exécuter.
   [`tasks/appliquer.yml`](fichiers/M04-E17/ansible/roles/pare_feu/tasks/appliquer.yml) :
   ```yaml
   - name: Appliquer et confirmer
     block:
       - name: Sauvegarder la configuration en place            # copy remote_src → /var/lib/pare-feu/nftables.conf.precedent
       - name: Nettoyer une minuterie restée d'un passage interrompu  # systemctl stop / reset-failed
       - name: Armer le retour automatique, délai en secondes {{ pare_feu_delai_retour }}
         ansible.builtin.command:
           argv: [systemd-run, --unit=pare-feu-retour, "--description=…", "--on-active={{ pare_feu_delai_retour }}s",
                  --collect, /usr/local/sbin/pare-feu-retour]
       - name: Poser la nouvelle configuration                  # template, validate: nft -c -f %s
       - name: Charger la nouvelle configuration                # nft -f /etc/nftables.conf
       - name: Fermer la connexion existante
         ansible.builtin.meta: reset_connection
       - name: Confirmer par une nouvelle connexion SSH
         ansible.builtin.wait_for_connection:
           timeout: "{{ pare_feu_delai_confirmation }}"
       - name: Confirmer les flux de contrôle depuis le contrôleur   # wait_for, delegate_to: localhost, become: false
       - name: Désarmer le retour automatique (changement confirmé)  # systemd_service: pare-feu-retour.timer stopped
     rescue:
       - name: Revenir en arrière tout de suite si gw01 répond encore   # ignore_unreachable, failed_when: false
       - name: Désarmer la minuterie si le retour immédiat a eu lieu
       - name: Attendre que gw01 soit de nouveau joignable (retour immédiat ou minuterie)  # wait_for_connection, délai + 60 s
       - name: Vérifier que la configuration précédente est en place      # cmp
       - name: Échouer en expliquant
   ```
   Le script [`pare-feu-retour`](fichiers/M04-E17/ansible/roles/pare_feu/files/pare-feu-retour) recopie la sauvegarde **dans** `/etc/nftables.conf`, puis la charge, puis écrit dans le journal (`logger -t pare-feu-retour`) : restaurer seulement les règles chargées laisserait le fichier fautif en place pour le prochain démarrage.
3. **Équivalence.** Premier passage :
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/gw01-pare-feu.yml --check --diff
   TASK [pare_feu : Prévoir la nouvelle configuration] *******************************
   --- before: /etc/nftables.conf
   +++ after: …/nftables.conf.j2
   @@ … @@
   -define WAN       = "ens18"
   +define WAN = "ens18"
   …
   -		iifname $WAN ip saddr $PVE01 oifname $LAB_IFS tcp dport 22 accept comment "pve01 vers les VMs (vérifications avant E15)"
   +		iifname $WAN oifname $LAB_IFS ip saddr $PVE01 tcp dport 22 accept comment "pve01 vers les VMs (vérifications avant M00-E15) (M00-E10)"
   ```
   Le diff est cosmétique (espaces, ordre des critères, références ajoutées aux commentaires) : à vérifier ligne à ligne, mais c'est l'**équivalence des règles chargées** qui prouve que rien ne change :
   ```
   admin@gw01:~$ sudo nft -j list ruleset > avant.json        # avant le passage, puis apres.json après
   admin@adm01:~$ scp gw01:avant.json gw01:apres.json ~/m04/e17/
   admin@adm01:~$ cd ~/m04/e17 && for f in avant apres; do
   >   jq -S '[.nftables[] | select(.rule) | .rule | {table, chain, expr: (.expr | map(tostring) | sort)}] | sort' $f.json > $f.norm
   > done && diff avant.norm apres.norm && echo "RÈGLES IDENTIQUES"
   RÈGLES IDENTIQUES
   ```
   (Le filtre ignore les poignées, les commentaires et l'ordre des critères dans une règle ; il ignore aussi l'**ordre des règles** dans une chaîne : sans conséquence ici, toutes les règles de flux sont des `accept` sans chevauchement avec un `drop` avant la fin de chaîne.) Fait sur la référence M00-E26 complétée par E31, M01-E28, M03-E05 et E15 : identique.
4. **Essai de coupure** (flux « SSH depuis MGMT et le VPN » retiré, délai 120 s) :
   ```
   TASK [pare_feu : Charger la nouvelle configuration] *********************************
   changed: [gw01]
   TASK [pare_feu : Fermer la connexion existante] **************************************
   TASK [pare_feu : Confirmer par une nouvelle connexion SSH] ***************************
   fatal: [gw01]: FAILED! => changed=false
     elapsed: 37
     msg: 'timed out waiting for ping module test: Data could not be sent to remote host "10.10.10.1"…'
   TASK [pare_feu : Revenir en arrière tout de suite si gw01 répond encore] *************
   fatal: [gw01]: UNREACHABLE! => …
   TASK [pare_feu : Désarmer la minuterie si le retour immédiat a eu lieu] **************
   fatal: [gw01]: UNREACHABLE! => …
   TASK [pare_feu : Attendre que gw01 soit de nouveau joignable (retour immédiat ou minuterie)] ***
   ok: [gw01]
   TASK [pare_feu : Vérifier que la configuration précédente est en place] **************
   ok: [gw01]
   TASK [pare_feu : Échouer en expliquant] **********************************************
   fatal: [gw01]: FAILED! => …
     msg: La nouvelle configuration nftables n'a pas été confirmée (tâche « Confirmer par une nouvelle connexion SSH »).
       gw01 est revenu à la configuration précédente. …
   PLAY RECAP ****************************************************************************
   gw01 : ok=18 changed=5 unreachable=0 failed=1 skipped=0 rescued=1 ignored=2
   admin@gw01:~$ sudo journalctl -t pare-feu-retour
   oct. 07 17:09:29 gw01 pare-feu-retour[3205]: configuration nftables précédente restaurée et chargée (changement non confirmé)
   ```
   (Sortie de l'essai sur conteneur, délai de 60 s, adaptée.) La session SSH ouverte avant le passage a survécu (connexion établie, `ct state established`) : elle ne prouvait rien, d'où la confirmation par une **nouvelle** connexion. Pendant le délai, tout le transit restait ouvert (seule la chaîne `input` avait changé) ; un essai qui casse `forward` couperait le lab pendant ce délai : c'est le prix du filet, et la raison de le garder court.
5. **Documentation** : la matrice de `docs/socle/matrice-flux.md` garde la vue par service et renvoie, pour le détail, à `host_vars/gw01/pare_feu.yml` (lien vers le fichier sur `main`). Une règle ajoutée à la main par `nft add rule` disparaît au prochain passage du rôle (`flush ruleset`) ; entre-temps, elle n'est visible nulle part : la détection de dérive (E29) compare le fichier, pas les règles chargées — à ajouter (`nft -j list ruleset` normalisé, comme à l'étape 3).

**Explications**

Le filet « homme mort » (*dead man's switch*) renverse la charge de la preuve : le changement n'est pas gardé **parce qu'il n'a pas échoué**, il est gardé **parce que quelqu'un a confirmé** qu'il fonctionne. C'est le même principe que la confirmation de résolution d'écran d'un système d'exploitation ou que `commit confirmed` des routeurs Juniper. La minuterie est armée **sur `gw01`**, indépendamment d'Ansible : si le contrôleur plante, si le réseau se coupe, si quelqu'un interrompt le playbook, `gw01` revient seul en arrière.
`systemd-run --on-active=` crée deux unités transitoires (`pare-feu-retour.timer` et `.service`) qui disparaissent au redémarrage ; `--collect` décharge le service même s'il a échoué, pour qu'un passage suivant puisse réutiliser le nom.

**Alternatives**
- `at now + 2 minutes` : même principe, dépend du paquet `at` et de `atd`.
- Une boucle `sleep 120; restaurer` lancée en arrière-plan par Ansible (`async`, `poll: 0`) : fragile (le processus dépend de la session).
- Matrice en ensembles nommés (`set`) nftables générés depuis les données, règles fixes dans le template : plus compact pour de nombreux flux identiques.
- Pare-feu sur chaque hôte (nftables local, rôle commun) en plus de `gw01` : défense en profondeur, mais deux matrices à tenir.

**Pièges classiques**
- Confirmer avec la connexion existante (ControlPersist) : elle survit au changement, la confirmation est fausse.
- Restaurer les règles chargées mais pas le fichier : la configuration fautive revient au redémarrage.
- Délai de confirmation plus long que le délai de retour : la minuterie restaure **pendant** que le playbook confirme, et le playbook désarme une minuterie déjà passée… en laissant croire que tout va bien.
- `flush ruleset` dans le fichier + un autre outil qui crée ses propres tables (fail2ban, Docker) : chaque rechargement efface leurs règles (voir E21).
- Commentaires avec guillemets, ou de plus de 128 octets : `nft` refuse le fichier (attrapé par la validation, mais message peu clair).

**En production chez MédiSphère**
Deux routeurs en haute disponibilité (module 07), jamais modifiés en même temps (`serial: 1`) ; toute ouverture de flux par MR avec la RSSI en relecture ; matrice des flux générée depuis les données et publiée dans la documentation ; dérive des règles **chargées** surveillée ; journalisation des rejets vers le SIEM.

---

### M04-E18 — Collections : utiliser et créer `medisphere.socle`

**Solution**

Fichiers : [`fichiers/M04-E18/ansible/`](fichiers/M04-E18/ansible/) — [`collections/requirements.yml`](fichiers/M04-E18/ansible/collections/requirements.yml), la collection [`collections/ansible_collections/medisphere/socle/`](fichiers/M04-E18/ansible/collections/ansible_collections/medisphere/socle/) (`galaxy.yml`, `meta/runtime.yml`, `README.md`, `CHANGELOG.md`, `LICENCE`, [`plugins/filter/nft.py`](fichiers/M04-E18/ansible/collections/ansible_collections/medisphere/socle/plugins/filter/nft.py) et sa documentation [`regle_nft.yml`](fichiers/M04-E18/ansible/collections/ansible_collections/medisphere/socle/plugins/filter/regle_nft.yml), [`tests/unit/plugins/filter/test_nft.py`](fichiers/M04-E18/ansible/collections/ansible_collections/medisphere/socle/tests/unit/plugins/filter/test_nft.py), rôle [`roles/ca_lab/`](fichiers/M04-E18/ansible/collections/ansible_collections/medisphere/socle/roles/ca_lab/)), le template de `pare_feu` réécrit [`roles/pare_feu/templates/nftables.conf.j2`](fichiers/M04-E18/ansible/roles/pare_feu/templates/nftables.conf.j2), [`roles/gitlab_runner/tasks/ca.yml`](fichiers/M04-E18/ansible/roles/gitlab_runner/tasks/ca.yml).

1. **Collections externes.**
   ```
   admin@adm01:~/src/ansible$ uv run ansible-galaxy collection list
   # /home/admin/src/ansible/collections/ansible_collections
   Collection                               Version
   ---------------------------------------- -------
   ansible.posix                            2.2.2
   community.general                        13.5.0
   community.library_inventory_filtering_v1 1.1.5
   community.proxmox                        2.1.0
   medisphere.socle                         1.0.0
   # /home/admin/src/ansible/.venv/lib/python3.13/site-packages/ansible/_internal/ansible_collections
   …
   ```
   `community.library_inventory_filtering_v1` est une **dépendance** de `community.general`, installée avec elle. `collections_path = collections` (M04-E02) : Ansible ne cherche que là (plus les collections internes d'ansible-core) ; une collection dans `~/.ansible/collections` n'est **pas** vue par le projet, ce qui est voulu (adm01, runner01 et sem01 exécutent le même code). Sans ce réglage, la première trouvée dans l'ordre de `COLLECTIONS_PATHS` gagnerait.
   `ansible-galaxy collection verify -r collections/requirements.yml` télécharge le manifeste de chaque collection depuis Galaxy et compare les empreintes de **chaque fichier installé** avec celles publiées : il détecte une collection modifiée localement (ou installée depuis une autre source). Ce n'est pas une signature d'éditeur (Galaxy accepte des signatures GPG de collections, peu de collections communautaires en publient) : la confiance repose sur Galaxy et HTTPS.
2. **Squelette** : `uv run ansible-galaxy collection init medisphere.socle --init-path collections/ansible_collections` crée `docs/`, `meta/`, `plugins/`, `roles/`, `galaxy.yml`, `README.md`. `galaxy.yml` : `namespace`, `name`, `version: 1.0.0`, `readme`, `authors`, `description`, une licence (ici `license_file: LICENCE` : code interne, pas de licence SPDX ; ansible-lint en profil `production` exige l'une ou l'autre), `tags`, `repository`, `build_ignore`. `meta/runtime.yml` : `requires_ansible: ">=2.19.0"`. ansible-lint demande aussi un `CHANGELOG.md` (règle `galaxy[no-changelog]`). `.gitignore` (lignes déjà présentes depuis M04-E02, à vérifier) :
   ```
   /collections/ansible_collections/*
   !/collections/ansible_collections/medisphere/
   ```
3. **Le filtre** : [`nft.py`](fichiers/M04-E18/ansible/collections/ansible_collections/medisphere/socle/plugins/filter/nft.py), une fonction `regle_nft(flux)` et la classe `FilterModule`. En plus de la macro : refus des champs inconnus (`destinaton` → « champ(s) inconnu(s) ['destinaton'] (faute de frappe ?) »), d'un motif absent, d'un guillemet, d'un commentaire de plus de 128 **octets** (UTF-8 : `é` en compte deux, ce qu'aucune vérification Jinja par `length` ne voit), de ports sans protocole ou avec ICMP, d'une action inconnue, d'une liste vide. Documentation : [`regle_nft.yml`](fichiers/M04-E18/ansible/collections/ansible_collections/medisphere/socle/plugins/filter/regle_nft.yml) (clés `DOCUMENTATION`, `EXAMPLES`, `RETURN`).
   ```
   admin@adm01:~/src/ansible$ uv run ansible-doc -t filter medisphere.socle.regle_nft
   > FILTER medisphere.socle.regle_nft (…/plugins/filter/regle_nft.yml)
     Prend un dictionnaire décrivant un flux autorisé et rend une ligne de règle nftables.
   …
   admin@adm01:~/src/ansible$ PYTHONPATH=collections uv run --with pytest pytest -q collections/ansible_collections/medisphere/socle/tests/unit
   ...............                                                          [100%]
   15 passed in 0.17s
   ```
   `PYTHONPATH=collections` : le dossier qui **contient** `ansible_collections/` doit être dans le chemin de Python pour que `from ansible_collections.medisphere.socle.plugins.filter.nft import regle_nft` fonctionne. `uv run --with pytest` ajoute pytest à un environnement temporaire, sans toucher au verrou du projet ; si l'équipe garde ces tests, ajoute `pytest` au groupe `dev` de `pyproject.toml`.
4. **Le template** : `{{ f | medisphere.socle.regle_nft }}` remplace l'appel de la macro, et la macro disparaît.
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/gw01-pare-feu.yml --check --diff
   TASK [pare_feu : Prévoir la nouvelle configuration] ****************************
   ok: [gw01]
   …
   gw01 : ok=8 changed=0 unreachable=0 failed=0 skipped=1 rescued=0 ignored=0
   ```
   Même fichier au caractère près : le filtre est un remaniement (*refactoring*) sans effet, prouvé par le `--check`.
5. **Rôle partagé** `medisphere.socle.ca_lab` : liste `ca_lab_certificats` (`nom`, `source` sur le contrôleur), contrat dans `meta/argument_specs.yml`, `update-ca-certificates` immédiat (la suite du play peut en avoir besoin). Dans `gitlab_runner` :
   ```yaml
   - name: Autorités de certification du lab
     ansible.builtin.include_role:
       name: medisphere.socle.ca_lab
     vars:
       ca_lab_certificats:
         - {nom: medisphere-provisoire, source: "{{ gitlab_runner_ca_provisoire }}"}
         - {nom: pve01-root-ca, source: "{{ gitlab_runner_ca_pve01 }}"}
   ```
   `ansible-doc -t role medisphere.socle.ca_lab` affiche son contrat.
6. `ansible-galaxy collection build` produit `medisphere-socle-1.0.0.tar.gz` (fichiers, plus `MANIFEST.json` et `FILES.json` avec les empreintes de chaque fichier ; `tests/` exclu par `build_ignore`). Pour une autre équipe : soit `requirements.yml` pointant le dépôt Git (`name: git+https://git01…/plateforme/ansible.git#/collections/ansible_collections/medisphere/socle,v1.2.0`), soit un registre (Galaxy NG / Automation Hub privé, ou un registre de paquets générique de GitLab) ; dans les deux cas, version figée.

**Explications**

Une collection est un **espace de noms** (`medisphere.socle.*`) qui regroupe modules, plugins (filtres, tests, inventaires, callbacks…), rôles et playbooks, avec une version. Ansible trouve un plugin par son nom complet en cherchant `ansible_collections/<espace>/<nom>/` dans les chemins configurés. Mettre la logique dans un filtre Python plutôt que dans Jinja, c'est la rendre **testable** (pytest, cas d'erreur compris), **lisible** en revue et **réutilisable** (la même fonction peut générer la documentation de la matrice). Jinja reste pour la mise en forme.

**Alternatives**
- Un dépôt Git séparé pour la collection, publié et versionné à part : indispensable quand plusieurs projets la consomment ; prématuré ici (un seul consommateur).
- Un plugin de filtre « local » (`filter_plugins/` à côté des playbooks) : plus simple, pas d'espace de noms, pas de version, invisible pour `ansible-doc` sans configuration.
- Garder la macro, avec des tests de rendu (Molecule ou un playbook de test qui compare le fichier rendu à une référence) : possible, mais les erreurs restent tardives et peu claires.

**Pièges classiques**
- Une collection externe versionnée par erreur dans le dépôt (`git add collections/`) : des milliers de fichiers, et une version qui ne suit plus `requirements.yml`.
- `requirements.yml` avec des plages (`>=2.0.0`) : la CI et les postes n'ont plus la même version.
- Oublier `meta/runtime.yml` : avertissement à chaque exécution, et `ansible-galaxy` ne sait pas quelles versions d'ansible-core sont supportées.
- Un plugin qui importe un module Python absent de l'environnement du contrôleur : l'erreur n'apparaît qu'à l'exécution du template.
- Renommer un champ de flux dans le filtre sans changer la version majeure de la collection : les autres consommateurs cassent sans prévenir.

**En production chez MédiSphère**
Collection interne dans son propre dépôt dès qu'un second projet la consomme, publiée par la CI à chaque étiquette (semantic-release, comme M01), testée (`ansible-test sanity` et `units`) ; collections externes **mirrorées** dans un registre interne (pas de dépendance directe à Galaxy pour déployer), versions mises à jour par MR automatique (Renovate, module 13).

---

### M04-E19 — Exploitation quotidienne : tags, limit, check, diff

**Solution**

Fichiers : [`fichiers/M04-E19/ansible/playbooks/site.yml`](fichiers/M04-E19/ansible/playbooks/site.yml), [`fichiers/M04-E19/ansible/docs/exploitation.md`](fichiers/M04-E19/ansible/docs/exploitation.md).

1. **`site.yml`** : `socle-base.yml`, puis `gw01-pare-feu.yml`, puis `runner01.yml` (`ansible.builtin.import_playbook`, un `name:` par import). La configuration commune d'abord (comptes, SSH, temps : ce dont tout le reste dépend, y compris la capacité de se reconnecter) ; le pare-feu ensuite, seul sur `gw01`, sur une machine déjà conforme ; les services enfin. Au mini-projet s'ajouteront `dns01` et `git01`.
2. **Sans rien exécuter** :
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/site.yml --list-hosts --tags pare_feu
   playbook: playbooks/site.yml
     play #1 (socle): Configuration commune du socle	TAGS: []
       pattern: ['socle']
       hosts (5): …
     play #2 (role_routeur): Pare-feu du routeur	TAGS: []
       pattern: ['role_routeur']
       hosts (1):
         gw01
     …
   ```
   `--list-hosts` liste les hôtes **de chaque play**, que des tâches y correspondent aux étiquettes ou non : le play 1 apparaît avec ses cinq hôtes. Pour voir ce qui **s'exécuterait** :
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/site.yml --list-tasks --tags pare_feu
     play #1 (socle): Configuration commune du socle	TAGS: []
       tasks:
         Vérifier le système de l'hôte	TAGS: [always]
         Vérifier l'adresse de connexion (l'inventaire ne doit pas dépendre du DNS)	TAGS: [always]
         base : Validating arguments against arg spec 'main' - Configuration commune des VMs du socle MédiSphère	TAGS: [always, base]
     play #2 (role_routeur): Pare-feu du routeur	TAGS: []
       tasks:
         pare_feu : Vérifier la matrice des flux	TAGS: [pare_feu]
         …
   ```
   Les `pre_tasks` (`always`) et la validation des arguments du rôle `base` (Ansible l'étiquette `always` d'office) s'exécutent quand même sur les cinq hôtes : c'est voulu, elles ne modifient rien.
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/site.yml --list-tasks --tags base_temps --limit dns01
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/site.yml --list-tags
     play #1 (socle): Configuration commune du socle	TAGS: []
         TASK TAGS: [always, base, base_identite, base_journal, base_maj, base_paquets, base_temps, base_utilisateurs, ssh]
     play #2 (role_routeur): Pare-feu du routeur	TAGS: []
         TASK TAGS: [pare_feu]
     play #3 (role_runner): Runner de CI du socle	TAGS: []
         TASK TAGS: [runner, runner_ca, runner_outils, runner_preconditions, runner_service, runner_verifier]
   admin@adm01:~/src/ansible$ uv run ansible socle:\!gw01 --list-hosts         # 4 hôtes
   admin@adm01:~/src/ansible$ uv run ansible 'role_*' --list-hosts             # les 5, par leurs groupes de rôle
   ```
   Motifs : `a:b` union, `a:&b` intersection, `a:!b` exclusion, jokers (`role_*`), expressions régulières (`~role_(dns|gitlab)`). Dans un shell interactif, `!` se protège (`\!` ou guillemets simples).
3. Après modification de `/etc/motd` sur `dns01` :
   ```
   TASK [base : Message d'accueil] **************************************************
   --- before: /etc/motd
   +++ after: …/motd.j2
   @@ -6,3 +6,2 @@
   -  Coucou
   changed: [dns01]
   ```
   Corrigé par un passage normal (`--limit dns01 --tags base_identite`). C'est le principe de la détection de dérive (E29).
4. **Expériences.**
   - `--skip-tags always` : la collecte des faits (tâche implicite étiquetée `always`) est sautée ; les rôles échouent alors sur la première variable qui dépend d'un fait (`ansible_facts['default_ipv4']` indéfini), et les `pre_tasks` (étiquetées `always`) ne s'exécutent pas. À ne pas utiliser pour « sauter les vérifications ».
   - En `--check`, les tâches `command`/`shell` sont **sautées**, sauf celles qui portent `check_mode: false` ; on ne met `check_mode: false` qu'à une commande qui **lit** : `chronyc -n waitsync` (E10 ; en E15 elle est en plus conditionnée par `not ansible_check_mode`, rien n'ayant été posé), `nft -c -f -` (E17), `apt-cache policy`, `uv tool list`, `id -nG gitlab-runner` (E16). Sont sautées à dessein : les commandes qui modifient (`update-ca-certificates`, `gitlab-runner register`, `systemd-run`) et tout ce que conditionne `not ansible_check_mode` (application du pare-feu, contrôle de `sshd -T` en E11 : rien n'a été rechargé, le contrôle porterait sur l'ancienne configuration).
5. **Aide-mémoire** : voir le fichier ; il tient en une page.

**Explications**

Les étiquettes servent à **réduire** un passage connu, pas à structurer le code : une étiquette par rôle (posée dans le playbook) et une par thème (posée sur les `import_tasks` du rôle) suffisent. Une stratégie d'étiquettes qui grossit (une par tâche) devient illisible et donne des passages partiels dont on ignore l'état final. `--limit` réduit les hôtes, `--tags` les tâches : les deux combinés donnent le plus petit changement possible, celui qu'on applique d'abord.
`--check` n'est pas une garantie : c'est une **prédiction** faite par chaque module (ceux qui ne savent pas prédire sont sautés). `--diff` n'affiche que ce que les modules savent montrer (fichiers, lignes, comptes, pas les commandes).

**Alternatives**
- Un playbook par hôte (`gw01.yml`, `dns01.yml`…) plutôt que par fonction : simple, mais une politique commune se retrouve répétée.
- `--start-at-task` pour reprendre un passage interrompu : à éviter (les `register` des tâches sautées n'existent pas) ; un rôle idempotent se relance entièrement.

**Pièges classiques**
- `--tags` sur un rôle importé dynamiquement (`include_role`) : l'étiquette ne descend pas dans les tâches (il faut `apply: tags:`) ; avec `roles:` ou `import_role`, elle descend.
- `--limit` oublié sur un `--tags ssh` « juste pour tester » : tout le socle.
- Confondre `--list-hosts` (hôtes des plays) et « hôtes qui seront changés ».
- `--check` vert sur un rôle jamais appliqué : les tâches qui dépendent d'un paquet pas encore installé ont été sautées ou ont échoué silencieusement selon les modules.

**En production chez MédiSphère**
L'astreinte n'a qu'un point d'entrée (`site.yml`, par la CI ou Semaphore au palier 3) et l'aide-mémoire ; les passages manuels depuis un poste restent possibles pour l'équipe Plateforme, tracés dans le journal des changements (E23).

---

### M04-E20 — ansible-lint en pre-commit et en CI

**Solution**

Fichiers : [`fichiers/M04-E20/ansible/.ansible-lint`](fichiers/M04-E20/ansible/.ansible-lint), [`.pre-commit-config.yaml.extrait`](fichiers/M04-E20/ansible/.pre-commit-config.yaml.extrait), [`.gitlab-ci.yml`](fichiers/M04-E20/ansible/.gitlab-ci.yml).

1. **Premier passage** sur un projet typique de fin de palier (exemples rencontrés en écrivant ce corrigé, et leur traitement) :

   | Règle | Exemple | Traitement |
   |---|---|---|
   | `name[template]` | `- name: "Clé {{ _cle.nom }} : télécharger"` | Jinja seulement en **fin** de nom : « Télécharger la clé candidate {{ _cle.nom }} » |
   | `name[casing]` | `- name: config.toml lisible…` | commencer par une majuscule (« Rendre config.toml… ») |
   | `var-naming[no-role-prefix]` | `register: _runner_config` dans `gitlab_runner` | préfixe du rôle : `_gitlab_runner_config` |
   | `command-instead-of-module` | `command: systemctl stop pare-feu-retour.timer` | `ansible.builtin.systemd_service` ; pour `reset-failed` (pas de module) : `# noqa: command-instead-of-module` et la raison |
   | `ignore-errors` | `ignore_errors: true` dans un `rescue` | `failed_when: false` (on assume explicitement de ne jamais échouer) |
   | `no-handler` | `when: _conf is changed` | handler… sauf quand l'action doit précéder une vérification dans le même bloc (E15) : `# noqa: no-handler` justifié |
   | `galaxy[no-changelog]`, `schema[galaxy]` | collection sans `CHANGELOG.md`, licence non SPDX | ajouter `CHANGELOG.md`, `license_file: LICENCE` |
   | `yaml[line-length]` | une expression Jinja de 170 caractères | la couper (`>-`) |

2. [`.ansible-lint`](fichiers/M04-E20/ansible/.ansible-lint) : `profile: production`, `exclude_paths` (`.venv/`, `.cache/`, collections `community/` et `ansible/`, `**/*.exemple`, `**/*.extrait`), `offline: true` (le job installe les collections lui-même ; ansible-lint n'a rien à télécharger), `skip_list: []` et la règle écrite en commentaire : une exception se fait **sur la ligne**, avec la raison.
3. **Hook local** :
   ```yaml
   - repo: local
     hooks:
       - id: ansible-lint
         name: ansible-lint (profil production)
         language: system
         entry: uv run --frozen ansible-lint
         pass_filenames: false
         files: \.(ya?ml|j2)$|^\.ansible-lint$
   ```
   Le hook publié par le projet (`repo: https://github.com/ansible/ansible-lint`) installe **son** environnement, avec sa propre version d'ansible-core : on ne lint plus avec la version qui exécute. Le hook local utilise celle du verrou `uv.lock`, comme la CI. `pass_filenames: false` : ansible-lint a besoin du contexte (un rôle, ses variables, ses handlers), pas d'une liste de fichiers modifiés. Essai :
   ```
   admin@adm01:~/src/ansible$ git commit -am "test: mode sans zéro"
   ansible-lint (profil production)........................................Failed
   - hook id: ansible-lint
   - exit code: 2
   risky-octal: Octal file permissions must contain leading zero or be a string.
   roles/base/tasks/journal.yml:3 Task/Handler: Dossier des réglages de journald
   ```
4. **Job de CI** (extrait) :
   ```yaml
   pre-commit:
     variables:
       SKIP: gitleaks,ansible-lint

   ansible-lint:
     stage: lint
     tags: [shell]
     variables:
       ANSIBLE_INVENTORY: inventories/lab/hosts.yml
     script:
       - export ANSIBLE_VAULT_IDENTITY_LIST="lab@$(mktemp)" && printf 'factice\n' > "${ANSIBLE_VAULT_IDENTITY_LIST#lab@}"
       - uv sync --frozen
       - uv run ansible-galaxy collection install -r collections/requirements.yml -p collections
       - uv run ansible-lint
   ```
   - Le job `pre-commit` du gabarit est **redéfini partiellement** : GitLab fusionne la définition locale avec celle du gabarit inclus ; seule `variables` change.
   - ansible-lint lance `ansible-playbook --syntax-check`, qui lit `ansible.cfg` : inventaire **dynamique** (pas d'accès à Proxmox depuis ce job, et `unparsed_is_failed` fait échouer) et identité Vault (fichier absent sur `runner01` : « The vault password file … was not found », **toute** commande échoue, même sans déchiffrer). On remplace l'inventaire par le statique (`ANSIBLE_INVENTORY`) et l'identité par un mot de passe **factice** : le lint ne déchiffre rien, il ne remarque pas qu'il est faux. Une variable **vide** ne marche pas (`ANSIBLE_VAULT_IDENTITY_LIST=""` est lue comme un chemin vide : « … can not be a directory ») — testé.
   - Aucune variable secrète dans ce job : un job de lint n'a pas à recevoir le mot de passe du Vault (E27 le donnera aux seuls jobs qui en ont besoin, sur des branches protégées).
5. MR fautive : job `ansible-lint` rouge, « Merge blocked: pipeline must succeed » (règle de M01-E24).

**Explications**

ansible-lint combine des règles de **style** (noms, YAML), d'**idiome** (FQCN, `command` à la place d'un module, `no-handler`), de **sûreté** (`risky-file-permissions`, `risky-octal`, `no-changed-when`, `ignore-errors`) et une vérification de syntaxe par ansible-core lui-même. Les profils (`min` → `basic` → `moderate` → `safety` → `shared` → `production`) empilent les règles ; `production` ajoute ce qu'exige un contenu publié (métadonnées, préfixes de variables, collection). Il ne remplace ni la revue (il ne voit pas qu'une clé est récupérée sans TLS, E21) ni les tests (Molecule, E24).

**Alternatives**
- Hook publié par ansible-lint, avec `additional_dependencies` pour figer ansible-core : plus « standard », deux environnements à tenir alignés.
- Lancer ansible-lint seulement en CI : retour plus lent (minutes au lieu de secondes), mais un environnement de moins sur les postes.
- `yamllint` séparé : ansible-lint l'appelle déjà s'il est installé (règles `yaml[…]`), avec sa configuration `.yamllint`.

**Pièges classiques**
- Lint en CI avec une version d'ansible-lint différente de celle des postes : des écarts « ça passe chez moi ».
- `skip_list` qui grossit à chaque MR : au bout de six mois, le lint ne vérifie plus rien.
- Job de lint avec le mot de passe du Vault « parce que sinon ça plante » : une MR depuis une branche non protégée peut alors l'exfiltrer.
- `offline: false` en CI sans accès à Galaxy : ansible-lint tente d'installer les collections et échoue de façon confuse.

**En production chez MédiSphère**
Le profil `production` est la porte d'entrée de `main` ; le rapport *Code Quality* (format `codeclimate`) s'affiche dans la MR ; la montée de version d'ansible-lint est une MR comme une autre (nouvelles règles = corrections dans la même MR).

---

### M04-E21 — Revue des rôles du stagiaire

**Lecture du code, sur notre socle**

Avec `ansible.cfg` du projet (`inject_facts_as_vars = False`) et ansible-core 2.21 : la **première** tâche (`when: ansible_distribution == "Debian"`) échoue sur les cinq hôtes (« 'ansible_distribution' is undefined ») ; rien d'autre ne s'exécute. Corrigée cette ligne, la tâche `when: fail2ban_jails` échoue à son tour (une liste n'est pas un booléen, M04-E14). Corrigées les deux : fail2ban s'installe, `jail.local` impose `backend = auto` à `sshd` ; Debian 13 n'a pas de `/var/log/auth.log` (pas de rsyslog) : la prison `sshd` ne trouve pas son journal, fail2ban **refuse de démarrer**, le handler de redémarrage échoue. Côté comptes : `password_hash` échoue sur `adm01` (Python 3.13, plus de module `crypt`, pas de `passlib`) ; sans cela, le *lookup* `file` cherche `/tmp/<compte>.keys` **sur `adm01`**, où `get_url` ne l'a pas écrit (il est sur la cible) : échec.
Sur sa VM, tout était vert parce que : Ansible 2.14 (pas de *data tagging*, faits injectés), Python 3.11 (`crypt` présent), rsyslog installé, et contrôleur = cible (le fichier téléchargé était « local »). Rien de cela n'est vrai chez nous.
Si tout finissait par passer : au **deuxième** passage, `fail2ban-client reload` (toujours `changed`), le mot de passe (nouveau sel à chaque fois) et `useradd` (erreur ignorée) changent encore : rôle non idempotent. Sur `gw01`, fail2ban crée sa table nftables… que le rôle `pare_feu` efface à chaque rechargement (`flush ruleset`). Sur `adm01`, `hosts: all` applique les deux rôles au poste d'administration lui-même.

ansible-lint (profil `production`, lancé dans le projet pour qu'il trouve `ansible.posix`) trouve : modules sans nom complet (`fqcn`), forme `clé=valeur` (`no-free-form`), `state=latest` (`package-latest`), `{{ }}` dans `when` (`no-jinja-when`), `command` sans `changed_when` (`no-changed-when`), `ignore_errors` (`ignore-errors`), `shell` pour `useradd` (`command-instead-of-shell`), modes absents (`risky-file-permissions`), `mode: 644` (`risky-octal`), variables sans le préfixe du rôle (`var-naming[no-role-prefix]` : `equipe`, `mot_de_passe`, `gitlab_url`), `yes` au lieu de `true` (`yaml[truthy]`), noms en minuscules (`name[casing]`), play sans nom (`name[play]`). Lancé hors du projet, il s'arrête sur `syntax-check[unknown-module]` (`authorized_key` vient de `ansible.posix`, absente) et en voit beaucoup moins. Il ne voit **pas** : le mot de passe en clair, `validate_certs: no` en tant que risque, le *lookup* exécuté au mauvais endroit, `ignoreip`, la combinaison avec Debian 13, `vars/` qui bloque l'inventaire, l'absence de `validate` sur sudoers, l'absence de révocation.

**Revue**

Numéros de ligne : `cat -n` des fichiers de `ressources/M04-E21/`.

| N° | Fichier : ligne(s) | Défaut | Catégorie | Gravité | Impact concret | Correction |
|---|---|---|---|---|---|---|
| 1 | `comptes_equipe/defaults/main.yml` : 7-8 | Mot de passe commun en clair, versionné, connu de toute l'équipe | Sécurité | **Critique** | Le dépôt donne un mot de passe valide sur toutes les VMs, pour tous les comptes ; impossible de savoir qui s'est connecté | Pas de mot de passe (clés seulement) ; si besoin, empreinte par personne en Vault (E12) |
| 2 | `comptes_equipe/tasks/main.yml` : 16-21 | Clés téléchargées depuis GitLab avec `validate_certs: no` | Sécurité | **Critique** | Une interception (ARP, DNS) suffit à faire installer **sa** clé sur tous les serveurs, avec sudo sans mot de passe | Clés publiques **dans le dépôt**, relues en MR (E14) ; TLS toujours vérifié |
| 3 | `comptes_equipe/tasks/main.yml` : 16-27 | Les profils GitLab deviennent la source des accès root | Sécurité | **Critique** | Quiconque ajoute une clé à un compte GitLab (ou compromet ce compte) obtient root sur le socle au passage suivant | Source des accès = données relues (inventaire), puis certificats SSH (M06) |
| 4 | `fail2ban/templates/jail.local.j2` : 3 | `ignoreip` limité à `127.0.0.1/8` | Fonctionnement | **Critique** | Trois échecs depuis `adm01` (agent avec plusieurs clés et `MaxAuthTries 3`, clé de CI erronée) bannissent le poste d'administration de **tout** le socle en même temps : Ansible, astreinte, CI coupés | `ignoreip` : MGMT, VPN, `runner01` (et `sem01` plus tard) |
| 5 | `comptes_equipe/tasks/main.yml` : 23-27 | `authorized_key` sans `exclusive`, aucun retrait de compte | Sécurité | **Élevée** | Une clé retirée de GitLab, un départ de l'équipe : l'accès reste sur les serveurs, pour toujours | Liste exclusive, `etat: absent` pour les départs (E14) |
| 6 | `comptes_equipe/tasks/main.yml` : 35-38 | `lineinfile` sur `/etc/sudoers` sans `validate: visudo -cf %s` | Sécurité / fonctionnement | **Élevée** | Une faute de syntaxe un jour = plus aucun `sudo` sur l'hôte, `become` d'Ansible compris ; en double avec `sudoers.d/` | Un fichier dans `/etc/sudoers.d/`, `validate: visudo -cf %s`, mode `"0440"` |
| 7 | `comptes_equipe/files/sudoers-equipe` ; `defaults/main.yml` : 2-6 | `NOPASSWD: ALL` pour toute l'équipe, stagiaire compris | Sécurité | **Élevée** | Toute compromission d'une session = root sans obstacle ; principe du moindre privilège ignoré | sudo **avec** mot de passe (ou certificats courts), droits par rôle ; pas de root pour un stagiaire |
| 8 | `fail2ban/tasks/main.yml` : 4 | `ansible_distribution` (faits injectés) | Fonctionnement | **Élevée** | Indéfini avec notre `ansible.cfg` : le playbook échoue sur tout le socle dès la première tâche | `ansible_facts['distribution']`, ou rien (le socle est tout Debian) |
| 9 | `fail2ban/tasks/main.yml` : 15 | `when: fail2ban_jails` (une liste) | Fonctionnement | **Élevée** | Erreur avec ansible-core ≥ 2.19 | `when: fail2ban_jails \| length > 0` |
| 10 | `fail2ban/templates/jail.local.j2` : 9-11 | `backend = auto` impose la lecture de fichiers journaux | Fonctionnement | **Élevée** | Debian 13 sans rsyslog : prison `sshd` sans journal, fail2ban ne démarre pas | Ne pas surcharger : Debian fournit `backend = systemd` (`jail.d/defaults-debian.conf`) |
| 11 | `fail2ban/templates/jail.local.j2` : 6 | `banaction = iptables-multiport` | Fonctionnement / sécurité | **Élevée** | `iptables` absent de nos VMs : les bannissements échouent, la protection est illusoire | Garder `banaction = nftables` de Debian |
| 12 | `comptes_equipe/tasks/main.yml` : 23-27 | *Lookup* `file` sur un fichier écrit par `get_url` sur la **cible** | Fonctionnement | **Élevée** | Le *lookup* s'exécute sur `adm01` : fichier absent, échec (ou pire : un vieux fichier homonyme de `adm01` installé partout) | Clés dans les données (n° 2) ; sinon `slurp` sur la cible |
| 13 | `comptes_equipe/tasks/main.yml` : 13 | `password_hash('sha512')` sans sel fixe | Idempotence / fonctionnement | Moyenne | Nouveau sel à chaque passage : `changed` permanent, dérive impossible à détecter ; erreur sur Python 3.13 sans `passlib` | Empreinte calculée une fois, stockée en Vault (E12) |
| 14 | `comptes_equipe/tasks/main.yml` : 5-8 | `shell: useradd` + `ignore_errors` | Idempotence / fonctionnement | Moyenne | `changed` à chaque passage, et toute vraie erreur (groupe absent, disque plein) est masquée | `ansible.builtin.user` |
| 15 | `fail2ban/tasks/main.yml` : 13-15 | `fail2ban-client reload` à chaque passage | Idempotence | Moyenne | `changed` permanent, rechargement inutile | Handler notifié par le template |
| 16 | `fail2ban/vars/main.yml` | Réglages dans `vars/` | Maintenabilité | Moyenne | Impossible de corriger `ignoreip` ou `maxretry` depuis l'inventaire (précédence de `vars/`, M04-E37) | Tout dans `defaults/` |
| 17 | `comptes_equipe/tasks/main.yml` : 33 | `mode: 644` (sans zéro, ni guillemets) | Sécurité | Moyenne | YAML lit l'entier 644 : mode `01204` (bit sticky, propriétaire en écriture seule) | `mode: "0440"` |
| 18 | `playbooks/durcir-socle.yml` | `hosts: all`, sans `serial`, sans nom ; rôles appliqués au routeur et au poste d'admin | Fonctionnement | Moyenne | `gw01` : la table de fail2ban est effacée à chaque passage du rôle `pare_feu` (`flush ruleset`) ; un échec touche tout le socle d'un coup | Cibler des groupes ; ne pas mettre fail2ban sur `gw01` sans l'intégrer au pare-feu |
| 19 | `fail2ban/tasks/main.yml` : 3 | `state=latest`, forme `clé=valeur`, pas de nom complet | Maintenabilité | Faible | Version non maîtrisée, mises à jour pendant un passage de configuration | `state: present`, FQCN, mises à jour par unattended-upgrades |
| 20 | `fail2ban/tasks/main.yml` : 6-11 | Template sans `owner`/`mode` ; `when: "{{ … }}"` ; `jail.local` qui remplace toute la section `[DEFAULT]` | Maintenabilité | Faible | Droits hérités de l'umask ; `{{ }}` dans `when` retiré en 2.23 ; réglages Debian masqués | `jail.d/medisphere.local`, mode explicite, condition booléenne |

**Ordre de traitement** : d'abord ce qui donne ou garde un accès indu (1, 2, 3, 5, 7), puis ce qui peut couper l'accès légitime à tout le socle (4, 6), puis ce qui empêche le rôle de fonctionner ou rend la protection illusoire (8 à 12), enfin l'idempotence et la maintenabilité (13 à 20). Les n° 1 à 3 imposent aussi une action immédiate : ce mot de passe est « grillé » (versionné, même dans une MR non fusionnée : il est dans les objets du dépôt sur `git01`), à ne jamais utiliser.

**Version corrigée de `fail2ban`** : [`fichiers/M04-E21/roles/fail2ban/`](fichiers/M04-E21/roles/fail2ban/) — un fichier `jail.d/medisphere.local` qui ne fait que compléter Debian (`ignoreip` des postes d'administration et de la CI, `maxretry`, `findtime`, `bantime`), un handler qui **teste** la configuration complète (`fail2ban-client --test` ; `validate:` ne peut pas servir, fail2ban ne sait tester que tout `/etc/fail2ban`) puis recharge. Testé sur Debian 13 (fail2ban 1.1.0) : idempotent, `ignoreip` effectif (`fail2ban-client get sshd ignoreip`). **`comptes_equipe`** n'a pas lieu d'être : son besoin (comptes nominatifs, clés relues, départs) se couvre par `base_utilisateurs` (E14), avec des clés publiques dans le dépôt et `etat: absent` au départ.

**Question de fond.** Sur notre socle, fail2ban n'apporte presque rien : l'authentification par mot de passe est fermée (`AuthenticationMethods publickey`), une attaque par force brute sur des clés ed25519 n'a pas de sens, `MaxAuthTries` et `MaxStartups` limitent déjà les tentatives, et SSH n'est joignable que depuis MGMT et le VPN (le reste est filtré par `gw01`). Le risque, lui, est réel : bannir l'administration et l'automatisation, et une interaction de plus avec le pare-feu. Recommandation à Karim : **pas** de fail2ban sur le socle ; les échecs d'authentification remontent dans les journaux centralisés (module 22) avec une alerte ; fail2ban (ou mieux, une protection au niveau du proxy) se discute pour les services exposés **avec mot de passe** (DMZ, module 07). Les **comptes nominatifs** sont une bonne idée pour HDS (imputabilité : savoir qui a fait quoi, ce qu'`admin` partagé ne permet pas) : à faire avec `base_utilisateurs`, des clés relues en MR, sudo avec mot de passe ou journalisé, et à terme des certificats SSH (module 06) et l'annuaire (module 24).

**Conseils à Lucas** : teste dans les conditions de la cible (même version d'ansible-core, depuis `adm01`, avec l'`ansible.cfg` du projet) ; lance ansible-lint **et** un second passage, qui doit être à zéro ; essaie de casser ton rôle (que se passe-t-il si je me trompe trois fois ? si je quitte l'équipe ?) avant de demander une revue.

---

### M04-E22 — Runbook : appliquer un changement de configuration sur le socle

**Modèle** : [`fichiers/M04-E22/medisphere/docs/socle/runbooks/RB-040-appliquer-changement-configuration.md`](fichiers/M04-E22/medisphere/docs/socle/runbooks/RB-040-appliquer-changement-configuration.md).

**Ce qui fait un bon RB-040** (grille d'auto-évaluation)

| Critère | Ce qu'on attend | Points |
|---|---|---|
| Périmètre | Quand l'utiliser, et quand **ne pas** l'utiliser (hôte injoignable, mises à jour de paquets) | 2 |
| Règles | MR fusionnée seulement ; `--check --diff` lu ; un hôte puis les autres ; `gw01` seul et en dernier ; numéro de changement | 3 |
| Prérequis | Accès (agent SSH, Vault, accès Proxmox), outils, **console prête** | 2 |
| Étapes | Numérotées, chaque commande avec son résultat attendu et quoi faire sinon ; second passage à `changed=0` | 4 |
| Cas particuliers | `gw01` (filet du pare-feu, ne pas relancer après un retour automatique) ; clés et SSH (session ouverte, nouvelle connexion de test) | 3 |
| Retour arrière | Trois niveaux : revert de MR (le plus propre), commit précédent en urgence, instantané (avec ce qu'on perd) | 3 |
| Diagnostic | Symptômes fréquents (UNREACHABLE, Vault, inventaire vide, second passage non nul, rescue) → action | 2 |
| Après | Ticket, journal des changements, correction du runbook | 1 |

17 points et plus : prêt pour le test de Nadia. Moins de 12 : il manque probablement le retour arrière ou le cas de `gw01`.

**Explications**

Un runbook n'est pas une documentation : c'est une **procédure à exécuter sous stress**, par quelqu'un qui ne connaît pas le code. Chaque étape doit dire ce qu'on doit **voir** ; sans résultat attendu, l'exécutant ne sait pas s'il peut passer à la suite. Le retour arrière s'écrit avant d'en avoir besoin, et par ordre de propreté : le revert de MR garde le dépôt comme source de vérité ; l'instantané, lui, efface aussi ce qui a changé de légitime sur l'hôte depuis.

**Pièges classiques**
- « Lancer `site.yml` » sans `--limit` ni simulation : le runbook recrée le passage massif qu'il devait éviter.
- Un runbook qui suppose les connaissances de son auteur (« vérifier que chrony va bien ») : l'exécutant ne sait pas comment.
- Oublier la console : la seule chose qui sert quand SSH est cassé.
- Pas de critère de fin : on ne sait pas quand le changement est terminé (second passage à zéro, contrôle propre au changement).

**En production chez MédiSphère**
RB-040 est exécuté par la CI pour l'essentiel (E27 : `check-socle` en MR, `appliquer` manuel et protégé) ; la version humaine sert en secours et à l'astreinte. Il est testé à chaque exercice d'astreinte (F3) et relu à chaque changement de l'outillage.

---

### M04-E23 — Déléguer et orchestrer : `delegate_to`, `run_once`

**Solution**

Fichier : [`fichiers/M04-E23/ansible/playbooks/changement-socle.yml`](fichiers/M04-E23/ansible/playbooks/changement-socle.yml).

1. **Play « avant »** (`hosts: socle`, `gather_facts: false`) : `assert` sur `changement` (`^(CHG|INC)-[0-9]+$`), en `run_once` et délégué à `localhost` ; `set_fact: _chg_vise: true` (pour chaque hôte : sert au journal) ; puis
   ```yaml
   - name: Instantané Proxmox de chaque VM visée
     ansible.builtin.command:
       argv: >-
         {{ ['ms-snapshot', '--prefix', changement | lower, '--keep', '2']
            + (ansible_play_hosts | map('extract', hostvars, 'vmid') | map('string') | list) }}
     run_once: true
     delegate_to: localhost
     become: false
     changed_when: true
     when: not ansible_check_mode
     tags: [always]
   ```
   Sans `run_once` : cinq exécutions, chacune avec les cinq VMID (cinq instantanés par VM, horodatages différents, et `--keep 2` qui supprime les précédents). Avec `run_once` mais sans `delegate_to` : une exécution, **sur le premier hôte du play** (`gw01`), où `ms-snapshot` et son jeton n'existent pas. `become: false` : la tâche déléguée hériterait sinon de `become: true`… s'il était posé sur le play (il ne l'est pas ici ; il l'est dans les plays importés).
   `ansible_play_hosts` = hôtes du play **encore actifs**, après `--limit` : avec `--limit dns01`, un seul instantané. Les `vmid` viennent de l'inventaire dynamique (`compose`, E13).
2. **Play « après »** :
   ```yaml
   - name: Le nom de l'hôte est résolu par dns01
     ansible.builtin.command: dig +short +time=3 @10.10.20.10 {{ inventory_hostname }}.par1.medisphere.internal A
     register: _chg_dns
     changed_when: false
     check_mode: false
     failed_when: _chg_dns.stdout_lines | first | default('') != ansible_host
     delegate_to: dns01
     become: false
   ```
   Dans la tâche déléguée, `inventory_hostname`, `ansible_host` et toutes les variables sont **celles de l'hôte du play** (`git01` par exemple) ; seules la **connexion** et l'exécution sont celles de `dns01` (son adresse, son compte `admin`). C'est pourquoi `ansible_host` vaut 10.10.20.12 dans la comparaison, alors que la commande tourne sur 10.10.20.10. Sans `become: false`, la commande serait lancée par `sudo` sur `dns01` (si le play avait `become`).
   Le test de port : `ansible.builtin.wait_for` délégué à `localhost`. Puis `set_fact: _chg_verifie: true`.
3. **Play « journal »** sur `localhost` (`gather_facts: false`, `become: false`) : il s'exécute même si tous les hôtes du socle ont échoué (un play dont tous les hôtes sont en échec est sauté ; `localhost` n'a pas échoué). Il lit les hôtes visés et vérifiés dans `hostvars` (`groups['socle'] | map('extract', hostvars) | selectattr('_chg_vise', 'defined') …`), crée le fichier (`copy`, `force: false`) puis ajoute la ligne (`lineinfile`). En `--check`, `copy` et `lineinfile` n'écrivent rien.
4. Étiquette `always` sur toutes les tâches de l'enveloppe.
5. Changement réel :
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/changement-socle.yml -e changement=CHG-533 --tags base_journal
   TASK [Instantané Proxmox de chaque VM visée] ***************************************
   changed: [gw01 -> localhost]
   …
   TASK [base : Journal persistant avec plafond d'espace] *****************************
   changed: [dns01] …
   RUNNING HANDLER [base : Redémarrer journald] ***************************************
   …
   TASK [Le nom de l'hôte est résolu par dns01] ***************************************
   ok: [gw01 -> dns01] …
   PLAY [Journal du changement] *******************************************************
   TASK [Ligne du changement] *********************************************************
   changed: [localhost]
   root@pve01:~# qm listsnapshot 1002
   `-> chg-533-20261007-153012   2026-10-07 15:30:14   no-description
    `-> current                                          You are here!
   admin@adm01:~/medisphere$ tail -n 1 docs/socle/journal/changements-ansible.md
   | 2026-10-07 13:30 | CHG-533 | gw01, adm01, dns01, git01, runner01 | gw01, adm01, dns01, git01, runner01 | — |
   ```
   (Sortie indicative.) `gw01 -> localhost` : la tâche `run_once` s'affiche sous le premier hôte du play, exécutée sur `localhost`. Puis commit et MR du journal dans `plateforme/medisphere`.
6. **Réponses.** Avec `serial: 2`, le play est découpé en lots de deux hôtes, et `run_once` s'exécute **une fois par lot** : trois commandes `ms-snapshot`, chacune avec les VMID de son lot, au début de chaque lot. `delegate_facts: true` range les faits collectés par une tâche déléguée (`setup` délégué à `dns01`) dans `hostvars['dns01']` au lieu de l'hôte du play : utile pour lire une fois les faits d'un hôte qu'on ne configure pas dans ce play (la version de dnsmasq de `dns01`, pour l'ajouter au journal par exemple).

**Explications**

`delegate_to` change **où** une tâche s'exécute, pas **pour qui** : variables, `register`, état d'échec restent ceux de l'hôte du play. `run_once` choisit le premier hôte actif du lot et applique le résultat (et le `register`) à tous les hôtes du lot. `localhost` est un hôte implicite : il n'appartient à aucun groupe, a une connexion locale et l'interpréteur Python d'ansible-playbook (celui de l'environnement uv) — d'où `become: false` et des modules qui n'ont pas besoin de `python3-apt`.

**Alternatives**
- Un `pre_tasks` et un `post_tasks` dans chaque playbook au lieu d'une enveloppe : répétition.
- Instantanés par le module `community.proxmox.proxmox_snap` : possible, mais il faudrait donner au jeton d'Ansible le droit `VM.Snapshot` (il est en lecture seule), ou utiliser le jeton de `ms-snapshot` dans Ansible.
- Journal dans un ticket GitLab (API) plutôt qu'un fichier : plus visible, une dépendance de plus pendant un changement.

**Pièges classiques**
- `run_once` + `--limit` : l'action ne concerne que les hôtes limités (voulu ici, surprenant ailleurs).
- `delegate_to: localhost` avec `become: true` hérité : fichier du journal créé par root dans le dossier de l'utilisateur, puis `git commit` impossible.
- Une tâche déléguée qui utilise `ansible_host` en pensant obtenir l'adresse de la machine déléguée.
- Oublier `tags: [always]` : avec `--tags`, l'enveloppe disparaît et le changement passe sans instantané ni journal.
- `ignore_unreachable` ou `any_errors_fatal` mal placés : un hôte injoignable fait sauter tout le play « après » pour lui, et le journal le classe en échec (c'est voulu : un hôte non vérifié est un hôte en échec).

**En production chez MédiSphère**
L'enveloppe devient le job `appliquer` de la CI (E27) : numéro de changement tiré de la MR, instantané, application, vérification, journal et commentaire automatique dans la MR. Les instantanés sont supprimés au bout de 24 h par une tâche planifiée.
