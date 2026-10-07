# Module 03 — Palier 1 : Découverte

Avant de construire le catalogue, il faut l'outil, les droits et la compréhension. Ce palier installe Packer et son compte Proxmox, fait un premier build par clonage pour voir la mécanique de bout en bout, dissèque cloud-init (tout le module repose sur lui), puis attaque le morceau de bravoure : une installation Debian 13 **entièrement automatisée** depuis l'ISO officielle, qui produit l'image de base `tpl-debian13-base`. Karim Benali relit tout ce qui entre dans `plateforme/images` ; Sophie Laurent relit les droits du compte de Packer.

> **D'où lancer ?** Les builds et les vérifications se lancent depuis `adm01`. Certaines opérations se font en root sur `pve01` (création du compte, dépôt des ISO, *snippets*) : l'énoncé l'indique par l'invite.

---

### M03-E01 — Questions : pourquoi des images dorées ?  `Q` `★★`

> **Ticket PLAT-401** — *De : Claire Morel*
> Avant d'engager deux semaines sur les images, je veux que tu saches défendre le chantier devant le comité : ce que ça apporte, ce que ça coûte, ce qui va dans l'image et ce qui n'y va pas. Réponds par écrit, d'abord sans documentation, puis complète.

**Objectifs pédagogiques**
- Situer l'image dorée entre l'installation manuelle, la configuration au démarrage et la gestion de configuration.
- Identifier ce qui est propre à une instance et ne doit jamais être dans une image.
- Mesurer les compromis : délai de mise en service, fraîcheur des correctifs, prolifération des images, traçabilité.

**Prérequis** : M00-E11, M00-E12.
**Durée indicative** : 1 h.

Réponds par écrit dans `~/m03/e01/reponses.md`. Pour les QCM, justifie aussi pourquoi les autres propositions sont fausses.

1. Explique la différence entre *bake* (cuire dans l'image) et *fry* (configurer au démarrage). Donne pour chacun deux avantages et deux inconvénients dans le contexte de MédiSphère.
2. **(QCM)** Lequel de ces éléments a sa place **dans** une image dorée Debian de MédiSphère ?
   a) La clé publique SSH de l'administrateur `admin`.
   b) Le certificat public de l'autorité de certification interne.
   c) Le fichier `/etc/machine-id` de la VM de construction.
   d) Le jeton d'enregistrement du runner GitLab.
3. Classe chacun de ces éléments en « image », « cloud-init au clonage », « Ansible après démarrage » ou « jamais sur disque », et justifie : agent QEMU ; nom d'hôte ; adresse IP statique de `git01` ; configuration de base durcie de `sshd` ; configuration de GitLab (`gitlab.rb`) ; mot de passe de la base PostgreSQL de MédiAgenda ; correctifs de sécurité du mois ; fuseau horaire ; règles de journalisation de l'équipe ; clé privée TLS d'un serveur web.
4. Le template `tpl-debian13` (M00-E11) est-il une image dorée ? Liste ce qui lui manque pour l'être, au sens du mail de Sophie.
5. **(QCM)** Tu clones dix VMs d'un template qui a démarré une fois avant d'être converti, sans préparation. Que partagent-elles certainement ?
   a) Leur adresse MAC.
   b) Leurs clés d'hôte SSH et leur `machine-id`.
   c) Leur nom d'hôte, pour toujours.
   d) Leur UUID SMBIOS.
6. Donne trois conséquences concrètes, pour l'exploitation ou la sécurité, de la réponse à la question 5.
7. Une image dorée est reconstruite chaque dimanche ; Debian publie un correctif critique d'OpenSSH un mardi. Combien de temps une VM clonée le mercredi reste-t-elle vulnérable si rien d'autre n'est fait ? Que met-on en place pour réduire ce délai, côté image **et** côté VM déjà déployées ?
8. **(QCM)** À propos des clones Proxmox d'un template sur LVM-thin, quelle affirmation est vraie ?
   a) Un clone lié est une copie complète, simplement plus rapide.
   b) Un clone lié dépend du disque du template : on ne peut plus supprimer ce template tant que le clone existe.
   c) Un clone complet partage les blocs du template jusqu'à la première écriture.
   d) Un template peut être redémarré pour être mis à jour sans conséquence pour ses clones liés.
