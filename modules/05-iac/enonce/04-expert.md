# Module 05 — Palier 4 : Expert

L'infrastructure du socle est déclarée : `plateforme/infra` décrit les VMs permanentes, l'état est sur `s3-01`, chiffré, verrouillé et versionné, les modules sont publiés par version, chaque MR montre son plan et l'apply passe par un job protégé. Claire Morel en tire la conséquence habituelle : « Désormais, quand OpenTofu se trompe, il se trompe sur tout le socle à la fois. Un plan faux qu'on applique, c'est un incident majeur. » Karim Benali a préparé des pannes, toutes vécues un jour par une équipe qui fait de l'IaC : un plan qui veut recréer une VM permanente, un verrou que personne ne lâche, un backend qu'on n'atteint plus, un apply refusé par Proxmox, une VM créée mais injoignable, un état qui ne décrit plus la réalité, un plan cassé sans le moindre commit, et l'état qui disparaît. Une astreinte les combine. Puis tu descends sous le capot : le graphe, le dialogue entre OpenTofu et son provider, la structure de l'état.

La méthode est celle des modules précédents : observer avant d'agir, formuler une hypothèse, la tester par la mesure la moins invasive, corriger à la racine, prévenir la récidive. Avec trois règles propres à l'IaC :
- **Le plan est la preuve, pas l'apply.** Tant que tu n'as pas un plan que tu comprends ligne à ligne, tu n'appliques rien. Un plan qui détruit, remplace ou importe quelque chose que personne n'a demandé est un **incident**, pas un détail.
- **L'état est une donnée de production.** Il se sauvegarde avant d'être modifié, il ne se modifie qu'avec les commandes prévues pour cela (`tofu state …`, `import`, `moved`, `removed`), il ne s'édite jamais à la main, et une copie en clair (`tofu state pull`) contient des secrets : elle se traite comme tel.
- **Un verrou appartient à quelqu'un.** Avant de le forcer, tu prouves que son détenteur n'existe plus.

> **Rappels** : tout se lance depuis `adm01`, dans le clone `~/src/infra` (variable `WB_SRC`) : configurations `socle/` (état `socle/terraform.tfstate`) et `envs/lab-m05/` (état `envs/lab-m05/terraform.tfstate`), compartiment `tofu-state` de `s3-01` (`https://s3-01.par1.medisphere.internal:8333`, versionné). L'environnement de travail se charge comme au palier 3 : `~/.config/workbook/pve-tofu.env`, `~/.config/workbook/s3-tofu.env`, phrase de chiffrement de l'état lue dans `~/.config/workbook/tofu-chiffrement.pass` (M05-E27). Client S3 : AWS CLI v2, profil `s3-socle` (M05-E10). Tout correctif durable passe par une MR fusionnée dans `main`, plan relu et pipeline vert.

## Règles du jeu des pannes (M05-E35 à M05-E43)

- Les pannes s'injectent **depuis `adm01`**, à la racine de ta copie du workbook :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ lab/bin/break 05 35
  ```
  Le script tire une variante au hasard et n'affiche que le **symptôme**, comme un ticket. Chaque panne a 3 ou 4 variantes : refais l'exercice jusqu'à les avoir toutes rencontrées (`--variante N` force une variante, sans dire laquelle est laquelle). Si une variante n'a pas d'effet sur ton lab (selon tes choix d'écriture du code), le script en essaie une autre.
- **Avant d'injecter**, lance le contrôle de l'exercice (`lab/bin/check 05 35`) : il doit être vert. Une panne posée sur un lab déjà malade fausse tout le diagnostic. Exceptions : les contrôles de M05-E38, E39 et E40 vérifient aussi ce que demande le ticket (une VM d'environnement de plus) ; ils sont verts avant l'injection et doivent le redevenir **avec** la VM demandée.
- **Ta copie de travail `~/src/infra` doit être propre** (`git status` sans modification) et **les plans de `socle/` et de `envs/lab-m05/` doivent être vides** : l'injection le vérifie. Plusieurs pannes modifient cette copie de travail comme le ferait un collègue qui travaille sur `adm01` (Lucas a un compte sur le bastion) : fichiers modifiés ou ajoutés, **jamais** de commit.
- **Ne lis pas** les scripts de `corrige/pannes/`, ni `/var/lib/workbook/` sur les hôtes, ni `~/.local/state/workbook/` sur `adm01` : ils contiennent la cause.
- Une seule panne active à la fois par exercice. Si tu abandonnes : `lab/bin/break 05 35 --annuler` remet l'état sain (filet de sécurité, pas un correctif : compte l'exercice comme non réussi). **Quand tu as réparé**, lance aussi `--annuler` pour **clore** la panne (sinon elle reste marquée active et bloque la suivante, l'astreinte E43 et le mini-projet) : l'annulation ne rétablit que ce qui est encore dans l'état cassé et ne revient jamais sur ta réparation.
- Ce que les pannes touchent : l'**état distant** (toujours après une copie de l'objet et de la liste de ses versions dans `/var/lib/workbook/` sur `adm01`, jamais de suppression sans copie), ta copie de travail `~/src/infra` (sauvegardée), `~/.config/workbook/` (sauvegardé), les droits du compte `wb-tofu@pve` et les étiquettes des images dorées sur `pve01`, la passerelle S3 de `s3-01` (fichiers sauvegardés), `/etc/hosts` de `adm01`, la configuration de `dnsmasq` sur `dns01`, des règles nftables **temporaires** sur `gw01` (ajoutées à chaud, jamais dans `/etc/nftables.conf`), les VMs d'environnement 2050-2059. Jamais le réseau de `pve01`, son pare-feu, une VM hors du pool `lab` ni une VM permanente.
- **Tiens un journal de diagnostic** pour chaque panne, dans `docs/socle/journal/` de `~/medisphere` (publié par MR) : heure, hypothèse, commande, résultat observé, conclusion. Il alimente le post-mortem de M05-E43.
- Le **temps cible** est indicatif. Le dépasser n'est pas un échec ; corriger sans comprendre en est un.

> ⚠️ **Aucun `tofu apply` « pour voir »**. Plusieurs pannes de ce palier produisent un plan qui **détruit** une VM, importe une VM permanente à une mauvaise adresse ou recrée tout le socle. Ici, `tofu plan` est ton instrument de mesure ; `apply` n'arrive qu'à la fin, sur un plan relu. Les VMs du socle portent `prevent_destroy` et la protection Proxmox (`protection = true`) : ce sont des filets, pas une méthode.

> ⚠️ **Une copie de l'état en clair contient des secrets.** `tofu state pull` déchiffre l'état (M05-E27) : si tu en as besoin, écris-le dans un fichier en `600` (`umask 077`), hors de tout dépôt, et supprime-le à la fin (`shred -u`). Les pannes et le contrôle de M05-E44 vérifient qu'aucune copie ne traîne.

> ⚠️ **Interdits pendant ces pannes** : `-lock=false` sur une commande qui écrit l'état, `tofu state push -force`, désactiver la vérification TLS, mettre une adresse IP à la place d'un nom dans le backend, élargir les droits de `wb-tofu` « pour que ça passe ». Si tu penses en avoir besoin, c'est que ton diagnostic n'est pas fini.

---

### M05-E35 — Panne : le plan veut recréer une VM du socle  `BF` `★★★`

> **Ticket INC-3241** — *De : Karim Benali*
> Je relisais le plan du socle avant la fusion d'une petite MR (une sortie en plus) et je n'en crois pas mes yeux : `tofu plan` dans `~/src/infra/socle` veut détruire (ou remplacer) une de nos VMs permanentes, ou s'arrête sur une erreur de `prevent_destroy`. Hier soir, le même plan était vide. Personne n'a fusionné quoi que ce soit dans `main` depuis.
> Ne lance **aucun** apply. Trouve ce qui a changé, ramène le plan à « No changes » sans recréer aucune VM, et dis-moi quel garde-fou aurait dû nous prévenir.

**Objectifs pédagogiques**
- Lire un plan qui remplace une ressource : `-/+`, `# forces replacement`, `(tainted)`, « because … is not in configuration », et remonter à l'**entrée** qui a changé (code, variables, état, réalité).
- Connaître les sources de vérité d'un plan et leur ordre : fichiers `.tf`, fichiers de **surcharge** (`*_override.tf`), valeurs de variables (`terraform.tfvars`, `*.auto.tfvars`, `TF_VAR_*`, `-var`), état distant, réalité lue au rafraîchissement.
- Réparer l'état avec la bonne commande (`state mv`, `untaint`, bloc `moved`) après sauvegarde, sans jamais recréer ce qui tourne.

