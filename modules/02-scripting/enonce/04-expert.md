# Module 02 — Palier 4 : Expert

`plateforme/outils` est en production : la CI vérifie chaque MR, `medictl` s'installe depuis le registre, le contrôle des sauvegardes tourne chaque matin, Nadia a son guide d'astreinte. Claire Morel prévient : « Maintenant que l'équipe dépend de ces outils, leur panne est un incident comme un autre. Et un outil d'exploitation tombe rarement en panne parce que son code change : il tombe parce que son **environnement** change. » Ce palier est celui des incidents : huit pannes d'outillage (environnement d'exécution, droits d'API, scripts qui détruisent ou perdent des données, CI, planification, Python), une astreinte où elles se combinent, puis une descente sous le capot de Bash et des questions d'entretien. La méthode est celle des modules 00 et 01 : observer avant d'agir, formuler une hypothèse, la tester par la mesure la moins invasive, corriger à la racine, prévenir la récidive. Avec une règle de plus, propre aux scripts : **on ne teste jamais un correctif sur des données réelles.**

> **Rappels** : tout se fait depuis `adm01`. Projet : `~/src/outils` (variable `WB_SRC`). Conventions communes (codes retour 0/1/2/3, stdout pour les données, secrets dans `~/.config/workbook/` en 600, TLS vérifié) : voir [`00-introduction.md`](00-introduction.md). Tout correctif durable passe par une MR fusionnée dans `main`, pipeline vert.

## Règles du jeu des pannes (M02-E35 à M02-E43)

