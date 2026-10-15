# Module 14 — Palier 5 : Mini-projet

Le module a construit, exploité, cassé et réparé `k8s-par1`. Il reste à le **livrer** comme une brique de la plateforme : un cluster 1.36 décrit par le code et reconstructible, dont la haute disponibilité a été éprouvée, dont etcd est sauvegardé et restaurable, où les équipes ont des identités, des droits, des quotas et des garde-fous d'admission, et où MédiAgenda tourne en recette depuis Harbor. Le nœud d'essai `k8s-w04` a disparu, les pannes du palier 4 ont laissé des runbooks, et la documentation dit aux modules suivants ce qu'ils trouvent et ce qui reste à faire. C'est ce que Claire Morel présentera à la DSI et à l'auditeur HDS comme « Kubernetes MédiSphère v1 ».

---

### M14-E46 — Mini-projet : Kubernetes MédiSphère v1  `LIBRE` `★★★`

> **Ticket PLAT-1546** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent, Nadia Roussel, Julien Petit*
> Recette de Kubernetes v1 dans deux semaines. Je veux un cluster qui passe le contrôle global sans un seul rouge, **sans rien de provisoire** (plus de `k8s-w04`, plus de panne ouverte, plus de taint oubliée), et prêt pour les modules qui arrivent : réseau (Cilium sans kube-proxy, BGP, Gateway API), stockage (ceph-csi), packaging, GitOps.
> Pendant la revue : Karim fera la revue de `plateforme/k8s` et de `plateforme/ansible`, puis reconstruira un travailleur depuis le code ; Sophie relira les identités, le RBAC, l'admission, l'audit, le chiffrement et le registre des secrets ; Nadia arrêtera le nœud de contrôle qui porte la VIP pendant ta présentation ; Julien fera tourner une boucle de requêtes sur MédiAgenda en recette pendant la panne de Nadia. Format habituel : 10 minutes de présentation, les démonstrations, nos questions.

**Objectifs pédagogiques**
- Consolider le cluster du module en une brique cohérente, pilotée par le code, sans dette provisoire.
- Prouver ce qui a été construit : haute disponibilité du plan de contrôle, sauvegarde et restauration d'etcd, cloisonnement des équipes, reconstruction d'un nœud.
- Livrer l'état `k8s-v1` : documentation, flux, sauvegardes, runbooks, étiquette de version, et ce que les modules 15 à 20 devront traiter.

**Prérequis** : M14-E01 à M14-E45 (au minimum tous les `LAB`, `LIBRE`, `BF` et le `CHRONO`) ; `registre-v1` (M13-E25).
**Durée indicative** : 12 à 18 h, plus 30 min de revue.

**Contexte technique**
- Cluster `k8s-par1` (PLAN.md §4.10) : `k8s-cp01-03` (2141-2143, 10.10.40.51-53), `k8s-w01-03` (2144-2146, 10.10.40.61-63), API `https://k8s-api.par1.medisphere.internal:8443` (VIP 10.10.40.200), Kubernetes **1.36.x**, containerd 2.3, Cilium 1.20 avec kube-proxy conservé, metrics-server. `k8s-w04` (2147) **n'existe plus** à la livraison.
- Projets : `plateforme/k8s` (configuration du cluster, composants, espaces, RBAC, admission, outils, Taskfile), `plateforme/ansible` (rôles des nœuds), `plateforme/infra` (état OpenTofu `k8s`), `plateforme/medisphere` (documentation `docs/kubernetes/`).
- MédiAgenda en recette : espace `mediagenda-recette`, image du projet `medisphere` de Harbor (étiquette `v*` signée, ou digest), PostgreSQL et Valkey **jetables** (`emptyDir`) : le stockage persistant arrive au module 16, dis-le dans la documentation.
- Les témoins `wb-pannes` du palier 4 peuvent rester (ils ne gênent pas le contrôle) ou être supprimés après la recette.
- Le contrôle global `lab/bin/check 14 46` vérifie les nœuds et leurs versions, le point d'accès de l'API, etcd et ses sauvegardes, les certificats, la sécurité, les composants de plateforme, MédiAgenda en recette, l'absence de provisoire et la documentation livrée. Il prend quelques minutes.

**État livré `k8s-v1`** — ce que les modules 15 à 29 trouveront en entrant, tel que les exercices du module l'ont construit. Rien de ce tableau ne doit manquer, rien ne doit porter un autre nom.