9. Pourquoi construire une image depuis l'**ISO** d'installation plutôt que depuis l'image *genericcloud* déjà prête (M00-E11) ? Donne aussi un argument en sens inverse.
10. Cite trois outils qui permettent de produire une image de VM, en dehors de Packer, et dis dans quel cas tu en choisirais un.
11. La licence de Packer est la BUSL 1.1. Que permet-elle et qu'interdit-elle ? Est-ce un problème pour MédiSphère ? Qu'est-ce que cela change par rapport à Terraform et OpenTofu (module 05) ?
12. Qu'est-ce que la « prolifération des images » (*image sprawl*) ? Quels mécanismes la contiennent ?
13. **(QCM)** Un template porte l'étiquette `current`. Que doit faire OpenTofu (module 05) pour créer une VM Debian ?
    a) Cloner le VMID 9010, fixé dans le code.
    b) Chercher le template étiqueté `gold`, `debian13` et `current`, et échouer s'il n'en trouve pas exactement un.
    c) Cloner le template de plus grand VMID dans la plage 9010-9029.
    d) Cloner `tpl-debian13`, qui est stable.
14. Comment prouverais-tu à l'auditeur HDS ce que contient une image donnée ? Liste les éléments de preuve à produire et où ils seraient stockés.

<details><summary>Indice</summary>

Pour 5 et 6, relis la question 8 du corrigé de M00-E11. Pour 8, la documentation de Proxmox VE, section *Templates and Clones* du chapitre *Qemu/KVM Virtual Machines*. Pour 11, le texte de la licence est publié sur le site de HashiCorp (*Business Source License*).
</details>

---

### M03-E02 — Installer Packer et créer un compte Proxmox dédié  `LAB` `★★`

> **Ticket SEC-402** — *De : Sophie Laurent* — *Copie : Karim Benali*
> Packer va créer, modifier et supprimer des VMs sur l'hyperviseur. Pas avec `root@pam`, pas avec le jeton des scripts : un compte à lui, un jeton qui expire, des droits limités au pool `lab` et aux seuls stockages et réseau dont il a besoin, et **chaque privilège justifié** dans la réponse au ticket. Le binaire vient d'un dépôt signé, pas d'un zip téléchargé au hasard. Et le TLS est vérifié, comme partout.

**Objectifs pédagogiques**
- Installer un outil depuis un dépôt APT tiers en vérifiant la clé de signature.
- Déduire les privilèges Proxmox VE 9 d'un outil à partir des appels qu'il fait à l'API.
- Comprendre comment un programme Go (Packer et son plugin) vérifie un certificat, et lui faire approuver l'autorité de `pve01` sans désactiver la vérification.
- Créer le projet `plateforme/images` avec la configuration standard de la plateforme.

