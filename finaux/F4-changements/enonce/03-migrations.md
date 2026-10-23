# Final F4 — Phase 3 : Migrations

Les montées de version sont faites (ou décidées). Il reste le changement que tout le monde redoute : sortir de chez InfoGér. Leur VMware s'éteint dans six semaines ; dessus tournent trois VMs que personne chez MédiSphère n'a jamais administrées, dont **Legacy-RDV**, la prise de rendez-vous qu'utilisent encore quarante cabinets. Claire Morel découpe le travail en deux temps : d'abord **rapatrier les VMs telles quelles** sur `pve01` (le « *lift and shift* » qui met fin au contrat), ensuite **sortir Legacy-RDV de sa VM** vers Kubernetes, avec une bascule courte et réversible. Sophie Laurent pose ses conditions : pas un mot de passe d'InfoGér ne survit à la migration, et les données de santé ne traînent nulle part. Nadia Roussel, elle, veut que les cabinets ne s'aperçoivent de rien.

Prérequis : phases 1 et 2 terminées ou décidées (`lab/bin/check F4 1` et `F4 2` verts : processus de changement et sonde de continuité en place).

**Ce que cette phase utilise** (rien ne doit porter un autre nom)

| Élément | Valeur |
|---|---|
| Processus | fiches `docs/changements/fiches/CHG-34xx[-<sujet>].md` sur le modèle `docs/changements/fiches/modele.md` (F4-S01), sonde de continuité et tableau « changement en cours » (F4-S02) |
| Hôte d'import | `pve01` ; stockage des disques `local-nvme` ; pool `lab` ; VNet `vinfra` (VLAN 20) |
| VMs d'InfoGér | `legacy-rdv01` **3401** → **10.10.20.44**, `ftp-part01` **3402** → **10.10.20.45**, `stats01` **3403** → **10.10.20.46** (adresses d'origine dans `192.168.50.0/24`, inexistant dans le lab) ; étiquettes `env-f4` et `role-<rôle>` |
| Code | état OpenTofu **`envs/f4-infoger`** de `plateforme/infra` ; `plateforme/ansible` (inventaire NetBox, rôles `node_exporter`, `alloy`, `durcissement`) ; `plateforme/k8s`, `plateforme/gitops`, `plateforme/charts-miroir`, `plateforme/secrets`, `plateforme/politiques` |
| Nom publié de Legacy-RDV | **`rdv.par1.medisphere.internal`** (VIP des répartiteurs `lb01`/`lb02`, 10.10.70.200) : c'est le nom des cabinets, il ne change jamais |
| Legacy-RDV sur Kubernetes | locataire Capsule **`legacy`**, espaces **`legacy-rdv-recette`** et **`legacy-rdv-prod`**, dépôt de déploiement **`legacy/deploiement`**, noms internes `legacy-rdv-recette.apps.par1.medisphere.internal` et `legacy-rdv.apps.par1.medisphere.internal` |
| Code de l'application | projet `legacy/legacy-rdv` (M12-E19 : image PHP 8.4 + Apache, `config.php` par l'environnement, `sante.php`) ; image `registry.par1.medisphere.internal/medisphere/legacy-rdv` (M13) |
| Documentation | `docs/changements/` de `plateforme/medisphere` (fiches, `runbooks/` à partir de RB-345, `post-mortems/`, `adr/`) |

**Variables de `lab/lab.env`** utilisées par les checks de cette phase (les défauts conviennent au lab) : `WB_F4_STOCKAGE_EXPORT` (`hdd-bulk`), `WB_F4_RDV_URL` (`https://rdv.par1.medisphere.internal`), `WB_F4_LEGACY_RECETTE_URL` (`https://legacy-rdv-recette.apps.par1.medisphere.internal`), `WB_F4_LEGACY_PROD_URL` (`https://legacy-rdv.apps.par1.medisphere.internal`), `WB_F4_INFRA` (`~/src/infra`).

> ⚠️ **Règles de la phase** (elles valent pour chaque scénario) :
> 1. **L'export d'InfoGér est la VM d'origine.** Tant que F4-S14 n'a pas décidé autre chose, les fichiers de `import/infoger-export/` restent intacts : c'est ton retour arrière ultime (« la VM est toujours chez InfoGér »). Tu travailles sur des copies importées, jamais sur l'export.
> 2. **Chaque changement a sa fiche CHG** (modèle de F4-S01), avec la mesure de la sonde avant, pendant et après.
> 3. **Les données de `legacy-rdv01` sont des données de santé** (fictives ici, traitées comme réelles) : aucune copie intermédiaire ne reste sur `adm01`, `pve01` ou un poste ; toute copie est chiffrée en transit et effacée après usage, et cela s'écrit.

---

### F4-S09 — Plan de migration du VMware d'InfoGér  `RED` `★★★`

> **Ticket CHG-3409** — *De : Claire Morel* — *Copie : Sophie Laurent, Nadia Roussel*
> InfoGér a enfin livré son export : trois VMs, une fiche d'inventaire de trois lignes et des mots de passe « sous dix jours ». Avant de toucher à quoi que ce soit, je veux savoir ce qu'il y a **vraiment** dedans, ce qui dépend de quoi, dans quel ordre on les fait venir, comment on revient en arrière, et quand. Le plan passe en revue jeudi avec Sophie et Nadia ; tant qu'il n'est pas validé, rien ne démarre chez nous.

