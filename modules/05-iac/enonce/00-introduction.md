# Module 05 — Introduction : Infrastructure as Code avec OpenTofu

## Personne ne sait ce qui devrait exister

Lundi, 9 h 20. La revue de capacité de Nadia a tourné court.

> **De** : Claire Morel — Responsable infrastructure
> **À** : toi
> **Cc** : Karim Benali, Sophie Laurent, Nadia Roussel, Julien Petit, Lucas Martin
> **Objet** : Les machines passent en code, elles aussi — projets `plateforme/infra` et `plateforme/tofu-modules`
>
> Bonjour à tous,
>
> Ce matin, Nadia a trouvé sur `pve01` une VM 2044 allumée depuis trois semaines, quatre disques orphelins sur `local-nvme`, et un clone lié de l'ancienne image dorée qui empêche de la retirer. Personne n'a su dire à qui ils étaient, ni s'ils devaient exister. La configuration des machines est en code depuis le module 04 ; leur **existence**, elle, dépend encore de qui a cliqué ou lancé quel script.
>
> Décision : l'infrastructure du lab est **déclarée**. Un dépôt, `plateforme/infra`, dit quelles VMs doivent exister, avec quelles ressources, sur quel réseau. Toute création, modification ou destruction passe par un **plan** relu en MR avant d'être appliqué. Ce qui n'est pas dans le dépôt n'a pas vocation à exister.
>
> L'outil retenu est **OpenTofu** : licence libre (Terraform est passé sous licence BUSL en 2023, et OpenTofu en est le fork maintenu par la Linux Foundation), verrou d'état S3 natif, chiffrement de l'état côté client. Karim fixe les règles : versions épinglées, modules réutilisables versionnés dans `plateforme/tofu-modules`, jamais d'`apply` sans plan lu. Sophie a deux exigences : l'état contient des secrets, il sera **chiffré** ; et le code d'infrastructure sera **analysé** comme du code applicatif.
>
> Premier obstacle, et pas des moindres : un état partagé a besoin d'un stockage objet S3. Nous avions prévu MinIO ; son éditeur a abandonné l'édition communautaire. Il nous faut une alternative, sur notre socle, sans dépendre d'un fournisseur.
>
> Julien attend des environnements de test qu'il puisse demander sans ouvrir de ticket. Lucas écrira ses premières configurations ; tu les reliras.
>
> On commence comme d'habitude par un test de positionnement.
> Claire

---

## Ce que tu construis dans ce module

À la fin du module 05 :

- **OpenTofu 1.13** est installé sur `adm01` puis sur `runner01`, depuis le dépôt officiel signé, avec un compte Proxmox dédié **`wb-tofu@pve`** (jeton à privilèges minimaux) ;
- le projet **`plateforme/infra`** décrit l'environnement d'exercices du module (`envs/lab-m05`, VMs 2050-2059) et tout le **socle** (`socle/`) : `s3-01` créée par le code, les VMs existantes (`adm01`, `dns01`, `git01`, `runner01`) **importées** sans être recréées ;
- **`s3-01`** (VMID 1006, 10.10.20.14), nouvel hôte permanent : stockage objet **SeaweedFS** en HTTPS, configuré par un rôle Ansible, qui héberge l'**état distant** d'OpenTofu, versionné, verrouillé et **chiffré** ;
- un module **`vm-debian`** réutilisable, versionné par semantic-release dans **`plateforme/tofu-modules`** et consommé par étiquette ;
- une chaîne de qualité (fmt, validate, tflint, terraform-docs, Checkov, Trivy) et un **pipeline** qui produit le plan en MR et applique, sur `main` seulement, le plan relu ;
- **Terragrunt** pour factoriser backends et environnements ; une détection de **dérive** planifiée ; une procédure de sauvegarde et de restauration de l'état ;
- la capacité à diagnostiquer les pannes d'IaC : dérive, verrou bloqué, backend inaccessible, droits, état désynchronisé ou perdu, provider qui change de comportement.

## Architecture du module

