# Module 01 — Introduction : Git et workflow professionnel

## Une forge pour l'équipe

Lundi matin, le socle v0 est livré et étiqueté. La revue de Claire s'est bien passée. Dans ta boîte de réception :

> **De** : Claire Morel — Responsable infrastructure
> **À** : toi
> **Cc** : Karim Benali, Sophie Laurent
> **Objet** : Prochaine étape — la forge
>
> Bravo pour le socle. Une remarque de la revue m'a marquée : toute la documentation, les scripts et l'historique de ce que tu as construit vivent dans un dépôt Git **sur `adm01`, connu de toi seul**. Si `adm01` disparaît, ou si tu pars en vacances, l'équipe repart de zéro.
>
> Avant d'écrire la moindre ligne de script, de rôle Ansible ou de code OpenTofu, je veux une **forge** :
> 1. un **GitLab auto-hébergé** sur le socle. Pas de SaaS : notre code décrit une infrastructure qui héberge des données de santé, il reste chez nous ;
> 2. un **workflow commun** : personne ne pousse directement sur `main`, tout passe par une demande de fusion (*merge request*, MR) relue ;
> 3. des **garde-fous automatiques** : format des messages de commit, qualité, et surtout **aucun secret** dans un dépôt (Sophie y tient, et elle a raison) ;
> 4. des **versions publiées sans intervention manuelle**, avec des notes de version lisibles ;
> 5. une forge **sauvegardée, mise à jour et supervisée**, comme n'importe quel service de production.
>
> Karim profitera de ce module pour vérifier que tu maîtrises Git au-delà de `add`, `commit`, `push` : on va beaucoup réécrire, fusionner et réparer d'historique dans les mois qui viennent.
>
> Claire

Sophie a répondu à tous dans la foulée : « D'accord sur tout. J'ajoute : HTTPS partout, même en interne, et des jetons à durée de vie limitée. »

---

## Ce que tu construis dans ce module

À la fin du module 01 :

- `git01` (GitLab CE) et `runner01` (GitLab Runner) font partie du **socle permanent** ;
- une **PKI provisoire** signe le certificat HTTPS de la forge (elle sera remplacée par step-ca au module 06) ;
- l'instance GitLab est administrée proprement : comptes nominatifs, groupes privés, inscriptions fermées, jetons à portée minimale ;
- le dépôt de documentation `~/medisphere` est devenu le projet **`plateforme/medisphere`**, avec tout son historique ;
- chaque projet de la plateforme a une branche `main` protégée, des MR relues, des **hooks pre-commit** versionnés, un **pipeline de qualité obligatoire**, des **hooks côté serveur** en dernier rempart, et des **versions automatiques** (semantic-release) ;
- la forge est sauvegardée vers PBS, restaurée au moins une fois, mise à jour en suivant le chemin officiel, et surveillée ;
- tu sais diagnostiquer les pannes classiques d'une forge et réparer un dépôt local abîmé.

## Architecture du module

```
  Ton poste ─── VPN wg1 (10.255.1.2) ───┐
                                         │
  VLAN 10 MGMT                 ┌─────────┴──────────────┐                   PAR2 (tunnel wg0)
 ┌───────────────────────┐     │ gw01 — routeur, NAT    │═════ wg0 ═════╗  ┌──────────────────────┐
 │ adm01  10.10.10.10    │────▶│ 10.10.10.1 / 10.10.20.1│               ╚══│ pbs01  10.20.10.10   │
 │ git, clés SSH,        │     │ NTP, filtrage          │                  │ datastore ds-lab     │
 │ PKI provisoire,       │     └─────────┬──────────────┘                  │ ns par1/git01 (E28)  │
 │ ~/medisphere, ~/src/* │               │                                 └──────────────────────┘
 └───────────────────────┘               │ (MGMT → INFRA : autorisé ; INFRA → MGMT : refusé)
                                         │
  VLAN 20 INFRA ─────────────────────────┴──────────────────────────────────────────────────
     ┌────────────────────┐   ┌──────────────────────────────┐   ┌──────────────────────────┐
     │ dns01 10.10.20.10  │   │ git01  10.10.20.12  (1004)   │   │ runner01 10.10.20.15     │
     │ dnsmasq : A + PTR  │   │ GitLab CE 19.x (omnibus)     │◀──│ (1007) GitLab Runner     │
     │ de git01, runner01 │   │ HTTPS 443 · SSH 22 (git@)    │   │ exécuteur shell          │
     └────────────────────┘   │ PostgreSQL, Gitaly, Puma…    │   │ étiquettes shell, socle  │
                              └──────────────────────────────┘   └──────────────────────────┘
```

