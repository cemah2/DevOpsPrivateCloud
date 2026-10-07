# Infrastructure as code du socle MédiSphère

> Modèle de corrigé (M05-E46). Remplace les valeurs entre chevrons, supprime ce qui ne correspond pas à tes choix, et **justifie** chaque écart dans la section 9. Aucune valeur secrète dans ce document : seulement des emplacements.

## 1. En une page

- L'infrastructure du socle et des environnements est décrite dans `plateforme/infra` (OpenTofu 1.13, provider `bpg/proxmox` `~> 0.115.0`), avec des modules versionnés de `plateforme/tofu-modules` (`?ref=vX.Y.Z`).
- Toute création ou modification d'une VM passe par une MR : plan visible dans la MR, revue, fusion, **apply manuel et protégé** du plan sauvegardé, sur `main`.
- L'état vit sur `s3-01` (SeaweedFS, `https://s3-01.par1.medisphere.internal:8333`, compartiment `tofu-state`) : verrouillé (`use_lockfile`), chiffré (bloc `encryption`), versionné, sauvegardé hors de `s3-01`.
- La dérive est détectée chaque nuit ; un écart ouvre un ticket.
- Ce qui n'est **pas** en code est listé en section 8.

## 2. Projets et configurations

| Configuration | Clé d'état | Contenu | Qui applique |
|---|---|---|---|
| `socle/` | `socle/terraform.tfstate` | VMs permanentes : `adm01` (1001), `dns01` (1002), `git01` (1004), `s3-01` (1006), `runner01` (1007) | job `apply` protégé, `resource_group` `infra-socle` |
| `envs/lab-m05/` | `envs/lab-m05/terraform.tfstate` | VMs d'environnement 2050-2059 (vides en fin de module) | job `apply` protégé ou `adm01` pour les essais |
| `terragrunt/` | (mêmes clés, via `root.hcl`) | <si retenu : factorisation des backends et providers, M05-E24> | — |

Rayon d'impact : un état = un verrou = un périmètre. Les VMs jetables ne partagent jamais l'état du socle.

`gw01` (1000) : <hors IaC / importé en lecture seule> — décision : <ADR ou paragraphe>, raison : cœur réseau construit à la main au module 00, sa recréation couperait tout le lab, sa configuration est gérée par Ansible (rôle `pare_feu`).

## 3. Modules (`plateforme/tofu-modules`)

| Module | Rôle | Version consommée | Sorties |
|---|---|---|---|
| `vm-debian` | VM Debian du socle ou d'environnement : clone **complet** de l'image `gold`+`debian13`+`current`, cloud-init minimal, étiquettes | `v<X.Y.Z>` | `vmid`, `nom`, `ipv4` |

Publication par semantic-release (étiquettes protégées) ; mise à jour par MR dans `plateforme/infra`, plan relu ; README généré par terraform-docs.

## 4. Chaîne de livraison

| Étape | Job | Quand | Garde-fous |
|---|---|---|---|
| Qualité | `fmt`, `validate`, `tflint`, `terraform-docs`, pre-commit | MR | bloquant |
| Sécurité | `checkov`, `trivy` (image **épinglée par empreinte**) | MR | exceptions justifiées dans `.checkov.yaml` / `.trivyignore` |
| Plan | `plan:socle`, `plan:envs` | MR et `main` | plan chiffré en artefact, résumé en commentaire de MR ; échec si destruction d'une VM 1000-1099 |
| Apply | `apply:socle`, `apply:envs` | `main`, manuel | environnement protégé, `resource_group`, applique **le plan sauvegardé** du pipeline, `interruptible: false` |
| Dérive | `derive:socle` | planifié chaque nuit | `plan -detailed-exitcode` : 2 = écart, alerte et ticket |

## 5. L'état

