# Module 03 — Introduction : images dorées

## Le template que personne ne sait refaire

Mardi, 9 h 10. Le comité de sécurité de la veille a laissé des traces.

> **De** : Sophie Laurent — RSSI
> **À** : toi
> **Cc** : Claire Morel, Karim Benali, Julien Petit
> **Objet** : Ce qui tourne sur nos VMs — j'ai besoin de preuves
>
> Bonjour,
>
> Hier, l'auditeur HDS m'a posé une question simple : « Que contient le système de base de vos machines virtuelles, et comment le prouvez-vous ? ». Je n'ai pas su répondre. Toutes nos VMs sont des clones de `tpl-debian13`, fabriqué à la main au module 00 à partir d'une image téléchargée, complété au premier démarrage par un *vendor-data* qui installe ce qu'il trouve sur les miroirs ce jour-là. Personne ne sait le reconstruire à l'identique, personne ne sait dire quand il a été mis à jour pour la dernière fois.
>
> Je veux des **images dorées** :
> - construites par du **code** relu en MR, à partir de sources dont on a **vérifié la signature** ;
> - **préparées** pour le clonage (chaque clone a sa propre identité) et **durcies** selon nos règles ;
> - **testées** automatiquement avant d'être utilisées, **versionnées**, et dont on peut lire le contenu sur le template lui-même ;
> - reconstruites régulièrement, et retirées proprement quand elles sont trop vieilles.
>
> Julien a aussi un besoin : un éditeur de logiciel de facturation n'est certifié que sur la famille Red Hat. Il nous faut une image **Rocky Linux 10** au même niveau d'exigence.
>
> Karim relira le code, je relirai les droits et les secrets. Claire veut le catalogue d'images en place avant le chantier Ansible (module 04) : Ansible et OpenTofu consommeront ces images, et rien d'autre.
>
> Sophie

---

## Ce que tu construis dans ce module

À la fin du module 03 :

- **Packer** est installé sur `adm01` (puis sur `runner01` en M03-E15), avec un compte Proxmox dédié `wb-packer@pve` et un jeton à privilèges minimaux ;
- le projet **`plateforme/images`** (forge `git01`) contient le code de toutes les images, relu en MR, contrôlé par pre-commit et la CI ;
- deux **images de base** construites depuis l'ISO officielle par une installation automatisée : `tpl-debian13-base` (9001, *preseed*) et `tpl-rocky10-base` (9002, *kickstart*) ;
- des **images dorées** versionnées, construites par clonage des images de base : `deb13-gold-AAAAMMJJ-N` (9010-9029) et `rocky10-gold-AAAAMMJJ-N` (9030-9049), avec leur manifeste dans le champ « notes » ;
- un **test automatique** et une **publication** qui pose l'étiquette `current` sur la seule version validée de chaque famille ;
- un **pipeline** qui reconstruit, teste et publie chaque semaine, et une **rotation** qui retire les vieilles versions ;
- la maîtrise de **cloud-init** : étapes, modules, fréquences, *vendor-data*, configuration réseau, diagnostic.

## Architecture du module

```
                    ┌──────────────── git01 (1004) · 10.10.20.12 ─────────────────┐
                    │ GitLab — plateforme/images : code des images, MR, CI (E15)   │
                    └───────────────────────────────┬─────────────────────────────┘
                                                    │ clone / push (SSH)
┌────────────────────────── adm01 (1001) · 10.10.10.10 ── VLAN 10 MGMT ─────────────────────┐
│ ~/src/images  · Packer 1.16 + plugin hashicorp/proxmox 1.2.x                              │
│ ~/.config/workbook/pve-packer.env  (jeton wb-packer@pve!packer, 600)                       │
│ serveur HTTP de Packer : 10.10.10.10, TCP 8100-8199 (preseed, kickstart)                  │
└──────┬─────────────────────────────────────────────────────▲────────────────────────────┘
       │ ① API Proxmox HTTPS :8006, TLS vérifié                │ ③ l'installeur télécharge
       │   (créer, démarrer, frapper au clavier, convertir)    │    preseed / kickstart
       ▼                                                       │    (vsandbox → adm01, via gw01)
┌──────────────────────────── pve01 (Proxmox VE 9) ─────────────┴──────────────────────────┐
│  hdd-bulk : ISO vérifiées (deposer-iso.sh)        local-nvme : disques, lecteurs cloud-init │
│                                                                                            │
│  VM de construction (VMID du template visé) ── VNet vsandbox (VLAN 99, DHCP de dns01) ─────┤
│     ② démarre sur l'ISO, boot_command tapé par l'API ; ④ Packer s'y connecte en SSH        │
│        (adresse lue par l'agent QEMU) et lance les provisioners ; ⑤ arrêt, conversion      │
│                                                                                            │
│  9000 tpl-debian13 (M00, manuel)    9001 tpl-debian13-base    9002 tpl-rocky10-base         │
│  9010-9029 deb13-gold-AAAAMMJJ-N    9030-9049 rocky10-gold-…  9090-9099 essais              │
│  2030-2039 VMs de test (env-m03, détruites après usage)                                    │
└────────────────────────────────────────────────────────────────────────────────────────────┘
            consommateurs : Ansible/Molecule (M04), OpenTofu (M05) — étiquettes gold + debian13 + current
```

