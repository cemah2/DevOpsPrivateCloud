# Module 03 — Palier 2 : Opérationnel

L'image de base Debian existe, construite depuis une ISO vérifiée. Il reste à en faire un **produit** : une seconde famille (Rocky Linux) pour l'éditeur de Julien, des templates réellement prêts à être clonés, des secrets de build traités proprement, une première image dorée avec le contenu exigé par Sophie, un versionnage et une publication qui disent aux consommateurs quelle image utiliser. C'est aussi le palier où cloud-init sert à autre chose qu'à créer un utilisateur, et où Lucas propose sa propre image.

> **Rappel** : toute VM de test (2030-2039) est détruite à la fin de son exercice, tout template d'essai (9090-9099) supprimé. Les vérifications se lancent depuis `adm01`.

---

### M03-E06 — Image de base Rocky Linux 10 avec kickstart  `LAB` `★★★`

> **Ticket DEV-420** — *De : Julien Petit* — *Copie : Claire Morel*
> Le logiciel de facturation que nous intégrons à MédiAgenda n'est certifié que sur RHEL et ses dérivés. Il me faut une image Rocky Linux 10 au même niveau que la Debian : construite depuis l'ISO, signature vérifiée, prête pour cloud-init. Mes développeurs connaissent mal la famille Red Hat : documente les différences qui comptent.

**Objectifs pédagogiques**
- Écrire un fichier *kickstart* pour Rocky Linux 10 et le valider hors build.
- Piloter le menu GRUB 2 d'une ISO de la famille RHEL avec `boot_command`.
- Connaître les exigences matérielles de RHEL 10 (niveau de microarchitecture x86-64) et leur traduction dans Proxmox.
- Repérer les différences Debian / RHEL qui touchent une image : réseau, SELinux, pare-feu, gestion des paquets, traces de l'installeur.

**Prérequis** : M03-E05.
**Durée indicative** : 3 h.

