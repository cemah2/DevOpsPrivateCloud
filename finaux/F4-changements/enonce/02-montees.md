# Final F4 — Phase 2 : Montées

Le cluster, ses composants, le stockage, le cloud : quatre montées, chacune sous la sonde, chacune avec sa fiche. Et une décision avant la première : la mineure suivante de Kubernetes est-elle prête pour **nous** ?

Prérequis de la phase : F4-S01 et F4-S02 terminés (`lab/bin/check F4 1` et `lab/bin/check F4 2` verts). Pendant toute la phase, **une** fenêtre à la fois, la sonde lancée avant (RB-340), et la fiche ouverte par MR avant la fenêtre.

> ⚠️ **Attention** : avant chaque fenêtre, vérifie les filets que la fiche nomme (instantané etcd de moins d'une heure, sauvegarde PBS de la nuit, sauvegarde CNPG `Completed`, base d'OpenStack sauvegardée et envoyée sur PBS). Une montée qui ne se défait pas (plan de contrôle Kubernetes, moniteurs Ceph, série OpenStack) n'a pas d'autre retour arrière que ces sauvegardes.

---

### F4-S03 — Go ou no-go : la mineure suivante de Kubernetes  `RED` `★★★`

> **Ticket CHG-3403** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent*
> La 1.37 est sortie. Je ne veux ni la monter parce qu'elle existe, ni la refuser par prudence. Je veux une décision écrite : **tout** ce qui tourne dans `k8s-par1` déclare-t-il cette version ? Utilisons-nous une API qui disparaît ? Qu'est-ce qui change de comportement ? Si c'est non, dis-moi ce qu'on fait à la place ce trimestre, et quand on en reparle.

**Objectifs pédagogiques**
- Inventorier **tous** les composants d'un cluster et leurs déclarations de compatibilité, à la source.
- Détecter les API dépréciées et retirées réellement appelées, et celles qui le seraient au prochain déploiement.
- Prendre et écrire une décision go/no-go argumentée, avec ses conditions de révision.

