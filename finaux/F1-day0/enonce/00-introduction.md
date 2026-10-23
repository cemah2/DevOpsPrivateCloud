# Final F1 — Introduction : Day 0

## « Montrez-moi »

Lundi, 9 h 15, salle Rhône. L'auditeur HDS arrive dans six semaines. Sophie Laurent a posé sa question en comité de direction, devant Claire Morel :

> **De** : Sophie Laurent — RSSI
> **À** : Claire Morel
> **Cc** : toi, Karim Benali
> **Objet** : Plan de continuité — la question que l'auditeur posera
>
> Bonjour Claire,
>
> Le dossier HDS affirme que « la plateforme est entièrement décrite par du code et reconstructible ». L'auditeur ne lira pas le code : il demandera une preuve. Si on perd `k8s-par1` demain, combien de temps pour revenir, avec quelles données, et qu'est-ce qui exige encore une main humaine ? Je veux une démonstration réelle, mesurée, documentée, avant l'audit. Pas une estimation.
>
> Sophie

Claire a répondu le soir même, à toute l'équipe :

> **De** : Claire Morel — Responsable infrastructure
> **À** : toi
> **Cc** : Karim Benali, Sophie Laurent, Julien Petit, Nadia Roussel
> **Objet** : Day 0 — on le fait pour de bon
>
> Bonjour,
>
> On va répondre à Sophie de la seule façon honnête : en le faisant. Dans trois semaines, pendant une fenêtre de changement annoncée (CHG-3107), on **détruit `k8s-par1`** et on le **reconstruit à partir du code seul** : Git, états OpenTofu, rôles Ansible, Helmfile, Argo CD, OpenBao. Mêmes noms, mêmes adresses, mêmes VMID. Les données reviennent par les mécanismes prévus pour ça, pas par une copie de disque.
>
> Avant d'y aller :
> 1. je veux la **carte** de ce qu'il faut reconstruire, dans quel ordre, et de ce qui n'est pas dans le code ;
> 2. je veux que le code et la réalité disent **la même chose** : une dérive découverte pendant la fenêtre, c'est une reconstruction qui ne ressemble pas à l'original ;
> 3. je veux un **filet** : des sauvegardes prouvées la veille, des critères de go/no-go écrits, et un retour arrière qu'on sait jouer ;
> 4. on s'échauffe sur deux VMs **redondantes** du socle, `lb02` et `dns02`, refaites de la même façon ;
> 5. un des nœuds passera par l'**usine de provisioning** du M11, comme un serveur sorti du carton : c'est ce qui arrivera le jour où on aura du vrai matériel.
>
> Puis la reconstruction, puis une vraie livraison de MédiAgenda en production par le chemin normal, et un rapport. Tout ce qui demande une main humaine est chronométré, écrit, et devient de la dette.
>
> Karim relit tout. Julien a une livraison qui attend. Nadia prévient le support.
> Claire

---

## Ce que tu vas faire

Le final se déroule en quatre phases. Ce fichier ouvre les deux premières ; les phases 3 et 4 ont leurs propres fichiers.

| Phase | Fichier | Scénarios | Ce qui en sort |
|---|---|---|---|
| 1. Préparer | [`01-preparer.md`](01-preparer.md) | S01 à S04 | carte d'amorçage, code et réalité alignés, filet prouvé, go/no-go |
| 2. Socle et usine | [`02-socle-usine.md`](02-socle-usine.md) | S05, S06 | `lb02` et `dns02` refaites depuis le code, profil `k8s-noeud` dans l'usine, `k8s-w03` prêt à passer par elle |
| 3. Cluster | [`03-cluster.md`](03-cluster.md) | S07 à S12 | `k8s-par1` détruit puis reconstruit, couche de base, identité, secrets, plateforme, données |
| 4. Livrer et recetter | [`04-livrer-recetter.md`](04-livrer-recetter.md) | S13 à S15 | première livraison en production, recette `day0-v1`, rapport, RB-310, ADR-0310 |