```
                ┌──────────────── git01 (1004) · 10.10.20.12 ─────────────────┐
                │ GitLab — plateforme/infra : MR (plan en artefact + widget    │
                │ « terraform » de la MR, toutes éditions), apply manuel sur   │
                │ main, réservé aux Maintainers (E26)                          │
                │ plateforme/tofu-modules : vm-debian vX.Y.Z                   │
                └───────────────┬──────────────────────────────▲──────────────┘
                                │ jobs (étiquette shell)        │ source = "git::https://…?ref=vX.Y.Z"
           ┌────────────────────▼──── runner01 (1007) · 10.10.20.15 ───────────┐
           │ tofu plan / apply en CI (E26), Terragrunt (E24), Checkov, Trivy    │
           └──────────┬────────────────────────────┬─────────────────────────────┘
                      │ API :8006 (M03-E15)         │ HTTPS :8333 (même VLAN)
┌─────────────────────┼──── adm01 (1001) · 10.10.10.10 ┼──────────────────────────────────┐
│ ~/src/infra, ~/src/tofu-modules · OpenTofu 1.13 · provider bpg/proxmox ~> 0.115.0         │
│ ~/.config/workbook/ : pve-tofu.env (E03), s3-tofu.env (E11), tofu-chiffrement.pass (E27) │
└───────┬────────────────────────────┬─────────────────────────────────────┬───────────────┘
        │ API HTTPS :8006, TLS vérifié │ HTTPS :8333 (état distant, E11)       │ SSH (E23, Ansible)
        ▼                              ▼                                       ▼
┌──────────────── pve01 ──────────────────────────┐   ┌──── s3-01 (1006) · 10.10.20.14 ────┐
│ jeton wb-tofu@pve!tofu, rôle WBTofu (pool lab)  │   │ SeaweedFS 4.4x, passerelle S3 HTTPS │
│ images dorées : gold + debian13 + current        │   │ compartiment tofu-state (versionné) │
│ envs/lab-m05 : VMs 2050-2059 (vsandbox, DHCP)    │   │ disque de données 100 Go (hdd-bulk) │
│ socle/ : adm01, dns01, git01, runner01 importés, │   │ créée par OpenTofu (E10), configurée│
│          s3-01 créée ; gw01 reste hors IaC (E16) │   │ par le rôle Ansible seaweedfs        │
└──────────────────────────────────────────────────┘   └─────────────────────────────────────┘
```

OpenTofu ne se connecte jamais aux VMs : il parle à l'**API de Proxmox**, qui crée les VMs en clonant l'image dorée et leur passe leur identité par cloud-init. La configuration de l'intérieur des machines reste le travail d'Ansible (module 04) ; E23 montre comment les deux s'enchaînent.

### Flux réseau du module

