# Module 16 — Palier 5 : Mini-projet

Le module a raccordé `k8s-par1` à `ceph-par1`, comparé Rook et Longhorn, sauvegardé et restauré des espaces de noms, installé PostgreSQL sous CloudNativePG, puis cassé et réparé tout cela. Il reste à le **livrer** : les données de MédiAgenda et de MédiDoc vivent désormais dans le cluster, sont sauvegardées hors du cluster, et l'équipe sait les restaurer en un temps connu. Les essais (Rook, Longhorn, leurs disques) disparaissent, les pannes du palier 4 ont laissé des runbooks, et la politique de sauvegarde dit aux équipes ce qu'elles peuvent attendre. C'est ce que Claire Morel présentera comme « données Kubernetes MédiSphère v1 », et ce que les modules suivants consommeront : packaging (M17), GitOps (M20), supervision (M21), secrets (M25), données et messagerie (M27), plan de reprise (F5).

---

### M16-E46 — Mini-projet : données Kubernetes MédiSphère v1  `LIBRE` `★★★`

> **Ticket PLAT-1746** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent, Nadia Roussel, Julien Petit*
> Recette « données Kubernetes v1 » dans deux semaines. Je veux un contrôle global sans un seul rouge et **rien de provisoire** : plus de Rook, plus de Longhorn, plus de disques d'essai sur les travailleurs, plus de panne ouverte. MédiAgenda tourne en recette avec sa base sous CloudNativePG et son cache persistant, MédiDoc range ses documents dans le RGW de `ceph-par1`, et tout est sauvegardé hors du cluster, avec des restaurations **faites et chronométrées** pour cette livraison.
> Pendant la revue : Karim relira `plateforme/k8s` et rejouera le pipeline ; Sophie relira l'ADR-0160, la politique de sauvegarde, le registre des secrets et la matrice des flux ; Nadia te donnera une heure de la journée et te demandera de restaurer `mediagenda-db` à cet instant, pendant que Julien supprimera l'espace `medidoc-dev` « par erreur » et attendra son retour. Format habituel : 10 minutes de présentation, les démonstrations, nos questions.

**Objectifs pédagogiques**
- Consolider les briques du module en un service de données cohérent, décrit par le code et sans dette provisoire.
- Garantir la restaurabilité des données de MédiSphère dans le cluster, la prouver par des restaurations mesurées, et l'écrire dans une politique.
- Livrer l'état `k8s-stockage-v1` : documentation, flux, supervision en ligne de commande, étiquette de version.

**Prérequis** : M16-E01 à M16-E45 (au minimum tous les `LAB`, `LIBRE`, `BF` et le `CHRONO`) ; mini-projets M14-E46 (`k8s-v1`), M15-E46 (`k8s-reseau-v1`) et M08-E46 (`stockage-v1`).
**Durée indicative** : 14 à 20 h, plus 30 min de revue.