| Protection | Mise en œuvre | Vérification |
|---|---|---|
| Verrou | `use_lockfile = true` (objet `<clé>.tflock`, écriture conditionnelle) | script `outils/s3-tester-ecriture-conditionnelle.sh` après chaque mise à jour de SeaweedFS |
| Chiffrement | bloc `encryption` : `pbkdf2` + `aes_gcm`, `state` et `plan`, phrase dans `~/.config/workbook/tofu-chiffrement.pass` et en variable CI protégée et masquée | `aws s3 cp s3://tofu-state/socle/terraform.tfstate - \| jq 'keys'` ne montre que l'enveloppe |
| Versionnage | compartiment versionné | `aws s3api get-bucket-versioning --bucket tofu-state` |
| Sauvegarde | <M05-E29 : copie quotidienne hors de `s3-01`, vers …> ; disque de données de `s3-01` dans la sauvegarde PBS `lab-nuit` | restauration testée le <date> par <qui> |
| Droits | identité S3 `tofu-etat` limitée à `tofu-state` ; `admin-s3` réservée au bris de glace | revue trimestrielle |

Restauration : **RB-051**. Verrou bloqué : **RB-050**. Rotation de la phrase : nouvelle méthode + `fallback`, réécriture des états, retrait du `fallback` (procédure dans le registre des secrets).

## 6. Import et refactoring

- L'existant entre par des blocs `import {}` relus en MR (M05-E16) ; un import n'est terminé que lorsque le plan qui suit est **vide**.
- Les VMs du socle portent `prevent_destroy = true` **et** la protection Proxmox (`protection = true`).
- `ignore_changes` : chaque attribut ignoré est commenté (pourquoi, et ce qui le surveille à la place). Exemple : `clone` (l'image `current` change chaque semaine ; une VM passe à une nouvelle image par `tofu apply -replace` décidé).
- Renommages et déplacements : blocs `moved` ; sortie de gestion sans destruction : blocs `removed` (`lifecycle { destroy = false }`). Les commandes `tofu state mv/rm`, `taint` sont réservées aux réparations, après copie de l'état.

## 7. Dérive

Plan planifié chaque nuit sur `socle` (et sur les environnements actifs). Un écart est : soit **défait** (la réalité revient au code par l'apply), soit **adopté** (le code est modifié par MR). `tofu apply -refresh-only` n'adopte rien : il ne fait que recopier la réalité dans l'état. Les VMs étiquetées `socle` ou `env-*` qui n'appartiennent à aucun état sont listées par <script / job>.

## 8. Ce qui n'est pas (encore) en code

| Élément | Pourquoi | Quand |
|---|---|---|
| `gw01` | décision section 2 | réexaminé au module 07 (HA du routage) |
| Comptes, rôles et ACL Proxmox (`wb-tofu`…) | créés par script versionné (M05-E03), pas par OpenTofu | module 24 (identités) |
| Enregistrements DNS | `dnsmasq` géré par Ansible | module 06 : PowerDNS piloté par provider |
| Adresses IP | variables de `terraform.tfvars` | module 06 : NetBox source de vérité |
| Certificat de `s3-01` | CA provisoire, posé par Ansible | module 06 : step-ca, ACME |
| Images dorées | Packer (module 03) | — (hors périmètre d'OpenTofu) |

## 9. Conventions de l'équipe (leçons du palier 4)

- Un plan se lance sur une copie **propre** (`git status --ignored` sans surcharge ni `*.auto.tfvars` local).
- Aucun `tofu apply` « pour voir » ; aucun `-lock=false` sur une commande qui écrit ; aucun `state push -force`.
- Avant un `force-unlock` : preuve que le détenteur n'existe plus, message dans `#plateforme` (RB-050).
- Une copie de l'état en clair (`state pull`) : `umask 077`, hors dépôt, `shred -u` après usage.
- Les droits de `wb-tofu` ne s'élargissent pas pour débloquer un apply : on ajoute le privilège manquant, sur le bon chemin, par le script versionné.
- Écarts par rapport aux énoncés : <liste justifiée>.
