# Final F5 — Introduction : le site de repli

## Mardi, 10 h

Claire Morel pose sur la table le rapport de l'audit HDS, ouvert à la page des écarts. La même ligne revient trois fois : « Plan de reprise d'activité non testé ».

> **De** : Claire Morel — Responsable infrastructure
> **À** : toi
> **Cc** : Karim Benali, Sophie Laurent, Julien Petit, Nadia Roussel
> **Objet** : PRA — on arrête d'écrire qu'on en a un
>
> Bonjour,
>
> Aujourd'hui, si la salle de PAR1 brûle, nous avons des sauvegardes à PAR2 et une conviction : « on remontera ». Personne ne sait en combien de temps, ni dans quel ordre, ni avec quels secrets. La direction m'a accordé un budget modeste (pas de nouveau serveur : `hp01` fera l'affaire) et une date : **dans deux mois, un exercice réel**. On isole PAR1, on reprend à PAR2, on mesure, on revient.
>
> Ce que je veux à la fin :
> 1. des objectifs de reprise **justifiés** par l'impact, pas copiés d'un modèle ;
> 2. un site de repli **tiède**, alimenté en continu, qui ne dépend de rien à PAR1 le jour où PAR1 n'existe plus ;
> 3. un runbook que quelqu'un d'autre que toi peut suivre à 3 h du matin ;
> 4. le jour de l'exercice, deux nombres mesurés : l'heure à laquelle les patients reprennent rendez-vous, et combien de rendez-vous on a perdus.
>
> Sophie sera l'observatrice de l'exercice : elle relève les heures et les preuves, elle n'aide pas. Nadia pilote la cellule de crise. Julien veut savoir ce que son équipe fera le jour J. Karim a une seule inquiétude, et il a raison : `hp01` porte **toutes nos sauvegardes**. Le moindre geste malheureux sur cette machine nous ferait perdre d'un coup le site de secours et ce qu'il protège.
>
> Claire

---

## Ce que tu construis dans ce final

À la fin de F5, MédiSphère a un **site de repli testé** et sait le prouver. L'étiquette `pra-v1` de `plateforme/medisphere` est posée en F5-S14.

| Phase | Fichier | Scénarios | Ce qui en sort |
|---|---|---|---|
| 1. Analyser | [`01-analyser.md`](01-analyser.md) | S01-S02 | analyse d'impact, objectifs de reprise, carte des dépendances, ADR-0350 (architecture de PAR2) |
| 2. Construire PAR2 | [`02-construire-par2.md`](02-construire-par2.md) | S03-S07 | hyperviseur et réseau de PAR2, réplication des données, confiance et secrets hors de PAR1, cluster de secours `k8s-par2`, runbook de bascule RB-350, cellule de crise |
| 3. L'exercice | [`03-exercice.md`](03-exercice.md) | S08-S11 | répétition à blanc, **sinistre** (isolement de PAR1), reprise mesurée, mode dégradé |
| 4. Retour et bilan | [`04-retour-bilan.md`](04-retour-bilan.md) | S12-S14 | retour à PAR1 sans perte, rapport d'exercice, recette `pra-v1` |

Un final ne réenseigne rien : il **combine** ce que tu as construit au M00 (PBS, tunnel `wg0`), au M05 (OpenTofu, SeaweedFS), au M06 (DNS, PKI et sa racine hors ligne), au M07 (bordure), aux M13 et M19 (registre, signatures, runner protégé), M14-M16 (kubeadm, Cilium, CloudNativePG), M20 (Argo CD), M25 (OpenBao, `kms01`), M27 (réplica de secours) et M29 (mesures de bascule), ainsi qu'au F1 (reconstruction depuis le code). Les énoncés donnent objectifs, contraintes et critères ; les commandes sont dans tes runbooks.

---

## L'architecture visée

Aujourd'hui, PAR2 n'est qu'un serveur de sauvegardes. À la fin de la phase 2 :

```
                        LAN maison (<LAN-MAISON>)
   ┌──────────────────────────┐              ┌───────────────────────────────────────────────┐
   │ pve01 — PAR1 (10.10/16)  │              │ hp01 — PAR2 (10.20/16)  PBS 4.2 + PVE 9.2      │
   │                          │  wg0 (UDP    │ nœud « pbs01 », 16 Go, 2 cœurs                 │
   │ gw01/gw02 ── wg0 ────────┼─51820)───────┼── wg0 10.255.0.2                               │
   │   wg1 (VPN admin PAR1)   │              │   wg1 10.255.3.1 UDP 51823 (VPN de secours)    │
   │                          │              │   vmbr1 10.20.10.10 (PAR2 MGMT : PBS, API PVE) │
   │ socle v5, ceph-par1,     │              │   vmbr2 10.20.20.1  (PAR2 INFRA, NAT inet par2)│
   │ k8s-par1 (gw-par1        │              │   ┌──────────────── pool par2 ──────────────┐ │
   │   10.10.41.10)           │   données    │   │ 1050 adm02  .10  miroirs Git, sonde     │ │
   │                          │  ───────────>│   │ 1051 dns03  .11  DNS secondaire+récurs. │ │
   │ s3-01 ─ filer.sync ──────┼──────────────┼──>│ 1052 s3-02  .14  SeaweedFS (copie)      │ │
   │ RGW   ─ rclone ──────────┼──────────────┼──>│ 1053 reg02  .18  registry:3 (lecture)   │ │
   │ Harbor ─ cosign copy ────┼──────────────┼──>│ 1054 k8s-par2-n01 .50  k8s-par2 « tiède »│ │
   │ GitLab ─ push mirrors ───┼──────────────┼──>│      gw-par2 10.20.20.200 (L2, lb-par2) │ │
   │ mediagenda-db (primaire) │  WAL (s3-02) │   │      mediagenda-db-par2 (réplica)       │ │
   │                          │              │   │ 1055 bao-par2 .21  (arrêté hors PRA)    │ │
   │ kms01 1024 ──── PBS ─────┼──────────────┼──>│ 3501 kms01 restauré .24 (PRA seulement) │ │
   │                          │  sauvegardes │   └─────────────────────────────────────────┘ │
   └──────────────────────────┘              │   datastore ds-lab : NE JAMAIS Y TOUCHER       │
                                             └───────────────────────────────────────────────┘
   Noms globaux (zone medisphere.internal, CNAME TTL 60 s) :
     mediagenda / medidoc / rdv .medisphere.internal → ….apps.par1… (normal) | ….apps.par2… (PRA)
```

En temps normal, PAR2 est **tiède** : les données arrivent en continu, le cluster existe, les applications y sont à **zéro réplica**, le coffre de secours est **arrêté**. Pendant un PRA, on démarre ce qui dort, on promeut ce qui suit, on bascule les noms.

---

## État d'entrée

| Élément | État attendu | Contrôle |
|---|---|---|
| Plateforme | étiquette **`day1-v1`** (F2) ou postérieure (`astreinte-v1`, `changements-v1`) sur `plateforme/medisphere` : socle v5, `ceph-par1`, `k8s-par1` avec tous les services des blocs C à G | `lab/bin/check F2 13` |
| Données de MédiAgenda | `mediagenda-prod/mediagenda-db` archive par le plugin Barman Cloud dans `s3://cnpg-k8s-par1/` de `s3-01` (nom de serveur fixé au F1 : `mediagenda-db-prod-day0`) ; le réplica de secours `mediagenda-secours/mediagenda-db-secours` (M27, repointé au F1) le suit | `kubectl -n mediagenda-prod get cluster mediagenda-db -o jsonpath='{.spec.plugins}'` |
| Sauvegardes | PBS `pbs01`, datastore `ds-lab`, espaces de noms `par1/…` à jour ; dernière vérification (*verify job*) verte ; `kms01` (1024) sauvegardé (`par1/secrets`) | interface de PBS, `lab/bin/check 25 26` |
| Aucune panne active | `ls ~/.local/state/workbook/pannes-actives/` vide ; aucune expérience de chaos en cours | — |
| `hp01` | PBS seul, aucune VM ; mémoire libre ≥ 12 Go (`free -g`) ; disque du datastore avec au moins **150 Go** libres en plus de la croissance prévue des sauvegardes | `proxmox-backup-manager datastore list`, `df -h` |

Si F3 ou F4 n'ont pas été faits, rien ne manque à F5 : ils ne changent que des versions et des pratiques. Si F4 a été fait, réutilise son modèle de fiche de changement (`docs/changements/fiches/modele.md`) pour les changements de ce final (CHG-35xx).

---

## ⚠️ Les règles du final

1. **`hp01` porte toutes les sauvegardes du lab.** Le datastore `ds-lab`, la configuration de PBS (`/etc/proxmox-backup`), le réseau existant de l'hôte (sa carte LAN, `vmbr1`, `wg0`, son pare-feu `/etc/nftables.conf`) et ses tâches de sauvegarde ne doivent **jamais** être perdus ni modifiés sans retour arrière **écrit et vérifié**. Pas de reformatage, pas de réinstallation, pas de nouveau RAID, pas de « je nettoie les vieux instantanés pour faire de la place ». Avant tout changement sur `hp01` : une sauvegarde de sa configuration, vérifiée, **hors de `hp01`**.
2. **`kms01` de PAR1 n'est jamais touché.** Il descelle le coffre de production. Toute répétition de sa restauration se fait sur une **copie** à PAR2 (VMID 3501), isolée, détruite après usage. Jamais deux `kms01` sur le même réseau.
3. **Une copie n'est pas une sauvegarde.** Ce que tu répliques à PAR2 (objets, dépôts, images) réplique aussi les suppressions et les erreurs. PBS reste la sauvegarde ; PAR2 est un site de **reprise**.
4. **PAR2 ne dépend pas de PAR1.** Tout ce dont la reprise a besoin (code, état OpenTofu, images, secrets, autorité de certification, comptes, documentation) doit être **à PAR2 avant** le sinistre. Une dépendance découverte pendant l'exercice est un résultat de l'exercice — on préfère la découvrir à la répétition (S08).
5. **Tout par le code.** VMs de PAR2 par OpenTofu (`plateforme/infra`, `envs/par2`), configuration par Ansible (groupe `site_par2`), cluster par `plateforme/k8s` et Argo CD. Les exceptions (installation de PVE sur `hp01`, cérémonie de PKI) sont écrites dans leur fiche ou leur procès-verbal.
6. **Les changements de PAR1 passent par le processus de changement** (fiches CHG-35xx) : filtrage de la bordure, nouvelles identités S3, *push mirrors*, ajout de l'en-tête de site aux routes, topologie distribuée de la base de production.

---

## Mémoire et disque de `hp01`

`hp01` : 16 Go, 2 cœurs, ≈ 2 To de disque dur qui portent déjà le datastore `ds-lab`. Le site de repli tient dans ce qui reste, sans toucher à PBS :

| Élément | Veille | Pendant un PRA |
|---|---|---|
| Hôte (Debian, PBS, PVE, ZFS éventuel) | ≈ 5 Go réservés | ≈ 5 Go |
| `adm02` (1050) | 1 Go | 1 Go |
| `dns03` (1051) | 0,5 Go | 0,5 Go |
| `s3-02` (1052) | 1 Go | 1 Go |
| `reg02` (1053) | 0,5 Go | 0,5 Go |
| `k8s-par2-n01` (1054) | 5 Go | 5 Go (applications démarrées en mode dégradé) |
| `bao-par2` (1055) | arrêté | 1 Go |
| `kms01` restauré (3501) | absent | 0,5 Go |
| **Total des VMs** | **≈ 8 Go** | **≈ 10 Go** |

Disque : stockage Proxmox **`par2-vms`** (répertoire sur le disque dur, à côté de `ds-lab`, avec une **place réservée** et une alerte avant saturation). Le plus gros consommateur est `s3-02` (copie des archives PostgreSQL, des sauvegardes Velero et des documents de MédiDoc) : dimensionne-le en S02 à partir des volumes réels de `s3-01`, **et** de la place réellement libre sur `hp01` hors de `ds-lab` (avec la disposition du M00-E20, il ne reste dans le groupe de volumes que ce que `ds-lab` n'a pas pris : `vgs`).

> ⚠️ **Attention** : un datastore PBS plein arrête **toutes** les sauvegardes du lab. Si `par2-vms` et `ds-lab` partagent un système de fichiers, une VM de PAR2 qui grossit peut remplir le disque des sauvegardes. S03 fixe une limite technique, pas une bonne intention.

---

## Hôtes, objets et valeurs figées

| Élément | Valeur | Scénarios |
|---|---|---|
| Hyperviseur de PAR2 | `hp01`, nœud Proxmox **`pbs01`** (PBS conservé) ; API PVE `https://10.20.10.10:8006` ; pool **`par2`**, étiquette **`site-par2`**, stockage **`par2-vms`** | S03 |
| Réseau PAR2 INFRA | pont **`vmbr2`** sans port physique, **10.20.20.0/24**, passerelle **10.20.20.1** (`hp01`) ; routage vers PAR1 par `wg0` ; sortie Internet par le LAN de `hp01`, NAT dans la table nftables **`inet par2`** (fichier séparé) | S03 |
| VPN d'administration de secours | `wg1` de `hp01`, **10.255.3.1/24**, UDP **51823** ; ton poste en 10.255.3.2 ; n'ouvre que PAR2 | S03 |
| `adm02` | VMID 1050, 10.20.20.10 : poste d'administration de secours, miroirs Git `/srv/miroirs/<groupe>/<projet>.git` (compte **`miroir`**), sonde `ms-sonde-pra` | S03, S04 |
| `dns03` | VMID 1051, 10.20.20.11 : PowerDNS autoritaire **secondaire** de toutes les zones internes + récurseur | S03 |
| `s3-02` | VMID 1052, 10.20.20.14 : SeaweedFS ; compartiment d'état **`tofu-par2`** ; cible de `weed filer.sync` | S03, S04 |
| `reg02` | VMID 1053, 10.20.20.18 : `registry:3`, `https://reg02.par2.medisphere.internal` | S04 |
| `k8s-par2-n01` | VMID 1054, 10.20.20.50 : cluster **`k8s-par2`** (nœud unique, sans *taint*) ; LB IPAM **`lb-par2`** 10.20.20.200-239 annoncé en **L2** ; Gateway **`gw-par2`** 10.20.20.200 (`*.apps.par2.medisphere.internal`) | S06 |
| `bao-par2` | VMID 1055, 10.20.20.21 : OpenBao de secours, **arrêté** hors PRA | S05 |
| `kms01` restauré | VMID **3501**, **10.20.20.24** : copie de `kms01` restaurée depuis PBS, **pendant un PRA ou une répétition seulement** | S05 |
| Base de secours | `Cluster` **`mediagenda-db-par2`** dans `mediagenda-prod` de `k8s-par2`, topologie distribuée avec `mediagenda-db` de PAR1 | S06 |
| Repère de site | en-tête de réponse **`X-MediSphere-Site: par1`** (ou `par2`), posé par un filtre `ResponseHeaderModifier` des HTTPRoute | S06 |
| Témoin de RPO | CronJob **`temoin-rpo`** dans `mediagenda-prod` de chaque cluster (suspendu sur le site passif) : chaque minute, un rendez-vous du praticien technique **`PRA-TEMOIN`**, horodatage dans `motif` | S06 |
| Noms globaux | `mediagenda.medisphere.internal`, `medidoc.medisphere.internal`, `rdv.medisphere.internal` : CNAME, TTL **60 s** | S03, S06 |
| VMID du final | 3500-3599 (3501 réservé à `kms01` restauré) ; PAR2 : 1050-1059 | — |

**MédiDoc dans le lab.** MédiDoc n'a pas d'espace de production dans le lab : son instance de référence est `medidoc-recette` (comme au F4). Le PRA la traite comme la production de MédiDoc.

---

## Conventions du final

**Documentation** (dépôt `plateforme/medisphere`, par MR) :

| Chemin | Contenu | Scénario |
|---|---|---|
| `docs/pra/bia.md`, `docs/pra/objectifs.md` | analyse d'impact, objectifs de reprise | S01 |
| `docs/pra/dependances.md`, `docs/pra/adr/ADR-0350-site-de-repli-par2.md` | dépendances et ordre de reprise ; architecture de PAR2 | S02 |
| `docs/pra/enveloppe.md` | contenu de l'**enveloppe de reprise** (liste, emplacements, gardiens : **aucun secret**) | S05 |
| `docs/pra/runbooks/RB-350-bascule-par2.md`, `docs/pra/cellule-de-crise.md` | bascule, organisation de crise | S07 |
| `docs/pra/runbooks/RB-351-retour-par1.md` | retour | S12 |
| `docs/pra/runbooks/RB-353…RB-356` | runbooks de construction et d'exploitation de PAR2 (hyperviseur, réplication, restauration de `kms01`, cluster de secours) | S03-S06 |
| `docs/pra/mesures/` | mesures exportées (retards de réplication, répétitions, exercice) | S04-S11 |
| `docs/pra/journal/AAAA-MM-JJ.md` | main courante de l'exercice : une ligne `- HH:MM INC-6109 [type] texte` | S09-S12 |
| `docs/pra/exercices/2026-exercice-1/rapport.md` | rapport d'exercice | S13 |
| `docs/pra/calendrier-tests.md` | calendrier des tests de reprise | S14 |

**Tickets** : `PLAT-35xx`, `CHG-35xx`, `INC-61xx` (`xx` = numéro du scénario ; le sinistre est **INC-6109**).

**Code** :
- `plateforme/infra` : `envs/par2/` (OpenTofu, fournisseur `bpg/proxmox` vers `https://10.20.10.10:8006`, état dans le compartiment **`tofu-par2` de `s3-02`**) ;
- `plateforme/ansible` : groupe d'inventaire **`site_par2`** ;
- `plateforme/k8s` : inventaire et valeurs du cluster **`k8s-par2`** — **même code** que `k8s-par1`, les différences dans des fichiers de site seulement ;
- `plateforme/gitops` : ce qu'Argo CD de `k8s-par2` déploie, lu sur les **miroirs** de `adm02` : `ssh://miroir@adm02.par2.medisphere.internal/srv/miroirs/<groupe>/<projet>.git`.

---

## Variables de `lab/lab.env`

Toutes facultatives : les défauts conviennent au lab ; la liste complète, commentée, est dans la section F5 de [`lab/lab.env.example`](../../../lab/lab.env.example). Pendant l'exercice (S09 à S11), les checks se lancent **depuis `adm02`** (dépôt du workbook cloné depuis GitHub sur `adm02`, avec son propre `lab/lab.env`).

| Variable | Défaut | Utilisée par |
|---|---|---|
| `WB_F5_DOC`, `WB_F5_PROJET_DOC` | `docs/pra`, `plateforme/medisphere` | checks des documents |
| `WB_F5_SOURCE_DOC` | `gitlab` | `miroir` : lire les documents sur les miroirs de `adm02` (quand GitLab n'est pas joignable) |
| `WB_F5_MIROIRS` | `/srv/miroirs` | S04 et suivants (dossier des miroirs sur `adm02`) |
| `WB_F5_HP01` | valeur de `WB_PBS_HOST` (`pbs01`) | S03 et suivants (SSH `root`) |
| `WB_F5_ADM02`, `WB_F5_S3_02_HOTE`, `WB_F5_DNS03_HOTE` | `adm02.par2.medisphere.internal`, `s3-02.par2…`, `dns03.par2…` | SSH `admin` vers les VMs de PAR2 |
| `WB_F5_DNS01`, `WB_F5_DNS03` | `10.10.20.10`, `10.20.20.11` | récurseurs interrogés (S03, S09 à S12) |
| `WB_F5_S3_URL`, `WB_F5_S3_CHECKS_FILE` | `https://s3-02.par2.medisphere.internal:8333`, `~/.config/workbook/s3-02-checks.env` | S03, S04 (identité **`wb-checks`** de `s3-02`, lecture et liste) |
| `WB_F5_REG02_URL`, `WB_F5_REG02_CHECKS_FILE` | `https://reg02.par2.medisphere.internal`, `~/.config/workbook/reg02-checks.env` | S04 (`REG02_USER`, `REG02_PASSWORD`) |
| `WB_F5_KUBECONFIG_PAR2` | `~/.config/workbook/k8s-par2-checks.kubeconfig` | S06 et suivants (compte `wb-checks` de `k8s-par2`, lecture, jamais les Secrets) |
| `WB_F5_PAR2_ADMIN_KUBECONFIG` | `~/.kube/k8s-par2.config` | panne S08 (administration de `k8s-par2` depuis `adm01`) |
| `WB_F5_SERVEUR_PROD` | `mediagenda-db-prod-day0` | S04, S06 (nom d'archivage de la base de production ; `mediagenda-db-prod-pra1` après le retour de S12) |
| `WB_F5_RETARD_MAX_S`, `WB_F5_MIROIR_RETARD_MAX_S` | `900`, `3600` | S04 (RPO de MédiAgenda ; retard d'un miroir Git) |
| `WB_F5_PROJETS_MIROIRS` | voir `checks/_f5-par2.sh` | S04 (projets qui doivent avoir un miroir) |
| `WB_F5_URL_PAR1`, `WB_F5_KMS01_URL` | `https://mediagenda.apps.par1.medisphere.internal`, `https://kms01.par1.medisphere.internal:8200` | S06 (repère de site), S05 (`kms01` de PAR1 intact) |
| `WB_F5_EXERCICE`, `WB_F5_DEPOT_PAR2` | `2026-exercice-1`, `~/medisphere` (sur `adm02`) | S08 à S14 (dossiers de l'exercice, clone de travail de la documentation pendant le PRA) |
| `WB_F5_RTO_MEDIAGENDA_MIN`, `WB_F5_RTO_MEDIDOC_MIN`, `WB_F5_RTO_RDV_MIN` | `240`, `480`, `480` | S09 (tes objectifs de S01, en minutes) |
| `WB_F5_PROM_PAR2_URL`, `WB_F5_AM_PAR2_URL`, `WB_F5_MAILPIT_PAR2_URL` | `http://adm02.par2.medisphere.internal:9090`, `:9093`, `:8025` | S11, S12, S14 (supervision minimale de PAR2) |
| `WB_F5_COUPURE_RETOUR_MAX_MIN` | `15` | S12 |

**Outils sur `adm01` et `adm02`** : `curl`, `jq`, `dig`, `openssl`, `kubectl`, `aws` (CLI, S03-S04), `ssh` (vers `pbs01` en `root`, vers les VMs de PAR2 en `admin`), `git`.

---

## Pour commencer

Lis [`01-analyser.md`](01-analyser.md). Les deux premiers scénarios ne touchent à rien : ils décident de ce que vaut chaque heure d'arrêt, et de tout ce qui doit exister à PAR2 pour qu'une reprise soit possible. Tout le reste en découle.