Les phases 1 et 2 ne détruisent **rien** du cluster. La seule destruction de la phase 2 porte sur `lb02` et `dns02`, une à la fois, leur jumelle tenant le service. La destruction de `k8s-par1` n'a lieu qu'en phase 3, après le **go** de S04.

---

## La chaîne de reconstruction

C'est le fil de tout le final. Tu en feras ta propre version, plus fine et chiffrée, en S01.

```
 HORS DU CODE (coffre physique, poste d'astreinte)                                   ┌─────────────┐
 parts Shamir de kms01 · racine PKI hors ligne · mots de passe Vault Ansible ·       │ pbs01 (PAR2)│
 clés age · comptes de bris de glace (RB-240) · admin.conf                           │ s3-01       │
          │                                                                          │ sauvegardes │
          ▼                                                                          └──────┬──────┘
 ┌─ SOCLE (reste debout pendant F1, sauf lb02/dns02 en S05) ────────────────────────────────┼────────┐
 │ gw01/gw02 ─▶ dns01/dns02 ─▶ ca01 ─▶ git01 + runner01 ─▶ s3-01 (états, artefacts)        │        │
 │       └────▶ nbx01 ─▶ reg01 (Harbor) ─▶ kms01 ─▶ vault01-03 (OpenBao) ─▶ ipa01 ─▶ idp01  │        │
 │       └────▶ lb01/lb02 (points d'entrée) · mon01 (témoin) · pxe01 (usine, VLAN 60)       │        │
 └─────────────────────────────────────────────────────────────────────────────────────────┼────────┘
          ▼                                                                                 │
 ceph-par1 (stockage des volumes : RIEN n'y est effacé)                                     │
          ▼                                                                                 ▼
 VMs 2141-2146 (OpenTofu envs/k8s ; k8s-w03 par l'usine) ─▶ rôles Ansible (containerd, k8s_noeud,
 k8s_plan_controle, k8s_travailleur…) ─▶ kubeadm (VIP 10.10.40.200:8443, OIDC)
          ▼
 couche de base : Helmfile de plateforme/k8s (Cilium, cert-manager, ExternalDNS, ceph-csi, CNPG,
 Velero, metrics-server, runners, BuildKit, agent GitLab, Argo CD) + secrets d'amorçage
          ▼
 identité et secrets : méthode k8s-par1 d'OpenBao, ESO, RBAC oidc:*, Kyverno, robots Harbor
          ▼
 Argo CD : App of Apps ─▶ supervision, journaux, traces, sécurité, données, portail…
          ▼
 données : CNPG bootstrap.recovery (cnpg-k8s-par1), définitions RabbitMQ, Velero en appoint
          ▼
 applications (MédiAgenda, MédiNotif, MédiDoc) ─▶ première livraison en production (S13)
```

Chaque flèche est une dépendance. Plusieurs sont **circulaires** (la forge héberge le code de la forge, le registre sert ses propres images, le coffre et Ansible se tiennent mutuellement) : les identifier et dire comment on les casse est le cœur de S01.

---

## État d'entrée

Le final part de l'état de fin du bloc G. Avant S01, **tous** ces contrôles doivent être verts, dans cet ordre :

```
admin@adm01:~/DevOpsPrivateCloud$ lab/bin/check 24 46     # identite-v1
admin@adm01:~/DevOpsPrivateCloud$ lab/bin/check 25 46     # secrets-v1
admin@adm01:~/DevOpsPrivateCloud$ lab/bin/check 26 46     # durcissement-v1
admin@adm01:~/DevOpsPrivateCloud$ lab/bin/check 27 25     # donnees-v1
admin@adm01:~/DevOpsPrivateCloud$ lab/bin/check 28 25     # plateforme-dev-v1
admin@adm01:~/DevOpsPrivateCloud$ lab/bin/check 29 25     # resilience-v1
```

