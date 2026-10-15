# Module 14 — Palier 5 : Mini-projet — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

### M14-E46 — Mini-projet : Kubernetes MédiSphère v1

Il n'y a pas de solution unique : ce corrigé donne un **plan de travail** éprouvé, les points de contrôle de chaque étape, la préparation des démonstrations et la **grille de revue** avec laquelle Claire, Karim, Sophie, Nadia et Julien évaluent la livraison. Les fichiers de référence sont ceux des exercices du module ; les nouveaux sont le modèle de [`docs/kubernetes/architecture.md`](fichiers/M14-E46/medisphere/docs/kubernetes/architecture.md) et le pod de la boucle de Julien, [`boucle-recette.yaml`](fichiers/M14-E46/adm01/boucle-recette.yaml) (objet d'essai appliqué à la main dans `mediagenda-recette` le temps de la revue, rangé dans `~/m14/e46/` et non dans `plateforme/k8s`).

**Solution**

*Plan de travail recommandé* (dans cet ordre : on prouve d'abord, on nettoie ensuite, on documente à la fin)

1. **État des lieux** (1 h) : `lab/bin/check 14 46`, puis `lab/bin/check 14 43` (tout le palier 4 d'un coup) et les contrôles détaillés rouges. Inventaire des restes : `kubectl get nodes`, `kubectl get pods -A --field-selector=status.phase!=Running`, `kubectl get csr`, `kubectl get all,cm,secrets,rolebindings -n wb-essais`, `kubectl get nodes -o custom-columns=NOM:.metadata.name,TAINTS:.spec.taints[*].key`, `ls ~/.local/state/workbook/pannes-actives/`.
2. **Filet** (30 min) : instantané etcd à la demande (`outils/etcd-instantane.sh`, M14-E24) vérifié, sauvegarde PBS des six VMs réussie.
3. **Démonstration de Nadia, répétition** (1 h) : voir le tableau ci-dessous. Faite **avant** le nettoyage du plan de contrôle : si un nœud ne revient pas, l'instantané est frais et le temps ne manque pas.
4. **Retirer `k8s-w04`** s'il existe encore (M14-E17) : `kubectl drain k8s-w04 --ignore-daemonsets --delete-emptydir-data`, `kubectl delete node k8s-w04`, `kubeadm reset` sur le nœud, VM 2147 retirée de l'état OpenTofu `k8s` (`tofu plan` puis `apply` dans `plateforme/infra/envs/k8s/`), objets NetBox et enregistrement DNS retirés par le même code, inventaire Ansible propre.
5. **Converger le code** (2 à 3 h) : `task appliquer` dans `plateforme/k8s` et `kubectl diff` vide sur tout le dépôt ; `ansible-playbook <playbook des nœuds> --check --diff` vide sur les six nœuds (reporte les correctifs du palier 4 : `track_script`, `hosts.toml`, swap, chrony, CoreDNS) ; pipeline de `main` vert.
6. **Sécurité** (1 à 2 h) : liaisons `cluster-admin` (`kubectl get clusterrolebindings -o wide | grep cluster-admin`) limitées à `kubeadm:cluster-admins`, `system:masters` (implicite) et `medisphere:plateforme-admins` ; `kubeadm certs check-expiration` sur les trois nœuds de contrôle (renouvellement par RB-143 si moins de 30 jours) ; audit et chiffrement présents sur les trois kube-apiserver ; registre des secrets (emplacements de `admin.conf`, `super-admin.conf`, clés de chiffrement, identité `etcd-k8s`, jeton `robot$k8s-pull`, kubeconfig `wb-checks`).
7. **MédiAgenda en recette** (1 à 2 h) : manifestes de l'équipe appliqués dans `mediagenda-recette` (ceux de M14-E21 : image signée par étiquette `v*` ou digest, 3 réplicas, PDB `maxUnavailable: 1` avec `unhealthyPodEvictionPolicy: AlwaysAllow`, sondes `/sante` et `/pret`, demandes et limites, Job de migration), PostgreSQL et Valkey jetables, pod de boucle prêt.
8. **Restauration et reconstruction** (2 à 3 h) : test de restauration d'etcd selon RB-141 sur un environnement d'essai (ou une restauration réelle annoncée, si tu l'as déjà faite en M14-E24 et que tu la refais pour la livraison), chronométré ; reconstruction d'un travailleur depuis le code (M14-E23), chronométrée.
9. **Documentation et livraison** (3 h) : `architecture.md` (modèle fourni), ADR-0140, ADR-0141, RB-140 à RB-149, journal des pannes, post-mortem INC-4150, matrice des flux, inventaire NetBox ; MR, pipelines verts, étiquette `k8s-v1`.

*Démonstration de Nadia — arrêt du nœud de contrôle qui porte la VIP* (à répéter **avant** la revue)

| Étape | Action | Attendu |
|---|---|---|
| 1 | Julien : `kubectl -n mediagenda-recette logs -f boucle-recette` (une ligne par seconde : `/pret` du Service `mediagenda-api`, port 80) | `OK` en continu |
| 2 | `ssh k8s-cp0X 'ip -br -4 addr \| grep 10.10.40.200'` : repérer le porteur ; instantané etcd vérifié | — |
| 3 | `qm shutdown 214X` (arrêt propre) depuis `pve01` ; en parallèle, `while sleep 1; do date +%T; kubectl get --raw /livez; done` sur `adm01` | quelques secondes d'échec, puis `ok` (VIP basculée) |
| 4 | `kubectl get nodes` ; `etcdctl endpoint health` depuis un nœud restant | `k8s-cp0X` `NotReady` ; deux membres sains sur trois, quorum conservé |
| 5 | Boucle de Julien | aucune requête en échec : le trafic de pod à Service ne passe ni par l'API ni par la VIP |
| 6 | `qm start 214X` ; attendre | nœud `Ready`, membre etcd sain (même révision), VIP qui revient ou non selon la préemption de keepalived (à expliquer) |
| 7 | Bilan | temps de bascule de l'API, nombre de requêtes perdues (zéro attendu), ce qui a été visible (et ce qui ne l'a pas été) |

*Démonstration de Karim — reconstruire un travailleur* : drain de `k8s-w03` (PDB respectés), retrait (`kubectl delete node`, `kubeadm reset`), destruction et recréation de la VM 2146 par OpenTofu, préparation par les rôles, jonction (jeton de jonction à durée courte), taint `dedie=bdd` et zone remises par le code, `uncordon`. Durée mesurée, notée dans RB-140.

*Grille de revue* (ce que chaque relecteur regarde)

| Relecteur | Points | Attendu |
|---|---|---|
| Karim | `plateforme/k8s`, `plateforme/ansible`, `plateforme/infra` | MR lisibles, aucune configuration hors code, `diff` et `--check` vides, versions épinglées, reconstruction d'un travailleur réussie et mesurée |
| Sophie | identités, RBAC, admission, audit, chiffrement, secrets | aucun `cluster-admin` hors administration, `super-admin.conf` jamais sorti du coffre depuis E04, audit des Secrets en `Metadata`, chiffrement vérifié dans etcd, registre des secrets sans valeur |
| Nadia | HA, sauvegardes, runbooks | démonstration réussie, RTO et RPO d'etcd mesurés, RB-140 à RB-149 utilisables à 4 h du matin, alertes à créer listées pour le module 21 |
| Julien | recette | MédiAgenda déployable par l'équipe dans `mediagenda-recette` avec ses droits, sans ticket, boucle sans perte pendant la panne |
| Claire | ensemble | limites assumées et écrites (stockage jetable, un seul hyperviseur, kube-proxy encore présent), feuille de route des modules 15 à 21 |

**Explications**

Le contrôle global ne remplace pas les contrôles détaillés : il vérifie l'**état de livraison** (versions, absence de provisoire, preuves documentées) et revérifie les points qui cassent le plus souvent en silence (SAN des certificats, suivi keepalived, alarmes etcd, âge des sauvegardes). La démonstration de Nadia montre ce que la haute disponibilité couvre ; celle de Karim montre que le code suffit à refaire un nœud, ce qui rend tolérable tout ce qui n'est pas redondant au niveau d'un nœud.

**Alternatives**

Faire la démonstration avec un arrêt brutal (`qm stop`) plutôt qu'un arrêt propre : plus réaliste, mais le délai de bascule dépend alors de `advert_int` et des contrôles de keepalived, et etcd perd un membre sans le prévenir (c'est son rôle de le supporter). Les deux sont acceptables si l'écart est expliqué.

**Pièges classiques**
- Nettoyer le plan de contrôle (certificats, manifestes) avant la démonstration de Nadia, puis découvrir qu'un nœud ne revient pas sans instantané frais.
- Faire tourner la boucle de Julien par `kubectl port-forward` : la session passe par l'API et coupe à la bascule, ce qui fausse la démonstration.
- Oublier que les témoins `wb-pannes` utilisent une image MédiAgenda : supprimer l'étiquette de Harbor pendant le nettoyage casse leurs redémarrages (sans effet sur la livraison, mais sur le palier 4 si tu le rejoues).
- Poser l'étiquette `k8s-v1` avant que les pipelines de `main` soient verts.

**En production chez MédiSphère**

La livraison `k8s-v1` devient la référence des changements suivants (fiches de changement `CHG-15xx`) ; la feuille de route documentée (modules 15 à 21) fixe l'ordre : remplacement de kube-proxy et politiques réseau avant toute donnée réelle, stockage persistant avant toute base, GitOps avant d'ouvrir le cluster à d'autres équipes, alertes (module 21) avant la première astreinte réelle.
