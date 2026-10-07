# Module 03 — Palier 4 : Expert

Le catalogue est en production : la forge construit chaque semaine, les tests filtrent, la rotation fait le ménage. Nadia Roussel prévient : « Une image cassée ne casse rien tout de suite. Elle casse la prochaine VM qu'on crée, souvent la nuit, souvent pour quelqu'un d'autre. » Ce palier est celui des incidents propres aux images : un build qui ne voit jamais sa VM, des clones qui partagent une identité, cloud-init qui ignore sa configuration, une VM Rocky qui ne démarre pas. Puis une descente sous le capot du premier démarrage, et des questions d'entretien. La méthode reste celle des modules précédents : observer avant d'agir, formuler une hypothèse, la tester par la mesure la moins invasive, corriger à la racine, prévenir la récidive. Avec une règle de plus, propre aux images : **corriger une VM ne corrige pas l'image, et corriger l'image ne corrige pas les VMs déjà créées.**

> **Rappels** : tout se fait depuis `adm01`. Projet : `~/src/images` ; documentation : `~/medisphere`. VMs d'exercice : 2030-2039 (`env-m03`), essais : 9090-9099. Règles du module : [`00-introduction.md`](00-introduction.md).

## Règles du jeu des pannes (M03-E19 à M03-E22)

