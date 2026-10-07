# Module 03 — Corrigé du palier 1 : Découverte

⚠️ Corrigé — à lire après avoir cherché.

Les fichiers complets du projet sont dans [`fichiers/`](fichiers/), rangés par exercice : chaque dossier `M03-EXX/images/` contient les fichiers **tels qu'ils sont à la fin de l'exercice** (un même fichier peut donc évoluer d'un exercice à l'autre).

---

### M03-E01 — Questions : pourquoi des images dorées ?

**1.** *Bake* : tout ce qui est commun est installé et réglé **au moment de construire l'image** ; le clone démarre prêt. *Fry* : on part d'une image minimale et l'on configure **au démarrage** (cloud-init, puis Ansible). Avantages du *bake* : mise en service rapide et prévisible (une VM du socle en une minute au lieu de dix) ; toutes les VMs partent du même état, testé une fois, ce qui est la base d'une preuve pour l'audit HDS ; pas de dépendance aux miroirs Internet ni à `hdd-bulk` au démarrage. Inconvénients : une image vieillit (les correctifs publiés après le build manquent, question 7) ; chaque changement impose une reconstruction et une nouvelle version ; risque de prolifération (question 12). Avantages du *fry* : toujours à jour, une seule image à maintenir, la configuration vit dans un seul outil. Inconvénients : démarrage lent et dépendant du réseau et des miroirs, résultat qui varie selon le jour (deux VMs clonées à une semaine d'écart n'ont pas les mêmes paquets), panne d'un dépôt = plus de création de VM. MédiSphère combine les deux : image dorée pour le socle commun, cloud-init pour l'identité, Ansible (M04) pour le rôle.

**2. Réponse b.** Le certificat **public** de la CA interne est commun à toutes les machines et ne change que rarement : sa place est dans l'image (M03-E09). a) Faux : la clé de l'administrateur dépend de qui administre et change (départs, rotation) ; elle est injectée par cloud-init au clonage. c) Faux : le `machine-id` identifie **une** machine ; le copier dans l'image le donne à tous les clones (question 5). d) Faux : c'est un secret, propre à une instance, qui n'a sa place ni dans une image (lisible par quiconque peut cloner ou lire le stockage) ni sur disque en clair (module 25).

**3.**

| Élément | Où | Pourquoi |
|---|---|---|
| Agent QEMU | image | identique partout, nécessaire dès le premier démarrage (IP, arrêt propre, gel des systèmes de fichiers) |
| Nom d'hôte | cloud-init au clonage | propre à l'instance (Proxmox le dérive du nom de la VM) |
| Adresse IP statique de `git01` | cloud-init au clonage (`ipconfig0`) | propre à l'instance, connue de la source de vérité (puis NetBox, M06) |
| Base durcie de `sshd` | image | commune, et doit être active **avant** la première connexion |
| `gitlab.rb` | Ansible | propre au rôle « forge », évolue, contient des références à des secrets |
| Mot de passe PostgreSQL | jamais sur disque en clair | secret : gestionnaire de secrets (M25), injecté à l'exécution |
| Correctifs du mois | image (reconstruction hebdomadaire) **et** `unattended-upgrades` sur les VMs | l'image part à jour, les VMs le restent |
| Fuseau horaire | image | commun |
| Règles de journalisation | image pour la base (journal persistant), Ansible pour ce qui évolue (envoi centralisé, M22) | |
| Clé privée TLS | jamais dans l'image | secret propre à un serveur, émis par la PKI (ACME, M06) |

**4.** Non, pas au sens du mail. `tpl-debian13` est une image du fournisseur (*genericcloud*) transformée à la main : pas de code, pas de provenance vérifiée (seule la somme `SHA512SUMS` l'a été, pas sa signature), pas de version ni de manifeste, pas de durcissement, pas de test, pas de cycle de vie ; et une partie de son contenu (l'agent QEMU) dépend du *vendor-data* et des miroirs au premier démarrage. C'est un bon template, pas une image dorée.

**5. Réponse b.** Si la VM a démarré, elle a généré ses clés d'hôte SSH et son `machine-id` ; un clone copie le disque, donc les deux. a) Faux : Proxmox génère une nouvelle adresse MAC à chaque clonage. c) Faux : cloud-init, au premier démarrage du clone (nouvel identifiant d'instance), applique le nom de la VM. d) Faux : l'UUID SMBIOS (`smbios1: uuid=…`) est régénéré par Proxmox au clonage.

**6.** (1) Clés d'hôte identiques : un serveur compromis peut se faire passer pour n'importe lequel de ses frères sans que le client SSH ne voie de changement de clé ; les fichiers `known_hosts` deviennent sans valeur. (2) `machine-id` identique : `systemd-networkd` en dérive l'identifiant de client DHCP, donc **plusieurs clones reçoivent la même adresse** du serveur DHCP (M03-E07) ; les journaux centralisés (identifiant `_MACHINE_ID`) et certains outils de supervision confondent les machines. (3) État de cloud-init : selon ce qui reste dans `/var/lib/cloud`, un clone peut se croire déjà initialisé et ignorer sa configuration (M03-E21). Plus généralement, tout ce qui est généré « une fois par machine » (graine aléatoire, identifiants d'agents, clés de chiffrement locales) est partagé.

**7.** De mercredi au dimanche suivant au moins : 4 à 5 jours, si l'image est reconstruite, testée et publiée dès dimanche, et **jamais** pour les VMs déjà déployées tant qu'on ne les met pas à jour (les reconstruire est rare). On réduit le délai côté image par une reconstruction déclenchable à la demande (pipeline manuel, M03-E15) dès qu'un correctif critique sort, et côté VMs par `unattended-upgrades` pour la sécurité (M03-E09) et par une mise à jour orchestrée (Ansible, M04-E25). L'image n'est pas le mécanisme de mise à jour des VMs existantes : elle fixe le point de départ.