**Contexte technique**
- Cluster `k8s-par1` (PLAN.md §4.10) : travailleurs `k8s-w01-03` (2144-2146) avec leur carte VLAN 30 (10.10.30.81-83, MTU 9000, M16-E05) ; ceph-csi 3.18 (espace `ceph-csi`), classes `ceph-rbd` (par défaut), `ceph-rbd-retain`, `cephfs`, classes d'instantanés `ceph-rbd-snap` et `cephfs-snap`, external-snapshotter 8.6.
- `ceph-par1` (M08) : pool `k8s-rbd`, identité `client.k8s` (et l'identité CephFS que tu as retenue au M16-E07), RGW `https://rgw.par1.medisphere.internal` (VIP 10.10.30.200), compte RGW `medidoc-app` du M08 et ses identifiants dans `~/.config/workbook/s3-medidoc-app.env`, compartiment `medidoc-documents`.
- `s3-01` (M05) : compartiments `velero-k8s-par1` (compte `velero`) et `cnpg-k8s-par1` (compte `cnpg`).
- Applications : MédiAgenda (`mediagenda-recette`, publiée en `https://mediagenda-recette.apps.par1.medisphere.internal`, M15), base `mediagenda-db` (CloudNativePG 1.30, PostgreSQL 18, plugin Barman Cloud 0.15, `ObjectStore` `cnpg-s3`), Valkey en StatefulSet ; MédiDoc (`medidoc-dev`, M14-E33 et M15-E34), qui écrit encore ses documents dans le compartiment `medidoc-dev` de `s3-01` (Secret `medidoc-s3`, politique de sortie `medidoc-sortie` du M15-E34).
- Le contrôle global `lab/bin/check 16 46` vérifie le stockage du cluster et le réseau de stockage des travailleurs, l'**absence** de Rook, de Longhorn, de leurs disques et de panne ouverte, la base et sa sauvegarde continue, les applications, Velero, les objets du consommateur Kubernetes dans `ceph-par1`, la documentation et la livraison. Il prend quelques minutes.

**Travail demandé**
1. **Rien de provisoire.** Rook et Longhorn sont retirés selon leurs procédures officielles (aucun espace, aucune CRD, aucune classe, aucun reste sur les nœuds) ; les disques de comparaison (`ssd-lab` et `hdd-bulk`) sont retirés des travailleurs **par OpenTofu** (état `k8s`), et leurs traces dans la configuration des nœuds par Ansible ; les objets de test des paliers précédents (`exploration`, restaurations, clusters PostgreSQL d'essai, témoins du palier 4 s'ils ne servent plus) sont supprimés ou justifiés ; aucune panne M16 active.
2. **Stockage du cluster.** ceph-csi RBD et CephFS complets sur les trois travailleurs ; classes et classes d'instantanés conformes à la décision de l'ADR-0160 ; toutes les valeurs, classes, quotas par équipe et scripts de création des Secrets (depuis Vault, jamais dans le dépôt) décrits dans `plateforme/k8s` et appliqués par `task`, pipeline vert ; les droits de `client.k8s` (et de l'identité CephFS) identiques à `allocations.yaml` de `plateforme/ceph`.
3. **MédiAgenda.** API en recette avec au moins deux répliques, branchée sur `mediagenda-db` par le Secret généré par CloudNativePG ; `mediagenda-db` à trois instances sur `ceph-rbd`, PostgreSQL 18, réplication et bascule vérifiées ; Valkey en StatefulSet sur un volume persistant ; l'ensemble décrit dans le dépôt de déploiement de l'équipe (ou dans `plateforme/k8s` en attendant le M17).
4. **Sauvegarde continue de la base.** WAL archivés en continu vers `cnpg-k8s-par1` par le plugin Barman Cloud (aucun `barmanObjectStore` intégré), sauvegarde de base planifiée et réussie, rétention écrite dans la politique ; **restauration à un instant donné réalisée pour cette livraison** dans un nouveau cluster, chronométrée, avec la comparaison des données attendues et obtenues.
5. **MédiDoc.** MédiDoc quitte `s3-01` (sans perdre les documents déjà déposés) et range ses documents dans `medidoc-documents` sur le RGW de `ceph-par1`, en HTTPS vérifié par la CA MédiSphère, avec les identifiants de `medidoc-app` dans un Secret (jamais dans un manifeste) ; ses documents survivent à la suppression de tous ses pods ; le chemin réseau du trafic S3 (carte VLAN 30 des travailleurs ou bordure) est choisi, justifié et décrit dans la matrice des flux.
6. **Velero.** Sauvegarde planifiée (au moins quotidienne) de `mediagenda-recette` et `medidoc-dev`, volumes compris selon la méthode décidée dans la politique (et sans faire de la copie de fichiers de la base sa sauvegarde) ; la dernière exécution est réussie ; **restauration réalisée pour cette livraison** (espace entier, dans `wb-restauration` ou à sa place d'origine), chronométrée.
7. **Exploitation.** `ms-verif-k8s-stockage` (M16-E27) planifiée et verte, avec les contrôles ajoutés au palier 4 ; RB-160 à RB-167 à jour ; journaux de diagnostic et post-mortem INC-4350 publiés.
8. **Documentation.** `docs/kubernetes/stockage/` : architecture (du PVC à Ceph et à S3, ce qui se passe quand un travailleur, un moniteur Ceph, `s3-01` ou le RGW tombent), ADR-0160, politique de sauvegarde (`politique-sauvegarde.md` : RPO et RTO par donnée, M16-E32), note `du-pvc-au-bloc.md`, procès-verbal de recette `recette-k8s-stockage-v1.md` (restaurations datées et chronométrées, RTO et RPO mesurés, écarts) ; matrice des flux (`docs/socle/matrice-flux.md`) et registre des secrets à jour (emplacements, jamais de valeurs).
9. **Livraison.** Tout est fusionné, les pipelines de `main` (`plateforme/k8s`, `plateforme/ceph`, `plateforme/ansible`, `plateforme/infra`, `plateforme/outils`, `plateforme/medisphere`) sont verts, et l'étiquette **`k8s-stockage-v1`** est posée sur `plateforme/medisphere`.
10. **La revue.** 10 minutes de présentation (architecture, choix et compromis de l'ADR-0160, ce qui n'est **pas** redondant), puis les démonstrations de Nadia (restauration à un instant donné) et de Julien (espace supprimé « par erreur »).

**Contraintes**
- Aucune perte de données pendant le retrait de Rook et de Longhorn : les volumes qui y vivent encore sont migrés (M16-E29) ou déclarés jetables par écrit avant le retrait.
- Aucun secret dans un dépôt, un journal de CI, un manifeste ou la documentation : des **emplacements**, jamais des valeurs.
- Tout ce qui est créé l'est par le code (OpenTofu, Ansible, valeurs Helm et manifestes de `plateforme/k8s`) ; une intervention manuelle exceptionnelle est consignée et reportée dans le code.
- Les démonstrations se font sans le corrigé et sans lire les scripts de panne ; les choix qui s'écartent d'un exercice du module sont justifiés (ADR ou description de MR).

**Critères de réussite**
- [ ] `lab/bin/check 16 46` est entièrement vert.
- [ ] Démonstration de Nadia : `mediagenda-db` restaurée à l'heure donnée dans un nouveau cluster, données vérifiées, temps mesuré et inférieur au RTO de la politique.
- [ ] Démonstration de Julien : `medidoc-dev` recréé par Velero avec ses objets, MédiDoc relit un document déposé avant la suppression, temps mesuré.
- [ ] Le procès-verbal de recette contient les deux restaurations de la livraison et les deux démonstrations, avec RTO et RPO mesurés.
- [ ] La revue est passée (auto-évaluation avec la grille du corrigé si tu travailles seul).

**Vérification** : `lab/bin/check 16 46`

<details><summary>Indice 1</summary>

Lance `lab/bin/check 16 46` dès le début : la liste des points rouges est ton plan de travail. Les contrôles détaillés (`lab/bin/check 16 XX`) donnent le détail par brique ; `lab/bin/check 15 46` et `lab/bin/check 08 46` revérifient le réseau et `ceph-par1`.
</details>

<details><summary>Indice 2</summary>

Ordre conseillé : d'abord une sauvegarde complète et vérifiée de ce qui existe, puis le retrait des essais (qui libère mémoire et disques), puis les restaurations de la livraison, et la documentation en dernier — elle décrit ce qui existe, pas ce qui est prévu.
</details>

<details><summary>Indice 3</summary>

Pour MédiDoc, deux points font échouer `/readyz` sans message évident : la CA ajoutée par `MEDIDOC_CA_FILE` et le chemin réseau du pod vers 10.10.30.200 (adresse source vue par le RGW, route de retour). Teste depuis un pod jetable du même espace avant d'accuser l'application.
</details>

**Pour aller plus loin** (facultatif) : une démonstration « reconstruire tout le stockage du cluster depuis le code » sur `k8s-par1` vidé de ses composants de stockage (ceph-csi, snapshotter, Velero, CloudNativePG), puis restauration de `mediagenda-recette` depuis `s3-01`, chronométrée : c'est l'ébauche du plan de reprise du final F5.
