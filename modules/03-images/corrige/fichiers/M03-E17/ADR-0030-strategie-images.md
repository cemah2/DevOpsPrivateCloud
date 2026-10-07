# ADR-0030 — Images dorées minimales et durcies, rôle appliqué au démarrage, reconstruites chaque semaine

- Statut : accepté
- Date : AAAA-MM-JJ
- Décideurs : Claire Morel (responsable infrastructure), Karim Benali (ingénieur plateforme senior)
- Consultés : Sophie Laurent (RSSI), Julien Petit (lead dev MédiAgenda), Nadia Roussel (astreinte)
- Ticket : PLAT-460

## Contexte et problème

Jusqu'au module 02, toutes les VMs de MédiSphère sont des clones de `tpl-debian13`, fait à la
main et complété au premier démarrage par un *vendor-data* qui installe « ce que les miroirs
proposent ce jour-là ». L'auditeur HDS demande ce que contiennent nos systèmes et comment nous
le prouvons ; Julien a besoin d'une famille RHEL pour un éditeur. Le module 03 a construit les
outils (Packer, tests, publication, rotation, CI). Il reste à décider **ce qu'on met dans une
image**, **combien d'images** on maintient, **à quel rythme** on les reconstruit, **comment** on
les distribue et les retire, et ce que les consommateurs (Ansible M04, OpenTofu M05) ont le droit
d'en attendre.

## Facteurs de décision

- Preuve et reproductibilité (HDS, ISO 27001) : contenu connu, code relu, source vérifiée.
- Délai d'exposition aux vulnérabilités : de la publication d'un correctif à son arrivée dans les VMs.
- Temps de mise à disposition d'une VM (création → service) et prévisibilité du premier démarrage.
- Coût de maintenance : nombre d'images × fréquence de build × tests ; une équipe de 4 personnes.
- Dérive : écart entre ce que décrit le code et ce qui tourne.
- Capacité du lab : stockage `local-nvme`, un seul hyperviseur, builds sérialisés.
- Licence et pérennité de l'outillage (Packer en BUSL 1.1).

## Options envisagées