**8. Réponse b.** Un clone lié est un instantané du disque du template (LVM-thin : volume *thin* dont le volume `base-…` est l'origine) : il n'écrit que ses différences. Le template ne peut donc plus être supprimé tant que des clones liés existent (Proxmox le refuse… quand il sait le détecter : sur LVM-thin la référence n'est pas inscrite dans le nom du volume, voir M03-E16). a) Faux : c'est la description d'un clone complet. c) Faux : un clone complet copie tout. d) Faux : un template ne se démarre pas, et modifier son disque modifierait ce que voient les clones liés : Proxmox l'interdit.

**9.** Depuis l'ISO, on maîtrise **tout** ce qui est installé (partitionnement, paquets, pile réseau, console), à partir d'une source dont on vérifie la signature, et la même méthode sert pour toutes les distributions, y compris celles qui ne publient pas d'image *cloud* adaptée. On obtient aussi une image construite de la même façon que celle d'un serveur physique (module 11). En sens inverse, l'image *genericcloud* est construite, testée et maintenue par l'équipe *cloud* de Debian avec des choix éprouvés (noyau allégé, pile réseau), plus vite (pas d'installeur) : c'est un excellent point de départ si l'on vérifie sa signature et qu'on la personnalise avec `virt-customize` ou un build `proxmox-clone`. Le module construit depuis l'ISO pour apprendre la chaîne complète.

**10.** `virt-customize` et `virt-sysprep` (libguestfs) : modifier et préparer une image disque hors ligne, sans la démarrer ; idéal pour personnaliser une image *cloud*. `diskimage-builder` (OpenStack) : images construites par éléments réutilisables, très utilisé pour OpenStack (module 10). `mkosi` (systemd) : images minimales et reproductibles à partir des paquets de la distribution. `debos`, `kiwi` (SUSE), `osbuild` / *Image Builder* (Red Hat) : constructeurs propres aux distributions. Packer se distingue en pilotant l'hyperviseur cible lui-même, avec les mêmes fichiers pour plusieurs plateformes.

**11.** La *Business Source License* 1.1 autorise la copie, la modification et l'usage, y compris en production, **sauf** pour proposer un produit concurrent de ceux de HashiCorp (selon la clause « Additional Use Grant » propre à chaque produit) ; chaque version redevient libre (MPL 2.0) quatre ans après sa publication. Pour MédiSphère, qui utilise Packer en interne, aucun problème. Le changement de licence de Terraform a provoqué le *fork* OpenTofu, sous gouvernance de la Linux Foundation, que le workbook adopte au module 05 ; Packer n'a pas de *fork* aussi largement adopté. Le risque à suivre est contractuel et stratégique (évolutions futures de la licence), pas technique.

**12.** La multiplication non maîtrisée d'images (« une image par projet, par besoin, par personne »), dont personne ne sait laquelle est à jour ni qui l'utilise. Conséquences : correctifs appliqués à certaines seulement, stockage gaspillé, audits impossibles. Mécanismes : un catalogue court (deux familles, des images de base et dorées, PLAN.md §4.8) ; un seul dépôt et une seule chaîne de construction ; versionnage et étiquette `current` ; rotation automatique qui ne garde que les N dernières versions (M03-E16) ; règle « on enrichit par cloud-init ou Ansible, pas par une nouvelle image » ; revue des demandes d'images (ADR, M03-E17).

**13. Réponse b.** Le consommateur demande « la Debian dorée en vigueur » et vérifie qu'il n'y a pas d'ambiguïté : une seule image `current`. a) Faux : coder un VMID en dur, c'est cloner une version qui sera retirée par la rotation. c) Faux : le plus grand VMID n'est pas forcément la version validée (une version plus récente peut avoir échoué au test). d) Faux : `tpl-debian13` n'est pas une image dorée et sera retiré.

**14.** Éléments de preuve : (1) le **code** du build dans `plateforme/images`, avec l'historique des MR et des revues ; (2) le **manifeste** de l'image : commit, version de Packer et du plugin, ISO source et sa somme, date (notes du template, `manifests/<nom>.json` en artefact CI) ; (3) la **liste des paquets** avec versions et son empreinte ; (4) la preuve de **vérification de la source** (signature de `SHA256SUMS`, journal de `deposer-iso.sh`) ; (5) le **résultat des tests** (job de CI, M03-E15) ; (6) le journal du pipeline qui a construit et publié. Stockage : la forge (code, MR, artefacts de CI avec une durée de conservation adaptée à l'audit), les notes du template, et un registre des images publiées dans `docs/socle/images.md` (M03-E25). Mieux : un SBOM et une signature du manifeste (modules 13 et 26).

**Grille d'auto-évaluation** : une réponse est juste si elle cite le mécanisme (pas seulement la conclusion) ; pour 3, au moins 8 classements sur 10 corrects et justifiés ; pour 6, au moins deux conséquences concrètes ; pour 14, au moins quatre éléments de preuve et leur lieu de stockage.

---

### M03-E02 — Installer Packer et créer un compte Proxmox dédié

**Solution**

Fichiers : [`fichiers/M03-E02/pve-packer-compte.sh`](fichiers/M03-E02/pve-packer-compte.sh) (compte, rôles, jeton, ACL), [`pve-packer.env.exemple`](fichiers/M03-E02/pve-packer.env.exemple), [`registre-secrets-extrait.md`](fichiers/M03-E02/registre-secrets-extrait.md), et le squelette du projet dans [`fichiers/M03-E02/images/`](fichiers/M03-E02/images/).

*1. Packer depuis le dépôt HashiCorp.*
```
admin@adm01:~$ curl -fsSL -o /tmp/hashicorp.asc https://apt.releases.hashicorp.com/gpg
admin@adm01:~$ gpg --show-keys --with-fingerprint /tmp/hashicorp.asc
pub   rsa4096 2026-09-09 [SC] [expires: 2031-09-08]
      D55C 0D1A C78A 8D81 26CB  631C FC9C A96A CA02 6560
uid                      HashiCorp Security (HashiCorp Package Signing) <security+packaging@hashicorp.com>
admin@adm01:~$ sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg /tmp/hashicorp.asc
admin@adm01:~$ sudo tee /etc/apt/sources.list.d/hashicorp.sources >/dev/null <<'EOF'
Types: deb
URIs: https://apt.releases.hashicorp.com
Suites: trixie
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/hashicorp-archive-keyring.gpg
EOF
admin@adm01:~$ sudo apt update && sudo apt install packer
admin@adm01:~$ packer version
Packer v1.16.1
admin@adm01:~$ apt-cache policy packer | sed -n '1,4p'
packer:
  Installed: 1.16.1-1
  Candidate: 1.16.1-1
  Version table:
```
L'empreinte ci-dessus est celle relevée au moment de la rédaction (HashiCorp a renouvelé sa clé de signature des paquets en septembre 2026). ⚠️ À vérifier sur la page de sécurité officielle de HashiCorp (*PGP public keys*) **avant** d'installer : c'est tout l'intérêt de l'étape. `apt-cache policy` doit montrer l'origine `https://apt.releases.hashicorp.com trixie/main`.

*2. Privilèges.* Contrôles relevés dans l'API viewer de Proxmox VE 9 :

| Opération du plugin | Appel | Contrôle |
|---|---|---|
| Créer la VM de build dans le pool | `POST /nodes/{node}/qemu` (avec `pool`) | `VM.Allocate` sur `/vms/{vmid}` **ou** `/pool/{pool}` ; `Datastore.AllocateSpace` sur les stockages des disques ; `SDN.Use` sur le pont ou VNet |
| Monter l'ISO déposée | même appel (`ide2: hdd-bulk:iso/…`) | accès au volume : `Datastore.AllocateSpace` **ou** `Datastore.Audit` sur `/storage/hdd-bulk` (volume de type `iso`) |
| Cloner un template | `POST …/qemu/{vmid}/clone` | `VM.Clone` sur `/vms/{vmid}` et `VM.Allocate` sur `/pool/{pool}` |
| Régler matériel, cloud-init, notes, étiquettes | `POST/PUT …/qemu/{vmid}/config` | `VM.Config.*` selon les paramètres (CDROM, CPU, Cloudinit, Disk, HWType, Memory, Network, Options) |
| Démarrer, arrêter | `…/status/start`, `…/status/shutdown`, `…/status/stop` | `VM.PowerMgmt` |
| Taper au clavier (`boot_command`) | `PUT …/qemu/{vmid}/sendkey` | **`VM.Console`** |
| Lire l'adresse IP | `GET …/agent/network-get-interfaces` | `VM.GuestAgent.Audit` (ou `…Unrestricted`) |
| Convertir en template | `POST …/qemu/{vmid}/template` | `VM.Allocate` |
| Supprimer (`-force`, rotation) | `DELETE /nodes/{node}/qemu/{vmid}` | `VM.Allocate` |
| Lire l'état, la config | `GET …/status/current`, `…/config` | `VM.Audit` |
| Lister, trouver un VMID libre, suivre ses tâches | `/cluster/resources`, `/cluster/nextid`, `…/tasks/{upid}/status` | aucun (filtré par `VM.Audit`) ; ses propres tâches |

Rôle `WBPacker` (sur `/pool/lab`) : `VM.Allocate`, `VM.Clone`, `VM.Audit`, `VM.Config.CDROM`, `VM.Config.CPU`, `VM.Config.Cloudinit`, `VM.Config.Disk`, `VM.Config.HWType`, `VM.Config.Memory`, `VM.Config.Network`, `VM.Config.Options`, `VM.Console`, `VM.PowerMgmt`, `VM.GuestAgent.Audit` — justification ligne à ligne en commentaire dans le script. Rôles posés sur leurs propres chemins : `PVEDatastoreUser` sur `/storage/local-nvme`, un rôle `WBLectureISO` (`Datastore.Audit` seul) sur `/storage/hdd-bulk`, `PVESDNUser` sur `/sdn/zones/lab/vsandbox`.

Écartés : `Datastore.AllocateTemplate` (téléverser une ISO : les ISO sont déposées par un administrateur, E05) ; `Sys.AccessNetwork` sur le nœud (exigé par `download-url`, c'est-à-dire `iso_download_pve` : il permet de faire télécharger à `pve01` **n'importe quelle URL**, y compris de son réseau local ; Proxmox le classe parmi les privilèges réservés à root) ; `VM.GuestAgent.Unrestricted`, `FileRead`, `FileWrite` (exécuter ou lire dans l'invité : inutile, les provisioners passent par SSH) ; `VM.Snapshot*`, `VM.Backup`, `VM.Migrate` (pas d'usage) ; `Pool.Audit` (le plugin ne lit pas le contenu du pool ; ⚠️ à ajouter si une version future du plugin le demandait : le refus 403 nomme le chemin et le privilège) ; tout `Sys.*`, `Permissions.Modify`, `User.Modify`, `Realm.*`.

*3. Compte.* Sur `pve01` (script complet : [`pve-packer-compte.sh`](fichiers/M03-E02/pve-packer-compte.sh)) :
```
admin@adm01:~$ scp ~/DevOpsPrivateCloud/modules/03-images/corrige/fichiers/M03-E02/pve-packer-compte.sh pve01:/root/
root@pve01:~# bash /root/pve-packer-compte.sh
>>> Secret du jeton ci-dessous (« value ») : copie-le MAINTENANT dans pve-packer.env sur adm01.
┌──────────────┬──────────────────────────────────────┐
│ key          │ value                                │
╞══════════════╪══════════════════════════════════════╡
│ full-tokenid │ wb-packer@pve!packer                 │
│ value        │ xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx │
└──────────────┴──────────────────────────────────────┘
== droits effectifs du jeton sur /pool/lab
…
root@pve01:~# pveum user token permissions wb-packer@pve packer --path /
```
La dernière commande ne doit rien afficher pour `/` lui-même (aucun privilège `Sys.*`).

*4. Secret.* Comme en M00-E17 :
```
admin@adm01:~$ install -m 600 /dev/null ~/.config/workbook/pve-packer.env
admin@adm01:~$ ${EDITOR:-nano} ~/.config/workbook/pve-packer.env
```
Contenu : [`pve-packer.env.exemple`](fichiers/M03-E02/pve-packer.env.exemple). Registre des secrets : ligne de [`registre-secrets-extrait.md`](fichiers/M03-E02/registre-secrets-extrait.md), ajoutée par MR dans `plateforme/medisphere`.

*5. TLS.* Dans `builder/proxmox/common/client.go` du plugin :
```go
tlsConfig := &tls.Config{
    InsecureSkipVerify: config.SkipCertValidation,
}
```
Aucune liste d'autorités n'est fournie (`RootCAs` nul) : la bibliothèque standard de Go utilise alors le **magasin du système**. Sous Linux, elle lit le fichier désigné par `SSL_CERT_FILE` ou les dossiers de `SSL_CERT_DIR` s'ils sont définis, sinon une liste de chemins connus dont `/etc/ssl/certs/ca-certificates.crt` (Debian). On y ajoute l'ancre conforme de M02-E08 :
```
admin@adm01:~$ sudo install -m 644 ~/.config/workbook/pve-root-ca.pem /usr/local/share/ca-certificates/pve01-root-ca.crt
admin@adm01:~$ sudo update-ca-certificates
Updating certificates in /etc/ssl/certs...
1 added, 0 removed; done.
admin@adm01:~$ ( set -a; . ~/.config/workbook/pve-packer.env; set +a
    curl -sS -H @<(printf 'Authorization: PVEAPIToken=%s=%s\n' "$PKR_VAR_proxmox_username" "$PKR_VAR_proxmox_token") \
         "$PKR_VAR_proxmox_url/version" | jq -c .data )
{"release":"9.0","repoid":"…","version":"9.0.10"}
```
(Le fichier dans `/usr/local/share/ca-certificates/` doit porter l'extension `.crt`.) Le plugin respecte aussi `HTTPS_PROXY`/`NO_PROXY` : sans proxy sur `adm01`, rien à faire.

*6. Projet.* Création et configuration standard par le script de M02-E02, puis contrôle par celui de M01-E47 :
```
admin@adm01:~$ MERGE_METHOD=rebase_merge ~/DevOpsPrivateCloud/modules/02-scripting/corrige/fichiers/M02-E02/configurer-projet.sh plateforme/images
admin@adm01:~$ ~/medisphere/forge/outils/conformite-plateforme.sh --verifier
admin@adm01:~$ git clone git@git01.par1.medisphere.internal:plateforme/images.git ~/src/images
admin@adm01:~$ cd ~/src/images && git switch -c chore/initialisation
admin@adm01:~/src/images$ cp ~/src/outils/{commitlint.config.mjs,.releaserc.json,CONTRIBUTING.md,.gitleaks.toml} .
admin@adm01:~/src/images$ cp -r ~/src/outils/.gitlab .
admin@adm01:~/src/images$ pre-commit install
```
puis les fichiers du squelette : [`.pre-commit-config.yaml`](fichiers/M03-E02/images/.pre-commit-config.yaml), [`outils/valider-syntaxe.sh`](fichiers/M03-E02/images/outils/valider-syntaxe.sh), [`.gitignore`](fichiers/M03-E02/images/.gitignore), [`.gitlab-ci.yml`](fichiers/M03-E02/images/.gitlab-ci.yml), [`README.md`](fichiers/M03-E02/images/README.md). Commit `chore: initialisation du projet images`, MR, pipeline vert, fusion.

La dette CI : le job `pre-commit` du gabarit fixe `SKIP: gitleaks`. Une définition locale du même job **fusionne** ses clés avec celle du gabarit ; on redéfinit donc seulement `variables.SKIP`, en y **gardant** `gitleaks` :
```yaml
pre-commit:
  variables:
    SKIP: "gitleaks,packer-fmt,packer-validate"
```
Commentaire « à supprimer en M03-E15 » dans le fichier et ticket de dette ouvert.

*7. Réponse au ticket* : les deux tableaux ci-dessus, les ACL, le TLS (ancre de `pve01` dans le magasin système d'`adm01`, puis de `runner01` en E15), et le cycle de vie du jeton (renouvellement : nouveau jeton `packer2` avec les mêmes ACL, bascule du fichier et de la variable CI, build de contrôle, suppression de l'ancien ; révocation immédiate : `pveum user token remove wb-packer@pve packer`).

**Explications**

- **`VM.Console` pour taper au clavier.** `boot_command` passe par l'appel `sendkey`, protégé par `VM.Console` : le même privilège donne la console noVNC/xterm.js des VMs du pool. C'est un privilège fort (une console, c'est un clavier sur la machine), accepté parce qu'il est limité au pool `lab` et que `proxmox-iso` ne peut pas s'en passer. Un jeton qui ne ferait que des builds `proxmox-clone` pourrait s'en passer.
- **Pourquoi pas `iso_download_pve`** : le téléchargement par `pve01` exige `Sys.AccessNetwork` sur le nœud (ou `Sys.Modify` sur `/`), privilège de catégorie « root ». Le dépôt par un administrateur, avec vérification de **signature** (que Packer ne fait pas : il ne vérifie qu'une somme), est à la fois plus sûr et plus rapide (pas de nouveau téléchargement à chaque build).
- **Séparation des privilèges** : comme en M00-E17, les droits effectifs du jeton sont l'intersection des siens et de ceux de son utilisateur : ACL des deux côtés.
- **Go et la vérification stricte** : Go refuse une autorité dont l'extension *Key Usage* existe sans `keyCertSign`, mais accepte une autorité **sans** cette extension ; l'autorité d'origine de `pve01` fonctionnerait donc avec Packer. On installe tout de même l'ancre conforme de M02-E08 : un seul fichier de confiance pour tous les outils (Python l'exige).

**Alternatives**

- **`SSL_CERT_FILE` réservé à Packer** : un fichier contenant le magasin système **plus** l'autorité de `pve01`, désigné par `SSL_CERT_FILE` dans `construire.sh` seulement. Plus étroit : le reste d'`adm01` ne fait pas confiance à `pve01`. Prix : un fichier de plus à régénérer à chaque mise à jour de `ca-certificates`. Choix raisonnable si la sécurité l'exige ; ici, la vérification de la CI (E15) s'appuie sur le magasin système.
- **Archive zip officielle** (`releases.hashicorp.com`, `SHA256SUMS` signé) : utile pour figer une version exacte hors dépôt ; mais mises à jour manuelles et pas d'inventaire par le gestionnaire de paquets.
- **Un compte par usage** (`wb-packer-iso`, `wb-packer-clone`) : permettrait de retirer `VM.Console` aux builds par clonage ; complexité non justifiée pour l'instant.

**Pièges classiques**

- Ajouter la clé HashiCorp dans `/etc/apt/trusted.gpg.d/` : elle devient valable pour **tous** les dépôts.
- Recopier une liste de privilèges d'un tutoriel pour Proxmox VE 8 (`VM.Monitor`) : la création du rôle échoue en version 9 (privilège inconnu).
- Oublier `VM.Console` : le build démarre l'ISO, n'arrive jamais à taper la ligne de démarrage, l'installeur attend au menu, et Packer attend SSH jusqu'au délai maximal.
- ACL sur l'utilisateur seulement (ou sur le jeton seulement) : 403 partout.
- `insecure_skip_tls_verify = true` « en attendant » : le jeton part vers quiconque se place au milieu.
- Mettre le certificat avec l'extension `.pem` dans `/usr/local/share/ca-certificates/` : `update-ca-certificates` l'ignore.
- Laisser le job `pre-commit` de la CI en échec permanent (Packer absent du runner) : on prend l'habitude d'ignorer le rouge.

**En production chez MédiSphère**

- Jeton délivré par Vault/OpenBao à la durée du build (module 25) ; un compte de build par environnement.
- Builds sur un runner dédié, sur un réseau de construction isolé, avec un miroir de paquets interne (pas d'accès direct à Internet pendant le build).
- Accès à l'API de Proxmox (8006) limité aux machines de build par le pare-feu de l'hyperviseur (E15).

---

### M03-E03 — Premier build : `proxmox-clone` depuis `tpl-debian13`

**Solution**

Fichier : [`fichiers/M03-E03/essai.pkr.hcl`](fichiers/M03-E03/essai.pkr.hcl) (version finale, matériel aligné sur 9000).

*1-2. Build.*
```
admin@adm01:~/m03/e03$ set -a; . ~/.config/workbook/pve-packer.env; set +a
admin@adm01:~/m03/e03$ packer init .
Installed plugin github.com/hashicorp/proxmox v1.2.4 in "/home/admin/.config/packer/plugins/github.com/hashicorp/proxmox/packer-plugin-proxmox_v1.2.4_x5.0_linux_amd64"
admin@adm01:~/m03/e03$ packer validate . && packer build .
proxmox-clone.essai: output will be in this color.

==> proxmox-clone.essai: Creating ephemeral key pair for SSH communicator...
==> proxmox-clone.essai: Created ephemeral SSH key pair for communicator
==> proxmox-clone.essai: Creating VM
==> proxmox-clone.essai: Starting VM
==> proxmox-clone.essai: Waiting for SSH to become available...
==> proxmox-clone.essai: Connected to SSH!
==> proxmox-clone.essai: Provisioning with shell script: /tmp/packer-shell1234567
…
==> proxmox-clone.essai: Trying to remove ephemeral keys from authorized_keys files
==> proxmox-clone.essai: Stopping VM
==> proxmox-clone.essai: Converting VM to template
Build 'proxmox-clone.essai' finished after 4 minutes 12 seconds.
```
(Sortie abrégée ; les durées dépendent du stockage et des miroirs.)

`notes.md` attendu, étape par étape :

| Packer | Côté Proxmox (journal des tâches, utilisateur `wb-packer@pve!packer`) |
|---|---|
| *Creating ephemeral key pair* | rien : paire de clés générée en mémoire sur `adm01` |
| *Creating VM* | tâche `qmclone` 9000 → 9090 (copie complète du disque), puis modification de la configuration : matériel, `ciuser packer`, `sshkeys` (clé éphémère), `ipconfig0 ip=dhcp`, résolveur |
| *Starting VM* | tâche `qmstart` ; cloud-init du clone : utilisateur `packer`, clé, puis *vendor-data* de 9000 (installation de l'agent) |
| *Waiting for SSH* | Packer interroge l'agent (`agent/network-get-interfaces`) jusqu'à obtenir une adresse IPv4, puis tente SSH |
| *Provisioning* | le script du provisioner est copié dans `/tmp` et exécuté |
| *Stopping VM* | arrêt propre (`qmshutdown`, par l'agent) |
| *Converting VM to template* | lecteur cloud-init et paramètres `ciuser`, `sshkeys`, `ipconfig0`, `nameserver`, `searchdomain` **retirés**, tâche `qmtemplate`, puis ajout d'un lecteur cloud-init vide (`cloud_init = true`), nom et notes du template |

*3. Valeurs par défaut.* Avec un premier fichier qui ne précise que le minimum, la comparaison montre typiquement `scsihw: lsi`, `cpu: kvm64`, `memory: 512`, `ostype: other`, et un affichage ou un port série qui ne correspondent plus à 9000 (⚠️ le détail exact dépend de la version du plugin et des options omises). Ces valeurs sont celles **du plugin**, appliquées au clone : `kvm64` (CPU par défaut du plugin), `lsi` (contrôleur par défaut), 512 Mo. Conséquences : performances disque dégradées (`lsi` émulé au lieu de virtio), console série perdue, et pour une future image Rocky, un noyau qui ne démarre pas (`kvm64`). La version corrigée fixe tout le matériel.

*4. Cloud-init du template.* `qm config 9090` montre un lecteur `cloudinit` (ajouté vide à la fin) mais plus de `ciuser`, `sshkeys`, `ipconfig0`, `nameserver` ni `searchdomain` : Packer a retiré ce qui servait au build (la clé éphémère n'a plus de sens), y compris ce qu'il avait reçu de 9000. Un clone de 9090 doit donc tout préciser (et c'est pour cela qu'en E09 les valeurs par défaut sont reposées après la conversion). Le `cicustom` (vendor) de 9000, lui, est conservé.

*5. Les clones.*
```
root@pve01:~# for i in 2030 2031; do
    qm clone 9090 $i --name m03-essai-$([ $i = 2030 ] && echo a || echo b) --pool lab
    qm set $i --tags env-m03 --ipconfig0 ip=dhcp --nameserver 10.10.20.10 \
       --searchdomain par1.medisphere.internal --ciuser admin --sshkeys /root/cle-adm01.pub
    qm start $i
  done
```
(`/root/cle-adm01.pub` : la clé publique d'`adm01`, copiée par `scp ~/.ssh/id_ed25519.pub pve01:/root/cle-adm01.pub`.) Observation : **même** `machine-id`, **mêmes** empreintes de clés d'hôte (le démarrage de construction les a créées, rien ne les a effacées), **même adresse IP** obtenue par DHCP (l'identifiant de client DHCP de `systemd-networkd` dérive du `machine-id`, donc `dns01` voit deux fois le même client), un compte `packer` présent avec `sudo` sans mot de passe (`/etc/sudoers.d/90-cloud-init-users`). L'adresse partagée rend les deux VMs à moitié injoignables (le premier qui répond à l'ARP gagne).

*6.* `qm stop` puis `qm destroy` pour 2030 et 2031, vérification, puis `qm destroy 9090`.

**Explications**

- **Le builder clone applique une configuration complète.** Le plugin construit une description de VM à partir de **ses** paramètres (avec leurs valeurs par défaut) et l'applique au clone ; il ne « fusionne » pas avec le template source. D'où l'habitude du projet : décrire **tout** le matériel dans chaque build.
- **La paire de clés éphémère** est créée par le builder `proxmox-clone` et injectée par cloud-init (`ciuser` + `sshkeys`) : aucun secret n'est à fournir. À la fin, Packer tente de retirer la clé de `authorized_keys` ; le vrai nettoyage est la préparation au clonage (E07).
- **Pourquoi l'agent compte** : sans `ssh_host`, Packer trouve l'adresse de la VM uniquement par l'agent QEMU. Une image sans agent fonctionnel bloque le build à « Waiting for SSH ».

**Alternatives**

- Construire depuis l'image *genericcloud* importée (comme 9000) avec un build `proxmox-clone` : rapide et sûr si l'image est vérifiée (signature) ; c'est un choix défendable pour une image dorée Debian (E01, question 9).
- `virt-customize` sur le fichier qcow2 avant import : sans démarrage, donc sans identité à nettoyer, mais limité à ce qu'on peut faire hors ligne.

**Pièges classiques**

- `-force` dans un essai : supprime la VM qui porte `vm_id` sans confirmation.
- `task_timeout` par défaut (1 min) : un clone complet de plusieurs Go le dépasse, le build échoue sur « timeout » alors que le clone se termine.
- `cloud-init status --wait` dans un provisioner : son code de sortie vaut 2 si cloud-init a terminé avec des avertissements (clé dépréciée, par exemple) ; le provisioner échoue si on ne le prévoit pas.
- Oublier `pool` : la VM est créée hors du pool et le jeton n'a plus aucun droit dessus (403 à l'étape suivante, VM orpheline à supprimer en root).

**En production chez MédiSphère**

Aucun template n'est produit hors du projet et de la CI ; les essais se font dans la plage 9090-9099 et sont supprimés automatiquement (règle de rotation, E16). Le journal des tâches de Proxmox (utilisateur du jeton) sert de trace d'audit des builds.

---

### M03-E04 — cloud-init en profondeur : étapes, modules, journaux

**Solution**

Snippet : [`fichiers/M03-E04/m03-e04-vendor.yaml`](fichiers/M03-E04/m03-e04-vendor.yaml).

*1. Avant le premier démarrage.*
```
admin@adm01:~$ scp ~/DevOpsPrivateCloud/modules/03-images/corrige/fichiers/M03-E04/m03-e04-vendor.yaml pve01:/mnt/hdd-bulk/snippets/
root@pve01:~# qm clone 9000 2032 --name m03-ci --pool lab --full 1 --storage local-nvme
root@pve01:~# qm set 2032 --tags env-m03 --net0 virtio,bridge=vsandbox --ipconfig0 ip=dhcp \
    --ciuser admin --sshkeys /root/cle-adm01.pub \
    --cicustom "vendor=hdd-bulk:snippets/m03-e04-vendor.yaml"
root@pve01:~# qm cloudinit dump 2032 meta
instance-id: 0d6f3c…
```
L'identifiant d'instance est calculé par Proxmox : c'est l'empreinte SHA-1 du *user-data* et du *network-config* générés (code de `PVE::QemuServer::Cloudinit`, fonction `nocloud_gen_metadata`). Le *vendor-data* n'entre **pas** dans ce calcul. `cicustom` posé sur 2032 **remplace** celui hérité de 9000 (une seule valeur par type) : d'où l'obligation de reprendre l'agent et le fuseau dans le snippet de l'exercice.

*2. Étapes.* `systemctl list-units --all 'cloud*'` montre les services de cloud-init 25.1 et leurs étapes (documentation *Boot stages*) :

| Étape | Service | Modules (`/etc/cloud/cloud.cfg` de Debian) | Effet notable ici |
|---|---|---|---|
| Détection | générateur systemd + `ds-identify` | — | trouve la source *NoCloud* (lecteur étiqueté `cidata`), sinon désactive cloud-init |
| Local | `cloud-init-local.service` | aucun module : source de données, configuration réseau | écrit la configuration réseau (netplan) **avant** que le réseau monte |
| Network | `cloud-init-network.service` | `cloud_init_modules` : `seed_random`, `bootcmd`, `write_files`, `growpart`, `resizefs`, …, `users_groups`, `ssh` | `bootcmd` ; utilisateur `admin` ; clés d'hôte SSH |
| Config | `cloud-config.service` | `cloud_config_modules` : …, `apt_configure`, `ntp`, `timezone`, `runcmd` | fuseau ; `runcmd` **écrit** son script |
| Final | `cloud-final.service` | `cloud_final_modules` : `package_update_upgrade_install`, …, `scripts_vendor`, `scripts_per_*`, `scripts_user`, …, `final_message` | installation de l'agent, puis `scripts_user` exécute le script de `runcmd` |

L'agent est installé par `package_update_upgrade_install`, à l'étape **Final** : c'est la dernière, parce qu'installer des paquets demande un réseau complet et ne doit retarder ni SSH ni la connexion console. Conséquence : tant que cloud-init n'a pas fini (mise à jour des listes, `package_upgrade: true` du *user-data* de Proxmox, installation), l'agent est absent — c'est la VM « injoignable pendant un quart d'heure » du ticket.
```
admin@m03-ci:~$ cloud-init analyze blame | head -4
     58.21300s (modules-final/config-package_update_upgrade_install)
      2.10100s (init-network/config-ssh)
      1.55500s (init-local/search-NoCloud)
      …
```
(Valeurs indicatives.)

*3. Ce qui a été détecté.* `cloud-id` → `nocloud` ; `/run/cloud-init/ds-identify.log` explique la détection ; `cloud-init query --all` (en root pour les données sensibles) donne `v1.instance_id`, `v1.platform`… Données rangées dans `/var/lib/cloud/instances/<instance-id>/` (lien `/var/lib/cloud/instance`) : `user-data.txt`, `vendor-data.txt`, `cloud-config.txt`, `vendor-cloud-config.txt`, `scripts/runcmd`, et `sem/` (un fichier par module « une fois par instance » déjà exécuté).

*4. Fréquences.* Après deux redémarrages, puis un changement de `searchdomain`, puis un changement du snippet seul :
```
admin@m03-ci:~$ cat /var/log/m03-e04.log
bootcmd 2026-10-07T10:02:11+02:00 5c1e…
runcmd 2026-10-07T10:03:20+02:00 instance=0d6f3c…
bootcmd 2026-10-07T10:06:40+02:00 9a0b…
bootcmd 2026-10-07T10:08:02+02:00 77d2…
bootcmd 2026-10-07T10:12:30+02:00 e3f1…
runcmd 2026-10-07T10:13:05+02:00 instance=4b88a1…
bootcmd 2026-10-07T10:16:47+02:00 a51c…
```
- `bootcmd` : fréquence `always`, une ligne par démarrage.
- `runcmd` : fréquence `instance`, exécuté au premier démarrage, puis **de nouveau** après le changement de `searchdomain` : le *network-config* a changé, donc l'identifiant d'instance aussi ; cloud-init considère qu'il s'agit d'une **nouvelle instance** et rejoue tous les modules « une fois par instance » — dont le module `ssh`, qui **régénère les clés d'hôte** (les clients SSH crient à l'usurpation) et recrée l'utilisateur.
- Changement du snippet seul : rien ne se rejoue ; le *vendor-data* n'entre pas dans l'identifiant d'instance, et le *vendor-data* n'est traité qu'une fois par instance.

*5. `cloud-init clean --logs`* efface l'état (`/var/lib/cloud/instance`, sémaphores) et les journaux : au démarrage suivant, cloud-init se comporte comme au premier, **avec le même identifiant d'instance** (nouvelle ligne `runcmd` portant le même `instance=`). Différence avec l'étape 4 : là, c'est Proxmox qui a changé l'identité de l'instance ; ici, c'est toi qui as effacé la mémoire de cloud-init. Dans les deux cas, clés d'hôte régénérées.

*6. Erreur d'indentation.* `cloud-init status --long` passe à `status: error` (ou `degraded` si le reste a pu s'appliquer) avec un message de schéma ; `/var/log/cloud-init.log` contient la trace (« Failed loading yaml blob » ou un avertissement de schéma) ; `sudo cloud-init schema --system` désigne la ligne fautive. Selon l'endroit de l'erreur, tout le *vendor-data* est ignoré : plus d'agent, plus de `bootcmd`.

*7. Fiche* : voir les tableaux ci-dessus ; ordre de lecture conseillé : `cloud-init status --long` → `/var/log/cloud-init-output.log` (sortie des commandes) → `/var/log/cloud-init.log` (détail, chercher `WARNING`, `Traceback`) → `/run/cloud-init/ds-identify.log` (source non trouvée) → `qm cloudinit dump <vmid> user|network|meta` côté Proxmox. Causes classiques de « VM injoignable après clonage » : réseau (VLAN, DHCP, `ipconfig0` absent), agent pas encore installé (étape Final pas finie), *vendor-data* invalide, stockage des snippets hors ligne (la VM ne démarre même pas), clés d'hôte changées après une modification cloud-init.

**Explications**

- **Une « nouvelle instance »** est décidée en comparant l'identifiant d'instance fourni par la source de données à celui du dernier démarrage (*First boot determination*). Avec Proxmox, **toute** modification de l'utilisateur, des clés, du réseau, du résolveur crée une nouvelle instance. Sur une VM de production, `qm set --sshkeys` pour ajouter une clé a donc des effets de bord : nouvelles clés d'hôte, modules rejoués.
- **Fusion user/vendor.** Les configurations fusionnent clé par clé et le *user-data* l'emporte (E11).

**Alternatives**

- `cloud-init single --name <module> --frequency always` pour rejouer un module précis plutôt que tout.
- `cloud-init collect-logs` produit une archive de diagnostic à joindre à un ticket.

**Pièges classiques**

- Modifier `--cicustom` sur un clone en croyant **ajouter** un *vendor-data* : on **remplace** celui du template.
- Croire qu'un changement de snippet sera pris en compte au prochain démarrage.
- Lire `/var/log/cloud-init.log` seul : la sortie des commandes (`apt`, scripts) est dans `cloud-init-output.log`.
- `cloud-init clean` sur une VM de production : utilisateurs, clés d'hôte, configuration réseau rejoués au démarrage suivant.

**En production chez MédiSphère**

La fiche rejoint le guide d'astreinte (RB-03x, palier 4). Les VMs durables ne voient plus leurs paramètres cloud-init modifiés après création : un changement d'identité passe par une reconstruction (OpenTofu, M05) ou par Ansible, jamais par `qm set` à chaud.

---

### M03-E05 — Construire depuis l'ISO : `proxmox-iso` et preseed Debian 13

**Solution**

Fichiers complets : [`fichiers/M03-E05/images/`](fichiers/M03-E05/images/) — [`debian13-base/build.pkr.hcl`](fichiers/M03-E05/images/debian13-base/build.pkr.hcl), [`variables.pkr.hcl`](fichiers/M03-E05/images/debian13-base/variables.pkr.hcl), [`http/preseed.cfg`](fichiers/M03-E05/images/debian13-base/http/preseed.cfg), [`http/late-command.sh`](fichiers/M03-E05/images/debian13-base/http/late-command.sh), [`vars/lab.pkrvars.hcl`](fichiers/M03-E05/images/vars/lab.pkrvars.hcl), [`outils/deposer-iso.sh`](fichiers/M03-E05/images/outils/deposer-iso.sh) ; règle `gw01` : [`gw01-nftables-extrait.nft`](fichiers/M03-E05/gw01-nftables-extrait.nft).

*1. L'ISO.*
```
admin@adm01:~/src/images$ ssh pve01 'bash -s' -- debian13 < outils/deposer-iso.sh
== Clé de signature attendue : DF9B9C49EAA9298432589D76DA87E80D6294BE9B
== Fichier de sommes et signature
signature de SHA256SUMS valide (DF9B9C49EAA9298432589D76DA87E80D6294BE9B)
== Téléchargement de debian-13.7.0-amd64-netinst.iso vers /mnt/hdd-bulk/template/iso
…
ISO vérifiée et déposée : hdd-bulk:iso/debian-13.7.0-amd64-netinst.iso
iso_name   = "debian-13.7.0-amd64-netinst.iso"
iso_sha256 = "a7ef94ac2fb9a7fec454552abd629b7cc9d5155c886165a45649f5ce6167e355"
```
(Version et somme au moment de la rédaction ; la tienne dépend de la dernière version intermédiaire.) Points du script : clé importée dans un trousseau **temporaire** puis contrôlée par son **empreinte complète** (un identifiant court se falsifie) ; signature vérifiée par la ligne `VALIDSIG <empreinte>` de `gpg --status-fd` (une signature valide **d'une autre clé** présente dans le trousseau serait refusée) ; ISO téléchargée sous un nom provisoire dans le même dossier, renommée seulement après vérification de la somme (jamais une ISO partielle ou corrompue sous son nom final) ; chemin du stockage obtenu par `pvesm path`, pas codé en dur. Sorties de `gpg` capturées avant d'être filtrées : avec `pipefail`, un `grep -q` en fin de tube peut faire échouer le tube.

*2. Le flux.* Règle sur `gw01` (extrait), avec les précautions de M00-E21 :
```
iifname $V_SANDBOX ip daddr $ADM01 tcp dport 8100-8199 accept comment "VMs de build Packer vers le serveur HTTP de Packer sur adm01 (M03-E05)"
```
Matrice des flux : `vsandbox (10.10.99.0/24) → adm01 10.10.10.10 | TCP 8100-8199 | téléchargement du preseed/kickstart par l'installeur | M03-E05`. Les autres flux du build existent déjà : `adm01` → `pve01` 8006 (API), `adm01` → `vsandbox` 22 (communicateur SSH : « bastion vers tout le lab »), `vsandbox` → `dns01` 53 et DHCP par relais, `vsandbox` → Internet (miroirs Debian, NAT). C'est la seule ouverture du VLAN SANDBOX vers MGMT : elle est limitée à une adresse et une plage de ports.

*3. Le preseed* (voir le fichier, commenté). Choix notables :
- `auto url=…` sur la ligne de démarrage : mode automatique, les questions de langue et de clavier sont posées **après** le chargement du preseed, qui y répond ;
- compte de construction créé par `passwd/username` et `passwd/user-password` (gabarit : valeurs injectées par `templatefile`), `passwd/root-login false` : pas de mot de passe root, le compte reçoit `sudo` ;
- partitionnement par une recette `expert_recipe` : une seule partition ext4 qui occupe tout le disque, sans swap (`partman-basicfilesystems/no_swap false` évite la question « pas de swap ? ») ; la racine est la dernière (et la seule) partition, donc `growpart` peut l'agrandir ;
- `pkgsel/include` : `qemu-guest-agent cloud-init cloud-guest-utils netplan.io systemd-resolved sudo ca-certificates` (+ tâche `ssh-server`) ;
- `debian-installer/add-kernel-opts` : console `tty0` et `ttyS0` dans la configuration GRUB du système installé ;
- `late_command` : récupère `late-command.sh` sur le serveur qui a servi le preseed (`debconf-get preseed/url`) et l'exécute dans la cible. Ce script donne `sudo` sans mot de passe au compte de construction (validé par `visudo -c`), écrit une configuration netplan provisoire (DHCP) pour le build, **purge `ifupdown`** et active `systemd-networkd` et `systemd-resolved`.

Pourquoi purger `ifupdown` : cloud-init choisit son moteur de rendu réseau dans un ordre fixe (`eni`, `sysconfig`, `netplan`, `network-manager`, …, `networkd` : `cloudinit/net/renderers.py`) et retient le premier **disponible**. Avec `ifupdown` installé et `/etc/network/interfaces` présent, il choisit `eni` : il écrit `/etc/network/interfaces.d/50-cloud-init` avec des lignes `dns-nameservers`, que rien n'applique sans le paquet `resolvconf` → un clone en adresse statique **n'a pas de résolveur**. Avec netplan seul, cloud-init écrit `/etc/netplan/50-cloud-init.yaml`, `systemd-networkd` applique l'adresse et `systemd-resolved` le résolveur : c'est la pile de l'image *genericcloud*, et le problème rapporté sur Debian 13 avec Proxmox VE 9 (forum Proxmox, « cloud-init and Debian 13 fails to set DNS ») vient précisément d'une image sans `systemd-resolved`.

Le mot de passe de construction : il circule en clair dans le preseed servi sur le VLAN SANDBOX pendant le build, puis le compte est verrouillé (E05) et supprimé (E07) ; il n'est jamais écrit dans le dépôt. E08 le fait générer par Packer.

*4. Le builder* (voir le fichier). `boot_command` : en BIOS, l'ISO *netinst* démarre sur isolinux (`isolinux/isolinux.cfg`, menu graphique `vesamenu.c32`) ; `Échap` donne l'invite `boot:` ; le libellé `auto` (fichier `isolinux/adtxt.cfg`) ajoute `auto=true priority=critical` ; on lui passe l'URL du preseed et le nom :
```hcl
boot_command = [
  "<esc><wait2>",
  "auto url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg ",
  "hostname=tpl-debian13-base domain=par1.medisphere.internal interface=auto",
  "<enter>",
]
```
`{{ .HTTPIP }}` vaut `http_bind_address` (10.10.10.10) quand elle est fixée. `ssh_timeout = "45m"` : une installation par le réseau prend 10 à 25 minutes. `vga std` pour suivre l'installeur dans la console web, `serials = ["socket"]` et la console noyau `ttyS0` pour le système installé.

*5. Build.* Environ 15 à 25 minutes, dont l'essentiel en téléchargement de paquets. Fin de sortie :
```
==> proxmox-iso.debian13: Provisioning with shell script: /tmp/packer-shell…
    proxmox-iso.debian13: PRETTY_NAME="Debian GNU/Linux 13 (trixie)"
    proxmox-iso.debian13: active
    proxmox-iso.debian13: enabled
    proxmox-iso.debian13: enabled
    proxmox-iso.debian13: ../run/systemd/resolve/stub-resolv.conf
    proxmox-iso.debian13: /usr/bin/cloud-init 25.1.4
    proxmox-iso.debian13: passwd: password changed.
==> proxmox-iso.debian13: Stopping VM
==> proxmox-iso.debian13: Converting VM to template
==> proxmox-iso.debian13: Adding a cloud-init cdrom in storage pool local-nvme
Build 'proxmox-iso.debian13' finished after 19 minutes 40 seconds.
```
(Sortie abrégée et indicative.)

*6. Contrôle.*
```
root@pve01:~# qm clone 9001 2030 --name m03-base-test --pool lab
root@pve01:~# qm set 2030 --tags env-m03 --ipconfig0 ip=10.10.99.250/24,gw=10.10.99.1 \
    --nameserver 10.10.20.10 --searchdomain par1.medisphere.internal \
    --ciuser admin --sshkeys /root/cle-adm01.pub
root@pve01:~# qm disk resize 2030 scsi0 +4G && qm start 2030
admin@adm01:~$ ssh admin@10.10.99.250 'hostname -f; resolvectl dns; df -h /; sudo passwd -S packer'
m03-base-test.par1.medisphere.internal
Global:
Link 2 (eth0): 10.10.20.10
/dev/sda1        12G  1.6G  9.6G  15% /
packer L 2026-10-07 0 99999 7 -1
```
Le disque est passé de 8 à 12 Go et `growpart`/`resizefs` (cloud-init, à chaque démarrage) ont agrandi la partition et le système de fichiers. L'interface s'appelle `eth0` : la configuration réseau générée par Proxmox la nomme ainsi (par adresse MAC). Le compte `packer` est verrouillé (`L`) : il disparaîtra en E07.

**Explications**

- **Chemin d'un build ISO** : Packer crée la VM (API), ouvre son serveur HTTP sur `adm01`, démarre la VM, attend `boot_wait`, tape `boot_command` (API `sendkey`) ; l'installeur obtient une adresse par DHCP (`dns01` via le relais de `gw01`), télécharge le preseed sur `adm01` (flux ouvert), installe depuis les miroirs (NAT de `gw01`), redémarre sur le disque ; l'agent démarre, Packer lit l'adresse, se connecte en SSH, lance les provisioners, arrête la VM et la convertit.
- **`boot_iso {}`** remplace les options de premier niveau (`iso_file`, `iso_url`, `iso_storage_pool`, `unmount_iso`), dépréciées dans le plugin 1.2 (elles produisent un avertissement et seront retirées). `unmount = true` retire l'ISO du template.
- **ISO déposée plutôt que téléchargée par Packer** : Packer sait télécharger (`iso_url` + `iso_checksum`, éventuellement `file:` vers un fichier de sommes) et vérifier une **somme**, mais pas une **signature** ; et le jeton aurait besoin de `Datastore.AllocateTemplate` (téléversement depuis `adm01`, 800 Mo à chaque build) ou de `Sys.AccessNetwork` (téléchargement par `pve01`). Avec `iso_file`, Packer ne vérifie rien : la vérification est faite, mieux, au dépôt.

**Alternatives**

- `iso_url` + `iso_checksum = "file:https://…/SHA256SUMS"` : téléchargement par Packer et contrôle de somme (sans signature) ; nécessite `Datastore.AllocateTemplate`.
- `iso_download_pve = true` : `pve01` télécharge (et vérifie la somme), nécessite `Sys.AccessNetwork` ; à réserver à un compte d'administration.
- Partitionnement LVM : plus souple sur un serveur, mais `growpart` ne gère pas l'extension d'un volume logique ; pour une image clonée, la partition unique est la règle des images *cloud*.
- Construire l'image de base depuis *genericcloud* (E01, question 9).

**Pièges classiques**

- `http_bind_address` absent : Packer écoute sur toutes les interfaces et `{{ .HTTPIP }}` vaut la **première** adresse non locale trouvée, pas forcément celle que la VM peut joindre.
- Ports HTTP par défaut (8000-9000) : la règle de `gw01` ne correspond plus.
- `$` mal échappé dans le gabarit : Packer refuse le fichier ou remplace `${u%/*}` par une variable HCL inexistante. Dans un gabarit, `$${…}` produit `${…}`.
- Swap en fin de disque (recette `atomic`) : la racine ne peut plus grandir.
- `ifupdown` laissé en place : clones sans résolveur en adresse statique, bug « intermittent » (il fonctionne en DHCP).
- Clavier : la ligne tapée l'est en disposition QWERTY (le chargeur ne connaît pas encore le français) ; les caractères spéciaux sont traduits par le plugin, mais une ligne trop longue ou un caractère exotique peuvent arriver déformés : regarde la console.
- Oublier `index = "2"`/`type` dans `boot_iso` est sans conséquence (valeur historique `ide2`), mais le lecteur cloud-init est ensuite ajouté sur un autre port IDE : ne code pas `ide2` en dur dans tes vérifications.
- Lancer le build sans avoir vérifié qu'aucune VM 9001 étrangère n'existe, avec `-force`.

**En production chez MédiSphère**

Un miroir interne des dépôts Debian (et des ISO) supprime la dépendance à Internet pendant les builds et rend la construction reproductible à une date donnée (`snapshot.debian.org` pour rejouer un build ancien). Le preseed est relu comme du code (il exécute des commandes en root dans l'image). L'image de base change rarement ; c'est l'image dorée qui est reconstruite chaque semaine.