**Prérequis** : M05-E05, M05-E06, M05-E16, M05-E17, M05-E22 ; `lab/bin/check 05 35` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Injection** : `lab/bin/break 05 35` (4 variantes ; l'injection lance un plan complet du socle : une à deux minutes).

**Travail demandé**
1. Reproduis le symptôme. Note dans ton journal, mot pour mot, la ligne du plan (ou de l'erreur) qui annonce la destruction : quelle **adresse** de ressource, quelle **raison** affichée par OpenTofu ?
2. Avant de toucher à quoi que ce soit, photographie les entrées du plan : `git status` et `git diff` de `~/src/infra`, liste des fichiers que `tofu` lit réellement dans `socle/` (y compris ceux que `git` ignore), `tofu state list`, version courante de l'objet d'état dans le compartiment (`aws s3api list-object-versions`).
3. Formule l'hypothèse « code », « variables », « état » ou « réalité », et prouve-la par une mesure : un plan JSON (`tofu plan -out` puis `tofu show -json`), un `tofu state show`, un `-refresh-only`, une comparaison de versions de l'état.
4. Si l'état doit être corrigé : **copie d'abord** l'objet d'état courant (nouvelle version, ou `aws s3api get-object` vers un fichier protégé), puis utilise la commande dédiée. Si le code doit l'être : MR.
5. Plan du socle vide. Écris dans ton journal pourquoi `prevent_destroy` a (ou n'a pas) arrêté le plan dans ta variante, et quel contrôle de la CI (M05-E26) l'aurait détecté avant Karim.

**Critères de réussite**
- [ ] `tofu plan` dans `socle/` affiche « No changes » ; aucune VM du socle n'a été recréée (même VMID, même date de création dans Proxmox).
- [ ] L'état contient `adm01`, `dns01`, `git01`, `s3-01` et `runner01` à des adresses décrites par le code ; aucun fichier local non commité n'influence plus le plan.
- [ ] Ton journal contient la ligne du plan d'origine, la mesure qui a prouvé la cause et la commande de réparation (avec sa sauvegarde préalable).

**Vérification** : `lab/bin/check 05 35`

<details><summary>Indice 1</summary>

Un plan n'a que quatre entrées : la configuration, les valeurs des variables, l'état, la réalité. `git status --ignored` montre aussi les fichiers que `git` ne suit pas mais qu'OpenTofu lit (relis la documentation *Override Files* et *Variable Definition Precedence*). `tofu plan -refresh=false` compare configuration et état **sans** regarder la réalité : si le plan dangereux persiste, la réalité n'y est pour rien.
</details>

<details><summary>Indice 2</summary>

Le texte entre parenthèses ou en commentaire après l'adresse dit tout : `# forces replacement` sur un attribut (lequel a changé, et d'où vient sa nouvelle valeur ?), `(tainted)` (qui a marqué la ressource ?), « is not in configuration » (l'adresse a changé, d'un côté ou de l'autre). Compare `tofu state list` à la sortie de la version précédente de l'objet d'état.
</details>

<details><summary>Indice 3</summary>

`tofu state mv`, `tofu untaint`, un bloc `moved {}` : chacun répare un cas précis. Le bloc `moved` laisse une trace relue en MR ; la commande, seulement un nouvel objet d'état. Pour une ressource sortie d'un module ou renommée par erreur, lequel préfères-tu en équipe, et pourquoi ?
</details>

**Pour aller plus loin** : ajoute au pipeline de `plateforme/infra` (M05-E26) un contrôle qui fait échouer le job de plan si le plan JSON contient une action `delete` sur une VM de VMID 1000-1099, avec un message explicite (le plan reste visible en artefact).

---

### M05-E36 — Panne : « Error acquiring the state lock »  `BF` `★★`

> **Ticket INC-3242** — *De : Julien Petit*
> Impossible de lancer le moindre plan ce matin : OpenTofu répond « Error acquiring the state lock » et s'arrête. Le pipeline de ma MR échoue pareil. Lucas me conseille « `tofu force-unlock`, ça marche toujours ». Je préfère te demander avant.
> Débloque-nous, mais sans risquer de corrompre l'état, et dis-moi qui détenait ce verrou.

**Objectifs pédagogiques**
- Lire un message de verrou (`ID`, `Path`, `Operation`, `Who`, `Version`, `Created`) et le relier à l'objet `<clé>.tflock` du compartiment.
- Prouver qu'un verrou est orphelin (processus, job CI, session) **avant** de le libérer ; savoir qu'un verrou vivant se libère en terminant proprement son détenteur.
- Choisir entre `tofu force-unlock <ID>` et la suppression de l'objet de verrou, et savoir quand le premier est impossible.

**Prérequis** : M05-E12 (verrou natif `use_lockfile`), M05-E26 (pipeline), M05-E33 (RB-050) ; `lab/bin/check 05 36` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : avec `use_lockfile = true`, OpenTofu prend le verrou en écrivant `<clé>.tflock` à côté de l'état, avec une écriture conditionnelle (`If-None-Match: *`). Le compartiment est versionné : supprimer cet objet ajoute un marqueur de suppression, rien n'est perdu.

**Injection** : `lab/bin/break 05 36` (4 variantes ; le ticket précise quel répertoire est bloqué).

**Travail demandé**
1. Reproduis le symptôme et recopie dans ton journal le bloc `Lock Info` complet (ou le message d'erreur s'il n'y en a pas). Que t'apprend chaque champ ? Que t'apprend son **absence** ?
2. Lis l'objet de verrou directement dans le compartiment (`aws s3api head-object`, `get-object` vers la sortie standard) et compare-le au message d'OpenTofu.
3. Trouve le détenteur : processus sur `adm01` (`ps`, `pgrep -a tofu`), jobs de `plateforme/infra` (en cours, annulés, échoués), processus sur `runner01`. Conclus par écrit : verrou **vivant** ou **orphelin** ?
4. Libère le verrou par la méthode adaptée à ta conclusion. Si tu forces : avec l'ID exact, après avoir prévenu l'équipe, et en vérifiant ensuite que l'état n'a pas changé de version.
5. Vérifie qu'un plan passe dans `socle/` **et** dans `envs/lab-m05/`, puis complète RB-050 avec ce que ta variante t'a appris.

**Critères de réussite**
- [ ] Aucun objet `*.tflock` ne subsiste pour les états `socle` et `envs/lab-m05` ; un plan passe dans les deux répertoires.
- [ ] Aucun processus OpenTofu oublié ne tourne sur `adm01`.
- [ ] Ton journal établit, preuve à l'appui, si le verrou était vivant ou orphelin, et qui le détenait ; RB-050 est à jour (MR fusionnée).

**Vérification** : `lab/bin/check 05 36`

<details><summary>Indice 1</summary>

`Who` est de la forme `utilisateur@hôte`, `Created` est en UTC. Un verrou posé par la CI porte le compte du runner ; un verrou posé depuis `adm01` porte ton compte. Un verrou récent et un verrou de la veille ne racontent pas la même histoire.
</details>

<details><summary>Indice 2</summary>

`tofu force-unlock` a besoin de l'ID **exact** du verrou : OpenTofu relit l'objet, compare l'ID, puis le supprime. Si OpenTofu ne parvient pas à lire l'objet (« unable to json parse the lock info »), il n'y a pas d'ID à donner : quel autre outil peut supprimer un objet, et quelles précautions prends-tu avant ?
</details>

<details><summary>Indice 3</summary>

Certaines commandes d'OpenTofu prennent le verrou et le gardent tant qu'elles tournent, même sans rien modifier (relis la page de `tofu console`). Un processus détaché de tout terminal se trouve avec `ps -ef` ; sa session avec `ps -o sid,pgid,args`.
</details>

**Pour aller plus loin** : écris `outils/verrou-etat.sh` (dans `plateforme/infra`) qui, pour une clé d'état, affiche l'objet de verrou, son âge, et selon le `Who` les jobs GitLab en cours du projet ou les processus `tofu` de l'hôte concerné ; il ne supprime rien.

---

### M05-E37 — Panne : le backend d'état est inaccessible  `BF` `★★`

> **Ticket INC-3243** — *De : Nadia Roussel*
> Alerte remontée par Julien : depuis `adm01`, `tofu plan` dans `~/src/infra/socle` échoue avant même de comparer quoi que ce soit, sur une erreur liée au backend d'état (`s3-01`). Il n'a pas réussi à savoir si c'est le stockage, le réseau ou OpenTofu, et il n'est pas sûr non plus que le pipeline de `plateforme/infra` soit touché.
> Rétablis l'accès à l'état, explique-moi la cause et la première commande qui l'aurait révélée. Interdit : `-lock=false`, contourner TLS, ou mettre une IP en dur à la place du nom.

**Objectifs pédagogiques**
- Décomposer l'accès au backend en maillons testables séparément : résolution du nom (et **quel** résolveur), routage et filtrage, TLS, authentification S3, autorisation (lecture, écriture, écriture conditionnelle du verrou).
- Utiliser `getent`, `dig`, `curl -v`, `openssl s_client`, `aws s3api` et `TF_LOG` comme instruments, du plus bas au plus haut.
- Comparer deux points de vue (`adm01` et `runner01`) pour localiser la panne.

**Prérequis** : M05-E10, M05-E11, M05-E12 ; M00-E40 (méthode DNS) ; `lab/bin/check 05 37` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Injection** : `lab/bin/break 05 37` (4 variantes).

**Travail demandé**
1. Reproduis le symptôme et note le message **complet**. Le pipeline (job de plan d'une MR ou relance du dernier pipeline de `main`) est-il touché ? Qu'en déduis-tu sur l'emplacement de la panne ?
2. Remplis une matrice de tests **avant** toute correction : résolution (`getent hosts`, `dig @10.10.20.10`), TCP/8333 (`nc -vz` ou `curl`), TLS (`openssl s_client -connect … -servername …`), S3 en lecture (`aws s3api list-objects-v2`), S3 en écriture conditionnelle (le script de M05-E12), et `tofu state list`. Une case suffit à éliminer chaque hypothèse : montre-le dans ton journal.
3. Trouve la cause racine sur l'hôte en cause (`adm01`, `gw01` ou `s3-01`) et corrige-la à l'endroit où elle a été introduite, par l'outil qui gère normalement cet endroit (rôle Ansible, configuration du pare-feu en code, fichier système).
4. Vérifie la chaîne complète : un plan **avec** verrou passe dans `socle/`, et le script d'écriture conditionnelle de M05-E12 est vert.

**Critères de réussite**
- [ ] Depuis `adm01`, `s3-01.par1.medisphere.internal` se résout en 10.10.20.14 par le résolveur système comme par le DNS ; la passerelle S3 répond en TLS vérifié.
- [ ] L'identité `tofu-etat` lit, écrit et prend le verrou ; aucune règle temporaire ne filtre 8333 sur `gw01`.
- [ ] Ton journal contient la matrice de tests remplie et la première commande qui aurait révélé la cause.

**Vérification** : `lab/bin/check 05 37`

<details><summary>Indice 1</summary>

`dig` interroge un serveur DNS ; `getent hosts` interroge la chaîne de résolution du système (`/etc/nsswitch.conf`), comme le font la bibliothèque C, Python (AWS CLI) et la plupart des programmes Go. Quand les deux divergent, le problème est sur le client.
</details>

<details><summary>Indice 2</summary>

`curl -v https://s3-01.par1.medisphere.internal:8333/` montre à quelle adresse il se connecte, si TCP aboutit, qui a signé le certificat présenté et pourquoi il est refusé. `TF_LOG=debug tofu state list 2>&1 | grep -iE 'error|status|x509'` montre la requête S3 qui échoue et le code HTTP.
</details>

<details><summary>Indice 3</summary>

Si la lecture fonctionne mais que le plan échoue en prenant le verrou, l'écriture est en cause : quels droits a l'identité `tofu-etat` dans la configuration des identités de la passerelle S3 (M05-E10) ? Une modification de ce fichier n'est prise en compte qu'au rechargement du service.
</details>

**Pour aller plus loin** : ajoute à la supervision (préparée pour le module 21) une sonde qui, depuis `adm01` et depuis `runner01`, fait toutes les 5 minutes le parcours complet (résolution, TLS, lecture, écriture conditionnelle sur une clé `_sondes/…`) et signale le premier maillon en échec.

---

### M05-E38 — Panne : l'apply échoue sur un refus de droits  `BF` `★★`

> **Ticket DEV-680** — *De : Julien Petit*
> Pour la campagne de tests de charge de MédiAgenda, j'ai besoin dans `envs/lab-m05` d'une VM d'environnement de plus (le VMID est indiqué à l'injection), construite comme les autres, et de 512 Mo de mémoire en plus pour chacune des VMs existantes de l'environnement. Fais la modification (MR, comme d'habitude) et applique-la. Lucas a essayé hier soir : « le plan est parfait, mais l'apply s'arrête sur une erreur de droits Proxmox ».
> Je veux l'environnement complet, et pas de droits en plus de ce qui est nécessaire.

**Objectifs pédagogiques**
- Comprendre pourquoi un plan réussit là où l'apply échoue : le plan **lit**, l'apply **écrit**, et chaque écriture a son privilège Proxmox sur son chemin (`/vms/<VMID>`, `/pool/lab`, `/storage/<stockage>`, `/sdn/zones/<zone>/<vnet>`).
- Lire un refus Proxmox (`Permission check failed (<chemin>, <privilège>)`) et retrouver l'ACL, le rôle et l'identité en cause (utilisateur ou jeton à droits séparés).
- Gérer un apply **partiel** : ressources créées, ressources marquées `tainted`, état à jour de ce qui a réellement été fait.

**Prérequis** : M05-E03 (compte `wb-tofu`, rôle `WBTofu`), M05-E07 ; M00-E17 (jeton à privilèges minimaux) ; `lab/bin/check 05 38` vert avant l'injection.
**Durée indicative** : 40 min (temps cible).

**Injection** : `lab/bin/break 05 38` (4 variantes ; le symptôme affiché donne le VMID de la VM à ajouter).

**Travail demandé**
1. Fais la modification demandée sur une branche, relis le plan, puis applique-le **depuis `adm01`** (l'apply n'est pas encore fusionné : c'est un essai, annonce-le dans ton journal). Note le message d'erreur exact et ce qui a été fait **avant** l'erreur.
2. Lis l'état après l'échec : quelles ressources ont été créées ou modifiées ? Lesquelles sont marquées `tainted` ? Un nouveau plan propose quoi, et pourquoi ?
3. Remonte la chaîne des droits sur `pve01` : identité réellement utilisée par le jeton (droits séparés ou non), ACL qui portent sur le chemin cité, rôles et privilèges. Compare à ce que M05-E03 a documenté (rôle `WBTofu`, registre des secrets).
4. Corrige **au plus juste** (le privilège manquant, sur le bon chemin, pour la bonne identité), et consigne la correction là où les droits de `wb-tofu` sont décrits (script ou documentation de M05-E03).
5. Termine la demande de Julien par la chaîne normale (MR, plan relu, apply) ; vérifie que l'état ne contient plus rien de `tainted` et qu'un second plan est vide.

**Critères de réussite**
- [ ] L'environnement contient la VM demandée et la mémoire augmentée ; `tofu plan` dans `envs/lab-m05/` est vide, aucune ressource `tainted`.
- [ ] Le jeton `wb-tofu@pve!tofu` a les privilèges nécessaires sur `/pool/lab`, `/storage/local-nvme` et le VNet `vsandbox`, et aucun droit d'administration (`Permissions.Modify`, `Sys.Modify`, `User.Modify`) sur `/`.
- [ ] Ton journal contient le message d'erreur, l'état de l'apply partiel et la commande qui a identifié l'ACL ou le privilège manquant.

**Vérification** : `lab/bin/check 05 38`

<details><summary>Indice 1</summary>

Le message de Proxmox cite le **chemin** et le **privilège** vérifiés. `pveum user token permissions wb-tofu@pve tofu --path <chemin>` affiche les privilèges effectifs du jeton sur ce chemin ; `pveum acl list` et `pveum role list` montrent d'où ils viennent.
</details>

<details><summary>Indice 2</summary>

Un jeton créé avec `--privsep 1` n'hérite **pas** des droits de son utilisateur : il a ses propres ACL, toujours un sous-ensemble de celles de l'utilisateur. Une ACL sur `/pool/lab` ne donne rien sur `/storage/…` ni sur `/sdn/…` : ce sont d'autres branches de l'arbre des permissions.
</details>

<details><summary>Indice 3</summary>

Une ressource dont la création a échoué **après** que Proxmox l'a créée est enregistrée dans l'état et marquée `tainted` : le plan suivant propose de la remplacer. Si la VM est saine une fois les droits rétablis, `tofu untaint` évite une destruction inutile ; sinon, laisse OpenTofu la recréer.
</details>

**Pour aller plus loin** : écris un test de non-régression des droits (`outils/verifier-droits-wb-tofu.sh`) qui compare les privilèges effectifs du jeton sur chaque chemin à une liste de référence versionnée, et lance-le dans le pipeline planifié de dérive.

---

### M05-E39 — Panne : la VM est créée mais injoignable  `BF` `★★★`

> **Ticket DEV-681** — *De : Julien Petit*
> J'ai besoin d'une VM d'environnement de plus dans `envs/lab-m05` (le VMID est indiqué à l'injection), construite comme les autres : image dorée `current`, VNet `vsandbox`, DHCP, compte `admin`, ta clé. Lucas l'a tentée hier : « l'apply passe (ou attend longtemps l'agent QEMU), la VM tourne dans Proxmox, mais impossible de m'y connecter depuis `adm01` ».
> Ajoute-la, et fais en sorte que je puisse m'y connecter en SSH. Je veux la cause, pas un contournement.

**Objectifs pédagogiques**
- Séparer ce qu'OpenTofu garantit (la VM existe avec la configuration demandée) de ce qu'il ne voit pas (adresse obtenue, routage, filtrage, contenu de cloud-init effectivement appliqué).
- Diagnostiquer une VM neuve de l'extérieur vers l'intérieur : agent QEMU, console, adresse DHCP, relais, filtrage, clés SSH.
- Relier un symptôme d'apply (attente de l'agent, délai dépassé) à sa cause hors d'OpenTofu.

**Prérequis** : M05-E04, M05-E08, M05-E19 ; M00-E14 (relais DHCP), M00-E39 (méthode) ; `lab/bin/check 05 39` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Injection** : `lab/bin/break 05 39` (4 variantes ; le symptôme affiché donne le VMID de la VM à ajouter).

**Travail demandé**
1. Ajoute la VM (branche, plan relu, apply depuis `adm01`). Note la durée de l'apply et ce qu'il affiche. Relis le plan : touchait-il **autre chose** que la nouvelle VM ?
2. Établis, sans SSH, ce que sait la VM : `qm guest cmd <VMID> network-get-interfaces`, `qm guest exec <VMID> -- cloud-init status --long`, journal de cloud-init (`/var/log/cloud-init.log`). A-t-elle une adresse ? Laquelle ? Une passerelle ?
3. Selon la réponse, suis le chemin : demande DHCP (capture sur `gw01`, `ens19.99`), relais, serveur `dnsmasq` de `dns01` et son journal ; ou chemin `adm01` → VM (ping, TCP/22, compteurs nftables de `gw01`) ; ou authentification SSH (`ssh -v -o ControlPath=none`, `authorized_keys` de la VM lu par l'agent).
4. Corrige la cause à sa source, sans contournement (pas de mot de passe posé à la main, pas d'adresse statique improvisée, pas de règle « accept » ajoutée en tête pour masquer une règle « drop »).
5. Vérifie que la VM répond en SSH **et** que les autres VMs de l'environnement aussi ; plan de `envs/lab-m05/` vide.

**Critères de réussite**
- [ ] Toutes les VMs `env-m05` démarrées sont sur `vsandbox`, ont une adresse 10.10.99.x et acceptent une **nouvelle** connexion SSH depuis `adm01` (`-o ControlPath=none`).
- [ ] Le DHCP du VLAN 99 et le filtrage de `gw01` sont conformes à la matrice des flux ; `dnsmasq` sert les machines non déclarées du VLAN 99.
- [ ] Le plan de `envs/lab-m05/` est vide ; ton journal donne, pour ta variante, la première mesure qui a localisé la panne.

**Vérification** : `lab/bin/check 05 39`

<details><summary>Indice 1</summary>

Une VM sans adresse IPv4 (seulement `fe80::…` dans la réponse de l'agent) n'a pas obtenu de bail : la panne est sur le chemin DHCP. Une VM qui a une adresse mais ne répond pas sur 22 a un problème de chemin ou de filtrage. Une VM qui répond mais refuse ta clé a un problème de **contenu** cloud-init.
</details>

<details><summary>Indice 2</summary>

Sur `gw01`, `tcpdump -ni ens19.99 port 67 or port 68` pendant le démarrage de la VM montre si la demande arrive et si une réponse repart. Les compteurs `nft list ruleset` (règles avec `counter`) montrent quelles règles voient passer les paquets. Sur `dns01`, `journalctl -u dnsmasq` trace chaque `DHCPDISCOVER` et ce que `dnsmasq` en fait.
</details>

<details><summary>Indice 3</summary>

`qm guest exec <VMID> -- cat /home/admin/.ssh/authorized_keys` montre les clés réellement installées ; `qm cloudinit dump <VMID> user` montre ce que Proxmox a fourni à cloud-init, donc ce qu'OpenTofu a demandé. Compare avec `~/.ssh/id_ed25519.pub` de `adm01`, puis avec ce que le **plan** a envoyé.
</details>

**Pour aller plus loin** : ajoute à l'environnement une sortie `adresses_ipv4` (tirée de l'agent) et un bloc `check` qui avertit au plan quand une VM démarrée n'a pas d'adresse dans 10.10.99.0/24.

---

### M05-E40 — Panne : l'état ne correspond plus à la réalité  `BF` `★★`

> **Ticket DEV-682** — *De : Julien Petit*
> Encore une VM pour les tests de charge, s'il te plaît : dans `envs/lab-m05`, VMID indiqué à l'injection, construite comme les autres. Lucas a préparé la modification mais n'ose pas appliquer : « le plan annonce des choses que je n'ai pas demandées », et chez lui l'apply a fini en erreur.
> Je ne veux rien perdre de ce qui tourne (une VM d'environnement sert à mes tests en ce moment). Remets OpenTofu et Proxmox d'accord, puis ajoute ma VM.

**Objectifs pédagogiques**
- Classer un écart entre état et réalité : ressource **absente de l'état** mais présente (à importer), ressource **modifiée hors IaC** (à adopter ou à défaire), ressource **inconnue** occupant une place que le code réclame.
- Utiliser `tofu plan -refresh-only`, `tofu apply -refresh-only`, les blocs `import {}` et `tofu import`, en sachant ce que chacun écrit dans l'état.
- Décider **avec le demandeur** si la réalité ou le code a raison, et le traduire dans le code.

**Prérequis** : M05-E05, M05-E16, M05-E28 ; `lab/bin/check 05 40` vert avant l'injection.
**Durée indicative** : 40 min (temps cible).

**Injection** : `lab/bin/break 05 40` (3 variantes ; le symptôme affiché donne le VMID de la VM à ajouter).

**Travail demandé**
1. Écris la modification demandée sur une branche et lance le plan. Classe chaque ligne du plan : demandée, ou non demandée. Pour chaque ligne non demandée, formule l'écart (« l'état dit X, Proxmox dit Y, le code dit Z »).
2. Mesure sans rien écrire : `tofu plan -refresh-only`, `tofu state list`, `tofu state show`, et côté Proxmox `qm config`, `qm list`, les étiquettes `env-m05`, les tâches récentes de `pve01` (`pvesh get /nodes/<NŒUD>/tasks`) qui disent qui a fait quoi et quand.
3. Pour chaque écart, choisis la réconciliation et justifie-la dans ton journal (« Julien confirme que… ») : import, adoption de la valeur réelle dans le code, retour de la réalité à la valeur du code, suppression d'un objet orphelin. **Aucune** VM existante ne doit être détruite pour être recréée.
4. Applique la réconciliation puis la demande de Julien par la chaîne normale. Plan vide.
5. Explique dans ton journal pourquoi `tofu apply -refresh-only` n'aurait **pas** suffi à régler ta variante, ou dans quel cas il aurait suffi.

**Critères de réussite**
- [ ] Les VMs étiquetées `env-m05` dans Proxmox et les VMs de l'état `envs/lab-m05` sont exactement les mêmes ; la VM demandée existe.
- [ ] `tofu plan` dans `envs/lab-m05/` est vide ; aucune VM d'environnement préexistante n'a été recréée.
- [ ] Ton journal classe chaque écart et justifie la réconciliation choisie.

**Vérification** : `lab/bin/check 05 40`

<details><summary>Indice 1</summary>

« will be created » pour une VM dont le VMID existe déjà dans Proxmox : l'état l'a perdue (ou ne l'a jamais eue). « will be updated in-place » sur la mémoire ou les étiquettes : la réalité a bougé. « already exists » à l'apply : un objet que l'état ne connaît pas occupe la place.
</details>

<details><summary>Indice 2</summary>

Un bloc `import { to = … id = "<NŒUD>/<VMID>" }` (format d'import de la ressource VM du provider) est relu en MR et rejoué par le pipeline ; `tofu import` en ligne de commande ne laisse qu'un nouvel objet d'état. Après l'import, le plan doit être vide : sinon, ton code ne décrit pas encore la VM telle qu'elle est.
</details>

**Pour aller plus loin** : complète la détection de dérive planifiée (M05-E28) par un rapport des VMs étiquetées `env-*` ou `socle` qui n'appartiennent à **aucun** état (inventaire Proxmox moins états OpenTofu) : c'est la dérive que `tofu plan` ne verra jamais.

---

### M05-E41 — Panne : le plan est cassé du jour au lendemain  `BF` `★★★`

> **Ticket INC-3244** — *De : Karim Benali*
> Ce matin, `tofu plan` échoue sur `adm01` dans `~/src/infra` (au moins dans `socle` ou dans `envs/lab-m05`) avant même d'afficher un plan. Aucun commit dans `plateforme/infra` depuis hier. Ce qui s'est passé hier, d'après le canal `#plateforme` : le pipeline de `plateforme/images` a publié (ou tenté de publier) une nouvelle image dorée ; Lucas a « fait de la place » sur `adm01` et préparé la mise à jour des providers ; Sophie a commencé la rotation trimestrielle des secrets (nouvelles valeurs déposées sur `adm01`, la suite est prévue aujourd'hui) ; les mises à jour de sécurité de la nuit sont passées sur `adm01` et `runner01`.
> Trouve lequel de ces événements nous casse (et pourquoi les autres sont hors de cause), répare sans régénérer à l'aveugle ce que tu ne comprends pas, et vérifie aussi le pipeline.

**Objectifs pédagogiques**
- Lister tout ce dont dépend un plan **hors du dépôt** : binaire OpenTofu, providers installés et fichier de verrouillage, modules téléchargés, sources de données (images, état d'autres configurations), secrets d'environnement, phrase de chiffrement.
- Comprendre le fichier `.terraform.lock.hcl` : versions retenues, empreintes `h1:` et `zh:`, plateformes, et ce qu'OpenTofu vérifie à chaque exécution.
- Mener une rotation de la phrase de chiffrement de l'état sans perte (bloc `fallback`), si la variante l'exige.

**Prérequis** : M05-E08, M05-E27, M05-E31 ; M03-E10 (publication d'image) ; `lab/bin/check 05 41` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Injection** : `lab/bin/break 05 41` (4 variantes).

**Travail demandé**
1. Reproduis l'erreur dans `socle/` et dans `envs/lab-m05/`, puis relance le dernier pipeline de `main` (ou celui d'une MR de test). Note les trois résultats : la comparaison `adm01` / CI élimine déjà une partie des quatre événements.
2. Pour chacun des quatre événements du ticket, écris la commande qui le **met hors de cause** ou le confirme (une par événement), et son résultat.
3. Trouve la cause racine. Corrige-la à sa source : par l'outil qui l'a produite (pipeline d'images, `tofu init` sur un lock rétabli depuis `git`, cache des providers reconstruit, rotation de la phrase terminée proprement), jamais en modifiant la configuration pour contourner l'erreur.
4. Si tu touches au fichier `.terraform.lock.hcl` : explique dans ton journal pourquoi `tofu init -upgrade` n'est **pas** la bonne réponse ici, et ce que doit contenir un lock destiné à `adm01` **et** `runner01`.
5. Vérifie : plans vides dans les deux répertoires, pipeline vert, `git status` propre.

**Critères de réussite**
- [ ] `tofu plan` aboutit sans changement dans `socle/` et dans `envs/lab-m05/` ; le dernier pipeline de `main` est vert.
- [ ] Les fichiers `.terraform.lock.hcl` sont ceux du dépôt et contiennent les empreintes `zh:` de bpg/proxmox ; une seule image dorée Debian porte `current` ; l'état se déchiffre depuis `adm01` et depuis la CI avec la même phrase.
- [ ] Ton journal contient, pour chacun des quatre événements, la commande qui l'a disculpé ou confirmé.

**Vérification** : `lab/bin/check 05 41`

<details><summary>Indice 1</summary>

Si la CI fonctionne et `adm01` non, la cause est dans ce que `adm01` a et que `runner01` n'a pas : la copie de travail (et son dossier `.terraform/`), `~/.config/workbook/`. Si les deux échouent, cherche dans ce qu'ils partagent : Proxmox, `s3-01`, la forge.
</details>

<details><summary>Indice 2</summary>

`git status --ignored` et `git diff` dans `~/src/infra` ; `ls -la` et `sha256sum` dans `.terraform/providers/…` ; `pvesh get /cluster/resources --type vm` filtré sur les templates et leurs étiquettes ; `tofu state list` (lit et déchiffre l'état sans rien planifier). Chacune de ces commandes disculpe ou accuse un événement.
</details>

<details><summary>Indice 3</summary>

Une rotation de phrase de chiffrement se fait en deux temps : nouvelle méthode **et** ancienne en `fallback`, un apply (ou `tofu apply -refresh-only`) qui réécrit l'état avec la nouvelle, puis retrait du `fallback`. Où se trouve l'ancienne phrase, d'après ton registre des secrets ?
</details>

**Pour aller plus loin** : ajoute au pipeline un job planifié (quotidien) qui lance `tofu init -lockfile=readonly` et `tofu validate` dans un répertoire propre : il échoue dès qu'une image, un module ou un provider attendu n'est plus disponible, avant le premier plan de la journée.

---

### M05-E42 — Panne : l'état a disparu  `BF` `★★★`

> **Ticket INC-3245** — *De : Nadia Roussel* — priorité P1
> Karim vient de lancer `tofu plan` dans `~/src/infra/socle` pour une petite MR : OpenTofu propose de **créer** (ou d'importer) tout le socle, et peut-être pire. Comme si l'état n'existait plus. Personne n'admet avoir touché à quoi que ce soit.
> Gel immédiat : aucun apply sur `socle` tant que ce n'est pas réglé (préviens l'équipe). Retrouve l'état, restaure-le **sans perdre de version**, prouve qu'il est complet, et dis-moi ce qui aurait pu être perdu si le compartiment n'avait pas été versionné.

**Objectifs pédagogiques**
- Distinguer « l'état a disparu » de « OpenTofu regarde ailleurs » : clé du backend, espace de travail (*workspace*), configuration initialisée (`.terraform/terraform.tfstate`, `.terraform/environment`).
- Restaurer une version précise d'un objet S3 versionné (`list-object-versions`, marqueurs de suppression, `copy-object` d'une version), sans écraser l'historique.
- Prouver qu'un état restauré est complet et cohérent (`serial`, `lineage`, ressources, plan vide) avant de lever le gel.

**Prérequis** : M05-E11, M05-E15, M05-E27, M05-E29 ; `lab/bin/check 05 42` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : le compartiment `tofu-state` est versionné (M05-E11). Avec AWS CLI v2 : `aws s3api list-object-versions --bucket tofu-state --prefix <clé>` liste les versions (`Versions`) et les marqueurs de suppression (`DeleteMarkers`), avec `VersionId`, `IsLatest` et `LastModified` ; `get-object --version-id` lit une version ; `copy-object --copy-source 'tofu-state/<clé>?versionId=<ID>'` recopie une version comme nouvelle version courante ; `delete-object --version-id` supprime **définitivement** une version ou un marqueur.

**Injection** : `lab/bin/break 05 42` (4 variantes).

> ⚠️ **Attention** : `delete-object` **avec** `--version-id` est irréversible, y compris sur un compartiment versionné. Avant toute manipulation, enregistre la liste complète des versions de la clé (`list-object-versions … > fichier`) et copie la version que tu crois bonne (`get-object --version-id … fichier`, en `600`). Le plan proposé pendant la panne peut **détruire des VMs** : aucun apply avant la levée du gel.

**Travail demandé**
1. Annonce le gel (message court dans ton journal, comme au canal `#plateforme`). Reproduis le symptôme et note le résumé du plan (`Plan: X to import, Y to add, Z to destroy`) et les adresses concernées.
2. Établis où OpenTofu cherche l'état : configuration du backend dans le code **et** dans `.terraform/`, espace de travail sélectionné (`tofu workspace show`, `tofu workspace list`). L'objet attendu existe-t-il dans le compartiment ?
3. Liste les versions de la clé `socle/terraform.tfstate`. Identifie la dernière version **saine** et prouve-le (taille, date, contenu déchiffré : `serial`, `lineage`, nombre de ressources) **avant** de restaurer.
4. Restaure par la méthode qui conserve l'historique, ou remets la configuration sur le bon état, selon ce que tu as établi. Vérifie que plus rien ne pointe ailleurs.
5. Lève le gel seulement après : `tofu state list` complet, plan vide, et une note dans ton journal sur ce qui aurait été perdu sans versionnage (et sans la sauvegarde de M05-E29).

**Critères de réussite**
- [ ] L'objet courant de `socle/terraform.tfstate` est une version saine (pas un marqueur de suppression) ; toutes les versions antérieures existent encore.
- [ ] `socle/` utilise la clé `socle/terraform.tfstate` dans l'espace `default` ; `tofu plan` y est vide et l'état contient les cinq VMs du socle.
- [ ] Ton journal contient le gel, la liste des versions examinées, la preuve de la version choisie et la levée du gel.

**Vérification** : `lab/bin/check 05 42`

<details><summary>Indice 1</summary>

Avant de chercher dans le compartiment, demande à OpenTofu où il regarde : `cat .terraform/environment` (s'il existe), `jq .backend.config .terraform/terraform.tfstate`, `grep -n key *.tf`. Un état « vide » peut être un état parfaitement intact… à une autre adresse.
</details>

<details><summary>Indice 2</summary>

Dans la sortie de `list-object-versions`, la version courante est celle qui porte `"IsLatest": true` (version **ou** marqueur). La taille d'une version (`Size`) et sa date suffisent souvent à repérer l'intrus ; le contenu déchiffré le prouve : pour lire une ancienne version sans la restaurer, copie-la sous une **autre** clé (`_examen/…`) et lis-la avec une configuration jetable qui pointe sur cette clé, ou compare tailles et dates avec les apply connus.
</details>

<details><summary>Indice 3</summary>

Supprimer un marqueur de suppression (avec son `VersionId`) rend sa place à la version précédente ; recopier une ancienne version la rend courante en ajoutant une version. Les deux conservent les versions de données : lequel laisse la meilleure trace pour le post-mortem ?
</details>

**Pour aller plus loin** : écris `outils/restaurer-etat.sh <clé> <VersionId>` qui sauvegarde la liste des versions, copie la version actuelle sous `_sauvegardes/`, recopie la version demandée comme version courante et affiche le `serial` avant/après ; référence-le dans RB-050 ou dans un nouveau runbook RB-051.

---

### M05-E43 — Astreinte : l'IaC en panne  `BF` `★★★★`

> **Ticket INC-3250** — *De : Nadia Roussel (responsable astreinte)* — priorité P2
> Tu es d'astreinte. Plusieurs remontées sur la chaîne d'infrastructure as code depuis ce matin (le détail s'affiche à l'injection). Julien a une démonstration de MédiAgenda à 14 h sur `envs/lab-m05`, et la MR de Karim sur le socle attend son apply : gel des apply sur `socle` jusqu'à ton feu vert. Rétablis la chaîne, tiens-moi informée toutes les 30 minutes (un message court dans `#astreinte` suffit), puis rédige le post-mortem avec le modèle de l'équipe.

**Objectifs pédagogiques**
- Gérer un incident à causes multiples sur une chaîne IaC : trier, prioriser, éviter qu'une panne en masque une autre (un backend inaccessible cache tout ce qui se passe dans l'état).
- Protéger l'état pendant l'incident : gel des apply, copies avant chaque manipulation, une modification à la fois.
- Communiquer et rédiger un post-mortem sans recherche de coupable.

**Prérequis** : M05-E35 à M05-E42 (au moins une variante de chacun).
**Durée indicative** : 2 h de rétablissement + 45 min de post-mortem.

**Contexte technique** : le script tire **deux** pannes distinctes parmi celles de M05-E35 à M05-E42 (variantes aléatoires) et les injecte ensemble. Les symptômes peuvent se recouvrir. `--variante N` (1 à 27) force la paire, pas les variantes. `--annuler` retire les deux. La copie de travail `~/src/infra` doit être propre et les plans vides avant l'injection.

**Injection** : `lab/bin/break 05 43`

**Travail demandé**
1. **Triage (10 min max)** : avant toute correction, liste les symptômes, leur impact (qui ne peut plus faire quoi : plans, apply, démonstration de Julien), et une première hypothèse de regroupement. Annonce le gel des apply et envoie la première communication.
2. **Diagnostic** : traite les pannes dans l'ordre que tu justifies. Rétablis d'abord tes **instruments** (accès au backend, lecture de l'état, plan) : tant qu'ils mentent, tout le reste est faux. Journal horodaté.
3. **Rétablissement** : corrige chaque cause racine ; après chaque correction, rejoue **tous** tes tests de départ (`lab/bin/check 05 35` à `05 42` sont de bonnes sondes).
4. **Clôture** : levée du gel, communication de fin, puis post-mortem rédigé à partir de `modules/00-lab/ressources/M00-E46/modele-post-mortem.md`, enregistré dans `docs/socle/post-mortems/AAAA-MM-JJ-INC-3250.md` de `~/medisphere` et fusionné.

**Critères de réussite**
- [ ] Toutes les vérifications de M05-E35 à M05-E42 sont vertes (le contrôle les rejoue toutes) et aucune panne n'est encore marquée active.
- [ ] Le post-mortem contient une chronologie horodatée, les deux causes racines prouvées, l'analyse de la détection et des actions correctives avec responsable et échéance.
- [ ] Le journal contient au moins trois communications espacées d'environ 30 minutes, le gel et sa levée.

**Vérification** : `lab/bin/check 05 43`

<details><summary>Indice 1</summary>

Commence par ce qui conditionne tes instruments : `getent hosts s3-01…`, `aws s3api list-objects-v2`, `tofu state list` dans les deux répertoires, `git status`. Si l'un d'eux échoue, tous les plans que tu lanceras ensuite te mentiront.
</details>

<details><summary>Indice 2</summary>

Une panne d'état (verrou, état disparu, état désynchronisé) se règle **avant** toute panne qui demande un apply (droits, VM injoignable) : un apply sur un état faux aggrave les deux.
</details>

**Pour aller plus loin** : fais-toi injecter une astreinte par quelqu'un d'autre (`--variante` tirée par lui), sans regarder l'écran pendant l'injection, et chronomètre ton temps de rétablissement.

---

### M05-E44 — Sous le capot : graphe, providers et état  `LAB` `★★★`

> **Ticket PLAT-685** — *De : Karim Benali*
> Pendant les pannes, j'ai entendu trop de « OpenTofu a dû… ». Je veux que tu saches **montrer** ce qu'il fait : dans quel ordre il traite les ressources, ce qu'il demande au provider et ce que le provider répond, ce qu'il écrit dans l'état et pourquoi. Fais-moi un compte rendu qu'on donnera aux prochains arrivants. Et pas sur l'état de production : tu as un bac à sable.

**Objectifs pédagogiques**
- Lire le graphe de dépendances d'OpenTofu (`tofu graph`) et relier ses nœuds à l'ordre d'exécution et au parallélisme.
- Observer le protocole entre OpenTofu et un provider (processus séparé, gRPC, poignée de main, appels `GetProviderSchema`, `ConfigureProvider`, `ReadResource`, `PlanResourceChange`, `ApplyResourceChange`) grâce aux journaux.
- Connaître la structure d'un état (`version`, `serial`, `lineage`, `resources`, `instances`, `schema_version`, `dependencies`, `private`) et les garde-fous de `tofu state push`.
- Comprendre le fichier de verrouillage des providers (`h1:`, `zh:`, plateformes).

**Prérequis** : M05-E05, M05-E18, M05-E27, M05-E31.
**Durée indicative** : 3 h.

**Contexte technique**
- Bac à sable : `~/m05/e44/labo/` sur `adm01` (dossier de brouillons du module, hors de tout dépôt), **backend local**, ressources `terraform_data` (intégrées à OpenTofu, sans provider) et une copie de la configuration `envs/lab-m05` limitée à des **sources de données** (lecture seule). Rien n'y touche à l'état distant.
- Les journaux de trace (`TF_LOG=trace`) peuvent contenir des en-têtes et des réponses d'API : écris-les en `600`, hors de tout dépôt, et supprime-les à la fin.

> ⚠️ **Attention** : n'exécute **aucune** commande `tofu state push`, `state rm` ou `state mv` dans `~/src/infra`. Les expériences sur l'état se font dans le bac à sable, avec un backend local.

**Travail demandé**
1. **Graphe.** Dans `~/src/infra/socle`, produis `tofu graph -type=plan` et rends-le en SVG (`dot -Tsvg`, paquet `graphviz`). Repère : le nœud du provider, les sources de données, les VMs, les nœuds de fermeture. Compare avec `-type=plan-destroy` : qu'est-ce qui s'inverse ? Publie le SVG dans `docs/socle/analyses/graphe-socle.svg`.
2. **Ordre et parallélisme.** Dans le bac à sable, écris cinq `terraform_data` dont deux dépendent d'un troisième (une référence, puis un `depends_on`), avec un `provisioner "local-exec"` qui écrit l'heure dans un fichier. Applique avec `-parallelism=1` puis `-parallelism=10` : compare l'ordre et la durée. Où, dans le graphe, lis-tu ce qui peut tourner en parallèle ?
3. **Protocole des providers.** Dans le bac à sable, copie de `envs/lab-m05` uniquement le provider et les sources de données (image `current`, version de Proxmox). Lance `TF_LOG=trace TF_LOG_PATH=<fichier> tofu plan` : retrouve le démarrage du processus du provider (chemin du binaire, version du protocole négociée), les appels gRPC dans l'ordre, et la configuration du provider. Combien de processus de provider tournent pendant un plan (`ps` pendant l'exécution) ?
4. **Ce qui force un remplacement.** Avec `tofu providers schema -json`, cherche l'attribut `clone` de `proxmox_virtual_environment_vm` : le schéma dit-il qu'il force un remplacement ? Puis, dans le bac à sable, fais un plan de remplacement sur un `terraform_data` (`triggers_replace`) et lis `resource_changes[].change.replace_paths` dans `tofu show -json`. Qui décide d'un remplacement : OpenTofu ou le provider ?
5. **État.** Dans le bac à sable : lis `terraform.tfstate` (champs de premier niveau, une instance complète), applique un changement et observe `serial` et `lineage` ; puis tente de « pousser » une copie plus ancienne (`tofu state push`) et une copie d'un **autre** bac à sable (autre `lineage`). Recopie les refus. Dans quel cas `-force` les contourne-t-il, et que perd-on ?
6. **Verrouillage des providers.** Compare le `.terraform.lock.hcl` de `socle/` avant et après `tofu providers lock -platform=linux_amd64 -platform=darwin_arm64` **dans le bac à sable** (copie du fichier). Que sont les empreintes `h1:` et `zh:` ? Pourquoi l'erreur de M05-E41 apparaît-elle sur un poste et pas sur l'autre ?
7. **Compte rendu.** Rédige `docs/socle/analyses/opentofu-sous-le-capot.md` dans `~/medisphere` : graphe commenté, extraits **anonymisés** de la trace (aucun jeton, aucun en-tête d'autorisation), structure de l'état annotée, puis une section `## Réponses aux questions` traitant les questions ci-dessous. Supprime ensuite les traces et toute copie d'état (`shred -u`).

**Questions d'analyse** (à traiter dans le compte rendu)
1. Pourquoi la source de données de l'image `current` est-elle lue pendant **chaque** plan, même avec `-refresh=false` ?
2. Que représentent les nœuds `provider["registry.opentofu.org/bpg/proxmox"] (close)` et `root` du graphe ?
3. Pourquoi une erreur de cycle (`Cycle: …`) est-elle détectée **avant** tout appel à l'API Proxmox ?
4. Le provider bpg/proxmox négocie quelle version du protocole de plugin ? Que change pour toi le fait qu'il combine deux implémentations (SDKv2 et Plugin Framework) derrière un seul serveur ?
5. Dans la trace, quel appel lit l'état réel d'une VM ? Combien de fois est-il appelé pour l'environnement, et pourquoi ?
6. Pourquoi `tofu providers schema -json` ne permet-il **pas** de savoir quels attributs forcent un remplacement ? Où cette information apparaît-elle ?
7. À quoi servent `serial` et `lineage` ? Quelle protection apportent-ils contre l'erreur de M05-E42 (variante « état d'un autre environnement ») ?
8. Que contient le champ `private` d'une instance, et pourquoi ne faut-il jamais le modifier ?
9. `schema_version` d'une instance : que se passe-t-il quand un provider plus récent change ce numéro ?
10. Que vérifie OpenTofu avec les empreintes `h1:` à chaque exécution, et avec les `zh:` à l'installation ? Pourquoi un lock créé sur un seul poste peut-il casser la CI ?
11. Pourquoi l'état chiffré (M05-E27) ne contient-il plus `serial` ni `lineage` lisibles dans l'objet S3, et que reste-t-il de visible pour un attaquant qui lit le compartiment ?
12. `-parallelism` : quelle valeur par défaut, et pourquoi la réduire face à l'API Proxmox ?

**Critères de réussite**
- [ ] `docs/socle/analyses/opentofu-sous-le-capot.md` et `graphe-socle.svg` sont publiés (MR fusionnée) ; le compte rendu traite les 12 questions.
- [ ] Aucune trace ni copie d'état en clair ne reste sur `adm01` hors du bac à sable ; le dépôt de documentation ne contient aucun état.
- [ ] Aucune expérience n'a modifié les états distants (leur nombre de versions n'a pas bougé pendant l'exercice).

**Vérification** : `lab/bin/check 05 44`

<details><summary>Indice 1</summary>

Dans la trace, cherche `plugin started`, `using plugin`, `protocol version` et les noms d'appels gRPC (`GetProviderSchema`, `ValidateResourceConfig`, `ConfigureProvider`, `ReadDataSource`, `ReadResource`, `PlanResourceChange`). `grep -c` donne le nombre d'appels ; l'adresse de la ressource figure souvent sur la ligne voisine.
</details>

<details><summary>Indice 2</summary>

La documentation de `tofu state push` décrit ses deux contrôles de sécurité. Le format de l'état n'est pas une interface publique : lis-le, ne l'écris pas. Pour comparer deux états du bac à sable : `jq '{version, serial, lineage, terraform_version}'`.
</details>

**Pour aller plus loin** : écris un petit provider avec le *Terraform Plugin Framework* (une ressource « fichier » locale), compile-le et utilise-le dans le bac à sable via `dev_overrides` de `~/.tofurc` ; observe ses appels dans la trace.

---

### M05-E45 — Questions expert : OpenTofu  `Q` `★★★`

> **Ticket PLAT-686** — *De : Karim Benali*
> Dernière étape avant la recette : ces questions, je les pose en entretien pour un poste d'ingénieur plateforme senior. Réponds par écrit, en argumentant. Pas de recherche pendant la première passe ; vérifie ensuite dans la documentation et corrige-toi en couleur.

**Objectifs pédagogiques**
- Consolider les mécanismes internes manipulés dans ce module (état, verrou, graphe, providers, refactoring, import, chiffrement).
- S'entraîner à argumenter une réponse technique comme en entretien ou en revue d'architecture.

**Prérequis** : paliers 1 à 3 du module, M05-E44.
**Durée indicative** : 2 h 30.

**Questions**

1. Explique les trois phases d'un `tofu apply` (rafraîchissement, planification, application) et ce que chacune lit et écrit. Pourquoi un `apply` sans plan sauvegardé peut-il appliquer autre chose que ce que le relecteur a vu en MR ?
2. QCM — Un job CI fait `tofu plan -out=plan.bin`, puis un autre job, une heure plus tard, `tofu apply plan.bin`. Entre-temps, un collègue a appliqué une autre MR sur le même état. Que se passe-t-il ?
   a) le plan est appliqué tel quel, l'état est fusionné ; b) OpenTofu refuse : le plan sauvegardé ne correspond plus à l'état courant (plan périmé) ; c) OpenTofu replanifie automatiquement ; d) le verrou empêche le second job de démarrer.
3. Quelle différence entre `tofu plan -refresh-only`, `tofu apply -refresh-only` et `tofu plan -refresh=false` ? Donne un usage légitime de chacun.
4. `prevent_destroy = true` : que protège-t-il exactement, et dans quels cas ne protège-t-il **rien** ? (Pense à `state mv`, à la suppression du bloc, à `tofu destroy -target`, à la protection Proxmox.)
5. QCM — Tu renommes `resource "proxmox_virtual_environment_vm" "s3_01"` en `module "s3_01"` (module `vm-debian`). Sans autre précaution, le plan :
   a) détecte le renommage et ne change rien ; b) détruit l'ancienne adresse et crée la nouvelle ; c) échoue sur `prevent_destroy` de l'ancienne adresse ; d) b ou c selon que le bloc d'origine (avec son `prevent_destroy`) existe encore dans la configuration.
6. Compare `moved {}`, `tofu state mv`, `removed {}` (avec `lifecycle { destroy = false }`) et `tofu state rm` : trace laissée, relecture en MR, rejouabilité en CI, risque.
7. Bloc `import {}` contre `tofu import` : différences, et pourquoi le premier est préférable en équipe. Que fait `tofu plan -generate-config-out=…`, et pourquoi ne faut-il pas fusionner sa sortie telle quelle ?
8. Explique le verrou natif S3 (`use_lockfile`) : quel objet, quelle requête, quelle propriété du stockage est indispensable, et pourquoi Garage ne convient pas. Que se passe-t-il si deux processus écrivent l'**état** (pas le verrou) en même temps sans verrou ?
9. QCM — `tofu force-unlock <ID>` :
   a) supprime le verrou quel que soit son détenteur, sans vérification ; b) supprime le verrou seulement si l'ID fourni correspond à l'objet de verrou ; c) attend la fin du processus qui détient le verrou ; d) remet l'état dans sa version d'avant le verrou.
