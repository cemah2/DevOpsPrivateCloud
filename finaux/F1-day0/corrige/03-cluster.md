# Final F1 — Phase 3 : Le cluster — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les scénarios de cette phase sont des `LIBRE` : ce corrigé donne **une solution de référence** (il y en a d'autres), éprouvée sur le papier contre les fichiers des modules 14 à 29, avec ses scripts d'orchestration. Les fichiers sont dans [`fichiers/`](fichiers/), un dossier par scénario, sous la forme d'un **extrait des projets** : `…/k8s/…` = `plateforme/k8s`, `…/ansible/…` = `plateforme/ansible`, `…/secrets/…` = `plateforme/secrets`, `…/gitops/…` = `plateforme/gitops`, `…/deploiement/…` = `mediagenda/deploiement`, `…/medisphere/…` = la documentation. Les scripts `outils/day0/*.sh` vont **tous** dans `plateforme/k8s/outils/day0/` (ils partagent [`commun.sh`](fichiers/S07/k8s/outils/day0/commun.sh), rangé avec S07). Les `*.extrait*` sont à intégrer dans un fichier existant (emplacement en tête).

**Principe de la solution de référence.** Un script par phase, qui n'invente rien : il enchaîne les tâches, playbooks, releases et outils des modules, dans l'ordre que leurs dépendances imposent, horodate chaque étape dans `~/day0/chronologie.tsv` et note les gestes manuels. Ce sont ces scripts qui deviennent le cœur de RB-310 (S15). Tu peux tout faire à la main : les durées seront plus longues et les oublis plus probables, c'est précisément ce que le rapport doit montrer.

**Validé hors du lab** : `bash -n` et `shellcheck -x` de tous les scripts ; YAML des manifestes et du playbook (`yaml.safe_load`) ; filtres `jq` des outils et de la panne rejoués sur des échantillons ; extraction des noms d'une demande de certificat (`openssl req -text`) ; sémantique de `bootstrap.recovery` avec le plugin Barman Cloud et du contrôle « Expected empty archive » relue dans la documentation de CloudNativePG (page *Recovery*) et du plugin (*Usage*) ; paramètres de `POST auth/kubernetes/config` d'OpenBao (documentation de l'API : `issuer` et `disable_iss_validation` dépréciés) ; `rbd trash mv --expires-at` (documentation de Ceph Tentacle).

**Points non testés en conditions réelles** (signale tes retours) :
- l'enchaînement complet des scripts `outils/day0/` sur le lab (durées, attentes, ordre exact des releases de **ton** `releases/`) ;
- `tofu plan -replace` sur les ressources VM du module `vm-noeud` (adresse exacte de la ressource dans le module : le script la cherche par `tofu state list`) et `tofu plan -destroy -target='module.noeud["k8s-w03"]'` (le garde-fou du script refuse tout ce qui ne porte pas `"k8s-w03"` dans son adresse) ;
- la ré-inscription FreeIPA d'un hôte déjà connu (variable de **ton** rôle `freeipa_client` pour forcer la jonction ; à défaut, `ipa host-disable` de l'ancien hôte avant) ;
- les options `--method plugin --plugin-name` de `kubectl cnpg backup` 1.30 (vérifie `--help`) ;
- `argocd app sync --resource` avec les noms de **tes** objets de la base de production ;
- `openssl s_client -starttls postgres` depuis `vault01` (utilisé par le check de S11) ;
- le comportement d'ExternalDNS 0.23 devant un enregistrement possédé par un autre propriétaire (panne S12 v2 : le script constate l'effet sur 150 s et passe à une autre variante sinon).

---

### F1-S07 — Détruire et reconstruire les nœuds de `k8s-par1`

**Solution de référence**

Fichiers : [`commun.sh`](fichiers/S07/k8s/outils/day0/commun.sh), [`10-gel.sh`](fichiers/S07/k8s/outils/day0/10-gel.sh), [`20-noeuds.sh`](fichiers/S07/k8s/outils/day0/20-noeuds.sh), [`k8s-reconstruction.yml`](fichiers/S07/ansible/playbooks/k8s-reconstruction.yml), [`volumes-orphelins.sh`](fichiers/S07/k8s/outils/volumes-orphelins.sh), modèles [`chronologie.md`](fichiers/S07/medisphere/docs/day0/chronologie.md) et [`volumes-ancien-cluster.md`](fichiers/S07/medisphere/docs/day0/volumes-ancien-cluster.md).

*0. Avant la fenêtre (la veille).* Fusionne **avant** le gel les MR qui préparent la reconstruction, pour ne pas attendre une revue pendant la coupure : scripts `outils/day0/` et `amorcage.conf` (S08) dans `plateforme/k8s`, `k8s-reconstruction.yml` dans `plateforme/ansible`, et les **descriptions de récupération des bases** (S11) — elles ne servent qu'à la création d'un Cluster, elles sont sans effet sur les bases en service. Relis `retour-arriere.md` avec Nadia.

*1. Gel* (`10-gel.sh`, ≈ 30 à 60 min) :
```
admin@adm01:~/src/k8s$ outils/day0/10-gel.sh
```
- contrôle du filet par `lab/bin/check F1 4` (sauvegardes de moins de 24 h) ;
- **Argo CD arrêté** (contrôleurs d'applications et d'ApplicationSets à 0) : sans cela, l'auto-réparation de `mediagenda-recette` remettrait les réplicas que tu viens d'enlever. Geste manuel, noté : le cluster est détruit ensuite, rien à remettre ;
- Rollouts `mediagenda` à 0 en recette et en production (`kubectl scale rollout`, sous-ressource `scale` des Rollouts) : un HPA ne fait **rien** sur une cible à 0 réplique (condition `ScalingActive=False`, « scaling is disabled since the replica count of the target is zero ») ; `portail` à 0 ; CronJobs suspendus ;
- files vidées **par MédiNotif** (qui tourne encore) : on attend `messages == 0` sur les deux vhosts, on ne purge jamais ;
- compteurs du gel (`~/day0/compteurs-gel.txt`) et topologie des files (`~/day0/files-gel.tsv`), ajoutés à `reference-avant.md` (section « Gel ») avec l'écart à S04 expliqué (rendez-vous de la recette créés par les tests nocturnes, par exemple) ;
- `SELECT pg_switch_wal();` puis sauvegarde de base (méthode `plugin`) de chacune des trois bases, attente `completed` : c'est le **dernier point de reprise**, postérieur à la dernière écriture.

