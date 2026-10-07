# Module 05 — Palier 2 : Opérationnel

Le palier 1 a donné un outil, un compte, un environnement et un langage. Tout cela tient encore sur ton poste : l'état est un fichier de `adm01`, chaque VM est décrite en entier là où elle est créée, et le socle (les VMs qui comptent) n'est pas dans le code. Ce palier fait de `plateforme/infra` un outil d'équipe. D'abord un **stockage S3 à nous**, `s3-01`, créé par OpenTofu et configuré par Ansible (E10), pour y mettre l'**état partagé** (E11) et son **verrou** (E12). Puis la factorisation : un **module** `vm-debian` (E13), **versionné** dans `plateforme/tofu-modules` (E14), des **environnements** séparés (E15). Ensuite le plus délicat : faire entrer le **socle existant** dans le code sans le recréer (E16), **refactorer** sans rien détruire (E17), maîtriser le **cycle de vie** (E18) et le **cloud-init** généré (E19). On finit par la **qualité** du code (E20), deux exercices de relecture (E21, E22) et le passage de témoin à **Ansible** (E23).

> **Rappels** : tout se lance depuis `adm01`, dans `~/src/infra` (variable `WB_SRC`), après `set -a; . ~/.config/workbook/pve-tofu.env; set +a` (et, à partir de E11, `. ~/.config/workbook/s3-tofu.env`). Chaque changement passe par une **MR** relue et fusionnée dans `main` ; on applique depuis `main` à jour. Les règles du module ([`00-introduction.md`](00-introduction.md)) s'appliquent, en particulier : aucun `apply` sans plan lu en entier, et **jamais** de `tofu destroy` dans `socle/`.

> **VMs de ce palier** : `s3-01` (VMID 1006, permanente) ; VMs d'environnement **2050-2056** (2050-2053 viennent du palier 1 ; 2054 `m05-module` puis `m05-jetable`, 2055-2056 la recette). Les VMID 2057-2059 sont réservés au palier 3 et aux pannes : ne les utilise pas.

---

### M05-E10 — Construire `s3-01` : un stockage S3 pour le socle  `LAB` `★★★`

> **Ticket PLAT-620** — *De : Claire Morel* — *Copie : Sophie Laurent, Karim Benali*
> On ne partagera pas l'état d'OpenTofu sur un poste. Il nous faut un stockage objet S3 sur le socle : MinIO est hors jeu, l'équipe a retenu **SeaweedFS** (l'ADR viendra en E30, avec les mesures). Ce sera `s3-01`, notre première machine permanente **créée par le code** : OpenTofu pour la VM, Ansible pour l'intérieur, comme tout le reste du socle. Sophie a ses conditions : HTTPS uniquement, une identité par usage et rien de plus que nécessaire, l'historique des états impossible à effacer par OpenTofu lui-même. Karim : le rôle Ansible est testé par Molecule, comme les autres.

**Objectifs pédagogiques**
- Créer une VM permanente du socle avec OpenTofu : clone complet, disque de données, réseau statique, cloud-init, garde-fous de cycle de vie.
- Installer SeaweedFS proprement : binaire vérifié par empreinte, compte dédié, service durci, écoute réseau minimale, disque de données monté.
- Configurer la passerelle S3 : TLS avec la CA provisoire, identités et droits par compartiment, versionnage, politique de compartiment.
- Faire entrer un nouvel hôte dans le socle : DNS, inventaire dynamique, `site.yml`, sauvegarde, documentation, registre des secrets.

**Prérequis** : M05-E08 (image dorée courante par source de données), M04-E24 (Molecule), M04-E46 (rôle `dnsmasq`, `site.yml`), M01-E04 (CA provisoire).
**Durée indicative** : 5 à 6 h.

**Contexte technique**
- `s3-01` (PLAN §4.5) : VMID **1006**, `10.10.20.14/24`, passerelle `10.10.20.1`, VNet `vinfra`, 2 vCPU, 2 Go, disque système 20 Go sur `local-nvme`, **disque de données 100 Go sur `hdd-bulk`**, étiquettes `socle` et `role-s3`, démarrage avec l'hôte (rang 4, comme `git01`). Code dans `~/src/infra/socle/` (nouvelle configuration, état **local** pour l'instant : E11 le migre).
- Le compte `wb-tofu` ne connaît que `vsandbox` et `local-nvme` (E03). Son script le prévoit : `VNETS="vsandbox vinfra" STOCKAGES="local-nvme hdd-bulk" ./pve-tofu-compte.sh` en root sur `pve01`.
- SeaweedFS **4.4x** (référence : 4.45), binaire unique `weed`, archive `linux_amd64.tar.gz` de la page des versions (<https://github.com/seaweedfs/seaweedfs/releases>). Mode retenu : **un seul processus** `weed server -s3` (master, volume, filer et passerelle S3). Port S3 : **8333**, en HTTPS.
- Identités S3 (fichier JSON de la passerelle, format de la page « S3 Credentials » du wiki) :

| Identité | Droits | Où vivent ses clés |
|---|---|---|
| `tofu-etat` | lire, écrire, lister le **seul** compartiment `tofu-state` | Vault (`lab`), `~/.config/workbook/s3-tofu.env` |
| `admin-s3` | administration (bris de glace) | Vault (`critique`), `~/.config/workbook/s3-admin.env` |

- Compartiment `tofu-state`, **versionné**. Certificat : CA provisoire (`~/pki-provisoire/`, M01-E04), SAN `s3-01.par1.medisphere.internal`, `s3-01`, `10.10.20.14`.
- Client S3 de `adm01` : **AWS CLI v2** (installeur officiel, <https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html>), profil `s3-socle` dans `~/.aws/config`. Les deux fichiers `s3-*.env` contiennent `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` et `AWS_PROFILE=s3-socle`.
- Rôle Ansible `seaweedfs` dans `plateforme/ansible` ; scénario Molecule `seaweedfs` sur l'instance **2049** (la plage Molecule 2045-2049 est pleine : 2049 est partagé avec `dnsmasq` et `node_exporter`, même `resource_group` en CI).
- Flux : `adm01` (MGMT) → `s3-01`:8333 et `runner01` → `s3-01`:8333 (même VLAN) n'ont rien à ouvrir sur `gw01` ; à reporter quand même dans `docs/socle/matrice-flux.md`.
- Alias SSH `s3-01` sur `adm01` (utilisateur `admin`, comme `git01`) : les vérifications l'utilisent.

**Travail demandé**
1. **Prépare le terrain.** Vérifie que le VMID 1006 et l'adresse 10.10.20.14 sont libres (comment le prouves-tu pour l'adresse ?). Élargis les droits de `wb-tofu` (contexte). Crée `socle/` dans une branche : versions, provider, variables, source de données de l'image dorée courante. Vérifie que `.gitignore` exclut bien l'état local que tu vas créer.
2. **Déclare `s3-01`.** Une ressource `proxmox_virtual_environment_vm` (pas encore de module : il vient en E13). Écris **explicitement** le matériel de l'image dorée (lis dans la documentation du provider ce qui arrive aux attributs non écrits lors d'un clone). Ajoute un second disque `scsi1`. Deux garde-fous : la VM ne doit jamais pouvoir être détruite par un plan, ni recréée parce que l'image `current` a changé. Quel drapeau de Proxmox ajoute une protection côté hyperviseur ? Justifie dans ton journal le format du disque de données sur `hdd-bulk` (pense à `ms-snapshot`, M02).
3. **Plan, MR, apply.** Lis le plan ligne à ligne, ouvre la MR, fais-la relire, puis applique depuis `main`. Vérifie dans Proxmox (`qm config 1006`) que le résultat est celui que tu as décrit.
4. **Nom et accès.** Ajoute `s3-01` au DNS par le rôle `dnsmasq` (M04-E46), l'alias SSH sur `adm01`, puis vérifie que l'inventaire dynamique d'Ansible la range dans `role_s3`. Pourquoi ne la voit-il dans aucun groupe avant l'étiquette ?
5. **Certificat.** Émets la clé et le certificat de `s3-01` avec la CA provisoire, comme pour `git01` (M01-E04).
6. **Rôle `seaweedfs`.** Écris le rôle, idempotent, testé par Molecule. Exigences :
   - binaire téléchargé et **vérifié par empreinte SHA-256** (la page des versions publie une somme MD5 à côté de chaque archive : compare-la, puis calcule et fige la SHA-256 dans le rôle) ; version et empreinte vont ensemble ;
   - compte système dédié, service systemd durci, démarrage impossible si le disque de données n'est pas monté ;
   - disque de données formaté **seulement s'il est vierge**, monté par étiquette ou UUID ;
   - **seule** la passerelle S3 écoute sur le réseau ; télémétrie désactivée ; services annexes non utilisés fermés (lis `weed server -h`) ;
   - identités générées depuis des variables (secrets en Vault), TLS, compartiments et versionnage créés par le rôle ;
   - une modification des identités ne coupe pas les clients.
   Le scénario Molecule vérifie le **service rendu** : TLS, refus de l'anonyme, versionnage, et une écriture conditionnelle (`If-None-Match: *`) refusée sur un objet existant.
7. **Mise en service.** Ajoute le playbook `s3-01.yml` à `site.yml` (garde-fou d'inventaire à mettre à jour : combien d'hôtes dans `socle` désormais ?), MR, pipeline, application par la chaîne de M04.
8. **Client et politique.** Installe AWS CLI v2 sur `adm01`, crée le profil `s3-socle` et les deux fichiers `s3-*.env`. Avec `tofu-etat`, liste les compartiments et lis le versionnage de `tofu-state`. Puis, avec `tofu-etat`, essaie de **suspendre** le versionnage de `tofu-state` : que se passe-t-il ? Avec `admin-s3`, pose une **politique de compartiment** qui l'interdit à `tofu-etat`, ainsi que la suppression définitive d'une version ; vérifie-la par l'essai inverse.
9. **Socle complet.** Inventaire du socle, matrice des flux, registre des secrets (les deux identités, la clé TLS), sauvegarde (`s3-01` est-elle dans `lab-nuit` ?) : mets à jour `plateforme/medisphere`.

