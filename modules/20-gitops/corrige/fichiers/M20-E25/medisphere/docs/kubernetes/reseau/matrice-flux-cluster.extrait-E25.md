<!-- docs/kubernetes/reseau/matrice-flux-cluster.md : section AJOUTÉE en M20-E25 (SEC-2125), complétée
     en M20-E26 (lyo-k3s01) et M20-E28 (sauvegarde). Politiques : plateforme/k8s,
     composants/reseau/politiques/argocd.yaml (et argocd-sauvegarde.yaml en E28). -->

## Argo CD (espace `argocd`)

Refus par défaut en entrée et en sortie de tout l'espace (`refus-par-defaut`) ; NetworkPolicy du chart désactivées.

| Source | Destination | Port | Chiffrement | Raison | Politique | Exercice |
|---|---|---|---|---|---|---|
| Gateway `gw-par1` (entité `ingress`) | `argocd-server` | TCP 8080 | TLS terminé à la Gateway, HTTP en clair ensuite | interface, API (CLI en grpc-web), webhooks GitLab | `argocd-server` | M20-E02, E25 |
| `argocd-server` | API du cluster | TCP 6443 | TLS | lecture et écriture des Applications, AppProjects | `argocd-server` | M20-E25 |
| `argocd-server`, `argocd-application-controller`, `argocd-applicationset-controller`, `argocd-notifications-controller` | `argocd-repo-server` | TCP 8081 | TLS (certificat auto-signé du repo-server) | génération des manifestes, métadonnées des commits | `argocd-repo-server` (entrée) et chaque source (sortie) | M20-E25 |
| `argocd-server`, `argocd-repo-server`, `argocd-application-controller` | `argocd-redis` | TCP 6379 | aucun (mot de passe `argocd-redis`) | cache | `argocd-redis` (entrée) et sources | M20-E25 |
| `argocd-repo-server` | `git01.par1.medisphere.internal` | TCP 443 | TLS (racine MédiSphère, `argocd-tls-certs-cm`) | dépôts Git (jetons de déploiement) | `argocd-repo-server` (`toFQDNs`) | M20-E06, E25 |
| `argocd-repo-server` | `registry.par1.medisphere.internal` (`reg01`) | TCP 443 | TLS | charts OCI du miroir | `argocd-repo-server` (`toFQDNs`) | M20-E13, E25 |
| `argocd-application-controller` | API du cluster | TCP 6443 | TLS | cache d'état, synchronisation | `argocd-application-controller` | M20-E25 |
| `argocd-application-controller` (adresse du nœud, `K8S_TRAV`) | `lyo-k3s01.par1.medisphere.internal` (10.10.99.61) | TCP 6443 | TLS (autorité de k3s dans le Secret de cluster) | cluster de l'agence LYO1 ; règle de bordure `K8S_TRAV` → 10.10.99.61:6443 | `argocd-application-controller` (`toFQDNs`) | M20-E26 |
| `argocd-applicationset-controller` | API du cluster | TCP 6443 | TLS | Applications générées | `argocd-applicationset-controller` | M20-E25 |
| `argocd-notifications-controller` | API du cluster | TCP 6443 | TLS | lecture des Applications, annotations | `argocd-notifications-controller` | M20-E25 |
| `argocd-notifications-controller` | `smtp.par1.medisphere.internal` (`mon01`) | TCP 25 | STARTTLS | courriels vers Mailpit | `argocd-notifications-controller` (`toFQDNs`) | M20-E19, E25 |
| Job `argocd-redis-secret-init` (crochet Helm) | API du cluster | TCP 6443 | TLS | crée le Secret `argocd-redis` avant installation et mise à jour | `argocd-redis-secret-init` | M20-E25 |
| tous les composants | `kube-dns` | UDP/TCP 53 | — | résolution (proxy DNS de Cilium) | chaque politique + `base-dns` (M15-E28) | M20-E25 |

**Ouvert volontairement, à traiter plus tard** : trafic Gateway → `argocd-server` en clair dans le cluster (TLS de bout en bout : `BackendTLSPolicy`, support Cilium à vérifier) ; Redis sans TLS ; métriques (ports 8082 à 8084, 9001) fermées jusqu'au M21, qui ouvrira l'entrée depuis Prometheus.
