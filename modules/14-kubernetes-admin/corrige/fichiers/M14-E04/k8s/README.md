# plateforme/k8s — le cluster k8s-par1 décrit par le code

Projet de l'équipe Plateforme (M14). Les VMs sont dans `plateforme/infra` (`envs/k8s`), la
préparation des nœuds et kubeadm dans `plateforme/ansible` (rôles `containerd`, `k8s_noeud`,
`k8s_plan_controle`, `k8s_travailleur`). Ici : ce que l'on applique **au cluster**.

| Dossier | Contenu | Exercice |
|---|---|---|
| `cluster/` | `kubeadm-config.yaml` : ClusterConfiguration, KubeletConfiguration, KubeProxyConfiguration (v1beta4) | M14-E04 |
| `composants/<nom>/` | values et manifestes des composants (`cilium/`, `metrics-server/`…) | M14-E05, E20… |
| `espaces/` | espaces de noms, quotas, LimitRanges | M14-E06, E10 |
| `rbac/` | ClusterRoles, liaisons, comptes de service (dont `wb-checks`) | M14-E06, E11 |
| `admission/` | politiques d'admission | M14-E18 |
| `outils/` | scripts (`kubeconfig-personnel.sh`, `kubeconfig-checks.sh`, `etcd-instantane.sh`…) | M14-E06, E24 |
| `secrets/` | bris de glace **chiffrés** (Vault `critique`) : `admin.conf`, `super-admin.conf` | M14-E04 |

Règles :
- toute modification passe par une MR relue ; on applique depuis `main` à jour, depuis `adm01` :
  `task diff`, puis `task appliquer` (GitOps au M20) ;
- le contexte kubectl est toujours explicite (`--context k8s-par1`) ;
- aucun secret en clair (`.gitignore`) ;
- `task --list` décrit le reste.

Point d'accès : `https://k8s-api.par1.medisphere.internal:8443` (VIP 10.10.40.200, keepalived VRID 140
+ HAProxy sur `k8s-cp01-03`). Documentation d'exploitation : `docs/kubernetes/` de `plateforme/medisphere`.