**Prérequis** : M00-E17 (modèle de permissions, jeton à privilèges séparés), M00-E28 (zone SDN `lab`), M02-E02 (création d'un projet de la plateforme), M02-E08 (ancre de confiance conforme pour `pve01`).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Dépôt APT HashiCorp : `https://apt.releases.hashicorp.com`, suite `trixie`, composant `main`, clé publiée sur `https://apt.releases.hashicorp.com/gpg`. Format des sources : fichier `.sources` (deb822) avec `Signed-By`.
- Compte : `wb-packer@pve`, jeton `packer` à privilèges séparés, expiration à un an au plus. Rôle personnalisé `WBPacker` sur `/pool/lab`.
- Ce que Packer doit pouvoir faire (modules 03 à 05) : créer une VM dans le pool `lab` et la supprimer ; cloner un template du pool ; monter une ISO **déjà déposée** sur `hdd-bulk` ; créer des disques et un lecteur cloud-init sur `local-nvme` ; régler CPU, mémoire, contrôleur, affichage, port série, carte réseau sur le VNet `vsandbox` ; régler les paramètres cloud-init ; démarrer, arrêter ; **taper au clavier** de la VM (ligne de démarrage de l'installeur) ; lire son adresse IP par l'agent QEMU ; convertir en template ; modifier les étiquettes et les notes d'un template.
- Interdits : tout ce qui est hors du pool ; téléverser ou télécharger des ISO (elles sont déposées par un administrateur, E05) ; exécuter des commandes ou lire des fichiers dans les invités ; administrer le nœud, les stockages, les utilisateurs.
- Fichier d'accès sur `adm01` : `~/.config/workbook/pve-packer.env`, mode 600, avec exactement ces variables : `PKR_VAR_proxmox_url`, `PKR_VAR_proxmox_username` (`wb-packer@pve!packer`), `PKR_VAR_proxmox_token`, `PKR_VAR_proxmox_node`.
- Autorité de `pve01` : l'ancre conforme construite en M02-E08 (`~/.config/workbook/pve-root-ca.pem`).
- Projet : `plateforme/images`, clone `~/src/images`, configuration standard (M02-E02), plus deux contrôles pre-commit propres au projet : `packer fmt -check -recursive` et `packer validate -syntax-only` sur chaque image.

**Travail demandé**

1. **Packer.** Déclare le dépôt HashiCorp. Avant de l'utiliser, affiche l'empreinte complète de la clé téléchargée (`gpg --show-keys --with-fingerprint`) et compare-la à celle que publie HashiCorp sur sa page de sécurité officielle. Installe Packer, vérifie la version (`packer version`), et note d'où vient le paquet (`apt-cache policy packer`).
   > ⚠️ **Attention** : une clé ajoutée dans `Signed-By` permet à son détenteur de signer **n'importe quel** paquet installable sur `adm01`, y compris un paquet qui remplacerait un outil du système. Restreins-la au seul dépôt HashiCorp (fichier `.sources` dédié, jamais dans `/etc/apt/trusted.gpg.d/`).
2. **Privilèges.** Pour chaque opération de la liste ci-dessus, trouve dans l'API viewer de Proxmox VE 9 l'appel correspondant et le contrôle de permissions exact (privilège **et** chemin). Indice de méthode : le plugin passe par `POST /nodes/{node}/qemu`, `…/clone`, `…/config`, `…/status/start`, `…/sendkey`, `…/agent/network-get-interfaces`, `…/template`, `DELETE …/qemu/{vmid}`. Écris la liste minimale, une ligne de justification par privilège, et une ligne par privilège écarté qui « aurait pu servir ».
3. **Compte.** Crée les rôles nécessaires, l'utilisateur (sans mot de passe), le jeton, puis les ACL sur `/pool/lab`, `/storage/local-nvme`, `/storage/hdd-bulk` et `/sdn/zones/lab/vsandbox`. Contrôle les droits effectifs du jeton sur chacun de ces chemins **et** sur `/` (`pveum user token permissions`).
4. **Secret.** Crée `~/.config/workbook/pve-packer.env` avec les bons droits **avant** d'y écrire, sans que le secret passe par l'historique du shell. Inscris le jeton au registre des secrets (`docs/socle/registre-secrets.md` de `plateforme/medisphere`, par MR).
5. **TLS.** Trouve comment le plugin vérifie le certificat de l'API (documentation du plugin, et son code source : `builder/proxmox/common/client.go`). Fais approuver l'autorité de `pve01` par le mécanisme qu'il utilise, sans `insecure_skip_tls_verify`. Prouve-le avec `curl` **sans** `--cacert` : `GET /version` avec le jeton répond 200.
6. **Projet.** Crée `plateforme/images` avec la configuration standard, clone-le dans `~/src/images`, et ajoute par MR : les fichiers standard, un `.gitignore` adapté (sorties de build, cache de Packer, ISO, fichiers de variables locaux), les deux contrôles Packer dans pre-commit (le second appelle un petit script `outils/valider-syntaxe.sh`), un `README.md`. Le runner n'a pas encore Packer (il l'aura en E15) : trouve comment le job `pre-commit` de la CI peut sauter ces deux contrôles **temporairement**, et marque-le comme une dette à solder.
7. Réponds au ticket : privilèges et ACL justifiés, emplacement du secret, mécanisme TLS retenu et ses limites, procédure de renouvellement du jeton.

**Critères de réussite**
- [ ] `packer version` affiche 1.16.x ; le paquet vient de `apt.releases.hashicorp.com`, signé par une clé limitée à ce dépôt.
- [ ] Le jeton `wb-packer@pve!packer` a la séparation des privilèges et une date d'expiration.
- [ ] Le rôle `WBPacker` permet de taper au clavier et de lire l'agent, mais ne contient aucun privilège `Sys.*`, `Permissions.*`, `User.*`, `Realm.*`, ni `VM.GuestAgent.Unrestricted`, `VM.GuestAgent.File*`, `Datastore.Allocate`, `Datastore.AllocateTemplate`.
- [ ] Droits effectifs du jeton : création de VM sur `/pool/lab`, allocation d'espace sur `local-nvme`, lecture seule sur `hdd-bulk`, usage du VNet `vsandbox`, rien sur `/`.
- [ ] `pve-packer.env` est en mode 600 dans un dossier 700, hors de tout dépôt ; le jeton est au registre des secrets.
- [ ] `curl` sans `--cacert` joint l'API de `pve01` avec certificat vérifié.
- [ ] `plateforme/images` existe, conforme aux règles de la plateforme ; `main` contient la configuration pre-commit avec les contrôles Packer.

**Vérification** : `lab/bin/check 03 02`

<details><summary>Indice 1</summary>

Le plugin est écrit en Go et n'a pas d'option « chemin vers une autorité ». Dans `client.go`, regarde comment est construit le `tls.Config` : si aucune liste d'autorités n'est fournie, la bibliothèque standard de Go utilise celle du système. Sur Debian, où la cherche-t-elle, et quelles variables d'environnement peuvent la remplacer ?
</details>

<details><summary>Indice 2</summary>

`boot_command` passe par l'appel `PUT /nodes/{node}/qemu/{vmid}/sendkey`. Regarde son contrôle de permissions : il surprend souvent. Pour l'adresse IP, Proxmox VE 9 a remplacé `VM.Monitor` par la famille `VM.GuestAgent.*` : prends la plus étroite qui suffit. Pour monter une ISO déjà présente, lis la fonction qui contrôle l'accès à un volume de type `iso` : la lecture du stockage suffit-elle ?
</details>

<details><summary>Indice 3</summary>

Pour sauter des hooks pre-commit en CI, le gabarit `qualite.yml` utilise déjà la variable `SKIP`. Une définition locale d'un job inclus est **fusionnée** avec celle du gabarit : tu peux redéfinir uniquement ses `variables`. N'oublie pas ce que le gabarit y mettait déjà.
</details>

**Pour aller plus loin** (facultatif) : compare avec un `packer` installé depuis l'archive zip officielle et son fichier `SHA256SUMS` signé (vérification `gpg --verify`). Lequel des deux modes facilite la mise à jour et l'inventaire des versions sur le parc ?

---

### M03-E03 — Premier build : `proxmox-clone` depuis `tpl-debian13`  `LAB` `★`

> **Ticket PLAT-403** — *De : Karim Benali*
> Avant d'écrire nos vraies images, fais un premier build sans enjeu, pour voir ce que fait Packer à chaque étape : un clone de `tpl-debian13`, un fichier ajouté, un paquet installé, et un template en sortie. Puis clone ce template deux fois et compare les clones : je veux que tu voies de tes yeux pourquoi on ne fera **jamais** ça en production.

**Objectifs pédagogiques**
- Lire et écrire un fichier Packer HCL : bloc `packer` et `required_plugins`, `variable`, `source`, `build`, `provisioner`.
- Suivre les étapes d'un build : clonage, configuration, démarrage, connexion SSH, provisioners, arrêt, conversion.
- Constater les valeurs par défaut du plugin et leurs effets sur un clone.
- Observer ce que deux clones d'un template non préparé ont en commun.

**Prérequis** : M03-E02.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Brouillon : `~/m03/e03/essai.pkr.hcl` (hors du projet, non versionné).
- Source : template 9000 `tpl-debian13`, clone complet. Résultat : template d'essai **9090** `tpl-essai-e03`, pool `lab`, étiquettes `essai` et `debian13`.
- Communicateur : SSH avec l'utilisateur `packer`. Le builder `proxmox-clone` le crée par cloud-init sur la VM de build, avec une paire de clés éphémère qu'il génère lui-même.
- VM de build sur `vsandbox` en DHCP, résolveur 10.10.20.10, domaine `par1.medisphere.internal`.
- Clones de comparaison : 2030 `m03-essai-a` et 2031 `m03-essai-b` (clones liés de 9090, pool `lab`, étiquette `env-m03`, `vsandbox` en DHCP, `ciuser admin` et ta clé de `adm01`).

**Travail demandé**

1. Écris `essai.pkr.hcl` : le bloc `packer` (plugin `github.com/hashicorp/proxmox`, version `~> 1.2.4`), quatre variables pour l'accès (le jeton marqué `sensitive`), une source `proxmox-clone` et un bloc `build` avec un provisioner `shell` qui attend la fin de cloud-init, écrit `/etc/motd` et installe `htop`.
2. Charge les accès dans ton shell sans les afficher (`set -a; . ~/.config/workbook/pve-packer.env; set +a`), puis :
   ```
   admin@adm01:~/m03/e03$ packer init .
   admin@adm01:~/m03/e03$ packer fmt .
   admin@adm01:~/m03/e03$ packer validate .
   admin@adm01:~/m03/e03$ packer build .
   ```
   Pendant le build, suis la VM dans l'interface web (*Console*, *Hardware*, *Cloud-Init*, *Task History*). Note dans `~/m03/e03/notes.md` chaque étape affichée par Packer et ce qu'elle fait côté Proxmox.
3. Compare `qm config 9000` et `qm config 9090`. Qu'est-ce qui a changé alors que tu ne l'as pas demandé ? D'où viennent ces valeurs ? Corrige ton fichier pour que le matériel de 9090 soit identique à celui de 9000 (contrôleur, CPU, mémoire, console série), et reconstruis.
   > ⚠️ **Attention** : pour reconstruire, supprime d'abord 9090 (`qm destroy 9090` sur `pve01`, après avoir vérifié avec `qm config 9090` que c'est bien `tpl-essai-e03`). Pas de `-force` ici : il supprime **sans demander** la VM qui porte le `vm_id` du fichier, quelle qu'elle soit.
