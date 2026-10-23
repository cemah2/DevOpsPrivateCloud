# RB-310 — Reconstruire `k8s-par1` depuis le code

| | |
|---|---|
| Quand | Le cluster est perdu ou n'est plus digne de confiance (compromission, corruption d'etcd sans instantané exploitable, montée de version ratée irréparable), **ou** exercice de reconstruction planifié |
| Quand NE PAS l'utiliser | Un nœud perdu : RB-140 (travailleur) ou RB-144 (nœud de contrôle) ; etcd abîmé avec un instantané récent : RB-141 ; base de production perdue seule : RB-275 (secours) ; retour à l'état d'avant une fenêtre ratée : restauration PBS des six VMs (`docs/day0/retour-arriere.md`) |
| Qui décide | Claire Morel (ou l'astreinte de direction), par écrit ; fiche CHG avec go/no-go ; Nadia prévient le support et les centres |
| Durées de référence (Day 0, <AAAA-MM-JJ>) | coupure <h:mm> ; gel <mm> min, nœuds <h:mm>, couche de base <h:mm>, identité <mm> min, Argo CD <mm> min, données <h:mm>. Au-delà de **1,5 ×** une durée de référence : ce n'est plus « long », c'est cassé — diagnostiquer |
| Outils | `plateforme/k8s/outils/day0/` (`10-gel.sh`, `20-noeuds.sh`, `30-couche-base.sh`, `40-identite-secrets.sh`, `50-argocd.sh`, `60-donnees.sh`), journal `~/day0/chronologie.tsv` |

## 0. Préalables vérifiables (go/no-go)

| Contrôle | Commande (sur `adm01`) | Attendu |
|---|---|---|
| Filet de moins de 24 h | `lab/bin/check F1 04` | vert (PBS `par1/k8s` des six VMs, etcd, Velero, CNPG, RabbitMQ, Argo CD) |
| Socle sain | `ms-verif-services`, `ms-verif-sauvegardes` | code 0 |
| Coffre ouvert, session | `bao status`, `bao token lookup` | `Sealed false` ; politique `plateforme-admin` |
| Dépôts à jour | `git -C ~/src/<projet> pull` pour infra, ansible, k8s, secrets, gitops, deploiement | `main` à jour, pipelines verts |
| Mémoire | `pvesh get /nodes/<NOEUD>/status` | ≥ 40 Go libres (+ 1 Go pour `pxe01`) |
| Retour arrière relu | `docs/day0/retour-arriere.md` | personne qui sait le faire présente |

## 1. Gel — `outils/day0/10-gel.sh` (référence <mm> min)

Arrête Argo CD, met l'API MédiAgenda (recette, prod) et le portail à 0, suspend les CronJobs, attend
que MédiNotif vide les files, relève les compteurs, force l'archivage du WAL courant et prend une
sauvegarde de base des trois bases **après** le gel.
**Point de contrôle** : `~/day0/compteurs-gel.txt` rempli ; trois `Backup` `completed` nommés `…-gel-…` ;
`profondeur` 0 et 0. **Si une file ne se vide pas** : MédiNotif en panne → RB-277 ; ne pas détruire.

## 2. Nœuds — `outils/day0/20-noeuds.sh` (référence <h:mm>) — ⚠️ POINT DE NON-RETOUR

1. `tofu plan -replace` des six ressources VM de `envs/k8s` : **le plan ne doit supprimer que six
   `proxmox_virtual_environment_vm`** (garde-fou du script) ; `apply`.
2. `k8s-w03` par l'usine : VM vide en démarrage réseau (VLAN 60), installation par `pxe01` (profil
   `k8s-noeud`), passage sur le VLAN 40 (procédure de F1-S06). Repli si l'usine est indisponible :
   `DAY0_W03_SANS_USINE=oui` (clone, écart noté).
3. Anciennes clés d'hôte retirées de `~/.ssh/known_hosts` ; SSH des six nœuds.
4. `inscription-ipa.yml --limit <nœud>` un par un (ré-inscription forcée : l'hôte existe dans l'annuaire).
5. `k8s-reconstruction.yml --limit k8s_par1 -e k8s_plan_controle_amorcage_auto=true` : nœuds,
   durcissement (vague 6), fichiers de l'API (audit, chiffrement, OIDC), VIP, `kubeadm init` sur
   `k8s-cp01`, jonctions, instantanés etcd.
6. `admin.conf` du nouveau cluster (`~/.kube/admin-k8s-par1.conf`, 600) ; `wb-checks` recréé.

**Points de contrôle** : `curl -k https://10.10.40.200:8443/livez` → `ok` ; un seul nœud porte
10.10.40.200 ; `kubectl get nodes` : six nœuds `NotReady` (pas de CNI), version 1.36 ;
`lab/bin/check F1 07`.

## 3. Couche de base — `outils/day0/30-couche-base.sh` (référence <h:mm>)

