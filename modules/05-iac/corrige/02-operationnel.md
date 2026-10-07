# Module 05 — Palier 2 : Opérationnel — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les fichiers complets cités ici sont dans [`fichiers/`](fichiers/), rangés comme les projets : `M05-EXX/infra/` (`plateforme/infra`), `M05-EXX/tofu-modules/`, `M05-EXX/ansible/` (`plateforme/ansible`), et les fichiers de poste (`adm01/`, `pve01/`, `pki/`). Chaque exercice ne fournit que ce qu'il ajoute ou modifie ; l'état de référence de `socle/` en fin de palier est la réunion de E10 (variables, provider), E11 (`versions.tf` avec backend), E16 (imports) et E17 (module, `moved`), sans `images.tf` (devenu inutile en E17, tflint le signale).

**Ce qui a été vérifié pendant la rédaction** (avec OpenTofu 1.13.1, provider `bpg/proxmox` 0.115.0, SeaweedFS 4.45, AWS CLI 2.37, tflint 0.64.0, terraform-docs 0.24.0, ansible-core 2.21, ansible-lint 26.9) :
- toutes les configurations OpenTofu des fichiers de solution passent `tofu fmt -check` et `tofu validate` (schéma réel du provider 0.115.0), `tflint --recursive` avec les `.tflint.hcl` de E20, et les tests `tofu test` du module (8 tests, provider simulé) ;
- contre une instance SeaweedFS 4.45 locale, lancée avec les options exactes de l'unité du rôle : HTTPS sur le port S3 (et refus du HTTP clair), refus de l'anonyme (403) dès qu'une identité existe, droits limités à un compartiment, versionnage, **écritures conditionnelles** (`If-None-Match: *` → 412, par AWS CLI comme par boto3), verrou `use_lockfile` d'OpenTofu (second `apply` refusé avec « Error acquiring the state lock »), politique de compartiment `Deny` sur une identité, rechargement de `s3.json` par SIGHUP, création de compartiments et versionnage par `weed shell` ;
- le rôle `seaweedfs` passe `ansible-lint` (profil `production`), et un `--check` sur hôte neuf jusqu'au service (le reste demande systemd) ; le gabarit `s3.json` et l'unité systemd ont été rendus et contrôlés ;
- le *user-data* de E19 passe `cloud-init schema` ; l'expression `compose` de E23 a été évaluée sur des données d'inventaire réalistes ; tous les scripts passent `shellcheck -x` et `bash -n`.

**Non testé en conditions réelles** (pas d'hyperviseur dans l'environnement de rédaction ; à confirmer par tes retours) : les plans et applies réels contre `pve01` (création de `s3-01`, imports de E16, `moved` de E17, snippets de E19), le scénario Molecule sur une VM Proxmox, et les points marqués « ⚠️ À vérifier ».

---

### M05-E10 — Construire `s3-01` : un stockage S3 pour le socle

**Solution**

1. **Terrain.** VMID : `ssh pve01 'qm status 1006'` doit répondre « does not exist ». Adresse : un `ping` muet ne prouve rien (pare-feu) ; on regarde la table ARP de `gw01` après un essai (`ssh gw01 'ping -c1 -W1 10.10.20.14; ip neigh show 10.10.20.14'` : `FAILED` ou rien = libre), et le DNS (`dig -x 10.10.20.14 @10.10.20.10` : aucune réponse). Droits : 
   ```
   root@pve01:~# VNETS="vsandbox vinfra" STOCKAGES="local-nvme hdd-bulk" ./pve-tofu-compte.sh
   ```
   Le script affiche les droits effectifs du jeton sur `/storage/hdd-bulk` et `/sdn/zones/lab/vinfra` : `Datastore.AllocateSpace`, `Datastore.Audit`, `SDN.Use`.

2. **Code** : [`fichiers/M05-E10/infra/socle/`](fichiers/M05-E10/infra/socle/) — `versions.tf` (sans backend), `providers.tf`, `variables.tf`, `images.tf` (source de données + postcondition « exactement une image »), `s3-01.tf`, `outputs.tf`, `terraform.tfvars`. Les lignes qui comptent dans `s3-01.tf` :
   ```hcl
   clone { vm_id = local.image_debian13.vm_id, full = true, datastore_id = var.datastore_systeme }
   cpu { cores = 2, type = "x86-64-v2-AES" }      # sinon qemu64 (défaut du provider)
   scsi_hardware = "virtio-scsi-single"           # sinon virtio-scsi-pci
   agent { enabled = true }                       # sinon désactivé
   disk { interface = "scsi1", datastore_id = var.datastore_donnees, size = 100, file_format = "qcow2", … }
   protection = true
   lifecycle {
     prevent_destroy = true
     ignore_changes  = [clone]
   }
   ```
   (Écrit ici sur une ligne pour la lecture ; HCL demande un attribut par ligne dans un bloc.) Format du disque de données : `hdd-bulk` est un stockage de type **répertoire** ; un disque `raw` y interdit les instantanés de VM, donc `ms-snapshot` (M02-E11) échouerait sur `s3-01`. `qcow2` les permet, pour un léger coût en performances, sans importance ici.

3. **Plan et apply** :
   ```
   admin@adm01:~/src/infra/socle$ set -a; . ~/.config/workbook/pve-tofu.env; set +a
   admin@adm01:~/src/infra/socle$ tofu init && tofu plan -out=/tmp/s3-01.tfplan
   …
     # proxmox_virtual_environment_vm.s3_01 will be created
     + resource "proxmox_virtual_environment_vm" "s3_01" {
         + name        = "s3-01"
         + protection  = true
         + tags        = [ "role-s3", "socle" ]
         + vm_id       = 1006
         …
   Plan: 1 to add, 0 to change, 0 to destroy.
   ```
   MR (plan collé dans la description), fusion, puis depuis `main` à jour : `tofu plan -out=…` et `tofu apply …tfplan`. Contrôle : `ssh pve01 qm config 1006`.

4. **DNS, SSH, inventaire.** Une ligne dans `group_vars/role_dns/dnsmasq.yml` ([extrait](fichiers/M05-E10/ansible/inventories/lab/group_vars/role_dns/dnsmasq-extrait.yml)), appliquée par la chaîne de M04 (`playbooks/dns01.yml`). Alias SSH sur `adm01` (`Host s3-01`, `HostName 10.10.20.14`, `User admin`), puis `ssh s3-01` une première fois pour enregistrer la clé d'hôte (et `ssh-keyscan` dans `inventories/lab/known_hosts` du projet Ansible). L'inventaire dynamique fabrique ses groupes **à partir des étiquettes** (`keyed_groups`) : sans `role-s3`, aucune raison d'entrer dans `role_s3`, et sans `socle`, le filtre de `proxmox.yml` l'exclut.
   ```
   admin@adm01:~/src/ansible$ uv run ansible-inventory --graph role_s3
   @role_s3:
     |--s3-01
   ```

5. **Certificat** : sections [`pki-provisoire-s3-01.cnf`](fichiers/M05-E10/pki/pki-provisoire-s3-01.cnf) à ajouter à `~/pki-provisoire/pki-provisoire.cnf`, puis [`emettre-s3-01.sh`](fichiers/M05-E10/pki/emettre-s3-01.sh) (même procédure que `git01`). Sortie attendue : `s3-01.crt: OK` et le SAN `DNS:s3-01.par1.medisphere.internal, DNS:s3-01, IP Address:10.10.20.14`. Le certificat et la clé vont dans le coffre Ansible (étape 6), pas sur `s3-01` à la main.