**Prérequis** : F4-S01 ; M14-E25 et M14-E30 (montée et politique de cycle de vie), M20 (Argo CD, `charts-miroir`), M21 (métriques de l'API), M29-E02 (kubeconform, `schemas-crd`).
**Durée indicative** : 4 h.

**Contexte technique**
- Version actuelle : 1.36.5 ; mineure suivante au relevé : 1.37 (voir l'annexe des versions). Fin de maintenance : 1.36 le 28/06/2027.
- Composants installés : couche de base sous Helmfile (`plateforme/k8s` : Cilium, cert-manager, ExternalDNS, ceph-csi, CloudNativePG et son plugin, Velero, metrics-server, runners, BuildKit, agent GitLab, Argo CD), le reste sous Argo CD (`plateforme/gitops`) ; outils de `adm01` ; runtime containerd.io 2.3.
- La métrique `apiserver_requested_deprecated_apis` de l'API (étiquettes `group`, `version`, `resource`, `removed_release`) est collectée par Prometheus depuis le M21.
- Livrables attendus par le check : fiche **`docs/changements/fiches/CHG-3403*.md`** avec `decision: go` ou `decision: no-go` dans son en-tête, et matrice **`docs/changements/matrices/compatibilite-kubernetes-<mineure>.md`**.

**Travail demandé**
1. **Inventaire** de tout ce qui tourne (images, releases Helm, Applications, CRD, outils) : chaque composant une ligne.
2. **Matrice** : pour chaque composant, la version installée, ce qu'il **déclare** pour la cible (page de compatibilité, matrice de tests, notes de version), la source (lien), et s'il est bloquant pour **nous**. Un silence n'est pas un oui.
3. **API** : celles que l'on appelle et qui disparaissent (côté serveur, sur plusieurs jours), et celles que nos dépôts produiraient (rendus validés contre les schémas de la cible).
4. **Changements de comportement** de la mineure qui toucheraient ce cluster (CHANGELOG : *Urgent Upgrade Notes*, *Deprecation*, kubeadm), et ceux qui ne le touchent pas, avec la raison.
5. **Décision** dans CHG-3403 : go ou no-go, par qui, quand ; si no-go, ce qui se fait quand même ce trimestre (ce qui est prêt) et les conditions précises de révision ; si go, l'ordre de la chaîne pour S04.

**Critères de réussite**
- [ ] CHG-3403 est sur `main` avec une décision `go` ou `no-go` dans son en-tête, l'analyse de Cilium, des API et les conditions de révision.
- [ ] La matrice est sur `main`, couvre au moins vingt composants installés et cite la source de chaque compatibilité.

**Vérification** : `lab/bin/check F4 3` (présence et contenu minimal ; la justesse de l'analyse se juge avec le corrigé).

<details><summary>Indice 1</summary>

Commence par ce qui porte tout : le CNI. Un cluster dont le CNI ne déclare pas la version du plan de contrôle n'a plus de réseau garanti. Puis tout ce qui pose des webhooks d'admission à « Fail » : s'ils cassent, plus rien ne se crée.
</details>

<details><summary>Indice 2</summary>

La métrique des API dépréciées dit ce qui a été **appelé** depuis le dernier redémarrage de chaque kube-apiserver, pas ce qui le sera au prochain déploiement. Les deux sources sont complémentaires ; pour savoir **qui** appelle, le journal d'audit (M14-E27, Loki locataire `audit`) porte une annotation sur les requêtes dépréciées.
</details>

**Pour aller plus loin** (facultatif) : automatiser la matrice (Renovate signale les nouvelles versions ; un job lit les pages de compatibilité et ouvre une issue quand la chaîne devient prête).

---

### F4-S04 — Monter Kubernetes sans interruption  `LIBRE` `★★★★`

> **Ticket CHG-3404** — *De : Karim Benali* — *Copie : Julien Petit, Nadia Roussel*
> On applique la décision de CHG-3403. Si c'est go : toute la chaîne dans l'ordre, puis le cluster, un nœud à la fois, sous la sonde. Si c'est no-go : on fait ce qui est prêt — Cilium à sa dernière corrective, et un travailleur **remplacé** par une VM neuve de la dernière image dorée plutôt que mis à jour sur place. Dans les deux cas, Julien veut zéro erreur côté cabinets, et moi je veux le chiffre.

**Objectifs pédagogiques**
- Exécuter une montée (ou un remplacement immuable de nœud) sous mesure, en respectant toutes les protections des charges : PDB, bascule CloudNativePG, quorum RabbitMQ, webhooks d'admission.
- Ordonner la chaîne : CNI d'abord, plan de contrôle, travailleurs, outils, schémas, code.
- Fixer un objectif d'interruption **avant** et le tenir.

**Prérequis** : F4-S02, F4-S03 ; M14-E25 (playbook `k8s-montee-version.yml`, RB-142), M14-E17 (ajout et retrait d'un nœud), M15 (Cilium par Helmfile), M16 et M27 (CNPG), M27 (RabbitMQ), M26 (Kyverno, kubelet-csr-approver), M29-E02 (`schemas-crd`).
**Durée indicative** : 6 à 8 h, dont une fenêtre de 3 h.

**Contexte technique**
- Rôles Ansible `k8s_*` et playbook de montée du M14 ; versions dans `group_vars/k8s_par1/kubernetes.yml` (`k8s_version`, `k8s_image_pause`) et `cluster/kubeadm-config.yaml` ; dépôts `pkgs.k8s.io` **par mineure** ; outils de `adm01` par le rôle `outils_k8s`.
- Cilium : release `cilium` de `plateforme/k8s` (`releases/10-reseau.yaml.gotmpl`, espace `kube-system`). Une montée de **mineure** de Cilium suit son guide de montée (contrôle préalable compris) ; une corrective se fait par la même release.
- Nœuds : `k8s-cp01-03` (2141-2143), `k8s-w01-03` (2144-2146, `k8s-w03` porte le taint `dedie=bdd`) ; VMs créées par l'état OpenTofu `envs/k8s` de `plateforme/infra` (module `vm-noeud`), préparées par `task noeuds` dans `plateforme/k8s` ; image dorée par `plateforme/images`.
- Bases : `mediagenda-db` (recette, prod) avec PDB gérées par CloudNativePG ; RabbitMQ (grappe `rabbitmq`, espace `messagerie`) ; Kyverno et Capsule posent des webhooks à « Fail ».
- La fiche **CHG-3404** porte la mesure (en-tête). Le check lit la décision de CHG-3403 : issue « go » = tous les kubelets dans la mineure cible ; issue « no-go » = Cilium homogène et au moins un travailleur **remplacé** (objet `Node` créé après la décision).

**Travail demandé**

Objectifs :
1. Préparer : fiche CHG-3404 (objectif d'interruption fixé avant), MR de versions prêtes, contrôles **avant le go** (santé, sauvegardes, PDB, webhooks, Applications, bases, files quorum) et **avant chaque drain** — outille-les, tu les rejoueras à chaque fenêtre.
2. Exécuter l'issue décidée en S03, un nœud à la fois, sous la sonde, avec un journal horodaté.
3. Remettre le code en accord avec la réalité (versions fusionnées après, rôles rejoués sans changement), régénérer et republier le paquet `schemas-crd`, aligner les outils de `adm01`.
4. Écrire RB-341 « monter Kubernetes (ou remplacer un nœud) sous la sonde ».

Contraintes :
- Jamais deux nœuds hors service en même temps ; jamais de drain forcé (`--disable-eviction`) ni de PDB supprimée « pour passer ».
- Aucun primaire PostgreSQL tué : la bascule se fait par l'opérateur.
- Pas de mineure de Kubernetes que le CNI en place ne déclare pas.
- Retour arrière écrit pour chaque étape, y compris « après le point de non-retour ».

**Critères de réussite**
- [ ] Tous les nœuds sont `Ready`, aucun n'est cordonné, une seule version de kubelet ; Cilium est sain et homogène, au moins à sa corrective de référence.
- [ ] Issue « go » : kubelets et `kubeadm-config` dans la mineure cible, le code (`kubeadm-config.yaml`, `kubernetes.yml`) la décrit, `kubectl` de `adm01` à ±1 mineure. Issue « no-go » : un travailleur a été remplacé après la décision, et aucun nœud n'est passé dans la mineure refusée.
- [ ] CHG-3404 : la mesure recalculée sur la fenêtre déclarée est couverte, sous l'objectif, et égale à ce que tu as noté ; la charge de la sonde tournait ; `schemas-crd` a été republié après le début de la montée.
- [ ] RB-341 est publié.

**Vérification** : `lab/bin/check F4 4`

<details><summary>Indice 1</summary>

Un drain ne fait qu'**évincer** : il demande, pod par pod, et l'API refuse quand une PDB l'interdit. Avant de drainer un nœud, regarde quels pods il porte, quelles PDB les couvrent et combien de perturbations elles autorisent ; un pod couvert par **deux** PDB ne s'évince pas du tout.
</details>

<details><summary>Indice 2</summary>

CloudNativePG documente le cas : quand le nœud qui porte le primaire est cordonné, l'opérateur bascule vers une réplique **avant** que le drain ne l'atteigne. Lis la page « Kubernetes Upgrade and Maintenance » de ta version (et ce qu'elle dit de `nodeMaintenanceWindow`). Côté RabbitMQ, regarde ce que fait le pré-arrêt (*preStop*) des pods créés par le Cluster Operator.
</details>

<details><summary>Indice 3</summary>

Remplacer un travailleur « à l'identique » par OpenTofu, c'est demander le remplacement d'**une** ressource de l'état (`-replace` sur son adresse, lue par `tofu state list`) : relis le plan, NetBox et le DNS ne doivent pas bouger. La nouvelle VM rejoint par `task noeuds` ; pense à tout ce qui la rend semblable aux autres (carte du VLAN 30, étiquettes de zone, inscription à l'annuaire, certificat de service du kubelet).
</details>

**Pour aller plus loin** (facultatif) : remplacer les trois travailleurs au fil des fenêtres standard et mesurer l'écart ; `UpgradeConfiguration` v1beta4 ; Cluster API (M18) comme moteur de remplacement immuable.

---

### F4-S05 — Monter les composants de plateforme par GitOps  `LIBRE` `★★★`

> **Ticket CHG-3405** — *De : Karim Benali* — *Copie : Sophie Laurent*
> Argo CD 3.6, Kyverno 1.20, CloudNativePG 1.31 : si elles sont publiées, on les prend ce trimestre ; sinon, les dernières correctives, plus une mineure d'un autre composant qui est prête (KEDA ou cert-manager, par exemple — la matrice de S03 te dira lequel débloque la suite). Trois montées au moins, par MR, une vague à la fois. Et lis les notes de version avant, pas après : Kyverno 1.20 supprime `ClusterPolicy`, CNPG 1.31 supprime `barmanObjectStore`.

**Objectifs pédagogiques**
- Monter des composants par le chemin GitOps du M20 (miroir des charts, Application, ou Helmfile pour la couche de base) avec lecture préalable des suppressions d'API.
- Ordonner : CRD avant contrôleurs, une vague par composant, mesurée.
- Choisir et écrire le bon retour arrière (revert Git, *rollback* d'Argo CD, CRD qui ne redescendent pas).

**Prérequis** : F4-S03, F4-S04 ; M20 (Argo CD, `charts-miroir`, Helmfile de la couche de base, ADR-0200), M26 (Kyverno, politiques CEL), M16 et M27 (CNPG, plugin Barman Cloud, RB-164), M28 (KEDA).
**Durée indicative** : 4 à 5 h.

**Contexte technique**
- Avant F4 : Argo CD 3.5.5 (chart `argo/argo-cd` 10.10.5, **release Helmfile** `argocd` de `plateforme/k8s`) ; Kyverno 1.19.2 (chart 3.9.2, Application `kyverno` de `plateforme/gitops`) ; CloudNativePG 1.30.1 (chart 0.29.1, release Helmfile `cnpg`) et plugin Barman Cloud 0.15.1 ; KEDA 2.21 (Application `keda`) ; cert-manager 1.21 (Helmfile).
- Charts tiers sous Argo CD : recopiés et signés dans Harbor `charts/` par `plateforme/charts-miroir` (`charts.yaml` : nom, dépôt, version, empreinte, usage).
- La fiche **CHG-3405** porte la mesure. Le check compte les composants dont l'image en service a dépassé sa version d'avant F4 (version exacte quand elle est connue, sinon mineure).

**Travail demandé**

Objectifs :
1. Pour chaque composant retenu : lecture des notes de version (toutes les versions sautées), inventaire **dans le cluster** des objets qui utilisent une API supprimée, valeurs du chart relues contre la nouvelle version, décision écrite dans la fiche.
2. Au moins **trois** montées, dont au moins une de **mineure**, chacune par MR (miroir puis GitOps, ou Helmfile), en vagues séparées et mesurées.
3. Après : Applications saines, fonction de chaque composant **essayée** (une politique qui refuse, une base qui archive, un `ScaledObject` qui réagit), matrice de S03 mise à jour, `schemas-crd` republié.
4. RB-342 « monter un composant de plateforme ».

Contraintes :
- Aucun chart tiré d'Internet par Argo CD ; aucune montée hors MR.
- Aucune vague pendant une promotion d'application en prod (fenêtre annoncée aux équipes).
- Les anciennes versions restent disponibles (miroir) jusqu'à la clôture.

**Critères de réussite**
- [ ] Au moins trois composants tournent au-delà de leur version d'avant F4, dont au moins une montée de mineure.
- [ ] Toutes les Applications du projet `plateforme` sont `Synced/Healthy` ; aucune `ClusterPolicy` ; aucun `Cluster` CNPG avec `barmanObjectStore` ; tous les `Cluster` CNPG sains.
- [ ] CHG-3405 (notes de version, CRD, miroir, retour arrière) et sa mesure sont conformes ; RB-342 est publié.

**Vérification** : `lab/bin/check F4 5`

<details><summary>Indice 1</summary>

Argo CD ne se met pas à jour par Argo CD chez MédiSphère : relis l'ADR-0200 (frontière de la couche de base). CloudNativePG non plus. Les autres passent par deux MR : le miroir, puis la référence de version dans l'Application.
</details>

<details><summary>Indice 2</summary>

Une CRD montée ne redescend pas avec le revert : si la nouvelle version a changé la version **stockée** d'un type, les objets restent dans cette version. Avant de monter, lis si la version précédente du contrôleur accepte les CRD de la nouvelle ; c'est ce qui dit si ton retour arrière en est un.
</details>

**Pour aller plus loin** (facultatif) : Renovate (M13) configuré pour ouvrir les MR de `charts-miroir` et de `plateforme/gitops` ensemble, avec le lien des notes de version ; vagues de synchronisation Argo CD pour imposer « CRD avant contrôleur » quand un projet livre ses CRD à part.

---

### F4-S06 — Panne : la montée qui bloque  `BF` `★★★★`

> **Ticket INC-6006** — *De : Karim Benali*
> Fenêtre de montée en cours, travailleur suivant, et tout se grippe. Je ne relance rien tant qu'on n'a pas compris : la fenêtre se ferme dans une heure, et je ne veux ni forcer ni casser la recette. Lance `lab/bin/break F4 6` : je te décris ce que je vois.

**Objectifs pédagogiques**
- Diagnostiquer, sous la pression d'une fenêtre, ce qui bloque une opération de maintenance du cluster : éviction, admission, synchronisation GitOps.
- Réparer sans contourner les protections (pas de drain forcé, pas de suppression aveugle) et prévenir le retour du problème.

**Prérequis** : F4-S04 (contrôles avant drain), M14 (drain, PDB), M26 (webhooks d'admission), M20 (Argo CD), M29 (composant `validation`).
**Durée indicative** : 30 à 45 min de diagnostic, plus le post-mortem.

**Contexte technique**
- Le lab doit être sain avant l'injection : tous les nœuds `Ready` et aucun cordonné, au moins deux pods prêts de l'API MédiAgenda en recette, Application de la recette `Synced/Healthy`. La panne ne touche que la recette, `wb-essais` et des objets créés pour elle ; jamais la production.
- Injection : `lab/bin/break F4 6` (depuis `adm01`) ; le symptôme s'affiche. Abandon : `lab/bin/break F4 6 --annuler`.
- Post-mortem attendu : `docs/changements/post-mortems/INC-6006-<sujet>.md`.

**Travail demandé**
1. Lance `lab/bin/break F4 6` et lis le symptôme de Karim.
2. Diagnostique et répare.
3. Écris le post-mortem INC-6006 (chronologie, détection, cause, réparation, prévention : qu'est-ce qui, dans tes contrôles de S04 ou dans la CI, l'aurait arrêté avant la fenêtre ?).

**Critères de réussite**
- [ ] Aucun nœud cordonné ; aucune PDB d'un espace applicatif n'interdit toute éviction (hors PDB gérées par CloudNativePG) ; aucun webhook d'admission « Fail » sans point d'accès prêt ; aucune Application Argo CD en erreur de comparaison ou de synchronisation ; aucun manifeste de `mediagenda/deploiement` dans une version d'API retirée.
- [ ] Le post-mortem INC-6006 est publié (cause, prévention).

**Vérification** : `lab/bin/check F4 6`
**Temps cible** : 45 min.

<details><summary>Indice 1</summary>

Pars du symptôme, pas d'une hypothèse : ce qui « ne finit pas » ou « ne se crée pas » a toujours laissé une trace dans l'API — un message du drain, un événement sur le contrôleur qui n'arrive pas à créer, un état et une condition sur l'Application.
</details>

<details><summary>Indice 2</summary>

Trois mécanismes peuvent dire non pendant une montée : la **politique d'éviction** (PDB), l'**admission** (webhooks), et le **dépôt** que GitOps applique. Pour chacun, demande-toi qui a ajouté quoi récemment (historique Git, `metadata.managedFields`, étiquettes et annotations des objets).
</details>

<details><summary>Indice 3</summary>

Réparer, c'est retirer ou corriger la cause **par le bon chemin** : un objet créé à la main se retire à la main (et se trace), un objet d'un dépôt se corrige par une MR. Le nœud que Karim a laissé cordonné ne doit repartir qu'une fois la cause levée.
</details>

---

### F4-S07 — Monter Ceph sous charge  `LIBRE` `★★★`

> **Ticket CHG-3407** — *De : Sophie Laurent* — *Copie : Claire Morel*
> L'audit HDS demande des systèmes maintenus. Pour `ceph-par1`, deux cas : si une corrective Tentacle plus récente que la 20.2.4 est publiée, on la passe par l'orchestrateur ; sinon, on met à jour le système Rocky Linux 10 des trois hôtes, un à la fois. Le cluster sert les volumes de nos bases et le stockage objet de nos journaux et de nos métriques : rien ne doit s'arrêter, et la sonde le prouvera.

**Objectifs pédagogiques**
- Mettre à jour un stockage distribué **en service** : corrective par `ceph orch upgrade`, ou maintenance des hôtes en roulement.
- S'appuyer sur les garde-fous du cluster (ok-to-stop, mode maintenance de cephadm, `noout`) plutôt que sur la chance.
- Mesurer l'effet sur les consommateurs réels (RBD des PVC, RGW de Loki et Thanos).

**Prérequis** : F4-S02 ; M08-E26 (RB-082), M08-E25 (sauvegarde PBS `par1/ceph`), M16 (ceph-csi), M21-M22 (Thanos et Loki sur le RGW).
**Durée indicative** : 4 h, dont une fenêtre de 3 h.

**Contexte technique**
- `ceph-par1` : `ceph01-03` (2081-2083), Rocky Linux 10, cephadm, Podman ; image et paquets dans `plateforme/ansible` (`ceph_image` dans `group_vars/env_m08/ceph.yml`, `ceph_noeud_version` dans `group_vars/role_ceph/ceph_noeud.yml`, paquets `cephadm` et `ceph-common` épinglés) ; RGW derrière l'ingress de cephadm (VIP 10.10.30.200, `rgw.par1.medisphere.internal`).
- Consommateurs : PVC `ceph-rbd` de `k8s-par1` (bases CNPG, RabbitMQ, Prometheus), compartiments RGW `thanos-k8s-par1`, `loki-k8s-par1`, `tempo-k8s-par1`. Cinder ne se mesure que si le profil openstack tourne (il ne tourne pas en même temps que le cluster).
- La fiche **CHG-3407** porte dans son en-tête une clé **`variante: ceph-orch`** ou **`variante: systeme`** (lue par le check) et la mesure.

**Travail demandé**

Objectifs :
1. Choisir la variante (notes de version, avis de sécurité, mises à jour système en attente) et l'écrire.
2. Ajouter à la sonde ce qui manque pour **ce** changement (le stockage objet), préparer les filets, et exécuter sous la sonde : par l'orchestrateur (échelonné, mesuré), ou un hôte à la fois par du code (pas de commandes tapées hôte par hôte).
3. Vérifier après : santé, aucun drapeau de maintenance oublié, aucune mise à jour en attente ou en cours, autoscaler actif, code à jour.
4. RB-343 « Ceph sous charge ».

Contraintes :
- Jamais deux hôtes indisponibles ; l'hôte suivant seulement après `HEALTH_OK`.
- Aucune intervention manuelle sur un démon pendant que l'orchestrateur travaille.
- Paquets `cephadm` et `ceph-common` : ne changent qu'avec `ceph_noeud_version`.

**Critères de réussite**
- [ ] `ceph-par1` en `HEALTH_OK`, aucun drapeau `noout`/`norebalance`/… resté posé, aucune mise à jour de l'orchestrateur en cours, autoscaler actif sur tous les pools.
- [ ] Variante `ceph-orch` : une seule version, postérieure à 20.2.4, décrite dans `plateforme/ansible`. Variante `systeme` : chaque hôte a redémarré pendant la fenêtre et n'a plus de mise à jour en attente.
- [ ] CHG-3407 : mesure conforme, charge présente pendant la fenêtre, RBD, RGW, garde-fous et retour arrière écrits ; RB-343 est publié.

**Vérification** : `lab/bin/check F4 7`

<details><summary>Indice 1</summary>

cephadm sait mettre un hôte **en maintenance** : il vérifie que l'arrêt de ses démons est sans danger, protège ses OSD contre le marquage *out* et les arrête ; la sortie de maintenance les relance. Regarde ce qu'il refuse, et pourquoi le mgr actif est un cas particulier.
</details>

<details><summary>Indice 2</summary>

Une sonde HTTPS sur le point d'entrée S3 dit si un RGW répond derrière la VIP ; elle ne dit pas si Loki ou le sidecar de Thanos ont échoué à écrire. Leurs journaux et leurs métriques d'envoi le disent.
</details>

**Pour aller plus loin** (facultatif) : faire de la mise à jour mensuelle des hôtes un changement **standard** (minuterie, playbook, mesure automatique dans une fiche courte).

---

### F4-S08 — Monter OpenStack de 2026.1 à 2026.2  `LIBRE` `★★★★`

> **Ticket CHG-3408** — *De : Claire Morel* — *Copie : Karim Benali, Julien Petit*
> La série 2026.2 est sortie fin septembre. On passe notre cloud dessus avec la procédure officielle de Kolla-Ansible, pas une réinstallation. Pour la mémoire, le cluster Kubernetes sera arrêté pendant la fenêtre ; si le profil OpenStack a été détruit depuis le M10, tu le reconstruis depuis le code avant. Les instances doivent continuer de répondre sur leur IP flottante, et je veux le mesurer. Si Kolla-Ansible 23 n'est encore qu'en version candidate quand tu t'y mets, on **répète** et on décide par écrit.

**Objectifs pédagogiques**
- Conduire une montée de **série** OpenStack par Kolla-Ansible (environnement Python neuf, mots de passe, `pull`, `prechecks`, `upgrade`).
- Préserver un chemin de retour (environnement et images de l'ancienne série, sauvegarde de la base).
- Mesurer la continuité du plan de données quand l'outillage habituel (cluster, Prometheus du cluster) n'est pas disponible.

**Prérequis** : F4-S02 ; M10-E03 (projet `uv`), M10-E25 (sauvegarde de la base, PBS `par1/openstack`), M10-E28 (RB-101, mise à jour dans une série), M10-E46 (`outils/deployer.sh`, étiquettes `deploye-*`).
**Durée indicative** : 7 à 9 h, dont une fenêtre de 6 h (samedi).

**Contexte technique**
- Avant F4 : OpenStack 2026.1, Kolla-Ansible 22.2.0, ansible-core 2.20 (contrainte de la 22 : < 2.21), projet `uv` de `plateforme/openstack` (`~/src/openstack`), `globals.yml` (`openstack_release: "2026.1"`, `kolla_base_distro: "debian"`), `passwords.yml` chiffré (Ansible Vault, identité `critique`), inventaire `inventaire/multinode`, configuration `--configdir etc/kolla`.
- Nœuds `osctl01`, `oscmp01-02` (2101-2103) ; état OpenTofu `openstack` ; `ceph-par1` démarré et en `HEALTH_OK`.
- La plage d'ansible-core change à chaque série : lis-la dans la documentation de la **cible** (« Operating Kolla », *Upgrade procedure*) et dans les notes de version 23.x.
- Mémoire : `k8s-par1` **arrêté** pendant toute la fenêtre (ordre de `lab/topologie.md`). Mesure : Prometheus **témoin** de `mon01` seulement (`mesure-source: temoin`), restreinte aux sondes de l'IP flottante (`mesure-groupes`). Les sondes `continuite-openstack*` visent une instance témoin `sonde-fip01` (projet `plateforme`) sur son IP flottante `<FIP-SONDE>`.
- La fiche **CHG-3408** porte `decision: go` (production montée) ou `decision: no-go` (Kolla 23 en version candidate : répétition seulement).

**Travail demandé**

Objectifs :
1. Préparer sans rien interrompre : notes de version (Kolla-Ansible et chaque service déployé), prise en charge de Debian 13, environnement Python **séparé** de celui de la 2026.1, dépendances Ansible, inventaire et `globals.yml` comparés aux exemples de la nouvelle version, mots de passe des nouveaux services ajoutés sans changer les existants (fichier chiffré), MR prête.
2. Le jour J : libérer la mémoire, remettre le profil openstack en état (ou le reconstruire), sauvegarder la base et l'envoyer sur PBS, poser l'instance témoin et ses sondes, mesurer la ligne de base, puis la montée de série par la procédure officielle, déployée par le chemin tracé du M10.
3. Vérifier (services, agents, volumes, répartiteur OVN, Horizon, images en série 2026.2), relever la mesure, rendre la mémoire au cluster.
4. RB-344 « monter OpenStack de série ».

Contraintes :
- Jamais `--limit` pour une montée ; jamais d'ansible-core hors de la plage de la série.
- Les images de l'ancienne série restent présentes jusqu'à la clôture ; l'environnement 2026.1 reste utilisable.
- Pas de version candidate en production.

**Critères de réussite**
- [ ] Issue « go » : `uv.lock` de `plateforme/openstack` (main) épingle Kolla-Ansible 23.x et un ansible-core de la plage exigée ; `openstack_release` vaut 2026.2 ; une étiquette `deploye-*` a été posée pendant la fenêtre ; avec le profil démarré, services de calcul, de réseau et de volume sains et conteneurs en images 2026.2. Issue « no-go » : la production reste en 22.x, la répétition et la condition de reprise sont écrites.
- [ ] CHG-3408 : mesure prise par le témoin, restreinte aux sondes de l'IP flottante, conforme ; `k8s-par1` arrêté, sauvegarde PBS, `prechecks` et IP flottante écrits ; RB-344 publié.

**Vérification** : `lab/bin/check F4 8` (les contrôles de services sont ignorés, et dits ignorés, si le profil openstack est arrêté au moment du check)

<details><summary>Indice 1</summary>

La procédure officielle commence par une phrase importante : elle vaut pour un passage **de série à série**, pas pour une mise à jour dans une série (RB-101). Elle demande de lire les notes de version, de mettre à jour Kolla-Ansible **et** Ansible, les dépendances, l'inventaire, `globals.yml`, puis les mots de passe par deux outils fournis par Kolla, avant `pull`, `prechecks` et `upgrade`.
</details>

<details><summary>Indice 2</summary>

`uv` fait un environnement par **dossier** de projet. Un second arbre de travail Git du même dépôt (sur la branche de la montée) a son propre `.venv` : l'ancien reste prêt pour un retour arrière, sans jongler avec des versions dans un même environnement.
</details>

<details><summary>Indice 3</summary>

Les outils de Kolla qui fusionnent les mots de passe lisent des fichiers **en clair**. Ton `passwords.yml` est chiffré : prévois où le clair existe (en mémoire, droits restreints), combien de temps, et comment tu prouves qu'aucune valeur existante n'a changé.
</details>

**Pour aller plus loin** (facultatif) : un registre Harbor qui reçoit les images Kolla de la série cible avec des étiquettes immuables datées ; la montée SLURP (sauter une série) et ce qu'elle impose à RabbitMQ.