Flux réseau à ouvrir dans ce module (ciblés, commentés, reportés dans la matrice des flux) :

| Flux | Exercice | Pourquoi |
|---|---|---|
| `vsandbox` → `adm01` TCP 8100-8199 | E05 | l'installeur lit le *preseed* / *kickstart* servi par Packer |
| `vsandbox` → `runner01` TCP 8100-8199, `runner01` → `vsandbox` TCP 22, `runner01` → `pve01` TCP 8006 (`gw01` **et** pare-feu Proxmox, IPSet `automation`) | E15 | construction par la CI |

`adm01` (MGMT) joint déjà `pve01` (8006) et tout le lab (SSH vers `vsandbox`) depuis le module 00.

## Concepts clés

Une synthèse pour se repérer : les exercices et les liens « Pour aller plus loin » approfondissent.

**Image dorée ou configuration au démarrage.** Une *image dorée* contient déjà tout ce qui est commun à toutes les machines (paquets, durcissement, agents, autorités de confiance) : un clone est prêt en une minute et identique à ses frères. La configuration au démarrage (cloud-init, puis Ansible) apporte ce qui est **propre à chaque instance** : nom, adresse, utilisateurs, clés, secrets, rôle applicatif. La frontière se discute (E01, ADR en E17) ; ce qui est sûr, c'est qu'un **secret** ou une **identité** n'est jamais cuit dans une image.

**Packer.** Outil de HashiCorp qui construit des images à partir d'un fichier HCL : un *builder* crée une machine (ici une VM Proxmox), des *provisioners* la configurent (scripts, fichiers), puis le builder la convertit en template, et des *post-processors* traitent le résultat (manifeste, finalisation). Les builders Proxmox sont dans un **plugin** (`github.com/hashicorp/proxmox`), déclaré dans `required_plugins` et installé par `packer init`. Packer est distribué sous licence **BUSL 1.1** depuis la 1.10 : usage interne autorisé, pas de *fork* communautaire équivalent à OpenTofu.

