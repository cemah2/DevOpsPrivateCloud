# Module 04 — Corrigé du palier 5 : Mini-projet

> ⚠️ Corrigé — à lire après avoir cherché.

---

### M04-E46 — Mini-projet : le socle en configuration as code

**Solution**

Il n'y a pas « une » solution : il y a un dépôt qui décrit tout le socle, une chaîne qui l'applique et une équipe qui peut s'en servir sans toi. Les fichiers de référence sont répartis dans les exercices ; ce mini-projet les assemble et ajoute ce qui manquait.

| Élément | Où le trouver |
|---|---|
| Projet, environnement `uv`, `ansible.cfg`, inventaires statique et dynamique | corrigés de M04-E02, E03, E13 (`corrige/fichiers/M04-E02/`, `M04-E03/`, `M04-E13/`) |
| Rôles `base`, `ssh_durci`, `gitlab_runner`, `pare_feu`, collection `medisphere.socle` | corrigés de M04-E10, E11, E16, E17, E18 |
| Vault, séparation et rotation | M04-E12, M04-E30 |
| Molecule, CI, Semaphore, dérive | M04-E24, E27, E28, E29 |
| Renforcement du rôle `ssh_durci` (clés d'hôte, adresses d'écoute, validation à chaque passage, port vérifié) | [`fichiers/M04-E40/ssh_durci-renforcement.yml`](fichiers/M04-E40/ssh_durci-renforcement.yml) |
| Module `systemd_dropin` et `Restart=on-failure` de `chrony` | [`fichiers/M04-E44/`](fichiers/M04-E44/) |
| **Nouveau** — rôle `dnsmasq` et son scénario Molecule | [`fichiers/M04-E46/roles/dnsmasq/`](fichiers/M04-E46/roles/dnsmasq/), [`fichiers/M04-E46/molecule/dnsmasq/`](fichiers/M04-E46/molecule/dnsmasq/), job CI : [`fichiers/M04-E46/gitlab-ci-molecule-dnsmasq.yml`](fichiers/M04-E46/gitlab-ci-molecule-dnsmasq.yml) |
| **Nouveau** — données DNS/DHCP du socle | [`fichiers/M04-E46/inventories/lab/group_vars/role_dns/dnsmasq.yml`](fichiers/M04-E46/inventories/lab/group_vars/role_dns/dnsmasq.yml) |
| **Nouveau** — rôle `gitlab_hote` | [`fichiers/M04-E46/roles/gitlab_hote/`](fichiers/M04-E46/roles/gitlab_hote/) |
| **Nouveau** — `site.yml` final, `dns01.yml`, `git01.yml` | [`fichiers/M04-E46/playbooks/`](fichiers/M04-E46/playbooks/) |
| **Nouveau** — modèle de `docs/socle/configuration.md` | [`fichiers/M04-E46/docs/socle/configuration.md`](fichiers/M04-E46/docs/socle/configuration.md) |

