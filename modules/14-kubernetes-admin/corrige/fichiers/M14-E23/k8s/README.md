# plateforme/k8s — le cluster k8s-par1 décrit par le code

Projet de l'équipe Plateforme (M14). Les VMs sont dans `plateforme/infra` (`envs/k8s`), la
préparation des nœuds et kubeadm dans `plateforme/ansible` (rôles `containerd`, `k8s_noeud`,
`k8s_plan_controle`, `k8s_travailleur`, playbooks `k8s-noeuds.yml` et `k8s-cluster.yml`). Ici : ce
que l'on applique **au cluster**. Les manifestes des applications sont chez les équipes
(`mediagenda/api`, dossier `k8s/`).

| Dossier / fichier | Contenu | Exercice |
|---|---|---|
| `cluster/kubeadm-config.yaml` | ClusterConfiguration, KubeletConfiguration, KubeProxyConfiguration (v1beta4) | M14-E04 |
| `cluster/noeuds.yaml` | étiquettes (zones `par1-baie-a/b/c`, `medisphere.internal/dedie`) et taints MédiSphère des nœuds | M14-E14 |
| `composants/<nom>/` | values des composants : `cilium/` (CLI cilium), `metrics-server/` (chart 3.14.0) | M14-E05, E20 |
| `espaces/` | espaces du workbook (`wb-*.yaml`) et des équipes (`<espace>/` : espace, quota, LimitRange, comptes de service) | M14-E06, E10, E13, E18, E19 |
| `rbac/` | rôles agrégés MédiSphère, liaisons par groupe, `wb-checks` | M14-E06, E11 |
| `admission/` | ValidatingAdmissionPolicy `medisphere-images` et ses paramètres | M14-E18 |
| `ordonnancement/` | PriorityClasses | M14-E14 |
| `outils/` | `kubeconfig-personnel.sh`, `kubeconfig-checks.sh`, `kubeconfig-csr.sh`, `secret-tirage.sh`, `secret-mediagenda.sh`, `etiqueter-noeuds.sh`, `derive.sh`, `verifier-cluster.sh` | M14-E06 à E23 |
| `secrets/` | bris de glace **chiffrés** (Vault `critique`) : `admin.conf`, `super-admin.conf` | M14-E04 |

Règles :
- toute modification passe par une MR relue (CI : yamllint, kubeconform pour la version du cluster,
  shellcheck) ; on applique depuis `main` à jour, depuis `adm01` : `task diff`, puis `task appliquer`
  (GitOps au M20) ;
- le contexte kubectl est toujours explicite (`--context k8s-par1`) ; les objets sont appliqués en
  *server-side apply* avec le gestionnaire `plateforme-k8s` : le dépôt fait foi (`--force-conflicts`) ;
- aucun secret en clair (`.gitignore`) : les Secrets (`harbor-pull`, `mediagenda-db`) sont **créés**
  par les outils, jamais versionnés ;
- outils requis sur `adm01` : kubectl 1.36, helm 4.3, cilium, task, yq 4, jq, yamllint, kubeconform 0.8, shellcheck.

## Reconstruire le cluster depuis zéro

Prérequis : socle sain (DNS, step-ca, Harbor et ses caches, NetBox), bordure (flux VLAN 40), secrets
disponibles (Vault `lab` et `critique`, `~/.config/workbook/harbor-k8s-pull.env`).

| # | Étape | Commande (depuis `adm01`) | Contrôle |
|---|---|---|---|
| 1 | VMs | `plateforme/infra` : pipeline de `envs/k8s` (ou `tofu apply` dans `envs/k8s`) | `qm list` sur `pve01` : 2141-2146 ; NetBox ; DNS |
| 2 | Nœuds et cluster | `task noeuds -- -e k8s_plan_controle_amorcage_auto=true` (amorçage de `k8s-cp01`, jonctions) | `kubectl get nodes` : 6 nœuds (NotReady sans CNI) |
| 3 | Réseau des pods | `task cilium` | `cilium status` ; nœuds `Ready` |
| 4 | Objets de plateforme | `task appliquer` (espaces, RBAC, admission, priorités, puis `task etiquettes`) | `task diff` vide |
| 5 | Composants | `task metrics-server` | `kubectl top node` |
| 6 | Accès | `outils/kubeconfig-personnel.sh`, `outils/kubeconfig-checks.sh` | `lab/bin/check 14 06` |
| 7 | Secrets d'exploitation | `outils/secret-tirage.sh mediagenda-dev mediagenda-recette`, `outils/secret-mediagenda.sh <espace>` | `kubectl get sa mediagenda-api -n mediagenda-dev -o yaml` |
| 8 | Vérification | `task verifier` | « Cluster conforme au dépôt. » |
| 9 | Applications | dépôts des équipes (`mediagenda/api` : Job de migration, puis `kubectl apply -f k8s/<env>/`) | `/pret` |

Reconstruire **un** travailleur : `docs/kubernetes/reconstruction.md` de `plateforme/medisphere`.
Point d'accès : `https://k8s-api.par1.medisphere.internal:8443` (VIP 10.10.40.200). Documentation
d'exploitation : `docs/kubernetes/` de `plateforme/medisphere`.