> ⚠️ **Attention** : l'étape 8 modifie la configuration de `tofu-state` avec l'identité d'administration. Fais-le dans un sous-shell (`( set -a; . ~/.config/workbook/s3-admin.env; set +a; aws … )`) pour ne pas laisser ces clés dans ton environnement. Si tu suspends le versionnage par erreur, réactive-le aussitôt : les objets écrits entre-temps n'auront pas d'historique.

**Critères de réussite**
- [ ] `qm config 1006` : `s3-01`, 2 vCPU, 2048 Mo, `scsi0` 20 Go sur `local-nvme`, `scsi1` 100 Go sur `hdd-bulk`, `vinfra`, `ip=10.10.20.14/24,gw=10.10.20.1`, `protection: 1`, `onboot: 1`, étiquettes `role-s3;socle`, aucun disque adossé à un template.
- [ ] La VM 1006 est dans l'état de `socle/`.
- [ ] `s3-01.par1.medisphere.internal` se résout (A et PTR) ; `ssh s3-01 sudo -n true` aboutit.
- [ ] `curl https://s3-01.par1.medisphere.internal:8333/` aboutit **sans** `-k` et répond 403 ; en HTTP clair, la passerelle refuse.
- [ ] Sur `s3-01`, seuls 22 et 8333 écoutent sur 10.10.20.14 ; les données sont sur le disque de 100 Go.
- [ ] `tofu-etat` ne voit que `tofu-state` ; `tofu-state` est versionné ; `tofu-etat` ne peut ni suspendre le versionnage ni supprimer une version.
- [ ] `uv run molecule test -s seaweedfs` passe ; un second passage de `site.yml` donne `changed=0` sur `s3-01`.
- [ ] Aucun secret S3 ni clé TLS en clair dans un dépôt ; les deux identités sont au registre des secrets.

**Vérification** : `lab/bin/check 05 10`

<details><summary>Indice 1</summary>

Pour le provider, cherche dans la documentation de `proxmox_virtual_environment_vm` les paragraphes sur le clonage et les valeurs par défaut (`cpu.type`, `scsi_hardware`, `agent.enabled`…), et sur l'import d'un disque par interface (`scsi1`). Dans la VM, `/dev/disk/by-id/` donne un nom stable au disque `scsi1` d'un contrôleur virtio-scsi. Pour SeaweedFS, `weed server -h` liste toutes les options : regarde celles qui commencent par `-ip`, `-s3.`, `-master.` et `-volume.max`.
</details>

<details><summary>Indice 2</summary>

Si la première écriture dans un compartiment échoue avec « No writable volumes », compare la taille maximale d'un volume SeaweedFS (option du master) à la taille du disque : chaque compartiment réserve plusieurs volumes dès sa première écriture. Si la passerelle accepte une requête sans signature, c'est qu'elle n'a chargé **aucune** identité : relis le wiki sur ce comportement. Pour créer un compartiment et activer son versionnage sans clé S3, `weed shell` (en local sur `s3-01`) a des commandes `s3.bucket.*`.
</details>

<details><summary>Indice 3</summary>

Si la CLI aws refuse le certificat alors que `curl` l'accepte : la CLI v2 n'utilise pas le magasin de certificats du système, mais sa propre liste, sauf réglage `ca_bundle` du profil (ou variable `AWS_CA_BUNDLE`, qui l'emporte sur le profil). Pour la politique de compartiment, le « principal » d'une identité SeaweedFS s'écrit comme un utilisateur IAM : `arn:aws:iam::<compte>:user/<nom>`.
</details>

**Pour aller plus loin** (facultatif) : `weed server -h` montre aussi `-metricsPort` : prépare la supervision du module 21. Lis la page « S3 Object Lock » du wiki : quel compromis entre un historique **inaltérable** (verrou d'objet en mode conformité) et la capacité à faire le ménage ?

---

### M05-E11 — Backend S3 et migration de l'état  `LAB` `★★`

> **Ticket PLAT-621** — *De : Karim Benali*
> `s3-01` tourne : on arrête de garder les états sur ton poste. Les deux configurations (`socle/` et `envs/lab-m05/`) passent sur `tofu-state`, une clé chacune. Je veux un état distant **identique** à l'état local, aucun fichier d'état qui traîne derrière, et aucun identifiant dans le code. Et que quelqu'un d'autre que toi puisse lancer un plan demain matin.

**Objectifs pédagogiques**
- Configurer le backend `s3` d'OpenTofu 1.13 pour un stockage compatible S3 qui n'est pas AWS, en comprenant chaque option.
- Migrer un état local vers un backend distant sans perte, et le prouver.
- Savoir où OpenTofu range la configuration du backend et l'état, et ce qui reste sur le poste.

**Prérequis** : M05-E10.
**Durée indicative** : 2 h.

**Contexte technique**
- Compartiment `tofu-state` ; clés `socle/terraform.tfstate` et `envs/lab-m05/terraform.tfstate` ; adresse `https://s3-01.par1.medisphere.internal:8333` ; région : n'importe quelle valeur acceptée par le SDK AWS (SeaweedFS l'ignore), le workbook écrit `us-east-1`.
- Identifiants : `AWS_ACCESS_KEY_ID` et `AWS_SECRET_ACCESS_KEY` de `~/.config/workbook/s3-tofu.env` (identité `tofu-etat`).
- Documentation : <https://opentofu.org/docs/language/settings/backends/s3/>.

**Travail demandé**
1. Avant tout : copie de sauvegarde des deux états locaux dans `~/m05/e11/` (mode 600). Note le `serial` et le `lineage` de chacun (`jq`), et la liste des ressources (`tofu state list`).
2. Lis la documentation du backend `s3`. Pour chaque option que tu comptes écrire, note en une ligne dans ton journal **pourquoi** elle est nécessaire avec SeaweedFS (que ferait OpenTofu sans elle ?). Quelles options ne mettras-tu **pas** (identifiants, profil…) et pourquoi ?
3. Écris le bloc `backend "s3"` de `socle/`, sans le verrou pour l'instant (E12). Lance `tofu init -migrate-state`. Lis chaque question posée. Vérifie avec `aws s3api list-object-versions` que l'objet est là, puis compare `serial`, `lineage` et `tofu state list` avec tes notes. Un `tofu plan` doit être vide.
4. Que reste-t-il dans `socle/` ? Regarde `terraform.tfstate`, `terraform.tfstate.backup` et `.terraform/terraform.tfstate` : que contient chacun, lequel peut-on supprimer, lequel ne doit **jamais** être commité ? Fais le ménage.
5. Même migration pour `envs/lab-m05/`. Que se passe-t-il si tu oublies de changer la clé en copiant le bloc d'une configuration à l'autre ? (Réponds par écrit, ne l'essaie pas sur `socle/`.)
6. MR, fusion. Puis, sur un **clone neuf** de `plateforme/infra` (dans `~/m05/e11/clone`), `tofu init` et `tofu plan` dans `socle/` : l'état distant suffit-il ?
7. Coupe le service SeaweedFS une minute (`sudo systemctl stop seaweedfs` sur `s3-01`) et lance `tofu plan` : que dit OpenTofu ? Redémarre le service.

> ⚠️ **Attention** : à l'étape 3, si `tofu init` propose de **ne pas** copier l'état existant, réponds non et arrête-toi : un état vide côté S3 ferait proposer à OpenTofu de recréer toutes les VMs. Ne supprime les fichiers locaux qu'après avoir vérifié l'état distant (étape 3).

**Critères de réussite**
- [ ] `socle/` et `envs/lab-m05/` déclarent un backend `s3` (clés `socle/terraform.tfstate` et `envs/lab-m05/terraform.tfstate`), sans aucun identifiant dans le code.
- [ ] Les deux objets existent dans `tofu-state` ; `serial` et `lineage` correspondent à tes notes.
- [ ] Plus aucun `terraform.tfstate` ni `terraform.tfstate.backup` local ; aucun fichier d'état suivi par Git.
- [ ] `tofu plan` est vide dans `socle/`, y compris depuis un clone neuf.

**Vérification** : `lab/bin/check 05 11`

<details><summary>Indice 1</summary>

Le SDK AWS essaie, par défaut, d'appeler des services qui n'existent pas chez SeaweedFS : STS pour valider les identifiants, IAM/STS pour trouver un numéro de compte, le service de métadonnées EC2 pour trouver des identifiants. Cherche dans la documentation les options `skip_…` qui les désactivent, et celle qui choisit l'adressage par chemin plutôt que par sous-domaine.
</details>

<details><summary>Indice 2</summary>

`tofu init` sans option, quand le backend a changé, refuse de continuer et propose `-migrate-state` ou `-reconfigure` : lis la différence dans `tofu init -help`. L'un copie l'état, l'autre ignore l'ancien.
</details>

**Pour aller plus loin** (facultatif) : depuis OpenTofu 1.8, le bloc `backend` accepte des variables et des `locals` « statiques » (évaluation anticipée). Dans quel cas est-ce utile, et pourquoi le workbook garde-t-il des littéraux ? (Indice : M05-E24.)

---

### M05-E12 — Verrouiller l'état partagé  `LAB` `★★`

> **Ticket PLAT-622** — *De : Karim Benali*
> Maintenant que l'état est partagé, deux `apply` peuvent partir en même temps, depuis ton poste et bientôt depuis la CI. Je veux un verrou, sans base de données à côté : OpenTofu sait poser un fichier verrou dans le compartiment. Mais je veux une **preuve** que SeaweedFS le respecte : un verrou qui ne verrouille pas, c'est pire que pas de verrou, on se croit protégé.

**Objectifs pédagogiques**
- Comprendre le verrou d'état : à quoi il sert, quand il est pris et rendu, ce qu'il contient.
- Configurer le verrou natif S3 d'OpenTofu (`use_lockfile`) et savoir de quelle propriété du stockage il dépend.
- Prouver par un test que le stockage implémente les écritures conditionnelles.

**Prérequis** : M05-E11.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Le verrou natif écrit un objet à côté de l'état, avec une **écriture conditionnelle** (en-tête HTTP `If-None-Match: *` : « n'écris que si l'objet n'existe pas »). Un stockage qui ignore cet en-tête accepte la seconde écriture : deux verrous « réussis ».
- AWS CLI v2 : `aws s3api put-object` accepte `--if-none-match`.
- Script à écrire : `outils/s3-tester-ecriture-conditionnelle.sh` dans `plateforme/infra`, objets d'essai sous le préfixe `_essais/` du compartiment.

**Travail demandé**
1. Active le verrou natif dans `socle/` et `envs/lab-m05/` (MR). Faut-il relancer `tofu init` ? Pourquoi ?
2. **Preuve par OpenTofu.** Dans deux terminaux sur `adm01`, lance un `tofu apply` dans `envs/lab-m05` (une modification sans risque, par exemple une description, et **ne réponds pas** à la question de confirmation), puis un `tofu plan` dans le second terminal. Note le message complet. Pendant que le premier attend, lis l'objet verrou avec `aws s3 cp s3://tofu-state/<clé du verrou> -` : quels champs contient-il ? Réponds `no` au premier, relance le plan.
3. Relance l'essai avec `-lock-timeout=2m` sur le second : que change cette option ? Dans quelle situation l'utiliserais-tu (pense à la CI, E26) ?
4. **Preuve par le stockage.** Écris `outils/s3-tester-ecriture-conditionnelle.sh` : deux `put-object --if-none-match '*'` sur la même clé, la seconde doit être refusée ; code retour 0 si c'est le cas, 1 sinon ; ménage de l'objet d'essai. ShellCheck propre. Lance-le avec `tofu-etat`. Quel code HTTP obtiens-tu ?
5. Le compartiment est versionné : `aws s3api list-object-versions --prefix envs/lab-m05/` après tes essais. Qu'est devenu l'objet verrou ? Que coûte ce choix, et faut-il s'en soucier ?
6. Questions à traiter par écrit : que se passe-t-il si `tofu apply` est tué (`kill -9`) pendant qu'il tient le verrou ? Qui peut lever un verrou, avec quelle commande, et quelles vérifications **avant** ? (Le runbook complet est l'objet de M05-E33.)

