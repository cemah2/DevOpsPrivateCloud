# Module 05 — Palier 4 : Expert — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les corrigés des pannes suivent la trame habituelle : **symptômes → hypothèses → commandes de diagnostic dans l'ordre → cause racine (par variante) → correctif → prévention**. La démarche compte plus que le correctif. En IaC, un correctif trouvé par chance est doublement dangereux : un `tofu apply` lancé « pour voir si ça repart » peut détruire une VM, réécrire l'état ou appliquer un plan que personne n'a relu.

Les scripts d'injection sont dans `corrige/pannes/` (`_m05-commun.sh` contient les fonctions partagées). Toute modification de l'état distant est précédée d'une copie de l'objet courant et de la liste de ses versions dans `/var/lib/workbook/M05-EXX/` sur `adm01` ; les fichiers modifiés sur les hôtes sont sauvegardés dans `/var/lib/workbook/M05-EXX.*` ; la copie de travail et `~/.config/workbook/` dans `~/.local/state/workbook/M05-EXX/`. Plusieurs pannes vérifient leur effet par un vrai plan : une variante sans effet sur ton code (par exemple parce que ton module ignore déjà l'attribut visé) est défaite et remplacée par la suivante.

Les sorties de commandes reproduites ci-dessous sont **représentatives** : VersionId, handles, compteurs, ID de verrou et formulation exacte des messages varient selon ta version (OpenTofu 1.13.x, bpg/proxmox 0.116.x depuis M05-E31, SeaweedFS 4.4x) et ton code.

**Points non testés en conditions réelles** (signale-les si ton comportement diffère) : texte exact de l'erreur « Required plugins are not installed » d'OpenTofu 1.13 quand le paquet en cache ne correspond plus au lock (E41 v2/v3) ; comportement de `tofu console` sur `SIGINT`/`SIGTERM` et libération du verrou (E36 v2) ; texte de l'erreur d'OpenTofu sur un objet de verrou illisible (E36 v4, tiré du code source 1.10 du backend S3) ; code d'erreur renvoyé par SeaweedFS quand l'identité n'a pas `Write` (E37 v4 : `AccessDenied` attendu) ; réécriture de l'état par un `tofu apply` sans changement pendant une rotation de phrase (E41 v4) ; message de Proxmox VE 9 à la création d'une VM dont le VMID existe (E40) ; présence du champ `replace_paths` dans `tofu show -json` d'OpenTofu 1.13 (E44).

---

## Méthode commune aux pannes d'IaC

Un plan a **quatre entrées**. Toute panne de ce palier se ramène à l'une d'elles (ou à l'outillage qui les lit) :

| Entrée | Où la lire | Ce qui la change sans commit |
|---|---|---|
| Configuration | `*.tf`, `*.tofu`, **fichiers de surcharge** `*_override.tf`, modules téléchargés (`.terraform/modules`) | fichier local non suivi (ou ignoré par `.gitignore`), module consommé par une branche mobile |
| Valeurs des variables | `terraform.tfvars`, `*.auto.tfvars` (ordre lexical), `-var`/`-var-file`, `TF_VAR_*` | fichier `*.auto.tfvars` local, variable d'environnement exportée dans un shell |
| État | objet `<clé>` du compartiment (et son verrou `<clé>.tflock`), clé et espace de travail choisis dans `.terraform/` | `tofu state …`, `taint`, une copie S3, un `init -reconfigure`, un `workspace select` |
| Réalité | API Proxmox (et ce que lisent les sources de données : images, versions) | `qm set`, une publication d'image, un collègue dans l'interface web |

Et l'outillage autour : binaire `tofu`, providers installés et `.terraform.lock.hcl`, accès (`~/.config/workbook/`, variables CI), réseau et TLS jusqu'à `pve01` et `s3-01`.

Les mesures, de la moins invasive à la plus invasive :

```
admin@adm01:~/src/infra/socle$ git status --short --ignored        # fichiers que tofu lit mais que git ignore
admin@adm01:~/src/infra/socle$ tofu workspace show; jq .backend.config.key .terraform/terraform.tfstate
admin@adm01:~/src/infra/socle$ tofu state list                     # lit et déchiffre l'état, ne verrouille pas
admin@adm01:~/src/infra/socle$ tofu plan -refresh=false -lock=false  # configuration contre état, sans la réalité
admin@adm01:~/src/infra/socle$ tofu plan -refresh-only -lock=false   # état contre réalité, sans la configuration
admin@adm01:~/src/infra/socle$ aws --profile s3-socle s3api list-object-versions --bucket tofu-state --prefix socle/terraform.tfstate
```

`-lock=false` est acceptable ici **parce que ces commandes n'écrivent rien** (un plan sans `-out` n'écrit pas l'état). Il ne l'est jamais sur une commande qui écrit.

Règle d'or avant toute écriture dans l'état (`state mv/rm`, `untaint`, `import`, restauration) : **copie** de l'objet courant (le versionnage la fait pour toi, à condition de noter le `VersionId` courant avant), **gel** annoncé si l'état est partagé, **une** commande, **un** plan de contrôle.

---

### M05-E35 — Panne : le plan veut recréer une VM du socle

**Démarche de diagnostic**

*Symptôme* : le plan du socle, vide la veille, propose de détruire ou de remplacer une VM permanente, ou s'arrête sur `prevent_destroy`.

*Hypothèses* : changement de configuration non fusionné (fichier local), changement de valeur de variable, état modifié, réalité modifiée sur un attribut qui force le remplacement (*ForceNew*), nouvelle image `current` (écartée d'office si ton code ignore `clone`, comme celui du corrigé de M05-E10).

**Étape 1 — Lire le plan, ou l'erreur.** Selon la variante, deux formes (adresses du corrigé de M05-E16/E17 : VMs importées `proxmox_virtual_environment_vm.socle["…"]`, `s3-01` dans `module.s3_01`) :

```
admin@adm01:~/src/infra/socle$ tofu plan -lock=false
…
│ Error: Instance cannot be destroyed
│
│   on socle-importe.tf line 58:
│   58: resource "proxmox_virtual_environment_vm" "socle" {
│
│ Resource proxmox_virtual_environment_vm.socle["dns01"] has lifecycle.prevent_destroy set, but the plan
│ calls for this resource to be destroyed. To avoid this error and continue with the plan, either disable
│ lifecycle.prevent_destroy or reduce the scope of the plan using the -target option.
```

ou bien un plan qui **aboutit** :

```
  # module.s3_01.proxmox_virtual_environment_vm.vm will be created
  + resource "proxmox_virtual_environment_vm" "vm" {
  …
  # proxmox_virtual_environment_vm.s3_01_avant_refacto will be destroyed
  # (because proxmox_virtual_environment_vm.s3_01_avant_refacto is not in configuration)
  - resource "proxmox_virtual_environment_vm" "s3_01_avant_refacto" {
  …
Plan: 1 to add, 0 to change, 1 to destroy.
```

La seconde forme est la plus dangereuse : **aucune** erreur, un plan « propre » qui détruit `s3-01`. `prevent_destroy` est lu dans le bloc de configuration ; une adresse qui n'a **plus** de bloc n'a plus de `prevent_destroy` (et `s3-01`, gérée par le module depuis M05-E17, n'en a pas : un appel de module ne porte pas de `lifecycle`). Ce qui sauverait la VM à l'apply : la protection Proxmox (`protection = true`, M05-E10 puis argument du module en M05-E17), qui fait échouer la suppression… après que le plan a été approuvé.

**Étape 2 — Couper le problème en deux.**

```
admin@adm01:~/src/infra/socle$ tofu plan -refresh=false -lock=false
```

Si le résultat dangereux persiste, la réalité n'y est pour rien : c'est la configuration, les variables ou l'état. C'est le cas dans les quatre variantes.

**Étape 3 — Photographier les entrées.**

```
admin@adm01:~/src/infra$ git status --short --ignored socle/
?? socle/lucas.auto.tfvars                      ← variante 1
!! socle/.terraform/
!! socle/zz_lucas_override.tf                   ← variante 4 (ignoré par .gitignore)
admin@adm01:~/src/infra/socle$ tofu state list
admin@adm01:~/src/infra/socle$ aws --profile s3-socle s3api list-object-versions --bucket tofu-state --prefix socle/terraform.tfstate \
    --query 'Versions[?Key==`socle/terraform.tfstate`].[LastModified,VersionId,Size,IsLatest]' --output table
```

Une version de l'état créée cette nuit, alors qu'aucun pipeline n'a tourné, désigne les variantes 2 et 3.

**Variante 1 — un `*.auto.tfvars` local redéfinit le nœud.**

```
admin@adm01:~/src/infra/socle$ cat lucas.auto.tfvars
# Essai Lucas : préparation du futur cluster Proxmox (module 09), nœud de test.
# Fichier local, NE PAS COMMITER.
noeud = "pve02"
admin@adm01:~/src/infra/socle$ echo 'var.noeud' | tofu console
"pve02"
```

(`tofu console` prend le verrou le temps de la commande : c'est sans conséquence ici, mais ne le laisse pas ouvert, cf. M05-E36.) Les fichiers `*.auto.tfvars` sont chargés **automatiquement**, après `terraform.tfvars`, dans l'ordre lexical : ils l'emportent. `node_name` change ; avec `migrate = false` (défaut du provider), le provider demande le remplacement de la VM (`ForceNewIf` sur `node_name` dans le code de la ressource). Correctif : retirer le fichier (après en avoir parlé à Lucas : ce fichier est **son** essai) ; ses expériences de cluster iront dans une copie de travail à lui ou un environnement à lui, jamais dans `socle/`.

**Variante 2 — `state mv` vers une adresse orpheline.**

```
admin@adm01:~/src/infra/socle$ tofu state list | grep vm
proxmox_virtual_environment_vm.s3_01_avant_refacto
proxmox_virtual_environment_vm.socle["adm01"]
…
```

L'adresse `module.s3_01.proxmox_virtual_environment_vm.vm` a disparu de l'état, une adresse sans bloc est apparue. Correctif, après avoir noté le `VersionId` courant :

```
admin@adm01:~/src/infra/socle$ tofu state mv proxmox_virtual_environment_vm.s3_01_avant_refacto <ADRESSE-DU-CODE>
admin@adm01:~/src/infra/socle$ tofu plan
No changes. Your infrastructure matches the configuration.
```

`<ADRESSE-DU-CODE>` est l'adresse que le plan voulait créer : `module.s3_01.proxmox_virtual_environment_vm.vm` avec le corrigé de M05-E17 (mets l'adresse entre apostrophes dès qu'elle contient des crochets et des guillemets).

**Variante 3 — la VM est marquée `tainted`.**

```
admin@adm01:~/src/infra/socle$ tofu state show module.s3_01.proxmox_virtual_environment_vm.vm | head -n 2
# module.s3_01.proxmox_virtual_environment_vm.vm: (tainted)
resource "proxmox_virtual_environment_vm" "vm" {
```

Une ressource `tainted` est remplacée au prochain apply, sans que rien n'ait changé dans le code ni dans Proxmox : c'est une marque de l'**état** (posée par `tofu taint` ou par une création qui a échoué à mi-chemin, cf. M05-E38). Avant de la retirer, vérifie que la VM est saine (`qm status 1006`, service S3 qui répond). Puis :

```
admin@adm01:~/src/infra/socle$ tofu untaint module.s3_01.proxmox_virtual_environment_vm.vm
```

**Variante 4 — un fichier de surcharge.**

```
admin@adm01:~/src/infra/socle$ cat zz_lucas_override.tf
# Essai Lucas : préparation du futur cluster Proxmox (module 09).
# Fichier local, NE PAS COMMITER.
resource "proxmox_virtual_environment_vm" "socle" {
  node_name = "pve02"
}
```

Le bloc visé est le premier bloc VM de la racine de ton code (`socle`, qui porte les quatre VMs importées, dans le corrigé) : les quatre VMs seraient remplacées, `prevent_destroy` arrête le plan. Les fichiers `override.tf` et `*_override.tf` sont **fusionnés** dans les blocs de même adresse, après tous les autres fichiers. Ils sont prévus pour des exceptions locales… et ton `.gitignore` (M05-E02) les ignore : `git status` sans `--ignored` ne les montre pas. Correctif : supprimer le fichier.

**Correctif commun et vérification** : plan vide ; `qm config 1006 | grep -E '^(name|meta)'` montre la même date de création (`meta: … ctime=`) qu'avant l'incident ; `lab/bin/check 05 35`, puis `lab/bin/break 05 35 --annuler` pour clore.

**Prévention**
- Le plan de référence est celui de la **CI**, calculé sur une copie propre de la branche : il n'aurait vu ni la variante 1 ni la variante 4. Mais un plan de dérive planifié de `main` (M05-E28) aurait vu les variantes 2 et 3 dès la nuit.
- Contrôle de plan dans le pipeline (« Pour aller plus loin ») : échec si une action `delete` vise une VM de VMID 1000-1099.
- Validation de la variable `noeud` contre la liste réelle des nœuds (source de données `proxmox_virtual_environment_nodes`), ou contre une valeur unique tant que le socle n'a qu'un nœud.
- Hygiène du bastion : un `tofu plan` depuis `adm01` se lance sur une copie **propre** (`git status --ignored` vide, hors `.terraform/`) ; les essais vont dans `~/m05/…`.
- Les opérations sur l'état (`mv`, `rm`, `taint`) passent par des blocs `moved`/`removed` en MR, ou, à défaut, par une procédure écrite avec copie préalable.

**Explications**

Le provider, pas OpenTofu, décide qu'un changement d'attribut exige un remplacement : il le signale dans sa réponse à `PlanResourceChange` (M05-E44). Dans bpg/proxmox 0.115, la ressource VM marque ainsi `node_name` (sauf `migrate = true`), `vm_id`, tout le bloc `clone`, les identifiants de fichiers cloud-init (`initialization.*_data_file_id`) et quelques cas (TPM, disque EFI). C'est pourquoi les modules ignorent `clone` : la nouvelle image hebdomadaire recréerait sinon chaque VM.

**Alternatives**
- Variante 2 : un bloc `moved { from = proxmox_virtual_environment_vm.s3_01_avant_refacto  to = module.s3_01.proxmox_virtual_environment_vm.vm }` en MR répare aussi, et laisse une trace relue ; mais il garde dans le code la mémoire d'une adresse qui n'a jamais existé que par erreur. Restaurer la version précédente de l'état (M05-E42) est équivalent si **rien d'autre** n'a été écrit depuis (compare les `serial`).
- Variante 3 : `tofu apply -replace=…` est le geste moderne pour forcer un remplacement ; `tofu taint` existe encore mais laisse une marque invisible dans le code, que le prochain venu découvre par surprise.

**Pièges classiques**
- Commenter `prevent_destroy` « pour voir le plan » : le plan suivant, appliqué par erreur, détruit la VM.
- Chercher dans l'historique Git un changement qui n'y est pas : deux des quatre causes ne sont pas dans le dépôt, et une ne s'affiche pas dans `git status`.
- Réparer la variante 2 par un apply (créer la nouvelle, détruire l'ancienne) : `s3-01` porte l'état ; la détruire, c'est perdre le stockage de l'état pendant qu'OpenTofu l'écrit.

**En production chez MédiSphère**

Le job de plan échoue sur toute destruction d'une VM du socle ; un second regard (Karim ou Claire) est exigé pour l'outrepasser. Les commandes `tofu state` sur le socle sont réservées au runbook RB-051 (restauration) et aux blocs `moved`/`removed`.

---

### M05-E36 — Panne : « Error acquiring the state lock »

**Démarche de diagnostic**

*Symptôme* : toute commande qui prend le verrou (plan, apply, `state …`, console) échoue sur `socle/` (ou `envs/lab-m05/` en variante 3).

**Étape 1 — Lire le message.**

```
admin@adm01:~/src/infra/socle$ tofu plan
╷
│ Error: Error acquiring the state lock
│
│ Error message: operation error S3: PutObject, https response error StatusCode: 412, RequestID: …,
│ api error PreconditionFailed: At least one of the pre-conditions you specified did not hold
│ Lock Info:
│   ID:        6f1d2a4e-93b0-4b51-8c7e-0f2c95d1e3a7
│   Path:      tofu-state/socle/terraform.tfstate
│   Operation: OperationTypeApply
│   Who:       gitlab-runner@runner01
│   Version:   1.13.2
│   Created:   2026-10-14 22:41:07.4161 +0000 UTC
│   Info:
│
│ OpenTofu acquires a state lock to protect the state from being written
│ by multiple users at the same time. Please resolve the issue above and try
│ again. For most commands, you can disable locking with the "-lock=false"
│ flag, but this is not recommended.
```

Le `412` est la preuve que le mécanisme fonctionne : OpenTofu a tenté de **créer** `socle/terraform.tfstate.tflock` avec `If-None-Match: *`, l'objet existait, le stockage a refusé. OpenTofu a alors lu l'objet pour afficher `Lock Info`.

**Étape 2 — Lire l'objet directement.**

```
admin@adm01:~$ aws --profile s3-socle s3api head-object --bucket tofu-state --key socle/terraform.tfstate.tflock
admin@adm01:~$ aws --profile s3-socle s3 cp s3://tofu-state/socle/terraform.tfstate.tflock - | jq .
```

**Étape 3 — Trouver le détenteur.**

| Champ | Question | Commande |
|---|---|---|
| `Who: gitlab-runner@runner01` | un job tourne-t-il ? | Interface GitLab, *Build → Jobs* de `plateforme/infra` (ou `GET /projects/:id/jobs?scope[]=running`) ; `ssh runner01 pgrep -a tofu` |
| `Who: admin@adm01` | un processus tourne-t-il ? | `pgrep -a tofu`, `ps -o pid,sid,tty,etimes,args -C tofu` |
| `Created` | depuis quand ? | la date seule ne prouve rien : un apply long peut durer |

**Variante 1 — orphelin de la CI.** Aucun job en cours ; le dernier job `apply` de `main` est **annulé** (ou en délai dépassé) à l'heure de `Created` ; aucun processus `tofu` sur `runner01`. Le verrou est orphelin. Mais un apply interrompu a pu écrire une **partie** de ses changements : avant de libérer, note le `VersionId` courant de l'état, et après avoir libéré, lance un plan pour voir ce qui reste à faire.

```
admin@adm01:~/src/infra/socle$ tofu force-unlock 6f1d2a4e-93b0-4b51-8c7e-0f2c95d1e3a7
Do you really want to force-unlock?
  …
  Enter a value: yes

OpenTofu state has been successfully unlocked!
```

**Variante 2 — verrou vivant.**

```
admin@adm01:~$ pgrep -a tofu
48211 tofu console -no-color
admin@adm01:~$ ps -o pid,sid,tty,etimes,args -p 48211
    PID     SID TT        ELAPSED COMMAND
  48211   48211 ?           31544 tofu console -no-color
```

Une console OpenTofu détachée de tout terminal, ouverte depuis près de 9 heures : la documentation de `tofu console` le dit, la console **garde** le verrou tant qu'elle tourne. Un `force-unlock` « marcherait »… et laisserait un processus qui se croit propriétaire du verrou. Avec une console, sans conséquence ; avec un apply, deux écritures concurrentes de l'état. Le bon geste : retrouver le propriétaire (le compte est `admin` : demande dans l'équipe qui a ouvert une console hier) et terminer **proprement** le processus : `kill -TERM 48211` (OpenTofu intercepte `SIGINT` et `SIGTERM`, termine et libère le verrou ; ⚠️ à vérifier sur ta version pour la console). Jamais `kill -9` : le verrou resterait. Vérifie ensuite que l'objet `.tflock` a disparu sans `force-unlock`.

**Variante 3 — orphelin sur `envs/lab-m05`, posé depuis `adm01`.** `Who: admin@adm01`, `Operation: OperationTypePlan`, `Created` de la veille au soir, aucun processus `tofu` : un plan interrompu brutalement (session SSH coupée, `kill -9`). `journalctl _COMM=sshd --since yesterday` montre une déconnexion à l'heure de `Created`. `tofu force-unlock <ID>` dans `envs/lab-m05/`. Un plan n'écrit pas l'état : rien d'autre à vérifier.

**Variante 4 — objet de verrou illisible.**

```
│ Error: Error acquiring the state lock
│
│ Error message: 2 errors occurred:
│ 	* operation error S3: PutObject, https response error StatusCode: 412, …, api error PreconditionFailed: …
│ 	* unable to json parse the lock info "socle/terraform.tfstate.tflock" from bucket "tofu-state": invalid character 'e' looking for beginning of value
admin@adm01:~$ aws --profile s3-socle s3 cp s3://tofu-state/socle/terraform.tfstate.tflock -
essai M05-E12 : écriture conditionnelle (if-none-match) — à supprimer
```

Pas d'ID, donc pas de `force-unlock` possible. C'est le reste d'un essai d'écriture conditionnelle fait à la main **sur la clé du verrou** (le script de M05-E12 utilise un préfixe `_essais/` justement pour éviter cela). Après avoir vérifié qu'aucun `tofu` ne tourne nulle part (variante 1, étape 3), supprime l'objet :

```
admin@adm01:~$ aws --profile s3-socle s3api delete-object --bucket tofu-state --key socle/terraform.tfstate.tflock
```

(Compartiment versionné : un marqueur de suppression est créé, l'objet reste dans l'historique ; la prochaine écriture conditionnelle d'OpenTofu réussit, car aucun objet **courant** n'existe.)

**Correctif commun et vérification** : `tofu plan` passe dans les deux répertoires ; `aws … list-object-versions --prefix socle/terraform.tfstate` montre que la **version de l'état** n'a pas bougé (sauf apply partiel de la variante 1, à analyser) ; RB-050 complété ; `lab/bin/check 05 36`.

**Prévention**
- Pipeline : `resource_group` sur les jobs d'apply (M05-E26) pour sérialiser en amont du verrou, `-lock-timeout=5m` pour absorber une contention courte, `interruptible: false` sur `apply` pour qu'un nouveau pipeline ne l'annule pas à mi-chemin.
- Sur `adm01` : jamais de console ni d'apply dans une session non gérée ; `tmux` nommé (`tmux new -s tofu-<ticket>`) si une opération est longue.
- Sonde : alerte si un objet `*.tflock` a plus de 2 heures.

**Explications**

Le verrou S3 natif est un objet : le prendre = le créer de façon conditionnelle ; le rendre = le supprimer après avoir vérifié l'ID. `force-unlock` fait exactement la seconde moitié, **sans** savoir si le détenteur vit encore : la preuve est ton travail.

**Alternatives** : `aws s3api delete-object` sur la clé du verrou fait la même chose que `force-unlock`, sans la vérification de l'ID ; à réserver au cas où l'objet est illisible.

**Pièges classiques**
- `-lock=false` sur un apply « parce que le verrou est forcément orphelin ».
- Libérer le verrou d'un apply CI annulé sans relancer un plan : l'état reflète un apply partiel.
- Prendre `Created` pour une preuve d'abandon : un apply de 40 VMs peut durer une heure.

**En production chez MédiSphère** : RB-050 impose un message dans `#plateforme` avant tout `force-unlock` sur `socle`, avec l'ID, le `Who` et la preuve d'abandon ; le post-mortem est obligatoire si un apply a été interrompu.

---

### M05-E37 — Panne : le backend d'état est inaccessible

**Démarche de diagnostic**

*Symptôme* : `tofu plan` échoue sur le backend. *Hypothèses*, de bas en haut : résolution du nom, chemin réseau et filtrage, service S3, TLS, identifiants, autorisations (dont l'écriture du verrou).

**Étape 1 — Le pipeline est-il touché ?** Relance le dernier pipeline de `main` (ou une MR de test). `runner01` est dans le même VLAN que `s3-01` : il n'emprunte pas `gw01` et a son propre `/etc/hosts`. Le résultat sépare déjà les variantes :

| Test | V1 (hosts) | V2 (certificat) | V3 (filtrage) | V4 (droits) |
|---|---|---|---|---|
| Pipeline (plan) | OK | **KO** (x509) | OK | **KO** (verrou) |
| `getent hosts s3-01.par1…` sur `adm01` | **10.10.20.41** | 10.10.20.14 | 10.10.20.14 | 10.10.20.14 |
| `dig +short @10.10.20.10 s3-01.par1…` | 10.10.20.14 | 10.10.20.14 | 10.10.20.14 | 10.10.20.14 |
| TCP/8333 depuis `adm01` | KO (vers .41) | OK | **KO** (délai) | OK |
| TLS (`curl -v`) | — | **KO** (autorité inconnue) | — | OK |
| `aws s3api list-objects-v2` | KO | KO | KO | OK |
| `tofu state list` | KO | KO | KO | **OK** |
| `tofu plan` (avec verrou) | KO | KO | KO | **KO** (AccessDenied) |

**Variante 1 — `/etc/hosts` de `adm01`.**

```
admin@adm01:~/src/infra/socle$ tofu plan
│ Error: error loading state: … dial tcp 10.10.20.41:8333: connect: no route to host
admin@adm01:~$ getent hosts s3-01.par1.medisphere.internal
10.10.20.41     s3-01.par1.medisphere.internal s3-01
admin@adm01:~$ grep -n s3-01 /etc/hosts
9:10.10.20.41  s3-01.par1.medisphere.internal s3-01   # migration stockage S3 (InfoGér, ne pas retirer)
```

`/etc/nsswitch.conf` met `files` avant `dns` : le fichier gagne, pour la bibliothèque C, pour Python (AWS CLI) et pour le résolveur de Go qu'utilise OpenTofu. 10.10.20.41 était `sem01`, détruite en M04 : plus personne ne répond, `gw01` renvoie « hôte injoignable ». Correctif : retirer la ligne. Prévention : `/etc/hosts` est géré par le rôle `base` (gabarit), et la détection de dérive d'Ansible l'aurait signalé ; la règle « nom de service dans le DNS, jamais dans `/etc/hosts` » va dans les conventions.

**Variante 2 — certificat auto-signé sur `s3-01`.**

```
│ Error: … tls: failed to verify certificate: x509: certificate signed by unknown authority
admin@adm01:~$ openssl s_client -connect s3-01.par1.medisphere.internal:8333 -servername s3-01.par1.medisphere.internal </dev/null 2>/dev/null | openssl x509 -noout -issuer -subject -dates
issuer=CN=s3-01.par1.medisphere.internal
subject=CN=s3-01.par1.medisphere.internal
notBefore=Oct 14 18:02:11 2026 GMT
```

Émetteur = sujet : certificat auto-signé, émis hier soir. Le nom et le SAN sont bons : seule la chaîne de confiance manque. Correctif : redéployer le certificat signé par la CA provisoire **par le rôle Ansible `seaweedfs`** (qui le gère depuis M05-E10), qui redémarre la passerelle ; vérifier avec `openssl s_client … -verify_return_error`. Ne pas ajouter ce certificat à la confiance de `adm01` : ce serait faire confiance à n'importe quel serveur qui se présente sous ce nom.

**Variante 3 — filtrage à chaud sur `gw01`.**

```
│ Error: … dial tcp 10.10.20.14:8333: i/o timeout
root@gw01:~# nft -a list chain inet filter forward | grep 8333
	ip saddr 10.10.10.0/24 ip daddr 10.10.20.14 tcp dport 8333 counter packets 37 bytes 2220 drop comment "temp LM 0412 : isolement s3-01 pendant tests de charge" # handle 87
```

Le compteur augmente à chaque essai depuis `adm01`. La règle n'est pas dans `host_vars/gw01/pare_feu.yml` (M04) : modification à chaud. Correctif : réappliquer le rôle `pare_feu` par la chaîne de M04 (rechargement complet, `--check --diff` d'abord : il montre la règle en trop), ou, en urgence, `nft delete rule inet filter forward handle 87`, puis vérifier que la configuration persistante n'a jamais contenu la règle.

**Variante 4 — l'identité `tofu-etat` a perdu l'écriture.**

```
admin@adm01:~/src/infra/socle$ tofu state list        # fonctionne
admin@adm01:~/src/infra/socle$ tofu plan
│ Error: Error acquiring the state lock
│ Error message: operation error S3: PutObject, https response error StatusCode: 403, …, api error AccessDenied: Access Denied.
admin@s3-01:~$ sudo jq '.identities[] | select(.name == "tofu-etat") | .actions' <FICHIER-IDENTITÉS>
[
  "Read:tofu-state",
  "List:tofu-state"
]
```

`<FICHIER-IDENTITÉS>` est le fichier passé à `-s3.config` (voir `systemctl cat <unité>` ou `ps -o args -C weed`). Lire fonctionne, écrire non : le plan échoue **au verrou**, avant de lire quoi que ce soit, ce qui ressemble à une panne de verrou (M05-E36) mais n'en est pas une (code 403, pas 412). Correctif : rétablir `Write:tofu-state` **par le rôle `seaweedfs`** (source de vérité des identités), qui recharge le service.

**Vérification** : matrice entièrement verte, script de M05-E12 vert, `lab/bin/check 05 37`.

**Prévention** : sonde S3 complète depuis `adm01` **et** `runner01` (« Pour aller plus loin ») ; détection de dérive Ansible sur `adm01`, `gw01` et `s3-01` ; règles temporaires de `gw01` uniquement par le rôle, avec date d'expiration.

**Explications** : un backend distant ajoute une chaîne de dépendances à chaque commande OpenTofu. `TF_LOG=debug` affiche les requêtes du SDK AWS (méthode, URL, code HTTP) : c'est la façon la plus rapide de savoir à quel maillon on échoue quand le message est tronqué.

**Pièges classiques**
- Ajouter `insecure`/`skip_tls_verify` ou une IP dans `endpoints` : on masque la panne, on garde une faille.
- Confondre 412 (verrou pris), 403 (droits) et 404 (objet absent) : trois pannes différentes.
- Corriger sur `s3-01` à la main sans passer par le rôle : la prochaine exécution d'Ansible réintroduit… ou défait la correction.

**En production chez MédiSphère** : `s3-01` porte l'état de toute l'infrastructure ; il entre dans le périmètre de supervision P1 (module 21) et son certificat sera émis par step-ca avec renouvellement automatique (module 06).

---

### M05-E38 — Panne : l'apply échoue sur un refus de droits

**Démarche de diagnostic**

*Symptôme* : plan correct, apply en échec, message `Permission check failed`. *Pourquoi le plan passe* : il ne fait que lire (`VM.Audit`, `Datastore.Audit`, `Pool.Audit`, lecture des étiquettes) ; chaque écriture demande un privilège de plus, sur un chemin précis.

**Étape 1 — Lire l'erreur et l'apply partiel.**

```
module.app["app04"].proxmox_virtual_environment_vm.vm: Creating...
╷
│ Error: error updating VM: received an HTTP 403 response - Reason: Permission check failed (/vms/2051, VM.Config.Memory)
```

Selon la variante, le chemin et le privilège cités :

| Variante | Message (extrait) | Ce qui a été fait avant l'erreur |
|---|---|---|
| 1 | `(/vms/2051, VM.Config.Memory)` | la nouvelle VM a pu être créée ; les mises à jour de mémoire échouent une à une |
| 2 | `(/sdn/zones/lab/vsandbox, SDN.Use)` | rien, ou une VM clonée sans carte réseau valide |
| 3 | `(/storage/local-nvme, Datastore.AllocateSpace)` | rien : le clonage complet est refusé |
| 4 | `(/vms/<VMID>, VM.PowerMgmt)` | la VM est créée **et configurée**, son démarrage est refusé |

```
admin@adm01:~/src/infra/envs/lab-m05$ tofu state list
admin@adm01:~/src/infra/envs/lab-m05$ tofu state show 'module.app["app04"].proxmox_virtual_environment_vm.vm' | head -n 1
# module.app["app04"].proxmox_virtual_environment_vm.vm: (tainted)
```

En variante 4, la VM existe dans Proxmox et dans l'état, marquée `tainted` : le prochain plan propose de la **remplacer**.

**Étape 2 — Remonter la chaîne des droits sur `pve01`.**

```
root@pve01:~# pveum user token list wb-tofu@pve
│ tokenid │ comment │ expire     │ privsep │
│ tofu    │ …       │ 1791936000 │ 1       │
root@pve01:~# pveum user token permissions wb-tofu@pve tofu --path /vms/2051
root@pve01:~# pveum acl list | grep -E 'wb-tofu'
root@pve01:~# pveum role list --output-format json | jq -r '.[] | select(.roleid == "WBTofu") | .privs'
```

Avec `privsep = 1`, les droits effectifs du jeton sont l'**intersection** des ACL de l'utilisateur et des ACL du jeton : une ACL manquante d'un seul côté suffit à refuser.

**Variante 1 / variante 4 — privilège retiré du rôle `WBTofu`.** La liste des privilèges du rôle ne contient plus `VM.Config.Memory` (ou `VM.PowerMgmt`). Correctif au plus juste, puis report dans le script de M05-E03 qui définit le rôle :

```
root@pve01:~# pveum role modify WBTofu --privs VM.Config.Memory --append 1
```

**Variante 2 — ACL du VNet supprimée pour le jeton.**

```
root@pve01:~# pveum acl list | grep vsandbox
│ /sdn/zones/lab/vsandbox │ user  │ wb-tofu@pve       │ PVESDNUser │ 1 │
```

L'utilisateur a toujours son ACL, le jeton ne l'a plus. Correctif :

```
root@pve01:~# pveum acl modify /sdn/zones/lab/vsandbox --roles PVESDNUser --tokens 'wb-tofu@pve!tofu'
```

**Variante 3 — ACL du stockage supprimée pour le jeton.** Même lecture, chemin `/storage/local-nvme`, rôle `PVEDatastoreUser` :

```
root@pve01:~# pveum acl modify /storage/local-nvme --roles PVEDatastoreUser --tokens 'wb-tofu@pve!tofu'
```

**Étape 3 — Terminer proprement l'apply partiel.** Variante 4 : la VM créée est saine (même configuration que les autres) ; `tofu untaint 'module.app["app04"].proxmox_virtual_environment_vm.vm'` évite une destruction inutile, puis l'apply la démarre. Si tu préfères repartir d'une VM neuve (elle est jetable), laisse OpenTofu la remplacer : c'est aussi correct, à condition de le **décider**. Puis la demande de Julien par la chaîne normale ; plan vide ; `tofu show -json | jq '[..|objects|select(.tainted?==true)]|length'` vaut 0.

**Vérification** : `lab/bin/check 05 38` (privilèges effectifs du jeton, absence de droits d'administration, environnement appliqué).

**Prévention** : test de non-régression des droits (« Pour aller plus loin ») dans le pipeline de dérive ; toute modification des rôles et ACL de `pve01` passe par le script versionné de M05-E03 (ou, plus tard, par un rôle Ansible) ; le registre des secrets décrit la portée du jeton.

**Explications** : l'arbre des permissions de Proxmox a plusieurs branches : `/vms`, `/pool`, `/storage`, `/sdn`, `/nodes`. Une VM du pool `lab` hérite des ACL de `/pool/lab` pour ce qui la concerne, mais créer une VM consomme aussi du stockage et branche une carte sur un VNet, qui sont d'autres chemins.

**Alternatives** : un rôle unique sur `/` avec propagation simplifierait… et donnerait au jeton le droit de toucher aux VMs personnelles de `pve01`, au pare-feu et aux utilisateurs. La séparation `/pool/lab` + stockages + VNets est le moindre privilège.

**Pièges classiques**
- Donner `PVEVMAdmin` ou `Administrator` au jeton « pour débloquer » : interdit par le ticket, et le contrôle le vérifie.
- Corriger l'ACL de l'utilisateur alors que c'est celle du jeton qui manque (ou l'inverse) : relis la règle d'intersection.
- Relancer l'apply sans lire l'état : la ressource `tainted` est remplacée sans que personne l'ait voulu.

**En production chez MédiSphère** : les droits des comptes d'automatisation sont décrits en code et testés ; un refus de droits en CI déclenche une alerte, pas une élévation.

---

### M05-E39 — Panne : la VM est créée mais injoignable

**Démarche de diagnostic**

*Symptôme* : l'apply réussit (ou attend l'agent QEMU puis expire), la VM tourne, SSH depuis `adm01` échoue.

**Étape 1 — Relire le plan de l'apply.** En variante 4, il contenait **plus** que la nouvelle VM :

```
  # module.app["app01"].proxmox_virtual_environment_vm.vm will be updated in-place
  ~ resource "proxmox_virtual_environment_vm" "vm" {
      ~ initialization {
          ~ user_account {
              ~ keys     = [
                  - "ssh-ed25519 AAAAC3Nz… admin@adm01",
                  + "ssh-ed25519 AAAAC3Nz… lucas.martin@poste-lucas",
                ]
```

Ce bloc était l'indice : une modification que personne n'a demandée.

**Étape 2 — Ce que sait la VM, sans SSH.**

```
root@pve01:~# qm guest cmd 2059 network-get-interfaces | jq -r '.[] | .name + " " + ([."ip-addresses"[]?."ip-address"] | join(" "))'
lo 127.0.0.1 ::1
ens18 fe80::be24:11ff:fe5a:1c03                 ← variantes 1 et 3 : aucune IPv4
```

Avec une IPv4 10.10.99.1xx (variantes 2 et 4), passe à l'étape 4.

**Étape 3 — Chemin DHCP (variantes 1 et 3).** Redémarre la VM (`qm reboot 2059`) en capturant sur `gw01` :

```
root@gw01:~# tcpdump -ni ens19.99 -c 6 port 67 or port 68
IP 0.0.0.0.68 > 255.255.255.255.67: BOOTP/DHCP, Request from bc:24:11:5a:1c:03, length 300
IP 0.0.0.0.68 > 255.255.255.255.67: BOOTP/DHCP, Request from bc:24:11:5a:1c:03, length 300
```

Les demandes arrivent sur `ens19.99` ; `tcpdump` voit les paquets **avant** le filtrage (hook d'entrée). Puis :

```
root@gw01:~# nft list chain inet filter input | grep -E 'dport (67|bootps)'
		iifname "ens19.99" udp dport 67 counter packets 14 bytes 4704 drop comment "SEC-683 test filtrage DHCP sandbox (LM)"
```

*Variante 1* : le relais ne reçoit jamais les demandes, jetées en entrée de `gw01`. Correctif : réappliquer le rôle `pare_feu` (M04), qui recharge le jeu de règles de référence.

*Variante 3* : aucune règle sur `gw01`, le relais transmet (`journalctl -u dnsmasq` sur `gw01`), mais sur `dns01` :

```
admin@dns01:~$ sudo journalctl -u dnsmasq --since -10min | grep -i dhcp
dnsmasq-dhcp[612]: DHCPDISCOVER(ens18) 10.10.99.1 bc:24:11:5a:1c:03 ignored
admin@dns01:~$ grep -rn dhcp-ignore /etc/dnsmasq.d/
/etc/dnsmasq.d/90-sec-683.conf:3:dhcp-ignore=tag:!known
```

`dhcp-ignore=tag:!known` ignore toute machine sans réservation `dhcp-host` : exactement toutes les VMs d'environnement. Sophie voulait réserver les adresses aux machines **déclarées** ; dans un VLAN de bac à sable créé par l'IaC, c'est contradictoire avec le DHCP dynamique. Correctif : retirer ce fichier (rôle `dnsmasq` de M04 appliqué, qui ne connaît pas ce fichier : vérifie s'il purge le dossier ou non), et répondre à SEC-683 : la déclaration des machines viendra de NetBox et des réservations Kea au module 06.

**Étape 4 — Chemin `adm01` → VM (variante 2).**

```
admin@adm01:~$ ping -c 2 10.10.99.142        # répond
admin@adm01:~$ ssh -o ControlPath=none -o ConnectTimeout=5 admin@10.10.99.142
ssh: connect to host 10.10.99.142 port 22: Connection timed out
root@gw01:~# nft list chain inet filter forward | grep 10.10.99.0/24
		ip saddr 10.10.10.0/24 ip daddr 10.10.99.0/24 tcp dport 22 counter packets 9 bytes 540 drop comment "SEC-683 test isolement sandbox (LM)"
```

ICMP passe, TCP/22 non, le compteur monte : filtrage à chaud. Correctif : rôle `pare_feu`.

**Étape 5 — Authentification (variante 4).**

```
admin@adm01:~$ ssh -v -o ControlPath=none admin@10.10.99.142 true 2>&1 | tail -n 3
debug1: Offering public key: /home/admin/.ssh/id_ed25519 ED25519 SHA256:…
debug1: Authentications that can continue: publickey
admin@10.10.99.142: Permission denied (publickey).
root@pve01:~# qm cloudinit dump 2059 user | grep -A2 ssh_authorized_keys
```

La clé injectée est celle de Lucas, et seulement elle. Correctif : rétablir `cles_ssh_admin` (`git restore envs/lab-m05/terraform.tfvars`) ; Lucas ajoutera sa clé **en plus** par une MR, s'il en a besoin. La nouvelle VM, elle, a déjà fait son premier démarrage avec la mauvaise clé : cloud-init n'applique les clés qu'une fois par instance. Le plus simple pour une VM neuve et jetable : `tofu apply -replace='<ADRESSE-DE-LA-VM>'` sur le plan relu. Les autres VMs n'ont reçu que la mise à jour du lecteur cloud-init (effective seulement à un changement d'instance) : un apply avec la bonne clé la rétablit.

**Vérification** : chaque VM `env-m05` démarrée a une IPv4 10.10.99.x et accepte une connexion SSH **neuve** (`-o ControlPath=none`) ; plan vide ; `lab/bin/check 05 39`.

**Prévention**
- Un `check` OpenTofu (« Pour aller plus loin ») qui avertit quand une VM démarrée n'a pas d'adresse attendue.
- Les clés autorisées viennent d'une seule source (la variable, alimentée par la clé de `adm01` et des clés nominatives **ajoutées** par MR), et le plan de MR est relu : un `~ keys` sur toutes les VMs est un signal.
- Les règles temporaires de `gw01` passent par le rôle `pare_feu`, avec date d'expiration ; toute modification de `dnsmasq` par le rôle `dnsmasq`.

**Explications** : OpenTofu garantit l'**objet** (une VM, son matériel, son lecteur cloud-init) ; il ne voit pas ce qui se passe dans le réseau ni dans l'invité. L'attente de l'agent QEMU (le provider attend des adresses quand l'agent est activé) est le seul pont, et il ne dit pas **pourquoi** l'adresse manque.

**Pièges classiques**
- Poser un mot de passe par `qm guest passwd` « pour entrer » et oublier de le retirer.
- Donner une adresse statique à la VM pour contourner le DHCP : la panne reste pour la suivante.
- Ajouter une règle `accept` en tête de chaîne sur `gw01` : elle masque la règle fautive, qui reviendra au prochain rechargement… ou restera, invisible.

**En production chez MédiSphère** : chaque création de VM par le pipeline se termine par un test de joignabilité (SSH, ou sonde applicative) ; un échec marque le job en erreur même si l'apply a réussi.

---

### M05-E40 — Panne : l'état ne correspond plus à la réalité

**Démarche de diagnostic**

*Symptôme* : en ajoutant la VM demandée, le plan propose des actions non demandées, ou l'apply échoue.

**Étape 1 — Classer chaque ligne du plan.**

| Variante | Ligne non demandée | Écart |
|---|---|---|
| 1 | `# module.app["app02"].proxmox_virtual_environment_vm.vm will be created` | la VM 2052 existe dans Proxmox, l'état ne la connaît plus |
| 2 | `~ memory { ~ dedicated = 2048 -> 1024 }`, `~ tags = [ - "essai-perf", … ]`, `~ description` | la VM a été modifiée à la main |
| 3 | aucune ; l'apply échoue : `unable to create VM <VMID>: config file already exists` (formulation selon la version de Proxmox) | une VM inconnue de l'état occupe le VMID |

**Étape 2 — Mesurer sans écrire.**

```
admin@adm01:~/src/infra/envs/lab-m05$ tofu plan -refresh-only -lock=false
root@pve01:~# pvesh get /nodes/<NOEUD>/tasks --vmid 2052 --limit 10
root@pve01:~# qm list | awk '$1 >= 2050 && $1 <= 2059'
root@pve01:~# for id in $(seq 2050 2059); do qm config $id 2>/dev/null | grep -E '^(name|tags|description):' | sed "s/^/$id /"; done
admin@adm01:~$ aws --profile s3-socle s3api list-object-versions --bucket tofu-state --prefix envs/lab-m05/terraform.tfstate \
    --query 'Versions[?Key==`envs/lab-m05/terraform.tfstate`].[LastModified,Size]' --output table
```

- *Variante 1* : aucune tâche Proxmox sur 2052 cette nuit, mais une nouvelle version de l'état, **plus petite** : quelqu'un a retiré la VM de l'état (`tofu state rm`), la VM n'a pas bougé.
- *Variante 2* : une tâche `qmconfig` de `root@pam` sur la VM, à l'heure de la modification ; la description dit pourquoi (« tests de charge », Julien).
- *Variante 3* : une tâche `qmclone` vers le VMID demandé, une VM `m05-charge-manuel` arrêtée, étiquetée `env-m05`, **clone lié** (`qm config` : disque `base-90xx-disk-0/vm-<VMID>-disk-0`).

**Étape 3 — Réconcilier, après accord du demandeur.**

*Variante 1 — importer.* La VM est saine et décrite par le code : elle doit revenir dans l'état, à son adresse.

```hcl
# envs/lab-m05/imports.tf — réimport de la VM sortie de l'état par erreur (DEV-682)
import {
  to = module.app["app02"].proxmox_virtual_environment_vm.vm
  id = "<NOEUD>/2052"
}
```

Le plan doit annoncer `1 to import, 0 to change` (plus la VM demandée) ; s'il annonce aussi des changements, ton code ne décrit pas la VM telle qu'elle est (attribut par défaut du provider, par exemple) : corrige le code, pas la VM. Après l'apply, le bloc `import` peut rester (il est sans effet une fois la ressource dans l'état) ou être retiré dans une MR suivante. Alternative valable : restaurer la version précédente de l'état (M05-E42), si **rien** n'a été écrit depuis.

*Variante 2 — adopter ou défaire.* Julien a besoin de la mémoire : on l'**adopte** dans le code (valeur `memoire_mo` de cette VM dans `terraform.tfvars`). L'étiquette `essai-perf` et la description manuelle n'ont pas de raison d'être : l'apply les **défait**. `tofu apply -refresh-only` seul n'aurait rien réglé : il recopie la réalité dans l'état, mais le plan suivant comparerait toujours le code (1024) à l'état (2048) et proposerait de revenir à 1024. Le code est la seule source à corriger.

*Variante 3 — supprimer l'orphelin.* La VM manuelle est un clone **lié** (interdit pour une VM durable, règle de M03), sans données utiles (Julien le confirme : il voulait « juste tester »). On la détruit (`qm destroy <VMID> --purge 1`, après `qm config` gardé dans le journal), puis la VM demandée est créée par la chaîne. L'importer aurait fait entrer dans l'état une VM que le code ne sait pas décrire (pas de `clone` complet, disques liés au template).

**Vérification** : VMs `env-m05` de Proxmox = VMs des états `envs/lab-m05` et `envs/recette-m05` ; plan vide ; aucune VM préexistante recréée (dates de création inchangées) ; `lab/bin/check 05 40`.

**Prévention** : détection de dérive planifiée (M05-E28) étendue aux **objets orphelins** (« Pour aller plus loin ») ; `tofu state rm` réservé au runbook, remplacé en équipe par un bloc `removed` relu en MR ; règle « une VM d'environnement se crée par l'environnement, jamais à la main ».

**Explications** : `-refresh-only` répond à la question « que sait l'état de la réalité ? », pas « que doit être la réalité ? ». Un import répond à « cet objet existe-t-il pour OpenTofu ? ». Aucune de ces commandes ne choisit à ta place qui a raison : c'est une décision humaine, tracée.

**Pièges classiques**
- Laisser OpenTofu « recréer » la VM 2052 de la variante 1 : l'apply échoue (le VMID existe), ou pire, avec un autre VMID, on se retrouve avec deux VMs.
- `tofu apply -refresh-only` en croyant avoir « accepté » la modification manuelle.
- Importer une VM sans vérifier que le plan qui suit est vide.

**En production chez MédiSphère** : le rapport de dérive nocturne liste, par environnement, les écarts d'attributs **et** les VMs sans propriétaire ; chaque ligne devient un ticket.

---

### M05-E41 — Panne : le plan est cassé du jour au lendemain

**Démarche de diagnostic**

*Symptôme* : sans commit, le plan échoue sur `adm01`. *Hypothèses* : les quatre événements du ticket, et ce dont dépend un plan hors du dépôt.

**Étape 1 — `adm01` contre la CI.**

| Variante | `socle/` sur `adm01` | `envs/lab-m05/` sur `adm01` | Pipeline |
|---|---|---|---|
| 1 (image) | KO | KO | **KO** |
| 2 (lock) | KO | OK | OK |
| 3 (cache providers) | KO | OK | OK |
| 4 (phrase) | KO | KO | OK |

**Étape 2 — Une commande par événement.**

| Événement | Commande qui tranche |
|---|---|
| Publication d'image | `ssh pve01 "pvesh get /cluster/resources --type vm --output-format json" \| jq -r '.[] \| select(.template == 1) \| "\(.vmid) \(.name) \(.tags)"'` |
| Lucas : place disque et providers | `git -C ~/src/infra status --ignored`, `git diff`, `ls -l socle/.terraform/providers/registry.opentofu.org/bpg/proxmox/*/linux_amd64/`, `df -h` |
| Rotation des secrets | `ls -l --time-style=full-iso ~/.config/workbook/`, `tofu state list` (lit **et déchiffre**) |
| Mises à jour de la nuit | `tofu version` sur `adm01` et `runner01` (la série 1.13 est épinglée en E02 : rien n'a changé), `grep -h ' install \| upgrade ' /var/log/dpkg.log` |

**Variante 1 — plus d'image `current`.**

```
│ Error: Resource postcondition failed
│
│   on data.tf line 22, in data "proxmox_virtual_environment_vms" "image_courante":
│   22:       condition     = length(self.vms) == 1
│
│ Il faut exactement UNE image dorée Debian 13 étiquetée current (trouvé : 0). Vérifie la publication des
│ images (M03-E10) avant tout plan.
```

C'est ta postcondition de M05-E08 qui parle : elle transforme une liste vide en un message clair. La liste des templates montre l'ancienne image `current` sans son étiquette, et aucune nouvelle. Correctif : à la **source**, l'outil de publication de M03 (`outils/publier-image.sh` de `plateforme/images`, ou le job de publication), qui repose `current` sur la dernière image **validée** après ses tests. En urgence, `qm set <VMID> --tags …` avec les étiquettes d'origine est acceptable s'il est tracé et suivi de la publication propre. Ensuite, regarde **pourquoi** la publication s'est arrêtée entre « retirer » et « poser » : l'outil devrait poser la nouvelle étiquette **avant** de retirer l'ancienne (ou les deux dans une seule opération), pour ne jamais passer par zéro.

**Variante 2 — lock réécrit.**

```
│ Error: Required plugins are not installed
│
│ The installed provider plugins are not consistent with the packages selected in the dependency lock file:
│   - registry.opentofu.org/bpg/proxmox: the cached package for registry.opentofu.org/bpg/proxmox 0.116.0
│     (in .terraform/providers) does not match any of the checksums recorded in the dependency lock file
admin@adm01:~/src/infra$ git diff --stat
 socle/.terraform.lock.hcl | 30 +-----
```

Le lock ne contient plus que deux empreintes `h1:` inconnues, et aucune `zh:`. Correctif : `git restore socle/.terraform.lock.hcl` puis `tofu init` (sans `-upgrade`). `tofu init -upgrade` choisirait la version la plus récente autorisée par la contrainte (`~> 0.116.0` depuis M05-E31 : un correctif 0.116.x plus récent, s'il existe) et réécrirait le lock : on masquerait la panne en changeant **aussi** de version de provider, sans MR. Une montée de version est un changement délibéré, traité comme en M05-E31 (journal relu, plan comparé, MR), jamais un effet de bord d'une réparation. Les numéros de version ci-dessous supposent M05-E31 fait (0.116.0) ; avant, lis 0.115.x. Un lock commun à `adm01` (linux_amd64) et à d'autres postes s'obtient par `tofu providers lock -platform=linux_amd64 -platform=darwin_arm64 …`, dans une MR.

**Variante 3 — paquet en cache tronqué.** Même message, mais `git status` est propre. Le binaire du provider fait 1 Mio :

```
admin@adm01:~/src/infra/socle$ ls -l .terraform/providers/registry.opentofu.org/bpg/proxmox/0.116.0/linux_amd64/
-rwxr-xr-x 1 admin admin 1048576 … terraform-provider-proxmox_v0.116.0
```

Correctif : `rm -rf .terraform/providers` puis `tofu init` ; OpenTofu retélécharge le paquet et le vérifie contre le lock **intact**. Vérifie aussi `df -h` : un disque plein pendant un `init` produit exactement cela.

**Variante 4 — rotation de phrase à moitié faite.**

```
│ Error: … decryption failed for all provided methods: attempted decryption failed for state: …
│ cipher: message authentication failed
```

`tofu-chiffrement.pass` date d'hier soir ; la CI, qui a encore l'ancienne phrase (`TOFU_PHRASE_CHIFFREMENT`), déchiffre. `outils/charger-acces.sh` a construit `TF_ENCRYPTION` avec la **nouvelle** phrase sous le nom de fournisseur `etat` : or chaque état chiffré garde le sel PBKDF2 sous le nom de son fournisseur, et il a été chiffré avec l'ancienne phrase. La nouvelle phrase est légitime (rotation de Sophie) : il faut **terminer** la rotation, pas revenir en arrière en silence. C'est la procédure « Rotation de la phrase » du registre des secrets (M05-E27) :

1. Récupère l'ancienne phrase (coffre de l'équipe, d'après le registre ; la variable CI est cachée, donc non relisible) dans un second fichier 600, par exemple `~/.config/workbook/tofu-chiffrement-ancienne.pass`, et inscris-le au registre.
2. MR : dans `socle/chiffrement.tf` (copié tel quel dans `envs/*` et généré pour Terragrunt par `root.hcl`), un **nouveau** couple sous un autre nom devient principal, l'ancien couple `etat` passe en `fallback`. Toujours aucune phrase dans le code :

```hcl
# Rotation de la phrase (SEC-6xx, AAAA-MM-JJ). Ne JAMAIS donner une nouvelle phrase à un
# fournisseur déjà utilisé : ses métadonnées sont enregistrées sous son nom dans l'état chiffré.
terraform {
  encryption {
    method "aes_gcm" "etat" {          # ancienne phrase : lecture seulement
      keys = key_provider.pbkdf2.etat
    }
    method "aes_gcm" "etat_2027" {     # nouvelle phrase
      keys = key_provider.pbkdf2.etat_2027
    }
    state {
      method   = method.aes_gcm.etat_2027
      enforced = true
      fallback {
        method = method.aes_gcm.etat
      }
    }
    plan {
      method   = method.aes_gcm.etat_2027
      enforced = true
      fallback {
        method = method.aes_gcm.etat
      }
    }
    remote_state_data_sources {
      default {
        method = method.aes_gcm.etat_2027
        fallback {
          method = method.aes_gcm.etat
        }
      }
    }
  }
}
```

3. `outils/charger-acces.sh` (et `ci-preparer.sh`, avec une seconde variable CI protégée et cachée pour l'ancienne phrase) déclare désormais **deux** fournisseurs dans `TF_ENCRYPTION` :

```
key_provider "pbkdf2" "etat"      { passphrase = "<ANCIENNE>" }
key_provider "pbkdf2" "etat_2027" { passphrase = "<NOUVELLE>" }
```

   Les vérifications et les scripts de panne du module utilisent ton `outils/charger-acces.sh` quand il existe : c'est lui qui doit suivre la rotation.
4. Apply de chaque état par le pipeline (`socle`, `envs/lab-m05`, `envs/recette-m05`, unités Terragrunt encore présentes) : le plan est vide, mais l'apply réécrit l'état avec la nouvelle méthode. Vérifie qu'une **nouvelle version** de chaque objet est apparue dans le compartiment (⚠️ à vérifier sur ta version : si un apply sans changement ne réécrit pas l'état, un changement anodin, une description par exemple, le fera), puis que `tofu state list` réussit avec la **seule** nouvelle phrase.
5. Seconde MR : retrait du `fallback` et du couple `etat` ; `charger-acces.sh` et `ci-preparer.sh` ne déclarent plus que `etat_2027` ; l'ancienne phrase quitte `~/.config/workbook/` et les variables CI, et reste au coffre pour les copies externes antérieures (E29), comme le prévoit le registre.

**Vérification** : plans vides des deux côtés, pipeline vert, `git status` propre, `lab/bin/check 05 41`.

**Prévention** : job planifié `tofu init -lockfile=readonly` + `validate` dans un répertoire propre (« Pour aller plus loin ») ; publication d'image qui ne passe jamais par « zéro `current` » ; procédure de rotation écrite (registre des secrets) et exécutée d'un bloc, par la chaîne ; espace disque de `adm01` supervisé.

**Explications** : à chaque exécution, OpenTofu calcule l'empreinte `h1:` du paquet installé dans `.terraform/providers` et la compare au lock ; les `zh:` sont les sommes des archives publiées par le registre pour **toutes** les plateformes, vérifiées au téléchargement. Un lock qui n'a que des `h1:` d'une autre plateforme ne peut valider aucun paquet installé ici.

**Pièges classiques**
- `rm .terraform.lock.hcl && tofu init` : un nouveau lock, peut-être une nouvelle version, et plus aucune preuve de ce qui était installé.
- Remettre l'ancienne phrase dans le fichier sans le dire à Sophie : la rotation est « faite » dans son tableau, pas dans les états.
- Retirer la postcondition de l'image « parce qu'elle bloque » : elle vient de faire exactement son travail.

**En production chez MédiSphère** : aucune dépendance d'un plan n'est implicite : versions épinglées, lock versionné, images désignées par des étiquettes gérées par un outil, secrets à rotation outillée.

---

### M05-E42 — Panne : l'état a disparu

**Démarche de diagnostic**

*Symptôme* : le plan du socle propose de tout créer ou importer. Gel annoncé.

**Étape 1 — Où OpenTofu regarde-t-il ?**

```
admin@adm01:~/src/infra/socle$ tofu workspace show
admin@adm01:~/src/infra/socle$ jq -r .backend.config.key .terraform/terraform.tfstate
admin@adm01:~/src/infra/socle$ git status --short; git diff
```

- *Variante 4* : `tofu workspace show` répond `lucas-essai`. Avec un espace de travail autre que `default`, le backend S3 range l'état sous `env:/<espace>/<clé>` (préfixe `workspace_key_prefix`, `env:` par défaut) : ici `env:/lucas-essai/socle/terraform.tfstate`, vide. Correctif : `tofu workspace select default`, puis `tofu workspace delete lucas-essai` (refusé s'il n'est pas vide : bonne nouvelle).
- *Variante 3* : `git diff` montre `key = "socle/tofu.tfstate"` et la configuration initialisée pointe sur cette clé. Rien n'a disparu. Correctif : `git restore socle/versions.tf` puis `tofu init -reconfigure` (pas `-migrate-state`, qui proposerait de **copier** l'état vide de la mauvaise clé vers la bonne). Vérifie qu'aucun objet `socle/tofu.tfstate` n'a été créé (`aws s3api list-objects-v2 --prefix socle/`) ; un plan ne l'aurait pas créé, un apply oui.

Si la configuration est saine, l'objet lui-même est en cause (variantes 1 et 2).

**Étape 2 — Lister les versions (et les enregistrer).**

```
admin@adm01:~$ mkdir -p ~/m05/e42 && cd ~/m05/e42 && umask 077
admin@adm01:~/m05/e42$ aws --profile s3-socle s3api list-object-versions --bucket tofu-state --prefix socle/terraform.tfstate > versions-avant.json
admin@adm01:~/m05/e42$ jq -r '(.Versions // [] | map(select(.Key == "socle/terraform.tfstate")) | .[] | "\(.LastModified) version  \(.IsLatest) \(.Size) \(.ETag) \(.VersionId)"),
                               (.DeleteMarkers // [] | map(select(.Key == "socle/terraform.tfstate")) | .[] | "\(.LastModified) MARQUEUR \(.IsLatest) - - \(.VersionId)")' versions-avant.json | sort -r
2026-10-15T02:13:07Z MARQUEUR true - - v_4fa0…                           ← variante 1
2026-10-14T17:20:41Z version  false 41873 "9b1f…" v_1b7c…
2026-10-14T09:02:13Z version  false 41851 "77e0…" v_9e02…
```

*Variante 1* : un marqueur de suppression est la version courante. *Variante 2* : la version courante est une vraie version, mais sa taille et son ETag sont **ceux de l'état de `envs/lab-m05`** :

```
admin@adm01:~$ aws --profile s3-socle s3api head-object --bucket tofu-state --key envs/lab-m05/terraform.tfstate --query ETag
admin@adm01:~/src/infra/socle$ tofu state list
module.app["app01"].proxmox_virtual_environment_vm.vm
…
proxmox_virtual_environment_vm.jetable
```

Le plan du socle voulait donc **détruire** les VMs d'environnement (dans l'état, absentes du code du socle) et importer ou créer les VMs du socle. Un apply aurait détruit les VMs de `envs/lab-m05` (2051-2054 avec le corrigé du palier 2).

**Étape 3 — Prouver la version saine.** La dernière version avant l'incident correspond au dernier apply connu (job du pipeline, même heure) ; sa taille est cohérente avec les précédentes. Pour en lire le contenu **sans** la restaurer, copie-la sous une clé d'examen et lis-la par une configuration jetable (même chiffrement, backend sur `_examen/socle.tfstate`), ou contente-toi de la cohérence date/taille/ETag avec l'historique du pipeline.

**Étape 4 — Restaurer en gardant l'historique.**

*Variante 1* : supprimer le **marqueur** rend sa place à la version précédente, à l'identique (même `VersionId`, même ETag) :

```
admin@adm01:~$ aws --profile s3-socle s3api delete-object --bucket tofu-state --key socle/terraform.tfstate --version-id v_4fa0…
```

⚠️ Vérifie trois fois que ce `VersionId` est celui du **marqueur** : le même geste sur une version de données la détruit définitivement.

*Variante 2* : recopier la version saine comme version courante (une nouvelle version s'ajoute, rien n'est effacé) :

```
admin@adm01:~$ aws --profile s3-socle s3api copy-object --bucket tofu-state --key socle/terraform.tfstate \
    --copy-source 'tofu-state/socle/terraform.tfstate?versionId=v_1b7c…'
```

Le script de M05-E29, [`outils/restaurer-etat.sh`](fichiers/M05-E29/infra/outils/restaurer-etat.sh), enchaîne ces précautions (`--lister` ; `--version` : refus si un verrou existe ou si le `lineage` diffère, copie de l'objet courant, confirmation, `copy-object`). Il convient à la variante 1 ; en variante 2 il **refuse**, parce que l'objet courant est un autre état (autre `lineage`) : c'est voulu, la copie se fait alors à la main comme ci-dessus, une fois la version saine prouvée. Il sert de base au runbook RB-051 (mini-projet).

**Étape 5 — Prouver la restauration, lever le gel.** `tofu state list` (cinq VMs du socle), `tofu plan` vide, `serial` identique à celui du dernier apply connu (`tofu state pull | jq .serial` **dans** `~/m05/e42`, puis `shred -u` du fichier si tu l'as écrit). Ensuite seulement : levée du gel.

**Vérification** : `lab/bin/check 05 42`.

**Prévention**
- Droits : `tofu-etat` n'a pas besoin de supprimer les objets `*.tfstate` (seulement les `*.tflock`) : à restreindre si la passerelle le permet (actions par chemin, `Write:tofu-state/…`), sinon identité de verrou séparée ; journal d'accès S3 pour savoir **qui**.
- Contrôle quotidien : l'objet courant de chaque état est une version de données, de taille plausible.
- Socle : refuser tout espace de travail autre que `default` (précondition sur `terraform.workspace == "default"`), et afficher l'espace de travail dans l'invite du shell.
- Sauvegarde **hors** de `s3-01` (M05-E29) : le versionnage ne protège ni d'une suppression de version, ni de la perte de `s3-01`.

**Explications** : sans versionnage, la variante 1 était une perte sèche (il fallait reconstruire l'état par des imports, VM par VM) et la variante 2 un écrasement définitif. Le `lineage` de l'état ne protège pas d'une copie au niveau S3 : OpenTofu le contrôle quand **il** écrit (`state push`), pas quand il lit.

**Alternatives** : restaurer depuis la sauvegarde hors site de M05-E29 si l'historique S3 était lui-même compromis ; reconstruire l'état par des blocs `import` en dernier recours (long, et toute ressource non importable est perdue pour OpenTofu).

**Pièges classiques**
- Appliquer le plan « pour réimporter » : variante 2, il détruit les VMs d'environnement.
- `tofu state push` d'une copie locale ancienne, `-force` en prime : tu écrases peut-être un état plus récent que ta copie.
- `delete-object --version-id` sur la mauvaise version.

**En production chez MédiSphère** : RB-051 (restauration de l'état) est testé chaque trimestre par une autre personne que son auteur ; une perte d'état du socle est un incident P1.

---

### M05-E43 — Astreinte : l'IaC en panne

**Démarche de diagnostic**

La difficulté est méthodologique : deux pannes, des symptômes qui se recouvrent, une panne qui en masque une autre.

**1. Triage (10 minutes).** Les instruments d'abord :

```
admin@adm01:~$ getent hosts s3-01.par1.medisphere.internal
admin@adm01:~$ aws --profile s3-socle s3api list-objects-v2 --bucket tofu-state --max-items 5
admin@adm01:~$ for d in socle envs/lab-m05; do (cd ~/src/infra/$d && echo "== $d" && tofu state list | wc -l); done
admin@adm01:~$ git -C ~/src/infra status --short --ignored
admin@adm01:~/DevOpsPrivateCloud$ for x in 35 36 37 38 39 40 41 42; do lab/bin/check 05 $x | tail -n 2; done
```

Tableau d'impact (exemple, paire E37 v3 + E42 v1) :

| Symptôme | Impact | Couche | Dépend de |
|---|---|---|---|
| plan impossible depuis `adm01` (délai sur 8333) | plus aucun changement d'infra depuis le bastion | réseau / backend | `gw01`, `s3-01` |
| (masqué) état du socle vide | un apply du socle importerait ou recréerait tout | état | accès au backend |

**2. Ordre de traitement.** Accès au backend (E37) → lecture de l'état (E42, E41 v4) → verrous (E36) → cohérence de l'état (E35, E40) → ce qui demande un apply (E38, E39). Raison : chaque étage fausse les mesures de l'étage suivant, et un apply sur un état faux aggrave tout.

**3. Le piège central : la panne masquée.**

| Paire | Ce qu'on voit d'abord | Ce qui reste caché |
|---|---|---|
| E37 + E42 | backend injoignable | une fois joint, l'état du socle est vide (ou faux) |
| E37 + E36 | backend injoignable | une fois joint, un verrou bloque encore |
| E41 (v4) + E40 | état indéchiffrable | une fois déchiffré, une VM manque dans l'état |
| E36 + E35 | verrou | une fois libéré, le plan veut détruire une VM du socle |
| E38 + E39 | apply refusé | une fois les droits rétablis, la VM créée est injoignable |
| E42 (v3/v4) + E36 | « l'état a disparu » | le verrou est sur la **vraie** clé, invisible tant qu'on regarde ailleurs |

Après chaque correction, rejoue **tout** le triage.

**4. Gel et communication.** Exemples :

> **[INC-3250] 08:00 — En cours.** Plus de plan ni d'apply depuis `adm01` (backend d'état injoignable depuis le bastion). La CI semble épargnée. Gel des apply sur `socle` jusqu'à nouvel ordre. Démonstration de 14 h non menacée à ce stade. Prochain point : 08:30.

> **[INC-3250] 08:30 — Partiellement rétabli.** Accès au backend rétabli à 08:16 (règle de filtrage temporaire oubliée sur `gw01`). Second problème découvert : l'état du socle n'est plus l'objet courant du stockage. Gel maintenu. Restauration en cours, sans perte attendue (stockage versionné). Prochain point : 09:00.

> **[INC-3250] 09:45 — Résolu.** État du socle restauré à l'identique à 09:12, plans vides, contrôles verts. Gel levé. Post-mortem diffusé demain.

**5. Post-mortem.** Exemple complet : [`fichiers/M05-E43/post-mortem-exemple.md`](fichiers/M05-E43/post-mortem-exemple.md). Grille :

| Critère | Attendu |
|---|---|
| Sans recherche de coupable | faits et mécanismes ; « Lucas » n'apparaît pas comme fautif, mais le **processus** qui a permis la modification à chaud |
| Chronologie | horodatée, sources citées, gel et levée compris |
| Causes | deux causes prouvées par commande et sortie ; facteurs contributifs (droits trop larges, modifications à chaud, absence de journal d'accès S3) |
| Détection | délai, sonde qui aurait détecté avant l'utilisateur |
| Actions | typées, avec responsable et échéance ; au moins une sur la **protection de l'état** |
| Masquage | comment la seconde panne était masquée et a été découverte |

**Vérification** : `lab/bin/check 05 43` (rejoue les contrôles de E35 à E42, vérifie le post-mortem). **Annulation** si nécessaire : `lab/bin/break 05 43 --annuler`.

**Explications** : en IaC, la panne masquée est souvent une panne **d'état** derrière une panne **d'accès**. La règle « relire l'état avant de reprendre les apply » est le garde-fou.

**Pièges classiques** : lever le gel dès que le premier symptôme disparaît ; appliquer pour « vérifier que tout va bien » ; corriger deux choses à la fois.

**En production chez MédiSphère** : un gel des apply est un état explicite (variable CI `GEL_APPLY=1` qui fait échouer les jobs d'apply, par exemple) plutôt qu'un message qu'on peut manquer.

---

### M05-E44 — Sous le capot : graphe, providers et état

**Solution**

*Bac à sable* (`~/m05/e44/labo/`, backend local par défaut) :

```hcl
# ~/m05/e44/labo/main.tf
terraform {
  required_version = "~> 1.13.0"
}

resource "terraform_data" "base" {
  input = "base"
  provisioner "local-exec" {
    command = "sleep 3; date +%T.%N >> ordre.txt; echo base >> ordre.txt"
  }
}

resource "terraform_data" "fille_ref" {
  input = terraform_data.base.output # dépendance implicite (référence)
  provisioner "local-exec" {
    command = "sleep 3; date +%T.%N >> ordre.txt; echo fille_ref >> ordre.txt"
  }
}

resource "terraform_data" "fille_depends" {
  depends_on = [terraform_data.base] # dépendance explicite
  provisioner "local-exec" {
    command = "sleep 3; date +%T.%N >> ordre.txt; echo fille_depends >> ordre.txt"
  }
}

resource "terraform_data" "libre" {
  count = 2
  triggers_replace = [var.version_libre]
  provisioner "local-exec" {
    command = "sleep 3; date +%T.%N >> ordre.txt; echo libre >> ordre.txt"
  }
}

variable "version_libre" {
  type    = string
  default = "1"
}
```

```
admin@adm01:~/m05/e44/labo$ tofu init && tofu apply -auto-approve -parallelism=1    # ~15 s : une ressource à la fois
admin@adm01:~/m05/e44/labo$ tofu destroy -auto-approve && rm -f ordre.txt
admin@adm01:~/m05/e44/labo$ tofu apply -auto-approve -parallelism=10   # ~6 s : base et libre[*] ensemble, puis les filles
```

*Graphe du socle* :

```
admin@adm01:~/src/infra/socle$ sudo apt install graphviz
admin@adm01:~/src/infra/socle$ tofu graph -type=plan | dot -Tsvg > ~/medisphere/docs/socle/analyses/graphe-socle.svg
admin@adm01:~/src/infra/socle$ tofu graph -type=plan-destroy | dot -Tsvg > ~/m05/e44/graphe-destroy.svg
```

*Trace du protocole* (copie de `envs/lab-m05` réduite au provider et aux sources de données, dans `~/m05/e44/lecture/`) :

```
admin@adm01:~/m05/e44/lecture$ umask 077; set -a; . ~/.config/workbook/pve-tofu.env; set +a
admin@adm01:~/m05/e44/lecture$ TF_LOG=trace TF_LOG_PATH=$HOME/m05/e44/trace.log tofu plan
admin@adm01:~/m05/e44/lecture$ grep -E 'plugin started|using plugin|protocol version|GRPCProvider' ~/m05/e44/trace.log | cut -c1-160 | head -n 20
admin@adm01:~/m05/e44/lecture$ grep -oE 'GRPCProvider(\.v[0-9]+)?: [A-Za-z]+' ~/m05/e44/trace.log | sort | uniq -c
```

Tu y vois, dans l'ordre : le lancement du binaire `terraform-provider-proxmox_v0.116.0` (la version de ton lock) depuis `.terraform/providers/…` (le provider est un **processus séparé**, lancé et arrêté par OpenTofu, éventuellement plusieurs fois au cours d'une commande), la poignée de main du protocole de plugin (version **6** : bpg sert l'ancienne implémentation SDKv2, remontée en v6, et le Plugin Framework derrière un multiplexeur unique), puis les appels `GetProviderSchema`, `ValidateProviderConfig`, `ValidateDataResourceConfig`, `ConfigureProvider`, `ReadDataSource`, et enfin l'arrêt du plugin. Avant d'extraire un passage dans le compte rendu : `grep -n -iE 'authorization|PVEAPIToken|api_token|secret'` sur l'extrait, et remplace ce qui sort.

*État* (bac à sable) :

```
admin@adm01:~/m05/e44/labo$ jq '{version, terraform_version, serial, lineage, nb: (.resources | length)}' terraform.tfstate
admin@adm01:~/m05/e44/labo$ cp terraform.tfstate ancien.tfstate
admin@adm01:~/m05/e44/labo$ tofu apply -auto-approve -var version_libre=2      # serial +1, lineage inchangé
admin@adm01:~/m05/e44/labo$ tofu state push ancien.tfstate
Failed to write state: cannot overwrite existing state with serial 6 with a different state that has the same or lower serial …
admin@adm01:~/m05/e44/labo$ tofu state push ../autre-labo/terraform.tfstate
Failed to write state: cannot import state with lineage "…" over unrelated state with lineage "…"
```

(Libellés représentatifs.) Avec `-force`, les deux contrôles sautent : l'état de destination est écrasé, et tout ce qu'il savait de plus que la copie est perdu (ressources créées depuis, attributs mis à jour) : OpenTofu proposera de recréer ce qui existe déjà.

*Lock* (copie) :

```
admin@adm01:~/m05/e44/labo$ mkdir lock && cp ~/src/infra/socle/{versions.tf,.terraform.lock.hcl} lock/ && cd lock
admin@adm01:~/m05/e44/labo/lock$ sed -i '/backend "s3"/,/^  }/d' versions.tf       # copie locale, sans backend
admin@adm01:~/m05/e44/labo/lock$ tofu providers lock -platform=linux_amd64 -platform=darwin_arm64
admin@adm01:~/m05/e44/labo/lock$ diff ~/src/infra/socle/.terraform.lock.hcl .terraform.lock.hcl
```

Une empreinte `h1:` par plateforme apparaît ; les `zh:` (une par archive publiée, toutes plateformes) ne changent pas.

**Réponses aux questions**

1. Une source de données n'a pas d'état à « rafraîchir » : elle **est** une lecture, faite pendant le plan dès que ses arguments sont connus. `-refresh=false` ne saute que le rafraîchissement des ressources gérées. Exception : si un argument dépend d'une valeur inconnue au plan (attribut d'une ressource à créer), la lecture est reportée à l'apply.
2. `provider[…] (close)` est le nœud qui arrête le processus du provider une fois toutes les ressources qui en dépendent traitées ; `root` est le puits du graphe, atteint quand tout est fini. Ils structurent le parcours, ils ne correspondent à aucun objet réel.
3. Le graphe est construit à partir de la configuration (références, `depends_on`) avant tout appel au provider ; un cycle rend le parcours impossible, il est donc détecté à la construction, avant même `ConfigureProvider`.
4. Version 6 du protocole de plugin. bpg remonte son implémentation SDKv2 en v6 (`tf5to6server`) et la multiplexe avec le Plugin Framework (`tf6muxserver`) : OpenTofu ne voit qu'un provider. Pour toi : selon la ressource, le comportement (valeurs par défaut, détection des changements, messages) suit l'une ou l'autre implémentation, d'où des différences de style entre `proxmox_virtual_environment_vm` (SDKv2) et les ressources plus récentes.
5. `ReadResource`, une fois par instance de ressource gérée présente dans l'état (ici 4 VMs d'environnement, plus la nouvelle s'il y en a une, mais elle n'existe pas encore) ; les sources de données passent par `ReadDataSource`.
6. Le schéma décrit les types, les attributs obligatoires, optionnels, calculés, sensibles ; il ne contient pas la notion de remplacement. C'est le provider qui, dans sa réponse à `PlanResourceChange`, renvoie la liste des chemins qui exigent un remplacement ; OpenTofu l'affiche (`# forces replacement`) et l'expose dans le plan JSON (`change.replace_paths` ; ⚠️ à vérifier sur ta version).
7. `lineage` identifie une **lignée** d'états (fixé à la création, jamais modifié) ; `serial` augmente à chaque écriture. `state push` refuse une autre lignée ou un `serial` inférieur ou égal (sauf `-force`). Ils ne protègent pas d'une copie faite **sous** OpenTofu (copie S3 de M05-E42 v2) : OpenTofu ne vérifie pas le `lineage` à la lecture.
8. Des données opaques propres au provider (pour bpg, par exemple des délais ou des métadonnées de schéma), en base64. OpenTofu les renvoie telles quelles au provider à chaque appel ; une modification peut corrompre silencieusement le comportement du provider sur cette ressource.
9. Si le provider a augmenté la version de schéma d'une ressource, il doit fournir une **mise à niveau d'état** (`UpgradeResourceState`) : OpenTofu la lui demande à la lecture. Revenir ensuite à un provider plus ancien est refusé (« … was created by a newer provider version ») : on ne redescend pas.
10. `h1:` : empreinte du contenu du paquet **décompressé**, recalculée sur le dossier installé à chaque exécution. `zh:` : somme SHA-256 de l'archive `.zip` publiée par le registre, une par plateforme, vérifiée au téléchargement. Un lock produit sur un seul poste peut n'avoir que le `h1:` de sa plateforme (et pas les `zh:`, selon la commande qui l'a produit) : sur une autre plateforme, aucun paquet ne peut être validé.
11. L'objet S3 est une enveloppe (`meta`, `encrypted_data`, `encryption_version`) : `serial`, `lineage` et ressources sont **dans** les données chiffrées. Restent visibles : l'existence, la taille et la date des objets et de leurs versions, les clés (donc le nom des configurations), les métadonnées du fournisseur de clé (sel et itérations PBKDF2), et le contenu des **verrous** (en clair : qui travaille, depuis où, quand).
12. 10 par défaut. L'API de Proxmox sérialise beaucoup d'opérations par VM et par nœud (verrous de configuration, tâches de clonage qui saturent le stockage) : un parallélisme élevé produit des délais, des verrous Proxmox (`can't lock file`) et des erreurs transitoires. Le pipeline peut le réduire (3 à 5) pour les gros apply.

**Explications** : comprendre la séparation OpenTofu / provider explique la moitié des pannes de ce palier : OpenTofu gère l'état, le graphe et le plan ; le provider sait ce que veut dire « une VM », ce qui force un remplacement et comment parler à l'API.

**Pièges classiques** : coller une trace brute dans la documentation (jetons, en-têtes) ; faire les expériences de `state push` sur l'état distant ; laisser `TF_LOG=trace` exporté dans le shell.

**En production chez MédiSphère** : `TF_LOG` n'est jamais activé dans le pipeline sauf job de diagnostic manuel, dont les artefacts expirent en 24 h.

---

### M05-E45 — Questions expert : OpenTofu

1. *Rafraîchissement* : lit la réalité pour chaque ressource de l'état (`ReadResource`) et les sources de données, met à jour une copie **en mémoire** de l'état. *Planification* : compare configuration et état rafraîchi, demande au provider le plan de chaque changement (`PlanResourceChange`), produit le plan (en mémoire ou dans `-out`). *Application* : exécute les actions dans l'ordre du graphe (`ApplyResourceChange`), écrit l'état au fil de l'eau. Sans plan sauvegardé, `apply` refait un plan **au moment de l'apply** : si la réalité, l'état ou une source de données (image `current`) ont changé depuis la MR, ce qui est appliqué n'est pas ce qui a été relu. D'où `plan -out` en MR et `apply plan.bin` (M05-E26).
2. **b.** Un plan sauvegardé enregistre l'état sur lequel il a été calculé ; si l'état a changé depuis (autre `serial`), OpenTofu refuse un plan « périmé » (*stale*). a) est faux : aucune fusion d'état n'existe. c) faux : rien n'est replanifié automatiquement. d) faux : le verrou ne dure que le temps d'une commande ; il a été libéré entre les deux jobs.
3. `plan -refresh-only` : montre ce qui a changé dans la réalité par rapport à l'état, sans rien proposer sur la configuration (usage : constater une dérive). `apply -refresh-only` : **écrit** ces changements dans l'état (usage : accepter qu'un attribut purement informatif a changé, ou réaligner l'état après une intervention connue, avant d'adapter le code). `plan -refresh=false` : compare configuration et état **sans** lire la réalité (usage : revue rapide d'une MR qui ne touche que du code, ou diagnostic « est-ce la réalité qui a changé ? » comme en E35).
4. Il interdit qu'un plan **calculé à partir de ce bloc** contienne une destruction de cette ressource (remplacement compris). Il ne protège rien si : le bloc est supprimé ou renommé (l'adresse orpheline n'a plus de `prevent_destroy`, E35 v2), on retire la ressource de l'état (`state rm` : elle n'est plus gérée, pas détruite), la destruction se fait hors d'OpenTofu (`qm destroy`), ou si on retire la ligne dans la même MR. `tofu destroy -target` sur la ressource échoue, lui. La protection Proxmox (`protection = true`) est complémentaire : elle tient même si l'IaC se trompe.
5. **b.** Renommer le bloc **supprime** l'ancienne adresse de la configuration : l'état contient `proxmox_virtual_environment_vm.s3_01`, le code ne décrit plus que `module.s3_01…`. OpenTofu ne devine jamais un renommage (a faux) : il détruit l'ancienne adresse et crée la nouvelle. c) est faux : `prevent_destroy` appartenait au bloc supprimé, l'adresse orpheline n'est plus protégée (c'est exactement E35 v2). d) est faux pour la même raison : dès que le bloc d'origine n'existe plus, rien ne peut échouer sur son `prevent_destroy`. La parade est un bloc `moved` (M05-E17), et la protection Proxmox (`protection = true`) comme dernier filet : l'apply échouerait à la suppression.
6. `moved {}` : dans le code, relu en MR, rejoué par tout le monde (chaque copie d'état le subit au prochain plan), sans risque s'il est juste ; à garder tant que d'anciens états peuvent exister. `tofu state mv` : immédiat, invisible en MR, à refaire sur chaque état, risque de faute de frappe. `removed { lifecycle { destroy = false } }` : sort la ressource de la gestion **sans la détruire**, relu en MR. `tofu state rm` : même effet, sans trace. En équipe : les blocs ; les commandes réservées aux réparations, après copie.
7. Le bloc `import {}` est relu en MR, planifié (on voit ce qui sera importé et si le code correspond), appliqué par la chaîne, et accepte `for_each` ; `tofu import` écrit directement l'état, sans plan, depuis un poste. `-generate-config-out` écrit un brouillon de configuration à partir de la réalité : il contient tous les attributs lus, y compris calculés, valeurs par défaut et parfois secrets, sans variables ni modules : à réécrire, jamais à fusionner tel quel.
8. Objet `<clé>.tflock` à côté de l'état, créé par `PutObject` avec `If-None-Match: *` ; le stockage doit refuser (412) une création conditionnelle sur un objet existant, de façon **atomique**. Garage n'implémente pas les écritures conditionnelles : la requête réussirait toujours, deux processus croiraient tenir le verrou. Sans verrou, deux écritures concurrentes de l'état : la dernière gagne, les ressources créées par la première disparaissent de l'état (orphelines dans Proxmox), et le `serial` peut même régresser.
9. **b.** `force-unlock` relit l'objet de verrou, compare l'ID fourni, puis le supprime. a) faux : il vérifie l'ID (pas le détenteur). c) faux : il n'attend rien. d) faux : il ne touche pas à l'état.
10. Il protège la **confidentialité** et l'**intégrité** de l'état et des plans contre qui lit le stockage, les sauvegardes, les artefacts CI (AES-GCM authentifié). Il ne protège pas contre qui a la phrase (poste, CI), ni la disponibilité, ni les verrous (en clair), ni les métadonnées d'objets. PBKDF2 dérive une clé d'une phrase mémorisable avec sel et itérations (coût d'une attaque par force brute) ; une clé brute de 256 bits serait plus forte mais plus difficile à manipuler. Perte de la phrase = perte de l'état (reconstruction par imports). Rotation : nouvelle méthode + `fallback` sur l'ancienne, écriture de chaque état, retrait du `fallback` (E41 v4) ; ne jamais renommer un fournisseur de clé utilisé.
11. Une branche bouge : le même code donne d'un jour à l'autre une autre infrastructure (reproductibilité nulle), une mise à jour du module (ou une compromission du dépôt amont) s'applique sans revue, une rupture arrive sans prévenir. Politique : modules internes seulement (copie relue d'un module communautaire si besoin), consommés par étiquette `vX.Y.Z` immuable (étiquettes protégées), publication par semantic-release, mise à jour par MR (Renovate au module 13), changelog lu.
12. `~> 0.115.0` n'accepte que les correctifs 0.115.x. En 0.x, la convention SemVer n'offre aucune garantie entre mineures : 0.116 peut casser (des ruptures documentées existent entre versions récentes). `>= 0.115` laisserait `tofu init -upgrade` choisir la 0.120 un matin. La montée de mineure est un acte délibéré (M05-E31).
13. Séparés par **état** : ce qui n'a pas le même rayon d'impact, les mêmes droits ou le même rythme (socle permanent / environnements jetables ; plus tard production / préproduction) — un état = un verrou, une phrase, une ACL de stockage. Par **variable** : les différences de taille entre instances d'un même modèle. Les workspaces partagent code, backend et droits : bons pour des copies identiques et éphémères, mauvais pour isoler la production. Terragrunt factorise les répertoires sans fusionner les états.
14. Rafraîchissement (une lecture API par ressource, sérialisée côté Proxmox), sources de données, démarrage des providers, téléchargements (init). Acceptables : découper l'état (le socle ne devrait pas contenir des dizaines de VMs d'environnement), `-refresh=false` pour une revue de code **en plus** du plan complet de la CI, cache de providers (`plugin_cache_dir`), `-parallelism` ajusté. `-target` : réservé à la réparation d'urgence, jamais en routine (plan partiel, dépendances ignorées).
15. Une valeur éphémère n'est jamais écrite dans l'état ni dans le plan (fournie à l'exécution, par exemple par une source éphémère qui lit un coffre) ; un attribut *write-only* est envoyé au provider sans être stocké. Ils résolvent « tout ce que lit ou envoie le provider finit en clair dans l'état ». Au socle : mot de passe cloud-init éventuel, jetons d'enregistrement, futurs secrets Vault (module 25), si le provider expose des attributs write-only (à vérifier ressource par ressource).
16. **b.** Le rafraîchissement lit 4 Go dans Proxmox, la configuration dit 2 Go : le plan propose un `update in-place` vers 2 Go. a) faux depuis toujours : l'état est rafraîchi. c) c'est `apply -refresh-only`. d) faux : c'est le cas nominal de la dérive.
17. Terraform : BUSL 1.1 (usage interne permis, offre concurrente interdite), gouvernance HashiCorp/IBM. OpenTofu : MPL 2.0, Linux Foundation, gouvernance ouverte. Divergences utilisées ici : verrou S3 natif avant Terraform, chiffrement de l'état, extension `.tofu`, `enabled`, évaluation statique des variables dans le backend et le chiffrement. Risques : un outil (Terragrunt, un scanner) ou un module qui suppose Terraform (registre `registry.terraform.io`, fonctionnalités absentes) ; mitigation : tester chaque outil avec OpenTofu, préférer les outils qui le supportent officiellement, garder un code compatible quand c'est gratuit.
18. OpenTofu : existence de la VM, matériel (CPU, mémoire, disques, carte et VNet), étiquettes, démarrage automatique, premier démarrage (cloud-init minimal : compte, clé, réseau). Ansible : paquets, fichiers de configuration, services, utilisateurs, durcissement. Chevauchement typique : les clés SSH (cloud-init au premier démarrage, rôle `base` ensuite), ou le nom d'hôte, ou l'agent QEMU ; règle : cloud-init amorce, Ansible maintient, et un seul des deux gère chaque fichier dans la durée.
19. Artefacts : plans de chaque apply (chiffrés, conservés), journaux des jobs d'apply (qui, quand, quel commit, quel plan), rapport de dérive quotidien (vide, ou ticket pour chaque écart), versions de l'état (historique S3 + sauvegarde hors site), revue de MR. Fréquence : dérive quotidienne, revue trimestrielle des droits. Conservation alignée sur la politique de traçabilité HDS (à fixer avec Sophie, plusieurs années pour les journaux d'administration).
20. Ordre : créer le compartiment cible (versionné, chiffré, identités, verrou testé avec le script de M05-E12) ; geler les apply (variable de gel) et attendre la fin des jobs ; pour chaque état : copie de l'objet et de ses versions, changement du bloc backend en MR, `tofu init -migrate-state` (OpenTofu lit l'état de l'ancien backend, sous verrou, et l'écrit dans le nouveau), `tofu state list` et plan vide sur le nouveau ; comparaison des `serial` ; bascule de la CI ; levée du gel. Retour arrière : l'ancien backend reste intact (lecture seule) tant que la nouvelle chaîne n'a pas fait un cycle complet ; revenir = remettre l'ancien bloc et `init -reconfigure`. `s3-01` n'est détruite (après retrait de `prevent_destroy` et de la protection, par MR) qu'après une sauvegarde finale de ses données.

**Grille d'auto-évaluation** : une réponse est juste si elle cite le **mécanisme** (pas seulement la commande) et un cas où il ne s'applique pas. Pour les QCM, sans la réfutation des trois autres options, compte la réponse comme à moitié juste. Relis en priorité les questions 4, 7, 10 et 20 : ce sont celles que posent les auditeurs et les revues d'architecture.

---

## Pour aller plus loin (palier 4)

- OpenTofu : [*State locking*](https://opentofu.org/docs/language/state/locking/), [`tofu force-unlock`](https://opentofu.org/docs/cli/commands/force-unlock/), [`tofu state push`](https://opentofu.org/docs/cli/commands/state/push/), [`tofu state pull`](https://opentofu.org/docs/cli/commands/state/pull/), [`tofu graph`](https://opentofu.org/docs/cli/commands/graph/), [`tofu console`](https://opentofu.org/docs/cli/commands/console/), [*Refactoring* (`moved`)](https://opentofu.org/docs/language/modules/develop/refactoring/), [*Import*](https://opentofu.org/docs/language/import/), [*Override files*](https://opentofu.org/docs/language/files/override/), [*State encryption* (rotation, `fallback`)](https://opentofu.org/docs/language/state/encryption/), [backend S3](https://opentofu.org/docs/language/settings/backends/s3/), [*Dependency lock file*](https://opentofu.org/docs/language/files/dependency-lock/).
- bpg/proxmox 0.115 : [documentation de la ressource VM](https://github.com/bpg/terraform-provider-proxmox/blob/v0.115.0/docs/resources/virtual_environment_vm.md) (import `<nœud>/<VMID>`, `migrate`), [authentification et SSH](https://github.com/bpg/terraform-provider-proxmox/blob/v0.115.0/docs/index.md).
- SeaweedFS : [*S3 Object Versioning*](https://github.com/seaweedfs/seaweedfs/wiki/S3-Object-Versioning), [*S3 Credentials*](https://github.com/seaweedfs/seaweedfs/wiki/S3-Credentials).
- AWS CLI v2 : [`list-object-versions`](https://docs.aws.amazon.com/cli/latest/reference/s3api/list-object-versions.html), [`copy-object`](https://docs.aws.amazon.com/cli/latest/reference/s3api/copy-object.html), [`delete-object`](https://docs.aws.amazon.com/cli/latest/reference/s3api/delete-object.html).
- Proxmox VE : [*User Management* — permissions, jetons à privilèges séparés](https://pve.proxmox.com/pve-docs/chapter-pveum.html).
