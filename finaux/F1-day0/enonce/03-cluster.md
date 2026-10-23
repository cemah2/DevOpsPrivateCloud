# Final F1 — Phase 3 : Le cluster

La phase 2 a prouvé que le socle et l'usine savent refaire une machine. Le filet de la phase 1 est tendu : sauvegardes vérifiées de moins de 24 heures, inventaire de référence des données (`docs/day0/reference-avant.md`), fiche de go/no-go CHG-3104 et plan de retour arrière (`docs/day0/retour-arriere.md`). Claire Morel donne le go : la fenêtre **CHG-3107** s'ouvre. `k8s-par1` va être **détruit et reconstruit à blanc**, sur ses VMID d'origine, à partir du code seul. Pas d'instantané etcd restauré, pas de VM restaurée depuis PBS : ce sont les filets si tout échoue, pas le chemin.

Cette phase est la plus longue du final (25 à 35 heures, dont de longues attentes). Elle se découpe comme une vraie reconstruction : les nœuds (S07), la couche de base que Helmfile installe et Argo CD (S08), l'identité et les secrets (S09), la plateforme qu'Argo CD redéploie seule (S10), puis les données (S11). Un piège typique du Day 0 t'attend ensuite (S12).

## Règles de la fenêtre CHG-3107

- **Le code fait foi.** Tout ce qui se reconstruit passe par `plateforme/infra` (OpenTofu, état `envs/k8s`), `plateforme/ansible` (rôles et playbooks), `plateforme/k8s` (configuration kubeadm, Helmfile, espaces, RBAC, outils), `plateforme/secrets` et `plateforme/identite` (OpenTofu), `plateforme/gitops` et les dépôts de déploiement des équipes (Argo CD). Quand le code ne suffit pas, tu **corriges le code** par une MR (fusionnée dans la fenêtre si Karim l'approuve), tu ne contournes pas.
- **Gestes manuels = dette.** Un geste tapé à la main qui n'est pas dans un outil versionné est permis s'il débloque la reconstruction, mais il est **noté** dans la chronologie (heure, commande, raison) et devient une ligne de dette du rapport de S15. Le but n'est pas zéro geste, c'est zéro geste **caché**.
- **Chronomètre.** Chaque étape est horodatée (début, fin, attente comprise) dans `docs/day0/chronologie.md` de `plateforme/medisphere`. Le rapport de S15 compare ces durées à l'estimation de la carte d'amorçage de S01.
- **Communication.** Nadia Roussel a prévenu les centres de santé que la prise de rendez-vous en ligne est **indisponible** pendant la fenêtre. Tu lui donnes un point d'avancement à chaque fin de scénario (une ligne dans la chronologie suffit : « 14:05 — point Nadia : nœuds prêts, couche de base en cours »).
- **Point de non-retour.** Tant que les nœuds ne sont pas détruits, le no-go est un simple retour en service. Après, le retour arrière est la restauration PBS de `docs/day0/retour-arriere.md` : relis-le **avant** de détruire quoi que ce soit.
- **Données.** Rien n'est effacé côté `ceph-par1`, `s3-01` ni PBS pendant toute la phase : ni volume RBD, ni archive de WAL, ni sauvegarde Velero, ni instantané etcd. Une base qui naîtrait **vide** à la place de la base de production serait un incident, même si elle « marche ».
- **Mémoire.** Profil des blocs F et G (≈ 111 Go) ; `pxe01` reste allumé tant que `k8s-w03` n'est pas installé, puis il peut être arrêté.

> ⚠️ **Effets de bord** : pendant toute la phase, MédiAgenda (recette et production), MédiNotif, le portail, Grafana, Argo CD et tout ce qui vit dans le cluster sont **indisponibles**. Les sondes de `mon01` (Prometheus « témoin ») vont alerter : c'est attendu, mets-les en silence pour la durée de la fenêtre (Alertmanager témoin) et note-le. Les pipelines GitLab qui ont besoin des runners du cluster (`k8s`, `protege`) attendent : seuls `runner01` (shell) et `runner02` (docker) répondent tant que S08 n'est pas fini.

## Accès pendant la reconstruction

- Les **checks** de S07 à S14 lisent le cluster par le compte de service `wb-checks` (M14-E06) : son kubeconfig (`~/.config/workbook/k8s-checks.kubeconfig`) contient un jeton et une autorité de certification de l'**ancien** cluster. Tu le recrées dès que l'API du nouveau cluster répond (espace `wb-system`, ClusterRole agrégée et ses extensions `wb-checks-*`, puis l'outil du M14-E06).
- Ton accès personnel (contexte `k8s-par1`, OIDC par kubelogin, M24) suppose que le serveur d'API connaît Keycloak et que tes liaisons `oidc-*` existent ; avant cela, seul `admin.conf` du nouveau cluster entre. Le nouvel `admin.conf` remplace l'ancien dans le Vault `critique` (bris de glace, PLAN §4.10).
- Les outils et dépôts sont ceux de `adm01` : clones `~/src/infra`, `~/src/ansible`, `~/src/k8s`, `~/src/secrets`, `~/src/identite`, `~/src/gitops`, `~/src/deploiement` (MédiAgenda), `~/medisphere` (documentation).

---

### F1-S07 — Détruire et reconstruire les nœuds de `k8s-par1`  `LIBRE` `★★★★`

> **Fiche de changement CHG-3107** — *De : Claire Morel*
> Go donné sur CHG-3104. Fenêtre ouverte : Nadia a prévenu le support et les centres, la prise de rendez-vous en ligne est coupée. Tu détruis les six nœuds de `k8s-par1` et tu les refais **depuis le code**, sur les mêmes noms, adresses et VMID. `k8s-w03` passe par l'usine comme un serveur sorti du carton. Avant de détruire, je veux un gel propre : plus aucune écriture, plus aucun message en vol, et une dernière sauvegarde **après** le gel. Les anciens volumes de Ceph restent où ils sont tant que je n'ai pas lu ta décision écrite sur leur sort. Chronomètre tout.

**Objectifs pédagogiques**
- Geler une plateforme de production avant une opération destructive : écritures arrêtées, files vidées, dernier point de reprise **postérieur** au gel.
- Reconstruire un cluster kubeadm hautement disponible depuis OpenTofu et Ansible seuls, dans l'ordre que ses dépendances imposent (fichiers du serveur d'API avant l'amorçage, VIP avant les jonctions, durcissement et inscription à l'annuaire).
- Faire passer un nœud par la chaîne NetBox → PXE → Ansible → cluster au milieu d'une reconstruction.
- Mesurer chaque étape et décider du sort des données orphelines (volumes RBD de l'ancien cluster).

**Prérequis** : F1-S04 (`lab/bin/check F1 4` vert **dans les 24 heures** qui précèdent la destruction) ; F1-S06 (profil `k8s-noeud` de l'usine, `k8s-w03` préparé) ; modules 14 (kubeadm, rôles, VIP, etcd), 16 (carte VLAN 30 des travailleurs), 19 (travailleurs à 10 Go), 24 (authentification structurée, inscription FreeIPA), 26 (durcissement, pare-feu d'hôte, kubelets), 27 (gel des files, sauvegardes CNPG).
**Durée indicative** : 8 à 12 h (dont 1 h de gel et 2 à 3 h d'attente d'installation).

**Contexte technique**
- Nœuds : `k8s-cp01-03` (2141-2143, 10.10.40.51-53, 2 vCPU, 4 Go) et `k8s-w01-03` (2144-2146, 10.10.40.61-63, 4 vCPU, **10 Go**, carte VLAN 30 10.10.30.81-83 MTU 9000) ; MAC `bc:24:11:40:00:<suffixe>` ; état OpenTofu **`envs/k8s`** de `plateforme/infra` (module `vm-noeud`). `k8s-w03` suit le chemin préparé en F1-S06 : VM créée vide en démarrage réseau sur le VLAN 60, installée par `pxe01` (profil `k8s-noeud`), puis passée sur le VLAN 40.
- Cluster : kubeadm et Kubernetes **1.36.5**, containerd.io **2.3.x**, configuration kubeadm v1beta4 de `plateforme/k8s/cluster/kubeadm-config.yaml` (sans kube-proxy depuis M15), VIP de l'API **10.10.40.200:8443** (`k8s-api.par1.medisphere.internal`, keepalived VRID 140 + HAProxy sur les trois nœuds de contrôle), Pods 10.240.0.0/16, Services 10.96.0.0/16.
- Playbooks de `plateforme/ansible` (noms des corrigés des modules) : `k8s-noeuds.yml` (rôles `containerd`, `k8s_noeud`), `k8s-api-fichiers.yml` (audit, chiffrement des Secrets, authentification structurée OIDC), `k8s-cluster.yml` (`k8s_plan_controle`, `k8s_travailleur` ; l'amorçage d'un cluster neuf ne se fait que si `k8s_plan_controle_amorcage_auto` est vrai), `k8s-reseau-stockage.yml` (carte VLAN 30 : il attend des nœuds `Ready`), `k8s-etcd-instantane.yml`, `inscription-ipa.yml` (un hôte à la fois), `durcissement.yml` (vagues ; les nœuds sont dans la vague 6). Les nœuds n'ont ni node_exporter ni Alloy système : ce sont des DaemonSets du cluster.
- Les données des applications sont protégées **hors** du cluster : WAL et sauvegardes de base dans `s3://cnpg-k8s-par1/` (recette sous `mediagenda-db`, production sous `mediagenda-db-prod`, portail sous `portail-db`), sauvegardes Velero dans `velero-k8s-par1`, définitions RabbitMQ dans `messagerie-definitions`. Les volumes RBD des PVC sont dans le pool `k8s-rbd` de `ceph-par1`.
- La production de MédiAgenda est mise à l'échelle par un HPA sur le Rollout `mediagenda` (M28) ; MédiNotif de production par KEDA, au moins une réplique.

**Contraintes**
- **Gel** avant toute destruction : plus aucune écriture dans `mediagenda-db` (recette et production) ni `portail-db` ; file `notifications` **vide** dans `medinotif-recette` et `medinotif-prod` (les messages ont été consommés, pas purgés) ; une sauvegarde de base CNPG **réussie après le gel** pour chacune des trois bases ; le segment de WAL courant archivé ; les compteurs du gel (rendez-vous en production et en recette, messages en file, ExternalSecrets, certificats) relevés et ajoutés à la référence. L'écart avec `reference-avant.md` (écritures entre S04 et le gel) est expliqué.
- Destruction et recréation **par OpenTofu** (`envs/k8s`), sur les mêmes VMID, noms, adresses et MAC ; NetBox et le DNS restent justes pendant et après. Aucune VM recréée à la main dans Proxmox.
- Préparation **par Ansible** uniquement (CI ou `adm01`, comme au M14), dans un ordre qui ne casse rien : aucun serveur d'API ne démarre avec une option qui vise un fichier absent ; les nœuds sont inscrits dans FreeIPA et durcis (score de conformité publié) **avant** la fin du scénario (leur supervision et leurs journaux sont des DaemonSets du cluster : ils reviennent en S10) ; le pare-feu d'hôte de Cilium n'est pas encore en jeu (pas de CNI avant S08).
- L'amorçage du cluster neuf est un **geste explicite** (variable d'Ansible) et unique : jamais deux `kubeadm init`.
- Pas de restauration d'etcd ni de VM : c'est une reconstruction à blanc. L'instantané etcd horaire reprend sur le nouveau cluster.
- Rien n'est supprimé dans `ceph-par1` : les images RBD et sous-volumes CephFS de l'ancien cluster restent. Tu écris **une décision** sur leur sort (garder combien de temps, comment les reconnaître, qui décide de la purge, par quelle procédure réversible).
- Le compte `wb-checks` et son kubeconfig sont recréés dès que l'API répond.

**Livrables**
- Six nœuds neufs, enregistrés dans le nouveau cluster (ils resteront `NotReady` jusqu'au CNI de S08), plan de contrôle à trois membres etcd, une et une seule VIP.
- `docs/day0/chronologie.md` : une ligne horodatée par étape (gel, destruction, création des VMs, installation de `k8s-w03`, chaque playbook, amorçage, jonctions), avec la durée et les gestes manuels marqués comme tels ; les points donnés à Nadia.
- `docs/day0/volumes-ancien-cluster.md` : inventaire des volumes orphelins (nombre, taille, comment on les reconnaît), décision et procédure de purge réversible, date de revue.
- Les MR éventuelles (correctifs de code découverts pendant la reconstruction), citées dans la chronologie.

**Critères de réussite**
- [ ] Les VMs 2141 à 2146 existent, tournent, et ont été **créées après** une sauvegarde PBS récente de l'ancienne VM de même VMID ; `k8s-w03` a été installée par l'usine (journaux de l'installateur présents) et sa carte est sur le VLAN 40.
- [ ] Le cluster est **neuf** (créé après le filet de S04, il y a moins de 30 jours) ; six nœuds en Kubernetes 1.36 ; trois serveurs d'API avec audit, chiffrement des Secrets et authentification structurée ; trois membres etcd.
- [ ] Exactement un nœud de contrôle porte 10.10.40.200 ; l'API répond par la VIP.
- [ ] Les six nœuds sont inscrits dans FreeIPA et ont un score de conformité publié (fichier du collecteur textfile) ; l'instantané etcd horaire est actif sur les nœuds de contrôle.
- [ ] `chronologie.md` et `volumes-ancien-cluster.md` sont publiés sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check F1 7`

<details><summary>Indice 1</summary>

Pour le gel, demande-toi ce qui écrit encore : l'API de MédiAgenda (et son HPA, qui remettrait des réplicas), MédiNotif qui consomme, les tâches planifiées, les sauvegardes elles-mêmes. Un HPA ne fait rien sur une cible à zéro réplique. Une base sans écriture n'archive pas son dernier segment de WAL tant qu'on ne le lui demande pas, et une sauvegarde lancée **avant** le dernier écrit ne prouve rien.
</details>

<details><summary>Indice 2</summary>

« Détruire et recréer » une VM sans toucher aux objets NetBox et DNS que le même module gère : regarde la liste des ressources de l'état et l'option de remplacement ciblé du plan plutôt qu'une destruction. Pour `k8s-w03`, relis ce que ton code de F1-S06 dit du passage d'un nœud **existant** à l'usine. Côté Ansible, relis l'en-tête de `k8s-api-fichiers.yml` et celle du rôle `k8s_plan_controle` : l'ordre y est écrit.
</details>

<details><summary>Indice 3</summary>

Les PV de `ceph-rbd` ont une politique `Delete`, mais personne ne les a supprimés : le cluster a disparu avant. Leurs images portent le préfixe `csi-vol-` et ceph-csi garde leur correspondance dans un objet omap du pool. Une purge réversible existe dans RBD (la corbeille, avec un délai).
</details>

**Pour aller plus loin** (facultatif) : chronomètre aussi le chemin de retour arrière **sans le faire** : combien de temps pour restaurer les six VMs depuis PBS sur ton datastore (débit mesuré d'une restauration de test en S04) ? C'est le vrai délai de décision du no-go.

---

### F1-S08 — La couche de base et Argo CD  `LIBRE` `★★★`

> **Ticket PLAT-3108** — *De : Karim Benali*
> Les nœuds sont là, `NotReady`. Maintenant tout ce que Helmfile tient dans `plateforme/k8s` : réseau, certificats, DNS, stockage, opérateurs de données, sauvegarde, métriques, CI, et Argo CD au bout. Le dépôt dit « une reconstruction applique les fichiers dans l'ordre des noms » : on va voir si c'est vrai. Chaque fois que l'ordre écrit ne marche pas, corrige le dépôt, pas ta mémoire. Et pas de secret dans un fichier, ni dans l'historique de ton terminal.

**Objectifs pédagogiques**
- Remonter une couche de base complète depuis Helmfile en respectant les dépendances cachées : CRD avant contrôleurs, CNI avant tout, émetteur de certificats avant ses clients, webhooks prêts avant leurs objets.
- Casser la boucle « les composants ont besoin de secrets, le distributeur de secrets est installé par Argo CD, qui a besoin de secrets » par un **amorçage** explicite, minimal et tracé.
- Retrouver la publication réseau (BGP, LB IPAM, Gateway, DNS, certificats) sans toucher à la bordure.

**Prérequis** : F1-S07 ; modules 15 (Cilium, BGP, Gateway, ExternalDNS, cert-manager), 16 (ceph-csi, Velero, CNPG, plugin Barman Cloud), 17 (Helmfile de `plateforme/k8s`), 19 (runners, BuildKit, agent GitLab), 20 (Argo CD sous Helmfile), 25 (inventaire des secrets, ce qui est resté en amorçage), 26 (kubelets en `serverTLSBootstrap`, pare-feu d'hôte).
**Durée indicative** : 4 à 6 h.

**Contexte technique**
- Helmfile 1.8 : `helmfile.yaml` inclut `releases/*.yaml.gotmpl` (`10-reseau`, `20-certificats-dns`, `30-stockage`, `40-observabilite`, `50-ci`, `argocd`), environnement `par1`, contexte `k8s-par1`. Hors Helmfile mais dans le dépôt : CRD Gateway API v1.6.1 (`composants/gateway-api/`), contrôleur de snapshots (Kustomize, `composants/snapshot-controller/`), objets LB IPAM et BGP (`composants/cilium/`), émetteurs, espaces (`espaces/`), RBAC (`rbac/`), étiquettes et taints des nœuds (`cluster/noeuds.yaml`), politiques d'hôte (`composants/cilium/hote/`).
- Réseau : Cilium 1.20 en remplacement de kube-proxy, BGP (AS 65040 ↔ `gw01`/`gw02` AS 65000), pool `lb-par1` 10.10.41.10-199, Gateway `gw-par1` (espace `passerelles`, 10.10.41.10, certificat joker `apps-joker`) ; cert-manager 1.21 (ClusterIssuer `step-ca-acme`, DNS-01 RFC 2136 clé `certmanager-k8s`) ; ExternalDNS (propriétaire `k8s-par1`, clé `externaldns-k8s`).
- Stockage : ceph-csi 3.18 vers `ceph-par1` (pool `k8s-rbd`, identités `client.k8s` et `client.k8s-cephfs`, StorageClasses `ceph-rbd` par défaut, `ceph-rbd-retain`, `ceph-rbd-chiffre`, `cephfs`) ; CloudNativePG 1.30 et son plugin Barman Cloud (espace `cnpg-system`) ; Velero 1.18 (emplacement `s3-01`, compartiment `velero-k8s-par1`).
- Les valeurs secrètes de la couche de base (clés TSIG, clés cephx, identités S3, jetons des runners et de l'agent, identifiants des dépôts d'Argo CD) sont dans OpenBao (`kv/plateforme/…`) depuis M25-E46, livrées par External Secrets Operator… qu'Argo CD installe. La méthode `k8s-par1` d'OpenBao connaît encore l'**ancienne** autorité du cluster : c'est l'objet de S09.
- Les kubelets demandent leur certificat de service à l'API (`serverTLSBootstrap: true`, M26-E25) ; leur approbateur automatique est une Application d'Argo CD.

**Contraintes**
- Tout composant de la couche de base est installé par **Helmfile** ou par une tâche du dépôt ; versions et valeurs du dépôt, rien en ligne de commande. Si un fichier de `releases/` ou une tâche est faux ou mal ordonné, la correction est une MR de `plateforme/k8s`.
- **Aucune base de données ne naît vide.** Tant que S11 n'a pas décrit la récupération des bases, rien ne doit créer `mediagenda-db` (recette, production) ni `portail-db`, ni le réplica de secours : regarde ce qu'appliquent tes tâches avant de les lancer.
- **Amorçage des secrets** : un seul outil versionné dans `plateforme/k8s` crée, depuis OpenBao et avec **ta** session OIDC, les Secrets dont la couche de base a besoin avant ESO ; aucune valeur sur la ligne de commande, dans un fichier ou dans l'historique ; chaque Secret ainsi créé porte une marque qui le distingue, et chacun sera repris par son `ExternalSecret` en S09 (mêmes noms, mêmes clés). La liste de ce qui passe par l'amorçage est la plus courte possible et justifiée.
- Une demande de certificat de kubelet n'est approuvée qu'après vérification de son demandeur et de ses noms ; tracée dans la chronologie tant que l'approbateur automatique n'est pas revenu.
- Le pare-feu d'hôte est réactivé nœud par nœud par l'outil du M26, plan de contrôle compris, sans couper etcd ni le VRRP de la VIP.
- Argo CD est installé et lit ses dépôts, mais l'application racine n'est **pas** encore créée (S10).

**Livrables**
- Couche de base en place, nœuds `Ready`, publication `*.apps` rétablie.
- L'outil d'amorçage des secrets et sa liste, dans `plateforme/k8s` (MR), et la section « amorçage » de `chronologie.md` (quels Secrets, lus par qui, quand).
- L'ordre **réel** de reconstruction de la couche de base, corrigé dans le dépôt (README, Taskfile ou script) s'il différait de l'ordre écrit.

**Critères de réussite**
- [ ] Six nœuds `Ready` ; Cilium sans kube-proxy, WireGuard actif ; deux sessions BGP établies par nœud ; `gw-par1` programmée sur 10.10.41.10 ; `step-ca-acme` et `apps-joker` prêts ; ExternalDNS en service.
- [ ] ceph-csi, snapshots, CNPG et son plugin, Velero (emplacement `s3-01` disponible), metrics-server (API `metrics.k8s.io` disponible) opérationnels ; les StorageClasses attendues existent, `ceph-rbd` par défaut.
- [ ] Runners `gitlab-runner` et `gitlab-runner-protege`, `buildkitd`, agent GitLab et Argo CD prêts ; `https://argocd.apps.par1.medisphere.internal` répond.
- [ ] Les politiques d'hôte de Cilium existent et les six nœuds portent l'étiquette du pare-feu d'hôte.
- [ ] Aucune base CNPG n'existe encore (ou alors déjà sur un amorçage par récupération).

**Vérification** : `lab/bin/check F1 8`

<details><summary>Indice 1</summary>

Lis les commentaires de tes fichiers `releases/` : certains disent pourquoi `needs:` ne traverse pas les fichiers, d'autres pourquoi une release attend un Secret avant son premier `apply` (et `rollbackOnFailure` attend que tout soit prêt). Fais la liste des Secrets attendus **par release** avant de lancer quoi que ce soit, en partant de `inventaire-secrets.md` du M25.
</details>

<details><summary>Indice 2</summary>

Sans certificat de service des kubelets, la lecture des journaux des pods, l'exécution dans un conteneur et metrics-server échouent alors que les nœuds sont `Ready`. La liste des demandes de certificat montre des demandes `kubernetes.io/kubelet-serving` en attente. Que vérifie l'approbateur du M26 avant d'approuver ? Fais au moins la même chose.
</details>

<details><summary>Indice 3</summary>

Un ExternalSecret dont la cible est `creationPolicy: Owner` prend possession d'un Secret existant **qui n'a pas de propriétaire** (c'est ainsi qu'ESO a repris les Secrets de `secrets-k8s.sh` au M25-E13). L'amorçage peut donc créer des Secrets de mêmes nom et clés que ceux que les ExternalSecrets produiront : ils seront adoptés. ESO ne retire que les étiquettes qu'il gère lui-même : ta marque, elle, reste jusqu'à ce que tu l'enlèves, une fois l'adoption prouvée.
</details>

**Pour aller plus loin** (facultatif) : mesure séparément l'attente « images » (premier tirage par le cache Harbor) et l'attente « contrôleurs » (webhooks prêts) : la première se réduit par un préchargement, la seconde seulement par un meilleur ordre.

---

### F1-S09 — Raccrocher l'identité et les secrets  `LIBRE` `★★★★`

> **Ticket SEC-3109** — *De : Sophie Laurent*
> Un cluster neuf, c'est une autorité de certification neuve, des comptes de service neufs, et un coffre qui ne reconnaît plus personne. Je veux que la confiance soit refaite **par le code**, pas en désactivant une vérification « le temps que ça marche ». À la fin : OpenBao fait confiance au nouveau cluster et à lui seul, ESO a repris tous les Secrets d'amorçage, les personnes entrent par le SSO avec les mêmes droits qu'avant, et il ne reste aucun Secret créé par une personne dans le cluster.

**Objectifs pédagogiques**
- Identifier tout ce qui, hors du cluster, référence son ancienne identité (autorité de certification, jetons, kubeconfig) et le mettre à jour par le code.
- Remettre en route la chaîne OpenBao → ESO → Secrets, et prouver qu'elle a repris ce que l'amorçage avait posé.
- Rétablir l'authentification OIDC et l'autorisation par groupes du cluster, et la vérification des signatures d'images.

**Prérequis** : F1-S08 ; modules 24 (Keycloak, client `kubernetes`, authentification structurée, liaisons `oidc-*`, kubelogin), 25 (méthode `k8s-par1`, ESO, ClusterSecretStore `openbao`, SecretStores `openbao` par espace, pipeline de `plateforme/secrets`), 26 (Kyverno et la clé publique Cosign, robots Harbor).
**Durée indicative** : 3 à 5 h.

**Contexte technique**
- Méthode `kubernetes` d'OpenBao montée en **`k8s-par1`**, décrite dans `plateforme/secrets` (`tofu/auth-k8s-par1.tf`, fournisseur `hashicorp/vault` ~> 5.13, état S3 `secrets`) : hôte `https://k8s-api.par1.medisphere.internal:8443`, autorité du cluster lue dans un fichier du dépôt, **pas** de jeton de relecture dédié (OpenBao présente le jeton du client à l'API TokenReview), audience `openbao.medisphere.internal`, rôles `eso-plateforme` et `eso-<espace>`.
- ESO 2.13 (Application `external-secrets`, espace `external-secrets`), ClusterSecretStore `openbao` (espaces de plateforme), SecretStore `openbao` par espace applicatif (compte `eso`, liaison `openbao-auth-delegator`) ; ExternalSecrets des espaces de plateforme dans `plateforme/gitops/secrets/` (Application `secrets-plateforme`), ceux des applications dans leurs dépôts de déploiement.
- Kubernetes : `AuthenticationConfiguration` (`/etc/kubernetes/authentification/config.yaml`, émetteur `https://sso.par1.medisphere.internal/realms/medisphere`, audience `kubernetes`, préfixes `oidc:`), liaisons `oidc-*` et ClusterRoles `medisphere-*` dans `plateforme/k8s/rbac/` ; kubelogin 1.36 sur `adm01`.
- Kyverno 1.19 : `ImageValidatingPolicy` `exiger-signature-medisphere` (clés publiques dans la politique, robot Harbor `robot$medisphere+kyverno` livré par ESO) ; tirage des images par les robots `robot$k8s-pull` et `harbor-pull` des espaces.

**Contraintes**
- La confiance d'OpenBao envers le cluster change **par une MR de `plateforme/secrets`** appliquée par son pipeline ; aucune écriture directe dans `auth/k8s-par1/` ; aucune vérification désactivée (TLS, audience, comptes liés).
- Aucune valeur de secret ne repasse par un terminal pendant ce scénario ; les Secrets d'amorçage de S08 sont **tous** adoptés par leur ExternalSecret (prouve-le), aucun ne reste orphelin.
- Les personnes retrouvent exactement leurs droits d'avant (mêmes groupes, mêmes ClusterRoles) ; ton accès quotidien est OIDC, pas `admin.conf`.
- L'ancien `admin.conf` (et `super-admin.conf`) ne vaut plus rien : les nouveaux les remplacent dans le Vault `critique`, l'inventaire des secrets est mis à jour.
- Rien à désactiver dans Kyverno pour « faire passer » les déploiements de S10.

**Livrables**
- MR de `plateforme/secrets` (autorité du nouveau cluster), pipeline réussi.
- Chaîne ESO opérationnelle, liste des Secrets d'amorçage avec leur ExternalSecret repreneur (dans `chronologie.md`).
- Kubeconfigs à jour : le tien (OIDC), `admin.conf` dans le Vault `critique`, celui de `wb-checks`.
- Mise à jour de `docs/securite/secrets/inventaire-secrets.md` (autorité `k8s-par1`, `admin.conf`).

**Critères de réussite**
- [ ] L'autorité configurée dans `auth/k8s-par1/config` d'OpenBao est **celle du cluster actuel**.
- [ ] Le ClusterSecretStore `openbao` et tous les SecretStores sont prêts ; **tous** les ExternalSecrets du cluster sont `Ready`.
- [ ] Les serveurs d'API utilisent l'authentification structurée ; les liaisons `oidc-*` existent et visent des groupes `oidc:` ; le client `kubernetes` de Keycloak est actif.
- [ ] La politique `exiger-signature-medisphere` est prête dans le cluster (si Kyverno est déjà revenu ; sinon, elle le sera en S10).

**Vérification** : `lab/bin/check F1 9`

<details><summary>Indice 1</summary>

Quand OpenBao reçoit une connexion de la méthode `k8s-par1`, il appelle l'API TokenReview **du cluster** en TLS. Avec quelle autorité vérifie-t-il le certificat de l'API ? Où cette autorité est-elle écrite dans `plateforme/secrets` ? La configuration de la méthode, lue avec ta session, te montre ce qu'il croit.
</details>

<details><summary>Indice 2</summary>

Pour prouver l'adoption : un Secret adopté porte une `ownerReference` vers son ExternalSecret ; un Secret d'amorçage resté orphelin porte encore ta marque et aucun propriétaire. Une seule lecture des Secrets de tout le cluster, filtrée sur ta marque et avec une sortie personnalisée, suffit.
</details>

<details><summary>Indice 3</summary>

Le serveur d'API du nouveau cluster n'a rien appris de Keycloak : il lit le même fichier d'authentification structurée, posé par le même rôle. Ce qui a changé, c'est ce que **ton** kubeconfig croit du serveur, et ce que le cluster sait des liaisons de groupes.
</details>

**Pour aller plus loin** (facultatif) : écris le test qui aurait trouvé l'autorité périmée avant la fenêtre : un job planifié de `plateforme/secrets` qui compare l'autorité de `auth/k8s-par1/config` à celle publiée par le cluster (ConfigMap `kube-root-ca.crt`) et échoue si elles diffèrent.

---

### F1-S10 — Laisser Argo CD reconstruire la plateforme  `LIBRE` `★★★`

> **Ticket PLAT-3110** — *De : Karim Benali*
> On a passé un an à tout mettre dans `plateforme/gitops`. Aujourd'hui, on vérifie : tu crées l'application racine, une fois, et tu laisses Argo CD faire. Supervision, journaux, traces, sécurité, autoscaling, locataires, portail, messagerie, chaos, charge. Chaque fois qu'il bloque, la correction est un commit, pas un `kubectl`. Je relirai les MR.

**Objectifs pédagogiques**
- Reconstruire une plateforme complète par GitOps à partir d'un seul objet créé à la main.
- Lire et corriger l'ordre de synchronisation (vagues, CRD, webhooks, dépendances entre Applications) quand il échoue sur un cluster vide.
- Distinguer ce qui revient seul (l'état déclaré) de ce qui doit être remis (les données, S11).

**Prérequis** : F1-S09 ; modules 20 (application racine, AppProjects, ApplicationSets, vagues, `plateforme/charts-miroir`), 21 à 23 (observabilité), 26 (Kyverno, Falco, Tetragon, kubelet-csr-approver), 27 à 29 (RabbitMQ, KEDA, VPA, Capsule, Backstage, k6-operator, Chaos Mesh).
**Durée indicative** : 4 à 6 h (dont l'attente de convergence).

**Contexte technique**
- `plateforme/gitops` : `racine/` (application racine qui se gère elle-même, et les groupes `projets`, `plateforme`, `applications`), `projets/`, `plateforme/` (une Application par service), `applications/` (ApplicationSets `mediagenda`, `medidoc`, `medinotif`, `labo`), `secrets/`, `valeurs/` ; charts tiers depuis Harbor `charts/` uniquement.
- La racine se crée **une seule fois** à la main (M20-E06) ; tout le reste vient d'elle.
- `dev` et `recette` se synchronisent automatiquement, `prod` à la main. Les données (bases CNPG, files) ne sont pas l'objet de ce scénario : les Applications qui en dépendent (`mediagenda-recette`, `mediagenda-prod`, `portail`) peuvent rester non saines jusqu'à S11, **mais rien ne doit créer une base vide à leur place**.
- La supervision à long terme est dans le RGW de `ceph-par1` (Thanos, Loki, Tempo, Pyroscope) : rien n'y a été effacé.

**Contraintes**
- Un seul objet créé à la main : l'application racine (plus, si tu l'as fait en S09, les deux Applications d'amorçage d'ESO, qu'Argo CD reprend sans les recréer).
- Toute correction passe par une MR (`plateforme/gitops`, `plateforme/politiques`, `plateforme/donnees`, dépôts de déploiement…), avec le motif dans la chronologie.
- Aucune synchronisation forcée qui supprime des objets d'une autre Application ; aucun `Replace=true` ni suppression de CRD.
- La production ne se synchronise pas dans ce scénario.

**Livrables**
- Plateforme reconstruite ; `chronologie.md` complétée (durée de convergence, Applications bloquées, cause et correctif de chacune).
- Si l'ordre n'était pas bon : vagues ou dépendances corrigées dans `plateforme/gitops` (MR).

**Critères de réussite**
- [ ] L'application racine existe ; toutes les Applications sont `Synced` et `Healthy`, sauf celles qui attendent leurs données (S11), qui existent.
- [ ] Prometheus, Alertmanager, Grafana, Loki répondent ; l'historique d'avant la reconstruction est encore lisible dans la vue globale de Thanos.
- [ ] Kyverno, Falco, Tetragon, l'approbateur des certificats de kubelets, KEDA, VPA, Capsule (locataires `mediagenda`, `medidoc`, `medinotif`), RabbitMQ (grappe de trois nœuds), k6-operator et Chaos Mesh sont en service.
- [ ] Aucune demande de certificat de kubelet en attente.

**Vérification** : `lab/bin/check F1 10`

<details><summary>Indice 1</summary>

Sur un cluster vide, une Application dont les objets dépendent d'une CRD installée par **une autre** Application échoue au premier essai (« no matches for kind ») puis réussit au suivant, si sa politique réessaie. Lis `status.operationState` et `status.conditions` des Applications bloquées avant de toucher à quoi que ce soit.
</details>

<details><summary>Indice 2</summary>

Un webhook d'admission qui n'est pas encore prêt bloque des objets **d'autres** Applications. Quels composants posent des webhooks en `Fail` (Kyverno, Capsule, cert-manager, CNPG, ESO…) ? Leur ordre d'arrivée compte plus que celui des applications.
</details>

**Pour aller plus loin** (facultatif) : compte les objets créés par Argo CD (`argocd.argoproj.io/tracking-id`) et compare le temps de convergence au nombre d'objets : où passe le temps, dans Argo CD, dans les tirages d'images ou dans les sondes de disponibilité ?

---

### F1-S11 — Remettre les données  `LIBRE` `★★★★`

> **Ticket PLAT-3111** — *De : Nadia Roussel*
> Pour les centres de santé, il n'y a qu'une question : est-ce que leurs rendez-vous sont toujours là ? Je veux pouvoir répondre « oui, tous, voilà la preuve », avec le même nombre qu'au gel. Et je veux que la base de secours suive de nouveau la production avant que tu rouvres le service : on ne repart pas sans filet.

**Objectifs pédagogiques**
- Recréer des bases PostgreSQL de production depuis leur archive (CloudNativePG `bootstrap.recovery` par le plugin Barman Cloud), sans écraser l'archive d'origine.
- Rebrancher tout ce qui dépend de l'identité d'une base (autorité TLS propre au cluster CNPG, connexion d'OpenBao, réplica de secours).
- Remettre la messagerie (topologie déclarative, définitions exportées) et le cache, et prouver l'intégrité des données par comparaison à la référence.

**Prérequis** : F1-S10 ; modules 16 (récupération CNPG, Velero), 25 (moteur `db-mediagenda`, autorités des bases copiées sur `vault01-03`), 27 (bases approfondies, réplica de secours, RabbitMQ, Valkey), 28 (`portail-db`).
**Durée indicative** : 4 à 6 h.

**Contexte technique**
- Bases : `mediagenda-db` de recette (`plateforme/k8s/espaces/mediagenda-recette/50-mediagenda-db.yaml`, appliqué par `kubectl apply`, exception écrite), de production (`mediagenda/deploiement`, `components/dependances` + correctifs de `overlays/prod`, Argo CD, synchronisation manuelle), `portail-db` (`plateforme/k8s/espaces/portail/`) ; ObjectStore `cnpg-s3` dans chaque espace, compartiment `s3://cnpg-k8s-par1/`, `serverName` d'archivage : `mediagenda-db` (recette), `mediagenda-db-prod` (production), `portail-db` ; base `mediagenda` (propriétaire `mediagenda`) et base `portail` (propriétaire `portail`) ; PostgreSQL 18.6, même image qu'avant.
- Réplica de secours `mediagenda-db-secours` (espace `mediagenda-secours`, `kubectl apply`, exception écrite), alimenté par l'archive de la production.
- Le moteur `db-mediagenda` d'OpenBao se connecte aux primaires par 10.10.41.64 (recette) et 10.10.41.65 (production) en `sslmode=verify-ca`, avec l'autorité **propre à chaque cluster CNPG** copiée sur `vault01-03` (`/etc/openbao/postgresql/mediagenda-<env>-ca.crt`, rôle `openbao`, fichiers de `plateforme/ansible`).
- RabbitMQ : topologie déclarative de `plateforme/donnees/topologie/` (vhosts `medinotif-recette`, `medinotif-prod`, file quorum `notifications`, rebut) ; export nocturne des définitions dans `messagerie-definitions` de `s3-01` (RB-275 §4). Valkey de MédiAgenda : cache, repart vide.
- La CRD `Cluster` de CNPG ne lit `bootstrap` qu'à la création.

**Contraintes**
- **Aucune perte** : nombre de rendez-vous en production et en recette **identique** à celui relevé au gel (S07) ; aucun message perdu (la file était vide au gel) ; les identifiants dynamiques de MédiAgenda refonctionnent.
- **L'archive d'origine reste intacte** : aucune base reconstruite n'écrit sous le `serverName` dont elle a été récupérée ; aucune vérification de sécurité de CNPG désactivée.
- Récupération décrite **dans le code** (dépôts des bases), appliquée par le chemin habituel de chaque base (Argo CD pour la production, `kubectl apply` pour les exceptions écrites).
- Le réplica de secours suit de nouveau la production (nouveau `serverName`) et une sauvegarde de base **neuve** existe pour chacune des trois bases avant la réouverture.
- Velero ne sert qu'en appoint, objet par objet, pour ce qui n'est pas déclaratif : jamais une restauration complète d'un espace (elle ramènerait des objets liés à l'ancien cluster).
- La réouverture du service (MédiAgenda en production synchronisé et à l'échelle normale) est annoncée par Nadia et notée dans la chronologie : c'est la **fin de la coupure**, à mesurer.

**Livrables**
- Correctifs de récupération dans les dépôts (MR), bases saines, archivage actif sous les nouveaux noms, secours reraccroché.
- `docs/day0/donnees-apres.md` : tableau de comparaison avec la référence (au moins une ligne `| rendez-vous (prod) | <au gel> | <après> |` et la même pour la recette), messages en file, ExternalSecrets, certificats, et ce qui a été restauré par Velero (ou « rien »), avec la méthode de comptage.
- `chronologie.md` complétée, dont l'heure de réouverture.

**Critères de réussite**
- [ ] Les trois bases sont saines, issues d'une récupération, archivent sous un `serverName` **nouveau**, et ont une sauvegarde `completed` postérieure à leur récupération ; leurs sauvegardes planifiées existent.
- [ ] `mediagenda-db-secours` est sain, en réplica, et suit le nouveau `serverName` de la production.
- [ ] OpenBao se connecte de nouveau aux bases (identifiants dynamiques de production prêts, autorité vérifiée).
- [ ] Les files `notifications` existent (type quorum) dans les deux vhosts ; un export des définitions a réussi sur le nouveau cluster.
- [ ] Toutes les Applications d'Argo CD sont `Synced` et `Healthy`, production comprise ; la comparaison de `donnees-apres.md` ne montre aucun écart.

**Vérification** : `lab/bin/check F1 11`

<details><summary>Indice 1</summary>

Lis la page *Recovery* de CloudNativePG et l'usage du plugin Barman Cloud : `externalClusters` décrit d'où l'on lit, `.spec.plugins` où l'on écrit. Que se passe-t-il si les deux visent le même `serverName` ? Un cluster qui reste dans l'état « Setting up primary » avec « Expected empty archive » dans ses journaux te protège : ne le contourne pas.
</details>

<details><summary>Indice 2</summary>

Sans `database` et `owner` dans `bootstrap.recovery`, l'opérateur crée une base `app` vide et le Secret `-app` la vise. Pour la production, la récupération se décrit en correctif de l'overlay (le component `dependances` sert aussi à `dev`) ; un correctif JSON6902 qui retire `initdb` et ajoute `recovery` est plus sûr qu'une fusion.
</details>

<details><summary>Indice 3</summary>

Chaque cluster CNPG génère sa propre autorité à sa création. Qui, hors du cluster, en avait gardé une copie ? Même question pour le secours : de quel préfixe de `s3://cnpg-k8s-par1/` lit-il ses WAL, et qu'y a-t-il d'écrit depuis la récupération ?
</details>

**Pour aller plus loin** (facultatif) : refais la récupération de la recette à un instant donné (`recoveryTarget.targetTime`) dans un cluster à part de `wb-essais`, juste avant le gel, et compare : c'est la preuve que la chaîne de WAL de l'ancien cluster est complète jusqu'au dernier segment.

---

### F1-S12 — Panne : la reconstruction coince  `BF` `★★★★`

> **Incident INC-5712** — *De : Nadia Roussel*
> *(Le détail s'affiche à l'injection.)* Le service vient de rouvrir et quelque chose ne va pas. Personne n'a touché à rien depuis la fin de ta reconstruction, m'assure-t-on.

**Objectifs pédagogiques**
- Diagnostiquer un incident typique des lendemains de reconstruction : un reste de l'ancien monde (confiance, propriété, objet restauré) qui se manifeste plus tard, ailleurs.
- Remonter de l'effet visible à la cause en traversant les frontières (cluster, coffre, DNS, admission).
- Corriger par le code et rendre la récidive détectable.

**Prérequis** : F1-S11 (`lab/bin/check F1 11` vert) ; modules 15, 25, 26.
**Durée indicative** : 45 min (temps cible), plus la rédaction.

**Injection** : `lab/bin/break F1 12` (3 variantes, depuis `adm01`, à la racine de ta copie du workbook).

**Règles de la panne**
- Le script vérifie d'abord que le lab est sain ; il refuse sinon. Il tire une variante, la pose, **constate son effet** (jusqu'à 6 minutes) et n'affiche que le symptôme. Si une variante ne peut pas s'appliquer à ton lab, il en essaie une autre ; si l'effet n'est pas constaté, il remet tout en état et le dit.
- Prérequis sur `adm01` : `kubectl` avec un kubeconfig d'administration (`WB_K8S_ADMIN_KUBECONFIG`, par défaut `~/.kube/config` connecté), une session OpenBao portant `plateforme-admin` et valable au moins 20 minutes (`bao login -method=oidc`, ou `BAO_TOKEN`), le fichier `~/.config/workbook/powerdns-api.env` (M06-E14), `jq`, `yq`, `dig`, `openssl`.
- Ne lis pas `corrige/pannes/`, ni `~/.local/state/workbook/F1-S12/`.
- `lab/bin/break F1 12 --annuler` remet l'état sain (filet, pas correctif). Quand tu as réparé, lance-le aussi pour **clore** la panne : il ne défait jamais ta réparation.
- La panne n'agit que sur : la configuration de la méthode `k8s-par1` d'OpenBao, des enregistrements de la zone `apps.par1.medisphere.internal`, un objet d'admission du cluster et un pod de `mediagenda-recette`. Elle n'écrit rien dans la production, ne touche ni `kms01` ni aucune donnée. Mais une plateforme est un tout : si tu n'as pas de piste au bout de **30 minutes**, lance `--annuler` (des secrets de production pourraient ne plus se renouveler) et reprends le diagnostic à froid avec une nouvelle injection.

**Travail demandé**
1. Ouvre un journal de diagnostic `docs/day0/journal/AAAA-MM-JJ-INC-5712.md` : heure, hypothèse, commande, résultat, conclusion.
2. Trouve la cause racine, puis l'**origine** : qu'est-ce qui, dans la reconstruction ou après, a pu produire cet état ? Qui l'a fait (traces d'audit) ?
3. Corrige par le chemin normal (code, pipeline) ; si un geste direct est nécessaire pour rétablir le service vite, refais-le ensuite par le code.
4. Prévention : un contrôle (alerte, job planifié, test) qui aurait vu la panne avant l'utilisateur, ou une étape ajoutée à la procédure de reconstruction.
5. Post-mortem sans recherche de coupable `docs/day0/post-mortems/INC-5712.md` (chronologie, impact, cause, détection, actions datées).

**Critères de réussite**
- [ ] Le service est rétabli (ExternalSecrets prêts, noms `*.apps` justes, pods qui se créent dans tous les espaces) et la panne est close (`--annuler` lancé après réparation).
- [ ] L'autorité de `auth/k8s-par1/config` est celle du cluster ; chaque nom publié par ExternalDNS pointe vers `gw-par1` ; aucun webhook d'admission ne vise un service inexistant.
- [ ] Journal et post-mortem INC-5712 publiés, avec au moins une action de prévention.

**Vérification** : `lab/bin/check F1 12`

<details><summary>Indice 1</summary>

Commence par délimiter : un seul espace, une seule application, un seul nom, ou tout ? Depuis quand ? Les statuts des objets (`ExternalSecret`, `ReplicaSet`, événements de l'espace) et le DNS **faisant autorité** (`dig @10.10.20.10 -p 5300`) disent souvent la cause mot pour mot.
</details>

<details><summary>Indice 2</summary>

Trois familles de restes de l'ancien monde : une **confiance** (autorité, clé) qui pointe encore vers l'ancien cluster ; une **propriété** (qui a le droit de modifier tel enregistrement) attribuée à un autre que `k8s-par1` ; un **objet** ramené tel quel d'une sauvegarde et qui vise quelque chose qui n'existe plus. Les étiquettes et les gestionnaires de champs (`managedFields`) d'un objet disent d'où il vient.
</details>

<details><summary>Indice 3</summary>

ExternalDNS ne modifie jamais un enregistrement dont l'enregistrement TXT de propriété désigne un autre propriétaire : c'est sa protection contre un autre cluster. OpenBao ne réécrit jamais seul sa configuration. Un webhook en `failurePolicy: Fail` dont le service n'existe pas refuse tout ce qu'il intercepte, en silence pour ceux qui ne regardent que les pods.
</details>

**Pour aller plus loin** (facultatif) : ajoute à `ms-verif-services` (M06-E29) ou à une règle Prometheus le contrôle de chacune des trois familles : autorité d'OpenBao contre `kube-root-ca.crt`, propriétaire des TXT de la zone `apps`, services visés par les webhooks.