4. Que contient le champ *Cloud-Init* de 9090 ? Et `ciuser`, `sshkeys` ? Explique ce que Packer a retiré et ajouté avant la conversion.
5. Crée les clones 2030 et 2031, démarre-les et compare : `/etc/machine-id`, empreinte des clés d'hôte SSH (`ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`), adresse IP obtenue, comptes présents dans `/etc/passwd`, contenu de `/etc/sudoers.d/`. Note ce que tu observes et ce que cela implique.
6. Détruis 2030 et 2031, lance la vérification, puis supprime 9090.

**Critères de réussite**
- [ ] `essai.pkr.hcl` passe `packer fmt -check` et `packer validate`.
- [ ] Le template 9090 a été créé et converti par le jeton `wb-packer@pve!packer` (journal des tâches).
- [ ] Le matériel de 9090 est identique à celui de 9000 (contrôleur `virtio-scsi-single`, CPU `x86-64-v2-AES`, 2 Go, `serial0` et `vga: serial0`, agent), avec un lecteur cloud-init.
- [ ] `notes.md` explique chaque étape du build et les points communs des deux clones.
- [ ] Les VMs 2030 et 2031 ont été détruites.

**Vérification** : `lab/bin/check 03 03` (avant de supprimer 9090)

<details><summary>Indice 1</summary>