**Critères de réussite**
- [ ] `use_lockfile = true` dans les deux configurations, aucune table DynamoDB.
- [ ] Ton journal contient le message « Error acquiring the state lock » obtenu et le contenu de l'objet verrou.
- [ ] Le script renvoie 0 sur `tofu-state` et affiche le refus (412).
- [ ] Aucun verrou ne reste en place après tes essais.

**Vérification** : `lab/bin/check 05 12`

<details><summary>Indice 1</summary>

Le verrou porte le nom de la clé de l'état suivi de `.tflock`. Il n'existe que pendant une opération qui écrit l'état (ou pourrait l'écrire).
</details>

<details><summary>Indice 2</summary>

Dans le script, la seconde commande doit échouer : sous `set -e`, isole-la (`set +e … set -e`, ou `if ! …`) et examine sa sortie d'erreur pour distinguer « refusée comme prévu » de « échouée pour une autre raison » (réseau, droits).
</details>

**Pour aller plus loin** (facultatif) : relance ton script contre un autre stockage S3 (une instance Garage jetable sur une VM 2057-2059, détruite ensuite) : c'est l'expérience demandée par l'ADR de M05-E30.

---

### M05-E13 — Écrire un module `vm-debian` réutilisable  `LAB` `★★`

> **Ticket PLAT-623** — *De : Karim Benali* — *Copie : Lucas Martin*
> Compte les lignes : `s3-01` en fait cent, chaque VM d'environnement soixante, et ce sont les **mêmes** soixante lignes avec trois valeurs différentes. La prochaine fois qu'on change le type de CPU de l'image, on oublie une VM sur quatre. Je veux un module `vm-debian` dans un nouveau projet `plateforme/tofu-modules` : une VM Debian du lab, clone complet de l'image dorée courante, cloud-init, étiquettes, avec un contrat clair (entrées validées, sorties utiles, README généré). Lucas devra pouvoir s'en servir sans lire le code.

**Objectifs pédagogiques**
- Concevoir l'interface d'un module : variables obligatoires et facultatives, types objets avec `optional()`, validations, sorties.
- Savoir ce qui va dans un module et ce qui reste dans la configuration racine (providers, versions exactes, backend, `lifecycle`).
- Documenter un module avec terraform-docs et le tester sans infrastructure (`tofu test`, provider simulé).

**Prérequis** : M05-E07, M05-E08, M05-E10.
**Durée indicative** : 3 h.

**Contexte technique**
- Projet GitLab `plateforme/tofu-modules`, clone `~/src/tofu-modules`, configuré comme les autres projets `plateforme/*` (M01-E11, script `gitlab-proteger-projet.sh`). Module dans `vm-debian/` : `versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`, `README.md`.
- terraform-docs **0.24** : binaire de la page des versions <https://github.com/terraform-docs/terraform-docs/releases>, vérifié par sa somme, dans `/usr/local/bin`. Configuration `.terraform-docs.yml` à la racine du projet, mode **injection** entre les marqueurs `<!-- BEGIN_TF_DOCS -->` et `<!-- END_TF_DOCS -->`.
- Le module doit au moins savoir produire `s3-01` (E10), les VMs d'environnement de `envs/lab-m05` (E07) et une VM en DHCP sur `vsandbox`. Sorties minimales : `vm_id`, `nom`, `ipv4`.
- `tofu test` (fichiers `*.tftest.hcl`, dossier `tests/`) et les providers simulés (`mock_provider`) : <https://opentofu.org/docs/cli/commands/test/>.

**Travail demandé**
1. Avant d'écrire : liste dans ton journal tout ce qui **varie** entre `s3-01`, `m05-essai` et `m05-app02` (ce seront les variables), et tout ce qui est **identique** (ce sera le code du module). Où mets-tu les étiquettes `socle`, `role-…`, `env-…` : une liste libre, ou des variables qui les construisent ? Pourquoi ?
2. Écris le module. Contraintes :
   - aucune configuration de provider dans le module, une contrainte de version **large** (pourquoi pas `~> 0.115.0` ici ?) ;
   - l'image : par défaut le template `gold` + `<famille>` + `current`, avec la possibilité d'imposer un VMID (pour quoi faire ?) ;
   - les erreurs de saisie sortent au **plan** (validations : VMID dans une plage du PLAN, adresse avec masque, passerelle obligatoire en statique…) ;
   - une nouvelle image `current` ne recrée **aucune** VM ;
   - étiquettes dans l'ordre que Proxmox leur donne ;
   - disques de données en nombre variable, `scsi1`, `scsi2`… dans l'ordre.
3. Le module ne peut pas porter `prevent_destroy` selon le souhait de l'appelant : pourquoi ? Quelle protection proposes-tu à la place pour `s3-01` ?
4. Écris un exemple d'appel minimal (`exemples/minimal/`) qui sert aussi de test de validation.
5. Installe terraform-docs, génère le README. Écris à la main, autour du tableau généré, ce que le tableau ne dit pas : choix, limites, comment reconstruire une VM sur une nouvelle image.
6. Écris au moins quatre tests `tofu test` avec un provider simulé : étiquettes triées, image courante par défaut, image imposée, une validation qui doit échouer (`expect_failures`).
7. Commite sur `main` par MR (la version et la publication viennent en E14).

