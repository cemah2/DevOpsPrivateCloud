# Module 08 — Palier 5 : Mini-projet

Le module a construit, exploité, cassé et réparé `ceph-par1`. Il reste à le **livrer** comme une brique de la plateforme : un cluster décrit par le code, à jour, chiffré, surveillé, sauvegardé, prêt à recevoir les disques des VMs d'OpenStack (M10) et les volumes persistants de Kubernetes (M16), et un stockage objet que MédiDoc peut utiliser pour des données de santé. Le nœud d'essai `ceph04` disparaît proprement, les pannes du palier 4 ont laissé des runbooks, et la politique de stockage dit aux équipes ce qu'elles peuvent demander. Ce mini-projet est ce que Claire Morel présentera à la DSI et à l'auditeur HDS comme « stockage MédiSphère v1 ».

---

### M08-E46 — Mini-projet : stockage MédiSphère v1  `LIBRE` `★★★`

> **Ticket PLAT-990** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent, Nadia Roussel, Julien Petit*
> Recette du stockage v1 dans deux semaines. Je veux un cluster qui passe le contrôle global sans un seul rouge, **sans rien de provisoire** (plus de `ceph04`, plus d'OSD en clair, plus de pool d'essai oublié), et prêt pour les deux consommateurs qui arrivent : OpenStack et Kubernetes auront leurs pools et leurs identités le jour où ils démarrent, sans ticket.
> Pendant la revue : Karim fera la revue de `plateforme/ceph` et rejouera le pipeline ; Sophie relira la politique de stockage, l'ADR-0080, le registre des secrets et la matrice des flux ; Nadia arrêtera un nœud entier pendant ta présentation et regardera ce que dit la supervision ; Julien déposera un document dans le compte S3 de MédiDoc et le relira, pendant que Nadia fait sa panne. Format habituel : 10 minutes de présentation, les démonstrations, nos questions.

**Objectifs pédagogiques**
- Consolider le cluster du module en une brique cohérente, pilotée par le code et sans dette provisoire.
- Préparer l'intégration des consommateurs (OpenStack, Kubernetes, MédiDoc) : pools, règles, quotas, identités.
- Livrer l'état `stockage-v1` : documentation, flux, sauvegardes, supervision, étiquette de version.

**Prérequis** : M08-E01 à M08-E45 (au minimum tous les `LAB`, `LIBRE`, `BF` et le `CHRONO`) ; le mini-projet M07-E46 (`socle-v2`).
**Durée indicative** : 14 à 20 h, plus 30 min de revue.

**Contexte technique**
- Cluster `ceph-par1` (PLAN.md §4.9) : `ceph01-03` (2081-2083), public 10.10.30.51-53, cluster 10.10.31.51-53, MTU 9000, Ceph Tentacle **20.2.4**, cephadm, Podman, Rocky Linux 10. Client `cephcli01` (2085, 10.10.30.20). `ceph04` (2084) **n'existe plus** à la livraison.
- Consommateurs à préparer (créés ici, **pas encore distribués**) :

  | Consommateur | Pool | Usage | Classe |
  |---|---|---|---|
  | Glance (M10) | `images` | images de VM | `ssd` |
  | Cinder (M10) | `volumes` | volumes persistants | `ssd` |
  | Nova (M10) | `vms` | disques éphémères | `ssd` |
  | Cinder Backup (M10) | `backups` | sauvegardes de volumes | `hdd` |
  | Kubernetes, Ceph-CSI (M16) | `k8s-rbd` | volumes persistants | `ssd` |

  Identités : `client.glance`, `client.cinder` (utilisée aussi par Nova, comme dans la documentation Ceph pour OpenStack), `client.cinder-backup`, `client.k8s`.
- Stockage objet : point d'entrée `https://rgw.par1.medisphere.internal` (VIP 10.10.30.200, ingress cephadm, certificat step-ca), compte RGW de MédiDoc (E12) ; décision de l'ADR-0080 (E30).
- Le contrôle global `lab/bin/check 08 46` vérifie le cluster et ses services, les consommateurs préparés, la sécurité, l'exploitation (supervision, sauvegarde), la documentation, **revérifie les acquis de M07** utilisés par le stockage (MTU 9000 de bout en bout sur les VLAN 30 et 31) et vérifie l'**absence** de `ceph04` et des ressources d'essai. Il prend quelques minutes.