*2. Nœuds* (`20-noeuds.sh`, ≈ 3 à 5 h) :
```
admin@adm01:~/src/k8s$ outils/day0/20-noeuds.sh
```
- **point de non-retour** confirmé ;
- `tofu plan -replace=<adresse>` des **cinq ressources VM** des nœuds clonés (`k8s-cp01-03`, `k8s-w01`, `k8s-w02`) trouvées par `tofu state list` dans `envs/k8s`, avec un garde-fou : le plan ne doit rien supprimer d'autre que cinq `proxmox_virtual_environment_vm` (NetBox, DNS, réservations restent) ; `tofu apply` du plan enregistré. Un `tofu destroy` puis `apply` marcherait aussi, mais retirerait et recréerait les adresses NetBox et les enregistrements DNS (fenêtre où `k8s-cp01` ne se résout plus, NetBox qui change d'identifiants d'objets) ;
- `k8s-w03` change de **mode de création** (clone de `vm-noeud` → `usine.tf` de F1-S06). Comme l'écrit l'en-tête de `usine.tf`, jamais en une passe sur un nœud existant (même VMID, même adresse : « VM 2146 already exists »). D'abord un apply qui **retire** `module.noeud["k8s-w03"]` (`tofu plan -destroy -target='module.noeud["k8s-w03"]'`, garde-fou : uniquement des suppressions d'objets de `k8s-w03` : VM 2146, VM NetBox, adresses, DNS), puis la procédure de `usine-k8s.md` §6 : MR `noeuds_usine = { "k8s-w03" = "installation" }` et apply (VM vide sur `vprov`, démarrage réseau), job `provisionner` de `plateforme/provisioning` (`EQUIPEMENT=k8s-w03` : installation par `pxe01`, profil `k8s-noeud`), MR `noeuds_usine = { "k8s-w03" = "service" }` et apply (modification **en place** : carte sur `vk8s`, carte de stockage, démarrage sur disque, adresse 10.10.40.63), puis `uv run outils/provisionner.py k8s-w03 --apres-bascule` (clé d'hôte confirmée par l'agent QEMU, NetBox `active`). Le script attend la fin de ces étapes et vérifie la phase `service` dans `tofu output noeuds_usine` ;
- **clés d'hôte SSH** : les VMs neuves ont des clés neuves, `~/.ssh/known_hosts` garde les anciennes (« REMOTE HOST IDENTIFICATION HAS CHANGED ») ; le certificat d'hôte signé par step-ca (M06-E19) n'est posé que plus tard. Geste manuel noté : `ssh-keygen -R` des noms, FQDN et adresses ; pour `k8s-w03`, la clé confirmée par l'agent QEMU (`~/.cache/provisionner/known_hosts-k8s-w03`) est reprise telle quelle ;
- **inscription FreeIPA nœud par nœud** (`inscription-ipa.yml --limit <nœud>`, garde-fous du M24) : les hôtes **existent déjà** dans l'annuaire avec la clé de l'ancienne VM ; une jonction forcée (variable de jonction forcée de ton rôle `freeipa_client`, `ipaclient_force_join` si ton rôle s'appuie sur le rôle `ipaclient` d'ansible-freeipa) ou une désactivation préalable de l'hôte (`ipa host-disable k8s-w01.par1.medisphere.internal`) est nécessaire ;
- `k8s-reconstruction.yml --limit k8s_par1 -e k8s_plan_controle_amorcage_auto=true` : nœuds (containerd, kubeadm), **durcissement** (vague 6, un nœud à la fois, avant kubeadm), **fichiers du serveur d'API** (audit, chiffrement, authentification structurée) **avant** l'amorçage — un kube-apiserver dont `--authentication-config` vise un fichier absent ne démarre pas —, VIP (keepalived + HAProxy), `kubeadm init` sur `k8s-cp01` seulement (premier du groupe, amorçage explicite), jonctions, instantanés etcd ;
- `admin.conf` du nouveau cluster copié en 600 dans `~/.kube/admin-k8s-par1.conf` (contexte renommé `k8s-par1`) : c'est l'identité de la reconstruction jusqu'à S09 ;
- compte `wb-checks` : seulement l'espace `wb-system` et les fichiers RBAC qui le concernent, puis `outils/kubeconfig-checks.sh` (M14-E06). **Pas** `task appliquer` (voir pièges).

*3. Score de conformité.* L'analyse hebdomadaire (`conformite-analyse.timer`, M26-E24) n'a pas encore tourné sur les nœuds neufs : `sudo systemctl start conformite-analyse.service` sur chacun publie le fichier du collecteur *textfile* que le check lit (et que le DaemonSet node-exporter de `kps` lira en S10).

*4. Volumes orphelins.* `outils/volumes-orphelins.sh lister` après S08 (il compare les images `csi-vol-*` du pool `k8s-rbd` aux PV du cluster **actuel**) ; décision écrite dans `volumes-ancien-cluster.md` : rien n'est supprimé avant la recette + 30 jours, puis corbeille RBD datée (`rbd trash mv --expires-at`, restaurable par `rbd trash restore`), purge par un geste séparé et tracé.

*5. Points de contrôle* : `curl -k https://10.10.40.200:8443/livez` → `ok` ; `kubectl --kubeconfig ~/.kube/admin-k8s-par1.conf get nodes` → six nœuds `NotReady` en v1.36.5 (pas encore de CNI) ; `lab/bin/check F1 7`.

**Explications**

- *Pourquoi un gel aussi strict ?* La reconstruction remet les bases par **rejeu d'archive** jusqu'au dernier WAL archivé. Toute écriture après le dernier segment archivé est perdue ; toute écriture entre la sauvegarde de S04 et la destruction n'est sauvée que si son WAL est archivé. `pg_switch_wal()` ferme le segment courant pour qu'il parte vers `s3-01` tout de suite (sinon, jusqu'à `archive_timeout`, 5 min chez CNPG). La sauvegarde de base **après** le gel raccourcit aussi le rejeu de S11.
- *Pourquoi vider les files plutôt que les exporter ?* L'export des définitions (CronJob `export-definitions`) ne contient **pas** les messages. Un message en file au moment de la destruction est perdu (RB-275 §4). Laisser le consommateur finir est la seule façon de n'en perdre aucun ; MédiAgenda ne publie plus rien puisqu'il est à l'arrêt.
- *Pourquoi `-replace` et pas `destroy` ?* Le module `vm-noeud` gère la VM et des objets annexes (adresse NetBox, enregistrement DNS selon ton module) : seule la VM doit mourir. `-replace` est aussi ce qu'a fait M14-E23 pour un travailleur. `k8s-w03` est l'exception : ses objets **changent de propriétaire** (de `module.noeud` à `usine.tf`), ils sont donc retirés puis recréés, en deux applies pour qu'OpenTofu ne crée jamais la nouvelle VM 2146 avant d'avoir détruit l'ancienne.
- *Ordre Ansible.* Les dépendances sont écrites dans les en-têtes des playbooks : fichiers de l'API avant toute (re)configuration du serveur d'API, VIP avant les jonctions, un nœud de contrôle à la fois (`serial: 1`, quorum etcd). Le durcissement **avant** kubeadm : ses exceptions pour les nœuds (sysctl, modules, swap, ports) sont éprouvées sur un nœud vide, pas découvertes sur un cluster en service.
- *Ce qui ne revient pas ici.* Supervision et journaux des nœuds sont des DaemonSets (node-exporter de `kps`, Alloy) : ils reviennent en S10. La carte VLAN 30 (`k8s-reseau-stockage.yml`) attend un nœud `Ready` : S08.

**Alternatives**

- *Restaurer etcd au lieu d'amorcer un cluster neuf* (RB-141) : plus rapide pour retrouver les objets, mais c'est l'inverse de la demande (on ramènerait l'ancien monde : autorité, comptes, objets hors code) et un instantané ne prouve pas que le code suffit.
- *Un second cluster à côté, puis bascule* (bleu/vert) : plus de continuité de service, impossible avec 128 Go de mémoire ; c'est la cible d'un vrai PRA (F5).
- *Garder `k8s-w03` en clone* (`DAY0_W03_SANS_USINE=oui`) : acceptable si l'usine tombe, à condition de l'écrire comme écart.
- *Laisser Argo CD tourner et passer par Git pour le gel* (réplicas à 0 dans les overlays) : plus « GitOps », mais le HPA, le `RespectIgnoreDifferences` et la production à synchronisation manuelle rendent l'effet moins sûr et plus long ; le gel est un geste d'exploitation encadré par la fiche de changement.