**Critères de réussite**
- [ ] `vm-debian/` contient `versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`, `README.md` ; aucune configuration de provider.
- [ ] Toutes les variables ont une description, au moins trois ont une validation ; sorties `vm_id`, `nom`, `ipv4`.
- [ ] `tofu validate` passe ; `terraform-docs --output-check vm-debian` dit que le README est à jour.
- [ ] Le module ignore les changements de `clone` et fait des clones complets.
- [ ] `tofu test` passe (si tu as fait l'étape 6).

**Vérification** : `lab/bin/check 05 13`

<details><summary>Indice 1</summary>

Un objet avec attributs facultatifs (`optional(string, "debian13")`) donne une interface compacte : `reseau = { vnet = "vsandbox" }` suffit pour une VM en DHCP. Un bloc `dynamic "disk"` sur la liste des disques de données, avec `disk.key + 1` pour le numéro d'interface.
</details>

<details><summary>Indice 2</summary>

Avec un provider simulé, une source de données renvoie des valeurs inventées : fixe-les avec `mock_data` pour que `vms[0].vm_id` ait du sens. Pour comparer une liste produite par le module à une liste littérale dans une assertion, attention aux types (`list` contre `tuple`) : `jsonencode` des deux côtés évite la surprise.
</details>

**Pour aller plus loin** (facultatif) : une variante `vm-rocky` (Rocky 10, CPU `x86-64-v3`) : un second module, ou une variable `famille` dans le même ? Argumente (taille de l'interface, risque d'erreur, coût de maintenance).

---

### M05-E14 — Versionner les modules dans `plateforme/tofu-modules`  `LAB` `★★`

> **Ticket PLAT-624** — *De : Karim Benali* — *Copie : Julien Petit*
> Un module qu'on consomme par sa branche `main`, c'est un module qui change sous nos pieds un vendredi soir. Versions sémantiques par semantic-release, comme pour nos autres projets, et consommation **par étiquette**. Julien voudra s'en servir pour ses propres environnements : explique-lui, dans le README du projet, comment choisir une version et quand une version est « majeure ». Et il faut que la CI de `plateforme/infra` puisse télécharger les modules sans qu'on lui donne un jeton personnel.

**Objectifs pédagogiques**
- Publier un module par versions sémantiques (Conventional Commits, semantic-release, étiquettes protégées).
- Consommer un module Git par étiquette, et gérer l'authentification sur le poste et en CI sans secret supplémentaire.
- Savoir quand un changement de module est **majeur** pour ses consommateurs.

**Prérequis** : M05-E13 ; M01-E25 (semantic-release, `ci-templates`).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Gabarits CI : `plateforme/ci-templates`, `ref: v1`, fichiers `templates/qualite.yml` et `templates/release.yml` (M01-E24, M01-E25) ; `.releaserc.json` de référence : M01-E25 ; jeton de projet `bot-release` en variable `GITLAB_TOKEN`.
- Syntaxe d'une source Git pour OpenTofu : `git::https://<hôte>/<chemin>.git//<sous-dossier>?ref=<étiquette>` (<https://opentofu.org/docs/language/modules/sources/>).
- Sur `adm01`, Git peut réécrire une URL HTTPS en URL SSH (`url.<base>.insteadOf`). En CI, le jeton du job (`CI_JOB_TOKEN`) peut lire un autre projet **si** ce projet l'autorise (*Settings › CI/CD › Job token permissions*, liste d'autorisation).
- VM d'essai : 2054 `m05-module`, `vsandbox`, DHCP, **détruite en fin d'exercice**.

**Travail demandé**
1. Configure `plateforme/tofu-modules` pour publier des versions : `.releaserc.json`, `.gitlab-ci.yml` (gabarits), étiquettes `v*` protégées, variable `GITLAB_TOKEN`. Publie la première version (quel type de commit déclenche `v1.0.0` ?).
2. Sur `adm01`, rends la source HTTPS utilisable sans jeton (SSH). Dans `envs/lab-m05`, ajoute une VM d'essai **par le module**, à l'étiquette publiée. `tofu init` : où OpenTofu a-t-il rangé le module ? Plan, MR, apply.
3. Fais évoluer le module par une MR `feat(vm-debian): …` (par exemple une sortie `fqdn`). Constate la nouvelle version. Dans `envs/lab-m05`, que se passe-t-il au `tofu plan` si tu changes `?ref=` **sans** relancer `tofu init` ? Puis passe à la nouvelle version proprement.
4. Écris dans le README du projet : comment consommer, comment choisir une version, et une règle « est **majeur** tout changement qui… » avec au moins trois exemples concrets tirés de ton module (renommage d'une variable, d'une ressource interne, nouvel attribut à remplacement forcé…).
5. Ajoute `plateforme/infra` à la liste d'autorisation des jetons de job de `plateforme/tofu-modules`. Écris (sans l'activer : la CI d'infra n'a pas encore OpenTofu, E26) l'extrait de `.gitlab-ci.yml` qui donne aux jobs d'infra l'accès aux modules par `CI_JOB_TOKEN` **sans modifier** la configuration Git de l'utilisateur `gitlab-runner`. Pourquoi est-ce important sur un exécuteur `shell` ?
6. Retire la VM d'essai du code, applique (destruction relue au plan).

**Critères de réussite**
- [ ] `plateforme/tofu-modules` : `main` protégée, étiquettes `v*` protégées, au moins deux versions `vX.Y.Z` avec leurs notes de version.
- [ ] Toutes les sources de modules de `plateforme/infra` pointent une étiquette `vX.Y.Z` existante, jamais une branche.
- [ ] `plateforme/infra` figure dans la liste d'autorisation des jetons de job de `plateforme/tofu-modules`.
- [ ] La VM 2054 `m05-module` a été créée par le module puis détruite.

**Vérification** : `lab/bin/check 05 14`

<details><summary>Indice 1</summary>

`tofu init` télécharge les modules dans `.terraform/modules/` et les note dans `.terraform/modules/modules.json`. `tofu init -upgrade` relit les sources. Les étiquettes protégées se règlent dans *Settings › Repository › Protected tags*.
</details>

<details><summary>Indice 2</summary>

Git lit sa configuration aussi dans des variables d'environnement : `GIT_CONFIG_COUNT`, `GIT_CONFIG_KEY_<n>`, `GIT_CONFIG_VALUE_<n>` (Git ≥ 2.31, `man git-config`). Elles ne vivent que le temps du processus.
</details>

**Pour aller plus loin** (facultatif) : le registre de modules de GitLab (*Terraform Module Registry*) accepte aussi les modules OpenTofu. Compare : contrainte de version `~> 1.1` possible (registre) contre `?ref=` exact (Git). Renovate (module 13) saura proposer les montées de version dans les deux cas.

---

### M05-E15 — Environnements : workspaces ou répertoires ?  `LAB` `★★`

> **Ticket DEV-625** — *De : Julien Petit* — *Copie : Karim Benali*
> Pour la recette de MédiAgenda, il me faut deux VMs à moi : une pour l'API, une pour la base, que je puisse détruire et recréer sans toucher à `lab-m05`. Karim me parle de « workspaces », Lucas a lu sur un blog qu'il ne fallait jamais s'en servir. Tranchez, et donnez-moi un environnement.

**Objectifs pédagogiques**
- Pratiquer les espaces de travail (workspaces) d'OpenTofu et savoir où ils rangent leurs états.
- Comparer espaces de travail et répertoires par environnement : isolation, accès, versions, rayon d'impact, lisibilité.
- Créer un environnement par répertoire qui réutilise le module versionné.

**Prérequis** : M05-E14.
**Durée indicative** : 2 h 30.

**Contexte technique**
- Essai des espaces de travail : brouillon `~/m05/e15/espaces/` (hors dépôt), backend sur `tofu-state`, clé `essais/e15/terraform.tfstate` ; espaces `recette` et `dev` ; VMs 2055 et 2056 (`vsandbox`, DHCP), détruites à la fin de l'essai.
- Environnement retenu : `envs/recette-m05/` dans `plateforme/infra`, clé `envs/recette-m05/terraform.tfstate` ; VMs **2055** `m05-rec-api` et **2056** `m05-rec-bdd` (2 vCPU, 2 Go ; la base a un disque de données de 10 Go sur `local-nvme`), étiquettes `env-m05` et `recette`, créées par le module `vm-debian` à une étiquette publiée. Elles restent en place jusqu'à la fin du module.