| Élément | État attendu à la livraison |
|---|---|
| Nœuds | `k8s-cp01-03` et `k8s-w01-03` en **1.36.x** (kubelet, kubeadm, kubectl épinglés, dépôt pkgs.k8s.io v1.36), containerd.io 2.3.x (image *pause* de kubeadm 1.36, miroirs `hosts.toml` vers les caches Harbor), carte `eth0` ; zones `topology.kubernetes.io/zone` `par1-baie-a/b/c` ; `k8s-w03` étiqueté `medisphere.internal/dedie=bdd` avec la taint `dedie=bdd:NoSchedule` ; certificats de service des kubelets signés par la CA du cluster (`serverTLSBootstrap: true`) ; aucun nœud cordonné ; `k8s-w04` (2147) détruit |
| Plan de contrôle | etcd empilé, trois membres ; VIP 10.10.40.200 (keepalived VRID 140, suivi d'HAProxy) et HAProxy 8443 → 6443 ; audit (`/etc/kubernetes/audit/politique.yaml`, journaux `/var/log/kubernetes/audit/`, rotation bornée) ; Secrets chiffrés par `secretbox` (`/etc/kubernetes/chiffrement/configuration.yaml`, rechargement automatique) ; ces options dans `cluster/kubeadm-config.yaml` **et** le ConfigMap `kubeadm-config` |
| Sauvegarde | `etcd-instantane.timer` horaire sur les trois nœuds de contrôle → `s3-01`, compartiment `etcd-k8s-par1` (préfixe `horaire/`, chiffré par `age`, identité `etcd-k8s`) ; VMs dans `par1/k8s` de PBS ; RB-141 et un test de restauration chronométré |
| Composants (`kube-system`) | Cilium 1.20 (CLI cilium, `composants/cilium/values.yaml` : `kubeProxyReplacement: "false"`, VXLAN, IPAM `cluster-pool` 10.240.0.0/16, relais Hubble) ; **kube-proxy conservé** en mode `iptables` (le M15 le remplace) ; CoreDNS de kubeadm, deux réplicas, Corefile par défaut (transfert vers le résolveur des nœuds) ; metrics-server (chart 3.14.0, `composants/metrics-server/values.yaml`, **sans** `--kubelet-insecure-tls`) |
| Espaces de noms | `wb-system` (vérifications), `wb-essais` (essais, jetable, conservé pour les modules suivants), `wb-diagnostic` (`privileged`, vide), `mediagenda-dev`, `mediagenda-recette`, `medidoc-dev` (M14-E33) ; `wb-pannes` facultatif ; `wb-examen` supprimé |
| Garde-fous | ResourceQuota `quota-equipe` et LimitRange `limites-defaut` dans les espaces d'équipe ; Pod Security `restricted` appliqué sur `mediagenda-*` et `medidoc-dev`, `baseline` sur `wb-essais` ; ValidatingAdmissionPolicy et liaison `medisphere-images` en `Deny` (paramètres : ConfigMap `kube-system/medisphere-images`, clé `registres`), sélection par l'étiquette `medisphere.internal/equipe` ; PriorityClasses `medisphere-critique`, `medisphere-standard`, `medisphere-essai` |
| Identités et droits | groupes `medisphere:plateforme-admins` (`cluster-admin`), `medisphere:mediagenda-devs`, `medisphere:medidoc-devs`, `medisphere:lecture` ; ClusterRoles agrégées `medisphere-lecture` et `medisphere-developpeur` (étiquettes `rbac.medisphere.internal/agreger-vers-*`) ; ton identité personnelle (7 jours, `outils/kubeconfig-personnel.sh`) ; `admin.conf` et `super-admin.conf` en Vault `critique` seulement |
| Compte des vérifications | `wb-system/wb-checks`, jeton durable `wb-checks-jeton` (exception documentée), ClusterRole **agrégée** `wb-checks` : elle réunit toutes les ClusterRoles étiquetées `workbook.medisphere.internal/checks: "true"` (aujourd'hui `wb-checks-base`). Chaque module suivant qui installe des ressources nouvelles (CRD de Gateway API, cert-manager, ceph-csi…) ajoute **sa** ClusterRole de lecture étiquetée, sans toucher aux deux premières ni jamais accorder les Secrets (règle de `docs/kubernetes/acces.md`) |
| MédiAgenda | dans `mediagenda-dev` (manifestes `k8s/dev/`) et `mediagenda-recette` (`k8s/recette/`, M14-E21) de `mediagenda/api` : Deployment et Service `mediagenda-api` (étiquettes `app.kubernetes.io/name: mediagenda-api`, `app.kubernetes.io/part-of: mediagenda` ; Service ClusterIP en **port 80** vers le port nommé `http` = 8000 du conteneur ; compte `mediagenda-api`), PDB `mediagenda-api`, ConfigMap `mediagenda-api-config`, Secret `mediagenda-db` (clé `mot-de-passe`, hors dépôt), Secret de tirage `harbor-pull` porté par les comptes `default` et `mediagenda-api`, Job `mediagenda-migration-v1-0-0` ; PostgreSQL `postgresql` (Deployment jetable sur `k8s-w03`, `emptyDir`) et Valkey `valkey` (StatefulSet `valkey-0..2` derrière le Service sans tête `valkey`, `emptyDir`) : **jetables** jusqu'au M16 ; CronJob `mediagenda-sauvegarde` en dev |
| `adm01` | `~/.kube/config` (contexte `k8s-par1`), `~/.config/workbook/k8s-checks.kubeconfig`, `harbor-k8s-pull.env`, `s3-etcd.env` (tous en 600) ; kubectl 1.36, Helm 4.3, k9s, cilium, hubble, etcdctl/etcdutl de la version de l'etcd du cluster ; minuterie `k8s-certificats.timer` |
| Code et documentation | `plateforme/k8s` (`cluster/`, `composants/`, `espaces/`, `rbac/`, `admission/`, `ordonnancement/`, `gabarits/`, `outils/`, `secrets/`, `Taskfile.yml`, CI verte) ; rôles `containerd`, `k8s_noeud`, `k8s_plan_controle`, `k8s_travailleur`, `outils_k8s`, `etcd_instantane`, `k8s_audit`, `k8s_chiffrement` dans `plateforme/ansible` ; état `envs/k8s` dans `plateforme/infra` ; `docs/kubernetes/` (fiche du cluster, accès, architecture, ADR-0140/0141, RB-140 à RB-149, tests, post-mortem INC-4150), matrice des flux et registre des secrets à jour ; étiquette `k8s-v1` sur `plateforme/medisphere` |

**Travail demandé**
1. **Rien de provisoire.** `k8s-w04` est retiré proprement (drain, retrait du cluster, VM détruite par OpenTofu, objets NetBox et DNS retirés, fichiers du code nettoyés) ; aucune panne `M14` ouverte, aucune taint ni cordon laissés, aucun pod `Pending` qui traîne ; les ressources d'essai des paliers (pods, ConfigMaps et liaisons de `wb-essais`, CSR, jetons) sont supprimées ou justifiées.
2. **Le cluster par le code.** Version 1.36.x partout, configuration kubeadm v1beta4 dans `plateforme/k8s`, composants (Cilium, metrics-server, CoreDNS) et objets du cluster (espaces, quotas, RBAC, admission) appliqués par `task appliquer` sans écart (`kubectl diff` vide), nœuds préparés par les rôles Ansible sans dérive (`--check --diff` vide) ; pipeline de `main` vert.
3. **Haute disponibilité éprouvée.** VIP portée par un seul nœud, HAProxy et keepalived actifs partout, contrôle de santé suivi, certificats de service valables pour le nom et l'adresse de la VIP ; démonstration de Nadia répétée **avant** la revue et chronométrée (temps de bascule de la VIP, requêtes en échec pendant la bascule).
4. **etcd.** Trois membres sains, aucune alarme, instantané horaire envoyé vers `s3-01` et vérifié, VMs sauvegardées par PBS (`par1/k8s`), test de restauration **réalisé pour cette livraison** sur un environnement d'essai ou selon RB-141, chronométré et consigné (RTO, RPO) dans `docs/kubernetes/tests/`.
5. **Sécurité.** Identités personnelles par certificats courts, `admin.conf` et `super-admin.conf` en Vault `critique` seulement ; RBAC des trois groupes, aucun `cluster-admin` hors administration ; Pod Security `restricted` sur `mediagenda-*` ; politiques d'admission (registre, étiquettes) en `Deny` ; audit actif ; Secrets chiffrés au repos ; certificats du cluster valables plus de 30 jours et procédure de renouvellement (RB-143) ; registre des secrets à jour (emplacements, jamais les valeurs).
6. **MédiAgenda en recette.** Au moins deux réplicas disponibles derrière un Service, PDB, sondes conformes au contrat de l'application, demandes et limites, aucune image hors Harbor ni `latest` ; une boucle de requêtes **depuis le cluster** (pod de test dans l'espace) sert à la démonstration de Julien.
7. **Reconstructible.** Karim doit pouvoir reconstruire un travailleur depuis le code (M14-E23) : la procédure est dans RB-140 ou un document dédié, avec la durée mesurée.
8. **Documentation.** `docs/kubernetes/` : `architecture.md` (composants, réseaux, flux, ce qui se passe quand un nœud de contrôle, un travailleur, un membre etcd, la VIP, CoreDNS tombent, et ce qui n'est **pas** redondant), ADR-0140 et ADR-0141, runbooks RB-140 à RB-149, journal des pannes et post-mortem INC-4150 ; inventaire NetBox et matrice des flux à jour (VLAN 40 → `reg01` 443, `s3-01` 8333, `ca01` 443).
9. **Livraison.** Tout est fusionné, les pipelines de `main` sont verts, l'étiquette **`k8s-v1`** est posée sur `plateforme/medisphere`. La documentation liste ce que les modules 15 (kube-proxy remplacé, LB IPAM, BGP, Gateway API, NetworkPolicy), 16 (stockage persistant de MédiAgenda), 17 (Helm, Kustomize, Helmfile), 19-20 (CI et GitOps) et 21 (alertes tirées des pannes du palier 4) devront traiter.
10. **La revue.** 10 minutes de présentation (architecture, choix et compromis, limites), puis la démonstration de Nadia (arrêt du nœud de contrôle qui porte la VIP) pendant la boucle de Julien, et la reconstruction d'un travailleur par Karim.

**Contraintes**
- Jamais deux nœuds de contrôle arrêtés ou modifiés en même temps ; instantané etcd vérifié avant toute opération sur le plan de contrôle.
- Aucun secret dans un dépôt, un journal de CI ou la documentation : des **emplacements**, jamais des valeurs.
- Tout ce qui est créé l'est par le code (OpenTofu, Ansible, `plateforme/k8s`) ; une intervention manuelle exceptionnelle est consignée et reportée dans le code.
- Les choix qui s'écartent d'un exercice du module sont justifiés (ADR ou description de MR).

**Critères de réussite**
- [ ] `lab/bin/check 14 46` est entièrement vert.
- [ ] La démonstration de Nadia : la VIP bascule, l'API revient en moins de 10 s, la boucle de Julien ne perd aucune requête (le trafic entre pods ne passe pas par l'API), le nœud revenu rejoint sans intervention et etcd retrouve trois membres.
- [ ] Le test de restauration d'etcd est chronométré et consigné, avec RTO et RPO ; la reconstruction d'un travailleur est mesurée.
- [ ] La documentation dit ce qui n'est **pas** redondant et ce que les modules 15 à 21 devront traiter.
- [ ] La revue est passée (auto-évaluation avec la grille du corrigé si tu travailles seul).

**Vérification** : `lab/bin/check 14 46`

<details><summary>Indice 1</summary>

Lance `lab/bin/check 14 46` dès le début : la liste des points rouges est ton plan de travail. Les contrôles détaillés (`lab/bin/check 14 XX`) donnent le détail par brique ; `lab/bin/check 14 43` rejoue d'un coup toutes les vérifications du palier 4.
</details>

<details><summary>Indice 2</summary>

Fais la démonstration de Nadia **avant** les opérations de nettoyage du plan de contrôle : si quelque chose ne revient pas, tu as encore le temps et l'instantané. Pour la boucle de Julien, un pod qui appelle le Service de MédiAgenda (`/pret`) chaque seconde et journalise le code reçu suffit ; le profil `restricted` de l'espace s'applique aussi à lui.
</details>

<details><summary>Indice 3</summary>

« Ce qui n'est pas redondant » : un seul hyperviseur physique, une seule salle, un seul registre, un seul récurseur par site, PostgreSQL et Valkey jetables, la CA du cluster, les fichiers `admin.conf`. Écris pour chacun le risque et le module (ou le final) qui le traite.
</details>

**Pour aller plus loin** (facultatif) : un tableau de bord texte (préparé pour le module 21) qui résume, depuis `adm01`, l'état des nœuds, des membres etcd, de la VIP, de l'âge du dernier instantané et des certificats les plus proches de l'expiration ; une reconstruction complète du cluster sur des VMs jetables, chronométrée.
