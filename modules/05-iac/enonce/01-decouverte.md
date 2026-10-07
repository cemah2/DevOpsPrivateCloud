# Module 05 — Palier 1 : Découverte

Karim veut d'abord savoir ce que tu sais déjà de l'Infrastructure as Code. Ensuite, tu installes OpenTofu comme on installe un outil de production (dépôt signé, version épinglée), tu ouvres le projet `plateforme/infra`, tu donnes à OpenTofu un compte Proxmox à lui, et tu fais un premier plan qui ne crée rien. Puis une première VM, et tout son cycle de vie : modification, remplacement, destruction, et ce qu'OpenTofu en garde dans son état. Les trois exercices suivants font évoluer le même environnement `envs/lab-m05` avec le langage : variables et validations, boucles, sources de données. Ce que tu écris ici n'est pas jetable : au palier 2, cet environnement passe sur un état distant (E11) et ses VMs deviennent les premières utilisatrices du module `vm-debian` (E13). Le palier se termine par un questionnaire sur l'état et sur ce qui sépare OpenTofu de Terraform.

Prérequis : module 04 terminé ; module 03 (image dorée `current`, ancre TLS de `pve01` dans le magasin d'`adm01`) ; module 02 (script de configuration d'un projet de la forge). Lis [`00-introduction.md`](00-introduction.md), en particulier les conventions du projet, les règles du module et la section « Préparer `adm01` ».

---

### M05-E01 — Test de positionnement : Infrastructure as Code  `Q` `★★`

> **Ticket PLAT-601** — *De : Karim Benali*
> Même rituel qu'aux modules précédents. Infrastructure as Code en général, OpenTofu et Terraform en particulier, un peu de HCL : par écrit, sans moteur de recherche ni IA, sans rien exécuter. Une heure maximum, puis tu te corriges avec la grille. Si tu n'as jamais écrit une ligne de Terraform, réponds quand même : le raisonnement compte.

**Objectifs pédagogiques**
- Évaluer tes acquis en Infrastructure as Code (déclaratif, état, plan, dérive, immuabilité).
- Repérer les notions d'OpenTofu et de HCL à travailler avant les exercices qui les mobilisent.