Les fichiers nouveaux passent `ansible-lint` (profil `production`) et `ansible-playbook --syntax-check` avec ansible-core 2.21 ; le modèle du rôle `dnsmasq`, rendu avec les données du socle, donne **les mêmes directives** que le fichier de référence de M00-E14 (seul l'ordre des `host-record` change), plus `git01` et `runner01` ajoutés au module 01. Les noms des playbooks importés par `site.yml` (`socle-base.yml`, `runner01.yml`, `gw01-pare-feu.yml`) sont ceux du projet de référence : adapte-les aux tiens.

**Démarche recommandée** (10 à 14 h)

1. **Assainir d'abord** (1 h) : `lab/bin/check 04 46`, puis les contrôles détaillés. KO typiques : une panne `M04` jamais close, `sem01` ou une instance Molecule encore là, une copie de travail avec des fichiers d'essai, `ansible-lint` qui signale un rôle écrit tôt dans le module, l'inventaire dynamique qui n'est pas strict.

2. **Reprendre `dns01` sans casse** (2 à 3 h). Démarche de « reprise d'existant » :
   - photographier l'existant : `sudo cat /etc/dnsmasq.d/medisphere.conf`, `dnsmasq --test`, et une **batterie de requêtes de référence** enregistrée dans un fichier (noms internes, inverses, nom externe, zone inconnue → NXDOMAIN), avec `dig +short` ;
   - écrire les données (`group_vars/role_dns/dnsmasq.yml`) jusqu'à ce que `--check --diff --limit dns01 --tags dnsmasq` ne montre plus que des commentaires et l'ordre des lignes ; ce premier passage réel est annoncé (un redémarrage de `dnsmasq`, moins d'une seconde d'interruption) ;
   - rejouer la batterie de requêtes et comparer ; vérifier qu'un client du VLAN 99 obtient toujours un bail (`journalctl -u dnsmasq | grep DHCPACK` après un `dhclient` sur une VM de test, ou attendre un renouvellement) ;
   - le rôle valide la configuration **complète** (`dnsmasq --test` sans fichier) avant de redémarrer, et se vérifie lui-même (sonde `dig` sur chaque adresse d'écoute) : leçons de M04-E40 et E36.

3. **Reprendre `git01` sans toucher à GitLab** (1 h). Le rôle `gitlab_hote` gère l'**hôte** : paquet `gitlab-ce` en `hold` (aucune mise à jour hors procédure M01-E29), droits des fichiers sensibles de `/etc/gitlab`, état de GitLab vérifié **en lecture** (`gitlab-ctl status`). Il ne touche ni `gitlab.rb` ni `gitlab-ctl reconfigure` : GitLab a son propre outil de configuration déclarative, deux outils sur le même fichier se battraient. Deux points d'attention avec les rôles communs :
   - `ssh_durci` : `sshd` de `git01` sert aussi `git@git01` (Git en SSH, compte `git`, clés vérifiées par GitLab). Le rôle de M04-E11 ne restreint les comptes que par une liste de refus (`ssh_durci_utilisateurs_refuses`) : `git` ne doit jamais y figurer, et une évolution vers une liste d'autorisation (`AllowUsers`) devrait l'inclure sur `role_gitlab`, sous peine de couper les `git push` de toute l'équipe. Molecule ne le verra pas (pas de GitLab sur l'instance) : un `--check --diff --limit git01` relu, puis un `ssh -T git@git01.par1.medisphere.internal` après application, si ;
   - `base` : si `unattended-upgrades` est configuré pour la sécurité seulement, le dépôt de GitLab n'en fait pas partie ; le `hold` rend la règle explicite.

4. **Assembler `site.yml`** (1 h) : garde-fou d'inventaire en tête, rôles communs, DNS (les autres en dépendent), forge, runner, et `gw01` en dernier (son rôle `pare_feu` a un filet anti-coupure, M04-E17, mais si quelque chose devait mal tourner, le reste a déjà convergé et `adm01` garde la main par la console de `pve01`). `serial: 1` + `any_errors_fatal` sur les rôles qui portent un service unique (DNS) : le jour où `dns02` existera (M06), on ne casse jamais les deux à la fois.

5. **Idempotence** (1 à 2 h) : passage réel par le job `appliquer`, puis un second : `changed=0`. Les `changed` résiduels typiques et leur correction :

   | Symptôme au second passage | Cause | Correction |
   |---|---|---|
   | une tâche `command`/`shell` toujours `changed` | commande de lecture | `changed_when: false` **et** `check_mode: false` (lecture seulement) |
   | une tâche `command` d'action toujours `changed` | pas d'idempotence | `creates:`/`removes:` ou test préalable, ou module dédié |
   | `template` `changed` à chaque passage | valeur qui change à chaque rendu (date, `ansible_date_time`, ordre d'un dictionnaire non trié) | retirer la valeur variable, trier (`dictsort`) |
   | handler de redémarrage à chaque passage | notifié par une tâche non idempotente | corriger la tâche, pas le handler |
   | `apt` `changed` | `update_cache: true` sans `cache_valid_time` | `cache_valid_time: 3600` |

6. **Tests et CI** (2 h) : un scénario Molecule par rôle maison, sur le modèle de M04-E24 (`molecule/<rôle>/`, inventaire avec un VMID réservé, `create`/`destroy` communs), qui vérifie l'**état effectif** : [`molecule/dnsmasq/verify.yml`](fichiers/M04-E46/molecule/dnsmasq/verify.yml) interroge le DNS, il n'inspecte pas le fichier. VMID du scénario `dnsmasq` : 2049, laissé libre par M04-E24 (et utilisé ponctuellement par le CHRONO M04-E34 : ne lance pas les deux en même temps). Un job `molecule:dnsmasq` sur le modèle des autres, déclenché par les changements du rôle ; `ansible-lint` en profil `production` (ou `shared`, justifié dans `.ansible-lint`).

7. **Inventaire, secrets, dérive** (1 h) : `[inventory] any_unparsed_is_failed = True` dans `ansible.cfg`, garde-fou de nombre dans `site.yml` et dans le playbook de dérive (M04-E39) ; registre des secrets complété ; démonstration de dérive (exemple : `sudo sed -i 's/^MaxAuthTries 3$/MaxAuthTries 6/' /etc/ssh/sshd_config.d/01-ssh-durci.conf` sur `runner01`, annoncé dans le journal, puis lancement de la planification `derive` : le job échoue avec le `--diff` qui montre la ligne, le ticket « derive » est ouvert ; correction par le job `appliquer`).

8. **Documentation et revue** (2 h) : `configuration.md` (modèle fourni, section « ce qui n'est pas en code » remplie honnêtement), RB-040 mis à jour (ajouter : inventaire, coffre, relance après échec partiel), ADR-0040, inventaire et matrice des flux.

9. **Hygiène** (30 min) :
   ```
   admin@adm01:~$ ssh pve01 "qm list | awk 'NR>1 && \$1 >= 2040 && \$1 <= 2049'"
   admin@adm01:~$ ls ~/.local/state/workbook/pannes-actives/ 2>/dev/null
   admin@adm01:~/src/ansible$ git status --short && gitleaks git --no-banner --redact .
   admin@adm01:~$ find ~/.config/workbook -type f ! -perm 600
   ```
   ⚠️ Avant de détruire `sem01` (2041) : exporter sa configuration (projets, modèles, inventaires, environnements) dans `configuration.md` et révoquer sa clé de déploiement et sa clé SSH (registre des secrets) ; retirer son `host-record` (rôle `dnsmasq`, par MR) et ses flux (`pare_feu`, par MR) **après** la destruction de la VM.

**Grille d'évaluation de la revue** (Claire, Karim, Sophie, Nadia ; en auto-évaluation si tu travailles seul)

Barème sur 100. Seuil de recette : 70, **et** aucun critère éliminatoire.

*Critères éliminatoires* : contrôle global non vert ; un secret en clair dans un dépôt, un journal CI ou la documentation (même dans l'historique) ; une machine du socle modifiée à la main sans trace ni reprise par la chaîne ; `host_key_checking = False` ou un jeton Proxmox aux droits élargis « pour que ça marche ».

| # | Axe | Points | Insuffisant (0-40 %) | Attendu (60-80 %) | Excellent (100 %) |
|---|---|---|---|---|---|
| 1 | Couverture | 15 | des machines ou des fonctions hors code sans le dire | les cinq machines convergées, `changed=0` au second passage | « ce qui n'est pas en code » documenté et transformé en tickets |
| 2 | Qualité des rôles | 20 | rôles non idempotents, `changed_when: false` de complaisance | rôles idempotents, variables préfixées, défauts sensés | état effectif vérifié par les rôles eux-mêmes ; reprise de `dns01` et `git01` sans différence non voulue |
| 3 | Tests | 15 | lint seul | Molecule par rôle, en CI sur les rôles modifiés | vérifications d'état effectif, cas d'échec testés (fichier invalide injecté) |
| 4 | Chaîne et traçabilité | 15 | application depuis un poste | MR + `--check --diff` + job protégé | trace exploitable (qui, quoi, quel commit), retour arrière décrit et testé |
| 5 | Sécurité | 15 | secrets et accès non inventoriés | Vault, registre des secrets, clés d'automatisation restreintes | rotations décrites et testées, droits Proxmox minimaux justifiés |
| 6 | Exploitation | 10 | pas de dérive | dérive planifiée qui échoue sur changement | démonstration faite, inventaire vide bloquant, durée surveillée |
| 7 | Présentation et défense | 10 | lecture des fichiers | 10 min structurées, démonstration réussie | limites, risques et suite (M05, M06) assumés |

**Questions de revue typiques et éléments de réponse attendus**

| Question | Ce qu'une bonne réponse contient |
|---|---|
| (Sophie) « Si `runner01` est compromis, qu'obtient l'attaquant ? » | la clé `ansible-ci` (admin + `sudo` sur le socle, limitée par `from=` à `runner01`… donc utilisable depuis `runner01`), le mot de passe du coffre et le jeton `wb-ansible` **pendant** un job protégé (variables protégées : seulement sur `main` et les étiquettes protégées) ; d'où : runner dédié aux jobs protégés, jobs de MR sans secrets, rotation, et à terme des secrets à courte durée (module 25) |
| (Karim) « Comment sais-tu que ton rôle `dnsmasq` ne change pas les réponses ? » | la batterie de requêtes de référence rejouée avant/après, le `--diff` nul, le scénario Molecule qui interroge le DNS |
| (Nadia) « Le job `appliquer` échoue au milieu de `site.yml` : que fais-je ? » | lire le récapitulatif (quels hôtes, quelle tâche), ne pas relancer à l'aveugle, `--check --diff --limit` sur l'hôte en échec, relance ciblée (`--limit`, `--start-at-task` en dernier recours), consigner ; c'est une section du RB-040 |
| (Claire) « Qu'est-ce qui change au module 05 et 06 ? » | OpenTofu crée les VMs (étiquettes `socle`/`role-…` posées par le code), Ansible les configure ; NetBox devient la source de l'inventaire ; PowerDNS/Kea remplacent `dnsmasq` (le rôle est retiré, ses données migrent) ; certificats SSH (M06) |
| (Karim) « Pourquoi pas `strategy: free` pour aller plus vite ? » | M04-E41 : elle déplace l'attente sans la supprimer, rend la sortie plus difficile à lire et casse l'ordre implicite entre hôtes ; on mesure d'abord |

**Explications**

Le contrôle global vérifie la **forme** (pipelines, planification, convergence, documents) ; la revue vérifie l'**usage** : Nadia qui applique un changement avec le seul RB-040 est le test qui compte. Le palier 4 a montré que la chaîne de configuration casse surtout par ce qui se fait **hors** d'elle (copie de travail partagée, fichiers posés à la main, droits changés en direct) : la livraison se juge donc autant sur la discipline (tout passe par la chaîne, la dérive se voit) que sur les rôles.

**Alternatives**
- Semaphore UI comme chemin d'exécution de référence (si ADR-0040 le retient) : interface pour les non-spécialistes, historique, planification ; au prix d'une machine et d'une base de plus à maintenir, et des mêmes secrets à protéger.
- Un dépôt par rôle (rôles versionnés et publiés dans un registre de collections) : pertinent à l'échelle de plusieurs équipes, prématuré pour le socle.

**Pièges classiques**
- Reprendre `dns01` en écrivant le rôle « idéal » et en découvrant les différences en production.
- Gérer `gitlab.rb` avec Ansible en plus de `gitlab-ctl reconfigure`.
- Un second passage `changed=0` obtenu à coups de `changed_when: false`.
- Un contrôle de dérive qui passe vert sur un inventaire vide.
- Détruire `sem01` sans révoquer ses clés.

**En production chez MédiSphère**
La configuration du socle est un produit : propriétaire, versions, journal des modifications ; chaque machine nouvelle (module 05) naît avec ses étiquettes et passe par `site.yml` avant d'entrer en service ; la dérive est suivie en tableau de bord (module 21) ; les secrets d'exécution deviennent des secrets à courte durée émis par Vault/OpenBao (module 25) ; le bastion n'est plus un poste partagé (comptes nominatifs, certificats SSH, module 06).
