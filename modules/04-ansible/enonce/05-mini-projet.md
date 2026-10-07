# Module 04 — Palier 5 : Mini-projet

Fin du quatrième chantier. Au début du module, le socle était un ensemble de machines configurées à la main, chacune un peu différemment. Il est devenu un projet : des rôles relus et testés, un inventaire qui suit Proxmox, des secrets chiffrés, une chaîne qui vérifie chaque changement en `--check` et une détection de dérive qui veille la nuit. Il reste à le **livrer** : que tout le socle, sans exception, soit décrit par ce code, que ce code soit la seule façon de le modifier, et que l'équipe puisse s'en servir sans toi. Les modules suivants s'appuient dessus : OpenTofu (module 05) créera les machines et Ansible les configurera, NetBox (module 06) deviendra la source de l'inventaire, PowerDNS et Kea remplaceront le rôle `dnsmasq` que tu écris ici. Ce mini-projet est ce que Claire Morel présentera à l'auditeur HDS comme « la configuration du socle est en code ».

---

### M04-E46 — Mini-projet : le socle en configuration as code  `LIBRE` `★★★`

> **Ticket PLAT-590** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent, Nadia Roussel*
> Recette de la configuration du socle vendredi. Ce que je veux montrer à l'auditeur : **chaque** machine du socle (`gw01`, `adm01`, `dns01`, `git01`, `runner01`) est décrite par le dépôt `plateforme/ansible` ; un second passage ne change rien ; aucun changement n'arrive en production sans MR, tests et trace d'exécution ; on saurait dès le lendemain si quelqu'un modifiait une machine à la main ; les secrets sont chiffrés. Karim fera la revue du code et des tests, Sophie celle des secrets et des accès, Nadia testera le runbook en appliquant elle-même un changement. Format habituel : 10 minutes de présentation, une démonstration, nos questions.

**Objectifs pédagogiques**
- Consolider les briques du module (rôles, inventaire dynamique, Vault, Molecule, CI, exécution traçable, dérive) en une chaîne cohérente, sans dette cachée.
- Reprendre en code les deux machines qui ne l'étaient pas encore (`dns01`, `git01`) sans les réinstaller ni interrompre leur service.
- Préparer les modules suivants : ce qui sera repris par OpenTofu (création des machines), NetBox (inventaire) et les services socle du module 06.

**Prérequis** : M04-E01 à M04-E45 (au minimum tous les `LAB`, `LIBRE`, `BF` et le `CHRONO`).
**Durée indicative** : 10 à 14 h, plus 30 min de revue.