**Pièges classiques**
- Lancer `task appliquer` de `plateforme/k8s` sur le cluster neuf : il applique **tout** `espaces/`, y compris `espaces/mediagenda-recette/50-mediagenda-db.yaml` et `espaces/portail/50-portail-db.yaml`. Dès que la CRD de CNPG existe (S08), une base **vide** (`initdb`) naît à la place de la recette, et tente d'archiver sous l'ancien `serverName` (le plugin l'arrête : « Expected empty archive »). Avant S11, on n'applique que des sous-ensembles choisis.
- Détruire avant que la sauvegarde d'après le gel soit `completed` (ou avant que la file soit vide).
- `tofu destroy` « pour aller plus vite » : NetBox et le DNS perdent les nœuds pendant la reconstruction, l'inventaire `netbox-k8s.yml` ne voit plus rien, et les identifiants des objets NetBox changent.
- Poser `noeuds_usine = { "k8s-w03" = "installation" }` **avant** d'avoir retiré le clone : un seul apply qui détruit `module.noeud["k8s-w03"]` et crée les ressources de l'usine, sans ordre entre elles (« VM 2146 already exists », adresse en double dans NetBox).
- Garder l'ancien `admin.conf` : il ne vaut plus rien (autorité différente) ; un script qui l'utilise échoue en `x509`, parfois longtemps après.
- Oublier le compte `wb-checks` : tous les checks suivants échouent sur « l'API ne répond pas au compte des checks » alors que le cluster va bien.
- Supprimer les images RBD de l'ancien cluster pendant la fenêtre : le retour arrière par PBS en a besoin (les PV restaurés y renvoient).

**En production chez MédiSphère**

Une reconstruction réelle se répète en exercice (annuel, ADR-0310), avec un observateur qui chronomètre et note les gestes : c'est la seule façon d'obtenir les durées de référence que l'astreinte utilisera un jour de vrai sinistre. La fenêtre est annoncée par une page de maintenance servie par `lb01`/`lb02` plutôt qu'un service qui ne répond plus.

---

### F1-S08 — La couche de base et Argo CD

**Solution de référence**

Fichiers : [`30-couche-base.sh`](fichiers/S08/k8s/outils/day0/30-couche-base.sh), [`amorcer-secrets.sh`](fichiers/S08/k8s/outils/amorcer-secrets.sh) et sa liste [`amorcage.conf`](fichiers/S08/k8s/outils/amorcage.conf), [`approuver-csr-kubelet.sh`](fichiers/S08/k8s/outils/approuver-csr-kubelet.sh).

```
admin@adm01:~$ bao login -method=oidc                     # session OpenBao (SSO + OTP), pour l'amorçage
admin@adm01:~/src/k8s$ DAY0_KUBECONFIG=~/.kube/admin-k8s-par1.conf outils/day0/30-couche-base.sh
```

Ordre réel (et pourquoi) :

| # | Étape | Dépendance qui impose l'ordre |
|---|---|---|
| 1 | Espaces de noms **seuls** (`yq` sur `espaces/`, `kind: Namespace`) | Helmfile ne crée pas les espaces (`createNamespace: false`) ; `espaces/` contient aussi les bases CNPG (S07, pièges) |
| 2 | CRD Gateway API (`task reseau:crd-gateway-api`, empreintes vérifiées) | le contrôleur Gateway de Cilium ne démarre que si les CRD existent **à son démarrage** |
| 3 | Cilium (`helmfile -l composant=cilium apply`), `cilium status --wait` | aucun pod ne démarre sans CNI ; sans kube-proxy, Cilium joint l'API par la VIP (`k8sServiceHost` de ses valeurs) |
| 4 | Étiquettes et taints (`outils/etiqueter-noeuds.sh`), `task reseau:lb-bgp`, `task reseau:coredns` | les objets BGP sélectionnent les nœuds `bgp=par1` |
| 5 | **Secrets d'amorçage** (`outils/amorcer-secrets.sh appliquer`) | les releases suivantes attendent des Secrets que seul ESO sait livrer, et ESO viendra d'Argo CD |
| 6 | cert-manager, émetteurs, ExternalDNS (`helmfile -l groupe=certificats apply`), `task reseau:passerelles` | les CRD de cert-manager avant la ClusterIssuer ; `apps-joker` exige DNS-01 (TSIG) |
| 7 | Carte VLAN 30 des travailleurs (`k8s-reseau-stockage.yml --limit k8s_travailleurs`) | le rôle draine, redémarre et attend un nœud `Ready` |
| 8 | Contrôleur de snapshots (Kustomize), `helmfile -l groupe=stockage apply` | CRD de snapshots avant ceph-csi ; CNPG avant son plugin (`needs`) |
| 9 | CSR des kubelets (`outils/approuver-csr-kubelet.sh --approuver`), metrics-server | metrics-server lit les kubelets en TLS : il lui faut leurs certificats de service |
| 10 | `helmfile -l groupe=ci apply`, puis Argo CD | runners et agent attendent leurs jetons ; Argo CD ses identifiants de dépôts |
| 11 | Pare-feu d'hôte : `pare-feu-hote.sh audit` sur les six nœuds, politiques `composants/cilium/hote/`, observation, `applique` travailleurs puis nœuds de contrôle **un par un** | une politique d'hôte mal écrite coupe etcd ou le VRRP ; jamais deux membres etcd à la fois |

*L'amorçage des secrets.* La liste (`amorcage.conf`) est **courte et justifiée** : clés TSIG (cert-manager, ExternalDNS), identités ceph-csi et clé du chiffrement des volumes, identité S3 de Velero, jetons des runners et de l'agent, et deux identifiants d'Argo CD (`repo-creds-plateforme` pour lire `plateforme/gitops`, `depot-harbor-charts` pour les charts). Tout le reste attend ESO. L'outil lit OpenBao avec **ta** session OIDC (audit : `kv/data/plateforme/…` lu par `<MOI>`), construit le Secret par des tubes (`bao kv get -format=json | jq | kubectl apply -f -`) : aucune valeur sur une ligne de commande ni dans un fichier. Chaque Secret porte `medisphere.internal/amorcage=f1` ; S09 prouve qu'ils sont tous adoptés.

*Les certificats de kubelets.* Avec `serverTLSBootstrap: true` (M26-E25), chaque kubelet demande un certificat `kubernetes.io/kubelet-serving` que personne n'approuve tant que kubelet-csr-approver (Application d'Argo CD) n'est pas revenu. Symptômes : nœuds `Ready`, mais `kubectl logs`/`exec` échouent (« remote error: tls: internal error ») et metrics-server reste non prêt. L'outil refait à la main les contrôles de l'approbateur (demandeur `system:node:<nœud>` d'un des six nœuds, noms et adresses ⊂ nom court, FQDN, adresses du statut du nœud) et laisse en attente tout ce qui sort du cadre.