Flux principaux (tous à l'intérieur du lab, rien n'est exposé sur Internet) :

| Source | Destination | Port | Usage | Passe par `gw01` ? |
|---|---|---|---|---|
| `adm01`, ton poste (VPN) | `git01` | TCP 443 (et 80, redirigé) | interface web, API | oui (MGMT/VPN → INFRA, déjà autorisé au M00) |
| `adm01`, ton poste (VPN) | `git01` | TCP 22 | `git clone`/`push` en SSH (`git@`) et administration (`admin@`) | oui (déjà autorisé) |
| `runner01` | `git01` | TCP 443 | récupération des jobs, clonage, API | non (même VLAN) |
| `git01`, `runner01` | Internet | TCP 443 | paquets (`packages.gitlab.com`, Debian, NodeSource) | oui (NAT, déjà autorisé) |
| `git01` | `pbs01` | TCP 8007 | copie des sauvegardes de GitLab (E28) | oui, **nouveau flux** à ouvrir en E28 |

Les VLANs INFRA ne joignent pas MGMT : `git01` ne peut pas initier de connexion vers `adm01`. C'est voulu, et c'est pour cela que les *webhooks* ou les sauvegardes partent toujours vers des services d'INFRA ou de PAR2, jamais vers le poste d'administration.

## Adresses et objets du module