Dans la documentation du plugin, chaque option a une valeur par défaut. Un builder `proxmox-clone` **applique** sa configuration au clone : une option absente du fichier ne veut pas dire « garder celle du template », mais souvent « appliquer la valeur par défaut du plugin ».
</details>

<details><summary>Indice 2</summary>

Si Packer attend SSH indéfiniment : il lit l'adresse de la VM par l'agent QEMU. Sur un clone de 9000, l'agent n'est installé qu'au premier démarrage par le *vendor-data* : regarde la console série et `cloud-init status` dans la VM. `PACKER_LOG=1 packer build .` affiche le détail des échanges.
</details>

**Pour aller plus loin** (facultatif) : lance un build avec `-on-error=ask`, provoque une erreur dans le provisioner (commande inexistante) et explore les choix proposés. Dans quel cas `-debug` est-il utile, et pourquoi ne faut-il pas l'utiliser en CI ?

---

### M03-E04 — cloud-init en profondeur : étapes, modules, journaux  `LAB` `★★`

> **Ticket PLAT-404** — *De : Nadia Roussel*
> La semaine dernière, une VM clonée a mis un quart d'heure à devenir joignable, et une autre n'a jamais eu son agent QEMU. Personne n'a su dire où regarder. Toutes nos images vont reposer sur cloud-init : je veux que l'équipe sache ce qu'il fait, dans quel ordre, quand il se relance, et où il écrit. Écris-moi une fiche de diagnostic d'une page.

**Objectifs pédagogiques**
- Décrire les étapes de démarrage de cloud-init, leurs services systemd et les modules de chacune.
- Comprendre les fréquences (`always`, `instance`, `once`) et ce qui déclenche une « nouvelle instance ».
- Savoir lire ce que Proxmox fournit (*NoCloud*), ce que cloud-init a détecté et ce qu'il a fait (journaux, état, données d'instance).
- Valider une configuration et relancer proprement.

**Prérequis** : M00-E11, M03-E03.
**Durée indicative** : 2 h.

**Contexte technique**
- VM : **2032** `m03-ci`, clone complet de 9000, pool `lab`, étiquette `env-m03`, `vsandbox` en DHCP, `ciuser admin`, ta clé publique de `adm01`.
- *Vendor-data* de l'exercice : snippet `hdd-bulk:snippets/m03-e04-vendor.yaml` (fichier `/mnt/hdd-bulk/snippets/m03-e04-vendor.yaml` sur `pve01`). Il doit **reprendre** ce que fait celui de 9000 (agent QEMU, fuseau horaire) et ajouter :
  - une commande `bootcmd` qui ajoute à `/var/log/m03-e04.log` une ligne `bootcmd <date> <identifiant de démarrage>` (`/proc/sys/kernel/random/boot_id`) ;
  - une commande `runcmd` qui ajoute une ligne `runcmd <date> instance=<identifiant d'instance>`.
- cloud-init 25.1 (Debian 13) : documentation <https://cloudinit.readthedocs.io/en/25.1/>.

**Travail demandé**

1. **Avant le premier démarrage.** Crée la VM 2032, pose le *vendor-data* de l'exercice (`qm set … --cicustom`), puis lis ce que Proxmox va fournir : `qm cloudinit dump 2032 user`, `network`, `meta`. Quel est l'identifiant d'instance ? D'où vient-il ? Pourquoi la VM aura-t-elle un `vendor-data` différent de celui de 9000 ?
2. **Premier démarrage.** Démarre la VM en suivant la console série. Dans la VM :
   ```
   admin@m03-ci:~$ cloud-init status --long
   admin@m03-ci:~$ systemctl list-units --all 'cloud*'
   admin@m03-ci:~$ cloud-init analyze show
   admin@m03-ci:~$ cloud-init analyze blame | head
   ```
   Associe chaque étape à son service systemd et à la liste de modules de `/etc/cloud/cloud.cfg` qu'elle exécute. Quel module a installé l'agent QEMU, à quelle étape, et pourquoi si tard ?