**Travail demandé**
1. Dans le brouillon, écris une configuration qui crée **une** VM par le module, dont le VMID et le nom dépendent de `terraform.workspace`. Crée les espaces `recette` et `dev`, applique dans chacun. Où sont les états dans le compartiment (`aws s3 ls --recursive s3://tofu-state/`) ? Que se passe-t-il dans l'espace `default` ?
2. Fais l'expérience qui fâche : dans l'espace `dev`, change une valeur et lance `tofu plan` en croyant être dans `recette`. Comment t'en serais-tu rendu compte ? Qu'est-ce qui l'aurait empêché ?
3. Détruis les deux VMs, supprime les espaces (`tofu workspace delete`), vérifie qu'il ne reste aucun état vivant sous `env:/`.
4. Compare les deux approches dans un tableau (au moins six critères : isolation des états et des verrous, droits d'accès différents par environnement, versions de providers et de modules différentes, lisibilité d'une MR, risque d'erreur humaine, duplication du code). Écris la décision de l'équipe dans `docs/environnements.md` de `plateforme/infra` : quand utiliser l'un, quand l'autre.
5. Crée `envs/recette-m05/` selon la décision : MR, plan relu, apply. Les deux VMs ne doivent apparaître que dans l'état de la recette.

**Critères de réussite**
- [ ] Le compartiment garde la trace de l'essai (versions sous `env:/`), mais aucun état de workspace n'est plus en vigueur.
- [ ] `envs/recette-m05/` a son backend (clé dédiée, verrou), utilise `vm-debian` par étiquette, sans `terraform.workspace`.
- [ ] VMs 2055 `m05-rec-api` et 2056 `m05-rec-bdd` existent, dans l'état de la recette et dans aucun autre.
- [ ] `tofu plan` est vide dans `envs/recette-m05/` et dans `envs/lab-m05/`.
- [ ] `docs/environnements.md` explique la décision.

**Vérification** : `lab/bin/check 05 15`

<details><summary>Indice 1</summary>

Avec le backend `s3`, l'état d'un espace autre que `default` est rangé sous un préfixe réglable (option `workspace_key_prefix`, valeur par défaut dans la documentation du backend). `tofu workspace show` dit où tu es ; ton invite de shell ne le dit pas.
</details>

<details><summary>Indice 2</summary>

La documentation d'OpenTofu elle-même prévient que les espaces de travail ne conviennent pas quand les environnements demandent des identifiants ou des contrôles d'accès différents : relis la page « Workspaces » avant d'écrire le tableau.
</details>

**Pour aller plus loin** (facultatif) : la duplication entre `envs/lab-m05/` et `envs/recette-m05/` (backend, provider, versions) est réelle : compte les lignes identiques. C'est exactement ce que Terragrunt supprime en M05-E24.

---

### M05-E16 — Importer le socle existant sans le recréer  `LAB` `★★★`

> **Ticket PLAT-626** — *De : Claire Morel* — *Copie : Karim Benali, Nadia Roussel*
> `s3-01` est dans le code ; les autres machines du socle, non. Tant que `adm01`, `dns01`, `git01` et `runner01` ne sont pas dans `plateforme/infra`, je ne peux pas dire à l'auditeur que l'infrastructure est déclarée. Condition absolue : **aucune** de ces machines n'est arrêtée, modifiée ou recréée. Le jour où l'import est appliqué, le plan est vide, ou on ne l'applique pas. Pour `gw01`, je veux ton avis argumenté.

**Objectifs pédagogiques**
- Importer des ressources existantes avec des blocs `import` (au plan, relus en MR), y compris en boucle.
- Générer une configuration de départ (`-generate-config-out`) puis la réécrire jusqu'au plan vide.
- Repérer les attributs à remplacement forcé qui transformeraient un import en recréation, et justifier chaque `ignore_changes`.
- Décider ce qui ne doit **pas** être géré par OpenTofu.

**Prérequis** : M05-E10, M05-E11, M05-E13 ; M02-E05 (étiquettes du socle).
**Durée indicative** : 4 h.

**Contexte technique**
- VMs à importer dans l'état `socle` : 1001 `adm01`, 1002 `dns01`, 1004 `git01`, 1007 `runner01`. Identifiant d'import du provider : `<nœud>/<VMID>`.
- Elles ont été construites à la main (M00, M01) en clonant le template 9000 : elles en ont hérité des réglages (dont un *vendor-data* cloud-init, M00-E11) qu'aucune VM créée par OpenTofu n'a.
- Documentation : <https://opentofu.org/docs/language/import/> et `tofu plan -help` (option `-generate-config-out`).
- `gw01` (1000) : deux cartes (`vmbr0` et `vmbr1` en trunk, hors SDN), installé depuis l'ISO, sans cloud-init (M00-E10).

> ⚠️ **Attention** : un import ne modifie rien par lui-même, mais l'**apply** qui le porte applique aussi tout le reste du plan. Si une ligne `~`, `-` ou `-/+` concerne une VM importée, **n'applique pas** : corrige le code. Avant l'apply : `ms-snapshot --prefix avant-import 1001 1002 1004 1007` (M02) et copie de l'état socle (`aws s3 cp`). Retour arrière : un import raté se retire de l'état (`tofu state rm <adresse>`), sans toucher à la VM.

**Travail demandé**
1. Relève l'existant : `qm config` des quatre VMs, rangé dans `~/m05/e16/`. Quelles différences vois-tu avec `s3-01` ?
2. Dans une branche, écris **seulement** quatre blocs `import` (pas de ressource), puis `tofu plan -generate-config-out=genere.tf`. Lis le fichier produit : que pourrais-tu commiter tel quel ? Que faut-il absolument en garder ?
3. Réécris la configuration proprement (une ressource par VM ou une ressource avec `for_each` et un bloc `import` en boucle : choisis et justifie), sans `genere.tf`. Itère sur `tofu plan` jusqu'au résultat attendu : `4 to import, 0 to add, 0 to change, 0 to destroy`. Pour chaque écart rencontré, note dans ton journal sa cause et ta décision : recopier la valeur réelle dans le code, ou l'ignorer (`ignore_changes`) ? Une règle : on ne change **jamais** la VM pour faire plaisir au code.
4. Protège ces VMs : aucun plan ne doit pouvoir les détruire. Prouve-le avec `tofu plan -destroy` (rien n'est appliqué par cette commande : lis pourquoi).
5. `gw01` : importé, laissé dehors, ou suivi en lecture seule ? Écris ta décision (ADR court dans `plateforme/medisphere`, numéro ADR-0051) et mets-la en œuvre. Que peut faire un bloc `check` d'OpenTofu ici ?
6. MR (avec le plan dans la description), relecture par Karim, fusion, apply. Puis `tofu plan` doit être vide. Supprime les instantanés.

**Critères de réussite**
- [ ] Les VMs 1001, 1002, 1004 et 1007 sont dans l'état socle ; 1000 n'y est pas ; aucune n'a été arrêtée.
- [ ] `tofu plan` est vide dans `socle/`.
- [ ] `tofu plan -destroy` dans `socle/` est refusé.
- [ ] Aucun fichier de configuration générée n'est commité ; chaque `ignore_changes` est commenté.
- [ ] La décision sur `gw01` est écrite (ADR-0051).

**Vérification** : `lab/bin/check 05 16`

<details><summary>Indice 1</summary>

Dans un plan d'import, un attribut suivi de `# forces replacement` transforme l'import en « importer puis détruire et recréer ». Dans le schéma du provider, certains attributs de `initialization` sont dans ce cas : compare ce que `qm config` montre en `cicustom` avec ce que ta configuration déclare.
</details>

<details><summary>Indice 2</summary>

Un bloc `import` accepte `for_each` (OpenTofu ≥ 1.7) : `to = proxmox_virtual_environment_vm.socle[each.key]`. La génération de configuration, elle, travaille sur des imports simples : génère d'abord, factorise ensuite.
</details>

<details><summary>Indice 3</summary>

Les clés SSH de cloud-init de ces VMs ont été posées en M00 ; les comptes sont gérés depuis par Ansible (rôle `base`). Réécrire les clés dans le lecteur cloud-init n'apporterait rien et pourrait faire régénérer les clés d'hôte SSH au prochain démarrage (M00-E13). Ce genre d'écart se traite par `ignore_changes`, avec un commentaire.
</details>

**Pour aller plus loin** (facultatif) : `tofu state show` sur une VM importée, comparé au même sur `s3-01` : que sait l'état d'une VM créée par OpenTofu qu'il ne sait pas d'une VM importée ?

---

### M05-E17 — Refactorer sans détruire : `moved` et `removed`  `LAB` `★★★`

> **Ticket CHG-627** — *De : Karim Benali* — *Copie : Julien Petit*
> Le module existe, il est temps que le code s'en serve. Trois changements, aucune VM détruite : `s3-01` passe dans le module ; les trois serveurs d'application de `lab-m05` aussi ; et Julien récupère `m05-essai` (2050) dans sa recette, pour ses tests de charge — elle quitte `lab-m05` sans être détruite. Chaque MR montre un plan sans aucune ligne `-` ni `-/+`, sinon elle n'est pas fusionnée.

**Objectifs pédagogiques**
- Changer l'adresse d'une ressource dans l'état avec un bloc `moved`, y compris vers un module et pour des instances `for_each`.
- Sortir une ressource de la gestion d'OpenTofu sans la détruire (`removed` avec `destroy = false`), puis la faire entrer dans un autre état.
- Savoir combien de temps garder un bloc `moved`, et pourquoi `tofu state mv` n'est plus la méthode de choix.

**Prérequis** : M05-E13 à M05-E16.
**Durée indicative** : 3 h.

**Contexte technique**
- Adresses actuelles : `proxmox_virtual_environment_vm.s3_01` (socle) ; `proxmox_virtual_environment_vm.app["app01"]`, `["app02"]`, `["app03"]` et `proxmox_virtual_environment_vm.essai` (lab-m05, palier 1).
- Le module doit reproduire **exactement** les VMs existantes (disques, options), sinon le plan propose de les modifier, voire de les recréer.
- Documentation : <https://opentofu.org/docs/language/modules/develop/refactoring/>, <https://opentofu.org/docs/language/resources/syntax/#removing-resources>.

> ⚠️ **Attention** : copie de l'état concerné avant chaque apply (`aws s3 cp s3://tofu-state/<clé> ~/m05/e17/`). Une adresse mal écrite dans un `moved` ne casse rien au plan, mais se voit : la VM apparaît en `+` (nouvelle adresse) **et** en `-` (ancienne). Ne fusionne jamais un plan qui montre les deux.

**Travail demandé**
1. **`s3-01` dans le module.** Remplace la ressource par un appel de `vm-debian` (version publiée). Lance un plan **sans** bloc `moved` : que propose OpenTofu ? Arrête-toi là. Ajoute le bloc `moved`, relance : lis la ligne `has moved to`. Reste-t-il des modifications sur place ? Lesquelles acceptes-tu, lesquelles corriges-tu dans l'appel ? Que deviennent les garde-fous de E10 ?
2. **Serveurs d'application dans le module.** Même démarche pour les trois instances `for_each`. Un bloc `moved` accepte-t-il `for_each` ? Le plan final ne doit contenir que des « has moved to » et, au plus, des modifications sur place que tu sais justifier.
3. **`m05-essai` change d'état.** Dans `lab-m05`, retire la ressource et ajoute un bloc `removed` qui ne détruit pas. Plan : que signifie « will be removed from the OpenTofu state but will not be destroyed » ? Applique. **Ensuite seulement**, dans `envs/recette-m05`, importe la VM 2050 avec le module (même méthode qu'en E16). Pourquoi cet ordre, et jamais l'inverse ?
4. Combien de temps gardes-tu les blocs `moved` et `removed` dans le code ? Écris la règle de l'équipe dans `CONTRIBUTING.md` (pense aux copies de travail des collègues, aux branches ouvertes, à la restauration d'un ancien état en E29).
5. Comparaison par écrit : ce que tu viens de faire avec des blocs, comment l'aurait-on fait avec `tofu state mv` / `tofu state rm` / `tofu import` ? Qu'est-ce que la méthode par blocs apporte en équipe ?

**Critères de réussite**
- [ ] État socle : `module.s3_01…` et plus `proxmox_virtual_environment_vm.s3_01` ; `s3-01` n'a pas été recréée (son historique d'état est intact, `protection: 1`).
- [ ] État lab-m05 : `module.app["app01"]…` à `["app03"]` ; la VM 2050 n'y est plus mais existe toujours, dans l'état de recette-m05.
- [ ] Les blocs `moved` (socle) et `removed` (lab-m05) sont dans le code.
- [ ] `tofu plan` vide dans `socle/`, `envs/lab-m05/` et `envs/recette-m05/`.

