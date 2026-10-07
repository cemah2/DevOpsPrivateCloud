# Module 05 — Palier 1 : Découverte — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Ce corrigé suit l'ordre de l'énoncé. Les questionnaires (E01, E09) sont argumentés et les QCM expliquent pourquoi les autres options sont fausses. Les fichiers complets sont dans [`fichiers/`](fichiers/), exercice par exercice : `fichiers/M05-EXX/infra/` reproduit l'arborescence du projet `plateforme/infra` **à la fin de l'exercice** (chaque dossier est complet : tu peux le comparer au tien avec `diff -r`).

Ce qui a été testé à la rédaction :
- OpenTofu **1.13.1** (archive officielle, empreinte vérifiée) et le provider **`bpg/proxmox` 0.115.0** téléchargé depuis `registry.opentofu.org` (installation signée) ; le fichier `.terraform.lock.hcl` des corrigés est celui produit par `tofu init`.
- `tofu fmt -check` et `tofu init -backend=false` + `tofu validate` sur chaque dossier `fichiers/M05-EXX/infra/envs/lab-m05/`.
- Des plans complets contre une **API Proxmox simulée** (réponses de `GET /version`, `/nodes/{node}/qemu`, `/nodes/{node}/storage` au format de PVE 9) : plan de création de E04 (la sortie reproduite en E04 est réelle), refus des validations de E06 et E07, source de données, postcondition et bloc `check` de E08, messages d'erreur du provider (point d'accès absent, jeton mal formé, 401, certificat inconnu).
- Le bac à sable `count`/`for_each` de E07, exécuté pour de vrai (`terraform_data`).
- Le dépôt APT d'OpenTofu, ses clés (empreintes, signature d'`InRelease`) et l'épinglage (`apt-cache policy`) dans un environnement APT isolé.
- Les scripts (`pve-tofu-compte.sh`, `installer-opentofu.sh`) et les vérifications passent `shellcheck -x` et `bash -n` ; les vérifications ont été exécutées contre un `pve01` et une forge simulés.

Points **non testés en conditions réelles**, à vérifier sur ta version et à signaler s'ils diffèrent :
- tout ce qui touche un vrai `pve01` : clonage, redimensionnement, cloud-init, attente de l'agent, redémarrage provoqué par le changement de mémoire (E05) ; les privilèges de `WBTofu` sont déduits de l'API viewer et du code du provider, pas d'un essai — en particulier la nécessité de `VM.Config.CDROM` (lecteur cloud-init) et l'absence de contrôle supplémentaire pour l'option `purge` de la destruction ;
- l'héritage silencieux des étiquettes d'un clone (E05) est déduit du code de lecture du provider (`vmReadCustom`, v0.115.0) ;
- la forme exacte des sorties de `qm guest exec` et `qm cloudinit dump` (PVE 9.0).

---

### M05-E01 — Test de positionnement : Infrastructure as Code

**Barème** : 2 points par question. 2 = complet et justifié ; 1 = idée juste mais incomplète ; 0 = faux ou blanc. Total sur 40. En dessous de 20, lis attentivement les « Concepts clés » de l'introduction et fais E04 et E05 sans te presser ; au-dessus de 30, tu peux aller vite sur E04.

**Réponses argumentées — Infrastructure as Code**