3. **Ce qui a été détecté.** Trouve la source de données retenue (`cloud-id`, `/run/cloud-init/ds-identify.log`, `cloud-init query --all`) et où cloud-init a rangé `user-data`, `vendor-data` et l'état de l'instance (`/var/lib/cloud/instance/`, `/var/lib/cloud/instances/`, dossier `sem/`).
4. **Fréquences.** Redémarre deux fois la VM et observe `/var/log/m03-e04.log`. Puis change un paramètre cloud-init côté Proxmox (par exemple ajoute une deuxième clé SSH, ou change `--searchdomain`), redémarre, et observe de nouveau le fichier, l'identifiant d'instance et l'empreinte des clés d'hôte SSH. Recommence en modifiant **seulement** le snippet *vendor-data* (ajoute un commentaire). Explique chaque différence.
5. **Relancer.** Fais `sudo cloud-init clean --logs` puis redémarre : que se passe-t-il ? Quelle différence avec le cas de l'étape 4 ?
6. **Valider et casser.** Valide la configuration du système (`sudo cloud-init schema --system`). Introduis une erreur d'indentation dans le snippet, redémarre après un `cloud-init clean --logs`, et trouve où l'erreur apparaît (statut, journal, schéma). Remets le snippet correct et refais un démarrage propre.
7. **La fiche.** Rédige `~/m03/e04/fiche-cloud-init.md` pour l'astreinte : les étapes et leurs services, les fichiers à lire dans l'ordre, les commandes de diagnostic, les causes classiques de « VM injoignable après clonage », et l'avertissement sur ce qui déclenche une nouvelle instance.
8. Lance la vérification, puis détruis la VM 2032 et supprime le snippet de l'exercice.

**Critères de réussite**
- [ ] La VM 2032 utilise le *vendor-data* `m03-e04-vendor.yaml`, qui commence par `#cloud-config`, reprend l'agent QEMU et contient `bootcmd` et `runcmd`.
- [ ] `/var/log/m03-e04.log` montre au moins 4 démarrages, moins d'exécutions de `runcmd` que de `bootcmd`, et au moins deux identifiants d'instance différents.
- [ ] Au dernier démarrage, cloud-init a terminé (`status: done`) et `cloud-init schema --system` ne signale aucune erreur.
- [ ] La fiche explique pourquoi un changement de *vendor-data* seul ne relance pas les modules « une fois par instance ».

**Vérification** : `lab/bin/check 03 04` (VM 2032 démarrée)

<details><summary>Indice 1</summary>

Chaque module a une fréquence par défaut, indiquée dans la *Module reference* de la documentation (« Module frequency »). `runcmd` n'exécute rien lui-même : il écrit un script que le module `scripts_user` lance plus tard.
</details>

<details><summary>Indice 2</summary>

Pour savoir comment Proxmox calcule l'identifiant d'instance, compare la sortie de `qm cloudinit dump 2032 meta` avant et après chaque type de modification. Quelles données entrent dans ce calcul, et lesquelles n'y entrent pas ?
</details>

<details><summary>Indice 3</summary>

Les journaux : `/var/log/cloud-init.log` (détaillé), `/var/log/cloud-init-output.log` (sortie des commandes), `journalctl -u cloud-init-local -u cloud-init-network -u cloud-config -u cloud-final -b`. `cloud-init status --format json` donne les erreurs et avertissements récupérables.
</details>

**Pour aller plus loin** (facultatif) : `cloud-init single --name ntp --frequency always` permet de rejouer un seul module. Lis la note de la documentation sur l'idempotence des modules et cite un module qu'il serait dangereux de rejouer.

---

### M03-E05 — Construire depuis l'ISO : `proxmox-iso` et preseed Debian 13  `LAB` `★★★`

> **Ticket PLAT-405** — *De : Sophie Laurent* — *Copie : Karim Benali*
> Première vraie image : Debian 13 installée depuis l'ISO officielle, dont la **signature** a été vérifiée, par une installation entièrement automatisée, sans un clic. Le résultat devient le template de base `tpl-debian13-base`, à partir duquel on fabriquera les images dorées. Je veux pouvoir lire dans les notes du template quelle ISO a servi, avec sa somme. Et je ne veux voir aucun mot de passe permanent nulle part.