1. **Image « complète » par rôle** (une image par application : `mediagenda-api`, `postgres`…,
   tout est cuit, rien n'est configuré au démarrage).
2. **Image minimale du fournisseur + tout au démarrage** (image *cloud* officielle, cloud-init puis
   Ansible installent et durcissent tout à chaque création).
3. **Image dorée commune, minimale et durcie, par famille d'OS + rôle appliqué au démarrage**
   (cloud-init pour l'identité, Ansible pour le rôle), reconstruite chaque semaine.
4. Option 3 avec un autre outil de construction (`virt-builder`, `mkosi`, `diskimage-builder`)
   à la place de Packer.

## Décision

Option retenue : **3**, avec Packer.

**Contenu d'une image dorée** — ce qui est commun à **toutes** les VMs d'une famille et change
rarement : système à jour à la date du build, agent QEMU, cloud-init, chrony (passerelle du VLAN),
CA MédiSphère, mises à jour de sécurité automatiques, journal persistant, durcissement SEC-450
(`docs/durcissement.md`). **Jamais** : identité (machine-id, clés d'hôte), utilisateur, clé,
secret, adresse, paquet applicatif, configuration propre à un rôle.

**Catalogue** — deux familles : Debian 13 (par défaut) et Rocky Linux 10 (sur demande justifiée :
logiciel certifié RHEL). Une nouvelle famille ou une image par rôle exige un nouvel ADR.

**Construction** — images de base depuis l'ISO officielle (signature vérifiée) à chaque version
intermédiaire de la distribution, à la main ; images dorées **chaque semaine** (pipeline planifié)
et à la demande (correctif critique), par la CI uniquement ; un seul build à la fois.

**Version et publication** — version `AAAAMMJJ-N`, manifeste dans les notes du template et en
artefact CI (conservé 90 jours) ; publication (étiquette `current`) seulement après succès de
`tests/tester-image.sh` ; une seule version `current` par famille.

**Consommation** — les consommateurs sélectionnent `gold` + `<famille>` + `current` au moment de
la **création** et enregistrent le VMID (ou le nom) effectivement utilisé (état OpenTofu, inventaire) :
une VM existante n'est jamais « mise à jour par l'image ». Les VMs durables sont des **clones
complets** ; les clones liés sont réservés aux VMs éphémères (tests, Molecule), détruites dans
l'heure.

**Rétention** — 3 versions non rejetées + `current` par famille (rotation automatique après chaque
publication) ; retrait d'urgence par runbook (RB-037).

### Conséquences

- Positives : contenu prouvable (code, manifeste, tests, journaux CI) ; une VM est utilisable en
  quelques minutes avec un premier démarrage court et prévisible ; une seule image par famille à
  tester et à durcir ; correctifs intégrés chaque semaine sans toucher au code des rôles ; la
  frontière image / Ansible est nette (commun / spécifique).
- Négatives : le rôle applicatif reste à installer au démarrage (temps et dépendance aux dépôts
  de paquets, atténués par un miroir local plus tard) ; une semaine maximum d'écart entre un
  correctif et l'image (compensé par `unattended-upgrades` et le build à la demande) ; un
  hyperviseur et un runner uniques sérialisent tout ; Packer est sous BUSL (usage interne permis).
- Risques suivis : dérive des VMs anciennes (traitée par Ansible et la reconstruction périodique
  des VMs, modules 04-05) ; clones liés non détectables par l'API sur LVM-thin (règle « durables =
  clones complets », vérification `lvs` dans RB-037) ; disponibilité du runner (build manuel depuis
  `adm01` par `outils/construire.sh` en secours).

## Avantages et inconvénients des options

### Option 1 — Image complète par rôle
- Pour : démarrage le plus rapide ; aucune dépendance aux dépôts au démarrage ; immuabilité.
- Contre : une image par rôle et par version d'application → explosion du catalogue (*image
  sprawl*), un build et des tests par changement applicatif ; secrets et configuration propres à un
  environnement tentés d'entrer dans l'image ; adapté aux conteneurs (module 12) plus qu'aux VMs.

### Option 2 — Image du fournisseur + tout au démarrage
- Pour : rien à construire ; toujours la dernière image du fournisseur.
- Contre : contenu non maîtrisé ni prouvable (l'image change sans nous) ; durcissement et mises à
  jour à chaque création (premier démarrage long et variable, échec si un dépôt est indisponible) ;
  c'est la situation actuelle que l'audit reproche.

### Option 3 — Image dorée commune + rôle au démarrage (retenue)
- Pour : voir la décision.
- Contre : deux mécanismes à maintenir (image et Ansible), frontière à tenir dans les revues.

### Option 4 — Autre outil de construction
- Pour : `virt-builder` et `mkosi` sont libres (LGPL/GPL), sans VM ni réseau de build pour
  certains (`mkosi` construit hors VM) ; `diskimage-builder` est l'outil d'OpenStack (module 10).
- Contre : intégration Proxmox moins directe (import de disque à scripter, pas de builder natif) ;
  compétences Packer réutilisables ailleurs (autres hyperviseurs, nuages) ; à réévaluer si la
  licence BUSL ou le plugin Proxmox posaient problème.

## Liens

- `plateforme/images` : `docs/durcissement.md`, `tests/tester-image.sh`, `.gitlab-ci.yml`,
  `outils/rotation-images.sh`.
- `docs/socle/images.md` (catalogue), RB-037 (retrait d'une image), ADR-0010 (organisation des
  dépôts), ADR-0020 (langages des outils).
- Modules suivants : 04 (Ansible, Molecule sur clones liés), 05 (OpenTofu : sélection par
  étiquettes, clones complets), 13 (signature et SBOM pour les images de conteneurs), 26
  (conformité outillée).