La phase 2 consomme en plus l'usine de provisioning du M11 (`provisioning-v1`). `pxe01` a pu rester éteinte depuis : démarre-la au début de la phase 2, puis lance `lab/bin/check 11 25` (ses contrôles de nettoyage de MAAS se règlent comme au M11 avec `WB_M11_MAAS_CONSERVE`). Un rouge à ce contrôle se répare **avant** S06.

Un contrôle rouge n'est pas une formalité à contourner : c'est exactement le genre d'écart qui fait échouer une reconstruction. Note-le, répare-le par le code, et garde la trace : S02 en fera l'inventaire.

Vérifie aussi que rien d'ancien ne traîne :

```
admin@adm01:~$ ls ~/.local/state/workbook/pannes-actives/ 2>/dev/null       # aucune panne ouverte
admin@adm01:~$ ssh root@pve01 'qm list | awk "\$1 >= 3100 && \$1 < 3200 || \$1 >= 5000 && \$1 < 6000"'
admin@adm01:~$ git -C ~/medisphere fetch --tags && git -C ~/medisphere tag -l 'resilience-v1'
```

---

## Profil de lab et mémoire

| Moment | Ce qui tourne | Mémoire de `pve01` |
|---|---|---|
| Phase 1 | socle v5 (≈ 51 Go) + `ceph-par1` (18 Go) + `k8s-par1` (42 Go) | ≈ 111 Go |
| S04, restauration de test | + **une** VM restaurée depuis PBS (un nœud de contrôle, 4 Go), le temps de la preuve | ≈ 115 Go |
| Phase 2 | + `pxe01` (1 Go) ; S06 : + la machine d'essai `f1-usine-essai` (2 Go) le temps de l'essai | ≈ 112 à 114 Go |
| S05 | `lb02` puis `dns02` détruites et recréées **une à la fois** : rien en plus | ≈ 112 Go |
| Phase 3 | `k8s-par1` détruit puis reconstruit sur ses VMID d'origine | ≤ 112 Go |

La marge sur 128 Go est faible. Deux règles : **jamais** deux VMs temporaires en même temps (restauration de test, essai de l'usine), et `mon01` reste allumé (il surveille la reconstruction depuis l'extérieur du cluster).

VMID du final : **3100-3199** (`3101` = `f1-usine-essai`, S06) ; restaurations de test depuis PBS : **5310-5319** (bac à sable, jamais sur le VLAN de production avec la carte active). `k8s-par1` garde ses VMID **2141-2146**.

---

## Règles de l'opération destructive

Elles valent pour tout le final. Relis-les avant chaque destruction.

