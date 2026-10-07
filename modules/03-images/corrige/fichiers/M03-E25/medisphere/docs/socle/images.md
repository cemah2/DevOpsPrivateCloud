# Catalogue des images MédiSphère

> Document de `plateforme/medisphere` (M03-E25). Source de vérité du **code** : `plateforme/images`.
> Source de vérité de l'**état** : Proxmox (étiquettes et notes des templates). Ce document dit ce
> qui existe, comment le consommer, et qui fait quoi ; il ne remplace pas `pvesh`.
> Décision : ADR-0030. Retrait : RB-030. Durcissement : `plateforme/images` → `docs/durcissement.md`.

## Familles et templates

| VMID | Nom | Type | Construit par | Fréquence | Consommé par |
|---|---|---|---|---|---|
| 9000 | `tpl-debian13` | historique (M00, manuel) | — | gelé | VMs du socle existantes ; retrait après reconstruction du socle (M04-M05) |
| 9001 | `tpl-debian13-base` | base, ISO Debian 13 (preseed) | job manuel `build-base:debian13` | à chaque version intermédiaire de Debian | images dorées Debian |
| 9002 | `tpl-rocky10-base` | base, ISO Rocky 10 (kickstart) | job manuel `build-base:rocky10` | à chaque version mineure de Rocky | images dorées Rocky |
| 9010-9029 | `deb13-gold-AAAAMMJJ-N` | dorée Debian 13 | pipeline planifié `build:debian13` | chaque semaine + à la demande | Ansible/Molecule (M04), OpenTofu (M05) |
| 9030-9049 | `rocky10-gold-AAAAMMJJ-N` | dorée Rocky 10 | pipeline planifié `build:rocky10` | chaque semaine + à la demande | VMs certifiées RHEL (éditeur de facturation) |
| 9090-9099 | — | essais | à la main, supprimés en fin d'essai | — | personne |

Étiquettes : `base` + famille (images de base) ; `gold` + `debian13`|`rocky10` (dorées) ;
`current` sur la **seule** version publiée de chaque famille ; `rejete` sur une version dont les
tests ont échoué (jamais publiée, gardée pour analyse jusqu'à la rotation).

## Consommer une image

- Sélection : `gold` + `<famille>` + `current`, **au moment de la création**. Retenir le VMID ou le
  nom effectivement cloné (état OpenTofu, inventaire) : la version `current` change chaque semaine.
- VM durable : **clone complet** sur `local-nvme`. Clone lié : VMs éphémères seulement (tests,
  Molecule), détruites dans l'heure (sinon la rotation ne peut pas retirer le template).
- À fournir au clonage : nom, VNet, `ipconfig0`, `ciuser` (`admin`), `sshkeys`, `ciupgrade 0`
  (l'image est à jour à la semaine près ; `unattended-upgrades` / `dnf-automatic` font le reste).
  Résolveur et domaine : hérités du template (10.10.20.10, `par1.medisphere.internal`).
- Rocky Linux 10 : CPU `x86-64-v3` ou `host` (hérité du template : ne pas l'écraser), contrôleur
  `virtio-scsi-single`.
- Requête de référence (root sur `pve01`) :
  ```
  root@pve01:~# pvesh get /cluster/resources --type vm --output-format json \
    | jq -r '.[] | select(.template == 1) | select((.tags // "") | split(";") | (index("gold") and index("debian13") and index("current"))) | "\(.vmid) \(.name)"'
  ```

## Contenu (v1)

| | Debian 13 | Rocky Linux 10 |
|---|---|---|
| Système | à jour à la date du build | à jour à la date du build |
| Agents | `qemu-guest-agent`, `cloud-init` (NoCloud) | idem |
| Temps | chrony sur la passerelle du VLAN (`ms-ntp-passerelle`) | idem (`chronyd`) |
| Confiance | CA provisoire MédiSphère (M01 ; racine step-ca en M06) | idem (`ca-trust`) |
| Mises à jour | `unattended-upgrades`, sécurité seulement | `dnf-automatic`, sécurité seulement |
| Accès | SSH par clé, pas de root, pas de mot de passe ; comptes injectés au clonage | idem |
| Durcissement | SEC-450 (`durcir.sh`) | SEC-450 (`durcir.sh`) + SELinux *enforcing* |
| Journal | persistant, 200 Mo max. | idem |

Le détail exact d'une version est dans les **notes** de son template (commit, Packer, plugin,
source, paquets) et dans l'artefact `manifests/` du pipeline qui l'a construite (90 jours).

## Cycle de vie

1. MR sur `plateforme/images` → `packer validate` et contrôles de qualité.
2. Fusion, puis pipeline planifié (lundi matin) ou manuel : build → `tests/tester-image.sh` →
   `outils/publier-image.sh` (rejoue le test, pose `current`) → `outils/rotation-images.sh`.
3. Rétention : 3 versions non rejetées + `current` par famille ; retrait d'urgence : RB-030.

## Responsabilités

| Qui | Quoi |
|---|---|
| Équipe Plateforme (Karim Benali, référent) | code, pipeline, publication, rotation, ce document |
| Sophie Laurent (RSSI) | référentiel de durcissement, revue des exceptions, demandes de retrait d'urgence |
| Nadia Roussel (astreinte) | RB-030, alertes du pipeline planifié |
| Consommateurs (M04, M05, équipes) | sélection par étiquettes, clones complets pour le durable |

## Registre des versions publiées

| Date | Famille | Version | VMID | Commit | Pipeline | Remarque |
|---|---|---|---|---|---|---|
| AAAA-MM-JJ | debian13 | AAAAMMJJ-N | 90xx | `<COMMIT>` | `#<ID>` | première publication par la CI |
| AAAA-MM-JJ | rocky10 | AAAAMMJJ-N | 90xx | `<COMMIT>` | `#<ID>` | première image dorée Rocky |