- Les pannes s'injectent **depuis `adm01`**, à la racine de ta copie du workbook :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ lab/bin/break 02 35
  ```
  Le script tire une variante au hasard et n'affiche que le **symptôme**, comme un ticket. Chaque panne a 4 variantes : refais l'exercice jusqu'à les avoir toutes rencontrées (`--variante N` force une variante, sans dire laquelle est laquelle).
- **Avant d'injecter**, lance le contrôle de l'exercice (`lab/bin/check 02 35`) : il doit être vert. Exception : E37, E39 et E40 déposent eux-mêmes, à l'injection, une zone de test dans `/opt/workbook/m02/eXX/` ; leur contrôle ne vérifie rien avant (il l'indique).
- **Ne lis pas** les scripts de `corrige/pannes/`, ni `corrige/fichiers/M02-EXX/panne/`, ni `/var/lib/workbook/` sur `adm01` et `pve01`, ni `~/.local/state/workbook/` : ils contiennent la cause.
- Une seule panne active à la fois par exercice. Si tu abandonnes : `lab/bin/break 02 35 --annuler` remet l'état sain (filet de sécurité, pas un correctif : compte l'exercice comme non réussi). Pour E37, E39 et E40, l'annulation **déplace** la zone de test (`/opt/workbook/m02/eXX.annule-<date>`) sans rien supprimer ; fais le ménage toi-même quand tu n'en as plus besoin.
- Les pannes agissent sur `adm01` (unités systemd, environnements Python, outil installé par `uv tool`, fichiers de configuration : tous sauvegardés avant modification), sur `pve01` (jeton, ACL et compte `wb-automation@pve` uniquement : jamais de réseau ni de pare-feu), et sur GitLab par l'API avec ton **jeton d'administration** (`WB_GITLAB_ADMIN_TOKEN_FILE`) : une MR ouverte au nom de Lucas, une variable CI. Elles ne suppriment aucun projet, aucune VM, aucune sauvegarde, aucun fichier de ton dépôt. Les scripts « défectueux » de E37 et E39 ne travaillent que sur des **données fictives** fabriquées à l'injection.
- Ton jeton d'administration GitLab doit être valide (90 jours au plus, M01-E05) : sinon E38 échoue proprement à l'injection. Renouvelle-le d'abord.
- **Tiens un journal de diagnostic** pour chaque panne, dans `docs/socle/journal/` de ton clone `~/medisphere` (publié par MR) : heure, hypothèse, commande, résultat observé, conclusion. Il alimente le post-mortem de M02-E43.
- Le **temps cible** est indicatif. Le dépasser n'est pas un échec ; corriger sans comprendre en est un.

> ⚠️ **Accès de secours** : plusieurs pannes touchent ce dont tu te sers pour diagnostiquer (`medictl`, le jeton d'automatisation, l'environnement Python). Tu as toujours l'interface web de `pve01` (compte `wb-admin`), SSH vers `pve01` en root (`pveum`, `pvesh`, `qm` y fonctionnent sans jeton) et `curl` pour parler à l'API sans dépendre de `medictl`. Repère ces chemins **avant** d'en avoir besoin.

---

### M02-E35 — Panne : le script marche à la main mais pas la nuit  `BF` `★★`

> **Ticket INC-2841** — *De : Nadia Roussel*
> Le contrôle des sauvegardes de 07:30 sur `adm01` est en échec, et j'ai reçu l'alerte. Lucas a relancé le script à la main : tout est vert, les sauvegardes de la nuit sont bien là. Il dit que « ça marche chez lui ». Je ne veux pas d'un contrôle qui crie au loup : il doit passer en planifié, pas à la main.

**Objectifs pédagogiques**
- Distinguer l'environnement d'un terminal de celui d'un service systemd : utilisateur, `HOME`, variables, protections, commande réellement exécutée.
- Lire la configuration **effective** d'une unité (fichier, drop-ins, valeurs appliquées) plutôt que le fichier qu'on croit en vigueur.
- Reproduire une exécution « comme le service » sans attendre 07:30.

**Prérequis** : M02-E26 (`ms-verif-sauvegardes`, ses unités et `ms-alerte@`), M02-E29 ; `lab/bin/check 02 35` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Injection** : `lab/bin/break 02 35` (4 variantes). Le script relance une fois le service, comme le timer l'aurait fait : l'échec et l'alerte sont dans le journal.

**Travail demandé**
1. Reproduis les deux constats du ticket : l'échec sous systemd (`systemctl status`, journal de l'unité, alerte `ms-alerte`) et la réussite dans ton terminal. Note le message d'erreur **exact** du service.
2. Avant d'ouvrir le moindre fichier d'unité, liste tout ce qui peut différer entre ton terminal et le service (au moins six éléments). Pour chacun, indique la commande qui montre la valeur appliquée au service.
3. Trouve ce qui a changé et prouve-le : quel fichier, posé quand, avec quelle valeur effective. Reproduis l'échec **en dehors du timer**, avec l'environnement exact du service, puis la réussite une fois la différence retirée.
4. Corrige à la racine. Si la modification avait une intention légitime (durcissement, journalisation, réseau), atteins cet objectif **autrement**, sans casser le contrôle, et explique-le dans ton journal.
5. Relance le service par `systemctl start` : il doit réussir, et l'alerte ne doit plus se déclencher. Ajoute au guide d'astreinte (`docs/astreinte.md`) la procédure « rejouer le contrôle comme le service ».

**Critères de réussite**
- [ ] Le service tourne en `admin`, exécute la copie installée `/usr/local/bin/ms-verif-sauvegardes` (identique à celle de `main`), avec un accès en lecture à ses fichiers de configuration ; son dernier passage sous systemd a réussi.
- [ ] Aucun proxy n'intercepte ses appels aux API de Proxmox VE et de PBS ; le timer est actif.
- [ ] Ton journal contient le message d'erreur, la liste des différences terminal/service, la preuve de la cause et la commande de reproduction « comme le service ».

**Vérification** : `lab/bin/check 02 35`

<details><summary>Indice 1</summary>

`systemctl cat` n'affiche pas seulement le fichier d'unité. Et `systemctl show -p <Propriété>` donne la valeur **appliquée**, après tous les fichiers lus : `User`, `ExecStart`, `Environment`, `ProtectHome`… Compare avec ce que tu croyais.
</details>

<details><summary>Indice 2</summary>

`systemd-run` lance une commande comme une unité transitoire, avec les propriétés que tu lui passes (`-p`) ; `--wait`, `--pipe` et `--collect` en font un outil de reproduction interactif. `systemd-delta` liste ce qui étend ou remplace les unités livrées.
</details>

<details><summary>Indice 3</summary>

Un message d'erreur qui cite un chemin te dit aussi **qui** cherchait ce chemin, et avec quel `HOME`. Un message de `curl` qui cite une adresse que tu n'as jamais configurée te dit par où passent ses connexions.
</details>

**Pour aller plus loin** (facultatif) : `systemd-analyze security ms-verif-sauvegardes.service` donne un score d'exposition ; durcis encore le service (`ReadOnlyPaths=`, `InaccessiblePaths=`, `CapabilityBoundingSet=`) **en le relançant après chaque ajout**. [systemd.exec](https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html), [systemd-run](https://www.freedesktop.org/software/systemd/man/latest/systemd-run.html).

---

### M02-E36 — Panne : `medictl` ne parle plus à Proxmox  `BF` `★★`

> **Ticket INC-2842** — *De : Karim Benali*
> Depuis ce matin, `medictl` ne fonctionne plus depuis `adm01` : `medictl vm list --pool lab` échoue ou ne renvoie plus rien, alors que les VMs tournent (l'interface web de Proxmox les montre). `ms-snapshot` est en erreur aussi. Personne n'a touché au code de `plateforme/outils` depuis la dernière release. J'ai une intervention à 14 h qui a besoin des instantanés.

**Objectifs pédagogiques**
- Décomposer un appel d'API en maillons testables séparément : configuration locale, TLS, authentification, autorisation, données.
- Interpréter les codes et erreurs de chaque maillon (erreur de vérification TLS, 401, 403, liste vide en 200).
- Mesurer les droits **effectifs** d'un jeton à privilèges séparés, et corriger sans élargir les droits.

**Prérequis** : M00-E17 (jeton, rôle `WBAutomation`, séparation des privilèges), M02-E08, M02-E19, M02-E26 ; `lab/bin/check 02 36` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Injection** : `lab/bin/break 02 36` (4 variantes).

**Travail demandé**
1. Reproduis avec `medictl`, en mode verbeux, et note la classe d'erreur. Un résultat vide est-il un échec pour `medictl` ? Pour toi ?
2. Contourne `medictl` : interroge l'API avec `curl` et le même fichier d'accès, **sans jamais faire apparaître le secret** dans la ligne de commande ni dans ton journal. Teste un maillon à la fois : `GET /version` (TLS et authentification), puis `GET /cluster/resources?type=vm` (autorisation et données).
3. Va voir côté `pve01`, en root : état du compte, du jeton, de ses ACL et de ses droits **effectifs** sur `/pool/lab`. Compare avec la conception de M00-E17.
4. Corrige avec le moindre privilège. Si la cause est une décision humaine (revue d'accès, rotation), la correction technique ne suffit pas : note dans ton journal ce que tu demandes à qui.
5. Vérifie que tout ce qui dépend du même compte est revenu : `medictl`, `ms-snapshot --dry-run`, le contrôle des sauvegardes (jeton `!lecture`).
6. Propose une sonde qui aurait détecté la panne **avant** Karim.

**Critères de réussite**
- [ ] `medictl vm list --pool lab --format json` renvoie les VMs du pool ; l'API répond au jeton avec TLS vérifié contre la CA de `pve01`.
- [ ] Le compte `wb-automation@pve` est actif, son jeton `!lab` valide encore au moins 30 jours, ses droits effectifs sur `/pool/lab` sont ceux de `WBAutomation`, ni plus ni moins.
- [ ] Ton journal montre, pour chaque maillon testé, la commande et son résultat ; aucun secret n'y figure.

**Vérification** : `lab/bin/check 02 36`

<details><summary>Indice 1</summary>

`curl -H @fichier` lit un en-tête depuis un fichier (ou une substitution de processus) : le secret n'apparaît pas dans `ps`. `-w '%{http_code}'` donne le code HTTP, et le code de sortie de `curl` lui-même distingue une erreur TLS (60) d'une réponse HTTP.
</details>

<details><summary>Indice 2</summary>

`pveum user list`, `pveum user token list wb-automation@pve`, `pveum acl list`, puis `pveum user token permissions wb-automation@pve lab --path /pool/lab`. Rappel de M00-E17 : avec la séparation des privilèges, un droit doit exister **deux fois**.
</details>

<details><summary>Indice 3</summary>

Une erreur de vérification TLS alors que `pve01` n'a pas changé de certificat : compare l'autorité que **tu** présentes à `curl` (`PVE_CACERT`) avec celle de `pve01` (`/etc/pve/pve-root-ca.pem`) : sujet et clé publique. Souviens-toi de M02-E08 : ton ancre peut légitimement différer du fichier de `pve01` par ses extensions et son empreinte.
</details>

**Pour aller plus loin** (facultatif) : ajoute à `medictl config` une vérification de bout en bout (TLS, authentification, nombre de VMs visibles, date d'expiration du jeton) qui rend un code ≠ 0 au moindre maillon cassé. [API Proxmox VE](https://pve.proxmox.com/pve-docs/api-viewer/), [gestion des utilisateurs](https://pve.proxmox.com/wiki/User_Management).

---

### M02-E37 — Panne : le nettoyage a supprimé trop de choses  `BF` `★★★`

> **Ticket INC-2843** — *De : Julien Petit*
> Il manque des rapports ce matin dans `/opt/workbook/m02/e37/rapports` (zone de recette). Lucas y a lancé hier soir, pour la première fois « en vrai », son script de purge (`bin/ms-purge-rapports`, politique PLAT-384) : il dit qu'il n'a supprimé que les vieux rapports. Or des rapports récents ou sous conservation légale ont disparu. Rends-nous ce qui n'aurait jamais dû partir, et que ça ne se reproduise pas : ce script doit tourner chaque nuit sur la vraie racine.

**Objectifs pédagogiques**
- Établir **ce qui** a été supprimé, à partir d'une sauvegarde et d'une politique, avant de chercher **pourquoi**.
- Restaurer de façon sélective sans écraser ni réintroduire, en conservant les métadonnées (dates).
- Reconnaître les pièges classiques d'un script de suppression (variable vide, `cd` non vérifié, précédence de `find`, sens de `-mtime`) et écrire un script de purge défensif.

**Prérequis** : M02-E10, M02-E12 (fichiers en masse, `find -print0`), M02-E14 (bats), M02-E27 (`--dry-run`).
**Durée indicative** : 45 min (temps cible) pour le diagnostic et la restauration ; 1 h 30 de plus pour le script corrigé et ses tests.

**Injection** : `lab/bin/break 02 37` (4 variantes). Elle fabrique la zone de test `/opt/workbook/m02/e37/` (données **fictives**), la « sauvegarde de la nuit », le script de Lucas et sa configuration, puis le lance comme hier soir.

**Contexte technique**
- Zone de test : `rapports/` (racine purgeable, marquée par `.zone-de-test`), `hors-zone/` (témoin qui ne doit jamais être touché), `bin/ms-purge-rapports`, `etc/purge.conf`, `sauvegardes/rapports-<date>-0215.tar.gz` (faite **avant** la purge), `journal/` (sortie du passage d'hier soir), `attendu.tsv` (état attendu après une purge conforme : ne le modifie pas, la vérification s'en sert).
- Politique : [`ressources/M02-E37/politique-retention.md`](../ressources/M02-E37/politique-retention.md). Interface imposée du script corrigé : `ms-purge-rapports [-n|--dry-run] [-c FICHIER_CONF] [-h]`, codes 0/1/2/3, refus (3) d'une racine non marquée.
- Jeu de données neuf pour tes essais : [`ressources/M02-E37/fabriquer-donnees.sh`](../ressources/M02-E37/fabriquer-donnees.sh) `<DOSSIER>` (un dossier vide ou inexistant).

> ⚠️ **Attention** : ne relance **jamais** le script de Lucas, ni un correctif en cours de mise au point, sur la zone de recette : travaille sur une copie ou sur un jeu neuf. Avant toute restauration, mets de côté l'état actuel (`cp -a rapports rapports.avant-restauration`) : c'est ton retour arrière.

**Travail demandé**
1. **Le constat.** Sans toucher à la zone, établis la liste exacte de ce qui a disparu, en comparant la sauvegarde et l'état actuel, puis classe chaque fichier : devait partir selon la politique, ou non. Note les chiffres dans ton journal.
2. **La cause.** Lis le journal du passage d'hier et le script. Passe-le à ShellCheck : que trouve-t-il, que ne trouve-t-il pas ? Reproduis la suppression sur un jeu neuf, dans un dossier jetable, et explique ligne par ligne le mécanisme.
3. **La restauration.** Remets en place, depuis la sauvegarde, **uniquement** ce qui devait rester, avec contenu et dates d'origine. Ce que la politique supprime ne doit pas revenir. Note pourquoi les dates comptent pour la prochaine purge.
4. **Le script.** Corrige `bin/ms-purge-rapports` dans la zone (c'est lui que vérifie le contrôle), selon l'interface imposée. Il doit au minimum : valider sa configuration avant d'agir, refuser une racine non marquée, ne jamais rien supprimer hors de la racine ni dans `a-conserver/`, annoncer exactement ce qu'il ferait en `--dry-run`. Lance-le sur la zone restaurée : l'état final doit être celui de la politique.
5. **Le projet.** Versionne-le dans `plateforme/outils` (`bin/ms-purge-rapports`) avec des tests bats sur des données fabriquées, dont un test par variante de bogue que tu as rencontrée, et une MR.

**Critères de réussite**
- [ ] Tous les fichiers qui devaient rester sont présents, avec leur contenu d'origine ; plus aucun fichier que la politique supprime.
- [ ] Le script de la zone passe ShellCheck, produit exactement l'état de la politique sur un jeu neuf, et refuse (code ≠ 0, rien supprimé) une racine non marquée.
- [ ] Le script et ses tests sont fusionnés dans `main` ; ton journal contient le constat chiffré et le mécanisme de la panne.

**Vérification** : `lab/bin/check 02 37`

<details><summary>Indice 1</summary>

`tar -tzvf` liste le contenu d'une archive avec les dates ; `diff <(…) <(…)` compare deux listes triées. `attendu.tsv` te dit, pour chaque fichier, s'il doit rester (avec son empreinte) ou partir.
</details>

<details><summary>Indice 2</summary>

Extrais la sauvegarde **à côté** (`tar -C <dossier-temporaire> -xzf …`), applique-lui la politique avec un script correct, puis copie vers la zone ce qui y manque, sans écraser et en conservant les dates. Quel outil copie « seulement ce qui manque » ?
</details>

<details><summary>Indice 3</summary>

Pour `find`, un `-o` sans parenthèses ne s'applique pas à ce que tu crois ; `-mtime +30` et `-mtime -30` ne sont pas symétriques. En Bash, que vaut `"$RACINE/$x"` quand `x` n'a jamais été affectée, et que fait `rm -rf ./*` si le `cd` qui précède a échoué ?
</details>

**Pour aller plus loin** (facultatif) : un mode « corbeille » (déplacer vers un dossier daté, purgé plus tard) au lieu de supprimer ; `find -delete` vs `-print0 | xargs -0 rm` vs tableau Bash : effets sur les noms exotiques et sur `-depth`. [GNU findutils](https://www.gnu.org/software/findutils/manual/html_mono/find.html), [BashPitfalls](https://mywiki.wooledge.org/BashPitfalls).

---

### M02-E38 — Panne : rouge en CI, vert en local  `BF` `★★`

> **Ticket PLAT-380** — *De : Lucas Martin* (ou Karim Benali, selon le cas : le détail s'affiche à l'injection)
> Ma MR sur `plateforme/outils` est rouge en CI, mais chez moi tout passe, je l'ai lancé trois fois. C'est `runner01` qui doit avoir un problème ? J'aimerais la fusionner aujourd'hui.

**Objectifs pédagogiques**
- Lister méthodiquement ce qui diffère entre un poste et un runner : copie de travail propre, verrous de dépendances, configuration et secrets locaux, outils installés, variables CI (y compris héritées).
- Reproduire un job « comme la CI » sur son poste.
- Corriger la cause dans le dépôt ou la plateforme, sans désactiver le contrôle qui la révèle.

**Prérequis** : M02-E07 (uv, `uv.lock`), M02-E18 (tests sans Proxmox), M02-E20 (Taskfile), M02-E24 (CI du projet) ; dernier pipeline de `main` vert avant l'injection (`lab/bin/check 02 38`).
**Durée indicative** : 30 min (temps cible), plus l'attente des pipelines.

**Injection** : `lab/bin/break 02 38` (4 variantes). Selon la variante, l'injection ouvre une MR au nom de Lucas, ou modifie la configuration CI ; elle attend ensuite que le pipeline concerné échoue (jusqu'à 20 min).

**Travail demandé**
1. Ouvre le pipeline en échec : quel job, quelle tâche du Taskfile, quelle commande, quel message ? Note-le.
2. Reproduis sur `adm01` **comme Lucas** (ou comme toi au quotidien), puis **comme la CI** : clone propre de la branche dans un dossier temporaire, mêmes tâches que le job. Le résultat diffère-t-il ? Qu'est-ce que cela élimine ?
3. Pour chaque différence possible entre `adm01` et `runner01` (au moins cinq), donne la commande qui la met en évidence, puis trouve celle qui joue ici. Si rien ne diffère entre ton clone propre et la CI, regarde ce que le runner **reçoit** en plus du dépôt.
4. Corrige à la racine, dans le dépôt de Lucas ou dans la plateforme : jamais en ajoutant `allow_failure`, en sautant un test ou en retirant un job. Si la MR n'a pas lieu d'être sous cette forme, explique-le à Lucas en commentaire et ferme-la.
5. Propose une mesure qui aurait fait échouer le problème **sur le poste de Lucas**, avant le push.

**Critères de réussite**
- [ ] Le dernier pipeline de `main` est vert ; aucune MR ouverte de `plateforme/outils` n'a un pipeline en échec.
- [ ] Aucune variable CI (projet ou groupe) ne modifie le comportement des outils de lint ; `uv.lock` est à jour dans ton clone ; `runner01` dispose des outils du pipeline.
- [ ] Ton journal contient la liste des différences poste/runner avec leurs commandes, la cause, et la mesure préventive (en commentaire de la MR si elle concerne Lucas).

**Vérification** : `lab/bin/check 02 38`

<details><summary>Indice 1</summary>

`git clone --branch <BRANCHE> <URL> "$(mktemp -d)"` puis `task ci` : c'est ce que fait le runner, à l'environnement près. Une commande qui passe dans ta copie de travail et échoue dans un clone propre dépend de quelque chose qui n'est pas dans le dépôt.
</details>

<details><summary>Indice 2</summary>

Trois commandes « qui marchent » mais ne font pas la même chose : `uv run pytest`, `uv run --locked pytest`, `task test:py`. Et deux sources d'outils : le `PATH` de `admin` sur `adm01`, celui de `gitlab-runner` sur `runner01`.
</details>

<details><summary>Indice 3</summary>

Les variables CI d'un projet ne sont pas toutes définies dans le projet : la page *Paramètres → CI/CD → Variables* montre aussi celles héritées du groupe. Beaucoup d'outils lisent des options dans l'environnement : `man shellcheck`, section *ENVIRONMENT*.
</details>

**Pour aller plus loin** (facultatif) : un job de diagnostic manuel (`when: manual`) qui affiche les versions des outils et la liste des **noms** de variables présentes (jamais leurs valeurs) ; pourquoi `CI_DEBUG_TRACE` est dangereux sur un projet qui a des variables protégées. [Variables CI/CD](https://docs.gitlab.com/ci/variables/), [uv : verrouillage](https://docs.astral.sh/uv/concepts/projects/sync/).

---

### M02-E39 — Panne : `set -e` ne fait pas ce qu'on croit  `BF` `★★★`

> **Ticket INC-2844** — *De : Sophie Laurent (RSSI)*
> La tâche d'archivage des journaux de cette nuit (`/opt/workbook/m02/e39`, journal dans `journal/`) s'est terminée en succès, code retour 0. Pourtant l'archive de `dns01` ne contient pas tous les journaux collectés, et le spool de `dns01` est vide : des journaux ont disparu. Pour un hébergeur HDS, perdre une trace est un incident de sécurité. Lucas m'assure que son script est en « mode strict » et s'arrête à la moindre erreur. Je veux comprendre comment c'est possible, récupérer les journaux, et un script dont l'échec ne passe plus inaperçu.

**Objectifs pédagogiques**
- Connaître précisément les contextes où Bash ignore `set -e` (conditions, listes `&&`/`||`, tubes sans `pipefail`, substitutions de commande, `local x=$(…)`), et ceux que ShellCheck signale ou non.
- Écrire un script dont le contrat (« un fichier ne quitte le spool que s'il est dans une archive vérifiée ») est vérifié explicitement, au lieu de compter sur `set -e`.
- Récupérer des données depuis une sauvegarde faite avec d'autres droits.

**Prérequis** : M02-E03 (mode strict), M02-E10, M02-E14 ; M02-E44 conseillé ensuite.
**Durée indicative** : 45 min (temps cible), puis 1 h pour le script et ses tests.

**Injection** : `lab/bin/break 02 39` (4 variantes). Elle fabrique la zone `/opt/workbook/m02/e39/` : un spool de journaux **fictifs** de `gw01`, `dns01` et `git01`, le script de Lucas (`bin/ms-archiver-journaux`), une sauvegarde du spool faite par root à 01:00 (`sauvegardes/`), puis lance l'archivage « de 02:00 » en `admin`.

**Contexte technique**
- Interface imposée du script corrigé : `ms-archiver-journaux [-s SPOOL] [-a ARCHIVES] [-h]` (défauts `../spool` et `../archives` relatifs au script), une archive `<hôte>-<horodatage>.tar.gz` par hôte, codes 0 (tout archivé), 1 (au moins un hôte en erreur), 2 (usage), 3 (spool non marqué `.zone-de-test`). Un hôte en erreur n'empêche pas de traiter les autres.
- Spool neuf pour tes essais : [`ressources/M02-E39/fabriquer-spool.sh`](../ressources/M02-E39/fabriquer-spool.sh) `[--sain] <DOSSIER>`.

**Travail demandé**
1. Constate : ce que dit le journal de l'archivage, ce que contient chaque archive, ce qui reste dans le spool. Qu'est-ce qui, dans le journal, aurait dû arrêter le script ?
2. Explique pourquoi le script a continué, en citant la règle exacte du manuel de Bash (section sur `set -e`). Démontre-la par un script minimal de cinq lignes, sans `tar`.
3. Lance ShellCheck sur le script, puis avec les vérifications optionnelles qui concernent `set -e` (`shellcheck --list-optional`). Que détecte-t-il, que ne détecte-t-il pas ?
4. Récupère les journaux perdus depuis la sauvegarde, sans écraser ce qui a été archivé correctement. Pourquoi un de ces fichiers pose-t-il problème à `admin`, et que faut-il signaler à l'équipe qui gère l'agent de collecte ?
5. Corrige le script selon l'interface imposée : chaque étape critique vérifiée explicitement, l'archive comparée à la liste des fichiers prévus, seuls les fichiers archivés retirés du spool. Archive les journaux récupérés avec lui.
6. Versionne le script dans `plateforme/outils` avec des tests bats (fichier illisible, spool sain, hôte en erreur au milieu), et ajoute à `.shellcheckrc` du projet la vérification optionnelle que tu juges utile, en justifiant ton choix dans la MR.

**Critères de réussite**
- [ ] Chaque journal du spool fabriqué à l'injection est soit encore dans le spool, soit dans une archive lisible de son hôte.
- [ ] Sur un spool contenant un fichier illisible, le script de la zone rend un code ≠ 0, ne vide pas le spool de l'hôte en erreur et archive quand même les autres ; sur un spool sain, il rend 0 et archive tout.
- [ ] Le script passe ShellCheck ; ton journal contient la règle du manuel, le script minimal de démonstration et le résultat de ShellCheck.

**Vérification** : `lab/bin/check 02 39`

<details><summary>Indice 1</summary>

Le code de retour de `tar` dans le journal (« Exiting with failure status due to previous errors ») et le message « Terminé » ne peuvent pas être vrais tous les deux… sauf si quelque chose a avalé ce code. Cherche **où** est appelé `tar`, puis **d'où** est appelée la fonction qui l'appelle.
</details>

<details><summary>Indice 2</summary>

Dans le manuel de Bash, l'entrée `-e` de la commande interne `set` contient une phrase qui commence par « If a compound command or shell function executes in a context where -e is being ignored… ». Lis aussi l'entrée `inherit_errexit` de `shopt` et la description de `local`.
</details>

<details><summary>Indice 3</summary>

`tar -tzf` liste une archive. Comparer cette liste à celle des fichiers que tu voulais archiver est une vérification qui ne dépend d'aucune option du shell.
</details>

**Pour aller plus loin** (facultatif) : `trap 'log_err "ligne $LINENO : $BASH_COMMAND"' ERR` avec `set -E` : quand le piège se déclenche-t-il, et quand ne se déclenche-t-il pas (les mêmes contextes) ? [Manuel de Bash : The Set Builtin](https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html), [BashFAQ/105](https://mywiki.wooledge.org/BashFAQ/105).

---

### M02-E40 — Panne : l'inventaire met dix minutes  `BF` `★★★`

> **Ticket PLAT-381** — *De : Karim Benali*
> Lucas a repris le script d'inventaire d'InfoGér : `/opt/workbook/m02/e40/bin/ms-inventaire-lab`. Le résultat est juste, mais il met une dizaine de minutes pour une dizaine de VMs. Je veux le lancer avant chaque intervention et pendant les astreintes : il doit tenir en moins de 30 s. Mesure d'abord où passe le temps (pas d'optimisation à l'aveugle), corrige, et montre-moi les chiffres avant/après.

**Objectifs pédagogiques**
- Mesurer avant d'optimiser : temps total, nombre d'appels, coût unitaire de chaque appel, attentes.
- Reconnaître les causes classiques de lenteur d'un script d'API : appels inutiles, reprises sur des erreurs définitives, coût de démarrage des processus, délais d'attente réseau.
- Corriger sans changer le résultat.

**Prérequis** : M02-E05 (API et jq), M02-E17 (reprises : quelles erreurs reprendre ?), M02-E21 (inventaire), M02-E28.
**Durée indicative** : 45 min (temps cible).

**Injection** : `lab/bin/break 02 40` (4 variantes). Elle dépose la zone `/opt/workbook/m02/e40/` (`bin/ms-inventaire-lab`, `etc/inventaire.conf`, `sortie/`). Le script lit l'API en lecture seule ; il ne modifie rien.

**Contexte technique**
- Interface du script (à conserver) : `ms-inventaire-lab [-o FICHIER|-]` ; `-o -` écrit sur la sortie standard. Résultat attendu : un tableau Markdown dont chaque ligne de VM commence par `| <VMID> |`, une ligne par VM du pool `lab`.
- Bash 5 fournit `EPOCHREALTIME` (secondes avec microsecondes) ; `PS4` est le préfixe des lignes de `bash -x`.

**Travail demandé**
1. **Mesure de départ.** Chronomètre une exécution complète (laisse-la finir une fois). Note le nombre de VMs du pool.
2. **Profil.** Trouve où passe le temps, par la mesure : traces horodatées (`PS4` + `bash -x`), nombre d'appels par type, coût unitaire d'un appel représentatif, appels qui échouent. Sur `pve01`, le journal d'accès de l'API (`/var/log/pveproxy/access.log`) montre ce que le script demande réellement. Établis un tableau « poste de dépense → nombre × coût unitaire = total » qui explique au moins 80 % du temps mesuré.
3. **Correction.** Corrige la ou les causes en gardant le même résultat (mêmes VMs, colonnes utiles conservées ou retirées avec une justification). Ne touche à rien côté Proxmox.
4. **Mesure finale.** Refais la mesure de l'étape 1. Note le gain, et le nouveau profil (où passe le temps maintenant ?).
5. **Leçon.** Écris dans ton journal la règle générale que cette variante illustre, et ajoute-la à la grille de revue des scripts de l'équipe (`CONTRIBUTING.md` de `plateforme/outils`).

**Critères de réussite**
- [ ] `bin/ms-inventaire-lab -o -` se termine sans erreur en moins de 30 s et liste toutes les VMs du pool `lab`.
- [ ] Le script passe ShellCheck.
- [ ] Ton journal contient le tableau de profil (avant), les mesures avant/après et la règle générale ; la grille de revue est complétée par MR.

**Vérification** : `lab/bin/check 02 40`

<details><summary>Indice 1</summary>

`PS4='+ ${EPOCHREALTIME} '` puis `bash -x bin/ms-inventaire-lab -o /dev/null 2> trace.txt` : chaque commande exécutée est horodatée. `grep -c` sur la trace compte les appels ; la différence entre deux horodatages consécutifs donne le coût d'une commande.
</details>

<details><summary>Indice 2</summary>

Mesure **un** appel isolé de chaque type (`time curl …`, `time ssh pve01 true`, `time dig …`) et compare au nombre d'appels. Pour un appel qui échoue, regarde son code HTTP et sa durée : que fait le script ensuite ?
</details>

<details><summary>Indice 3</summary>

Une seule requête de l'API renvoie déjà nom, état, vCPU, mémoire, pool et étiquettes de **toutes** les VMs. Une erreur 403 ou « VM not running » n'a aucune chance de réussir à la deuxième tentative.
</details>

**Pour aller plus loin** (facultatif) : paralléliser les appels à l'agent QEMU (M02-E28) et mesurer le gain réel sur un pool de 10 VMs ; `hyperfine` pour des mesures répétées avec écart type.

---

### M02-E41 — Panne : le contrôle planifié ne tourne plus  `BF` `★★`

> **Ticket INC-2845** — *De : Nadia Roussel*
> Je viens de m'en rendre compte : je n'ai plus aucune trace du contrôle quotidien des sauvegardes (07:30 sur `adm01`) depuis plusieurs jours. Pas d'échec, pas de notification, rien : il ne tourne plus, tout simplement. Un contrôle silencieux, c'est pire que pas de contrôle. Remets-le en route, et dis-moi comment on aurait pu s'en apercevoir plus tôt.

**Objectifs pédagogiques**
- Diagnostiquer un timer systemd : chargement, activation, état, prochaine échéance, conditions du service déclenché.
- Distinguer « a échoué », « n'a pas été déclenché » et « a été sauté ».
- Concevoir une surveillance de l'**absence** d'exécution (chien de garde, *dead man's switch*).

**Prérequis** : M00-E30 (timers), M02-E26 ; `lab/bin/check 02 41` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Injection** : `lab/bin/break 02 41` (4 variantes).

**Travail demandé**
1. Établis l'état du timer et du service : chargé ? actif ? activé ? prochaine échéance ? dernier déclenchement ? dernier passage du service et son résultat ? Note chaque valeur avec sa commande.
2. Trouve la cause et sa provenance (quel fichier, posé quand, par quelle action). Si une expression de planification est en cause, teste-la avec l'outil prévu par systemd avant de la corriger.
3. Corrige, puis prouve que le timer se déclenchera bien demain à 07:30 et que le service s'exécute réellement (pas seulement « réussi »).
4. Explique pourquoi aucune des alertes en place (`OnFailure=`, notifications PBS) ne pouvait signaler cette panne.
5. **Détection.** Mets en place un chien de garde qui alerte si le contrôle n'a pas réussi depuis plus de 26 h, quelle que soit la raison (au minimum un script et sa planification, versionnés dans `plateforme/outils`, alerte par `ms-alerte@`). Dans ton journal, indique ce que ton chien de garde ne verra pas, et ce qu'il faudrait pour le voir.

**Critères de réussite**
- [ ] Le timer est chargé sans erreur, actif, activé au démarrage, planifié chaque jour à 07:30, prochaine échéance dans moins de 25 h.
- [ ] Le dernier passage du service a été réellement exécuté (pas sauté), a réussi, il y a moins de 26 h.
- [ ] Le chien de garde est versionné, installé et planifié ; ses limites sont écrites dans ton journal.

**Vérification** : `lab/bin/check 02 41`

<details><summary>Indice 1</summary>

`systemctl list-timers --all`, `systemctl status` (du timer **et** du service), `systemctl cat`, et le journal de **l'unité timer** (`journalctl -u ms-verif-sauvegardes.timer`), qui n'est pas celui du service.
</details>

<details><summary>Indice 2</summary>

`systemd-analyze calendar '<expression>'` affiche la forme normalisée d'une expression et ses prochaines échéances, ou une erreur. Une ligne `Condition:` dans `systemctl status` du service explique pourquoi il n'a pas tourné.
</details>

<details><summary>Indice 3</summary>

Un contrôle qui ne tourne pas ne peut rien signaler. Il faut un **autre** observateur, qui juge la fraîcheur du dernier succès (`systemctl show -p ExecMainExitTimestamp,Result,ConditionResult`). Où le faire tourner pour qu'il voie aussi l'arrêt complet de `adm01` ?
</details>

**Pour aller plus loin** (facultatif) : exposer « horodatage du dernier succès » comme métrique (collecteur *textfile* de node_exporter) et alerter sur son âge (module 21) ; services de type *heartbeat* (le contrôle « pousse » un signe de vie). [systemd.timer](https://www.freedesktop.org/software/systemd/man/latest/systemd.timer.html), [systemd.time](https://www.freedesktop.org/software/systemd/man/latest/systemd.time.html), [systemd.unit, section Conditions](https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html).

---

### M02-E42 — Panne : l'environnement Python est cassé  `BF` `★★`

> **Ticket INC-2846** — *De : Karim Benali*
> Depuis le « ménage » fait hier par Lucas sur `adm01`, l'outillage Python est en vrac : selon le cas, `medictl` ne marche plus, ou les tests du projet plantent (le détail s'affiche à l'injection). Personne n'a touché au code ni à la release. Ne réinstalle pas tout à l'aveugle : je veux savoir ce qui a été cassé, pour que ça ne se reproduise pas sur les autres postes.

**Objectifs pédagogiques**
- Savoir quel programme et quel interpréteur sont réellement exécutés (`PATH`, lanceurs, shebang, liens).
- Comprendre comment Python construit `sys.path` (environnement virtuel, site utilisateur, fichiers `.pth`) et comment uv gère les environnements d'outils et de projet.
- Réparer de façon ciblée et reproductible, en sachant ce qui est jetable (`.venv`) et ce qui ne l'est pas.

**Prérequis** : M02-E07 (uv, `.venv`), M02-E25 (`uv tool install` depuis le registre) ; `lab/bin/check 02 42` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Injection** : `lab/bin/break 02 42` (4 variantes).

**Travail demandé**
1. Reproduis le symptôme et note le message exact. Avant toute hypothèse : **quel** fichier est exécuté, avec **quel** interpréteur ? Remonte toute la chaîne (commande → lanceur → shebang → interpréteur → paquet importé).
2. Pour le projet, compare ce que les **métadonnées** de l'environnement annoncent (`uv pip list`, `uv pip show`) avec ce que Python **importe** réellement (`__file__`, `sys.path`).
3. Trouve ce qui a été modifié et quand. Écris dans ton journal le mécanisme précis (pas « l'environnement était cassé »).
4. Répare de la façon la plus ciblée possible, puis vérifie que `medictl`, `uv run medictl --version` et la suite de tests fonctionnent. Si tu supprimes quelque chose, archive-le d'abord.
5. Rédige trois règles d'hygiène des environnements Python pour le `CONTRIBUTING.md` de `plateforme/outils`, chacune reliée à une variante que tu as rencontrée.

**Critères de réussite**
- [ ] `medictl` appelé dans ton shell est celui installé par `uv tool`, à la version que `uv tool list` annonce ; aucun autre paquet `medictl` n'est visible de l'interpréteur système.
- [ ] Dans `~/src/outils`, l'environnement importe ses dépendances et le code du projet (`src/`) sans resynchronisation ; aucun `.pth` n'y ajoute de chemin étranger ; la suite pytest passe.
- [ ] Ton journal contient la chaîne d'exécution remontée et le mécanisme ; les règles d'hygiène sont proposées par MR.

**Vérification** : `lab/bin/check 02 42`

<details><summary>Indice 1</summary>

`type -a medictl`, `ls -l "$(command -v medictl)"`, `head -n 1` du lanceur, `readlink -f`. Puis `uv tool list` et `uv tool dir` : ce que uv **croit** avoir installé.
</details>

<details><summary>Indice 2</summary>

`python -c 'import sys; print(sys.path)'` dans l'environnement, `python -m site`, et la liste des fichiers `*.pth` de `site-packages`. Un paquet « installé » d'après ses métadonnées (`*.dist-info`) n'est pas forcément importable.
</details>

<details><summary>Indice 3</summary>

Debian 13 refuse `pip install` dans le Python du système (PEP 668, fichier `EXTERNALLY-MANAGED`) : qui l'a contourné, et avec quelle option au nom explicite ? Les interpréteurs gérés par uv vivent dans un dossier que `uv python dir` indique.
</details>

**Pour aller plus loin** (facultatif) : `python -I` (mode isolé) et `PYTHONSAFEPATH` ; installer les outils uv avec `python-preference = "only-system"` dans `~/.config/uv/uv.toml` et mesurer ce que cela change à la variante qui t'a le plus coûté. [Module site](https://docs.python.org/3/library/site.html), [uv : outils](https://docs.astral.sh/uv/concepts/tools/), [PEP 668](https://peps.python.org/pep-0668/).

---

### M02-E43 — Astreinte : l'outillage en panne  `BF` `★★★★`

> **Ticket INC-2850** — *De : Nadia Roussel (responsable astreinte)* — priorité P2
> Tu es d'astreinte. Lundi matin, plusieurs remontées sur l'outillage de l'équipe (le détail s'affiche à l'injection). Je ne sais pas si c'est lié. Rétablis l'outillage, tiens-moi informée toutes les 30 minutes (un message court dans #astreinte suffit), puis rédige le post-mortem avec le modèle de l'équipe.

**Objectifs pédagogiques**
- Gérer un incident à causes multiples : trier, prioriser, éviter qu'une panne en masque une autre.
- Choisir l'ordre de traitement selon les dépendances entre outils (un outil de diagnostic cassé fausse les autres tests).
- Communiquer pendant l'incident et rédiger un post-mortem sans recherche de coupable.

**Prérequis** : M02-E35 à M02-E42 (au moins une variante de chacun) ; M00-E46 (méthode d'astreinte et modèle de post-mortem).
**Durée indicative** : 2 h de rétablissement + 45 min de post-mortem.

**Contexte technique** : le script tire **deux** pannes distinctes parmi celles de M02-E35 à M02-E42 (variantes aléatoires) et les injecte ensemble ; l'injection peut prendre quelques minutes. Les symptômes peuvent se recouvrir. `--variante N` (1 à 28) force la paire, pas les variantes. `--annuler` retire les deux. Modèle de post-mortem : [`modules/00-lab/ressources/M00-E46/modele-post-mortem.md`](../../00-lab/ressources/M00-E46/modele-post-mortem.md).

**Injection** : `lab/bin/break 02 43`

**Travail demandé**
1. **Triage (10 min max)** : liste les symptômes, leur impact (qui est bloqué, quel risque pour les sauvegardes ou les interventions du jour), une première hypothèse de regroupement, et les contrôles `lab/bin/check 02 35` à `02 42` en rouge. Envoie la première communication.
2. **Diagnostic** : traite les pannes dans l'ordre que tu justifies. Commence par ce qui conditionne tes instruments (accès à l'API, `medictl`, environnement Python).
3. **Rétablissement** : corrige chaque cause racine ; après chaque correction, relance **tous** les tests du triage.
4. **Clôture** : communication de fin, post-mortem dans `docs/socle/post-mortems/AAAA-MM-JJ-INC-2850.md` de `~/medisphere`, commité et publié par MR.

**Critères de réussite**
- [ ] Toutes les vérifications de M02-E35 à M02-E42 sont vertes (le contrôle les rejoue) ; aucune panne `M02` n'est encore marquée active.
- [ ] Le post-mortem contient une chronologie horodatée, les deux causes racines prouvées, l'analyse de la détection et des actions avec responsable et échéance ; il est commité.
- [ ] Ton journal contient au moins trois communications espacées d'environ 30 minutes.

**Vérification** : `lab/bin/check 02 43`

<details><summary>Indice 1</summary>

Deux pannes peuvent toucher le **même** outil (le contrôle des sauvegardes, `medictl`) pour des raisons différentes. Quand une correction ne fait pas disparaître le symptôme, ne l'annule pas : le message a-t-il changé ?
</details>

<details><summary>Indice 2</summary>

Les contrôles `lab/bin/check 02 35` à `02 42` sont des sondes de triage. Certains prennent du temps (E40 mesure une exécution, E42 lance pytest) : lance-les en tâche de fond pendant que tu lis les journaux.
</details>

**Pour aller plus loin** (facultatif) : fais-toi injecter une astreinte par quelqu'un d'autre (`--variante` tirée par lui), sans regarder l'écran pendant l'injection, et chronomètre ton temps de rétablissement.

---

### M02-E44 — Sous le capot : expansions, sous-shells et descripteurs  `LAB` `★★★`

> **Ticket PLAT-385** — *De : Karim Benali*
> Après la panne de l'archivage (`set -e`), j'ai relu nos MR du trimestre : la moitié des commentaires de revue sur nos scripts Bash commencent par « je crois que… ». Je veux qu'on arrête de croire. Écris-nous une **spécification exécutable** de Bash : chaque comportement dont nos outils dépendent, prouvé par un test, plus une note qui l'explique. Elle tournera en CI : le jour où une montée de version de Bash change quelque chose, on le saura.

**Objectifs pédagogiques**
- Connaître l'ordre des expansions de Bash et en déduire le comportement d'une ligne sans l'exécuter.
- Savoir ce qui crée un sous-shell et ce qui n'y survit pas.
- Manipuler les descripteurs de fichiers (ordre des redirections, `{fd}`, héritage par les enfants) et en voir les conséquences sur les verrous et les fichiers temporaires.
- Transformer une connaissance en test automatisé (bats).

**Prérequis** : M02-E03, M02-E12, M02-E13 (verrous, `lock_or_die`), M02-E14 (bats), M02-E39.
**Durée indicative** : 3 h.

**Contexte technique**
- Livrables dans `plateforme/outils` : `tests/bats/sous-le-capot.bats` (au moins 10 tests) et `docs/analyses/sous-le-capot-bash.md` (avec une section `## Réponses aux questions`, une réponse numérotée par question). La tâche `test:bats` du Taskfile les exécute déjà en CI.
- Chaque test doit exécuter le code étudié dans un `bash` neuf (`bash --norc --noprofile -c '…'`), pour que ni les options de bats ni ton environnement ne faussent le résultat, et ne doit écrire que dans `$BATS_TEST_TMPDIR`.

**Travail demandé**
1. **Expansions.** Prédis **par écrit** la sortie de chaque ligne, puis exécute-la et compare :
   ```
   admin@adm01:~$ n=3; echo {1..$n}; a='{1,2}'; echo $a
   admin@adm01:~$ v='~'; echo $v ~
   admin@adm01:~$ f() { echo $#; }; vide=; f $vide; f "$vide"; set -- 'un deux' trois; f "$@"; f "$*"; f $@
   admin@adm01:~$ cd "$(mktemp -d)"; touch a.log b.log; x='*.log'; echo $x "$x"; echo *.absent
   admin@adm01:~$ x="$(printf 'a\n\n\n')"; printf '[%s]\n' "$x"
   ```
2. **Sous-shells.** Même démarche :
   ```
   admin@adm01:~$ n=0; printf '1\n2\n' | while read -r l; do n=$((n + l)); done; echo $n
   admin@adm01:~$ echo "$$ $BASHPID $BASH_SUBSHELL"; ( echo "$$ $BASHPID $BASH_SUBSHELL" )
   admin@adm01:~$ ( cd /; exit 7 ); echo "$? $PWD"
   ```
   Puis donne deux façons de récupérer `n` dans le premier exemple, et vérifie dans un **script** (pas dans ton terminal) celle qui dépend d'une option du shell. Pourquoi ce détail ?
3. **Descripteurs.** Même démarche :
   ```
   admin@adm01:~$ f() { echo out; echo err >&2; }; f 2>&1 >un.txt; f >deux.txt 2>&1; cat un.txt deux.txt
   admin@adm01:~$ exec {fd}>trace.txt; echo "$fd"; ls -l /proc/$$/fd; exec {fd}>&-
   admin@adm01:~$ echo <(true); wc -c <<<abc
   ```
   Puis l'expérience du **verrou hérité** : un petit script prend un verrou `flock` sur un descripteur ouvert par `exec`, lance `sleep 300 &` et se termine. Le verrou est-il libre ? Qui le tient (`fuser -v`, `ls -l /proc/<PID>/fd`) ? Corrige le script pour que le verrou meure avec lui. Relis `lock_or_die` de la bibliothèque : `ms-snapshot` ou un autre outil lance-t-il un processus en arrière-plan pendant qu'il tient son verrou ?
4. **Spécification exécutable.** Écris `tests/bats/sous-le-capot.bats` : au moins 10 tests, un comportement par test, dont au moins trois sur les expansions, trois sur les sous-shells et trois sur les descripteurs. Le nom de chaque test énonce le comportement (« sous-shell : … »).
5. **Analyse.** Rédige `docs/analyses/sous-le-capot-bash.md` : un tableau « motif repéré en revue → risque → écrire plutôt », puis la section `## Réponses aux questions` ci-dessous, chaque réponse renvoyant au test qui la prouve.
6. **Audit.** Cherche dans `bin/` et `lib/` du projet les motifs de ton tableau (un `grep` par motif, noté dans l'analyse) ; corrige ou justifie chaque occurrence dans la même MR.

**Questions** (à traiter dans l'analyse)
1. Donne l'ordre des expansions de Bash. Explique avec lui pourquoi `echo {1..$n}` n'affiche pas une suite, et pourquoi `v='~'; ls $v` ne liste pas ton dossier personnel.
2. Combien d'arguments une fonction reçoit-elle avec `$vide`, `"$vide"`, `"$@"`, `"$*"` et `$@` (arguments contenant des espaces) ? Quelle forme pour transmettre des arguments, et pourquoi ?
3. Quand le développement des chemins a-t-il lieu par rapport au contenu des variables ? Que se passe-t-il sans correspondance, avec et sans `nullglob`, et pourquoi `nullglob` peut-il changer le sens d'une commande ?
4. Pourquoi `x=$(cat f)` ne restitue-t-il pas toujours le contenu exact de `f` ? Conséquence pour un script qui réécrit un fichier ou calcule une empreinte ; parade.
5. Pourquoi le compteur reste-t-il à 0 dans `cmd | while read …` ? Deux corrections, et la limite de chacune.
6. Que valent `$$`, `$BASHPID` et `BASH_SUBSHELL` dans un sous-shell ? Lequel utiliser pour un fichier propre à un processus fils, et pourquoi `mktemp` reste préférable ?
7. Quelles constructions créent un sous-shell ? Qu'est-ce qui n'y survit pas ?
8. Explique, descripteur par descripteur, `cmd 2>&1 >f` et `cmd >f 2>&1`. Que fait `exec 3>&1 1>&2 2>&3 3>&-` ?
9. Pourquoi `exec {fd}>fichier` choisit-il un numéro ≥ 10 ? Explique l'expérience du verrou hérité et son lien avec `lock_or_die` (E13).
10. Qu'est-ce que `/dev/fd/63` dans `diff <(a) <(b)` ? Comment récupérer le code retour d'une substitution de processus ?
11. Rôle de `-r`, de `IFS=` et de `-d ''` pour `read`. Pourquoi la dernière ligne d'un fichier sans saut de ligne final est-elle perdue par `while read`, et comment l'éviter ?
12. Pourquoi la fonction `retry` de la bibliothèque préfixe-t-elle ses variables locales par `_ms_` ? Donne un exemple de bogue évité.
13. Différences de sémantique et de sécurité entre `[[ $a == $b ]]`, `[[ $a == "$b" ]]` et `[ $a = $b ]`.
14. Quand lire `PIPESTATUS`, et qu'apporte-t-il par rapport à `pipefail` ?

**Critères de réussite**
- [ ] `tests/bats/sous-le-capot.bats` contient au moins 10 tests, qui passent en local et dans le dernier pipeline de `main`.
- [ ] `docs/analyses/sous-le-capot-bash.md` contient le tableau de revue et la section `## Réponses aux questions` avec au moins 10 réponses numérotées.
- [ ] Les deux fichiers sont versionnés dans `plateforme/outils` ; l'audit et ses suites sont dans la MR.

**Vérification** : `lab/bin/check 02 44`

<details><summary>Indice 1</summary>

Dans bats, `run -0 bash --norc --noprofile -c '<code>' bash <args…>` exécute le code, vérifie le code retour et remplit `$output` et `${lines[@]}`. `--separate-stderr` sépare la sortie d'erreur dans `$stderr` (bats ≥ 1.5, d'où `bats_require_minimum_version 1.5.0`).
</details>

<details><summary>Indice 2</summary>

Pour le verrou hérité : `flock -n <fichier> true` rend 1 si quelqu'un tient le verrou. Une redirection placée sur une commande lancée en arrière-plan (`cmd {fd}>&- &`) ne concerne que cette commande. Un test qui lance un processus en arrière-plan doit le tuer même s'il échoue (`teardown`).
</details>

**Pour aller plus loin** (facultatif) : ajoute des tests sur `trap … EXIT` dans un sous-shell, `wait -n` et les codes de sortie (M02-E28), `coproc` ; fais tourner la spécification avec `bash --posix` et note ce qui change. [Manuel de Bash](https://www.gnu.org/software/bash/manual/bash.html) (sections *Shell Expansions*, *Redirections*, *Command Execution Environment*), [BashFAQ](https://mywiki.wooledge.org/BashFAQ).

---

### M02-E45 — Questions expert : shell et Python  `Q` `★★★`

> **Ticket PLAT-386** — *De : Karim Benali*
> Dernière étape avant la recette de l'outillage : ces questions, je les pose en entretien pour un poste d'ingénieur plateforme senior. Réponds par écrit, en argumentant. Pas de recherche pendant la première passe ; vérifie ensuite dans la doc et corrige-toi en couleur.

**Objectifs pédagogiques**
- Consolider la compréhension des mécanismes internes du shell, de Python et de leurs environnements d'exécution.
- S'entraîner à argumenter une réponse technique comme en entretien ou en revue de code.

**Prérequis** : paliers 1 à 3 du module, M02-E39, M02-E42, M02-E44.
**Durée indicative** : 2 h 30.

**Questions**

1. QCM — `set -euo pipefail` est actif. Lesquelles de ces lignes **arrêtent** le script quand `f` (une fonction dont la première commande échoue) est appelée ?
   a) `f` ; b) `if f; then …; fi` ; c) `f || echo raté` ; d) `x=$(f)` ; e) `local y; y=$(f)` dans une fonction ; f) `echo "$(f)"`.
   Pour chaque cas, dis aussi si le **reste du corps** de `f` s'exécute.
2. `trap 'echo "ligne $LINENO"' ERR` ne se déclenche jamais dans les fonctions d'un script. Pourquoi, et quelle option corrige ? Dans quels contextes le piège `ERR` reste-t-il muet, et pourquoi sont-ce les mêmes que pour `set -e` ?
3. Un script lancé par systemd fait `exec /usr/local/bin/ms-verif-sauvegardes "$@"` à la fin, au lieu d'un simple appel. Qu'est-ce que `exec` change pour le PID, les signaux reçus à l'arrêt du service, le code de sortie et les `trap` du script appelant ?
4. QCM — Dans `while read -r h; do ssh "$h" uptime; done < hotes.txt`, seule la première ligne est traitée. Pourquoi ?
   a) `read` sans `IFS=` s'arrête à la première espace ; b) `ssh` lit l'entrée standard et consomme le reste du fichier ; c) `ssh` renvoie 255, ce qui sort de la boucle ; d) le fichier n'a pas de saut de ligne final.
   Donne deux corrections.
5. Pourquoi `printf '%s\n' "$var"` est-il préféré à `echo "$var"` dans un script ? Cite deux valeurs de `var` qui font diverger les deux.
6. Un script Bash tourne en root et écrit dans `/tmp/ms-diag.$$`. Décris l'attaque possible et sa parade. Qu'apporte en plus `PrivateTmp=yes` pour un service ?
7. QCM — En Python, `subprocess.run(["tar", "-czf", archive, dossier])` sans autre argument. Que se passe-t-il si `tar` échoue ?
   a) une exception `CalledProcessError` est levée ; b) rien : il faut tester `returncode` ou passer `check=True` ; c) Python affiche un avertissement ; d) `tar` est relancé.
   Et avec `shell=True` et une chaîne construite par f-string : quel risque ?
8. `requests.get(url)` sans `timeout=` dans un outil planifié. Que se passe-t-il si `pve01` accepte la connexion TCP mais ne répond jamais ? Quelles sont les deux valeurs d'un `timeout` de requests, et que ne couvre aucune des deux ?
9. Par quels moyens `requests` (et donc `proxmoxer`) peut-il se retrouver à vérifier TLS contre un autre magasin de certificats que celui que tu crois (variables d'environnement, paramètre `verify`, `certifi`) ? Pourquoi `medictl` passe-t-il explicitement `PVE_CACERT` ?
10. QCM — Une variable d'environnement `https_proxy` est définie, et `no_proxy=.medisphere.internal`. `medictl` appelle `https://10.10.10.x:8006/…` (adresse IP). La requête :
    a) passe en direct, car le domaine interne est exempté ; b) passe par le proxy, car l'adresse IP ne correspond à aucune entrée de `no_proxy` ; c) échoue, car `no_proxy` doit contenir des adresses ; d) dépend de la présence de `HTTPS_PROXY` en majuscules.
11. Explique comment Python construit `sys.path` dans un environnement virtuel créé par uv : rôle de `pyvenv.cfg`, de `site-packages`, des fichiers `.pth` (deux usages : chemins et lignes `import`), du site utilisateur. Pourquoi un `.pth` est-il un vecteur d'attaque ?
12. Que contient un lanceur installé dans `~/.local/bin` par `uv tool install`, et que se passe-t-il pour lui si l'interpréteur de son environnement disparaît ? Pourquoi les outils de l'équipe devraient-ils utiliser le Python 3.13 de Debian plutôt qu'un Python téléchargé par uv ?
13. `uv sync` (sans option) dans une CI, `uv sync --locked`, `uv sync --frozen` : différence de comportement quand `pyproject.toml` et `uv.lock` ne correspondent plus ? Lequel en CI, lequel en local, et pourquoi ?
14. QCM — Un service systemd lance `medictl` (Python) pour créer une VM. `systemctl stop` envoie SIGTERM. Sans gestionnaire de signal dans `medictl` :
    a) Python lève `KeyboardInterrupt` et exécute les blocs `finally` ; b) l'interpréteur est tué sans exécuter les `finally` ni les `atexit` ; c) Python ignore SIGTERM ; d) systemd attend la fin de la création.
    Comment rendre l'arrêt propre, et pourquoi la tâche Proxmox continue-t-elle de toute façon ?
15. Pourquoi les gestionnaires de signaux Python ne s'exécutent-ils que dans le fil principal, et quelle conséquence pour un outil qui lance ses appels d'API dans un `ThreadPoolExecutor` ?
16. Un module de journalisation Python est configuré par `logging.basicConfig()` dans `medictl` **et** dans une bibliothèque importée. Que se passe-t-il ? Comment un outil doit-il configurer la journalisation, et comment éviter que le secret du jeton y apparaisse ?
17. Tu dois réécrire `ms-archiver-journaux` (E39) en Python. Quelles garanties te donne Python « gratuitement » par rapport à Bash (erreurs, structures de données), et lesquelles restent à écrire toi-même (atomicité, contrôle de l'archive, codes retour) ?
18. ShellCheck, ruff, bats, pytest, revue de code : pour chacune des pannes M02-E37 (variantes rencontrées), M02-E39 et M02-E42, quel outil l'aurait arrêtée **avant** la production, et lequel ne l'aurait pas vue ? Conclus sur la place de chacun.

**Critères de réussite**
- [ ] Les 18 questions ont une réponse écrite et argumentée (pour les QCM : la bonne réponse **et** pourquoi les autres sont fausses).
- [ ] Après correction, tu as identifié tes trois points les plus faibles et noté un exercice ou une lecture pour chacun.

<details><summary>Indice 1</summary>

Pour les questions 1 à 6, tes tests de M02-E44 et le script minimal de M02-E39 contiennent l'essentiel des réponses ; vérifie-les dans le manuel de Bash.
</details>

<details><summary>Indice 2</summary>

Pour les questions 7 à 16, la documentation de la bibliothèque standard (`subprocess`, `signal`, `logging`, `site`), celle de requests (*Advanced Usage* : délais, proxys, vérification TLS) et celle de uv (projets, outils) sont la référence.
</details>

**Pour aller plus loin** (facultatif) : choisis trois questions et transforme chacune en test automatisé (bats ou pytest) dans `plateforme/outils`.