**Objectifs pédagogiques**
- Vérifier une ISO de bout en bout : signature du fichier de sommes (clé dont l'empreinte est contrôlée), puis somme de l'ISO.
- Écrire un *preseed* Debian 13 complet et le servir par le serveur HTTP de Packer.
- Piloter le chargeur de démarrage de l'ISO avec `boot_command`.
- Comprendre le chemin réseau d'un build : VM de build, installeur, serveur HTTP, miroirs, communicateur SSH ; ouvrir le seul flux nécessaire.
- Faire les choix d'une image destinée à être clonée : partitionnement, pile réseau compatible avec cloud-init, console série.

**Prérequis** : M03-E02, M03-E03, M03-E04, M00-E13 (DNS), M00-E14 (DHCP du VLAN 99).
**Durée indicative** : 4 à 5 h.

**Contexte technique**
- Projet : `~/src/images`, dossier `debian13-base/` (`build.pkr.hcl`, `variables.pkr.hcl`, `http/preseed.cfg`), valeurs d'environnement non secrètes dans `vars/lab.pkrvars.hcl` (pool, stockages, VNet de build, ports HTTP).
- ISO : Debian 13 *netinst* amd64, dernière version intermédiaire (`https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/`), avec `SHA256SUMS` et `SHA256SUMS.sign`. Clé de signature : « Debian CD signing key », empreinte publiée sur <https://www.debian.org/CD/verify>. Dépôt **à l'avance** dans le contenu `iso` de `hdd-bulk` par un script `outils/deposer-iso.sh` du projet, lancé en root sur `pve01` : le jeton de Packer n'a pas le droit de télécharger (E02).
- Template : **9001** `tpl-debian13-base`, étiquettes `base` et `debian13`, matériel des templates du lab (voir l'introduction), console série **et** affichage `std` (pour suivre l'installation dans la console web), disque de 8 Go sur `local-nvme`, lecteur cloud-init vide sur le template, ISO retirée à la fin.
- Serveur HTTP de Packer : `http_bind_address = 10.10.10.10`, ports 8100-8199. Flux à ouvrir sur `gw01` : `vsandbox` → `adm01` TCP 8100-8199, avec les précautions de M00-E21 (session ouverte, `nft -c`, retour arrière programmé), reporté dans `docs/socle/matrice-flux.md`.
- Compte de construction : `packer`, mot de passe **jetable** fourni à chaque build par la variable d'environnement `PKR_VAR_build_password` (tu la génères juste avant le build ; E08 automatisera). Pas de mot de passe `root`.
- Contraintes sur le système installé :
  - une seule partition racine ext4, **dernière** du disque, sans swap ;
  - paquets : système minimal + serveur SSH, `qemu-guest-agent`, `cloud-init`, `cloud-guest-utils`, `sudo`, `ca-certificates` ;
  - **pile réseau identique à celle de l'image *genericcloud*** : netplan (`netplan.io`) + `systemd-networkd` + `systemd-resolved`, sans `ifupdown` ;
  - noyau avec console sur `tty0` **et** `ttyS0` ; fuseau `Europe/Paris` ; heure prise sur la passerelle du VLAN pendant l'installation.
- VM de contrôle : **2030** `m03-base-test`, clone lié de 9001, pool `lab`, étiquette `env-m03`, sur `vsandbox` avec une adresse **statique** 10.10.99.250/24 (plage « tests » du VLAN, PLAN.md §4.2) (passerelle 10.10.99.1) donnée par cloud-init, résolveur 10.10.20.10, domaine `par1.medisphere.internal`, `ciuser admin`, ta clé.

**Travail demandé**

1. **L'ISO.** Écris `outils/deposer-iso.sh` : télécharge le fichier de sommes et sa signature, importe la clé de signature et **contrôle son empreinte complète**, vérifie la signature (et qu'elle est bien faite par cette clé), choisit la ligne de l'ISO *netinst*, télécharge l'ISO sous un nom provisoire, vérifie sa somme, et seulement alors la dépose sous son nom définitif. Il affiche le nom et la somme, que tu reportes dans `variables.pkr.hcl`. Lance-le sur `pve01` depuis `adm01` (`ssh pve01 'bash -s' -- debian13 < outils/deposer-iso.sh`).
2. **Le flux.** Ajoute la règle sur `gw01` et mets à jour la matrice des flux. Quel autre flux le build utilise-t-il, et pourquoi est-il déjà ouvert ?
3. **Le preseed.** Écris `http/preseed.cfg` à partir de l'exemple officiel de *trixie*. Il est servi par `http_content` en tant que **gabarit** (`templatefile`) : le nom et le mot de passe du compte de construction y sont injectés au moment du build, jamais écrits dans le dépôt. Pour ce qui doit être fait à la fin de l'installation (droits `sudo` du compte de construction, pile réseau, retrait d'`ifupdown`), préfère un script récupéré sur le même serveur HTTP à une longue ligne de `late_command`.
   Questions à traiter dans ton journal : pourquoi une seule partition, en dernier ? Pourquoi retirer `ifupdown` (lis comment cloud-init choisit son moteur de rendu réseau) ? Que devient le mot de passe de construction après le build ?
4. **Le builder.** Écris `build.pkr.hcl` avec le bloc `boot_iso {}` (pas les options de premier niveau `iso_file`, `iso_url`, dépréciées), le serveur HTTP, le communicateur SSH (l'adresse est lue par l'agent QEMU) et un délai SSH réaliste pour une installation. Pour `boot_command`, regarde l'ISO : quel chargeur de démarrage s'affiche en BIOS ? Comment obtenir une invite et lancer l'entrée d'installation automatisée avec l'URL du preseed ? Un provisioner contrôle le résultat (agent actif, pile réseau, pas d'`ifup`, version de cloud-init) puis **verrouille** le compte de construction (E07 le supprimera).
5. **Le build.** Génère le mot de passe jetable dans ton shell sans l'afficher, valide, puis construis :
   ```
   admin@adm01:~/src/images/debian13-base$ export PKR_VAR_build_password="$(openssl rand -base64 24)"
   admin@adm01:~/src/images/debian13-base$ packer validate -var-file=../vars/lab.pkrvars.hcl .
   admin@adm01:~/src/images/debian13-base$ packer build -force -var-file=../vars/lab.pkrvars.hcl .
   ```
   > ⚠️ **Attention** : `-force` supprime, au début du build, la VM qui porte le `vm_id` du fichier. Vérifie avant **chaque** build que `vm_id` vaut 9001 et que 9001 est libre ou contient l'ancien `tpl-debian13-base`. Si le build échoue, la VM de construction est supprimée par Packer ; s'il est interrompu brutalement, vérifie avec `qm list` qu'aucune VM 9001 orpheline ne reste allumée.
   Suis l'installation dans la console web. Mesure la durée totale.