**1. Déclaratif et impératif.** Impératif : la suite d'actions (« clone 9012 en 2051, règle la mémoire, démarre ; puis 2052… ») ; relancé, le script recrée ou échoue. Déclaratif : l'état voulu (« trois VMs m05-app01 à 03, 1 Go chacune ») ; l'outil calcule l'écart et les actions. Ansible est déclaratif **tâche par tâche** mais retirer une tâche ne défait rien : le paquet installé reste installé. OpenTofu compare le code à son **état** : une ressource retirée du code mais présente dans l'état est **détruite** au prochain `apply`. C'est sa force (rien d'orphelin) et son danger (une ligne supprimée par erreur détruit une VM).

**2. Mutable et immuable.** Mutable : on modifie la machine en place, au fil du temps (mises à jour, configuration). Immuable : on ne modifie pas, on **remplace** par une nouvelle instance construite à partir d'une image. On préfère remplacer quand la machine n'a pas d'état précieux (serveur applicatif, runner, nœud de calcul), pour une montée de version majeure de l'OS, ou quand la dérive accumulée rend le comportement imprévisible. Les images dorées (M03) rendent le remplacement rapide et sûr ; OpenTofu le rend traçable. Les VMs à données (GitLab, S3) restent mutables, ou séparent données (disque à part) et système.

**3. Bénéfices et risques.** Bénéfices : reproductibilité (un environnement recréé à l'identique en quelques minutes) ; revue (le plan relu en MR avant toute création ou destruction) ; documentation exacte (le dépôt **est** l'inventaire de ce qui doit exister) ; détection de la dérive ; traçabilité pour l'audit HDS (qui a changé quoi, quand, approuvé par qui). Risques nouveaux : **rayon d'impact** (une erreur de code, ou un `for_each` mal écrit, détruit dix VMs d'un coup) ; l'**état** contient tous les attributs, secrets compris, et devient une cible ; le compte d'automatisation, très privilégié, vit dans la CI ; la dépendance à un provider tiers qui change de comportement entre deux versions.

**4. Réponse B.** Un provider est un programme séparé (un binaire Go), téléchargé par `tofu init` depuis un registre, qui expose des types de ressources et de sources de données et traduit les opérations en appels d'API. A est faux : OpenTofu n'a pas de serveur (les plateformes « TACOS » comme Spacelift ou Atlantis sont des produits à part). C décrit un module. D décrit un backend.

**5. Dérive.** C'est l'écart entre la réalité et ce que décrivent le code et l'état, apparu en dehors d'OpenTofu (modification dans l'interface, `qm set`, script, autre outil). Le rafraîchissement du plan relit chaque ressource : tout écart apparaît comme une modification à appliquer. Une correction manuelle est dangereuse parce que le prochain `apply`, lancé par quelqu'un d'autre pour une autre raison, va **l'annuler** sans prévenir ; et si l'attribut modifié est de ceux qui forcent le remplacement, il va **recréer** la ressource. Ansible, lui, ne ramène que ce qu'il gère et ne détruit jamais une machine.

**Réponses argumentées — OpenTofu**

**6. Vocabulaire.** *Ressource* : un objet géré (créé, modifié, détruit) par OpenTofu, ici une VM. *Source de données* : une lecture d'un objet qu'on ne gère pas (l'image courante). *Variable* : une entrée de la configuration, typée, fournie par l'appelant. *Valeur locale* : une expression nommée, calculée une fois dans la configuration. *Sortie* : une valeur exposée par la configuration (à l'utilisateur, à un module parent, à un autre outil). *Module* : un dossier de fichiers `.tf` réutilisable, appelé avec des variables et qui rend des sorties. *Backend* : l'endroit où l'état est stocké (et verrouillé).

**7. Réponse B.** Le plan rafraîchit (lit chaque ressource chez le provider), compare au code et affiche les actions, sans rien modifier. A est faux : sans `-refresh=false`, le plan contacte l'API. C est faux : rien n'est appliqué. D est faux : le plan ne sauvegarde pas l'état rafraîchi ; c'est `tofu apply -refresh-only` qui le fait (E05, « pour aller plus loin »).

**8. Symboles.** `+` création ; `-` destruction ; `~` modification sur place ; `-/+` remplacement, destruction **puis** création (comportement par défaut) ; `+/-` remplacement, création puis destruction (`create_before_destroy`) ; `<=` lecture d'une source de données pendant l'apply. Le relecteur s'arrête sur tout `-` et `-/+` : sur une VM, c'est un disque qui disparaît. Le plan dit **pourquoi** (« forces replacement » à côté de l'attribut, ou la raison affichée sous l'adresse).

**9. Réponse B.** L'état associe chaque adresse du code (`proxmox_virtual_environment_vm.essai`) à l'objet réel et contient tous ses attributs tels que le provider les a lus, y compris des valeurs sensibles (mot de passe cloud-init, clés). A est insuffisant : sans les attributs, pas de calcul d'écart. C et D sont faux : ni le code ni les plans ne sont dans l'état.

**10. État local à plusieurs.** (a) Chacun a **sa** vérité : Julien crée une VM, ton état ne la connaît pas, ton prochain apply ne la voit pas (ou la recrée en conflit). (b) Aucun verrou entre deux postes : deux `apply` simultanés produisent deux états divergents, et le dernier qui écrit gagne. (c) Le fichier vit sur un portable : perdu avec lui, jamais sauvegardé, et il contient des secrets. Backend distant : une seule copie de référence, versionnée, sauvegardée, aux accès contrôlés. Verrou : un seul `apply` (ou plan) à la fois par état (E11, E12).

**11. `count` et `for_each`.** `count` crée des instances numérotées `ressource[0]`, `[1]`, `[2]` ; `for_each` des instances nommées par une clé `ressource["app01"]`. Retirer `app02` du milieu d'une liste avec `count` : l'index 1 reçoit les valeurs d'`app03`, l'index 2 disparaît ; OpenTofu propose donc de **modifier** (ou remplacer) l'instance `[1]` pour qu'elle devienne `app03` et de **détruire** l'instance `[2]`, c'est-à-dire le vrai `app03`. Avec `for_each`, seule l'instance `["app02"]` est détruite (E07 le montre).

**12. Réponse B.** Un attribut *ForceNew* ne peut pas changer sur l'objet existant : le provider demande un remplacement, affiché `-/+` avec « forces replacement ». Par défaut la destruction précède la création. A est faux par définition. C est faux : ce n'est pas une erreur, c'est un remplacement (d'où le danger). D est faux, sauf si on l'a demandé explicitement avec `lifecycle { ignore_changes }` (E08).

**13. Fichier de verrouillage.** `.terraform.lock.hcl` fige, pour chaque provider, la **version exacte** retenue et les **empreintes** des paquets acceptés. Il se versionne : toute l'équipe et la CI installent alors exactement le même binaire, et un paquet modifié est refusé. La contrainte de `required_providers` dit ce qui est **acceptable** (`~> 0.115.0`) ; le fichier dit ce qui a été **choisi** (0.115.0). Pour changer de version dans la plage : `tofu init -upgrade`, puis MR du fichier modifié.

**14. Contraintes de version.** `~> 0.115.0` : de 0.115.0 inclus à 0.116.0 exclu (correctifs seulement). `~> 0.115` : de 0.115 à 1.0 exclu (toutes les mineures 0.x à venir). `>= 0.115.0` : tout, y compris une future 1.0 ou 2.0. En version 0.x, la convention de versionnage sémantique n'apporte aucune garantie : une mineure peut casser la compatibilité, et le `CHANGELOG.md` de `bpg/proxmox` en contient régulièrement (« BREAKING CHANGES » en 0.100, 0.101, 0.102, 0.109…). Sur un provider 5.x qui respecte le versionnage sémantique, `~> 5.4` est raisonnable.

**15. `sensitive = true`.** La valeur est masquée (`(sensitive value)`) dans les sorties du plan, de l'apply et de `tofu output`, et la sensibilité se propage aux expressions qui l'utilisent. Elle n'est **pas** chiffrée ni retirée : elle est en clair dans l'état, dans le fichier de plan enregistré, dans `tofu output -json` ou `-raw`, et un provider peut la journaliser en mode débogage. Protéger la valeur, c'est protéger l'état (E27) ou ne jamais l'y mettre (valeurs éphémères, E09).

**16. Réponse B.** Le rafraîchissement constate que la VM n'existe plus et la retire de l'état en mémoire ; le plan propose alors de la **recréer**. A est faux (pas d'erreur), C est faux (le plan lit la réalité), D est absurde : OpenTofu ne modifie jamais le code. Si le plan était appliqué, la VM serait recréée **vide** : une suppression manuelle ne se « répare » pas par un apply quand la VM avait des données.

**17. Dépendances.** Dès qu'une expression cite une autre ressource ou source de données (`data.x.vms[0].vm_id`), OpenTofu en déduit l'ordre. `depends_on` sert quand la dépendance existe mais n'apparaît dans aucune expression : un snippet cloud-init référencé par son nom écrit en dur, une règle de pare-feu qui doit exister avant le démarrage d'une VM. À utiliser avec méfiance : sur une source de données ou un module, `depends_on` repousse souvent la lecture à l'apply (« known after apply ») et rend le plan moins précis ; il masque aussi un couplage qu'une vraie référence rendrait explicite.

**18. Reprendre l'existant.** On écrit d'abord la configuration qui décrit la VM telle qu'elle est, puis on l'**importe** : bloc `import { to = proxmox_virtual_environment_vm.git01, id = "<NOEUD>/1004" }` (relu en MR, puis appliqué), ou la commande `tofu import`. Objectif : un plan **vide** après l'import. Ce qui peut mal tourner : un attribut décrit différemment fait proposer une modification, ou pire un **remplacement** si l'attribut force la recréation (par exemple un bloc `clone` ajouté à une VM qui n'a jamais été un clone) ; d'où `lifecycle { prevent_destroy = true }` sur les VMs du socle. C'est l'objet de E16.

**Réponses argumentées — écosystème et langage**

**19. Histoire.** Terraform était sous licence libre MPL 2.0 jusqu'à la série 1.5. Le 10 août 2023, HashiCorp annonce le passage de ses produits à la *Business Source License* 1.1 (BUSL), qui interdit les usages concurrents de ses offres commerciales. Un collectif publie le manifeste OpenTF, puis forke Terraform 1.5 ; le projet rejoint la **Linux Foundation** en septembre 2023 sous le nom **OpenTofu** et publie sa première version stable (1.6.0) en janvier 2024, sous MPL 2.0. HashiCorp a depuis été rachetée par IBM (2025). Conséquences pour MédiSphère : les providers sont les mêmes binaires, mais servis par `registry.opentofu.org` (les adresses complètes diffèrent : `registry.opentofu.org/bpg/proxmox` contre `registry.terraform.io/bpg/proxmox`, d'où des fichiers de verrouillage différents) ; le code reste compatible pour l'essentiel, mais chaque outil a ses fonctions propres (chiffrement de l'état, `enabled`, `.tofu` côté OpenTofu) ; l'état garde le même format, mais un état chiffré ou utilisant des fonctions propres à l'un n'est pas lisible par l'autre. Mélanger les deux sur un même état est la recette d'un état réécrit par le mauvais outil.

**20. HCL.**

| Expression | Valeur | Type |
|---|---|---|
| `"vm-${2050 + 1}"` | `"vm-2051"` | chaîne |
| `length(["a", "b"]) > 1` | `true` | booléen |
| `upper("m05")` | `"M05"` | chaîne |
| `[for n in ["app01", "app02"] : "m05-${n}"]` | `["m05-app01", "m05-app02"]` | tuple de chaînes |
| `{ for n in ["app01", "app02"] : n => length(n) }` | `{ app01 = 5, app02 = 5 }` | objet |
| `coalesce("", "defaut")` | `"defaut"` | chaîne : `coalesce` saute `null` **et** les chaînes vides |
| `try(tonumber("2050a"), -1)` | `-1` | nombre : la conversion échoue, `try` rend la valeur de repli |

(Vérifiées avec `tofu console`, OpenTofu 1.13.1.)

---

### M05-E02 — Installer OpenTofu et créer le projet `plateforme/infra`

**Solution**

1. **Dépôt et clés.**
   ```
   admin@adm01:~$ mkdir -p ~/m05/e02 && cd ~/m05/e02
   admin@adm01:~/m05/e02$ curl --proto '=https' --tlsv1.2 -fsSLO https://get.opentofu.org/opentofu.gpg
   admin@adm01:~/m05/e02$ curl --proto '=https' --tlsv1.2 -fsSL https://packages.opentofu.org/opentofu/tofu/gpgkey -o opentofu-repo.asc
   admin@adm01:~/m05/e02$ gpg --show-keys --with-fingerprint opentofu.gpg opentofu-repo.asc
   pub   rsa4096 2023-11-15 [SC]
         E3E6 E43D 84CB 852E ADB0  051D 0C0A F313 E5FD 9F80
   uid                      OpenTofu (This key is used to sign opentofu providers) <core@opentofu.org>
   sub   rsa4096 2023-11-15 [E]

   pub   rsa4096 2023-11-10 [SCEA]
         F4AF 70F6 6EAC 4337 EEEC  C974 07D3 DFCD 4C61 499F
   uid                      https://packagecloud.io/opentofu/tofu (https://packagecloud.io/docs#gpg_signing) <support@packagecloud.io>
   sub   rsa4096 2023-11-10 [SEA]
   ```
   L'empreinte de la clé d'OpenTofu est écrite dans le script d'installation officiel (`DEFAULT_GPG_KEY_ID="E3E6E43D84CB852EADB0051D0C0AF313E5FD9F80"`), servi par le même site. Celle de la clé du dépôt (packagecloud, l'hébergeur des paquets) n'est publiée nulle part par OpenTofu.

   Qui signe quoi :
   ```
   admin@adm01:~/m05/e02$ curl -fsSLO https://packages.opentofu.org/opentofu/tofu/any/dists/any/InRelease
   admin@adm01:~/m05/e02$ mkdir -m 700 gnupg-tmp && gpg --homedir gnupg-tmp --import opentofu.gpg opentofu-repo.asc
   admin@adm01:~/m05/e02$ gpg --homedir gnupg-tmp --verify InRelease
   gpg: Signature made …
   gpg:                using RSA key 59D41234F9F7AFD007143F6A70DF59811A8B9109
   gpg: Good signature from "https://packagecloud.io/opentofu/tofu (…)" [unknown]
   ```
   C'est une **sous-clé** de la clé packagecloud qui signe l'index du dépôt : c'est elle qu'APT utilise. La clé d'OpenTofu signe les providers publiés par le projet et des signatures détachées des paquets (`.gpgsig`) ; la documentation la déclare quand même dans `signed-by` : on suit la documentation, en sachant pourquoi.

   Réponse du journal : comparer une empreinte à celle qu'affiche **le même site** protège d'un téléchargement corrompu ou intercepté sur un seul des deux canaux, pas d'une compromission du site lui-même. Pour la clé packagecloud, c'est de la confiance au premier usage (*trust on first use*, l'ironie du nom n'échappera à personne) : on fige l'empreinte constatée aujourd'hui (le script [`installer-opentofu.sh`](fichiers/M05-E02/installer-opentofu.sh) refuse toute autre clé), et on dispose d'une vérification indépendante, cosign (« Pour aller plus loin »).

2. **Installation épinglée.** Forme documentée par OpenTofu (une ligne, deux clés séparées par une virgule), limitée au dépôt :
   ```
   admin@adm01:~/m05/e02$ sudo install -m 0755 -d /etc/apt/keyrings
   admin@adm01:~/m05/e02$ sudo install -m 0644 opentofu.gpg /etc/apt/keyrings/opentofu.gpg
   admin@adm01:~/m05/e02$ gpg --dearmor < opentofu-repo.asc | sudo tee /etc/apt/keyrings/opentofu-repo.gpg >/dev/null
   admin@adm01:~/m05/e02$ echo 'deb [signed-by=/etc/apt/keyrings/opentofu.gpg,/etc/apt/keyrings/opentofu-repo.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main' \
       | sudo tee /etc/apt/sources.list.d/opentofu.list
   admin@adm01:~/m05/e02$ printf 'Package: tofu\nPin: version 1.13.*\nPin-Priority: 1001\n' | sudo tee /etc/apt/preferences.d/opentofu
   admin@adm01:~/m05/e02$ sudo apt-get update && sudo apt-get install -y tofu
   admin@adm01:~$ tofu version
   OpenTofu v1.13.1
   on linux_amd64
   admin@adm01:~$ apt-cache policy tofu
   tofu:
     Installed: 1.13.1
     Candidate: 1.13.1
     Version table:
    *** 1.13.1 1001
           500 https://packages.opentofu.org/opentofu/tofu/any any/main amd64 Packages
           100 /var/lib/dpkg/status
        1.13.0 1001
           500 https://packages.opentofu.org/opentofu/tofu/any any/main amd64 Packages
        1.12.7 500
           500 https://packages.opentofu.org/opentofu/tofu/any any/main amd64 Packages
   …
   ```
   Le tout, rejouable et avec contrôle des empreintes : [`installer-opentofu.sh`](fichiers/M05-E02/installer-opentofu.sh) (il servira tel quel sur `runner01` en E26, ou sera repris par un rôle Ansible).

   Priorités : 1001 pour les versions qui correspondent à `1.13.*`, 500 (défaut d'un dépôt) pour les autres. APT installe la version de plus haute priorité : le jour où la 1.14.0 paraît (priorité 500), `apt upgrade` reste sur la dernière 1.13.x. Une priorité supérieure à 1000 autorise aussi un retour en arrière **dans** la série (si la 1.13.2 était retirée du dépôt, APT reviendrait à la 1.13.1). `apt install tofu=1.12.7` installe quand même la 1.12.7 : une version demandée explicitement passe outre les priorités ; l'épinglage protège des mises à jour **implicites**, pas d'un administrateur.

3. **Le poste.**
   ```
   admin@adm01:~$ tofu -install-autocomplete && exec bash
   admin@adm01:~$ mkdir -p ~/.cache/opentofu/plugins
   admin@adm01:~$ printf 'plugin_cache_dir = "$HOME/.cache/opentofu/plugins"\n' > ~/.tofurc
   ```
   Sans cache, chaque configuration (`envs/lab-m05`, `socle`, chaque module testé) télécharge sa propre copie du provider (environ 50 Mo pour `bpg/proxmox`) ; avec le cache, une seule copie, liée symboliquement dans chaque `.terraform/`. Si le dossier n'existe pas, OpenTofu affiche « The specified plugin cache dir … cannot be opened » et continue **sans** cache : il ne le crée pas.

4. **Le projet.**
   ```
   admin@adm01:~$ MERGE_METHOD=rebase_merge ~/DevOpsPrivateCloud/modules/02-scripting/corrige/fichiers/M02-E02/configurer-projet.sh plateforme/infra
   admin@adm01:~$ JETON=~/.config/workbook/gitlab-admin.token G=https://git01.par1.medisphere.internal/api/v4/projects/plateforme%2Finfra
   admin@adm01:~$ curl -sS -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(<$JETON)") "$G/access_tokens" | jq '.[] | {id, name, active}'
   admin@adm01:~$ curl -sS -X DELETE -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(<$JETON)") "$G/access_tokens/<ID>"
   admin@adm01:~$ curl -sS -X DELETE -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(<$JETON)") "$G/variables/GITLAB_TOKEN"
   ```
   (`<ID>` : l'identifiant du jeton `bot-release` affiché par la première commande. L'en-tête passe par un descripteur de fichier : le jeton n'apparaît pas dans `ps`.) La description du projet laissée par le script (« Outils d'exploitation… ») se corrige dans *Settings → General*.

   Pourquoi : un jeton `api` de rôle Maintainer, même écrit nulle part, peut être volé là où il vit (variable CI lisible par un job compromis, sauvegarde de GitLab) ; un secret qui ne sert à rien est un risque sans contrepartie. Le registre des secrets n'a pas à porter de ligne pour lui.

5. **Le squelette.** Fichiers : [`fichiers/M05-E02/infra/`](fichiers/M05-E02/infra/) — [`.gitignore`](fichiers/M05-E02/infra/.gitignore), [`.gitlab-ci.yml`](fichiers/M05-E02/infra/.gitlab-ci.yml), [`.pre-commit-config.yaml`](fichiers/M05-E02/infra/.pre-commit-config.yaml) (référence M01-E15 sans ajout), [`README.md`](fichiers/M05-E02/infra/README.md), [`envs/lab-m05/README.md`](fichiers/M05-E02/infra/envs/lab-m05/README.md), et la section à ajouter au `CONTRIBUTING.md` commun : [`CONTRIBUTING-section-infra.md`](fichiers/M05-E02/infra/CONTRIBUTING-section-infra.md). `commitlint.config.mjs`, `.gitleaks.toml`, le modèle de MR : copiés de `~/src/outils`.
   ```
   admin@adm01:~/src/infra$ git check-ignore -v envs/lab-m05/terraform.tfstate envs/lab-m05/.terraform/providers envs/lab-m05/essai.tfplan
   .gitignore:10:*.tfstate	envs/lab-m05/terraform.tfstate
   .gitignore:5:.terraform/	envs/lab-m05/.terraform/providers
   .gitignore:18:*.tfplan	envs/lab-m05/essai.tfplan
   admin@adm01:~/src/infra$ git check-ignore -v envs/lab-m05/.terraform.lock.hcl envs/lab-m05/terraform.tfvars || echo "versionnés"
   versionnés
   ```
   Attention au motif `.terraform/` : il ne couvre **que** le dossier, pas `.terraform.lock.hcl`, qui est un fichier voisin et doit être versionné. Un `.terraform*` « pour faire court » l'ignorerait.

6. **MR** : comme d'habitude (`chore: initialisation du projet infra`), pipeline vert (pre-commit, commitlint, gitleaks), fusion. Le pipeline de `main` n'a pas de job de publication : c'est voulu.

7. **Terraform à côté.** Risques : `terraform init` dans `envs/lab-m05` réécrit `.terraform.lock.hcl` avec des adresses `registry.terraform.io/…` (une MR de « bruit » au mieux, un provider d'une autre source au pire) ; un `terraform apply` sur un état OpenTofu réécrit l'état avec `terraform_version` et peut refuser ou casser ce qu'il ne connaît pas (état chiffré à partir de E27) ; deux binaires, deux comportements, des incidents qu'on ne reproduit pas. Règle proposée : **un seul outil** sur les postes et les runners de la plateforme ; Terraform s'essaie dans une VM jetable, jamais sur un état de `plateforme/infra`. À écrire dans `CONTRIBUTING.md`.

**Explications**

- **Une série épinglée, pas une version.** La série 1.13 reçoit des correctifs (dont de sécurité, comme la 1.13.1) : on les veut sans décision. Une nouvelle série change le langage ou des comportements : elle se décide par MR, en changeant **en même temps** `required_version` dans le code et la préférence APT sur `adm01` et `runner01`. Le code refuse alors de tourner avec un mauvais binaire : `required_version = "~> 1.13.0"` (E03) est la seconde ceinture.
- **Pas de semantic-release.** Une version de `plateforme/infra` n'aurait pas de sens : la « livraison » est l'`apply` d'un plan relu, sur `main`. Les étiquettes `v*` restent protégées par la configuration standard (inoffensif), mais rien ne les pose. Les **modules**, eux, se versionnent (E14, `plateforme/tofu-modules`).
- **cosign (« Pour aller plus loin »).** La signature cosign ne repose sur aucune clé à conserver : elle lie le fichier `SHA256SUMS` à l'**identité du pipeline** qui l'a produit (le flux de publication du dépôt `opentofu/opentofu` sur GitHub, via OIDC) et elle est inscrite dans un journal public de transparence (Rekor). Elle prouve d'où vient l'artefact, indépendamment de l'hébergeur des paquets et de la façon dont une clé GPG a été gardée ; elle ne prouve pas que le code publié est sain.
- **Ce que protège le `.gitignore`.** L'état (tous les attributs, des secrets), sa sauvegarde, son verrou, les plans enregistrés (binaires, ils embarquent les valeurs, sensibles comprises), le dossier `.terraform/` (providers téléchargés, plusieurs dizaines de Mo, et la configuration du backend), les journaux de plantage et les fichiers de surcharge personnels. Un fichier `*.secret.tfvars` est ignoré par principe : s'il existe, c'est que quelqu'un a mis un secret dans une variable, et il ne doit pas en plus partir dans Git.

**Alternatives**

- **Archive officielle + `SHA256SUMS` signé** (et cosign) : mêmes garanties, mais ni mise à jour par APT ni inventaire par `dpkg -l` ; utile sur une machine sans accès au dépôt.
- **Gestionnaire de versions** (`tofuenv`, `asdf`, `mise`) : plusieurs versions d'OpenTofu sur un même poste, choisie par projet (`.opentofu-version`). Pratique pour un consultant qui travaille sur dix projets ; inutile sur un poste d'administration qui ne doit avoir qu'**une** version, celle de la plateforme.
- **Image de conteneur** `ghcr.io/opentofu/opentofu` épinglée par empreinte : le modèle des runners Docker/Kubernetes (modules 12 et 19).

**Pièges classiques**

- Déclarer la clé dans `/etc/apt/trusted.gpg.d/` (vieux tutoriels, `apt-key add`) : elle vaut alors pour **tous** les dépôts.
- Épingler `Pin: version 1.13.1` (une version exacte) : les correctifs de sécurité ne s'installent plus.
- Oublier que l'épinglage est **par machine** : `runner01` (E26) doit avoir la même préférence, sinon le pipeline et ton poste divergent.
- Un `plugin_cache_dir` sur un dossier qui n'existe pas : message à chaque commande, et pas de cache.
- Relancer `configurer-projet.sh` plus tard « pour remettre les protections » : il recrée le jeton `bot-release`. Écris l'écart dans le `README.md`.

**En production chez MédiSphère**

- OpenTofu et sa préférence APT sont posés par le rôle Ansible `base` (ou un rôle `outils_iac`) sur `adm01` et `runner01`, avec la version dans l'inventaire : changer de série = une MR dans `plateforme/ansible` et une dans `plateforme/infra`, relues ensemble.
- Un miroir APT interne (Aptly, Pulp, module 13) sert les paquets : on ne dépend plus d'Internet au moment d'un incident, et la clé est vérifiée une fois, à l'entrée du miroir.
- Renovate (module 13) propose les montées de version d'OpenTofu et des providers en MR, avec le changelog.

---

### M05-E03 — Compte Proxmox `wb-tofu`, provider épinglé, premier plan

**Solution**

*1. Lire avant d'écrire.* La page d'accueil du provider (version 0.115) répond :
- jeton : argument `api_token` ou variable `PROXMOX_VE_API_TOKEN`, au format **`utilisateur@royaume!jeton=secret`** (une seule chaîne) ; adresse : `endpoint` ou `PROXMOX_VE_ENDPOINT`, de la forme `https://hôte:8006/`, **sans** `/api2/json` ;
- SSH n'est exigé que pour quatre opérations : téléverser des *snippets* (`proxmox_virtual_environment_file` de type `snippets`), certains types de fichiers, l'import de disque par `source_file.path`, et l'`idmap` des conteneurs. Avec un jeton d'API, il faut un compte **PAM** sur le nœud (`ssh { username = … }`), avec un `sudo` sans mot de passe restreint à des commandes précises (`/usr/sbin/pvesm apiinfo`, `tee` vers le dossier des snippets) — la documentation met en garde contre tout `sudo` sur `qm` ou `pvesm` entiers, équivalents à root ;
- au palier 1, aucune de ces opérations : **pas de bloc `ssh`**, pas de compte système sur `pve01`. La question reviendra en E19 (snippets cloud-init).

*2. Privilèges.* Relevés dans l'API viewer de Proxmox VE 9 :

| Opération du provider | Appel | Contrôle |
|---|---|---|
| Cloner le template | `POST /nodes/{node}/qemu/{vmid}/clone` | `VM.Clone` sur `/vms/{vmid}` **et** (`VM.Allocate` sur `/vms/{newid}` **ou** `VM.Allocate` sur `/pool/{pool}` si le paramètre `pool` est passé) ; plus `Datastore.AllocateSpace` sur les stockages et `SDN.Use` sur les VNets utilisés |
| Régler la VM | `PUT`/`POST …/config` | au moins un `VM.Config.*`, puis contrôle par paramètre (CPU, mémoire, disque, réseau, matériel, options, cloud-init) |
| Agrandir le disque | `PUT …/resize` | `VM.Config.Disk` |
| Démarrer, éteindre, redémarrer, arrêter | `POST …/status/{start,shutdown,reboot,stop}` | `VM.PowerMgmt` |
| Détruire | `DELETE /nodes/{node}/qemu/{vmid}` | `VM.Allocate` sur `/vms/{vmid}` |
| Lire l'adresse IP | `GET …/agent/network-get-interfaces` | `VM.GuestAgent.Audit` **ou** `VM.GuestAgent.Unrestricted` |
| Lire config et état | `GET …/config`, `…/status/current` | `VM.Audit` |
| Lister les VMs, les pools, les stockages | `GET /nodes/{node}/qemu`, `GET /pools`, `GET /nodes/{node}/storage` | aucun refus : **filtrage** par `VM.Audit`, `Pool.Audit`, `Datastore.Audit` ou `Datastore.AllocateSpace` |

Le point clé est le clone : la VM 2050 n'existe pas encore, donc `/vms/2050` n'hérite d'aucun droit du pool ; c'est la seconde branche qui s'applique, `VM.Allocate` sur `/pool/lab`, **parce que** le provider passe `pool` dans la requête quand la ressource a un `pool_id` (code du provider, `vmCreateClone`). Sans `pool_id`, le même jeton recevrait un 403 au clonage.

Liste minimale et justification : en commentaires dans [`pve-tofu-compte.sh`](fichiers/M05-E03/pve-tofu-compte.sh) (rôle `WBTofu` : `VM.Audit`, `VM.Clone`, `VM.Allocate`, `VM.Config.CPU`, `.Memory`, `.Disk`, `.CDROM`, `.Network`, `.HWType`, `.Options`, `.Cloudinit`, `VM.PowerMgmt`, `VM.GuestAgent.Audit`, `Pool.Audit` ; `PVEDatastoreUser` sur `/storage/local-nvme` ; `PVESDNUser` sur `/sdn/zones/lab/vsandbox`). Écartés : `VM.Console` (rien à taper, contrairement à Packer), `VM.Migrate` (un seul nœud), `VM.Snapshot*` et `VM.Backup` (PBS s'en charge), `VM.GuestAgent.Unrestricted` et `VM.GuestAgent.File*` (exécuter ou lire dans l'invité : `Audit` suffit pour les adresses), `Datastore.Allocate` (supprimer **n'importe quel** volume du stockage), `Pool.Allocate`, tout `Sys.*`. `VM.Config.CDROM` mérite une remarque : le lecteur cloud-init est un média de type `cdrom` ; le garder évite un refus au moment où le provider (re)crée ce lecteur (point « à vérifier » du début du corrigé).

*3. Compte.*
```
admin@adm01:~$ scp ~/DevOpsPrivateCloud/modules/05-iac/corrige/fichiers/M05-E03/pve-tofu-compte.sh pve01:/root/
root@pve01:~# bash pve-tofu-compte.sh
>>> Secret du jeton ci-dessous (« value ») : copie-le MAINTENANT dans pve-tofu.env sur adm01.
┌──────────────┬──────────────────────────────────────┐
│ key          │ value                                │
╞══════════════╪══════════════════════════════════════╡
│ full-tokenid │ wb-tofu@pve!tofu                     │
├──────────────┼──────────────────────────────────────┤
│ info         │ {"comment":"OpenTofu, …","expire":…} │
├──────────────┼──────────────────────────────────────┤
│ value        │ xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx │
└──────────────┴──────────────────────────────────────┘
== droits effectifs du jeton sur /
== droits effectifs du jeton sur /pool/lab
…
```
(Ton script, s'il est écrit autrement, doit avoir les mêmes propriétés : rejouable, ACL sur l'utilisateur **et** sur le jeton, expiration, contrôle final.) Rien pour `/` : c'est le résultat attendu. Rappel de M00-E17 : un jeton à privilèges séparés n'a que l'**intersection** des ACL de l'utilisateur et des siennes ; poser les ACL seulement sur le jeton ne donnerait rien.

*4. Secret.*
```
admin@adm01:~$ install -m 600 /dev/null ~/.config/workbook/pve-tofu.env
admin@adm01:~$ ${EDITOR:-nano} ~/.config/workbook/pve-tofu.env
```
Contenu : [`pve-tofu.env.exemple`](fichiers/M05-E03/pve-tofu.env.exemple). Registre des secrets : ligne de [`registre-secrets-extrait.md`](fichiers/M05-E03/registre-secrets-extrait.md), par MR dans `plateforme/medisphere`.

*5. Code.* [`versions.tf`](fichiers/M05-E03/infra/envs/lab-m05/versions.tf), [`providers.tf`](fichiers/M05-E03/infra/envs/lab-m05/providers.tf), [`main.tf`](fichiers/M05-E03/infra/envs/lab-m05/main.tf), et le [`.terraform.lock.hcl`](fichiers/M05-E03/infra/envs/lab-m05/.terraform.lock.hcl) produit par `tofu init`.
```
admin@adm01:~/src/infra/envs/lab-m05$ tofu init
Initializing the backend...

Initializing provider plugins...
- Finding bpg/proxmox versions matching "~> 0.115.0"...
- Installing bpg/proxmox v0.115.0...
- Installed bpg/proxmox v0.115.0 (signed, key ID 0B3405B36193A495)
…
OpenTofu has created a lock file .terraform.lock.hcl to record the provider
selections it made above. Include this file in your version control repository…
admin@adm01:~/src/infra/envs/lab-m05$ tofu providers

Providers required by configuration:
.
└── provider[registry.opentofu.org/bpg/proxmox] ~> 0.115.0
```
Réponses du journal :
- Adresse complète : `registry.opentofu.org/bpg/proxmox` (`bpg/proxmox` est un raccourci : l'hôte par défaut d'OpenTofu est son registre). Le registre fournit l'adresse de l'archive (sur GitHub, chez l'auteur), son empreinte et la **signature GPG** de l'auteur sur la liste des empreintes : « signed, key ID 0B3405B36193A495 ».
- Le fichier contient 13 empreintes `h1:` et 14 `zh:`. `zh:` est l'empreinte SHA-256 de chaque **archive** publiée (une par plateforme : linux_amd64, linux_arm64, darwin, windows…, telle que la liste signée par l'auteur) ; `h1:` est une empreinte calculée sur le **contenu** décompressé du paquet. Depuis OpenTofu 1.12, `tofu init` enregistre les empreintes de **toutes** les plateformes que le registre annonce : le même fichier vaut pour ton poste, `runner01` et un Mac, sans `tofu providers lock`.
- Une empreinte modifiée : au prochain `tofu init`, le paquet téléchargé (ou trouvé dans le cache) ne correspond plus, et OpenTofu refuse de l'installer (« doesn't match any of the checksums previously recorded in the dependency lock file »). C'est la protection contre un paquet substitué.
- `.terraform/` contient le provider décompressé (`providers/registry.opentofu.org/bpg/proxmox/0.115.0/linux_amd64/`, ou un lien vers le cache), et plus tard les modules téléchargés et la configuration du backend : tout se reconstruit par `tofu init`, c'est volumineux et propre au poste.

*6. Premier plan.* Sans les accès :
```
Error: Missing Proxmox VE API Endpoint
…
The provider cannot create the Proxmox VE API client as there is a missing or
empty value for the API endpoint. Set the host value in the configuration or
use the PROXMOX_VE_ENDPOINT environment variable.
```
Avec :
```
admin@adm01:~/src/infra/envs/lab-m05$ set -a; . ~/.config/workbook/pve-tofu.env; set +a
admin@adm01:~/src/infra/envs/lab-m05$ tofu plan
data.proxmox_version.pve01: Reading...
data.proxmox_version.pve01: Read complete after 0s [id=version]

Changes to Outputs:
  + version_pve = "9.0.10"

You can apply this plan to save these new output values to the OpenTofu
state, without changing any real infrastructure.
admin@adm01:~/src/infra/envs/lab-m05$ tofu apply
…
Apply complete! Resources: 0 added, 0 changed, 0 destroyed.

Outputs:

version_pve = "9.0.10"
```
Rien n'a été créé sur `pve01`. Le dossier contient maintenant `terraform.tfstate` (une source de données et une sortie : l'état existe dès le premier apply, même sans ressource) ; `tofu output` affiche `version_pve`.

*7. Ce que le plan prouve.*
- Faux secret : `Error: Unable to Read Version … received an HTTP 401 response - Reason: Unauthorized`. Un jeton mal formé (sans `=secret`) échoue plus tôt : « the API token must be in the format 'USER@REALM!TOKENID=UUID' ».
- `SSL_CERT_FILE=/dev/null tofu plan` **réussit encore** ; avec `SSL_CERT_DIR=/dev/null` en plus, il échoue : `tls: failed to verify certificate: x509: failed to load system roots and no roots provided`. Le provider construit son client TLS sans liste d'autorités (`proxmox/api/client.go` : `tls.Config{MinVersion: …, InsecureSkipVerify: insecure}`) : Go utilise le **magasin du système**, qu'il lit dans **un** fichier (`SSL_CERT_FILE`, sinon `/etc/ssl/certs/ca-certificates.crt`) **et** dans des dossiers (`SSL_CERT_DIR`, sinon `/etc/ssl/certs`). `update-ca-certificates` (M03-E02) a mis l'autorité de `pve01` aux deux endroits ; c'est pourquoi vider le seul fichier ne suffit pas. Conclusion : la vérification est active, et elle repose sur le magasin d'`adm01` (et, en E26, sur celui de `runner01`).
- Un plan réussi ne prouve **rien** sur les privilèges : `GET /version` est autorisé à tout utilisateur authentifié (« user: all » dans l'API viewer). Les droits se prouvent par `pveum user token permissions` (étape 3), puis par la première création (E04).

*8. Réponse au ticket* : les tableaux ci-dessus, le mécanisme TLS, l'absence de SSH au palier 1 (et ce qu'il faudra en E19), la provenance du provider (registre OpenTofu, signature de l'auteur vérifiée à l'installation, empreintes figées dans le fichier de verrouillage versionné), le renouvellement : `JETON=tofu2 ./pve-tofu-compte.sh`, bascule du fichier et de la variable CI, `tofu plan` vide sur chaque configuration, suppression de l'ancien (`pveum user token remove wb-tofu@pve tofu`).

**Explications**

- **Aucun secret dans le code, même « pour l'instant ».** Les variables `PROXMOX_VE_*` viennent de l'environnement ; le code ne contient que `insecure = false`, écrit pour que la revue n'ait pas à deviner la valeur par défaut. Un `api_token = var.jeton` serait à peine mieux : la valeur finirait dans un `*.tfvars` ou dans l'historique du shell.
- **Le provider est du code exécuté avec tes droits.** Il reçoit le jeton et parle à l'API. D'où les trois garanties : un registre identifié, une signature de l'auteur vérifiée à l'installation, et des empreintes figées et relues en MR (`.terraform.lock.hcl`). Le jour où l'empreinte change sans changement de version, c'est un incident.
- **`min_tls`** vaut `1.3` par défaut dans ce provider : Proxmox VE 9 l'accepte. Inutile de l'écrire, mais à savoir si un jour un proxy intermédiaire ne parle que TLS 1.2.

**Alternatives**

- **Écrire les accès dans des variables OpenTofu** (`TF_VAR_api_token`) : même effet que l'environnement du provider, mais la valeur devient une variable de la configuration, donc susceptible d'apparaître dans un plan si on s'en sert mal. Le provider sait lire ses variables seul : autant en profiter.
- **Authentification par ticket** (`PROXMOX_VE_AUTH_TICKET`, avec TOTP) : utile pour un humain, pas pour un pipeline.
- **Compte `root@pam` et mot de passe** : certaines opérations l'exigent (architecture du CPU, `hookscript`, RNG, AMD SEV, `ciupgrade`) ; le workbook ne les utilise pas, et le jour où il le faudrait, ce serait une décision de sécurité (ADR), pas une facilité.

**Pièges classiques**

- `PROXMOX_VE_ENDPOINT` qui se termine par `/api2/json` : le provider l'ajoute lui-même, les requêtes partent vers `/api2/json/api2/json/…` (404).
- L'adresse de `pve01` qui n'est pas dans son certificat (nom court, autre interface) : erreur de nom (`x509: certificate is valid for …, not …`), à ne pas « corriger » avec `insecure = true`.
- Oublier `set -a` : les variables du fichier sont définies dans le shell mais pas **exportées**, le provider ne les voit pas.
- Lancer `tofu init` avant d'avoir écrit la contrainte de version : le fichier de verrouillage retient la dernière version du provider, peut-être hors de la série voulue.
- Croire qu'un plan qui « marche » valide les droits du jeton (étape 7).

**En production chez MédiSphère**

- Le jeton a une date d'expiration **et** un rappel : une alerte (module 21) à J-30, et la procédure de rotation testée une fois par an (RB-05x).
- En CI (E26), les deux variables sont des variables **protégées et masquées** de `plateforme/infra`, disponibles seulement sur `main` et pour le job d'apply ; les plans de MR utiliseraient idéalement un second jeton **en lecture seule** (`PVEAuditor` sur le pool), pour qu'une MR malveillante ne puisse rien modifier.
- Au module 25, le jeton vient de Vault/OpenBao, avec une durée de vie courte.

---

### M05-E04 — Première VM déclarée

**Solution**

*1. Documentation.* Correspondances : `vm_id`, `name`, `node_name`, `pool_id`, `tags`, `description` ; `clone { vm_id, full, datastore_id }` ; `cpu { cores, type }`, `memory { dedicated }`, `scsi_hardware`, `disk { interface, datastore_id, size, file_format, iothread, discard, ssd }`, `serial_device {}`, `vga { type }`, `operating_system { type = "l26" }`, `agent { enabled }` ; `network_device { bridge, model }` ; `initialization { datastore_id, dns { domain, servers }, ip_config { ipv4 { address = "dhcp" } }, user_account { username, keys } }` ; `on_boot`, `started`, `stop_on_destroy`.

Réponses du journal :
- Sur un clone, cela dépend de l'argument, et c'est précisément le piège (code du provider : `vmCreateClone` pour l'envoi, `vmReadCustom` pour la relecture). Certains blocs ont une valeur par défaut **toujours envoyée** après le clonage : `cpu` (1 cœur, type `qemu64`), `memory` (512 Mo), `operating_system` (`other`), `on_boot` (`true`) ; ne pas les écrire **change** la VM par rapport au template. D'autres réglages ne sont envoyés que s'ils diffèrent de la valeur par défaut, et, pour un clone, **ne sont pas relus** tant que la configuration ne les déclare pas : `scsi_hardware`, `bios`, `description`, `tags`. Le contrôleur SCSI non écrit garde donc la valeur du template (`virtio-scsi-single`)… sans que l'état ni le plan le disent. Règle pratique : **écrire tout ce qui compte**, avec la valeur de l'image.
- Section *Cloning* : si on décrit un disque du clone, il faut redonner **tous** ses attributs qui diffèrent des défauts du schéma (`size`, `discard`, `cache`, `aio`…), sinon les défauts s'appliquent et écrasent ceux du template.
- `agent.enabled` : un clone hérite du réglage `agent` du template ; le provider se fie à la configuration **réelle** de la VM : même sans bloc `agent`, il attend l'agent jusqu'à 15 minutes si le template l'a activé. À l'inverse, activer l'agent sur une image qui ne le lance pas bloque arrêts et redémarrages (ils passent par l'agent). L'image dorée de M03 contient `qemu-guest-agent` : on l'active, avec un délai plus court.

*2. Trouver l'image.*
```
root@pve01:~# for id in $(qm list | awk '$1 >= 9010 && $1 <= 9029 {print $1}'); do echo "$id $(qm config $id | grep -E '^(name|tags):' | tr '\n' ' ')"; done
9011 name: deb13-gold-20260928-1 tags: debian13;gold
9012 name: deb13-gold-20261005-1 tags: current;debian13;gold
root@pve01:~# qm config 9012
agent: 1
boot: order=scsi0
cores: 2
cpu: x86-64-v2-AES
description: Image dorée deb13-gold-20261005-1%0ASource %3A template 9001 …
ide2: local-nvme:vm-9012-cloudinit,media=cdrom
memory: 2048
name: deb13-gold-20261005-1
net0: virtio=BC:24:11:…,bridge=vsandbox
scsi0: local-nvme:base-9012-disk-0,discard=on,iothread=1,size=8G,ssd=1
scsihw: virtio-scsi-single
serial0: socket
tags: current;debian13;gold
template: 1
vga: serial0
…
```
(Ton VMID et ta date diffèrent.) Un clone sans étiquettes déclarées porterait `current;debian13;gold` et la description de l'image.

*3. Code.* [`fichiers/M05-E04/infra/envs/lab-m05/main.tf`](fichiers/M05-E04/infra/envs/lab-m05/main.tf) (avec `versions.tf`, `providers.tf` et le fichier de verrouillage de E03). Remplace `9012` par ton `<VMID-CURRENT>` et `"pve01"` par ton `<NOEUD>`.

*4. Le plan* (extrait, sortie réelle du provider 0.115.0) :
```
OpenTofu will perform the following actions:

  # proxmox_virtual_environment_vm.essai will be created
  + resource "proxmox_virtual_environment_vm" "essai" {
      + acpi                                 = true
      + bios                                 = "seabios"
      + delete_unreferenced_disks_on_destroy = true
      + description                          = "VM d'essai du module 05. Gérée par OpenTofu (plateforme/infra, envs/lab-m05) : ne pas modifier à la main."
      + id                                   = (known after apply)
      + ipv4_addresses                       = (known after apply)
      + keyboard_layout                      = "en-us"
      + mac_addresses                        = (known after apply)
      + name                                 = "m05-essai"
      + on_boot                              = false
      + pool_id                              = "lab"
      + purge_on_destroy                     = true
      + reboot_after_update                  = true
      + scsi_hardware                        = "virtio-scsi-single"
      + started                              = true
      + stop_on_destroy                      = true
      + tags                                 = [
          + "env-m05",
        ]
      + timeout_clone                        = 1800
      …
      + vm_id                                = 2050

      + clone {
          + datastore_id = "local-nvme"
          + full         = true
          + retries      = 1
          + vm_id        = 9012
        }
      + disk {
          + aio               = "io_uring"
          + backup            = true
          + cache             = "none"
          + datastore_id      = "local-nvme"
          + discard           = "on"
          + file_format       = "raw"
          + interface         = "scsi0"
          + iothread          = true
          + path_in_datastore = (known after apply)
          + size              = 10
          + ssd               = true
        }
      + initialization {
          + datastore_id         = "local-nvme"
          + upgrade              = (known after apply)
          …
          + user_account {
              + keys     = [
                  + "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA… admin@adm01",
                ]
              + username = "admin"
            }
        }
      …
    }

Plan: 1 to add, 0 to change, 0 to destroy.
```
Une soixantaine d'attributs affichés pour une vingtaine écrits : le plan montre **tout** ce que le provider enverra ou suivra, valeurs par défaut comprises (`timeout_*`, `purge_on_destroy`, `keyboard_layout`, `acpi` : défauts du schéma de la ressource, donc décisions implicites qu'on accepte). Sont `(known after apply)` les valeurs que seul Proxmox ou la VM connaîtront : `id`, les adresses (rapportées par l'agent), les MAC (générées au clonage), `path_in_datastore` (nom du volume), `units` du CPU, `upgrade` de cloud-init (calculé par Proxmox).

*5. Appliquer.* `tofu apply` dure en général de 1 à 3 minutes : clonage complet (copie des 8 Go sur `local-nvme`), configuration (`POST …/config`), agrandissement du disque (`PUT …/resize`), démarrage, puis attente de l'agent (cloud-init et démarrage de Debian). Dans `qm config 2050`, on retrouve chaque valeur du plan, plus `ide2: local-nvme:vm-2050-cloudinit,media=cdrom`, `sshkeys` (encodée), `ipconfig0: ip=dhcp`, `nameserver: 10.10.20.10`, `searchdomain: par1.medisphere.internal`, `onboot: 0`. Le disque s'appelle `local-nvme:vm-2050-disk-0` : un clone **lié** sur LVM-thin s'appellerait `base-9012-disk-0/vm-2050-disk-0` (il référencerait le volume du template, qu'on ne pourrait plus supprimer). `qm cloudinit dump 2050 user` montre le *user-data* généré par Proxmox : `user: admin`, la clé dans `ssh_authorized_keys`, `hostname: m05-essai`, `fqdn: m05-essai.par1.medisphere.internal`.

*6. Se connecter.*
```
admin@adm01:~/src/infra/envs/lab-m05$ tofu output essai_ipv4
[
  "10.10.99.123",
]
root@pve01:~# qm guest exec 2050 -- ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
{
   "exitcode" : 0,
   "exited" : 1,
   "out-data" : "256 SHA256:Qm3k… root@m05-essai (ED25519)\n"
}
admin@adm01:~$ ssh admin@10.10.99.123
The authenticity of host '10.10.99.123 (10.10.99.123)' can't be established.
ED25519 key fingerprint is SHA256:Qm3k….
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```
On compare les deux empreintes **avant** de répondre `yes`. Puis : `hostname -f` (`m05-essai.par1.medisphere.internal`), `sudo -n true`, `resolvectl dns` (10.10.20.10), `df -h /` (environ 10 Go : la partition racine a été agrandie au premier démarrage par cloud-init, module `growpart`).

*7. Plan vide.* Avec le code du corrigé, le second plan affiche « No changes. Your infrastructure matches the configuration. » Un plan non vide vient d'un attribut dont la valeur **relue** chez Proxmox diffère de celle du code : valeur normalisée par Proxmox (une taille, un format), réglage que Proxmox ajoute seul, attribut écrit d'une façon que le provider ne reconnaît pas comme équivalente. La correction est dans le code (écrire la valeur telle que Proxmox la rend), ou, si Proxmox la modifie lui-même légitimement, dans un `lifecycle { ignore_changes }` justifié. Et l'inverse est aussi vrai : un plan vide ne prouve pas que tout est conforme. Ce que le provider ne relit pas sur un clone (étiquettes, description, contrôleur non déclarés) n'apparaîtra **jamais** dans un plan : E05 le montre.

*8. MR* : description avec le plan de création ; après fusion, `git switch main && git pull && tofu plan` : vide.

**Explications**

- **Ce que fait le provider, dans l'ordre.** Clone (`POST …/clone`, avec `pool`, `full`, `storage`, `name`, `description`), attente de la fin de la tâche, puis **une** mise à jour de configuration qui pose tout ce que la ressource décrit, puis le disque (redimensionnement), puis le démarrage et l'attente des adresses par l'agent. Quand l'apply se termine, l'état contient la VM avec tous ses attributs relus.
- **cloud-init de Proxmox.** Les arguments d'`initialization` deviennent les options `ciuser`, `sshkeys`, `ipconfig0`, `nameserver`, `searchdomain` de la VM ; Proxmox génère le lecteur NoCloud. L'image dorée (M03) n'attend que ça : utilisateur et clé injectés au clonage.
- **`on_boot` vaut `true` par défaut dans le provider** (c'est l'inverse dans Proxmox). Pour une VM d'environnement, on ne veut pas qu'elle redémarre avec `pve01` et consomme de la mémoire : `false`, écrit.

**Alternatives**

- **Clone lié** (`full = false`) : quelques secondes au lieu d'une minute, et presque pas de place. Réservé aux VMs jetables d'un test automatique (PLAN, M03) : la VM dépend du template, qui ne peut plus être supprimé.
- **Création à partir d'une image cloud** (`disk { import_from = … }` et `proxmox_download_file`) sans template : c'est ce que montre l'exemple de la documentation. On perd tout ce que garantit l'image dorée (durcissement, tests, CA).
- **`proxmox_cloned_vm`** (« Pour aller plus loin ») : nouvelle ressource du provider qui ne gère **que** ce qui est écrit et laisse le reste au template. Elle résout le problème des défauts du provider sur un clone ; mais elle est récente, son comportement sur la dérive est différent (ce qui n'est pas écrit n'est pas surveillé), et le provider la range dans les ressources du « framework » qui évoluent encore. Le workbook la cite sans l'adopter : une décision à reprendre quand elle sera stabilisée.

**Pièges classiques**

- Oublier `tags` : le clone porte `current`, et devient, pour une recherche par étiquette sans filtre `template`, « l'image courante » (E05, E08).
- Écrire `size = 6` sur un clone de 8 Go : Proxmox ne réduit jamais un disque ; l'apply échoue.
- `agent { enabled = true }` sur une image sans agent : apply bloqué 15 minutes (puis échec), destruction qui n'en finit pas (l'arrêt passe par l'agent). D'où `timeout = "5m"` et `stop_on_destroy = true` sur des VMs jetables.
- Le VNet `vsandbox` sans `SDN.Use` pour le jeton : le **clonage** échoue déjà (le template est sur `vsandbox`), même si la VM devait aller ailleurs.
- `file("~/.ssh/id_ed25519.pub")` : « no file exists at "~/.ssh/id_ed25519.pub" » ; `file()` ne développe pas `~` (`pathexpand()`).
- Se connecter en SSH à la VM avec `StrictHostKeyChecking=no` « parce que c'est une VM jetable » : c'est précisément l'habitude qui fera accepter un jour une clé usurpée sur une VM qui ne l'est pas.

**En production chez MédiSphère**

- Le plan de création est joint à la MR par le pipeline (E26), et un garde-fou refuse tout plan qui détruit plus de N ressources sans approbation explicite.
- Les VMs d'environnement portent une date d'expiration (étiquette ou description) et un nettoyage planifié les signale ; un `tofu destroy` par environnement, jamais une suppression à la main.

---

### M05-E05 — Plan, apply, destroy et fichier d'état

**Solution**

*1. L'état.*
```
admin@adm01:~/src/infra/envs/lab-m05$ tofu state list
data.proxmox_version.pve01
proxmox_virtual_environment_vm.essai
admin@adm01:~/src/infra/envs/lab-m05$ jq '{version, terraform_version, serial, lineage}' terraform.tfstate
{
  "version": 4,
  "terraform_version": "1.13.1",
  "serial": 4,
  "lineage": "3c0e…-…"
}
```
- `version` : version du **format** du fichier (4 depuis Terraform 0.12, inchangé dans OpenTofu). `serial` : compteur incrémenté à chaque écriture de l'état ; `lineage` : identifiant fixé à la création de l'état. Ensemble, ils empêchent d'écraser un état plus récent par un plus ancien (serial inférieur), ou par un état d'une **autre** lignée (un état recréé de zéro qui porterait les mêmes noms) : OpenTofu refuse ces écritures sur un backend distant (E11).
- Oui, la clé publique est dans l'état (`initialization[0].user_account[0].keys`), comme chaque attribut. Un mot de passe cloud-init y serait aussi, **en clair**, même déclaré `sensitive` (marqué dans `sensitive_attributes`, mais présent). L'état contient aussi tout ce que le provider a relu : MAC, adresses, chemins des volumes, valeurs par défaut.

*2. Modification sur place.*
```
admin@adm01:~/m05/e05$ jq '.resource_changes[] | {address, actions: .change.actions}' plan-memoire.json
{
  "address": "proxmox_virtual_environment_vm.essai",
  "actions": [
    "update"
  ]
}
```
(D'autres entrées peuvent apparaître pour des sources de données relues pendant l'apply.) La VM **redémarre** : la mémoire de Proxmox ne s'ajoute à chaud que si le *hotplug* de la mémoire est activé (et NUMA avec), ce qui n'est pas le cas par défaut (`hotplug: network,disk,usb`). Le changement reste « en attente » côté Proxmox, et le provider, qui a `reboot_after_update = true` par défaut, redémarre la VM pour l'appliquer (tâche `qmreboot` dans le journal des tâches ; `uptime` dans la VM). « Sur place » signifie même VM, même disque, même identité ; pas « sans interruption ». Avec `reboot_after_update = false`, l'apply aurait échoué au lieu de redémarrer (comportement documenté de l'argument).

Rejouer le même fichier de plan :
```
Error: Saved plan is stale

The given plan file can no longer be applied because the state was changed by
another operation after the plan was created.
```
Un plan enregistré est lié au `serial` (et à la lignée) de l'état sur lequel il a été calculé : on ne peut appliquer qu'un plan calculé sur l'état **actuel**. C'est ce qui rend sûr le schéma « plan en MR, apply du même plan » (E26).

*3. Remplacement.*
- `vm_id = 2051` : le plan affiche `-/+ resource … must be replaced` et, à côté de l'attribut, `~ vm_id = 2050 -> 2051 # forces replacement`. Dans le JSON : `"actions": ["delete", "create"]` et `"action_reason": "replace_because_cannot_update"`. On remet 2050 avant toute application.
- `tofu apply -replace=proxmox_virtual_environment_vm.essai` (raison `replace_by_request`) : destruction **puis** création (`-/+`) ; la VM 2050 disparaît pendant une à deux minutes. À la reconnexion :
  ```
  @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  @    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
  @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  ```
  Normal : nouvelle VM, nouvelles clés d'hôte (l'image est préparée pour que chaque clone génère les siennes, M03-E07). Traitement propre : relire l'empreinte par l'agent (`qm guest exec 2050 -- ssh-keygen -lf …`), puis `ssh-keygen -R <IP>` et première connexion en comparant. L'adresse change souvent : nouvelle MAC générée au clonage, donc nouveau bail DHCP.

*4. Destruction.* `tofu plan -destroy` liste `- resource … will be destroyed` et `Plan: 0 to add, 0 to change, 1 to destroy`. Après `tofu destroy` : `qm list` ne montre plus 2050 ; `tofu state list` ne montre plus que la source de données (ou rien) ; le `serial` a augmenté. `terraform.tfstate.backup` est la **version précédente** de l'état (celle d'avant ce destroy) : OpenTofu en garde une seule, écrasée à chaque écriture. Ce n'est pas une sauvegarde au sens de PBS : deux opérations plus tard, elle a disparu.

*5. L'héritage silencieux.* Ligne `tags` commentée, VM recréée par `-replace` (un `apply` simple aurait seulement **retiré** les étiquettes de la VM existante : `~ tags = ["env-m05"] -> null`) :
```
root@pve01:~# qm config 2050 | grep tags
tags: current;debian13;gold
admin@adm01:~/src/infra/envs/lab-m05$ tofu plan
…
No changes. Your infrastructure matches the configuration.
```
Le clonage copie la configuration du template, étiquettes et description comprises. Pour un clone, le provider n'envoie les étiquettes que si la configuration en déclare (`len(tags) > 0` dans `vmCreateClone`), et ne les **relit** que si la configuration en déclare (`vmReadCustom` : « `len(clone) == 0 || len(currentTags) > 0` ») ; même logique pour la description. Il ne voit donc pas ce qu'il ne gère pas, et le plan est vide. Conséquences : l'inventaire dynamique d'Ansible (M04-E13), qui fabrique des groupes à partir des étiquettes, ne mettrait pas cette VM dans `role_*` (pas d'étiquette `role-`), mais la prendrait pour ce qu'elle n'est pas si l'on cherche `current` ; une recherche de l'image courante **par étiquettes seulement** trouverait deux candidats (l'image et cette VM) ; un script de rotation des images (M03-E16) pourrait la prendre pour une image. Ligne rétablie, `tofu plan` propose `+ tags = ["env-m05"]` (l'état n'en avait pas), l'apply remplace `current;debian13;gold` par `env-m05`.

*6. Le verrou local.* Pendant l'apply apparaît `.terraform.tfstate.lock.info` (qui, quand, quelle opération). Le second terminal :
```
Error: Error acquiring the state lock

Error message: resource temporarily unavailable
Lock Info:
  ID:        6b1f…
  Path:      terraform.tfstate
  Operation: OperationTypeApply
  Who:       admin@adm01
  Version:   1.13.1
  Created:   …
```
Ce verrou est un verrou de **fichier** sur `adm01` : il ne protège que des processus du même poste qui utilisent le même fichier. Un `apply` lancé depuis `runner01` aurait **son** état (ou une copie) : aucune exclusion. D'où le verrou côté backend (E12).

*7.* Mémoire à 2048 Mo dans `main.tf` ([`fichiers/M05-E05/…/main.tf`](fichiers/M05-E05/infra/envs/lab-m05/main.tf)), MR avec le plan, fusion, plan vide.

**Explications**

- **Trois natures de changement, trois symboles.** `~` garde l'identité de la ressource, `-/+` la remplace (nouvelle VM, nouveau disque, nouvelles clés, souvent nouvelle adresse), `-` la supprime. La raison est toujours dans le plan : on la lit avant de taper `yes`.
- **Le plan enregistré.** `tofu plan -out` fige les actions, les valeurs **et** le `serial` de l'état. `tofu show -json` le rend lisible par un programme : c'est sur ce JSON qu'on écrit des garde-fous (« refuser tout plan qui détruit une VM du socle », E09 et E26). Le fichier de plan contient les valeurs sensibles : il se traite comme l'état.
- **L'état est la mémoire d'OpenTofu, et elle est simple.** Un JSON lisible, que l'on **lit** sans scrupule (`jq`, `tofu state show`) et que l'on ne modifie **jamais** à la main : une erreur de syntaxe, un `serial` incohérent, une ressource retirée à tort, et OpenTofu recréera ou oubliera des VMs. Les commandes `tofu state mv/rm`, `tofu import` et les blocs `moved`/`removed`/`import` (palier 2) existent pour ça.

**Alternatives**

- `-target` pour n'appliquer qu'une ressource : réservé à l'exception (E09, question 12).
- `tofu taint` (déprécié au profit de `-replace`) : marquait une ressource à remplacer au prochain apply, en modifiant l'état sans plan relu.

**Pièges classiques**

- Croire qu'une modification « en place » est sans impact : mémoire, CPU, contrôleur, certains réglages de disque redémarrent la VM (`reboot_after_update`). Sur le socle, un plan `~` se lit aussi attentivement qu'un `-/+`.
- Appliquer sans `-out` un plan relu la veille : l'apply recalcule, et peut faire **autre chose** que ce qui a été relu (la réalité ou le code ont changé).
- Supprimer `terraform.tfstate` « parce que le plan est bizarre » : OpenTofu ne connaît plus rien ; le plan suivant veut **créer** la VM 2050, qui existe déjà (erreur de VMID) — ou pire, avec un VMID automatique, en créer une seconde.
- `StrictHostKeyChecking=no` après un remplacement : voir E04.

**En production chez MédiSphère**

- Les plans enregistrés et leurs JSON sont des artefacts du pipeline (E26), conservés quelques jours seulement (ils contiennent des secrets), et le job d'apply ne peut appliquer **que** le plan de son pipeline.
- Un remplacement de VM du socle passe par un ticket de changement (CHG-…) avec fenêtre, sauvegarde PBS vérifiée la veille et procédure de retour.

---

### M05-E06 — Variables, `locals`, sorties, types et validations

**Solution**

Fichiers complets : [`variables.tf`](fichiers/M05-E06/infra/envs/lab-m05/variables.tf), [`locals.tf`](fichiers/M05-E06/infra/envs/lab-m05/locals.tf), [`main.tf`](fichiers/M05-E06/infra/envs/lab-m05/main.tf), [`outputs.tf`](fichiers/M05-E06/infra/envs/lab-m05/outputs.tf), [`terraform.tfvars`](fichiers/M05-E06/infra/envs/lab-m05/terraform.tfvars).

L'essentiel de `variables.tf` :
```hcl
variable "vm_essai" {
  type = object({
    vmid       = number
    nom        = string
    coeurs     = optional(number, 2)
    memoire_mo = optional(number, 2048)
    disque_go  = optional(number, 10)
  })

  validation {
    condition     = var.vm_essai.vmid >= 2050 && var.vm_essai.vmid <= 2059
    error_message = "Les VMs d'environnement du module 05 ont un VMID entre 2050 et 2059 (PLAN §4.6)."
  }
  validation {
    condition     = can(regex("^m05-[a-z0-9]([a-z0-9-]{0,18}[a-z0-9])?$", var.vm_essai.nom))
    error_message = "Le nom commence par m05-, en minuscules, chiffres et tirets (c'est aussi le nom d'hôte)."
  }
  # … mémoire (512-8192, multiple de 256), cœurs (1-4), disque (10-100)
}
```

*1-2.* La clé publique passe de `file(pathexpand(…))` à `var.cles_ssh_admin` (dans `terraform.tfvars`) : en CI, `runner01` n'a pas le `~/.ssh/id_ed25519.pub` d'`adm01` ; la clé fait partie de la **description** de l'environnement, pas du poste qui lance OpenTofu ; et on peut en donner plusieurs (secours). Le plan après refactoring est **vide** : c'est le seul critère d'un refactoring réussi. S'il ne l'est pas, une valeur a changé : défaut de `memoire_mo` à 1024 alors que la VM est à 2048 depuis E05, étiquettes non triées, description réécrite.

*3. Les garde-fous.*
```
admin@adm01:~/src/infra/envs/lab-m05$ tofu plan -var 'vm_essai={vmid=1004, nom="m05-essai"}'
…
Error: Invalid value for variable

  on variables.tf line 85:
  85: variable "vm_essai" {
    ├────────────────
    │ var.vm_essai.vmid is 1004

Les VMs d'environnement du module 05 ont un VMID entre 2050 et 2059 (PLAN
§4.6).

This was checked by the validation rule at variables.tf:95,3-13.
```
Même forme pour les autres cas (« Le nom commence par m05-… », « Mémoire entre 512 et 8192 Mo… », « Au moins une clé… », « Étiquettes réservées interdites… », « Les VMs du workbook vont dans le pool « lab »… »). Moment : les validations sont évaluées **pendant** le parcours du graphe du plan, au même titre que le reste. OpenTofu a donc déjà configuré le provider et peut avoir **lu** des sources de données (la version de PVE, en E08 l'image courante) ; mais l'erreur interrompt le plan avant toute action : aucune ressource n'est planifiée, et un plan en erreur ne peut pas être appliqué. Le garde-fou protège des **écritures**, pas des lectures.

Une validation peut citer d'autres variables (OpenTofu l'accepte, E07 s'en sert) ; elle ne peut pas citer une ressource ni une source de données.

*4. Explorer.*
```
> var.vm_essai
{
  "coeurs" = 2
  "disque_go" = 10
  "memoire_mo" = 2048
  "nom" = "m05-essai"
  "vmid" = 2050
}
> type(var.vm_essai)
object({
    coeurs: number,
    disque_go: number,
    memoire_mo: number,
    nom: string,
    vmid: number,
})
> local.etiquettes
[
  "env-m05",
]
> proxmox_virtual_environment_vm.essai.ipv4_addresses
[
  [
    "127.0.0.1",
  ],
  [
    "10.10.99.123",
  ],
]
```
Les attributs facultatifs omis sont **présents** avec leur valeur par défaut (et `type()`, fonction réservée à la console, le confirme). `ipv4_addresses` est une liste **par interface** rapportée par l'agent, la boucle locale en premier : d'où `flatten`, le filtre sur `127.`, `[0]` et `try(…, null)` (liste vide tant que l'agent n'a pas répondu, ou avec `agent.wait_for_ip.disabled`).

*5. Priorités* (de la plus faible à la plus forte) : valeur par défaut de la variable ; variables d'environnement `TF_VAR_…` ; `terraform.tfvars` ; `terraform.tfvars.json` ; fichiers `*.auto.tfvars` (ordre alphabétique) ; enfin `-var` et `-var-file` **dans l'ordre de la ligne de commande**, le dernier gagnant. Résultats : `TF_VAR_environnement=m99` → `m99` (rien d'autre ne fixe `environnement` : le défaut `m05` perd) ; avec `essai.auto.tfvars` → `m98` ; avec `-var environnement=m97` → `m97` ; `-var-file=f.tfvars` (m96) placé **après** `-var` → `m96`, **avant** → `m97`. Le fichier `essai.auto.tfvars` est retiré (sinon il s'applique silencieusement à toute commande).

*6. Sensible.*
```
admin@adm01:~/src/infra/envs/lab-m05$ tofu output
essai = <sensitive>
version_pve = "9.0.10"
admin@adm01:~/src/infra/envs/lab-m05$ tofu output -json | jq .essai
{
  "sensitive": true,
  "type": [ "object", { … } ],
  "value": { "fqdn": "m05-essai.par1.medisphere.internal", "ipv4": "10.10.99.123", "vmid": 2050 }
}
admin@adm01:~/src/infra/envs/lab-m05$ jq '.outputs.essai' terraform.tfstate
{ "value": { … en clair … }, "type": [ … ], "sensitive": true }
```
Conclusion pour Sophie : `sensitive` est un masque d'**affichage**. La valeur est en clair dans l'état et dans `-json`. La seule protection de l'état, c'est son stockage (accès, chiffrement : E11, E27).

**Explications**

- **Données dans `terraform.tfvars`, logique dans le code.** C'est la règle d'Ansible (« le code est générique, les données sont dans l'inventaire », M04-E06) appliquée à OpenTofu. Le code de l'environnement de E15 ou d'un autre module sera le même ; seules les valeurs changeront.
- **Des validations qui protègent ce qui n'est pas à toi.** Elles ne servent pas à vérifier que Proxmox accepte la valeur (il le dira), mais à empêcher qu'une valeur **valide pour Proxmox** fasse du dégât : un VMID du socle, le mauvais pool, une étiquette qui ferait entrer la VM dans l'inventaire du socle. Le message dit quoi faire, pas seulement ce qui est faux.
- **`locals` pour calculer une fois.** Les étiquettes triées et dédoublonnées, la description : une seule définition, utilisée par toutes les ressources (E07 en ajoute trois).

**Alternatives**

- **`*.auto.tfvars` par environnement** (`lab.auto.tfvars`) plutôt que `terraform.tfvars` : même effet, nom plus parlant quand un dossier sert plusieurs environnements. Le workbook préfère un dossier par environnement (E15).
- **Variables d'environnement `TF_VAR_…` en CI** pour des valeurs non secrètes : à éviter, la configuration n'est plus lisible dans le dépôt.
- **Préconditions sur la ressource** (`lifecycle { precondition }`) plutôt que validations de variables : utiles quand la règle dépend d'une valeur lue (une source de données), ce qu'une validation ne peut pas faire.

**Pièges classiques**

- `optional()` sans valeur par défaut : l'attribut vaut `null`, et `null` passé à un argument du provider veut dire « valeur par défaut du **provider** » (1 cœur, 512 Mo).
- Une validation qui ne gère pas `null` (`var.x.vmid >= 2050` sur un objet nul) : erreur d'évaluation au lieu du message prévu. `nullable = false` ferme la porte.
- Le refactoring qui change un défaut : `memoire_mo` à 1024 par défaut quand la VM est à 2048 depuis E05 → le plan veut réduire la mémoire, et redémarrer la VM.
- Un `essai.auto.tfvars` oublié dans le dossier : il s'applique à **chaque** commande, sans le dire, et il n'est même pas ignoré par Git.
- Mettre `sensitive = true` partout « par sécurité » : les plans deviennent illisibles en revue, sans rien protéger de plus dans l'état.

**En production chez MédiSphère**

- Les garde-fous de plage (VMID, pool, VNet) sont dans le **module** `vm-debian` (E13), pas dans chaque environnement : impossible de les oublier.
- Une politique (OPA/conftest, module 29) lit le plan JSON en CI et refuse ce qu'une validation ne peut pas voir (« aucune VM du socle détruite », « aucune VM de plus de 16 Go sans étiquette d'approbation »).

---

### M05-E07 — `count`, `for_each` et blocs dynamiques

**Solution**

*Partie A.* Après `tofu apply` : `terraform_data.serveur[0]`, `[1]`, `[2]`. Plan du retrait d'`app02` (sortie réelle) :
```
  # terraform_data.serveur[1] will be updated in-place
  ~ resource "terraform_data" "serveur" {
        id     = "bde70d9a-44d1-ef54-26d5-5f213d85b267"
      ~ input  = {
          ~ nom  = "m05-app02" -> "m05-app03"
            # (1 unchanged attribute hidden)
        }
    }

  # terraform_data.serveur[2] will be destroyed
  # (because index [2] is out of range for count)
  - resource "terraform_data" "serveur" {
      - input  = {
          - nom  = "m05-app03"
          - vmid = 2053
        } -> null
    }

Plan: 0 to add, 1 to change, 1 to destroy.
```
Lecture : l'instance `[1]` (la VM d'`app02`, VMID 2052) serait **renommée** `m05-app03` en gardant le VMID 2052 et le disque d'`app02` ; l'instance `[2]` (le vrai `app03`, ses données) serait **détruite**. Avec des VMs, le changement de nom est sur place, mais si le VMID était calculé autrement, ce serait un remplacement : dans tous les cas, on rend `app02` et c'est `app03` qui disparaît.

Version `for_each` : [`fichiers/M05-E07/compteur/main.tf`](fichiers/M05-E07/compteur/main.tf). Le premier plan après réécriture propose de **détruire** `[0]`, `[1]`, `[2]` (« because resource does not use count ») et de **créer** `["app01"]`, `["app02"]`, `["app03"]` : les adresses ont changé et OpenTofu ne peut pas deviner la correspondance (sur des VMs : trois destructions, trois créations ; le bloc `moved` de E17 l'évite). Après application, retirer `app02` :
```
  # terraform_data.serveur["app02"] will be destroyed
  # (because key ["app02"] is not in for_each map)
Plan: 0 to add, 0 to change, 1 to destroy.
```

Règle : `for_each` dès que les instances ont une **identité** (un nom, un rôle, des données) ; `count` pour des instances interchangeables (N nœuds identiques d'un groupe, dont on ne retire jamais que le dernier) ou pour un « zéro ou un » — que le méta-argument `enabled` d'OpenTofu 1.11 fait mieux (« Pour aller plus loin »).

*Partie B.* Fichiers : [`fichiers/M05-E07/infra/envs/lab-m05/`](fichiers/M05-E07/infra/envs/lab-m05/) (variable `vms_app` dans `variables.tf`, ressource `app` dans `main.tf`, sortie `apps`, valeurs dans `terraform.tfvars`). Le cœur :
```hcl
resource "proxmox_virtual_environment_vm" "app" {
  for_each = var.vms_app

  vm_id = each.value.vmid
  name  = "m05-${each.key}"
  # …
  dynamic "disk" {
    for_each = { for i, taille in each.value.disques_donnees : "scsi${i + 1}" => taille }
    content {
      interface    = disk.key
      datastore_id = var.stockage_vm
      size         = disk.value
      file_format  = "raw"
      iothread     = true
      discard      = "on"
      ssd          = true
    }
  }
}
```
Le `dynamic` itère sur un dictionnaire interface → taille, construit par une expression `for` avec index ; la clé donne l'interface. Le plan crée trois VMs et ne mentionne pas `essai`. Dans les VMs, `lsblk` montre `sdb` (2 G) sur `m05-app02`, `sdb` (2 G) et `sdc` (3 G) sur `m05-app03` (disques vierges, sans partition).

*Étape 7.*
- Rendre `app02` : seule `proxmox_virtual_environment_vm.app["app02"]` est détruite.
- 3 → 4 Go : `~ size = 3 -> 4` sur place, agrandissement à chaud (`hotplug` comprend `disk`) ; dans la VM, le disque grandit, le système de fichiers éventuel reste à agrandir.
- 3 → 2 Go : le plan l'**accepte** (`~ size = 3 -> 2`) ; l'apply échouerait : « Cannot shrink local-nvme:vm-2053-disk-2 in VM 2053, it is not supported! » (code du provider) — Proxmox ne réduit jamais un disque (`PUT …/resize` n'accepte que des agrandissements). Un plan valide n'est pas un apply réussi.
- `[3]` au lieu de `[2, 3]` : `scsi1` passe de 2 à 3 Go (agrandi : il garde les **données du premier disque**), `scsi2` est **supprimé** avec ses données. Exactement le défaut de `count` : l'identité du disque est sa position dans la liste. Une liste convient pour un exercice ; en production, on décrirait les disques par un dictionnaire dont la clé **est** l'interface (`{ scsi1 = 2, scsi2 = 3 }`), pour que retirer l'un ne décale pas l'autre.

**Explications**

- **Adresse = identité.** OpenTofu ne connaît pas les noms de VM : il associe des **adresses** (`app["app02"]`) à des objets. Tout ce qui change une adresse (passer de `count` à `for_each`, renommer une ressource, déplacer dans un module) ressemble pour lui à « une ressource disparaît, une autre apparaît ».
- **`dynamic` génère des blocs, pas des ressources.** Les disques sont des blocs imbriqués d'une même ressource : leur ordre et leur clé comptent pour le provider (ici l'interface). `dynamic` ne doit pas servir à rendre illisible une configuration simple : on l'utilise quand le **nombre** de blocs varie.

**Alternatives**

- Une **source de vérité** des VMs hors du code (un fichier YAML lu par `yamldecode`, NetBox au module 06) : les données sortent du HCL, et Julien pourrait demander une VM sans écrire de HCL.
- Des **modules** (E13) : la ressource dupliquée entre `essai` et `app` disparaît.

**Pièges classiques**

- `for_each` sur une **liste** : refusé (« The given "for_each" argument value is unsuitable… ») ; il faut un ensemble de chaînes (`toset(…)`) ou un dictionnaire.
- Des clés connues seulement à l'apply (`for_each` sur des attributs calculés) : « Invalid for_each argument ».
- Changer la valeur d'une clé (`app02` → `app2`) : c'est une destruction et une création.
- Deux VMs avec le même VMID dans le dictionnaire : la seconde création échoue au milieu de l'apply ; la validation de `vms_app` le refuse au plan.

**En production chez MédiSphère**

- Les demandes de Julien passent par une MR sur `terraform.tfvars` (ou un fichier de données), relue par l'équipe Plateforme : c'est déjà un libre-service, avec revue. Le module 28 (Backstage) ira plus loin.
- Chaque VM d'environnement porte le ticket qui l'a demandée (`etiquettes_supplementaires = ["dev-607"]`) : on sait à qui elle est.

---

### M05-E08 — Sources de données : trouver l'image dorée courante

**Solution**

Fichiers : [`fichiers/M05-E08/infra/envs/lab-m05/`](fichiers/M05-E08/infra/envs/lab-m05/), en particulier [`data.tf`](fichiers/M05-E08/infra/envs/lab-m05/data.tf) :
```hcl
data "proxmox_virtual_environment_vms" "image_courante" {
  node_name = var.noeud
  tags      = ["current", "debian13", "gold"]

  filter {
    name   = "template"
    values = [true]
  }
  filter {
    name   = "name"
    regex  = true
    values = ["^deb13-gold-[0-9]{8}-[0-9]+$"]
  }

  lifecycle {
    postcondition {
      condition     = length(self.vms) == 1
      error_message = "Il faut exactement UNE image dorée Debian 13 étiquetée current (trouvé : ${length(self.vms)}). …"
    }
  }
}

locals {
  image_vmid = data.proxmox_virtual_environment_vms.image_courante.vms[0].vm_id
}
```

*1. Explorer.* Avec les seules étiquettes, la liste contient le template ; elle contiendrait aussi toute **VM** clonée sans étiquettes déclarées (E05), qui porte `current;debian13;gold`. D'où le filtre `template` (et le filtre de nom, qui écarte un template bricolé à la main). Tous les filtres doivent être satisfaits ; dans un filtre, une valeur suffit.

*2. Échouer tôt.* Avec `curent` :
```
Error: Resource postcondition failed

  on data.tf line 23, in data "proxmox_virtual_environment_vms" "image_courante":
  23:       condition     = length(self.vms) == 1
    ├────────────────
    │ self.vms is empty list of object

Il faut exactement UNE image dorée Debian 13 étiquetée current (trouvé : 0).
Vérifie la publication des images (M03-E10) avant tout plan.
```
Le plan s'arrête dès la lecture : aucune ressource n'est évaluée. Sans postcondition, l'erreur serait « Invalid index » sur `vms[0]`, bien moins parlante ; et avec **deux** images `current`, on clonerait sans bruit la première de la liste (triée par VMID).

*3. Brancher.* Si l'image `current` est toujours celle de E04, le plan est vide : passer d'une valeur écrite à une valeur lue ne change rien quand la valeur est la même. Si une nouvelle image a été publiée depuis (la chaîne de M03 tourne chaque semaine), le plan propose de **remplacer les quatre VMs** (`clone[0].vm_id` est *ForceNew*). C'est exactement la crainte de Karim.

*4. Le lundi suivant.* Filtre temporaire sur `["base", "debian13"]` sans contrainte de nom : le plan affiche quatre `-/+` avec `~ vm_id = 9012 -> 9001 # forces replacement` dans le bloc `clone`. Après ajout, dans chaque ressource,
```hcl
  lifecycle {
    ignore_changes = [clone]
  }
```
le plan est vide. Vrai filtre remis. Réponses du journal :
- passer volontairement une VM sur la nouvelle image : `tofu apply -replace='proxmox_virtual_environment_vm.app["app01"]'` ; le remplacement relit la source de données et clone l'image courante. On le fait VM par VM, quand on l'a décidé (et pour le socle, par un changement planifié) ;
- l'état garde, dans le bloc `clone` de chaque VM, l'image **d'origine** (celle du dernier `apply` qui a créé ou mis à jour l'attribut) ; avec `ignore_changes`, cette valeur n'est plus mise à jour : elle reste vraie (la VM a bien été clonée de cette image), et c'est même une information utile (« Pour aller plus loin »).

*5. Contrôle.*
```hcl
check "place_sur_le_stockage_des_vms" {
  data "proxmox_datastores" "vms" {
    node_name = var.noeud
    filters   = { id = var.stockage_vm }
  }
  assert {
    condition     = alltrue([for d in data.proxmox_datastores.vms.datastores : coalesce(d.space_available, 0) > 50 * 1024 * 1024 * 1024])
    error_message = "Moins de 50 Gio libres sur ${var.stockage_vm} : un clone complet de plus pourrait remplir le stockage."
  }
}
```
Avec un seuil de 10 Tio : `Warning: Check block assertion failed` et le message, puis le plan continue ; il peut être appliqué. Un `check` **signale** (et est réévalué à chaque plan et apply) ; une postcondition **bloque**. On préfère un `check` pour un état du monde qui mérite l'attention sans justifier d'empêcher le travail (place, version d'un service, certificat proche de l'expiration). À noter : quand le plan prévoit des changements, OpenTofu relit aussi les données du `check` pendant l'apply (« will be read during apply (config will be reloaded to verify a check block) »).

*6. Droits.* `GET /nodes/{node}/qemu` ne **refuse** jamais : il ne liste que les VMs où le jeton a `VM.Audit`. Une image sortie du pool `lab` disparaît simplement de la liste : pas d'erreur de droits, mais la postcondition échoue avec « trouvé : 0 ». C'est pourquoi le message de la postcondition doit évoquer les causes possibles (publication, pool, droits) : une liste vide n'en dit pas plus.

**Explications**

- **Désigner par ce que c'est, pas par son numéro.** Les étiquettes `gold` + `debian13` + `current` sont le **contrat** entre la chaîne d'images (M03) et ses consommateurs (Ansible/Molecule en M04, OpenTofu ici). Le VMID est un détail d'implémentation qui change chaque semaine.
- **Une valeur lue change sans MR.** C'est le revers des sources de données : la configuration n'a pas bougé, mais le plan, si. `ignore_changes` rétablit la règle « rien ne change sans décision » pour les attributs qui ne doivent agir qu'**à la création**.
- **La source dépréciée.** `proxmox_virtual_environment_vm` (source de données d'une seule VM) est marquée dépréciée dans le schéma du provider depuis 0.101, au profit de la nouvelle `proxmox_vm` ; OpenTofu 1.12+ signale aussi, par un avertissement, les attributs et blocs dépréciés qu'une configuration utilise. `proxmox_virtual_environment_vms` (la liste), elle, ne l'est pas.

**Alternatives**

- **Le nom plutôt que les étiquettes** (`filter { name = "name", regex = true, values = ["^deb13-gold-"] }` et le dernier par ordre) : fragile, on contourne la publication (une image non testée serait prise).
- **Une sortie de la chaîne d'images** (le VMID publié dans un fichier ou un état distant lu par `terraform_remote_state`) : couplage plus fort entre les deux dépôts, sans avantage tant que Proxmox est la source de vérité.
- **`replace_triggered_by`** pour remplacer automatiquement une VM quand l'image change : l'inverse de ce qu'on veut pour des VMs durables ; envisageable pour des nœuds jetables d'un cluster.

**Pièges classiques**

- Oublier le filtre `template` : un clone qui a hérité de `current` devient candidat ; avec deux candidats, la postcondition le dit… si elle existe.
- `ignore_changes = all` « pour être tranquille » : plus aucune dérive n'est vue ni corrigée sur la VM.
- Mettre `depends_on` sur la source de données : sa lecture est repoussée à l'apply, `vm_id` du clone devient « known after apply », et le plan ne dit plus quelle image sera clonée.
- Tester la postcondition en modifiant les étiquettes **des templates** dans Proxmox : tu casses la publication de M03 et les autres consommateurs. On fausse le **filtre**, pas le catalogue.

**En production chez MédiSphère**

- Un rapport hebdomadaire (Nadia) liste les VMs dont l'image d'origine n'est plus `current` depuis plus de 30 jours : candidates à un remplacement planifié (immuabilité progressive), ou à une mise à jour par Ansible si elles sont mutables.
- Le module `vm-debian` (E13) embarque la source de données, les filtres, la postcondition et `ignore_changes` : un consommateur ne peut pas les oublier.

---

### M05-E09 — Questions : OpenTofu, Terraform et l'état

**Barème** : 2 points par question, total sur 30. Une réponse sans exemple tiré de ton environnement quand la question en demande un plafonne à 1.

**1. Rafraîchissement.** Au début d'un plan, OpenTofu demande au provider de relire chaque ressource de l'état (et les sources de données) et met à jour sa vue de la réalité, **en mémoire**. `-refresh=false` saute cette lecture : plus rapide, mais le plan compare le code à un état peut-être faux (une VM supprimée à la main serait « modifiée » au lieu d'être recréée ; une dérive ne serait pas vue). Acceptable pour tester un changement de code sans toucher l'API (validations de E06), dangereux pour un plan qu'on va appliquer. `-refresh-only` fait l'inverse : il **ne propose que** de mettre l'état à jour avec la réalité, sans toucher l'infrastructure ; utile après une modification légitime faite hors d'OpenTofu (et reportée dans le code), dangereux comme moyen de « faire taire » une dérive qu'on ne comprend pas.

**2. `serial` et `lineage`.** `lineage` identifie **une** histoire d'état (fixée à la création) ; `serial` numérote ses versions. Scénario : deux personnes ont chacune une copie de l'état local (serial 12) ; l'une applique (serial 13) et pousse sa copie sur un partage ; l'autre, qui a appliqué autre chose de son côté (serial 13 aussi, mais un contenu différent), écrase la première. Sur un backend, OpenTofu refuse d'écrire un état de serial inférieur ou égal avec un contenu différent, ou d'une autre lignée : l'erreur se voit au lieu de se perdre. Le verrou (E12) empêche de toute façon les deux apply simultanés.

**3. Fichier de verrouillage.** `zh:` = SHA-256 de l'archive zip de chaque plateforme, telle que publiée par l'auteur dans sa liste d'empreintes **signée** ; `h1:` = empreinte du contenu du paquet installé (indépendante du format d'archive). Depuis 1.12, `tofu init` enregistre les empreintes de toutes les plateformes annoncées par le registre : si `runner01` passe un jour sur arm64, son `tofu init` trouve déjà l'empreinte attendue. Le fichier garantit qu'on installe **exactement** les mêmes octets partout, et refuse un paquet substitué. Il ne garantit pas que la version choisie la première fois était saine : c'est la signature de l'auteur (vérifiée à l'installation) et la revue de la MR qui ajoute ou change le fichier qui le font.

**4. Valeur sensible.** Elle peut se retrouver : dans l'**état** (attributs et sorties), dans le **fichier de plan** enregistré et son export JSON, dans `tofu output -json`, dans les journaux du provider en mode débogage (`TF_LOG=DEBUG`), dans l'historique du shell si on l'a passée par `-var`, dans un artefact de CI. Les valeurs **éphémères** (variables et sorties `ephemeral = true`, ressources éphémères) n'existent qu'en mémoire pendant une commande et ne sont jamais écrites dans l'état ni dans le plan ; les attributs ***write-only*** d'un provider sont envoyés à l'API sans être stockés. Le provider doit les prendre en charge : c'est la piste pour les mots de passe (module 25).

**5. Remplacements.** Forcent le remplacement : `vm_id`, tout le bloc `clone` (`vm_id`, `full`, `datastore_id`, `node_name`), `node_name` (sauf `migrate = true`), les fichiers cloud-init personnalisés (`user_data_file_id`, `vendor_data_file_id`, `network_data_file_id`, `meta_data_file_id`), la version du TPM, le type de disque EFI. `create_before_destroy` crée la nouvelle VM **avant** de détruire l'ancienne : avec un `vm_id` fixé, la création échoue (le VMID est encore pris). Il faudrait un VMID différent (ou automatique), donc une VM qui change d'identifiant : incompatible avec nos conventions.

**6. Apply partiel.** OpenTofu écrit l'état après **chaque** ressource traitée. Les deux VMs créées sont dans l'état, normales. La troisième, créée mais dont la fin de création a échoué, est dans l'état marquée **tainted** (« tainted » : l'objet existe mais n'est pas fiable) ; la quatrième n'y est pas. Le plan suivant : rien pour les deux premières (si la réalité correspond), **remplacement** de la troisième (« is tainted, so must be replaced »), création de la quatrième. Si l'on sait la troisième saine, `tofu untaint` évite le remplacement ; sinon on laisse faire.

**7. Retirer de l'état.** `tofu state rm` : retire la ressource de l'état immédiatement, sans plan, sans trace dans le dépôt. Bloc `removed { from = …  lifecycle { destroy = false } }` : la même intention écrite dans le code, visible dans le plan (« will be removed from the OpenTofu state but will not be destroyed »), relue en MR. `lifecycle { destroy = false }` sur la ressource (1.12) : la ressource reste dans le code, mais si elle doit être détruite (retrait, remplacement), OpenTofu se contente de l'oublier ; utile pour une ressource qu'on ne veut **jamais** voir détruite par OpenTofu. Le bloc `removed` est celui qui laisse une trace relue ; c'est l'outil de E17.

**8. Compatibilité des états.** Le format (version 4) est le même : un état OpenTofu 1.13 **sans** fonctionnalité propre est en général lisible par Terraform 1.16 (et réciproquement), mais rien ne le garantit dans la durée, et l'état mémorise `terraform_version`. Un état **chiffré** par OpenTofu (E27) est illisible par Terraform. Précautions pour changer d'outil : suivre le guide de migration officiel (version de départ et d'arrivée supportées), déchiffrer l'état avant, sauvegarder l'état et ses versions, vérifier un plan vide avec le nouvel outil **avant** tout apply, régénérer le fichier de verrouillage (adresses de registre différentes).

**9. Fichiers `.tofu`.** Un `.tofu` est un fichier de configuration lu **seulement** par OpenTofu ; si `main.tf` et `main.tofu` coexistent, OpenTofu ignore `main.tf` et lit `main.tofu` (Terraform, lui, ignore `main.tofu`). Utile à un auteur de module qui veut offrir à OpenTofu une fonctionnalité propre (chiffrement, `enabled`) tout en restant compatible avec Terraform. Le bloc `language` (1.12) sépare les contraintes de version d'OpenTofu du reste ; il ne remplace pas encore `terraform {}` dans l'outillage : tflint, terraform-docs, Checkov, Trivy (E20, E25) comprennent `terraform { required_version … }` et pas forcément `language`. Le projet garde donc le bloc classique ; à revoir quand l'outillage suivra.

**10. Lire le `CHANGELOG.md`.** Avant une montée : lire **toutes** les versions entre l'actuelle et la cible, chercher d'abord « BREAKING CHANGES », puis les corrections qui touchent les ressources qu'on utilise (`vm`, `file`, `vms`), puis les fonctionnalités. Exemples entre 0.100 et 0.115 : 0.100.0 « vm: set power state of VM centrally » (gestion de `started`, peut changer le comportement au démarrage et à l'arrêt : à tester sur `envs/lab-m05`) ; 0.101.0 « vm: fix and improve VM datasources, deprecate SDK datasource » (la source d'une VM est dépréciée : n'aurait pas touché notre code, qui utilise la liste) ; 0.109.0 « vm: restore ipv4_addresses on refresh for existing VMs » (nos sorties `ipv4` en dépendent : bénéfique). Un avertissement de dépréciation (affiché par OpenTofu 1.12+ pour tout élément déprécié du schéma) annonce une suppression future : on le traite à la prochaine MR, pas le jour où la version suivante casse le plan.

**11. Héritage silencieux.** Le provider ne lit, sur un clone, que ce que la configuration déclare (code `vmReadCustom`) : c'est un choix pour éviter que tout réglage hérité du template apparaisse comme une dérive à corriger. Le revers : ce qu'on ne déclare pas n'est pas surveillé. Autres réglages hérités : la **description** (le manifeste de l'image se retrouve sur la VM), le `hookscript`, et, côté provider, l'agent (attente de 15 minutes, E04). Règle : sur un clone, **déclarer** tout ce qui a un sens pour l'identité de la VM (étiquettes, description) et pour son matériel.

**12. Réponse B.** `-target` restreint le plan à une ressource et à ses dépendances : légitime pour une réparation pendant un incident, en sachant que le reste de l'écart n'est pas traité ; OpenTofu l'affiche d'ailleurs comme une exception. On relance un plan complet juste après. A : la vitesse n'est jamais une raison (on découpe les configurations, E15). C : c'est de la dissimulation. D : l'option existe (avec `-exclude`, ajouté par OpenTofu).

**13. `on_boot`.** Les VMs d'environnement ne doivent pas redémarrer avec `pve01` : elles consommeraient de la mémoire pour rien, et un environnement oublié se rallumerait à chaque redémarrage. Pour le socle, c'est l'inverse : les VMs importées en E16 ont `onboot: 1` et un ordre de démarrage (`startup`, M01 : `git01` order=4, `runner01` order=5) ; si la configuration d'import ne les décrit pas tels qu'ils sont (`on_boot = true`, bloc `startup`), le plan propose de les ramener aux valeurs par défaut du provider, et un `apply` distrait supprimerait l'ordre de démarrage du socle. Un plan d'import se lit ligne à ligne.

**14. Qui fait quoi.**

| Réglage | Outil | Pourquoi |
|---|---|---|
| Version de chrony | Packer (image) puis Ansible | paquet de l'image dorée, mis à jour et configuré ensuite par le rôle `base` |
| Adresse IP de `s3-01` | OpenTofu (cloud-init : `ip_config`) | identité de l'instance, connue à la création |
| Utilisateur `admin` et sa clé | OpenTofu → cloud-init | identité de l'instance, jamais dans l'image (M03) ; Ansible gère ensuite les clés de l'équipe (`base`) |
| Mémoire d'une VM | OpenTofu | propriété de la VM vue par l'hyperviseur |
| Configuration de SeaweedFS | Ansible (rôle `seaweedfs`, E10) | configuration de l'intérieur, qui évolue après la création |
| CA provisoire dans le magasin | Packer (image) | commun à toutes les VMs ; une nouvelle CA (M06) = une nouvelle image, et Ansible pour le parc existant |

La frontière : OpenTofu crée et décrit la **machine** (et ce qui doit être connu au premier démarrage), Packer fabrique ce qui est **commun**, Ansible gère ce qui **vit** dans la machine.

**15. Verrou local.** `.terraform.tfstate.lock.info` (avec un verrou de fichier du système) empêche deux commandes **sur le même poste et le même fichier** d'écrire l'état en même temps. Il ne protège pas deux postes (chacun a sa copie), ni un état copié ailleurs. `-lock=false` supprime cette protection : deux écritures concurrentes peuvent produire un état incohérent ou perdre des ressources. Les seuls usages défendables : une commande de lecture pendant qu'un verrou **orphelin** est en cours d'analyse (E33, E36), et les vérifications du workbook, qui ne font que des plans sans enregistrement.