**Objectifs pédagogiques**
- Auditer un export VMware sans le démarrer : intégrité, matériel déclaré, contenu des disques.
- Reconstituer un inventaire réel (services, comptes, flux, données, tâches planifiées) à partir de ce qu'on trouve, pas de ce qu'on vous dit.
- Écrire un plan de migration par vagues : dépendances, re-adressage, fenêtres, critères de succès, retour arrière.

**Prérequis** : F4-S01 (modèle de fiche) ; M09-E23 (import d'une OVA) ; M06 (NetBox, DNS) ; M26 (registre des exceptions).
**Durée indicative** : 4 à 5 h (dont 30 min de fabrication de l'export).

**Contexte technique**
- L'export est simulé : lis [`ressources/S09/README.md`](../ressources/S09/README.md) et fabrique-le sur `pve01` avec `fabriquer-export-vmware.sh`. Il arrive dans `<chemin de hdd-bulk>/import/infoger-export/` : un dossier par VM (`.ovf`, `.mf`, `-disk1.vmdk`). Le script affiche à la fin les sommes SHA-256 « envoyées par InfoGér par un autre canal ».
- La fiche [`ressources/S09/inventaire-infoger.csv`](../ressources/S09/inventaire-infoger.csv) est celle d'InfoGér. Elle est incomplète, et au moins une de ses lignes est fausse.
- Aucun identifiant ne t'est transmis. Les outils de `libguestfs` (installés sur `pve01` pour la fabrication) savent lire un disque **sans démarrer la VM** et sans le modifier (montage en lecture seule).
- Cible : `pve01`, VMID 3401-3403, VNet `vinfra`, adresses 10.10.20.44-46 (tableau d'en-tête). Les cabinets utiliseront `rdv.par1.medisphere.internal` dès la migration de `legacy-rdv01`.
- Le VMware d'InfoGér n'existe pas dans le lab : « la VM d'origine reste disponible chez InfoGér » se traduit par **les fichiers d'export intacts**, réimportables à tout moment.

**Travail demandé**

Livre `docs/changements/migration-vmware.md` dans `plateforme/medisphere` (MR relue par Claire et Sophie), avec :
1. **Contrôle de la livraison** : sommes vérifiées (contre le manifeste **et** contre les sommes « du courriel »), ce que déclare chaque descripteur (processeurs, mémoire, contrôleur de disque, carte réseau et son adresse MAC, micrologiciel, type de système, version du matériel virtuel), ce qui posera problème à l'import.
2. **Inventaire découvert**, VM par VM, en lisant les disques hors ligne : système et noyau, services activés, paquets notables, comptes locaux (et lesquels ont un accès SSH ou sudo), configuration réseau (nom d'interface, adresse, passerelle, résolveurs, fichiers `hosts`), tâches planifiées, données (où, combien, quelle taille ; pour Legacy-RDV : nombre de rendez-vous et de pièces jointes **référencées** et **présentes**), copies de données qui traînent, secrets trouvés en clair. Corrige la fiche d'InfoGér (un `inventaire-reel.csv` à côté du document, sans aucun secret).
3. **Dépendances et flux** : un schéma (Mermaid ou texte) des flux entre les trois VMs et avec l'extérieur (cabinets, partenaires, direction), avec ports et sens ; ce qui casse si une VM change d'adresse avant les autres.
4. **Vagues et ordre** : quelle VM d'abord, lesquelles ensemble, pourquoi ; le **re-adressage** vers 10.10.20.44-46 et tout ce qu'il implique dans les VMs (configurations, droits de base de données, adresses annoncées) ; les noms DNS et l'inscription dans NetBox ; le nom publié des cabinets.
5. Pour chaque vague : **fenêtre** (durée, horaire, à qui on l'annonce), **critères go/no-go**, **critères de succès** observables, **retour arrière** (étapes, durée, point de non-retour), mesures de la sonde attendues.
6. **Ce qui ne migre pas tel quel** : écarts aux standards MédiSphère (système, pilotes, outils, accès, chiffrement des flux, durcissement) et, pour chacun, « corrigé à la migration », « exception déclarée jusqu'au … », ou « réglé par la suite (F4-S12 à S14) ».
7. Une fiche **`docs/changements/fiches/CHG-3410.md`** (catégorie, risque, impact, fenêtre…) pour la migration des trois VMs, prête pour F4-S10.

**Contraintes**
- Aucun démarrage des VMs d'InfoGér avant la validation du plan (le contrôle porte sur les disques à l'arrêt).
- Aucune modification de l'export : toute inspection est en lecture seule, ou sur une copie effacée ensuite.
- Aucun secret trouvé dans les disques ne figure dans le dépôt (mentionne seulement *où* il est et *ce qu'on en fera*).

**Critères de réussite**
- [ ] L'export des trois VMs est présent sur `pve01`, complet et conforme à ses manifestes.
- [ ] `docs/changements/migration-vmware.md` est sur `main` de `plateforme/medisphere` : inventaire découvert, dépendance de `stats01` vers `legacy-rdv01`, vagues, re-adressage vers 10.10.20.44-46, fenêtres, critères, retour arrière.
- [ ] `docs/changements/inventaire-reel.csv` et `docs/changements/fiches/CHG-3410.md` sont sur `main`.

**Vérification** : `lab/bin/check F4 9`

<details><summary>Indice 1</summary>

Un manifeste VMware a le format `SHA256(fichier)= somme` : convertis-le pour `sha256sum -c`. Pour le contenu, `virt-inspector`, `virt-ls`, `virt-cat` et `guestfish --ro` lisent directement le fichier VMDK, sans conversion et sans démarrer quoi que ce soit.
</details>

<details><summary>Indice 2</summary>

Les dépendances ne sont pas dans la fiche : elles sont dans les fichiers de configuration (`/etc/hosts`, fichiers `.cnf`, scripts de `/opt`, `/etc/cron.d/`) et dans les droits de la base. Les droits MariaDB sont dans la base elle-même : une copie du disque, montée sur une VM jetable, ou la lecture du vidage que fait InfoGér chaque nuit (cherche-le) te les donnent sans rien démarrer chez toi.
</details>

<details><summary>Indice 3</summary>

Pour chaque élément qui contient une **adresse** (`192.168.50.x`) ou un **nom** d'InfoGér (`infoger.local`), demande-toi qui le lit et à quel moment : au démarrage d'un service, à la connexion d'un client, la nuit ?
</details>

**Pour aller plus loin** (facultatif) : l'import direct depuis un ESXi (stockage `esxi` de Proxmox VE, <https://pve.proxmox.com/wiki/Migrate_to_Proxmox_VE>) : qu'aurait-il changé à ton plan (temps d'arrêt, migration à chaud des disques, accès réseau à l'ESXi d'InfoGér) ?

---

### F4-S10 — Migrer les VMs d'InfoGér vers Proxmox VE  `LIBRE` `★★★`

> **Ticket CHG-3410** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent*
> Plan validé. Fais venir les trois VMs, dans l'ordre que tu as proposé et dans les fenêtres annoncées. Je veux à la fin des VMs qui ressemblent aux nôtres : pilotes, agent, adresses de notre plan, noms dans le DNS, dans NetBox, sauvegardées, supervisées, et **inscrites dans le code** comme tout le reste. Karim relira l'état OpenTofu : s'il voit un `plan` qui veut recréer quoi que ce soit, ça ne passe pas.

**Objectifs pédagogiques**
- Importer une VM VMware dans Proxmox VE et la convertir aux pilotes paravirtualisés (contrôleur, carte, initramfs, nom d'interface), outils de l'ancien hyperviseur retirés, agent installé.
- Reprendre la main sur des VMs dont on n'a aucun identifiant, proprement et en laissant une trace.
- Re-adresser des services couplés (base de données, FTP passif, script distant) sans casser leurs dépendances.
- Inscrire dans le code des VMs créées hors du code (blocs `import` d'OpenTofu, inventaire, sauvegarde, supervision).

**Prérequis** : F4-S09 (plan validé, fiche CHG-3410) ; M09-E23 ; M05 (OpenTofu, `bpg/proxmox`) ; M06 (NetBox, DNS) ; M07 (HAProxy de `lb01`/`lb02`) ; M21-M22 (supervision, journaux) ; M26 (durcissement, exceptions).
**Durée indicative** : 6 à 8 h.

**Contexte technique**
- Cible : tableau d'en-tête de la phase (VMID, adresses, VNet, pool, stockage). Passerelle 10.10.20.1, résolveurs 10.10.20.10 et 10.10.20.16, domaine `par1.medisphere.internal`.
- Standards de VM MédiSphère : contrôleur `virtio-scsi-single`, carte `virtio`, type de CPU commun (`x86-64-v2-AES`), console série, agent QEMU activé **et** répondant, micrologiciel conforme à l'origine, compte `admin` avec ta clé SSH (sudo sans mot de passe), aucun compte ni clé d'un tiers.
- `stats01` lit la base de `legacy-rdv01` chaque nuit : à la fin du scénario, elle la lit à sa **nouvelle** adresse, avec un compte de base qui n'accepte que la nouvelle adresse de `stats01`.
- Les partenaires déposent sur `ftp-part01` en FTP (mode passif). Au moins un dépôt de test en mode passif doit réussir depuis `adm01` à la nouvelle adresse.
- Publication : à la migration de `legacy-rdv01`, le nom des cabinets `rdv.par1.medisphere.internal` est servi par `lb01`/`lb02` (terminaison TLS sur les répartiteurs, certificat ACME, comme `sso` au M24) vers `legacy-rdv01`. Le flux répartiteurs → `legacy-rdv01` reste en HTTP jusqu'à F4-S13 : c'est une **exception déclarée** (registre du M26), avec sa date de fin.
- Le rôle `durcissement` vise Debian 13 et Rocky 10 : des VMs Debian 12 ne sont pas dans son référentiel. Décide (et écris) ce que tu appliques à ces trois VMs d'ici leur fin de vie.
- Code : état **`envs/f4-infoger`** dans `plateforme/infra` ; les VMs existent déjà quand tu écris le code : OpenTofu sait les **importer** dans l'état sans les recréer (`import` dans la configuration, OpenTofu ≥ 1.5), et peut écrire une première configuration pour toi. Sauvegarde : PBS (`pbs-par2`), travail planifié dédié aux trois VMs.

**Travail demandé**

Objectifs :
1. Les trois VMs tournent sur `pve01` dans l'ordre et les fenêtres de ton plan, après **vérification de l'intégrité** de chaque export ; chacune est conforme aux standards (contexte), sans `open-vm-tools`, avec l'agent QEMU qui répond.
2. Elles sont à leurs adresses de 10.10.20.44-46, résolues dans le DNS (direct et inverse), décrites dans NetBox, et plus aucune configuration n'y mentionne `192.168.50.` ni `infoger.local`.
3. Les services rendent le même service qu'avant : Legacy-RDV répond sur `legacy-rdv01` et sur `rdv.par1.medisphere.internal` ; le dépôt FTP passif fonctionne ; le script de statistiques de `stats01` produit un fichier non vide ce soir (ou lancé à la main pour le prouver).
4. L'accès d'InfoGér est fermé (compte, clé, sudo), et aucun mot de passe d'InfoGér ne permet plus rien. Le mot de passe de base écrit en dur dans Legacy-RDV ne peut être changé qu'avec le code (F4-S12) : décide quoi en faire d'ici là, et écris-le.
5. Tout est **dans le code** : état `envs/f4-infoger` (VMs importées, NetBox, DNS), inventaire et variables Ansible (supervision, journaux, exceptions de durcissement), répartiteurs, travail de sauvegarde ; `tofu plan` sur `envs/f4-infoger` ne propose **aucun** changement.
6. Une première sauvegarde PBS de chaque VM existe ; la sonde de continuité surveille Legacy-RDV sur le nom publié ; la fiche CHG-3410 est complétée (mesures, écarts, durée réelle) et un runbook **RB-345** « Migrer une VM VMware vers Proxmox VE » décrit ta méthode pour les prochaines.

Contraintes :
- L'export n'est jamais modifié ; tu travailles sur des disques importés.
- Une VM à la fois ; le retour arrière de ton plan est prêt avant chaque vague.
- Aucune modification « à la main » qui ne soit ensuite rattrapée par le code (sauf les gestes de conversion propres à l'import, consignés dans RB-345).

**Critères de réussite**
- [ ] Les VMs 3401, 3402 et 3403 existent dans le pool `lab`, avec leur nom, un contrôleur VirtIO SCSI, une carte `virtio` sur `vinfra`, l'agent activé et répondant, sans disque SATA/IDE ni carte `vmxnet3`/`e1000`.
- [ ] Elles portent 10.10.20.44, .45 et .46 ; les noms `legacy-rdv01`, `ftp-part01`, `stats01` de `par1.medisphere.internal` y résolvent (et l'inverse) ; NetBox les décrit avec ces adresses.
- [ ] `open-vm-tools` n'est ni installé ni actif ; le compte `infoger` ne peut plus se connecter ; plus aucune mention de `192.168.50.` dans les configurations réseau et applicatives.
- [ ] Legacy-RDV répond sur `http://legacy-rdv01.par1.medisphere.internal/` et sur `https://rdv.par1.medisphere.internal/` ; un dépôt FTP passif réussit sur `ftp-part01` ; `stats01` a produit un fichier de statistiques non vide depuis la migration.
- [ ] `envs/f4-infoger` existe dans `plateforme/infra` avec des blocs `import` pour les trois VMs, et son `tofu plan` est vide.
- [ ] Une sauvegarde de chaque VM existe sur `pbs-par2`.
- [ ] Le témoin de `mon01` sonde Legacy-RDV par le nom des cabinets dans un groupe `continuite-*` étiqueté `service=legacy-rdv` (contrat de la sonde de F4-S02).

**Vérification** : `lab/bin/check F4 10`

<details><summary>Indice 1</summary>

`qm importovf` lit le descripteur, mais pas tout : compare sa sortie `--dryrun` avec ce que tu as relevé en F4-S09 (carte réseau, contrôleur, micrologiciel). Ce qui manque se règle avec `qm set` **avant** le premier démarrage. Pour les fichiers de l'invité (réseau, comptes, clé, paquets), `virt-customize` sait aussi travailler sur le disque d'une VM **arrêtée** : demande à `pvesm path` où il est.
</details>

<details><summary>Indice 2</summary>

Un nom d'interface Linux dépend de l'emplacement PCI de la carte (`ens192` chez VMware). Démarre une fois sans réseau si tu doutes, et regarde la console série (`qm terminal`). Pour la base : les comptes MariaDB sont liés à une **adresse cliente** ; `RENAME USER` existe. Pour le FTP passif, relis ce que le serveur **annonce** au client.
</details>

<details><summary>Indice 3</summary>

Pour l'état OpenTofu : un bloc `import { to = …, id = "<nœud>/<vmid>" }` par VM, puis `tofu plan -generate-config-out=…` écrit une configuration de départ que tu nettoies jusqu'au plan vide (en ignorant ce que le fournisseur ne sait pas relire, avec justification). Les VMs importées ne viennent pas d'un modèle : le module `vm-debian` ne leur convient pas.
</details>

**Pour aller plus loin** (facultatif) : écris un contrôle de conformité scripté (`medictl vm conformite <vmid>` ou un test Testinfra) qui vérifie les standards du contexte sur n'importe quelle VM migrée.

---

### F4-S11 — Panne : la VM migrée ne démarre pas comme avant  `BF` `★★★`

> **Ticket INC-6011** — *De : Nadia Roussel*
> Lucas a fait la « petite maintenance » des VMs d'InfoGér ce matin (il voulait « finir la conversion » et appliquer une consigne d'InfoGér retrouvée dans leur wiki). Depuis son redémarrage, une des VMs ne revient pas comme avant. Personne n'a touché à Legacy-RDV, heureusement. Lucas est en formation toute la journée, il a laissé ses notes… qui disent « rien de spécial ».

**Objectifs pédagogiques**
- Diagnostiquer un démarrage raté par la console série, sans accès réseau à la VM.
- Relier un symptôme de démarrage à une couche : micrologiciel, initramfs (pilotes), montage des systèmes de fichiers, réseau.
- Réparer sans réinstaller, puis rendre la correction durable (code, documentation).

**Prérequis** : F4-S10 (les trois VMs migrées, `lab/bin/check F4 10` vert).
**Durée indicative** : 1 h 30 (temps cible : 45 min).

**Injection** : `lab/bin/break F4 11` (depuis `adm01`). La panne vise `ftp-part01` ou `stats01`, jamais `legacy-rdv01`. Un instantané Proxmox est pris avant l'injection : `lab/bin/break F4 11 --annuler` revient à cet instantané si la VM est encore en panne (filet de sécurité si tu abandonnes), ou supprime seulement l'instantané si tu l'as réparée : lance-le une fois le contrôle vert.

**Symptôme** : affiché par la commande d'injection (comme Nadia le rapporte).

**Travail demandé**
1. Diagnostique depuis la console de la VM et depuis `pve01` ; note chaque hypothèse et ce qui l'a confirmée ou écartée.
2. Répare la VM sans la réinstaller, sans restaurer de sauvegarde et sans revenir à l'instantané de la panne.
3. Rends la correction durable : ce qui doit changer dans le code (`envs/f4-infoger`, Ansible) ou dans RB-345 pour que ça ne se reproduise pas.
4. Écris le post-mortem `docs/changements/post-mortems/INC-6011-<sujet>.md` : chronologie, hypothèses, cause, correction, prévention.

**Critères de réussite**
- [ ] La VM visée a redémarré **après** ta réparation, l'agent QEMU répond, elle est joignable à son adresse et son service (FTP ou statistiques) fonctionne.
- [ ] La configuration Proxmox de la VM est de nouveau conforme aux standards (contrôleur, carte, `tofu plan` vide).
- [ ] Le post-mortem INC-6011 est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check F4 11`

<details><summary>Indice 1</summary>

Une console série ne montre que ce que le noyau et systemd y écrivent : regarde `qm config` pour savoir où elle est, et demande-toi à quel moment exact le démarrage s'arrête (avant ou après le montage de la racine ? avant ou après le réseau ?).
</details>

<details><summary>Indice 2</summary>

Compare la configuration actuelle de la VM avec celle de la veille : Proxmox garde la configuration de chaque instantané (`qm listsnapshot`, `qm config --snapshot`). Les fichiers de l'invité se lisent aussi VM arrêtée (`virt-cat`, `guestfish --ro`) : `fstab`, configuration du réseau, `/etc/systemd/network/`, `/etc/initramfs-tools/`.
</details>

<details><summary>Indice 3</summary>

Un noyau qui ne trouve pas sa racine n'a pas, dans son initramfs, le pilote du contrôleur sur lequel est le disque ; un système qui passe en mode urgence attend un périphérique qu'il ne trouvera jamais ; une interface qui garde un nom inattendu ne reçoit pas la configuration prévue pour un autre nom.
</details>

**Pour aller plus loin** (facultatif) : ajoute à ton contrôle de conformité (S10) une vérification qui aurait détecté la cause **avant** le redémarrage.

---

### F4-S12 — Legacy-RDV sur Kubernetes  `LIBRE` `★★★★`

> **Ticket CHG-3412** — *De : Claire Morel* — *Copie : Sophie Laurent, Julien Petit, Karim Benali*
> Legacy-RDV est chez nous, sur une VM Debian 12 qui ne passera pas l'audit HDS. Il ne sera pas réécrit cette année. On le met dans `k8s-par1`, en recette d'abord, avec les mêmes exigences que MédiAgenda : configuration et secrets hors du code, deux réplicas, journaux sur la sortie standard, sauvegardes, image signée. Pour la base, Karim propose **mariadb-operator** plutôt qu'un StatefulSet fait main ; Sophie veut que le mot de passe de 2014 meure ici. La production attendra la bascule (CHG-3413), mais elle doit être prête.

**Objectifs pédagogiques**
- Rendre une application monolithique « sans état » au strict nécessaire pour qu'elle tourne à deux réplicas : sessions partagées, fichiers partagés, configuration, santé.
- Installer et exploiter un opérateur de base de données par GitOps (CRD avant l'opérateur, charts recopiés et signés).
- Intégrer une nouvelle application à toute la plateforme : locataire, espaces, secrets, politiques, publication, sauvegarde, supervision.

**Prérequis** : F4-S10 ; M12-E19 (image), M13 (signature), M16 (CephFS RWX), M19 (composants CI), M20 (GitOps, `charts-miroir`), M24-M26 (identité, ESO, Kyverno, PSA), M27 (données), M28 (Capsule).
**Durée indicative** : 10 à 12 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Opérateur | **mariadb-operator 26.6.x** (licence MIT ; distinct du *MariaDB Enterprise Operator*) : charts OCI `oci://ghcr.io/mariadb-operator/charts/mariadb-operator-crds` et `…/mariadb-operator`, recopiés et signés par `plateforme/charts-miroir` ; espace **`mariadb-system`** ; API `k8s.mariadb.com/v1alpha1` (`MariaDB`, `Database`, `User`, `Grant`, `Backup`, `SqlJob`…). L'ancien dépôt Helm non OCI est **déprécié** |
| Base | MariaDB **11.8** (image officielle par le cache Harbor) : la VM est en 10.11, la migration change aussi de version majeure |
| Locataire et espaces | locataire Capsule **`legacy`** (propriétaire : l'équipe plateforme, Legacy-RDV n'a pas d'équipe de développement), espaces **`legacy-rdv-recette`** (synchronisé automatiquement) et **`legacy-rdv-prod`** (synchronisé à la main), PSA `restricted`, quotas ; créés par le mécanisme « équipe en code » de F2 ou, à défaut, par `plateforme/k8s` comme les autres espaces |
| Secrets | OpenBao : `kv/legacy/<env>/mariadb` et `kv/legacy/<env>/s3`, livrés par ESO (SecretStore `openbao` de chaque espace, rôle `eso-legacy-rdv-<env>`) |
| Pièces jointes | PVC **`cephfs`** en `ReadWriteMany` partagé par les réplicas et le CronJob de purge |
| Sauvegardes | sauvegardes logiques de l'opérateur vers `s3-01` (compartiment à créer, chiffré en transit) ; restauration **éprouvée** |
| Publication | HTTPRoute sur `gw-par1` : `legacy-rdv-recette.apps.par1.medisphere.internal` (recette), `legacy-rdv.apps.par1.medisphere.internal` (prod) ; noms **internes** au lab (non publiés par les répartiteurs avant F4-S13) |
| Image | `registry.par1.medisphere.internal/medisphere/legacy-rdv:v2.4.0` construite par les composants CI/CD (M19), signée, référencée par empreinte ; Kyverno doit l'exiger dans les deux espaces |
| Vérifications | le compte `wb-checks` doit lire (jamais les Secrets) les objets `k8s.mariadb.com` : ClusterRole agrégée `wb-checks-donnees-mariadb` (étiquette `workbook.medisphere.internal/checks: "true"`, comme `wb-checks-services` au M27) à ajouter dans `plateforme/k8s` |

Correctifs de code **autorisés** (dans `legacy/legacy-rdv`, jamais dans `apps/` du dépôt du workbook) : ajouts et modifications strictement nécessaires à l'exécution en plusieurs réplicas (sessions, santé, journal, fuseau, purge), sans changer ce que voient les cabinets (mêmes pages, mêmes règles).

**Travail demandé**

Objectifs :
1. **Application prête pour deux réplicas** : sessions partagées entre les réplicas (dans la base ou dans Valkey : décide et justifie), pièces jointes partagées, configuration et mot de passe par l'environnement et des fichiers de secret, journaux de l'application et d'Apache sur les sorties standard, `display_errors` coupé, réglages PHP (taille des téléversements) dans un `php.ini` de l'image, point de **vivacité** qui ne touche pas la base et point de **disponibilité** qui la touche ; la date « maintenant » ne doit pas dépendre du fuseau du serveur de base. Version **2.4.0**, image signée.
2. **Opérateur** : CRD puis opérateur installés par Argo CD depuis Harbor, dans le bon ordre, avec des valeurs relues (webhook, métriques, ressources, sécurité des pods) ; ce que l'opérateur crée en ton nom, et avec quels droits.
3. **Base de recette** : une `MariaDB` 11.8 dans `legacy-rdv-recette` (stockage, ressources, métriques, fuseau, jeu de caractères ; et ce qui se passe pour elle pendant le drain d'un nœud), la base `legacy_rdv`, un compte applicatif aux droits minimaux et un compte de migration distinct, déclarés par les objets de l'opérateur ; mots de passe générés et rangés dans OpenBao, **jamais** celui de 2014.
4. **Déploiement** dans `legacy/deploiement` (Kustomize, base + overlays `recette` et `prod`) synchronisé par Argo CD : deux réplicas, anti-affinité, PDB, sondes, ressources, PSA `restricted` (Apache sans root, racine en lecture seule si tu y arrives, sinon écrit), politique réseau, priorité, HTTPRoute ; **CronJob de purge** des pièces jointes qui met **aussi** la base à jour (ou décision écrite de ne pas le faire) et purge les sessions expirées.
5. **Données de recette** : copie des données actuelles de `legacy-rdv01` (base et pièces jointes) dans la recette, sans fichier intermédiaire qui reste ; vérification qu'aucun rendez-vous ne change d'heure et que les pièces jointes se téléchargent.
6. **Sauvegarde et restauration** : sauvegarde planifiée de la base vers `s3-01` ; restauration éprouvée dans un espace jetable ou une seconde `MariaDB` ; sauvegarde des pièces jointes décrite (Velero ou autre). La **production** (`legacy-rdv-prod`) est prête à recevoir les données : base vide, application déployée à zéro trafic.
7. **Documentation** : fiche CHG-3412, ADR des choix (opérateur, sessions, stockage des pièces jointes), mise à jour de `docs/conteneurs/legacy-rdv-12-facteurs.md` (ce qui était « écart assumé » au M12 et ne l'est plus).

Contraintes :
- `apps/legacy-rdv` du dépôt du workbook reste inchangé ; aucune image Bitnami ; aucun chart tiré d'Internet par Argo CD.
- Aucun mot de passe dans Git, dans l'image, dans une ligne de commande ou dans les variables d'un pod visibles par `kubectl describe`.
- Deux réplicas réellement actifs : un formulaire servi par un réplica et soumis à l'autre doit réussir.

**Critères de réussite**
- [ ] Les Applications Argo CD de l'opérateur (CRD et contrôleur) et de Legacy-RDV en recette sont `Synced` et `Healthy` ; les charts viennent de `registry.par1.medisphere.internal/charts`.
- [ ] Dans `legacy-rdv-recette` : une `MariaDB` prête en 11.8, `Database`, `User` et `Grant` prêts, une `Backup` planifiée vers `s3-01` qui a déjà réussi, deux pods de Legacy-RDV prêts sur deux nœuds différents, un PVC `cephfs` en `ReadWriteMany`, un PDB, un CronJob de purge, des `ExternalSecret` synchronisés.
- [ ] `https://legacy-rdv-recette.apps.par1.medisphere.internal/sante.php` répond 200, la page d'accueil liste les rendez-vous, une pièce jointe de la recette se télécharge, et un formulaire de prise de rendez-vous soumis plusieurs fois de suite ne répond jamais « Votre session a expiré ».
- [ ] L'image de Legacy-RDV est référencée par empreinte et la politique de signature de Kyverno couvre `legacy-rdv-recette` et `legacy-rdv-prod`.
- [ ] `legacy-rdv-prod` contient une `MariaDB` prête et l'application déployée.

**Vérification** : `lab/bin/check F4 12`

<details><summary>Indice 1</summary>

Pour l'opérateur, regarde ce qu'Argo CD doit appliquer en premier (CRD) et comment l'exprimer (deux Applications, ou des vagues de synchronisation). La référence des champs est `docs/api_reference.md` du dépôt de mariadb-operator, **à la version 26.6.0** (les champs changent d'une version à l'autre). L'opérateur sait générer les mots de passe… mais alors ils ne sont pas dans OpenBao : choisis la source de vérité.
</details>

<details><summary>Indice 2</summary>

PHP permet de remplacer le stockage des sessions par une classe qui implémente `SessionHandlerInterface` (`session_set_save_handler`) : quelques dizaines de lignes avec `mysqli` suffisent, sans extension supplémentaire dans l'image. Pour « maintenant », comparer une `DATETIME` sans fuseau avec `NOW()` du serveur suppose que serveur et application ont le même fuseau : est-ce encore vrai dans un conteneur MariaDB ?
</details>

<details><summary>Indice 3</summary>

Pour les données de recette, un vidage logique depuis `legacy-rdv01` par un tuyau SSH, chargé par un pod client, ne laisse aucun fichier ; pour les pièces jointes, un `rsync` par SSH vers un pod qui monte le PVC (ou un Job), ou `kubectl cp` en flux. Compte, avant et après, les rendez-vous **et** les pièces jointes présentes.
</details>

**Pour aller plus loin** (facultatif) : remplace le PVC CephFS par un stockage objet (RGW) pour les pièces jointes : que faut-il changer dans le code, et qu'est-ce que ça simplifie (sauvegarde, réplication, purge) ?

---

### F4-S13 — La bascule de Legacy-RDV  `LIBRE` `★★★★`

> **Ticket CHG-3413** — *De : Claire Morel* — *Copie : Nadia Roussel, Sophie Laurent*
> La recette tient depuis une semaine, Julien et deux cabinets pilotes l'ont validée. On bascule la production samedi matin : quinze minutes de coupure **au plus**, mesurées par ta sonde, annoncées aux cabinets par Nadia une semaine avant. Je veux un retour arrière prêt pendant 48 heures, et que la VM ne bouge plus d'un octet après la bascule, au cas où. Et qu'on ne découvre pas lundi que les rendez-vous de mardi ont glissé d'une heure.

**Objectifs pédagogiques**
- Préparer et conduire une bascule de production : répétition, fenêtre, gel, synchronisation finale, contrôles, communication, retour arrière.
- Migrer des données d'une version majeure de MariaDB à une autre sans perte ni décalage horaire.
- Changer la cible d'un nom publié sans que les utilisateurs changent quoi que ce soit.

**Prérequis** : F4-S12 (recette validée, production prête) ; F4-S02 (sonde) ; F4-S10 (publication par `lb01`/`lb02`).
**Durée indicative** : 6 à 8 h (dont une répétition complète).

**Contexte technique**
- Avant la bascule, `rdv.par1.medisphere.internal` est servi par `legacy-rdv01` à travers les répartiteurs (F4-S10) ; après, par Legacy-RDV dans `legacy-rdv-prod` (Gateway `gw-par1`, nom interne `legacy-rdv.apps.par1.medisphere.internal`). Les cabinets ne changent ni d'adresse ni de favori.
- Source : MariaDB 10.11 de `legacy-rdv01`, base `legacy_rdv`, fuseau système `Europe/Paris`. Cible : MariaDB 11.8 de l'opérateur dans `legacy-rdv-prod`.
- `stats01` lit chaque nuit la base de production : après la bascule, il lit la base de `legacy-rdv-prod` (par quel chemin réseau, avec quel compte : à toi de le décider et de l'écrire), ou la décision est prise de l'arrêter.
- Fenêtre : ≤ **15 min** d'indisponibilité vue par la sonde de continuité, du gel au retour du service.
- La **référence** (nombre de rendez-vous de la base source au moment du gel) est relevée dans la fiche, sur une ligne de la forme `Référence rendez-vous : <nombre>` : le contrôle la relit.

**Travail demandé**

Objectifs :
1. **Plan de bascule** dans la fiche CHG-3413 : étapes minutées, responsables, critères go/no-go (avant, et au point de non-retour), contrôles après bascule, communication (avant, pendant, après), retour arrière **testé** et sa durée, et la mesure de la sonde avant / pendant / après.
2. **Synchronisation des données** : choisis entre un vidage logique complet dans la fenêtre, un vidage initial suivi d'un rattrapage court, ou une réplication depuis la VM, et justifie-le par les volumes mesurés et le temps de la répétition. Les jeux de caractères, les collations et les `DATETIME` sans fuseau arrivent intacts : prouve qu'**aucun rendez-vous ne change d'heure** (au moins sur les rendez-vous témoins de l'export : `dr-temoin`).
3. **Pièces jointes** : copie initiale et rattrapage vers le PVC de production, vérification (nombre et sommes d'un échantillon), sans fichier intermédiaire.
4. **Gel** de l'ancienne application (plus aucune écriture possible, lecture seule pour les vérifications), puis **bascule** du nom publié vers Kubernetes, puis contrôles fonctionnels par l'URL des cabinets.
5. **Retour arrière** prêt pendant 48 h : la VM reste en lecture seule et sauvegardée ; tu sais en combien de minutes rendre le nom à la VM et quoi faire des rendez-vous pris entre-temps (décision écrite).
6. **Après la bascule** : `stats01` repointée (ou arrêtée par décision), sauvegardes de production vérifiées, supervision et alertes de Legacy-RDV en production, runbook **RB-346** « Bascule et retour arrière de Legacy-RDV », fiche CHG-3413 complétée avec les mesures réelles.

Contraintes :
- Répétition complète **avant** la vraie bascule, chronométrée, sur la recette (ou sur une copie de la production) ; la vraie bascule suit le plan, écart par écart consigné.
- Aucune écriture possible sur l'ancienne base après le gel ; aucune perte de rendez-vous ; aucun fichier de données qui traîne après la bascule.
- La sonde de continuité tourne pendant toute la fenêtre.

**Critères de réussite**
- [ ] `https://rdv.par1.medisphere.internal/` est servi par Legacy-RDV dans `legacy-rdv-prod` (deux pods prêts), plus par `legacy-rdv01`.
- [ ] La base de `legacy-rdv01` est gelée (Legacy-RDV ne peut plus y écrire) et son nombre de rendez-vous est égal à la référence de la fiche CHG-3413 ; la production en compte au moins autant.
- [ ] Les rendez-vous témoins (`dr-temoin`) s'affichent en production à la même date et à la même heure que dans l'export, et la pièce jointe témoin se télécharge à l'identique.
- [ ] La fiche CHG-3413 (en-tête de mesure du modèle de F4-S01 sur la fenêtre de bascule, objectif ≤ 900 s, référence) et RB-346 sont sur `main` ; l'interruption recalculée par le contrôle à partir de la sonde respecte l'objectif et correspond à celle que tu as notée.

**Vérification** : `lab/bin/check F4 13`

<details><summary>Indice 1</summary>

`mariadb-dump` écrit les `TIMESTAMP` en UTC (en-tête `SET TIME_ZONE='+00:00'`) mais les `DATETIME` tels quels : c'est ce qui se passe **après** le chargement (fuseau du serveur cible, de PHP, de la comparaison avec « maintenant ») qui décale un affichage. Compare l'affichage, pas seulement les valeurs.
</details>

<details><summary>Indice 2</summary>

Mesure d'abord : taille du vidage, temps de chargement dans la cible, volume des pièces jointes, pendant la répétition. Un `rsync` répété juste avant le gel réduit le rattrapage à quelques fichiers. Pour geler une application qui écrit en base, on peut retirer les droits d'écriture du compte applicatif (et le vérifier), ou couper l'application elle-même : choisis ce qui garde la lecture pour tes vérifications.
</details>

<details><summary>Indice 3</summary>

Le changement de cible du nom publié est une variable des répartiteurs (code Ansible, un répartiteur à la fois) ; le retour arrière est la même variable dans l'autre sens. Les répartiteurs savent réécrire l'en-tête `Host` et présenter le bon SNI à la Gateway.
</details>

**Pour aller plus loin** (facultatif) : refais la bascule avec une réplication MariaDB depuis `legacy-rdv01` vers l'opérateur (réplica externe) : de combien la fenêtre se réduit-elle, et qu'est-ce qu'il faut ouvrir et sécuriser pour cela ?