**Contexte technique**
- Dossier `rocky10-base/` (`build.pkr.hcl`, `variables.pkr.hcl`, `http/ks.cfg`), mêmes conventions que `debian13-base/`.
- ISO : Rocky Linux 10, dernière version intermédiaire, variante *boot* (l'installeur seul ; les paquets viennent des dépôts en ligne `BaseOS` et `AppStream` de `dl.rockylinux.org`). Fichiers `CHECKSUM` et `CHECKSUM.asc` dans `https://download.rockylinux.org/pub/rocky/10/isos/x86_64/` ; clé « Release Engineering (Rocky Linux 10) », clé publique `https://dl.rockylinux.org/pub/rocky/RPM-GPG-KEY-Rocky-10`, empreinte publiée sur <https://rockylinux.org/resources/gpg-key-info>. Dépôt sur `hdd-bulk` avec `outils/deposer-iso.sh rocky10`.
- Template **9002** `tpl-rocky10-base`, étiquettes `base` et `rocky10`, même matériel que 9001 **sauf** le type de CPU (voir l'introduction).
- Compte de construction `packer` (groupe `wheel`), mot de passe jetable comme en E05, `root` verrouillé, SELinux en mode `enforcing`, pare-feu actif avec SSH autorisé.
- Disque : partitions classiques (pas de LVM), racine en dernier, sans swap ; console série comme pour Debian.
- Paquets : environnement minimal, `qemu-guest-agent`, `cloud-init`, `cloud-utils-growpart`, `sudo`.
- VM de contrôle : **2031** `m03-rocky-test`, clone lié de 9002, `vsandbox` en DHCP, `ciuser admin`, ta clé.
- Validation hors build : `ksvalidator` (paquet Python `pykickstart`, dans un environnement `uv` jetable sur `adm01`), version de syntaxe `RHEL10`.

**Travail demandé**

1. Étends `outils/deposer-iso.sh` à la famille `rocky10` (format différent du fichier de sommes, clé différente) et dépose l'ISO.
2. Écris `http/ks.cfg`. Le fichier est un gabarit Packer comme le preseed. Valide-le **rendu** (avec un mot de passe factice) par `ksvalidator -v RHEL10`. Questions pour ton journal : que fait `autopart --type=plain --noswap` sur un disque vierge démarré en BIOS (quelles partitions crée-t-il) ? Pourquoi pas de LVM pour une image destinée au clonage ?
3. Pour `boot_command`, lis le fichier `boot/grub2/grub.cfg` de l'ISO (par exemple en la montant sur `pve01` en lecture seule : `mount -o loop,ro`). Quelle entrée est sélectionnée par défaut et pourquoi ne convient-elle pas ? Comment éditer la ligne `linux` d'une entrée et démarrer l'entrée modifiée ?
4. Écris `build.pkr.hcl`. Contraint le type de CPU par une **règle de validation** de la variable : le build doit refuser de démarrer avec un type qui ne convient pas à Rocky Linux 10.
5. Construis 9002 (même méthode qu'en E05). Pendant l'installation, ouvre la console : où Anaconda affiche-t-il sa progression en mode texte ?
6. Clone 9002 en 2031 et vérifie : cloud-init a terminé, SELinux est en mode `enforcing`, `firewalld` autorise SSH, `admin` a `sudo`, l'agent répond. Que contient `/root` ? Que contient `/var/log/anaconda/` ? Note ce qui devra être nettoyé en E07, et pourquoi c'est sensible.
7. Rédige pour Julien `~/m03/e06/debian-vs-rocky.md` : une page sur les différences qui comptent pour une image (paquets, réseau, SELinux, pare-feu, sudo, mises à jour, traces de l'installeur).
8. MR, fusion. Lance la vérification, puis détruis 2031.

**Critères de réussite**
- [ ] L'ISO Rocky 10 *boot* est sur `hdd-bulk`, déposée après vérification de la signature et de la somme.
- [ ] `ks.cfg` rendu passe `ksvalidator -v RHEL10`.
- [ ] Le template 9002 `tpl-rocky10-base` existe, avec un type de CPU compatible avec Rocky Linux 10, les étiquettes et le matériel demandés, un lecteur cloud-init, sans ISO montée.
- [ ] Un `packer validate` avec `-var cpu_type=x86-64-v2-AES` échoue sur la règle de validation.
- [ ] La VM 2031 a terminé cloud-init, SELinux est en `enforcing`, `admin` a `sudo`.

**Vérification** : `lab/bin/check 03 06` (VM 2031 démarrée)

<details><summary>Indice 1</summary>

Dans l'éditeur de GRUB, la première ligne de l'entrée est un `setparams`, la ligne `linux` vient ensuite ; `Ctrl-x` démarre. La syntaxe de `boot_command` pour maintenir une touche : `<leftCtrlOn>` … `<leftCtrlOff>`. Les paramètres d'Anaconda utiles : `inst.ks=`, `inst.text`.
</details>

<details><summary>Indice 2</summary>

Avec le type de CPU par défaut de Proxmox (`x86-64-v2-AES`) ou celui du plugin (`kvm64`), le noyau de Rocky Linux 10 s'arrête très tôt : regarde la console. La documentation de RHEL 10 indique le niveau d'architecture minimal. Dans `variables.pkr.hcl`, un bloc `validation { condition … error_message … }` ; attention, Packer exige que le message soit une phrase complète (majuscule, point final).
</details>

<details><summary>Indice 3</summary>

Anaconda écrit le kickstart d'origine **et** celui qu'il a reconstitué dans `/root`. Ouvre-les : que contient la ligne `user` du premier ?
</details>

**Pour aller plus loin** (facultatif) : remplace l'ISO *boot* par l'ISO *minimal* (qui contient les paquets) et compare durée de build, dépendance au réseau et reproductibilité.

---

### M03-E07 — Provisioners et préparation au clonage  `LAB` `★★`

> **Ticket SEC-421** — *De : Sophie Laurent*
> Tu m'as montré en E03 deux clones avec les mêmes clés SSH et le même `machine-id`. C'est une faille : un serveur peut en usurper un autre sans que le client SSH le voie, et nos journaux centralisés vont confondre les machines. Je veux que chaque image soit **préparée** avant de devenir un template, et que le build **échoue** si la préparation est incomplète. Et pendant qu'on y est : le compte de construction n'a rien à faire dans une image livrée.

**Objectifs pédagogiques**
- Organiser les provisioners d'un build (contrôles, personnalisation, préparation) et comprendre leur contexte d'exécution (utilisateur, `sudo`, variables, dossier temporaire).
- Lister tout ce qui identifie une instance ou trahit un build, sur Debian et sur RHEL.
- Écrire un script de préparation qui se vérifie lui-même.
- Prouver le résultat par deux clones.

**Prérequis** : M03-E05, M03-E06.
**Durée indicative** : 2 h 30.

**Contexte technique**
- Script : `scripts/preparer-clonage.sh` (partagé par toutes les images, Debian et Rocky), lancé en root par un provisioner `shell` **en dernier**. Nom du compte de construction transmis par une variable d'environnement `COMPTE_BUILD`.
- À traiter au minimum : compte de construction et ses droits ; configuration réseau propre au build ; état de cloud-init ; `machine-id` ; clés d'hôte SSH ; graine aléatoire de systemd ; baux DHCP ; journaux, historiques, caches de paquets, fichiers temporaires ; traces des installeurs.
- Clones de contrôle : **2030** `m03-prep-a` et **2031** `m03-prep-b`, clones liés de 9001, `vsandbox` en DHCP, `ciuser admin`, ta clé.

**Travail demandé**

1. Fais la liste de ce qui doit disparaître, avec pour chaque élément : où il se trouve sur Debian et sur Rocky, ce qui le recrée sur le clone (systemd, cloud-init, sshd, rien), et le risque s'il reste. Lis l'aide de `cloud-init clean` : quelles options couvrent une partie de la liste ?
2. Écris `scripts/preparer-clonage.sh`. Il doit fonctionner sur les deux familles, s'arrêter à la première erreur, et finir par une série de **vérifications** qui font échouer le build si quelque chose est resté. Il passe ShellCheck.
3. Remplace, dans `debian13-base/` et `rocky10-base/`, le provisioner de E05/E06 par : un provisioner de contrôles, puis la préparation. Pourquoi doit-elle être le **dernier** provisioner ? Que se passerait-il si un provisioner écrivait ensuite dans `/var/log` ?
4. Le script supprime le compte avec lequel Packer est connecté. Pourquoi est-ce possible ? Que va afficher Packer à l'étape suivante, et est-ce grave ?
5. Reconstruis 9001 et 9002.
6. Clone 9001 en 2030 et 2031, démarre-les, et compare comme en E03 : `machine-id`, empreintes des clés d'hôte, adresses obtenues, comptes, `sudoers.d`. Pourquoi les adresses DHCP étaient-elles identiques en E03 ? (Indice : avec `systemd-networkd`, d'où vient l'identifiant de client DHCP ?)
7. MR, fusion. Lance la vérification, puis détruis 2030 et 2031.

**Critères de réussite**
- [ ] `scripts/preparer-clonage.sh` est sur `main`, exécutable, sans remarque ShellCheck, et c'est le dernier provisioner de `debian13-base` et de `rocky10-base`.
- [ ] Les templates 9001 et 9002 ont été reconstruits après l'ajout du script.
- [ ] Les clones 2030 et 2031 ont des `machine-id` et des clés d'hôte différents, et des adresses différentes.
- [ ] Aucun compte `packer` ni fichier `/etc/sudoers.d/90-build-packer` dans les clones.

**Vérification** : `lab/bin/check 03 07` (VMs 2030 et 2031 démarrées)

<details><summary>Indice 1</summary>

`/etc/machine-id` ne doit pas être supprimé mais remis à l'état « non initialisé » : lis `man machine-id` (section *First Boot Semantics*). Pour les clés d'hôte, qui les régénère au premier démarrage d'un clone Debian ? Et si cloud-init ne trouve aucune source de données ?
</details>

<details><summary>Indice 2</summary>

Avec `set -euo pipefail`, attention aux tubes qui finissent par `grep -q` ou `head` : la commande en amont peut être tuée et faire échouer le tube alors que le motif a été trouvé. Pour vider `/tmp`, souviens-toi que Packer exécute ton script **depuis** `/tmp`.
</details>

**Pour aller plus loin** (facultatif) : compare ta liste avec celle de `virt-sysprep --list-operations` (paquet `guestfs-tools`). Lesquelles de ses opérations n'as-tu pas prévues, et sont-elles pertinentes ici ?

---

### M03-E08 — Variables, fichiers de variables et secrets de build  `LAB` `★★`

> **Ticket PLAT-422** — *De : Karim Benali*
> Les deux images de base se construisent, mais chacune à sa façon : des `export` à la main, un mot de passe généré dans le shell, des valeurs du lab recopiées. Avant d'en écrire d'autres, on met de l'ordre : des variables typées et contrôlées, un fichier de valeurs non secrètes versionné, des secrets qui ne passent que par l'environnement, un mot de passe de build qui n'existe que le temps du build, et **une seule commande** pour construire, la même pour toi et pour la CI. Et je veux pouvoir dire, en lisant un template, quel commit l'a produit.

**Objectifs pédagogiques**
- Maîtriser les variables de Packer : types, valeurs par défaut, `sensitive`, `validation`, variables locales.
- Connaître l'ordre de priorité des sources de valeurs (environnement `PKR_VAR_*`, fichiers `*.pkrvars.hcl`, `-var-file`, `-var`) et ses pièges.
- Supprimer un secret de build plutôt que le protéger.
- Écrire l'outil de construction de l'équipe : garde-fous, traçabilité, journal, verrou.

**Prérequis** : M03-E07.
**Durée indicative** : 2 h 30.

**Contexte technique**
- Variables de connexion : fournies **uniquement** par l'environnement (`PKR_VAR_proxmox_url`, `_username`, `_token`, `_node`), soit depuis `~/.config/workbook/pve-packer.env` sur `adm01`, soit depuis des variables CI protégées et masquées (E15).
- `vars/lab.pkrvars.hcl` : valeurs non secrètes communes à toutes les images (pool, stockages, VNet de build, ports HTTP). Versionné.
- Outil : `outils/construire.sh <image> [options -var…]`, lancé depuis n'importe où ; codes retour communs de la plateforme (0, 1, 2 usage, 3 refus d'un garde-fou, M02).
- Traçabilité : le commit du projet et la version du plugin apparaissent dans les notes du template.

**Travail demandé**

1. **Précédence.** Dans un dossier d'essai, déclare une variable `essai` sans valeur par défaut et affiche-la dans un provisioner `shell-local`. Fournis-la successivement par `PKR_VAR_essai`, par un fichier `essai.auto.pkrvars.hcl`, par `-var-file` et par `-var`, en combinant les sources. Écris l'ordre de priorité observé. Conséquence pour `vars/lab.pkrvars.hcl` : quelles variables ne doivent **jamais** y figurer, et pourquoi le nœud Proxmox (`<NOEUD>`) est-il dans le fichier d'environnement plutôt que dans ce fichier versionné ?
2. **Variables sûres.** Dans `variables.pkr.hcl` des deux images : jeton marqué `sensitive` ; règles de validation sur l'URL (HTTPS, chemin de l'API), l'identifiant du jeton (`utilisateur@domaine!jeton`) et `vm_id` (refus de tout VMID hors de la plage 9001-9099 : pense à `-force`). Vérifie chaque règle par un `packer validate` qui doit échouer.
3. **Mot de passe de build.** Supprime la variable `build_password` : le mot de passe est généré **par Packer** à chaque build, dans une variable locale sensible. Quelle fonction de Packer produit une valeur aléatoire ? Montre que la valeur n'apparaît pas dans la sortie de `packer build`. Où apparaissait-elle encore malgré tout pendant le build (pense au serveur HTTP et à ce que l'installeur conserve), et pourquoi ce n'est plus un problème après E07 ?
4. **L'outil.** Écris `outils/construire.sh` :
   - charge les accès depuis l'environnement s'ils y sont, sinon depuis le fichier d'accès, en **refusant** un fichier qui n'est pas en mode 600 ;
   - refuse de construire un dépôt modifié non commité, sauf option explicite `--brouillon` (et le commit est alors marqué comme tel) ;
   - passe à Packer le commit et la version du plugin (`packer plugins installed`), fait `packer init` et `packer validate` avant `packer build -force` ;
   - garde le journal du build dans `manifests/` (ignoré par git) ;
   - interdit deux builds simultanés de la même image sur la machine ;
   - ne fait jamais apparaître le secret en argument d'un programme.
5. Ajoute le commit et la version du plugin aux notes des deux templates, reconstruis 9001 **avec l'outil**, et lis les notes dans l'interface.
6. Cherche toute trace de secret dans le dépôt (historique compris) avec Gitleaks, et dans le journal du build.
7. MR, fusion, vérification.

**Critères de réussite**
- [ ] Le jeton est `sensitive` ; `vm_id`, l'URL et l'identifiant du jeton sont contrôlés par des règles de validation ; plus aucune variable `build_password`.
- [ ] `vars/lab.pkrvars.hcl` ne contient ni l'URL, ni le jeton, ni le nœud.
- [ ] `outils/construire.sh` refuse un fichier d'accès lisible par d'autres (code 3), une image inconnue (code 2), et passe ShellCheck.
- [ ] Les notes du template 9001 citent le commit qui l'a construit et la version du plugin.
- [ ] Gitleaks ne trouve aucun secret dans l'historique de `plateforme/images`.

**Vérification** : `lab/bin/check 03 08`

<details><summary>Indice 1</summary>

La documentation de Packer (*Input Variables*, section sur la priorité) décrit l'ordre des sources. Un bloc `local "nom" { expression = … sensitive = true }` permet de marquer une valeur locale comme sensible. Pour une valeur aléatoire, cherche dans les fonctions de Packer la famille UUID.
</details>

<details><summary>Indice 2</summary>

Pour exporter toutes les variables d'un fichier vers les programmes lancés ensuite sans les afficher : `set -a`, `.` (source), `set +a`. Pour le verrou : `flock` sur un descripteur ouvert avec `exec`. Pour récupérer le code de sortie de `packer build` à travers un `tee` : `PIPESTATUS`.
</details>

**Pour aller plus loin** (facultatif) : lis la page *Sensitive variables* de Packer : par quel mécanisme la valeur est-elle masquée dans la sortie ? Que se passe-t-il si la valeur sensible est un mot très court qui apparaît aussi ailleurs dans les journaux ?

---

### M03-E09 — Image dorée Debian 13 v1  `LIBRE` `★★`

> **Ticket PLAT-423** — *De : Claire Morel* — *Copie : Sophie Laurent, Karim Benali*
> On y est : la première image dorée de MédiSphère. Elle part de `tpl-debian13-base` et contient ce que toutes nos VMs Debian doivent avoir, sans exception. Sophie a fixé le contenu ci-dessous. Cette v1 n'est pas encore publiée : on la teste d'abord à la main, la publication arrive en E10.

**Objectifs pédagogiques**
- Concevoir le contenu d'une image dorée à partir d'exigences, et le vérifier pendant le build.
- Construire par clonage au-dessus d'une image de base (`proxmox-clone`).
- Rendre une configuration indépendante de l'endroit où le clone sera déployé (VLAN, adresse).
- Faire la part entre ce qui est cuit dans l'image et ce que cloud-init apporte au clonage.

**Prérequis** : M03-E07, M03-E08, M01 (CA provisoire).
**Durée indicative** : 4 h.

**Contexte technique**
- Dossier `debian13-gold/` (`build.pkr.hcl`, `variables.pkr.hcl`) ; scripts dans `scripts/`, fichiers à déposer dans `fichiers/`.
- Source : template 9001, clone **complet**. Résultat : template `deb13-gold-AAAAMMJJ-N` (date du build, N = numéro du build du jour), VMID libre de 9010-9029 (vérifie qu'il est libre), étiquettes `gold` et `debian13`. **Pas** d'étiquette `current`.
- Contenu exigé (ticket SEC de Sophie) :
  - `qemu-guest-agent`, `cloud-init`, `chrony`, `sudo`, `curl`, `ca-certificates`, `unattended-upgrades` ; système à jour au moment du build ;
  - la **CA provisoire MédiSphère** (certificat public de M01) approuvée par le système ;
  - `chrony` synchronisé sur **la passerelle du VLAN où le clone est déployé** (règle du lab, PLAN.md §4.3 bis), sans source Internet : le mécanisme est à ton choix, mais il doit fonctionner pour un clone posé dans n'importe quel VLAN, en DHCP comme en adresse statique ;
  - `unattended-upgrades` actif pour les mises à jour de **sécurité seulement** ;
  - `sshd` de base durci : connexion `root` interdite, authentification par mot de passe interdite, par un fichier de `/etc/ssh/sshd_config.d/`, effectif quoi que cloud-init écrive ensuite ;
  - journal `systemd` persistant ;
  - console série, matériel identique à celui de 9000.
- Au clonage, cloud-init apporte : l'utilisateur `admin` et sa clé, le nom, l'adresse ; le résolveur 10.10.20.10 et le domaine `par1.medisphere.internal` doivent être les valeurs **par défaut** du template (un clone qui ne précise rien doit les avoir). Aucune mise à niveau complète des paquets au premier démarrage d'un clone.
- VM de recette : **2034** `m03-gold-test`, clone lié de ton image, VNet `vinfra`, adresse **statique** 10.10.20.49/24 (passerelle 10.10.20.1), `ciuser admin`, ta clé, **sans** préciser de résolveur.
  > ⚠️ 10.10.20.49 est la dernière adresse de la plage des services statiques du VLAN INFRA (PLAN.md §4.2) : vérifie qu'elle est libre (`ping`, `dig -x`) avant de l'utiliser, et ne l'inscris pas au DNS : la VM est détruite après la recette.

**Contraintes**
- Tout passe par le code du projet et par `outils/construire.sh` ; rien n'est fait à la main sur le template.
- Chaque exigence est **vérifiée pendant le build** (le build échoue si elle n'est pas satisfaite), pas seulement appliquée.
- Aucun secret, aucune clé privée, aucun compte personnel dans l'image ; le compte de construction n'y survit pas.
- Les notes du template décrivent son contenu et sa provenance (source, commit, outils).

**Critères de réussite**
- [ ] Un template `deb13-gold-AAAAMMJJ-N` existe dans 9010-9029, étiqueté `gold` et `debian13`, sans `current`, avec console série, lecteur cloud-init, résolveur 10.10.20.10 et domaine par défaut, sans mise à niveau au premier démarrage.
- [ ] Dans la VM 2034 : cloud-init a terminé, `admin` existe, `packer` n'existe pas, `chrony` a pour source 10.10.20.1, la CA provisoire est approuvée, `sshd -T` montre `permitrootlogin no` et `passwordauthentication no`, le journal est persistant, `unattended-upgrades` ne suit que la sécurité, et le résolveur est 10.10.20.10 sans l'avoir précisé au clonage.
- [ ] `debian13-gold/` et ses scripts sont sur `main`, sans remarque ShellCheck.

**Vérification** : `lab/bin/check 03 09` (VM 2034 démarrée)

<details><summary>Indice 1</summary>

Packer retire du template les paramètres cloud-init qu'il a utilisés pendant le build (regarde ce qu'il y avait dans `qm config` de 9090 en E03). Les réglages par défaut d'un template peuvent être posés **après** sa conversion : un post-processor `shell-local` peut appeler un petit script qui parle à l'API.
</details>

<details><summary>Indice 2</summary>

Pour les mises à jour automatiques, lis `/etc/apt/apt.conf.d/50unattended-upgrades` : que contient déjà la liste par défaut ? Une liste d'`apt.conf` redéfinie dans un autre fichier s'**ajoute** à la première : cherche dans `man apt.conf` comment la vider. Pour `sshd`, lis dans `man sshd_config` quelle occurrence d'un mot-clé l'emporte, et regarde dans quel fichier cloud-init écrit ses réglages SSH.
</details>

<details><summary>Indice 3</summary>

Pour la source de temps, l'image ne connaît pas le VLAN de ses clones, mais un clone connaît sa route par défaut au démarrage. Debian lit les sources de `chrony` dans `/etc/chrony/sources.d/` (directive `sourcedir`) et `chronyc reload sources` les relit sans redémarrage.
</details>

**Pour aller plus loin** (facultatif) : mesure le temps entre `qm start` et « SSH disponible » pour un clone de 9000 (avec son *vendor-data*) et pour un clone de ton image dorée. D'où vient la différence ?

---

### M03-E10 — Versionner et publier les images  `LAB` `★★`

> **Ticket PLAT-424** — *De : Karim Benali*
> Ansible et OpenTofu vont consommer nos images. Ils ne doivent jamais deviner laquelle prendre. Règles : chaque image dorée a une version `AAAAMMJJ-N` et un VMID calculés par un outil, pas choisis à la main ; un manifeste lisible (provenance, outils, empreinte de la liste des paquets) ; et une étiquette `current` posée **par un outil de publication**, **uniquement** si un test automatique a réussi, et retirée de la version précédente. Une seule `current` par famille, toujours.

**Objectifs pédagogiques**
- Concevoir un schéma de version d'image et un calcul d'identifiant sûr.
- Produire un manifeste de build (post-processor `manifest`, rapatriement de fichiers) et l'attacher au template.
- Écrire une publication atomique du point de vue des consommateurs, conditionnée par un test.
- Manipuler les étiquettes et les notes par l'API.

**Prérequis** : M03-E09.
**Durée indicative** : 3 h.

**Contexte technique**
- Outils du projet (Bash, `curl` + `jq`, accès de `pve-packer.env`, TLS vérifié) :
  - `outils/version-image.sh debian13|rocky10` → affiche `<VMID> <VERSION>` : premier VMID libre de la plage **sur tout le cluster** (une VM hors du pool est invisible pour le jeton : rappelle-toi M00-E18), version `AAAAMMJJ-N` ;
  - `outils/construire.sh` : pour une image dorée, appelle `version-image.sh` si le VMID n'est pas imposé ;
  - `outils/publier-image.sh [--dry-run] <VMID>` : contrôle qu'il s'agit d'un template doré, lance `tests/tester-image.sh <VMID>`, complète les notes, déplace `current` ; codes 0, 1, 2, 3 (refus).
- Test : `tests/tester-image.sh <VMID-template>` (interface fixée : clone dans le premier VMID libre de 2030-2033, étiquette `env-m03`, code 0 si conforme, 1 sinon, VM toujours détruite). Une **version minimale** est fournie : `ressources/M03-E10/tester-image-minimal.sh` (démarrage, agent, cloud-init, SSH, `sudo`) ; elle sera complétée en E14.
- Manifeste : liste des paquets installés (`nom<TAB>version`, triée) produite dans la VM de build par `scripts/manifeste-paquets.sh`, rapatriée dans `manifests/<nom>-paquets.txt` ; post-processor `manifest` dans `manifests/<nom>.json`.

**Travail demandé**

1. Lis le test minimal fourni : que vérifie-t-il, que ne vérifie-t-il pas ? Pourquoi passe-t-il l'option `ControlPath=none` à SSH sur `adm01` ? Pourquoi encode-t-il la clé SSH avant de l'envoyer à l'API ? Copie-le dans `tests/tester-image.sh`.
2. Écris `outils/version-image.sh`. Teste-le contre l'état réel : que renvoie-t-il aujourd'hui ? Que doit-il faire quand la plage est pleine ?
3. Complète `debian13-gold/build.pkr.hcl` : production et rapatriement de la liste des paquets (avant la préparation au clonage : pourquoi ?), post-processor `manifest` avec des données personnalisées (version, commit, outils). Étends `construire.sh` pour les images dorées.
4. Écris `outils/publier-image.sh`. Questions à trancher et à justifier dans le code : dans quel ordre retirer et poser `current` (pense à un consommateur qui lit les étiquettes au même instant) ? Que faire si l'image est déjà `current` ? Comment garantir à la fin qu'il y a exactement une `current` ?
5. Construis une nouvelle version de l'image dorée avec l'outil, essaie `--dry-run`, puis publie-la. Rends le test volontairement impossible (par exemple en le lançant avec une clé SSH inexistante) et vérifie que la publication est **refusée**.
6. Lis les notes et les étiquettes du template publié dans l'interface. Que reste-t-il de ta v1 de E09 ?
7. MR, fusion, vérification.

**Critères de réussite**
- [ ] `outils/version-image.sh`, `outils/publier-image.sh` et `tests/tester-image.sh` sont sur `main`, exécutables, sans remarque ShellCheck, avec un code 2 sur un usage incorrect.
- [ ] Exactement un template `gold` + `debian13` porte `current` ; ses notes indiquent la date de publication, le succès du test et l'empreinte de la liste des paquets.
- [ ] `debian13-gold/build.pkr.hcl` contient le post-processor `manifest` et le rapatriement de la liste des paquets.
- [ ] Aucune VM de test ne reste dans 2030-2033.

**Vérification** : `lab/bin/check 03 10`

<details><summary>Indice 1</summary>

`GET /cluster/nextid?vmid=N` répond l'identifiant s'il est libre et une erreur s'il est pris, quels que soient tes droits sur la VM qui l'occupe. Les étiquettes d'une VM se lisent dans `tags` de sa configuration (séparées par `;`) et dans `/cluster/resources` ; elles s'écrivent par `PUT …/config` avec le paramètre `tags`.
</details>

<details><summary>Indice 2</summary>

Un provisioner `file` accepte `direction = "download"`. Le dossier de destination sur la machine de build doit exister : qui le crée ? Pour le post-processor `manifest`, `custom_data` attend des chaînes.
</details>

**Pour aller plus loin** (facultatif) : signe le manifeste JSON (clé SSH de signature de M01-E27, `ssh-keygen -Y sign`) et vérifie la signature avant publication. Ce sera la base de la chaîne de confiance des images de conteneurs (module 13).

---

### M03-E11 — cloud-init avancé : vendor-data, multi-part, réseau v2  `LAB` `★★`

> **Ticket DEV-425** — *De : Julien Petit*
> Mon équipe va créer ses VMs de développement à partir de l'image dorée. On voudrait, sans modifier l'image : un message d'accueil qui rappelle qu'il n'y a pas de données réelles sur la machine, `git` installé, une trace de chaque démarrage, et une inscription unique de la VM dans notre inventaire (un script). Et une adresse fixe dans le VLAN SANDBOX pour notre VM d'intégration, avec deux DNS si possible. Karim dit que c'est faisable avec cloud-init seul ; montre-nous.

**Objectifs pédagogiques**
- Composer un *vendor-data* en plusieurs parties (MIME *multi-part*) : configuration, script, gabarit Jinja.
- Comprendre comment cloud-init fusionne *user-data* et *vendor-data*, et qui l'emporte.
- Écrire une configuration réseau v2 et la substituer à celle que génère Proxmox, en connaissant les conséquences.
- Valider chaque partie hors de la VM.

**Prérequis** : M03-E04, M03-E10.
**Durée indicative** : 2 h 30.

**Contexte technique**
- VM : **2032** `m03-ci-avance`, clone lié de l'image dorée Debian `current`, pool `lab`, étiquette `env-m03`, VNet `vsandbox`, adresse MAC **imposée** `BC:24:11:03:20:32` (préfixe Proxmox), `ciuser admin`, ta clé.
- Brouillons dans `~/m03/e11/` ; snippets déposés sur `pve01` dans `/mnt/hdd-bulk/snippets/` : `m03-e11-vendor.mime` et `m03-e11-network.yaml`.
- *Vendor-data* en deux parties :
  - partie 1, configuration en gabarit **Jinja** : `/etc/motd` qui affiche l'identifiant d'instance et la distribution (données d'instance de cloud-init), paquet `git`, une ligne datée ajoutée à `/var/log/mediagenda-demarrages.log` à **chaque** démarrage ;
  - partie 2, script shell exécuté **une fois par instance** : écrit `/var/lib/mediagenda/inscription` (date, identifiant d'instance, adresses).
- Réseau v2 : interface reconnue par son adresse MAC et nommée `eth0`, adresse 10.10.99.251/24, route par défaut via 10.10.99.1, résolveur 10.10.20.10, domaine `par1.medisphere.internal`.
- Outils sur `adm01` (cloud-init y est installé : c'est un clone *genericcloud*) : `cloud-init devel make-mime`, `cloud-init devel render`, `cloud-init schema`.

**Travail demandé**

1. Écris les deux parties et la configuration réseau. Valide chacune **avant** de toucher à la VM : schéma réseau (`cloud-init schema -t network-config`), syntaxe du script, rendu de la partie Jinja avec les données d'instance d'`adm01` puis schéma du résultat. Assemble le *vendor-data* avec `make-mime`. Garde ces étapes dans un petit script `~/m03/e11/fabriquer-vendor.sh`.
2. Avant de créer la VM, réponds dans ton journal : si le *user-data* généré par Proxmox et ton *vendor-data* définissent tous deux `packages` ou `runcmd`, que se passe-t-il ? Et si tu passais ta configuration par `cicustom user=` au lieu de `vendor=` ?
3. Crée la VM 2032, pose `cicustom` pour le *vendor-data* **et** le réseau, regarde ce que Proxmox va fournir (`qm cloudinit dump 2032 network` puis `meta`). Que deviennent `ipconfig0`, `nameserver`, `searchdomain` ? Et l'identifiant d'instance ?
4. Démarre, vérifie : adresse, nom d'interface, résolveur, `motd`, `git`, inscription, journal des démarrages. Redémarre : qu'est-ce qui change dans les fichiers de Julien ?
5. Change seulement la configuration réseau (ajoute un second serveur DNS, par exemple 10.10.20.16, le futur `dns02`), redémarre : l'inscription est-elle refaite ? Pourquoi ? Est-ce souhaitable pour Julien ? Remets la configuration du contexte.
6. Réponds à Julien (`~/m03/e11/reponse-dev-425.md`) : ce qui est faisable sans modifier l'image, les limites (le snippet réseau contient une adresse : un snippet par VM), les dépendances créées (le stockage `hdd-bulk` doit être en ligne au démarrage de chaque VM), et ce qui relèverait plutôt d'Ansible (module 04).
7. Lance la vérification, puis détruis 2032 et supprime les snippets de l'exercice.

**Critères de réussite**
- [ ] La VM 2032 utilise les snippets `m03-e11-vendor.mime` (multi-part) et `m03-e11-network.yaml`, et sa carte a l'adresse MAC imposée.
- [ ] Dans la VM : `eth0` porte 10.10.99.251/24, le résolveur est 10.10.20.10, `/etc/motd` mentionne MédiAgenda et l'identifiant d'instance, `git` est installé, `/var/lib/mediagenda/inscription` existe, le journal des démarrages a au moins deux lignes.
- [ ] cloud-init a terminé **sans erreur ni avertissement** (`cloud-init status` renvoie 0).
- [ ] `~/m03/e11/fabriquer-vendor.sh` valide les trois éléments avant d'assembler.

**Vérification** : `lab/bin/check 03 11` (VM 2032 démarrée)

<details><summary>Indice 1</summary>

Une partie Jinja commence par la ligne `## template: jinja`, puis le type réel du contenu (`#cloud-config`). `make-mime` attend des couples `fichier:type` ; `--list-types` les affiche. Les données disponibles dans un gabarit : `cloud-init query --all` (clés `v1.*`).
</details>

<details><summary>Indice 2</summary>

Relis dans le corrigé de E04 comment Proxmox calcule l'identifiant d'instance : le contenu de la configuration réseau en fait partie, qu'elle soit générée ou fournie par `cicustom`. En v2, `gateway4` est déprécié : utilise `routes`.
</details>

**Pour aller plus loin** (facultatif) : ajoute à la partie configuration une clé `merge_how` qui concatène les listes `runcmd` du *user-data* et du *vendor-data*, et vérifie le résultat dans `/var/lib/cloud/instance/scripts/runcmd`.

---

### M03-E12 — Revue du template Packer d'un stagiaire  `REV` `★★`

> **Ticket PLAT-426** — *De : Karim Benali*
> Lucas a écrit sa propre image Debian « plus simple que la nôtre » (dossier `ressources/M03-E12/debian13-lucas/`). Il dit qu'elle marche du premier coup chez lui. Fais-lui une vraie revue avant qu'il ouvre sa MR : chaque défaut avec sa gravité, l'impact concret et la correction, puis ta recommandation (corriger son fichier ou repartir des nôtres). Exigeant mais pédagogue.

**Objectifs pédagogiques**
- Relire un fichier Packer et un *preseed* sous les angles sécurité, fonctionnement, exploitation.
- Relier chaque défaut à une conséquence concrète dans le lab de MédiSphère.
- Rédiger une revue utile et priorisée.

**Prérequis** : M03-E05 à M03-E10.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Fichiers : `build.pkr.hcl`, `http/preseed.cfg` et le `LISEZMOI.md` de Lucas, dans `ressources/M03-E12/debian13-lucas/`. Dans ces fichiers, `192.168.1.20` est l'adresse de `pve01` et `192.168.1.0/24` le LAN maison.
- Ils contiennent entre 10 et 14 défauts de gravités variées.

> ⚠️ **Attention** : ne lance **pas** ce build. Pour l'examiner, `packer validate` suffit (il ne contacte pas Proxmox), dans une copie du dossier, avec le plugin déjà installé.

**Travail demandé**
1. Lis les trois fichiers une première fois sans rien noter. Puis suis le build pas à pas, comme si tu le lançais : qui se connecte à quoi, avec quels droits, sur quel réseau, ce qui est téléchargé et vérifié, ce qui finit dans le template, ce que voit un clone.
2. Lance `packer validate` sur une copie : que disent les avertissements ?
3. Rédige la revue sous forme de tableau : n°, fichier et ligne(s), défaut, catégorie (sécurité, fonctionnement, exploitation), gravité (critique, élevée, moyenne, faible), impact concret, correction.
4. Classe les défauts par ordre de traitement et donne ta recommandation à Lucas.
5. Ajoute trois conseils sur sa méthode (« ça marche chez moi »).

**Critères de réussite** (auto-évaluation avec le corrigé)
- [ ] Au moins 10 défauts identifiés, dont tous les défauts critiques et élevés du corrigé.
- [ ] Chaque défaut a un impact concret et une correction précise.
- [ ] La recommandation est argumentée.
- [ ] Le ton est utile à Lucas.

<details><summary>Indice 1</summary>

Trois familles à chercher : ce qui donne trop de droits (identité, TLS, secrets), ce qui expose (réseau, serveur HTTP), ce qui rend l'image inutilisable ou dangereuse une fois clonée (cloud-init, identité, mots de passe permanents).
</details>

<details><summary>Indice 2</summary>

Demande-toi ce que sert exactement `http_directory = "."`, à qui, sur quelle interface. Et ce que fait Packer quand aucun `vm_id` ni `pool` n'est indiqué.
</details>