| Flux | Exercice | État |
|---|---|---|
| `adm01` → `pve01` TCP 8006 (API) | E03 | existant (M00) |
| `adm01` → Internet HTTPS (dépôt APT d'OpenTofu, registre `registry.opentofu.org`, téléchargement des providers) | E02, E03 | existant (tout le lab sort vers Internet, M00) |
| `adm01` → `vsandbox` TCP 22 (contrôle des VMs d'environnement) | E04 | existant (MGMT joint tout le lab) |
| `adm01` → `s3-01` TCP 8333 | E10, E11 | existant (MGMT joint tout le lab) |
| `runner01` → `s3-01` TCP 8333 | E26 | même VLAN (INFRA) : rien à ouvrir sur `gw01` |
| `runner01` → `pve01` TCP 8006 | E26 | ouvert en M03-E15 (`gw01` + IPSet Proxmox `automation`) |

Tout nouveau flux est ouvert au plus juste par le rôle Ansible `pare_feu` (`host_vars/gw01/pare_feu.yml`, M04-E17), par MR, puis reporté dans `docs/socle/matrice-flux.md`.

## Le projet `plateforme/infra`

Arborescence visée en fin de module (chaque exercice indique ce qu'il ajoute) :

```
infra/
├── README.md, CONTRIBUTING.md, .gitignore, .pre-commit-config.yaml, .gitlab-ci.yml   (E02, E20, E26)
├── envs/
│   └── lab-m05/              environnement d'exercices : VMs 2050-2059 (E03 → E08, puis palier 2)
│       ├── versions.tf       required_version, required_providers (E03), backend (E11)
│       ├── providers.tf      provider proxmox, sans aucun secret (E03)
│       ├── variables.tf, locals.tf, outputs.tf, terraform.tfvars   (E06)
│       ├── main.tf, data.tf  ressources et sources de données (E04, E07, E08)
│       └── .terraform.lock.hcl   versions et empreintes exactes des providers (E03, versionné)
├── socle/                    VMs permanentes : s3-01 (E10), import du socle (E16)
├── terragrunt/               factorisation des backends, providers et environnements (E24)
└── .tflint.hcl, .terraform-docs.yml, .checkov.yaml, .trivyignore   (E20, E25)
```

Chaque dossier racine (`envs/lab-m05/`, `socle/`) est une **configuration** OpenTofu autonome, avec son propre état : on lance `tofu` depuis ce dossier.

### Conventions du projet

| Convention | Règle |
|---|---|
| Lancement | Depuis le dossier de la configuration (`cd ~/src/infra/envs/lab-m05`), après avoir chargé les accès : `set -a; . ~/.config/workbook/pve-tofu.env; set +a` (puis `s3-tofu.env` à partir de E11 ; à partir de E27, un seul geste : `. outils/charger-acces.sh`) |
| Versions | `required_version = "~> 1.13.0"` ; provider `bpg/proxmox` `~> 0.115.0` ; `.terraform.lock.hcl` **versionné** |
| Ressource VM | `proxmox_virtual_environment_vm` uniquement ; **jamais** `proxmox_vm` (ressource expérimentale du provider) |
| Nommage | Ressources, variables et sorties en `snake_case` français (`vm_essai`, `cles_ssh_admin`) ; noms de VM conformes à PLAN §4.4 (`m05-…` pour l'environnement du module) |
| Fichiers | `versions.tf`, `providers.tf`, `variables.tf`, `locals.tf`, `main.tf`, `data.tf`, `outputs.tf` ; valeurs non secrètes dans `terraform.tfvars` (versionné) |
| Secrets | Jamais dans le code ni dans `terraform.tfvars` : variables d'environnement (`PROXMOX_VE_*`, `AWS_*`) chargées depuis `~/.config/workbook/`, variables CI protégées et masquées |
| Étiquettes Proxmox | Toujours **déclarées** sur chaque VM : `env-m05` pour l'environnement, `socle` + `role-…` pour le socle (PLAN §4.8) |
| Clones | **Complets** (`full = true`) de l'image dorée `current` ; clones liés réservés aux VMs jetables d'un test automatique (règle PLAN, M03) |
| Brouillons | `~/m05/eXX/` sur `adm01` (non versionnés) : notes, plans enregistrés, essais |

---

## Concepts clés

Une synthèse pour se repérer, pas un cours : les exercices et les liens « Pour aller plus loin » approfondissent.

**Déclaratif.** Un script dit **comment** faire (« clone 9012 en 2050, puis règle la mémoire »). Une configuration OpenTofu dit **ce qui doit exister** (« une VM 2050, 2 Go, clone complet de l'image courante »). OpenTofu compare cette description à ce qui existe et calcule seul les actions : créer, modifier sur place, remplacer, détruire. Retirer une ressource du code demande sa **destruction** : c'est la grande différence avec Ansible, qui ne défait jamais ce qu'il a fait quand on retire une tâche.

**Providers, ressources, sources de données.** OpenTofu ne connaît aucune infrastructure : il délègue à des **providers**, des programmes téléchargés depuis un registre (ici `registry.opentofu.org/bpg/proxmox`) qui traduisent la description en appels d'API. Une **ressource** (`resource`) est un objet que la configuration **gère** (crée, modifie, détruit). Une **source de données** (`data`) est une **lecture** : trouver l'image dorée courante, la place libre d'un stockage, sans rien gérer.

**L'état.** Pour savoir que la ressource `proxmox_virtual_environment_vm.essai` correspond à la VM 2050, OpenTofu tient un **état** : un fichier JSON qui associe chaque adresse du code à un objet réel, avec tous ses attributs. Sans état, pas de mise à jour ni de destruction ciblées ; avec un état faux, OpenTofu prend de mauvaises décisions. L'état contient **tout** ce que le provider a lu, secrets compris : il se protège comme un secret, il se partage (backend S3), il se verrouille (un seul `apply` à la fois), il se sauvegarde et il se chiffre.

**Le cycle plan / apply.** `tofu plan` rafraîchit l'état (lit la réalité), compare au code et affiche les actions prévues ; `tofu apply` exécute un plan. Le plan est la pièce que l'on **relit** : le symbole `-/+` (remplacement) sur une VM signifie qu'un disque va disparaître. En équipe, on enregistre le plan (`-out`) et on applique exactement celui qui a été relu (E26).

**Le graphe.** OpenTofu construit un graphe des dépendances entre ressources (références, `depends_on`) et traite en parallèle ce qui est indépendant. Une référence (`data.x.vms[0].vm_id`) crée une dépendance ; c'est elle qui ordonne les opérations, pas l'ordre des blocs dans les fichiers.

**Modules.** Un dossier de fichiers `.tf` est un module ; la configuration qu'on lance est le module **racine**. Un module réutilisable (`vm-debian`, E13) encapsule une façon de faire (« une VM Debian du socle ») derrière des variables et des sorties ; il se versionne et se consomme par étiquette, comme une bibliothèque.

**Dérive.** Toute modification faite hors d'OpenTofu (un `qm set` en urgence, un réglage dans l'interface) écarte la réalité de l'état et du code. Le prochain plan la révèle, et le prochain apply l'annule, ou recrée la ressource. Détecter la dérive régulièrement (E28) et la ramener dans le code, c'est l'hygiène de base d'une infrastructure déclarée.

**OpenTofu et Terraform.** OpenTofu est né en 2023 du fork de Terraform 1.5, quand HashiCorp est passé à la licence BUSL. Le langage, les commandes et le format d'état sont compatibles pour l'essentiel ; les providers sont les mêmes binaires, servis par un autre registre. Depuis, les deux évoluent chacun de leur côté : certaines nouveautés existent des deux côtés (verrou S3 natif `use_lockfile`, valeurs éphémères — Terraform les a même eues en premier), d'autres sont propres à OpenTofu, comme le chiffrement de l'état côté client, le méta-argument `enabled` ou l'extension `.tofu` (E09). Le workbook utilise OpenTofu ; Terraform n'est cité que pour comparaison.

---

## Faits techniques du module

| Élément | Valeur |
|---|---|
| OpenTofu | 1.13.x, dépôt APT officiel `packages.opentofu.org` (clés vérifiées par empreinte, série épinglée), sur `adm01` (E02) puis `runner01` (E26) |
| Provider Proxmox | `bpg/proxmox` `~> 0.115.0` (encore en 0.x : ruptures possibles entre versions mineures) ; ressource `proxmox_virtual_environment_vm`, sources de données `proxmox_virtual_environment_vms`, `proxmox_datastores` |
| Compte Proxmox (E03) | utilisateur `wb-tofu@pve`, jeton `wb-tofu@pve!tofu` (privilèges séparés, expiration ≤ 1 an), rôle `WBTofu` sur `/pool/lab` ; `PVEDatastoreUser` sur les stockages et `PVESDNUser` sur les VNets utilisés |
| Accès sur `adm01` | `~/.config/workbook/pve-tofu.env` (600) : `PROXMOX_VE_ENDPOINT` (`https://<IP-PVE01>:8006/`), `PROXMOX_VE_API_TOKEN` (`wb-tofu@pve!tofu=<SECRET>`) |
| TLS | vérifié (`insecure = false`) ; autorité de `pve01` dans le magasin du système (`/usr/local/share/ca-certificates/pve01-root-ca.crt`, M03-E02) |
| Image consommée | template doré étiqueté `gold` + `debian13` + `current` (VMID 9010-9029, module 03), **clone complet** |
| VMs d'environnement | 2050-2059, pool `lab`, étiquette `env-m05`, VNet `vsandbox` (DHCP 10.10.99.100-199), stockage `local-nvme` ; détruites en fin de module. Palier 1 : 2050 `m05-essai` (E04), 2051-2053 `m05-app01` à `m05-app03` (E07) |
| `s3-01` (E10) | VMID 1006, 10.10.20.14, VNet `vinfra`, 2 vCPU, 2 Go, disque système 20 Go + données 100 Go sur `hdd-bulk`, étiquettes `socle` + `role-s3` ; SeaweedFS 4.4x, S3 en HTTPS sur le port 8333 (certificat de la CA provisoire) |
| État distant (E11, E12) | `https://s3-01.par1.medisphere.internal:8333`, compartiment `tofu-state` versionné, clés `socle/terraform.tfstate` et `envs/<env>/terraform.tfstate`, verrou natif `use_lockfile = true` ; identifiants dans `~/.config/workbook/s3-tofu.env` (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) |
| Chiffrement de l'état (E27) | phrase secrète dans `~/.config/workbook/tofu-chiffrement.pass` (600) et en variable CI protégée et masquée |
| Projets | `plateforme/infra` (`~/src/infra`), `plateforme/tofu-modules` (`~/src/tofu-modules`, étiquettes `vX.Y.Z` par semantic-release) |
| Pipeline (E26) | plan enregistré par configuration, en artefact, et résumé dans le widget « terraform » de la MR (`artifacts:reports:terraform`, disponible dans GitLab CE) ; apply = job manuel de `main` qui applique ce plan. Les environnements protégés et les approbations de déploiement sont réservés aux éditions payantes : en CE, c'est la protection de `main` qui limite l'apply aux Maintainers |
| Outils de qualité | tflint 0.64, terraform-docs 0.24, Checkov 3.3, Trivy 0.75 (**épinglé par empreinte**), Terragrunt 1.1 |
| Documentation | `plateforme/medisphere` : `docs/socle/iac.md`, ADR-0050 (stockage S3, E30), ADR-0051 (`gw01` hors IaC, E16), runbooks RB-050 (verrou d'état bloqué, E33) et RB-051 (restaurer un état, E46), registre des secrets |
| Brouillons | `~/m05/eXX/` sur `adm01` (non versionnés) |

### Valeurs à adapter

| Valeur | Signification |
|---|---|
| `<NOEUD>` | Nom du nœud Proxmox de `pve01` (son `hostname`) |
| `<IP-PVE01>` | Adresse de `pve01` présente dans son certificat (comme `PVE_API_URL`, M00-E17) |
| `<MOI>` | Ton compte GitLab personnel (M01-E05) |
| `<VMID-CURRENT>` | VMID du template doré Debian 13 qui porte aujourd'hui l'étiquette `current` (il change à chaque publication, M03) |

### Variables de `lab/lab.env`

Rien de nouveau. Les vérifications utilisent `WB_SRC` (elles cherchent `$WB_SRC/infra` et `$WB_SRC/tofu-modules`), `WB_PVE_HOST` (état réel de Proxmox, lu **en root sur `pve01`**, jamais avec ton jeton : une vérification peut ainsi diagnostiquer un jeton en panne), `WB_GITLAB_URL` et `WB_GITLAB_TOKEN_FILE` (projets sur la forge), `WB_DEPOT` (documentation) et `WB_S3_ENDPOINT` (stockage objet, à partir de E10). Quand une vérification lance `tofu`, elle charge **tes** accès (`~/.config/workbook/pve-tofu.env`, puis `s3-tofu.env`, puis à partir de E27 le chiffrement de l'état par ton `outils/charger-acces.sh`) et ne lance que des commandes de lecture : `tofu validate`, `tofu plan` sans enregistrement ni verrou, lecture de l'état.

---

## Règles du module

1. **Aucun `apply` sans plan lu en entier.** On lit chaque ligne marquée `-` ou `-/+` et on sait dire ce qui disparaît. `-auto-approve` est réservé au pipeline (E26), qui applique un plan déjà relu ; il est interdit sur le socle depuis un poste.
2. **Un VMID se vérifie avant usage.** Plage du module : 2050-2059. OpenTofu crée ce que tu déclares : une faute de frappe dans un VMID peut viser une VM existante (la création échoue) ou, pire, une ressource importée (E16). Les variables du projet refusent tout VMID hors plage (E06).
3. **Le socle ne se détruit pas.** Les VMs du socle importées portent `lifecycle { prevent_destroy = true }` ; on ne lance jamais `tofu destroy` dans `socle/`. Un plan qui remplace une VM du socle s'arrête là : on cherche pourquoi (E35).
4. **L'état est un secret, et il ne se modifie pas à la main.** Jamais dans Git, jamais dans un ticket, jamais édité avec un éditeur ou `jq` : seulement par les commandes `tofu state …`, `tofu import` ou les blocs `import`, `moved`, `removed`, **après** une copie de sauvegarde.
5. **Une ressource gérée ne se modifie pas hors d'OpenTofu.** Un `qm set` sur une VM décrite dans `plateforme/infra` est une dérive : il sera annulé au prochain `apply`. Une urgence traitée à la main est reportée dans le code le jour même.
6. **Un seul `apply` à la fois par état.** Tant que l'état est local (avant E11), on n'applique que depuis `adm01`, dans `~/src/infra`. Ensuite, le verrou (E12) le garantit.
7. **Aucun secret dans le code**, ni dans `terraform.tfvars`, ni dans une sortie de pipeline. Une valeur marquée `sensitive` est masquée à l'écran, **pas** dans l'état.
8. **Nettoie derrière toi.** Les VMs 2050-2059 sont jetables : détruis-les par `tofu destroy` (jamais à la main, sinon l'état ment) quand un exercice le demande, et toutes en fin de module.

---

## Préparer `adm01`

OpenTofu s'installe en E02. Vérifie d'abord ce dont le module a besoin :

```
admin@adm01:~$ git --version; jq --version; pre-commit --version
admin@adm01:~$ ssh-add -l
admin@adm01:~$ ls -l /usr/local/share/ca-certificates/pve01-root-ca.crt
admin@adm01:~$ ssh pve01 'qm list | awk "\$1 >= 2050 && \$1 <= 2059"'
admin@adm01:~$ ssh pve01 'for id in $(qm list | awk "\$1 >= 9010 && \$1 <= 9029 {print \$1}"); do echo "$id $(qm config $id | grep -E "^(name|tags):" | tr "\n" " ")"; done'
```

- L'ancre TLS de `pve01` doit être dans le magasin système (M03-E02) : OpenTofu et son provider l'utilisent comme Packer.
- Aucune VM ne doit occuper la plage 2050-2059 : si une de tes VMs s'y trouve, note-le et choisis avec le corrigé de E04 comment adapter (le workbook s'adapte, pas ta VM).
- **Une et une seule** image dorée Debian 13 doit porter l'étiquette `current`. Sinon, règle-le d'abord avec la chaîne du module 03 (`outils/publier-image.sh`) : tout le module en dépend.
- La clé de `~/.ssh/id_ed25519` doit être chargée dans l'agent : cloud-init la déposera sur les VMs, et tu t'y connecteras avec.

---

## Indices, corrigé, vérifications

- Les vérifications se lancent depuis `adm01` : `lab/bin/check 05 <XX>`. Elles lisent Proxmox en root sur `pve01` (`qm config`, `pvesh`), l'intérieur des VMs par l'agent QEMU, les projets sur GitLab avec le jeton des checks, et ta copie de travail `~/src/infra`. Quand elles lancent `tofu plan`, c'est sans verrou, sans enregistrement et sans rien appliquer ; elles attendent souvent un plan **vide** : c'est la preuve que la réalité correspond au code. Comptez 30 secondes à 2 minutes.
- Les vérifications du palier 1 décrivent l'état de `envs/lab-m05` **à la fin de chaque exercice**. Quand l'état part sur `s3-01` (E11), elles ne lisent plus l'état et ne lancent plus de plan dans `envs/lab-m05`, et le disent (la vérification de E11 prend le relais) ; quand l'environnement est détruit (fin de module), leurs contrôles de VMs passent au rouge : c'est attendu.
- Les indices sont progressifs : ouvre-les un par un, seulement quand tu bloques.
- Le corrigé (`corrige/`) donne une solution, le *pourquoi*, les alternatives, les pièges et la vision production. Les fichiers complets sont dans `corrige/fichiers/M05-EXX/infra/` (même arborescence que le projet). Même quand ta vérification est verte, lis « Pièges classiques ».
- Les scripts de panne (`corrige/pannes/`) révèlent les causes : ne les lis pas avant d'avoir résolu. Au palier 4, `lab/bin/break 05 XX --annuler` sert aussi à **clore** une panne que tu as réparée : il ne restaure que ce qui est encore dans l'état cassé, sans écraser ta réparation.

## Ordre conseillé

```
E01 ─ E02 ─ E03 ─ E04 ─ E05 ─ E06 ─ E07 ─ E08 ─ E09 ─ palier 2 : E10 (s3-01) ─ E11 (état distant) …
```

1. **E01** — positionnement, à froid, avant de lire la suite.
2. **E02 → E03** — l'outil, le projet, puis le compte Proxmox et un premier plan qui ne crée rien : rien ne marche sans eux.
3. **E04 → E05** — une première VM, puis tout le cycle de vie : plan, apply, remplacement, destruction, et ce que contient l'état.
4. **E06 → E08** — le langage : variables et validations, boucles, sources de données. Chaque exercice fait évoluer le même environnement `envs/lab-m05`.
5. **E09** — à faire en dernier : il demande d'avoir pratiqué.

Durée indicative du palier 1 : 12 à 16 heures.

## Pour aller plus loin

- Documentation d'OpenTofu 1.13 : <https://opentofu.org/docs/> (langage, CLI, état, backends, chiffrement)
- Provider `bpg/proxmox` : <https://search.opentofu.org/provider/bpg/proxmox/latest> et son dépôt <https://github.com/bpg/terraform-provider-proxmox> (lire le `CHANGELOG.md` avant toute montée de version)
- Proxmox VE, gestion des utilisateurs et des privilèges : <https://pve.proxmox.com/pve-docs/pveum.1.html>
- Le manifeste OpenTofu et l'historique du fork : <https://opentofu.org/manifesto/>
- Kief Morris, *Infrastructure as Code*, 3ᵉ édition (O'Reilly) : les principes, indépendamment de l'outil