*Points de contrôle* : `kubectl get nodes` (six `Ready`) ; `cilium bgp peers` (douze sessions établies) ; `kubectl -n passerelles get gateway gw-par1` (`PROGRAMMED True`, 10.10.41.10) ; `curl -sI https://argocd.apps.par1.medisphere.internal` ; `lab/bin/check F1 8`.

**Explications**

Une couche de base a des dépendances qu'aucun outil ne voit en entier : Helmfile ordonne les releases **d'un même fichier** (`needs`), pas entre fichiers (commentaire de `50-ci.yaml.gotmpl` au M19) ; une release avec `rollbackOnFailure` attend des pods prêts, donc ses Secrets ; une CRD doit exister avant le contrôleur qui la surveille au démarrage. L'ordre des noms de fichiers (`10-`, `20-`…) est une **convention** ; la reconstruction est le seul test qui la valide. Chaque écart trouvé devient une MR (README, Taskfile ou ce script).

**Alternatives**

- *ESO d'abord, par Helmfile* (ADR-0310 option B) : après Cilium, installer ESO et le ClusterSecretStore depuis Helmfile, après avoir mis à jour la méthode `k8s-par1` d'OpenBao (S09 §1 avancé) : plus aucun Secret lu par une personne, sauf les identifiants d'Argo CD (eux aussi livrables par ESO à ce moment). Coût : ESO sort d'Argo CD.
- *Approbateur des kubelets dans Helmfile* plutôt qu'Argo CD : supprime le geste des CSR.
- *`kubeletConfiguration.serverTLSBootstrap` retiré le temps de la reconstruction* : refusé (Sophie) : c'est désactiver une sécurité pour aller plus vite.

**Pièges classiques**
- Installer Cilium avant les CRD Gateway API : tout semble marcher, mais `gw-par1` n'est jamais programmée ; il faut redémarrer l'opérateur de Cilium après coup.
- Lancer `helmfile apply` sans `-l` : les releases sans leurs Secrets échouent et la sortie mélange tout.
- Approuver toutes les CSR en attente d'un coup (`kubectl certificate approve $(kubectl get csr -o name)`) : c'est exactement ce que l'approbateur refuse de faire (une CSR forgée par un pod qui aurait volé l'identité d'un nœud, M26-E25).
- Étiqueter les nœuds pour le pare-feu d'hôte **après** avoir appliqué ses politiques sans passer par l'audit : application immédiate, etcd ou VRRP coupés si une règle manque.
- Créer l'application racine dans la foulée : Argo CD se lancerait dans la plateforme entière sans ESO ni secrets (S09 d'abord).

**En production chez MédiSphère**

Le script de la couche de base tourne aussi chaque trimestre sur un cluster jetable (CAPI ou `kind`, M18) pour vérifier que l'ordre écrit marche encore après les montées de version ; une couche de base qui ne se réinstalle plus est une dette invisible jusqu'au jour où l'on en a besoin.

---

### F1-S09 — Raccrocher l'identité et les secrets

**Solution de référence**

Fichiers : [`ca-k8s-par1.sh`](fichiers/S09/secrets/outils/ca-k8s-par1.sh), [`auth-k8s-par1.tf`](fichiers/S09/secrets/tofu/auth-k8s-par1.tf) (version F1), [`40-identite-secrets.sh`](fichiers/S09/k8s/outils/day0/40-identite-secrets.sh), job de contrôle [`.gitlab-ci.extrait-F1.yml`](fichiers/S09/secrets/.gitlab-ci.extrait-F1.yml) (prévention de S12).

```
admin@adm01:~/src/k8s$ DAY0_KUBECONFIG=~/.kube/admin-k8s-par1.conf outils/day0/40-identite-secrets.sh
```