1. **Rien ne se détruit sans go écrit.** Le go de la fenêtre CHG-3107 est prononcé en S04, sur des critères écrits à l'avance, au vu de preuves. Un critère rouge = no-go, même si « ça devrait aller ».
2. **Sauvegardes prouvées, pas supposées.** Une sauvegarde n'existe que si on l'a vue réussie et qu'on sait la relire (restauration de test ou vérification). Les preuves ont moins de 24 h au moment du go.
3. **Une redondance à la fois.** `lb02` ne se détruit que si `lb01` porte la VIP et sert ; `dns02` que si `dns01` répond et que Kea y tient le DHCP seul. Jamais les deux jumelles dans la même passe.
4. **Le stockage n'est pas effacé.** Ni pool Ceph, ni volume RBD de l'ancien cluster, ni compartiment de `s3-01`, ni archive de WAL, ni instantané PBS, ni état OpenTofu. Ce qui devient orphelin fait l'objet d'une **décision écrite**, pas d'un nettoyage réflexe.
5. **`kms01` ne se scelle jamais**, les parts Shamir ne sortent pas du coffre pour un exercice, la clé racine reste hors ligne. Les comptes de bris de glace (`root` de GitLab, `root@pam`, `admin.conf`, `admin` local des VMs, RB-240) restent utilisables du début à la fin.
6. **Tout passe par le code et la CI.** Un geste à la main est permis seulement quand il est **listé** (dans la carte d'amorçage ou dans le compte rendu) comme exception, chronométré, et inscrit comme dette.
7. **La production est annoncée.** Toute interruption de MédiAgenda, même en dehors de la fenêtre, est annoncée par Nadia au support avant de commencer. Ici, ton journal `docs/day0/journal/` fait office de canal.

---

## Documentation : `docs/day0/`

Tout ce que produit le final va dans `plateforme/medisphere`, dossier **`docs/day0/`**, par MR (relue par Karim : fais-la relire, ou relis-toi avec la grille du corrigé si tu travailles seul).

| Fichier | Scénario | Contenu |
|---|---|---|
| `carte-amorcage.md` | S01 | ordre de construction, dépendances circulaires, secrets hors du code, durées estimées |
| `derive-<AAAA-MM-JJ>.md` | S02, S03 | compte rendu de la chasse à la dérive, une ligne par écart et sa décision |
| `reference-avant.md` | S04 | inventaire de référence des données avant la fenêtre |
| `retour-arriere.md` | S04 | plan de retour arrière (restauration des six VMs depuis PBS) |
| `changements/CHG-31xx-<sujet>.md` | S04, S05, S07… | fiches de changement (go/no-go, déroulé, retour arrière) |
| `reconstruction-socle.md` | S05 | `lb02` et `dns02` : déroulé, durées mesurées, gestes manuels |
| `usine-k8s.md` | S06 | profil `k8s-noeud`, essai, préparation de `k8s-w03` |
| `chronologie.md` | S07 et suivants | chronométrage de la reconstruction, étape par étape |
| `rapport-reconstruction.md` | S15 | rapport final |
| `runbooks/RB-310-…` et suivants | S15 | runbooks du Day 0 |
| `adr/ADR-0310-…` et suivants | S15 | décisions |
| `journal/AAAA-MM-JJ-<sujet>.md` | tous | journal de diagnostic et annonces (rôle du canal du support) |

**Numérotation** : tickets `PLAT-31xx`, changements `CHG-31xx`, incidents `INC-57xx`, avec `xx` = numéro du scénario (PLAT-3101 pour S01, INC-5703 pour S03, CHG-3107 pour la fenêtre de S07). Runbooks à partir de **RB-310**, ADR à partir d'**ADR-0310**. L'étiquette finale **`day0-v1`** est posée sur `plateforme/medisphere` en S14.

**Aucun secret** dans `docs/day0/` : des **emplacements** (« part 3 : coffre de la DSI, enveloppe scellée n° … »), jamais des valeurs. Les checks le vérifient sur les documents qu'ils lisent.

---

## Préparer l'environnement

Copies de travail à jour sur `adm01` (`~/src/<projet>`, et `~/medisphere` pour la documentation) :

```
admin@adm01:~$ for p in infra ansible k8s gitops provisioning identite secrets politiques tofu-modules; do git -C ~/src/$p pull --ff-only; done
admin@adm01:~$ git -C ~/medisphere pull --ff-only && mkdir -p ~/medisphere/docs/day0/{changements,journal,runbooks,adr}
```

Ouvre `docs/day0/journal/<date>-ouverture.md` et notes-y l'heure de début : les durées du final se mesurent depuis tes notes.

### Variables de `lab/lab.env`

Toutes facultatives : les valeurs par défaut conviennent au lab de référence. Ne pose que ce qui diffère chez toi, et note la raison (S14 te demandera la liste).

| Variable | Défaut | Usage |
|---|---|---|
| `WB_F1_PROJET_DOC` | `plateforme/medisphere` | dépôt de la documentation lu par les checks (tous) |
| `WB_F1_DOC` | `docs/day0` | dossier du final dans ce dépôt (tous) |
| `WB_F1_JOURS` | `7` | fraîcheur exigée des contrôles de dérive et des plans (S02) |
| `WB_F1_HEURES` | `24` | âge maximal des sauvegardes du filet (S04) |
| `WB_F1_PBS_DATASTORE`, `WB_F1_PBS_NS` | `ds-lab`, `par1/k8s` | datastore et espace de noms PBS des nœuds (S04, S07) |
| `WB_F1_NOEUDS_VMID` | `2141 2142 2143 2144 2145 2146` | VMID des nœuds de `k8s-par1` (S04, S07) |
| `WB_F1_ETCD_UNITE`, `WB_F1_ETCD_HEURES` | `etcd-instantane.service`, `2` | unité d'instantané etcd des nœuds de contrôle et âge maximal (S04) |
| `WB_F1_LB01`, `WB_F1_LB02`, `WB_F1_DNS02` | `lb01`, `lb02`, `dns02` | hôtes visés par la panne et le check de S03 |
| `WB_F1_LB02_VMID` | `1011` | VMID de `lb02` (S03) |
| `WB_F1_LB02_ETIQUETTES`, `WB_F1_LB02_ONBOOT` | `role-lb;socle`, `1` | configuration Proxmox attendue de `lb02` (S03) |
| `WB_F1_VIP_LB` | `10.10.70.200` | VIP des répartiteurs (S03, S05) |
| `WB_F1_DEBUT` | — | date de référence (époque Unix) qui remplace le premier commit de `reference-avant.md` (S05) : seulement en cas de reprise du final |
| `WB_F1_ZONES` | `par1.medisphere.internal par2.medisphere.internal 10.10.in-addr.arpa 20.10.in-addr.arpa` | zones comparées entre `dns01` et `dns02` (S05) |
| `WB_F1_ESSAI_VMID`, `WB_F1_ESSAI_NOM`, `WB_F1_ESSAI_MAC` | `3101`, `f1-usine-essai`, `02:4d:53:60:31:01` | machine d'essai de l'usine (S06) |
| `WB_F1_PXE`, `WB_F1_PROFIL` | `pxe01`, `k8s-noeud` | serveur de démarrage et nom du profil (S06) |
| `WB_F1_K8S_VERSION` | `v1.36` | mineure attendue des nœuds reconstruits (S07) |
| `WB_F1_NAISSANCE_JOURS` | `30` | âge maximal du cluster reconstruit (S07) |
| `WB_F1_S10_ATTENTE` | `mediagenda-recette mediagenda-prod portail` | Applications qui peuvent attendre leurs données en S10 |
| `WB_F1_SERVEURS_ANCIENS` | `mediagenda-db mediagenda-db-prod portail-db` | `serverName` d'archivage des anciennes bases, interdits aux bases reconstruites (S11) |
| `WB_F1_PROD_URL` | `https://mediagenda.apps.par1.medisphere.internal` | MédiAgenda de production (S11, S13) |
| `WB_F1_DNS_AUTORITE`, `WB_F1_DNS_PORT` | `10.10.20.10`, `5300` | DNS faisant autorité interrogé sans récursion (S12) |
| `WB_F1_GATEWAY_IP` | `10.10.41.10` | adresse de `gw-par1` (S08, S12) |
| `WB_F1_S12_NOM`, `WB_F1_S12_ADRESSE`, `WB_F1_S12_ESPACE` | `portail.apps.par1.medisphere.internal`, `10.10.41.20`, `mediagenda-recette` | cibles de la panne de S12 (à ne changer que si ton lab diffère du corrigé) |
| `WB_F1_PROJET_API`, `WB_F1_PROJET_DEPLOIEMENT` | `mediagenda/api`, `mediagenda/deploiement` | projets de la livraison (S13) |
| `WB_F1_HARBOR_DEPOT` | `medisphere/mediagenda-api` | dépôt Harbor de l'image livrée (S13) |
| `WB_F1_S14_CONTROLES` | `29 25, 28 25, 27 25, 26 46, 25 46, 24 46, F1 02, F1 05, F1 06, F1 07, F1 08, F1 09, F1 10, F1 11, F1 12, F1 13` | contrôles rejoués par la recette (S14) ; toute réduction est une décision écrite |

Les checks réutilisent aussi `WB_PVE_HOST`, `WB_PBS_HOST`, `WB_K8S_*` (dont `WB_K8S_CP` et `WB_K8S_ADMIN_KUBECONFIG`), `WB_GITLAB_*`, `WB_NETBOX_*`, `WB_PROM_URL`, `WB_IPA_*`, `WB_OPENBAO_URL`, `WB_TIMEOUT`.

### Outillage sur `adm01`

En plus de ce que les modules ont installé (`tofu`, `uv`, `ansible`, `task`, `helm`, `helmfile`, `kubectl`, `kubelogin`), le final suppose :

| Outil | Pour quoi |
|---|---|
| `jq`, `yq` **de mikefarah (v4)**, `curl`, `dig`, `openssl`, `ssh`, `timeout` | checks et pannes (S03 et S12 refusent de s'injecter sans eux) |
| `bao` (CLI OpenBao) et une session OIDC portant `plateforme-admin` | amorçage des secrets (S08), confiance d'OpenBao (S09), panne S12 (session valable au moins 20 min) |
| greffon `kubectl cnpg` | gel et sauvegardes (S04, S07), récupération (S11) |
| `velero` | sauvegarde complète du filet (S04), restauration d'appoint (S11) |
| `argocd` (CLI, connexion SSO) | synchronisation sélective de la production (S11) |
| `cilium` (CLI) | couche de base (S08) |
| greffon `kubectl argo rollouts` | suivi du canary (S13) |
| `age` et `etcdutl` | relecture d'un instantané etcd (S04, RB-141) |
| `~/.config/workbook/powerdns-api.env` (M06-E14), `rabbitmq-checks.env` | panne S12, gel des files (S07) |

---

## Indices, corrigé, vérifications

- Les vérifications se lancent depuis `adm01` : `lab/bin/check F1 <XX>`. Elles sont en **lecture seule** : GitLab (jeton `read_api`), NetBox et le cluster (comptes `wb-checks`), Prometheus, `pve01` et `pbs01` en consultation, commandes de lecture en `sudo -n` sur les VMs. Elles ne lisent jamais un Secret ni une valeur du coffre. Un `RED` publié (S01) a un check de **présence** : il ne juge pas le fond, la grille du corrigé le fait.
- Les pannes s'injectent par `lab/bin/break F1 <XX>` ; `--annuler` remet l'état sain sans défaire une réparation faite par le code.
- Le corrigé (`corrige/`) donne une solution de référence (il en existe d'autres), le *pourquoi*, les pièges et la vision production. Les fichiers complets sont dans `corrige/fichiers/SXX/` : `infra/` reproduit `plateforme/infra`, `provisioning/` `plateforme/provisioning`, `ansible/` `plateforme/ansible`, `medisphere/` la documentation.

## Ordre conseillé

```
S01 ─ S02 ─ S03 ─ S04 (go/no-go)                         phase 1 : 12 à 19 h
S05 (lb02, puis dns02) ─ S06 (usine)                     phase 2 : 11 à 15 h, dont des attentes d'installation
S07 ─ S08 ─ S09 ─ S10 ─ S11 ─ S12                        phase 3 : 25 à 35 h (fenêtre CHG-3107)
S13 ─ S14 ─ S15                                          phase 4 : 10 à 16 h
```

S03 se lance **après** S02 : la panne suppose un code et une réalité alignés (son contrôle préalable vérifie seulement que les éléments qu'elle vise sont sains ; l'alignement, c'est `lab/bin/check F1 2` vert qui le prouve). S04 se rejoue juste avant la fenêtre de la phase 3 : ses preuves ont moins de 24 h au moment du go, quitte à refaire les sauvegardes. S05 et S06 sont indépendants ; S06 doit être terminé avant S07.

## Pour aller plus loin

- *Site Reliability Engineering*, chapitre « Data Integrity » (« personne ne veut de sauvegardes, tout le monde veut des restaurations »).
- Documentation Proxmox Backup Server : *Maintenance Tasks* (vérification), *Backup Namespaces*.
- Documentation kubeadm : *Creating Highly Available Clusters with kubeadm* ; documentation d'Argo CD : *Cluster Bootstrapping*.