**Vérification** : `lab/bin/check 05 17`

<details><summary>Indice 1</summary>

L'adresse d'une ressource dans un module : `module.<nom_de_l_appel>.<type>.<nom_dans_le_module>`, et pour un appel avec `for_each` : `module.<nom>["<clé>"].<type>.<nom>`. `tofu state list` donne les adresses exactes de départ.
</details>

<details><summary>Indice 2</summary>

Si le plan veut modifier les disques des serveurs d'application, compare le format, le stockage et l'option `ssd` des disques dans `qm config 2052` avec ce que le module écrit par défaut. Le module doit permettre de les fixer ; s'il ne le permet pas, c'est une évolution du module (nouvelle version, E14).
</details>

**Pour aller plus loin** (facultatif) : un module peut contenir ses propres blocs `moved` (renommage d'une ressource interne entre deux versions) : c'est ce qui permet à une version **mineure** de renommer sans casser les consommateurs. Essaie sur une branche de `tofu-modules`.

---

### M05-E18 — Dépendances et cycle de vie des ressources  `LAB` `★★`

> **Ticket PLAT-628** — *De : Nadia Roussel* — *Copie : Karim Benali*
> Pour les tests de panne, je veux une VM jetable dans `lab-m05` qu'on reconstruit **à neuf** quand on le décide, sur l'image du jour, d'un seul changement de valeur. Et je veux que l'apply **échoue** s'il livre une VM sans adresse, au lieu de me laisser la découvrir à 3 h du matin. Profites-en pour m'expliquer, avec le graphe, dans quel ordre OpenTofu fait les choses.

**Objectifs pédagogiques**
- Lire le graphe de dépendances d'OpenTofu ; distinguer dépendances implicites (références) et explicites (`depends_on`), et connaître le coût de ces dernières.
- Utiliser les méta-arguments de cycle de vie : `replace_triggered_by`, `create_before_destroy`, `ignore_changes`, `prevent_destroy`, `precondition`, `postcondition`.
- Reconstruire une ressource volontairement (`-replace`, déclencheur), et savoir quand c'est impossible sans interruption.

**Prérequis** : M05-E08, M05-E17.
**Durée indicative** : 2 h 30.

**Contexte technique**
- VM jetable : 2054 `m05-jetable` (1 vCPU, 1 Go, `vsandbox`, DHCP), dans `envs/lab-m05`, **ressource directe** (pas le module : un appel de module n'accepte pas de bloc `lifecycle`). Sa « génération » est une date `AAAA-MM-JJ` déclarée dans `terraform.tfvars` (variable `generation_jetable`), reprise dans sa description.
- `terraform_data` : ressource intégrée à OpenTofu, sans infrastructure, qui stocke une valeur dans l'état (<https://opentofu.org/docs/language/resources/terraform-data/>).
- `tofu graph` produit du format DOT ; `dot` (paquet `graphviz`) le dessine.

**Travail demandé**
1. `tofu graph` dans `envs/recette-m05`, dessin en SVG. Retrouve les arêtes qui viennent de **références**. Comment OpenTofu sait-il qu'il peut créer les deux VMs en parallèle ? Mesure un `tofu plan` avec `-parallelism=1` puis la valeur par défaut.
2. Crée `m05-jetable` avec ces garde-fous : une **précondition** qui refuse la création si l'image courante n'est pas une image dorée Debian 13 ; une **postcondition** qui fait échouer l'apply si la VM n'a pas d'adresse dans 10.10.99.0/24 ; une recréation déclenchée par le changement de génération, et **seulement** par lui (pas par une nouvelle image `current`).
3. Change la génération. Lis le plan : quelle ligne dit pourquoi la VM sera remplacée ? Applique. La nouvelle VM a-t-elle été clonée depuis la même image que l'ancienne ?
4. Ajoute `create_before_destroy = true` à la VM, lance un plan après un changement de génération, **n'applique pas**. Que se passerait-il à l'apply ? Retire-le. Dans quel cas ce méta-argument est-il utile avec Proxmox ?
5. Pour comparer, reconstruis la VM sans changer le code (`tofu apply -replace=…`). Quand préférer l'un ou l'autre ?
6. Questions par écrit : un collègue ajoute `depends_on = [module.bdd]` sur une **source de données** utilisée par une autre VM : qu'arrive-t-il aux plans suivants ? (Le plan 5 de M05-E22 le montre.) Pourquoi `prevent_destroy` ne se règle-t-il pas par variable ?

**Critères de réussite**
- [ ] `m05-jetable` (2054) existe dans l'état de `lab-m05`, avec une adresse 10.10.99.x ; sa description porte la génération de `terraform.tfvars`.
- [ ] Le code contient `replace_triggered_by` (vers une ressource `terraform_data`), une précondition et une postcondition, et pas de `depends_on` inutile.
- [ ] `tofu plan` est vide dans `envs/lab-m05`.
- [ ] Ton journal contient le graphe, les mesures de durée et les réponses écrites.

**Vérification** : `lab/bin/check 05 18`

<details><summary>Indice 1</summary>

`replace_triggered_by` n'accepte que des références à des ressources gérées (ou à leurs attributs), pas une variable : il faut un intermédiaire qui change quand la variable change.
</details>

<details><summary>Indice 2</summary>

Une postcondition voit l'objet créé sous le nom `self`. L'attribut qui porte les adresses remontées par l'agent QEMU est une liste de listes (une par interface) : `flatten()` puis un test sur chaque adresse.
</details>

**Pour aller plus loin** (facultatif) : un bloc `check` (hors ressource) avec une source de données ou une requête HTTP (provider `http`) vérifie un état à **chaque** plan sans bloquer l'apply. Que surveillerais-tu ainsi dans `envs/recette-m05` ?

---

### M05-E19 — cloud-init généré et snippets gérés par le code  `LAB` `★★`

> **Ticket PLAT-629** — *De : Karim Benali* — *Copie : Sophie Laurent*
> Les réglages cloud-init de Proxmox (`ciuser`, `sshkeys`, `ipconfig0`) ne suffisent plus : pour la VM jetable de Nadia, je veux des paquets et des fichiers posés dès le premier démarrage, le tout **généré** par OpenTofu et déposé par lui sur `pve01`. Sophie a vu passer « le provider a besoin de SSH vers l'hyperviseur » : pas en root, pas avec la clé de tout le monde, pas avec des droits sur les disques des autres VMs.

**Objectifs pédagogiques**
- Générer un *user-data* cloud-init avec `templatefile()` (ou `yamlencode()`) et le valider avant de l'envoyer.
- Gérer un snippet avec `proxmox_virtual_environment_file`, en sachant pourquoi il passe par SSH et ce que cela exige.
- Donner au provider un accès minimal à `pve01` : compte Linux dédié, `sudo` limité, stockage dédié, droits Proxmox sur ce seul stockage.
- Éviter le piège du fichier modifié sous une VM déjà démarrée.

**Prérequis** : M05-E18 ; M00-E11 (snippets cloud-init) ; M03-E04 (*vendor-data*).
**Durée indicative** : 3 h.

**Contexte technique**
- Proxmox n'accepte par son API que l'envoi d'ISO, de modèles de conteneurs et d'images à importer : le provider écrit les snippets **par SSH** (commande `tee`, avec `sudo` si le compte n'est pas root). Lis la section SSH de la documentation du provider (<https://search.opentofu.org/provider/bpg/proxmox/latest>, page d'accueil).
- Le provider lit le chemin d'un stockage par `GET /storage/<id>`, qui exige `Datastore.Allocate` sur ce stockage ; une VM ne peut référencer un snippet qu'avec ce même privilège. Sur `hdd-bulk`, ce privilège permettrait de supprimer **n'importe quel** volume du stockage (ISO, sauvegardes locales, disque de données de `s3-01`).
- À créer : stockage de type répertoire **`tofu-snippets`** (`/mnt/hdd-bulk/tofu-snippets`, contenu `snippets` seulement) ; compte Linux **`wb-tofu`** sur `pve01`, clé de `admin@adm01` limitée à 10.10.10.10 ; règles `sudo` dans `/etc/sudoers.d/wb-tofu` ; rôle Proxmox `WBTofuSnippets` sur `/storage/tofu-snippets` (utilisateur et jeton).
- Le snippet remplace `user_account` de la VM (les deux s'excluent) : c'est lui qui crée le compte `admin` et ses clés. Le réseau reste généré par Proxmox.
- Contenu attendu du *user-data* de `m05-jetable` : compte `admin` (clés de `cles_ssh_admin`, sudo sans mot de passe, mot de passe verrouillé), paquets `curl` et `jq`, fichier `/etc/medisphere/generation` contenant `generation=<génération>`.

> ⚠️ **Attention** : tu modifies `pve01` (stockage, compte, sudoers, ACL). Garde une session root ouverte pendant toute l'étape. Un fichier sudoers invalide peut casser `sudo` : valide-le (`visudo -cf`) **avant** de l'installer. Retour arrière : `pvesm remove tofu-snippets` (le dossier reste), `userdel -r wb-tofu`, suppression de `/etc/sudoers.d/wb-tofu` et des ACL (`pveum acl delete`).

**Travail demandé**
1. Lis dans la documentation du provider quelles opérations exigent SSH. Dans ton journal : que fait le provider en SSH, sous quel compte, avec quelle commande ? Pourquoi une règle `sudo` sur `qm` ou `pvesm` entiers serait-elle une faute ?
2. Prépare `pve01` (contexte). Vérifie avec `pveum user token permissions` que le jeton a `Datastore.Allocate` sur `tofu-snippets` et **pas** sur `hdd-bulk`. Teste depuis `adm01` : `ssh -o ControlPath=none wb-tofu@<IP-PVE01> sudo -n /usr/sbin/pvesm apiinfo`.
3. Ajoute le bloc `ssh` au provider de `envs/lab-m05` : compte `wb-tofu`, agent SSH, adresse de `pve01` donnée explicitement. Aucune clé privée dans le code. Pourquoi l'état `socle` ne doit-il **pas** gérer de snippets (pense à la CI, E26) ?
4. Écris le gabarit du *user-data* et la ressource `proxmox_virtual_environment_file`. Avant tout apply, valide le rendu : `tofu console` (ou une sortie), puis `cloud-init schema -c <fichier>` sur `adm01`.
5. Fais utiliser le snippet par `m05-jetable`. Lis le plan : pourquoi la VM est-elle **remplacée** ?
6. Le piège : change seulement le contenu du snippet (un paquet de plus), en gardant le même nom de fichier. Plan : que devient la VM ? Que verrait-on dans la VM ? Corrige pour qu'un nouveau contenu entraîne une nouvelle VM, et que l'ancien fichier ne disparaisse pas avant que la nouvelle VM existe.
7. Vérifie dans la VM (`qm guest exec 2054 -- cat /etc/medisphere/generation`, `cloud-init status`) que le snippet a bien été appliqué.

**Critères de réussite**
- [ ] `pve01` : stockage `tofu-snippets` (snippets seulement), compte `wb-tofu` sans mot de passe, `sudo` limité à `pvesm apiinfo` et à `tee` dans le dossier des snippets ; le jeton a `Datastore.Allocate` sur `tofu-snippets`, pas sur `hdd-bulk`.
- [ ] `m05-jetable` a `cicustom: user=tofu-snippets:snippets/…` ; le fichier commence par `#cloud-config` ; dans la VM, `/etc/medisphere/generation` existe et `cloud-init status` dit `done`.
- [ ] Le snippet est une ressource de l'état de `lab-m05` ; `socle/` n'en gère aucun ; aucune clé privée ni mot de passe dans le code.
- [ ] `tofu plan` est vide dans `envs/lab-m05`.

**Vérification** : `lab/bin/check 05 19`

<details><summary>Indice 1</summary>

Les règles `sudo` recommandées par la documentation du provider sont très précises (chemin absolu de la commande, motif sur le nom du fichier). Adapte le chemin au stockage dédié : `<chemin du stockage>/snippets/<nom>`.
</details>

<details><summary>Indice 2</summary>

Un attribut à remplacement forcé de la VM (l'identifiant du fichier) ne change que si le **nom** du fichier change. Mettre une empreinte du contenu dans le nom (`sha256()`) relie les deux. Pour l'ordre de création et de destruction du fichier, regarde `create_before_destroy`.
</details>

**Pour aller plus loin** (facultatif) : déposer le même snippet en *vendor-data* plutôt qu'en *user-data* : qu'est-ce que cela change pour les comptes créés par Proxmox ? (Relis M03-E04.)

---

### M05-E20 — Qualité du code : fmt, validate, tflint, terraform-docs  `LAB` `★★`

> **Ticket PLAT-630** — *De : Karim Benali*
> Dans la dernière MR de Lucas, j'ai passé vingt minutes sur de l'indentation et une variable jamais utilisée. Une machine doit le voir avant moi. `tofu fmt`, `tofu validate`, tflint et la documentation générée, en pre-commit dans `infra` et dans `tofu-modules`. En CI aussi, dès que `runner01` aura les outils (E26) ; d'ici là, que la CI ne bloque pas pour ça.

**Objectifs pédagogiques**
- Outiller un dépôt IaC : formatage, validation de chaque configuration, analyse statique (tflint), documentation générée et vérifiée.
- Écrire des hooks pre-commit locaux fiables, qui ne modifient ni l'état ni la copie de travail.
- Choisir et justifier des règles de tflint.

**Prérequis** : M05-E13 à M05-E19 ; M01-E15 (pre-commit).
**Durée indicative** : 2 h 30.

**Contexte technique**
- tflint **0.64** (binaire de la page des versions <https://github.com/terraform-linters/tflint/releases>, somme vérifiée, `/usr/local/bin`), jeu de règles `terraform` intégré (documentation des règles : <https://github.com/terraform-linters/tflint-ruleset-terraform/tree/main/docs/rules>). terraform-docs 0.24 (installé en E13).
- Fichiers : `.tflint.hcl` à la racine de chaque projet ; `.terraform-docs.yml` à la racine de `infra` ; hooks dans `.pre-commit-config.yaml` (configuration de référence de M01-E15, déjà présente) ; scripts `outils/tofu-valider.sh` et `outils/docs-verifier.sh`.
- `tofu validate` exige un `tofu init` : la validation ne doit utiliser ni S3 ni Proxmox, ni toucher au `.terraform/` de la copie de travail (variable `TF_DATA_DIR`), ni réécrire un `.terraform.lock.hcl`.
- `pre-commit` saute les hooks listés dans la variable `SKIP`. Valeur à mettre dans le `.gitlab-ci.yml` des deux projets jusqu'à E26 : `tofu-fmt,tofu-validate,tflint,terraform-docs` (identifiants de tes hooks).

**Travail demandé**
1. Installe tflint, vérifie la somme. Lance `tflint --recursive` à nu sur `infra` : que trouve-t-il ?
2. Écris `.tflint.hcl` : préréglage `recommended`, plus les règles de l'équipe (nommage `snake_case`, variables et sorties documentées et typées, versions contraintes, modules **épinglés par étiquette**, déclarations inutilisées). Pour `tofu-modules`, ajoute la structure standard d'un module. Pour chaque règle activée ou désactivée, une ligne de justification en commentaire. Corrige le code jusqu'à zéro avertissement.
3. Écris `outils/tofu-valider.sh` (toutes les configurations, dossier de travail jetable, aucune réécriture du fichier de verrouillage) et `outils/docs-verifier.sh` (`terraform-docs --output-check` sur chaque README à marqueurs). Ajoute un README documenté à `socle/`.
4. Ajoute les hooks à `.pre-commit-config.yaml` des deux projets (hooks locaux appelant les outils du poste : pourquoi ce choix plutôt qu'un dépôt de hooks tiers ?). Fais un commit volontairement mal formaté : le hook doit l'arrêter.
5. CI : ajoute `SKIP` aux deux `.gitlab-ci.yml`, avec un commentaire qui dit quand il disparaîtra. Les pipelines de `main` doivent être verts.

**Critères de réussite**
- [ ] tflint 0.64 et terraform-docs 0.24 sur `adm01`.
- [ ] `tofu fmt -check -recursive` et `tflint --recursive` passent sans avertissement dans `infra` et `tofu-modules`.
- [ ] Les hooks `tofu fmt`, `validate`, `tflint` et `terraform-docs` sont dans les deux `.pre-commit-config.yaml`, installés dans tes copies de travail ; la documentation générée est à jour.
- [ ] Les derniers pipelines de `main` des deux projets sont verts.

**Vérification** : `lab/bin/check 05 20`

<details><summary>Indice 1</summary>

`tflint --recursive` analyse chaque dossier contenant des `.tf` comme un module à part, avec le fichier de configuration indiqué par `--config` (chemin absolu de préférence). L'option `call_module_type` de `.tflint.hcl` dit s'il faut aussi inspecter les appels de modules.
</details>

<details><summary>Indice 2</summary>

`tofu init` écrit `.terraform.lock.hcl` dans le dossier **courant**, quel que soit `TF_DATA_DIR`. Dans un module réutilisable qui n'en a pas, ton script doit le retirer après usage ; dans une configuration racine qui en a un, `-lockfile=readonly`.
</details>

**Pour aller plus loin** (facultatif) : un hook `tofu test` sur `tofu-modules`, à l'étape `pre-push` seulement (il télécharge le provider). Que faut-il changer dans `default_install_hook_types` ?

---

### M05-E21 — Revue de la MR OpenTofu d'un stagiaire  `REV` `★★`

> **Ticket PLAT-631** — *De : Karim Benali* — *Copie : Lucas Martin*
> Lucas a ouvert sa première MR sur `plateforme/infra` : la supervision de MédiAgenda (DEV-641). Je pars deux jours, c'est toi qui relis. Fais une vraie revue : commentaires classés par gravité, chacun avec le risque concret et la correction attendue. Et dis-moi s'il y a quelque chose à faire **avant même** de répondre à Lucas.

**Objectifs pédagogiques**
- Relire une MR d'infrastructure : sécurité, état, versions, conformité au PLAN, cycle de vie, intégration avec le reste de la chaîne.
- Classer les défauts par gravité et distinguer ce qui bloque la fusion de ce qui peut suivre.
- Reconnaître un incident caché dans une revue et le traiter en premier.

**Prérequis** : M05-E10 à M05-E20.
**Durée indicative** : 2 h.

**Contexte technique**
- La MR est fabriquée en local par `ressources/M05-E21/fabriquer-mr.sh` (dépôt `~/m05/e21/infra-mr`, branche `lucas/supervision`, description dans `DESCRIPTION-MR.md`). Rien ne doit être appliqué ni poussé.
- Lis-la comme sur la forge : `git log --stat main..lucas/supervision`, `git diff main...lucas/supervision`.

**Travail demandé**
1. Fabrique le dépôt et lis toute la MR, description comprise.
2. Écris ta revue dans `~/m05/e21/revue.md` : pour chaque défaut, le fichier et la ligne, la gravité (**bloquant**, **majeur**, **mineur**), le risque concret (« si on fusionne, il se passe… »), la correction attendue.
3. En tête de la revue, la section « Avant de répondre à Lucas » : ce qui ne peut pas attendre la correction de la MR, et dans quel ordre.
4. Termine par une réponse à Lucas : bienveillante, pédagogique, avec deux ou trois liens vers nos conventions ou la documentation.

**Critères de réussite**
- [ ] Au moins **douze** défauts distincts relevés, dont tous ceux que le corrigé classe « bloquant ».
- [ ] La section « Avant de répondre » traite le secret exposé et l'état commité.
- [ ] Chaque commentaire dit le risque et la correction, pas seulement « c'est mal ».

Auto-évaluation avec la grille du corrigé (pas de vérification automatique).

<details><summary>Indice 1</summary>

Lis chaque fichier en te demandant : qu'est-ce que cette ligne ferait au **premier** plan, puis au plan de la semaine prochaine (nouvelle image `current`, nouvelle version du provider) ? Puis compare avec les conventions de l'introduction, les VMID et adresses du PLAN, et l'inventaire Ansible.
</details>

<details><summary>Indice 2</summary>

Copier un dossier d'environnement copie aussi son bloc `backend`. Que contient l'état désigné par cette clé, et que proposerait un plan lancé dans le nouveau dossier ?
</details>

**Pour aller plus loin** (facultatif) : lesquels de ces défauts tes outils de E20 auraient-ils arrêtés ? Lesquels arrêteront Checkov et Trivy (E25) ? Ce qui reste est le vrai travail du relecteur.

---

### M05-E22 — Lire un plan comme un relecteur  `Q` `★★`

> **Ticket PLAT-632** — *De : Nadia Roussel*
> Quand un plan arrive dans une MR à 18 h, j'ai besoin de savoir en deux minutes si on peut l'appliquer. J'ai gardé six plans de la semaine. Dis-moi, pour chacun, ce qu'il va **vraiment** faire, si on l'applique, et sinon ce qu'on fait à la place.

**Objectifs pédagogiques**
- Lire un plan OpenTofu : symboles, raisons de remplacement, valeurs connues après l'apply, dérive détectée, lectures différées.
- Lire la version JSON d'un plan et l'exploiter dans un contrôle automatique.
- Décider : appliquer, corriger, ou enquêter.

**Prérequis** : M05-E16 à M05-E19.
**Durée indicative** : 1 h 30.

**Contexte technique** : les plans sont dans `ressources/M05-E22/` (contexte de chacun dans `LISEZMOI.md`).

**Questions**
1. **Plan 1.** Que voulait faire Lucas, et qu'est-ce qui l'a empêché ? Que se serait-il passé sans ce garde-fou, VM par VM ? Comment Lucas doit-il s'y prendre pour changer le *vendor-data* des VMs importées ? (Deux options au moins.)
2. **Plan 2.** Peut-on l'appliquer ? Qu'est-ce que l'apply va réellement changer sur `pve01` ? Pourquoi ne voit-on ni `+` ni `-` ?
3. **Plan 3.** Personne n'a rien fusionné : pourquoi ce plan du lundi veut-il remplacer `m05-lucas-test` ? Qu'est-ce qui manque dans son code ? Si le pipeline de dérive (E28) appliquait automatiquement, que perdrait-on ?
4. **Plan 4.** Raconte ce qui s'est passé cette nuit. Que fera l'apply sur `m05-app02` (la VM va-t-elle redémarrer ?) et sur `m05-app03` ? Que conseilles-tu à Nadia : appliquer, ou modifier d'abord le code ? Selon quoi ?
5. **Plan 5.** Pourquoi la source de données est-elle lue « during apply » ? Pourquoi la description de `m05-rec-api` devient-elle inconnue alors que personne n'y a touché ? Que se passerait-il si la valeur inconnue alimentait un attribut à remplacement forcé ? Quelle ligne du code de Julien faut-il changer ?
6. **Plan 6.** Pour chaque entrée du JSON, traduis en symbole et en phrase. Lesquelles bloquent la fusion ? Écris le filtre `jq` qu'un job de CI utiliserait pour échouer si un plan **détruit** quoi que ce soit dans `socle/` (y compris par remplacement), et dis ce qu'il laisserait passer à tort ou bloquerait à tort.
7. **Synthèse.** Classe ces symboles et mentions du plus anodin au plus dangereux pour une VM du socle, en une ligne chacun : `~`, `+`, `-`, `-/+`, `+/-`, `<=`, `# forces replacement`, `(known after apply)`, `has moved to`, `will be removed from the OpenTofu state but will not be destroyed`, `Objects have changed outside of OpenTofu`.

Auto-évaluation avec le corrigé (pas de vérification automatique).

---

### M05-E23 — De OpenTofu à Ansible : inventaire et configuration après création  `LAB` `★★`

> **Ticket PLAT-633** — *De : Nadia Roussel* — *Copie : Julien Petit, Karim Benali*
> OpenTofu crée les VMs, Ansible les configure, très bien. Mais entre les deux, aujourd'hui, il y a toi qui copies une adresse IP d'une fenêtre à l'autre. Je veux qu'une VM créée par `envs/lab-m05` soit vue par Ansible **sans rien saisir**, et qu'un seul enchaînement documenté la configure. Lucas propose un `local-exec` qui lance `ansible-playbook` : dis-moi pourquoi ou pourquoi pas.

**Objectifs pédagogiques**
- Relier les deux outils par un contrat simple : les étiquettes Proxmox et l'inventaire dynamique, plutôt que des adresses recopiées.
- Obtenir l'adresse d'une VM en DHCP par l'agent QEMU, dans l'inventaire dynamique.
- Enchaîner création et configuration sans `provisioner`, et en garder chaque étape rejouable seule.

**Prérequis** : M05-E19 ; M04-E13 (inventaire dynamique), M04-E10 (rôle `base`).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Inventaire dynamique de M04 (`inventories/lab/proxmox.yml`) : il ne retient que `socle` et `env-m04`, et prend l'adresse dans `ipconfig0` (absente des VMs en DHCP). Le plugin `community.proxmox.proxmox` lit aussi les interfaces remontées par l'agent QEMU quand l'agent est activé (fait `proxmox_agent_interfaces`) ; le jeton `wb-ansible` doit pouvoir les lire (`VM.GuestAgent.Audit` sur PVE 9).
- Groupe Ansible issu de l'étiquette `env-m05` : `env_m05`. Playbook à écrire : `playbooks/env-m05.yml` (rôle `base`). Script d'enchaînement : `outils/configurer-env.sh <env>` dans `plateforme/infra`, sortie OpenTofu `hotes_ansible` dans `envs/lab-m05`.
- VMs visées : celles de `envs/lab-m05` (`m05-app01` à `m05-app03`, `m05-jetable`).
- Règle M04 : on ne désactive jamais la vérification des clés d'hôte.

**Travail demandé**
1. Lance `ansible-inventory --graph` : où sont les VMs de `lab-m05` ? Pourquoi ? Élargis le filtre de l'inventaire aux VMs d'environnement de tous les modules, **sans** y faire entrer les instances Molecule ni les templates. Combien d'hôtes dans `socle` après ta modification (le garde-fou de `site.yml` doit rester vrai) ?
2. Calcule `ansible_host` pour les VMs en DHCP à partir des interfaces de l'agent (première adresse IPv4 du lab, hors boucle locale), en gardant `ipconfig0` pour le socle. Vérifie avec `ansible-inventory --host m05-jetable`.
3. Clés d'hôte : ces VMs changent d'adresse et de clé à chaque génération. Que proposes-tu, dans le respect de la règle M04 ? (Inspire-toi de ce que fait Molecule, M04-E24.)
4. Écris `playbooks/env-m05.yml` : attendre que la VM soit joignable **et** que cloud-init ait fini (pourquoi ?), puis le rôle `base`.
5. Ajoute la sortie `hotes_ansible` à `envs/lab-m05` et écris `outils/configurer-env.sh` : lit les hôtes dans l'état, vérifie qu'Ansible les voit, lance le playbook limité à ces hôtes. Enchaîne : génération nouvelle de `m05-jetable` (E18), apply, script.
6. Réponds à Lucas par écrit : pourquoi pas de `provisioner "local-exec"` ? (Au moins trois raisons : rejouabilité, état « contaminé » en cas d'échec, secrets et journaux, dépendance au poste, ordre de création.) Dans quel cas un `provisioner` reste-t-il acceptable ?

**Critères de réussite**
- [ ] `ansible-inventory --list` : `m05-jetable` dans le groupe `env_m05`, avec une adresse 10.10.99.x ; `socle` contient toujours exactement les six hôtes du socle, sans VM d'environnement.
- [ ] Les VMs d'environnement utilisent un `known_hosts` dédié avec `accept-new`, jamais `StrictHostKeyChecking=no`.
- [ ] Dans `m05-jetable`, le rôle `base` a été appliqué (fuseau, chrony vers 10.10.99.1, journal persistant).
- [ ] `envs/lab-m05` a une sortie `hotes_ansible` ; `outils/configurer-env.sh` existe ; aucun `provisioner` dans `plateforme/infra`.

**Vérification** : `lab/bin/check 05 23`

<details><summary>Indice 1</summary>

Dans un filtre ou un `compose` de l'inventaire, `proxmox_tags_parsed` est une liste : `select('match', '^env-m[0-9]{2}$')` y garde ce qui t'intéresse. Attention aux barres obliques inverses dans une expression régulière écrite dans du YAML puis évaluée par Jinja : une classe de caractères (`[.]`) évite de compter les échappements.
</details>

<details><summary>Indice 2</summary>

`ansible.builtin.wait_for_connection` attend SSH et Python ; `cloud-init status --wait` attend la fin de cloud-init (codes de retour : 0, 1, 2, voir M04-E24).
</details>

**Pour aller plus loin** (facultatif) : la collection `cloud.terraform` propose un inventaire lu dans l'état OpenTofu lui-même. Avantages, inconvénients (qui doit pouvoir lire l'état ?) face à l'inventaire Proxmox.