| Élément | Valeur | Créé en |
|---|---|---|
| `git01` | VMID 1004, 10.10.20.12/24 (VNet `vinfra`), 4 vCPU, 8 Go, disque 60 Go, étiquettes `socle;role-gitlab` | E04 |
| URL de GitLab | `https://git01.par1.medisphere.internal` | E04 |
| Accès Git en SSH | `git@git01.par1.medisphere.internal:<groupe>/<projet>.git` (sshd système, port 22) | E04, E06 |
| PKI provisoire | `~/pki-provisoire/` sur `adm01` (700) ; racine installée sous `/usr/local/share/ca-certificates/medisphere-provisoire.crt` | E04 |
| `runner01` | VMID 1007, 10.10.20.15/24 (VNet `vinfra`), 2 vCPU, 4 Go, disque 30 Go, étiquettes `socle;role-runner` | E23 |
| Groupes GitLab | `plateforme` (projets de l'équipe), `formation` (bac à sable des exercices Git) | E05 |
| Projets | `plateforme/medisphere` (E06), `plateforme/ci-templates` (E24) ; bac à sable : `formation/git-labo` (E07), `formation/labo-fuite` (E17), `formation/chrono-…` (E35), `formation/legacy-rdv` (E45) | |
| Comptes GitLab | `root` (bris de glace), `<MOI>` (ton compte, administrateur), `claire.morel`, `karim.benali`, `sophie.laurent`, `julien.petit`, `nadia.roussel`, `lucas.martin` | E05 |
| VMs jetables | 2010-2019 (pool `lab`), dont 2010 `git-restore` (E28) | |
| Documentation | `docs/socle/` de `plateforme/medisphere` : ADR à partir d'`ADR-0010`, runbooks `RB-010` (restaurer GitLab, E28), `RB-011` (mettre à jour, E29), `RB-012` (diagnostiquer, E30), `RB-013` (forge en panne, E47) | |

`<MOI>` désigne **ton identifiant** sur la forge (par exemple `camille.durand`, sur le modèle des comptes des personnages). Tu le choisis en E03 et tu ne le changes plus : il apparaît dans ton adresse Git, ton compte GitLab et `lab/lab.env`.

### Fichiers locaux sur `adm01`

| Emplacement | Contenu | Droits |
|---|---|---|
| `~/.config/workbook/gitlab-checks.token` | jeton personnel en **lecture** (`read_api`), utilisé par les checks | 600 |
| `~/.config/workbook/gitlab-admin.token` | jeton personnel d'**administration** (`api`, expiration courte), utilisé par les scripts de ressources et de panne | 600 |
| `~/pki-provisoire/` | clé et certificat de la CA provisoire, certificats serveur | 700 (clés en 600) |
| `~/medisphere` | clone de `plateforme/medisphere` (`WB_DEPOT`) | |
| `~/src/<projet>` | clones des autres projets (`WB_SRC`) : `labo-objets` (E02), `git-labo` (E07), `ci-templates` (E24)… | |

Le dossier `~/.config/workbook/` (700) existe depuis M00-E17 et contient déjà `pve-api.env`. **Aucun de ces fichiers n'entre jamais dans un dépôt.** À partir de M01-E31 (*Admin Mode* activé), les deux jetons GitLab portent aussi la portée `admin_mode`, sans laquelle un jeton d'administrateur n'accède plus aux points d'administration de l'API.

---

## Préparation : `lab/lab.env`

Le module utilise les variables suivantes de `lab/lab.env` (copie de `lab/lab.env.example` faite au M00). Si ta copie date d'avant le bloc A, ajoute les lignes manquantes en les recopiant depuis `lab/lab.env.example` (après un `git pull` du workbook).

| Variable | Défaut | Rôle |
|---|---|---|
| `WB_DEPOT` | `$HOME/medisphere` | Dépôt de documentation, migré vers `plateforme/medisphere` en E06 |
| `WB_SRC` | `$HOME/src` | Dossier des clones de travail des autres projets |
| `WB_MOI` | vide | Ton identifiant `<MOI>` : à renseigner en E03 |
| `WB_GITLAB_URL` | `https://git01.par1.medisphere.internal` | URL de la forge |
| `WB_GITLAB_TOKEN_FILE` | `~/.config/workbook/gitlab-checks.token` | Jeton en lecture des checks (E05) |
| `WB_GITLAB_ADMIN_TOKEN_FILE` | `~/.config/workbook/gitlab-admin.token` | Jeton d'administration des scripts de ressources et de panne (E05) |

Outils nécessaires sur `adm01` (installés au M00-E15, sauf mention) : `git`, `curl`, `jq`, `openssl`, `ssh`. Les checks de ce module en ont besoin et te le signalent s'il en manque un.

Avant de commencer, vérifie que le socle est sain : `lab/bin/check 00 50` doit être vert, et `ssh-add -l` doit lister ta clé (les checks travaillent en SSH non interactif).

---

## Concepts clés (synthèse)

Ce module n'est pas un cours de Git : il suppose que tu as déjà utilisé Git au quotidien. Les notions ci-dessous sont celles que les exercices mobilisent ; la référence reste le livre *Pro Git* et la documentation officielle (liens en fin de page).

**Le modèle objet.** Un dépôt Git est une base de données d'**objets** immuables, adressés par leur empreinte SHA-1 : *blob* (contenu d'un fichier), *tree* (un répertoire : noms, modes, empreintes), *commit* (un arbre racine, zéro, un ou plusieurs parents, un auteur, un message), *tag* annoté. Les **références** (branches, étiquettes, `HEAD`) sont de simples pointeurs vers ces objets. Presque toute la « magie » de Git (branches gratuites, récupération après erreur, déduplication) découle de ce modèle. Exercices : E02, E45, E46.