**Prérequis** : aucun.
**Durée indicative** : 1 h (+ 30 min d'auto-correction).

**Travail demandé**

Réponds aux 20 questions. Pour les QCM, justifie ton choix en une ou deux phrases.

*Infrastructure as Code*

1. Définis **déclaratif** et **impératif**, avec un exemple de chaque pour « créer trois VMs ». Ansible (module 04) est souvent dit déclaratif, OpenTofu aussi : que se passe-t-il dans chacun des deux outils quand on **retire** du code la description d'un objet ?

2. Qu'appelle-t-on infrastructure **mutable** et **immuable** ? Dans quel cas préfère-t-on remplacer une VM plutôt que la modifier ? Quel lien avec les images dorées du module 03 ?

3. Donne quatre bénéfices concrets de l'IaC pour une équipe comme celle de MédiSphère, et deux risques **nouveaux** qu'elle introduit.

4. *(QCM)* Dans OpenTofu, qu'est-ce qu'un **provider** ?
   - A. Un serveur central qui exécute les plans pour le compte des utilisateurs
   - B. Un programme, téléchargé depuis un registre, qui traduit les ressources décrites en appels à l'API d'un système (Proxmox, un cloud, un DNS…)
   - C. Un module réutilisable publié par un éditeur
   - D. L'endroit où OpenTofu stocke son état

5. Qu'est-ce que la **dérive** (*drift*) ? Comment une configuration OpenTofu la révèle-t-elle ? Pourquoi « je corrige vite à la main dans l'interface, je reporterai plus tard » est-il dangereux avec OpenTofu, plus encore qu'avec Ansible ?

*OpenTofu*

6. Explique en une phrase chacun : ressource, source de données, variable, valeur locale (`locals`), sortie (`output`), module, backend.

7. *(QCM)* Que fait `tofu plan` ?
   - A. Il lit seulement le code et l'état, sans contacter l'infrastructure
   - B. Il lit l'état réel des ressources (rafraîchissement), le compare au code, et affiche les actions prévues sans rien modifier
   - C. Il applique les changements en mode test, puis les annule
   - D. Il rafraîchit l'état et enregistre le résultat dans le fichier d'état

8. Dans un plan, que signifient les symboles `+`, `-`, `~`, `-/+`, `+/-` et `<=` ? Lequel doit faire s'arrêter un relecteur, et pourquoi ?

9. *(QCM)* Que contient le fichier d'état d'OpenTofu ?
   - A. Seulement les identifiants des ressources créées
   - B. L'adresse de chaque ressource du code et tous ses attributs lus chez le provider, y compris des valeurs sensibles
   - C. Une copie du code au moment du dernier `apply`
   - D. L'historique des plans appliqués

10. Donne trois raisons pour lesquelles un état **local** (un fichier sur le poste de celui qui lance OpenTofu) pose problème dès qu'on est deux. Qu'apportent un backend distant et un verrou ?

11. Quelle différence entre `count` et `for_each` pour désigner les instances d'une ressource ? Décris ce qui se passe, avec chacun, quand on retire l'élément du **milieu** d'une liste de trois serveurs.

12. *(QCM)* Sur une VM existante, tu modifies un attribut que le provider marque *ForceNew* (par exemple l'identifiant du template à cloner). Que propose le plan ?
    - A. Une modification sur place
    - B. Le remplacement de la VM : destruction puis création (ou l'inverse)
    - C. Une erreur : l'attribut ne peut pas changer
    - D. Rien : OpenTofu ignore les attributs de création une fois la ressource créée

13. À quoi sert le fichier `.terraform.lock.hcl` ? Faut-il le versionner ? Quelle différence avec la contrainte `version` écrite dans `required_providers` ?

14. Compare les contraintes `~> 0.115.0`, `~> 0.115` et `>= 0.115.0`. Pourquoi épingler plus strictement un provider en version 0.x qu'un provider en version 5.x ?

15. Une sortie déclarée `sensitive = true` : que protège ce réglage, et que ne protège-t-il pas ?

16. *(QCM)* Une VM créée par OpenTofu est supprimée à la main dans l'interface de Proxmox. Que fait le plan suivant ?
    - A. Il échoue : la ressource de l'état n'existe plus
    - B. Il constate l'absence au rafraîchissement et propose de recréer la VM
    - C. Il ne voit rien : l'état dit que la VM existe
    - D. Il retire la ressource du code

17. Les dépendances entre ressources : quand OpenTofu les déduit-il seul ? Dans quel cas faut-il écrire `depends_on`, et pourquoi faut-il s'en méfier ?

18. Une VM du socle existe déjà, créée à la main il y a six mois. Comment la faire gérer par OpenTofu **sans la recréer** ? Qu'est-ce qui peut mal tourner ?

*Écosystème et langage*

19. Raconte en quelques lignes l'histoire d'OpenTofu (licences, dates, organisation qui le porte). Quelles conséquences pratiques pour MédiSphère : registre des providers, compatibilité du code et de l'état avec Terraform, risques à mélanger les deux outils ?

20. Que donnent ces expressions HCL (valeur et type) ?
    ```hcl
    "vm-${2050 + 1}"
    length(["a", "b"]) > 1
    upper("m05")
    [for n in ["app01", "app02"] : "m05-${n}"]
    { for n in ["app01", "app02"] : n => length(n) }
    coalesce("", "defaut")
    try(tonumber("2050a"), -1)
    ```

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 20 questions avant d'ouvrir le corrigé.
- [ ] Tu as noté chaque réponse avec la grille (0, 1 ou 2 points) et calculé ton score sur 40.
- [ ] Tu as noté les thèmes à retravailler et les exercices du module qui les mobilisent.

<details><summary>Indice 1</summary>

Pour les questions sur l'état, pars de ce dont OpenTofu a besoin pour décider qu'une ressource du code « est » tel objet réel, et pour savoir ce qui a changé depuis la dernière fois. Tout ce dont il a besoin, il doit le garder quelque part.
</details>

<details><summary>Indice 2</summary>

Pour `count` et `for_each`, écris l'adresse complète de chaque instance (`ressource.nom[...]`) avant et après le retrait : OpenTofu compare des **adresses**, pas des noms de VM.
</details>

**Pour aller plus loin** (facultatif) : refais ce test à la fin du module (E46), sans relire le corrigé, et compare.

---

### M05-E02 — Installer OpenTofu et créer le projet `plateforme/infra`  `LAB` `★`

> **Ticket PLAT-602** — *De : Karim Benali*
> Installe OpenTofu sur `adm01` comme on installe un outil qui va créer et détruire des machines : depuis le dépôt officiel, clés vérifiées, et une version **fixée** (je ne veux pas découvrir une 1.14 un lundi matin après un `apt upgrade`). Ensuite, ouvre `plateforme/infra` avec la configuration standard de la forge, à une différence près : ce dépôt ne publie pas de versions, on y **applique** des changements. Pas de semantic-release, donc pas de jeton de publication qui traînerait sans usage.

**Objectifs pédagogiques**
- Installer un outil depuis un dépôt APT tiers en contrôlant les clés de signature et en épinglant une série de versions.
- Configurer l'outil pour le poste (complétion, cache des providers).
- Créer un projet de la plateforme, et justifier un écart à la configuration standard.
- Écrire un `.gitignore` qui protège ce qu'OpenTofu produit de sensible.

**Prérequis** : M02-E02 (script de configuration d'un projet), M01-E15 (pre-commit), M03-E02 (dépôt APT tiers et clé limitée à un dépôt).
**Durée indicative** : 2 h.

**Contexte technique**
- Méthode d'installation : la documentation officielle (<https://opentofu.org/docs/intro/install/deb/>), **pas à pas** (pas le script d'installation exécuté en aveugle). Deux clés publiques y sont déclarées pour le dépôt `https://packages.opentofu.org/opentofu/tofu/any/`. Paquet : `tofu`.
- Version : série **1.13** seulement, maintenue par des préférences APT (`/etc/apt/preferences.d/`).
- Fichier de configuration de la CLI d'OpenTofu : `~/.tofurc` (cache des providers dans `~/.cache/opentofu/plugins`, à créer).
- Projet : `plateforme/infra`, privé, clone `~/src/infra` (`git@git01.par1.medisphere.internal:plateforme/infra.git`). Configuration standard (M02-E02) **sauf** la publication de versions :

| Élément standard | Dans `plateforme/infra` |
|---|---|
| Règles de fusion, protections de `main`, étiquettes `v*` protégées | oui |
| `.pre-commit-config.yaml` (référence M01-E15), `commitlint.config.mjs`, `.gitleaks.toml`, `CONTRIBUTING.md`, modèle de MR | oui (les hooks OpenTofu arrivent en E20) |
| `.gitlab-ci.yml` incluant `plateforme/ci-templates` en `ref: v1` | `templates/qualite.yml` **seulement** |
| `.releaserc.json`, `templates/release.yml`, jeton de projet `bot-release`, variable CI `GITLAB_TOKEN` | **non** : rien ne doit en rester |

- Arborescence initiale : `README.md` (à quoi sert le dépôt, arborescence, prérequis du poste, comment travailler), `envs/lab-m05/README.md` (une ligne : VMs 2050-2059, jetables, état local jusqu'à E11). Le reste arrive avec les exercices.
- `.gitignore` : protège tout ce qu'OpenTofu produit et qui ne doit jamais entrer dans Git (dossier de travail, états, leurs sauvegardes et verrous, plans enregistrés, journaux de plantage, surcharges locales, fichiers de secrets) ; laisse versionnés `.terraform.lock.hcl` et `terraform.tfvars`.

**Travail demandé**
1. **Dépôt et clés.** Télécharge les deux clés de la documentation dans un dossier temporaire, et affiche l'empreinte complète de chacune (`gpg --show-keys --with-fingerprint`). Où OpenTofu publie-t-il l'empreinte de sa propre clé ? Celle de la seconde clé est-elle publiée quelque part par OpenTofu ? Dans ton journal (`~/m05/e02/notes.md`) : que vérifies-tu vraiment en comparant une empreinte à celle qu'affiche le même site que celui qui t'a donné la clé ? Que signe chacune des deux clés (un fichier `InRelease` se vérifie avec `gpg --verify`) ?
   > ⚠️ **Attention** : une clé ajoutée sans `signed-by` (dans `/etc/apt/trusted.gpg.d/`) peut signer **n'importe quel** paquet installable sur `adm01`, y compris un faux `openssh-server`. Les clés d'OpenTofu ne valent que pour son dépôt.
2. **Installation épinglée.** Déclare le dépôt dans `/etc/apt/sources.list.d/`, écris la préférence qui limite `tofu` à la série 1.13, installe, puis :
   ```
   admin@adm01:~$ tofu version
   admin@adm01:~$ apt-cache policy tofu
   ```
   Que montre la priorité affichée devant chaque version ? Que ferait `apt upgrade` le jour où la 1.14.0 sera publiée ? Et `apt install tofu=1.12.7` ?
3. **Le poste.** Active la complétion (`tofu -install-autocomplete`, puis un nouveau shell) et le cache des providers dans `~/.tofurc`. Pourquoi un cache est-il utile quand chaque configuration (`envs/lab-m05`, `socle`…) télécharge ses propres providers ? Que se passerait-il si le dossier du cache n'existait pas ?
4. **Le projet.** Crée `plateforme/infra` avec le script de M02-E02 (il est rejouable), puis défais ce qui ne sert pas ici : le jeton `bot-release` et la variable `GITLAB_TOKEN` (par l'API ou l'interface). Pourquoi un jeton inutilisé est-il un risque, même s'il n'est écrit nulle part ?
5. **Le squelette.** Clone le projet dans `~/src/infra`, branche `chore/initialisation`. Ajoute les fichiers du tableau (copiés de `~/src/outils` ou de `~/src/ansible`, adaptés), le `.gitlab-ci.yml`, le `README.md`, `envs/lab-m05/README.md`, et une section « Règles propres à `plateforme/infra` » dans `CONTRIBUTING.md` (comment une MR présente un plan, d'où l'on applique, ce qui est interdit). Puis teste ton `.gitignore` **avant** d'avoir le moindre état :
   ```
   admin@adm01:~/src/infra$ git check-ignore -v envs/lab-m05/terraform.tfstate envs/lab-m05/.terraform/providers envs/lab-m05/essai.tfplan
   admin@adm01:~/src/infra$ git check-ignore -v envs/lab-m05/.terraform.lock.hcl envs/lab-m05/terraform.tfvars || echo "versionnés"
   ```
6. `pre-commit install`, `pre-commit run --all-files`, commit conventionnel, MR avec le modèle, pipeline vert, fusion.
7. Journal : un collègue propose d'installer aussi Terraform sur `adm01` « pour comparer ». Quels risques concrets pour les états et les fichiers de verrouillage du projet ? Quelle règle proposerais-tu ?

**Critères de réussite**
- [ ] `tofu version` affiche 1.13.x ; le paquet vient de `packages.opentofu.org`, signé par des clés limitées à ce dépôt ; la série 1.13 est épinglée.
- [ ] `plateforme/infra` existe, conforme aux règles de la plateforme ; aucun jeton de publication ni variable `GITLAB_TOKEN` n'y subsiste.
- [ ] `main` contient les fichiers standard, le `.gitlab-ci.yml` (gabarit `qualite.yml` seul), le `README.md` et `envs/lab-m05/README.md`.
- [ ] États, sauvegardes d'état, plans enregistrés et dossier `.terraform/` sont ignorés ; `.terraform.lock.hcl` et `terraform.tfvars` ne le sont pas.
- [ ] Le dernier pipeline de `main` est réussi.

**Vérification** : `lab/bin/check 05 02`

<details><summary>Indice 1</summary>

Le script d'installation officiel d'OpenTofu contient, en clair, l'identifiant de la clé qu'il attend : lis-le (sans l'exécuter). Pour la clé qui signe le dépôt, `gpg --verify InRelease` après import dans un trousseau **temporaire** (`--homedir`) te dit laquelle sert à APT.
</details>

<details><summary>Indice 2</summary>

Une préférence APT associe un motif de version (`Pin: version 1.13.*`) à une priorité. Une priorité supérieure à 1000 l'emporte même sur une version plus récente, et autorise un retour en arrière à l'intérieur du motif ; `apt-cache policy` affiche la priorité retenue pour chaque version.
</details>

<details><summary>Indice 3</summary>

Les jetons de projet se listent et se révoquent par `GET`/`DELETE /projects/:id/access_tokens`, les variables CI par `DELETE /projects/:id/variables/:clé`. Le script de M02-E02 recréerait le jeton si tu le relançais : note-le dans le `README.md` (écart à la configuration standard).
</details>

**Pour aller plus loin** (facultatif) : les publications d'OpenTofu sont aussi signées avec **cosign** (signature sans clé, liée à l'identité du pipeline de publication sur GitHub). En suivant la page d'installation autonome (*standalone*) de la documentation, vérifie avec `cosign verify-blob` le fichier `tofu_<version>_SHA256SUMS` d'une release, puis l'archive `.tar.gz` avec ce fichier : que prouve cette signature que la clé GPG ne prouve pas ?

---

### M05-E03 — Compte Proxmox `wb-tofu`, provider épinglé, premier plan  `LAB` `★★`

> **Ticket SEC-603** — *De : Sophie Laurent* — *Copie : Karim Benali*
> OpenTofu va créer et **détruire** des VMs. Même exigence que pour Packer et Ansible : un compte à lui, un jeton qui expire, des droits limités au pool `lab` et aux seuls stockages et réseaux nécessaires, **chaque privilège justifié**. Le provider est un binaire téléchargé sur Internet : je veux savoir lequel, quelle version, et comment on est sûr que c'est le bon. Et le TLS est vérifié, comme partout. Premier plan quand tout ça est prêt, et pas avant.

**Objectifs pédagogiques**
- Déduire les privilèges Proxmox VE 9 d'un provider à partir des appels qu'il fait à l'API.
- Configurer un provider sans aucun secret dans le code, et lui faire vérifier le certificat de l'API.
- Épingler un provider et comprendre le fichier de verrouillage (`.terraform.lock.hcl`).
- Lancer un premier plan, comprendre ce qu'il prouve et ce qu'il ne prouve pas.

**Prérequis** : M05-E02 ; M00-E17 (jetons à privilèges séparés), M03-E02 (privilèges déduits de l'API, ancre TLS dans le magasin système).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Compte : `wb-tofu@pve`, jeton `tofu` à privilèges séparés, expiration à un an au plus. Rôle personnalisé `WBTofu` sur `/pool/lab` ; rôles intégrés de Proxmox autorisés sur les stockages et les VNets.
- Ce qu'OpenTofu doit pouvoir faire au palier 1 : cloner un template du pool `lab` (clone complet) dans le pool `lab` ; régler CPU, mémoire, contrôleur, port série, affichage, options (nom, description, étiquettes, démarrage), paramètres cloud-init ; agrandir le disque cloné et ajouter des disques sur `local-nvme` ; brancher la carte réseau sur le VNet `vsandbox` ; démarrer, redémarrer, éteindre, détruire ; lire l'adresse IP par l'agent QEMU ; lister les VMs et templates du pool ; lire la place libre de `local-nvme`. E10 élargira le périmètre au VNet `vinfra` et au stockage `hdd-bulk`.
- Interdits : tout ce qui est hors du pool ; exécuter des commandes ou lire des fichiers dans les invités ; console ; instantanés et sauvegardes ; supprimer des volumes arbitraires d'un stockage ; administrer le nœud, les stockages, les pools, les utilisateurs.
- Fichier d'accès sur `adm01` : `~/.config/workbook/pve-tofu.env`, mode 600, avec **exactement** les deux variables d'environnement que le provider lit pour l'adresse de l'API et le jeton (trouve leur nom et leur format dans la documentation du provider).
- Provider : `bpg/proxmox`, contrainte `~> 0.115.0` ; OpenTofu `~> 1.13.0`. Configuration dans `envs/lab-m05/` : `versions.tf` (versions), `providers.tf` (bloc `provider`, sans secret, TLS vérifié écrit explicitement), `main.tf` (une source de données `proxmox_version` nommée `pve01` et une sortie `version_pve`).
- Documentation du provider (version 0.115) : page d'accueil (*Authentication*, *Environment Variables Summary*, *SSH Connection*) et pages des ressources, sur <https://search.opentofu.org/provider/bpg/proxmox/v0.115.0>.

**Travail demandé**
1. **Lire avant d'écrire.** Dans la documentation du provider : comment lui passer un jeton d'API, et sous quel format ? Quelles variables d'environnement lit-il ? Quelles opérations exigent une connexion **SSH** au nœud, en plus de l'API, et avec quel compte ? En auras-tu besoin à ce palier ? Note tes réponses dans `~/m05/e03/notes.md`.
2. **Privilèges.** Pour chaque opération du contexte, trouve dans l'API viewer de Proxmox VE 9 l'appel correspondant et son contrôle de permissions (privilège **et** chemin). Méthode : le provider passe par `POST /nodes/{node}/qemu/{vmid}/clone`, `PUT` et `POST …/config`, `PUT …/resize`, `POST …/status/{start,shutdown,stop,reboot}`, `DELETE …/qemu/{vmid}`, `GET …/agent/network-get-interfaces`, `GET /pools`, `GET /nodes/{node}/qemu`, `GET /nodes/{node}/storage`. Lis attentivement le contrôle de `…/clone` : sur quel chemin `VM.Allocate` est-il exigé, et à quelle condition ? Écris la liste minimale, une ligne de justification par privilège, et une ligne par privilège écarté qui « aurait pu servir ».
3. **Compte.** Crée le rôle, l'utilisateur (sans mot de passe), le jeton et les ACL, sur l'utilisateur **et** sur le jeton. Écris-le sous forme de script rejouable (tu en élargiras le périmètre en E10). Contrôle les droits effectifs du jeton sur chaque chemin **et** sur `/` (`pveum user token permissions`).
4. **Secret.** Crée `~/.config/workbook/pve-tofu.env` avec les bons droits **avant** d'y écrire, sans que le secret passe par l'historique du shell. Inscris le jeton au registre des secrets (`docs/socle/registre-secrets.md` de `plateforme/medisphere`, par MR).
5. **Code.** Sur une branche `feat/lab-m05-provider`, écris `versions.tf`, `providers.tf` et `main.tf`. Puis :
   ```
   admin@adm01:~/src/infra/envs/lab-m05$ tofu init
   admin@adm01:~/src/infra/envs/lab-m05$ tofu providers
   admin@adm01:~/src/infra/envs/lab-m05$ cat .terraform.lock.hcl
   ```
   Questions pour le journal : d'où le provider a-t-il été téléchargé (adresse complète) ? Combien d'empreintes `h1:` et `zh:` contient le fichier de verrouillage, et pourquoi autant pour un seul poste ? Que se passe-t-il au prochain `tofu init` si quelqu'un a modifié une empreinte ? Que contient `.terraform/`, et pourquoi ne le versionne-t-on pas ?
6. **Premier plan.** Lance `tofu plan` sans avoir chargé `pve-tofu.env` : lis l'erreur. Charge-le (`set -a; . ~/.config/workbook/pve-tofu.env; set +a`), relance, puis `tofu apply`. Qu'a-t-il créé sur `pve01` ? Que contient maintenant le dossier ? Que donne `tofu output` ?
7. **Ce que le plan prouve.** Trois expériences, à noter dans le journal :
   - remplace le secret du jeton par un faux dans ta session (pas dans le fichier) et relance le plan ;
   - relance-le en faisant croire au provider que le magasin d'autorités est vide : `SSL_CERT_FILE=/dev/null tofu plan`. Le plan réussit-il encore ? Ajoute `SSL_CERT_DIR=/dev/null` et relance. Qu'en déduis-tu sur l'endroit où le provider cherche les autorités, et sur la façon dont le TLS est vérifié ?
   - un plan réussi prouve-t-il que le jeton a les **privilèges** nécessaires à E04 ? Cherche dans l'API viewer qui a le droit d'appeler `GET /version`.
8. Commit, MR, fusion. Réponds au ticket : privilèges et ACL justifiés, emplacement du secret, mécanisme TLS, besoin (ou non) de SSH, provenance et vérification du provider, procédure de renouvellement du jeton.

**Critères de réussite**
- [ ] Le jeton `wb-tofu@pve!tofu` a la séparation des privilèges et une date d'expiration à un an au plus.
- [ ] Le rôle `WBTofu` permet de cloner, configurer, démarrer, détruire et lire l'agent, mais ne contient aucun privilège `Sys.*`, `Permissions.*`, `User.*`, `Realm.*`, `Pool.Allocate`, `Datastore.Allocate`, `VM.Console`, `VM.GuestAgent.Unrestricted` ni `VM.GuestAgent.File*`.
- [ ] Droits effectifs du jeton : `/pool/lab` (rôle `WBTofu`), allocation d'espace sur `local-nvme`, usage du VNet `vsandbox`, rien sur `/`.
- [ ] `pve-tofu.env` est en mode 600 dans un dossier 700, hors de tout dépôt, avec les deux variables du provider et sans désactivation du TLS ; le jeton est au registre des secrets.
- [ ] `main` contient `envs/lab-m05/versions.tf`, `providers.tf`, `main.tf` et `.terraform.lock.hcl` (provider `bpg/proxmox` 0.115.x) ; aucun secret ni `insecure = true` dans le code.
- [ ] L'état local de `envs/lab-m05` contient la sortie `version_pve` (Proxmox VE 9).

**Vérification** : `lab/bin/check 05 03`

<details><summary>Indice 1</summary>

Le provider est un programme Go : comme le plugin Packer du module 03, il n'a pas d'option « chemin vers une autorité ». Regarde dans son code (`proxmox/api/client.go`) comment est construit le `tls.Config`, et rappelle-toi où la bibliothèque standard de Go cherche les autorités sur Debian.
</details>

<details><summary>Indice 2</summary>

Le contrôle de `…/clone` combine plusieurs conditions avec `and` et `or`, dont une qui ne s'applique que si le paramètre `pool` est passé. Le provider passe-t-il ce paramètre quand la ressource a un `pool_id` ? Et `/vms/{newid}`, pour une VM qui n'existe pas encore, hérite-t-il des droits du pool ?
</details>

<details><summary>Indice 3</summary>

`GET /nodes/{node}/qemu` et `GET /pools` ne refusent jamais : ils **filtrent**. Un jeton sans `VM.Audit` ou sans `Pool.Audit` obtient une liste incomplète, sans erreur. Garde-le en tête pour E08.
</details>

**Pour aller plus loin** (facultatif) : `tofu providers lock -platform=linux_amd64 -platform=linux_arm64` ; lis la page *Dependency Lock File* de la documentation : dans quel cas aurait-on besoin de cette commande depuis OpenTofu 1.12 ?

---

### M05-E04 — Première VM déclarée  `LAB` `★`

> **Ticket PLAT-604** — *De : Karim Benali*
> Montre-moi une VM qui n'existe que parce qu'elle est écrite : `m05-essai`, VMID 2050, clone complet de l'image dorée courante, sur `vsandbox`. Une condition : quand tu relances `tofu plan` après l'`apply`, il doit dire qu'il n'y a **rien** à faire. Si ce n'est pas le cas, c'est que ton code ne décrit pas ce qui existe, et je veux que tu comprennes pourquoi avant de passer à la suite.

**Objectifs pédagogiques**
- Décrire une VM Proxmox clonée d'un template avec la ressource `proxmox_virtual_environment_vm`.
- Lire un plan de création, puis vérifier dans Proxmox que la réalité correspond.
- Comprendre ce qu'une VM clonée hérite du template, et ce que le provider impose par ses valeurs par défaut.
- Obtenir un plan vide après création : la preuve que le code décrit la réalité.

**Prérequis** : M05-E03 ; M03-E10 (image dorée publiée `current`).
**Durée indicative** : 2 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Ressource | `proxmox_virtual_environment_vm.essai`, dans `envs/lab-m05/main.tf` |
| VM | VMID 2050, nom `m05-essai`, nœud `<NOEUD>`, pool `lab`, étiquette `env-m05` (et aucune autre), description qui dit que la VM est gérée par OpenTofu et par quel dossier |
| Source | clone **complet** de l'image dorée Debian 13 étiquetée `current` (son VMID, `<VMID-CURRENT>`, écrit en dur pour l'instant), disques du clone sur `local-nvme` |
| Matériel | 2 vCPU `x86-64-v2-AES`, 1024 Mo, contrôleur `virtio-scsi-single`, disque `scsi0` agrandi à 10 Go (même format, `iothread`, `discard` et émulation SSD que le template), port série `socket` et affichage `serial0`, type d'OS Linux, agent QEMU |
| Réseau | une carte `virtio` sur le VNet `vsandbox` (DHCP) |
| cloud-init | lecteur sur `local-nvme` ; compte `admin` avec la clé publique `~/.ssh/id_ed25519.pub` d'`adm01` ; DHCP ; résolveur 10.10.20.10, domaine `par1.medisphere.internal` |
| Démarrage | démarrée après création ; **ne** redémarre **pas** avec `pve01` ; arrêtée net (pas d'arrêt propre) à la destruction |
| Sortie | `essai_ipv4` : les adresses IPv4 rapportées par l'agent, sans la boucle locale |

- Pages utiles de la documentation du provider : la ressource `proxmox_virtual_environment_vm` (arguments, sections *Qemu guest agent* et *Important Notes / Cloning*).
- Règle du projet (`CONTRIBUTING.md`) : pendant la mise au point, tu peux appliquer depuis ta branche, parce que la VM 2050 est jetable ; la version finale passe par MR, et un plan depuis `main` à jour doit être vide.

**Travail demandé**
1. **Lire la documentation.** Pour chaque ligne du tableau, trouve l'argument du provider. Puis réponds dans `~/m05/e04/notes.md` : pour une VM **clonée**, que devient un réglage que tu n'écris pas (le contrôleur SCSI, par exemple) : garde-t-il la valeur du template, ou prend-il la valeur par défaut du provider ? Que dit la documentation sur la description d'un disque cloné ? Pourquoi `agent.enabled` sur un clone mérite-t-il une attention particulière ?
2. **Trouver l'image.** Sur `pve01`, identifie le VMID du template doré Debian 13 qui porte l'étiquette `current`, et regarde sa configuration (`qm config`) : contrôleur, disque, port série, affichage, étiquettes, notes. Que porterait un clone dont tu n'aurais pas déclaré les étiquettes ? Garde la réponse : E05 la vérifie.
3. **Écrire.** Branche `feat/lab-m05-essai`, ressource dans `main.tf`. `tofu fmt`, `tofu validate`.
4. **Lire le plan.** `tofu plan`. Combien d'attributs affiche-t-il, comparé à ce que tu as écrit ? D'où viennent `timeout_clone`, `purge_on_destroy`, `keyboard_layout` ? Lesquels sont `(known after apply)`, et pourquoi ceux-là ?
5. **Appliquer.** `tofu apply`, en suivant pendant ce temps les tâches dans l'interface de Proxmox (*Tasks*). Combien de temps, quelles étapes (clone, configuration, démarrage, attente de l'agent) ? Puis compare la réalité au plan :
   ```
   root@pve01:~# qm config 2050
   root@pve01:~# qm cloudinit dump 2050 user
   root@pve01:~# pvesh get /cluster/resources --type vm --output-format json | jq '.[] | select(.vmid == 2050)'
   ```
   Le clone est-il vraiment **complet** ? (Regarde le nom du volume du disque.)
6. **Se connecter.** Lis l'adresse dans la sortie `essai_ipv4`. Avant la première connexion, vérifie l'empreinte de la clé d'hôte de la VM **sans passer par le réseau** (agent QEMU, depuis `pve01`), comme en M04-E03. Puis connecte-toi : nom d'hôte complet, `sudo` sans mot de passe, résolveur, place sur `/`.
7. **Plan vide.** Relance `tofu plan`. S'il propose quelque chose, trouve la cause et corrige **le code** (pas la VM), jusqu'à « No changes ».
8. Commit, MR (la sortie du plan de création dans la description), fusion. Puis, depuis `main` à jour, `tofu plan` : vide.

**Critères de réussite**
- [ ] La VM 2050 `m05-essai` existe dans le pool `lab`, démarrée, étiquetée `env-m05` seulement, clone complet de l'image `current`, disque de 10 Go sur `local-nvme`, sur `vsandbox`, sans démarrage automatique.
- [ ] Son agent QEMU répond, elle a une adresse DHCP du VLAN 99, et `adm01` s'y connecte en SSH avec le compte `admin`.
- [ ] La ressource est de type `proxmox_virtual_environment_vm` et le code est formaté (`tofu fmt -check`).
- [ ] `tofu plan` dans `envs/lab-m05` ne propose aucun changement ; le code est sur `main`.

**Vérification** : `lab/bin/check 05 04`

<details><summary>Indice 1</summary>

Dans la documentation de la ressource, cherche les arguments qui ont une valeur par défaut (« defaults to ») : ce sont eux qui s'appliquent quand tu n'écris rien, y compris sur un clone. Compare chacun à la configuration du template.
</details>

<details><summary>Indice 2</summary>

La clé publique d'`adm01` n'est pas un secret : elle peut être lue par la fonction `file()`. Mais `file()` ne comprend pas `~` : il existe une fonction qui le développe.
</details>

<details><summary>Indice 3</summary>

Si le plan après création propose un changement sur un attribut que tu n'as jamais écrit, la valeur lue chez Proxmox diffère de la valeur par défaut du provider : écris cet attribut avec la valeur de l'image. Si l'apply attend 15 minutes puis échoue sur l'agent, regarde si l'agent tourne dans la VM (console série : `qm terminal 2050` sur `pve01`).
</details>

**Pour aller plus loin** (facultatif) : lis la description de la ressource `proxmox_cloned_vm` dans la documentation du provider (gestion « opt-in » : seuls les réglages écrits sont gérés). Quels problèmes de cet exercice résoudrait-elle, et pourquoi n'est-elle pas retenue pour le workbook ?

---

### M05-E05 — Plan, apply, destroy et fichier d'état  `LAB` `★`

> **Ticket PLAT-605** — *De : Nadia Roussel* — *Copie : Karim Benali*
> En astreinte, je vais devoir lire des plans et comprendre ce qu'OpenTofu croit savoir de nos machines. Montre-moi, sur `m05-essai`, les trois cas qu'on rencontre : une modification « sur place », un remplacement, une destruction. Pour chacun : comment on le voit **avant** dans le plan, ce que ça fait vraiment à la VM, et ce qui change dans l'état. Je veux aussi savoir ce qu'il y a dans ce fichier d'état, et pourquoi on me dit qu'il ne faut jamais le toucher.

**Objectifs pédagogiques**
- Distinguer modification sur place, remplacement et destruction, dans le plan et dans la réalité.
- Enregistrer un plan, le lire en JSON, et appliquer exactement ce plan.
- Lire l'état (format, `serial`, `lineage`, attributs) avec les commandes d'OpenTofu, sans jamais l'éditer.
- Constater ce qu'un clone hérite silencieusement de son template.

**Prérequis** : M05-E04.
**Durée indicative** : 2 h.

**Contexte technique**
- Dossier de travail : `~/m05/e05/` (non versionné) : `notes.md` (ton journal), `plan-memoire.tfplan` et `plan-memoire.json` (étape 2), `plan-remplacement.json` (étape 3).
- La mémoire de `m05-essai` passe de 1024 à **2048 Mo** (besoin de Nadia pour ses essais) : c'est l'état attendu à la fin de l'exercice, par MR.
- La VM 2050 est jetable : la remplacer ou la détruire ne coûte que quelques minutes.

**Travail demandé**
1. **L'état.** Avant toute modification, examine l'état **en lecture seule** :
   ```
   admin@adm01:~/src/infra/envs/lab-m05$ tofu state list
   admin@adm01:~/src/infra/envs/lab-m05$ tofu state show proxmox_virtual_environment_vm.essai
   admin@adm01:~/src/infra/envs/lab-m05$ jq '{version, terraform_version, serial, lineage}' terraform.tfstate
   ```
   Journal : à quoi servent `serial` et `lineage` ? La clé publique d'`admin` est-elle dans l'état ? Qu'y trouverait-on si la VM avait un mot de passe cloud-init ? Pourquoi l'état contient-il des attributs que tu n'as jamais écrits ?
2. **Modification sur place.** Passe la mémoire à 2048 Mo. Enregistre le plan, puis exporte-le en JSON :
   ```
   admin@adm01:~/src/infra/envs/lab-m05$ tofu plan -out ~/m05/e05/plan-memoire.tfplan
   admin@adm01:~/src/infra/envs/lab-m05$ tofu show -json ~/m05/e05/plan-memoire.tfplan > ~/m05/e05/plan-memoire.json
   admin@adm01:~/m05/e05$ jq '.resource_changes[] | {address, actions: .change.actions}' plan-memoire.json
   ```
   Applique **ce** plan (`tofu apply ~/m05/e05/plan-memoire.tfplan`). La VM a-t-elle redémarré (`uptime` dans la VM, tâches de Proxmox) ? Pourquoi, alors que le plan annonçait une modification « sur place » ? Quel argument de la ressource règle ce comportement ? Relance `tofu apply` avec le même fichier de plan : que se passe-t-il, et pourquoi est-ce une protection ?
3. **Remplacement.** Deux façons de le provoquer :
   - change le `vm_id` en 2051 et lance un plan **sans l'appliquer** ; enregistre-le et exporte-le en JSON dans `~/m05/e05/plan-remplacement.json`. Quelle ligne du plan dit pourquoi la VM serait remplacée ? Remets 2050 ;
   - demande explicitement le remplacement : `tofu plan -replace=proxmox_virtual_environment_vm.essai`, puis `tofu apply -replace=…`. Dans quel ordre la destruction et la création ont-elles lieu ? Reconnecte-toi en SSH : que dit ton client, pourquoi, et comment le traites-tu proprement (pas avec `StrictHostKeyChecking=no`) ? L'adresse IP a-t-elle changé ?
4. **Destruction.** `tofu plan -destroy` (lis-le), puis `tofu destroy`. Vérifie sur `pve01` (`qm list`). Que contient maintenant l'état (`tofu state list`, `serial`) ? Que contient `terraform.tfstate.backup` ?
5. **L'héritage silencieux.** Commente la ligne `tags` de la ressource et **recrée** la VM (`tofu apply -replace=proxmox_virtual_environment_vm.essai` ; un simple `apply` ne ferait que retirer les étiquettes de la VM existante). Que montre `qm config 2050 | grep tags` ? Que dit `tofu plan` ? Explique l'écart dans le journal (la documentation et la section *Cloning* aident), puis rétablis la ligne et applique. Quelles conséquences aurait eues cette VM pour l'inventaire dynamique d'Ansible (M04-E13) et pour toute recherche de l'image « current » par étiquette ?
6. **Le verrou local.** Pendant un `tofu apply` (une modification de la description, par exemple), lance un `tofu plan` dans un second terminal. Quel fichier apparaît dans le dossier pendant l'apply ? Ce verrou protégerait-il d'un `apply` lancé en même temps depuis `runner01` ?
7. Commit (mémoire à 2048 Mo), MR avec le plan, fusion, plan vide depuis `main`.

**Critères de réussite**
- [ ] `~/m05/e05/plan-memoire.json` décrit une modification sur place de `proxmox_virtual_environment_vm.essai` (mémoire de 1024 à 2048 Mo).
- [ ] `~/m05/e05/plan-remplacement.json` décrit un remplacement de la même ressource.
- [ ] `notes.md` répond aux questions des étapes 1 à 6.
- [ ] La VM 2050 existe, avec 2048 Mo et la seule étiquette `env-m05` ; l'état local a une sauvegarde et un `serial` qui reflète tes opérations ; `tofu plan` est vide ; le code est sur `main`.

**Vérification** : `lab/bin/check 05 05`

<details><summary>Indice 1</summary>

Dans le JSON d'un plan, `resource_changes[].change.actions` vaut `["update"]`, `["delete","create"]`, `["create","delete"]`, `["delete"]`… et `action_reason` dit pourquoi une ressource est remplacée. `change.before` et `change.after` contiennent les valeurs avant et après.
</details>

<details><summary>Indice 2</summary>

« Sur place » veut dire que la ressource garde son identité (même VM, même disque), pas que l'opération est invisible. Cherche dans la documentation de la ressource l'argument qui autorise le provider à redémarrer la VM pendant une mise à jour, et ce que Proxmox exige pour ajouter de la mémoire à chaud.
</details>

<details><summary>Indice 3</summary>

Pour l'héritage des étiquettes : lis dans la documentation ce que fait le provider des réglages d'un clone **que la configuration ne mentionne pas**. Il ne les lit pas, donc il ne peut pas les voir changer.
</details>

**Pour aller plus loin** (facultatif) : `tofu plan -refresh-only` et `tofu apply -refresh-only` : arrête la VM à la main (`qm shutdown 2050`), compare les deux plans (normal et `-refresh-only`), redémarre-la. Dans quelle situation un `apply -refresh-only` est-il la bonne réponse, et dans quelle situation est-il une faute ?

---

### M05-E06 — Variables, `locals`, sorties, types et validations  `LAB` `★★`

> **Ticket PLAT-606** — *De : Karim Benali* — *Copie : Lucas Martin*
> J'ai refusé la MR de Lucas qui copiait `main.tf` pour créer une deuxième VM en changeant trois valeurs à la main. Avant toute copie, l'environnement doit être **paramétré** : les valeurs du lab dans `terraform.tfvars`, des variables typées et décrites, et des garde-fous qui refusent au plan ce qui pourrait abîmer autre chose que l'environnement (un VMID du socle, le mauvais pool, une étiquette réservée). Et un refactoring, ça ne doit rien changer : je veux un plan **vide** à la fin.

**Objectifs pédagogiques**
- Déclarer des variables typées (types simples et objets avec attributs optionnels), avec description et validations.
- Utiliser `locals` pour calculer une valeur une seule fois, et des sorties structurées.
- Connaître l'ordre de priorité des sources de valeurs de variables, et le vérifier.
- Refactorer une configuration sans changer l'infrastructure (plan vide).

**Prérequis** : M05-E05.
**Durée indicative** : 2 h.

**Contexte technique**
- Fichiers de `envs/lab-m05/` : `variables.tf`, `locals.tf`, `outputs.tf`, `terraform.tfvars` (versionné, rien de secret), `main.tf` réécrit avec ces valeurs. La source de données `proxmox_version` et sa sortie peuvent rester.
- Variables (noms contractuels : la vérification et les exercices suivants s'en servent) :

| Variable | Type | Défaut | Garde-fou exigé |
|---|---|---|---|
| `noeud` | chaîne | aucun | non nulle |
| `pool` | chaîne | `lab` | seul `lab` est accepté |
| `stockage_vm` | chaîne | `local-nvme` | — |
| `vnet` | chaîne | `vsandbox` | seul `vsandbox` est accepté pour un environnement |
| `environnement` | chaîne | `m05` | format `mNN` |
| `etiquettes_supplementaires` | liste de chaînes | vide | format des étiquettes Proxmox ; refuse `socle`, `role-…`, `gold`, `current`, `base` |
| `image_vmid` | nombre | aucun | plage des images dorées Debian 13 (PLAN §4.8) |
| `cles_ssh_admin` | liste de chaînes | aucun | au moins une ; chaque élément est une clé **publique** OpenSSH |
| `vm_essai` | objet : `vmid`, `nom`, et facultatifs `coeurs` (2), `memoire_mo` (2048), `disque_go` (10) | aucun | VMID 2050-2059 ; nom `m05-…` valide comme nom d'hôte ; 1 à 4 vCPU ; 512 à 8192 Mo par multiples de 256 ; disque de 10 à 100 Go |

- Valeurs locales : le domaine, le résolveur, la liste triée et dédoublonnée des étiquettes (`env-<environnement>` plus les supplémentaires), la description.
- Sortie `essai` : un objet `{ vmid, fqdn, ipv4 }` (`ipv4` = première adresse non locale, ou `null` si l'agent n'a encore rien dit).

**Travail demandé**
1. Écris `variables.tf` : type, description, validations avec un message qui dit **quoi faire**. Écris `terraform.tfvars` avec les valeurs du lab (la clé publique d'`adm01` passe du `file()` de E04 à la variable : pourquoi est-ce mieux pour le futur pipeline ?).
2. Écris `locals.tf` et `outputs.tf`, réécris `main.tf`. Puis `tofu plan` : il doit être **vide**. S'il ne l'est pas, ton refactoring a changé une valeur : trouve laquelle.
3. **Les garde-fous.** Prouve que chacun refuse ce qu'il doit refuser, au plan, sans rien appliquer :
   ```
   admin@adm01:~/src/infra/envs/lab-m05$ tofu plan -var 'vm_essai={vmid=1004, nom="m05-essai"}'
   ```
   Fais de même pour un nom invalide, 1000 Mo de mémoire, une liste de clés vide, l'étiquette `socle`, le pool `production`. Note chaque message. À quel moment du plan la validation intervient-elle : avant ou après la connexion à l'API ?
4. **Explorer.** `tofu console` (depuis le dossier, avec les accès chargés) : affiche `var.vm_essai` (que sont devenus les attributs facultatifs ?), `local.etiquettes`, puis essaie `type(var.vm_essai)`, `[for k in var.cles_ssh_admin : split(" ", k)[2]]`, `proxmox_virtual_environment_vm.essai.ipv4_addresses`. Quelle est la structure de `ipv4_addresses`, et pourquoi la sortie `essai.ipv4` est-elle écrite ainsi ?
5. **Priorités.** Prédis, puis vérifie avec `tofu console`, la valeur de `var.environnement` dans chaque cas : `TF_VAR_environnement=m99` exporté ; en plus, un fichier `essai.auto.tfvars` contenant `environnement = "m98"` ; en plus, `-var environnement=m97` ; puis `-var-file` d'un fichier qui dit `m96`, placé avant puis après `-var`. Retire ensuite le fichier `essai.auto.tfvars`. Résume l'ordre dans le journal (`~/m05/e06/notes.md`).
6. **Sensible.** Ajoute temporairement `sensitive = true` à la sortie `essai`. Compare `tofu output`, `tofu output -json` et `jq '.outputs.essai' terraform.tfstate`. Conclusion pour Sophie ? Retire-le.
7. Commit, MR (plan vide dans la description : c'est l'argument de la revue), fusion.

**Critères de réussite**
- [ ] Les variables du tableau existent avec leur type ; `terraform.tfvars` est sur `main` et ne contient aucun secret.
- [ ] Un plan avec un VMID hors 2050-2059, un nom invalide, une mémoire hors règle, une liste de clés vide ou une étiquette réservée est refusé avant toute création, avec un message explicite.
- [ ] La sortie `essai` donne le VMID, le nom complet et l'adresse IPv4 de `m05-essai`.
- [ ] `tofu plan` est vide (le refactoring n'a rien changé) et le code est sur `main`.

**Vérification** : `lab/bin/check 05 06`

<details><summary>Indice 1</summary>

Un attribut d'objet se déclare facultatif avec `optional(type, défaut)` dans la contrainte de type : la valeur reçue contient alors toujours l'attribut, avec la valeur par défaut s'il est omis. Plusieurs blocs `validation` peuvent coexister dans une variable ; chacun a sa condition et son message.
</details>

<details><summary>Indice 2</summary>

Pour tester une liste dans une validation : `alltrue([for x in liste : condition])`, `anytrue(…)`, `can(regex(…))`. Pour un ensemble interdit : `setintersection` ou `contains`. Une validation peut-elle citer une autre variable ? Essaie, et regarde ce que dit OpenTofu.
</details>

<details><summary>Indice 3</summary>

La page *Input Variables* de la documentation donne l'ordre de priorité des sources (variables d'environnement, `terraform.tfvars`, `*.auto.tfvars`, `-var` et `-var-file` sur la ligne de commande). Pour les deux dernières, l'ordre **sur la ligne de commande** compte.
</details>

**Pour aller plus loin** (facultatif) : déclare `noeud` avec `const = true` (OpenTofu 1.12) et lis la page *Input Variables* : à quoi servent les variables constantes, et où une variable ordinaire est-elle refusée (backend, sources de modules) ?

---

### M05-E07 — `count`, `for_each` et blocs dynamiques  `LAB` `★★`

> **Ticket DEV-607** — *De : Julien Petit* — *Copie : Karim Benali*
> Pour les tests de charge de MédiAgenda, il me faudrait trois serveurs d'application jetables, `app01` à `app03`, avec des disques de données différents selon le serveur (aucun pour `app01`, un pour `app02`, deux pour `app03`). Et surtout : la semaine prochaine j'en rendrai un, peut-être celui du milieu. Je ne veux pas que rendre `app02` touche aux deux autres.

**Objectifs pédagogiques**
- Créer plusieurs instances d'une ressource avec `count` et avec `for_each`, et comprendre leurs adresses.
- Choisir entre les deux selon ce qui identifie une instance.
- Générer des blocs imbriqués variables avec `dynamic`.
- Prévoir l'effet d'une modification de la liste avant de l'appliquer.

**Prérequis** : M05-E06.
**Durée indicative** : 2 h.

**Contexte technique**
- Bac à sable : [`ressources/M05-E07/compteur/`](../ressources/M05-E07/compteur/), une configuration **sans provider externe** (ressource intégrée `terraform_data`) : rien n'est créé sur `pve01`. Copie-le dans `~/m05/e07/compteur/` et travaille dans la copie.
- Nouvelle variable `vms_app` (nom contractuel), dictionnaire dont la clé est le nom court (`app01`…) et la valeur un objet : `vmid`, et facultatifs `coeurs` (2), `memoire_mo` (1024), `disques_donnees` (liste de tailles en Go, vide par défaut). Garde-fous : clés au format `appNN`, VMID 2050-2059, VMID tous différents entre eux et de celui de la VM d'essai, au plus 3 disques de 1 à 20 Go.
- Valeurs : `app01` → 2051, aucun disque ; `app02` → 2052, un disque de 2 Go ; `app03` → 2053, deux disques de 2 et 3 Go.
- Ressource `proxmox_virtual_environment_vm.app`, même modèle que `m05-essai` (nom `m05-<clé>`, mêmes étiquettes, 10 Go système), plus un disque `scsi1`, `scsi2`… sur `local-nvme` par disque de données, avec les mêmes options que le disque système. Sortie `apps` : nom → `{ vmid, ipv4 }`.
- Mémoire de `pve01` : trois VMs de 1 Go de plus, détruites en fin de module.

**Travail demandé**

*Partie A — le bac à sable*

1. Lis `main.tf`, `tofu init`, `tofu apply`. Note les adresses des instances (`tofu state list`).
2. Prédis, puis vérifie avec `tofu plan -var 'serveurs=["app01","app03"]'`, ce que devient le retrait de `app02`. Lis attentivement le plan : quelle instance est modifiée, laquelle est détruite, et quel serait le résultat **réel** si c'étaient des VMs (nom, VMID, données) ?
3. Réécris la configuration avec `for_each` (la variable devient un dictionnaire nom → VMID). Avant d'appliquer, lance un plan : que propose OpenTofu pour les instances existantes, et pourquoi ? (Applique-le : ce sont des `terraform_data`.) Puis refais l'essai de retrait de `app02`.
4. Journal (`~/m05/e07/notes.md`) : dans quels cas `count` reste-t-il le bon choix ? Une règle simple pour choisir ?

*Partie B — les serveurs de Julien*

5. Ajoute `vms_app` et ses garde-fous, la ressource `app` avec `for_each`, ses disques de données par un bloc `dynamic "disk"`, et la sortie `apps`. Dans le bloc `dynamic`, sur quoi itères-tu, et quelle clé donne l'interface (`scsi1`, `scsi2`) ?
6. `tofu plan` : vérifie que seules trois VMs sont créées et que `m05-essai` n'est pas touchée. Applique. Dans chaque VM, `lsblk` : les disques de données sont-ils là, à la bonne taille ?
7. **Prévoir sans appliquer.** Pour chacun de ces changements, enregistre le plan, lis-le, note le résultat, puis **reviens en arrière** sans appliquer :
   - Julien rend `app02` ;
   - `app03` passe son second disque de 3 à 4 Go ;
   - `app03` passe son second disque de 3 à 2 Go (le plan l'accepte-t-il ? que dit la documentation de Proxmox sur la réduction d'un disque ? et l'`apply`, à ton avis ?) ;
   - `app03` retire son **premier** disque (`[3]` au lieu de `[2, 3]`) : que devient le contenu des disques ? Quel parallèle avec la partie A ?
8. Commit, MR, fusion, plan vide depuis `main`.

**Critères de réussite**
- [ ] Le bac à sable est passé à `for_each` ; `notes.md` décrit les plans de retrait avec `count` et avec `for_each`, et le résultat des quatre plans de l'étape 7.
- [ ] Les VMs 2051-2053 `m05-app01` à `m05-app03` existent, étiquetées `env-m05`, sur `vsandbox` ; 2052 a un disque `scsi1` de 2 Go, 2053 des disques `scsi1` de 2 Go et `scsi2` de 3 Go, 2051 aucun disque de données.
- [ ] Les instances sont adressées par clé (`proxmox_virtual_environment_vm.app["app01"]`…) ; les disques de données sont produits par un bloc `dynamic`.
- [ ] `tofu plan` est vide et le code est sur `main`.

**Vérification** : `lab/bin/check 05 07`

<details><summary>Indice 1</summary>

Avec `count`, l'identité d'une instance est sa **position** ; avec `for_each`, c'est sa **clé**. Retirer un élément d'une liste décale toutes les positions qui suivent.
</details>

<details><summary>Indice 2</summary>

`for_each` d'un bloc `dynamic` accepte une liste ou un dictionnaire ; l'itérateur porte le nom du bloc (`disk.key`, `disk.value`). Une expression `for` avec index (`for i, t in liste : …`) construit un dictionnaire dont la clé peut être le nom de l'interface.
</details>

<details><summary>Indice 3</summary>

Passer d'une ressource avec `count` à la même ressource avec `for_each` change toutes les adresses : sans indication, OpenTofu ne sait pas que `[0]` est devenu `["app01"]`. Le palier 2 (E17) montre comment le lui dire ; ici, le bac à sable permet de le constater sans dommage.
</details>

**Pour aller plus loin** (facultatif) : le méta-argument `enabled` (OpenTofu 1.11, dans `lifecycle`) crée zéro ou une instance sans changer l'adresse de la ressource. Ajoute à la VM d'essai une variable `vm_essai_active` (vrai par défaut) qui la contrôle : en quoi est-ce préférable à `count = var.vm_essai_active ? 1 : 0` ?

---

### M05-E08 — Sources de données : trouver l'image dorée courante  `LAB` `★★`

> **Ticket PLAT-608** — *De : Karim Benali*
> Le VMID de l'image dorée est écrit en dur dans `terraform.tfvars`. Chaque lundi, la chaîne du module 03 publie une nouvelle image et déplace l'étiquette `current` : il faudrait une MR par semaine juste pour changer un nombre, et le jour où on l'oublie, on clone une image retirée. Je veux que la configuration **demande** à Proxmox quelle est l'image courante. Mais je ne veux pas non plus que nos VMs soient détruites et recréées tous les lundis parce que l'image a changé.

**Objectifs pédagogiques**
- Lire l'infrastructure existante avec une source de données, filtrée par étiquettes et attributs.
- Protéger une lecture par une postcondition : échouer tôt, avec un message utile, quand la réalité n'est pas celle attendue.
- Empêcher qu'une valeur lue (qui change hors de ton contrôle) ne provoque des remplacements, avec `lifecycle { ignore_changes }`, et savoir déclencher volontairement un remplacement.
- Ajouter un contrôle non bloquant avec un bloc `check`.

**Prérequis** : M05-E07 ; M03-E10 (publication et étiquette `current`).
**Durée indicative** : 1 h 30.

**Contexte technique**
- Source de données du provider : `proxmox_virtual_environment_vms` (liste de VMs filtrée par étiquettes et par `filter { name, values, regex }`). La source `proxmox_virtual_environment_vm` (une seule VM) est **dépréciée** depuis la version 0.101 du provider : ne l'utilise pas.
- L'image cherchée : un **template** portant les étiquettes `gold`, `debian13` et `current`, nommé `deb13-gold-AAAAMMJJ-N` ; il doit y en avoir **exactement un**.
- Fichier `envs/lab-m05/data.tf` (sources de données), valeur locale `image_vmid`, sortie `image_source` (`{ vmid, nom }` de l'image trouvée). La variable `image_vmid` de E06 disparaît, de `variables.tf` comme de `terraform.tfvars`.
- Contrôle non bloquant : avertir quand il reste moins de 50 Gio libres sur `local-nvme` (source de données `proxmox_datastores`).

**Travail demandé**
1. **Explorer.** Ajoute la source de données (sans encore t'en servir) et regarde ce qu'elle renvoie : `tofu plan`, puis `tofu console` → `data.proxmox_virtual_environment_vms.image_courante.vms`. Essaie d'abord avec les seules étiquettes : qu'est-ce qui pourrait, un jour, apparaître dans cette liste en plus du template (souviens-toi de E05) ? Ajoute les filtres qui l'en empêchent.
2. **Échouer tôt.** Ajoute une postcondition qui exige exactement une image, avec un message qui dit quoi vérifier. Teste-la en faussant temporairement une étiquette du filtre (`curent`) : que dit le plan, et à quel moment s'arrête-t-il ?
3. **Brancher.** Remplace `var.image_vmid` par la valeur locale dans les deux ressources, supprime la variable, ajoute la sortie `image_source`. `tofu plan` : vide si l'image `current` est celle que tu avais écrite en dur ; sinon, que propose-t-il ? N'applique **rien** qui détruise une VM.
4. **Le lundi suivant.** Simule une nouvelle publication **sans toucher au catalogue** : fais pointer temporairement le filtre sur l'image de base (`tpl-debian13-base`, étiquettes `base` et `debian13`, sans contrainte de nom). Lis le plan : combien de VMs seraient remplacées, et pourquoi (quelle propriété de l'argument `clone` du provider) ? Ajoute à chaque ressource ce qui fait ignorer ce changement, relance le plan, puis remets le vrai filtre. Journal (`~/m05/e08/notes.md`) : comment fera-t-on passer, volontairement, une VM sur la nouvelle image ? Quelle information l'état garde-t-il alors de l'image d'origine de chaque VM, et est-elle encore vraie ?
5. **Contrôle.** Ajoute le bloc `check` sur la place libre. Essaie-le avec un seuil absurde (10 Tio) : un plan avec un `check` en échec peut-il être appliqué ? Remets 50 Gio. Quand préfère-t-on un `check` à une postcondition ?
6. **Droits.** Journal : la source de données liste les VMs que le **jeton** voit. Que se passerait-il si l'image courante était, par erreur, sortie du pool `lab` : erreur de droits, ou autre chose ? Quel message obtiendrais-tu ?
7. Commit, MR, fusion, plan vide depuis `main`.

**Critères de réussite**
- [ ] Aucune configuration de `envs/lab-m05` ne contient plus de VMID de template en dur ; l'image vient de `proxmox_virtual_environment_vms`, filtrée sur les trois étiquettes et sur les templates, protégée par une postcondition.
- [ ] Les deux ressources de VM ignorent les changements de leur bloc `clone` ; un bloc `check` surveille la place libre de `local-nvme`.
- [ ] La sortie `image_source` désigne le template doré Debian 13 qui porte aujourd'hui l'étiquette `current`.
- [ ] `tofu plan` est vide et le code est sur `main`.

**Vérification** : `lab/bin/check 05 08`

<details><summary>Indice 1</summary>

Les filtres de `proxmox_virtual_environment_vms` portent sur `name`, `template`, `status` et `node_name` ; les étiquettes passent par l'argument `tags`, où la VM doit porter **toutes** les étiquettes demandées. Les valeurs d'un filtre sont des chaînes : `values = [true]` est converti.
</details>

<details><summary>Indice 2</summary>

Une postcondition se place dans un bloc `lifecycle` de la source de données et y désigne le résultat par `self`. Son message d'erreur peut contenir une interpolation (le nombre trouvé, par exemple).
</details>

<details><summary>Indice 3</summary>

`ignore_changes` prend une liste d'attributs ou de blocs de la ressource, sans guillemets. Pour remplacer volontairement une instance, relis l'étape 3 de E05.
</details>

**Pour aller plus loin** (facultatif) : ajoute une sortie qui liste, pour chaque VM de l'environnement, l'image dont elle a été clonée (attribut `clone` de l'état) et signale celles qui ne sont plus sur l'image courante. Ce serait la base d'un rapport « VMs à rafraîchir » pour Nadia.

---

### M05-E09 — Questions : OpenTofu, Terraform et l'état  `Q` `★★`

> **Ticket PLAT-609** — *De : Karim Benali*
> Avant le palier 2, où l'état part sur `s3-01` et où on touche au socle, je veux être sûr que tu as compris ce que tu as manipulé. Quinze questions, par écrit, avec tes propres exemples tirés de `envs/lab-m05` quand c'est possible.

**Objectifs pédagogiques**
- Consolider la compréhension de l'état, du plan et du cycle de vie des ressources.
- Situer OpenTofu par rapport à Terraform et aux autres outils de la plateforme.

**Prérequis** : M05-E02 à M05-E08.
**Durée indicative** : 1 h 30.

**Travail demandé**

Réponds aux 15 questions, en t'appuyant sur ce que tu as observé.

1. Que fait le rafraîchissement (*refresh*) au début d'un plan ? Que change `tofu plan -refresh=false`, et quand est-ce dangereux ? À quoi sert `-refresh-only` ?

2. À quoi servent `serial` et `lineage` dans l'état ? Décris un scénario où, sans eux, deux personnes écraseraient l'état l'une de l'autre.

3. Ton `.terraform.lock.hcl` contient de nombreuses empreintes pour une seule version du provider. Que sont les empreintes `h1:` et `zh:` ? Que se passe-t-il si `runner01` tourne un jour sur une autre architecture ? Que garantit le fichier de verrouillage, et que ne garantit-il pas sur l'origine du provider ?

4. Une valeur sensible (un mot de passe cloud-init passé par une variable `sensitive`) : cite tous les endroits où elle peut se retrouver en clair. Qu'apportent les valeurs **éphémères** et les attributs *write-only* d'OpenTofu 1.11 ?

5. Cite trois arguments de `proxmox_virtual_environment_vm` qui forcent le remplacement de la VM. Pourquoi `lifecycle { create_before_destroy = true }` n'aide-t-il pas pour une VM dont le VMID est fixé dans le code ?

6. Un `apply` échoue au milieu : deux VMs sur quatre ont été créées, la troisième a été clonée mais son démarrage a échoué. Que contient l'état ? Que proposera le plan suivant pour chacune des quatre ? Que signifie *tainted* ?

7. Compare `tofu state rm`, le bloc `removed {}` et `lifecycle { destroy = false }` (OpenTofu 1.12). Lequel laisserait une trace relue en MR ?

8. Terraform 1.16 peut-il lire un état produit par OpenTofu 1.13 ? Et un état chiffré par OpenTofu ? Quelles précautions si MédiSphère devait un jour changer d'outil, dans un sens ou dans l'autre ?

9. Qu'est-ce qu'un fichier `.tofu`, et que se passe-t-il si `main.tf` et `main.tofu` coexistent ? Le bloc `language` (OpenTofu 1.12) remplace-t-il `terraform {}` ? Pourquoi le projet garde-t-il `terraform { required_version … }` pour l'instant ?

10. Le provider `bpg/proxmox` est en 0.x. Comment lis-tu son `CHANGELOG.md` avant une montée de version ? Trouve deux « BREAKING CHANGES » des versions 0.100 à 0.115 et dis si elles auraient touché `envs/lab-m05`. Que t'apprend un avertissement de dépréciation affiché par `tofu plan` ?

11. En E05, une VM clonée sans étiquettes déclarées a hérité de celles du template sans que le plan le signale. Pourquoi le provider se comporte-t-il ainsi ? Cite deux autres réglages hérités qui pourraient poser le même problème, et la règle que tu en tires.

12. *(QCM)* Dans quel cas `tofu apply -target=ADRESSE` est-il acceptable ?
    - A. Pour aller plus vite quand le plan complet est long
    - B. En situation exceptionnelle (réparer une ressource pendant un incident), en sachant que l'état et le code peuvent rester désalignés, et en relançant un plan complet juste après
    - C. Pour éviter qu'un collègue voie les autres changements de la MR
    - D. Jamais : l'option n'existe plus dans OpenTofu

13. `on_boot` vaut `true` par défaut dans le provider, alors que Proxmox ne démarre pas une VM au boot si on ne le lui demande pas. Pourquoi est-ce important pour les VMs d'environnement, et pour les VMs du socle qu'on importera en E16 ?

14. Qui fait quoi : Packer (M03), cloud-init, OpenTofu, Ansible (M04). Pour chacun de ces réglages, dis quel outil en est responsable et pourquoi : la version de chrony, l'adresse IP de `s3-01`, l'utilisateur `admin` et sa clé, la mémoire d'une VM, la configuration de SeaweedFS, la CA provisoire dans le magasin de certificats.

15. Le verrou de l'état local (`.terraform.tfstate.lock.info`) : que protège-t-il, que ne protège-t-il pas ? Pourquoi `-lock=false` est-il presque toujours une faute ?

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 15 questions avant d'ouvrir le corrigé, avec des exemples tirés de ton environnement.
- [ ] Tu as noté chaque réponse avec la grille (0, 1 ou 2 points) et calculé ton score sur 30.

<details><summary>Indice 1</summary>

Pour les questions 3 et 10, ouvre les fichiers : ton `.terraform.lock.hcl`, et le `CHANGELOG.md` du provider sur son dépôt. Pour la question 8, la documentation d'OpenTofu a une page sur la migration depuis Terraform.
</details>

<details><summary>Indice 2</summary>

Pour la question 6, rappelle-toi ce qu'OpenTofu écrit dans l'état après **chaque** ressource traitée, et pas seulement à la fin de l'`apply`.
</details>

**Pour aller plus loin** (facultatif) : lis la page *Internals / JSON Output Format* de la documentation et écris, avec `jq`, la commande qui liste depuis un plan enregistré toutes les ressources qui seraient détruites ou remplacées. Elle servira de garde-fou au pipeline (E26).