Ordre : espaces de noms **seuls** → CRD Gateway API → Cilium → étiquettes et taints → LB IPAM, BGP,
CoreDNS → **Secrets d'amorçage** (`outils/amorcer-secrets.sh appliquer`, session OIDC d'OpenBao) →
cert-manager, émetteurs, ExternalDNS, `gw-par1` → carte VLAN 30 des travailleurs → snapshots,
ceph-csi, CNPG + plugin, Velero → CSR des kubelets (`outils/approuver-csr-kubelet.sh --approuver`) et
metrics-server → CI → Argo CD → pare-feu d'hôte nœud par nœud (audit, observation, application ;
nœuds de contrôle un par un).

⚠️ **Jamais `task appliquer` pendant la reconstruction** : `espaces/` contient les bases CNPG, qui
naîtraient vides (`initdb`) avant leur récupération.
**Points de contrôle** : six nœuds `Ready` ; `cilium bgp peers` : 12 sessions établies ;
`kubectl -n passerelles get gateway gw-par1` `PROGRAMMED True` ; `kubectl get apiservice
v1beta1.metrics.k8s.io` `True` ; `lab/bin/check F1 08`.

## 4. Identité et secrets — `outils/day0/40-identite-secrets.sh` (référence <mm> min)

1. `plateforme/secrets` : `outils/ca-k8s-par1.sh ecrire` (autorité du nouveau cluster, contrôlée par
   TLS), MR, pipeline. **Jamais** d'écriture directe dans `auth/k8s-par1/config`.
2. AppProject `plateforme`, Applications `external-secrets` et `secrets-plateforme` appliqués une fois.
3. SecretStores applicatifs (`espaces/*/80-openbao.yaml`), `rbac/openbao-auth-delegator.yaml`.
4. `outils/amorcer-secrets.sh verifier` → tout `adopte` ; `nettoyer`.
5. `rbac/` (liaisons `oidc-*`) ; ton kubeconfig : nouvelle autorité, `kubectl auth whoami` par OIDC.
6. Nouvel `admin.conf` (et `super-admin.conf`) dans le Vault `critique` ; inventaire des secrets.

**Points de contrôle** : `outils/ca-k8s-par1.sh verifier` → deux OK ; tous les ExternalSecrets
`Ready` ; `lab/bin/check F1 09`.

## 5. Plateforme par Argo CD — `outils/day0/50-argocd.sh` (référence <mm> min)

`kubectl apply --server-side -f racine/racine.yaml` (seul objet à la main), puis
`gitops/outils/etat-applications.sh` jusqu'à convergence. Attendues non saines : `mediagenda-recette`,
`mediagenda-prod`, `portail` (données). Tout blocage : MR, jamais `kubectl`.
**Points de contrôle** : `lab/bin/check F1 10` ; aucune CSR de kubelet en attente.

## 6. Données — `outils/day0/60-donnees.sh` (référence <h:mm>)

1. MR de récupération **avant** : `bootstrap.recovery` + `externalClusters` (lecture sous l'ancien
   `serverName`) + archivage sous un **nouveau** `serverName` (`-day0`) pour la recette
   (`espaces/mediagenda-recette/50-mediagenda-db.yaml`), le portail, la production
   (`overlays/prod/day0-recuperation.yaml`, JSON6902) et le secours (lit `mediagenda-db-prod-day0`).
2. Recette et portail appliqués, récupération.
3. Production : **synchronisation sélective** de la base (Cluster, ObjectStore, identifiants S3).
4. **Comparaison au gel avant réouverture** : écart ⇒ on ne rouvre pas (RB-162 : instant donné).
5. Autorités des nouvelles bases → `plateforme/ansible` `files/openbao/postgresql/`, `coffre.yml`.
6. Sauvegardes de base immédiates des trois bases ; secours recréé (après la sauvegarde de la prod).
7. Messagerie : topologie identique au gel, export des définitions.
8. Synchronisation complète de la production = **réouverture**, annoncée par Nadia.

**Points de contrôle** : `kubectl cnpg status` de chaque base (`Continuous Backup status` OK,
`serverName` nouveau) ; `lab/bin/check F1 11`.

## 7. Après

- Lendemain : `lab/bin/check F1 14` (recette), étiquette.
- J+30 : volumes RBD et préfixes d'archive de l'ancien cluster mis en corbeille / supprimés par geste
  daté (`docs/day0/volumes-ancien-cluster.md`, `outils/volumes-orphelins.sh`).
- Contrôles des restes de l'ancien monde (INC-5712) : `outils/ca-k8s-par1.sh verifier`, propriétaires
  TXT de la zone `apps`, services visés par les webhooks. **Jamais** de restauration Velero d'objets à
  portée de cluster.

## Retour arrière

- **Avant le point de non-retour (§2)** : annuler le gel : remettre Argo CD (contrôleurs à leur nombre
  de réplicas), l'API, le portail et les CronJobs ; vérifier `/pret` ; fermer la fenêtre.
- **Après** : `docs/day0/retour-arriere.md` : arrêt des VMs neuves, restauration PBS des six VMs
  (`par1/k8s`, sauvegardes du filet), démarrage nœuds de contrôle d'abord (un par un, quorum etcd),
  puis travailleurs ; `admin.conf` d'avant (Vault `critique`, ancienne version) ; vérifications de
  `retour-arriere.md`. ⚠️ Les bases restaurées par PBS sont celles **du filet** ; les écritures
  postérieures (aucune si le gel a tenu) seraient perdues.