**L'index et les trois arbres.** `HEAD` (le dernier commit), l'**index** (ce qui sera commité) et l'**arbre de travail** (tes fichiers). `restore`, `reset` et `checkout` se comprennent comme des copies entre ces trois arbres. Exercice : E08.

**Réécrire n'est pas annuler.** `commit --amend`, `rebase`, `reset` créent de **nouveaux** commits et déplacent des références : sans danger sur une branche locale, destructeur pour les autres sur une branche partagée. Sur ce qui est publié, on **ajoute** (`revert`). Le **reflog** garde trace de chaque déplacement de référence local : c'est ton filet de sécurité. Exercices : E08, E12, E42.

**Fusionner ou rebaser.** Une fusion préserve l'historique tel qu'il s'est passé (commit à deux parents) ; un rebase le réécrit pour le rendre linéaire. Une avance rapide (*fast-forward*) ne crée aucun commit. Le choix de la méthode de fusion d'une équipe (commit de fusion, semi-linéaire, *fast-forward*, *squash*) a des conséquences sur la lisibilité, le `bisect` et les outils de version. Exercices : E07, E09, E11, E12, E13.

**La forge.** GitLab CE installé par le paquet *omnibus* regroupe une dizaine de services pilotés par `gitlab-ctl` : NGINX (TLS), Workhorse, Puma (application Rails), Sidekiq (tâches de fond), Gitaly (accès aux dépôts), PostgreSQL, Redis, et `gitlab-shell` derrière le sshd du système. Toute la configuration tient dans `/etc/gitlab/gitlab.rb`, appliquée par `gitlab-ctl reconfigure`. Les secrets de chiffrement sont dans `/etc/gitlab/gitlab-secrets.json` : sans lui, une sauvegarde est inutilisable (E28).

**Défense en profondeur sur le code.** Trois lignes de contrôle, complémentaires : **pre-commit** sur le poste (rapide, mais contournable par `--no-verify`), **hooks côté serveur** (incontournables, mais rudimentaires), **pipeline CI obligatoire** avant fusion (complet, mais après le push). Un secret arrêté sur le poste n'a jamais fui ; un secret poussé doit être considéré comme compromis (E16, E17).

**Conventions et versions.** Les messages de commit au format **Conventional Commits** (`feat:`, `fix:`, `feat!:`…) deviennent une donnée exploitable : **semantic-release** en déduit le prochain numéro de version (SemVer), l'étiquette et les notes de version. Exercices : E14, E25.

**GitLab CE et Premium.** Plusieurs protections présentées partout comme « standard » sont réservées aux éditions payantes : approbations obligatoires, *push rules*, propriétaires de code obligatoires. Le module les contourne avec ce que CE offre : branches protégées, discussions résolues obligatoires, pipeline obligatoire, hooks côté serveur. C'est un vrai sujet d'arbitrage, que tu documenteras.

**Mémoire.** GitLab est gourmand. Sur 8 Go, on applique le profil « mémoire contrainte » de la documentation officielle et on désactive la supervision Prometheus embarquée ; l'E30 réactive seulement ce qui est utile, en mesurant le coût. Budget du module : `git01` 8 Go + `runner01` 4 Go, ajoutés au socle (PLAN §3.3).

---

## Règles du module

Les règles de sécurité du lab (introduction du module 00) restent valables. S'y ajoutent :