6. **Rôle** : [`fichiers/M05-E10/ansible/roles/seaweedfs/`](fichiers/M05-E10/ansible/roles/seaweedfs/), scénario [`molecule/seaweedfs/`](fichiers/M05-E10/ansible/molecule/seaweedfs/), valeurs du socle [`host_vars/s3-01/seaweedfs.yml`](fichiers/M05-E10/ansible/inventories/lab/host_vars/s3-01/seaweedfs.yml), modèles des coffres (`vault.yml.exemple` pour l'identité `lab`, `vault-critique.yml.exemple` pour `critique` : clé TLS et `admin-s3`), job CI [`gitlab-ci-molecule-seaweedfs.yml`](fichiers/M05-E10/ansible/gitlab-ci-molecule-seaweedfs.yml).
   - **Empreinte** (sur `adm01`, une fois par version) :
     ```
     admin@adm01:~/m05/e10$ curl -fLO https://github.com/seaweedfs/seaweedfs/releases/download/4.45/linux_amd64.tar.gz
     admin@adm01:~/m05/e10$ curl -fLO https://github.com/seaweedfs/seaweedfs/releases/download/4.45/linux_amd64.tar.gz.md5
     admin@adm01:~/m05/e10$ cat linux_amd64.tar.gz.md5; md5sum linux_amd64.tar.gz
     admin@adm01:~/m05/e10$ sha256sum linux_amd64.tar.gz        # → seaweedfs_archive_sha256
     ```
     ⚠️ À vérifier sur la page de la version : le nom exact du fichier de somme publié à côté de l'archive. MD5 ne protège que contre la corruption, pas contre une substitution délibérée (collisions) : la SHA-256 calculée **une fois** sur une archive dont la MD5 correspond, puis figée dans le code relu en MR, protège les passages suivants. Ce n'est pas une signature : si la page de l'éditeur est compromise le jour du calcul, on fige la mauvaise empreinte.
   - **Unité systemd** ([gabarit](fichiers/M05-E10/ansible/roles/seaweedfs/templates/seaweedfs.service.j2)) : un processus `weed server`. Les options qui portent les exigences :
     ```
     -ip=127.0.0.1 -ip.bind=127.0.0.1        master, volume, filer : en local seulement
     -s3.ip.bind=10.10.20.14 -s3.port=8333    seule la passerelle S3 sur le réseau
     -s3.cert.file=… -s3.key.file=…           HTTPS sur 8333 (le HTTP clair est refusé)
     -s3.config=/etc/seaweedfs/s3.json        identités
     -master.telemetry=false                  pas de statistiques envoyées à l'éditeur
     -master.volumeSizeLimitMB=1024 -volume.max=0
     -s3.port.iceberg=0 -s3.port.lance=0      catalogues ouverts par défaut, inutiles ici
     -s3.autoCreateBucket=false
     ```
     plus `RequiresMountsFor=/srv/seaweedfs`, `ProtectSystem=strict`, `ReadWritePaths=/srv/seaweedfs`, `ExecReload=/bin/kill -HUP $MAINPID`.
   - **Identités** : gabarit [`s3.json.j2`](fichiers/M05-E10/ansible/roles/seaweedfs/templates/s3.json.j2) qui produit le format du wiki :
     ```json
     { "identities": [ { "name": "tofu-etat",
         "credentials": [ { "accessKey": "…", "secretKey": "…" } ],
         "actions": [ "Read:tofu-state", "Write:tofu-state", "List:tofu-state" ] }, … ] }
     ```
     Tâche en `no_log: true` et `diff: false` (sinon `--diff` affiche les clés secrètes), handler **Recharger** (SIGHUP : vérifié, la nouvelle identité est acceptée sans redémarrage).
   - **Compartiments** : `weed shell -master=127.0.0.1:9333` avec `s3.bucket.list`, `s3.bucket.create -name tofu-state`, `s3.bucket.versioning -name tofu-state -enable` (sortie : `Bucket tofu-state versioning set to Enabled`). Aucune clé S3 nécessaire : le shell parle au master et au filer en local.
   - **Disque** : `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1`, `community.general.filesystem` (ne reformate jamais un disque qui porte un système de fichiers), montage par étiquette `LABEL=s3-donnees` sur `/srv/seaweedfs`, `nofail`.
   - **Molecule** : `uv run molecule test -s seaweedfs` (fichier d'accès Proxmox chargé). Le `converge` fabrique une CA de test et un certificat pour l'adresse de l'instance dans le dossier éphémère, et deux identités aux clés aléatoires ; le `verify` contrôle l'écoute (8333 seul hors de 127.0.0.1), le TLS **vérifié** avec la CA de test et le refus de l'anonyme (`uri` avec `ca_path`, attendu 403), le versionnage (`weed shell`), et deux `put_object(IfNoneMatch="*")` successifs : le second doit renvoyer **412**.

7. **Mise en service** : [`playbooks/s3-01.yml`](fichiers/M05-E10/ansible/playbooks/s3-01.yml), et dans `site.yml` ([extrait](fichiers/M05-E10/ansible/playbooks/site-extrait.yml)) le garde-fou passe à **six** hôtes dans `socle` et exige un hôte dans `role_s3`, le playbook est importé après le DNS. MR, pipeline (`ansible-lint`, `molecule:seaweedfs`, `--check` du socle), job `appliquer`, puis second passage : `s3-01 : ok=… changed=0`.

8. **Client et politique.** AWS CLI v2 par l'installeur officiel (archive vérifiée par sa signature PGP, procédure de la page d'installation), profil [`aws-config`](fichiers/M05-E10/adm01/aws-config) dans `~/.aws/config`, fichiers [`s3-tofu.env`](fichiers/M05-E10/adm01/s3-tofu.env.exemple) et [`s3-admin.env`](fichiers/M05-E10/adm01/s3-admin.env.exemple) en 600.
   ```
   admin@adm01:~$ set -a; . ~/.config/workbook/s3-tofu.env; set +a
   admin@adm01:~$ aws s3api list-buckets --query 'Buckets[].Name'
   [
       "tofu-state"
   ]
   admin@adm01:~$ aws s3api get-bucket-versioning --bucket tofu-state
   {
       "Status": "Enabled"
   }
   admin@adm01:~$ aws s3api put-bucket-versioning --bucket tofu-state --versioning-configuration Status=Suspended
   admin@adm01:~$ echo $?
   0
   ```
   **C'est accepté** : dans SeaweedFS, le droit `Write:tofu-state` couvre aussi la configuration du versionnage et la suppression définitive d'une version (`delete-object --version-id`), vérifié avec 4.45. Une identité `tofu-etat` volée (ou un script de nettoyage maladroit) pourrait donc effacer tout l'historique des états. Réactive, puis pose la politique ([`politique-tofu-state.json`](fichiers/M05-E10/infra/outils/s3/politique-tofu-state.json), versionnée dans `plateforme/infra/outils/s3/`) avec l'identité d'administration :
   ```
   admin@adm01:~/src/infra$ ( set -a; . ~/.config/workbook/s3-admin.env; set +a
   >   aws s3api put-bucket-versioning --bucket tofu-state --versioning-configuration Status=Enabled
   >   aws s3api put-bucket-policy --bucket tofu-state --policy file://outils/s3/politique-tofu-state.json )
   admin@adm01:~/src/infra$ aws s3api put-bucket-versioning --bucket tofu-state --versioning-configuration Status=Suspended
   aws: [ERROR]: An error occurred (AccessDenied) when calling the PutBucketVersioning operation: Access Denied.
   ```
   La politique refuse à `tofu-etat` : `s3:DeleteObjectVersion`, `s3:PutBucketVersioning`, `s3:PutLifecycleConfiguration`, `s3:PutBucketPolicy`, `s3:DeleteBucketPolicy`. La suppression **ordinaire** (qui pose un marqueur, réversible) reste permise : OpenTofu en a besoin pour rendre le verrou (E12). Vérifié avec 4.45 : le principal `arn:aws:iam::000000000000:user/tofu-etat` désigne bien l'identité `tofu-etat` (une politique visant un autre nom ne la bloque pas) ; ⚠️ à vérifier sur ta version si le numéro de compte est ignoré ou doit valoir une valeur précise.

9. **Socle complet** : `inventaire.md` (s3-01, 1006, 10.10.20.14, rôle, créée par OpenTofu, configurée par `seaweedfs`), `matrice-flux.md` (MGMT et `runner01` → `s3-01` TCP 8333, rien à ouvrir, raison), registre des secrets : `tofu-etat` (portée : `tofu-state` ; emplacements : Vault `lab`, `s3-tofu.env`, plus tard variable CI ; rotation 6 mois), `admin-s3` (portée : tout SeaweedFS ; Vault `critique`, `s3-admin.env` ; bris de glace, rotation à chaque usage), clé TLS (Vault `critique` ; avec le certificat, 397 jours). Sauvegarde : `s3-01` est dans le pool `lab`, donc dans `lab-nuit` — disque de données compris (`backup = true`) : c'est voulu, l'état y vit (voir E29 pour la sauvegarde **applicative**).

**Explications**

- **Pourquoi tout écrire sur un clone.** Le provider applique à tout attribut non écrit **sa** valeur par défaut, pas celle du template : `cpu.type` deviendrait `qemu64`, l'agent serait désactivé, le contrôleur SCSI changerait. La documentation le dit pour les disques ; on le constate pour le reste au premier `qm config`. La règle de l'équipe (déjà vue avec Packer en M03) : écrire le matériel complet de l'image.
- **`prevent_destroy` + `protection`.** Le premier est vérifié par OpenTofu au **plan** (toute action qui détruirait l'objet, remplacement compris, fait échouer le plan) ; le second par Proxmox à l'**API** (refus de supprimer la VM ou un disque, même par un autre outil). Ils se complètent : `prevent_destroy` disparaît si quelqu'un supprime la ressource du code (le plan devient « destroy »… que `protection` refusera).
- **`ignore_changes = [clone]`.** `clone.vm_id` est un attribut à remplacement forcé (vérifié dans le schéma du provider 0.115). L'image `current` change chaque semaine (M03) : sans cette ligne, le lundi suivant, le plan proposerait de détruire `s3-01` — et `prevent_destroy` bloquerait **tous** les plans du socle.
- **Un seul processus `weed server`.** Master (métadonnées des volumes), volume (données), filer (arborescence et métadonnées S3) et passerelle S3 dans un même service : simple à exploiter, à sauvegarder, à redémarrer. Séparer les composants n'a de sens qu'avec plusieurs machines (réplication, montée en charge) : pas notre cas, et ce serait trois services à durcir au lieu d'un.
- **Volumes de SeaweedFS.** Les données vont dans des « volumes » de taille maximale fixe (30 Go par défaut). `-volume.max=0` les compte automatiquement : espace libre ÷ taille d'un volume. Sur 100 Go avec 30 Go par volume : 3 volumes ; or chaque compartiment (« collection ») en réserve plusieurs dès sa première écriture (7 observés avec 4.45). Résultat : « No writable volumes and no free volumes left » à la première écriture d'OpenTofu. Avec 1 Go par volume, ~95 emplacements.
- **TLS sur le port 8333.** Quand `-s3.cert.file` et `-s3.key.file` sont donnés, le port S3 lui-même passe en HTTPS (vérifié : une requête en clair reçoit une réponse 400 « client sent an HTTP request to an HTTPS server »). Il existe aussi `-s3.port.https`, pour servir les deux à la fois : inutile ici.
- **« Allow-All ».** Le wiki (page « S3 Credentials ») est explicite : sans aucune identité chargée, la passerelle **accepte tout, sans authentification**. D'où l'`assert` du rôle (liste d'identités non vide) et la sonde 403 en fin de rôle et dans le `verify` de Molecule.
- **Le paradoxe de l'œuf et de la poule.** `s3-01` porte l'état qui la décrit. Si elle est perdue, OpenTofu ne peut plus lire l'état du socle… nécessaire pour la recréer. On l'accepte parce que : la VM est protégée deux fois, sauvegardée chaque nuit par PBS (restauration en une commande, sans OpenTofu), et l'état sera sauvegardé ailleurs (E29). La procédure de reconstruction « à froid » (état local temporaire, `import`, puis migration) va dans RB-050/RB-051.

**Alternatives**

- **Garage** : léger, conçu pour l'auto-hébergement… mais sans écritures conditionnelles au moment de la rédaction : le verrou `use_lockfile` serait illusoire (E12, ADR de E30).
- **Ceph RGW** (module 08) : le S3 « de production », mais un cluster entier pour un état de quelques Mo.
- **Backend `http` de GitLab** (état géré par la forge) : aucun stockage à construire, verrou par l'API GitLab, et le chiffrement côté client d'OpenTofu (E27) fonctionne avec tout backend ; mais l'état dépend alors de `git01`, que ce même état décrit (E16), et chaque projet gère ses états dans son propre espace GitLab. L'option est sérieuse et doit figurer dans l'ADR de E30.
- **Client `s5cmd` ou `rclone`** au lieu d'AWS CLI : plus rapides pour copier beaucoup d'objets ; AWS CLI v2 reste la référence pour les opérations fines (`s3api`, `--if-none-match`, versions, politiques).

**Pièges classiques**

- Oublier `-s3.ip.bind` : la passerelle n'écoute alors que sur l'adresse de `-ip` (ici 127.0.0.1) ; mettre `-ip=10.10.20.14` à la place expose master, volume et filer (et leurs ports gRPC) sur le réseau, **sans authentification**.
- La CLI aws qui refuse le certificat alors que `curl` l'accepte : elle n'utilise pas le magasin du système (réglage `ca_bundle` du profil). Et une variable `AWS_CA_BUNDLE` héritée d'ailleurs **l'emporte** sur le profil.
- Au démarrage, SeaweedFS 4.45 écrit « Failed to load IAM configuration: no signing key found for STS service » : sans conséquence pour les identités de `-s3.config` (il parle du service STS, non utilisé) ; vérifié, l'authentification fonctionne.
- `-s3.allowDeleteBucketNotEmpty=false` ne protège pas comme on le croit : dans notre essai avec 4.45, la suppression d'un compartiment versionné non vide par une identité `Admin` a quand même abouti. La protection réelle : `admin-s3` hors de l'usage courant, et la sauvegarde (E29).
- Un `--check` du rôle sur un hôte neuf qui échoue sur `get_url` ou `systemd` : le rôle de référence saute proprement ce qui ne peut pas être simulé (binaire pas encore là, unité inexistante).
- `site.yml` qui refuse de partir après la création de `s3-01` : c'est le garde-fou de M04-E39 qui compte les hôtes de `socle`. Il faut le mettre à jour **dans la même MR** que le playbook.
- Disque de données vu comme `/dev/sdb` aujourd'hui, `/dev/sda` après un ajout de disque : toujours `/dev/disk/by-id/…` et un montage par étiquette ou UUID.

**En production chez MédiSphère**

- Deux nœuds SeaweedFS au moins (réplication `001`), ou un S3 Ceph RGW quand le module 08 l'apporte ; supervision de l'espace disque, du nombre de volumes libres et du code HTTP de la sonde (module 21, `-metricsPort`).
- Certificat ACME de step-ca (module 06), renouvelé automatiquement ; identités gérées par le filer ou l'interface d'administration avec rotation outillée ; clés `admin-s3` dans un coffre-fort (module 25), jamais sur un poste.
- Versionnage avec une règle de cycle de vie qui purge les versions de plus de N jours **posée par l'administrateur** (pas par `tofu-etat`), et verrouillage d'objet (*Object Lock*) en mode gouvernance pour les états du socle.

---

### M05-E11 — Backend S3 et migration de l'état

**Solution**

1. Sauvegardes et repères :
   ```
   admin@adm01:~/src/infra/socle$ install -d -m 700 ~/m05/e11 && install -m 600 terraform.tfstate ~/m05/e11/socle.tfstate
   admin@adm01:~/src/infra/socle$ jq '{serial, lineage}' terraform.tfstate
   {
     "serial": 4,
     "lineage": "8e2c4b51-0d9f-4a77-a3c1-6b2e9f0d7a14"
   }
   admin@adm01:~/src/infra/socle$ tofu state list > ~/m05/e11/socle.liste
   ```
2. Options (fichier complet : [`fichiers/M05-E11/infra/socle/versions.tf`](fichiers/M05-E11/infra/socle/versions.tf)) :

   | Option | Pourquoi avec SeaweedFS |
   |---|---|
   | `bucket`, `key` | où ranger l'état ; une clé par configuration |
   | `region = "us-east-1"` | le SDK AWS exige une région ; SeaweedFS l'ignore |
   | `endpoints = { s3 = "https://s3-01…:8333" }` | sinon le SDK appelle `s3.us-east-1.amazonaws.com` |
   | `use_path_style = true` | sinon il appelle `https://tofu-state.s3-01.par1…` : nom inexistant |
   | `skip_credentials_validation` | pas d'appel STS `GetCallerIdentity` (STS n'existe pas ici) |
   | `skip_region_validation` | ne pas refuser une région inconnue d'AWS |
   | `skip_requesting_account_id` | pas d'appel IAM/STS pour trouver un numéro de compte |
   | `skip_metadata_api_check` | ne pas interroger 169.254.169.254 (métadonnées EC2) pour des identifiants |
   | `use_lockfile` | ajouté en E12 |

   Non écrits : `access_key`/`secret_key` (secrets : environnement), `profile` (OpenTofu lit les variables `AWS_*` ; le profil `s3-socle` sert à la CLI), `skip_s3_checksum` (inutile avec SeaweedFS 4.45 : l'état et le verrou s'écrivent avec les sommes de contrôle par défaut du SDK, vérifié), `custom_ca_bundle` (OpenTofu, programme Go, lit le magasin du système, qui contient la CA provisoire).
3. Migration :
   ```
   admin@adm01:~/src/infra/socle$ set -a; . ~/.config/workbook/pve-tofu.env; . ~/.config/workbook/s3-tofu.env; set +a
   admin@adm01:~/src/infra/socle$ tofu init -migrate-state
   Initializing the backend...
   Do you want to copy existing state to the new backend?
     Pre-existing state was found while migrating the previous "local" backend to the
     newly configured "s3" backend. No existing state was found in the newly
     configured "s3" backend. Do you want to copy this state to the new "s3"
     backend? Enter "yes" to copy and "no" to start with an empty state.

     Enter a value: yes

   Successfully configured the backend "s3"! OpenTofu will automatically
   use this backend unless the backend configuration changes.
   admin@adm01:~/src/infra/socle$ aws s3api list-object-versions --bucket tofu-state --prefix socle/ --query 'Versions[].[Key,VersionId,Size]' --output text
   socle/terraform.tfstate	6723a8…	14873
   admin@adm01:~/src/infra/socle$ aws s3 cp s3://tofu-state/socle/terraform.tfstate - | jq '{serial, lineage}'
   admin@adm01:~/src/infra/socle$ diff <(tofu state list) ~/m05/e11/socle.liste && tofu plan
   …
   No changes. Your infrastructure matches the configuration.
   ```
   Le `lineage` est identique : c'est le **même** état (même lignée), pas un nouvel état.
4. Restes : `terraform.tfstate` (l'ancien état local, intact, **plus utilisé** : à supprimer, il contient tout, secrets compris) ; `terraform.tfstate.backup` (s'il existe : idem) ; `.terraform/terraform.tfstate` : **pas** un état, la configuration du backend mémorisée par `tofu init` (type, options, empreinte) — il reste, mais `.terraform/` n'est jamais commité. `rm terraform.tfstate terraform.tfstate.backup` (`shred -u` n'a pas de sens sur un SSD/LVM-thin ; la copie de `~/m05/e11/` est supprimée à la fin de l'exercice).
5. `envs/lab-m05` : [`backend.tf`](fichiers/M05-E11/infra/envs/lab-m05/backend.tf), même procédure. Oublier de changer la clé : `envs/lab-m05` lirait l'état du socle. `tofu init -migrate-state` constaterait un état existant des deux côtés et demanderait lequel garder ; et si quelqu'un répond mal, ou si la clé est copiée dans un **nouveau** dossier (E21), le premier plan voit toutes les VMs du socle « absentes de la configuration » et propose de les **détruire** (bloqué par `prevent_destroy`, heureusement).
6. Clone neuf : `git clone`, `cd socle`, `tofu init` (télécharge le provider aux empreintes de `.terraform.lock.hcl`, configure le backend), `tofu plan` → « No changes ». L'état distant suffit ; il faut en plus les deux fichiers d'accès.
7. Service coupé :
   ```
   │ Error: error loading state: operation error S3: GetObject, exceeded maximum number of attempts, 5,
   │ https response error StatusCode: 0, RequestID: , HostID: , request send failed, Get
   │ "https://s3-01.par1.medisphere.internal:8333/tofu-state/socle/terraform.tfstate": dial tcp 10.10.20.14:8333: connect: connection refused
   ```
   (Forme indicative ; le message exact dépend du SDK.) OpenTofu réessaie plusieurs fois avant d'échouer : aucun plan sans état. C'est le symptôme de M05-E37.

**Explications**

- L'état n'est **pas** dans Git et **pas** sur un poste : il est dans un stockage partagé, versionné, sauvegardé. Le code dit ce qui doit exister, l'état dit ce qui existe pour OpenTofu ; perdre le second, c'est perdre le lien entre les deux.
- `-migrate-state` copie l'état ; `-reconfigure` ignore l'ancien backend (utile quand on change d'adresse pour un backend **qui contient déjà** le bon état). Confondre les deux est l'erreur classique de cette étape.
- Depuis OpenTofu 1.8, un bloc `backend` accepte des variables et des `locals` évalués à l'`init` (vérifié : `key = local.cle` fonctionne). Le workbook garde des littéraux : lisibles d'un coup d'œil en MR, sans `-var` oublié à l'`init` ; la factorisation sérieuse passe par Terragrunt (E24).

**Alternatives**

- Configuration **partielle** du backend (`backend "s3" {}` dans le code, valeurs dans un fichier `-backend-config=socle.s3.tfbackend`) : utile quand l'adresse change d'un site à l'autre ; plus de fichiers à garder synchronisés.
- Mettre l'adresse dans `AWS_ENDPOINT_URL_S3` plutôt que dans le code : documenté, mais l'adresse disparaît du dépôt ; on préfère l'avoir sous les yeux en revue.

**Pièges classiques**

- Répondre `no` à « copy existing state » : OpenTofu repart d'un état **vide**, et le plan suivant propose de créer `s3-01`… qui existe (échec), ou pire, sur une autre configuration, de tout recréer.
- Supprimer l'état local **avant** d'avoir vérifié l'objet distant.
- Copier le bloc `backend` d'une configuration à une autre sans changer la clé (E21).
- Croire qu'un `terraform.tfstate` vide ou absent en local signifie « pas d'état » : depuis la migration, `tofu state list` lit S3.

**En production chez MédiSphère**

- Une clé par configuration, et des configurations **petites** (rayon d'impact, durée des plans) : socle, réseau, chaque environnement applicatif.
- Accès à `tofu-state` limité au pipeline (E26) et aux administrateurs ; les postes n'ont plus que la lecture, et le bris de glace.
- Sauvegarde de l'état hors de `s3-01` (E29), testée.

---

### M05-E12 — Verrouiller l'état partagé

**Solution**

1. `use_lockfile = true` dans les deux blocs `backend`. Toute modification du bloc `backend` demande `tofu init` (OpenTofu compare l'empreinte de la configuration mémorisée dans `.terraform/terraform.tfstate` : « Backend configuration changed ») ; ici `tofu init -reconfigure` suffit, l'état ne change pas d'endroit.
2. Deux terminaux :
   ```
   admin@adm01:~/src/infra/envs/lab-m05$ tofu apply        # terminal 1 : NE PAS répondre
   …
   Do you want to perform these actions?
     Enter a value:

   admin@adm01:~/src/infra/envs/lab-m05$ tofu plan         # terminal 2
   ╷
   │ Error: Error acquiring the state lock
   │
   │ Error message: operation error S3: PutObject, https response error
   │ StatusCode: 412, RequestID: 18DC57FD29AD39FD, HostID: , api error
   │ PreconditionFailed: At least one of the pre-conditions you specified did not
   │ hold
   │ Lock Info:
   │   ID:        db30670d-f286-ca4a-51c5-796421aee8c2
   │   Path:      tofu-state/envs/lab-m05/terraform.tfstate
   │   Operation: OperationTypeApply
   │   Who:       admin@adm01
   │   Version:   1.13.1
   │   Created:   2026-10-12 08:14:52.625192205 +0000 UTC
   │   Info:
   ╵
   admin@adm01:~$ aws s3 cp s3://tofu-state/envs/lab-m05/terraform.tfstate.tflock - | jq .
   {
     "ID": "db30670d-f286-ca4a-51c5-796421aee8c2",
     "Operation": "OperationTypeApply",
     "Info": "",
     "Who": "admin@adm01",
     "Version": "1.13.1",
     "Created": "2026-10-12T08:14:52.625192205Z",
     "Path": "tofu-state/envs/lab-m05/terraform.tfstate"
   }
   ```
   (Message obtenu tel quel contre SeaweedFS 4.45 ; seules les valeurs changent.) Le verrou est pris **avant** le calcul du plan et gardé pendant la question de confirmation : un `apply` laissé en attente bloque toute l'équipe.
3. `-lock-timeout=2m` : le second réessaie pendant deux minutes avant d'échouer. En CI (E26), deux pipelines rapprochés attendent leur tour au lieu d'échouer ; sur un poste, c'est rarement souhaitable (on préfère savoir tout de suite que quelqu'un travaille).
4. Script : [`fichiers/M05-E12/infra/outils/s3-tester-ecriture-conditionnelle.sh`](fichiers/M05-E12/infra/outils/s3-tester-ecriture-conditionnelle.sh) (testé contre SeaweedFS 4.45) :
   ```
   admin@adm01:~/src/infra$ outils/s3-tester-ecriture-conditionnelle.sh
   1. Première écriture conditionnelle de s3://tofu-state/_essais/if-none-match-20261012-081930-4242 (doit réussir)
   6723a70d88d883b06cbe783dd3f7de1e
   2. Seconde écriture conditionnelle de la même clé (doit être REFUSÉE : 412)
   3. Ménage (marqueur de suppression ; les versions restent, c'est voulu)
   OK : seconde écriture refusée (PreconditionFailed / HTTP 412).
        Le verrou use_lockfile d'OpenTofu est fiable sur ce stockage.
   ```
5. Avec le versionnage, l'objet `.tflock` n'est jamais vraiment supprimé : chaque prise ajoute une version, chaque libération un marqueur de suppression. Quelques centaines d'octets par opération : négligeable ici, mais à purger par une règle de cycle de vie (administrateur) sur un état très actif. Avantage : on voit **qui** a verrouillé et quand, après coup (historique de l'objet verrou).
6. `kill -9` : le verrou reste (personne ne le rend). Tout plan suivant échoue avec le message ci-dessus et l'identifiant du verrou. On le lève avec `tofu force-unlock <ID>` depuis la configuration concernée, **après** avoir vérifié que plus aucun processus ne travaille (`Who`, `Created`, `ps` sur la machine indiquée, jobs CI en cours), et que l'état n'a pas été laissé à moitié écrit (dernière version de l'objet d'état, `tofu plan`). Détails : RB-050 (M05-E33).

**Explications**

- Le verrou natif repose sur une **seule** propriété du stockage : l'écriture conditionnelle atomique (`If-None-Match: *`). Si deux clients l'envoient en même temps, un seul réussit. Un stockage qui ignore l'en-tête (Garage au moment de la rédaction, MinIO d'avant 2024…) accepte les deux : chacun croit tenir le verrou. D'où le test **sur le stockage lui-même**, et non sur la foi d'un tableau de compatibilité.
- Le verrou protège l'**écriture de l'état**, pas l'infrastructure : deux configurations différentes qui gèrent la même VM (erreur de E15 ou E21) ont deux verrous différents et se marchent dessus quand même.
- Avant OpenTofu 1.10, il fallait une table DynamoDB (ou équivalent) : un second service, inexistant hors d'AWS.

**Alternatives**

- Backend `http` de GitLab : verrou par l'API de la forge.
- Backend `pg` (PostgreSQL) : verrou par *advisory lock* ; intéressant quand une base est déjà là (NetBox, module 06), mais l'état ne serait plus versionné de la même façon.

**Pièges classiques**

- Laisser un `tofu apply` interactif ouvert pendant la pause de midi : verrou tenu.
- `-lock=false` « pour aller plus vite » : réservé aux lectures (les vérifications du workbook l'utilisent pour `plan`, qui n'écrit pas l'état).
- Conclure « le verrou marche » d'un seul essai où les deux commandes ne se sont pas chevauchées.

**En production chez MédiSphère**

- `-lock-timeout` dans le pipeline, `resource_group` GitLab par état (E26) : la forge sérialise avant même OpenTofu.
- Alerte sur un `.tflock` présent depuis plus d'une heure (sonde S3, module 21).
- Le test d'écriture conditionnelle rejoué après chaque montée de version de SeaweedFS, dans la CI de `plateforme/ansible` (Molecule le fait déjà).

---

### M05-E13 — Écrire un module `vm-debian` réutilisable

**Solution**

1. Ce qui varie : nom, VMID, rôle et étiquettes, ressources (vCPU, mémoire, disques), réseau (VNet, statique ou DHCP), démarrage avec l'hôte et rang, protection, cloud-init personnalisé. Ce qui est identique : clone complet de l'image courante, matériel de l'image (CPU, SCSI, agent, console série), cloud-init de base (résolveur, domaine, compte `admin`), règles de cycle de vie. Étiquettes : des variables qui les **construisent** (`socle`, `role`, `environnement`) plutôt qu'une liste libre ; c'est le contrat avec l'inventaire Ansible (M04) : impossible d'écrire `role_s3` ou `env-M05` par erreur. Une liste `etiquettes` libre reste possible pour le reste.
2. Module complet : [`fichiers/M05-E13/tofu-modules/vm-debian/`](fichiers/M05-E13/tofu-modules/vm-debian/) (`versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`, `README.md`, `exemples/minimal/`, `tests/`). Points d'interface :
   ```hcl
   variable "reseau" {
     type = object({
       vnet       = string
       ipv4       = optional(string, "dhcp")
       passerelle = optional(string)
     })
     validation {
       condition     = var.reseau.ipv4 == "dhcp" || var.reseau.passerelle != null
       error_message = "reseau.passerelle est obligatoire avec une adresse statique (…)."
     }
   }
   locals {
     etiquettes = sort(distinct(compact(concat(
       var.socle ? ["socle"] : [], var.role != null ? ["role-${var.role}"] : [], …))))
   }
   ```
   Contrainte de version du module : `>= 0.115.0, < 1.0.0`. Un module ne fixe pas la version exacte : c'est le `.terraform.lock.hcl` de chaque **racine** qui le fait. Avec `~> 0.115.0` dans le module, une racine qui voudrait passer à 0.116 (E31) ne le pourrait qu'en publiant d'abord une nouvelle version du module. L'image : source de données avec `count` (lue seulement si `image.vm_id` est nul) ; imposer un VMID sert à essayer une image **candidate** avant sa publication (M03) ou à reconstruire une VM à l'identique.
3. `lifecycle` n'accepte que des valeurs **littérales** (OpenTofu le vérifie avant toute évaluation) : `prevent_destroy = var.proteger` est refusé. Et un appel de module n'a pas de bloc `lifecycle`. Le module expose donc `protection` (drapeau Proxmox) ; la relecture du plan fait le reste. Les VMs importées (E16) gardent `prevent_destroy` : ce sont des ressources directes.
4. [`exemples/minimal/`](fichiers/M05-E13/tofu-modules/vm-debian/exemples/minimal/) : `main.tf`, `variables.tf` (vide, commenté), `outputs.tf` (structure demandée par tflint en E20).
5. terraform-docs : [`.terraform-docs.yml`](fichiers/M05-E13/tofu-modules/.terraform-docs.yml) (format tableau, mode injection, sections requirements, providers, modules, inputs, outputs, resources, data-sources), `terraform-docs vm-debian` depuis la racine du projet. Le texte autour du tableau (« Choix et limites ») est écrit à la main : `ignore_changes` sur `clone` et la commande `-replace`, absence de `prevent_destroy`, effet d'un snippet, numérotation des disques.
6. Tests : [`tests/vm-debian.tftest.hcl`](fichiers/M05-E13/tofu-modules/vm-debian/tests/vm-debian.tftest.hcl), 8 cas, tous verts :
   ```
   admin@adm01:~/src/tofu-modules/vm-debian$ tofu init -backend=false && tofu test
   tests/vm-debian.tftest.hcl... pass
     run "etiquettes_triees_et_role"... pass
     run "image_courante_par_defaut"... pass
     run "image_imposee"... pass
     run "ip_statique"... pass
     run "statique_sans_passerelle_refusee"... pass
     run "vmid_hors_plage_refuse"... pass
     run "disques_donnees_numerotes"... pass
     run "sans_acces_refuse"... pass

   Success! 8 passed, 0 failed.
   ```
   Le provider simulé (`mock_provider "proxmox"` + `mock_data` pour la liste de templates) remplace l'API : `command = plan` suffit, rien n'est créé.

**Explications**

- **Le contrat d'un module**, ce sont ses variables (types, valeurs par défaut, validations) et ses sorties. Le reste peut changer sans prévenir… tant que le **plan** des consommateurs ne change pas. C'est ce qui rend un changement « majeur » (E14).
- **Ce qui reste dans la racine** : configuration des providers (adresse, accès), versions exactes (`.terraform.lock.hcl`), backend, décisions de cycle de vie propres à un usage (`prevent_destroy` des VMs importées).
- **`optional()` avec valeur par défaut** (OpenTofu ≥ 1.3) : des objets d'interface compacts sans multiplier les variables à plat.
- **Pourquoi `tofu test` avec un provider simulé** : il teste la **logique** du module (expressions, validations, choix de l'image) en quelques secondes, sans VM. Il ne teste pas Proxmox : ce rôle revient à un environnement réel (E15, E18).

**Alternatives**

- Modules publics (registre OpenTofu) pour bpg/proxmox : utiles pour s'inspirer, mais un module interne encode **nos** règles (plages de VMID, étiquettes, image dorée).
- Terratest (Go, module 29) : tests de bout en bout sur une vraie VM ; complémentaire, plus lent.

**Pièges classiques**

- Un bloc `provider` dans le module : il ne peut plus être utilisé avec `count`/`for_each`, ni avec un autre alias de provider.
- Des sorties qui exposent l'objet ressource entier : le moindre attribut interne devient une interface.
- `assert { condition = output.etiquettes == ["role-s3", …] }` qui échoue alors que les valeurs sont égales : liste contre tuple ; comparer les `jsonencode`.
- Oublier `sort()` sur les étiquettes : Proxmox les trie, et chaque plan affiche un changement.

**En production chez MédiSphère**

- Un module par « type de machine » de la plateforme (VM Debian, VM Rocky, nœud Kubernetes…), chacun avec son README, ses tests, ses exemples, et un responsable.
- Les règles du PLAN (plages de VMID, étiquettes réservées) testées dans les modules, pour qu'une erreur sorte au **plan** de n'importe quel consommateur.

---

### M05-E14 — Versionner les modules dans `plateforme/tofu-modules`

**Solution**

1. Projet : [`.releaserc.json`](fichiers/M05-E14/tofu-modules/.releaserc.json) (celui de M01-E25), [`.gitlab-ci.yml`](fichiers/M05-E14/tofu-modules/.gitlab-ci.yml) (gabarits `qualite.yml` et `release.yml`), étiquettes `v*` protégées, variable protégée et masquée `GITLAB_TOKEN` (jeton de projet `bot-release`, rôle Maintainer, portées `api` et `write_repository`). Le premier `feat:` (ou `fix:`) fusionné publie `v1.0.0` : sans étiquette antérieure, semantic-release commence à 1.0.0 ; un `docs:` ou un `chore:` ne publie rien.
2. Sur `adm01`, [réécriture HTTPS → SSH](fichiers/M05-E14/gitconfig-adm01.txt) :
   ```
   admin@adm01:~$ git config --global url."ssh://git@git01.par1.medisphere.internal/".insteadOf "https://git01.par1.medisphere.internal/"
   ```
   Appel : [`envs/lab-m05/modules.tf`](fichiers/M05-E14/infra/envs/lab-m05/modules.tf), `source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-debian?ref=v1.0.0"`. `tofu init` clone le dépôt dans `.terraform/modules/essai_module/` et note la source dans `.terraform/modules/modules.json`.
3. Après `feat(vm-debian): sortie fqdn` → `v1.1.0`. Changer `?ref=` sans `init` :
   ```
   │ Error: Module source has changed
   │
   │   on modules.tf line 5, in module "essai_module":
   │    5:   source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-debian?ref=v1.1.0"
   │
   │ The source address was changed since this module was installed. Run "tofu init" to install all modules required by this configuration.
   ```
   (Message indicatif.) Puis `tofu init` (ou `tofu init -upgrade`), plan relu : une nouvelle version peut changer des ressources.
4. README du projet : [`fichiers/M05-E14/tofu-modules/README.md`](fichiers/M05-E14/tofu-modules/README.md). Est majeur tout changement qui oblige un consommateur à modifier son code **ou** fait apparaître dans son plan une destruction ou un remplacement : renommer ou supprimer une variable ou une sortie ; rendre obligatoire une variable facultative ; renommer la ressource interne `vm` **sans** bloc `moved` ; changer une valeur par défaut qui touche un attribut à remplacement forcé (ex. `datastore` par défaut des disques de données) ; durcir une validation qui refuse des valeurs acceptées avant.
5. Liste d'autorisation : *Settings › CI/CD › Job token permissions › Add* `plateforme/infra` dans `plateforme/tofu-modules`. Extrait pour la CI d'infra : [`gitlab-ci-extrait-infra.yml`](fichiers/M05-E14/gitlab-ci-extrait-infra.yml) :
   ```yaml
   before_script:
     - export GIT_CONFIG_COUNT=1
     - export GIT_CONFIG_KEY_0="url.https://gitlab-ci-token:${CI_JOB_TOKEN}@git01.par1.medisphere.internal/.insteadOf"
     - export GIT_CONFIG_VALUE_0="https://git01.par1.medisphere.internal/"
   ```
   Sur un exécuteur `shell`, tous les jobs de tous les projets tournent sous le même compte `gitlab-runner` : un `git config --global` avec un jeton y resterait (valeur expirée qui casse les jobs suivants, ou jeton lisible par le job d'un autre projet). Les variables `GIT_CONFIG_*` ne vivent que le temps du processus du job.
6. Retrait de l'appel, plan (`- destroy` sur `module.essai_module…`, rien d'autre), apply.

**Explications**

- **Pourquoi une étiquette et pas une branche** : une branche bouge ; le même code donne alors deux plans différents selon le jour du `tofu init`. Une étiquette protégée ne bouge pas (on ne peut ni la supprimer ni la déplacer sans être Maintainer).
- Une source Git **n'accepte pas** de contrainte `version = "~> 1.1"` : c'est le privilège des registres. D'où la discipline `?ref=vX.Y.Z` et, plus tard, Renovate pour proposer les montées (module 13).
- `CI_JOB_TOKEN` : jeton éphémère, propre au job, avec les droits de l'utilisateur qui a déclenché le pipeline, **limité** par la liste d'autorisation du projet cible (activée par défaut sur les projets récents de GitLab). Rien à stocker, rien à faire tourner.

**Alternatives**

- Registre de modules GitLab (*Terraform Module Registry*, disponible en CE) : contraintes de version, découverte ; publication par un job (API `packages/terraform/modules`). Plus propre à grande échelle, une étape de plus.
- Jeton de déploiement en lecture dans une variable CI : fonctionne, mais c'est un secret de plus à faire tourner.

**Pièges classiques**

- `?ref=v1.1.0` alors que l'étiquette n'existe pas encore (MR du module pas encore fusionnée) : `tofu init` échoue sur un « reference not found » peu explicite.
- `git config --global` avec un jeton sur un runner partagé.
- Oublier `//vm-debian` (le module serait la racine du dépôt) ou le mettre après `?ref=`.

**En production chez MédiSphère**

- Renovate propose chaque nouvelle version de module par MR, avec le plan de chaque environnement consommateur.
- Notes de version lues par les consommateurs : semantic-release les génère à partir des messages de commit, qui doivent donc dire ce qui change **pour l'appelant**.

---

### M05-E15 — Environnements : workspaces ou répertoires ?

**Solution**

1. Brouillon : [`fichiers/M05-E15/essai-espaces/main.tf`](fichiers/M05-E15/essai-espaces/main.tf).
   ```
   admin@adm01:~/m05/e15/espaces$ tofu init && tofu workspace new recette && tofu apply
   admin@adm01:~/m05/e15/espaces$ tofu workspace new dev && tofu apply
   admin@adm01:~/m05/e15/espaces$ aws s3 ls --recursive s3://tofu-state/ | grep e15
   2026-10-13 09:12:40      14512 env:/dev/essais/e15/terraform.tfstate
   2026-10-13 09:05:11      14498 env:/recette/essais/e15/terraform.tfstate
   ```
   Préfixe `env:` = valeur par défaut de `workspace_key_prefix`. Dans `default`, l'expression `local.vmids[terraform.workspace]` échoue (« Invalid index ») : garde-fou rudimentaire.
2. Rien, dans le terminal, ne dit dans quel espace on est (sauf `tofu workspace show`) : un plan lancé dans `dev` en croyant être dans `recette` s'appliquerait à la VM de `dev`. Seul le contenu du plan (nom de la VM) peut alerter. Ce qui l'aurait empêché : des **répertoires** (on voit où on est), un invite de shell qui affiche l'espace, ou une variable d'environnement `TF_WORKSPACE` posée par un script.
3. `tofu destroy` dans chaque espace, `tofu workspace select default`, `tofu workspace delete recette` et `dev`. `aws s3api list-objects-v2 --prefix env:/` : `KeyCount: 0` ; les versions restent (historique).
4. Comparaison :

   | Critère | Espaces de travail | Répertoires |
   |---|---|---|
   | États et verrous | séparés (préfixe `env:/<espace>/`) | séparés (clé par dossier) |
   | Accès différents par environnement | **non** : même backend, mêmes identifiants | oui : backend, clé, identifiants propres |
   | Versions de providers et de modules | identiques pour tous | propres à chaque environnement (montée progressive) |
   | Lisibilité d'une MR | on ne voit pas quel environnement change | le chemin du fichier le dit |
   | Erreur humaine | espace courant invisible | dossier courant visible |
   | Duplication | aucune | backend/provider/versions recopiés (Terragrunt, E24) |
   | Différences de structure entre environnements | `count`/conditions sur `terraform.workspace` | du code différent, naturellement |

   Décision ([`docs/environnements.md`](fichiers/M05-E15/infra/docs/environnements.md)) : **répertoires** pour les environnements durables ou qui diffèrent (accès, taille, versions) ; espaces de travail tolérés pour des copies **identiques et éphémères** d'une même configuration (une branche de test, une démo), jamais pour séparer production et recette. C'est aussi ce que dit la documentation d'OpenTofu.
5. [`fichiers/M05-E15/infra/envs/recette-m05/`](fichiers/M05-E15/infra/envs/recette-m05/) : `versions.tf` (backend, clé `envs/recette-m05/terraform.tfstate`), `providers.tf`, `variables.tf`, `main.tf` (module avec `for_each` sur `vms`), `outputs.tf`, `terraform.tfvars`. Plan : `2 to add`. Apply. Puis `tofu plan` dans `envs/lab-m05` : vide (la recette ne l'a pas touché).

**Explications**

- Un espace de travail n'est qu'un **second état** pour la même configuration. Tout ce qui diffère doit se calculer à partir de `terraform.workspace`, ce qui disperse des conditions dans le code et cache la différence aux relecteurs.
- Les répertoires dupliquent un peu de « plomberie » (backend, provider) mais rendent chaque environnement explicite et indépendant. La duplication se traite par un outil (Terragrunt) ou une convention, pas en mélangeant les environnements.

**Alternatives**

- Une seule configuration avec des fichiers de variables par environnement (`-var-file=recette.tfvars`) et une clé de backend passée à l'`init` (`-backend-config`) : moins de duplication, mais l'environnement dépend de deux options à ne pas oublier.
- Terragrunt (E24) : répertoires **et** pas de duplication.

**Pièges classiques**

- Oublier qu'un `tofu workspace delete` refuse un espace dont l'état n'est pas vide (il faut détruire d'abord, ou `-force`, qui « oublie » des ressources bien réelles).
- Créer `envs/recette-m05/` par copie de `envs/lab-m05/` sans changer la clé du backend (E11, E21).
- Laisser des VMs de l'essai : `qm list` doit être propre avant de créer la recette (mêmes VMID).

**En production chez MédiSphère**

- Un répertoire (ou une unité Terragrunt) par environnement et par composant ; droits du pipeline différents pour la production (variables protégées propres, E26).
- Les environnements éphémères (une MR = un environnement) sont créés et détruits par la CI, avec leur propre clé d'état dérivée du numéro de MR.

---

### M05-E16 — Importer le socle existant sans le recréer

**Solution**

1. Relevé : `for i in 1001 1002 1004 1007; do ssh pve01 qm config $i > ~/m05/e16/$i.conf; done`. Différences avec `s3-01` : `cicustom: vendor=hdd-bulk:snippets/vendor-debian13.yaml` (hérité du template 9000, M00-E11), lecteur cloud-init sur `ide2`, clés SSH de `root@pve01` dans `sshkeys` (M00), `agent: enabled=1,fstrim_cloned_disks=1`, VNet ou pont avec étiquette VLAN selon ton M00, parfois une ancienne étiquette (`dns`) en plus de `role-dns`.
2. Blocs `import` seuls, puis :
   ```
   admin@adm01:~/src/infra/socle$ tofu plan -generate-config-out=genere.tf
   …
   Plan: 4 to import, 0 to add, 0 to change, 0 to destroy.
   ```
   `genere.tf` contient **tous** les attributs lus, valeurs calculées comprises (adresses MAC, `vm_id`, valeurs par défaut) : illisible et fragile, à ne pas commiter. On en garde les valeurs **qui comptent** : disques (interface, stockage, taille, options), cartes réseau, `initialization` (dont `vendor_data_file_id`), CPU, mémoire, démarrage, étiquettes.
3. Version de référence : une ressource `for_each` et un import en boucle ([`imports.tf`](fichiers/M05-E16/infra/socle/imports.tf), [`socle-importe.tf`](fichiers/M05-E16/infra/socle/socle-importe.tf)) : les quatre VMs sont des clones du même template, leurs différences tiennent dans une table. Si tes VMs diffèrent davantage (cartes en plus), une ressource par VM est plus lisible : c'est un choix, pas une règle.
   ```hcl
   import {
     for_each = local.socle_importe
     to       = proxmox_virtual_environment_vm.socle[each.key]
     id       = "${var.noeud}/${each.value.vm_id}"
   }
   ```
   Journal des écarts typiques et décisions :

   | Écart au plan | Cause | Décision |
   |---|---|---|
   | `vendor_data_file_id = "hdd-bulk:snippets/vendor-debian13.yaml" -> null # forces replacement` | hérité du template 9000 | **recopier** dans le code (sinon remplacement) |
   | `user_account { keys = [ … ] }` | clés de M00, gérées depuis par Ansible | `ignore_changes = [initialization[0].user_account]`, commenté |
   | `tags = ["dns", "role-dns", "socle"] -> ["role-dns", "socle"]` | ancienne étiquette | retirer l'étiquette dans Proxmox **avant**, ou la déclarer ; on ne laisse pas OpenTofu modifier une VM pendant un import |
   | `agent { trim = true -> false }` | `fstrim_cloned_disks=1` | recopier `trim = true` |
   | `description` | notes saisies dans l'interface | `ignore_changes`, commenté |
   | `size = 30 -> 20` sur `scsi0` | taille réelle différente de la table | corriger la table (et jamais l'inverse : un disque ne rétrécit pas) |

   ⚠️ À vérifier sur ta version : les écarts réels dépendent de ce que M00/M01 ont laissé sur tes VMs et de la façon dont le provider 0.115 relit certains attributs (`keyboard_layout`, `startup`, `network_device.firewall`…). La méthode, elle, ne change pas : un écart = une valeur réelle à recopier, ou un `ignore_changes` justifié.
4. Protection : `lifecycle { prevent_destroy = true }` dans la ressource. Preuve :
   ```
   admin@adm01:~/src/infra/socle$ tofu plan -destroy
   ╷
   │ Error: Resource instance cannot be destroyed
   │
   │   on socle-importe.tf line 61:
   │   61: resource "proxmox_virtual_environment_vm" "socle" {
   │
   │ Resource instance proxmox_virtual_environment_vm.socle["adm01"] has
   │ prevent_destroy set, but the plan calls for it to be destroyed.
   │
   │ To proceed, either disable prevent_destroy for this resource or exclude
   │ instances of this resource from this round using:
   │     -exclude="proxmox_virtual_environment_vm.socle[\"adm01\"]"
   ╵
   ```
   (Forme du message vérifiée avec OpenTofu 1.13 ; il est répété pour chaque instance protégée.) `tofu plan` ne modifie jamais rien : le pire risque est le verrou, rendu à la fin.
5. `gw01` : **hors d'OpenTofu, surveillé en lecture** ([`gw01.tf`](fichiers/M05-E16/infra/socle/gw01.tf), [ADR-0051](fichiers/M05-E16/docs/adr-0051-gw01-hors-iac.md)). Un bloc `check` lit la VM à chaque plan (source de données `proxmox_virtual_environment_vms` filtrée par nom) et **avertit** sans bloquer si elle n'existe plus, ne tourne plus, ou a perdu ses étiquettes. (La source de données au singulier `proxmox_virtual_environment_vm` est dépréciée dans le provider 0.115 au profit de `proxmox_vm`, encore expérimentale : on l'évite, vérifié au `validate`.)
6. MR avec le plan (`4 to import, 0 to add, 0 to change, 0 to destroy`), relecture, fusion, apply :
   ```
   proxmox_virtual_environment_vm.socle["adm01"]: Importing... [id=pve01/1001]
   proxmox_virtual_environment_vm.socle["adm01"]: Import complete [id=pve01/1001]
   …
   Apply complete! Resources: 4 imported, 0 added, 0 changed, 0 destroyed.
   ```
   Puis `tofu plan` → « No changes ». Suppression des instantanés : `ms-snapshot --prefix avant-import --keep 0 …` (selon les options de ton script M02) ou `qm delsnapshot`.

**Explications**

- **Import ≠ adoption sans risque.** L'import ne fait qu'**associer** un objet existant à une adresse. Tout ce que le code dit différemment de la réalité devient, au même apply, une modification… ou un remplacement si l'attribut est à remplacement forcé. D'où la règle : on n'applique qu'un plan d'import **pur**.
- **Blocs `import` plutôt que `tofu import`** : le bloc passe par une MR, se voit au plan, se rejoue dans la CI ; la commande modifie l'état tout de suite, depuis un poste, sans relecture.
- **`ignore_changes`** est une dette : chaque attribut ignoré est une dérive que le plan ne montrera plus. D'où le commentaire obligatoire (pourquoi, et qui gère cette valeur à la place).
- **Ce qu'OpenTofu ne doit pas gérer** : ce dont la panne coupe le chemin d'OpenTofu lui-même (`gw01`), ce qui se reconstruit mieux autrement, ce qui change sans cesse hors de lui.

**Alternatives**

- Recréer les VMs du socle par le module, une par une, avec migration des données : propre à terme (une seule façon de faire), coûteux et risqué maintenant ; à planifier VM par VM (une nouvelle `runner01` est le meilleur candidat : sans données).
- Importer `gw01` avec `ignore_changes = all` : il entre dans l'état, mais OpenTofu ne pourra plus rien y faire ni rien y voir… sauf le détruire si le code disparaît (`prevent_destroy` indispensable). Peu d'intérêt face au bloc `check`.

**Pièges classiques**

- Commiter `genere.tf` « pour l'instant ».
- Appliquer un plan d'import qui contient aussi un `~` « sans importance » sur `git01` (description, ou `started`) : un changement de configuration de VM peut provoquer un redémarrage.
- Oublier `vendor_data_file_id` : `-/+` sur les quatre VMs (et `prevent_destroy` qui bloque tout : heureusement).
- Corriger l'écart en modifiant la VM (`qm set`) pour coller au code : c'est l'inverse de l'objectif, et ça peut régénérer la configuration cloud-init.

**En production chez MédiSphère**

- Un inventaire de ce qui est **hors IaC**, tenu à jour (ADR, `docs/socle/iac.md`), avec la raison et la date de réexamen.
- Les imports se font par lots petits, dans des fenêtres annoncées, avec instantanés, et le plan d'import est relu par deux personnes.

---

### M05-E17 — Refactorer sans détruire : `moved` et `removed`

**Solution**

1. **`s3-01`** : [`socle/s3-01.tf`](fichiers/M05-E17/infra/socle/s3-01.tf) (appel du module), [`socle/refactorisation.tf`](fichiers/M05-E17/infra/socle/refactorisation.tf), [`socle/outputs.tf`](fichiers/M05-E17/infra/socle/outputs.tf) ; `images.tf` est supprimé (le module cherche lui-même l'image). Sans `moved`, le plan dit :
   ```
     # module.s3_01.proxmox_virtual_environment_vm.vm will be created
     # proxmox_virtual_environment_vm.s3_01 will be destroyed
     # (because proxmox_virtual_environment_vm.s3_01 is not in configuration)
   ╷
   │ Error: Resource instance cannot be destroyed
   ```
   (`prevent_destroy` sauve la situation : sans lui, le plan proposait `1 to add, 1 to destroy`.) Avec :
   ```hcl
   moved {
     from = proxmox_virtual_environment_vm.s3_01
     to   = module.s3_01.proxmox_virtual_environment_vm.vm
   }
   ```
   le plan affiche `# proxmox_virtual_environment_vm.s3_01 has moved to module.s3_01.proxmox_virtual_environment_vm.vm` et, au plus, une modification sur place de la `description` (texte ajouté par le module) : acceptable, sans effet sur la VM en marche. Les garde-fous : `protection = true` passe par la variable du module ; `prevent_destroy` est **perdu** (impossible dans un module, E13) ; `ignore_changes = [clone]` est dans le module.
2. **Serveurs d'application** : [`envs/lab-m05/app.tf`](fichiers/M05-E17/infra/envs/lab-m05/app.tf) et [`envs/lab-m05/refactorisation.tf`](fichiers/M05-E17/infra/envs/lab-m05/refactorisation.tf). Un `moved` n'accepte ni `for_each` ni `count` : un bloc par instance. L'appel du module reproduit les VMs du palier 1 : disques `raw` sur `local-nvme` présentés en SSD (`format = "raw"`, `ssd = true`), système de 10 Go, `demarrage_auto = false`, `arret_force = true`. Il reste au plan une modification sur place de l'`agent` (le palier 1 écrivait `timeout = "5m"`, le module laisse la valeur par défaut) et de la `description` : réglages du provider et texte, sans effet sur les VMs.
3. **`m05-essai`** : ressource et sortie `essai` retirées de `lab-m05`, bloc `removed` :
   ```hcl
   removed {
     from = proxmox_virtual_environment_vm.essai
     lifecycle {
       destroy = false
     }
   }
   ```
   Plan : `# proxmox_virtual_environment_vm.essai will be removed from the OpenTofu state but will not be destroyed` puis `Plan: 0 to add, 0 to change, 0 to destroy, 1 to forget.` (formulation vérifiée avec OpenTofu 1.13). Apply. **Puis** dans `envs/recette-m05` : [`essai-importe.tf`](fichiers/M05-E17/infra/envs/recette-m05/essai-importe.tf) (bloc `import` vers `module.essai.proxmox_virtual_environment_vm.vm`), plan `1 to import`, apply. L'ordre inverse mettrait la VM dans **deux** états à la fois : deux configurations qui la gèrent, deux verrous différents, et le premier `apply` de `lab-m05` (où elle serait encore « à moi ») pourrait la modifier ou la détruire.
4. Règle (`CONTRIBUTING.md`) : un `moved` reste au moins jusqu'à ce que **tous** les états qui pourraient contenir l'ancienne adresse aient été appliqués avec lui (copies de travail, branches ouvertes, et les versions d'état qu'on pourrait restaurer, E29) ; en pratique, une version et un mois, puis retrait par MR dédiée. Un `removed` peut partir dès que l'apply est passé partout. Vérifié : retirer un `moved` trop tôt et appliquer un **ancien** état ramène le couple `destroy` + `create`.
5. Méthode impérative équivalente : `tofu state mv proxmox_virtual_environment_vm.s3_01 module.s3_01.proxmox_virtual_environment_vm.vm`, `tofu state rm proxmox_virtual_environment_vm.essai`, `tofu import 'module.essai.proxmox_virtual_environment_vm.vm' pve01/2050`. Chaque commande modifie l'état **immédiatement**, depuis un poste, sans plan ni revue, et doit être répétée à la main sur chaque copie de l'état. Les blocs sont du code : relus en MR, appliqués par la chaîne, rejoués partout.

**Explications**

- `moved` change l'**adresse** dans l'état, jamais l'objet. Il s'applique avant le calcul du plan : la ressource est alors comparée à son nouveau code ; tout écart restant est un vrai changement, à traiter comme tel.
- `removed` (OpenTofu ≥ 1.7, `lifecycle { destroy = false }` vérifié en 1.13) est l'équivalent déclaratif de `tofu state rm` : « oublie cet objet, ne le touche pas ». Le JSON du plan porte l'action `forget`.
- Le plan est la preuve : une MR de refactorisation qui montre un `+` et un `-` sur la même VM n'est **pas** une refactorisation.

**Alternatives**

- Garder la ressource directe pour `s3-01` (avec `prevent_destroy`) et n'utiliser le module que pour les nouvelles VMs : défendable ; on perd l'uniformité, on garde la protection d'OpenTofu.
- `tofu state mv` en bris de glace, quand une MR est impossible (forge en panne), avec copie de l'état avant.

**Pièges classiques**

- Adresse d'instance mal écrite (`module.app.app01…` au lieu de `module.app["app01"]…`) : OpenTofu accepte le bloc, ne trouve rien à déplacer, et le plan revient à `+`/`-`.
- Faire l'import dans la recette **avant** le `removed` dans `lab-m05`.
- Croire que la `description` modifiée « ne touche pas la VM » sans l'avoir vérifié : certaines modifications sur place (matériel) demandent un redémarrage ; le provider le fait si `reboot_after_update` le permet (vrai par défaut).

**En production chez MédiSphère**

- Toute refactorisation passe par une MR **sans autre changement**, dont le plan est relu par deux personnes ; le pipeline refuse un plan de refactorisation qui contient une destruction (filtre `jq` de E22).
- Les modules portent leurs propres `moved` quand ils renomment une ressource interne : c'est ce qui permet de publier une version mineure.

---

### M05-E18 — Dépendances et cycle de vie des ressources

**Solution**

1. Graphe :
   ```
   admin@adm01:~/src/infra/envs/recette-m05$ sudo apt install -y graphviz
   admin@adm01:~/src/infra/envs/recette-m05$ tofu graph | dot -Tsvg > ~/m05/e18/recette.svg
   ```
   Les arêtes `module.vm["api"]…vm → module.vm["api"]…data…image` viennent de la **référence** `local.image_vm_id` ; il n'y a aucune arête entre `api` et `bdd` : rien ne les relie, OpenTofu les traite en parallèle (10 opérations simultanées par défaut). Avec `-parallelism=1`, le plan (lecture de deux VMs) prend à peu près le double ; sur un `apply` de création, la différence est d'autant plus grande que chaque clone complet dure.
2. VM jetable : [`envs/lab-m05/cycle-de-vie.tf`](fichiers/M05-E18/infra/envs/lab-m05/cycle-de-vie.tf) et la ligne de [`terraform.tfvars`](fichiers/M05-E18/infra/envs/lab-m05/terraform.tfvars-extrait). L'essentiel :
   ```hcl
   resource "terraform_data" "generation_jetable" {
     input = var.generation_jetable
   }
   resource "proxmox_virtual_environment_vm" "jetable" {
     …
     lifecycle {
       ignore_changes       = [clone]
       replace_triggered_by = [terraform_data.generation_jetable]
       precondition {
         condition     = startswith(local.image_nom, "deb13-gold-")
         error_message = "…"
       }
       postcondition {
         condition     = anytrue([for a in flatten(self.ipv4_addresses) : startswith(a, "10.10.99.")])
         error_message = "m05-jetable n'a pas d'adresse dans 10.10.99.0/24 : …"
       }
     }
   }
   ```
   (`local.image_nom` vient de `data.tf` du palier 1.) `replace_triggered_by` n'accepte pas une variable : `terraform_data` sert d'intermédiaire. La postcondition est évaluée après la création (l'agent a remonté ses adresses : le provider attend une adresse avant de rendre la main) ; si le DHCP du VLAN 99 est en panne, l'apply échoue au lieu de livrer une VM injoignable (c'est la panne de M05-E39).
3. Changement de génération (formulation vérifiée avec OpenTofu 1.13) :
   ```
     # terraform_data.generation_jetable will be updated in-place
     ~ resource "terraform_data" "generation_jetable" {
         ~ input  = "2026-10-12" -> "2026-10-19"
         ~ output = "2026-10-12" -> (known after apply)
       }

     # proxmox_virtual_environment_vm.jetable will be replaced due to changes in replace_triggered_by
   -/+ resource "proxmox_virtual_environment_vm" "jetable" {
   …
   Plan: 1 to add, 1 to change, 1 to destroy.
   ```
   Le `terraform_data` n'est que **modifié** (son `input` change) ; cela suffit à déclencher le remplacement de la VM, qui le référence dans `replace_triggered_by`.
   La nouvelle VM est clonée depuis l'image courante **du jour** : `ignore_changes = [clone]` ignore le changement pour décider s'il faut remplacer, mais une ressource **créée** utilise la valeur actuelle du code (`local.image_vmid`). C'est exactement le « reconstruire à neuf sur l'image du jour » de Nadia.
4. `create_before_destroy` : le plan affiche `+/-` (créer puis détruire). À l'apply, la création de la nouvelle VM 2054 échouerait (« VM 2054 already exists ») puisque l'ancienne vit encore : le VMID et le nom sont fixes. Le méta-argument n'a de sens que pour des objets dont l'identité est générée (VMID choisi par Proxmox, nom avec suffixe), ou pour des objets sans identité unique (le snippet de E19 : un nouveau nom de fichier à chaque contenu).
5. `tofu apply -replace=proxmox_virtual_environment_vm.jetable` : remplacement ponctuel sans changer le code (dépannage, VM abîmée). Le déclencheur, lui, est **dans le code** : relu en MR, historisé, rejoué par la chaîne. Pour une reconstruction planifiée, le déclencheur ; pour une réparation, `-replace`.
6. `depends_on = [module.bdd]` sur une source de données : OpenTofu ne peut plus la lire au plan dès que `module.bdd` a un changement en attente ; il la lit « during apply ». Tout ce qui dépend de cette lecture devient « known after apply » : modification sur place à chaque plan, et **remplacement** si la valeur alimente un attribut à remplacement forcé (plan 5 de E22). On remplace `depends_on` par une vraie référence, ou on retire la dépendance. `prevent_destroy` ne peut pas venir d'une variable parce qu'OpenTofu évalue les blocs `lifecycle` avant les variables : la protection doit être visible dans le code, pas dépendre d'une valeur passée à l'exécution.

**Explications**

- **Dépendances implicites** : toute référence (`a.b.c`) crée une arête. C'est le cas normal, et le seul qui dise **pourquoi** l'ordre compte. `depends_on` sert quand la dépendance est réelle mais invisible (un rôle Proxmox qui doit exister avant l'ACL qui l'utilise, sans attribut à référencer).
- **Préconditions et postconditions** : des assertions attachées à une ressource, évaluées au plan (avant) ou à l'apply (après). Elles transforment une hypothèse implicite (« l'image courante est une Debian », « la VM a une adresse ») en échec clair.
- **Ordre `-/+` par défaut** : détruire puis créer, parce que la plupart des objets ont une identité unique. `create_before_destroy` inverse l'ordre quand c'est possible.

**Alternatives**

- `tofu taint` (déprécié) : marque une ressource à remplacer au prochain apply ; remplacé par `-replace`, qui se voit au plan.
- Un `check` (hors ressource) au lieu d'une postcondition : avertit sans bloquer, utile pour ce qui peut s'arranger seul (une VM qui met du temps à démarrer un service).

**Pièges classiques**

- Un `depends_on` ajouté « pour être sûr » sur une source de données : plans instables, remplacements surprises.
- Une postcondition sur un attribut que l'agent QEMU remplit **après** l'apply (adresse IPv6, service applicatif) : échec aléatoire.
- Oublier que `replace_triggered_by` recrée aussi au **premier** changement de la ressource de déclenchement, y compris son passage d'une version d'OpenTofu à une autre si son contenu change.

**En production chez MédiSphère**

- Les environnements jetables sont reconstruits chaque semaine sur la nouvelle image dorée, par un pipeline planifié qui change la génération (même principe), avec leurs tests.
- Les VMs durables, elles, ne sont jamais remplacées automatiquement : une nouvelle image s'applique par une MR qui cible une VM à la fois (`-replace` dans un job manuel).

---

### M05-E19 — cloud-init généré et snippets gérés par le code

**Solution**

1. La documentation du provider liste ce qui demande SSH : envoi de snippets (et de certains types de fichiers), import d'un disque par `source_file.path`, `idmap` des conteneurs. Le provider ouvre une session SSH sur le nœud et exécute `try_sudo /usr/bin/tee <chemin du stockage>/snippets/<nom>` (vérifié dans le code du provider 0.115 : mode `stream`, par défaut), après un test de `sudo -n /usr/sbin/pvesm apiinfo`. `sudo` sur `qm` ou `pvesm` entiers revient à donner root (`qm` lance des commandes sur les VMs, `pvesm` alloue et libère des volumes, et tous deux lisent des fichiers arbitraires) : la documentation du provider le déconseille expressément.
2. Préparation : [`fichiers/M05-E19/pve01/preparer-snippets-tofu.sh`](fichiers/M05-E19/pve01/preparer-snippets-tofu.sh) (rejouable) :
   ```
   root@pve01:~# CLE_PUBLIQUE='ssh-ed25519 AAAA… admin@adm01' ./preparer-snippets-tofu.sh   # contenu de ~/.ssh/id_ed25519.pub d'adm01
   ```
   Il crée le stockage `tofu-snippets` (`pvesm add dir … --content snippets --is_mountpoint /mnt/hdd-bulk`), le compte `wb-tofu` (sans mot de passe : connexion par clé seulement, `from="10.10.10.10"`), le fichier sudoers **validé avant installation** :
   ```
   wb-tofu ALL=(root) NOPASSWD: /usr/sbin/pvesm apiinfo
   wb-tofu ALL=(root) NOPASSWD: /usr/bin/tee /mnt/hdd-bulk/tofu-snippets/snippets/[a-zA-Z0-9_][a-zA-Z0-9_.-]*
   ```
   et le rôle `WBTofuSnippets` (`Datastore.Allocate`, `Datastore.AllocateSpace`, `Datastore.Audit`) sur `/storage/tofu-snippets`, pour l'utilisateur **et** le jeton (séparation des privilèges, E03). Contrôles :
   ```
   root@pve01:~# pveum user token permissions wb-tofu@pve tofu --path /storage/hdd-bulk
   root@pve01:~# pveum user token permissions wb-tofu@pve tofu --path /storage/tofu-snippets
   ```
   Sur `hdd-bulk` : `Datastore.AllocateSpace` et `Datastore.Audit` seulement (E03, E10) ; sur `tofu-snippets` : en plus `Datastore.Allocate`. Puis, depuis `adm01` :
   ```
   admin@adm01:~$ ssh -o ControlPath=none wb-tofu@<IP-PVE01> sudo -n /usr/sbin/pvesm apiinfo
   APIVER 12
   APIAGE 3
   ```
   (Valeurs d'`APIVER` indicatives.)
3. Provider : [`envs/lab-m05/providers.tf`](fichiers/M05-E19/infra/envs/lab-m05/providers.tf) — `ssh { agent = true, username = "wb-tofu", node { name = var.noeud, address = var.pve01_ssh } }`. Sans le bloc `node`, le provider cherche l'adresse du nœud par l'API (interfaces réseau), ce que le jeton n'a pas le droit de lire. L'état `socle` n'a **aucun** snippet : il reste applicable par le pipeline (E26), et `runner01` n'a aucun accès SSH à `pve01` (rien à ouvrir, ni dans `gw01`, ni dans le pare-feu Proxmox). Conséquence acceptée : `envs/lab-m05` ne s'applique que depuis `adm01`.
4. Gabarit [`templates/user-data.yaml.tftpl`](fichiers/M05-E19/infra/envs/lab-m05/templates/user-data.yaml.tftpl) et ressource [`cloud-init.tf`](fichiers/M05-E19/infra/envs/lab-m05/cloud-init.tf). Validation avant envoi :
   ```
   admin@adm01:~/src/infra/envs/lab-m05$ echo 'local.user_data_jetable' | tofu console > ~/m05/e19/user-data.yaml
   admin@adm01:~/src/infra/envs/lab-m05$ sed -i '1s/^<<EOT$//;$s/^EOT$//' ~/m05/e19/user-data.yaml   # selon la forme affichée par la console
   admin@adm01:~/src/infra/envs/lab-m05$ cloud-init schema -c ~/m05/e19/user-data.yaml
   Valid schema /home/admin/m05/e19/user-data.yaml
   ```
   (Plus simple : une sortie temporaire `output "user_data" { value = local.user_data_jetable }` et `tofu output -raw user_data`. Le rendu de référence a été validé par `cloud-init schema`.)
5. VM : [`cycle-de-vie.tf`](fichiers/M05-E19/infra/envs/lab-m05/cycle-de-vie.tf) remplace `user_account` par `user_data_file_id = proxmox_virtual_environment_file.user_data_jetable.id`. Plan : la VM est **remplacée**, `user_data_file_id … # forces replacement` (attribut à remplacement forcé dans le schéma du provider) : Proxmox ne rejoue pas cloud-init sur une VM déjà initialisée, le provider le sait.
6. Le piège : contenu changé, nom fixe → le **fichier** est remplacé (son contenu est à remplacement forcé), mais son identifiant (`tofu-snippets:snippets/m05-jetable.yaml`) ne change pas : la VM n'est pas touchée. Elle garde l'ancien cloud-init (déjà exécuté), alors que le code et le fichier disent autre chose : une dérive invisible au plan. Correction (version de référence) : empreinte du contenu dans le nom, `file_name = "m05-jetable-${substr(sha256(local.user_data_jetable), 0, 12)}.yaml"`, et `create_before_destroy = true` sur le fichier (le nouveau existe avant que l'ancien disparaisse ; si la recréation de la VM échoue, l'ancienne VM a toujours un snippet valide pour redémarrer).
7. Contrôle dans la VM :
   ```
   root@pve01:~# qm config 2054 | grep cicustom
   cicustom: user=tofu-snippets:snippets/m05-jetable-4be1a07c93d2.yaml
   root@pve01:~# qm guest exec 2054 -- cat /etc/medisphere/generation
   {
      "exitcode" : 0,
      "exited" : 1,
      "out-data" : "generation=2026-10-19\ncree_par=opentofu\n"
   }
   root@pve01:~# qm guest exec 2054 -- cloud-init status
   ```

**Explications**

- **Pourquoi SSH** : l'API de Proxmox n'accepte en téléversement que les ISO, modèles de conteneurs et images à importer. Les snippets doivent être écrits dans le dossier du stockage, sur le nœud.
- **Pourquoi `Datastore.Allocate`** : le provider lit le chemin du stockage par `GET /storage/{id}`, et Proxmox exige ce privilège pour cette lecture (contrôle relevé dans la documentation de l'API de PVE 9) ; la suppression d'un snippet par l'API et la vérification d'accès quand une VM référence un snippet passent aussi par lui (dans le code de `PVE::Storage`, un volume de type `snippets` n'est accessible qu'avec `Datastore.Allocate`). Sur un stockage **dédié**, ce privilège ne donne accès qu'aux snippets d'OpenTofu ; sur `hdd-bulk`, il permettrait de supprimer le disque de données de `s3-01`.
- **Un snippet *user-data* remplace** tout ce que Proxmox génère pour l'utilisateur (`ciuser`, `sshkeys`, mot de passe) ; le réseau (`ipconfig0`) et les métadonnées restent générés. D'où le compte `admin` et les clés **dans** le gabarit.

**Alternatives**

- *Vendor-data* plutôt que *user-data* : garde les comptes de Proxmox (`user_account`) et ajoute paquets et fichiers ; c'est ce que fait le template 9000 (M00-E11). Très bien pour du commun à toutes les VMs.
- Pas de snippet du tout : `user_account` + Ansible après création (E23). Moins de pièces, et le cloud-init reste minimal ; c'est le choix du socle.
- Images plus complètes (Packer, M03) : ce qui est identique partout va dans l'image, pas dans cloud-init.

**Pièges classiques**

- Règle sudoers `tee /var/lib/vz/*` copiée d'un tutoriel : chemin du stockage `local`, pas du nôtre, et motif trop large (`*` accepte `../`).
- Oublier `-o ControlPath=none` en testant la connexion de `wb-tofu` : le multiplexage SSH réutilise la connexion de `root@pve01` et le test « réussit » à tort.
- Clé de `admin@adm01` non chargée dans l'agent : le provider échoue sur « unable to authenticate » au moment de l'envoi, pas avant.
- Le provider accepte une clé d'hôte inconnue et l'ajoute à `~/.ssh/known_hosts` (vérifié dans son code) ; il refuse une clé **changée** : un `pve01` réinstallé bloque l'envoi des snippets jusqu'à ce qu'on vérifie et mette à jour la clé.
- `file_mode` sur la ressource fichier : réservé à `root@pam`, refusé avec un jeton.

**En production chez MédiSphère**

- Snippets génériques (*vendor-data*) dans l'image ou gérés une fois par Ansible sur les nœuds ; *user-data* par VM réservé aux cas qui le justifient.
- Sur un cluster (module 09), les snippets doivent exister sur **chaque** nœud où la VM peut démarrer : stockage partagé (CephFS, NFS) ou dépôt sur tous les nœuds.
- Le compte SSH `wb-tofu` inscrit au registre des secrets (clé autorisée, portée, sudoers) et revu à chaque audit.

---

### M05-E20 — Qualité du code : fmt, validate, tflint, terraform-docs

**Solution**

1. Installation (même méthode que terraform-docs en E13) :
   ```
   admin@adm01:~/m05/e20$ curl -fLO https://github.com/terraform-linters/tflint/releases/download/v0.64.0/tflint_linux_amd64.zip
   admin@adm01:~/m05/e20$ curl -fLO https://github.com/terraform-linters/tflint/releases/download/v0.64.0/checksums.txt
   admin@adm01:~/m05/e20$ sha256sum --ignore-missing -c checksums.txt
   tflint_linux_amd64.zip: OK
   admin@adm01:~/m05/e20$ unzip tflint_linux_amd64.zip && sudo install -m 755 tflint /usr/local/bin/
   admin@adm01:~$ tflint --version
   TFLint version 0.64.0
   + ruleset.terraform (0.15.0-bundled)
   ```
   (Noms des fichiers de la page des versions : ⚠️ à vérifier.) À nu, tflint signale typiquement une variable déclarée et inutilisée, une sortie sans description, une contrainte de version absente dans un exemple.
2. [`infra/.tflint.hcl`](fichiers/M05-E20/infra/.tflint.hcl) et [`tofu-modules/.tflint.hcl`](fichiers/M05-E20/tofu-modules/.tflint.hcl). Activées : `recommended`, `terraform_naming_convention` (`snake_case`), `terraform_documented_variables`/`outputs`, `terraform_typed_variables`, `terraform_required_version`/`providers`, `terraform_module_pinned_source` (style `semver` : `?ref=main` refusé), `terraform_unused_declarations`, `terraform_comment_syntax` ; `terraform_standard_module_structure` désactivée dans `infra` (nos racines répartissent le code en plusieurs fichiers), activée dans `tofu-modules`. `call_module_type = "all"` : tflint inspecte aussi les appels de modules (variables mal passées). Corrections faites sur le code de référence : `images.tf` supprimé de `socle/` (inutilisé depuis E17), exemple du module restructuré (`variables.tf`, `outputs.tf`, `required_version`). Résultat : aucune alerte.
3. [`outils/tofu-valider.sh`](fichiers/M05-E20/infra/outils/tofu-valider.sh) (testé) : pour chaque dossier contenant des `.tf`, `tofu init -backend=false` dans un `TF_DATA_DIR` jetable, `-lockfile=readonly` s'il y a un fichier de verrouillage, et suppression du fichier de verrouillage que `init` crée dans un module qui n'en avait pas ; [`outils/docs-verifier.sh`](fichiers/M05-E20/infra/outils/docs-verifier.sh) : `terraform-docs --output-check` sur chaque README à marqueurs. README de `socle/` : [`socle/README.md`](fichiers/M05-E20/infra/socle/README.md) (texte écrit à la main, tableau généré).
4. Hooks : [`infra/.pre-commit-hooks-opentofu.yaml`](fichiers/M05-E20/infra/.pre-commit-hooks-opentofu.yaml) et [`tofu-modules/.pre-commit-hooks-opentofu.yaml`](fichiers/M05-E20/tofu-modules/.pre-commit-hooks-opentofu.yaml), à ajouter à la liste `repos:` (YAML fusionné vérifié). Hooks **locaux** (`language: system`) : ils utilisent les versions installées et figées par l'équipe ; un dépôt de hooks tiers (`pre-commit-terraform`) est un logiciel de plus à épingler par empreinte et à surveiller, et il appelle `terraform` par défaut. Essai :
   ```
   admin@adm01:~/src/infra$ sed -i 's/^  vm_id = 1006/vm_id=1006/' socle/s3-01.tf; git commit -am "test: format"
   tofu fmt (format canonique)..............................................Failed
   - hook id: tofu-fmt
   - exit code: 3
   socle/s3-01.tf
   ```
5. [`gitlab-ci-extrait.yml`](fichiers/M05-E20/infra/gitlab-ci-extrait.yml) : `variables: SKIP: tofu-fmt,tofu-validate,tflint,terraform-docs`, retiré en E26. Pipelines de `main` verts. Pour `tofu-modules`, ajouter aussi [`.gitignore-extrait`](fichiers/M05-E20/tofu-modules/.gitignore-extrait) (`.terraform.lock.hcl` ignoré dans un dépôt de modules).

**Explications**

- **`tofu fmt`** : un seul format, pas de discussion de style en revue. **`tofu validate`** : la configuration est cohérente (types, références, arguments connus du **schéma du provider**) ; il ne contacte aucune API. **tflint** : ce que `validate` accepte mais que l'équipe refuse (nommage, documentation, versions, déclarations inutiles, sources non épinglées). **terraform-docs** : la documentation suit le code, et `--output-check` empêche qu'elle s'en écarte.
- **`TF_DATA_DIR`** déplace `.terraform/` (providers, modules, configuration du backend) ; le fichier de verrouillage, lui, reste dans le dossier courant : d'où le traitement particulier dans le script.

**Alternatives**

- `pre-commit-terraform` (antonbabenko) : très complet, supporte OpenTofu par une option ; une dépendance de plus.
- Checkov, Trivy (E25) : sécurité ; complémentaires de tflint, pas des remplaçants.

**Pièges classiques**

- Lancer `tofu init` dans le hook avec le backend : il faudrait les identifiants S3 sur chaque poste et dans la CI de MR, et il risquerait de toucher la configuration du backend.
- `tflint --recursive` sans `--config` absolu : chaque dossier cherche son propre `.tflint.hcl`.
- `call_module_type = "all"` sur une copie où `tofu init` n'a jamais été lancé : tflint ne trouve pas les modules Git téléchargés et le dit.
- Hooks installés dans un dépôt mais pas dans l'autre : vérifier `pre-commit install` dans chaque clone.

**En production chez MédiSphère**

- Les mêmes outils en CI (E26), aux mêmes versions que sur les postes (fichier de versions commun, E26), et une règle de protection : pas de fusion si un de ces jobs échoue.
- Règles tflint propres à l'entreprise (un *plugin* de règles maison : étiquettes obligatoires, plages de VMID) quand le module ne suffit plus.

---

### M05-E21 — Revue de la MR OpenTofu d'un stagiaire

**Solution**

**Avant de répondre à Lucas** (dans cet ordre) :
1. **Le jeton `wb-tofu@pve!tofu` est exposé** dans `envs/supervision/providers.tf`, poussé sur la forge (donc dans les miroirs, les caches de runner, les clones des collègues). On le considère compromis : **révocation immédiate** (`pveum user token remove wb-tofu@pve tofu`), nouveau jeton (`JETON=tofu2 ./pve-tofu-compte.sh`, E03), mise à jour de `pve-tofu.env` et des variables CI, lecture du journal de tâches de `pve01` pour l'usage du jeton depuis la poussée. Réécrire l'historique de la branche ne suffit **pas** (la valeur a circulé) ; on le fait quand même avant fusion (branche supprimée, MR recréée), et on signale l'incident (registre des secrets, Sophie).
2. **Le mot de passe `Medisphere2026!`** est dans le code **et** dans un état commité : s'il a été appliqué (Lucas dit avoir fait l'apply des VMs Grafana), il est actif sur des VMs. Changer le mot de passe / verrouiller le compte sur les VMs concernées, puis les détruire avec le reste de l'essai ; vérifier qu'il n'est réutilisé nulle part.
3. **Les VMs créées « chez lui »** (2058, 2059 d'après l'état commité) existent hors de tout état partagé, avec un état local dans Git : les inventorier (`qm list`), les détruire proprement (par l'état local récupéré, ou à la main avec le ticket), et s'assurer qu'aucun état n'a été écrit sous la clé de `lab-m05` (voir le défaut bloquant n° 1).

**Défauts relevés** (fichier, gravité, risque, correction) :

| # | Où | Gravité | Risque | Correction |
|---|---|---|---|---|
| 1 | `backend.tf` copié, clé `envs/lab-m05/terraform.tfstate` | **bloquant** | deux configurations, **un** état : le premier plan de `envs/supervision` voit les VMs de `lab-m05` « hors configuration » et propose de les **détruire** ; un apply écrase l'état de `lab-m05` | clé `envs/supervision/terraform.tfstate` ; vérifier l'état de `lab-m05` (versions S3) |
| 2 | `providers.tf` : `api_token = "wb-tofu@pve!tofu=…"` | **bloquant** | secret dans Git (voir ci-dessus) | rien d'autre que `insecure = false` ; accès par `PROXMOX_VE_*` |
| 3 | `providers.tf` : `insecure = true` | **bloquant** | TLS non vérifié : interception du jeton possible | ancre TLS de `pve01` installée (M03-E02) ; on ne contourne pas, on corrige le poste |
| 4 | `providers.tf` : `endpoint` avec une IP en dur | mineur | adresse propre au lab dans le code, différente selon le poste | `PROXMOX_VE_ENDPOINT` |
| 5 | `terraform.tfstate` commité, `.gitignore` affaibli | **bloquant** | état (et mot de passe en clair) dans l'historique ; second état divergent de toute vérité | supprimer le fichier, restaurer `.gitignore`, réécrire la branche ; état distant seulement |
| 6 | `user_account.password` en clair | **bloquant** | secret dans le code et l'état ; connexion par mot de passe | clés SSH (`var.cles_ssh_admin`), jamais de mot de passe |
| 7 | `versions.tf` : pas de `required_version`, provider `>= 0.100.0` ; `.terraform.lock.hcl` mis dans `.gitignore` | majeur | n'importe quelle version d'OpenTofu ; provider non épinglé (0.116 existe déjà, 0.x = ruptures) ; versions différentes d'un poste à l'autre | `~> 1.13.0`, `~> 0.115.0`, fichier de verrouillage versionné |
| 8 | `module "prometheus"` : `?ref=main` | majeur | le module change sous nos pieds | étiquette `?ref=vX.Y.Z` (E14) |
| 9 | Prometheus : `vm_id = 1009`, `socle = true`, rôle `supervision`, `10.10.20.19` | **bloquant** | VMID et adresse **hors PLAN** (plage du socle sans décision ; 1009 non attribué) ; l'étiquette `socle` fait entrer la VM dans l'inventaire du socle : le garde-fou de `site.yml` (six hôtes) bloque **toute** application Ansible du socle | VM d'environnement (2050-2059, `env-m05`, `vsandbox`) ; un hôte permanent passe par PLAN.md, un ADR et un ticket |
| 10 | Prometheus : clé `lucas@portable` | majeur | accès d'un poste personnel, hors `adm01` | `var.cles_ssh_admin` |
| 11 | `noeud = "pve01"` et `node_name = "pve01"` en dur | mineur | faux si le nœud s'appelle autrement | `var.noeud` |
| 12 | Grafana : `clone { full = false }` | majeur | clone **lié** : le template doré ne peut plus être supprimé, la VM en dépend (règle M03) | `full = true` |
| 13 | Grafana : pas d'`ignore_changes = [clone]` | majeur | la semaine suivante (nouvelle image `current`), le plan **recrée** les deux VMs | `ignore_changes = [clone]`, ou le module |
| 14 | Source de données sans filtre `template` ni postcondition | majeur | un clone qui a hérité des étiquettes `gold`/`current` peut être pris pour l'image ; zéro ou deux résultats = erreur obscure | filtre `template = true` et postcondition « exactement un » (E08) |
| 15 | Grafana : matériel non déclaré (pas de `cpu.type`, `scsi_hardware`, `operating_system`, console) | majeur | valeurs par défaut du provider (`qemu64`, `virtio-scsi-pci`…) : VM différente de l'image | le module, ou le matériel complet (E10) |
| 16 | Grafana : étiquettes non triées, `pool_id` et VNet en dur | mineur | écart à chaque plan (Proxmox trie) | `sort()`, variables |
| 17 | Grafana : `count` + `vm_id = 2058 + count.index`, noms `grafana-0` | majeur | retirer la première VM renumérote et **recrée** la seconde ; noms hors convention (`m05-…`) ; 2058-2059 réservés au palier 3 | `for_each` sur une table (nom → VMID), noms `m05-grafana01` |
| 18 | `provisioner "local-exec"` avec `StrictHostKeyChecking=no`, `sleep 60`, chemin vers un autre dépôt, `ipv4_addresses[1][0]` | majeur | règle M04 violée (clés d'hôte) ; un échec du playbook **marque la VM à remplacer** ; dépend du poste de Lucas ; ordre et index fragiles | pas de provisioner : étiquettes + inventaire dynamique + playbook (E23) |
| 19 | Pas de garde-fou sur les VMID (validation) | mineur | erreur de saisie vue seulement à l'apply | variables validées (E06) ou le module |
| 20 | Messages de commit `feat: supervision`, `fix: ca marche chez moi` | mineur | historique inexploitable ; un `fix` qui ajoute un état n'est pas un correctif | `feat(supervision): …` avec un corps qui explique ; un commit par intention |
| 21 | Description de MR : « apply fait depuis la branche », pipeline rouge « juste le formatage », pas de plan | **bloquant** (processus) | apply hors chaîne, sans relecture ; le pipeline rouge signale aussi Gitleaks | aucun apply hors `main` ; plan collé dans la MR ; pipeline vert |

**Réponse à Lucas** (exemple) : « Merci pour la MR, l'intention est bonne et la structure se lit bien. Avant tout : ton jeton Proxmox et le mot de passe se sont retrouvés sur la forge, on les a révoqués ensemble ce matin (rien de grave si on réagit vite, c'est pour ça qu'on a un registre des secrets). Pour la suite : repars de `envs/lab-m05` en changeant la clé du backend (lis le commentaire n° 1, c'est le plus important), utilise le module `vm-debian` à la dernière version (il règle d'un coup les défauts 12 à 16), et laisse Ansible configurer Grafana après création (E23). Les conventions sont dans l'introduction du module 05 et dans `CONTRIBUTING.md` ; viens me voir pour relire le prochain plan ensemble avant de pousser. »

Grille d'auto-évaluation : 2 points par défaut **bloquant** trouvé (8 : n° 1, 2, 3, 5, 6, 9, 21, et la section « avant de répondre »), 1 point par autre défaut, 2 points si chaque commentaire dit le risque **et** la correction, 2 points pour l'ordre de la section « avant de répondre » (révocation d'abord). 25 points et plus : revue de niveau équipe Plateforme.

**Explications**

- Le défaut le plus grave n'est pas le plus visible : un **état partagé par erreur** ne se voit pas dans le diff (le fichier `backend.tf` est identique à celui de `lab-m05` : c'est justement le problème).
- Un secret poussé est un **incident** avant d'être un commentaire de revue : on traite la fuite, puis le code.

**Alternatives**

- Une revue « par pair » avec Lucas devant le plan, plutôt qu'écrite : plus pédagogique pour un premier passage ; l'écrit reste pour la trace.

**Pièges classiques**

- Commenter la forme (indentation, noms) et rater l'état partagé.
- Demander à Lucas de « retirer le secret dans un nouveau commit » : il reste dans l'historique.

**En production chez MédiSphère**

- Gitleaks avec une règle pour les jetons Proxmox (`[a-z0-9-]+@(pve|pam)![a-z0-9]+=[0-9a-f-]{36}`) dans `.gitleaks.toml` : le pre-commit et la CI auraient arrêté le défaut n° 2.
- Un job CI qui refuse toute MR ajoutant un `*.tfstate`, un `provisioner`, ou une clé de backend déjà utilisée par un autre dossier.

---

### M05-E22 — Lire un plan comme un relecteur

**Réponses**

1. **Plan 1.** Lucas a remplacé le *vendor-data* de `dns01` (`vendor-debian13.yaml` → `vendor-socle.yaml`). L'attribut `initialization.vendor_data_file_id` est à **remplacement forcé** (`# forces replacement`) : pour OpenTofu, le seul moyen d'appliquer est de **détruire et recréer** `dns01`. `prevent_destroy` a fait échouer le plan : rien n'est appliqué. Sans lui : `dns01` détruite (disque, configuration dnsmasq, baux DHCP), puis recréée vierge depuis l'image courante — tout le lab sans DNS pendant la recréation, et un `dns01` à reconfigurer par Ansible ; si Lucas avait changé la valeur pour les quatre VMs, les quatre y passaient. Options : (a) changer le snippet **lui-même** (même nom de fichier, contenu nouveau) n'a aucun effet sur des VMs déjà initialisées : cloud-init ne le rejoue pas ; (b) appliquer le changement voulu (paquets, fichiers) par **Ansible** sur les VMs existantes, et réserver le nouveau *vendor-data* aux VMs **créées** ensuite ; (c) si l'on tient à aligner la configuration Proxmox, `ignore_changes` sur cet attribut pour les VMs importées, ou une reconstruction planifiée VM par VM (fenêtre, instantané, `-replace`).
2. **Plan 2.** Oui, on peut l'appliquer : `has moved to` (refactorisation E17) et une seule modification sur place, la `description`. L'apply change le texte des notes de la VM 1006 dans Proxmox (`qm set 1006 --description …`) et met à jour l'adresse dans l'état. Ni `+` ni `-` : le bloc `moved` a dit à OpenTofu que l'objet existant **est** la ressource à la nouvelle adresse.
3. **Plan 3.** L'image dorée `current` a changé le week-end (publication hebdomadaire, M03 : 9012 → 9013). `clone.vm_id` suit la source de données ; c'est un attribut à remplacement forcé, et la ressource `lucas_test` n'a pas `ignore_changes = [clone]`. Si la détection de dérive appliquait automatiquement, on perdrait la VM et tout ce qu'elle contient (données de test, configuration faite à la main), recréée vierge. Une détection de dérive **signale**, elle n'applique pas (E28).
4. **Plan 4.** Cette nuit, quelqu'un a augmenté la mémoire de `m05-app02` à la main (1024 → 4096 Mo, `qm set`) et **supprimé** `m05-app03` (`qm destroy`), hors OpenTofu. Au rafraîchissement, OpenTofu le constate (« Objects have changed outside of OpenTofu ») ; le plan propose de **remettre** 1024 Mo sur `app02` et de **recréer** `app03` (sur l'image courante, 9013). Sur `app02`, réduire la mémoire d'une VM en marche sans *hotplug* exige un arrêt : le provider redémarre la VM (`reboot_after_update`, vrai par défaut) — ⚠️ à vérifier selon la configuration de *hotplug* de tes VMs. Conseil : **ne pas appliquer** tel quel. D'abord savoir pourquoi (incident de la nuit, ticket, Nadia) : si 4096 Mo étaient nécessaires, on les met dans le code (MR) ; si `app03` devait disparaître, on la retire du code ; sinon on applique en connaissance de cause, dans une fenêtre.
5. **Plan 5.** La source de données `base_prete` porte un `depends_on` vers le module `bdd` (ou dépend d'une valeur qu'il produit) ; comme `module.bdd` a un changement en attente (mémoire 2048 → 4096), OpenTofu ne peut pas la lire au plan : « will be read during apply ». Tout ce qui l'utilise devient inconnu : la `description` de `m05-rec-api` (qui cite la VM de base) passe à `(known after apply)`, donc modification sur place à **chaque** plan où `bdd` change. Si cette valeur alimentait un attribut à remplacement forcé (`clone.vm_id`, `user_data_file_id`, `node_name`…), `m05-rec-api` serait **remplacée**. Correction : retirer le `depends_on` (la source de données ne dépend réellement de rien qui soit créé par ce plan) ou remplacer la lecture par une **référence directe** à la sortie du module (`module.bdd.vm_id`, connue au plan).
6. **Plan 6.**

   | Entrée | Symbole | Phrase | Bloque ? |
   |---|---|---|---|
   | `socle["adm01"]` no-op + importing | (import) | importée, aucun changement | non |
   | `socle["dns01"]` update + importing | `~` | importée **et modifiée** dans le même apply | **oui** (import pur exigé, E16) |
   | `socle["git01"]` no-op + importing | (import) | importée, aucun changement | non |
   | `socle["runner01"]` delete, create + `replace_because_cannot_update` + importing | `-/+` | importée puis **détruite et recréée** | **oui** (et `prevent_destroy` l'arrêterait) |
   | `module.s3_01…vm` no-op + `previous_address` | `has moved to` | déplacée, rien d'autre | non |
   | `essai_karim` forget | `will be removed from the OpenTofu state` | sortie de la gestion, non détruite | à vérifier : voulu ? (bloc `removed`) |

   Filtre d'un job CI :
   ```
   tofu show -json plan.tfplan \
     | jq -e '[.resource_changes[] | select(.change.actions | index("delete"))] | length == 0'
   ```
   `jq -e` renvoie 1 si l'expression est `false` : le job échoue dès qu'une action contient `delete` (destruction **et** remplacement, dans les deux ordres `["delete","create"]` et `["create","delete"]`). Il **laisse passer** à tort : un `update` qui redémarre une VM, un `forget` (objet abandonné), un import modifié (`dns01`). Il **bloque** à tort : la destruction voulue d'une VM d'environnement (à exclure par préfixe d'adresse ou en ne l'appliquant qu'à `socle/`).
7. **Du plus anodin au plus dangereux pour une VM du socle** :
   - `<=` : lecture d'une source de données (pendant l'apply : surveiller ce qui en dépend) ;
   - `has moved to` : nouvelle adresse, même objet ;
   - `+` : création (vérifier VMID et adresse) ;
   - `(known after apply)` : valeur calculée plus tard — anodin sur un attribut calculé, inquiétant sur un attribut à remplacement forcé ;
   - `Objects have changed outside of OpenTofu` : dérive constatée ; le plan qui suit va la **défaire** ;
   - `~` : modification sur place (peut redémarrer la VM) ;
   - `will be removed from the OpenTofu state but will not be destroyed` : la VM sort du code, plus personne ne la gère ;
   - `+/-` : remplacement, création d'abord (coupure courte, si l'identité le permet) ;
   - `# forces replacement` : la ligne qui explique **pourquoi** une VM sera remplacée ;
   - `-/+` : destruction **puis** création : disque perdu, coupure ;
   - `-` : destruction.

**Explications**

- Lire un plan, c'est d'abord chercher les mots `replace`, `destroy`, `forces replacement`, `forget`, puis lire les `~` sur les VMs du socle, puis la dérive. La ligne `Plan: X to add, Y to change, Z to destroy` résume, mais ne dit pas **quoi**.
- La version JSON (`tofu show -json`) est la seule forme stable pour un contrôle automatique ; le texte peut changer d'une version à l'autre.

**Alternatives**

- Politiques de plan avec OPA/conftest (module 29) : règles plus riches que `jq` (adresses autorisées, attributs sensibles).

**Pièges classiques**

- Ne regarder que le résumé (`1 to change`) : le plan 2 et un redémarrage forcé ont le même résumé.
- Appliquer un plan de dérive « pour revenir à l'état du code » sans savoir pourquoi la réalité a changé.

**En production chez MédiSphère**

- Le job `plan` de la CI publie le JSON, un job de contrôle applique le filtre ci-dessus sur `socle/`, et la MR affiche le résumé (rapport `terraform` de GitLab, E26).

---

### M05-E23 — De OpenTofu à Ansible : inventaire et configuration après création

**Solution**

1. Le filtre de `proxmox.yml` (M04-E13) ne retient que `socle` et `env-m04` : les VMs `env-m05` sont exclues. Nouveau filtre ([extrait](fichiers/M05-E23/ansible/inventories/lab/proxmox-extrait.yml)) :
   ```yaml
   filters:
     - not proxmox_template
     - >-
       'socle' in (proxmox_tags_parsed | default([]))
       or (proxmox_tags_parsed | default([]) | select('match', '^env-m[0-9]{2}$') | list | length) > 0
     - "'molecule' not in (proxmox_tags_parsed | default([]))"
   ```
   `socle` reste à **six** hôtes (les VMs d'environnement n'ont pas l'étiquette `socle`) : le garde-fou de `site.yml` tient.
2. Adresse :
   ```yaml
   compose:
     ansible_host: >-
       (proxmox_ipconfig0.ip.split('/') | first)
       if (proxmox_ipconfig0.ip | default('dhcp')) != 'dhcp'
       else (proxmox_agent_interfaces | default([])
             | rejectattr('name', 'equalto', 'lo')
             | map(attribute='ip-addresses') | flatten
             | select('match', '^10[.]10[.]')
             | first | default('')).split('/') | first
   ```
   Expression évaluée sur des données réalistes : `10.10.20.14` pour une IP statique, `10.10.99.142` pour une VM en DHCP (le plugin rend les adresses de l'agent sous la forme `10.10.99.142/24`), vide si l'agent ne répond pas. Avec `'^10\\.10\\.'` dans du YAML replié, l'échappement est mangé une fois de trop et rien ne correspond (essayé) : la classe `[.]` évite la question. Vérification :
   ```
   admin@adm01:~/src/ansible$ uv run ansible-inventory --host m05-jetable | jq -r .ansible_host
   10.10.99.142
   ```
   ⚠️ À vérifier : le rôle `WBAnsible` de `wb-ansible` doit permettre de lire les interfaces de l'agent (`VM.GuestAgent.Audit` sur PVE 9) ; sinon le plugin n'obtient rien, sans erreur.
3. Clés d'hôte : [`group_vars/env_m05/connexion.yml`](fichiers/M05-E23/ansible/inventories/lab/group_vars/env_m05/connexion.yml), `StrictHostKeyChecking=accept-new` dans un `known_hosts` **dédié** (`~/.ssh/known_hosts_env-m05`), purgé après chaque `tofu destroy` : une clé inconnue est acceptée (VM neuve), une clé **qui change** pour une adresse connue est refusée. Même raisonnement que Molecule (M04-E24). Alternative plus stricte : publier la clé d'hôte de la VM par cloud-init dans les métadonnées et la lire par l'agent avant la première connexion.
4. [`playbooks/env-m05.yml`](fichiers/M05-E23/ansible/playbooks/env-m05.yml) : `wait_for_connection`, `cloud-init status --wait` (sinon `apt` du rôle `base` se heurte au verrou de cloud-init qui installe encore ses paquets), puis le rôle `base`. `ansible-lint` profil `production` : vert.
5. Sortie [`hotes_ansible`](fichiers/M05-E23/infra/envs/lab-m05/outputs-extrait.tf) et [`outils/configurer-env.sh`](fichiers/M05-E23/infra/outils/configurer-env.sh) :
   ```
   admin@adm01:~/src/infra$ outils/configurer-env.sh lab-m05
   Hôtes de lab-m05 : m05-app01,m05-app02,m05-app03,m05-jetable
   PLAY [Attendre les VMs fraîchement créées] *****
   …
   PLAY RECAP *********
   m05-jetable : ok=24   changed=11   unreachable=0    failed=0 …
   ```
   (Compte de tâches indicatif.) Un second passage donne `changed=0`.
6. Pas de `provisioner "local-exec"` :
   - **rejouabilité** : le provisioner ne tourne qu'à la **création** ; pour reconfigurer, il faut recréer la VM. Le playbook, lui, se rejoue seul ;
   - **état contaminé** : si le playbook échoue, OpenTofu marque la VM *tainted* et la **recrée** au prochain apply ;
   - **dépendance au poste** : chemin vers un autre dépôt, version d'Ansible, coffre et clés du poste qui lance OpenTofu (et en CI, sur `runner01`, un mélange des droits des deux chaînes) ;
   - **journaux et secrets** : la sortie d'Ansible part dans la sortie d'OpenTofu (et ses artefacts de CI) ;
   - **couplage** : un changement de rôle Ansible déclenche… rien côté OpenTofu, et inversement.
   Un provisioner reste acceptable pour une action **locale, idempotente et sans dépendance** liée à la vie de la ressource (enregistrer la VM dans un outil qui n'a pas de provider, nettoyer un cache à la destruction), et en dernier recours.

**Explications**

- Le **contrat** entre les deux outils, ce sont les **étiquettes** Proxmox : OpenTofu les pose, l'inventaire dynamique les lit. Aucun fichier d'adresses à tenir à jour, aucune recopie.
- OpenTofu crée et détruit ; Ansible configure et maintient. Chacun a son état (l'état d'OpenTofu ; la machine elle-même pour Ansible), sa chaîne, ses journaux. Un script d'enchaînement (ou deux jobs de pipeline) les relie sans les fusionner.

**Alternatives**

- Collection `cloud.terraform` : inventaire lu dans l'état d'OpenTofu (les sorties, ou les ressources). Il faut alors donner à Ansible l'accès en lecture à l'état — qui contient des secrets — et lier Ansible au format de l'état.
- `ansible-pull` lancé par cloud-init : la VM se configure seule au démarrage ; pratique à grande échelle, mais la VM doit pouvoir lire le dépôt et le coffre.
- NetBox (module 06) comme source de vérité : OpenTofu y enregistre la VM, Ansible lit NetBox. C'est la cible du module 06.

**Pièges classiques**

- Laisser la règle `env-m04` et ajouter `env-m05` à côté : chaque module ajoutera la sienne ; le motif `^env-m[0-9]{2}$` règle la question une fois.
- Une VM d'environnement qui porterait `socle` par erreur : le garde-fou de `site.yml` refuse alors de converger le socle (c'était le défaut n° 9 de E21).
- Lancer le playbook pendant que cloud-init tourne encore : `Could not get lock /var/lib/dpkg/lock-frontend`.
- `StrictHostKeyChecking=no` « parce que les VMs changent » : interdit (M04), et inutile avec `accept-new` + `known_hosts` dédié.

**En production chez MédiSphère**

- Deux jobs de pipeline : `apply` (OpenTofu) puis `configurer` (Ansible, limité aux hôtes de la sortie), chacun avec ses variables protégées ; la configuration de la VM est aussi rejouée par la détection de dérive d'Ansible (M04-E29).
- NetBox comme source de l'inventaire à partir du module 06 ; les étiquettes Proxmox restent le lien entre la VM et son rôle.
