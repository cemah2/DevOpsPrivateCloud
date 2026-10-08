# AVANCEMENT.md — État de production

Statuts : `à faire` · `rédigé` · `harmonisé` · `relu` · `validé apprenant` (testé sur le vrai lab)

## Fondations

| Élément | Statut | Remarques |
|---|---|---|
| PLAN.md | rédigé | Versions des outils hors bloc A à figer au démarrage de chaque bloc |
| CONVENTIONS.md | rédigé | À ajuster après les retours sur le module 00 |
| lab/ (check, break, check-lib, lab.env.example) | rédigé | Bloc A : `lab/lib/pannes-lib.sh` (pannes des modules 01+), fonctions `gitlab_api`/`netbox_api`, variables du bloc A dans `lab.env.example` |
| annexes/ | rédigé (blocs A et B) | `versions-bloc-A.md`, `versions-bloc-B.md`, `prerequis.md` (graphe 00-29/F1-F7, état laissé par chaque module des blocs A et B), `certifications.md` (LFCS, RHCSA, RHCE, Terraform Associate, GitLab, COA, CCNA, grilles Ceph et Proxmox ; CKA et suivants à compléter), `glossaire.md` (380 termes) : à compléter à la fin de chaque bloc |

## Modules

| # | Module | Statut | Exercices | Remarques |
|---|---|---|---|---|
| 00 | Positionnement et montage du lab | relu | 50 | Relecture indépendante complète (§11). Restent à confirmer sur matériel réel : `GET /pools/{poolid}` déprécié (check-E17, E50), statut du stockage PBS avec ACL limitée au namespace (E22), format de la paperkey (E36), résolveur de l'image genericcloud Debian 13. Points « à vérifier sur ta version » signalés dans les corrigés |
| 01 | Git et workflow professionnel | relu | 46 + mini-projet | 4 rédacteurs, harmonisation, relecture indépendante en 2 parties (~50 vérifications sur la doc officielle et le code source de GitLab). À confirmer sur le lab : conservation d'un `gitlab.rb` pré-installation, titre des processus Puma, lecture de `application/settings` en `read_api`, libellés exacts des refus (hooks, ref cachée), effet de *Remove blobs* sur les diffs de MR, valeurs `unhealthy_*` du runner, `python3` sur `pbs01`, suppression différée des projets |
| 02 | Scripting d'automatisation | relu | 45 + mini-projet | 4 rédacteurs (le 4e relancé après interruption), harmonisation, relecture indépendante en 2 parties (~60 vérifications, projet de référence exécuté : 148 bats, 110+ pytest, ruff/ShellCheck/shfmt propres). À confirmer sur le lab : droits de `/run/lock`, visibilité des nœuds sans `Sys.Audit`, `uv --check-url` et `uv auth` avec le registre PyPI de GitLab, ACL PBS limitée au namespace, messages 401 de pveproxy |
| 03 | Images dorées | relu | 24 + mini-projet | 2 rédacteurs, harmonisation, relecture indépendante (~35 vérifications ; plugin Packer proxmox 1.2.4 compilé et `packer validate` complet sur tous les HCL, kickstart validé par `ksvalidator RHEL10`, sommes d'ISO et empreintes GPG vérifiées). À confirmer sur le lab : `boot_command` GRUB de Rocky 10.2, `qm set` cloud-init sur template, `user-tag-access`, format de dnf-automatic, régénération des clés sshd sur Debian 13 |
| 04 | Gestion de configuration (Ansible) | relu | 45 + mini-projet | 4 rédacteurs, harmonisation, relecture indépendante en 2 parties (~80 vérifications ; ansible-core 2.21.5/2.19, ansible-lint 26.9 profil production, Molecule 26.9 et Semaphore 2.19 exécutés, pytest de la collection et du module maison verts, filet anti-coupure du pare-feu testé). À confirmer sur le lab : ACL Proxmox de `wb-ansible`, enregistrement réel du runner, `qm terminal` sur `gw01`, délai `logger --tcp` (E41 v4), API `/project/users` de Semaphore |
| 05 | Infrastructure as Code (OpenTofu) | relu | 45 + mini-projet | 4 rédacteurs, harmonisation, relecture indépendante en 2 parties (~65 vérifications ; OpenTofu 1.13.1, Terragrunt 1.1.6, SeaweedFS 4.45/4.48 et AWS CLI exécutés : `validate`, `tofu test` 8/8, verrou `use_lockfile` et 412 `If-None-Match` constatés, chiffrement de l'état éprouvé ; règle sudo de `wb-tofu` corrigée et éprouvée). À confirmer sur le lab : `ciupgrade` avec un jeton non-root, attente de l'agent sur un clone, message de PVE 9 pour un VMID existant, affichage du rapport `terraform` en MR |
| 06 | Services socle | relu | 45 + mini-projet | 4 rédacteurs, harmonisation, relecture indépendante en 2 parties (~50 vérifications ; Kea 3.0.4, PowerDNS 5.0.7/Recursor 5.4.7, step-ca 0.30.2 et NetBox 4.6 exécutés, 138 pytest, ansible-lint production sur tous les rôles). À confirmer sur le lab : formats de sortie de `pdnsutil` 5.0, coexistence ancre `par1` / NTA `medisphere.internal`, authentification de l'écouteur HA de Kea, écrans NetBox de création des jetons, relecture à chaud des certificats NTS par chrony |
| 07 | Réseau datacenter et haute disponibilité | relu | 45 + mini-projet | 4 rédacteurs, harmonisation, relecture indépendante en 2 parties (~87 vérifications ; FRR 10.7.1 en espaces de noms, HAProxy 3.2.25 `-c`, keepalived 2.2.8/2.3.4 `-t`, `vtysh --dryrun`, `nft -c`, conntrackd 1.4.8 ; migration VRRP de la bordure refaite pour ne jamais faire tomber les VIP déjà migrées). À confirmer sur le lab : nommage `eth*` de la maquette et renommage de `gw02`, option `mtu` d'une zone SDN VLAN, FDB de `vmbr1`, TCP-MD5 sur voisins *unnumbered*, `retry-on`+`redispatch` du défi ACME, `SDN.Use` sur `localnetwork`, script `STOP` de keepalived sous systemd |
| 08 | Stockage distribué (Ceph) | relu | 45 + mini-projet | 4 rédacteurs, harmonisation, relecture indépendante en 2 parties (~91 vérifications sur le code et la doc de Ceph 20.2 ; RPM el10 et clé de signature vérifiés, specs validées par `python-common`, `crushtool`, notes de 20.2.4 et CVE). À confirmer sur le lab : valeurs du réglage mémoire automatique, formats JSON (`mutes`, comptes RGW), `aes256k` pendant la mise à jour, messages de refus cephx, timing de E36 v2 |
| 09 | Cluster de virtualisation | relu | 45 + mini-projet | 4 rédacteurs, harmonisation, relecture indépendante en 2 parties (~90 vérifications ; wiki Automated Installation, signatures de l'ISO 9.2-1, code de pve-ha-manager, guide Squid→Tentacle, `tofu validate`, `ansible-lint`). À confirmer sur le lab : épinglage `nic0..4` par `ID_NET_NAME_MAC`, libellés de `ha-manager status` et de `disarm-ha`, configuration FRR du SDN EVPN, démarrage de l'OVA, `watchdog-mux` sans périphérique |
| 10 | OpenStack | relu | 45 + mini-projet | 4 rédacteurs, harmonisation, relecture indépendante en 2 parties (~104 vérifications dans le code de kolla-ansible 22.2.0 `stable/2026.1`, kolla, horizon, keystone, OSC 10 ; `tofu validate`, 15 bats). Rôle `sauvegarde_pbs` fusionné avec la version M09. À confirmer sur le lab : déploiement complet, images Debian « untested » de la matrice Kolla (repli `rocky` documenté), ACME de Kolla vers step-ca, formats JSON de la CLI, droits cephx minimaux |
| 11 | Provisioning bare-metal | relu | 24 + mini-projet | 2 rédacteurs, harmonisation, relecture indépendante (~45 vérifications ; `kea-dhcp4 -t` 3.0.4, `ksvalidator` RHEL10, `debconf-set-selections -c`, pilote Proxmox de MAAS 3.7 lu dans le code ; construction iPXE corrigée `TRUST=`+`CERT=`). À confirmer sur le lab : user-class iPXE au second DISCOVER, ROM iPXE de QEMU/OVMF, `IPMI.ProtocolEnabled`/`FirmwareInventory` sur iLO 4, magasin TLS du snap MAAS |
| 12-18 | Bloc C | à faire | | |
| 19-20 | Bloc D | à faire | | |
| 21-23 | Bloc E | à faire | | |
| 24-26 | Bloc F | à faire | | |
| 27-29 | Bloc G | à faire | | |
| F1-F7 | Finaux | à faire | | |

## Effets du bloc B sur les modules précédents (à surveiller)

- Après M07-E25, `gw01` répond en `.2` et la VIP `.1` peut être portée par `gw02` : les vérifications des modules 00 à 06 qui joignent `gw01` par `10.10.x.1` atteignent le maître VRRP (le plus souvent `gw01`, `nopreempt`). À revoir si un retour de l'apprenant montre un faux rouge.
- Après M07-E24, la matrice des flux est dans `group_vars/role_routeur/pare_feu.yml` ; le check M06-E46 lit encore `host_vars/gw01/pare_feu.yml` (il reste vert grâce aux autres fichiers de `host_vars/gw01`).

## Retours de l'apprenant en attente

| Module | Exercice | Problème | Statut |
|---|---|---|---|
| — | — | — | — |

## Journal

| Date | Conversation | Travail |
|---|---|---|
| 2026-10-03/04 | 1 (fondations) | Plan, conventions, outillage lab, module 00 complet (4 rédacteurs + harmonisation + relecture indépendante), règles 9-12 ajoutées à la grille de relecture |
| 2026-10-03/04 | 2 (bloc A) | Versions du bloc A figées (recherche web), décisions structurantes dans PLAN §4.8 et journal (MinIO → SeaweedFS, `runner01`, `dns02`, AWX en fiche/Semaphore, Molecule sur VMs Proxmox), README et cartes d'exercices des modules 01 à 06, bibliothèque de pannes commune ; modules 01 à 06 rédigés, harmonisés, relus (session interrompue une fois par la limite d'utilisation, reprise sans perte) |
| 2026-10-07 | 2 (bloc A, clôture) | Annexes du bloc A ; contrôle global de cohérence : hôtes/VMID/IP conformes à PLAN §4.5, PLAN précisé (rôle DHCP de `dns01`, zone parente `medisphere.internal`, emplacement de l'ancre TLS de `pve01`), `lab.env.example` complet, `shellcheck -x` et `bash -n` propres sur tous les scripts, aucun secret ni cache versionné (`dump.rdb` retiré, `.gitignore` complété), README racine et REPRISE mis à jour |
| 2026-10-07 | 2 (bloc A, fin) | **Bloc A terminé** : modules 01 à 06 relus et poussés, annexes et topologie, contrôle global de cohérence (474 scripts ShellCheck propres). Tâche planifiée créée pour lancer le bloc B |

| 2026-10-08 | 3 (bloc B) | Lancée par la tâche planifiée. Versions du bloc B figées (recherche web, `annexes/versions-bloc-B.md`), décisions structurantes en PLAN §4.9 et journal, cartes des exercices des modules 07 à 11 |
| 2026-10-08 | 3 (bloc B) | Modules 07 à 11 rédigés (18 rédacteurs en parallèle sur des briefs communs), harmonisés (1 agent par module), relus indépendamment (9 relecteurs, ~420 vérifications sur la documentation et le code officiels, défauts bloquants corrigés : migration VRRP de la bordure, `--dry-run` de cephadm, construction d'iPXE, playbooks E24/E28/E46 de M09…). 323 scripts : `bash -n` et `shellcheck -x` propres. Annexes, topologie, README, REPRISE mis à jour. Correction transverse : M00-E22 (secret PBS hors des arguments de `pvesm`). **Bloc B terminé**, tâche planifiée créée pour lancer le bloc C |
## Choix faits en l'absence de l'apprenant (bloc A)

- **Stockage S3 du socle** : MinIO prévu au plan est abandonné par son éditeur (édition communautaire sans binaires depuis octobre 2025, dépôt archivé). Remplacé par SeaweedFS (Apache 2.0, écritures conditionnelles nécessaires au verrou d'état OpenTofu). Garage écarté pour cette raison. Le module 05 en fait un ADR.
- **AWX** : figé depuis 2024 et lourd (Kubernetes) ; traité en fiche, l'orchestrateur pratiqué au module 04 est Semaphore UI.
- **Molecule** : instances = VMs Proxmox éphémères (pilote `default`), les conteneurs n'étant enseignés qu'au module 12.
- **GitLab** : installé en 19.3 puis monté en 19.4 au M01-E29 pour pratiquer une vraie montée de version.
- **CI du bloc A** : un runner `shell` permanent (`runner01`) ; les exécuteurs Docker/Kubernetes viendront aux modules 12 et 19.
- **TLS avant step-ca** : une CA provisoire `openssl` (M01) remplacée au M06.
- **Versions éditeur plutôt que Debian** pour PowerDNS (5.x), Kea (3.0), step-ca (0.30), NetBox (4.6, la 4.7 n'étant pas encore validée par la collection Ansible et le provider) : les paquets de Debian 13 sont obsolètes ou en fin de vie.
- **Module 01** : méthode de fusion d'équipe `rebase_merge` (commit de fusion, historique semi-linéaire) ; Admin Mode activé en E31 (jetons avec portée `admin_mode` ensuite) ; hooks serveur sur `plateforme/*` seulement ; sauvegarde applicative de GitLab vers PBS (`proxmox-backup-client`) en plus de la sauvegarde de VM ; runbooks RB-010 à RB-013.
- **Module 02** : CA de `pve01` refusée par Python 3.13 (pas d'extension *Key Usage*, bogue Proxmox 6701) : le module fait construire une ancre de confiance conforme (M02-E08) utilisée par tous les outils Python ; scripts de panne qui mémorisent l'empreinte des fichiers posés pour que `--annuler` n'écrase pas une réparation (`corrige/pannes/_m02-reparations.sh`).
- **Module 03** : ISO déposées par script (`outils/deposer-iso.sh`) plutôt que téléchargées par Proxmox (contrôle de la somme et de la signature côté build) ; clones complets pour les VMs durables (PLAN, journal du 2026-10-07).
- **Module 04** : Semaphore UI pratiqué mais **non retenu** (ADR-0040 : application par la CI seule) — `sem01` est détruite en fin de module ; deux identités Vault (`lab`, `critique`) ; l'inventaire par défaut devient dynamique (Proxmox) dès M04-E13.
- **Module 05** : `gw01` reste hors IaC (ADR-0051) ; l'ordre de démarrage des VMs (exige `Sys.Modify` sur `/`) est posé en root et ignoré par OpenTofu ; environnements protégés de GitLab absents en CE → protection par branche protégée + job manuel + variables protégées + `resource_group` ; montée délibérée de `bpg/proxmox` en 0.116 en M05-E31.
- **Module 06** : CA provisoire retirée dès M06-E03 ; zones générées par le code (OpenTofu, Kea DDNS) gérées en mode API par le rôle PowerDNS pour ne jamais être écrasées ; NetBox devient l'inventaire Ansible par défaut (M06-E12).

## Choix faits en l'absence de l'apprenant (bloc B)

- **Bordure redondante** : `gw02` ajoutée au socle, VRRP sur toutes les passerelles (VIP `.1`, `gw01` en `.2`, `gw02` en `.3`), tunnels WireGuard qui suivent le maître. C'est le changement le plus risqué du bloc : il est placé au palier 3 de M07, avec répétition sur la maquette et retour arrière écrit.
- **Répartiteurs permanents** `lb01`/`lb02` dans la DMZ (VLAN 70), conformément au rôle prévu de ce VLAN.
- **LACP** : impossible entre VMs à travers un pont Linux (trames 802.3ad non relayées) ; pratiqué dans une VM entre espaces de noms.
- **Ceph sur Rocky Linux 10** : Debian 13 n'est pas un hôte supporté par Ceph Tentacle ; Rocky 10 l'est et l'image dorée existe depuis M03.
- **Cluster Proxmox imbriqué** : deux nœuds + QDevice sur `pbs01`, puis trois nœuds (le QDevice est retiré : déconseillé avec un nombre impair de nœuds). Ceph hyperconvergé installé en Squid pour pratiquer la montée en Tentacle.
- **OpenStack 2026.1** plutôt que 2026.2 (Kolla-Ansible encore en RC pour 2026.2) ; OVN choisi explicitement (le défaut de Kolla reste OVS) ; Octavia avec le fournisseur OVN (amphora trop lourd pour le lab).
- **MAAS sur Ubuntu 24.04** : seul cas d'Ubuntu du bloc (outil qui l'impose). `hp01` n'est jamais réinstallé : il porte PBS ; l'iLO est exploré en lecture.