1. **Aucun secret dans un dépôt, jamais.** Jetons, mots de passe, clés privées : sous `~/.config/workbook/` (700/600) ou dans des variables CI protégées et masquées. Avant tout `push`, tu sais ce que tu publies (`git log -p`, `git diff --staged`). Un secret poussé est **compromis** : on le révoque d'abord, on nettoie ensuite (E17).
2. **La clé de la CA provisoire ne quitte pas `adm01`** (`~/pki-provisoire/`, 700). Quiconque la possède peut fabriquer un certificat valable pour n'importe quel nom auprès de toutes les machines qui font confiance à la CA.
3. **`root` est un compte de bris de glace.** Tu travailles avec ton compte nominatif `<MOI>`. Le mot de passe de `root` est rangé dans ton gestionnaire de mots de passe, pas sur `adm01`, pas dans un dépôt.
4. **Jetons à portée minimale et à durée de vie courte.** Le jeton des checks ne peut que lire ; le jeton d'administration expire en 90 jours au plus. Ils sont révoqués dès qu'ils ne servent plus.
5. **Rien n'est exposé sur Internet.** GitLab n'est joignable que depuis le lab et ton VPN d'administration.
6. **Les exercices de manipulation Git se font dans le groupe `formation`**, jamais sur les projets de `plateforme`. Si tu casses `formation/git-labo`, tu le recrées avec le script fourni ; si tu casses `plateforme/medisphere`, tu restaures.
7. **Les scripts fournis lisent avant d'écrire.** Les scripts de `ressources/` fabriquent des dépôts d'exercice dans `~/src` et refusent d'écraser un dossier existant. Lis-les avant de les lancer : ils sont courts, et c'est une bonne habitude.

---

## Vérifications, pannes, corrigé

- **Checks** : `lab/bin/check 01 <XX>`, depuis `adm01`, comme pour la fin du module 00. Les checks qui interrogent GitLab utilisent le jeton en lecture (`WB_GITLAB_TOKEN_FILE`) : ils ne fonctionnent qu'à partir de l'E05. Ils sont en lecture seule.
- **Pannes** (palier 4) : `lab/bin/break 01 <XX>`, depuis `adm01`, `lab/bin/break 01 <XX> --annuler` pour abandonner **ou pour clore une panne que tu as réparée** (le marqueur de panne active resterait sinon en place et bloquerait l'astreinte E43 et le mini-projet ; l'annulation ne défait pas ta réparation). Elles agissent sur `git01`, `runner01`, sur GitLab avec ton jeton d'administration, ou sur tes clones de `~/src` après les avoir sauvegardés.
- **Corrigé** : même règle qu'au module 00. Cherche honnêtement d'abord ; lis ensuite, même quand le check est vert, les sections « Pièges classiques » et « En production chez MédiSphère ».

## Ordre conseillé

```
E01 ─ E02 ─ E03 ─ E04 ─ E05 ─ E06 ─ E07 ─ E08 ─ E09 ─ palier 2 (E10…)
                   └──── E04 est long : l'installation de GitLab prend du temps,
                         avance la lecture de l'E09 pendant les attentes
```

1. **E01** — positionnement, à froid, avant toute lecture.
2. **E02, E03** — les fondations locales sur `adm01` : le modèle objet, puis ta configuration Git. Pas besoin de GitLab.
3. **E04 → E06** — la forge : installation, administration, migration de `~/medisphere`. Dans cet ordre strict.
4. **E07, E08** — historique et annulations, dans le bac à sable `formation/git-labo`.
5. **E09** — le modèle de branches de l'équipe : il prépare les décisions du palier 2 (E10, E11).

Durée indicative du palier 1 : 14 à 18 heures.

## Pour aller plus loin

- *Pro Git*, 2e édition (Scott Chacon, Ben Straub), en ligne et en français : <https://git-scm.com/book/fr/v2> — chapitres 2, 3, 7 et 10 en priorité.
- Documentation de référence de Git : <https://git-scm.com/docs>
- Documentation de GitLab (installation, administration, API) : <https://docs.gitlab.com/>
- Conventional Commits : <https://www.conventionalcommits.org/fr/v1.0.0/>
- Versions et changements de comportement du bloc A : [`annexes/versions-bloc-A.md`](../../../annexes/versions-bloc-A.md)