- Les pannes s'injectent **depuis `adm01`**, à la racine de ta copie du workbook :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ lab/bin/break 03 19
  ```
  Le script tire une variante au hasard et n'affiche que le **symptôme**, comme un ticket. Chaque panne a 4 variantes : refais l'exercice jusqu'à les avoir toutes rencontrées (`--variante N` force une variante, sans dire laquelle est laquelle).
- **Avant d'injecter**, lance le contrôle de l'exercice (`lab/bin/check 03 19`) pour E19 : il doit être vert. Pour E20, E21 et E22, la panne **fabrique elle-même** les VMs de l'incident (2036 à 2039, et le template d'essai 9095 pour E20) à partir de tes images publiées : il faut seulement que ces VMID soient libres et qu'une version `current` existe (Debian pour E20 et E21 ; Rocky ou, à défaut, le template 9002 pour E22). Leur contrôle échoue tant que la panne n'est pas injectée et réparée : c'est normal. L'injection de E20 à E22 prend 3 à 8 minutes (clonages, démarrages).
- **Ne lis pas** les scripts de `corrige/pannes/`, ni `/var/lib/workbook/` sur les hôtes, ni `~/.local/state/workbook/` sur `adm01` : ils contiennent la cause.
- Une seule panne active à la fois par exercice. **`--annuler` sert à deux choses** :
  - **clore** une panne que tu as réparée (le marqueur de panne active reste sinon, et le contrôle du mini-projet le verra). L'annulation ne restaure que ce qui est **encore** dans l'état cassé : elle n'écrase jamais ta réparation ;
  - abandonner (filet de sécurité, pas un correctif : compte l'exercice comme non réussi).
  Pour E20, E21 et E22, l'annulation **détruit** les VMs et le template d'essai créés par la panne (2036-2039, 9095) : garde-les tant que ton contrôle n'est pas vert.
- Les pannes n'agissent que sur des ressources du lab : `gw01` (règles nftables, sauvegardées), `dns01` (configuration de dnsmasq, sauvegardée), ta copie de travail `~/src/images` (fichier sauvegardé, jamais de commit) et des VMs ou templates **qu'elles créent elles-mêmes** dans 2036-2039 et 9095. Elles ne modifient **jamais** tes templates 9000-9049 (elles ne font que les cloner).
- **Tiens un journal de diagnostic** pour chaque panne dans `docs/socle/journal/` de `~/medisphere` (publié par MR) : heure, hypothèse, commande, résultat observé, conclusion. Cite le numéro de l'incident (`INC-30xx`) : le contrôle le cherche.
- Le **temps cible** est indicatif. Le dépasser n'est pas un échec ; corriger sans comprendre en est un.

> ⚠️ **Accès de secours** : une VM qui ne démarre pas ou n'a pas de réseau n'est accessible que par sa **console** (interface web, onglet *Console* ; `qm terminal <VMID>` en root sur `pve01` si la VM a un port série) ou par l'**agent QEMU** (`qm guest exec <VMID> -- …`) s'il tourne. Repère ces deux chemins **avant** d'en avoir besoin, et note ce que chacun suppose (système démarré, agent installé, port série configuré).

---

### M03-E19 — Panne : le build attend SSH indéfiniment  `BF` `★★★`

> **Ticket INC-3001** — *De : Karim Benali*
> *(le détail s'affiche à l'injection)* Le build de l'image de base Debian reste bloqué sur « Waiting for SSH to become available... » jusqu'au délai maximal. Rien n'a changé dans le dépôt à ma connaissance.

**Objectifs pédagogiques**
- Décomposer un build `proxmox-iso` en étapes observables (démarrage de l'ISO, frappe de la ligne de démarrage, téléchargement du *preseed*, installation, redémarrage, découverte de l'adresse, connexion SSH) et savoir où regarder pour chacune.
- Comprendre comment Packer trouve l'adresse de la VM (agent QEMU) et ce que signifie vraiment « Waiting for SSH ».
- Lire en parallèle la console de la VM, le journal détaillé de Packer, les journaux de `dns01` et les compteurs de `gw01`.

**Prérequis** : M03-E05, M03-E08 ; M00-E13, M00-E14 ; `lab/bin/check 03 19` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Injection** : `lab/bin/break 03 19` (4 variantes).

**Contexte technique** : reproduis le build **dans la zone d'essai**, jamais sur 9001 :
```
admin@adm01:~/src/images$ PACKER_LOG=1 PACKER_LOG_PATH=/tmp/e19.log outils/construire.sh --brouillon debian13-base -var vm_id=9090
```
(`--brouillon` : ta copie de travail est peut-être modifiée, c'est à toi de le découvrir.) Garde la console de la VM 9090 ouverte pendant l'installation.

> ⚠️ **Attention** : `-var vm_id=9090` est indispensable. Sans lui, `construire.sh` vise 9001 et `-force` supprime ton image de base avant de construire. Vérifie la ligne de commande avant de valider. Si tu interromps Packer (Ctrl-C), vérifie qu'il a bien détruit la VM 9090 (`qm list` en root sur `pve01`).

**Travail demandé**
1. Reproduis le symptôme en zone d'essai. Pendant l'attente, regarde la **console** de la VM : à quelle étape l'installation en est-elle ? Note ce que tu vois.
2. Dans le journal détaillé de Packer, trouve la ligne qui se répète pendant l'attente et ce qu'elle dit vraiment. Packer attend-il SSH, ou autre chose avant SSH ?
3. Selon l'étape où tout s'arrête, vérifie le maillon correspondant : bail DHCP (journal de dnsmasq sur `dns01`), accès au serveur HTTP de Packer, résolution DNS depuis le VLAN 99, présence de l'agent dans le système installé. Utilise des **mesures** (journaux, compteurs nftables, `tcpdump`), pas la relecture seule.
4. Corrige à la racine. Si la cause est un fichier modifié (sur un hôte ou dans ta copie de travail), compare-le à sa référence (`nft -c`, `git diff`, `dnsmasq --test`) et explique comment le changement est arrivé là.
5. Relance le build d'essai jusqu'au template, puis supprime 9090. Clos la panne (`--annuler`).
6. Propose une mesure qui aurait fait échouer le build **vite et clairement** au lieu d'attendre le délai maximal.

**Critères de réussite**
- [ ] Un build d'essai de `debian13-base` aboutit ; 9090 est supprimé, 9001 intact.
- [ ] `gw01`, `dns01` et ta copie de travail sont cohérents avec leur configuration de référence.
- [ ] Ton journal (INC-3001) identifie l'étape bloquée, la mesure qui l'a prouvé et la cause racine.

**Vérification** : `lab/bin/check 03 19`

<details><summary>Indice 1</summary>

Avec `proxmox-iso`, Packer ne connaît pas l'adresse de la VM : il la demande à l'agent QEMU. Tant que l'agent ne répond pas (installation pas terminée, ou agent absent), Packer « attend SSH ». Une installation qui reste bloquée sur un écran de l'installeur et un système installé sans agent produisent le **même** message.
</details>

<details><summary>Indice 2</summary>

Sur `dns01` : `journalctl -u dnsmasq` pendant le démarrage de la VM (`DHCPDISCOVER`… et la suite ?). Sur `gw01` : `sudo nft list chain inet filter forward` avec les compteurs, avant et après une tentative ; `sudo tcpdump -ni ens19.99 'port 53 or portrange 8100-8199'`. Dans ta copie de travail : `git status`, `git diff`.
</details>

<details><summary>Indice 3</summary>

Si la console montre une invite de connexion (`login:`), l'installation est **terminée** : le problème est entre le système installé et Packer. Depuis la console, connecte-toi n'est pas possible (aucun mot de passe connu)… mais `qm guest cmd 9090 ping` en root sur `pve01` répond-il ?
</details>

**Pour aller plus loin** : ajoute au build une limite de temps plus courte pour la seule étape d'installation (et pas pour les provisioners), et documente-la dans RB-038 « Diagnostiquer un build d'image » (ce runbook est un livrable du mini-projet).

---

### M03-E20 — Panne : les clones se marchent dessus  `BF` `★★`

> **Ticket INC-3004** — *De : Julien Petit*
> *(le détail s'affiche à l'injection)* Deux VMs de test clonées depuis une image préparée par Lucas se gênent mutuellement : SSH arrive tantôt sur l'une, tantôt sur l'autre, ou se plaint de la clé.

**Objectifs pédagogiques**
- Inventorier ce qui fait l'**identité** d'une VM (adresse MAC, `machine-id`, identifiant DHCP, clés d'hôte, nom) et savoir lequel est en cause à partir des symptômes.
- Réparer l'identité de VMs existantes sans les reconstruire, puis corriger la fabrication de l'image.
- Vérifier qu'un test d'image aurait détecté le défaut.

**Prérequis** : M03-E07, M03-E14.
**Durée indicative** : 40 min (temps cible).

**Injection** : `lab/bin/break 03 20` (4 variantes). La panne crée le template 9095 (« image de Lucas ») et les VMs 2038 `mediagenda-test1` et 2039 `mediagenda-test2`, démarrées sur `vsandbox` avec ta clé.

**Travail demandé**
1. Reproduis les symptômes depuis `adm01` (`ssh admin@<IP>`, `ping`, `getent hosts`, `ssh-keygen -F`…). Tiens compte du multiplexage SSH de `adm01` dans tes essais (M00-E15).
2. Compare les deux VMs **côté Proxmox** (configuration, adresses MAC) puis **côté système**, par l'agent QEMU si SSH est trompeur : `machine-id`, empreintes des clés d'hôte, nom d'hôte, adresse et bail DHCP (et le journal de dnsmasq sur `dns01`).
3. Identifie ce qui est partagé, et de quelle étape de fabrication cela vient (image ou création des VMs ?). Lis le template 9095 sans le démarrer : notes, configuration.
4. Répare les **deux VMs en place**, sans les recréer : chacune doit retrouver une identité propre, durablement (au redémarrage suivant aussi).
5. Corrige la **fabrication** : explique à Lucas ce qui manquait (avec la référence de ta préparation, E07), et vérifie que `tests/tester-image.sh 9095` échoue sur son image (si le défaut est dans l'image) et pour quelle raison.
6. Contrôle, puis clos la panne : `--annuler` détruit 2038, 2039 et 9095.

**Critères de réussite**
- [ ] 2038 et 2039 ont des `machine-id`, clés d'hôte, noms, adresses MAC et adresses IPv4 différents, et cloud-init y a terminé sans erreur.
- [ ] Ton journal (INC-3004) nomme l'identité partagée, sa source (image ou création) et la correction de la fabrication.
- [ ] `tests/tester-image.sh` contrôle cette propriété.

**Vérification** : `lab/bin/check 03 20`

<details><summary>Indice 1</summary>

Deux machines, deux MAC différentes, une seule adresse IP : qui choisit l'adresse ? Le serveur DHCP, à partir de l'identifiant que le **client** lui présente. Sur Debian 13, `networkctl status` et le journal de dnsmasq (`log-dhcp`) montrent cet identifiant.
</details>

<details><summary>Indice 2</summary>

Pour régénérer une identité sur une VM existante : `machine-id` (`systemd-machine-id-setup`, après l'avoir vidé), clés d'hôte (`ssh-keygen -A` après suppression, puis redémarrage de sshd), nom (`hostnamectl`, et ce qui l'empêche peut-être d'être remis par cloud-init). Chaque changement a des effets de bord : bail DHCP, `known_hosts` de `adm01`, journaux.
</details>

**Pour aller plus loin** : mesure combien de temps une VM peut tourner avec une identité dupliquée avant qu'un outil de la plateforme ne s'en rende compte (supervision, sauvegarde PBS, inventaire `medictl`), et propose un contrôle qui le détecterait dans le parc existant.

---

### M03-E21 — Panne : cloud-init ignore la configuration  `BF` `★★`

> **Ticket INC-3007** — *De : Julien Petit*
> *(le détail s'affiche à l'injection)* J'ai changé l'adresse et ajouté ma clé dans l'onglet Cloud-Init de ma VM, puis redémarré : rien n'est appliqué.

**Objectifs pédagogiques**
- Suivre le chemin d'une configuration cloud-init de Proxmox jusqu'à la VM : lecteur `cidata`, détection de la source de données (`ds-identify`, générateur systemd), identifiant d'instance, fréquences des modules.
- Utiliser les outils de diagnostic de cloud-init 25.1 : `cloud-init status --long`, `cloud-init query`, `/run/cloud-init/ds-identify.log`, `/run/cloud-init/cloud-init-generator.log`, `/var/log/cloud-init.log`, `cloud-init schema --system`.
- Distinguer « cloud-init ne tourne pas », « cloud-init ne trouve pas sa source » et « cloud-init croit que rien n'a changé ».

**Prérequis** : M03-E04, M03-E11.
**Durée indicative** : 40 min (temps cible).

**Injection** : `lab/bin/break 03 21` (4 variantes). La panne crée la VM 2037 `agenda-dev01` (DHCP, ta clé), puis applique les changements de Julien.

**Travail demandé**
1. Constate l'état : la VM a-t-elle sa nouvelle adresse (10.10.99.37) ? La clé de Julien (commentaire `julien.petit@medisphere`) est-elle installée ? Entre dans la VM par ta clé (adresse DHCP) ou par l'agent QEMU.
2. Vérifie côté Proxmox ce que la VM **devrait** recevoir : `qm cloudinit dump 2037 user`, `… network`, `… meta`, et le matériel de la VM.
3. Dans la VM, établis si cloud-init a tourné à ce démarrage, avec quelle source de données, et s'il a considéré l'instance comme nouvelle. Relève les lignes de journal qui le prouvent.
4. Trouve la cause racine et corrige-la **durablement** (le prochain changement de Julien doit fonctionner sans toi). Fais appliquer la configuration demandée.
5. Explique à Julien, en trois phrases, ce que Proxmox change quand il modifie l'onglet Cloud-Init, et ce que cloud-init en fait.
6. Contrôle, puis clos la panne (`--annuler` détruit 2037).

**Critères de réussite**
- [ ] 2037 a l'adresse 10.10.99.37/24 ; la clé de Julien et celle de `adm01` sont installées pour `admin`.
- [ ] cloud-init y est actif, avec la source NoCloud, statut `done` sans erreur ; aucune configuration qui fige ou désactive cloud-init ne subsiste.
- [ ] Ton journal (INC-3007) contient les lignes de journal qui prouvent la cause.

**Vérification** : `lab/bin/check 03 21`

<details><summary>Indice 1</summary>

`cloud-init status --long` donne `status`, `boot_status_code` et `detail`. `disabled-by-generator`, `disabled-by-marker-file` et `enabled-by-generator` ne mènent pas au même endroit.
</details>

<details><summary>Indice 2</summary>

Proxmox calcule l'identifiant d'instance (`instance-id` du *meta-data*) à partir du contenu de la configuration : `qm cloudinit dump 2037 meta` avant et après un changement. Dans la VM, compare-le à `cloud-init query instance_id` et à `/var/lib/cloud/data/instance-id`. Si cloud-init a tourné mais n'a pas vu une nouvelle instance, cherche « restored from cache » dans `/var/log/cloud-init.log`.
</details>

<details><summary>Indice 3</summary>

`/run/cloud-init/ds-identify.log` dit quelles sources ont été cherchées, **d'après quel fichier de configuration**, et ce qui a été trouvé. `blkid -t LABEL=cidata` dit si le lecteur est là.
</details>

**Pour aller plus loin** : ajoute à `tests/tester-image.sh` un contrôle qui modifie la configuration cloud-init du clone de test (nouvelle clé), le redémarre, et vérifie que la modification est appliquée.

---

### M03-E22 — Panne : la VM Rocky ne démarre pas  `BF` `★★`

> **Ticket INC-3010** — *De : Julien Petit*
> *(le détail s'affiche à l'injection)* La VM Rocky préparée pour l'éditeur est « running » dans Proxmox mais ne répond à rien. La console affiche des messages incompréhensibles.

**Objectifs pédagogiques**
- Diagnostiquer un échec de démarrage par étape : micrologiciel (SeaBIOS/OVMF), chargeur, noyau, initramfs (dracut), espace utilisateur.
- Relier un message de console à un réglage matériel de la VM (type de CPU, contrôleur de disque, micrologiciel, ordre d'amorçage).
- Connaître les exigences propres à Rocky Linux 10 (niveau de microarchitecture x86-64-v3, pilotes du noyau RHEL).

**Prérequis** : M03-E06 ; M00-E11.
**Durée indicative** : 30 min (temps cible).

**Injection** : `lab/bin/break 03 22` (4 variantes). La panne crée la VM 2036 `editeur-rocky01` (clone complet de ton image Rocky `current`, ou du template 9002), vérifie qu'elle démarre, puis applique la recette de création de Julien.

**Travail demandé**
1. Ouvre la console de 2036 (interface web) et **redémarre-la en regardant** (`qm reset 2036`) : note le dernier message lisible et l'étape à laquelle il appartient.
2. Compare la configuration de 2036 à celle du template dont elle est issue (`qm config`, en root sur `pve01`) : quels réglages diffèrent ?
3. Formule une hypothèse qui relie le message de console à l'un de ces réglages, et vérifie-la avec la documentation (Proxmox, notes de version de Rocky Linux 10).
4. Corrige la VM (arrêtée), redémarre-la, vérifie qu'elle arrive à ses services (agent, réseau, SSH).
5. Corrige la **recette** de Julien et ce qui aurait dû l'empêcher : où ce réglage doit-il être imposé pour qu'un clone ne puisse pas se tromper ?
6. Contrôle, puis clos la panne (`--annuler` détruit 2036).

**Critères de réussite**
- [ ] 2036 démarre jusqu'à ses services : l'agent QEMU répond, Rocky Linux 10 est en marche.
- [ ] Son matériel est compatible avec Rocky Linux 10 (CPU, contrôleur, disque dans l'ordre d'amorçage) ; le template Rocky de référence impose le bon CPU.
- [ ] Ton journal (INC-3010) relie le message de console au réglage fautif.

**Vérification** : `lab/bin/check 03 22`

<details><summary>Indice 1</summary>

Quatre étapes, quatre familles de messages : le micrologiciel (« No bootable device », écran OVMF, *UEFI Interactive Shell*), le chargeur (GRUB), le noyau et l'initramfs (`dracut-initqueue timeout`, `Could not boot`, `/dev/mapper/… does not exist`), l'espace utilisateur (`Kernel panic … Attempted to kill init`). Où t'arrêtes-tu ?
</details>

<details><summary>Indice 2</summary>

`qm config 2036` et `qm config <TEMPLATE>` côte à côte : `cpu`, `scsihw`, `bios`, `boot`. Pour le CPU, `/lib64/ld-linux-x86-64.so.2 --help` sur une machine Rocky 10 qui fonctionne liste les niveaux `x86-64-v2/v3/v4` supportés par le processeur.
</details>

**Pour aller plus loin** : passe la VM sur une console série (`serial0` + `console=ttyS0` dans la ligne de commande du noyau) pour lire les messages de démarrage avec `qm terminal`, et intègre ce réglage à l'image Rocky.

---

### M03-E23 — Sous le capot : mesurer un premier démarrage  `LAB` `★★★`

> **Ticket PLAT-480** — *De : Karim Benali*
> Molecule (module 04) va créer et détruire des dizaines de VMs par jour à partir de nos images. Chaque seconde du premier démarrage se paiera des centaines de fois. Je veux savoir **où passe le temps**, de `qm start` jusqu'à « cloud-init terminé », preuves à l'appui, et les trois leviers qui comptent vraiment.

**Objectifs pédagogiques**
- Mesurer un démarrage de bout en bout, vu de l'extérieur (API, agent, SSH) et de l'intérieur (`systemd-analyze`, `cloud-init analyze`, journal monotone).
- Lire `systemd-analyze time`, `blame` et `critical-chain` sans les confondre (temps cumulé ou chemin critique).
- Comprendre les étapes de cloud-init (générateur, `init-local`, `init`, `config`, `final`) et ce que coûte chacune.
- Distinguer premier démarrage et démarrages suivants (fréquences des modules), et l'effet de `ciupgrade`.

**Prérequis** : M03-E04, M03-E14.
**Durée indicative** : 3 h.

**Contexte technique** : VM de mesure **2034 `m03-boot`**, clone de la version Debian `current` (lié, puis complet pour une comparaison), VNet `vsandbox`, utilisateur `admin` et ta clé, étiquette `env-m03`. Toutes les mesures se font **au moins trois fois** ; on note la médiane.

**Travail demandé**
1. **Vu de l'extérieur.** Écris un petit script (brouillon dans `~/m03/e23/`) qui, pour une VM donnée, horodate : appel de démarrage → première réponse de l'agent (`qm guest cmd <VMID> ping` ou API) → premier accès SSH réussi → `cloud-init status --wait` terminé. Mesure un premier démarrage de 2034 avec `ciupgrade=0`.
2. **Vu de l'intérieur.** Sur 2034, relève et interprète :
   ```
   admin@m03-boot:~$ systemd-analyze time
   admin@m03-boot:~$ systemd-analyze blame | head -n 15
   admin@m03-boot:~$ systemd-analyze critical-chain
   admin@m03-boot:~$ cloud-init analyze show
   admin@m03-boot:~$ cloud-init analyze blame | head -n 15
   admin@m03-boot:~$ cloud-init analyze boot
   admin@m03-boot:~$ journalctl -b -o short-monotonic -u 'cloud-init*' --no-pager | head -n 40
   ```
   Explique pourquoi la somme des durées de `blame` dépasse le temps total de démarrage, et ce que montre `critical-chain` que `blame` ne montre pas. Génère aussi `systemd-analyze plot > boot.svg` et ouvre-le sur `adm01`.
3. **Comparaisons** (une variable à la fois) :
   - second démarrage de la même VM (redémarrage) : qu'est-ce qui disparaît, et pourquoi ?
   - nouveau clone avec `ciupgrade=1` (valeur par défaut de Proxmox) ;
   - clone complet au lieu d'un clone lié : temps de clonage, temps de démarrage ;
   - (au choix) 1 vCPU au lieu de 2, ou `ssh_genkeytypes` réduit à ed25519 par un *vendor-data*.
4. **Leviers.** Classe les trois leviers qui comptent le plus pour Molecule, chiffrés, et dis lesquels relèvent de l'image, du clonage ou de la configuration cloud-init. Propose (sans forcément l'appliquer) la modification de l'image ou des paramètres de clonage correspondante.
5. **Rapport.** `docs/socle/mesures/premier-demarrage.md` dans `~/medisphere` (MR) : protocole, tableau des mesures (médianes), extraits commentés, leviers. Puis détruis 2034.

**Critères de réussite**
- [ ] Le rapport contient la chronologie de bout en bout, les analyses `systemd-analyze` et `cloud-init analyze`, les comparaisons demandées et au moins dix valeurs chiffrées.
- [ ] Les trois leviers sont classés et chiffrés, avec leur lieu de mise en œuvre.
- [ ] La VM 2034 a été détruite.

**Vérification** : `lab/bin/check 03 23`

<details><summary>Indice 1</summary>

`systemd-analyze blame` liste le temps passé par **chaque unité** dans son démarrage, même quand elles tournent en parallèle ; `critical-chain` suit la chaîne de dépendances qui a déterminé l'heure d'arrivée d'une cible. Une unité lente hors du chemin critique ne retarde rien.
</details>

<details><summary>Indice 2</summary>

Les modules cloud-init ont une fréquence (`per-instance`, `per-boot`, `per-once`) : `cloud-init analyze show` le laisse voir, la documentation de chaque module le dit. Ce que Proxmox met dans le *user-data* quand `ciupgrade` vaut 1 se lit avec `qm cloudinit dump <VMID> user`.
</details>

**Pour aller plus loin** : mesure l'effet d'un miroir APT local (module 13 ou proxy de cache) sur le premier démarrage avec `ciupgrade=1`.

---

### M03-E24 — Questions expert : images et démarrage  `Q` `★★★`

> **Ticket PLAT-485** — *De : Karim Benali*
> Dernières questions avant la recette du catalogue : celles que je pose en entretien pour un poste d'ingénieur plateforme. Première passe sans documentation, puis vérifie et corrige-toi en couleur.

**Objectifs pédagogiques**
- Consolider la compréhension des mécanismes internes manipulés dans ce module : Packer et Proxmox, cloud-init, identité des machines, démarrage Linux, stockage des templates.
- S'entraîner à argumenter une réponse technique.

**Prérequis** : paliers 1 à 3, M03-E19 à M03-E23.
**Durée indicative** : 2 h 30.

**Questions**

1. Décris les étapes de cloud-init sur un système systemd (générateur, `cloud-init-local`, `cloud-init-network` ou `cloud-init`, `cloud-config`, `cloud-final`) : à quel moment du démarrage chacune s'exécute (avant ou après le réseau), et donne un module typique de chacune.
2. Que fait `ds-identify` et pourquoi existe-t-il, alors que cloud-init sait lui-même chercher une source de données ? Que se passe-t-il, sur x86_64 avec la politique par défaut, quand aucune source n'est trouvée ?
3. QCM — Une VM Proxmox clonée change de clé SSH dans l'onglet Cloud-Init, puis redémarre. Pourquoi cloud-init applique-t-il la nouvelle clé alors que le module des clés est « par instance » ?
   a) Proxmox efface `/var/lib/cloud` dans la VM ; b) l'identifiant d'instance de NoCloud est calculé par Proxmox à partir du contenu de *user-data* et *network-config* : il change, cloud-init voit une nouvelle instance ; c) le module des clés est en réalité « à chaque démarrage » ; d) l'agent QEMU écrit la clé directement.
4. Quelle différence entre un `/etc/machine-id` vide et un fichier contenant `uninitialized` au démarrage suivant ? Pourquoi `cloud-init clean --machine-id` choisit-il la seconde forme ?
5. Une image Debian 13 dont les clés d'hôte SSH ont été supprimées, mais dont cloud-init est désactivé : que se passe-t-il au démarrage d'un clone ? Et sur Rocky Linux 10 ?
6. Explique la différence entre un clone lié sur LVM-thin et sur ZFS : objet créé sur le stockage, nom du volume dans la configuration du clone, effet de la suppression du template.
7. QCM — Pourquoi recommande-t-on `full_clone = true` pour le build d'une image dorée par `proxmox-clone` ?
   a) un clone lié ne peut pas être converti en template ; b) l'image dorée ne doit pas dépendre de l'image de base, qui sera reconstruite (et supprimée) ; c) un clone complet est plus rapide à créer ; d) le plugin ne gère pas les clones liés.
8. Packer « attend SSH » sur un build `proxmox-iso` alors que la console montre une invite de connexion. Cite trois causes possibles, dans l'ordre où tu les vérifierais, et la commande qui confirme chacune.
9. Que sont les niveaux de microarchitecture x86-64 (v1 à v4) ? Pourquoi RHEL 10 et ses dérivés exigent-ils v3, et pourquoi Proxmox propose-t-il `x86-64-v2-AES` par défaut plutôt que `host` ? Quel compromis fait `host` pour la migration à chaud dans un cluster (module 09) ?
10. Pourquoi une VM Rocky installée avec un contrôleur `virtio-scsi-single` ne démarre-t-elle pas si on passe son contrôleur en `lsi` ? Le même changement sur une VM Debian a-t-il le même effet ? Quel rôle joue l'initramfs, et qu'est-ce qu'un initramfs *hostonly* ?
11. `systemd-analyze blame` montre `cloud-init.service` à 25 s et `systemd-networkd-wait-online.service` à 20 s, pour un démarrage total de 32 s. Est-ce incohérent ? Que regardes-tu ensuite ?
12. QCM — Un *vendor-data* et un *user-data* fournissent tous deux `packages:` (listes différentes). Que se passe-t-il par défaut ?
    a) les deux listes sont fusionnées ; b) le *user-data* remplace la clé du *vendor-data* ; c) le *vendor-data* l'emporte ; d) erreur de schéma.
13. Le contrôle de Proxmox `ciupgrade` vaut 1 par défaut. Que met-il dans le *user-data*, quel est son coût, et dans quels cas le garder ?
14. Pourquoi un template ne doit-il jamais être démarré « juste pour vérifier » ? Que faire à la place ?
15. Décris ce que contient le lecteur cloud-init d'une VM Proxmox (format, étiquette, fichiers) et comment l'examiner sans démarrer la VM.
16. Quelles informations une VM peut-elle lire sur son hyperviseur par SMBIOS (`dmidecode`) et par l'agent ? Pourquoi `ds-identify` lit-il le DMI, et qu'est-ce que cela implique pour une VM qui prétendrait être sur OpenStack ?

**Critères de réussite**
- [ ] Les 16 questions ont une réponse argumentée (QCM : bonne réponse **et** pourquoi les autres sont fausses).
- [ ] Après correction, tes trois points les plus faibles sont identifiés, avec un exercice ou une lecture pour chacun.

<details><summary>Indice 1</summary>

Pour les questions 1 à 5, la documentation de cloud-init 25.1 (*Boot stages*, *Instance-ID*, *Module frequency*) et tes journaux de E21 suffisent.
</details>

<details><summary>Indice 2</summary>

Pour la question 6, ton étape 1 de M03-E16 contient la moitié de la réponse ; pour la question 10, `lsinitrd` sur une VM Rocky liste les modules embarqués.
</details>

**Pour aller plus loin** : choisis trois questions et transforme chacune en démonstration reproductible de 5 minutes sur le lab, à présenter à Karim.