10. Chiffrement de l'état d'OpenTofu : que protège-t-il (et contre qui), que ne protège-t-il pas ? Pourquoi `pbkdf2` avec une phrase plutôt qu'une clé brute, et quelle est la conséquence de la perte de la phrase ? Comment se déroule une rotation ?
11. Un module public de la communauté est consommé par `?ref=main`. Énumère les risques (supply chain, reproductibilité, rupture) et la politique que tu proposes à MédiSphère pour `plateforme/tofu-modules`.
12. Pourquoi épingler `bpg/proxmox` avec `~> 0.115.0` plutôt que `>= 0.115` ? Que signifie un provider encore en version 0.x pour le choix de cette contrainte ?
13. Workspaces contre répertoires (et Terragrunt) : pour MédiSphère, qu'est-ce qui doit être séparé par **état**, et qu'est-ce qui peut l'être par variable ? Argumente avec le rayon d'impact, les droits et les verrous.
14. Un `tofu plan` sur le socle prend 4 minutes. D'où vient ce temps, et quelles mesures (découpage des états, `-refresh=false` en revue, `-target`, `-parallelism`, cache de providers) sont acceptables, et dans quel cadre ?
15. Que sont les valeurs éphémères et les attributs *write-only* (OpenTofu 1.11) ? Quel problème de l'état résolvent-ils, et quels secrets du socle pourraient en profiter ?
16. QCM — Une VM créée par OpenTofu est modifiée à la main dans Proxmox (mémoire 2 → 4 Go). Sans `ignore_changes`, le plan suivant :
   a) ne voit rien, l'état fait foi ; b) propose de ramener la mémoire à 2 Go ; c) met à jour l'état sans rien proposer ; d) échoue sur une incohérence.
