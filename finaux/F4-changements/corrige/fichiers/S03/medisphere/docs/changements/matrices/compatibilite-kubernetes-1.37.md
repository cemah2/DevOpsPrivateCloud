# Matrice de compatibilité — Kubernetes 1.36 → 1.37 (`k8s-par1`)

| | |
|---|---|
| Changement | CHG-3403 (go/no-go), CHG-3404 (montée) |
| Relevé | 23/10/2026 (corrigé de référence du final F4) — **à refaire le jour de ta décision** |
| Règle | un composant compte comme compatible s'il **déclare** la mineure cible (page de compatibilité, matrice de tests, notes de version). Un silence n'est pas un oui : il est noté « non déclaré », et la décision dit comment on le traite |
| Inventaire | `kubectl get deploy,ds,sts -A -o jsonpath='{..image}' \| tr ' ' '\n' \| sort -u` ; `helmfile -e par1 list` (`plateforme/k8s`) ; Applications de `plateforme/gitops` |

Légende : **D** = déclare 1.37 · **N** = ne déclare pas 1.37 (silence ou matrice qui s'arrête avant) · **X** = exclut 1.37 · **—** = indépendant de la version de l'API (rien à déclarer) · « à relever » = non relevé dans ce corrigé, à lire à la source.

## 1. Couche de base (Helmfile, `plateforme/k8s`)

| Composant | Installé | Déclare | 1.37 au relevé | Bloquant ? | Source |
|---|---|---|---|---|---|
| Cilium (CNI, Gateway, BGP, WireGuard, pare-feu d'hôte) | 1.20.3 | 1.20 : Kubernetes 1.33 à 1.36 ; 1.21 (en développement) : 1.34 à 1.37 | **X** pour 1.20 | **oui** : le CNI porte tout le réseau des pods | https://docs.cilium.io/en/stable/network/kubernetes/compatibility/ et https://docs.cilium.io/en/latest/network/kubernetes/compatibility/ |
| containerd.io | 2.3.x | table « Kubernetes support » par version de containerd | à relever | oui si absent | https://containerd.io/releases/ |
| cert-manager | 1.21.x | tableau des versions prises en charge | à relever | non (montée possible avant) | https://cert-manager.io/docs/releases/ |
| ExternalDNS | 0.23.x | compatibilité dans le README | à relever | non | https://github.com/kubernetes-sigs/external-dns |
| ceph-csi (RBD, CephFS) + external-snapshotter | 3.18.1 / 8.6.0 | matrice de prise en charge du README | à relever | **oui** si exclu (stockage de toutes les données) | https://github.com/ceph/ceph-csi |
| CloudNativePG + plugin Barman Cloud | 1.30.1 / 0.15.1 | « Supported releases » : versions de Kubernetes testées par version | à relever | **oui** si exclu (bases de production) | https://cloudnative-pg.io/documentation/current/supported_releases/ |
| Velero + plugin AWS | 1.18.4 / 1.14.4 | matrice de compatibilité du README | à relever | non (sauvegarde : tester une restauration après) | https://github.com/vmware-tanzu/velero |
| metrics-server | 0.9.x | matrice du README | à relever | non (HPA dégradé) | https://github.com/kubernetes-sigs/metrics-server |
| Argo CD | 3.5.5 | 3.5 : Kubernetes 1.33 à 1.36 testés (PLAN §6) ; 3.6 annoncée le 03/11/2026 | **N** | oui pour la livraison (aucune synchronisation sûre) | https://argo-cd.readthedocs.io/en/stable/operator-manual/installation/ |
| GitLab Runner (exécuteur kubernetes) + agent GitLab | 19.5 | « supported Kubernetes versions » de l'agent | à relever | non (CI suspendue au pire) | https://docs.gitlab.com/user/clusters/agent/ |
| BuildKit (`buildkitd`) | — | — | — | non | — |

## 2. Composants sous Argo CD (`plateforme/gitops`)

| Composant | Installé | Déclare | 1.37 au relevé | Bloquant ? | Source |
|---|---|---|---|---|---|
| Argo Rollouts + plugin Gateway API | 1.10.x / 0.17.0 | notes de version | à relever | oui pour les déploiements canary | https://github.com/argoproj/argo-rollouts/releases |
| kube-prometheus-stack (prometheus-operator 0.94, kube-state-metrics 2.20) | chart 92.x | matrice de compatibilité de kube-prometheus / kube-state-metrics | à relever | non pour le service, **oui** pour la mesure (la sonde passe par Prometheus) | https://github.com/prometheus-operator/kube-prometheus et https://github.com/kubernetes/kube-state-metrics |
| Thanos, Grafana, Pyrra, Loki, Alloy, Tempo, Pyroscope | — | — (clients de l'API limités) | — | non | — |
| OpenTelemetry Operator | 0.161 | `docs/compatibility.md` | à relever | non | https://github.com/open-telemetry/opentelemetry-operator |
| Kyverno | 1.19.2 | matrice de compatibilité (versions de Kubernetes par version de Kyverno) | à relever | **oui** : webhooks d'admission à « Fail » | https://kyverno.io/docs/installation/ |
| Falco | 0.45 | pilote `modern_ebpf` : noyau, pas l'API | — | non | https://falco.org/docs/ |
| Tetragon | 1.7 | idem (noyau) | — | non | https://tetragon.io/docs/ |
| kubelet-csr-approver | 1.2.15 | notes de version | à relever | **oui** : sans lui, les kubelets montés n'ont plus de certificat de service | https://github.com/postfinance/kubelet-csr-approver |
| External Secrets Operator | 2.13 | page « Stability and support » (versions de Kubernetes par version d'ESO) | à relever | oui (Secrets des applications) | https://external-secrets.io/latest/introduction/stability-support/ |
| Reloader | 2.2 | — | — | non | https://github.com/stakater/Reloader |
| OAuth2 Proxy | 7.15.5 | — | — | non | — |
| KEDA | 2.21 | 2.21 : Kubernetes 1.34 à 1.36 (PLAN §6) | **N** | oui pour MédiNotif (mise à l'échelle) | https://keda.sh/docs/latest/operate/cluster/ |
| VPA | 1.7.1 | compatibilité du README | à relever | non (mode `Off`) | https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler |
| Capsule | 0.15 | exige ≥ 1.36.0 ; plafond à relever | à relever | **oui** : webhooks sur les espaces des locataires | https://github.com/projectcapsule/capsule/releases |
| RabbitMQ Cluster Operator / Messaging Topology Operator | 2.23 / 1.20 | notes de version | à relever | oui (messagerie de prod) | https://github.com/rabbitmq/cluster-operator/releases et https://github.com/rabbitmq/messaging-topology-operator/releases |
| Chaos Mesh | 2.8 | « compatibilité Kubernetes 1.36 à vérifier » dès le M29 | **N** | non (recette seulement) : désactivable | https://github.com/chaos-mesh/chaos-mesh |
| k6-operator | 1.7 | notes de version | à relever | non pour le service, **oui** pour la sonde | https://github.com/grafana/k6-operator/releases |
| Backstage (plugin Kubernetes) | 1.56 | client de l'API en lecture | — | non | https://backstage.io/docs/features/kubernetes/ |
| Gateway API (CRD canal standard) | v1.6.1 | versions de Kubernetes prises en charge par version de Gateway API | à relever | non (porté par Cilium) | https://gateway-api.sigs.k8s.io/ |

## 3. Outils et chaîne de validation

| Outil | Où | Ce qu'il faut | Source |
|---|---|---|---|
| kubectl, kubeadm, kubelet | `adm01`, nœuds | même mineure (kubectl ±1) ; dépôt `pkgs.k8s.io/core:/stable:/v1.37/deb/` | https://kubernetes.io/releases/version-skew-policy/ |
| kubelogin, k9s, cilium et hubble CLI | `adm01` | versions qui connaissent la cible | notes de version de chaque outil |
| Configuration kubeadm `v1beta4` | `plateforme/k8s/cluster/kubeadm-config.yaml` | `kubeadm config validate` avec le kubeadm cible | https://kubernetes.io/docs/reference/config-api/kubeadm-config.v1beta4/ |
| Schémas kubeconform (`schemas-crd`, M29) | `plateforme/k8s` | régénérés après la montée ; schémas des API natives de la nouvelle mineure | https://github.com/yannh/kubeconform |
| Image dorée des nœuds (Packer) | `plateforme/images` | noyau et paquets de la nouvelle mineure | — |

## 4. API dépréciées ou retirées

- Côté **serveur** (ce qui est réellement appelé) : la métrique `apiserver_requested_deprecated_apis` de l'API (Prometheus du M21), filtrée par `removed_release="1.37"` ; elle dit **qui** appelle une API dépréciée (étiquettes `group`, `version`, `resource`). C'est la source qui fait foi.
- Côté **dépôts** (ce qui le serait au prochain déploiement) : kubeconform `-strict` avec les schémas de la **cible** sur les rendus des dépôts (`plateforme/gitops`, `plateforme/k8s`, dépôts de déploiement) ; un outil comme `pluto` (FairwindsOps) détecte les `apiVersion` dépréciées dans des fichiers et des releases Helm (à évaluer : non installé au M29).
- Relevé du corrigé : aucune ressource du lab n'utilise une API retirée en 1.37 d'après la métrique (à refaire : un composant monté entre-temps peut en appeler une).

## 5. Lecture

Au relevé, **trois composants ne déclarent pas 1.37** (Cilium 1.20 l'exclut, Argo CD 3.5 et KEDA 2.21 s'arrêtent à 1.36) et plusieurs sont « à relever ». Cilium suffit à décider : on ne monte pas le plan de contrôle d'un cluster dont le CNI ne déclare pas la version. Décision : CHG-3403.