6. **Le contrôle.** Clone 9001 en 2030 avec l'adresse statique du contexte, démarre-la, connecte-toi. Vérifie : nom d'hôte, adresse, résolveur effectif (`resolvectl status`), taille de la racine après un `qm disk resize 2030 scsi0 +4G` et redémarrage, console série (`qm terminal 2030`), absence de mot de passe utilisable pour `packer`.
7. MR avec `debian13-base/`, `vars/lab.pkrvars.hcl` et `outils/deposer-iso.sh`, pipeline vert, fusion. Lance la vérification, puis détruis 2030.

**Critères de réussite**
- [ ] L'ISO *netinst* est sur `hdd-bulk`, et `deposer-iso.sh` refuse toute ISO dont la signature du fichier de sommes ou la somme ne correspond pas.
- [ ] Le template 9001 `tpl-debian13-base` existe dans le pool `lab`, avec les étiquettes, le matériel et le lecteur cloud-init demandés, sans ISO montée, et ses notes citent l'ISO et sa somme.
- [ ] `gw01` autorise `vsandbox` → `adm01` TCP 8100-8199 et rien de plus ; la matrice des flux est à jour.
- [ ] La VM 2030 clonée de 9001 a l'adresse 10.10.99.250, utilise 10.10.20.10 comme résolveur et sa racine a grandi avec son disque.
- [ ] Aucun mot de passe ni jeton n'est écrit dans le dépôt ; `debian13-base/` est sur `main` et passe `packer fmt -check`.

**Vérification** : `lab/bin/check 03 05` (VM 2030 démarrée)

<details><summary>Indice 1</summary>

L'ISO *netinst* de Debian démarre en BIOS sur isolinux avec un menu graphique : la touche Échap donne l'invite `boot:`. Regarde dans l'ISO le fichier `isolinux/adtxt.cfg` : une entrée porte un nom court qui active le mode automatique. L'annexe B du guide d'installation (section *Auto mode*) explique quels paramètres ajouter et pourquoi les questions de langue et de clavier peuvent alors venir du preseed.
</details>

<details><summary>Indice 2</summary>

Dans un gabarit `templatefile`, `${…}` est interprété par Packer : un `$` suivi d'une accolade destiné au shell de l'installeur s'écrit `$${…}`. Pour retrouver, depuis `late_command`, l'adresse du serveur qui a servi le preseed, l'installeur garde l'URL dans la question `preseed/url` (`debconf-get`).
</details>

<details><summary>Indice 3</summary>

Si l'installation se termine mais que Packer attend SSH : l'agent tourne-t-il dans le système installé ? La VM a-t-elle une adresse (le DHCP du VLAN 99 passe par le relais de `gw01`) ? Si l'installeur bloque sur « téléchargement du fichier de préconfiguration » : la règle sur `gw01`, l'adresse d'écoute de Packer, le pare-feu local d'`adm01`. Pour le résolveur des clones : quel moteur de rendu cloud-init a-t-il choisi (`/var/log/cloud-init.log`, « Selected renderer ») ?
</details>

**Pour aller plus loin** (facultatif) : compare avec `iso_download_pve = true` dans `boot_iso` (Proxmox télécharge lui-même l'ISO). Quel privilège faudrait-il ajouter au jeton, et pourquoi Proxmox le classe-t-il parmi les privilèges réservés à root ?