17. Terraform (BUSL) et OpenTofu (MPL) : différences de licence, de gouvernance, et fonctionnalités divergentes déjà utilisées dans ce module. Quels risques pour MédiSphère si un module ou un outil tiers ne supporte que Terraform ?
18. Où vit la frontière entre OpenTofu et Ansible pour une VM du socle ? Donne trois réglages qui relèvent du premier, trois du second, et un cas où les deux se marchent dessus.
19. Comment prouver, à un auditeur HDS, que l'infrastructure réelle correspond au code ? Quels artefacts, quelle fréquence, quelle conservation ?
20. Tu dois supprimer `s3-01` et migrer l'état vers un autre stockage S3 (Ceph RGW, module 08). Décris la procédure sans perte : ordre des opérations, verrous, `tofu init -migrate-state`, vérifications, retour arrière.

**Critères de réussite**
- [ ] Les 20 questions ont une réponse écrite et argumentée (pour les QCM : la bonne réponse **et** pourquoi les autres sont fausses).
- [ ] Après correction, tu as identifié tes trois points les plus faibles et noté un exercice ou une lecture pour chacun.

<details><summary>Indice 1</summary>

Pour les questions 2, 3 et 16, ton journal des pannes E35 et E40 et les plans sauvegardés de ton pipeline (M05-E26) contiennent la réponse.
</details>

<details><summary>Indice 2</summary>

Pour les questions 4 à 7, la documentation d'OpenTofu (*Refactoring*, *Import*, *Removing resources*, *lifecycle*) est la référence ; pour 8 à 10, celle du backend S3 et de *State encryption*.
</details>

**Pour aller plus loin** : choisis trois questions et transforme chacune en mini-démonstration reproductible dans le bac à sable de M05-E44 (5 minutes), à présenter à Karim.