**Deux builders.** `proxmox-iso` crée une VM vide, démarre l'ISO d'installation et **tape au clavier** (via l'API `sendkey`) une ligne de démarrage qui lance une installation automatisée : *preseed* pour Debian, *kickstart* pour Rocky Linux. Le fichier de réponses est servi par un petit serveur HTTP que Packer ouvre sur la machine de build. `proxmox-clone` part d'un template existant : plus rapide, il sert aux images dorées construites au-dessus d'une image de base.

**cloud-init.** Programme qui configure une instance au démarrage à partir d'une **source de données** (*datasource*). Proxmox fournit la source *NoCloud* : un petit lecteur CD (`cloudinit`) contenant `meta-data` (l'identifiant d'instance), `user-data` (utilisateur, clés), `network-config` et éventuellement `vendor-data`. cloud-init travaille en étapes (détection, `local`, `network`, `config`, `final`), lance des modules à une **fréquence** donnée (à chaque démarrage, une fois par instance, une fois pour toutes) et décide qu'il s'agit d'une « nouvelle instance » quand l'identifiant d'instance change.

**Préparer au clonage.** Une VM qui a démarré a acquis une identité : `machine-id`, clés d'hôte SSH, état de cloud-init, baux DHCP, journaux, et ici un compte de construction. Si on en fait un template sans les retirer, **tous** les clones les partagent : collisions DHCP, usurpation SSH indétectable, journaux confondus. Cette préparation est la dernière étape de chaque build.

**Versionner, tester, publier.** Une image a une version (`AAAAMMJJ-N`), un manifeste (source, commit, outils, paquets) et un statut. On ne la donne aux consommateurs qu'après un test automatique ; l'étiquette `current` désigne la seule version publiée d'une famille. Les consommateurs ne connaissent ni le VMID ni le nom : ils demandent `gold` + `debian13` + `current`.

**Chaîne de confiance.** Ce qui entre dans une image doit être vérifiable : ISO dont la **signature** du fichier de sommes est vérifiée, dépôts de paquets signés, outils de build installés depuis un dépôt signé, code relu, construction par la CI. L'image n'est jamais plus sûre que le maillon le plus faible de cette chaîne (E18).

## Le projet `plateforme/images`

Arborescence visée en fin de module (chaque exercice indique ce qu'il ajoute) :

```
images/
├── .gitlab-ci.yml, .pre-commit-config.yaml, … configuration standard de la plateforme (E02)
├── debian13-base/    build.pkr.hcl, variables.pkr.hcl, http/preseed.cfg, http/late-command.sh  (E05)
├── rocky10-base/     build.pkr.hcl, variables.pkr.hcl, http/ks.cfg                             (E06)
├── debian13-gold/    build.pkr.hcl, variables.pkr.hcl   (clone de 9001)                       (E09)
├── rocky10-gold/     build.pkr.hcl, variables.pkr.hcl   (clone de 9002)                       (E25)
├── scripts/          preparer-clonage.sh (E07), gold-debian13.sh (E09), manifeste-paquets.sh (E10), durcir.sh (E13)
├── fichiers/         déposés dans les images : CA provisoire, sshd_config.d/, chrony, journald, apt (E09)
├── vars/lab.pkrvars.hcl   valeurs NON secrètes de l'environnement (pool, stockages, VNet, ports)
├── docs/durcissement.md   mesures de durcissement, références, exceptions (E13)
├── tests/tester-image.sh  test automatique d'une image (E10, complété en E14)
├── outils/           deposer-iso.sh (E05), construire.sh (E08), publier-image.sh, version-image.sh (E10), rotation-images.sh (E16)
└── manifests/        journaux et manifestes de build (artefacts, ignorés par git)
```

## Faits techniques du module

| Élément | Valeur |
|---|---|
| Packer | 1.16.x, dépôt APT HashiCorp (suite `trixie`) ; plugin `github.com/hashicorp/proxmox` `~> 1.2.4` |
| Compte Proxmox | utilisateur `wb-packer@pve`, jeton `wb-packer@pve!packer` (séparation des privilèges), rôle `WBPacker` |
| Accès sur `adm01` | `~/.config/workbook/pve-packer.env` (600) : `PKR_VAR_proxmox_url`, `PKR_VAR_proxmox_username`, `PKR_VAR_proxmox_token`, `PKR_VAR_proxmox_node` |
| TLS | `insecure_skip_tls_verify = false` ; autorité de `pve01` approuvée par le magasin système de la machine de build |
| Réseau de build | VNet `vsandbox` (DHCP de `dns01`, 10.10.99.100-199) ; serveur HTTP de Packer sur `adm01` 10.10.10.10, ports 8100-8199 |
| ISO | sur `hdd-bulk` (contenu `iso`), signature et somme vérifiées avant dépôt |
| Templates | 9001 `tpl-debian13-base`, 9002 `tpl-rocky10-base`, 9010-9029 `deb13-gold-AAAAMMJJ-N`, 9030-9049 `rocky10-gold-AAAAMMJJ-N`, 9090-9099 essais ; disques sur `local-nvme` |
| Matériel | `virtio-scsi-single`, agent QEMU, carte `virtio`, port série `serial0` ; CPU `x86-64-v2-AES` (Debian), **`x86-64-v3` minimum pour Rocky Linux 10** |
| Étiquettes | `base` + famille sur les images de base ; `gold` + `debian13`/`rocky10` (+ `current` sur la version publiée) sur les images dorées |
| VMs de test | 2030-2039, pool `lab`, étiquette `env-m03`, VNet `vsandbox` ; **toujours détruites après usage** (2030-2033 : tests automatiques, à partir de E10) |
| Brouillons | `~/m03/eXX/` sur `adm01` (non versionnés) |

### Valeurs à adapter

| Valeur | Signification |
|---|---|
| `<IP-PVE01>` | Adresse de `pve01` présente dans son certificat (comme `PVE_API_URL`, M00-E17) |
| `<NOEUD>` | Nom du nœud Proxmox de `pve01` |
| `<MOI>` | Ton compte GitLab personnel (M01-E05) |
| `<VMID-LIBRE>` | VMID libre de la plage indiquée par l'exercice (vérifie avant : `qm list`, `pvesh get /cluster/nextid --vmid N`) |

### Variables de `lab/lab.env`

Rien de nouveau : les vérifications utilisent `WB_PVE_HOST` (alias `pve01`), `WB_SRC` (elles cherchent `$WB_SRC/images`), `WB_DEPOT`, `WB_GITLAB_URL` et `WB_GITLAB_TOKEN_FILE`, et les noms de stockage `WB_STORAGE_*` si tu as dû garder d'autres noms. Elles lisent l'état de Proxmox **en root sur `pve01`**, jamais avec ton jeton Packer : une vérification peut ainsi diagnostiquer un jeton en panne.

---

## Règles du module

1. **Un VMID se vérifie avant usage.** Plages : 9001-9099 pour les templates, 2030-2039 pour les VMs de test. `packer build -force` **supprime la VM qui porte le `vm_id` indiqué**, quelle qu'elle soit : une faute de frappe peut détruire autre chose qu'un template. Les fichiers du projet refusent tout `vm_id` hors plage (E08).
2. **Les templates du socle ne se modifient pas à la main.** Un template se reconstruit par le code ; on ne le démarre jamais, on ne le « répare » pas dans l'interface.
3. **Aucun secret dans une image, dans le dépôt ou dans les journaux.** Ni jeton, ni mot de passe, ni clé privée. Le compte de construction est jetable et supprimé à la fin du build.
4. **Le template `tpl-debian13` (9000) est conservé** : le socle actuel en est issu. Il ne sera retiré qu'une fois toutes les VMs du socle reconstruites depuis une image dorée (module 04/05).
5. **Nettoie derrière toi** : VMs de test détruites, templates d'essai (9090-9099) supprimés à la fin de chaque exercice.

---

## Indices, corrigé, vérifications

- Les vérifications se lancent depuis `adm01` : `lab/bin/check 03 <XX>`. Elles lisent la configuration Proxmox (`qm config`, `pvesh`) en SSH root sur `pve01`, l'intérieur des VMs par l'agent QEMU (`qm guest exec`), le projet sur GitLab avec le jeton des checks et ta copie de travail `~/src/images`. Elles ne construisent rien et ne modifient rien.
- Les indices sont progressifs : ouvre-les un par un, seulement quand tu bloques.
- Le corrigé (`corrige/`) donne une solution, le *pourquoi*, les alternatives, les pièges et la vision production. Les fichiers complets du projet sont dans `corrige/fichiers/M03-EXX/images/`. Même quand ta vérification est verte, lis « Pièges classiques ».
- Un build Packer dure de 5 à 30 minutes : lis la sortie au fil de l'eau, et garde la console de la VM ouverte (interface web, onglet *Console*) pendant les installations depuis l'ISO.

## Ordre conseillé

```
E01 ─ E02 ─ E03 ─ E04 ─ E05 ─┬─ E06 (Rocky) ──────────────┐
                             └─ E07 ─ E08 ─ E09 ─ E10 ─ E11 ─ E12 ─ palier 3 (E13…)
```

1. **E01** — à froid, avant de lire la suite.
2. **E02 → E03** — l'outil, le compte, le projet, puis un premier build simple pour voir la mécanique.
3. **E04** — cloud-init en profondeur : tout le reste du module en dépend.
4. **E05** — l'installation automatisée depuis l'ISO : l'exercice le plus long du palier 1.
5. **E06 à E12** — dans l'ordre ; E06 (Rocky) peut se faire en parallèle de E07-E08 si un build tourne pendant que tu écris l'autre.

Durée indicative des paliers 1 et 2 : 15 à 20 heures, dont beaucoup d'attente de builds : prévois de lire la documentation pendant ce temps.

## Pour aller plus loin

- Documentation de Packer : <https://developer.hashicorp.com/packer/docs>
- Plugin Proxmox (builders `proxmox-iso` et `proxmox-clone`) : <https://developer.hashicorp.com/packer/integrations/hashicorp/proxmox>
- Guide d'installation Debian 13, annexe B (*preseed*) : <https://www.debian.org/releases/trixie/amd64/apb.en.html>
- RHEL 10, installation automatisée par *kickstart* : <https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/automatically_installing_rhel/>
- cloud-init 25.1 : <https://cloudinit.readthedocs.io/en/25.1/>
- Proxmox VE, cloud-init : <https://pve.proxmox.com/wiki/Cloud-Init_Support>