**Contexte technique**
- Projet : `plateforme/ansible` (clone `~/src/ansible`, variable `WB_SRC`) ; documentation : `plateforme/medisphere` (clone `~/medisphere`, variable `WB_DEPOT`). Arborescence de référence du projet : [`00-introduction.md`](00-introduction.md).
- Hôtes et groupes : `socle` = `gw01` (`role_routeur`), `adm01` (`role_bastion`), `dns01` (`role_dns`), `git01` (`role_gitlab`), `runner01` (`role_runner`), identiques dans l'inventaire statique et dans l'inventaire dynamique.
- **Nouveaux rôles minimaux** : `dnsmasq` pour `dns01` (il remplace la gestion à la main de `/etc/dnsmasq.d/medisphere.conf` jusqu'au module 06, qui passera à PowerDNS et Kea : le fichier généré doit donner **exactement** les mêmes réponses DNS et DHCP qu'aujourd'hui) et un rôle de configuration de l'hôte `git01` autour de GitLab (sans réinstaller ni reconfigurer GitLab lui-même : ni `gitlab.rb`, ni `gitlab-ctl reconfigure`).
- **Exécution de référence** : le pipeline protégé de `plateforme/ansible` (job `appliquer`, manuel, sur `main`, M04-E27). `sem01` (VM d'environnement 2041) est **détruite** à la fin du module, comme toutes les VMs 2040-2049 : sa configuration (projet, inventaire, modèles, clés et leur portée) est décrite dans `docs/socle/configuration.md` pour pouvoir la recréer. Si ton ADR-0040 (M04-E31) retient Semaphore UI comme outil d'exécution, il le dit, et indique que sa mise en service permanente (hôte du socle, VMID de la plage 1000-1099) est reportée au module 05, où les VMs durables seront créées par OpenTofu.
- Le contrôle global `lab/bin/check 04 46` lance notamment un `ansible-playbook playbooks/site.yml --check` complet (quelques minutes) et `ansible-lint`, et interroge GitLab (pipelines, planification, versions). Il vérifie aussi les protections de M04-E39 : garde-fou sur le contenu du groupe `socle` en tête de `site.yml`, et `unparsed_is_failed` ou `any_unparsed_is_failed` activé dans la section `[inventory]` de `ansible.cfg`.

**Travail demandé**
1. **Tout le socle en code.** `playbooks/site.yml` converge les cinq machines : rôles communs partout, rôle par fonction (routeur, bastion, DNS, forge, runner), dans un ordre que tu justifies (où mets-tu `gw01` et pourquoi ?). Un garde-fou en tête refuse de continuer si l'inventaire ne contient pas les cinq hôtes. Avant de prendre la main sur `dns01` et `git01`, compare l'existant et ce que tes rôles produiraient (`--check --diff`) jusqu'à n'avoir **aucune** différence non voulue.
2. **Idempotence prouvée.** Un passage réel de `site.yml` par la chaîne, puis un second : `changed=0` partout. Tout `changed` résiduel est corrigé dans le rôle, pas masqué (`changed_when: false` n'est acceptable que pour une commande de lecture).
3. **Tests.** Chaque rôle maison (au moins `base`, `ssh_durci`, `dnsmasq`) a un scénario Molecule sur VM éphémère qui vérifie l'**état effectif** (pas seulement des fichiers) ; la CI les lance sur les rôles modifiés ; `ansible-lint` (profil choisi et justifié) passe sur tout le projet.
4. **Inventaire et secrets.** L'inventaire dynamique Proxmox est l'inventaire par défaut de la CI et du contrôle de dérive, avec les protections de M04-E39 ; tous les secrets du projet sont en Vault, le registre des secrets (`docs/socle/registre-secrets.md`) liste ceux du module (jeton `wb-ansible`, mot de passe du coffre, clés SSH d'automatisation, clé de déploiement, jetons CI) avec emplacement, portée, propriétaire, échéance.
5. **Chaîne d'application.** Toute modification passe par MR (lint, Molecule, `--check --diff` affiché dans la MR) et s'applique par le job protégé depuis `main`, avec trace (qui, quand, quel commit, quel résultat). Les flux nécessaires sont ouverts au plus juste et reportés dans `docs/socle/matrice-flux.md`.
6. **Dérive.** Le contrôle de dérive planifié tourne chaque nuit, échoue (et alerte) s'il trouve un changement ou si l'inventaire est incomplet, et son dernier passage est vert. Démontre-le : modifie à la main un réglage géré sur une machine, constate l'alerte le lendemain matin (ou en lançant la planification), corrige par la chaîne.
7. **Documentation.** `docs/socle/configuration.md` (organisation du projet, rôles et ce qu'ils gèrent **et ne gèrent pas**, variables importantes, conventions de l'équipe tirées du palier 4, chaîne d'application, contrôle de dérive, procédure de rotation du coffre, recréation de Semaphore) ; RB-040 (appliquer un changement, M04-E22) mis à jour et testé par quelqu'un d'autre (ou par toi, une semaine plus tard, sans autre document) ; ADR-0040 fusionné ; inventaire du socle et matrice des flux à jour.
8. **Version et hygiène.** Une version publiée du projet (étiquette `vX.Y.Z` posée par semantic-release) contient tout le livrable. Aucune panne `M04` active, VMs 2040-2049 détruites (dont `sem01`), copie de travail propre, aucun secret en clair dans les dépôts.
9. **La revue.** Prépare 10 minutes de présentation (ce qui est en code, ce qui ne l'est pas encore et pourquoi, les risques) et la démonstration : Nadia applique un changement simple (une ligne du `motd`, par exemple) avec le seul RB-040, de la branche à la vérification.

**Contraintes**
- Aucune réinstallation de machine du socle ; aucune interruption de service de `dns01` (DNS et DHCP) ni de `git01` au-delà d'un redémarrage de service annoncé.
- Aucun secret en clair dans le dépôt, les journaux CI, les sorties de Semaphore ou la documentation (cite des **emplacements**, jamais des valeurs).
- Aucune modification manuelle du socle pendant le mini-projet, sauf la démonstration de dérive (étape 6), annoncée et corrigée par la chaîne.
- Les choix qui s'écartent de l'énoncé d'un exercice sont justifiés (ADR ou description de MR).

**Critères de réussite**
- [ ] `lab/bin/check 04 46` est entièrement vert.
- [ ] `site.yml` converge les cinq machines du socle, un second passage donne `changed=0`, et le `--check` planifié est vert.
- [ ] La démonstration de dérive a été faite : alerte reçue, correction par la chaîne, trace dans le journal.
- [ ] Le runbook RB-040 a permis à un tiers d'appliquer un changement sans aide (auto-évaluation avec la grille du corrigé si tu travailles seul).
- [ ] La documentation dit ce qu'Ansible **ne** gère **pas** encore sur le socle.

**Vérification** : `lab/bin/check 04 46`

<details><summary>Indice 1</summary>

Lance `lab/bin/check 04 46` dès le début : la liste des points rouges est ton plan de travail. Les contrôles détaillés (`lab/bin/check 04 XX`) donnent le détail par brique.
</details>

<details><summary>Indice 2</summary>

Pour reprendre une machine existante sans casse : récupère d'abord sa configuration réelle (les fichiers, mais aussi les paquets, les services actifs, les surcharges systemd), écris le rôle pour qu'il produise **la même chose**, et itère sur `--check --diff --limit <hôte>` jusqu'à zéro différence. Ce n'est qu'ensuite que tu changes quelque chose, dans une MR séparée.
</details>

<details><summary>Indice 3</summary>

Pour `git01`, la frontière est nette : GitLab lui-même est géré par son propre outil (`gitlab.rb` et `gitlab-ctl reconfigure`, module 01) ; ton rôle gère **l'hôte** autour : version du paquet maîtrisée, droits des fichiers sensibles, accès SSH du compte `git` compatibles avec `ssh_durci`, et des vérifications en lecture de l'état de GitLab.
</details>

**Pour aller plus loin** (facultatif) : une étiquette `configuration-v1` dans `plateforme/medisphere` sur le commit qui documente la livraison ; un tableau de bord (préparé pour le module 21) de la dérive par hôte et de la durée des passages ; une liste « ce qu'Ansible ne gère pas encore » transformée en tickets.