1. **Confiance d'OpenBao.** La méthode `k8s-par1` vérifie le certificat de l'API (appel TokenReview) avec `kubernetes_ca_cert`, lu dans `racine/k8s-par1-ca.crt` de `plateforme/secrets` : c'est l'**ancienne** autorité. `outils/ca-k8s-par1.sh ecrire` lit la ConfigMap publique `kube-root-ca.crt` du nouveau cluster, **vérifie** qu'elle valide le certificat de `k8s-api.par1.medisphere.internal:8443` (poignée de main TLS), écrit le fichier ; MR « fix(k8s-par1): autorité du cluster reconstruit », pipeline, `tofu apply`. Rien d'autre ne change : pas de jeton de relecture dédié (choix du M25-E12 : OpenBao présente le jeton du client), donc aucun secret nouveau. Contrôle : `outils/ca-k8s-par1.sh verifier` (deux `OK`).
2. **ESO.** AppProject `plateforme` et Applications `external-secrets` et `secrets-plateforme` appliqués une fois (`kubectl apply --server-side` des fichiers de `plateforme/gitops`) : Argo CD lit le chart dans Harbor et le dépôt grâce aux deux identifiants d'amorçage. L'application racine les reprendra en S10 (mêmes noms). Le ClusterSecretStore `openbao` devient `Ready` (vague 1 de l'Application).
3. **Magasins applicatifs** : `espaces/*/80-openbao.yaml` (comptes `eso`, SecretStores) et `rbac/openbao-auth-delegator.yaml`, appliqués fichier par fichier (pas `task appliquer`).
4. **Adoption** : `outils/amorcer-secrets.sh verifier` jusqu'à ce que chaque Secret d'amorçage ait une `ownerReference` vers son ExternalSecret (`creationPolicy: Owner` adopte un Secret sans propriétaire, M25-E13), puis `nettoyer` (retrait de la marque). Contre-preuve :
   ```
   admin@adm01:~$ kubectl get secrets -A -l medisphere.internal/amorcage -o custom-columns=NS:.metadata.namespace,NOM:.metadata.name,PROPRIETAIRE:.metadata.ownerReferences[0].kind
   No resources found
   ```
5. **Personnes.** Le serveur d'API lit le même fichier d'authentification structurée (rôle `k8s_authentification`, posé en S07) : rien à refaire côté Keycloak. Ce qui manque : les **liaisons** (`kubectl apply --server-side -R -f rbac/` : `oidc-*`, ClusterRoles `medisphere-*`) et **ton kubeconfig**, dont l'autorité est l'ancienne (`kubectl config set-cluster <cluster> --certificate-authority=… --embed-certs`). `kubectl --context k8s-par1 auth whoami` → `oidc:<MOI>`, groupes `oidc:plateforme-admins`… À partir d'ici, plus d'`admin.conf` au quotidien.
6. **Bris de glace.** Nouvel `admin.conf` (et `super-admin.conf`, `/etc/kubernetes/super-admin.conf` de `k8s-cp01`) chiffrés dans le Vault `critique` à leur emplacement du M14 ; les anciens supprimés ; ligne de l'inventaire des secrets mise à jour (date, autorité). La copie locale `~/.kube/admin-k8s-par1.conf` est supprimée à la fin de la fenêtre.
7. **Kyverno et Harbor.** Rien à changer dans `exiger-signature-medisphere` : les clés publiques sont **dans** la politique (M26-E15), le robot de lecture vient d'ESO (`kv/plateforme/kyverno/harbor`). Les robots Harbor (`robot$k8s-pull`, `robot$medisphere+kyverno`) vivent dans Harbor, hors du cluster : vérifier seulement qu'ils ne sont pas expirés (`harbor_api robots`). La politique revient avec Argo CD (S10).

**Explications**

Tout ce qui, hors du cluster, porte l'**identité** de l'ancien cluster doit être retrouvé : l'autorité dans OpenBao, l'autorité dans les kubeconfigs (le tien, celui des checks, `admin.conf` du Vault), les jetons de comptes de service (morts avec lui : ESO se reconnecte avec des jetons neufs, rien à faire), les liaisons RBAC (objets du cluster : dans le code). À l'inverse, ce qui porte l'identité des **personnes** (Keycloak, FreeIPA) ne bouge pas. La règle de Sophie (« par le code ») protège d'un raccourci tentant : écrire l'autorité directement dans `auth/k8s-par1/config` marche tout de suite… et sera défait au prochain pipeline de `plateforme/secrets`, qui réappliquera l'ancienne.

Note sur l'émetteur : `issuer` et `disable_iss_validation` de la méthode `kubernetes` sont **dépréciés** dans OpenBao, et la validation de l'émetteur est désactivée par défaut ; un cluster kubeadm reconstruit garde de toute façon le même émetteur (`https://kubernetes.default.svc.cluster.local`). Seule l'autorité compte.

**Alternatives**

- `pem_keys` (clés publiques de signature des jetons) au lieu de TokenReview : OpenBao vérifie les jetons hors ligne, sans flux vers l'API ; mais un compte supprimé reste accepté jusqu'à l'expiration de son jeton, et les clés changent aussi à chaque reconstruction.
- Un jeton de relecture dédié (`token_reviewer_jwt`) : un secret de longue durée de plus à tourner, écarté au M25.

**Pièges classiques**
- « ESO ne marche pas » alors que c'est OpenBao qui refuse : lire les journaux d'OpenBao ou `bao write auth/k8s-par1/login` avec un jeton projeté (`kubectl create token eso -n wb-essais --audience openbao.medisphere.internal`) donne l'erreur `x509` en clair.
- Oublier `rbac/openbao-auth-delegator.yaml` : les SecretStores applicatifs restent `InvalidProviderConfig` (TokenReview refusé au compte `eso`).
- Désactiver la vérification TLS (`kubernetes_ca_cert` vide, ou `disable_local_ca_jwt: false` en espérant une CA « locale ») : OpenBao tourne hors du cluster, il n'a pas de CA locale.
- Laisser des Secrets d'amorçage orphelins : ils ne tourneront jamais (personne ne les met à jour) et l'inventaire ment.
- Garder une session `admin.conf` ouverte « au cas où » pendant toute la suite : les traces d'audit ne disent plus qui a fait quoi.

**En production chez MédiSphère**

Le job planifié `verifier-ca-k8s-par1` (prévention d'INC-5712) compare chaque nuit l'autorité du dépôt à celle de l'API et à celle d'OpenBao. L'inventaire des secrets distingue désormais une catégorie « identité du cluster » (autorité, `admin.conf`, `super-admin.conf`) avec la règle : « à refaire à chaque reconstruction, par telle procédure ».

---

### F1-S10 — Laisser Argo CD reconstruire la plateforme

**Solution de référence**

Fichiers : [`50-argocd.sh`](fichiers/S10/k8s/outils/day0/50-argocd.sh), [`etat-applications.sh`](fichiers/S10/gitops/outils/etat-applications.sh).

```
admin@adm01:~/src/k8s$ outils/day0/50-argocd.sh
admin@adm01:~/src/gitops$ ATTENTE="mediagenda-recette mediagenda-prod portail" watch -n 60 outils/etat-applications.sh
```

1. `kubectl apply --server-side -f racine/racine.yaml` : le seul objet créé à la main. La racine crée `projets`, `plateforme`, `applications` (et adopte les trois objets d'amorçage de S09, mêmes noms) ; `plateforme` crée une Application par service ; `applications` crée les ApplicationSets.
2. Suivi de la convergence : `etat-applications.sh` liste les Applications non saines avec la raison (condition d'erreur, message d'opération, première ressource en échec), triées par vague.
3. Blocages typiques sur un cluster vide et leur correction **par MR** :

| Blocage | Cause | Correction |
|---|---|---|
| `kube-prometheus-stack` : `ServiceMonitor`/`PrometheusRule` « no matches for kind » dans d'autres Applications | les CRD de l'opérateur arrivent avec `kps` | rien si la politique de réessai (`retry`) suffit ; sinon vague plus tardive (`argocd.argoproj.io/sync-wave`) pour les Applications consommatrices, ou `SkipDryRunOnMissingResource=true` sur leurs objets |
| ESO, Kyverno, Capsule, CNPG : « failed calling webhook » | le webhook existe mais son pod n'est pas prêt | attendre ; vagues : contrôleurs d'admission tôt (vague −1/0), consommateurs après |
| `politiques` (Kyverno) refuse des objets d'autres Applications | `ImageValidatingPolicy` en `Fail` sur `mediagenda-recette` : images non signées ? | les images sont signées (vérifier) ; ne jamais ajouter d'exception pour passer |
| `messagerie` (RabbitMQ) `Progressing` longtemps | trois nœuds, PVC neufs, formation du cluster Khepri | attendre ; `rabbitmq-topologie` après `rabbitmq` |
| `kubelet-csr-approver` arrive : CSR approuvées en rafale | normal | contrôler qu'aucune CSR ne reste en attente |
| `mediagenda-recette`, `portail` `Degraded` | pas de base (S11) | **attendu** ; surtout ne pas « réparer » en créant une base |

4. Vérifications d'ensemble : Prometheus (vue globale) répond **et** rend l'historique (`count(up offset 3d)`) : Thanos relit les blocs de `thanos-k8s-par1` (RGW), rien n'a été perdu de la supervision à long terme, seule la rétention locale de 15 jours des Prometheus est repartie de zéro ; Loki relit `loki-k8s-par1` ; Grafana, Alertmanager (alerte `Watchdog` revenue, le Prometheus témoin de `mon01` se tait : lever son silence) ; `lab/bin/check F1 10`.

**Explications**

C'est la récompense d'un an de discipline GitOps : une seule commande, et une plateforme de plusieurs dizaines d'Applications revient seule. Ce qui coince n'est jamais la description des objets, c'est l'**ordre** sur un cluster vide, que la vie quotidienne (où tout existe déjà) ne teste jamais : CRD fournies par une autre Application, webhooks pas encore prêts, Applications qui dépendent de données. Les vagues de synchronisation (`sync-wave`) ordonnent les objets **d'une** Application ; entre Applications, c'est l'App of Apps qui ordonne (vagues des Applications enfants) et la politique de réessai qui rattrape le reste.

**Alternatives**

- *ApplicationSet unique « plateforme »* à générateur de répertoires : moins de fichiers, mais un dossier ajouté par erreur devient un service déployé (refusé au M20 pour les applications, même raison).
- *Vagues explicites partout* : plus déterministe, plus verbeux ; à réserver aux dépendances réellement rencontrées pendant ce scénario (c'est ce que la correction par MR documente).

**Pièges classiques**
- Corriger un blocage par `kubectl apply` ou `kubectl edit` : Argo CD le défait (auto-réparation) ou, pire, ne le voit pas (objet hors de l'Application) et la prochaine reconstruction recassera.
- « Forcer » une synchronisation avec `Replace=true` ou supprimer une CRD pour la recréer : supprime tous les objets de ce type, Secrets possédés compris (ESO).
- Synchroniser `mediagenda-prod` « pour voir » : elle créerait la base de production… vide, si sa récupération n'est pas encore décrite (S11).
- Oublier de lever le silence posé sur l'Alertmanager témoin de `mon01` au début de la fenêtre.

**En production chez MédiSphère**

Le temps de convergence et la liste des blocages deviennent des indicateurs : la recette suivante (exercice annuel) doit converger plus vite et sans le même blocage ; chaque blocage corrigé est une ligne du rapport (S15).

---

### F1-S11 — Remettre les données

**Solution de référence**

Fichiers : [`day0-recuperation.yaml`](fichiers/S11/deploiement/overlays/prod/day0-recuperation.yaml) et [`kustomization.extrait-F1.yaml`](fichiers/S11/deploiement/overlays/prod/kustomization.extrait-F1.yaml) (production), extraits de la [recette](fichiers/S11/k8s/espaces/mediagenda-recette/50-mediagenda-db.extrait-F1.yaml), du [portail](fichiers/S11/k8s/espaces/portail/50-portail-db.extrait-F1.yaml) et du [secours](fichiers/S11/k8s/espaces/mediagenda-secours/50-mediagenda-db-secours.extrait-F1.yaml), [`60-donnees.sh`](fichiers/S11/k8s/outils/day0/60-donnees.sh), modèle [`donnees-apres.md`](fichiers/S11/medisphere/docs/day0/donnees-apres.md).

*1. Décrire la récupération (MR, préparées la veille, S07 §0).* Pour chaque base : `bootstrap.recovery` (source = un `externalClusters` du plugin Barman Cloud qui lit l'**ancien** `serverName`), `database` et `owner` explicites, et `.spec.plugins` qui archive sous un **nouveau** `serverName` :

| Base | Lit sous | Écrit sous | Où |
|---|---|---|---|
| `mediagenda-recette/mediagenda-db` | `mediagenda-db` | `mediagenda-db-day0` | `plateforme/k8s/espaces/mediagenda-recette/50-mediagenda-db.yaml` |
| `mediagenda-prod/mediagenda-db` | `mediagenda-db-prod` | `mediagenda-db-prod-day0` | `mediagenda/deploiement/overlays/prod/` (correctif JSON6902 : `remove /spec/bootstrap/initdb`, `add /spec/bootstrap/recovery`, `add /spec/externalClusters`) |
| `portail/portail-db` | `portail-db` | `portail-db-day0` | `plateforme/k8s/espaces/portail/50-portail-db.yaml` |
| `mediagenda-secours/mediagenda-db-secours` (réplica) | `mediagenda-db-prod-day0` | — | `plateforme/k8s/espaces/mediagenda-secours/50-mediagenda-db-secours.yaml` |

*2. Remettre* (`60-donnees.sh`, avec ton contexte OIDC et `argocd login … --sso`) :
```
admin@adm01:~/src/k8s$ outils/day0/60-donnees.sh
```
- recette et portail : `kubectl apply --server-side -f` de leurs fichiers (exception écrite du M27), attente de `Cluster in healthy state` (`kubectl cnpg status` montre la phase de récupération puis la promotion) ;
- production : **synchronisation sélective** de la base seule :
  ```
  admin@adm01:~$ argocd app sync mediagenda-prod --resource postgresql.cnpg.io:Cluster:mediagenda-db \
      --resource barmancloud.cnpg.io:ObjectStore:cnpg-s3 --resource external-secrets.io:ExternalSecret:cnpg-s3
  ```
  Une synchronisation complète lancerait aussi le Job de migrations (hook Sync, vague −1) et l'API **avant** que la base soit récupérée : échecs, réessais, et API ouverte au public pendant la récupération ;
- **comparaison avant réouverture** : `SELECT count(*) FROM rendez_vous` en prod et en recette contre `compteurs-gel.txt` ; un écart arrête tout (on cherche avec une récupération à un instant donné dans un cluster à part, RB-162, on ne rouvre pas) ;
- **autorités des bases pour OpenBao** : chaque cluster CNPG a généré une **nouvelle** autorité (`mediagenda-db-ca`) ; OpenBao se connecte en `sslmode=verify-ca` avec la copie de `/etc/openbao/postgresql/mediagenda-<env>-ca.crt` (M25-E14) : copie dans `plateforme/ansible/files/openbao/postgresql/`, MR, `coffre.yml` (seuls les fichiers changent, OpenBao les relit à chaque connexion). Le mot de passe du rôle `openbao` n'a pas changé : il est dans la base récupérée (`pg_authid`), tel que le dernier `rotate-root` l'avait laissé ;
- sauvegardes de base immédiates des trois bases (premières archives sous les nouveaux noms) ; ScheduledBackups revenus avec les fichiers ;
- secours : `60-cnpg-s3.yaml` puis le Cluster de secours, qui démarre de la sauvegarde de base de la **nouvelle** production et suit son archive ;
- messagerie : topologie (vhosts, files, types, arguments) identique à `files-gel.tsv` (le Topology Operator l'a recréée depuis `plateforme/donnees/topologie/`) ; export des définitions lancé depuis le CronJob ; l'export du gel sert de **comparaison** (RB-275 §4), pas de source : on ne réimporte que ce que Git ne décrit pas (rien, si M27 a été mené au bout) ;
- Valkey : repart vide, c'est un cache (dégradation de performance quelques minutes, pas de panne) ;
- **réouverture** : synchronisation complète de `mediagenda-prod` (`argocd app sync`, puis `app wait --health --sync`) ; heure notée, annoncée par Nadia : c'est la fin de la coupure.

*3. Velero en appoint.* Avec le nouveau Velero pointé sur le même compartiment, les sauvegardes d'avant apparaissent (`velero backup get`). Elles servent à récupérer **un objet** non déclaratif s'il en manque un (`velero restore create --from-backup <sauvegarde> --include-namespaces <espace> --include-resources <type> --selector …`) ; si rien ne manque, `donnees-apres.md` le dit.

*4. Points de contrôle* : `kubectl cnpg status mediagenda-db -n mediagenda-prod` (« Continuous Backup status » OK, `serverName` `mediagenda-db-prod-day0`) ; `bao read db-mediagenda/creds/mediagenda-api-prod` refusé à ta politique mais l'ExternalSecret de prod est `Ready` ; `lab/bin/check F1 11`.

**Explications**

- *Pourquoi un nouveau `serverName` ?* Le plugin refuse d'archiver dans un emplacement non vide (contrôle « Expected empty archive » : le cluster reste dans « Setting up primary »). Ce garde-fou protège l'historique de l'ancienne base : si la récupération devait être refaite (écart découvert plus tard), c'est cette archive-là qu'on relirait. Le contourner (`cnpg.io/skipEmptyWalArchiveCheck`) mélangerait deux lignées de WAL au même endroit ; la documentation parle de « perte de données grave ». Conséquence assumée : les anciens préfixes ne sont plus élagués par personne (la rétention est appliquée par le cluster qui écrit) ; leur sort suit celui des volumes RBD (S07).
- *Pourquoi le secours suit-il le nouveau nom ?* Il lit l'archive de la production ; en restant sur `mediagenda-db-prod`, il serait figé au gel pour toujours, sans alerte (rien de plus récent n'y arrive, l'alerte de retard ne compare qu'à ce qui est archivé).
- *`bootstrap` n'est lu qu'à la création* : le correctif de récupération peut rester dans Git ; il décrit désormais l'origine réelle de la base. L'enlever plus tard ne changerait rien au Cluster existant.
- *Autorités propres aux bases* : c'est la dépendance la plus cachée de la reconstruction (elle était notée au M25-E14 : « CloudNativePG renouvelle sa CA… la copie doit suivre »). Le « pour aller plus loin » du M25-E16 (certificat serveur de la base signé par la PKI de services) la supprimerait.

**Alternatives**

- *Restaurer les PVC par Velero (déplacement des données d'instantanés CSI)* : ramène des volumes d'avant le gel et des objets liés à l'ancien cluster ; CNPG ne les adopterait pas proprement. La récupération par l'archive est le chemin prévu par l'opérateur.
- *Promouvoir le secours en production* (RB-275) : possible si le secours avait survécu (il était dans le cluster détruit) ; il est ici recréé, pas promu.
- *Même `serverName` avec l'ancien préfixe renommé* (copie dans `s3-01`) : plus propre en apparence, mais une manipulation manuelle d'archive à l'endroit le plus sensible.

**Pièges classiques**
- Laisser `initdb` à côté de `recovery` (fusion stratégique d'une ressource personnalisée) : le webhook de CNPG refuse deux méthodes d'amorçage, ou pire selon l'ordre de rendu.
- Oublier `database`/`owner` : base `app` vide créée, Secret `mediagenda-db-app` qui la vise, API « saine » sur une base vide.
- Rouvrir avant de compter : des rendez-vous neufs rendent la comparaison impossible.
- Recréer le secours avant la première sauvegarde de base de la nouvelle production : il n'a rien pour démarrer (« no target backup found »).
- Réimporter l'export des définitions RabbitMQ par-dessus la topologie déclarative : deux sources pour les mêmes objets, et des utilisateurs sans mot de passe (l'export n'a pas les empreintes).

**En production chez MédiSphère**

La convention de `serverName` devient versionnée et écrite (ADR-0310 option D : suffixe de génération), la récupération de chaque base est testée chaque mois dans `wb-essais` (M16-E19) **avec** la vérification de l'autorité pour OpenBao, et le certificat serveur des bases passe par la PKI de services pour supprimer la copie d'autorité.

---

### F1-S12 — Panne : la reconstruction coince

**Démarche de diagnostic**

*Symptômes* (selon la variante tirée) : des Applications d'Argo CD passent `Degraded` une à une, un ExternalSecret « n'est plus mis à jour » (v1) ; le portail ne répond plus alors qu'Argo CD est vert (v2) ; en recette, un pod de l'API a disparu et ne revient pas, sans `Pending` ni `CrashLoop` (v3). Point commun : **rien n'a changé dans Git** ; c'est un reste de l'ancien monde ou un geste hors du code.

*Hypothèses* : (a) une **confiance** périmée (autorité, clé) ; (b) une **propriété** contestée (qui a le droit d'écrire un enregistrement) ; (c) un **objet** venu d'ailleurs (restauration, `kubectl` à la main) ; (d) un composant réellement en panne (OpenBao scellé, ExternalDNS arrêté, Kyverno indisponible).

*Commandes, dans l'ordre (de l'effet vers la cause)*

Variante 1 — ExternalSecrets en erreur :
```
admin@adm01:~$ kubectl get externalsecrets -A | grep -v True                       # lesquels, depuis quand
admin@adm01:~$ kubectl -n mediagenda-recette describe externalsecret harbor-pull | tail -5
  Warning  UpdateFailed  … could not get provider client: … error logging in: … Code: 403 / 500 …
admin@adm01:~$ kubectl get clustersecretstores,secretstores -A                     # magasins en erreur aussi
admin@adm01:~$ kubectl create token eso -n mediagenda-recette --audience openbao.medisphere.internal \
    | bao write auth/k8s-par1/login role=eso-mediagenda-recette jwt=-
  … x509: certificate signed by unknown authority                                  ← OpenBao ne vérifie plus l'API
admin@adm01:~$ bao read -field=kubernetes_ca_cert auth/k8s-par1/config | openssl x509 -noout -fingerprint -sha256
admin@adm01:~$ kubectl get cm kube-root-ca.crt -o jsonpath='{.data.ca\.crt}' | openssl x509 -noout -fingerprint -sha256
                                                                                   ← deux empreintes différentes
admin@adm01:~/src/secrets$ outils/ca-k8s-par1.sh verifier                          # le dépôt est juste, OpenBao non
```
(`jwt=-` lit le jeton sur l'entrée standard : il n'apparaît pas dans `ps`.) Origine : journal d'audit d'OpenBao (Loki, locataire `audit`) : `{service="openbao"} |= "auth/k8s-par1/config"` → écriture `update` par une identité (la tienne : c'est ta session qui a servi à injecter), hors du pipeline. Pourquoi les ExternalSecrets tombent « un à un » : ESO se connecte à OpenBao à chaque synchronisation ; chacun échoue à son prochain rafraîchissement (la panne force celui de `harbor-pull` en recette), au rythme des `refreshInterval`. Les Secrets déjà écrits restent, et les identifiants dynamiques déjà délivrés restent valides jusqu'à la fin de leur bail (1 h) : c'est ce qui rend l'incident urgent, car la production manquerait ensuite d'identifiants de base.

Variante 2 — le portail ne répond plus :
```
admin@adm01:~$ dig +short portail.apps.par1.medisphere.internal                     # 10.10.41.20 (pas la Gateway)
admin@adm01:~$ dig +short +norec -p 5300 @10.10.20.10 portail.apps.par1.medisphere.internal
admin@adm01:~$ kubectl -n portail get httproute -o yaml | yq '.items[].status.parents'   # route acceptée, Gateway OK
admin@adm01:~$ curl -s --resolve portail.apps.par1.medisphere.internal:443:10.10.41.10 -o /dev/null -w '%{http_code}\n' https://portail.apps.par1.medisphere.internal/
200                                                                                ← le service va bien, le nom non
admin@adm01:~$ kubectl -n external-dns logs deploy/external-dns | grep -i portail | tail -3
  … Skipping endpoint portail.apps.par1.medisphere.internal … because owner id does not match, found: "k8s-par1-essai", required: "k8s-par1"
admin@adm01:~$ dig +short -p 5300 @10.10.20.10 a-portail.apps.par1.medisphere.internal TXT
"heritage=external-dns,external-dns/owner=k8s-par1-essai,external-dns/resource=httproute/portail/portail"
```
(Le libellé exact du journal d'ExternalDNS est à lire sur ta version ; l'enregistrement de propriété est au nouveau format `a-<nom>` ou à l'ancien, au même nom.) Origine : journal de l'API de PowerDNS sur `dns01` (`journalctl -u pdns`), série de la zone ; aucun ExternalDNS ne porte `k8s-par1-essai` dans le cluster.

Variante 3 — un pod qui ne revient pas :
```
admin@adm01:~$ kubectl -n mediagenda-recette get rollout mediagenda                  # 2/3
admin@adm01:~$ kubectl -n mediagenda-recette get events --field-selector reason=FailedCreate
  … Error creating: Internal error occurred: failed calling webhook "validate.kyverno.svc-fail": … service "kyverno-svc-ancien" not found
admin@adm01:~$ kubectl get validatingwebhookconfigurations -o custom-columns=NOM:.metadata.name,SERVICE:.webhooks[*].clientConfig.service.name
admin@adm01:~$ kubectl get validatingwebhookconfiguration kyverno-resource-validating-webhook-cfg-restauree -o yaml | yq '.metadata.labels, .webhooks[].namespaceSelector'
  velero.io/restore-name: day0-complement-…                                        ← ramenée d'une sauvegarde Velero
admin@adm01:~$ kubectl get validatingwebhookconfiguration kyverno-resource-validating-webhook-cfg-restauree --show-managed-fields -o yaml | yq '.metadata.managedFields[].manager'
```
Le webhook n'est pas géré par Kyverno (pas d'étiquette `webhook.kyverno.io/managed-by`), n'appartient à aucune Application d'Argo CD, vise un Service qui n'existe pas, en `failurePolicy: Fail`, limité aux pods de `mediagenda-recette` : chaque création de pod y est refusée. Les pods existants tournent, d'où le symptôme « juste un pod qui manque ». Le gestionnaire de champs `velero-server` et les étiquettes de restauration désignent une restauration Velero ; le journal d'audit de l'API (Loki, locataire `audit`) montre l'identité qui a réellement créé l'objet.

*Cause racine, par variante*

| Variante | Cause | Correctif | Prévention |
|---|---|---|---|
| 1 | Autorité de l'**ancien** cluster réécrite dans `auth/k8s-par1/config` hors du pipeline ; plus aucune connexion de la méthode `k8s-par1` ne passe | relancer le pipeline de `plateforme/secrets` (le dépôt porte la bonne autorité) : `tofu apply` réécrit la configuration ; forcer une synchronisation des ExternalSecrets touchés (annotation `force-sync`) ou attendre leur rafraîchissement | job planifié `verifier-ca-k8s-par1` ([extrait](fichiers/S09/secrets/.gitlab-ci.extrait-F1.yml)) ; alerte Prometheus sur les ExternalSecrets non prêts depuis 10 min (métrique de statut d'ESO) ; écriture de `auth/*/config` réservée au rôle du pipeline (politique) |
| 2 | Enregistrement TXT de propriété de `portail.apps…` au nom de `k8s-par1-essai` et A vers 10.10.41.20 : ExternalDNS refuse de toucher un nom qui ne lui appartient pas | remettre la **propriété** à `k8s-par1` (enregistrement TXT réécrit ou supprimé avec l'enregistrement A, par l'API de PowerDNS ou `nsupdate` signé) : ExternalDNS republie lui-même l'adresse au tour suivant ; ne jamais changer `txtOwnerId` du cluster pour « reprendre » le nom | sonde : propriétaire des TXT de la zone `apps` = `k8s-par1` ; aucun autre ExternalDNS (essai, agence, futur cluster) n'écrit dans `apps` (domaine propre à chaque cluster, M15) |
| 3 | `ValidatingWebhookConfiguration` ramenée par une restauration Velero de l'ancien cluster, en `Fail`, vers un Service absent | supprimer l'objet (il n'est dans aucun dépôt) ; le ReplicaSet recrée le pod de lui-même | RB-310 : jamais de restauration Velero d'objets à portée de cluster (`--exclude-cluster-scoped-resources` ou `--include-cluster-resources=false`) ; contrôle « webhooks vers des Services inexistants » après toute restauration |

*Correctif commun et clôture* : rétablir, puis vérifier (`lab/bin/check F1 12`), puis `lab/bin/break F1 12 --annuler` pour clore (il ne défait pas ta réparation : il ne remet que l'état sauvegardé, identique au code). Journal et post-mortem : modèle [`INC-5712.md`](fichiers/S12/medisphere/docs/day0/post-mortems/INC-5712.md).

**Explications**

Après une reconstruction, le cluster est neuf mais son **environnement** ne l'est pas : coffre, DNS, sauvegardes, kubeconfigs gardent des traces de l'ancien. Chaque reste se manifeste plus tard et ailleurs (au rafraîchissement d'un secret, au prochain changement d'un nom, à la prochaine création de pod), ce qui rend le lien avec la reconstruction difficile à faire. Les protections qui « bloquent » (TLS d'OpenBao, propriété d'ExternalDNS, `failurePolicy: Fail`) font leur travail : la bonne réponse n'est jamais de les désactiver.

**Pièges classiques**
- v1 : écrire la bonne autorité directement dans OpenBao (ça marche, mais c'est encore un geste hors du code) ou, pire, vider `kubernetes_ca_cert`.
- v2 : changer `txtOwnerId` d'ExternalDNS en `k8s-par1-essai` « pour qu'il reprenne la main » : il abandonne alors **tous** les autres noms.
- v3 : passer le webhook en `Ignore` au lieu de le supprimer, ou redémarrer Kyverno (qui n'y est pour rien).
- Toutes : redémarrer des pods « pour voir » avant d'avoir lu les événements ; la cause est écrite dans les statuts.

**En production chez MédiSphère**

Les trois contrôles de prévention entrent dans `ms-verif-services` ou dans les règles Prometheus et passent dans la liste de RB-310 §7 (« après une reconstruction »). Le post-mortem est présenté en revue d'exploitation : c'est le type d'incident qu'un audit HDS aime voir traité.