**Travail demandé**
1. **Rien de provisoire.** `ceph04` est retiré proprement (OSD vidés puis retirés, hôte retiré de l'orchestrateur et de CRUSH, VM détruite par OpenTofu, objets NetBox et DNS retirés) ; les pools et images d'essai des paliers précédents (`bench`, restaurations, pools de démonstration des codes d'effacement s'ils ne servent plus) sont supprimés ou justifiés dans le registre des allocations ; aucune panne `M08` active.
2. **Le cluster.** HEALTH_OK, 3 MON en quorum, 2 MGR, 9 OSD `up` et `in`, autoscaler actif ; tous les démons et la commande `cephadm` des nœuds en 20.2.4 ; `osd_memory_target` = 1 Gio ; tout l'état est décrit dans `plateforme/ceph` (spécifications, règles, pools, identités) et le pipeline le valide.
3. **Sécurité.** Messager en mode `secure` ; **tous** les OSD chiffrés au repos (redéploiement de `ceph01` et `ceph02` par la procédure de E27) ; clés cephx de démons et d'administration du nouveau type, clés clientes renouvelées quand leur logiciel le permet (les autres listées, datées, en sourdine **temporaire**) ; clé SSH de l'orchestrateur renouvelée ; tableau de bord en TLS avec compte personnel en lecture seule ; aucune identité `allow *` hors administration.
4. **Consommateurs.** Les cinq pools du tableau, application `rbd`, règle de la bonne classe, quota chacun (somme cohérente avec la capacité et la réserve de la politique de stockage, écrite dans le registre des allocations), et les quatre identités aux droits minimaux de la documentation Ceph (OpenStack, Ceph-CSI). Les trousseaux sont en Vault, prêts à être distribués ; le type de clé sera choisi au moment de la distribution selon le client (M10, M16) : écris-le.
5. **Objet et fichier.** RGW joignable en HTTPS par le nom et la VIP depuis `adm01` et `cephcli01`, compte MédiDoc avec quota ; CephFS avec MDS actif et en attente, groupes de sous-volumes des équipes (E31, E34).
6. **Exploitation.** Sonde `ms-verif-ceph` planifiée et verte ; sauvegarde nocturne (volumes et configuration) vers `pbs01` réussie, avec un test de restauration **réalisé pour cette livraison** et chronométré (en tête de `docs/stockage/tests/restauration-ceph.md`) ; RB-080, RB-081, RB-082 et les runbooks du palier 4 à jour.
7. **Réseau (acquis M07).** MTU 9000 de bout en bout sur les VLAN 30 et 31 pour les trois nœuds et `cephcli01` (configuration Proxmox des cartes et des invités, preuve par `ping -M do`), MTU 1500 partout ailleurs ; flux ouverts pour le stockage décrits dans `group_vars/role_routeur/pare_feu.yml` et la matrice documentaire (dont `runner01` → VIP RGW, `cephcli01` → `pbs01`, `runner01` → nœuds Ceph pour la détection de dérive).
8. **Documentation.** `docs/stockage/` : architecture (`architecture.md` : démons, réseaux, pools et règles, ce qui se passe quand un OSD, un nœud, un MON, un MGR, l'ingress tombent), politique de stockage (E33), ADR-0080 (E30), registre des allocations, mesures de performances (E28-E29), runbooks ; inventaire NetBox (`ceph01-03`, `cephcli01`, VIP RGW) et matrice des flux à jour ; registre des secrets complété (dashboard, cephx, clés de sauvegarde, clé SSH de cephadm, clés LUKS : emplacements, jamais les valeurs).
9. **Livraison.** Tout est fusionné, les pipelines de `main` (`plateforme/ceph`, `plateforme/ansible`, `plateforme/infra`, `plateforme/outils`, `plateforme/medisphere`) sont verts, et l'étiquette **`stockage-v1`** est posée sur `plateforme/medisphere`.
10. **La revue.** 10 minutes de présentation (architecture, choix et compromis, ce qui n'est **pas** redondant : un seul hyperviseur physique, un seul site, une seule baie de SSD), puis les démonstrations de Nadia (arrêt d'un nœud entier) et de Julien (dépôt et relecture S3 pendant la panne).

**Contraintes**
- Aucune perte de redondance pendant les redéploiements d'OSD (un seul à la fois, HEALTH_OK entre deux).
- Aucun secret dans un dépôt, un journal de CI ou la documentation : des **emplacements**, jamais des valeurs. La clé `client.admin` ne réside que sur les hôtes `_admin`.
- Tout ce qui est créé l'est par le code (spécifications, rôles, OpenTofu) ; une intervention manuelle exceptionnelle est consignée et reportée dans le code.
- Les choix qui s'écartent d'un exercice du module sont justifiés (ADR ou description de MR).

**Critères de réussite**
- [ ] `lab/bin/check 08 46` est entièrement vert.
- [ ] La démonstration de Nadia (arrêt d'un nœud) : la sonde alerte, les clients continuent (RBD, CephFS, S3 de Julien), le retour du nœud ramène HEALTH_OK sans intervention.
- [ ] Le test de restauration est chronométré et consigné, avec RTO et RPO.
- [ ] La documentation dit ce qui n'est **pas** redondant et ce que M09, M10 et M16 devront traiter.
- [ ] La revue est passée (auto-évaluation avec la grille du corrigé si tu travailles seul).

**Vérification** : `lab/bin/check 08 46`

<details><summary>Indice 1</summary>

Lance `lab/bin/check 08 46` dès le début : la liste des points rouges est ton plan de travail. Les contrôles détaillés (`lab/bin/check 08 XX`) donnent le détail par brique, et `lab/bin/check 07 46` revérifie la bordure et le MTU.
</details>

<details><summary>Indice 2</summary>

Redéployer six OSD chiffrés et retirer `ceph04` déplacent beaucoup de données : planifie l'ordre (retirer `ceph04` d'abord, puis redéployer), et laisse la récupération finir à chaque étape. Une restauration de test faite **avant** les redéploiements est une bonne assurance.
</details>

<details><summary>Indice 3</summary>

Pour les identités OpenStack et Kubernetes, la documentation Ceph (*Block Devices and OpenStack*, et celle de Ceph-CSI) donne les profils `rbd` et `rbd-read-only` par pool, côté moniteurs, OSD **et** mgr. Compare avec ce que tu as écrit : un droit de trop ici sera un droit de trop pendant des années.
</details>

**Pour aller plus loin** (facultatif) : une démonstration « reconstruire le cluster depuis le code » sur des VMs jetables (amorçage, spécifications, pools, identités) chronométrée ; un tableau de bord texte (préparé pour M21) des allocations par équipe à partir de `rbd du` et des quotas.
